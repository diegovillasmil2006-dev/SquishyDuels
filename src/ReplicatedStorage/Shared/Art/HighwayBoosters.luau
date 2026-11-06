--!strict
-- HighwayBoosters: the two boosters of each highway biome from the owner's "Launchers & Biomes - Concept Sheet" (Desktop
-- "jason designs", Candy Toy-Box Park Lobby.zip, concept-kit.js:280-299, `M.<biome>_<booster>`), in Art/HighwayTraps'
-- shape and builder. a and b are the sheet's two in the order it lines them up on its lanes (concept-kit.js:455-499).
-- The course (2026-11-06): HighwayService stands them on the lane at Config.Economy.Highway.course.spots.
-- 2026-11-01: blocky Blender meshes like the traps (tools/meshes/highway_props.py), with the sheet's tapered fire jet
-- vent and the halo ring's two gold wings; 2026-11-06: the sheet's other seven.
--   HighwayBoosters.build(biome, kind, origin) -> Model?  biome 1..7's booster "a" or "b" (HighwayTraps.make), nil for
--                                                         any other biome or kind

local HighwayTraps = require(script.Parent.HighwayTraps)

local A: { HighwayTraps.Trap } = {
	{ -- 1 Candy Meadow (concept-kit.js:280): "Bounces the squishy up and forward."
		id = "cm_jelly_pad",
		pal = { base = { "Stud", "FF8FBF" }, jelly = { "Stud", "FF7FC0" }, bean = { "Stud", "FFD84A" } },
	},
	{ -- 2 Bakery Town (concept-kit.js:283)
		id = "bt_toaster_cannon",
		pal = {
			body = { "Stud", "9FB4C7" },
			dark = { "Stud", "1E1428" },
			toast = { "Stud", "F2C487" },
			lever = { "Stud", "FF5C8A" },
		},
	},
	{ -- 3 Boba Lagoon (concept-kit.js:286): "Bouncy pearls: high bounce."
		id = "bl_pearl_bouncer",
		pal = { base = { "Stud", "FF6FA3" }, pearl = { "Stud", "3B2630" } },
	},
	{ -- 4 Frozen Dessert Peaks (concept-kit.js:289): "Speeds the squishy up."
		id = "fd_ice_slide",
		pal = { ice = { "Stud", "BDEBFF" }, curb = { "Stud", "8FD8FF" }, snow = { "Stud", "F4FBFF" } },
	},
	{ -- 5 Lava Volcano (concept-kit.js:292): "Launches the squishy up."
		id = "lv_fire_jet",
		pal = {
			vent = { "Stud", "3A2C3A" },
			ring = { "Neon", "FF6A3D" },
			f1 = { "Neon", "FFB03A" },
			f2 = { "Neon", "FF6A3D" },
		},
	},
	{ -- 6 Rainbow Road (concept-kit.js:295)
		id = "rr_star_ring",
		pal = { ring = { "Neon", "FFD84A" }, halo = { "Stud", "FFF0A0" }, star = { "Neon", "FFFFFF" } },
	},
	{ -- 7 Divine Heaven (concept-kit.js:298)
		id = "dh_wing_gate",
		pal = {
			marble = { "Stud", "FBF7F2" },
			gold = { "Stud", "FFC23C" },
			wing = { "Stud", "FFFFFF" },
			halo = { "Neon", "FFF0A0" },
		},
	},
}

local B: { HighwayTraps.Trap } = {
	{ -- 1 Candy Meadow (concept-kit.js:281)
		id = "cm_sprinkle_ramp",
		pal = {
			ramp = { "Stud", "8EEAD0" },
			s1 = { "Stud", "FF8FBF" },
			s2 = { "Stud", "FFD84A" },
			s3 = { "Stud", "FFF6EC" },
		},
	},
	{ -- 2 Bakery Town (concept-kit.js:284)
		id = "bt_butter_slide",
		pal = { butter = { "Stud", "FFE36E" }, melt = { "Stud", "FFE36E" }, foil = { "Stud", "FFF6EC" } },
	},
	{ -- 3 Boba Lagoon (concept-kit.js:287)
		id = "bl_straw_tube",
		pal = { tube = { "Stud", "FF6FA3" }, stripe = { "Stud", "FFF6EC" } },
	},
	{ -- 4 Frozen Dessert Peaks (concept-kit.js:290)
		id = "fd_cone_cannon",
		pal = { stand = { "Stud", "F4FBFF" }, cone = { "Stud", "E0A062" }, rim = { "Stud", "FF8FBF" } },
	},
	{ -- 5 Lava Volcano (concept-kit.js:293)
		id = "lv_magma_ramp",
		pal = { ramp = { "Stud", "3A2C3A" }, seam = { "Neon", "FF6A3D" } },
	},
	{ -- 6 Rainbow Road (concept-kit.js:296): "Speed pad; the trail turns rainbow."
		id = "rr_comet_pad",
		pal = { pad = { "Stud", "B98CFF" }, chev = { "Neon", "FFFFFF" }, tail = { "Neon", "FF5C8A" } },
	},
	{ -- 7 Divine Heaven (concept-kit.js:299): "Speed ring."
		id = "dh_halo_ring",
		pal = { halo = { "Neon", "FFF0A0" }, gold = { "Stud", "FFC23C" } },
	},
}

-- Module table

local HighwayBoosters = {}

HighwayBoosters.lists = { a = A, b = B }

function HighwayBoosters.build(biome: number, kind: string, origin: CFrame): Model?
	local list = HighwayBoosters.lists[kind]
	local booster = if list then list[biome] else nil
	return if booster then HighwayTraps.make(booster, origin) else nil
end

return HighwayBoosters
