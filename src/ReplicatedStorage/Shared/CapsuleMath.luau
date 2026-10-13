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
--   CapsuleMath.capsuleCoins(id, level)  -> number: Coins of one capsule squeeze, squishyPower(id) × power(level)
--                                           (0 for an unknown squishy or level)
--   CapsuleMath.squeezeValue(capsules)   -> number: Coins per squeeze of the best capsule, the max of capsuleCoins over
--                                           capsules.list (`capsules` = a profile's {slots, list}; an entry without a
--                                           known squishy or a level skipped); with none, the starter's value (Kitty
--                                           Bread × CP(1) = 10): a new player's squeeze is 10 Coins (spec §9)
--   CapsuleMath.squeezeGrip(capsules)    -> number: Grip of one own squeeze before Double Grip, the power of the
--                                           highest capsule level in capsules.list, empty capsules included (CP(1) = 10
--                                           with none; spec §3, §10)
--   CapsuleMath.rewardCoins(squeezes, value) -> number: a reward counted in squeezes as Coins, floor(squeezes × value),
--                                           clamped to [0, Config.Economy.maxCoins] (a negative or non-finite input
--                                           counts as 0)
--   CapsuleMath.upgradeDecision(capsules, slot, expectedPrice, gripLevel) -> Decision: the pure CapsuleUpgrade checks
--     (lobby spec §6) in GripMath.upgradeDecision's order, the first that applies wins:
--       2 slot a whole number 1..#slotPrices and expectedPrice whole Coins in [0, maxCoins], else "net.invalid";
--       the slot is unlocked (slot <= capsules.slots), else "capsule.locked"; below maxLevel, else "capsule.maxLevel";
--       6 the next level's Grip gate (gripLevelFor(level + 1) <= gripLevel), else "capsule.gripLocked";
--       7 expectedPrice == price(level), else "capsule.priceChanged" (the client's price is only compared);
--       else "buy" (cost = price(level)). No replay: a retry carries the old price, and two prices in a row always
--       differ (CapsuleMath_Test), so it is capsule.priceChanged and nothing is charged twice.
--   CapsuleMath.unlockDecision(capsules, slot, expectedPrice) -> Decision: the pure CapsuleUnlock checks, same order:
--       2 the argument range, else "net.invalid"; 4 slot <= capsules.slots -> "replay" (already unlocked: nothing is
--       charged; the slot count is the idempotency key); 5 slot ~= slots + 1 -> "capsule.notNext" (in order);
--       7 expectedPrice ~= slotPrice(slot) -> "capsule.priceChanged"; else "buy" (cost = slotPrice(slot)).
--
-- Rounding is Luau's math.round (half away from zero); no CP or price of today's table is within 0.003 of a half, so
-- float noise never moves one (CapsuleMath_Test checks every spec row).

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Catalog = require(script.Parent.Catalog)
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)
local Validate = require(script.Parent.Util.Validate)

-- Types

-- One capsule as the squeeze value reads it.
export type CapsuleEntry = { level: number, squishyId: string? }
export type Capsules = Types.CapsulesState
export type DecisionKind = "buy" | "replay" | "reject"
-- `cost` = the price the checks read (0 when the arguments are invalid or nothing can be bought).
export type Decision = { kind: DecisionKind, reason: string?, cost: number }

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

-- capsules.list, or an empty list for anything that is not a capsules state (fail closed).
local function listOf(capsules: Capsules?): { any }
	local list = if type(capsules) == "table" then (capsules :: any).list else nil
	return if type(list) == "table" then list else {}
end

-- capsules.slots (1 for anything else: the free first slot).
local function slotsOf(capsules: Capsules?): number
	local slots = if type(capsules) == "table" then (capsules :: any).slots else nil
	return if isWholeNumber(slots) then slots else 1
end

local function reject(reason: string, cost: number): Decision
	return { kind = "reject", reason = reason, cost = cost }
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

function CapsuleMath.capsuleCoins(id: unknown, level: number): number
	local cp = CapsuleMath.power(level)
	return if cp then CapsuleMath.squishyPower(id) * cp else 0
end

function CapsuleMath.squeezeValue(capsules: Capsules?): number
	local best = 0
	for _, entry in listOf(capsules) do
		if type(entry) == "table" then
			best = math.max(best, CapsuleMath.capsuleCoins(entry.squishyId, entry.level))
		end
	end
	if best == 0 then
		return CapsuleMath.capsuleCoins(Catalog.starterId(), 1)
	end
	return best
end

function CapsuleMath.squeezeGrip(capsules: Capsules?): number
	local highest = 1
	for _, entry in listOf(capsules) do
		if type(entry) == "table" and isLevel(entry.level) then
			highest = math.max(highest, entry.level)
		end
	end
	return CapsuleMath.power(highest) :: number
end

function CapsuleMath.rewardCoins(squeezes: number, value: number): number
	return math.min(math.floor(amount(squeezes) * amount(value)), Config.Economy.maxCoins)
end

-- Public: the CapsuleUpgrade / CapsuleUnlock checks

function CapsuleMath.upgradeDecision(
	capsules: Capsules?,
	slot: number,
	expectedPrice: number,
	gripLevel: number
): Decision
	if CapsuleMath.slotPrice(slot) == nil or Validate.coins(expectedPrice) == nil then
		return reject("net.invalid", 0)
	end
	local capsule = listOf(capsules)[slot]
	if type(capsule) ~= "table" or slot > slotsOf(capsules) then
		return reject("capsule.locked", 0)
	end
	local level = capsule.level
	local cost = CapsuleMath.price(level)
	if cost == nil then
		return reject("capsule.maxLevel", 0)
	end
	if (CapsuleMath.gripLevelFor(level + 1) :: number) > gripLevel then
		return reject("capsule.gripLocked", cost)
	end
	if expectedPrice ~= cost then
		return reject("capsule.priceChanged", cost)
	end
	return { kind = "buy", cost = cost }
end

function CapsuleMath.unlockDecision(capsules: Capsules?, slot: number, expectedPrice: number): Decision
	local cost = CapsuleMath.slotPrice(slot)
	if cost == nil or Validate.coins(expectedPrice) == nil then
		return reject("net.invalid", 0)
	end
	local slots = slotsOf(capsules)
	if slot <= slots then
		return { kind = "replay", cost = cost }
	end
	if slot ~= slots + 1 then
		return reject("capsule.notNext", cost)
	end
	if expectedPrice ~= cost then
		return reject("capsule.priceChanged", cost)
	end
	return { kind = "buy", cost = cost }
end

return table.freeze(CapsuleMath)
