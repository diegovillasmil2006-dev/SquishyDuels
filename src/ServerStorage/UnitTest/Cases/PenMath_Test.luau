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
-- Phase 7 (selling): sellPrice = the rarity's price (1K / 150K / 90M / 225B) x 1 / 3 / 9 by form, nothing for food or
-- coatings; sellDecision checks every id (net.invalid, inventory.notOwned, pen.sellStarter, pen.locked, pen.lastCopy:
-- every form counts) and sums the Coins; sellAllIds sells only the Toy Box's plain Lv 1 unlocked squishies, never Kitty
-- Bread, keeping the best one of a kind nothing else keeps; liveBuyBack keeps the entries younger than buyBackSeconds,
-- the newest buyBackMax; buyBackDecision finds a live entry (net.invalid, pen.buyBackGone, inventory.full). Phase 8
-- (fusion): fuseDecision takes 3 of one kind and form (net.invalid, inventory.notOwned, pen.locked, pen.fuseMismatch,
-- pen.fuseTop for Rainbow); the keeper is the highest level (a tie: a placed one, then the lower id), the result its
-- next form at its level, and every input's coating is listed for the bag. Phase 10 (the pen look): segmentFrames is
-- K's fence at a spot count in build order (front from the gate out, the sides, the back), newSegments what a growing
-- pen gains, decorOf the tier's decor (K:4170-4189: tier 2 bulbs + lamps, tier 3 also the bow + trees).
-- Phase 11 (the shelf rows + the TOP spot, V3:144-151, J's prices): the open spots are the pen's 1..spots, the shelf's
-- 13.. (2 a row, shelfRows rows; a missing or broken shelfRows opens no shelf spot: fail closed) and the TOP
-- spot 21 once bought; placed lists them all in slot order (they all earn: rate, squeeze value, Feed All, a fusion
-- keeper), inPen / onShelf split them; freeSlot fills the pen, then the shelf, then the TOP spot; room counts every
-- open spot; placeDecision moves into, out of and between them (a closed shelf spot or an unbought TOP spot is
-- pen.spotClosed); shelfPrice / shelfDecision sell row 2, 3, 4 at 31M / 250B / 11T, then the TOP spot at 140T, then
-- pen.shelfMax (a wrong price pen.priceChanged, bad input or a broken pen net.invalid); from 9 spots the back wall is
-- the shelf (no back fence segments); encodeShelf / decodeShelf carry each shelf squishy's slot and look.

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

	-- Pens3 phase 11: a pen with shelf rows and the TOP spot.
	local function shelfPen(spots: number, rows: any, top: any, items: { any }): any
		return { spots = spots, nextId = 100, items = items, shelfRows = rows, top = top }
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

	-- Pens3 phase 10 (the pen look): the fence's segments and the tier decor.
	local function spots(frames: { CFrame }): { string }
		local list = {}
		for _, frame in frames do
			table.insert(list, string.format("%g,%g", frame.Position.X, frame.Position.Z))
		end
		return list
	end

	t.test(
		"segmentFrames: K's segments in build order (front from the gate out, sides, the back); none off-step",
		function()
			-- 16 × 12 at 3 spots, front z 19, gate gap x -4..4: one front pair, 3 per side, 4 at the back (z 7).
			expect.deepEqual(spots(PenMath.segmentFrames(3)), {
				"-6,19",
				"6,19",
				"-8,17",
				"8,17",
				"-8,13",
				"8,13",
				"-8,9",
				"8,9",
				"-6,7",
				"-2,7",
				"2,7",
				"6,7",
			})
			local side = PenMath.segmentFrames(3)[3]
			expect.near(math.abs(side.RightVector.Z), 1, 1e-6) -- a side segment runs along the plot's Z
			expect.near(math.abs(PenMath.segmentFrames(3)[1].RightVector.X), 1, 1e-6)
			local WorldLayout = t.requireShared("World/WorldLayout")
			for count = 3, 12 do
				-- Pens3 phase 11: K's fence count; from 9 spots the back wall is the shelf (no back segments).
				local step = WorldLayout.Bases.pen.steps[count]
				expect.equal(#PenMath.segmentFrames(count), step.fence)
				local backZ = string.format("%g", WorldLayout.Bases.pen.frontZ - step.d)
				local back = 0
				for _, key in spots(PenMath.segmentFrames(count)) do
					if string.match(key, ",(.+)$") == backZ then
						back += 1
					end
				end
				expect.equal(back, if step.backWall == "shelf" then 0 else step.w / 4)
			end
			expect.deepEqual(PenMath.segmentFrames(2), {})
			expect.deepEqual(PenMath.segmentFrames(13), {})
		end
	)

	t.test(
		"newSegments: the segments a pen gains when it grows, in build order; none when only the tier moves",
		function()
			-- 3 -> 4 spots (16 × 12 -> 16 × 16): one more piece down each side and the whole back, 4 deeper.
			expect.deepEqual(spots(PenMath.newSegments(3, 4)), { "-8,5", "8,5", "-6,3", "-2,3", "2,3", "6,3" })
			-- 4 -> 5 (16 × 16 -> 24 × 16): a front pair further out, both sides 4 wider out, the back's two new
			-- ends (its middle 4 pieces stand where they stood).
			expect.equal(#PenMath.newSegments(4, 5), 2 + 8 + 2)
			-- Pens3 phase 11, 8 -> 9 (24 × 28 -> 24 × 32): one more piece down each side; the back fence goes (the
			-- shelf is the back wall now).
			expect.deepEqual(spots(PenMath.newSegments(8, 9)), { "-12,-11", "12,-11" })
			-- 9 -> 10: the same 24 × 32 fence, only the tier changes.
			expect.deepEqual(PenMath.newSegments(9, 10), {})
			expect.deepEqual(PenMath.newSegments(6, 6), {})
			-- Two spots at once (a grant): everything new at 7 spots that 5 did not have.
			expect.equal(#PenMath.newSegments(5, 7), 4 + 6)
		end
	)

	t.test(
		"decorOf: K's tier adds: tier 1 plain, tier 2 the gate bulbs and 2 lamps, tier 3 also the bow and 2 trees",
		function()
			local none = { bulbs = false, lamps = false, bow = false, trees = false }
			local mint = { bulbs = true, lamps = true, bow = false, trees = false }
			local royal = { bulbs = true, lamps = true, bow = true, trees = true }
			for count = 3, 5 do
				expect.deepEqual(PenMath.decorOf(count), none)
			end
			for count = 6, 9 do
				expect.deepEqual(PenMath.decorOf(count), mint)
			end
			for count = 10, 12 do
				expect.deepEqual(PenMath.decorOf(count), royal)
			end
			expect.deepEqual(PenMath.decorOf(2), none)
			expect.deepEqual(PenMath.decorOf(13), none)
			expect.deepEqual(PenMath.decorOf(nil :: any), none)
		end
	)

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

	-- Pens3 phase 7 (selling + the 10-minute buy-back) -------------------------------------------------------------

	t.test(
		"sellPrice: Common 1K, Uncommon 150K, Epic 90M, Dragon 225B; Golden x3, Rainbow x9; level and coat free",
		function()
			expect.equal(PenMath.sellPrice(item("toast")), 1_000)
			expect.equal(PenMath.sellPrice(item("butter")), 150_000)
			expect.equal(PenMath.sellPrice(item("mochi_fox")), 150_000) -- Uncommon until the Rare tier (phase 22)
			expect.equal(PenMath.sellPrice(item("bird")), 90_000_000)
			expect.equal(PenMath.sellPrice(item("dragon")), 225_000_000_000)
			expect.equal(PenMath.sellPrice(item("toast", 1)), 3_000)
			expect.equal(PenMath.sellPrice(item("toast", 2)), 9_000)
			expect.equal(PenMath.sellPrice(item("dragon", 2)), 2_025_000_000_000)
			expect.equal(PenMath.sellPrice(item("toast", 0, 9, 3)), 1_000) -- food and coatings are not refunded
			expect.equal(PenMath.sellPrice(item("unicorn")), 0)
			expect.equal(PenMath.sellPrice(item("toast", 3)), 0)
			expect.equal(PenMath.sellPrice(nil), 0)
		end
	)

	-- A's pen for the sell cases: Kitty Bread in spot 1, two Toasts (spot 2, Toy Box), one Butter (Toy Box).
	local function sellPen(): (any, { any })
		local list = {
			at(1, item("kitty_bread")),
			at(2, item("toast")),
			at(0, item("toast")),
			at(0, item("butter")),
		}
		return pen(3, list), list
	end

	t.test("sellDecision: the items and their Coins; one of two copies sells, a whole list is checked first", function()
		local box, list = sellPen()
		local sale = PenMath.sellDecision(box, { list[3].id }) :: any
		expect.deepEqual(sale.items, { list[3] })
		expect.equal(sale.coins, 1_000)
		list[2].form = 1 -- a Golden Toast still counts as a Toast copy (every form counts)
		local two = PenMath.sellDecision(box, { list[3].id }) :: any
		expect.equal(two.coins, 1_000)
		local both = PenMath.sellDecision(
			pen(3, {
				at(1, item("kitty_bread")),
				at(0, item("toast")),
				at(0, item("toast")),
				at(0, item("toast", 1)),
			}),
			{ nextId - 2, nextId - 1 }
		) :: any
		expect.equal(both.coins, 2_000)
	end)

	t.test("sellDecision refusals, in order: invalid, not owned, Kitty Bread, locked, the last copy", function()
		local box, list = sellPen()
		local function refusal(state: any, ids: any): string?
			local sale, code = PenMath.sellDecision(state, ids)
			expect.equal(sale, nil)
			return code
		end
		for _, bad in { {}, { 1.5 }, { list[3].id, list[3].id }, "1", { [2] = list[3].id }, nil } :: { any } do
			expect.equal(refusal(box, bad), "net.invalid")
		end
		local tooMany = {}
		for id = 1, PEN.sellMaxIds + 1 do
			table.insert(tooMany, id)
		end
		expect.equal(refusal(box, tooMany), "net.invalid")
		expect.equal(refusal(pen(2, list), { list[3].id }), "net.invalid") -- a broken pen
		expect.equal(refusal(box, { list[3].id, 9999 }), "inventory.notOwned")
		expect.equal(refusal(box, { list[1].id }), "pen.sellStarter") -- Kitty Bread is never sold
		list[3].locked = true
		expect.equal(refusal(box, { list[3].id }), "pen.locked")
		list[3].locked = false
		expect.equal(refusal(box, { list[4].id }), "pen.lastCopy") -- the only Butter
		expect.equal(refusal(box, { list[2].id, list[3].id }), "pen.lastCopy") -- both Toasts
		expect.equal(refusal(box, { list[3].id, list[1].id }), "pen.sellStarter") -- one bad id refuses all
	end)

	t.test(
		"sellAllIds: Toy Box squishies only; skips levelled, fused, locked and Kitty Bread; keeps one of a kind",
		function()
			local kitty = at(0, item("kitty_bread"))
			local placedToast = at(1, item("toast"))
			local toastA = at(0, item("toast"))
			local toastB = at(0, item("toast"))
			local levelled = at(0, item("banana", 0, 2))
			local banana = at(0, item("banana"))
			local golden = at(0, item("butter", 1))
			local butter = at(0, item("butter"))
			local lockedBird = at(0, item("bird"), true)
			local birdA = at(0, item("bird"))
			local donutA = at(0, item("donut"))
			local donutB = at(0, item("donut"))
			local box = pen(3, {
				kitty,
				placedToast,
				toastA,
				toastB,
				levelled,
				banana,
				golden,
				butter,
				lockedBird,
				birdA,
				donutA,
				donutB,
			})
			-- Toasts: a placed one stays, so both Toy Box ones go. Banana / Butter / Bird: a skipped copy stays, so the
			-- plain one goes. Donuts: no other copy stays, so the best one (the lower id at the same rate) is kept.
			expect.deepEqual(
				PenMath.sellAllIds(box),
				{ toastA.id, toastB.id, banana.id, butter.id, birdA.id, donutB.id }
			)
			expect.deepEqual(PenMath.sellAllIds(pen(3, { at(1, item("kitty_bread")) })), {})
			expect.deepEqual(PenMath.sellAllIds(nil), {})
			local sale = PenMath.sellDecision(box, PenMath.sellAllIds(box)) :: any
			expect.equal(sale.coins, 3 * 1_000 + 150_000 + 2 * 90_000_000)
		end
	)

	t.test("liveBuyBack: entries younger than buyBackSeconds, newest buyBackMax, broken ones left out", function()
		local now = 10_000
		local function entry(id: number, age: number, price: number?): any
			return {
				item = at(0, { id = id, kind = "toast", form = 0, level = 1, coat = 0 }),
				price = price or 1_000,
				at = now - age,
			}
		end
		local fresh = entry(1, 0)
		local old = entry(2, PEN.buyBackSeconds)
		local mid = entry(3, PEN.buyBackSeconds - 1)
		local broken = { item = { id = 4, kind = "unicorn" }, price = 5, at = now }
		expect.deepEqual(PenMath.liveBuyBack({ old, mid, broken, fresh, 7 } :: any, now), { mid, fresh })
		expect.deepEqual(PenMath.liveBuyBack({ entry(5, 0, -1), entry(6, 0, 1.5) }, now), {})
		local many = {}
		for id = 1, PEN.buyBackMax + 3 do
			table.insert(many, entry(id, 0))
		end
		local kept = PenMath.liveBuyBack(many, now)
		expect.equal(#kept, PEN.buyBackMax)
		expect.equal(kept[1], many[4]) -- the oldest fall off first
		expect.deepEqual(PenMath.liveBuyBack(nil, now), {})
	end)

	t.test(
		"buyBackDecision: the entry within 10 minutes; gone, expired, a full Toy Box and bad input refused",
		function()
			local now = 10_000
			local sold =
				{ item = at(0, { id = 7, kind = "toast", form = 0, level = 1, coat = 0 }), price = 1_000, at = now - 5 }
			local list = { sold }
			local box = pen(3, { at(1, item("kitty_bread")), at(0, item("toast")) })
			local back = PenMath.buyBackDecision(list, box, 7, now) :: any
			expect.equal(back.entry, sold)
			expect.equal(back.index, 1)
			local function refusal(entries: any, state: any, id: any, time: number): string?
				local found, code = PenMath.buyBackDecision(entries, state, id, time)
				expect.equal(found, nil)
				return code
			end
			expect.equal(refusal(list, box, 1.5, now), "net.invalid")
			expect.equal(refusal(list, box, 8, now), "pen.buyBackGone")
			expect.equal(refusal(list, box, 7, sold.at + PEN.buyBackSeconds), "pen.buyBackGone") -- 10 minutes are over
			expect.equal(refusal(nil, box, 7, now), "pen.buyBackGone")
			local full = { at(1, item("kitty_bread")) }
			for _ = 1, 2 + PEN.toyBoxMax do
				table.insert(full, at(0, item("toast")))
			end
			expect.equal(refusal(list, pen(3, full), 7, now), "inventory.full")
		end
	)

	-- Pens3 phase 8 (fusion) -------------------------------------------------------------------------------------

	t.test("fuseDecision: 3 of one kind and form make the next form at the highest level, in its slot", function()
		local a = at(0, item("toast", 0, 2, 3)) -- Lv 2, Jelly
		local b = at(2, item("toast", 0, 7)) -- the highest level: its slot (2) is the result's
		local c = at(0, item("toast", 0, 1, 1)) -- Wax
		local box = pen(3, { at(1, item("kitty_bread")), a, b, c })
		local fusion = PenMath.fuseDecision(box, { a.id, b.id, c.id }) :: any
		expect.equal(fusion.keeper, b)
		expect.deepEqual(fusion.others, { a, c })
		expect.equal(fusion.form, 1)
		expect.equal(fusion.level, 7)
		expect.deepEqual(fusion.coats, { 3, 1 }) -- every input's coating goes to the bag
		-- Golden -> Rainbow; a level tie keeps the placed one, then the lower id.
		local g1 = at(0, item("butter", 1, 4))
		local g2 = at(0, item("butter", 1, 4))
		local g3 = at(3, item("butter", 1, 4))
		local rainbow = PenMath.fuseDecision(pen(3, { g1, g2, g3 }), { g1.id, g2.id, g3.id }) :: any
		expect.equal(rainbow.keeper, g3)
		expect.equal(rainbow.form, 2)
		g3.slot = 0
		expect.equal((PenMath.fuseDecision(pen(3, { g1, g2, g3 }), { g3.id, g2.id, g1.id }) :: any).keeper, g1)
	end)

	t.test(
		"fuseDecision refusals: invalid, not owned, locked, not the same kind and form, Rainbow is the top",
		function()
			local a = at(0, item("toast"))
			local b = at(0, item("toast"))
			local c = at(1, item("toast"))
			local box = pen(3, { a, b, c })
			local function refusal(state: any, ids: any): string?
				local fusion, code = PenMath.fuseDecision(state, ids)
				expect.equal(fusion, nil)
				return code
			end
			for _, bad in
				{ { a.id, b.id }, { a.id, b.id, b.id }, { a.id, b.id, 1.5 }, { a.id, b.id, c.id, 99 }, nil } :: { any }
			do
				expect.equal(refusal(box, bad), "net.invalid")
			end
			expect.equal(refusal(pen(2, { a, b, c }), { a.id, b.id, c.id }), "net.invalid")
			expect.equal(refusal(box, { a.id, b.id, 9999 }), "inventory.notOwned")
			b.locked = true
			expect.equal(refusal(box, { a.id, b.id, c.id }), "pen.locked")
			b.locked = false
			c.form = 1
			expect.equal(refusal(box, { a.id, b.id, c.id }), "pen.fuseMismatch")
			c.form = 0
			c.kind = "banana"
			expect.equal(refusal(box, { a.id, b.id, c.id }), "pen.fuseMismatch")
			c.kind = "toast"
			for _, it in { a, b, c } do
				it.form = #PEN.formMult - 1
			end
			expect.equal(refusal(box, { a.id, b.id, c.id }), "pen.fuseTop")
		end
	)

	-- Pens3 phase 9: food and levels ----------------------------------------------------------------------------------

	local FOOD = Config.Economy.Food

	local function foodIds(list: { any }): { string }
		local out = {}
		for _, food in list do
			table.insert(out, food.id)
		end
		return out
	end

	t.test("feedCost: each step's food and pieces; every band's steps sum to the piece table", function()
		local candy, one = PenMath.feedCost(1)
		expect.equal((candy :: any).id, "candy_drop")
		expect.equal(one, 1)
		expect.equal(select(2, PenMath.feedCost(3)), 2)
		expect.equal(select(2, PenMath.feedCost(9)), 12) -- Lv 9 -> 10: the last Candy Drop step
		local bun, first = PenMath.feedCost(10)
		expect.equal((bun :: any).id, "butter_bun")
		expect.equal(first, 1)
		expect.equal(select(2, PenMath.feedCost(19)), 16)
		expect.equal((PenMath.feedCost(69) :: any).id, "halo_puff")
		for _, bad in { 0, PEN.maxLevel, 1.5, -1, 0 / 0, "3" } :: { any } do
			local none, zero = PenMath.feedCost(bad)
			expect.equal(none, nil)
			expect.equal(zero, 0)
		end
		-- A whole band, step by step (the piece table wins over V2's rounded 17K, 365K, 7.9M, 171M, 3.7B, 80B, 1.7T).
		local totals: { [string]: number } = {}
		for level = 1, PEN.maxLevel - 1 do
			local food, pieces = PenMath.feedCost(level)
			local def = food :: any
			totals[def.id] = (totals[def.id] or 0) + pieces * def.price
		end
		expect.deepEqual(totals, {
			candy_drop = 16_800,
			butter_bun = 371_200,
			boba_pearl_pop = 8_004_000,
			frosty_scoop = 174_000_000,
			lava_truffle = 3_770_000_000,
			prism_tart = 81_200_000_000,
			halo_puff = 1_740_000_000_000,
		})
	end)

	t.test(
		"levelCap: 10 a biome, biome 1 (Lv 10) until phase 13; foodsOnSale: the bands that start below it",
		function()
			expect.equal(PenMath.levelCap(), 10)
			expect.deepEqual(foodIds(PenMath.foodsOnSale(PenMath.levelCap())), { "candy_drop" })
			expect.deepEqual(foodIds(PenMath.foodsOnSale(20)), { "candy_drop", "butter_bun" })
			expect.equal(#PenMath.foodsOnSale(PEN.maxLevel), #FOOD.foods)
			expect.equal((PenMath.food("halo_puff") :: any).price, 30_000_000_000)
			expect.equal(PenMath.food("pizza"), nil)
			expect.equal(PenMath.foodCount({ candy_drop = 7 }, "candy_drop"), 7)
			for _, bad in { { candy_drop = -1 }, { candy_drop = 1.5 }, { candy_drop = "7" }, "x", false } :: { any } do
				expect.equal(PenMath.foodCount(bad, "candy_drop"), 0) -- broken counts as none
			end
		end
	)

	t.test("foodInside: the Coins of the food a squishy's levels took (the sell confirm's line)", function()
		expect.equal(PenMath.foodInside(item("toast")), 0)
		expect.equal(PenMath.foodInside(item("toast", 0, 4)), (1 + 1 + 2) * 400)
		expect.equal(PenMath.foodInside(item("toast", 0, 10)), 16_800)
		expect.equal(PenMath.foodInside(item("toast", 2, 12)), 16_800 + 2 * 6_400) -- the form adds nothing
		expect.equal(PenMath.foodInside("x"), 0)
	end)

	t.test("buyFoodDecision: the price is compared, never taken from the client; the refusals in order", function()
		local buy, code = PenMath.buyFoodDecision({ candy_drop = 3 }, "candy_drop", 5, 2_000, 10)
		expect.equal(code, nil)
		expect.equal((buy :: any).food.id, "candy_drop")
		expect.equal((buy :: any).count, 5)
		expect.equal((buy :: any).price, 2_000)
		local function refusal(food: any, id: any, count: any, price: any, cap: number?): string?
			local none, why = PenMath.buyFoodDecision(food, id, count, price, cap or 10)
			expect.equal(none, nil)
			return why
		end
		expect.equal(refusal({}, "pizza", 1, 400), "net.invalid")
		expect.equal(refusal({}, 5, 1, 400), "net.invalid")
		expect.equal(refusal({}, "candy_drop", 0, 0), "net.invalid")
		expect.equal(refusal({}, "candy_drop", 1.5, 600), "net.invalid")
		expect.equal(refusal({}, "candy_drop", FOOD.maxBuy + 1, 400 * (FOOD.maxBuy + 1)), "net.invalid")
		expect.equal(refusal({}, "candy_drop", 1, -1), "net.invalid")
		expect.equal(refusal({}, "butter_bun", 1, 6_400), "food.notYet") -- biome 1: only Candy Drop is sold
		expect.equal(refusal({ candy_drop = FOOD.maxPieces - 1 }, "candy_drop", 2, 800), "food.full")
		expect.equal(refusal({}, "candy_drop", 2, 400), "pen.priceChanged")
		expect.equal(refusal({}, "candy_drop", 1, 401), "pen.priceChanged")
		expect.equal((PenMath.buyFoodDecision({}, "butter_bun", 1, 6_400, 20) :: any).price, 6_400) -- biome 2
		expect.equal((PenMath.buyFoodDecision("x", "candy_drop", 1, 400, 10) :: any).count, 1) -- broken food: none
	end)

	t.test("feedDecision: one level of one owned squishy for its step's pieces; the refusals in order", function()
		local toast = at(0, item("toast", 0, 3)) -- a Toy Box squishy can be fed too
		local box = pen(3, { at(1, item("kitty_bread")), toast })
		local step, code = PenMath.feedDecision(box, { candy_drop = 2 }, toast.id, 10)
		expect.equal(code, nil)
		expect.equal((step :: any).item, toast)
		expect.equal((step :: any).food.id, "candy_drop")
		expect.equal((step :: any).pieces, 2)
		local function refusal(state: any, food: any, id: any, cap: number): string?
			local none, why = PenMath.feedDecision(state, food, id, cap)
			expect.equal(none, nil)
			return why
		end
		expect.equal(refusal(box, { candy_drop = 9 }, 1.5, 10), "net.invalid")
		expect.equal(refusal(pen(2, { toast }), { candy_drop = 9 }, toast.id, 10), "net.invalid") -- a broken pen
		expect.equal(refusal(box, { candy_drop = 9 }, 999, 10), "inventory.notOwned")
		expect.equal(refusal(box, { candy_drop = 1 }, toast.id, 10), "food.notEnough")
		expect.equal(refusal(box, { butter_bun = 9 }, toast.id, 10), "food.notEnough") -- the wrong food
		toast.level = 10
		expect.equal(refusal(box, { candy_drop = 99, butter_bun = 99 }, toast.id, 10), "pen.maxLevel")
		-- A higher cap (the biomes of phase 13) opens the next band.
		local bun = PenMath.feedDecision(box, { butter_bun = 1 }, toast.id, 20)
		expect.equal((bun :: any).food.id, "butter_bun")
		toast.level = PEN.maxLevel
		expect.equal(refusal(box, { halo_puff = 99 }, toast.id, PEN.maxLevel), "pen.maxLevel")
	end)

	t.test(
		"feedAllPlan: the pen only, the weakest first (level, coins/s, id), a level at a time, until the food runs out",
		function()
			local kitty = at(1, item("kitty_bread", 0, 2)) -- 10/s at Lv 1, here Lv 2
			local butter = at(2, item("butter")) -- 40/s
			local toast = at(3, item("toast")) -- 10/s
			local toy = at(0, item("banana")) -- the Toy Box: never fed by Feed All
			local box = pen(3, { kitty, butter, toast, toy })
			local plan = PenMath.feedAllPlan(box, { candy_drop = 1 }, 10)
			expect.deepEqual(plan.levels, { [toast.id] = 2 }) -- Lv 1, and fewer coins/s than the Butter
			expect.deepEqual(plan.used, { candy_drop = 1 })
			expect.equal(plan.steps, 1)
			plan = PenMath.feedAllPlan(box, { candy_drop = 4 }, 10)
			-- Toast 1 -> 2, Butter 1 -> 2, then all Lv 2: Kitty Bread (10/s, the lower id) 2 -> 3, Toast 2 -> 3.
			expect.deepEqual(plan.levels, { [toast.id] = 3, [butter.id] = 2, [kitty.id] = 3 })
			expect.deepEqual(plan.used, { candy_drop = 4 })
			expect.equal(plan.steps, 4)
			-- Plenty: everyone to the cap (Kitty Bread from Lv 2: 41 pieces; the others from Lv 1: 42 each), no more.
			plan = PenMath.feedAllPlan(box, { candy_drop = 1_000 }, 10)
			expect.deepEqual(plan.levels, { [kitty.id] = 10, [butter.id] = 10, [toast.id] = 10 })
			expect.deepEqual(plan.used, { candy_drop = 125 })
			expect.equal(plan.steps, 26)
			-- It stops when the food runs out: 5 pieces, Lv 4 -> 5 takes 3; 2 are left and each next step needs 3+.
			kitty.level, butter.level, toast.level = 4, 5, 6
			plan = PenMath.feedAllPlan(box, { candy_drop = 5 }, 10)
			expect.deepEqual(plan.levels, { [kitty.id] = 5 })
			expect.deepEqual(plan.used, { candy_drop = 3 })
			-- Nothing to feed: no food, everyone at the cap, a broken pen.
			expect.equal(PenMath.feedAllPlan(box, {}, 10).steps, 0)
			expect.equal(PenMath.feedAllPlan(box, { candy_drop = 9 }, 4).steps, 0)
			expect.deepEqual(PenMath.feedAllPlan(pen(2, { kitty }), { candy_drop = 9 }, 10).levels, {})
			-- The weakest that can eat: with no Candy Drop for the Lv 9 ones, the Lv 12 Butter still eats Butter Bun.
			kitty.level, butter.level, toast.level = 9, 12, 9
			plan = PenMath.feedAllPlan(box, { candy_drop = 5, butter_bun = 2 }, 20)
			expect.deepEqual(plan.levels, { [butter.id] = 13 })
			expect.deepEqual(plan.used, { butter_bun = 2 })
		end
	)
	-- Pens3 phase 11 (the shelf rows + the TOP spot) ------------------------------------------------------------------

	t.test("isOpen / openSlots: the pen's spots, 2 shelf spots a row from 13, the TOP spot 21 once bought", function()
		expect.deepEqual(PenMath.openSlots(shelfPen(3, 1, false, {})), { 1, 2, 3, 13, 14 }) -- the start row
		expect.deepEqual(PenMath.openSlots(pen(3, {})), { 1, 2, 3 }) -- no shelfRows (not sanitized): no shelf spot
		expect.deepEqual(PenMath.openSlots(shelfPen(4, 2, false, {})), { 1, 2, 3, 4, 13, 14, 15, 16 })
		local full = PenMath.openSlots(shelfPen(12, 4, true, {}))
		expect.equal(#full, 21)
		expect.equal(full[13], 13)
		expect.equal(full[20], 20)
		expect.equal(full[21], 21)
		local box = shelfPen(3, 1, false, {})
		expect.equal(PenMath.isOpen(box, 3), true)
		expect.equal(PenMath.isOpen(box, 4), false) -- a pen spot not bought
		expect.equal(PenMath.isOpen(box, 14), true)
		expect.equal(PenMath.isOpen(box, 15), false) -- row 2 not bought
		expect.equal(PenMath.isOpen(box, 21), false) -- the TOP spot not bought
		expect.equal(PenMath.isOpen(shelfPen(3, 1, true, {}), 21), true)
		for _, bad in { 0, 22, 12.5, -1, 0 / 0, "13" } :: { any } do
			expect.equal(PenMath.isOpen(shelfPen(12, 4, true, {}), bad), false)
		end
		-- Fail closed: a broken shelfRows opens no shelf spot (nor the TOP spot), a broken pen nothing.
		for _, rows in { 0, 5, 1.5, "2", 0 / 0, false } :: { any } do
			expect.deepEqual(PenMath.openSlots(shelfPen(3, rows, true, {})), { 1, 2, 3 })
		end
		expect.deepEqual(PenMath.openSlots(shelfPen(3, 1, "yes", {})), { 1, 2, 3, 13, 14 }) -- top must be true
		expect.deepEqual(PenMath.openSlots(pen(2, {})), {})
		expect.deepEqual(PenMath.openSlots(nil), {})
	end)

	t.test("placed: the pen, then the shelf, then the TOP spot, in slot order; inPen / onShelf split them", function()
		local kitty = at(1, item("kitty_bread"))
		local dragon = at(21, item("dragon")) -- the TOP spot
		local bird = at(14, item("bird"))
		local toast = at(13, item("toast"))
		local banana = at(15, item("banana")) -- row 2: closed until bought
		local box = shelfPen(3, 1, true, { dragon, bird, kitty, toast, banana })
		expect.deepEqual(PenMath.placed(box), { kitty, toast, bird, dragon })
		expect.deepEqual(PenMath.inPen(box), { kitty })
		expect.deepEqual(PenMath.onShelf(box), { toast, bird, dragon })
		box.top = false
		expect.deepEqual(PenMath.placed(box), { kitty, toast, bird }) -- the TOP spot is not bought
		box.shelfRows = 2
		expect.deepEqual(PenMath.onShelf(box), { toast, bird, banana })
		expect.deepEqual(PenMath.inPen(nil), {})
		expect.deepEqual(PenMath.onShelf(pen(2, { toast })), {})
	end)

	t.test("rate, squeezeValue and Feed All count the shelf and the TOP spot like the pen", function()
		local kitty = at(1, item("kitty_bread"))
		local dragon = at(21, item("dragon")) -- 640/s on the TOP spot
		local butter = at(13, item("butter")) -- 40/s on the shelf
		local box = shelfPen(3, 1, true, { kitty, dragon, butter })
		expect.equal(PenMath.rate(box), 10 + 640 + 40)
		expect.equal(PenMath.squeezeValue(box), 690)
		box.top = false
		expect.equal(PenMath.rate(box), 50) -- an unbought TOP spot earns nothing
		box.top = true
		local plan = PenMath.feedAllPlan(box, { candy_drop = 3 }, 10)
		expect.deepEqual(plan.levels, { [kitty.id] = 2, [butter.id] = 2, [dragon.id] = 2 })
	end)

	t.test("freeSlot fills the pen, then the shelf, then the TOP spot; room counts every open spot", function()
		local items = { at(1, item("kitty_bread")), at(2, item("toast")), at(3, item("toast")) }
		local box = shelfPen(3, 1, false, items)
		expect.equal(PenMath.freeSlot(box), 13)
		table.insert(items, at(13, item("toast")))
		expect.equal(PenMath.freeSlot(box), 14)
		table.insert(items, at(14, item("toast")))
		expect.equal(PenMath.freeSlot(box), 0)
		box.top = true
		expect.equal(PenMath.freeSlot(box), 21)
		items[2].slot = 0
		expect.equal(PenMath.freeSlot(box), 2) -- a free pen spot first
		-- room: 3 pen + 2 shelf + 1 TOP + toyBoxMax, less the 5 items.
		expect.equal(PenMath.room(box), 3 + 2 + 1 + PEN.toyBoxMax - 5)
		box.shelfRows, box.top = 4, false
		expect.equal(PenMath.room(box), 3 + 8 + PEN.toyBoxMax - 5)
		expect.equal(PenMath.room(shelfPen(12, 4, true, {})), PEN.placedMax + PEN.toyBoxMax)
	end)

	t.test(
		"placeDecision on the shelf: into a shelf spot, swaps with the pen, put away; closed spots refused",
		function()
			local kitty = at(1, item("kitty_bread"))
			local toast = at(13, item("toast"))
			local banana = at(0, item("banana"))
			local box = shelfPen(3, 1, false, { kitty, toast, banana })
			expect.deepEqual(PenMath.placeDecision(box, banana.id, 14), { id = banana.id, from = 0, to = 14 })
			expect.deepEqual(
				PenMath.placeDecision(box, kitty.id, 13),
				{ id = kitty.id, from = 1, to = 13, swapId = toast.id }
			)
			expect.deepEqual(PenMath.placeDecision(box, toast.id, 0), { id = toast.id, from = 13, to = 0 })
			expect.deepEqual(PenMath.placeDecision(box, toast.id, 2), { id = toast.id, from = 13, to = 2 })
			local _, closed = PenMath.placeDecision(box, banana.id, 15) -- row 2 not bought
			expect.equal(closed, "pen.spotClosed")
			local _, noTop = PenMath.placeDecision(box, banana.id, 21) -- the TOP spot not bought
			expect.equal(noTop, "pen.spotClosed")
			box.top = true
			expect.deepEqual(PenMath.placeDecision(box, banana.id, 21), { id = banana.id, from = 0, to = 21 })
			-- A squishy left in a slot that is not open counts as the Toy Box's (from 0), like a closed pen spot.
			local stray = at(17, item("toast"))
			table.insert(box.items, stray)
			expect.deepEqual(PenMath.placeDecision(box, stray.id, 14), { id = stray.id, from = 0, to = 14 })
			-- A fusion keeper on the shelf counts as placed (a level tie keeps the placed one).
			local g1 = at(0, item("butter", 1, 4))
			local g2 = at(14, item("butter", 1, 4))
			local g3 = at(0, item("butter", 1, 4))
			local fused = PenMath.fuseDecision(shelfPen(3, 1, false, { g1, g2, g3 }), { g1.id, g2.id, g3.id }) :: any
			expect.equal(fused.keeper, g2)
		end
	)

	t.test("shelfPrice / shelfDecision: row 2, 3, 4 (31M, 250B, 11T), then the TOP spot (140T), then max", function()
		local box = shelfPen(3, 1, false, {}) -- row 1 is open from the start
		expect.equal(PenMath.shelfPrice(box), 31_000_000)
		expect.deepEqual(
			PenMath.shelfDecision(box, 31_000_000),
			{ row = 2, top = false, price = 31_000_000, slots = { 15, 16 } }
		)
		box.shelfRows = 2
		expect.deepEqual(
			PenMath.shelfDecision(box, 250_000_000_000),
			{ row = 3, top = false, price = 250_000_000_000, slots = { 17, 18 } }
		)
		box.shelfRows = 3
		expect.deepEqual(
			PenMath.shelfDecision(box, 11_000_000_000_000),
			{ row = 4, top = false, price = 11_000_000_000_000, slots = { 19, 20 } }
		)
		box.shelfRows = 4
		expect.equal(PenMath.shelfPrice(box), 140_000_000_000_000)
		expect.deepEqual(
			PenMath.shelfDecision(box, 140_000_000_000_000),
			{ top = true, price = 140_000_000_000_000, slots = { 21 } }
		)
		box.top = true
		expect.equal(PenMath.shelfPrice(box), nil)
		local function refusal(state: any, price: any): string?
			local buy, code = PenMath.shelfDecision(state, price)
			expect.equal(buy, nil)
			return code
		end
		expect.equal(refusal(box, 140_000_000_000_000), "pen.shelfMax")
		-- The price is compared, never taken: an old price (a retry after the buy) is refused.
		expect.equal(refusal(shelfPen(3, 2, false, {}), 31_000_000), "pen.priceChanged")
		expect.equal(refusal(shelfPen(3, 4, false, {}), 11_000_000_000_000), "pen.priceChanged")
		-- Rows first: a pen with the TOP spot but row 3 still sells row 4.
		expect.equal((PenMath.shelfDecision(shelfPen(3, 3, true, {}), 11_000_000_000_000) :: any).row, 4)
		for _, bad in { -1, 1.5, 0 / 0, "31000000", Config.Economy.maxCoins + 1 } :: { any } do
			expect.equal(refusal(shelfPen(3, 1, false, {}), bad), "net.invalid")
		end
		expect.equal(refusal(nil, 31_000_000), "net.invalid")
		expect.equal(refusal(pen(2, {}), 31_000_000), "net.invalid") -- a broken pen
		expect.equal(refusal(shelfPen(3, 9, false, {}), 31_000_000), "net.invalid") -- broken rows
		expect.equal(refusal(pen(3, {}), 31_000_000), "net.invalid") -- no shelfRows (not sanitized)
		expect.equal(PenMath.shelfPrice(shelfPen(3, 9, false, {})), nil)
	end)

	t.test("encodeShelf / decodeShelf: slot=kind.form.level.coat joined by ';'; junk entries skipped", function()
		local list = { at(13, item("toast", 1, 4, 2)), at(21, item("dragon", 2, 70, 7)) }
		local text = PenMath.encodeShelf(list)
		expect.equal(text, "13=toast.1.4.2;21=dragon.2.70.7")
		local back = PenMath.decodeShelf(text)
		expect.deepEqual(back[13], { kind = "toast", form = 1, level = 4, coat = 2 })
		expect.deepEqual(back[21], { kind = "dragon", form = 2, level = 70, coat = 7 })
		expect.deepEqual(PenMath.decodeShelf(""), {})
		expect.deepEqual(PenMath.decodeShelf(nil), {})
		local junk =
			PenMath.decodeShelf("13=toast.0.1.0;x=toast.0.1.0;5=toast.0.1.0;22=toast.0.1.0;14=unicorn.0.1.0;15")
		expect.deepEqual(junk, { [13] = { kind = "toast", form = 0, level = 1, coat = 0 } }) -- shelf slots only
	end)
end
