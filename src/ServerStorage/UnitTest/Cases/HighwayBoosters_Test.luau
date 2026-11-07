--!strict
-- HighwayBoosters_Test: ReplicatedStorage.Shared.Art.HighwayBoosters, two boosters a biome from the owner's concept sheet,
-- as big toy models (2026-11-06). Builds each booster unparented and destroys it.
-- Contract:
--   * two boosters per highway biome, in highway order, a and b in the sheet's lane order;
--   * ServerStorage.SD_HighwayProps holds each booster's meshes: one MeshPart per palette key, no ink hull;
--   * build(biome, kind, origin) is that Model painted at the origin ("Stud" the stud tile, "Smooth" plain, "Neon"), on the
--     lane top, as long as the course keeps clear (course.clearStuds), as wide as the rails (the wings of the wing gate and
--     the halo ring reach over them), big (at least 4 studs high, Candy Meadow's flat old pad was 1.8), and at least as high
--     as where a squishy touches it; with an "x2" floating over its top; any other biome or kind builds nothing.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local GearShop = t.requireShared("Config/GearShop")
	local HighwayBoosters = t.requireShared("Art/HighwayBoosters")
	local HighwayTraps = t.requireShared("Art/HighwayTraps")
	local Palette = t.requireShared("Art/Palette")
	local Strings = t.requireShared("Strings")
	local WorldLayout = t.requireShared("World/WorldLayout")

	local COURSE = Config.Economy.Highway.course
	local RAILS = 15 -- x: the rails stand at +-14
	local WIDE: { [string]: number } = { dh_wing_gate = 23, dh_halo_ring = 17.5 } -- the sheet's wings
	local SQUISHY_RADIUS = 1

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

	t.test("build: the painted toy at the origin, on the lane top, inside the course's room, touched inside its height", function()
		local origin = CFrame.new(-40, 20, 600) * CFrame.Angles(0, math.rad(-15), 0)
		for kind, list in HighwayBoosters.lists do
			for biome, def in list do
				local model = HighwayBoosters.build(biome, kind, origin) :: Model
				expect.truthy(model ~= nil)
				expect.equal(model.Name, def.id)
				local names = {}
				for _, part in model:GetChildren() do
					local p = part :: MeshPart
					expect.truthy(p:IsA("MeshPart") and p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch)
					local entry = def.pal[p.Name]
					expect.truthy(entry ~= nil)
					expect.equal(p.Color:ToHex():upper(), entry[2])
					expect.equal(p.Material, if entry[1] == "Neon" then Enum.Material.Neon else Enum.Material.SmoothPlastic)
					expect.equal(p.MaterialVariant, if entry[1] == "Stud" then "SquishyStud" else "")
					names[p.Name] = true
				end
				expect.equal(names[HighwayTraps.OUTLINE], nil)
				for key in def.pal do
					expect.truthy(names[key])
				end
				local box, size = model:GetBoundingBox()
				local at = origin:PointToObjectSpace(box.Position)
				local top = at.Y + size.Y / 2
				expect.truthy(math.abs(at.X) + size.X / 2 <= (WIDE[def.id] or RAILS))
				expect.truthy(math.abs(at.Z) + size.Z / 2 <= COURSE.clearStuds)
				expect.truthy(at.Y - size.Y / 2 >= -0.05)
				expect.truthy(top >= 4)
				expect.truthy(COURSE.touch[kind][biome] <= top + SQUISHY_RADIUS)
				model:Destroy()
			end
		end
		expect.equal(HighwayBoosters.build(0, "a", origin), nil)
		expect.equal(HighwayBoosters.build(8, "b", origin), nil)
		expect.equal(HighwayBoosters.build(1, "trap", origin), nil)
	end)

	t.test("the sign: x2 floating just over the model's top, in the Palette's colours", function()
		local origin = CFrame.new(10, 1, -300)
		local sign = GearShop.booster.sign
		local model = HighwayBoosters.build(2, "a", origin) :: Model
		-- lihfolk-ignore: findfirstchild-chain a test: a missing child fails it, as it should
		local gui = model:FindFirstChild("Sign", true) :: BillboardGui
		local anchor = gui.Parent :: Attachment
		expect.truthy(anchor:IsA("Attachment") and gui.Adornee == anchor)
		local box, size = model:GetBoundingBox()
		local want = origin.Y + (origin:PointToObjectSpace(box.Position).Y + size.Y / 2) + sign.liftStuds + sign.heightStuds / 2
		expect.near(anchor.WorldPosition.Y, want, 0.01)
		expect.near(anchor.WorldPosition.X, origin.X, 0.01)
		expect.near(anchor.WorldPosition.Z, origin.Z, 0.01)
		expect.equal(gui.Size, UDim2.fromScale(sign.widthStuds, sign.heightStuds))
		expect.equal(gui.MaxDistance, sign.maxDistance)
		-- lihfolk-ignore: findfirstchild-chain a test: a missing child fails it, as it should
		local label = gui:FindFirstChild("Text") :: TextLabel
		expect.equal(label.Text, Strings.format(Strings.highway.boosterSign, { x = 2 }))
		expect.equal(label.Text, "x2")
		expect.equal(label.TextColor3, Palette[sign.color])
		-- lihfolk-ignore: findfirstchild-chain a test: a missing child fails it, as it should
		local stroke = label:FindFirstChildOfClass("UIStroke") :: UIStroke
		expect.equal(stroke.Color, Palette[sign.stroke])
		model:Destroy()
	end)
end
