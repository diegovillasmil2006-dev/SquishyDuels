--!strict
-- LayoutAudit (client only, Studio only). DESIGN §13.1 (Studio debug hooks), §11.2 (touch targets, text sizes, the base
-- canvas), §11.4 (gamepad focus), §17.12 L5 (the HUD's left column); Part 8's layout audit.
-- DebugHooks answers SD_DebugClient:Invoke("layoutAudit", opts?) with LayoutAudit.run(opts, deps). It reads the local
-- player's PlayerGui and lists what does not fit. It never sends a remote and never changes saved state (it only opens
-- and closes screens whose opening sends nothing, and puts the open screens back).
--   opts = nil | { screens = nil | "all" | { screenName... }, maxItems = number? (default 40) }
--   * screens nil: what is visible now, one view "current" (works during a duel: the duel HUD, the result card).
--   * "all" (lobby only: from Matched through Returning the reply is ok = false with an error): closes every modal,
--     audits the bare lobby as "current", then for each registered modal screen that opens without side effects opens
--     it, waits for its open motion, audits its root and closes it; at the end the modals that were open are opened
--     again (bottom first). Readings: skipped and listed in `skipped` ({ name, reason }) are the non-modal screens
--     ("queue": opening it sends QueueJoin; "onboarding"), "boxReveal" (it needs a box result), and "inspect" whenever
--     opening it would send something (its first open marks the onboarding "inspect" step through OnboardingStep) or
--     nothing is equipped; else "inspect" opens on the equipped squishy. A box reveal on screen or waiting in
--     BoxController's queue refuses "all" and the lists (closing a reveal sends AckReveal); one that starts during the
--     audit stops it there and stays open (ok = false, ran = false, error).
--   * { names }: the same for those names only, in that order ("current" = the bare lobby).
-- Reply (JSON-able): { ok, ran = true, mode = "current" | "all" | "list", viewport = { w, h }, scale, class, textScale,
--   preferredInput, hud = { leftBottomShare, leftMaxShare, planFits, narrow, thumbstickZone }, views = { View },
--   skipped = { { name, reason } }, counts = { checked, offscreen, textOverflow, smallTargets, overlaps, smallText,
--   belowFold, textTruncated, brokenWords, hudOverlaps, thumbZone, thumbZoneExpected }, truncated }.
--   View = { name, primary = path?, primaryOk = boolean?, selected = path?, offscreen, textOverflow, smallTargets,
--   overlaps, smallText, belowFold, textTruncated, brokenWords, hudOverlaps, thumbZone, thumbZoneExpected };
--   an item is { path (from the PlayerGui), x, y, w, h } in whole actual px (+ px for smallTargets / smallText and the
--   word's width for brokenWords, + word for brokenWords, + area for thumbZone / thumbZoneExpected); an overlap
--   (overlaps, hudOverlaps) is { a, b, area }. Each list keeps at most maxItems items (counts keep the totals;
--   truncated = true when one was cut). The foam fix batch (2026-10-09) added brokenWords, hudOverlaps, thumbZone,
--   thumbZoneExpected, hud.narrow and hud.thumbstickZone (and dockRows, gone with the dock in the lobby HUD of spec
--   2026-10-11); every older field is unchanged.
--   hud.leftBottomShare = (Hud_Left's bottom - SD_Hud's top) / SD_Hud's height (nil while it is hidden); leftMaxShare =
--   Config.UI.Grip.leftColumnMaxFraction; planFits = HudController's column plan says some layout ends above that line
--   (false: none can at this screen and text size, so the column is expected to reach lower; nil when unknown);
--   narrow = the touch / compact rules apply (the compact layout class or touch input, as HudController decides);
--   thumbstickZone = the zone thumbZone checks, { x, y, w, h } in actual px (nil unless narrow and the HUD shows).
--   ok = no offscreen, textOverflow, smallTargets, overlaps, smallText, brokenWords, hudOverlaps or thumbZone in any
--   view, and no audited modal whose primary is not ok. `ran` tells a finished audit with problems (ok = false,
--   no error) from one that could not run (ok = false, error). belowFold, textTruncated and thumbZoneExpected are
--   informational and never make ok false.
-- Rules (Readings where DESIGN is silent):
--   * Only visible objects: Visible on it and every ancestor, in an Enabled ScreenGui whose name starts with "SD_"
--     (the game's guis; not Roblox's TouchGui / Freecam, not the Studio sound picker SD_SoundPicker), without the
--     ModalWash backdrop between two stacked modals (it bleeds past SD_Modal on purpose) and without the mirrored
--     copies SD_Drop / SD_Face of Theme.stickerText (UI FINAL R1: their label, the source of truth, is audited), and
--     (UI FINAL R2) the moving shine strips SD_Shine, the soft shadows SD_SoftShadow and a Button's gamepad ring
--     SD_FocusRing (decoration that reaches past its box on purpose). An
--     object with no area is counted in `checked` but left out of the rules that need a box.
--   * offscreen: an edge outside its ScreenGui's AbsolutePosition / AbsoluteSize box by more than 1 px, unless the
--     object is inside a ScrollingFrame.
--   * belowFold: a GuiButton inside a ScrollingFrame that is not entirely inside that frame's visible window
--     (AbsoluteWindowSize): the player must scroll to reach all of it (informational).
--   * textOverflow: a TextLabel / TextButton / TextBox with Text, TextScaled false and TextFits false, whose
--     TextTruncate is None. With a TextTruncate (AtEnd / SplitWord) the cut is by design (Inspect's name in the header,
--     the compact Grip card's level line): textTruncated instead (informational, like belowFold; Part 8 review).
--   * smallTargets: an Active GuiButton whose smaller side is under Config.UI.Touch.minTargetFloor actual px.
--   * smallText: TextSize × every UIScale on the object and its ancestors < Config.UI.minTextSize (TextScaled skipped).
--   * overlaps: siblings that are GuiButtons or show text (a text object with Text, or a frame with a visible text
--     child) intersecting by more than 2 px on both axes, inside the clip of their ScrollingFrame / ClipsDescendants
--     ancestors. A frame that shows text counts as its own box when it draws a background, else as the union of its
--     text children (a transparent holder the size of a card, like a card's Overlay, is not a box the player sees).
--     Two layer roots (registered modal roots, stacked on purpose) are never compared. UI FINAL R2 (PR1): a Button's
--     box here is its drawn face (its SD_Visual child), not its hit box, which may be larger (touch minimum); the
--     smallTargets rule keeps reading the hit box.
--   * primaryOk (modals): spec.primary() is a GuiObject inside the modal's root, visible, Selectable and with an area.
--   * brokenWords: a wrapped text (TextWrapped, not TextScaled) with a word wider than its text box (AbsoluteSize.X
--     less its UIPadding) by more than TEXT_FIT_SLACK_PX, which the engine breaks mid-word ("Squishie / s" on the first
--     screen: the tile came out narrower than its word on the first layout; the two wrapped lines still fit the box, so
--     TextFits stays true and textOverflow cannot see it). The words come from ContentText (rich text dropped); a word
--     is measured with TextService:GetTextBoundsAsync at the object's FontFace and TextSize (× its UIScale product)
--     only when it may be too wide (mayBreak), once per run.
--   * The HUD rules, in a view that shows SD_Hud ("current"). Its top-level objects are the groups (Hud_Left, Hud_Nav,
--     Hud_Right, Hud_DuelButton, the coach card, Practice_Panel, QueuePill...); a group's pieces (pieces) are the boxes
--     it shows: its buttons, texts and opaque frames, without those inside the box of a shown ancestor. Why the rules
--     above missed them: overlaps compares siblings only, and a frame whose children are buttons with an empty Text
--     (the tile row, the old equipped dock) shows no text, so the dock's Inspect chip was never compared with the Daily
--     tile; the toasts live in another ScreenGui; hud.leftBottomShare reads Hud_Left only (the tile row Hud_Nav sits
--     under it).
--       - hudOverlaps: pieces of two different groups, or a toast (SD_Overlay/Toasts) and a HUD piece, overlapping by
--         more than 2 px on both axes (lobby HUD, spec 2026-10-11: the Duel CTA at the top middle, the coach card or the
--         queue pill under it and the toasts under those).
--       - thumbZone (narrow layouts only: the compact class or touch input, the rule HudController keeps; on PC the tile
--         column reaches low by design): a piece more than 2 px into the lower-left thumbstick zone:
--         Config.UI.Touch.thumbstickZoneWidth of SD_Hud's width × thumbstickZoneHeight of the whole screen's height
--         (Camera.ViewportSize.Y, never less than SD_Hud's), its bottom at SD_Hud's bottom: HudFormat.thumbstickZone's
--         zone (integration of the foam fix batch: SD_Hud sits under the top bar inset, so a share of its own height put
--         the zone's top about 25 px too low on a phone). While planFits is false (no layout ends above the line,
--         §17.7) Hud_Left's and Hud_Nav's hits are thumbZoneExpected (informational) instead (on phones the two tile
--         columns reach into the zone by the user's choice, spec 2026-10-11).
-- Pure helpers, unit-tested in Edit mode (LayoutAudit_Test): intersection, overlapArea, offscreen, belowFold, tooSmall,
-- actualTextPx, union, overlapRect, primaryOk, share, words, mayBreak, wordBreaks, innerWidth, pieces, thumbZone,
-- evaluate (the rules over plain node trees). snapshot / run read instances (and measure the words).

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

-- Types

export type Rect = { x: number, y: number, w: number, h: number }

-- One visible GuiObject as the rules see it (snapshot builds these from instances; tests build them by hand).
export type Node = {
	path: string,
	rect: Rect, -- actual px (AbsolutePosition / AbsoluteSize)
	button: boolean, -- a GuiButton
	active: boolean,
	opaque: boolean, -- draws its background (BackgroundTransparency < 1)
	clips: boolean, -- ClipsDescendants
	text: string?, -- a text object's Text (nil for other classes)
	textFits: boolean?,
	textScaled: boolean?,
	truncates: boolean?, -- TextTruncate is not None (a designed cut: textTruncated, not textOverflow)
	textPx: number?, -- TextSize × every UIScale on it and its ancestors
	scroll: Rect?, -- a ScrollingFrame's visible window
	layer: boolean?, -- a registered modal root
	-- Wrapped text (brokenWords): its widest word that may break, measured with TextService at its font and size.
	wideWord: string?,
	wideWordPx: number?, -- that word's width in actual px
	textBoxPx: number?, -- the width the text can use, in actual px (AbsoluteSize.X less its UIPadding)
	face: Rect?, -- UI FINAL R2: a Button's drawn face (its SD_Visual), the box the overlap rule compares
	children: { Node }, -- the visible GuiObject children
}

-- A ScreenGui's box and the nodes audited in it; `name` is the ScreenGui's (the HUD rules read SD_Hud and SD_Overlay).
export type Screen = { rect: Rect, roots: { Node }, name: string? }

export type Limits = {
	floorPx: number, -- smallTargets
	minTextPx: number, -- smallText
	offscreenPx: number, -- offscreen tolerance
	overlapPx: number, -- overlaps: more than this on both axes
	maxItems: number, -- per list
	narrow: boolean?, -- the touch / compact rules apply (thumbZone); nil = not
	zoneWidth: number?, -- the thumbstick zone as shares of SD_Hud's width and of the screen's height (Config.UI.Touch)
	zoneHeight: number?,
	zoneScreenHeight: number?, -- the whole screen's height in actual px (nil: SD_Hud's own height)
	zoneExpected: { [string]: boolean }?, -- HUD groups whose thumbZone hits are expected (thumbZoneExpected)
}

export type Item = {
	path: string,
	x: number,
	y: number,
	w: number,
	h: number,
	px: number?,
	word: string?, -- brokenWords
	area: number?, -- thumbZone / thumbZoneExpected: the part inside the zone (actual px²)
}
export type Overlap = { a: string, b: string, area: number }

-- A box a HUD group shows (pieces): the object's path and its box in actual px (cut to its scroll / clip window).
export type Piece = { path: string, rect: Rect }

export type Counts = {
	checked: number,
	offscreen: number,
	textOverflow: number,
	smallTargets: number,
	overlaps: number,
	smallText: number,
	belowFold: number,
	textTruncated: number,
	brokenWords: number,
	hudOverlaps: number,
	thumbZone: number,
	thumbZoneExpected: number,
}

export type Findings = {
	offscreen: { Item },
	textOverflow: { Item },
	smallTargets: { Item },
	overlaps: { Overlap },
	smallText: { Item },
	belowFold: { Item },
	textTruncated: { Item },
	brokenWords: { Item },
	hudOverlaps: { Overlap },
	thumbZone: { Item },
	thumbZoneExpected: { Item },
	counts: Counts,
	truncated: boolean,
}

-- What primaryOk needs to know about a modal's primary (pure).
export type PrimaryInfo = {
	exists: boolean,
	inside: boolean,
	visible: boolean,
	selectable: boolean,
	w: number,
	h: number,
}

-- One registered screen (UIController.debugScreens).
export type DebugScreen = { name: string, modal: boolean, open: boolean, root: GuiObject?, primary: GuiObject? }

-- What run() needs from UIController.
export type UIDeps = {
	debugScreens: () -> { DebugScreen },
	open: (name: string, params: any?) -> boolean,
	close: (name: string, reason: string?) -> boolean,
	closeAll: (reason: string) -> (),
	isOpen: (name: string) -> boolean,
	openModals: () -> { string },
	topModal: () -> string?,
	scale: () -> number,
	layoutClass: () -> string,
}

export type Deps = {
	ui: UIDeps,
	playerGui: () -> Instance?,
	isLobbyLocked: () -> boolean,
	equipped: () -> string?,
	textScale: () -> number,
	openInspect: ((squishyId: string) -> boolean)?, -- nil while InspectController is not built
	inspectedId: (() -> string?)?,
	inspectSafe: () -> (boolean, string?), -- true when opening Inspect sends nothing (else the reason)
	revealBusy: (() -> boolean)?, -- a box reveal runs or waits in BoxController's queue (closing one sends AckReveal)
	columnFits: (() -> boolean?)?, -- HudController's column plan: some layout ends above the line (hud.planFits)
	touch: (() -> boolean)?, -- the player uses touch (ControlsController); nil = UserInputService.PreferredInput
}

type Reply = { [string]: any }

-- Constants

local UI = Config.UI
local MOTION = UI.motion
local DEFAULT_MAX_ITEMS = 40
local OFFSCREEN_TOLERANCE_PX = 1
local OVERLAP_MIN_PX = 2
local FOLD_TOLERANCE_PX = 1
-- An AutomaticSize box under a fractional UIScale (0.85 on phones) can come out a pixel short of its text: TextFits is
-- false although the text shows whole on one line (Part 8 phone run, "Cancel" / "Keep playing"). Within this slack it
-- counts as fitting.
local TEXT_FIT_SLACK_PX = 2
local EPS = 1e-3
-- brokenWords: no glyph is wider than this many em, so a word shorter than its box at this width cannot break and is
-- not measured (most words of a body text); GetTextBoundsAsync measures one word in a box this wide (no wrap).
local MAX_GLYPH_EM = 1.2
local MEASURE_WIDTH_PX = 100000
-- pieces: a box within this of a shown ancestor's box lies inside it (its outline and rounding).
local INSIDE_TOLERANCE_PX = 1
local GUI_PREFIX = "SD_"
local EXCLUDED_GUIS: { [string]: boolean } = { SD_SoundPicker = true } -- a Studio tool, not the game's UI
-- Backdrops left out of every rule: UIController's ModalWash between two stacked modals reaches past SD_Modal's edges
-- on purpose (over the top bar inset, like SD_Dimmer) and holds nothing (integration of the foam fix batch). UI FINAL
-- R1: a text drop's two mirrored copies (Theme.stickerText) would read as text overlapping its own label.
local EXCLUDED_OBJECTS: { [string]: boolean } = {
	ModalWash = true,
	SD_Drop = true,
	SD_Face = true,
	SD_Shine = true,
	SD_SoftShadow = true,
	SD_FocusRing = true,
}
local HUD_GUI = "SD_Hud"
local OVERLAY_GUI = "SD_Overlay"
local TOASTS = "Toasts" -- UIController's toast column in SD_Overlay
local HUD_LEFT = "Hud_Left"
-- The left side HudFormat.leftColumnPlan lays out: with planFits false it is expected to reach into the zone (§17.7).
local LEFT_GROUPS: { [string]: boolean } = { [HUD_LEFT] = true, Hud_Nav = true }
local CURRENT = "current"
local INSPECT = "inspect"
local REVEAL = "boxReveal"
local QUEUE = "queue"
local CLOSE_REASON = "debug" -- plays no sound (not a close the player asked for)
-- Waits (s): the open motion (Config.UI.motion.modalOpen) and the close shrink (modalClose.visualMs), plus a margin for
-- the next layout pass; Inspect also builds its model.
local OPEN_WAIT = MOTION.modalOpen.ms / 1000 + 0.15
local CLOSE_WAIT = MOTION.modalClose.visualMs / 1000 + 0.1
local INSPECT_EXTRA_WAIT = 0.35
local PROBLEM_LISTS = {
	"offscreen",
	"textOverflow",
	"smallTargets",
	"overlaps",
	"smallText",
	"brokenWords",
	"hudOverlaps",
	"thumbZone",
}

-- Module table

local LayoutAudit = {}

LayoutAudit.DEFAULT_MAX_ITEMS = DEFAULT_MAX_ITEMS

-- Private

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

local function round(n: number): number
	return if finite(n) then math.floor(n + 0.5) else 0
end

local function round1(n: number): number
	return if finite(n) then math.floor(n * 10 + 0.5) / 10 else 0
end

local function round3(n: number): number
	return if finite(n) then math.floor(n * 1000 + 0.5) / 1000 else 0
end

-- The last part of a path ("SD_Hud/Hud_Nav" -> "Hud_Nav").
local function leaf(path: string): string
	return string.match(path, "([^/]+)$") or path
end

local function newCounts(): Counts
	return {
		checked = 0,
		offscreen = 0,
		textOverflow = 0,
		smallTargets = 0,
		overlaps = 0,
		smallText = 0,
		belowFold = 0,
		textTruncated = 0,
		brokenWords = 0,
		hudOverlaps = 0,
		thumbZone = 0,
		thumbZoneExpected = 0,
	}
end

-- Public: pure helpers ------------------------------------------------------------------------------------------------

-- The overlap of two rects, or nil when they do not overlap (touching edges do not).
function LayoutAudit.intersection(a: Rect, b: Rect): Rect?
	local x0 = math.max(a.x, b.x)
	local y0 = math.max(a.y, b.y)
	local x1 = math.min(a.x + a.w, b.x + b.w)
	local y1 = math.min(a.y + a.h, b.y + b.h)
	if x1 <= x0 or y1 <= y0 then
		return nil
	end
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

-- The area two rects share when they overlap by more than `minPx` on both axes, else 0.
function LayoutAudit.overlapArea(a: Rect, b: Rect, minPx: number): number
	local r = LayoutAudit.intersection(a, b)
	if r == nil or r.w <= minPx or r.h <= minPx then
		return 0
	end
	return r.w * r.h
end

-- True when an edge of `rect` is outside `container` by more than `tolerancePx`.
function LayoutAudit.offscreen(rect: Rect, container: Rect, tolerancePx: number): boolean
	return rect.x < container.x - tolerancePx
		or rect.y < container.y - tolerancePx
		or rect.x + rect.w > container.x + container.w + tolerancePx
		or rect.y + rect.h > container.y + container.h + tolerancePx
end

-- True when `rect` is not entirely inside a ScrollingFrame's visible `window` (1 px tolerance): cut by its edge or
-- past it, so the player has to scroll to reach all of it.
function LayoutAudit.belowFold(rect: Rect, window: Rect): boolean
	return LayoutAudit.offscreen(rect, window, FOLD_TOLERANCE_PX)
end

-- True when the smaller side of a w × h target is under `floorPx`.
function LayoutAudit.tooSmall(w: number, h: number, floorPx: number): boolean
	return math.min(w, h) < floorPx - EPS
end

-- Whether text fits its box: the engine's TextFits, or the drawn text (TextBounds) within TEXT_FIT_SLACK_PX of the
-- box (AbsoluteSize) on both axes, both in actual px.
function LayoutAudit.textFits(
	engineFits: boolean,
	boundsW: number,
	boundsH: number,
	boxW: number,
	boxH: number
): boolean
	if engineFits then
		return true
	end
	return boundsW <= boxW + TEXT_FIT_SLACK_PX + EPS and boundsH <= boxH + TEXT_FIT_SLACK_PX + EPS
end

-- The size text is drawn at: TextSize × the product of every UIScale on the object and its ancestors.
function LayoutAudit.actualTextPx(textSize: number, uiScaleProduct: number): number
	return textSize * uiScaleProduct
end

-- The smallest rect around `rects` (nil for none).
function LayoutAudit.union(rects: { Rect }): Rect?
	local first = rects[1]
	if first == nil then
		return nil
	end
	local x0, y0 = first.x, first.y
	local x1, y1 = first.x + first.w, first.y + first.h
	for i = 2, #rects do
		local r = rects[i]
		x0, y0 = math.min(x0, r.x), math.min(y0, r.y)
		x1, y1 = math.max(x1, r.x + r.w), math.max(y1, r.y + r.h)
	end
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

local function showsText(node: Node): boolean
	return node.text ~= nil and node.text ~= ""
end

-- What a node shows for the overlap rule: a button or a text object: its box; a frame with a visible text child: its
-- box when it draws a background, else the union of those text children, cut to its window when it scrolls or clips;
-- anything else: nil (not compared).
function LayoutAudit.overlapRect(node: Node): Rect?
	if node.button or showsText(node) then
		return node.face or node.rect
	end
	local texts: { Rect } = {}
	for _, child in node.children do
		if showsText(child) then
			table.insert(texts, child.rect)
		end
	end
	if #texts == 0 then
		return nil
	end
	if node.opaque then
		return node.rect
	end
	local shown = LayoutAudit.union(texts) :: Rect
	local window = node.scroll or (if node.clips then node.rect else nil)
	return if window then LayoutAudit.intersection(shown, window) else shown
end

-- A modal's primary is ok when it exists inside the modal's root, is visible and Selectable and has an area.
function LayoutAudit.primaryOk(info: PrimaryInfo): boolean
	return info.exists and info.inside and info.visible and info.selectable and info.w > 0 and info.h > 0
end

-- (bottom - top) / height, rounded to 3 decimals; nil without a height.
function LayoutAudit.share(bottom: number, top: number, height: number): number?
	if not (finite(bottom) and finite(top) and finite(height)) or height <= 0 then
		return nil
	end
	return math.floor((bottom - top) / height * 1000 + 0.5) / 1000
end

-- The words of a text as it draws, split on whitespace. `rich`: the rich-text tags are dropped (a <br /> is a space)
-- and the five escapes undone (ContentText needs neither).
function LayoutAudit.words(text: string, rich: boolean?): { string }
	local s = text
	if rich then
		s = string.gsub(s, "<[bB][rR]%s*/?>", " ")
		s = string.gsub(s, "<[^>]*>", "")
		s = string.gsub(s, "&lt;", "<")
		s = string.gsub(s, "&gt;", ">")
		s = string.gsub(s, "&quot;", '"')
		s = string.gsub(s, "&apos;", "'")
		s = string.gsub(s, "&amp;", "&")
	end
	local list: { string } = {}
	for word in string.gmatch(s, "%S+") do
		table.insert(list, word)
	end
	return list
end

-- True when a word of `chars` characters drawn at `textPx` (actual px) may be wider than a `boxPx` text box (no glyph
-- is wider than MAX_GLYPH_EM): only such words are measured.
function LayoutAudit.mayBreak(chars: number, textPx: number, boxPx: number): boolean
	return chars * textPx * MAX_GLYPH_EM > boxPx + TEXT_FIT_SLACK_PX
end

-- True when a word `wordPx` wide does not fit a `boxPx` text box (actual px, TEXT_FIT_SLACK_PX of slack): wrapped text
-- breaks it across lines. A box with no width (not laid out yet) breaks nothing.
function LayoutAudit.wordBreaks(wordPx: number, boxPx: number): boolean
	return boxPx > 0 and wordPx > boxPx + TEXT_FIT_SLACK_PX + EPS
end

-- The width text can use in a box `boxW` actual px wide: less its UIPadding, `padScale` of the box (left + right) and
-- `padOffset` base px (left + right) under the UIScale product.
function LayoutAudit.innerWidth(boxW: number, padScale: number, padOffset: number, scaleProduct: number): number
	return boxW * (1 - padScale) - padOffset * scaleProduct
end

-- True when `inner` lies inside `outer`, give or take `tolerancePx`.
local function inside(inner: Rect, outer: Rect, tolerancePx: number): boolean
	return inner.x >= outer.x - tolerancePx
		and inner.y >= outer.y - tolerancePx
		and inner.x + inner.w <= outer.x + outer.w + tolerancePx
		and inner.y + inner.h <= outer.y + outer.h + tolerancePx
end

local function clipWith(clip: Rect?, rect: Rect): Rect
	if clip == nil then
		return rect
	end
	return LayoutAudit.intersection(clip, rect) or { x = rect.x, y = rect.y, w = 0, h = 0 }
end

-- The boxes a HUD group shows (see the header): every button, text object with text and opaque frame in `root`, cut to
-- its ScrollingFrame / ClipsDescendants window, except one that lies inside the box of a shown ancestor (a button on
-- its panel, a label on its button). One that reaches out of it (a popup above its panel, a badge on a tile's corner)
-- is a box of its own. In tree order.
function LayoutAudit.pieces(root: Node): { Piece }
	local list: { Piece } = {}
	local function visit(node: Node, cover: Rect?, clip: Rect?)
		local r = node.rect
		local shown = if clip then LayoutAudit.intersection(r, clip) else r
		local nextCover = cover
		if
			(node.button or showsText(node) or node.opaque)
			and shown
			and shown.w > 0
			and shown.h > 0
			and not (cover and inside(shown, cover, INSIDE_TOLERANCE_PX))
		then
			table.insert(list, { path = node.path, rect = shown })
			nextCover = shown
		end
		local childClip = clip
		if node.scroll then
			childClip = clipWith(clip, node.scroll)
		elseif node.clips then
			childClip = clipWith(clip, r)
		end
		for _, child in node.children do
			visit(child, nextCover, childClip)
		end
	end
	visit(root, nil, nil)
	return list
end

-- The lower-left thumbstick zone at the HUD box's bottom-left corner: `widthShare` of its width × `heightShare` of the
-- whole screen's height `screenHeight` (actual px; nil, bad or shorter than the HUD: the HUD's own height), the shares
-- Config.UI.Touch.thumbstickZoneWidth / thumbstickZoneHeight. The zone HudFormat.thumbstickZone keeps the HUD out of.
function LayoutAudit.thumbZone(hud: Rect, widthShare: number, heightShare: number, screenHeight: number?): Rect
	local base = if screenHeight ~= nil and finite(screenHeight) then math.max(screenHeight, hud.h) else hud.h
	local h = base * heightShare
	return { x = hud.x, y = hud.y + hud.h - h, w = hud.w * widthShare, h = h }
end

local function rectItem(path: string, r: Rect): Item
	return { path = path, x = round(r.x), y = round(r.y), w = round(r.w), h = round(r.h) }
end

local function item(node: Node, px: number?): Item
	local entry = rectItem(node.path, node.rect)
	entry.px = px
	return entry
end

-- The rules over `screens` (plain nodes, see the header).
function LayoutAudit.evaluate(screens: { Screen }, limits: Limits): Findings
	local f: Findings = {
		offscreen = {},
		textOverflow = {},
		smallTargets = {},
		overlaps = {},
		smallText = {},
		belowFold = {},
		textTruncated = {},
		brokenWords = {},
		hudOverlaps = {},
		thumbZone = {},
		thumbZoneExpected = {},
		counts = newCounts(),
		truncated = false,
	}
	local counts = f.counts :: any
	local lists = f :: any
	local function add(key: string, entry: any)
		counts[key] += 1
		local list = lists[key]
		if #list < limits.maxItems then
			table.insert(list, entry)
		else
			f.truncated = true
		end
	end

	-- Siblings compared pairwise (inside `clip` when given).
	local function siblings(kids: { Node }, clip: Rect?)
		local shown: { { node: Node, rect: Rect } } = {}
		for _, kid in kids do
			local r = LayoutAudit.overlapRect(kid)
			if r and clip then
				r = LayoutAudit.intersection(r, clip)
			end
			if r and r.w > 0 and r.h > 0 then
				table.insert(shown, { node = kid, rect = r })
			end
		end
		for i = 1, #shown do
			for j = i + 1, #shown do
				local a, b = shown[i], shown[j]
				if not (a.node.layer and b.node.layer) then
					local area = LayoutAudit.overlapArea(a.rect, b.rect, limits.overlapPx)
					if area > 0 then
						add("overlaps", { a = a.node.path, b = b.node.path, area = round(area) })
					end
				end
			end
		end
	end

	local function walk(node: Node, container: Rect, scroll: Rect?, clip: Rect?)
		counts.checked += 1
		local r = node.rect
		if r.w > 0 and r.h > 0 then
			if scroll == nil and LayoutAudit.offscreen(r, container, limits.offscreenPx) then
				add("offscreen", item(node))
			end
			if scroll ~= nil and node.button and LayoutAudit.belowFold(r, scroll) then
				add("belowFold", item(node))
			end
			if node.button and node.active and LayoutAudit.tooSmall(r.w, r.h, limits.floorPx) then
				add("smallTargets", item(node, round1(math.min(r.w, r.h))))
			end
		end
		if showsText(node) and node.textScaled ~= true then
			if node.textFits == false then
				add(if node.truncates == true then "textTruncated" else "textOverflow", item(node))
			end
			local px = node.textPx
			if px ~= nil and px < limits.minTextPx - EPS then
				add("smallText", item(node, round1(px)))
			end
			local wordPx, boxPx = node.wideWordPx, node.textBoxPx
			if wordPx ~= nil and boxPx ~= nil and LayoutAudit.wordBreaks(wordPx, boxPx) then
				local entry = item(node, round1(wordPx))
				entry.word = node.wideWord
				add("brokenWords", entry)
			end
		end
		local childScroll, childClip = scroll, clip
		local window = node.scroll
		if window then
			childScroll = window
			childClip = clipWith(clip, window)
		elseif node.clips then
			childClip = clipWith(clip, r)
		end
		siblings(node.children, childClip)
		for _, child in node.children do
			walk(child, container, childScroll, childClip)
		end
	end

	-- Every piece of `a` against every piece of `b` (hudOverlaps).
	local function across(a: { Piece }, b: { Piece })
		for _, pa in a do
			for _, pb in b do
				local area = LayoutAudit.overlapArea(pa.rect, pb.rect, limits.overlapPx)
				if area > 0 then
					add("hudOverlaps", { a = pa.path, b = pb.path, area = round(area) })
				end
			end
		end
	end

	-- The HUD rules (see the header): SD_Hud's groups against each other and SD_Overlay's toasts, the thumbstick zone on
	-- narrow layouts.
	local function hudRules(hud: Screen, overlay: Screen?)
		local groups: { { name: string, pieces: { Piece } } } = {}
		for _, root in hud.roots do
			table.insert(groups, { name = leaf(root.path), pieces = LayoutAudit.pieces(root) })
		end
		for i = 1, #groups do
			for j = i + 1, #groups do
				across(groups[i].pieces, groups[j].pieces)
			end
		end
		if overlay then
			for _, root in overlay.roots do
				if leaf(root.path) == TOASTS then
					local toasts = LayoutAudit.pieces(root)
					for _, group in groups do
						across(toasts, group.pieces)
					end
				end
			end
		end
		local zoneWidth, zoneHeight = limits.zoneWidth, limits.zoneHeight
		if limits.narrow == true and zoneWidth ~= nil and zoneHeight ~= nil then
			local zone = LayoutAudit.thumbZone(hud.rect, zoneWidth, zoneHeight, limits.zoneScreenHeight)
			local expected = limits.zoneExpected or {}
			for _, group in groups do
				for _, piece in group.pieces do
					local area = LayoutAudit.overlapArea(piece.rect, zone, limits.overlapPx)
					if area > 0 then
						local entry = rectItem(piece.path, piece.rect)
						entry.area = round(area)
						add(if expected[group.name] then "thumbZoneExpected" else "thumbZone", entry)
					end
				end
			end
		end
	end

	local hud: Screen?, overlay: Screen? = nil, nil
	for _, screen in screens do
		siblings(screen.roots, nil)
		for _, root in screen.roots do
			walk(root, screen.rect, nil, nil)
		end
		if screen.name == HUD_GUI then
			hud = screen
		elseif screen.name == OVERLAY_GUI then
			overlay = screen
		end
	end
	if hud then
		hudRules(hud, overlay)
	end
	return f
end

-- Instances -----------------------------------------------------------------------------------------------------------

local function rectOf(object: GuiBase2d): Rect
	local p, s = object.AbsolutePosition, object.AbsoluteSize
	return { x = p.X, y = p.Y, w = s.X, h = s.Y }
end

-- The product of the UIScales parented to `instance`.
local function ownScale(instance: Instance): number
	local product = 1
	for _, child in instance:GetChildren() do
		if child:IsA("UIScale") then
			product *= child.Scale
		end
	end
	return product
end

-- `object`'s path from the PlayerGui ("SD_Modal/Squishies/..."); its full name when it is not under it.
local function pathOf(object: Instance, playerGui: Instance): string
	if not object:IsDescendantOf(playerGui) then
		return object:GetFullName()
	end
	local parts: { string } = {}
	local node: Instance? = object
	while node and node ~= playerGui do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, "/")
end

-- Visible on it and every GuiObject ancestor, in an Enabled LayerCollector.
local function effectivelyVisible(object: GuiObject): boolean
	local node: Instance? = object
	while node do
		if node:IsA("GuiObject") then
			if not (node :: GuiObject).Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return (node :: LayerCollector).Enabled
		end
		node = node.Parent
	end
	return false
end

-- The product of the UIScales from `from` up to and including its ScreenGui.
local function ancestorScale(from: Instance?): number
	local product = 1
	local node = from
	while node do
		product *= ownScale(node)
		if node:IsA("LayerCollector") then
			break
		end
		node = node.Parent
	end
	return product
end

-- The words measured in this run (base px wide), by font, size and word; run() empties it.
local wordWidths: { [string]: number } = {}

-- `word`'s one-line width in base px at `font` and `size`: TextService:GetTextBoundsAsync (it waits for the font to
-- load, so it reads the real glyphs), else GetTextSize with the legacy `fallback` font; nil when neither answers.
local function measureWord(word: string, font: Font, size: number, fallback: Enum.Font): number?
	local key = table.concat({ font.Family, font.Weight.Name, font.Style.Name, tostring(size), word }, "\0")
	local cached = wordWidths[key]
	if cached then
		return cached
	end
	local ok, bounds = pcall(function(): Vector2
		local params = Instance.new("GetTextBoundsParams")
		params.Text = word
		params.Font = font
		params.Size = size
		params.Width = MEASURE_WIDTH_PX
		return TextService:GetTextBoundsAsync(params)
	end)
	if not (ok and typeof(bounds) == "Vector2") and fallback ~= Enum.Font.Unknown then
		ok, bounds = pcall(function(): Vector2
			return TextService:GetTextSize(word, size, fallback, Vector2.new(MEASURE_WIDTH_PX, MEASURE_WIDTH_PX))
		end)
	end
	if not (ok and typeof(bounds) == "Vector2") then
		return nil
	end
	wordWidths[key] = bounds.X
	return bounds.X
end

-- A text object's inner width in actual px: its AbsoluteSize.X less its UIPadding (LayoutAudit.innerWidth).
local function textBoxWidth(object: GuiObject, product: number): number
	local padScale, padOffset = 0, 0
	local pad = object:FindFirstChildOfClass("UIPadding")
	if pad then
		padScale = pad.PaddingLeft.Scale + pad.PaddingRight.Scale
		padOffset = pad.PaddingLeft.Offset + pad.PaddingRight.Offset
	end
	return LayoutAudit.innerWidth(object.AbsoluteSize.X, padScale, padOffset, product)
end

-- The widest word of a wrapped text object among those that may not fit `boxPx` (LayoutAudit.mayBreak), in actual px
-- (its TextSize × the UIScale `product`); nil when no word may break or none could be measured.
local function widestWord(object: GuiObject, product: number, boxPx: number): (string?, number?)
	local text = object :: any
	local okContent, content = pcall(function(): any
		return text.ContentText
	end)
	local words = if okContent and type(content) == "string"
		then LayoutAudit.words(content)
		else LayoutAudit.words(text.Text, text.RichText == true)
	local size: number = text.TextSize
	local best: string?, bestPx: number? = nil, nil
	for _, word in words do
		if LayoutAudit.mayBreak(utf8.len(word) or #word, size * product, boxPx) then
			local base = measureWord(word, text.FontFace, size, text.Font)
			if base then
				local px = base * product
				if bestPx == nil or px > bestPx then
					best, bestPx = word, px
				end
			end
		end
	end
	return best, bestPx
end

local nodeOf: (object: GuiObject, path: string, parentScale: number, layers: { [Instance]: boolean }) -> Node

local function collectChildren(
	parent: Instance,
	path: string,
	scale: number,
	layers: { [Instance]: boolean },
	out: { Node }
)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			if child.Visible and not EXCLUDED_OBJECTS[child.Name] then
				table.insert(out, nodeOf(child, path .. "/" .. child.Name, scale, layers))
			end
		elseif child:IsA("Folder") then
			collectChildren(child, path .. "/" .. child.Name, scale, layers, out)
		end
	end
end

nodeOf = function(object: GuiObject, path: string, parentScale: number, layers: { [Instance]: boolean }): Node
	local product = parentScale * ownScale(object)
	local node: Node = {
		path = path,
		rect = rectOf(object),
		button = object:IsA("GuiButton"),
		active = object.Active,
		opaque = object.BackgroundTransparency < 1,
		clips = object.ClipsDescendants,
		layer = if layers[object] then true else nil,
		children = {},
	}
	local visual = if object:IsA("GuiButton") then object:FindFirstChild("SD_Visual") else nil
	if visual and visual:IsA("GuiObject") then
		node.face = rectOf(visual)
	end
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		local text = object :: any
		node.text = text.Text
		local bounds: Vector2 = text.TextBounds
		node.textFits =
			LayoutAudit.textFits(text.TextFits, bounds.X, bounds.Y, object.AbsoluteSize.X, object.AbsoluteSize.Y)
		node.textScaled = text.TextScaled
		local okTruncate, truncate = pcall(function(): any
			return text.TextTruncate
		end)
		node.truncates = okTruncate and truncate ~= nil and truncate ~= Enum.TextTruncate.None
		node.textPx = LayoutAudit.actualTextPx(text.TextSize, product)
		-- brokenWords: only wrapped text breaks a word across lines.
		if text.TextWrapped and not text.TextScaled and node.text ~= "" then
			local boxPx = textBoxWidth(object, product)
			node.textBoxPx = boxPx
			node.wideWord, node.wideWordPx = widestWord(object, product, boxPx)
		end
	end
	if object:IsA("ScrollingFrame") then
		local window = (object :: ScrollingFrame).AbsoluteWindowSize
		node.scroll = { x = object.AbsolutePosition.X, y = object.AbsolutePosition.Y, w = window.X, h = window.Y }
	end
	collectChildren(object, path, product, layers, node.children)
	return node
end

-- The game's ScreenGuis that show now (Enabled, "SD_" names, not the Studio tools).
local function shownGuis(playerGui: Instance): { ScreenGui }
	local list: { ScreenGui } = {}
	for _, child in playerGui:GetChildren() do
		if
			child:IsA("ScreenGui")
			and child.Enabled
			and string.sub(child.Name, 1, #GUI_PREFIX) == GUI_PREFIX
			and not EXCLUDED_GUIS[child.Name]
		then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a: ScreenGui, b: ScreenGui): boolean
		return a.Name < b.Name
	end)
	return list
end

-- Every shown ScreenGui as a Screen (the "current" view).
function LayoutAudit.snapshotAll(playerGui: Instance, layers: { [Instance]: boolean }): { Screen }
	local screens: { Screen } = {}
	for _, gui in shownGuis(playerGui) do
		local screen: Screen = { rect = rectOf(gui), roots = {}, name = gui.Name }
		collectChildren(gui, gui.Name, ownScale(gui), layers, screen.roots)
		table.insert(screens, screen)
	end
	return screens
end

-- One root (a modal's) as a Screen of its ScreenGui; empty when it does not show.
function LayoutAudit.snapshotRoot(root: GuiObject, playerGui: Instance): { Screen }
	local gui = root:FindFirstAncestorWhichIsA("LayerCollector")
	if gui == nil or not gui:IsA("ScreenGui") or not effectivelyVisible(root) then
		return {}
	end
	local node = nodeOf(root, pathOf(root, playerGui), ancestorScale(root.Parent), {})
	return { { rect = rectOf(gui), roots = { node }, name = gui.Name } }
end

local function primaryInfo(primary: GuiObject?, root: GuiObject?): PrimaryInfo
	if primary == nil or root == nil then
		return { exists = false, inside = false, visible = false, selectable = false, w = 0, h = 0 }
	end
	local size = primary.AbsoluteSize
	return {
		exists = true,
		inside = primary == root or primary:IsDescendantOf(root),
		visible = effectivelyVisible(primary),
		selectable = primary.Selectable,
		w = size.X,
		h = size.Y,
	}
end

-- The column plan's answer (`columnFits`, HudController): nil when unknown.
local function planFitsOf(columnFits: (() -> boolean?)?): boolean?
	if columnFits == nil then
		return nil
	end
	local okFits, fits = pcall(columnFits)
	return if okFits and type(fits) == "boolean" then fits else nil
end

-- Touch input: `deps.touch` (ControlsController), else UserInputService.PreferredInput.
local function touchInput(touch: (() -> boolean)?): boolean
	if touch then
		local okTouch, on = pcall(touch)
		return okTouch and on == true
	end
	local okInput, input = pcall(function(): Enum.PreferredInput
		return UserInputService.PreferredInput
	end)
	return okInput and input == Enum.PreferredInput.Touch
end

-- HUD: Hud_Left's bottom (its box or its lowest visible child) as a share of SD_Hud's height, whether the column plan
-- says it can end above the line, whether the narrow rules apply and, then, the thumbstick zone in actual px
-- (`screenHeight`: the whole screen's height, thumbZone).
local function hudReport(playerGui: Instance, planFits: boolean?, narrow: boolean, screenHeight: number?): Reply
	local report: Reply = { leftMaxShare = UI.Grip.leftColumnMaxFraction, planFits = planFits, narrow = narrow }
	local hud = playerGui:FindFirstChild(HUD_GUI)
	if hud == nil or not hud:IsA("ScreenGui") or not hud.Enabled then
		return report
	end
	if narrow then
		local zone = LayoutAudit.thumbZone(
			rectOf(hud),
			UI.Touch.thumbstickZoneWidth,
			UI.Touch.thumbstickZoneHeight,
			screenHeight
		)
		report.thumbstickZone = { x = round(zone.x), y = round(zone.y), w = round(zone.w), h = round(zone.h) }
	end
	local left = hud:FindFirstChild(HUD_LEFT) or hud:FindFirstChild(HUD_LEFT, true)
	if left == nil or not left:IsA("GuiObject") or not effectivelyVisible(left) then
		return report
	end
	local bottom = left.AbsolutePosition.Y + left.AbsoluteSize.Y
	for _, child in left:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			bottom = math.max(bottom, child.AbsolutePosition.Y + child.AbsoluteSize.Y)
		end
	end
	report.leftBottomShare = LayoutAudit.share(bottom, hud.AbsolutePosition.Y, hud.AbsoluteSize.Y)
	return report
end

-- Public: the hook ----------------------------------------------------------------------------------------------------

-- SD_DebugClient:Invoke("layoutAudit", opts?) (see the header). Yields while it opens and closes screens.
function LayoutAudit.run(opts: unknown, deps: Deps): Reply
	local wanted: any = nil
	local maxItems = DEFAULT_MAX_ITEMS
	if opts ~= nil then
		if type(opts) ~= "table" then
			return { ok = false, error = "layoutAudit opts must be a table or nil" }
		end
		local o = opts :: any
		wanted = o.screens
		if wanted ~= nil and wanted ~= "all" and type(wanted) ~= "table" then
			return { ok = false, error = "layoutAudit screens must be nil, 'all' or a list of screen names" }
		end
		local m = o.maxItems
		if m ~= nil then
			if type(m) ~= "number" or not finite(m) or m < 0 then
				return { ok = false, error = "layoutAudit maxItems must be a number >= 0" }
			end
			maxItems = math.floor(m)
		end
	end
	local playerGui = deps.playerGui()
	if playerGui == nil then
		return { ok = false, error = "no PlayerGui" }
	end
	local pg = playerGui :: Instance
	local ui = deps.ui
	-- The narrow rules as HudController keeps them (the compact class or touch input); with no layout that ends above
	-- the line (planFits false) the left side's zone hits are expected.
	local planFits = planFitsOf(deps.columnFits)
	local narrow = ui.layoutClass() == "compact" or touchInput(deps.touch)
	-- The whole screen: the viewport in the reply and the thumbstick zone's height share (thumbZone).
	local okViewport, viewport = pcall(function(): Vector2
		local camera = Workspace.CurrentCamera
		return if camera then camera.ViewportSize else Vector2.zero
	end)
	if not okViewport or typeof(viewport) ~= "Vector2" then
		viewport = Vector2.zero
	end
	local screenHeight = if viewport.Y > 0 then viewport.Y else nil
	local limits: Limits = {
		floorPx = UI.Touch.minTargetFloor,
		minTextPx = UI.minTextSize,
		offscreenPx = OFFSCREEN_TOLERANCE_PX,
		overlapPx = OVERLAP_MIN_PX,
		maxItems = maxItems,
		narrow = narrow,
		zoneWidth = UI.Touch.thumbstickZoneWidth,
		zoneHeight = UI.Touch.thumbstickZoneHeight,
		zoneScreenHeight = screenHeight,
		zoneExpected = if planFits == false then LEFT_GROUPS else nil,
	}
	table.clear(wordWidths)

	local totals = newCounts()
	local views: { Reply } = {}
	local truncated = false
	local ok = true

	local function record(name: string, screens: { Screen }, primary: GuiObject?, root: GuiObject?, modal: boolean)
		local f = LayoutAudit.evaluate(screens, limits)
		local okSelected, selected = pcall(function(): GuiObject?
			return GuiService.SelectedObject
		end)
		if not okSelected then
			selected = nil
		end
		local view: Reply = {
			name = name,
			primary = if primary then pathOf(primary, pg) else nil,
			primaryOk = if modal then LayoutAudit.primaryOk(primaryInfo(primary, root)) else nil,
			selected = if selected then pathOf(selected, pg) else nil,
			offscreen = f.offscreen,
			textOverflow = f.textOverflow,
			smallTargets = f.smallTargets,
			overlaps = f.overlaps,
			smallText = f.smallText,
			belowFold = f.belowFold,
			textTruncated = f.textTruncated,
			brokenWords = f.brokenWords,
			hudOverlaps = f.hudOverlaps,
			thumbZone = f.thumbZone,
			thumbZoneExpected = f.thumbZoneExpected,
		}
		for key, n in f.counts :: any do
			(totals :: any)[key] += n
		end
		for _, key in PROBLEM_LISTS do
			if (f.counts :: any)[key] > 0 then
				ok = false
			end
		end
		if view.primaryOk == false then
			ok = false
		end
		truncated = truncated or f.truncated
		table.insert(views, view)
	end

	-- What shows now: every game ScreenGui; the top modal's primary.
	local function auditCurrent()
		local layers: { [Instance]: boolean } = {}
		local top = ui.topModal()
		local topScreen: DebugScreen? = nil
		for _, screen in ui.debugScreens() do
			if screen.root then
				layers[screen.root] = true
			end
			if screen.name == top then
				topScreen = screen
			end
		end
		local s = topScreen
		record(
			CURRENT,
			LayoutAudit.snapshotAll(pg, layers),
			if s then s.primary else nil,
			if s then s.root else nil,
			s ~= nil
		)
	end

	local mode = if wanted == nil then CURRENT elseif wanted == "all" then "all" else "list"
	local skipped: { Reply } = {}
	local stopped: string? = nil -- why the audit stopped early (a box reveal started)
	if wanted == nil then
		auditCurrent()
	else
		if deps.isLobbyLocked() then
			return {
				ok = false,
				error = "layoutAudit 'all' and screen lists run in the lobby only (refused from Matched through Returning)",
			}
		end
		local start = ui.openModals() -- bottom first
		local revealBusy = deps.revealBusy
		if table.find(start, REVEAL) or (revealBusy ~= nil and revealBusy()) then
			return {
				ok = false,
				error = "a box reveal is open or waiting to play (closing it would send AckReveal); try again after it",
			}
		end
		local inspectStart = if table.find(start, INSPECT) and deps.inspectedId then deps.inspectedId() else nil
		local byName: { [string]: DebugScreen } = {}
		local names: { string } = {}
		for _, screen in ui.debugScreens() do
			byName[screen.name] = screen
		end
		if wanted == "all" then
			table.insert(names, CURRENT)
			for _, screen in ui.debugScreens() do
				table.insert(names, screen.name)
			end
		else
			for _, name in wanted :: { any } do
				if type(name) == "string" then
					table.insert(names, name)
				end
			end
		end

		-- Why a screen is not opened (nil = it opens without side effects).
		local function skipReason(name: string): string?
			local screen = byName[name]
			if screen == nil then
				return "not registered"
			elseif name == QUEUE then
				return "not a modal: opening it sends QueueJoin"
			elseif not screen.modal then
				return "not a modal"
			elseif name == REVEAL then
				return "needs a box result"
			elseif name == INSPECT then
				if deps.openInspect == nil then
					return "InspectController is not built"
				elseif deps.equipped() == nil then
					return "no squishy equipped"
				end
				local safe, why = deps.inspectSafe()
				if not safe then
					return why or "opening it would send something"
				end
			end
			return nil
		end

		-- Closes every modal, unless a box reveal is on screen (closing it would send AckReveal): then the audit stops
		-- there and leaves it open.
		local function closeAllSafely(): boolean
			if ui.isOpen(REVEAL) then
				stopped = "a box reveal started during the audit: it was left open and the audit stopped"
				return false
			end
			ui.closeAll(CLOSE_REASON)
			return true
		end

		closeAllSafely()
		task.wait(CLOSE_WAIT)
		for _, name in names do
			if name == CURRENT then
				auditCurrent()
				continue
			end
			local reason = skipReason(name)
			if reason then
				table.insert(skipped, { name = name, reason = reason })
				continue
			end
			local opened: boolean
			if name == INSPECT then
				local open = deps.openInspect :: (string) -> boolean
				opened = open(deps.equipped() :: string)
			else
				opened = ui.open(name)
			end
			if not opened or not ui.isOpen(name) then
				table.insert(skipped, { name = name, reason = "did not open" })
				if not closeAllSafely() then
					break
				end
				continue
			end
			task.wait(OPEN_WAIT + (if name == INSPECT then INSPECT_EXTRA_WAIT else 0))
			local now: DebugScreen? = nil
			for _, screen in ui.debugScreens() do
				if screen.name == name then
					now = screen
				end
			end
			local root = if now then now.root else nil
			if root and ui.isOpen(name) then
				record(name, LayoutAudit.snapshotRoot(root, pg), if now then now.primary else nil, root, true)
			else
				table.insert(skipped, { name = name, reason = "closed before the audit" })
			end
			if not closeAllSafely() then
				break
			end
			task.wait(CLOSE_WAIT)
		end

		-- The starting state again (bottom first; Inspect on the squishy it showed).
		if stopped == nil and closeAllSafely() then
			for _, name in start do
				if name == INSPECT then
					local open = deps.openInspect
					if open and inspectStart then
						open(inspectStart)
					end
				else
					ui.open(name)
				end
			end
		end
	end

	local okInput, input = pcall(function(): string
		return UserInputService.PreferredInput.Name
	end)
	return {
		ok = ok and stopped == nil,
		ran = stopped == nil,
		error = stopped,
		mode = mode,
		viewport = { w = round(viewport.X), h = round(viewport.Y) },
		scale = round3(ui.scale()),
		class = ui.layoutClass(),
		textScale = round3(deps.textScale()),
		preferredInput = if okInput then input else "unknown",
		hud = hudReport(pg, planFits, narrow, screenHeight),
		views = views,
		skipped = skipped,
		counts = totals,
		truncated = truncated,
	}
end

return LayoutAudit
