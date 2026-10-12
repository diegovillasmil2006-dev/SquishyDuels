--!strict
-- KneadMath (client only; pure: no instances, connections, yields or clock reads). Spec phase2-squeeze §3.3, §3.5,
-- §3.6: the small formulas the knead screen (Controllers/KneadController) puts around Anim/SoftBody in Inspect.
--
--   KneadMath.kickPeak(v, feel) -> number
--     The design's soft jiggle kick (kick(v): jv += kickVelocity·v, squish.js:321) on the feel's jiggle spring
--     (Config.Anim.rig.feels = the design's FEELS.jig), as Anim/SquishRig:kick's amount: that spring's first-swing peak
--     after the impulse (spec §3.3). The rig shows it × the feel's gain (= FEELS.wob), as the design shows j·wob.
--   KneadMath.kneadZoom(stage, box) -> number
--     The design's knead fit (fp.js:85-91) with the Inspect stage as the free area: the zoom kz at which the toy fills
--     fitWidth of the stage's width or fitHeight of its height, seen at fitDepth du in the cameraFovDeg viewmodel
--     camera, never below 1. stage = the stage's size (px; a bad size counts as square), box = the toy's soft box.
--   KneadMath.duToStuds(maxDim, kz) -> number   studs per du at that zoom: the design's toy is toyLongestDu·kz du long
--     (K = toyLongestDu / maxDim, fp.js:100), ours maxDim studs. The flakes and the jolt are in du (fp.js:678-683).
--   KneadMath.approach(rate, dt) -> number      1 - e^(-rate·dt): the design's per-frame slerp share (fp.js:482-484)
--   KneadMath.tilt(yaw, pitch, targetYaw, targetPitch, rate, dt) -> (dYaw, dPitch)   the degrees a frame moves toward
--     the target at that share, the yaw the short way round (the orbit camera stands in for the toy's rotation)
--   KneadMath.moveAction(pulling, hit) -> "fingerMove" | "pullTo"   a pressed pointer's move: knead while it is on the
--     toy, stretch off it, and keep stretching once the body pulls (fp.js:636)
--   KneadMath.ringState(pressing, pulling, over) -> "hidden" | "over" | "press" | "pull"   the fingertip ring
--     (html:59-62, fp.js:615-645)
--   KneadMath.barycentric(p, a, b, c) -> (wa, wb, wc)   p's weights in triangle abc (projected onto its plane; a
--     degenerate triangle gives the first corner)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SquishRig = require(script.Parent.SquishRig)

export type MoveAction = "fingerMove" | "pullTo"
export type RingState = "hidden" | "over" | "press" | "pull"

local VIEW = Config.Knead.view
local KICK_VELOCITY = Config.Knead.kickVelocity
local FULL_TURN = 360
local HALF_TURN = 180
local MIN_DENOMINATOR = 1e-12

local KneadMath = {}

-- The impulse velocity that makes a spring (ω, ζ) at rest peak at 1 on its first swing (SquishRig's own rule).
local function peakVelocity(omega: number, zeta: number): number
	if zeta >= 1 then
		return omega * math.exp(1)
	end
	local damped = math.sqrt(1 - zeta * zeta)
	local peakAt = math.atan2(damped, zeta) / (omega * damped)
	return omega * math.exp(zeta * omega * peakAt)
end

function KneadMath.kickPeak(v: number, feel: string): number
	if v == 0 then
		return 0
	end
	local omega, zeta = SquishRig.feelSpring(feel)
	return KICK_VELOCITY * v / peakVelocity(omega, zeta)
end

function KneadMath.kneadZoom(stage: Vector2, box: Vector3): number
	local aspect = if stage.X > 0 and stage.Y > 0 then stage.X / stage.Y else 1
	local viewHeight = 2 * VIEW.fitDepth * math.tan(math.rad(VIEW.cameraFovDeg) / 2)
	local maxDim = math.max(box.X, box.Y, box.Z, MIN_DENOMINATOR)
	local K = VIEW.toyLongestDu / maxDim
	local byWidth = VIEW.fitWidth * viewHeight * aspect / math.max(box.X * K, MIN_DENOMINATOR)
	local byHeight = VIEW.fitHeight * viewHeight / math.max(box.Y * K, MIN_DENOMINATOR)
	return math.max(1, math.min(byWidth, byHeight))
end

function KneadMath.duToStuds(maxDim: number, kz: number): number
	return maxDim / (VIEW.toyLongestDu * kz)
end

function KneadMath.approach(rate: number, dt: number): number
	if dt <= 0 then
		return 0
	end
	return 1 - math.exp(-rate * dt)
end

function KneadMath.tilt(
	yaw: number,
	pitch: number,
	targetYaw: number,
	targetPitch: number,
	rate: number,
	dt: number
): (number, number)
	local share = KneadMath.approach(rate, dt)
	local delta = (targetYaw - yaw + HALF_TURN) % FULL_TURN - HALF_TURN
	return delta * share, (targetPitch - pitch) * share
end

function KneadMath.moveAction(pulling: boolean, hit: boolean): MoveAction
	return if not pulling and hit then "fingerMove" else "pullTo"
end

function KneadMath.ringState(pressing: boolean, pulling: boolean, over: boolean): RingState
	if pressing then
		return if pulling then "pull" else "press"
	end
	return if over then "over" else "hidden"
end

function KneadMath.barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3): (number, number, number)
	local v0, v1, v2 = b - a, c - a, p - a
	local d00, d01, d11 = v0:Dot(v0), v0:Dot(v1), v1:Dot(v1)
	local d20, d21 = v2:Dot(v0), v2:Dot(v1)
	local denominator = d00 * d11 - d01 * d01
	if math.abs(denominator) < MIN_DENOMINATOR then
		return 1, 0, 0
	end
	local wb = (d11 * d20 - d01 * d21) / denominator
	local wc = (d00 * d21 - d01 * d20) / denominator
	return 1 - wb - wc, wb, wc
end

return KneadMath
