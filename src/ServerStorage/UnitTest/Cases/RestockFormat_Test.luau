--!strict
-- RestockFormat_Test: unit tests for StarterPlayer.StarterPlayerScripts.Client.UI.RestockFormat (2026-10-31 shop
-- restock: the shop's RESTOCK tab; owner "Yes, build it"). Pure.
-- Contract:
--   * cards(t, stockText, coins, busyLine?, bought): no cards while no restock is live; else one card per offer in the
--     gear card's shape: the squishy pictured, "Golden <name>" / "Rainbow <name>" / the name, the line (what it earns
--     or the discount, and the stock left), the price, the deal's colour; state max with SOLD OUT (none left) or BOUGHT
--     (bought[slot]), busy, needCoins (with the Coins missing) or buy;
--   * waitText(t): the countdown to the next restock.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local RestockFormat = t.requireClient("UI/RestockFormat")
	local EventSchedule = t.requireShared("EventSchedule")
	local EVENTS = t.requireShared("Config/Events")
	local LOOP = EVENTS.loopSeconds
	local RESTOCK = (4 * 1_000 + 3) * LOOP -- a restock's start (index % 4 == 3)
	local INDEX = RESTOCK // LOOP
	local RICH = 1e13

	t.test("no cards between restocks; the wait line counts down to the next one", function()
		expect.deepEqual(RestockFormat.cards(RESTOCK - 10, nil, RICH, nil, {}), {})
		expect.equal(
			RestockFormat.waitText(RESTOCK - 600),
			"Next restock in 10:00. Golden squishies and deals, first come!"
		)
	end)

	t.test("cards: the offers' names, lines, prices and the squishy on the tile", function()
		local offers = EventSchedule.restockOffers(INDEX)
		local cards = RestockFormat.cards(RESTOCK + 10, nil, RICH, nil, {})
		expect.equal(#cards, #offers)
		for slot, card in cards do
			local offer = offers[slot]
			expect.equal(card.line, tostring(slot))
			expect.equal(card.squishy, offer.squishy)
			expect.equal(card.price, offer.price)
			expect.equal(card.state, "buy")
			if offer.deal == "golden" then
				expect.truthy(string.find(card.name, "^Golden ") ~= nil)
				expect.equal(card.desc, `Earns 2x · {offer.stock} left`)
			elseif offer.deal == "rainbow" then
				expect.truthy(string.find(card.name, "^Rainbow ") ~= nil)
				expect.equal(card.desc, `Earns 4x · {offer.stock} left`)
			else
				expect.equal(card.desc, `30% off · {offer.stock} left`)
			end
		end
	end)

	t.test("states: SOLD OUT, BOUGHT, busy, and short of Coins with what is missing", function()
		local offers = EventSchedule.restockOffers(INDEX)
		local text = EventSchedule.stockText(INDEX, { 0, offers[2].stock, offers[3].stock, offers[4].stock })
		local cards = RestockFormat.cards(RESTOCK + 10, text, offers[3].price - 1, "4", { [2] = true })
		expect.deepEqual({ cards[1].state, cards[1].maxText }, { "max", "SOLD OUT" })
		expect.deepEqual({ cards[2].state, cards[2].maxText }, { "max", "BOUGHT" })
		expect.deepEqual({ cards[3].state, cards[3].missing }, { "needCoins", 1 })
		expect.equal(cards[4].state, "busy")
	end)
end
