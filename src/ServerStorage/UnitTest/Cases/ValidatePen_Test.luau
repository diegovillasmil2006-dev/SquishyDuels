--!strict
-- ValidatePen_Test: unit tests for ReplicatedStorage.Shared.Config.ValidatePen (the pen, pens3 phase 1). Server only
-- (ServerStorage.UnitTest). Pure: broken copies of Config.Economy.Pen.
-- Contract (Config/ValidatePen header): the shipped Config is valid and holds the plan's numbers; a missing section is
-- one problem; each broken value is reported by name (phase 4: awayRate, a share in [0, 1]; phase 5: giftQueueMax, the
-- Welcome prices (whole Coins, a rarity with sold squishies, never above their shop price) and the Frog gift; phase 7:
-- the sell prices (every rarity, whole Coins, below what it can be bought for, times sellFormMult within maxCoins),
-- sellFormMult, sellMaxIds, sellHold and the buy-back's seconds and size; phase 11: the shelf rows and the TOP spot,
-- Neon Sugar part 5's prices (Diego's 12 cubbies, one a buy) strictly rising in the order they are bought, and
-- placedMax = the pen's spots + the shelf's + 1).

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

	-- Pens3 phase 11: Config's shelf row prices with some changed.
	local function rows(changes: { [number]: any }): any
		local list = table.clone(Config.Economy.Pen.shelfRowPrices)
		for key, value in changes do
			list[key] = value
		end
		return list
	end

	-- Pens3 phase 7: Config's sell prices with some changed.
	local function sells(changes: { [string]: any }): any
		local list = table.clone(Config.Economy.Pen.sellPrice)
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
		expect.equal(pen.awayRate, 0.05) -- pens3 phase 4 (owner: 5% of the pen's rate while away)
		-- Pens3 phase 5: the gift queue (D1:254-258, [P] 50), the Welcome price (D1:202) and the Frog gift (SIM:226).
		expect.equal(pen.giftQueueMax, 50)
		expect.deepEqual(pen.welcomePrice, { Common = 1_000 }) -- owner 2026-10-31: 3K -> 1K
		expect.deepEqual(pen.frogGift, { kind = "strawberry_frog", seconds = 180 })
		-- Pens3 phase 7: V3:164's sell prices (Rare comes with phase 22), Golden x3 / Rainbow x9, D1:222's hold rule,
		-- the 10-minute buy-back of at most toyBoxMax + placedMax sales.
		expect.deepEqual(
			pen.sellPrice,
			{ Common = 900, Uncommon = 150_000, Epic = 90_000_000, Exclusive = 225_000_000_000 } -- Common 1K -> 900
		)
		expect.deepEqual(pen.sellFormMult, { 1, 3, 9 })
		expect.equal(pen.sellMaxIds, 50)
		expect.deepEqual(pen.sellHold, { form = 1, level = 10, rarity = "Epic" })
		expect.equal(pen.buyBackSeconds, 600)
		expect.equal(pen.buyBackMax, pen.toyBoxMax + pen.placedMax)
		-- Neon Sugar part 5 (owner 2026-10-24): one cubby a row, 2 open from the start, cubbies 3-11 then the TOP spot,
		-- each about x5 the last (300M .. 190T, 1Qa); 12 + 11 + 1 = 24 placed.
		expect.equal(pen.shelfStartRows, 2)
		expect.equal(pen.shelfMaxRows, 11)
		expect.equal(pen.shelfRowSpots, 1)
		expect.deepEqual(pen.shelfRowPrices, {
			[3] = 300_000_000,
			[4] = 1_600_000_000,
			[5] = 8_400_000_000,
			[6] = 45_000_000_000,
			[7] = 240_000_000_000,
			[8] = 1_300_000_000_000,
			[9] = 6_700_000_000_000,
			[10] = 36_000_000_000_000,
			[11] = 190_000_000_000_000,
		})
		expect.equal(pen.topPrice, 1_000_000_000_000_000)
		expect.equal(pen.placedMax, 24)
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
			{ changes = { awayRate = -0.05 }, field = "awayRate" }, -- pens3 phase 4: a share in [0, 1]
			{ changes = { awayRate = 1.5 }, field = "awayRate" },
			{ changes = { awayRate = 0 / 0 }, field = "awayRate" },
			-- Pens3 phase 5.
			{ changes = { giftQueueMax = -1 }, field = "giftQueueMax" },
			{ changes = { giftQueueMax = 1.5 }, field = "giftQueueMax" },
			{ changes = { welcomePrice = 3_000 }, field = "welcomePrice" },
			{ changes = { welcomePrice = { Common = 0 } }, field = "welcomePrice.Common" },
			{ changes = { welcomePrice = { Common = 2_999.5 } }, field = "welcomePrice.Common" },
			{ changes = { welcomePrice = { Common = 789_001 } }, field = "welcomePrice.Common" }, -- above the price
			{ changes = { welcomePrice = { Rare = 3_000 } }, field = "welcomePrice.Rare" }, -- no sold squishy
			{ changes = { frogGift = "frog" }, field = "frogGift" },
			{ changes = { frogGift = { kind = "unicorn", seconds = 180 } }, field = "frogGift.kind" },
			{ changes = { frogGift = { kind = "strawberry_frog", seconds = -1 } }, field = "frogGift.seconds" },
			-- Pens3 phase 7.
			{ changes = { sellPrice = 1_000 }, field = "sellPrice" },
			{
				changes = { sellPrice = { Common = 1_000, Uncommon = 150_000, Epic = 90_000_000 } },
				field = "sellPrice.Exclusive",
			},
			{ changes = { sellPrice = sells({ Common = 2.5 }) }, field = "sellPrice.Common" },
			{ changes = { sellPrice = sells({ Common = -1 }) }, field = "sellPrice.Common" },
			{ changes = { sellPrice = sells({ Common = 1_000 }) }, field = "sellPrice.Common" }, -- = the Welcome price
			{ changes = { sellPrice = sells({ Epic = 1_800_000_000 }) }, field = "sellPrice.Epic" }, -- = the shop price
			{ changes = { sellPrice = sells({ Exclusive = 1e15 }) }, field = "sellPrice.Exclusive" }, -- x9 > maxCoins
			{ changes = { sellPrice = sells({ Rare = 300_000 }) }, field = "sellPrice.Rare" }, -- not a rarity yet
			{ changes = { sellFormMult = { 1, 3 } }, field = "sellFormMult" }, -- one per form
			{ changes = { sellFormMult = { 1, 0.5, 9 } }, field = "sellFormMult[2]" },
			{ changes = { sellFormMult = { 1, 9, 3 } }, field = "sellFormMult[3]" },
			{ changes = { sellMaxIds = 0 }, field = "sellMaxIds" },
			{ changes = { sellMaxIds = 2.5 }, field = "sellMaxIds" },
			{ changes = { sellHold = true }, field = "sellHold" },
			{ changes = { sellHold = { form = 3, level = 10, rarity = "Epic" } }, field = "sellHold.form" },
			{ changes = { sellHold = { form = 1, level = 0, rarity = "Epic" } }, field = "sellHold.level" },
			{ changes = { sellHold = { form = 1, level = 10, rarity = "Rare" } }, field = "sellHold.rarity" },
			{ changes = { buyBackSeconds = 0 }, field = "buyBackSeconds" },
			{ changes = { buyBackMax = 0 }, field = "buyBackMax" },
			{ changes = { buyBackMax = 70.5 }, field = "buyBackMax" },
			-- Pens3 phase 11.
			{ changes = { shelfStartRows = 0 }, field = "shelfStartRows" },
			{ changes = { shelfStartRows = 12 }, field = "shelfStartRows" }, -- above shelfMaxRows
			{ changes = { shelfMaxRows = 2.5 }, field = "shelfMaxRows" },
			{ changes = { shelfRowSpots = 0 }, field = "shelfRowSpots" },
			{ changes = { placedMax = 25 }, field = "placedMax" }, -- not 12 + 11 x 1 + 1
			{ changes = { shelfRowPrices = 300_000_000 }, field = "shelfRowPrices" },
			{ changes = { shelfRowPrices = rows({ [4] = 300_000_000 }) }, field = "shelfRowPrices[4]" }, -- no rise
			{ changes = { shelfRowPrices = rows({ [3] = 300_000_000.5 }) }, field = "shelfRowPrices[3]" },
			{ changes = { shelfRowPrices = rows({ [4] = false :: any }) }, field = "shelfRowPrices[4]" },
			{ changes = { shelfRowPrices = rows({ [2] = 100 }) }, field = "shelfRowPrices" }, -- a free cubby
			{ changes = { shelfRowPrices = rows({ [12] = 5e14 }) }, field = "shelfRowPrices" }, -- past shelfMaxRows
			{ changes = { topPrice = 190_000_000_000_000 }, field = "topPrice" }, -- not above cubby 11
			{ changes = { topPrice = Config.Economy.maxCoins + 1 }, field = "topPrice" },
			{ changes = { topPrice = "1Qa" }, field = "topPrice" },
		}
		for _, case in cases do
			local problems = validate(broken(case.changes))
			if not mentions(problems, case.field) then
				error(`no problem names {case.field}: {table.concat(problems, " | ")}`)
			end
		end
	end)
end
