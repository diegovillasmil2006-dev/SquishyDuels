--!strict
-- PenMath_Test: unit tests for ReplicatedStorage.Shared.PenMath (pens3 phase 1). Server only (ServerStorage.UnitTest).
-- Contract (work/pens3/PLAN.md phase 1, "Tests"): an item earns coinsPerPower × squishy power × form × coating ×
-- levelGain^(level - 1) Coins a second (Kitty Bread 10, Butter 40, Bird 160, Dragon 640); the pen places its best
-- `spots` items (rate high first, a tie to the lower id); the squeeze value is the placed items' rate, never below 10
-- (nil or a broken pen: 10), and an own squeeze's Grip is its floor; spot prices are the J table (4 = 1,500 ..
-- 12 = 5.6T), nil for any other spot; a buy is the next spot at its exact price; the tick pays whole Coins and carries
-- the rest, at most maxTickSeconds of time at once; rewardCoins = floor(squeezes × value) clamped to maxCoins; the
-- base attribute text round-trips; the walk area keeps a squishy inside the fence.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local PenMath = t.requireShared("PenMath")
	local Config = t.requireShared("Config")
	local PEN = Config.Economy.Pen

	local nextId = 0
	local function item(kind: string, form: number?, level: number?, coat: number?): any
		nextId += 1
		return { id = nextId, kind = kind, form = form or 0, level = level or 1, coat = coat or 0 }
	end

	local function pen(spots: number, items: { any }): any
		return { spots = spots, nextId = 100, items = items }
	end

	t.test("itemRate: 10 / 40 / 160 / 640 by rarity; Golden x2, Rainbow x4, Wax x1.5, x1.15 a level", function()
		expect.equal(PenMath.itemRate(item("kitty_bread")), 10)
		expect.equal(PenMath.itemRate(item("butter")), 40)
		expect.equal(PenMath.itemRate(item("bird")), 160)
		expect.equal(PenMath.itemRate(item("dragon")), 640)
		expect.equal(PenMath.itemRate(item("kitty_bread", 1)), 20)
		expect.equal(PenMath.itemRate(item("kitty_bread", 2)), 40)
		expect.equal(PenMath.itemRate(item("kitty_bread", 0, 1, 1)), 15)
		expect.near(PenMath.itemRate(item("kitty_bread", 0, 2)), 11.5, 1e-9)
		expect.near(PenMath.itemRate(item("kitty_bread", 0, 11)), 10 * 1.15 ^ 10, 1e-9)
		expect.near(PenMath.itemRate(item("dragon", 2, 1, 7)), 640 * 4 * 12, 1e-9) -- Rainbow Galaxy Dragon
	end)

	t.test("itemRate: anything that is not a pen item earns 0", function()
		for _, bad in
			{
				item("unicorn"),
				item("kitty_bread", 3),
				item("kitty_bread", 0.5),
				item("kitty_bread", 0, 0),
				item("kitty_bread", 0, PEN.maxLevel + 1),
				item("kitty_bread", 0, 1, 8),
				item("kitty_bread", 0, 0 / 0),
				{ id = 1, kind = "kitty_bread" },
			} :: { any }
		do
			expect.equal(PenMath.itemRate(bad), 0)
		end
		expect.equal(PenMath.itemRate(nil), 0)
		expect.equal(PenMath.itemRate("kitty_bread"), 0)
	end)

	t.test("placed: the best `spots` items, the higher rate first, a tie to the lower id", function()
		local a = item("kitty_bread")
		local b = item("butter")
		local c = item("toast") -- 10, the same as a: a has the lower id
		local d = item("dragon")
		local e = item("banana")
		local placed = PenMath.placed(pen(3, { a, b, c, d, e }))
		expect.deepEqual(placed, { d, b, a })
		expect.deepEqual(PenMath.placed(pen(4, { e, c, a })), { a, c, e }) -- fewer items than spots: all of them
		-- An unknown kind earns nothing and takes no spot.
		expect.deepEqual(PenMath.placed(pen(3, { item("unicorn"), a })), { a })
		expect.deepEqual(PenMath.placed(nil), {})
		expect.deepEqual(PenMath.placed(pen(2, { a })), {}) -- below startSpots: a broken pen
		expect.deepEqual(PenMath.placed(pen(13, { a })), {})
		expect.deepEqual(PenMath.placed({ spots = 3 }), {})
	end)

	t.test("rate and squeezeValue: the placed items' sum, never below 10; squeezeGrip = floor", function()
		expect.equal(PenMath.squeezeValue(nil), 10)
		expect.equal(PenMath.squeezeValue("garbage"), 10)
		expect.equal(PenMath.squeezeValue(pen(3, {})), 10)
		expect.equal(PenMath.rate(pen(3, {})), 0)
		expect.equal(PenMath.squeezeValue(pen(3, { item("kitty_bread") })), 10)
		expect.equal(PenMath.squeezeValue(pen(3, { item("dragon") })), 640)
		local two = pen(3, { item("kitty_bread"), item("butter") })
		expect.equal(PenMath.rate(two), 50)
		expect.equal(PenMath.squeezeValue(two), 50)
		-- Only the placed spots count: the 4th-best squishy waits.
		local four = pen(3, { item("kitty_bread"), item("butter"), item("bird"), item("dragon") })
		expect.equal(PenMath.rate(four), 640 + 160 + 40)
		local levelled = pen(3, { item("kitty_bread", 0, 2) })
		expect.near(PenMath.squeezeValue(levelled), 11.5, 1e-9)
		expect.equal(PenMath.squeezeGrip(levelled), 11)
		expect.equal(PenMath.squeezeGrip(nil), 10)
		-- Phase 1's top: one of each kind in 12 spots (no copies, levels, forms or coatings yet).
		local all = {}
		for _, kind in
			{
				"dragon",
				"bird",
				"donut",
				"cloud_bunny",
				"cupcake_axolotl",
				"butter",
				"chocolate",
				"mochi_fox",
				"strawberry_frog",
				"kitty_bread",
				"toast",
				"banana",
				"boba_bear",
				"pancake_pup",
			}
		do
			table.insert(all, item(kind))
		end
		expect.equal(PenMath.squeezeValue(pen(12, all)), 1_470)
	end)

	t.test("spotPrice: the J table; 3, 13, 4.5 and non-numbers give nil", function()
		expect.equal(PenMath.spotPrice(4), 1_500)
		expect.equal(PenMath.spotPrice(7), 2_300_000)
		expect.equal(PenMath.spotPrice(12), 5_600_000_000_000)
		for _, bad in { 3, 13, 4.5, 0 / 0, "4" } :: { any } do
			expect.equal(PenMath.spotPrice(bad), nil)
		end
	end)

	t.test("buyDecision: the next spot at its exact price; max, a wrong price and bad input are refused", function()
		local buy, refused = PenMath.buyDecision(pen(3, {}), 1_500)
		expect.deepEqual(buy, { spot = 4, price = 1_500 })
		expect.equal(refused, nil)
		expect.deepEqual(PenMath.buyDecision(pen(11, {}), 5_600_000_000_000), { spot = 12, price = 5_600_000_000_000 })
		-- A refusal: no buy, only the code.
		local function refusal(state: any, price: any): string?
			local refusedBuy, code = PenMath.buyDecision(state, price)
			expect.equal(refusedBuy, nil)
			return code
		end
		expect.equal(refusal(pen(12, {}), 0), "pen.max")
		expect.equal(refusal(pen(3, {}), 3_100), "pen.priceChanged")
		expect.equal(refusal(pen(4, {}), 1_500), "pen.priceChanged") -- a retry
		for _, bad in { -1, 1.5, 0 / 0, "1500", Config.Economy.maxCoins + 1 } :: { any } do
			expect.equal(refusal(pen(3, {}), bad), "net.invalid")
		end
		expect.equal(refusal(nil, 1_500), "net.invalid")
	end)

	t.test("payStep: whole Coins, the rest carried; dt clamped to [0, maxTickSeconds]", function()
		local coins, carry = PenMath.payStep(0, 11.5, 1)
		expect.equal(coins, 11)
		expect.near(carry, 0.5, 1e-9)
		coins, carry = PenMath.payStep(carry, 11.5, 1)
		expect.equal(coins, 12)
		expect.near(carry, 0, 1e-9)
		expect.equal(PEN.maxTickSeconds, 10)
		expect.equal((PenMath.payStep(0, 10, 30)), 100) -- a hitch pays at most 10 s
		expect.deepEqual({ PenMath.payStep(0, 10, -5) }, { 0, 0 })
		expect.deepEqual({ PenMath.payStep(0, 10, 0 / 0) }, { 0, 0 })
		expect.deepEqual({ PenMath.payStep(0 / 0, 10, 1) }, { 10, 0 })
		expect.deepEqual({ PenMath.payStep(0, -10, 1) }, { 0, 0 })
		expect.deepEqual({ PenMath.payStep(0, math.huge, 1) }, { 0, 0 })
	end)

	t.test("rewardCoins: floor(squeezes × value), clamped to maxCoins; non-finite or negative counts 0", function()
		expect.equal(PenMath.rewardCoins(600, 10), 6_000)
		expect.equal(PenMath.rewardCoins(3, 11.5), 34)
		expect.equal(PenMath.rewardCoins(1e9, 1e10), Config.Economy.maxCoins)
		expect.equal(PenMath.rewardCoins(0 / 0, 10), 0)
		expect.equal(PenMath.rewardCoins(10, math.huge), 0)
		expect.equal(PenMath.rewardCoins(-5, 10), 0)
	end)

	t.test("encode / decode: kind.form.level.coat joined by ';' round-trips; junk entries are skipped", function()
		local items = { item("dragon", 2, 70, 7), item("kitty_bread"), item("strawberry_frog", 1, 12, 3) }
		local text = PenMath.encode(items)
		expect.equal(text, "dragon.2.70.7;kitty_bread.0.1.0;strawberry_frog.1.12.3")
		expect.deepEqual(PenMath.decode(text), {
			{ kind = "dragon", form = 2, level = 70, coat = 7 },
			{ kind = "kitty_bread", form = 0, level = 1, coat = 0 },
			{ kind = "strawberry_frog", form = 1, level = 12, coat = 3 },
		})
		expect.equal(PenMath.encode({}), "")
		expect.deepEqual(PenMath.decode(""), {})
		expect.deepEqual(PenMath.decode(nil), {})
		expect.deepEqual(PenMath.decode("unicorn.0.1.0;kitty_bread.9.1.0;toast.0.1;butter.0.1.0"), {
			{ kind = "butter", form = 0, level = 1, coat = 0 },
		})
	end)

	t.test("wanderRect: inside the step's fence, half the squishy and the edge margin in", function()
		local rect = PenMath.wanderRect(3, 2) :: any
		-- 16 × 12 at spots 3, front z 19: x ±(8 - 1 - 0.8), z from 19 - 12 + 1.8 to 19 - 1.8.
		expect.near(rect.minX, -6.2, 1e-9)
		expect.near(rect.maxX, 6.2, 1e-9)
		expect.near(rect.minZ, 8.8, 1e-9)
		expect.near(rect.maxZ, 17.2, 1e-9)
		local big = PenMath.wanderRect(12, 5) :: any -- 24 × 32
		expect.near(big.minX, -8.7, 1e-9)
		expect.near(big.maxZ, 15.7, 1e-9)
		expect.near(big.minZ, 19 - 32 + 3.3, 1e-9)
		expect.equal(PenMath.wanderRect(2, 2), nil)
		expect.equal(PenMath.wanderRect(13, 2), nil)
	end)
end
