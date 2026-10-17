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
--   * awayRate (phase 4: the share of the saved pen rate paid for time away) is a number in [0, 1].

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
	return problems
end
