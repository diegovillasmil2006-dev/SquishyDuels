--!strict
-- HighwayBoosters_Test: ReplicatedStorage.Shared.Art.HighwayBoosters, one booster a biome from the owner's concept
-- sheet (boosters, plan step 6, 2026-10-31). Builds each booster unparented and destroys it.
-- Contract:
--   * one booster per highway biome, in highway order (jelly pad, toaster cannon, pearl bouncer, ice slide, fire jet,
--     comet pad, halo ring);
--   * build(biome, origin) is a decor Model (every part anchored, never collides, queried or touched) at the origin,
--     on the lane top and inside the lane (the halo ring hovers over it); a torus is its segments; any other biome
--     builds nothing.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local HighwayBoosters = t.requireShared("Art/HighwayBoosters")
	local WorldLayout = t.requireShared("World/WorldLayout")

	local LANE_TOP_WIDTH = 26

	t.test("one booster per biome, in highway order", function()
		expect.equal(#HighwayBoosters.list, #WorldLayout.Highway.biomes)
		local ids = {}
		for _, booster in HighwayBoosters.list do
			table.insert(ids, booster.id)
		end
		expect.deepEqual(ids, {
			"cm_jelly_pad",
			"bt_toaster_cannon",
			"bl_pearl_bouncer",
			"fd_ice_slide",
			"lv_fire_jet",
			"rr_comet_pad",
			"dh_halo_ring",
		})
	end)

	t.test("build: a decor Model at the origin, on the lane top, inside the lane; a torus is its segments", function()
		local origin = CFrame.new(-40, 20, 600) * CFrame.Angles(0, math.rad(-15), 0)
		for biome = 1, #HighwayBoosters.list do
			local def = HighwayBoosters.list[biome]
			local model = HighwayBoosters.build(biome, origin) :: Model
			expect.truthy(model ~= nil)
			expect.equal(model.Name, def.id)
			local want = 0
			for _, part in def.parts do
				want += if part.kind == "r" then part.size[3] else 1
			end
			expect.equal(#model:GetChildren(), want)
			for _, part in model:GetChildren() do
				local p = part :: BasePart
				expect.truthy(p:IsA("BasePart") and p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch)
			end
			local box, size = model:GetBoundingBox()
			local at = origin:PointToObjectSpace(box.Position)
			expect.truthy(math.abs(at.X) + size.X / 2 <= LANE_TOP_WIDTH / 2 + 2)
			expect.truthy(at.Y - size.Y / 2 >= -1e-3) -- (turned parts round off a little)
			model:Destroy()
		end
		expect.equal(HighwayBoosters.build(0, origin), nil)
		expect.equal(HighwayBoosters.build(8, origin), nil)
	end)
end
