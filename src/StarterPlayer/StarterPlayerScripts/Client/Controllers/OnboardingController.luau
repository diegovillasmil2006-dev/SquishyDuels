--!strict
-- OnboardingController (client only). DESIGN §11.8 (onboarding, Config/Onboarding; never pays Coins), §11.6
-- (Settings "Replay tutorial"), §9.12 / §9.13 (pulse and flash rules); the foam UI restyle (spec 2026-10-09
-- "Onboarding: a coach card at the top centre that never overlaps the queue pill, toasts or banners"). What the card
-- says comes from UI/OnboardingFormat (pure).
-- * The coach card (Hud_OnboardingCard, a foam card in SD_Hud) sits right under the Duel CTA at the top middle (lobby
--   HUD, spec 2026-10-11), between the HUD's left column and its top-right group (HudFormat.coachPlacement from
--   HudController.layoutRects(); its width the design's 512 base px, wider when the text needs it); the toasts start
--   under it. It shows the lowest incomplete step for a ready profile that has not skipped.
--   The welcome card has [Got it] (Onboarding_GotItButton -> OnboardingStep("welcome")); every other card has the one
--   "Skip tutorial" link (Onboarding_SkipButton -> OnboardingStep(Config.Onboarding.skipStepId); the server sets
--   onboarding.skipped). Both act on the card at once (the saved flags follow in a StateDelta). Hidden during duels
--   (StateController lobby lock; the HUD column hides too), with its guidance.
-- * Guidance: a waypoint (UI/Waypoint, hidden within Config.Onboarding.waypointHideStuds) to the step's
--   WorldLayout.waypoint target ("shop", "duel"; the squeeze and capsule steps have none since spec 2026-10-11 §5 /
--   Batch 1), or a pulsing Lemon ring on a HUD button (HudController.element("squishies"): the inspect step; lobby
--   HUD, spec 2026-10-11: no dock, so Inspect is reached through the Squishies list). Reading: the ring's stroke fades in
--   and out once per PULSE_SECONDS (1 s, under §9.12's 3 Hz and the 1 Hz skeleton pulse); static under ReducedMotion.
--   The ring is our own frame in SD_Hud that follows the element's box (hidden with the HUD or the element), so
--   HudController needs no pulse API.
-- * The inspect step is recorded by the client: when UIController opens "inspect" (Part 6), OnboardingStep("inspect")
--   is sent once while the saved flag is false. The other steps are observed by the server. Reading: until the
--   "inspect" screen is registered, that step is passed over (OnboardingFormat ctx.unavailable), so the card never
--   waits on an Inspect button that does not exist.
-- * "onboarding" is a non-modal screen registered in init, so Settings shows "Replay tutorial", which opens it with
--   {replay = true}: a local replay from the first step that ignores and never changes the saved flags (no
--   OnboardingStep is sent). A replay step completes on the local signs of the same events: Got it (welcome), an
--   accepted SqueezeResult (squeeze), stats.boxesOpened rising or a new owned squishy (firstBox), a capsule level or
--   slot rising (capsule, OnboardingFormat.capsuleBought), Inspect opening (inspect), the queue turning Searching
--   (duel). Skip ends the replay.
-- * Done: when a run that showed a card completes (not by skipping), the done toast (Config.Onboarding.doneToastKey)
--   shows once for that run. A full state (a profile recovered after an OFFLINE start, §3.13) is a new baseline: no
--   toast for what it replaced.
-- * Layout (Part 8, rebuilt for the foam HUD): one row, the text (Body; Small on phones) beside the visible button and
--   as wide as that button leaves. It is placed again whenever HudController lays the HUD out (LayoutChanged) or its own
--   size changes. Reading (spec: never over the queue pill): the queue pill takes the spot under the Duel CTA, so on
--   every layout (lobby HUD, spec 2026-10-11) the card waits while the queue is Searching (it comes back with the same
--   step). The skip link always reads onboarding.skip "Skip tutorial" (§11.8: it ends the whole tutorial for good, so
--   it is never shortened). Got it (primary) and Skip (secondary) are Button touch targets and the visible one is
--   HudController's "onboarding" focus target (setFocusTarget), so a gamepad reaches it Down from the Duel CTA.
-- UI overhaul (2026-10-11, Candy UI): the coach card is a compact prompt at the bottom middle
-- (HudFormat.coachBottomPlacement, clear of the HUD groups and, on narrow layouts, the thumbstick zone and the touch
-- buttons), so the centre column stays open (the Duel CTA and the toasts at the top, the character in the middle); it
-- no longer pushes the toasts down. It wears a Coral rim (guidance) and pops in when a new step shows.
-- Public: startReplay(), debugState().

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local Create = require(Client.UI.Create)
local HudFormat = require(Client.UI.HudFormat)
local OnboardingFormat = require(Client.UI.OnboardingFormat)
local Scheduler = require(Client.Anim.Scheduler)
local Theme = require(Client.UI.Theme)
local Tweens = require(Client.Anim.Tweens)
local Waypoint = require(Client.UI.Waypoint)
local ControlsController = require(script.Parent.ControlsController)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

type Pulse = { name: string, cleanup: Cleanup.Cleanup }

-- Constants

local ONBOARDING = Config.Onboarding
local SCREEN = "onboarding"
local INSPECT_SCREEN = "inspect"
local REMOTE = "OnboardingStep"
local FIELD = "onboarding"
local WELCOME = "welcome"
local INSPECT_STEP = "inspect"
local SKIP_STEP: string = ONBOARDING.skipStepId
local HUD_GUI = "SD_Hud"
local COLUMN = HudFormat.COLUMN
local MIN_LABEL_WIDTH = 60 -- base px: the text never gets narrower than this
local SEARCHING = "Searching"
local TOUCH = Config.UI.Touch
local PULSE_SECONDS = 1 -- one fade cycle of the guidance ring (<= 1 Hz)
local PULSE_GAP_PX = 4 -- the ring stands this far outside the element
local PULSE_MIN_TRANSPARENCY = 0
local PULSE_MAX_TRANSPARENCY = 0.7
local PULSE_NAME = "SD_OnboardingPulse"
-- UI overhaul: a new step's pop (the toast pop's numbers).
local POP_FROM = Config.UI.motion.toast.popFrom
local POP_SPEC: Tweens.Spec = { ms = 260, style = Enum.EasingStyle.Back, direction = Enum.EasingDirection.Out }
local STATE_FIELDS = { "onboarding", "dataStatus", "coins" }

-- Module table

local OnboardingController = {}

-- Private

local log = Log.new("Onboarding")
local cleanup: Cleanup.Cleanup? = nil
local card: Frame? = nil
local textLabel: TextLabel? = nil
local gotItButton: Button.Button? = nil
local skipButton: Button.Button? = nil
local replay: { [string]: boolean }? = nil -- the local replay's done set (nil = no replay)
local pendingDone: { [string]: boolean } = {} -- steps sent by this client and not yet in the saved state
local pendingSkip = false
local inspectSent = false
local runActive = false -- a card was shown since the last baseline (the done toast needs it)
local doneToasts = 0
local shownStep: string? = nil
local shownText = "" -- the shown step's text and button (the card's height at a width, HudFormat.coachHeight)
local shownButton = ""
local waypointName: string? = nil
local waypoint: Waypoint.Handle? = nil
local pulse: Pulse? = nil
local lastPlace: HudFormat.CoachPlace? = nil

-- Places the card at the top centre (defined with the card below; refresh() calls it).
local layoutCard: () -> ()

local function inputKind(): OnboardingFormat.InputKind
	local preferred = ControlsController.preferredInput()
	if preferred == Enum.PreferredInput.Gamepad then
		return "gamepad"
	elseif preferred == Enum.PreferredInput.Touch then
		return "touch"
	end
	return "keyboard"
end

-- The saved onboarding state with this client's pending steps and skip folded in (they reach the server first).
local function effectiveState(): any
	local saved = StateController.get(FIELD)
	local done = OnboardingFormat.done(saved)
	for id in pendingDone do
		done[id] = true
	end
	local skipped = (type(saved) == "table" and saved.skipped == true) or pendingSkip
	return { v = if type(saved) == "table" then saved.v else nil, done = done, skipped = skipped }
end

-- Steps whose screen is not registered yet are passed over (the Inspect step until Part 6's "inspect" exists).
local function unavailable(): { [string]: boolean }?
	if UIController.isRegistered(INSPECT_SCREEN) then
		return nil
	end
	return { [INSPECT_STEP] = true }
end

local function context(): OnboardingFormat.Context
	return {
		onboarding = effectiveState(),
		ready = StateController.isProfileReady(),
		replay = replay,
		coins = StateController.coins(),
		input = inputKind(),
		unavailable = unavailable(),
	}
end

local function doneSet(): { [string]: boolean }
	return if replay then replay else effectiveState().done :: { [string]: boolean }
end

-- Guidance -----------------------------------------------------------------------------------------------------------

local function clearWaypoint()
	local handle = waypoint
	waypoint, waypointName = nil, nil
	if handle then
		handle:destroy()
	end
end

local function setWaypoint(name: string?)
	if name == waypointName then
		return
	end
	clearWaypoint()
	local target = if name then WorldLayout.waypoint(name) else nil
	if name and target then
		waypoint = Waypoint.show(target)
		waypointName = name
	end
end

local function clearPulse()
	local current = pulse
	pulse = nil
	if current then
		current.cleanup:clean()
	end
end

-- True when `object` and every GuiObject above it are Visible.
local function onScreen(object: GuiObject): boolean
	local node: Instance? = object
	while node and node:IsA("GuiObject") do
		if not (node :: GuiObject).Visible then
			return false
		end
		node = node.Parent
	end
	return node ~= nil
end

-- A Lemon ring around the HUD element, fading in and out (static under ReducedMotion). Reading: the ring is a direct
-- child of SD_Hud that follows the element's absolute box every frame, not a child of the element: the HUD buttons
-- size themselves to their content (AutomaticSize), so a ring inside one would grow it.
local function setPulse(name: string?)
	if pulse and name and pulse.name == name then
		return
	end
	clearPulse()
	local element = if name then HudController.element(name) else nil
	if name == nil or element == nil then
		return
	end
	local target = element :: GuiObject
	local gui = UIController.screenGui(HUD_GUI)
	local pc = Cleanup.new()
	local ring: Frame = Create("Frame", {
		Name = PULSE_NAME,
		BackgroundTransparency = 1,
		Active = false,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	})
	pc:add(ring)
	Theme.corner(Theme.Radius.medium + PULSE_GAP_PX, ring)
	local stroke = Theme.stroke(Theme.Colors.lemon, Theme.Stroke.thick, ring)
	local elapsed = 0
	pc:add(Scheduler.add(function(dt: number): boolean
		local shown = target.Parent ~= nil and HudController.isShown() and onScreen(target)
		ring.Visible = shown
		if not shown then
			return true
		end
		local scale = UIController.scale()
		local s = if scale > 0 then scale else 1
		local offset = (target.AbsolutePosition - gui.AbsolutePosition) / s
		local size = target.AbsoluteSize / s
		ring.Position = UDim2.fromOffset(offset.X - PULSE_GAP_PX, offset.Y - PULSE_GAP_PX)
		ring.Size = UDim2.fromOffset(size.X + 2 * PULSE_GAP_PX, size.Y + 2 * PULSE_GAP_PX)
		if Tweens.reducedMotion() then
			stroke.Transparency = PULSE_MIN_TRANSPARENCY
		else
			elapsed = (elapsed + dt) % PULSE_SECONDS
			local wave = 0.5 - 0.5 * math.cos(2 * math.pi * elapsed / PULSE_SECONDS)
			stroke.Transparency = PULSE_MIN_TRANSPARENCY + (PULSE_MAX_TRANSPARENCY - PULSE_MIN_TRANSPARENCY) * wave
		end
		return true
	end, "render"))
	pulse = { name = name, cleanup = pc }
end

-- Card ---------------------------------------------------------------------------------------------------------------

local function showDoneToast()
	doneToasts += 1
	local text = Strings.resolve(ONBOARDING.doneToastKey)
	if text then
		UIController.toast(text, "success")
	end
end

-- Recomputes the card. `baseline` (a full state): no done toast for what changed, the run restarts from here.
local function refresh(baseline: boolean?)
	local model = OnboardingFormat.model(context())
	if model then
		runActive = true
	elseif baseline then
		runActive = false
	elseif runActive and OnboardingFormat.isComplete(doneSet(), unavailable()) then
		runActive = false
		showDoneToast()
		if replay then
			replay = nil
			model = OnboardingFormat.model(context()) -- back to the saved state (complete or skipped: hidden)
		end
	end
	-- Reading (spec: never over the queue pill): the pill takes the spot under the Duel CTA, so the card waits while
	-- queued (every layout since spec 2026-10-11).
	local waiting = StateController.queue().state == SEARCHING
	local visible = model ~= nil and not StateController.isLobbyLocked() and not waiting
	local previousStep = shownStep
	shownStep = if visible and model then model.stepId else nil
	local frame = card
	if frame then
		frame.Visible = visible
		-- UI overhaul: a new step pops in (Back Out; a scale effect, so none under ReducedMotion).
		local pop = frame:FindFirstChild("Pop")
		if visible and shownStep ~= previousStep and pop and pop:IsA("UIScale") then
			Tweens.scale(pop, POP_FROM, 1, POP_SPEC)
		end
	end
	local target: GuiObject? = nil
	if visible and model then
		if textLabel then
			textLabel.Text = model.text
		end
		shownText = model.text
		shownButton = if model.gotIt then Strings.common.gotIt else Strings.onboarding.skip
		if gotItButton then
			gotItButton.root.Visible = model.gotIt
			if model.gotIt then
				target = gotItButton.root
			end
		end
		if skipButton then
			skipButton.root.Visible = model.skip
			if model.skip and target == nil then
				target = skipButton.root
			end
		end
		setWaypoint(model.waypoint)
		setPulse(model.pulse)
	else
		setWaypoint(nil)
		setPulse(nil)
	end
	layoutCard()
	HudController.setFocusTarget("onboarding", target)
end

local function markReplay(stepId: string)
	local current = replay
	if current and current[stepId] ~= true then
		current[stepId] = true
		refresh()
	end
end

local function onGotIt()
	if replay then
		markReplay(WELCOME)
		return
	end
	if NetController.fire(REMOTE, WELCOME) then
		pendingDone[WELCOME] = true
		refresh()
	end
end

local function onSkip()
	if replay then
		replay = nil
		runActive = false
		refresh(true)
		return
	end
	if NetController.fire(REMOTE, SKIP_STEP) then
		pendingSkip = true
		runActive = false
		refresh(true)
	end
end

local function onInspectOpened()
	if replay then
		markReplay(INSPECT_STEP)
		return
	end
	if inspectSent or not StateController.isProfileReady() then
		return
	end
	if OnboardingFormat.done(StateController.get(FIELD))[INSPECT_STEP] == true then
		return
	end
	if NetController.fire(REMOTE, INSPECT_STEP) then
		inspectSent = true
		pendingDone[INSPECT_STEP] = true
		refresh()
	end
end

local function buildCard(c: Cleanup.Cleanup)
	local frame = Theme.panel({
		Name = "Hud_OnboardingCard",
		Position = UDim2.fromOffset(COLUMN.edge, COLUMN.edge),
		Size = UDim2.fromOffset(COLUMN.coachWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, Theme.Radius.panel, COLUMN.coachPadding)
	Theme.list(
		Enum.FillDirection.Horizontal,
		COLUMN.coachGap,
		frame,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	textLabel = Theme.label({
		Name = "Text",
		Text = "",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(COLUMN.coachWidth - 200, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, "Body")
	local gotIt = Button.new({
		name = "Onboarding_GotItButton",
		text = Strings.common.gotIt,
		kind = "primary",
		height = TOUCH.minTarget,
		layoutOrder = 2,
		parent = frame,
		onActivated = onGotIt,
	})
	c:add(gotIt)
	gotItButton = gotIt
	local skip = Button.new({
		name = "Onboarding_SkipButton",
		text = Strings.onboarding.skip,
		height = TOUCH.minTarget,
		layoutOrder = 3,
		parent = frame,
		onActivated = onSkip,
	})
	skip.root.Visible = false
	c:add(skip)
	skipButton = skip
	frame.Parent = UIController.screenGui(HUD_GUI)
	c:add(frame)
	card = frame
	-- UI overhaul: guidance wears the brand colour on its rim; a new step pops in (refresh).
	Theme.rim(frame, Theme.Accents.strawberry.face, 0.15, Theme.Stroke.medium)
	Create("UIScale", { Name = "Pop", Parent = frame })
	-- UI overhaul: at the bottom middle the card no longer meets the toasts (they stay under the Duel CTA).
	-- The text's width follows the visible button's real width; the place follows the card's height.
	c:add(gotIt.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layoutCard()
	end))
	c:add(skip.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layoutCard()
	end))
end

-- The coach card's place (HudFormat.coachPlacement, from HudController.layoutRects(): a row gap under the Duel CTA,
-- clear of the left column, the tiles and the top-right group) and its parts: one row, the text (Body; Small on phones)
-- beside the visible button and as wide as that button leaves (measured; HudFormat's estimate until the button has a
-- size).
layoutCard = function()
	local frame, label = card, textLabel
	if frame == nil or label == nil then
		return
	end
	local compact = UIController.layoutClass() == "compact"
	local kind: Theme.TextKind = if compact then "Small" else "Body"
	if label:GetAttribute("SD_TextKind") ~= kind then
		Theme.text(label, kind)
	end
	local gotIt = gotItButton
	local showsGotIt = gotIt ~= nil and gotIt.root.Visible
	local button = if showsGotIt then gotIt else skipButton
	local scale = UIController.scale()
	local measured = if button and scale > 0 then button.root.AbsoluteSize.X / scale else 0
	local textScale = HudController.textScale()
	local buttonWidth = if measured > 0
		then measured
		else HudFormat.buttonWidth(if showsGotIt then Strings.common.gotIt else Strings.onboarding.skip, textScale)
	local rects = HudController.layoutRects()
	local blockers: { HudFormat.Rect } = {}
	for _, rect in { rects.left, rects.tiles, rects.right } do
		if rect then
			table.insert(blockers, rect)
		end
	end
	-- UI overhaul: the bottom prompt keeps clear of the thumbstick zone and the touch buttons on narrow layouts.
	for _, rect in rects.reserved do
		table.insert(blockers, rect)
	end
	local text, buttonText = shownText, shownButton
	local place = HudFormat.coachBottomPlacement({
		canvas = rects.canvas,
		blockers = blockers,
		heightAt = function(width: number): number
			return HudFormat.coachHeight(width, textScale, scale, text, buttonText, compact)
		end,
	})
	lastPlace = place
	local position = UDim2.fromOffset(math.floor(place.x), math.floor(place.y))
	if frame.Position ~= position then
		frame.Position = position
	end
	local size = UDim2.fromOffset(math.floor(place.width), 0)
	if frame.Size ~= size then
		frame.Size = size
	end
	local labelWidth = math.max(MIN_LABEL_WIDTH, place.width - 2 * COLUMN.coachPadding - buttonWidth - COLUMN.coachGap)
	local labelSize = UDim2.fromOffset(math.floor(labelWidth), 0)
	if label.Size ~= labelSize then
		label.Size = labelSize
	end
end

-- The text a Button shows (its "Label"), for debugState.
local function buttonLabel(button: Button.Button?): string?
	local label = if button then button.root:FindFirstChild("Label", true) else nil
	return if label and label:IsA("TextLabel") then label.Text else nil
end

-- Public -------------------------------------------------------------------------------------------------------------

-- Replays the tutorial locally from the first step (Settings "Replay tutorial"); the saved flags never change.
function OnboardingController.startReplay()
	replay = {}
	runActive = false
	refresh()
end

-- Small table for Studio debug hooks.
function OnboardingController.debugState(): { [string]: any }
	local replayDone = {}
	local current = replay
	if current then
		for id in current do
			table.insert(replayDone, id)
		end
	end
	table.sort(replayDone)
	return {
		step = shownStep,
		visible = card ~= nil and card.Visible,
		replay = replay ~= nil,
		replayDone = replayDone,
		waypoint = waypointName,
		pulse = if pulse then pulse.name else nil,
		pendingSkip = pendingSkip,
		inspectSent = inspectSent,
		doneToasts = doneToasts,
		-- The coach card's place (HudFormat.coachPlacement, base px): fits = it ends above the toasts.
		x = if lastPlace then lastPlace.x else nil,
		width = if card then card.Size.X.Offset else nil,
		fits = if lastPlace then lastPlace.fits else nil,
		skipText = buttonLabel(skipButton), -- always onboarding.skip "Skip tutorial" (§11.8)
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function OnboardingController.init()
	local c = Cleanup.new()
	cleanup = c
	buildCard(c)
	layoutCard()
	-- The layout class decides the text size.
	c:add(UIController.LayoutChanged:connect(function()
		refresh()
	end))
	c:add(HudController.LayoutChanged:connect(function()
		layoutCard()
	end))

	c:add(UIController.registerScreen(SCREEN, {
		modal = false,
		onOpen = function(params: any?)
			if type(params) == "table" and params.replay == true then
				OnboardingController.startReplay()
			else
				refresh()
			end
		end,
	}))

	local function onState()
		refresh(StateController.isApplyingFull())
	end
	for _, field in STATE_FIELDS do
		c:add(StateController.changed(field):connect(onState))
	end
	c:add(StateController.LobbyLockChanged:connect(function()
		refresh()
	end))
	c:add(ControlsController.PreferredInputChanged:connect(function()
		refresh()
	end))
	c:add(UIController.ScreenOpened:connect(function(name: string)
		if name == INSPECT_SCREEN then
			onInspectOpened()
		end
	end))

	-- Replay: the local signs of each server-observed step (only while a replay runs).
	c:add(NetController.onSqueezeResult(function(payload: any)
		if replay and type(payload) == "table" and payload.ok == true then
			markReplay("squeeze")
		end
	end))
	c:add(StateController.changed("stats"):connect(function(value: any, old: any)
		if replay and not StateController.isApplyingFull() and type(value) == "table" and type(old) == "table" then
			if type(value.boxesOpened) == "number" and value.boxesOpened > (old.boxesOpened or 0) then
				markReplay("firstBox")
			end
		end
	end))
	c:add(StateController.changed("owned"):connect(function(value: any, old: any)
		if replay and not StateController.isApplyingFull() and type(value) == "table" and type(old) == "table" then
			for id in value do
				if old[id] == nil then
					markReplay("firstBox")
					return
				end
			end
		end
	end))
	c:add(StateController.changed("capsules"):connect(function(value: any, old: any)
		if replay and not StateController.isApplyingFull() and OnboardingFormat.capsuleBought(value, old) then
			markReplay("capsule")
		end
	end))
	c:add(StateController.QueueChanged:connect(function(new: StateController.QueueView, old: StateController.QueueView)
		if replay and new.state == SEARCHING and old.state ~= SEARCHING then
			markReplay("duel")
		end
		if new.state ~= old.state then
			refresh() -- the card waits while queued
		end
	end))

	c:add(function()
		clearWaypoint()
		clearPulse()
		HudController.setFocusTarget("onboarding", nil)
		card, textLabel, gotItButton, skipButton, lastPlace = nil, nil, nil, nil, nil
		replay, shownStep, shownText, shownButton = nil, nil, "", ""
		table.clear(pendingDone)
		pendingSkip, inspectSent, runActive = false, false, false
	end)
	refresh(true)
end

function OnboardingController.start()
	-- The first full state arrived before start (boot step 5): it is the baseline.
	local ok, err = pcall(function(): any
		refresh(true)
		return nil
	end)
	if not ok then
		log:error("onboarding refresh failed:", err)
	end
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function OnboardingController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return OnboardingController
