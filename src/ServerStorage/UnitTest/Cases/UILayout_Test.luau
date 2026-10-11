--!strict
-- UILayout_Test: the pure UI layout maths (StarterPlayerScripts.Client.UI.Layout) and the modal stack
-- (UI.ModalStack) used by UIController. Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §11.1, §11.2, §10.3):
--   * UIScale = clamp(height / 800, 0.85, 1.25); "compact" below 500 px tall or 700 px wide;
--   * text size = base × the PreferredTextSize multiplier (unknown kinds use Body); touch targets never below
--     Config.UI.Touch.minTargetFloor actual px; modal width capped at Config.UI.modalMaxWidth;
--   * the modal stack holds at most Config.UI.modalStackMax screens: a full stack closes its newest first; reopening
--     a screen closes everything above it; removing one closes it and everything above it;
--   * Back answers the newest layer (ModalStack.backTarget): a back handler pushed after the top modal opened, else
--     the top modal (Part 6 review: Inspect opened over the duel result card closes first).
--   * Part 8: modalPanel sizes a centred panel like the Squishies / Shop / Boxes panels at 667×375, 893×673, 1280×720
--     and 1920×1080 (inside the screen after the UIScale); wrapRow wraps like UIListLayout.Wraps (greedy, in order,
--     an over-wide item alone on its row, rows as tall as their tallest item); pinnedButtons keeps the button rows at
--     the bottom of the column and gives the list the rest; bannerTop keeps UIController's banner under the duel top
--     bar (the lives) at 667×375, 1280×720 and 1920×1080 at Medium and the largest text, never past the middle.
--   * Foam UI (spec 2026-10-09): foamStops gives a valid UIGradient (0 to 1, strictly rising, <= 20 stops) with the
--     top, face, bevel and drop bands at their base px heights, leaves missing or too thin bands out, never lets bands
--     pass each other and treats an unmeasured surface as a 52 px button.
--   * Foam fix round 2 (2026-10-09): scrollThumb (the touch scroll rail of UI/Components/ScrollHint) shows only for a
--     list longer than its window, its size and top as shares of the track; modalBackdrop keeps one backdrop at a time
--     (the dimmer under one modal, only the wash under the top of two); pinnedButtons takes the buttons' own gap.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Layout = t.requireClient("UI/Layout")
	local ModalStack = t.requireClient("UI/ModalStack")
	local Config = t.requireShared("Config")
	local UI = Config.UI

	t.test("UIScale follows the HUD height inside its clamp", function()
		expect.near(Layout.uiScale(UI.Scale.referenceHeight), 1)
		expect.near(Layout.uiScale(400), UI.Scale.min)
		expect.near(Layout.uiScale(4000), UI.Scale.max)
		expect.near(Layout.uiScale(0 / 0), UI.Scale.min)
		expect.near(Layout.uiScale(-5), UI.Scale.min)
		expect.near(Layout.uiScale(880), 880 / UI.Scale.referenceHeight)
	end)

	t.test("layout class: compact on small screens", function()
		expect.equal(Layout.layoutClass(1920, 1080), "regular")
		expect.equal(Layout.layoutClass(667, 375), "compact")
		expect.equal(Layout.layoutClass(800, UI.Breakpoints.compactBelowHeight - 1), "compact")
		expect.equal(Layout.layoutClass(UI.Breakpoints.compactBelowWidth - 1, 900), "compact")
		expect.equal(Layout.layoutClass(UI.Breakpoints.compactBelowWidth, UI.Breakpoints.compactBelowHeight), "regular")
	end)

	t.test("text sizes: base × the preferred text multiplier; unknown kinds use Body", function()
		expect.equal(Layout.textSize("Body", "Medium"), UI.TextSize.Body)
		expect.equal(Layout.textSize("Title", nil), UI.TextSize.Title)
		expect.equal(
			Layout.textSize("Body", "Largest"),
			math.floor(UI.TextSize.Body * UI.PreferredTextScale.Largest + 0.5)
		)
		expect.equal(Layout.textSize("NoSuchKind", "Medium"), UI.TextSize.Body)
		expect.equal(Layout.preferredTextScale("Bogus"), 1)
		-- Nothing below the minimum after the smallest UIScale.
		for kind, base in UI.TextSize do
			if Layout.textSize(kind, "Medium") * UI.Scale.min < UI.minTextSize then
				error(`{kind} ({base}) falls below {UI.minTextSize} px at the smallest scale`)
			end
		end
	end)

	t.test("touch targets never shrink below the floor; modal width is capped", function()
		local floor = UI.Touch.minTargetFloor
		expect.equal(Layout.touchBase(UI.Touch.minTarget, UI.Scale.min), UI.Touch.minTarget)
		expect.truthy(Layout.actualPx(Layout.touchBase(UI.Touch.minTarget, UI.Scale.min), UI.Scale.min) >= floor)
		local small = Layout.touchBase(30, UI.Scale.min)
		expect.truthy(Layout.actualPx(small, UI.Scale.min) >= floor)
		expect.equal(Layout.touchBase(30, 0), math.max(30, floor))
		expect.equal(Layout.modalWidth(5000, 1, 20), UI.modalMaxWidth)
		expect.equal(Layout.modalWidth(800, 1, 20), 760)
		expect.equal(Layout.modalWidth(800, 2, 20), 360)
		expect.equal(Layout.modalWidth(10, 1, 20), 0)
	end)

	t.test("modal stack: at most max open; reopening or removing closes what is above", function()
		local stack = ModalStack.new(2)
		expect.deepEqual(stack:push("shop"), {})
		expect.deepEqual(stack:push("inspect"), {})
		expect.deepEqual(stack:list(), { "shop", "inspect" })
		expect.equal(stack:top(), "inspect")
		-- Full: the newest (top) closes, the opener underneath stays.
		expect.deepEqual(stack:push("boxes"), { "inspect" })
		expect.deepEqual(stack:list(), { "shop", "boxes" })
		-- Reopening a lower screen closes everything above it.
		expect.deepEqual(stack:push("shop"), { "boxes" })
		expect.deepEqual(stack:list(), { "shop" })
		expect.deepEqual(stack:push("shop"), {})
		stack:push("inspect")
		expect.deepEqual(stack:remove("shop"), { "inspect", "shop" })
		expect.equal(stack:size(), 0)
		expect.deepEqual(stack:remove("missing"), {})
		expect.equal(stack:top(), nil)
		expect.equal(stack:contains("shop"), false)
	end)

	t.test("modal stack: a screen that closes when covered (Inspect, §10.10) leaves before another opens", function()
		local function inspectOnly(name: string): boolean
			return name == "inspect"
		end
		local stack = ModalStack.new(2)
		-- Inspect alone, then the shop: Inspect closes, the shop opens alone.
		expect.deepEqual(stack:push("inspect", inspectOnly), {})
		expect.deepEqual(stack:push("shop", inspectOnly), { "inspect" })
		expect.deepEqual(stack:list(), { "shop" })
		-- Inspect over the shop, then Boxes: only Inspect closes, Boxes goes over the shop.
		expect.deepEqual(stack:push("inspect", inspectOnly), {})
		expect.deepEqual(stack:push("boxes", inspectOnly), { "inspect" })
		expect.deepEqual(stack:list(), { "shop", "boxes" })
		-- Screens without the rule stack as before; reopening Inspect itself closes nothing new.
		expect.deepEqual(stack:push("shop", inspectOnly), { "boxes" })
		expect.deepEqual(stack:push("inspect", inspectOnly), {})
		expect.deepEqual(stack:push("inspect", inspectOnly), {})
		expect.deepEqual(stack:list(), { "shop", "inspect" })
		-- No predicate: the old rule (a full stack closes its top only).
		expect.deepEqual(stack:push("daily"), { "inspect" })
		expect.deepEqual(stack:list(), { "shop", "daily" })
	end)

	t.test("Back answers the newest layer: a back handler or the top modal, whichever came last", function()
		-- The duel result card's back handler (layer 4), then Inspect opened over it (layer 5): Back closes Inspect.
		expect.equal(ModalStack.backTarget(4, 5), "modal")
		-- Inspect closed: the card's handler answers the next Back.
		expect.equal(ModalStack.backTarget(4, nil), "handler")
		-- The box reveal (layer 6) pushes its skip handler from its own open (layer 7): the handler answers.
		expect.equal(ModalStack.backTarget(7, 6), "handler")
		-- Only a modal, or nothing at all.
		expect.equal(ModalStack.backTarget(nil, 3), "modal")
		expect.equal(ModalStack.backTarget(nil, nil), "none")
	end)

	t.test("modalPanel: a centred panel inside the screen at every tested size; a bad size falls back", function()
		for _, size in { Vector2.new(667, 375), Vector2.new(893, 673), Vector2.new(1280, 720), Vector2.new(1920, 1080) } do
			local p = Layout.modalPanel(size, 24, 0.88, 12)
			expect.near(p.scale, Layout.uiScale(size.Y))
			expect.equal(p.class, Layout.layoutClass(size.X, size.Y))
			expect.truthy(p.panelWidth <= UI.modalMaxWidth)
			expect.truthy(p.panelWidth * p.scale <= size.X + 1e-6)
			expect.near(p.panelHeight * p.scale, size.Y * 0.88)
			expect.near(p.contentWidth, p.panelWidth - 24)
			expect.near(p.contentHeight, p.panelHeight - 24)
		end
		expect.deepEqual(
			Layout.modalPanel(Vector2.new(0, 0 / 0), 24, 0.88, 12),
			Layout.modalPanel(Vector2.new(1280, 720), 24, 0.88, 12)
		)
	end)

	t.test("wrapRow: greedy rows like UIListLayout.Wraps", function()
		local items = { { w = 100, h = 56 }, { w = 80, h = 56 }, { w = 120, h = 70 }, { w = 50, h = 56 } }
		local wide = Layout.wrapRow(items, 1000, 6)
		expect.equal(wide.rows, 1)
		expect.deepEqual(wide.rects[2], { x = 106, y = 0, w = 80, h = 56 })
		expect.equal(wide.height, 70)
		expect.equal(wide.width, 100 + 6 + 80 + 6 + 120 + 6 + 50)
		-- 200 wide: [100, 80] then [120, 50] (the second row is as tall as its 70 px item).
		local narrow = Layout.wrapRow(items, 200, 6)
		expect.equal(narrow.rows, 2)
		expect.deepEqual(narrow.rects[3], { x = 0, y = 62, w = 120, h = 70 })
		expect.deepEqual(narrow.rects[4], { x = 126, y = 62, w = 50, h = 56 })
		expect.equal(narrow.height, 56 + 6 + 70)
		-- Exactly full fits; one pixel less wraps.
		expect.equal(Layout.wrapRow({ { w = 100, h = 10 }, { w = 94, h = 10 } }, 200, 6).rows, 1)
		expect.equal(Layout.wrapRow({ { w = 100, h = 10 }, { w = 95, h = 10 } }, 200, 6).rows, 2)
		-- An item wider than the row takes a row alone; nothing is lost.
		local over = Layout.wrapRow({ { w = 300, h = 10 }, { w = 20, h = 10 } }, 200, 6)
		expect.equal(over.rows, 2)
		expect.equal(over.rects[1].x, 0)
		expect.equal(over.rects[2].y, 16)
		-- No items; bad numbers count as 0.
		expect.deepEqual(Layout.wrapRow({}, 200, 6), { rows = 0, width = 0, height = 0, rects = {} })
		local bad = Layout.wrapRow({ { w = 0 / 0, h = -5 } }, 0 / 0, 0 / 0)
		expect.deepEqual(bad.rects[1], { x = 0, y = 0, w = 0, h = 0 })
	end)

	t.test("pinnedButtons: the button rows sit at the bottom of the column, the list takes the rest", function()
		local items = { { w = 150, h = 56 }, { w = 120, h = 56 }, { w = 160, h = 56 } }
		local p = Layout.pinnedButtons(300, 250, 6, items)
		expect.equal(p.rows, 2)
		expect.equal(p.buttonsHeight, 56 * 2 + 6)
		expect.equal(p.buttonsTop, 250 - p.buttonsHeight)
		expect.equal(p.scrollHeight, 250 - p.buttonsHeight - 6)
		expect.equal(#p.buttons, 3)
		-- Too short a column: the list shrinks to 0, the buttons start at the top.
		local short = Layout.pinnedButtons(300, 50, 6, items)
		expect.equal(short.scrollHeight, 0)
		expect.equal(short.buttonsTop, 0)
		-- No buttons: the list takes the whole column.
		local none = Layout.pinnedButtons(300, 250, 6, {})
		expect.equal(none.scrollHeight, 250)
		expect.equal(none.buttonsHeight, 0)
	end)

	t.test("bannerTop: 20% down, else under the duel top bar; never past the middle", function()
		-- The duel top bar as DuelFormat_Test estimates it: 110 base px × the text scale, 12 px from the top.
		local function canvasHeight(actualY: number): number
			return actualY / Layout.uiScale(actualY)
		end
		for _, actualY in { 375, 720, 1080 } do -- 667×375, 1280×720, 1920×1080
			local h = canvasHeight(actualY)
			for _, textScale in { 1, UI.PreferredTextScale.Largest } do
				local barBottom = 12 + 110 * textScale
				local top = Layout.bannerTop(h, barBottom, 0.2, 8)
				expect.truthy(top >= h * 0.2 - 1e-6) -- never higher than as built
				expect.truthy(top >= barBottom + 8 - 1e-6) -- the lives row stays clear
				expect.truthy(top <= h * 0.5 + 1e-6) -- room for the banner below
			end
		end
		-- 667×375 at Medium: 20% down (about 88 base px) was inside the bar (bottom 122): now 8 under it.
		local phone = canvasHeight(375)
		expect.near(Layout.bannerTop(phone, 122, 0.2, 8), 130, 1e-6)
		-- 1920×1080 at Medium: room to spare, exactly as built.
		local big = canvasHeight(1080)
		expect.near(Layout.bannerTop(big, 122, 0.2, 8), big * 0.2, 1e-6)
		-- Nothing to keep clear, or a bad number: as built.
		expect.near(Layout.bannerTop(phone, nil, 0.2, 8), phone * 0.2, 1e-6)
		expect.near(Layout.bannerTop(phone, 0 / 0, 0.2, 8), phone * 0.2, 1e-6)
		-- A bar past the middle: the banner stops at the middle and stays on the screen.
		expect.near(Layout.bannerTop(phone, phone * 0.9, 0.2, 8), phone * 0.5, 1e-6)
		-- A bad canvas height gives 0.
		expect.equal(Layout.bannerTop(0 / 0, 100, 0.2, 8), 0)
	end)

	-- Foam UI (spec 2026-10-09) -------------------------------------------------------------------------------------

	-- Checks the shape every UIGradient needs: first stop at 0, last at 1, times strictly rising, at most 20 stops.
	local function expectValidStops(stops: { any })
		expect.truthy(#stops >= 2 and #stops <= 20)
		expect.equal(stops[1].time, 0)
		expect.equal(stops[#stops].time, 1)
		for i = 2, #stops do
			if not (stops[i].time > stops[i - 1].time) then
				error(`stop {i} at {stops[i].time} does not rise past {stops[i - 1].time}`)
			end
		end
	end

	-- The bands in order, each once (consecutive stops of one band merged).
	local function bandOrder(stops: { any }): { string }
		local order: { string } = {}
		for _, stop in stops do
			if order[#order] ~= stop.band then
				table.insert(order, stop.band)
			end
		end
		return order
	end

	t.test("foamStops: a button's top, face, bevel and drop bands at their base px heights", function()
		local stops = Layout.foamStops(56, 2, 5, 3)
		expectValidStops(stops)
		expect.deepEqual(bandOrder(stops), { "top", "face", "bevel", "drop" })
		-- Each band starts where its pixels start (top 2 px, bevel 5 px above the 3 px drop).
		local starts: { [string]: number } = {}
		for _, stop in stops do
			if starts[stop.band] == nil then
				starts[stop.band] = stop.time
			end
		end
		expect.near(starts.face, 2 / 56, 1e-9)
		expect.near(starts.bevel, 1 - 8 / 56, 1e-9)
		expect.near(starts.drop, 1 - 3 / 56, 1e-9)
		-- A hard edge: the previous band reaches to just before the next one (one edge, 0.001, earlier).
		for i = 2, #stops - 1 do
			if stops[i].band ~= stops[i - 1].band then
				expect.near(stops[i].time - stops[i - 1].time, 0.001, 1e-9)
			end
		end
	end)

	t.test("foamStops: missing bands are left out; a panel has no top band", function()
		local panel = Layout.foamStops(300, 0, 5, 4)
		expectValidStops(panel)
		expect.deepEqual(bandOrder(panel), { "face", "bevel", "drop" })
		local flat = Layout.foamStops(26, 0, 0, 0)
		expectValidStops(flat)
		expect.deepEqual(bandOrder(flat), { "face" })
		local inset = Layout.foamStops(80, 3, 0, 0)
		expectValidStops(inset)
		expect.deepEqual(bandOrder(inset), { "top", "face" })
		local keycap = Layout.foamStops(24, 0, 0, 2)
		expectValidStops(keycap)
		expect.deepEqual(bandOrder(keycap), { "face", "drop" })
	end)

	t.test("foamStops: bands never pass each other; a bad height counts as a button", function()
		-- Bands larger than the surface: the top band stops at half, the drop and the bevel share the rest.
		local crowded = Layout.foamStops(10, 20, 20, 20)
		expectValidStops(crowded)
		for _, stop in crowded do
			expect.truthy(stop.time >= 0 and stop.time <= 1)
		end
		-- Not measured yet (0, negative, NaN): the same stops as a 52 px button.
		local fallback = Layout.foamStops(52, 2, 5, 3)
		expect.deepEqual(Layout.foamStops(0, 2, 5, 3), fallback)
		expect.deepEqual(Layout.foamStops(-4, 2, 5, 3), fallback)
		expect.deepEqual(Layout.foamStops(0 / 0, 2, 5, 3), fallback)
		-- Bad band sizes count as no band.
		expect.deepEqual(bandOrder(Layout.foamStops(56, 0 / 0, -5, math.huge)), { "face" })
		-- Bands thinner than two edges are left out (no zero-length band).
		expect.deepEqual(bandOrder(Layout.foamStops(1000, 0.01, 5, 3)), { "face", "bevel", "drop" })
	end)

	-- Foam fix round 2 ---------------------------------------------------------------------------------------------

	t.test("scrollThumb: a thumb only when the list is longer than its window; size and top as track shares", function()
		-- The list fits (or is a rounding longer): nothing to show.
		expect.equal(Layout.scrollThumb(200, 200, 0).shown, false)
		expect.equal(Layout.scrollThumb(200, 150, 0).shown, false)
		expect.equal(Layout.scrollThumb(200, 200.5, 0).shown, false)
		-- A list four windows long: a quarter-size thumb at the top, at the bottom once scrolled to the end.
		local top = Layout.scrollThumb(100, 400, 0)
		expect.equal(top.shown, true)
		expect.near(top.size, 0.25, 1e-6)
		expect.near(top.top, 0, 1e-6)
		expect.near(Layout.scrollThumb(100, 400, 150).top, 0.375, 1e-6)
		local bottom = Layout.scrollThumb(100, 400, 300)
		expect.near(bottom.top + bottom.size, 1, 1e-6)
		-- An overscroll at either end keeps the thumb on its track.
		expect.near(Layout.scrollThumb(100, 400, -50).top, 0, 1e-6)
		local over = Layout.scrollThumb(100, 400, 900)
		expect.near(over.top + over.size, 1, 1e-6)
		-- A very long list keeps a thumb big enough to see.
		expect.near(Layout.scrollThumb(100, 100000, 0).size, Layout.SCROLL_THUMB_MIN, 1e-6)
		expect.near(Layout.scrollThumb(100, 100000, 99900).top, 1 - Layout.SCROLL_THUMB_MIN, 1e-6)
		-- Bad sizes: nothing to show; a bad offset counts as the top.
		for _, bad in { 0 / 0, math.huge, -5, 0 } do
			expect.equal(Layout.scrollThumb(bad, 400, 0).shown, false)
			expect.equal(Layout.scrollThumb(100, bad, 0).shown, false)
		end
		local nanOffset = Layout.scrollThumb(100, 400, 0 / 0)
		expect.equal(nanOffset.shown, true)
		expect.near(nanOffset.top, 0, 1e-6)
	end)

	t.test(
		"modalBackdrop: one backdrop at a time, the dimmer under one modal, the wash under the top of two",
		function()
			expect.deepEqual(Layout.modalBackdrop(0), { dimmer = false, wash = false })
			expect.deepEqual(Layout.modalBackdrop(1), { dimmer = true, wash = false })
			-- Two open (Inspect over Squishies, the box reveal over Boxes): the dimmer hands over to the wash, so the HUD and
			-- the world are darkened once, as under one modal.
			expect.deepEqual(Layout.modalBackdrop(2), { dimmer = false, wash = true })
			expect.deepEqual(Layout.modalBackdrop(3), { dimmer = false, wash = true })
			for _, bad in { 0 / 0, -1, -math.huge } do
				expect.deepEqual(Layout.modalBackdrop(bad), { dimmer = false, wash = false })
			end
		end
	)

	t.test("pinnedButtons: the buttons keep their own gap between them and their rows; the list keeps `gap`", function()
		local items = { { w = 150, h = 56 }, { w = 120, h = 56 }, { w = 160, h = 56 } }
		local p = Layout.pinnedButtons(300, 250, 6, items, 12)
		expect.equal(p.rows, 2)
		expect.equal(p.buttons[2].x, 150 + 12)
		expect.equal(p.buttons[3].y, 56 + 12)
		expect.equal(p.buttonsHeight, 56 * 2 + 12)
		expect.equal(p.buttonsTop, 250 - p.buttonsHeight)
		expect.equal(p.scrollHeight, 250 - p.buttonsHeight - 6) -- the list still ends `gap` above them
		-- 150 + 12 + 140 passes 300 although 150 + 6 + 140 does not: the wider gap wraps sooner.
		expect.equal(Layout.pinnedButtons(300, 250, 6, { { w = 150, h = 56 }, { w = 140, h = 56 } }, 12).rows, 2)
		-- No or a bad button gap: `gap` between the buttons, as before.
		for _, same in
			{
				Layout.pinnedButtons(300, 250, 6, items),
				Layout.pinnedButtons(300, 250, 6, items, 0 / 0),
				Layout.pinnedButtons(300, 250, 6, items, -4),
			}
		do
			expect.equal(same.buttons[2].x, 150 + 6)
			expect.equal(same.buttonsHeight, 56 * 2 + 6)
		end
	end)

	t.test("the configured stack size and the ScreenGui orders of §11.1", function()
		expect.equal(UI.modalStackMax, 2)
		local orders = {}
		for name, spec in UI.ScreenGuis do
			orders[name] = spec.displayOrder
		end
		expect.deepEqual(
			orders,
			{ SD_Hud = 10, SD_DuelHud = 11, SD_Dimmer = 19, SD_Modal = 20, SD_Overlay = 30, SD_Fade = 40 }
		)
		expect.throws(function()
			ModalStack.new(0)
		end)
	end)
end
