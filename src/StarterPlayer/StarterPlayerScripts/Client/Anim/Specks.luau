--!strict
-- Specks (client only, pure): small particles as plain numbers, the design's FX particles (sd/fx.js:92-143) for the
-- first-person Inspect showcases (final polish 2026-10-11). ParticleEmitters draw nothing in a ViewportFrame, so the
-- overlay shows each speck as a small part (ViewmodelController); this module only spawns and moves them. Units are
-- the overlay's du (camera space: -Z forward, +Y up); no instances, connections or clock reads.
--
-- API
--   Specks.spawn(spec, at, random, multiplier, colours) -> { Speck }   one design call: "burst" (fx.js:97-106) or
--       "emit" (fx.js:92-96 called `count` times, as fp.js:182, 191 do), at `at` + (0, spec.offsetY, 0);
--       round(count × multiplier) specks (multiplier: Config.Vfx.reducedParticleMultiplier under ReducedMotion, else
--       1); `colours` are the toy's own (its accent and white) for a spec without its own colours
--   Specks.step(speck, dt) -> boolean   one frame (fx.js:131-137); false once its age reached its life (gone)
--   Specks.envelope(t) -> number        the size curve over its life share t (fx.js:139)
--   Specks.radius(speck) -> number      its radius now (du): the design's unit sphere × size × the envelope
--   Specks.rotation(speck) -> CFrame    its spin now (a random axis at `spin` rad/s from a random start, fx.js:94-95)

-- Types

export type Shape = "puff" | "cube" | "petal" | "heart" | "spark" | "sphere" | "glowdrop"

-- One design call. "puff" is the toy's own speck shape (the design's per-toy trail shape, toys.js:412-425; the game
-- has none: a round speck in the toy's colours).
export type Spec = {
	kind: "burst" | "emit",
	count: number,
	shape: Shape,
	colours: { Color3 }?, -- nil: the toy's own
	speed: number?, -- burst: the speed before its random share (fx.js:104)
	normal: Vector3?, -- burst: folded into this half and biased toward it (fx.js:102)
	velMin: Vector3?, -- emit: each axis random between these (fp.js:182, 191)
	velMax: Vector3?,
	size: number,
	life: number,
	gravity: number?, -- du/s² on Y; nil = the design's -6 (fx.js:95)
	drag: number?, -- per second; nil = the design's 1.6 (fx.js:95)
	offsetY: number?, -- the point above the toy's (toyWorldPos(off), fp.js:168)
}

export type Speck = {
	shape: Shape,
	colour: Color3,
	glow: boolean, -- the design's unlit pools (spark, glowdrop; fx.js:79)
	p: Vector3,
	v: Vector3,
	g: number,
	drag: number,
	life: number,
	age: number,
	size: number,
	axis: Vector3,
	spin: number,
	angle: number,
}

-- Constants

local DEFAULT_GRAVITY = -6 -- design: fx.js:95
local DEFAULT_DRAG = 1.6 -- design: fx.js:95
local DEFAULT_SPIN = 6 -- design: fx.js:95
local DEFAULT_BIAS = 0.6 -- design: fx.js:102
local START_ANGLE_MAX = 6 -- design: fx.js:95 (Math.random() * 6)
local SPEED_MIN, SPEED_SPAN = 0.45, 0.75 -- design: fx.js:104
local SIZE_MIN, SIZE_SPAN = 0.6, 0.8 -- design: fx.js:105
local LIFE_MIN, LIFE_SPAN = 0.7, 0.6 -- design: fx.js:105
local POP_UNTIL, POP_PEAK, POP_PHASE = 0.12, 1.25, 0.62 -- design: fx.js:139
local FADE_FROM, FADE_SPAN, FADE_POWER = 0.6, 0.4, 1.6 -- design: fx.js:139
local GLOW: { [string]: boolean } = { spark = true, glowdrop = true } -- design: fx.js:79
local MIN_LENGTH = 1e-6

-- Module table

local Specks = {}

-- Private

-- The design's random direction: a random point in the unit cube, normalised (fx.js:94, 101).
local function randomDirection(random: Random): Vector3
	for _ = 1, 8 do
		local d = Vector3.new(random:NextNumber() - 0.5, random:NextNumber() - 0.5, random:NextNumber() - 0.5)
		if d.Magnitude > MIN_LENGTH then
			return d.Unit
		end
	end
	return Vector3.yAxis
end

local function between(random: Random, lo: number, hi: number): number
	return lo + random:NextNumber() * (hi - lo)
end

local function newSpeck(
	spec: Spec,
	random: Random,
	colour: Color3,
	p: Vector3,
	v: Vector3,
	size: number,
	life: number
): Speck
	return {
		shape = spec.shape,
		colour = colour,
		glow = GLOW[spec.shape] == true,
		p = p,
		v = v,
		g = if spec.gravity ~= nil then spec.gravity else DEFAULT_GRAVITY,
		drag = if spec.drag ~= nil then spec.drag else DEFAULT_DRAG,
		life = life,
		age = 0,
		size = size,
		axis = randomDirection(random),
		spin = DEFAULT_SPIN,
		angle = random:NextNumber() * START_ANGLE_MAX,
	}
end

-- Public

function Specks.spawn(spec: Spec, at: Vector3, random: Random, multiplier: number, colours: { Color3 }): { Speck }
	local list: { Speck } = {}
	local count = math.floor(spec.count * multiplier + 0.5) -- design: fx.js:98 (Math.round)
	local palette = spec.colours or colours
	local point = at + Vector3.new(0, spec.offsetY or 0, 0)
	for i = 1, count do
		local colour = palette[(i - 1) % #palette + 1]
		if spec.kind == "emit" then
			local lo, hi = spec.velMin or Vector3.zero, spec.velMax or Vector3.zero
			local v = Vector3.new(between(random, lo.X, hi.X), between(random, lo.Y, hi.Y), between(random, lo.Z, hi.Z))
			table.insert(list, newSpeck(spec, random, colour, point, v, spec.size, spec.life))
		else
			local d = randomDirection(random)
			local normal = spec.normal
			if normal then
				if d:Dot(normal) < 0 then
					d -= normal * (2 * d:Dot(normal)) -- design: fx.js:102 (reflect)
				end
				local biased = d + normal * DEFAULT_BIAS
				d = if biased.Magnitude > MIN_LENGTH then biased.Unit else normal
			end
			local speed = (spec.speed or 0) * (SPEED_MIN + random:NextNumber() * SPEED_SPAN)
			local size = spec.size * (SIZE_MIN + random:NextNumber() * SIZE_SPAN)
			local life = spec.life * (LIFE_MIN + random:NextNumber() * LIFE_SPAN)
			table.insert(list, newSpeck(spec, random, colour, point, d * speed, size, life))
		end
	end
	return list
end

function Specks.step(speck: Speck, dt: number): boolean
	speck.age += dt
	if speck.age >= speck.life then
		return false -- design: fx.js:132
	end
	local v = Vector3.new(speck.v.X, speck.v.Y + speck.g * dt, speck.v.Z) * math.exp(-speck.drag * dt)
	speck.v = v
	speck.p += v * dt -- design: fx.js:135
	speck.angle += speck.spin * dt -- design: fx.js:137
	return true
end

function Specks.envelope(t: number): number
	if t < POP_UNTIL then
		return POP_PEAK * math.sin((t / POP_UNTIL) * math.pi * POP_PHASE)
	elseif t > FADE_FROM then
		return 1 - ((math.min(t, 1) - FADE_FROM) / FADE_SPAN) ^ FADE_POWER
	end
	return 1
end

function Specks.radius(speck: Speck): number
	return speck.size * Specks.envelope(speck.age / speck.life)
end

function Specks.rotation(speck: Speck): CFrame
	return CFrame.fromAxisAngle(speck.axis, speck.angle)
end

return Specks
