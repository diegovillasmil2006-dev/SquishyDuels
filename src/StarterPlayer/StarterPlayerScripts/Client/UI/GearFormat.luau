--!strict
-- GearFormat (client only, pure). Gear step 3 (2026-10-26; owner "Yes, build step 3 like that"): what the shop's GEAR
-- tab shows (ShopController) and the throw's trail tier (HighwayThrowController), as plain data. Numbers:
-- Shared/GearMath (Config/Gear); texts: Strings.gear; zone colours: WorldLayout.Highway.biomes[tier].nameColor.
--   cards(gear, coins, busyLine?) -> { Card }  one card a GearMath line, in GearMath.LINES order, for its NEXT step:
--                                             the piece's name (with "★n" on a star step), its tier, the stars bought
--                                             in that tier and the tier's steps (the tile's pips; armor: none), its
--                                             line, its price and the tier's zone colour token; state buy /
--                                             needCoins (missing = the Coins still short; no Coins known = none) /
--                                             busy (busyLine's buy on its way) / max (all bought: the last piece, no
--                                             price, Strings.gear.maxLine)
--   powerText(gear) -> string                  "x" and the gear's throw power multiplier (Format.power)
--   trailTier(gear) -> number                  the held launcher's tier, 0 without one

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local GearMath = require(Shared.GearMath)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

-- Types

export type CardState = "buy" | "needCoins" | "busy" | "max"

export type Card = {
	line: string,
	name: string,
	tier: number,
	stars: number,
	steps: number,
	desc: string,
	price: number?,
	state: CardState,
	missing: number,
	color: string, -- a Palette token
}

-- Constants

local G = Config.Economy.Gear
local S = Strings.gear
local BIOMES = WorldLayout.Highway.biomes

-- Module table

local GearFormat = {}

-- Private

-- A power step's multiplier as text: "2" for a 4-step tier, "1.4" for an 8-step one.
local function stepText(tier: number): string
	local x = G.tierPower ^ (1 / G.tierSteps[tier])
	return if x == math.floor(x) then tostring(math.floor(x)) else string.format("%.1f", x)
end

local function card(gear: any, line: string, coins: number, busyLine: string?): Card
	local last = GearMath.maxStep(line) :: number
	local bought = GearMath.steps(gear, line)
	local max = bought >= last
	local step = if max then last else bought + 1
	local armor = line == "armor"
	local tier = if armor then step else GearMath.tierOf(step)
	local before = 0
	for t = 1, tier - 1 do
		before += G.tierSteps[t]
	end
	local index = if armor then 0 else step - 1 - before -- 0 = the tier's base piece
	local steps = if armor then 0 else G.tierSteps[tier]
	local base = (S.names :: any)[line][tier]
	local price = if max then nil else GearMath.price(line, step)
	local state: CardState = if max
		then "max"
		elseif busyLine == line then "busy"
		elseif coins >= (price :: number) then "buy"
		else "needCoins"
	return {
		line = line,
		name = if index > 0 then Strings.format(S.star, { name = base, n = index }) else base,
		tier = tier,
		stars = if max then steps else index,
		steps = steps,
		desc = if max
			then S.maxLine
			elseif armor then S.armorLine
			else Strings.format(S.powerLine, { x = stepText(tier) }),
		price = price,
		state = state,
		missing = if state == "needCoins" then (price :: number) - coins else 0,
		color = BIOMES[tier].nameColor,
	}
end

-- Public

function GearFormat.cards(gear: any, coins: number?, busyLine: string?): { Card }
	local have = if type(coins) == "number" and coins == coins then coins else 0
	local list: { Card } = {}
	for _, line in GearMath.LINES do
		table.insert(list, card(gear, line, have, busyLine))
	end
	return list
end

function GearFormat.powerText(gear: any): string
	return "x" .. Format.power(GearMath.multiplier(gear))
end

function GearFormat.trailTier(gear: any): number
	return GearMath.tierOf(GearMath.steps(gear, "held"))
end

return GearFormat
