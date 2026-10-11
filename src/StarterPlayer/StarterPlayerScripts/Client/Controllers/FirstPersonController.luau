--!strict
-- FirstPersonController (client only). First-person spec 2026-10-10 §3.1, §3.8, §3.12. Roblox's own first person
-- (Player.CameraMode = LockFirstPerson; Camera.CameraType stays Custom, so mouse lock, sensitivity, the gamepad stick,
-- touch drag-look, the shake and the FOV punch all keep working) in duels and in the practice range's throw box.
--
-- When (Machine.wanted, pure):
--   * duels: Countdown, Active and SuddenDeath; Result for Config.FirstPerson.resultHoldSeconds (0.4 s, the last hit
--     lands from your eyes) when already in it; today's camera in the queue, Preparing and Positioning, and at once on
--     Returning, Cancelled, Void and the duel view gone;
--   * practice (answer 3): inside the throw box (PracticeController.ZoneChanged / isInZone) while no screen blocks the
--     controls (ControlsController.BlockChanged / isBlocked: any modal, Inspect and the reveal included); it ends
--     practiceExitDelaySeconds (0.3 s) after the zone turns off (walking the box's edge never flips it), at once on a
--     match (SD_MatchId or SD_DuelPhase set: the duel rows take over) or a block, and comes back when the block ends
--     in the box;
--   * never while the session switch is off, the character is dead or removed.
-- Entry: save CameraMode, the min / max zoom, the zoom distance (camera to Focus) and UserInputService.MouseIconEnabled,
--   then LockFirstPerson; the shoulder offset off (ThrowController.setShoulderSuppressed). Roblox glides in; under
--   ReducedMotion the max zoom is held at 0.5 for one frame so it cuts. No CameraController.save() snapshot (it would
--   stop the FOV punch for the whole duel).
-- Exit (idempotent, on every end): CameraMode and MouseIconEnabled back, the min zoom held at the saved distance for one
--   frame (the camera cuts back out to where it was), then the saved min and max; the shoulder offset back.
--   "One frame" is two render steps here, so the camera module reads it whatever the order of the two in a frame.
-- Mouse icon while on: hidden only while MouseBehavior is LockCenter, the Roblox menu is closed and the forfeit
--   dialog is closed (setDialogOpen), so only the reticle shows at the centre and the cursor comes back when the mouse
--   is freed.
-- The switch "First-person duels" (Settings) is session only: on at every join (Config.FirstPerson.defaultOn), never
--   saved and never sent to the server.
-- The look (spec 2026-10-11 §3.8, Machine.look, pure): where the camera is, apart from what this module forces. It is
--   the mode while one is on; otherwise "lobby" while the local Head's LocalTransparencyModifier is at least
--   HEAD_HIDDEN (Roblox's own zoom into the head hides it: the same value at which the held model stops drawing), the
--   character is alive, not in a match, no duel phase, not in the throw box and not blocked, and the exit is not
--   pushing the camera back out to a third-person distance (its restore frames); nil otherwise. The lobby look writes
--   nothing (camera, zoom, cursor, shoulder offset) and does not depend on the switch.
-- The camera machine is pure on the stand-ins its Env gives (FirstPersonController.Machine), so it is unit-tested in
--   Edit mode; the module drives one machine on the real player, camera and services, stepped by a Scheduler render
--   effect only while first person is on or a zoom restore waits.
--
-- API
--   FirstPersonController.isEnabled() -> boolean   the session switch
--   FirstPersonController.setEnabled(on)           Settings' switch (and the Studio debug hook)
--   FirstPersonController.isActive() -> boolean    first person is on now (mode() ~= nil)
--   FirstPersonController.mode() -> Mode?          "duel", "practice" or nil (today's camera)
--   FirstPersonController.Changed                  Signal<Mode?>: fired with the new mode whenever it changes
--   FirstPersonController.look() -> Look?          the camera is in first person: "duel", "practice", or "lobby" (the
--                                                  player's own zoom into the head, spec 2026-10-11 §3.8; it never
--                                                  writes the camera); nil otherwise (the look above)
--   FirstPersonController.LookChanged              Signal<Look?>: fired with the new look whenever it changes (after
--                                                  Changed when both change)
--   FirstPersonController.faceOpponent(distance, height) -> boolean   the Countdown facing: in first person a level
--                                                  look ahead (CameraController.faceForward(countdownPitchDeg));
--                                                  otherwise today's CameraController.faceBehindCharacter
--   FirstPersonController.setDialogOpen(open)      DuelController's forfeit dialog opened or closed (the mouse icon)
-- Require direction (§7): this module requires only CameraController, ThrowController, StateController,
-- ControlsController and PracticeController (plus shared modules); none of them requires it back.

-- Services

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Signal = require(Shared.Util.Signal)

local Scheduler = require(script.Parent.Parent.Anim.Scheduler)
local CameraController = require(script.Parent.CameraController)
local ControlsController = require(script.Parent.ControlsController)
local PracticeController = require(script.Parent.PracticeController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)

-- Types

export type Mode = "duel" | "practice"
export type Look = Mode | "lobby" -- spec 2026-10-11 §3.8

-- The machine's facts that are simply on or off.
export type Flag = "enabled" | "inMatch" | "alive" | "blocked" | "dialogOpen" | "headHidden"

-- What the machine reads and writes. Real: the local player, the current camera, UserInputService, GuiService and the
-- controllers; tests: stand-in tables.
export type Env = {
	now: () -> number,
	player: () -> any?, -- CameraMode, CameraMinZoomDistance, CameraMaxZoomDistance
	camera: () -> any?, -- CFrame, Focus
	input: any, -- MouseIconEnabled, MouseBehavior
	menuOpen: () -> boolean,
	reducedMotion: () -> boolean,
	setShoulderSuppressed: (on: boolean) -> (),
	faceForward: (pitchDeg: number) -> boolean,
	faceBehind: (distance: number, height: number) -> boolean,
	changed: (mode: Mode?) -> (),
	lookChanged: (look: Look?) -> (),
	wake: () -> (), -- the machine wants step() every frame (until step returns false)
}

type Saved = {
	cameraMode: Enum.CameraMode,
	minZoom: number,
	maxZoom: number,
	distance: number,
	mouseIcon: boolean,
}

-- Zoom limits to write back `frame` steps on (the one-frame cuts); nil fields are left alone.
type Restore = { frame: number, min: number?, max: number?, distance: number? }

export type Machine = {
	env: Env,
	-- facts
	enabled: boolean,
	phase: string?,
	inMatch: boolean,
	alive: boolean,
	zone: boolean,
	blocked: boolean,
	dialogOpen: boolean,
	headHidden: boolean,
	-- state
	mode: Mode?,
	look: Look?,
	resultAt: number, -- env.now() when the phase became Result
	zoneOffAt: number, -- env.now() when the zone turned off
	saved: Saved?,
	restore: Restore?,
	frame: number,
}

-- Constants

local FP = Config.FirstPerson
local RESULT_HOLD_S = FP.resultHoldSeconds
local PRACTICE_EXIT_S = FP.practiceExitDelaySeconds
local COUNTDOWN_PITCH_DEG = FP.countdownPitchDeg
local DUEL_PHASES: { [string]: boolean } = { Countdown = true, Active = true, SuddenDeath = true }
local CUT_ZOOM = 0.5 -- Roblox's nearest zoom: the ReducedMotion entry cut
-- Reading: a saved zoom distance within this of CUT_ZOOM is the head (float rounding of camera to Focus).
local ZOOM_EPSILON = 1e-3
-- The local Head's LocalTransparencyModifier from which Roblox's own zoom counts as first person: the value at which
-- HeldSquishyController's HIDDEN_MODIFIER stops drawing the held model (spec 2026-10-11 §3.8).
local HEAD_HIDDEN = 0.99
local RESTORE_STEPS = 2
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_DUEL_PHASE = "SD_DuelPhase"

-- Module table

local FirstPersonController = {}

FirstPersonController.Changed = Signal.new() :: Signal.Signal<Mode?>
FirstPersonController.LookChanged = Signal.new() :: Signal.Signal<Look?>

-- Pure ----------------------------------------------------------------------------------------------------------------

-- Whether the mouse icon shows: hidden only while first person is on, the mouse is locked at the centre and neither
-- the Roblox menu nor the forfeit dialog is open.
function FirstPersonController.mouseIconShown(
	active: boolean,
	behavior: Enum.MouseBehavior,
	menuOpen: boolean,
	dialogOpen: boolean
): boolean
	return not (active and behavior == Enum.MouseBehavior.LockCenter and not menuOpen and not dialogOpen)
end

-- Whether the server's SD_MatchId / SD_DuelPhase attributes say the player is in a match (as PracticeController reads).
function FirstPersonController.inMatchFrom(matchId: unknown, phase: unknown): boolean
	return (type(matchId) == "string" and matchId ~= "") or (type(phase) == "string" and phase ~= "")
end

-- The camera machine ------------------------------------------------------------------------------------------------

local Machine = {}
FirstPersonController.Machine = Machine

function Machine.new(env: Env): Machine
	return {
		env = env,
		enabled = FP.defaultOn,
		phase = nil,
		inMatch = false,
		alive = false,
		zone = false,
		blocked = false,
		dialogOpen = false,
		headHidden = false,
		mode = nil,
		look = nil,
		resultAt = -math.huge,
		zoneOffAt = -math.huge,
		saved = nil,
		restore = nil,
		frame = 0,
	}
end

-- Pure: the mode the facts ask for at `now` (the duel rows win over the practice rows).
function Machine.wanted(m: Machine, now: number): Mode?
	if not m.enabled or not m.alive then
		return nil
	end
	local phase = m.phase
	if phase ~= nil or m.inMatch then
		if phase ~= nil and DUEL_PHASES[phase] then
			return "duel"
		end
		if phase == "Result" and m.mode == "duel" and now - m.resultAt < RESULT_HOLD_S then
			return "duel"
		end
		return nil
	end
	if m.blocked then
		return nil
	end
	if m.zone or (m.mode == "practice" and now - m.zoneOffAt < PRACTICE_EXIT_S) then
		return "practice"
	end
	return nil
end

-- Pure: the look (header): the mode, else "lobby" for the player's own zoom into the head, else nil.
function Machine.look(m: Machine): Look?
	if m.mode ~= nil then
		return m.mode
	end
	if not m.headHidden or not m.alive or m.inMatch or m.phase ~= nil or m.zone or m.blocked then
		return nil
	end
	local r = m.restore
	if r ~= nil and r.min ~= nil and r.distance ~= nil and r.distance > CUT_ZOOM + ZOOM_EPSILON then
		return nil -- the exit pushes the camera back out of the head: not the player's own zoom
	end
	return "lobby"
end

local function writeRestore(m: Machine, r: Restore)
	local player = m.env.player()
	if player == nil then
		return
	end
	if r.min ~= nil then
		player.CameraMinZoomDistance = r.min
	end
	if r.max ~= nil then
		player.CameraMaxZoomDistance = r.max
	end
end

-- Writes a waiting zoom restore now; returns it (nil when none waited).
local function flushRestore(m: Machine): Restore?
	local r = m.restore
	if r ~= nil then
		m.restore = nil
		writeRestore(m, r)
	end
	return r
end

local function enterCamera(m: Machine)
	local env = m.env
	-- An exit still pushing the camera out: its zoom goes back first, and its distance is the one to keep (the camera
	-- may not have moved out yet).
	local pending = flushRestore(m)
	local player = env.player()
	if player == nil then
		return
	end
	local camera = env.camera()
	local distance = if pending and pending.distance
		then pending.distance
		elseif camera then (camera.CFrame.Position - camera.Focus.Position).Magnitude
		else player.CameraMinZoomDistance
	local saved: Saved = {
		cameraMode = player.CameraMode,
		minZoom = player.CameraMinZoomDistance,
		maxZoom = player.CameraMaxZoomDistance,
		distance = distance,
		mouseIcon = env.input.MouseIconEnabled,
	}
	m.saved = saved
	env.setShoulderSuppressed(true)
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	if env.reducedMotion() then
		player.CameraMaxZoomDistance = CUT_ZOOM
		m.restore = { frame = m.frame + RESTORE_STEPS, max = saved.maxZoom }
	end
end

local function exitCamera(m: Machine)
	local saved = m.saved
	if saved == nil then
		return
	end
	m.saved = nil
	m.restore = nil -- an entry cut still waiting: the max goes back below
	local env = m.env
	local player = env.player()
	if player ~= nil then
		player.CameraMode = saved.cameraMode
		if player.CameraMaxZoomDistance ~= saved.maxZoom then
			player.CameraMaxZoomDistance = saved.maxZoom
		end
		player.CameraMinZoomDistance = math.clamp(saved.distance, saved.minZoom, math.max(saved.minZoom, saved.maxZoom))
	end
	env.input.MouseIconEnabled = saved.mouseIcon
	env.setShoulderSuppressed(false)
	m.restore = { frame = m.frame + RESTORE_STEPS, min = saved.minZoom, distance = saved.distance }
end

local function applyIcon(m: Machine)
	local env = m.env
	local input = env.input
	local shown = FirstPersonController.mouseIconShown(m.mode ~= nil, input.MouseBehavior, env.menuOpen(), m.dialogOpen)
	if input.MouseIconEnabled ~= shown then
		input.MouseIconEnabled = shown
	end
end

local function update(m: Machine)
	local env = m.env
	local wanted: Mode? = Machine.wanted(m, env.now())
	if wanted ~= m.mode then
		if m.mode ~= nil then
			exitCamera(m)
		end
		if wanted ~= nil then
			enterCamera(m)
		end
		m.mode = wanted
		env.changed(wanted)
	end
	local look: Look? = Machine.look(m)
	if look ~= m.look then
		m.look = look :: Look?
		env.lookChanged(look :: Look?)
	end
	if m.mode ~= nil then
		applyIcon(m)
	end
	if m.mode ~= nil or m.restore ~= nil then
		env.wake()
	end
end

-- The duel phase (nil: no duel view).
function Machine.setPhase(m: Machine, phase: string?)
	if phase == m.phase then
		return
	end
	if phase == "Result" then
		m.resultAt = m.env.now()
	end
	m.phase = phase
	update(m)
end

-- The practice zone (inside the throw box and not in a match).
function Machine.setZone(m: Machine, inside: boolean)
	if inside == m.zone then
		return
	end
	if not inside then
		m.zoneOffAt = m.env.now()
	end
	m.zone = inside
	update(m)
end

function Machine.setFlag(m: Machine, flag: Flag, on: boolean)
	local facts = m :: any
	if facts[flag] == on then
		return
	end
	facts[flag] = on
	update(m)
end

-- One render frame: a waiting zoom restore, the timers (Result hold, practice exit delay) and the mouse icon. Returns
-- false once nothing needs stepping.
function Machine.step(m: Machine): boolean
	m.frame += 1
	local r = m.restore
	if r ~= nil and m.frame >= r.frame then
		m.restore = nil
		writeRestore(m, r)
	end
	update(m)
	return m.mode ~= nil or m.restore ~= nil
end

-- The Countdown facing. The facts are applied first, so a Countdown heard in the same moment already counts.
function Machine.faceOpponent(m: Machine, distance: number, height: number): boolean
	update(m)
	if m.mode == "duel" then
		return m.env.faceForward(COUNTDOWN_PITCH_DEG)
	end
	return m.env.faceBehind(distance, height)
end

-- Private ---------------------------------------------------------------------------------------------------------

local cleanup: Cleanup.Cleanup? = nil
local job: Scheduler.Handle? = nil
local machine: Machine

machine = Machine.new({
	now = os.clock,
	player = function(): any?
		return Players.LocalPlayer
	end,
	camera = function(): any?
		return Workspace.CurrentCamera
	end,
	input = UserInputService,
	menuOpen = function(): boolean
		return GuiService.MenuIsOpen
	end,
	reducedMotion = function(): boolean
		return GuiService.ReducedMotionEnabled
	end,
	setShoulderSuppressed = ThrowController.setShoulderSuppressed,
	faceForward = CameraController.faceForward,
	faceBehind = CameraController.faceBehindCharacter,
	changed = function(mode: Mode?)
		FirstPersonController.Changed:fire(mode)
	end,
	lookChanged = function(look: Look?)
		FirstPersonController.LookChanged:fire(look)
	end,
	wake = function()
		if job ~= nil then
			return
		end
		job = Scheduler.add(function(): boolean
			local alive = Machine.step(machine)
			if not alive then
				job = nil
			end
			return alive
		end, "render")
	end,
})

-- Public --------------------------------------------------------------------------------------------------------------

function FirstPersonController.isEnabled(): boolean
	return machine.enabled
end

function FirstPersonController.setEnabled(on: boolean)
	Machine.setFlag(machine, "enabled", on == true)
end

function FirstPersonController.isActive(): boolean
	return machine.mode ~= nil
end

function FirstPersonController.mode(): Mode?
	return machine.mode
end

function FirstPersonController.look(): Look?
	return machine.look
end

function FirstPersonController.faceOpponent(distance: number, height: number): boolean
	return Machine.faceOpponent(machine, distance, height)
end

function FirstPersonController.setDialogOpen(open: boolean)
	Machine.setFlag(machine, "dialogOpen", open == true)
end

-- Lifecycle -----------------------------------------------------------------------------------------------------------

function FirstPersonController.init()
	local c = Cleanup.new()
	cleanup = c
	local player = Players.LocalPlayer
	local character = Cleanup.new()
	c:add(character)

	local function readMatch()
		local matchId, phase = player:GetAttribute(ATTR_MATCH_ID), player:GetAttribute(ATTR_DUEL_PHASE)
		Machine.setFlag(machine, "inMatch", FirstPersonController.inMatchFrom(matchId, phase))
	end
	-- Alive while the character has a Humanoid with health; dying or losing the character ends first person at once.
	local function watchHumanoid(humanoid: Humanoid)
		Machine.setFlag(machine, "alive", humanoid.Health > 0)
		character:add(humanoid.Died:Connect(function()
			Machine.setFlag(machine, "alive", false)
		end))
	end
	-- The lobby look's signal: Roblox hides the Head through its LocalTransparencyModifier at its own first person.
	local function watchHead(head: BasePart)
		local function read()
			Machine.setFlag(machine, "headHidden", head.LocalTransparencyModifier >= HEAD_HIDDEN)
		end
		character:add(head:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(read))
		read()
	end
	local function onCharacter(model: Model)
		character:clean()
		Machine.setFlag(machine, "headHidden", false)
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local head = model:FindFirstChild("Head")
		if humanoid then
			watchHumanoid(humanoid)
		else
			Machine.setFlag(machine, "alive", false)
		end
		if head and head:IsA("BasePart") then
			watchHead(head)
		else
			head = nil
		end
		if humanoid and head then
			return
		end
		character:add(model.ChildAdded:Connect(function(child: Instance)
			if humanoid == nil and child:IsA("Humanoid") then
				humanoid = child
				watchHumanoid(child)
			elseif head == nil and child.Name == "Head" and child:IsA("BasePart") then
				head = child
				watchHead(child)
			end
		end))
	end

	c:add(player.CharacterAdded:Connect(onCharacter))
	c:add(player.CharacterRemoving:Connect(function()
		character:clean()
		Machine.setFlag(machine, "alive", false)
		Machine.setFlag(machine, "headHidden", false)
	end))
	c:add(player:GetAttributeChangedSignal(ATTR_MATCH_ID):Connect(readMatch))
	c:add(player:GetAttributeChangedSignal(ATTR_DUEL_PHASE):Connect(readMatch))
	c:add(StateController.DuelChanged:connect(function(view: StateController.DuelView?)
		Machine.setPhase(machine, if view then view.phase else nil)
	end))
	c:add(PracticeController.ZoneChanged:connect(function(inside: boolean)
		Machine.setZone(machine, inside)
	end))
	c:add(ControlsController.BlockChanged:connect(function(blocked: boolean)
		Machine.setFlag(machine, "blocked", blocked)
	end))
	c:add(function()
		Machine.setFlag(machine, "alive", false) -- back to today's camera
		flushRestore(machine)
		local handle = job
		job = nil
		if handle then
			handle:disconnect()
		end
	end)

	readMatch()
	local view = StateController.duel()
	Machine.setPhase(machine, if view then view.phase else nil)
	Machine.setZone(machine, PracticeController.isInZone())
	Machine.setFlag(machine, "blocked", ControlsController.isBlocked())
	if player.Character then
		onCharacter(player.Character)
	end
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function FirstPersonController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return FirstPersonController
