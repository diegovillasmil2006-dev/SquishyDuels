--!strict
-- OrbitCamera_Test: the pure orbit maths of StarterPlayerScripts.Client.UI.OrbitCamera (Inspect). Server only
-- (ServerStorage.UnitTest). Pure: no instances, no clock (every step gets its dt), no ViewportFrame.
-- Contract (DESIGN §10.5, §10.6, Config.Inspect):
--   * new / wrapYaw / clamps: the view starts at its defaults (zoom 1); pitch stays in [pitchMinDeg, pitchMaxDeg], zoom
--     in [zoomMin, zoomMax]; yaw is continuous inside and wrapped to [0, 360) on output, and never takes the long way;
--   * smoothDamp converges without overshoot, nearly independent of the frame rate, and dt = 0 changes nothing;
--   * a drag turns yaw by dx/H × 300° and pitch by dy/H × 180°; the model's FRONT follows the finger (checked through
--     ViewportStage.projectPoint of the face point); release inertia decays e^(-6t) and is 0 under ReducedMotion; a
--     finger that stops before release leaves (almost) no inertia;
--   * Reset View goes back to the defaults (and zoom 1) by the short way, then snaps;
--   * stick: radial deadzone 0.18 rescaled to 0..1, response x², 200 / 120 °/s; keys 120 °/s; wheel 1.12 per notch
--     (wheel up = closer); triggers 1.5×/s (R2 in, L2 out); pinch startZoom × startDist / currentDist, clamped;
--   * tap: < 8 px and < 300 ms; tapRay is the exact inverse of ViewportStage.projectPoint; hitsBox scales the ray into
--     the bounding box's unit sphere and ignores hits behind the origin.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local FRAME = 1 / 60

return function(t: Context)
	local expect = t.expect
	local OrbitCamera = t.requireClient("UI/OrbitCamera")
	local ViewportStage = t.requireClient("UI/ViewportStage")
	local Config = t.requireShared("Config")
	local ORBIT = Config.Inspect.Orbit
	local FRAMING = Config.Inspect.Framing
	local INPUT = Config.Inspect.Input

	local function near3(a: Vector3, b: Vector3, tolerance: number?)
		local tol = tolerance or 1e-5
		expect.near(a.X, b.X, tol)
		expect.near(a.Y, b.Y, tol)
		expect.near(a.Z, b.Z, tol)
	end

	-- The shortest angular distance between two angles, in [0, 180].
	local function angleGap(a: number, b: number): number
		local d = math.abs(a - b) % 360
		return math.min(d, 360 - d)
	end

	-- The signed turn from `from` to `to`, in [-180, 180).
	local function signedGap(from: number, to: number): number
		return (to - from + 180) % 360 - 180
	end

	local function settle(s: any, seconds: number?)
		for _ = 1, math.ceil((seconds or 2) / FRAME) do
			OrbitCamera.step(s, FRAME)
		end
	end

	-- new, wrap and clamps ------------------------------------------------------------------------------------------

	t.test("new: current = target = the defaults, zoom 1, at rest", function()
		local s = OrbitCamera.new(25, 12)
		expect.equal(s.yaw, 25)
		expect.equal(s.pitch, 12)
		expect.equal(s.zoom, 1)
		expect.equal(s.targetYaw, 25)
		expect.equal(s.targetPitch, 12)
		expect.equal(s.targetZoom, 1)
		expect.equal(s.defaultYaw, 25)
		expect.equal(s.defaultPitch, 12)
		expect.equal(s.inertia, 0)
		expect.equal(s.yawVelocity, 0)
		expect.equal(s.pitchVelocity, 0)
		expect.equal(s.zoomVelocity, 0)
		expect.equal(s.resetting, false)
		expect.equal(s.dragging, false)
		-- Missing or non-finite angles use Config.Inspect.Orbit's defaults.
		local fallback = OrbitCamera.new(nil, 0 / 0)
		expect.equal(fallback.yaw, ORBIT.defaultYawDeg)
		expect.equal(fallback.pitch, ORBIT.defaultPitchDeg)
		-- The yaw wraps and the pitch is clamped.
		local odd = OrbitCamera.new(-30, 100)
		expect.near(odd.yaw, 330, 1e-9)
		expect.equal(odd.pitch, ORBIT.pitchMaxDeg)
		expect.equal(odd.defaultPitch, ORBIT.pitchMaxDeg)
	end)

	t.test("wrapYaw: any angle to [0, 360)", function()
		expect.near(OrbitCamera.wrapYaw(370), 10, 1e-9)
		expect.near(OrbitCamera.wrapYaw(-10), 350, 1e-9)
		expect.equal(OrbitCamera.wrapYaw(360), 0)
		expect.equal(OrbitCamera.wrapYaw(0), 0)
		expect.equal(OrbitCamera.wrapYaw(-720), 0)
		expect.near(OrbitCamera.wrapYaw(725.5), 5.5, 1e-9)
		expect.equal(OrbitCamera.wrapYaw(0 / 0), 0)
		expect.equal(OrbitCamera.wrapYaw(math.huge), 0)
		for _, deg in { -1e-15, -359.999, 1e6 + 0.25, -1e6 } do
			local wrapped = OrbitCamera.wrapYaw(deg)
			expect.truthy(wrapped >= 0 and wrapped < 360)
		end
	end)

	t.test("pitch is clamped to [pitchMinDeg, pitchMaxDeg] and zoom to [zoomMin, zoomMax]", function()
		local s = OrbitCamera.new(25, 12)
		OrbitCamera.rotate(s, 0, 500)
		expect.equal(s.targetPitch, ORBIT.pitchMaxDeg)
		settle(s)
		expect.near(s.pitch, ORBIT.pitchMaxDeg, 1e-3)
		OrbitCamera.rotate(s, 0, -1000)
		expect.equal(s.targetPitch, ORBIT.pitchMinDeg)
		settle(s)
		expect.near(s.pitch, ORBIT.pitchMinDeg, 1e-3)
		-- A drag clamps too.
		OrbitCamera.beginDrag(s)
		OrbitCamera.drag(s, 0, 10000, 400, FRAME)
		OrbitCamera.endDrag(s, true)
		expect.equal(s.targetPitch, ORBIT.pitchMaxDeg)

		OrbitCamera.zoomBy(s, 0.01)
		expect.equal(s.targetZoom, FRAMING.zoomMin)
		OrbitCamera.zoomBy(s, 100)
		expect.equal(s.targetZoom, FRAMING.zoomMax)
		settle(s)
		expect.near(s.zoom, FRAMING.zoomMax, 1e-4)
		-- Bad factors change nothing.
		OrbitCamera.zoomBy(s, 0)
		OrbitCamera.zoomBy(s, -2)
		OrbitCamera.zoomBy(s, 0 / 0)
		expect.equal(s.targetZoom, FRAMING.zoomMax)
		OrbitCamera.setZoom(s, 0.8)
		expect.near(s.targetZoom, 0.8, 1e-12)
		OrbitCamera.setZoom(s, 9)
		expect.equal(s.targetZoom, FRAMING.zoomMax)
	end)

	t.test("yaw is continuous inside, wrapped on output, and never takes the long way", function()
		local s = OrbitCamera.new(350, 0)
		OrbitCamera.rotate(s, 20, 0)
		for _ = 1, 120 do
			local yaw = OrbitCamera.step(s, FRAME)
			expect.truthy(yaw >= 0 and yaw < 360)
			expect.truthy(angleGap(yaw, 350) <= 20 + 1e-6)
			expect.truthy(angleGap(yaw, 10) <= 20 + 1e-6)
		end
		local yaw = OrbitCamera.view(s)
		expect.near(yaw, 10, 1e-3)
		-- Many turns stay small inside.
		OrbitCamera.rotate(s, 3600 + 45, 0)
		settle(s)
		expect.near(OrbitCamera.view(s), 55, 1e-3)
		expect.truthy(math.abs(s.yaw) <= 360 and math.abs(s.targetYaw) <= 720)
	end)

	-- smoothDamp -------------------------------------------------------------------------------------------------------

	t.test("smoothDamp converges to the target without overshoot", function()
		local value, velocity = 0, 0
		local previous = value
		for _ = 1, 60 do
			value, velocity = OrbitCamera.smoothDamp(value, 10, velocity, ORBIT.rotateSmoothSeconds, FRAME)
			expect.truthy(value >= previous - 1e-12)
			expect.truthy(value <= 10)
			previous = value
		end
		expect.near(value, 10, 1e-3)
		-- Downward too.
		local down, downVelocity = 5, 0
		for _ = 1, 60 do
			down, downVelocity = OrbitCamera.smoothDamp(down, -3, downVelocity, ORBIT.zoomSmoothSeconds, FRAME)
			expect.truthy(down >= -3)
		end
		expect.near(down, -3, 1e-2)
		-- dt <= 0 changes nothing; at the target at rest it stays there.
		local same, sameVelocity = OrbitCamera.smoothDamp(4, 9, 2, 0.1, 0)
		expect.equal(same, 4)
		expect.equal(sameVelocity, 2)
		local rest, restVelocity = OrbitCamera.smoothDamp(7, 7, 0, 0.1, FRAME)
		expect.equal(rest, 7)
		expect.equal(restVelocity, 0)
	end)

	t.test("smoothDamp is nearly independent of the frame rate", function()
		-- 0.1 s: 3 frames at 30 fps, 24 at 240 fps.
		local function run(fps: number): number
			local value, velocity = 0, 0
			for _ = 1, math.floor(0.1 * fps + 0.5) do
				value, velocity = OrbitCamera.smoothDamp(value, 1, velocity, ORBIT.rotateSmoothSeconds, 1 / fps)
			end
			return value
		end
		local slow, fast = run(30), run(240)
		expect.near(slow, fast, 0.03)
		-- Critically damped with omega = 2 / T: after t, 1 - (1 + omega·t)·e^(-omega·t) of the way.
		local wt = 2 / ORBIT.rotateSmoothSeconds * 0.1
		expect.near(fast, 1 - (1 + wt) * math.exp(-wt), 0.02)
	end)

	-- Drag, inertia, rotate --------------------------------------------------------------------------------------------

	t.test("drag: yaw = dx/H × dragYawDegPerHeight (front follows), pitch = dy/H × dragPitchDegPerHeight", function()
		local s = OrbitCamera.new(25, 12)
		OrbitCamera.beginDrag(s)
		expect.equal(s.dragging, true)
		OrbitCamera.drag(s, 40, 20, 400, FRAME)
		expect.near(s.targetYaw, 25 - 40 / 400 * INPUT.dragYawDegPerHeight, 1e-9)
		expect.near(s.targetPitch, 12 + 20 / 400 * INPUT.dragPitchDegPerHeight, 1e-9)
		-- A drag with dt = 0 still moves the view.
		OrbitCamera.drag(s, -40, 0, 400, 0)
		expect.near(s.targetYaw, 25, 1e-9)
		-- Bad heights are ignored.
		OrbitCamera.drag(s, 40, 0, 0, FRAME)
		OrbitCamera.drag(s, 0 / 0, 0, 400, FRAME)
		expect.near(s.targetYaw, 25, 1e-9)
		OrbitCamera.endDrag(s, true)
		expect.equal(s.dragging, false)
	end)

	t.test("drag direction: the model's front follows the finger (through ViewportStage.projectPoint)", function()
		local center = Vector3.new(2, 1, -3)
		local pivot = CFrame.Angles(0, math.rad(30), 0)
		local face = center + pivot.LookVector -- a point on the model's front
		local vFov, aspect, distance = FRAMING.vFovDeg, 1.5, 6
		local function faceOnScreen(s: any): Vector2
			local yaw, pitch, zoom = OrbitCamera.view(s)
			local cam = ViewportStage.orbitCFrame(center, pivot, yaw, pitch, distance * zoom)
			local point = ViewportStage.projectPoint(cam, vFov, aspect, face)
			assert(point ~= nil, "the face point is behind the camera")
			return point
		end
		local function dragged(dx: number, dy: number): (Vector2, Vector2)
			local s = OrbitCamera.new(25, 12)
			local before = faceOnScreen(s)
			OrbitCamera.beginDrag(s)
			OrbitCamera.drag(s, dx, dy, 400, FRAME)
			OrbitCamera.endDrag(s, true)
			settle(s, 1)
			return before, faceOnScreen(s)
		end
		local beforeRight, afterRight = dragged(30, 0)
		expect.truthy(afterRight.X > beforeRight.X + 1e-3)
		local beforeLeft, afterLeft = dragged(-30, 0)
		expect.truthy(afterLeft.X < beforeLeft.X - 1e-3)
		local beforeDown, afterDown = dragged(0, 30)
		expect.truthy(afterDown.Y > beforeDown.Y + 1e-3)
		local beforeUp, afterUp = dragged(0, -30)
		expect.truthy(afterUp.Y < beforeUp.Y - 1e-3)
		-- The arrow keys and the stick use the same directions: right / up = a drag right / up.
		local keyYaw, keyPitch = OrbitCamera.keyRates(1, 1)
		expect.truthy(keyYaw < 0 and keyPitch < 0)
		local stickYaw, stickPitch = OrbitCamera.stickRates(1, 0)
		expect.truthy(stickYaw < 0 and stickPitch == 0)
	end)

	t.test("release inertia decays e^(-inertiaDecay·t); none under ReducedMotion", function()
		-- 10 px per frame on a 400 px frame: -7.5° per frame = -450°/s.
		local speed = -10 / 400 * INPUT.dragYawDegPerHeight / FRAME
		local s = OrbitCamera.new(0, 0)
		OrbitCamera.beginDrag(s)
		for _ = 1, 30 do
			OrbitCamera.drag(s, 10, 0, 400, FRAME)
		end
		OrbitCamera.endDrag(s, false)
		expect.near(s.inertia, speed, 0.5)
		local inertia = s.inertia
		local target = s.targetYaw
		OrbitCamera.step(s, 0.1)
		local k = ORBIT.inertiaDecay
		expect.near(s.inertia, inertia * math.exp(-k * 0.1), 1e-6)
		-- step() may shift current and target by whole turns, so compare the signed turn (all glides < 180° here).
		expect.near(signedGap(target, s.targetYaw), inertia * (1 - math.exp(-k * 0.1)) / k, 1e-6)
		settle(s, 5)
		expect.equal(s.inertia, 0)
		-- The whole glide is inertia / k, less the tail dropped below the stop speed (0.5°/s).
		expect.near(signedGap(target, s.targetYaw), inertia / k, 0.5 / k + 1e-6)

		local reduced = OrbitCamera.new(0, 0)
		OrbitCamera.beginDrag(reduced)
		for _ = 1, 30 do
			OrbitCamera.drag(reduced, 10, 0, 400, FRAME)
		end
		OrbitCamera.endDrag(reduced, true)
		expect.equal(reduced.inertia, 0)
		local held = reduced.targetYaw
		settle(reduced, 1)
		expect.near(signedGap(held, reduced.targetYaw), 0, 1e-9) -- no glide (whole-turn shifts aside)
		expect.near(OrbitCamera.view(reduced), OrbitCamera.wrapYaw(held), 1e-3)
	end)

	t.test("a finger that stops before release leaves almost no inertia; a new drag stops a glide", function()
		local s = OrbitCamera.new(0, 0)
		OrbitCamera.beginDrag(s)
		for _ = 1, 30 do
			OrbitCamera.drag(s, 10, 0, 400, FRAME)
		end
		for _ = 1, 30 do
			OrbitCamera.drag(s, 0, 0, 400, FRAME)
		end
		OrbitCamera.endDrag(s, false)
		expect.truthy(math.abs(s.inertia) < 1)

		local glide = OrbitCamera.new(0, 0)
		OrbitCamera.beginDrag(glide)
		for _ = 1, 30 do
			OrbitCamera.drag(glide, 10, 0, 400, FRAME)
		end
		OrbitCamera.endDrag(glide, false)
		expect.truthy(glide.inertia ~= 0)
		OrbitCamera.beginDrag(glide)
		expect.equal(glide.inertia, 0)
	end)

	t.test("rotate turns the target view; snap makes current = target at once", function()
		local s = OrbitCamera.new(25, 12)
		OrbitCamera.rotate(s, 30, -10)
		expect.near(s.targetYaw, 55, 1e-9)
		expect.near(s.targetPitch, 2, 1e-9)
		expect.near(s.yaw, 25, 1e-9)
		OrbitCamera.zoomBy(s, 0.8)
		OrbitCamera.snap(s)
		local yaw, pitch, zoom = OrbitCamera.view(s)
		expect.near(yaw, 55, 1e-9)
		expect.near(pitch, 2, 1e-9)
		expect.near(zoom, 0.8, 1e-9)
		expect.equal(s.yawVelocity, 0)
		expect.equal(s.inertia, 0)
		-- Bad deltas change nothing.
		OrbitCamera.rotate(s, 0 / 0, math.huge)
		expect.near(s.targetYaw, 55, 1e-9)
		expect.near(s.targetPitch, 2, 1e-9)
	end)

	-- Reset View --------------------------------------------------------------------------------------------------------

	t.test("reset: back to the defaults and zoom 1, smoothed, then snapped", function()
		local s = OrbitCamera.new(25, 12)
		OrbitCamera.rotate(s, 100, 30)
		OrbitCamera.zoomBy(s, 0.7)
		settle(s, 1)
		OrbitCamera.reset(s)
		expect.equal(s.resetting, true)
		-- Smoothed with resetSmoothSeconds: not there after one frame.
		OrbitCamera.step(s, FRAME)
		expect.truthy(angleGap(OrbitCamera.view(s), 25) > 1)
		settle(s, 3)
		local yaw, pitch, zoom = OrbitCamera.view(s)
		expect.near(yaw, 25, 1e-6)
		expect.near(pitch, 12, 1e-6)
		expect.near(zoom, 1, 1e-9)
		expect.equal(s.resetting, false)
		expect.equal(s.yawVelocity, 0)
		-- New defaults (a select): setDefaults + reset + snap shows them at once.
		OrbitCamera.setDefaults(s, 200, -10)
		expect.near(OrbitCamera.view(s), 25, 1e-6) -- setDefaults alone does not move the view
		OrbitCamera.reset(s)
		OrbitCamera.snap(s)
		local newYaw, newPitch = OrbitCamera.view(s)
		expect.near(newYaw, 200, 1e-6)
		expect.near(newPitch, -10, 1e-9)
		-- Any input cancels a reset.
		OrbitCamera.reset(s)
		OrbitCamera.rotate(s, 1, 0)
		expect.equal(s.resetting, false)
	end)

	t.test("reset takes the short way round", function()
		local s = OrbitCamera.new(10, 0)
		OrbitCamera.setDefaults(s, 350, 0)
		OrbitCamera.reset(s)
		for _ = 1, 180 do
			local yaw = OrbitCamera.step(s, FRAME)
			expect.truthy(angleGap(yaw, 10) <= 20 + 1e-6)
		end
		expect.near(OrbitCamera.view(s), 350, 1e-6)
	end)

	-- Stick, keys, wheel, triggers, pinch ------------------------------------------------------------------------------

	t.test("stickRates: radial deadzone 0.18 rescaled to 0..1, response x², 200 / 120 °/s", function()
		local yaw, pitch = OrbitCamera.stickRates(0.18, 0)
		expect.equal(yaw, 0)
		expect.equal(pitch, 0)
		yaw, pitch = OrbitCamera.stickRates(0.1, 0.12) -- |v| = 0.156: inside the radial deadzone
		expect.equal(yaw, 0)
		expect.equal(pitch, 0)
		yaw, pitch = OrbitCamera.stickRates(0.15, 0.15) -- |v| = 0.212: outside it although each axis is inside
		expect.truthy(yaw ~= 0 and pitch ~= 0)
		yaw, pitch = OrbitCamera.stickRates(1, 0)
		expect.near(yaw, -INPUT.stickYawDegPerSecond, 1e-9)
		expect.equal(pitch, 0)
		yaw, pitch = OrbitCamera.stickRates(-1, 0)
		expect.near(yaw, INPUT.stickYawDegPerSecond, 1e-9)
		yaw, pitch = OrbitCamera.stickRates(0, 1)
		expect.near(pitch, -INPUT.stickPitchDegPerSecond, 1e-9)
		-- Halfway past the deadzone: 0.5² = a quarter of the full rate.
		yaw = OrbitCamera.stickRates(0.18 + 0.82 / 2, 0)
		expect.near(yaw, -0.25 * INPUT.stickYawDegPerSecond, 1e-9)
		-- A diagonal past full deflection is capped at the full rate along its direction.
		yaw, pitch = OrbitCamera.stickRates(1, 1)
		expect.near(yaw, -math.sqrt(0.5) * INPUT.stickYawDegPerSecond, 1e-9)
		expect.near(pitch, -math.sqrt(0.5) * INPUT.stickPitchDegPerSecond, 1e-9)
		yaw, pitch = OrbitCamera.stickRates(0 / 0, 1)
		expect.equal(yaw, 0)
		expect.equal(pitch, 0)
		-- The DESIGN numbers.
		expect.equal(INPUT.stickDeadzone, 0.18)
		expect.equal(INPUT.stickExponent, 2)
		expect.equal(INPUT.stickYawDegPerSecond, 200)
		expect.equal(INPUT.stickPitchDegPerSecond, 120)
	end)

	t.test("keyRates: 120 °/s per arrow", function()
		local yaw, pitch = OrbitCamera.keyRates(1, 0)
		expect.equal(yaw, -INPUT.keyDegPerSecond)
		expect.equal(pitch, 0)
		yaw, pitch = OrbitCamera.keyRates(-1, -1)
		expect.equal(yaw, INPUT.keyDegPerSecond)
		expect.equal(pitch, INPUT.keyDegPerSecond)
		yaw, pitch = OrbitCamera.keyRates(5, 0 / 0)
		expect.equal(yaw, -INPUT.keyDegPerSecond)
		expect.equal(pitch, 0)
		expect.equal(INPUT.keyDegPerSecond, 120)
	end)

	t.test("wheel, trigger and pinch zoom factors", function()
		-- Wheel: ×1.12 per notch; wheel up (Position.Z > 0) = closer.
		expect.near(OrbitCamera.wheelFactor(1), 1 / 1.12, 1e-12)
		expect.near(OrbitCamera.wheelFactor(-1), 1.12, 1e-12)
		expect.near(OrbitCamera.wheelFactor(3), 1.12 ^ -3, 1e-12)
		expect.equal(OrbitCamera.wheelFactor(0 / 0), 1)
		-- Triggers: 1.5×/s at full press, R2 in / L2 out.
		expect.near(OrbitCamera.triggerFactor(1, 0, 1), 1 / 1.5, 1e-12)
		expect.near(OrbitCamera.triggerFactor(0, 1, 1), 1.5, 1e-12)
		expect.near(OrbitCamera.triggerFactor(1, 0, 0.5), 1.5 ^ -0.5, 1e-12)
		expect.near(OrbitCamera.triggerFactor(0.5, 0.5, 1), 1, 1e-12)
		expect.equal(OrbitCamera.triggerFactor(1, 0, 0), 1)
		expect.near(OrbitCamera.triggerFactor(2, 0, 1), 1 / 1.5, 1e-12) -- pressure is clamped to 1
		-- A second of full R2 one frame at a time = the same zoom as one big step.
		local s = OrbitCamera.new(0, 0)
		for _ = 1, 60 do
			OrbitCamera.zoomBy(s, OrbitCamera.triggerFactor(1, 0, FRAME))
		end
		expect.near(s.targetZoom, 1 / 1.5, 1e-9)
		-- Pinch: startZoom × startDist / currentDist (fingers apart = closer), clamped.
		expect.near(OrbitCamera.pinchZoom(1, 100, 125), 0.8, 1e-12)
		expect.near(OrbitCamera.pinchZoom(1, 100, 80), 1.25, 1e-12)
		expect.equal(OrbitCamera.pinchZoom(1, 100, 400), FRAMING.zoomMin)
		expect.equal(OrbitCamera.pinchZoom(1.4, 100, 50), FRAMING.zoomMax)
		expect.near(OrbitCamera.pinchZoom(1.1, 0, 50), 1.1, 1e-12)
		expect.near(OrbitCamera.pinchZoom(1.1, 100, 0), 1.1, 1e-12)
		expect.equal(INPUT.wheelZoomFactor, 1.12)
		expect.equal(INPUT.triggerZoomPerSecond, 1.5)
		expect.equal(FRAMING.zoomMin, 0.6)
		expect.equal(FRAMING.zoomMax, 1.5)
	end)

	-- Tap ----------------------------------------------------------------------------------------------------------------

	t.test("isTap: < 8 px and < 300 ms", function()
		expect.equal(OrbitCamera.isTap(0, 0), true)
		expect.equal(OrbitCamera.isTap(7.9, 299), true)
		expect.equal(OrbitCamera.isTap(8, 0), false)
		expect.equal(OrbitCamera.isTap(0, 300), false)
		expect.equal(OrbitCamera.isTap(0 / 0, 0), false)
		expect.equal(
			OrbitCamera.isTap(0, 0, { Orbit = ORBIT, Framing = FRAMING, Input = { tapMaxPixels = 2, tapMaxMs = 50 } }),
			true
		)
		expect.equal(
			OrbitCamera.isTap(3, 0, { Orbit = ORBIT, Framing = FRAMING, Input = { tapMaxPixels = 2, tapMaxMs = 50 } }),
			false
		)
	end)

	t.test("tapRay is the exact inverse of ViewportStage.projectPoint", function()
		local center = Vector3.new(1, 2, 3)
		local pivot = CFrame.Angles(0, math.rad(-40), 0)
		local points = {
			Vector2.new(0.5, 0.5),
			Vector2.new(0.1, 0.2),
			Vector2.new(0.93, 0.71),
			Vector2.new(0, 1),
			Vector2.new(1, 0),
		}
		for _, aspect in { 0.5, 1, 16 / 9, 2.4 } do
			for _, view in { { 0, 0 }, { 25, 12 }, { -140, 50 }, { 300, -25 } } do
				local cam = ViewportStage.orbitCFrame(center, pivot, view[1], view[2], 6)
				for _, point in points do
					local origin, direction = OrbitCamera.tapRay(cam, FRAMING.vFovDeg, aspect, point)
					near3(origin, cam.Position)
					expect.near(direction.Magnitude, 1, 1e-6)
					local back = ViewportStage.projectPoint(cam, FRAMING.vFovDeg, aspect, origin + direction * 7)
					assert(back ~= nil, "the ray points behind the camera")
					expect.near(back.X, point.X, 1e-5)
					expect.near(back.Y, point.Y, 1e-5)
				end
				-- And the other way: the ray through a projected world point passes through it.
				local world = center + Vector3.new(0.4, -0.3, 0.2)
				local screen = ViewportStage.projectPoint(cam, FRAMING.vFovDeg, aspect, world)
				assert(screen ~= nil, "the world point is behind the camera")
				local origin, direction = OrbitCamera.tapRay(cam, FRAMING.vFovDeg, aspect, screen)
				local offset = world - origin
				expect.truthy(offset:Dot(direction) > 0)
				expect.near(offset:Cross(direction).Magnitude, 0, 1e-4)
			end
		end
	end)

	t.test("hitsBox: the ray in the box's unit sphere; misses and hits behind the origin are false", function()
		local box, size = CFrame.identity, Vector3.new(2, 2, 2)
		local forward = Vector3.new(0, 0, 1)
		expect.equal(OrbitCamera.hitsBox(Vector3.new(0, 0, -10), forward, box, size), true)
		expect.equal(OrbitCamera.hitsBox(Vector3.new(0.9, 0, -10), forward, box, size), true)
		expect.equal(OrbitCamera.hitsBox(Vector3.new(1.2, 0, -10), forward, box, size), false)
		-- The sphere, not the box: a corner of the box is a miss.
		expect.equal(OrbitCamera.hitsBox(Vector3.new(0.9, 0.9, -10), forward, box, size), false)
		-- Scaled by 1 / half-size: a long box hits further out.
		expect.equal(OrbitCamera.hitsBox(Vector3.new(2.5, 0, -10), forward, box, Vector3.new(6, 2, 2)), true)
		expect.equal(OrbitCamera.hitsBox(Vector3.new(2.5, 0, -10), forward, box, size), false)
		-- Behind the origin: ignored. Inside: a hit.
		expect.equal(OrbitCamera.hitsBox(Vector3.new(0, 0, 10), forward, box, size), false)
		expect.equal(OrbitCamera.hitsBox(Vector3.zero, forward, box, size), true)
		-- A rotated, moved box: its long X axis now lies along world Z.
		local turned = CFrame.new(5, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
		local along = Vector3.new(1, 0, 0)
		expect.equal(OrbitCamera.hitsBox(Vector3.new(-10, 0, 2.5), along, turned, Vector3.new(6, 2, 2)), true)
		expect.equal(
			OrbitCamera.hitsBox(Vector3.new(-10, 0, 2.5), along, CFrame.new(5, 0, 0), Vector3.new(6, 2, 2)),
			false
		)
		-- A zero direction never hits; a flat box still has a thickness.
		expect.equal(OrbitCamera.hitsBox(Vector3.new(0, 0, -10), Vector3.zero, box, size), false)
		expect.equal(OrbitCamera.hitsBox(Vector3.new(0, 5, 0), Vector3.new(0, -1, 0), box, Vector3.new(2, 0, 2)), true)
	end)

	t.test("a tap on the framed model hits; a tap in the frame's corner misses", function()
		local center = Vector3.new(0, 1, 0)
		local size = Vector3.new(2, 2, 1.6)
		local boxCFrame = CFrame.new(center)
		local aspect = 1.4
		local distance = ViewportStage.fitDistance(size, FRAMING.vFovDeg, aspect, FRAMING)
		local cam = ViewportStage.orbitCFrame(center, CFrame.identity, 25, 12, distance)
		local origin, direction = OrbitCamera.tapRay(cam, FRAMING.vFovDeg, aspect, Vector2.new(0.5, 0.5))
		expect.equal(OrbitCamera.hitsBox(origin, direction, boxCFrame, size), true)
		local cornerOrigin, cornerDirection = OrbitCamera.tapRay(cam, FRAMING.vFovDeg, aspect, Vector2.new(0.03, 0.03))
		expect.equal(OrbitCamera.hitsBox(cornerOrigin, cornerDirection, boxCFrame, size), false)
	end)
end
