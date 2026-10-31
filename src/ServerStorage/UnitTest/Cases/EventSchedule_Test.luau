--!strict
-- EventSchedule_Test: ReplicatedStorage.Shared.EventSchedule (the timed events' clock and candy rules). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (2026-10-31, owner: candy rain, "Yes, build it"):
--   * an event starts every 15 minutes on the UTC clock and runs 5; the pill counts down to it, then the time left;
--   * a candy pays 10 s of the grabber's pen Coins a second, at least 100;
--   * 30 candies per player fall evenly over the event; spots stay inside the ring;
--   * the nearest player within the grab radius gets a candy, nobody farther;
--   * double coins (owner: "Pen + playing") pays 2x for the pen, squeezes, duels, matches, throws and candy only;
--   * the shop restock (owner "both", "Premium"): 2 Golden offers at 3x (the first Rainbow at 6x on some restocks),
--     2 rare offers at 30% off, the same for every server; the stock as a string the client reads back.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local EventSchedule = t.requireShared("EventSchedule")
	local EVENTS = t.requireShared("Config/Events")
	local CANDY = EVENTS.CandyRain
	local LOOP = EVENTS.loopSeconds -- 900
	local BASE = 1_000 * LOOP -- a loop start on the clock (1000 % 4 == 0: candy rain's turn, on the hour)

	t.test("owner's timing: an event every 15 minutes, 5 minutes long", function()
		expect.equal(LOOP, 900)
		expect.equal(EVENTS.liveSeconds, 300)
		expect.equal(CANDY.penSeconds, 10)
		expect.equal(CANDY.perPlayer, 30)
	end)

	-- BASE is candy rain's loop; the next one golden luck, then double coins, then the shop restock (they take turns).
	local GOLDEN = BASE + LOOP
	local DOUBLE = BASE + 2 * LOOP
	local RESTOCK = BASE + 3 * LOOP

	t.test("at: live for the first 5 minutes of a loop, then waiting for the next one", function()
		local live = EventSchedule.at(BASE + 10)
		expect.equal(live.live, true)
		expect.equal(live.startsAt, BASE)
		expect.equal(live.endsAt, BASE + 300)
		expect.equal(live.kind, "candyRain")
		expect.equal(EventSchedule.at(GOLDEN + 10).kind, "goldenLuck")
		expect.equal(EventSchedule.at(DOUBLE + 10).kind, "doubleCoins")
		expect.equal(EventSchedule.at(RESTOCK + 10).kind, "shopRestock")
		expect.equal(EventSchedule.at(RESTOCK + LOOP + 10).kind, "candyRain")
		local waiting = EventSchedule.at(BASE + 300)
		expect.equal(waiting.live, false)
		expect.equal(waiting.startsAt, BASE + LOOP)
		expect.equal(waiting.index, live.index + 1)
	end)

	t.test("pillText: the countdown while waiting, the time left while live", function()
		expect.equal(EventSchedule.pillText(BASE + 300), "Golden luck in 10:00") -- the next one takes its turn
		expect.equal(EventSchedule.pillText(GOLDEN + 300), "Double coins in 10:00")
		expect.equal(EventSchedule.pillText(DOUBLE + 300), "Shop restock in 10:00")
		expect.equal(EventSchedule.pillText(RESTOCK + 300), "Candy rain in 10:00")
		expect.equal(EventSchedule.pillText(RESTOCK + 79), "SHOP RESTOCK! 3:41")
		expect.equal(EventSchedule.pillText(DOUBLE - 1), "Double coins in 0:01")
		expect.equal(EventSchedule.pillText(DOUBLE + 79), "DOUBLE COINS! 3:41")
		expect.equal(EventSchedule.pillText(BASE + 79), "CANDY RAIN! 3:41")
	end)

	t.test("candyCoins: 10 s of the pen, at least 100; a broken rate pays the least", function()
		expect.equal(EventSchedule.candyCoins(10), 100)
		expect.equal(EventSchedule.candyCoins(2_500), 25_000)
		expect.equal(EventSchedule.candyCoins(0), 100)
		expect.equal(EventSchedule.candyCoins(0 / 0), 100)
	end)

	t.test("candiesDue: 30 a player spread over the event, never negative", function()
		expect.equal(EventSchedule.candiesDue(2, 0, 0), 0)
		expect.equal(EventSchedule.candiesDue(2, 150, 0), 30) -- half the event, half of 60
		expect.equal(EventSchedule.candiesDue(2, 150, 28), 2)
		expect.equal(EventSchedule.candiesDue(2, 300, 0), 60)
		expect.equal(EventSchedule.candiesDue(2, 999, 60), 0) -- capped at the event's end
		expect.equal(EventSchedule.candiesDue(1, 150, 40), 0) -- a player left: no catch-up below zero
	end)

	t.test("ringPoint: every spot is inside the ring around the Monument", function()
		for _, uv in { { 0, 0 }, { 0.25, 0.999 }, { 0.5, 0.5 }, { 0.99, 0.01 } } do
			local x, z = EventSchedule.ringPoint(uv[1], uv[2])
			local r = Vector2.new(x - CANDY.centre.X, z - CANDY.centre.Z).Magnitude
			expect.truthy(r >= CANDY.innerRadius - 1e-6 and r <= CANDY.outerRadius + 1e-6)
		end
	end)

	t.test("boxForm: golden luck gives Rainbow 1 in 100, Golden 1 in 10; nothing outside it", function()
		expect.equal(EVENTS.GoldenLuck.rainbowChance, 0.01)
		expect.equal(EVENTS.GoldenLuck.goldenChance, 0.10)
		local function rolls(value: number): () -> number
			return function(): number
				return value
			end
		end
		expect.equal(EventSchedule.boxForm(GOLDEN + 10, rolls(0.005)), 2)
		expect.equal(EventSchedule.boxForm(GOLDEN + 10, rolls(0.05)), 1)
		expect.equal(EventSchedule.boxForm(GOLDEN + 10, rolls(0.109)), 1)
		expect.equal(EventSchedule.boxForm(GOLDEN + 10, rolls(0.12)), 0)
		-- Outside golden luck no roll is taken, so the box draws stay exactly as before.
		local rolled = false
		local function spy(): number
			rolled = true
			return 0
		end
		expect.equal(EventSchedule.boxForm(GOLDEN + 400, spy), 0) -- golden luck is over
		expect.equal(EventSchedule.boxForm(BASE + 10, spy), 0) -- candy rain: no golden chance
		expect.equal(rolled, false)
	end)

	t.test("goldenOddsText: the odds line only while golden luck is live", function()
		expect.equal(EventSchedule.goldenOddsText(GOLDEN + 10), "Golden luck: 10% Golden, 1% Rainbow")
		expect.equal(EventSchedule.goldenOddsText(BASE + 10), nil)
		expect.equal(EventSchedule.pillText(GOLDEN + 79), "GOLDEN LUCK! 3:41")
	end)

	t.test("coinMult: double coins pays 2x for the pen and playing, nothing else, only while live", function()
		expect.equal(EVENTS.DoubleCoins.mult, 2)
		for _, reason in { "pen", "squeeze", "duel_win", "duel_loss", "duel_draw", "match", "highway", "event" } do
			expect.equal(EventSchedule.coinMult(DOUBLE + 10, reason), 2)
		end
		for _, reason in { "sell", "refund", "daily", "quest", "starter", "away", "robux", "debug" } do
			expect.equal(EventSchedule.coinMult(DOUBLE + 10, reason), 1)
		end
		expect.equal(EventSchedule.coinMult(DOUBLE + 300, "squeeze"), 1) -- over
		expect.equal(EventSchedule.coinMult(GOLDEN + 10, "squeeze"), 1) -- another event
	end)

	t.test("restockAt / nextStart: the restock's index only while it is live; the next start of a kind", function()
		local index = RESTOCK // LOOP
		expect.equal(EventSchedule.restockAt(RESTOCK + 10), index)
		expect.equal(EventSchedule.restockAt(RESTOCK + 300), nil)
		expect.equal(EventSchedule.restockAt(DOUBLE + 10), nil)
		expect.equal(EventSchedule.nextStart(BASE + 10, "shopRestock"), RESTOCK)
		expect.equal(EventSchedule.nextStart(RESTOCK + 10, "shopRestock"), RESTOCK) -- live: its own start
		expect.equal(EventSchedule.nextStart(RESTOCK + 300, "shopRestock"), RESTOCK + 4 * LOOP)
		expect.equal(EventSchedule.nextStart(BASE + 10, "nope"), math.huge)
	end)

	t.test("restockOffers: 2 Golden at 3x (a Rainbow at 6x, stock 1), 2 rare at 30% off; the same each call", function()
		local Catalog = t.requireShared("Catalog")
		local cfg = EVENTS.ShopRestock
		expect.equal(cfg.goldenPriceMult, 3) -- owner: "Premium"
		expect.equal(cfg.rainbowPriceMult, 6)
		local sawRainbow, sawPlain = false, false
		for index = 1, 200 do
			local offers = EventSchedule.restockOffers(index)
			expect.deepEqual(EventSchedule.restockOffers(index), offers) -- every server and client gets the same
			expect.equal(#offers, 4)
			for slot, offer in offers do
				local def = Catalog.get(offer.squishy)
				if slot <= 2 then
					expect.truthy(table.find(cfg.goldenRarities, def.rarity) ~= nil)
					if offer.deal == "rainbow" then
						expect.equal(slot, 1)
						expect.deepEqual({ offer.form, offer.price, offer.stock }, { 2, def.shopPrice * 6, 1 })
					else
						local got = { offer.deal, offer.form, offer.price, offer.stock }
						expect.deepEqual(got, { "golden", 1, def.shopPrice * 3, 3 })
					end
				else
					expect.truthy(table.find(cfg.rareRarities, def.rarity) ~= nil)
					expect.deepEqual({ offer.deal, offer.form, offer.stock }, { "rare", 0, 3 })
					expect.equal(offer.price, math.floor(def.shopPrice * 0.7))
				end
			end
			expect.truthy(offers[1].squishy ~= offers[2].squishy and offers[3].squishy ~= offers[4].squishy)
			sawRainbow = sawRainbow or offers[1].deal == "rainbow"
			sawPlain = sawPlain or offers[1].deal == "golden"
		end
		expect.truthy(sawRainbow and sawPlain)
	end)

	t.test("stockText / stockLeft: this restock's numbers; another restock or a broken text = the full stock", function()
		local offers = EventSchedule.restockOffers(7)
		local full = {}
		for i, offer in offers do
			full[i] = offer.stock
		end
		expect.equal(EventSchedule.stockText(7, { 3, 0, 2, 1 }), "7:3,0,2,1")
		expect.deepEqual(EventSchedule.stockLeft("7:3,0,2,1", 7, offers), { math.min(3, full[1]), 0, 2, 1 })
		expect.deepEqual(EventSchedule.stockLeft("6:0,0,0,0", 7, offers), full)
		expect.deepEqual(EventSchedule.stockLeft(nil, 7, offers), full)
		expect.deepEqual(EventSchedule.stockLeft("junk", 7, offers), full)
	end)

	t.test("grabber: the nearest root within the radius, nobody beyond it", function()
		local candy = Vector3.new(0, 1, 0)
		local roots = { a = Vector3.new(4, 3, 0), b = Vector3.new(2, 3, 0), c = Vector3.new(9, 3, 0) }
		expect.equal(EventSchedule.grabber(candy, roots, CANDY.grabRadius), "b")
		expect.equal(EventSchedule.grabber(candy, { c = roots.c }, CANDY.grabRadius), nil)
		expect.equal(EventSchedule.grabber(candy, {}, CANDY.grabRadius), nil)
	end)
end
