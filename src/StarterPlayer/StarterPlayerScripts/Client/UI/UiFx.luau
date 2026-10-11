--!strict
-- UiFx (client only). UI overhaul (2026-10-11, Candy UI): the UI's celebrations, in importance tiers so the game's
-- juice stays proportional (layered, brief, back to rest):
--   UiFx.burst(at, tier, color?, opts?) -> boolean (false when nothing could be drawn)
--     at     a GuiObject (its centre) or a Vector2 (absolute px, the space of AbsolutePosition)
--     tier   "small" (an equip, a purchase: a ring, a glow and a few sparkles), "medium" (a quest or daily claim, a
--            box opening: + a starburst and a little confetti), "large" (a level up, an Epic reveal: more of each
--            and jelly droplets), "huge" (the top rarity, a win: two rings and the most of everything)
--     color  the main colour (default Gold); the pieces mix it with white and a lighter tint of it (never red)
--     opts   { neutral = true }: every piece white and cream (the box pop: no rarity hint before the reveal,
--            §9.11); { radius = n }: the tier's travel radius overridden (base px)
--   UiFx.punch(object, peak?, ms?)   a pop on the object's own UIScale (SD_Punch, made when it has none): to `peak`
--            (default PUNCH_PEAK) and back with an overshoot
--   UiFx.shake(object, trauma)   a brief, smooth, decaying shake of a window: trauma 0..1 adds up and decays
--            SHAKE_DECAY per second, the offset is SHAKE_PX x trauma² along two sines (never a random jitter), drawn
--            through its AnchorPoint so its layout never moves; back at rest after
--   UiFx.cascade(key, objects, opts?)   a staggered entrance: each object's UIScale (SD_Punch) goes opts.from -> 1
--            (Back Out) over opts.ms, opts.staggerMs apart, the whole set never longer than opts.maxStaggerMs (defaults
--            Config.UI.motion.cardIn); one Scheduler effect per key, and a new cascade on the key first puts the last
--            one's objects at rest (rapid filter changes never stack); nothing under ReducedMotion
--   UiFx.setLayer(screenGui)   the ScreenGui the bursts draw in (UIController: SD_Overlay, above every window)
--   UiFx.activeCount()   bursts running now (tests and leak checks)
-- Every burst is one holder frame at the target's centre whose pieces ONE Scheduler render effect moves; the effect
-- ends by itself and destroys the holder (no permanent per-frame connection). At most MAX_ACTIVE bursts run at once
-- (a new one finishes the oldest early). UiPrefs.fewerEffects halves the pieces (and drops droplets and confetti below
-- "large"). Under ReducedMotion (Anim/Tweens: Roblox's setting or the in-game one) a burst is only its soft glow
-- fading in place; punch and shake do nothing.
-- Pure (unit-tested in Edit mode): TIERS, counts(tier, fewer), rayRect(i, n, length, spinDeg), sparkleAt(...),
-- fallAt(...).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)
local UiPrefs = require(UI.UiPrefs)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Tier = "small" | "medium" | "large" | "huge"

export type TierSpec = {
	radius: number, -- base px the pieces travel
	seconds: number, -- the burst's whole life
	rings: number,
	rays: number,
	sparkles: number,
	confetti: number,
	droplets: number,
}

export type Options = { neutral: boolean?, radius: number? }

export type CascadeOptions = { from: number?, ms: number?, staggerMs: number?, maxStaggerMs: number? }

type Piece = {
	kind: "ray" | "sparkle" | "confetti" | "droplet",
	frame: GuiObject,
	scale: UIScale?,
	stroke: UIStroke?, -- a falling piece's outline (fades with it)
	shine: GuiObject?, -- a droplet's highlight (fades with it)
	angle: number, -- radians (sparkles, falls: the launch direction)
	reach: number, -- base px (sparkles: how far it travels; falls: its launch speed)
	spin: number, -- degrees / second
	delay: number, -- seconds before it starts
}

type Burst = {
	holder: Frame,
	handle: Scheduler.Handle?,
	done: boolean,
}

-- Constants

local TIERS: { [string]: TierSpec } = {
	small = { radius = 70, seconds = 0.6, rings = 1, rays = 0, sparkles = 5, confetti = 0, droplets = 0 },
	medium = { radius = 110, seconds = 0.85, rings = 1, rays = 10, sparkles = 8, confetti = 6, droplets = 0 },
	large = { radius = 150, seconds = 1.1, rings = 2, rays = 14, sparkles = 12, confetti = 12, droplets = 6 },
	huge = { radius = 190, seconds = 1.4, rings = 2, rays = 18, sparkles = 16, confetti = 18, droplets = 10 },
}
for _, spec in TIERS do
	table.freeze(spec)
end

local MAX_ACTIVE = 4
local LAYER_NAME = "SD_Overlay"
local HOLDER_Z = 20
local WHITE = Color3.new(1, 1, 1)
local GOLD = Palette.CandyGold
local NEUTRAL_COLORS = { Color3.new(1, 1, 1), Palette.WarmWhite, Palette.Cream }
-- Rings and the glow.
local RING_DELAY = 0.09 -- the second ring follows the first
local RING_FROM, RING_TO = 0.35, 1.8 -- the ring's diameter, in radii
local RING_PX = 7 -- its stroke at the start (thins to 1)
local GLOW_FROM, GLOW_TO = 0.7, 1.5
local GLOW_TRANSPARENCY = 0.55
-- Rays (the starburst).
local RAY_WIDTH = 10
local RAY_REACH = 1.35 -- in radii, at full length
local RAY_GROW = 0.35 -- the share of the life over which they grow (Back Out)
local RAY_FADE_FROM = 0.45 -- they fade over the rest from this share
local RAY_SPIN_DEG = 30 -- the whole burst turns this much over its life
local RAY_TRANSPARENCY = 0.25
-- Sparkles (four-point stars).
local SPARKLE_PX = 22
local SPARKLE_MIN, SPARKLE_MAX = 0.55, 1.05 -- how far they travel, in radii
local SPARKLE_PEAK = 1.25 -- their scale at the middle of their life
-- Confetti and droplets fall: launched up and out, pulled down.
local GRAVITY = 900 -- base px / s²
local LAUNCH_UP = 260 -- base px / s
local FALL_FADE_FROM = 0.65
local CONFETTI_W, CONFETTI_H = 7, 11
local DROPLET_PX = 12
-- punch and shake.
local PUNCH_NAME = "SD_Punch"
local PUNCH_PEAK = 1.18
local PUNCH_MS = 300
local SHAKE_PX = 9
local SHAKE_DECAY = 2.4 -- trauma per second

-- Module table

local UiFx = {}

UiFx.TIERS = table.freeze(TIERS)
UiFx.MAX_ACTIVE = MAX_ACTIVE

-- Private

local layerGui: ScreenGui? = nil
local active: { Burst } = {}
local punches: { [UIScale]: Tween } = setmetatable({}, { __mode = "k" }) :: any
type Shake = { trauma: number, rest: Vector2, t: number }
local shakes: { [GuiObject]: Shake } = {}
type Cascade = { handle: Scheduler.Handle, scales: { UIScale } }
local cascades: { [string]: Cascade } = {}
local rng = Random.new()

local function easeOut(u: number): number
	return 1 - (1 - u) ^ 3
end

local function backOut(u: number): number
	local s = 1.70158
	local x = u - 1
	return 1 + (s + 1) * x ^ 3 + s * x ^ 2
end

local function layer(): ScreenGui?
	local gui = layerGui
	if gui and gui.Parent then
		return gui
	end
	local player = Players.LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	local found = if playerGui then playerGui:FindFirstChild(LAYER_NAME) else nil
	return if found and found:IsA("ScreenGui") then found else nil
end

local function layerScale(gui: ScreenGui): number
	local uiScale = gui:FindFirstChildOfClass("UIScale")
	return if uiScale and uiScale.Scale > 0 then uiScale.Scale else 1
end

-- `at`'s centre in the layer's base px, or nil (an object not on screen).
local function centreOf(at: GuiObject | Vector2, gui: ScreenGui): Vector2?
	local absolute: Vector2
	if typeof(at) == "Vector2" then
		absolute = at
	else
		local object = at :: GuiObject
		if object.Parent == nil or object.AbsoluteSize.X <= 0 then
			return nil
		end
		absolute = object.AbsolutePosition + object.AbsoluteSize / 2
	end
	return (absolute - gui.AbsolutePosition) / layerScale(gui)
end

local function finish(burst: Burst)
	if burst.done then
		return
	end
	burst.done = true
	local handle = burst.handle
	if handle then
		handle:disconnect()
	end
	burst.holder:Destroy()
	local index = table.find(active, burst)
	if index then
		table.remove(active, index)
	end
end

local function circle(name: string, px: number, color: Color3, parent: Instance): Frame
	local frame: Frame = Create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(px, px),
		Active = false,
		Parent = parent,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
	return frame
end

-- A four-point star: two tapered pills crossed and a bright centre, in a holder scaled by its UIScale.
local function sparkle(color: Color3, parent: Instance): (Frame, UIScale)
	local holder: Frame = Create("Frame", {
		Name = "Sparkle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(SPARKLE_PX, SPARKLE_PX),
		Active = false,
		Parent = parent,
	})
	for _, vertical in { false, true } do
		local pill: Frame = Create("Frame", {
			Name = if vertical then "V" else "H",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = if vertical then UDim2.fromScale(0.24, 1) else UDim2.fromScale(1, 0.24),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = holder,
		})
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = pill })
		Create("UIGradient", {
			Rotation = if vertical then 90 else 0,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = pill,
		})
	end
	local dot = circle("Core", math.floor(SPARKLE_PX * 0.3), WHITE, holder)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	local scale: UIScale = Create("UIScale", { Scale = 0, Parent = holder })
	return holder, scale
end

-- Public: pure ---------------------------------------------------------------------------------------------------------

-- The piece counts of a tier: the tier's own, or (fewer effects) about half, without droplets and confetti below
-- "large". An unknown tier counts nothing.
function UiFx.counts(tier: string, fewer: boolean): TierSpec
	local spec = TIERS[tier]
	if spec == nil then
		return { radius = 0, seconds = 0, rings = 0, rays = 0, sparkles = 0, confetti = 0, droplets = 0 }
	end
	if not fewer then
		return spec
	end
	local big = tier == "large" or tier == "huge"
	return {
		radius = spec.radius,
		seconds = spec.seconds,
		rings = 1,
		rays = math.ceil(spec.rays / 2),
		sparkles = math.ceil(spec.sparkles / 2),
		confetti = if big then math.ceil(spec.confetti / 2) else 0,
		droplets = if big then math.ceil(spec.droplets / 2) else 0,
	}
end

-- Ray i of n reaching `length` base px from the centre, the burst turned `spinDeg`: its centre (relative to the burst's
-- centre) and its rotation in degrees (a ray is a tall frame; at 0° it points up).
function UiFx.rayRect(i: number, n: number, length: number, spinDeg: number): (Vector2, number)
	local deg = (i - 1) * 360 / math.max(1, n) + spinDeg
	local rad = math.rad(deg)
	return Vector2.new(math.sin(rad) * length / 2, -math.cos(rad) * length / 2), deg
end

-- A sparkle `u` (0..1) into its life: where it is (travelling `reach` px along `angle`, easing out) and its scale
-- (0 at both ends, SPARKLE_PEAK in the middle).
function UiFx.sparkleAt(angle: number, reach: number, u: number): (Vector2, number)
	local k = math.clamp(u, 0, 1)
	local d = reach * easeOut(k)
	return Vector2.new(math.cos(angle) * d, math.sin(angle) * d), SPARKLE_PEAK * math.sin(math.pi * k) ^ 0.6
end

-- A falling piece `t` seconds after launch along `angle` at `speed` px/s with LAUNCH_UP more upwards: where it is.
function UiFx.fallAt(angle: number, speed: number, t: number): Vector2
	local vx = math.cos(angle) * speed
	local vy = math.sin(angle) * speed - LAUNCH_UP
	return Vector2.new(vx * t, vy * t + 0.5 * GRAVITY * t * t)
end

-- Public ---------------------------------------------------------------------------------------------------------------

function UiFx.setLayer(gui: ScreenGui?)
	layerGui = gui
end

function UiFx.activeCount(): number
	return #active
end

function UiFx.burst(at: GuiObject | Vector2, tier: Tier, color: Color3?, opts: Options?): boolean
	local o: Options = opts or {}
	local gui = layer()
	if gui == nil or TIERS[tier] == nil then
		return false
	end
	local centre = centreOf(at, gui)
	if centre == nil then
		return false
	end
	while #active >= MAX_ACTIVE do
		finish(active[1])
	end
	local reduced = Tweens.reducedMotion()
	local spec = UiFx.counts(tier, UiPrefs.get("fewerEffects"))
	local radius = o.radius or spec.radius
	local life = spec.seconds
	local main = if o.neutral then WHITE else (color or GOLD)
	local palette: { Color3 } = if o.neutral
		then NEUTRAL_COLORS
		else { main, main:Lerp(WHITE, 0.45), WHITE, GOLD }

	local holder: Frame = Create("Frame", {
		Name = "SD_Burst",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(centre.X, centre.Y),
		Size = UDim2.fromOffset(0, 0),
		Active = false,
		ZIndex = HOLDER_Z,
	})
	local burst: Burst = { holder = holder, handle = nil, done = false }

	local glow = circle("Glow", radius * GLOW_FROM * 2, main, holder)
	glow.BackgroundTransparency = GLOW_TRANSPARENCY
	local rings: { { frame: Frame, stroke: UIStroke, delay: number } } = {}
	local pieces: { Piece } = {}
	if not reduced then
		for i = 1, spec.rings do
			local ring = circle("Ring", radius * RING_FROM * 2, main, holder)
			ring.BackgroundTransparency = 1
			local stroke: UIStroke = Create("UIStroke", {
				Color = if i == 1 then WHITE else main,
				Thickness = RING_PX,
				Parent = ring,
			})
			table.insert(rings, { frame = ring, stroke = stroke, delay = (i - 1) * RING_DELAY })
		end
		for i = 1, spec.rays do
			local ray: Frame = Create("Frame", {
				Name = "Ray",
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = if i % 2 == 0 then main:Lerp(WHITE, 0.35) else main,
				BackgroundTransparency = RAY_TRANSPARENCY,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(RAY_WIDTH, 0),
				Active = false,
				Parent = holder,
			})
			Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ray })
			Create("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(1, 0),
				}),
				Parent = ray,
			})
			table.insert(pieces, { kind = "ray", frame = ray, angle = 0, reach = 0, spin = 0, delay = 0 })
		end
		for i = 1, spec.sparkles do
			local frame, scale = sparkle(palette[(i - 1) % #palette + 1], holder)
			local angle = (i - 1) * 2 * math.pi / math.max(1, spec.sparkles) + rng:NextNumber(-0.3, 0.3)
			table.insert(pieces, {
				kind = "sparkle",
				frame = frame,
				scale = scale,
				angle = angle,
				reach = radius * rng:NextNumber(SPARKLE_MIN, SPARKLE_MAX),
				spin = rng:NextNumber(-180, 180),
				delay = rng:NextNumber(0, 0.08),
			})
		end
		for i = 1, spec.confetti + spec.droplets do
			local droplet = i > spec.confetti
			local color = palette[(i - 1) % #palette + 1]
			local frame: Frame
			local shine: Frame? = nil
			if droplet then
				frame = circle("Droplet", DROPLET_PX, color, holder)
				local highlight = circle("Shine", math.floor(DROPLET_PX * 0.35), WHITE, frame)
				highlight.Position = UDim2.fromScale(0.35, 0.35)
				highlight.BackgroundTransparency = 0.25
				shine = highlight
			else
				frame = Create("Frame", {
					Name = "Confetti",
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(CONFETTI_W, CONFETTI_H),
					Active = false,
					Parent = holder,
				})
				Create("UICorner", { CornerRadius = UDim.new(0, 2), Parent = frame })
			end
			local outline = Theme.stroke(Theme.Colors.inkUI, 1.5, frame)
			table.insert(pieces, {
				kind = if droplet then "droplet" else "confetti",
				frame = frame,
				stroke = outline,
				shine = shine,
				angle = rng:NextNumber(-math.pi, 0), -- upwards half
				reach = radius * rng:NextNumber(1.2, 2.4), -- the launch speed (px/s)
				spin = rng:NextNumber(-360, 360),
				delay = rng:NextNumber(0, 0.06),
			})
		end
	end
	holder.Parent = gui
	table.insert(active, burst)

	local elapsed = 0
	local function step(dt: number): boolean
		if burst.done then
			return false
		end
		elapsed += dt
		if elapsed >= life or holder.Parent == nil then
			finish(burst)
			return false
		end
		local u = elapsed / life
		local glowSize = radius * 2 * (if reduced then GLOW_FROM else GLOW_FROM + (GLOW_TO - GLOW_FROM) * easeOut(u))
		glow.Size = UDim2.fromOffset(glowSize, glowSize)
		glow.BackgroundTransparency = GLOW_TRANSPARENCY + (1 - GLOW_TRANSPARENCY) * u
		for _, ring in rings do
			local ru = math.clamp((elapsed - ring.delay) / (life * 0.7), 0, 1)
			local d = radius * 2 * (RING_FROM + (RING_TO - RING_FROM) * easeOut(ru))
			ring.frame.Size = UDim2.fromOffset(d, d)
			ring.stroke.Thickness = 1 + (RING_PX - 1) * (1 - ru)
			ring.stroke.Transparency = if elapsed < ring.delay then 1 else ru ^ 1.4
		end
		local spin = RAY_SPIN_DEG * u
		local rayCount = 0
		for _, piece in pieces do
			if piece.kind == "ray" then
				rayCount += 1
			end
		end
		local rayIndex = 0
		for _, piece in pieces do
			local kind = piece.kind
			if kind == "ray" then
				rayIndex += 1
				local length = radius * RAY_REACH * math.max(0, backOut(math.clamp(u / RAY_GROW, 0, 1)))
				local centreOffset, deg = UiFx.rayRect(rayIndex, rayCount, length, spin)
				local frame = piece.frame
				frame.Size = UDim2.fromOffset(RAY_WIDTH, length)
				frame.Position = UDim2.fromOffset(centreOffset.X, centreOffset.Y)
				frame.Rotation = deg
				local fade = if u < RAY_FADE_FROM then 0 else (u - RAY_FADE_FROM) / (1 - RAY_FADE_FROM)
				frame.BackgroundTransparency = RAY_TRANSPARENCY + (1 - RAY_TRANSPARENCY) * fade
			else
				local t = elapsed - piece.delay
				local frame = piece.frame
				if t <= 0 then
					frame.Visible = false
				elseif kind == "sparkle" then
					frame.Visible = true
					local at, size = UiFx.sparkleAt(piece.angle, piece.reach, t / (life - piece.delay))
					frame.Position = UDim2.fromOffset(at.X, at.Y)
					frame.Rotation = piece.spin * t
					local scale = piece.scale
					if scale then
						scale.Scale = size
					end
				else
					frame.Visible = true
					local at = UiFx.fallAt(piece.angle, piece.reach, t)
					frame.Position = UDim2.fromOffset(at.X, at.Y)
					frame.Rotation = piece.spin * t
					local fu = t / (life - piece.delay)
					local fade = if fu < FALL_FADE_FROM
						then 0
						else math.clamp((fu - FALL_FADE_FROM) / (1 - FALL_FADE_FROM), 0, 1)
					frame.BackgroundTransparency = fade
					local outline = piece.stroke
					if outline then
						outline.Transparency = fade
					end
					local highlight = piece.shine
					if highlight then
						highlight.BackgroundTransparency = 0.25 + 0.75 * fade
					end
				end
			end
		end
		return true
	end
	step(0)
	burst.handle = Scheduler.add(step, "render")
	return true
end

function UiFx.punch(object: GuiObject, peak: number?, ms: number?)
	if Tweens.reducedMotion() or object.Parent == nil then
		return
	end
	local existing = object:FindFirstChildOfClass("UIScale")
	local scale: UIScale = if existing then existing else Create("UIScale", { Name = PUNCH_NAME, Parent = object })
	local previous = punches[scale]
	if previous then
		previous:Cancel()
	end
	local total = ms or PUNCH_MS
	local up = Tweens.play(scale, total * 0.35, { Scale = peak or PUNCH_PEAK }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	punches[scale] = up
	up.Completed:Once(function(state: Enum.PlaybackState)
		if state ~= Enum.PlaybackState.Completed or punches[scale] ~= up then
			return
		end
		punches[scale] =
			Tweens.play(scale, total * 0.65, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
end

-- The UIScale a cascade or a punch drives on `object` (its own, or SD_Punch made for it).
local function scaleOf(object: GuiObject): UIScale
	local existing = object:FindFirstChildOfClass("UIScale")
	return if existing then existing else Create("UIScale", { Name = PUNCH_NAME, Parent = object })
end

local function stopCascade(key: string)
	local current = cascades[key]
	if current == nil then
		return
	end
	cascades[key] = nil
	current.handle:disconnect()
	for _, scale in current.scales do
		scale.Scale = 1
	end
end

function UiFx.cascade(key: string, objects: { GuiObject }, opts: CascadeOptions?)
	stopCascade(key)
	if Tweens.reducedMotion() or #objects == 0 then
		return
	end
	local spec = Config.UI.motion.cardIn
	local o: CascadeOptions = opts or {}
	local from = o.from or spec.scaleFrom
	local seconds = (o.ms or spec.ms) / 1000
	local stagger = (o.staggerMs or spec.staggerMs) / 1000
	local maxStagger = (o.maxStaggerMs or spec.maxStaggerMs) / 1000
	local scales: { UIScale } = {}
	local delays: { number } = {}
	for index, object in objects do
		local scale = scaleOf(object)
		scale.Scale = from
		table.insert(scales, scale)
		table.insert(delays, math.min((index - 1) * stagger, maxStagger))
	end
	local elapsed = 0
	local handle = Scheduler.add(function(dt: number): boolean
		elapsed += dt
		local running = false
		for index, scale in scales do
			local u = math.clamp((elapsed - delays[index]) / seconds, 0, 1)
			scale.Scale = from + (1 - from) * backOut(u)
			running = running or u < 1
		end
		if not running then
			for _, scale in scales do
				scale.Scale = 1
			end
			cascades[key] = nil
			return false
		end
		return true
	end, "render")
	cascades[key] = { handle = handle, scales = scales }
end

function UiFx.shake(object: GuiObject, trauma: number)
	if Tweens.reducedMotion() or object.Parent == nil then
		return
	end
	local current = shakes[object]
	if current then
		current.trauma = math.min(1, current.trauma + trauma)
		return
	end
	local shake: Shake = { trauma = math.clamp(trauma, 0, 1), rest = object.AnchorPoint, t = 0 }
	shakes[object] = shake
	Scheduler.add(function(dt: number): boolean
		shake.t += dt
		shake.trauma = math.max(0, shake.trauma - SHAKE_DECAY * dt)
		local size = object.AbsoluteSize
		if object.Parent == nil or shake.trauma <= 0 or size.X <= 0 or size.Y <= 0 then
			object.AnchorPoint = shake.rest
			shakes[object] = nil
			return false
		end
		local k = shake.trauma * shake.trauma
		local dx = SHAKE_PX * k * math.sin(shake.t * 47)
		local dy = SHAKE_PX * 0.7 * k * math.sin(shake.t * 61 + 1.3)
		object.AnchorPoint = Vector2.new(shake.rest.X + dx / size.X, shake.rest.Y + dy / size.Y)
		return true
	end, "render")
end

return UiFx
