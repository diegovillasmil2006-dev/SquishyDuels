--!strict
-- MatchRewards_Test: unit tests for ServerScriptService.Server.Logic.MatchRewards (Match HUD M2, 2026-10-16). Server
-- only (ServerStorage.UnitTest). Pure: every case passes its own Config.Economy copy (the duel's numbers spelled out)
-- and plain outcome tables shaped like MatchRules' outcome.
-- Contract (owner Q3 / Q4, matchhud2 PLAN v2 §4 M2 + §12): a match pays like a 1v1 duel with no hourly cap: FFA 1st
-- "win", the rest "loss"; TDM the winning team "win", the other "loss"; a draw "draw" (an FFA draw: only the tied
-- leaders draw, the others lose); paid with >= minOwnThrows own throws and >= winMinActiveSeconds (win) /
-- lossMinActiveSeconds (loss) of Active (nothing more for a draw); the pay = DuelRewards[result] squeezes (Coins AND
-- Grip), 0 when not paid; the win streak +1 for every win (paid or not: §12 Q4, review fix), 0 for a loss, a draw
-- and for leaving (left());
-- cancelled / void, a player not present and a bot get nil (nothing paid, the streak untouched); the 7th, 8th ... paid
-- match pays in full (no cap); streakOf / nextStreak keep a whole number >= 0; squeezeWorth = the pen's squeeze value
-- and own-squeeze Grip (PenMath, pens3 phase 1; a capsule counts for nothing); maxSqueezes = the largest duel reward.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local CFG = {
	Economy = {
		DuelRewards = {
			win = 600,
			loss = 180,
			draw = 300,
			minOwnThrows = 3,
			winMinActiveSeconds = 20,
			lossMinActiveSeconds = 45,
			samePairFullRewards = 6, -- never read by match pay (no cap)
			samePairWindowSeconds = 3600,
			samePairMultiplier = 0.25,
		},
	},
}

return function(t: Context)
	local expect = t.expect
	local MatchRewards = t.requireServer("Logic/MatchRewards")
	local PenMath = t.requireShared("PenMath")

	local function player(userId: number, overrides: { [string]: any }?): any
		local input: any = { userId = userId, team = nil, present = true, isBot = false, throws = 3 }
		for key, value in (overrides or {}) :: { [string]: any } do
			input[key] = value
		end
		return input
	end

	local function ffaWin(winner: number, activeSeconds: number): any
		return {
			kind = "win",
			reason = "koTarget",
			winnerUserId = winner,
			winners = { winner },
			activeSeconds = activeSeconds,
		}
	end

	t.test("FFA: 1st is a paid win (+1 streak), the others a paid loss (streak 0)", function()
		local outcome = ffaWin(1, 120)
		expect.deepEqual(
			MatchRewards.forPlayer(outcome, player(1), CFG),
			{ result = "win", eligible = true, squeezes = 600, streakUp = true }
		)
		expect.deepEqual(
			MatchRewards.forPlayer(outcome, player(2), CFG),
			{ result = "loss", eligible = true, squeezes = 180, streakUp = false }
		)
	end)

	t.test("TDM: the whole winning team wins, the other team loses", function()
		local outcome = {
			kind = "win",
			reason = "wiped",
			winnerTeam = "Red",
			winners = { 1, 3 },
			activeSeconds = 200,
		}
		for _, id in { 1, 3 } do
			local pay = MatchRewards.forPlayer(outcome, player(id, { team = "Red" }), CFG)
			expect.deepEqual(pay, { result = "win", eligible = true, squeezes = 600, streakUp = true })
		end
		local lost = MatchRewards.forPlayer(outcome, player(2, { team = "Blue" }), CFG)
		expect.deepEqual(lost, { result = "loss", eligible = true, squeezes = 180, streakUp = false })
	end)

	t.test("a draw pays the draw and resets the streak; in an FFA draw only the tied leaders draw", function()
		local tdm = { kind = "draw", reason = "overtimeTimeout", winners = {}, activeSeconds = 720 }
		expect.deepEqual(
			MatchRewards.forPlayer(tdm, player(1, { team = "Red" }), CFG),
			{ result = "draw", eligible = true, squeezes = 300, streakUp = false }
		)
		local wiped = { kind = "draw", reason = "wiped", winners = {}, activeSeconds = 10 }
		local both = MatchRewards.forPlayer(wiped, player(2, { team = "Blue" }), CFG)
		expect.deepEqual(both, { result = "draw", eligible = true, squeezes = 300, streakUp = false }) -- no Active minimum
		local ffa = { kind = "draw", reason = "overtimeTimeout", winners = { 1, 2 }, activeSeconds = 600 }
		expect.equal(MatchRewards.forPlayer(ffa, player(2), CFG).result, "draw")
		local behind = MatchRewards.forPlayer(ffa, player(3), CFG)
		expect.deepEqual(behind, { result = "loss", eligible = true, squeezes = 180, streakUp = false })
	end)

	t.test("cancelled, void, a player not present and a bot get nil: nothing paid, the streak untouched", function()
		local cancelled = { kind = "cancelled", reason = "notEnoughPlayers", winners = {}, activeSeconds = 0 }
		local void = { kind = "void", reason = "shutdown", winners = {}, activeSeconds = 300 }
		expect.equal(MatchRewards.forPlayer(cancelled, player(1), CFG), nil)
		expect.equal(MatchRewards.forPlayer(void, player(1), CFG), nil)
		expect.equal(MatchRewards.forPlayer(nil, player(1), CFG), nil)
		local outcome = ffaWin(1, 300)
		expect.equal(MatchRewards.forPlayer(outcome, player(1, { present = false }), CFG), nil) -- left / never arrived
		expect.equal(MatchRewards.forPlayer(outcome, player(1, { isBot = true }), CFG), nil)
	end)

	t.test("the duel's own rules: 3 own throws, 20 s of Active for a win, 45 s for a loss", function()
		local afk = MatchRewards.forPlayer(ffaWin(1, 300), player(1, { throws = 2 }), CFG)
		-- Review fix (owner §12 Q4): an unpaid win is still a win: no pay, but the streak +1.
		expect.deepEqual(afk, { result = "win", eligible = false, squeezes = 0, streakUp = true })
		expect.equal(MatchRewards.nextStreak(5, afk), 6)
		local quickWin = MatchRewards.forPlayer(ffaWin(1, 19.9), player(1), CFG)
		expect.equal(quickWin.eligible, false)
		expect.equal(quickWin.streakUp, true)
		expect.equal(MatchRewards.forPlayer(ffaWin(1, 20), player(1), CFG).eligible, true)
		local quickLoss = MatchRewards.forPlayer(ffaWin(1, 44.9), player(2), CFG)
		expect.deepEqual(quickLoss, { result = "loss", eligible = false, squeezes = 0, streakUp = false })
		expect.equal(MatchRewards.forPlayer(ffaWin(1, 45), player(2), CFG).squeezes, 180)
		local drawNoThrows = { kind = "draw", reason = "overtimeTimeout", winners = {}, activeSeconds = 720 }
		local idle = MatchRewards.forPlayer(drawNoThrows, player(1, { team = "Red", throws = 0 }), CFG)
		expect.deepEqual(idle, { result = "draw", eligible = false, squeezes = 0, streakUp = false })
		-- A missing or broken Active time or throw count pays nothing.
		local broken = MatchRewards.forPlayer({ kind = "win", winnerUserId = 1 }, player(1, { throws = 0 / 0 }), CFG)
		expect.equal(broken.eligible, false)
	end)

	t.test("no hourly limit: the same player's 7th, 8th and 20th paid match pay in full", function()
		for _ = 1, 20 do
			local pay = MatchRewards.forPlayer(ffaWin(1, 120), player(1), CFG)
			expect.equal(pay.squeezes, 600)
		end
	end)

	t.test("the amounts follow the config (the duel's numbers)", function()
		local tuned = { Economy = { DuelRewards = table.clone(CFG.Economy.DuelRewards) } }
		tuned.Economy.DuelRewards.win = 900
		tuned.Economy.DuelRewards.minOwnThrows = 5
		expect.equal(MatchRewards.forPlayer(ffaWin(1, 120), player(1, { throws = 5 }), tuned).squeezes, 900)
		expect.equal(MatchRewards.forPlayer(ffaWin(1, 120), player(1, { throws = 4 }), tuned).eligible, false)
		expect.equal(MatchRewards.maxSqueezes(CFG), 600)
		expect.equal(MatchRewards.maxSqueezes(tuned), 900)
	end)

	t.test("left(): nothing paid, the streak goes to 0", function()
		expect.deepEqual(MatchRewards.left(), { result = "left", eligible = false, squeezes = 0, streakUp = false })
		expect.equal(MatchRewards.nextStreak(7, MatchRewards.left()), 0)
	end)

	t.test("streakOf / nextStreak: a whole number >= 0; a win +1, anything else 0", function()
		expect.equal(MatchRewards.streakOf(4), 4)
		expect.equal(MatchRewards.streakOf(4.7), 4)
		for _, bad in { -1, 0 / 0, math.huge, -math.huge, "3", {} } :: { any } do
			expect.equal(MatchRewards.streakOf(bad), 0)
		end
		expect.equal(MatchRewards.streakOf(nil), 0) -- a profile without the stat
		expect.equal(MatchRewards.streakOf(2 ^ 60), 2 ^ 53)
		local win = MatchRewards.forPlayer(ffaWin(1, 120), player(1), CFG) :: any
		local loss = MatchRewards.forPlayer(ffaWin(1, 120), player(2), CFG) :: any
		expect.equal(MatchRewards.nextStreak(0, win), 1)
		expect.equal(MatchRewards.nextStreak(5, win), 6)
		expect.equal(MatchRewards.nextStreak(-3, win), 1) -- a broken saved streak counts as 0
		expect.equal(MatchRewards.nextStreak(2 ^ 53, win), 2 ^ 53) -- the counter cap
		expect.equal(MatchRewards.nextStreak(5, loss), 0)
	end)

	t.test("squeezeWorth: the pen's squeeze value and own-squeeze Grip, a new player's without a pen", function()
		local pen: any = {
			spots = 3,
			nextId = 3,
			items = {
				{ id = 1, kind = "kitty_bread", form = 0, level = 2, coat = 0, slot = 1, locked = false }, -- 11.5
				{ id = 2, kind = "butter", form = 0, level = 1, coat = 0, slot = 2, locked = false }, -- 40
			},
		}
		local capsules: any = { slots = 1, list = { { level = 40, squishyId = "dragon" } } } -- counts for nothing
		local coins, grip = MatchRewards.squeezeWorth({ pen = pen, capsules = capsules })
		expect.equal(coins, PenMath.squeezeValue(pen))
		expect.near(coins, 51.5, 1e-9)
		expect.equal(grip, 51) -- floored
		local newCoins, newGrip = MatchRewards.squeezeWorth(nil)
		expect.equal(newCoins, 10)
		expect.equal(newGrip, 10)
	end)
end
