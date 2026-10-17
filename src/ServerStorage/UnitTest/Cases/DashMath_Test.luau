--!strict
-- DashMath_Test: unit tests for ReplicatedStorage.Shared.DashMath (spec phase 5 §3.3; the design's dash). Server only
-- (ServerStorage.UnitTest). Pure math, runs in Edit mode.
-- Contract (design numbers in Config.Duel.Rules.Dash):
--   * the dash covers distanceStuds (14) in seconds (0.22) along e(x) = 1 - (1 - x)³ (design: fp.js:537), so 87.5% of
--     it is done halfway, and it never moves before 0 or after the end;
--   * clampToZone keeps the end point inside a box shrunk by a margin on X and Z (the own half minus the body radius,
--     so a dash never crosses into the neutral band), from an origin that may already sit in the margin;
--   * snapDirection picks one of 4 camera-relative directions from the movement input (no input = forward);
--   * poseKey says which design key (F, B, L or R: avatar.js:102) a world direction is for a character's facing;
--   * the visual timeline: 12 frames at 30 fps, push-off at frame 2 and plant at frame 7, full weight until frame 9 then
--     w² (design: avatar.js:79-99, 155-161).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local DashMath = t.requireShared("DashMath")
	local Config = t.requireShared("Config")
	local DASH = Config.Duel.Rules.Dash

	local function near(a: Vector3, b: Vector3, tolerance: number?)
		expect.near((a - b).Magnitude, 0, tolerance or 1e-6)
	end

	-- Movement overhaul (2026-10-17): 18 studs (the design's 14) and a 1.3 s cooldown (2 s before).
	t.test("the numbers: 18 studs in 0.22 s, 12 frames at 30 fps, push-off f2, plant f7", function()
		expect.equal(DASH.distanceStuds, 18)
		expect.equal(DASH.seconds, 0.22)
		expect.equal(DASH.visualFrames, 12)
		expect.equal(DASH.visualFps, 30)
		expect.equal(DASH.pushoffFrame, 2)
		expect.equal(DASH.plantFrame, 7)
		expect.equal(DASH.cooldownSeconds, 1.3)
	end)

	t.test("the ease-out cubic: 0 at the start, 87.5% halfway, all of it at the end, never past it", function()
		expect.near(DashMath.ease(0), 0, 1e-12)
		expect.near(DashMath.ease(0.5), 0.875, 1e-12)
		expect.near(DashMath.ease(1), 1, 1e-12)
		expect.near(DashMath.ease(-1), 0, 1e-12)
		expect.near(DashMath.ease(2), 1, 1e-12)
		expect.near(DashMath.offsetAt(0.11, 14, 0.22), 14 * 0.875, 1e-9)
		expect.near(DashMath.offsetAt(0.22, 14, 0.22), 14, 1e-9)
		expect.near(DashMath.offsetAt(1, 14, 0.22), 14, 1e-9)
		expect.near(DashMath.offsetAt(-0.1, 14, 0.22), 0, 1e-9)
		-- The peak speed is at the start: 3 × 14 / 0.22 ≈ 191 studs/s (spec §1.2, derived).
		expect.near(DashMath.speedAt(0, 14, 0.22), 3 * 14 / 0.22, 1e-6)
		expect.near(DashMath.speedAt(0.22, 14, 0.22), 0, 1e-9)
	end)

	-- A half like WorldLayout's HalfA: X -36..36, Z -52..-8.
	local HALF = { cframe = CFrame.new(0, 12.5, -30), size = Vector3.new(72, 55, 44) }

	t.test("clampToZone: a full dash inside the half keeps its length", function()
		expect.near(DashMath.clampToZone(Vector3.new(0, 3, -30), Vector3.new(1, 0, 0), 14, HALF, 1.3), 14, 1e-9)
	end)

	t.test("clampToZone: a dash toward the neutral band stops a body radius before it", function()
		-- From Z -15 forward (+Z): the half ends at -8, minus the margin 1.3 = -9.3, so 5.7 studs.
		expect.near(DashMath.clampToZone(Vector3.new(0, 3, -15), Vector3.new(0, 0, 1), 14, HALF, 1.3), 5.7, 1e-6)
		-- Toward a side wall at X 36: 36 - 1.3 - 30 = 4.7.
		expect.near(DashMath.clampToZone(Vector3.new(30, 3, -30), Vector3.new(1, 0, 0), 14, HALF, 1.3), 4.7, 1e-6)
		-- Diagonal: the nearer limit wins.
		local diagonal = Vector3.new(1, 0, 1).Unit
		expect.near(DashMath.clampToZone(Vector3.new(0, 3, -15), diagonal, 14, HALF, 1.3), 5.7 / diagonal.Z, 1e-6)
	end)

	t.test("clampToZone: from inside the margin, a dash further out goes nowhere, one back inward is whole", function()
		local edge = Vector3.new(0, 3, -8.5) -- 0.8 studs past the shrunk edge at -9.3
		expect.near(DashMath.clampToZone(edge, Vector3.new(0, 0, 1), 14, HALF, 1.3), 0, 1e-9)
		expect.near(DashMath.clampToZone(edge, Vector3.new(0, 0, -1), 14, HALF, 1.3), 14, 1e-9)
		-- Sideways along the band from there: X is free, Z does not change.
		expect.near(DashMath.clampToZone(edge, Vector3.new(1, 0, 0), 14, HALF, 1.3), 14, 1e-9)
	end)

	t.test("snapDirection: no input is forward; otherwise the nearest of the 4 camera directions", function()
		local look, right = Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)
		local key, dir = DashMath.snapDirection(Vector3.zero, look, right)
		expect.equal(key, "F")
		near(dir, look)
		key, dir = DashMath.snapDirection(Vector3.new(0.2, 0, 0.98).Unit, look, right) -- mostly back
		expect.equal(key, "B")
		near(dir, -look)
		key, dir = DashMath.snapDirection(Vector3.new(-0.9, 0, -0.3).Unit, look, right) -- mostly left
		expect.equal(key, "L")
		near(dir, -right)
		key, dir = DashMath.snapDirection(Vector3.new(0.7, 0, -0.69).Unit, look, right) -- just more right than forward
		expect.equal(key, "R")
		near(dir, right)
		-- The camera's tilt never leaks in: the look is flattened first.
		local tilted = Vector3.new(0, -0.6, -0.8)
		local _, flat = DashMath.snapDirection(Vector3.zero, tilted, right)
		near(flat, Vector3.new(0, 0, -1))
	end)

	t.test("poseKey: the design key for a world direction, relative to the character's facing", function()
		local facing = Vector3.new(0, 0, -1) -- a Roblox character faces -Z; its right is +X
		expect.equal(DashMath.poseKey(Vector3.new(0, 0, -1), facing), "F")
		expect.equal(DashMath.poseKey(Vector3.new(0, 0, 1), facing), "B")
		expect.equal(DashMath.poseKey(Vector3.new(1, 0, 0), facing), "R")
		expect.equal(DashMath.poseKey(Vector3.new(-1, 0, 0), facing), "L")
		-- Turned to face +X: a world -Z dash is to its left.
		expect.equal(DashMath.poseKey(Vector3.new(0, 0, -1), Vector3.new(1, 0, 0)), "L")
	end)

	t.test("isFlatUnit: a unit vector along the ground only", function()
		expect.truthy(DashMath.isFlatUnit(Vector3.new(1, 0, 0)))
		expect.truthy(DashMath.isFlatUnit(Vector3.new(0.6, 0.01, 0.8)))
		expect.falsy(DashMath.isFlatUnit(Vector3.new(0.6, 0.3, 0.74)))
		expect.falsy(DashMath.isFlatUnit(Vector3.new(2, 0, 0)))
		expect.falsy(DashMath.isFlatUnit(Vector3.zero))
	end)

	t.test("the pose timeline: frame f at f / 30 s; weight 1 until frame 9, then ((12 - f) / 3)²", function()
		expect.near(DashMath.frameAt(0.1), 3, 1e-9)
		expect.near(DashMath.weightAt(0), 1, 1e-9)
		expect.near(DashMath.weightAt(8.9), 1, 1e-9)
		expect.near(DashMath.weightAt(10.5), 0.25, 1e-9) -- ((12 - 10.5) / 3)² (design: avatar.js:160-161)
		expect.near(DashMath.weightAt(12), 0, 1e-9)
		expect.near(DashMath.weightAt(13), 0, 1e-9)
		-- Push-off at frame 2 (0.067 s) and plant at frame 7 (0.233 s).
		expect.near(DashMath.eventSeconds(DASH.pushoffFrame), 2 / 30, 1e-9)
		expect.near(DashMath.eventSeconds(DASH.plantFrame), 7 / 30, 1e-9)
	end)

	t.test("sampleKeys: cosine ease between keys; the held-arm offset blends with the same ease", function()
		local keys = {
			{ f = 0, angles = { Root = Vector3.new(-10, 0, 0) }, hold = 0 },
			{ f = 2, angles = { Root = Vector3.new(-24, 0, 0) }, hold = 8 },
		}
		local angles, hold = DashMath.sampleKeys(keys, 1)
		-- ease(0.5) = 0.5 - 0.5·cos(π/2) = 0.5 (design: avatar.js:120, 126)
		near(angles.Root, Vector3.new(-17, 0, 0), 1e-9)
		expect.near(hold, 4, 1e-9)
		local first = DashMath.sampleKeys(keys, -1)
		near(first.Root, Vector3.new(-10, 0, 0), 1e-9)
		local last, lastHold = DashMath.sampleKeys(keys, 5)
		near(last.Root, Vector3.new(-24, 0, 0), 1e-9)
		expect.near(lastHold, 0, 1e-9) -- past the last key the hold offset is 0 (avatar.js:128)
	end)
end
