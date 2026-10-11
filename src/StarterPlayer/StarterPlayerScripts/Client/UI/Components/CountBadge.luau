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

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	sizePx: number?, -- the height and the minimum width (base px); default 26
	accent: Theme.AccentName?, -- default "red"
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

local DEFAULT_SIZE_PX = 26
local PADDING_X = 6
local MAX = 99
local Z_INDEX = 4 -- above the tile's content

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
	local size = spec.sizePx or DEFAULT_SIZE_PX
	local accent = Theme.accent(spec.accent or "red")
	-- The size is the minimum: a larger text size grows the badge (AutomaticSize XY), so the number always fits.
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		ZIndex = Z_INDEX,
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Theme.foam(root, {
		radius = Theme.Radius.pill,
		stroke = Theme.Stroke.bar,
		colors = { face = accent.face, bevel = accent.shade },
	})
	Theme.rim(root, Theme.Colors.white, 0.6, 1.5)
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, PADDING_X),
		PaddingRight = UDim.new(0, PADDING_X),
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
	if accent.light then
		Theme.textOnLight(label)
	else
		Theme.textOnColor(label, nil, accent.face)
	end

	local self = {} :: CountBadge
	self.root = root
	self.label = label

	function self.setText(_: CountBadge, text: string?)
		label.Text = text or ""
		root.Visible = text ~= nil and text ~= ""
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
