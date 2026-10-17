--!strict
-- KillBanner (client only; kill banners 2026-10-16, v2 2026-10-17, VillasmilGaming: Valorant-style). The killer's kill
-- banner, top-centre under the duel / match HUD's top bar (the held squishy at the bottom of the screen stays clear):
-- the set's low-fidelity emblem SLAMS in with a white flash, slashes, two shock rings, shards and a shake; one ornament
-- per K.O. without being knocked out flies in (1k-5k), the 6k crown slams in; it holds, then squashes and pops away.
-- Built in code from UI/Create, styled by Art/KillStyle (Art/Palette colours, AssetTable pictures), timed by
-- UI/KillBannerFormat.pose (Config.UI.KillBanner). Drawn only; Controllers/KillBannerController decides when (and plays
-- the sound and the VFX Studio burst behind it).
--   local banner = KillBanner.new(screenGui)
--   banner:show("dragon_blaze", 3, reduced)   -- a K.O. (a K.O. during a banner restarts it, no blink)
--   banner:center() -> (Vector2?, number)      -- the emblem's centre (screen px) and width (px), for the burst
--   banner:seek(t)                             -- Studio previews: draw the pose at t seconds and hold it there
--   banner:hide(); banner:destroy()
-- Layers, back to front: Rays, Glow, Rings (2), Slashes (2), CrownFrame (6k), Frame, Shadow (the emblem's silhouette in
-- ink, offset), Emblem, Flash (its white silhouette), Pieces (the ornaments), Shards. Pictures with an `outline` get an
-- ink copy behind them; `donut` and `bubble` pieces are drawn from UI shapes (each keeps its own base transparency under
-- the fades). Non-interactive (Active false, no buttons): it never takes a tap. ReducedMotion: KillBannerFormat's fade.

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
	x: number, -- its place (emblems from the centre)
	y: number,
	rot: number,
}

type Ring = { frame: Frame, stroke: UIStroke }

-- Constants

local CFG = Config.UI.KillBanner
local INK = Palette.InkUI
local WHITE = Palette.White
local GLOW_SIZE = 2.2 -- × the emblem
local RAYS_SIZE = 2.6
local SHADOW_OFFSET = Vector2.new(0.035, 0.055) -- emblems
local OUTLINE_GROW = 1.16 -- an outline copy's size × the picture
local CROWN_RADIUS = 1.08 -- the crown pieces sit a little further out than the ornaments
local RING_PX = 7
local SLASH_THICKNESS = 0.06 -- emblems
local SLASH_TURN = -28
local GLOW_KEY = "img.fx.glow"
local RAYS_KEY = "img.fx.rays"
local SHARD_KEY = "img.kill.sparkle"
local BUBBLE_BODY_ALPHA = 0.35
local DUEL_HUD_GUI = "SD_DuelHud"
local DUEL_TOP_BAR = "TopBar"

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

local function centered(props: { [string]: any }): { [string]: any }
	props.AnchorPoint = Vector2.new(0.5, 0.5)
	props.Position = props.Position or UDim2.fromScale(0.5, 0.5)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.BorderSizePixel = 0
	props.Active = false
	return props
end

local function circle(name: string, size: number, fill: Color3?, z: number, parent: Instance): Frame
	return Create("Frame", centered({
		Name = name,
		Size = UDim2.fromScale(size, size),
		BackgroundColor3 = fill or WHITE,
		BackgroundTransparency = if fill then 0 else 1,
		ZIndex = z,
		Parent = parent,
	}), { Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
end

local function image(name: string, key: string?, size: number, tint: Color3, z: number, parent: Instance): ImageLabel
	return Create("ImageLabel", centered({
		Name = name,
		Size = UDim2.fromScale(size, size),
		Image = picture(key),
		ImageColor3 = tint,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = z,
		Parent = parent,
	}))
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
	local rot = KillBannerFormat.ornamentAngle(slot.angle, spec.turn)
	local holder: Frame = Create("Frame", centered({
		Name = (if slot.kind == "crown" then "Crown" else "Ornament") .. slot.order,
		Size = UDim2.fromScale(spec.size, spec.size),
		Rotation = rot,
		ZIndex = z,
		Parent = parent,
	}))
	local piece: Piece = {
		holder = holder,
		scale = Create("UIScale", { Scale = 0, Parent = holder }),
		images = {},
		frames = {},
		strokes = {},
		x = math.sin(a) * radius,
		y = -math.cos(a) * radius,
		rot = rot,
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

local function fadePiece(piece: Piece, state: KillBannerFormat.PieceState)
	piece.scale.Scale = math.max(state.scale, 0)
	piece.holder.Visible = state.scale > 0.001 and state.fade < 0.999
	piece.holder.Position = UDim2.fromScale(0.5 + piece.x * state.radius, 0.5 + piece.y * state.radius)
	piece.holder.Rotation = piece.rot + state.spin
	for _, label in piece.images do
		label.ImageTransparency = state.fade
	end
	for _, shape in piece.frames do
		shape.frame.BackgroundTransparency = shape.base + (1 - shape.base) * state.fade
	end
	for _, stroke in piece.strokes do
		stroke.Transparency = state.fade
	end
end

-- The bottom of the duel / match HUD's top bar in `gui`'s px (both guis' AbsolutePositions share one space), or nil
-- while it is not on screen.
local function topBarBottom(gui: LayerCollector): number?
	local playerGui = gui.Parent
	local hud = playerGui and playerGui:FindFirstChild(DUEL_HUD_GUI)
	if hud == nil or not hud:IsA("ScreenGui") or not hud.Enabled then
		return nil
	end
	local bar = hud:FindFirstChild(DUEL_TOP_BAR, true)
	if bar == nil or not bar:IsA("GuiObject") or not bar.Visible or bar.AbsoluteSize.Y <= 0 then
		return nil
	end
	return bar.AbsolutePosition.Y + bar.AbsoluteSize.Y - gui.AbsolutePosition.Y
end

-- Public

function KillBanner.new(parent: Instance): KillBanner
	local root: Frame = Create("Frame", centered({
		Name = "KillBanner",
		Position = UDim2.fromScale(0.5, CFG.topShare),
		Size = UDim2.fromOffset(CFG.emblemPx, CFG.emblemPx),
		Visible = false,
		Parent = parent,
	}))
	local rays = image("Rays", RAYS_KEY, RAYS_SIZE, WHITE, 1, root)
	local raysScale: UIScale = Create("UIScale", { Parent = rays })
	local glow = image("Glow", GLOW_KEY, GLOW_SIZE, WHITE, 2, root)
	local glowScale: UIScale = Create("UIScale", { Parent = glow })
	local rings: { Ring } = {}
	for i = 1, 2 do
		local frame = circle("Ring" .. i, 1, nil, 3, root)
		local stroke: UIStroke = Create("UIStroke", { Color = WHITE, Thickness = RING_PX, Parent = frame })
		table.insert(rings, { frame = frame, stroke = stroke })
	end
	local slashes: { Frame } = {}
	for i, turn in { 0, SLASH_TURN } do
		local slash: Frame = Create("Frame", centered({
			Name = "Slash" .. i,
			Size = UDim2.fromScale(0, SLASH_THICKNESS),
			Rotation = turn,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0,
			ZIndex = 4,
			Parent = root,
		}), {
			Create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
			Create("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
		})
		table.insert(slashes, slash)
	end
	local crownFrame = image("CrownFrame", nil, 1, WHITE, 5, root)
	local crownFrameScale: UIScale = Create("UIScale", { Parent = crownFrame })
	local frame = image("Frame", nil, 1, WHITE, 6, root)
	local frameScale: UIScale = Create("UIScale", { Parent = frame })
	local emblemHolder: Frame = Create("Frame", centered({ Name = "EmblemHolder", Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = root }))
	local shadow = image("Shadow", nil, 1, INK, 7, emblemHolder)
	local emblem = image("Emblem", nil, 1, WHITE, 8, emblemHolder)
	local flash = image("Flash", nil, 1, WHITE, 9, emblemHolder)
	local pieces: Frame = Create("Frame", centered({ Name = "Pieces", Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = root }))
	local shardLabels: { ImageLabel } = {}
	for i = 1, CFG.shardCount do
		table.insert(shardLabels, image("Shard" .. i, SHARD_KEY, 1, WHITE, 12, root))
	end

	local style: KillStyle.Style? = nil
	local slots: { KillBannerFormat.Slot } = {}
	local shards: { KillBannerFormat.Shard } = {}
	local built: { Piece } = {}
	local started = 0
	local tier = 1
	local replaced = false
	local reduced = false
	local active = false
	local seed = 0
	local basePosition = root.Position
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
		local pose = KillBannerFormat.pose(t, slots, shards, replaced, reduced, tier)
		root.Position = basePosition + UDim2.fromScale(pose.shakeX, pose.shakeY)
		raysScale.Scale = pose.raysScale
		rays.Rotation = pose.raysTurn
		rays.ImageTransparency = pose.raysFade
		glowScale.Scale = pose.glowScale
		glow.ImageTransparency = pose.glowFade
		for i, ring in rings do
			local state = pose.rings[i]
			ring.frame.Size = UDim2.fromScale(state.scale, state.scale)
			ring.stroke.Thickness = math.max(RING_PX * state.thickness, 0)
			ring.stroke.Transparency = state.fade
			ring.frame.Visible = state.fade < 0.999
		end
		for _, slash in slashes do
			slash.Size = UDim2.fromScale(pose.slashScale, SLASH_THICKNESS)
			slash.BackgroundTransparency = pose.slashFade
			slash.Visible = pose.slashFade < 0.999
		end
		frameScale.Scale = pose.frameScale
		frame.ImageTransparency = pose.frameFade
		frame.Rotation = s.frame.spin * pose.frameTurn + (if s.frame.spin >= 0 then pose.frameBoost else -pose.frameBoost)
		crownFrame.Visible = pose.crownFrameFade < 0.999
		crownFrameScale.Scale = pose.crownFrameScale
		crownFrame.ImageTransparency = pose.crownFrameFade
		crownFrame.Rotation = s.crownFrame.spin * pose.frameTurn
		local w, h = pose.emblemScale * pose.emblemSquashX, pose.emblemScale * pose.emblemSquashY
		emblemHolder.Size = UDim2.fromScale(math.max(w, 0), math.max(h, 0))
		emblemHolder.Rotation = pose.emblemTurn
		emblemHolder.Visible = pose.emblemScale > 0.001
		emblem.ImageTransparency = pose.emblemFade
		flash.ImageTransparency = math.max(pose.flashFade, pose.emblemFade)
		shadow.ImageTransparency = pose.shadowFade
		for index, piece in built do
			local state = pose.pieces[index]
			if state then
				fadePiece(piece, state)
			end
		end
		for i, label in shardLabels do
			local state = pose.shards[i]
			if state == nil or state.fade >= 0.999 or state.scale <= 0.001 then
				label.Visible = false
			else
				label.Visible = true
				label.Position = UDim2.fromScale(0.5 + state.x, 0.5 + state.y)
				label.Size = UDim2.fromScale(state.scale, state.scale)
				label.Rotation = state.rot
				label.ImageTransparency = state.fade
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
		if gui == nil then
			return
		end
		local uiScale = gui:FindFirstChildOfClass("UIScale")
		local scale = if uiScale and uiScale.Scale > 0 then uiScale.Scale else 1
		local height = gui.AbsoluteSize.Y / scale
		local d = KillBannerFormat.emblemPx(height)
		local bar = topBarBottom(gui)
		local y = KillBannerFormat.centerY(height, if bar then bar / scale else nil, d)
		root.Size = UDim2.fromOffset(d, d)
		basePosition = UDim2.new(0.5, 0, 0, math.floor(y + 0.5))
		root.Position = basePosition
		shadow.Position = UDim2.fromScale(0.5 + SHADOW_OFFSET.X, 0.5 + SHADOW_OFFSET.Y)
	end

	local function dress(s: KillStyle.Style)
		local ring, glowColour = color(s.ring), color(s.glow)
		rays.ImageColor3 = glowColour
		glow.ImageColor3 = glowColour
		for i, r in rings do
			r.stroke.Color = if i == 1 then WHITE else ring
		end
		slashes[1].BackgroundColor3 = WHITE
		slashes[2].BackgroundColor3 = ring
		frame.Image = picture(s.frame.image)
		frame.ImageColor3 = color(s.frame.tint)
		frame.Size = UDim2.fromScale(s.frame.size, s.frame.size)
		crownFrame.Image = picture(s.crownFrame.image)
		crownFrame.ImageColor3 = color(s.crownFrame.tint)
		crownFrame.Size = UDim2.fromScale(s.crownFrame.size, s.crownFrame.size)
		emblem.Image = picture(s.emblem)
		flash.Image = picture(s.emblemWhite)
		shadow.Image = picture(s.emblemWhite)
		for i, label in shardLabels do
			label.ImageColor3 = color(s.shards[(i - 1) % #s.shards + 1])
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
			fadePiece(piece, { scale = 0, fade = 1, radius = 1, spin = 0 })
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
		seed += 1
		shards = KillBannerFormat.shards(CFG.shardCount, seed * 7919 + tier)
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
		return root.AbsolutePosition + size / 2, size.X
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
		root:Destroy()
	end

	return self
end

return KillBanner
