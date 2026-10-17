--!strict
-- StageLook (client only). UI FINAL R5 (plan work/ui/PLAN.md R5 [G5.1] [G5.11]; `H:n` = "Squishy Duels HUD.dc.html"
-- line n): the design's detail stage (H:218-224, numbers in Config.UI.Inventory.stage), drawn into a holder the caller
-- sizes (the face and its lip): the Squishies detail and, at full size, the Inspect stage.
--   * SD_Lip: the 5 px ink copy of the face under it (box-shadow 0 5px 0 #1E1428);
--   * SD_Face: radius 22, the exact radial picture img.fx.radial.stage<Rarity> (circle at 50% 62%: R.l 0, R.c 62%,
--     R.d 100%; pack 2), else Theme.radial's fallback with the mid ring at .62 centred at (.5, .62);
--   * SD_Clip: the face's inside (inset by the 4 px border; clips): the inset 0 5px 0 white .35 (StageLook.shade),
--     the rays (img.fx.raysDetail, 640 px at (50%, 60%), white .26 x the rarity's opacity, sdSpin 16 s:
--     InventoryFormat.raysAlpha), the floor (150 x 24 at bottom 16, ink .25; opts.floor = false leaves it out: the
--     Inspect stage's own contact shadow is its floor), the three stars (img.icon.star 26 / 20 / 16 at their spots,
--     sdTwinkle 2.2 s from 0 / .8 / 1.4 s) and, above them, `look.slot` (a clear frame filling the clip) for the
--     caller's squishy (the Squishies picture, or Inspect's ViewportStage: the slot carries SD_OwnBackdrop, so the
--     stage draws no background of its own over this look);
--   * SD_Border: the 4 px ink border drawn inside the face, over everything.
--   local look = StageLook.new(holder, { floor = true })
--   look:setRarity("Epic");   look:setFace(186);   look:destroy()
-- StageLook.shade(frame, corner, inset, height, topPx, topAlpha, bottomPx?, bottomAlpha?) draws the design's inset
-- box-shadow bands on a picture surface (a white band along the top at topAlpha, a black one along the bottom at
-- bottomAlpha), an overlay SD_Shade inside `frame`'s border (`inset`) for a box `height` px tall: the stage's highlight
-- and the card plate's (H:204). Every loop rests under ReducedMotion (Anim/UiIdle, Theme.rays).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local RarityStyle = require(Shared.Art.RarityStyle)

local Client = script.Parent.Parent
local Create = require(script.Parent.Create)
local IconGlyph = require(script.Parent.Components.IconGlyph)
local InventoryFormat = require(script.Parent.InventoryFormat)
local Theme = require(script.Parent.Theme)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type Options = { floor: boolean? }

export type StageLook = {
	slot: Frame,
	setRarity: (self: StageLook, rarity: string) -> (),
	setFace: (self: StageLook, facePx: number) -> (),
	destroy: (self: StageLook) -> (),
}

-- Constants

local STAGE = Config.UI.Inventory.stage
local RADIAL_PREFIX = "img.fx.radial.stage"
local RAYS_KEY = "img.fx.raysDetail"
local STAR_KEY = "img.icon.star"
local OWN_BACKDROP_ATTR = "SD_OwnBackdrop"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local EDGE = 0.001 -- a hard edge: two keypoints this far apart
-- Inside the clip (the design's paint order: the background's inset shadow, then the rays, the floor, the stars and
-- the squishy).
local SHADE_Z = 1
local RAYS_Z = 2
local FLOOR_Z = 3
local STAR_Z = 4
local SLOT_Z = 5
local BORDER_Z = 10

-- Module table

local StageLook = {}

-- Public

function StageLook.shade(
	frame: GuiObject,
	corner: UDim,
	inset: number,
	height: number,
	topPx: number,
	topAlpha: number,
	bottomPx: number?,
	bottomAlpha: number?
): Frame
	local existing = frame:FindFirstChild("SD_Shade")
	local shade: Frame = if existing and existing:IsA("Frame")
		then existing
		else Create("Frame", {
			Name = "SD_Shade",
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = SHADE_Z,
			Parent = frame,
		})
	shade.Position = UDim2.fromOffset(inset, inset)
	shade.Size = UDim2.new(1, -2 * inset, 1, -2 * inset)
	local round = shade:FindFirstChildOfClass("UICorner") or Create("UICorner", { Parent = shade })
	round.CornerRadius = corner
	local h = math.max(1, height - 2 * inset)
	local t1 = math.clamp(topPx / h, EDGE, 0.5 - 2 * EDGE)
	local b = bottomPx or 0
	local t2 = if b > 0 then math.clamp(1 - b / h, 0.5, 1 - EDGE) else 1
	local transparency = { NumberSequenceKeypoint.new(0, 1 - topAlpha), NumberSequenceKeypoint.new(t1, 1 - topAlpha) }
	table.insert(transparency, NumberSequenceKeypoint.new(t1 + EDGE, 1))
	local colors = { ColorSequenceKeypoint.new(0, WHITE) }
	if b > 0 then
		table.insert(transparency, NumberSequenceKeypoint.new(t2 - EDGE, 1))
		table.insert(transparency, NumberSequenceKeypoint.new(t2, 1 - (bottomAlpha or 0)))
		table.insert(transparency, NumberSequenceKeypoint.new(1, 1 - (bottomAlpha or 0)))
		table.insert(colors, ColorSequenceKeypoint.new(t2 - EDGE, WHITE))
		table.insert(colors, ColorSequenceKeypoint.new(t2, BLACK))
		table.insert(colors, ColorSequenceKeypoint.new(1, BLACK))
	else
		table.insert(transparency, NumberSequenceKeypoint.new(1, 1))
		table.insert(colors, ColorSequenceKeypoint.new(1, WHITE))
	end
	local gradient = shade:FindFirstChildOfClass("UIGradient")
		or Create("UIGradient", { Rotation = 90, Parent = shade })
	gradient.Transparency = NumberSequence.new(transparency)
	gradient.Color = ColorSequence.new(colors)
	return shade
end

function StageLook.new(holder: GuiObject, options: Options?): StageLook
	local cleanup = Cleanup.new()
	local o: Options = options or {}
	local border, lip, radius = STAGE.border, STAGE.lip, STAGE.radius
	local function frame(name: string, z: number, parent: Instance): Frame
		local made: Frame = Create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, -lip),
			Active = false,
			ZIndex = z,
			Parent = parent,
		})
		cleanup:add(made)
		return made
	end
	local lipFrame = frame("SD_Lip", 0, holder)
	lipFrame.Position = UDim2.fromOffset(0, lip)
	lipFrame.BackgroundColor3 = Theme.Colors.inkUI
	lipFrame.BackgroundTransparency = 0
	Theme.corner(radius, lipFrame)
	local face = frame("SD_Face", 1, holder)
	face.BackgroundTransparency = 0
	Theme.corner(radius, face)
	local clip = frame("SD_Clip", 2, holder)
	clip.Position = UDim2.fromOffset(border, border)
	clip.Size = UDim2.new(1, -2 * border, 1, -2 * border - lip)
	clip.ClipsDescendants = true
	local rays = Theme.rays(clip, RAYS_KEY, STAGE.raysPx, STAGE.raysAlpha, STAGE.raysSpinS, STAGE.raysCentreY)
	if rays then
		rays.ZIndex = RAYS_Z
	end
	if o.floor ~= false then
		local floor: Frame = Create("Frame", {
			Name = "SD_Floor",
			BackgroundColor3 = Theme.Colors.inkUI,
			BackgroundTransparency = 1 - STAGE.floorAlpha,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			-- H:220: bottom 16 of the stage's padding box (the clip)
			Position = UDim2.new(0.5, 0, 1, -STAGE.floorBottom),
			Size = UDim2.fromOffset(STAGE.floorWidth, STAGE.floorHeight),
			Active = false,
			ZIndex = FLOOR_Z,
			Parent = clip,
		})
		Theme.corner(STAGE.floorWidth, floor)
	end
	for index, star in STAGE.stars do
		local icon = IconGlyph.image(STAR_KEY, { name = "SD_Star" .. index, sizePx = star.px, parent = clip })
		icon.ZIndex = STAR_Z
		for _, child in icon:GetChildren() do
			if child:IsA("GuiObject") then
				child.ZIndex = STAR_Z
			end
		end
		local fromRight, fromBottom = star.right ~= nil, star.bottom ~= nil
		icon.AnchorPoint = Vector2.new(if fromRight then 1 else 0, if fromBottom then 1 else 0)
		icon.Position = UDim2.new(
			if fromRight then 1 else 0,
			if fromRight then -star.right else star.left,
			if fromBottom then 1 else 0,
			if fromBottom then -star.bottom else star.top
		)
		UiIdle.add(icon, "twinkle", { periodS = STAGE.twinkleS, delayS = star.delayS })
	end
	local slot = frame("SD_Slot", SLOT_Z, clip)
	slot.Size = UDim2.fromScale(1, 1)
	slot:SetAttribute(OWN_BACKDROP_ATTR, true)
	local borderFrame = frame("SD_Border", BORDER_Z, holder)
	Theme.corner(radius, borderFrame)
	local stroke = Theme.stroke(Theme.Colors.inkUI, border, borderFrame)
	pcall(function()
		(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)

	local self = {} :: StageLook
	self.slot = slot

	function self.setRarity(_: StageLook, rarity: string)
		local style = RarityStyle.get(rarity)
		local ui = if style then style.ui else nil
		local light = if ui then ui.light or ui.faceTop else Theme.Colors.panelAlt
		local base = if ui then ui.base or ui.faceBottom else Theme.Colors.panel
		local dark = if ui then ui.dark or ui.faceBottom else Theme.Colors.bevel
		Theme.radial(face, RADIAL_PREFIX .. rarity, {
			inner = light,
			mid = base,
			midAt = STAGE.midAt,
			outer = dark,
			centre = Vector2.new(0.5, STAGE.centreY),
		})
		if rays then
			rays.ImageTransparency = 1 - InventoryFormat.raysAlpha(rarity)
		end
	end

	function self.setFace(_: StageLook, facePx: number)
		StageLook.shade(clip, UDim.new(0, radius - border), 0, facePx - 2 * border, STAGE.shinePx, STAGE.shineAlpha)
	end

	function self.destroy(_: StageLook)
		cleanup:clean()
	end

	self:setFace(STAGE.face)
	return self
end

return StageLook
