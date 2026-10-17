--!strict
-- Config/ValidateFood: the checks of Config.Economy.Food (food and levels, pens3 phase 9, 2026-10-17). Apart from
-- Config/init (Roblox's 200,000-character Source limit): PenService.init runs it and stops with an error on any
-- problem. Pure; shared.
-- validate(config) -> { string }: the problems as text (an empty list = valid). `config` = a table with Config's
-- Economy section (Food, Pen.maxLevel and maxCoins) (Config itself or a test's copy). Checks:
--   * base is a number > 0, growth a number > 1;
--   * levelsPerBiome is a whole number in [1, Pen.maxLevel];
--   * pieces is a non-empty list with pieces[i] = round(growth^(i - 1)) (the table follows the curve);
--   * foods is a non-empty list in band order: each a unique non-empty string id and a non-empty string nameKey, a
--     whole price in [1, maxCoins] within PRICE_SLACK of base × growth^(from - 1) (the first step of its band), whole
--     from < to with to - from <= #pieces; the first starts at level 1, each next one where the last ended, and the
--     last ends at Pen.maxLevel (every step from 1 to maxLevel has exactly one food);
--   * maxPieces is a whole number >= the biggest pieces entry; maxBuy a whole number in [1, maxPieces] whose price at
--     the dearest food stays within maxCoins (so a buy's price is always whole Coins).

local F = "Config.Economy.Food"
local PRICE_SLACK = 0.02 -- V2 rounds each price to 2 significant figures (Halo Puff 30B is 0.9% under its 30.3B)

local function isNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isWhole(v: unknown): boolean
	return isNumber(v) and math.floor(v :: number) == v
end

local function isText(v: unknown): boolean
	return type(v) == "string" and v ~= ""
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
	local c = if type(economy) == "table" then economy.Food else nil
	if type(c) ~= "table" then
		table.insert(problems, `{F} is missing`)
		return problems
	end
	local maxCoins = if isNumber(economy.maxCoins) then economy.maxCoins else 0 -- none: every price fails
	local pen = if type(economy.Pen) == "table" then economy.Pen else {}
	local maxLevel = if isWhole(pen.maxLevel) then pen.maxLevel else 0

	local base, growth = c.base, c.growth
	local curve = isNumber(base) and base > 0 and isNumber(growth) and growth > 1
	expect(isNumber(base) and base > 0, `{F}.base must be a number > 0 (got {show(base)})`)
	expect(isNumber(growth) and growth > 1, `{F}.growth must be a number > 1 (got {show(growth)})`)
	expect(
		isWhole(c.levelsPerBiome) and c.levelsPerBiome >= 1 and c.levelsPerBiome <= maxLevel,
		`{F}.levelsPerBiome must be a whole number in [1, Pen.maxLevel] (got {show(c.levelsPerBiome)})`
	)

	local pieces = if type(c.pieces) == "table" then c.pieces else {}
	local biggest = 0
	expect(#pieces > 0, `{F}.pieces must be a non-empty list`)
	for i, count in pieces do
		local want = if curve then math.floor(growth ^ (i - 1) + 0.5) else nil
		expect(
			isWhole(count) and count == want,
			`{F}.pieces[{i}] must be round(growth^{i - 1}) = {show(want)} (got {show(count)})`
		)
		if isNumber(count) then
			biggest = math.max(biggest, count)
		end
	end

	local list = if type(c.foods) == "table" then c.foods else {}
	expect(#list > 0, `{F}.foods must be a non-empty list`)
	local seen: { [string]: boolean } = {}
	local dearest = 0
	local reach = 1 -- the level the next band must start at
	for i, food in list do
		local p = `{F}.foods[{i}]`
		if type(food) ~= "table" then
			table.insert(problems, `{p} must be a table`)
			continue
		end
		expect(isText(food.id), `{p}.id must be a non-empty string (got {show(food.id)})`)
		expect(not (isText(food.id) and seen[food.id]), `{F}.foods lists {show(food.id)} twice`)
		if isText(food.id) then
			seen[food.id] = true
		end
		expect(isText(food.nameKey), `{p}.nameKey must be a non-empty string (got {show(food.nameKey)})`)
		local from, to = food.from, food.to
		expect(
			isWhole(from) and from == reach,
			`{p}.from must be {reach}, where the last band ended (got {show(from)})`
		)
		expect(
			isWhole(to) and isWhole(from) and to > from and to - from <= #pieces,
			`{p}.to must be a whole number in [from + 1, from + #pieces] (got {show(to)})`
		)
		local price = food.price
		local first = if curve and isNumber(from) then base * growth ^ (from - 1) else nil
		expect(
			isWhole(price)
				and price >= 1
				and price <= maxCoins
				and first ~= nil
				and math.abs(price / first - 1) <= PRICE_SLACK,
			`{p}.price must be whole Coins near base × growth^(from - 1) = {show(first)} (got {show(price)})`
		)
		if isNumber(price) then
			dearest = math.max(dearest, price)
		end
		reach = if isWhole(to) then to else reach
	end
	expect(reach == maxLevel, `{F}.foods must end at Pen.maxLevel {maxLevel} (the last ends at {reach})`)

	expect(
		isWhole(c.maxPieces) and c.maxPieces >= math.max(1, biggest),
		`{F}.maxPieces must be a whole number >= the biggest pieces entry (got {show(c.maxPieces)})`
	)
	expect(
		isWhole(c.maxBuy)
			and c.maxBuy >= 1
			and isNumber(c.maxPieces)
			and c.maxBuy <= c.maxPieces
			and c.maxBuy * dearest <= maxCoins,
		`{F}.maxBuy must be a whole number in [1, maxPieces] with maxBuy × the dearest price within maxCoins (got {show(
			c.maxBuy
		)})`
	)
	return problems
end
