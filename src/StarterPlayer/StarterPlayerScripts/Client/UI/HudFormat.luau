--!strict
-- HudFormat (client only, pure). DESIGN §11.6 (lobby HUD), §11.3 (shared states), §3.13 (failure modes), §6.8 / §6.9
-- (claimable quests and daily rewards for the badges); the foam UI restyle (spec docs/superpowers/specs/
-- 2026-10-09-foam-ui-restyle-design.md, "Lobby HUD"). What HudController shows, as plain data:
--   NAV                        the HUD's screen buttons in DESIGN order: Squishies, Boxes, Shop, Quests, Daily (the left
--                              tile column), Duel (the CTA at the top middle), Settings (the top-right gear tile),
--                              each with the screen it opens, its stable button name (Hud_<Id>Button, §2.11), its
--                              place, accent and icon (UI/Components/IconGlyph)
--   visibleNav(isRegistered)   the items whose screen exists (a button never opens nothing, §7.6 / acceptance 5)
--   banner(dataStatus)         the data-status line: a pending save -> "Saving your collection…" (reason box.saving,
--                              §3.11) first; else the server's own choice (dataStatus.banner, a Strings key: reading,
--                              StateService.bannerFor); else derived: offline -> data.offlineRetrying, read-only ->
--                              data.loadFailed. Offline and read-only lines are warnings. Foam restyle (spec): Studio
--                              memory mode (data.studioMemory, or ready and not persisted) is never shown to players;
--                              isStudioMemory(dataStatus) lets HudController log it instead. ("Progress loaded!" is the
--                              server's Notify data.loaded, shown by NotifyController.)
--   keyHint(textKey, input)    an action label with its key, "Inspect (V)" / "Inspect (Y)", plain on touch
--   keyFor(textKey, input)     the Strings key of that key ("controls.key.inspectKeyboard"), nil on touch or without one
--                              (a keycap's text, UI/Components/Keycap)
--   coinGain(old, new)         the "+N" float of a Coin increase (none on the first value or a decrease)
--   questBadge(quests)         daily quests done and not claimed
--   dailyBadge(daily, today)   1 when today's daily reward is unclaimed (UTC day index, §6.9)
--   badgeText(n)               the badge number (nil for 0; capped at BADGE_MAX)
--   coinsText(coins)           Format.coins, or "Loading…" before the first value (§11.3)
--   trackedQuest(board)        the quest tracker's quest (spec "Top right"): the unclaimed quest closest to done, the
--                              Starter tasks first, then the day's quests (UI/QuestFormat.board); nil when there is none
--   ctaModel(queue, now)       the Duel CTA's texts: "DUEL" / "Join the queue", or while Searching "IN QUEUE" and
--                              "Searching · 0:23" (the queue pill's clock, UI/QueueFormat)
-- Feel pass (§18.5.2 B1-B2):
--   coinAction(displayed, previous, new, shown, replaced) / releaseHeld(displayed, target, hasSource, reducedMotion)
--                              what the coin capsule does with a new Coins value / with the gain held while the HUD was
--                              hidden (set, hold, gain, spend, flight, none)
--   iconWiggle(t)              the coin disc's rotation t seconds into a gain: 0 -> -iconWiggleDeg -> 0 over 200 ms
--   gainRise(pill, label)      foam fix 2: how far the "+N" rises from beside the capsule's middle (at most floatPx,
--                              never past the HUD's top)
--   gainText(amount) / gainSpot(beside, pill, textScale)
--                              foam fix 3: the "+N" text with the capsule's thousands separator ("+12,450"); where it
--                              starts and how far it rises: beside a stacked capsule's middle (fix 2), and on a phone
--                              (the Grip card right of the capsule) on the capsule's top edge over its number's end, in
--                              the small display kind, inside the HUD
-- Layout (Part 8 device pass, rebuilt for the foam HUD), all in base px under the SD_Hud UIScale:
--   COLUMN                     the HUD's shared sizes (the controllers read them here, so the maths and the UI agree)
--   textWidth / textLines / textHeight(text, sizePx, widthPx, font)
--                              a text estimate (Reading, DESIGN gives no font metrics; TEXT_METRICS: a character is
--                              0.6 em in Fredoka One, every kind's font since UI FINAL R1, a line 1.25 × the size;
--                              greedy word wrap). The Studio layout audit measures the real boxes.
--   leftColumnPlan(screenPx, layoutClass, textScale, parts?) / columnLayouts(...) / samePlan(a, b)
--                              the left side: the top-left column Hud_Left (the coin capsule and the Grip card) and the
--                              tile group Hud_Nav under it. It picks the Grip card's layout (regular / compact), how
--                              Hud_Left holds its two items (stacked, or side by side on one row: "beside") and the
--                              tiles' arrangement (one column as in the design, two columns, or a row that wraps) so the
--                              left side ends above its limit: on narrow layouts (the compact class or touch input) the
--                              top of the thumbstick zone (thumbstickZone: the lower 45% of the whole screen, whose top
--                              bar inset the HUD does not cover, and never below Config.UI.Grip.leftColumnMaxFraction of
--                              the HUD, §11.2 / §17.7 L5), else the bottom of the screen. Order tried: regular screens:
--                              the regular card with a tile column, the compact card with a column, then two columns,
--                              then a row (each with the regular card first), then the compact card beside the capsule
--                              with a row; phones (compact class; lobby HUD, spec 2026-10-11: phones follow the PC
--                              layout): the compact card beside the capsule, only when that keeps the Duel CTA's widest
--                              width clear at the top middle (ctaWidth), then under it, the tiles always in two columns.
--                              If none fits, the shortest is used (fits = false: on phones the two columns reach into
--                              the thumbstick zone, the user's choice; the joystick still starts in the lower-left
--                              corner below them). Sized for the longest texts each part can show (worstCaseTexts), so
--                              the choice only changes with the screen, the layout class, the input and the text size.
--                              The Grip card never hides for it (§17.7).
--   badgeReachRect(tiles)      foam fix 2: the tile row's box plus a count badge's reach above and right of it (the box
--                              the toast column keeps beside)
--   thumbstickZone(canvas, screenHeightPx?, scale)
--                              the lower-left thumbstick zone (Config.UI.Touch: 40% of the width × 45% of the whole
--                              screen's height) in the HUD's base px, its bottom at the HUD's bottom
--   gripCompactWidth(text, textScale?)
--                              the compact Grip card's width: its one line plus padding, between gripCompactMinWidth
--                              and the regular card's width (so it fits beside the coin capsule on a phone)
--   coachPlacement(input) / coachHeight(...)
--                              the onboarding coach card (spec "Onboarding"): from `top` (lobby HUD, spec 2026-10-11:
--                              right under the Duel CTA; default COLUMN.edge), centred between the left and the right
--                              groups; the preferred width when it is no taller than its band (the old one, down to
--                              the toast line), else as wide as the room (fewer lines); fits = false when no width
--                              keeps it in the band (the toasts start under it anyway: NotifyFormat chains them)
--   coachBottomPlacement(input)
--                              UI overhaul (2026-10-11): the coach card as a compact prompt at the bottom middle (the
--                              centre column stays open: the Duel CTA and the toasts at the top, the character in the
--                              middle): COLUMN.coachBottomGap above the HUD's bottom edge, centred in the free span its
--                              band leaves between the blockers (the HUD groups and, on narrow layouts, the thumbstick
--                              zone, the jump and touch buttons); its preferred width when the span allows, else the
--                              span; fits = false when the span is narrower than minWidth (then centred anyway)
--   ctaPlacement(input) / ctaWidth(compact, textScale?)
--                              lobby HUD (spec 2026-10-11): the Duel CTA at the top middle on every layout, COLUMN.edge
--                              down, centred and moved into the free span the left and right groups leave (freeSpan);
--                              fits = false when that span is narrower than it (then the screen's centre). ctaWidth is
--                              its widest width estimate (the queued texts; the left plan keeps it clear on phones)
--   focusLinks(groups)
--                              the gamepad links of the HUD (§11.4, §17.7): the left column top to bottom through the
--                              tiles (DPadUp's Grip card, Down walks the tiles), the right column (Settings, the
--                              tracker) and the links between them: the Duel CTA between the left column and Settings,
--                              Down to the queue pill's Cancel or the coach card's button (which link Up back to it), a
--                              tile -> the CTA (chainLinks, the Grip panel's Show me chain, went with its pad cards,
--                              build plan Phase 6)
--   dpadUpTarget(hudShown, entryShown, rowShown)
--                              DPadUp's target: the Grip card while it shows, else the first tile

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local GripMath = require(Shared.GripMath)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local Layout = require(script.Parent.Layout)
local OnboardingFormat = require(script.Parent.OnboardingFormat)
local QuestFormat = require(script.Parent.QuestFormat)

-- Types

-- Where a NAV item lives on the foam HUD.
export type NavPlace = "tile" | "cta" | "settings"

export type NavItem = {
	id: string,
	screen: string, -- UIController screen name
	textKey: string, -- Strings key of the label
	button: string, -- stable instance name
	badge: string?, -- which badge it carries
	params: any?, -- UIController.open params
	place: NavPlace,
	accent: string, -- Theme accent name of its face
	icon: string, -- IconGlyph name
	fx: string?, -- UI FINAL R2: its design hover kind (Button spec.fx) when not its Button kind's own
}

export type BannerKind = "info" | "warn"
export type Banner = { text: string, kind: BannerKind }
export type InputKind = "keyboard" | "gamepad" | "touch"

-- What the coin capsule does with a value (§18.5.2 B1-B2).
export type CoinActionKind = "none" | "set" | "hold" | "gain" | "spend" | "flight"
export type CoinAction = {
	kind: CoinActionKind,
	to: number?, -- the value to show (set) or to count to (gain, spend, flight)
	gain: number?, -- the "+N" of a gain or a flight
}

-- The Duel CTA's texts (ctaModel).
export type CtaModel = { queued: boolean, title: string, subtext: string }
-- The fields of StateController.QueueView the CTA reads.
export type QueueLike = { state: Types.QueueState, joinedAt: number? }

-- Layout types (base px).
export type FontKind = "body" | "title"
export type Rect = { x: number, y: number, w: number, h: number }
-- "hidden" = no Grip card in the column: it has no Grip state yet or a duel holds it back (never a layout choice).
export type GripMode = "regular" | "compact" | "hidden"
-- The tiles: one column (the design), two columns, or a row that wraps to the screen's width.
export type TilesMode = "column" | "grid" | "row"
-- Hud_Left's two items: the coin capsule over the Grip card (the design), or side by side on one row (phones).
export type LeftMode = "stack" | "beside"
-- Foam fix 3: where the coins "+N" starts, in the coin capsule's box (Hud_Coins), and how far it rises (gainSpot).
export type GainSpot = {
	kind: "HudNumber" | "Chip", -- its text kind
	anchorX: number, -- 0: its left edge is at x; 1: its right edge is
	x: number, -- base px from the capsule's right edge (+ = right)
	yScale: number, -- its centre from the capsule's middle (0.5) or top edge (0) ...
	y: number, -- ... plus this (base px, + = down)
	rise: number, -- base px it rises while it fades
}
-- One text the onboarding card can show, with the button it shows next to it.
export type OnboardingText = { text: string, gotIt: boolean }
-- The texts the plan sizes the parts for (worstCaseTexts: the longest of each).
export type ColumnTexts = {
	coins: string, -- the widest coin capsule text
	gripRank: string, -- the longest grip.rank.* name (the regular card's title)
	gripLevel: string, -- the widest level number (the regular card's level tile)
	gripCompact: string, -- grip.hudLevelCompact
	gripBar: string,
	gripChip: string,
	gripGoal: string,
	tiles: { string }, -- the tile labels
	onboarding: { OnboardingText },
	gotIt: string,
	skip: string, -- onboarding.skip "Skip tutorial" (§11.8; never shortened)
}
-- Which parts are on screen (default: the Grip card, every tile, mouse input) and the texts to size them for (default:
-- worstCaseTexts()). `screenHeight` is the whole screen's height in px (Camera.ViewportSize.Y, with the top bar inset
-- the HUD leaves out; default the HUD's own height): the thumbstick zone is a share of it.
export type ColumnParts = {
	grip: boolean?,
	touch: boolean?,
	tiles: number?,
	texts: ColumnTexts?,
	screenHeight: number?,
}
export type ColumnPlan = {
	scale: number, -- the SD_Hud UIScale (Layout.uiScale)
	canvas: Vector2, -- the screen in base px
	narrow: boolean, -- the compact class or touch input: the thumbstick zone stays clear
	limit: number, -- the left side ends above this (base px from the HUD's top)
	grip: GripMode,
	left: LeftMode, -- Hud_Left's capsule and Grip card stacked or side by side
	tiles: TilesMode,
	columns: number, -- tiles per row
	rows: number,
	tileWidth: number,
	tileHeight: number,
	pillHeight: number, -- the coin capsule
	gripHeight: number, -- 0 when the card is not in the column
	leftBottom: number, -- Hud_Left's bottom (the coin capsule and the Grip card)
	tilesTop: number, -- Hud_Nav's top
	tilesWidth: number,
	tilesHeight: number,
	bottom: number, -- the left side's lowest point
	width: number, -- Hud_Left's width (its widest item stacked, or both items beside each other)
	fits: boolean, -- bottom <= limit and Hud_Left and the tiles fit the width (false only when no layout fits)
}
export type FocusLink = { up: string?, down: string?, left: string?, right: string? }
-- The HUD's selectable objects by key, grouped as they sit on screen (focusLinks).
export type FocusGroups = {
	left: { string }, -- top to bottom: the coin capsule, the Grip card
	tiles: { string }, -- the tiles in order
	tileColumns: number?, -- tiles per row (default 1: a column)
	right: { string }, -- top to bottom: Settings, the quest tracker
	coach: string?, -- the coach card's visible button (under the Duel CTA)
	cta: string?, -- the Duel CTA (the top middle)
	queue: string?, -- the queue pill's Cancel (under the Duel CTA)
}
-- coachPlacement's input: the canvas, the HUD groups it keeps clear of, its height at a width.
export type CoachInput = {
	canvas: Vector2,
	blockers: { Rect },
	heightAt: (width: number) -> number,
	top: number?, -- its top edge (lobby HUD, spec 2026-10-11: right under the Duel CTA); default COLUMN.edge
	preferred: number?, -- default COLUMN.coachWidth
	minWidth: number?, -- default COLUMN.coachMinWidth
}
export type CoachPlace = { x: number, y: number, width: number, height: number, fits: boolean }
-- ctaPlacement's input.
export type CtaInput = {
	canvas: Vector2,
	size: Vector2, -- the CTA's size
	blockers: { Rect }, -- the HUD groups beside it (Hud_Left, the tiles, Hud_Right)
}
export type CtaPlace = { x: number, y: number, fits: boolean }
-- One way to lay out the left side (leftColumnPlan tries them in order). `clearCta`: only when Hud_Left beside keeps the
-- Duel CTA's widest width clear at the top middle (phones).
type Candidate = { grip: GripMode, tiles: TilesMode, left: LeftMode, clearCta: boolean? }

-- Constants

local BADGE_MAX = 99
local SAVE_PENDING_CODE = "box.saving"
local STUDIO_MEMORY_KEY = "data.studioMemory"
local SEARCHING = "Searching"
local COIN_MOTION = Config.UI.motion.coinCounter
local FLIGHT = Config.UI.motion.coinFlight
-- reading (DESIGN: "rotates 0 -> -12° -> 0 over 200 ms"): one half sine over WIGGLE_SECONDS.
local WIGGLE_SECONDS = 0.2
local WARN_STATUSES: { [string]: boolean } = { offline = true, readonly = true }
-- Keys of the key hints by input kind (controls.key.*), per action text key.
local KEY_HINTS: { [string]: { keyboard: string?, gamepad: string? } } = {
	["common.inspect"] = { keyboard = "controls.key.inspectKeyboard", gamepad = "controls.key.inspectGamepad" },
	["hud.nav.squishies"] = { keyboard = "controls.key.squishiesKeyboard" },
}

-- Spec "Lobby HUD": the tiles' accents (Squishies Strawberry, Boxes Lilac, Shop the new accent, Quests the quest mint,
-- Daily Sky blue), the Settings gear on Frosting, the Duel CTA in Strawberry.
local NAV: { NavItem } = {
	{
		id = "squishies",
		screen = "squishies",
		textKey = "hud.nav.squishies",
		button = "Hud_SquishiesButton",
		badge = "squishies",
		place = "tile",
		accent = "strawberry",
		icon = "squishies",
	},
	{
		id = "boxes",
		screen = "boxes",
		textKey = "hud.nav.boxes",
		button = "Hud_BoxesButton",
		place = "tile",
		accent = "lilac",
		icon = "boxes",
	},
	{
		id = "shop",
		screen = "shop",
		textKey = "hud.nav.shop",
		button = "Hud_ShopButton",
		place = "tile",
		accent = "shop",
		icon = "shop",
	},
	{
		id = "quests",
		screen = "quests",
		textKey = "hud.nav.quests",
		button = "Hud_QuestsButton",
		badge = "quests",
		place = "tile",
		accent = "quests",
		icon = "quests",
	},
	{
		id = "daily",
		screen = "daily",
		textKey = "hud.nav.daily",
		button = "Hud_DailyButton",
		badge = "daily",
		place = "tile",
		accent = "sky",
		icon = "daily",
	},
	-- The Duel CTA sends QueueJoin through QueueController's non-modal "queue" screen (§11.6).
	{
		id = "duel",
		screen = "queue",
		textKey = "hud.nav.duel",
		button = "Hud_DuelButton",
		place = "cta",
		accent = "strawberry",
		icon = "duel",
	},
	{
		id = "settings",
		screen = "settings",
		textKey = "hud.nav.settings",
		button = "Hud_SettingsButton",
		place = "settings",
		accent = "plum", -- UI overhaul (Candy UI): the neutral plum tile
		icon = "settings",
		fx = "icon", -- UI FINAL R2: the Settings sticker's data-fx="icon" (H:157): 1.12, no tilt, no wiggle
	},
}

-- UI FINAL R1: the sticker shapes (Config.UI.Sticker) the band sums below come from, and UI/Theme's room kept over a
-- panel's bands (PANEL_BAND_GAP there).
local STICKER = Config.UI.Sticker
local PANEL_BAND_GAP = 3

-- The HUD's shared sizes in base px (Readings: the design's 1080p px ÷ 1.25, spec "Shapes"; DESIGN gives the content,
-- not the sizes).
local COLUMN = table.freeze({
	edge = 12, -- every HUD group sits this far from the HUD's edges
	gap = 6, -- Theme.Padding.small: between the items inside a group
	rowGap = 8, -- between two groups
	leftGap = 10, -- between the coin capsule and the Grip card
	cardWidth = 270, -- the Grip card (the design's 336)
	cardPadding = 6, -- the compact Grip card's padding (Theme.Padding.small)
	cardPadTop = 10, -- the regular Grip card's padding
	cardPadBottom = 14,
	cardPadLeft = 10,
	cardPadRight = 12,
	cardGap = 10, -- the regular card's level tile to its lines
	levelTileWidth = 54,
	levelTileHeight = 58,
	listGap = 4, -- between the regular card's lines
	barHeight = 12, -- the regular card's ProgressBar
	chipIconPx = 18, -- the clock before the Double Grip line
	tilesGap = 22, -- Hud_Left to the tiles under the regular card (it held the removed Upgrade tab's lower half)
	tileGap = 10,
	-- Foam fix 2: a tile's count badge reaches this far past the tile's top and right edges (CountBadge's height / 2
	-- less Button's BADGE_INSET 5; UI FINAL R1: the 32 px badge of H:102, its border drawn inside); what is above or
	-- beside the tiles keeps badgeAir more.
	badgeReach = 11,
	badgeAir = 4,
	tileSize = 84, -- the HUD nav cell (the grid's CellSize wins over Button.TILE_SIZE, the design's 118 × 104 sticker)
	-- Phones (foam fix): the icon, the label line and the bands, so the tile row clears the thumbstick zone; still the
	-- touch minimum (>= 44 px at the 0.85 phone scale).
	tileSizeCompact = 58,
	tileIconPx = 42, -- UI overhaul: 36 -> 42, bolder tiles (still inside the 84 px tile with its label)
	tileIconCompactPx = 24,
	settingsIconPx = 28, -- the Settings tile's gear (top right; it keeps its size on phones)
	tilePadding = 6, -- Button's tile side padding
	tileBands = 12, -- Theme.Foam.tile: top 2 + bevel 6 + drop 4
	tileLabelGap = 2,
	measureMargin = 4, -- Button.widthFor's margin
	buttonPadding = 18, -- Button's primary / secondary side padding
	buttonBands = 10, -- Theme.Foam.button: top 2 + bevel 5 + drop 3
	coinDiscPx = 52, -- UI/Components/CoinCapsule
	capsuleHeight = 44,
	capsuleBands = 11, -- top 2 + bevel 5 + drop 4
	capsuleTextGap = 8,
	capsulePadRight = 18,
	gainGap = 6, -- foam fix 2: a stacked column's coins "+N" starts this far right of the capsule (gainSpot)
	settingsSize = 64, -- the Settings tile (top right)
	trackerWidth = 256, -- the quest tracker card (the design's 320)
	bannerWidth = 256, -- Hud_DataBanner
	ctaWidth = 240, -- the Duel CTA (the design's 300 × 116)
	ctaHeight = 92 + STICKER.lip.cta, -- UI FINAL R2 (P1): the CTA's frame, its 92 px face (Button.CTA_HEIGHT) + the lip
	ctaCompactHeight = 64, -- phones: a medium CTA
	ctaIconPx = 44,
	ctaCompactIconPx = 32,
	ctaPadding = 22, -- Button's CTA side padding (Button.style("cta").paddingX)
	ctaLineGap = 8, -- Button's gap between the CTA's icon and its texts
	ctaAir = 4, -- a little air over the CTA's measured content
	coachWidth = 512, -- the coach card (the design's 640)
	coachMinWidth = 320,
	coachBottomGap = 14, -- UI overhaul: the bottom prompt's bottom edge, this far above COLUMN.edge
	coachPadding = 10, -- top and sides (the bottom is at least panelBottom, over the foam bands)
	coachGap = 12, -- the coach card's text to its button
	-- Theme.panel's least bottom padding: the purple card's border and lip (drawn inside it) and the room over them.
	panelBottom = STICKER.border.normal + STICKER.lip.card + PANEL_BAND_GAP,
	toastTop = 110, -- UIController's TOAST_TOP: where the toasts start (base px from the top)
	gripCompactMinWidth = 120, -- the compact Grip card is never narrower than this (gripCompactWidth)
	fallbackScreen = Vector2.new(1280, 720), -- before the HUD has a size
})
-- Reading: the text estimate (see the header).
local TEXT_METRICS = table.freeze({ bodyEm = 0.6, titleEm = 0.6, lineHeight = 1.25 })
local TOUCH = Config.UI.Touch
local UI_GRIP = Config.UI.Grip
local TEXT_SIZE = Config.UI.TextSize
local FIT_SLACK = 1e-6
-- The coach card's band: as tall as the one from the top edge down to the toast line (coachPlacement).
local COACH_BAND = COLUMN.toastTop - COLUMN.rowGap - COLUMN.edge
-- ctaWidth: the queued clock at its widest digits (QueueFormat.measureSample's rule).
local CTA_CLOCK_SAMPLE = "88:88"
local WORST_COINS = { 99_999, 999_999, 999_999_999 } -- the widest Format.coins texts of each form
local WORST_ONBOARDING_COINS = 1e12
local ONBOARDING_INPUTS: { OnboardingFormat.InputKind } = { "keyboard", "touch", "gamepad" }
local GRID_COLUMNS = 2
-- Every layout the left side may take, in the order of preference (see the header). A column without the Grip card
-- uses the same layouts with grip = "hidden" (candidates).
local REGULAR_ORDER: { Candidate } = {
	{ grip = "regular", tiles = "column", left = "stack" },
	{ grip = "compact", tiles = "column", left = "stack" },
	{ grip = "regular", tiles = "grid", left = "stack" },
	{ grip = "compact", tiles = "grid", left = "stack" },
	{ grip = "regular", tiles = "row", left = "stack" },
	{ grip = "compact", tiles = "row", left = "stack" },
	{ grip = "compact", tiles = "row", left = "beside" },
}
-- Lobby HUD (spec 2026-10-11): phones follow the PC layout, the tiles always in two columns.
local COMPACT_ORDER: { Candidate } = {
	{ grip = "compact", tiles = "grid", left = "beside", clearCta = true },
	{ grip = "compact", tiles = "grid", left = "stack" },
}

-- Module table

local HudFormat = {}

HudFormat.NAV = NAV
HudFormat.BADGE_MAX = BADGE_MAX
HudFormat.COLUMN = COLUMN
HudFormat.TEXT_METRICS = TEXT_METRICS

-- Public

function HudFormat.visibleNav(isRegistered: (screen: string) -> boolean): { NavItem }
	local list: { NavItem } = {}
	for _, item in NAV do
		if isRegistered(item.screen) then
			table.insert(list, item)
		end
	end
	return list
end

-- The NAV items of one place, in DESIGN order.
function HudFormat.navAt(place: NavPlace): { NavItem }
	local list: { NavItem } = {}
	for _, item in NAV do
		if item.place == place then
			table.insert(list, item)
		end
	end
	return list
end

-- True when the data status is Studio memory mode (progress is not saved): never shown to players, only logged.
function HudFormat.isStudioMemory(status: Types.DataStatus?): boolean
	if status == nil then
		return false
	end
	return status.banner == STUDIO_MEMORY_KEY
		or (status.banner == nil and status.status == "ready" and status.persisted == false)
end

function HudFormat.banner(status: Types.DataStatus?): Banner?
	if status == nil then
		return nil
	end
	local kind: BannerKind = if WARN_STATUSES[status.status] then "warn" else "info"
	if status.status == "ready" and status.savePending then
		return { text = Strings.reasonText(SAVE_PENDING_CODE), kind = "info" }
	end
	-- Spec: the Studio memory-mode line is log only; an offline or read-only status still gets its own line.
	local serverKey = status.banner
	if serverKey == STUDIO_MEMORY_KEY then
		serverKey = nil
	end
	local serverText = if type(serverKey) == "string" then Strings.resolve(serverKey) else nil
	if serverText then
		return { text = serverText, kind = kind }
	end
	if status.status == "offline" then
		return { text = Strings.data.offlineRetrying, kind = kind }
	elseif status.status == "readonly" then
		return { text = Strings.data.loadFailed, kind = kind }
	end
	return nil
end

-- "{action} ({key})" for keyboard / gamepad when the action has a key there, else the action text alone.
function HudFormat.keyHint(textKey: string, input: InputKind): string
	local action = Strings.resolve(textKey) or textKey
	local keyKey = HudFormat.keyFor(textKey, input)
	local key = if keyKey then Strings.resolve(keyKey) else nil
	if key == nil then
		return action
	end
	return Strings.format(Strings.controls.keyHint, { action = action, key = key })
end

-- The Strings key of the key that does `textKey`'s action with this input (a keycap's text), or nil (touch, or no
-- key for that input).
function HudFormat.keyFor(textKey: string, input: InputKind): string?
	local keys = KEY_HINTS[textKey]
	if keys == nil then
		return nil
	elseif input == "keyboard" then
		return keys.keyboard
	elseif input == "gamepad" then
		return keys.gamepad
	end
	return nil
end

function HudFormat.coinGain(old: number?, new: number?): number?
	if type(old) ~= "number" or type(new) ~= "number" or not (new > old) then
		return nil
	end
	return math.floor(new - old)
end

function HudFormat.questBadge(quests: any): number
	if type(quests) ~= "table" or type(quests.active) ~= "table" then
		return 0
	end
	local n = 0
	for _, entry in quests.active do
		if type(entry) == "table" and entry.done == true and entry.claimed ~= true then
			n += 1
		end
	end
	return n
end

function HudFormat.dailyBadge(daily: any, today: number): number
	if type(daily) ~= "table" or type(daily.lastClaimDay) ~= "number" then
		return 0
	end
	return if daily.lastClaimDay < today then 1 else 0
end

function HudFormat.badgeText(n: number): string?
	if not (n >= 1) then
		return nil
	end
	return tostring(math.min(math.floor(n), BADGE_MAX))
end

function HudFormat.coinsText(coins: number?): string
	if type(coins) ~= "number" then
		return Strings.common.loading
	end
	return Format.coins(coins)
end

-- The quest tracker's quest (spec "Top right: a Quest tracker card (the unclaimed quest closest to done, Starter quests
-- first, then Daily)"): of the Starter tasks not yet claimed the one with the largest share done (a task ready to claim
-- counts as done), else the same among the day's quests; the first of equals (board order). Nil when every quest is
-- claimed or there is none (the card hides).
function HudFormat.trackedQuest(board: QuestFormat.Board): QuestFormat.Card?
	local function best(cards: { QuestFormat.Card }): QuestFormat.Card?
		local pick: QuestFormat.Card? = nil
		for _, card in cards do
			if card.state ~= "claimed" and (pick == nil or card.fraction > (pick :: QuestFormat.Card).fraction) then
				pick = card
			end
		end
		return pick
	end
	return best(board.starter) or best(board.daily)
end

local function isNumber(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- The Duel CTA's title and second line: "DUEL" / "Join the queue"; while the queue is Searching (spec: "While queued it
-- shows the queued state consistently with the queue pill") "IN QUEUE" and "Searching · m:ss" from joinedAt (the
-- pill's own clock, UI/QueueFormat.pill), or "Searching" before joinedAt is known.
function HudFormat.ctaModel(queue: QueueLike?, now: number): CtaModel
	if queue == nil or queue.state ~= SEARCHING then
		return { queued = false, title = Strings.hud.duelCta, subtext = Strings.hud.duelJoin }
	end
	local joinedAt = queue.joinedAt
	local subtext = Strings.hud.duelSearching
	if joinedAt ~= nil and isNumber(joinedAt) and isNumber(now) then
		subtext = Strings.format(Strings.hud.duelSearchingTime, { time = Format.clock(math.max(0, now - joinedAt)) })
	end
	return { queued = true, title = Strings.hud.duelQueued, subtext = subtext }
end

-- Feel pass (§18.5.2 B1-B2) ------------------------------------------------------------------------------------------

-- What the capsule does with a new Coins value. `displayed` is the number on screen, `previous` the last server value,
-- `shown` whether the HUD is visible, `replaced` a full Snapshot (§3.13: replaces the value, no count-up, no "+N").
function HudFormat.coinAction(
	displayed: number?,
	previous: number?,
	new: number?,
	shown: boolean,
	replaced: boolean
): CoinAction
	if not isNumber(new) then
		return { kind = "set", to = nil }
	end
	local value = new :: number
	if replaced or not isNumber(displayed) or not isNumber(previous) then
		return { kind = "set", to = value }
	end
	if not shown then
		return { kind = "hold", to = value }
	end
	local before = previous :: number
	if value > before then
		return { kind = "gain", to = value, gain = math.floor(value - before) }
	elseif value < before then
		return { kind = "spend", to = value }
	end
	return { kind = "none", to = value }
end

-- What the gain held while the HUD was hidden does when it shows again (§18.5.2 B1): it flies from the result panel's
-- reward label (hasSource) when it is a flight-sized amount and motion is not reduced, else counts up at the capsule.
function HudFormat.releaseHeld(
	displayed: number?,
	target: number?,
	hasSource: boolean,
	reducedMotion: boolean
): CoinAction
	if not isNumber(displayed) or not isNumber(target) then
		return { kind = "none" }
	end
	local from, to = displayed :: number, target :: number
	if to > from then
		local gain = math.floor(to - from + 0.5)
		if gain < 1 then
			return { kind = "set", to = to }
		end
		if hasSource and gain >= FLIGHT.minAmount and not reducedMotion then
			return { kind = "flight", to = to, gain = gain }
		end
		return { kind = "gain", to = to, gain = gain }
	elseif to < from then
		return { kind = "spend", to = to }
	end
	return { kind = "none", to = to }
end

-- The coin disc's rotation (degrees) t seconds into a gain, and whether the wiggle is over.
function HudFormat.iconWiggle(t: number): (number, boolean)
	if not isNumber(t) or t <= 0 then
		return 0, false
	elseif t >= WIGGLE_SECONDS then
		return 0, true
	end
	return -COIN_MOTION.iconWiggleDeg * math.sin(math.pi * t / WIGGLE_SECONDS), false
end

-- Text estimate ------------------------------------------------------------------------------------------------------

local function charCount(text: string): number
	local n = utf8.len(text)
	return if n then n else #text
end

local function charWidth(sizePx: number, font: FontKind?): number
	return sizePx * (if font == "title" then TEXT_METRICS.titleEm else TEXT_METRICS.bodyEm)
end

-- Lines of one paragraph (no line breaks) with greedy word wrap; a word wider than the line breaks across lines.
local function paragraphLines(paragraph: string, perLine: number): number
	local lines, used = 1, 0
	for _, word in string.split(paragraph, " ") do
		local length = charCount(word)
		if used > 0 and used + 1 + length <= perLine + FIT_SLACK then
			used += 1 + length
		else
			if used > 0 then
				lines += 1
			end
			local extra = math.max(0, math.ceil(length / perLine - FIT_SLACK) - 1)
			lines += extra
			used = length - extra * perLine
		end
	end
	return lines
end

-- The estimated width of `text` on one line at `sizePx` (base px).
function HudFormat.textWidth(text: string, sizePx: number, font: FontKind?): number
	return charCount(text) * charWidth(sizePx, font)
end

-- The estimated number of lines of `text` wrapped into `widthPx` (0 for an empty text).
function HudFormat.textLines(text: string, sizePx: number, widthPx: number, font: FontKind?): number
	if text == "" then
		return 0
	end
	local char = charWidth(sizePx, font)
	if not isNumber(widthPx) or not isNumber(char) or char <= 0 then
		return 1
	end
	local perLine = math.max(widthPx, char) / char
	local lines = 0
	for _, paragraph in string.split(text, "\n") do
		lines += paragraphLines(paragraph, perLine)
	end
	return lines
end

-- The estimated height of `text` wrapped into `widthPx` (TEXT_METRICS.lineHeight per line).
function HudFormat.textHeight(text: string, sizePx: number, widthPx: number, font: FontKind?): number
	return math.ceil(HudFormat.textLines(text, sizePx, widthPx, font) * sizePx * TEXT_METRICS.lineHeight - FIT_SLACK)
end

-- Base text size of a Config.UI.TextSize kind at a PreferredTextSize multiplier (Layout.textSize's rounding).
function HudFormat.kindPx(kind: string, textScale: number?): number
	local base = TEXT_SIZE[kind] or TEXT_SIZE.Body
	local multiplier = if textScale ~= nil and isNumber(textScale) and textScale > 0 then textScale else 1
	return math.floor(base * multiplier + 0.5)
end

-- Part sizes ---------------------------------------------------------------------------------------------------------

local function textScaleOf(textScale: number?): number
	return if textScale ~= nil and isNumber(textScale) and textScale > 0 then textScale else 1
end

-- Height of one line of a kind (base px).
local function lineOf(kind: string, textScale: number): number
	return math.ceil(HudFormat.kindPx(kind, textScale) * TEXT_METRICS.lineHeight - FIT_SLACK)
end

-- A Button's height (Button.new raises it to the touch minimum) under the HUD's UIScale.
local function buttonHeight(scale: number): number
	return Layout.touchBase(TOUCH.minTarget, scale)
end

-- The estimated width of a Button with this label (the Button kind in the display font; Button's own side padding
-- unless given, and its measuring margin).
function HudFormat.buttonWidth(text: string, textScale: number?, paddingPx: number?): number
	local padding = if paddingPx ~= nil and isNumber(paddingPx) then paddingPx else COLUMN.buttonPadding
	local width = HudFormat.textWidth(text, HudFormat.kindPx("Button", textScale), "title")
	return math.ceil(width + 2 * padding + COLUMN.measureMargin)
end

-- The coin capsule: the disc (at least the touch minimum), or taller when the number's line and the capsule's bands are.
function HudFormat.pillHeight(textScale: number?, scale: number): number
	local capsule = math.max(COLUMN.capsuleHeight, lineOf("HudNumber", textScaleOf(textScale)) + COLUMN.capsuleBands)
	return math.max(Layout.touchBase(COLUMN.coinDiscPx, scale), capsule)
end

-- The coin capsule's estimated width with this text (default: the widest one): the disc, then the capsule's number.
function HudFormat.pillWidth(textScale: number?, coinsText: string?): number
	local text = coinsText or HudFormat.worstCaseTexts().coins
	local number = HudFormat.textWidth(text, HudFormat.kindPx("HudNumber", textScale), "title")
	return math.ceil(COLUMN.coinDiscPx + COLUMN.capsuleTextGap + number + COLUMN.capsulePadRight)
end

-- Foam fix 2: how far the coins "+N" rises (base px). HudController starts it beside the capsule's middle (COLUMN.edge
-- + pillHeight / 2 from the HUD's top); a `labelHeight` tall label rises up to coinCounter.floatPx but never past the
-- HUD's top (it floated from the capsule's top into Roblox's top bar). Bad numbers give 0.
function HudFormat.gainRise(pillHeight: number, labelHeight: number): number
	local room = COLUMN.edge + (pillHeight - labelHeight) / 2
	if not isNumber(room) then
		return 0
	end
	return math.clamp(room, 0, COIN_MOTION.floatPx)
end

-- Foam fix 3: the coins "+N" with the capsule's thousands separator ("+12,450").
function HudFormat.gainText(amount: number): string
	return Strings.format(Strings.common.plusAmount, { n = Format.coins(amount) })
end

-- Foam fix 3: where the coins "+N" starts and how far it rises (GainSpot). A stacked column (PCs) keeps fix 2's spot:
-- gainGap right of the capsule at its middle, in HudNumber, rising gainRise. On a phone the Grip card sits right of
-- the capsule (`beside`; fix 2's "+N" printed over it), so the "+N" is the small display kind (Chip) on the capsule's
-- top edge, its right edge at the number's right end: over the capsule's own top, under Roblox's top bar. Its centre
-- moves down off the edge only as far as keeps its top inside the HUD at a large text size; it rises at most to the
-- HUD's top. Bad numbers give no rise.
function HudFormat.gainSpot(beside: boolean, pillHeight: number, textScale: number?): GainSpot
	local scale = textScaleOf(textScale)
	if not beside then
		local label = HudFormat.kindPx("HudNumber", scale) * TEXT_METRICS.lineHeight
		return {
			kind = "HudNumber",
			anchorX = 0,
			x = COLUMN.gainGap,
			yScale = 0.5,
			y = 0,
			rise = HudFormat.gainRise(pillHeight, label),
		}
	end
	local half = HudFormat.kindPx("Chip", scale) * TEXT_METRICS.lineHeight / 2
	local y = math.max(0, half - COLUMN.edge)
	return {
		kind = "Chip",
		anchorX = 1,
		x = -COLUMN.capsulePadRight,
		yScale = 0,
		y = y,
		rise = math.clamp(COLUMN.edge + y - half, 0, COIN_MOTION.floatPx),
	}
end

-- The compact Grip card's visible row (§17.7: "Lv 12 · Firm Grip" plus a 4 px bar): one line, a 2 px gap, the bar.
function HudFormat.gripCompactRowHeight(textScale: number?): number
	return lineOf("Small", textScaleOf(textScale)) + 2 + UI_GRIP.compactBarHeight
end

-- The compact Grip card's width (foam fix: phones put it beside the coin capsule): its one line `text` (Small) with the
-- card's padding (GripController: cardPadding + 4 on each side) and the measuring margin, at least
-- COLUMN.gripCompactMinWidth and at most the regular card's width (a longer line is cut with "…").
function HudFormat.gripCompactWidth(text: string, textScale: number?): number
	local line = HudFormat.textWidth(text, HudFormat.kindPx("Small", textScale))
	local width = math.ceil(line + 2 * (COLUMN.cardPadding + 4) + COLUMN.measureMargin)
	return math.clamp(width, COLUMN.gripCompactMinWidth, COLUMN.cardWidth)
end

-- The width of the regular Grip card's lines (right of its level tile).
function HudFormat.gripInfoWidth(): number
	return COLUMN.cardWidth - COLUMN.cardPadLeft - COLUMN.cardPadRight - COLUMN.levelTileWidth - COLUMN.cardGap
end

-- The regular card's level tile: "GRIP" (Chip) over the level (H2), inside the button bands.
function HudFormat.levelTileHeight(textScale: number?): number
	local ts = textScaleOf(textScale)
	return math.max(COLUMN.levelTileHeight, lineOf("Chip", ts) + lineOf("H2", ts) + COLUMN.buttonBands)
end

-- The Grip card's height: hidden 0; compact = one tap target at least the touch minimum (Reading, §17.7 vs §11.2: the
-- visible row stays <= compactRowMaxHeight, the card around it is Layout.touchBase(minTarget) tall); regular = the
-- level tile beside its lines (the rank, the bar, "{have} / {need} Grip", the Double Grip line, the next goal), padded.
function HudFormat.gripCardHeight(mode: GripMode, textScale: number?, scale: number, texts: ColumnTexts?): number
	if mode == "hidden" then
		return 0
	end
	local ts = textScaleOf(textScale)
	if mode == "compact" then
		local row = HudFormat.gripCompactRowHeight(ts)
		return math.max(
			row + 2 * COLUMN.cardPadding,
			UI_GRIP.compactRowMaxHeight,
			Layout.touchBase(TOUCH.minTarget, scale)
		)
	end
	local t = texts or HudFormat.worstCaseTexts()
	local inner = HudFormat.gripInfoWidth()
	local small = HudFormat.kindPx("Small", ts)
	local lines = {
		HudFormat.textHeight(t.gripRank, HudFormat.kindPx("Button", ts), inner, "title"),
		COLUMN.barHeight,
		HudFormat.textHeight(t.gripBar, small, inner),
		HudFormat.textHeight(t.gripChip, small, inner - COLUMN.chipIconPx - COLUMN.listGap),
		HudFormat.textHeight(t.gripGoal, small, inner),
	}
	local info = 0
	for index, h in lines do
		info += h + if index > 1 then COLUMN.listGap else 0
	end
	return COLUMN.cardPadTop + math.max(HudFormat.levelTileHeight(ts), info) + COLUMN.cardPadBottom
end

-- A tile's size (base px): at least the tile size, as wide as the widest label needs (all tiles share it, so a column
-- lines up), as tall as the icon, the label line and the foam bands need. Phones use the smaller tile.
function HudFormat.tileSize(compact: boolean, textScale: number?, labels: { string }?): (number, number)
	local ts = textScaleOf(textScale)
	local base = if compact then COLUMN.tileSizeCompact else COLUMN.tileSize
	local icon = if compact then COLUMN.tileIconCompactPx else COLUMN.tileIconPx
	local chip = HudFormat.kindPx("Chip", ts)
	local widest = 0
	for _, label in labels or HudFormat.worstCaseTexts().tiles do
		widest = math.max(widest, HudFormat.textWidth(label, chip, "title"))
	end
	local width = math.max(base, math.ceil(widest + 2 * COLUMN.tilePadding + COLUMN.measureMargin))
	local height = math.max(base, icon + COLUMN.tileLabelGap + lineOf("Chip", ts) + COLUMN.tileBands)
	return width, height
end

-- How `n` tiles of `w` × `h` arrange in a mode: (columns, rows, width, height). A row wraps at `maxWidth`.
function HudFormat.tilesBox(
	mode: TilesMode,
	n: number,
	w: number,
	h: number,
	maxWidth: number
): (number, number, number, number)
	if n <= 0 then
		return 0, 0, 0, 0
	end
	local columns = 1
	if mode == "grid" then
		columns = math.min(n, GRID_COLUMNS)
	elseif mode == "row" then
		columns = math.clamp(math.floor((maxWidth + COLUMN.tileGap + FIT_SLACK) / (w + COLUMN.tileGap)), 1, n)
	end
	local rows = math.ceil(n / columns)
	return columns, rows, columns * w + (columns - 1) * COLUMN.tileGap, rows * h + (rows - 1) * COLUMN.tileGap
end

-- The onboarding coach card's height at `width` for one text (spec "Onboarding: a coach card"): one row, the text (Body;
-- Small on phones) beside its button (Got it / Skip tutorial, a Button-kind label), padded. math.huge when the button
-- leaves no room for the text.
function HudFormat.coachHeight(
	width: number,
	textScale: number?,
	scale: number,
	text: string,
	buttonText: string,
	compact: boolean
): number
	local ts = textScaleOf(textScale)
	local size = HudFormat.kindPx(if compact then "Small" else "Body", ts)
	local pad = COLUMN.coachPadding
	local labelWidth = width - 2 * pad - HudFormat.buttonWidth(buttonText, ts) - COLUMN.coachGap
	if labelWidth < charWidth(size) * 6 then
		return math.huge
	end
	local content = math.max(HudFormat.textHeight(text, size, labelWidth), buttonHeight(scale))
	return pad + content + math.max(pad, COLUMN.panelBottom)
end

-- Worst-case texts ----------------------------------------------------------------------------------------------------

local worstTexts: ColumnTexts? = nil

local function text(key: string, args: { [string]: any }?): string
	local template = Strings.resolve(key)
	return if template then Strings.format(template, args) else ""
end

local function longest(list: { string }): string
	local best = ""
	for _, entry in list do
		if charCount(entry) > charCount(best) then
			best = entry
		end
	end
	return best
end

local function longestName(prefix: string, rows: { any }): string
	local names = {}
	for _, row in rows do
		table.insert(names, text(prefix .. row.key))
	end
	return longest(names)
end

-- The longest text each HUD part can show (Strings, Config and Catalog; computed once).
function HudFormat.worstCaseTexts(): ColumnTexts
	local cached = worstTexts
	if cached then
		return cached
	end
	local grip = Config.Grip
	local maxLevel = grip.maxLevel
	local rank = longestName("grip.rank.", grip.Ranks)
	local topRankLevel = 0
	for _, row in grip.Ranks do
		topRankLevel = math.max(topRankLevel, row.level)
	end
	local totals = grip.LevelTotals
	local coinsTexts = { Strings.common.loading }
	for _, n in WORST_COINS do
		table.insert(coinsTexts, Format.coins(n))
	end
	local tiles = {}
	for _, item in HudFormat.navAt("tile") do
		table.insert(tiles, text(item.textKey))
	end
	local onboarding: { OnboardingText } = {}
	for _, step in OnboardingFormat.steps() do
		for _, input in ONBOARDING_INPUTS do
			-- Coins above every goal: the text reads "{goal}/{goal}", its widest form.
			local ctx: OnboardingFormat.Context = {
				onboarding = nil,
				ready = true,
				coins = WORST_ONBOARDING_COINS,
				input = input :: OnboardingFormat.InputKind,
			}
			local line = OnboardingFormat.text(step, ctx)
			table.insert(onboarding, { text = line, gotIt = step.id == "welcome" })
		end
	end
	-- Batch 1 #7a: the capsule goals as the regular card shows them, at the widest Coins text.
	local capsuleSlot = #grip.Capsule.slotPrices
	local worstCoins = Format.coins(WORST_COINS[#WORST_COINS])
	local result: ColumnTexts = {
		coins = longest(coinsTexts),
		gripRank = rank,
		gripLevel = tostring(maxLevel),
		gripCompact = text("grip.hudLevelCompact", { level = maxLevel, rank = rank }),
		gripBar = longest({
			text("grip.hudBar", {
				have = Format.coins(totals[#totals - 1] or 0),
				need = Format.coins(totals[#totals] or 0),
			}),
			text("grip.hudMax"),
		}),
		gripChip = text("grip.restedChip", { minutes = GripMath.restedMinutes(grip.Rested.burst) }),
		gripGoal = longest({
			text("grip.goalRank", { rank = rank, level = topRankLevel }),
			text("grip.goalMax"),
			text("grip.goalCapsuleReady", { slot = capsuleSlot }),
			text("grip.goalUnlockReady", { slot = capsuleSlot }),
			text("grip.hudGoalCapsule", { slot = capsuleSlot, have = worstCoins, need = worstCoins }),
		}),
		tiles = tiles,
		onboarding = onboarding,
		gotIt = Strings.common.gotIt,
		skip = Strings.onboarding.skip,
	}
	worstTexts = result
	return result
end

-- The left side plan (Hud_Left and the tiles) --------------------------------------------------------------------------

local function validScreen(screenPx: Vector2): Vector2
	local x, y = screenPx.X, screenPx.Y
	if not (isNumber(x) and isNumber(y) and x > 0 and y > 0) then
		return COLUMN.fallbackScreen
	end
	return screenPx
end

-- The left side's gaps (base px): between the coin capsule and the Grip card (phones use the tight gap: the thumbstick
-- line is close), and from Hud_Left to the tiles: under the regular card COLUMN.tilesGap (it held the removed Upgrade
-- tab), else a tile badge's reach plus air (foam fix 2: on phones the 6 px gap put the Squishies
-- count on the coin capsule's outline).
function HudFormat.leftGaps(compact: boolean, grip: GripMode): (number, number)
	local inner = if compact then COLUMN.gap else COLUMN.leftGap
	local toTiles = if grip == "regular" then COLUMN.tilesGap else COLUMN.badgeReach + COLUMN.badgeAir
	return inner, toTiles
end

-- Foam fix 2: the tile row's box (base px) grown by a count badge's reach above it and right of it: what the toast
-- column keeps beside (HudController registers it; the Daily "1" hanging past the last tile touched a toast).
function HudFormat.badgeReachRect(tiles: Rect): Rect
	local reach = COLUMN.badgeReach
	return { x = tiles.x, y = tiles.y - reach, w = tiles.w + reach, h = tiles.h + reach }
end

-- The layouts to try, in order: a Grip card that is in the column is never hidden; one that is not there is "hidden"
-- (it takes no room, and the capsule alone is the same stacked or beside).
local function candidates(compact: boolean, gripPresent: boolean): { Candidate }
	local list: { Candidate } = {}
	local seen: { [string]: boolean } = {}
	local order: { Candidate } = if compact then COMPACT_ORDER else REGULAR_ORDER
	for _, candidate in order do
		local grip: GripMode = if gripPresent then candidate.grip else "hidden"
		local left: LeftMode = if gripPresent then candidate.left else "stack"
		local key = table.concat({ grip, candidate.tiles, left }, "/")
		if not seen[key] then
			seen[key] = true
			local entry: Candidate =
				{ grip = grip, tiles = candidate.tiles, left = left, clearCta = candidate.clearCta }
			table.insert(list, entry)
		end
	end
	return list
end

-- The lower-left thumbstick zone (see the header) in base px: Config.UI.Touch's share of the canvas width and of the
-- whole screen's height (`screenHeightPx`, px; never less than the HUD's own height), its bottom at the HUD's bottom.
-- Reading: the HUD (CoreUISafeInsets) leaves out the top bar inset, so a share of the HUD's height alone put the zone's
-- top about 25 px too low on a phone (foam fix: the phone tiles reached into it).
function HudFormat.thumbstickZone(canvas: Vector2, screenHeightPx: number?, scale: number): Rect
	local s = if isNumber(scale) and scale > 0 then scale else 1
	local hudPx = canvas.Y * s
	local screen = if screenHeightPx ~= nil and isNumber(screenHeightPx) then math.max(screenHeightPx, hudPx) else hudPx
	local height = TOUCH.thumbstickZoneHeight * screen / s
	return { x = 0, y = canvas.Y - height, w = canvas.X * TOUCH.thumbstickZoneWidth, h = height }
end

-- Every layout the left side may take for these inputs, in the order leftColumnPlan tries them (see the header).
-- `parts.grip` says whether the Grip card wants to show (default true), `parts.touch` whether the player uses touch
-- (default false), `parts.tiles` how many tiles show (default every tile), `parts.screenHeight` the whole screen's
-- height in px (default the HUD's); `parts.texts` replaces the worst-case texts. A phone's side-by-side layout is left
-- out when Hud_Left would reach the Duel CTA's widest width centred at the top (clearCta; a row gap kept).
function HudFormat.columnLayouts(
	screenPx: Vector2,
	layoutClass: string,
	textScale: number?,
	parts: ColumnParts?
): { ColumnPlan }
	local ts = textScaleOf(textScale)
	local screen = validScreen(screenPx)
	local scale = Layout.uiScale(screen.Y, screen.X) -- UI FINAL R2 (PR1): the live UIScale's fit
	local canvas = Vector2.new(screen.X / scale, screen.Y / scale)
	local compact = layoutClass == "compact"
	local narrow = compact or (parts ~= nil and parts.touch == true)
	local zone = HudFormat.thumbstickZone(canvas, if parts then parts.screenHeight else nil, scale)
	local limit = if narrow then math.min(canvas.Y * UI_GRIP.leftColumnMaxFraction, zone.y) else canvas.Y - COLUMN.edge
	local texts = (parts and parts.texts) or HudFormat.worstCaseTexts()
	local gripPresent = parts == nil or parts.grip ~= false
	local tileCount = if parts and parts.tiles ~= nil then math.max(0, parts.tiles) else #texts.tiles
	local tileWidth, tileHeight = HudFormat.tileSize(compact, ts, texts.tiles)
	local pill = HudFormat.pillHeight(ts, scale)
	local pillWidth = HudFormat.pillWidth(ts, texts.coins)
	local maxRow = canvas.X - 2 * COLUMN.edge
	local ctaLeft = (canvas.X - HudFormat.ctaWidth(compact, ts)) / 2
	local layouts: { ColumnPlan } = {}
	for _, candidate in candidates(compact, gripPresent) do
		local gripHeight = HudFormat.gripCardHeight(candidate.grip, ts, scale, texts)
		local innerGap, tilesGap = HudFormat.leftGaps(compact, candidate.grip)
		local beside = candidate.left == "beside" and gripHeight > 0
		local leftBottom = if beside
			then COLUMN.edge + math.max(pill, gripHeight)
			else COLUMN.edge + pill + (if gripHeight > 0 then innerGap + gripHeight else 0)
		local tilesTop = leftBottom + tilesGap
		local columns, rows, tilesWidth, tilesHeight =
			HudFormat.tilesBox(candidate.tiles, tileCount, tileWidth, tileHeight, maxRow)
		local bottom = if tileCount > 0 then tilesTop + tilesHeight else leftBottom
		local gripWidth = if candidate.grip == "compact"
			then HudFormat.gripCompactWidth(texts.gripCompact, ts)
			elseif gripHeight > 0 then COLUMN.cardWidth
			else 0
		local width = if beside then pillWidth + innerGap + gripWidth else math.max(pillWidth, gripWidth)
		if candidate.clearCta and beside and COLUMN.edge + width + COLUMN.rowGap > ctaLeft + FIT_SLACK then
			continue
		end
		table.insert(layouts, {
			scale = scale,
			canvas = canvas,
			narrow = narrow,
			limit = limit,
			grip = candidate.grip,
			left = if beside then "beside" else "stack",
			tiles = candidate.tiles,
			columns = columns,
			rows = rows,
			tileWidth = tileWidth,
			tileHeight = tileHeight,
			pillHeight = pill,
			gripHeight = gripHeight,
			leftBottom = leftBottom,
			tilesTop = tilesTop,
			tilesWidth = tilesWidth,
			tilesHeight = tilesHeight,
			bottom = bottom,
			width = width,
			fits = bottom <= limit + FIT_SLACK and tilesWidth <= maxRow + FIT_SLACK and width <= maxRow + FIT_SLACK,
		})
	end
	return layouts
end

-- The left side's layout (see the header): the first layout of columnLayouts that fits, else the shortest one (the first
-- of equally short ones).
function HudFormat.leftColumnPlan(
	screenPx: Vector2,
	layoutClass: string,
	textScale: number?,
	parts: ColumnParts?
): ColumnPlan
	local shortest: ColumnPlan? = nil
	for _, plan in HudFormat.columnLayouts(screenPx, layoutClass, textScale, parts) do
		if plan.fits then
			return plan
		end
		if shortest == nil or plan.bottom < (shortest :: ColumnPlan).bottom then
			shortest = plan
		end
	end
	return shortest :: ColumnPlan
end

-- True when two plans lay the parts out the same way (the controllers re-layout only then).
function HudFormat.samePlan(a: ColumnPlan?, b: ColumnPlan?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a.grip == b.grip
		and a.left == b.left
		and a.tiles == b.tiles
		and a.columns == b.columns
		and a.narrow == b.narrow
		and a.tileWidth == b.tileWidth
		and a.tileHeight == b.tileHeight
		and a.scale == b.scale
end

-- Free room ------------------------------------------------------------------------------------------------------------

local function present(rect: Rect?): Rect?
	if rect == nil or not (isNumber(rect.x) and isNumber(rect.y) and isNumber(rect.w) and isNumber(rect.h)) then
		return nil
	end
	return if rect.w > 0 and rect.h > 0 then rect else nil
end

-- The free span (low, high) of a band [y, y + h] on the canvas: from the left edge to the right edge, cut by every
-- blocker that meets the band (one left of the canvas's centre pushes `low` right of it, one right of the centre pulls
-- `high` left of it), COLUMN.rowGap from each.
function HudFormat.freeSpan(canvas: Vector2, y: number, h: number, blockers: { Rect }): (number, number)
	local low, high = COLUMN.edge, canvas.X - COLUMN.edge
	local centre = canvas.X / 2
	for _, raw in blockers do
		local rect = present(raw)
		if rect and rect.y < y + h and y < rect.y + rect.h then
			if rect.x + rect.w / 2 < centre then
				low = math.max(low, rect.x + rect.w + COLUMN.rowGap)
			else
				high = math.min(high, rect.x - COLUMN.rowGap)
			end
		end
	end
	return low, high
end

-- Where the coach card goes (see the header): centred from `top` (default COLUMN.edge; lobby HUD, spec 2026-10-11:
-- right under the Duel CTA), in the room the HUD groups leave on its band (COACH_BAND tall: from the top edge it ended
-- at the toast line), its preferred width when it ends inside the band, else as wide as the room. x = its left edge.
function HudFormat.coachPlacement(input: CoachInput): CoachPlace
	local canvas = input.canvas
	local top = if input.top ~= nil and isNumber(input.top) then input.top else COLUMN.edge
	local line = top + COACH_BAND
	local want = input.preferred or COLUMN.coachWidth
	local minWidth = input.minWidth or COLUMN.coachMinWidth
	local low, high = HudFormat.freeSpan(canvas, top, line - top, input.blockers)
	local room = high - low
	if room < minWidth - FIT_SLACK then
		local width = math.max(0, math.min(want, canvas.X - 2 * COLUMN.edge))
		return {
			x = (canvas.X - width) / 2,
			y = top,
			width = width,
			height = input.heightAt(width),
			fits = false,
		}
	end
	local function place(width: number, height: number, fits: boolean): CoachPlace
		local x = math.clamp(canvas.X / 2 - width / 2, low, high - width)
		return { x = x, y = top, width = width, height = height, fits = fits }
	end
	local first = math.min(want, room)
	local firstHeight = input.heightAt(first)
	if top + firstHeight <= line + FIT_SLACK then
		return place(first, firstHeight, true)
	end
	local roomHeight = input.heightAt(room)
	return place(room, roomHeight, top + roomHeight <= line + FIT_SLACK)
end

-- UI overhaul (see the header): the coach card at the bottom middle, clear of the blockers on its band. The band
-- depends on the card's height, which depends on its width, so the width is settled in two passes (the preferred
-- width's band, then the room that band leaves). x = its left edge.
function HudFormat.coachBottomPlacement(input: CoachInput): CoachPlace
	local canvas = input.canvas
	local want = input.preferred or COLUMN.coachWidth
	local minWidth = input.minWidth or COLUMN.coachMinWidth
	local bottom = canvas.Y - COLUMN.edge - COLUMN.coachBottomGap
	local function band(width: number): (number, number, number, number)
		local height = input.heightAt(width)
		local top = bottom - height
		local low, high = HudFormat.freeSpan(canvas, top, height, input.blockers)
		return top, height, low, high
	end
	local width = math.max(0, math.min(want, canvas.X - 2 * COLUMN.edge))
	local top, height, low, high = band(width)
	if high - low < width - FIT_SLACK then
		width = math.max(0, high - low)
		top, height, low, high = band(width)
	end
	local room = high - low
	if room < minWidth - FIT_SLACK or width < minWidth - FIT_SLACK then
		local fallback = math.max(0, math.min(want, canvas.X - 2 * COLUMN.edge))
		local fallbackHeight = input.heightAt(fallback)
		return {
			x = (canvas.X - fallback) / 2,
			y = bottom - fallbackHeight,
			width = fallback,
			height = fallbackHeight,
			fits = false,
		}
	end
	local x = math.clamp(canvas.X / 2 - width / 2, low, high - width)
	return { x = x, y = top, width = width, height = height, fits = true }
end

-- Where the Duel CTA goes (lobby HUD, spec 2026-10-11; see the header): COLUMN.edge from the HUD's top on every layout,
-- centred, moved into the free span its band leaves between the blockers (freeSpan: the left column and the tiles push
-- it right, the top-right group left). With a span narrower than the CTA it stays at the screen's centre, fits = false.
-- x = its left edge.
function HudFormat.ctaPlacement(input: CtaInput): CtaPlace
	local canvas, size = input.canvas, input.size
	local y = COLUMN.edge
	local low, high = HudFormat.freeSpan(canvas, y, size.Y, input.blockers)
	local centred = (canvas.X - size.X) / 2
	if high - low < size.X - FIT_SLACK then
		return { x = centred, y = y, fits = false }
	end
	return { x = math.clamp(centred, low, high - size.X), y = y, fits = true }
end

-- The Duel CTA's widest width (base px, Theme's text estimate at a PreferredTextSize multiplier): its icon, the gap, the
-- wider of its titles (DUEL, IN QUEUE; H2 on phones, Title elsewhere) and its second lines (the queued clock at its
-- widest digits) and the paddings, as HudController sizes it; at least COLUMN.ctaWidth on regular layouts.
function HudFormat.ctaWidth(compact: boolean, textScale: number?): number
	local ts = textScaleOf(textScale)
	local hud = Strings.hud
	local titlePx = HudFormat.kindPx(if compact then "H2" else "Title", ts)
	local subPx = HudFormat.kindPx("Chip", ts)
	local clock = Strings.format(hud.duelSearchingTime, { time = CTA_CLOCK_SAMPLE })
	local title = math.max(
		HudFormat.textWidth(hud.duelCta, titlePx, "title"),
		HudFormat.textWidth(hud.duelQueued, titlePx, "title")
	)
	local sub = math.max(HudFormat.textWidth(hud.duelJoin, subPx, "title"), HudFormat.textWidth(clock, subPx, "title"))
	local icon = if compact then COLUMN.ctaCompactIconPx else COLUMN.ctaIconPx
	local natural = math.ceil(icon + COLUMN.ctaLineGap + math.max(title, sub) + 2 * COLUMN.ctaPadding + COLUMN.ctaAir)
	return if compact then natural else math.max(COLUMN.ctaWidth, natural)
end

-- Gamepad links (§11.4, §17.7) ----------------------------------------------------------------------------------------

local function linkOf(links: { [string]: FocusLink }, key: string): FocusLink
	local existing = links[key]
	if existing then
		return existing
	end
	local created: FocusLink = {}
	links[key] = created
	return created
end

-- The HUD's gamepad links by key (see FocusGroups). Every key without a link in a direction gets none (the engine's
-- own search):
-- * the left column (`left`, then the tiles) top to bottom; tiles in rows (two columns, a row) link left / right in a
--   row and up / down between rows, the first row up to the column's last;
-- * the right column (`right`) top to bottom;
-- * across (lobby HUD, spec 2026-10-11): the column's top items right to the Duel CTA at the top middle (else the
--   coach card's button, else the right column's first); the CTA left back to the column's last item and right to the
--   right column's first (which links left back to it), Down to the queue pill's Cancel, else the coach card's button
--   (each links Up back to the CTA); the coach card's button left to the column's last item and right to the right
--   column; a tile at the right end of its row (every tile of a column) right to the CTA (spec "Gamepad: D-pad moves
--   along the tile column, the Duel CTA is reachable").
function HudFormat.focusLinks(groups: FocusGroups): { [string]: FocusLink }
	local links: { [string]: FocusLink } = {}
	local left, tiles, right = groups.left, groups.tiles, groups.right
	local columns = math.max(1, groups.tileColumns or 1)
	local coach, cta, queue = groups.coach, groups.cta, groups.queue
	for index, key in left do
		local item = linkOf(links, key)
		item.up = left[index - 1]
		item.down = left[index + 1]
	end
	local lastLeft = left[#left]
	for index, key in tiles do
		local item = linkOf(links, key)
		local column = (index - 1) % columns
		if columns == 1 then
			item.up = tiles[index - 1] or lastLeft
			item.down = tiles[index + 1]
		else
			item.up = if index > columns then tiles[index - columns] else lastLeft
			item.down = tiles[index + columns]
			if column > 0 then
				item.left = tiles[index - 1]
			end
			if column < columns - 1 then
				item.right = tiles[index + 1]
			end
		end
	end
	if lastLeft and tiles[1] then
		linkOf(links, lastLeft).down = tiles[1]
	end
	for index, key in right do
		local item = linkOf(links, key)
		item.up = right[index - 1]
		item.down = right[index + 1]
	end
	-- Across the screen.
	local topRight = right[1]
	local acrossTop = cta or coach or topRight
	if acrossTop then
		for _, key in left do
			linkOf(links, key).right = acrossTop
		end
	end
	if topRight then
		local fromRight = cta or coach or lastLeft
		if fromRight then
			linkOf(links, topRight).left = fromRight
		end
	end
	if coach then
		local item = linkOf(links, coach)
		item.up = cta
		item.left = lastLeft
		item.right = topRight
	end
	if cta then
		local item = linkOf(links, cta)
		item.left = lastLeft or tiles[#tiles]
		item.right = topRight
		item.down = queue or coach
		if queue then
			linkOf(links, queue).up = cta
		end
		for index, key in tiles do
			local atRowEnd = (index - 1) % columns == columns - 1 or index == #tiles
			if atRowEnd then
				linkOf(links, key).right = cta
			end
		end
	end
	return links
end

-- What DPadUp selects (§11.4, §17.7, §17.12 L5 "DPadUp reaches the Grip card"): nothing while the HUD hides, else the
-- entry (the Grip card) while it shows, else the first tile, else nothing.
function HudFormat.dpadUpTarget(hudShown: boolean, entryShown: boolean, rowShown: boolean): ("entry" | "row")?
	if not hudShown then
		return nil
	elseif entryShown then
		return "entry"
	elseif rowShown then
		return "row"
	end
	return nil
end

return HudFormat
