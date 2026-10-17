--!strict
-- ValidateFood_Test: unit tests for ReplicatedStorage.Shared.Config.ValidateFood (food and levels, pens3 phase 9).
-- Server only (ServerStorage.UnitTest). Pure: broken copies of Config.Economy.Food.
-- Contract (Config/ValidateFood header; work/pens3/PLAN.md "PHASE 9"; V2:214-224, V3:169): the shipped Config is
-- valid and holds V2's food table (7 foods, 400 .. 30B a piece, the bands 1-10 .. 60-70, the pieces 1, 1, 2, 3, 3, 5,
-- 6, 9, 12, 16, base 400, growth 1.36, 10 levels a biome); a missing section is one problem; each broken value is
-- reported by name (the curve: base, growth, a piece count off round(growth^(i - 1)), a price off the first step of
-- its band; the bands: a gap, a wrong start or end, longer than the piece table; ids and names; the caps).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local validate = t.requireShared("Config/ValidateFood")

	-- A Config-shaped copy with Economy.Food changed.
	local function broken(changes: { [string]: any }): any
		local food = table.clone(Config.Economy.Food)
		for key, value in changes do
			food[key] = value
		end
		return { Economy = { maxCoins = Config.Economy.maxCoins, Pen = Config.Economy.Pen, Food = food } }
	end

	-- Config's food list with the food at `index` changed.
	local function foods(index: number, changes: { [string]: any }): any
		local list = table.clone(Config.Economy.Food.foods)
		local one = table.clone(list[index])
		for key, value in changes do
			one[key] = value
		end
		list[index] = one
		return list
	end

	local function mentions(problems: { string }, text: string): boolean
		for _, problem in problems do
			if string.find(problem, text, 1, true) then
				return true
			end
		end
		return false
	end

	t.test("the shipped Config is valid and holds V2's food table", function()
		expect.deepEqual(validate(Config), {})
		local food = Config.Economy.Food
		expect.equal(food.base, 400)
		expect.equal(food.growth, 1.36)
		expect.equal(food.levelsPerBiome, 10)
		expect.deepEqual(food.pieces, { 1, 1, 2, 3, 3, 5, 6, 9, 12, 16 })
		local rows: { string } = {}
		for _, f in food.foods do
			table.insert(rows, `{f.id} {f.price} {f.from}-{f.to}`)
		end
		expect.deepEqual(rows, {
			"candy_drop 400 1-10",
			"butter_bun 6400 10-20",
			"boba_pearl_pop 138000 20-30",
			"frosty_scoop 3000000 30-40",
			"lava_truffle 65000000 40-50",
			"prism_tart 1400000000 50-60",
			"halo_puff 30000000000 60-70",
		})
		expect.equal(food.foods[#food.foods].to, Config.Economy.Pen.maxLevel)
	end)

	t.test("a missing section is one problem", function()
		local problems = validate({ Economy = { maxCoins = 1 } })
		expect.equal(#problems, 1)
		expect.truthy(mentions(problems, "Config.Economy.Food is missing"))
		expect.equal(#validate(nil), 1)
	end)

	t.test("each broken value is reported by name", function()
		local cases: { { changes: { [string]: any }, field: string } } = {
			{ changes = { base = 0 }, field = "base" },
			{ changes = { growth = 1 }, field = "growth" },
			{ changes = { growth = 0 / 0 }, field = "growth" },
			{ changes = { levelsPerBiome = 0 }, field = "levelsPerBiome" },
			{ changes = { levelsPerBiome = 1.5 }, field = "levelsPerBiome" },
			{ changes = { levelsPerBiome = 71 }, field = "levelsPerBiome" }, -- above Pen.maxLevel
			{ changes = { pieces = {} }, field = "pieces" },
			{ changes = { pieces = { 1, 1, 2, 3, 3, 5, 6, 9, 12, 15 } }, field = "pieces[10]" }, -- off the curve
			{ changes = { foods = {} }, field = "foods" },
			{ changes = { foods = foods(2, { id = "candy_drop" }) }, field = "twice" },
			{ changes = { foods = foods(2, { id = "" }) }, field = "foods[2].id" },
			{ changes = { foods = foods(1, { nameKey = 5 }) }, field = "foods[1].nameKey" },
			{ changes = { foods = foods(3, { price = 150_000 }) }, field = "foods[3].price" }, -- 9% off its first step
			{ changes = { foods = foods(1, { price = 0 }) }, field = "foods[1].price" },
			{ changes = { foods = foods(1, { price = 400.5 }) }, field = "foods[1].price" },
			{ changes = { foods = foods(2, { from = 11 }) }, field = "foods[2].from" }, -- a gap after Candy Drop
			{ changes = { foods = foods(1, { from = 2 }) }, field = "foods[1].from" }, -- level 1 has no food
			{ changes = { foods = foods(7, { to = 80 }) }, field = "foods[7].to" }, -- longer than the piece table
			{ changes = { foods = foods(7, { to = 60 }) }, field = "foods[7].to" }, -- an empty band
			{ changes = { foods = foods(7, { to = 69 }) }, field = "maxLevel" }, -- Lv 69 -> 70 has no food
			{ changes = { maxPieces = 0 }, field = "maxPieces" },
			{ changes = { maxPieces = 2.5 }, field = "maxPieces" },
			{ changes = { maxBuy = 0 }, field = "maxBuy" },
			{ changes = { maxBuy = Config.Economy.Food.maxPieces + 1 }, field = "maxBuy" },
		}
		for _, case in cases do
			local problems = validate(broken(case.changes))
			if not mentions(problems, case.field) then
				error(`expected a problem naming {case.field}, got: {table.concat(problems, "; ")}`)
			end
		end
		-- A buy of maxBuy of the dearest food must stay within maxCoins (a buy's price is whole Coins).
		local dear = broken({ maxPieces = 10 ^ 9, maxBuy = 10 ^ 9 })
		expect.truthy(mentions(validate(dear), "maxBuy"))
	end)
end
