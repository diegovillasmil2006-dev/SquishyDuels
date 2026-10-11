--!strict
-- DuelServiceRewards_Test: unit tests for the duel reward wiring of ServerScriptService.Server.Services.DuelService
-- (settleReward, eliminationsFor). Server only (ServerStorage.UnitTest). Edit mode: no match is started; ended
-- matches come from the real Logic/DuelRules and rewards from the real Logic/DuelRewards; EconomyService is either a
-- recorder or the real one on a fake data port (useDeps). Cases run in order: the first ones run before any profile
-- system is wired (setHooks), the later ones after.
-- Contract (DESIGN §2.8 DuelResult, §3.11, §6.7, §12 #14):
--   * DuelResult.coins is what EconomyService really paid; when it is 0 the blocked reason is shown (tooShort, ...);
--     duel.noRewardsOffline only once a profile system is wired (§0.3 #9); a same-pair reduction rides along;
--   * a reward without a duelLog entry asks EconomyService nothing; a matchId already paid pays 0 with no reason;
--   * through the real EconomyService a match pays once, however often it is settled (duelLog.matchId), and unpaid
--     results are recorded but never count toward the same-pair reduction (§6.7 "fully rewarded results");
--   * §12 #15 through the real EconomyService: seven alts in rotation (~105 results an hour, more than duelLog's 30
--     entries hold) are reduced from the 7th full result against the same alt inside the hour, for both players; an
--     hour after the first of those results the pair is paid in full again;
--   * eliminations: the winner of an elimination or sudden-death hit, and both players of a simultaneous final hit.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local T0 = 5000 -- server time (DuelRules)
local NOW_UNIX = 1_790_000_000 -- os.time() (duelLog)
local MATCH_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
local USER_A, USER_B = 301, 402

return function(t: Context)
	local expect = t.expect
	local DuelService = t.requireServer("Services/DuelService")
	local DuelRules = t.requireServer("Logic/DuelRules")
	local DuelRewards = t.requireServer("Logic/DuelRewards")
	local EconomyService = t.requireServer("Services/EconomyService")
	local Config = t.requireShared("Config")

	local function step(s: any, event: any, now: number): any
		local nextState = DuelRules.step(s, event, now)
		return nextState
	end

	-- A ended match: B forfeits `seconds` into Active after both made `throws` accepted throws (A wins when >= 20 s).
	-- B is USER_B unless `userB` is given.
	local function forfeitMatch(
		seconds: number,
		throws: number,
		rewardsEnabled: boolean,
		matchId: string?,
		userB: number?
	): any
		local s = DuelRules.new(matchId or MATCH_ID, {
			A = { userId = USER_A, rewardsEnabled = rewardsEnabled },
			B = { userId = userB or USER_B, rewardsEnabled = rewardsEnabled },
		}, T0, Config.Duel)
		s = step(s, { kind = "streamed", side = "A" }, T0 + 0.1)
		s = step(s, { kind = "streamed", side = "B" }, T0 + 0.2)
		s = step(s, { kind = "positioned", side = "A" }, T0 + 0.3)
		s = step(s, { kind = "positioned", side = "B" }, T0 + 0.4)
		local startAt = s.phaseEndsAt
		s = step(s, { kind = "tick" }, startAt)
		for _ = 1, throws do
			s = step(s, { kind = "throwAccepted", side = "A" }, startAt + 0.5)
			s = step(s, { kind = "throwAccepted", side = "B" }, startAt + 0.5)
		end
		return step(s, { kind = "forfeit", side = "B" }, startAt + seconds)
	end

	local function recorder(answer: any): (any, { any })
		local calls: { any } = {}
		local payer = {
			grantDuelResult = function(player: any, matchId: string, outcome: string, result: any): any
				table.insert(calls, { player = player, matchId = matchId, outcome = outcome, result = result })
				return answer
			end,
		}
		return payer, calls
	end

	local function fakePort(profiles: { [any]: any }): any
		return {
			getProfile = function(player: any): any?
				return profiles[player]
			end,
			status = function(player: any): string
				return if profiles[player] then "ready" else "loading"
			end,
			persisted = function(_player: any): boolean
				return true
			end,
			savePending = function(_player: any): boolean
				return false
			end,
			statusReason = function(_player: any): string?
				return nil
			end,
			mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
				local profile = profiles[player]
				if profile == nil then
					return false, "data.notReady"
				end
				return true, fn(profile)
			end,
			requestSave = function(_player: any, _reason: string) end,
			onLoaded = function(_handler: any) end,
			onStatusChanged = function(_handler: any) end,
		}
	end

	local function newProfile(): any
		return {
			coins = 0,
			owned = { kitty_bread = { at = 1, src = "starter" } },
			stats = {
				coinsEarned = 0,
				coinsSpent = 0,
				squeezes = 0,
				duelsPlayed = 0,
				duelsWon = 0,
				duelsLost = 0,
				duelsDrawn = 0,
				eliminations = 0,
				boxesOpened = 0,
			},
			duelLog = {},
			samePair = {},
		}
	end

	-- What DuelService reads for DuelRewards (its duelLog and samePair hooks), from the real EconomyService.
	local function historyOf(player: any): any
		return { duelLog = EconomyService.duelLog(player), samePair = EconomyService.samePair(player) }
	end

	-- The real EconomyService on fake profiles, with a clock the test moves (`clock.now`).
	local function useEconomy(profiles: { [any]: any }, clock: { now: number })
		EconomyService.useDeps({
			data = fakePort(profiles),
			markDirty = function(_player: any, _field: string) end,
			now = function(): number
				return clock.now
			end,
			debugAllowed = function(): boolean
				return false
			end,
		})
	end

	-- Before any profile system is wired --------------------------------------------------------------------------------

	t.test("without a profile system an unready reward asks nothing and shows no offline line", function()
		local s = forfeitMatch(60, 3, false)
		local reward = DuelRewards.compute(s, "A", {}, NOW_UNIX, Config)
		expect.equal(reward.coinsBlockedReason, "duel.noRewardsOffline")
		local payer, calls = recorder(nil)
		local settled = DuelService.settleReward({ UserId = USER_A }, MATCH_ID, "win", reward, 0, payer)
		expect.equal(settled.coins, 0)
		-- A fresh clone is not wired (the line is left out); a module the running server already wired shows it.
		expect.equal(settled.coinsBlockedReason, if DuelService.rewardsWired() then "duel.noRewardsOffline" else nil)
		expect.equal(#calls, 0)
	end)

	-- Wired -----------------------------------------------------------------------------------------------------------

	t.test("once wired, an unready profile's result shows duel.noRewardsOffline", function()
		DuelService.setHooks({
			profileReady = function(_player: any): boolean
				return false
			end,
		})
		expect.truthy(DuelService.rewardsWired())
		local s = forfeitMatch(60, 3, false)
		local reward = DuelRewards.compute(s, "A", {}, NOW_UNIX, Config)
		local payer, calls = recorder(nil)
		local settled = DuelService.settleReward({ UserId = USER_A }, MATCH_ID, "win", reward, 0, payer)
		-- Put back the hooks init uses, so a run inside a live server leaves its rewards working.
		DuelService.setHooks({
			profileReady = EconomyService.canEarn,
			duelLog = EconomyService.duelLog,
			samePair = EconomyService.samePair,
		})
		expect.deepEqual(settled, { coins = 0, coinsBlockedReason = "duel.noRewardsOffline" })
		expect.equal(#calls, 0)
	end)

	t.test("an eligible reward is paid through EconomyService and DuelResult shows what was paid", function()
		local s = forfeitMatch(60, 3, true)
		local reward = DuelRewards.compute(s, "A", {}, NOW_UNIX, Config)
		local payer, calls = recorder({ coins = 200, recorded = true, alreadyGranted = false })
		local player = { UserId = USER_A }
		local settled = DuelService.settleReward(player, MATCH_ID, "win", reward, 1, payer)
		expect.deepEqual(settled, { coins = 200 })
		expect.equal(#calls, 1)
		expect.equal(calls[1].player, player)
		expect.equal(calls[1].matchId, MATCH_ID)
		expect.equal(calls[1].outcome, "win")
		expect.deepEqual(calls[1].result, {
			coins = 200,
			logEntry = { matchId = MATCH_ID, opp = USER_B, result = "win", at = NOW_UNIX, full = true },
			eliminations = 1,
		})
	end)

	t.test("a too-short result is recorded with 0 Coins and shows duel.tooShort", function()
		local s = forfeitMatch(60, 2, true) -- fewer than 3 accepted throws
		local reward = DuelRewards.compute(s, "A", {}, NOW_UNIX, Config)
		local payer, calls = recorder({ coins = 0, recorded = true, alreadyGranted = false })
		local settled = DuelService.settleReward({ UserId = USER_A }, MATCH_ID, "win", reward, 0, payer)
		expect.deepEqual(settled, { coins = 0, coinsBlockedReason = "duel.tooShort" })
		expect.equal(#calls, 1)
	end)

	t.test("a reduced same-pair reward shows its Coins with duel.rewardsReduced", function()
		local s = forfeitMatch(60, 3, true)
		local times = {}
		for i = Config.Economy.DuelRewards.samePairFullRewards, 1, -1 do
			table.insert(times, NOW_UNIX - i)
		end
		local reward = DuelRewards.compute(s, "A", { samePair = { [tostring(USER_B)] = times } }, NOW_UNIX, Config)
		local payer = recorder({ coins = reward.coins, recorded = true, alreadyGranted = false })
		local settled = DuelService.settleReward({ UserId = USER_A }, MATCH_ID, "win", reward, 0, payer)
		expect.equal(settled.coins, 50)
		expect.equal(settled.coinsBlockedReason, "duel.rewardsReduced")
	end)

	t.test("EconomyService says already paid or no longer ready: 0 Coins", function()
		local s = forfeitMatch(60, 3, true)
		local reward = DuelRewards.compute(s, "A", {}, NOW_UNIX, Config)
		local paid = recorder({ coins = 0, recorded = false, alreadyGranted = true })
		expect.deepEqual(DuelService.settleReward({ UserId = USER_A }, MATCH_ID, "win", reward, 0, paid), { coins = 0 })
		local lost = recorder({
			coins = 0,
			recorded = false,
			alreadyGranted = false,
			blockedReason = "duel.noRewardsOffline",
		})
		expect.deepEqual(
			DuelService.settleReward({ UserId = USER_A }, MATCH_ID, "win", reward, 0, lost),
			{ coins = 0, coinsBlockedReason = "duel.noRewardsOffline" }
		)
	end)

	t.test("through the real EconomyService a match pays once, however often it is settled", function()
		local winner, loser = { UserId = USER_A }, { UserId = USER_B }
		local profiles = { [winner] = newProfile(), [loser] = newProfile() }
		useEconomy(profiles, { now = NOW_UNIX })
		local s = forfeitMatch(60, 3, true)
		for _ = 1, 2 do
			local winReward = DuelRewards.compute(s, "A", historyOf(winner), NOW_UNIX, Config)
			local lossReward = DuelRewards.compute(s, "B", historyOf(loser), NOW_UNIX, Config)
			DuelService.settleReward(winner, MATCH_ID, "win", winReward, 0)
			DuelService.settleReward(loser, MATCH_ID, "loss", lossReward, 0)
		end
		-- The loser bailed after 60 s: the win pays 200; the loss (>= 45 s of Active) pays 60.
		expect.equal(profiles[winner].coins, Config.Economy.DuelRewards.win)
		expect.equal(profiles[loser].coins, Config.Economy.DuelRewards.loss)
		expect.equal(#profiles[winner].duelLog, 1)
		expect.equal(#profiles[loser].duelLog, 1)
		-- One same-pair time each, however often the match was settled.
		expect.deepEqual(profiles[winner].samePair, { [tostring(USER_B)] = { NOW_UNIX } })
		expect.deepEqual(profiles[loser].samePair, { [tostring(USER_A)] = { NOW_UNIX } })
		expect.equal(profiles[winner].stats.duelsWon, 1)
		expect.equal(profiles[loser].stats.duelsLost, 1)
		-- Settling the already-recorded match directly (a duplicate call past DuelRewards) pays 0 too.
		local replay = DuelService.settleReward(
			winner,
			MATCH_ID,
			"win",
			{
				coins = 200,
				logEntry = { matchId = MATCH_ID, opp = USER_B, result = "win", at = NOW_UNIX },
				alreadyGranted = false,
			} :: any,
			0
		)
		expect.deepEqual(replay, { coins = 0 })
		expect.equal(profiles[winner].coins, Config.Economy.DuelRewards.win)
		expect.deepEqual(profiles[winner].samePair, { [tostring(USER_B)] = { NOW_UNIX } })
		EconomyService.useDeps(nil)
	end)

	-- §6.7 "6 fully rewarded results per rolling hour": unpaid results are recorded (stats, exactly once) but never
	-- count toward the same-pair reduction, so they cannot cut a later real win.
	t.test("through the real EconomyService, unpaid results against the same opponent never reduce a win", function()
		local winner = { UserId = USER_A }
		local profiles = { [winner] = newProfile() }
		useEconomy(profiles, { now = NOW_UNIX })
		local REWARDS = Config.Economy.DuelRewards
		-- More unpaid wins against B than the same-pair limit: B forfeits after 60 s, but A made only 2 throws.
		for i = 1, REWARDS.samePairFullRewards + 2 do
			local id = "short-" .. i
			local reward = DuelRewards.compute(forfeitMatch(60, 2, true, id), "A", historyOf(winner), NOW_UNIX, Config)
			expect.equal(reward.coinsBlockedReason, "duel.tooShort")
			DuelService.settleReward(winner, id, "win", reward, 0)
		end
		expect.equal(profiles[winner].coins, 0)
		expect.equal(#profiles[winner].duelLog, REWARDS.samePairFullRewards + 2)
		expect.equal(profiles[winner].stats.duelsPlayed, REWARDS.samePairFullRewards + 2)
		expect.deepEqual(profiles[winner].samePair, {}) -- unpaid results add no same-pair time
		-- The next real win against B pays in full.
		local real = DuelRewards.compute(forfeitMatch(60, 3, true, "real-1"), "A", historyOf(winner), NOW_UNIX, Config)
		expect.deepEqual(DuelService.settleReward(winner, "real-1", "win", real, 0), { coins = REWARDS.win })
		expect.equal(profiles[winner].coins, REWARDS.win)
		EconomyService.useDeps(nil)
	end)

	-- §12 #15, the exploit the samePair record closes: a fast cycle is ~34 s (~105 results an hour), so duelLog's 30
	-- entries cover ~17 minutes and seven alts in rotation never put 6 results against one alt in it.
	t.test("seven alts in rotation: the 7th full result against one alt inside the hour is reduced for both", function()
		local REWARDS = Config.Economy.DuelRewards
		local CYCLE_SECONDS = 34
		local ALTS = 7
		local limit = REWARDS.samePairFullRewards
		local main = { UserId = USER_A }
		local profiles: { [any]: any } = { [main] = newProfile() }
		local alts = {}
		for i = 1, ALTS do
			alts[i] = { UserId = 9000 + i }
			profiles[alts[i]] = newProfile()
		end
		local clock = { now = NOW_UNIX }
		useEconomy(profiles, clock)

		-- One match: B (the alt) forfeits after 60 s of Active, both made 3 throws (a full win and a full loss).
		local played = 0
		local function play(alt: any): (number, number, any)
			played += 1
			local id = `rotation-{played}`
			local s = forfeitMatch(60, 3, true, id, alt.UserId)
			local mainReward = DuelRewards.compute(s, "A", historyOf(main), clock.now, Config)
			local altReward = DuelRewards.compute(s, "B", historyOf(alt), clock.now, Config)
			local mainPaid = DuelService.settleReward(main, id, "win", mainReward, 0)
			local altPaid = DuelService.settleReward(alt, id, "loss", altReward, 0)
			clock.now += CYCLE_SECONDS
			return mainPaid.coins, altPaid.coins, mainPaid
		end

		-- Rounds 1..6: every result against every alt is paid in full.
		for _ = 1, limit do
			for i = 1, ALTS do
				local mainCoins, altCoins = play(alts[i])
				expect.equal(mainCoins, REWARDS.win)
				expect.equal(altCoins, REWARDS.loss)
			end
		end
		-- duelLog (capped) no longer holds `limit` results against the first alt, so it could never have caught this.
		local firstAlt = alts[1]
		local inLog = 0
		for _, entry in profiles[main].duelLog do
			if entry.opp == firstAlt.UserId then
				inLog += 1
			end
		end
		expect.equal(#profiles[main].duelLog, Config.Data.caps.duelLog)
		expect.truthy(inLog < limit)
		expect.equal(#profiles[main].samePair[tostring(firstAlt.UserId)], limit)
		expect.truthy(clock.now - NOW_UNIX < REWARDS.samePairWindowSeconds)

		-- Round 7: the 7th full result against each alt inside the hour is reduced, for both players.
		for i = 1, ALTS do
			local mainCoins, altCoins, shown = play(alts[i])
			expect.equal(mainCoins, math.floor(REWARDS.win * REWARDS.samePairMultiplier))
			expect.equal(altCoins, math.floor(REWARDS.loss * REWARDS.samePairMultiplier))
			expect.equal(shown.coinsBlockedReason, "duel.rewardsReduced")
		end
		-- Reduced results add no time: still `limit` per alt.
		expect.equal(#profiles[main].samePair[tostring(firstAlt.UserId)], limit)
		expect.equal(#profiles[firstAlt].samePair[tostring(USER_A)], limit)

		-- An hour after the first result against the first alt that one has left the window: full again.
		clock.now = NOW_UNIX + REWARDS.samePairWindowSeconds
		local mainCoins, altCoins = play(firstAlt)
		expect.equal(mainCoins, REWARDS.win)
		expect.equal(altCoins, REWARDS.loss)
		EconomyService.useDeps(nil)
	end)

	-- Eliminations ----------------------------------------------------------------------------------------------------

	t.test(
		"eliminationsFor: the winner of an elimination or sudden-death hit, both on a simultaneous final hit",
		function()
			expect.equal(DuelService.eliminationsFor({ reason = "eliminated" }, "win"), 1)
			expect.equal(DuelService.eliminationsFor({ reason = "eliminated" }, "loss"), 0)
			expect.equal(DuelService.eliminationsFor({ reason = "suddenDeath" }, "win"), 1)
			expect.equal(DuelService.eliminationsFor({ reason = "doubleKo" }, "draw"), 1)
			expect.equal(DuelService.eliminationsFor({ reason = "opponentLeft" }, "win"), 0)
			expect.equal(DuelService.eliminationsFor({ reason = "timeUp" }, "win"), 0)
		end
	)
end
