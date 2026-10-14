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
-- UI FINAL R1 (H:197, H:437, H:980, H:1010): spec.variant "small" (56 × 32, the default; the Squishies switch) or
-- "large" (80 × 42, the Settings switches), Config.UI.Sticker.toggles: a 4 px ink border drawn inside the switch, the
-- on track StickerToggleOnTop -> StickerGreen2End, the off track StickerSwitchOff, the white knob at the design's
-- places inside the border (small: 20 px with its ink drop 2 px lower at .4; large: 28 px with a 3 px ink border and a
-- 3 px bevel at .12), the large track's inner shade (3 px at .25). The row stays one button the touch minimum tall.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local Layout = require(UI.Layout)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	text: string,
	value: boolean,
	onChanged: (value: boolean) -> (),
	widthPx: number?, -- nil = fill the parent's width
	variant: Variant?, -- default "small"
	layoutOrder: number?,
	parent: Instance?,
}

-- UI FINAL R1: the design's two switches (Config.UI.Sticker.toggles).
export type Variant = "small" | "large"

export type Toggle = {
	root: TextButton,
	setValue: (self: Toggle, value: boolean) -> (),
	getValue: (self: Toggle) -> boolean,
	setText: (self: Toggle, text: string) -> (),
	destroy: (self: Toggle) -> (),
}

-- Constants

local TOUCH = Config.UI.Touch
local TOGGLES = Config.UI.Sticker.toggles
local DEFAULT_VARIANT = "small"
local STATE_WIDTH = 60
local ON_TEXT = Strings.common.on
local OFF_TEXT = Strings.common.off
local MEASURE_MARGIN_PX = 4
local ON_TOP = Palette.StickerToggleOnTop -- H:980
local ON_END = Palette.StickerGreen2End
local OFF_FILL = Palette.StickerSwitchOff -- H:980
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

-- Everything beside the label (base px): the switch, the state text and their gaps.
local function chromePx(variant: string): number
	return (TOGGLES[variant] or TOGGLES[DEFAULT_VARIANT]).width + STATE_WIDTH + Theme.Padding.small * 2
end

-- Module table

local Toggle = {}

-- Private

local log = Log.new("Toggle")

-- Public

-- The width (base px) a toggle (default variant "small") needs for `text` on one line at the player's text size, with
-- its state text and switch.
function Toggle.widthFor(text: string, variant: Variant?): number
	return math.ceil(Theme.textWidth(text, "Body")) + chromePx(variant or DEFAULT_VARIANT) + MEASURE_MARGIN_PX
end

function Toggle.new(spec: Spec): Toggle
	local cleanup = Cleanup.new()
	local value = spec.value == true
	local variant: string = if spec.variant and TOGGLES[spec.variant] then spec.variant else DEFAULT_VARIANT
	local look = TOGGLES[variant]
	local chrome = chromePx(variant)
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
		Size = UDim2.new(1, -chrome, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	}, "Body")
	local stateLabel = Theme.label({
		Name = "State",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(look.width + Theme.Padding.small), 0.5, 0),
		Size = UDim2.fromOffset(STATE_WIDTH, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	}, "Small", Enum.FontWeight.Bold)
	local switch: Frame = Create("Frame", {
		Name = "Switch",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(look.width, look.height),
		Active = false,
		Parent = root,
	})
	-- The track: a "tint" surface (BackgroundColor3 is its top colour) with the border inside and the inner shade.
	local track = Theme.foam(switch, {
		radius = look.height,
		stroke = look.border,
		inner = true,
		mode = "tint",
		top = look.border + (look.trackShadePx or 0),
		colors = { face = OFF_FILL },
	})
	local knobSize = look.knob
	local knobBorder = look.knobBorder or 0
	local knob: Frame = Create("Frame", {
		Name = "Knob",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(knobSize, knobSize),
		Active = false,
		ZIndex = 2,
		Parent = switch,
	})
	local knobBands = Layout.stickerBands(knobBorder, 0, look.knobBevelPx or 0, 0)
	Theme.foam(knob, {
		radius = knobSize,
		stroke = knobBorder,
		inner = true,
		top = knobBands.top,
		bevel = knobBands.bevel,
		drop = knobBands.drop,
		colors = { face = WHITE, bevel = WHITE:Lerp(BLACK, look.knobBevelAlpha or 0), drop = Theme.Colors.inkUI },
	})
	-- H:197: the small knob's drop, the ink at knobDropAlpha a few px lower, behind it.
	local knobDrop: Frame? = nil
	if look.knobDropPx then
		local made: Frame = Create("Frame", {
			Name = "KnobDrop",
			BackgroundColor3 = Theme.Colors.inkUI,
			BackgroundTransparency = 1 - (look.knobDropAlpha or 0),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(knobSize, knobSize),
			Active = false,
			ZIndex = 1,
			Parent = switch,
		})
		Theme.corner(knobSize, made)
		knobDrop = made
	end

	local function paint()
		local face = if value then ON_TOP else OFF_FILL
		switch.BackgroundColor3 = face
		track:paint({
			face = face,
			faceEnd = if value then ON_END else nil,
			top = face:Lerp(BLACK, look.trackShadeAlpha or 0),
		})
		local x = look.border + (if value then look.knobOn else look.knobOff)
		local y = look.border + look.knobTop
		knob.Position = UDim2.fromOffset(x, y)
		local drop = knobDrop
		if drop then
			drop.Position = UDim2.fromOffset(x, y + (look.knobDropPx or 0))
		end
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
