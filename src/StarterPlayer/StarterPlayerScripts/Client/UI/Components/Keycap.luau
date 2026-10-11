--!strict
-- Keycap (client only). Foam UI restyle (spec 2026-10-09, "keycap (follows KeyText)"; DESIGN §11.4: button prompts are
-- text): a key prompt drawn as a small dark key, e.g. a duel meter's throw key.
--   local cap = Keycap.new({ name = "Keycap", key = "controls.key.inspectKeyboard", parent = row })
--   cap:setKey("controls.key.inspectGamepad");   cap:setText("Y");   cap:setText(nil)   -- hidden
-- The text comes from a Strings key through UI/KeyText (`key`), or is given as `text`; nil / "" hides the cap. The
-- caller picks the key for the active input and hides the cap on touch (§11.7). An InkUI face with a 2 px Ink2 band at
-- its bottom (the design's key drop), Frosting text in the Chip display kind (14.2:1), at least sizePx square, growing
-- with longer texts ("Backspace").

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local KeyText = require(UI.KeyText)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	key: string?, -- a Strings key, read through KeyText
	text: string?, -- or the text itself
	sizePx: number?, -- the height and the minimum width (base px); default 24
	layoutOrder: number?,
	parent: Instance?,
}

export type Keycap = {
	root: Frame,
	label: TextLabel,
	setKey: (self: Keycap, key: string?) -> (),
	setText: (self: Keycap, text: string?) -> (),
	destroy: (self: Keycap) -> (),
}

-- Constants

local DEFAULT_SIZE_PX = 24
local DROP_PX = 2
local PADDING_X = 5
local RADIUS_SHARE = 0.3 -- the corner, as a share of the size

-- Module table

local Keycap = {}

Keycap.SIZE_PX = DEFAULT_SIZE_PX

-- Public

function Keycap.new(spec: Spec): Keycap
	local cleanup = Cleanup.new()
	local size = spec.sizePx or DEFAULT_SIZE_PX
	-- The size is the minimum: a larger text size grows the cap (AutomaticSize XY), so the key always fits.
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Theme.foam(root, {
		radius = math.floor(size * RADIUS_SHARE),
		stroke = 0,
		drop = DROP_PX,
		colors = { face = Theme.Colors.inkUI, drop = Theme.Colors.ink2 },
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, PADDING_X),
		PaddingRight = UDim.new(0, PADDING_X),
		PaddingBottom = UDim.new(0, DROP_PX),
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, 0, root)
	local label = Theme.label({
		Name = "Key",
		Text = "",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	}, "Chip", nil, Theme.Colors.frosting)

	local self = {} :: Keycap
	self.root = root
	self.label = label

	function self.setText(_: Keycap, text: string?)
		label.Text = text or ""
		root.Visible = text ~= nil and text ~= ""
	end

	function self.setKey(_: Keycap, key: string?)
		self:setText(if key then KeyText.get(key) else nil)
	end

	if spec.key then
		self:setKey(spec.key)
	else
		self:setText(spec.text)
	end

	function self.destroy(_: Keycap)
		cleanup:clean()
	end

	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return Keycap
