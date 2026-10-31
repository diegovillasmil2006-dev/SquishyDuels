--!strict
-- PenMath_Test: unit tests for ReplicatedStorage.Shared.PenMath (pens3 phase 1). Server only (ServerStorage.UnitTest).
-- Contract (work/pens3/PLAN.md phase 1, "Tests"): an item earns coinsPerPower × squishy power × form × coating ×
-- levelGain^(level - 1) Coins a second (Kitty Bread 10, Butter 40, Bird 160, Dragon 640); the pen places its best
-- `spots` items (rate high first, a tie to the lower id); the squeeze value is the placed items' rate, never below 10
-- (nil or a broken pen: 10), and an own squeeze's Grip is its floor; spot prices are the J table (4 = 1,500 ..
-- 12 = 5.6T), nil for any other spot; a buy is the next spot at its exact price; the tick pays whole Coins and carries
-- the rest, at most maxTickSeconds of time at once; rewardCoins = floor(squeezes × value) clamped to maxCoins; the
-- base attribute text round-trips. Phase 4: awayCoins = floor(5% ×
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
-- next form at its level, and every input's coating is listed for the bag.
-- Phase 11 (the shelf rows + the TOP spot, V3:144-151; Neon Sugar part 5: one cubby a row): the open spots are the
-- pen's 1..spots, the shelf's 13.. (one a row, shelfRows rows, 2 from the start; a missing or broken shelfRows opens no
-- shelf spot: fail closed) and the TOP spot 24 once bought; placed lists them all in slot order (they all earn: rate, squeeze value, Feed All, a fusion
-- keeper), inPen / onShelf split them; freeSlot fills the pen, then the shelf, then the TOP spot; room counts every
-- open spot; placeDecision moves into, out of and between them (a closed shelf spot or an unbought TOP spot is
-- pen.spotClosed); shelfPrice / shelfDecision sell cubby 3 .. 11 at 300M .. 190T, then the TOP spot at 1Qa, then
-- pen.shelfMax (a wrong price pen.priceChanged, bad input or a broken pen net.invalid); encodeShelf / decodeShelf
-- carry each shelf squishy's slot and look.
-- Wb (owner 2026-10-17: the pen is the whole base): walkArea(studs) is the pen's floor (Bases.pen.walk: Diego's
-- WalkArea since Neon Sugar part 4, no blocks in it), half the squishy and edgeMargin in from the floor's edges and out
-- round every block; walkable says a point is on that floor and in no block; clearPath that the straight line between
-- two such points crosses no block's inside (touching its edge is fine). A squishy standing on any walkable point stays
-- on the floor, and the floor it has is bigger than the old biggest pen.

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

	-- Wb (owner 2026-10-17): the whole base is the pen; the squishies walk its floor round the blocks.
	local WorldLayout = t.requireShared("World/WorldLayout")
	local LAYOUT = WorldLayout.Bases.pen

	t.test("walkArea: the pen's floor (Diego's WalkArea), half the squishy and the edge margin in; no blocks", function()
		local area = PenMath.walkArea(2) -- a Common: 1 + 0.8 in from every edge
		local walk = LAYOUT.walk
		expect.near(area.minX, walk.minX + 1.8, 1e-9)
		expect.near(area.maxX, walk.maxX - 1.8, 1e-9)
		expect.near(area.minZ, walk.minZ + 1.8, 1e-9)
		expect.near(area.maxZ, walk.maxZ - 1.8, 1e-9)
		expect.equal(#area.blocks, 0) -- nothing stands inside his walk area
		local dragon = PenMath.walkArea(5) -- an Exclusive: 2.5 + 0.8
		expect.near(dragon.maxX, walk.maxX - 3.3, 1e-9)
		-- The area's middle is always walkable (a new walker's fallback spot, PenController.newWalk).
		for _, studs in { 2, 2.8, 3.8, 5 } do
			local a = PenMath.walkArea(studs)
			expect.truthy(PenMath.walkable(a, (a.minX + a.maxX) / 2, (a.minZ + a.maxZ) / 2))
		end
	end)

	t.test("walkable / clearPath: on the floor and in no block; a straight line that crosses no block", function()
		local area: any = {
			minX = 0,
			maxX = 10,
			minZ = 0,
			maxZ = 10,
			blocks = { { minX = 4, maxX = 6, minZ = 4, maxZ = 6 } },
		}
		expect.truthy(PenMath.walkable(area, 1, 1))
		expect.truthy(PenMath.walkable(area, 0, 10)) -- the floor's edge is on it
		expect.falsy(PenMath.walkable(area, 5, 5)) -- in the block
		expect.truthy(PenMath.walkable(area, 4, 5)) -- on its edge
		expect.falsy(PenMath.walkable(area, -0.1, 5)) -- off the floor
		expect.falsy(PenMath.walkable(area, 5, 10.1))
		expect.truthy(PenMath.clearPath(area, 1, 1, 9, 1)) -- below the block
		expect.falsy(PenMath.clearPath(area, 1, 5, 9, 5)) -- through it
		expect.falsy(PenMath.clearPath(area, 1, 1, 9, 9)) -- across its corner, diagonally
		expect.truthy(PenMath.clearPath(area, 1, 4, 9, 4)) -- along its edge
		expect.truthy(PenMath.clearPath(area, 6, 1, 6, 9))
		expect.truthy(PenMath.clearPath(area, 2, 2, 2, 2)) -- standing still
		-- No blocks (a walk area of a test): every line on the floor is clear.
		local open: any = { minX = 0, maxX = 10, minZ = 0, maxZ = 10 }
		expect.truthy(PenMath.walkable(open, 5, 5))
		expect.truthy(PenMath.clearPath(open, 0, 0, 10, 10))
	end)

	t.test("the whole pen: a squishy anywhere it may stand stays on the floor and has room", function()
		local walk = LAYOUT.walk
		for _, studs in { 2, 2.8, 3.8, 5 } do
			local area = PenMath.walkArea(studs)
			local free = 0
			for x = -21, 21, 0.25 do
				for z = -27, 27, 0.25 do
					if PenMath.walkable(area, x, z) then
						free += 0.25 * 0.25
						local h = studs / 2
						local out = x - h < walk.minX or x + h > walk.maxX
						if out or z - h < walk.minZ or z + h > walk.maxZ then
							error(`a {studs}-stud squishy at ({x}, {z}) pokes out of the pen's floor`)
						end
					end
				end
			end
			-- The old biggest pen was 24 × 32 less the same margins: Diego's pen gives more room.
			local m = studs + 2 * LAYOUT.edgeMargin
			expect.truthy(free > (24 - m) * (32 - m))
		end
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

	-- Pens3 phase 7 (selling + the 10-minute buy-back) -------------------------------------------------------------

	t.test(
		"sellPrice: Common 900, Uncommon 150K, Epic 90M, Dragon 225B; Golden x3, Rainbow x9; level and coat free",
		function()
			expect.equal(PenMath.sellPrice(item("toast")), 900) -- owner 2026-10-31: under the 1K Welcome price
			expect.equal(PenMath.sellPrice(item("butter")), 150_000)
			expect.equal(PenMath.sellPrice(item("mochi_fox")), 150_000) -- Uncommon until the Rare tier (phase 22)
			expect.equal(PenMath.sellPrice(item("bird")), 90_000_000)
			expect.equal(PenMath.sellPrice(item("dragon")), 225_000_000_000)
			expect.equal(PenMath.sellPrice(item("toast", 1)), 2_700)
			expect.equal(PenMath.sellPrice(item("toast", 2)), 8_100)
			expect.equal(PenMath.sellPrice(item("dragon", 2)), 2_025_000_000_000)
			expect.equal(PenMath.sellPrice(item("toast", 0, 9, 3)), 900) -- food and coatings are not refunded
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
		expect.equal(sale.coins, 900)
		list[2].form = 1 -- a Golden Toast still counts as a Toast copy (every form counts)
		local two = PenMath.sellDecision(box, { list[3].id }) :: any
		expect.equal(two.coins, 900)
		local both = PenMath.sellDecision(
			pen(3, {
				at(1, item("kitty_bread")),
				at(0, item("toast")),
				at(0, item("toast")),
				at(0, item("toast", 1)),
			}),
			{ nextId - 2, nextId - 1 }
		) :: any
		expect.equal(both.coins, 1_800)
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
			expect.equal(sale.coins, 3 * 900 + 150_000 + 2 * 90_000_000)
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
		"levelCap: 10 a biome reached (profile.highway.biome, pens3 phase 13); foodsOnSale: the bands below it",
		function()
			expect.equal(PenMath.levelCap({ best = 0, biome = 1 }), 10)
			expect.equal(PenMath.levelCap({ best = 900, biome = 3 }), 30)
			expect.equal(PenMath.levelCap({ best = 8500, biome = 8 }), PEN.maxLevel) -- the Golden Gates: 80, at most 70
			local brokens = { false, "x", { biome = 0 }, { biome = 2.5 }, { biome = 0 / 0 }, { best = 900 } } :: { any }
			for _, broken in brokens do
				expect.equal(PenMath.levelCap(broken), 10) -- fails closed: biome 1
			end
			expect.deepEqual(foodIds(PenMath.foodsOnSale(PenMath.levelCap(nil))), { "candy_drop" })
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
	-- Pens3 phase 11 (the shelf rows + the TOP spot; Neon Sugar part 5: one cubby a row, 2 open at the start) ----------

	t.test("isOpen / openSlots: the pen's spots, one shelf spot a row from 13, the TOP spot 24 once bought", function()
		expect.deepEqual(PenMath.openSlots(shelfPen(3, 2, false, {})), { 1, 2, 3, 13, 14 }) -- the start rows
		expect.deepEqual(PenMath.openSlots(pen(3, {})), { 1, 2, 3 }) -- no shelfRows (not sanitized): no shelf spot
		expect.deepEqual(PenMath.openSlots(shelfPen(4, 4, false, {})), { 1, 2, 3, 4, 13, 14, 15, 16 })
		local full = PenMath.openSlots(shelfPen(12, 11, true, {}))
		expect.equal(#full, 24)
		expect.equal(full[13], 13)
		expect.equal(full[23], 23)
		expect.equal(full[24], 24)
		local box = shelfPen(3, 2, false, {})
		expect.equal(PenMath.isOpen(box, 3), true)
		expect.equal(PenMath.isOpen(box, 4), false) -- a pen spot not bought
		expect.equal(PenMath.isOpen(box, 14), true)
		expect.equal(PenMath.isOpen(box, 15), false) -- cubby 3 not bought
		expect.equal(PenMath.isOpen(box, 24), false) -- the TOP spot not bought
		expect.equal(PenMath.isOpen(shelfPen(3, 2, true, {}), 24), true)
		for _, bad in { 0, 25, 12.5, -1, 0 / 0, "13" } :: { any } do
			expect.equal(PenMath.isOpen(shelfPen(12, 11, true, {}), bad), false)
		end
		-- Fail closed: a broken shelfRows opens no shelf spot (nor the TOP spot), a broken pen nothing.
		for _, rows in { 0, 1, 12, 1.5, "2", 0 / 0, false } :: { any } do
			expect.deepEqual(PenMath.openSlots(shelfPen(3, rows, true, {})), { 1, 2, 3 })
		end
		expect.deepEqual(PenMath.openSlots(shelfPen(3, 2, "yes", {})), { 1, 2, 3, 13, 14 }) -- top must be true
		expect.deepEqual(PenMath.openSlots(pen(2, {})), {})
		expect.deepEqual(PenMath.openSlots(nil), {})
	end)

	t.test("placed: the pen, then the shelf, then the TOP spot, in slot order; inPen / onShelf split them", function()
		local kitty = at(1, item("kitty_bread"))
		local dragon = at(24, item("dragon")) -- the TOP spot
		local bird = at(14, item("bird"))
		local toast = at(13, item("toast"))
		local banana = at(15, item("banana")) -- cubby 3: closed until bought
		local box = shelfPen(3, 2, true, { dragon, bird, kitty, toast, banana })
		expect.deepEqual(PenMath.placed(box), { kitty, toast, bird, dragon })
		expect.deepEqual(PenMath.inPen(box), { kitty })
		expect.deepEqual(PenMath.onShelf(box), { toast, bird, dragon })
		box.top = false
		expect.deepEqual(PenMath.placed(box), { kitty, toast, bird }) -- the TOP spot is not bought
		box.shelfRows = 3
		expect.deepEqual(PenMath.onShelf(box), { toast, bird, banana })
		expect.deepEqual(PenMath.inPen(nil), {})
		expect.deepEqual(PenMath.onShelf(pen(2, { toast })), {})
	end)

	t.test("rate, squeezeValue and Feed All count the shelf and the TOP spot like the pen", function()
		local kitty = at(1, item("kitty_bread"))
		local dragon = at(24, item("dragon")) -- 640/s on the TOP spot
		local butter = at(13, item("butter")) -- 40/s on the shelf
		local box = shelfPen(3, 2, true, { kitty, dragon, butter })
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
		local box = shelfPen(3, 2, false, items)
		expect.equal(PenMath.freeSlot(box), 13)
		table.insert(items, at(13, item("toast")))
		expect.equal(PenMath.freeSlot(box), 14)
		table.insert(items, at(14, item("toast")))
		expect.equal(PenMath.freeSlot(box), 0)
		box.top = true
		expect.equal(PenMath.freeSlot(box), 24)
		items[2].slot = 0
		expect.equal(PenMath.freeSlot(box), 2) -- a free pen spot first
		-- room: 3 pen + 2 shelf + 1 TOP + toyBoxMax, less the 5 items.
		expect.equal(PenMath.room(box), 3 + 2 + 1 + PEN.toyBoxMax - 5)
		box.shelfRows, box.top = 11, false
		expect.equal(PenMath.room(box), 3 + 11 + PEN.toyBoxMax - 5)
		expect.equal(PenMath.room(shelfPen(12, 11, true, {})), PEN.placedMax + PEN.toyBoxMax)
	end)

	t.test(
		"placeDecision on the shelf: into a shelf spot, swaps with the pen, put away; closed spots refused",
		function()
			local kitty = at(1, item("kitty_bread"))
			local toast = at(13, item("toast"))
			local banana = at(0, item("banana"))
			local box = shelfPen(3, 2, false, { kitty, toast, banana })
			expect.deepEqual(PenMath.placeDecision(box, banana.id, 14), { id = banana.id, from = 0, to = 14 })
			expect.deepEqual(
				PenMath.placeDecision(box, kitty.id, 13),
				{ id = kitty.id, from = 1, to = 13, swapId = toast.id }
			)
			expect.deepEqual(PenMath.placeDecision(box, toast.id, 0), { id = toast.id, from = 13, to = 0 })
			expect.deepEqual(PenMath.placeDecision(box, toast.id, 2), { id = toast.id, from = 13, to = 2 })
			local _, closed = PenMath.placeDecision(box, banana.id, 15) -- cubby 3 not bought
			expect.equal(closed, "pen.spotClosed")
			local _, noTop = PenMath.placeDecision(box, banana.id, 24) -- the TOP spot not bought
			expect.equal(noTop, "pen.spotClosed")
			box.top = true
			expect.deepEqual(PenMath.placeDecision(box, banana.id, 24), { id = banana.id, from = 0, to = 24 })
			-- A squishy left in a slot that is not open counts as the Toy Box's (from 0), like a closed pen spot.
			local stray = at(17, item("toast"))
			table.insert(box.items, stray)
			expect.deepEqual(PenMath.placeDecision(box, stray.id, 14), { id = stray.id, from = 0, to = 14 })
			-- A fusion keeper on the shelf counts as placed (a level tie keeps the placed one).
			local g1 = at(0, item("butter", 1, 4))
			local g2 = at(14, item("butter", 1, 4))
			local g3 = at(0, item("butter", 1, 4))
			local fused = PenMath.fuseDecision(shelfPen(3, 2, false, { g1, g2, g3 }), { g1.id, g2.id, g3.id }) :: any
			expect.equal(fused.keeper, g2)
		end
	)

	t.test("arrange (qb1): the best to the TOP spot, the shelf, then the pen; locks and the Toy Box stay", function()
		local kitty = at(1, item("kitty_bread")) -- 10/s
		local butter = at(2, item("butter")) -- 40/s
		local bird = at(3, item("bird")) -- 160/s
		local dragon = at(13, item("dragon")) -- 640/s
		local toast = at(0, item("toast")) -- the Toy Box: never moved
		local box = shelfPen(3, 2, false, { kitty, butter, bird, dragon, toast })
		expect.equal(PenMath.arrange(box), 3)
		expect.deepEqual(
			{ dragon.slot, bird.slot, butter.slot, kitty.slot, toast.slot },
			{ 13, 14, 1, 2, 0 } -- the 2 start cubbies hold the best two, the pen the rest (free spots last)
		)
		expect.equal(PenMath.arrange(box), 0) -- already sorted: nothing moves
		-- The TOP spot opens: the best goes up there, the next ones follow.
		box.top = true
		expect.equal(PenMath.arrange(box), 4)
		expect.deepEqual({ dragon.slot, bird.slot, butter.slot, kitty.slot }, { 24, 13, 14, 1 })
		-- A locked one keeps its spot; the others sort around it.
		kitty.slot, kitty.locked = 24, true
		dragon.slot = 2
		expect.equal(PenMath.arrange(box), 3)
		expect.deepEqual({ kitty.slot, dragon.slot, bird.slot, butter.slot }, { 24, 13, 14, 1 })
		-- Selling the TOP squishy leaves no hole up there: the next best climbs, the pen gives one up.
		kitty.locked = false
		box.items = { kitty, butter, bird, toast }
		dragon.slot = 0
		PenMath.arrange(box)
		expect.deepEqual({ bird.slot, butter.slot, kitty.slot }, { 24, 13, 14 })
		-- Only slots change: every item once, every open spot held by at most one.
		local seen = {}
		for _, it in box.items do
			if it.slot ~= 0 then
				expect.equal(seen[it.slot], nil)
				seen[it.slot] = true
			end
		end
		expect.equal(#box.items, 4)
		-- A broken pen moves nothing.
		expect.equal(PenMath.arrange(nil), 0)
		expect.equal(PenMath.arrange(pen(2, { at(1, item("dragon")) })), 0)
	end)

	t.test("shelfPrice / shelfDecision: cubby 3 .. 11 one at a time (300M .. 190T), the TOP spot (1Qa), max", function()
		-- Neon Sugar part 5 (owner 2026-10-24): each about x5 the last.
		local prices = {
			[3] = 300_000_000,
			[4] = 1_600_000_000,
			[5] = 8_400_000_000,
			[6] = 45_000_000_000,
			[7] = 240_000_000_000,
			[8] = 1_300_000_000_000,
			[9] = 6_700_000_000_000,
			[10] = 36_000_000_000_000,
			[11] = 190_000_000_000_000,
		}
		expect.deepEqual(PEN.shelfRowPrices, prices)
		expect.equal(PEN.topPrice, 1_000_000_000_000_000)
		local box = shelfPen(3, 2, false, {}) -- cubbies 1-2 are open from the start
		for row = 3, 11 do
			expect.equal(PenMath.shelfPrice(box), prices[row])
			expect.deepEqual(
				PenMath.shelfDecision(box, prices[row]),
				{ row = row, top = false, price = prices[row], slots = { 12 + row } }
			)
			box.shelfRows = row
		end
		expect.equal(PenMath.shelfPrice(box), 1_000_000_000_000_000)
		expect.deepEqual(
			PenMath.shelfDecision(box, 1_000_000_000_000_000),
			{ top = true, price = 1_000_000_000_000_000, slots = { 24 } }
		)
		box.top = true
		expect.equal(PenMath.shelfPrice(box), nil)
		local function refusal(state: any, price: any): string?
			local buy, code = PenMath.shelfDecision(state, price)
			expect.equal(buy, nil)
			return code
		end
		expect.equal(refusal(box, 1_000_000_000_000_000), "pen.shelfMax")
		-- The price is compared, never taken: an old price (a retry after the buy) is refused.
		expect.equal(refusal(shelfPen(3, 3, false, {}), 300_000_000), "pen.priceChanged")
		expect.equal(refusal(shelfPen(3, 11, false, {}), 190_000_000_000_000), "pen.priceChanged")
		-- Cubbies first: a pen with the TOP spot but 10 cubbies still sells cubby 11.
		expect.equal((PenMath.shelfDecision(shelfPen(3, 10, true, {}), 190_000_000_000_000) :: any).row, 11)
		for _, bad in { -1, 1.5, 0 / 0, "300000000", Config.Economy.maxCoins + 1 } :: { any } do
			expect.equal(refusal(shelfPen(3, 2, false, {}), bad), "net.invalid")
		end
		expect.equal(refusal(nil, 300_000_000), "net.invalid")
		expect.equal(refusal(pen(2, {}), 300_000_000), "net.invalid") -- a broken pen
		expect.equal(refusal(shelfPen(3, 12, false, {}), 300_000_000), "net.invalid") -- broken rows
		expect.equal(refusal(pen(3, {}), 300_000_000), "net.invalid") -- no shelfRows (not sanitized)
		expect.equal(PenMath.shelfPrice(shelfPen(3, 12, false, {})), nil)
	end)

	t.test("encodeShelf / decodeShelf: slot=kind.form.level.coat joined by ';'; junk entries skipped", function()
		local list = { at(13, item("toast", 1, 4, 2)), at(24, item("dragon", 2, 70, 7)) }
		local text = PenMath.encodeShelf(list)
		expect.equal(text, "13=toast.1.4.2;24=dragon.2.70.7")
		local back = PenMath.decodeShelf(text)
		expect.deepEqual(back[13], { kind = "toast", form = 1, level = 4, coat = 2 })
		expect.deepEqual(back[24], { kind = "dragon", form = 2, level = 70, coat = 7 })
		expect.deepEqual(PenMath.decodeShelf(""), {})
		expect.deepEqual(PenMath.decodeShelf(nil), {})
		local junk =
			PenMath.decodeShelf("13=toast.0.1.0;x=toast.0.1.0;5=toast.0.1.0;25=toast.0.1.0;14=unicorn.0.1.0;15")
		expect.deepEqual(junk, { [13] = { kind = "toast", form = 0, level = 1, coat = 0 } }) -- shelf slots only
	end)

	-- INCOME step 1 (2026-10-26; Config.Economy.Income, the owner's curve C) ------------------------------------------

	local INCOME_COINS = {
		500_000,
		1_600_000,
		5_100_000,
		16_000_000,
		52_000_000,
		170_000_000,
		540_000_000,
		1_700_000_000,
		5_500_000_000,
		18_000_000_000,
		56_000_000_000,
		180_000_000_000,
		580_000_000_000,
		1_800_000_000_000,
		5_900_000_000_000,
		19_000_000_000_000,
		60_000_000_000_000,
		190_000_000_000_000,
		620_000_000_000_000,
		2_000_000_000_000_000,
	}
	local INCOME_ALL = {
		2_500_000,
		7_500_000,
		23_000_000,
		68_000_000,
		200_000_000,
		610_000_000,
		1_800_000_000,
		5_500_000_000,
		16_000_000_000,
		49_000_000_000,
		150_000_000_000,
		440_000_000_000,
		1_300_000_000_000,
		4_000_000_000_000,
		12_000_000_000_000,
		36_000_000_000_000,
		110_000_000_000_000,
		320_000_000_000_000,
		970_000_000_000_000,
		2_900_000_000_000_000,
	}

	-- A pen with its squishies placed and the INCOME levels bought.
	local function incomePen(coins: any, all: any, items: { any }): any
		local p = placedPen(3, items)
		p.income = { coins = coins, all = all }
		return p
	end

	t.test("income: 20 levels a line at the owner's prices (curve C); nil outside", function()
		for level, price in INCOME_COINS do
			expect.equal(PenMath.incomePrice("coins", level), price)
		end
		for level, price in INCOME_ALL do
			expect.equal(PenMath.incomePrice("all", level), price)
		end
		for _, bad in { 0, 21, 1.5, -1, 0 / 0, "1" } :: { any } do
			expect.equal(PenMath.incomePrice("coins", bad), nil)
		end
		expect.equal(PenMath.incomePrice("gear", 1), nil)
		local Validate = t.requireShared("Config/ValidateIncome")
		expect.deepEqual(Validate(Config), {})
		local economy = table.clone(Config.Economy)
		economy.Income = {
			coins = { boost = 1.07, prices = { 2, 1 } }, -- falls
			all = { boost = 1, prices = { 1.5 } }, -- boosts nothing, not whole Coins
		}
		expect.truthy(#Validate({ Economy = economy }) >= 3)
	end)

	t.test("income: COINS x1.07 and ALL x1.05 a level on the pen's rate; only ALL on the squeeze value", function()
		expect.near(PenMath.incomeMult(incomePen(1, 0, {}), "coins"), 1.07, 1e-12)
		expect.near(PenMath.incomeMult(incomePen(20, 0, {}), "coins"), 1.07 ^ 20, 1e-9)
		expect.near(PenMath.incomeMult(incomePen(0, 20, {}), "all"), 1.05 ^ 20, 1e-9)
		-- None saved, broken or negative counts as none, past the last as the last, a fraction is cut.
		expect.equal(PenMath.incomeMult(placedPen(3, {}), "coins"), 1)
		expect.equal(PenMath.incomeMult(incomePen("x", -3, {}), "coins"), 1)
		expect.equal(PenMath.incomeMult(incomePen(0, -3, {}), "all"), 1)
		expect.near(PenMath.incomeMult(incomePen(99, 0, {}), "coins"), 1.07 ^ 20, 1e-9)
		expect.near(PenMath.incomeMult(incomePen(2.9, 0, {}), "coins"), 1.07 ^ 2, 1e-12)
		-- The rate: both lines (the pen, the shelf, the away rate DataService stamps).
		local dragon = incomePen(2, 3, { item("dragon") })
		expect.near(PenMath.rate(dragon), 640 * 1.07 ^ 2 * 1.05 ^ 3, 1e-6)
		-- The squeeze value (squeezes, duels, matches, the highway, Grip): ALL only, on top of the floor of 10.
		expect.near(PenMath.squeezeValue(dragon), 640 * 1.05 ^ 3, 1e-6)
		expect.near(PenMath.squeezeValue(incomePen(5, 2, {})), 10 * 1.05 ^ 2, 1e-9)
		expect.equal(PenMath.squeezeGrip(incomePen(0, 2, { item("dragon") })), math.floor(640 * 1.05 ^ 2))
		-- None bought: as before.
		expect.equal(PenMath.rate(incomePen(0, 0, { item("dragon") })), 640)
		expect.equal(PenMath.squeezeValue(incomePen(0, 0, { item("dragon") })), 640)
		-- INCOME step 2: the rate's boost alone (the coin labels over each squishy and the pen cards use it).
		expect.near(PenMath.rateBoost(dragon), 1.07 ^ 2 * 1.05 ^ 3, 1e-12)
		expect.equal(PenMath.rateBoost(nil), 1)
	end)

	t.test("incomeDecision: the next level and its price, or net.invalid / pen.incomeMax / pen.priceChanged", function()
		expect.deepEqual(
			PenMath.incomeDecision(incomePen(0, 0, {}), "coins", 500_000),
			{ line = "coins", level = 1, price = 500_000 }
		)
		expect.deepEqual(
			PenMath.incomeDecision(incomePen(0, 4, {}), "all", 200_000_000),
			{ line = "all", level = 5, price = 200_000_000 }
		)
		-- A pen with no income saved yet (sanitize gives every saved pen one) counts as none bought.
		expect.deepEqual(
			PenMath.incomeDecision(placedPen(3, {}), "all", 2_500_000),
			{ line = "all", level = 1, price = 2_500_000 }
		)
		local function refused(p: any, line: any, price: any, code: string)
			local decision, why = PenMath.incomeDecision(p, line, price)
			expect.equal(decision, nil)
			expect.equal(why, code)
		end
		refused(incomePen(0, 0, {}), "gear", 500_000, "net.invalid")
		refused(incomePen(0, 0, {}), "coins", -1, "net.invalid")
		refused(incomePen(0, 0, {}), "coins", 1.5, "net.invalid")
		refused("garbage", "coins", 500_000, "net.invalid")
		refused(incomePen(20, 0, {}), "coins", 1, "pen.incomeMax")
		refused(incomePen(0, 0, {}), "coins", 499_999, "pen.priceChanged")
	end)
end
