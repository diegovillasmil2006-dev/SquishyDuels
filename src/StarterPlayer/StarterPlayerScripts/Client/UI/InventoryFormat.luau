--!strict
-- InventoryFormat (client only, pure). DESIGN §11.6 (Squishies screen), §10.8 (compact info panel), §4.3 (rarity),
-- §5.8 (throw stat bands). What InventoryController shows, as plain data:
--   entries(defs, owned, equipped, isNew)  one entry per Catalog squishy, sorted: equipped first, then rarity
--                                          descending, then name (§11.6)
--   FILTERS / nextFilter(f, dir)           All, Common, Uncommon, Epic, Exclusive; L1 / R1 cycle them (§11.4)
--   visible(entries, filter, showNotOwned) the cards a filter shows ("Show locked" off hides unowned ones)
--   collected(entries)                     owned, total ("Collected {n}/8")
--   columns(gridWidth, cardWidth, pad)     floor(gridWidth / (cardWidth + pad)), at least 1 (§11.6)
--   keepSelection(selected, visible)       the selection, kept when still visible, else the first visible card
--   equipState(entry, ctx)                 the Equip button: equip / equipped / notOwned / locked / loading
--   statBars(def)                          the five throw stats as bars normalized to the §5.8 bands
--   emptyText(filter)                      "No {rarity} squishies yet." for a filter with no card
--   filterName(filter)                     a tab's name ("All" / the rarity name)
-- Part 8 layout (DESIGN §11.2, §11.6), all base px; the Shop, the box reveal and the layout audit still use:
--   cardSize(base, metrics)                a card's size at the player's text size: never smaller than the base, wide
--                                          enough for the rarity tag and the longest word, the rarity tag stacked
--                                          when pips + chip do not fit side by side, the name on 1 or 2 lines
--   cardTags(cardWidth, inset, gap, left?, right?)   two corner badges on one row, or the right one on a second row
--   hangingChrome(tabHeight, closeHeight, padding?)   what hangs on a panel's top edge: the panel's top padding, what
--                                          hangs above it and how far it moves down so both stay centred
--   gridFit(maxWidth, cardWidth, pad, chrome)   the columns that fit and the grid's width for exactly those columns
--   previewPx(scrollHeight, reserve, wellPad, minPx, maxPx)   a preview that shrinks so the name under it stays in
--                                          view; 0 (hidden) when not even its minimum fits above the reserve
-- UI FINAL R5 (the design's Squishies window, plan work/ui/PLAN.md R5; `H:n` = "Squishy Duels HUD.dc.html" line n;
-- every number in Config.UI.Inventory):
--   PANEL / panelLayout(screenPx, top?)    the window (Layout.windowFit, H:181) and its body (H:191: padding 18 22 22
--                                          inside the 5 px border, the 600 px grid column, gap 22, the detail the
--                                          rest; a small window narrows the grid so the detail keeps body.detailMin):
--                                          the tab row (touch-sized), the grid under it, its columns and card width
--                                          ((600 - 12 - 3 x 12) / 4 = 138 at the design's size: the 12 px scroll bar
--                                          is always kept, so the cards never change width while filtering)
--   detailLayout(columnHeight, buttonHeight, restHeight)   the detail column (H:217-248): the one button pinned at
--                                          its bottom, the list above it and the stage's face: the design's 186,
--                                          shrunk so the rest of the list (`restHeight`, measured: the name row, the
--                                          chips, the stats and the gaps) fits without scrolling, never under
--                                          minFace (the list then scrolls: phones)
--   tabCounts(entries)                     each tab's count: the catalogue total of its rarity, All every squishy
--                                          (H:927), whatever "Show locked" says
--   tabRowFits(widths, gap, room)          whether the tabs fit one row (else the row scrolls sideways, G5.3)
--   cardFrame(cardWidth, nameWidth, lineHeight, footerHeight)   a card's face height (178, grown only by the
--                                          measured extra, e.g. a 2-line name: PR2), its name lines and inner width
--   footerFits(inner, pipsWidth, pillWidth)   whether the pips fit beside the rarity pill ([PR25]: else they drop)
--   showNewTag(isNew, equipped)            NEW only on a new squishy that is not equipped (H:933)
--   riseSlots(before, after)               the grid slots that rise in after a change (G5.10: only the new ones; the
--                                          slots already shown are reused without an animation)
--   raysAlpha(rarity) / stageSquishyPx(face)   the stage rays' alpha (.26 x 1 from Epic on, x .45 below: H:1014) and
--                                          the floating squishy's size for a stage face (190 on the design's 186)
--   throwText(id)                          a squishy's throw style (inventory.throwStyle.<id>, lib:20-33)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Rarity = require(Shared.Rarity)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local Layout = require(script.Parent.Layout)

-- Types

-- "All" or a rarity name (Types.Rarity). A plain string: the type checker widens the literals of an imported union
-- when they are iterated, so the values are checked against FILTERS instead.
export type Filter = string

export type Entry = {
	id: string,
	def: Types.SquishyDef,
	name: string,
	rarity: Types.Rarity,
	owned: boolean,
	equipped: boolean,
	isNew: boolean,
}

export type EquipState = "equip" | "equipped" | "notOwned" | "locked" | "loading"

export type EquipContext = {
	locked: boolean, -- lobby lock (Matched through Returning)
	pending: string?, -- the id an Equip request is running for
	confirmed: string?, -- the id the server just accepted (until the StateDelta arrives)
}

export type StatBar = {
	stat: string, -- speed / size / reload / windup / arc
	labelKey: string, -- Strings key of the label
	value: number,
	unitKey: string, -- Strings key of the unit
	fraction: number, -- 0..1 inside the §5.8 band
}

-- The Squishies window in base px (panelLayout). UI FINAL R5: the content box is the design's body inside the border
-- (H:191); the left column holds the tab row and, bodyTop under its top, the grid; the detail column is the content's
-- full height.
export type PanelLayout = {
	scale: number,
	class: string, -- "compact" | "regular"
	panelWidth: number,
	panelHeight: number,
	topPadding: number, -- the window's top padding (its border, its band and the body's top padding)
	contentWidth: number,
	contentHeight: number,
	closeHeight: number, -- the close X's touch size
	rowHeight: number, -- the tab row: the tabs and "Show locked" (touch-sized)
	bodyTop: number, -- the grid's top in the left column (under the tab row and the column gap)
	bodyHeight: number, -- the grid's height
	gridWidth: number, -- the left column (600 at the design's size)
	columns: number, -- the grid's columns (H:202: 4; fewer only when a card would be under grid.minCard)
	cardWidth: number, -- a card's width (fluid like the design's 1fr; the 12 px scroll bar kept)
	detailWidth: number,
	detailHeight: number,
	-- UI FINAL R3: the window's chrome scale, its centre's offset below the middle and what hangs above it
	-- (Layout.windowFit of the Squishies window).
	chromeScale: number,
	shift: number,
	above: number,
}

-- What hangs on the panel's top edge (hangingChrome), base px.
export type Chrome = {
	top: number, -- the panel's top padding: room for the lower halves of the tab and Close, and the gap under them
	above: number, -- how far the tab or Close reach above the panel's top edge
	shift: number, -- how far the centred panel moves down, so the panel and what hangs above it are centred together
}

-- The grid's columns and width (gridFit), base px.
export type GridFit = { columns: number, width: number }

-- UI FINAL R5: the detail column (detailLayout): the list (the stage first) above the one pinned button.
export type DetailLayout = {
	listHeight: number,
	stageFace: number, -- the stage's face (its lip hangs under it)
	buttonsTop: number,
	scrolls: boolean, -- the list is taller than its window (the stage is at its minimum)
}

-- UI FINAL R5: a card's face (cardFrame): its height, its name's lines and the content's width inside the border and
-- padding.
export type CardFrame = { face: number, nameLines: number, inner: number }

-- A card's fixed parts (cardSize), base px at the default text size.
export type CardBase = {
	width: number,
	height: number,
	iconPx: number,
	padX: number, -- left and right inside the card
	padY: number, -- top and bottom
	gap: number, -- between the icon, the name, the rarity tag and an extra row
	extraWidth: number?, -- an extra row under the rarity tag (the shop's status line): its widest content
	extraHeight: number?,
	bands: number?, -- the foam card's bevel and drop along its bottom (foam restyle; default 0)
}

-- What the card's texts measure at the player's text size (cardSize).
export type CardMetrics = {
	nameWidth: number, -- the widest squishy name on one line
	wordWidth: number, -- the widest single word of any name (a word never breaks)
	lineHeight: number, -- one line of the name
	tagInlineWidth: number, -- the widest rarity tag with the pips beside the chip ...
	tagInlineHeight: number,
	tagStackedWidth: number, -- ... and with the pips above it
	tagStackedHeight: number,
}

export type CardSize = { width: number, height: number, nameLines: number, stacked: boolean }

-- A corner badge's size (cardTags).
export type TagBox = { w: number, h: number }

export type CardTags = { twoRows: boolean, leftY: number, rightY: number }

-- Constants

local FILTERS: { Filter } = { "All", "Common", "Uncommon", "Epic", "Exclusive" }
local BANDS = Config.Combat.Bands
-- §10.8 order: Speed, Size, Reload, Windup, Arc; each from a SquishyDef.throw field and its band.
local STATS: { { stat: string, field: string, unitKey: string } } = {
	{ stat = "speed", field = "speed", unitKey = "inspect.unit.studsPerSecond" },
	{ stat = "size", field = "radius", unitKey = "inspect.unit.studs" },
	{ stat = "reload", field = "cooldown", unitKey = "inspect.unit.seconds" },
	{ stat = "windup", field = "windup", unitKey = "inspect.unit.seconds" },
	{ stat = "arc", field = "gravity", unitKey = "inspect.unit.studsPerSecondSquared" },
}

local TOUCH = Config.UI.Touch
local INVENTORY = Config.UI.Inventory
-- The panel (base px). Readings: the same margin, height share and inner padding as the Shop and Boxes panels; `gap`
-- is Theme.Padding.small between the filter row and the body, `columnGap` Theme.Padding.medium between the grid and
-- the detail column (InventoryFormat_Test keeps them equal to Theme's tokens). Fix batch: `tabGap` is Theme.headerTab's
-- gap under the tab (also kept under the hanging Close); `cellPad` the gap between grid cells; `gridChrome` the grid's
-- side room (its UIPadding: 4 on the left, the 6 px scrollbar and 4 on the right). Fix round 2: `buttonGap`
-- (Theme.Padding.medium) between the detail buttons and their wrapped rows (at `gap` the bevelled buttons read as one).
local PANEL = {
	margin = 24,
	heightShare = 0.88,
	padding = 12,
	gap = 6,
	columnGap = 12,
	gridShare = (INVENTORY.gridWidthMin + INVENTORY.gridWidthMax) / 2,
	tabGap = 6,
	cellPad = 8,
	gridChrome = 14,
	buttonGap = 12,
}
-- Review fix (gridFit): the grid keeps this much room (base px) beyond its cells. An exact fit can come out a hair short
-- in the engine's float maths under a fractional UI scale (0.85 on phones), and UIGridLayout then wraps the last column
-- onto a new row, leaving the empty strip the fit removed.
local GRID_FIT_SLACK = 1
-- UI FINAL R5: the window's border (H:182) and scroll bar (H:22), the design's body and card numbers.
local WINDOW_BORDER = Config.UI.Sticker.border.heavy
local SCROLLBAR_PX = Config.UI.Sticker.window.scrollbarPx

-- Module table

local InventoryFormat = {}

InventoryFormat.FILTERS = FILTERS
InventoryFormat.PANEL = PANEL
InventoryFormat.GRID_FIT_SLACK = GRID_FIT_SLACK

-- Private

local function nameOf(def: Types.SquishyDef): string
	return Strings.resolve(def.nameKey) or def.id
end

local function rarityName(rarity: string): string
	local info = Rarity.get(rarity)
	return if info then Strings.resolve(info.nameKey) or rarity else rarity
end

-- A finite number above 0, else 0.
local function positive(n: number?): number
	if n == nil or n ~= n or n == math.huge or n <= 0 then
		return 0
	end
	return n
end

-- Public

function InventoryFormat.sort(list: { Entry }): { Entry }
	local sorted = table.clone(list)
	table.sort(sorted, function(a: Entry, b: Entry): boolean
		if a.equipped ~= b.equipped then
			return a.equipped
		end
		local byRarity = Rarity.compare(a.rarity, b.rarity)
		if byRarity ~= 0 then
			return byRarity > 0
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.id < b.id
	end)
	return sorted
end

function InventoryFormat.entries(
	defs: { Types.SquishyDef },
	owned: { [string]: any },
	equipped: string,
	isNew: (id: string) -> boolean
): { Entry }
	local list: { Entry } = {}
	for _, def in defs do
		local has = owned[def.id] ~= nil
		table.insert(list, {
			id = def.id,
			def = def,
			name = nameOf(def),
			rarity = def.rarity,
			owned = has,
			equipped = has and def.id == equipped,
			isNew = has and isNew(def.id),
		})
	end
	return InventoryFormat.sort(list)
end

function InventoryFormat.nextFilter(current: Filter, direction: number): Filter
	local index = table.find(FILTERS, current) or 1
	local count = #FILTERS
	local step = if direction < 0 then -1 else 1
	return FILTERS[((index - 1 + step) % count) + 1]
end

function InventoryFormat.matches(entry: Entry, filter: Filter, showNotOwned: boolean): boolean
	if not showNotOwned and not entry.owned then
		return false
	end
	return filter == "All" or entry.rarity == filter
end

function InventoryFormat.visible(list: { Entry }, filter: Filter, showNotOwned: boolean): { Entry }
	local result: { Entry } = {}
	for _, entry in list do
		if InventoryFormat.matches(entry, filter, showNotOwned) then
			table.insert(result, entry)
		end
	end
	return result
end

-- UI FINAL R5 (H:927): each tab's count is the catalogue total of its rarity (All: every squishy), not what "Show
-- locked" shows.
function InventoryFormat.tabCounts(list: { Entry }): { [string]: number }
	local result: { [string]: number } = {}
	for _, filter in FILTERS do
		result[filter] = #InventoryFormat.visible(list, filter, true)
	end
	return result
end

-- UI FINAL R5 (G5.3): whether tabs of `widths` with `gap` between them fit `room` (else the row scrolls sideways).
function InventoryFormat.tabRowFits(widths: { number }, gap: number, room: number): boolean
	local total = 0
	for index, width in widths do
		total += positive(width) + (if index > 1 then positive(gap) else 0)
	end
	return total <= positive(room)
end

-- UI FINAL R5 (H:933): NEW shows on a new squishy only while it is not the equipped one.
function InventoryFormat.showNewTag(isNew: boolean, equipped: boolean): boolean
	return isNew and not equipped
end

-- UI FINAL R5 (G5.10, support.js:611-633): after a filter change the grid's first `before` slots are reused with no
-- animation; only the slots past them rise in (their index). On open `before` is 0: every slot rises.
function InventoryFormat.riseSlots(before: number, after: number): { number }
	local slots: { number } = {}
	for index = math.floor(positive(before)) + 1, math.floor(positive(after)) do
		table.insert(slots, index)
	end
	return slots
end

function InventoryFormat.collected(list: { Entry }): (number, number)
	local n = 0
	for _, entry in list do
		if entry.owned then
			n += 1
		end
	end
	return n, #list
end

function InventoryFormat.columns(gridWidth: number, cardWidth: number, pad: number): number
	local cell = cardWidth + pad
	if not (gridWidth > 0) or not (cell > 0) then
		return 1
	end
	return math.max(1, math.floor(gridWidth / cell))
end

function InventoryFormat.keepSelection(selected: string?, visibleList: { Entry }): string?
	if selected then
		for _, entry in visibleList do
			if entry.id == selected then
				return selected
			end
		end
	end
	local first = visibleList[1]
	return if first then first.id else nil
end

function InventoryFormat.equipState(entry: Entry, ctx: EquipContext): EquipState
	if not entry.owned then
		return "notOwned"
	end
	if entry.equipped or (ctx.confirmed == entry.id) then
		return "equipped"
	end
	if ctx.pending == entry.id then
		return "loading"
	end
	if ctx.locked then
		return "locked"
	end
	return "equip"
end

function InventoryFormat.statBars(def: Types.SquishyDef): { StatBar }
	local bars: { StatBar } = {}
	for _, spec in STATS do
		local value = (def.throw :: any)[spec.field]
		local band = BANDS[spec.field]
		local fraction = 0
		if type(value) == "number" and band and band.max > band.min then
			fraction = math.clamp((value - band.min) / (band.max - band.min), 0, 1)
		end
		table.insert(bars, {
			stat = spec.stat,
			labelKey = "inspect.stat." .. spec.stat,
			value = if type(value) == "number" then value else 0,
			unitKey = spec.unitKey,
			fraction = fraction,
		})
	end
	return bars
end

function InventoryFormat.emptyText(filter: Filter): string
	local rarity = if filter == "All" then "" else rarityName(filter)
	local text = string.gsub(Strings.format(Strings.inventory.empty, { rarity = rarity }), "  +", " ")
	return text
end

-- The text of a tab's name (UI FINAL R5: title case, H:929).
function InventoryFormat.filterName(filter: Filter): string
	if filter == "All" then
		return Strings.inventory.filterAll
	end
	return rarityName(filter)
end

-- UI FINAL R5 (lib:20-33): a squishy's throw style for its chip; "" for an id with none.
function InventoryFormat.throwText(id: string): string
	return Strings.resolve("inventory.throwStyle." .. id) or ""
end

-- UI FINAL R5 (H:1014: selRays = 1 from Epic on, .45 below): the stage rays' alpha, the design's .26 white times it.
function InventoryFormat.raysAlpha(rarity: string): number
	local stage = INVENTORY.stage
	local index = Rarity.index(rarity) or 1
	return stage.raysAlpha * (if index >= stage.raysFromIndex then stage.raysHigh else stage.raysLow)
end

-- UI FINAL R5 (H:224): the floating squishy for a stage `face` px tall: the design's 190 on its 186, in proportion.
function InventoryFormat.stageSquishyPx(face: number): number
	local stage = INVENTORY.stage
	return math.max(0, math.round(positive(face) * stage.squishyPx / stage.face))
end

-- UI FINAL R5 (H:203-209): a card `cardWidth` wide: the content's width inside the border and padding, the name's
-- lines (2 when the widest name, `nameWidth`, does not fit), and the face's height: the design's 178, grown only when
-- the plate, the name's lines (`lineHeight` each), the footer (`footerHeight`: the rarity pill) and the gaps need more
-- (PR2: the 16 px floor makes some boxes taller).
function InventoryFormat.cardFrame(
	cardWidth: number,
	nameWidth: number,
	lineHeight: number,
	footerHeight: number
): CardFrame
	local card = INVENTORY.card
	local inner = math.max(0, positive(cardWidth) - 2 * (card.border + card.padSide))
	local lines = if positive(nameWidth) > inner then 2 else 1
	local content = 2 * card.border
		+ card.padTop
		+ card.padBottom
		+ INVENTORY.plate.px
		+ card.gap
		+ lines * positive(lineHeight)
		+ card.gap
		+ positive(footerHeight)
	return { face = math.max(card.face, math.ceil(content)), nameLines = lines, inner = inner }
end

-- UI FINAL R5 ([PR25], H:209): the pips (`pipsWidth`, 0 for none) fit beside the rarity pill in a footer `inner` wide.
function InventoryFormat.footerFits(inner: number, pipsWidth: number, pillWidth: number): boolean
	local pips = positive(pipsWidth)
	return pips + (if pips > 0 then INVENTORY.footer.gap else 0) + positive(pillWidth) <= positive(inner)
end

-- Part 8 layout -------------------------------------------------------------------------------------------------------

-- The panel's top padding: `topPadding` (a header tab raises it) when it is a finite number above PANEL.padding, else
-- PANEL.padding.
function InventoryFormat.topPadding(topPadding: number?): number
	local top = topPadding
	if top == nil or top ~= top or top == math.huge or top <= PANEL.padding then
		return PANEL.padding
	end
	return top
end

-- What hangs on a panel's top edge (fix batch): the header tab (`tabHeight`, centred) and Close (`closeHeight`, on the
-- top-right corner, level with the tab; 0 = none). The top padding keeps PANEL.tabGap under the lower half of each
-- (never below `padding`, default PANEL.padding); `above` is what reaches above the edge; the centred panel moves down
-- by half of it (`shift`), so the panel and what hangs above it are centred together.
function InventoryFormat.hangingChrome(tabHeight: number, closeHeight: number, padding: number?): Chrome
	local tab = positive(tabHeight)
	local close = positive(closeHeight)
	local function room(height: number): number
		return if height > 0 then math.ceil(height / 2) + PANEL.tabGap else 0
	end
	local above = math.max(tab, close) / 2
	return {
		top = math.max(positive(padding or PANEL.padding), room(tab), room(close)),
		above = above,
		shift = math.floor(above / 2),
	}
end

-- The grid for cards `cardWidth` wide with `pad` between them, inside at most `maxWidth` (its side room `chrome`
-- included): the columns that fit (at least 1) and the width those columns take with GRID_FIT_SLACK (never more than
-- `maxWidth`), so no empty strip is left beside the cards.
function InventoryFormat.gridFit(maxWidth: number, cardWidth: number, pad: number, chrome: number): GridFit
	local limit = positive(maxWidth)
	local card = positive(cardWidth)
	local gap = positive(pad)
	local side = positive(chrome) + GRID_FIT_SLACK
	if card <= 0 then
		return { columns = 1, width = limit }
	end
	local columns = math.max(1, math.floor((limit - side + gap) / (card + gap) + 1e-9))
	local width = side + columns * card + (columns - 1) * gap
	return { columns = columns, width = math.min(width, limit) }
end

-- The Squishies window for a ScreenGui of `screenPx` actual px (UI FINAL R3: H:181's 1060 x 650, shrunk to fit,
-- Layout.windowFit; its lip under the face). UI FINAL R5 (H:191-202): the content box is the body inside the window's
-- border and the body's padding (`topPadding` = the window's real top padding: the border, the band and the body's
-- top padding, Theme.fitWindow; missing or too small: PANEL.padding); the left column is the design's 600 px (narrowed
-- on a small window so the detail column keeps body.detailMin, never under one card) with the tab row (touch-sized)
-- and, a column gap lower, the grid: its columns (grid.columns, fewer only when a card would be under grid.minCard)
-- and its card width ((the column - the 12 px scroll bar - the gaps) / columns); the detail column takes the rest of
-- the width after the body gap, and the content's whole height.
function InventoryFormat.panelLayout(screenPx: Vector2, topPadding: number?): PanelLayout
	local p = Layout.modalPanel(screenPx, PANEL.margin, PANEL.heightShare, PANEL.padding, "squishies")
	local body, grid = INVENTORY.body, INVENTORY.grid
	local top = InventoryFormat.topPadding(topPadding)
	local contentWidth = math.max(0, p.panelWidth - 2 * (WINDOW_BORDER + body.padSide))
	local contentHeight = math.max(0, p.panelHeight - top - (WINDOW_BORDER + body.padBottom))
	local rowHeight = Layout.touchBase(TOUCH.minTarget, p.scale)
	local bodyTop = rowHeight + body.columnGap
	local smallest = grid.minCard + SCROLLBAR_PX
	local gridWidth = math.max(smallest, math.min(body.gridWidth, contentWidth - body.gap - body.detailMin))
	local inner = gridWidth - SCROLLBAR_PX
	local columns = math.clamp(math.floor((inner + grid.gap) / (grid.minCard + grid.gap)), 1, grid.columns)
	return {
		scale = p.scale,
		class = p.class,
		panelWidth = p.panelWidth,
		panelHeight = p.panelHeight,
		topPadding = top,
		contentWidth = contentWidth,
		contentHeight = contentHeight,
		closeHeight = Layout.touchBase(TOUCH.closeButton, p.scale),
		rowHeight = rowHeight,
		bodyTop = bodyTop,
		bodyHeight = math.max(0, contentHeight - bodyTop),
		gridWidth = gridWidth,
		columns = columns,
		cardWidth = math.floor((inner - (columns - 1) * grid.gap) / columns),
		detailWidth = math.max(0, contentWidth - gridWidth - body.gap),
		detailHeight = contentHeight,
		chromeScale = p.chromeScale or 1,
		shift = p.shift or 0,
		above = p.above or 0,
	}
end

-- The detail preview's size (base px) in a list `scrollHeight` tall: what is left after the well's padding (`wellPad`
-- above and below) and `reserve` (what must show under the well: the name and, since fix round 2, the rarity tag), at
-- most `maxPx`. Fix round 2: when not even `minPx` is left, 0: the well hides, so the reserve is never cut (on a phone
-- the tag was cut in half above the buttons).
function InventoryFormat.previewPx(
	scrollHeight: number,
	reserve: number,
	wellPad: number,
	minPx: number,
	maxPx: number
): number
	local room = math.floor(positive(scrollHeight) - 2 * positive(wellPad) - positive(reserve))
	local smallest = math.min(minPx, maxPx)
	if room < smallest then
		return 0
	end
	return math.min(room, maxPx)
end

-- UI FINAL R5 (H:217-248): the detail column `columnHeight` tall: its one button (`buttonHeight`: face + lip) pinned at
-- the bottom, the list in the rest above it (a detail gap between), and the stage's face: the design's 186, shrunk so
-- the stage, its lip and the rest of the list (`restHeight`) fit the list without scrolling, never under minFace (the
-- list then scrolls).
function InventoryFormat.detailLayout(columnHeight: number, buttonHeight: number, restHeight: number): DetailLayout
	local stage = INVENTORY.stage
	local button = positive(buttonHeight)
	local listHeight = math.max(0, positive(columnHeight) - button - INVENTORY.detail.gap)
	local rest = positive(restHeight)
	local face = math.clamp(math.floor(listHeight - stage.lip - rest), stage.minFace, stage.face)
	return {
		listHeight = listHeight,
		stageFace = face,
		buttonsTop = math.max(0, positive(columnHeight) - button),
		scrolls = face + stage.lip + rest > listHeight,
	}
end

-- A card's size at the player's text size: at least `base` (so the default look is unchanged), wide enough for the
-- longest single word of a name and the rarity tag (stacked: pips above the chip, when side by side does not fit the
-- inner width), the name on a second line when the widest name does not fit, and tall enough for every row and the
-- foam bands under them (`base.bands`).
function InventoryFormat.cardSize(base: CardBase, m: CardMetrics): CardSize
	local extraWidth = base.extraWidth or 0
	local extraHeight = base.extraHeight or 0
	local bands = math.max(0, base.bands or 0)
	local width = math.max(
		base.width,
		math.ceil(m.wordWidth + 2 * base.padX),
		math.ceil(m.tagStackedWidth + 2 * base.padX),
		math.ceil(extraWidth + 2 * base.padX)
	)
	local inner = width - 2 * base.padX
	local stacked = m.tagInlineWidth > inner
	local nameLines = if m.nameWidth > inner then 2 else 1
	local tagHeight = if stacked then m.tagStackedHeight else m.tagInlineHeight
	local content = 2 * base.padY
		+ base.iconPx
		+ base.gap
		+ nameLines * m.lineHeight
		+ base.gap
		+ tagHeight
		+ (if extraHeight > 0 then base.gap + extraHeight else 0)
		+ bands
	return {
		width = width,
		height = math.max(base.height, math.ceil(content)),
		nameLines = nameLines,
		stacked = stacked,
	}
end

-- The corner badges of a card `cardWidth` wide: `left` at (inset, inset); `right` right-aligned at `inset` from the
-- right edge, on the same row when both fit with `gap` between them, else on a second row under the left one. A
-- missing badge keeps the other at the top. The Squishies cards no longer have corner badges (UI FINAL R5); this stays
-- for the Studio layout audit's test (LayoutAudit_Test).
function InventoryFormat.cardTags(
	cardWidth: number,
	inset: number,
	gap: number,
	left: TagBox?,
	right: TagBox?
): CardTags
	if left == nil or right == nil then
		return { twoRows = false, leftY = inset, rightY = inset }
	end
	local fits = inset + left.w + gap + right.w + inset <= cardWidth
	if fits then
		return { twoRows = false, leftY = inset, rightY = inset }
	end
	return { twoRows = true, leftY = inset, rightY = inset + left.h + gap }
end

return InventoryFormat
