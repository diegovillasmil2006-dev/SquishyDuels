--!strict
-- IncomeFormat_Test: unit tests for StarterPlayer.StarterPlayerScripts.Client.UI.IncomeFormat (INCOME step 2,
-- 2026-10-26: the shop's INCOME tab; owner "Yes, take a snapshot and build INCOME step 2"). Pure.
-- Contract:
--   * cards(pen, coins, busyLine?): one card a line (coins = SQUISHY COINS, all = ALL EARNINGS) in the gear card's
--     shape for the NEXT level: its name, the level it buys (the tile's number; 20 at max), no stars, its line ("x1.07
--     -> x1.14 squishy coins": the boost now and after), its price (Config.Economy.Income), its colour token and the
--     state: buy / needCoins (with the Coins missing) / busy (a buy of that line on its way) / max (every level bought:
--     no price, Strings.income.maxLine);
--   * multText(x): "1", "1.07", "1.1" (2 decimals, no trailing zeros).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local IncomeFormat = t.requireClient("UI/IncomeFormat")
	local Strings = t.requireShared("Strings")
	local Palette = t.requireShared("Art/Palette")
	local Config = t.requireShared("Config")
	local INCOME = Config.Economy.Income
	local S = Strings.income

	local function pen(coins: number?, all: number?): any
		return { spots = 3, nextId = 1, items = {}, income = { coins = coins or 0, all = all or 0 } }
	end

	t.test("multText: 2 decimals without trailing zeros", function()
		expect.equal(IncomeFormat.multText(1), "1")
		expect.equal(IncomeFormat.multText(1.07), "1.07")
		expect.equal(IncomeFormat.multText(1.05 ^ 2), "1.1")
		expect.equal(IncomeFormat.multText(1.07 ^ 20), "3.87")
	end)

	t.test(
		"cards: SQUISHY COINS then ALL EARNINGS, level 1 first, its price and line; buy when the Coins reach",
		function()
			local cards = IncomeFormat.cards(pen(), 600_000)
			expect.equal(#cards, 2)
			local coins, all = cards[1], cards[2]
			expect.equal(coins.line, "coins")
			expect.equal(coins.name, S.names.coins)
			expect.equal(coins.tier, 1)
			expect.equal(coins.stars, 0)
			expect.equal(coins.steps, 0)
			expect.equal(coins.desc, Strings.format(S.lines.coins, { now = "1", next = "1.07" }))
			expect.equal(coins.price, INCOME.coins.prices[1])
			expect.equal(coins.state, "buy")
			expect.equal(coins.missing, 0)
			expect.equal(all.line, "all")
			expect.equal(all.name, S.names.all)
			expect.equal(all.desc, Strings.format(S.lines.all, { now = "1", next = "1.05" }))
			expect.equal(all.price, INCOME.all.prices[1])
			expect.equal(all.state, "needCoins")
			expect.equal(all.missing, INCOME.all.prices[1] - 600_000)
			for _, card in cards do
				expect.equal(typeof((Palette :: any)[card.color]), "Color3")
			end
		end
	)

	t.test("cards: the levels bought move each card on; busy while its buy is on its way", function()
		local cards = IncomeFormat.cards(pen(1, 2), 0, "coins")
		expect.equal(cards[1].tier, 2)
		expect.equal(cards[1].price, INCOME.coins.prices[2])
		expect.equal(cards[1].desc, Strings.format(S.lines.coins, { now = "1.07", next = "1.14" }))
		expect.equal(cards[1].state, "busy")
		expect.equal(cards[1].missing, 0)
		expect.equal(cards[2].tier, 3)
		expect.equal(cards[2].desc, Strings.format(S.lines.all, { now = "1.1", next = "1.16" }))
		expect.equal(cards[2].state, "needCoins")
	end)

	t.test(
		"cards: every level bought is MAX (no price, the max line); no pen or no Coins read as level 0 and 0",
		function()
			local levels = #INCOME.coins.prices
			local max = IncomeFormat.cards(pen(levels, 0), 1e30)[1]
			expect.equal(max.state, "max")
			expect.equal(max.price, nil)
			expect.equal(max.tier, levels)
			expect.equal(max.desc, S.maxLine)
			expect.equal(max.missing, 0)
			local none = IncomeFormat.cards(nil, 0 / 0)
			expect.equal(none[1].tier, 1)
			expect.equal(none[1].state, "needCoins")
			expect.equal(none[1].missing, INCOME.coins.prices[1])
		end
	)
end
