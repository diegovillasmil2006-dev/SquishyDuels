--!strict
-- SquishyImage (client only). UI FINAL R2 (plan work/ui/PLAN.md §2 toy thumbnails, T7, T8; `H:n` = "Squishy Duels
-- HUD.dc.html" line n): a squishy drawn as the design draws its toys' <img> (H:205, H:224, H:274, H:305, H:523, H:542,
-- H:846), from a 2D picture of the game's own squishy (AssetTable img.squishy.<catalogId>, pack 2), never the
-- design's placeholder toys.
--   local image = SquishyImage.new("toast", { size = 88, owned = true, shadow = { px = 5, alpha = 0.3 }, parent = card
--   }) image:setOwned(false);   image:setCatalogId("dragon");   image:squash(1.2, 0.8);   image:destroy()
-- * With the picture: an ImageLabel "Image" (ScaleType Fit) over an optional drop-shadow copy "Shadow" (the same
--   picture tinted the ink at `alpha`, `px` lower: filter drop-shadow(0 Npx 0 rgba(30,20,40,a))); not owned it is the
--   design's silhouette, brightness(0) opacity(.42) (H:922), black at ImageTransparency .58, and the shadow hides
--   (the design swaps the drop-shadow filter for the silhouette's, H:936).
-- * While that picture has no id: a StaticIcon (the 3D model in a ViewportFrame, greyed when not owned) over the
--   img.fx.glow picture tinted the ink as its shadow (T7's How) when a shadow is asked for, at its px and alpha
--   (reading: FALLBACK_SHADOW_SHARE of the size); it hides too when not owned.
-- * squash(sx, sy) sizes the picture holder about its centre (a non-uniform squash, G2.2; the StaticIcon fallback takes
--   the uniform part, as a ViewportFrame cannot squash out of shape).
-- AFFECTED 2026-10-15: fusion (Golden, Rainbow) and the 7 coatings will need a variant look on this component; it draws
-- the base picture now.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)
local StaticIcon = require(script.Parent.StaticIcon)

-- Types

export type Shadow = { px: number, alpha: number }

export type Options = {
	size: number?, -- base px square (default DEFAULT_SIZE_PX)
	owned: boolean?, -- default true
	shadow: Shadow?,
	name: string?, -- default "SquishyImage"
	layoutOrder: number?,
	parent: Instance?,
}

export type SquishyImage = {
	root: Frame,
	setOwned: (self: SquishyImage, owned: boolean) -> (),
	setCatalogId: (self: SquishyImage, catalogId: string) -> (),
	squash: (self: SquishyImage, sx: number, sy: number) -> (),
	catalogId: (self: SquishyImage) -> string,
	destroy: (self: SquishyImage) -> (),
}

-- Constants

local DEFAULT_SIZE_PX = 88
local KEY_PREFIX = "img.squishy."
local GLOW_KEY = "img.fx.glow"
local SILHOUETTE_TRANSPARENCY = 0.58 -- H:922: brightness(0) opacity(.42)
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local FALLBACK_SHADOW_SHARE = 0.9 -- reading: the ink glow under the 3D fallback, a share of its size

-- Module table

local SquishyImage = {}

-- Public: pure

-- The AssetTable key of a squishy's picture.
function SquishyImage.keyOf(catalogId: string): string
	return KEY_PREFIX .. catalogId
end

function SquishyImage.new(catalogId: string, options: Options?): SquishyImage
	local o: Options = options or {}
	local cleanup = Cleanup.new()
	local size = o.size or DEFAULT_SIZE_PX
	local owned = o.owned ~= false
	local current = catalogId
	local root: Frame = Create("Frame", {
		Name = o.name or "SquishyImage",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = o.layoutOrder or 0,
	})
	cleanup:add(root)
	-- The picture's holder: squashed about the centre, never placed by a layout.
	local holder: Frame = Create("Frame", {
		Name = "Holder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	local parts = Cleanup.new()
	cleanup:add(parts)
	local image: ImageLabel? = nil
	local shadowPart: ImageLabel? = nil
	local icon: StaticIcon.StaticIcon? = nil
	local iconScale: UIScale? = nil

	local function paintOwned()
		local picture = image
		if picture then
			picture.ImageColor3 = if owned then WHITE else BLACK
			picture.ImageTransparency = if owned then 0 else SILHOUETTE_TRANSPARENCY
		end
		local shade = shadowPart
		if shade then
			shade.Visible = owned -- H:936: a silhouette has no drop shadow
		end
		local model = icon
		if model then
			model:setOwned(owned)
		end
	end

	local function build()
		parts:clean()
		image, icon, iconScale, shadowPart = nil, nil, nil, nil
		local content = AssetTable.image(SquishyImage.keyOf(current))
		local shadow = o.shadow
		if content then
			if shadow then
				shadowPart = parts:add(Create("ImageLabel", {
					Name = "Shadow",
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, shadow.px),
					Size = UDim2.fromScale(1, 1),
					Image = content,
					ImageColor3 = Theme.Colors.inkUI,
					ImageTransparency = 1 - shadow.alpha,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 1,
					Parent = holder,
				}))
			end
			image = parts:add(Create("ImageLabel", {
				Name = "Image",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = content,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 2,
				Parent = holder,
			}))
		else
			local glow = AssetTable.image(GLOW_KEY)
			if glow and shadow then
				shadowPart = parts:add(Create("ImageLabel", {
					Name = "Shadow",
					BackgroundTransparency = 1,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 0, 0.5, shadow.px),
					Size = UDim2.fromScale(FALLBACK_SHADOW_SHARE, FALLBACK_SHADOW_SHARE),
					Image = glow,
					ImageColor3 = Theme.Colors.inkUI,
					ImageTransparency = 1 - shadow.alpha,
					ZIndex = 1,
					Parent = holder,
				}))
			end
			local model = StaticIcon.new({ name = "Icon", squishyId = current, sizePx = size, parent = holder })
			model.root.AnchorPoint = Vector2.new(0.5, 0.5)
			model.root.Position = UDim2.fromScale(0.5, 0.5)
			model.root.ZIndex = 2
			parts:add(model)
			iconScale = Create("UIScale", { Name = "SD_Squash", Parent = model.root })
			icon = model
		end
		paintOwned()
	end
	build()

	local self = {} :: SquishyImage
	self.root = root

	function self.setOwned(_: SquishyImage, isOwned: boolean)
		owned = isOwned
		paintOwned()
	end

	function self.setCatalogId(_: SquishyImage, id: string)
		if id == current then
			return
		end
		current = id
		build()
	end

	-- sx / sy of the picture (1 = rest); the 3D fallback takes √(sx·sy).
	function self.squash(_: SquishyImage, sx: number, sy: number)
		holder.Size = UDim2.fromScale(sx, sy)
		local uniform = iconScale
		if uniform then
			uniform.Scale = math.sqrt(math.max(0, sx * sy))
			holder.Size = UDim2.fromScale(1, 1)
		end
	end

	function self.catalogId(_: SquishyImage): string
		return current
	end

	function self.destroy(_: SquishyImage)
		cleanup:clean()
	end

	if o.parent then
		root.Parent = o.parent
	end
	return self
end

return SquishyImage
