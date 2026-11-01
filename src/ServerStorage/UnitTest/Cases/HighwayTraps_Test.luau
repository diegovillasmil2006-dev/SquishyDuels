--!strict
-- HighwayTraps_Test: ReplicatedStorage.Shared.Art.HighwayTraps, the 7 traps of the owner's concept sheet (traps you
-- can see, plan step 5, 2026-10-31). Builds each trap unparented and destroys it.
-- Contract:
--   * one trap per highway biome, in highway order (gum, jam, splash pool, marshmallow, lava pit, cloud gap, soft cloud);
--   * build(biome, origin) is a decor Model: every part anchored, never collides, queried or touched; it fits on the
--     26-stud lane top and stands on it (nothing more than 0.6 under the origin, the cloud gap's shade); its pivot is
--     the origin; Glass parts are see-through; any other biome builds nothing.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local HighwayTraps = t.requireShared("Art/HighwayTraps")
	local WorldLayout = t.requireShared("World/WorldLayout")

	local LANE_TOP_WIDTH = 26

	t.test("one trap per biome, in highway order", function()
		expect.equal(#HighwayTraps.list, #WorldLayout.Highway.biomes)
		local ids = {}
		for _, trap in HighwayTraps.list do
			table.insert(ids, trap.id)
		end
		expect.deepEqual(ids, {
			"cm_gum_puddle",
			"bt_jam_puddle",
			"bl_splash_pool",
			"fd_marshmallow",
			"lv_lava_pit",
			"rr_cloud_gap",
			"dh_soft_cloud",
		})
	end)

	t.test("build: a decor Model standing on the lane top at the origin, inside the lane", function()
		local origin = CFrame.new(100, 50, -300) * CFrame.Angles(0, math.rad(30), 0)
		for biome = 1, #HighwayTraps.list do
			local model = HighwayTraps.build(biome, origin) :: Model
			expect.truthy(model ~= nil)
			expect.equal(model.Name, HighwayTraps.list[biome].id)
			expect.truthy((model.WorldPivot.Position - origin.Position).Magnitude < 1e-6)
			local parts = model:GetChildren()
			expect.equal(#parts, #HighwayTraps.list[biome].parts)
			for _, part in parts do
				expect.truthy(part:IsA("BasePart"))
				local p = part :: BasePart
				expect.truthy(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch)
				if p.Material == Enum.Material.Glass then
					expect.truthy(p.Transparency > 0)
				end
			end
			local box, size = model:GetBoundingBox()
			local local_ = origin:PointToObjectSpace(box.Position)
			expect.truthy(math.abs(local_.X) + size.X / 2 <= LANE_TOP_WIDTH / 2 + 2) -- within the lane (rotated parts)
			expect.truthy(local_.Y - size.Y / 2 >= -0.6 - 1e-6) -- stands on the lane top
			model:Destroy()
		end
		expect.equal(HighwayTraps.build(0, origin), nil)
		expect.equal(HighwayTraps.build(8, origin), nil)
	end)
end
