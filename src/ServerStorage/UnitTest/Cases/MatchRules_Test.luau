--!strict
-- MatchRules_Test: unit tests for ServerScriptService.Server.Logic.MatchRules (Free for All / Team Deathmatch, jayyyyy's
-- rules 2026-10-15). Contract: Waiting (every entrant arrived, else waitSeconds) -> Countdown -> Active -> (Overtime)
-- -> Result -> Closed; one hit = K.O.; respawn after respawnSeconds with spawnProtectSeconds of protection; FFA first to
-- koTarget, time-up single leader, tie -> overtime until one player alone leads; TDM (2026-10-26): every K.O. scores
-- for the other team, first to koTarget, time-up higher score, tie -> the next K.O.'s team wins (a storm K.O. counts
-- for the other team), a team whose players all leave loses; Waiting lasts at least introMinSeconds; the storm bar
-- (TDM only); shield, timed buffs and ult charge; leaving; void; `step` never modifies the state it is given. Time
-- comes only from the test.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local T0 = 1000
local MATCH_ID = "match-test"

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

return function(t: Context)
	local MatchRules = t.requireServer("Logic/MatchRules")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local M = deepCopy(Config.Match)
	M.teamNames = { "Red", "Blue" } -- the cases' own team names (qb1: the live ones are Strawberry / Blueberry)
	M.introMinSeconds = 0 -- the cases count down at the last arrival; the intro's minimum has its own case

	-- A copy of Config.Match with mode fields and top-level fields replaced.
	local function matchWith(modeId: string?, modeOverrides: { [string]: any }?, overrides: { [string]: any }?): any
		local cfg = deepCopy(M)
		if modeId and modeOverrides then
			for key, value in modeOverrides do
				cfg.Modes[modeId][key] = value
			end
		end
		for key, value in overrides or {} do
			cfg[key] = value
		end
		return cfg
	end

	local function step(state: any, event: any, now: number): (any, { any })
		return MatchRules.step(state, event, now)
	end

	local function kinds(fx: { any }, kind: string): { any }
		local out = {}
		for _, e in fx do
			if e.kind == kind then
				table.insert(out, e)
			end
		end
		return out
	end

	-- A live match: every entrant arrived at T0, Active from T0 + countdownSeconds. Returns (state, activeAt).
	local function live(modeId: string, entrants: { any }, cfg: any?): (any, number)
		local c = cfg or M
		local s = MatchRules.new(MATCH_ID, modeId, entrants, T0, c)
		for _, e in entrants do
			s = step(s, { kind = "arrived", userId = e.userId }, T0)
		end
		local activeAt = T0 + c.countdownSeconds
		s = step(s, { kind = "tick" }, activeAt)
		assert(s.phase == "Active", `expected Active, got {s.phase}`)
		return s, activeAt
	end

	local function hit(state: any, victim: number, by: number, at: number): (any, { any })
		return step(state, { kind = "hits", hits = { { victim = victim, by = by, at = at } } }, at)
	end

	local FFA3 = { { userId = 1 }, { userId = 2 }, { userId = 3 } }
	local TDM4 = {
		{ userId = 1, team = "Red" },
		{ userId = 2, team = "Red" },
		{ userId = 3, team = "Blue" },
		{ userId = 4, team = "Blue" },
	}

	-- Phases ---------------------------------------------------------------------------------------------------------

	t.test("waits for every arrival, then counts down, then Active for matchSeconds", function()
		local s = MatchRules.new(MATCH_ID, "ffa", FFA3, T0, M)
		expect.equal(s.phase, "Waiting")
		s = step(s, { kind = "arrived", userId = 1 }, T0 + 1)
		s = step(s, { kind = "arrived", userId = 2 }, T0 + 2)
		expect.equal(s.phase, "Waiting")
		local fx
		s, fx = step(s, { kind = "arrived", userId = 3 }, T0 + 3)
		expect.equal(s.phase, "Countdown")
		expect.equal(kinds(fx, "phase")[1].endsAt, T0 + 3 + M.countdownSeconds)
		s = step(s, { kind = "tick" }, T0 + 3 + M.countdownSeconds)
		expect.equal(s.phase, "Active")
		expect.equal(s.phaseEndsAt, T0 + 3 + M.countdownSeconds + M.Modes.ffa.matchSeconds)
		expect.truthy(MatchRules.isLive(s))
	end)

	-- Round 1 of the match screens (2026-10-26): the intro's cards play at least introMinSeconds.
	t.test("Waiting lasts at least introMinSeconds, even when everyone is in at once", function()
		local cfg = matchWith(nil, nil, { introMinSeconds = 1.7 })
		local s = MatchRules.new(MATCH_ID, "ffa", FFA3, T0, cfg)
		for _, e in FFA3 do
			s = step(s, { kind = "arrived", userId = e.userId }, T0)
		end
		expect.equal(s.phase, "Waiting")
		s = step(s, { kind = "tick" }, T0 + 1.6)
		expect.equal(s.phase, "Waiting")
		local fx
		s, fx = step(s, { kind = "tick" }, T0 + 1.7)
		expect.equal(s.phase, "Countdown")
		expect.equal(kinds(fx, "phase")[1].startedAt, T0 + 1.7)
	end)

	t.test("the wait times out: players who never arrived are left out; under minPlayers cancels", function()
		local s = MatchRules.new(MATCH_ID, "ffa", FFA3, T0, M)
		s = step(s, { kind = "arrived", userId = 1 }, T0)
		s = step(s, { kind = "arrived", userId = 2 }, T0)
		s = step(s, { kind = "tick" }, T0 + M.waitSeconds)
		expect.equal(s.phase, "Countdown")
		expect.falsy(MatchRules.participant(s, 3).present)

		local lonely = MatchRules.new(MATCH_ID, "ffa", FFA3, T0, M)
		lonely = step(lonely, { kind = "arrived", userId = 1 }, T0)
		local fx
		lonely, fx = step(lonely, { kind = "tick" }, T0 + M.waitSeconds)
		expect.equal(lonely.phase, "Result")
		expect.equal(lonely.outcome.kind, "cancelled")
		expect.equal(lonely.outcome.reason, "notEnoughPlayers")
		expect.equal(#kinds(fx, "ended"), 1)
	end)

	t.test("bots count as arrived; a TDM team with nobody present cancels", function()
		local s = MatchRules.new(MATCH_ID, "ffa", { { userId = 1 }, { userId = -1, isBot = true } }, T0, M)
		s = step(s, { kind = "arrived", userId = 1 }, T0)
		expect.equal(s.phase, "Countdown")

		local tdm = MatchRules.new(MATCH_ID, "tdm", TDM4, T0, M)
		tdm = step(tdm, { kind = "arrived", userId = 1 }, T0)
		tdm = step(tdm, { kind = "arrived", userId = 2 }, T0)
		tdm = step(tdm, { kind = "tick" }, T0 + M.waitSeconds)
		expect.equal(tdm.outcome.kind, "cancelled")
	end)

	t.test("Result lasts resultSeconds, then Closed with a closed effect", function()
		local s = MatchRules.new(MATCH_ID, "ffa", FFA3, T0, M)
		s = step(s, { kind = "tick" }, T0 + M.waitSeconds) -- nobody arrived: cancelled
		expect.equal(s.phase, "Result")
		local fx
		s, fx = step(s, { kind = "tick" }, T0 + M.waitSeconds + M.resultSeconds)
		expect.equal(s.phase, "Closed")
		expect.truthy(s.closed)
		expect.equal(#kinds(fx, "closed"), 1)
	end)

	-- Hits, respawn, protection --------------------------------------------------------------------------------------

	t.test("FFA: one hit knocks out; back after respawnSeconds with spawnProtectSeconds of protection", function()
		local s, a = live("ffa", FFA3)
		local fx
		s, fx = hit(s, 2, 1, a + 10)
		local ko = kinds(fx, "ko")[1]
		expect.equal(ko.victim, 2)
		expect.equal(ko.by, 1)
		expect.equal(ko.cause, "hit")
		expect.falsy(MatchRules.participant(s, 2).alive)
		expect.equal(MatchRules.participant(s, 1).kos, 1)
		expect.equal(MatchRules.participant(s, 2).knockedOut, 1)

		s, fx = step(s, { kind = "tick" }, a + 10 + M.respawnSeconds - 0.1)
		expect.equal(#kinds(fx, "respawn"), 0)
		s, fx = step(s, { kind = "tick" }, a + 10 + M.respawnSeconds)
		local back = kinds(fx, "respawn")[1]
		expect.equal(back.userId, 2)
		expect.equal(back.protectUntil, a + 10 + M.respawnSeconds + M.spawnProtectSeconds)

		local protectedAt = a + 10 + M.respawnSeconds + M.spawnProtectSeconds - 0.5
		s, fx = hit(s, 2, 1, protectedAt)
		expect.equal(#kinds(fx, "ko"), 0)
		s, fx = hit(s, 2, 1, protectedAt + 1)
		expect.equal(#kinds(fx, "ko"), 1)
	end)

	t.test("hits on oneself, by unknown players, on a knocked-out player or before Active are ignored", function()
		local s = MatchRules.new(MATCH_ID, "ffa", FFA3, T0, M)
		for _, e in FFA3 do
			s = step(s, { kind = "arrived", userId = e.userId }, T0)
		end
		local fx
		s, fx = hit(s, 2, 1, T0 + 1) -- Countdown
		expect.equal(#kinds(fx, "ko"), 0)
		local a = T0 + M.countdownSeconds
		s, fx = hit(s, 1, 1, a + 1)
		expect.equal(#kinds(fx, "ko"), 0)
		s, fx = hit(s, 1, 99, a + 1)
		expect.equal(#kinds(fx, "ko"), 0)
		s, fx = hit(s, 2, 1, a + 2)
		expect.equal(#kinds(fx, "ko"), 1)
		s, fx = hit(s, 2, 3, a + 2.5)
		expect.equal(#kinds(fx, "ko"), 0)
		s, fx = step(s, { kind = "hits", hits = { { victim = "2", by = 1, at = a + 3 }, "junk" } }, a + 3)
		expect.equal(#kinds(fx, "ko"), 0)
	end)

	t.test("hits of one step apply in impact order", function()
		local s, a = live("ffa", FFA3)
		local fx
		s, fx = step(s, {
			kind = "hits",
			hits = { { victim = 1, by = 2, at = a + 5.2 }, { victim = 2, by = 1, at = a + 5.1 } },
		}, a + 5.3)
		local kos = kinds(fx, "ko")
		expect.equal(#kos, 2) -- 2's throw was already flying: it still knocks 1 out
		expect.equal(kos[1].victim, 2)
		expect.equal(kos[2].victim, 1)
	end)

	t.test("FFA: the first to koTarget K.O.s wins at once", function()
		local cfg = matchWith("ffa", { koTarget = 2 })
		local s, a = live("ffa", FFA3, cfg)
		s = hit(s, 2, 1, a + 1)
		local fx
		s, fx = hit(s, 3, 1, a + 2)
		expect.equal(s.outcome.kind, "win")
		expect.equal(s.outcome.reason, "koTarget")
		expect.equal(s.outcome.winnerUserId, 1)
		expect.deepEqual(s.outcome.winners, { 1 })
		expect.equal(s.phase, "Result")
		expect.equal(#kinds(fx, "ended"), 1)
		s, fx = hit(s, 1, 2, a + 6) -- after the end: ignored
		expect.equal(#kinds(fx, "ko"), 0)
	end)

	t.test("FFA time-up: the single leader wins", function()
		local s, a = live("ffa", FFA3)
		s = hit(s, 2, 1, a + 1)
		s = step(s, { kind = "tick" }, a + M.Modes.ffa.matchSeconds)
		expect.equal(s.outcome.reason, "timeUp")
		expect.equal(s.outcome.winnerUserId, 1)
	end)

	t.test("FFA tie at time-up: overtime until one player alone leads", function()
		local s, a = live("ffa", FFA3)
		s = hit(s, 3, 1, a + 1)
		s = hit(s, 3, 2, a + 1 + M.respawnSeconds + M.spawnProtectSeconds + 1) -- 1 and 2 tied on 1
		local endAt = a + M.Modes.ffa.matchSeconds
		s = step(s, { kind = "tick" }, endAt)
		expect.equal(s.phase, "Overtime")
		expect.falsy(s.ended)
		s = hit(s, 1, 3, endAt + 1) -- 3 scores: 1, 2 and 3 all on 1, still tied
		expect.equal(s.phase, "Overtime")
		s = hit(s, 2, 3, endAt + 2) -- 3 alone on 2
		expect.equal(s.outcome.reason, "overtime")
		expect.equal(s.outcome.winnerUserId, 3)
	end)

	t.test("overtime with no winner ends as a draw after overtimeMaxSeconds", function()
		local s, a = live("ffa", FFA3)
		local endAt = a + M.Modes.ffa.matchSeconds
		s = step(s, { kind = "tick" }, endAt)
		expect.equal(s.phase, "Overtime")
		s = step(s, { kind = "tick" }, endAt + M.overtimeMaxSeconds)
		expect.equal(s.outcome.kind, "draw")
		expect.equal(s.outcome.reason, "overtimeTimeout")
		expect.equal(#s.outcome.winners, 3)
		expect.equal(s.outcome.activeSeconds, M.Modes.ffa.matchSeconds + M.overtimeMaxSeconds)
	end)

	t.test("FFA: when only one player is left they win; leaving players never respawn", function()
		local s, a = live("ffa", FFA3)
		s = hit(s, 3, 1, a + 1)
		s = step(s, { kind = "leave", userId = 3 }, a + 2)
		local fx
		s, fx = step(s, { kind = "tick" }, a + 10)
		expect.equal(#kinds(fx, "respawn"), 0)
		expect.falsy(s.ended)
		s = step(s, { kind = "leave", userId = 2 }, a + 11)
		expect.equal(s.outcome.reason, "lastPlayer")
		expect.equal(s.outcome.winnerUserId, 1)
	end)

	-- Team Deathmatch ------------------------------------------------------------------------------------------------

	t.test("TDM: teammates can't hit each other", function()
		local s, a = live("tdm", TDM4)
		expect.falsy(MatchRules.canBeHit(s, 2, a + 1, 1))
		expect.truthy(MatchRules.canBeHit(s, 3, a + 1, 1))
		local fx
		s, fx = hit(s, 2, 1, a + 1)
		expect.equal(#kinds(fx, "ko"), 0)
	end)

	t.test("TDM: every K.O. scores one for the other team (the victim respawns); first to koTarget wins", function()
		local cfg = matchWith("tdm", { koTarget = 2 })
		local s, a = live("tdm", TDM4, cfg)
		local fx
		s, fx = hit(s, 3, 1, a + 1)
		expect.deepEqual(s.teamScore, { Red = 1, Blue = 0 })
		expect.deepEqual(kinds(fx, "teamScore"), { { kind = "teamScore", team = "Red", score = 1 } })
		expect.equal(MatchRules.participant(s, 3).respawnAt, a + 1 + M.respawnSeconds)
		expect.falsy(MatchRules.participant(s, 3).out)
		expect.falsy(s.ended)
		s, fx = hit(s, 4, 2, a + 2)
		expect.equal(s.outcome.kind, "win")
		expect.equal(s.outcome.reason, "koTarget")
		expect.equal(s.outcome.winnerTeam, "Red")
		table.sort(s.outcome.winners)
		expect.deepEqual(s.outcome.winners, { 1, 2 })
	end)

	t.test("TDM time-up: the higher score wins; a tie goes to overtime where the next K.O.'s team wins", function()
		local s, a = live("tdm", TDM4)
		s = hit(s, 3, 1, a + 1)
		s = step(s, { kind = "tick" }, a + M.Modes.tdm.matchSeconds)
		expect.equal(s.outcome.reason, "timeUp")
		expect.equal(s.outcome.winnerTeam, "Red")

		local tie, b = live("tdm", TDM4)
		local endAt = b + M.Modes.tdm.matchSeconds
		tie = step(tie, { kind = "tick" }, endAt)
		expect.equal(tie.phase, "Overtime")
		tie = hit(tie, 1, 4, endAt + 3)
		expect.equal(tie.outcome.reason, "overtime")
		expect.equal(tie.outcome.winnerTeam, "Blue")
	end)

	t.test("TDM: a team whose players all leave is wiped", function()
		local s, a = live("tdm", TDM4)
		s = step(s, { kind = "leave", userId = 3 }, a + 1)
		expect.falsy(s.ended)
		s = step(s, { kind = "leave", userId = 4 }, a + 2)
		expect.equal(s.outcome.winnerTeam, "Red")
	end)

	-- Storm ------------------------------------------------------------------------------------------------------------

	t.test("TDM storm: barFillSeconds in the storm is a storm K.O. the other team scores; inside it drains", function()
		local s, a = live("tdm", TDM4)
		local start = a + M.Storm.stormStartSeconds
		local inStorm = { [3] = true }
		local fx
		s = step(s, { kind = "storm", inStorm = inStorm }, start)
		s = step(s, { kind = "storm", inStorm = inStorm }, start + 2)
		expect.near(MatchRules.participant(s, 3).stormBar, 2 / M.Storm.barFillSeconds, 1e-6)
		local drained = start + 2 + M.Storm.barDrainSeconds / 3
		s = step(s, { kind = "storm", inStorm = {} }, drained)
		expect.near(MatchRules.participant(s, 3).stormBar, 2 / M.Storm.barFillSeconds - 1 / 3, 1e-6)
		s = step(s, { kind = "storm", inStorm = {} }, drained + M.Storm.barDrainSeconds) -- empty again
		expect.equal(MatchRules.participant(s, 3).stormBar, 0)
		local again = drained + M.Storm.barDrainSeconds + 1
		s = step(s, { kind = "storm", inStorm = inStorm }, again)
		expect.truthy(MatchRules.participant(s, 3).alive)
		s, fx = step(s, { kind = "storm", inStorm = inStorm }, again + M.Storm.barFillSeconds)
		local ko = kinds(fx, "ko")[1]
		expect.equal(ko.victim, 3)
		expect.equal(ko.cause, "storm")
		expect.equal(ko.by, nil)
		expect.deepEqual(s.teamScore, { Red = 1, Blue = 0 })
		expect.equal(MatchRules.participant(s, 1).stormBar, 0)
	end)

	t.test("the storm does nothing before stormStartSeconds or in FFA", function()
		local s, a = live("tdm", TDM4)
		s = step(s, { kind = "storm", inStorm = { [3] = true } }, a + 10)
		s = step(s, { kind = "storm", inStorm = { [3] = true } }, a + 20)
		expect.equal(MatchRules.participant(s, 3).stormBar, 0)

		local ffa, b = live("ffa", FFA3)
		local start = b + M.Storm.stormStartSeconds
		ffa = step(ffa, { kind = "storm", inStorm = { [1] = true } }, start)
		ffa = step(ffa, { kind = "storm", inStorm = { [1] = true } }, start + 10)
		expect.truthy(MatchRules.participant(ffa, 1).alive)
		expect.equal(MatchRules.participant(ffa, 1).stormBar, 0)
	end)

	t.test("TDM overtime: a storm K.O. counts for the other team", function()
		local cfg = matchWith("tdm", { matchSeconds = M.Storm.stormStartSeconds + 10 })
		local s, a = live("tdm", TDM4, cfg)
		local endAt = a + M.Storm.stormStartSeconds + 10
		s = step(s, { kind = "tick" }, endAt)
		expect.equal(s.phase, "Overtime")
		s = step(s, { kind = "storm", inStorm = { [2] = true } }, endAt + 1)
		s = step(s, { kind = "storm", inStorm = { [2] = true } }, endAt + 1 + M.Storm.barFillSeconds)
		expect.equal(s.outcome.reason, "overtime")
		expect.equal(s.outcome.winnerTeam, "Blue")
	end)

	-- Power-ups ------------------------------------------------------------------------------------------------------

	t.test("a shield blocks one hit and is used up; it ends after its seconds", function()
		local s, a = live("ffa", FFA3)
		local fx
		s, fx = step(s, { kind = "pickup", userId = 2, power = "shield" }, a + 1)
		expect.equal(kinds(fx, "buff")[1].untilAt, a + 1 + M.PowerUps.kinds.shield.seconds)
		s, fx = hit(s, 2, 1, a + 2)
		expect.equal(#kinds(fx, "shieldBlocked"), 1)
		expect.equal(#kinds(fx, "ko"), 0)
		expect.falsy(MatchRules.hasBuff(s, 2, "shield", a + 2))
		s, fx = hit(s, 2, 1, a + 3)
		expect.equal(#kinds(fx, "ko"), 1)

		local late, b = live("ffa", FFA3)
		late = step(late, { kind = "pickup", userId = 2, power = "shield" }, b + 1)
		late, fx = hit(late, 2, 1, b + 1 + M.PowerUps.kinds.shield.seconds)
		expect.equal(#kinds(fx, "ko"), 1)
	end)

	t.test("timed power-ups last their seconds, ult charge is an effect, a K.O. clears buffs", function()
		local s, a = live("ffa", FFA3)
		local fx
		s, fx = step(s, { kind = "pickup", userId = 1, power = "dashBoost" }, a + 1)
		expect.equal(kinds(fx, "pickup")[1].power, "dashBoost")
		expect.truthy(MatchRules.hasBuff(s, 1, "dashBoost", a + 1 + M.PowerUps.kinds.dashBoost.seconds - 0.01))
		expect.falsy(MatchRules.hasBuff(s, 1, "dashBoost", a + 1 + M.PowerUps.kinds.dashBoost.seconds))
		s, fx = step(s, { kind = "pickup", userId = 1, power = "ultCharge" }, a + 2)
		expect.equal(kinds(fx, "ultCharge")[1].fraction, M.PowerUps.kinds.ultCharge.ultFraction)
		s = step(s, { kind = "pickup", userId = 1, power = "speed" }, a + 3)
		s = hit(s, 1, 2, a + 4)
		expect.falsy(MatchRules.hasBuff(s, 1, "speed", a + 4))
		s, fx = step(s, { kind = "pickup", userId = 1, power = "speed" }, a + 5) -- knocked out: ignored
		expect.equal(#fx, 0)
		s, fx = step(s, { kind = "pickup", userId = 2, power = "nope" }, a + 5)
		expect.equal(#fx, 0)
	end)

	-- Snapshots and ends -----------------------------------------------------------------------------------------------

	t.test("step never modifies the state it is given", function()
		local s, a = live("tdm", TDM4)
		local before = deepCopy(s)
		local after = hit(s, 3, 1, a + 1)
		after = step(after, { kind = "pickup", userId = 1, power = "speed" }, a + 2)
		expect.deepEqual(s, before)
		expect.equal(MatchRules.participant(after, 1).kos, 1)
	end)

	t.test("shutdown voids and closes at once; nothing happens after it", function()
		local s, a = live("ffa", FFA3)
		local fx
		s, fx = step(s, { kind = "shutdown" }, a + 1)
		expect.equal(s.outcome.kind, "void")
		expect.equal(s.phase, "Closed")
		expect.truthy(s.closed)
		expect.equal(#kinds(fx, "closed"), 1)
		s, fx = hit(s, 2, 1, a + 2)
		expect.equal(#fx, 0)
	end)

	t.test("standings: most K.O.s, then fewest times knocked out, then entrant order", function()
		local s, a = live("ffa", FFA3)
		s = hit(s, 2, 3, a + 1)
		local list = MatchRules.standings(s)
		expect.equal(list[1].userId, 3)
		expect.equal(list[2].userId, 1)
		expect.equal(list[3].userId, 2)
		expect.equal(MatchRules.activeSeconds(s, a + 30), 30)
	end)

	-- Out of bounds (jayyyyy 2026-10-15: falling off the map "counts as a knockout") ---------------------------------

	t.test(
		"oob: a K.O. with no attacker that respawns; in TDM the other team scores; ignored when down or not live",
		function()
			local s, a = live("ffa", FFA3)
			local fx
			s, fx = step(s, { kind = "oob", userId = 2 }, a + 1)
			local ko = kinds(fx, "ko")[1]
			expect.equal(ko.victim, 2)
			expect.equal(ko.by, nil)
			expect.equal(ko.cause, "outOfBounds")
			expect.equal(MatchRules.participant(s, 2).knockedOut, 1)
			expect.equal(MatchRules.participant(s, 1).kos + MatchRules.participant(s, 3).kos, 0)
			s, fx = step(s, { kind = "oob", userId = 2 }, a + 2) -- already down
			expect.equal(#kinds(fx, "ko"), 0)
			s, fx = step(s, { kind = "tick" }, a + 1 + M.respawnSeconds)
			expect.equal(kinds(fx, "respawn")[1].userId, 2)

			local tdm, b = live("tdm", TDM4)
			tdm = step(tdm, { kind = "oob", userId = 3 }, b + 1)
			expect.deepEqual(tdm.teamScore, { Red = 1, Blue = 0 })

			local early = MatchRules.new(MATCH_ID, "ffa", FFA3, T0, M)
			for _, e in FFA3 do
				early = step(early, { kind = "arrived", userId = e.userId }, T0)
			end
			early, fx = step(early, { kind = "oob", userId = 1 }, T0 + 1) -- Countdown: not live
			expect.equal(#kinds(fx, "ko"), 0)
		end
	)

	t.test("oob in TDM overtime counts for the other team", function()
		local s, a = live("tdm", TDM4)
		local endAt = a + M.Modes.tdm.matchSeconds
		s = step(s, { kind = "tick" }, endAt)
		expect.equal(s.phase, "Overtime")
		s = step(s, { kind = "oob", userId = 1 }, endAt + 1)
		expect.equal(s.outcome.reason, "overtime")
		expect.equal(s.outcome.winnerTeam, "Blue")
	end)

	-- Match bots (2026-10-17): `empty` voids the match (MatchService sends it once only bots are left in it).
	t.test("empty voids the match at once (reason empty); after the end it changes nothing", function()
		local s, a =
			live("ffa", { { userId = 1 }, { userId = -200001, isBot = true }, { userId = -200002, isBot = true } })
		s = step(s, { kind = "leave", userId = 1 }, a + 5)
		expect.equal(s.ended, false) -- two bots are still present
		local fx
		s, fx = step(s, { kind = "empty" }, a + 5)
		expect.equal(s.outcome.kind, "void")
		expect.equal(s.outcome.reason, "empty")
		expect.equal(s.phase, "Closed")
		expect.equal(#kinds(fx, "closed"), 1)
		local done = live("ffa", FFA3)
		done = step(done, { kind = "shutdown" }, a + 1)
		local _, again = step(done, { kind = "empty" }, a + 2)
		expect.equal(#again, 0)
	end)
end
