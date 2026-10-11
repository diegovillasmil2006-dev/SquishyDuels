--!strict
-- OrbitCamera (client only, pure). DESIGN §10.2 ('OrbitCamera': pure math, target/current yaw, pitch, zoom and the
-- SmoothDamp state), §10.5 (orbit, clamps, smoothing, drag-release inertia, Reset View), §10.6 (input scaling, the
-- analytic tap test). No instances, no TweenService, no clock: the caller passes dt, so it runs in Edit mode and Lune.
-- Reading (§10.2 puts OrbitCamera inside InspectController): it is its own module so it is unit-tested alone.
--   local s = OrbitCamera.new(def.inspect.yaw, def.inspect.pitch)   -- current = target = the defaults, zoom 1
--   OrbitCamera.beginDrag(s) / drag(s, dx, dy, H, dt) / endDrag(s, reduced)
--   OrbitCamera.rotate(s, dYaw, dPitch)        -- arrow keys / right stick, already multiplied by dt
--   OrbitCamera.zoomBy(s, factor) / setZoom(s, zoom) / reset(s)
--   local yaw, pitch, zoom = OrbitCamera.step(s, dt)   -- every frame; then stage:setView(yaw, pitch, zoom)
--   On select (a new squishy): setDefaults(s, yaw, pitch); reset(s); snap(s)  -- the new default view at once.
-- Conventions:
--   * Yaw / pitch are ViewportStage.orbitCFrame's: yaw 0 / pitch 0 = in front of the face (the pivot's -Z side),
--     +yaw = the camera toward the model's own left (-X), +pitch = from above (its documented reading of §10.5).
--   * Screen directions follow the finger: a drag to the right turns the model's FRONT to the right on screen (yaw
--     falls), a drag down tilts the front down (pitch rises: seen more from above). keyRates and stickRates use the
--     same directions (right = like a drag right, up = like a drag up; the stick's Position.Y is up-positive), which
--     is also the default Roblox camera's (stick / drag up = look up = the camera goes lower).
--   * Zoom is the distance multiplier of ViewportStage (< 1 = closer), kept in Config.Inspect.Framing [zoomMin,
--     zoomMax]; pitch in Config.Inspect.Orbit [pitchMinDeg, pitchMaxDeg]; yaw is continuous inside (so smoothing
--     never takes the long way round) and wrapped to [0, 360) on output.
--   * drag(): call it once per frame while a drag is held, with that frame's summed pointer delta (0, 0 when the
--     pointer did not move) and the frame's dt, so the tracked speed falls to 0 when the finger stops; a call with
--     dt = 0 still moves the view and its yaw counts toward the next sample.
--   * Inertia (§10.5): endDrag hands the tracked yaw speed to step(), which adds it to the target yaw and decays it
--     e^(-inertiaDecay·t) (integrated exactly, so the travel does not depend on the frame rate); none under
--     ReducedMotion (endDrag(s, true)).
--   * Reset View: the targets go back to the defaults (the yaw by the shortest way) and all three are smoothed with
--     resetSmoothSeconds until within a small epsilon, then snapped. Any drag, rotate or zoom cancels the reset.
-- Tap test (§10.6): tapRay is the exact inverse of ViewportStage.projectPoint (frame scale (0, 0) top-left), and
-- hitsBox transforms the ray into the bounding box's space, scales it by 1 / half-size and intersects the unit sphere;
-- hits behind the origin are ignored.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

-- Types

-- The Config.Inspect sections OrbitCamera reads (tests pass edited copies).
export type Tuning = {
	Orbit: typeof(Config.Inspect.Orbit),
	Framing: typeof(Config.Inspect.Framing),
	Input: typeof(Config.Inspect.Input),
}

export type State = {
	yaw: number, -- current (smoothed), degrees, continuous
	pitch: number, -- current (smoothed), degrees
	zoom: number, -- current (smoothed) distance multiplier
	targetYaw: number,
	targetPitch: number,
	targetZoom: number,
	yawVelocity: number, -- SmoothDamp velocities (units per second)
	pitchVelocity: number,
	zoomVelocity: number,
	inertia: number, -- degrees per second added to targetYaw (drag release)
	resetting: boolean,
	defaultYaw: number,
	defaultPitch: number,
	dragging: boolean,
	dragSpeed: number, -- the tracked (filtered) yaw speed of the drag, degrees per second
	dragCarry: number, -- yaw moved by drag calls with dt = 0, counted in the next sample
	cfg: Tuning,
}

-- Constants

local DEFAULT_TUNING: Tuning = Config.Inspect
local FULL_TURN = 360
local HALF_TURN = 180
local MIN_SMOOTH_SECONDS = 1e-4 -- SmoothDamp's T never reaches 0 (division)
local RESET_EPSILON_DEG = 0.01 -- reading: Reset View snaps once yaw and pitch are this close ...
local RESET_EPSILON_ZOOM = 1e-4 -- ... and the zoom this close
local INERTIA_STOP_DEG_PER_SECOND = 0.5 -- reading: slower inertia is dropped (at most 0.5 / inertiaDecay° left)
local MIN_HALF_SIZE = 1e-4 -- a flat bounding box still has a thickness for the tap test
local MIN_DIRECTION = 1e-9
-- SmoothDamp's exp(-x) approximation (Game Programming Gems 4, ch. 1.10), as Unity's Mathf.SmoothDamp uses.
local SMOOTH_C2 = 0.48
local SMOOTH_C3 = 0.235

-- Module table

local OrbitCamera = {}

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function positive(n: unknown, fallback: number): number
	if finite(n) and (n :: number) > 0 then
		return n :: number
	end
	return fallback
end

local function clampPitch(cfg: Tuning, pitch: number): number
	return math.clamp(pitch, cfg.Orbit.pitchMinDeg, cfg.Orbit.pitchMaxDeg)
end

local function clampZoom(cfg: Tuning, zoom: number): number
	return math.clamp(zoom, cfg.Framing.zoomMin, cfg.Framing.zoomMax)
end

-- The signed smallest turn from `from` to `to`, in (-180, 180].
local function shortestDelta(from: number, to: number): number
	local delta = (to - from + HALF_TURN) % FULL_TURN - HALF_TURN
	if delta <= -HALF_TURN then
		delta += FULL_TURN
	end
	return delta
end

-- Public: pure helpers ---------------------------------------------------------------------------------------------

-- Any angle to [0, 360). A non-finite angle gives 0.
function OrbitCamera.wrapYaw(deg: number): number
	if not finite(deg) then
		return 0
	end
	local wrapped = deg % FULL_TURN
	if wrapped >= FULL_TURN or wrapped < 0 then
		wrapped = 0 -- float edge: -1e-15 % 360 rounds to 360
	end
	return wrapped
end

-- A critically damped spring toward `target` that takes about `smoothTime` seconds (Unity's Mathf.SmoothDamp,
-- without the speed cap): returns (value, velocity). Never overshoots the target. dt <= 0 changes nothing.
function OrbitCamera.smoothDamp(
	current: number,
	target: number,
	velocity: number,
	smoothTime: number,
	dt: number
): (number, number)
	if not finite(dt) or dt <= 0 then
		return current, velocity
	end
	local omega = 2 / math.max(positive(smoothTime, MIN_SMOOTH_SECONDS), MIN_SMOOTH_SECONDS)
	local x = omega * dt
	local decay = 1 / (1 + x + SMOOTH_C2 * x * x + SMOOTH_C3 * x * x * x)
	local change = current - target
	local temp = (velocity + omega * change) * dt
	local newVelocity = (velocity - omega * temp) * decay
	local value = target + (change + temp) * decay
	if change ~= 0 and (change < 0) == (value > target) then
		return target, 0
	end
	return value, newVelocity
end

-- The right stick (§10.6): radial deadzone (|v| <= stickDeadzone gives 0), the rest rescaled to 0..1, response
-- |v|^stickExponent, full deflection = stickYawDegPerSecond / stickPitchDegPerSecond. Returns (yaw, pitch) degrees
-- per second in the drag's directions: x > 0 (right) = like a drag right (yaw falls), y > 0 (up) = like a drag up
-- (pitch falls).
function OrbitCamera.stickRates(x: number, y: number, cfg: Tuning?): (number, number)
	local input = (cfg or DEFAULT_TUNING).Input
	if not finite(x) or not finite(y) then
		return 0, 0
	end
	local magnitude = math.sqrt(x * x + y * y)
	local deadzone = input.stickDeadzone
	if magnitude <= deadzone then
		return 0, 0
	end
	local scaled = math.clamp((magnitude - deadzone) / (1 - deadzone), 0, 1)
	local response = scaled ^ input.stickExponent
	local dirX, dirY = x / magnitude, y / magnitude
	return -dirX * response * input.stickYawDegPerSecond, -dirY * response * input.stickPitchDegPerSecond
end

-- The arrow keys (§10.6, keyDegPerSecond): `right` and `up` are -1, 0 or 1 (Right minus Left, Up minus Down).
-- Returns (yaw, pitch) degrees per second in the same directions as stickRates.
function OrbitCamera.keyRates(right: number, up: number, cfg: Tuning?): (number, number)
	local speed = (cfg or DEFAULT_TUNING).Input.keyDegPerSecond
	local r = if finite(right) then math.clamp(right, -1, 1) else 0
	local u = if finite(up) then math.clamp(up, -1, 1) else 0
	return -r * speed, -u * speed
end

-- The zoom factor of `notches` mouse-wheel notches (InputObject.Position.Z; > 0 = wheel up = zoom in): <1 = closer.
-- `+` / `-` count as one notch each (+1 / -1).
function OrbitCamera.wheelFactor(notches: number, cfg: Tuning?): number
	if not finite(notches) then
		return 1
	end
	return (cfg or DEFAULT_TUNING).Input.wheelZoomFactor ^ -notches
end

-- The zoom factor of the triggers over dt (§10.6: R2 in / L2 out, triggerZoomPerSecond at full press; r2 and l2 are
-- Position.Z in 0..1).
function OrbitCamera.triggerFactor(r2: number, l2: number, dt: number, cfg: Tuning?): number
	local r = if finite(r2) then math.clamp(r2, 0, 1) else 0
	local l = if finite(l2) then math.clamp(l2, 0, 1) else 0
	if not finite(dt) or dt <= 0 then
		return 1
	end
	return (cfg or DEFAULT_TUNING).Input.triggerZoomPerSecond ^ ((l - r) * dt)
end

-- Two-finger pinch (§10.6): zoom = startZoom × startDist / currentDist (fingers apart = closer), clamped to
-- [zoomMin, zoomMax]. Bad distances keep startZoom.
function OrbitCamera.pinchZoom(startZoom: number, startDistPx: number, currentDistPx: number, cfg: Tuning?): number
	local c = cfg or DEFAULT_TUNING
	local start = positive(startZoom, 1)
	if not (finite(startDistPx) and startDistPx > 0 and finite(currentDistPx) and currentDistPx > 0) then
		return clampZoom(c, start)
	end
	return clampZoom(c, start * startDistPx / currentDistPx)
end

-- Tap vs drag (§10.6): moved < tapMaxPixels and held < tapMaxMs.
function OrbitCamera.isTap(movedPx: number, heldMs: number, cfg: Tuning?): boolean
	local input = (cfg or DEFAULT_TUNING).Input
	return finite(movedPx) and finite(heldMs) and movedPx < input.tapMaxPixels and heldMs < input.tapMaxMs
end

-- The camera ray through a point of the view (frame scale: (0, 0) top-left, (1, 1) bottom-right) for a camera at
-- `cameraCFrame` with vertical FOV `vFovDeg` and `aspect` = width / height: (origin, unit direction). The exact
-- inverse of ViewportStage.projectPoint (same FOV and aspect fallbacks).
function OrbitCamera.tapRay(cameraCFrame: CFrame, vFovDeg: number, aspect: number, point01: Vector2): (Vector3, Vector3)
	local fov = math.clamp(positive(vFovDeg, DEFAULT_TUNING.Framing.vFovDeg), 1, 179)
	local tanV = math.tan(math.rad(fov) / 2)
	local tanH = tanV * positive(aspect, 1)
	local x = point01.X * 2 - 1
	local y = 1 - point01.Y * 2
	local direction = Vector3.new(x * tanH, y * tanV, -1).Unit
	return cameraCFrame.Position, cameraCFrame:VectorToWorldSpace(direction)
end

-- The analytic tap test (§10.6): the ray (origin, direction) in the space of the box (boxCFrame, boxSize: a model's
-- GetBoundingBox), scaled by 1 / half-size, against the unit sphere. True when it hits ahead of the origin (an origin
-- inside counts); hits behind it are ignored.
function OrbitCamera.hitsBox(origin: Vector3, direction: Vector3, boxCFrame: CFrame, boxSize: Vector3): boolean
	if direction.Magnitude < MIN_DIRECTION then
		return false
	end
	local hx = math.max(boxSize.X / 2, MIN_HALF_SIZE)
	local hy = math.max(boxSize.Y / 2, MIN_HALF_SIZE)
	local hz = math.max(boxSize.Z / 2, MIN_HALF_SIZE)
	local p = boxCFrame:PointToObjectSpace(origin)
	local v = boxCFrame:VectorToObjectSpace(direction)
	local o = Vector3.new(p.X / hx, p.Y / hy, p.Z / hz)
	local d = Vector3.new(v.X / hx, v.Y / hy, v.Z / hz)
	local a = d:Dot(d)
	local b = 2 * o:Dot(d)
	local c = o:Dot(o) - 1
	local discriminant = b * b - 4 * a * c
	if a <= 0 or discriminant < 0 then
		return false
	end
	local far = (-b + math.sqrt(discriminant)) / (2 * a)
	return far >= 0
end

-- Public: the orbit state ------------------------------------------------------------------------------------------

-- A new orbit at its default view (current = target = defaults, zoom 1, at rest). Missing or non-finite angles use
-- Config.Inspect.Orbit's defaults; the pitch is clamped.
function OrbitCamera.new(yawDeg: number?, pitchDeg: number?, cfg: Tuning?): State
	local c = cfg or DEFAULT_TUNING
	local yaw = OrbitCamera.wrapYaw(if finite(yawDeg) then yawDeg :: number else c.Orbit.defaultYawDeg)
	local pitch = clampPitch(c, if finite(pitchDeg) then pitchDeg :: number else c.Orbit.defaultPitchDeg)
	local zoom = clampZoom(c, 1)
	return {
		yaw = yaw,
		pitch = pitch,
		zoom = zoom,
		targetYaw = yaw,
		targetPitch = pitch,
		targetZoom = zoom,
		yawVelocity = 0,
		pitchVelocity = 0,
		zoomVelocity = 0,
		inertia = 0,
		resetting = false,
		defaultYaw = yaw,
		defaultPitch = pitch,
		dragging = false,
		dragSpeed = 0,
		dragCarry = 0,
		cfg = c,
	}
end

-- The view Reset View returns to (a new squishy's Catalog `inspect`). Does not move the view by itself.
function OrbitCamera.setDefaults(s: State, yawDeg: number, pitchDeg: number)
	if finite(yawDeg) then
		s.defaultYaw = OrbitCamera.wrapYaw(yawDeg)
	end
	if finite(pitchDeg) then
		s.defaultPitch = clampPitch(s.cfg, pitchDeg)
	end
end

-- Current = target at once: no smoothing, no velocity, no inertia, no reset in progress (used on select).
function OrbitCamera.snap(s: State)
	s.targetPitch = clampPitch(s.cfg, s.targetPitch)
	s.targetZoom = clampZoom(s.cfg, s.targetZoom)
	s.yaw, s.pitch, s.zoom = s.targetYaw, s.targetPitch, s.targetZoom
	s.yawVelocity, s.pitchVelocity, s.zoomVelocity = 0, 0, 0
	s.inertia = 0
	s.resetting = false
	s.dragSpeed = 0
	s.dragCarry = 0
end

-- A drag starts (MouseButton1 / one finger on the viewport): any inertia or reset stops.
function OrbitCamera.beginDrag(s: State)
	s.dragging = true
	s.inertia = 0
	s.resetting = false
	s.dragSpeed = 0
	s.dragCarry = 0
end

-- One frame of a drag: yaw -= dx / H × dragYawDegPerHeight (the front follows the finger), pitch += dy / H ×
-- dragPitchDegPerHeight (down = from above), H = the viewport height in px. Tracks the yaw speed for the release.
function OrbitCamera.drag(s: State, dxPx: number, dyPx: number, heightPx: number, dt: number)
	if not (finite(dxPx) and finite(dyPx) and finite(heightPx) and heightPx > 0) then
		return
	end
	local input = s.cfg.Input
	local dYaw = -dxPx / heightPx * input.dragYawDegPerHeight
	local dPitch = dyPx / heightPx * input.dragPitchDegPerHeight
	s.targetYaw += dYaw
	s.targetPitch = clampPitch(s.cfg, s.targetPitch + dPitch)
	s.resetting = false
	s.inertia = 0
	if finite(dt) and dt > 0 then
		local sample = (dYaw + s.dragCarry) / dt
		s.dragCarry = 0
		local alpha = 1 - math.exp(-dt / positive(input.dragSpeedSmoothSeconds, MIN_SMOOTH_SECONDS))
		s.dragSpeed += (sample - s.dragSpeed) * alpha
	else
		s.dragCarry += dYaw
	end
end

-- The drag ends (release, or the CAS Cancel state): its tracked yaw speed becomes the inertia, none when `reduced`
-- (ReducedMotion).
function OrbitCamera.endDrag(s: State, reduced: boolean)
	s.dragging = false
	s.inertia = if reduced or not finite(s.dragSpeed) then 0 else s.dragSpeed
	s.dragSpeed = 0
	s.dragCarry = 0
end

-- Turns the target view by (dYaw, dPitch) degrees (arrow keys and the stick: rate × dt; see keyRates / stickRates).
function OrbitCamera.rotate(s: State, dYawDeg: number, dPitchDeg: number)
	if finite(dYawDeg) then
		s.targetYaw += dYawDeg
	end
	if finite(dPitchDeg) then
		s.targetPitch = clampPitch(s.cfg, s.targetPitch + dPitchDeg)
	end
	s.resetting = false
end

-- Multiplies the target zoom (< 1 = closer; wheelFactor / triggerFactor give the factor), clamped.
function OrbitCamera.zoomBy(s: State, factor: number)
	if not (finite(factor) and factor > 0) then
		return
	end
	s.targetZoom = clampZoom(s.cfg, s.targetZoom * factor)
	s.resetting = false
end

-- Sets the target zoom (the pinch's absolute result), clamped.
function OrbitCamera.setZoom(s: State, zoom: number)
	if not (finite(zoom) and zoom > 0) then
		return
	end
	s.targetZoom = clampZoom(s.cfg, zoom)
	s.resetting = false
end

-- Reset View (§10.5): the targets go back to the defaults and zoom 1 (the yaw by the shortest way), smoothed with
-- resetSmoothSeconds by step(); inertia stops.
function OrbitCamera.reset(s: State)
	s.targetYaw = s.yaw + shortestDelta(s.yaw, s.defaultYaw)
	s.targetPitch = s.defaultPitch
	s.targetZoom = clampZoom(s.cfg, 1)
	s.inertia = 0
	s.dragSpeed = 0
	s.dragCarry = 0
	s.resetting = true
end

-- The current view without stepping: (yaw in [0, 360), pitch, zoom).
function OrbitCamera.view(s: State): (number, number, number)
	return OrbitCamera.wrapYaw(s.yaw), s.pitch, s.zoom
end

-- One frame: inertia into the target yaw (decayed e^(-inertiaDecay·dt)), targets clamped, then SmoothDamp toward
-- them (rotateSmoothSeconds / zoomSmoothSeconds, or resetSmoothSeconds while resetting). Returns (yaw in [0, 360),
-- pitch, zoom). dt <= 0 only returns the view.
function OrbitCamera.step(s: State, dt: number): (number, number, number)
	if not finite(dt) or dt <= 0 then
		return OrbitCamera.view(s)
	end
	local orbit = s.cfg.Orbit
	if s.inertia ~= 0 then
		local k = orbit.inertiaDecay
		local decay = math.exp(-k * dt)
		s.targetYaw += s.inertia * (1 - decay) / k
		s.inertia *= decay
		if math.abs(s.inertia) < INERTIA_STOP_DEG_PER_SECOND then
			s.inertia = 0
		end
	end
	s.targetPitch = clampPitch(s.cfg, s.targetPitch)
	s.targetZoom = clampZoom(s.cfg, s.targetZoom)

	local rotateT = if s.resetting then orbit.resetSmoothSeconds else orbit.rotateSmoothSeconds
	local zoomT = if s.resetting then orbit.resetSmoothSeconds else orbit.zoomSmoothSeconds
	s.yaw, s.yawVelocity = OrbitCamera.smoothDamp(s.yaw, s.targetYaw, s.yawVelocity, rotateT, dt)
	s.pitch, s.pitchVelocity = OrbitCamera.smoothDamp(s.pitch, s.targetPitch, s.pitchVelocity, rotateT, dt)
	s.zoom, s.zoomVelocity = OrbitCamera.smoothDamp(s.zoom, s.targetZoom, s.zoomVelocity, zoomT, dt)

	if
		s.resetting
		and math.abs(s.yaw - s.targetYaw) < RESET_EPSILON_DEG
		and math.abs(s.pitch - s.targetPitch) < RESET_EPSILON_DEG
		and math.abs(s.zoom - s.targetZoom) < RESET_EPSILON_ZOOM
	then
		OrbitCamera.snap(s)
	end

	-- Keep the continuous yaw small: shift current and target by the same whole turns.
	local turns = math.floor(s.yaw / FULL_TURN) * FULL_TURN
	if turns ~= 0 then
		s.yaw -= turns
		s.targetYaw -= turns
	end
	return OrbitCamera.view(s)
end

return OrbitCamera
