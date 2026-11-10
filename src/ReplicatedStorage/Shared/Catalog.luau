--!strict
-- Catalog: the 27 squishy definitions (DESIGN §4.1, §4.2; the 6 after Dragon from the squishy overhaul spec
-- 2026-10-09 §3.3; the 6 Series 01, then the 7 of the Frosty Box at the end, 2026-11-10), in catalog order. Shared (server and client).
-- Every system (inventory, shop, squeeze rewards, Inspect, combat, quests) reads these fields; no stat is copied
-- anywhere else. All numbers are [P]. Box membership and odds live in Boxes.luau, prices are checked against box
-- odds by Pricing.luau, the throw power budget is checked by server Logic/PowerBudget (§5.8), and the cross-checks
-- (bands, rarities, ultimate ids, starter, Strings keys) run in Config.validate().
-- Shop prices are ECONOMY_V3:163's (pens3 phase 5: Commons 789K, Butter and Chocolate 1.875M, Mochi Fox and Strawberry
-- Frog 3.75M, Epics 1.8B, Dragon 1.1T; were the spec 2026-10-12 §6 ladder 10K / 2.7M / 1.7B / 1.1T), each at most its
-- box ceiling (Pricing.ceiling); the first of each Common costs the Welcome price instead (Pricing.shopPrice).
--
-- API:
--   Catalog.get(id)              -> SquishyDef? (nil for an unknown id or a non-string)
--   Catalog.list()               -> { SquishyDef } in catalog order (a new array each call; the defs are frozen)
--   Catalog.isValidId(v)         -> boolean (v is the id of a squishy in the catalog)
--   Catalog.starterId()          -> "kitty_bread" (the free starter: Common, not in boxes, not sold)
--   Catalog.byRarity(r)          -> { SquishyDef } of that rarity in catalog order (empty for a non-rarity)
--   Catalog.getPower(id)         -> squishy power (spec 2026-10-12 §3, §6): def.power, else
--                                   Config.Economy.SquishyPower[rarity] (1 / 2 / 4 / 16 / 256) × def.boxMult (a zone
--                                   box's squishies, plan "50 squishies": Frosty 3); 0 for an unknown id
--
-- Field notes (§4.1, §4.2):
--   blueprintId  key in Art/SquishyBlueprints; the same as the id for all 14.
--   visuals      trail = nil for Commons; flightSpin "wobble" = ±8° roll, "roll" = 360°/s roll about the travel
--                axis (the face always leads); accent "#RRGGBB" (vignette, puffs, trail start).
--   anim         squeezeFx names a hook in Config.Anim.squeeze.squeezeFx (Exclusive flourish only). The "ears
--                rigidity 0.2" / "wings rigidity 0.3" notes of §4.2 are part rigidities in the blueprints (§8.2).
--   hold         grip offset from RightGripAttachment, heldYaw degrees (§9.5 weld C1).
--   inspect      default 3/4 view, degrees.
--   power        optional squishy power for one squishy (spec 2026-10-12 §6: tunable without touching the others); no
--                def sets one today, so each uses Config.Economy.SquishyPower by rarity.
--   eliminationEffectId  the kill set (Art/KillStyle; kill banners 2026-10-16): its kill banner, kill sounds and kill
--                effect. Every Common, Uncommon and Rare squishy shares "standard"; each squishy above Rare has its own.

local Config = require(script.Parent.Config)
local TableUtil = require(script.Parent.Util.TableUtil)
local Types = require(script.Parent.Types)

-- Types

type SquishyDef = Types.SquishyDef

-- Constants

local STARTER_ID = "kitty_bread"

-- §4.2, in table order. Throw: speed studs/s, gravity studs/s², radius studs, cooldown s, windup s.
local DEFS: { SquishyDef } = {
	{
		id = "kitty_bread",
		nameKey = "squishy.kittyBread.name",
		rarity = "Common",
		blueprintId = "kitty_bread",
		-- shopPrice nil: the free starter (not in boxes, not sold)
		throw = { speed = 95, gravity = 35, radius = 1.0, cooldown = 1.00, windup = 0.18 },
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#D98E47" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.42, 0.10), heldYaw = 35 },
		inspect = { yaw = 20, pitch = 8 },
	},
	{
		id = "toast",
		nameKey = "squishy.toast.name",
		rarity = "Common",
		blueprintId = "toast",
		shopPrice = 789_000,
		throw = { speed = 105, gravity = 25, radius = 0.8, cooldown = 1.05, windup = 0.18 },
		eliminationEffectId = "standard",
		visuals = { flightSpin = "roll", accent = "#C9853F" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.26 },
		hold = { grip = Vector3.new(0, -0.42, 0.30), heldYaw = 35 }, -- z 0.30: held from behind (play-check: hand hid the mouth)
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "banana",
		nameKey = "squishy.banana.name",
		rarity = "Common",
		blueprintId = "banana",
		shopPrice = 789_000,
		throw = { speed = 88, gravity = 50, radius = 1.2, cooldown = 0.95, windup = 0.18 },
		eliminationEffectId = "standard",
		visuals = { flightSpin = "roll", accent = "#FFE066" },
		anim = { squeezeAxis = "Z", foamRecoveryT = 0.30 },
		hold = { grip = Vector3.new(0, -0.30, 0.32), heldYaw = 35 }, -- z 0.32: held from behind (thin squishy)
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "butter",
		nameKey = "squishy.butter.name",
		rarity = "Uncommon",
		blueprintId = "butter",
		shopPrice = 937_500, -- half the Pricing.ceiling: Uncommon power 4 -> 2 (2026-11-01, the same pay-back)
		throw = { speed = 95, gravity = 30, radius = 0.9, cooldown = 1.05, windup = 0.15 },
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#FFD86B" }, -- Ribbon (gold)
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.42 },
		hold = { grip = Vector3.new(0, -0.40, 0.05), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "chocolate",
		nameKey = "squishy.chocolate.name",
		rarity = "Uncommon",
		blueprintId = "chocolate",
		shopPrice = 937_500, -- half the Pricing.ceiling: Uncommon power 4 -> 2 (2026-11-01, the same pay-back)
		throw = { speed = 90, gravity = 40, radius = 1.4, cooldown = 1.00, windup = 0.18 },
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#7A4632" }, -- Ribbon (cocoa)
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.34 },
		hold = { grip = Vector3.new(0, -0.55, 0.30), heldYaw = 35 }, -- z 0.30: held from behind (play-check: hand hid the mouth)
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "bird",
		nameKey = "squishy.bird.name",
		rarity = "Epic",
		blueprintId = "bird",
		shopPrice = 1_800_000_000,
		throw = { speed = 110, gravity = 20, radius = 0.9, cooldown = 1.10, windup = 0.18 },
		ultimateId = "flock_volley", -- spec phase 5: the design's Epic ultimate (ults.js:3), paid for out of the budget
		eliminationEffectId = "feather_storm", -- kill banners 2026-10-16: its own kill set (Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#7CC0F5" }, -- Twin ribbon + sparkle
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.30 },
		hold = { grip = Vector3.new(0, -0.50, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "donut",
		nameKey = "squishy.donut.name",
		rarity = "Epic",
		blueprintId = "donut",
		shopPrice = 1_800_000_000,
		throw = { speed = 92, gravity = 38, radius = 1.3, cooldown = 1.00, windup = 0.19 },
		ultimateId = "sprinkle_roller", -- spec phase 5 (ults.js:4)
		eliminationEffectId = "sprinkle_blast", -- kill banners 2026-10-16: its own kill set (Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "roll", accent = "#FF8FB1" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.36 },
		hold = { grip = Vector3.new(0, -0.60, 0.32), heldYaw = 35 }, -- z 0.32: held from behind (thin squishy)
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "dragon",
		nameKey = "squishy.dragon.name",
		rarity = "Exclusive",
		blueprintId = "dragon",
		shopPrice = 1_100_000_000_000, -- the guaranteed Coin path to Dragon (§6.6)
		throw = { speed = 92, gravity = 35, radius = 1.0, cooldown = 1.05, windup = 0.19 },
		ultimateId = "dragon_rush", -- paid for out of the power budget (§5.8)
		eliminationEffectId = "dragon_blaze", -- kill banners 2026-10-16: its own kill set (Art/KillStyle)
		visuals = { trail = "ember", flightSpin = "wobble", accent = "#3FB8AF" }, -- Ember comet
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.30, squeezeFx = "dragon_steam" },
		hold = { grip = Vector3.new(0, -0.60, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	-- Spec 2026-10-09 §3.3: appended after Dragon so pedestal slots 1-8 stay put. Each throw is an exact copy of a
	-- same-rarity sibling (no new balance point); hold.grip and inspect are retuned in the Studio pass.
	{
		id = "boba_bear",
		nameKey = "squishy.bobaBear.name",
		rarity = "Common",
		blueprintId = "boba_bear",
		shopPrice = 789_000,
		throw = { speed = 95, gravity = 35, radius = 1.0, cooldown = 1.00, windup = 0.18 }, -- = kitty_bread
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#B07A52" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.30 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "pancake_pup",
		nameKey = "squishy.pancakePup.name",
		rarity = "Common",
		blueprintId = "pancake_pup",
		shopPrice = 789_000,
		throw = { speed = 105, gravity = 25, radius = 0.8, cooldown = 1.05, windup = 0.18 }, -- = toast
		eliminationEffectId = "standard",
		visuals = { flightSpin = "roll", accent = "#C8752A" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.36 },
		hold = { grip = Vector3.new(0, -0.35, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 20 },
	},
	{
		id = "mochi_fox",
		nameKey = "squishy.mochiFox.name",
		rarity = "Rare", -- 2026-11-01 (the Rare tier, pens3 phase 22)
		blueprintId = "mochi_fox",
		shopPrice = 3_750_000, -- the Pricing.ceiling (pens3 phase 5)
		throw = { speed = 95, gravity = 30, radius = 0.9, cooldown = 1.05, windup = 0.15 }, -- = butter
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#F39A4C" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.42 },
		hold = { grip = Vector3.new(0, -0.40, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "strawberry_frog",
		nameKey = "squishy.strawberryFrog.name",
		rarity = "Rare", -- 2026-11-01 (the Rare tier, pens3 phase 22)
		blueprintId = "strawberry_frog",
		shopPrice = 3_750_000, -- the Pricing.ceiling (pens3 phase 5)
		throw = { speed = 90, gravity = 40, radius = 1.4, cooldown = 1.00, windup = 0.18 }, -- = chocolate
		eliminationEffectId = "standard",
		-- The design's trail start: the body red (#EE4A5C) is too near the reserved Danger red (splat red guard).
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#FF9AA8" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.28 },
		hold = { grip = Vector3.new(0, -0.50, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "cloud_bunny",
		nameKey = "squishy.cloudBunny.name",
		rarity = "Epic",
		blueprintId = "cloud_bunny",
		shopPrice = 1_800_000_000,
		throw = { speed = 110, gravity = 20, radius = 0.9, cooldown = 1.10, windup = 0.18 }, -- = bird
		ultimateId = "rain_check", -- spec phase 5 (ults.js:5)
		eliminationEffectId = "cloudburst", -- kill banners 2026-10-16: its own kill set (Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#D5C8F6" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.42 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "cupcake_axolotl",
		nameKey = "squishy.cupcakeAxolotl.name",
		rarity = "Epic",
		blueprintId = "cupcake_axolotl",
		shopPrice = 1_800_000_000,
		throw = { speed = 92, gravity = 38, radius = 1.3, cooldown = 1.00, windup = 0.19 }, -- = donut
		ultimateId = "bubble_pop", -- spec phase 5 (ults.js:6)
		eliminationEffectId = "bubble_burst", -- kill banners 2026-10-16: its own kill set (Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#F9AFCB" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.50, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	-- Series 01 (owner 2026-11-10 "Yes, Series 01 first"; plan "50 squishies" step 3; looks from Claude Design's
	-- "Squishies 50 Lineup", sd/toys2.js CATALOG2): appended so every slot before stays put. 5 go in the Soft Box, Cosmo
	-- (the design's Legendary = our Exclusive) in the Sweet Box next to Dragon. Each throw is an exact copy of a
	-- same-rarity sibling (no new balance point) and each price its sibling's; accents are the design's trail colours.
	{
		id = "berry_jelly",
		nameKey = "squishy.berryJelly.name",
		rarity = "Common",
		blueprintId = "berry_jelly",
		shopPrice = 789_000,
		throw = { speed = 95, gravity = 35, radius = 1.0, cooldown = 1.00, windup = 0.18 }, -- = kitty_bread
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#FF7AA5" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.28 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "peachy",
		nameKey = "squishy.peachy.name",
		rarity = "Common",
		blueprintId = "peachy",
		shopPrice = 789_000,
		throw = { speed = 105, gravity = 25, radius = 0.8, cooldown = 1.05, windup = 0.18 }, -- = toast
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#FFA868" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.36 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "grapey",
		nameKey = "squishy.grapey.name",
		rarity = "Uncommon",
		blueprintId = "grapey",
		shopPrice = 937_500, -- = butter
		throw = { speed = 95, gravity = 30, radius = 0.9, cooldown = 1.05, windup = 0.15 }, -- = butter
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#B27AEB" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.30 },
		hold = { grip = Vector3.new(0, -0.50, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "bao_buddy",
		nameKey = "squishy.baoBuddy.name",
		rarity = "Rare",
		blueprintId = "bao_buddy",
		shopPrice = 3_750_000, -- = mochi_fox
		throw = { speed = 95, gravity = 30, radius = 0.9, cooldown = 1.05, windup = 0.15 }, -- = mochi_fox
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#E8C892" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.40 },
		hold = { grip = Vector3.new(0, -0.40, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "pando",
		nameKey = "squishy.pando.name",
		rarity = "Rare",
		blueprintId = "pando",
		shopPrice = 3_750_000, -- = strawberry_frog
		throw = { speed = 90, gravity = 40, radius = 1.4, cooldown = 1.00, windup = 0.18 }, -- = strawberry_frog
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "roll", accent = "#FFC25E" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.42 },
		hold = { grip = Vector3.new(0, -0.50, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "cosmo",
		nameKey = "squishy.cosmo.name",
		rarity = "Exclusive", -- the design's Legendary (Strings show Exclusive as "Legendary")
		blueprintId = "cosmo",
		shopPrice = 1_100_000_000_000, -- = dragon
		throw = { speed = 92, gravity = 35, radius = 1.0, cooldown = 1.05, windup = 0.19 }, -- = dragon
		ultimateId = "gravity_well", -- the design's own (sd/ults2.js:4), paid for out of the power budget (§5.8)
		eliminationEffectId = "cosmo_supernova", -- the design's kill set (sd/ults2.js:43, Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#C7A0FF" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.55, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	-- Frosty Box (owner 2026-11-10 "lets build everything", box by box; plan "50 squishies" step 4; looks from Claude
	-- Design's "Squishies 50 Lineup", sd/toys2.js:168-330, CATALOG2 round 2): the first zone box, opened once the player
	-- reaches Frozen Dessert Peaks (Boxes zone 4). boxMult 3: they earn and sell for 3x their rarity (plan, "Yes, use
	-- 3x"). Prices: the Frosty ceilings (Pricing.ceiling, 20B box), the Uncommons half theirs like the Soft ones; no
	-- Welcome price (Soft Box Commons only). Each throw copies a same-rarity sibling (no new balance point); accents are
	-- colours from the design (its trail or body).
	{
		id = "cone_cub",
		nameKey = "squishy.coneCub.name",
		rarity = "Common",
		blueprintId = "cone_cub",
		boxMult = 3,
		shopPrice = 66_000_000_000,
		throw = { speed = 95, gravity = 35, radius = 1.0, cooldown = 1.00, windup = 0.18 }, -- = kitty_bread
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#E9B46C" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.34 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "slushy_seal",
		nameKey = "squishy.slushySeal.name",
		rarity = "Common",
		blueprintId = "slushy_seal",
		boxMult = 3,
		shopPrice = 66_000_000_000,
		throw = { speed = 105, gravity = 25, radius = 0.8, cooldown = 1.05, windup = 0.18 }, -- = toast
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#8ED3FA" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.30 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "ice_pop_beaver",
		nameKey = "squishy.icePopBeaver.name",
		rarity = "Uncommon",
		blueprintId = "ice_pop_beaver",
		boxMult = 3,
		shopPrice = 76_900_000_000,
		throw = { speed = 95, gravity = 30, radius = 0.9, cooldown = 1.05, windup = 0.15 }, -- = butter
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#A0623A" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.50, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "mint_chip_mouse",
		nameKey = "squishy.mintChipMouse.name",
		rarity = "Uncommon",
		blueprintId = "mint_chip_mouse",
		boxMult = 3,
		shopPrice = 76_900_000_000,
		throw = { speed = 90, gravity = 40, radius = 1.4, cooldown = 1.00, windup = 0.18 }, -- = chocolate
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#9AE4C2" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.34 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "sundae_manatee",
		nameKey = "squishy.sundaeManatee.name",
		rarity = "Rare",
		blueprintId = "sundae_manatee",
		boxMult = 3,
		shopPrice = 200_000_000_000,
		throw = { speed = 95, gravity = 30, radius = 0.9, cooldown = 1.05, windup = 0.15 }, -- = mochi_fox
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#B0AAE6" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.40 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "gelato_narwhal",
		nameKey = "squishy.gelatoNarwhal.name",
		rarity = "Epic",
		blueprintId = "gelato_narwhal",
		boxMult = 3,
		shopPrice = 512_000_000_000,
		throw = { speed = 110, gravity = 20, radius = 0.9, cooldown = 1.10, windup = 0.18 }, -- = cloud_bunny
		ultimateId = "geyser_line", -- the design's own (sd/ults2.js:5), paid for out of the power budget (§5.8)
		eliminationEffectId = "narwhal_brain_freeze", -- the design's kill set (sd/ults2.js:57, Art/KillStyle),
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#8CCDEB" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "parfait_wyvern",
		nameKey = "squishy.parfaitWyvern.name",
		rarity = "Exclusive", -- the design's Legendary (Strings show Exclusive as "Legendary")
		blueprintId = "parfait_wyvern",
		boxMult = 3,
		shopPrice = 20_000_000_000_000,
		throw = { speed = 92, gravity = 35, radius = 1.0, cooldown = 1.05, windup = 0.19 }, -- = dragon
		ultimateId = "layer_cake_shockwave", -- the design's own (sd/ults2.js:6), paid for out of the power budget (§5.8)
		eliminationEffectId = "wyvern_sugar_storm", -- the design's kill set (sd/ults2.js:69, Art/KillStyle),
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#FF8FAE" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.55, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	-- Lava Box (2026-11-10, plan "50 squishies" step 5): the Lava ceilings (600B box: cost x 10,000 / weight), the
	-- Uncommons half theirs; throws = their siblings'; power and sell x9 (boxMult).
	{
		id = "cocoa_quokka",
		nameKey = "squishy.cocoaQuokka.name",
		rarity = "Common",
		blueprintId = "cocoa_quokka",
		boxMult = 9,
		shopPrice = 2_000_000_000_000,
		throw = { speed = 95, gravity = 35, radius = 1.0, cooldown = 1.00, windup = 0.18 }, -- = kitty_bread
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#C2915F" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.34 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "cinder_bun",
		nameKey = "squishy.cinderBun.name",
		rarity = "Common",
		blueprintId = "cinder_bun",
		boxMult = 9,
		shopPrice = 2_000_000_000_000,
		throw = { speed = 105, gravity = 25, radius = 0.8, cooldown = 1.05, windup = 0.18 }, -- = toast
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#DB9852" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "smore_skunk",
		nameKey = "squishy.smoreSkunk.name",
		rarity = "Uncommon",
		blueprintId = "smore_skunk",
		boxMult = 9,
		shopPrice = 2_300_000_000_000,
		throw = { speed = 95, gravity = 30, radius = 0.9, cooldown = 1.05, windup = 0.15 }, -- = butter
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#8E5E48" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "cayenne_kiwi",
		nameKey = "squishy.cayenneKiwi.name",
		rarity = "Uncommon",
		blueprintId = "cayenne_kiwi",
		boxMult = 9,
		shopPrice = 2_300_000_000_000,
		throw = { speed = 90, gravity = 40, radius = 1.4, cooldown = 1.00, windup = 0.18 }, -- = chocolate
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#FF8A3C" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.34 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "pizza_pangolin",
		nameKey = "squishy.pizzaPangolin.name",
		rarity = "Rare",
		blueprintId = "pizza_pangolin",
		boxMult = 9,
		shopPrice = 6_000_000_000_000,
		throw = { speed = 90, gravity = 40, radius = 1.4, cooldown = 1.00, windup = 0.18 }, -- = strawberry_frog
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#FFC94A" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.36 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "lava_cake_hippo",
		nameKey = "squishy.lavaCakeHippo.name",
		rarity = "Epic",
		blueprintId = "lava_cake_hippo",
		boxMult = 9,
		shopPrice = 15_300_000_000_000,
		throw = { speed = 92, gravity = 38, radius = 1.3, cooldown = 1.00, windup = 0.19 }, -- = donut
		ultimateId = "fondue_flood", -- the design's own (sd/ults2.js: Fondue Flood), paid for out of the power budget (§5.8)
		eliminationEffectId = "hippo_meltdown", -- the design's kill set (sd/ults2.js KILLSETS2.LavaCakeHippo, Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#FFA040" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.36 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "mallow_behemoth",
		nameKey = "squishy.mallowBehemoth.name",
		rarity = "Exclusive", -- the design's Legendary (Strings show Exclusive as "Legendary")
		blueprintId = "mallow_behemoth",
		boxMult = 9,
		shopPrice = 600_000_000_000_000,
		throw = { speed = 92, gravity = 35, radius = 1.0, cooldown = 1.05, windup = 0.19 }, -- = dragon
		ultimateId = "campfire_ring", -- the design's own (sd/ults2.js: Campfire Ring), paid for out of the power budget (§5.8)
		eliminationEffectId = "behemoth_bonfire", -- the design's kill set (sd/ults2.js KILLSETS2.MallowBehemoth, Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#EDB06A" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.40 },
		hold = { grip = Vector3.new(0, -0.55, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	-- Prism Box (2026-11-10, plan "50 squishies" step 6): the Prism ceilings (8T box: cost x 10,000 / weight, 3 digits
	-- down), the Uncommons half theirs; throws = their siblings'; power and sell x27 (boxMult).
	{
		id = "taffy_tadpole",
		nameKey = "squishy.taffyTadpole.name",
		rarity = "Common",
		blueprintId = "taffy_tadpole",
		boxMult = 27,
		shopPrice = 26_600_000_000_000,
		throw = { speed = 95, gravity = 35, radius = 1.0, cooldown = 1.00, windup = 0.18 }, -- = kitty_bread
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#FFB3D1" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.34 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "jellybean_piglet",
		nameKey = "squishy.jellybeanPiglet.name",
		rarity = "Common",
		blueprintId = "jellybean_piglet",
		boxMult = 27,
		shopPrice = 26_600_000_000_000,
		throw = { speed = 105, gravity = 25, radius = 0.8, cooldown = 1.05, windup = 0.18 }, -- = toast
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#FF8FB4" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "cotton_candy_alpaca",
		nameKey = "squishy.cottonCandyAlpaca.name",
		rarity = "Uncommon",
		blueprintId = "cotton_candy_alpaca",
		boxMult = 27,
		shopPrice = 30_700_000_000_000,
		throw = { speed = 95, gravity = 30, radius = 0.9, cooldown = 1.05, windup = 0.15 }, -- = butter
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#FFB8DA" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.40 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "lollipop_lemur",
		nameKey = "squishy.lollipopLemur.name",
		rarity = "Uncommon",
		blueprintId = "lollipop_lemur",
		boxMult = 27,
		shopPrice = 30_700_000_000_000,
		throw = { speed = 90, gravity = 40, radius = 1.4, cooldown = 1.00, windup = 0.18 }, -- = chocolate
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#FF8FC8" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.34 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "gumball_goat",
		nameKey = "squishy.gumballGoat.name",
		rarity = "Rare",
		blueprintId = "gumball_goat",
		boxMult = 27,
		shopPrice = 80_000_000_000_000,
		throw = { speed = 90, gravity = 40, radius = 1.4, cooldown = 1.00, windup = 0.18 }, -- = strawberry_frog
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#FFD36B" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.36 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "gummy_pufferfish",
		nameKey = "squishy.gummyPufferfish.name",
		rarity = "Epic",
		blueprintId = "gummy_pufferfish",
		boxMult = 27,
		shopPrice = 205_000_000_000_000,
		throw = { speed = 110, gravity = 20, radius = 0.9, cooldown = 1.10, windup = 0.18 }, -- = cloud_bunny (it floats)
		ultimateId = "puff_burst", -- the design's own (sd/ults2.js: Puff Burst), paid for out of the power budget (§5.8)
		eliminationEffectId = "puffer_pop_rocks", -- the design's kill set (sd/ults2.js KILLSETS2.GummyPufferfish, Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#FFB36B" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.30 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "candyglass_qilin",
		nameKey = "squishy.candyglassQilin.name",
		rarity = "Exclusive", -- the design's Legendary (Strings show Exclusive as "Legendary")
		blueprintId = "candyglass_qilin",
		boxMult = 27,
		shopPrice = 8_000_000_000_000_000,
		throw = { speed = 92, gravity = 35, radius = 1.0, cooldown = 1.05, windup = 0.19 }, -- = dragon
		ultimateId = "prism_pen", -- the design's own (sd/ults2.js: Prism Pen), paid for out of the power budget (§5.8)
		eliminationEffectId = "qilin_prism_parade", -- the design's kill set (sd/ults2.js KILLSETS2.CandyglassQilin, Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#C7A0FF" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.40 },
		hold = { grip = Vector3.new(0, -0.55, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	-- Halo Box (2026-11-10, plan "50 squishies" step 7): the Halo ceilings (80T box: cost x 10,000 / weight, 3 digits
	-- down), the Uncommons half theirs; throws = their siblings'; power and sell x81 (boxMult).
	{
		id = "meringue_chick",
		nameKey = "squishy.meringueChick.name",
		rarity = "Common",
		blueprintId = "meringue_chick",
		boxMult = 81,
		shopPrice = 266_000_000_000_000,
		throw = { speed = 95, gravity = 35, radius = 1.0, cooldown = 1.00, windup = 0.18 }, -- = kitty_bread
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#F4D9A0" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.34 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "cream_puff_kitten",
		nameKey = "squishy.creamPuffKitten.name",
		rarity = "Common",
		blueprintId = "cream_puff_kitten",
		boxMult = 81,
		shopPrice = 266_000_000_000_000,
		throw = { speed = 105, gravity = 25, radius = 0.8, cooldown = 1.05, windup = 0.18 }, -- = toast
		eliminationEffectId = "standard",
		visuals = { flightSpin = "wobble", accent = "#E9B66E" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.40, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "bumble_bun",
		nameKey = "squishy.bumbleBun.name",
		rarity = "Uncommon",
		blueprintId = "bumble_bun",
		boxMult = 81,
		shopPrice = 307_000_000_000_000,
		throw = { speed = 95, gravity = 30, radius = 0.9, cooldown = 1.05, windup = 0.15 }, -- = butter
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#F0A830" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.36 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "waffle_corgi",
		nameKey = "squishy.waffleCorgi.name",
		rarity = "Uncommon",
		blueprintId = "waffle_corgi",
		boxMult = 81,
		shopPrice = 307_000_000_000_000,
		throw = { speed = 90, gravity = 40, radius = 1.4, cooldown = 1.00, windup = 0.18 }, -- = chocolate
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#E5A85C" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.36 },
		hold = { grip = Vector3.new(0, -0.40, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "custard_cherub",
		nameKey = "squishy.custardCherub.name",
		rarity = "Rare",
		blueprintId = "custard_cherub",
		boxMult = 81,
		shopPrice = 800_000_000_000_000,
		throw = { speed = 90, gravity = 40, radius = 1.4, cooldown = 1.00, windup = 0.18 }, -- = strawberry_frog
		eliminationEffectId = "standard",
		visuals = { trail = "ribbon", flightSpin = "wobble", accent = "#F2C46A" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.36 },
		hold = { grip = Vector3.new(0, -0.45, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "souffle_seraph",
		nameKey = "squishy.souffleSeraph.name",
		rarity = "Epic",
		blueprintId = "souffle_seraph",
		boxMult = 81,
		shopPrice = 2_050_000_000_000_000,
		throw = { speed = 110, gravity = 20, radius = 0.9, cooldown = 1.10, windup = 0.18 }, -- = cloud_bunny (it floats)
		ultimateId = "halo_toss", -- the design's own (sd/ults2.js: Halo Toss), paid for out of the power budget (§5.8)
		eliminationEffectId = "seraph_ascension", -- the design's kill set (sd/ults2.js KILLSETS2.SouffleSeraph, Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#F4D27A" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.34 },
		hold = { grip = Vector3.new(0, -0.65, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
	{
		id = "divine_loaf",
		nameKey = "squishy.divineLoaf.name",
		rarity = "Exclusive", -- the design's Legendary (Strings show Exclusive as "Legendary")
		blueprintId = "divine_loaf",
		boxMult = 81,
		-- no shopPrice: its ceiling (80Qa) is over the coin cap (9Qa), so it only comes from the Halo Box
		throw = { speed = 92, gravity = 35, radius = 1.0, cooldown = 1.05, windup = 0.19 }, -- = dragon
		ultimateId = "bread_stamp", -- the design's own (sd/ults2.js: Bread Stamp), paid for out of the power budget (§5.8)
		eliminationEffectId = "divine_coronation", -- the design's kill set (sd/ults2.js KILLSETS2.DivineLoaf, Art/KillStyle)
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#D8C8FF" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.40 },
		hold = { grip = Vector3.new(0, -0.55, 0.10), heldYaw = 35 },
		inspect = { yaw = 25, pitch = 12 },
	},
}

local BY_ID: { [string]: SquishyDef } = {}
local BY_RARITY: { [string]: { SquishyDef } } = {}
for _, def in DEFS do
	BY_ID[def.id] = def
	local list = BY_RARITY[def.rarity]
	if list == nil then
		list = {}
		BY_RARITY[def.rarity] = list
	end
	table.insert(list, def)
end
TableUtil.deepFreeze(DEFS)
TableUtil.deepFreeze(BY_ID)
TableUtil.deepFreeze(BY_RARITY)

-- Module table

local Catalog = {}

-- Public

function Catalog.get(id: unknown): SquishyDef?
	if type(id) ~= "string" then
		return nil
	end
	return BY_ID[id]
end

function Catalog.list(): { SquishyDef }
	return table.clone(DEFS)
end

function Catalog.isValidId(v: unknown): boolean
	return Catalog.get(v) ~= nil
end

function Catalog.starterId(): string
	return STARTER_ID
end

function Catalog.byRarity(r: unknown): { SquishyDef }
	local list = if type(r) == "string" then BY_RARITY[r] else nil
	return if list then table.clone(list) else {}
end

function Catalog.getPower(id: unknown): number
	local def = Catalog.get(id)
	if def == nil then
		return 0
	end
	if def.power ~= nil then
		return def.power
	end
	return (Config.Economy.SquishyPower[def.rarity] or 0) * (def.boxMult or 1)
end

return table.freeze(Catalog)
