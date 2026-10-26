--!strict
-- KneadMath_Test: unit tests for StarterPlayerScripts.Client.Anim.KneadMath, the small formulas of the knead screen in
-- Inspect (spec phase2-squeeze §3.3, §3.5, §3.6). Server only (ServerStorage.UnitTest). Pure. Contract:
--   * kickPeak: the design's kick jv += 20·v on the feel's jiggle spring, as the rig's kick (the first-swing peak):
--     foam about 1.0·v (spec §3.3), the exact damped-spring peak for every feel, the sign kept, 0 for 0;
--   * kneadZoom: the design's knead fit with the stage as the free area: 0.82 of the width or 0.74 of the height at
--     0.42 du in a 70° camera, never below 1; duToStuds: maxDim / (0.19·kz);
--   * approach: 1 - e^(-rate·dt); tilt: toward the target at that share, the yaw the short way round;
--   * moveAction: a pressed finger kneads while it is on the toy, stretches off it, and keeps stretching once pulling
--     (fp.js:636); ringState: hidden / over / press / pull (html:59-62);
--   * barycentric: the weights of a point in a triangle (they sum to 1 and rebuild the point);
--   * pressAxis / pressScale (owner 2026-10-26): a pressed rider's mesh Scale multiplier: the axis the press runs most
--     along (a tie: the first), squashed by amount, the other two bulged so the volume stays; rayPart: where a ray first
--     meets a part's ellipsoid (E) or box (other shapes).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local KneadMath = t.requireClient("Anim/KneadMath")
	local Config = t.requireShared("Config")
	local expect = t.expect

	-- The first peak of x'' = -k x - c x' after an impulse velocity v0, by brute-force integration.
	local function simulatedPeak(k: number, c: number, v0: number): number
		local x, v, peak = 0, v0, 0
		local h = 1e-5
		for _ = 1, 200000 do
			v += (-k * x - c * v) * h
			x += v * h
			if math.abs(x) > math.abs(peak) then
				peak = x
			elseif math.abs(x) < math.abs(peak) * 0.999 then
				break
			end
		end
		return peak
	end

	t.test("kickPeak: the design's 20·v kick as the rig's first-swing peak (foam about 1.0·v)", function()
		expect.near(KneadMath.kickPeak(1, "foam"), 1.0, 0.01)
		for feel, spring in Config.Anim.rig.feels do
			local v = 0.022
			local expected = simulatedPeak(spring.k, spring.c, Config.Knead.kickVelocity * v)
			expect.near(KneadMath.kickPeak(v, feel), expected, math.abs(expected) * 0.002)
		end
		expect.truthy(KneadMath.kickPeak(-0.016, "jelly") < 0)
		expect.equal(KneadMath.kickPeak(0, "mochi"), 0)
		-- An unknown feel is foam (the rig's own rule).
		expect.equal(KneadMath.kickPeak(0.05, "no_such_feel"), KneadMath.kickPeak(0.05, "foam"))
	end)

	t.test(
		"kneadZoom: 0.82 of the width or 0.74 of the height in the design's 70° camera at 0.42 du, at least 1",
		function()
			local view = Config.Knead.view
			local vh = 2 * view.fitDepth * math.tan(math.rad(view.cameraFovDeg) / 2)
			-- A wide toy on a square stage: the width decides.
			local box = Vector3.new(2, 0.5, 1)
			local K = view.toyLongestDu / 2
			local byWidth = view.fitWidth * vh / (2 * K)
			local byHeight = view.fitHeight * vh / (0.5 * K)
			expect.near(KneadMath.kneadZoom(Vector2.new(600, 600), box), math.min(byWidth, byHeight), 1e-9)
			expect.near(KneadMath.kneadZoom(Vector2.new(600, 600), box), byWidth, 1e-9)
			-- Half as wide a stage halves the width's zoom.
			expect.near(KneadMath.kneadZoom(Vector2.new(300, 600), box), byWidth / 2, 1e-9)
			-- A tiny stage never zooms below 1; a bad size counts as square.
			expect.equal(KneadMath.kneadZoom(Vector2.new(40, 600), Vector3.new(1, 1, 1)), 1)
			expect.near(KneadMath.kneadZoom(Vector2.new(0, 0), box), byWidth, 1e-9)
		end
	)

	t.test("duToStuds: the toy is 0.19·kz du long, maxDim studs", function()
		expect.near(KneadMath.duToStuds(1.53, 3), 1.53 / (0.19 * 3), 1e-12)
		expect.near(KneadMath.duToStuds(2, 1), 2 / 0.19, 1e-12)
	end)

	t.test("approach and tilt: 1 - e^(-rate·dt) of the way, the yaw the short way round", function()
		expect.near(KneadMath.approach(8, 1 / 60), 1 - math.exp(-8 / 60), 1e-12)
		expect.equal(KneadMath.approach(5, 0), 0)
		local share = KneadMath.approach(5, 0.1)
		local dYaw, dPitch = KneadMath.tilt(350, 10, 0, 25.8, 5, 0.1)
		expect.near(dYaw, 10 * share, 1e-9) -- 350 -> 360 (0) is +10 the short way
		expect.near(dPitch, 15.8 * share, 1e-9)
		local backYaw = KneadMath.tilt(20, 0, 0, 0, 5, 0.1)
		expect.near(backYaw, -20 * share, 1e-9)
	end)

	t.test("moveAction: knead on the toy, stretch off it, and keep stretching once pulling", function()
		expect.equal(KneadMath.moveAction(false, true), "fingerMove")
		expect.equal(KneadMath.moveAction(false, false), "pullTo")
		expect.equal(KneadMath.moveAction(true, true), "pullTo")
		expect.equal(KneadMath.moveAction(true, false), "pullTo")
	end)

	t.test("ringState: hidden, over the toy, pressing, stretching", function()
		expect.equal(KneadMath.ringState(false, false, false), "hidden")
		expect.equal(KneadMath.ringState(false, false, true), "over")
		expect.equal(KneadMath.ringState(true, false, false), "press")
		expect.equal(KneadMath.ringState(true, false, true), "press")
		expect.equal(KneadMath.ringState(true, true, false), "pull")
	end)

	t.test("barycentric: weights that sum to 1 and rebuild the point", function()
		local a, b, c = Vector3.new(0, 0, 0), Vector3.new(2, 0, 0), Vector3.new(0, 3, 1)
		local p = a * 0.2 + b * 0.5 + c * 0.3
		local wa, wb, wc = KneadMath.barycentric(p, a, b, c)
		expect.near(wa, 0.2, 1e-9)
		expect.near(wb, 0.5, 1e-9)
		expect.near(wc, 0.3, 1e-9)
		-- A point off the plane takes its projection's weights; a degenerate triangle gives the first corner.
		local wa2, wb2, wc2 = KneadMath.barycentric(p + (b - a):Cross(c - a).Unit * 0.4, a, b, c)
		expect.near(wa2, 0.2, 1e-9)
		expect.near(wb2, 0.5, 1e-9)
		expect.near(wc2, 0.3, 1e-9)
		local d1, d2, d3 = KneadMath.barycentric(p, a, a, a)
		expect.deepEqual({ d1, d2, d3 }, { 1, 0, 0 })
	end)

	-- Owner 2026-10-26 ("wings dont squish, check every model"): a pressed rider (wing, tail, ear, gill, leaf...) squashes.
	t.test("pressAxis / pressScale: its strongest axis squashed, the others bulged; none at 0", function()
		local function nearV(a: Vector3, b: Vector3)
			expect.near((a - b).Magnitude, 0, 1e-6) -- a Vector3 holds 32-bit floats
		end
		expect.equal(KneadMath.pressAxis(Vector3.new(1, 0, 0)), 1)
		expect.equal(KneadMath.pressAxis(Vector3.new(0, 0, -2)), 3) -- any length, either way
		-- A slanted press (in Studio the dragon's wing took (-0.68, -0.37, 0.63)) still picks one axis.
		expect.equal(KneadMath.pressAxis(Vector3.new(-0.68, -0.37, 0.63)), 1)
		expect.equal(KneadMath.pressAxis(Vector3.new(1, 1, 0)), 1) -- a tie: the first
		local w = 1 / math.sqrt(0.7)
		nearV(KneadMath.pressScale(1, 0.3), Vector3.new(0.7, w, w))
		nearV(KneadMath.pressScale(3, 0.3), Vector3.new(w, w, 0.7))
		nearV(KneadMath.pressScale(2, 0), Vector3.one)
		local s = KneadMath.pressScale(2, -0.2) -- a rebound stretches along the press
		expect.truthy(s.Y > 1 and s.X < 1)
		expect.near(s.X * s.Y * s.Z, 1, 1e-6)
	end)

	t.test("rayPart: where a ray first meets a part's ellipsoid (E) or box (other shapes), as a share", function()
		local at = CFrame.new(0, 0, -5) * CFrame.Angles(0, math.rad(90), 0)
		local size = Vector3.new(2, 2, 2)
		local front, back = Vector3.new(0, 0, 5), Vector3.new(0, 0, -10)
		-- Straight at its centre from 10 studs: the near surface 9 studs on, 0.9 of the 10-stud ray.
		expect.near(KneadMath.rayPart(at, size, "E", front, back) :: number, 0.9, 1e-9)
		-- Past a corner: misses the ellipsoid, hits the box.
		local origin = Vector3.new(0.9, 0.9, 5)
		expect.equal(KneadMath.rayPart(at, size, "E", origin, back), nil)
		expect.near(KneadMath.rayPart(at, size, "W", origin, back) :: number, 0.9, 1e-9)
		-- A ray that stops short or points away meets nothing.
		expect.equal(KneadMath.rayPart(at, size, "B", front, Vector3.new(0, 0, -2)), nil)
		expect.equal(KneadMath.rayPart(at, size, "B", front, Vector3.new(0, 0, 10)), nil)
	end)
end
