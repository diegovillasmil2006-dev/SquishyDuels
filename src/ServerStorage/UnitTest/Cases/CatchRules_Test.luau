--!strict
-- CatchRules_Test: unit tests for ServerScriptService.Server.Logic.CatchRules (feature 1, 2026-10-11: the catch; design:
-- the combat-effects page "Squishy Combat FP v2.html", html:342-345, 532, 614). Server only (ServerStorage.UnitTest).
-- Pure.
-- Contract (cheapest check first, one reason each):
--   * clientTime must be a server timestamp (net.invalid, a violation);
--   * a registered duel in Active or SuddenDeath, alive with a root (catch.context);
--   * not crushing (until busyUntil), not rooted, not in a throw windup (catch.busy);
--   * cooldownSeconds (1.3, review quick win 2026-10-14) from the last accepted press, with cooldownToleranceSeconds of
--     slack (catch.cooldown); a real catch keeps its own wait (the lag-compensated rule below);
--   * accepted: the window opens at the lag-compensated press (now - lag, as a ThrowRequest's) for windowSeconds (0.42);
--   * the catch test: the first point of a sub-step within radiusStuds (2.7 m) of the centre (root + 1.5) while still
--     moving toward it, inside the part of the sub-step the window covers; a throw going away is never caught.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local NOW = 1_800_000_000
local EPS = 1e-6

return function(t: Context)
	local CatchRules = t.requireServer("Logic/CatchRules")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local CATCH = Config.Combat.Catch
	local R = CATCH.radiusStuds
	local CENTRE = Vector3.new(0, 4.5, 0)

	local function state(overrides: { [string]: any }?): any
		local s: { [string]: any } = {
			inDuel = true,
			matchPhase = "Active",
			alive = true,
			hasRoot = true,
			busyUntil = -math.huge,
			rooted = false,
			windup = false,
			lastPressAt = -math.huge,
			ping = 0,
		}
		if overrides then
			for key, value in overrides do
				s[key] = value
			end
		end
		return s
	end

	local function validate(clientTime: unknown, s: any): any
		return CatchRules.validate({ clientTime = clientTime }, s, nil, NOW)
	end

	local function expectRefused(decision: any, reason: string)
		if decision.ok then
			error("expected " .. reason .. ", but the catch was accepted", 2)
		end
		if decision.reason ~= reason then
			error(`expected {reason}, got {decision.reason}`, 2)
		end
	end

	t.test("the numbers: 0.42 s open, 1.3 s after a miss, 2.7 m (≈ 9.6 studs), 1.02 s crush", function()
		expect.equal(CATCH.windowSeconds, 0.42) -- design: html:532
		expect.equal(CATCH.cooldownSeconds, 1.3) -- review quick win 2026-10-14 (design: html:344 has 0.75)
		expect.near(R, 2.7 / 0.28, 1e-9) -- design: html:614
		expect.equal(CATCH.crushSeconds, 1.02) -- design: html:554
		local entry = Config.Net.Remotes.CatchRequest
		expect.truthy(entry.rate > 0 and entry.burst >= 1)
		-- A real catch keeps its own wait: the client gate (unlagged) and the server gate (the press lag-compensated by
		-- up to Lag.maxCompensationSeconds) both open by the time the hands are back.
		expect.truthy(CATCH.cooldownSeconds <= CATCH.handsBackSeconds)
		expect.truthy(
			CATCH.cooldownSeconds - CATCH.cooldownToleranceSeconds
				<= CATCH.handsBackSeconds - Config.Combat.Lag.maxCompensationSeconds
		)
	end)

	t.test("accepted: the window opens at the lag-compensated press for windowSeconds", function()
		local decision = validate(NOW - 0.05, state({ ping = 0.2 }))
		expect.truthy(decision.ok)
		expect.falsy(decision.violation)
		expect.near(decision.pressAt, NOW - 0.05, EPS) -- under min(ping/2 + 0.03, 0.12)
		expect.near(decision.opensAt, decision.pressAt, EPS)
		expect.near(decision.closesAt, decision.pressAt + CATCH.windowSeconds, EPS)
		-- A press claiming more lag than the cap is held to it.
		local capped = validate(NOW - 0.5, state({ ping = 0.2 }))
		expect.near(capped.pressAt, NOW - 0.12, EPS)
		expect.near(CatchRules.pressTime(NOW, NOW - 0.05, 0.2) :: number, NOW - 0.05, EPS)
	end)

	t.test("net.invalid: clientTime must be a server timestamp (a violation)", function()
		for _, bad in { "1", 0 / 0, math.huge, 1e11, true } :: { any } do
			local decision = validate(bad, state())
			expectRefused(decision, "net.invalid")
			expect.truthy(decision.violation)
		end
		expectRefused(validate(nil, state()), "net.invalid")
		expect.equal(CatchRules.pressTime(NOW, "x", 0), nil)
	end)

	t.test("catch.context: only a live duel fighter, alive with a root", function()
		expectRefused(validate(NOW, state({ inDuel = false })), "catch.context")
		for _, phase in { "Countdown", "Result", "Preparing", "Returning" } do
			expectRefused(validate(NOW, state({ matchPhase = phase })), "catch.context")
		end
		local noPhase = state()
		noPhase.matchPhase = nil
		expectRefused(validate(NOW, noPhase), "catch.context")
		expect.truthy(validate(NOW, state({ matchPhase = "SuddenDeath" })).ok)
		expectRefused(validate(NOW, state({ alive = false })), "catch.context")
		expectRefused(validate(NOW, state({ hasRoot = false })), "catch.context")
		expect.falsy(validate(NOW, state({ alive = false })).violation)
	end)

	t.test("catch.busy: crushing (until busyUntil), rooted or in a throw windup", function()
		expectRefused(validate(NOW, state({ busyUntil = NOW + 0.3 })), "catch.busy")
		expect.truthy(validate(NOW, state({ busyUntil = NOW })).ok)
		expectRefused(validate(NOW, state({ rooted = true })), "catch.busy")
		expectRefused(validate(NOW, state({ windup = true })), "catch.busy")
	end)

	t.test("catch.cooldown: 1.3 s from the last accepted press (a missed catch), with the tolerance", function()
		local cooldown, tolerance = CATCH.cooldownSeconds, CATCH.cooldownToleranceSeconds
		expectRefused(validate(NOW, state({ lastPressAt = NOW - 0.5 })), "catch.cooldown")
		expectRefused(validate(NOW, state({ lastPressAt = NOW - 1.0 })), "catch.cooldown") -- the old 0.75 s let this in
		expectRefused(validate(NOW, state({ lastPressAt = NOW - (cooldown - tolerance) + 0.01 })), "catch.cooldown")
		expect.truthy(validate(NOW, state({ lastPressAt = NOW - (cooldown - tolerance) - 1e-3 })).ok)
		expect.truthy(validate(NOW, state({ lastPressAt = NOW - cooldown })).ok)
	end)

	t.test("the order: a bad payload before the context, the context before busy, busy before the cooldown", function()
		expectRefused(validate("x", state({ inDuel = false })), "net.invalid")
		expectRefused(validate(NOW, state({ inDuel = false, rooted = true })), "catch.context")
		expectRefused(validate(NOW, state({ rooted = true, lastPressAt = NOW })), "catch.busy")
	end)

	t.test("the centre is the root + centreAboveRootStuds", function()
		local centre = CatchRules.centre(Vector3.new(1, 3, -2))
		expect.near((centre - Vector3.new(1, 3 + CATCH.centreAboveRootStuds, -2)).Magnitude, 0, EPS)
	end)

	t.test("windowShare: the part of a sub-step the window covers, nil when they do not meet", function()
		local lo, hi = CatchRules.windowShare(10, 11, 10.5, 10.6)
		expect.near(lo :: number, 0, EPS)
		expect.near(hi :: number, 1, EPS)
		lo, hi = CatchRules.windowShare(10.55, 11, 10.5, 10.6)
		expect.near(lo :: number, 0.5, 1e-6)
		expect.near(hi :: number, 1, EPS)
		lo, hi = CatchRules.windowShare(10, 10.52, 10.5, 10.6)
		expect.near(lo :: number, 0, EPS)
		expect.near(hi :: number, 0.2, 1e-6)
		expect.equal((CatchRules.windowShare(11, 12, 10.5, 10.6)), nil)
		expect.equal((CatchRules.windowShare(9, 10.4, 10.5, 10.6)), nil)
		expect.equal((CatchRules.windowShare(10, 11, 10.6, 10.6)), nil)
	end)

	t.test("catchFraction: the first point inside the radius, approaching only", function()
		-- Straight at the centre along -Z from 20 studs: it enters at R from the centre.
		local p0 = CENTRE + Vector3.new(0, 0, 20)
		local p1 = CENTRE + Vector3.new(0, 0, -20)
		local f = CatchRules.catchFraction(p0, p1, CENTRE, R) :: number
		expect.truthy(f ~= nil)
		local at = p0:Lerp(p1, f)
		expect.near((at - CENTRE).Magnitude, R, 1e-4) -- Vector3 holds 32-bit floats
		-- Starting inside, still coming: caught at once.
		local inside = CENTRE + Vector3.new(0, 0, R / 2)
		expect.near(CatchRules.catchFraction(inside, inside + Vector3.new(0, 0, -1), CENTRE, R) :: number, 0, EPS)
		-- Starting inside but going away: never.
		expect.equal(CatchRules.catchFraction(inside, inside + Vector3.new(0, 0, 3), CENTRE, R), nil)
		-- A pass outside the radius: never.
		local wide = Vector3.new(R + 0.5, 0, 0)
		expect.equal(CatchRules.catchFraction(p0 + wide, p1 + wide, CENTRE, R), nil)
		-- A segment that ends before reaching the radius: never (the next sub-step will).
		expect.equal(CatchRules.catchFraction(p0, CENTRE + Vector3.new(0, 0, R + 1), CENTRE, R), nil)
		-- No length: never.
		expect.equal(CatchRules.catchFraction(inside, inside, CENTRE, R), nil)
	end)

	t.test("catchFraction keeps to the window's part of the sub-step", function()
		local p0 = CENTRE + Vector3.new(0, 0, 20)
		local p1 = CENTRE + Vector3.new(0, 0, -20)
		local enter = CatchRules.catchFraction(p0, p1, CENTRE, R) :: number -- (20 - R) / 40
		-- The window opens later in the sub-step, while the throw is still inside and coming: caught then.
		local later = CatchRules.catchFraction(p0, p1, CENTRE, R, enter + 0.05, 1) :: number
		expect.near(later, enter + 0.05, EPS)
		-- The window opens after it passed the closest point (going away by then): never.
		expect.equal(CatchRules.catchFraction(p0, p1, CENTRE, R, 0.6, 1), nil)
		-- The window closes before it arrives: never.
		expect.equal(CatchRules.catchFraction(p0, p1, CENTRE, R, 0, enter - 0.01), nil)
	end)
end
