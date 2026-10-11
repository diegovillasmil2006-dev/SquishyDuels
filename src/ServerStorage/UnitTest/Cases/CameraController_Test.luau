--!strict
-- CameraController_Test: unit tests for the pure shake maths of StarterPlayerScripts.Client.Controllers.CameraController.
-- Server only (ServerStorage.UnitTest). Edit mode: no shake is started (no BindToRenderStep, no camera writes).
-- Contract (DESIGN §9.8, §9.10, §9.12, Config.Vfx.Shake):
--   * a = amp·(1 − t/dur)²: every axis stays within the faded amplitude, the roll axis within a × rollFactor;
--   * the amplitude is clamped to maxAmplitudeDeg (1°);
--   * nothing is left once the shake is over (t >= dur), before it starts (t < 0) or for a shake without a length;
--   * the noise moves (a shake is not a constant tilt);
--   * no drift: the offset of a frame is taken off before the camera module builds the next frame from the camera's
--     look vector (applyShake / removeShake against a stand-in camera module), so the aim ends where it started;
--   * FOV punch (§18.4.3, Config.Vfx.Punch; on a stand-in camera table): punchOffset is 0 at t = 0, delta at
--     attackMs, 0 at the end, never beyond ±4°; after 50 random punches the base FOV is back exactly; a new punch
--     replaces the running one only when |delta| >= the offset left; nothing unless CameraType is Custom; a snapshot
--     taken mid-punch holds the base;
--   * first person (spec 2026-10-10 §3.1): forwardCFrame looks along the root's flat facing, pitched pitchDeg;
--   * the world FOV owner (spec 2026-10-11 §3.4, §3.5; on a stand-in camera): a hold writes base + offset and the base
--     exactly when its offset goes to 0 or it stops; one owner at a time; only on a Custom camera (leaving Custom puts
--     the base back); a FOV changed by something else wins (no write); stopped first, a punch reads the true base.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPSILON = 1e-12

return function(t: Context)
	local CameraController = t.requireClient("Controllers/CameraController")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local shake = Config.Vfx.Shake

	local function within(value: number, limit: number)
		expect.truthy(math.abs(value) <= limit + EPSILON)
	end

	t.test("every axis stays inside amp·(1 − t/dur)², the roll inside its share", function()
		local spec = shake.hitReceived
		local seconds = spec.ms / 1000
		for i = 0, 40 do
			local at = seconds * i / 40
			local x, y, z = CameraController.shakeAngles(spec.amplitudeDeg, seconds, at, 7.31)
			local fade = math.max(0, 1 - at / seconds)
			local a = math.rad(spec.amplitudeDeg) * fade * fade
			within(x, a)
			within(y, a)
			within(z, a * shake.rollFactor)
		end
	end)

	t.test("the amplitude is clamped to maxAmplitudeDeg", function()
		local limit = math.rad(shake.maxAmplitudeDeg)
		for i = 0, 50 do
			local x, y, z = CameraController.shakeAngles(30, 1, i / 100, 3.7)
			within(x, limit)
			within(y, limit)
			within(z, limit * shake.rollFactor)
		end
	end)

	t.test("nothing is left after the end, before the start or without a length", function()
		for _, case in { { 0.5, 0.2, 0.2 }, { 0.5, 0.2, 5 }, { 0.5, 0.2, -0.01 }, { 0.5, 0, 0 }, { 0.5, -1, 0.1 } } do
			local x, y, z = CameraController.shakeAngles(case[1], case[2], case[3], 1.3)
			expect.equal(x, 0)
			expect.equal(y, 0)
			expect.equal(z, 0)
		end
	end)

	t.test("the shake moves: the angles change over its first half", function()
		local spec = shake.dragonRushNearby
		local seconds = spec.ms / 1000
		local seen: { [string]: boolean } = {}
		local distinct = 0
		for i = 0, 10 do
			local x, y = CameraController.shakeAngles(spec.amplitudeDeg, seconds, seconds * 0.05 * i, 11.9)
			local key = string.format("%.6f|%.6f", x, y)
			if not seen[key] then
				seen[key] = true
				distinct += 1
			end
		end
		expect.truthy(distinct >= 5)
	end)

	-- A stand-in for the default camera module: each frame it orbits the focus along the CURRENT camera's look vector
	-- (ClassicCamera reads Workspace.CurrentCamera.CFrame.LookVector), so whatever rotation is left on the camera
	-- carries into the next frame.
	local FOCUS = Vector3.new(0, 5, 0)
	local function cameraModule(cf: CFrame): CFrame
		return CFrame.lookAt(FOCUS - cf.LookVector * 12, FOCUS)
	end

	-- Runs `frames` frames of a shake (angles per frame from `anglesAt`) and one frame after it, with or without the
	-- undo before the module. Returns the angle (radians) between the final and the starting look vector.
	local function drift(frames: number, anglesAt: (number) -> (number, number, number), undo: boolean): number
		local cf = cameraModule(CFrame.lookAt(Vector3.new(3, 9, 12), FOCUS))
		local start = cf.LookVector
		local last: CFrame? = nil
		for frame = 1, frames + 1 do
			if undo and last then
				cf = CameraController.removeShake(cf, last)
				last = nil
			end
			cf = cameraModule(cf)
			if frame <= frames then
				local x, y, z = anglesAt(frame)
				cf, last = CameraController.applyShake(cf, x, y, z)
			end
		end
		-- |a × b| = sin(angle): well conditioned for the tiny angles checked here (acos of a dot near 1 is not).
		return math.asin(math.clamp(cf.LookVector:Cross(start).Magnitude, 0, 1))
	end

	t.test("no drift: the undo before the camera module leaves the aim where it was", function()
		local tilt = math.rad(0.5)
		local function constant(): (number, number, number)
			return tilt, tilt, 0
		end
		-- Left in place, a shake adds up frame after frame (12 frames of 0.5° is several degrees).
		expect.truthy(drift(12, constant, false) > math.rad(3))
		-- Taken off before the module runs, nothing is left.
		expect.truthy(drift(12, constant, true) < 1e-4)
		-- The real noise shake (hit received, 60 fps) leaves nothing either.
		local spec = shake.hitReceived
		local seconds = spec.ms / 1000
		local frames = math.ceil(seconds * 60)
		local function noise(frame: number): (number, number, number)
			return CameraController.shakeAngles(spec.amplitudeDeg, seconds, (frame - 1) / 60, 7.31)
		end
		expect.truthy(drift(frames, noise, true) < 1e-4)
	end)

	t.test("the shake runs after the camera module and its undo before it", function()
		expect.truthy(shake.priorityOffset > 0)
		expect.truthy(shake.undoPriorityOffset < 0)
		expect.truthy(shake.bindName ~= shake.undoBindName)
	end)

	t.test("the duel camera sits behind the positioned character, looking where it faces", function()
		-- Part 4 test play: pad A at (320, 0, -344) faces +Z toward the opponent; the camera must end up on the -Z side.
		local root = CFrame.lookAt(Vector3.new(320, 3, -344), Vector3.new(320, 3, -300))
		local cam = CameraController.behindCFrame(root, 12, 4)
		expect.truthy((cam.Position - Vector3.new(320, 7, -356)).Magnitude < 1e-3)
		expect.truthy(cam.LookVector.Z > 0.9) -- toward the opponent
		local positioning = Config.Duel.Positioning
		expect.truthy(positioning.CameraBehindStuds > 0)
		expect.truthy(positioning.CameraHeightStuds >= 0)
		-- a root facing straight up still gives a usable camera (falls back to -Z)
		local up = CameraController.behindCFrame(CFrame.lookAt(Vector3.zero, Vector3.new(0, 1, 0)), 12, 4)
		expect.truthy(up.LookVector.Z < -0.9)
	end)

	t.test("first person faces the opponent: the root's flat facing, pitched pitchDeg, at the root", function()
		-- First-person spec 2026-10-10 §3.1: the Countdown facing in first person is a level look ahead (-3°), not the
		-- third-person look from behind (about 9.5° down).
		local root = CFrame.lookAt(Vector3.new(320, 3, -344), Vector3.new(320, 3, -300))
		local pitch = Config.FirstPerson.countdownPitchDeg
		local cam = CameraController.forwardCFrame(root, pitch)
		expect.truthy((cam.Position - root.Position).Magnitude < 1e-3)
		expect.near(cam.LookVector.X, 0, 1e-4)
		expect.near(cam.LookVector.Y, math.sin(math.rad(pitch)), 1e-4)
		expect.near(cam.LookVector.Z, math.cos(math.rad(pitch)), 1e-4)
		-- A root tilted forward still gives a level heading; a root facing straight up falls back to -Z.
		local tilted = CameraController.forwardCFrame(root * CFrame.Angles(-0.4, 0, 0), 0)
		expect.near(tilted.LookVector.Y, 0, 1e-4)
		expect.truthy(tilted.LookVector.Z > 0.999)
		local up = CameraController.forwardCFrame(CFrame.Angles(math.pi / 2, 0, 0), 0)
		expect.truthy(up.LookVector.Z < -0.999)
	end)

	-- FOV punch (§18.4.3) -----------------------------------------------------------------------------------------------

	local punch = Config.Vfx.Punch

	-- A stand-in camera: a plain table with the two properties the punch reads and writes.
	local function standIn(fov: number?, cameraType: Enum.CameraType?): any
		return {
			CameraType = cameraType or Enum.CameraType.Custom,
			FieldOfView = fov or 70,
			CameraSubject = nil,
			CFrame = CFrame.identity,
		}
	end

	t.test("punchOffset: 0 at the start, delta at attackMs, 0 at the end", function()
		for _, spec in { punch.hitDealt, punch.elimDealt, punch.practiceHit } do
			local attack = spec.attackMs / 1000
			local total = (spec.attackMs + spec.releaseMs) / 1000
			expect.near(CameraController.punchOffset(0, spec), 0, 1e-9)
			expect.near(CameraController.punchOffset(attack, spec), spec.fovDeg, 1e-9)
			expect.near(CameraController.punchOffset(total, spec), 0, 1e-9)
			expect.near(CameraController.punchOffset(total + 1, spec), 0, 1e-9)
			expect.near(CameraController.punchOffset(-0.1, spec), 0, 1e-9)
			-- Toward delta on the way in, back on the way out.
			local mid = CameraController.punchOffset(attack + (total - attack) / 2, spec)
			expect.truthy(math.abs(mid) < math.abs(spec.fovDeg))
			expect.truthy(mid * spec.fovDeg > 0)
		end
	end)

	t.test("the offset never goes beyond ±4°", function()
		local wild = { fovDeg = -30, attackMs = 50, releaseMs = 200 }
		for i = 0, 50 do
			local offset = CameraController.punchOffset(i / 200, wild)
			expect.truthy(math.abs(offset) <= math.min(punch.maxFovDeg, 4) + 1e-9)
		end
		expect.near(CameraController.punchOffset(0.05, wild), -math.min(punch.maxFovDeg, 4), 1e-9)
	end)

	t.test("a punch writes base + offset, then the base exactly", function()
		local camera = standIn(70)
		local state = CameraController.newPunchState()
		expect.truthy(CameraController.punchStart(state, camera, punch.hitDealt, 10))
		expect.truthy(CameraController.punchStep(state, camera, 10.05))
		expect.near(camera.FieldOfView, 70 + punch.hitDealt.fovDeg, 1e-9)
		expect.falsy(CameraController.punchStep(state, camera, 10.25))
		expect.equal(camera.FieldOfView, 70)
		expect.falsy(CameraController.punchRunning(state))
	end)

	t.test("after 50 random punches the base FOV is restored exactly", function()
		local rng = Random.new(11)
		local camera = standIn(73.25)
		local state = CameraController.newPunchState()
		local now = 0
		local kinds = { punch.hitDealt, punch.elimDealt, punch.practiceHit }
		for _ = 1, 50 do
			CameraController.punchStart(state, camera, kinds[rng:NextInteger(1, 3)], now)
			for _ = 1, rng:NextInteger(1, 8) do
				now += rng:NextNumber(0.005, 0.05)
				CameraController.punchStep(state, camera, now)
				expect.truthy(math.abs(camera.FieldOfView - 73.25) <= 4 + 1e-9)
			end
		end
		while CameraController.punchStep(state, camera, now) do
			now += 1 / 60
		end
		expect.equal(camera.FieldOfView, 73.25)
	end)

	t.test("a new punch replaces the running one only when it is at least as strong as what is left", function()
		local camera = standIn(70)
		local state = CameraController.newPunchState()
		CameraController.punchStart(state, camera, punch.elimDealt, 0)
		CameraController.punchStep(state, camera, 0.06) -- at its peak: -3.5 left
		-- A weaker punch is refused and the running one goes on.
		expect.falsy(CameraController.punchStart(state, camera, punch.practiceHit, 0.06))
		expect.near(state.spec.fovDeg, punch.elimDealt.fovDeg, 1e-9)
		-- Late in its release, a hit punch is stronger than what is left: it replaces it and keeps the same base.
		CameraController.punchStep(state, camera, 0.3)
		expect.truthy(CameraController.punchStart(state, camera, punch.hitDealt, 0.3))
		expect.equal(state.base, 70)
		-- It starts from the offset still on the camera, so the FOV never jumps.
		local before = camera.FieldOfView
		CameraController.punchStep(state, camera, 0.3)
		expect.near(camera.FieldOfView, before, 1e-6)
		expect.falsy(CameraController.punchStep(state, camera, 1)) -- long over
		expect.equal(camera.FieldOfView, 70)
	end)

	t.test("nothing punches unless the camera is Custom; leaving Custom puts the base back", function()
		local state = CameraController.newPunchState()
		local scripted = standIn(70, Enum.CameraType.Scriptable)
		expect.falsy(CameraController.punchStart(state, scripted, punch.hitDealt, 0))
		expect.equal(scripted.FieldOfView, 70)
		local camera = standIn(70)
		CameraController.punchStart(state, camera, punch.hitDealt, 0)
		CameraController.punchStep(state, camera, 0.05)
		camera.CameraType = Enum.CameraType.Scriptable
		expect.falsy(CameraController.punchStep(state, camera, 0.06))
		expect.equal(camera.FieldOfView, 70)
	end)

	t.test("a snapshot taken mid-punch holds the base, and the punch is over", function()
		local camera = standIn(70)
		local state = CameraController.newPunchState()
		CameraController.punchStart(state, camera, punch.elimDealt, 0)
		CameraController.punchStep(state, camera, 0.06)
		expect.truthy(camera.FieldOfView < 70)
		local snapshot = CameraController.snapshotOf(camera, state)
		expect.equal(snapshot.fieldOfView, 70)
		expect.equal(camera.FieldOfView, 70)
		expect.falsy(CameraController.punchRunning(state))
	end)

	t.test("a FOV changed by something else mid-punch wins; the punch ends without a write", function()
		local camera = standIn(70)
		local state = CameraController.newPunchState()
		CameraController.punchStart(state, camera, punch.hitDealt, 0)
		CameraController.punchStep(state, camera, 0.05)
		camera.FieldOfView = 50
		expect.falsy(CameraController.punchStep(state, camera, 0.06))
		expect.equal(camera.FieldOfView, 50)
	end)

	-- World FOV owner (spec 2026-10-11 §3.4, §3.5) ----------------------------------------------------------------------

	t.test("a FOV hold writes base + offset each step and the base exactly when its offset goes to 0", function()
		local camera = standIn(73.25)
		local state = CameraController.newFovHold()
		expect.truthy(CameraController.fovHoldStep(state, camera, "Viewmodel", -5.5))
		expect.near(camera.FieldOfView, 73.25 - 5.5, 1e-6)
		expect.equal(state.owner, "Viewmodel")
		expect.truthy(CameraController.fovHoldStep(state, camera, "Viewmodel", 0.37))
		expect.near(camera.FieldOfView, 73.25 + 0.37, 1e-6)
		expect.falsy(CameraController.fovHoldStep(state, camera, "Viewmodel", 0))
		expect.equal(camera.FieldOfView, 73.25)
		expect.equal(state.owner, nil)
		-- 50 random offsets, then 0: the base comes back exactly.
		local rng = Random.new(5)
		for _ = 1, 50 do
			CameraController.fovHoldStep(state, camera, "Viewmodel", rng:NextNumber(-6, 4))
		end
		CameraController.fovHoldStop(state, camera)
		expect.equal(camera.FieldOfView, 73.25)
	end)

	t.test("one owner at a time: another owner is refused while a hold is on", function()
		local camera = standIn(70)
		local state = CameraController.newFovHold()
		CameraController.fovHoldStep(state, camera, "Viewmodel", -2)
		expect.falsy(CameraController.fovHoldStep(state, camera, "Other", 3))
		expect.near(camera.FieldOfView, 68, 1e-6)
		expect.falsy(CameraController.fovHoldStep(state, camera, "Other", 0)) -- nor can it release someone else's
		expect.equal(state.owner, "Viewmodel")
		CameraController.fovHoldStop(state, camera)
		expect.truthy(CameraController.fovHoldStep(state, camera, "Other", 3))
		expect.near(camera.FieldOfView, 73, 1e-6)
	end)

	t.test("no hold unless the camera is Custom; leaving Custom puts the base back", function()
		local state = CameraController.newFovHold()
		local scripted = standIn(70, Enum.CameraType.Scriptable)
		expect.falsy(CameraController.fovHoldStep(state, scripted, "Viewmodel", -3))
		expect.equal(scripted.FieldOfView, 70)
		local camera = standIn(70)
		CameraController.fovHoldStep(state, camera, "Viewmodel", -3)
		camera.CameraType = Enum.CameraType.Scriptable
		expect.falsy(CameraController.fovHoldStep(state, camera, "Viewmodel", -3))
		expect.equal(camera.FieldOfView, 70)
		expect.equal(state.owner, nil)
	end)

	t.test("a FOV changed by something else wins; the hold ends without a write", function()
		local camera = standIn(70)
		local state = CameraController.newFovHold()
		CameraController.fovHoldStep(state, camera, "Viewmodel", -3)
		camera.FieldOfView = 50
		expect.falsy(CameraController.fovHoldStep(state, camera, "Viewmodel", -2))
		expect.equal(camera.FieldOfView, 50)
		expect.equal(state.owner, nil)
		CameraController.fovHoldStop(state, camera) -- nothing held: no write
		expect.equal(camera.FieldOfView, 50)
	end)

	t.test("a punch never sees the hold's offset (the base goes back first)", function()
		local camera = standIn(70)
		local hold = CameraController.newFovHold()
		CameraController.fovHoldStep(hold, camera, "Viewmodel", -5.5)
		-- What punch() and save() do before they read the base.
		CameraController.fovHoldStop(hold, camera)
		local state = CameraController.newPunchState()
		expect.truthy(CameraController.punchStart(state, camera, punch.hitDealt, 0))
		expect.equal(state.base, 70)
		-- No live hold in Edit mode: nothing owns the real camera's FOV.
		expect.equal(CameraController.fovOwner(), nil)
	end)
end
