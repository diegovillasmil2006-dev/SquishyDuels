--!strict
-- PenMath_Test: unit tests for ReplicatedStorage.Shared.PenMath (pens3 phase 1). Server only (ServerStorage.UnitTest).
-- Contract (work/pens3/PLAN.md phase 1, "Tests"): an item earns coinsPerPower × squishy power × form × coating ×
-- levelGain^(level - 1) Coins a second (Kitty Bread 10, Butter 40, Bird 160, Dragon 640); the pen places its best
-- `spots` items (rate high first, a tie to the lower id); the squeeze value is the placed items' rate, never below 10
-- (nil or a broken pen: 10), and an own squeeze's Grip is its floor; spot prices are the J table (4 = 1,500 ..
-- 12 = 5.6T), nil for any other spot; a buy is the next spot at its exact price; the tick pays whole Coins and carries
-- the rest, at most maxTickSeconds of time at once; rewardCoins = floor(squeezes × value) clamped to maxCoins; the
-- base attribute text round-trips; the walk area keeps a squishy inside the fence. Phase 4: awayCoins = floor(5% ×
-- the saved rate × the seconds away), the seconds clamped to [0, now - createdAt], no limit, clamped to maxCoins.
-- Phase 5: room = spots + toyBoxMax - the items (never below 0; 0 for a broken pen): 0 means the Toy Box is full.
-- Phase 6 (the pen screen): an item's `slot` says where it is (0 = the Toy Box, 1..spots the pen): the pen places the
-- items in slots 1..spots, in slot order (an item with no slot, or a slot out of the open spots, takes none; a
-- repeated slot counts once); freeSlot is the first open spot nobody holds (0 when none); toyBox lists the slot-0
-- items; bestToyBox is the best unlocked one (rate, then id); placeDecision checks a move (net.invalid, then
-- inventory.notOwned, then pen.spotClosed, then inventory.full for a put away into a full Toy Box): an occupied spot
-- swaps (the other squishy takes the mover's old place), the same place is a move that changes nothing.

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

	-- Pens3 phase 6: an item at a slot (0 = the Toy Box), optionally locked.
	local function at(slot: number, it: any, locked: boolean?): any
		it.slot = slot
		it.locked = locked == true
		return it
	end

	-- Phase 6: a pen whose items sit in slots 1, 2, ... in list order, the ones past `spots` in the Toy Box.
	local function placedPen(spots: number, items: { any }): any
		for index, it in items do
			at(if index <= spots then index else 0, it)
		end
		return pen(spots, items)
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

	t.test("placed: the items in slots 1..spots, in slot order; no slot or a closed one takes no spot", function()
		local a = at(2, item("kitty_bread"))
		local b = at(1, item("butter"))
		local c = at(0, item("toast")) -- the Toy Box
		local d = at(3, item("dragon"))
		local e = at(5, item("banana")) -- a spot past the 3 open ones
		expect.deepEqual(PenMath.placed(pen(3, { a, b, c, d, e })), { b, a, d })
		expect.deepEqual(PenMath.placed(pen(5, { a, b, c, d, e })), { b, a, d, e }) -- spot 4 is empty
		-- A placed squishy never moves for a better one: the Toy Box's Dragon waits.
		local kitty = at(1, item("kitty_bread"))
		local dragon = at(0, item("dragon"))
		expect.deepEqual(PenMath.placed(pen(3, { kitty, dragon })), { kitty })
		-- Fail closed: no slot, a broken slot, a repeated slot (the first keeps it), an unknown kind.
		local noSlot = item("toast")
		local broken = at(1.5, item("toast"))
		local first = at(2, item("toast"))
		local twin = at(2, item("banana"))
		expect.deepEqual(PenMath.placed(pen(3, { noSlot, broken, first, twin, at(3, item("unicorn")) })), { first })
		expect.deepEqual(PenMath.placed(nil), {})
		expect.deepEqual(PenMath.placed(pen(2, { at(1, item("toast")) })), {}) -- below startSpots: a broken pen
		expect.deepEqual(PenMath.placed(pen(13, { at(1, item("toast")) })), {})
		expect.deepEqual(PenMath.placed({ spots = 3 }), {})
	end)

	t.test("rate and squeezeValue: the placed items' sum, never below 10; squeezeGrip = floor", function()
		expect.equal(PenMath.squeezeValue(nil), 10)
		expect.equal(PenMath.squeezeValue("garbage"), 10)
		expect.equal(PenMath.squeezeValue(pen(3, {})), 10)
		expect.equal(PenMath.rate(pen(3, {})), 0)
		expect.equal(PenMath.squeezeValue(placedPen(3, { item("kitty_bread") })), 10)
		expect.equal(PenMath.squeezeValue(placedPen(3, { item("dragon") })), 640)
		expect.equal(PenMath.squeezeValue(pen(3, { at(0, item("dragon")) })), 10) -- in the Toy Box: no pay
		local two = placedPen(3, { item("kitty_bread"), item("butter") })
		expect.equal(PenMath.rate(two), 50)
		expect.equal(PenMath.squeezeValue(two), 50)
		-- Only the placed spots count: the 4th squishy waits in the Toy Box.
		local four = placedPen(3, { item("dragon"), item("bird"), item("butter"), item("kitty_bread") })
		expect.equal(PenMath.rate(four), 640 + 160 + 40)
		local levelled = placedPen(3, { item("kitty_bread", 0, 2) })
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
		expect.equal(PenMath.squeezeValue(placedPen(12, all)), 1_470)
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

	-- Pens3 phase 4: coins while away (owner: 5% of the pen's rate, no limit, no idle rule).
	t.test("awayCoins: floor(awayRate × rate × seconds away), the seconds clamped to [0, now - createdAt]", function()
		local now = 1_800_000_000
		expect.equal(PEN.awayRate, 0.05)
		local coins, seconds = PenMath.awayCoins(10, now - 3600, now - 86400, now)
		expect.equal(coins, 1_800) -- an hour of Kitty Bread at 10 a second: 5% of 36,000
		expect.equal(seconds, 3600)
		expect.equal((PenMath.awayCoins(11.5, now - 61, now - 61, now)), 35) -- 35.075, floored
		expect.equal((PenMath.awayCoins(10, now - 365 * 86400, 0, now)), 15_768_000) -- a year away: no limit
		-- The createdAt clamp: never more time away than the profile is old.
		coins, seconds = PenMath.awayCoins(10, now - 10_000, now - 100, now)
		expect.equal(coins, 50)
		expect.equal(seconds, 100)
		expect.equal((PenMath.awayCoins(1e15, now - 1e6, 0, now)), Config.Economy.maxCoins) -- clamped
	end)

	t.test("awayCoins: no time away, a future time, a bad rate or a bad time pay 0", function()
		local now = 1_800_000_000
		local cases: { { any } } = {
			{ 10, now, 0, now, 0 }, -- just saved
			{ 10, now + 600, 0, now, 0 }, -- a lastSeenAt in the future (another server's clock)
			{ 10, now - 3600, now + 60, now, 0 }, -- a createdAt in the future
			{ 0 / 0, now - 3600, 0, now, 3600 },
			{ math.huge, now - 3600, 0, now, 3600 },
			{ -10, now - 3600, 0, now, 3600 },
			{ "10" :: any, now - 3600, 0, now, 3600 },
			{ 10, 0 / 0, 0, now, 0 },
			{ 10, now - 3600, nil, now, 0 },
			{ 10, now - 3600, 0, math.huge, 0 },
		}
		for _, case in cases do
			local coins, seconds = PenMath.awayCoins(case[1], case[2], case[3], case[4])
			expect.equal(coins, 0)
			expect.equal(seconds, case[5])
		end
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

	-- Pens3 phase 5: the Toy Box (D1:254-258).
	t.test("room: the pen's spots plus the Toy Box's toyBoxMax, less every item; 0 for anything not a pen", function()
		local items = { item("kitty_bread") }
		expect.equal(PenMath.room(pen(3, items)), 3 + PEN.toyBoxMax - 1)
		for _ = 2, 3 + PEN.toyBoxMax - 1 do
			table.insert(items, item("toast"))
		end
		expect.equal(PenMath.room(pen(3, items)), 1) -- 3 placed, 49 unplaced
		table.insert(items, item("toast"))
		expect.equal(PenMath.room(pen(3, items)), 0) -- 50 unplaced: the Toy Box is full
		expect.equal(PenMath.room(pen(4, items)), 1) -- a spot bought makes room for one more
		table.insert(items, item("toast"))
		table.insert(items, item("toast"))
		expect.equal(PenMath.room(pen(3, items)), 0) -- never below 0
		-- Fail closed: nil, spots out of range, items not a table, a broken nextId.
		expect.equal(PenMath.room(nil), 0)
		expect.equal(PenMath.room({ spots = 2, nextId = 2, items = {} }), 0)
		expect.equal(PenMath.room({ spots = 3, nextId = 2, items = "x" }), 0)
		expect.equal(PenMath.room({ spots = 3, nextId = 0 / 0, items = {} }), 0)
	end)
	-- Pens3 phase 6: the pen screen (place, put away, swap, lock).
	t.test("freeSlot: the first open spot nobody holds, else 0; toyBox: the slot-0 items in list order", function()
		local kitty = at(1, item("kitty_bread"))
		local toast = at(3, item("toast"))
		local banana = at(0, item("banana"))
		local box = pen(4, { kitty, toast, banana })
		expect.equal(PenMath.freeSlot(box), 2)
		expect.deepEqual(PenMath.toyBox(box), { banana })
		toast.slot = 2
		expect.equal(PenMath.freeSlot(box), 3)
		expect.equal(PenMath.freeSlot(pen(3, { at(1, item("toast")), at(2, item("toast")), at(3, item("toast")) })), 0)
		expect.equal(PenMath.freeSlot(pen(3, {})), 1)
		expect.equal(PenMath.freeSlot(nil), 0)
		expect.equal(PenMath.freeSlot(pen(2, {})), 0) -- a broken pen has no spot
		expect.deepEqual(PenMath.toyBox(nil), {})
		expect.deepEqual(PenMath.toyBox(pen(3, { item("toast"), at(0, item("unicorn")) })), {}) -- no slot, no kind
	end)

	t.test("find and bestToyBox: an item by id; the best unlocked Toy Box squishy (rate, then the lower id)", function()
		local kitty = at(1, item("kitty_bread"))
		local toastA = at(0, item("toast"))
		local toastB = at(0, item("toast"))
		local bird = at(0, item("bird"), true) -- locked: auto-place never moves it
		local box = pen(4, { kitty, toastB, bird, toastA })
		expect.equal(PenMath.find(box, kitty.id), kitty)
		expect.equal(PenMath.find(box, 999), nil)
		expect.equal(PenMath.find(nil, kitty.id), nil)
		expect.equal(PenMath.bestToyBox(box), toastA) -- 10 each: the lower id, whatever the list order
		bird.locked = false
		expect.equal(PenMath.bestToyBox(box), bird)
		expect.equal(PenMath.bestToyBox(pen(3, { kitty })), nil)
		expect.equal(PenMath.bestToyBox(nil), nil)
	end)

	t.test("placeDecision: an empty spot, a swap, a put away, the same place; every refusal code", function()
		local kitty = at(1, item("kitty_bread"))
		local butter = at(2, item("butter"))
		local toast = at(0, item("toast"))
		local box = pen(4, { kitty, butter, toast })
		-- A Toy Box squishy into the empty spot 3.
		expect.deepEqual(PenMath.placeDecision(box, toast.id, 3), { id = toast.id, from = 0, to = 3 })
		-- Into an occupied spot: a swap (Kitty Bread goes where the Toast was: the Toy Box).
		expect.deepEqual(
			PenMath.placeDecision(box, toast.id, 1),
			{ id = toast.id, from = 0, to = 1, swapId = kitty.id }
		)
		-- Two pen squishies swap spots.
		expect.deepEqual(
			PenMath.placeDecision(box, kitty.id, 2),
			{ id = kitty.id, from = 1, to = 2, swapId = butter.id }
		)
		-- Put away: slot 0 (never a swap: the Toy Box holds many).
		expect.deepEqual(PenMath.placeDecision(box, butter.id, 0), { id = butter.id, from = 2, to = 0 })
		-- The same place: a move that changes nothing.
		expect.deepEqual(PenMath.placeDecision(box, kitty.id, 1), { id = kitty.id, from = 1, to = 1 })
		expect.deepEqual(PenMath.placeDecision(box, toast.id, 0), { id = toast.id, from = 0, to = 0 })
		-- A locked squishy still moves (a lock only keeps it from being sold or fused, D1:221, D1:230).
		kitty.locked = true
		expect.equal((PenMath.placeDecision(box, kitty.id, 0) :: any).to, 0)
		local function refusal(state: any, id: any, slot: any): string?
			local move, code = PenMath.placeDecision(state, id, slot)
			expect.equal(move, nil)
			return code
		end
		expect.equal(refusal(box, 999, 1), "inventory.notOwned")
		expect.equal(refusal(box, toast.id, 5), "pen.spotClosed") -- a spot not bought yet
		expect.equal(refusal(box, toast.id, PEN.placedMax), "pen.spotClosed") -- the shelf (phase 11)
		for _, bad in { -1, PEN.placedMax + 1, 1.5, 0 / 0, "1" } :: { any } do
			expect.equal(refusal(box, toast.id, bad), "net.invalid")
		end
		expect.equal(refusal(box, 1.5, 1), "net.invalid")
		expect.equal(refusal(nil, toast.id, 1), "net.invalid")
		expect.equal(refusal(pen(2, { kitty }), kitty.id, 1), "net.invalid") -- a broken pen
	end)

	t.test("placeDecision: a put away into a full Toy Box is inventory.full; a swap from it is fine", function()
		local items = { at(1, item("kitty_bread")) }
		for _ = 1, PEN.toyBoxMax do
			table.insert(items, at(0, item("toast")))
		end
		local box = pen(3, items)
		local _, code = PenMath.placeDecision(box, items[1].id, 0)
		expect.equal(code, "inventory.full")
		-- A Toy Box squishy swapping with a pen one keeps the count: allowed.
		expect.deepEqual(
			PenMath.placeDecision(box, items[2].id, 1),
			{ id = items[2].id, from = 0, to = 1, swapId = items[1].id }
		)
		expect.equal((PenMath.placeDecision(box, items[2].id, 2) :: any).to, 2) -- an empty spot: one fewer in the box
	end)
end
