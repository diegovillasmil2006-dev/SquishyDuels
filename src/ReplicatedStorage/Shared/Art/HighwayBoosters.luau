--!strict
-- HighwayBoosters: one booster per highway biome from the owner's "Launchers & Biomes - Concept Sheet" (Desktop
-- "jason designs", Candy Toy-Box Park Lobby.zip, concept-kit.js:280-299, `M.<biome>_<booster>`), ported part for part
-- in Art/HighwayTraps' shape and builder (boosters, plan step 6, 2026-10-31: HighwayService stands the touchdown
-- biome's booster where a lucky throw bounces). The sheet draws two boosters a biome; Claude's call (owner away): the
-- one each biome's kit calls allow (boxes, cylinders, balls, tori), the bouncy one where there is a choice:
--   1 Candy Meadow jelly pad, 2 Bakery Town toaster cannon, 3 Boba Lagoon pearl bouncer, 4 Frozen Dessert Peaks ice
--   slide, 5 Lava Volcano fire jet, 6 Rainbow Road comet pad, 7 Divine Heaven halo ring.
-- shortcut: two readings, until the custom shapes are made (Diego's to-do): the fire jet's vent is a tapered
-- 6-sided cylinder (2.6 -> 4.6) drawn as a round one of 3.6; the halo ring's two small extruded wings are left out.
--   HighwayBoosters.build(biome, origin) -> Model?  biome 1..7's booster (HighwayTraps.make), nil for any other biome

local HighwayTraps = require(script.Parent.HighwayTraps)

local K = HighwayTraps.kit
local u, b, c, s, r = K.u, K.b, K.c, K.s, K.r

local BOOSTERS: { HighwayTraps.Trap } = {
	{ -- 1 Candy Meadow (concept-kit.js:280): "Bounces the squishy up and forward."
		id = "cm_jelly_pad",
		pal = { base = { "Marble", "FF8FBF" }, jelly = { "Glass", "FF7FC0" }, bean = { "Sand", "FFD84A" } },
		parts = {
			u("base", { 8, 0.5, 8 }, { 0, 0, 0 }),
			u("jelly", { 7, 0.9, 7 }, { 0, 0.5, 0 }),
			u("bean", { 0.9, 0.4, 0.55 }, { -2.2, 1.4, -2 }, { 0, 20, 0 }),
			u("bean", { 0.9, 0.4, 0.55 }, { 2, 1.4, -1.6 }, { 0, -30, 0 }),
			u("bean", { 0.9, 0.4, 0.55 }, { -1.6, 1.4, 2.2 }, { 0, 60, 0 }),
			u("bean", { 0.9, 0.4, 0.55 }, { 2.3, 1.4, 2.1 }, { 0, 10, 0 }),
		},
	},
	{ -- 2 Bakery Town (concept-kit.js:283)
		id = "bt_toaster_cannon",
		pal = {
			body = { "Foil", "9FB4C7" },
			dark = { "Slate", "1E1428" },
			toast = { "Sand", "F2C487" },
			lever = { "Marble", "FF5C8A" },
		},
		parts = {
			u("dark", { 0.6, 0.3, 0.6 }, { -2.4, 0, -1.5 }),
			u("dark", { 0.6, 0.3, 0.6 }, { -2.4, 0, 1.5 }),
			u("dark", { 0.6, 0.3, 0.6 }, { 2.4, 0, -1.5 }),
			u("dark", { 0.6, 0.3, 0.6 }, { 2.4, 0, 1.5 }),
			u("body", { 6, 4, 4.2 }, { 0, 0.3, 0 }),
			u("dark", { 4, 0.12, 0.9 }, { 0, 4.3, -0.9 }),
			u("toast", { 3.6, 2.2, 0.7 }, { 0, 3.4, -0.9 }),
			u("dark", { 4, 0.12, 0.9 }, { 0, 4.3, 0.9 }),
			u("toast", { 3.6, 2.2, 0.7 }, { 0, 3.4, 0.9 }),
			u("lever", { 0.5, 0.7, 0.9 }, { 3.25, 2.2, 0 }),
		},
	},
	{ -- 3 Boba Lagoon (concept-kit.js:286): "Bouncy pearls: high bounce."
		id = "bl_pearl_bouncer",
		pal = { base = { "Glass", "FF6FA3" }, pearl = { "Foil", "3B2630" } },
		parts = {
			u("base", { 10, 0.4, 8 }, { 0, 0, 0 }),
			s("pearl", 4.4, { -2.2, 2.4, 0 }),
			s("pearl", 4.4, { 2.2, 2.4, 0.6 }),
			s("pearl", 4, { 0, 2.2, -2.2 }),
		},
	},
	{ -- 4 Frozen Dessert Peaks (concept-kit.js:289): "Speeds the squishy up."
		id = "fd_ice_slide",
		pal = { ice = { "Ice", "BDEBFF" }, curb = { "Glacier", "8FD8FF" }, snow = { "Sand", "F4FBFF" } },
		parts = {
			u("ice", { 12, 0.5, 26 }, { 0, 0, 0 }),
			u("curb", { 1, 0.9, 26 }, { -6.5, 0, 0 }),
			u("curb", { 1, 0.9, 26 }, { 6.5, 0, 0 }),
			u("snow", { 1.4, 1.1, 2.4 }, { -7.4, 0, -6 }),
			u("snow", { 1.4, 1.1, 2.4 }, { 7.4, 0, 4 }),
			u("snow", { 1.4, 1.1, 2.4 }, { -7.2, 0, 9 }),
		},
	},
	{ -- 5 Lava Volcano (concept-kit.js:292): "Launches the squishy up."
		id = "lv_fire_jet",
		pal = {
			vent = { "Basalt", "3A2C3A" },
			ring = { "Neon", "FF6A3D" },
			f1 = { "Neon", "FFB03A" },
			f2 = { "Glass", "FF6A3D" },
		},
		parts = {
			c("vent", 3.6, 1.6, { 0, 0.8, 0 }), -- the sheet's tapered vent 2.6 -> 4.6 (see the header)
			c("ring", 2.7, 0.2, { 0, 1.65, 0 }),
			u("f2", { 2.4, 4.4, 2.4 }, { 0, 1.7, 0 }, { 0, 45, 0 }),
			u("f1", { 1.4, 3.6, 1.4 }, { 0, 1.7, 0 }, { 0, 20, 0 }),
			u("f1", { 0.8, 2.2, 0.8 }, { 0, 6.1, 0 }, { 0, 45, 0 }),
			u("f2", { 1.2, 1.4, 1.2 }, { 0, 5.6, 0 }, { 0, 10, 0 }),
		},
	},
	{ -- 6 Rainbow Road (concept-kit.js:296): "Speed pad; the trail turns rainbow."
		id = "rr_comet_pad",
		pal = { pad = { "Glass", "B98CFF" }, chev = { "Neon", "FFFFFF" }, tail = { "Neon", "FF5C8A" } },
		parts = {
			u("pad", { 10, 0.5, 13 }, { 0, 0, 0 }),
			b("chev", { 3.2, 0.12, 0.7 }, { -1.25, 0.56, 3.5 }, { 0, -35, 0 }),
			b("chev", { 3.2, 0.12, 0.7 }, { 1.25, 0.56, 3.5 }, { 0, 35, 0 }),
			b("chev", { 3.2, 0.12, 0.7 }, { -1.25, 0.56, 0 }, { 0, -35, 0 }),
			b("chev", { 3.2, 0.12, 0.7 }, { 1.25, 0.56, 0 }, { 0, 35, 0 }),
			b("chev", { 3.2, 0.12, 0.7 }, { -1.25, 0.56, -3.5 }, { 0, -35, 0 }),
			b("chev", { 3.2, 0.12, 0.7 }, { 1.25, 0.56, -3.5 }, { 0, 35, 0 }),
			u("tail", { 1.2, 0.12, 4 }, { 0, 0.5, 5.4 }),
		},
	},
	{ -- 7 Divine Heaven (concept-kit.js:299): "Speed ring."
		id = "dh_halo_ring",
		pal = { halo = { "Neon", "FFF0A0" }, gold = { "Foil", "FFC23C" } },
		parts = {
			r("halo", 6, 0.6, { 0, 7.5, 0 }, 12),
			r("gold", 6.9, 0.32, { 0, 7.5, 0 }, 12), -- the two small side wings: see the header
		},
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
