--!strict
-- CapsuleMath: pure capsule arithmetic for the big-number progression (spec 2026-10-12 §3-§7, §9; lobby spec
-- 2026-10-11 §5-§6). Shared: the server pays from it (Phase 3: CapsuleService, the squeeze value of your own squeezes
-- and rewards) and the client shows it (Phase 5). Every number comes from Config.Grip.Capsule, the Catalog's squishy
-- power and Config.Economy.maxCoins. No instances, no yields, no side effects.
--
-- A capsule level is a whole number 1..Capsule.maxLevel (100) and a slot a whole number 1..#Capsule.slotPrices (4).
-- Anything else is not one: tier, seconds, power, price, gripLevelFor and slotPrice return nil for it (fail closed),
-- and squeezeValue skips such an entry.
--
-- API:
--   CapsuleMath.tier(level)              -> number?: ceil(level / levelsPerTier), 1 (Foam, Lv1-10) .. 10 (Royal, Lv91-100)
--   CapsuleMath.seconds(level)           -> number?: the tier's seconds between two squeezes (4.0 at Foam .. 1.3 at Royal)
--   CapsuleMath.power(level)             -> number?: capsule power CP = round(base × growth^(level - 1) ×
--                                           tierMultiplier^(tier - 1)): 10 at Lv1, 30 at Lv10, 68 at Lv11, 920,525,589
--                                           at Lv100. A capsule squeeze pays squishy power × CP Coins and CP Grip.
--   CapsuleMath.price(level)             -> number?: Coins from level to level + 1 = base × growth^(level - 1) rounded
--                                           to `digits` significant digits; a tier's last level (the evolve: 10, 20 ..
--                                           90) costs evolveMultiplier × that rounded price (1K at Lv1, 28K at Lv10,
--                                           2.9Qa at Lv99); nil at maxLevel (nothing to buy)
--   CapsuleMath.gripLevelFor(level)      -> number?: the Grip Level the level's tier needs (0 for Foam, 10 for Jelly ..
--                                           90 for Royal)
--   CapsuleMath.slotPrice(slot)          -> number?: Coins to unlock the slot (0, 2,500, 80,000, 1,500,000)
--   CapsuleMath.squishyPower(id)         -> number: Catalog.getPower(id) (1 / 4 / 16 / 64 by rarity; 0 for an unknown id)
--   CapsuleMath.squeezeValue(capsules)   -> number: Coins per squeeze of the best capsule, the max of squishyPower(id) ×
--                                           power(level) over the { level, squishyId } entries (an entry without a known
--                                           squishy or a level skipped); with none, the starter's value (Kitty Bread ×
--                                           CP(1) = 10): a new player's squeeze is 10 Coins (spec §9)
--   CapsuleMath.rewardCoins(squeezes, value) -> number: a reward counted in squeezes as Coins, floor(squeezes × value),
--                                           clamped to [0, Config.Economy.maxCoins] (a negative or non-finite input
--                                           counts as 0)
--
-- Rounding is Luau's math.round (half away from zero); no CP or price of today's table is within 0.003 of a half, so
-- float noise never moves one (CapsuleMath_Test checks every spec row).

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Catalog = require(script.Parent.Catalog)
local Config = require(script.Parent.Config)

-- Types

-- One capsule as the squeeze value reads it.
export type CapsuleEntry = { level: number, squishyId: string? }

-- Constants

local CAPSULE = Config.Grip.Capsule
local TIERS = CAPSULE.Tiers
local POWER = CAPSULE.power
local PRICE = CAPSULE.price
local SLOT_PRICES = CAPSULE.slotPrices

-- Module table

local CapsuleMath = {}

-- Private

local function isWholeNumber(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and math.floor(n) == n
end

local function isLevel(level: unknown): boolean
	return isWholeNumber(level) and (level :: number) >= 1 and (level :: number) <= CAPSULE.maxLevel
end

-- n for a finite n >= 0, else 0.
local function amount(n: unknown): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n < 0 then
		return 0
	end
	return n
end

-- base × growth^(level - 1), rounded to PRICE.digits significant digits (never below whole Coins).
local function roundedBase(level: number): number
	local raw = PRICE.base * PRICE.growth ^ (level - 1)
	local scale = math.max(1, 10 ^ (math.floor(math.log10(raw)) + 1 - PRICE.digits))
	return math.round(raw / scale) * scale
end

-- Public: one capsule level

function CapsuleMath.tier(level: number): number?
	if not isLevel(level) then
		return nil
	end
	return math.ceil(level / CAPSULE.levelsPerTier)
end

function CapsuleMath.seconds(level: number): number?
	local tier = CapsuleMath.tier(level)
	return if tier then TIERS[tier].seconds else nil
end

function CapsuleMath.power(level: number): number?
	local tier = CapsuleMath.tier(level)
	if tier == nil then
		return nil
	end
	return math.round(POWER.base * POWER.growth ^ (level - 1) * POWER.tierMultiplier ^ (tier - 1))
end

function CapsuleMath.price(level: number): number?
	if not isLevel(level) or level >= CAPSULE.maxLevel then
		return nil
	end
	local price = roundedBase(level)
	if level % CAPSULE.levelsPerTier == 0 then
		price *= PRICE.evolveMultiplier
	end
	return price
end

function CapsuleMath.gripLevelFor(level: number): number?
	local tier = CapsuleMath.tier(level)
	return if tier then TIERS[tier].gripLevel else nil
end

function CapsuleMath.slotPrice(slot: number): number?
	if not isWholeNumber(slot) or slot < 1 or slot > #SLOT_PRICES then
		return nil
	end
	return SLOT_PRICES[slot]
end

-- Public: squishies, the squeeze value and rewards

function CapsuleMath.squishyPower(id: unknown): number
	return Catalog.getPower(id)
end

function CapsuleMath.squeezeValue(capsules: { CapsuleEntry }?): number
	local best = 0
	if type(capsules) == "table" then
		for _, entry in capsules do
			if type(entry) == "table" then
				local cp = CapsuleMath.power(entry.level)
				local squishy = CapsuleMath.squishyPower(entry.squishyId)
				if cp ~= nil and squishy > 0 then
					best = math.max(best, squishy * cp)
				end
			end
		end
	end
	if best == 0 then
		return CapsuleMath.squishyPower(Catalog.starterId()) * (CapsuleMath.power(1) :: number)
	end
	return best
end

function CapsuleMath.rewardCoins(squeezes: number, value: number): number
	return math.min(math.floor(amount(squeezes) * amount(value)), Config.Economy.maxCoins)
end

return table.freeze(CapsuleMath)
