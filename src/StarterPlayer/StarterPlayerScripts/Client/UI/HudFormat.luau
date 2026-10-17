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
--   COIN_SHOP / coinShop(monetization, bundles?, allowed?)
--                              2026-10-16 (the coin pill's "+", owner yes "Add it", plan [UD5]): the Shop's open params
--                              of a coin pill tap. Review fix (2026-10-16): COIN_SHOP (its Coins tab) only once a coin
--                              pack can be bought there (ShopFormat.coinsView has rows: offered by the server, with a
--                              productId, on sale, bundles allowed); else nil, the Shop's top, as the design's
--                              openCoins opens the whole shop (H:987) and the Coins tab would only say "not available"
--   trackedQuest(board)        the quest tracker's quest (spec "Top right"): the unclaimed quest closest to done, the
--                              Starter tasks first, then the day's quests (UI/QuestFormat.board); nil when there is none
--   ctaModel(queue, now)       the DUEL area (UI FINAL R4): "DUEL" / "Join the queue" while idle (H:130-131); while the
--                              1v1 queue is Searching the search bar's "Finding match", its "m:ss" since joining
--                              (H:139) and its second line (the queue's position or arena line, plan FD1)
--   pickerShown(userId, match) UI FINAL R4: whether the DUEL button shows the TDM / FFA picker (Config.Match testers,
--   or
--                              everyone with pickerForEveryone)
--   duelAction(pickerOn, mode, match?)
--                              the owner's 1v1 tab (2026-10-16): a DUEL press with TEAM DEATHMATCH / FREE FOR ALL
--                              picked joins the match queue ("match"); with the 1v1 tab (or no picker) the 1v1 queue
--                              ("queue")
--   trackerStatus(card)        UI FINAL R4: the quest tracker's status line: "Ready to claim!" (ready, the coin yellow)
--                              or "+N coins" (H:995)
-- Feel pass (§18.5.2 B1-B2; UI FINAL R4: the design's coin landing, H:562-578, H:663-675):
--   coinAction(displayed, previous, new, shown, replaced) / releaseHeld(displayed, target, hasSource, reducedMotion)
--                              what the coin capsule does with a new Coins value / with the gain held while the HUD was
--                              hidden (set, hold, gain, spend, flight, none)
--   coinStep(amount, k, i)     G4.10: the share of a gain shown after the i-th of k coins lands: floor(amount / k) a
--                              coin, the last coin the rest (H:663-668)
--   flashPlan(now, lastAt, big) PR7: a landing's bright flash "now", "later" (the last coin's, at lastAt + the gap) or
--                              "skip" (inside coinFlight.bounceMinGapMs of the last one)
--   flightShows(base, target, amount, k, i)
--                              G4.10: the number a flight shows once i of its k coins landed: base + coinStep, never
--                              past the newest Coins (target) when that is known, the newest at the last coin, so it
--                              only rises from what was shown
--   gripFloatShown(shown, level, compact, firstPerson)
--                              UI FINAL R4: whether the GRIP float (H:92-96) shows: the HUD up with a Grip level, not
--                              on phones (the compact Grip card shows the level; it would sit over the player) and not
--                              in first person (practice: it would sit over the targets)
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
--                              UI FINAL R4 (the design's spots, Config.UI.Sticker.hud): on regular layouts Hud_Left
--                              starts at (leftX, leftTop) (H:74), the tiles at (navX, navTop) or a row gap under
--                              Hud_Left when it reaches lower (H:98), the right column at (rightEdge, rightTop) (H:156)
--                              and the DUEL area at ctaTop (PR10); phones (the compact class) keep COLUMN.edge
--                              (origins)
--   origins(compact)           those spots: { left, nav, right (its top-right corner), ctaTop }
--   badgeReachRect(tiles)      foam fix 2: the tile row's box plus a count badge's reach above and right of it (the box
--                              the toast column keeps beside; UI FINAL R4: the badge sits inside the tile, H:102, so
--                              the reach is its sdBadge pop's, H:32)
--   thumbstickZone(canvas, screenHeightPx?, scale)
--                              the lower-left thumbstick zone (Config.UI.Touch: 40% of the width × 45% of the whole
--                              screen's height) in the HUD's base px, its bottom at the HUD's bottom
--   gripRowWidth(textScale?, texts?) / gripGoalWidth(textScale?, texts?)
--                              UI FINAL R4 (H:82-90): the bare Grip row's width (the bar column, the gap and the
--                              Double Grip chip) and the width its goal line wraps at
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
--                              lobby HUD (spec 2026-10-11): the Duel CTA at the top middle on every layout, `top`
--                              (default COLUMN.edge) down, centred and moved into the free span the left and right
--                              groups leave (freeSpan); fits = false when that span is narrower than it (then the
--                              screen's centre). UI FINAL R4: ctaWidth is the DUEL button's design width (350, H:126;
--                              times the compact scale on phones); the search and found bars take barWidth
--   barWidth(design, span)     the search / found bar's width: its design width, narrower only to the span (and the
--                              canvas) it has; barParts(width) drops the dots and the second line under dropBelow
--   ctaScales(compact)         the DUEL area's draw scales: phones draw only the idle DUEL button at ctaCompactScale;
--                              the search bar (its texts, its cancel X) and the mode picker stay at 1 (PR1, PR2)
--   foundSpot(rect, canvas, compact, barBottom?)
--                              MATCH FOUND's top middle (G4.2): the DUEL area's last rect (else the canvas centre at
--                              origins().ctaTop), pushed a row gap under the duel HUD's top bar once that shows
--   focusLinks(groups)
--                              the gamepad links of the HUD (§11.4, §17.7): the left column top to bottom through the
--                              tiles (DPadUp's Grip card, Down walks the tiles), the right column (Settings, the
--                              tracker) and the links between them: the Duel CTA between the left column and Settings,
--                              Down to the mode picker's tabs (UI FINAL R4; left / right between them, Up back), else
--                              (while searching) the queue pill's first hint button, else the queue pill's Cancel or
--                              the coach card's button (which link Up back to it), a tile ->
--                              the CTA (chainLinks, the Grip panel's Show me chain, went with its pad cards, build plan
--                              Phase 6)
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
local QueueFormat = require(script.Parent.QueueFormat)
local ShopFormat = require(script.Parent.ShopFormat)

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

-- The DUEL area's texts (ctaModel; UI FINAL R4): idle, the DUEL button's two lines; queued (the 1v1 queue
-- Searching), the search bar's title, its time ("" before joinedAt is known) and its second line.
export type CtaModel = { queued: boolean, title: string, subtext: string, time: string }
-- The fields of StateController.QueueView the CTA reads.
export type QueueLike = {
	state: Types.QueueState,
	joinedAt: number?,
	position: number?,
	messageKey: string?,
	searching: number?,
	arenasFree: number?,
}
-- UI FINAL R4: the quest tracker's status line (trackerStatus): its text and whether it is the ready one (the coin
-- yellow and the yellow border, H:995).
export type TrackerStatus = { text: string, ready: boolean }
-- UI FINAL R4: where the HUD's groups start (origins; base px): Hud_Left's and the tiles' top-left corners, the right
-- column's top-right corner (x from the right edge) and the DUEL area's top.
export type Origins = { left: Vector2, nav: Vector2, right: Vector2, ctaTop: number }

-- Layout types (base px).
export type FontKind = "body" | "title"
export type Rect = { x: number, y: number, w: number, h: number }
-- "hidden" = no Grip card in the column: it has no Grip state yet or a duel holds it back (never a layout choice).
export type GripMode = "regular" | "compact" | "hidden"
-- The tiles: one column (the design), two columns, or a row that wraps to the screen's width.
export type TilesMode = "column" | "grid" | "row"
-- Hud_Left's two items: the coin capsule over the Grip card (the design), or side by side on one row (phones).
export type LeftMode = "stack" | "beside"
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
	modes: { string }?, -- UI FINAL R4: the DUEL mode picker's tabs, left to right (under the Duel CTA; testers)
	hint: string?, -- UI FINAL R4: the queue pill's first hint button while it shows (under the searching bar)
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
	top: number?, -- UI FINAL R4: its top edge (origins().ctaTop); default COLUMN.edge
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
local FLIGHT = Config.UI.motion.coinFlight
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

-- UI FINAL R4: the design's HUD numbers (Config.UI.Sticker.hud, `H:n` = "Squishy Duels HUD.dc.html" line n).
local HUD = STICKER.hud

-- The HUD's shared sizes in base px (UI FINAL R4: 1 design px = 1 base px, plan §1.1; the phone-only sizes are the
-- game's own readings, the design draws no phone layout).
local COLUMN = table.freeze({
	edge = 12, -- phones (the compact class): every HUD group sits this far from the HUD's edges
	-- UI FINAL R4: the design's spots on every other layout (origins).
	leftX = HUD.left.x, -- H:74
	leftTop = HUD.left.y,
	navX = HUD.nav.x, -- H:98
	navTop = HUD.nav.y,
	rightEdge = HUD.right.edge, -- H:156
	rightTop = HUD.right.top,
	rightGap = HUD.right.gap,
	gap = 6, -- Theme.Padding.small: between the items inside a group
	rowGap = 8, -- between two groups
	-- H:74 gap 14, H:82 margin-top -4: the Grip row starts 10 under the pill's 58 px face, 5 under its 5 px lip.
	leftGap = HUD.left.gap - HUD.grip.pull - STICKER.lip.button,
	cardWidth = 270, -- the compact Grip card's widest (phones; the regular row is gripRowWidth)
	cardPadding = 6, -- the compact Grip card's padding (Theme.Padding.small)
	listGap = 4, -- the Grip row to its goal line
	-- UI FINAL R4 (H:82-90): the bare Grip row: its bar (14 tall + the 3 px lip), the gap, its text line; the Double
	-- Grip chip beside it.
	gripBarWidth = HUD.grip.barWidth,
	gripBarHeight = STICKER.bars.grip.height + STICKER.lip.bar,
	gripBarGap = Layout.lipGap(HUD.grip.barGap, STICKER.lip.bar), -- H:83: 3 under the 14 px bar = 0 past its 3 px lip
	gripPadLeft = HUD.grip.padLeft,
	gripRowGap = HUD.grip.gap,
	boltPx = HUD.grip.boltPx,
	boostGap = HUD.grip.boostGap,
	tilesGap = 8, -- Hud_Left to the tiles when Hud_Left reaches past navTop (a row gap)
	tileGap = 0, -- H:98: the nav column has no gap
	tileGapCompact = 10, -- phones: the two tile columns keep the game's gap
	-- UI FINAL R4 (H:102, H:32): the badge sits inside the tile (right 8, top 0); only its sdBadge pop (1.3) reaches
	-- past the tile's top: (1.3 - 1) x 32 / 2 = 5 px. What is above or beside the tiles keeps badgeAir more.
	badgeReach = 5,
	badgeAir = 4,
	tileWidth = HUD.nav.width, -- H:99: the nav sticker, 118 x 104
	tileHeight = HUD.nav.height,
	tileIconPx = HUD.nav.iconPx, -- H:100
	tileLabelPull = HUD.nav.labelPull, -- H:101
	-- Phones (foam fix): the tile row clears the thumbstick zone; still the touch minimum (>= 44 px at the 0.85 phone
	-- scale). UI FINAL R4 (reading): the faceless sticker's proportions on the 58 px tile (92 / 104, 28 / 104).
	tileSizeCompact = 58,
	tileIconCompactPx = 50,
	tileLabelPullCompact = 16,
	tilePadding = 6, -- Button's tile side padding
	tileBands = 0, -- UI FINAL R4 (P13): the faceless sticker has no bands
	measureMargin = 4, -- Button.widthFor's margin
	buttonPadding = 18, -- Button's primary / secondary side padding
	-- UI FINAL R4 (H:75-80): the coin pill: its 58 px face + the 5 px lip, at least 220 wide, the number after a 68 px
	-- left padding (the 78 px coin overhangs it), 10 on the right.
	pillFace = HUD.coins.face,
	pillLip = STICKER.lip.button,
	pillBorder = STICKER.border.normal,
	pillMinWidth = HUD.coins.minWidth,
	pillPadLeft = HUD.coins.padLeft,
	pillPadRight = HUD.coins.padRight,
	-- 2026-10-16 (plan [UD5]): the green "+" after the number (H:80), the design's 12 px gap before it (H:75).
	pillGap = HUD.coins.gap,
	pillPlus = HUD.coinPlus.face,
	settingsSize = 64, -- phones: the Settings tile (top right)
	settingsWidth = HUD.settings.width, -- H:157: the Settings sticker, 92 x 90
	settingsHeight = HUD.settings.height,
	settingsIconPx = HUD.settings.iconPx, -- H:158
	settingsLabelPull = HUD.settings.labelPull, -- H:159
	settingsIconCompactPx = 28, -- phones: the gear on the 64 px tile
	trackerWidth = HUD.tracker.width, -- the quest tracker card (the quest row's look, H:363)
	bannerWidth = 256, -- Hud_DataBanner
	ctaWidth = HUD.cta.width, -- H:126: the DUEL button, 350 x 92
	ctaHeight = 92 + STICKER.lip.cta, -- UI FINAL R2 (P1): the CTA's frame, its 92 px face (Button.CTA_HEIGHT) + the lip
	ctaCompactScale = HUD.cta.compactScale, -- phones: the design's CTA at this scale, 64 base px tall
	ctaCompactHeight = 64,
	ctaTop = HUD.cta.top, -- PR10
	searchWidth = HUD.search.width, -- H:136
	foundWidth = HUD.found.width, -- H:149
	barHeight = HUD.search.face + STICKER.lip.search, -- H:136, H:149: the bars' 96 px face + the 7 px lip
	pickerGap = Layout.lipGap(HUD.picker.gap, STICKER.lip.cta), -- N:145: 14 under the 92 px face = 7 past its lip
	coachWidth = 512, -- the coach card (the design's 640)
	coachMinWidth = 320,
	coachBottomGap = 14, -- UI overhaul: the bottom prompt's bottom edge, this far above COLUMN.edge
	coachPadding = 10, -- top and sides (the bottom is at least panelBottom, over the foam bands)
	coachGap = 12, -- the coach card's text to its button
	-- Theme.panel's least bottom padding: the purple card's border and lip (drawn inside it) and the room over them.
	panelBottom = STICKER.border.normal + STICKER.lip.card + PANEL_BAND_GAP,
	-- UIController's TOAST_TOP: where the toasts start (base px from the top; UI FINAL R4: N:197's 200, the toasts
	-- still start under the DUEL area when it reaches lower, UIController.toastsBelow)
	toastTop = HUD.toastTop,
	coachLine = 110, -- the coach card's band ends here (the toast line before UI FINAL R4; coachPlacement)
	gripCompactMinWidth = 120, -- the compact Grip card is never narrower than this (gripCompactWidth)
	fallbackScreen = Vector2.new(1280, 720), -- before the HUD has a size
})
-- Reading: the text estimate (see the header).
local TEXT_METRICS = table.freeze({ bodyEm = 0.6, titleEm = 0.6, lineHeight = 1.25 })
local TOUCH = Config.UI.Touch
local UI_GRIP = Config.UI.Grip
local TEXT_SIZE = Config.UI.TextSize
local FIT_SLACK = 1e-6
-- The coach card's band (coachPlacement): as tall as from the top edge down to COLUMN.coachLine.
local COACH_BAND = COLUMN.coachLine - COLUMN.rowGap - COLUMN.edge
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
HudFormat.COIN_SHOP = table.freeze({ tab = "coins" }) -- 2026-10-16 (plan [UD5]): see the header

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

-- Review fix (2026-10-16, job coinplus): a coin pill tap's Shop params (see the header). `monetization` = the
-- StateController "monetization" field ({bundles = the offered keys}); `bundles` defaults to
-- Config.Monetization.CoinBundles and `allowed` to ShopFormat.bundlesAllowed(Config.Grip), as the Shop reads them.
function HudFormat.coinShop(monetization: unknown, bundles: { any }?, allowed: boolean?): { tab: string }?
	local offered = if type(monetization) == "table" and type((monetization :: any).bundles) == "table"
		then (monetization :: any).bundles
		else nil
	local on = if allowed == nil then ShopFormat.bundlesAllowed(Config.Grip) else allowed
	local view = ShopFormat.coinsView(offered, bundles or Config.Monetization.CoinBundles, {}, on)
	return if view.unavailable then nil else HudFormat.COIN_SHOP
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

-- The DUEL area (UI FINAL R4; see the header): idle "DUEL" / "Join the queue" (H:130-131); while the 1v1 queue is
-- Searching the search bar's "Finding match", its time "m:ss" from joinedAt (the queue pill's own clock; "" before
-- joinedAt is known; H:139) and its second line (QueueFormat.searchLine: the arena or position line, else "").
function HudFormat.ctaModel(queue: QueueLike?, now: number): CtaModel
	if queue == nil or queue.state ~= SEARCHING then
		return { queued = false, title = Strings.hud.duelCta, subtext = Strings.hud.duelJoin, time = "" }
	end
	local joinedAt = queue.joinedAt
	local time = ""
	if joinedAt ~= nil and isNumber(joinedAt) and isNumber(now) then
		time = Format.clock(math.max(0, now - joinedAt))
	end
	local counted = type(queue.arenasFree) == "number" and type(queue.searching) == "number"
	local line = if counted then QueueFormat.searchLine(queue :: any) else nil
	return { queued = true, title = Strings.hud.findingMatch, subtext = line or "", time = time }
end

-- UI FINAL R4: whether the DUEL button shows the mode picker for `userId` (Config.Match.pickerTesters, or everyone
-- with pickerForEveryone; `match` defaults to Config.Match).
function HudFormat.pickerShown(userId: number?, match: any?): boolean
	local m = match or Config.Match
	if m.pickerForEveryone == true then
		return true
	end
	return type(userId) == "number" and type(m.pickerTesters) == "table" and table.find(m.pickerTesters, userId) ~= nil
end

-- The owner's 1v1 tab (2026-10-16): what a DUEL press starts. A picked match mode (a key of Config.Match.Modes: TEAM
-- DEATHMATCH, FREE FOR ALL) joins the in-server match queue ("match": MatchJoin(mode)); the 1v1 tab, any other pick
-- or no picker the 1v1 queue ("queue": the "queue" screen's QueueJoin, as before the picker). `match` defaults to
-- Config.Match.
function HudFormat.duelAction(pickerOn: boolean, mode: string?, match: any?): "match" | "queue"
	local modes = (match or Config.Match).Modes
	if pickerOn and type(mode) == "string" and type(modes) == "table" and modes[mode] ~= nil then
		return "match"
	end
	return "queue"
end

-- UI FINAL R4 (H:995): the quest tracker's status line: "Ready to claim!" for a quest ready to claim, else its reward
-- "+N coins".
function HudFormat.trackerStatus(card: QuestFormat.Card): TrackerStatus
	if card.state == "claim" then
		return { text = Strings.hud.questReady, ready = true }
	end
	return { text = Strings.format(Strings.hud.trackerReward, { coins = Format.coins(card.reward) }), ready = false }
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

-- UI FINAL R4 (G4.10, H:663-668): how much of a gain of `amount` the number shows once i of its k coins have landed:
-- floor(amount / k) per coin, all of it at the last (i >= k). Whole numbers; bad input gives the whole amount.
function HudFormat.coinStep(amount: number, k: number, i: number): number
	if not (isNumber(amount) and isNumber(k) and isNumber(i)) or k < 1 or i >= k then
		return if isNumber(amount) then math.floor(amount) else 0
	end
	return math.floor(amount / math.floor(k)) * math.max(0, math.floor(i))
end

-- UI FINAL R4 (PR7, decided 2026-10-15): a landing's bright flash (the coin's flip, glow, rays, the number's pop and
-- the pill's ring, H:566-575): "now" when the last one played at least coinFlight.bounceMinGapMs ago (or never),
-- "later" for the last coin of a flight (`big`, never dropped: it plays at lastAt + the gap, `at`), else "skip" (its
-- sparks and number step still play). Times in seconds.
function HudFormat.flashPlan(now: number, lastAt: number?, big: boolean): ("now" | "later" | "skip", number?)
	local gap = FLIGHT.bounceMinGapMs / 1000
	if lastAt == nil or not isNumber(lastAt) or now - (lastAt :: number) >= gap - FIT_SLACK then
		return "now", nil
	elseif big then
		return "later", (lastAt :: number) + gap
	end
	return "skip", nil
end

-- UI FINAL R4 (G4.10): the number a flight of `amount` started from `base` shows once i of its k coins have landed:
-- base + coinStep, never past `target` (the newest Coins) when that is known; the last coin, or a spend that took the
-- newest under base, shows target. A claim's StateDelta may come before or after the flight starts: either way the
-- number only rises from base (until the delta it stays at base).
function HudFormat.flightShows(base: number, target: number?, amount: number, k: number, i: number): number
	local known = target ~= nil and isNumber(target)
	if known and (i >= k or (target :: number) < base) then
		return target :: number
	end
	local shown = base + HudFormat.coinStep(amount, k, i)
	return if known then math.min(shown, target :: number) else shown
end

-- UI FINAL R4 (H:92-96): whether the GRIP float shows (see the header).
function HudFormat.gripFloatShown(shown: boolean, level: number?, compact: boolean, firstPerson: boolean): boolean
	return shown and level ~= nil and not compact and not firstPerson
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

-- UI FINAL R4 (H:75, G4.23): the coin pill's frame: its 58 px face and 5 px lip, taller only when the number's line
-- (the coin role's Coin kind, H:79) and the 4 px border need it. Every layout and every UI scale (the coin overhangs
-- the face; the tap target is the frame, >= 52).
function HudFormat.pillHeight(textScale: number?, _scale: number?): number
	local line = lineOf("Coin", textScaleOf(textScale)) + 2 * COLUMN.pillBorder
	return math.max(COLUMN.pillFace, line) + COLUMN.pillLip
end

-- UI FINAL R4 (H:75): the coin pill's estimated width with this text (default: the widest one): its 4 px border, its
-- 68 px left padding (the coin overhangs it), the number (Coin kind), the 12 px gap and the 36 px "+" (2026-10-16,
-- H:80) and its 10 px right padding, at least 220 (a border-box width, H:18).
function HudFormat.pillWidth(textScale: number?, coinsText: string?): number
	local text = coinsText or HudFormat.worstCaseTexts().coins
	local number = HudFormat.textWidth(text, HudFormat.kindPx("Coin", textScale), "title")
	local width = 2 * COLUMN.pillBorder
		+ COLUMN.pillPadLeft
		+ number
		+ COLUMN.pillGap
		+ COLUMN.pillPlus
		+ COLUMN.pillPadRight
	return math.max(COLUMN.pillMinWidth, math.ceil(width))
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

-- UI FINAL R4 (H:82-90, G4.14): the bare Grip row's width: its left padding, the bar column (the 200 px bar over
-- "{have} / {need} Grip", the wider of the two), the gap and the Double Grip chip (the bolt, its gap and "2x ~N min";
-- reserved even while empty, so the row never widens). Its goal line (UD4) wraps inside it (gripGoalWidth).
function HudFormat.gripRowWidth(textScale: number?, texts: ColumnTexts?): number
	local t = texts or HudFormat.worstCaseTexts()
	local small = HudFormat.kindPx("Small", textScale)
	local bar = math.max(COLUMN.gripBarWidth, HudFormat.textWidth(t.gripBar, small))
	local chip = COLUMN.boltPx + COLUMN.boostGap + HudFormat.textWidth(t.gripChip, small)
	return math.ceil(COLUMN.gripPadLeft + bar + COLUMN.gripRowGap + chip)
end

-- UI FINAL R4 (UD4): the regular row's goal line width: the row's, inside its left padding (the line wraps there, so
-- the left column is never wider than the row).
function HudFormat.gripGoalWidth(textScale: number?, texts: ColumnTexts?): number
	return HudFormat.gripRowWidth(textScale, texts) - COLUMN.gripPadLeft
end

-- The Grip card's height: hidden 0; compact = one tap target at least the touch minimum (Reading, §17.7 vs §11.2: the
-- visible row stays <= compactRowMaxHeight, the card around it is Layout.touchBase(minTarget) tall); regular (UI
-- FINAL R4, the bare row, H:83-87) = the bar with its lip, the gap and "{have} / {need} Grip" (one line), then the
-- goal line (UD4) wrapped at gripGoalWidth.
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
	local small = HudFormat.kindPx("Small", ts)
	local row = COLUMN.gripBarHeight + COLUMN.gripBarGap + lineOf("Small", ts)
	local goal = if t.gripGoal ~= ""
		then COLUMN.listGap + HudFormat.textHeight(t.gripGoal, small, HudFormat.gripGoalWidth(ts, t))
		else 0
	return row + goal
end

-- A tile's size (base px; UI FINAL R4: the faceless nav sticker, H:99-101): at least 118 x 104, as wide as the widest
-- label needs (all tiles share it, so a column lines up), as tall as the picture less the label's pull plus the label
-- line (the nav label's D23, H:101). Phones use the smaller tile (Chip labels, the scaled picture and pull).
function HudFormat.tileSize(compact: boolean, textScale: number?, labels: { string }?): (number, number)
	local ts = textScaleOf(textScale)
	local width0 = if compact then COLUMN.tileSizeCompact else COLUMN.tileWidth
	local height0 = if compact then COLUMN.tileSizeCompact else COLUMN.tileHeight
	local icon = if compact then COLUMN.tileIconCompactPx else COLUMN.tileIconPx
	local pull = if compact then COLUMN.tileLabelPullCompact else COLUMN.tileLabelPull
	local kind = if compact then "Chip" else "D23"
	local px = HudFormat.kindPx(kind, ts)
	local widest = 0
	for _, label in labels or HudFormat.worstCaseTexts().tiles do
		widest = math.max(widest, HudFormat.textWidth(label, px, "title"))
	end
	local width = math.max(width0, math.ceil(widest + 2 * COLUMN.tilePadding + COLUMN.measureMargin))
	local height = math.max(height0, icon - pull + lineOf(kind, ts) + COLUMN.tileBands)
	return width, height
end

-- How `n` tiles of `w` × `h` arrange in a mode, `gap` apart (default COLUMN.tileGap; phones COLUMN.tileGapCompact):
-- (columns, rows, width, height). A row wraps at `maxWidth`.
function HudFormat.tilesBox(
	mode: TilesMode,
	n: number,
	w: number,
	h: number,
	maxWidth: number,
	gap: number?
): (number, number, number, number)
	if n <= 0 then
		return 0, 0, 0, 0
	end
	local g = if gap ~= nil and isNumber(gap) then gap else COLUMN.tileGap
	local columns = 1
	if mode == "grid" then
		columns = math.min(n, GRID_COLUMNS)
	elseif mode == "row" then
		columns = math.clamp(math.floor((maxWidth + g + FIT_SLACK) / (w + g)), 1, n)
	end
	local rows = math.ceil(n / columns)
	return columns, rows, columns * w + (columns - 1) * g, rows * h + (rows - 1) * g
end

-- UI FINAL R4: where the HUD's groups start (see the header and Origins): the design's spots, phones COLUMN.edge (the
-- DUEL area there: PR10's top at the compact scale, so the emblem stays inside the HUD too).
function HudFormat.origins(compact: boolean): Origins
	if compact then
		local edge = COLUMN.edge
		return {
			left = Vector2.new(edge, edge),
			nav = Vector2.new(edge, edge),
			right = Vector2.new(edge, edge),
			ctaTop = math.ceil(COLUMN.ctaTop * COLUMN.ctaCompactScale - FIT_SLACK),
		}
	end
	return {
		left = Vector2.new(COLUMN.leftX, COLUMN.leftTop),
		nav = Vector2.new(COLUMN.navX, COLUMN.navTop),
		right = Vector2.new(COLUMN.rightEdge, COLUMN.rightTop),
		ctaTop = COLUMN.ctaTop,
	}
end

-- UI FINAL R4 (plan R4 "compact widths"): the search / found bar's width: its design width, at most the free span it
-- has (the span the HUD groups leave at its band, or the canvas less its edges); never below 0.
function HudFormat.barWidth(design: number, span: number): number
	if not (isNumber(design) and isNumber(span)) then
		return math.max(0, if isNumber(design) then design else 0)
	end
	return math.max(0, math.min(design, span))
end

-- UI FINAL R4: whether a search bar `width` wide keeps its dots and its second line (plan R4: under
-- Config.UI.Sticker.hud.search.dropBelow they drop).
function HudFormat.barParts(width: number): { dots: boolean, line2: boolean }
	local keep = isNumber(width) and width >= HUD.search.dropBelow - FIT_SLACK
	return { dots = keep, line2 = keep }
end

-- UI FINAL R4 (PR1, PR2; plan R4 "compact widths": the bars at full size, only narrower): the DUEL area's parts' draw
-- scales. Phones draw the idle DUEL button at COLUMN.ctaCompactScale; the search bar (its 16 px texts and the 52 px
-- cancel X) and the testers' mode picker (52 px tabs) are never scaled.
function HudFormat.ctaScales(compact: boolean): { idle: number, search: number, picker: number }
	return { idle = if compact then COLUMN.ctaCompactScale else 1, search = 1, picker = 1 }
end

-- UI FINAL R4 (G4.2): MATCH FOUND's top-middle point in SD_Overlay's base px (the same insets as SD_Hud): the DUEL
-- area's last rect, else the canvas centre at origins(compact).ctaTop; once the duel HUD's top bar shows (its bottom
-- `barBottom`), a row gap under it (the overlays fix of the old matched banner: on a phone it covered the lives row).
function HudFormat.foundSpot(rect: Rect?, canvas: Vector2, compact: boolean, barBottom: number?): Vector2
	local x = if rect then rect.x + rect.w / 2 else canvas.X / 2
	local y = if rect then rect.y else HudFormat.origins(compact).ctaTop
	if barBottom ~= nil and isNumber(barBottom) then
		y = math.max(y, barBottom + COLUMN.rowGap)
	end
	return Vector2.new(x, y)
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
		-- UI FINAL R4: the bare row's chip (H:89, FD3).
		gripChip = text("hud.gripBoost", { minutes = GripMath.restedMinutes(grip.Rested.burst) }),
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
-- line is close; UI FINAL R4: the design's 5 under the pill's lip, H:74 + H:82), and from Hud_Left to the tiles: under
-- the regular Grip row COLUMN.tilesGap (a row gap; on regular layouts the tiles start at navTop anyway, H:98), else a
-- tile badge's reach plus air (foam fix 2: on phones the 6 px gap put the Squishies count on the coin capsule's
-- outline).
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
	-- UI FINAL R4: the design's spots (origins; phones COLUMN.edge) and the tiles' gap.
	local origin = HudFormat.origins(compact)
	local tileGap = if compact then COLUMN.tileGapCompact else COLUMN.tileGap
	local layouts: { ColumnPlan } = {}
	for _, candidate in candidates(compact, gripPresent) do
		local gripHeight = HudFormat.gripCardHeight(candidate.grip, ts, scale, texts)
		local innerGap, tilesGap = HudFormat.leftGaps(compact, candidate.grip)
		local beside = candidate.left == "beside" and gripHeight > 0
		local top = origin.left.Y
		local leftBottom = if beside
			then top + math.max(pill, gripHeight)
			else top + pill + (if gripHeight > 0 then innerGap + gripHeight else 0)
		local tilesTop = if compact then leftBottom + tilesGap else math.max(origin.nav.Y, leftBottom + tilesGap)
		local columns, rows, tilesWidth, tilesHeight =
			HudFormat.tilesBox(candidate.tiles, tileCount, tileWidth, tileHeight, maxRow, tileGap)
		local bottom = if tileCount > 0 then tilesTop + tilesHeight else leftBottom
		local gripWidth = if candidate.grip == "compact"
			then HudFormat.gripCompactWidth(texts.gripCompact, ts)
			elseif gripHeight > 0 then HudFormat.gripRowWidth(ts, texts)
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

-- Where the Duel CTA goes (lobby HUD, spec 2026-10-11; see the header): `input.top` (default COLUMN.edge; UI FINAL R4:
-- origins().ctaTop) from the HUD's top on every layout, centred, moved into the free span its band leaves between the
-- blockers (freeSpan: the left column and the tiles push it right, the top-right group left). With a span narrower
-- than the CTA it stays at the screen's centre, fits = false. x = its left edge.
function HudFormat.ctaPlacement(input: CtaInput): CtaPlace
	local canvas, size = input.canvas, input.size
	local y = if input.top ~= nil and isNumber(input.top) then input.top else COLUMN.edge
	local low, high = HudFormat.freeSpan(canvas, y, size.Y, input.blockers)
	local centred = (canvas.X - size.X) / 2
	if high - low < size.X - FIT_SLACK then
		return { x = centred, y = y, fits = false }
	end
	return { x = math.clamp(centred, low, high - size.X), y = y, fits = true }
end

-- UI FINAL R4: the DUEL button's width (base px, Theme's text estimate at a PreferredTextSize multiplier): the
-- design's 350 (H:126), or wider when its 128 px left padding (the emblem), "DUEL" or "Join the queue" and its 24 px
-- right padding need it at a large text size; on phones the second line hides and the whole button is drawn at
-- COLUMN.ctaCompactScale. The search and found bars take barWidth instead.
function HudFormat.ctaWidth(compact: boolean, textScale: number?): number
	local ts = textScaleOf(textScale)
	local hud = Strings.hud
	local title = HudFormat.textWidth(hud.duelCta, HudFormat.kindPx("Duel", ts), "title")
	local sub = if compact then 0 else HudFormat.textWidth(hud.duelJoin, HudFormat.kindPx("D17", ts), "title")
	local frame = 2 * STICKER.border.heavy + HUD.cta.padLeft + HUD.cta.padRight -- H:126 (border-box, H:18)
	local natural = math.ceil(frame + math.max(title, sub) + COLUMN.measureMargin)
	local width = math.max(COLUMN.ctaWidth, natural)
	return if compact then math.ceil(width * COLUMN.ctaCompactScale) else width
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
		local modes: { string } = groups.modes or {}
		item.left = lastLeft or tiles[#tiles]
		item.right = topRight
		item.down = modes[1] or groups.hint or queue or coach
		if queue then
			linkOf(links, queue).up = cta
		end
		-- UI FINAL R4: the mode picker's tabs, left / right between them, Up back to the CTA, Down on to the queue's
		-- Cancel or the coach card's button.
		for index, key in modes do
			local tab = linkOf(links, key)
			tab.up = cta
			tab.left = modes[index - 1]
			tab.right = modes[index + 1]
			tab.down = queue or coach
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
