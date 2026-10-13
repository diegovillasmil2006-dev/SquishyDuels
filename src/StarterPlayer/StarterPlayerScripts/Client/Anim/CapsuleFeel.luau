--!strict
-- CapsuleFeel (client only, pure). Lobby bases spec 2026-10-11 §5.3, build plan Phase 5: the timing and the curves of
-- the capsule feel that Controllers/CapsuleController plays on the island's capsules. Every number is
-- Config.UI.Capsule's (the brick flight Config.Vfx.Confetti's); every function is of the time since the event, never
-- added up frame by frame, so a capsule that was culled comes back where the clock says.
--   squeeze(t, contact?)  -> (press 0..1, height): the press comes down over pressDownMs (Quad In), holds pressHoldMs and
--                            rises over pressUpMs (smoothstep); the squishy keeps its height until the press reaches
--                            `contact` (the share of the press travel where it meets the squishy's top), squashes to
--                            squashHeight at the full press, then springs back from the end of the hold
--   spring(t, depth)      -> a damped wobble from 1 - depth at rest (zero speed): 1 - depth·e^(-kt)·(cos ωt + (k/ω) sin ωt),
--                            whose extremes fall exactly at ωt = π, 2π, ... Reading: ω = π / pressUp (WOBBLE_HZ) and
--                            k = ln(depth / overshoot) / pressUp put the first peak at springHeight just as the press is
--                            back up (spec: "springs back to 112% height and wobbles"); 1.56 Hz, under the 3 Hz limit
--   width(height)         -> the x and z scale: squashWidth at squashHeight, 1 at 1, linear (thinner when stretched)
--   upgrade(t, evolve)    -> (height, turn): a stretch of upgradeStretch (evolveStretch for a new tier) springing back
--                            while the squishy turns upgradeTurns (evolveTurns) whole turns over spinMs (Quad Out)
--   duration(kind)        -> seconds until "squeeze", "tap", "upgrade" or "evolve" stays within REST of rest; 0 for
--                            anything else
--   brick(velocity, t)    -> (offset, transparency, done): a confetti brick's flight under Confetti.gravity, solid until
--                            its last Confetti.fadeSeconds, gone after Confetti.lifetime
--   pop(t, reduced)       -> (rise, transparency, done): the owner's "+N" rises popRiseStuds over popMs (Quad Out) and
--                            fades over its last popFadeShare; under ReducedMotion it never rises and fades over the last
--                            Config.UI.motion.reducedMotionMaxFadeMs

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Constants

local C = Config.UI.Capsule
local CONFETTI = Config.Vfx.Confetti
local DOWN = C.pressDownMs / 1000
local HOLD = C.pressHoldMs / 1000
local UP = C.pressUpMs / 1000
local SQUASH = 1 - C.squashHeight -- the squishy's depth at the press's bottom
local OMEGA = math.pi / UP
local DAMPING = math.log(SQUASH / (C.springHeight - 1)) / UP
local ENVELOPE = math.sqrt(1 + (DAMPING / OMEGA) ^ 2) -- the spring's largest swing for a depth of 1
local REST = 0.005 -- reading: a motion this close to rest is at rest
local SPIN = C.spinMs / 1000
local POP = C.popMs / 1000
local REDUCED_FADE = Config.UI.motion.reducedMotionMaxFadeMs / 1000

-- Module table

local CapsuleFeel = {}

CapsuleFeel.WOBBLE_HZ = OMEGA / (2 * math.pi)

-- Private

local function clamp01(u: number): number
	return if u ~= u then 0 else math.clamp(u, 0, 1)
end

-- Seconds until a spring of `depth` stays within REST of 1.
local function settle(depth: number): number
	local swing = math.abs(depth) * ENVELOPE
	return if swing > REST then math.log(swing / REST) / DAMPING else 0
end

-- Public

function CapsuleFeel.spring(t: number, depth: number): number
	local time = math.max(0, t)
	local wave = math.cos(OMEGA * time) + DAMPING / OMEGA * math.sin(OMEGA * time)
	return 1 - depth * math.exp(-DAMPING * time) * wave
end

function CapsuleFeel.squeeze(t: number, contact: number?): (number, number)
	local touch = clamp01(contact or 0)
	if t <= 0 then
		return 0, 1
	elseif t < DOWN + HOLD then
		local press = if t < DOWN then (t / DOWN) ^ 2 else 1
		local share = if touch < 1 then math.max(0, (press - touch) / (1 - touch)) else 0
		return press, 1 - SQUASH * share
	end
	local after = t - DOWN - HOLD
	local u = clamp01(after / UP)
	return 1 - u * u * (3 - 2 * u), CapsuleFeel.spring(after, if touch < 1 then SQUASH else 0)
end

function CapsuleFeel.width(height: number): number
	return 1 + (1 - height) * (C.squashWidth - 1) / SQUASH
end

function CapsuleFeel.upgrade(t: number, evolve: boolean): (number, number)
	local stretch = if evolve then C.evolveStretch else C.upgradeStretch
	local turns = if evolve then C.evolveTurns else C.upgradeTurns
	local u = clamp01(t / SPIN)
	return CapsuleFeel.spring(t, -stretch), 2 * math.pi * turns * (1 - (1 - u) ^ 2)
end

function CapsuleFeel.duration(kind: string): number
	if kind == "squeeze" then
		return DOWN + HOLD + settle(SQUASH)
	elseif kind == "tap" then
		return settle(C.tapSquish)
	elseif kind == "upgrade" then
		return math.max(SPIN, settle(C.upgradeStretch))
	elseif kind == "evolve" then
		return math.max(SPIN, settle(C.evolveStretch))
	end
	return 0
end

function CapsuleFeel.brick(velocity: Vector3, t: number): (Vector3, number, boolean)
	local time = math.max(0, t)
	local offset = velocity * time + Vector3.new(0, -0.5 * CONFETTI.gravity * time * time, 0)
	if time >= CONFETTI.lifetime then
		return offset, 1, true
	end
	return offset, clamp01((time - (CONFETTI.lifetime - CONFETTI.fadeSeconds)) / CONFETTI.fadeSeconds), false
end

function CapsuleFeel.pop(t: number, reduced: boolean): (number, number, boolean)
	if t >= POP then
		return if reduced then 0 else C.popRiseStuds, 1, true
	elseif reduced then
		return 0, clamp01((t - (POP - REDUCED_FADE)) / REDUCED_FADE), false
	end
	local u = clamp01(t / POP)
	return C.popRiseStuds * (1 - (1 - u) ^ 2), clamp01((u - (1 - C.popFadeShare)) / C.popFadeShare), false
end

return table.freeze(CapsuleFeel)
