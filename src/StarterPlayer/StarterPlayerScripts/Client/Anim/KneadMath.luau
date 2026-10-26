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
--   Owner 2026-10-26 ("wings dont squish, check every model"): a pressed rider's squash.
--   KneadMath.pressAxis(direction) -> 1 | 2 | 3   the part's axis (X, Y, Z) a press along `direction` (its own space, any
--     length) runs most along; a tie takes the first
--   KneadMath.pressScale(axis, amount) -> Vector3   the mesh Scale multiplier of a part pressed along that axis: squashed
--     to 1 - amount on it, the other two bulged so the volume stays
--   KneadMath.rayPart(cframe, size, shape, origin, direction) -> number?   where the ray origin + t·direction (t in
--     0..1) first meets the part: its ellipsoid for shape "E", else its box (W wedges and TRI halves too); nil if not

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

-- One axis, not a mix: a mesh Scale only scales along the part's own axes, and spreading the squash over them by the
-- press's shares cancels out on a slanted press (Studio: the dragon's wing moved 7%).
function KneadMath.pressAxis(direction: Vector3): number
	local x, y, z = math.abs(direction.X), math.abs(direction.Y), math.abs(direction.Z)
	if x >= y and x >= z then
		return 1
	end
	return if y >= z then 2 else 3
end

-- c = 1 - amount on that axis, w = 1 / √c on the other two (the product stays 1); a negative amount (a spring's
-- rebound) stretches along the press.
function KneadMath.pressScale(axis: number, amount: number): Vector3
	if amount == 0 then
		return Vector3.one
	end
	local c = 1 - amount
	local w = 1 / math.sqrt(c)
	return Vector3.new(if axis == 1 then c else w, if axis == 2 then c else w, if axis == 3 then c else w)
end

-- In the part's unit space (half size 1): the unit sphere for E, else the unit box (slab test). Nil past the ray's end.
function KneadMath.rayPart(cframe: CFrame, size: Vector3, shape: string, origin: Vector3, direction: Vector3): number?
	local half = size / 2
	local o = cframe:PointToObjectSpace(origin) / half
	local d = cframe:VectorToObjectSpace(direction) / half
	local t: number
	if shape == "E" then
		local a, b, c = d:Dot(d), o:Dot(d), o:Dot(o) - 1
		local disc = b * b - a * c
		if a < MIN_DENOMINATOR or disc < 0 then
			return nil
		end
		local root = math.sqrt(disc)
		t = (-b - root) / a
		if t < 0 then
			t = (-b + root) / a -- the ray starts inside
		end
	else
		local near, far = -math.huge, math.huge
		for _, pair in { { o.X, d.X }, { o.Y, d.Y }, { o.Z, d.Z } } do
			local oi, di = pair[1], pair[2]
			if math.abs(di) < MIN_DENOMINATOR then
				if math.abs(oi) > 1 then
					return nil
				end
			else
				local t1, t2 = (-1 - oi) / di, (1 - oi) / di
				near, far = math.max(near, math.min(t1, t2)), math.min(far, math.max(t1, t2))
			end
		end
		if near > far then
			return nil
		end
		t = if near >= 0 then near else far
	end
	return if t >= 0 and t <= 1 then t else nil
end

return KneadMath
