--!strict
-- Confetti2D (client only). DESIGN §18.5.2 B7 (result panel confetti), §18.1 #4 (nothing red), §18.9 (UI juice frames),
-- §18.12 #25 (18 pieces on a win, 6 on a draw, none on a defeat).
--   local handle = Confetti2D.play(layer, title, Config.Anim.duel.confetti.pieces, Confetti2D.WIN_COLORS, uiScale)
-- Rounded rectangles (w × h px) launched from a point (vx ±vxPx, vy -vyMinPx..-vyMaxPx px/s, gravity gravityPx px/s²,
-- spin ±spinDeg °/s, life `lifetime` s, fading over the last fadeSeconds), drawn inside `layer` (a frame that covers the
-- panel, never the screen). They bounce softly off the layer's edges, so a piece never leaves the panel (reading:
-- DESIGN launches them upward from the title at the top of the panel, faster than the room above it allows).
-- Colours: WIN_COLORS (Strawberry, Mint, Lemon, Sky) or DRAW_COLORS (Sky, Lavender); never Danger and never red.
-- Foam UI restyle (spec 2026-10-09: the ink-outlined look): each piece has a thin InkUI outline that fades with it.
-- One Scheduler render effect per burst; nothing under ReducedMotion (play returns nil).
-- Pure: isRed, spawn, step, transparencyAt (unit-tested in Edit mode with a seeded Random).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Piece = {
	x: number, -- centre, base px from the layer's top-left
	y: number,
	vx: number, -- px/s
	vy: number,
	rotation: number, -- degrees
	spin: number, -- degrees/s
	age: number, -- seconds
	color: Color3,
}

export type Handle = {
	stop: (self: Handle) -> (),
	isAlive: (self: Handle) -> boolean,
}

-- Constants

local CONFETTI = Config.Anim.duel.confetti
local SPLAT = Config.Vfx.Splat -- the red guard's numbers (redHueDeg, redMinSaturation), shared with the splats
-- reading (DESIGN gives no bounce): the share of speed a piece keeps when it touches an edge of the panel.
local RESTITUTION = 0.35
local CORNER_PX = 3 -- reading: "rounded rectangles"
local OUTLINE_PX = 1.5 -- foam restyle: the pieces' ink outline (Theme.Stroke.thin)
local OUTLINE_COLOR = Palette.InkUI
local LAYER_Z = 4

-- Module table

local Confetti2D = {}

Confetti2D.WIN_COLORS = table.freeze({ Palette.Strawberry, Palette.Mint, Palette.Lemon, Palette.Sky })
Confetti2D.DRAW_COLORS = table.freeze({ Palette.Sky, Palette.Lavender })

-- Private

-- Half the diagonal of a piece: its centre stays this far inside every edge, whatever its rotation.
local REACH = math.sqrt(CONFETTI.w * CONFETTI.w + CONFETTI.h * CONFETTI.h) / 2

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- [lo, hi] for a centre inside `size`, or the middle when the room is smaller than a piece.
local function range(size: number): (number, number)
	if size < 2 * REACH then
		return size / 2, size / 2
	end
	return REACH, size - REACH
end

-- Public: pure ------------------------------------------------------------------------------------------------------

-- True for a hue within redHueDeg of red with HSV saturation above redMinSaturation (the splats' guard, §18.4.1).
function Confetti2D.isRed(color: Color3): boolean
	local h, s = color:ToHSV()
	local hueDeg = h * 360
	return math.min(hueDeg, 360 - hueDeg) <= SPLAT.redHueDeg and s > SPLAT.redMinSaturation
end

-- `count` pieces at `origin` (base px in the layer), colours taken in turn from `colors` (red ones are skipped).
function Confetti2D.spawn(rng: Random, count: number, origin: Vector2, colors: { Color3 }): { Piece }
	local safe: { Color3 } = {}
	for _, color in colors do
		if not Confetti2D.isRed(color) and color ~= Palette.Danger then
			table.insert(safe, color)
		end
	end
	if #safe == 0 then
		safe = { Palette.Sky }
	end
	local pieces: { Piece } = {}
	for i = 1, math.max(0, math.floor(count)) do
		table.insert(pieces, {
			x = origin.X,
			y = origin.Y,
			vx = rng:NextNumber(-CONFETTI.vxPx, CONFETTI.vxPx),
			vy = -rng:NextNumber(CONFETTI.vyMinPx, CONFETTI.vyMaxPx),
			rotation = rng:NextNumber(0, 360),
			spin = rng:NextNumber(-CONFETTI.spinDeg, CONFETTI.spinDeg),
			age = 0,
			color = safe[(i - 1) % #safe + 1],
		})
	end
	return pieces
end

-- Moves a piece by dt inside a layer of `size` base px (semi-implicit Euler, soft bounces at the edges). Returns
-- whether it is still alive (age < lifetime).
function Confetti2D.step(piece: Piece, dt: number, size: Vector2): boolean
	local h = if finite(dt) and dt > 0 then dt else 0
	piece.age += h
	piece.vy += CONFETTI.gravityPx * h
	piece.x += piece.vx * h
	piece.y += piece.vy * h
	piece.rotation = (piece.rotation + piece.spin * h) % 360
	local minX, maxX = range(size.X)
	local minY, maxY = range(size.Y)
	if piece.x < minX then
		piece.x, piece.vx = minX, math.abs(piece.vx) * RESTITUTION
	elseif piece.x > maxX then
		piece.x, piece.vx = maxX, -math.abs(piece.vx) * RESTITUTION
	end
	if piece.y < minY then
		piece.y, piece.vy = minY, math.abs(piece.vy) * RESTITUTION
	elseif piece.y > maxY then
		piece.y, piece.vy = maxY, -math.abs(piece.vy) * RESTITUTION
	end
	return piece.age < CONFETTI.lifetime
end

-- A piece's transparency at `age`: 0, then fading to 1 over the last fadeSeconds of its lifetime.
function Confetti2D.transparencyAt(age: number): number
	local fadeFrom = CONFETTI.lifetime - CONFETTI.fadeSeconds
	if not finite(age) or age <= fadeFrom then
		return 0
	elseif age >= CONFETTI.lifetime or CONFETTI.fadeSeconds <= 0 then
		return 1
	end
	return (age - fadeFrom) / CONFETTI.fadeSeconds
end

-- Public: runtime ---------------------------------------------------------------------------------------------------

-- Bursts `count` pieces from `from` (a GuiObject's centre, or a point in base px inside `layer`) inside `layer`, whose
-- offsets are scaled by `uiScale` (UIController.scale()). nil under ReducedMotion or for no pieces.
function Confetti2D.play(
	layer: GuiObject,
	from: GuiObject | Vector2,
	count: number,
	colors: { Color3 },
	uiScale: number,
	rng: Random?
): Handle?
	if Tweens.reducedMotion() or not (count >= 1) then
		return nil
	end
	local scale = if finite(uiScale) and uiScale > 0 then uiScale else 1
	local random = rng or Random.new()
	local pieces: { Piece }? = nil
	local frames: { Frame } = {}
	local outlines: { UIStroke } = {}
	local alive = true
	local handle = {} :: Handle
	local scheduled: Scheduler.Handle? = nil

	local function stop()
		if not alive then
			return
		end
		alive = false
		if scheduled then
			scheduled:disconnect()
			scheduled = nil
		end
		for _, frame in frames do
			frame:Destroy()
		end
		table.clear(frames)
		table.clear(outlines)
	end

	-- The layer's size in base px and the origin, once the layout has given the layer a size.
	local function measure(): (Vector2?, Vector2?)
		local size = layer.AbsoluteSize / scale
		if size.X <= 0 or size.Y <= 0 then
			return nil, nil
		end
		if typeof(from) == "Vector2" then
			return size, from :: Vector2
		end
		local object = from :: GuiObject
		if object.Parent == nil then
			return size, size / 2
		end
		local centre = object.AbsolutePosition + object.AbsoluteSize / 2
		return size, (centre - layer.AbsolutePosition) / scale
	end

	scheduled = Scheduler.add(function(dt: number): boolean
		if not alive or layer.Parent == nil then
			stop()
			return false
		end
		local size, origin = measure()
		if size == nil or origin == nil then
			return true -- not laid out yet: start on a later frame
		end
		local existing = pieces
		local list: { Piece } = if existing then existing else Confetti2D.spawn(random, count, origin, colors)
		if existing == nil then
			pieces = list
			for i, piece in list do
				local frame: Frame = Create("Frame", {
					Name = "Confetti" .. i,
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = piece.color,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(CONFETTI.w, CONFETTI.h),
					ZIndex = LAYER_Z,
					Parent = layer,
				})
				Create("UICorner", { CornerRadius = UDim.new(0, CORNER_PX), Parent = frame })
				local outline: UIStroke = Create("UIStroke", {
					Color = OUTLINE_COLOR,
					Thickness = OUTLINE_PX,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Parent = frame,
				})
				table.insert(frames, frame)
				table.insert(outlines, outline)
			end
		end
		local any = false
		for i, piece in list do
			local frame = frames[i]
			if frame then
				local live = Confetti2D.step(piece, dt, size)
				frame.Visible = live
				if live then
					any = true
					frame.Position = UDim2.fromOffset(piece.x, piece.y)
					frame.Rotation = piece.rotation
					local transparency = Confetti2D.transparencyAt(piece.age)
					frame.BackgroundTransparency = transparency
					local outline = outlines[i]
					if outline then
						outline.Transparency = transparency
					end
				end
			end
		end
		if not any then
			stop()
			return false
		end
		return true
	end, "render")

	function handle.stop(_: Handle)
		stop()
	end
	function handle.isAlive(_: Handle): boolean
		return alive
	end
	return handle
end

return Confetti2D
