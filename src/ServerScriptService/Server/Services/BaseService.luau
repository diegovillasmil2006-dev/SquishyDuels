--!strict
-- BaseService (server only). Lobby bases spec 2026-10-11 §2, §4, §6, §8; build plan Phases 3 and 4.
-- The island's 10 plots (WorldLayout.Bases), one per player in the server:
-- * playerAdded: the lowest free plot. It goes to the Player attribute SD_Plot (1..10; clients read it) and the
--   plot's name sign shows the player's DisplayName (the owner view below). The player spawns on the plot (its
--   SpawnLocation, WorldLayout.Tags.BaseSpawn with the Plot attribute) once the world has one (Squish Island, Phase 4);
--   without it CharacterService's lobby spawn stays. With no plot free (a player who left is freed on their leave
--   hook, so only briefly, or in a Studio test with more players than plots), it tries again every RETRY_SECONDS for
--   RETRY_FOR_SECONDS while the player waits in the hub; a plot found later is used from their next respawn.
-- * Batch 3 (friends, review #6): a player who joined from a friend's invite (GetJoinData().ReferredByPlayerId) or
--   followed a friend in (Player.FollowUserId) while that friend has a plot here gets the free plot nearest to the
--   friend's on the ring (min(|i - p|, 10 - |i - p|); a tie takes the lower number) instead of the lowest one.
-- * playerRemoving: the plot is free again ("Open plot", grey, no pen). Rejoining gives the lowest free plot again
--   (maybe another one); the pen lives in the profile, so it comes back wherever the player lands.
-- * The owner view (Phase 4, spec §4, §8): render(plot) shows on the plot's generated Model (Tags.Base with that Plot)
--   who owns it. The name sign's live "Owner" label reads the owner's DisplayName, or Strings base.openPlot; every part
--   with SD_BaseTint ("full" / "light") takes the plot's colour (WorldLayout.Bases.colors) while it has an owner and the
--   open grey (Bases.openColors) otherwise.
-- * Pens3 phase 1 (the pen replaced the capsules and the statue): a "Pen" Folder, replaced on every render, holds the
--   owner's pen (drawPen; lobby design v6, `LK:n` = lobby-kit.js line n, `K:n` = kit.json line n), built in the plot's
--   frame from WorldLayout.Bases.pen and its steps[spots]:
--   - Fence: one Model "Segment" per 4-stud piece of LK:82-85 pen_fence (2 Rails, 3 Pickets and, once per spot on the
--     outline, a Post with its PostTop ball): K's segment count (the front split by the gateWidth gap) plus the back
--     fence at 9-12 spots, where K's back wall is the shelf of phase 11 (placeholder); posts and rails in the tier's
--     colours (Palette PenFence*, K:4170-4189); every visual part out of collisions, queries, touches and shadows.
--     Five invisible Colliders (3.2 tall, 0.5 thick) hold the outline: both front pieces beside the gate, the sides,
--     the back.
--   - Sign: the Model "Sign" (LK:96-101 pen_upgrade_sign: Post, the state Trim, the price Face with its SurfaceGui
--     Title / Row (Icon, Price) / Line) at Bases.pen.signs.pen, attributes SD_PenSign = plot and SD_Price = the next
--     spot's price (none at maxSpots); the Face's ProximityPrompt (PenPrompt) is a hold of Config.Economy.Pen
--     .signHoldSeconds, off at MAX. Everyone sees this face: the title, the coin icon and the price (MAX with the star
--     picture and the gold trim at maxSpots; the star is a picture, not LK's star shape: placeholder); the owner's
--     client recolours its own sign locally and writes its Line (Controllers/PenController).
--   - The base Model's attributes for every client's walking squishies (PenController): SD_PenSpots, SD_Pen
--     (PenMath.encode of the placed items), SD_PenRate (PenMath.rate) and SD_PenTier; none on an open plot.
--   A plot renders when it is handed out or freed, when its owner's profile loads (the data port's Loaded) and on
--   refresh(player) after a pen change (PenService: a spot bought, a squishy granted). Until the profile is ready a plot
--   shows its owner's name and colour only; without the generated plot or with a broken pen nothing is drawn and
--   nothing fails.
-- No remote ever names a plot: PenBuySpot always buys the caller's own next spot.
-- Dependencies are injectable (useDeps) so unit tests run without the world or the task scheduler; a player is only a
-- table key (an Instance also gets the attribute; a Player also gets the spawn). playerAdded / playerRemoving never
-- yield.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local PenMath = require(Shared.PenMath)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

-- Types

export type Deps = {
	delay: (seconds: number, fn: () -> ()) -> (), -- task.delay
	spawnOf: (plot: number) -> SpawnLocation?, -- the plot's SpawnLocation in the generated world, or nil
	plotModel: (plot: number) -> Instance?, -- the plot's generated Model, or nil
	penOf: (player: any) -> any, -- the pen (Types.PenState) of the player's READY profile, or nil
	displayNameOf: (player: any) -> string,
	friendOf: (player: any) -> any?, -- Batch 3: the friend in this server who invited the player (or was followed)
}

-- Constants

local PLOT_COUNT = #WorldLayout.Bases.frames
local ATTR_PLOT = "SD_Plot"
local TAG_SPAWN = WorldLayout.Tags.BaseSpawn
local ATTR_SPAWN_PLOT = WorldLayout.Attributes.Plot
local RETRY_FOR_SECONDS = 5 -- lobby spec §6: "it tries again for up to 5 s"
local RETRY_SECONDS = 0.5 -- reading (the spec gives no step)
local TAG_BASE = WorldLayout.Tags.Base
local ATTR_TINT = WorldLayout.Attributes.BaseTint
local OWNER_LABEL = "Owner"
-- Pens3 phase 1: the pen (see the header).
local PEN = WorldLayout.Bases.pen
local PEN_FOLDER = "Pen"
local PEN_ATTRS = { "SD_PenSpots", "SD_Pen", "SD_PenRate", "SD_PenTier" }
local TIER_COLORS = { -- K:4170-4189
	{ post = "PenFenceWaferPost", rail = "PenFenceWaferRail" },
	{ post = "PenFenceMintPost", rail = "PenFenceMintRail" },
	{ post = "PenFenceRoyalPost", rail = "PenFenceRoyalRail" },
}
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Roblox cylinder runs along X: this stands it up
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- a side segment: its X along the plot's Z
-- LK:83-84 pen_fence, in segment studs (4 along its X): posts r 0.35 h 3.2 at x ±2 with r 0.45 balls at y 3.3; rails
-- r 0.22 along it at y 1.2 and 2.4; pickets 0.5 × 2.6 × 0.25 at x -1, 0, 1 from y 0.3.
local POST_SIZE = Vector3.new(3.2, 0.7, 0.7)
local POST_X = 2
local BALL_SIZE = Vector3.new(0.9, 0.9, 0.9)
local BALL_Y = 3.3
local RAIL_SIZE = Vector3.new(4, 0.44, 0.44)
local RAIL_Y = { 1.2, 2.4 }
local PICKET_SIZE = Vector3.new(0.5, 2.6, 0.25)
local PICKET_Y = 0.3 + 2.6 / 2
local PICKET_X = { -1, 0, 1 }
local COLLIDER_HEIGHT = 3.2 -- the plan: as tall as the posts, 0.5 thick
local COLLIDER_THICK = 0.5
-- LK:97-99 pen_upgrade_sign, in sign studs (its front -Z = the Face's side): the post r 0.25 h 3.2 at z 0.15, the state
-- trim 3.8 × 2.8 × 0.3 from y 3 at z 0.15, the price face 3.4 × 2.4 × 0.3 centred at y 4.4, z -0.05.
local SIGN_POST_SIZE = Vector3.new(3.2, 0.5, 0.5)
local SIGN_POST = CFrame.new(0, 1.6, 0.15) * UPRIGHT
local SIGN_TRIM_SIZE = Vector3.new(3.8, 2.8, 0.3)
local SIGN_TRIM = CFrame.new(0, 3 + 2.8 / 2, 0.15)
local SIGN_FACE_SIZE = Vector3.new(3.4, 2.4, 0.3)
local SIGN_FACE = CFrame.new(0, 4.4, -0.05)
-- The face's SurfaceGui (reading; Kit/Signs' look: 50 px a stud, LightInfluence 0.15, Fredoka One, ink text): the title
-- in its top quarter, the icon and price row in the middle, the owner's line under it (y and h: shares of the face's
-- height; px: the largest text size).
local SIGN_PX_PER_STUD = 50
local SIGN_LIGHT = 0.15
local SIGN_FONT = Enum.Font.FredokaOne
local SIGN_INSET = 0.05 -- each side
local SIGN_TITLE = { y = 0.06, h = 0.24, px = 25 }
local SIGN_ROW = { y = 0.34, h = 0.32, px = 32, gap = 4 }
local SIGN_LINE = { y = 0.72, h = 0.2, px = 20 }
local PROMPT_STUDS = 10 -- the plan

-- Module table

local BaseService = {}

-- Private

local log = Log.new("Base")
local owners: { [number]: any } = {} -- plot -> player
local plots: { [any]: number } = {} -- player -> plot
local waiting: { [any]: boolean } = {} -- players with no plot yet, still retrying

local function defaultDeps(): Deps
	return {
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
		spawnOf = function(plot: number): SpawnLocation?
			for _, instance in WorldService.stations(TAG_SPAWN) do
				if instance:IsA("SpawnLocation") and instance:GetAttribute(ATTR_SPAWN_PLOT) == plot then
					return instance
				end
			end
			return nil
		end,
		plotModel = function(plot: number): Instance?
			for _, instance in WorldService.stations(TAG_BASE) do
				if instance:GetAttribute(ATTR_SPAWN_PLOT) == plot then
					return instance
				end
			end
			return nil
		end,
		penOf = function(player: any): any
			local port = StateService.dataPort()
			if port.status(player) ~= "ready" then
				return nil
			end
			local profile = port.getProfile(player)
			return if type(profile) == "table" then profile.pen else nil
		end,
		displayNameOf = function(player: any): string
			local ok, name = pcall(function(): any
				return player.DisplayName
			end)
			return if ok and type(name) == "string" then name else tostring(player)
		end,
		friendOf = function(player: any): any?
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return nil
			end
			local ok, data = pcall(player.GetJoinData, player) -- never yields
			local id = if ok and type(data) == "table" then (data :: any).ReferredByPlayerId else nil
			if type(id) ~= "number" or id <= 0 then
				id = player.FollowUserId
			end
			return if type(id) == "number" and id > 0 then Players:GetPlayerByUserId(id) else nil
		end,
	}
end

local deps: Deps = defaultDeps()

-- Writes `text` into the TextLabel `name` somewhere under `model`.
local function setLabel(model: Instance, name: string, text: string)
	local label = model:FindFirstChild(name, true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- A visual part of the pen: anchored, out of collisions, queries, touches and shadows.
local function piece(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- The part blocks players but stays out of queries (Kit/Prims' barrier order: CanQuery false after CanCollide).
local function block(part: Part): Part
	part.CanCollide = true
	part.CanQuery = false
	return part
end

-- The plot-local frame of every fence segment at `step` (see the header): the front pieces from the gate out, the two
-- sides from the front back (their X along the plot's Z), then the back (K's "shelf" back wall is a fence until phase
-- 11: placeholder).
local function segmentFrames(step: WorldLayout.PenStep): { CFrame }
	local frames: { CFrame } = {}
	local seg, half = PEN.segment, step.w / 2
	local gate = PEN.gateWidth / 2
	for i = 0, (half - gate) / seg - 1 do
		local x = gate + seg / 2 + i * seg
		table.insert(frames, CFrame.new(-x, 0, PEN.frontZ))
		table.insert(frames, CFrame.new(x, 0, PEN.frontZ))
	end
	for i = 0, step.d / seg - 1 do
		local z = PEN.frontZ - seg / 2 - i * seg
		table.insert(frames, CFrame.new(-half, 0, z) * ALONG_Z)
		table.insert(frames, CFrame.new(half, 0, z) * ALONG_Z)
	end
	for i = 0, step.w / seg - 1 do
		table.insert(frames, CFrame.new(-half + seg / 2 + i * seg, 0, PEN.frontZ - step.d))
	end
	return frames
end

-- The fence (see the header): LK's segment parts, one post (and its ball) per spot on the outline.
local function drawFence(folder: Instance, frame: CFrame, step: WorldLayout.PenStep)
	local colors = TIER_COLORS[step.tier] or TIER_COLORS[1]
	local post, rail = Palette[colors.post], Palette[colors.rail]
	local fence = Instance.new("Folder")
	fence.Name = "Fence"
	local posts: { [string]: boolean } = {}
	for _, spot in segmentFrames(step) do
		local at = frame * spot
		local segment = Instance.new("Model")
		segment.Name = "Segment"
		for _, x in { -POST_X, POST_X } do
			local p = spot * Vector3.new(x, 0, 0)
			local key = `{math.round(p.X * 100) + 0},{math.round(p.Z * 100) + 0}` -- + 0 makes -0 a 0
			if not posts[key] then
				posts[key] = true
				local base = at * CFrame.new(x, 0, 0)
				piece(
					"Post",
					Enum.PartType.Cylinder,
					POST_SIZE,
					base * CFrame.new(0, POST_SIZE.X / 2, 0) * UPRIGHT,
					post,
					segment
				)
				piece("PostTop", Enum.PartType.Ball, BALL_SIZE, base * CFrame.new(0, BALL_Y, 0), post, segment)
			end
		end
		for _, y in RAIL_Y do
			piece("Rail", Enum.PartType.Cylinder, RAIL_SIZE, at * CFrame.new(0, y, 0), rail, segment)
		end
		for _, x in PICKET_X do
			piece("Picket", Enum.PartType.Block, PICKET_SIZE, at * CFrame.new(x, PICKET_Y, 0), rail, segment)
		end
		segment.WorldPivot = at
		segment.Parent = fence
	end
	fence.Parent = folder
end

-- The invisible walls on the outline (see the header).
local function drawColliders(folder: Instance, frame: CFrame, step: WorldLayout.PenStep)
	local function collider(size: Vector3, cframe: CFrame)
		local part = Instance.new("Part")
		part.Name = "Collider"
		part.Size = size
		part.CFrame = frame * cframe
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = folder
	end
	local half, gate, y = step.w / 2, PEN.gateWidth / 2, COLLIDER_HEIGHT / 2
	local front = half - gate
	for _, side in { -1, 1 } do
		collider(
			Vector3.new(front, COLLIDER_HEIGHT, COLLIDER_THICK),
			CFrame.new(side * (gate + front / 2), y, PEN.frontZ)
		)
		collider(
			Vector3.new(COLLIDER_THICK, COLLIDER_HEIGHT, step.d),
			CFrame.new(side * half, y, PEN.frontZ - step.d / 2)
		)
	end
	collider(Vector3.new(step.w, COLLIDER_HEIGHT, COLLIDER_THICK), CFrame.new(0, y, PEN.frontZ - step.d))
end

-- The one-line width (px) of a sign text at `px` (TextService; a roomy estimate when it cannot answer).
local function textWidth(text: string, px: number): number
	local ok, size = pcall(function(): Vector2
		return TextService:GetTextSize(text, px, SIGN_FONT, Vector2.new(1000, 1000))
	end)
	return if ok and typeof(size) == "Vector2" then size.X else #text * px * 0.6
end

-- A TextLabel of the sign face, scaled to its box under the text size `px`.
local function signLabel(name: string, text: string, px: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = SIGN_FONT
	label.Text = text
	label.TextColor3 = Palette.PenSignText
	label.TextScaled = true
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = px
	cap.Parent = label
	label.Parent = parent
	return label
end

-- The PEN SPACE sign (see the header); `price` is the next spot's, nil at MAX.
local function drawSign(folder: Instance, frame: CFrame, plot: number, price: number?)
	local at = frame * PEN.signs.pen
	local max = price == nil
	local sign = Instance.new("Model")
	sign.Name = "Sign"
	block(piece("Post", Enum.PartType.Cylinder, SIGN_POST_SIZE, at * SIGN_POST, Palette.PenSignPost, sign))
	local trim = if max then Palette.PenSignMax else Palette.PenSignCanBuy
	block(piece("Trim", Enum.PartType.Block, SIGN_TRIM_SIZE, at * SIGN_TRIM, trim, sign))
	local face = block(piece("Face", Enum.PartType.Block, SIGN_FACE_SIZE, at * SIGN_FACE, Palette.PenSignFace, sign))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = SIGN_PX_PER_STUD
	gui.LightInfluence = SIGN_LIGHT
	local width = 1 - 2 * SIGN_INSET
	local title = signLabel("Title", Strings.pen.sign.title, SIGN_TITLE.px, gui)
	title.Position = UDim2.fromScale(SIGN_INSET, SIGN_TITLE.y)
	title.Size = UDim2.fromScale(width, SIGN_TITLE.h)
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(SIGN_INSET, SIGN_ROW.y)
	row.Size = UDim2.fromScale(width, SIGN_ROW.h)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, SIGN_ROW.gap)
	list.Parent = row
	local rowPx = SIGN_FACE_SIZE.Y * SIGN_PX_PER_STUD * SIGN_ROW.h
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(rowPx, rowPx)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = AssetTable.image(if max then "img.icon.star" else "img.coin") or ""
	icon.LayoutOrder = 1
	icon.Parent = row
	local text = if price ~= nil then Format.coins(price) else Strings.pen.sign.max
	local room = SIGN_FACE_SIZE.X * SIGN_PX_PER_STUD * width - rowPx - SIGN_ROW.gap
	local priceLabel = signLabel("Price", text, SIGN_ROW.px, row)
	priceLabel.Size = UDim2.fromOffset(math.min(room, math.ceil(textWidth(text, SIGN_ROW.px)) + 2), rowPx)
	priceLabel.LayoutOrder = 2
	row.Parent = gui
	local line = signLabel("Line", "", SIGN_LINE.px, gui)
	line.Position = UDim2.fromScale(SIGN_INSET, SIGN_LINE.y)
	line.Size = UDim2.fromScale(width, SIGN_LINE.h)
	gui.Parent = face
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PenPrompt"
	prompt.ActionText = Strings.pen.prompt.action
	prompt.ObjectText = Strings.pen.prompt.object
	prompt.HoldDuration = Config.Economy.Pen.signHoldSeconds
	prompt.MaxActivationDistance = PROMPT_STUDS
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Enabled = not max
	prompt.Parent = face
	sign:SetAttribute("SD_PenSign", plot)
	sign:SetAttribute("SD_Price", price)
	sign.WorldPivot = at
	sign.Parent = folder
end

-- The owner's pen on the plot (see the header): a fresh "Pen" Folder and the base Model's pen attributes. False (and
-- nothing drawn) for a spot count with no step.
local function drawPen(model: Instance, plot: number, pen: any): boolean
	local step = PEN.steps[pen.spots]
	local frame = WorldLayout.plotFrame(plot)
	if step == nil or frame == nil then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = PEN_FOLDER
	drawFence(folder, frame, step)
	drawColliders(folder, frame, step)
	drawSign(folder, frame, plot, PenMath.spotPrice(pen.spots + 1))
	folder.Parent = model
	model:SetAttribute("SD_PenSpots", pen.spots)
	model:SetAttribute("SD_Pen", PenMath.encode(PenMath.placed(pen)))
	model:SetAttribute("SD_PenRate", PenMath.rate(pen))
	model:SetAttribute("SD_PenTier", step.tier)
	return true
end

-- Shows the plot's owner on its generated Model, or an open plot (see the header). Never throws.
local function render(plot: number)
	local ok, err = pcall(function(): any
		local model = deps.plotModel(plot)
		if model == nil then
			return nil
		end
		local owner = owners[plot]
		local colors = if owner ~= nil then WorldLayout.Bases.colors[plot] else WorldLayout.Bases.openColors
		for _, part in model:GetDescendants() do
			local which = part:GetAttribute(ATTR_TINT)
			if part:IsA("BasePart") and (which == "full" or which == "light") then
				part.Color = Palette[colors[which]]
			end
		end
		local name = if owner ~= nil then deps.displayNameOf(owner) else Strings.resolve("base.openPlot") or ""
		setLabel(model, OWNER_LABEL, name)
		local old = model:FindFirstChild(PEN_FOLDER)
		if old then
			old:Destroy()
		end
		local pen = if owner ~= nil then deps.penOf(owner) else nil
		if type(pen) ~= "table" or not drawPen(model, plot, pen) then
			for _, attribute in PEN_ATTRS do
				model:SetAttribute(attribute, nil) -- not cleared before a draw, so a client never sees a gap
			end
		end
		return nil
	end)
	if not ok then
		log:warn(`could not draw plot {plot}:`, err)
	end
end

-- The free plot for the player: the one nearest their friend's plot on the ring (Batch 3; a tie takes the lower
-- number), else the lowest free one; nil when all are taken.
local function freePlot(player: any): number?
	local friend = deps.friendOf(player)
	local near = if friend ~= nil then plots[friend] else nil
	local best, bestGap = nil, math.huge
	for plot = 1, PLOT_COUNT do
		if owners[plot] == nil then
			if near == nil then
				return plot
			end
			local gap = math.abs(plot - near)
			gap = math.min(gap, PLOT_COUNT - gap)
			if gap < bestGap then
				best, bestGap = plot, gap
			end
		end
	end
	return best
end

-- Gives the player a free plot (freePlot, and its spawn, when the world has it). Returns it, or nil when all are taken.
local function assign(player: any): number?
	local plot = freePlot(player)
	if plot == nil then
		return nil
	end
	owners[plot] = player
	plots[player] = plot
	if typeof(player) == "Instance" then
		(player :: Instance):SetAttribute(ATTR_PLOT, plot)
		local spawn = deps.spawnOf(plot)
		if spawn and (player :: Instance):IsA("Player") then
			(player :: Player).RespawnLocation = spawn
		end
	end
	render(plot)
	return plot
end

-- Public

-- The player's plot (1..10), or nil while they have none.
function BaseService.plotOf(player: any): number?
	return plots[player]
end

-- The player on plot `plot`, or nil for an open plot.
function BaseService.ownerOf(plot: number): any?
	return owners[plot]
end

-- Redraws the player's plot (their profile loaded, or their pen changed). Nothing for a player without a plot.
function BaseService.refresh(player: any)
	local plot = plots[player]
	if plot ~= nil then
		render(plot)
	end
end

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function BaseService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Frees every plot and stops every retry (tests; not called by the bootstrap).
function BaseService.reset()
	table.clear(owners)
	table.clear(plots)
	table.clear(waiting)
end

-- Lifecycle

function BaseService.init()
	StateService.dataPort().onLoaded(function(player: any)
		BaseService.refresh(player)
	end)
end

function BaseService.playerAdded(player: Player)
	if plots[player] ~= nil or assign(player) ~= nil then
		return
	end
	waiting[player] = true
	local triesLeft = math.floor(RETRY_FOR_SECONDS / RETRY_SECONDS)
	local function retry()
		if not waiting[player] then
			return -- left (or reset) meanwhile
		end
		triesLeft -= 1
		if assign(player) ~= nil then
			waiting[player] = nil
		elseif triesLeft <= 0 then
			waiting[player] = nil
			log:warn(`no free plot for {tostring(player)} after {RETRY_FOR_SECONDS} s; they stay in the hub`)
		else
			deps.delay(RETRY_SECONDS, retry)
		end
	end
	deps.delay(RETRY_SECONDS, retry)
end

function BaseService.playerRemoving(player: Player)
	waiting[player] = nil
	local plot = plots[player]
	if plot ~= nil then
		plots[player] = nil
		owners[plot] = nil
		render(plot)
	end
end

return BaseService
