--!strict
-- DuelService_Test: unit tests for DuelService.resultFor, the pure part of ServerScriptService.Server.Services.
-- DuelService that turns an ended Logic/DuelRules state into each participant's DuelResult outcome and reasonKey.
-- Server only (ServerStorage.UnitTest). Edit mode: no match is started, nothing is created; the states come from
-- DuelRules itself, driven with plain events and times.
-- Contract (DESIGN §5.2 victory and draw, §5.4 edge cases, §2.8 DuelResult):
--   * every way a duel ends gives each side the right view (win / loss / draw / cancelled / void) and a reasonKey that
--     exists in Strings;
--   * a bail before Active tells the requeued player "duel.opponentLeftEarly"; a bail before EarlyForfeitSeconds of
--     Active is a plain cancel; a later bail is a win for the other side ("duel.opponentLeft" / "duel.youLeft"), and
--     repeated out-of-bounds has its own line;
--   * a state that has not ended reads as void;
--   * DuelResult.coinsBlockedReason leaves out duel.noRewardsOffline until a profile system exists (§0.3 #9);
--   * DuelResult.questProgress / tip (Part 7, resultExtras): the hooks registered with setResultHooks are asked once
--     per real participant and never for the test dummy; their answers are carried; a throwing hook or an answer of
--     the wrong type leaves {} / nil; a missing field keeps the current hook.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local DuelService = t.requireServer("Services/DuelService")
	local DuelRules = t.requireServer("Logic/DuelRules")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")

	local RULES = Config.Duel.Rules

	local function step(state: any, event: { [string]: any }, now: number): any
		local nextState = DuelRules.step(state, event, now)
		return nextState
	end

	-- A match between user 1 (side A) and user 2 (side B), driven to Countdown. Returns (state, countdownEndsAt).
	local function countdown(): (any, number)
		local s = DuelRules.new("match-test", { A = { userId = 1 }, B = { userId = 2 } }, 0)
		s = step(s, { kind = "streamed", side = "A" }, 0.1)
		s = step(s, { kind = "streamed", side = "B" }, 0.2)
		s = step(s, { kind = "positioned", side = "A" }, 0.3)
		s = step(s, { kind = "positioned", side = "B" }, 0.4)
		expect.equal(s.phase, "Countdown")
		return s, s.phaseEndsAt
	end

	-- The same match at the start of Active. Returns (state, activeStartedAt).
	local function active(): (any, number)
		local s, endsAt = countdown()
		s = step(s, { kind = "tick" }, endsAt)
		expect.equal(s.phase, "Active")
		return s, endsAt
	end

	local function expectResult(state: any, side: string, view: string, key: string)
		local gotView, gotKey = DuelService.resultFor(state, side)
		expect.equal(gotView, view)
		expect.equal(gotKey, key)
		expect.truthy(Strings.resolve(key) ~= nil) -- the client can show it
	end

	t.test("elimination: the survivor wins, the other is out", function()
		local s, start = active()
		for i = 1, RULES.Lives do
			local at = start + i * (RULES.HitInvulnSeconds + 0.5)
			s = step(s, { kind = "hit", victim = "B", at = at }, at)
		end
		expect.truthy(s.ended)
		expectResult(s, "A", "win", "duel.opponentOut")
		expectResult(s, "B", "loss", "duel.youOut")
	end)

	t.test("time-up with different lives: more lives wins", function()
		local s, start = active()
		s = step(s, { kind = "hit", victim = "B", at = start + 1 }, start + 1)
		s = step(s, { kind = "tick" }, start + RULES.MatchSeconds)
		expectResult(s, "A", "win", "duel.timeUpWin")
		expectResult(s, "B", "loss", "duel.timeUpLoss")
	end)

	t.test("sudden death: the next hit wins; no hit is a draw", function()
		local s, start = active()
		s = step(s, { kind = "tick" }, start + RULES.MatchSeconds)
		expect.equal(s.phase, "SuddenDeath")
		local won =
			step(s, { kind = "hit", victim = "A", at = start + RULES.MatchSeconds + 5 }, start + RULES.MatchSeconds + 5)
		expectResult(won, "B", "win", "duel.suddenDeathWin")
		expectResult(won, "A", "loss", "duel.suddenDeathLoss")
		local drawn = step(s, { kind = "tick" }, start + RULES.MatchSeconds + RULES.SuddenDeathSeconds)
		expectResult(drawn, "A", "draw", "duel.suddenDeathDraw")
		expectResult(drawn, "B", "draw", "duel.suddenDeathDraw")
	end)

	t.test("two final hits at the same moment are a draw", function()
		local s, start = active()
		s = step(s, { kind = "tick" }, start + RULES.MatchSeconds)
		local at = start + RULES.MatchSeconds + 3
		s = step(s, { kind = "hits", hits = { { victim = "A", at = at }, { victim = "B", at = at } } }, at)
		expectResult(s, "A", "draw", "duel.tieHit")
		expectResult(s, "B", "draw", "duel.tieHit")
	end)

	t.test("a forfeit after EarlyForfeitSeconds of Active is a win for the other side", function()
		local s, start = active()
		s = step(s, { kind = "forfeit", side = "A" }, start + RULES.EarlyForfeitSeconds + 1)
		expectResult(s, "B", "win", "duel.opponentLeft")
		expectResult(s, "A", "loss", "duel.youLeft")
	end)

	t.test("a bail early in Active is cancelled for both", function()
		local s, start = active()
		s = step(s, { kind = "leave", side = "A" }, start + 1)
		expectResult(s, "A", "cancelled", "duel.cancelled")
		expectResult(s, "B", "cancelled", "duel.cancelled")
	end)

	t.test("a bail before Active tells the requeued player they are back at the front", function()
		local s = countdown()
		s = step(s, { kind = "forfeit", side = "A" }, 1)
		expect.equal(s.phase, "Cancelled")
		expectResult(s, "B", "cancelled", "duel.opponentLeftEarly")
		expectResult(s, "A", "cancelled", "duel.cancelled")
	end)

	t.test("repeated out-of-bounds after EarlyForfeitSeconds has its own line", function()
		local s, start = active()
		local at = start + RULES.EarlyForfeitSeconds + 1
		for i = 1, RULES.OutOfBounds.MaxPerMatch + 1 do
			s = step(s, { kind = "oob", side = "A" }, at + i)
		end
		expect.truthy(s.ended)
		expectResult(s, "B", "win", "duel.opponentOutOfBounds")
		expectResult(s, "A", "loss", "duel.youOutOfBounds")
	end)

	t.test("before profiles exist the result never claims progress failed to load (duel.noRewardsOffline)", function()
		local offline = { coinsBlockedReason = "duel.noRewardsOffline" }
		local short = { coinsBlockedReason = "duel.tooShort" }
		expect.equal(DuelService.shownBlockedReason(offline, false), nil) -- Part 4: no DataService, nothing failed
		expect.equal(DuelService.shownBlockedReason(offline, true), "duel.noRewardsOffline") -- Part 5: a real offline
		expect.equal(DuelService.shownBlockedReason(short, false), "duel.tooShort")
		expect.equal(DuelService.shownBlockedReason(nil, true), nil)
	end)

	t.test("shutdown voids the match; a match that has not ended reads as void", function()
		local s, start = active()
		expectResult(s, "A", "void", "duel.void")
		s = step(s, { kind = "shutdown" }, start + 30)
		expectResult(s, "A", "void", "duel.void")
		expectResult(s, "B", "void", "duel.void")
	end)

	-- DuelResult hooks (Part 7: questProgress and tip) -------------------------------------------------------------

	local INFO = { matchId = "match-hooks", outcome = "win", reason = "eliminated", activeSeconds = 61 }

	local function summaryFor(player: any, isTestDummy: boolean, userId: number): any
		return {
			userId = userId,
			player = player,
			isTestDummy = isTestDummy,
			side = "A",
			squishyId = "toast",
			opponentUserId = 2,
			outcome = "win",
			reasonKey = "duel.opponentOut",
			throws = 5,
			hits = 3,
			livesLeft = 2,
			rewardsEnabled = true,
			reward = nil,
			coinsGranted = 200,
			bailed = false,
			requeueFront = false,
		}
	end

	local function restoreResultHooks()
		DuelService.setResultHooks({
			questProgress = function(): { any }
				return {}
			end,
			tip = function(): string?
				return nil
			end,
		})
	end

	t.test("result hooks: asked once per real participant, never for the test dummy; answers are carried", function()
		local calls: { any } = {}
		local line = { questId = "q20000_2", progress = 1, goal = 2, done = false }
		DuelService.setResultHooks({
			questProgress = function(player: any, summary: any, info: any): { any }
				table.insert(calls, { hook = "questProgress", player = player, summary = summary, info = info })
				return { line }
			end,
			tip = function(player: any, summary: any, info: any): string?
				table.insert(calls, { hook = "tip", player = player, summary = summary, info = info })
				return "duel.lossTip"
			end,
		})
		local player = { UserId = 1, Name = "Real" }
		local real = summaryFor(player, false, 1)
		local lines, tip = DuelService.resultExtras(real, INFO)
		expect.deepEqual(lines, { line })
		expect.equal(tip, "duel.lossTip")
		expect.equal(#calls, 2)
		for _, call in calls do
			expect.equal(call.player, player)
			expect.equal(call.summary, real)
			expect.deepEqual(call.info, INFO)
		end
		-- The test dummy (no Player) and a dummy flagged by mistake with a player never reach the hooks.
		local dummyLines, dummyTip = DuelService.resultExtras(summaryFor(nil, true, -1), INFO)
		expect.deepEqual(dummyLines, {})
		expect.equal(dummyTip, nil)
		local flagged = DuelService.resultExtras(summaryFor(player, true, -2), INFO)
		expect.deepEqual(flagged, {})
		expect.equal(#calls, 2)
		restoreResultHooks()
	end)

	t.test("result hooks: a throwing hook or a wrong answer leaves {} / nil and never breaks the result", function()
		DuelService.setResultHooks({
			questProgress = function(): { any }
				error("quest hook exploded")
			end,
			tip = function(): string?
				error("tip hook exploded")
			end,
		})
		local player = { UserId = 1 }
		local lines, tip = DuelService.resultExtras(summaryFor(player, false, 1), INFO)
		expect.deepEqual(lines, {})
		expect.equal(tip, nil)
		DuelService.setResultHooks({
			questProgress = function(): any
				return "not a list"
			end,
			tip = function(): any
				return 42
			end,
		})
		local badLines, badTip = DuelService.resultExtras(summaryFor(player, false, 1), INFO)
		expect.deepEqual(badLines, {})
		expect.equal(badTip, nil)
		restoreResultHooks()
	end)

	t.test("result hooks: a missing field keeps the current hook (like setHooks)", function()
		DuelService.setResultHooks({
			tip = function(): string?
				return "duel.lossTip"
			end,
		})
		DuelService.setResultHooks({
			questProgress = function(): { any }
				return { { questId = "starter_duel", progress = 1, goal = 1, done = true } }
			end,
		})
		local lines, tip = DuelService.resultExtras(summaryFor({ UserId = 1 }, false, 1), INFO)
		expect.equal(#lines, 1)
		expect.equal(lines[1].questId, "starter_duel")
		expect.equal(tip, "duel.lossTip")
		restoreResultHooks()
		local noLines, noTip = DuelService.resultExtras(summaryFor({ UserId = 1 }, false, 1), INFO)
		expect.deepEqual(noLines, {})
		expect.equal(noTip, nil)
	end)
end
