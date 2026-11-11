--!strict
-- GearFormat (client only, pure). Gear step 3 (2026-10-26; owner "Yes, build step 3 like that"): what the shop's GEAR
-- tab shows (ShopController) and the throw's trail tier (HighwayThrowController), as plain data. Numbers:
-- Shared/GearMath (Config/Gear); texts: Strings.gear; zone colours: WorldLayout.Highway.biomes[tier].nameColor.
--   cards(gear, coins, busyLine?) -> { Card }  one card a GearMath line, in GearMath.LINES order, for its NEXT step:
--                                             the piece's name (with "★n" on a star step), its tier, the stars bought
--                                             in that tier and the tier's steps (the tile's pips; armor: none), its
--                                             line, its price, the tier's zone colour token and its 3D model's
--                                             name (Shared/GearLooks.modelName, big job item 9); state buy /
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
local GearLooks = require(Shared.GearLooks) -- big job item 9: the models' names
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
	squishy: string?, -- 2026-10-31 RESTOCK tab: this squishy's picture on the tile instead of the tier number
	maxText: string?, -- 2026-10-31 RESTOCK tab: the "max" chip's text (SOLD OUT / BOUGHT), else Strings.gear.max
	icon: string?, -- 2026-11-01 INCOME tab: a picture (AssetTable key) on the tile, the tier in a badge
	model: string?, -- 2026-11-10 (big job item 9): the piece's 3D model on the tile (its name in SD_Gear), the tier in a badge
	golden: boolean?, -- 2026-11-10 (big job item 10): the pictured piece is Golden (its model shows gold)
}

-- Constants

local G = Config.Economy.Gear
local S = Strings.gear
local BIOMES = WorldLayout.Highway.biomes

-- Module table

local GearFormat = {}

GearFormat.BOX = "box" -- big job item 10: the Gear Box's card "line" (not a GearMath line)
local BOX_COLOR = "StickerGoldTop" -- its tile (a Palette token)
local BOX_ICON = "img.icon.gift" -- its tile's picture (an AssetTable key; a stand-in until the GEAR tab is designed)

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
	local desc = if max
		then S.maxLine
		elseif armor then S.armorLine
		else Strings.format(S.powerLine, { x = stepText(tier) })
	-- Big job item 10: the gear cards waiting on this line ride on the line's text; the pictured piece is Golden when
	-- the line's own piece is and the step shown belongs to it (a star of the same tier, or all bought).
	local waiting = GearMath.cards(gear, line)
	if waiting > 0 and not max then
		desc ..= " · " .. Strings.format(S.box.cards, { n = waiting, max = G.goldCards })
	end
	return {
		line = line,
		name = if index > 0 then Strings.format(S.star, { name = base, n = index }) else base,
		tier = tier,
		stars = if max then steps else index,
		steps = steps,
		desc = desc,
		price = price,
		state = state,
		missing = if state == "needCoins" then (price :: number) - coins else 0,
		color = BIOMES[tier].nameColor,
		model = GearLooks.modelName(line, tier),
		golden = GearMath.isGold(gear, line) and GearMath.tier(gear, line) == tier,
	}
end

-- Big job item 10: the name of the piece a gear card on `line` is for: the line's own piece (none yet: its first).
local function pieceName(gear: any, line: string): string
	return (S.names :: any)[line][math.max(1, GearMath.tier(gear, line))]
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

-- Big job item 10: the Gear Box as a 5th card of the GEAR page (line BOX): its price, and under its name who can get
-- the card: every line with room at the same chance (`random`: the account may buy paid random items), else the one
-- line the fixed order gives next. The pool and the price are GearMath's, the ones the server opens with. No line
-- with room = "max" (its chip reads Strings.gear.box.full).
function GearFormat.boxCard(gear: any, coins: number?, busyLine: string?, random: boolean): Card
	local have = if type(coins) == "number" and coins == coins then coins else 0
	local pool = GearMath.boxPool(gear)
	local price = GearMath.boxPrice(gear)
	local names: { string } = {}
	for _, line in pool do
		table.insert(names, pieceName(gear, line))
	end
	local full = #pool == 0
	local state: CardState = if full
		then "max"
		elseif busyLine == GearFormat.BOX then "busy"
		elseif have >= price then "buy"
		else "needCoins"
	local chance = if full then 0 else math.floor(100 / #pool + 0.5)
	-- Who gets the card: every line with room at the same chance (the lines without room read "Cards 3/3" on their
	-- own cards), or the one line the fixed order gives next.
	local who = if full
		then S.box.fullLine
		elseif not random or #pool == 1 then Strings.format(S.box.next, { name = names[1] })
		else Strings.format(S.box.odds, { chance = chance })
	return {
		line = GearFormat.BOX,
		name = S.box.name,
		tier = 0,
		stars = 0,
		steps = 0,
		-- one wrapped sentence (a line break made the card's text stack a line too tall: seen 2026-11-10)
		desc = Strings.format(S.box.line, { max = G.goldCards }) .. " " .. who,
		price = if full then nil else price,
		state = state,
		missing = if state == "needCoins" then price - have else 0,
		color = BOX_COLOR,
		icon = BOX_ICON,
		maxText = S.box.full,
	}
end

-- Big job item 10: what a Gear Box open says: the card's piece and the cards now waiting, or that it turned Golden.
function GearFormat.boxToast(gear: any, line: string, turned: boolean): string
	local name = pieceName(gear, line)
	if turned then
		return Strings.format(S.box.turned, { name = name })
	end
	return Strings.format(S.box.card, { name = name, n = GearMath.cards(gear, line), max = G.goldCards })
end

function GearFormat.powerText(gear: any): string
	return "x" .. Format.power(GearMath.multiplier(gear))
end

function GearFormat.trailTier(gear: any): number
	return GearMath.tierOf(GearMath.steps(gear, "held"))
end

return GearFormat
