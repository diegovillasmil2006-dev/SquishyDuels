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

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Focus = require(UI.Focus)
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
local BAR_HEIGHT_PX = 12
local FILL_BEVEL_PX = 3
local KNOB_PX = 26
local KNOB_BEVEL_PX = 3
local KNOB_DROP_PX = 2
local STICK_THRESHOLD = 0.6 -- reading: a sideways stick push counts as one DPad step
local DISABLED_TRANSPARENCY = 0.5

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
		BackgroundColor3 = Theme.Colors.biscuit,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT_PX),
		Active = false,
		Parent = track,
	})
	Theme.corner(BAR_HEIGHT_PX, bar)
	Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.bar, bar)
	local fill: Frame = Create("Frame", {
		Name = "Fill",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Active = false,
		Parent = bar,
	})
	local accent = Theme.Accents.mint
	Theme.foam(fill, {
		radius = BAR_HEIGHT_PX,
		stroke = 0,
		bevel = FILL_BEVEL_PX,
		colors = { face = accent.face, bevel = accent.shade },
	})
	local knob: Frame = Create("Frame", {
		Name = "Knob",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(KNOB_PX, KNOB_PX),
		Active = false,
		ZIndex = 2,
		Parent = track,
	})
	Theme.foam(knob, {
		radius = KNOB_PX,
		bevel = KNOB_BEVEL_PX,
		drop = KNOB_DROP_PX,
		colors = { face = Theme.Colors.frosting, bevel = Theme.Colors.bevel, drop = Theme.Colors.inkUI },
	})

	local function paint()
		local f = Slider.fractionOf(value, min, max)
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		local transparency = if enabled then 0 else DISABLED_TRANSPARENCY
		fill.BackgroundTransparency = transparency
		knob.BackgroundTransparency = transparency
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
			value = newValue
			paint()
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
