--!strict
-- Slider (client only). DESIGN §11.1 (UI/Components: Slider), §11.6 (Settings: "Sliders support drag, tap and DPad
-- left/right in steps of 5"), §11.4 (gamepad focus), §11.2 (touch targets).
--   local slider = Slider.new({ name = "Settings_MusicSlider", min = 0, max = 100, step = 5, value = 40,
--       onChanged = function(value, final) ... end, parent = row })
--   slider:setValue(70)    -- no callback
-- * Mouse / touch: press anywhere on the track to jump there (tap), keep holding to drag; the value follows the
--   pointer in whole numbers. onChanged(value, false) while dragging, onChanged(value, true) on release.
-- * Gamepad: the track is selectable; while it is the selected object, DPad left / right (and the left stick pushed
--   sideways, reading) move by `step`, and the selection does not leave it sideways (NextSelectionLeft/Right = itself).
--   onChanged(value, true) per step.
-- * The track is at least Config.UI.Touch.minTarget tall (an invisible hit area around the thin bar).
-- The value maths (valueAt, fractionOf, stepped) is pure and unit-tested in Edit mode.
-- Foam UI (spec 2026-10-09): the bar is a Biscuit track with the InkUI 2 px outline of bars, the fill the Mint accent
-- with its bevel shade, the knob a Frosting foam disc (outline, bevel, drop). Behaviour unchanged.
-- UI FINAL R1 (H:444-446, the Volume row): the track 20 base px tall with its 3 px ink border (drawn outside a 14 px
-- bar, so it shows the design's 20), StickerTrough; the fill the pink volume gradient under a 3 px highlight at .5; the
-- knob a 36 px white disc with a 4 px ink border inside it, the 3 px ink lip under it and a 3 px bevel at .12.
-- UI FINAL R9 (G9.7, H:898, lib:191): a value change by drag, tap or DPad ticks ui.hover at Config.Audio.uiPitch
-- slideFrom + slideSpan x the knob's share whenever the share moved more than slideStepShare since the last tick (the
-- first change always ticks), through Button.playSound; Slider.tickPitch(last, share) is that rule (pure).

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Log = require(Shared.Util.Log)

local UI = script.Parent.Parent
local Button = require(script.Parent.Button)
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local Layout = require(UI.Layout)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	min: number,
	max: number,
	step: number,
	value: number,
	widthPx: number?, -- nil = fill the parent's width
	onChanged: (value: number, final: boolean) -> (),
	layoutOrder: number?,
	parent: Instance?,
}

export type Slider = {
	root: Frame,
	track: TextButton,
	setValue: (self: Slider, value: number) -> (),
	getValue: (self: Slider) -> number,
	setEnabled: (self: Slider, enabled: boolean) -> (),
	destroy: (self: Slider) -> (),
}

-- Constants

local TOUCH = Config.UI.Touch
local STICKER = Config.UI.Sticker
local VOLUME = STICKER.bars.volume -- H:444
local BAR_BORDER_PX = VOLUME.border
local BAR_HEIGHT_PX = 20 - 2 * BAR_BORDER_PX -- H:444: 20 with the border, drawn outside the bar
local KNOB_PX = 36 -- H:445
local KNOB_BORDER_PX = STICKER.border.normal -- H:445
local KNOB_LIP_PX = STICKER.lip.bar -- H:445: box-shadow 0 3px 0
local KNOB_BEVEL_PX = 3 -- H:445: inset 0 -3px 0 rgba(0,0,0,.12)
local KNOB_BEVEL_ALPHA = 0.12
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local STICK_THRESHOLD = 0.6 -- reading: a sideways stick push counts as one DPad step
local DISABLED_TRANSPARENCY = 0.5
local UI_PITCH = Config.Audio.uiPitch -- UI FINAL R9: the tick (H:898, lib:191)
local SOUND_TICK = "ui.hover"

-- Module table

local Slider = {}

-- Private

local log = Log.new("Slider")

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

-- Public: pure maths -------------------------------------------------------------------------------------------------

-- The whole-number value at `fraction` (0..1, clamped) of the range.
function Slider.valueAt(fraction: number, min: number, max: number): number
	local f = if finite(fraction) then math.clamp(fraction, 0, 1) else 0
	return math.clamp(math.floor(min + (max - min) * f + 0.5), min, max)
end

-- Where `value` sits in the range (0..1).
function Slider.fractionOf(value: number, min: number, max: number): number
	if not finite(value) or max <= min then
		return 0
	end
	return math.clamp((value - min) / (max - min), 0, 1)
end

-- One step in `direction` (-1 / +1): snaps to the step grid first, so 42 + 5 = 45 and 42 - 5 = 40.
function Slider.stepped(value: number, direction: number, step: number, min: number, max: number): number
	local s = if finite(step) and step > 0 then step else 1
	local v = if finite(value) then value else min
	local result: number
	if direction > 0 then
		result = (math.floor((v - min) / s + 1e-9) + 1) * s + min
	else
		result = (math.ceil((v - min) / s - 1e-9) - 1) * s + min
	end
	return math.clamp(result, min, max)
end

-- UI FINAL R9 (H:898): the tick's pitch when the knob's share `share` (0..1) is more than slideStepShare away from the
-- share of the last tick (`last`; nil = none yet), else nil.
function Slider.tickPitch(last: number?, share: number): number?
	if not finite(share) then
		return nil
	end
	if last ~= nil and math.abs(share - last) <= UI_PITCH.slideStepShare then
		return nil
	end
	return UI_PITCH.slideFrom + UI_PITCH.slideSpan * math.clamp(share, 0, 1)
end

-- Public -------------------------------------------------------------------------------------------------------------

function Slider.new(spec: Spec): Slider
	local cleanup = Cleanup.new()
	local min, max, step = spec.min, spec.max, spec.step
	local value = math.clamp(spec.value, min, max)
	local enabled = true
	local dragging: InputObject? = nil

	local root: Frame = Create("Frame", {
		Name = spec.name,
		BackgroundTransparency = 1,
		Size = if spec.widthPx
			then UDim2.fromOffset(spec.widthPx, TOUCH.minTarget)
			else UDim2.new(1, 0, 0, TOUCH.minTarget),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	local track: TextButton = Create("TextButton", {
		Name = "Track",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	Focus.decorate(track)
	track.NextSelectionLeft = track
	track.NextSelectionRight = track
	local bar: Frame = Create("Frame", {
		Name = "Bar",
		BackgroundColor3 = Theme.Colors.track, -- H:444: the trough
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT_PX),
		Active = false,
		Parent = track,
	})
	Theme.corner(BAR_HEIGHT_PX, bar)
	Theme.stroke(Theme.Colors.inkUI, BAR_BORDER_PX, bar)
	local fill: Frame = Create("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Active = false,
		Parent = bar,
	})
	Theme.foam(fill, {
		radius = BAR_HEIGHT_PX,
		stroke = 0,
		top = VOLUME.fillHighlightPx,
		colors = {
			face = Palette.StickerVolumeTop,
			faceEnd = Palette.StickerVolumeEnd,
			top = Palette.StickerVolumeTop:Lerp(WHITE, VOLUME.fillHighlightAlpha),
		},
	})
	-- The knob's lip is inside its box under the disc, so the box is KNOB_LIP_PX taller and sits that much lower.
	local knob: Frame = Create("Frame", {
		Name = "Knob",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, KNOB_LIP_PX / 2),
		Size = UDim2.fromOffset(KNOB_PX, KNOB_PX + KNOB_LIP_PX),
		Active = false,
		ZIndex = 2,
		Parent = track,
	})
	local knobBands = Layout.stickerBands(KNOB_BORDER_PX, 0, KNOB_BEVEL_PX, KNOB_LIP_PX)
	Theme.foam(knob, {
		radius = KNOB_PX / 2,
		stroke = KNOB_BORDER_PX,
		inner = true,
		top = knobBands.top,
		bevel = knobBands.bevel,
		drop = knobBands.drop,
		colors = { face = WHITE, bevel = WHITE:Lerp(BLACK, KNOB_BEVEL_ALPHA), drop = Theme.Colors.inkUI },
	})

	local function paint()
		local f = Slider.fractionOf(value, min, max)
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.new(f, 0, 0.5, KNOB_LIP_PX / 2)
		local transparency = if enabled then 0 else DISABLED_TRANSPARENCY
		fill.BackgroundTransparency = transparency
		knob.BackgroundTransparency = transparency
	end

	local tickedAt: number? = nil -- the share of the last tick (UI FINAL R9)
	local function tick()
		local share = Slider.fractionOf(value, min, max)
		local pitch = Slider.tickPitch(tickedAt, share)
		if pitch then
			tickedAt = share
			Button.playSound(SOUND_TICK, pitch)
		end
	end

	local function notify(final: boolean)
		local ok, err = pcall(function(): any
			spec.onChanged(value, final)
			return nil
		end)
		if not ok then
			log:error(`{spec.name} onChanged failed:`, err)
		end
	end

	local function setFromX(x: number, final: boolean)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local newValue = Slider.valueAt((x - track.AbsolutePosition.X) / width, min, max)
		if newValue ~= value or final then
			local moved = newValue ~= value
			value = newValue
			paint()
			if moved then
				tick()
			end
			notify(final)
		end
	end

	local function stepBy(direction: number)
		if not enabled then
			return
		end
		local newValue = Slider.stepped(value, direction, step, min, max)
		if newValue ~= value then
			value = newValue
			paint()
			tick()
			notify(true)
		end
	end

	cleanup:add(track.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if not enabled or (kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch) then
			return
		end
		dragging = input
		setFromX(input.Position.X, false)
	end))
	cleanup:add(UserInputService.InputChanged:Connect(function(input: InputObject)
		local current = dragging
		if current == nil then
			return
		end
		local kind = input.UserInputType
		if
			(kind == Enum.UserInputType.MouseMovement and current.UserInputType == Enum.UserInputType.MouseButton1)
			or (kind == Enum.UserInputType.Touch and input == current)
		then
			setFromX(input.Position.X, false)
		end
	end))
	cleanup:add(UserInputService.InputEnded:Connect(function(input: InputObject)
		local current = dragging
		if current == nil then
			return
		end
		if input == current or input.UserInputType == current.UserInputType then
			dragging = nil
			setFromX(input.Position.X, true)
		end
	end))
	local stickPushed = false
	cleanup:add(UserInputService.InputBegan:Connect(function(input: InputObject)
		if GuiService.SelectedObject ~= track then
			return
		end
		if input.KeyCode == Enum.KeyCode.DPadLeft then
			stepBy(-1)
		elseif input.KeyCode == Enum.KeyCode.DPadRight then
			stepBy(1)
		end
	end))
	cleanup:add(UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.KeyCode ~= Enum.KeyCode.Thumbstick1 or GuiService.SelectedObject ~= track then
			return
		end
		local x = input.Position.X
		if math.abs(x) >= STICK_THRESHOLD then
			if not stickPushed then
				stickPushed = true
				stepBy(if x > 0 then 1 else -1)
			end
		else
			stickPushed = false
		end
	end))

	paint()
	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: Slider
	self.root = root
	self.track = track
	function self.setValue(_: Slider, newValue: number)
		if finite(newValue) then
			value = math.clamp(math.floor(newValue + 0.5), min, max)
			paint()
		end
	end
	function self.getValue(_: Slider): number
		return value
	end
	function self.setEnabled(_: Slider, on: boolean)
		enabled = on
		if not on then
			dragging = nil
		end
		paint()
	end
	function self.destroy(_: Slider)
		cleanup:clean()
	end
	return self
end

return Slider
