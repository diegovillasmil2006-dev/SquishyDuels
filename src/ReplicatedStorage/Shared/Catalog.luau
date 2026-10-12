--!strict
-- Catalog: the 14 squishy definitions (DESIGN §4.1, §4.2; the 6 after Dragon from the squishy overhaul spec
-- 2026-10-09 §3.3), in catalog order. Shared (server and client).
-- Every system (inventory, shop, squeeze rewards, Inspect, combat, quests) reads these fields; no stat is copied
-- anywhere else. All numbers are [P]. Box membership and odds live in Boxes.luau, prices are checked against box
-- odds by Pricing.luau, the throw power budget is checked by server Logic/PowerBudget (§5.8), and the cross-checks
-- (bands, rarities, ultimate ids, starter, Strings keys) run in Config.validate().
-- Shop prices follow the squishy ladder of spec 2026-10-12 §6 (Commons 10K, Uncommons 2.7M, Epics 1.7B, Dragon 1.1T;
-- were 1,200 / 2,500 / 7,500 / 25,000), each under its box ceiling (Pricing.ceiling).
--
-- API:
--   Catalog.get(id)              -> SquishyDef? (nil for an unknown id or a non-string)
--   Catalog.list()               -> { SquishyDef } in catalog order (a new array each call; the defs are frozen)
--   Catalog.isValidId(v)         -> boolean (v is the id of a squishy in the catalog)
--   Catalog.starterId()          -> "kitty_bread" (the free starter: Common, not in boxes, not sold)
--   Catalog.byRarity(r)          -> { SquishyDef } of that rarity in catalog order (empty for a non-rarity)
--   Catalog.getSqueezeCoins(id)  -> Coins per paid squeeze: def.squeezeCoins, else
--                                   Config.Economy.CoinsByRarity[rarity]; 0 for an unknown id (fail closed). Replaced by
--                                   the squeeze value (CapsuleMath) in Phase 3.
--   Catalog.getPower(id)         -> squishy power (spec 2026-10-12 §3, §6): def.power, else
--                                   Config.Economy.SquishyPower[rarity] (1 / 4 / 16 / 64); 0 for an unknown id
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
		shopPrice = 10_000,
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
		shopPrice = 10_000,
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
		shopPrice = 2_700_000,
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
		shopPrice = 2_700_000,
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
		shopPrice = 1_700_000_000,
		throw = { speed = 110, gravity = 20, radius = 0.9, cooldown = 1.10, windup = 0.18 },
		ultimateId = "flock_volley", -- spec phase 5: the design's Epic ultimate (ults.js:3), paid for out of the budget
		eliminationEffectId = "epic_pending", -- shows Standard until the Epic effect is approved (§9.9)
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
		shopPrice = 1_700_000_000,
		throw = { speed = 92, gravity = 38, radius = 1.3, cooldown = 1.00, windup = 0.19 },
		ultimateId = "sprinkle_roller", -- spec phase 5 (ults.js:4)
		eliminationEffectId = "epic_pending",
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
		eliminationEffectId = "standard",
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
		shopPrice = 10_000,
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
		shopPrice = 10_000,
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
		rarity = "Uncommon",
		blueprintId = "mochi_fox",
		shopPrice = 2_700_000,
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
		rarity = "Uncommon",
		blueprintId = "strawberry_frog",
		shopPrice = 2_700_000,
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
		shopPrice = 1_700_000_000,
		throw = { speed = 110, gravity = 20, radius = 0.9, cooldown = 1.10, windup = 0.18 }, -- = bird
		ultimateId = "rain_check", -- spec phase 5 (ults.js:5)
		eliminationEffectId = "epic_pending",
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
		shopPrice = 1_700_000_000,
		throw = { speed = 92, gravity = 38, radius = 1.3, cooldown = 1.00, windup = 0.19 }, -- = donut
		ultimateId = "bubble_pop", -- spec phase 5 (ults.js:6)
		eliminationEffectId = "epic_pending",
		visuals = { trail = "twinRibbon", flightSpin = "wobble", accent = "#F9AFCB" },
		anim = { squeezeAxis = "Y", foamRecoveryT = 0.32 },
		hold = { grip = Vector3.new(0, -0.50, 0.10), heldYaw = 35 },
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

function Catalog.getSqueezeCoins(id: unknown): number
	local def = Catalog.get(id)
	if def == nil then
		return 0
	end
	if def.squeezeCoins ~= nil then
		return def.squeezeCoins
	end
	return Config.Economy.CoinsByRarity[def.rarity] or 0
end

function Catalog.getPower(id: unknown): number
	local def = Catalog.get(id)
	if def == nil then
		return 0
	end
	if def.power ~= nil then
		return def.power
	end
	return Config.Economy.SquishyPower[def.rarity] or 0
end

return table.freeze(Catalog)
