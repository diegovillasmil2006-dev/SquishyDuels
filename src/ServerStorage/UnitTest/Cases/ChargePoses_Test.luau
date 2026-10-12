--!strict
-- ChargePoses_Test: unit tests for StarterPlayerScripts.Client.Anim.ChargePoses (feature 1, 2026-10-11: the charge,
-- catch and crush poses of the first-person overlay; design: the combat-effects page "Squishy Combat FP v2.html",
-- html:498-553). Server only (ServerStorage.UnitTest). Pure: no instances, no clock; random nil = no jitter.
-- Contract:
--   * map: a design offset × depthScale·fovScale across and × depthScale in depth; size: metres / the held toy's 0.066;
--   * the charge: at c = 0 the hold (no glow, orbit, outline, squash); the toy reaches its charged point once
--     ease(c·1.4) is 1; the glow from c 0.2 (≤ 0.24), the orbit from 0.4, the outline, squish face, shake 0.12 and
--     100 sparks a second at full; the left hand away, then steadying the toy with its roll turned to 1.3;
--   * the catch: the hands open from rest over 0.07 s, the own toy tucked away;
--   * the crush: e = (t - 0.12) / 0.9; at e 0 the "wow" face, no squeeze; at e 1 the scale (0.48, 1.3, 1.22), the squish
--     face, the orbit, 80 specks a second, camera shake 0.55; ReducedMotion: no wobble, no shake, no flicker;
--   * crushShape: the crush's scale and its shake in the caught toy's radii (0 under ReducedMotion).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-6

return function(t: Context)
	local ChargePoses = t.requireClient("Anim/ChargePoses")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local FP = Config.FirstPerson
	local V2, CHARGE, CATCH, CRUSH = FP.v2, FP.charge, FP.catch, FP.crush
	local ARM_ROLL = FP.arm.roll

	local HOLD = Vector3.new(0, -0.3, -0.9)
	local FRAME = {
		hold = HOLD,
		sideL = HOLD + Vector3.new(-0.1, 0, 0),
		sideR = HOLD + Vector3.new(0.1, 0, 0),
		restL = Vector3.new(-0.3, -0.5, -0.8),
		restR = Vector3.new(0.3, -0.5, -0.8),
	}

	local function close(a: Vector3, b: Vector3, tolerance: number?)
		expect.near((a - b).Magnitude, 0, tolerance or EPS)
	end

	t.test("map and size: the design's moves on our camera, its sizes in toy radii", function()
		local across = V2.depthScale * V2.fovScale
		close(ChargePoses.map(Vector3.new(1, 2, 3)), Vector3.new(across, 2 * across, 3 * V2.depthScale))
		expect.near(ChargePoses.size(0.066), 1, EPS)
		expect.near(ChargePoses.size(0.132), 2, EPS)
	end)

	t.test("the charge at c = 0 is the hold: nothing glows, orbits or squashes", function()
		local pose = ChargePoses.charge(0, 0, FRAME, nil, false)
		close(pose.toy, HOLD)
		close(pose.right, FRAME.sideR)
		close(pose.left, FRAME.sideL)
		close(pose.scale, Vector3.one)
		expect.equal(pose.glow, 0)
		expect.falsy(pose.orbit)
		expect.falsy(pose.outline)
		expect.falsy(pose.squish)
		expect.falsy(pose.full)
		expect.equal(pose.shake, 0)
		expect.equal(pose.sparkRate, 0)
	end)

	t.test("the glow from 0.2, the orbit from 0.4, sparks past 0.2; the toy at its charged point by c 1/1.4", function()
		expect.equal(ChargePoses.charge(0.2, 0, FRAME, nil, false).glow, 0)
		expect.near(ChargePoses.charge(0.5, 0, FRAME, nil, false).glow, 0.3 * CHARGE.glowGain, EPS)
		expect.near(ChargePoses.charge(0.95, 0, FRAME, nil, false).glow, CHARGE.glowMax, EPS)
		expect.falsy(ChargePoses.charge(0.39, 0, FRAME, nil, false).orbit)
		expect.truthy(ChargePoses.charge(0.4, 0, FRAME, nil, false).orbit)
		expect.equal(ChargePoses.charge(0.2, 0, FRAME, nil, false).sparkRate, 0)
		expect.near(ChargePoses.charge(0.5, 0, FRAME, nil, false).sparkRate, CHARGE.sparkRate + 0.5 * 70, EPS)
		local charged = HOLD + ChargePoses.map(CHARGE.toy - V2.hold)
		close(ChargePoses.charge(1 / CHARGE.easeGain + 0.01, 0, FRAME, nil, false).toy, charged)
		-- The squash grows with c: flatter in Y, wider in X.
		local half = ChargePoses.charge(0.5, 0, FRAME, nil, false).scale
		expect.truthy(half.Y < 1 and half.X > 1)
	end)

	t.test("full: the outline, the squish face, shake 0.12, 100 sparks a second, the orbit at its full spin", function()
		local pose = ChargePoses.charge(1, 0, FRAME, nil, false)
		expect.truthy(pose.full)
		expect.truthy(pose.outline)
		expect.truthy(pose.squish)
		expect.equal(pose.shake, CHARGE.shake)
		expect.equal(CHARGE.shake, 0.12) -- design: html:514
		expect.near(pose.sparkRate, CHARGE.sparkRate + CHARGE.sparkRateGain, EPS)
		expect.equal(pose.orbitSpin, CHARGE.orbitSpinFull)
		expect.equal(pose.orbitScale, 1)
		-- The left hand steadies the toy, its roll turned to leftRollTo.
		local steady = pose.toy + (FRAME.sideL - HOLD) + ChargePoses.map(CHARGE.leftSteady - (V2.holdL - V2.hold))
		close(pose.left, steady)
		expect.near(pose.lRoll, ARM_ROLL + (CHARGE.leftRollTo - V2.rollL), EPS)
		expect.near(pose.rRoll, -ARM_ROLL, EPS)
	end)

	t.test("at full the squash and glow pulse; ReducedMotion holds them and never jitters", function()
		local random = Random.new(3)
		local a = ChargePoses.charge(1, 0.1, FRAME, random, false)
		local b = ChargePoses.charge(1, 0.2, FRAME, random, false)
		expect.truthy(math.abs(a.scale.Y - b.scale.Y) > 1e-4)
		local ra = ChargePoses.charge(1, 0.1, FRAME, Random.new(3), true)
		local rb = ChargePoses.charge(1, 0.2, FRAME, Random.new(4), true)
		close(ra.scale, rb.scale)
		expect.near(ra.glow, rb.glow, EPS)
		close(ra.toy, HOLD + ChargePoses.map(CHARGE.toy - V2.hold)) -- no jitter
	end)

	t.test("the catch: the hands open from rest over 0.07 s; the own toy tucked away", function()
		local start = ChargePoses.catch(0, FRAME)
		close(start.left, FRAME.restL)
		close(start.right, FRAME.restR)
		local open = ChargePoses.catch(CATCH.openSeconds, FRAME)
		close(open.left, FRAME.restL + ChargePoses.map(CATCH.handL - V2.emptyL))
		close(open.right, FRAME.restR + ChargePoses.map(CATCH.handR - V2.emptyR))
		close(open.toy, HOLD + ChargePoses.map(CATCH.toy - V2.hold))
		expect.near(open.lRoll, ARM_ROLL + (CATCH.rollL - V2.rollL), EPS)
		expect.near(open.rRoll, -ARM_ROLL + (CATCH.rollR - V2.rollR), EPS)
	end)

	t.test("the crush: wow, then squeezed and grown by e²; the orbit, specks and camera shake rise", function()
		local first = ChargePoses.crush(0.05, FRAME, nil, true)
		expect.equal(first.face, "wow")
		close(first.scale, Vector3.one)
		expect.equal(first.glow, 0)
		expect.falsy(first.orbit)
		expect.equal(first.speckRate, 0)
		expect.near(first.cameraShake, CRUSH.shake, EPS)
		expect.equal(first.tone, 0)
		local full = ChargePoses.crush(CRUSH.easeFrom + CRUSH.easeOver, FRAME, nil, true)
		expect.equal(full.face, "squish")
		close(full.scale, Vector3.new(1 - CRUSH.squeezeX, 1 + CRUSH.growY, 1 + CRUSH.growZ))
		expect.truthy(full.orbit)
		expect.near(full.speckRate, CRUSH.speckRate, EPS)
		expect.near(full.cameraShake, CRUSH.shake + CRUSH.shakeGainE, EPS)
		expect.near(full.press, 1, EPS)
		expect.near(full.glow, CRUSH.glow, EPS) -- no flicker under ReducedMotion
		close(full.shake, Vector3.zero)
		close(full.toy, HOLD + ChargePoses.map(CRUSH.base - V2.hold))
		close(full.held, HOLD + ChargePoses.map(CRUSH.toy - V2.hold))
		-- With motion: it wobbles and shakes.
		local moving = ChargePoses.crush(0.9, FRAME, Random.new(1), false)
		expect.truthy(moving.shake.Magnitude > 0)
	end)

	t.test("crushShape: the crush's scale, and its shake in the caught toy's radii", function()
		for _, at in { 0.05, 0.5, 0.9, 1.02 } do
			local scale, shake = ChargePoses.crushShape(at, true)
			close(scale, ChargePoses.crush(at, FRAME, nil, true).scale)
			expect.equal(shake, 0)
		end
		local _, shake = ChargePoses.crushShape(CRUSH.easeFrom + CRUSH.easeOver, false)
		local radius = V2.toyRadius * CRUSH.toyScale
		expect.near(shake, (CRUSH.shakeBase + CRUSH.shakeGain) / radius, EPS)
		local _, early = ChargePoses.crushShape(0, false)
		expect.near(early, CRUSH.shakeBase / radius, EPS)
	end)
end
