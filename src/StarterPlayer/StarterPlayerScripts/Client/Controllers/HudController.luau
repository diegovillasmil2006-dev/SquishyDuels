--!strict
-- HudController (client only). DESIGN §11.6 (lobby HUD), §11.2 (layout, phone zones), §11.3 (states), §11.4 / §11.7
-- (DPadUp focuses the HUD), §9.13 (coin counter), §3.13 (data banner), §17.7 (the Grip card slot); the foam UI restyle
-- (spec docs/superpowers/specs/2026-10-09-foam-ui-restyle-design.md "Lobby HUD", kit guide 2026-10-09-foam-ui-
-- components.md). Everything lives in SD_Hud and is hidden from Matched through Returning (StateController lobby lock:
-- "Hidden during duels"; the Grip card inside the left column hides with it, §17.2).
--
-- * Top-left column (Hud_Left): the coin capsule (Hud_Coins / Hud_CoinsButton, UI/Components/CoinCapsule: the coin disc
--   over a Frosting capsule with Format.coins); a change counts up over coinCounter.countUpMs and a gain floats "+N" up
--   while fading over floatMs (Config.UI.motion; no float or count-up under ReducedMotion), with the ui.coin sound.
--   Foam fix 2: the "+N" starts right of the capsule at its middle and rises HudFormat.gainRise (at most floatPx, never
--   past the HUD's top; from the capsule's top it floated into Roblox's top bar), its outline fading with it. Foam fix
--   3: on phones (the Grip card beside the capsule, where that "+N" printed over the card) it sits on the capsule's top
--   edge over the number's end in the small display kind (HudFormat.gainSpot); it reads "+12,450" (gainText). Tapping
--   it opens the Shop's Coins tab once a "shop" screen exists. Under it GripController adds the Grip card
--   (LEFT_ORDER.grip).
-- * The tiles (Hud_Nav, under Hud_Left): Squishies (Strawberry), Boxes (Lilac), Shop (the Shop accent), Quests (the
--   quest mint), Daily (Sky blue) as foam tiles with a placeholder icon (IconGlyph) and their label; a tile shows only
--   when its screen is registered (checked at start, after every init), so no button opens nothing. Count badges
--   (UI/Components/CountBadge on the tile's corner): new squishies (StateController.newOwnedIds), claimable daily quests
--   plus claimable starter tasks (UI/QuestFormat.starterClaimable), an unclaimed daily reward (today's logic). Foam fix
--   2: the tiles start a badge's reach plus air under Hud_Left (HudFormat.leftGaps), and the toast column keeps beside
--   Hud_NavReach, Hud_Nav grown by that reach (buildNavReach).
-- * Top right (Hud_Right): the Settings gear tile (Hud_SettingsButton, Frosting), the quest tracker card
--   (Hud_QuestTracker: the unclaimed quest closest to done, Starter tasks first, HudFormat.trackedQuest; tap opens
--   Quests; hidden when there is none and on the compact layout) and the data banner (Hud_DataBanner, HudFormat.banner:
--   a pending save, offline, read-only or the server's line; Studio memory mode is only logged, never shown).
-- * Lobby HUD (spec 2026-10-11): no equipped card at the bottom (the dock went: the Squishies tile opens the list,
--   which equips and inspects; V still opens Inspect) and no HUD side of a squeeze panel.
-- * Top middle: the Duel CTA (Hud_DuelButton, a "cta" Button: the swords placeholder icon, "DUEL" and "Join the
--   queue"; it opens QueueController's non-modal "queue" screen, which sends QueueJoin). While the queue is Searching it
--   shows the queued state like the queue pill (Sky blue, the clock icon, "IN QUEUE" and "Searching · 0:23",
--   HudFormat.ctaModel); pressing it then does what it always did (joinAsync refuses while queued). Its place is
--   HudFormat.ctaPlacement on every layout: COLUMN.edge from the top, centred, moved only as far as Hud_Left, the tiles
--   (with their badges' reach) and Hud_Right need; medium-sized on phones. The toasts start under it (UIController
--   .toastsBelow "cta"), then under the coach card or the queue pill right under it (NotifyFormat chains them).
-- * Lobby audio zones: WorldBinder (a higher layer than SoundController) is connected to SoundController here (reading).
-- * Feel pass (§18.5.2 B1, B2, B5; pure rules in UI/HudFormat): the capsule has the Button press feel (silent: it opens
--   the Shop, so ui.open plays); every gain bounces it and wiggles the coin disc; a spend squishes it and counts down;
--   the gain held from Matched to Returning lands when the HUD shows again (a flight from the result panel's reward
--   label, setGainSource, or a count-up); flyCoins(from, amount) is the one place coin flights start (UI/CoinFlight
--   into SD_Overlay, landing on the coin disc); under ReducedMotion no flight, bounce or wiggle. A tile's badge pops when
--   its count rises. The tiles, Settings, the tracker and the CTA open screens: silent (ui.open plays).
-- * Layout (Part 8 device pass, rebuilt for the foam HUD; pure maths in UI/HudFormat): HudFormat.leftColumnPlan picks the
--   Grip card's layout (regular / compact, GripController reads columnPlan()), whether Hud_Left holds the coin capsule
--   and the Grip card stacked or side by side and the tiles' arrangement (a column, two columns, or a row) so the left
--   side ends above the thumbstick zone on narrow layouts (compact class or touch input; the zone is a share of the
--   whole screen, Camera.ViewportSize, foam fix) and on screen elsewhere, for the HUD's size, layout class, input and
--   GuiService.PreferredTextSize. Lobby HUD (spec 2026-10-11): phones follow the PC layout, the tiles in two columns
--   under the column (they may reach into the thumbstick zone, the user's choice), the capsule and the Grip card side
--   by side only when that keeps the top-middle CTA clear. The tiles sit under Hud_Left's real bottom; everything is
--   laid out again (deferred, at most once a frame) when a size, the class, the input, the text size or a visible part
--   changes, and when a label's TextBounds changes (foam fix: widths measured before Fredoka One loaded broke
--   "Squishie / s"); LayoutChanged then tells the coach card and the queue pill (they place themselves from
--   layoutRects(), under the CTA).
-- * Hover / press (foam fix): the Settings tile sits in a fixed-size slot and the Duel CTA grows from its centre, so the
--   press feel's scale never moves what is next to them (the Grip card has its own slot, GripController).
-- * Gamepad (HudFormat.focusLinks): the left column top to bottom (the coin capsule, the Grip card = the DPadUp entry,
--   the tiles), the right column (Settings, the tracker) and the links between them: the Duel CTA between the left
--   column and Settings, Down to the queue pill's Cancel or the coach card's button (both Up back to it), a tile -> the
--   CTA. Only the links this module set are cleared again.
-- UI overhaul (2026-10-11, Candy UI): the tiles are bold candy tiles with larger icons (COLUMN.tileIconPx) and red
-- notification badges; Settings is the plum neutral; the quest tracker turns Gold with hud.questReady when its quest
-- is ready to claim (tap opens Quests); the Duel CTA gets one gloss sweep (Button:sweep) every CTA_SWEEP_SECONDS while
-- it shows and is not queued (no bounce loop; nothing under ReducedMotion). The coach card moved to the bottom middle
-- (OnboardingController), so the centre column stays open.
-- Public: leftColumn(), LEFT_ORDER, setFocusEntry(object?), setFocusTarget(key, object?), element(name), coinsAnchor(),
-- isShown(), VisibilityChanged, LayoutChanged, layoutRects(), flyCoins(from, amount), setGainSource(label?),
-- debugCoinFlight(amount), columnPlan(), ColumnPlanChanged, setColumnItem(key, present), textScale(), debugState().

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
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
local Theme = require(Client.UI.Theme)
local Tweens = require(Client.Anim.Tweens)
local ControlsController = require(script.Parent.ControlsController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

export type Rect = HudFormat.Rect
-- The HUD's groups in SD_Hud's base px (layoutRects), nil while hidden: the queue pill and the coach card keep clear.
export type Rects = {
	canvas: Vector2,
	left: Rect?, -- Hud_Left (the coin capsule and the Grip card)
	tiles: Rect?, -- Hud_Nav (the tiles)
	right: Rect?, -- Hud_Right (Settings, the tracker, the data banner)
	cta: Rect?, -- Hud_DuelButton (the top middle)
	coach: Rect?, -- Hud_OnboardingCard (OnboardingController)
	reserved: { Rect }, -- narrow layouts: the thumbstick zone, the touch Throw / Ultimate buttons and the jump button
}

type BadgeTile = { button: Button.Button, scale: UIScale? }
type Tracker = {
	root: TextButton,
	section: TextLabel,
	title: TextLabel,
	bar: ProgressBar.ProgressBar,
	count: TextLabel,
	ready: boolean?, -- UI overhaul: the shown quest is ready to claim (Gold)
}

-- Constants

local HUD_GUI = "SD_Hud"
local OVERLAY_GUI = "SD_Overlay"
local COIN_MOTION = Config.UI.motion.coinCounter
local FLIGHT = Config.UI.motion.coinFlight
local BADGE_POP = Config.UI.motion.badgePop
local MAX_FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
-- ReducedMotion "+N": shown this long, then faded over MAX_FADE_MS (§18.5.2 B2).
local STATIC_GAIN_SECONDS = 0.5
local COLUMN = HudFormat.COLUMN
local EDGE_PX = COLUMN.edge
local GAP_PX = COLUMN.rowGap
-- The quest tracker card.
local TRACKER_ICON_PX = 20
local TRACKER_BAR_PX = 14
-- The Duel CTA: the content's room over its bands (UI FINAL R1: Button's cta sticker, the border and highlight on top,
-- the bevel, the border and the lip at the bottom); its icon gap and air are COLUMN.ctaLineGap / ctaAir (shared with
-- HudFormat.ctaWidth).
local CTA_STYLE = Button.style("cta")
local CTA_BANDS_PX = CTA_STYLE.top + CTA_STYLE.bevel + CTA_STYLE.drop
local QUEUE_TICK_SECONDS = 0.25 -- the queued CTA's clock shows whole seconds
local CTA_SWEEP_SECONDS = 7 -- UI overhaul: the idle Duel CTA's gloss sweep, this often
local DAY_CHECK_SECONDS = 30 -- reading: how often the daily badge re-checks the UTC day
local SHOP_SCREEN = "shop"
local QUESTS_SCREEN = "quests"
local COIN_SOUND = "ui.coin"
local FOCUS_ACTION = "FocusHud"
local COACH_NAME = "Hud_OnboardingCard" -- OnboardingController's coach card (a stable name)
local SEARCHING = "Searching"
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
local floatLayer: Frame? = nil
local navRow: Frame? = nil
local navGrid: UIGridLayout? = nil
local tiles: { [string]: Button.Button } = {}
local tileOrder: { string } = {}
local tileLabels: { [string]: string } = {} -- a tile's label (its width follows the widest one)
local badgeTiles: { [string]: BadgeTile } = {}
local badgeCounts: { [string]: number } = {}
local rightColumn: Frame? = nil
local settingsSlot: Frame? = nil -- the Settings tile's fixed-size holder in Hud_Right (its hover never moves the list)
local settingsButton: Button.Button? = nil
local tracker: Tracker? = nil
local trackedId: string? = nil
local bannerFrame: Frame? = nil
local bannerLabel: TextLabel? = nil
local duelButton: Button.Button? = nil
local ctaQueued = false
local ctaCompact = false
local ctaRect: Rect? = nil
local ctaFits: boolean? = nil -- HudFormat.ctaPlacement's answer (debugState)
local focusEntry: GuiObject? = nil
local focusTargets: { [string]: GuiObject } = {} -- setFocusTarget ("onboarding": the coach card's button; "queue")
local shown = true
local displayedCoins: number? = nil
local targetCoins: number? = nil
local countHandle: Scheduler.Handle? = nil
local countEffect: Tweens.CountUp? = nil
local coinsFeel: Button.Decorated? = nil
local coinIcon: GuiObject? = nil
local wiggleHandle: Scheduler.Handle? = nil
local lastBounceAt = -math.huge
local awaitingLanding = false -- coins are in the air and the count waits for the first landing
local gainSource: GuiObject? = nil -- the result panel's reward label (setGainSource)
local columnGrip = false -- the Grip card wants to show (setColumnItem "grip")
local columnPlan: HudFormat.ColumnPlan = HudFormat.leftColumnPlan(COLUMN.fallbackScreen, "regular", 1)
-- The NextSelection* links the last applyFocusLinks set (object, property, target): only those are cleared again.
type FocusWrite = { object: GuiObject, property: string, target: GuiObject }
local focusWrites: { FocusWrite } = {}
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

-- Coins ---------------------------------------------------------------------------------------------------------------

local function setCoinsText(value: number?)
	local capsule = coins
	if capsule then
		capsule.label.Text = HudFormat.coinsText(value)
	end
end

local function stopCount()
	if countEffect then
		countEffect:cancel()
		countEffect = nil
	end
	if countHandle then
		countHandle:disconnect()
		countHandle = nil
	end
end

-- Foam fix 2: the "+N" starts right of the capsule at its middle (from its top it floated into Roblox's top bar) and
-- rises at most floatPx, never past the HUD's top. Foam fix 3: on phones, where the Grip card sits right of the
-- capsule, it sits on the capsule's top edge over the number's end instead (HudFormat.gainSpot), and its number has
-- the capsule's thousands separator (HudFormat.gainText).
local function gainPosition(spot: HudFormat.GainSpot, rise: number): UDim2
	return UDim2.new(1, spot.x, spot.yScale, spot.y - math.floor(rise))
end

local function gainLabel(layer: Frame, amount: number, spot: HudFormat.GainSpot): (TextLabel, UIStroke)
	local label = Theme.label({
		Name = "Gain",
		Text = HudFormat.gainText(amount),
		AnchorPoint = Vector2.new(spot.anchorX, 0.5),
		Position = gainPosition(spot, 0),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = layer,
	}, spot.kind)
	-- The small kind takes the thin outline (2 px closed up its comma and digits, like the reticle's small text).
	local thickness = if spot.kind == "HudNumber" then Theme.Stroke.medium else Theme.Stroke.thin
	local stroke: UIStroke = Create("UIStroke", { Color = Theme.Colors.white, Thickness = thickness, Parent = label })
	if spot.kind ~= "HudNumber" then
		Theme.noOutline(label) -- UI FINAL R1: the small "+N" keeps only its thin outline, as before
	end
	return label, stroke
end

-- The "+N" of a gain: floats coinCounter.floatPx up while fading (§9.13). Under ReducedMotion it stays still for
-- STATIC_GAIN_SECONDS, then fades in <= reducedMotionMaxFadeMs (§18.5.2 B2), timed from its own Scheduler effect.
-- Foam fix 2: its outline fades with it (it stayed whole until the end, a white "+N" left hanging).
local function showGain(amount: number)
	local layer = floatLayer
	if layer == nil then
		return
	end
	local spot = HudFormat.gainSpot(columnPlan.left == "beside", columnPlan.pillHeight, currentTextScale())
	local label, stroke = gainLabel(layer, amount, spot)
	if not Tweens.reducedMotion() then
		local tween = Tweens.play(label, COIN_MOTION.floatMs, {
			Position = gainPosition(spot, spot.rise),
			TextTransparency = 1,
		})
		Tweens.play(stroke, COIN_MOTION.floatMs, { Transparency = 1 })
		tween.Completed:Once(function()
			label:Destroy()
		end)
		return
	end
	local elapsed = 0
	local fade = MAX_FADE_MS / 1000
	Scheduler.add(function(dt: number): boolean
		elapsed += dt
		if label.Parent == nil or elapsed >= STATIC_GAIN_SECONDS + fade then
			label:Destroy()
			return false
		end
		local transparency = math.clamp((elapsed - STATIC_GAIN_SECONDS) / fade, 0, 1)
		label.TextTransparency = transparency
		stroke.Transparency = transparency
		return true
	end, "render")
end

-- Counts the shown number from `from` to `to` over `ms` (at once under ReducedMotion or for ms <= 0).
local function startCount(
	from: number?,
	to: number?,
	ms: number,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
)
	stopCount()
	if to == nil then
		return
	end
	if from == nil or ms <= 0 or Tweens.reducedMotion() then
		displayedCoins = to
		setCoinsText(to)
		return
	end
	local effect = Tweens.countUp(from, to, ms, function(n: number)
		displayedCoins = n
		setCoinsText(math.floor(n + 0.5))
	end, style, direction)
	countEffect = effect
	countHandle = Scheduler.add(effect, "render")
end

-- The capsule bounce and the coin disc wiggle of a gain (§18.5.2 B1); at most once per bounceMinGapMs (a flight's
-- coins land 45 ms apart).
local function bounce()
	if Tweens.reducedMotion() then
		return
	end
	local now = os.clock()
	if now - lastBounceAt < FLIGHT.bounceMinGapMs / 1000 then
		return
	end
	lastBounceAt = now
	local pill = COIN_MOTION.pillBounce
	if coinsFeel then
		coinsFeel:pulse(pill.scale, pill.upMs, pill.downMs)
	end
	local icon = coinIcon
	if icon == nil then
		return
	end
	if wiggleHandle then
		wiggleHandle:disconnect()
	end
	local elapsed = 0
	wiggleHandle = Scheduler.add(function(dt: number): boolean
		elapsed += dt
		local rotation, done = HudFormat.iconWiggle(elapsed)
		icon.Rotation = rotation
		if done then
			wiggleHandle = nil
			return false
		end
		return true
	end, "render")
end

-- A Coins decrease (Part 7 spending): the capsule squishes and the number counts down, no float (§18.5.2 B1).
local function spend(to: number?)
	local motion = COIN_MOTION.spend
	if coinsFeel and not Tweens.reducedMotion() then
		coinsFeel:pulse(motion.scale, motion.downMs, motion.upMs)
	end
	startCount(displayedCoins, to, motion.countMs, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- A gain counted up at the capsule: count-up, "+N", bounce, ui.coin.
local function countUpGain(to: number?, gain: number?)
	startCount(displayedCoins, to, COIN_MOTION.countUpMs, COIN_MOTION.style, COIN_MOTION.direction)
	if gain and gain > 0 then
		showGain(gain)
		bounce()
		SoundController.play(COIN_SOUND)
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

local function flyCoins(from: CoinFlight.Source, amount: number): boolean
	local anchor = coinIcon
	if anchor == nil or not shown or not finiteNumber(amount) then
		return false
	end
	local options: CoinFlight.Options = { parent = UIController.screenGui(OVERLAY_GUI), scale = UIController.scale() }
	local ok = CoinFlight.play(from, anchor, amount, function(i: number, k: number)
		bounce()
		SoundController.play(COIN_SOUND)
		if i == 1 then
			awaitingLanding = false
			startCount(displayedCoins, targetCoins, CoinFlight.countMs(k), COIN_MOTION.style, COIN_MOTION.direction)
		end
	end, options)
	if ok then
		-- The shown number waits for the first landing.
		awaitingLanding = true
		stopCount()
	end
	return ok
end

-- A gain that may fly from the result panel's reward label (consumed on use), else counts up at the capsule.
local function landGain(to: number?, gain: number?)
	local source = usableSource()
	if source and gain and gain >= FLIGHT.minAmount and not Tweens.reducedMotion() then
		gainSource = nil
		if flyCoins(source, gain) then
			return
		end
	end
	countUpGain(to, gain)
end

local function applyCoinAction(action: HudFormat.CoinAction)
	local kind = action.kind
	if kind == "set" then
		stopCount()
		displayedCoins = action.to
		setCoinsText(action.to)
	elseif kind == "gain" or kind == "flight" then
		if awaitingLanding then
			if CoinFlight.isFlying() then
				return -- the coins in the air count up to the newest value when they land
			end
			awaitingLanding = false -- the flight ended without landing (its capsule went away): count as usual
		end
		landGain(action.to, action.gain)
	elseif kind == "spend" then
		spend(action.to)
	end
	-- "hold": the number on screen stays (the HUD is hidden); "none": nothing changed.
end

local function onCoins(value: any)
	local amount = if type(value) == "number" then value else nil
	local previous = targetCoins
	targetCoins = amount
	-- A full Snapshot (a profile recovered after an OFFLINE start, §3.13) replaces the value: no count-up, no "+N".
	local action = HudFormat.coinAction(displayedCoins, previous, amount, shown, StateController.isApplyingFull())
	applyCoinAction(action)
end

-- The HUD shows again (§18.5.2 B1): the gain held since Matched lands now.
local function releaseHeldGain()
	local action = HudFormat.releaseHeld(displayedCoins, targetCoins, usableSource() ~= nil, Tweens.reducedMotion())
	applyCoinAction(action)
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

local function setBadge(id: string, n: number)
	local tile = badgeTiles[id]
	if tile == nil then
		return
	end
	local count = if finiteNumber(n) then n else 0
	tile.button:setBadge(count)
	-- §18.5.2 B5: the badge pops when its count rises (the first value is the silent baseline).
	local previous = badgeCounts[id]
	badgeCounts[id] = count
	if previous == nil or count <= previous or HudFormat.badgeText(count) == nil then
		return
	end
	local badge = tile.button.root:FindFirstChild("Badge")
	if badge == nil or not badge:IsA("GuiObject") then
		return
	end
	local scale = tile.scale
	if scale == nil or scale.Parent ~= badge then
		scale = Create("UIScale", { Name = "Pop", Parent = badge })
		tile.scale = scale
	end
	Tweens.scale(scale :: UIScale, BADGE_POP.from, 1, {
		ms = BADGE_POP.ms,
		style = Enum.EasingStyle.Back,
		direction = Enum.EasingDirection.Out,
	})
end

local function refreshBadges()
	setBadge("squishies", #StateController.newOwnedIds())
	local ready = StateController.isProfileReady()
	local quests = StateController.get("quests")
	setBadge("quests", if ready then HudFormat.questBadge(quests) + QuestFormat.starterClaimable(quests) else 0)
	local today = TimeUtil.utcDay(Workspace:GetServerTimeNow())
	setBadge("daily", if ready then HudFormat.dailyBadge(StateController.get("daily"), today) else 0)
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
	setIfChanged(
		view.section,
		"Text",
		if ready
			then Strings.hud.questReady
			elseif picked.kind == "starter" then Strings.quest.section.starter
			else Strings.quest.section.daily
	)
	setIfChanged(view.count, "Text", picked.progressText)
	setIfChanged(view.section, "TextColor3", if ready then Theme.Colors.gold else Theme.Colors.ink2)
	if view.ready ~= ready then
		view.ready = ready
		view.bar:setAccent(if ready then "gold" else "mint")
	end
	-- A new quest jumps to its share; the same quest moving eases (Config.UI.motion.barFill).
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

-- The tiles' size from their labels at the player's text size (Button.widthFor; shared, so the column lines up) and
-- their arrangement from the plan; Hud_Left holds its items stacked or side by side (the plan's `left`); Hud_Nav sits
-- under Hud_Left's real bottom.
local function layoutTiles(canvas: Vector2, compact: boolean)
	local row, grid, left = navRow, navGrid, leftColumn
	if row == nil or grid == nil or left == nil then
		return
	end
	local ids = visibleTiles()
	local base = if compact then COLUMN.tileSizeCompact else COLUMN.tileSize
	local iconPx = if compact then COLUMN.tileIconCompactPx else COLUMN.tileIconPx
	local width = base
	for _, id in ids do
		width = math.max(width, Button.widthFor(tileLabels[id] or id, nil, "Chip", "tile"))
	end
	local height = math.max(base, math.ceil(iconPx + COLUMN.tileLabelGap + Theme.lineHeight("Chip") + COLUMN.tileBands))
	local columns = HudFormat.tilesBox(columnPlan.tiles, #ids, width, height, canvas.X - 2 * EDGE_PX)
	setIfChanged(grid, "CellSize", UDim2.fromOffset(width, height))
	setIfChanged(grid, "FillDirectionMaxCells", math.max(1, columns))
	for _, id in ids do
		local glyph = tiles[id].root:FindFirstChild("Icon", true)
		if glyph and glyph:IsA("GuiObject") then
			setIfChanged(glyph, "Size", UDim2.fromOffset(iconPx, iconPx))
		end
	end
	local innerGap, gap = HudFormat.leftGaps(compact, columnPlan.grip)
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
	local top = math.floor(leftBottom + gap)
	setIfChanged(row, "Position", UDim2.fromOffset(EDGE_PX, top))
end

-- The right column and the CTA ----------------------------------------------------------------------------------------

local function layoutRight(compact: boolean)
	local right = rightColumn
	if right == nil then
		return
	end
	setIfChanged(right, "Position", UDim2.new(1, -EDGE_PX, 0, EDGE_PX))
	local settings, slot = settingsButton, settingsSlot
	if settings and slot then
		local label = Strings.hud.nav.settings
		local width = math.max(COLUMN.settingsSize, Button.widthFor(label, nil, "Chip", "tile"))
		local height = math.max(
			COLUMN.settingsSize,
			math.ceil(COLUMN.settingsIconPx + COLUMN.tileLabelGap + Theme.lineHeight("Chip") + COLUMN.tileBands)
		)
		setIfChanged(settings.root, "Size", UDim2.fromOffset(width, height))
		-- The slot keeps the tile's unscaled size, so its hover / press scale never moves the tracker under it.
		setIfChanged(slot, "Size", UDim2.fromOffset(width, height))
		setIfChanged(slot, "Visible", settings.root.Visible)
	end
	if compact then
		refreshTracker() -- hides it on the compact layout
	end
end

-- The CTA's style for the layout class: the title's text kind and the icon size (phones: a medium CTA).
local function applyCtaStyle(compact: boolean)
	local button = duelButton
	if button == nil then
		return
	end
	ctaCompact = compact
	local label = button.root:FindFirstChild("Label", true)
	if label and label:IsA("TextLabel") then
		Theme.text(label, if compact then "H2" else "Title")
		label.TextWrapped = false
		Theme.textOnColor(label)
	end
	local glyph = button.root:FindFirstChild("Icon", true)
	if glyph and glyph:IsA("GuiObject") then
		local px = if compact then COLUMN.ctaCompactIconPx else COLUMN.ctaIconPx
		glyph.Size = UDim2.fromOffset(px, px)
	end
end

-- The CTA's texts, accent and icon from the queue (HudFormat.ctaModel; spec "While queued it shows the queued state").
local function refreshCta()
	local button = duelButton
	if button == nil then
		return
	end
	local queue = StateController.queue()
	local model = HudFormat.ctaModel(queue, Workspace:GetServerTimeNow())
	if model.queued ~= ctaQueued then
		ctaQueued = model.queued
		button:setAccent(if model.queued then "sky" else "strawberry")
		button:setIcon(if model.queued then "clock" else "duel")
		queueLayout()
	end
	button:setText(model.title)
	-- Phones keep the medium CTA: "DUEL" alone; the queued clock always shows.
	button:setSubtext(if ctaCompact and not model.queued then nil else model.subtext)
end

-- Sizes the CTA for its texts and places it at the top middle (HudFormat.ctaPlacement), clear of Hud_Left, the tiles
-- with their badges' reach and Hud_Right.
local function layoutCta(canvas: Vector2, compact: boolean)
	local button = duelButton
	if button == nil then
		ctaRect = nil
		return
	end
	if compact ~= ctaCompact then
		applyCtaStyle(compact)
		refreshCta()
	end
	local root = button.root
	if not root.Visible then
		ctaRect = nil
		return
	end
	local titleKind: Theme.TextKind = if compact then "H2" else "Title"
	local label = root:FindFirstChild("Label", true)
	local sub = root:FindFirstChild("Subtext", true)
	local subShown = sub ~= nil and sub:IsA("TextLabel") and sub.Visible and sub.Text ~= ""
	local titleText = if label and label:IsA("TextLabel") then label.Text else Strings.hud.duelCta
	local subText = if subShown and sub and sub:IsA("TextLabel") then sub.Text else ""
	local iconPx = if compact then COLUMN.ctaCompactIconPx else COLUMN.ctaIconPx
	local textWidth = math.max(Theme.textWidth(titleText, titleKind), Theme.textWidth(subText, "Chip"))
	local natural = math.ceil(iconPx + COLUMN.ctaLineGap + textWidth + 2 * Button.style("cta").paddingX + COLUMN.ctaAir)
	local width = if compact then natural else math.max(COLUMN.ctaWidth, natural)
	local lines = Theme.lineHeight(titleKind) + (if subShown then Theme.lineHeight("Chip") else 0)
	local content = math.max(lines, iconPx)
	local base = if compact then COLUMN.ctaCompactHeight else COLUMN.ctaHeight
	local height = math.max(base, math.ceil(content + CTA_BANDS_PX + COLUMN.ctaAir))
	button:setWidth(width)
	setIfChanged(root, "Size", UDim2.fromOffset(width, height))
	local blockers: { Rect } = {}
	local tilesRect = rectOf(navRow)
	local tilesReach = if tilesRect then HudFormat.badgeReachRect(tilesRect) else nil
	for _, rect in { rectOf(leftColumn), tilesReach, rectOf(rightColumn) } do
		if rect then
			table.insert(blockers, rect)
		end
	end
	local place = HudFormat.ctaPlacement({ canvas = canvas, size = Vector2.new(width, height), blockers = blockers })
	ctaFits = place.fits
	-- Placed by its centre, so the hover / press scale grows it evenly (foam fix: from the top-left corner a hovered
	-- CTA reached 3 px from the screen's right edge, out of line with the queue pill).
	setIfChanged(root, "AnchorPoint", Vector2.new(0.5, 0.5))
	setIfChanged(root, "Position", UDim2.fromOffset(math.floor(place.x + width / 2), math.floor(place.y + height / 2)))
	ctaRect = { x = place.x, y = place.y, w = width, h = height }
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
	-- One object each (the Duel CTA, the coach card's button, the queue pill's Cancel), or nil.
	local function single(key: string, object: GuiObject?): string?
		if object and usable(object) then
			objects[key] = object
			return key
		end
		return nil
	end
	local links = HudFormat.focusLinks({
		left = left,
		tiles = tileKeys,
		tileColumns = if navGrid then navGrid.FillDirectionMaxCells else 1,
		right = right,
		coach = single("coach", focusTargets.onboarding),
		cta = single("cta", if duelButton then duelButton.root else nil),
		queue = single("queue", focusTargets.queue),
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
		elseif item.place == "cta" and duelButton then
			duelButton.root.Visible = registered and shown
		end
	end
	queueLayout()
end

local function setShown(on: boolean)
	if on == shown then
		return
	end
	shown = on
	for _, frame in { leftColumn, navRow, rightColumn } do
		if frame then
			frame.Visible = on
		end
	end
	if duelButton then
		duelButton.root.Visible = on and UIController.isRegistered("queue")
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

local function buildCoins(c: Cleanup.Cleanup, parent: Instance)
	local holder: Frame = Create("Frame", {
		Name = "Hud_Coins",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		LayoutOrder = HudController.LEFT_ORDER.coins,
		-- Foam fix 2: drawn over its neighbours (foam fix 3: its "+N" no longer reaches the Grip card beside it on phones;
		-- HudFormat.gainSpot).
		ZIndex = 2,
		Parent = parent,
	})
	local capsule = CoinCapsule.new({ name = "Hud_CoinsButton", text = HudFormat.coinsText(nil), parent = holder })
	c:add(capsule)
	-- The Button press feel; silent, because it opens the Shop (ui.open). Its pulse is the gain bounce (§18.5.2 B1).
	local feel = Button.decorate(capsule.root, { sound = false })
	c:add(feel)
	coinsFeel = feel
	coinIcon = capsule.disc.root
	floatLayer = Create("Frame", {
		Name = "Floats",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = 3,
		Parent = holder,
	})
	c:add(capsule.root.Activated:Connect(function()
		if UIController.isRegistered(SHOP_SCREEN) then
			UIController.open(SHOP_SCREEN, { tab = "coins" })
		end
	end))
	coinsHolder = holder
	coins = capsule
end

local function buildTiles(c: Cleanup.Cleanup, gui: ScreenGui)
	local row: Frame = Create("Frame", {
		Name = "Hud_Nav",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(EDGE_PX, EDGE_PX + 200),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Parent = gui,
	})
	c:add(row)
	navGrid = Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(COLUMN.tileSize, COLUMN.tileSize),
		CellPadding = UDim2.fromOffset(COLUMN.tileGap, COLUMN.tileGap),
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = 1,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for index, item in HudFormat.NAV do
		if item.place == "tile" then
			local label = Strings.resolve(item.textKey) or item.id
			tileLabels[item.id] = label
			local button = Button.new({
				name = item.button,
				text = label,
				kind = "tile",
				accent = item.accent :: any,
				icon = item.icon,
				layoutOrder = index,
				parent = row,
				sound = false, -- opens a screen: ui.open plays instead (§18.5.2 B3)
				onActivated = function()
					UIController.open(item.screen, item.params)
				end,
			})
			button.root.Visible = false
			c:add(button)
			relayoutOnText(c, button)
			tiles[item.id] = button
			table.insert(tileOrder, item.id)
			if item.badge then
				badgeTiles[item.badge] = { button = button, scale = nil }
			end
		end
	end
	navRow = row
end

-- Foam fix 2: the box the toast column keeps beside for the tiles (Hud_NavReach, nothing drawn): Hud_Nav grown by a
-- count badge's reach (HudFormat.badgeReachRect; the Daily "1" hanging past the last tile touched a toast). It follows
-- Hud_Nav's box, not the badges' own, whose pop and press scales would move the toasts.
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

local function buildTracker(c: Cleanup.Cleanup, parent: Instance)
	local root: TextButton = Create("TextButton", {
		Name = "Hud_QuestTracker",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.panel,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(COLUMN.trackerWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 2,
	})
	local bands = Theme.Foam.panel
	Theme.foam(root, {
		radius = Theme.Radius.panel,
		mode = "tint",
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.panelColors(), -- Candy UI: the dark window face
	})
	Theme.rim(root)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, Theme.Padding.medium),
		PaddingRight = UDim.new(0, Theme.Padding.medium),
		PaddingBottom = UDim.new(0, bands.bevel + bands.drop + 5),
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Vertical, 4, root, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	Focus.decorate(root, Theme.Radius.panel)
	c:add(Button.decorate(root, { sound = false })) -- opens a screen: ui.open plays instead

	local header: Frame = Create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, 6, header, Enum.HorizontalAlignment.Left)
	local icon = IconGlyph.new({
		name = "Icon",
		icon = "quests",
		sizePx = TRACKER_ICON_PX,
		tone = "light", -- Candy UI: on the dark card
		layoutOrder = 1,
		parent = header,
	})
	c:add(icon)
	Theme.label({
		Name = "Tag",
		Text = Strings.hud.questTracker,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = header,
	}, "Chip")
	local section = Theme.label({
		Name = "Section",
		LayoutOrder = 3,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = header,
	}, "Small", nil, Theme.Colors.ink2)
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = section })
	local title = Theme.label({
		Name = "Title",
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	}, "Button")
	local progress: Frame = Create("Frame", {
		Name = "Progress",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, 8, progress, Enum.HorizontalAlignment.Left)
	local bar = ProgressBar.new({
		name = "Bar",
		accent = "mint",
		heightPx = TRACKER_BAR_PX,
		widthPx = 0,
		layoutOrder = 1,
		parent = progress,
	})
	c:add(bar)
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = bar.root })
	local count = Theme.label({
		Name = "Count",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = progress,
	}, "Chip")
	c:add(root.Activated:Connect(function()
		if UIController.isRegistered(QUESTS_SCREEN) then
			UIController.open(QUESTS_SCREEN)
		end
	end))
	root.Parent = parent
	tracker = { root = root, section = section, title = title, bar = bar, count = count }
end

local function buildRight(c: Cleanup.Cleanup, gui: ScreenGui)
	local right: Frame = Create("Frame", {
		Name = "Hud_Right",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -EDGE_PX, 0, EDGE_PX),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		Parent = gui,
	})
	c:add(right)
	Theme.list(Enum.FillDirection.Vertical, GAP_PX, right, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Top)
	-- The Settings tile sits centred in a fixed-size slot (layoutRight sizes both): the list only sees the slot, so the
	-- tile's hover / press scale never moves the tracker under it.
	local slot: Frame = Create("Frame", {
		Name = "Hud_SettingsSlot",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMN.settingsSize, COLUMN.settingsSize),
		Visible = false,
		LayoutOrder = 1,
		Parent = right,
	})
	local item = HudFormat.navAt("settings")[1]
	local settings = Button.new({
		name = item.button,
		text = Strings.resolve(item.textKey) or item.id,
		kind = "tile",
		accent = item.accent :: any,
		icon = item.icon,
		iconSize = COLUMN.settingsIconPx,
		width = COLUMN.settingsSize,
		height = COLUMN.settingsSize,
		parent = slot,
		sound = false, -- opens a screen: ui.open plays instead
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

local function buildCta(c: Cleanup.Cleanup, gui: ScreenGui)
	local item = HudFormat.navAt("cta")[1]
	local button = Button.new({
		name = item.button,
		text = Strings.hud.duelCta,
		kind = "cta",
		accent = item.accent :: any,
		textKind = "Title",
		icon = item.icon,
		iconSize = COLUMN.ctaIconPx,
		subtext = Strings.hud.duelJoin,
		width = COLUMN.ctaWidth,
		parent = gui,
		sound = false, -- opens a screen: ui.open plays instead (§18.5.2 B3)
		onActivated = function()
			UIController.open(item.screen, item.params)
		end,
	})
	button.root.Visible = false
	c:add(button)
	-- The title only: the queued clock's second line changes every second.
	relayoutOnText(c, button)
	duelButton = button
	ctaCompact = false
	ctaQueued = false
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

-- A selectable object another module owns, for the gamepad links: "onboarding" (the coach card's visible button) or
-- "queue" (the queue pill's Cancel); nil while it hides.
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
		cta = if duelButton and duelButton.root.Visible then ctaRect else nil,
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
-- The shown number counts up to the current Coins from the first landing. Returns false when nothing flies (the HUD is
-- hidden, amount < coinFlight.minAmount, ReducedMotion): the number then follows StateDelta as usual.
function HudController.flyCoins(from: CoinFlight.Source, amount: number): boolean
	return flyCoins(from, amount)
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
	if duelButton and duelButton.root.Visible then
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
		cta = { queued = ctaQueued, compact = ctaCompact, fits = ctaFits, rect = ctaRect },
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
		Position = UDim2.fromOffset(EDGE_PX, EDGE_PX),
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
	-- Overlays fix (2026-10-09): toasts keep beside the HUD groups (on a phone the tile row ran under them). Foam fix 2:
	-- beside the tiles with their badges' reach (Hud_NavReach). Lobby HUD (spec 2026-10-11): they start under the Duel
	-- CTA at the top middle (then under the coach card or the queue pill right under it: NotifyFormat chains them).
	local navReach = if navRow then buildNavReach(c, gui, navRow) else nil
	UIController.toastsBeside("hud", left, navReach, rightColumn)
	UIController.toastsBelow("cta", if duelButton then duelButton.root else nil)

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
	if duelButton then
		c:add(duelButton.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout))
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
	c:add(function()
		stopCount()
		if wiggleHandle then
			wiggleHandle:disconnect()
			wiggleHandle = nil
		end
		CoinFlight.clear()
		awaitingLanding = false
		gainSource, coinsFeel, coinIcon = nil, nil, nil
		table.clear(badgeCounts)
		table.clear(tiles)
		table.clear(tileOrder)
		table.clear(tileLabels)
		table.clear(badgeTiles)
		leftColumn, coinsHolder, coins, floatLayer = nil, nil, nil, nil
		navRow, navGrid, rightColumn, settingsButton, tracker, trackedId = nil, nil, nil, nil, nil, nil
		settingsSlot = nil
		bannerFrame, bannerLabel = nil, nil
		duelButton, ctaRect, ctaFits, ctaQueued, ctaCompact = nil, nil, nil, false, false
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
	-- UI overhaul: the idle Duel CTA's gloss sweep (only while it shows and is not queued; Button:sweep does nothing
	-- under ReducedMotion).
	c:add(task.spawn(function()
		while true do
			task.wait(CTA_SWEEP_SECONDS)
			local button = duelButton
			if button and shown and button.root.Visible and not ctaQueued then
				button:sweep()
			end
		end
	end))
	-- The queued CTA's clock (the queue pill's own clock, whole seconds).
	c:add(task.spawn(function()
		while true do
			task.wait(QUEUE_TICK_SECONDS)
			if StateController.queue().state == SEARCHING then
				local okTick, errTick = pcall(function(): any
					refreshCta()
					return nil
				end)
				if not okTick then
					log:error("Duel CTA update failed:", errTick)
				end
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
