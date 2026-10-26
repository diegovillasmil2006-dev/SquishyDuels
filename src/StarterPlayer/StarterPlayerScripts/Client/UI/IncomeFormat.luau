--!strict
-- IncomeFormat (client only, pure). INCOME step 2 (2026-10-26; owner "Yes, take a snapshot and build INCOME step 2"):
-- what the shop's INCOME tab shows (ShopController), as plain data in the gear card's shape (GearFormat.Card), so the
-- tab reuses the gear cards. Numbers: Shared/PenMath (Config.Economy.Income); texts: Strings.income; tile colours:
-- Config/GearShop.income.
--   cards(pen, coins, busyLine?) -> { Card }  SQUISHY COINS then ALL EARNINGS, each for its NEXT level: its name, the
--                                             level it buys (the tile's number; the last at max), no stars, its line
--                                             (the boost now -> after), its price and colour token; state buy /
--                                             needCoins (missing = the Coins still short; no Coins known = none) /
--                                             busy (busyLine's buy on its way) / max (every level bought: no price,
--                                             Strings.income.maxLine)
--   multText(x) -> string                     a boost with 2 decimals, no trailing zeros ("1", "1.07", "1.1")

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GearShop = require(Shared.Config.GearShop)
local PenMath = require(Shared.PenMath)
local Strings = require(Shared.Strings)

local GearFormat = require(script.Parent.GearFormat)

-- Constants

local INCOME = Config.Economy.Income
local S = Strings.income
local LINES = { "coins", "all" }

-- Module table

local IncomeFormat = {}

-- Public

function IncomeFormat.multText(x: number): string
	local text = string.format("%.2f", x)
	text = string.gsub(text, "0+$", "")
	return (string.gsub(text, "%.$", ""))
end

function IncomeFormat.cards(pen: any, coins: number?, busyLine: string?): { GearFormat.Card }
	local have = if type(coins) == "number" and coins == coins then coins else 0
	local list: { GearFormat.Card } = {}
	for _, line in LINES do
		local def = INCOME[line]
		local levels = #def.prices
		local level = PenMath.incomeLevel(pen, line)
		local max = level >= levels
		local price = PenMath.incomePrice(line, level + 1)
		local state: GearFormat.CardState = if max
			then "max"
			elseif busyLine == line then "busy"
			elseif have >= (price :: number) then "buy"
			else "needCoins"
		table.insert(list, {
			line = line,
			name = (S.names :: any)[line],
			tier = math.min(level + 1, levels),
			stars = 0,
			steps = 0,
			desc = if max
				then S.maxLine
				else Strings.format(
					(S.lines :: any)[line],
					{
						now = IncomeFormat.multText(def.boost ^ level),
						next = IncomeFormat.multText(def.boost ^ (level + 1)),
					}
				),
			price = price,
			state = state,
			missing = if state == "needCoins" then (price :: number) - have else 0,
			color = (GearShop.income.colors :: any)[line],
		})
	end
	return list
end

return IncomeFormat
