--!strict
-- ValidatePen_Test: unit tests for ReplicatedStorage.Shared.Config.ValidatePen (the pen, pens3 phase 1). Server only
-- (ServerStorage.UnitTest). Pure: broken copies of Config.Economy.Pen.
-- Contract (Config/ValidatePen header): the shipped Config is valid and holds the plan's numbers; a missing section is
-- one problem; each broken value is reported by name.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local validate = t.requireShared("Config/ValidatePen")

	-- A Config-shaped copy with Economy.Pen changed.
	local function broken(changes: { [string]: any }): any
		local pen = table.clone(Config.Economy.Pen)
		for key, value in changes do
			pen[key] = value
		end
		return { Economy = { maxCoins = Config.Economy.maxCoins, Pen = pen } }
	end

	local function prices(changes: { [number]: any }): any
		local list = table.clone(Config.Economy.Pen.spotPrices)
		for key, value in changes do
			list[key] = value
		end
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

	t.test("the shipped Config is valid and holds the plan's numbers", function()
		expect.deepEqual(validate(Config), {})
		local pen = Config.Economy.Pen
		expect.equal(pen.startSpots, 3)
		expect.equal(pen.maxSpots, 12)
		expect.deepEqual(pen.spotPrices, {
			[4] = 1_500,
			[5] = 3_100,
			[6] = 4_650,
			[7] = 2_300_000,
			[8] = 2_100_000_000,
			[9] = 7_900_000_000,
			[10] = 63_000_000_000,
			[11] = 2_200_000_000_000,
			[12] = 5_600_000_000_000,
		})
		expect.deepEqual(pen.formMult, { 1, 2, 4 })
		expect.deepEqual(pen.coatMult, { 1, 1.5, 2, 3, 4, 6, 8, 12 })
		expect.equal(pen.coinsPerPower, 10)
		expect.equal(pen.levelGain, 1.15)
		expect.equal(pen.minSqueezeValue, 10)
		expect.equal(pen.maxLevel, 70)
		expect.equal(pen.tickSeconds, 1)
		expect.equal(pen.maxTickSeconds, 10)
		expect.equal(pen.buyCooldownSeconds, 1)
		expect.equal(pen.signHoldSeconds, 0.5)
	end)

	t.test("a missing section is one problem", function()
		local problems = validate({ Economy = {} })
		expect.equal(#problems, 1)
		expect.truthy(mentions(problems, "Config.Economy.Pen is missing"))
		expect.equal(#validate(nil), 1)
	end)

	t.test("each broken value is reported by name", function()
		local cases: { { changes: { [string]: any }, field: string } } = {
			{ changes = { spotPrices = prices({ [6] = 3_000 }) }, field = "spotPrices[6]" }, -- falls
			{ changes = { spotPrices = prices({ [5] = 1_500 }) }, field = "spotPrices[5]" }, -- does not rise
			{ changes = { spotPrices = prices({ [4] = 1_500.5 }) }, field = "spotPrices[4]" },
			{ changes = { spotPrices = prices({ [12] = Config.Economy.maxCoins + 1 }) }, field = "spotPrices[12]" },
			{ changes = { spotPrices = prices({ [12] = false :: any }) }, field = "spotPrices[12]" },
			{ changes = { spotPrices = prices({ [13] = 9e12 }) }, field = "spotPrices" }, -- a key past maxSpots
			{ changes = { spotPrices = prices({ [3] = 100 }) }, field = "spotPrices" }, -- the free spots have no price
			{ changes = { formMult = { 1, 0, 4 } }, field = "formMult[2]" },
			{ changes = { formMult = { 1, 4, 2 } }, field = "formMult[3]" },
			{ changes = { formMult = {} }, field = "formMult" },
			{ changes = { coatMult = { 0, 1.5 } }, field = "coatMult[1]" },
			{ changes = { startSpots = 0 }, field = "startSpots" },
			{ changes = { maxSpots = 3 }, field = "maxSpots" },
			{ changes = { maxLevel = 0 }, field = "maxLevel" },
			{ changes = { maxLevel = 2.5 }, field = "maxLevel" },
			{ changes = { tickSeconds = 0 }, field = "tickSeconds" },
			{ changes = { maxTickSeconds = -1 }, field = "maxTickSeconds" },
			{ changes = { coinsPerPower = 0 }, field = "coinsPerPower" },
			{ changes = { levelGain = 0 / 0 }, field = "levelGain" },
			{ changes = { minSqueezeValue = -1 }, field = "minSqueezeValue" },
			{ changes = { placedMax = 11 }, field = "placedMax" },
			{ changes = { toyBoxMax = -1 }, field = "toyBoxMax" },
			{ changes = { buyCooldownSeconds = -1 }, field = "buyCooldownSeconds" },
			{ changes = { signHoldSeconds = "long" }, field = "signHoldSeconds" },
		}
		for _, case in cases do
			local problems = validate(broken(case.changes))
			if not mentions(problems, case.field) then
				error(`no problem names {case.field}: {table.concat(problems, " | ")}`)
			end
		end
	end)
end
