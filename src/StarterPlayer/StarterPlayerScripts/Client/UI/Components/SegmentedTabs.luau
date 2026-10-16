--!strict
-- SegmentedTabs (client only). UI FINAL R4 (plan work/tdmffa/PLAN.md R4Δ "Picker"; `N:n` = Diego's newer
-- "Squishy Duels TDMFFA animations and hud/Squishy Duels HUD.dc.html" line n): a row of tabs in a dark well, one
-- picked (the DUEL button's TEAM DEATHMATCH / FREE FOR ALL picker, N:154-158, N:1252-1256).
--   local picker = SegmentedTabs.new({ name = "Hud_DuelModes", tabs = { ... }, selected = "tdm",
--   	onSelect = function(id) ... end, parent = wrap })
--   picker:select("ffa");   picker:selected() -> "ffa";   picker.tabs.ffa (the tab's TextButton)
--   picker:size(short?, chips?)   picker:setShort(on, chips?)   (each tab's `short` name alone, no chip: the HUD's
--   narrow fit; with `chips` (2026-10-16, the owner's 1v1 tab makes three: [P] not in the design) the narrowest fit,
--   each tab's chip word alone in its name's place, e.g. "6v6", "SOLO", "1v1");   picker:destroy()
--   SegmentedTabs.gradientRotation(degrees, width, height)   pure: a screen angle as a UIGradient's Rotation
-- The well (N:154): #2A1D45, a 4 px ink border drawn inside, radius 20, the 3 px highlight at .08, the 5 px ink lip,
-- 5 px of padding round the tabs and 6 between them. Each tab (N:156-158) is a 52 px touch box (PR1) holding its 42 px
-- face: 3 px border, radius 14, padding 0 9 0 14, the label (16 px) and the chip (22 tall, radius 8, padding 0 7, its
-- 12 px text at the 16 px floor, PR2) 8 apart. The picked tab (N:1255-1256): its mode gradient (Tab.stops at
-- Tab.rotation degrees on the screen: CSS linear-gradient(a deg) = a - 90; a UIGradient rotates in its frame's own
-- 0..1 space, so the face's Rotation is that angle turned for the face's size, gradientRotation), the ink border, the
-- 3 px highlight at .5 and the 3 px ink lip, white text with the 4 px stroke (Sticker text role "small"), the chip ink
-- with white text; the others clear, their text and chip text #B9AEDA (no outline: 7.4:1 on the well), the chip white
-- at .92.
-- Hover and press: Button.decorate's "tab" feel (H:785: scale 1.05 and the hover sound at 1.3; the decorated feel
-- draws the scale, not the 2 px lift: Button.decorate is a UIScale only); a press on another tab picks it and calls
-- onSelect(id) (the caller plays the design's tab() sound, N:1254); picking the picked one does nothing. Gamepad: every
-- tab is selectable with the Focus ring.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent.Parent
local Button = require(script.Parent.Button)
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local Layout = require(UI.Layout)
local Theme = require(UI.Theme)

-- Types

-- One tab: its id, its label and chip texts, and its picked face (gradient stops at shares 0..1, turned `rotation`).
export type Stop = { at: number, color: Color3 }
export type Tab = { id: string, label: string, chip: string, short: string?, stops: { Stop }, rotation: number }

export type Spec = {
	name: string,
	tabs: { Tab },
	selected: string?, -- default the first tab
	onSelect: (id: string) -> (),
	layoutOrder: number?,
	parent: Instance?,
}

export type SegmentedTabs = {
	root: Frame,
	tabs: { [string]: TextButton },
	order: { string }, -- the tab ids left to right
	select: (self: SegmentedTabs, id: string) -> (),
	selected: (self: SegmentedTabs) -> string,
	-- base px, from its tabs (the HUD places the DUEL area); `chips` (with `short`) the chip words alone
	size: (self: SegmentedTabs, short: boolean?, chips: boolean?) -> Vector2,
	setShort: (self: SegmentedTabs, on: boolean, chips: boolean?) -> (),
	destroy: (self: SegmentedTabs) -> (),
}

type Parts = {
	face: Frame,
	lip: Frame,
	gloss: Frame,
	gradient: UIGradient,
	stroke: UIStroke,
	label: TextLabel,
	chip: Frame,
	chipText: TextLabel,
	full: number, -- the tab's width with its name and chip, with its short name alone, and with its chip word alone
	short: number,
	chips: number,
	chipWidth: number,
}

-- Constants

local STICKER = Config.UI.Sticker
local PICKER = STICKER.hud.picker
local HIT = Config.UI.Touch.minTarget -- PR1: the tab's touch box
local WHITE = Palette.White
local OFF_TEXT = Palette.StickerTrackerStatus -- N:1256 #B9AEDA

-- Module table

local SegmentedTabs = {}

-- Private

local log = Log.new("SegmentedTabs")

-- A ColorSequence of a tab's stops (at least two; a single stop is a flat colour).
local function sequenceOf(stops: { Stop }): ColorSequence
	if #stops == 0 then
		return ColorSequence.new(WHITE)
	elseif #stops == 1 then
		return ColorSequence.new(stops[1].color)
	end
	local keys: { ColorSequenceKeypoint } = {}
	for _, stop in stops do
		table.insert(keys, ColorSequenceKeypoint.new(math.clamp(stop.at, 0, 1), stop.color))
	end
	return ColorSequence.new(keys)
end

-- Turns a label's ink outline off (the off tab's text and chip: the design draws none, N:1256).
local function bare(label: TextLabel)
	local outline = label:FindFirstChild("SD_Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Enabled = false
	end
end

-- Public

-- A UIGradient Rotation (degrees) that draws a gradient at `degrees` on the screen across a frame `width` x `height`:
-- the engine turns the gradient in the frame's own 0..1 space, so its isolines lean atan(tan(r) * w / h) on screen; the
-- inverse is atan2(h sin(a), w cos(a)) (a flat frame turns it less; 0 and 90 stay). Bad sizes: `degrees` as it is.
function SegmentedTabs.gradientRotation(degrees: number, width: number, height: number): number
	if not (width > 0 and height > 0 and width < math.huge and height < math.huge) then
		return degrees
	end
	local a = math.rad(degrees)
	return math.deg(math.atan2(height * math.sin(a), width * math.cos(a)))
end

function SegmentedTabs.new(spec: Spec): SegmentedTabs
	local cleanup = Cleanup.new()
	local border, padding = PICKER.border, PICKER.padding
	local bands = Layout.stickerBands(border, PICKER.highlightPx, 0, PICKER.lip)
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, bands.top - PICKER.highlightPx + HIT + bands.drop),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Theme.foam(root, {
		radius = PICKER.radius,
		stroke = border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
		colors = {
			face = Palette.StickerPickerWell,
			top = Palette.StickerPickerWell:Lerp(WHITE, PICKER.highlightAlpha),
			drop = Theme.Colors.inkUI,
		},
	})
	-- The 52 px tab boxes fill the well between its border and its lip; their 42 px faces sit `padding` inside.
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, border + padding),
		PaddingRight = UDim.new(0, border + padding),
		PaddingTop = UDim.new(0, border),
		PaddingBottom = UDim.new(0, bands.drop),
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, PICKER.tabGap, root, Enum.HorizontalAlignment.Left)

	local parts: { [string]: Parts } = {}
	local tabs: { [string]: TextButton } = {}
	local order: { string } = {}
	local current = spec.selected or (spec.tabs[1] and spec.tabs[1].id) or ""

	local function paint(id: string)
		local p = parts[id]
		if p == nil then
			return
		end
		local on = id == current
		p.face.BackgroundTransparency = if on then 0 else 1
		p.gradient.Enabled = on
		p.stroke.Transparency = if on then 0 else 1
		p.lip.Visible = on
		p.gloss.Visible = on
		if on then
			Theme.stickerText(p.label, "small") -- N:1256: white, 4px #1E1428
			Theme.text(p.chipText, "Chip")
		else
			Theme.text(p.label, "Small", nil, OFF_TEXT)
			bare(p.label)
			Theme.text(p.chipText, "Chip", nil, OFF_TEXT)
			bare(p.chipText)
		end
		p.label.TextWrapped = false
		p.chipText.TextWrapped = false
		p.chip.BackgroundColor3 = if on then Theme.Colors.inkUI else WHITE
		p.chip.BackgroundTransparency = if on then 0 else 1 - PICKER.offChipAlpha
	end

	-- A tab's widths from its texts at the player's text size (Theme.textWidth; the picker's texts never change):
	-- the border, the paddings, the label, the gap and the chip (its text and padding); short = the short name alone;
	-- chips = the chip's word alone in the label's place (2026-10-16).
	local function widths(label: string, chipText: string, shortLabel: string): (number, number, number, number)
		local frame = 2 * PICKER.tabBorder + PICKER.tabPadLeft + PICKER.tabPadRight
		local chip = math.ceil(Theme.textWidth(chipText, "Chip")) + 2 * PICKER.chipPad
		local full = frame + math.ceil(Theme.textWidth(label, "Small")) + PICKER.tabGapInside + chip
		local short = frame + math.ceil(Theme.textWidth(shortLabel, "Small"))
		return full, short, chip, frame + math.ceil(Theme.textWidth(chipText, "Small"))
	end
	local isShort, isChips = false, false
	-- A tab at its width (the full, the short or the chips one): its hit box and its gradient's turn for that face.
	local function fit(tab: Tab, p: Parts)
		local width = if isChips then p.chips elseif isShort then p.short else p.full
		tabs[tab.id].Size = UDim2.fromOffset(width, HIT)
		p.label.Text = if isChips then tab.chip elseif isShort then tab.short or tab.label else tab.label
		p.chip.Visible = not isShort
		p.gradient.Rotation = SegmentedTabs.gradientRotation(tab.rotation, width, PICKER.tabHeight)
	end

	for index, tab in spec.tabs do
		local faceHeight = PICKER.tabHeight
		local faceTop = math.floor((HIT - faceHeight) / 2)
		local hit: TextButton = Create("TextButton", {
			Name = "Tab_" .. tab.id,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(0, HIT),
			LayoutOrder = index,
			Parent = root,
		})
		Focus.decorate(hit, PICKER.tabRadius)
		cleanup:add(Button.decorate(hit, { fx = "tab", clickSound = false }))
		-- The lip (N:1255: 0 3px 0 #1E1428): the ink shape 3 px taller behind the face.
		local lip: Frame = Create("Frame", {
			Name = "Lip",
			BackgroundColor3 = Theme.Colors.inkUI,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, faceTop),
			Size = UDim2.new(1, 0, 0, faceHeight + PICKER.tabLip),
			Visible = false,
			ZIndex = 0,
			Parent = hit,
		})
		Theme.corner(PICKER.tabRadius, lip)
		local face: Frame = Create("Frame", {
			Name = "Face",
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, faceTop),
			Size = UDim2.new(1, 0, 0, faceHeight),
			ZIndex = 1,
			Parent = hit,
		})
		Theme.corner(PICKER.tabRadius, face)
		local stroke = Theme.stroke(Theme.Colors.inkUI, PICKER.tabBorder, face, 1)
		pcall(function()
			(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner -- the CSS border-box
		end)
		local gradient: UIGradient = Create("UIGradient", {
			Color = sequenceOf(tab.stops),
			Rotation = tab.rotation, -- fit turns it for the face's size
			Enabled = false,
			Parent = face,
		})
		-- N:1255: inset 0 3px 0 rgba(255,255,255,.5) under the border, following the rounded corners.
		local top = PICKER.tabBorder / faceHeight
		local bottom = (PICKER.tabBorder + PICKER.tabHighlightPx) / faceHeight
		local gloss: Frame = Create("Frame", {
			Name = "Gloss",
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1 - PICKER.tabHighlightAlpha,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			ZIndex = 1,
			Parent = face,
		})
		Theme.corner(PICKER.tabRadius, gloss)
		Create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(top, 1),
				NumberSequenceKeypoint.new(top + 0.001, 0),
				NumberSequenceKeypoint.new(bottom, 0),
				NumberSequenceKeypoint.new(bottom + 0.001, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = gloss,
		})
		local content: Frame = Create("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Parent = face,
		})
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, PICKER.tabBorder + PICKER.tabPadLeft),
			PaddingRight = UDim.new(0, PICKER.tabBorder + PICKER.tabPadRight),
			Parent = content,
		})
		Theme.list(Enum.FillDirection.Horizontal, PICKER.tabGapInside, content, Enum.HorizontalAlignment.Left)
		local label = Theme.label({
			Name = "Label",
			Text = tab.label,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			TextWrapped = false,
			LayoutOrder = 1,
			ZIndex = 2,
			Parent = content,
		}, "Small")
		local chip: Frame = Create("Frame", {
			Name = "Chip",
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(0, PICKER.chipHeight),
			LayoutOrder = 2,
			ZIndex = 2,
			Parent = content,
		})
		Theme.corner(PICKER.chipRadius, chip)
		local chipText = Theme.label({
			Name = "Text",
			Text = tab.chip,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			TextWrapped = false,
			ZIndex = 3,
			Parent = chip,
		}, "Chip")
		local full, short, chipWidth, chips = widths(tab.label, tab.chip, tab.short or tab.label)
		local made: Parts = {
			face = face,
			lip = lip,
			gloss = gloss,
			gradient = gradient,
			stroke = stroke,
			label = label,
			chip = chip,
			chipText = chipText,
			full = full,
			short = short,
			chips = chips,
			chipWidth = chipWidth,
		}
		parts[tab.id] = made
		tabs[tab.id] = hit
		table.insert(order, tab.id)
		chip.Size = UDim2.fromOffset(chipWidth, PICKER.chipHeight)
		fit(tab, made)
		cleanup:add(hit.Activated:Connect(function()
			if current == tab.id then
				return
			end
			current = tab.id
			for _, id in order do
				paint(id)
			end
			local ok, err = pcall(function(): any
				spec.onSelect(tab.id)
				return nil
			end)
			if not ok then
				log:error("onSelect failed:", err)
			end
		end))
	end
	for _, id in order do
		paint(id)
	end

	local self = {} :: SegmentedTabs
	self.root = root
	self.tabs = tabs
	self.order = order

	function self.select(_: SegmentedTabs, id: string)
		if parts[id] == nil or id == current then
			return
		end
		current = id
		for _, key in order do
			paint(key)
		end
	end

	function self.selected(_: SegmentedTabs): string
		return current
	end

	function self.size(_: SegmentedTabs, short: boolean?, chips: boolean?): Vector2
		local useShort = if short == nil then isShort else short
		local useChips = if short == nil then isChips else useShort and chips == true
		local width = 2 * (border + padding) + math.max(0, #order - 1) * PICKER.tabGap
		for _, id in order do
			local p = parts[id]
			width += if useChips then p.chips elseif useShort then p.short else p.full
		end
		return Vector2.new(width, root.Size.Y.Offset)
	end

	function self.setShort(_: SegmentedTabs, on: boolean, chips: boolean?)
		local onChips = on and chips == true
		if on == isShort and onChips == isChips then
			return
		end
		isShort, isChips = on, onChips
		for _, tab in spec.tabs do
			local p = parts[tab.id]
			if p then
				fit(tab, p)
			end
		end
	end

	function self.destroy(_: SegmentedTabs)
		cleanup:clean()
	end

	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return SegmentedTabs
