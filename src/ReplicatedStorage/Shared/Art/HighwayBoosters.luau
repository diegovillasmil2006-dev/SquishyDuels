--!strict
-- HighwayBoosters: one booster per highway biome from the owner's "Launchers & Biomes - Concept Sheet" (Desktop
-- "jason designs", Candy Toy-Box Park Lobby.zip, concept-kit.js:280-299, `M.<biome>_<booster>`), in Art/HighwayTraps'
-- shape and builder (boosters, plan step 6, 2026-10-31: HighwayService stands the touchdown biome's booster where a
-- lucky throw bounces). The sheet draws two boosters a biome; Claude's call (owner away), the bouncy one where there
-- is a choice:
--   1 Candy Meadow jelly pad, 2 Bakery Town toaster cannon, 3 Boba Lagoon pearl bouncer, 4 Frozen Dessert Peaks ice
--   slide, 5 Lava Volcano fire jet, 6 Rainbow Road comet pad, 7 Divine Heaven halo ring.
-- 2026-11-01: blocky Blender meshes like the traps (tools/meshes/highway_props.py), now with the sheet's tapered fire
-- jet vent and the halo ring's two gold wings.
--   HighwayBoosters.build(biome, origin) -> Model?  biome 1..7's booster (HighwayTraps.make), nil for any other biome

local HighwayTraps = require(script.Parent.HighwayTraps)

local BOOSTERS: { HighwayTraps.Trap } = {
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

HighwayBoosters.list = BOOSTERS

function HighwayBoosters.build(biome: number, origin: CFrame): Model?
	local booster = BOOSTERS[biome]
	return if booster then HighwayTraps.make(booster, origin) else nil
end

return HighwayBoosters
