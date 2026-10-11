--!strict
-- SideIcon (client only). DESIGN §7.8 (sides are "always labelled with text and icon in the UI, never colour alone"),
-- §11.6 (duel HUD side labels), §11.2 (no image ids yet: drawn from UI shapes).
--   local icon = SideIcon.new({ name = "SideIcon", side = "A", parent = row })
--   icon:setSide("B")
-- Side A ("Strawberry side"): a berry, a round body in the side colour with three seed dots under a leaf cap.
-- Side B ("Mint side"): a mint leaf, a rounded diamond in the side colour with an Ink centre vein.
-- The two outlines differ (round with a cap vs. a diamond), so the icon reads without colour; the side text sits next
-- to it (DuelController). Foam UI (spec 2026-10-09): InkUI 2 px outlines; the side colours and shapes are unchanged.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)

-- Types

export type Kind = "strawberry" | "mint"

export type Spec = {
	name: string,
	side: string, -- "A" or "B"
	sizePx: number?,
	layoutOrder: number?,
	parent: Instance?,
}

export type SideIcon = {
	root: Frame,
	setSide: (self: SideIcon, side: string) -> (),
	kind: (self: SideIcon) -> Kind,
	destroy: (self: SideIcon) -> (),
}

-- Constants

local DEFAULT_SIZE_PX = 20
local STRAWBERRY_NAME = "Strawberry"
local MINT_NAME = "Mint"
local LEAF_COLOR = Palette.Mint
local SEED_COLOR = Palette.Lemon
-- Seed dots inside the berry body (scale of the body).
local SEEDS = { Vector2.new(0.32, 0.42), Vector2.new(0.66, 0.4), Vector2.new(0.5, 0.68) }

-- Module table

local SideIcon = {}

-- Private

local function round(parent: Instance)
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = parent })
end

local function buildStrawberry(root: Frame): Frame
	local holder: Frame = Create("Frame", {
		Name = STRAWBERRY_NAME,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	local body: Frame = Create("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(0.82, 0.78),
		BackgroundColor3 = Theme.Colors.sideA,
		BorderSizePixel = 0,
		Parent = holder,
	})
	round(body)
	Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.bar, body)
	for index, at in SEEDS do
		local seed: Frame = Create("Frame", {
			Name = "Seed" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(at.X, at.Y),
			Size = UDim2.fromScale(0.14, 0.14),
			BackgroundColor3 = SEED_COLOR,
			BorderSizePixel = 0,
			Parent = body,
		})
		round(seed)
	end
	-- The leaf cap: two small leaves fanned out on top of the body.
	for index, angle in { -35, 35 } do
		local leaf: Frame = Create("Frame", {
			Name = "Leaf" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + (if angle < 0 then -0.13 else 0.13), 0.2),
			Size = UDim2.fromScale(0.38, 0.2),
			Rotation = angle,
			BackgroundColor3 = LEAF_COLOR,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = holder,
		})
		round(leaf)
		Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.bar, leaf)
	end
	return holder
end

local function buildMint(root: Frame): Frame
	local holder: Frame = Create("Frame", {
		Name = MINT_NAME,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	local leaf: Frame = Create("Frame", {
		Name = "Leaf",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.66, 0.66),
		Rotation = 45,
		BackgroundColor3 = Theme.Colors.sideB,
		BorderSizePixel = 0,
		Parent = holder,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.3, 0), Parent = leaf })
	Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.bar, leaf)
	Create("Frame", {
		Name = "Vein",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1.1, 0, 0, 2),
		Rotation = 45,
		BackgroundColor3 = Theme.Colors.inkUI,
		BorderSizePixel = 0,
		Parent = leaf,
	})
	return holder
end

-- Public

-- Pure: the icon of a side ("A" = Strawberry side, anything else = Mint side, like DuelFormat.sideText).
function SideIcon.kindOf(side: string): Kind
	return if side == "A" then "strawberry" else "mint"
end

function SideIcon.new(spec: Spec): SideIcon
	local cleanup = Cleanup.new()
	local size = spec.sizePx or DEFAULT_SIZE_PX
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	local strawberry = buildStrawberry(root)
	local mint = buildMint(root)
	local current: Kind = "strawberry"

	local self = {} :: SideIcon
	self.root = root

	function self.setSide(_: SideIcon, side: string)
		current = SideIcon.kindOf(side)
		strawberry.Visible = current == "strawberry"
		mint.Visible = current == "mint"
	end

	function self.kind(_: SideIcon): Kind
		return current
	end

	function self.destroy(_: SideIcon)
		cleanup:clean()
	end

	self:setSide(spec.side)
	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return SideIcon
