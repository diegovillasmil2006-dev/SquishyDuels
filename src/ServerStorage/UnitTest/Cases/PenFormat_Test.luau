--!strict
-- PenFormat_Test: unit tests for StarterPlayerScripts.Client.UI.PenFormat (pens3 phase 6: the stand-in pen screen's
-- pure parts). Server only (ServerStorage.UnitTest). Contract (work/pens3/PLAN.md "PHASE 6"):
--   * view(pen, selectedId, picking): one card per open spot (its squishy or none), the Toy Box best first, the count
--     line (or, while picking, the hint naming the squishy), the selected squishy (none once it is gone), and its
--     actions: a pen squishy PUT AWAY (with the Toy Box full reason when full), MOVE and LOCK / UNLOCK; a Toy Box one
--     PLACE while a spot is free, else SWAP, and LOCK / UNLOCK; picking only CANCEL; nothing selected none;
--   * tap(view, slot?, itemId?): while picking a pen spot places the squishy there (an occupied one swaps on the
--     server); otherwise a squishy's card selects it; an empty spot does nothing;
--   * pickFor(pen, kind): the squishy of that kind the screen opens on (from the Squishies window): the pen's best
--     first, then the Toy Box's best; none for a kind not in the pen;
--   * walkerItem(pen, index, look): the pen squishy a tapped walker shows (the walkers follow the placed order, so
--     placed[index] when its look matches, else the first placed one with that look);
--   * cardText(item): the name, "+N/s" and "Lv N" of a card (phase 8: "Golden · Lv N" / "Rainbow · Lv N");
--   * pens3 phases 7-8 (selling, the buy-back, fusion): nothing selected offers SELL ALL (refused with its reason when
--     nothing can go), a squishy SELL after its other actions (refused with the server's reason: Kitty Bread, locked,
--     the last copy) and FUSE when 3 unlocked of its kind and form are there (fuseSet: it and the two worth least);
--     a confirm (sell, Sell All, buy-back, fuse) asks in the count line with the price, says the buy-back time (or the
--     balance after, or the fusion's result: form, level, +N/s, the coatings to the bag) in the hint and offers the
--     confirm and CANCEL; selling Golden, Rainbow, Lv 10+ or Epic+ is a hold (needsHold; holdFraction); the live
--     buy-back entries are sold cards newest first with their minutes, a sold card offers BUY BACK (refused when the
--     Toy Box is full or the Coins are short).
--   * pens3 phase 9 (food and levels): a squishy offers FEED last (refused at the top level, PenMath.levelCap, or
--     with the food it is short of) and its hint is its next step ("Lv N -> N+1: P <food>"; the top level says so);
--     nothing selected adds FEED ALL (refused when nothing can be fed); the food row lists what you own; the BUY FOOD
--     cards are the foods on sale (biome 1: Candy Drop) with their price and count, and a card offers BUY 1 / BUY 10
--     (refused with the missing Coins or a full stack); the sell confirm of a levelled squishy says its food is not
--     refunded; requestFor reuses a request id only for a retry of the same action.
--   * pens3 phase 11 (the shelf rows + the TOP spot): the shelf's open spots (13.., slot order) and the TOP spot (21,
--     once bought) are their own sections (shelf, top) with their headings ("On your shelf placed/open", "TOP spot");
--     the count line counts the pen's own spots; a shelf squishy is placed (PUT AWAY, MOVE, ...), a Toy Box one PLACEs
--     while any open spot is free (the shelf's too), and picking taps a shelf or TOP card to move there; walkerItem
--     maps a walker to the pen's own spots only; a pen with no shelfRows (never after sanitize) shows no shelf.
--   * wb (owner 2026-10-17): nothing selected also offers the shelf's BUY button (after SELL ALL and FEED ALL; the
--     SHELF SPOTS sign stays): "BUY ROW <price>" for the next row, then "BUY TOP <price>", carrying that price
--     (PenController sends PenBuyShelf with it); short of Coins it is refused with the missing Coins, once all is
--     open it reads SHELF MAX, refused with the server's pen.shelfMax text (the screen shows reasons on its reason
--     row, never inside a button: every label stays short); no button for a pen without a shelf or with a squishy
--     selected.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local PenFormat = t.requireClient("UI/PenFormat")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local PEN = Config.Economy.Pen
	local screen = Strings.pen.screen

	local function item(id: number, kind: string, slot: number, locked: boolean?, level: number?): any
		return { id = id, kind = kind, form = 0, level = level or 1, coat = 0, slot = slot, locked = locked == true }
	end

	-- Kitty Bread (1) in spot 1, Butter (2) in spot 3, Toast (3) and Bird (4) in the Toy Box; spot 2 empty.
	local function samplePen(): any
		return {
			spots = 3,
			nextId = 5,
			items = { item(1, "kitty_bread", 1), item(2, "butter", 3), item(3, "toast", 0), item(4, "bird", 0) },
		}
	end

	local function ids(list: { any }): { number }
		local out = {}
		for _, entry in list do
			table.insert(out, entry.id)
		end
		return out
	end

	local function actionIds(view: any): { string }
		local out = {}
		for _, action in view.actions do
			table.insert(out, action.id)
		end
		return out
	end

	t.test("view: a card per open spot, the Toy Box best first, the count line, nothing selected", function()
		local pen = samplePen()
		local view = PenFormat.view(pen, nil, false)
		expect.equal(#view.spots, 3)
		expect.equal(view.spots[1].slot, 1)
		expect.equal(view.spots[1].item.id, 1)
		expect.equal(view.spots[2].item, nil) -- the empty spot
		expect.equal(view.spots[3].item.id, 2)
		expect.deepEqual(ids(view.toys), { 4, 3 }) -- Bird (160) before Toast (10)
		expect.equal(
			view.status,
			Strings.format(screen.count, { placed = 2, spots = 3, toys = 2, max = PEN.toyBoxMax })
		)
		expect.equal(view.hint, screen.selectHint)
		expect.equal(view.selected, nil)
		expect.deepEqual(actionIds(view), { "sellAll", "feedAll" }) -- pens3 phases 7, 9
		-- No pen yet (no Snapshot): no cards; SELL ALL is refused (nothing to sell).
		local none = PenFormat.view(nil, 1, true)
		expect.deepEqual(none.spots, {})
		expect.deepEqual(none.toys, {})
		expect.equal(none.picking, false)
		expect.equal(none.actions[1].reason, Strings.reasonText("pen.nothingToSell"))
		-- An empty Toy Box says so.
		expect.equal(
			PenFormat.view({ spots = 3, nextId = 2, items = { item(1, "kitty_bread", 1) } }, nil, false).hint,
			screen.toyEmpty
		)
	end)

	t.test(
		"view actions: a pen squishy PUT AWAY / MOVE / LOCK; a Toy Box one PLACE or SWAP / LOCK; picking CANCEL",
		function()
			local pen = samplePen()
			local placed = PenFormat.view(pen, 1, false)
			expect.equal(placed.selected.id, 1)
			expect.deepEqual(actionIds(placed), { "putAway", "move", "lock", "sell", "feed" }) -- + SELL, FEED
			expect.equal(placed.actions[1].text, screen.putAway)
			expect.equal(placed.actions[1].kind, "primary")
			expect.equal(placed.actions[1].reason, nil)
			local toy = PenFormat.view(pen, 3, false)
			expect.deepEqual(actionIds(toy), { "place", "lock", "sell", "feed" }) -- spot 2 is free
			-- A full pen: SWAP instead of PLACE.
			pen.items[3].slot = 2
			local full = PenFormat.view(pen, 4, false)
			expect.deepEqual(actionIds(full), { "swap", "lock", "sell", "feed" })
			-- A locked one offers UNLOCK.
			pen.items[4].locked = true
			expect.deepEqual(actionIds(PenFormat.view(pen, 4, false)), { "swap", "unlock", "sell", "feed" })
			expect.equal(PenFormat.view(pen, 4, false).actions[2].text, screen.unlock)
			-- Picking: only CANCEL, and the hint names the squishy.
			local picking = PenFormat.view(pen, 4, true)
			expect.equal(picking.picking, true)
			expect.deepEqual(actionIds(picking), { "cancel" })
			expect.equal(picking.actions[1].text, Strings.common.cancel)
			expect.equal(
				picking.status,
				Strings.format(screen.pickHint, { name = PenFormat.cardText(pen.items[4]).name })
			)
			-- A selected id that is gone (sold, fused, another server): nothing selected, no picking.
			local gone = PenFormat.view(pen, 99, true)
			expect.equal(gone.selected, nil)
			expect.equal(gone.picking, false)
			expect.deepEqual(actionIds(gone), { "sellAll", "feedAll" })
		end
	)

	t.test("view: PUT AWAY carries the Toy Box full reason while the Toy Box holds toyBoxMax", function()
		local pen = { spots = 3, nextId = 100, items = { item(1, "kitty_bread", 1) } }
		for id = 2, PEN.toyBoxMax + 1 do
			table.insert(pen.items, item(id, "toast", 0))
		end
		local view = PenFormat.view(pen, 1, false)
		expect.equal(view.actions[1].id, "putAway")
		expect.equal(view.actions[1].reason, Strings.reasonText("inventory.full"))
	end)

	t.test(
		"tap: picking places on a pen spot; otherwise a card selects its squishy; an empty spot does nothing",
		function()
			local pen = samplePen()
			local picking = PenFormat.view(pen, 3, true)
			expect.deepEqual({ PenFormat.tap(picking, 2, nil) }, { "place", 3, 2 } :: { any })
			-- An occupied spot: the server swaps.
			expect.deepEqual({ PenFormat.tap(picking, 1, 1) }, { "place", 3, 1 } :: { any })
			-- A Toy Box card picks another squishy.
			expect.deepEqual({ PenFormat.tap(picking, nil, 4) }, { "select", 4 } :: { any })
			local resting = PenFormat.view(pen, 3, false)
			expect.deepEqual({ PenFormat.tap(resting, 1, 1) }, { "select", 1 } :: { any })
			expect.deepEqual({ PenFormat.tap(resting, nil, 4) }, { "select", 4 } :: { any })
			expect.deepEqual({ PenFormat.tap(resting, 2, nil) }, { "none" })
		end
	)

	t.test("pickFor: the pen's best of that kind first, then the Toy Box's; none for a kind not in the pen", function()
		local pen = {
			spots = 3,
			nextId = 9,
			items = {
				item(1, "toast", 0, false, 5), -- the Toy Box's best Toast
				item(2, "toast", 2), -- placed
				item(3, "toast", 0),
				item(4, "bird", 0),
			},
		}
		expect.equal(PenFormat.pickFor(pen, "toast"), 2)
		expect.equal(PenFormat.pickFor(pen, "bird"), 4)
		pen.items[2].slot = 0
		expect.equal(PenFormat.pickFor(pen, "toast"), 1)
		expect.equal(PenFormat.pickFor(pen, "dragon"), nil)
		expect.equal(PenFormat.pickFor(nil, "toast"), nil)
	end)

	t.test("walkerItem: placed[index] when its look matches, else the first placed one that looks the same", function()
		local pen = {
			spots = 3,
			nextId = 9,
			items = { item(1, "toast", 2), item(2, "kitty_bread", 1), item(3, "toast", 3) },
		}
		-- The walkers follow the placed order: Kitty Bread (spot 1), Toast (2), Toast (3).
		local look = { kind = "toast", form = 0, level = 1, coat = 0 }
		expect.equal(PenFormat.walkerItem(pen, 3, look), 3)
		expect.equal(PenFormat.walkerItem(pen, 2, look), 1)
		expect.equal(PenFormat.walkerItem(pen, 1, look), 1) -- a stale index: the first Toast
		expect.equal(PenFormat.walkerItem(pen, 1, { kind = "dragon", form = 0, level = 1, coat = 0 }), nil)
		expect.equal(PenFormat.walkerItem(nil, 1, look), nil)
	end)

	t.test("cardText: the name, +N/s and Lv N", function()
		local text = PenFormat.cardText(item(1, "butter", 1, false, 2))
		expect.equal(text.name, Strings.resolve("squishy.butter.name"))
		expect.equal(text.rate, "+46/s") -- 40 × 1.15
		expect.equal(text.level, "Lv 2")
	end)

	-- Pens3 phases 7-8: selling, the buy-back and fusion -------------------------------------------------------------

	local NOW = 1_800_000_000
	local Format = t.requireShared("Util/Format")
	local MINUTES = math.ceil(PEN.buyBackSeconds / 60)

	-- Kitty Bread (1) in spot 1, Toasts 2 (spot 2), 3 and 4 (Toy Box), one Butter (5, Toy Box), one Bird (6, Toy Box).
	local function shopPen(): any
		return {
			spots = 3,
			nextId = 7,
			items = {
				item(1, "kitty_bread", 1),
				item(2, "toast", 2),
				item(3, "toast", 0),
				item(4, "toast", 0),
				item(5, "butter", 0),
				item(6, "bird", 0),
			},
		}
	end

	local function sold(id: number, kind: string, price: number, age: number): any
		return { item = item(id, kind, 0), price = price, at = NOW - age, req = "r" }
	end

	t.test("needsHold: Golden, Rainbow, Lv 10 and up, Epic and up must be held to sell (D1:222)", function()
		expect.falsy(PenFormat.needsHold(item(1, "toast", 0)))
		expect.falsy(PenFormat.needsHold(item(1, "butter", 0, false, 9)))
		expect.truthy(PenFormat.needsHold(item(1, "toast", 0, false, 10)))
		expect.truthy(PenFormat.needsHold(item(1, "bird", 0)))
		expect.truthy(PenFormat.needsHold(item(1, "dragon", 0)))
		local golden = item(1, "toast", 0)
		golden.form = 1
		expect.truthy(PenFormat.needsHold(golden))
	end)

	t.test(
		"view: SELL ALL with nothing selected (refused with its reason when nothing can go); SELL on a squishy",
		function()
			local pen = shopPen()
			local idle = PenFormat.view(pen, nil, false)
			expect.deepEqual(actionIds(idle), { "sellAll", "feedAll" })
			expect.equal(idle.actions[1].text, screen.sellAll)
			expect.equal(idle.actions[1].reason, nil) -- Toasts 3 and 4 can go
			local nothing = PenFormat.view(samplePen(), nil, false)
			expect.equal(nothing.actions[1].reason, Strings.reasonText("pen.nothingToSell"))
			-- A squishy: SELL after its other actions, refused with the server's reason where it would be.
			-- 3 Toasts: FUSE; then FEED (pens3 phase 9).
			expect.deepEqual(actionIds(PenFormat.view(pen, 3, false)), { "place", "lock", "sell", "fuse", "feed" })
			expect.equal(PenFormat.view(pen, 3, false).actions[3].reason, nil)
			expect.equal(PenFormat.view(pen, 1, false).actions[4].reason, Strings.reasonText("pen.sellStarter"))
			expect.equal(PenFormat.view(pen, 5, false).actions[3].reason, Strings.reasonText("pen.lastCopy"))
			pen.items[3].locked = true
			expect.equal(PenFormat.view(pen, 3, false).actions[3].reason, Strings.reasonText("pen.locked"))
		end
	)

	t.test(
		"view: the sell confirm asks with the price and the buy-back time; a hold for Golden / Lv 10 / Epic",
		function()
			local pen = shopPen()
			local view = PenFormat.view(pen, 3, false, { confirm = "sell" })
			expect.equal(view.confirm, "sell")
			expect.deepEqual(view.sellIds, { 3 })
			expect.equal(
				view.status,
				Strings.format(
					screen.confirmSell,
					{ name = PenFormat.cardText(pen.items[3]).name, coins = Format.coins(1_000) }
				)
			)
			expect.equal(view.hint, Strings.format(screen.sellNote, { minutes = MINUTES }))
			expect.deepEqual(actionIds(view), { "confirm", "cancel" })
			expect.equal(view.actions[1].text, screen.sell)
			expect.equal(view.actions[1].hold, nil)
			table.insert(pen.items, item(7, "bird", 0)) -- a second Bird: one may go (an Epic: held)
			local bird = PenFormat.view(pen, 6, false, { confirm = "sell" })
			expect.equal(bird.actions[1].text, screen.holdSell)
			expect.equal(bird.actions[1].hold, true)
			-- A sell confirm with nothing to sell (Kitty Bread) does not open.
			expect.equal(PenFormat.view(pen, 1, false, { confirm = "sell" }).confirm, nil)
		end
	)

	t.test("view: the Sell All confirm counts what goes and says what stays; a hold when an Epic goes", function()
		local pen = shopPen()
		local view = PenFormat.view(pen, nil, false, { confirm = "sellAll" })
		expect.deepEqual(view.sellIds, { 3, 4 }) -- the placed Toast, the last Butter and the last Bird stay
		local all = screen.confirmSellAll
		expect.equal(
			view.status,
			Strings.format(Strings.plural(2, all.one, all.many), { n = 2, coins = Format.coins(2_000) })
		)
		expect.equal(view.hint, Strings.format(screen.sellAllNote, { minutes = MINUTES }))
		expect.equal(view.actions[1].hold, nil)
		table.insert(pen.items, item(7, "bird", 0))
		expect.equal(PenFormat.view(pen, nil, false, { confirm = "sellAll" }).actions[1].hold, true)
		expect.equal(PenFormat.view(samplePen(), nil, false, { confirm = "sellAll" }).confirm, nil)
	end)

	t.test(
		"view: sold cards newest first with their minutes; a sold card offers BUY BACK, its confirm the balance",
		function()
			local pen = shopPen()
			local list = {
				sold(20, "toast", 1_000, 120),
				sold(21, "butter", 150_000, 30),
				sold(22, "toast", 1_000, PEN.buyBackSeconds),
			}
			local view = PenFormat.view(pen, nil, false, { buyBack = list, now = NOW, coins = 5_000 })
			expect.deepEqual(ids(view.sold), { 21, 20 }) -- the expired one is gone
			expect.equal(view.sold[1].price, 150_000)
			expect.equal(view.sold[1].time, Strings.format(screen.soldTime, { minutes = MINUTES })) -- 9.5 min: 10
			expect.equal(view.sold[2].time, Strings.format(screen.soldTime, { minutes = MINUTES - 2 }))
			expect.equal(view.soldHeading, screen.soldHeading)
			expect.equal(PenFormat.view(pen, nil, false).soldHeading, nil) -- nothing sold
			local picked = PenFormat.view(pen, nil, false, { buyBack = list, now = NOW, coins = 5_000, soldId = 20 })
			expect.equal(picked.soldSelected.id, 20)
			expect.deepEqual(actionIds(picked), { "buyBack" })
			expect.equal(picked.actions[1].reason, nil)
			local poor = PenFormat.view(pen, nil, false, { buyBack = list, now = NOW, coins = 5_000, soldId = 21 })
			expect.equal(
				poor.actions[1].reason,
				Strings.format(Strings.plural(145_000, Strings.common.needCoins.one, Strings.common.needCoins.many), {
					missing = Format.coins(145_000),
				})
			)
			local confirm = PenFormat.view(
				pen,
				nil,
				false,
				{ buyBack = list, now = NOW, coins = 5_000, soldId = 20, confirm = "buyBack" }
			)
			expect.equal(
				confirm.status,
				Strings.format(
					screen.confirmBuyBack,
					{ name = Strings.resolve("squishy.toast.name"), coins = Format.coins(1_000) }
				)
			)
			expect.equal(confirm.hint, Strings.format(Strings.spend.balanceAfter, { balance = Format.coins(4_000) }))
			expect.deepEqual(actionIds(confirm), { "confirm", "cancel" })
			expect.equal(confirm.actions[1].text, screen.buyBack)
			-- A sold card that expired meanwhile is no longer selected.
			expect.equal(PenFormat.view(pen, nil, false, { buyBack = list, now = NOW, soldId = 22 }).soldSelected, nil)
		end
	)

	t.test("fuseSet and FUSE: 3 unlocked of one kind and form; the selected one and the two least worth", function()
		local pen = shopPen()
		pen.items[3].level = 5
		expect.deepEqual(PenFormat.fuseSet(pen, 3), { 3, 2, 4 }) -- the selected one, then the two others
		expect.equal(PenFormat.fuseSet(pen, 5), nil) -- one Butter
		table.insert(pen.items, item(7, "toast", 0, false, 9))
		expect.deepEqual(PenFormat.fuseSet(pen, 2), { 2, 3, 4 }) -- the Lv 9 one is kept out
		pen.items[4].locked = true
		expect.deepEqual(PenFormat.fuseSet(pen, 2), { 2, 7, 3 })
		expect.equal(PenFormat.fuseSet(pen, 4), nil) -- locked itself
		expect.deepEqual(actionIds(PenFormat.view(pen, 3, false)), { "place", "lock", "sell", "fuse", "feed" })
		for _, it in pen.items do
			if it.kind == "toast" then
				it.form = 2
			end
		end
		expect.equal(PenFormat.fuseSet(pen, 2), nil) -- Rainbow is the top
	end)

	t.test(
		"view: the fuse confirm shows the result first (name, form, level, its +N/s); coatings to the bag",
		function()
			local pen = shopPen()
			pen.items[4].level = 3
			local view = PenFormat.view(pen, 3, false, { confirm = "fuse" })
			expect.equal(view.confirm, "fuse")
			expect.deepEqual(view.fuseIds, { 3, 4, 2 })
			expect.truthy(view.marked[2] and view.marked[3] and view.marked[4])
			local toast = Strings.resolve("squishy.toast.name")
			expect.equal(
				view.status,
				Strings.format(screen.confirmFuse, {
					name = toast,
					result = Strings.format(screen.formName, { form = screen.forms[1], name = toast }),
				})
			)
			local rate = PenFormat.cardText({
				id = 0,
				kind = "toast",
				form = 1,
				level = 3,
				coat = 0,
				slot = 0,
				locked = false,
			}).rate
			expect.equal(view.hint, Strings.format(screen.fuseNote, { level = 3, rate = rate }))
			expect.equal(view.actions[1].text, screen.fuse)
			pen.items[2].coat = 2
			local coated = PenFormat.view(pen, 3, false, { confirm = "fuse" })
			expect.equal(
				coated.hint,
				Strings.format(screen.fuseNote, { level = 3, rate = rate }) .. " " .. screen.coatNote
			)
			expect.equal(PenFormat.view(pen, 5, false, { confirm = "fuse" }).confirm, nil) -- not three
		end
	)

	t.test("cardText: a Golden or Rainbow squishy says its form on the level line", function()
		local golden = item(1, "toast", 0, false, 3)
		golden.form = 1
		expect.equal(PenFormat.cardText(golden).level, Strings.format(screen.formLevel, { form = "Golden", level = 3 }))
		golden.form = 2
		expect.equal(PenFormat.cardText(golden).level, "Rainbow · Lv 3")
	end)

	t.test("holdFraction: 0 to 1 over the hold time, clamped", function()
		local seconds = Config.UI.Pen.screen.holdSeconds
		expect.equal(PenFormat.holdFraction(10, 10), 0)
		expect.near(PenFormat.holdFraction(10, 10 + seconds / 2), 0.5, 1e-9)
		expect.equal(PenFormat.holdFraction(10, 10 + seconds * 3), 1)
		expect.equal(PenFormat.holdFraction(10, 9), 0)
	end)

	-- Pens3 phase 9: food and levels ---------------------------------------------------------------------------------

	local FOOD = Config.Economy.Food
	local SCREEN_UI = Config.UI.Pen.screen
	local CANDY = Strings.resolve("food.candyDrop.name")

	t.test(
		"view: a squishy offers FEED last, its next step in the hint; refused at the top level or short of food",
		function()
			local pen = samplePen()
			local view = PenFormat.view(pen, 1, false, { food = { candy_drop = 3 } })
			local feed = view.actions[#view.actions]
			expect.equal(feed.id, "feed")
			expect.equal(feed.text, screen.feed)
			expect.equal(feed.reason, nil)
			expect.equal(view.hint, Strings.format(screen.feedHint, { level = 1, next = 2, pieces = 1, food = CANDY }))
			pen.items[1].level = 3 -- Lv 3 -> 4 takes 2
			local short = PenFormat.view(pen, 1, false, { food = { candy_drop = 1 } })
			expect.equal(
				short.actions[#short.actions].reason,
				Strings.format(screen.needFood, { missing = 1, food = CANDY })
			)
			expect.equal(short.hint, Strings.format(screen.feedHint, { level = 3, next = 4, pieces = 2, food = CANDY }))
			pen.items[1].level = 10 -- the cap at biome 1
			local top = PenFormat.view(pen, 1, false, { food = { candy_drop = 99, butter_bun = 99 } })
			expect.equal(top.actions[#top.actions].reason, Strings.reasonText("pen.maxLevel"))
			expect.equal(top.hint, Strings.format(screen.feedTop, { level = 10 }))
			-- No food yet (no Snapshot field): short of the step's pieces.
			pen.items[1].level = 1
			local none = PenFormat.view(pen, 1, false)
			expect.equal(
				none.actions[#none.actions].reason,
				Strings.format(screen.needFood, { missing = 1, food = CANDY })
			)
		end
	)

	t.test(
		"view: nothing selected adds FEED ALL (refused when nothing can eat); the food row lists what you own",
		function()
			local pen = samplePen()
			local view = PenFormat.view(pen, nil, false, { food = { candy_drop = 3 } })
			expect.deepEqual(actionIds(view), { "sellAll", "feedAll" })
			expect.equal(view.actions[2].text, screen.feedAll)
			expect.equal(view.actions[2].reason, nil)
			local item = Strings.format(screen.foodItem, { n = 3, food = CANDY })
			expect.equal(view.foodLine, Strings.format(screen.foodLine, { list = item }))
			local hungry = PenFormat.view(pen, nil, false, { food = {} })
			expect.equal(hungry.actions[2].reason, Strings.reasonText("pen.nothingToFeed"))
			expect.equal(hungry.foodLine, screen.foodNone)
			-- Only the pen's squishies eat: a Toy Box full of hungry squishies still has nothing to feed at the cap.
			for _, it in pen.items do
				it.level = if it.slot > 0 then 10 else 1
			end
			expect.equal(
				PenFormat.view(pen, nil, false, { food = { candy_drop = 9 } }).actions[2].reason,
				Strings.reasonText("pen.nothingToFeed")
			)
			-- Two foods: band order, joined.
			local two = PenFormat.view(pen, nil, false, { food = { butter_bun = 2, candy_drop = 1 } })
			local bun = Strings.format(screen.foodItem, { n = 2, food = Strings.resolve("food.butterBun.name") })
			local candy = Strings.format(screen.foodItem, { n = 1, food = CANDY })
			expect.equal(two.foodLine, Strings.format(screen.foodLine, { list = candy .. ", " .. bun }))
		end
	)

	t.test(
		"view: the BUY FOOD cards are the foods on sale; a card offers BUY 1 / BUY 10 with the true reasons",
		function()
			local pen = samplePen()
			local view = PenFormat.view(pen, nil, false, { food = { candy_drop = 2 }, coins = 1_000 })
			expect.deepEqual(ids(view.foods), { "candy_drop" } :: { any }) -- biome 1: Candy Drop only
			expect.equal(view.foodHeading, screen.foodHeading)
			expect.equal(view.foods[1].name, CANDY)
			expect.equal(view.foods[1].each, Strings.format(screen.foodEach, { coins = Format.coins(400) }))
			expect.equal(view.foods[1].have, Strings.format(screen.foodHave, { n = 2 }))
			expect.equal(view.foodSelected, nil)
			local few, many = SCREEN_UI.foodBuy.few, SCREEN_UI.foodBuy.many
			expect.truthy(few >= 1 and many > few and many <= FOOD.maxBuy)
			local picked =
				PenFormat.view(pen, nil, false, { food = { candy_drop = 2 }, coins = 1_000, foodId = "candy_drop" })
			expect.equal((picked.foodSelected :: any).id, "candy_drop")
			expect.deepEqual(actionIds(picked), { "buyFew", "buyMany" })
			expect.equal(picked.actions[1].text, Strings.format(screen.buyFood, { n = few }))
			expect.equal(picked.actions[2].text, Strings.format(screen.buyFood, { n = many }))
			expect.equal(picked.actions[1].reason, nil)
			local need = Strings.common.needCoins
			local missing = 400 * many - 1_000
			expect.equal(
				picked.actions[2].reason,
				Strings.format(Strings.plural(missing, need.one, need.many), { missing = Format.coins(missing) })
			)
			expect.equal(
				picked.hint,
				Strings.format(screen.foodBuyHint, { food = CANDY, coins = Format.coins(400), n = 2 })
			)
			local full = PenFormat.view(
				pen,
				nil,
				false,
				{ food = { candy_drop = FOOD.maxPieces }, coins = 10 ^ 9, foodId = "candy_drop" }
			)
			expect.equal(full.actions[1].reason, Strings.reasonText("food.full"))
			-- A food not on sale yet, or a squishy selected: no food card is.
			expect.equal(PenFormat.view(pen, nil, false, { foodId = "butter_bun" }).foodSelected, nil)
			expect.equal(PenFormat.view(pen, 1, false, { foodId = "candy_drop" }).foodSelected, nil)
		end
	)

	-- Pens3 phase 13: the level cap is 10 a biome the highway reached (Extra.highway = the profile's highway field).
	t.test("pens3 phase 13: the foods on sale and FEED follow the biome the highway reached", function()
		local pen = samplePen()
		local bakery = { best = 320, biome = 2 }
		local view = PenFormat.view(pen, nil, false, { food = {}, coins = 1_000, highway = bakery })
		expect.deepEqual(ids(view.foods), { "candy_drop", "butter_bun" } :: { any })
		expect.deepEqual(ids(PenFormat.view(pen, nil, false, { food = {} }).foods), { "candy_drop" } :: { any })
		pen.items[1].level = 10
		local feed = PenFormat.view(pen, 1, false, { food = { butter_bun = 9 }, highway = bakery })
		expect.equal(feed.actions[#feed.actions].reason, nil) -- Lv 10 -> 11 in Bakery Town
		local top = PenFormat.view(pen, 1, false, { food = { butter_bun = 9 } })
		expect.equal(top.hint, Strings.format(screen.feedTop, { level = 10 })) -- Candy Meadow's top
	end)

	t.test("view: the sell confirm of a levelled squishy says the food inside is not refunded", function()
		local pen = shopPen()
		pen.items[3].level = 4 -- 1 + 1 + 2 Candy Drop
		local view = PenFormat.view(pen, 3, false, { confirm = "sell" })
		expect.equal(
			view.hint,
			Strings.format(screen.sellNote, { minutes = MINUTES })
				.. " "
				.. Strings.format(screen.foodNote, { coins = Format.coins(1_600) })
		)
	end)

	t.test("requestFor: a retry of the same action reuses its id; another action gets a new one", function()
		local made = 0
		local function newId(): string
			made += 1
			return "id" .. made
		end
		local id, pending = PenFormat.requestFor(nil, "feed:3", newId)
		expect.equal(id, "id1")
		local again, kept = PenFormat.requestFor(pending, "feed:3", newId)
		expect.equal(again, "id1")
		expect.equal(kept, pending)
		local other = PenFormat.requestFor(pending, "feed:4", newId)
		expect.equal(other, "id2")
	end)
	-- Pens3 phase 11 ---------------------------------------------------------------------------------------------

	t.test(
		"view: the shelf's open spots and the TOP spot are their own sections; the count line is the pen's",
		function()
			local pen = {
				spots = 3,
				nextId = 5,
				shelfRows = 1,
				top = false,
				items = { item(1, "kitty_bread", 1), item(2, "toast", 13), item(3, "butter", 0), item(4, "bird", 2) },
			}
			local view = PenFormat.view(pen, nil, false)
			expect.equal(#view.spots, 3)
			expect.deepEqual(view.shelf, { { slot = 13, item = pen.items[2] }, { slot = 14 } })
			expect.equal(view.top, nil)
			expect.equal(view.shelfHeading, "On your shelf 1/2")
			expect.equal(view.topHeading, nil)
			expect.equal(view.status, "Pen 2/3 · Toy Box 1/50") -- the pen's own spots
			-- The TOP spot bought: its own card and heading; rows 2-4 add their spots.
			pen.top, pen.shelfRows = true, 4
			view = PenFormat.view(pen, nil, false)
			expect.equal(#view.shelf, 8)
			expect.deepEqual(view.top, { slot = 21 })
			expect.equal(view.topHeading, screen.topHeading)
			expect.equal(view.shelfHeading, "On your shelf 1/8")
			-- No shelfRows (an unsanitized pen): no shelf at all.
			local old = { spots = 3, nextId = 2, items = { item(1, "kitty_bread", 1) } }
			local plain = PenFormat.view(old, nil, false)
			expect.deepEqual(plain.shelf, {})
			expect.equal(plain.shelfHeading, nil)
		end
	)

	t.test(
		"a shelf squishy is placed; a Toy Box one PLACEs into a free shelf spot; picking moves to a shelf card",
		function()
			local pen = {
				spots = 3,
				nextId = 7,
				shelfRows = 1,
				top = true,
				items = {
					item(1, "kitty_bread", 1),
					item(2, "toast", 2),
					item(3, "banana", 3),
					item(4, "butter", 13),
					item(5, "bird", 0),
				},
			}
			local onShelf = PenFormat.view(pen, 4, false)
			expect.equal(onShelf.selected, pen.items[4])
			expect.deepEqual(actionIds(onShelf), { "putAway", "move", "lock", "sell", "feed" })
			local toy = PenFormat.view(pen, 5, false)
			expect.deepEqual(actionIds(toy), { "place", "lock", "sell", "feed" }) -- the pen is full, the shelf is not
			-- Picking: a shelf card and the TOP card take the squishy.
			local picking = PenFormat.view(pen, 5, true)
			expect.deepEqual({ PenFormat.tap(picking, 14, nil) }, { "place", 5, 14 } :: { any })
			expect.deepEqual({ PenFormat.tap(picking, 21, nil) }, { "place", 5, 21 } :: { any })
			-- Every open spot full: SWAP.
			table.insert(pen.items, item(6, "toast", 14))
			pen.items[5].slot = 0
			table.insert(pen.items, item(7, "toast", 21))
			expect.deepEqual(actionIds(PenFormat.view(pen, 5, false)), { "swap", "lock", "sell", "feed" })
		end
	)

	t.test("walkerItem maps a walker to the pen's own spots, never a shelf squishy", function()
		local pen = {
			spots = 3,
			nextId = 4,
			shelfRows = 1,
			top = false,
			items = { item(1, "toast", 13), item(2, "toast", 1), item(3, "banana", 2) },
		}
		local look = { kind = "toast", form = 0, level = 1, coat = 0 }
		expect.equal(PenFormat.walkerItem(pen, 1, look), 2) -- the first walker is the pen's Toast, not the shelf's
		expect.equal(PenFormat.walkerItem(pen, 2, look), 2) -- a stale index: the first pen Toast
	end)
	-- Wb (owner 2026-10-17): the shelf's BUY button in the MY PEN window ------------------------------------------

	t.test(
		"wb: the shelf BUY button: the next row's price, then the TOP spot's; MAX; short of Coins; no shelf",
		function()
			local Format = t.requireShared("Util/Format")
			local function shelfPen(rows: number, top: boolean): any
				return { spots = 3, nextId = 2, shelfRows = rows, top = top, items = { item(1, "kitty_bread", 1) } }
			end
			local function buy(view: any): any
				for _, action in view.actions do
					if action.id == "buyShelf" then
						return action
					end
				end
				return nil
			end
			-- Row 2 next, the Coins there: BUY ROW 31M, live, after SELL ALL and FEED ALL.
			local view = PenFormat.view(shelfPen(1, false), nil, false, { coins = 31_000_000 })
			expect.deepEqual(actionIds(view), { "sellAll", "feedAll", "buyShelf" })
			local row = buy(view)
			expect.equal(row.text, Strings.format(screen.buyRow, { coins = Format.coins(31_000_000) }))
			expect.equal(row.price, 31_000_000)
			expect.equal(row.reason, nil)
			expect.equal(row.kind, "secondary")
			-- Short of Coins: refused with the missing Coins (the reason row, not the button), the price still shown.
			local short = buy(PenFormat.view(shelfPen(1, false), nil, false, { coins = 1_000_000 }))
			local need = Strings.common.needCoins
			expect.equal(short.reason, Strings.format(need.many, { missing = Format.coins(30_000_000) }))
			expect.equal(short.price, 31_000_000)
			expect.equal(short.text, row.text)
			-- Rows 3 and 4: their prices (J: 250B, 11T).
			expect.equal(buy(PenFormat.view(shelfPen(2, false), nil, false)).price, 250_000_000_000)
			expect.equal(buy(PenFormat.view(shelfPen(3, false), nil, false)).price, 11_000_000_000_000)
			-- Every row open: the TOP spot next (140T).
			local top = buy(PenFormat.view(shelfPen(4, false), nil, false, { coins = 140_000_000_000_000 }))
			expect.equal(top.text, Strings.format(screen.buyTop, { coins = Format.coins(140_000_000_000_000) }))
			expect.equal(top.price, 140_000_000_000_000)
			expect.equal(top.reason, nil)
			-- All open: SHELF MAX, refused with the server's own text, no price to send.
			local max = buy(PenFormat.view(shelfPen(4, true), nil, false, { coins = 10 ^ 15 }))
			expect.equal(max.text, screen.shelfMax)
			expect.equal(max.reason, Strings.reasonText("pen.shelfMax"))
			expect.equal(max.price, nil)
			-- Short labels only: a reason never goes inside the button.
			for _, action in { row, top, max } do
				expect.truthy(#action.text <= 14)
			end
			-- No shelf (an unsanitized pen) or a squishy selected: no button.
			expect.equal(
				buy(PenFormat.view({ spots = 3, nextId = 2, items = { item(1, "kitty_bread", 1) } }, nil, false)),
				nil
			)
			expect.equal(buy(PenFormat.view(shelfPen(1, false), 1, false, { coins = 31_000_000 })), nil)
		end
	)
end
