--!strict
-- HighwayTraps: the 7 highway traps of the owner's "Launchers & Biomes - Concept Sheet" (Desktop "jason designs",
-- Candy Toy-Box Park Lobby.zip, concept-kit.js:282-300, `M.<biome>_<trap>`), one per biome in highway order (traps you
-- can see, plan step 5, 2026-10-31: HighwayService shows the landing biome's trap under a trapped throw where it
-- stops). Each stands on the lane top at its origin (y 0 = the lane top), x right and z back like the lane
-- (WorldLayout.highwayCFrame).
-- 2026-11-01, the owner's style rule (blocky, made in Blender, like Steal an Egg): the sheet's shapes are Blender
-- meshes (tools/meshes/highway_props.py: chamfered blocks, the stud tile UVs of Diego's lobby, an ink hull round every
-- part), kept in ServerStorage.SD_HighwayProps as one Model per piece (MeshParts named by palette key, plus
-- "Outline"; pivot = the lane top centre; tools/meshes/highway_props_setup.luau). This module paints a clone: "Stud" =
-- SmoothPlastic with the lobby's stud tile, "Smooth" = plain SmoothPlastic (the boosters' toys, 2026-11-06), "Neon" glows
-- without a shadow, the Outline is Diego's map ink.
--   HighwayTraps.build(biome, origin) -> Model?  an unparented decor Model (anchored, no collide, query or touch) of
--                                                biome 1..7's trap at `origin`; nil for any other biome
--   HighwayTraps.make(piece, origin) -> Model?   the same for any piece in this shape (Art/HighwayBoosters' too); nil
--                                                when its meshes are missing (server only: ServerStorage)

local ServerStorage = game:GetService("ServerStorage")

-- Types

-- pal: palette key (= the MeshPart's name) -> { "Stud" | "Smooth" | "Neon", its hex }
export type Trap = { id: string, pal: { [string]: { string } } }

-- Constants

local PROPS = "SD_HighwayProps" -- ServerStorage folder of the meshes
local OUTLINE = "Outline"
local STUD = "SquishyStud" -- the stud tile MaterialVariant of Diego's lobby (SquishyLobby/Theme.Stud)
local INK = Color3.fromHex("#1c1530") -- Diego's map outline ink (SkyMapBuilder INK)

local TRAPS: { Trap } = {
	{ id = "cm_gum_puddle", pal = { gum = { "Stud", "FF9ED2" }, bub = { "Stud", "FF7FC0" } } }, -- 1 Candy Meadow
	{ id = "bt_jam_puddle", pal = { jam = { "Stud", "C2185B" }, seed = { "Stud", "E0315F" } } }, -- 2 Bakery Town
	{ -- 3 Boba Lagoon
		id = "bl_splash_pool",
		pal = { rim = { "Stud", "EED6B8" }, water = { "Stud", "7FD8D0" }, drop = { "Stud", "DFF4FF" } },
	},
	{ id = "fd_marshmallow", pal = { m = { "Stud", "FFF3F7" }, toast = { "Stud", "F2C487" } } }, -- 4 Frozen Dessert Peaks
	{ -- 5 Lava Volcano
		id = "lv_lava_pit",
		pal = { rim = { "Stud", "3A2C3A" }, lava = { "Neon", "FF6A3D" }, bub = { "Neon", "FFB03A" } },
	},
	{ id = "rr_cloud_gap", pal = { cloud = { "Stud", "FFFFFF" }, shade = { "Stud", "E6DDFF" } } }, -- 6 Rainbow Road
	{ id = "dh_soft_cloud", pal = { cloud = { "Stud", "FFE9A8" }, hi = { "Stud", "FFF6EC" } } }, -- 7 Divine Heaven
}

-- Module table

local HighwayTraps = {}

HighwayTraps.list = TRAPS
HighwayTraps.PROPS = PROPS
HighwayTraps.OUTLINE = OUTLINE

-- Private

local function paint(part: BasePart, entry: { string }?)
	if entry == nil then -- the ink hull
		part.Color = INK
		part.Material = Enum.Material.SmoothPlastic
		return
	end
	part.Color = Color3.fromHex(entry[2])
	if entry[1] == "Neon" then
		part.Material = Enum.Material.Neon
		part.CastShadow = false
	else
		part.Material = Enum.Material.SmoothPlastic
		if entry[1] == "Stud" then
			part.MaterialVariant = STUD
		end
	end
end

-- Public

function HighwayTraps.make(piece: Trap, origin: CFrame): Model?
	local props = ServerStorage:FindFirstChild(PROPS)
	local template = props and props:FindFirstChild(piece.id)
	if template == nil then
		return nil
	end
	local model = template:Clone() :: Model
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			paint(part, if part.Name == OUTLINE then nil else piece.pal[part.Name])
		end
	end
	model:PivotTo(origin)
	return model
end

function HighwayTraps.build(biome: number, origin: CFrame): Model?
	local trap = TRAPS[biome]
	return if trap then HighwayTraps.make(trap, origin) else nil
end

return HighwayTraps
