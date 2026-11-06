--!strict
-- HighwayBoosters_Test: ReplicatedStorage.Shared.Art.HighwayBoosters, two boosters a biome from the owner's concept
-- sheet (boosters, plan step 6, 2026-10-31; blocky Blender meshes 2026-11-01; the sheet's other seven 2026-11-06). Builds
-- each booster unparented and destroys it.
-- Contract:
--   * two boosters per highway biome, in highway order, a and b in the sheet's lane order;
--   * ServerStorage.SD_HighwayProps holds each booster's meshes: one MeshPart per palette key plus the Outline;
--   * build(biome, kind, origin) is that Model painted at the origin, on the lane top (its ink a little under it) and
--     inside the lane (the wing gate's wings reach over the rails, as in the sheet); any other biome or kind builds
--     nothing.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local HighwayBoosters = t.requireShared("Art/HighwayBoosters")
	local HighwayTraps = t.requireShared("Art/HighwayTraps")
	local WorldLayout = t.requireShared("World/WorldLayout")

	local LANE_TOP_WIDTH = 26
	local WING_GATE_WIDTH = 40 -- the sheet's posts at +-9 with their wings on the outside

	local function idsOf(list: any): { string }
		local ids = {}
		for _, booster in list do
			table.insert(ids, booster.id)
		end
		return ids
	end

	t.test("two boosters per biome, in highway order", function()
		expect.equal(#HighwayBoosters.lists.a, #WorldLayout.Highway.biomes)
		expect.equal(#HighwayBoosters.lists.b, #WorldLayout.Highway.biomes)
		expect.deepEqual(idsOf(HighwayBoosters.lists.a), {
			"cm_jelly_pad",
			"bt_toaster_cannon",
			"bl_pearl_bouncer",
			"fd_ice_slide",
			"lv_fire_jet",
			"rr_star_ring",
			"dh_wing_gate",
		})
		expect.deepEqual(idsOf(HighwayBoosters.lists.b), {
			"cm_sprinkle_ramp",
			"bt_butter_slide",
			"bl_straw_tube",
			"fd_cone_cannon",
			"lv_magma_ramp",
			"rr_comet_pad",
			"dh_halo_ring",
		})
	end)

	t.test("build: the painted meshes at the origin, on the lane top, inside the lane", function()
		local origin = CFrame.new(-40, 20, 600) * CFrame.Angles(0, math.rad(-15), 0)
		for kind, list in HighwayBoosters.lists do
			for biome, def in list do
				local model = HighwayBoosters.build(biome, kind, origin) :: Model
				expect.truthy(model ~= nil)
				expect.equal(model.Name, def.id)
				local names = {}
				for _, part in model:GetChildren() do
					local p = part :: BasePart
					expect.truthy(p:IsA("MeshPart") and p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch)
					local entry = def.pal[p.Name]
					expect.truthy(entry ~= nil or p.Name == HighwayTraps.OUTLINE)
					if entry then
						expect.equal(p.Color:ToHex():upper(), entry[2])
					end
					names[p.Name] = true
				end
				expect.truthy(names[HighwayTraps.OUTLINE])
				for key in def.pal do
					expect.truthy(names[key])
				end
				local box, size = model:GetBoundingBox()
				local at = origin:PointToObjectSpace(box.Position)
				local width = if def.id == "dh_wing_gate" then WING_GATE_WIDTH else LANE_TOP_WIDTH + 4
				expect.truthy(math.abs(at.X) + size.X / 2 <= width / 2)
				expect.truthy(at.Y - size.Y / 2 >= -0.3)
				model:Destroy()
			end
		end
		expect.equal(HighwayBoosters.build(0, "a", origin), nil)
		expect.equal(HighwayBoosters.build(8, "b", origin), nil)
		expect.equal(HighwayBoosters.build(1, "trap", origin), nil)
	end)
end
