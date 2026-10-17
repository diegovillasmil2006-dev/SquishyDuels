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
--   * cardText(item): the name, "+N/s" and "Lv N" of a card.

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
		expect.deepEqual(view.actions, {})
		-- No pen yet (no Snapshot): no cards, no actions.
		local none = PenFormat.view(nil, 1, true)
		expect.deepEqual(none.spots, {})
		expect.deepEqual(none.toys, {})
		expect.equal(none.picking, false)
		expect.deepEqual(none.actions, {})
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
			expect.deepEqual(actionIds(placed), { "putAway", "move", "lock" })
			expect.equal(placed.actions[1].text, screen.putAway)
			expect.equal(placed.actions[1].kind, "primary")
			expect.equal(placed.actions[1].reason, nil)
			local toy = PenFormat.view(pen, 3, false)
			expect.deepEqual(actionIds(toy), { "place", "lock" }) -- spot 2 is free
			-- A full pen: SWAP instead of PLACE.
			pen.items[3].slot = 2
			local full = PenFormat.view(pen, 4, false)
			expect.deepEqual(actionIds(full), { "swap", "lock" })
			-- A locked one offers UNLOCK.
			pen.items[4].locked = true
			expect.deepEqual(actionIds(PenFormat.view(pen, 4, false)), { "swap", "unlock" })
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
			expect.deepEqual(gone.actions, {})
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
end
