--!strict
-- UIController (client only). DESIGN §2.4, §2.6, §11.1-§11.4, §9.12, §9.13. The UI base: ScreenGuis, scale and layout
-- class, loading/error cover, toasts, banners, the duel transition fade, and the screen registry with its modal stack.
-- No framework: plain instances through UI/Create and UI/Theme.
--
-- * ScreenGuis (§11.1 table, Config.UI.ScreenGuis): SD_Hud 10, SD_DuelHud 11, SD_Dimmer 19, SD_Modal 20, SD_Overlay 30,
--   SD_Fade 40, created by code with ResetOnSpawn = false and ZIndexBehavior = Sibling set explicitly (the defaults are
--   true and Global, V). screenGui(name, fallback?) creates one on first use (fallback: the spec of a gui Config does
--   not list yet). StarterGui stays empty; the Backpack core GUI is off (no Tools).
-- * Scale (§11.2): every inset-safe ScreenGui holds a UIScale = clamp(SD_Hud.AbsoluteSize.Y / 800, 0.85, 1.25),
--   recomputed on size change, with the layout class (compact / regular); LayoutChanged(class, scale). The full-bleed
--   guis (SD_Dimmer, SD_Fade) have no UIScale; their text content is scaled through trackScale(). PreferredTextSize
--   changes re-apply every Theme.text size.
-- * Boot (§2.6): showLoading() (before init; never yields: the cover is parented once the PlayerGui exists),
--   hideLoading(), showError(code) (`error.connect`: the cover stays with the reason text).
-- * Toasts (§9.13): toast(text, kind, opts?) / notify(code, args, kind, opts?): top-centre, slide 16 px down in
--   200 ms, auto-dismiss 2.5 s, at most 3 stacked (the oldest leaves first); the same text while visible restarts that
--   toast instead of stacking a copy (so a NotifyController and a screen can both report one message).
-- * Banners: banner(text, options) -> handle; one at a time in SD_Overlay (countdown-style screens own their own).
-- * Fade (§9.14, §9.12): fadeTo(transparency, seconds, color) on SD_Fade, non-interactive; the dark duel transition
--   fade is the only full-screen overlay allowed above 30% opacity.
-- * Screens (§11.1): registerScreen(name, spec); open(name, params) -> ok, refused from Matched through Returning with
--   the `common.lockedInDuel` toast (screens with lobbyOnly = false excepted); non-modal screens just run onOpen
--   (e.g. "queue"). Modals: built lazily on first open and kept; stack <= Config.UI.modalStackMax (UI/ModalStack; a
--   spec with closeOnCover closes, reason "replaced", when another modal opens over it: Inspect, §10.10);
--   shared dimmer (1 -> 0.45 over modalOpen.ms, back in 120 ms Quad In); the panel pops (feel pass, below);
--   ControlsController.block("modal") and the Modal context while any modal is open; focus saved on open and restored
--   on close (UI/Focus, §11.4); GuiService.MenuOpened closes the top modal; closeAll(reason) when a match is found
--   (StateController.LobbyLockChanged).
-- * Back stack: pushBack(handler) -> pop, for non-modal dialogs that must answer Backspace / ButtonB without blocking
--   the player (the duel's forfeit confirmation: duels never call ControlsController.block, §11.7). Back (ModalBack
--   action: Backspace, ButtonB) answers the newest layer: the newest back handler when it was pushed after the top
--   modal opened, else it closes the top modal (Part 6 review: Inspect opened over the duel result card closes first;
--   ModalStack.backTarget). L1/R1 go to the top modal's onTab(direction).
-- Feel pass (§18.5.2 B3-B5, §18.6; every sound is silent until the picker approves an id):
-- * Sounds: init installs Button.setSoundHook (ui.click, ui.hover, ui.error of every Button). open() plays ui.open
--   when a screen opens; close() plays ui.back for a close by Back / ButtonB (reason "back") or a Close button or key
--   ("button", "close", "key"), never for "matched", "replaced" and other closes the player did not ask for; back()
--   plays ui.back when a back handler answers it. One sound per action: a Button click right after an open or a back
--   is dropped (NAV_CLICK_GUARD), so a Button that opens or closes a screen is heard once even when its spec forgets
--   `sound = false`. The one GuiService.SelectedObject listener plays ui.hover when the gamepad selection moves: only
--   while the last input is a gamepad, and not when an open, a close, a back or another UI sound (a click, an error)
--   came within NAV_CLICK_GUARD, because code moved the selection as part of that action (UI/Focus stays sound-free).
--   The check is deferred, so a Button's click (played after its onActivated) is already known.
-- * Modals: open pops the panel UIScale modalOpen.scaleFrom -> 1 (0.88, 240 ms, Back Out). The logical close is
--   immediate (state, input block, context and focus); visually the root stays modalClose.visualMs (100 ms) while
--   UIScale goes 1 -> modalClose.scaleTo (0.92, Quad In), then hides; reopening during that time cancels the shrink.
--   The banner pops with the open spec too.
-- * Toasts: toast(text, kind, opts?) pops UIScale toast.popFrom -> 1 (Back Out) with the slide and plays opts.sound (a
--   key, or false for none; default ui.toast, or ui.error for a warn / error toast: one sound per action). A repeated
--   (re-armed) toast nudges toast.nudgeScale -> 1 over nudgeMs and sounds again, unless it was re-armed within nudgeMs
--   (two modules reporting one message at once). Under ReducedMotion every scale is off; sounds stay.
-- Part 8 (§11.2 audit): toasts (TOAST_WIDTH 420 base) and the banner (BANNER_WIDTH 640 base) fit the narrowest base
-- canvas (667×375 at scale 0.85 = 785 base px wide) and wrap to more lines at a large text size (AutomaticSize Y).
-- banner(text, {below = object}) sits under that object when it ends lower than BANNER_TOP (Layout.bannerTop; the
-- duel banners pass SD_DuelHud.TopBar: 20% down covered the lives row on a phone).
-- debugScreens() lists the registered screens for the Studio layout audit (Studio/LayoutAudit through DebugHooks).
-- Foam UI restyle (spec 2026-10-09; motion and timings unchanged): a toast is a foam panel (Frosting, InkUI outline,
-- bevel and drop) with its text in InkUI after an accent dot by kind (NotifyFormat.toastAccent: info Sky blue, success
-- Mint, warn Strawberry, error Danger; the text always says what happened, the dot is never the only sign). The banner
-- is a foam panel too; BannerOptions.color stays its outline colour (else InkUI). The dimmer is InkUI (same 0.45) and
-- the boot cover Frosting. toastsBelow(key, object?) keeps the toast column under the objects registered by key that
-- hang into it from above (integration 2026-10-09: "coach" the lobby's coach card, "queue" the queue pill, "duel" the
-- duel HUD's top bar; lobby HUD, spec 2026-10-11: "cta" the Duel CTA at the top middle, with the coach card or the
-- pill right under it, chained by NotifyFormat.toastClearance / toastTop), re-placed when one of them moves, resizes or
-- shows / hides, and on every new toast.
-- Overlays fix (2026-10-09): toastsBeside(key, ...objects) keeps the toast column beside what is registered there
-- (HudController: the left column, the tiles and the right column; on a phone the tile row ran under the
-- centred column): NotifyFormat.toastColumn moves it aside, narrows it (not below TOAST_MIN_WIDTH) or puts it under
-- them, for the band the column fills (re-placed as it grows). A modal opened over another gets a wash (InkUI at the
-- dimmer's 0.45) between the two (each modal root's ZIndex is MODAL_Z_STEP × its place in the stack), and the covered
-- modal's header tab hides, so the top one reads as a layer and two tabs never stack (the box reveal over Boxes). The
-- banner keeps its foam handle: an accent banner paints its drop band in the accent too (Theme.panel's InkUI drop
-- showed as a black stripe inside the accent outline), and it follows `below` while it shows (the duel HUD can appear
-- after the banner).
-- Foam fix round 2 (2026-10-09): one backdrop at a time (Layout.modalBackdrop): while two modals are open the dimmer
-- fades out under the wash, so the HUD and the world are as dark as under one modal (the dimmer and the wash together
-- made Inspect over Squishies darker than usual); the covered modal is darkened as much as they are.
-- UI overhaul (2026-10-11, Candy UI): the dimmer and the wash are the plum Backdrop (Colors.backdrop) at
-- modalOpen.dimmerTransparency, fading in over modalOpen.backdropMs. A modal pops elastically (popIn): UIScale
-- scaleFrom -> overshoot over overshootShare of ms (Quad Out), then -> 1 (Quad InOut), while the root rises riseShare
-- of its height into place (its AnchorPoint eases from that much lower to where it rests); a close or a reopen stops
-- it first (stopPop: the scale and the anchor go back to rest), so open / close spam never strands a panel. A modal root
-- that is a foam window gets the jelly-bubble texture (Theme.bubbles) when it is built. The banner is a dark window
-- (Theme.panelColors) with its drop band in its outline colour.

-- Services

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local Create = require(Client.UI.Create)
local Focus = require(Client.UI.Focus)
local Layout = require(Client.UI.Layout)
local ModalStack = require(Client.UI.ModalStack)
local NotifyFormat = require(Client.UI.NotifyFormat)
local Theme = require(Client.UI.Theme)
local Tweens = require(Client.Anim.Tweens)
local UiFx = require(Client.UI.UiFx)
local ControlsController = require(script.Parent.ControlsController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)

-- Types

export type ScreenSpec = {
	modal: boolean?, -- default true
	lobbyOnly: boolean?, -- default true: refused from Matched through Returning
	-- Modal only: builds the screen's root once (first open); it is parented under SD_Modal and kept.
	build: ((parent: Instance) -> GuiObject)?,
	onOpen: ((params: any?) -> ())?,
	onClose: ((reason: string) -> ())?,
	primary: (() -> GuiObject?)?, -- the gamepad focus target on open
	onTab: ((direction: number) -> ())?, -- L1 = -1, R1 = +1
	-- Modal only (Part 6, DESIGN §10.10): when another modal opens over this one, this one closes first (reason
	-- "replaced") instead of staying underneath (Inspect).
	closeOnCover: boolean?,
}

-- debugScreens() (Part 8, Studio debug): one registered screen as the layout audit sees it.
export type DebugScreen = {
	name: string,
	modal: boolean,
	open: boolean,
	lobbyOnly: boolean,
	root: GuiObject?, -- nil before its first open (modals are built lazily)
	primary: GuiObject?, -- spec.primary() now
}

export type ToastKind = "info" | "success" | "warn" | "error"

-- toast() options (§18.5.2 B5): `sound` is a sound key, or false for none; nil = ui.toast (ui.error for warn / error).
export type ToastOptions = { sound: (string | boolean)? }

export type ScreenGuiSpec = { displayOrder: number, insets: Enum.ScreenInsets }

export type BannerOptions = {
	seconds: number?, -- auto-dismiss after this long (nil = until dismissed)
	kind: Theme.TextKind?, -- default "Title"
	color: Color3?, -- outline (and drop band) colour; default InkUI (the foam panel's)
	-- Part 8: keep the banner's top under this object's bottom while it shows (DuelController: SD_DuelHud.TopBar, so
	-- "Sudden death!" never covers the lives on a phone); placed when the banner shows (Layout.bannerTop) and, since the
	-- overlays fix, again whenever the object moves, resizes or shows (QueueController's matched banner)
	below: GuiObject?,
}

export type BannerHandle = {
	setText: (self: BannerHandle, text: string) -> (),
	dismiss: (self: BannerHandle) -> (),
	isShown: (self: BannerHandle) -> boolean,
}

type ScreenRecord = {
	spec: ScreenSpec,
	root: GuiObject?,
	openScale: UIScale?,
	open: boolean,
	focusToken: Focus.Token?,
	openCleanup: Cleanup.Cleanup?,
	closeTween: Tween?, -- the visual shrink after a logical close (§18.5.2 B4)
	closeToken: number,
	openTween: Tween?, -- UI overhaul: the running phase of the elastic pop (popIn)
	riseTween: Tween?, -- ... and its rise into place
	restAnchor: Vector2?, -- the root's AnchorPoint at rest while it rises
	layer: number, -- nextLayer() when open() last put it on top (Back answers the newest layer, ModalStack.backTarget)
}

type Toast = {
	text: string,
	holder: Frame,
	panel: Frame,
	scale: UIScale,
	timer: thread?,
	closing: boolean,
	soundAt: number, -- os.clock() of its last sound
}

-- Constants

local UI = Config.UI
local MOTION = UI.motion
local TOAST = MOTION.toast
local SCALED_INSETS = Enum.ScreenInsets.CoreUISafeInsets
local SCALE_NAME = "SD_Scale"
local HUD = "SD_Hud"
local DIMMER_GUI = "SD_Dimmer"
local MODAL_GUI = "SD_Modal"
local OVERLAY_GUI = "SD_Overlay"
local FADE_GUI = "SD_Fade"
local TOAST_WIDTH = 420
-- reading: §9.13 gives the toast motion, not its place. Top centre, below the queue pill and the duel HUD's top
-- row (both about 90 base px tall), so a toast never covers the timer or the queue status.
local TOAST_TOP = 110
local TOAST_GAP = 8 -- reading (foam UI): base px between toastsBelow's object and the first toast
local TOAST_DOT_PX = 14 -- the accent dot before a toast's text (foam UI)
local TOAST_DOT_GAP = 10
local TOAST_DOT_LINE = 0.65 -- the dot's centre, in Body text sizes from the text's top (about half its first line)
-- Overlays fix (readings): the narrowest the column gets beside the HUD (a 20-character line of Body text), the HUD's
-- edge distance, and one toast's height in Body text sizes over its paddings (the band a new toast will fill).
local TOAST_MIN_WIDTH = 280
local TOAST_EDGE = 12
local TOAST_LINE = 1.3
local BANNER_TOP = 0.2
local BANNER_WIDTH = 640
local BANNER_GAP = 8 -- reading (Part 8): base px between BannerOptions.below's bottom and the banner
-- Overlays fix: modal roots take ZIndex MODAL_Z_STEP × their place in the stack, the wash the one under the top's; it
-- reaches WASH_BLEED base px past SD_Modal's edges (reading: over the top-bar inset, like the full-bleed dimmer). A
-- covered modal hides its children of this name (Theme.headerTab's default).
local MODAL_Z_STEP = 2
local WASH_BLEED = 200
local HEADER_TAB = "HeaderTab"
local BACK_ACTION = "ModalBack"
local TAB_PREVIOUS = "ModalTabPrevious"
local TAB_NEXT = "ModalTabNext"
-- Sounds (§18.6).
local SOUND_OPEN = "ui.open"
local SOUND_BACK = "ui.back"
local SOUND_CLICK = "ui.click"
local SOUND_HOVER = "ui.hover"
local SOUND_TOAST = "ui.toast"
local SOUND_ERROR = "ui.error"
local ERROR_KINDS: { [string]: boolean } = { warn = true, error = true }
-- Close reasons the player asked for (Back / ButtonB, a Close button, a toggle key): these play ui.back.
local BACK_REASONS: { [string]: boolean } = { back = true, button = true, close = true, key = true }
-- Close reasons whose root is about to go away: no shrink.
local INSTANT_CLOSE_REASONS: { [string]: boolean } = { unregistered = true, destroyed = true }
-- reading (§18.6 "one sound per action"): a Button click this soon after ui.open / ui.back belongs to that action, and
-- so does a selection change this soon after any UI action.
local NAV_CLICK_GUARD = 0.1
local GAMEPAD_INPUTS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
	[Enum.UserInputType.Gamepad5] = true,
	[Enum.UserInputType.Gamepad6] = true,
	[Enum.UserInputType.Gamepad7] = true,
	[Enum.UserInputType.Gamepad8] = true,
}
local BACK_OUT: Tweens.Spec = { ms = TOAST.ms, style = Enum.EasingStyle.Back, direction = Enum.EasingDirection.Out }

-- Module table

local UIController = {}

-- (layoutClass, scale) when either changes.
UIController.LayoutChanged = Signal.new() :: Signal.Signal<Layout.LayoutClass, number>
UIController.ScreenOpened = Signal.new() :: Signal.Signal<string>
UIController.ScreenClosed = Signal.new() :: Signal.Signal<string, string>

-- Private

local log = Log.new("UI")
local cleanup: Cleanup.Cleanup? = nil
local guis: { [string]: ScreenGui } = {}
local scales: { UIScale } = {}
local currentScale = 1
local currentClass: Layout.LayoutClass = "regular"
local loadingCover: Frame? = nil
local toastHolder: Frame? = nil
local toasts: { Toast } = {}
local toastSerial = 0 -- LayoutOrder: newer toasts below older ones
-- toastsBelow(key, object): the toast column starts under these while they show and hang into it.
local toastBelow: { [string]: GuiObject? } = {}
local toastBelowCleanups: { [string]: Cleanup.Cleanup } = {}
-- toastsBeside(key, ...objects): the toast column keeps beside these while they show.
local toastBeside: { [string]: { GuiObject } } = {}
local toastBesideCleanups: { [string]: Cleanup.Cleanup } = {}
-- Review fix (foam fix batch): the places the toast column took for the toasts showing now (`columnSet`: toastSerial and
-- their count) and the one it has (`columnPlace`, `columnWidth`). A re-place caused by the column's own resize goes back
-- to one of them only when that one is wider: a narrowed column wraps taller, its band can meet a group that sends it
-- under them at full width, where it is shorter and fits beside them again, and it flipped every frame. It now stays
-- at the wider place.
local columnSet: string? = nil
local columnPlaces: { [string]: boolean } = {}
local columnPlace: string? = nil
local columnWidth = 0
local bannerFrame: Frame? = nil
local bannerLabel: TextLabel? = nil
local bannerFoam: Theme.Foam? = nil
local bannerScale: UIScale? = nil
local bannerFollow: Cleanup.Cleanup? = nil -- re-places the banner while its `below` moves or shows
local bannerToken = 0
local dimmer: Frame? = nil
local wash: Frame? = nil
local washedTabs: { [GuiObject]: boolean } = {} -- covered modals' header tabs this module hid
local fadeFrame: Frame? = nil
local fadeTween: Tween? = nil
local screens: { [string]: ScreenRecord } = {}
local stack = ModalStack.new(UI.modalStackMax)
local backHandlers: { { fn: () -> (), layer: number } } = {}
local layerCount = 0 -- one counter for back handlers and modals put on top (nextLayer)
local modalRelease: (() -> ())? = nil
local lastNavSoundAt = -math.huge -- os.clock() of the last ui.open / ui.back
local lastActionAt = -math.huge -- os.clock() of the last UI action (a sound other than hover, an open or a close)

-- The order of UI layers: every back handler and every modal open() puts on top takes the next number, so Back always
-- answers the newest layer (a modal opened over a non-modal dialog closes first, Part 6 review).
local function nextLayer(): number
	layerCount += 1
	return layerCount
end

-- An open, close or back moves the gamepad selection itself: no ui.hover for that move.
local function markAction()
	lastActionAt = os.clock()
end

-- ui.open / ui.back: remembered so the click of the Button that caused it is dropped (one sound per action).
local function playNav(key: string)
	lastNavSoundAt = os.clock()
	markAction()
	SoundController.play(key)
end

-- Every Button sound comes through here (Button.setSoundHook).
local function buttonSound(key: string)
	if key == SOUND_CLICK and os.clock() - lastNavSoundAt < NAV_CLICK_GUARD then
		return
	end
	if key ~= SOUND_HOVER then
		markAction()
	end
	SoundController.play(key)
end

local function lastInputIsGamepad(): boolean
	local ok, kind = pcall(function(): Enum.UserInputType
		return UserInputService:GetLastInputType()
	end)
	return ok and GAMEPAD_INPUTS[kind] == true
end

-- GuiService.SelectedObject changed (§18.6 ui.hover for a gamepad selection change). Deferred, so the sound of the
-- action that may have moved it (a Button click after its onActivated) is known first.
local function onSelectionChanged()
	task.defer(function()
		if GuiService.SelectedObject == nil or os.clock() - lastActionAt < NAV_CLICK_GUARD then
			return
		end
		if lastInputIsGamepad() then
			SoundController.play(SOUND_HOVER)
		end
	end)
end

local function playerGui(): PlayerGui?
	local player = Players.LocalPlayer
	return if player then player:FindFirstChildOfClass("PlayerGui") else nil
end

-- Parents `gui` to the PlayerGui now, or as soon as it exists (never yields the caller).
local function parentToPlayerGui(gui: ScreenGui)
	local current = playerGui()
	if current then
		gui.Parent = current
		return
	end
	local player = Players.LocalPlayer
	if player == nil then
		return -- Edit mode (tests): stays unparented
	end
	task.spawn(function()
		local found = player:WaitForChild("PlayerGui")
		if gui.Parent == nil then
			gui.Parent = found
		end
	end)
end

local function applyScale()
	for _, uiScale in scales do
		uiScale.Scale = currentScale
	end
end

local function trackHudSize(hud: ScreenGui)
	local function update()
		local size = hud.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local scale = Layout.uiScale(size.Y)
		local class: Layout.LayoutClass = Layout.layoutClass(size.X, size.Y)
		local changed = scale ~= currentScale or class ~= currentClass
		if changed then
			currentScale = scale
			currentClass = class
			applyScale()
			UIController.LayoutChanged:fire(class, scale)
		end
	end
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
end

local function setModalContext()
	ControlsController.setContext("Modal", stack:size() > 0 or #backHandlers > 0)
end

local function updateDimmer()
	local frame = dimmer
	if frame == nil then
		local gui = UIController.screenGui(DIMMER_GUI)
		frame = Create("Frame", {
			Name = "Dimmer",
			BackgroundColor3 = Theme.Colors.backdrop,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Active = false,
			Visible = false,
			Parent = gui,
		})
		dimmer = frame
	end
	local shown = stack:size() > 0
	local f = frame :: Frame
	if shown then
		-- Fix round 2: under two modals the wash alone darkens the screen (Layout.modalBackdrop), so the dimmer fades out
		-- while the wash fades in (and back); the HUD and the world were darkened twice.
		local dim = Layout.modalBackdrop(stack:size()).dimmer
		f.Visible = true
		Tweens.fade(
			f,
			{ BackgroundTransparency = if dim then MOTION.modalOpen.dimmerTransparency else 1 },
			MOTION.modalOpen.backdropMs or MOTION.modalOpen.ms
		)
	else
		local tween = Tweens.fade(
			f,
			{ BackgroundTransparency = 1 },
			MOTION.modalClose.ms,
			MOTION.modalClose.style,
			MOTION.modalClose.direction
		)
		tween.Completed:Once(function()
			if stack:size() == 0 then
				f.Visible = false
			end
		end)
	end
end

-- Overlays fix: each open modal's root draws at MODAL_Z_STEP × its place in the stack; while one is open over another,
-- the wash (InkUI at the dimmer's transparency, over the whole screen) sits right under the top one, and the covered
-- modals' header tabs hide (they are restored once uncovered; a tab their screen hid itself is left alone). Fix round
-- 2: the wash is then the only backdrop (updateDimmer fades the dimmer out under it).
local function updateWash()
	local list = stack:list()
	for index, name in list do
		local record = screens[name]
		local root = if record then record.root else nil
		if root then
			root.ZIndex = index * MODAL_Z_STEP
		end
	end
	local hidden: { [GuiObject]: boolean } = {}
	for index = 1, #list - 1 do
		local record = screens[list[index]]
		local root = if record then record.root else nil
		if root then
			for _, child in root:GetChildren() do
				if child.Name == HEADER_TAB and child:IsA("GuiObject") and (child.Visible or washedTabs[child]) then
					hidden[child] = true
					child.Visible = false
				end
			end
		end
	end
	for tab in washedTabs do
		if not hidden[tab] then
			tab.Visible = true
		end
	end
	washedTabs = hidden
	local covered = Layout.modalBackdrop(#list).wash
	local frame = wash
	if frame == nil then
		if not covered then
			return
		end
		frame = Create("Frame", {
			Name = "ModalWash",
			BackgroundColor3 = Theme.Colors.backdrop,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(-WASH_BLEED, -WASH_BLEED),
			Size = UDim2.new(1, 2 * WASH_BLEED, 1, 2 * WASH_BLEED),
			Active = false,
			Visible = false,
			Parent = UIController.screenGui(MODAL_GUI),
		})
		wash = frame
	end
	local f = frame :: Frame
	if covered then
		f.ZIndex = #list * MODAL_Z_STEP - 1
		f.Visible = true
		Tweens.fade(
			f,
			{ BackgroundTransparency = MOTION.modalOpen.dimmerTransparency },
			MOTION.modalOpen.backdropMs or MOTION.modalOpen.ms
		)
	elseif f.Visible then
		local tween = Tweens.fade(
			f,
			{ BackgroundTransparency = 1 },
			MOTION.modalClose.ms,
			MOTION.modalClose.style,
			MOTION.modalClose.direction
		)
		tween.Completed:Once(function()
			if stack:size() <= 1 then
				f.Visible = false
			end
		end)
	end
end

local function setModalBlock()
	if stack:size() > 0 and modalRelease == nil then
		modalRelease = ControlsController.block("modal")
	elseif stack:size() == 0 and modalRelease then
		local release = modalRelease
		modalRelease = nil
		release()
	end
end

local function callSafely(label: string, fn: (...any) -> ...any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok then
		log:error(`{label} failed:`, err)
	end
end

-- UI overhaul: stops a modal's elastic pop (popIn) and puts its anchor back at rest (the scale is the caller's).
local function stopPop(record: ScreenRecord)
	Tweens.cancel(record.openTween)
	record.openTween = nil
	Tweens.cancel(record.riseTween)
	record.riseTween = nil
	local root, rest = record.root, record.restAnchor
	if root and rest then
		root.AnchorPoint = rest
	end
	record.restAnchor = nil
end

-- UI overhaul: the elastic pop of a modal opening (Config.UI.motion.modalOpen, see the header). At rest at once under
-- ReducedMotion.
local function popIn(record: ScreenRecord)
	local scale, root = record.openScale, record.root
	stopPop(record)
	if scale == nil or root == nil then
		return
	end
	local spec = MOTION.modalOpen
	if Tweens.reducedMotion() then
		scale.Scale = 1
		return
	end
	local upMs = spec.ms * (spec.overshootShare or 1)
	local settleMs = math.max(0, spec.ms - upMs)
	scale.Scale = spec.scaleFrom
	local up = Tweens.play(
		scale,
		upMs,
		{ Scale = spec.overshoot or 1 },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	record.openTween = up
	up.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and record.openTween == up then
			record.openTween =
				Tweens.play(scale, settleMs, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		end
	end)
	local rise = spec.riseShare or 0
	if rise > 0 then
		local rest = root.AnchorPoint
		record.restAnchor = rest
		root.AnchorPoint = Vector2.new(rest.X, rest.Y - rise)
		local tween = Tweens.play(root, spec.ms, { AnchorPoint = rest }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		record.riseTween = tween
		tween.Completed:Once(function()
			if record.riseTween == tween then
				record.riseTween = nil
				record.restAnchor = nil
			end
		end)
	end
end

-- Closes one open modal record (no stack bookkeeping).
local function closeRecord(name: string, reason: string)
	local record = screens[name]
	if record == nil or not record.open then
		return
	end
	record.open = false
	markAction() -- the focus goes back below: not a gamepad move of the player's (no ui.hover)
	if record.spec.onClose then
		callSafely(`{name}.onClose`, record.spec.onClose, reason)
	end
	local root = record.root
	if root then
		-- §18.5.2 B4: the logical close is now; the panel shrinks for visualMs before it hides (not under
		-- ReducedMotion, and not when the root is about to be destroyed).
		record.closeToken += 1
		local token = record.closeToken
		Tweens.cancel(record.closeTween)
		record.closeTween = nil
		stopPop(record) -- UI overhaul: an interrupted pop goes back to rest before the shrink
		local openScale = record.openScale
		if openScale == nil or Tweens.reducedMotion() or INSTANT_CLOSE_REASONS[reason] then
			root.Visible = false
		else
			local close = MOTION.modalClose
			local tween =
				Tweens.play(openScale, close.visualMs, { Scale = close.scaleTo }, close.style, close.direction)
			record.closeTween = tween
			tween.Completed:Once(function()
				if record.closeToken == token and not record.open then
					record.closeTween = nil
					root.Visible = false
					openScale.Scale = 1
				end
			end)
		end
	end
	if record.openCleanup then
		record.openCleanup:clean()
		record.openCleanup = nil
	end
	if record.focusToken then
		Focus.restore(record.focusToken)
		record.focusToken = nil
	end
	UIController.ScreenClosed:fire(name, reason)
end

local function afterStackChange()
	updateDimmer()
	updateWash()
	setModalBlock()
	setModalContext()
end

-- ModalStack.push's closesWhenCovered: a screen whose spec says closeOnCover leaves before a modal opens over it.
local function closesWhenCovered(name: string): boolean
	local record = screens[name]
	return record ~= nil and record.spec.closeOnCover == true
end

local function ensureBuilt(name: string, record: ScreenRecord): GuiObject?
	if record.root then
		return record.root
	end
	local build = record.spec.build
	if build == nil then
		log:warn(`modal screen {name} has no build function`)
		return nil
	end
	local parent = UIController.screenGui(MODAL_GUI)
	local ok, result = pcall(build, parent)
	if not ok or typeof(result) ~= "Instance" or not (result :: Instance):IsA("GuiObject") then
		log:error(`building screen {name} failed:`, if ok then "build returned no GuiObject" else result)
		return nil
	end
	local root = result :: GuiObject
	root.Visible = false
	if root.Parent == nil then
		root.Parent = parent
	end
	Focus.prepareGroup(root)
	record.openScale = Create("UIScale", { Name = "SD_OpenScale", Parent = root })
	record.root = root
	-- UI overhaul: a foam window gets the jelly-bubble texture behind its content.
	if root:FindFirstChild("SD_Foam") then
		Theme.bubbles(root)
	end
	return root
end

-- Toasts --------------------------------------------------------------------------------------------------------------

-- True while `object` shows: Visible itself and up to its ScreenGui, which is Enabled.
local function onScreen(object: GuiObject): boolean
	local node: Instance? = object
	while node ~= nil do
		if node:IsA("ScreenGui") then
			return node.Enabled
		elseif node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return false
end

-- `object`'s rect in base px from its own ScreenGui's origin while it shows (nil otherwise). The toastsBelow and
-- toastsBeside objects live in other ScreenGuis (SD_Hud, SD_DuelHud; all CoreUISafeInsets with the same UI scale).
local function shownRect(object: GuiObject, scale: number): NotifyFormat.Rect?
	if object.Parent == nil or not onScreen(object) or not (scale > 0) or object.AbsoluteSize.Y <= 0 then
		return nil
	end
	local objectGui = object:FindFirstAncestorWhichIsA("ScreenGui")
	if objectGui == nil then
		return nil
	end
	local position = (object.AbsolutePosition - objectGui.AbsolutePosition) / scale
	local size = object.AbsoluteSize / scale
	return { x = position.X, y = position.Y, w = size.X, h = size.Y }
end

-- Places the toast column (base px of SD_Overlay; NotifyFormat.toastColumn): TOAST_TOP, or under the lowest
-- toastsBelow object that shows and hangs into it from above; sideways clear of the toastsBeside objects its band
-- meets. The band is the column's height now plus `adding` (a toast about to arrive). `resized`: the column's own size
-- changed (it returns to a place it took for these toasts only when that one is wider, see columnPlaces).
local function placeColumn(adding: number, resized: boolean?)
	local frame = toastHolder
	if frame == nil then
		return
	end
	local gui = UIController.screenGui(OVERLAY_GUI)
	local scale = currentScale
	local canvas = if scale > 0 then gui.AbsoluteSize / scale else Vector2.zero
	if canvas.X <= 0 or canvas.Y <= 0 then
		return -- not drawn yet: the column keeps its place (re-placed when SD_Overlay gets its size)
	end
	local above: { NotifyFormat.Rect } = {}
	for _, below in toastBelow do
		local rect = if below then shownRect(below, scale) else nil
		if rect then
			table.insert(above, rect)
		end
	end
	local beside: { NotifyFormat.Rect } = {}
	for _, objects in toastBeside do
		for _, object in objects do
			local rect = shownRect(object, scale)
			if rect then
				table.insert(beside, rect)
			end
		end
	end
	local height = if scale > 0 then frame.AbsoluteSize.Y / scale else 0
	if adding > 0 then
		height += (if height > 0 then Theme.Padding.small else 0) + adding
	end
	local column = NotifyFormat.toastColumn({
		canvas = canvas,
		width = TOAST_WIDTH,
		minWidth = TOAST_MIN_WIDTH,
		height = height,
		defaultTop = TOAST_TOP,
		gap = TOAST_GAP,
		edge = TOAST_EDGE,
		above = above,
		beside = beside,
	})
	local width = math.floor(column.width + 0.5)
	local position = UDim2.fromOffset(math.floor(column.x + width / 2 + 0.5), math.floor(column.y + 0.5))
	local place = `{position.X.Offset},{position.Y.Offset},{width}`
	local set = `{toastSerial}/{#toasts}`
	if set ~= columnSet then
		columnSet, columnPlaces = set, {}
	end
	if resized and place ~= columnPlace and columnPlaces[place] and width <= columnWidth then
		return -- back to a place it left for these toasts and no wider: it keeps this one (columnPlaces)
	end
	columnPlaces[place] = true
	columnPlace, columnWidth = place, width
	if frame.Position ~= position then
		frame.Position = position
	end
	local size = UDim2.fromOffset(width, 0)
	if frame.Size ~= size then
		frame.Size = size
	end
end

local function placeToasts()
	placeColumn(0)
end

-- The height (base px) of a one-line toast: its Body line and its panel paddings (Theme.panel's bottom padding is the
-- larger of its padding and its bands, both 12 here).
local function oneToastHeight(): number
	return Theme.textSize("Body") * TOAST_LINE + 2 * Theme.Padding.medium
end

local function toastContainer(): Frame
	if toastHolder then
		return toastHolder
	end
	local frame: Frame = Create("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOAST_TOP),
		Size = UDim2.fromOffset(TOAST_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = UIController.screenGui(OVERLAY_GUI),
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, frame, nil, Enum.VerticalAlignment.Top)
	toastHolder = frame
	-- The band the column keeps clear grows and shrinks with its toasts (NotifyFormat.toastColumn); a re-place its own
	-- resize causes goes back to an earlier place for the same toasts only when that one is wider (columnPlaces), so it
	-- settles.
	frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		placeColumn(0, true)
	end)
	placeToasts()
	return frame
end

local function dismissToast(toast: Toast)
	if toast.closing then
		return
	end
	toast.closing = true
	if toast.timer then
		task.cancel(toast.timer)
		toast.timer = nil
	end
	local index = table.find(toasts, toast)
	if index then
		table.remove(toasts, index)
	end
	if Tweens.reducedMotion() then
		toast.holder:Destroy()
		return
	end
	local tween = Tweens.play(toast.panel, TOAST.ms, { Position = UDim2.fromOffset(0, -TOAST.slidePx) })
	tween.Completed:Once(function()
		toast.holder:Destroy()
	end)
end

local function armToast(toast: Toast)
	if toast.timer then
		task.cancel(toast.timer)
	end
	toast.timer = task.delay(TOAST.autoDismissSeconds, function()
		toast.timer = nil
		dismissToast(toast)
	end)
end

-- The sound a toast plays (§18.5.2 B5): opts.sound, else ui.error for a warn / error toast, else ui.toast; nil = none.
local function toastSound(kind: ToastKind?, opts: ToastOptions?): string?
	local sound = if opts then opts.sound else nil
	if sound == false then
		return nil
	elseif type(sound) == "string" and sound ~= "" then
		return sound
	end
	return if kind and ERROR_KINDS[kind] then SOUND_ERROR else SOUND_TOAST
end

local function playToastSound(toast: Toast, key: string?)
	toast.soundAt = os.clock()
	if key then
		SoundController.play(key)
	end
end

-- Public: ScreenGuis and layout ---------------------------------------------------------------------------------------

-- The ScreenGui `name` (one of Config.UI.ScreenGuis), created on first use. `fallback` is the spec of a ScreenGui
-- Config does not list yet (reading: e.g. the duel reticle overlay); a Config entry always wins over it.
function UIController.screenGui(name: string, fallback: ScreenGuiSpec?): ScreenGui
	local existing = guis[name]
	if existing then
		return existing
	end
	local spec = UI.ScreenGuis[name] or fallback
	assert(spec ~= nil, `[SD][UI] unknown ScreenGui {tostring(name)}`)
	local gui: ScreenGui = Create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = spec.displayOrder,
		ScreenInsets = spec.insets,
	})
	if spec.insets == SCALED_INSETS then
		local uiScale: UIScale = Create("UIScale", { Name = SCALE_NAME, Scale = currentScale, Parent = gui })
		table.insert(scales, uiScale)
	end
	guis[name] = gui
	parentToPlayerGui(gui)
	if name == HUD then
		trackHudSize(gui)
	end
	return gui
end

-- Keeps a UIScale at the current UI scale (content inside the full-bleed guis).
function UIController.trackScale(uiScale: UIScale)
	uiScale.Scale = currentScale
	table.insert(scales, uiScale)
	uiScale.Destroying:Once(function()
		local index = table.find(scales, uiScale)
		if index then
			table.remove(scales, index)
		end
	end)
end

function UIController.scale(): number
	return currentScale
end

function UIController.layoutClass(): Layout.LayoutClass
	return currentClass
end

-- Public: boot cover --------------------------------------------------------------------------------------------------

local function cover(text: string): Frame
	local frame = loadingCover
	if frame == nil then
		frame = Create("Frame", {
			Name = "SD_Loading",
			BackgroundColor3 = Theme.Colors.panel,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
			Parent = UIController.screenGui(FADE_GUI),
		})
		local content: Frame = Create("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(BANNER_WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = frame,
		})
		local contentScale: UIScale = Create("UIScale", { Parent = content })
		UIController.trackScale(contentScale)
		Theme.label({ Name = "Text", Text = text, Parent = content }, "Title")
		loadingCover = frame
	end
	local label = (frame :: Frame):FindFirstChild("Text", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
	return frame :: Frame
end

-- Boot step 1 (§2.6): a full-screen "Loading…" cover until hideLoading(). Never yields.
function UIController.showLoading()
	cover(Strings.common.loading).Visible = true
end

function UIController.hideLoading()
	local frame = loadingCover
	if frame then
		loadingCover = nil
		frame:Destroy()
	end
end

-- A full-screen error that stays (boot failure, e.g. `error.connect`).
function UIController.showError(code: string)
	cover(Strings.reasonText(code)).Visible = true
end

-- Public: toasts and banners -----------------------------------------------------------------------------------------

function UIController.toast(text: string, kind: ToastKind?, opts: ToastOptions?)
	if type(text) ~= "string" or text == "" then
		return
	end
	local sound = toastSound(kind, opts)
	for _, existing in toasts do
		if existing.text == text and not existing.closing then
			armToast(existing)
			-- The same message again: a nudge so the player sees it registered, and its sound unless two modules are
			-- reporting one message right now.
			if os.clock() - existing.soundAt >= TOAST.nudgeMs / 1000 then
				Tweens.scale(existing.scale, TOAST.nudgeScale, 1, {
					ms = TOAST.nudgeMs,
					style = Enum.EasingStyle.Back,
					direction = Enum.EasingDirection.Out,
				})
				playToastSound(existing, sound)
			end
			return
		end
	end
	toastSerial += 1
	while #toasts >= TOAST.maxStacked do
		dismissToast(toasts[1])
	end
	local container = toastContainer()
	placeColumn(oneToastHeight()) -- placed for the band it is about to fill, so it does not jump once it shows
	local holder: Frame = Create("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ClipsDescendants = false,
		LayoutOrder = toastSerial,
	})
	local panel = Theme.panel({
		Name = "Panel",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(0, if Tweens.reducedMotion() then 0 else -TOAST.slidePx),
		Parent = holder,
	}, Theme.Radius.button, Theme.Padding.medium)
	-- Foam UI: the kind as an accent dot on the first line (the text says what happened; the dot adds the colour).
	local accent = NotifyFormat.toastAccent(kind)
	local dot: Frame = Create("Frame", {
		Name = "Accent",
		BackgroundColor3 = if accent == "danger" then Theme.Colors.danger else Theme.accent(accent).face,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, math.floor(Theme.textSize("Body") * TOAST_DOT_LINE + 0.5)),
		Size = UDim2.fromOffset(TOAST_DOT_PX, TOAST_DOT_PX),
		Parent = panel,
	})
	Theme.corner(TOAST_DOT_PX, dot)
	Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.bar, dot)
	Theme.label({
		Name = "Text",
		Text = text,
		Position = UDim2.fromOffset(TOAST_DOT_PX + TOAST_DOT_GAP, 0),
		Size = UDim2.new(1, -(TOAST_DOT_PX + TOAST_DOT_GAP), 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	}, "Body", Enum.FontWeight.Bold)
	local scale: UIScale = Create("UIScale", { Name = "Pop", Parent = panel })
	holder.Parent = container
	local toast: Toast = {
		text = text,
		holder = holder,
		panel = panel,
		scale = scale,
		timer = nil,
		closing = false,
		soundAt = -math.huge,
	}
	table.insert(toasts, toast)
	if not Tweens.reducedMotion() then
		Tweens.play(panel, TOAST.ms, { Position = UDim2.fromOffset(0, 0) })
	end
	Tweens.scale(scale, TOAST.popFrom, 1, BACK_OUT)
	playToastSound(toast, sound)
	armToast(toast)
end

-- Foam UI (spec: the lobby's coach card never overlaps toasts): while the object registered under `key` shows, starts
-- at or above TOAST_TOP in the toast column's width (or at or above TOAST_GAP under one that does: lobby HUD, spec
-- 2026-10-11) and reaches lower, the toast column starts TOAST_GAP under it (under the lowest of them; never past the
-- middle of the screen). One object per key (integration: "coach", "queue", "duel"; "cta" the Duel CTA); nil removes
-- the key. The column follows each object as it moves, resizes, shows or hides, and drops it when it is destroyed.
function UIController.toastsBelow(key: string, object: GuiObject?)
	local previous = toastBelowCleanups[key]
	if previous then
		previous:clean()
		toastBelowCleanups[key] = nil
	end
	toastBelow[key] = object
	if object then
		local c = Cleanup.new()
		toastBelowCleanups[key] = c
		for _, property in { "AbsoluteSize", "AbsolutePosition", "Visible" } do
			c:add(object:GetPropertyChangedSignal(property):Connect(placeToasts))
		end
		c:add(object.Destroying:Connect(function()
			if toastBelow[key] == object then
				UIController.toastsBelow(key, nil)
			end
		end))
	end
	placeToasts()
end

-- Overlays fix (toasts never cover the HUD): while the objects registered under `key` show, the toast column keeps
-- beside the ones its band meets (moved aside, narrowed, or under them: NotifyFormat.toastColumn). One set per key
-- (HudController: "hud", its groups; nil objects are skipped); no objects removes the key. The column follows each
-- object as it moves, resizes, shows or hides, and drops it when it is destroyed.
function UIController.toastsBeside(key: string, ...: GuiObject?)
	local previous = toastBesideCleanups[key]
	if previous then
		previous:clean()
		toastBesideCleanups[key] = nil
	end
	toastBeside[key] = nil
	local given = table.pack(...)
	local list: { GuiObject } = {}
	for index = 1, given.n do
		local object = given[index]
		if object then
			table.insert(list, object)
		end
	end
	if #list > 0 then
		local c = Cleanup.new()
		toastBesideCleanups[key] = c
		for _, object in list do
			for _, property in { "AbsoluteSize", "AbsolutePosition", "Visible" } do
				c:add(object:GetPropertyChangedSignal(property):Connect(placeToasts))
			end
			c:add(object.Destroying:Connect(function()
				local index = table.find(list, object)
				if index then
					table.remove(list, index)
				end
				placeToasts()
			end))
		end
		toastBeside[key] = list
	end
	placeToasts()
end

-- A reason code or Strings key as a toast (Strings.reasonText + format).
function UIController.notify(code: string, args: { [string]: any }?, kind: ToastKind?, opts: ToastOptions?)
	UIController.toast(Strings.format(Strings.reasonText(code), args), kind, opts)
end

-- The banner's place: BANNER_TOP down its ScreenGui, or under `below` (Layout.bannerTop) when that shows in an enabled
-- ScreenGui and ends lower. Both boxes are read in actual px from their own ScreenGui's origin, then turned into the
-- banner gui's base px (its UIScale).
local function bannerPosition(frame: GuiObject, below: GuiObject?): UDim2
	local fallback = UDim2.fromScale(0.5, BANNER_TOP)
	local gui = frame:FindFirstAncestorWhichIsA("ScreenGui")
	local belowGui = if below then below:FindFirstAncestorWhichIsA("ScreenGui") else nil
	local scale = currentScale
	if below == nil or gui == nil or belowGui == nil or not belowGui.Enabled or not below.Visible then
		return fallback
	end
	local height = gui.AbsoluteSize.Y
	if not (scale > 0) or height <= 0 or below.AbsoluteSize.Y <= 0 then
		return fallback
	end
	local bottom = (below.AbsolutePosition.Y + below.AbsoluteSize.Y - gui.AbsolutePosition.Y) / scale
	local top = Layout.bannerTop(height / scale, bottom, BANNER_TOP, BANNER_GAP)
	return UDim2.new(0.5, 0, 0, math.floor(top + 0.5))
end

-- The banner's foam colours (Theme.panel's: the dark window face and bevel) with its drop band in `drop`.
local function bannerColors(drop: Color3): Theme.FoamColors
	return { face = Theme.Colors.panel, bevel = Theme.Colors.bevel, drop = drop }
end

local function stopBannerFollow()
	local follow = bannerFollow
	bannerFollow = nil
	if follow then
		follow:clean()
	end
end

-- Shows the one banner (replacing the current one). Returns its handle.
function UIController.banner(text: string, options: BannerOptions?): BannerHandle
	local opts: BannerOptions = options or {}
	if bannerFrame == nil then
		-- Theme.panel's look, built here to keep its foam handle (an accent banner repaints its drop band).
		local bands = Theme.Foam.panel
		local frame: Frame = Create("Frame", {
			Name = "Banner",
			BackgroundColor3 = Theme.Colors.panel,
			BackgroundTransparency = Theme.Transparency.panel,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, BANNER_TOP),
			Size = UDim2.fromOffset(BANNER_WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false,
		})
		bannerFoam = Theme.foam(frame, {
			radius = Theme.Radius.large,
			mode = "tint",
			bevel = bands.bevel,
			drop = bands.drop,
			colors = bannerColors(Theme.Colors.inkUI),
		})
		-- Theme.Padding.large on every side: already more than the bands under the text (Theme.panel's rule).
		Theme.padding(math.max(Theme.Padding.large, bands.bevel + bands.drop), frame)
		frame.Parent = UIController.screenGui(OVERLAY_GUI)
		bannerScale = Create("UIScale", { Parent = frame })
		bannerLabel =
			Theme.label({ Name = "Text", TextXAlignment = Enum.TextXAlignment.Center, Parent = frame }, "Title")
		bannerFrame = frame
	end
	bannerToken += 1
	local token = bannerToken
	local frame = bannerFrame :: Frame
	local label = bannerLabel :: TextLabel
	Theme.text(label, opts.kind or "Title")
	label.Text = text
	local foam = bannerFoam
	if foam then
		-- Foam UI: the InkUI outline of panels, or the caller's accent outline (Sudden death, Opponent found). Overlays
		-- fix: the drop band takes the outline's colour, so an accent banner has no InkUI stripe inside its outline.
		local outline = opts.color or Theme.Colors.inkUI
		foam:setStroke(outline, if opts.color then Theme.Stroke.thick else Theme.Stroke.ink)
		foam:paint(bannerColors(outline))
	end
	stopBannerFollow()
	frame.Position = bannerPosition(frame, opts.below)
	frame.Visible = true
	Tweens.scale(bannerScale :: UIScale, MOTION.modalOpen.scaleFrom, 1, MOTION.modalOpen)
	-- Overlays fix: under `below` while it shows, re-placed as it moves, resizes or shows (the matched banner appears
	-- before the duel HUD does).
	local below = opts.below
	if below then
		local follow = Cleanup.new()
		bannerFollow = follow
		local function replace()
			if token == bannerToken and frame.Visible then
				frame.Position = bannerPosition(frame, below)
			end
		end
		for _, property in { "AbsoluteSize", "AbsolutePosition", "Visible" } do
			follow:add(below:GetPropertyChangedSignal(property):Connect(replace))
		end
		local belowGui = below:FindFirstAncestorWhichIsA("ScreenGui")
		if belowGui then
			follow:add(belowGui:GetPropertyChangedSignal("Enabled"):Connect(replace))
		end
	end

	local handle = {} :: BannerHandle
	function handle.isShown(_: BannerHandle): boolean
		return token == bannerToken and frame.Visible
	end
	function handle.setText(_: BannerHandle, newText: string)
		if token == bannerToken then
			label.Text = newText
		end
	end
	function handle.dismiss(_: BannerHandle)
		if token == bannerToken then
			frame.Visible = false
			stopBannerFollow()
		end
	end
	if opts.seconds and opts.seconds > 0 then
		task.delay(opts.seconds, function()
			handle:dismiss()
		end)
	end
	return handle
end

-- Public: fade (§9.14) -------------------------------------------------------------------------------------------------

-- Fades the SD_Fade overlay to `transparency` (0 = covered, 1 = clear) over `seconds` in `color`.
function UIController.fadeTo(transparency: number, seconds: number, color: Color3?): Tween
	local frame = fadeFrame
	if frame == nil then
		frame = Create("Frame", {
			Name = "Fade",
			BackgroundColor3 = color or Theme.Colors.ink,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Active = false,
			Visible = false,
			Parent = UIController.screenGui(FADE_GUI),
		})
		fadeFrame = frame
	end
	local f = frame :: Frame
	if color then
		f.BackgroundColor3 = color
	end
	f.Visible = true
	Tweens.cancel(fadeTween)
	local tween = Tweens.fade(f, { BackgroundTransparency = transparency }, seconds * 1000)
	fadeTween = tween
	if transparency >= 1 then
		tween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and fadeTween == tween then
				f.Visible = false
			end
		end)
	end
	return tween
end

-- Public: screens -----------------------------------------------------------------------------------------------------

-- Registers a screen. Returns a function that unregisters it (closing it first).
function UIController.registerScreen(name: string, spec: ScreenSpec): () -> ()
	assert(type(name) == "string" and name ~= "", "[SD][UI] screen name required")
	if screens[name] then
		log:warn(`screen {name} registered twice; the newer one replaces it`)
		UIController.close(name, "replaced")
	end
	local record: ScreenRecord =
		{ spec = spec, root = nil, openScale = nil, open = false, closeTween = nil, closeToken = 0, layer = 0 }
	screens[name] = record
	return function()
		if screens[name] == record then
			UIController.close(name, "unregistered")
			screens[name] = nil
			if record.root then
				record.root:Destroy()
			end
		end
	end
end

function UIController.isRegistered(name: string): boolean
	return screens[name] ~= nil
end

-- Opens a screen. Returns false when it is unknown, refused during a match, or fails to build.
function UIController.open(name: string, params: any?): boolean
	local record = screens[name]
	if record == nil then
		log:warn(`open: unknown screen {tostring(name)}`)
		return false
	end
	local spec = record.spec
	if spec.lobbyOnly ~= false and StateController.isLobbyLocked() then
		UIController.toast(Strings.common.lockedInDuel, "info")
		return false
	end
	if spec.modal == false then
		local onOpen = spec.onOpen
		playNav(SOUND_OPEN)
		if onOpen then
			task.spawn(callSafely, `{name}.onOpen`, onOpen, params)
		end
		UIController.ScreenOpened:fire(name)
		return true
	end

	local root = ensureBuilt(name, record)
	if root == nil then
		return false
	end
	if record.open and stack:top() == name then
		if spec.onOpen then
			callSafely(`{name}.onOpen`, spec.onOpen, params)
		end
		return true
	end
	local closing = stack:push(name, closesWhenCovered)
	for _, other in closing do
		closeRecord(other, "replaced")
	end
	record.layer = nextLayer() -- before onOpen, so a back handler it pushes is the newer layer (the box reveal's skip)
	markAction() -- Focus.follow below may move the gamepad selection: part of this open (no ui.hover)
	if not record.open then
		record.open = true
		-- Reopening during the close shrink cancels it (§18.5.2 B4).
		record.closeToken += 1
		Tweens.cancel(record.closeTween)
		record.closeTween = nil
		record.focusToken = Focus.capture()
		-- The newest modal draws on top of the one it opened over (updateWash keeps every open root at its place).
		root.ZIndex = stack:size() * MODAL_Z_STEP
		root.Visible = true
		popIn(record) -- UI overhaul: the elastic pop and the rise into place
		local openCleanup = Cleanup.new()
		record.openCleanup = openCleanup
		Focus.follow(root, spec.primary or function(): GuiObject?
			return nil
		end, openCleanup)
	end
	afterStackChange()
	playNav(SOUND_OPEN)
	if spec.onOpen then
		callSafely(`{name}.onOpen`, spec.onOpen, params)
	end
	UIController.ScreenOpened:fire(name)
	return true
end

-- Closes a modal screen (and any modal above it). Returns true when something closed. A close the player asked for
-- (reason back / button / close / key) plays ui.back.
function UIController.close(name: string, reason: string?): boolean
	if not stack:contains(name) then
		return false
	end
	local why = reason or "closed"
	for _, other in stack:remove(name) do
		closeRecord(other, why)
	end
	afterStackChange()
	if BACK_REASONS[why] then
		playNav(SOUND_BACK)
	end
	return true
end

function UIController.closeTop(reason: string?): boolean
	local top = stack:top()
	return if top then UIController.close(top, reason) else false
end

-- Closes every modal (e.g. "matched" when a match is found).
function UIController.closeAll(reason: string)
	while stack:size() > 0 do
		local top = stack:top() :: string
		UIController.close(top, reason)
	end
end

function UIController.isOpen(name: string): boolean
	local record = screens[name]
	return record ~= nil and record.open
end

function UIController.topModal(): string?
	return stack:top()
end

function UIController.openModals(): { string }
	return stack:list()
end

-- Studio debug (Part 8, DebugHooks "layoutAudit"): every registered screen, sorted by name: whether it is a modal, open,
-- lobby only, its root (nil before its first open) and its gamepad primary now (spec.primary(); nil when it has none or
-- the call fails). Reads only.
function UIController.debugScreens(): { DebugScreen }
	local list: { DebugScreen } = {}
	for name, record in screens do
		local spec = record.spec
		local primary: GuiObject? = nil
		local primaryFn = spec.primary
		if primaryFn and record.root then
			local ok, result = pcall(primaryFn)
			if ok and typeof(result) == "Instance" and (result :: Instance):IsA("GuiObject") then
				primary = result :: GuiObject
			end
		end
		table.insert(list, {
			name = name,
			modal = spec.modal ~= false,
			open = record.open,
			lobbyOnly = spec.lobbyOnly ~= false,
			root = record.root,
			primary = primary,
		})
	end
	table.sort(list, function(a: DebugScreen, b: DebugScreen): boolean
		return a.name < b.name
	end)
	return list
end

-- Pushes a back handler (Backspace / ButtonB / the Roblox menu opening) for a non-modal dialog. Returns pop().
function UIController.pushBack(handler: () -> ()): () -> ()
	local entry = { fn = handler, layer = nextLayer() }
	table.insert(backHandlers, entry)
	setModalContext()
	local popped = false
	return function()
		if popped then
			return
		end
		popped = true
		local index = table.find(backHandlers, entry)
		if index then
			table.remove(backHandlers, index)
		end
		setModalContext()
	end
end

-- Answers the newest layer (ModalStack.backTarget): the newest back handler when it came after the top modal opened,
-- else closes the top modal (Inspect opened over the duel result card closes first, Part 6 review). Returns true when
-- something handled it.
function UIController.back(reason: string?): boolean
	local entry = backHandlers[#backHandlers]
	local top = stack:top()
	local topRecord = if top then screens[top] else nil
	local target = ModalStack.backTarget(if entry then entry.layer else nil, if topRecord then topRecord.layer else nil)
	if entry and target == "handler" then
		markAction() -- the handler may restore the focus (no ui.hover for that)
		callSafely("back handler", entry.fn)
		playNav(SOUND_BACK)
		return true
	end
	return UIController.closeTop(reason or "back")
end

-- Lifecycle -----------------------------------------------------------------------------------------------------------

function UIController.init()
	local c = Cleanup.new()
	cleanup = c

	for name in UI.ScreenGuis do
		UIController.screenGui(name)
	end
	-- UI overhaul: the celebrations (UI/UiFx) draw above every window.
	UiFx.setLayer(UIController.screenGui(OVERLAY_GUI))
	c:add(function()
		UiFx.setLayer(nil)
	end)
	-- The toast column's place follows the screen (toastsBelow).
	c:add(UIController.screenGui(OVERLAY_GUI):GetPropertyChangedSignal("AbsoluteSize"):Connect(placeToasts))
	c:add(UIController.LayoutChanged:connect(placeToasts))
	c:add(function()
		for key in toastBelowCleanups do
			UIController.toastsBelow(key, nil)
		end
		for key in toastBesideCleanups do
			UIController.toastsBeside(key, nil)
		end
		stopBannerFollow()
	end)

	-- Sounds (§18.6): every Button plays through the hook; the gamepad selection moving plays ui.hover (not when an
	-- open or close moved it: that action already has its sound).
	Button.setSoundHook(buttonSound)
	c:add(function()
		Button.setSoundHook(nil)
	end)
	c:add(GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(onSelectionChanged))

	c:add(ControlsController.bindAction(BACK_ACTION, function(inputState: Enum.UserInputState): boolean?
		if inputState ~= Enum.UserInputState.Begin then
			return nil
		end
		return UIController.back("back")
	end))
	local function tab(direction: number)
		return function(inputState: Enum.UserInputState): boolean?
			if inputState ~= Enum.UserInputState.Begin then
				return nil
			end
			local top = stack:top()
			local record = if top then screens[top] else nil
			if record and record.spec.onTab then
				callSafely(`{top}.onTab`, record.spec.onTab, direction)
				return true
			end
			return nil
		end
	end
	c:add(ControlsController.bindAction(TAB_PREVIOUS, tab(-1)))
	c:add(ControlsController.bindAction(TAB_NEXT, tab(1)))

	c:add(GuiService.MenuOpened:Connect(function()
		local entry = backHandlers[#backHandlers]
		if entry then
			markAction()
			callSafely("back handler", entry.fn)
		end
		UIController.closeTop("menu")
	end))
	-- pcall: an engine without GuiService.PreferredTextSize must not stop the boot (Theme reads it the same way).
	local okSignal, textSizeChanged = pcall(function(): RBXScriptSignal
		return GuiService:GetPropertyChangedSignal("PreferredTextSize")
	end)
	if okSignal then
		c:add(textSizeChanged:Connect(function()
			for _, gui in guis do
				Theme.refreshText(gui)
			end
		end))
	else
		log:warn("PreferredTextSize changes are not followed:", textSizeChanged)
	end
	c:add(StateController.LobbyLockChanged:connect(function(isLocked: boolean)
		if isLocked then
			UIController.closeAll("matched")
		end
	end))
	c:add(function()
		UIController.closeAll("destroyed")
		table.clear(backHandlers)
		setModalContext()
	end)
end

function UIController.start()
	local ok, err = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	if not ok then
		log:warn("could not hide the Backpack:", err)
	end
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function UIController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return UIController
