--!strict
-- DuelRules_Test: unit tests for ServerScriptService.Server.Logic.DuelRules. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §5.2, §5.4): phases Preparing (3 s or both streamed) -> Positioning (both positioned, else
-- Cancelled at 5 s) -> Countdown (3 s) -> Active (120 s) -> time-up: more lives wins, tied -> SuddenDeath (30 s, next
-- hit wins, cooldowns × 0.8; 0 s -> draw), SuddenDeath timeout -> draw -> Result (4 s) -> Returning -> closed.
-- Every edge-case row of §5.4: forfeit, leave, death, missing, out of bounds, restart, shutdown, match-tick error,
-- lease expiry and late remote spam, in each phase column. A bail before Active or before 20 s of Active cancels
-- (innocent requeued at the front, bailer 15 s cooldown); from 20 s it is a win for the other side. Two final hits in
-- one step: the earlier impact wins, an exact tie is a draw. `ended` happens exactly once; step never modifies the
-- state it is given. Time comes only from the test (no wall clock). Feature 1 (2026-10-11): a forced hit (a caught
-- throw's burst) costs the life even inside the victim's invulnerability, and starts a new invulnerability as any hit;
-- after the end it is ignored like any hit.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local T0 = 1000
local MATCH_ID = "11111111-2222-3333-4444-555555555555"
local USER_A, USER_B = 101, 202

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
	local DuelRules = t.requireServer("Logic/DuelRules")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local RULES = Config.Duel.Rules

	-- A copy of Config.Duel with some Rules replaced.
	local function duelWith(overrides: { [string]: any }): any
		local duel = deepCopy(Config.Duel)
		for key, value in overrides do
			duel.Rules[key] = value
		end
		return duel
	end

	local function newMatch(duel: any?): any
		return DuelRules.new(MATCH_ID, {
			A = { userId = USER_A, rewardsEnabled = true },
			B = { userId = USER_B, rewardsEnabled = true },
		}, T0, duel or Config.Duel)
	end

	-- Steps through { {event, now}, ... }; returns the final state and every effect in order.
	local function run(state: any, steps: { { any } }): (any, { any })
		local all: { any } = {}
		for _, item in steps do
			local effects
			state, effects = DuelRules.step(state, item[1], item[2])
			for _, effect in effects do
				table.insert(all, effect)
			end
		end
		return state, all
	end

	local function find(effects: { any }, kind: string, side: string?): any
		for _, effect in effects do
			if effect.kind == kind and (side == nil or effect.side == side) then
				return effect
			end
		end
		return nil
	end

	local function count(effects: { any }, kind: string): number
		local n = 0
		for _, effect in effects do
			if effect.kind == kind then
				n += 1
			end
		end
		return n
	end

	local function toPositioning(duel: any?): any
		return (
			run(newMatch(duel), {
				{ { kind = "streamed", side = "A" }, T0 + 0.2 },
				{ { kind = "streamed", side = "B" }, T0 + 0.4 },
			})
		)
	end

	local function toCountdown(duel: any?): any
		return (
			run(toPositioning(duel), {
				{ { kind = "positioned", side = "A" }, T0 + 1 },
				{ { kind = "positioned", side = "B" }, T0 + 1.2 },
			})
		)
	end

	-- Returns the match in Active and the time Active began.
	local function toActive(duel: any?): (any, number)
		local s = toCountdown(duel)
		local startAt = s.phaseEndsAt
		s = run(s, { { { kind = "tick" }, startAt } })
		return s, startAt
	end

	local function hit(victim: string, at: number): any
		return { kind = "hit", victim = victim, at = at }
	end

	local function expectCancelled(s: any, bailer: string?, requeue: string?)
		expect.equal(s.phase, "Cancelled")
		expect.truthy(s.ended)
		expect.equal(s.outcome.kind, "cancelled")
		expect.equal(s.outcome.bailer, bailer)
		expect.equal(s.outcome.requeue, requeue)
	end

	-- Phases and timers ------------------------------------------------------------------------------------------------

	t.test("a new match is in Preparing with full lives and a 3 s timer", function()
		local s = newMatch()
		expect.equal(s.phase, "Preparing")
		expect.equal(s.phaseEndsAt, T0 + RULES.PreparingTimeoutSeconds)
		expect.equal(s.participants.A.lives, RULES.Lives)
		expect.equal(s.participants.B.lives, RULES.Lives)
		expect.equal(s.participants.A.userId, USER_A)
		expect.falsy(s.ended)
		expect.falsy(DuelRules.isLive(s))
	end)

	t.test("Preparing -> Positioning when both finished streaming", function()
		local s, effects = run(newMatch(), {
			{ { kind = "streamed", side = "A" }, T0 + 0.2 },
		})
		expect.equal(s.phase, "Preparing")
		s, effects = run(s, { { { kind = "streamed", side = "B" }, T0 + 0.4 } })
		expect.equal(s.phase, "Positioning")
		local phase = find(effects, "phase")
		expect.equal(phase.phase, "Positioning")
		expect.equal(phase.endsAt, T0 + 0.4 + RULES.PositioningTimeoutSeconds)
	end)

	t.test("Preparing stream timeout: continue to Positioning after 3 s", function()
		local s = run(newMatch(), { { { kind = "tick" }, T0 + 2.9 } })
		expect.equal(s.phase, "Preparing")
		s = run(s, { { { kind = "tick" }, T0 + 3 } })
		expect.equal(s.phase, "Positioning")
		expect.equal(s.phaseStartedAt, T0 + 3)
	end)

	t.test("Positioning -> Countdown -> Active; throws only count from Active", function()
		local s = toCountdown()
		expect.equal(s.phase, "Countdown")
		expect.equal(s.phaseEndsAt, T0 + 1.2 + RULES.CountdownSeconds)
		s = run(s, { { { kind = "throwAccepted", side = "A" }, T0 + 2 } })
		expect.equal(s.participants.A.throws, 0)
		local active, startAt = toActive()
		expect.equal(active.phase, "Active")
		expect.equal(active.activeStartedAt, startAt)
		expect.equal(active.phaseEndsAt, startAt + RULES.MatchSeconds)
		expect.truthy(DuelRules.isLive(active))
		active = run(active, { { { kind = "throwAccepted", side = "A" }, startAt + 1 } })
		expect.equal(active.participants.A.throws, 1)
	end)

	t.test("a long hitch runs each due transition at its own deadline", function()
		local s = toCountdown()
		local countdownEnd = s.phaseEndsAt
		s = run(s, { { { kind = "tick" }, countdownEnd + 5 } })
		expect.equal(s.phase, "Active")
		expect.equal(s.activeStartedAt, countdownEnd)
	end)

	t.test("Positioning timeout with one side not positioned: Cancelled, that side is the bailer", function()
		local s, effects = run(toPositioning(), {
			{ { kind = "positioned", side = "A" }, T0 + 1 },
			{ { kind = "tick" }, T0 + 0.4 + RULES.PositioningTimeoutSeconds },
		})
		expectCancelled(s, "B", "A")
		expect.equal(s.outcome.reason, "missing")
		expect.truthy(find(effects, "requeue", "A"))
		expect.equal(find(effects, "notify", "A").key, "duel.opponentLeftEarly")
		expect.equal(find(effects, "requeueCooldown", "B").seconds, RULES.BailRequeueCooldownSeconds)
		expect.equal(find(effects, "requeueCooldown", "A"), nil) -- requeued by the server, no cooldown
	end)

	t.test("Positioning timeout with neither side positioned: Cancelled, nobody blamed or requeued", function()
		local s, effects = run(toPositioning(), { { { kind = "tick" }, T0 + 10 } })
		expectCancelled(s, nil, nil)
		expect.equal(count(effects, "requeue"), 0)
		expect.equal(find(effects, "requeueCooldown", "A").seconds, RULES.RequeueCooldownSeconds)
		expect.equal(find(effects, "requeueCooldown", "B").seconds, RULES.RequeueCooldownSeconds)
	end)

	t.test("time-up with different lives: more lives wins", function()
		local s, startAt = toActive()
		s = run(s, { { hit("A", startAt + 10), startAt + 10 } })
		local effects
		s, effects = run(s, { { { kind = "tick" }, startAt + RULES.MatchSeconds } })
		expect.equal(s.phase, "Result")
		expect.equal(s.outcome.kind, "win")
		expect.equal(s.outcome.winner, "B")
		expect.equal(s.outcome.loser, "A")
		expect.equal(s.outcome.reason, "timeUp")
		expect.equal(s.outcome.endedFrom, "Active")
		expect.equal(s.outcome.activeSeconds, RULES.MatchSeconds)
		expect.equal(s.phaseEndsAt, startAt + RULES.MatchSeconds + RULES.ResultSeconds)
		expect.equal(count(effects, "ended"), 1)
	end)

	t.test("time-up with equal lives: SuddenDeath, faster cooldowns, next hit wins", function()
		local s, startAt = toActive()
		local endAt = startAt + RULES.MatchSeconds
		s = run(s, { { { kind = "tick" }, endAt } })
		expect.equal(s.phase, "SuddenDeath")
		expect.equal(s.phaseEndsAt, endAt + RULES.SuddenDeathSeconds)
		expect.equal(DuelRules.cooldownMultiplier(s), RULES.SuddenDeathCooldownMultiplier)
		expect.falsy(s.ended)
		local effects
		s, effects = run(s, { { hit("B", endAt + 5), endAt + 5 } })
		expect.equal(s.phase, "Result")
		expect.equal(s.outcome.winner, "A")
		expect.equal(s.outcome.reason, "suddenDeath")
		expect.equal(s.outcome.endedFrom, "SuddenDeath")
		expect.equal(s.participants.B.lives, RULES.Lives - 1) -- lives are left, but sudden death ends it
		expect.truthy(find(effects, "lifeLost", "B").eliminated)
		expect.equal(DuelRules.cooldownMultiplier(s), 1)
	end)

	t.test("SuddenDeath timeout: draw", function()
		local s, startAt = toActive()
		local endAt = startAt + RULES.MatchSeconds
		s = run(s, { { { kind = "tick" }, endAt + RULES.SuddenDeathSeconds } })
		expect.equal(s.phase, "Result")
		expect.equal(s.outcome.kind, "draw")
		expect.equal(s.outcome.reason, "suddenDeathTimeout")
		expect.equal(s.outcome.endedFrom, "SuddenDeath")
	end)

	t.test("SuddenDeathSeconds = 0: tied lives at time-up go straight to a draw", function()
		local s, startAt = toActive(duelWith({ SuddenDeathSeconds = 0 }))
		s = run(s, { { { kind = "tick" }, startAt + RULES.MatchSeconds } })
		expect.equal(s.phase, "Result")
		expect.equal(s.outcome.kind, "draw")
		expect.equal(s.outcome.reason, "timeUp")
	end)

	t.test("Result -> Returning after 4 s -> closed when the players are back", function()
		local s, startAt = toActive()
		local endAt = startAt + RULES.MatchSeconds
		s = run(s, { { hit("A", startAt + 1), startAt + 1 }, { { kind = "tick" }, endAt } })
		expect.equal(s.phase, "Result")
		s = run(s, { { { kind = "returned" }, endAt + 1 } })
		expect.falsy(s.closed) -- still in Result: nothing to return yet
		s = run(s, { { { kind = "tick" }, endAt + RULES.ResultSeconds } })
		expect.equal(s.phase, "Returning")
		expect.equal(s.phaseEndsAt, math.huge)
		local effects
		s, effects = run(s, { { { kind = "returned" }, endAt + 6 } })
		expect.truthy(s.closed)
		expect.equal(count(effects, "closed"), 1)
		s, effects = run(s, { { { kind = "returned" }, endAt + 7 } })
		expect.equal(#effects, 0)
	end)

	-- Hits ---------------------------------------------------------------------------------------------------------------

	t.test("three hits: lives 3 -> 0, invulnerability between, elimination wins", function()
		local s, startAt = toActive()
		local invuln = RULES.HitInvulnSeconds
		local effects
		s, effects = run(s, { { hit("B", startAt + 1), startAt + 1 } })
		local lost = find(effects, "lifeLost", "B")
		expect.equal(lost.lives, 2)
		expect.equal(lost.invulnUntil, startAt + 1 + invuln)
		expect.falsy(lost.eliminated)
		expect.equal(s.participants.A.hits, 1)
		s = run(s, { { hit("B", startAt + 3), startAt + 3 } })
		s, effects = run(s, { { hit("B", startAt + 5), startAt + 5 } })
		expect.equal(s.participants.B.lives, 0)
		expect.truthy(find(effects, "lifeLost", "B").eliminated)
		expect.equal(s.phase, "Result")
		expect.equal(s.outcome.winner, "A")
		expect.equal(s.outcome.reason, "eliminated")
		expect.equal(s.participants.A.hits, 3)
	end)

	t.test("a hit inside the victim's invulnerability is ignored", function()
		local s, startAt = toActive()
		s = run(s, { { hit("B", startAt + 1), startAt + 1 } })
		expect.falsy(DuelRules.canBeHit(s, "B", startAt + 2))
		local effects
		s, effects = run(s, { { hit("B", startAt + 2), startAt + 2 } })
		expect.equal(s.participants.B.lives, 2)
		expect.equal(count(effects, "lifeLost"), 0)
		expect.truthy(DuelRules.canBeHit(s, "B", startAt + 1 + RULES.HitInvulnSeconds))
	end)

	t.test("feature 1: a forced hit (a caught throw's burst) lands inside the invulnerability", function()
		local s, startAt = toActive()
		local invuln = RULES.HitInvulnSeconds
		s = run(s, { { hit("B", startAt + 1), startAt + 1 } })
		expect.falsy(DuelRules.canBeHit(s, "B", startAt + 1.2))
		local effects
		s, effects = run(s, {
			{ { kind = "hits", hits = { { victim = "B", at = startAt + 1.2, force = true } } }, startAt + 1.2 },
		})
		expect.equal(s.participants.B.lives, 1)
		local lost = find(effects, "lifeLost", "B")
		expect.truthy(lost ~= nil)
		expect.equal(lost.invulnUntil, startAt + 1.2 + invuln) -- the later of the two invulnerabilities
		expect.equal(s.participants.A.hits, 2)
		-- An unforced hit at the same moment is still ignored.
		s, effects = run(s, { { { kind = "hits", hits = { { victim = "B", at = startAt + 1.3 } } }, startAt + 1.3 } })
		expect.equal(s.participants.B.lives, 1)
		expect.equal(count(effects, "lifeLost"), 0)
		-- After the end, a forced hit is ignored like any hit.
		s = run(s, { { { kind = "forfeit", side = "A" }, startAt + 30 } })
		local ended
		ended, effects = run(s, {
			{ { kind = "hits", hits = { { victim = "B", at = startAt + 31, force = true } } }, startAt + 31 },
		})
		expect.equal(ended.participants.B.lives, 1)
		expect.equal(count(effects, "lifeLost"), 0)
	end)

	t.test("simultaneous KO: two final hits with the same impact time are a draw", function()
		local s, startAt = toActive()
		s = run(s, {
			{ hit("A", startAt + 1), startAt + 1 },
			{ hit("B", startAt + 1), startAt + 1 },
			{ hit("A", startAt + 4), startAt + 4 },
			{ hit("B", startAt + 4), startAt + 4 },
		})
		expect.equal(s.participants.A.lives, 1)
		expect.equal(s.participants.B.lives, 1)
		local effects
		s, effects = run(s, {
			{
				{ kind = "hits", hits = { { victim = "A", at = startAt + 8 }, { victim = "B", at = startAt + 8 } } },
				startAt + 8,
			},
		})
		expect.equal(s.phase, "Result")
		expect.equal(s.outcome.kind, "draw")
		expect.equal(s.outcome.reason, "doubleKo")
		expect.equal(count(effects, "ended"), 1)
	end)

	t.test("two final hits in one step: the earlier impact time wins, the later is a no-op", function()
		local s, startAt = toActive()
		s = run(s, {
			{ hit("A", startAt + 1), startAt + 1 },
			{ hit("B", startAt + 1), startAt + 1 },
			{ hit("A", startAt + 4), startAt + 4 },
			{ hit("B", startAt + 4), startAt + 4 },
		})
		-- Listed out of order on purpose: B's impact is earlier.
		local effects
		s, effects = run(s, {
			{
				{
					kind = "hits",
					hits = { { victim = "A", at = startAt + 8.02 }, { victim = "B", at = startAt + 8.01 } },
				},
				startAt + 8.03,
			},
		})
		expect.equal(s.outcome.kind, "win")
		expect.equal(s.outcome.winner, "A")
		expect.equal(s.outcome.at, startAt + 8.01)
		expect.equal(s.participants.A.lives, 1) -- the later hit never landed
		expect.equal(count(effects, "lifeLost"), 1)
	end)

	t.test("hits before Active and after the end are ignored", function()
		local s = toCountdown()
		local effects
		s, effects = run(s, { { hit("A", T0 + 2), T0 + 2 } })
		expect.equal(s.participants.A.lives, RULES.Lives)
		expect.equal(#effects, 0)
		local active, startAt = toActive()
		active = run(active, { { { kind = "forfeit", side = "A" }, startAt + 30 } })
		local after = run(active, { { hit("A", startAt + 31), startAt + 31 } })
		expect.equal(after.participants.A.lives, RULES.Lives)
		expect.equal(after.outcome, active.outcome)
	end)

	t.test("a hit landing after the Active deadline: time-up resolves first", function()
		-- Tied lives: SuddenDeath begins at the deadline and the late hit wins it.
		local s, startAt = toActive()
		local endAt = startAt + RULES.MatchSeconds
		s = run(s, { { hit("A", endAt + 0.01), endAt + 0.02 } })
		expect.equal(s.outcome.reason, "suddenDeath")
		expect.equal(s.outcome.winner, "B")
		-- Different lives: the match is already decided at the deadline, the hit is ignored.
		local d, startD = toActive()
		d = run(d, { { hit("A", startD + 1), startD + 1 } })
		d = run(d, { { hit("B", startD + RULES.MatchSeconds), startD + RULES.MatchSeconds + 0.01 } })
		expect.equal(d.outcome.reason, "timeUp")
		expect.equal(d.outcome.winner, "B")
		expect.equal(d.participants.B.lives, RULES.Lives)
	end)

	t.test(
		"a hit just before the deadline reported just after it: the hit lands, then time-up in the same step",
		function()
			local s, startAt = toActive()
			local endAt = startAt + RULES.MatchSeconds
			local effects
			s, effects = run(s, { { hit("A", endAt - 0.5), endAt + 0.1 } })
			expect.equal(s.participants.A.lives, RULES.Lives - 1)
			expect.equal(s.phase, "Result")
			expect.equal(s.outcome.reason, "timeUp")
			expect.equal(s.outcome.winner, "B")
			expect.equal(s.outcome.at, endAt) -- at the deadline, not at the step
			expect.equal(count(effects, "ended"), 1)
			-- No hit landed (all ignored or none sent): due timers still run.
			local quiet, quietStart = toActive()
			quiet = run(quiet, { { { kind = "hits", hits = {} }, quietStart + RULES.MatchSeconds } })
			expect.equal(quiet.phase, "SuddenDeath")
		end
	)

	-- Forfeit ------------------------------------------------------------------------------------------------------

	t.test("forfeit before Active (each phase): Cancelled, other requeued at the front, bailer 15 s", function()
		local starts: { [string]: any } = {
			Preparing = newMatch(),
			Positioning = toPositioning(),
			Countdown = toCountdown(),
		}
		for phase, start in starts do
			expect.equal(start.phase, phase)
			local s, effects = run(start, { { { kind = "forfeit", side = "A" }, T0 + 1.5 } })
			expectCancelled(s, "A", "B")
			expect.equal(s.outcome.reason, "forfeit")
			expect.equal(s.outcome.endedFrom, phase)
			expect.truthy(find(effects, "requeue", "B"))
			expect.equal(find(effects, "notify", "B").key, "duel.opponentLeftEarly")
			expect.equal(find(effects, "requeueCooldown", "A").seconds, RULES.BailRequeueCooldownSeconds)
		end
	end)

	t.test("bail timing: a forfeit just before 20 s of Active cancels, at 20 s it is a win", function()
		local early, startAt = toActive()
		local s, effects =
			run(early, { { { kind = "forfeit", side = "A" }, startAt + RULES.EarlyForfeitSeconds - 0.01 } })
		expectCancelled(s, "A", "B")
		expect.equal(s.outcome.endedFrom, "Active")
		expect.truthy(find(effects, "requeue", "B"))
		expect.equal(find(effects, "notify", "B"), nil) -- the duel had started: no "left before it started" toast
		expect.equal(find(effects, "requeueCooldown", "A").seconds, RULES.BailRequeueCooldownSeconds)

		local late, lateStart = toActive()
		local w, winEffects = run(late, { { { kind = "forfeit", side = "A" }, lateStart + RULES.EarlyForfeitSeconds } })
		expect.equal(w.phase, "Result")
		expect.equal(w.outcome.kind, "win")
		expect.equal(w.outcome.winner, "B")
		expect.equal(w.outcome.reason, "opponentLeft")
		expect.equal(w.outcome.activeSeconds, RULES.EarlyForfeitSeconds)
		expect.equal(count(winEffects, "requeue"), 0)
		expect.equal(find(winEffects, "requeueCooldown", "A").seconds, RULES.RequeueCooldownSeconds)
		expect.equal(find(winEffects, "requeueCooldown", "B").seconds, RULES.RequeueCooldownSeconds)
	end)

	t.test("forfeit in SuddenDeath is a win for the other side", function()
		local s, startAt = toActive()
		s = run(s, { { { kind = "tick" }, startAt + RULES.MatchSeconds } })
		s = run(s, { { { kind = "forfeit", side = "B" }, startAt + RULES.MatchSeconds + 2 } })
		expect.equal(s.outcome.winner, "A")
		expect.equal(s.outcome.endedFrom, "SuddenDeath")
	end)

	t.test("forfeit in Result or Returning is ignored", function()
		local s, startAt = toActive()
		s = run(s, { { { kind = "forfeit", side = "A" }, startAt + 30 } })
		local outcome = s.outcome
		local again, effects = run(s, { { { kind = "forfeit", side = "B" }, startAt + 31 } })
		expect.equal(#effects, 0)
		expect.equal(again.outcome, outcome)
		local returning = run(s, { { { kind = "tick" }, startAt + 30 + RULES.ResultSeconds } })
		expect.equal(returning.phase, "Returning")
		local _, late = run(returning, { { { kind = "forfeit", side = "B" }, startAt + 40 } })
		expect.equal(#late, 0)
	end)

	-- Leave / disconnect ----------------------------------------------------------------------------------------------

	t.test("leave before Active: Cancelled, the other is requeued with duel.opponentLeftEarly", function()
		local s, effects = run(toCountdown(), { { { kind = "leave", side = "B" }, T0 + 2 } })
		expectCancelled(s, "B", "A")
		expect.equal(s.outcome.reason, "left")
		expect.falsy(s.participants.B.present)
		expect.equal(find(effects, "notify", "A").key, "duel.opponentLeftEarly")
	end)

	t.test("both leave before Active: the first ends it, the second is a no-op (double end)", function()
		local s, effects = run(newMatch(), {
			{ { kind = "leave", side = "A" }, T0 + 1 },
			{ { kind = "leave", side = "B" }, T0 + 1 },
		})
		expectCancelled(s, "A", "B")
		expect.equal(count(effects, "ended"), 1)
		expect.equal(count(effects, "requeue"), 1)
	end)

	t.test("the bailer's opponent is not requeued if it already left the game", function()
		local s = newMatch()
		s.participants.B.present = false -- B's leave was not reported yet
		s = run(s, { { { kind = "forfeit", side = "A" }, T0 + 1 } })
		expectCancelled(s, "A", nil)
	end)

	t.test("leave in Active: before 20 s Cancelled, from 20 s a win; in Result nothing to undo", function()
		local early, startAt = toActive()
		expectCancelled((run(early, { { { kind = "leave", side = "A" }, startAt + 5 } })), "A", "B")
		local late, lateStart = toActive()
		local w = run(late, { { { kind = "leave", side = "A" }, lateStart + 25 } })
		expect.equal(w.outcome.winner, "B")
		expect.equal(w.outcome.reason, "opponentLeft")
		local _, effects = run(w, { { { kind = "leave", side = "B" }, lateStart + 26 } })
		expect.equal(#effects, 0)
	end)

	-- Character dies / removed ---------------------------------------------------------------------------------------

	t.test("death in Preparing waits 5 s for a respawn: respawned in time, the match goes on", function()
		local s = run(newMatch(), {
			{ { kind = "died", side = "A" }, T0 + 0.5 },
			{ { kind = "respawned", side = "A" }, T0 + 4 },
			{ { kind = "tick" }, T0 + 6 },
		})
		expect.falsy(s.ended)
		expect.equal(s.phase, "Positioning")
	end)

	t.test("death in Preparing without a respawn: Cancelled 5 s later, even after entering Positioning", function()
		local wait = Config.Duel.Positioning.RespawnWaitSeconds
		local s = run(newMatch(), {
			{ { kind = "died", side = "A" }, T0 + 0.5 },
			{ { kind = "tick" }, T0 + 0.5 + wait - 0.01 },
		})
		expect.falsy(s.ended)
		expect.equal(s.phase, "Positioning") -- the 3 s stream timeout passed meanwhile
		s = run(s, { { { kind = "tick" }, T0 + 0.5 + wait } })
		expectCancelled(s, "A", "B")
		expect.equal(s.outcome.reason, "died")
		expect.equal(s.outcome.at, T0 + 0.5 + wait)
	end)

	t.test("death in Positioning or Countdown: Cancelled at once", function()
		expectCancelled((run(toPositioning(), { { { kind = "died", side = "B" }, T0 + 1 } })), "B", "A")
		expectCancelled((run(toCountdown(), { { { kind = "died", side = "B" }, T0 + 2 } })), "B", "A")
	end)

	t.test("death in Active counts as a forfeit; in Result it is ignored", function()
		local early, startAt = toActive()
		expectCancelled((run(early, { { { kind = "died", side = "A" }, startAt + 10 } })), "A", "B")
		local late, lateStart = toActive()
		local w = run(late, { { { kind = "died", side = "A" }, lateStart + 21 } })
		expect.equal(w.outcome.winner, "B")
		local _, effects = run(w, { { { kind = "died", side = "B" }, lateStart + 22 } })
		expect.equal(#effects, 0)
	end)

	-- Opponent missing -------------------------------------------------------------------------------------------------

	t.test("missing before Active: Cancelled after 5 s of absence unless found again", function()
		local missingWait = RULES.PositioningTimeoutSeconds
		local found = run(newMatch(), {
			{ { kind = "missing", side = "B" }, T0 + 0.5 },
			{ { kind = "found", side = "B" }, T0 + 2 },
			{ { kind = "streamed", side = "A" }, T0 + 2.1 },
			{ { kind = "streamed", side = "B" }, T0 + 2.2 },
		})
		expect.equal(found.phase, "Positioning")
		expect.falsy(found.ended)
		-- Missing from Preparing on: the 5 s absence ends it before the Positioning timeout would.
		local gone = run(newMatch(), {
			{ { kind = "missing", side = "B" }, T0 + 0.5 },
			{ { kind = "tick" }, T0 + 0.5 + missingWait - 0.01 },
		})
		expect.equal(gone.phase, "Positioning")
		expect.falsy(gone.ended)
		gone = run(gone, { { { kind = "tick" }, T0 + 0.5 + missingWait } })
		expectCancelled(gone, "B", "A")
		expect.equal(gone.outcome.reason, "missing")
		expect.equal(gone.outcome.at, T0 + 0.5 + missingWait)
	end)

	t.test("missing in Countdown and still missing when Active begins: that player bailed", function()
		local s = toCountdown()
		local startAt = s.phaseEndsAt
		s = run(s, {
			{ { kind = "missing", side = "A" }, T0 + 2 },
			{ { kind = "tick" }, startAt },
		})
		expectCancelled(s, "A", "B")
		expect.equal(s.outcome.reason, "missing")
		expect.equal(s.outcome.endedFrom, "Active")
	end)

	t.test("missing in Active: a forfeit by the missing player", function()
		local s, startAt = toActive()
		s = run(s, { { { kind = "missing", side = "A" }, startAt + 40 } })
		expect.equal(s.outcome.winner, "B")
		expect.equal(s.outcome.reason, "opponentLeft")
	end)

	-- Out of bounds --------------------------------------------------------------------------------------------------

	t.test("out of bounds before Active: a silent re-pivot that never counts", function()
		local s, effects = run(toCountdown(), { { { kind = "oob", side = "A" }, T0 + 2 } })
		local repivot = find(effects, "repivot", "A")
		expect.truthy(repivot.silent)
		expect.equal(s.participants.A.outOfBounds, 0)
		-- Positioning: only a side already on its pad is put back.
		local positioning = run(toPositioning(), { { { kind = "positioned", side = "A" }, T0 + 1 } })
		local _, placed = run(positioning, { { { kind = "oob", side = "A" }, T0 + 1.5 } })
		expect.truthy(find(placed, "repivot", "A").silent)
		local _, onTheWay = run(positioning, { { { kind = "oob", side = "B" }, T0 + 1.5 } })
		expect.equal(#onTheWay, 0)
		-- Preparing: nobody is on a pad yet.
		local _, preparing = run(newMatch(), { { { kind = "oob", side = "A" }, T0 + 1 } })
		expect.equal(#preparing, 0)
	end)

	t.test("out of bounds in Active: pivot to the pad, 1 s invulnerability, counted; the 7th forfeits", function()
		local s, startAt = toActive()
		local maxOob = RULES.OutOfBounds.MaxPerMatch
		local effects
		s, effects = run(s, { { { kind = "oob", side = "A" }, startAt + 21 } })
		local repivot = find(effects, "repivot", "A")
		expect.falsy(repivot.silent)
		expect.equal(repivot.count, 1)
		expect.equal(repivot.invulnUntil, startAt + 21 + RULES.OutOfBoundsInvulnSeconds)
		expect.equal(s.participants.A.lives, RULES.Lives - RULES.OutOfBounds.LifePenalty)
		for i = 2, maxOob do
			s = run(s, { { { kind = "oob", side = "A" }, startAt + 21 + i } })
		end
		expect.falsy(s.ended)
		s = run(s, { { { kind = "oob", side = "A" }, startAt + 30 } })
		expect.truthy(s.ended)
		expect.equal(s.outcome.winner, "B")
		local _, after = run(s, { { { kind = "oob", side = "A" }, startAt + 31 } })
		expect.equal(#after, 0)
	end)

	t.test("the 7th out-of-bounds before 20 s of Active cancels instead", function()
		local s, startAt = toActive()
		for i = 1, RULES.OutOfBounds.MaxPerMatch + 1 do
			s = run(s, { { { kind = "oob", side = "B" }, startAt + i } })
		end
		expectCancelled(s, "B", "A")
		expect.equal(s.outcome.reason, "outOfBounds")
	end)

	-- Restart, shutdown, errors, lease -------------------------------------------------------------------------------

	t.test(
		"ServerRestartScheduled: before Active Cancelled without requeue; a match that can finish continues",
		function()
			local s, effects = run(toCountdown(), { { { kind = "restartScheduled", deadline = T0 + 600 }, T0 + 2 } })
			expectCancelled(s, nil, nil)
			expect.equal(s.outcome.reason, "restart")
			expect.equal(count(effects, "requeue"), 0)

			local active, startAt = toActive()
			local worstEnd = startAt + RULES.MatchSeconds + RULES.SuddenDeathSeconds + RULES.ResultSeconds
			local continues = run(active, { { { kind = "restartScheduled", deadline = worstEnd }, startAt + 5 } })
			expect.falsy(continues.ended)
			local voided = run(active, { { { kind = "restartScheduled", deadline = worstEnd - 1 }, startAt + 5 } })
			expect.equal(voided.phase, "Void")
			expect.equal(voided.outcome.kind, "void")
			expect.equal(voided.outcome.reason, "restart")
		end
	)

	t.test("ServerRestartScheduled during Result continues", function()
		local s, startAt = toActive()
		s = run(s, { { { kind = "forfeit", side = "A" }, startAt + 30 } })
		local _, effects = run(s, { { { kind = "restartScheduled", deadline = startAt + 31 }, startAt + 30.5 } })
		expect.equal(#effects, 0)
	end)

	t.test("shutdown (BindToClose) voids every running phase, never Result", function()
		for _, start in { newMatch(), toPositioning(), toCountdown(), (toActive()) } :: { any } do
			local s = run(start, { { { kind = "shutdown" }, T0 + 2 } })
			expect.equal(s.phase, "Void")
			expect.equal(s.outcome.reason, "shutdown")
			expect.equal(s.outcome.requeue, nil)
		end
		local done, startAt = toActive()
		done = run(done, { { { kind = "forfeit", side = "A" }, startAt + 30 } })
		local after = run(done, { { { kind = "shutdown" }, startAt + 31 } })
		expect.equal(after.phase, "Result")
		expect.equal(after.outcome.kind, "win")
	end)

	t.test("an error in the match tick: Void before the end, a forced return after it", function()
		local active, startAt = toActive()
		local voided = run(active, { { { kind = "error" }, startAt + 5 } })
		expect.equal(voided.phase, "Void")
		expect.equal(voided.outcome.reason, "error")
		local result = run(active, { { { kind = "forfeit", side = "A" }, startAt + 30 } })
		local forced, effects = run(result, { { { kind = "error" }, startAt + 31 } })
		expect.equal(forced.phase, "Returning")
		expect.equal(forced.outcome, result.outcome) -- the result stands
		expect.equal(find(effects, "forceReturn").reason, "error")
		local cancelled = run(toCountdown(), { { { kind = "forfeit", side = "A" }, T0 + 2 } })
		local _, cancelledEffects = run(cancelled, { { { kind = "error" }, T0 + 3 } })
		expect.truthy(find(cancelledEffects, "forceReturn"))
	end)

	t.test("lease expired: Void while running, forced return after the end", function()
		local active, startAt = toActive()
		local voided = run(active, { { { kind = "leaseExpired" }, startAt + 5 } })
		expect.equal(voided.phase, "Void")
		expect.equal(voided.outcome.reason, "lease")
		local result = run(active, { { { kind = "forfeit", side = "A" }, startAt + 30 } })
		local _, effects = run(result, { { { kind = "leaseExpired" }, startAt + 31 } })
		expect.equal(find(effects, "forceReturn").reason, "lease")
	end)

	t.test("Void and Cancelled close after the players are returned", function()
		local s = run(newMatch(), { { { kind = "shutdown" }, T0 + 1 } })
		local closed, effects = run(s, { { { kind = "returned" }, T0 + 2 } })
		expect.truthy(closed.closed)
		expect.equal(count(effects, "closed"), 1)
		-- A closed match ignores everything.
		local _, after = run(closed, { { { kind = "error" }, T0 + 3 } })
		expect.equal(#after, 0)
	end)

	-- Exactly once, purity, robustness ---------------------------------------------------------------------------------

	t.test("ended happens exactly once across a whole match with late spam", function()
		local s, startAt = toActive()
		local _, effects = run(s, {
			{ hit("B", startAt + 21), startAt + 21 },
			{ hit("B", startAt + 23), startAt + 23 },
			{ hit("B", startAt + 25), startAt + 25 },
			{ hit("B", startAt + 27), startAt + 27 },
			{ { kind = "forfeit", side = "A" }, startAt + 27 },
			{ { kind = "leave", side = "B" }, startAt + 28 },
			{ { kind = "oob", side = "A" }, startAt + 28 },
			{ { kind = "shutdown" }, startAt + 29 },
			{ { kind = "throwAccepted", side = "A" }, startAt + 29 },
			{ { kind = "tick" }, startAt + 40 },
			{ { kind = "returned" }, startAt + 41 },
			{ { kind = "returned" }, startAt + 42 },
		})
		expect.equal(count(effects, "ended"), 1)
		expect.equal(count(effects, "closed"), 1)
	end)

	t.test("step never modifies the state it is given", function()
		local s, startAt = toActive()
		local livesBefore = s.participants.B.lives
		local phaseBefore = s.phase
		local nextState = DuelRules.step(s, hit("B", startAt + 1), startAt + 1)
		expect.equal(s.participants.B.lives, livesBefore)
		expect.equal(s.phase, phaseBefore)
		expect.equal(nextState.participants.B.lives, livesBefore - 1)
		local forfeited = DuelRules.step(s, { kind = "forfeit", side = "A" }, startAt + 30)
		expect.falsy(s.ended)
		expect.truthy(forfeited.ended)
	end)

	t.test("unknown events, bad sides and malformed hits are ignored", function()
		local s, startAt = toActive()
		for _, event in
			{
				{ kind = "teleport", side = "A" },
				{ kind = "queueLeave", side = "A" }, -- §5.4 "Queue cancel" during a match: ignored (use Forfeit)
				{ kind = "forfeit", side = "C" },
				{ kind = "forfeit" },
				{ kind = "hit", victim = "Z", at = startAt + 1 },
				{ kind = "hit", victim = "A", at = 0 / 0 },
				{ kind = "hits", hits = { { victim = "A", at = "soon" } } },
				{ kind = 42 },
			} :: { any }
		do
			local after, effects = DuelRules.step(s, event, startAt + 1)
			expect.equal(#effects, 0)
			expect.falsy(after.ended)
			expect.equal(after.participants.A.lives, RULES.Lives)
		end
	end)

	t.test("helpers: other, sideOf, activeSeconds, canBeHit", function()
		expect.equal(DuelRules.other("A"), "B")
		expect.equal(DuelRules.other("B"), "A")
		local s, startAt = toActive()
		expect.equal(DuelRules.sideOf(s, USER_A), "A")
		expect.equal(DuelRules.sideOf(s, USER_B), "B")
		expect.equal(DuelRules.sideOf(s, 999), nil)
		expect.equal(DuelRules.activeSeconds(s, startAt + 12), 12)
		expect.truthy(DuelRules.canBeHit(s, "A", startAt + 1))
		expect.falsy(DuelRules.canBeHit(toCountdown(), "A", T0 + 2))
		local ended = run(s, { { { kind = "forfeit", side = "A" }, startAt + 25 } })
		expect.equal(DuelRules.activeSeconds(ended, startAt + 90), 25) -- frozen at the end
		expect.falsy(DuelRules.canBeHit(ended, "A", startAt + 26))
	end)

	t.test("entrants carry the test-dummy and rewards flags; a missing userId is an error", function()
		local s = DuelRules.new(MATCH_ID, {
			A = { userId = USER_A, rewardsEnabled = true },
			B = { userId = -1, isTestDummy = true },
		}, T0, Config.Duel)
		expect.truthy(s.participants.B.isTestDummy)
		expect.falsy(s.participants.B.rewardsEnabled)
		expect.falsy(s.participants.A.isTestDummy)
		expect.throws(function()
			DuelRules.new(MATCH_ID, { A = { userId = USER_A } } :: any, T0, Config.Duel)
		end, "needs a userId")
	end)
end
