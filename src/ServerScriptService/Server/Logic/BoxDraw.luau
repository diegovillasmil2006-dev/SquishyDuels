--!strict
-- BoxDraw (server only, pure): the box draw (DESIGN §6.4). No instances, no yields; the random source is injected.
-- BoxService owns one server Random.new() (never sent to clients) and passes it in; tests pass a seeded or
-- scripted rng (Fakes/FakeRng).
--
-- API:
--   BoxDraw.pick(items, r)    -> string?: walks the ordered items accumulating weights and returns the first id with
--                                r <= acc; nil when r is not an integer in 1..(sum of the weights).
--   BoxDraw.isValid(boxDef)   -> boolean: at least one item, every weight a whole number >= 1, every id a string, and
--                                the weights sum to Boxes.WeightTotal (Config.validate guarantees it for the shipped
--                                boxes; BoxService may check it before taking Coins, to fail closed).
--   BoxDraw.draw(boxDef, rng) -> string: r = rng:NextInteger(1, Boxes.WeightTotal), then pick. Errors for a box that
--                                is not valid (or an rng that returns a number outside 1..WeightTotal).
-- No luck boosts, pity counters, rate-up or multi-open (§6.4): the odds are the box's weights, the same for everyone.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)

-- Types

export type BoxItem = Boxes.BoxItem
export type BoxDef = Boxes.BoxDef

-- Module table

local BoxDraw = {}

-- Private

-- isValid results of frozen box defs (a frozen def can't change), so draw checks each shipped box once.
local checkedFrozen: { [BoxDef]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function isWhole(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and math.floor(n) == n
end

local function isValidCached(boxDef: BoxDef): boolean
	if
		type(boxDef) ~= "table"
		or type(boxDef.items) ~= "table"
		or not table.isfrozen(boxDef)
		or not table.isfrozen(boxDef.items)
	then
		return BoxDraw.isValid(boxDef)
	end
	local known = checkedFrozen[boxDef]
	if known == nil then
		known = BoxDraw.isValid(boxDef)
		checkedFrozen[boxDef] = known
	end
	return known
end

-- Public

function BoxDraw.pick(items: { BoxItem }, r: number): string?
	if not isWhole(r) or r < 1 then
		return nil
	end
	local acc = 0
	for _, entry in items do
		acc += entry.weight
		if r <= acc then
			return entry.id
		end
	end
	return nil
end

function BoxDraw.isValid(boxDef: BoxDef): boolean
	if type(boxDef) ~= "table" or type(boxDef.items) ~= "table" or #boxDef.items == 0 then
		return false
	end
	local total = 0
	for _, entry in boxDef.items do
		if type(entry) ~= "table" or type(entry.id) ~= "string" or not isWhole(entry.weight) or entry.weight < 1 then
			return false
		end
		total += entry.weight
	end
	return total == Boxes.WeightTotal
end

function BoxDraw.draw(boxDef: BoxDef, rng: Random): string
	if not isValidCached(boxDef) then
		error("[SD][BoxDraw] the box's weights do not sum to Boxes.WeightTotal", 2)
	end
	local r = rng:NextInteger(1, Boxes.WeightTotal)
	local id = BoxDraw.pick(boxDef.items, r)
	if id == nil then
		error(`[SD][BoxDraw] the rng returned {r}, outside 1..{Boxes.WeightTotal}`, 2)
	end
	return id
end

return table.freeze(BoxDraw)
