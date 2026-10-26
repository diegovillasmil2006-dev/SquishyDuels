--!strict
-- InspectPanel_Test: the pure layout of StarterPlayerScripts.Client.UI.InspectPanel (the Inspect modal). Server only
-- (ServerStorage.UnitTest). Pure: InspectPanel.new is never called (no instances, no LocalPlayer).
-- Contract (DESIGN §10.8, §11.2; Part 6 readings):
--   * layoutFor(screenPx, class, textScale?) at 1920×1080 and 1280×720 (regular) and 667×375 (compact, a phone in
--     landscape): the stage column takes about 55% (regular) / 50% (compact) of the content width;
--   * every button is at least Config.UI.Touch.minTarget base px and never below minTargetFloor actual px; the regular
--     buttons are primary-sized, Close is Touch.closeButton;
--   * nothing goes past the edges: the panel is capped at modalMaxWidth and fits the screen after the UIScale, every rect
--     lies inside the content box, the stage and info columns don't overlap, the header row (badges and Close) and the
--     body follow each other, the caption sits under the stage and both button rows share one bottom row under the
--     stage and the list;
--   * a bigger PreferredTextSize grows the caption, still inside the panel;
--   * a zero or NaN screen size falls back to 1280×720 (no NaN anywhere); an unknown class is "regular";
--   * howToGetSlots() = #Boxes.list() + 1 (the fixed pool of "How to get" lines, §10.11).
--   * Part 8 (re-checked at the largest text): buttonRows counts the rows of each button row from the buttons' widths
--     (2 for "Not owned" + "View in Shop" on a phone at the Largest text size); layoutFor(..., rows) grows that row
--     from the bottom up, keeps both rows' bottom edge, shrinks the list or the stage above it and stays inside, at
--     667×375, 893×673 (Studio's window), 1280×720 and 1920×1080; rows default to 1 (the layouts above unchanged).
--   * Foam UI restyle (2026-10-09): the name is a header tab, so the separate badge row is gone (the badges share the
--     Close row); layoutFor(..., topPadding) takes the panel's top padding that the tab raises: the content box loses
--     the difference, every rect stays inside it at every screen and text size, and a missing, bad or too small
--     padding means the panel padding (the layout without a tab).
--   * Foam fix batch (2026-10-09): Close hangs on the panel's top-right corner (InventoryFormat.hangingChrome), so the
--     header row holds only the badges: at least a Chip tall, shorter than Close, growing with the text size; the
--     stage gets the room back (taller than with a Close-tall row).
--   * Foam fix round 2 (2026-10-09): the body starts Theme.Padding.medium under the badges (the chips' outline and drop
--     sat on the stage's rim at 6), and the buttons of a row and its wrapped rows keep Theme.Padding.medium apart.
-- Tables are compared by value.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

type Rect = { x: number, y: number, w: number, h: number }

return function(t: Context)
	local expect = t.expect
	local InspectPanel = t.requireClient("UI/InspectPanel")
	local Chip = t.requireClient("UI/Components/Chip")
	local Config = t.requireShared("Config")
	local Boxes = t.requireShared("Boxes")
	local TOUCH = Config.UI.Touch
	local EPS = 1e-6
	local MIN_STAGE_ACTUAL_PX = 100 -- reading: a stage a phone player can still drag and tap

	local SCREENS = {
		{ label = "1920x1080", size = Vector2.new(1920, 1080), class = "regular" },
		{ label = "1280x720", size = Vector2.new(1280, 720), class = "regular" },
		{ label = "667x375", size = Vector2.new(667, 375), class = "compact" },
	}

	local function isFinite(n: unknown): boolean
		return type(n) == "number" and n == n and n > -math.huge and n < math.huge
	end

	local function rects(l: any): { [string]: Rect }
		return {
			header = l.header,
			stage = l.stage,
			caption = l.caption,
			stageButtons = l.stageButtons,
			info = l.info,
			infoButtons = l.infoButtons,
		}
	end

	local function expectInside(name: string, r: Rect, l: any)
		for _, key in { "x", "y", "w", "h" } do
			if not isFinite((r :: any)[key]) then
				error(`{name}.{key} is not a finite number`)
			end
		end
		if r.x < -EPS or r.y < -EPS or r.w < 0 or r.h < 0 then
			error(`{name} starts outside the content box: {r.x}, {r.y} ({r.w} x {r.h})`)
		end
		if r.x + r.w > l.contentWidth + EPS or r.y + r.h > l.contentHeight + EPS then
			error(`{name} ends past the content box: {r.x + r.w} x {r.y + r.h} > {l.contentWidth} x {l.contentHeight}`)
		end
	end

	-- Every structural rule of one layout.
	local function expectSound(l: any, size: Vector2)
		-- The panel fits the screen.
		expect.equal(l.panelWidth <= Config.UI.modalMaxWidth, true)
		expect.equal(l.panelWidth * l.scale <= size.X + EPS, true)
		expect.equal(l.panelHeight * l.scale <= size.Y + EPS, true)
		expect.equal(l.contentWidth, l.panelWidth - 2 * l.padding)
		expect.equal(l.contentHeight, l.panelHeight - l.topPadding - l.padding)
		expect.equal(l.topPadding >= l.padding, true)
		-- Every rect inside the content box.
		for name, r in rects(l) do
			expectInside(name, r, l)
		end
		-- The header row (the badges; fix batch: Close hangs on the corner, so the row is shorter than Close), then the
		-- body.
		expect.equal(l.header.y, 0)
		expect.equal(l.header.h >= Chip.HEIGHT_PX, true)
		expect.equal(l.header.h < l.closeHeight, true)
		expect.equal(l.stage.y >= l.header.y + l.header.h, true)
		expect.equal(l.info.y, l.stage.y)
		-- Two columns side by side, no overlap.
		expect.equal(l.stage.x, 0)
		expect.equal(l.stage.x + l.stage.w <= l.info.x, true)
		expect.equal(l.stageButtons.x + l.stageButtons.w <= l.infoButtons.x, true)
		expect.equal(l.caption.w, l.stage.w)
		-- The caption under the stage; one shared bottom row of buttons under the caption and the list.
		expect.equal(l.caption.y >= l.stage.y + l.stage.h, true)
		expect.equal(l.stageButtons.y >= l.caption.y + l.caption.h, true)
		expect.equal(l.infoButtons.y >= l.info.y + l.info.h, true)
		expect.equal(l.stageButtons.y, l.infoButtons.y)
		expect.equal(l.stageButtons.h, l.buttonHeight)
		expect.equal(l.infoButtons.h, l.buttonHeight)
		-- Something to see and something to read.
		expect.equal(l.stage.w * l.scale >= MIN_STAGE_ACTUAL_PX, true)
		expect.equal(l.stage.h * l.scale >= MIN_STAGE_ACTUAL_PX, true)
		expect.equal(l.info.w > 0 and l.info.h > 0, true)
	end

	local function expectTouchTargets(l: any)
		expect.equal(l.buttonHeight >= TOUCH.minTarget, true)
		expect.equal(l.buttonHeight * l.scale >= TOUCH.minTargetFloor - EPS, true)
		expect.equal(l.closeHeight >= TOUCH.closeButton, true)
		expect.equal(l.closeHeight * l.scale >= TOUCH.minTargetFloor - EPS, true)
	end

	for _, screen in SCREENS do
		t.test(
			`layoutFor {screen.label}: {screen.class}, stage share, touch targets, nothing past the edges`,
			function()
				local l = InspectPanel.layoutFor(screen.size, screen.class)
				expect.equal(l.class, screen.class)
				if screen.class == "regular" then
					expect.equal(l.stageWidthShare > 0.5 and l.stageWidthShare <= 0.6, true)
					expect.equal(l.buttonHeight >= TOUCH.primaryButton, true)
				else
					expect.equal(l.stageWidthShare >= 0.45 and l.stageWidthShare <= 0.55, true)
				end
				-- The stage column really takes that share of the width (a column gap aside).
				local measured = l.stage.w / l.contentWidth
				expect.equal(measured <= l.stageWidthShare + EPS, true)
				expect.equal(measured >= l.stageWidthShare - 0.03, true)
				expectTouchTargets(l)
				expectSound(l, screen.size)
			end
		)
	end

	t.test("layoutFor: the panel width is capped at modalMaxWidth on big screens and shrinks on a phone", function()
		local big = InspectPanel.layoutFor(Vector2.new(1920, 1080), "regular")
		local hd = InspectPanel.layoutFor(Vector2.new(1280, 720), "regular")
		local phone = InspectPanel.layoutFor(Vector2.new(667, 375), "compact")
		expect.equal(big.panelWidth, Config.UI.modalMaxWidth)
		expect.equal(hd.panelWidth, Config.UI.modalMaxWidth)
		expect.equal(phone.panelWidth < Config.UI.modalMaxWidth, true)
		expect.equal(phone.scale, Config.UI.Scale.compactMin)
		expect.equal(big.scale, Config.UI.Scale.max)
	end)

	t.test("layoutFor: the largest PreferredTextSize grows the caption, still inside", function()
		for _, screen in SCREENS do
			local normal = InspectPanel.layoutFor(screen.size, screen.class)
			local large = InspectPanel.layoutFor(screen.size, screen.class, 1.45)
			-- Fix batch: the badge row grows with the chips' text (Close no longer sets its height).
			expect.equal(large.header.h > normal.header.h, true)
			expect.equal(large.caption.h > normal.caption.h, true)
			expect.equal(large.stage.h < normal.stage.h, true)
			expectTouchTargets(large)
			expectSound(large, screen.size)
		end
	end)

	t.test("layoutFor: a bad text scale means 1", function()
		local size = Vector2.new(1280, 720)
		local normal = InspectPanel.layoutFor(size, "regular")
		expect.deepEqual(InspectPanel.layoutFor(size, "regular", 0 / 0), normal)
		expect.deepEqual(InspectPanel.layoutFor(size, "regular", -2), normal)
		expect.deepEqual(InspectPanel.layoutFor(size, "regular", 1), normal)
	end)

	t.test("layoutFor: a zero or NaN screen falls back to 1280x720; an unknown class is regular", function()
		local fallback = InspectPanel.layoutFor(Vector2.new(1280, 720), "regular")
		expect.deepEqual(InspectPanel.layoutFor(Vector2.new(0, 0), "regular"), fallback)
		expect.deepEqual(InspectPanel.layoutFor(Vector2.new(0 / 0, 0 / 0), "regular"), fallback)
		expect.deepEqual(InspectPanel.layoutFor(Vector2.new(1280, 720), "sideways" :: any), fallback)
	end)

	-- Part 8 --------------------------------------------------------------------------------------------------------

	local Strings = t.requireShared("Strings")
	local Theme = t.requireClient("UI/Theme")
	local EM = 0.6 -- per character: wider than Builder Sans Bold really is (a pessimistic estimate)
	local function buttonWidth(text: string, textScale: number): number
		return #text * Config.UI.TextSize.Button * textScale * EM + 2 * 18 + 4
	end
	local ALL_SCREENS = {
		{ label = "667x375", size = Vector2.new(667, 375), class = "compact" },
		{ label = "893x673", size = Vector2.new(893, 673), class = "regular" },
		{ label = "1280x720", size = Vector2.new(1280, 720), class = "regular" },
		{ label = "1920x1080", size = Vector2.new(1920, 1080), class = "regular" },
	}

	t.test("buttonRows: one row when the buttons fit side by side, more when they do not", function()
		expect.deepEqual(InspectPanel.buttonRows(400, 400, { 120, 140 }, { 150 }), { stage = 1, info = 1 })
		expect.deepEqual(InspectPanel.buttonRows(200, 250, { 120, 140 }, { 150, 160 }), { stage = 2, info = 2 })
		expect.deepEqual(InspectPanel.buttonRows(200, 250, {}, {}), { stage = 1, info = 1 })
		-- A phone at the Largest text size: "Not owned" + "Buy" fit side by side (owner 2026-10-22: was "View in
		-- Shop", two rows).
		local largest = Config.UI.PreferredTextScale.Largest
		local phone = InspectPanel.layoutFor(Vector2.new(667, 375), "compact", largest)
		local rows = InspectPanel.buttonRows(phone.stage.w, phone.info.w, {
			buttonWidth(Strings.controls.squeeze, largest),
			buttonWidth(Strings.inspect.resetView, largest),
		}, {
			buttonWidth(Strings.common.notOwned, largest),
			buttonWidth(Strings.inspect.viewInShop, largest),
		})
		expect.equal(rows.info, 1)
	end)

	for _, screen in ALL_SCREENS do
		for _, textScale in { 1, Config.UI.PreferredTextScale.Largest } do
			t.test(`layoutFor {screen.label} text x{textScale} with measured rows: wrapped rows inside`, function()
				local first = InspectPanel.layoutFor(screen.size, screen.class, textScale)
				local rows = InspectPanel.buttonRows(first.stage.w, first.info.w, {
					buttonWidth(Strings.controls.squeeze, textScale),
					buttonWidth(Strings.inspect.resetView, textScale),
				}, {
					buttonWidth(Strings.common.notOwned, textScale),
					buttonWidth(Strings.inspect.viewInShop, textScale),
				})
				local l = InspectPanel.layoutFor(screen.size, screen.class, textScale, rows)
				expect.equal(l.stageRows, rows.stage)
				expect.equal(l.infoRows, rows.info)
				-- Every rect inside, columns side by side, the caption under the stage, the list above its buttons.
				for name, r in rects(l) do
					expectInside(name, r, l)
				end
				expect.equal(l.stage.x + l.stage.w <= l.info.x, true)
				expect.equal(l.caption.y >= l.stage.y + l.stage.h, true)
				expect.equal(l.stageButtons.y >= l.caption.y + l.caption.h, true)
				expect.equal(l.infoButtons.y >= l.info.y + l.info.h, true)
				-- Fix round 2: wrapped rows sit Theme.Padding.medium apart, like the buttons in a row.
				expect.near(l.stageButtons.h, rows.stage * l.buttonHeight + (rows.stage - 1) * Theme.Padding.medium)
				expect.near(l.infoButtons.h, rows.info * l.buttonHeight + (rows.info - 1) * Theme.Padding.medium)
				-- Both rows end on one bottom edge.
				expect.near(l.stageButtons.y + l.stageButtons.h, l.infoButtons.y + l.infoButtons.h)
				expect.equal(l.info.w > 0 and l.info.h > 0, true)
				expect.equal(l.stage.h > 0, true)
				-- The columns fit the buttons once wrapped: no button is wider than its column.
				expect.truthy(buttonWidth(Strings.inspect.viewInShop, textScale) <= l.info.w)
				expect.truthy(buttonWidth(Strings.inspect.resetView, textScale) <= l.stage.w)
				-- One row everywhere: the old layout exactly.
				local plain = InspectPanel.layoutFor(screen.size, screen.class, textScale, { stage = 1, info = 1 })
				expect.deepEqual(plain, first)
			end)
		end
	end

	-- Foam UI restyle --------------------------------------------------------------------------------------------------

	-- The header tab's room at the top of the panel (Title-kind tab: about 34 base px at the default text, 42 at the
	-- Largest; both generous).
	local TAB_TOPS = { 34, 42 }

	for _, screen in ALL_SCREENS do
		t.test(`layoutFor {screen.label} with a header tab: the content box shrinks, every rect inside`, function()
			for _, top in TAB_TOPS do
				for _, textScale in { 1, Config.UI.PreferredTextScale.Largest } do
					local plain = InspectPanel.layoutFor(screen.size, screen.class, textScale)
					local first = InspectPanel.layoutFor(screen.size, screen.class, textScale, nil, top)
					expect.equal(first.topPadding, top)
					expect.near(first.contentHeight, plain.contentHeight - (top - plain.padding))
					expect.equal(first.panelHeight, plain.panelHeight)
					local rows = InspectPanel.buttonRows(first.stage.w, first.info.w, {
						buttonWidth(Strings.controls.squeeze, textScale),
						buttonWidth(Strings.inspect.resetView, textScale),
					}, {
						buttonWidth(Strings.common.notOwned, textScale),
						buttonWidth(Strings.inspect.viewInShop, textScale),
					})
					local l = InspectPanel.layoutFor(screen.size, screen.class, textScale, rows, top)
					for name, r in rects(l) do
						expectInside(name, r, l)
					end
					expect.equal(l.stage.y >= l.header.y + l.header.h, true)
					expect.near(l.stageButtons.y + l.stageButtons.h, l.contentHeight)
					expect.near(l.infoButtons.y + l.infoButtons.h, l.contentHeight)
					expect.equal(l.stage.h > 0 and l.info.h > 0, true)
					-- The panel and the tab's outer half (half the tab: top - its 6 px gap) fit the screen together.
					expect.truthy((l.panelHeight + (top - 6)) * l.scale <= screen.size.Y + EPS)
				end
			end
		end)
	end

	-- Foam fix batch ------------------------------------------------------------------------------------------------

	t.test("layoutFor: Close hangs on the corner, so the stage gets the old Close row's room back", function()
		for _, screen in ALL_SCREENS do
			for _, textScale in { 1, Config.UI.PreferredTextScale.Largest } do
				local l = InspectPanel.layoutFor(screen.size, screen.class, textScale)
				-- The body starts under the badge row (fix round 2: Theme.Padding.medium under it, the chips' outline and
				-- drop took the old 6 px); before the fix batch it started under a Close-tall row.
				expect.equal(l.stage.y, l.header.h + Theme.Padding.medium)
				expect.equal(l.closeHeight - l.header.h > 0, true)
				expect.equal(l.stage.h > 0, true)
			end
		end
	end)

	-- Foam fix round 2 -------------------------------------------------------------------------------------------------

	t.test(
		"buttonRows: the buttons of a row keep Theme.Padding.medium between them (6 px read as one button)",
		function()
			-- 120 + 122 fit a 250 px column 6 apart but not 12 apart.
			expect.deepEqual(InspectPanel.buttonRows(250, 250, { 120, 122 }, { 120, 122 }), { stage = 2, info = 2 })
			expect.deepEqual(InspectPanel.buttonRows(254, 254, { 120, 122 }, { 120, 122 }), { stage = 1, info = 1 })
		end
	)

	t.test("layoutFor: a missing, bad or too small top padding means the panel padding", function()
		local size = Vector2.new(1280, 720)
		local plain = InspectPanel.layoutFor(size, "regular")
		expect.equal(plain.topPadding, plain.padding)
		for _, bad in { 0 / 0, -5, 0, plain.padding, math.huge } do
			expect.deepEqual(InspectPanel.layoutFor(size, "regular", nil, nil, bad), plain)
		end
	end)

	t.test("howToGetSlots: one line per box plus one shop line", function()
		expect.equal(InspectPanel.howToGetSlots(), #Boxes.list() + 1)
		-- Every box that holds a squishy fits in the pool, with the shop line.
		local Catalog = t.requireShared("Catalog")
		for _, def in Catalog.list() do
			local lines = #Boxes.containing(def.id) + (if def.shopPrice ~= nil then 1 else 0)
			expect.equal(lines <= InspectPanel.howToGetSlots(), true)
		end
	end)
end
