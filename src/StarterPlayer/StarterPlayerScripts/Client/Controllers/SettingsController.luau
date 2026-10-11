--!strict
-- SettingsController (client only). DESIGN §11.6 (Settings), §2.8 (SetSettings), §11.9 (volumes), §9.12 (camera shake),
-- §11.4 (focus), §11.8 ("Replay tutorial").
-- The "settings" modal (lobby only; refused from Matched through Returning by UIController): Music and Sound effects
-- sliders 0-100 (drag, tap, DPad left/right in steps of Config.UI.Settings.sliderStep), Camera shake and Show tips
-- toggles, Replay tutorial, Close: exactly §11.6's list. There is no in-game "Reduce motion" switch (an unapproved
-- §16 proposal); reduced motion is Roblox's own GuiService.ReducedMotionEnabled (§9.12, Anim/Tweens.reducedMotion).
-- * Applied instantly on the client: every change sets a StateController override of "settings" (the merged server
--   value + local edits), so SoundController volumes and the camera-shake check follow at once.
-- * Saved through SetSettings with a Config.UI.Settings.saveDebounceSeconds (1.5 s) debounce after the last change; the
--   table holds only the keys that differ from the server's value (UI/SettingsFormat.patch). A send refused locally
--   (NetController's rate bucket) is retried after another debounce. When the server's settings arrive and no change
--   is waiting, the server's value wins and the override is cleared (a server that never answers leaves the override
--   for the session).
-- * While no music id is approved the Music slider reads "No music yet"; while no sound effect id is approved the
--   effects slider reads "No sound effects yet" (SoundController.hasAnyIn; not on phones since fix round 2, below).
--   The slider still works and saves.
-- * Replay tutorial opens the "onboarding" screen with {replay = true} (OnboardingController, Part 7); the button shows
--   only once that screen is registered.
-- * Part 8 (§11.2 audit): the panel's width follows the screen (Layout.modalWidth, at most PANEL_WIDTH) like its body
--   height; each slider's touch target is its whole row (Slider: the track is the row's full width and
--   Config.UI.Touch.minTarget tall, 44.2 px at scale 0.85), not the 26 px knob; the gamepad focus on open is the Music
--   slider's track.
-- * Foam UI restyle (spec 2026-10-09; behaviour, names and timings unchanged): a foam panel with the title in a header
--   tab and Close straddling the top-right corner (the panel moves down by half of what hangs above it, as in Quests);
--   the two sliders and the two toggles sit in two inset fields (Biscuit), each slider's value in a chip, the
--   captions in InkUI (Ink2 is under 4.6:1 on Biscuit); the body's height comes from SettingsFormat.bodyHeight with
--   the chrome measured (before, a fixed 60 px guess).
-- * Foam fix batch (2026-10-09): on a phone the rows opened cut off at the top and the bottom ("No music yet" cut in
--   half under the tab, the Music row out of reach): the body's list was centred, and a list centred in a
--   ScrollingFrame shorter than it is centred on the window, so its top sat above the canvas. It is top-aligned now,
--   and the rows open scrolled to the top every time.
-- * Foam fix round 2 (2026-10-09): on a phone the fold fell exactly under the volumes field, so the two switches were
--   out of sight with no sign of them. On the compact layout the "No music yet" / "No sound effects yet" notes stay
--   hidden (SettingsFormat.captionShown), so the switches field's top shows under the volumes; on touch the body's
--   scroll bar stays on screen while the rows are longer than it (UI/Components/ScrollHint, "ScrollRail" on the panel).
-- * First person (spec 2026-10-10 §3.8): a third switch "First-person duels" in the switches field. It is
--   FirstPersonController's session switch (on at every join): it reads isEnabled() when built and on every open and
--   calls only setEnabled; it is never saved, never in the SetSettings patch (Validate.settings refuses an unknown key
--   whole). The next duel uses it, and the practice range as soon as Settings closes (a modal pauses first person).
-- Stable names: Settings_MusicSlider, Settings_SfxSlider, Settings_CameraShakeToggle, Settings_ShowTipsToggle,
-- Settings_FirstPersonToggle, Settings_ReplayTutorialButton, Settings_CloseButton.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local Chip = require(Client.UI.Components.Chip)
local Create = require(Client.UI.Create)
local Layout = require(Client.UI.Layout)
local ScrollHint = require(Client.UI.Components.ScrollHint)
local SettingsFormat = require(Client.UI.SettingsFormat)
local Slider = require(Client.UI.Components.Slider)
local Theme = require(Client.UI.Theme)
local Toggle = require(Client.UI.Components.Toggle)
local FirstPersonController = require(script.Parent.FirstPersonController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Constants

local SCREEN = "settings"
local ONBOARDING_SCREEN = "onboarding"
local FIELD = "settings"
local REMOTE = "SetSettings"
local SETTINGS = Config.UI.Settings
local DATA = Config.Data
local TOUCH = Config.UI.Touch
local MODAL_GUI = "SD_Modal"
local PANEL_WIDTH = 560
local MARGIN_PX = 24
local SCROLLBAR_PX = 6
local MAX_HEIGHT_SHARE = 0.86 -- reading: the panel never covers more than this share of the screen height
-- Foam UI (readings: DESIGN gives no numbers): the body's inner padding keeps the fields inside its clip; Close sits
-- CLOSE_INSET from the panel's right edge.
local BODY_PAD_PX = 3
local CLOSE_INSET = 16
local MUSIC_GROUPS = { "Music" }
local SFX_GROUPS = { "SFX", "UI", "Ambient" }

-- Module table

local SettingsController = {}

-- Private

type SliderRow = { slider: Slider.Slider, value: Chip.Chip, caption: TextLabel }

local log = Log.new("Settings")
local cleanup: Cleanup.Cleanup? = nil
local edits: SettingsFormat.Edits = {}
local saveTimer: thread? = nil
local rows: { [string]: SliderRow } = {}
local toggles: { [string]: Toggle.Toggle } = {}
local firstPersonToggle: Toggle.Toggle? = nil -- the session switch: not in `toggles` (not a saved setting)
local replayButton: Button.Button? = nil
local closeButton: Button.Button? = nil
local panel: Frame? = nil
local bodyScroll: ScrollingFrame? = nil -- the rows' scrolling body (it opens at the top, onOpen)

local function serverSettings(): Types.Settings?
	local value = StateController.serverValue(FIELD)
	return if type(value) == "table" then value else nil
end

local function desired(): Types.Settings
	return SettingsFormat.merge(serverSettings(), edits)
end

local function refreshControls()
	local current = StateController.settings()
	for key, row in rows do
		local value = (current :: any)[key]
		if type(value) == "number" then
			row.slider:setValue(value)
			row.value:setText(SettingsFormat.volumeText(value))
		end
	end
	for key, toggle in toggles do
		local value = (current :: any)[key]
		if type(value) == "boolean" then
			toggle:setValue(value)
		end
	end
	if firstPersonToggle then
		firstPersonToggle:setValue(FirstPersonController.isEnabled())
	end
	if replayButton then
		replayButton.root.Visible = UIController.isRegistered(ONBOARDING_SCREEN)
	end
end

local function refreshCaptions()
	local music, sfx = rows.music, rows.sfx
	local class = UIController.layoutClass()
	if music then
		music.caption.Visible = SettingsFormat.captionShown(class, SoundController.hasAnyIn(MUSIC_GROUPS))
	end
	if sfx then
		sfx.caption.Visible = SettingsFormat.captionShown(class, SoundController.hasAnyIn(SFX_GROUPS))
	end
end

local function save()
	saveTimer = nil
	local wanted = desired()
	local patch = SettingsFormat.patch(serverSettings(), wanted)
	if SettingsFormat.isEmpty(patch) then
		edits = {}
		StateController.setOverride(FIELD, nil)
		return
	end
	if not NetController.fire(REMOTE, patch) then
		-- Refused locally (rate bucket) or not connected: try again after another debounce.
		log:debug("SetSettings not sent; retrying")
		saveTimer = task.delay(SETTINGS.saveDebounceSeconds, save)
	end
end

local function change(key: string, value: any)
	edits[key] = value
	StateController.setOverride(FIELD, desired())
	if saveTimer then
		task.cancel(saveTimer)
	end
	saveTimer = task.delay(SETTINGS.saveDebounceSeconds, save)
end

local function onServerSettings()
	if saveTimer ~= nil then
		return -- the player is still changing things; the next save compares against this value
	end
	edits = {}
	StateController.setOverride(FIELD, nil)
	refreshControls()
end

-- Builders -----------------------------------------------------------------------------------------------------------

local function sliderRow(
	c: Cleanup.Cleanup,
	parent: Instance,
	order: number,
	key: string,
	name: string,
	label: string,
	captionText: string
)
	local frame: Frame = Create("Frame", {
		Name = name .. "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.list(Enum.FillDirection.Vertical, 2, frame, Enum.HorizontalAlignment.Left)
	local header: Frame = Create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = frame,
	})
	Theme.label({
		Name = "Label",
		Text = label,
		Size = UDim2.fromScale(0.7, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	}, "Body", Enum.FontWeight.Bold)
	-- Foam UI: the value in a chip at the right ("40%").
	local value = Chip.new({ name = "Value", text = "", parent = header })
	value.root.AnchorPoint = Vector2.new(1, 0)
	value.root.Position = UDim2.fromScale(1, 0)
	c:add(value)
	local current = (StateController.settings() :: any)[key]
	local slider = Slider.new({
		name = name,
		min = DATA.settingsMin,
		max = DATA.settingsMax,
		step = SETTINGS.sliderStep,
		value = if type(current) == "number" then current else 0,
		layoutOrder = 2,
		parent = frame,
		onChanged = function(newValue: number)
			value:setText(SettingsFormat.volumeText(newValue))
			change(key, SettingsFormat.volume(newValue))
		end,
	})
	c:add(slider)
	-- InkUI: Ink2 is only about 4.6:1 on the Biscuit field.
	local caption = Theme.label({
		Name = "Caption",
		Text = captionText,
		LayoutOrder = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = frame,
	}, "Small")
	value:setText(SettingsFormat.volumeText(slider:getValue()))
	rows[key] = { slider = slider, value = value, caption = caption }
end

local function toggleRow(
	c: Cleanup.Cleanup,
	parent: Instance,
	order: number,
	key: string,
	name: string,
	label: string,
	onChanged: (value: boolean) -> ()
)
	local current = (StateController.settings() :: any)[key]
	local toggle = Toggle.new({
		name = name,
		text = label,
		value = if type(current) == "boolean" then current else false,
		layoutOrder = order,
		parent = parent,
		onChanged = onChanged,
	})
	c:add(toggle)
	toggles[key] = toggle
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local width = math.min(PANEL_WIDTH, Layout.modalWidth(gui.AbsoluteSize.X, UIController.scale(), MARGIN_PX))
	local root = Theme.panel({
		Name = "Settings",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(if width > 0 then width else PANEL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, Theme.Radius.panel, Theme.Padding.large)
	c:add(root)
	-- Foam UI: room at the top for Close's lower half, then the header tab (it raises the padding for its own half).
	local pad = root:FindFirstChildOfClass("UIPadding") :: UIPadding
	pad.PaddingTop = UDim.new(0, math.ceil(TOUCH.closeButton / 2) + Theme.Padding.small)
	local tab = Theme.headerTab(root, Strings.settings.title)
	-- The header tab sits on the panel itself, so the rows go in a Content frame with the list.
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.medium, content, Enum.HorizontalAlignment.Left)

	local close = Button.new({
		name = "Settings_CloseButton",
		text = Strings.common.close,
		height = TOUCH.closeButton,
		parent = root,
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	-- Straddles the panel's top edge at the right, like the tab in the middle.
	close.root.AnchorPoint = Vector2.new(1, 0.5)
	close.root.Position = UDim2.new(1, Theme.Padding.large - CLOSE_INSET, 0, -pad.PaddingTop.Offset)
	close.root.ZIndex = tab.ZIndex
	close.root.Modal = true -- frees the cursor in shift lock / first person (§10.4 step 4)
	c:add(close)
	closeButton = close

	-- The rows scroll when the screen is too short for them (phones in landscape).
	local body: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR_PX,
		ScrollBarImageColor3 = Theme.Colors.inkUI,
		LayoutOrder = 1,
		Parent = content,
	})
	-- Top-aligned (fix batch): a centred list taller than the window was centred on the window, its top out of reach.
	local list = Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.medium,
		body,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Top
	)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, BODY_PAD_PX), -- the Replay button's outline and a knob at 0 stay inside the clip
		PaddingBottom = UDim.new(0, BODY_PAD_PX),
		PaddingLeft = UDim.new(0, BODY_PAD_PX),
		PaddingRight = UDim.new(0, SCROLLBAR_PX + 4),
		Parent = body,
	})
	-- Fix round 2: on touch the body's scroll bar stays on screen while the rows are longer than it (UI/Components/
	-- ScrollHint), on the panel over the body's right edge (the body is the first row of Content); fitBody sizes it.
	local scrollHint = ScrollHint.new({ scroll = body, parent = root })
	scrollHint.root.AnchorPoint = Vector2.new(1, 0)
	scrollHint.root.Position = UDim2.fromScale(1, 0)
	c:add(scrollHint)
	-- Part 8: the width follows the screen. Foam UI: the body's height from SettingsFormat.bodyHeight with the chrome
	-- measured (the tab and Close above the panel, its paddings), and the panel moves down by half of what hangs above
	-- it, so the whole stays centred.
	local function fitBody()
		local scale = UIController.scale()
		local pop = root:FindFirstChild("SD_OpenScale")
		local s = scale * (if pop and pop:IsA("UIScale") then pop.Scale else 1)
		local screen = gui.AbsoluteSize
		if not (scale > 0) or not (s > 0) or screen.X <= 0 or screen.Y <= 0 then
			return
		end
		local fit = math.min(PANEL_WIDTH, Layout.modalWidth(screen.X, scale, MARGIN_PX))
		local size = UDim2.fromOffset(if fit > 0 then fit else PANEL_WIDTH, 0)
		if root.Size ~= size then
			root.Size = size
		end
		local above = math.max(tab.AbsoluteSize.Y / s, TOUCH.closeButton) / 2
		local position = UDim2.new(0.5, 0, 0.5, math.floor(above / 2 + 0.5))
		if root.Position ~= position then
			root.Position = position
		end
		local current = body.AbsoluteSize.Y / s
		local chrome = root.AbsoluteSize.Y / s - current + above
		local height = math.ceil(
			SettingsFormat.bodyHeight(
				screen.Y / scale,
				list.AbsoluteContentSize.Y / s + 2 * BODY_PAD_PX,
				chrome,
				MAX_HEIGHT_SHARE,
				TOUCH.minTarget
			)
		)
		if math.abs(height - current) >= 1 then
			body.Size = UDim2.new(1, 0, 0, height)
		end
		local railSize = UDim2.fromOffset(SCROLLBAR_PX, body.Size.Y.Offset)
		if scrollHint.root.Size ~= railSize then
			scrollHint.root.Size = railSize
		end
	end
	c:add(list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitBody))
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBody))
	c:add(UIController.LayoutChanged:connect(function()
		refreshCaptions() -- fix round 2: the notes hide on the compact layout
		fitBody()
	end))

	-- Two inset fields: the volumes, then the two switches.
	local function field(name: string, order: number): Frame
		local frame = Theme.inset({
			Name = name,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			Parent = body,
		}, Theme.Radius.button, Theme.Padding.medium)
		Theme.list(Enum.FillDirection.Vertical, Theme.Padding.medium, frame, Enum.HorizontalAlignment.Left)
		return frame
	end
	local volumes = field("Volumes", 1)
	local switches = field("Switches", 2)
	sliderRow(c, volumes, 1, "music", "Settings_MusicSlider", Strings.settings.music, Strings.settings.noMusic)
	sliderRow(c, volumes, 2, "sfx", "Settings_SfxSlider", Strings.settings.sfx, Strings.settings.noSfx)
	toggleRow(c, switches, 1, "cameraShake", "Settings_CameraShakeToggle", Strings.settings.cameraShake, function(on)
		change("cameraShake", on)
	end)
	toggleRow(c, switches, 2, "showTips", "Settings_ShowTipsToggle", Strings.settings.showTips, function(on)
		change("showTips", on)
	end)
	-- First person (spec 2026-10-10 §3.8): its own row, not toggleRow / change(): the value is FirstPersonController's
	-- session switch (on at every join), never a saved setting, so it stays out of `toggles`, `edits` and SetSettings.
	local firstPerson = Toggle.new({
		name = "Settings_FirstPersonToggle",
		text = Strings.settings.firstPerson,
		value = FirstPersonController.isEnabled(),
		layoutOrder = 3,
		parent = switches,
		onChanged = FirstPersonController.setEnabled,
	})
	c:add(firstPerson)
	firstPersonToggle = firstPerson

	local replay = Button.new({
		name = "Settings_ReplayTutorialButton",
		text = Strings.settings.replayTutorial,
		height = TOUCH.primaryButton,
		layoutOrder = 3,
		parent = body,
		onActivated = function()
			UIController.close(SCREEN, "replayTutorial")
			UIController.open(ONBOARDING_SCREEN, { replay = true })
		end,
	})
	c:add(replay)
	replayButton = replay
	bodyScroll = body
	panel = root
	fitBody()
	refreshCaptions()
	refreshControls()
	return root
end

-- Public -------------------------------------------------------------------------------------------------------------

-- True while a change waits for its debounced save.
function SettingsController.isSavePending(): boolean
	return saveTimer ~= nil
end

-- Small table for Studio debug hooks.
function SettingsController.debugState(): { [string]: any }
	return {
		built = panel ~= nil,
		pending = saveTimer ~= nil,
		edits = table.clone(edits),
		override = StateController.hasOverride(FIELD),
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function SettingsController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(UIController.registerScreen(SCREEN, {
		build = build,
		onOpen = function()
			refreshCaptions()
			refreshControls()
			-- Fix batch: the rows always open at the top (the Music row first), however the list was left.
			local scroll = bodyScroll
			if scroll then
				scroll.CanvasPosition = Vector2.zero
			end
		end,
		primary = function(): GuiObject?
			local music = rows.music
			if music then
				return music.slider.track
			end
			return if closeButton then closeButton.root else nil -- Part 8: never nothing
		end,
	}))
	c:add(StateController.ServerChanged:connect(function(field: string)
		if field == FIELD then
			onServerSettings()
		end
	end))
	c:add(StateController.changed(FIELD):connect(function()
		if UIController.isOpen(SCREEN) then
			refreshControls()
		end
	end))
	c:add(function()
		if saveTimer then
			task.cancel(saveTimer)
			saveTimer = nil
		end
		edits = {}
		table.clear(rows)
		table.clear(toggles)
		firstPersonToggle, replayButton, closeButton, panel, bodyScroll = nil, nil, nil, nil, nil
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function SettingsController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return SettingsController
