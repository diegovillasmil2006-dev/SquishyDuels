--!strict
-- Chip (client only). Foam UI restyle (spec 2026-10-09, "chip (rarity / info)"): a small labelled pill, e.g.
-- "Equipped", "NEW", "Ultimate", "Starter", the "Upgrade ready" tab on the Grip card.
--   local chip = Chip.new({ name = "EquippedChip", text = Strings.common.equipped, parent = row })
--   chip:setText(text);   chip:setAccent("lilac");   chip:setColor(face, textColor?)   -- e.g. a rarity colour
-- A face (an accent, default Frosting, or any colour) with the InkUI 2 px outline of chips, radius Theme.Radius.chip,
-- the text in the Chip display kind (16 base px), an optional IconGlyph before it. spec.raised adds the chip foam bands
-- (bevel 3, drop 2: a tab that can be pressed, like the Upgrade tab); flat chips are labels. Text colour: InkUI on a
-- light face; on an accent the outlined-text rule (InkUI below 18 px); setColor(face, textColor) for a colour whose
-- text colour is known (RarityStyle.labelTextColor). Grows with its text (AutomaticSize XY), at least heightPx tall.
-- The chip is never the only sign of a state: it always carries its word.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local IconGlyph = require(script.Parent.IconGlyph)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	text: string,
	accent: Theme.AccentName?, -- default "frosting"
	textKind: Theme.TextKind?, -- default "Chip"
	icon: string?, -- an IconGlyph name, before the text
	heightPx: number?, -- the minimum height (base px); default 26
	raised: boolean?, -- the chip foam bands (a pressable tab)
	layoutOrder: number?,
	parent: Instance?,
}

export type Chip = {
	root: Frame,
	label: TextLabel,
	setText: (self: Chip, text: string) -> (),
	setAccent: (self: Chip, accent: Theme.AccentName) -> (),
	setColor: (self: Chip, face: Color3, textColor: Color3?) -> (),
	destroy: (self: Chip) -> (),
}

-- Constants

local DEFAULT_HEIGHT_PX = 26
local PADDING_X = 10
local GAP_PX = 4
local ICON_SHARE = 0.7 -- the icon, as a share of the chip's height
local SHADE_MIX = 0.15 -- setColor: the bevel shade of a raised chip, the face this far towards InkUI

-- Module table

local Chip = {}

Chip.HEIGHT_PX = DEFAULT_HEIGHT_PX

-- Public

function Chip.new(spec: Spec): Chip
	local cleanup = Cleanup.new()
	local height = spec.heightPx or DEFAULT_HEIGHT_PX
	local bands = if spec.raised then Theme.Foam.chip else { top = 0, bevel = 0, drop = 0 }
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, height),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	local foam = Theme.foam(root, {
		radius = Theme.Radius.chip,
		stroke = Theme.Stroke.bar,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.accentColors(spec.accent or "frosting"),
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, PADDING_X),
		PaddingRight = UDim.new(0, PADDING_X),
		PaddingBottom = UDim.new(0, bands.bevel + bands.drop),
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, GAP_PX, root)
	local icon: IconGlyph.IconGlyph? = nil
	if spec.icon then
		icon = IconGlyph.new({
			name = "Icon",
			icon = spec.icon,
			sizePx = math.floor(height * ICON_SHARE),
			layoutOrder = 1,
			parent = root,
		})
		cleanup:add(icon)
	end
	local label = Theme.label({
		Name = "Label",
		Text = spec.text,
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = root,
	}, spec.textKind or "Chip")

	local function paintText(light: boolean, textColor: Color3?)
		if textColor then
			Theme.textOnLight(label, textColor)
		elseif light then
			Theme.textOnLight(label)
		else
			Theme.textOnColor(label)
		end
		local glyph = icon
		if glyph then
			glyph:setTone(if light or textColor then "dark" else "light")
		end
	end

	local self = {} :: Chip
	self.root = root
	self.label = label

	function self.setText(_: Chip, text: string)
		label.Text = text
	end

	function self.setAccent(_: Chip, name: Theme.AccentName)
		foam:paint(Theme.accentColors(name))
		paintText(Theme.accent(name).light, nil)
	end

	function self.setColor(_: Chip, face: Color3, textColor: Color3?)
		foam:paint({ face = face, bevel = face:Lerp(Theme.Colors.inkUI, SHADE_MIX) })
		paintText(false, textColor)
	end

	function self.destroy(_: Chip)
		cleanup:clean()
	end

	paintText(Theme.accent(spec.accent or "frosting").light, nil)
	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return Chip
