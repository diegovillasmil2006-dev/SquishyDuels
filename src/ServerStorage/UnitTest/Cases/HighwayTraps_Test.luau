--!strict
-- HighwayTraps_Test: ReplicatedStorage.Shared.Art.HighwayTraps, the 7 traps of the owner's concept sheet (traps you
-- can see, plan step 5, 2026-10-31; blocky Blender meshes 2026-11-01). Builds each trap unparented and destroys it.
-- Contract:
--   * one trap per highway biome, in highway order (gum, jam, splash pool, marshmallow, lava pit, cloud gap, soft cloud);
--   * ServerStorage.SD_HighwayProps holds each trap's meshes: one MeshPart per palette key plus the Outline, nothing
--     else, all anchored and never colliding, queried or touched, the Outline one-sided;
--   * build(biome, origin) is that Model painted (the key's hex; Neon glows, the rest wears the stud tile; the Outline
--     is ink) with its pivot at the origin; it fits on the 26-stud lane top and stands on it (nothing more than 0.9
--     under the origin: the cloud gap's shade and its ink); any other biome builds nothing.

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
	local props = game:GetService("ServerStorage"):FindFirstChild(HighwayTraps.PROPS)

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

	t.test("meshes: one MeshPart per palette key plus the Outline, inert", function()
		expect.truthy(props ~= nil)
		for _, trap in HighwayTraps.list do
			local template = props:FindFirstChild(trap.id)
			expect.truthy(template ~= nil and template:IsA("Model"))
			local names = {}
			for _, part in template:GetChildren() do
				expect.truthy(part:IsA("MeshPart"))
				local p = part :: MeshPart
				expect.truthy(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch)
				expect.truthy(p.Name == HighwayTraps.OUTLINE or trap.pal[p.Name] ~= nil)
				if p.Name == HighwayTraps.OUTLINE then
					expect.equal(p.DoubleSided, false)
				end
				names[p.Name] = true
			end
			expect.truthy(names[HighwayTraps.OUTLINE])
			for key in trap.pal do
				expect.truthy(names[key])
			end
		end
	end)

	t.test("build: painted, standing on the lane top at the origin, inside the lane", function()
		local origin = CFrame.new(100, 50, -300) * CFrame.Angles(0, math.rad(30), 0)
		for biome = 1, #HighwayTraps.list do
			local trap = HighwayTraps.list[biome]
			local model = HighwayTraps.build(biome, origin) :: Model
			expect.truthy(model ~= nil)
			expect.equal(model.Name, trap.id)
			expect.equal(model.Parent, nil)
			expect.truthy((model:GetPivot().Position - origin.Position).Magnitude < 1e-3)
			for _, part in model:GetChildren() do
				local p = part :: BasePart
				local entry = trap.pal[p.Name]
				if entry == nil then
					expect.equal(p.Material, Enum.Material.SmoothPlastic)
					expect.equal(p.MaterialVariant, "")
				else
					expect.equal(p.Color:ToHex():upper(), entry[2])
					if entry[1] == "Neon" then
						expect.equal(p.Material, Enum.Material.Neon)
					else
						expect.equal(p.MaterialVariant, "SquishyStud")
					end
				end
			end
			local box, size = model:GetBoundingBox()
			local local_ = origin:PointToObjectSpace(box.Position)
			expect.truthy(math.abs(local_.X) + size.X / 2 <= LANE_TOP_WIDTH / 2 + 2) -- within the lane (rotated parts)
			expect.truthy(local_.Y - size.Y / 2 >= -0.9) -- stands on the lane top
			model:Destroy()
		end
		expect.equal(HighwayTraps.build(0, origin), nil)
		expect.equal(HighwayTraps.build(8, origin), nil)
	end)
end
