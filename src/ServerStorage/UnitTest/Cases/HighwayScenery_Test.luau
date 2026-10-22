--!strict
-- HighwayScenery_Test: the highway's biome scenery (pens3 phase 12b, 2026-10-18; the owner: "the biomes have to be
-- themed too, like, not just plain terrain and color changes"): the decor pieces of the lobby design v6's
-- layout.json (L:488-1599), built by ServerStorage.SDTools.Builders.HighwayBuilder from the rows of SDTools
-- Builders/HighwayScenery.
-- Server only (ServerStorage.UnitTest). It runs the builder as Main does (build(ctx) with a scratch Cleanup, an
-- UNPARENTED tree destroyed afterwards) and pins, restated from the design (`L:n` = layout.json, `K:n` = kit.json,
-- `HK:n` / `LK:n` = highway-kit.js / lobby-kit.js line n) instead of read from the builder:
--   * every row is built once, in its biome's Model, named as v6 names it, SD_Piece = its kind, an Atomic Model
--     pivoted on its v6 point in the lane-local frame (L:1 "z = -62 - d") turned by its yaw (L "rot"); only the
--     clouds under v6's Golden Gates (L:1598-1599 "gate support") follow ours (Config.Economy.Highway.gatesAt), the
--     rest keeps its v6 distance and nothing stands past the lane's end (8,500 in v6 too, L:1369);
--   * v6's kinds and counts per biome, rows' exact numbers, the clouds under the sky arches and the Golden Gates;
--   * none of the gameplay pieces (boosters, traps, reward bubbles: phases 15 and 17) is built;
--   * the look: each kind as big as K says, every part one of K's parts for its kind in that K material's colour and
--     Roblox material (the tinted parts in their row's L tint); the volcano's light (L:4) and crater (HK:69-70);
--   * nobody reaches the scenery, so none of it collides; pieces per biome within v6's 600, parts within a phone
--     budget; scenery for another number of biomes than Config's stops the build.

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
}

-- Restated from the design.
local BIOME_MODELS =
	{ "Biome_1_CM", "Biome_2_BT", "Biome_3_BL", "Biome_4_FD", "Biome_5_LV", "Biome_6_RR", "Biome_7_DH" }
local V6_ZERO = 62 -- L:1 "z = -62 - d"
local V6_GATES_AT = 8350 -- L:1597 dh_golden_gates_01 at z -8,412
local GATE_SUPPORTS = { dh_gold_cloud_41 = true, dh_gold_cloud_42 = true } -- L:1598-1599 "role": "gate support"
local TOLERANCE = 2e-3 -- CFrames are single precision; 8,500 studs out that is a few thousandths

-- The scenery kinds and how many of each v6 places in each biome (L:488-1599).
local KINDS: { { [string]: number } } = {
	{ lollipop_lamp = 3, gumdrop_tree = 5, candy_hill = 2 }, -- L:488-497 (CM reuses the lobby's, HK:30)
	{ bt_bread_house = 11, bt_croissant_hill = 5 }, -- L:551-566
	{ bl_cup_island = 10 }, -- L:643-652
	{ fd_popsicle = 20, fd_sundae_peak = 9 }, -- L:761-789
	{ lv_basalt_rock = 38, lv_volcano = 1 }, -- L:951-989
	{ rr_cloud_bank = 35, rr_planet = 3 }, -- L:1131-1132, :1186-1221
	{ dh_gold_cloud = 42, dh_marble_pillar = 92 }, -- L:1398-1399, :1467-1599
}
local ROWS = 276

-- The gameplay pieces of the same layout, built with phase 15's boosters and traps and phase 17's coatings.
local NOT_NOW = {
	"cm_jelly_pad",
	"cm_sprinkle_ramp",
	"cm_gum_puddle",
	"bt_toaster_cannon",
	"bt_butter_slide",
	"bt_jam_puddle",
	"bl_pearl_bouncer",
	"bl_straw_tube",
	"bl_splash_pool",
	"fd_ice_slide",
	"fd_cone_cannon",
	"fd_marshmallow",
	"lv_fire_jet",
	"lv_magma_ramp",
	"lv_lava_pit",
	"rr_star_ring",
	"rr_comet_pad",
	"rr_cloud_gap",
	"dh_wing_gate",
	"dh_halo_ring",
	"dh_soft_cloud",
	"reward_bubble",
}

-- Rows with their exact v6 numbers (biome, position, yaw).
local SPOTS = {
	{ id = "lollipop_lamp_35", biome = 1, at = Vector3.new(-19, 0, -212), rot = 180 }, -- L:488
	{ id = "gumdrop_tree_17", biome = 1, at = Vector3.new(-26, 0, -222), rot = -28.5 }, -- L:491
	{ id = "candy_hill_23", biome = 1, at = Vector3.new(120.875, 0, -307), rot = 87.1 }, -- L:497
	{ id = "bt_bread_house_01", biome = 2, at = Vector3.new(-40.75, 0, -382), rot = 90 }, -- L:551
	{ id = "bt_croissant_hill_01", biome = 2, at = Vector3.new(-144.375, 0, -412), rot = -128.2 }, -- L:562
	{ id = "bl_cup_island_01", biome = 3, at = Vector3.new(-59.875, -2, -892), rot = 154.2 }, -- L:643
	{ id = "fd_popsicle_01", biome = 4, at = Vector3.new(-24, 0, -1587), rot = -3.8 }, -- L:761
	{ id = "fd_sundae_peak_01", biome = 4, at = Vector3.new(-150.25, 0, -1622), rot = -41.6 }, -- L:781
	{ id = "lv_basalt_rock_01", biome = 5, at = Vector3.new(-26.75, 0, -2577), rot = 134.6 }, -- L:951
	{ id = "lv_volcano_01", biome = 5, at = Vector3.new(-230, 0, -3312), rot = 0 }, -- L:989
	{ id = "rr_cloud_bank_35", biome = 6, at = Vector3.new(-91.625, -12.807, -6012), rot = -76.7 }, -- L:1218
	{ id = "rr_planet_02", biome = 6, at = Vector3.new(300, 110, -5262), rot = 85.7 }, -- L:1220
	{ id = "dh_marble_pillar_01", biome = 7, at = Vector3.new(-22, 1, -6087), rot = 0 }, -- L:1467
	{ id = "dh_marble_pillar_92", biome = 7, at = Vector3.new(22, 1, -8337), rot = 0 }, -- L:1558
	{ id = "dh_gold_cloud_38", biome = 7, at = Vector3.new(72.75, -11.453, -8372), rot = -97.9 }, -- L:1594
}

-- The K materials of the scenery: colour, Roblox material and shine (K:7-444 "hex" / "roblox").
local MATERIALS: { [string]: { hex: string, material: Enum.Material, reflectance: number? } } = {
	Frosting = { hex = "#FFF6EC", material = Enum.Material.SmoothPlastic }, -- K:7
	CandyGrass = { hex = "#9EE89B", material = Enum.Material.SmoothPlastic }, -- K:13
	Wafer = { hex = "#E0A062", material = Enum.Material.SmoothPlastic }, -- K:25
	PinkIcing = { hex = "#FF8FBF", material = Enum.Material.SmoothPlastic }, -- K:31
	Lilac = { hex = "#B98CFF", material = Enum.Material.SmoothPlastic }, -- K:55
	Berry = { hex = "#FF5C8A", material = Enum.Material.SmoothPlastic }, -- K:61
	Gold = { hex = "#FFC23C", material = Enum.Material.SmoothPlastic, reflectance = 0.2 }, -- K:73
	Glow = { hex = "#FFF0A0", material = Enum.Material.Neon }, -- K:80
	Crust = { hex = "#C9803F", material = Enum.Material.SmoothPlastic }, -- K:336
	StrawPink = { hex = "#FF6FA3", material = Enum.Material.SmoothPlastic }, -- K:348
	MilkTea = { hex = "#EED6B8", material = Enum.Material.SmoothPlastic }, -- K:361
	Snow = { hex = "#F4FBFF", material = Enum.Material.Snow }, -- K:374
	BerrySauce = { hex = "#E0315F", material = Enum.Material.SmoothPlastic, reflectance = 0.1 }, -- K:386
	Basalt = { hex = "#3A2C3A", material = Enum.Material.Basalt }, -- K:392
	LavaGlow = { hex = "#FF6A3D", material = Enum.Material.Neon }, -- K:398
	StarGold = { hex = "#FFD84A", material = Enum.Material.Neon }, -- K:419
	Cloud = { hex = "#FFFFFF", material = Enum.Material.SmoothPlastic }, -- K:426
	Marble = { hex = "#FBF7F2", material = Enum.Material.Marble }, -- K:432
	GoldCloud = { hex = "#FFE9A8", material = Enum.Material.SmoothPlastic }, -- K:444
	-- GumdropTint (K:123) and PopsicleTint (K:297) are SmoothPlastic in the row's own L tint.
}

-- Each kind's parts and their K materials (K "parts", K:1253-2823), and its size (K "size").
local PIECES: { [string]: { parts: { [string]: string }, size: Vector3 } } = {
	gumdrop_tree = { -- K:1253
		parts = { trunk = "Frosting", trunk_stripes = "PinkIcing", canopy = "GumdropTint" },
		size = Vector3.new(6, 8.8, 6),
	},
	lollipop_lamp = { -- K:1283
		parts = { lamp_pole = "Frosting", lamp_candy = "Glow", lamp_swirl = "PinkIcing" },
		size = Vector3.new(3.2, 10.8, 0.85),
	},
	candy_hill = { -- K:1313
		parts = { hill_body = "CandyGrass", hill_icing = "Frosting" },
		size = Vector3.new(40, 15.3, 40),
	},
	bt_bread_house = { -- K:2044
		parts = { house_crust = "Crust", house_trim = "Frosting" },
		size = Vector3.new(16.4, 15, 12.45),
	},
	bt_croissant_hill = { parts = { croissant = "Wafer" }, size = Vector3.new(34.6, 13, 25.98) }, -- K:2070
	bl_cup_island = { -- K:2176 (its cup_pearls lie inside the opaque cup: not built, see HighwayBuilder)
		parts = { cup = "MilkTea", cup_lid = "Frosting", cup_straw = "StrawPink" },
		size = Vector3.new(18.6, 38.86, 18.6),
	},
	fd_sundae_peak = { -- K:2298
		parts = { peak = "Snow", peak_sauce = "BerrySauce", peak_cherry = "Berry" },
		size = Vector3.new(60, 43.4, 60),
	},
	fd_popsicle = { -- K:2328
		parts = { popsicle = "PopsicleTint", popsicle_stick = "Wafer" },
		size = Vector3.new(4, 11, 1.5),
	},
	lv_volcano = { -- K:2446
		parts = { volcano = "Basalt", volcano_lava = "LavaGlow" },
		size = Vector3.new(120, 66, 120),
	},
	lv_basalt_rock = { parts = { rocks = "Basalt" }, size = Vector3.new(9.27, 5.61, 5.67) }, -- K:2475
	rr_cloud_bank = { parts = { cloud_bank = "Cloud" }, size = Vector3.new(35, 14.8, 19.6) }, -- K:2608
	rr_planet = { -- K:2630
		parts = { planet = "Lilac", planet_ring = "StarGold" },
		size = Vector3.new(58.8, 36, 55.24),
	},
	dh_marble_pillar = { -- K:2797
		parts = { pillar = "Marble", pillar_gold = "Gold" },
		size = Vector3.new(4.4, 14.4, 4.4),
	},
	dh_gold_cloud = { parts = { gold_cloud = "GoldCloud" }, size = Vector3.new(42, 10.9, 29.65) }, -- K:2823
}
-- The rows' own tints (L tints): GumdropTint is one of K:535-540's, PopsicleTint one of L:761-780's.
local TINTS: { [string]: { string } } = {
	gumdrop_tree = { "#FF8FBF", "#FFD84A", "#B98CFF", "#5FE0E8" },
	fd_popsicle = { "#FF8FBF", "#8FD8FF", "#8DF27A", "#FFD84A" },
}
local TINTED = { -- L:491, :494, :761-764
	gumdrop_tree_17 = "#FF8FBF",
	gumdrop_tree_20 = "#5FE0E8",
	fd_popsicle_01 = "#FF8FBF",
	fd_popsicle_02 = "#8FD8FF",
	fd_popsicle_03 = "#8DF27A",
	fd_popsicle_04 = "#FFD84A",
}
local SIZE_SHARE = 0.12 -- a port of v6's meshes as parts keeps each piece's size to this share of K's
local SIZE_FLOOR = 0.6 -- studs: a small piece's size may differ this much
local PHONE_PARTS = 2500 -- parts per biome (the task's phone line; streaming is off: everything loads)
local MAX_PIECES = 600 -- spec.txt:157

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local function kindOf(id: string): string
	return string.match(id, "^(.+)_%d+$") :: string
end

local function same(a: Color3, hex: string): boolean
	local b = Color3.fromHex(hex)
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

local function loadTools(): (Instance, any, any)
	local source = ServerStorage:FindFirstChild("SDTools")
	if source == nil then
		error("ServerStorage.SDTools not found (is Rojo connected?)")
	end
	local clone = source:Clone()
	local builders = clone:FindFirstChild("Builders")
	local builder = if builders then builders:FindFirstChild("HighwayBuilder") else nil
	local scenery = if builders then builders:FindFirstChild("HighwayScenery") else nil
	if builder == nil or scenery == nil or not builder:IsA("ModuleScript") or not scenery:IsA("ModuleScript") then
		clone:Destroy()
		error("SDTools.Builders.HighwayBuilder or HighwayScenery not found")
	end
	return clone, dynamicRequire(builder), dynamicRequire(scenery)
end

return function(t: Context)
	local expect = t.expect
	local tools, HighwayBuilder, HighwayScenery = loadTools()
	local Cleanup = t.requireShared("Util/Cleanup")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local origin: CFrame = WorldLayout.Highway.origin
	local starts = Config.Economy.Highway.starts
	local gatesAt = Config.Economy.Highway.gatesAt

	local scratch = Cleanup.new()
	local ok, result = pcall(HighwayBuilder.build, { scratch = scratch, Shared = t.Shared })
	if not ok or not result.ok or result.root == nil then
		scratch:clean()
		tools:Destroy()
		error("HighwayBuilder.build failed: " .. (if ok then tostring(result.error) else tostring(result)))
	end
	scratch:clean() -- the root was handed over: cleaning must not destroy it
	local root = result.root :: Model

	-- Where v6 puts a point (lane-local: L:1); a gate support follows our gates.
	local function mapped(at: Vector3, rot: number, id: string?): CFrame
		local d = -(at.Z + V6_ZERO)
		if id and GATE_SUPPORTS[id] then
			d += gatesAt - V6_GATES_AT
		end
		return origin * CFrame.new(at.X, at.Y, -d) * CFrame.Angles(0, math.rad(rot), 0)
	end

	-- The lane-local position of a model's pivot: (x, y, d).
	local function laneOf(model: Model): Vector3
		local p = origin:PointToObjectSpace(model.WorldPivot.Position)
		return Vector3.new(p.X, p.Y, -p.Z)
	end

	-- The one child of a biome named `id` (nil when there is none or more).
	local function piece(biome: number, id: string): Model?
		local found: Model? = nil
		for _, child in (root:FindFirstChild(BIOME_MODELS[biome]) :: Model):GetChildren() do
			if child.Name == id then
				if found ~= nil or not child:IsA("Model") then
					return nil
				end
				found = child :: Model
			end
		end
		return found
	end

	local function partsOf(model: Model): { BasePart }
		local list: { BasePart } = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	t.test("every v6 scenery row is built once, in its biome, named as v6 names it, at its place and yaw", function()
		local problems: { string } = {}
		local rows = 0
		for index in BIOME_MODELS do
			for _, row in HighwayScenery.biomes[index] do
				rows += 1
				local model = piece(index, row.id)
				if model == nil then
					table.insert(problems, row.id .. " missing or repeated in " .. BIOME_MODELS[index])
					continue
				end
				local want = mapped(row.at, row.rot, row.id)
				if
					model:GetAttribute("SD_Piece") ~= kindOf(row.id)
					or model.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic -- K:7887
					or (model.WorldPivot.Position - want.Position).Magnitude > TOLERANCE
					or model.WorldPivot.LookVector:Dot(want.LookVector) < 0.9999
				then
					table.insert(problems, row.id .. " is not v6's piece at v6's place")
				end
			end
		end
		expect.deepEqual(problems, {})
		expect.equal(rows, ROWS)
	end)

	t.test("v6's scenery kinds, as many in each biome as L:488-1599 places", function()
		local lane = {
			lane_tile = true,
			rr_rainbow_lane = true,
			lane_rail = true,
			distance_marker = true,
			biome_ground = true,
			biome_arch = true,
			dh_golden_gates = true,
			flight_ring = true, -- p13v4: the rings and the pads are not scenery
			flight_pad = true,
		}
		for index, name in BIOME_MODELS do
			local counts: { [string]: number } = {}
			for _, child in (root:FindFirstChild(name) :: Model):GetChildren() do
				local kind = child:GetAttribute("SD_Piece")
				if type(kind) == "string" and not lane[kind] then
					counts[kind] = (counts[kind] or 0) + 1
				end
			end
			expect.deepEqual(counts, KINDS[index])
		end
	end)

	t.test("rows keep v6's exact numbers", function()
		for _, spot in SPOTS do
			local model = piece(spot.biome, spot.id)
			expect.truthy(model ~= nil)
			local want = mapped(spot.at, spot.rot)
			expect.truthy(((model :: Model).WorldPivot.Position - want.Position).Magnitude < TOLERANCE)
			expect.truthy((model :: Model).WorldPivot.LookVector:Dot(want.LookVector) > 0.9999)
		end
	end)

	t.test("the sky arches and the Golden Gates stand on clouds; only the gate supports follow our gates", function()
		-- L:1131-1132 rr_cloud_bank_01/02 under Rainbow Road's arch legs (x ±18 x 1.45, HK:24, L:1130; v6 snaps to an
		-- eighth of a stud).
		for _, id in { "rr_cloud_bank_01", "rr_cloud_bank_02" } do
			local p = laneOf(piece(6, id) :: Model)
			expect.truthy(math.abs(math.abs(p.X) - 18 * 1.45) < 0.0625 and math.abs(p.Y + 9) < TOLERANCE)
			expect.truthy(math.abs(p.Z - starts[6]) < TOLERANCE)
		end
		-- L:1398-1399 dh_gold_cloud_01/02 under Divine Heaven's (x ±18 x 1.6, L:1397).
		for _, id in { "dh_gold_cloud_01", "dh_gold_cloud_02" } do
			local p = laneOf(piece(7, id) :: Model)
			expect.truthy(math.abs(math.abs(p.X) - 18 * 1.6) < 0.0625 and math.abs(p.Y + 9) < TOLERANCE)
			expect.truthy(math.abs(p.Z - starts[7]) < TOLERANCE)
		end
		-- L:1598-1599 dh_gold_cloud_41/42 under the Golden Gates' pillars (x ±16, HK:91), at the gates (PR3:36).
		local gates = laneOf(piece(7, "dh_golden_gates_01") :: Model)
		for _, id in { "dh_gold_cloud_41", "dh_gold_cloud_42" } do
			local p = laneOf(piece(7, id) :: Model)
			expect.truthy(math.abs(math.abs(p.X) - 16) < TOLERANCE and math.abs(p.Y + 9) < TOLERANCE)
			expect.truthy(math.abs(p.Z - gatesAt) < TOLERANCE and math.abs(p.Z - gates.Z) < TOLERANCE)
		end
		-- L:1595-1596 ("role": "scenery"): v6's lane-side clouds past its gates, beside its lane (which ends at 8,500,
		-- L:1369, as ours does), keep their v6 distance; nothing stands past the lane's end.
		expect.truthy(math.abs(laneOf(piece(7, "dh_gold_cloud_39") :: Model).Z - 8375) < TOLERANCE)
		expect.truthy(math.abs(laneOf(piece(7, "dh_gold_cloud_40") :: Model).Z - 8440) < TOLERANCE)
		for index in BIOME_MODELS do
			for _, row in HighwayScenery.biomes[index] do
				expect.truthy(laneOf(piece(index, row.id) :: Model).Z <= gatesAt + TOLERANCE)
			end
		end
	end)

	t.test("none of the gameplay pieces is built (boosters, traps, reward bubbles: phases 15 and 17)", function()
		local found: { string } = {}
		for _, d in root:GetDescendants() do
			local kind = d:GetAttribute("SD_Piece")
			if type(kind) == "string" and table.find(NOT_NOW, kind) then
				table.insert(found, d:GetFullName())
			end
		end
		expect.deepEqual(found, {})
	end)

	t.test("each kind is as big as K says, every part one of its K parts in that K material's look", function()
		local problems: { string } = {}
		local measured: { [string]: boolean } = {}
		for index in BIOME_MODELS do
			for _, row in HighwayScenery.biomes[index] do
				local kind = kindOf(row.id)
				local spec = PIECES[kind]
				local model = piece(index, row.id)
				if spec == nil or model == nil then
					table.insert(problems, row.id .. ": no K entry or no model")
					continue
				end
				local frame = (model :: Model).WorldPivot
				local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
				for _, part in partsOf(model :: Model) do
					local k = spec.parts[part.Name]
					local tint = TINTED[row.id]
					if k == nil then
						table.insert(problems, row.id .. "." .. part.Name .. " is not a K part of " .. kind)
					elseif k == "GumdropTint" or k == "PopsicleTint" then
						local ok2 = false
						for _, hex in TINTS[kind] do
							ok2 = ok2 or same(part.Color, hex)
						end
						if
							not ok2
							or (tint and not same(part.Color, tint))
							or part.Material ~= Enum.Material.SmoothPlastic
						then
							table.insert(problems, row.id .. "." .. part.Name .. " is not its row's tint")
						end
					else
						local m = MATERIALS[k]
						if
							not same(part.Color, m.hex)
							or part.Material ~= m.material
							or math.abs(part.Reflectance - (m.reflectance or 0)) > 1e-3
						then
							table.insert(problems, row.id .. "." .. part.Name .. " is not " .. k)
						end
					end
					-- Its box in the piece's frame (a Ball's is its sphere's).
					local cf, half = frame:ToObjectSpace(part.CFrame), part.Size / 2
					local isBall = part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Ball
					for _, sx in { -1, 1 } do
						for _, sy in { -1, 1 } do
							for _, sz in { -1, 1 } do
								local p = if isBall
									then cf.Position + Vector3.new(sx, sy, sz) * half
									else cf:PointToWorldSpace(half * Vector3.new(sx, sy, sz))
								low, high = low:Min(p), high:Max(p)
							end
						end
					end
				end
				if not measured[kind] then
					measured[kind] = true
					local size = high - low
					for _, axis in { "X", "Y", "Z" } do
						local want = (spec.size :: any)[axis] :: number
						local got = (size :: any)[axis] :: number
						if math.abs(got - want) > math.max(SIZE_FLOOR, SIZE_SHARE * want) then
							table.insert(
								problems,
								string.format("%s is %.2f on %s, K says %.2f", kind, got, axis, want)
							)
						end
					end
				end
			end
		end
		expect.deepEqual(problems, {})
	end)

	t.test("the volcano carries the biome's light (L:4 L3_volcano, HK:71 light_anchor at 66 up)", function()
		local volcano = piece(5, "lv_volcano_01") :: Model
		local light = volcano:FindFirstChild("L3_volcano", true)
		expect.truthy(light ~= nil and light:IsA("PointLight"))
		local pointLight = light :: PointLight
		expect.truthy(same(pointLight.Color, "#FF8A4D"))
		expect.equal(pointLight.Brightness, 2)
		expect.equal(pointLight.Range, 60)
		expect.falsy(pointLight.Shadows)
		local anchor = pointLight.Parent :: Attachment
		expect.equal(anchor.Name, "light_anchor")
		-- Its WorldCFrame (offline runs have no Attachment.WorldCFrame): the host part's CFrame times its CFrame.
		local at = ((anchor.Parent :: BasePart).CFrame * anchor.CFrame).Position
		local want = (mapped(Vector3.new(-230, 0, -3312), 0) * CFrame.new(0, 66, 0)).Position -- L:4 (-230, 66, -3312)
		expect.truthy((at - want).Magnitude < TOLERANCE)
		local lights = 0
		for _, d in root:GetDescendants() do
			lights += if d:IsA("Light") then 1 else 0
		end
		expect.equal(lights, 3) -- L:2 the deck, L:4 the volcano, L:5 the Golden Gates
	end)

	t.test("the volcano's crater: only the lava v6 shows (HK:69-70), a rim closed all round", function()
		local volcano = piece(5, "lv_volcano_01") :: Model
		local frame = volcano.WorldPivot
		local rim: { BasePart } = {}
		local lakes = 0
		for _, part in partsOf(volcano) do
			local isBlock = part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Block
			if part.Name == "volcano" and isBlock then
				table.insert(rim, part)
			elseif part.Name == "volcano_lava" and not isBlock then
				-- HK:69's crater floor (y = 61 + 0.2 r) covers HK:70's lake (top 61.4) beyond r 2: an upright Cylinder.
				lakes += 1
				local top = frame:PointToObjectSpace(part.CFrame.Position).Y + part.Size.X / 2
				expect.truthy(part.Size.Y <= 4 + TOLERANCE and part.Size.Z <= 4 + TOLERANCE)
				expect.truthy(math.abs(top - 61.4) < TOLERANCE)
			end
		end
		expect.equal(lakes, 1)
		-- Every point of a circle just inside the rim's outer edge (r 14.5) lies in one of its Blocks: no notches.
		for step = 0, 63 do
			local a = step * math.pi / 32
			local at = frame * Vector3.new(14.3 * math.cos(a), 63.5, 14.3 * math.sin(a))
			local inside = false
			for _, block in rim do
				local p, half = block.CFrame:PointToObjectSpace(at), block.Size / 2
				inside = inside or (math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z)
			end
			expect.truthy(inside)
		end
	end)

	t.test("nobody reaches the scenery: none of it collides or is queried, all anchored and untouched", function()
		local problems: { string } = {}
		for index in BIOME_MODELS do
			for _, row in HighwayScenery.biomes[index] do
				for _, part in partsOf(piece(index, row.id) :: Model) do
					if part.CanCollide or part.CanQuery or part.CanTouch or not part.Anchored then
						table.insert(problems, part:GetFullName())
					end
				end
			end
		end
		expect.deepEqual(problems, {})
	end)

	t.test("every biome within v6's 600 pieces and the phone budget of parts", function()
		for _, name in BIOME_MODELS do
			local biome = root:FindFirstChild(name) :: Model
			local pieces, parts = 0, 0
			for _, child in biome:GetChildren() do
				pieces += if child:GetAttribute("SD_Piece") ~= nil then 1 else 0
			end
			for _, d in biome:GetDescendants() do
				parts += if d:IsA("BasePart") then 1 else 0
			end
			expect.truthy(pieces <= MAX_PIECES)
			expect.truthy(parts <= PHONE_PARTS)
		end
	end)

	t.test("scenery for another number of biomes than Config's stops the build, nothing built", function()
		table.insert(HighwayScenery.biomes, {})
		local again = Cleanup.new()
		local built, other = pcall(HighwayBuilder.build, { scratch = again, Shared = t.Shared })
		table.remove(HighwayScenery.biomes)
		again:clean()
		expect.truthy(built and not other.ok and other.root == nil)
		expect.truthy(string.find(tostring(other.error), "HighwayScenery", 1, true) ~= nil)
	end)

	-- Last: until here the clone is in use.
	root:Destroy()
	tools:Destroy()
end
