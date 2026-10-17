--!strict
-- SettingsController (client only). DESIGN §11.6 (Settings), §2.8 (SetSettings), §11.9 (volumes), §9.12 (camera shake),
-- §11.4 (focus), §11.8 ("Replay tutorial").
-- The "settings" modal (lobby only; refused from Matched through Returning by UIController): Music and Sound effects
-- sliders 0-100 (drag, tap, DPad left/right in steps of Config.UI.Settings.sliderStep), Camera shake and Show tips
-- toggles, Replay tutorial, Close: §11.6's list. UI FINAL R9 adds the design's Sound effects and Reduced motion
-- switches (below); Roblox's own GuiService.ReducedMotionEnabled still counts too (§9.12, Anim/Tweens.reducedMotion).
-- * Applied instantly on the client: every change sets a StateController override of "settings" (the merged server
--   value + local edits), so SoundController volumes and the camera-shake check follow at once.
-- * Saved through SetSettings with a Config.UI.Settings.saveDebounceSeconds (1.5 s) debounce after the last change; the
--   table holds only the keys that differ from the server's value (UI/SettingsFormat.patch). A send refused locally
--   (NetController's rate bucket) is retried after another debounce. When the server's settings arrive and no change
--   is waiting, the server's value wins and the override is cleared (a server that never answers leaves the override
--   for the session).
-- * While no music id is approved the Music row has "No music yet" under it; while no sound effect id is approved the
--   Volume row has "No sound effects yet" (SoundController.hasAnyIn; not on phones since fix round 2, below). The
--   slider still works and saves.
-- * Replay tutorial opens the "onboarding" screen with {replay = true} (OnboardingController, Part 7); its row shows
--   only once that screen is registered.
-- * Part 8 (§11.2 audit): each slider's touch target is its whole track (Slider: Config.UI.Touch.minTarget tall), not
--   the knob.
-- * Foam fix batch (2026-10-09): the rows are top-aligned and open scrolled to the top every time (a list centred in a
--   ScrollingFrame shorter than it was centred on the window, its top out of reach).
-- * Foam fix round 2 (2026-10-09): on the compact layout the "No music yet" / "No sound effects yet" notes stay hidden
--   (SettingsFormat.captionShown); on touch the body's scroll bar stays on screen while the rows are longer than it
--   (UI/Components/ScrollHint, "ScrollRail" on the panel).
-- * First person (spec 2026-10-10 §3.8): the switch "First-person duels" is FirstPersonController's session switch (on
--   at every join): it reads isEnabled() when built and on every open and calls only setEnabled; it is never saved,
--   never in the SetSettings patch (Validate.settings refuses an unknown key whole). The next duel uses it, and the
--   practice range as soon as Settings closes (a modal pauses first person).
-- UI FINAL R3 (the window frame, plan work/ui/PLAN.md R3; `H:n` = "Squishy Duels HUD.dc.html" line n): the panel is
-- the design's Settings window (Theme.window "settings", H:425-428: 600 wide, shrunk to fit with its sticker and X,
-- Layout.windowFit; its height follows its rows up to the design's 500) with its lilac small band (Theme.headerTab:
-- "SETTINGS" in the settingsTitle role, 92 high, H:428-429; the 150 px sticker, H:451) and the 76 px close X in the
-- band (Theme.attachClose, H:452); fitBody lays the chrome out at the window's chrome scale (Theme.fitWindow), counts
-- what hangs above in the chrome and places the window as the design does (Layout.windowShift). The body scrolls with
-- the design's scroll bar (Theme.scrollbar, H:22).
-- UI FINAL R9 (plan R9 "Settings": G9.6-G9.9, PR27, PR28; Config.UI.Sticker.settings; UI/SettingsFormat.ROWS):
-- * The body (H:431): padding 20 26 24, the rows 12 apart (each face; the 5 px lips inside the boxes). The scroll frame
--   reaches SIDE_ROOM into the side padding, so a row's hover (x +4) and press squash are not clipped and the scroll
--   bar sits there; the rows keep the design's width.
-- * The rows in the design's order (H:979, H:440), then the game's (PR28): Sound effects, Screen shake (the saved
--   cameraShake), Reduced motion (Q6: UiPrefs.reduceMotion for the session, never saved), Volume (the SFX volume),
--   Music (the Volume row's look, PR27), Show tips, First-person duels, Replay tutorial. A switch row is
--   UI/Components/Toggle's row (the purple face, Button's row feel, the 80 x 42 switch, its ui.click pair); a volume
--   row (H:440-447) is one line, the picture 50 | the label | the slider growing in its 44 px area | the value 48 wide,
--   with no hover or press of its own (only the slider reacts, its tick: Slider); Replay tutorial is the row with an
--   empty picture slot and the design's chip (H:402) on the cyan face (H:247) in the switch's place.
-- * Sound effects (PR27, H:891): no save key of its own: Off sets the SFX volume to 0 (the switch's off click plays
--   first), On sets back the last volume above 0 of this visit, else the default 70 (the volume first, then the on
--   click: Toggle's order); the Volume row follows, and dragging it to 0 turns the switch off.
-- * The no-sound notes are the design's well pill (H:391) under their row, only while needed.
-- Stable names: Settings_SoundToggle, Settings_CameraShakeToggle, Settings_ReducedMotionToggle, Settings_SfxSlider,
-- Settings_MusicSlider, Settings_ShowTipsToggle, Settings_FirstPersonToggle, Settings_ReplayTutorialButton,
-- Settings_CloseButton.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local Create = require(Client.UI.Create)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local Layout = require(Client.UI.Layout)
local ScrollHint = require(Client.UI.Components.ScrollHint)
local SettingsFormat = require(Client.UI.SettingsFormat)
local Slider = require(Client.UI.Components.Slider)
local Theme = require(Client.UI.Theme)
local Toggle = require(Client.UI.Components.Toggle)
local UiPrefs = require(Client.UI.UiPrefs)
local WellPill = require(Client.UI.Components.WellPill)
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
local WINDOW_KIND = "settings" -- UI FINAL R3: its Config.UI.Sticker.window kind (H:425-454)
local SCROLLBAR_PX = Theme.SCROLLBAR_PX -- UI FINAL R3: the design's 12 px bar (H:22)
local MAX_HEIGHT_SHARE = 0.86 -- reading: the panel never covers more than this share of the screen height
-- UI FINAL R9 (H:431-447): the body, the rows and the window's border and lip (Config.UI.Sticker).
local LOOK = Config.UI.Sticker.settings
local ROW = LOOK.row
local BODY = LOOK.bodyPad
local ROW_SURFACE = Config.UI.Sticker.surfaces.row
local WINDOW_BORDER = Config.UI.Sticker.border.heavy
local WINDOW_LIP = Config.UI.Sticker.lip.window
local NOTE_LOOK = Config.UI.Daily.timer -- H:391: the design's well pill (the no-sound notes)
local LABEL_ROLE = "settingsRow" -- H:442: 20 px white
local LABEL_KIND: Theme.TextKind = "Button"
local VALUE_ROLE = "settingsValue" -- H:447: 20 px white, stroke 4
local VALUE_KIND: Theme.TextKind = "Button"
local VALUE_SAMPLE = "100%" -- the widest value text (its box is at least LOOK.volume.value)
-- Reading: the scroll frame's reach into the side padding (the bar and the row hover's room) and its own pad above and
-- under the rows (a press squash's room), both taken from the design's padding so the rows keep their place.
local SIDE_ROOM = SCROLLBAR_PX + 4
local BODY_PAD_PX = 3
local MEASURE_MARGIN_PX = 2
local WHITE = Color3.new(1, 1, 1)
local MUSIC_GROUPS = { "Music" }
local SFX_GROUPS = { "SFX", "UI", "Ambient" }
local TOGGLE_NAMES: { [string]: string } = {
	sound = "Settings_SoundToggle",
	cameraShake = "Settings_CameraShakeToggle",
	reducedMotion = "Settings_ReducedMotionToggle",
	showTips = "Settings_ShowTipsToggle",
	firstPerson = "Settings_FirstPersonToggle",
}
local SLIDER_NAMES: { [string]: string } = { sfx = "Settings_SfxSlider", music = "Settings_MusicSlider" }
local NOTE_TEXTS: { [string]: string } = { sfx = Strings.settings.noSfx, music = Strings.settings.noMusic }

-- Module table

local SettingsController = {}

-- Private

type SliderRow = { slider: Slider.Slider, value: TextLabel, note: WellPill.WellPill }

local log = Log.new("Settings")
local cleanup: Cleanup.Cleanup? = nil
local edits: SettingsFormat.Edits = {}
local saveTimer: thread? = nil
local rows: { [string]: SliderRow } = {}
local toggles: { [string]: Toggle.Toggle } = {} -- the saved switches (cameraShake, showTips)
local soundToggle: Toggle.Toggle? = nil -- UI FINAL R9: Sound effects (the SFX volume above 0)
local reducedToggle: Toggle.Toggle? = nil -- UI FINAL R9: Reduced motion (UiPrefs, the session)
local firstPersonToggle: Toggle.Toggle? = nil -- the session switch: not in `toggles` (not a saved setting)
local replayRow: Frame? = nil
local closeButton: Button.Button? = nil
local panel: Frame? = nil
local bodyScroll: ScrollingFrame? = nil -- the rows' scrolling body (it opens at the top, onOpen)
local lastSfx: number? = nil -- UI FINAL R9 (PR27): the last SFX volume above 0 this visit (the switch turns it back on)

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
			row.value.Text = SettingsFormat.volumeText(value)
		end
	end
	for key, toggle in toggles do
		local value = (current :: any)[key]
		if type(value) == "boolean" then
			toggle:setValue(value)
		end
	end
	local sfx = (current :: any).sfx
	if SettingsFormat.soundOn(sfx) then
		lastSfx = sfx
	end
	if soundToggle then
		soundToggle:setValue(SettingsFormat.soundOn(sfx))
	end
	if reducedToggle then
		reducedToggle:setValue(UiPrefs.get("reduceMotion"))
	end
	if firstPersonToggle then
		firstPersonToggle:setValue(FirstPersonController.isEnabled())
	end
	if replayRow then
		replayRow.Visible = UIController.isRegistered(ONBOARDING_SCREEN)
	end
end

local function refreshCaptions()
	local music, sfx = rows.music, rows.sfx
	local class = UIController.layoutClass()
	if music then
		music.note.root.Visible = SettingsFormat.captionShown(class, SoundController.hasAnyIn(MUSIC_GROUPS))
	end
	if sfx then
		sfx.note.root.Visible = SettingsFormat.captionShown(class, SoundController.hasAnyIn(SFX_GROUPS))
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

-- UI FINAL R9 (H:440): a row's face without a feel (the volume and Replay rows): the purple row surface, its 5 px lip,
-- and the padded Content frame the parts sit in.
local function rowFace(name: string, order: number, parent: Instance): (Frame, Frame)
	local frame: Frame = Create("Frame", {
		Name = name,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, ROW.face + ROW.lip),
		LayoutOrder = order,
		Parent = parent,
	})
	local bands = Layout.stickerBands(ROW.border, ROW_SURFACE.highlightPx, 0, ROW.lip)
	Theme.foam(frame, {
		radius = ROW.radius,
		stroke = ROW.border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
		colors = {
			face = Palette.StickerCardTop,
			faceEnd = Palette.StickerCardBottom,
			top = Palette.StickerCardTop:Lerp(WHITE, ROW_SURFACE.highlightAlpha),
			drop = Theme.Colors.inkUI,
		},
	})
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -ROW.lip),
		Parent = frame,
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, ROW.border + ROW.padLeft),
		PaddingRight = UDim.new(0, ROW.border + ROW.padRight),
		PaddingTop = UDim.new(0, ROW.border),
		PaddingBottom = UDim.new(0, ROW.border),
		Parent = content,
	})
	return frame, content
end

-- The 50 px picture slot at a row's left (H:434, H:441); empty without a picture.
local function iconSlot(content: Frame, icon: string?)
	local slot: Frame = Create("Frame", {
		Name = "IconSlot",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(LOOK.icon, LOOK.icon),
		Parent = content,
	})
	if icon then
		IconGlyph.image(icon, { name = "Icon", sizePx = LOOK.icon, parent = slot })
	end
end

-- A row's label after the picture: one line in the settingsRow role, `width` wide (nil = its measured width).
local function rowLabel(content: Frame, text: string, width: number?): (TextLabel, number)
	local measured = math.ceil(Theme.textWidth(text, LABEL_KIND)) + MEASURE_MARGIN_PX
	local label = Theme.label({
		Name = "Label",
		Text = text,
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, LOOK.icon + ROW.gap, 0.5, 0),
		Size = if width
			then UDim2.new(1, -(LOOK.icon + ROW.gap + width), 0, math.ceil(Theme.lineHeight(LABEL_KIND)))
			else UDim2.fromOffset(measured, math.ceil(Theme.lineHeight(LABEL_KIND))),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = content,
	}, LABEL_KIND)
	Theme.stickerText(label, LABEL_ROLE)
	label.TextWrapped = false
	label.TextTruncate = Enum.TextTruncate.AtEnd
	return label, measured
end

-- UI FINAL R9 (H:440-447, PR27): the Volume row's look: the picture | the label | the slider (it grows, its 44 px area
-- in the touch-sized track) | the value (48 wide at least, right-aligned); the no-sound note (the well pill, H:391)
-- as its own line under it, hidden until needed.
local function sliderRow(c: Cleanup.Cleanup, parent: Instance, order: number, entry: SettingsFormat.Row)
	local key = entry.key :: string
	local _, content = rowFace(entry.id .. "Row", order, parent)
	iconSlot(content, entry.icon)
	local _, labelWidth = rowLabel(content, Strings.resolve(entry.text) or "")
	local valueWidth =
		math.max(LOOK.volume.value, math.ceil(Theme.textWidth(VALUE_SAMPLE, VALUE_KIND)) + MEASURE_MARGIN_PX)
	local value = Theme.label({
		Name = "Value",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(valueWidth, math.ceil(Theme.lineHeight(VALUE_KIND))),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = content,
	}, VALUE_KIND)
	Theme.stickerText(value, VALUE_ROLE)
	value.TextWrapped = false
	local current = (StateController.settings() :: any)[key]
	local slider = Slider.new({
		name = SLIDER_NAMES[key],
		min = DATA.settingsMin,
		max = DATA.settingsMax,
		step = SETTINGS.sliderStep,
		value = if type(current) == "number" then current else 0,
		parent = content,
		onChanged = function(newValue: number)
			value.Text = SettingsFormat.volumeText(newValue)
			change(key, SettingsFormat.volume(newValue))
			if key == "sfx" then
				if SettingsFormat.soundOn(newValue) then
					lastSfx = SettingsFormat.volume(newValue)
				end
				local switch = soundToggle
				if switch then
					switch:setValue(SettingsFormat.soundOn(newValue))
				end
			end
		end,
	})
	c:add(slider)
	local left = LOOK.icon + ROW.gap + labelWidth + ROW.gap
	slider.root.AnchorPoint = Vector2.new(0, 0.5)
	slider.root.Position = UDim2.new(0, left, 0.5, 0)
	slider.root.Size = UDim2.new(1, -(left + ROW.gap + valueWidth), 0, TOUCH.minTarget)
	value.Text = SettingsFormat.volumeText(slider:getValue())
	local note = WellPill.new({ name = entry.id .. "Note", look = NOTE_LOOK, layoutOrder = order + 1, parent = parent })
	note:setText(NOTE_TEXTS[key] or "")
	note.root.Visible = false
	c:add(note)
	rows[key] = { slider = slider, value = value, note = note }
end

-- A switch row (UI/Components/Toggle's row, H:433-438).
local function switchRow(
	c: Cleanup.Cleanup,
	parent: Instance,
	order: number,
	entry: SettingsFormat.Row,
	value: boolean,
	onChanged: (on: boolean) -> ()
): Toggle.Toggle
	local toggle = Toggle.new({
		name = TOGGLE_NAMES[entry.id],
		text = Strings.resolve(entry.text) or "",
		value = value,
		variant = "large", -- H:437: 80 x 42
		row = true,
		icon = entry.icon,
		layoutOrder = order,
		parent = parent,
		onChanged = onChanged,
	})
	c:add(toggle)
	return toggle
end

-- PR28: Replay tutorial: the row with an empty picture slot and the design's chip (H:402) on the cyan face (H:247).
local function replayRowOf(c: Cleanup.Cleanup, parent: Instance, order: number, entry: SettingsFormat.Row): Frame
	local frame, content = rowFace("ReplayTutorialRow", order, parent)
	iconSlot(content, nil)
	local replay = Button.new({
		name = "Settings_ReplayTutorialButton",
		text = Strings.quest.go,
		size = "chip",
		accent = "cyan",
		parent = content,
		onActivated = function()
			UIController.close(SCREEN, "replayTutorial")
			UIController.open(ONBOARDING_SCREEN, { replay = true })
		end,
	})
	replay.root.AnchorPoint = Vector2.new(1, 0.5)
	replay.root.Position = UDim2.fromScale(1, 0.5)
	c:add(replay)
	rowLabel(content, Strings.resolve(entry.text) or "")
	return frame
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local root = Theme.window({
		Name = "Settings",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(Layout.windowFit(gui.AbsoluteSize, WINDOW_KIND).width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, WINDOW_KIND, BODY.top - BODY_PAD_PX)
	c:add(root)
	-- UI FINAL R9 (H:431): the body's padding inside the window's border (fitWindow sets the top).
	local pad = root:FindFirstChildOfClass("UIPadding") :: UIPadding
	pad.PaddingLeft = UDim.new(0, WINDOW_BORDER + BODY.x)
	pad.PaddingRight = UDim.new(0, WINDOW_BORDER + BODY.x)
	pad.PaddingBottom = UDim.new(0, WINDOW_BORDER + BODY.bottom - BODY_PAD_PX + WINDOW_LIP)
	-- UI FINAL R3: the small band (H:428-429) on the window's top (it sets the top padding).
	Theme.headerTab(root, Strings.settings.title)
	-- The header tab sits on the panel itself, so the rows go in a Content frame.
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})

	local close = Button.new({
		name = "Settings_CloseButton",
		text = Strings.common.close,
		kind = "close", -- UI overhaul: the chunky red X
		parent = root,
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	Theme.attachClose(root, close.root) -- UI FINAL R3: the 76 px X in the band (H:452)
	close.root.Modal = true -- frees the cursor in shift lock / first person (§10.4 step 4)
	c:add(close)
	closeButton = close

	-- The rows scroll when the screen is too short for them; UI FINAL R9: SIDE_ROOM into the side padding.
	local body: ScrollingFrame = Theme.scrollbar(Create("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-SIDE_ROOM, 0),
		Size = UDim2.new(1, 2 * SIDE_ROOM, 0, 0),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	}))
	-- Top-aligned (fix batch): a centred list taller than the window was centred on the window, its top out of reach.
	local list = Theme.list(
		Enum.FillDirection.Vertical,
		Layout.lipGap(LOOK.rowGap, ROW.lip), -- H:431: 12 between the faces
		body,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Top
	)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, BODY_PAD_PX),
		PaddingBottom = UDim.new(0, BODY_PAD_PX),
		PaddingLeft = UDim.new(0, SIDE_ROOM),
		PaddingRight = UDim.new(0, SIDE_ROOM),
		Parent = body,
	})
	-- Fix round 2: on touch the body's scroll bar stays on screen while the rows are longer than it (UI/Components/
	-- ScrollHint), over the body's right edge; fitBody sizes it.
	local scrollHint = ScrollHint.new({ scroll = body, parent = root })
	scrollHint.root.AnchorPoint = Vector2.new(1, 0)
	scrollHint.root.Position = UDim2.new(1, SIDE_ROOM, 0, 0)
	c:add(scrollHint)
	-- The body's height from SettingsFormat.bodyHeight with the chrome measured, and the window placed as the design
	-- places it (UI FINAL R3).
	local function fitBody()
		local scale = UIController.scale()
		local pop = root:FindFirstChild("SD_OpenScale")
		local s = scale * (if pop and pop:IsA("UIScale") then pop.Scale else 1)
		local screen = gui.AbsoluteSize
		if not (scale > 0) or not (s > 0) or screen.X <= 0 or screen.Y <= 0 then
			return
		end
		local fit = Layout.windowFit(screen, WINDOW_KIND) -- UI FINAL R3: the design's 600, shrunk to fit
		local size = UDim2.fromOffset(fit.width, 0)
		if root.Size ~= size then
			root.Size = size
		end
		-- UI FINAL R3: the band at the chrome scale; the sticker and the X hang above it (H:451-452).
		local above = Theme.fitWindow(root, fit.k).above
		local window = Layout.windowChrome(WINDOW_KIND) :: Layout.WindowChrome
		local shift =
			Layout.windowShift(screen.Y / scale, root.AbsoluteSize.Y / s, window.designShift, above, window.margin)
		local position = UDim2.new(0.5, 0, 0.5, shift)
		if root.Position ~= position then
			root.Position = position
		end
		-- UI FINAL R3: the face stays within its fitted design height (H:426, windowFit's height); the rest scrolls.
		-- bodyHeight keeps MAX_HEIGHT_SHARE of the height it is given, hence the division.
		local room = math.min(screen.Y / scale, (fit.height + window.lip + above) / MAX_HEIGHT_SHARE)
		local current = body.AbsoluteSize.Y / s
		local chrome = root.AbsoluteSize.Y / s - current + above
		local height = math.ceil(
			SettingsFormat.bodyHeight(
				room,
				list.AbsoluteContentSize.Y / s + 2 * BODY_PAD_PX,
				chrome,
				MAX_HEIGHT_SHARE,
				TOUCH.minTarget
			)
		)
		if math.abs(height - current) >= 1 then
			body.Size = UDim2.new(1, 2 * SIDE_ROOM, 0, height)
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

	-- UI FINAL R9: the rows in SettingsFormat.ROWS's order (H:979, H:440, PR27, PR28); a volume row's note takes the
	-- order after it.
	local current = StateController.settings() :: any
	for i, entry in SettingsFormat.ROWS do
		local index = 2 * i
		if entry.kind == "volume" then
			sliderRow(c, body, index, entry)
		elseif entry.kind == "action" then
			replayRow = replayRowOf(c, body, index, entry)
		elseif entry.id == "sound" then
			-- PR27, H:891: Off = the SFX volume 0, On = the last volume above 0 (Toggle plays the click around it).
			soundToggle = switchRow(c, body, index, entry, SettingsFormat.soundOn(current.sfx), function(on: boolean)
				local sfx = SettingsFormat.sfxFor(on, lastSfx)
				change("sfx", sfx)
				local volume = rows.sfx
				if volume then
					volume.slider:setValue(sfx)
					volume.value.Text = SettingsFormat.volumeText(sfx)
				end
			end)
		elseif entry.id == "reducedMotion" then
			-- Q6: a session switch (UiPrefs.reduceMotion; no save key, Validate.settings untouched).
			reducedToggle = switchRow(c, body, index, entry, UiPrefs.get("reduceMotion"), function(on: boolean)
				UiPrefs.set("reduceMotion", on)
			end)
		elseif entry.id == "firstPerson" then
			-- First person (spec 2026-10-10 §3.8): FirstPersonController's session switch, never a saved setting, so it
			-- stays out of `toggles`, `edits` and SetSettings.
			firstPersonToggle =
				switchRow(c, body, index, entry, FirstPersonController.isEnabled(), FirstPersonController.setEnabled)
		else
			local key = entry.key :: string
			toggles[key] = switchRow(c, body, index, entry, current[key] == true, function(on: boolean)
				change(key, on)
			end)
		end
	end
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
			-- Fix batch: the rows always open at the top (the first row first), however the list was left.
			local scroll = bodyScroll
			if scroll then
				scroll.CanvasPosition = Vector2.zero
			end
		end,
		primary = function(): GuiObject?
			local first = soundToggle -- UI FINAL R9: the first row (H:979)
			if first then
				return first.root
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
		soundToggle, reducedToggle, firstPersonToggle, replayRow, closeButton = nil, nil, nil, nil, nil
		panel, bodyScroll, lastSfx = nil, nil, nil
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
