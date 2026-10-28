--!strict
-- MoveFeelController (client only; 2026-10-17, VillasmilGaming: "upgrade the entire movement in duels by taking this
-- video as a reference, add camera shake and insane fast paced movement while still using the dash and double jump";
-- the reference is a Rivals-style first person). The local player's camera feel while moving, numbers in
-- Config.Vfx.MoveFeel:
-- * Speed FOV: the world FOV widens with the horizontal speed (fovTarget; a dash's burst gives the big kick), on a
--   spring. While ViewmodelController's first-person hands show they own the world FOV (their focus and charge), so
--   they take this offset and add it to their own (setFovRelay / fovOffset); otherwise this module holds it
--   (CameraController.setFovOffset "move": refused while another owner, a punch or a save() snapshot has the FOV, which
--   then wins). A dash or double jump that finds the FOV held skips its own FOV punch: the speed term is that kick.
-- * Strafe roll (rollTarget): the camera leans into a sideways run (first person rollDeg, third person rollTpShare).
-- * View bob (first person, on the ground; bobOffset): up and down per step, side to side per stride.
-- * Landing (landDip): after airSeconds in the air a dip (studs down, a little pitch) on a spring; a fall at least
--   hardLandSpeed fast also shakes (Config.Vfx.Shake.landHard through CameraController.shake).
-- The roll, bob and dip are one CFrame offset put on the camera after the camera module and the shake (BindToRenderStep
-- bindName at Camera + priorityOffset) and taken off again before the next frame's camera module and the shake's undo
-- (undoBindName at Camera + undoPriorityOffset): the shake's own no-drift rule (DESIGN §9.12), so the aim never drifts.
-- Nothing is put on while the camera is not Custom (Inspect, the box reveal, the duel transitions). The first-person
-- hands get the same motion, a little more (overlaySway: ViewmodelController multiplies its overlay camera by it).
-- Off (everything relaxes to 0): ReducedMotion, settings.cameraShake false (it is all camera motion), no live character.
-- First person = the camera within FP_FOCUS_STUDS of its Focus (Roblox's own first person puts the Focus at the head).
-- API: fovTarget(speed, walkSpeed), rollTarget(sideSpeed, walkSpeed, firstPerson), bobOffset(phase, amount),
--   landDip(fallSpeed, firstPerson) (pure, unit-tested); fovOffset(), setFovRelay(on), overlaySway(U), state();
--   init(), start(), destroy().

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Spring = require(Shared.Util.Spring)

local Client = script.Parent.Parent
local Tweens = require(Client.Anim.Tweens)
local CameraController = require(script.Parent.CameraController)
local StateController = require(script.Parent.StateController)

-- Constants

local FEEL = Config.Vfx.MoveFeel
local SHAKE = Config.Vfx.Shake
local MOVE_FX = require(Shared.Config.MoveFx)
local FeelFx = require(Client.Anim.FeelFx)
local FOV_OWNER = "move"
local FP_FOCUS_STUDS = 1.5
local MIN_WALK = 8 -- the speed scale never drops below this (a frozen WalkSpeed of 0 would divide by 0)
local REST = 0.001 -- an offset below this is nothing
local TAU = 2 * math.pi

-- Module table

local MoveFeelController = {}

-- Private state

local log = Log.new("MoveFeel")
local started = false
local relay = false -- the first-person hands take the FOV offset
local holding = false -- this module holds the world FOV ("move")
local fovSpring = Spring.new(0, FEEL.fovSpring.omega, FEEL.fovSpring.zeta, 0)
local rollSpring = Spring.new(0, FEEL.rollSpring.omega, FEEL.rollSpring.zeta, 0)
local dipSpring = Spring.new(0, FEEL.dipSpring.omega, FEEL.dipSpring.zeta, 0)
local bobPhase = 0
local bobAmount = 0 -- 0..1: the bob fades in and out
local airTime = 0
local fallSpeed = 0 -- the fastest fall of this air time (studs/s, positive down)
local firstPerson = false
local applied: CFrame? = nil -- the offset on the camera now (taken off before the camera module's next frame)
local last = { roll = 0, bobY = 0, bobX = 0, dip = 0 } -- the frame's parts (the hands' sway)
-- 2026-10-28 physics upgrade (Config.MoveFx.enabled): the design's camera dips, shakes and FOV kicks (Anim/FeelFx
-- envelopes), started by dip() / shake() / fovKick(); they replace the old landing dip and its shake.
local dips: { { spec: any, age: number } } = {}
local shakes: { { spec: any, age: number, phases: { number } } } = {}
local kicks: { { spec: any, age: number } } = {}
local kickFov = 0 -- the kicks' FOV this frame (degrees)
-- Part 2 (Config.HitFx punches): camera-space offset (studs) and turn (degrees) on an envelope.
local punches: { { spec: any, age: number } } = {}
local rng = Random.new()

-- Pure -----------------------------------------------------------------------------------------------------------------

-- The speed FOV in degrees for a horizontal `speed` at `walkSpeed`.
function MoveFeelController.fovTarget(speed: number, walkSpeed: number): number
	if not (speed == speed and speed > 0) then
		return 0
	end
	local walk = math.max(if walkSpeed == walkSpeed then walkSpeed else 0, MIN_WALK)
	local over = speed / walk - FEEL.fovFromShare
	return math.clamp(over * FEEL.fovPerWalk, 0, FEEL.fovMaxDeg)
end

-- The roll in degrees for a sideways speed (studs/s, + = to the camera's right): it leans into the run (a run to the
-- right rolls right: a negative angle about the look axis).
function MoveFeelController.rollTarget(sideSpeed: number, walkSpeed: number, isFirstPerson: boolean): number
	if not (sideSpeed == sideSpeed) then
		return 0
	end
	local walk = math.max(if walkSpeed == walkSpeed then walkSpeed else 0, MIN_WALK)
	local share = if isFirstPerson then 1 else FEEL.rollTpShare
	return -math.clamp(sideSpeed / walk, -1, 1) * FEEL.rollDeg * share
end

-- The bob at `phase` (radians, 2π a stride) times `amount` (0..1): (side, up) in studs. Up dips once a step.
function MoveFeelController.bobOffset(phase: number, amount: number): (number, number)
	local a = math.clamp(if amount == amount then amount else 0, 0, 1)
	return FEEL.swayStuds * a * math.sin(phase), -FEEL.bobStuds * a * (1 - math.cos(2 * phase)) / 2
end

-- The landing's dip in studs (<= 0) after a fall at `speed` studs/s (positive down).
function MoveFeelController.landDip(speed: number, isFirstPerson: boolean): number
	if not (speed == speed and speed > 0) then
		return 0
	end
	local dip = math.min(speed * FEEL.dipPerSpeed, FEEL.dipMaxStuds)
	return -dip * (if isFirstPerson then 1 else FEEL.dipTpShare)
end

-- Private ----------------------------------------------------------------------------------------------------------------

local function feelOn(): boolean
	if Tweens.reducedMotion() then
		return false
	end
	local ok, settings = pcall(StateController.settings)
	return not (ok and type(settings) == "table" and settings.cameraShake == false)
end

local function liveCharacter(): (Humanoid?, BasePart?)
	local player = Players.LocalPlayer
	local character = player and player.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return humanoid, root
end

local function releaseFov()
	if holding then
		holding = false
		CameraController.setFovOffset(FOV_OWNER, 0)
	end
end

local function writeFov(offset: number)
	if relay then
		releaseFov()
		return
	end
	if math.abs(offset) < REST then
		releaseFov()
		return
	end
	if holding or CameraController.fovOwner() == nil then
		holding = CameraController.setFovOffset(FOV_OWNER, offset)
	end
end

local function step(dt: number, camera: Camera)
	local on = feelOn()
	local humanoid, root = liveCharacter()
	local fovGoal, rollGoal = 0, 0
	local moving = false
	local speed = 0
	if on and humanoid and root then
		firstPerson = (camera.CFrame.Position - camera.Focus.Position).Magnitude < FP_FOCUS_STUDS
		local velocity = root.AssemblyLinearVelocity
		local flat = Vector3.new(velocity.X, 0, velocity.Z)
		speed = flat.Magnitude
		local walk = humanoid.WalkSpeed
		fovGoal = MoveFeelController.fovTarget(speed, walk)
		local right = camera.CFrame.RightVector
		local side = Vector3.new(right.X, 0, right.Z)
		if side.Magnitude > 1e-3 then
			rollGoal = MoveFeelController.rollTarget(flat:Dot(side.Unit), walk, firstPerson)
		end
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if grounded then
			if airTime >= FEEL.airSeconds and fallSpeed > 0 and not MOVE_FX.enabled then
				local dip = MoveFeelController.landDip(fallSpeed, firstPerson)
				dipSpring:impulse(dip * FEEL.dipSpring.omega * 2)
				if fallSpeed >= FEEL.hardLandSpeed then
					local ok, err = pcall(CameraController.shake, SHAKE.landHard.amplitudeDeg, SHAKE.landHard.ms / 1000)
					if not ok then
						log:warn("land shake failed:", err)
					end
				end
			end
			airTime, fallSpeed = 0, 0
			moving = firstPerson and speed > 1
			if moving then
				bobPhase = (bobPhase + dt * speed * FEEL.stepsPerStud * math.pi) % (2 * TAU)
			end
		else
			airTime += dt
			fallSpeed = math.max(fallSpeed, -velocity.Y)
		end
	else
		airTime, fallSpeed = 0, 0
	end
	local walkShare = if humanoid then math.min(speed / math.max(humanoid.WalkSpeed, MIN_WALK), 1.2) else 0
	local bobGoal = if moving then walkShare else 0
	local fade = math.min(dt * FEEL.bobFadePerSecond, 1)
	bobAmount += (bobGoal - bobAmount) * fade
	fovSpring:setTarget(fovGoal)
	rollSpring:setTarget(rollGoal)
	local fov = fovSpring:step(dt)
	local roll = rollSpring:step(dt)
	local dip = dipSpring:step(dt)
	local shake = Vector3.zero
	kickFov = 0
	for _, d in dips do
		d.age += dt
		local s = d.spec
		dip -= s.depth * FeelFx.envelope(d.age, s.down, s.hold, s.up, s.downEasing, s.upEasing)
	end
	for _, s in shakes do
		s.age += dt
		shake += FeelFx.shakeAt(s.spec, s.age, s.phases)
	end
	for _, k in kicks do
		k.age += dt
		local s = k.spec
		kickFov += s.delta * FeelFx.envelope(k.age, s.attack, s.hold, s.release, s.attackEasing, s.releaseEasing)
	end
	local punchAt, punchTurn = Vector3.zero, Vector3.zero
	for _, p in punches do
		p.age += dt
		local s = p.spec
		local e = FeelFx.envelope(p.age, s.attack, s.hold, s.release, s.attackEasing, s.releaseEasing)
		punchAt += s.offset * e
		punchTurn += s.rotation * e
	end
	MoveFeelController.prune()
	if not on then
		-- Off: no offset at all (the springs are reset so nothing is left over when it comes back).
		fovSpring:reset(0, 0)
		rollSpring:reset(0, 0)
		dipSpring:reset(0, 0)
		table.clear(dips)
		table.clear(shakes)
		table.clear(kicks)
		table.clear(punches)
		fov, roll, dip, bobAmount, kickFov, shake = 0, 0, 0, 0, 0, Vector3.zero
		punchAt, punchTurn = Vector3.zero, Vector3.zero
	end
	writeFov(fov + kickFov)
	local bobX, bobY = MoveFeelController.bobOffset(bobPhase, bobAmount)
	last.roll, last.bobX, last.bobY, last.dip = roll, bobX, bobY, dip
	if camera.CameraType ~= Enum.CameraType.Custom then
		return
	end
	if
		math.abs(roll) < REST
		and math.abs(bobX) < REST
		and math.abs(bobY) < REST
		and math.abs(dip) < REST
		and shake.Magnitude < REST
		and punchAt.Magnitude < REST
		and punchTurn.Magnitude < REST
	then
		return
	end
	-- The punch first (the design moves the camera along its own axes, then turns it), then the feel's offset.
	local offset = CFrame.new(punchAt)
		* CFrame.Angles(math.rad(punchTurn.X), math.rad(punchTurn.Y), math.rad(punchTurn.Z))
		* CFrame.new(bobX, bobY + dip, 0)
		* CFrame.Angles(math.rad(dip * FEEL.dipPitchPerStud + shake.X), math.rad(shake.Y), math.rad(roll + shake.Z))
	camera.CFrame *= offset
	applied = offset
end

local lastClock = os.clock()

local function onFrame()
	local now = os.clock()
	local dt = math.clamp(now - lastClock, 0, 1 / 20)
	lastClock = now
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local ok, err = pcall(step, dt, camera)
	if not ok then
		log:warn("step failed:", err)
	end
end

-- Takes the last frame's offset off before the camera module builds the next frame from the camera.
local function onUndo()
	local offset = applied
	if offset == nil then
		return
	end
	applied = nil
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType == Enum.CameraType.Custom then
		camera.CFrame *= offset:Inverse()
	end
end

-- Public -----------------------------------------------------------------------------------------------------------------

-- The speed FOV now (degrees) plus the design's FOV kicks: the first-person hands add it to their own world FOV
-- offset while they relay it.
function MoveFeelController.fovOffset(): number
	return if started then fovSpring.position + kickFov else 0
end

-- The design's camera moves (Config.MoveFx dips / shakes / fovs, Config.HitFx punches too; Anim/FeelFx's camera
-- hooks). Each plays once and ends on its own; all of them are off with the rest of the feel (ReducedMotion,
-- settings.cameraShake false).
function MoveFeelController.dip(spec: any)
	if started and feelOn() then
		table.insert(dips, { spec = spec, age = 0 })
	end
end

function MoveFeelController.shake(spec: any)
	if started and feelOn() then
		local phases = {}
		for i = 1, 6 do
			phases[i] = rng:NextNumber() * TAU
		end
		table.insert(shakes, { spec = spec, age = 0, phases = phases })
	end
end

function MoveFeelController.fovKick(spec: any)
	if started and feelOn() then
		table.insert(kicks, { spec = spec, age = 0 })
	end
end

function MoveFeelController.punch(spec: any)
	if started and feelOn() then
		table.insert(punches, { spec = spec, age = 0 })
	end
end

-- Drops the camera moves that have ended.
function MoveFeelController.prune()
	for i = #dips, 1, -1 do
		local s = dips[i].spec
		if dips[i].age >= s.down + s.hold + s.up then
			table.remove(dips, i)
		end
	end
	for i = #shakes, 1, -1 do
		if shakes[i].age >= shakes[i].spec.time then
			table.remove(shakes, i)
		end
	end
	for i = #kicks, 1, -1 do
		local s = kicks[i].spec
		if kicks[i].age >= s.attack + s.hold + s.release then
			table.remove(kicks, i)
		end
	end
	for i = #punches, 1, -1 do
		local s = punches[i].spec
		if punches[i].age >= s.attack + s.hold + s.release then
			table.remove(punches, i)
		end
	end
end

-- True while the own camera is in first person (Roblox's first person puts the Focus at the head).
function MoveFeelController.isFirstPerson(): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - camera.Focus.Position).Magnitude < FP_FOCUS_STUDS
end

-- The first-person hands own the world FOV (true while they show): this module stops holding it.
function MoveFeelController.setFovRelay(on: boolean)
	relay = on == true
	if relay then
		releaseFov()
	end
end

-- The hands' share of the motion as an overlay-camera offset (multiply ViewmodelMath.overlayCamera's frame by it):
-- the hands bob, sway and roll with the camera, a little more. Identity while nothing moves.
function MoveFeelController.overlaySway(U: number): CFrame
	if not started then
		return CFrame.identity
	end
	local bobX, bobY, dip = last.bobX, last.bobY, last.dip
	local scaleX = if FEEL.swayStuds > 0 then FEEL.handSwayDu / FEEL.swayStuds else 0
	local scaleY = if FEEL.bobStuds > 0 then FEEL.handBobDu / FEEL.bobStuds else 0
	local x = bobX * scaleX
	local y = bobY * scaleY + dip * FEEL.handDipPerStud
	local rollShare = if FEEL.rollDeg > 0 then last.roll / FEEL.rollDeg else 0
	local turn = math.rad(rollShare * FEEL.handRollDeg)
	if math.abs(x) < 1e-5 and math.abs(y) < 1e-5 and math.abs(turn) < 1e-5 then
		return CFrame.identity
	end
	return (CFrame.new(Vector3.new(x, y, 0) * U) * CFrame.Angles(0, 0, turn)):Inverse()
end

-- Studio readout.
function MoveFeelController.state(): { [string]: any }
	return {
		started = started,
		relay = relay,
		holding = holding,
		firstPerson = firstPerson,
		fov = fovSpring.position,
		roll = last.roll,
		dip = last.dip,
		bob = bobAmount,
		airTime = airTime,
	}
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------------

function MoveFeelController.init() end

function MoveFeelController.start()
	if started then
		return
	end
	started = true
	lastClock = os.clock()
	RunService:BindToRenderStep(FEEL.undoBindName, Enum.RenderPriority.Camera.Value + FEEL.undoPriorityOffset, onUndo)
	RunService:BindToRenderStep(FEEL.bindName, Enum.RenderPriority.Camera.Value + FEEL.priorityOffset, onFrame)
end

function MoveFeelController.destroy()
	if not started then
		return
	end
	started = false
	RunService:UnbindFromRenderStep(FEEL.bindName)
	RunService:UnbindFromRenderStep(FEEL.undoBindName)
	onUndo()
	releaseFov()
	fovSpring:reset(0, 0)
	rollSpring:reset(0, 0)
	dipSpring:reset(0, 0)
	bobAmount, airTime, fallSpeed = 0, 0, 0
end

return MoveFeelController
