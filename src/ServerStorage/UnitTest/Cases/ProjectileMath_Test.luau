--!strict
-- ProjectileMath_Test: unit tests for ReplicatedStorage.Shared.ProjectileMath. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §5.5, §5.7, §9.7): positionAt(o, v, g, t) = o + v·t + (0, -½·g·t², 0), deterministic;
-- solveLaunchDir returns a unit low-arc direction that lands on the target, falls back to 45° when the target is out
-- of reach and clamps the pitch to [-35°, +65°] (Config.Combat.Throw); the sweep splits (tPrev, tNow] into
-- clamp(ceil(span · 60), 1, 6) contiguous sub-steps whose ends are fresh positionAt values; impactTime =
-- releaseAt + a + f·(b - a); the client path settles from the hand onto the server path.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

-- Vector3 components are single precision: positions are compared within this many studs, and the pitch of a
-- direction read back from a Vector3 within this many degrees (float32 rounding is ≈ 3.4e-6°).
local POSITION_TOLERANCE = 0.02
local PITCH_TOLERANCE_DEG = 1e-4

-- Where a throw from `origin` along `dir` at `speed` is when it has covered the target's horizontal distance.
local function landingPoint(
	ProjectileMath: any,
	origin: Vector3,
	target: Vector3,
	dir: Vector3,
	speed: number,
	g: number
)
	local horizontal = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z).Magnitude
	local flatSpeed = Vector3.new(dir.X, 0, dir.Z).Magnitude * speed
	local t = horizontal / flatSpeed
	return ProjectileMath.positionAt(origin, dir * speed, g, t)
end

local function expectVectorNear(expect: any, actual: Vector3, expected: Vector3, tolerance: number)
	expect.near(actual.X, expected.X, tolerance)
	expect.near(actual.Y, expected.Y, tolerance)
	expect.near(actual.Z, expected.Z, tolerance)
end

return function(t: Context)
	local ProjectileMath = t.requireShared("ProjectileMath")
	local Config = t.requireShared("Config")
	local Catalog = t.requireShared("Catalog")
	local expect = t.expect
	local throwConfig = Config.Combat.Throw

	-- positionAt / velocityAt ---------------------------------------------------------------------------------------

	t.test("positionAt follows o + v·t - ½·g·t² on Y", function()
		local o, v = Vector3.new(0, 10, 0), Vector3.new(10, 20, -4)
		expectVectorNear(expect, ProjectileMath.positionAt(o, v, 30, 0), o, 1e-6)
		-- t = 0.5: (5, 10 + 10 - 3.75, -2)
		expectVectorNear(expect, ProjectileMath.positionAt(o, v, 30, 0.5), Vector3.new(5, 16.25, -2), 1e-4)
	end)

	t.test("positionAt with g = 0 is a straight line (Dragon Rush lane)", function()
		local o, v = Vector3.new(1, 4.5, 2), Vector3.new(0, 0, 260)
		expectVectorNear(expect, ProjectileMath.positionAt(o, v, 0, 0.25), Vector3.new(1, 4.5, 67), 1e-3)
	end)

	t.test("the same inputs always give the same position", function()
		local o, v = Vector3.new(3.3, 5.1, -44.7), Vector3.new(12.25, 30.5, 91.1)
		for _, time in { 0.016, 0.5, 1.234567, 2.999 } do
			expect.equal(ProjectileMath.positionAt(o, v, 35, time), ProjectileMath.positionAt(o, v, 35, time))
		end
	end)

	t.test("velocityAt is the derivative of positionAt", function()
		local o, v, g = Vector3.new(0, 3, 0), Vector3.new(40, 50, 60), 35
		local time, h = 0.7, 1e-3
		local numeric = (ProjectileMath.positionAt(o, v, g, time + h) - ProjectileMath.positionAt(o, v, g, time - h))
			/ (2 * h)
		expectVectorNear(expect, ProjectileMath.velocityAt(v, g, time), numeric, 0.05)
	end)

	t.test("positionAtTime uses server time minus releaseAt and holds the origin before release", function()
		local trajectory =
			{ origin = Vector3.new(0, 4, 0), velocity = Vector3.new(0, 10, 90), gravity = 35, releaseAt = 1000 }
		expect.equal(
			ProjectileMath.positionAtTime(trajectory, 1000.5),
			ProjectileMath.positionAt(trajectory.origin, trajectory.velocity, trajectory.gravity, 0.5)
		)
		expect.equal(ProjectileMath.positionAtTime(trajectory, 999), trajectory.origin)
	end)

	t.test("flightTime clamps to [0, ProjectileMaxLifetime]", function()
		local lifetime = Config.Duel.Rules.ProjectileMaxLifetime
		expect.near(ProjectileMath.flightTime(100.25, 100), 0.25)
		expect.equal(ProjectileMath.flightTime(99, 100), 0)
		expect.equal(ProjectileMath.flightTime(100 + lifetime + 5, 100), lifetime)
		expect.equal(ProjectileMath.flightTime(110, 100, 1), 1)
	end)

	t.test("maxRange is speed² / g; every catalog throw reaches past the court", function()
		expect.near(ProjectileMath.maxRange(88, 50), 154.88, 1e-6) -- Banana, DESIGN §5.8 "≥ 155"
		expect.equal(ProjectileMath.maxRange(260, 0), math.huge)
		for _, def in Catalog.list() do
			local range = ProjectileMath.maxRange(def.throw.speed, def.throw.gravity)
			if range < 104 then
				error(string.format("%s reaches only %.1f studs", def.id, range))
			end
		end
	end)

	-- solveLaunchDir ---------------------------------------------------------------------------------------------

	t.test("solveLaunchDir lands every catalog throw on reachable targets", function()
		local origin = Vector3.new(1, 4.8, -42.5)
		local targets = {
			Vector3.new(1, 4.8, -2.5), -- 40 studs, level
			Vector3.new(0, 0, 44), -- the far pad's floor
			Vector3.new(-20, 3, -20), -- diagonal, lower
			Vector3.new(6, 9, -26.5), -- 16 studs ahead, above
		}
		for _, def in Catalog.list() do
			local speed, g = def.throw.speed, def.throw.gravity
			for _, target in targets do
				local dir = ProjectileMath.solveLaunchDir(origin, target, speed, g)
				expect.near(dir.Magnitude, 1, 1e-4)
				local pitch = ProjectileMath.pitchDeg(dir)
				expect.truthy(pitch >= throwConfig.pitchMinDeg and pitch <= throwConfig.pitchMaxDeg)
				expectVectorNear(
					expect,
					landingPoint(ProjectileMath, origin, target, dir, speed, g),
					target,
					POSITION_TOLERANCE
				)
			end
		end
	end)

	t.test("solveLaunchDir picks the low arc", function()
		local dir = ProjectileMath.solveLaunchDir(Vector3.zero, Vector3.new(0, 0, -40), 95, 35)
		local pitch = ProjectileMath.pitchDeg(dir)
		expect.truthy(pitch > 0 and pitch < 45)
		expect.truthy(dir.Z < 0) -- toward the target
	end)

	t.test("solveLaunchDir falls back to the no-solution pitch toward an unreachable target", function()
		local dir = ProjectileMath.solveLaunchDir(Vector3.zero, Vector3.new(300, 0, 0), 85, 50)
		expect.near(ProjectileMath.pitchDeg(dir), throwConfig.noSolutionPitchDeg, PITCH_TOLERANCE_DEG)
		expect.truthy(dir.X > 0)
		expect.near(dir.Z, 0, 1e-6)
	end)

	t.test("solveLaunchDir clamps the pitch inside [-35°, +65°]", function()
		local inset = ProjectileMath.PITCH_INSET_DEG
		local up = ProjectileMath.solveLaunchDir(Vector3.zero, Vector3.new(0.5, 30, 0), 95, 35)
		expect.near(ProjectileMath.pitchDeg(up), throwConfig.pitchMaxDeg - inset, PITCH_TOLERANCE_DEG)
		local down = ProjectileMath.solveLaunchDir(Vector3.new(0, 30, 0), Vector3.new(0.5, 0, 0), 95, 35)
		expect.near(ProjectileMath.pitchDeg(down), throwConfig.pitchMinDeg + inset, PITCH_TOLERANCE_DEG)
		-- A clamped direction still passes the server's pitch rule after the Vector3 round trip.
		for _, dir in { up, down } do
			local copy = Vector3.new(dir.X, dir.Y, dir.Z)
			local pitch = ProjectileMath.pitchDeg(copy)
			expect.truthy(pitch >= throwConfig.pitchMinDeg and pitch <= throwConfig.pitchMaxDeg)
		end
	end)

	t.test("solveLaunchDir handles a target straight above or below", function()
		for _, target in { Vector3.new(0, 10, 0), Vector3.new(0, -10, 0), Vector3.zero } do
			local dir = ProjectileMath.solveLaunchDir(Vector3.zero, target, 95, 35)
			expect.near(dir.Magnitude, 1, 1e-4)
			expect.truthy(dir.X == dir.X and dir.Y == dir.Y and dir.Z == dir.Z)
		end
	end)

	t.test("solveLaunchDir with g = 0 aims straight at the target", function()
		local dir = ProjectileMath.solveLaunchDir(Vector3.zero, Vector3.new(30, 10, 40), 260, 0)
		expectVectorNear(expect, dir, Vector3.new(30, 10, 40).Unit, 1e-5)
	end)

	t.test("solveLaunchDir honours custom limits", function()
		local dir = ProjectileMath.solveLaunchDir(
			Vector3.zero,
			Vector3.new(300, 0, 0),
			85,
			50,
			{ minDeg = -10, maxDeg = 30, noSolutionDeg = 45 }
		)
		expect.near(ProjectileMath.pitchDeg(dir), 30 - ProjectileMath.PITCH_INSET_DEG, PITCH_TOLERANCE_DEG)
	end)

	t.test("pitchDeg reads the angle above the horizontal", function()
		expect.near(ProjectileMath.pitchDeg(Vector3.new(1, 1, 0)), 45, 1e-5)
		expect.near(ProjectileMath.pitchDeg(Vector3.new(0, -1, -1)), -45, 1e-5)
		expect.near(ProjectileMath.pitchDeg(Vector3.new(0, 0, -1)), 0, 1e-9)
		expect.equal(ProjectileMath.pitchDeg(Vector3.zero), 0)
	end)

	-- Sweep --------------------------------------------------------------------------------------------------------

	t.test("substepCount is clamp(ceil(span · 60), 1, 6)", function()
		expect.equal(ProjectileMath.substepCount(1 / 60), 1)
		expect.equal(ProjectileMath.substepCount(0.001), 1)
		expect.equal(ProjectileMath.substepCount(0.05), 3)
		expect.equal(ProjectileMath.substepCount(4 / 60), 4)
		expect.equal(ProjectileMath.substepCount(0.5), Config.Combat.Projectile.maxSubsteps)
		expect.equal(ProjectileMath.substepCount(0), 1)
		expect.equal(ProjectileMath.substepCount(0.05, 120, 10), 6)
	end)

	t.test("subSteps cover (tPrev, tNow] contiguously with exact end points", function()
		local o, v, g = Vector3.new(0, 4.8, -42.5), Vector3.new(0, 25, 90), 35
		local steps = ProjectileMath.subSteps(o, v, g, 0.1, 0.15)
		expect.equal(#steps, 3)
		expect.equal(steps[1].a, 0.1)
		expect.equal(steps[#steps].b, 0.15)
		for index, step in steps do
			expect.truthy(step.b > step.a)
			expect.equal(step.p0, ProjectileMath.positionAt(o, v, g, step.a))
			expect.equal(step.p1, ProjectileMath.positionAt(o, v, g, step.b))
			if index > 1 then
				expect.equal(step.a, steps[index - 1].b)
				expect.equal(step.p0, steps[index - 1].p1)
			end
		end
	end)

	t.test("subSteps is empty when no time passed and capped after a hitch", function()
		local o, v = Vector3.zero, Vector3.new(0, 0, 90)
		expect.equal(#ProjectileMath.subSteps(o, v, 35, 0.2, 0.2), 0)
		expect.equal(#ProjectileMath.subSteps(o, v, 35, 0.3, 0.2), 0)
		local hitch = ProjectileMath.subSteps(o, v, 35, 0, 1)
		expect.equal(#hitch, Config.Combat.Projectile.maxSubsteps)
		expect.equal(hitch[#hitch].b, 1)
	end)

	t.test("impactTime is releaseAt + a + f·(b - a), with f clamped to [0, 1]", function()
		expect.near(ProjectileMath.impactTime(1000, 0.2, 0.25, 0.5), 1000.225, 1e-9)
		expect.near(ProjectileMath.impactTime(1000, 0.2, 0.25, -1), 1000.2, 1e-9)
		expect.near(ProjectileMath.impactTime(1000, 0.2, 0.25, 2), 1000.25, 1e-9)
	end)

	-- Client path (§9.7) ---------------------------------------------------------------------------------------------

	t.test("settledPositionAt starts in the hand and settles on the server path", function()
		local o, v, g = Vector3.new(0, 4.8, 0), Vector3.new(0, 20, 90), 35
		local offset = Vector3.new(-0.6, -0.4, 0.3)
		local tau = Config.Anim.throw.pathSettleTau
		expectVectorNear(expect, ProjectileMath.settledPositionAt(o, v, g, 0, offset), o + offset, 1e-5)
		expectVectorNear(expect, ProjectileMath.settledPositionAt(o, v, g, -0.1, offset), o + offset, 1e-5)
		local later = 10 * tau
		expectVectorNear(
			expect,
			ProjectileMath.settledPositionAt(o, v, g, later, offset),
			ProjectileMath.positionAt(o, v, g, later),
			1e-3
		)
		expectVectorNear(
			expect,
			ProjectileMath.settledPositionAt(o, v, g, 0.3, offset, 0),
			ProjectileMath.positionAt(o, v, g, 0.3),
			1e-6
		)
	end)
end
