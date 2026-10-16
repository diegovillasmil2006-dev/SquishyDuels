--!strict
-- BoxController (client only). DESIGN §6.4 (boxes, presentation contract), §6.10 (paid random items: the policy table and
-- the odds disclosure items 1-7), §7.6 / §7.7 (the box counter prompt and the in-world odds board), §9.11 (the box
-- reveal), §9.15 (1 viewport, <= 24 UI frames), §11.1-§11.6 (Boxes screen, states, focus, spend confirmation), §18.1
-- (ReducedMotion), §18.6 (box.shake / box.open / reveal.<rarity>). Words and numbers come from UI/BoxFormat (pure).
-- The client only sends intents (a box id and a request id); the server decides the price, the policy, the draw, the
-- refund and the save (§6.1, §12). Lobby only: UIController refuses and closes both screens from Matched through
-- Returning (lobbyOnly), and the reveal queue waits for the lobby.
--
-- * "boxes" (modal, registered in init so the HUD Boxes button appears): the box list (StaticIcon gift box preview,
--   name, "400 Coins" / box.freeOnly), and for the selected box the full disclosure ALWAYS above the Open area:
--   1 name + price, 2 "Chances by rarity: …", 3 "What's inside & chances", 4 one row per item (preview, name, rarity text
--   + pips + colour, the exact percent, Owned, "If you already own it: +N Coins", Inspect when the "inspect" screen
--   exists, also for unowned), 5 "Total: 100.00%", 6 the footer, 7 the Open area below it all. Compact layout keeps
--   1, 2 and 6 inline and a text button box.details shows / hides 3-5 (never a lone (i) icon). L1 / R1 cycle the boxes.
-- * Open area (BoxFormat.openView, §6.10 table): eligible -> the two-step ConfirmButton "Open: {cost} Coins" ->
--   "Confirm: …" + "Balance after: …" (§11.5); not enough Coins -> disabled with box.needCoins and the text button
--   box.howToEarn (closes the screen and shows a Waypoint to WorldLayout.waypoint("squeeze")); checking -> disabled
--   "Checking…" + the checking note; unknown -> Try again (fires PolicyRetry; disabled, with the seconds left, until
--   Config.Monetization.Policy.manualRetryMinSeconds after the later of the last press and the moment "unknown"
--   arrived, BoxFormat.retryWait, so the server's 30 s rule never drops a press) + box.unknownNote; restricted -> "Shop
--   squishies directly" (opens "shop" with {tab = "squishies", boxId}) + box.restrictedNote; the Treat Box -> box.freeOnly
--   and no Open; complete / saving / duel / profile not ready -> disabled with the reason. No Robux upsell and no Coin
--   Store link anywhere here (§6.10).
-- * Open press (the confirming press): a new HttpService GUID per press, reused on the next press when the last reply
--   did not settle the request (BoxFormat.isIndeterminate); the spinner after Config.UI.motion.loadingSpinnerDelayMs and
--   a gentle 2D wobble of the selected card's gift box while waiting (§9.11 "Request"; off under ReducedMotion);
--   NetController.invokeAsync("BoxOpen", boxId, requestId). A refusal toasts its reason (NotifyController.showResult:
--   common.noCoinsSpent only when charged == false). No reply after Config.UI.Boxes.stillCheckingSeconds, or an
--   error.generic reply: box.stillChecking, and the outcome comes from the unseen reveals (below); the client never
--   claims a refund or a result itself.
-- * Reveal ("boxReveal", modal over Boxes or on its own; §9.11 table): the shared ViewportStage with the gift_box
--   (SquishyCache), 3 wobbles with hops and a NEUTRAL glow, the lid popping by mesh Offset with 16 Confetti2D dots, the
--   real squishy rising (scale 0.3 -> 1 on a spring ω 14, ζ 0.5) while the box sinks and fades, then the rarity colour
--   (glow <= Config.Anim.boxReveal.glowMaxOpacity, never a white flash), 8 slow light-ray frames, label + pips + "NEW!" or
--   "Already owned: +N Coins", then a 20°/s turntable with Equip (new only), Inspect (when "inspect" exists; params
--   {squishyId, owned = true, source = "boxReveal"}, the stage keeps the model for it), Open another (paid boxes) and
--   Close. Skip is visible from 0 ms; Skip, a tap after skipTapAfterMs or ButtonA (the Skip button holds the gamepad
--   focus) jumps to the final state with the identical result. Sounds fire from the Scheduler step: box.shake at the
--   wobbles, box.open at the pop, reveal.<rarity> at the reveal (BoxFormat.soundCues); SoundController.duck("boxReveal")
--   until the result. A duplicate refund >= Config.UI.motion.coinFlight.minAmount flies to the Coins pill
--   (HudController.flyCoins). ReducedMotion: anticipation 300 ms, no wobble, hops, lid pop, sinking, rays, confetti,
--   slide or turntable; the reveal is a crossfade (§9.11, §18.1); the sounds are unchanged. Closing or skipping never
--   calls a reward remote: AckReveal(requestId) is sent once per reveal when its result is reached.
-- * Unseen replay (one rule for rejoin, the day-7 Treat Box "daily:<day>" and the BoxOpen timeout): every
--   StateController unseenReveals entry whose requestId is not in this client's in-flight BoxOpen set and was not played
--   this session is queued and played one at a time (BoxFormat.pendingReveals). debugHoldReveals(true) pauses the
--   unseen ones (reply reveals still play).
-- * World: WorldBinder.registerStand("SD_BoxStand"): eligible / checking open "boxes" on the stand's BoxId box;
--   restricted / unknown open "shop" filtered to it (the boxes screen when no shop exists). Like QueueController does for
--   its podium, the prompt is relabelled locally from its SD_TextKey / SD_AltTextKey ("See Boxes" / "Shop Squishies",
--   BoxFormat.promptKey) and the odds board's live line "Body" shows BoxFormat.boardText, on policy changes, stream-in
--   and once a second.
-- Readings (DESIGN is silent):
--   * "Open another" closes the reveal and shows the Boxes screen on the same box (the odds again, then the two-step
--     confirm); it is offered for paid boxes only.
--   * A reveal closed by a match before its result is not acknowledged: it plays again after the duel (still unseen).
--     Any other close counts as seen (AckReveal), like a skip. While it animates, Backspace / ButtonB skip to the result
--     (a UIController.pushBack handler) instead of closing it unseen; at the result they close it.
--   * The §9.15 "<= 24 UI frames" counts the reveal's animated frames: 8 light rays + 16 confetti dots.
--   * The turntable is off under ReducedMotion (§18.1 "ambient motion ... stop").
--   * The skip after a tap also plays reveal.<rarity> when it has not played yet (sounds carry the moment, §18.1 #8);
--     the shakes and the pop are not replayed.
--   * The wait wobble of the Open press is a ±WAIT_WOBBLE_DEG rotation of the selected card's static preview at
--     WAIT_WOBBLE_HZ (StaticIcon itself is never animated in 3D).
--   * No result before the reveal (§9.11 "no fake-outs"; Part 7 review fix): StateController holds each new unseen
--     result (the Coins pill shows the spend but not the refund; the odds rows, Squishies and the NEW badge do not show
--     the new squishy) until ack() releases it at the result (after the refund's coin flight has started) or on a
--     close counted as seen. A reveal closed by a match keeps its hold (Config.UI.Boxes.revealHoldMaxSeconds at most).
-- Part 8 (DESIGN §11.2 audit): the reveal panel stays on screen at every text size. Its stage is the class height
-- (340 / 200 compact) unless the other rows at the player's text size (title, result info, saving note, the wrapped
-- result buttons) would push the panel past BoxFormat.REVEAL_PANEL.heightShare of the screen; then the stage shrinks
-- (BoxFormat.revealStageHeight; at the largest text on a phone the panel was about 517 base px on a 441 px screen).
-- Reading (§6.10 item 7, "the Open button below all of the above"): Boxes_OpenButton stays the last item of the
-- Disclosure list (not pinned like the Squishies and Shop buttons); the compact "Details" text button keeps the list
-- short on phones.
-- Foam UI restyle (spec 2026-10-09; look and layout only: every button, the timings, the reveal's result input guard and
-- the disclosure's items 1-7 in their order are unchanged):
-- * Boxes: the title is a Lilac header tab (the Boxes tile's colour, Theme.headerTab; the panel's top padding follows
--   it and the panel sits a quarter of the tab lower, so both are centred). The box list holds foam cards (the selected
--   one a light Lilac face) with the name in the Button display kind and the cost as the coin and a bare number
--   (BoxFormat.costText; the Treat Box keeps box.freeOnly). The disclosure: the box name in the Title kind, the price as
--   the coin and a number, the item rows on a lighter paper inside a Biscuit inset field, each chance in the HudNumber
--   kind, the footer in Ink2.
-- * Reveal: the box name is the header tab (Lilac); the rows sit in a Body frame (a header tab needs a panel without a
--   UIListLayout of its own); the stage's frame is the ink outline until the rarity rim; the result line is a Chip:
--   "NEW!" on Strawberry (outlined white), a duplicate's refund on Frosting.
-- Foam fix batch (2026-10-09; on an 844×390 phone only 35 of the Open button's 48 px showed, with no outline or bevel):
-- * Close hangs on the panel's top-right corner level with the header tab (as on Quests, Daily and Settings); the
--   Close-only header row is gone (InventoryFormat.hangingChrome).
-- * The Open area is pinned under the Disclosure list (a sibling of it, like the Squishies and Shop detail buttons):
--   the list (items 1-6, in their order) scrolls above it and the Open area (item 7) stays whole below all of it at every
--   size. The room under the list keeps the "Balance after" line reserved, so arming never moves the button. This
--   replaces Part 8's reading that kept it as the list's last item.
-- * An odds row's chance column is side by side: the percent and "Owned" on the left, Inspect on the right, centred
--   (before, Inspect was stacked under them with a 2 px gap and the rows switched between two heights); it wraps under
--   them only when the column is too narrow.
-- * The reveal's result rows breathe: REVEAL_PANEL.infoGap 6 between the name, the rarity tag and the result chip, and
--   REVEAL_PANEL.buttonGap 10 between the result buttons (BoxFormat; the stage height counts both).
-- Foam fix round 2 (2026-10-09; the odds list was cut 6 px above Open, the reveal's top edge cut through the box name
-- and price behind it, and on a phone the reveal was as tall as the Boxes panel):
-- * The odds list ends Theme.Padding.large above the Open area (was small).
-- * While the reveal shows, the disclosure's box name and price are see-through (they keep their room, so nothing
--   moves; the reveal's tab names the box), like the covered panel's header tab.
-- * The reveal keeps inside the Boxes panel's height less REVEAL_PANEL.shorterBy (BoxFormat; on phones its stage sits at
--   the new 88 px minimum), so the two outlines no longer double up.
-- Squishy overhaul (spec 2026-10-09 §3.2 idle life; Anim/IdleRig): the revealed squishy gets a rig ("hero", deformer
-- twist "pivot" like Inspect's) only once the rise ends. Until then writeScale / writeFade alone move it (no rig,
-- section or deformer write); writeFade keeps every part's built Transparency as its base, so the hidden squish face
-- stays hidden. At the highlight's writeScale(1) (or a skip's) the rig starts with the wow face for
-- IdleRig.REVEAL_WOW_SECONDS, then breathes and blinks through the result (the turntable stays); from then on
-- writeScale / writeFade never run again, so the normal and the squish mouth never both show. Inspect from the result
-- takes the rig over (InspectController.takeRig, called while the reveal closes, before Inspect opens and adopts the
-- model) with the reveal's breath (IdleRig:breathNow), so the shape does not jump; any other close destroys it with the
-- model. While it lives the rig counts as a hero rig in the rig budget (IdleRig, Anim/HeroRigs) and steps in the
-- "SD_Rigs" profiler scope (spec §5).
-- Studio: debugRevealPreview(id) queues a local reveal of the squishy (source "preview": no remote, no grant, no hold,
-- nothing acknowledged; no Equip or Open another) in a box that holds it (snack otherwise).
-- UI overhaul (2026-10-11, Candy UI): each box has its own colour (BOX_ACCENTS: Snack Coral, Sweet Lavender, Treat
-- Gold) on its selector card and its gift preview (BOX_TINTS, the StaticIcon's ImageColor3); the selected box is the
-- full face with a white frame, the others its face dimmed towards the window (UNSELECTED_DIM); their texts follow the
-- face (Theme.textOnColor). The odds rows are raised plum rows on the recessed field; Open is the Lime purchase CTA;
-- Close is the red X.
-- UI overhaul, the reveal's escalation (UI/UiFx, drawn above the windows): at the pop a neutral burst (white and cream
-- for every result: no rarity hint before the reveal, §9.11); at the reveal a burst in the rarity's colour whose tier
-- grows with the rarity (BOX_LOOK.revealTiers: Common small, Uncommon medium, Epic large, Exclusive huge) and, for Epic
-- and Exclusive, a brief localized shake of the reveal panel (BOX_LOOK.revealShake); the name, the rarity tag and the
-- result chip then pop in one after another (BOX_LOOK.infoStaggerMs; "NEW!" pops bigger than a duplicate's refund).
-- A skip lands on the same final state at once (no sequence). Under ReducedMotion only the bursts' glows show.
-- Stable names: Boxes_CloseButton, Boxes_Box_<id>, Boxes_DetailsButton, Boxes_Row_<i> (with Boxes_InspectButton),
-- Boxes_OpenButton, Boxes_RetryButton, Boxes_ShopDirectButton, Boxes_HowToEarnButton; Reveal_SkipButton,
-- Reveal_EquipButton, Reveal_InspectButton, Reveal_OpenAnotherButton, Reveal_CloseButton.

-- Services

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local RarityStyle = require(Shared.Art.RarityStyle)
local Spring = require(Shared.Util.Spring)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local BoxFormat = require(Client.UI.BoxFormat)
local Button = require(Client.UI.Components.Button)
local Chip = require(Client.UI.Components.Chip)
local CoinIcon = require(Client.UI.Components.CoinIcon)
local ConfirmButton = require(Client.UI.Components.ConfirmButton)
local Confetti2D = require(Client.UI.Confetti2D)
local Create = require(Client.UI.Create)
local Focus = require(Client.UI.Focus)
local InventoryFormat = require(Client.UI.InventoryFormat)
local KeyText = require(Client.UI.KeyText)
local Layout = require(Client.UI.Layout)
local RarityTag = require(Client.UI.Components.RarityTag)
local StaticIcon = require(Client.UI.Components.StaticIcon)
local Theme = require(Client.UI.Theme)
local ViewportStage = require(Client.UI.ViewportStage)
local Waypoint = require(Client.UI.Waypoint)
local IdleRig = require(Client.Anim.IdleRig)
local Scheduler = require(Client.Anim.Scheduler)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local Tweens = require(Client.Anim.Tweens)
local SquishyCache = require(Client.Models.SquishyCache)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

type Card = {
	id: string,
	root: TextButton,
	icon: StaticIcon.StaticIcon,
	price: TextLabel,
	coin: Frame,
	name: TextLabel, -- UI overhaul: painted for the card's face
	stroke: UIStroke, -- the outline (white when selected)
	accent: Theme.Accent, -- the box's colour
}

type Row = {
	root: Frame,
	icon: StaticIcon.StaticIcon,
	name: TextLabel,
	rarity: RarityTag.RarityTag,
	percent: TextLabel,
	owned: TextLabel,
	refund: TextLabel,
	inspect: Button.Button,
	squishyId: string?,
}

type Disclosure = {
	name: TextLabel,
	price: TextLabel,
	priceCoin: Frame, -- the coin beside a paid box's price
	summary: TextLabel,
	details: Button.Button,
	heading: TextLabel,
	rows: Frame,
	total: TextLabel,
	footer: TextLabel,
	confirm: ConfirmButton.ConfirmButton,
	retry: Button.Button,
	shop: Button.Button,
	howToEarn: Button.Button,
	note: TextLabel,
	status: TextLabel,
}

type RevealUi = {
	root: Frame,
	padding: UIPadding, -- the panel's (its top follows the header tab)
	tab: Frame, -- the header tab with the box name
	title: TextLabel,
	stageHolder: Frame,
	info: CanvasGroup,
	infoOffset: Frame,
	name: TextLabel,
	rarity: RarityTag.RarityTag,
	result: Chip.Chip,
	saving: TextLabel,
	skip: Button.Button,
	equip: Button.Button,
	inspect: Button.Button,
	another: Button.Button,
	close: Button.Button,
}

type QueueEntry = { reveal: BoxFormat.Reveal, source: "reply" | "unseen" | "preview", savePending: boolean }

type LidPart = { mesh: DataModelMesh, base: Vector3, up: Vector3 }
type FadePart = { part: BasePart, base: number }
type ScalePart = {
	part: BasePart,
	rel: CFrame,
	size: Vector3,
	mesh: DataModelMesh?,
	meshOffset: Vector3,
	meshScale: Vector3,
	fileMesh: boolean,
}

type Run = {
	entry: QueueEntry,
	rarity: string,
	reduced: boolean,
	elapsed: number, -- ms since the reveal started
	cues: { BoxFormat.SoundCue },
	cueIndex: number,
	revealSoundPlayed: boolean,
	stage: ViewportStage.Stage,
	cleanup: Cleanup.Cleanup,
	gift: Model?,
	giftDeformer: any,
	giftParts: { FadePart },
	lidParts: { LidPart },
	squishy: Model,
	squishyParts: { ScalePart },
	squishyRoot: BasePart?,
	squishyFade: { FadePart },
	life: IdleRig.IdleRig?, -- the squishy's rig, started when the rise ends (nil without a motion row)
	boxFraming: ViewportStage.Framing,
	squishyFraming: ViewportStage.Framing,
	spring: any,
	confetti: Confetti2D.Handle?,
	rays: { Frame },
	rayAngle: number,
	yaw: number,
	pitch: number,
	duckRelease: (() -> ())?,
	popped: boolean,
	swapped: boolean,
	revealed: boolean,
	highlighted: boolean,
	final: boolean,
	acked: boolean,
	done: boolean,
	equipped: boolean,
	popBack: (() -> ())?, -- while animating, Backspace / ButtonB skip instead of closing (UIController.pushBack)
}

-- Constants

local SCREEN = "boxes"
local REVEAL_SCREEN = "boxReveal"
local SHOP_SCREEN = "shop"
local INSPECT_SCREEN = "inspect"
local MODAL_GUI = "SD_Modal"
local STAND_TAG = "SD_BoxStand"
local ATTR_BOX_ID = WorldLayout.Attributes.BoxId
local ATTR_TEXT_KEY = "SD_TextKey"
local ATTR_ALT_TEXT_KEY = "SD_AltTextKey"
local ATTR_GROUP = "SD_Group"
local ODDS_BOARD_PART = "OddsBoard"
local BOARD_LINE = "Body"
local BOARD_TITLE = "Title"
local SHOP_PROMPT_KEY = "prompt.shopDirect"
local SQUEEZE_WAYPOINT = "squeeze"
local GIFT_BOX = "gift_box"
local LID_GROUP = "lid"
local HANDOFF_REASON = "inspect"
local INSPECT_SOURCE = "boxReveal"
local EQUIPPED_TOAST = "inspect.equippedToast"
local GENERIC = "error.generic"
local POLICY_UNKNOWN = "unknown"
local ROOT_PART = "HumanoidRootPart"
local REVEAL = Config.Anim.boxReveal
local MOTION = Config.UI.motion
local TOUCH = Config.UI.Touch
local FLIGHT = MOTION.coinFlight
local RETRY_SECONDS = Config.Monetization.Policy.manualRetryMinSeconds
local STILL_CHECKING_SECONDS = Config.UI.Boxes.stillCheckingSeconds
local SPINNER_DELAY_SECONDS = MOTION.loadingSpinnerDelayMs / 1000
-- Layout (reading: DESIGN gives the content, not these sizes; base px under the ScreenGui UIScale).
local LIST_SHARE = 0.3
local CARD_HEIGHT = 120
local CARD_ICON_PX = 76 -- UI overhaul: 64 -> 76, a bigger gift
local CARD_RADIUS = Theme.Radius.button
local CARD_BANDS = Theme.Foam.panel.bevel + Theme.Foam.panel.drop -- the foam card's bevel and drop (kept free)
local COIN_PX = 20
local PRICE_COIN_PX = 26
local ROW_ICON_PX = 48
-- The name / rarity / refund column; the chance column takes the rest (fix batch: 0.55, was 0.6, so the percent and
-- Inspect fit side by side).
local ROW_INFO_SHARE = 0.55
local MARGIN_PX = 24
local MAX_HEIGHT_SHARE = 0.88
local SCROLLBAR_PX = 6
local CLOSE_INSET = 16 -- fix batch: Close sits this far from the panel's right edge (as on Quests and Settings)
local TAB_KIND: Theme.TextKind = "H2" -- the header tab's gap under it: InventoryFormat.PANEL.tabGap (hangingChrome)
-- Foam restyle: the selected box card's face, a light Lilac (the Boxes tile's colour).
local ROW_FILL = Theme.Colors.panelAlt -- an item row on the inset field
-- UI overhaul: each box's colour (selector card) and its gift's tint (the gift_box model is pink and mint); an
-- unselected box's face goes `unselectedDim` towards the window; the selected one has a white `selectedFramePx`
-- frame. One table: this module's top level is at Luau's 200-local limit.
local BOX_LOOK = {
	accents = { snack = "strawberry", sweet = "lilac", treat = "gold" } :: { [string]: Theme.AccentName },
	tints = {
		snack = Color3.new(1, 1, 1),
		sweet = Color3.fromHex("#D9C6FF"),
		treat = Color3.fromHex("#FFE6A6"),
	} :: { [string]: Color3 },
	unselectedDim = 0.35,
	selectedFramePx = 4,
	-- The reveal's escalation (see the header).
	fx = require(Client.UI.UiFx),
	revealTiers = { Common = "small", Uncommon = "medium", Epic = "large", Exclusive = "huge" } :: { [string]: string },
	revealShake = { Epic = 0.3, Exclusive = 0.55 } :: { [string]: number },
	infoStaggerMs = 90,
}
local REVEAL_PANEL = BoxFormat.REVEAL_PANEL
local REVEAL_WIDTH = REVEAL_PANEL.width
local STAGE_HEIGHT = REVEAL_PANEL.stage
-- The reveal (reading: §9.11 names the moves, not these distances; studs at gift-box scale 1).
local POP_LIFT_STUDS = 1.4 -- the lid rises this far by the end of the pop
local START_DROP_STUDS = 0.35 -- the squishy starts this far below its rest pivot (inside the box)
local SINK_STUDS = 2.5 -- the box sinks this far while it fades
local GLOW_NEUTRAL_MAX = 0.3 -- the neutral anticipation glow (never rarity-tinted), under glowMaxOpacity
local TINT_MAX = 0.35 -- the background gradient's shift toward the rarity colour
local RAY_DEG_PER_SECOND = 12 -- "slow" light rays (one turn in 30 s)
local RAY_WIDTH_SCALE = 0.07
local RAY_LENGTH_SCALE = 1.6
local RAY_TRANSPARENCY = 0.72
local INFO_SLIDE_PX = 12
local INFO_FADE_MS = 220
local WAIT_WOBBLE_DEG = 4
local WAIT_WOBBLE_HZ = 1.2
local WAYPOINT_MAX_SECONDS = 120
local WAYPOINT_CHECK_SECONDS = 0.5
local WORLD_REFRESH_SECONDS = 1
local TICK_SECONDS = 1 -- the open area's countdowns (Try again)
local DEBUG_PRESS_GAP = ConfirmButton.GUARD_SECONDS + 0.05

-- Module table

local BoxController = {}

-- Private

local log = Log.new("Boxes")
local cleanup: Cleanup.Cleanup? = nil
local openCleanup: Cleanup.Cleanup? = nil
local panel: Frame? = nil
local loadingLabel: TextLabel? = nil
local body: Frame? = nil
local cards: { [string]: Card } = {}
local rows: { Row } = {}
local disclosure: Disclosure? = nil
local revealUi: RevealUi? = nil
local resultShownAt: number? = nil -- os.clock() when the result buttons last appeared (BoxFormat.resultInputOpen)
local selectedBox: string = "snack"
local detailsOpen = false
local headingHidden = false -- fix round 2: the disclosure's box name and price are see-through while the reveal shows
local retryAt: number? = nil -- os.clock() of the last Try again
local unknownAt: number? = nil -- os.clock() when the policy state last became "unknown" (BoxFormat.retryWait)
local statusText: string? = nil
local statusRequest: string? = nil
local opening: { boxId: string, requestId: string }? = nil
local waitWobble: Scheduler.Handle? = nil
local pendingIds: { [string]: string } = {} -- boxId -> requestId to reuse on the next press
local inFlight: { [string]: boolean } = {}
local played: { [string]: boolean } = {}
local queuedIds: { [string]: boolean } = {}
local queue: { QueueEntry } = {}
local holdReveals = false
local current: Run? = nil
local starting: QueueEntry? = nil
local waypoint: Waypoint.Handle? = nil
local lastResult: { [string]: any }? = nil

-- Runs `fn` in pcall; a failure is logged under `label`. Returns whether it ran without an error.
local function guarded(label: string, fn: () -> ()): boolean
	local ok, err = pcall(function(): any
		fn()
		return nil
	end)
	if not ok then
		log:error(`{label} failed:`, err)
	end
	return ok
end

-- A header tab's height (base px) at the player's text size: its title's line and its padding (Theme.headerTab's foam
-- bands included).
local function tabHeight(tab: Frame): number
	local tabPad = tab:FindFirstChildOfClass("UIPadding")
	local padY = if tabPad then tabPad.PaddingTop.Offset + tabPad.PaddingBottom.Offset else 0
	return math.ceil(Theme.lineHeight(TAB_KIND)) + padY
end

-- The header tab at the player's text size (foam restyle) and, on the Boxes panel, the Close button hanging on the
-- top-right corner level with it (fix batch; InventoryFormat.hangingChrome): the panel's top padding keeps the tab gap
-- under their lower halves, the tab stays centred on the panel's top edge, and the panel (anchored at its centre) moves
-- down by half of what hangs above it, so the panel and what hangs above it are centred together.
local function fitTab(root: GuiObject, tab: Frame, padding: UIPadding, minPadding: number, close: GuiObject?)
	local closeHeight = if close then Layout.touchBase(TOUCH.closeButton, UIController.scale()) else 0
	local chrome = InventoryFormat.hangingChrome(tabHeight(tab), closeHeight, minPadding)
	padding.PaddingTop = UDim.new(0, chrome.top)
	tab.Position = UDim2.new(0.5, 0, 0, -chrome.top)
	if close then
		close.Position = UDim2.new(1, padding.PaddingRight.Offset - CLOSE_INSET, 0, -chrome.top)
	end
	root.Position = UDim2.new(0.5, 0, 0.5, chrome.shift)
end

local function firstPaidBox(): string
	for _, box in Boxes.list() do
		if box.paid then
			return box.id
		end
	end
	return Boxes.List[1].id
end

local function validBox(id: unknown): string?
	if type(id) == "string" and Boxes.get(id) ~= nil then
		return id
	end
	return nil
end

local function standBoxId(stand: Instance): string
	return validBox(stand:GetAttribute(ATTR_BOX_ID)) or firstPaidBox()
end

local function retryWait(): number
	return BoxFormat.retryWait(os.clock(), retryAt, unknownAt, RETRY_SECONDS)
end

local function coins(): number
	return StateController.coins() or 0
end

local function currentView(): BoxFormat.OpenView
	local status = StateController.dataStatus()
	local d = disclosure
	return BoxFormat.openView({
		box = selectedBox,
		policy = StateController.get("policy"),
		coins = StateController.coins(),
		owned = StateController.owned(),
		savePending = status ~= nil and status.savePending,
		inLobby = not StateController.isLobbyLocked(),
		profileReady = StateController.isProfileReady(),
		armed = d ~= nil and d.confirm:getState().phase == "armed",
		retryWaitSeconds = retryWait(),
	})
end

local function clearWaypoint()
	if waypoint then
		waypoint:destroy()
		waypoint = nil
	end
end

local function rootPosition(): Vector3?
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild(ROOT_PART) else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- "How to earn Coins": a waypoint to the nearest Squeeze mat, removed once reached, after WAYPOINT_MAX_SECONDS or when a
-- match starts.
local function showEarnWaypoint()
	clearWaypoint()
	local target = WorldLayout.waypoint(SQUEEZE_WAYPOINT)
	if target == nil then
		return
	end
	local handle = Waypoint.show(target)
	waypoint = handle
	local startedAt = os.clock()
	task.spawn(function()
		while waypoint == handle do
			task.wait(WAYPOINT_CHECK_SECONDS)
			if waypoint ~= handle then
				return
			end
			local position = rootPosition()
			if
				(position and Waypoint.shouldHide(position, target))
				or os.clock() - startedAt > WAYPOINT_MAX_SECONDS
			then
				clearWaypoint()
			end
		end
	end)
end

-- The Boxes screen ----------------------------------------------------------------------------------------------------

local function setStatus(text: string?, requestId: string?)
	statusText = text
	statusRequest = requestId
end

local function refreshOpenArea()
	local d = disclosure
	if d == nil then
		return
	end
	local view = currentView()
	local confirm = d.confirm
	confirm.root.Visible = view.button == "confirm"
	d.retry.root.Visible = view.button == "retry"
	d.shop.root.Visible = view.button == "shop"
	d.howToEarn.root.Visible = view.howToEarn
	if view.button == "confirm" then
		confirm:setPrice(view.price, coins())
		if view.kind == "checking" then
			confirm:setText(view.text)
		else
			confirm:setText(Strings.format(Strings.box.openButton, { cost = Format.coins(view.price) }))
		end
		-- Not enough Coins: the ConfirmButton disables itself from the price and balance (with box.needCoins).
		if view.enabled or view.kind == "needCoins" then
			confirm:setDisabled(nil)
		else
			confirm:setDisabled(view.reason or "")
		end
	elseif view.button == "retry" then
		d.retry:setText(view.text)
		d.retry:setState(if view.enabled then "normal" else "disabled", view.reason)
	elseif view.button == "shop" then
		d.shop:setText(view.text)
	end
	local note = if view.kind == "freeOnly" then view.text elseif view.kind == "confirm" then nil else view.note
	d.note.Text = note or ""
	d.note.Visible = note ~= nil
	d.status.Text = statusText or ""
	d.status.Visible = statusText ~= nil
end

local function refreshRows()
	local d = disclosure
	if d == nil then
		return
	end
	local list = BoxFormat.oddsRows(selectedBox, StateController.owned())
	local inspectable = UIController.isRegistered(INSPECT_SCREEN)
	for index, row in rows do
		local data = list[index]
		row.root.Visible = data ~= nil
		if data then
			row.squishyId = data.id
			row.icon:setSquishy(data.id)
			row.name.Text = data.name
			row.rarity:setRarity(data.rarity)
			row.percent.Text = data.percentText
			-- UI overhaul: the row is tinted by its rarity and the chance is in the rarity's glow, for a quick scan (the
			-- rarity tag still names it).
			local style = RarityStyle.get(data.rarity)
			row.root.BackgroundColor3 = if style then ROW_FILL:Lerp(style.color, 0.16) else ROW_FILL
			row.percent.TextColor3 = if style then style.ui.glow else Theme.Colors.text
			row.owned.Text = data.ownedText or ""
			row.owned.Visible = data.ownedText ~= nil
			row.refund.Text = data.refundText
			row.inspect.root.Visible = inspectable and data.inspect
		else
			row.squishyId = nil
		end
	end
end

local function refresh()
	local root = panel
	if root == nil then
		return
	end
	local loaded = StateController.isLoaded()
	if loadingLabel then
		loadingLabel.Visible = not loaded
	end
	if body then
		body.Visible = loaded
	end
	for id, card in cards do
		-- UI overhaul: the selected box is its full colour with a white frame, the others dimmed; texts follow the face.
		local isSelected = id == selectedBox
		local face = if isSelected
			then card.accent.face
			else card.accent.face:Lerp(Theme.Colors.panel, BOX_LOOK.unselectedDim)
		card.root.BackgroundColor3 = face
		card.stroke.Color = if isSelected then Theme.Colors.white else Theme.Colors.inkUI
		card.stroke.Thickness = if isSelected then BOX_LOOK.selectedFramePx else Theme.Stroke.ink
		-- Fewer words: a paid box's cost as the coin and a bare number; the Treat Box's box.freeOnly note.
		local cost = BoxFormat.costText(id)
		card.price.Text = cost or BoxFormat.priceText(id)
		card.coin.Visible = cost ~= nil
		for _, text in { card.name, card.price } do
			if card.accent.light and isSelected then
				Theme.textOnLight(text)
			else
				Theme.textOnColor(text, nil, face)
			end
		end
	end
	local d = disclosure
	if d == nil then
		return
	end
	d.name.Text = BoxFormat.boxName(selectedBox)
	local cost = BoxFormat.costText(selectedBox)
	d.price.Text = cost or BoxFormat.priceText(selectedBox)
	d.priceCoin.Visible = cost ~= nil and not headingHidden
	-- The cost as a big number; the free box's note as body text.
	if cost then
		Theme.text(d.price, "HudNumber")
	else
		Theme.text(d.price, "Body", Enum.FontWeight.Bold)
	end
	d.price.TextWrapped = false -- one line beside the coin (it sizes itself)
	-- Fix round 2: while the reveal shows over this panel, its box name and price are see-through, keeping their room
	-- (nothing below moves): the reveal's tab names the box, and its top edge cut through them.
	d.name.TextTransparency = if headingHidden then 1 else 0
	d.price.TextTransparency = if headingHidden then 1 else 0
	d.summary.Text = BoxFormat.raritySummary(selectedBox)
	d.total.Text = BoxFormat.totalText(selectedBox)
	local compact = UIController.layoutClass() == "compact"
	local showList = not compact or detailsOpen
	d.details.root.Visible = compact
	d.heading.Visible = showList
	d.rows.Visible = showList
	d.total.Visible = showList
	refreshRows()
	refreshOpenArea()
end

local function selectBox(id: string)
	if id == selectedBox then
		return
	end
	selectedBox = id
	local d = disclosure
	if d then
		d.confirm:reset()
	end
	if statusRequest == nil or pendingIds[id] ~= statusRequest then
		setStatus(nil, nil)
	end
	refresh()
end

local function cycleBox(direction: number)
	local list = Boxes.list()
	local index = 1
	for i, box in list do
		if box.id == selectedBox then
			index = i
		end
	end
	local nextIndex = (index - 1 + direction) % #list + 1
	selectBox(list[nextIndex].id)
end

local function stopWaitWobble()
	if waitWobble then
		waitWobble:disconnect()
		waitWobble = nil
	end
	for _, card in cards do
		card.icon.root.Rotation = 0
	end
end

-- §9.11 "Request": the selected card's gift box wobbles gently while the reply is on its way (not under ReducedMotion).
local function startWaitWobble(boxId: string)
	stopWaitWobble()
	local card = cards[boxId]
	if card == nil or Tweens.reducedMotion() then
		return
	end
	local icon = card.icon.root
	local elapsed = 0
	waitWobble = Scheduler.add(function(dt: number): boolean
		elapsed += dt
		icon.Rotation = WAIT_WOBBLE_DEG * math.sin(2 * math.pi * WAIT_WOBBLE_HZ * elapsed)
		return true
	end, "render")
end

-- Reveals ------------------------------------------------------------------------------------------------------------

local pump: () -> ()

local function enqueue(entry: QueueEntry, front: boolean)
	local id = entry.reveal.requestId
	if queuedIds[id] or played[id] then
		return
	end
	queuedIds[id] = true
	if front then
		table.insert(queue, 1, entry)
	else
		table.insert(queue, entry)
	end
end

-- Queues every unseen reveal that is not in flight, not played this session and not queued yet (§3.11 replay).
local function scanUnseen()
	local list = BoxFormat.pendingReveals(StateController.get("unseenReveals"), function(id: string): boolean
		return inFlight[id] == true or played[id] == true or queuedIds[id] == true
	end)
	for _, reveal in list do
		enqueue({ reveal = reveal, source = "unseen", savePending = false }, false)
	end
	pump()
end

-- Every part's rest values, for the squishy's uniform scale (0.3 -> 1) and fade; exact at k = 1 (Inspect takes it).
local function captureScale(model: Model): ({ ScalePart }, BasePart?, { FadePart })
	local pivot = model:GetPivot()
	local primary = model.PrimaryPart
	local parts: { ScalePart } = {}
	local fade: { FadePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= primary then
			local part = descendant :: BasePart
			local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
			local fileMesh = mesh ~= nil
				and mesh:IsA("SpecialMesh")
				and (mesh :: SpecialMesh).MeshType == Enum.MeshType.FileMesh
			table.insert(parts, {
				part = part,
				rel = pivot:ToObjectSpace(part.CFrame),
				size = part.Size,
				mesh = mesh,
				meshOffset = if mesh then mesh.Offset else Vector3.zero,
				meshScale = if mesh then mesh.Scale else Vector3.one,
				fileMesh = fileMesh,
			})
			table.insert(fade, { part = part, base = part.Transparency })
		end
	end
	return parts, primary, fade
end

-- Writes the squishy at uniform scale `k` with its pivot at `pivot` (k = 1 at the identity pivot = the rest pose).
local function writeScale(run: Run, k: number, pivot: CFrame)
	for _, data in run.squishyParts do
		data.part.Size = data.size * k
		data.part.CFrame = pivot * CFrame.new(data.rel.Position * k) * data.rel.Rotation
		local mesh = data.mesh
		if mesh then
			mesh.Offset = data.meshOffset * k
			if data.fileMesh then
				mesh.Scale = data.meshScale * k
			end
		end
	end
	local root = run.squishyRoot
	if root then
		root.CFrame = pivot
	end
end

local function writeFade(list: { FadePart }, alpha: number)
	for _, data in list do
		data.part.Transparency = data.base + (1 - data.base) * math.clamp(alpha, 0, 1)
	end
end

local function blendFraming(a: ViewportStage.Framing, b: ViewportStage.Framing, u: number): ViewportStage.Framing
	local t = math.clamp(u, 0, 1)
	return {
		center = a.center:Lerp(b.center, t),
		size = a.size:Lerp(b.size, t),
		radius = a.radius + (b.radius - a.radius) * t,
		pivotRotation = b.pivotRotation,
	}
end

local function rarityColor(rarity: string): Color3
	local style = RarityStyle.get(rarity)
	return if style then style.color else Theme.Colors.cream
end

-- Seen: AckReveal once, and StateController shows the result it held back until now (the refund in the Coins pill, the
-- new squishy in owned and as NEW; reveal holds, Part 7 review fix).
local function ack(run: Run)
	if run.acked then
		return
	end
	run.acked = true
	if run.entry.source == "preview" then
		return -- a Studio preview: no remote, nothing held
	end
	local requestId = run.entry.reveal.requestId
	NetController.fire("AckReveal", requestId)
	StateController.releaseReveal(requestId)
end

-- Ends what the animation holds: the music duck (§11.9) and the back handler (Back skips while animating).
local function releaseHolds(run: Run)
	local release = run.duckRelease
	if release then
		run.duckRelease = nil
		release()
	end
	local popBack = run.popBack
	if popBack then
		run.popBack = nil
		popBack()
	end
end

local function destroyGift(run: Run)
	local deformer = run.giftDeformer
	if deformer then
		run.giftDeformer = nil
		deformer:destroy()
	end
	local gift = run.gift
	if gift then
		run.gift = nil
		if run.stage:model() == gift then
			local taken = run.stage:takeModel()
			if taken then
				taken:Destroy()
			end
		else
			run.stage:removeProp(gift, true)
		end
	end
end

-- The rest of the timeline: the squishy becomes the stage's model.
local function swapIn(run: Run)
	if run.swapped then
		return
	end
	run.swapped = true
	local gift = run.gift
	if gift and run.stage:model() == gift then
		run.stage:takeModel()
		run.stage:addProp(gift)
	end
	run.stage:setModel(run.squishy)
	run.stage:setFraming(run.boxFraming)
end

local function ensurePop(run: Run)
	if run.popped then
		return
	end
	run.popped = true
	local deformer = run.giftDeformer
	if deformer then
		run.giftDeformer = nil
		deformer:destroy() -- writes the rest pose once
	end
	local gift = run.gift
	if gift then
		gift:PivotTo(CFrame.identity)
	end
	run.stage:setShadowWiden(1)
	if not run.reduced then
		-- The same party colours for every result (no rarity hint before the reveal, §9.11 "no fake-outs").
		run.confetti = Confetti2D.play(
			run.stage.front,
			run.stage.root,
			REVEAL.popConfettiDots,
			Confetti2D.WIN_COLORS,
			UIController.scale()
		)
	end
	-- UI overhaul: the pop's neutral burst (white and cream for every result).
	BOX_LOOK.fx.burst(run.stage.root, "small", nil, { neutral = true })
end

-- The rarity highlight's entry (§9.11): the rarity colour on the frame, the label + pips + "NEW!" sliding in (shown at
-- once when `instant`, e.g. a skip), the light rays (not under ReducedMotion).
local function ensureHighlight(run: Run, instant: boolean)
	if run.highlighted then
		return
	end
	run.highlighted = true
	run.stage:setRarity(run.rarity)
	local ui = revealUi
	if ui then
		local def = Catalog.get(run.entry.reveal.squishyId)
		ui.name.Text = if def then KeyText.get(def.nameKey) else run.entry.reveal.squishyId
		ui.rarity:setRarity(run.rarity)
		-- "NEW!" on Strawberry (outlined white), a duplicate's refund on Frosting.
		ui.result:setText(BoxFormat.resultText(run.entry.reveal.isDuplicate, run.entry.reveal.refund))
		ui.result:setAccent(if run.entry.reveal.isDuplicate then "frosting" else "strawberry")
		ui.info.Visible = true
		if instant then
			ui.infoOffset.Position = UDim2.new()
			ui.info.GroupTransparency = 0
		elseif run.reduced then
			ui.infoOffset.Position = UDim2.new()
			Tweens.fade(ui.info, { GroupTransparency = 0 }, INFO_FADE_MS)
		else
			ui.info.GroupTransparency = 1
			ui.infoOffset.Position = UDim2.fromOffset(0, INFO_SLIDE_PX)
			Tweens.play(ui.infoOffset, INFO_FADE_MS, { Position = UDim2.new() })
			Tweens.fade(ui.info, { GroupTransparency = 0 }, INFO_FADE_MS)
			-- UI overhaul: the name, the rarity and the result arrive one after another ("NEW!" the biggest).
			local isNew = not run.entry.reveal.isDuplicate
			local sequence: { { object: GuiObject, peak: number } } = {
				{ object = ui.name, peak = 1.12 },
				{ object = ui.rarity.root, peak = 1.1 },
				{ object = ui.result.root, peak = if isNew then 1.22 else 1.08 },
			}
			for index, step in sequence do
				task.delay((index - 1) * BOX_LOOK.infoStaggerMs / 1000, function()
					if not run.done and step.object.Parent ~= nil then
						BOX_LOOK.fx.punch(step.object, step.peak)
					end
				end)
			end
		end
		-- UI overhaul: the reveal's burst in the rarity's colour, its tier growing with the rarity; a brief shake of the
		-- panel for the top rarities.
		local style = RarityStyle.get(run.rarity)
		local tier = BOX_LOOK.revealTiers[run.rarity] or "small"
		BOX_LOOK.fx.burst(run.stage.root, tier :: any, if style then style.ui.glow else nil)
		local trauma = BOX_LOOK.revealShake[run.rarity]
		if trauma and not instant then
			BOX_LOOK.fx.shake(ui.root, trauma)
		end
	end
	if not run.reduced then
		local color = rarityColor(run.rarity)
		for i = 1, REVEAL.lightRayFrames do
			local ray: Frame = Create("Frame", {
				Name = "Ray" .. i,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(RAY_WIDTH_SCALE, RAY_LENGTH_SCALE),
				BackgroundColor3 = color,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Rotation = (i - 1) * 180 / REVEAL.lightRayFrames,
				Parent = run.stage.back,
			})
			Create("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = ray,
			})
			table.insert(run.rays, ray)
		end
	end
end

local function applyRays(run: Run, dt: number, opacityShare: number)
	if #run.rays == 0 then
		return
	end
	run.rayAngle = (run.rayAngle + RAY_DEG_PER_SECOND * dt) % 360
	local transparency = 1 - (1 - RAY_TRANSPARENCY) * math.clamp(opacityShare, 0, 1)
	for i, ray in run.rays do
		ray.Rotation = run.rayAngle + (i - 1) * 180 / #run.rays
		ray.BackgroundTransparency = transparency
	end
end

local function showResultButtons(run: Run)
	local ui = revealUi
	if ui == nil then
		return
	end
	local reveal = run.entry.reveal
	local box = Boxes.get(reveal.boxId)
	local preview = run.entry.source == "preview" -- nothing was granted: no Equip, no Open another
	ui.skip.root.Visible = false
	ui.equip.root.Visible = not reveal.isDuplicate and not preview
	if not reveal.isDuplicate then
		ui.equip:setText(if run.equipped then Strings.common.equipped else Strings.common.equip)
		ui.equip:setState(if run.equipped then "disabled" else "normal")
	end
	ui.inspect.root.Visible = UIController.isRegistered(INSPECT_SCREEN)
	ui.another.root.Visible = box ~= nil and box.paid and not preview
	ui.close.root.Visible = true
	resultShownAt = os.clock()
	Focus.select(if ui.equip.root.Visible then ui.equip.root else ui.close.root)
end

-- The result buttons sit where Skip was: a press within resultInputGuardMs of their appearing is the skip's own press
-- (or a quick second tap) and is ignored (Part 8 acceptance fix).
local function resultInputOpen(): boolean
	return BoxFormat.resultInputOpen(resultShownAt, os.clock(), REVEAL.resultInputGuardMs)
end

-- Jumps to (or arrives at) the final state with the identical result; sends AckReveal once. `mode`: "natural" (the
-- timeline reached its result), "skip" (Skip, a tap, ButtonA) or "close" (the screen is closing: no visuals, no sound).
local function finalize(run: Run, mode: "natural" | "skip" | "close")
	if run.final then
		return
	end
	if mode == "close" then
		run.final = true
		run.cueIndex = #run.cues + 1
		releaseHolds(run)
		ack(run)
		return
	end
	local skipped = mode == "skip"
	if skipped and not run.revealSoundPlayed then
		SoundController.play(BoxFormat.revealSoundKey(run.rarity), { variance = 0 })
		run.revealSoundPlayed = true
	end
	run.cueIndex = #run.cues + 1
	ensurePop(run)
	local confetti = run.confetti
	if confetti and skipped then
		confetti:stop()
		run.confetti = nil
	end
	swapIn(run)
	destroyGift(run)
	local life = run.life
	if not (life and life:isStarted()) then
		writeScale(run, 1, CFrame.identity)
		writeFade(run.squishyFade, 0)
	end
	if life then
		life:start(IdleRig.REVEAL_WOW_SECONDS) -- the rise is over: the rig's first write (§3.2)
	end
	run.revealed = true
	ensureHighlight(run, skipped)
	run.stage:setFraming(run.squishyFraming)
	run.stage:setView(run.yaw, run.pitch, 1)
	run.stage:setGlow(rarityColor(run.rarity), REVEAL.glowMaxOpacity)
	run.stage:setTint(rarityColor(run.rarity), TINT_MAX)
	applyRays(run, 0, 1)
	local ui = revealUi
	run.final = true
	releaseHolds(run)
	showResultButtons(run)
	local reveal = run.entry.reveal
	if reveal.isDuplicate and reveal.refund >= FLIGHT.minAmount and ui then
		HudController.flyCoins(ui.result.root, reveal.refund)
	end
	-- After the flight starts: the refund the hold kept off the pill then lands with the coins (no second "+N").
	ack(run)
end

local function stepRun(run: Run, dt: number): boolean
	if run.done then
		return false
	end
	run.elapsed += dt * 1000
	local t = run.elapsed
	while run.cueIndex <= #run.cues and t >= run.cues[run.cueIndex].atMs do
		local cue = run.cues[run.cueIndex]
		run.cueIndex += 1
		SoundController.play(cue.key, { variance = cue.variance })
		if cue.key == BoxFormat.revealSoundKey(run.rarity) then
			run.revealSoundPlayed = true
		end
	end
	if run.final then
		if not run.reduced then
			run.yaw = (run.yaw + REVEAL.turntableDegPerSecond * dt) % 360
			run.stage:setView(run.yaw, run.pitch, 1)
		end
		applyRays(run, dt, 1)
		local life = run.life
		if life then
			debug.profilebegin("SD_Rigs") -- rig stepping and writes (spec §5); a literal: no room for a top-level local
			life:step(dt) -- breathing and blink through the result
			debug.profileend()
		end
		return true
	end
	local phase, u = BoxFormat.revealPhase(t, run.reduced)
	if phase == "anticipation" then
		local c, hop = BoxFormat.wobble(t, run.reduced)
		local deformer = run.giftDeformer
		if deformer then
			deformer:setScale(SquishDeformer.axisScale(c, 1 / math.sqrt(c), "Y"))
		end
		local gift = run.gift
		if gift then
			gift:PivotTo(CFrame.new(0, hop, 0))
		end
		run.stage:setShadowWiden(1 / math.sqrt(c))
		run.stage:setGlow(Theme.Colors.cream, GLOW_NEUTRAL_MAX * u)
	elseif phase == "pop" then
		ensurePop(run)
		if not run.reduced then
			local lift = POP_LIFT_STUDS * (1 - (1 - u) ^ 3)
			for _, lid in run.lidParts do
				lid.mesh.Offset = lid.base + lid.up * lift
			end
		end
		run.stage:setGlow(Theme.Colors.cream, GLOW_NEUTRAL_MAX)
	elseif phase == "reveal" then
		ensurePop(run)
		swapIn(run)
		local eased = 1 - (1 - u) ^ 2
		local gift = run.gift
		if gift then
			if not run.reduced then
				gift:PivotTo(CFrame.new(0, -SINK_STUDS * eased, 0)) -- under ReducedMotion it only fades (crossfade)
			end
			writeFade(run.giftParts, eased)
		end
		if run.reduced then
			-- The crossfade (§9.11 ReducedMotion): the squishy at rest fades in while the box fades out.
			writeScale(run, 1, CFrame.identity)
			writeFade(run.squishyFade, 1 - u)
			run.stage:setFraming(run.squishyFraming)
		else
			local k = run.spring:step(dt)
			local from = REVEAL.revealScaleFrom
			local rise = math.clamp((k - from) / (1 - from), 0, 1.2)
			writeScale(run, math.max(k, 0.05), CFrame.new(0, -START_DROP_STUDS * (1 - rise), 0))
			run.stage:setFraming(blendFraming(run.boxFraming, run.squishyFraming, eased))
		end
		run.stage:setView(run.yaw, run.pitch, 1)
	elseif phase == "highlight" then
		if not run.revealed then
			run.revealed = true
			destroyGift(run)
			writeScale(run, 1, CFrame.identity)
			writeFade(run.squishyFade, 0)
			run.stage:setFraming(run.squishyFraming)
			run.stage:setView(run.yaw, run.pitch, 1)
		end
		local life = run.life
		if life then
			life:start(IdleRig.REVEAL_WOW_SECONDS) -- once, after the writeScale(1) above: the rise is over (§3.2)
			debug.profilebegin("SD_Rigs")
			life:step(dt)
			debug.profileend()
		end
		ensureHighlight(run, false)
		local color = Theme.Colors.cream:Lerp(rarityColor(run.rarity), u)
		run.stage:setGlow(color, GLOW_NEUTRAL_MAX + (REVEAL.glowMaxOpacity - GLOW_NEUTRAL_MAX) * u)
		run.stage:setTint(rarityColor(run.rarity), TINT_MAX * u)
		applyRays(run, dt, u)
	else
		finalize(run, "natural")
	end
	return true
end

-- Builds the run's models on the stage (the gift box as the stage's model, the squishy ready at its start pose).
local function newRun(entry: QueueEntry, stage: ViewportStage.Stage): Run?
	local reveal = entry.reveal
	local def = Catalog.get(reveal.squishyId)
	if def == nil then
		return nil
	end
	local reduced = Tweens.reducedMotion()
	local c = Cleanup.new()
	local gift = SquishyCache.clone(GIFT_BOX, "Viewport", 1)
	local giftParts: { FadePart } = {}
	local lidParts: { LidPart } = {}
	for _, descendant in gift:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= gift.PrimaryPart then
			local part = descendant :: BasePart
			table.insert(giftParts, { part = part, base = part.Transparency })
			local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
			if mesh and part:GetAttribute(ATTR_GROUP) == LID_GROUP then
				-- Reading (§13.5: SpecialMesh.Offset is in part space, a play-check): the model's up in the part's space.
				table.insert(
					lidParts,
					{ mesh = mesh, base = mesh.Offset, up = part.CFrame:VectorToObjectSpace(Vector3.yAxis) }
				)
			end
		end
	end
	stage:clearModel()
	stage:clearLayers()
	stage:resetLook()
	local boxFraming = stage:setModel(gift)
	local squishy = SquishyCache.clone(reveal.squishyId, "Viewport", 1)
	local squishyFraming = ViewportStage.framingOf(squishy)
	local scaleParts, squishyRoot, squishyFade = captureScale(squishy)
	local yaw = def.inspect.yaw
	local pitch = def.inspect.pitch
	local run: Run = {
		entry = entry,
		rarity = def.rarity,
		reduced = reduced,
		elapsed = 0,
		cues = BoxFormat.soundCues(def.rarity, reduced),
		cueIndex = 1,
		revealSoundPlayed = false,
		stage = stage,
		cleanup = c,
		gift = gift,
		giftDeformer = if reduced then nil else SquishDeformer.attach(gift),
		giftParts = giftParts,
		lidParts = lidParts,
		squishy = squishy,
		squishyParts = scaleParts,
		squishyRoot = squishyRoot,
		squishyFade = squishyFade,
		life = IdleRig.new(squishy, reveal.squishyId, { detail = "hero", twist = "pivot", reduced = reduced }),
		boxFraming = boxFraming,
		squishyFraming = squishyFraming,
		spring = Spring.new(REVEAL.revealScaleFrom, REVEAL.revealOmega, REVEAL.revealZeta, 1),
		confetti = nil,
		rays = {},
		rayAngle = 0,
		yaw = yaw,
		pitch = pitch,
		duckRelease = SoundController.duck("boxReveal"),
		popped = false,
		swapped = false,
		revealed = false,
		highlighted = false,
		final = false,
		acked = false,
		done = false,
		equipped = false,
		popBack = nil,
	}
	-- The squishy waits inside the box: at its start scale and pose, or invisible for the crossfade.
	if reduced then
		writeScale(run, 1, CFrame.identity)
		writeFade(squishyFade, 1)
	else
		writeScale(run, REVEAL.revealScaleFrom, CFrame.new(0, -START_DROP_STUDS, 0))
	end
	stage:setView(yaw, pitch, 1)
	return run
end

-- Ends a run: stops its effects and frees the stage (keeps the model when Inspect takes it over).
local function teardown(run: Run, handoff: boolean)
	run.done = true
	run.cleanup:clean()
	local confetti = run.confetti
	if confetti then
		confetti:stop()
		run.confetti = nil
	end
	releaseHolds(run)
	destroyGift(run)
	local stage = run.stage
	stage:clearLayers()
	table.clear(run.rays)
	local life = run.life
	run.life = nil
	if handoff then
		if life and life:isStarted() then
			-- One owner per rig (§3.2): Inspect steps it from now on and adopts the model with its deformer, and
			-- breathes on from the reveal's breath (no jump). Required here, not at the top: this module is at Luau's
			-- 200-locals limit.
			local breath, rising = life:breathNow()
			local rig = life:handOff()
			if rig then
				require(script.Parent.InspectController).takeRig(run.squishy, rig, breath, rising)
			end
		else
			writeScale(run, 1, CFrame.identity)
			writeFade(run.squishyFade, 0)
			if life then
				life:destroy()
			end
		end
		local model = stage:model()
		if model ~= run.squishy then
			stage:setModel(run.squishy)
		end
	else
		if life then
			life:destroy()
		end
		stage:clearModel()
		run.squishy:Destroy() -- also when it never entered the stage (closed before the reveal phase)
	end
	stage:resetLook()
	stage:detach()
end

-- Skip / a tap / ButtonA: the final state with the identical result. False when nothing is running or it is final.
local function skip(): boolean
	local run = current
	if run == nil or run.final then
		return false
	end
	finalize(run, "skip")
	return true
end

-- The reveal's stage height for this screen and text size (Part 8, BoxFormat.revealStageHeight): the rows of the
-- result state measured (every result button shown, the saving note reserved), so the panel never grows off screen.
local function revealStageHeight(): number
	local items: { Layout.WrapItem } = {}
	local buttonHeight = Layout.touchBase(Button.frameHeight("primary"), UIController.scale()) -- UI FINAL R2 (P1)
	for _, text in { Strings.common.equip, Strings.common.inspect, Strings.box.openAnother, Strings.common.close } do
		table.insert(items, { w = Button.widthFor(text), h = buttonHeight })
	end
	local inner = REVEAL_WIDTH - 2 * REVEAL_PANEL.padding
	local ui = revealUi
	local parts: BoxFormat.RevealParts = {
		title = if ui then tabHeight(ui.tab) else Theme.lineHeight(TAB_KIND), -- the whole header tab
		name = Theme.lineHeight("Title"),
		rarity = RarityTag.measure("Exclusive").inlineHeight,
		result = math.max(Chip.HEIGHT_PX, Theme.lineHeight("Button")), -- the result chip
		saving = Theme.textBounds(Strings.reasonText("box.saving"), "Small", nil, inner).Y,
		buttons = Layout.wrapRow(items, inner, REVEAL_PANEL.buttonGap).height,
	}
	local scale = math.max(UIController.scale(), 1e-3)
	local screenBaseHeight = UIController.screenGui(MODAL_GUI).AbsoluteSize.Y / scale
	return BoxFormat.revealStageHeight(screenBaseHeight, parts, UIController.layoutClass())
end

local function startRun(entry: QueueEntry): boolean
	local ui = revealUi
	if ui == nil then
		return false
	end
	local stage = ViewportStage.get()
	local ok, result = pcall(newRun, entry, stage)
	if not ok or result == nil then
		log:warn("reveal could not start:", if ok then "unknown squishy" else result)
		played[entry.reveal.requestId] = true -- not retried this session (it stays unseen for the next one)
		return false
	end
	local run = result :: Run
	current = run
	played[entry.reveal.requestId] = true
	if statusRequest == entry.reveal.requestId then
		setStatus(nil, nil)
		refreshOpenArea()
	end
	local box = Boxes.get(entry.reveal.boxId)
	ui.title.Text = if box then BoxFormat.boxName(box.id) else ""
	fitTab(ui.root, ui.tab, ui.padding, REVEAL_PANEL.padding) -- the tab at the player's current text size
	ui.info.Visible = false
	ui.info.GroupTransparency = 1
	ui.saving.Visible = entry.savePending
	ui.skip.root.Visible = true
	ui.equip.root.Visible = false
	ui.inspect.root.Visible = false
	ui.another.root.Visible = false
	ui.close.root.Visible = false
	ui.stageHolder.Size = UDim2.new(1, 0, 0, revealStageHeight())
	stage:attach(ui.stageHolder)
	Focus.select(ui.skip.root) -- ButtonA = Skip (§9.11)
	-- Reading: while the reveal animates, Backspace / ButtonB skip to the result (like Skip) instead of closing it
	-- unseen; at the result they close it as usual.
	run.popBack = UIController.pushBack(function()
		if current == run then
			skip()
		end
	end)
	-- A tap or click on the stage after skipTapAfterMs jumps to the final state (the holder listens too; a second call
	-- is a no-op once final).
	run.cleanup:add(stage.root.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) and current == run then
			if not run.final and run.elapsed >= REVEAL.skipTapAfterMs then
				skip()
			end
		end
	end))
	run.cleanup:add(Scheduler.add(function(dt: number): boolean
		local alive = true
		local ok = guarded("reveal step", function()
			alive = stepRun(run, dt)
		end)
		if not ok then
			guarded("reveal skip", function()
				finalize(run, "skip")
			end)
			ack(run)
			return false
		end
		return alive and not run.done
	end, "render"))
	return true
end

-- Plays the next queued reveal when nothing is playing, the lobby is free and the screen exists. Unseen reveals wait
-- while debugHoldReveals is on. Part 6: reveals also wait while Inspect is open (the two share the one viewport stage,
-- and a reveal opened over a lone Inspect would destroy its model); init pumps again when Inspect closes.
pump = function()
	if current ~= nil or starting ~= nil or StateController.isLobbyLocked() then
		return
	end
	if UIController.isOpen(INSPECT_SCREEN) then
		return
	end
	if not UIController.isRegistered(REVEAL_SCREEN) then
		return
	end
	local index: number? = nil
	for i, entry in queue do
		if not (holdReveals and entry.source == "unseen") then
			index = i
			break
		end
	end
	if index == nil then
		return
	end
	local entry = table.remove(queue, index) :: QueueEntry
	queuedIds[entry.reveal.requestId] = nil
	if played[entry.reveal.requestId] then
		pump()
		return
	end
	starting = entry
	local opened = UIController.open(REVEAL_SCREEN, { requestId = entry.reveal.requestId })
	starting = nil
	if not opened or current == nil then
		if current == nil then
			-- Refused (e.g. a match just started): back to the front of the queue.
			enqueue(entry, true)
		end
		return
	end
end

local function equipRevealed()
	local run = current
	local ui = revealUi
	if run == nil or ui == nil or run.equipped then
		return
	end
	ui.equip:setState("loading")
	local result = NetController.equipSquishyAsync(run.entry.reveal.squishyId)
	if current ~= run then
		return
	end
	if result.ok then
		run.equipped = true
		ui.equip:setText(Strings.common.equipped)
		ui.equip:setState("disabled")
		NotifyController.show(EQUIPPED_TOAST, nil, "success")
	else
		ui.equip:setState("normal")
		local reason = result.reason
		local known = type(reason) == "string" and reason ~= GENERIC and KeyText.has("reason." .. reason)
		UIController.toast(
			if known then Strings.reasonText(reason) else Strings.inspect.equipFailed,
			"warn",
			{ sound = "ui.error" }
		)
	end
end

-- The Open press --------------------------------------------------------------------------------------------------------

-- Sends BoxOpen for the selected box (the confirming press). Yields until the reply. Returns a summary for the debug
-- hooks: { ok, reason?, requestId?, squishyId? }.
local function openSelected(): { [string]: any }
	if opening ~= nil then
		return { ok = false, reason = "net.rateLimited" }
	end
	local boxId = selectedBox
	local view = currentView()
	if view.kind ~= "open" and view.kind ~= "confirm" then
		refresh()
		return { ok = false, reason = view.kind }
	end
	local requestId = pendingIds[boxId] or HttpService:GenerateGUID(false)
	pendingIds[boxId] = requestId
	inFlight[requestId] = true
	local attempt = { boxId = boxId, requestId = requestId }
	opening = attempt
	setStatus(nil, nil)
	refreshOpenArea()
	startWaitWobble(boxId)
	local spinner = task.delay(SPINNER_DELAY_SECONDS, function()
		local d = disclosure
		if opening == attempt and d then
			d.confirm:setLoading(true)
		end
	end)
	local still = task.delay(STILL_CHECKING_SECONDS, function()
		if opening == attempt then
			-- No reply yet: say so, and let the unseen reveals deliver the outcome (§11.6 "Timeout").
			inFlight[requestId] = nil
			setStatus(Strings.box.stillChecking, requestId)
			refreshOpenArea()
			scanUnseen()
		end
	end)

	local result = NetController.invokeAsync("BoxOpen", boxId, requestId)

	if coroutine.status(spinner) == "suspended" then
		task.cancel(spinner)
	end
	if coroutine.status(still) == "suspended" then
		task.cancel(still)
	end
	opening = nil
	stopWaitWobble()
	local d = disclosure
	if d then
		d.confirm:setLoading(false)
	end
	lastResult = { ok = result.ok, reason = result.reason, requestId = requestId, boxId = boxId }
	local summary: { [string]: any } = { ok = result.ok, reason = result.reason, requestId = requestId }
	if result.ok then
		pendingIds[boxId] = nil
		inFlight[requestId] = nil
		local data: { [string]: any } = if type(result.data) == "table" then result.data :: { [string]: any } else {}
		local squishyId = data.squishyId
		summary.squishyId = squishyId
		if Catalog.isValidId(squishyId) then
			local reveal: BoxFormat.Reveal = {
				requestId = requestId,
				boxId = boxId,
				squishyId = squishyId,
				isDuplicate = data.isDuplicate == true,
				refund = if type(data.refund) == "number" and data.refund == data.refund then data.refund else 0,
			}
			if statusRequest == requestId then
				setStatus(nil, nil)
			end
			enqueue({ reveal = reveal, source = "reply", savePending = data.savePending == true }, true)
		else
			log:warn("BoxOpen replied without a valid squishy; waiting for the unseen reveals")
			setStatus(Strings.box.stillChecking, requestId)
			scanUnseen()
		end
	else
		local reason = result.reason
		if reason == GENERIC then
			-- Maybe opened: the outcome comes from the unseen reveals; the next press reuses this requestId.
			inFlight[requestId] = nil
			setStatus(Strings.box.stillChecking, requestId)
			scanUnseen()
		elseif BoxFormat.isIndeterminate(reason) then
			-- Never reached the server (refused locally): nothing happened; the next press reuses the id.
			inFlight[requestId] = nil
			NotifyController.showResult(result, "warn")
		else
			pendingIds[boxId] = nil
			inFlight[requestId] = nil
			NotifyController.showResult(result, "warn")
		end
	end
	refresh()
	pump()
	return summary
end

-- Builders: the Boxes screen ---------------------------------------------------------------------------------------------

local function label(
	parent: Instance,
	name: string,
	order: number,
	kind: Theme.TextKind,
	weight: Enum.FontWeight?
): TextLabel
	return Theme.label({
		Name = name,
		LayoutOrder = order,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}, kind, weight)
end

local function buildCard(c: Cleanup.Cleanup, parent: Instance, box: Boxes.BoxDef, order: number)
	local accent = Theme.accent(BOX_LOOK.accents[box.id] or "lilac")
	local root: TextButton = Create("TextButton", {
		Name = "Boxes_Box_" .. box.id,
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = accent.face,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		LayoutOrder = order,
		Parent = parent,
	})
	c:add(root)
	-- A foam card in the box's colour (refresh dims it unless selected; the bevel and ink drop follow the face).
	local foam = Theme.foam(root, {
		radius = CARD_RADIUS,
		mode = "tint",
		bevel = Theme.Foam.panel.bevel,
		drop = Theme.Foam.panel.drop,
		colors = { face = accent.face, bevel = accent.shade, drop = Theme.Colors.inkUI },
	})
	Theme.rim(root, Theme.Colors.white, 0.7)
	Focus.decorate(root, CARD_RADIUS)
	c:add(Button.decorate(root))
	local pad = Theme.padding(Theme.Padding.small, root)
	pad.PaddingLeft = UDim.new(0, Theme.Padding.medium)
	pad.PaddingBottom = UDim.new(0, Theme.Padding.small + CARD_BANDS) -- the foam bands stay free
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.medium, root, Enum.HorizontalAlignment.Left)
	local icon = StaticIcon.new({
		name = "Preview",
		squishyId = GIFT_BOX,
		sizePx = CARD_ICON_PX,
		layoutOrder = 1,
		parent = root,
	})
	icon.root.ImageColor3 = BOX_LOOK.tints[box.id] or Color3.new(1, 1, 1) -- UI overhaul: each box its own gift
	c:add(icon)
	local text: Frame = Create("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(CARD_ICON_PX + Theme.Padding.medium), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Vertical, 2, text, Enum.HorizontalAlignment.Left)
	local name = label(text, "Name", 1, "Button")
	name.Text = BoxFormat.boxName(box.id)
	-- The cost: the coin and a bare number (a paid box), or box.freeOnly in Ink2 (the Treat Box); refresh keeps it.
	local cost = BoxFormat.costText(box.id)
	local priceRow: Frame = Create("Frame", {
		Name = "PriceRow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = text,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, priceRow, Enum.HorizontalAlignment.Left)
	local coin = CoinIcon.new({ name = "Coin", sizePx = COIN_PX, layoutOrder = 1, parent = priceRow })
	c:add(coin)
	coin.root.Visible = cost ~= nil
	local price = Theme.label({
		Name = "Price",
		Text = cost or BoxFormat.priceText(box.id),
		LayoutOrder = 2,
		Size = UDim2.new(1, -(COIN_PX + Theme.Padding.small), 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = priceRow,
	}, if cost then "Button" else "Small", nil, if cost then nil else Theme.Colors.ink2)
	c:add(root.Activated:Connect(function()
		selectBox(box.id)
	end))
	cards[box.id] = {
		id = box.id,
		root = root,
		icon = icon,
		price = price,
		coin = coin.root,
		name = name,
		stroke = foam.stroke :: UIStroke,
		accent = accent,
	}
end

local function buildRow(c: Cleanup.Cleanup, parent: Instance, index: number): Row
	local root: Frame = Create("Frame", {
		Name = "Boxes_Row_" .. index,
		BackgroundColor3 = ROW_FILL,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = index,
		Visible = false,
		Parent = parent,
	})
	Theme.corner(Theme.Radius.chip, root)
	Theme.padding(Theme.Padding.small, root)
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.medium, root, Enum.HorizontalAlignment.Left)
	local icon = StaticIcon.new({
		name = "Preview",
		squishyId = Catalog.starterId(),
		sizePx = ROW_ICON_PX,
		layoutOrder = 1,
		parent = root,
	})
	c:add(icon)
	local middle: Frame = Create("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Size = UDim2.new(ROW_INFO_SHARE, -ROW_ICON_PX, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Vertical, 2, middle, Enum.HorizontalAlignment.Left)
	local name = label(middle, "Name", 1, "Button")
	local rarity =
		RarityTag.new({ name = "Rarity", rarity = "Common", pipSizePx = 8, layoutOrder = 2, parent = middle })
	c:add(rarity)
	local refund = label(middle, "Refund", 3, "Small")
	refund.TextColor3 = Theme.Colors.ink2
	local right: Frame = Create("Frame", {
		Name = "Chance",
		BackgroundTransparency = 1,
		-- The two list gaps and a little slack, so the three columns never overflow the row's padded width.
		Size = UDim2.new(1 - ROW_INFO_SHARE, -(Theme.Padding.medium * 2 + Theme.Padding.large), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = root,
	})
	-- Fix batch: side by side, the percent and "Owned" on the left and Inspect on the right, centred, so every row has
	-- the same height; Inspect wraps under them only when the column is too narrow (a phone at a large text size).
	local chanceList = Theme.list(
		Enum.FillDirection.Horizontal,
		Theme.Padding.medium,
		right,
		Enum.HorizontalAlignment.Right,
		Enum.VerticalAlignment.Center
	)
	chanceList.Wraps = true
	local figures: Frame = Create("Frame", {
		Name = "Figures",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 1,
		Parent = right,
	})
	Theme.list(Enum.FillDirection.Vertical, 2, figures, Enum.HorizontalAlignment.Right)
	local function figure(name: string, order: number, kind: Theme.TextKind, weight: Enum.FontWeight?): TextLabel
		return Theme.label({
			Name = name,
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = figures,
		}, kind, weight)
	end
	local percent = figure("Percent", 1, "HudNumber")
	local owned = figure("Owned", 2, "Small", Enum.FontWeight.Bold)
	local row: Row
	local inspect = Button.new({
		name = "Boxes_InspectButton",
		text = Strings.common.inspect,
		height = TOUCH.minTarget,
		textKind = "Chip",
		layoutOrder = 2,
		parent = right,
		sound = false, -- opens a screen: ui.open plays instead (§18.5.2 B3)
		onActivated = function()
			local id = row.squishyId
			if id then
				UIController.open(INSPECT_SCREEN, { squishyId = id, owned = StateController.owns(id), source = SCREEN })
			end
		end,
	})
	inspect.root.Visible = false
	c:add(inspect)
	row = {
		root = root,
		icon = icon,
		name = name,
		rarity = rarity,
		percent = percent,
		owned = owned,
		refund = refund,
		inspect = inspect,
		squishyId = nil,
	}
	return row
end

-- The Open area (§6.10 item 7), pinned at the bottom of the disclosure column under the list (fix batch; build fits
-- the list and its place to its height).
local function buildOpenArea(parent: Instance): Frame
	local area: Frame = Create("Frame", {
		Name = "OpenArea",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(1 - LIST_SHARE, -Theme.Padding.medium, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, area, Enum.HorizontalAlignment.Center)
	return area
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local root = Theme.panel({
		Name = "Boxes",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, Config.UI.modalMaxWidth, MAX_HEIGHT_SHARE, 0),
		Parent = parent,
	}, Theme.Radius.panel, Theme.Padding.medium)
	c:add(root)
	-- The title: a Lilac header tab (the Boxes tile's colour) on the panel's top edge.
	local tab = Theme.headerTab(root, Strings.box.title, { textKind = TAB_KIND, accent = "lilac" })
	local rootPad = root:FindFirstChildOfClass("UIPadding") :: UIPadding
	-- Fix batch: no header row. Close hangs on the top-right corner, level with the tab (fitTab places it; drawn over the
	-- panel's outline like the tab).
	local close = Button.new({
		name = "Boxes_CloseButton",
		text = Strings.common.close,
		kind = "close", -- UI overhaul: the chunky red X
		height = TOUCH.closeButton,
		parent = root,
		sound = false, -- closing plays ui.back (UIController.close, reason "button")
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	close.root.AnchorPoint = Vector2.new(1, 0.5)
	close.root.ZIndex = tab.ZIndex
	close.root.Modal = true -- frees the cursor in shift lock / first person (§10.4 step 4)
	c:add(close)
	local function fitWidth()
		local width = Layout.modalWidth(gui.AbsoluteSize.X, UIController.scale(), MARGIN_PX)
		root.Size = UDim2.new(0, if width > 0 then width else Config.UI.modalMaxWidth, MAX_HEIGHT_SHARE, 0)
		fitTab(root, tab, rootPad, Theme.Padding.medium, close.root)
	end
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWidth))
	c:add(UIController.LayoutChanged:connect(function()
		fitWidth()
		refresh()
	end))
	local okSignal, textSizeChanged = pcall(function(): RBXScriptSignal
		return GuiService:GetPropertyChangedSignal("PreferredTextSize")
	end)
	if okSignal then
		c:add(textSizeChanged:Connect(fitWidth)) -- the tab follows the player's text size
	end
	fitWidth()

	local content: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	body = content

	-- The box list.
	local list: ScrollingFrame = Create("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(LIST_SHARE, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR_PX,
		ScrollBarImageColor3 = Theme.Colors.inkUI,
		Selectable = false,
		Parent = content,
	})
	-- Room on every side for the cards' foam outlines (the list clips its children).
	Create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, SCROLLBAR_PX + 4),
		Parent = list,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.small,
		list,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Top
	)
	for index, box in Boxes.list() do
		buildCard(c, list, box, index)
	end

	-- The disclosure (§6.10 items 1-6, top to bottom), with the Open area (item 7) pinned under it (fix batch).
	local scroll: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Disclosure",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1 - LIST_SHARE, -Theme.Padding.medium, 1, 0),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR_PX,
		ScrollBarImageColor3 = Theme.Colors.inkUI,
		Selectable = false,
		Parent = content,
	})
	-- Room for the outlines of the chips and buttons at the list's edges (it clips its children).
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, SCROLLBAR_PX + 4),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = scroll,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.small,
		scroll,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)

	local nameRow: Frame = Create("Frame", {
		Name = "NameRow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = scroll,
	})
	Theme.list(Enum.FillDirection.Vertical, 2, nameRow, Enum.HorizontalAlignment.Left)
	local name = label(nameRow, "Name", 1, "Title")
	-- §6.10 item 1's price: the coin and a bare number, or the free box's note (refresh).
	local priceRow: Frame = Create("Frame", {
		Name = "PriceRow",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		Parent = nameRow,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, priceRow, Enum.HorizontalAlignment.Left)
	local priceCoin = CoinIcon.new({ name = "Coin", sizePx = PRICE_COIN_PX, layoutOrder = 1, parent = priceRow })
	c:add(priceCoin)
	local price = Theme.label({
		Name = "Price",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = priceRow,
	}, "HudNumber")
	local summary = label(scroll, "Summary", 2, "Body")
	local details = Button.new({
		name = "Boxes_DetailsButton",
		text = Strings.box.details,
		height = TOUCH.minTarget,
		textKind = "Chip",
		layoutOrder = 3,
		parent = scroll,
		onActivated = function()
			detailsOpen = not detailsOpen
			refresh()
		end,
	})
	details.root.Visible = false
	c:add(details)
	local heading = label(scroll, "Heading", 4, "H2")
	heading.Text = Strings.box.insideHeading
	-- The item rows on a lighter paper inside an inset field (shown and hidden as one, refresh).
	local rowsFrame = Theme.inset({
		Name = "Rows",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 5,
		Parent = scroll,
	}, Theme.Radius.button, Theme.Padding.small)
	Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.small,
		rowsFrame,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local most = 0
	for _, box in Boxes.list() do
		most = math.max(most, #box.items)
	end
	for index = 1, most do
		table.insert(rows, buildRow(c, rowsFrame, index))
	end
	local total = label(scroll, "Total", 6, "Body", Enum.FontWeight.Bold)
	local footer = label(scroll, "Footer", 7, "Small")
	footer.Text = Strings.box.footer
	footer.TextColor3 = Theme.Colors.ink2

	local area = buildOpenArea(content)
	local confirm = ConfirmButton.new({
		name = "Boxes_OpenButton",
		accent = "shop", -- UI overhaul: the Lime purchase CTA
		price = 0,
		balance = coins(),
		text = Strings.format(Strings.box.openButton, { cost = Format.coins(0) }),
		needText = BoxFormat.needCoinsText,
		height = TOUCH.primaryButton,
		layoutOrder = 1,
		parent = area,
		onConfirm = function()
			openSelected()
		end,
	})
	c:add(confirm)
	local retry = Button.new({
		name = "Boxes_RetryButton",
		text = Strings.common.tryAgain,
		kind = "primary",
		height = TOUCH.primaryButton,
		layoutOrder = 2,
		parent = area,
		onActivated = function()
			if retryWait() > 0 then
				return
			end
			retryAt = os.clock()
			NetController.fire("PolicyRetry")
			refreshOpenArea()
		end,
	})
	retry.root.Visible = false
	c:add(retry)
	local shop = Button.new({
		name = "Boxes_ShopDirectButton",
		text = Strings.box.shopDirect,
		kind = "primary",
		height = TOUCH.primaryButton,
		layoutOrder = 3,
		parent = area,
		sound = false, -- opens a screen: ui.open plays instead
		onActivated = function()
			local boxId = selectedBox
			UIController.close(SCREEN, "shopDirect")
			UIController.open(SHOP_SCREEN, { tab = "squishies", boxId = boxId })
		end,
	})
	shop.root.Visible = false
	c:add(shop)
	local note = label(area, "Note", 4, "Small")
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.Visible = false
	local status = label(area, "Status", 5, "Small", Enum.FontWeight.Bold)
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.Visible = false
	local howToEarn = Button.new({
		name = "Boxes_HowToEarnButton",
		text = Strings.box.howToEarn,
		height = TOUCH.minTarget,
		textKind = "Chip",
		layoutOrder = 6,
		parent = area,
		onActivated = function()
			UIController.close(SCREEN, "howToEarn")
			showEarnWaypoint()
		end,
	})
	howToEarn.root.Visible = false
	c:add(howToEarn)

	-- Fix batch: the list ends a gap above the pinned Open area, which sits at the bottom of the column. The room keeps
	-- the "Balance after" line that arming shows under the button (ConfirmButton), so the button never moves; measured
	-- in base px (AbsoluteSize over the UI scale and UIController's open pop, like Quests and Settings).
	local balanceLine = confirm.root:FindFirstChild("BalanceAfter")
	local function fitOpenArea()
		local pop = root:FindFirstChild("SD_OpenScale")
		local s = UIController.scale() * (if pop and pop:IsA("UIScale") then pop.Scale else 1)
		if not (s > 0) then
			return
		end
		local height = area.AbsoluteSize.Y / s
		local armedRoom = if confirm.root.Visible
				and balanceLine
				and balanceLine:IsA("GuiObject")
				and not balanceLine.Visible
			then ConfirmButton.SUB_GAP + Theme.lineHeight("Small", Enum.FontWeight.Bold)
			else 0
		local room = if height >= 1 then math.ceil(height + armedRoom) else 0
		-- Fix round 2: Theme.Padding.large (was small) between the list and the Open area, so a row cut at the list's
		-- bottom no longer sits on the button.
		local reserve = if room > 0 then room + Theme.Padding.large else 0
		scroll.Size = UDim2.new(1 - LIST_SHARE, -Theme.Padding.medium, 1, -reserve)
		area.Position = UDim2.new(1, 0, 1, -room)
	end
	c:add(area:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitOpenArea))
	c:add(confirm.root:GetPropertyChangedSignal("Visible"):Connect(fitOpenArea))

	disclosure = {
		name = name,
		price = price,
		priceCoin = priceCoin.root,
		summary = summary,
		details = details,
		heading = heading,
		rows = rowsFrame,
		total = total,
		footer = footer,
		confirm = confirm,
		retry = retry,
		shop = shop,
		howToEarn = howToEarn,
		note = note,
		status = status,
	}

	loadingLabel = Theme.label({
		Name = "Loading",
		Text = Strings.common.loading,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = root,
	}, "H2")

	panel = root
	refresh()
	fitOpenArea()
	return root
end

-- Builders: the reveal ------------------------------------------------------------------------------------------------

local function buildReveal(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local root = Theme.panel({
		Name = "BoxReveal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(REVEAL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, Theme.Radius.panel, REVEAL_PANEL.padding)
	c:add(root)
	-- The box name: a Lilac header tab on the panel's top edge (startRun sets its text and fits it). The rows go in a
	-- Body frame: a header tab needs a panel without a UIListLayout of its own.
	local tab, title = Theme.headerTab(root, "", { textKind = TAB_KIND, accent = "lilac" })
	local rootPad = root:FindFirstChildOfClass("UIPadding") :: UIPadding
	local body: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		REVEAL_PANEL.gap,
		body,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Top
	)
	local stageHolder: Frame = Create("Frame", {
		Name = "Stage",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, STAGE_HEIGHT),
		LayoutOrder = 2,
		Parent = body,
	})
	-- A tap or click after skipTapAfterMs jumps to the final state (§9.11).
	c:add(stageHolder.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		local run = current
		if run and not run.final and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
			if run.elapsed >= REVEAL.skipTapAfterMs then
				skip()
			end
		end
	end))
	local info: CanvasGroup = Create("CanvasGroup", {
		Name = "Info",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Visible = false,
		Parent = body,
	})
	local infoOffset: Frame = Create("Frame", {
		Name = "Slide",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = info,
	})
	-- A little room above and below: the CanvasGroup clips, and the chips' outlines sit just outside their boxes.
	Create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 4), Parent = infoOffset })
	Theme.list(Enum.FillDirection.Vertical, REVEAL_PANEL.infoGap, infoOffset, Enum.HorizontalAlignment.Center)
	local name = Theme.label(
		{ Name = "Name", LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Center, Parent = infoOffset },
		"Title"
	)
	local rarity = RarityTag.new({ name = "Rarity", rarity = "Common", layoutOrder = 2, parent = infoOffset })
	c:add(rarity)
	-- "NEW!" (Strawberry) or "Already owned: +N Coins" (Frosting): ensureHighlight.
	local result = Chip.new({ name = "Result", text = "", textKind = "Button", layoutOrder = 3, parent = infoOffset })
	c:add(result)
	local saving = Theme.label({
		Name = "Saving",
		Text = Strings.reasonText("box.saving"),
		LayoutOrder = 4,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = body,
	}, "Small", nil, Theme.Colors.ink2)
	local buttons: Frame = Create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 5,
		Parent = body,
	})
	-- Fix batch: REVEAL_PANEL.buttonGap between the chunky result buttons (they read as one joined button at 6).
	local buttonList =
		Theme.list(Enum.FillDirection.Horizontal, REVEAL_PANEL.buttonGap, buttons, Enum.HorizontalAlignment.Center)
	buttonList.Wraps = true
	local skipButton = Button.new({
		name = "Reveal_SkipButton",
		text = Strings.common.skip,
		height = TOUCH.primaryButton,
		layoutOrder = 1,
		parent = buttons,
		onActivated = function()
			skip()
		end,
	})
	c:add(skipButton)
	local equip = Button.new({
		name = "Reveal_EquipButton",
		text = Strings.common.equip,
		kind = "primary",
		height = TOUCH.primaryButton,
		layoutOrder = 2,
		parent = buttons,
		onActivated = function()
			if resultInputOpen() then
				equipRevealed()
			end
		end,
	})
	c:add(equip)
	local inspect = Button.new({
		name = "Reveal_InspectButton",
		text = Strings.common.inspect,
		height = TOUCH.primaryButton,
		layoutOrder = 3,
		parent = buttons,
		sound = false, -- opens a screen: ui.open plays instead
		onActivated = function()
			local run = current
			if run == nil or not resultInputOpen() then
				return
			end
			local id = run.entry.reveal.squishyId
			-- The stage keeps the squishy for Inspect (§9.11 "hands the same model to Inspect without rebuilding").
			UIController.close(REVEAL_SCREEN, HANDOFF_REASON)
			UIController.open(INSPECT_SCREEN, { squishyId = id, owned = true, source = INSPECT_SOURCE })
		end,
	})
	c:add(inspect)
	local another = Button.new({
		name = "Reveal_OpenAnotherButton",
		text = Strings.box.openAnother,
		height = TOUCH.primaryButton,
		layoutOrder = 4,
		parent = buttons,
		sound = false, -- shows the Boxes screen: ui.open / ui.back play instead
		onActivated = function()
			if not resultInputOpen() then
				return
			end
			local run = current
			local boxId = if run then run.entry.reveal.boxId else selectedBox
			UIController.close(REVEAL_SCREEN, "openAnother")
			selectBox(boxId)
			if not UIController.isOpen(SCREEN) then
				UIController.open(SCREEN, { boxId = boxId })
			else
				local d = disclosure
				Focus.select(if d then d.confirm.button.root else nil)
			end
		end,
	})
	c:add(another)
	local close = Button.new({
		name = "Reveal_CloseButton",
		text = Strings.common.close,
		height = TOUCH.primaryButton,
		layoutOrder = 5,
		parent = buttons,
		sound = false, -- closing plays ui.back
		onActivated = function()
			if resultInputOpen() then
				UIController.close(REVEAL_SCREEN, "button")
			end
		end,
	})
	close.root.Modal = true
	c:add(close)

	revealUi = {
		root = root,
		padding = rootPad,
		tab = tab,
		title = title,
		stageHolder = stageHolder,
		info = info,
		infoOffset = infoOffset,
		name = name,
		rarity = rarity,
		result = result,
		saving = saving,
		skip = skipButton,
		equip = equip,
		inspect = inspect,
		another = another,
		close = close,
	}
	fitTab(root, tab, rootPad, REVEAL_PANEL.padding)
	return root
end

-- World: the box counter prompt and the odds board ----------------------------------------------------------------------

-- The odds board's live line under a stand (the OddsBoard part of the stand's model), sized to hold every line.
local function boardLines(stand: Instance): { TextLabel }
	local found: { TextLabel } = {}
	local model = stand.Parent
	local board = if model then model:FindFirstChild(ODDS_BOARD_PART) else nil
	if board == nil then
		return found
	end
	for _, descendant in board:GetDescendants() do
		if descendant:IsA("TextLabel") and descendant.Name == BOARD_LINE then
			table.insert(found, descendant)
		end
	end
	return found
end

-- Reading: the generator bakes the live line one text line tall; this owner lets it fill the panel under the title
-- (TextScaled under its baked UITextSizeConstraint, wrapped, top-aligned) so every odds line fits.
local function writeBoard(lineLabel: TextLabel, text: string)
	local holder = lineLabel.Parent
	local title = if holder then holder:FindFirstChild(BOARD_TITLE) else nil
	local layout = if holder then holder:FindFirstChildOfClass("UIListLayout") else nil
	local used = (if title and title:IsA("GuiObject") then title.Size.Y.Offset else 0)
		+ (if layout then layout.Padding.Offset else 0)
	local size = UDim2.new(1, 0, 1, -used)
	if lineLabel.Size ~= size then
		lineLabel.Size = size
	end
	lineLabel.TextWrapped = true
	lineLabel.TextYAlignment = Enum.TextYAlignment.Top
	if lineLabel.Text ~= text then
		lineLabel.Text = text
	end
end

local function refreshWorld()
	local policy = StateController.get("policy")
	local key = BoxFormat.promptKey(policy)
	local attribute = if key == SHOP_PROMPT_KEY then ATTR_ALT_TEXT_KEY else ATTR_TEXT_KEY
	local fallback = Strings.resolve(key)
	for _, stand in CollectionService:GetTagged(STAND_TAG) do
		local candidates = stand:GetDescendants()
		table.insert(candidates, stand)
		for _, candidate in candidates do
			if candidate:IsA("ProximityPrompt") then
				local baked = candidate:GetAttribute(attribute)
				local text = (if type(baked) == "string" then Strings.resolve(baked) else nil) or fallback
				if text and candidate.ActionText ~= text then
					candidate.ActionText = text
				end
			end
		end
		local boardText = BoxFormat.boardText(policy, standBoxId(stand))
		for _, line in boardLines(stand) do
			writeBoard(line, boardText)
		end
	end
end

local function guardedRefreshWorld()
	guarded("box counter update", refreshWorld)
end

-- Public ---------------------------------------------------------------------------------------------------------------

-- Opens the Boxes screen, optionally on one box. Returns UIController.open's result.
function BoxController.open(boxId: string?): boolean
	return UIController.open(SCREEN, if boxId then { boxId = boxId } else nil)
end

-- Small table for Studio debug hooks (SD_DebugClient "boxes").
function BoxController.debugState(): { [string]: any }
	local view = currentView()
	local queued = {}
	for _, entry in queue do
		table.insert(queued, { requestId = entry.reveal.requestId, source = entry.source })
	end
	local function keys(set: { [string]: boolean }): { string }
		local list = {}
		for key in set do
			table.insert(list, key)
		end
		table.sort(list)
		return list
	end
	local run = current
	local runState: { [string]: any }? = nil
	if run then
		local phase = BoxFormat.revealPhase(run.elapsed, run.reduced)
		runState = {
			requestId = run.entry.reveal.requestId,
			boxId = run.entry.reveal.boxId,
			squishyId = run.entry.reveal.squishyId,
			isDuplicate = run.entry.reveal.isDuplicate,
			refund = run.entry.reveal.refund,
			source = run.entry.source,
			rarity = run.rarity,
			phase = if run.final then "result" else phase,
			elapsedMs = math.floor(run.elapsed),
			final = run.final,
			acked = run.acked,
			reduced = run.reduced,
			cuesPlayed = run.cueIndex - 1,
		}
	end
	local prompts = {}
	local boards = {}
	for _, stand in CollectionService:GetTagged(STAND_TAG) do
		for _, descendant in stand:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then
				table.insert(prompts, descendant.ActionText)
			end
		end
		for _, line in boardLines(stand) do
			table.insert(boards, line.Text)
		end
	end
	local stageExists = ViewportStage.exists()
	local stage = if stageExists then ViewportStage.get() else nil
	return {
		built = panel ~= nil,
		open = UIController.isOpen(SCREEN),
		revealOpen = UIController.isOpen(REVEAL_SCREEN),
		selected = selectedBox,
		policy = StateController.get("policy"),
		coins = StateController.coins(), -- as shown (a held reveal's refund left out)
		serverCoins = StateController.serverValue("coins"),
		ownedShown = keys(StateController.owned() :: any),
		heldReveals = StateController.heldRevealIds(),
		view = {
			kind = view.kind,
			button = view.button,
			text = view.text,
			enabled = view.enabled,
			reason = view.reason,
			note = view.note,
			howToEarn = view.howToEarn,
		},
		status = statusText,
		retryWait = retryWait(),
		detailsOpen = detailsOpen,
		layout = UIController.layoutClass(),
		opening = if opening then { boxId = opening.boxId, requestId = opening.requestId } else nil,
		pendingIds = table.clone(pendingIds),
		inFlight = keys(inFlight),
		played = keys(played),
		queue = queued,
		held = holdReveals,
		reveal = runState,
		lastResult = lastResult,
		stage = {
			exists = stageExists,
			attached = stage ~= nil and stage:isAttached(),
			hasModel = stage ~= nil and stage:model() ~= nil,
		},
		prompts = prompts,
		boards = boards,
		waypoint = waypoint ~= nil,
	}
end

-- Studio (SD_DebugClient "openBox"): the real flow on `boxId`: the screen opens on it, the Open area must allow it
-- (eligible, enough Coins, not complete, not saving: the same view the confirm step uses), then the confirming press
-- runs after the double-click guard and BoxOpen is sent. Yields until the reply.
function BoxController.debugOpen(boxId: unknown): { [string]: any }
	local id = validBox(boxId)
	if id == nil then
		return { ok = false, error = "unknown box " .. tostring(boxId) }
	end
	if not UIController.open(SCREEN, { boxId = id }) then
		return { ok = false, error = "the boxes screen was refused" }
	end
	selectBox(id)
	local view = currentView()
	if view.kind ~= "open" and view.kind ~= "confirm" then
		return { ok = false, error = "not openable: " .. view.kind, reason = view.reason, note = view.note }
	end
	task.wait(DEBUG_PRESS_GAP) -- the ConfirmButton's second press comes after its double-click guard
	return openSelected()
end

-- Studio (SD_DebugClient "holdReveals"): true pauses the unseen reveals (reply reveals still play); false resumes.
function BoxController.debugHoldReveals(on: boolean)
	holdReveals = on == true
	if not holdReveals then
		scanUnseen()
	end
end

-- Studio (SD_DebugClient "skipReveal"): jumps the running reveal to its final state. False when none is running.
function BoxController.debugSkip(): boolean
	return skip()
end

-- Studio only: plays the box reveal of `squishyId` as a local preview (no remote, no grant; spec 2026-10-09 §6 Studio
-- check 3): queued first, as a new squishy with no refund, in the first box that holds it (snack otherwise). It
-- plays when the queue does (the lobby, the reveal screen, Inspect closed); `playing` says whether it started now.
function BoxController.debugRevealPreview(squishyId: unknown): { [string]: any }
	local def = if type(squishyId) == "string" then Catalog.get(squishyId) else nil
	if def == nil then
		return { ok = false, error = `unknown squishy {tostring(squishyId)}` }
	end
	if not game:GetService("RunService"):IsStudio() then
		return { ok = false, error = "Studio only" }
	end
	local containing = Boxes.containing(def.id)
	local boxId = if #containing > 0 then containing[1].boxId else firstPaidBox()
	local requestId = "preview:" .. HttpService:GenerateGUID(false)
	enqueue({
		reveal = { requestId = requestId, boxId = boxId, squishyId = def.id, isDuplicate = false, refund = 0 },
		source = "preview",
		savePending = false,
	}, true)
	pump()
	local run = current
	return {
		ok = true,
		requestId = requestId,
		squishyId = def.id,
		boxId = boxId,
		playing = run ~= nil and run.entry.reveal.requestId == requestId,
		queued = queuedIds[requestId] == true, -- still waiting for its turn
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function BoxController.init()
	local c = Cleanup.new()
	cleanup = c
	selectedBox = firstPaidBox()

	c:add(UIController.registerScreen(SCREEN, {
		build = build,
		onOpen = function(params: any?)
			local wanted = if type(params) == "table" then validBox(params.boxId) else nil
			if wanted then
				selectBox(wanted)
			end
			local oc = Cleanup.new()
			if openCleanup then
				openCleanup:clean()
			end
			openCleanup = oc
			clearWaypoint()
			-- The Try again countdown follows the clock while the screen is open (one more refresh when it ends).
			oc:add(task.spawn(function()
				local cooling = false
				while true do
					task.wait(TICK_SECONDS)
					local waiting = retryWait() > 0
					if waiting or cooling then
						guarded("open area update", refreshOpenArea)
					end
					cooling = waiting
				end
			end))
			refresh()
		end,
		onClose = function()
			if openCleanup then
				openCleanup:clean()
				openCleanup = nil
			end
			detailsOpen = false
			local d = disclosure
			if d and opening == nil then
				d.confirm:reset()
			end
		end,
		primary = function(): GuiObject?
			local d = disclosure
			if d then
				local view = currentView()
				if view.button == "confirm" and view.enabled then
					return d.confirm.button.root
				elseif view.button == "retry" then
					return d.retry.root
				elseif view.button == "shop" then
					return d.shop.root
				end
			end
			local card = cards[selectedBox]
			return if card then card.root else nil
		end,
		onTab = function(direction: number)
			cycleBox(direction)
		end,
	}))

	c:add(UIController.registerScreen(REVEAL_SCREEN, {
		build = buildReveal,
		onOpen = function()
			headingHidden = true -- fix round 2 (refresh): the Boxes name and price under the reveal's tab
			refresh()
			local entry = starting
			if entry == nil or current ~= nil then
				return
			end
			if not startRun(entry) then
				task.defer(function()
					if current == nil then
						UIController.close(REVEAL_SCREEN, "failed")
						pump()
					end
				end)
			end
		end,
		onClose = function(reason: string)
			headingHidden = false
			refresh()
			local run = current
			if run == nil then
				return
			end
			if reason == "matched" and not run.final then
				-- Not seen yet: no AckReveal; it plays again after the duel (it is still unseen on the server).
				played[run.entry.reveal.requestId] = nil
				if run.entry.source == "reply" then
					enqueue(run.entry, true)
				end
			else
				local finalized = guarded("reveal finalize", function()
					finalize(run, "close")
				end)
				if not finalized then
					ack(run)
				end
			end
			current = nil
			guarded("reveal teardown", function()
				teardown(run, reason == HANDOFF_REASON)
			end)
			task.defer(pump)
		end,
		primary = function(): GuiObject?
			local ui = revealUi
			local run = current
			if ui == nil then
				return nil
			end
			if run and run.final then
				return if ui.equip.root.Visible then ui.equip.root else ui.close.root
			end
			return ui.skip.root
		end,
	}))

	c:add(WorldBinder.registerStand(STAND_TAG, function(stand: Instance)
		local boxId = standBoxId(stand)
		if
			BoxFormat.standScreen(StateController.get("policy")) == SHOP_SCREEN
			and UIController.isRegistered(SHOP_SCREEN)
		then
			UIController.open(SHOP_SCREEN, { tab = "squishies", boxId = boxId })
		else
			UIController.open(SCREEN, { boxId = boxId })
		end
	end))

	for _, field in { "coins", "owned", "dataStatus" } do
		c:add(StateController.changed(field):connect(function()
			refresh()
		end))
	end
	c:add(StateController.changed("policy"):connect(function(policy: any)
		if policy == POLICY_UNKNOWN then
			unknownAt = os.clock() -- Try again waits from here too (BoxFormat.retryWait)
		end
		refresh()
		guardedRefreshWorld()
	end))
	if StateController.get("policy") == POLICY_UNKNOWN then
		unknownAt = os.clock() -- already unknown before this listener existed: wait the full time from now
	end
	c:add(StateController.changed("unseenReveals"):connect(function()
		scanUnseen()
	end))
	c:add(StateController.Loaded:connect(function()
		refresh()
		guardedRefreshWorld()
		scanUnseen()
	end))
	c:add(StateController.LobbyLockChanged:connect(function(locked: boolean)
		if locked then
			clearWaypoint()
		else
			scanUnseen()
		end
		refresh()
	end))
	c:add(CollectionService:GetInstanceAddedSignal(STAND_TAG):Connect(function()
		task.defer(guardedRefreshWorld) -- after WorldBinder re-applies the baked prompt text on stream-in
	end))
	-- A reveal that waited for Inspect (pump) plays once Inspect has closed and given the stage back.
	c:add(UIController.ScreenClosed:connect(function(name: string)
		if name == INSPECT_SCREEN then
			task.defer(pump)
		end
	end))
	c:add(function()
		if openCleanup then
			openCleanup:clean()
			openCleanup = nil
		end
		stopWaitWobble()
		clearWaypoint()
		local run = current
		current = nil
		if run then
			guarded("reveal teardown", function()
				teardown(run, false)
			end)
		end
		table.clear(cards)
		table.clear(rows)
		table.clear(queue)
		table.clear(queuedIds)
		panel, loadingLabel, body, disclosure, revealUi = nil, nil, nil, nil, nil
	end)
	log:debug("ready")
end

function BoxController.start()
	local c = cleanup
	if c == nil then
		return
	end
	task.defer(guardedRefreshWorld)
	scanUnseen()
	c:add(task.spawn(function()
		while true do
			task.wait(WORLD_REFRESH_SECONDS)
			-- A counter that streams in later gets its baked prompt text back from WorldBinder; put the live one on.
			guardedRefreshWorld()
		end
	end))
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function BoxController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return BoxController
