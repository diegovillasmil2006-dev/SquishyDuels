--!strict
-- DuelRewards_Test: unit tests for ServerScriptService.Server.Logic.DuelRewards. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.7, §12 #14, #15): win 600 / loss 180 / draw 300 (Config.Economy.DuelRewards; spec 2026-10-12 §9:
-- squeezes, paid as written until Phase 3 multiplies them by the squeeze value); only results that
-- reached Result from Active or SuddenDeath pay; >= 3 server-accepted own throws; a win needs >= 20 s of Active, a
-- loss >= 45 s; a draw needs both players at >= 3 throws; Cancelled and Void pay nothing; the same pair gets × 0.25
-- (floored) once 6 fully rewarded results are inside the rolling hour, counted from the samePair record (never from
-- duelLog; a time exactly an hour old is outside, a future one inside, a non-finite one never counts); the record is
-- kept by recordSamePair (expired times dropped, a time added only for a full result, at most 6 per opponent) and
-- capSamePair (sorted, Config.Data.caps.samePair opponents, the least recent go first); a matchId already in duelLog
-- pays nothing again (exactly once); an unready profile is blocked with duel.noRewardsOffline, a short match with
-- duel.tooShort; the Studio test dummy is never rewarded. Matches are played through the real DuelRules machine.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
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
local HOUR = 3600

return function(t: Context)
	local DuelRewards = t.requireServer("Logic/DuelRewards")
	local DuelRules = t.requireServer("Logic/DuelRules")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local REWARDS = Config.Economy.DuelRewards
	local RULES = Config.Duel.Rules

	local function step(s: any, event: any, now: number): any
		local nextState = DuelRules.step(s, event, now)
		return nextState
	end

	-- A match in Active; returns (state, activeStart).
	local function activeMatch(entrantB: any?): (any, number)
		local s = DuelRules.new(MATCH_ID, {
			A = { userId = USER_A, rewardsEnabled = true },
			B = entrantB or { userId = USER_B, rewardsEnabled = true },
		}, T0, Config.Duel)
		s = step(s, { kind = "streamed", side = "A" }, T0 + 0.1)
		s = step(s, { kind = "streamed", side = "B" }, T0 + 0.2)
		s = step(s, { kind = "positioned", side = "A" }, T0 + 0.3)
		s = step(s, { kind = "positioned", side = "B" }, T0 + 0.4)
		local startAt = s.phaseEndsAt
		s = step(s, { kind = "tick" }, startAt)
		return s, startAt
	end

	local function withThrows(s: any, side: string, n: number, at: number): any
		for _ = 1, n do
			s = step(s, { kind = "throwAccepted", side = side }, at)
		end
		return s
	end

	-- A beats B by three hits; the last lands `seconds` after Active began (>= 4 to clear the invulnerability).
	local function eliminationAt(seconds: number, throwsA: number, throwsB: number): any
		local s, startAt = activeMatch()
		s = withThrows(s, "A", throwsA, startAt + 0.5)
		s = withThrows(s, "B", throwsB, startAt + 0.5)
		s = step(s, { kind = "hit", victim = "B", at = startAt + 1 }, startAt + 1)
		s = step(s, { kind = "hit", victim = "B", at = startAt + 3 }, startAt + 3)
		s = step(s, { kind = "hit", victim = "B", at = startAt + seconds }, startAt + seconds)
		assert(s.ended and s.outcome.winner == "A", "setup: A should have won")
		return s
	end

	-- B forfeits `seconds` after Active began (>= 20: A wins by opponentLeft).
	local function forfeitAt(seconds: number, throwsA: number, throwsB: number): any
		local s, startAt = activeMatch()
		s = withThrows(s, "A", throwsA, startAt + 0.5)
		s = withThrows(s, "B", throwsB, startAt + 0.5)
		return step(s, { kind = "forfeit", side = "B" }, startAt + seconds)
	end

	local function drawMatch(throwsA: number, throwsB: number): any
		local s, startAt = activeMatch()
		s = withThrows(s, "A", throwsA, startAt + 0.5)
		s = withThrows(s, "B", throwsB, startAt + 0.5)
		s = step(s, { kind = "tick" }, startAt + RULES.MatchSeconds)
		s = step(s, { kind = "tick" }, startAt + RULES.MatchSeconds + RULES.SuddenDeathSeconds)
		assert(s.outcome.kind == "draw", "setup: expected a draw")
		return s
	end

	-- A history whose samePair record holds fully rewarded results against `opponent`, `ages` seconds old.
	local function pairHistory(opponent: number, ages: { number }): any
		local times = {}
		for _, age in ages do
			table.insert(times, NOW_UNIX - age)
		end
		table.sort(times)
		return { duelLog = {}, samePair = { [tostring(opponent)] = times } }
	end

	-- duelLog entries against `opponent`, `ages` seconds old, all marked fully rewarded.
	local function logAgainst(opponent: number, ages: { number }): { any }
		local log = {}
		for index, age in ages do
			table.insert(
				log,
				{ matchId = "old-" .. index, opp = opponent, result = "win", at = NOW_UNIX - age, full = true }
			)
		end
		return log
	end

	-- Amounts --------------------------------------------------------------------------------------------------------

	t.test("Config amounts are spec 2026-10-12's win 600 / loss 180 / draw 300 (3x DESIGN's)", function()
		expect.equal(REWARDS.win, 600)
		expect.equal(REWARDS.loss, 180)
		expect.equal(REWARDS.draw, 300)
		expect.equal(REWARDS.minOwnThrows, 3)
		expect.equal(REWARDS.winMinActiveSeconds, 20)
		expect.equal(REWARDS.lossMinActiveSeconds, 45)
	end)

	t.test("a full win and loss pay 600 and 180 with a duelLog entry each", function()
		local s = forfeitAt(60, 3, 3)
		local win = DuelRewards.compute(s, "A", {}, NOW_UNIX, Config)
		expect.equal(win.outcome, "win")
		expect.truthy(win.eligible)
		expect.equal(win.coins, 600)
		expect.equal(win.coinsBlockedReason, nil)
		expect.deepEqual(win.logEntry, { matchId = MATCH_ID, opp = USER_B, result = "win", at = NOW_UNIX, full = true })
		local loss = DuelRewards.compute(s, "B", {}, NOW_UNIX, Config)
		expect.equal(loss.outcome, "loss")
		expect.equal(loss.coins, 180)
		expect.deepEqual(
			loss.logEntry,
			{ matchId = MATCH_ID, opp = USER_A, result = "loss", at = NOW_UNIX, full = true }
		)
	end)

	t.test("a draw pays 300 to both when both made 3 throws", function()
		local s = drawMatch(3, 3)
		local all = DuelRewards.computeAll(s, { A = {}, B = {} }, NOW_UNIX, Config)
		expect.equal(all.A.outcome, "draw")
		expect.equal(all.A.coins, 300)
		expect.equal(all.B.coins, 300)
	end)

	-- Minimum Active time (win 20 s, loss 45 s) -------------------------------------------------------------------

	t.test("win needs 20 s of Active: 19.9 s is too short, 20 s pays", function()
		local short = eliminationAt(19.9, 3, 3)
		local early = DuelRewards.compute(short, "A", {}, NOW_UNIX, Config)
		expect.equal(early.outcome, "win")
		expect.equal(early.coins, 0)
		expect.falsy(early.eligible)
		expect.equal(early.coinsBlockedReason, "duel.tooShort")
		expect.truthy(early.logEntry ~= nil) -- still a result: logged for stats and idempotency
		expect.equal((early.logEntry :: any).full, false) -- but not a fully rewarded one (same-pair rule, §6.7)
		local exact = eliminationAt(20, 3, 3)
		expect.equal(DuelRewards.compute(exact, "A", {}, NOW_UNIX, Config).coins, 600)
	end)

	t.test("loss needs 45 s of Active: 44.9 s is too short, 45 s pays", function()
		local short = eliminationAt(44.9, 3, 3)
		local loss = DuelRewards.compute(short, "B", {}, NOW_UNIX, Config)
		expect.equal(loss.outcome, "loss")
		expect.equal(loss.coins, 0)
		expect.equal(loss.coinsBlockedReason, "duel.tooShort")
		-- The winner of the same match (>= 20 s) is paid.
		expect.equal(DuelRewards.compute(short, "A", {}, NOW_UNIX, Config).coins, 600)
		local exact = eliminationAt(45, 3, 3)
		expect.equal(DuelRewards.compute(exact, "B", {}, NOW_UNIX, Config).coins, 180)
	end)

	t.test("a forfeit win at exactly 20 s of Active pays the winner", function()
		local s = forfeitAt(20, 3, 3)
		expect.equal(DuelRewards.compute(s, "A", {}, NOW_UNIX, Config).coins, 600)
		expect.equal(DuelRewards.compute(s, "B", {}, NOW_UNIX, Config).coins, 0) -- 20 s < 45 s for the loser
	end)

	-- Accepted throws -------------------------------------------------------------------------------------------------

	t.test("fewer than 3 accepted own throws pays nothing (duel.tooShort)", function()
		local s = forfeitAt(60, 2, 3)
		local reward = DuelRewards.compute(s, "A", {}, NOW_UNIX, Config)
		expect.equal(reward.coins, 0)
		expect.equal(reward.coinsBlockedReason, "duel.tooShort")
		expect.equal(DuelRewards.compute(s, "B", {}, NOW_UNIX, Config).coins, 180)
	end)

	t.test("a draw needs both players at 3 throws", function()
		local s = drawMatch(5, 2)
		local all = DuelRewards.computeAll(s, nil, NOW_UNIX, Config)
		expect.equal(all.A.coins, 0)
		expect.equal(all.A.coinsBlockedReason, "duel.tooShort")
		expect.equal(all.B.coins, 0)
	end)

	t.test("stats report throws, hits and accuracy as a rounded percentage (Types.DuelStats)", function()
		local s = eliminationAt(30, 4, 3)
		local reward = DuelRewards.compute(s, "A", {}, NOW_UNIX, Config)
		expect.equal(reward.stats.throws, 4)
		expect.equal(reward.stats.hits, 3)
		expect.equal(reward.stats.accuracy, 75)
		local loser = DuelRewards.compute(s, "B", {}, NOW_UNIX, Config)
		expect.equal(loser.stats.hits, 0)
		expect.equal(loser.stats.accuracy, 0)
		-- 3 hits from 7 throws = 42.86 % -> 43; no throws -> 0 (never a division by zero).
		local seven = eliminationAt(30, 7, 0)
		expect.equal(DuelRewards.compute(seven, "A", {}, NOW_UNIX, Config).stats.accuracy, 43)
		expect.equal(DuelRewards.compute(seven, "B", {}, NOW_UNIX, Config).stats.accuracy, 0)
	end)

	-- Cancelled and Void ----------------------------------------------------------------------------------------------

	t.test("Cancelled and Void pay nothing and log nothing", function()
		local cancelled = forfeitAt(10, 5, 5) -- a bail before 20 s
		expect.equal(cancelled.outcome.kind, "cancelled")
		for _, side in { "A", "B" } do
			local reward = DuelRewards.compute(cancelled, side, {}, NOW_UNIX, Config)
			expect.equal(reward.outcome, "cancelled")
			expect.equal(reward.coins, 0)
			expect.equal(reward.coinsBlockedReason, nil)
			expect.equal(reward.logEntry, nil)
		end
		local active, startAt = activeMatch()
		active = withThrows(active, "A", 5, startAt + 1)
		local voided = step(active, { kind = "shutdown" }, startAt + 60)
		local reward = DuelRewards.compute(voided, "A", {}, NOW_UNIX, Config)
		expect.equal(reward.outcome, "void")
		expect.equal(reward.coins, 0)
		expect.equal(reward.logEntry, nil)
	end)

	t.test("a match that has not ended pays nothing", function()
		local s = activeMatch()
		local reward = DuelRewards.compute(s, "A", {}, NOW_UNIX, Config)
		expect.equal(reward.outcome, "void")
		expect.equal(reward.coins, 0)
	end)

	-- Same pair ×0.25 after 6 per rolling hour -----------------------------------------------------------------------

	t.test("same pair: 5 recent results still pay in full, the 7th result gets × 0.25", function()
		local s = forfeitAt(60, 3, 3)
		local five = DuelRewards.compute(s, "A", pairHistory(USER_B, { 60, 600, 1200, 1800, 2400 }), NOW_UNIX, Config)
		expect.equal(five.coins, 600)
		expect.equal(five.reducedReason, nil)
		expect.equal((five.logEntry :: any).full, true)
		local six =
			DuelRewards.compute(s, "A", pairHistory(USER_B, { 60, 600, 1200, 1800, 2400, 3000 }), NOW_UNIX, Config)
		expect.equal(six.multiplier, REWARDS.samePairMultiplier)
		expect.equal(six.coins, 150)
		expect.equal(six.reducedReason, "duel.rewardsReduced")
		expect.equal(six.base, 600)
		expect.equal((six.logEntry :: any).full, false) -- a reduced result is not fully rewarded
		local lossSix = DuelRewards.compute(s, "B", pairHistory(USER_A, { 1, 2, 3, 4, 5, 6 }), NOW_UNIX, Config)
		expect.equal(lossSix.coins, 45)
		local drawn = drawMatch(3, 3)
		expect.equal(
			DuelRewards.compute(drawn, "A", pairHistory(USER_B, { 1, 2, 3, 4, 5, 6 }), NOW_UNIX, Config).coins,
			75
		)
	end)

	t.test("same pair: the window is a rolling hour; older results and other opponents do not count", function()
		local s = forfeitAt(60, 3, 3)
		-- Six times against B, but one is exactly an hour old (outside), plus one against someone else.
		local history = pairHistory(USER_B, { 10, 20, 30, 40, 50, HOUR })
		history.samePair["999"] = { NOW_UNIX - 5 }
		expect.equal(DuelRewards.compute(s, "A", history, NOW_UNIX, Config).coins, 600)
		table.insert(history.samePair[tostring(USER_B)], 2, NOW_UNIX - (HOUR - 1)) -- (kept ascending)
		expect.equal(DuelRewards.compute(s, "A", history, NOW_UNIX, Config).coins, 150)
	end)

	-- §6.7 / §12 #15: the count reads the samePair record, never duelLog (capped at 30, about 17 minutes of duels).
	t.test("same pair: the count reads the samePair record, never duelLog", function()
		local s = forfeitAt(60, 3, 3)
		-- Ten fully rewarded duelLog entries against B this hour but an empty record: paid in full.
		local onlyLog = { duelLog = logAgainst(USER_B, { 10, 20, 30, 40, 50, 60, 70, 80, 90, 100 }), samePair = {} }
		expect.equal(DuelRewards.compute(s, "A", onlyLog, NOW_UNIX, Config).coins, 600)
		-- An empty duelLog with six recent times in the record: reduced.
		expect.equal(
			DuelRewards.compute(s, "A", pairHistory(USER_B, { 1, 2, 3, 4, 5, 6 }), NOW_UNIX, Config).coins,
			150
		)
		-- No record at all (nil history or none in it) counts as empty.
		expect.equal(DuelRewards.compute(s, "A", nil, NOW_UNIX, Config).coins, 600)
		expect.equal(DuelRewards.compute(s, "A", { duelLog = {} }, NOW_UNIX, Config).coins, 600)
	end)

	t.test("same pair: a future time (another server's clock) counts; a non-finite one never does", function()
		local s = forfeitAt(60, 3, 3)
		local history = pairHistory(USER_B, { 1, 2, 3, 4, 5 })
		local times = history.samePair[tostring(USER_B)]
		table.insert(times, 0 / 0)
		table.insert(times, math.huge)
		expect.equal(DuelRewards.compute(s, "A", history, NOW_UNIX, Config).coins, 600)
		table.insert(times, NOW_UNIX + 30)
		expect.equal(DuelRewards.compute(s, "A", history, NOW_UNIX, Config).coins, 150)
	end)

	t.test("compute takes a history, never a bare duelLog", function()
		local s = forfeitAt(60, 3, 3)
		expect.throws(function()
			DuelRewards.compute(s, "A", logAgainst(USER_B, { 1 }) :: any, NOW_UNIX, Config)
		end, "history")
	end)

	-- The samePair record (kept by EconomyService.grantDuelResult and ProfileSchema.sanitize) ---------------------------

	t.test("samePairKey writes the userId as a whole-number string", function()
		expect.equal(DuelRewards.samePairKey(301), "301")
		expect.equal(DuelRewards.samePairKey(9_999_999_999), "9999999999")
		expect.equal(DuelRewards.samePairKey(-1), "-1")
	end)

	t.test("samePairCount counts one opponent's times inside the window", function()
		local record = {
			["402"] = { NOW_UNIX - HOUR, NOW_UNIX - (HOUR - 1), NOW_UNIX - 5, NOW_UNIX },
			["999"] = { NOW_UNIX - 1 },
		}
		expect.equal(DuelRewards.samePairCount(record, USER_B, NOW_UNIX, Config), 3)
		expect.equal(DuelRewards.samePairCount(record, 999, NOW_UNIX, Config), 1)
		expect.equal(DuelRewards.samePairCount(record, 12345, NOW_UNIX, Config), 0)
		expect.equal(DuelRewards.samePairCount(nil, USER_B, NOW_UNIX, Config), 0)
	end)

	t.test("recordSamePair: expired times go, a full result adds now, others add nothing", function()
		local record: any = {
			["402"] = { NOW_UNIX - HOUR, NOW_UNIX - 100 }, -- the first is exactly an hour old: dropped
			["777"] = { NOW_UNIX - HOUR - 5 }, -- nothing left: the opponent is dropped
		}
		DuelRewards.recordSamePair(record, USER_B, NOW_UNIX, false, Config)
		expect.deepEqual(record, { ["402"] = { NOW_UNIX - 100 } })
		DuelRewards.recordSamePair(record, USER_B, NOW_UNIX, true, Config)
		expect.deepEqual(record, { ["402"] = { NOW_UNIX - 100, NOW_UNIX } })
		DuelRewards.recordSamePair(record, USER_A, NOW_UNIX + 1, true, Config)
		expect.deepEqual(record, { ["402"] = { NOW_UNIX - 100, NOW_UNIX }, ["301"] = { NOW_UNIX + 1 } })
		-- An hour after the last one everything has expired.
		DuelRewards.recordSamePair(record, USER_A, NOW_UNIX + 1 + HOUR, false, Config)
		expect.deepEqual(record, {})
	end)

	t.test("recordSamePair keeps at most samePairFullRewards times per opponent (the newest)", function()
		local record: any = {}
		for i = 1, REWARDS.samePairFullRewards + 3 do
			DuelRewards.recordSamePair(record, USER_B, NOW_UNIX + i, true, Config)
		end
		local times = record[tostring(USER_B)]
		expect.equal(#times, REWARDS.samePairFullRewards)
		expect.equal(times[1], NOW_UNIX + 4)
		expect.equal(times[#times], NOW_UNIX + REWARDS.samePairFullRewards + 3)
		-- A time from a server whose clock is behind still lands in order (and the oldest makes room).
		DuelRewards.recordSamePair(record, USER_B, NOW_UNIX + 5, true, Config)
		local sorted = record[tostring(USER_B)]
		expect.equal(#sorted, REWARDS.samePairFullRewards)
		expect.equal(sorted[1], NOW_UNIX + 5)
		for i = 2, #sorted do
			expect.truthy(sorted[i - 1] <= sorted[i])
		end
	end)

	t.test("capSamePair: sorted, finite only, and above the opponent cap the least recent opponents go", function()
		local cfg = { Economy = Config.Economy, Data = { caps = { samePair = 3 } } }
		local record: any = {
			["1"] = { NOW_UNIX - 10, NOW_UNIX - 50 },
			["2"] = { NOW_UNIX - 40 },
			["3"] = { NOW_UNIX - 5, 0 / 0 },
			["4"] = { NOW_UNIX - 40 },
			["5"] = { NOW_UNIX - 20 },
		}
		local removed = DuelRewards.capSamePair(record, cfg)
		-- Newest times: 1 -> -10, 3 -> -5, 5 -> -20, 2 and 4 -> -40 (both dropped, as is the NaN).
		expect.deepEqual(record, {
			["1"] = { NOW_UNIX - 50, NOW_UNIX - 10 },
			["3"] = { NOW_UNIX - 5 },
			["5"] = { NOW_UNIX - 20 },
		})
		expect.equal(removed, 3)
		-- A tie at the cap keeps the smaller key, so the result never depends on table order.
		local tie: any = { ["8"] = { NOW_UNIX }, ["9"] = { NOW_UNIX } }
		DuelRewards.capSamePair(tie, { Economy = Config.Economy, Data = { caps = { samePair = 1 } } })
		expect.deepEqual(tie, { ["8"] = { NOW_UNIX } })
		-- The live cap is Config.Data.caps.samePair.
		expect.equal(Config.Data.caps.samePair, 128)
	end)

	-- Exactly once ------------------------------------------------------------------------------------------------

	t.test("exactly once by matchId: a matchId already in duelLog pays nothing again", function()
		local s = forfeitAt(60, 3, 3)
		local log: { any } = {}
		local first = DuelRewards.compute(s, "A", { duelLog = log }, NOW_UNIX, Config)
		expect.equal(first.coins, 600)
		table.insert(log, first.logEntry)
		local second = DuelRewards.compute(s, "A", { duelLog = log }, NOW_UNIX + 5, Config)
		expect.truthy(second.alreadyGranted)
		expect.equal(second.coins, 0)
		expect.equal(second.logEntry, nil)
		expect.falsy(second.eligible)
	end)

	t.test("exactly once per match: DuelRules ends a match once, so rewards are computed once", function()
		-- DuelService computes rewards on the `ended` effect; late spam after the end never produces another.
		local s, startAt = activeMatch()
		s = withThrows(s, "A", 3, startAt + 1)
		local endedCount = 0
		local granted = 0
		local events: { { any } } = {
			{ { kind = "forfeit", side = "B" }, startAt + 30 },
			{ { kind = "forfeit", side = "B" }, startAt + 30 },
			{ { kind = "leave", side = "B" }, startAt + 31 },
			{ { kind = "hit", victim = "B", at = startAt + 31 }, startAt + 31 },
			{ { kind = "shutdown" }, startAt + 32 },
		}
		for _, item in events do
			local effects
			s, effects = DuelRules.step(s, item[1], item[2])
			for _, effect in effects do
				if effect.kind == "ended" then
					endedCount += 1
					granted += DuelRewards.compute(s, "A", {}, NOW_UNIX, Config).coins
				end
			end
		end
		expect.equal(endedCount, 1)
		expect.equal(granted, 600)
	end)

	-- Profile, dummy, inputs ----------------------------------------------------------------------------------------

	t.test("a profile that is not ready gets duel.noRewardsOffline and no log entry", function()
		local s, startAt = activeMatch({ userId = USER_B, rewardsEnabled = false })
		s = withThrows(s, "A", 3, startAt + 1)
		s = withThrows(s, "B", 3, startAt + 1)
		s = step(s, { kind = "forfeit", side = "A" }, startAt + 60)
		local reward = DuelRewards.compute(s, "B", {}, NOW_UNIX, Config)
		expect.equal(reward.outcome, "win")
		expect.equal(reward.coins, 0)
		expect.equal(reward.coinsBlockedReason, "duel.noRewardsOffline")
		expect.equal(reward.logEntry, nil)
	end)

	t.test("the Studio test dummy is never rewarded; the real player still is", function()
		local s, startAt = activeMatch({ userId = -1, isTestDummy = true, rewardsEnabled = true })
		s = withThrows(s, "A", 3, startAt + 1)
		s = withThrows(s, "B", 3, startAt + 1)
		s = step(s, { kind = "forfeit", side = "A" }, startAt + 60)
		local dummy = DuelRewards.compute(s, "B", {}, NOW_UNIX, Config)
		expect.equal(dummy.outcome, "win")
		expect.equal(dummy.coins, 0)
		expect.equal(dummy.coinsBlockedReason, nil)
		expect.equal(dummy.logEntry, nil)
		local real = DuelRewards.compute(s, "A", {}, NOW_UNIX, Config)
		expect.equal(real.outcome, "loss")
		expect.equal(real.coins, 180)
	end)

	t.test("the participant may be given as its record instead of its side", function()
		local s = forfeitAt(60, 3, 3)
		expect.equal(DuelRewards.compute(s, s.participants.B, {}, NOW_UNIX, Config).outcome, "loss")
		expect.throws(function()
			DuelRewards.compute(s, "C", {}, NOW_UNIX, Config)
		end, "participant")
	end)

	t.test("compute never changes the match or the history it reads", function()
		local s = forfeitAt(60, 3, 3)
		local history = pairHistory(USER_B, { 1, 2, 3, 4, 5, 6, HOUR + 1 })
		history.duelLog = logAgainst(USER_B, { 1, 2, 3, 4, 5, 6 })
		local before = table.clone(history.samePair[tostring(USER_B)])
		DuelRewards.compute(s, "A", history, NOW_UNIX, Config)
		expect.equal(#history.duelLog, 6)
		expect.deepEqual(history.samePair[tostring(USER_B)], before) -- even the expired time stays
		expect.equal(s.participants.A.throws, 3)
		expect.truthy(s.ended)
	end)
end
