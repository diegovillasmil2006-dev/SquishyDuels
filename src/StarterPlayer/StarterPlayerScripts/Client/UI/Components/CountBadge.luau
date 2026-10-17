--!strict
-- CountBadge (client only). Foam UI restyle (spec 2026-10-09, "count badge"; DESIGN §11.6 notification badges): a small
-- foam pill with a number, on the corner of a tile or a button (the Daily tile's "1").
--   local badge = CountBadge.new({ name = "Badge", parent = tile })   -- the caller places root (AnchorPoint, Position)
--   badge:setCount(3)   -- "3"; 0 or nil hides it;   badge:setText("!")   -- any short text; nil or "" hides it
-- An accent face (default Strawberry) with the InkUI 2 px outline (bars and chips), at least sizePx wide and growing
-- with its text. The number is the Chip display kind; by the outlined-text rule it is InkUI on the accent (16 < 18 px).
-- CountBadge.text(n) is the shown text, pure: nil below 1, whole numbers capped at MAX (99, like HudFormat.badgeText).
-- Candy UI (UI overhaul 2026-10-11): the default face is Red (a notification), its number white with the PlumInk
-- outline (the Chip kind is outlined on an accent now), with a light inner rim.
-- UI FINAL R1 (H:102, H:120): a pill at least 32 base px, a 3 px ink border drawn inside it, the badge red gradient
-- with its inset highlight (2 px at .5), no rim, the number white in the badge role (18 px, the ink outline 1.5);
-- accent "yellow" is the daily "!" badge (its surface and role badgeMark: highlight 2 px at .6, 20 px). Padding 8
-- inside the border.
-- UI FINAL R8 (H:358): spec.small is the Quests tab's badge: 28 px, padding-top 3, no side padding, the 15 px (16,
-- PR2) count with a 3 px stroke (the tabBadge role); its size is measured from the text (no AutomaticSize, which
-- mis-sizes under a scaled ScreenGui), at least 28 square.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	sizePx: number?, -- the height and the minimum width (base px); default 32 (H:102)
	accent: Theme.AccentName?, -- default the badge red (H:102); "yellow" = the daily "!" (H:120)
	small: boolean?, -- UI FINAL R8: the Quests tab badge (H:358)
	layoutOrder: number?,
	parent: Instance?,
}

export type CountBadge = {
	root: Frame,
	label: TextLabel,
	setCount: (self: CountBadge, n: number?) -> (),
	setText: (self: CountBadge, text: string?) -> (),
	destroy: (self: CountBadge) -> (),
}

-- Constants

local STICKER = Config.UI.Sticker
local DEFAULT_SIZE_PX = 32 -- H:102
local SMALL_SIZE_PX = 28 -- H:358
local SMALL_PAD_TOP = 3 -- H:358
local MEASURE_MARGIN_PX = 2 -- reading: TextService rounding
local PADDING_X = 8 + STICKER.border.thin -- H:102: padding 0 8px inside the border
local MAX = 99
local Z_INDEX = 4 -- above the tile's content
-- The default face: the badge red of H:102 (its own pair; the "red" accent is the close X's).
local BADGE_RED: Theme.Accent = table.freeze({
	face = Palette.StickerRedTop,
	shade = Palette.StickerRedEnd,
	light = false,
	top = Palette.StickerRedTop,
})

-- Module table

local CountBadge = {}

CountBadge.MAX = MAX
CountBadge.SIZE_PX = DEFAULT_SIZE_PX

-- Public

-- The text of a count: nil below 1 (hidden), else the whole number capped at MAX.
function CountBadge.text(n: number?): string?
	if type(n) ~= "number" or not (n >= 1) then
		return nil
	end
	return tostring(math.min(math.floor(n), MAX))
end

function CountBadge.new(spec: Spec): CountBadge
	local cleanup = Cleanup.new()
	local small = spec.small == true
	local size = spec.sizePx or (if small then SMALL_SIZE_PX else DEFAULT_SIZE_PX)
	local accent = if spec.accent then Theme.accent(spec.accent) else BADGE_RED
	-- The size is the minimum: a larger text size grows the badge (AutomaticSize XY), so the number always fits.
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		AutomaticSize = if small then Enum.AutomaticSize.None else Enum.AutomaticSize.XY,
		Visible = false,
		ZIndex = Z_INDEX,
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	-- The badge's surface and text role: the daily "!" has its own highlight (H:120), the counts the badge's (H:102).
	local role = if spec.accent == "yellow" then "badgeMark" else "badge"
	local look = STICKER.surfaces[role]
	Theme.foam(root, {
		radius = Theme.Radius.pill,
		stroke = STICKER.border.thin,
		inner = true,
		top = STICKER.border.thin + (if small then 0 else look.highlightPx), -- H:358: no inset highlight
		colors = if small
			then { face = accent.top, faceEnd = accent.shade }
			else Theme.surfaceColors(accent, role, true),
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, if small then 0 else PADDING_X),
		PaddingRight = UDim.new(0, if small then 0 else PADDING_X),
		PaddingTop = UDim.new(0, if small then SMALL_PAD_TOP else 0),
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, 0, root)
	local label = Theme.label({
		Name = "Count",
		Text = "",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = Z_INDEX,
		Parent = root,
	}, "Chip")
	Theme.stickerText(label, role)
	label.TextWrapped = false -- Theme.text wraps; the badge grows with its number instead
	if small then
		label.AutomaticSize = Enum.AutomaticSize.None
		Theme.stickerText(label, "tabBadge")
	end

	local self = {} :: CountBadge
	self.root = root
	self.label = label

	function self.setText(_: CountBadge, text: string?)
		label.Text = text or ""
		root.Visible = text ~= nil and text ~= ""
		if small then
			local kind: Theme.TextKind = Theme.Sticker.text.tabBadge.kind :: Theme.TextKind
			local width = math.ceil(Theme.textWidth(label.Text, kind)) + MEASURE_MARGIN_PX
			label.Size = UDim2.fromOffset(width, math.ceil(Theme.lineHeight(kind)))
			root.Size = UDim2.fromOffset(math.max(size, width + 2 * STICKER.border.thin), size)
		end
	end

	function self.setCount(_: CountBadge, n: number?)
		self:setText(CountBadge.text(n))
	end

	function self.destroy(_: CountBadge)
		cleanup:clean()
	end

	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return CountBadge
