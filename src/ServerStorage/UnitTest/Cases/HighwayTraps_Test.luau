--!strict
-- HighwayTraps_Test: ReplicatedStorage.Shared.Art.HighwayTraps, the 7 traps of the owner's concept sheet (traps you
-- can see, plan step 5, 2026-10-31; big toy models like the boosters, 2026-11-07). Builds each trap unparented and
-- destroys it.
-- Contract:
--   * one trap per highway biome, in highway order (gum, jam, splash pool, marshmallow, lava pit, cloud gap, soft cloud);
--   * ServerStorage.SD_HighwayProps holds each trap's meshes: one MeshPart per palette key, nothing else (no ink hull),
--     all anchored and never colliding, queried or touched;
--   * build(biome, origin) is that Model painted at the origin ("Stud" the stud tile, "Smooth" plain, "Neon" glows), on
--     the lane top, as wide as the rails, inside the room the course keeps clear round a trap (course.trapClearStuds
--     along the lane, 2026-11-07: no stop lands in it) and big (at least 20 studs wide and long; the blocky ones of
--     2026-11-01 were 8 to 12); any other biome builds nothing.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local HighwayTraps = t.requireShared("Art/HighwayTraps")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local COURSE = t.requireShared("Config").Economy.Highway.course

	local RAILS = 15 -- x: the rails stand at +-14
	local BIG = 20
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

	t.test("meshes: one MeshPart per palette key, inert", function()
		expect.truthy(props ~= nil)
		for _, trap in HighwayTraps.list do
			local template = props:FindFirstChild(trap.id)
			expect.truthy(template ~= nil and template:IsA("Model"))
			local names = {}
			for _, part in template:GetChildren() do
				expect.truthy(part:IsA("MeshPart"))
				local p = part :: MeshPart
				expect.truthy(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch)
				expect.truthy(trap.pal[p.Name] ~= nil)
				names[p.Name] = true
			end
			for key in trap.pal do
				expect.truthy(names[key])
			end
		end
	end)

	t.test("build: the painted toy at the origin, on the lane top, inside the rails and the trap's room, big", function()
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
				expect.truthy(entry ~= nil)
				expect.equal(p.Color:ToHex():upper(), entry[2])
				expect.equal(p.Material, if entry[1] == "Neon" then Enum.Material.Neon else Enum.Material.SmoothPlastic)
				expect.equal(p.MaterialVariant, if entry[1] == "Stud" then "SquishyStud" else "")
			end
			local box, size = model:GetBoundingBox()
			local at = origin:PointToObjectSpace(box.Position)
			expect.truthy(math.abs(at.X) + size.X / 2 <= RAILS)
			expect.truthy(at.Y - size.Y / 2 >= -0.05) -- stands on the lane top
			expect.truthy(math.abs(at.Z) + size.Z / 2 <= COURSE.trapClearStuds) -- no stop lands in it
			expect.truthy(size.X >= BIG and size.Z >= BIG)
			model:Destroy()
		end
		expect.equal(HighwayTraps.build(0, origin), nil)
		expect.equal(HighwayTraps.build(8, origin), nil)
	end)
end
