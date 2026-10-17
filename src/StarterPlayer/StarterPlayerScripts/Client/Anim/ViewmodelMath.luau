--!strict
-- ViewmodelMath (client only, pure): where the first-person hands and toy go, as plain numbers and CFrames. No
-- instances are made or written, no connections, threads or clock reads.
--
-- The 3D Lab FP viewmodel (spec 2026-10-11 §3; every number from Config.FirstPerson, each with its design line). "du"
-- are the design's camera-space units (-Z forward, +Y up, +X right); U = studs per du.
--   ViewmodelMath.spring(p, v, target, spring, dt) -> (p, v)   the design's spring (fp.js:16-18): semi-implicit Euler
--       v += ((target - p)·k - v·c)·h; p += v·h, in n = max(1, ceil(dt / (1/240))) substeps h = dt / n; spring =
--       { k, c }; a number or a Vector3
--   ViewmodelMath.ease(u) -> number              cosine in-out, u clamped to 0-1 (fp.js:13)
--   ViewmodelMath.backOut(u) -> number           the pop-in: 1 + (c + 1)(u - 1)³ + c(u - 1)², c = equip.backOutC (fp.js:14)
--   ViewmodelMath.toyBox(model) -> (centre, size)   the box round every part but the Root ("E" parts by their
--       ellipsoid), in pivot space, studs at the build scale: the design's box of the whole toy (toys.js:36-38), which
--       sets its hold scale (fp.js:99)
--   ViewmodelMath.sides(toy, hw) -> (left, right)   the hands at the toy's sides: toy ± (hw + held.sideGap), y +
--       held.sideY, z + held.sideZ (fp.js:393-395); hw = the toy's half width (du)
--   ViewmodelMath.palms(toy, hw, S, k, c, held, now, reduced) -> (left, right, lRoll, rRoll, toyDx)   the two-palm
--       squeeze (fp.js:412-416): each palm at hw + sideGap - squeeze.inset · that side's narrowing (hw · (1 - S.X / k),
--       never < 0: the shown X narrowing of the rig's squeeze, our stand-in for the design's dent palmD·K), y + squeeze.y,
--       z + squeeze.z; rolls ±(arm.roll + rollPress·c); after tremorAfterSeconds held, the tremor ±tremor·c on the hands
--       (sin at tremorRateL / tremorRateR rad/s) and toyDx on the toy (×toyTremorShare at toyTremorRate); none under
--       ReducedMotion. S, k: the rig's shown scale and its uniform part; c: its press amount 0-1
--   ViewmodelMath.overlayCamera(now, kick, U) -> CFrame   the whole overlay's idle drift and kick (fp.js:660: offset
--       (x·sin(2π·xHz·T), y·sin(2π·yHz·T) + kickY·kick, 0), rotation X kickPitch·kick) as its inverse: the overlay
--       camera's CFrame (spec §3.1)
--   ViewmodelMath.toyFrame(pos, rot, U) -> CFrame   the toy's frame for a position (du) and design rotation (Euler XYZ,
--       rad): CFrame.Angles(rx, ry, rz) * CFrame.Angles(0, π, 0), since our toys face -Z and the design's +Z
--   ViewmodelMath.scaledFrame(frame, eye, s) -> CFrame   where a full-size model shows the same picture as `frame`'s
--       model scaled by s about its origin, seen from `eye`: the same rotation, moved along the ray from the eye by 1 / s
--       (a perspective picture has no other scale; the pop-in's backOut, fp.js:403, below the deformer's clamp)
--   ViewmodelMath.overlayLight() -> (ambient, lightColor, lightDirection)   the overlay's light (spec §3.1, closest
--       option): the hemisphere's mean ((sky + ground) / 2 · hemisphere, each channel at most 1), the key colour, and
--       -keyFrom.Unit (the key shines from keyFrom toward the origin; fp.js:32-33)
--   ViewmodelMath.shakeFor(value) -> (amplitudeDeg, seconds)   the design's camera shake value (fp.js:652-655: the
--       camera turns by (random - 0.5)·value²·radPerShakeSq rad, the value falling decayPerSecond a second) as
--       CameraController.shake's: the peak value²·radPerShakeSq / 2 in degrees, over value / decayPerSecond, whose
--       a·(1 - t/dur)² is the same curve
--   ViewmodelMath.screenPoint(point, screen, fovDeg) -> Vector2?   a camera-space point in pixels (vertical FOV); nil
--       when it is not in front of the camera
--   ViewmodelMath.screenBox(cframe, size, screen, fovDeg) -> Rect?   the pixel box of a camera-space box (nil when a
--       corner is behind the camera), vertical FOV
--   ViewmodelMath.touchPadRect(toyBox?, screen, layout) -> Rect?   the touch squeeze pad: the toy's box clipped to the
--       screen and cut clear of the thumbstick zone (Config.UI.Touch) and ControlsController.touchLayout's Throw,
--       Ultimate and Jump (all in the same safe-inset pixels); nil when nothing is left
--   ViewmodelMath.inspectButtonRect(screen, size, inset, layout?) -> Rect   the touch Inspect button (final polish
--       2026-10-11, build choice): centred `inset` above the bottom, moved right of the thumbstick zone (Config.UI.Touch)
--       while beside it and up above any of ControlsController.touchLayout's buttons it meets (`gap` apart), on screen
--       (pixels in the same safe-inset space)
--   ViewmodelMath.releasePoint(camera, toyCam, ratio, hitDistance?) -> (Vector3, number)   the own projectile's start:
--       on the world camera's ray through the overlay toy (toyCam, studs in camera space) at D0 = |toyCam| / ratio
--       (ratio = overlay build scale ÷ held build scale, so a held-size model there looks as big), cut by cover to
--       hitDistance - 0.5 (at least 1.5); returns the point and D / D0
--   ViewmodelMath.throttle(phase, dt, interval) -> (boolean, number)   phone speed fix 2026-10-16 (NOT IN DESIGN): a
--       step cap of one step per `interval` seconds on a phase clock; `phase` is the seconds since the last due step.
--       Due once phase + dt reaches interval (less 1 %, so two 60 Hz frames make one 30 Hz step despite rounding):
--       returns true and the phase carried on (phase + dt - interval, held to 0..interval), else false and phase + dt.
--       interval <= 0 is always due. 60 Hz frames at 1/30 step every 2nd frame, 45 Hz frames 2 of every 3, 30 Hz and
--       slower every frame
--   ViewmodelMath.stepInterval(hz) -> number   phone speed fix 2026-10-16: throttle's interval for a cap of `hz` steps a
--       second: 1 / hz, or 0 (no cap: every frame steps) when hz is 0, below 0 or not a number

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

export type Rect = { x: number, y: number, w: number, h: number }
export type TouchLayout = { throw: Rect, ultimate: Rect, jump: Rect }
export type SpringRow = { number } -- { k, c }

-- Constants

local FP = Config.FirstPerson
local HELD = FP.held
local SQUEEZE = FP.squeeze
local IDLE = FP.idle
local LIGHT = FP.light
local SHAKE = FP.shake
local ARM_ROLL = FP.arm.roll
local BACK_OUT_C = FP.equip.backOutC
local TOUCH = Config.UI.Touch
local SUBSTEP = 1 / 240 -- design: fp.js:17
local HALF_TURN = CFrame.Angles(0, math.pi, 0)
local TAU = 2 * math.pi
local NEAR_Z = 0.01 -- a corner nearer than this (studs) to the camera plane is behind it
local EDGE_BITS = { 1, 2, 4 } -- a box corner's X, Y and Z bits (screenBox)
local COVER_GAP = 0.5 -- §3.6: the own projectile starts this far in front of cover ...
local MIN_START = 1.5 -- ... and never nearer than this to the camera
local BUTTON_PASSES = 8 -- inspectButtonRect: at most this many moves up (the touch layout has 4 buttons)
local THROTTLE_SLACK = 0.99 -- throttle: a step is due at 99 % of its interval (frame-time rounding)

-- Module table

local ViewmodelMath = {}

-- Private

-- The pivot-space bounds of one part: its ellipsoid's for an "E" part, its box's otherwise.
local function partBounds(pivot: CFrame, part: BasePart): (Vector3, Vector3)
	local cf = pivot:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	local x, y, z = cf.XVector * half.X, cf.YVector * half.Y, cf.ZVector * half.Z
	local extent: Vector3
	if part:GetAttribute("SD_Shape") == "E" then
		extent = Vector3.new(
			math.sqrt(x.X * x.X + y.X * y.X + z.X * z.X),
			math.sqrt(x.Y * x.Y + y.Y * y.Y + z.Y * z.Y),
			math.sqrt(x.Z * x.Z + y.Z * y.Z + z.Z * z.Z)
		)
	else
		extent = Vector3.new(
			math.abs(x.X) + math.abs(y.X) + math.abs(z.X),
			math.abs(x.Y) + math.abs(y.Y) + math.abs(z.Y),
			math.abs(x.Z) + math.abs(y.Z) + math.abs(z.Z)
		)
	end
	return cf.Position - extent, cf.Position + extent
end

-- The pivot-space box (lo, hi) of every part but the Root.
local function partBoxes(model: Model): (Vector3, Vector3)
	local pivot = model:GetPivot()
	local root = model.PrimaryPart
	local allLo, allHi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			local lo, hi = partBounds(pivot, part)
			allLo, allHi = allLo:Min(lo), allHi:Max(hi)
		end
	end
	return allLo, allHi
end

-- Public: the 3D Lab FP viewmodel -----------------------------------------------------------------------------------

function ViewmodelMath.spring<T>(p: T, v: T, target: T, spring: SpringRow, dt: number): (T, T)
	local k, c = spring[1], spring[2]
	local n = math.max(1, math.ceil(dt / SUBSTEP)) -- design: fp.js:17
	local h = dt / n
	local x: any, xv: any, goal: any = p, v, target
	for _ = 1, n do
		xv += ((goal - x) * k - xv * c) * h
		x += xv * h
	end
	return x, xv
end

function ViewmodelMath.ease(u: number): number
	return 0.5 - 0.5 * math.cos(math.pi * math.clamp(u, 0, 1)) -- design: fp.js:13
end

function ViewmodelMath.backOut(u: number): number
	local c = BACK_OUT_C
	return 1 + (c + 1) * (u - 1) ^ 3 + c * (u - 1) ^ 2 -- design: fp.js:14
end

function ViewmodelMath.toyBox(model: Model): (Vector3, Vector3)
	local lo, hi = partBoxes(model)
	if lo.X > hi.X then
		return Vector3.zero, Vector3.zero -- no part at all
	end
	return (lo + hi) / 2, hi - lo
end

function ViewmodelMath.sides(toy: Vector3, hw: number): (Vector3, Vector3)
	local gap = hw + HELD.sideGap
	return toy + Vector3.new(-gap, HELD.sideY, HELD.sideZ), toy + Vector3.new(gap, HELD.sideY, HELD.sideZ)
end

function ViewmodelMath.palms(
	toy: Vector3,
	hw: number,
	S: Vector3,
	k: number,
	c: number,
	held: number,
	now: number,
	reduced: boolean
): (Vector3, Vector3, number, number, number)
	local narrow = if k > 0 then math.max(0, hw * (1 - S.X / k)) else 0
	local g = hw + HELD.sideGap - SQUEEZE.inset * narrow
	local tr = if held > SQUEEZE.tremorAfterSeconds and not reduced then SQUEEZE.tremor * c else 0
	local left = toy + Vector3.new(-g + math.sin(now * SQUEEZE.tremorRateL) * tr, SQUEEZE.y, SQUEEZE.z)
	local right = toy + Vector3.new(g - math.sin(now * SQUEEZE.tremorRateR) * tr, SQUEEZE.y, SQUEEZE.z)
	local roll = ARM_ROLL + SQUEEZE.rollPress * c
	return left, right, roll, -roll, math.sin(now * SQUEEZE.toyTremorRate) * tr * SQUEEZE.toyTremorShare
end

function ViewmodelMath.overlayCamera(now: number, kick: number, U: number): CFrame
	local offset = Vector3.new(
		IDLE.x * math.sin(TAU * IDLE.xHz * now),
		IDLE.y * math.sin(TAU * IDLE.yHz * now) + IDLE.kickY * kick,
		0
	)
	return (CFrame.new(offset * U) * CFrame.Angles(IDLE.kickPitch * kick, 0, 0)):Inverse()
end

function ViewmodelMath.toyFrame(pos: Vector3, rot: Vector3, U: number): CFrame
	return CFrame.new(pos * U) * CFrame.Angles(rot.X, rot.Y, rot.Z) * HALF_TURN
end

function ViewmodelMath.scaledFrame(frame: CFrame, eye: Vector3, s: number): CFrame
	return frame.Rotation + (eye + (frame.Position - eye) / s)
end

function ViewmodelMath.overlayLight(): (Color3, Color3, Vector3)
	return LIGHT.viewportAmbient, LIGHT.viewportLight, -LIGHT.keyFrom.Unit
end

function ViewmodelMath.shakeFor(value: number): (number, number)
	if not (value > 0) then
		return 0, 0
	end
	return math.deg(value * value * SHAKE.radPerShakeSq / 2), value / SHAKE.decayPerSecond
end

function ViewmodelMath.screenPoint(point: Vector3, screen: Vector2, fovDeg: number): Vector2?
	if not (point.Z <= -NEAR_Z) then
		return nil
	end
	local focal = screen.Y / 2 / math.tan(math.rad(fovDeg) / 2)
	return Vector2.new(screen.X / 2 + point.X / -point.Z * focal, screen.Y / 2 - point.Y / -point.Z * focal)
end

-- Corner `i` (0-7: bit 1 = +X, 2 = +Y, 4 = +Z) of a box in camera space.
local function corner(cframe: CFrame, half: Vector3, i: number): Vector3
	return cframe:PointToWorldSpace(
		Vector3.new(
			if bit32.band(i, 1) ~= 0 then half.X else -half.X,
			if bit32.band(i, 2) ~= 0 then half.Y else -half.Y,
			if bit32.band(i, 4) ~= 0 then half.Z else -half.Z
		)
	)
end

function ViewmodelMath.screenBox(cframe: CFrame, size: Vector3, screen: Vector2, fovDeg: number, out: Rect?): Rect?
	local focal = screen.Y / 2 / math.tan(math.rad(fovDeg) / 2)
	local half = size / 2
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	-- The corners in front of the camera plane, and where the 12 edges cross it (a sleeve reaching past the
	-- shoulder): the visible part's box. Edge e of corner i is the X, Y or Z bit flipped (e = 0 is the corner itself).
	for i = 0, 7 do
		local a = corner(cframe, half, i)
		local aFront = a.Z <= -NEAR_Z
		for e = 0, 3 do
			local bit = if e == 0 then 0 else EDGE_BITS[e]
			local p: Vector3? = nil
			if e == 0 then
				p = if aFront then a else nil
			elseif bit32.band(i, bit) == 0 then
				local b = corner(cframe, half, i + bit)
				if aFront ~= (b.Z <= -NEAR_Z) then
					p = a + (b - a) * ((-NEAR_Z - a.Z) / (b.Z - a.Z))
				end
			end
			if p then
				local px = screen.X / 2 + p.X / -p.Z * focal
				local py = screen.Y / 2 - p.Y / -p.Z * focal
				x0, y0, x1, y1 = math.min(x0, px), math.min(y0, py), math.max(x1, px), math.max(y1, py)
			end
		end
	end
	if x0 > x1 then
		return nil -- wholly behind the camera
	end
	local rect: Rect = out or { x = 0, y = 0, w = 0, h = 0 }
	rect.x, rect.y, rect.w, rect.h = x0, y0, x1 - x0, y1 - y0
	return rect
end

-- The biggest of the four pieces of (x0, y0)-(x1, y1) clear of the box (bx0, by0)-(bx1, by1): left of it, right of
-- it, above or below. Each piece lies inside the first rect, so no earlier cut is undone. Returns its corners; an
-- empty piece has x0 >= x1.
local function clearOf(
	x0: number,
	y0: number,
	x1: number,
	y1: number,
	bx0: number,
	by0: number,
	bx1: number,
	by1: number
): (number, number, number, number)
	if not (x0 < bx1 and bx0 < x1 and y0 < by1 and by0 < y1) then
		return x0, y0, x1, y1
	end
	local left = math.max(math.min(x1, bx0) - x0, 0) * (y1 - y0)
	local right = math.max(x1 - math.max(x0, bx1), 0) * (y1 - y0)
	local above = (x1 - x0) * math.max(math.min(y1, by0) - y0, 0)
	local below = (x1 - x0) * math.max(y1 - math.max(y0, by1), 0)
	local most = math.max(left, right, above, below)
	if most <= 0 then
		return x0, y0, x0, y1
	elseif most == left then
		return x0, y0, math.min(x1, bx0), y1
	elseif most == right then
		return math.max(x0, bx1), y0, x1, y1
	elseif most == above then
		return x0, y0, x1, math.min(y1, by0)
	end
	return x0, math.max(y0, by1), x1, y1
end

function ViewmodelMath.touchPadRect(toyBox: Rect?, screen: Vector2, layout: TouchLayout, out: Rect?): Rect?
	if toyBox == nil then
		return nil
	end
	local x0, y0 = math.max(toyBox.x, 0), math.max(toyBox.y, 0)
	local x1, y1 = math.min(toyBox.x + toyBox.w, screen.X), math.min(toyBox.y + toyBox.h, screen.Y)
	-- The thumbstick zone (lower left), then Throw, Ultimate and Jump.
	x0, y0, x1, y1 = clearOf(
		x0,
		y0,
		x1,
		y1,
		0,
		screen.Y * (1 - TOUCH.thumbstickZoneHeight),
		screen.X * TOUCH.thumbstickZoneWidth,
		screen.Y
	)
	for _, b in layout :: { [string]: Rect } do
		if x0 < x1 and y0 < y1 then
			x0, y0, x1, y1 = clearOf(x0, y0, x1, y1, b.x, b.y, b.x + b.w, b.y + b.h)
		end
	end
	if x0 >= x1 or y0 >= y1 then
		return nil
	end
	local rect: Rect = out or { x = 0, y = 0, w = 0, h = 0 }
	rect.x, rect.y, rect.w, rect.h = x0, y0, x1 - x0, y1 - y0
	return rect
end

function ViewmodelMath.inspectButtonRect(screen: Vector2, size: Vector2, inset: number, layout: TouchLayout?): Rect
	local gap = TOUCH.gap
	local x = screen.X / 2 - size.X / 2
	local y = screen.Y - inset - size.Y
	if x < screen.X * TOUCH.thumbstickZoneWidth + gap and y + size.Y > screen.Y * (1 - TOUCH.thumbstickZoneHeight) then
		x = screen.X * TOUCH.thumbstickZoneWidth + gap
	end
	if layout then
		-- Up above each touch button it meets; checked again after a move (a move can meet the next one up).
		for _ = 1, BUTTON_PASSES do
			local moved = false
			for _, b in layout :: { [string]: Rect } do
				if
					x < b.x + b.w + gap
					and b.x - gap < x + size.X
					and y < b.y + b.h + gap
					and b.y - gap < y + size.Y
				then
					y = b.y - gap - size.Y
					moved = true
				end
			end
			if not moved then
				break
			end
		end
	end
	return {
		x = math.clamp(x, 0, math.max(screen.X - size.X, 0)),
		y = math.clamp(y, 0, math.max(screen.Y - size.Y, 0)),
		w = size.X,
		h = size.Y,
	}
end

function ViewmodelMath.releasePoint(
	camera: CFrame,
	toyCam: Vector3,
	ratio: number,
	hitDistance: number?
): (Vector3, number)
	local d0 = toyCam.Magnitude / ratio
	local d = d0
	if hitDistance ~= nil then
		d = math.max(math.min(hitDistance - COVER_GAP, d0), math.min(MIN_START, d0))
	end
	return camera.Position + camera:VectorToWorldSpace(toyCam.Unit) * d, d / d0
end

function ViewmodelMath.throttle(phase: number, dt: number, interval: number): (boolean, number)
	if not (interval > 0) then
		return true, 0
	end
	local elapsed = phase + dt
	if elapsed < interval * THROTTLE_SLACK then
		return false, elapsed
	end
	return true, math.clamp(elapsed - interval, 0, interval)
end

function ViewmodelMath.stepInterval(hz: number): number
	if type(hz) ~= "number" or not (hz > 0) then
		return 0
	end
	return 1 / hz
end

return ViewmodelMath
