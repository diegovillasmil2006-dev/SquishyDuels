--!strict
-- KillBanner (client only; kill banners 2026-10-16, VillasmilGaming: Valorant-style). The killer's kill banner: a
-- medallion bottom-centre that pops in on a K.O., wears one ornament per K.O. without being knocked out (1k-5k) and its
-- crown at 6k, holds, then shrinks away. Built in code from UI/Create, styled by Art/KillStyle (Art/Palette colours,
-- AssetTable pictures), timed by UI/KillBannerFormat.pose (Config.UI.KillBanner). Drawn only; Controllers/
-- KillBannerController decides when (and plays the sound and the VFX Studio burst behind it).
--   local banner = KillBanner.new(screenGui)
--   banner:show("dragon_blaze", 3, reduced)   -- a K.O. (a K.O. during a banner restarts it, no blink)
--   banner:center() -> (Vector2?, number)      -- the medallion's centre (screen px) and diameter (px), for the burst
--   banner:seek(t)                             -- Studio previews: draw the pose at t seconds and hold it there
--   banner:hide(); banner:destroy()
-- Layers, back to front: Glow (the img.fx.glow picture in the set's glow), CrownFrame (6k only), Frame (the set's
-- frame ring, spinning), Medallion (the face with an ink edge, the inner ring, the centre: the set's squishy in a
-- StaticIcon viewport, or the duel emblem picture; a white flash on top), Pieces (the ornaments and the crown).
-- Pictures with an `outline` get an ink copy behind them (a sticker edge); `donut` and `bubble` pieces are drawn from
-- UI shapes (each shape keeps its own base transparency under the fades).
-- Non-interactive (Active false, no buttons): it never takes a tap. ReducedMotion: KillBannerFormat's plain fade.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local KillStyle = require(Shared.Art.KillStyle)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent
local Create = require(UI.Create)
local KillBannerFormat = require(UI.KillBannerFormat)
local StaticIcon = require(UI.Components.StaticIcon)

-- Types

export type KillBanner = {
	root: Frame,
	show: (self: KillBanner, setId: string, tier: number, reduced: boolean) -> (),
	center: (self: KillBanner) -> (Vector2?, number),
	hide: (self: KillBanner) -> (),
	seek: (self: KillBanner, t: number) -> (),
	showing: (self: KillBanner) -> boolean,
	destroy: (self: KillBanner) -> (),
}

type Piece = {
	holder: Frame,
	scale: UIScale,
	images: { ImageLabel },
	frames: { { frame: Frame, base: number } }, -- a UI shape and its own transparency
	strokes: { UIStroke },
}

-- Constants

local CFG = Config.UI.KillBanner
local INK = Palette.InkUI
local WHITE = Palette.White
local GLOW_SIZE = 2.3 -- × the disc
local RING_SIZE = 0.84 -- × the disc
local CENTER_SQUISHY = 0.98 -- × the disc (the toy may peek out of the ring)
local CENTER_IMAGE = 0.8
local EDGE_PX = 4 -- the medallion's ink edge
local RING_PX = 5
local OUTLINE_GROW = 1.16 -- an outline copy's size × the picture
local CROWN_RADIUS = 1.06 -- the crown pieces sit a little further out than the ornaments
local GLOW_KEY = "img.fx.glow"
local BUBBLE_BODY_ALPHA = 0.35 -- the bubble's see-through body

-- Module table

local KillBanner = {}

-- Private

local function color(token: string?): Color3
	local value = if token then (Palette :: any)[token] else nil
	return if typeof(value) == "Color3" then value else WHITE
end

local function picture(key: string?): string
	return if key then AssetTable.image(key) or "" else ""
end

local function circle(name: string, size: number, fill: Color3?, z: number, parent: Instance): Frame
	return Create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = fill or WHITE,
		BackgroundTransparency = if fill then 0 else 1,
		BorderSizePixel = 0,
		ZIndex = z,
		Active = false,
		Parent = parent,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	})
end

local function image(name: string, key: string?, size: number, tint: Color3, z: number, parent: Instance): ImageLabel
	return Create("ImageLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(size, size),
		BackgroundTransparency = 1,
		Image = picture(key),
		ImageColor3 = tint,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = z,
		Active = false,
		Parent = parent,
	})
end

-- A mini glazed donut from UI shapes (Sprinkle Blast): dough, glaze, hole, four sprinkles.
local function donut(holder: Frame, piece: Piece, z: number)
	local dough = circle("Dough", 1, Palette.KillDonutDough, z, holder)
	local edge = Create("UIStroke", { Color = INK, Thickness = 2, Parent = dough })
	local glaze = circle("Glaze", 0.84, Palette.Strawberry, z + 1, holder)
	glaze.Position = UDim2.fromScale(0.5, 0.46)
	local hole = circle("Hole", 0.32, Palette.KillDonutCream, z + 2, holder)
	local holeEdge = Create("UIStroke", { Color = INK, Thickness = 2, Parent = hole })
	table.insert(piece.frames, { frame = dough, base = 0 })
	table.insert(piece.frames, { frame = glaze, base = 0 })
	table.insert(piece.frames, { frame = hole, base = 0 })
	table.insert(piece.strokes, edge)
	table.insert(piece.strokes, holeEdge)
	local sprinkles = {
		{ Palette.Lemon, 0.27, 0.3, 35 },
		{ Palette.Mint, 0.7, 0.28, -40 },
		{ Palette.Sky, 0.24, 0.62, -60 },
		{ WHITE, 0.74, 0.62, 25 },
	}
	for i, s in sprinkles do
		local bit: Frame = Create("Frame", {
			Name = "Sprinkle" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(s[2], s[3]),
			Size = UDim2.fromScale(0.2, 0.07),
			Rotation = s[4],
			BackgroundColor3 = s[1],
			BorderSizePixel = 0,
			ZIndex = z + 3,
			Parent = holder,
		}, { Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
		table.insert(piece.frames, { frame = bit, base = 0 })
	end
end

-- A cartoon bubble from UI shapes (Bubble Burst): a see-through aqua body with an ink edge and a white shine.
local function bubble(holder: Frame, piece: Piece, z: number)
	local body = circle("Body", 1, Palette.KillAxolotlAqua, z, holder)
	local edge = Create("UIStroke", { Color = INK, Thickness = 2, Parent = body })
	local shine = circle("Shine", 0.3, WHITE, z + 1, holder)
	shine.Position = UDim2.fromScale(0.34, 0.32)
	local glint = circle("Glint", 0.12, WHITE, z + 1, holder)
	glint.Position = UDim2.fromScale(0.62, 0.24)
	table.insert(piece.frames, { frame = body, base = BUBBLE_BODY_ALPHA })
	table.insert(piece.frames, { frame = shine, base = 0.1 })
	table.insert(piece.frames, { frame = glint, base = 0.25 })
	table.insert(piece.strokes, edge)
end

local function buildPiece(parent: Instance, spec: KillStyle.Picture, slot: KillBannerFormat.Slot, z: number): Piece
	local radius = CFG.ornamentRadius * (if slot.kind == "crown" then CROWN_RADIUS else 1)
	local a = math.rad(slot.angle)
	local holder: Frame = Create("Frame", {
		Name = (if slot.kind == "crown" then "Crown" else "Ornament") .. slot.order,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.sin(a) * radius, 0.5 - math.cos(a) * radius),
		Size = UDim2.fromScale(spec.size, spec.size),
		Rotation = KillBannerFormat.ornamentAngle(slot.angle, spec.turn),
		BackgroundTransparency = 1,
		ZIndex = z,
		Active = false,
		Parent = parent,
	})
	local piece: Piece = {
		holder = holder,
		scale = Create("UIScale", { Scale = 0, Parent = holder }),
		images = {},
		frames = {},
		strokes = {},
	}
	if spec.donut then
		donut(holder, piece, z)
	elseif spec.bubble then
		bubble(holder, piece, z)
	else
		if spec.outline then
			table.insert(piece.images, image("Outline", spec.image, OUTLINE_GROW, INK, z, holder))
		end
		table.insert(piece.images, image("Picture", spec.image, 1, color(spec.tint), z + 1, holder))
	end
	return piece
end

local function fadePiece(piece: Piece, scale: number, fade: number)
	piece.scale.Scale = scale
	piece.holder.Visible = scale > 0.001 and fade < 0.999
	for _, label in piece.images do
		label.ImageTransparency = fade
	end
	for _, shape in piece.frames do
		shape.frame.BackgroundTransparency = shape.base + (1 - shape.base) * fade
	end
	for _, stroke in piece.strokes do
		stroke.Transparency = fade
	end
end

-- Public

function KillBanner.new(parent: Instance): KillBanner
	local root: Frame = Create("Frame", {
		Name = "KillBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, CFG.centerYShare),
		Size = UDim2.fromOffset(CFG.discPx, CFG.discPx),
		BackgroundTransparency = 1,
		Visible = false,
		Active = false,
		Parent = parent,
	})
	local glow = image("Glow", GLOW_KEY, GLOW_SIZE, WHITE, 1, root)
	local crownFrame = image("CrownFrame", nil, 1, WHITE, 2, root)
	local crownFrameScale: UIScale = Create("UIScale", { Parent = crownFrame })
	local frame = image("Frame", nil, 1, WHITE, 3, root)
	local frameScale: UIScale = Create("UIScale", { Parent = frame })
	local glowScale: UIScale = Create("UIScale", { Parent = glow })
	local medallion: Frame = Create("Frame", {
		Name = "Medallion",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Active = false,
		Parent = root,
	})
	local medScale: UIScale = Create("UIScale", { Parent = medallion })
	local face = circle("Face", 1, WHITE, 4, medallion)
	local edge: UIStroke = Create("UIStroke", { Color = INK, Thickness = EDGE_PX, Parent = face })
	local ring = circle("Ring", RING_SIZE, nil, 5, medallion)
	local ringStroke: UIStroke = Create("UIStroke", { Color = WHITE, Thickness = RING_PX, Parent = ring })
	local centerImage = image("Emblem", nil, CENTER_IMAGE, WHITE, 6, medallion)
	local flash = circle("Flash", 1, WHITE, 8, medallion)
	local pieces: Frame = Create("Frame", {
		Name = "Pieces",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Active = false,
		Parent = root,
	})

	local icon: StaticIcon.StaticIcon? = nil
	local style: KillStyle.Style? = nil
	local slots: { KillBannerFormat.Slot } = {}
	local built: { Piece } = {}
	local started = 0
	local tier = 1
	local replaced = false
	local reduced = false
	local active = false
	local connection: RBXScriptConnection? = nil

	local function stopLoop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local function apply(t: number)
		local s = style
		if s == nil then
			return
		end
		local pose = KillBannerFormat.pose(t, slots, replaced, reduced, tier)
		medScale.Scale = math.max(pose.medScale, 0)
		face.BackgroundTransparency = pose.medFade
		edge.Transparency = pose.medFade
		ringStroke.Transparency = pose.medFade
		centerImage.ImageTransparency = pose.medFade
		if icon then
			icon.root.ImageTransparency = pose.medFade
		end
		flash.BackgroundTransparency = math.max(pose.flashFade, pose.medFade)
		glowScale.Scale = pose.glowScale
		glow.ImageTransparency = pose.glowFade
		frameScale.Scale = pose.frameScale
		frame.ImageTransparency = pose.frameFade
		frame.Rotation = if reduced then 0 else s.frame.spin * pose.frameTurn
		crownFrame.Visible = pose.crownFrameFade < 0.999
		crownFrameScale.Scale = pose.crownFrameScale
		crownFrame.ImageTransparency = pose.crownFrameFade
		crownFrame.Rotation = if reduced then 0 else s.crownFrame.spin * pose.frameTurn
		for index, piece in built do
			local state = pose.pieces[index]
			if state then
				fadePiece(piece, state.scale, state.fade)
			end
		end
		if pose.done then
			active = false
			root.Visible = false
			stopLoop()
		end
	end

	local function layout()
		local gui = root:FindFirstAncestorWhichIsA("LayerCollector")
		local height = if gui then gui.AbsoluteSize.Y else 0
		local uiScale = if gui then gui:FindFirstChildOfClass("UIScale") else nil
		local layoutHeight = height / (if uiScale and uiScale.Scale > 0 then uiScale.Scale else 1)
		local compact = layoutHeight > 0 and layoutHeight < Config.UI.Breakpoints.compactBelowHeight
		local d = KillBannerFormat.discPx(layoutHeight)
		root.Size = UDim2.fromOffset(d, d)
		root.Position = UDim2.fromScale(0.5, KillBannerFormat.centerYShare(compact))
		edge.Thickness = math.max(2, math.floor(EDGE_PX * d / CFG.discPx + 0.5))
		ringStroke.Thickness = math.max(2, math.floor(RING_PX * d / CFG.discPx + 0.5))
	end

	local function dress(s: KillStyle.Style)
		face.BackgroundColor3 = color(s.disc)
		ringStroke.Color = color(s.ring)
		glow.ImageColor3 = color(s.glow)
		frame.Image = picture(s.frame.image)
		frame.ImageColor3 = color(s.frame.tint)
		frame.Size = UDim2.fromScale(s.frame.size, s.frame.size)
		crownFrame.Image = picture(s.crownFrame.image)
		crownFrame.ImageColor3 = color(s.crownFrame.tint)
		crownFrame.Size = UDim2.fromScale(s.crownFrame.size, s.crownFrame.size)
		local squishyId = s.squishyId
		if squishyId then
			centerImage.Visible = false
			local current = icon
			if current == nil then
				current = StaticIcon.new({ name = "Squishy", squishyId = squishyId, sizePx = CFG.discPx })
				current.root.AnchorPoint = Vector2.new(0.5, 0.5)
				current.root.Position = UDim2.fromScale(0.5, 0.52)
				current.root.Size = UDim2.fromScale(CENTER_SQUISHY, CENTER_SQUISHY)
				current.root.ZIndex = 6
				current.root.Parent = medallion
				icon = current
			else
				current:setSquishy(squishyId)
			end
			current.root.Visible = true
		else
			centerImage.Visible = true
			centerImage.Image = picture(s.centerImage)
			if icon then
				icon.root.Visible = false
			end
		end
	end

	local function rebuildPieces(s: KillStyle.Style)
		for _, piece in built do
			piece.holder:Destroy()
		end
		table.clear(built)
		slots = KillBannerFormat.slots(tier, s.crown.count, s.crown.fan)
		for _, slot in slots do
			local spec = if slot.kind == "crown" then s.crown else s.ornament
			local piece = buildPiece(pieces, spec, slot, 10)
			fadePiece(piece, 0, 1)
			table.insert(built, piece)
		end
	end

	local self = {} :: KillBanner
	self.root = root

	function self.show(_: KillBanner, setId: string, newTier: number, isReduced: boolean)
		local s = KillStyle.get(KillStyle.resolve(setId)) :: KillStyle.Style
		replaced = active
		reduced = isReduced
		tier = KillBannerFormat.tierFor(newTier)
		if style ~= s then
			style = s
			dress(s)
		end
		layout()
		rebuildPieces(s)
		started = os.clock()
		active = true
		root.Visible = true
		apply(0)
		if connection == nil then
			connection = RunService.RenderStepped:Connect(function()
				apply(os.clock() - started)
			end)
		end
	end

	function self.center(_: KillBanner): (Vector2?, number)
		if not active then
			return nil, 0
		end
		local size = root.AbsoluteSize
		return root.AbsolutePosition + size / 2, size.Y
	end

	function self.hide(_: KillBanner)
		active = false
		root.Visible = false
		stopLoop()
	end

	function self.seek(_: KillBanner, t: number)
		if not active then
			return
		end
		stopLoop()
		started = os.clock() - t
		apply(t)
	end

	function self.showing(_: KillBanner): boolean
		return active
	end

	function self.destroy(_: KillBanner)
		stopLoop()
		if icon then
			icon:destroy()
			icon = nil
		end
		root:Destroy()
	end

	return self
end

return KillBanner
