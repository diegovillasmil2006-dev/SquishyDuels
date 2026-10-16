--!strict
-- HudController (client only). DESIGN §11.6 (lobby HUD), §11.2 (layout, phone zones), §11.3 (states), §11.4 / §11.7
-- (DPadUp focuses the HUD), §9.13 (coin counter), §3.13 (data banner), §17.7 (the Grip card slot); the foam UI restyle
-- (spec docs/superpowers/specs/2026-10-09-foam-ui-restyle-design.md "Lobby HUD", kit guide 2026-10-09-foam-ui-
-- components.md). Everything lives in SD_Hud and is hidden from Matched through Returning (StateController lobby lock:
-- "Hidden during duels"; the Grip card inside the left column hides with it, §17.2).
-- UI FINAL R4 (plan work/ui/PLAN.md R4; `H:n` = "Squishy Duels HUD.dc.html" line n, `N:n` = Diego's newer
-- "Squishy Duels TDMFFA animations and hud/Squishy Duels HUD.dc.html" line n; numbers in Config.UI.Sticker.hud): the
-- design's HUD. Regular layouts put each group on the design's spot (HudFormat.origins); phones keep COLUMN.edge.
--
-- * Top-left column (Hud_Left, H:74): the coin pill (Hud_Coins / Hud_CoinsButton, UI/Components/CoinCapsule, H:75-81;
--   tapping it opens the Shop at its top, H:987, G4.16) and under it GripController's bare Grip row
--   (LEFT_ORDER.grip). A gain flies the design's coins into the pill (flyCoins; a claim's count, else 8, H:663): each
--   landing steps the number up (HudFormat.coinStep, the last coin the rest, G4.10), plays ui.coin a semitone higher
--   (PR8) and the landing's sparks (H:577), and the bright flash (CoinCapsule:flash, H:562-575) at most once per
--   coinFlight.bounceMinGapMs, the last coin's never dropped (PR7, HudFormat.flashPlan). The number only rises: a
--   claim's StateDelta comes before the reply that starts its flight, so a flight-sized gain with nothing in the air
--   holds the old number coinCounter.flightWaitMs for it (HudFormat.flightShows); a gain that does not fly shows the
--   new number with one landing. A spend drops the number at once with the "-N" float and the pill's squash
--   (H:671-674, G4.10); denyCoins() shakes the pill and toasts "Not enough coins!" (H:676, silent: the press played
--   ui.error). The old gain feedback (the "+N", the bounce, the disc wiggle, the badge pop) is gone (G4.11).
-- * The nav stickers (Hud_Nav, H:98-120): Squishies, Boxes, Shop, Quests, Daily as faceless stickers (Button "tile",
--   P13: the picture is the button) in one column at (navX, navTop), 118 x 104, their pictures bobbing 3.1 s each .3 s
--   later (H:100-118); a tile shows only when its screen is registered. Count badges inside the tile (H:102, H:115):
--   new squishies, claimable quests (and starter tasks); the Daily tile's yellow "!" while today's reward is unclaimed
--   (H:120, G4.15); each badge loops sdBadge. Phones keep the 58 px tiles in two columns. Keys 1-5 open these windows
--   or close the one on top (H:653-654; ControlsController NavN / ModalNavN, keyboard only, lobby only).
-- * Top right (Hud_Right, H:156): the Settings sticker (Hud_SettingsButton, 92 x 90, H:157-159), the quest tracker
--   (Hud_QuestTracker: the quest row's look, H:363-367, G4.21: the quest's picture (QuestFormat.iconFor), its title,
--   "x/y", the quest bar and "Ready to claim!" / "+N coins", H:995; the unclaimed quest closest to done, Starter tasks
--   first, HudFormat.trackedQuest; hidden on the compact layout) and the data banner (Hud_DataBanner,
--   HudFormat.banner).
-- * The GRIP float (Hud_GripFloat, H:92-96; the user, 2026-10-15: on the player's own screen, nothing above heads):
--   "GRIP" over the Grip level (GripController.setGripLevel), centred at the design's top 300 (at most 300/810 of a
--   shorter screen), floating 3.6 s; not on phones (the compact Grip card shows the level; it would sit over the
--   player) nor in first person (practice: over the targets), HudFormat.gripFloatShown.
-- * The DUEL area (Hud_CtaWrap, top middle at ctaTop, PR10): idle, the DUEL button (Hud_DuelButton, a "cta" Button,
--   H:126- 133: 350 x 92, the emblem bobbing 2.4 s, "DUEL" / "Join the queue", its soft shadow H:126 T2, the moving
--   shine); for the testers (Config.Match.pickerTesters, HudFormat.pickerShown) Diego's TEAM DEATHMATCH / FREE FOR ALL
--   picker under it (Hud_DuelModes, UI/Components/SegmentedTabs, N:154-158; TDM first, N:735; the design's short names,
--   N:711-712, where the full ones leave no room), and DUEL sends MatchJoin(the mode) (the in-server queue; its toasts
--   show the progress until the 12-slot bar exists; the join's sound and sparks play on its match.joined); everyone
--   else's DUEL opens QueueController's non-modal "queue" screen (QueueJoin). While the 1v1 queue searches: the search
--   bar (Hud_DuelSearch, H:135-146: "Finding match", the dots, m:ss, the two slots (you mint, the opponent pink), the
--   queue line, the QueueController's cancel X in its right end), popping in (sdPop, G4.1) with the join sounds and
--   sparks (H:758-763) and a tick every 700 ms (H:763); on Matched (QueueController.matchFound; the bar stays through
--   Matched) the opponent's slot fills first, then 350 ms later MATCH FOUND (Hud_MatchFound in SD_Overlay at the area's
--   last place, under the duel HUD's top bar once that shows, H:148-152, G4.2, G4.3) pops in with its sparks, ring,
--   jolt and ui.toast and stays Config.UI.Queue.matchedBannerSeconds or until the arena countdown. Phones draw only the
--   idle DUEL button at COLUMN.ctaCompactScale (the second line hidden); the search bar and the picker keep their full
--   size (PR1, PR2; HudFormat.ctaScales). The toasts start under the area (UIController.toastsBelow "cta"), then under
--   the coach card or the queue pill right under it (NotifyFormat chains them), at the design's top (N:197) only while
--   this HUD shows (UIController.setToastTop).
-- * Lobby audio zones: WorldBinder (a higher layer than SoundController) is connected to SoundController here (reading).
-- * Layout (Part 8 device pass; pure maths in UI/HudFormat): HudFormat.leftColumnPlan picks the Grip row's layout
--   (regular / compact, GripController reads columnPlan()), whether Hud_Left holds the coin pill and the Grip card
--   stacked or side by side and the tiles' arrangement (a column, two columns, or a row) so the left side ends above
--   the thumbstick zone on narrow layouts (compact class or touch input) and on screen elsewhere, for the HUD's size,
--   layout class, input and GuiService.PreferredTextSize. Everything is laid out again (deferred, at most once a frame)
--   when a size, the class, the input, the text size or a visible part changes; LayoutChanged then tells the coach card
--   and the queue pill (they place themselves from layoutRects(), under the DUEL area).
-- * Gamepad (HudFormat.focusLinks): the left column top to bottom (the coin pill, the Grip row = the DPadUp entry, the
--   tiles), the right column (Settings, the tracker) and the links between them: the DUEL button between the left
--   column and Settings (while searching, the search bar's cancel X), Down to the mode tabs, else (searching) the queue
--   pill's first hint button ("queueHint"), else the queue pill's or the coach card's button (both Up back to it), a
--   tile -> the DUEL button. Only the links this module set are
--   cleared again.
-- Public: leftColumn(), LEFT_ORDER, setFocusEntry(object?), setFocusTarget(key, object?), element(name), coinsAnchor(),
-- isShown(), VisibilityChanged, LayoutChanged, layoutRects(), flyCoins(from, amount, count?), denyCoins(),
-- setGainSource(label?), debugCoinFlight(amount), columnPlan(), ColumnPlanChanged, setColumnItem(key, present),
-- setGripLevel(level?), gripLevelLabel(), cancelSlot(), matchFound(text) -> handle, textScale(), debugState().

-- Services

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)
local TimeUtil = require(Shared.Util.TimeUtil)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local CoinCapsule = require(Client.UI.Components.CoinCapsule)
local CoinFlight = require(Client.UI.CoinFlight)
local Create = require(Client.UI.Create)
local Focus = require(Client.UI.Focus)
local HudFormat = require(Client.UI.HudFormat)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local Layout = require(Client.UI.Layout)
local ProgressBar = require(Client.UI.Components.ProgressBar)
local QuestFormat = require(Client.UI.QuestFormat)
local Scheduler = require(Client.Anim.Scheduler)
local SegmentedTabs = require(Client.UI.Components.SegmentedTabs)
local SquishyImage = require(Client.UI.Components.SquishyImage)
local Theme = require(Client.UI.Theme)
local Tweens = require(Client.Anim.Tweens)
local UiFx = require(Client.UI.UiFx)
local UiIdle = require(Client.Anim.UiIdle)
local ControlsController = require(script.Parent.ControlsController)
local FirstPersonController = require(script.Parent.FirstPersonController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

export type Rect = HudFormat.Rect
-- The HUD's groups in SD_Hud's base px (layoutRects), nil while hidden: the queue pill and the coach card keep clear.
export type Rects = {
	canvas: Vector2,
	left: Rect?, -- Hud_Left (the coin pill and the Grip row)
	tiles: Rect?, -- Hud_Nav (the tiles)
	right: Rect?, -- Hud_Right (Settings, the tracker, the data banner)
	cta: Rect?, -- the DUEL area (the button and the mode picker, or the search bar; the top middle)
	coach: Rect?, -- Hud_OnboardingCard (OnboardingController)
	reserved: { Rect }, -- narrow layouts: the thumbstick zone, the touch Throw / Ultimate buttons and the jump button
}
-- What matchFound returns (UIController.BannerHandle's shape: QueueController keeps it as its matched banner).
export type FoundHandle = {
	setText: (self: FoundHandle, text: string) -> (),
	dismiss: (self: FoundHandle) -> (),
	isShown: (self: FoundHandle) -> boolean,
}

type BadgeTile = { button: Button.Button }
type Tracker = {
	root: TextButton,
	foam: Theme.Foam,
	icon: Frame, -- the picture's tile (H:364)
	picture: Instance?, -- what it shows now (an image holder or a SquishyImage)
	pictureFor: string?, -- the image key or the squishy it shows
	squishy: SquishyImage.SquishyImage?,
	title: TextLabel,
	count: TextLabel,
	bar: ProgressBar.ProgressBar,
	status: TextLabel,
	ready: boolean?, -- the shown quest is ready to claim (H:995: the yellow border and status)
}
type SearchBar = {
	root: Frame, -- Hud_DuelSearch, laid out in the DUEL area
	pop: Frame, -- SD_Pop: its entrance
	dots: Frame,
	time: TextLabel,
	line2: Frame,
	fills: { Frame }, -- the two slots' fills: you, the opponent
	players: TextLabel,
	cancelSlot: Frame,
}
type FoundBar = { root: Frame, pop: Frame, sub: TextLabel }

-- Constants

local HUD_GUI = "SD_Hud"
local OVERLAY_GUI = "SD_Overlay"
local STICKER = Config.UI.Sticker
local HUD = STICKER.hud
local MOTION = Config.UI.motion
local COIN_MOTION = MOTION.coinCounter
local FLIGHT = MOTION.coinFlight
local FX = Config.UI.Fx
local UI_PITCH = Config.Audio.uiPitch
local COLUMN = HudFormat.COLUMN
local EDGE_PX = COLUMN.edge
local GAP_PX = COLUMN.rowGap
local QUEUE_TICK_SECONDS = 0.25 -- the search bar's clock shows whole seconds
local DAY_CHECK_SECONDS = 30 -- reading: how often the daily badge re-checks the UTC day
local SHOP_SCREEN = "shop"
local QUESTS_SCREEN = "quests"
local COIN_SOUND = "ui.coin"
local CLICK_SOUND = "ui.click"
local HOVER_SOUND = "ui.hover"
local TOAST_SOUND = "ui.toast"
local FOCUS_ACTION = "FocusHud"
local COACH_NAME = "Hud_OnboardingCard" -- OnboardingController's coach card (a stable name)
local SEARCHING = "Searching"
local MATCH_JOIN = "MatchJoin" -- Remotes: MatchJoin(mode: string), FFA/TDM v1's in-server queue
local MATCH_JOINED = "match.joined" -- MatchService's Notify when it took the join (a refusal is match.refused.*)
local DEFAULT_MODE = "tdm" -- N:735
-- The duel HUD's top bar (DuelController's stable names): MATCH FOUND keeps under it once it shows.
local DUEL_GUI, DUEL_TOP_BAR = "SD_DuelHud", "TopBar"
-- H:653-654: the keys 1-5 open these windows (ControlsController NavN / ModalNavN).
local NAV_KEYS: { string } = { "squishies", "boxes", "shop", "quests", "daily" }
-- H:92-96: the GRIP float's design top on the design's 810 px canvas (a shorter canvas keeps its share).
local DESIGN_CANVAS_HEIGHT = Config.UI.Scale.referenceHeight
-- HudFormat.focusLinks directions -> the GuiObject property each one sets (applyFocusLinks).
local FOCUS_PROPERTIES: { [string]: string } = {
	up = "NextSelectionUp",
	down = "NextSelectionDown",
	left = "NextSelectionLeft",
	right = "NextSelectionRight",
}

-- Module table

local HudController = {}

-- Where cards go in the left column: the coin capsule is first.
HudController.LEFT_ORDER = table.freeze({ coins = 0, grip = 10 })
-- (shown) when the HUD shows or hides (lobby lock).
HudController.VisibilityChanged = Signal.new() :: Signal.Signal<boolean>
-- (plan) when the left side's layout changes (HudFormat.samePlan decides "changes").
HudController.ColumnPlanChanged = Signal.new() :: Signal.Signal<HudFormat.ColumnPlan>
-- () after every layout pass (the coach card and the queue pill place themselves from layoutRects()).
HudController.LayoutChanged = Signal.new() :: Signal.Signal<>

-- Private

local log = Log.new("Hud")
local cleanup: Cleanup.Cleanup? = nil
local hudGui: ScreenGui? = nil
local leftColumn: Frame? = nil
local coinsHolder: Frame? = nil
local coins: CoinCapsule.CoinCapsule? = nil
local navRow: Frame? = nil
local navGrid: UIGridLayout? = nil
local tiles: { [string]: Button.Button } = {}
local tileOrder: { string } = {}
local tileLabels: { [string]: string } = {} -- a tile's label (its width follows the widest one)
local tileCompact: boolean? = nil -- the tiles' text look applied last (applyTileLook)
local badgeTiles: { [string]: BadgeTile } = {}
local rightColumn: Frame? = nil
-- The Settings sticker's fixed-size holder in Hud_Right (its hover never moves the list).
local settingsSlot: Frame? = nil
local settingsButton: Button.Button? = nil
local tracker: Tracker? = nil
local trackedId: string? = nil
local bannerFrame: Frame? = nil
local bannerLabel: TextLabel? = nil
local ctaWrap: Frame? = nil -- Hud_CtaWrap: the DUEL area
local ctaScale: UIScale? = nil -- SD_CtaScale: the phone scale of the idle DUEL button only (HudFormat.ctaScales)
local idleBox: Frame? = nil -- Hud_DuelIdle: the DUEL button and its soft shadow, sized to their drawn size
local idleHolder: Frame? = nil -- SD_IdleScale in Hud_DuelIdle: the button at its base size under SD_CtaScale
local duelButton: Button.Button? = nil
local picker: SegmentedTabs.SegmentedTabs? = nil
local pickerOn = false -- this player sees the mode picker (HudFormat.pickerShown)
local mode = DEFAULT_MODE
local search: SearchBar? = nil
local found: FoundBar? = nil
local foundToken = 0 -- the matchFound call that owns the found bar
local holdCta = false -- the DUEL area stays up for the opponent's slot (H:772) while the HUD hides
local ctaQueued = false
local ctaCompact = false
local ctaRect: Rect? = nil
local lastCtaRect: Rect? = nil -- the DUEL area's last rect while it showed (MATCH FOUND's place, foundSpot)
local foundFollow: Cleanup.Cleanup? = nil -- MATCH FOUND follows the duel HUD's top bar while it shows
local ctaFits: boolean? = nil -- HudFormat.ctaPlacement's answer (debugState)
local searchWidth = HUD.search.width
local gripFloat: Frame? = nil
local gripLevelLabel: TextLabel? = nil
local gripLevel: number? = nil
local focusEntry: GuiObject? = nil
local focusTargets: { [string]: GuiObject } = {} -- setFocusTarget ("onboarding": the coach card's button; "queue")
local shown = true
local displayedCoins: number? = nil
local targetCoins: number? = nil
local coinIcon: GuiObject? = nil
local lastFlashAt: number? = nil -- PR7: when the pill's bright flash last played (os.clock)
local laterFlash: thread? = nil -- PR7: the last coin's flash, waiting out the gap
local awaitingLanding = false -- coins are in the air and the number waits for the first landing
local pendingGain: thread? = nil -- a gain holding the old number for the flight that claims it (flightWaitMs)
local gainSource: GuiObject? = nil -- the result panel's reward label (setGainSource)
local columnGrip = false -- the Grip card wants to show (setColumnItem "grip")
local columnPlan: HudFormat.ColumnPlan = HudFormat.leftColumnPlan(COLUMN.fallbackScreen, "regular", 1)
-- The NextSelection* links the last applyFocusLinks set (object, property, target): only those are cleared again.
type FocusWrite = { object: GuiObject, property: string, target: GuiObject }
local focusWrites: { FocusWrite } = {}
-- A running sdPop per holder: its frame effect and how it puts the holder back at rest (popIn).
type Pop = { handle: Scheduler.Handle, rest: () -> () }
local popHandles: { [Instance]: Pop } = {}
local layoutQueued = false
local studioLogged = false

local function finiteNumber(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function setIfChanged(object: any, property: string, value: any)
	if object[property] ~= value then
		object[property] = value
	end
end

local function isTouch(): boolean
	return ControlsController.preferredInput() == Enum.PreferredInput.Touch
end

-- Touch or the compact layout: the thumbstick zone and the touch buttons stay clear.
local function isNarrow(): boolean
	return UIController.layoutClass() == "compact" or isTouch()
end

-- The player's GuiService.PreferredTextSize multiplier (1 when the engine has none).
local function currentTextScale(): number
	local ok, value = pcall(function(): any
		return GuiService.PreferredTextSize
	end)
	local name = if ok and typeof(value) == "EnumItem" then (value :: EnumItem).Name else nil
	return Layout.preferredTextScale(name)
end

-- The whole screen's height in px (Camera.ViewportSize.Y: with the top bar inset SD_Hud leaves out), or nil. The
-- thumbstick zone is a share of it (HudFormat.thumbstickZone).
local function screenHeight(): number?
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else nil
	return if finiteNumber(height) and (height :: number) > 0 then height else nil
end

-- `object`'s box in SD_Hud's base px, or nil while it is not on screen.
local function rectOf(object: GuiObject?): Rect?
	local gui = hudGui
	local scale = UIController.scale()
	if object == nil or gui == nil or scale <= 0 or object.Parent == nil then
		return nil
	end
	local node: Instance? = object
	while node and node:IsA("GuiObject") do
		if not (node :: GuiObject).Visible then
			return nil
		end
		node = node.Parent
	end
	local size = object.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end
	local position = (object.AbsolutePosition - gui.AbsolutePosition) / scale
	return { x = position.X, y = position.Y, w = size.X / scale, h = size.Y / scale }
end

-- UI FINAL R4 (G4.1, H:25): the design's sdPop on a bar's inner holder: its move, scale and tilt (Tweens.poser) and its
-- fade (Tweens.fadeGroup: the bar does not clip, so CSS's whole-element fade is drawn), each segment eased by `curve`;
-- a new pop on the same holder first puts the running one's holder back at rest (its fade group recorded the
-- transparencies as they were, so a half-faded rest would stay), then replaces it. Nothing under ReducedMotion (PR9).
local function popIn(holder: Frame, ms: number, curve: string)
	local running = popHandles[holder]
	if running then
		running.handle:disconnect()
		running.rest()
		popHandles[holder] = nil
	end
	if Tweens.reducedMotion() then
		return
	end
	local fade = Tweens.fadeGroup(holder)
	local poser = Tweens.poser(holder)
	local frames: { Tweens.Pose } = MOTION.ctaPop.frames :: any
	local started = os.clock()
	local function rest()
		fade:restore()
		poser:rest()
	end
	local handle = Scheduler.add(function(_dt: number, now: number): boolean
		if holder.Parent == nil then
			return false
		end
		local u = math.min((now - started) * 1000 / ms, 1)
		local pose = Tweens.poseAt(frames, u, curve)
		fade:setAlpha(pose.alpha or 1)
		poser:set({ x = pose.x, y = pose.y, scale = pose.scale, rot = pose.rot })
		if u >= 1 then
			rest()
			popHandles[holder] = nil
			return false
		end
		return true
	end, "render")
	popHandles[holder] = { handle = handle, rest = rest }
end

-- Coins ---------------------------------------------------------------------------------------------------------------

local function showCoins(value: number?)
	displayedCoins = value
	local capsule = coins
	if capsule then
		capsule:setText(HudFormat.coinsText(value))
	end
end

-- PR7: the pill's bright flash now (the caller decided it may play).
local function playFlash(big: boolean)
	local capsule = coins
	if capsule == nil or not shown then
		return
	end
	lastFlashAt = os.clock()
	-- PR7: the gap (>= 334 ms) is above the design's 260 ms combo window (H:565): the flip always runs its 560 ms.
	capsule:flash(big, false)
end

-- One coin landing (H:567-577): the sparks every time (n 6, the last coin 12), the bright flash as PR7 allows
-- (HudFormat.flashPlan).
local function landing(big: boolean)
	local spec = FX.events.coinLand
	local anchor = coinIcon
	if anchor then
		local opts = table.clone(spec.sparks) :: any
		opts.colors = UiFx.colors(spec.sparks.colors)
		if big then
			opts.n = spec.big.n
			opts.spread = spec.big.spread
		end
		UiFx.sparks(anchor, opts)
	end
	local now = os.clock()
	local plan, at = HudFormat.flashPlan(now, lastFlashAt, big)
	if plan == "now" then
		playFlash(big)
	elseif plan == "later" and at then
		if laterFlash then
			task.cancel(laterFlash)
		end
		laterFlash = task.delay(math.max(0, at - now), function()
			laterFlash = nil
			playFlash(big)
		end)
	end
end

-- A Coins decrease (H:671-674, G4.10): the number drops at once, the "-N" floats from below the pill's right part
-- (Config.UI.Fx.events.spend.float) and the pill squashes (CoinCapsule:squash; none under ReducedMotion).
local function spend(to: number?, amount: number?)
	showCoins(to)
	local capsule = coins
	if capsule == nil then
		return
	end
	capsule:squash(COIN_MOTION.spend.squash)
	if amount and amount > 0 then
		local f = FX.events.spend.float
		local root = capsule.root
		local at = root.AbsolutePosition + root.AbsoluteSize * Vector2.new(0.5 + f.at.xShare, 0.5 + f.at.yShare)
		local text = Strings.format(Strings.common.minusAmount, { n = Format.coins(amount) })
		UiFx.float(at, text, UiFx.colors({ f.color })[1], f.kind :: any, { rise = f.rise, dx = f.dx })
	end
end

-- The reward label when it can still be flown from (it is cleared once used: one owner, one flight).
local function usableSource(): GuiObject?
	local source = gainSource
	if source == nil or source.Parent == nil or not source.Visible then
		return nil
	end
	return source
end

local function cancelPendingGain()
	local waiting = pendingGain
	pendingGain = nil
	if waiting then
		task.cancel(waiting)
	end
end

local function flyCoins(from: CoinFlight.Source, amount: number, count: number?): boolean
	local anchor = coinIcon
	if anchor == nil or not shown or not finiteNumber(amount) then
		return false
	end
	-- G4.10: the number steps up with each coin from what it shows now (a gain that came first is still held at the
	-- old number: applyCoinAction), never past the newest Coins; the last coin shows the newest (flightShows).
	local base = displayedCoins
	local options: CoinFlight.Options =
		{ parent = UIController.screenGui(OVERLAY_GUI), scale = UIController.scale(), count = count }
	local ok = CoinFlight.play(from, anchor, amount, function(i: number, k: number)
		if i >= k then
			awaitingLanding = false
		end
		if base ~= nil then
			showCoins(HudFormat.flightShows(base :: number, targetCoins, amount, k, i))
		elseif i >= k then
			showCoins(targetCoins)
		end
		-- UI FINAL R2: each landing a semitone higher (the design's coin(i), lib:145; plan §2.2; PR8 batches them).
		SoundController.play(COIN_SOUND, { pitch = SoundController.coinPitch(i) })
		landing(i >= k)
	end, options)
	if ok then
		cancelPendingGain() -- the coins show the held gain coin by coin
		awaitingLanding = true -- the shown number waits for the first landing
	end
	return ok
end

-- A gain that may fly from the result panel's reward label (consumed on use); else the number takes the new value
-- with one landing (G4.11: no "+N", bounce or wiggle).
local function landGain(to: number?, gain: number?)
	local source = usableSource()
	if source and gain and gain >= FLIGHT.minAmount and not Tweens.reducedMotion() then
		gainSource = nil
		if flyCoins(source, gain) then
			return
		end
	end
	showCoins(to)
	if gain and gain > 0 then
		SoundController.play(COIN_SOUND)
		landing(true)
	end
end

local function applyCoinAction(action: HudFormat.CoinAction, previous: number?)
	local kind = action.kind
	if kind ~= "hold" and kind ~= "none" then
		cancelPendingGain() -- this value replaces the held one
	end
	if kind == "set" then
		showCoins(action.to)
	elseif kind == "gain" or kind == "flight" then
		if awaitingLanding then
			if CoinFlight.isFlying() then
				return -- the coins in the air show the newest value when the last one lands
			end
			awaitingLanding = false -- the flight ended without landing (its capsule went away): count as usual
		end
		local gain = action.gain
		if
			kind == "gain"
			and usableSource() == nil
			and gain ~= nil
			and gain >= FLIGHT.minAmount
			and not Tweens.reducedMotion()
		then
			-- G4.10: a claim's StateDelta comes before its reply starts the flight (QuestController.claim): the old
			-- number holds for that flight (flyCoins cancels this), else the gain lands as usual.
			pendingGain = task.delay(COIN_MOTION.flightWaitMs / 1000, function()
				pendingGain = nil
				local from, to = displayedCoins, targetCoins
				if shown and from and to and to > from then
					landGain(to, math.floor(to - from))
				end
			end)
			return
		end
		landGain(action.to, gain)
	elseif kind == "spend" then
		local amount = if previous and action.to then previous - action.to else nil
		spend(action.to, amount)
	end
	-- "hold": the number on screen stays (the HUD is hidden); "none": nothing changed.
end

local function onCoins(value: any)
	local amount = if type(value) == "number" then value else nil
	local previous = targetCoins
	targetCoins = amount
	-- A full Snapshot (a profile recovered after an OFFLINE start, §3.13) replaces the value: no count-up, no "+N".
	local action = HudFormat.coinAction(displayedCoins, previous, amount, shown, StateController.isApplyingFull())
	applyCoinAction(action, previous)
end

-- The HUD shows again (§18.5.2 B1): the gain held since Matched lands now.
local function releaseHeldGain()
	local action = HudFormat.releaseHeld(displayedCoins, targetCoins, usableSource() ~= nil, Tweens.reducedMotion())
	applyCoinAction(action, displayedCoins)
end

-- Layout scheduling (defined with the layout below) ------------------------------------------------------------------

local layoutAll: () -> ()

local function queueLayout()
	if layoutQueued or hudGui == nil then
		return
	end
	layoutQueued = true
	task.defer(function()
		layoutAll()
	end)
end

-- Banner, badges, tracker --------------------------------------------------------------------------------------------

local function refreshBanner()
	local frame, label = bannerFrame, bannerLabel
	if frame == nil or label == nil then
		return
	end
	local status = StateController.dataStatus()
	if HudFormat.isStudioMemory(status) and not studioLogged then
		studioLogged = true
		log:info("Studio memory mode: progress is not saved (the banner is not shown to players)")
	end
	local banner = HudFormat.banner(status)
	local visible = banner ~= nil
	if frame.Visible ~= visible then
		frame.Visible = visible
		queueLayout()
	end
	if banner then
		label.Text = banner.text
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			-- Offline / read-only are data errors (Danger is for error states, §7.2); a pending save is info (Sky).
			stroke.Color = if banner.kind == "warn" then Theme.Colors.danger else Theme.accent("sky").face
			stroke.Thickness = Theme.Sticker.border.normal -- UI FINAL R1: Theme.panel's border (H:203)
		end
	end
end

-- UI FINAL R4: a tile's badge (its count, or the daily "!"; the badge loops sdBadge itself: no pop, G4.11).
local function setBadge(id: string, n: number)
	local tile = badgeTiles[id]
	if tile == nil then
		return
	end
	tile.button:setBadge(if finiteNumber(n) then n else 0)
end

local function refreshBadges()
	setBadge("squishies", #StateController.newOwnedIds())
	local ready = StateController.isProfileReady()
	local quests = StateController.get("quests")
	setBadge("quests", if ready then HudFormat.questBadge(quests) + QuestFormat.starterClaimable(quests) else 0)
	local today = TimeUtil.utcDay(Workspace:GetServerTimeNow())
	setBadge("daily", if ready then HudFormat.dailyBadge(StateController.get("daily"), today) else 0)
end

-- UI FINAL R4 (G4.21): the tracker's picture: the squishy a quest names, else its category's (QuestFormat.iconFor).
local function setTrackerPicture(view: Tracker, card: QuestFormat.Card)
	local icon = QuestFormat.iconFor(card)
	local want = icon.squishy or icon.image
	if want == view.pictureFor then
		return
	end
	view.pictureFor = want
	local old = view.squishy
	if old then
		old:destroy()
		view.squishy = nil
	end
	local picture = view.picture
	if picture then
		picture:Destroy()
		view.picture = nil
	end
	local size = HUD.tracker.iconPx
	if icon.squishy then
		local made = SquishyImage.new(icon.squishy, { size = size, owned = true })
		made.root.AnchorPoint = Vector2.new(0.5, 0.5)
		made.root.Position = UDim2.fromScale(0.5, 0.5)
		made.root.Parent = view.icon
		view.squishy = made
	elseif icon.image then
		local holder = IconGlyph.image(icon.image, { name = "Picture", sizePx = size, parent = view.icon })
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		view.picture = holder
	end
end

-- The quest tracker (spec "Top right"): the unclaimed quest closest to done, Starter tasks first; hidden on the compact
-- layout, before the profile is ready, without a "quests" screen and when there is no quest left.
local function refreshTracker()
	local view = tracker
	if view == nil then
		return
	end
	local quest: QuestFormat.Card? = nil
	if
		UIController.layoutClass() ~= "compact"
		and StateController.isProfileReady()
		and UIController.isRegistered(QUESTS_SCREEN)
	then
		local board = QuestFormat.board(StateController.get("quests"), {
			owned = StateController.owned(),
			equipped = StateController.equipped(),
			now = Workspace:GetServerTimeNow(),
		})
		quest = HudFormat.trackedQuest(board)
	end
	local visible = quest ~= nil
	if view.root.Visible ~= visible then
		view.root.Visible = visible
		queueLayout()
	end
	if quest == nil then
		trackedId = nil
		return
	end
	local picked = quest :: QuestFormat.Card
	setIfChanged(view.title, "Text", picked.title)
	-- UI overhaul: a quest ready to claim says so in Gold (the tracker opens Quests, where Claim is).
	local ready = picked.state == "claim"
	-- UI FINAL R4 (H:995): "Ready to claim!" in the coin yellow with the yellow border, else "+N coins" in #B9AEDA.
	local status = HudFormat.trackerStatus(picked)
	setIfChanged(view.status, "Text", status.text)
	setIfChanged(view.count, "Text", picked.progressText)
	if view.ready ~= ready then
		view.ready = ready
		setIfChanged(view.status, "TextColor3", if ready then Palette.StickerCoinText else Palette.StickerTrackerStatus)
		view.foam:setStroke(if ready then Palette.StickerCoinText else Theme.Colors.inkUI)
		view.bar:setAccent(if ready then "yellow" else "blueBar") -- H:956: the ready bar yellow, else the blue
	end
	setTrackerPicture(view, picked)
	-- A new quest jumps to its share; the same quest moving eases (the bar variant's fillMs, Config.UI.Sticker.bars).
	view.bar:set(picked.fraction, trackedId == picked.id)
	trackedId = picked.id
end

-- Touch areas ---------------------------------------------------------------------------------------------------------

-- The touch areas kept clear on narrow layouts (base px; layoutRects().reserved, which the queue pill keeps clear of):
-- the touch Throw and Ultimate buttons, the jump button right of Throw (on large screens it is taller than Throw) and,
-- with `zone`, the lower-left thumbstick zone (a share of the whole screen, HudFormat.thumbstickZone).
local function reservedRects(canvas: Vector2, zone: boolean): { Rect }
	local list: { Rect } = {}
	local gui = hudGui
	local scale = UIController.scale()
	if gui == nil or scale <= 0 then
		return list
	end
	local ok, layout = pcall(ControlsController.touchLayout, gui.AbsoluteSize, scale, nil)
	if ok and layout then
		for _, rect in { layout.throw, layout.ultimate, layout.jump } do
			table.insert(list, { x = rect.x / scale, y = rect.y / scale, w = rect.w / scale, h = rect.h / scale })
		end
	end
	if zone then
		table.insert(list, HudFormat.thumbstickZone(canvas, screenHeight(), scale))
	end
	return list
end

-- The tiles -----------------------------------------------------------------------------------------------------------

local function visibleTiles(): { string }
	local list: { string } = {}
	for _, id in tileOrder do
		local tile = tiles[id]
		if tile and tile.root.Visible then
			table.insert(list, id)
		end
	end
	return list
end

-- UI FINAL R4: a faceless sticker's picture size, the label's pull over it and its text role (the regular stickers'
-- design ones, H:100-101 / H:158-159; phones the game's smaller tile, PR2's 16 px label).
local function applyStickerLook(button: Button.Button, iconPx: number, pull: number, role: string)
	local icon = button.root:FindFirstChild("Icon", true)
	if icon and icon:IsA("GuiObject") then
		setIfChanged(icon, "Size", UDim2.fromOffset(iconPx, iconPx))
	end
	local content = button.visual:FindFirstChild("Content")
	local list = if content then content:FindFirstChildOfClass("UIListLayout") else nil
	if list then
		setIfChanged(list, "Padding", UDim.new(0, -pull))
	end
	local label = button.root:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") and label:GetAttribute("SD_StickerRole") ~= role then
		label:SetAttribute("SD_StickerRole", role)
		Theme.stickerText(label, role)
		label.TextWrapped = false
	end
end

-- The tiles' size from their labels at the player's text size (Button.widthFor; shared, so the column lines up) and
-- their arrangement from the plan; Hud_Left holds its items stacked or side by side (the plan's `left`); Hud_Nav sits
-- at the design's spot (H:98), or under Hud_Left's real bottom when that reaches lower, and on phones.
local function layoutTiles(canvas: Vector2, compact: boolean)
	local row, grid, left = navRow, navGrid, leftColumn
	if row == nil or grid == nil or left == nil then
		return
	end
	local ids = visibleTiles()
	local textKind: Theme.TextKind = if compact then "Chip" else "D23"
	local iconPx = if compact then COLUMN.tileIconCompactPx else COLUMN.tileIconPx
	local pull = if compact then COLUMN.tileLabelPullCompact else COLUMN.tileLabelPull
	local width = if compact then COLUMN.tileSizeCompact else COLUMN.tileWidth
	for _, id in ids do
		width = math.max(width, Button.widthFor(tileLabels[id] or id, nil, textKind, "tile"))
	end
	local base = if compact then COLUMN.tileSizeCompact else COLUMN.tileHeight
	local height = math.max(base, math.ceil(iconPx - pull + Theme.lineHeight(textKind)))
	local gap = if compact then COLUMN.tileGapCompact else COLUMN.tileGap
	local columns = HudFormat.tilesBox(columnPlan.tiles, #ids, width, height, canvas.X - 2 * EDGE_PX, gap)
	setIfChanged(grid, "CellSize", UDim2.fromOffset(width, height))
	setIfChanged(grid, "CellPadding", UDim2.fromOffset(gap, gap))
	setIfChanged(grid, "FillDirectionMaxCells", math.max(1, columns))
	if tileCompact ~= compact then
		tileCompact = compact
		for _, id in tileOrder do
			applyStickerLook(tiles[id], iconPx, pull, if compact then "small" else "navLabel")
		end
	end
	local origin = HudFormat.origins(compact)
	setIfChanged(left, "Position", UDim2.fromOffset(origin.left.X, origin.left.Y))
	local innerGap, toTiles = HudFormat.leftGaps(compact, columnPlan.grip)
	local list = left:FindFirstChildOfClass("UIListLayout")
	if list then
		local beside = columnPlan.left == "beside"
		setIfChanged(list, "Padding", UDim.new(0, innerGap))
		setIfChanged(
			list,
			"FillDirection",
			if beside then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		)
		setIfChanged(
			list,
			"VerticalAlignment",
			if beside then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top
		)
	end
	local scale = math.max(UIController.scale(), 1e-3)
	local leftBottom = (left.AbsolutePosition.Y - (if hudGui then hudGui.AbsolutePosition.Y else 0)) / scale
		+ left.AbsoluteSize.Y / scale
	if left.AbsoluteSize.Y <= 0 then
		leftBottom = columnPlan.leftBottom
	end
	local under = math.floor(leftBottom + toTiles)
	local top = if compact then under else math.max(origin.nav.Y, under)
	setIfChanged(row, "Position", UDim2.fromOffset(origin.nav.X, top))
end

-- The right column and the DUEL area ----------------------------------------------------------------------------------

local function layoutRight(compact: boolean)
	local right = rightColumn
	if right == nil then
		return
	end
	local origin = HudFormat.origins(compact)
	setIfChanged(right, "Position", UDim2.new(1, -origin.right.X, 0, origin.right.Y))
	local list = right:FindFirstChildOfClass("UIListLayout")
	if list then
		setIfChanged(list, "Padding", UDim.new(0, if compact then GAP_PX else COLUMN.rightGap))
	end
	local settings, slot = settingsButton, settingsSlot
	if settings and slot then
		local label = Strings.hud.nav.settings
		local kind: Theme.TextKind = if compact then "Chip" else "D19"
		local iconPx = if compact then COLUMN.settingsIconCompactPx else COLUMN.settingsIconPx
		local pull = if compact then 0 else COLUMN.settingsLabelPull
		local width = math.max(
			if compact then COLUMN.settingsSize else COLUMN.settingsWidth,
			Button.widthFor(label, nil, kind, "tile")
		)
		local height = math.max(
			if compact then COLUMN.settingsSize else COLUMN.settingsHeight,
			math.ceil(iconPx - pull + Theme.lineHeight(kind))
		)
		applyStickerLook(settings, iconPx, pull, if compact then "small" else "settingsLabel")
		setIfChanged(settings.root, "Size", UDim2.fromOffset(width, height))
		-- The slot keeps the tile's unscaled size, so its hover / press scale never moves the tracker under it.
		setIfChanged(slot, "Size", UDim2.fromOffset(width, height))
		setIfChanged(slot, "Visible", settings.root.Visible)
	end
	if compact then
		refreshTracker() -- hides it on the compact layout
	end
end

-- The DUEL area's state from the queue (HudFormat.ctaModel): the button (and the picker), or the search bar with its
-- time, its second line and your slot; entering the search plays the join's sounds and sparks (H:758-763). Searching
-- -> Matched keeps the search bar (G4.3: the opponent's slot fills there, matchFound, whichever of QueueChanged and
-- DuelChanged comes first) until the queue leaves Matched.
local function refreshCta()
	local wrap, idle, bar = ctaWrap, idleBox, search
	if wrap == nil or idle == nil or bar == nil then
		return
	end
	local queue = StateController.queue()
	local model = HudFormat.ctaModel(queue :: any, Workspace:GetServerTimeNow())
	local queued = model.queued or (ctaQueued and queue.state == "Matched")
	if queued ~= ctaQueued then
		ctaQueued = queued
		idle.Visible = not queued
		local tabs = picker
		if tabs then
			tabs.root.Visible = pickerOn and not queued
		end
		bar.root.Visible = queued
		bar.fills[2].Visible = false -- the opponent's slot fills on Matched (matchFound)
		if queued then
			bar.fills[1].Visible = true
			popIn(bar.pop, MOTION.ctaPop.searchMs, MOTION.ctaPop.searchCurve) -- H:136
			-- H:760-762: slot(0) (whoosh: none, plan RL8) and the burst of 14 at the bar.
			SoundController.play(CLICK_SOUND, { pitch = SoundController.slotPitch(0) })
			local sparks = FX.events.duelJoin.sparks
			UiFx.sparks(bar.root, { n = sparks.n, spread = sparks.spread, colors = UiFx.colors(sparks.colors) })
			Scheduler.add(
				Tweens.keyframes(bar.fills[1], MOTION.slotPop.frames :: any, {
					ms = MOTION.slotPop.ms,
					curve = MOTION.slotPop.curve,
				}),
				"render"
			)
		end
		queueLayout()
	end
	if model.queued then
		setIfChanged(bar.time, "Text", model.time)
		setIfChanged(bar.players, "Text", model.subtext)
	end
end

-- The DUEL press (H:758-762): the testers' mode picks the in-server TDM / FFA queue (MatchJoin; its toasts show the
-- progress), everyone else the 1v1 queue (the "queue" screen; its search bar sounds and sparks on Searching).
local function onDuel(item: HudFormat.NavItem)
	if pickerOn then
		NetController.fire(MATCH_JOIN, mode)
		return
	end
	UIController.open(item.screen, item.params)
end

-- The testers' join feel (H:760-762: slot(0) and the burst of 14 at the DUEL button), once the server took the join
-- (its match.joined Notify; a refusal's match.refused.* toast plays alone).
local function onMatchJoined()
	local button = duelButton
	if not pickerOn or not shown or button == nil then
		return
	end
	SoundController.play(CLICK_SOUND, { pitch = SoundController.slotPitch(0) })
	local sparks = FX.events.duelJoin.sparks
	UiFx.sparks(button.root, { n = sparks.n, spread = sparks.spread, colors = UiFx.colors(sparks.colors) })
end

-- The DUEL area's size as drawn (base px): the search bar (never scaled), or the idle button at its phone scale `s`
-- with the picker (never scaled) `gap` under it (Layout.lipGap: the gap is the design's from the button's face, its
-- lip drawn at `s`), the picker with the design's names or its short ones (`short`).
local function areaSize(buttonWidth: number, s: number, gap: number, short: boolean): Vector2
	if ctaQueued then
		return Vector2.new(searchWidth, COLUMN.barHeight)
	end
	local size = Vector2.new(math.ceil(buttonWidth * s), math.ceil(COLUMN.ctaHeight * s))
	local tabs = picker
	if tabs and pickerOn then
		local extra = tabs:size(short)
		size = Vector2.new(math.max(size.X, extra.X), size.Y + gap + extra.Y)
	end
	return size
end

-- Sizes the DUEL area and places it at the top middle (HudFormat.ctaPlacement), clear of Hud_Left, the tiles with
-- their badges' reach and Hud_Right. Phones draw only the idle button at the compact scale (HudFormat.ctaScales: its
-- holder SD_IdleScale under SD_CtaScale; Hud_DuelIdle takes the drawn size in the area's list); the search bar takes
-- the room the groups leave at full size (HudFormat.barWidth), dropping its dots and second line when narrow
-- (barParts); the testers' picker switches to the design's short mode names (N:711-712 MODES.*.tab) when the area
-- with the full names has no room.
local function layoutCta(canvas: Vector2, compact: boolean)
	local wrap, button, bar = ctaWrap, duelButton, search
	if wrap == nil or button == nil or bar == nil then
		ctaRect = nil
		return
	end
	if compact ~= ctaCompact then
		ctaCompact = compact
		button:setSubtext(if compact then nil else Strings.hud.duelJoin) -- phones: "DUEL" alone (PR2)
	end
	local s = HudFormat.ctaScales(compact).idle
	local scale = ctaScale
	if scale then
		setIfChanged(scale, "Scale", s)
	end
	local gap = Layout.lipGap(HUD.picker.gap, math.round(STICKER.lip.cta * s))
	local list = wrap:FindFirstChildOfClass("UIListLayout")
	if list then
		setIfChanged(list, "Padding", UDim.new(0, gap))
	end
	if not wrap.Visible then
		ctaRect = nil
		return
	end
	local buttonWidth = HudFormat.ctaWidth(false, currentTextScale())
	local idle, holder = idleBox, idleHolder
	if idle and holder then
		setIfChanged(holder, "Size", UDim2.fromOffset(buttonWidth, COLUMN.ctaHeight))
		local drawn = UDim2.fromOffset(math.ceil(buttonWidth * s), math.ceil(COLUMN.ctaHeight * s))
		setIfChanged(idle, "Size", drawn)
	end
	button:setWidth(buttonWidth)
	local blockers: { Rect } = {}
	local tilesRect = rectOf(navRow)
	local tilesReach = if tilesRect then HudFormat.badgeReachRect(tilesRect) else nil
	for _, rect in { rectOf(leftColumn), tilesReach, rectOf(rightColumn) } do
		if rect then
			table.insert(blockers, rect)
		end
	end
	local origin = HudFormat.origins(compact)
	if ctaQueued then
		local low, high = HudFormat.freeSpan(canvas, origin.ctaTop, COLUMN.barHeight, blockers)
		searchWidth = HudFormat.barWidth(HUD.search.width, high - low)
		local parts = HudFormat.barParts(searchWidth)
		setIfChanged(bar.root, "Size", UDim2.fromOffset(searchWidth, COLUMN.barHeight))
		setIfChanged(bar.dots, "Visible", parts.dots)
		setIfChanged(bar.line2, "Visible", parts.line2)
	end
	local function placeFor(short: boolean): (Vector2, HudFormat.CtaPlace)
		local size = areaSize(buttonWidth, s, gap, short)
		return size, HudFormat.ctaPlacement({ canvas = canvas, size = size, blockers = blockers, top = origin.ctaTop })
	end
	local size, place = placeFor(false)
	local tabs = picker
	if tabs and pickerOn and not ctaQueued then
		local short = not place.fits
		if short then
			size, place = placeFor(true)
		end
		tabs:setShort(short)
	end
	ctaFits = place.fits
	setIfChanged(wrap, "Position", UDim2.fromOffset(math.floor(place.x + size.X / 2), math.floor(place.y)))
	ctaRect = { x = place.x, y = place.y, w = size.X, h = size.Y }
	lastCtaRect = ctaRect
end

-- UI FINAL R4: whether the GRIP float shows (HudFormat.gripFloatShown: not on phones, not in first person).
local function gripFloatVisible(): boolean
	local compact = UIController.layoutClass() == "compact"
	return HudFormat.gripFloatShown(shown, gripLevel, compact, FirstPersonController.isActive())
end

-- UI FINAL R4: the GRIP float's place (H:92: top 300 on the 810 px canvas; a shorter canvas keeps that share).
local function layoutGripFloat(canvas: Vector2)
	local float = gripFloat
	if float == nil then
		return
	end
	local top = math.min(HUD.gripFloat.top, canvas.Y * HUD.gripFloat.top / DESIGN_CANVAS_HEIGHT)
	setIfChanged(float, "Position", UDim2.new(0.5, 0, 0, math.floor(top)))
	setIfChanged(float, "Visible", gripFloatVisible())
end

-- Gamepad links -------------------------------------------------------------------------------------------------------

local function firstTile(): GuiObject?
	local id = visibleTiles()[1]
	return if id then tiles[id].root else nil
end

-- The HUD's gamepad links (§11.4, §17.7 "Gamepad"; HudFormat.focusLinks; see the header). Links set before are cleared
-- first, so a part that hid leaves no link behind (the engine's own navigation takes over). Only the links this
-- function set are cleared, and only while they still hold what it set; a direction with no HUD link is left alone.
local function applyFocusLinks()
	for _, write in focusWrites do
		local o = write.object :: any
		if o[write.property] == write.target then
			o[write.property] = nil
		end
	end
	table.clear(focusWrites)
	if not shown then
		return
	end
	local objects: { [string]: GuiObject } = {}
	local function usable(object: GuiObject?): boolean
		return object ~= nil and object.Parent ~= nil and object.Visible
	end
	local function add(list: { string }, key: string, object: GuiObject?)
		if object and usable(object) then
			objects[key] = object
			table.insert(list, key)
		end
	end
	local left: { string } = {}
	add(left, "coins", if coins then coins.root else nil)
	add(left, "grip", focusEntry)
	local tileKeys: { string } = {}
	for _, id in visibleTiles() do
		add(tileKeys, "tile:" .. id, tiles[id].root)
	end
	local right: { string } = {}
	add(right, "settings", if settingsButton then settingsButton.root else nil)
	add(right, "tracker", if tracker then tracker.root else nil)
	-- UI FINAL R4: the mode picker's tabs (testers, while idle).
	local modes: { string } = {}
	local tabs = picker
	if tabs and pickerOn and not ctaQueued and tabs.root.Visible then
		for _, id in tabs.order do
			add(modes, "mode:" .. id, tabs.tabs[id])
		end
	end
	-- One object each (the Duel CTA, the coach card's button, the queue pill's Cancel), or nil.
	local function single(key: string, object: GuiObject?): string?
		if object and usable(object) then
			objects[key] = object
			return key
		end
		return nil
	end
	-- UI FINAL R4: while searching the DUEL area's selectable is the search bar's cancel X (QueueController's "queue").
	local ctaObject = if ctaQueued then focusTargets.queue elseif duelButton then duelButton.root else nil
	local links = HudFormat.focusLinks({
		left = left,
		tiles = tileKeys,
		tileColumns = if navGrid then navGrid.FillDirectionMaxCells else 1,
		right = right,
		coach = single("coach", focusTargets.onboarding),
		cta = single("cta", ctaObject),
		queue = if ctaQueued then nil else single("queue", focusTargets.queue),
		modes = modes,
		-- UI FINAL R4: the queue pill's first hint button (QueueController's "queueHint") under the searching bar.
		hint = if ctaQueued then single("hint", focusTargets.queueHint) else nil,
	})
	for key, link in links do
		local object = objects[key]
		if object then
			for direction, property in FOCUS_PROPERTIES do
				local targetKey = (link :: any)[direction]
				local target = if type(targetKey) == "string" then objects[targetKey] else nil
				if target then
					(object :: any)[property] = target
					table.insert(focusWrites, { object = object, property = property, target = target })
				end
			end
		end
	end
end

-- Layout --------------------------------------------------------------------------------------------------------------

-- Recomputes the left side's plan (HudFormat.leftColumnPlan) and tells the Grip card when it changed.
local function refreshPlan()
	local gui = hudGui
	local size = if gui then gui.AbsoluteSize else Vector2.zero
	local plan = HudFormat.leftColumnPlan(size, UIController.layoutClass(), currentTextScale(), {
		grip = columnGrip,
		touch = isTouch(),
		tiles = #visibleTiles(),
		screenHeight = screenHeight(),
	})
	local changed = not HudFormat.samePlan(columnPlan, plan)
	columnPlan = plan
	if changed then
		HudController.ColumnPlanChanged:fire(plan)
	end
end

layoutAll = function()
	layoutQueued = false
	local gui = hudGui
	local scale = UIController.scale()
	if gui == nil or scale <= 0 or gui.AbsoluteSize.X <= 0 then
		return
	end
	local canvas = gui.AbsoluteSize / scale
	local compact = UIController.layoutClass() == "compact"
	refreshPlan()
	layoutTiles(canvas, compact)
	layoutRight(compact)
	layoutCta(canvas, compact)
	layoutGripFloat(canvas)
	applyFocusLinks()
	HudController.LayoutChanged:fire()
end

local function refreshNav()
	for _, item in HudFormat.NAV do
		local registered = UIController.isRegistered(item.screen)
		if item.place == "tile" then
			local tile = tiles[item.id]
			if tile then
				tile.root.Visible = registered
			end
		elseif item.place == "settings" and settingsButton then
			settingsButton.root.Visible = registered
			if settingsSlot then
				settingsSlot.Visible = registered
			end
		elseif item.place == "cta" and ctaWrap then
			ctaWrap.Visible = (registered or pickerOn) and (shown or holdCta)
		end
	end
	queueLayout()
end

local function setShown(on: boolean)
	-- UI FINAL R4: the design's toast column top (N:197) is the lobby HUD's; duels and matches keep the game's own.
	UIController.setToastTop(if on then HUD.toastTop else nil)
	if on == shown then
		return
	end
	shown = on
	for _, frame in { leftColumn, navRow, rightColumn } do
		if frame then
			frame.Visible = on
		end
	end
	local wrap = ctaWrap
	if wrap then
		-- UI FINAL R4: held up while the opponent's slot fills (matchFound, H:772).
		wrap.Visible = (on or holdCta) and (UIController.isRegistered("queue") or pickerOn)
	end
	if on then
		refreshBanner()
		releaseHeldGain()
	end
	layoutAll()
	HudController.VisibilityChanged:fire(on)
end

-- Builders ------------------------------------------------------------------------------------------------------------

-- Lays the HUD out again when `button`'s label is drawn at a new size (foam fix: a width measured before Fredoka One had
-- loaded was too narrow and broke a tile's word, "Squishie / s"; the label redraws when the font arrives, as the
-- nameplates do). The layout reads TextService, not the label, so this settles after one more pass.
local function relayoutOnText(c: Cleanup.Cleanup, button: Button.Button)
	local label = button.root:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		c:add(label:GetPropertyChangedSignal("TextBounds"):Connect(queueLayout))
	end
end

-- The coin pill (H:75-81): its hover and press feel (Button.decorate without its click: H:75's data-snd tab plays
-- instead, ui.click at Config.Audio.uiPitch.tab); a tap opens the Shop at its top (H:987, G4.16).
local function buildCoins(c: Cleanup.Cleanup, parent: Instance)
	local holder: Frame = Create("Frame", {
		Name = "Hud_Coins",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		LayoutOrder = HudController.LEFT_ORDER.coins,
		ZIndex = 2,
		Parent = parent,
	})
	local capsule = CoinCapsule.new({ name = "Hud_CoinsButton", text = HudFormat.coinsText(nil), parent = holder })
	c:add(capsule)
	c:add(Button.decorate(capsule.root, { clickSound = false }))
	coinIcon = capsule.disc.root
	c:add(capsule.root.Activated:Connect(function()
		SoundController.play(CLICK_SOUND, { pitch = UI_PITCH.tab }) -- H:75 data-snd="tab"
		if UIController.isRegistered(SHOP_SCREEN) then
			UIController.open(SHOP_SCREEN)
		end
	end))
	coinsHolder = holder
	coins = capsule
end

local function buildTiles(c: Cleanup.Cleanup, gui: ScreenGui)
	local row: Frame = Create("Frame", {
		Name = "Hud_Nav",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(COLUMN.navX, COLUMN.navTop),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Parent = gui,
	})
	c:add(row)
	navGrid = Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(COLUMN.tileWidth, COLUMN.tileHeight),
		CellPadding = UDim2.fromOffset(COLUMN.tileGap, COLUMN.tileGap),
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = 1,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local nav = HUD.nav
	local count = 0
	for index, item in HudFormat.NAV do
		if item.place == "tile" then
			local label = Strings.resolve(item.textKey) or item.id
			tileLabels[item.id] = label
			local daily = item.badge == "daily"
			local button = Button.new({
				name = item.button,
				text = label,
				kind = "tile",
				accent = item.accent :: any,
				icon = item.icon,
				iconSize = COLUMN.tileIconPx,
				textKind = "D23",
				textRole = "navLabel", -- H:101
				labelPull = COLUMN.tileLabelPull,
				iconShadow = { px = nav.shadowPx, alpha = nav.shadowAlpha }, -- H:100
				bob = { periodS = nav.bobS, delayS = count * nav.bobStepS }, -- H:100-118
				badgeAccent = if daily then "yellow" else nil, -- H:120
				badgeMark = if daily then "!" else nil,
				badgeDelay = if item.badge then HUD.badgeDelays[item.badge] else nil,
				layoutOrder = index,
				parent = row,
				-- UI FINAL R2 (G2.7): a tile's click is silent by kind (ui.open plays instead); its hover sound plays
				onActivated = function()
					UIController.open(item.screen, item.params)
				end,
			})
			count += 1
			button.root.Visible = false
			c:add(button)
			relayoutOnText(c, button)
			tiles[item.id] = button
			table.insert(tileOrder, item.id)
			if item.badge then
				badgeTiles[item.badge] = { button = button }
			end
		end
	end
	navRow = row
end

-- Foam fix 2: the box the toast column keeps beside for the tiles (Hud_NavReach, nothing drawn): Hud_Nav grown by a
-- count badge's reach (HudFormat.badgeReachRect). It follows Hud_Nav's box, not the badges' own, whose pop and press
-- scales would move the toasts.
local function buildNavReach(c: Cleanup.Cleanup, gui: ScreenGui, row: Frame): Frame
	local reach: Frame = Create("Frame", {
		Name = "Hud_NavReach",
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		Parent = gui,
	})
	c:add(reach)
	local function follow()
		local rect = rectOf(row)
		setIfChanged(reach, "Visible", rect ~= nil)
		if rect then
			local box = HudFormat.badgeReachRect(rect)
			local left, top = math.floor(box.x), math.floor(box.y)
			setIfChanged(reach, "Position", UDim2.fromOffset(left, top))
			setIfChanged(
				reach,
				"Size",
				UDim2.fromOffset(math.ceil(box.x + box.w) - left, math.ceil(box.y + box.h) - top)
			)
		end
	end
	for _, property in { "AbsoluteSize", "AbsolutePosition", "Visible" } do
		c:add(row:GetPropertyChangedSignal(property):Connect(follow))
	end
	follow()
	return reach
end

-- UI FINAL R4 (G4.21): the quest tracker: the plan's purple card (the card surface, H:935: border 4 drawn inside,
-- radius 20, the 2 px highlight at .1, the 5 px lip; a uniform 12 px pad) holding the quest row's insides (H:363-367):
-- the picture's tile (70 px, #EFE6FF, border 4, radius 18, the picture 58), and beside it the title (20 px, its soft
-- drop, PR3) with "x/y" (20 px, stroke 4) 10 apart, the quest bar (H:367) and the status line (H:995). A tap opens
-- Quests.
local function buildTracker(c: Cleanup.Cleanup, parent: Instance)
	local spec = HUD.tracker
	local border = STICKER.border.normal
	local look = STICKER.surfaces.card
	local bands = Layout.stickerBands(border, look.highlightPx, 0, STICKER.lip.card)
	local root: TextButton = Create("TextButton", {
		Name = "Hud_QuestTracker",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(spec.width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 2,
	})
	local foam = Theme.foam(root, {
		radius = STICKER.radius.card,
		stroke = border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
		colors = {
			face = Palette.StickerCardTop,
			faceEnd = Palette.StickerCardBottom,
			top = Palette.StickerCardTop:Lerp(Palette.White, look.highlightAlpha),
			drop = Theme.Colors.inkUI,
		},
	})
	Create("UIPadding", {
		PaddingTop = UDim.new(0, border + spec.pad),
		PaddingLeft = UDim.new(0, border + spec.pad),
		PaddingRight = UDim.new(0, border + spec.pad),
		PaddingBottom = UDim.new(0, bands.drop + spec.pad),
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, spec.gap, root, Enum.HorizontalAlignment.Left)
	Focus.decorate(root, STICKER.radius.card)
	c:add(Button.decorate(root, { fx = "row", clickSound = false })) -- opens a screen: ui.open plays instead

	local icon: Frame = Create("Frame", {
		Name = "Icon",
		BackgroundColor3 = Palette.StickerToyTile,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(spec.iconTile, spec.iconTile),
		LayoutOrder = 1,
		Parent = root,
	})
	Theme.corner(spec.iconRadius, icon)
	local iconStroke = Theme.stroke(Theme.Colors.inkUI, spec.iconBorder, icon)
	pcall(function()
		(iconStroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	local column: Frame = Create("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(spec.iconTile + spec.gap), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Vertical, spec.textGap, column, Enum.HorizontalAlignment.Left)
	local line: Frame = Create("Frame", {
		Name = "Line",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = column,
	})
	Theme.list(Enum.FillDirection.Horizontal, spec.titleGap, line, Enum.HorizontalAlignment.Left) -- H:366
	local title = Theme.label({
		Name = "Title",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = line,
	}, "Button")
	Theme.stickerText(title, "trackerTitle") -- H:366
	title.TextWrapped = true
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = title })
	local count = Theme.label({
		Name = "Count",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = line,
	}, "Button")
	Theme.stickerText(count, "trackerProgress") -- H:366
	count.TextWrapped = false
	local bar = ProgressBar.new({
		name = "Bar",
		variant = "quest", -- H:367
		accent = "blueBar", -- H:956
		layoutOrder = 2,
		parent = column,
	})
	c:add(bar)
	local status = Theme.label({
		Name = "Status",
		LayoutOrder = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = column,
	}, "Small", nil, Palette.StickerTrackerStatus)
	c:add(root.Activated:Connect(function()
		if UIController.isRegistered(QUESTS_SCREEN) then
			UIController.open(QUESTS_SCREEN)
		end
	end))
	root.Parent = parent
	tracker = {
		root = root,
		foam = foam,
		icon = icon,
		picture = nil,
		pictureFor = nil,
		squishy = nil,
		title = title,
		count = count,
		bar = bar,
		status = status,
		ready = false,
	}
	c:add(function()
		local view = tracker
		if view and view.squishy then
			view.squishy:destroy()
		end
	end)
end

local function buildRight(c: Cleanup.Cleanup, gui: ScreenGui)
	local right: Frame = Create("Frame", {
		Name = "Hud_Right",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -COLUMN.rightEdge, 0, COLUMN.rightTop),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Parent = gui,
	})
	c:add(right)
	Theme.list(
		Enum.FillDirection.Vertical,
		COLUMN.rightGap,
		right,
		Enum.HorizontalAlignment.Right,
		Enum.VerticalAlignment.Top
	)
	-- The Settings sticker sits centred in a fixed-size slot (layoutRight sizes both): the list only sees the slot, so
	-- the sticker's hover / press scale never moves the tracker under it.
	local slot: Frame = Create("Frame", {
		Name = "Hud_SettingsSlot",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMN.settingsWidth, COLUMN.settingsHeight),
		Visible = false,
		LayoutOrder = 1,
		Parent = right,
	})
	local item = HudFormat.navAt("settings")[1]
	local settingsLook = HUD.settings
	local settings = Button.new({
		name = item.button,
		text = Strings.resolve(item.textKey) or item.id,
		kind = "tile",
		fx = item.fx :: any, -- UI FINAL R2: "icon" (H:157), not the tiles' "nav"
		accent = item.accent :: any,
		icon = item.icon,
		iconSize = COLUMN.settingsIconPx,
		textKind = "D19",
		textRole = "settingsLabel", -- H:159
		labelPull = COLUMN.settingsLabelPull,
		iconShadow = { px = settingsLook.shadowPx, alpha = settingsLook.shadowAlpha }, -- H:158
		width = COLUMN.settingsWidth,
		height = COLUMN.settingsHeight,
		parent = slot,
		-- UI FINAL R2 (G2.7): a tile's click is silent by kind (ui.open plays instead); its hover sound plays
		onActivated = function()
			UIController.open(item.screen, item.params)
		end,
	})
	settings.root.AnchorPoint = Vector2.new(0.5, 0.5)
	settings.root.Position = UDim2.fromScale(0.5, 0.5)
	settings.root.Visible = false
	c:add(settings)
	relayoutOnText(c, settings)
	settingsButton = settings
	settingsSlot = slot
	buildTracker(c, right)
	local banner = Theme.panel({
		Name = "Hud_DataBanner",
		Size = UDim2.fromOffset(COLUMN.bannerWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 3,
		Parent = right,
	}, Theme.Radius.button, Theme.Padding.medium)
	bannerLabel = Theme.label({ Name = "Text", Parent = banner }, "Small")
	bannerFrame = banner
	rightColumn = right
end

-- One queue slot (H:141): the 24 px trough with its 3 px ink border, radius 8, and its 18 px fill (radius 5, the
-- 3 px highlight at .55) in `top` -> `bottom`, hidden until it fills.
local function buildSlot(parent: Instance, order: number, top: Color3, bottom: Color3): Frame
	local spec = HUD.slots
	local slot: Frame = Create("Frame", {
		Name = "Slot" .. order,
		BackgroundColor3 = Theme.Colors.track,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(spec.px, spec.px),
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.corner(spec.radius, slot)
	local stroke = Theme.stroke(Theme.Colors.inkUI, spec.border, slot)
	pcall(function()
		(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	local fill: Frame = Create("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(spec.fill, spec.fill),
		Visible = false,
		Parent = slot,
	})
	Theme.foam(fill, {
		radius = spec.fillRadius,
		stroke = 0,
		top = spec.highlightPx,
		fixedHeight = spec.fill,
		colors = { face = top, faceEnd = bottom, top = top:Lerp(Palette.White, spec.highlightAlpha) },
	})
	return fill
end

-- The search bar (H:135-146) in the DUEL area: the purple pill (border 5 inside, radius 28, the 4 px highlight at .12,
-- the 7 px lip), padding 0 14 0 104 inside the border, the 108 px emblem pulsing at (-6, -10) of its padding edge;
-- "Finding match" (24 px, stroke 5), the three pink dots (sdDot, .2 s apart) and the time pushed right (16 px #FFE36B);
-- under them the two slots (you mint, the opponent pink, H:983) and the queue line (16 px #EDE4FF, PR2, 6 px further);
-- the cancel X's slot at its right end (QueueController parents its Queue_CancelButton there).
local function buildSearch(c: Cleanup.Cleanup, parent: Instance): SearchBar
	local spec = HUD.search
	local border = STICKER.border.heavy
	local lip = STICKER.lip.search
	local root: Frame = Create("Frame", {
		Name = "Hud_DuelSearch",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(spec.width, COLUMN.barHeight),
		Visible = false,
		LayoutOrder = 1,
		Parent = parent,
	})
	local pop: Frame = Create("Frame", {
		Name = "SD_Pop",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = pop,
	})
	local look = STICKER.surfaces.search
	local bands = Layout.stickerBands(border, look.highlightPx, 0, lip)
	Theme.foam(face, {
		radius = STICKER.radius.duel,
		stroke = border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
		colors = Theme.surfaceColors(Theme.accent("plum"), "search", true),
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, border + spec.padLeft),
		PaddingRight = UDim.new(0, border + spec.padRight),
		PaddingTop = UDim.new(0, border),
		PaddingBottom = UDim.new(0, bands.drop),
		Parent = face,
	})
	Theme.list(Enum.FillDirection.Horizontal, spec.gap, face, Enum.HorizontalAlignment.Left)
	local emblem = IconGlyph.image("img.nav.duel", { name = "Emblem", sizePx = spec.emblemPx, parent = pop })
	-- Centre-anchored: its sdPulse (a UIScale, which scales about the AnchorPoint) breathes about its centre (CSS 50%).
	local half = spec.emblemPx / 2
	emblem.AnchorPoint = Vector2.new(0.5, 0.5)
	emblem.Position = UDim2.fromOffset(border + spec.emblemX + half, border + spec.emblemY + half)
	emblem.ZIndex = 2
	local emblemLoop = UiIdle.add(emblem, "pulse", { periodS = spec.emblemPulseS }) -- H:137
	local column: Frame = Create("Frame", {
		Name = "Texts",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = face,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = column })
	Theme.list(Enum.FillDirection.Vertical, spec.columnGap, column, Enum.HorizontalAlignment.Left)
	local line1: Frame = Create("Frame", {
		Name = "Line1",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = column,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		spec.line1Gap,
		line1,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Bottom
	)
	local title = Theme.label({
		Name = "Title",
		Text = Strings.hud.findingMatch,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = line1,
	}, "Big")
	Theme.stickerText(title, "button") -- H:139: 24 px, stroke 5
	title.TextWrapped = false
	local dots: Frame = Create("Frame", {
		Name = "Dots",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(3 * spec.dotPx + 2 * spec.dotGap, spec.dotPx),
		LayoutOrder = 2,
		Parent = line1,
	})
	Theme.list(Enum.FillDirection.Horizontal, spec.dotGap, dots, Enum.HorizontalAlignment.Left)
	local loops: { UiIdle.Handle } = {}
	if emblemLoop then
		table.insert(loops, emblemLoop)
	end
	for i = 1, 3 do
		local cell: Frame = Create("Frame", {
			Name = "Dot" .. i,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(spec.dotPx, spec.dotPx),
			LayoutOrder = i,
			Parent = dots,
		})
		local dot: Frame = Create("Frame", {
			Name = "Dot",
			BackgroundColor3 = Palette.StickerPinkSoft, -- H:139
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Parent = cell,
		})
		Theme.corner(spec.dotPx, dot)
		local loop = UiIdle.add(dot, "dot", { delayS = (i - 1) * spec.dotDelayS }) -- H:139: 0, .2, .4 s
		if loop then
			table.insert(loops, loop)
		end
	end
	local spacer: Frame = Create("Frame", {
		Name = "Push",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 1),
		LayoutOrder = 3,
		Parent = line1,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = spacer })
	local time = Theme.label({
		Name = "Time",
		Text = "",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 4,
		Parent = line1,
	}, "Small")
	Theme.stickerText(time, "searchTime") -- H:139
	time.TextWrapped = false
	local line2: Frame = Create("Frame", {
		Name = "Line2",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = column,
	})
	Theme.list(Enum.FillDirection.Horizontal, spec.line2Gap, line2, Enum.HorizontalAlignment.Left)
	local fills = {
		buildSlot(line2, 1, Palette.StickerSlotMintTop, Palette.StickerGripEnd), -- you (H:983)
		buildSlot(line2, 2, Palette.StickerSlotPinkTop, Palette.StickerSlotPinkEnd), -- the opponent (H:983)
	}
	local players = Theme.label({
		Name = "Players",
		Text = "",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 3,
		Parent = line2,
	}, "Small", nil, Theme.Colors.ink2)
	Create("UIPadding", { PaddingLeft = UDim.new(0, spec.playersPad), Parent = players }) -- H:142 margin-left 6
	local cancelSlot: Frame = Create("Frame", {
		Name = "CancelSlot",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Config.UI.Touch.minTarget, Config.UI.Touch.minTarget),
		LayoutOrder = 2,
		Parent = face,
	})
	c:add(function()
		for _, loop in loops do
			loop:remove()
		end
	end)
	return {
		root = root,
		pop = pop,
		dots = dots,
		time = time,
		line2 = line2,
		fills = fills,
		players = players,
		cancelSlot = cancelSlot,
	}
end

-- MATCH FOUND (H:148-152) in SD_Overlay (SD_Hud hides from Matched, G4.2): the gold pill (#FFF3A6 -> #FFC23A at 60%
-- -> #F59A12, the 4 px highlight at .65, the 8 px bevel towards the found tint, border 5, radius 28, the 7 px lip),
-- padding 0 24 0 120 inside the border, match.svg (112) pulsing at (4, -18) of its padding edge, "MATCH FOUND!" (36 px,
-- stroke 7, drop 4) over "Opponent: {name}" (17 px #5A3200, plan FD2).
local function buildFound(c: Cleanup.Cleanup): FoundBar
	local spec = HUD.found
	local border = STICKER.border.heavy
	local lip = STICKER.lip.search
	local root: Frame = Create("Frame", {
		Name = "Hud_MatchFound",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(spec.width, COLUMN.barHeight),
		Visible = false,
		Parent = UIController.screenGui(OVERLAY_GUI),
	})
	c:add(root)
	local pop: Frame = Create("Frame", {
		Name = "SD_Pop",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = pop,
	})
	local look = STICKER.surfaces.found
	local bands = Layout.stickerBands(border, look.highlightPx, look.bevelPx or 0, lip)
	local gold: Theme.Accent = {
		face = Palette.StickerGoldMid,
		shade = Palette.StickerGoldEnd,
		light = false,
		top = Palette.StickerCreamYellow,
		mid = Palette.StickerGoldMid,
		midAt = spec.midAt,
	}
	Theme.foam(face, {
		radius = STICKER.radius.duel,
		stroke = border,
		inner = true,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.surfaceColors(gold, "found", true),
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, border + spec.padLeft),
		PaddingRight = UDim.new(0, border + spec.padRight),
		PaddingTop = UDim.new(0, border),
		PaddingBottom = UDim.new(0, bands.drop),
		Parent = face,
	})
	Theme.list(Enum.FillDirection.Horizontal, spec.gap, face, Enum.HorizontalAlignment.Left)
	local icon = IconGlyph.image("img.icon.match", { name = "Icon", sizePx = spec.iconPx, parent = pop })
	local half = spec.iconPx / 2 -- centre-anchored for its sdPulse (see buildSearch)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromOffset(border + spec.iconX + half, border + spec.iconY + half)
	icon.ZIndex = 2
	local iconLoop = UiIdle.add(icon, "pulse", { periodS = spec.iconPulseS }) -- H:150
	if iconLoop then
		c:add(function()
			iconLoop:remove()
		end)
	end
	local texts: Frame = Create("Frame", {
		Name = "Texts",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = face,
	})
	Theme.list(Enum.FillDirection.Vertical, spec.columnGap, texts, Enum.HorizontalAlignment.Left)
	local title = Theme.label({
		Name = "Title",
		Text = Strings.hud.matchFound,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = texts,
	}, "Found")
	Theme.stickerText(title, "found") -- H:151
	title.TextWrapped = false
	local sub = Theme.label({
		Name = "Opponent",
		Text = "",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = texts,
	}, "D17", nil, Palette.StickerFoundText) -- H:151: 17 px #5A3200 (dark: no outline)
	sub.TextWrapped = false
	return { root = root, pop = pop, sub = sub }
end

-- The DUEL area (see the header): the wrap at the top middle, the idle box (the DUEL button over its soft shadow,
-- H:126 T2, in SD_IdleScale, whose UIScale SD_CtaScale draws only it at the phone scale), the testers' mode picker
-- under it and the search bar (both never scaled: PR1, PR2).
local function buildCta(c: Cleanup.Cleanup, gui: ScreenGui)
	local wrap: Frame = Create("Frame", {
		Name = "Hud_CtaWrap",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, COLUMN.ctaTop),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		Parent = gui,
	})
	c:add(wrap)
	Theme.list(
		Enum.FillDirection.Vertical,
		COLUMN.pickerGap,
		wrap,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Top
	)
	local cta = HUD.cta
	local idle: Frame = Create("Frame", {
		Name = "Hud_DuelIdle",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(cta.width, COLUMN.ctaHeight),
		LayoutOrder = 1,
		Parent = wrap,
	})
	-- The button at its base size, scaled about its top-left corner into Hud_DuelIdle's drawn size (layoutCta).
	local holder: Frame = Create("Frame", {
		Name = "SD_IdleScale",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(cta.width, COLUMN.ctaHeight),
		Parent = idle,
	})
	ctaScale = Create("UIScale", { Name = "SD_CtaScale", Parent = holder })
	local shadowBox: Frame = Create("Frame", {
		Name = "ShadowBox",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Button.CTA_HEIGHT), -- the face: CSS shadows are of the border box, not the lip
		ZIndex = 0,
		Parent = holder,
	})
	Theme.softShadow(shadowBox, "img.fx.shadowCta", {
		offsetY = cta.shadowY,
		blurPx = cta.shadowBlur,
		alpha = cta.shadowAlpha,
		color = Palette.StickerShadowCta,
	})
	local item = HudFormat.navAt("cta")[1]
	local border = STICKER.border.heavy
	local button = Button.new({
		name = item.button,
		text = Strings.hud.duelCta,
		kind = "cta",
		accent = item.accent :: any,
		textKind = "Duel",
		textRole = "duel", -- H:130
		subtext = Strings.hud.duelJoin,
		subtextRole = "duelSub", -- H:131 (PR3)
		textGap = cta.textGap, -- H:129
		-- H:126: padding 0 24 0 128 inside the 5 px border (the border is drawn inside the face here)
		padLeft = border + cta.padLeft,
		padRight = border + cta.padRight,
		align = "left",
		width = cta.width,
		parent = holder,
		clickSound = false, -- H:126 data-snd="none": the join plays its own sounds (G2.7); the hover sound stays
		onActivated = function()
			onDuel(item)
		end,
	})
	button.root.ZIndex = 1
	c:add(button)
	-- H:128: the emblem at (-10, -24) of the padding edge, bobbing 2.4 s, with its drop shadow (5 px at .3).
	local emblem = IconGlyph.image("img.nav.duel", {
		name = "Emblem",
		sizePx = cta.emblemPx,
		shadow = { px = cta.emblemShadowPx, alpha = cta.emblemShadowAlpha },
		parent = button.visual,
	})
	emblem.Position = UDim2.fromOffset(border + cta.emblemX - (border + cta.padLeft), border + cta.emblemY)
	emblem.ZIndex = 2
	local bob = UiIdle.add(emblem, "bob", { periodS = cta.emblemBobS })
	if bob then
		c:add(function()
			bob:remove()
		end)
	end
	-- The testers' mode picker (N:154-158).
	local player = Players.LocalPlayer
	pickerOn = HudFormat.pickerShown(if player then player.UserId else nil)
	if pickerOn then
		local spec = HUD.picker
		local tdm = spec.tdmStops
		local tabs = SegmentedTabs.new({
			name = "Hud_DuelModes",
			tabs = {
				{
					id = "tdm",
					label = Strings.hud.modes.tdm,
					chip = Strings.hud.modes.tdmChip,
					short = Strings.hud.modes.tdmShort,
					rotation = spec.tdmRotation,
					stops = {
						{ at = tdm[1], color = Palette.StickerTdmRedTop },
						{ at = tdm[2], color = Palette.StickerTdmRed },
						{ at = tdm[3], color = Palette.StickerTdmBlue },
						{ at = tdm[4], color = Palette.StickerTdmBlueEnd },
					},
				},
				{
					id = "ffa",
					label = Strings.hud.modes.ffa,
					chip = Strings.hud.modes.ffaChip,
					short = Strings.hud.modes.ffaShort,
					rotation = spec.ffaRotation,
					stops = {
						{ at = 0, color = Palette.StickerYellowTop },
						{ at = 1, color = Palette.StickerGoldMid },
					},
				},
			},
			selected = mode,
			layoutOrder = 2,
			parent = wrap,
			onSelect = function(id: string)
				mode = id
				SoundController.play(CLICK_SOUND, { pitch = UI_PITCH.tab }) -- N:1254: tab()
			end,
		})
		c:add(tabs)
		picker = tabs
	end
	search = buildSearch(c, wrap)
	found = buildFound(c)
	-- The title only: the second line never changes the button's width (it is fixed).
	relayoutOnText(c, button)
	duelButton = button
	idleBox = idle
	idleHolder = holder
	ctaWrap = wrap
	ctaCompact = false
	ctaQueued = false
end

-- UI FINAL R4 (H:92-96): the GRIP float: "GRIP" (18 px #9AF5D2, stroke 5) and the level (40 px, stroke 8, drop 4),
-- 6 px apart on one baseline (drawn bottom-aligned), floating 3.6 s (sdFloat on its inner holder).
local function buildGripFloat(c: Cleanup.Cleanup, gui: ScreenGui)
	local root: Frame = Create("Frame", {
		Name = "Hud_GripFloat",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HUD.gripFloat.top),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Visible = false,
		Active = false,
		Parent = gui,
	})
	c:add(root)
	local float: Frame = Create("Frame", {
		Name = "SD_Float",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Active = false,
		Parent = root,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		HUD.gripFloat.gap,
		float,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Bottom
	)
	local tag = Theme.label({
		Name = "Tag",
		Text = Strings.grip.levelTag,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = float,
	}, "Body")
	Theme.stickerText(tag, "gripTag") -- H:94
	tag.TextWrapped = false
	local level = Theme.label({
		Name = "Level",
		Text = "",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = float,
	}, "Hero")
	Theme.stickerText(level, "hero") -- H:95
	level.TextWrapped = false
	local loop = UiIdle.add(float, "float", { periodS = HUD.gripFloat.periodS }) -- H:93
	if loop then
		c:add(function()
			loop:remove()
		end)
	end
	gripFloat = root
	gripLevelLabel = level
end

-- Keys 1-5 (H:653-654): the window of the key, or closing it when it is the one on top; nothing while the HUD hides
-- or the window is not registered.
local function navKey(index: number): boolean?
	local id = NAV_KEYS[index]
	if not shown or id == nil then
		return nil
	end
	for _, item in HudFormat.navAt("tile") do
		if item.id == id and UIController.isRegistered(item.screen) then
			if UIController.topModal() == item.screen then
				UIController.close(item.screen, "key")
			else
				UIController.open(item.screen, item.params)
			end
			return true
		end
	end
	return nil
end

-- Public --------------------------------------------------------------------------------------------------------------

-- The top-left column under the coin capsule. Add cards with LayoutOrder from LEFT_ORDER (e.g. the Grip card).
function HudController.leftColumn(): Frame?
	return leftColumn
end

-- The object DPadUp selects first (the Grip card, §17.7), the column's second item. nil = the first tile.
function HudController.setFocusEntry(object: GuiObject?)
	focusEntry = object
	if object then
		Focus.decorate(object, Theme.Radius.panel)
	end
	applyFocusLinks()
end

-- A selectable object another module owns, for the gamepad links: "onboarding" (the coach card's visible button),
-- "queue" (the queue's Cancel: UI FINAL R4, the search bar's cancel X) or "queueHint" (UI FINAL R4: the queue pill's
-- first hint button); nil while it hides.
function HudController.setFocusTarget(key: string, object: GuiObject?)
	if focusTargets[key] == object then
		return
	end
	if object then
		focusTargets[key] = object
	else
		focusTargets[key] = nil
	end
	applyFocusLinks()
end

-- Whether a column card ("grip") wants to show (it has something to show and is not held back by a duel). The plan
-- then decides its layout.
function HudController.setColumnItem(key: string, present: boolean)
	if key ~= "grip" or columnGrip == present then
		return
	end
	columnGrip = present
	refreshPlan()
	queueLayout()
end

-- UI FINAL R4 (H:92-96): the Grip level the GRIP float shows; nil hides it (no Grip state, or a duel holds it back).
function HudController.setGripLevel(level: number?)
	gripLevel = if finiteNumber(level) then level else nil
	local label = gripLevelLabel
	if label and gripLevel then
		setIfChanged(label, "Text", tostring(math.floor(gripLevel :: number)))
	end
	local float = gripFloat
	if float then
		setIfChanged(float, "Visible", gripFloatVisible())
	end
end

-- UI FINAL R4: the GRIP float's level number (GripController pops it on a level up, §18.5.1 A9), or nil.
function HudController.gripLevelLabel(): TextLabel?
	return gripLevelLabel
end

-- UI FINAL R4: the search bar's cancel slot (QueueController parents its Queue_CancelButton there, H:145).
function HudController.cancelSlot(): Frame?
	local bar = search
	return if bar then bar.cancelSlot else nil
end

-- The duel HUD's top bar's bottom in SD_Overlay's base px while it shows (SD_DuelHud enabled, the bar visible), or nil.
local function duelTopBarBottom(): number?
	local duelGui = UIController.screenGui(DUEL_GUI)
	local bar = duelGui:FindFirstChild(DUEL_TOP_BAR)
	local overlay = UIController.screenGui(OVERLAY_GUI)
	local scale = UIController.scale()
	if not duelGui.Enabled or bar == nil or not bar:IsA("GuiObject") or not bar.Visible or scale <= 0 then
		return nil
	end
	if bar.AbsoluteSize.Y <= 0 then
		return nil
	end
	return (bar.AbsolutePosition.Y + bar.AbsoluteSize.Y - overlay.AbsolutePosition.Y) / scale
end

local function stopFoundFollow()
	local follow = foundFollow
	foundFollow = nil
	if follow then
		follow:clean()
	end
end

-- UI FINAL R4 (G4.2, G4.3; H:767-775): Matched: the opponent's slot fills (with the slot sound, i = 1), the DUEL area
-- stays up foundSwapDelayMs, then MATCH FOUND pops in at its last place in SD_Overlay (HudFormat.foundSpot: under the
-- duel HUD's top bar once that shows, followed while it moves) with the sparks, the ring, the jolt and ui.toast,
-- showing `text` ("Opponent: {name}"), for Config.UI.Queue.matchedBannerSeconds or until dismiss(). Replaces
-- QueueController's banner for this case; the handle has UIController.BannerHandle's shape.
function HudController.matchFound(text: string): FoundHandle
	foundToken += 1
	local token = foundToken
	local bar, wrap, view = search, ctaWrap, found
	if bar and wrap and ctaQueued then
		holdCta = true
		wrap.Visible = true
		local fill = bar.fills[2]
		fill.Visible = true
		Scheduler.add(
			Tweens.keyframes(fill, MOTION.slotPop.frames :: any, {
				ms = MOTION.slotPop.ms,
				curve = MOTION.slotPop.curve,
			}),
			"render"
		)
		SoundController.play(CLICK_SOUND, { pitch = SoundController.slotPitch(1) }) -- H:768
	end
	local handle = {} :: FoundHandle
	local live = true
	local function hide()
		live = false
		local v = found
		if v and token == foundToken then
			v.root.Visible = false
			stopFoundFollow()
		end
	end
	task.delay(HUD.found.swapDelayMs / 1000, function()
		if token ~= foundToken then
			return
		end
		local rect = ctaRect or lastCtaRect -- read before the area hides (a hidden area has no rect)
		holdCta = false
		local w = ctaWrap
		if w and not shown then
			w.Visible = false
		end
		if view == nil or not live then
			return
		end
		local canvas = HudController.layoutRects().canvas
		local width = math.min(HUD.found.width, math.max(0, canvas.X - 2 * EDGE_PX))
		view.root.Size = UDim2.fromOffset(width, COLUMN.barHeight)
		local compact = UIController.layoutClass() == "compact"
		local function place()
			if token == foundToken and live then
				local spot = HudFormat.foundSpot(rect, canvas, compact, duelTopBarBottom())
				view.root.Position = UDim2.fromOffset(math.floor(spot.X), math.floor(spot.Y))
			end
		end
		place()
		-- Overlays fix (the old matched banner's): DuelController turns its top bar on during Preparing; follow it.
		stopFoundFollow()
		local follow = Cleanup.new()
		foundFollow = follow
		local duelGui = UIController.screenGui(DUEL_GUI)
		follow:add(duelGui:GetPropertyChangedSignal("Enabled"):Connect(place))
		local topBar = duelGui:FindFirstChild(DUEL_TOP_BAR)
		if topBar and topBar:IsA("GuiObject") then
			for _, property in { "AbsoluteSize", "AbsolutePosition", "Visible" } do
				follow:add(topBar:GetPropertyChangedSignal(property):Connect(place))
			end
		end
		view.sub.Text = text
		view.root.Visible = true
		popIn(view.pop, MOTION.ctaPop.foundMs, MOTION.ctaPop.foundCurve) -- H:149
		local event = FX.events.matchFound -- H:773-775
		local sparks = table.clone(event.sparks) :: any
		sparks.colors = UiFx.colors(event.sparks.colors)
		UiFx.sparks(view.root, sparks)
		local ring = event.rings[1]
		UiFx.ring(view.root, UiFx.colors({ ring.color })[1], ring.size)
		UiFx.jolt(view.pop, event.jolt)
		SoundController.play(TOAST_SOUND)
		task.delay(Config.UI.Queue.matchedBannerSeconds, function()
			if token == foundToken then
				hide()
			end
		end)
	end)
	function handle.setText(_: FoundHandle, newText: string)
		text = newText
		local v = found
		if v and token == foundToken then
			v.sub.Text = newText
		end
	end
	function handle.dismiss(_: FoundHandle)
		hide()
	end
	function handle.isShown(_: FoundHandle): boolean
		return live and token == foundToken
	end
	return handle
end

-- The left side's current plan (HudFormat.leftColumnPlan): the Grip card's layout and the tiles' arrangement.
function HudController.columnPlan(): HudFormat.ColumnPlan
	return columnPlan
end

-- The player's GuiService.PreferredTextSize multiplier (Config.UI.PreferredTextScale; 1 when unknown).
function HudController.textScale(): number
	return currentTextScale()
end

-- The HUD's groups in SD_Hud's base px (see Rects): the coach card and the queue pill keep clear of them.
function HudController.layoutRects(): Rects
	local gui = hudGui
	local scale = UIController.scale()
	local canvas = if gui and scale > 0 then gui.AbsoluteSize / scale else COLUMN.fallbackScreen
	local coach = if gui then gui:FindFirstChild(COACH_NAME) else nil
	return {
		canvas = canvas,
		left = rectOf(leftColumn),
		tiles = rectOf(navRow),
		right = rectOf(rightColumn),
		cta = if ctaWrap and ctaWrap.Visible then ctaRect else nil,
		coach = if coach and coach:IsA("GuiObject") then rectOf(coach) else nil,
		reserved = if isNarrow() then reservedRects(canvas, true) else {},
	}
end

-- A HUD element by name: "coins", "squishies", "boxes", "shop", "quests", "daily", "duel", "settings", "tracker" (for
-- onboarding pulses and Studio checks).
function HudController.element(name: string): GuiObject?
	if name == "coins" then
		return if coins then coins.root else nil
	elseif name == "duel" then
		return if duelButton then duelButton.root else nil
	elseif name == "settings" then
		return if settingsButton then settingsButton.root else nil
	elseif name == "tracker" then
		return if tracker then tracker.root else nil
	end
	local tile = tiles[name]
	return if tile then tile.root else nil
end

-- Where "+X Coins" flies to (§9.14): the coin disc.
function HudController.coinsAnchor(): GuiObject?
	return coinIcon or coinsHolder
end

-- Flies "+amount" coins from `from` (a GuiObject, a GUI-space point or a world point) into the coin disc (§18.5.2 B2).
-- The shown number steps up from the first landing (G4.10). Returns false when nothing flies (the HUD is hidden,
-- amount < coinFlight.minAmount without a count, ReducedMotion): the number then follows StateDelta as usual.
-- UI FINAL R2 (G2.8): `count` coins fly (a claim passes Config.UI.Fx.events.questClaim / dailyClaim.coins, a paid
-- squeeze 1; R8 wires them), else the design's 8 (H:663).
function HudController.flyCoins(from: CoinFlight.Source, amount: number, count: number?): boolean
	return flyCoins(from, amount, count)
end

-- UI FINAL R4 (H:676): a spend the Coins do not cover: the pill's "no" shake (12 px, PR5) and the error toast "Not
-- enough coins!", silent (the press already played ui.error, H:643). Its coin icon and red face come with R9's toasts.
function HudController.denyCoins()
	local capsule = coins
	if capsule and shown then
		capsule:shake()
	end
	UIController.toast(Strings.hud.notEnoughCoins, "error", { sound = false })
end

-- The result panel's reward label, which the duel reward flies from once the HUD shows again (§18.5.2 B1, B7); nil
-- when that panel closes. DuelController hands it over; the HUD uses it at most once.
function HudController.setGainSource(label: GuiObject?)
	gainSource = label
end

-- Studio (§18.11 juice check 9; SD_DebugClient "juice coinFlight"): a flight of `amount` from the screen centre into
-- the coin disc, without changing Coins. Returns whether it flew.
function HudController.debugCoinFlight(amount: number?): boolean
	local overlay = UIController.screenGui(OVERLAY_GUI)
	local centre = overlay.AbsolutePosition + overlay.AbsoluteSize / 2
	return flyCoins(centre, if finiteNumber(amount) then amount :: number else FLIGHT.minAmount * 4)
end

function HudController.isShown(): boolean
	return shown
end

-- Small table for Studio debug hooks.
function HudController.debugState(): { [string]: any }
	local visibleNav = visibleTiles()
	if settingsButton and settingsButton.root.Visible then
		table.insert(visibleNav, "settings")
	end
	if ctaWrap and ctaWrap.Visible then
		table.insert(visibleNav, "duel")
	end
	local plan = columnPlan
	return {
		shown = shown,
		coins = targetCoins,
		displayedCoins = displayedCoins,
		flyingCoins = CoinFlight.liveCount(),
		gainSource = gainSource ~= nil,
		nav = visibleNav,
		banner = if bannerFrame and bannerFrame.Visible and bannerLabel then bannerLabel.Text else nil,
		-- The left side's plan in base px (HudFormat.leftColumnPlan).
		column = {
			grip = plan.grip,
			left = plan.left,
			tiles = plan.tiles,
			columns = if navGrid then navGrid.FillDirectionMaxCells else nil,
			bottom = plan.bottom,
			limit = plan.limit,
			narrow = plan.narrow,
			fits = plan.fits,
			items = { grip = columnGrip },
		},
		tracker = trackedId,
		-- fits: the top middle has room for it (HudFormat.ctaPlacement); rect: its box in base px.
		cta = {
			queued = ctaQueued,
			compact = ctaCompact,
			fits = ctaFits,
			rect = ctaRect,
			picker = pickerOn,
			mode = mode,
			searchWidth = searchWidth,
			idleScale = if ctaScale then ctaScale.Scale else nil, -- HudFormat.ctaScales: phones scale only the button
		},
		gripLevel = gripLevel,
		gripFloat = gripFloat ~= nil and gripFloat.Visible, -- HudFormat.gripFloatShown
		textScale = currentTextScale(),
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function HudController.init()
	local c = Cleanup.new()
	cleanup = c
	local gui = UIController.screenGui(HUD_GUI)
	hudGui = gui

	local left: Frame = Create("Frame", {
		Name = "Hud_Left",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(COLUMN.leftX, COLUMN.leftTop),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Parent = gui,
	})
	c:add(left)
	Theme.list(
		Enum.FillDirection.Vertical,
		COLUMN.leftGap,
		left,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	leftColumn = left
	buildCoins(c, left)
	buildTiles(c, gui)
	buildRight(c, gui)
	buildCta(c, gui)
	buildGripFloat(c, gui)
	-- Overlays fix (2026-10-09): toasts keep beside the HUD groups (on a phone the tile row ran under them). Foam fix 2:
	-- beside the tiles with their badges' reach (Hud_NavReach). Lobby HUD (spec 2026-10-11): they start under the DUEL
	-- area at the top middle (then under the coach card or the queue pill right under it: NotifyFormat chains them).
	local navReach = if navRow then buildNavReach(c, gui, navRow) else nil
	UIController.toastsBeside("hud", left, navReach, rightColumn)
	UIController.toastsBelow("cta", ctaWrap)

	c:add(StateController.changed("coins"):connect(onCoins))
	c:add(StateController.changed("equipped"):connect(refreshTracker))
	c:add(StateController.changed("dataStatus"):connect(function()
		refreshBanner()
		refreshBadges()
		refreshTracker()
	end))
	c:add(StateController.changed("quests"):connect(function()
		refreshBadges()
		refreshTracker()
	end))
	c:add(StateController.changed("owned"):connect(refreshTracker))
	c:add(StateController.changed("daily"):connect(refreshBadges))
	c:add(StateController.NewOwnedChanged:connect(refreshBadges))
	c:add(StateController.QueueChanged:connect(function()
		refreshCta()
	end))
	c:add(StateController.LobbyLockChanged:connect(function(isLocked: boolean)
		setShown(not isLocked)
	end))
	c:add(UIController.LayoutChanged:connect(function()
		refreshTracker()
		queueLayout()
	end))
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout))
	c:add(ControlsController.PreferredInputChanged:connect(queueLayout))
	-- UI FINAL R4: the GRIP float hides in first person (gripFloatVisible).
	c:add(FirstPersonController.Changed:connect(queueLayout))
	c:add(NetController.onNotify(function(code: string)
		if code == MATCH_JOINED then
			onMatchJoined()
		end
	end))
	-- The thumbstick zone is a share of the whole screen (the camera's viewport), not only of SD_Hud.
	local camera = Workspace.CurrentCamera
	if camera then
		c:add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(queueLayout))
	end
	-- The plan and the sizes follow the player's text size.
	local textOk, textSignal = pcall(function(): RBXScriptSignal
		return GuiService:GetPropertyChangedSignal("PreferredTextSize")
	end)
	if textOk then
		c:add(textSignal:Connect(queueLayout))
	end
	-- A part that changes size moves what sits next to it (positions only: no loop).
	local watched: { GuiObject } = { left }
	if rightColumn then
		table.insert(watched, rightColumn)
	end
	for _, object in watched do
		c:add(object:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout))
	end
	c:add(ControlsController.bindAction(FOCUS_ACTION, function(inputState: Enum.UserInputState): boolean?
		if inputState ~= Enum.UserInputState.Begin then
			return nil
		end
		-- §17.7: the Grip card while it shows, else the first tile (HudFormat.dpadUpTarget: also when the entry is set
		-- but not on screen, e.g. no Grip state yet).
		local entry = focusEntry
		local first = firstTile()
		local entryShown = entry ~= nil and entry.Visible and entry.Parent ~= nil
		local pick = HudFormat.dpadUpTarget(shown, entryShown, first ~= nil)
		local target = if pick == "entry" then entry elseif pick == "row" then first else nil
		if target then
			return Focus.select(target)
		end
		return nil
	end))
	-- UI FINAL R4 (H:653-654): the keys 1-5, in the lobby (NavN) and over an open window (ModalNavN).
	for index in NAV_KEYS do
		for _, prefix in { "Nav", "ModalNav" } do
			c:add(ControlsController.bindAction(prefix .. index, function(inputState: Enum.UserInputState): boolean?
				if inputState ~= Enum.UserInputState.Begin then
					return nil
				end
				return navKey(index)
			end))
		end
	end
	c:add(function()
		if laterFlash then
			task.cancel(laterFlash)
			laterFlash = nil
		end
		for _, pop in popHandles do
			pop.handle:disconnect()
		end
		table.clear(popHandles)
		cancelPendingGain()
		stopFoundFollow()
		CoinFlight.clear()
		awaitingLanding = false
		gainSource, coinIcon, lastFlashAt = nil, nil, nil
		table.clear(tiles)
		table.clear(tileOrder)
		table.clear(tileLabels)
		table.clear(badgeTiles)
		tileCompact = nil
		leftColumn, coinsHolder, coins = nil, nil, nil
		navRow, navGrid, rightColumn, settingsButton, tracker, trackedId = nil, nil, nil, nil, nil, nil
		settingsSlot = nil
		bannerFrame, bannerLabel = nil, nil
		ctaWrap, ctaScale, idleBox, duelButton, picker, search, found = nil, nil, nil, nil, nil, nil, nil
		idleHolder, lastCtaRect = nil, nil
		ctaRect, ctaFits, ctaQueued, ctaCompact, holdCta = nil, nil, false, false, false
		pickerOn, mode, searchWidth = false, DEFAULT_MODE, HUD.search.width
		gripFloat, gripLevelLabel, gripLevel = nil, nil, nil
		focusEntry, hudGui, layoutQueued = nil, nil, false
		table.clear(focusTargets)
		table.clear(focusWrites)
		columnGrip = false
	end)

	onCoins(StateController.get("coins"))
	refreshBanner()
	refreshCta()
	setShown(not StateController.isLobbyLocked())
	layoutAll()
end

function HudController.start()
	-- Every screen registers in its init(), so the HUD is complete now.
	refreshNav()
	refreshBadges()
	refreshTracker()
	local c = cleanup
	if c == nil then
		return
	end
	local ok, err = pcall(function()
		c:add(SoundController.setZoneSource(WorldBinder.currentZone, WorldBinder.ZoneChanged))
	end)
	if not ok then
		log:warn("audio zones not connected:", err)
	end
	c:add(task.spawn(function()
		while true do
			task.wait(DAY_CHECK_SECONDS)
			refreshBadges()
			refreshTracker()
		end
	end))
	-- The search bar's clock (the queue pill's own clock, whole seconds).
	c:add(task.spawn(function()
		while true do
			task.wait(QUEUE_TICK_SECONDS)
			if StateController.queue().state == SEARCHING then
				local okTick, errTick = pcall(function(): any
					refreshCta()
					return nil
				end)
				if not okTick then
					log:error("DUEL search bar update failed:", errTick)
				end
			end
		end
	end))
	-- UI FINAL R4 (H:763, H:768; AFFECTED 2026-10-15: the 1v1 search's pacing): every tickMs while the search bar
	-- shows, its tick(false), the 900 Hz blip (ui.hover at Config.Audio.uiPitch.tick.lo).
	c:add(task.spawn(function()
		while true do
			task.wait(HUD.search.tickMs / 1000)
			if ctaQueued and shown then
				SoundController.play(HOVER_SOUND, { pitch = UI_PITCH.tick.lo })
			end
		end
	end))
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function HudController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return HudController
