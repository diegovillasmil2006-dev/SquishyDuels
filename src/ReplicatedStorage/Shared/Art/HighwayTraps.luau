--!strict
-- HighwayTraps: the 7 highway traps of the owner's "Launchers & Biomes - Concept Sheet" (Desktop "jason designs",
-- Candy Toy-Box Park Lobby.zip, concept-kit.js:282-300, `M.<biome>_<trap>`), one per biome in highway order (traps you
-- can see, plan step 5, 2026-10-31: HighwayService shows the landing biome's trap under a trapped throw where it
-- stops). Each stands on the lane top at its origin (y 0 = the lane top), x right and z back like the lane
-- (WorldLayout.highwayCFrame).
-- 2026-11-07 (owner: "Yes, build all 7" on a sample, after the boosters' "more roblox style ... take hit a golf ball as
-- an example"): big toy models like the boosters (tools/meshes/highway_props.py with highway_boosters.py's kit): smooth,
-- loud colours, the stud tile only on rims, low and gooey with a dark edge so they look like a bad thing to hit, with
-- room in the middle for the stuck squishy. They replace the blocky ones with an ink hull of 2026-11-01. Kept in
-- ServerStorage.SD_HighwayProps as one Model per piece (MeshParts named by palette key; pivot = the lane top centre;
-- tools/meshes/highway_props_setup.luau). This module paints a clone: "Stud" = SmoothPlastic with the lobby's stud tile,
-- "Smooth" = plain SmoothPlastic, "Neon" glows without a shadow.
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
local STUD = "SquishyStud" -- the stud tile MaterialVariant of Diego's lobby (SquishyLobby/Theme.Stud)

local TRAPS: { Trap } = {
	{ -- 1 Candy Meadow: a gum puddle with a dark edge, big bubbles with a shine
		id = "cm_gum_puddle",
		pal = {
			edge = { "Smooth", "B0157A" },
			gum = { "Smooth", "FF4FAE" },
			bub = { "Smooth", "FF8AD0" },
			shine = { "Smooth", "FFFFFF" },
		},
	},
	{ -- 2 Bakery Town: a jam puddle with dollops, berry bits with gold seeds
		id = "bt_jam_puddle",
		pal = {
			edge = { "Smooth", "5E0B2A" },
			jam = { "Smooth", "D81458" },
			berry = { "Smooth", "FF3D6B" },
			seed = { "Smooth", "FFD21F" },
		},
	},
	{ -- 3 Boba Lagoon: a dark studded rim round milk-tea water, ripples, a splash crown
		id = "bl_splash_pool",
		pal = {
			rim = { "Stud", "4A2460" },
			water = { "Smooth", "1FB8C8" },
			ripple = { "Smooth", "BFF6FF" },
			drop = { "Smooth", "E8FBFF" },
		},
	},
	{ -- 4 Frozen Dessert Peaks: a heap of marshmallows in melted goo, burnt at the edge, toasty tops
		id = "fd_marshmallow",
		pal = {
			edge = { "Smooth", "7A3E2A" },
			goo = { "Smooth", "FFE4EF" },
			m = { "Smooth", "FFF8FB" },
			pink = { "Smooth", "FF9CC9" },
			toast = { "Smooth", "DE8A3E" },
		},
	},
	{ -- 5 Lava Volcano: a studded basalt rim and rocks round glowing lava, a bright inner rim, bubbles
		id = "lv_lava_pit",
		pal = {
			rim = { "Stud", "4A2546" },
			rock = { "Smooth", "2E1A33" },
			lava = { "Neon", "FF5A1F" },
			glow = { "Neon", "FFB03A" },
		},
	},
	{ -- 6 Rainbow Road: soft clouds with a lilac shade round a dark swirling gap
		id = "rr_cloud_gap",
		pal = {
			hole = { "Smooth", "2B1E66" },
			swirl = { "Smooth", "7C5CFF" },
			shade = { "Smooth", "C7B6FF" },
			cloud = { "Smooth", "FFFFFF" },
		},
	},
	{ -- 7 Divine Heaven: a soft gold cloud with an amber edge, light caps on its puffs
		id = "dh_soft_cloud",
		pal = { edge = { "Smooth", "D98A00" }, cloud = { "Smooth", "FFC93C" }, hi = { "Smooth", "FFF1BF" } },
	},
}

-- Module table

local HighwayTraps = {}

HighwayTraps.list = TRAPS
HighwayTraps.PROPS = PROPS

-- Private

local function paint(part: BasePart, entry: { string })
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
		local entry = piece.pal[part.Name]
		if part:IsA("BasePart") and entry ~= nil then
			paint(part, entry)
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
