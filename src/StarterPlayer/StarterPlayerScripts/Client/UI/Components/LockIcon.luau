--!strict
-- LockIcon (client only). DESIGN §11.6 ("Not owned (greyed, lock pip)"), §10.8 ("with a lock pip; never colour alone"),
-- §17.7 ("Locked (text plus a lock shape)"). A small padlock drawn from UI shapes (no image ids, §11.2): an Ink shackle
-- ring above a rounded Ink body (InkUI since the foam UI restyle). Always shown next to a text, never alone.
--   local lock = LockIcon.new({ name = "Lock", sizePx = 16, parent = row })
-- UI FINAL R1 (plan §3): with an img.icon.lock id (the design's lock.svg, H:206) it shows that picture
-- (UI/Components/IconGlyph.image); the shapes until then.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local IconGlyph = require(script.Parent.IconGlyph)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	sizePx: number?,
	color: Color3?,
	layoutOrder: number?,
	parent: Instance?,
}

export type LockIcon = {
	root: Frame,
	destroy: (self: LockIcon) -> (),
}

-- Constants

local DEFAULT_SIZE_PX = 16
local IMAGE_KEY = "img.icon.lock"
local BODY_HEIGHT = 0.58 -- of the icon height
local SHACKLE_WIDTH = 0.62
local SHACKLE_STROKE_PX = 2

-- Module table

local LockIcon = {}

-- Public

function LockIcon.new(spec: Spec): LockIcon
	local cleanup = Cleanup.new()
	local size = spec.sizePx or DEFAULT_SIZE_PX
	local color = spec.color or Theme.Colors.inkUI
	local self = {} :: LockIcon
	function self.destroy(_: LockIcon)
		cleanup:clean()
	end
	if AssetTable.image(IMAGE_KEY) ~= nil then
		self.root = IconGlyph.image(IMAGE_KEY, {
			name = spec.name,
			sizePx = size,
			layoutOrder = spec.layoutOrder,
			parent = spec.parent,
		})
		cleanup:add(self.root)
		return self
	end
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	self.root = root
	local shackle: Frame = Create("Frame", {
		Name = "Shackle",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(SHACKLE_WIDTH, 1 - BODY_HEIGHT + 0.2),
		Parent = root,
	})
	Theme.corner(size, shackle)
	Theme.stroke(color, SHACKLE_STROKE_PX, shackle)
	local body: Frame = Create("Frame", {
		Name = "Body",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, BODY_HEIGHT),
		ZIndex = 2,
		Parent = root,
	})
	Theme.corner(math.max(2, math.floor(size / 5)), body)
	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return LockIcon
