--!strict
-- CatchFx_Test: unit tests for StarterPlayerScripts.Client.Anim.CatchFx (feature 1, 2026-10-11: the catch's world
-- effects; design: the combat-effects page "Squishy Combat FP v2.html", html:353, 359, 361). Server only
-- (ServerStorage.UnitTest). Pure.
-- Contract:
--   * the catch: 14 sparks in the toy's accent and one accent ring 0.2 m wide over 0.28 s (design: html:353);
--   * the burst: the design's 46 / 22 / 6 (pieces / sparks / puffs) held to 60 particles in all (the per-effect budget),
--     the pieces half accent, half White, the puffs White, falling at grav 5 (design: html:359), and one accent ring
--     to 1.6 m over 0.3 s (design: html:361).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local CatchFx = t.requireClient("Anim/CatchFx")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local expect = t.expect
	local CATCH = Config.Vfx.Catch
	local BUDGET = Config.Vfx.Budgets.liveParticlesPerEffect
	local ACCENT = Color3.fromRGB(240, 120, 160)

	local function colourOf(emit: any): Color3
		return (emit.props.Color :: ColorSequence).Keypoints[1].Value
	end

	t.test("the catch: 14 accent sparks and one accent ring (design: html:353)", function()
		local emits, rings = CatchFx.caught(ACCENT)
		expect.equal(#emits, 1)
		expect.equal(emits[1].count, 14)
		expect.equal(colourOf(emits[1]), ACCENT)
		expect.equal(emits[1].props.Texture, Config.Vfx.Textures.sparkles)
		expect.equal(#rings, 1)
		expect.near(rings[1].diameter, 2 * 0.2 / 0.28, 1e-9)
		expect.equal(rings[1].seconds, 0.28)
		expect.equal(rings[1].colour, ACCENT)
		expect.truthy(CatchFx.total(emits) <= BUDGET)
	end)

	t.test("the burst: within the per-effect budget, accent and White pieces, White puffs, one ring", function()
		local emits, rings = CatchFx.burst(ACCENT)
		expect.equal(CatchFx.total(emits), CATCH.burstPieces + CATCH.burstSparks + CATCH.burstPuffs)
		expect.truthy(CatchFx.total(emits) <= BUDGET)
		expect.equal(#emits, 4)
		expect.equal(colourOf(emits[1]), ACCENT)
		expect.equal(colourOf(emits[2]), Palette.White)
		expect.equal(emits[1].count + emits[2].count, CATCH.burstPieces)
		expect.equal(emits[3].count, CATCH.burstSparks)
		expect.equal(emits[4].count, CATCH.burstPuffs)
		expect.equal(colourOf(emits[4]), Palette.White)
		expect.near(emits[1].props.Acceleration.Y, -5 / 0.28, 1e-4) -- design: html:359 (grav 5); 32-bit floats
		-- The design's 46 / 22 / 6 in the same shares.
		expect.truthy(math.abs(CATCH.burstPieces / CATCH.burstSparks - 46 / 22) < 0.1)
		expect.equal(#rings, 1)
		expect.near(rings[1].diameter, 2 * 1.6 / 0.28, 1e-9)
		expect.equal(rings[1].seconds, 0.3)
		expect.equal(rings[1].colour, ACCENT)
	end)
end
