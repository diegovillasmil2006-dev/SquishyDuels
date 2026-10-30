--!strict
-- ThrowRules_Test: unit tests for ServerScriptService.Server.Logic.ThrowRules. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §5.6, §12 #2, #5, #7, #8, #9, #10): one case per rejection reason, cheapest check first —
-- rate bucket (silent drop, NetService) -> payload types and seq replay (net.invalid) -> context (throw.context) ->
-- alive / HRP (throw.context) -> not rooted by Dragon Rush (throw.rooted) -> own half + 2 or the practice zone
-- (throw.context) -> |aimDir| 0.95..1.05, pitch -35°..+65°, practice cone 75° (throw.direction) -> lag compensation
-- clamp -> cooldown with 0.05 s tolerance
-- (throw.cooldown) -> 4 live projectiles (throw.tooMany) -> origin hint within 4 + 22·min(ping, 0.25) studs (a farther
-- one pulled back to it) with line of sight and in the own zone -> spawn overlap fizzles but still uses the cooldown ->
-- accept with nextThrowAt = releaseAt + clamp(cooldown) × multiplier. Lifetime 3 s and Bounds expiry (§12 #10). The thrown
-- squishy's stats come from the server state, never the request. validate never modifies the state it reads.
-- Feature 1 (2026-10-11, the charge throw and the catch): #7b the hands: a press (lag-compensated) before
-- handsBusyUntil (a catch window or a crush) is throw.busy; the charge c is measured from chargeStartAt to the press,
-- from the throw's ready moment (nextThrowAt - windup, not before chargeFloorAt) at the earliest, clamped 0..1 (no
-- start = 0), and the velocity is × (1 + speedGain·c).
-- Power-ups v1.1 (2026-10-16): speedMultiplier (the throw boost) scales the velocity only (nil = exactly the old one).
-- Review fix: the rapid throw's multiplier from MatchService (Min / the clamped cooldown) gives exactly the shortest
-- cooldown, CooldownClamp.Min (the clamp comes first): the next throw at once is refused, one Min later is accepted.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local NOW = 1_800_000_000 -- a realistic GetServerTimeNow() value (≈ 2027), far beyond the 1e6 number bound
local PING = 0.1
local FLOAT_TOLERANCE = 1e-4
local TIME_TOLERANCE = 1e-6 -- doubles near 1.8e9 carry about 2e-7 s of rounding

-- Kitty Bread's catalog throw (§4.2); the server reads stats from here, never from the request.
local THROW = { speed = 95, gravity = 35, radius = 1.0, cooldown = 1.0, windup = 0.18 }

-- Arena half A (Z -52..-8, X ±36, Y -15..40) and the practice throw box (X -24..-16, Y 0..12, Z -54..-20).
local HALF_A = { cframe = CFrame.new(0, 12.5, -30), size = Vector3.new(72, 55, 44) }
local PRACTICE_ZONE = { cframe = CFrame.new(-20, 6, -37), size = Vector3.new(8, 12, 34) }
local PRACTICE_FORWARD = Vector3.new(-1, 0, 0)

local function facing(position: Vector3, yawDeg: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, math.rad(yawDeg), 0)
end

-- Side A stands in its half facing +Z (yaw 180°); the practice range faces -X (yaw 90°).
local DUEL_ROOT = facing(Vector3.new(0, 3, -30), 180)
local PRACTICE_ROOT = facing(Vector3.new(-20, 3, -37), 90)

local function aim(yawFromForwardDeg: number, pitchDeg: number, forward: Vector3): Vector3
	local flat = (CFrame.Angles(0, math.rad(yawFromForwardDeg), 0) * forward).Unit
	local pitch = math.rad(pitchDeg)
	return flat * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
end

return function(t: Context)
	local ThrowRules = t.requireServer("Logic/ThrowRules")
	local Config = t.requireShared("Config")
	local RateLimiter = t.requireShared("Util/RateLimiter")
	local FakeClock = t.requireFake("FakeClock")
	local expect = t.expect

	local FORWARD_A = Vector3.new(0, 0, 1)

	local function duelState(overrides: { [string]: any }?): any
		local state: { [string]: any } = {
			lastSeq = 0,
			nextThrowAt = NOW - 10,
			activeProjectiles = 0,
			matchPhase = "Active",
			alive = true,
			rootCFrame = DUEL_ROOT,
			rooted = false,
			ownHalf = HALF_A,
			ping = PING,
			throw = THROW,
		}
		if overrides then
			for key, value in overrides do
				state[key] = value
			end
		end
		return state
	end

	local function practiceState(overrides: { [string]: any }?): any
		local state = duelState({
			matchPhase = nil,
			rootCFrame = PRACTICE_ROOT,
			ownHalf = nil,
			practiceZone = PRACTICE_ZONE,
			practiceForward = PRACTICE_FORWARD,
		})
		state.matchPhase = nil
		state.ownHalf = nil
		if overrides then
			for key, value in overrides do
				state[key] = value
			end
		end
		return state
	end

	local function serverOrigin(root: CFrame): Vector3
		return root * Config.Combat.ReleaseOffset
	end

	local function input(overrides: { [string]: any }?): any
		local request: { [string]: any } = {
			seq = 1,
			aimDir = aim(0, 10, FORWARD_A),
			originHint = serverOrigin(DUEL_ROOT),
			clientTime = NOW - 0.05,
		}
		if overrides then
			for key, value in overrides do
				request[key] = value
			end
		end
		return request
	end

	local function practiceInput(overrides: { [string]: any }?): any
		local request = input({ aimDir = aim(0, 10, PRACTICE_FORWARD), originHint = serverOrigin(PRACTICE_ROOT) })
		if overrides then
			for key, value in overrides do
				request[key] = value
			end
		end
		return request
	end

	local function validate(request: any, state: any): any
		return ThrowRules.validate(request, state, Config, NOW)
	end

	local function expectRejected(decision: any, reason: string)
		if decision.ok then
			error("expected a rejection with " .. reason .. ", but the throw was accepted", 2)
		end
		if decision.reason ~= reason then
			error(string.format("expected reason %s, got %s", reason, tostring(decision.reason)), 2)
		end
	end

	-- Accept ---------------------------------------------------------------------------------------------------------

	t.test("a valid duel throw is accepted with server stats, releaseAt and nextThrowAt", function()
		local state = duelState()
		local decision = validate(input(), state)
		expect.truthy(decision.ok)
		expect.equal(decision.mode, "duel")
		expect.equal(decision.seq, 1)
		expect.equal(decision.lastSeq, 1)
		expect.falsy(decision.violation)
		expect.near(decision.lag, 0.05, TIME_TOLERANCE) -- now - clientTime, under min(ping/2 + 0.03, 0.12)
		expect.near(decision.releaseAt, NOW - 0.05 + THROW.windup, 1e-6)
		expect.near(decision.nextThrowAt, decision.releaseAt + THROW.cooldown, 1e-6)
		expect.near(decision.direction.Magnitude, 1, FLOAT_TOLERANCE)
		expect.near((decision.velocity - decision.direction * THROW.speed).Magnitude, 0, FLOAT_TOLERANCE)
		expect.equal(decision.gravity, THROW.gravity)
		expect.equal(decision.radius, THROW.radius)
		expect.falsy(decision.originClamped)
		expect.falsy(decision.fizzle)
		-- The state it read is untouched.
		expect.equal(state.lastSeq, 0)
		expect.equal(state.nextThrowAt, NOW - 10)
	end)

	t.test("apply writes lastSeq and, on accept, nextThrowAt back", function()
		local state = duelState()
		local decision = validate(input(), state)
		ThrowRules.apply(state, decision)
		expect.equal(state.lastSeq, 1)
		expect.equal(state.nextThrowAt, decision.nextThrowAt)
		local rejected = validate(input({ seq = 2, aimDir = Vector3.new(0, 0, 2) }), state)
		ThrowRules.apply(state, rejected)
		expect.equal(state.lastSeq, 2) -- a rejected but well-formed seq is used up
		expect.equal(state.nextThrowAt, decision.nextThrowAt) -- unchanged by the rejection
	end)

	t.test("a practice throw inside the zone is accepted in practice mode", function()
		local decision = validate(practiceInput(), practiceState())
		expect.truthy(decision.ok)
		expect.equal(decision.mode, "practice")
	end)

	-- #1 Rate bucket (NetService, before ThrowRules) ------------------------------------------------------------------

	t.test("#1 rate bucket: burst 4 then silent drop, refill 3/s (Config.Net.Remotes.ThrowRequest)", function()
		local entry = Config.Net.Remotes.ThrowRequest
		expect.equal(entry.rate, 3)
		expect.equal(entry.burst, 4)
		local clock = FakeClock.new(100)
		local limiter = RateLimiter.new(entry.rate, entry.burst, clock.now)
		for _ = 1, 4 do
			expect.truthy(limiter:take("player"))
		end
		expect.falsy(limiter:take("player"))
		clock.advance(0.34) -- just over 1/3 s: one token back
		expect.truthy(limiter:take("player"))
		expect.falsy(limiter:take("player"))
	end)

	-- #2 Types and replay (§12 #2) ---------------------------------------------------------------------------------

	t.test("#2 seq must be an integer: strings, fractions, NaN and huge values are invalid", function()
		for _, seq in { "1", 1.5, 0 / 0, math.huge, 1e7, true, {} } :: { any } do
			local decision = validate(input({ seq = seq }), duelState())
			expectRejected(decision, "net.invalid")
			expect.truthy(decision.violation)
			expect.equal(decision.seq, nil)
			expect.equal(decision.lastSeq, 0)
		end
	end)

	t.test("#2 seq replay and window: <= lastSeq or >= lastSeq + 1000 is invalid", function()
		local state = duelState({ lastSeq = 50 })
		for _, seq in { 50, 49, 0, 50 + 1000, 5000 } do
			local decision = validate(input({ seq = seq }), state)
			expectRejected(decision, "net.invalid")
			expect.equal(decision.lastSeq, 50)
		end
		expect.truthy(validate(input({ seq = 51 }), state).ok)
		expect.truthy(validate(input({ seq = 50 + 999 }), state).ok)
	end)

	t.test("#2 the same request twice: the replay is rejected after apply", function()
		local state = duelState()
		local first = validate(input({ seq = 7 }), state)
		ThrowRules.apply(state, first)
		expectRejected(validate(input({ seq = 7 }), state), "net.invalid")
	end)

	t.test("#2 aimDir and originHint must be finite Vector3s", function()
		local bad: { any } = {
			Vector3.new(0 / 0, 0, 1),
			Vector3.new(math.huge, 0, 0),
			Vector3.new(0, -math.huge, 0),
			Vector3.new(2e6, 0, 0),
			"0,0,1",
			{ X = 0, Y = 0, Z = 1 },
			CFrame.new(),
			42,
		}
		for _, value in bad do
			local aimDecision = validate(input({ aimDir = value }), duelState())
			expectRejected(aimDecision, "net.invalid")
			expect.truthy(aimDecision.violation)
			expect.equal(aimDecision.seq, 1) -- seq was valid: echoed and used up
			expect.equal(aimDecision.lastSeq, 1)
			expectRejected(validate(input({ originHint = value }), duelState()), "net.invalid")
		end
	end)

	t.test("#2 clientTime is a server timestamp: finite and below 1e10, never the 1e6 bound", function()
		for _, value in { "now", 0 / 0, math.huge, -math.huge, 1e10, Vector3.zero } :: { any } do
			expectRejected(validate(input({ clientTime = value }), duelState()), "net.invalid")
		end
		-- A real GetServerTimeNow() value (≈ 1.8e9) is well above 1e6 and must pass.
		expect.truthy(validate(input({ clientTime = NOW }), duelState()).ok)
	end)

	-- #3 Context -----------------------------------------------------------------------------------------------------

	t.test("#3 context: in a match only Active and SuddenDeath may throw", function()
		for _, phase in { "Preparing", "Positioning", "Countdown", "Result", "Returning", "Cancelled", "Void" } do
			expectRejected(validate(input(), duelState({ matchPhase = phase })), "throw.context")
		end
		expect.truthy(validate(input(), duelState({ matchPhase = "SuddenDeath" })).ok)
	end)

	t.test("#3 context: outside a match only inside the practice zone (the lobby has no throws)", function()
		local lobby = practiceState({ rootCFrame = facing(Vector3.new(0, 3, 0), 90) })
		local decision = validate(practiceInput(), lobby)
		expectRejected(decision, "throw.context")
		expect.falsy(decision.violation)
		expect.equal(decision.seq, 1)
		-- In a match, standing in the practice zone does not turn the throw into a practice throw.
		local inMatch = practiceState({ matchPhase = "Countdown" })
		expectRejected(validate(practiceInput(), inMatch), "throw.context")
	end)

	-- #4 Alive, HRP, rooted ------------------------------------------------------------------------------------------

	t.test("#4 a dead player or a missing HRP cannot throw (throw.context)", function()
		expectRejected(validate(input(), duelState({ alive = false })), "throw.context")
		local noRoot = duelState()
		noRoot.rootCFrame = nil
		expectRejected(validate(input(), noRoot), "throw.context")
	end)

	t.test("#4 a player rooted by Dragon Rush cannot throw (throw.rooted), in a duel and in practice", function()
		local duel = validate(input(), duelState({ rooted = true }))
		expectRejected(duel, "throw.rooted")
		expect.falsy(duel.violation)
		expect.equal(duel.nextThrowAt, NOW - 10) -- unchanged
		expectRejected(validate(practiceInput(), practiceState({ rooted = true })), "throw.rooted")
		-- Dead and rooted at once: the cheaper alive check names the reason.
		expectRejected(validate(input(), duelState({ alive = false, rooted = true })), "throw.context")
	end)

	-- #5 Position (§12 #5) -----------------------------------------------------------------------------------------

	t.test("#5 duel throws only from the own half + 2 studs", function()
		local edge = facing(Vector3.new(0, 3, -6.2), 180) -- 1.8 studs past the half (Z -8), inside the margin
		local hint = serverOrigin(edge)
		expect.truthy(validate(input({ originHint = hint }), duelState({ rootCFrame = edge })).ok)
		local beyond = facing(Vector3.new(0, 3, -5.8), 180) -- 2.2 studs past: rejected
		expectRejected(validate(input(), duelState({ rootCFrame = beyond })), "throw.context")
		local opponentHalf = facing(Vector3.new(0, 3, 30), 0)
		expectRejected(validate(input(), duelState({ rootCFrame = opponentHalf })), "throw.context")
		local noHalf = duelState()
		noHalf.ownHalf = nil
		expectRejected(validate(input(), noHalf), "throw.context")
	end)

	-- #6 Direction (§12 #8) ------------------------------------------------------------------------------------------

	t.test("#6 |aimDir| must be within 0.95..1.05; accepted directions are normalized", function()
		local dir = aim(0, 10, FORWARD_A)
		expectRejected(validate(input({ aimDir = dir * 0.94 }), duelState()), "throw.direction")
		expectRejected(validate(input({ aimDir = dir * 1.06 }), duelState()), "throw.direction")
		expectRejected(validate(input({ aimDir = Vector3.zero }), duelState()), "throw.direction")
		local scaled = validate(input({ aimDir = dir * 0.96 }), duelState())
		expect.truthy(scaled.ok)
		expect.near(scaled.direction.Magnitude, 1, FLOAT_TOLERANCE)
	end)

	t.test("#6 pitch must be within -35°..+65° (the limits themselves pass)", function()
		expect.truthy(validate(input({ aimDir = aim(0, 65, FORWARD_A) }), duelState()).ok)
		expect.truthy(validate(input({ aimDir = aim(0, -35, FORWARD_A) }), duelState()).ok)
		expectRejected(validate(input({ aimDir = aim(0, 66, FORWARD_A) }), duelState()), "throw.direction")
		expectRejected(validate(input({ aimDir = aim(0, -36, FORWARD_A) }), duelState()), "throw.direction")
		expectRejected(validate(input({ aimDir = Vector3.new(0, 1, 0) }), duelState()), "throw.direction")
	end)

	t.test("#6 practice: the flat aim must be within 75° of the range's forward (-X)", function()
		expect.truthy(validate(practiceInput({ aimDir = aim(74, 10, PRACTICE_FORWARD) }), practiceState()).ok)
		expect.truthy(validate(practiceInput({ aimDir = aim(-74, 10, PRACTICE_FORWARD) }), practiceState()).ok)
		expectRejected(
			validate(practiceInput({ aimDir = aim(76, 10, PRACTICE_FORWARD) }), practiceState()),
			"throw.direction"
		)
		expectRejected(
			validate(practiceInput({ aimDir = aim(180, 10, PRACTICE_FORWARD) }), practiceState()),
			"throw.direction"
		)
		-- No range forward known: fail closed.
		local unknown = practiceState()
		unknown.practiceForward = nil
		expectRejected(validate(practiceInput(), unknown), "throw.direction")
	end)

	t.test("#6 duels have no direction cone: a sideways throw at a legal pitch is fine", function()
		expect.truthy(validate(input({ aimDir = aim(90, 0, FORWARD_A) }), duelState()).ok)
	end)

	-- #7 Latency (§12 #9) ------------------------------------------------------------------------------------------

	t.test("#7 lag compensation: clamp(now - clientTime, 0, min(ping/2 + 0.03, 0.12))", function()
		expect.near(ThrowRules.lagCompensation(NOW, NOW - 0.05, 0.1, Config), 0.05, TIME_TOLERANCE)
		expect.near(ThrowRules.lagCompensation(NOW, NOW - 0.5, 0.1, Config), 0.08, TIME_TOLERANCE) -- ping/2 + 0.03
		expect.near(ThrowRules.lagCompensation(NOW, NOW - 0.5, 0.4, Config), 0.12, TIME_TOLERANCE) -- hard cap
		expect.near(ThrowRules.lagCompensation(NOW, NOW + 0.04, 0.1, Config), 0, TIME_TOLERANCE) -- slightly ahead: 0
	end)

	t.test("#7 abnormal client times fall back to min(ping/2, 0.12)", function()
		expect.near(ThrowRules.lagCompensation(NOW, NOW + 0.06, 0.1, Config), 0.05, TIME_TOLERANCE) -- > 0.05 s ahead
		expect.near(ThrowRules.lagCompensation(NOW, NOW - 1.5, 0.1, Config), 0.05, TIME_TOLERANCE) -- > 1 s behind
		expect.near(ThrowRules.lagCompensation(NOW, NOW - 1.5, 0.6, Config), 0.12, TIME_TOLERANCE)
		expect.near(ThrowRules.lagCompensation(NOW, NOW - 1.5, 0 / 0, Config), 0, TIME_TOLERANCE) -- bad ping counts as 0
	end)

	t.test("#7 releaseAt is always in the future: the server never fast-forwards", function()
		local decision = validate(input({ clientTime = NOW - 0.9 }), duelState({ ping = 5 }))
		expect.truthy(decision.ok)
		expect.near(decision.lag, Config.Combat.Lag.maxCompensationSeconds, TIME_TOLERANCE)
		expect.truthy(decision.releaseAt > NOW)
	end)

	-- #8 Cooldown (§12 #7) -------------------------------------------------------------------------------------------

	t.test("#8 cooldown: releaseAt must reach nextThrowAt - 0.05", function()
		local releaseAt = NOW - 0.05 + THROW.windup
		local tooSoon = validate(input(), duelState({ nextThrowAt = releaseAt + 0.06 }))
		expectRejected(tooSoon, "throw.cooldown")
		expect.equal(tooSoon.nextThrowAt, releaseAt + 0.06) -- echoed unchanged for ThrowRejected
		expect.truthy(validate(input(), duelState({ nextThrowAt = releaseAt + 0.04 })).ok)
	end)

	t.test("#8 a rejected throw does not move nextThrowAt; an accepted one does", function()
		local state = duelState()
		local first = validate(input({ seq = 1 }), state)
		ThrowRules.apply(state, first)
		local second = validate(input({ seq = 2 }), state) -- same press time: inside the cooldown
		expectRejected(second, "throw.cooldown")
		ThrowRules.apply(state, second)
		expect.equal(state.nextThrowAt, first.nextThrowAt)
	end)

	t.test("#8 cooldowns are clamped to 0.6..2.0 s and scaled by the sudden-death multiplier", function()
		local clamp = Config.Duel.Rules.CooldownClamp
		local fast = validate(
			input(),
			duelState({ throw = { speed = 95, gravity = 35, radius = 1, cooldown = 0.1, windup = 0.18 } })
		)
		expect.near(fast.nextThrowAt - fast.releaseAt, clamp.Min, 1e-6)
		local slow = validate(
			input(),
			duelState({ throw = { speed = 95, gravity = 35, radius = 1, cooldown = 9, windup = 0.18 } })
		)
		expect.near(slow.nextThrowAt - slow.releaseAt, clamp.Max, 1e-6)
		local multiplier = Config.Duel.Rules.SuddenDeathCooldownMultiplier
		local sudden = validate(input(), duelState({ matchPhase = "SuddenDeath", cooldownMultiplier = multiplier }))
		expect.near(sudden.nextThrowAt - sudden.releaseAt, THROW.cooldown * multiplier, 1e-6)
	end)

	-- #9 Live projectiles (§12 #10) --------------------------------------------------------------------------------

	t.test("#9 a fifth live projectile is rejected with throw.tooMany", function()
		expect.equal(Config.Duel.Rules.MaxActiveProjectilesPerPlayer, 4)
		expect.truthy(validate(input(), duelState({ activeProjectiles = 3 })).ok)
		expectRejected(validate(input(), duelState({ activeProjectiles = 4 })), "throw.tooMany")
	end)

	-- #10 Origin (§12 #5) --------------------------------------------------------------------------------------------

	t.test("#10 a close, visible hint inside the own half is used as the origin", function()
		local hint = serverOrigin(DUEL_ROOT) + Vector3.new(0.5, 0, 2.4) -- 2.45 studs from the server origin
		local decision = validate(input({ originHint = hint }), duelState())
		expect.falsy(decision.originClamped)
		expect.near((decision.origin - hint).Magnitude, 0, FLOAT_TOLERANCE)
	end)

	t.test("#10 a hint farther than 4 + 22·min(ping, 0.25) studs is pulled back to that distance", function()
		local server = serverOrigin(DUEL_ROOT)
		local far = validate(input({ originHint = server + Vector3.new(0, 0, 8) }), duelState({ ping = 0.1 })) -- 6.2 allowed
		expect.truthy(far.ok)
		expect.truthy(far.originClamped)
		-- Toward the hint, not back to the server origin: a walker's lag spike only nudges the throw.
		expect.near((far.origin - (server + Vector3.new(0, 0, 6.2))).Magnitude, 0, FLOAT_TOLERANCE)
		-- More ping allows more, up to 9.5 studs (ping capped at 0.25 s).
		expect.falsy(
			validate(input({ originHint = server + Vector3.new(0, 0, 8) }), duelState({ ping = 0.25 })).originClamped
		)
		expect.truthy(
			validate(input({ originHint = server + Vector3.new(0, 0, 10) }), duelState({ ping = 2 })).originClamped
		)
	end)

	t.test("#10 a hint without line of sight, or outside the own half + 2, falls back", function()
		local blocked = validate(
			input(),
			duelState({
				isClear = function(_from: Vector3, _to: Vector3): boolean
					return false
				end,
			})
		)
		expect.truthy(blocked.ok)
		expect.truthy(blocked.originClamped)
		-- Near the half's edge, a hint pushed 2 studs forward lands past own half + 2.
		local edge = facing(Vector3.new(0, 3, -6.2), 180)
		local hint = serverOrigin(edge) + Vector3.new(0, 0, 2)
		local outside = validate(input({ originHint = hint }), duelState({ rootCFrame = edge }))
		expect.truthy(outside.ok)
		expect.truthy(outside.originClamped)
	end)

	t.test("#10 the line-of-sight adapter is asked from the server HRP to the hint", function()
		local seenFrom, seenTo = nil :: Vector3?, nil :: Vector3?
		local hint = serverOrigin(DUEL_ROOT)
		validate(
			input({ originHint = hint }),
			duelState({
				isClear = function(from: Vector3, to: Vector3): boolean
					seenFrom, seenTo = from, to
					return true
				end,
			})
		)
		expect.truthy(seenFrom ~= nil and (seenFrom - DUEL_ROOT.Position).Magnitude < FLOAT_TOLERANCE)
		expect.truthy(seenTo ~= nil and (seenTo - hint).Magnitude < FLOAT_TOLERANCE)
	end)

	-- #11 Spawn overlap (§12 #10) ----------------------------------------------------------------------------------

	t.test("#11 a spawn overlap fizzles the throw but still uses the cooldown", function()
		local asked = 0
		local decision = validate(
			input(),
			duelState({
				overlaps = function(_origin: Vector3, radius: number): boolean
					asked += 1
					expect.equal(radius, THROW.radius)
					return true
				end,
			})
		)
		expect.equal(asked, 1)
		expect.truthy(decision.ok)
		expect.truthy(decision.fizzle)
		expect.near(decision.nextThrowAt, decision.releaseAt + THROW.cooldown, 1e-6)
	end)

	-- Order -----------------------------------------------------------------------------------------------------------

	t.test("checks run cheapest first: the earliest failing check names the reason", function()
		-- Wrong phase and a bad aim: context comes first.
		expectRejected(
			validate(input({ aimDir = Vector3.new(0, 1, 0) }), duelState({ matchPhase = "Countdown" })),
			"throw.context"
		)
		-- Bad aim and on cooldown: direction comes first.
		expectRejected(
			validate(input({ aimDir = Vector3.new(0, 1, 0) }), duelState({ nextThrowAt = NOW + 10 })),
			"throw.direction"
		)
		-- On cooldown with four in the air: cooldown comes first.
		expectRejected(
			validate(input(), duelState({ nextThrowAt = NOW + 10, activeProjectiles = 4 })),
			"throw.cooldown"
		)
	end)

	-- Every catalog squishy ---------------------------------------------------------------------------------------------

	t.test("every catalog throw passes the power budget and is accepted unclamped, released in the future", function()
		local Catalog = t.requireShared("Catalog")
		local PowerBudget = t.requireServer("Logic/PowerBudget")
		local clamp = Config.Duel.Rules.CooldownClamp
		local defs = Catalog.list()
		expect.truthy(#defs > 0)
		for _, def in defs do
			local ok, problems = PowerBudget.check(def, Config)
			if not ok then
				error(def.id .. " fails the power budget: " .. table.concat(problems, "; "))
			end
			local stats = def.throw
			expect.truthy(stats.cooldown >= clamp.Min and stats.cooldown <= clamp.Max)
			-- The worst case for "never fast-forwards": a stale press with the largest lag compensation.
			local decision = validate(input({ clientTime = NOW - 0.9 }), duelState({ throw = stats, ping = 5 }))
			if not decision.ok then
				error(def.id .. " was rejected: " .. tostring(decision.reason))
			end
			expect.truthy(decision.releaseAt > NOW)
			expect.near(decision.nextThrowAt - decision.releaseAt, stats.cooldown, 1e-6)
			expect.near(decision.velocity.Magnitude, stats.speed, 1e-3)
			expect.equal(decision.gravity, stats.gravity)
			expect.equal(decision.radius, stats.radius)
		end
	end)

	-- Feature 1: the hands and the charge -------------------------------------------------------------------------

	t.test("#7b hands: a press before handsBusyUntil (lag-compensated) is throw.busy", function()
		expectRejected(validate(input(), duelState({ handsBusyUntil = NOW + 0.2 })), "throw.busy")
		-- The press is now - lag (0.05 here): busy until NOW - 0.02 still covers it.
		expectRejected(validate(input(), duelState({ handsBusyUntil = NOW - 0.02 })), "throw.busy")
		expect.truthy(validate(input(), duelState({ handsBusyUntil = NOW - 0.06 })).ok)
		expect.truthy(validate(input(), duelState({ handsBusyUntil = -math.huge })).ok)
		-- Rooted is still its own reason, checked first.
		expectRejected(validate(input(), duelState({ rooted = true, handsBusyUntil = NOW + 1 })), "throw.rooted")
	end)

	t.test("the charge: measured by the server from chargeStartAt to the press, × (1 + 0.85c) speed", function()
		local speedGain = Config.Combat.Charge.speedGain
		-- No start: an uncharged throw.
		local plain = validate(input(), duelState())
		expect.equal(plain.charge, 0)
		expect.near(plain.velocity.Magnitude, THROW.speed, 1e-3)
		-- Started 0.55 s before now, pressed (let go) at now - 0.05: c = 0.5.
		local half = validate(input(), duelState({ chargeStartAt = NOW - 0.55 }))
		expect.near(half.charge, 0.5, TIME_TOLERANCE * 10)
		expect.near(half.velocity.Magnitude, THROW.speed * (1 + speedGain * half.charge), 1e-3)
		-- Clamped at 1.
		local full = validate(input(), duelState({ chargeStartAt = NOW - 5 }))
		expect.equal(full.charge, 1)
		expect.near(full.velocity.Magnitude, THROW.speed * (1 + speedGain), 1e-3)
		-- Pressed during the cooldown: counted from the moment the throw was ready (nextThrowAt - windup).
		local cooled =
			validate(input(), duelState({ chargeStartAt = NOW - 2, nextThrowAt = NOW - 0.25 + THROW.windup }))
		expect.truthy(cooled.ok)
		expect.near(cooled.charge, 0.2, TIME_TOLERANCE * 10)
		-- Nor before chargeFloorAt (the hands back from a crush, an ultimate's root).
		local floored = validate(input(), duelState({ chargeStartAt = NOW - 2, chargeFloorAt = NOW - 0.15 }))
		expect.near(floored.charge, 0.1, TIME_TOLERANCE * 10)
		-- A start after the press counts nothing.
		expect.equal(validate(input(), duelState({ chargeStartAt = NOW })).charge, 0)
		-- The direction is the aim, whatever the charge.
		expect.near((full.direction - plain.direction).Magnitude, 0, FLOAT_TOLERANCE)
	end)

	-- Power-ups v1.1 (2026-10-16): the Free for All / Team Deathmatch throw boost and rapid throw.
	t.test(
		"power-ups: speedMultiplier scales the launch speed (nil = 1); the rapid throw's cooldown is the shortest one",
		function()
			local speedGain = Config.Combat.Charge.speedGain
			local plain = validate(input(), duelState())
			local boosted = validate(input(), duelState({ speedMultiplier = 1.4 }))
			expect.truthy(boosted.ok)
			expect.near(boosted.velocity.Magnitude, THROW.speed * 1.4, 1e-3)
			expect.near((boosted.direction - plain.direction).Magnitude, 0, FLOAT_TOLERANCE)
			expect.equal(boosted.gravity, plain.gravity)
			expect.equal(boosted.nextThrowAt, plain.nextThrowAt) -- the boost never touches the cooldown
			-- With a charge: both factors.
			local both = validate(input(), duelState({ speedMultiplier = 1.4, chargeStartAt = NOW - 5 }))
			expect.near(both.velocity.Magnitude, THROW.speed * (1 + speedGain) * 1.4, 1e-3)
			-- No multiplier is exactly the old velocity.
			expect.equal(validate(input(), duelState({ speedMultiplier = nil })).velocity, plain.velocity)
			-- Rapid throw (review fix): the clamp comes first, then × MatchService's Min / the clamped cooldown, so the
			-- cooldown is exactly CooldownClamp.Min (SPEC P3: "no wait" = the shortest cooldown).
			local clamp = Config.Duel.Rules.CooldownClamp
			local rapidMultiplier = clamp.Min / math.clamp(THROW.cooldown, clamp.Min, clamp.Max)
			local rapid = validate(input(), duelState({ cooldownMultiplier = rapidMultiplier }))
			expect.near(rapid.nextThrowAt, (rapid.releaseAt :: number) + clamp.Min, TIME_TOLERANCE)
			local state = duelState({ cooldownMultiplier = rapidMultiplier })
			ThrowRules.apply(state, rapid)
			state.activeProjectiles = 1
			expectRejected(validate(input({ seq = 2 }), state), "throw.cooldown") -- not at once
			local later = clamp.Min
			local next =
				ThrowRules.validate(input({ seq = 3, clientTime = NOW + later - 0.05 }), state, Config, NOW + later)
			expect.truthy(next.ok)
			expect.near(next.releaseAt :: number, (rapid.releaseAt :: number) + clamp.Min, TIME_TOLERANCE)
		end
	)

	-- §12 #10 Lifetime and Bounds -----------------------------------------------------------------------------------

	t.test("projectiles expire after ProjectileMaxLifetime (3 s) or outside Bounds", function()
		local bounds = { cframe = CFrame.new(0, 12.5, 0), size = Vector3.new(76, 55, 108) }
		local lifetime = Config.Duel.Rules.ProjectileMaxLifetime
		expect.equal(lifetime, 3)
		local inside = Vector3.new(0, 3, 0)
		expect.falsy(ThrowRules.isExpired(NOW, NOW + lifetime - 0.01, inside, bounds, Config))
		expect.truthy(ThrowRules.isExpired(NOW, NOW + lifetime, inside, bounds, Config))
		expect.truthy(ThrowRules.isExpired(NOW, NOW + 0.5, Vector3.new(0, 3, 60), bounds, Config))
		expect.truthy(ThrowRules.isExpired(NOW, NOW + 0.5, Vector3.new(0, 41, 0), bounds, Config))
	end)
end
