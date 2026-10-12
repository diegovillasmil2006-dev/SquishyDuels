--!strict
-- ThrowCharge_Test: unit tests for ReplicatedStorage.Shared.ThrowCharge (feature 1, 2026-10-11: the charge throw;
-- design: the combat-effects page "Squishy Combat FP v2.html"). Server only (ServerStorage.UnitTest). Pure.
-- Contract:
--   * c rises 0 -> 1 over Combat.Charge.seconds and stays in 0..1 (bad times give 0) (design: html:499);
--   * the server's measure counts from the later of the charge start and the throw's ready moment; no start, or a time
--     that is not finite, is an uncharged throw (0);
--   * the speed is × (1 + speedGain·c) (design: html:330: 20 -> 37 at full);
--   * a trail is × (1 + 0.22/0.15·p) wide and × (1 + 0.22/0.3·p) long (design: html:243);
--   * the release: puffs, ring, FOV kick and kick grow with p; the white ring from 0.45, the ring across the path from
--     0.6 (0.5 + 0.4p m), the hit-stop only at full (design: html:333-339);
--   * the FOV narrows by fovNarrowDeg·c and the walk is × walkFactor (design: html:437, 463);
--   * in-flight specks only without a rarity emitter, never over Effects.projectileParticles live (design: html:605);
--   * the tone's pitch and volume rise with c; a tremolo only at full (design: squishy-lib-v2.js:384);
--   * the ease is the design's quadratic in-out (design: html:115).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

local EPS = 1e-9
local NOW = 1_800_000_000

return function(t: Context)
	local ThrowCharge = t.requireShared("ThrowCharge")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local CHARGE = Config.Combat.Charge
	local VFX = Config.Vfx.Charge
	local TONE = Config.Audio.charge

	t.test("c rises over Charge.seconds and stays in 0..1; bad times give 0", function()
		expect.equal(CHARGE.seconds, 1.0) -- design: html:499
		expect.near(ThrowCharge.level(NOW, NOW), 0, EPS)
		expect.near(ThrowCharge.level(NOW, NOW + 0.25), 0.25, 1e-6)
		expect.near(ThrowCharge.level(NOW, NOW + 0.5, 2), 0.25, 1e-6)
		expect.equal(ThrowCharge.level(NOW, NOW + 5), 1)
		expect.equal(ThrowCharge.level(NOW, NOW - 1), 0)
		expect.equal(ThrowCharge.level(0 / 0, NOW), 0)
		expect.equal(ThrowCharge.level(NOW, math.huge), 0)
		expect.equal(ThrowCharge.level(NOW, NOW + 1, 0), 0)
		expect.truthy(ThrowCharge.isFull(ThrowCharge.level(NOW, NOW + 1)))
		expect.falsy(ThrowCharge.isFull(0.999))
	end)

	t.test("the server's measure counts from the later of the start and the ready moment; no start is 0", function()
		expect.equal(ThrowCharge.measure(nil, NOW, NOW - 5), 0)
		expect.near(ThrowCharge.measure(NOW - 0.4, NOW, NOW - 5), 0.4, 1e-6)
		-- Pressed during the cooldown: the charge only counts once the throw is ready.
		expect.near(ThrowCharge.measure(NOW - 0.9, NOW, NOW - 0.3), 0.3, 1e-6)
		expect.equal(ThrowCharge.measure(NOW - 3, NOW, NOW - 5), 1)
		expect.equal(ThrowCharge.measure(NOW + 1, NOW, NOW - 5), 0) -- a start after the press
		expect.equal(ThrowCharge.measure(0 / 0, NOW, NOW), 0)
		expect.equal(ThrowCharge.measure(NOW - 0.5, math.huge, NOW), 0)
		expect.near(ThrowCharge.measure(NOW - 0.5, NOW, 0 / 0), 0.5, 1e-6) -- an unknown ready moment: from the start
	end)

	t.test("speed × (1 + 17/20·c): 20 -> 37 m/s at full, as the design", function()
		expect.near(ThrowCharge.speedFactor(0), 1, EPS)
		expect.near(20 * ThrowCharge.speedFactor(1), 37, 1e-9) -- design: html:330
		expect.near(ThrowCharge.speedFactor(0.5), 1 + 0.425, 1e-9)
		expect.near(ThrowCharge.speedFactor(2), ThrowCharge.speedFactor(1), EPS) -- clamped
		expect.near(ThrowCharge.speedFactor(1, 0.5), 1.5, EPS)
	end)

	t.test("the trail grows with the power: 0.15 -> 0.37 wide, 0.3 -> 0.52 s long (design: html:243)", function()
		local width, life = ThrowCharge.trailFactors(0)
		expect.near(width, 1, EPS)
		expect.near(life, 1, EPS)
		width, life = ThrowCharge.trailFactors(1)
		expect.near(0.15 * width, 0.37, 1e-9)
		expect.near(0.3 * life, 0.52, 1e-9)
		width, life = ThrowCharge.trailFactors(nil)
		expect.near(width, 1, EPS)
		width = ThrowCharge.trailFactors(0 / 0)
		expect.near(width, 1, EPS)
	end)

	t.test(
		"the release grows with the power; the white ring from 0.45, the path ring from 0.6, the stop at full",
		function()
			local none = ThrowCharge.release(0)
			expect.near(none.puffs, 1, EPS)
			expect.near(none.ring, 1, EPS)
			expect.near(none.fovKick, 1, EPS)
			expect.near(none.kick, 1, EPS)
			expect.falsy(none.whiteRing)
			expect.falsy(none.powerRing)
			expect.equal(none.hitStop, nil)
			local full = ThrowCharge.release(1)
			expect.near(8 * full.puffs, 22, 1e-9) -- design: html:336 (8 + 14c)
			expect.near(0.09 * full.ring, 0.14, 1e-9) -- design: html:335 (0.09 + 0.05c)
			expect.near(60 * full.fovKick, 180, 1e-9) -- design: html:333 (60 + 120c)
			expect.near(0.5 * full.kick, 1.6, 1e-9) -- design: html:333 (0.5 + 1.1c)
			expect.truthy(full.whiteRing)
			expect.truthy(full.powerRing)
			expect.near(full.powerRingStuds, 2 * 0.9 / 0.28, 1e-9) -- design: html:338 (0.5 + 0.4c m)
			expect.equal(full.hitStop, CHARGE.hitStopSeconds)
			expect.equal(CHARGE.hitStopSeconds, 0.045) -- design: html:339
			expect.falsy(ThrowCharge.release(0.45).whiteRing)
			expect.truthy(ThrowCharge.release(0.46).whiteRing)
			expect.falsy(ThrowCharge.release(0.6).powerRing)
			local seven = ThrowCharge.release(0.7)
			expect.truthy(seven.powerRing)
			expect.near(seven.powerRingStuds, 2 * (0.5 + 0.4 * 0.7) / 0.28, 1e-9)
			expect.equal(ThrowCharge.release(0.99).hitStop, nil)
		end
	)

	t.test("the FOV narrows by 4° × c and the walk is 5.2 / 7 of the base (design: html:437, 463)", function()
		expect.near(ThrowCharge.fovOffset(0), 0, EPS)
		expect.near(ThrowCharge.fovOffset(0.5), -2, EPS)
		expect.near(ThrowCharge.fovOffset(1), -4, EPS)
		expect.near(ThrowCharge.walkSpeed(7), 5.2, 1e-9)
		expect.near(ThrowCharge.walkSpeed(16), 16 * 5.2 / 7, 1e-9)
	end)

	t.test("in-flight specks: none with a rarity emitter, the power's share, held to the particle budget", function()
		expect.equal(ThrowCharge.speckRate(1, true), 0)
		expect.equal(ThrowCharge.speckRate(0, false), 0)
		local cap = Config.Vfx.Effects.projectileParticles / VFX.speckLifetimeMax
		expect.near(ThrowCharge.speckRate(1, false), math.min(30, cap), 1e-9)
		expect.near(ThrowCharge.speckRate(0.2, false), math.min(6, cap), 1e-9)
		-- Live specks never pass the budget: rate × the longest life.
		expect.truthy(
			ThrowCharge.speckRate(1, false) * VFX.speckLifetimeMax <= Config.Vfx.Effects.projectileParticles + EPS
		)
	end)

	t.test("the tone rises with c (pitch and volume); a tremolo only at full", function()
		local p0, v0 = ThrowCharge.tone(0, 0)
		expect.near(p0, TONE.pitchFrom, EPS)
		expect.near(v0, TONE.volumeFrom, EPS)
		local pHalf, vHalf = ThrowCharge.tone(0.5, 0.3)
		expect.truthy(pHalf > p0 and vHalf > v0)
		local pHalfLater, vHalfLater = ThrowCharge.tone(0.5, 0.9)
		expect.near(pHalfLater, pHalf, EPS) -- no tremolo below full
		expect.near(vHalfLater, vHalf, EPS)
		local p1 = ThrowCharge.tone(1, 0)
		expect.near(p1, TONE.pitchTo, EPS)
		local _, vA = ThrowCharge.tone(1, math.pi / (2 * TONE.tremoloRate))
		local _, vB = ThrowCharge.tone(1, 3 * math.pi / (2 * TONE.tremoloRate))
		expect.near(vA, 1 + TONE.tremolo, 1e-6)
		expect.near(vB, 1 - TONE.tremolo, 1e-6)
		expect.truthy(TONE.pitchTo <= Config.Audio.pitchMax and TONE.pitchFrom >= Config.Audio.pitchMin)
	end)

	t.test("the ease is quadratic in-out (design: html:115)", function()
		expect.near(ThrowCharge.ease(0), 0, EPS)
		expect.near(ThrowCharge.ease(0.25), 0.125, EPS)
		expect.near(ThrowCharge.ease(0.5), 0.5, EPS)
		expect.near(ThrowCharge.ease(0.75), 0.875, EPS)
		expect.near(ThrowCharge.ease(1), 1, EPS)
		expect.near(ThrowCharge.ease(2), 1, EPS)
		expect.near(ThrowCharge.ease(-1), 0, EPS)
	end)
end
