--!strict
-- ChargePoses (client only, pure): the charge throw's, the catch's and the crush's poses on the first-person overlay
-- (feature 1, 2026-10-11; Config.FirstPerson.v2 / charge / catch / crush; design: the combat-effects page "Squishy
-- Combat FP v2.html", html:<line>). Plain numbers in the overlay's du (camera space: -Z forward, +Y up); no instances,
-- connections or clock reads. ViewmodelController puts these targets on its springs and draws the effects.
--
-- The design page has its own viewmodel (FOV 56°, its hold POSE). Its moves are taken as offsets from its own hold
-- and put on ours (map: × depthScale in depth, × depthScale·fovScale across, so they cover the same share of the
-- screen through our 70° camera); its rolls as changes from its hold's rolls; its sizes in toy radii (size).
--
-- API
--   ChargePoses.map(offset) -> Vector3        a design offset (its metres) in our du
--   ChargePoses.size(metres) -> number        a design size in held-toy radii (÷ v2.toyRadius)
--   ChargePoses.charge(c, t, frame, random?, reduced) -> ChargePose   design: html:498-517
--   ChargePoses.catch(t, frame) -> HandsPose  the open hands, t seconds after the press (design: html:528-533)
--   ChargePoses.crush(t, frame, random?, reduced) -> CrushPose   t seconds after the catch (design: html:535-553)
--   ChargePoses.crushShape(t, reduced) -> (scale, shake)   the crushed toy's own scale and its shake (in its radii) for
--       the world copy every other viewer sees in the catcher's hands (ProjectileRenderer; the design has no third
--       person: build choice 2026-10-11, NOT IN DESIGN, the overlay's numbers on the world toy)
-- `frame` is this frame's hold: the toy's hold point, the hands at its sides there and the empty hands' rest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ThrowCharge = require(ReplicatedStorage.Shared.ThrowCharge)

-- Types

-- Our hold this frame (du).
export type Frame = {
	hold: Vector3, -- the toy's hold point
	sideL: Vector3, -- the hands at the toy's sides at the hold (ViewmodelMath.sides)
	sideR: Vector3,
	restL: Vector3, -- the empty hands
	restR: Vector3,
}

export type HandsPose = {
	toy: Vector3, -- the held toy's target
	left: Vector3,
	right: Vector3,
	lRoll: number,
	rRoll: number,
}

export type ChargePose = {
	toy: Vector3,
	left: Vector3,
	right: Vector3,
	lRoll: number,
	rRoll: number,
	scale: Vector3, -- the toy's scale keys
	squish: boolean, -- the squish face (full)
	glow: number, -- the glow's opacity (0 = none)
	glowScale: number, -- the glow ball's radius in toy radii
	outline: boolean, -- the white shell (full)
	orbit: boolean,
	orbitScale: number,
	orbitSpin: number, -- rad/s
	shake: number, -- the camera shake value to raise to
	sparkRate: number, -- gathering sparks a second
	full: boolean,
}

export type CrushPose = {
	toy: Vector3, -- the caught toy's target (before its shake)
	shake: Vector3, -- this frame's shake on the caught toy and the hands (du)
	scale: Vector3, -- the caught toy's scale (its "manual" scale)
	face: string, -- "wow", then "squish"
	glow: number,
	glowScale: number,
	orbit: boolean,
	orbitSpin: number,
	speckRate: number,
	cameraShake: number,
	tone: number, -- the charge tone's level (e)
	press: number, -- e²: how hard the palms press (the overlay's two-palm squeeze)
	held: Vector3, -- the own held toy's target (tucked away)
}

-- Constants

local FP = Config.FirstPerson
local V2 = FP.v2
local CHARGE = FP.charge
local CATCH = FP.catch
local CRUSH = FP.crush
local ARM_ROLL = FP.arm.roll
local ACROSS = V2.depthScale * V2.fovScale
local TAU = 2 * math.pi

-- Module table

local ChargePoses = {}

-- Private

local function clamp01(x: number): number
	return if x ~= x then 0 else math.clamp(x, 0, 1)
end

-- The crush's ease e at t (design: html:538).
local function crushEase(t: number): number
	return clamp01((t - CRUSH.easeFrom) / CRUSH.easeOver)
end

-- The crushed toy's scale at t with ease e (design: html:541-542): squeezed across, grown up and along, the wobble.
local function crushScale(t: number, e: number, reduced: boolean): Vector3
	local ee = e * e
	local wob = if reduced then 0 else math.sin(t * (CRUSH.wobbleRate + CRUSH.wobbleRateGain * e)) * CRUSH.wobble * e
	return Vector3.new(
		1 - CRUSH.squeezeX * ee + wob,
		1 + CRUSH.growY * ee - CRUSH.wobbleY * wob,
		1 + CRUSH.growZ * ee - CRUSH.wobbleZ * wob
	)
end

local function jitter(random: Random?, a: number): Vector3
	if random == nil or not (a > 0) then
		return Vector3.zero
	end
	return Vector3.new(random:NextNumber(-a, a), random:NextNumber(-a, a), random:NextNumber(-a, a))
end

-- Public

function ChargePoses.map(offset: Vector3): Vector3
	return Vector3.new(offset.X * ACROSS, offset.Y * ACROSS, offset.Z * V2.depthScale)
end

function ChargePoses.size(metres: number): number
	return metres / V2.toyRadius
end

function ChargePoses.charge(c: number, t: number, frame: Frame, random: Random?, reduced: boolean): ChargePose
	local level = clamp01(c)
	local full = ThrowCharge.isFull(level)
	local ec = ThrowCharge.ease(math.min(1, level * CHARGE.easeGain)) -- design: html:499
	-- The toy toward its charged point (design: html:500); the right hand stays under it (html:501).
	local toy = frame.hold + ChargePoses.map((CHARGE.toy - V2.hold) * ec)
	local right = toy + (frame.sideR - frame.hold) + ChargePoses.map((CHARGE.handR - (V2.holdR - V2.hold)) * ec)
	-- The left hand goes away, then comes back to steady the toy (design: html:502-504).
	local away = frame.restL + ChargePoses.map(CHARGE.leftAway)
	local steady = toy + (frame.sideL - frame.hold) + ChargePoses.map(CHARGE.leftSteady - (V2.holdL - V2.hold))
	local back = clamp01((level - CHARGE.leftBackFrom) / CHARGE.leftBackOver)
	local left = if level < CHARGE.leftBackFrom
		then frame.sideL:Lerp(away, ThrowCharge.ease(math.min(1, level / CHARGE.leftAwayOver)))
		else away:Lerp(steady, ThrowCharge.ease(back))
	local lRoll = ARM_ROLL + (CHARGE.leftRollTo - V2.rollL) * back -- design: html:504
	-- The shake of a near-full charge (design: html:505).
	if level > CHARGE.jitterFrom and not reduced then
		local a = CHARGE.jitter * (if full then 1 else (level - CHARGE.jitterFrom) / (1 - CHARGE.jitterFrom))
		local j = ChargePoses.map(jitter(random, a))
		toy += j
		right += j
		left += j
	end
	-- The squash target (design: html:507) shown as the design's scale (squishy-lib-v2.js:196).
	local s = if level < CHARGE.squashKnee
		then CHARGE.squashSlope * level
		else CHARGE.squashBase + CHARGE.squashRise * (level - CHARGE.squashKnee) / (1 - CHARGE.squashKnee)
	if full and not reduced then
		s += CHARGE.squashPulse * math.sin(t * CHARGE.squashPulseRate)
	end
	local scale = Vector3.new(1 + CHARGE.squashX * s, 1 - CHARGE.squashY * s, 1 + CHARGE.squashX * s)
	-- The glow (design: html:508-509): none under glowFrom, then rising; at full a flicker and a pulse (none under
	-- ReducedMotion).
	local glow = if level < CHARGE.glowFrom
		then 0
		else math.min(CHARGE.glowMax, (level - CHARGE.glowFrom) * CHARGE.glowGain)
	local glowScale = CHARGE.glowScale
	if full and not reduced then
		local wave = math.sin(t * CHARGE.glowPulseRate)
		glow *= 1 - CHARGE.glowFlicker + CHARGE.glowFlicker * wave
		glowScale += CHARGE.glowPulse * wave
	end
	return {
		toy = toy,
		left = left,
		right = right,
		lRoll = lRoll,
		rRoll = -ARM_ROLL, -- the design's right roll does not change (html:501)
		scale = scale,
		squish = full, -- design: html:511
		glow = glow,
		glowScale = glowScale,
		outline = full, -- design: html:510
		orbit = level >= CHARGE.orbitFrom, -- design: html:510
		orbitScale = if full then 1 else CHARGE.orbitScaleFrom + (1 - CHARGE.orbitScaleFrom) * level, -- html:511
		orbitSpin = if full then CHARGE.orbitSpinFull else CHARGE.orbitSpin * level, -- design: html:510
		shake = if full then CHARGE.shake else 0, -- design: html:514
		sparkRate = if level > CHARGE.sparkFrom then CHARGE.sparkRate + CHARGE.sparkRateGain * level else 0, -- html:513
		full = full,
	}
end

function ChargePoses.catch(t: number, frame: Frame): HandsPose
	local open = clamp01(t / CATCH.openSeconds) -- design: html:529
	return {
		toy = frame.hold + ChargePoses.map(CATCH.toy - V2.hold), -- design: html:531 (tucked away)
		left = frame.restL + ChargePoses.map(CATCH.handL - V2.emptyL) * open, -- design: html:530
		right = frame.restR + ChargePoses.map(CATCH.handR - V2.emptyR) * open,
		lRoll = ARM_ROLL + (CATCH.rollL - V2.rollL), -- design: html:531
		rRoll = -ARM_ROLL + (CATCH.rollR - V2.rollR),
	}
end

function ChargePoses.crush(t: number, frame: Frame, random: Random?, reduced: boolean): CrushPose
	local e = crushEase(t) -- design: html:538
	local ee = e * e
	local shk = CRUSH.shakeBase + CRUSH.shakeGain * ee
	local flicker = if reduced then 0 else math.sin(TAU * CRUSH.glowFlickerHz * t)
	return {
		toy = frame.hold + ChargePoses.map(CRUSH.base - V2.hold), -- design: html:539
		shake = if reduced then Vector3.zero else ChargePoses.map(jitter(random, shk)),
		scale = crushScale(t, e, reduced), -- design: html:542
		face = if t < CRUSH.wowUntil then "wow" else "squish", -- design: html:543
		glow = CRUSH.glow * ee + (if e > CRUSH.glowFlickerFrom then CRUSH.glowFlicker * flicker else 0), -- html:544
		glowScale = CHARGE.glowScale + CRUSH.glowPulse * flicker * e,
		orbit = e > CRUSH.orbitFrom, -- design: html:545
		orbitSpin = CRUSH.orbitSpin + CRUSH.orbitSpinGain * e,
		speckRate = CRUSH.speckRate * e, -- design: html:550
		cameraShake = CRUSH.shake + CRUSH.shakeGainE * ee, -- design: html:551
		tone = e, -- design: html:552
		press = ee,
		held = frame.hold + ChargePoses.map(CRUSH.toy - V2.hold), -- design: html:549 (tucked away)
	}
end

function ChargePoses.crushShape(t: number, reduced: boolean): (Vector3, number)
	local e = crushEase(t) -- design: html:538
	local shk = CRUSH.shakeBase + CRUSH.shakeGain * e * e -- metres on the overlay's toy (design: html:538)
	local radius = V2.toyRadius * CRUSH.toyScale -- the caught toy's radius there (design: html:348)
	return crushScale(t, e, reduced), if reduced then 0 else shk / radius
end

return table.freeze(ChargePoses)
