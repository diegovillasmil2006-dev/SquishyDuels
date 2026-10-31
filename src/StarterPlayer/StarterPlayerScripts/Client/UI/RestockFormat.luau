--!strict
-- RestockFormat (client only, pure). 2026-10-31 shop restock (owner "Yes, build it"; [P] a stand-in until Diego draws
-- it): what the shop's RESTOCK tab shows (ShopController), in the gear card's shape (GearFormat.Card), so the tab reuses
-- the gear cards. Offers and stock: Shared/EventSchedule (Config.Events.ShopRestock); texts: Strings.event; tile
-- colours: Config/GearShop.restock.
--   cards(t, stockText, coins, busyLine?, bought) -> { Card }  the live restock's offers (none when no restock is
--                                    live): the squishy's picture on the tile, "Golden <name>" / "Rainbow <name>" /
--                                    the name, the line (what it earns or the discount, then the stock left), the price;
--                                    state max (SOLD OUT, or BOUGHT when bought[slot]) / busy / needCoins / buy
--   waitText(t) -> string            "Next restock in 12:00. ..." while no restock is live

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local EventSchedule = require(Shared.EventSchedule)
local Format = require(Shared.Util.Format)
local GearShop = require(Shared.Config.GearShop)
local Strings = require(Shared.Strings)
local EVENTS = require(Shared.Config.Events)

local GearFormat = require(script.Parent.GearFormat)

-- Constants

local S = Strings.event
local COLORS = GearShop.restock.colors

-- Module table

local RestockFormat = {}

-- Public

function RestockFormat.cards(
	t: number,
	stockText: unknown,
	coins: number?,
	busyLine: string?,
	bought: { [number]: boolean }
): { GearFormat.Card }
	local index = EventSchedule.restockAt(t)
	if index == nil then
		return {}
	end
	local offers = EventSchedule.restockOffers(index)
	local left = EventSchedule.stockLeft(stockText, index, offers)
	local have = if type(coins) == "number" and coins == coins then coins else 0
	local list: { GearFormat.Card } = {}
	for slot, offer in offers do
		local def = Catalog.get(offer.squishy)
		local base = if def then Strings.resolve(def.nameKey) or offer.squishy else offer.squishy
		local line = tostring(slot)
		local soldOut = left[slot] <= 0
		local state: GearFormat.CardState = if bought[slot] or soldOut
			then "max"
			elseif busyLine == line then "busy"
			elseif have >= offer.price then "buy"
			else "needCoins"
		local desc = if offer.deal == "rare"
			then Strings.format(S.restockRareLine, {
				off = math.round(EVENTS.ShopRestock.rareDiscount * 100),
				left = left[slot],
			})
			else Strings.format(
				if offer.deal == "rainbow" then S.restockRainbowLine else S.restockGoldenLine,
				{ left = left[slot] }
			)
		table.insert(list, {
			line = line,
			name = if offer.deal == "golden"
				then Strings.format(S.restockGolden, { name = base })
				elseif offer.deal == "rainbow" then Strings.format(S.restockRainbow, { name = base })
				else base,
			tier = 0,
			stars = 0,
			steps = 0,
			desc = desc,
			price = offer.price,
			state = state,
			missing = if state == "needCoins" then offer.price - have else 0,
			color = COLORS[offer.deal],
			squishy = offer.squishy,
			maxText = if bought[slot] then S.restockBought else S.restockSoldOut,
		})
	end
	return list
end

function RestockFormat.waitText(t: number): string
	return Strings.format(S.restockNext, { time = Format.clock(EventSchedule.nextStart(t, "shopRestock") - t) })
end

return RestockFormat
