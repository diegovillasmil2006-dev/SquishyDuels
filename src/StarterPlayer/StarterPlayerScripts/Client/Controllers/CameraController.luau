--!strict
-- CameraController (client only). DESIGN §2.4, §9.12, §10.4 steps 2-4, §10.10, §18.4.3.
-- Save and restore the camera and cursor state around features that take the camera (Inspect, box reveal, duel
-- transitions), the angular camera shake and the attacker's FOV punch. The Countdown facing: faceBehindCharacter
-- (today's camera) or faceForward (first person, a level look ahead; first-person spec 2026-10-10 §3.1).
--
--   local snapshot = CameraController.save()      -- before changing anything
--   ... camera.CameraType = Enum.CameraType.Scriptable ...
--   CameraController.restore(snapshot)            -- idempotent: a second restore of the same snapshot is a no-op
--   CameraController.shake(0.5, 0.2)              -- §9.8 hit received: 0.5° for 200 ms
--   CameraController.punch(-2.5, 50, 200)         -- §18.4.3 hit dealt: FOV −2.5° in 50 ms, back in 200 ms
--
-- FOV punch (§18.4.3, Config.Vfx.Punch): the offset goes 0 -> delta by attackMs (Quad Out), then back to 0 by
-- attackMs + releaseMs (Sine InOut); |delta| is clamped to maxFovDeg (4°). A Scheduler render effect writes only
-- FieldOfView = base + offset (the camera module never writes the FOV, so no undo binding is needed and the shake
-- stays §9.12's single exception). The base is captured only when no punch runs; a new punch replaces the running
-- one only when |delta| >= the offset left, and keeps the same base (reading: its attack starts from the offset still
-- on the camera, so the FieldOfView never jumps). At the end FieldOfView is the base exactly. It
-- runs only while CameraType is Custom and no save() snapshot is open (saved and not yet restored); a save() during
-- a punch stops it first, so the snapshot holds the base. Off under ReducedMotion (callers also skip it when
-- settings.cameraShake is false, as for the shake). Reading (DESIGN is silent): a camera that leaves Custom mid-punch
-- gets the base back at once; when something else changed the FOV mid-punch, its value wins and the punch ends
-- without a write. The punch maths (punchOffset, punchStart, punchStep, punchStop, snapshotOf) are pure on a camera
-- passed in, so tests use a stand-in table.
--
-- Shake (§9.12, Config.Vfx.Shake): RunService:BindToRenderStep("SD_Shake", Camera + 1) is the one documented exception
-- to the PreRender rule (§2.11). Each frame while a shake runs and the camera is Custom: cam.CFrame *= CFrame.Angles(nx·a,
-- ny·a, nz·a·rollFactor), math.noise at noiseHz, a = amp·(1 − t/dur)², amp clamped to maxAmplitudeDeg. Off under
-- GuiService.ReducedMotionEnabled (callers also skip it when settings.cameraShake is false). Reading (DESIGN gives no
-- rule for overlaps): a new shake replaces the running one only when it is at least as strong as what is left of it.
-- No drift: the default camera module builds each frame's CFrame from the CURRENT camera's look vector, so a shake left
-- in place would add up into a lasting aim offset. The offset applied in a frame is therefore taken off again before
-- the camera module runs the next frame, by the same shake mechanism at Camera − 1 ("SD_ShakeUndo"; reading: the
-- second half of the §9.12 exception, removeShake). Both bindings are removed when the shake and its undo are over.
--
-- World FOV owner (spec 2026-10-11 §3.4, §3.5: the first-person overlay's focus narrowing and release kick): one owner
-- at a time puts an offset on the current camera's FOV. setFovOffset(owner, offsetDeg) writes FieldOfView = base +
-- offset, the base read when its hold starts; an offset of 0 ends the hold with the base written back exactly. It is
-- refused, and a hold this owner had ends the same way, under ReducedMotion, while a save() snapshot is open, while a
-- punch runs (punch() and save() end a hold first, so they read the true base), on a camera that is not Custom, or
-- while another owner holds it. A FOV that something else changed mid-hold wins: the hold ends without a write. The
-- hold maths (fovHoldStep, fovHoldStop) are pure on a camera passed in, as the punch's.
--
-- Saved: CameraType, CameraSubject, CFrame, FieldOfView of Workspace.CurrentCamera at save time, and
-- UserInputService.MouseIconEnabled. MouseBehavior is never saved or written (the default camera scripts own it, and
-- a modal button with Modal = true frees the cursor, §10.4 step 4). On restore the camera is the CURRENT camera; a
-- subject that is gone (respawn) falls back to the local character's Humanoid, and the CFrame is written back only
-- when the restored type is not Custom/Follow-like (the camera module rebuilds those itself).

-- Services

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

local Scheduler = require(script.Parent.Parent.Anim.Scheduler)

-- Types

export type Snapshot = {
	cameraType: Enum.CameraType,
	cameraSubject: Instance?,
	cframe: CFrame,
	fieldOfView: number,
	mouseIconEnabled: boolean,
	restored: boolean,
	counted: boolean?, -- made by save(): open until restored (no punch starts meanwhile)
}

type ShakeState = {
	amplitudeDeg: number,
	seconds: number,
	startedAt: number, -- os.clock()
	seed: number,
}

-- One FOV punch (Config.Vfx.Punch.hitDealt and the like).
export type PunchSpec = { fovDeg: number, attackMs: number, releaseMs: number }

-- A punch in progress on one camera (newPunchState). base = the FOV without the punch; written = the FOV the punch
-- wrote last (read back, so float rounding never looks like another writer).
export type PunchState = {
	spec: PunchSpec?,
	startedAt: number,
	base: number?,
	written: number?,
	from: number?, -- the offset left by the punch this one replaced (its attack starts there)
}

-- A world FOV hold (newFovHold): owner = who holds it (nil = none), base = the FOV without the offset, written = the
-- FOV the hold wrote last (read back).
export type FovHold = { owner: string?, base: number?, written: number? }

-- Constants

local SHAKE = Config.Vfx.Shake
local PUNCH = Config.Vfx.Punch
local PUNCH_LIMIT = math.min(PUNCH.maxFovDeg, 4) -- §18.9: never over 4°
local SEED_STEP = 7.31 -- keeps successive shakes on different noise rows (math.noise is 0 at integer points)
-- reading (not in DESIGN): a FieldOfView further than this from the punch's last write was changed by someone else.
local FOV_FOREIGN_EPSILON = 1e-3

-- Camera types driven by the camera module every frame (their CFrame must not be written back).
local MODULE_DRIVEN: { [Enum.CameraType]: boolean } = {
	[Enum.CameraType.Custom] = true,
	[Enum.CameraType.Follow] = true,
	[Enum.CameraType.Track] = true,
	[Enum.CameraType.Attach] = true,
	[Enum.CameraType.Watch] = true,
	[Enum.CameraType.Orbital] = true,
}

-- Module table

local CameraController = {}

-- Private

local currentShake: ShakeState? = nil
local shakeBound = false
local shakeCount = 0
local lastOffset: CFrame? = nil -- the rotation the last shake frame applied, still on the camera
local livePunch: PunchState = { spec = nil, startedAt = 0, base = nil, written = nil, from = nil }
local punchCamera: Camera? = nil -- the camera the live punch writes
local punchHandle: Scheduler.Handle? = nil
local openSnapshots = 0 -- save() snapshots not restored yet: no punch starts while any is open
local liveFov: FovHold = { owner = nil, base = nil, written = nil }
local fovCamera: Camera? = nil -- the camera the live FOV hold writes

local function localHumanoid(): Humanoid?
	local player = Players.LocalPlayer
	local character = player and player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function subjectIsUsable(subject: Instance?): boolean
	return subject ~= nil and subject:IsDescendantOf(Workspace)
end

-- What is left of a shake's amplitude (degrees) `t` seconds in: amp·(1 − t/dur)², 0 from the end.
local function fadedAmplitude(amplitudeDeg: number, seconds: number, t: number): number
	if not (seconds > 0) or t < 0 or t >= seconds then
		return 0
	end
	local fade = 1 - t / seconds
	return math.clamp(amplitudeDeg, 0, SHAKE.maxAmplitudeDeg) * fade * fade
end

-- The shake rotation (radians about X, Y, Z) `t` seconds into a shake: smooth noise at noiseHz, each axis clamped to
-- ±1 so no axis exceeds the faded amplitude; the roll axis is scaled by rollFactor.
local function shakeAnglesAt(amplitudeDeg: number, seconds: number, t: number, seed: number): (number, number, number)
	local a = math.rad(fadedAmplitude(amplitudeDeg, seconds, t))
	if a <= 0 then
		return 0, 0, 0
	end
	local u = t * SHAKE.noiseHz
	local nx = math.clamp(math.noise(u, seed, 0.5), -1, 1)
	local ny = math.clamp(math.noise(u, seed + 0.5, 1.5), -1, 1)
	local nz = math.clamp(math.noise(u, seed + 1.5, 2.5), -1, 1)
	return nx * a, ny * a, nz * a * SHAKE.rollFactor
end

local function unbindShake()
	if shakeBound then
		shakeBound = false
		RunService:UnbindFromRenderStep(SHAKE.bindName)
		RunService:UnbindFromRenderStep(SHAKE.undoBindName)
	end
end

-- Camera − 1, before the camera module: takes last frame's shake off, so the module reads the unshaken look vector.
local function onUndoFrame()
	local offset = lastOffset
	if offset == nil then
		return
	end
	lastOffset = nil
	local camera = Workspace.CurrentCamera
	if camera ~= nil and camera.CameraType == Enum.CameraType.Custom then
		camera.CFrame = CameraController.removeShake(camera.CFrame, offset)
	end
end

-- Camera + 1, after the camera module: puts this frame's shake on. Unbinds once the shake is over and its last
-- offset was taken off.
local function onShakeFrame()
	local s = currentShake
	local t = if s then os.clock() - s.startedAt else math.huge
	if s == nil or t >= s.seconds then
		currentShake = nil
		if lastOffset == nil then
			unbindShake()
		end
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == nil or camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local x, y, z = shakeAnglesAt(s.amplitudeDeg, s.seconds, t, s.seed)
	local shaken, offset = CameraController.applyShake(camera.CFrame, x, y, z)
	camera.CFrame = shaken
	lastOffset = offset
end

local function quadOut(u: number): number
	local x = math.clamp(u, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

local function sineInOut(u: number): number
	local x = math.clamp(u, 0, 1)
	return -(math.cos(math.pi * x) - 1) / 2
end

local function clampedDelta(deltaDeg: number): number
	if deltaDeg ~= deltaDeg then
		return 0
	end
	return math.clamp(deltaDeg, -PUNCH_LIMIT, PUNCH_LIMIT)
end

local function punchSeconds(spec: PunchSpec): number
	return (math.max(spec.attackMs, 0) + math.max(spec.releaseMs, 0)) / 1000
end

local function stopLivePunch()
	CameraController.punchStop(livePunch, punchCamera)
	punchCamera = nil
	local handle = punchHandle
	if handle then
		punchHandle = nil
		handle:disconnect()
	end
end

local function stopLiveFov()
	CameraController.fovHoldStop(liveFov, fovCamera)
	fovCamera = nil
end

-- Public

-- Pure (unit-tested): a snapshot of `camera` and the cursor. A punch running on that camera (`state`) is stopped
-- first, so the snapshot holds the base FOV.
function CameraController.snapshotOf(camera: any, state: PunchState?): Snapshot
	if state then
		CameraController.punchStop(state, camera)
	end
	return {
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		cframe = camera.CFrame,
		fieldOfView = camera.FieldOfView,
		mouseIconEnabled = UserInputService.MouseIconEnabled,
		restored = false,
		counted = false,
	}
end

function CameraController.save(): Snapshot
	stopLivePunch() -- the base FOV goes back first, so the snapshot never holds a punch
	stopLiveFov() -- nor a FOV hold's offset
	local snapshot = CameraController.snapshotOf(Workspace.CurrentCamera, nil)
	snapshot.counted = true
	openSnapshots += 1
	return snapshot
end

function CameraController.restore(snapshot: Snapshot)
	if snapshot.restored then
		return
	end
	snapshot.restored = true
	if snapshot.counted then
		openSnapshots = math.max(openSnapshots - 1, 0)
	end
	local camera = Workspace.CurrentCamera
	local subject: Instance? = snapshot.cameraSubject
	if not subjectIsUsable(subject) then
		subject = localHumanoid()
	end
	if subject ~= nil and (subject:IsA("Humanoid") or subject:IsA("BasePart")) then
		camera.CameraSubject = subject
	end
	camera.FieldOfView = snapshot.fieldOfView
	camera.CameraType = snapshot.cameraType
	if not MODULE_DRIVEN[snapshot.cameraType] then
		camera.CFrame = snapshot.cframe
	end
	UserInputService.MouseIconEnabled = snapshot.mouseIconEnabled
end

-- The camera CFrame `distance` studs behind and `height` above a root, looking along the root's flat facing. Pure.
function CameraController.behindCFrame(rootCFrame: CFrame, distance: number, height: number): CFrame
	local look = rootCFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else flat.Unit
	local eye = rootCFrame.Position - flat * distance + Vector3.new(0, height, 0)
	return CFrame.lookAt(eye, rootCFrame.Position + flat * distance)
end

-- Duel Countdown: puts a Custom camera behind the local character, facing where it faces (toward the opponent). The
-- default camera module rebuilds each frame from the current camera, so one write turns it. False when it cannot.
function CameraController.faceBehindCharacter(distance: number, height: number): boolean
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if camera == nil or camera.CameraType ~= Enum.CameraType.Custom or root == nil or not root:IsA("BasePart") then
		return false
	end
	camera.CFrame = CameraController.behindCFrame(root.CFrame, distance, height)
	return true
end

-- A camera CFrame at the root looking along its flat facing, pitched `pitchDeg` (negative = down). Pure. In first
-- person only its rotation counts: the camera module puts it at the head (first-person spec 2026-10-10 §3.1).
function CameraController.forwardCFrame(rootCFrame: CFrame, pitchDeg: number): CFrame
	local look = rootCFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else flat.Unit
	local pitch = math.rad(pitchDeg)
	local at = rootCFrame.Position
	return CFrame.lookAt(at, at + flat * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0))
end

-- Duel Countdown in first person: turns a Custom camera to look along the local character's facing (toward the
-- opponent), pitched `pitchDeg`, with one write (the camera module rebuilds from the current look, as for
-- faceBehindCharacter). False when it cannot.
function CameraController.faceForward(pitchDeg: number): boolean
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if camera == nil or camera.CameraType ~= Enum.CameraType.Custom or root == nil or not root:IsA("BasePart") then
		return false
	end
	camera.CFrame = CameraController.forwardCFrame(root.CFrame, pitchDeg)
	return true
end

-- True when the snapshot's values are what the camera and cursor show now (leak/restore checks, §10.11).
function CameraController.matches(snapshot: Snapshot): boolean
	local camera = Workspace.CurrentCamera
	return camera.CameraType == snapshot.cameraType
		and camera.FieldOfView == snapshot.fieldOfView
		and UserInputService.MouseIconEnabled == snapshot.mouseIconEnabled
end

-- Public: shake (§9.12)

-- Pure (unit-tested): the shake rotation in radians about X, Y and Z `t` seconds into a shake of `amplitudeDeg`
-- (clamped to Config.Vfx.Shake.maxAmplitudeDeg) lasting `seconds`; (0, 0, 0) once it is over. `seed` picks the noise.
function CameraController.shakeAngles(
	amplitudeDeg: number,
	seconds: number,
	t: number,
	seed: number
): (number, number, number)
	return shakeAnglesAt(amplitudeDeg, seconds, t, seed)
end

-- Pure (unit-tested): the camera frame with a shake rotation (radians about X, Y, Z) applied, and that rotation (the
-- offset removeShake takes off again).
function CameraController.applyShake(cframe: CFrame, x: number, y: number, z: number): (CFrame, CFrame)
	local offset = CFrame.Angles(x, y, z)
	return cframe * offset, offset
end

-- Pure (unit-tested): the camera frame without a shake offset applyShake put on it.
function CameraController.removeShake(cframe: CFrame, offset: CFrame): CFrame
	return cframe * offset:Inverse()
end

-- Shakes the camera by `amplitudeDeg` (clamped to 1°) for `seconds`. Returns false when nothing starts: bad numbers,
-- ReducedMotion, or a running shake that is still stronger.
function CameraController.shake(amplitudeDeg: number, seconds: number): boolean
	if type(amplitudeDeg) ~= "number" or type(seconds) ~= "number" or not (amplitudeDeg > 0) or not (seconds > 0) then
		return false
	end
	if GuiService.ReducedMotionEnabled then
		return false
	end
	local now = os.clock()
	local amplitude = math.min(amplitudeDeg, SHAKE.maxAmplitudeDeg)
	local running = currentShake
	if running and fadedAmplitude(running.amplitudeDeg, running.seconds, now - running.startedAt) > amplitude then
		return false
	end
	shakeCount += 1
	-- The running shake's table is refilled, not remade: a held squeeze restarts its small shake every frame.
	local state: ShakeState = running or { amplitudeDeg = 0, seconds = 0, startedAt = 0, seed = 0 }
	state.amplitudeDeg, state.seconds, state.startedAt, state.seed = amplitude, seconds, now, shakeCount * SEED_STEP
	currentShake = state
	if not shakeBound then
		shakeBound = true
		RunService:BindToRenderStep(
			SHAKE.undoBindName,
			Enum.RenderPriority.Camera.Value + SHAKE.undoPriorityOffset,
			onUndoFrame
		)
		RunService:BindToRenderStep(
			SHAKE.bindName,
			Enum.RenderPriority.Camera.Value + SHAKE.priorityOffset,
			onShakeFrame
		)
	end
	return true
end

-- True while a shake runs (Studio checks).
function CameraController.isShaking(): boolean
	return currentShake ~= nil
end

-- Public: FOV punch (§18.4.3) -----------------------------------------------------------------------------------------

-- A punch state with nothing running (tests make their own; the module keeps one for the current camera).
function CameraController.newPunchState(): PunchState
	return { spec = nil, startedAt = 0, base = nil, written = nil, from = nil }
end

-- Pure (unit-tested): the FOV offset (degrees) `t` seconds into a punch: 0 -> delta by attackMs (Quad Out), then back
-- to 0 by attackMs + releaseMs (Sine InOut); 0 before the start and after the end. |delta| is clamped to maxFovDeg.
-- `from` (default 0): the offset still on the camera when this punch replaced another one; the attack starts there,
-- so the FieldOfView never jumps (reading: DESIGN says only "replaces").
function CameraController.punchOffset(t: number, spec: PunchSpec, from: number?): number
	local delta = clampedDelta(spec.fovDeg)
	local start = math.clamp(from or 0, -PUNCH_LIMIT, PUNCH_LIMIT)
	local attack = math.max(spec.attackMs, 0) / 1000
	local release = math.max(spec.releaseMs, 0) / 1000
	if not (t >= 0) or t >= attack + release then
		return 0
	end
	if t < attack then
		return start + (delta - start) * quadOut(t / attack)
	end
	if release <= 0 then
		return 0
	end
	return delta * (1 - sineInOut((t - attack) / release))
end

-- True while `state` holds a running punch.
function CameraController.punchRunning(state: PunchState): boolean
	return state.spec ~= nil
end

-- Pure on a camera passed in (unit-tested): ends the punch in `state`. When `camera` still shows the punch's last
-- write, its FieldOfView goes back to the base exactly; when something else changed it meanwhile, that value is kept.
function CameraController.punchStop(state: PunchState, camera: any?)
	local base, written = state.base, state.written
	if state.spec ~= nil and camera ~= nil and base ~= nil then
		local fov = camera.FieldOfView
		if written == nil or math.abs(fov - written) <= FOV_FOREIGN_EPSILON then
			camera.FieldOfView = base
		end
	end
	state.spec = nil
	state.base = nil
	state.written = nil
	state.from = nil
	state.startedAt = 0
end

-- Pure on a camera passed in (unit-tested): starts `spec` at `now`. Only a Custom camera punches; a zero delta never
-- starts. The base FOV is captured only when no punch runs; a new punch replaces the running one only when its |delta|
-- is at least the offset still left, and keeps the same base. Returns false when nothing starts.
function CameraController.punchStart(state: PunchState, camera: any, spec: PunchSpec, now: number): boolean
	if camera == nil or camera.CameraType ~= Enum.CameraType.Custom then
		return false
	end
	if type(spec.fovDeg) ~= "number" or type(spec.attackMs) ~= "number" or type(spec.releaseMs) ~= "number" then
		return false
	end
	local delta = clampedDelta(spec.fovDeg)
	if delta == 0 or not (punchSeconds(spec) > 0) then
		return false
	end
	local running = state.spec
	local from = 0
	if running ~= nil then
		local written = state.written
		if written ~= nil and math.abs(camera.FieldOfView - written) > FOV_FOREIGN_EPSILON then
			-- Something else changed the FOV: that value wins; the old punch ends without a write.
			CameraController.punchStop(state, nil)
			running = nil
		else
			from = CameraController.punchOffset(now - state.startedAt, running, state.from)
			if math.abs(delta) < math.abs(from) then
				return false
			end
		end
	end
	if running == nil then
		state.base = camera.FieldOfView
		state.written = camera.FieldOfView
		from = 0
	end
	state.spec = { fovDeg = delta, attackMs = spec.attackMs, releaseMs = spec.releaseMs }
	state.startedAt = now
	state.from = from
	return true
end

-- Pure on a camera passed in (unit-tested): one frame of the punch in `state` at `now`: FieldOfView = base + offset.
-- Returns false once it is over (the base is written back exactly), when the camera left Custom (base back at once)
-- or when something else changed the FOV (left as it is).
function CameraController.punchStep(state: PunchState, camera: any, now: number): boolean
	local spec, base = state.spec, state.base
	if spec == nil or base == nil or camera == nil then
		CameraController.punchStop(state, nil)
		return false
	end
	local written = state.written
	if written ~= nil and math.abs(camera.FieldOfView - written) > FOV_FOREIGN_EPSILON then
		CameraController.punchStop(state, nil)
		return false
	end
	if camera.CameraType ~= Enum.CameraType.Custom then
		CameraController.punchStop(state, camera)
		return false
	end
	local t = now - state.startedAt
	if t >= punchSeconds(spec) then
		CameraController.punchStop(state, camera)
		return false
	end
	camera.FieldOfView = base + CameraController.punchOffset(t, spec, state.from)
	state.written = camera.FieldOfView -- read back: the engine may round
	return true
end

-- The attacker's FOV punch on the current camera: FieldOfView goes `deltaDeg` (clamped to ±maxFovDeg) away from its
-- base in attackMs and back in releaseMs. False when nothing starts: bad numbers, ReducedMotion, an open save()
-- snapshot, a camera that is not Custom, or a running punch that is still stronger. Callers also skip it when
-- settings.cameraShake is false (the same gates as the shake).
function CameraController.punch(deltaDeg: number, attackMs: number, releaseMs: number): boolean
	if type(deltaDeg) ~= "number" or type(attackMs) ~= "number" or type(releaseMs) ~= "number" then
		return false
	end
	if GuiService.ReducedMotionEnabled or openSnapshots > 0 then
		return false
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return false
	end
	if punchCamera ~= nil and punchCamera ~= camera then
		stopLivePunch() -- the camera was replaced: the old one gets its base back
	end
	stopLiveFov() -- a FOV hold yields first, so the punch reads the true base
	local spec: PunchSpec = { fovDeg = deltaDeg, attackMs = attackMs, releaseMs = releaseMs }
	if not CameraController.punchStart(livePunch, camera, spec, os.clock()) then
		return false
	end
	punchCamera = camera
	if punchHandle == nil then
		punchHandle = Scheduler.add(function(_dt: number, now: number): boolean
			local cam = punchCamera
			local alive = cam ~= nil and CameraController.punchStep(livePunch, cam, now)
			if not alive then
				punchHandle = nil
				punchCamera = nil
			end
			return alive
		end, "render")
	end
	return true
end

-- True while a FOV punch runs (Studio checks).
function CameraController.isPunching(): boolean
	return livePunch.spec ~= nil
end

-- Public: world FOV owner (spec 2026-10-11 §3.4, §3.5) ------------------------------------------------------------------

-- A FOV hold with no owner (tests make their own; the module keeps one for the current camera).
function CameraController.newFovHold(): FovHold
	return { owner = nil, base = nil, written = nil }
end

-- Pure on a camera passed in (unit-tested): ends the hold in `state`. When `camera` still shows the hold's last write,
-- its FieldOfView goes back to the base exactly; when something else changed it meanwhile, that value is kept.
function CameraController.fovHoldStop(state: FovHold, camera: any?)
	local base, written = state.base, state.written
	if state.owner ~= nil and camera ~= nil and base ~= nil then
		if written == nil or math.abs(camera.FieldOfView - written) <= FOV_FOREIGN_EPSILON then
			camera.FieldOfView = base
		end
	end
	state.owner = nil
	state.base = nil
	state.written = nil
end

-- Pure on a camera passed in (unit-tested): one write of `owner`'s offset (degrees): FieldOfView = base + offset, the
-- base read when the hold starts. Returns false when nothing is held after it: an offset of 0 (the base back exactly),
-- a camera that is not Custom (the base back), a FOV something else changed (kept, no write) or another owner's hold.
function CameraController.fovHoldStep(state: FovHold, camera: any, owner: string, offsetDeg: number): boolean
	if state.owner ~= nil and state.owner ~= owner then
		return false
	end
	if camera == nil or camera.CameraType ~= Enum.CameraType.Custom or offsetDeg == 0 or offsetDeg ~= offsetDeg then
		CameraController.fovHoldStop(state, camera)
		return false
	end
	local written = state.written
	if state.owner ~= nil and written ~= nil and math.abs(camera.FieldOfView - written) > FOV_FOREIGN_EPSILON then
		CameraController.fovHoldStop(state, nil) -- something else changed the FOV: that value wins
		return false
	end
	if state.owner == nil then
		state.owner = owner
		state.base = camera.FieldOfView
	end
	camera.FieldOfView = (state.base :: number) + offsetDeg
	state.written = camera.FieldOfView -- read back: the engine may round
	return true
end

-- `owner` puts `offsetDeg` on the current camera's FOV (0 ends its hold, the base back exactly). False when nothing is
-- held after it: see the header for the refusals (ReducedMotion, an open snapshot, a punch, not Custom, another owner).
function CameraController.setFovOffset(owner: string, offsetDeg: number): boolean
	local offset = if type(offsetDeg) == "number" and offsetDeg == offsetDeg then offsetDeg else 0
	if GuiService.ReducedMotionEnabled or openSnapshots > 0 or livePunch.spec ~= nil then
		offset = 0
	end
	local camera = Workspace.CurrentCamera
	if fovCamera ~= nil and fovCamera ~= camera and liveFov.owner == owner then
		stopLiveFov() -- the camera was replaced: the old one gets its base back
	end
	local held = CameraController.fovHoldStep(liveFov, camera, owner, offset)
	fovCamera = if liveFov.owner ~= nil then camera else nil
	return held
end

-- Who holds the world FOV now (nil: nobody; Studio checks).
function CameraController.fovOwner(): string?
	return liveFov.owner
end

return CameraController
