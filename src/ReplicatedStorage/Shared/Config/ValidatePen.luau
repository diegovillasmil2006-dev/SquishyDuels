--!strict
-- Config/ValidatePen: the checks of Config.Economy.Pen (the pen, pens3 phase 1, 2026-10-17). Apart from Config/init
-- (Roblox's 200,000-character Source limit): PenService.init runs it and stops with an error on any problem (the pen
-- is the game's Coin source, so a broken table must never ship). Pure; shared.
-- validate(config) -> { string }: the problems as text (an empty list = valid). `config` = a table with Config's
-- Economy section (Pen and maxCoins) (Config itself or a test's copy). Checks:
--   * startSpots and maxSpots are whole numbers with 1 <= startSpots < maxSpots;
--   * spotPrices has exactly the keys startSpots + 1 .. maxSpots, each a whole number of Coins in [1, maxCoins], strictly
--     rising (so a retried buy always carries a wrong price and is never charged twice);
--   * formMult and coatMult are non-empty lists of positive numbers that never fall;
--   * coinsPerPower, levelGain, minSqueezeValue, tickSeconds and maxTickSeconds are positive numbers (levelGain >= 1);
--   * maxLevel is a whole number >= 1; toyBoxMax a whole number >= 0; placedMax a whole number >= maxSpots;
--   * buyCooldownSeconds and signHoldSeconds are numbers >= 0;
--   * awayRate (phase 4: the share of the saved pen rate paid for time away) is a number in [0, 1];
--   * phase 5: giftQueueMax a whole number >= 0; welcomePrice a table of rarity -> whole Coins >= 1, each rarity with
--     at least one squishy sold in the shop and the price never above any of their shopPrices (so a Welcome price
--     also stays under every Pricing.ceiling); frogGift {kind = a Catalog squishy, seconds = a number >= 0};
--   * phase 7: sellPrice has exactly the Rarity.ORDER rarities, each whole Coins >= 1, below the lowest price that
--     rarity is sold for (its shopPrices and its Welcome price: buying to sell always loses) and, times the biggest
--     sellFormMult, within maxCoins; sellFormMult one whole number >= 1 per form (#formMult), never falling;
--     sellMaxIds a whole number >= 1; sellHold {form in [0, #formMult - 1], level in [1, maxLevel], rarity a
--     Rarity}; buyBackSeconds a number > 0; buyBackMax a whole number >= 1;
--   * phase 11 (the shelf): shelfMaxRows and shelfRowSpots whole numbers >= 1, shelfStartRows a whole number in [1,
--     shelfMaxRows]; placedMax = maxSpots + shelfMaxRows x shelfRowSpots + 1 (the pen, the shelf, the TOP spot);
--     shelfRowPrices has exactly the keys shelfStartRows + 1 .. shelfMaxRows, each whole Coins in [1, maxCoins],
--     strictly rising, and topPrice whole Coins in [1, maxCoins] above the last row's (bought last: a retried buy
--     always carries a wrong price and is never charged twice).

local Catalog = require(script.Parent.Parent.Catalog)
local Rarity = require(script.Parent.Parent.Rarity)

local P = "Config.Economy.Pen"
local POSITIVE = { "coinsPerPower", "levelGain", "minSqueezeValue", "tickSeconds", "maxTickSeconds" }
local NON_NEGATIVE = { "buyCooldownSeconds", "signHoldSeconds" }

local function isNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isWhole(v: unknown): boolean
	return isNumber(v) and math.floor(v :: number) == v
end

local function show(v: unknown): string
	return if type(v) == "string" then string.format("%q", v) else tostring(v)
end

return function(config: any): { string }
	local problems: { string } = {}
	local function expect(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end

	local economy = if type(config) == "table" then config.Economy else nil
	local c = if type(economy) == "table" then economy.Pen else nil
	if type(c) ~= "table" then
		table.insert(problems, `{P} is missing`)
		return problems
	end
	local maxCoins = if isNumber(economy.maxCoins) then economy.maxCoins else 0 -- none: every price fails

	local first, last = c.startSpots, c.maxSpots
	expect(isWhole(first) and first >= 1, `{P}.startSpots must be a whole number >= 1 (got {show(first)})`)
	expect(
		isWhole(last) and isWhole(first) and last > first,
		`{P}.maxSpots must be a whole number above startSpots (got {show(last)})`
	)

	local prices = c.spotPrices
	if type(prices) ~= "table" then
		table.insert(problems, `{P}.spotPrices must be a table`)
	elseif isWhole(first) and isWhole(last) then
		for key in prices do
			expect(
				isWhole(key) and key > first and key <= last,
				`{P}.spotPrices has a key {show(key)} outside {first + 1} .. {last}`
			)
		end
		local previous = 0
		for spot = first + 1, last do
			local price = prices[spot]
			local ok = isWhole(price) and price >= 1 and price <= maxCoins and price > previous
			expect(
				ok,
				`{P}.spotPrices[{spot}] must be a whole number of Coins in [1, maxCoins] above the spot before (got {show(
					price
				)})`
			)
			previous = if isNumber(price) then price else previous
		end
	end

	for _, field in { "formMult", "coatMult" } do
		local list = c[field]
		if type(list) ~= "table" or #list == 0 then
			table.insert(problems, `{P}.{field} must be a non-empty list`)
			continue
		end
		local previous = 0
		for index, mult in ipairs(list) do
			expect(
				isNumber(mult) and mult > 0 and mult >= previous,
				`{P}.{field}[{index}] must be a positive number, never below the one before (got {show(mult)})`
			)
			previous = if isNumber(mult) then mult else previous
		end
	end

	for _, field in POSITIVE do
		local v = c[field]
		expect(isNumber(v) and v > 0, `{P}.{field} must be a positive number (got {show(v)})`)
	end
	expect(not isNumber(c.levelGain) or c.levelGain >= 1, `{P}.levelGain must be at least 1 (a level never earns less)`)
	expect(isWhole(c.maxLevel) and c.maxLevel >= 1, `{P}.maxLevel must be a whole number >= 1 (got {show(c.maxLevel)})`)
	expect(
		isWhole(c.toyBoxMax) and c.toyBoxMax >= 0,
		`{P}.toyBoxMax must be a whole number >= 0 (got {show(c.toyBoxMax)})`
	)
	expect(
		isWhole(c.placedMax) and isWhole(last) and c.placedMax >= last,
		`{P}.placedMax must be a whole number >= maxSpots (got {show(c.placedMax)})`
	)
	for _, field in NON_NEGATIVE do
		local v = c[field]
		expect(isNumber(v) and v >= 0, `{P}.{field} must be a number >= 0 (got {show(v)})`)
	end
	local away = c.awayRate
	expect(isNumber(away) and away >= 0 and away <= 1, `{P}.awayRate must be a number in [0, 1] (got {show(away)})`)

	expect(
		isWhole(c.giftQueueMax) and c.giftQueueMax >= 0,
		`{P}.giftQueueMax must be a whole number >= 0 (got {show(c.giftQueueMax)})`
	)
	local welcome = c.welcomePrice
	if type(welcome) ~= "table" then
		table.insert(problems, `{P}.welcomePrice must be a table of rarity -> Coins`)
	else
		for rarity, price in welcome do
			local lowest = math.huge -- stays huge for a rarity nobody sells
			for _, def in Catalog.byRarity(rarity) do
				if def.shopPrice ~= nil then
					lowest = math.min(lowest, def.shopPrice)
				end
			end
			expect(
				isWhole(price) and price >= 1 and lowest < math.huge and price <= lowest,
				`{P}.welcomePrice.{tostring(rarity)} must be whole Coins >= 1 for a rarity sold in the shop, `
					.. `at most its lowest shopPrice (got {show(price)})`
			)
		end
	end
	local frog = c.frogGift
	if type(frog) ~= "table" then
		table.insert(problems, `{P}.frogGift must be a table with a kind and seconds`)
	else
		expect(Catalog.isValidId(frog.kind), `{P}.frogGift.kind must be a Catalog squishy (got {show(frog.kind)})`)
		expect(
			isNumber(frog.seconds) and frog.seconds >= 0,
			`{P}.frogGift.seconds must be a number >= 0 (got {show(frog.seconds)})`
		)
	end

	-- Pens3 phase 7: selling and the buy-back.
	local forms = if type(c.formMult) == "table" then #c.formMult else 0
	local mults = c.sellFormMult
	local topMult = 0
	if type(mults) ~= "table" or #mults ~= forms then
		table.insert(problems, `{P}.sellFormMult must be a list with one entry per form ({forms})`)
	else
		local previous = 1
		for index, mult in ipairs(mults) do
			expect(
				isWhole(mult) and mult >= previous,
				`{P}.sellFormMult[{index}] must be a whole number >= 1, never below the one before (got {show(mult)})`
			)
			previous = if isNumber(mult) then mult else previous
			topMult = math.max(topMult, if isNumber(mult) then mult else 0)
		end
	end
	local sells = c.sellPrice
	if type(sells) ~= "table" then
		table.insert(problems, `{P}.sellPrice must be a table of rarity -> Coins`)
	else
		for rarity in sells do
			expect(Rarity.isValid(rarity), `{P}.sellPrice.{tostring(rarity)} is not a rarity`)
		end
		for _, rarity in Rarity.ORDER do
			local price = sells[rarity]
			local lowest = if type(welcome) == "table" and isNumber(welcome[rarity]) then welcome[rarity] else math.huge
			for _, def in Catalog.byRarity(rarity) do
				if def.shopPrice ~= nil then
					lowest = math.min(lowest, def.shopPrice)
				end
			end
			expect(
				isWhole(price) and price >= 1 and price < lowest and price * topMult <= maxCoins,
				`{P}.sellPrice.{rarity} must be whole Coins >= 1, below the lowest price it is sold for and within `
					.. `maxCoins times the biggest sellFormMult (got {show(price)})`
			)
		end
	end
	expect(
		isWhole(c.sellMaxIds) and c.sellMaxIds >= 1,
		`{P}.sellMaxIds must be a whole number >= 1 (got {show(c.sellMaxIds)})`
	)
	local hold = c.sellHold
	if type(hold) ~= "table" then
		table.insert(problems, `{P}.sellHold must be a table with a form, a level and a rarity`)
	else
		expect(
			isWhole(hold.form) and hold.form >= 0 and hold.form <= forms - 1,
			`{P}.sellHold.form must be a form (got {show(hold.form)})`
		)
		expect(
			isWhole(hold.level) and hold.level >= 1 and isNumber(c.maxLevel) and hold.level <= c.maxLevel,
			`{P}.sellHold.level must be a level in [1, maxLevel] (got {show(hold.level)})`
		)
		expect(Rarity.isValid(hold.rarity), `{P}.sellHold.rarity must be a rarity (got {show(hold.rarity)})`)
	end
	expect(
		isNumber(c.buyBackSeconds) and c.buyBackSeconds > 0,
		`{P}.buyBackSeconds must be a number > 0 (got {show(c.buyBackSeconds)})`
	)
	expect(
		isWhole(c.buyBackMax) and c.buyBackMax >= 1,
		`{P}.buyBackMax must be a whole number >= 1 (got {show(c.buyBackMax)})`
	)

	-- Pens3 phase 11: the shelf rows and the TOP spot.
	local rows, row = c.shelfMaxRows, c.shelfRowSpots
	expect(isWhole(rows) and rows >= 1, `{P}.shelfMaxRows must be a whole number >= 1 (got {show(rows)})`)
	expect(isWhole(row) and row >= 1, `{P}.shelfRowSpots must be a whole number >= 1 (got {show(row)})`)
	local start = c.shelfStartRows
	expect(
		isWhole(start) and start >= 1 and isWhole(rows) and start <= rows,
		`{P}.shelfStartRows must be a whole number in [1, shelfMaxRows] (got {show(start)})`
	)
	if isWhole(last) and isWhole(rows) and isWhole(row) then
		expect(
			c.placedMax == last + rows * row + 1,
			`{P}.placedMax must be maxSpots + shelfMaxRows x shelfRowSpots + 1 (got {show(c.placedMax)})`
		)
	end
	local rowPrices = c.shelfRowPrices
	local previous = 0
	if type(rowPrices) ~= "table" then
		table.insert(problems, `{P}.shelfRowPrices must be a table`)
	elseif isWhole(start) and isWhole(rows) then
		for key in rowPrices do
			expect(
				isWhole(key) and key > start and key <= rows,
				`{P}.shelfRowPrices has a key {show(key)} outside {start + 1} .. {rows}`
			)
		end
		for index = start + 1, rows do
			local price = rowPrices[index]
			expect(
				isWhole(price) and price >= 1 and price <= maxCoins and price > previous,
				`{P}.shelfRowPrices[{index}] must be whole Coins in [1, maxCoins], above the last (got {show(price)})`
			)
			previous = if isNumber(price) then price else previous
		end
	end
	local top = c.topPrice
	expect(
		isWhole(top) and top >= 1 and top <= maxCoins and top > previous,
		`{P}.topPrice must be a whole number of Coins in [1, maxCoins] above the last row's (got {show(top)})`
	)
	return problems
end
