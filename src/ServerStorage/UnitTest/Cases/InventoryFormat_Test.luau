--!strict
-- InventoryFormat_Test: StarterPlayerScripts.Client.UI.InventoryFormat (the Squishies screen as data). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §11.6, §10.8, §4.3, §5.8, §11.4):
--   * one entry per Catalog squishy, sorted: equipped first, then rarity descending, then name; an unowned squishy is
--     never "equipped" or "new";
--   * filters All, Common, Uncommon, Epic, Exclusive (L1 / R1 wrap around); "Show not owned" off hides unowned cards;
--     chip counts are what each chip would show; "Collected {n}/14";
--   * columns = floor(gridWidth / (cardWidth + pad)), at least 1; the selection is kept while visible;
--   * the Equip button: Not owned, Equipped (also right after the server's ok), loading, locked in a duel, Equip;
--   * the five throw stats as bars inside the §5.8 bands, in the §10.8 order.
-- Part 8 (DESIGN §11.2, §11.6; the Squishies fold and the "Not oUltimate" tags of Part 6's Studio run), at 667×375 (a
-- phone, compact), 893×673 (Studio's window, where the buttons sat below the fold), 1280×720 and 1920×1080, each at the
-- default and the largest text size (×1.45; button widths from a generous per-character estimate):
--   * panelLayout: the panel fits the screen; header and filter row touch-sized (>= minTargetFloor actual px); the
--     body and the two columns inside the content box; PANEL's gaps equal Theme's tokens;
--   * detailLayout: Equip / Inspect / View in Shop wrap inside the detail column, never overlap, and sit pinned under
--     the list inside the column (so inside the panel) at every size; the list keeps a positive height;
--   * cardSize: 112 × 168 at the default text with the rarity tag stacked ("◆◆◆◆ EXCLUSIVE" does not fit a card side
--     by side); larger only when the text needs it; never narrower than the widest word or tag;
--   * cardTags: the corner badges never overlap at any card width or text size; "Not owned" + "Ultimate" on a
--     112 px card take two rows (the "Not oUltimate" case); a lone badge stays at the top.
-- Foam UI restyle (2026-10-09):
--   * panelLayout(screen, topPadding): the header tab's top padding shrinks the content box by the difference, the
--     body still ends at its bottom, the detail buttons still pin inside it, and the panel with the tab's outer half
--     fits the screen; a missing, bad or too small padding means PANEL.padding (topPadding);
--   * cardSize: CardBase.bands (the foam bevel and drop) is kept free under the rows; a bad value counts as none.
-- Foam fix batch (2026-10-09; the phone cut-offs, the empty strip beside the grid, "Ultimate" on the Dragon):
--   * hangingChrome: the top padding keeps the tab gap under the lower halves of the tab and the hanging Close (never
--     below the panel padding); the panel moves down by half of what hangs above it; the panel with what hangs above it
--     fits the screen;
--   * panelLayout: no header row (the filter row starts the content: bodyTop = row + gap); with a card width the grid
--     takes the columns that fit in gridShare (gridFit) and leaves less than one card of room unused, and the detail
--     column takes the rest; on a 844×390-sized screen (a phone) the three detail buttons fit one row and the column
--     shows the preview and the name above them;
--   * gridFit: the most columns that fit (at least 1), the width exactly those columns take plus GRID_FIT_SLACK (review
--     fix: an exact fit could wrap a column under a fractional UI scale), never past the limit;
--   * previewPx: the preview shrinks so the name stays in view, between its min and max;
--   * cardBadges: one row always (never on the portrait): the compact left badge when it lets both fit, else the right
--     one is left out; "Not owned" + "Ultimate" on the Squishies card fit with the lock pip.
-- Foam fix round 2 (2026-10-09; the rarity tag cut in half on a phone, the detail buttons nearly touching):
--   * previewPx hides the preview (0) when not even its minimum fits above the reserve; on the 844×390 phone the
--     reserve (name and rarity tag) fits under a smaller preview;
--   * detailLayout keeps PANEL.buttonGap (Theme.Padding.medium) between the buttons and their rows, from the column's
--     left edge, and the list still ends PANEL.gap above them.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local InventoryFormat = t.requireClient("UI/InventoryFormat")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")

	local function never(_: string): boolean
		return false
	end

	local function ids(list: { any }): { string }
		local out = {}
		for _, entry in list do
			table.insert(out, entry.id)
		end
		return out
	end

	local function owned(list: { string }): { [string]: any }
		local map = {}
		for _, id in list do
			map[id] = { at = 1, src = "box" }
		end
		return map
	end

	t.test("entries: equipped first, then rarity descending, then name", function()
		local list = InventoryFormat.entries(Catalog.list(), owned({ "kitty_bread", "toast", "bird" }), "toast", never)
		expect.equal(#list, #Catalog.list())
		expect.equal(list[1].id, "toast")
		expect.equal(list[1].equipped, true)
		expect.equal(list[2].id, "dragon") -- Exclusive, unowned
		expect.equal(list[2].owned, false)
		-- Epic by name: Birdie, Cloud Bunny, Cupcake Axolotl, Donut
		expect.deepEqual(
			ids({ list[3], list[4], list[5], list[6] }),
			{ "bird", "cloud_bunny", "cupcake_axolotl", "donut" }
		)
		-- Commons last, by name (Banana, Boba Bear, Kitty Bread, Pancake Pup; Toast is equipped, so first)
		local tail = ids({ list[#list - 3], list[#list - 2], list[#list - 1], list[#list] })
		expect.deepEqual(tail, { "banana", "boba_bear", "kitty_bread", "pancake_pup" })
		for _, entry in list do
			if not entry.owned then
				expect.equal(entry.equipped, false)
				expect.equal(entry.isNew, false)
			end
		end
	end)

	t.test("entries: an unowned equipped id is never shown as equipped; new only for owned ids", function()
		local list = InventoryFormat.entries(Catalog.list(), owned({ "kitty_bread" }), "dragon", function(id: string)
			return id == "kitty_bread" or id == "dragon"
		end)
		for _, entry in list do
			expect.equal(entry.equipped, false)
			expect.equal(entry.isNew, entry.id == "kitty_bread")
		end
	end)

	t.test("filters: cycle with wrap-around; visible cards and chip counts follow Show not owned", function()
		expect.deepEqual(InventoryFormat.FILTERS, { "All", "Common", "Uncommon", "Epic", "Exclusive" })
		expect.equal(InventoryFormat.nextFilter("All", 1), "Common")
		expect.equal(InventoryFormat.nextFilter("Exclusive", 1), "All")
		expect.equal(InventoryFormat.nextFilter("All", -1), "Exclusive")
		expect.equal(InventoryFormat.nextFilter("Nope", 1), "Common")

		local list = InventoryFormat.entries(Catalog.list(), owned({ "kitty_bread", "butter" }), "kitty_bread", never)
		expect.equal(#InventoryFormat.visible(list, "All", true), #Catalog.list())
		expect.deepEqual(ids(InventoryFormat.visible(list, "All", false)), { "kitty_bread", "butter" })
		expect.deepEqual(ids(InventoryFormat.visible(list, "Uncommon", false)), { "butter" })
		expect.equal(#InventoryFormat.visible(list, "Exclusive", false), 0)

		local shown = InventoryFormat.chipCounts(list, true)
		expect.deepEqual(shown, { All = 14, Common = 5, Uncommon = 4, Epic = 4, Exclusive = 1 })
		local ownedOnly = InventoryFormat.chipCounts(list, false)
		expect.deepEqual(ownedOnly, { All = 2, Common = 1, Uncommon = 1, Epic = 0, Exclusive = 0 })
		local n, total = InventoryFormat.collected(list)
		expect.equal(n, 2)
		expect.equal(total, 14)
	end)

	t.test("chips and empty state: texts from Strings", function()
		expect.equal(InventoryFormat.filterName("All"), Strings.inventory.filterAll)
		expect.equal(InventoryFormat.filterName("Epic"), Strings.rarity.epic.name)
		expect.equal(
			InventoryFormat.chipText("Epic", 2),
			Strings.format(Strings.inventory.filterCount, { label = Strings.rarity.epic.name, n = 2 })
		)
		expect.equal(
			InventoryFormat.emptyText("Epic"),
			Strings.format(Strings.inventory.empty, { rarity = Strings.rarity.epic.name })
		)
		local all = InventoryFormat.emptyText("All")
		expect.equal(string.find(all, "  ", 1, true), nil) -- no double space where the rarity was
		expect.equal(string.find(all, "{", 1, true), nil)
	end)

	t.test("grid: columns from the width; the selection is kept while visible", function()
		local card, pad = Config.UI.Inventory.cardWidth, 8
		expect.equal(InventoryFormat.columns(card * 4 + pad * 4, card, pad), 4)
		expect.equal(InventoryFormat.columns(card * 4 + pad * 4 - 1, card, pad), 3)
		expect.equal(InventoryFormat.columns(10, card, pad), 1)
		expect.equal(InventoryFormat.columns(0 / 0, card, pad), 1)

		local list = InventoryFormat.entries(Catalog.list(), owned({ "kitty_bread", "butter" }), "kitty_bread", never)
		local visible = InventoryFormat.visible(list, "All", true)
		expect.equal(InventoryFormat.keepSelection("donut", visible), "donut")
		local commons = InventoryFormat.visible(list, "Common", true)
		expect.equal(InventoryFormat.keepSelection("donut", commons), commons[1].id)
		expect.equal(InventoryFormat.keepSelection(nil, commons), commons[1].id)
		expect.equal(InventoryFormat.keepSelection("donut", {}), nil)
	end)

	t.test("equip button: not owned, equipped, loading, locked, equip", function()
		local list = InventoryFormat.entries(Catalog.list(), owned({ "kitty_bread", "toast" }), "kitty_bread", never)
		local byId = {}
		for _, entry in list do
			byId[entry.id] = entry
		end
		local idle = { locked = false, pending = nil, confirmed = nil }
		expect.equal(InventoryFormat.equipState(byId.dragon, idle), "notOwned")
		expect.equal(InventoryFormat.equipState(byId.kitty_bread, idle), "equipped")
		expect.equal(InventoryFormat.equipState(byId.toast, idle), "equip")
		expect.equal(InventoryFormat.equipState(byId.toast, { locked = false, pending = "toast" }), "loading")
		expect.equal(InventoryFormat.equipState(byId.toast, { locked = false, confirmed = "toast" }), "equipped")
		expect.equal(InventoryFormat.equipState(byId.toast, { locked = true }), "locked")
		expect.equal(InventoryFormat.equipState(byId.dragon, { locked = true }), "notOwned")
		expect.equal(InventoryFormat.ownershipKey(byId.kitty_bread), "common.equipped")
		expect.equal(InventoryFormat.ownershipKey(byId.toast), "common.owned")
		expect.equal(InventoryFormat.ownershipKey(byId.dragon), "common.notOwned")
	end)

	-- Part 8 layout ---------------------------------------------------------------------------------------------------

	local Theme = t.requireClient("UI/Theme")
	local TOUCH = Config.UI.Touch
	-- UI FINAL R2 (P1): a primary Button's frame, its 56 px face and the 5 px lip under it (Button.frameHeight).
	local BUTTON_FRAME = TOUCH.primaryButton + Config.UI.Sticker.lip.button
	local EPS = 1e-6
	local SCREENS = {
		{ label = "667x375", size = Vector2.new(667, 375) },
		{ label = "893x673", size = Vector2.new(893, 673) },
		{ label = "1280x720", size = Vector2.new(1280, 720) },
		{ label = "1920x1080", size = Vector2.new(1920, 1080) },
	}
	local TEXT_SCALES = { 1, Config.UI.PreferredTextScale.Largest }
	local EM = 0.6 -- per character: wider than Builder Sans Bold really is (a pessimistic estimate)
	local BUTTON_PADDING = 2 * 18 + 4 -- Button's side padding and its measure margin

	local function buttonWidth(text: string, textScale: number): number
		return #text * Config.UI.TextSize.Button * textScale * EM + BUTTON_PADDING
	end

	-- Every button state the detail panel can show: Equip alone, Equip + Inspect, Not owned + Inspect + View in Shop.
	local function buttonSets(textScale: number): { { number } }
		local equip = buttonWidth(Strings.common.equip, textScale)
		local equipped = buttonWidth(Strings.common.equipped, textScale)
		local notOwned = buttonWidth(Strings.common.notOwned, textScale)
		local inspect = buttonWidth(Strings.common.inspect, textScale)
		local viewInShop = buttonWidth(Strings.inspect.viewInShop, textScale)
		return { { equip }, { equipped, inspect }, { equip, inspect }, { notOwned, inspect, viewInShop } }
	end

	local function overlap(a: any, b: any): boolean
		return a.x < b.x + b.w - EPS and b.x < a.x + a.w - EPS and a.y < b.y + b.h - EPS and b.y < a.y + a.h - EPS
	end

	for _, screen in SCREENS do
		t.test(`panelLayout {screen.label}: fits the screen, touch-sized Close and filter row`, function()
			local l = InventoryFormat.panelLayout(screen.size)
			expect.truthy(l.panelWidth <= Config.UI.modalMaxWidth)
			expect.truthy(l.panelWidth * l.scale <= screen.size.X + EPS)
			expect.truthy(l.panelHeight * l.scale <= screen.size.Y + EPS)
			expect.truthy(l.closeHeight >= TOUCH.closeButton)
			expect.truthy(l.rowHeight >= TOUCH.minTarget)
			expect.truthy(l.rowHeight * l.scale >= TOUCH.minTargetFloor - EPS)
			expect.truthy(l.closeHeight * l.scale >= TOUCH.minTargetFloor - EPS)
			-- Fix batch: Close hangs on the corner, so the filter row starts the content.
			expect.near(l.bodyTop, l.rowHeight + InventoryFormat.PANEL.gap)
			expect.near(l.bodyTop + l.bodyHeight, l.contentHeight)
			expect.truthy(l.bodyHeight > 0)
			expect.truthy(l.gridWidth + InventoryFormat.PANEL.columnGap + l.detailWidth <= l.contentWidth + EPS)
			expect.truthy(l.detailWidth > 0)
			expect.equal(l.detailHeight, l.bodyHeight)
			expect.equal(l.columns, 0) -- no card width given: the plain gridShare split
			expect.equal(l.class, if screen.label == "667x375" then "compact" else "regular")
		end)

		for _, textScale in TEXT_SCALES do
			t.test(
				`detailLayout {screen.label} text x{textScale}: buttons pinned, wrapped, never overlapping`,
				function()
					local l = InventoryFormat.panelLayout(screen.size)
					local buttonHeight = BUTTON_FRAME
					local gap = InventoryFormat.PANEL.gap
					local between = InventoryFormat.PANEL.buttonGap -- fix round 2: the buttons' own gap
					for _, widths in buttonSets(textScale) do
						local d = InventoryFormat.detailLayout(l.detailWidth, l.detailHeight, buttonHeight, gap, widths)
						expect.equal(#d.buttons, #widths)
						expect.truthy(d.rows >= 1 and d.rows <= #widths)
						-- Pinned at the bottom of the column, under the list, inside the panel.
						expect.near(d.buttonsTop + d.buttonsHeight, l.detailHeight)
						expect.truthy(d.scrollHeight + gap <= d.buttonsTop + EPS)
						expect.truthy(l.bodyTop + d.buttonsTop + d.buttonsHeight <= l.contentHeight + EPS)
						expect.truthy(d.scrollHeight > 0)
						expect.near(d.buttonsHeight, d.rows * buttonHeight + (d.rows - 1) * between)
						local total = 0
						for i, r in d.buttons do
							expect.near(r.w, widths[i])
							expect.truthy(r.x >= -EPS and r.x + r.w <= l.detailWidth + EPS)
							expect.truthy(r.y >= -EPS and r.y + r.h <= d.buttonsHeight + EPS)
							for j = i + 1, #d.buttons do
								expect.falsy(overlap(r, d.buttons[j]))
							end
							total += r.w
						end
						-- One row exactly when they all fit side by side.
						local oneRow = total + between * (#widths - 1) <= l.detailWidth + EPS
						expect.equal(d.rows == 1, oneRow)
					end
				end
			)
		end
	end

	t.test("detailLayout: Studio's 893x673 with three buttons keeps them on screen (the Part 6 fold)", function()
		local l = InventoryFormat.panelLayout(Vector2.new(893, 673))
		local widths = buttonSets(1)[4]
		local d = InventoryFormat.detailLayout(l.detailWidth, l.detailHeight, BUTTON_FRAME, 6, widths)
		-- Actual px from the panel's top edge: the buttons end inside the panel's content box.
		local bottom = (l.bodyTop + d.buttonsTop + d.buttonsHeight) * l.scale
		expect.truthy(bottom <= l.contentHeight * l.scale + EPS)
		-- No buttons: the list takes the whole column.
		local none = InventoryFormat.detailLayout(l.detailWidth, l.detailHeight, BUTTON_FRAME, 6, {})
		expect.equal(none.rows, 0)
		expect.equal(none.scrollHeight, l.detailHeight)
		expect.equal(none.buttonsHeight, 0)
	end)

	t.test("PANEL: the gaps and padding are Theme's tokens", function()
		local panel = InventoryFormat.PANEL
		expect.equal(panel.padding, Theme.Padding.medium)
		expect.equal(panel.gap, Theme.Padding.small)
		expect.equal(panel.columnGap, Theme.Padding.medium)
		expect.near(panel.gridShare, (Config.UI.Inventory.gridWidthMin + Config.UI.Inventory.gridWidthMax) / 2)
		-- Fix batch: Theme.headerTab's 6 px gap, the grid's cell gap and its side room (4 + a 6 px scrollbar + 4).
		expect.equal(panel.tabGap, Theme.Padding.small)
		expect.equal(panel.cellPad, 8)
		expect.equal(panel.gridChrome, 4 + 6 + 4)
	end)

	-- A card's measured texts at a text scale (Small 16 bold; "EXCLUSIVE" chip with 8 px padding, 4 diamond pips of 8 px).
	local function cardMetrics(textScale: number): any
		local small = Config.UI.TextSize.Small * textScale
		local chip = #"EXCLUSIVE" * small * EM + 16
		local pips = 4 * 8 + 3 * 3
		return {
			nameWidth = #"Kitty Bread" * small * EM,
			wordWidth = #"Chocolate" * small * EM,
			lineHeight = small * 1.25,
			tagInlineWidth = pips + 6 + chip,
			tagInlineHeight = small * 1.25 + 4,
			tagStackedWidth = chip,
			tagStackedHeight = 8 + 2 + small * 1.25 + 4,
		}
	end
	local SQUISHIES_CARD =
		{ width = Config.UI.Inventory.cardWidth, height = 168, iconPx = 84, padX = 4, padY = 6, gap = 2 }

	t.test("cardSize: the default card keeps 112 x 168 with the rarity tag stacked; larger text grows it", function()
		local normal = InventoryFormat.cardSize(SQUISHIES_CARD, {
			nameWidth = 66,
			wordWidth = 57,
			lineHeight = 20,
			tagInlineWidth = 125,
			tagInlineHeight = 24,
			tagStackedWidth = 80,
			tagStackedHeight = 34,
		})
		expect.deepEqual(normal, { width = 112, height = 168, nameLines = 1, stacked = true })
		for _, textScale in TEXT_SCALES do
			local m = cardMetrics(textScale)
			local size = InventoryFormat.cardSize(SQUISHIES_CARD, m)
			expect.truthy(size.width >= SQUISHIES_CARD.width and size.height >= SQUISHIES_CARD.height)
			local inner = size.width - 2 * SQUISHIES_CARD.padX
			expect.truthy(m.wordWidth <= inner + EPS)
			expect.truthy(m.tagStackedWidth <= inner + EPS)
			expect.equal(size.stacked, m.tagInlineWidth > inner)
			if not size.stacked then
				expect.truthy(m.tagInlineWidth <= inner + EPS)
			end
			local tagHeight = if size.stacked then m.tagStackedHeight else m.tagInlineHeight
			local needed = 12 + 84 + 2 + size.nameLines * m.lineHeight + 2 + tagHeight
			expect.truthy(needed <= size.height + EPS)
		end
		-- A wide shop card fits the tag side by side at the default text.
		local shop = InventoryFormat.cardSize({
			width = 150,
			height = 184,
			iconPx = 92,
			padX = 6,
			padY = 6,
			gap = 2,
			extraWidth = 100,
			extraHeight = 20,
		}, {
			nameWidth = 66,
			wordWidth = 57,
			lineHeight = 20,
			tagInlineWidth = 125,
			tagInlineHeight = 24,
			tagStackedWidth = 80,
			tagStackedHeight = 34,
		})
		expect.deepEqual(shop, { width = 150, height = 184, nameLines = 1, stacked = false })
	end)

	-- Foam UI restyle (2026-10-09) ------------------------------------------------------------------------------------

	-- The header tab's room at the top of the panel (an H2 tab: about 29 base px at the default text, 35 at Largest).
	local TAB_TOPS = { 29, 35 }

	for _, screen in SCREENS do
		t.test(`panelLayout {screen.label} with a header tab: the content box shrinks, the rest still fits`, function()
			local plain = InventoryFormat.panelLayout(screen.size)
			expect.equal(plain.topPadding, InventoryFormat.PANEL.padding)
			for _, top in TAB_TOPS do
				local l = InventoryFormat.panelLayout(screen.size, top)
				expect.equal(l.topPadding, top)
				expect.near(l.contentHeight, plain.contentHeight - (top - InventoryFormat.PANEL.padding))
				expect.equal(l.panelHeight, plain.panelHeight)
				expect.near(l.bodyTop + l.bodyHeight, l.contentHeight)
				expect.truthy(l.bodyHeight > 0)
				expect.equal(l.detailHeight, l.bodyHeight)
				-- The panel and the tab's outer half (top - its 6 px gap) fit the screen together.
				expect.truthy((l.panelHeight + (top - 6)) * l.scale <= screen.size.Y + EPS)
				-- The detail buttons still pin inside the shorter column.
				for _, textScale in TEXT_SCALES do
					for _, widths in buttonSets(textScale) do
						local d = InventoryFormat.detailLayout(
							l.detailWidth,
							l.detailHeight,
							BUTTON_FRAME,
							InventoryFormat.PANEL.gap,
							widths
						)
						expect.truthy(l.bodyTop + d.buttonsTop + d.buttonsHeight <= l.contentHeight + EPS)
						expect.truthy(d.scrollHeight > 0)
					end
				end
			end
		end)
	end

	t.test("topPadding: a missing, bad or too small padding means the panel padding", function()
		local padding = InventoryFormat.PANEL.padding
		expect.equal(InventoryFormat.topPadding(nil), padding)
		for _, bad in { 0 / 0, -4, 0, padding, math.huge } do
			expect.equal(InventoryFormat.topPadding(bad), padding)
		end
		expect.equal(InventoryFormat.topPadding(29), 29)
		local size = Vector2.new(1280, 720)
		expect.deepEqual(InventoryFormat.panelLayout(size, 0 / 0), InventoryFormat.panelLayout(size))
	end)

	t.test("cardSize: a foam card keeps its bands free under the rows", function()
		local metrics = {
			nameWidth = 66,
			wordWidth = 57,
			lineHeight = 20,
			tagInlineWidth = 125,
			tagInlineHeight = 24,
			tagStackedWidth = 80,
			tagStackedHeight = 34,
		}
		local base = {
			width = SQUISHIES_CARD.width,
			height = SQUISHIES_CARD.height,
			iconPx = SQUISHIES_CARD.iconPx,
			padX = SQUISHIES_CARD.padX,
			padY = SQUISHIES_CARD.padY,
			gap = SQUISHIES_CARD.gap,
			bands = 9,
		}
		-- Rows: 12 + 84 + 2 + 20 + 2 + 34 = 154, + 9 = 163: still the base height.
		expect.deepEqual(
			InventoryFormat.cardSize(base, metrics),
			{ width = 112, height = 168, nameLines = 1, stacked = true }
		)
		for _, textScale in TEXT_SCALES do
			local m = cardMetrics(textScale)
			local size = InventoryFormat.cardSize(base, m)
			local without = InventoryFormat.cardSize(SQUISHIES_CARD, m)
			expect.equal(size.width, without.width)
			local tagHeight = if size.stacked then m.tagStackedHeight else m.tagInlineHeight
			local needed = 12 + 84 + 2 + size.nameLines * m.lineHeight + 2 + tagHeight + base.bands
			expect.truthy(needed <= size.height + EPS)
		end
		-- Bands that are not a positive number count as none.
		base.bands = -5
		expect.deepEqual(InventoryFormat.cardSize(base, metrics), InventoryFormat.cardSize(SQUISHIES_CARD, metrics))
	end)

	t.test("cardTags: the corner badges never overlap (the 'Not oUltimate' case takes two rows)", function()
		local inset, gap = 4, 2
		local function rects(cardWidth: number, left: any, right: any): (any, any, any)
			local tags = InventoryFormat.cardTags(cardWidth, inset, gap, left, right)
			local a = { x = inset, y = tags.leftY, w = left.w, h = left.h }
			local b = { x = cardWidth - inset - right.w, y = tags.rightY, w = right.w, h = right.h }
			return tags, a, b
		end
		-- Part 6's Studio run: "Not owned" (lock + text, 79 px) and "Ultimate" (58 px) on a 112 px card.
		local tags, a, b = rects(112, { w = 79, h = 14 }, { w = 58, h = 14 })
		expect.equal(tags.twoRows, true)
		expect.falsy(overlap(a, b))
		expect.equal(tags.rightY, inset + 14 + gap)
		-- Small enough for one row.
		tags, a, b = rects(150, { w = 40, h = 14 }, { w = 58, h = 14 })
		expect.equal(tags.twoRows, false)
		expect.falsy(overlap(a, b))
		-- A lone badge stays at the top.
		expect.deepEqual(
			InventoryFormat.cardTags(112, inset, gap, nil, { w = 58, h = 14 }),
			{ twoRows = false, leftY = inset, rightY = inset }
		)
		expect.deepEqual(
			InventoryFormat.cardTags(112, inset, gap, { w = 79, h = 14 }, nil),
			{ twoRows = false, leftY = inset, rightY = inset }
		)
		-- Every card width and text size: never an overlap.
		for _, textScale in TEXT_SCALES do
			local small = Config.UI.TextSize.Small * textScale
			for _, leftText in { Strings.common.notOwned, Strings.common.equipped, Strings.inventory.new } do
				local left = { w = #leftText * small * EM + 12 + 3 + 10, h = small * 1.25 }
				local right = { w = #Strings.rarity.ultimateBadge * small * EM + 10, h = small * 1.25 }
				for width = 80, 260, 4 do
					local _, ra, rb = rects(width, left, right)
					expect.falsy(overlap(ra, rb))
				end
			end
		end
	end)

	-- Foam fix batch (2026-10-09) -------------------------------------------------------------------------------------

	local PANEL = InventoryFormat.PANEL
	-- The Squishies card at the default text (§11.6's 112 + the 12 px display-font room) and an H2 header tab (about
	-- 45 base px: its line, padding and foam bands).
	local CARD_WIDTH = Config.UI.Inventory.cardWidth + 12
	local TAB_HEIGHT = 45
	-- SD_Modal on an 844×390 phone: its safe area, as measured in the foam shots (the 0.88 panel was 274 px tall).
	local PHONE = Vector2.new(844, 311)

	t.test(
		"hangingChrome: room under the tab's and Close's lower halves; the panel moves down by half of the rest",
		function()
			local both = InventoryFormat.hangingChrome(TAB_HEIGHT, TOUCH.closeButton)
			expect.equal(both.top, math.ceil(TOUCH.closeButton / 2) + PANEL.tabGap) -- Close is the taller one
			expect.near(both.above, TOUCH.closeButton / 2)
			expect.equal(both.shift, math.floor(TOUCH.closeButton / 4))
			-- No Close (the box reveal): the old header-tab rule exactly.
			local tabOnly = InventoryFormat.hangingChrome(TAB_HEIGHT, 0)
			expect.equal(tabOnly.top, math.ceil(TAB_HEIGHT / 2) + PANEL.tabGap)
			expect.equal(tabOnly.shift, math.floor(TAB_HEIGHT / 4))
			-- Nothing hanging: the panel padding, no shift; a given padding wins when it is larger.
			expect.deepEqual(InventoryFormat.hangingChrome(0, 0), { top = PANEL.padding, above = 0, shift = 0 })
			expect.equal(InventoryFormat.hangingChrome(TAB_HEIGHT, 0, 40).top, 40)
			expect.deepEqual(InventoryFormat.hangingChrome(0 / 0, -5), { top = PANEL.padding, above = 0, shift = 0 })
			-- The panel, moved down, keeps what hangs above it and its own bottom on the screen.
			for _, screen in { { size = PHONE }, table.unpack(SCREENS) } :: { any } do
				for _, tab in { TAB_HEIGHT, 56 } do
					local chrome = InventoryFormat.hangingChrome(tab, TOUCH.closeButton)
					local l = InventoryFormat.panelLayout(screen.size, chrome.top)
					local margin = (screen.size.Y / l.scale - l.panelHeight) / 2
					expect.truthy(margin + chrome.shift >= chrome.above - EPS)
					expect.truthy(margin - chrome.shift >= -EPS)
				end
			end
		end
	)

	t.test("gridFit: the columns that fit and exactly their width, never past the limit", function()
		-- Review fix: the width keeps GRID_FIT_SLACK (1 base px) over the cells, so an exact fit never wraps a column
		-- under a fractional UI scale.
		local slack = InventoryFormat.GRID_FIT_SLACK
		expect.equal(slack, 1)
		expect.deepEqual(
			InventoryFormat.gridFit(529.5, 124, 8, 14),
			{ columns = 3, width = 14 + slack + 3 * 124 + 2 * 8 }
		)
		local four = 14 + slack + 4 * 124 + 3 * 8
		expect.deepEqual(InventoryFormat.gridFit(four, 124, 8, 14), { columns = 4, width = four })
		expect.deepEqual(InventoryFormat.gridFit(four - 1, 124, 8, 14), { columns = 3, width = 402 + slack })
		expect.deepEqual(InventoryFormat.gridFit(533, 124, 8, 14), { columns = 3, width = 402 + slack })
		-- A card wider than the room still takes one column, inside the limit.
		expect.deepEqual(InventoryFormat.gridFit(100, 124, 8, 14), { columns = 1, width = 100 })
		expect.deepEqual(InventoryFormat.gridFit(0 / 0, 124, 8, 14), { columns = 1, width = 0 })
		for limit = 150, 900, 7 do
			local fit = InventoryFormat.gridFit(limit, 124, 8, 14)
			expect.truthy(fit.columns >= 1)
			expect.truthy(fit.width <= limit + EPS)
			-- No room for one more column is left unused.
			expect.truthy(limit - fit.width < 124 + 8)
		end
	end)

	for _, screen in { { label = "844x390 phone", size = PHONE }, table.unpack(SCREENS) } :: { any } do
		t.test(
			`panelLayout {screen.label} with the card width: the grid fits its columns, the detail takes the rest`,
			function()
				local chrome = InventoryFormat.hangingChrome(TAB_HEIGHT, TOUCH.closeButton)
				local plain = InventoryFormat.panelLayout(screen.size, chrome.top)
				for _, cardWidth in { CARD_WIDTH, 150, 181 } do
					local l = InventoryFormat.panelLayout(screen.size, chrome.top, cardWidth)
					expect.truthy(l.columns >= 1)
					expect.truthy(l.gridWidth <= plain.gridWidth + EPS)
					expect.near(
						l.gridWidth,
						math.min(
							plain.gridWidth,
							PANEL.gridChrome
								+ InventoryFormat.GRID_FIT_SLACK
								+ l.columns * cardWidth
								+ (l.columns - 1) * PANEL.cellPad
						)
					)
					expect.truthy(plain.gridWidth - l.gridWidth < cardWidth + PANEL.cellPad)
					expect.near(l.gridWidth + PANEL.columnGap + l.detailWidth, l.contentWidth)
					expect.truthy(l.detailWidth >= plain.detailWidth - EPS)
					-- The rest of the layout does not depend on the cards.
					expect.equal(l.bodyTop, plain.bodyTop)
					expect.equal(l.bodyHeight, plain.bodyHeight)
				end
			end
		)
	end

	t.test(
		"844x390 phone: the three detail buttons fit one row and the preview and the name show above them",
		function()
			local chrome = InventoryFormat.hangingChrome(TAB_HEIGHT, TOUCH.closeButton)
			local l = InventoryFormat.panelLayout(PHONE, chrome.top, CARD_WIDTH)
			expect.equal(l.class, "compact")
			expect.equal(l.columns, 3)
			local d =
				InventoryFormat.detailLayout(l.detailWidth, l.detailHeight, BUTTON_FRAME, PANEL.gap, buttonSets(1)[4])
			expect.equal(d.rows, 1)
			-- Fix round 2: the reserve under the well is the list gap, the name line, the gap and the rarity tag (the tag
			-- was cut in half above the buttons).
			local tag = Config.UI.TextSize.Chip * 1.3 + 2 * 2 + 2 * 2 -- the chip's line and padding, its outline room
			local reserve = 2 * Theme.Padding.small + Config.UI.TextSize.Title * 1.3 + tag
			local icon = InventoryFormat.previewPx(d.scrollHeight, reserve, 8, 48, 88)
			expect.truthy(icon >= 48 and icon < 88) -- a smaller preview, and the tag whole under the name
			expect.truthy(2 * 8 + icon + reserve <= d.scrollHeight + EPS)
		end
	)

	t.test("previewPx: the preview shrinks so the name stays in view; below its min it hides (0)", function()
		expect.equal(InventoryFormat.previewPx(300, 45, 8, 48, 88), 88)
		expect.equal(InventoryFormat.previewPx(125, 45, 8, 48, 88), 125 - 16 - 45)
		-- Fix round 2: no room for the smallest preview: it hides, so what the reserve keeps (the rarity tag) is never cut.
		expect.equal(InventoryFormat.previewPx(60, 45, 8, 48, 88), 0)
		expect.equal(InventoryFormat.previewPx(16 + 45 + 47.5, 45, 8, 48, 88), 0)
		expect.equal(InventoryFormat.previewPx(16 + 45 + 48, 45, 8, 48, 88), 48)
		expect.equal(InventoryFormat.previewPx(0 / 0, 45, 8, 48, 88), 0)
		for height = 0, 400, 3 do
			local icon = InventoryFormat.previewPx(height, 45, 8, 48, 132)
			expect.truthy(icon == 0 or (icon >= 48 and icon <= 132))
			expect.equal(icon, math.floor(icon))
			if icon > 0 then
				expect.truthy(2 * 8 + icon + 45 <= height + EPS) -- the name under it stays in view
			end
		end
	end)

	-- Foam fix round 2 (2026-10-09) ------------------------------------------------------------------------------------

	t.test(
		"detailLayout: the buttons sit PANEL.buttonGap apart (6 read as one), the list ends PANEL.gap above",
		function()
			local Theme = t.requireClient("UI/Theme")
			expect.equal(PANEL.buttonGap, Theme.Padding.medium)
			expect.truthy(PANEL.buttonGap >= 2 * Theme.Stroke.ink + 4) -- both outlines and some air
			local d = InventoryFormat.detailLayout(500, 300, 56, PANEL.gap, { 100, 120, 140 })
			expect.equal(d.rows, 1)
			expect.equal(d.buttons[1].x, 0) -- the row starts at the column's left edge
			expect.equal(d.buttons[2].x, 100 + PANEL.buttonGap)
			expect.equal(d.buttons[3].x, 100 + 120 + 2 * PANEL.buttonGap)
			expect.equal(d.scrollHeight, 300 - 56 - PANEL.gap)
		end
	)

	t.test("cardBadges: one row always; the lock pip when it lets both fit, else no 'Ultimate'", function()
		local inset, gap = 4, 6
		local notOwned = { w = 108, h = 22 } -- the lock, "Not owned" and the chip padding (measured in the shots)
		local ultimate = { w = 80, h = 22 }
		local pip = { w = 24, h = 22 }
		-- The Dragon's Squishies card when not owned: the lock pip and "Ultimate" share the top row.
		expect.deepEqual(
			InventoryFormat.cardBadges(CARD_WIDTH, inset, gap, notOwned, ultimate, pip),
			{ compact = true, rightShown = true }
		)
		-- Owned and Equipped / NEW (no compact form): the card's state stays, "Ultimate" is left out.
		expect.deepEqual(
			InventoryFormat.cardBadges(CARD_WIDTH, inset, gap, { w = 90, h = 22 }, ultimate, nil),
			{ compact = false, rightShown = false }
		)
		-- Both fit: unchanged; a missing badge leaves the other alone.
		expect.deepEqual(
			InventoryFormat.cardBadges(260, inset, gap, notOwned, ultimate, pip),
			{ compact = false, rightShown = true }
		)
		expect.deepEqual(
			InventoryFormat.cardBadges(CARD_WIDTH, inset, gap, nil, ultimate, nil),
			{ compact = false, rightShown = true }
		)
		expect.deepEqual(
			InventoryFormat.cardBadges(CARD_WIDTH, inset, gap, notOwned, nil, pip),
			{ compact = false, rightShown = false }
		)
		-- Every card width and text size: whatever shows fits one row (nothing ever drops onto the portrait).
		for _, textScale in TEXT_SCALES do
			local chip = Config.UI.TextSize.Chip * textScale
			local right = { w = #Strings.rarity.ultimateBadge * chip * EM + 22, h = chip * 1.25 }
			for _, leftText in { Strings.common.notOwned, Strings.common.equipped, Strings.inventory.new } do
				local left = { w = #leftText * chip * EM + 12 + 4 + 22, h = chip * 1.25 }
				for width = 80, 260, 4 do
					local b = InventoryFormat.cardBadges(width, inset, gap, left, right, pip)
					if b.rightShown then
						local leftWidth = if b.compact then pip.w else left.w
						expect.truthy(inset + leftWidth + gap + right.w + inset <= width + EPS)
					end
				end
			end
		end
	end)

	t.test("stats: five bars inside the §5.8 bands, every key with a text", function()
		local bands = Config.Combat.Bands
		for _, def in Catalog.list() do
			local bars = InventoryFormat.statBars(def)
			local names = {}
			for _, bar in bars do
				table.insert(names, bar.stat)
				expect.truthy(bar.fraction >= 0 and bar.fraction <= 1)
				expect.truthy(Strings.resolve(bar.labelKey))
				expect.truthy(Strings.resolve(bar.unitKey))
			end
			expect.deepEqual(names, { "speed", "size", "reload", "windup", "arc" })
			local speed = bars[1]
			expect.equal(speed.value, def.throw.speed)
			expect.near(speed.fraction, (def.throw.speed - bands.speed.min) / (bands.speed.max - bands.speed.min), 1e-9)
		end
	end)
end
