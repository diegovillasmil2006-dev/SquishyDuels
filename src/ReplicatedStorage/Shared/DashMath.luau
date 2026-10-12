--!strict
-- DashMath: the dash's pure math (spec phase 5 §1.2, §3.3; numbers in Config.Duel.Rules.Dash). Shared, no instances,
-- no yields. The server clamps the end point with it (Logic/DashRules) and the dasher's client predicts the same path
-- with it (DashController), so both stop at the same spot; every client samples the pose clip with it.
--
-- API:
--   DashMath.ease(x)                                      -> 1 - (1 - x)³ for x clamped to [0, 1] (design: fp.js:537)
--   DashMath.offsetAt(t, distance, seconds)               -> studs travelled t seconds into the dash
--   DashMath.speedAt(t, distance, seconds)                -> studs/s at t (3·distance/seconds at the start, 0 at the end)
--   DashMath.clampToZone(origin, dir, length, zone, margin) -> the longest distance (<= length) along the flat `dir`
--                                                            whose end stays inside `zone` shrunk by `margin` on X
--                                                            and Z (an origin already past an edge may still move
--                                                            back inward or along it, never further out)
--   DashMath.snapDirection(move, look, right)             -> (key, world flat unit dir): one of the 4 camera-relative
--                                                            directions nearest the movement input (none = "F")
--   DashMath.poseKey(dir, facing)                         -> "F" | "B" | "L" | "R": the design key (avatar.js:102)
--                                                            of a world direction for a character facing `facing`
--   DashMath.isFlatUnit(dir)                              -> a unit vector (±0.05) along the ground (|Y| <= 0.05)
--   DashMath.frameAt(t) / weightAt(frame) / eventSeconds(frame) -> the pose clip's frame, weight and event times
--   DashMath.sampleKeys(keys, frame)                      -> (angles by joint, held-arm offset) between two keys with
--                                                            the design's cosine ease (avatar.js:120-128)

local Config = require(script.Parent.Config)

-- Types

-- One key of a dash pose clip (Config.Anim.dash): a frame, joint angles in degrees (game joint space) and the extra
-- degrees on the held arm's shoulder X (the design's `hold`).
export type Key = { f: number, angles: { [string]: Vector3 }, hold: number }
export type DashKey = "F" | "B" | "L" | "R"

-- Constants

local DASH = Config.Duel.Rules.Dash
local EPSILON = 1e-6
local UNIT_TOLERANCE = 0.05 -- a direction's length may be 0.95..1.05
local FLAT_TOLERANCE = 0.05 -- and its vertical part at most this
local NO_INPUT = 0.1 -- a movement input shorter than this is no input (forward)

-- Module table

local DashMath = {}

-- Private

local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < EPSILON then
		return nil
	end
	return f.Unit
end

-- The design's key ease (avatar.js:120): 0.5 - 0.5·cos(π·t).
local function keyEase(t: number): number
	return 0.5 - 0.5 * math.cos(math.pi * t)
end

-- Public: the move

function DashMath.ease(x: number): number
	local u = math.clamp(x, 0, 1)
	return 1 - (1 - u) ^ 3
end

function DashMath.offsetAt(t: number, distance: number, seconds: number): number
	if not (seconds > 0) then
		return distance
	end
	return distance * DashMath.ease(t / seconds)
end

function DashMath.speedAt(t: number, distance: number, seconds: number): number
	if not (seconds > 0) then
		return 0
	end
	local u = math.clamp(t / seconds, 0, 1)
	return 3 * distance / seconds * (1 - u) ^ 2
end

function DashMath.clampToZone(
	origin: Vector3,
	dir: Vector3,
	length: number,
	zone: { cframe: CFrame, size: Vector3 },
	margin: number
): number
	local localOrigin = zone.cframe:PointToObjectSpace(origin)
	local localDir = zone.cframe:VectorToObjectSpace(dir)
	local best = math.max(length, 0)
	for _, axis in { "X", "Z" } do
		local o = if axis == "X" then localOrigin.X else localOrigin.Z
		local d = if axis == "X" then localDir.X else localDir.Z
		local h = math.max((if axis == "X" then zone.size.X else zone.size.Z) / 2 - margin, 0)
		if math.abs(d) > EPSILON then
			local limit = ((if d > 0 then h else -h) - o) / d
			best = math.min(best, limit)
		end
	end
	return math.max(0, best)
end

function DashMath.snapDirection(move: Vector3, look: Vector3, right: Vector3): (DashKey, Vector3)
	local forward = flat(look) or Vector3.new(0, 0, -1)
	local side = flat(right) or forward:Cross(Vector3.yAxis)
	local input = Vector3.new(move.X, 0, move.Z)
	if input.Magnitude < NO_INPUT then
		return "F", forward
	end
	local f, r = input:Dot(forward), input:Dot(side)
	if math.abs(f) >= math.abs(r) then
		return if f >= 0 then "F" else "B", if f >= 0 then forward else -forward
	end
	return if r >= 0 then "R" else "L", if r >= 0 then side else -side
end

function DashMath.poseKey(dir: Vector3, facing: Vector3): DashKey
	local forward = flat(facing) or Vector3.new(0, 0, -1)
	local right = forward:Cross(Vector3.yAxis)
	local f, r = dir:Dot(forward), dir:Dot(right)
	if math.abs(f) >= math.abs(r) then
		return if f >= 0 then "F" else "B"
	end
	return if r >= 0 then "R" else "L"
end

function DashMath.isFlatUnit(dir: Vector3): boolean
	local magnitude = dir.Magnitude
	return magnitude >= 1 - UNIT_TOLERANCE and magnitude <= 1 + UNIT_TOLERANCE and math.abs(dir.Y) <= FLAT_TOLERANCE
end

-- Public: the pose clip

function DashMath.frameAt(t: number): number
	return t * DASH.visualFps
end

function DashMath.weightAt(frame: number): number
	local last, from = DASH.visualFrames, DASH.fadeFromFrame
	if frame < from then
		return 1
	end
	local w = math.clamp((last - frame) / (last - from), 0, 1)
	return w * w
end

function DashMath.eventSeconds(frame: number): number
	return frame / DASH.visualFps
end

function DashMath.sampleKeys(keys: { Key }, frame: number): ({ [string]: Vector3 }, number)
	local first = keys[1]
	if frame <= first.f then
		return first.angles, 0
	end
	for index = 1, #keys - 1 do
		local a, b = keys[index], keys[index + 1]
		if frame <= b.f then
			local u = keyEase((frame - a.f) / (b.f - a.f))
			local out: { [string]: Vector3 } = {}
			for joint, from in a.angles do
				out[joint] = from:Lerp(b.angles[joint] or Vector3.zero, u)
			end
			for joint, to in b.angles do
				local before: Vector3? = a.angles[joint]
				if before == nil then
					out[joint] = to * u
				end
			end
			return out, a.hold + (b.hold - a.hold) * u
		end
	end
	return keys[#keys].angles, 0
end

return table.freeze(DashMath)
