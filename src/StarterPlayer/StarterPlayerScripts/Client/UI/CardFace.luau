--!strict
-- CardFace (client only). UI FINAL R5 (plan work/ui/PLAN.md R5, Diego's design "Squishy Duels UI FINAL"; `H:n` =
-- "Squishy Duels HUD.dc.html" line n): the design's squishy card face, drawn into a card root (a GuiObject sized by its
-- grid: the face and its lip; numbers in Config.UI.Inventory.card). One purple face for every rarity (H:203-212):
--   * the face (SD_Face, the root less the lip): #A385FF -> #7A57F2 (StickerCardTop / Bottom), the 4 px ink border
--     drawn inside, radius 20, the inset highlight 2 px at .1 along its top (H:935);
--   * the lip (SD_Lip): the 5 px ink copy of the face under it (box-shadow 0 5px 0 #1E1428), behind the face;
--   * selected (H:935): a white border, no inset highlight, a 4 px ring in the rarity's colour around the face
--     (SD_Ring, radius 24) and a 26 px glow in it (SD_Glow, img.fx.glow tinted, 52 px bigger), behind the lip.
-- The caller's own content goes above the face (ZIndex 1 and up); the face's parts sit at ZIndex 0 and below. A card
-- that is not owned keeps the face: its picture is the silhouette and the lock (the caller's).
--   local face = CardFace.new(root, "Epic")
--   face:paint({ owned = true, selected = false });   face:setHover(0.5);   face:destroy()
-- setHover(mix) paints the design's hover filter, brightness(1.07) saturate(1.06) at `mix` (Button.hoverColor, H:637),
-- for Button.decorate's onFilter. The old Candy faces (the rarity gradient, rim, Epic gradient, Exclusive shimmer and
-- the art glow) are gone (G5.7); the Shop's cards take this face until R6 (its options are accepted and ignored).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local RarityStyle = require(Shared.Art.RarityStyle)

local Button = require(script.Parent.Components.Button)
local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

-- Types

export type Options = {
	radius: number?, -- kept for the Shop's call (the design's radius 20 is used)
	artCenterY: number?,
	artPx: number?,
}

export type State = { owned: boolean, selected: boolean }

export type CardFace = {
	face: Frame,
	paint: (self: CardFace, state: State) -> (),
	setHover: (self: CardFace, mix: number) -> (),
	destroy: (self: CardFace) -> (),
}

-- Constants

local CARD = Config.UI.Inventory.card
local GLOW_KEY = "img.fx.glow"
local WHITE = Color3.new(1, 1, 1)
local FACE_Z = 0
local LIP_Z = -1
local RING_Z = -2
local GLOW_Z = -3

-- Module table

local CardFace = {}

-- Public

-- The face's colours (pure): the purple gradient (H:203) with its inset highlight unless selected (H:935), under the
-- hover filter at `mix` (0 = none).
function CardFace.colors(selected: boolean, mix: number?): Theme.FoamColors
	local m = math.clamp(mix or 0, 0, 1)
	local function lit(color: Color3): Color3
		return if m > 0 then color:Lerp(Button.hoverColor(color), m) else color
	end
	local top = Palette.StickerCardTop
	return {
		face = lit(top),
		faceEnd = lit(Palette.StickerCardBottom),
		top = lit(if selected then top else top:Lerp(WHITE, CARD.highlightAlpha)),
	}
end

-- The ring's and glow's colour for a rarity (its design colour, lib:12-17), the ink for anything else.
function CardFace.ringColor(rarity: string): Color3
	local style = RarityStyle.get(rarity)
	return if style then style.ui.base or style.color else Theme.Colors.inkUI
end

function CardFace.new(root: GuiObject, rarity: string, _options: Options?): CardFace
	local cleanup = Cleanup.new()
	local ringColor = CardFace.ringColor(rarity)
	root.BackgroundTransparency = 1 -- the parts draw the card (the root is its hit box)
	local function part(name: string, z: number, outset: number): Frame
		local frame: Frame = Create("Frame", {
			Name = name,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, -outset),
			Size = UDim2.new(1, 2 * outset, 1, 2 * outset - CARD.lip),
			Active = false,
			ZIndex = z,
			Parent = root,
		})
		cleanup:add(frame)
		return frame
	end
	local face = part("SD_Face", FACE_Z, 0)
	local foam = Theme.foam(face, {
		radius = CARD.radius,
		stroke = CARD.border,
		inner = true,
		top = CARD.border + CARD.highlightPx,
		colors = CardFace.colors(false),
	})
	local lip = part("SD_Lip", LIP_Z, 0)
	lip.Position = UDim2.new(0.5, 0, 0, CARD.lip)
	lip.BackgroundColor3 = Theme.Colors.inkUI
	Theme.corner(CARD.radius, lip)
	local ring = part("SD_Ring", RING_Z, CARD.ringPx)
	ring.BackgroundColor3 = ringColor
	ring.Visible = false
	Theme.corner(CARD.ringRadius, ring)
	local glowImage = AssetTable.image(GLOW_KEY)
	local glow: ImageLabel? = nil
	if glowImage then
		local made: ImageLabel = Create("ImageLabel", {
			Name = "SD_Glow",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, -CARD.glowPx),
			Size = UDim2.new(1, 2 * CARD.glowPx, 1, 2 * CARD.glowPx - CARD.lip),
			Image = glowImage,
			ImageColor3 = ringColor,
			Visible = false,
			Active = false,
			ZIndex = GLOW_Z,
			Parent = root,
		})
		cleanup:add(made)
		glow = made
	end

	local selected = false
	local self = {} :: CardFace
	self.face = face

	function self.paint(_: CardFace, state: State)
		selected = state.selected
		foam:paint(CardFace.colors(selected))
		foam:setStroke(if selected then WHITE else Theme.Colors.inkUI, CARD.border)
		ring.Visible = selected
		if glow then
			glow.Visible = selected
		end
	end

	function self.setHover(_: CardFace, mix: number)
		foam:paint(CardFace.colors(selected, mix))
	end

	function self.destroy(_: CardFace)
		cleanup:clean()
	end

	return self
end

return CardFace
