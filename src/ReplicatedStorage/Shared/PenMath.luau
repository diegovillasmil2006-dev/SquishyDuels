--!strict
-- PenMath: pure pen arithmetic (pens3 phase 1, 2026-10-17). Shared: the server pays from it (PenService, the squeeze
-- value of own squeezes and of every reward counted in squeezes) and the client shows it (the coin labels, the sign,
-- the reward texts). Every number comes from Config.Economy.Pen (Config/Pen), the Catalog's squishy power,
-- Config.Economy.maxCoins and WorldLayout.Bases.pen. No instances, no yields, no side effects.
--
-- A pen is a profile's `pen` = Types.PenState {spots, nextId, items}. An item is Types.PenItem {id, kind, form, level,
-- coat}: kind a Catalog id, form 0..#formMult - 1, level 1..maxLevel, coat 0..#coatMult - 1, all whole. Anything else
-- earns 0 and takes no spot (fail closed); a pen whose spots is not a whole number in [startSpots, maxSpots] places
-- nothing.
--
-- API:
--   PenMath.itemRate(item)       -> number: Coins a second, coinsPerPower × Catalog.getPower(kind) × formMult[form + 1]
--                                   × coatMult[coat + 1] × levelGain^(level - 1) (Kitty Bread 10, Butter 40, Bird 160,
--                                   Dragon 640); 0 for anything that is not an item
--   PenMath.placed(pen)          -> {PenItem}: the best `spots` items, the higher rate first, a tie to the lower id
--   PenMath.rate(pen)            -> number: the placed items' Coins a second (the pen's pay)
--   PenMath.squeezeValue(pen)    -> number: SV = max(minSqueezeValue, rate(pen)); nil or a broken pen gives 10. What an
--                                   own squeeze and every reward counted in squeezes is worth (coatings in; toys and
--                                   Friend Boost, from later phases, never). A pure function of saved data.
--   PenMath.squeezeGrip(pen)     -> number: floor(SV), the Grip of one own squeeze before Double Grip
--   PenMath.rewardCoins(squeezes, value) -> number: floor(squeezes × value) clamped to [0, maxCoins] (a negative or
--                                   non-finite input counts as 0). Copied unchanged from CapsuleMath (its copy goes
--                                   with it in phase 3).
--   PenMath.spotPrice(spot)      -> number?: the Coins of spot startSpots + 1 .. maxSpots, else nil
--   PenMath.buyDecision(pen, expectedPrice) -> ({spot, price}?, code?): the pure PenBuySpot checks, the first that
--                                   applies wins: expectedPrice not whole Coins in [0, maxCoins], or a broken pen ->
--                                   "net.invalid"; no spot left -> "pen.max"; expectedPrice ~= the next spot's price ->
--                                   "pen.priceChanged" (the client's price is only compared; prices strictly rise, so a
--                                   retry is refused, never charged twice); else the next spot and its price.
--   PenMath.payStep(carry, rate, dt) -> (coins, carry): dt clamped to [0, maxTickSeconds]; coins = floor(carry +
--                                   rate × dt) (at most maxCoins), the rest carried to the next tick
--   PenMath.encode(items)        -> string: "kind.form.level.coat" per item joined by ";" (the base's SD_Pen attribute;
--                                   entries that are not items are left out)
--   PenMath.decode(text)         -> {{kind, form, level, coat}}: the reverse; malformed entries are skipped
--   PenMath.wanderRect(spots, studs) -> {minX, maxX, minZ, maxZ}?: where the centre of a squishy `studs` long may walk,
--                                   in plot-local studs: inside the steps[spots] fence (WorldLayout.Bases.pen), half its
--                                   size plus edgeMargin in from every side; nil for a spot count with no step

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Catalog = require(script.Parent.Catalog)
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)
local Validate = require(script.Parent.Util.Validate)
local WorldLayout = require(script.Parent.World.WorldLayout)

-- Types

export type Buy = { spot: number, price: number }
export type Look = { kind: string, form: number, level: number, coat: number }
export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

-- Constants

local PEN = Config.Economy.Pen
local MAX_COINS = Config.Economy.maxCoins
local LAYOUT = WorldLayout.Bases.pen
local CODE_INVALID = "net.invalid"
local CODE_MAX = "pen.max"
local CODE_PRICE = "pen.priceChanged"

-- Module table

local PenMath = {}

-- Private

local function isWhole(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and math.floor(n) == n
end

local function inRange(n: unknown, lo: number, hi: number): boolean
	return isWhole(n) and (n :: number) >= lo and (n :: number) <= hi
end

-- n for a finite n >= 0, else 0.
local function amount(n: unknown): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n < 0 then
		return 0
	end
	return n
end

-- True for a look an item can have (kind, form, level, coat; the id is not part of it).
local function isLook(look: any): boolean
	return type(look) == "table"
		and Catalog.isValidId(look.kind)
		and inRange(look.form, 0, #PEN.formMult - 1)
		and inRange(look.level, 1, PEN.maxLevel)
		and inRange(look.coat, 0, #PEN.coatMult - 1)
end

local function isItem(item: any): boolean
	return isLook(item) and isWhole(item.id)
end

-- The pen's open spots, or nil for anything that is not a pen.
local function spotsOf(pen: any): number?
	local spots = if type(pen) == "table" then pen.spots else nil
	return if inRange(spots, PEN.startSpots, PEN.maxSpots) then spots else nil
end

-- Public: one item and the pen

function PenMath.itemRate(item: any): number
	if not isLook(item) then
		return 0
	end
	return PEN.coinsPerPower
		* Catalog.getPower(item.kind)
		* PEN.formMult[item.form + 1]
		* PEN.coatMult[item.coat + 1]
		* PEN.levelGain ^ (item.level - 1)
end

function PenMath.placed(pen: any): { Types.PenItem }
	local spots = spotsOf(pen)
	local items = if spots ~= nil then pen.items else nil
	if type(items) ~= "table" then
		return {}
	end
	local list: { Types.PenItem } = {}
	for _, item in items do
		if isItem(item) then
			table.insert(list, item)
		end
	end
	table.sort(list, function(a: Types.PenItem, b: Types.PenItem): boolean
		local ra, rb = PenMath.itemRate(a), PenMath.itemRate(b)
		if ra ~= rb then
			return ra > rb
		end
		return a.id < b.id
	end)
	for index = #list, (spots :: number) + 1, -1 do
		list[index] = nil
	end
	return list
end

function PenMath.rate(pen: any): number
	local total = 0
	for _, item in PenMath.placed(pen) do
		total += PenMath.itemRate(item)
	end
	return total
end

function PenMath.squeezeValue(pen: any): number
	return math.max(PEN.minSqueezeValue, PenMath.rate(pen))
end

function PenMath.squeezeGrip(pen: any): number
	return math.floor(PenMath.squeezeValue(pen))
end

function PenMath.rewardCoins(squeezes: number, value: number): number
	return math.min(math.floor(amount(squeezes) * amount(value)), Config.Economy.maxCoins)
end

-- Public: spots

function PenMath.spotPrice(spot: any): number?
	if not inRange(spot, PEN.startSpots + 1, PEN.maxSpots) then
		return nil
	end
	return PEN.spotPrices[spot]
end

function PenMath.buyDecision(pen: any, expectedPrice: any): (Buy?, string?)
	local spots = spotsOf(pen)
	if Validate.coins(expectedPrice) == nil or spots == nil then
		return nil, CODE_INVALID
	end
	local spot = (spots :: number) + 1
	local price = PenMath.spotPrice(spot)
	if price == nil then
		return nil, CODE_MAX
	end
	if expectedPrice ~= price then
		return nil, CODE_PRICE
	end
	return { spot = spot, price = price }, nil
end

-- Public: the tick

function PenMath.payStep(carry: number, rate: number, dt: number): (number, number)
	local seconds = math.clamp(amount(dt), 0, PEN.maxTickSeconds)
	local due = amount(carry) + amount(rate) * seconds
	local coins = math.min(math.floor(due), MAX_COINS)
	return coins, due - coins
end

-- Public: the base attribute and the walk area

function PenMath.encode(items: { any }): string
	local parts: { string } = {}
	for _, item in items do
		if isLook(item) then
			table.insert(parts, string.format("%s.%d.%d.%d", item.kind, item.form, item.level, item.coat))
		end
	end
	return table.concat(parts, ";")
end

function PenMath.decode(text: any): { Look }
	local list: { Look } = {}
	if type(text) ~= "string" then
		return list
	end
	for _, part in string.split(text, ";") do
		local fields = string.split(part, ".")
		if #fields == 4 then
			local look = {
				kind = fields[1],
				form = tonumber(fields[2]),
				level = tonumber(fields[3]),
				coat = tonumber(fields[4]),
			}
			if isLook(look) then
				table.insert(list, look :: any)
			end
		end
	end
	return list
end

function PenMath.wanderRect(spots: number, studs: number): Rect?
	local step = LAYOUT.steps[spots]
	if step == nil then
		return nil
	end
	local inset = studs / 2 + LAYOUT.edgeMargin
	return {
		minX = -step.w / 2 + inset,
		maxX = step.w / 2 - inset,
		minZ = LAYOUT.frontZ - step.d + inset,
		maxZ = LAYOUT.frontZ - inset,
	}
end

return table.freeze(PenMath)
