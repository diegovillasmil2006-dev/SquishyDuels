--!strict
-- CatchMath: the throw catches squishies (rework Option A, owner 2026-11-12 "Yes, build it"; Config.Economy.Catch has
-- the numbers and the why). Shared (HighwayService decides, the client draws the CATCH meter). Pure; no instances.
--
-- API:
--   CatchMath.boxFor(zone)            -> string?: the box the zone's wild squishies come from (zones 1-8), else nil
--   CatchMath.zoneOf(studs, reached)  -> 1..7: the landing's zone, never past `reached` (the saved biome after the
--                                        throw; a bounce is no shortcut); a broken `reached` counts as 1
--   CatchMath.sellValue(boxId)        -> number: a catch's expected sell price (the box's weights x each squishy's plain
--                                        PenMath.sellPrice); 0 for an unknown box
--   CatchMath.chance(coins, boxId)    -> 0..maxChance: share x coins / the box's price in [minChance, maxChance], then at
--                                        most coins / sellValue (a catch never sells for more than the throw paid); 0
--                                        for no Coins or an unknown box
--   CatchMath.need(chance)            -> whole number: throws without a catch until a sure one (ceil(pity / chance));
--                                        a huge number for no chance
--   CatchMath.decide(miss, chance, roll) -> boolean: roll (0..1) under the chance, or miss + 1 reaching need(chance)
--   CatchMath.pick(boxId, roll)       -> string?: the squishy at `roll` (0..1) of the box's weights, in its order
--   CatchMath.have(owned, boxId)      -> (have, total): the box's kinds the `owned` map holds, and all its kinds
--   CatchMath.validate(config)        -> { string }: what is wrong with a Catch config (empty = fine)

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Boxes = require(script.Parent.Boxes)
local Config = require(script.Parent.Config)
local HighwayMath = require(script.Parent.HighwayMath)
local PenMath = require(script.Parent.PenMath)

-- Constants

local C = Config.Economy.Catch
local ZONES = #Config.Economy.Highway.starts -- 7: the Golden Gates lie in the last zone
local NEVER = 1e9 -- need() for no chance at all

-- Module table

local CatchMath = {}

-- Private

local sellCache: { [string]: number } = {}

local function isFinite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Public

function CatchMath.boxFor(zone: unknown): string?
	if type(zone) ~= "number" or zone % 1 ~= 0 then
		return nil
	end
	return C.zoneBoxes[zone]
end

function CatchMath.zoneOf(studs: number, reached: unknown): number
	local cap = if isFinite(reached) then math.max(1, math.floor(reached :: number)) else 1
	return math.min(HighwayMath.biomeAt(studs), cap, ZONES)
end

function CatchMath.sellValue(boxId: string): number
	local cached = sellCache[boxId]
	if cached ~= nil then
		return cached
	end
	local box = Boxes.get(boxId)
	if box == nil then
		return 0
	end
	local sum = 0
	for _, item in box.items do
		sum += PenMath.sellPrice({ kind = item.id, form = 0, coat = 0, level = 1, mut = 0 }) * item.weight
	end
	local value = sum / Boxes.WeightTotal
	sellCache[boxId] = value
	return value
end

function CatchMath.chance(coins: number, boxId: string): number
	local box = Boxes.get(boxId)
	if not isFinite(coins) or coins <= 0 or box == nil or not isFinite(box.cost) or (box.cost :: number) <= 0 then
		return 0
	end
	local chance = math.clamp(C.share * coins / (box.cost :: number), C.minChance, C.maxChance)
	local sell = CatchMath.sellValue(boxId)
	if sell > 0 then
		chance = math.min(chance, coins / sell)
	end
	return chance
end

function CatchMath.need(chance: number): number
	if not isFinite(chance) or chance <= 0 then
		return NEVER
	end
	return math.ceil(C.pity / chance - 1e-9)
end

function CatchMath.decide(miss: number, chance: number, roll: number): boolean
	if not isFinite(chance) or chance <= 0 then
		return false
	end
	return roll < chance or (if isFinite(miss) then miss else 0) + 1 >= CatchMath.need(chance)
end

function CatchMath.pick(boxId: string, roll: number): string?
	local box = Boxes.get(boxId)
	if box == nil or #box.items == 0 then
		return nil
	end
	local target = math.clamp(if isFinite(roll) then roll else 0, 0, 1) * Boxes.WeightTotal
	local sum = 0
	for _, item in box.items do
		sum += item.weight
		if target < sum then
			return item.id
		end
	end
	return box.items[#box.items].id
end

function CatchMath.have(owned: any, boxId: string): (number, number)
	local box = Boxes.get(boxId)
	if box == nil then
		return 0, 0
	end
	local have = 0
	for _, item in box.items do
		if type(owned) == "table" and owned[item.id] ~= nil then
			have += 1
		end
	end
	return have, #box.items
end

function CatchMath.validate(config: any): { string }
	local problems: { string } = {}
	local P = "Config.Economy.Catch"
	if type(config) ~= "table" then
		return { `{P} must be a table` }
	end
	local boxes = config.zoneBoxes
	if type(boxes) ~= "table" or #boxes ~= ZONES + 1 then
		table.insert(problems, `{P}.zoneBoxes must list a box for each zone and the Golden Gates`)
	end
	for zone, id in if type(boxes) == "table" then boxes else {} do
		local box = Boxes.get(id)
		if box == nil or not isFinite(box.cost) then
			table.insert(problems, `{P}.zoneBoxes[{zone}] = {tostring(id)} is no box sold for Coins`)
		end
	end
	if not isFinite(config.share) or config.share <= 0 then
		table.insert(problems, `{P}.share must be above 0`)
	end
	local lo, hi = config.minChance, config.maxChance
	if not (isFinite(lo) and isFinite(hi) and lo > 0 and lo <= hi and hi <= 1) then
		table.insert(problems, `{P}.minChance and maxChance must be 0 < min <= max <= 1`)
	end
	if not isFinite(config.pity) or config.pity < 1 then
		table.insert(problems, `{P}.pity must be at least 1`)
	end
	return problems
end

return CatchMath
