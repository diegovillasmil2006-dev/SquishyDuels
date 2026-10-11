--!strict
-- CoinIcon (client only). DESIGN §11.6 ("coin icon built from UI shapes"), §11.2 (no image ids yet), §7.2 (the reserved
-- Coin colours, used only for Coins), §4.3 (Coins always carry the coin icon).
--   local icon = CoinIcon.new({ name = "CoinIcon", sizePx = 28, parent = pill })
-- A foam coin (foam UI restyle, spec 2026-10-09: "the coin disc keeps the game's coin tokens"): a CoinGold disc with
-- the InkUI outline, a CoinHighlight band along its top, a CoinRing bevel band and an InkUI drop band along its bottom,
-- and an inner CoinHighlight disc ringed in CoinRing. Every measure is a share of the coin's size (outline at least
-- OUTLINE_MIN_PX), so the 22 px flight coins and the 52 px capsule disc look alike, and the bands are drawn once for
-- that size (they scale with the coin when a flight grows or shrinks it).
-- When AssetTable gets a vetted `img.coin` id it is shown instead (an ImageLabel); until then the shapes stay.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	sizePx: number?,
	layoutOrder: number?,
	parent: Instance?,
}

export type CoinIcon = {
	root: Frame,
	destroy: (self: CoinIcon) -> (),
}

-- Constants

local DEFAULT_SIZE_PX = 28
-- Shares of the coin's size (the design's 64 px coin: outline 3, top 3, bevel 5, drop 4, inner disc 32 with a 3 px
-- ring).
local OUTLINE_SHARE = 3 / 64
local OUTLINE_MIN_PX = 1.5
local TOP_SHARE = 3 / 64
local BEVEL_SHARE = 5 / 64
local DROP_SHARE = 4 / 64
local INNER_SCALE = 0.5 -- the inner disc, as a fraction of the coin
local INNER_RING_SHARE = 3 / 64
local INNER_LIFT = 0.04 -- the inner disc sits a little above the middle, on the face (share of the coin)
local IMAGE_KEY = "img.coin"

-- Module table

local CoinIcon = {}

-- Public

function CoinIcon.new(spec: Spec): CoinIcon
	local cleanup = Cleanup.new()
	local size = spec.sizePx or DEFAULT_SIZE_PX
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)

	local image = AssetTable.image(IMAGE_KEY)
	if image then
		Create("ImageLabel", {
			Name = "Image",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = image,
			Parent = root,
		})
	else
		local disc: Frame = Create("Frame", {
			Name = "Disc",
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Parent = root,
		})
		Theme.foam(disc, {
			radius = size,
			stroke = math.max(OUTLINE_MIN_PX, size * OUTLINE_SHARE),
			top = size * TOP_SHARE,
			bevel = size * BEVEL_SHARE,
			drop = size * DROP_SHARE,
			colors = {
				face = Palette.CoinGold,
				top = Palette.CoinHighlight,
				bevel = Palette.CoinRing,
				drop = Palette.InkUI,
			},
			fixedHeight = size,
		})
		local inner: Frame = Create("Frame", {
			Name = "Ring",
			BackgroundColor3 = Palette.CoinHighlight,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5 - INNER_LIFT),
			Size = UDim2.fromScale(INNER_SCALE, INNER_SCALE),
			Parent = disc,
		})
		Theme.corner(size, inner)
		Theme.stroke(Palette.CoinRing, math.max(1, size * INNER_RING_SHARE), inner)
	end

	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: CoinIcon
	self.root = root
	function self.destroy(_: CoinIcon)
		cleanup:clean()
	end
	return self
end

return CoinIcon
