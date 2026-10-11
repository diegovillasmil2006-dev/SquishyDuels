--!strict
-- Toggle (client only). DESIGN §11.1 (UI/Components: Toggle), §11.6 (Settings toggles, "Show not owned"), §11.4,
-- §11.2 (touch targets), §9.13 (never colour alone).
--   local toggle = Toggle.new({ name = "Settings_CameraShakeToggle", text = Strings.settings.cameraShake, value = true,
--       onChanged = function(on) ... end, parent = list })
--   toggle:setValue(false)   -- no callback
-- One button the full row wide (label left, switch right): a click, tap or ButtonA flips it. The state shows three
-- ways: the knob's side, the track colour and the state text (common.on / common.off).
-- Part 8: Toggle.widthFor(text) is the width (base px) a toggle needs to show `text` on one line at the player's text
-- size (Theme.textWidth + the state text and the switch), for a caller that sets widthPx (the Squishies filter row).
-- Foam UI (spec 2026-10-09): the switch is a Biscuit track (off) or the Mint accent (on) with the InkUI 2 px outline of
-- bars and chips; the knob is a Frosting foam disc with a small bevel. Sizes and behaviour unchanged.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	text: string,
	value: boolean,
	onChanged: (value: boolean) -> (),
	widthPx: number?, -- nil = fill the parent's width
	layoutOrder: number?,
	parent: Instance?,
}

export type Toggle = {
	root: TextButton,
	setValue: (self: Toggle, value: boolean) -> (),
	getValue: (self: Toggle) -> boolean,
	setText: (self: Toggle, text: string) -> (),
	destroy: (self: Toggle) -> (),
}

-- Constants

local TOUCH = Config.UI.Touch
local SWITCH_W = 52
local SWITCH_H = 28
local KNOB_INSET = 3
local STATE_WIDTH = 60
local ON_TEXT = Strings.common.on
local OFF_TEXT = Strings.common.off
local CHROME_PX = SWITCH_W + STATE_WIDTH + Theme.Padding.small * 2 -- everything beside the label
local MEASURE_MARGIN_PX = 4
local KNOB_BEVEL_PX = 2
local ON_FILL = Theme.Accents.mint.face
local OFF_FILL = Theme.Colors.biscuit

-- Module table

local Toggle = {}

-- Private

local log = Log.new("Toggle")

-- Public

-- The width (base px) a toggle needs for `text` on one line at the player's text size, with its state text and switch.
function Toggle.widthFor(text: string): number
	return math.ceil(Theme.textWidth(text, "Body")) + CHROME_PX + MEASURE_MARGIN_PX
end

function Toggle.new(spec: Spec): Toggle
	local cleanup = Cleanup.new()
	local value = spec.value == true
	local root: TextButton = Create("TextButton", {
		Name = spec.name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = if spec.widthPx
			then UDim2.fromOffset(spec.widthPx, TOUCH.minTarget)
			else UDim2.new(1, 0, 0, TOUCH.minTarget),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Focus.decorate(root)

	local label = Theme.label({
		Name = "Label",
		Text = spec.text,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, -CHROME_PX, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	}, "Body")
	local stateLabel = Theme.label({
		Name = "State",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(SWITCH_W + Theme.Padding.small), 0.5, 0),
		Size = UDim2.fromOffset(STATE_WIDTH, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	}, "Small", Enum.FontWeight.Bold)
	local switch: Frame = Create("Frame", {
		Name = "Switch",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(SWITCH_W, SWITCH_H),
		Active = false,
		Parent = root,
	})
	Theme.corner(SWITCH_H, switch)
	Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.bar, switch)
	local knobSize = SWITCH_H - KNOB_INSET * 2
	local knob: Frame = Create("Frame", {
		Name = "Knob",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(knobSize, knobSize),
		Active = false,
		Parent = switch,
	})
	Theme.foam(knob, {
		radius = knobSize,
		stroke = Theme.Stroke.bar,
		bevel = KNOB_BEVEL_PX,
		colors = { face = Theme.Colors.frosting, bevel = Theme.Colors.stickerBevel }, -- Candy UI: a light sticker knob
	})

	local function paint()
		switch.BackgroundColor3 = if value then ON_FILL else OFF_FILL
		knob.Position = if value
			then UDim2.new(1, -(knobSize + KNOB_INSET), 0.5, 0)
			else UDim2.new(0, KNOB_INSET, 0.5, 0)
		stateLabel.Text = if value then ON_TEXT else OFF_TEXT
	end

	cleanup:add(root.Activated:Connect(function()
		value = not value
		paint()
		local ok, err = pcall(function(): any
			spec.onChanged(value)
			return nil
		end)
		if not ok then
			log:error(`{spec.name} onChanged failed:`, err)
		end
	end))

	paint()
	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: Toggle
	self.root = root
	function self.setValue(_: Toggle, newValue: boolean)
		value = newValue == true
		paint()
	end
	function self.getValue(_: Toggle): boolean
		return value
	end
	function self.setText(_: Toggle, text: string)
		label.Text = text
	end
	function self.destroy(_: Toggle)
		cleanup:clean()
	end
	return self
end

return Toggle
