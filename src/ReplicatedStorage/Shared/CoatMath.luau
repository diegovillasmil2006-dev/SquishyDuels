--!strict
-- CoatMath: the pure rules of the coatings (big job item 10, 2026-11-10; Config/Coats: the owner's wax-type items and
-- Claude's calls). Shared: the server decides every change with it (PenService.coat, HighwayService's zone gift), the
-- client shows the same answers (the pen window's picker). A coating is PenItem.coat 1..COUNT (0 = bare); the bag is
-- profile.bag, one count a coating. No instances, no yields, no side effects.
--
-- API:
--   CoatMath.COUNT                          the number of coatings (7)
--   CoatMath.def(coat) -> entry?            Config/Coats' entry (id, zone, price, look) of a coat 1..COUNT, else nil
--   CoatMath.inBag(bag, coat) -> number     how many of a coating a saved bag holds (broken or missing -> 0)
--   CoatMath.open(coat, biome) -> boolean   whether a coating can be bought: the player has reached its zone
--   CoatMath.decision(pen, bag, biome, itemId, coat, expectedPrice) -> (Change?, code?)
--                                           putting coating `coat` on the squishy `itemId` (0 = take its coating off):
--                                           {coat, price, fromBag}: free from the bag when it holds one, else bought
--                                           at the coating's price. Or nil and: net.invalid (not whole numbers, no
--                                           such coating, a broken pen), inventory.notOwned (no such squishy),
--                                           coat.same (it wears that already; nothing to take off), coat.zoneLocked
--                                           (none in the bag and its zone not reached), pen.priceChanged (the price
--                                           is compared, never charged: 0 for the bag and for taking off)
--   CoatMath.zoneGift(from, to) -> {coat}   the coatings of the zones after `from` up to `to` that are a zone's
--                                           reward (zones 3 and later: the design's "<zone> reward"), one each

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local COATS = require(Shared.Config.Coats).list
local PenMath = require(Shared.PenMath)

export type Change = { coat: number, price: number, fromBag: boolean }

local CoatMath = {}

CoatMath.COUNT = #COATS

local FIRST_REWARD_ZONE = 3 -- Wax and Glitter are plain shop items (the design's "Shop")
local CODE_INVALID = "net.invalid"
local CODE_NOT_OWNED = "inventory.notOwned"
local CODE_SAME = "coat.same"
local CODE_LOCKED = "coat.zoneLocked"
local CODE_PRICE = "pen.priceChanged"

local function whole(v: unknown): boolean
	return type(v) == "number" and v == v and math.abs(v) ~= math.huge and math.floor(v) == v
end

function CoatMath.def(coat: any): any?
	return if whole(coat) then COATS[coat] else nil
end

function CoatMath.inBag(bag: any, coat: number): number
	local count = if type(bag) == "table" then bag[coat] else nil
	return if whole(count) and count > 0 then count else 0
end

function CoatMath.open(coat: any, biome: any): boolean
	local def = CoatMath.def(coat)
	return def ~= nil and whole(biome) and biome >= def.zone
end

function CoatMath.decision(pen: any, bag: any, biome: any, itemId: any, coat: any, expectedPrice: any): (Change?, string?)
	if not whole(itemId) or not whole(coat) or coat < 0 or coat > CoatMath.COUNT or not whole(expectedPrice) then
		return nil, CODE_INVALID
	end
	local item = PenMath.find(pen, itemId)
	if item == nil then
		return nil, CODE_NOT_OWNED
	end
	if item.coat == coat then
		return nil, CODE_SAME
	end
	local fromBag = coat > 0 and CoatMath.inBag(bag, coat) > 0
	local price = 0
	if coat > 0 and not fromBag then
		if not CoatMath.open(coat, biome) then
			return nil, CODE_LOCKED
		end
		price = COATS[coat].price
	end
	if expectedPrice ~= price then
		return nil, CODE_PRICE
	end
	return { coat = coat, price = price, fromBag = fromBag }, nil
end

function CoatMath.zoneGift(from: number, to: number): { number }
	local list: { number } = {}
	for coat, def in COATS do
		if def.zone >= FIRST_REWARD_ZONE and def.zone > from and def.zone <= to then
			table.insert(list, coat)
		end
	end
	return list
end

return CoatMath
