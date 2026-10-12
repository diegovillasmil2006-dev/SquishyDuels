--!strict
-- ThrowCharge (shared, pure): the charge throw's numbers (feature 1, 2026-10-11; Config.Combat.Charge,
-- Config.Vfx.Charge; design: the combat-effects page "Squishy Combat FP v2.html", html:<line>). No instances, no clock:
-- the server (Logic/ThrowRules) and the clients (ThrowController, ViewmodelController, ProjectileRenderer, the
-- reticles) read the same formulas.
--
--   ThrowCharge.level(startAt, now, seconds?) -> number   c = clamp((now - startAt) / seconds, 0, 1) (design: html:499)
--   ThrowCharge.measure(chargeStartAt?, pressAt, readyPressAt, seconds?) -> number   the server's c for a ThrowRequest
--       pressed (let go) at pressAt: counted from the later of the charge start and readyPressAt, the moment the throw
--       was ready (a press during the cooldown charges only once the throw is ready, as the client does); 0 without a
--       start or with a time that is not finite
--   ThrowCharge.speedFactor(c, gain?) -> number   the throw's speed × this: 1 + speedGain·c (design: html:330)
--   ThrowCharge.trailFactors(power) -> (width, lifetime)   a trail's width and lifetime × these (design: html:243)
--   ThrowCharge.release(power) -> Release         the release's scales and extras (design: html:333-339)
--   ThrowCharge.fovOffset(c) -> number            the world FOV offset while charging: -fovNarrowDeg·c (design: html:463)
--   ThrowCharge.walkSpeed(base) -> number         the walk speed while charging: base × walkFactor (design: html:437)
--   ThrowCharge.speckRate(power, hasEmitter) -> number   the in-flight specks a second (design: html:605; 0 for a
--       projectile whose rarity trail has its own emitter), held to Effects.projectileParticles live
--   ThrowCharge.tone(c, elapsed) -> (pitch, volume)   the charge tone's PlaybackSpeed and volume (Config.Audio.charge;
--       design: squishy-lib-v2.js:384): pitch and volume rise with c, a tremolo at full; the crush drives it with its e
--   ThrowCharge.ease(u) -> number                 the design's ease, quadratic in-out (design: html:115)
--   ThrowCharge.isFull(c) -> boolean
-- `power` is the server's c of a throw (ThrowStarted.power; nil or not finite = 0).

local Config = require(script.Parent.Config)

-- Types

-- What a release looks like at power p (design: html:333-339).
export type Release = {
	fovKick: number, -- × the first-person release FOV kick
	kick: number, -- × the first-person release kick
	puffs: number, -- × the release puffs
	ring: number, -- × the release ring's size
	whiteRing: boolean, -- a second, white ring
	powerRing: boolean, -- a ring across the throw's path
	powerRingStuds: number, -- its diameter (design: html:338, radius 0.5 + 0.4c m)
	hitStop: number?, -- the thrower's hit-stop (seconds) at a full charge, else nil
}

-- Constants

local CHARGE = Config.Combat.Charge
local VFX = Config.Vfx.Charge
local TONE = Config.Audio.charge
local PARTICLES = Config.Vfx.Effects.projectileParticles
local FULL = 1 - 1e-9 -- c at or above this is full (float slack)

-- Module table

local ThrowCharge = {}

-- Private

local function finite(x: unknown): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function clamp01(x: number): number
	return if x ~= x then 0 else math.clamp(x, 0, 1)
end

local function powerOf(power: number?): number
	return if finite(power) then clamp01(power :: number) else 0
end

-- Public

function ThrowCharge.level(startAt: number, now: number, seconds: number?): number
	local span = seconds or CHARGE.seconds
	if not finite(startAt) or not finite(now) or not (span > 0) then
		return 0
	end
	return clamp01((now - startAt) / span) -- design: html:499
end

function ThrowCharge.measure(chargeStartAt: number?, pressAt: number, readyPressAt: number, seconds: number?): number
	if chargeStartAt == nil or not finite(chargeStartAt) or not finite(pressAt) then
		return 0
	end
	local from = chargeStartAt :: number
	if finite(readyPressAt) and readyPressAt > from then
		from = readyPressAt
	end
	return ThrowCharge.level(from, pressAt, seconds)
end

function ThrowCharge.speedFactor(c: number, gain: number?): number
	return 1 + (gain or CHARGE.speedGain) * clamp01(c) -- design: html:330
end

function ThrowCharge.trailFactors(power: number?): (number, number)
	local p = powerOf(power)
	return 1 + VFX.trailWidthGain * p, 1 + VFX.trailLifeGain * p -- design: html:243
end

function ThrowCharge.release(power: number?): Release
	local p = powerOf(power)
	return {
		fovKick = 1 + VFX.fovKickGain * p, -- design: html:333
		kick = 1 + VFX.kickGain * p, -- design: html:333
		puffs = 1 + VFX.releasePuffGain * p, -- design: html:336
		ring = 1 + VFX.releaseRingGain * p, -- design: html:335
		whiteRing = p > VFX.whiteRingFrom, -- design: html:335
		powerRing = p > VFX.powerRingFrom, -- design: html:338
		powerRingStuds = VFX.powerRingStuds * (1 - VFX.powerRingGain * (1 - p)), -- design: html:338
		hitStop = if p >= FULL then CHARGE.hitStopSeconds else nil, -- design: html:339
	}
end

function ThrowCharge.fovOffset(c: number): number
	return -CHARGE.fovNarrowDeg * clamp01(c) -- design: html:463
end

function ThrowCharge.walkSpeed(base: number): number
	return base * CHARGE.walkFactor -- design: html:437
end

function ThrowCharge.speckRate(power: number?, hasEmitter: boolean): number
	if hasEmitter then
		return 0
	end
	local rate = VFX.speckRate * powerOf(power) -- design: html:605
	return math.min(rate, PARTICLES / VFX.speckLifetimeMax)
end

function ThrowCharge.tone(c: number, elapsed: number): (number, number)
	local level = clamp01(c)
	local pitch = TONE.pitchFrom + (TONE.pitchTo - TONE.pitchFrom) * level -- design: squishy-lib-v2.js:384
	local volume = TONE.volumeFrom + (1 - TONE.volumeFrom) * level
	if level >= FULL then
		volume *= 1 + TONE.tremolo * math.sin(TONE.tremoloRate * elapsed) -- design: squishy-lib-v2.js:384
	end
	return pitch, volume
end

function ThrowCharge.ease(u: number): number
	local t = clamp01(u)
	if t < 0.5 then
		return 2 * t * t -- design: html:115
	end
	return 1 - (-2 * t + 2) ^ 2 / 2
end

function ThrowCharge.isFull(c: number): boolean
	return c >= FULL
end

return table.freeze(ThrowCharge)
