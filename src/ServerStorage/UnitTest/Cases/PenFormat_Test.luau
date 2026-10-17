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
		expect.deepEqual(actionIds(view), { "sellAll" }) -- pens3 phase 7
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
			expect.deepEqual(actionIds(placed), { "putAway", "move", "lock", "sell" }) -- pens3 phase 7: + SELL
			expect.equal(placed.actions[1].text, screen.putAway)
			expect.equal(placed.actions[1].kind, "primary")
			expect.equal(placed.actions[1].reason, nil)
			local toy = PenFormat.view(pen, 3, false)
			expect.deepEqual(actionIds(toy), { "place", "lock", "sell" }) -- spot 2 is free
			-- A full pen: SWAP instead of PLACE.
			pen.items[3].slot = 2
			local full = PenFormat.view(pen, 4, false)
			expect.deepEqual(actionIds(full), { "swap", "lock", "sell" })
			-- A locked one offers UNLOCK.
			pen.items[4].locked = true
			expect.deepEqual(actionIds(PenFormat.view(pen, 4, false)), { "swap", "unlock", "sell" })
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
			expect.deepEqual(actionIds(gone), { "sellAll" })
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
			expect.deepEqual(actionIds(idle), { "sellAll" })
			expect.equal(idle.actions[1].text, screen.sellAll)
			expect.equal(idle.actions[1].reason, nil) -- Toasts 3 and 4 can go
			local nothing = PenFormat.view(samplePen(), nil, false)
			expect.equal(nothing.actions[1].reason, Strings.reasonText("pen.nothingToSell"))
			-- A squishy: SELL after its other actions, refused with the server's reason where it would be.
			expect.deepEqual(actionIds(PenFormat.view(pen, 3, false)), { "place", "lock", "sell", "fuse" }) -- 3 Toasts
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
		expect.deepEqual(actionIds(PenFormat.view(pen, 3, false)), { "place", "lock", "sell", "fuse" })
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
end
