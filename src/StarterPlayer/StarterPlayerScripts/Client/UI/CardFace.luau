--!strict
-- CardFace (client only). UI overhaul (2026-10-11, Candy UI): the collectible card look shared by the Squishies and
-- Shop grids, after the references' coloured item cards. On a card root (a GuiObject sized by its grid):
--   * the face: an "exact" foam surface (Theme.foam) in the rarity's colours (Art/RarityStyle `ui`: faceTop fading to
--     faceBottom, a deep bevel and the PlumInk drop), the PlumInk 3 px outline (Theme.Stroke.ink);
--   * the rim: an inner stroke (Theme.rim) in the rarity's glow, `card.strokePx` thick, carrying the rarity flourish of
--     Art/RarityStyle `card.gradient` (the Epic gradient; the Exclusive shimmer, which the caller turns: `gradient`);
--   * the glow: a soft disc in the rarity's glow behind the art (ZIndex 0, under the card's content), centred on the
--     art (setArt moves it when the card is resized).
-- States (paint): owned (the rarity face), locked (not owned: the dark disabled face, the rim and the glow faint; the
-- caller greys the art and shows the lock), selected (on top of either: a white SELECTED_PX outline and a brighter rim).
-- Colour is never the only sign: the card's chips and texts say owned, locked, equipped or new.
--   local face = CardFace.new(root, "Epic", { radius = 16, artCenterY = 54, artPx = 96 })
--   face:paint({ owned = true, selected = false });   face:setArt(54, 96);   face:destroy()

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local RarityStyle = require(Shared.Art.RarityStyle)

local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

-- Types

export type Options = {
	radius: number?, -- base px; default Theme.Radius.button
	artCenterY: number?, -- the art's centre, base px from the card's top (no glow without it)
	artPx: number?, -- the art's size (the glow is GLOW_SHARE of it)
}

export type State = { owned: boolean, selected: boolean }

export type CardFace = {
	outline: UIStroke,
	rim: UIStroke,
	gradient: UIGradient?, -- the rarity flourish on the rim (nil for a rarity without one)
	glow: Frame?,
	paint: (self: CardFace, state: State) -> (),
	setArt: (self: CardFace, centerY: number, px: number) -> (),
	destroy: (self: CardFace) -> (),
}

-- Constants

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local BEVEL_MIX = 0.3 -- the bevel band: faceBottom this far towards black
local SELECTED_PX = 4 -- the selected card's white outline
local RIM_TRANSPARENCY = 0.35
local RIM_SELECTED_TRANSPARENCY = 0.05
local RIM_LOCKED_TRANSPARENCY = 0.85
local GLOW_SHARE = 1.05 -- the glow disc, as a share of the art's size
local GLOW_TRANSPARENCY = 0.72
local GLOW_LOCKED_TRANSPARENCY = 0.94
-- Readings: the faces of a squishy with no rarity style and of a locked card.
local FALLBACK_UI = { faceTop = Theme.Colors.panelAlt, faceBottom = Theme.Colors.panel, glow = Theme.Colors.ink2 }

-- Module table

local CardFace = {}

CardFace.SELECTED_PX = SELECTED_PX

-- Public

-- The face colours of a card (pure): the rarity's for an owned card, the disabled ones for a locked card.
function CardFace.colors(rarity: string, owned: boolean): Theme.FoamColors
	if not owned then
		return {
			face = Theme.Colors.disabledFace,
			faceEnd = Theme.Colors.disabledShade,
			bevel = Theme.Colors.disabledShade:Lerp(BLACK, BEVEL_MIX),
			drop = Theme.Colors.inkUI,
		}
	end
	local style = RarityStyle.get(rarity)
	local ui = if style then style.ui else FALLBACK_UI
	return {
		face = ui.faceTop,
		faceEnd = ui.faceBottom,
		bevel = ui.faceBottom:Lerp(BLACK, BEVEL_MIX),
		drop = Theme.Colors.inkUI,
	}
end

function CardFace.new(root: GuiObject, rarity: string, options: Options?): CardFace
	local cleanup = Cleanup.new()
	local o: Options = options or {}
	local radius = o.radius or Theme.Radius.button
	local style = RarityStyle.get(rarity)
	local ui = if style then style.ui else FALLBACK_UI
	local foam = Theme.foam(root, {
		radius = radius,
		stroke = Theme.Stroke.ink,
		bevel = Theme.Foam.panel.bevel,
		drop = Theme.Foam.panel.drop,
		colors = CardFace.colors(rarity, true),
	})
	local outline = foam.stroke :: UIStroke
	local rim = Theme.rim(root, ui.glow, RIM_TRANSPARENCY, if style then style.card.strokePx else Theme.Stroke.bar)
	local gradient: UIGradient? = nil
	local spec = if style then style.card.gradient else nil
	if spec then
		local keypoints: { ColorSequenceKeypoint } = {}
		for index, color in spec.colors do
			table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / math.max(1, #spec.colors - 1), color))
		end
		rim.Color = WHITE -- the gradient paints the rim
		gradient = Create("UIGradient", {
			Name = "Flourish",
			Color = ColorSequence.new(keypoints),
			Rotation = spec.rotationDeg,
			Parent = rim,
		})
	end

	local glow: Frame? = nil
	if o.artCenterY then
		local disc: Frame = Create("Frame", {
			Name = "ArtGlow",
			BackgroundColor3 = ui.glow,
			BackgroundTransparency = GLOW_TRANSPARENCY,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Active = false,
			ZIndex = 0,
			Parent = root,
		})
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = disc })
		glow = disc
	end

	local self = {} :: CardFace
	self.outline = outline
	self.rim = rim
	self.gradient = gradient
	self.glow = glow

	function self.setArt(_: CardFace, centerY: number, px: number)
		local disc = glow
		if disc then
			local size = math.floor(px * GLOW_SHARE)
			disc.Position = UDim2.new(0.5, 0, 0, centerY)
			disc.Size = UDim2.fromOffset(size, size)
		end
	end

	function self.paint(_: CardFace, state: State)
		foam:paint(CardFace.colors(rarity, state.owned))
		foam:setStroke(if state.selected then WHITE else Theme.Colors.inkUI, if state.selected then SELECTED_PX else Theme.Stroke.ink)
		rim.Transparency = if state.selected
			then RIM_SELECTED_TRANSPARENCY
			elseif state.owned then RIM_TRANSPARENCY
			else RIM_LOCKED_TRANSPARENCY
		local disc = glow
		if disc then
			disc.BackgroundTransparency = if state.owned then GLOW_TRANSPARENCY else GLOW_LOCKED_TRANSPARENCY
		end
	end

	function self.destroy(_: CardFace)
		cleanup:clean()
	end

	if o.artCenterY then
		self:setArt(o.artCenterY, o.artPx or 0)
	end
	cleanup:add(rim)
	if glow then
		cleanup:add(glow)
	end
	return self
end

return CardFace
