--!strict
-- RarityTag (client only). DESIGN §4.3 (rarity is never shown by colour alone: label text + pips + colour), §10.8 (rarity
-- row: pips, label, colour chip), §11.6 (cards and the equipped card).
--   local tag = RarityTag.new({ name = "Rarity", rarity = "Epic", parent = row })
--   tag:setRarity("Exclusive")
-- Pips are UI shapes (no font or image risk): circles for Common / Uncommon / Epic, diamonds (rotated squares) for
-- Exclusive, in the rarity colour with an Ink outline, as many as Art/RarityStyle says. The label ("EPIC", from the
-- rarity's Strings labelKey) sits on a chip in the rarity colour with the style's label text colour (contrast >= 4.5:1).
-- Foam UI (spec 2026-10-09): a pill chip with the InkUI 2 px outline of chips, the label in the Chip display kind, pips
-- outlined in InkUI 2 px; the rarity colours and label colours are unchanged (Art/RarityStyle).
-- Part 8 (the Squishies and Shop cards: "◆◆◆◆ EXCLUSIVE" was wider than a 112 px card):
--   spec.stacked = true / tag:setStacked(on)   the pips sit centred above the chip instead of beside it
--   RarityTag.measure(rarity, pipSizePx?, textKind?) -> { pipsWidth, chipWidth, chipHeight, inlineWidth,
--       inlineHeight, stackedWidth, stackedHeight }   base px at the player's text size (Theme.textBounds), for card
--       layouts
-- Foam fix batch (2026-10-09): the pips' and the chip's 2 px outlines are drawn outside their boxes, so the gaps count
-- both outlines (INLINE_GAP, STACKED_GAP: the pips never touch the chip) and the tag keeps OUTLINE_ROOM inside its own
-- box on every side (the outlines and the diamonds' corners never touch the name above or a neighbour); measure()
-- includes both, so the cards grow to match. A diamond is a rotated square whose diagonal fits its pip box.
-- Foam fix round 2 (2026-10-09): RarityTag.tallest(pipSizePx?, textKind?) -> the tallest side-by-side tag over every
-- rarity (the Squishies and Shop details keep that much under the name, so the tag is never cut on a phone).
-- UI FINAL R1 (H:209, H:271): the pill is at least 22 base px tall with a 3 px ink border (still drawn outside, so the
-- measured room above holds; the pips keep their 2 px outline), in the design's rarity colour (Art/RarityStyle
-- ui.pillText, else ui.base) with the label white, outlined, in capitals (the Strings labels already are); the pips in
-- the same colour. Reading: Common is the card footer's darker #6F7D8B (H:933) on every tag, where the design's detail
-- and odds pills use #8C9AA8 (H:228, H:271): white reads 4.2:1 on it against 2.9:1.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Rarity = require(Shared.Rarity)
local RarityStyle = require(Shared.Art.RarityStyle)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	rarity: string,
	pipSizePx: number?,
	textKind: Theme.TextKind?, -- default "Chip" (the display font, foam UI)
	stacked: boolean?, -- pips above the chip (default: beside it)
	layoutOrder: number?,
	parent: Instance?,
}

export type RarityTag = {
	root: Frame,
	setRarity: (self: RarityTag, rarity: string) -> (),
	setStacked: (self: RarityTag, stacked: boolean) -> (),
	destroy: (self: RarityTag) -> (),
}

export type Measure = {
	pipsWidth: number,
	chipWidth: number,
	chipHeight: number,
	inlineWidth: number, -- pips, gap, chip side by side
	inlineHeight: number, -- the taller of the pips and the chip
	stackedWidth: number, -- the wider of the pips and the chip
	stackedHeight: number, -- pips, gap, chip
}

-- Constants

local DEFAULT_PIP_PX = 10
local PIP_GAP_PX = 3
local DIAMOND_SCALE = 0.7 -- a square this size, rotated 45°, fits the pip box (its diagonal is 0.99 of the box)
local CHIP_PADDING_X = 9 -- H:209: padding 2px 9px 0
local CHIP_PADDING_Y = 2
local CHIP_MIN_HEIGHT = 22 -- H:209
-- The outlines, drawn outside their boxes: the chip's is the pill border of H:209; the pips keep the bar outline
-- (Theme.Stroke.bar, kept, not the design: its bare dots would melt into the purple card).
local CHIP_OUTLINE = Config.UI.Sticker.border.thin
local PIP_OUTLINE = Theme.Stroke.bar
local OUTLINE_ROOM = math.max(CHIP_OUTLINE, PIP_OUTLINE) -- kept free inside the tag's box on every side
local INLINE_GAP = Theme.Padding.small + PIP_OUTLINE + CHIP_OUTLINE -- between the pips and the chip (6 px of air)
local STACKED_GAP = 2 + PIP_OUTLINE + CHIP_OUTLINE -- between the pips and the chip, stacked (2 px of air)

-- Module table

local RarityTag = {}

-- Public

-- The sizes (base px, the player's text size) of a tag for `rarity`, both ways round. An unknown rarity measures 0.
function RarityTag.measure(rarity: string, pipSizePx: number?, textKind: Theme.TextKind?): Measure
	local pipSize = pipSizePx or DEFAULT_PIP_PX
	local style = RarityStyle.get(rarity)
	local info = Rarity.get(rarity)
	if style == nil or info == nil then
		return {
			pipsWidth = 0,
			chipWidth = 0,
			chipHeight = 0,
			inlineWidth = 0,
			inlineHeight = 0,
			stackedWidth = 0,
			stackedHeight = 0,
		}
	end
	local pips = style.pips
	local pipsWidth = if pips > 0 then pips * pipSize + (pips - 1) * PIP_GAP_PX else 0
	local label = string.upper(Strings.resolve(info.labelKey) or "")
	local bounds = Theme.textBounds(label, textKind or "Chip", Enum.FontWeight.Bold)
	local chipWidth = math.ceil(bounds.X) + 2 * CHIP_PADDING_X
	local chipHeight = math.max(CHIP_MIN_HEIGHT, math.ceil(bounds.Y) + 2 * CHIP_PADDING_Y)
	local room = 2 * OUTLINE_ROOM
	return {
		pipsWidth = pipsWidth,
		chipWidth = chipWidth,
		chipHeight = chipHeight,
		inlineWidth = pipsWidth + (if pipsWidth > 0 then INLINE_GAP else 0) + chipWidth + room,
		inlineHeight = math.max(if pipsWidth > 0 then pipSize else 0, chipHeight) + room,
		stackedWidth = math.max(pipsWidth, chipWidth) + room,
		stackedHeight = (if pipsWidth > 0 then pipSize + STACKED_GAP else 0) + chipHeight + room,
	}
end

-- UI FINAL R1: the pill and pips colour of a rarity (the design's, H:209: RarityStyle ui.pillText, else ui.base, else
-- the game's rarity colour); the ink for anything that is not a rarity.
function RarityTag.color(rarity: string): Color3
	local style = RarityStyle.get(rarity)
	if style == nil then
		return Theme.Colors.inkUI
	end
	return style.ui.pillText or style.ui.base or style.color
end

-- The tallest side-by-side tag (measure().inlineHeight) over every rarity, base px at the player's text size (fix round
-- 2: the room the Squishies and Shop details keep for the tag under the name, whatever squishy is selected).
function RarityTag.tallest(pipSizePx: number?, textKind: Theme.TextKind?): number
	local tallest = 0
	for _, rarity in Rarity.ORDER do
		tallest = math.max(tallest, RarityTag.measure(rarity, pipSizePx, textKind).inlineHeight)
	end
	return tallest
end

function RarityTag.new(spec: Spec): RarityTag
	local cleanup = Cleanup.new()
	local pipSize = spec.pipSizePx or DEFAULT_PIP_PX
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Theme.padding(OUTLINE_ROOM, root) -- the outlines stay inside the tag's box (measure counts it)
	local list = Theme.list(Enum.FillDirection.Horizontal, INLINE_GAP, root, Enum.HorizontalAlignment.Left)
	local function applyStacked(stacked: boolean)
		list.FillDirection = if stacked then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal
		list.HorizontalAlignment = if stacked then Enum.HorizontalAlignment.Center else Enum.HorizontalAlignment.Left
		list.Padding = UDim.new(0, if stacked then STACKED_GAP else INLINE_GAP)
	end
	applyStacked(spec.stacked == true)

	local pips: Frame = Create("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, pipSize),
		LayoutOrder = 1,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, PIP_GAP_PX, pips)

	local chip: Frame = Create("Frame", {
		Name = "Chip",
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, CHIP_MIN_HEIGHT),
		LayoutOrder = 2,
		Parent = root,
	})
	Theme.corner(Theme.Radius.pill, chip)
	Theme.stroke(Theme.Colors.inkUI, CHIP_OUTLINE, chip)
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, CHIP_PADDING_X),
		PaddingRight = UDim.new(0, CHIP_PADDING_X),
		PaddingTop = UDim.new(0, CHIP_PADDING_Y),
		PaddingBottom = UDim.new(0, CHIP_PADDING_Y),
		Parent = chip,
	})
	local label = Theme.label({
		Name = "Label",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = chip,
	}, spec.textKind or "Chip", Enum.FontWeight.Bold)

	local function build(rarity: string)
		for _, child in pips:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local style = RarityStyle.get(rarity)
		local info = Rarity.get(rarity)
		if style == nil or info == nil then
			chip.Visible = false
			return
		end
		chip.Visible = true
		local color = RarityTag.color(rarity)
		chip.BackgroundColor3 = color
		label.Text = string.upper(Strings.resolve(info.labelKey) or "")
		Theme.textOnColor(label, nil, color)
		for i = 1, style.pips do
			local holder: Frame = Create("Frame", {
				Name = "Pip" .. i,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(pipSize, pipSize),
				LayoutOrder = i,
				Parent = pips,
			})
			local shape: Frame = Create("Frame", {
				Name = "Shape",
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = if style.pipShape == "diamond"
					then UDim2.fromScale(DIAMOND_SCALE, DIAMOND_SCALE)
					else UDim2.fromScale(1, 1),
				Rotation = if style.pipShape == "diamond" then 45 else 0,
				Parent = holder,
			})
			if style.pipShape ~= "diamond" then
				Theme.corner(pipSize, shape)
			end
			Theme.stroke(Theme.Colors.inkUI, PIP_OUTLINE, shape)
		end
	end

	build(spec.rarity)
	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: RarityTag
	self.root = root
	function self.setRarity(_: RarityTag, rarity: string)
		build(rarity)
	end
	function self.setStacked(_: RarityTag, stacked: boolean)
		applyStacked(stacked == true)
	end
	function self.destroy(_: RarityTag)
		cleanup:clean()
	end
	return self
end

return RarityTag
