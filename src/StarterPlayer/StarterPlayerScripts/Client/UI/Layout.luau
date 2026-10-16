--!strict
-- Layout (client only, pure). DESIGN §11.2, §5.10: the layout maths of the UI, all numbers from Config.UI.
--   uiScale(absY, absX?)     UIScale = clamp(min(absX / referenceWidth, absY / referenceHeight), min, max) (UI FINAL
--                            R2, PR1: the design's fit, H:624; absY alone without absX)
--   layoutClass(absX, absY)  "compact" if Y < compactBelowHeight or X < compactBelowWidth, else "regular"
--   textSize(kind, pref)     base px (Config.UI.TextSize[kind]) × the GuiService.PreferredTextSize multiplier,
--                            rounded; the UIScale of the ScreenGui multiplies it once more on screen
--   touchBase(base, scale)   the base px to give a touch target under a UIScale so its actual size never drops
--                            below Config.UI.Touch.minTargetFloor (52 base = 44.2 px at scale 0.85)
--   modalWidth(availX, s)    the base width of a modal panel: the available width (in base px) capped at
--                            Config.UI.modalMaxWidth (1100 px at scale 1)
-- Part 8 (DESIGN §11.2, §11.6; the Squishies fold found in Part 6's Studio run):
--   modalPanel(screenPx, margin, heightShare, padding)   a centred modal panel's size in base px for a ScreenGui of
--                            screenPx actual px (the same numbers its UDim2 sizes give: width modalWidth(), height
--                            heightShare of the screen), with its content box inside the padding
--   wrapRow(items, rowWidth, gap)   items {w, h} placed left to right like UIListLayout.Wraps: a new row when the
--                            next item would pass rowWidth (an item wider than the row takes a row alone); each row as
--                            tall as its tallest item; rects top-left aligned in their row
--   pinnedButtons(columnWidth, columnHeight, gap, items)  a column whose buttons are pinned under its scrolling list
--                            (InspectPanel's InfoButtons pattern): the wrapped button rows at the bottom, the list
--                            above them, so the buttons stay on screen however long the list is
--   bannerTop(canvasHeight, belowBottom?, topShare, gap)  the top of UIController's centred banner (base px):
--                            topShare of the canvas, or `gap` under `belowBottom` (the bottom of what it must not
--                            cover: the duel HUD's top bar with the lives) when that is lower; never past the middle
-- Foam UI (spec 2026-10-09):
--   foamStops(height, top, bevel, drop)   the stops of the vertical UIGradient that paints a foam surface (UI/Theme):
--                            a `top` band (highlight), the face, a `bevel` shade band and a `drop` ink band at the
--                            bottom, all in base px of a surface `height` base px tall, with hard edges
-- Foam fix round 2 (2026-10-09):
--   scrollThumb(window, canvas, offset)   the always-on scroll bar of a list on touch (UI/Components/ScrollHint):
--                            shown only when the list is longer than its window; the thumb's size and top as shares
--                            of the track (on touch the engine draws its bar only while the list moves)
--   modalBackdrop(open)      which backdrop shows under `open` stacked modals: the dimmer under one, only the wash
--                            under the top of two (the dimmer and the wash together darkened the HUD and the world
--                            twice: Inspect over Squishies, the box reveal over Boxes)
--   pinnedButtons(..., buttonGap?)   the buttons keep their own gap between them and between their rows (the detail
--                            buttons of Squishies and Shop: at 6 the bevelled buttons read as one)
-- UI FINAL R1 (the look kit, plan work/ui/PLAN.md §2):
--   stickerBands(border, highlight, bevel, lip)   the foam bands of a sticker surface whose ink border is drawn inside
--                            its box (UI/Theme foam's `inner`): the top band is the border and the inset highlight, the
--                            bevel sits right above the bottom border, the drop band is the bottom border and the lip
--   lipGap(gap, lip)         the padding of a list or grid whose items draw a `lip` px ink lip inside their box: the
--                            design's gap less the lip, so the pitch stays the design's (face + gap)
-- No instances, no services: unit-tested in Edit mode.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

-- Types

export type LayoutClass = "compact" | "regular"

-- A rectangle in base px.
export type Rect = { x: number, y: number, w: number, h: number }

-- One item of a wrapped row (base px).
export type WrapItem = { w: number, h: number }

export type Wrap = {
	rows: number, -- 0 for no items
	width: number, -- the widest row
	height: number, -- every row and the gaps between them
	rects: { Rect }, -- one per item, in order, relative to the row area
}

export type Pinned = {
	rows: number,
	scrollHeight: number, -- the list above the buttons
	buttonsTop: number, -- the button area's top, from the column's top
	buttonsHeight: number,
	buttons: { Rect }, -- one per item, relative to the button area
}

-- One stop of a foam surface's gradient (top to bottom): the band it starts at `time` (0..1).
export type FoamBand = "top" | "face" | "bevel" | "drop"

-- A foam surface's band heights in base px (stickerBands; UI/Theme.Bands).
export type Bands = { top: number, bevel: number, drop: number }
export type FoamStop = { time: number, band: FoamBand }

-- A scroll bar's thumb (scrollThumb): its size and its top as shares of the track (0..1).
export type ScrollThumb = { shown: boolean, size: number, top: number }

-- What darkens the screen under the open modals (modalBackdrop).
export type Backdrop = { dimmer: boolean, wash: boolean }

export type ModalPanel = {
	scale: number,
	class: LayoutClass,
	panelWidth: number,
	panelHeight: number,
	padding: number,
	contentWidth: number,
	contentHeight: number,
}

-- Constants

local UI = Config.UI
local DEFAULT_TEXT_KIND = "Body"
local FALLBACK_SCREEN_X = 1280 -- reading: before a ScreenGui has a size (unparented, Edit mode)
local FALLBACK_SCREEN_Y = 720
local EPS = 1e-6
local BANNER_MAX_TOP_SHARE = 0.5 -- bannerTop: the banner's top never passes the middle of the canvas
-- foamStops: a hard edge is two stops this far apart (a UIGradient needs strictly rising times); a band thinner than
-- two edges is left out. Readings: before a surface is measured it counts as a touch-sized button; a top band never takes
-- more than half the surface.
local FOAM_EDGE = 0.001
local FOAM_FALLBACK_HEIGHT = 52
local FOAM_TOP_MAX_SHARE = 0.5
-- scrollThumb (readings): a list longer than its window by at most this (one unit, a rounding) does not scroll; the
-- thumb never gets smaller than this share of its track, so a long list still shows one.
local SCROLL_SLACK = 1
local SCROLL_THUMB_MIN = 0.12

-- Module table

local Layout = {}

Layout.SCROLL_THUMB_MIN = SCROLL_THUMB_MIN

-- Private

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

-- Public

-- The UIScale for an SD_Hud of this absolute height (px). A non-finite or non-positive height gives the minimum. UI
-- FINAL R2 (PR1, decided 2026-10-15): with its absolute width too, the design's fit min(w / referenceWidth, h /
-- referenceHeight) (H:624) inside the floor and cap; a missing or bad width leaves the height alone to decide.
function Layout.uiScale(absoluteHeight: number, absoluteWidth: number?): number
	local scale = UI.Scale
	if not finite(absoluteHeight) or absoluteHeight <= 0 then
		return scale.min
	end
	local fit = absoluteHeight / scale.referenceHeight
	if absoluteWidth ~= nil and finite(absoluteWidth) and absoluteWidth > 0 then
		fit = math.min(fit, absoluteWidth / scale.referenceWidth)
	end
	return math.clamp(fit, scale.min, scale.max)
end

-- "compact" on small screens (phones in landscape), else "regular".
function Layout.layoutClass(absoluteWidth: number, absoluteHeight: number): LayoutClass
	local breakpoints = UI.Breakpoints
	if absoluteHeight < breakpoints.compactBelowHeight or absoluteWidth < breakpoints.compactBelowWidth then
		return "compact"
	end
	return "regular"
end

-- The text multiplier for a GuiService.PreferredTextSize item name (Medium/Large/Larger/Largest); 1 when unknown.
function Layout.preferredTextScale(preferredName: string?): number
	if preferredName == nil then
		return 1
	end
	local multiplier = UI.PreferredTextScale[preferredName]
	return if type(multiplier) == "number" and multiplier > 0 then multiplier else 1
end

-- Base text size (before the ScreenGui UIScale) of a Config.UI.TextSize kind; an unknown kind uses Body.
function Layout.textSize(kind: string, preferredName: string?): number
	local base = UI.TextSize[kind]
	if type(base) ~= "number" then
		base = UI.TextSize[DEFAULT_TEXT_KIND]
	end
	return math.floor(base * Layout.preferredTextScale(preferredName) + 0.5)
end

-- Base px for a touch target of `basePx` under a UIScale of `scale`, raised so the actual size (base × scale) is
-- never below Config.UI.Touch.minTargetFloor.
function Layout.touchBase(basePx: number, scale: number): number
	local floorPx = UI.Touch.minTargetFloor
	if not finite(scale) or scale <= 0 then
		return math.max(basePx, floorPx)
	end
	return math.max(basePx, math.ceil(floorPx / scale))
end

-- Actual px of a base size under a UIScale (what the player sees).
function Layout.actualPx(basePx: number, scale: number): number
	return basePx * scale
end

-- Base width of a modal panel: the screen's width in base px (absoluteWidth / scale) minus `marginBasePx` on each
-- side, capped at Config.UI.modalMaxWidth.
function Layout.modalWidth(absoluteWidth: number, scale: number, marginBasePx: number): number
	local s = if finite(scale) and scale > 0 then scale else 1
	local available = math.max(0, absoluteWidth / s - 2 * marginBasePx)
	return math.min(available, UI.modalMaxWidth)
end

-- A modal panel centred in a ScreenGui of `screenPx` actual px, sized like the Squishies, Shop and Boxes panels:
-- width = modalWidth(screen, scale, margin) (the cap when nothing is left), height = heightShare of the screen; the
-- content box is inside `padding` on every side. All sizes in base px (under the ScreenGui UIScale). A zero or
-- non-finite screen size falls back to 1280×720.
function Layout.modalPanel(
	screenPx: Vector2,
	marginBasePx: number,
	heightShare: number,
	paddingBasePx: number
): ModalPanel
	local x = if finite(screenPx.X) and screenPx.X > 0 then screenPx.X else FALLBACK_SCREEN_X
	local y = if finite(screenPx.Y) and screenPx.Y > 0 then screenPx.Y else FALLBACK_SCREEN_Y
	local scale = Layout.uiScale(y, x)
	local width = Layout.modalWidth(x, scale, marginBasePx)
	if width <= 0 then
		width = UI.modalMaxWidth
	end
	local share = if finite(heightShare) and heightShare > 0 then math.min(heightShare, 1) else 1
	local height = y / scale * share
	local padding = if finite(paddingBasePx) and paddingBasePx > 0 then paddingBasePx else 0
	return {
		scale = scale,
		class = Layout.layoutClass(x, y),
		panelWidth = width,
		panelHeight = height,
		padding = padding,
		contentWidth = math.max(0, width - 2 * padding),
		contentHeight = math.max(0, height - 2 * padding),
	}
end

-- Items placed left to right in rows of `rowWidth` like UIListLayout.Wraps (greedy, in order): the next item starts a
-- new row when it would pass the row's width; an item wider than the row takes a row of its own. Each row is as tall
-- as its tallest item; the rects are top-left aligned in their row. Non-finite or negative sizes count as 0.
function Layout.wrapRow(items: { WrapItem }, rowWidth: number, gap: number): Wrap
	local limit = if finite(rowWidth) and rowWidth > 0 then rowWidth else 0
	local g = if finite(gap) and gap > 0 then gap else 0
	local rects: { Rect } = {}
	local rows, widest = 0, 0
	local x, y, rowHeight, inRow = 0, 0, 0, 0
	for index, item in items do
		local w = if finite(item.w) and item.w > 0 then item.w else 0
		local h = if finite(item.h) and item.h > 0 then item.h else 0
		if rows == 0 then
			rows = 1
		elseif inRow > 0 and x + g + w > limit + EPS then
			y += rowHeight + g
			x, rowHeight, inRow = 0, 0, 0
			rows += 1
		end
		local left = if inRow > 0 then x + g else 0
		rects[index] = { x = left, y = y, w = w, h = h }
		x = left + w
		inRow += 1
		rowHeight = math.max(rowHeight, h)
		widest = math.max(widest, x)
	end
	return {
		rows = rows,
		width = widest,
		height = if rows > 0 then y + rowHeight else 0,
		rects = rects,
	}
end

-- A column of `columnWidth` × `columnHeight` (base px) whose buttons (`items`, wrapped by wrapRow) are pinned at its
-- bottom under a scrolling list: the list gets what is left above the buttons and one `gap`. The buttons never move
-- below the column, however long the list is (with no items the list takes the whole column). `buttonGap` (fix round
-- 2; missing or bad = `gap`) is the gap between the buttons and between their rows.
function Layout.pinnedButtons(
	columnWidth: number,
	columnHeight: number,
	gap: number,
	items: { WrapItem },
	buttonGap: number?
): Pinned
	local height = if finite(columnHeight) and columnHeight > 0 then columnHeight else 0
	local g = if finite(gap) and gap > 0 then gap else 0
	local between = if buttonGap ~= nil and finite(buttonGap) and buttonGap > 0 then buttonGap else g
	local wrap = Layout.wrapRow(items, columnWidth, between)
	local buttonsHeight = wrap.height
	local scrollHeight = if wrap.rows > 0 then math.max(0, height - buttonsHeight - g) else height
	return {
		rows = wrap.rows,
		scrollHeight = scrollHeight,
		buttonsTop = math.max(0, height - buttonsHeight),
		buttonsHeight = buttonsHeight,
		buttons = wrap.rects,
	}
end

-- The top of a centred banner on a canvas `canvasHeight` base px tall: `topShare` of it, or `gap` under `belowBottom`
-- (base px from the canvas top; nil or not finite = nothing to keep clear) when that is lower. Reading (integrator,
-- Part 8; DESIGN gives the banner no place below the bar): never lower than BANNER_MAX_TOP_SHARE of the canvas, so a
-- very tall bar cannot push the banner off the screen (it then covers the bar's lower part, as it did before).
function Layout.bannerTop(canvasHeight: number, belowBottom: number?, topShare: number, gap: number): number
	local h = if finite(canvasHeight) and canvasHeight > 0 then canvasHeight else 0
	local share = if finite(topShare) and topShare > 0 then topShare else 0
	local top = h * share
	if belowBottom ~= nil and finite(belowBottom) then
		local g = if finite(gap) and gap > 0 then gap else 0
		top = math.max(top, belowBottom + g)
	end
	return math.min(top, h * math.max(share, BANNER_MAX_TOP_SHARE))
end

-- The stops (top to bottom, times 0..1) of the vertical gradient of a foam surface `height` base px tall: a `top` band,
-- the face, a `bevel` band and a `drop` band at the bottom (base px; 0, negative or not finite = no band). The first
-- stop is at 0 and the last at 1; each edge between two bands is two stops FOAM_EDGE apart, so the times always rise.
-- The bands never pass each other: the top band takes at most half the surface, the drop and the bevel what is left
-- under it. A zero or non-finite height (not measured yet) counts as FOAM_FALLBACK_HEIGHT.
function Layout.foamStops(height: number, top: number, bevel: number, drop: number): { FoamStop }
	local h = if finite(height) and height > 0 then height else FOAM_FALLBACK_HEIGHT
	local function share(px: number): number
		return if finite(px) and px > 0 then px / h else 0
	end
	local topShare = math.min(share(top), FOAM_TOP_MAX_SHARE)
	local dropShare = math.min(share(drop), 1 - topShare)
	local lowShare = math.min(share(bevel) + dropShare, 1 - topShare) -- the bevel and the drop, from the bottom
	local segments: { { band: FoamBand, from: number, to: number } } = {
		{ band = "top", from = 0, to = topShare },
		{ band = "face", from = topShare, to = 1 - lowShare },
		{ band = "bevel", from = 1 - lowShare, to = 1 - dropShare },
		{ band = "drop", from = 1 - dropShare, to = 1 },
	}
	local stops: { FoamStop } = {}
	for _, segment in segments do
		if segment.to - segment.from > 2 * FOAM_EDGE then
			local last = stops[#stops]
			if last == nil then
				table.insert(stops, { time = 0, band = segment.band })
			else
				table.insert(stops, { time = segment.from - FOAM_EDGE, band = last.band })
				table.insert(stops, { time = segment.from, band = segment.band })
			end
		end
	end
	if #stops == 0 then
		return { { time = 0, band = "face" }, { time = 1, band = "face" } }
	end
	table.insert(stops, { time = 1, band = stops[#stops].band })
	return stops
end

-- UI FINAL R1: the foam bands (base px) of a sticker surface with an inner `border`, an inset `highlight` along its
-- top, a `bevel` along its bottom and a `lip` under it (CSS: border, inset 0 Hpx 0, inset 0 -Bpx 0, box-shadow 0 Dpx
-- 0). Negative or non-finite values count as 0.
function Layout.stickerBands(border: number, highlight: number, bevel: number, lip: number): Bands
	local function px(n: number): number
		return if finite(n) and n > 0 then n else 0
	end
	local b = px(border)
	return { top = b + px(highlight), bevel = px(bevel), drop = b + px(lip) }
end

-- UI FINAL R1: the padding between the items of a list or grid that each draw a `lip` px ink lip inside their box under
-- the face: the design's `gap` less the lip (never below 0), so the pitch stays the design's face + gap (CSS box-shadow
-- takes no room; our lip does).
function Layout.lipGap(gap: number, lip: number): number
	local g = if finite(gap) and gap > 0 then gap else 0
	local l = if finite(lip) and lip > 0 then lip else 0
	return math.max(0, g - l)
end

-- The thumb of a list `canvas` tall seen through a window `window` tall and scrolled `offset` down (one unit for all
-- three, e.g. actual px): shown only when the list is longer than the window by more than SCROLL_SLACK; its size is
-- window / canvas (never under SCROLL_THUMB_MIN) and its top follows the offset over the scroll range, clamped to the
-- track. A bad window or canvas shows nothing; a bad offset counts as the top.
function Layout.scrollThumb(window: number, canvas: number, offset: number): ScrollThumb
	if not finite(window) or not finite(canvas) or window <= 0 or canvas <= window + SCROLL_SLACK then
		return { shown = false, size = 1, top = 0 }
	end
	local size = math.max(window / canvas, SCROLL_THUMB_MIN)
	local travel = if finite(offset) then math.clamp(offset / (canvas - window), 0, 1) else 0
	return { shown = true, size = size, top = travel * (1 - size) }
end

-- The backdrop under `open` stacked modals: none, the dimmer under one, and only the wash (UIController's ModalWash,
-- right under the top modal) once two are open, so the HUD and the world are darkened once whatever the stack holds.
-- A bad count shows none.
function Layout.modalBackdrop(open: number): Backdrop
	local n = if finite(open) then open else 0
	return { dimmer = n >= 1 and n < 2, wash = n >= 2 }
end

return Layout
