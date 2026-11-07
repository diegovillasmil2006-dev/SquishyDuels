--!strict
-- HighwayBoosters: the two boosters of each highway biome, the objects of the owner's "Launchers & Biomes - Concept Sheet"
-- (Desktop "jason designs", Candy Toy-Box Park Lobby.zip, concept-kit.js:280-299, `M.<biome>_<booster>`), in
-- Art/HighwayTraps' shape and builder. a and b are the sheet's two in the order it lines them up on its lanes
-- (concept-kit.js:455-499). The course (2026-11-06): HighwayService stands them on the lane at
-- Config.Economy.Highway.course.spots.
-- 2026-11-06 (owner: "more roblox style, they look so bland, take hit a golf ball as an example", "Yes, build all 14"): big
-- toy models (tools/meshes/highway_boosters.py): smooth, 2-3 loud colours and one bright detail, the stud tile only on the
-- stands, no ink hull; each with an "x2" floating over it, seen from Config/GearShop.booster.sign.maxDistance.
--   HighwayBoosters.build(biome, kind, origin) -> Model?  biome 1..7's booster "a" or "b" (HighwayTraps.make) with its
--                                                         sign, nil for any other biome or kind

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GearShop = require(Shared.Config.GearShop)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local HighwayTraps = require(script.Parent.HighwayTraps)

local A: { HighwayTraps.Trap } = {
	{ -- 1 Candy Meadow (concept-kit.js:280): "Bounces the squishy up and forward."
		id = "cm_jelly_pad",
		pal = {
			base = { "Stud", "FFF3B0" },
			ring = { "Smooth", "FF2E93" },
			jelly = { "Smooth", "FF6FC0" },
			bean = { "Smooth", "FFD21F" },
			light = { "Neon", "35F0FF" },
		},
	},
	{ -- 2 Bakery Town (concept-kit.js:283)
		id = "bt_toaster_cannon",
		pal = {
			base = { "Stud", "B8C4E8" },
			body = { "Smooth", "1F8FFF" },
			trim = { "Smooth", "FFD21F" },
			toast = { "Smooth", "F6B860" },
			crumb = { "Smooth", "FFE6B8" },
			dark = { "Smooth", "16103A" },
			knob = { "Smooth", "FF2E4D" },
		},
	},
	{ -- 3 Boba Lagoon (concept-kit.js:286): "Bouncy pearls: high bounce."
		id = "bl_pearl_bouncer",
		pal = {
			base = { "Stud", "35D8C8" },
			ring = { "Smooth", "FF2E93" },
			pearl = { "Smooth", "4A2460" },
			shine = { "Smooth", "FFFFFF" },
			light = { "Neon", "FFD21F" },
		},
	},
	{ -- 4 Frozen Dessert Peaks (concept-kit.js:289): "Speeds the squishy up."
		id = "fd_ice_slide",
		pal = {
			base = { "Stud", "6FB8FF" },
			ice = { "Smooth", "5FE3FF" },
			curb = { "Smooth", "1F8FFF" },
			snow = { "Smooth", "FFFFFF" },
			cherry = { "Smooth", "FF2E93" },
			chev = { "Neon", "FFFFFF" },
		},
	},
	{ -- 5 Lava Volcano (concept-kit.js:292): "Launches the squishy up."
		id = "lv_fire_jet",
		pal = {
			base = { "Stud", "6A3A5C" },
			rock = { "Smooth", "4A2546" },
			glow = { "Neon", "FF5A1F" },
			mid = { "Neon", "FFB03A" },
			core = { "Neon", "FFF0A0" },
		},
	},
	{ -- 6 Rainbow Road (concept-kit.js:295)
		id = "rr_star_ring",
		pal = {
			base = { "Stud", "B98CFF" },
			post = { "Smooth", "6F5CFF" },
			halo = { "Smooth", "FF4FA3" },
			hoop = { "Neon", "FFD84A" },
			star = { "Neon", "FFFFFF" },
		},
	},
	{ -- 7 Divine Heaven (concept-kit.js:298)
		id = "dh_wing_gate",
		pal = {
			plinth = { "Stud", "FFD76A" },
			marble = { "Smooth", "FFFFFF" },
			gold = { "Smooth", "FFB300" },
			wing = { "Smooth", "FFFFFF" },
			halo = { "Neon", "FFE36A" },
			cloud = { "Smooth", "BFE8FF" },
		},
	},
}

local B: { HighwayTraps.Trap } = {
	{ -- 1 Candy Meadow (concept-kit.js:281)
		id = "cm_sprinkle_ramp",
		pal = {
			base = { "Stud", "FFF3B0" },
			ramp = { "Smooth", "18D8B4" },
			wall = { "Smooth", "FF2E93" },
			post = { "Smooth", "FFD21F" },
			chev = { "Neon", "FFF6A8" },
			cream = { "Smooth", "FFFFFF" },
		},
	},
	{ -- 2 Bakery Town (concept-kit.js:284)
		id = "bt_butter_slide",
		pal = {
			foil = { "Stud", "FFF6EC" },
			stripe = { "Smooth", "FF3E5C" },
			butter = { "Smooth", "FFD21F" },
			melt = { "Smooth", "FFF6B8" },
			chev = { "Neon", "FF5A1F" },
		},
	},
	{ -- 3 Boba Lagoon (concept-kit.js:287)
		id = "bl_straw_tube",
		pal = {
			base = { "Stud", "35D8C8" },
			foot = { "Smooth", "FFD21F" },
			pink = { "Smooth", "FF3E96" },
			white = { "Smooth", "FFFFFF" },
			rim = { "Neon", "35F0FF" },
		},
	},
	{ -- 4 Frozen Dessert Peaks (concept-kit.js:290)
		id = "fd_cone_cannon",
		pal = {
			base = { "Stud", "DFF4FF" },
			cheek = { "Smooth", "3FA8FF" },
			trim = { "Smooth", "FFD21F" },
			cone = { "Smooth", "E8A050" },
			band = { "Smooth", "B86A28" },
			scoop = { "Smooth", "FF6FB8" },
			cherry = { "Smooth", "FF2E4D" },
		},
	},
	{ -- 5 Lava Volcano (concept-kit.js:293)
		id = "lv_magma_ramp",
		pal = {
			base = { "Stud", "6A3A5C" },
			ramp = { "Smooth", "7A2E3A" },
			wall = { "Smooth", "FF4D1F" },
			seam = { "Neon", "FF9A1F" },
			rock = { "Smooth", "3A2340" },
		},
	},
	{ -- 6 Rainbow Road (concept-kit.js:296): "Speed pad; the trail turns rainbow."
		id = "rr_comet_pad",
		pal = {
			base = { "Stud", "6F5CFF" },
			pad = { "Smooth", "A06BFF" },
			fin = { "Smooth", "FF4FA3" },
			chev = { "Neon", "FFFFFF" },
			star = { "Neon", "FFD84A" },
			tail = { "Neon", "FF5C8A" },
		},
	},
	{ -- 7 Divine Heaven (concept-kit.js:299): "Speed ring."
		id = "dh_halo_ring",
		pal = {
			plinth = { "Stud", "FFD76A" },
			gold = { "Smooth", "FFB300" },
			halo = { "Neon", "FFE36A" },
			wing = { "Smooth", "FFFFFF" },
		},
	},
}

-- Module table

local HighwayBoosters = {}

HighwayBoosters.lists = { a = A, b = B }

-- Private

-- The floating "x2", on an attachment over the model's top (see the header).
local function addSign(model: Model, origin: CFrame)
	local sign = GearShop.booster.sign
	local box, size = model:GetBoundingBox()
	local top = origin:PointToObjectSpace(box.Position).Y + size.Y / 2
	-- lihfolk-ignore: findfirstchild-chain a piece's template always holds its meshes (setup refuses anything else)
	local part = model:FindFirstChildWhichIsA("BasePart") :: BasePart
	local anchor = Instance.new("Attachment")
	anchor.Name = "SignAnchor"
	anchor.Position = part.CFrame:PointToObjectSpace(origin:PointToWorldSpace(Vector3.new(0, top + sign.liftStuds + sign.heightStuds / 2, 0)))
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(sign.widthStuds, sign.heightStuds) -- studs (a BillboardGui's scale)
	gui.LightInfluence = 0
	gui.MaxDistance = sign.maxDistance
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = Strings.format(Strings.highway.boosterSign, { x = Config.Economy.Highway.course.bounceDistance })
	label.TextScaled = true
	label.TextColor3 = (Palette :: any)[sign.color]
	local stroke = Instance.new("UIStroke")
	stroke.Color = (Palette :: any)[sign.stroke]
	stroke.Thickness = sign.strokePx
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = anchor
	anchor.Parent = part
end

-- Public

function HighwayBoosters.build(biome: number, kind: string, origin: CFrame): Model?
	local list = HighwayBoosters.lists[kind]
	local booster = if list then list[biome] else nil
	local model = if booster then HighwayTraps.make(booster, origin) else nil
	if model ~= nil then
		addSign(model, origin)
	end
	return model
end

return HighwayBoosters
