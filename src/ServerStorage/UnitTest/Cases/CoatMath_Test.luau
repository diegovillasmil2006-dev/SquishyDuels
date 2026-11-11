--!strict
-- CoatMath_Test: unit tests for ReplicatedStorage.Shared.CoatMath and Config/Coats (big job item 10, 2026-11-10: the
-- 7 coatings a squishy can wear). Server only (ServerStorage.UnitTest). Pure.
-- Contract:
--   * 7 coatings, one for each Config.Economy.Pen.coatMult boost after "none", in the design's order (Wax, Glitter,
--     Jelly, Frost, Chrome, Neon, Galaxy), each with a zone (never falling), a rising whole price and a look (a real
--     Material, Reflectance and Transparency in 0..1);
--   * a coating can be bought once its zone is reached; one in the bag is free to put on;
--   * decision(pen, bag, biome, itemId, coat, expectedPrice): the change, or net.invalid / inventory.notOwned /
--     coat.same / coat.zoneLocked / pen.priceChanged; coat 0 takes the coating off, for free;
--   * zoneGift(from, to): one of each coating whose zone (3 or later) lies after `from` up to `to`;
--   * next(coat, bag, biome): the pen window's step up: the bag's best better coating (free), else the next coating
--     up at its price, locked while its zone is not reached; nil for the last coating.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local CoatMath = t.requireShared("CoatMath")
	local COATS = t.requireShared("Config/Coats").list
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local PEN = Config.Economy.Pen

	local function pen(coat: number): any
		return {
			spots = 3,
			nextId = 3,
			items = {
				{ id = 1, kind = "kitty_bread", form = 0, level = 1, coat = coat, slot = 1, locked = false },
				{ id = 2, kind = "kitty_bread", form = 0, level = 1, coat = 0, slot = 0, locked = false },
			},
		}
	end

	t.test("7 coatings in the design's order: a zone, a rising price, a real look, a name", function()
		expect.equal(CoatMath.COUNT, 7)
		expect.equal(#PEN.coatMult, CoatMath.COUNT + 1) -- one boost for each, after "none"
		expect.equal(#Strings.coat.names, CoatMath.COUNT)
		local ids = {}
		local lastZone, lastPrice = 0, 0
		for coat, def in COATS do
			ids[coat] = def.id
			expect.truthy(def.zone >= lastZone and def.zone >= 1 and def.zone <= 7)
			expect.truthy(def.price > lastPrice and math.floor(def.price) == def.price)
			expect.truthy(def.price <= Config.Economy.maxCoins)
			lastZone, lastPrice = def.zone, def.price
			expect.truthy((Enum.Material :: any)[def.look.material] ~= nil)
			expect.truthy(def.look.reflectance >= 0 and def.look.reflectance <= 1)
			expect.truthy(def.look.transparency >= 0 and def.look.transparency < 1)
			expect.equal(CoatMath.def(coat), def)
			local sparkle = def.look.sparkle -- the design's shared look sparkle: 1 to 3 a second a squishy
			if sparkle then
				expect.truthy(#sparkle.colors >= 1 and sparkle.rate >= 1 and sparkle.rate <= 3)
			end
			expect.equal(sparkle ~= nil, coat == 2 or coat == 4 or coat == 7) -- Glitter, Frost, Galaxy
		end
		expect.deepEqual(ids, { "wax", "glitter", "jelly", "frost", "chrome", "neon", "galaxy" })
		expect.equal(COATS[1].zone, 1) -- Wax and Glitter: plain shop items
		expect.equal(COATS[2].zone, 1)
		expect.equal(COATS[7].zone, 7) -- Galaxy: Divine Heaven
		for _, bad in { 0, 8, 1.5, "1", 0 / 0 } :: { any } do
			expect.equal(CoatMath.def(bad), nil)
		end
	end)

	t.test("the bag's count and whether a coating can be bought yet", function()
		expect.equal(CoatMath.inBag({ 0, 2, 0, 0, 0, 0, 0 }, 2), 2)
		expect.equal(CoatMath.inBag({ 0, 2 }, 5), 0)
		expect.equal(CoatMath.inBag({ -1, "x", 1.5 }, 1), 0)
		expect.equal(CoatMath.inBag({ -1, "x", 1.5 }, 2), 0)
		expect.equal(CoatMath.inBag({ -1, "x", 1.5 }, 3), 0)
		expect.equal(CoatMath.inBag(nil, 1), 0)
		expect.equal(CoatMath.open(1, 1), true)
		expect.equal(CoatMath.open(3, 2), false)
		expect.equal(CoatMath.open(3, 3), true)
		expect.equal(CoatMath.open(7, 8), true) -- the Golden Gates are past every zone
		expect.equal(CoatMath.open(9, 8), false)
		expect.equal(CoatMath.open(1, nil), false)
	end)

	t.test("decision: bought at its price, free from the bag, free to take off; refusals in order", function()
		local none = table.create(CoatMath.COUNT, 0)
		local wax = COATS[1].price
		expect.deepEqual(CoatMath.decision(pen(0), none, 1, 1, 1, wax), { coat = 1, price = wax, fromBag = false })
		-- one in the bag: free, whatever the zone
		local bag = table.clone(none)
		bag[5] = 1
		expect.deepEqual(CoatMath.decision(pen(0), bag, 1, 1, 5, 0), { coat = 5, price = 0, fromBag = true })
		-- taking a coating off is free
		expect.deepEqual(CoatMath.decision(pen(2), none, 1, 1, 0, 0), { coat = 0, price = 0, fromBag = false })
		-- a squishy in the Toy Box can be coated too
		expect.deepEqual(CoatMath.decision(pen(0), none, 1, 2, 1, wax), { coat = 1, price = wax, fromBag = false })
		local function refused(p: any, b: any, biome: any, id: any, coat: any, price: any, code: string)
			local change, why = CoatMath.decision(p, b, biome, id, coat, price)
			expect.equal(change, nil)
			expect.equal(why, code)
		end
		refused(pen(0), none, 1, 1.5, 1, wax, "net.invalid")
		refused(pen(0), none, 1, 1, 8, wax, "net.invalid")
		refused(pen(0), none, 1, 1, -1, 0, "net.invalid")
		refused(pen(0), none, 1, 1, 1, "x", "net.invalid")
		refused(pen(0), none, 1, 99, 1, wax, "inventory.notOwned")
		refused("garbage", none, 1, 1, 1, wax, "inventory.notOwned")
		refused(pen(1), none, 1, 1, 1, wax, "coat.same")
		refused(pen(0), none, 1, 1, 0, 0, "coat.same") -- nothing to take off
		refused(pen(0), none, 2, 1, 3, COATS[3].price, "coat.zoneLocked") -- Jelly needs Boba Lagoon
		refused(pen(0), none, 1, 1, 1, wax - 1, "pen.priceChanged")
		refused(pen(0), bag, 1, 1, 5, COATS[5].price, "pen.priceChanged") -- from the bag it is free
		refused(pen(2), none, 1, 1, 0, 5, "pen.priceChanged")
	end)

	t.test("zoneGift: one of each zone's coating from zone 3 on, for the zones reached first", function()
		expect.deepEqual(CoatMath.zoneGift(1, 2), {}) -- Wax and Glitter are shop items
		expect.deepEqual(CoatMath.zoneGift(1, 3), { 3 }) -- Boba Lagoon: Jelly
		expect.deepEqual(CoatMath.zoneGift(3, 3), {})
		expect.deepEqual(CoatMath.zoneGift(2, 5), { 3, 4, 5 }) -- a long throw through three new zones
		expect.deepEqual(CoatMath.zoneGift(6, 8), { 7 }) -- Divine Heaven and the Gates: Galaxy
		expect.deepEqual(CoatMath.zoneGift(7, 8), {})
	end)

	t.test("next: the best better coating in the bag for free, else the next one up; locked before its zone", function()
		local none = table.create(CoatMath.COUNT, 0)
		local function check(coat: any, bag: any, biome: any, want: any, wantLocked: boolean)
			local step, locked = CoatMath.next(coat, bag, biome)
			expect.deepEqual(step, want)
			expect.equal(locked, wantLocked)
		end
		check(0, none, 1, { coat = 1, price = COATS[1].price, fromBag = false }, false)
		check(1, none, 1, { coat = 2, price = COATS[2].price, fromBag = false }, false) -- Glitter: a shop item too
		check(2, none, 2, { coat = 3, price = COATS[3].price, fromBag = false }, true) -- Jelly waits for Boba Lagoon
		check(2, none, 3, { coat = 3, price = COATS[3].price, fromBag = false }, false)
		-- the bag first: its best coating above the worn one, whatever the zone
		check(0, { 2, 0, 0, 1, 0, 1, 0 }, 1, { coat = 6, price = 0, fromBag = true }, false)
		check(6, { 2, 0, 0, 1, 0, 1, 0 }, 1, { coat = 7, price = COATS[7].price, fromBag = false }, true) -- none better
		check(7, { 2, 2, 2, 2, 2, 2, 2 }, 8, nil, false) -- Galaxy is the last one
		-- a broken coat number or bag reads as bare and empty
		check("x", "garbage", 1, { coat = 1, price = COATS[1].price, fromBag = false }, false)
		check(0, none, nil, { coat = 1, price = COATS[1].price, fromBag = false }, true)
	end)
end
