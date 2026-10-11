--!strict
-- AutoDriver (client only, Studio only). DESIGN §2.4, §12 #21, §13.1, §13.4 (T2, T3).
-- Scripted input for automated tests. It never fakes anything: every throw goes through ThrowController.throwAt (the
-- same rules as a key press, the real ThrowRequest remote and the server's ThrowRules), every queue join through
-- NetController.queueJoinAsync (the real QueueJoin remote).
-- Gate (§12 #21): RunService:IsStudio() AND Config.Debug.autoDriver (always false outside Studio); init() and every
-- command check both again and do nothing otherwise. Loaded by the client bootstrap after the controllers.
--
-- Commands (called by Studio/DebugHooks: SD_DebugClient "fire", "ult", "auto", "drive"):
--   fireOnce(target?)    one throw now: nil / "auto" = the opponent in a duel, else the nearest practice target;
--                        "opponent"; "target" (the nearest practice target); "backstop" (the practice backstop's
--                        front face, high enough to pass over the targets: a geometry hit for the jelly ripple and
--                        sfx.impactSoft, DESIGN §18.7, §18.3.7; practice range only); or a TargetId ("target_05")
--   ultimateOnce(target?) the same for the ultimate (Dragon Rush)
--   setAuto(on)          auto-fire on / off. Default OFF: a person playing a forced Studio match throws for
--                        themselves (the user saw "the squishy throws itself"); tests turn it on ("auto", true)
--   state()              a small table for test polling
-- Scenario (Workspace attribute SD_TestScenario, written by the server harness or execute_luau; reading of
-- Config.Debug "acts only on Workspace.SD_TestScenario"): nothing happens on its own while it is empty.
--   "duel_e2e" (T3)      in the lobby and Idle -> QueueJoin, at most every QUEUE_RETRY_SECONDS; in Active /
--                        SuddenDeath -> throws at the opponent whenever a throw is ready (auto-fire)
--   "practice*"          inside the practice zone -> throws at the practice targets in turn (auto-fire)
--   anything else        (the T2 dummy scenarios: dummy_duel, dummy_passive, ...) -> throws at the opponent in Active
--                        / SuddenDeath (auto-fire); no queue join (the server harness starts those matches)
-- The opponent's aim point is its capsule centre: a real player through ThrowController.opponentAimPoint(); the Studio
-- test dummy (not in Players) through its rig in Workspace.SD_TestDummies whose SD_MatchId is this match.
-- Debug strings here are for tests, never shown to players.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local ControlsController = require(Client.Controllers.ControlsController)
local NetController = require(Client.Controllers.NetController)
local PracticeController = require(Client.Controllers.PracticeController)
local StateController = require(Client.Controllers.StateController)
local ThrowController = require(Client.Controllers.ThrowController)

-- Types

export type Mode = "off" | "duel" | "practice" | "fight"
export type TargetInfo = { id: string, distance: number, position: Vector3 }
type Reply = { [string]: any }

-- Constants

local ATTR_SCENARIO = "SD_TestScenario"
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_DUEL_PHASE = "SD_DuelPhase"
local DUMMY_FOLDER = "SD_TestDummies"
local DUMMY_ROOT = "HumanoidRootPart"
local DUEL_SCENARIO = "duel_e2e"
local PRACTICE_PREFIX = "practice"
-- reading (not in DESIGN): a QueueJoin retry interval (the server's requeue cooldown is 3 s, 15 s after a bail).
local QUEUE_RETRY_SECONDS = 4
local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }
local BACKSTOP = "backstop"
-- Reading (§18.7 "fireOnce("backstop")"): aim 1 stud below the backstop's top, so the arc from the throw box clears
-- the practice targets (their capsules reach 6.1 studs) and the ball still meets the front face, at the thrower's Z
-- kept 4 studs inside the backstop's ends.
local BACKSTOP_TOP_MARGIN = 1
local BACKSTOP_END_MARGIN = 4

-- Module table

local AutoDriver = {}

-- Private

local log = Log.new("AutoDriver")
local cleanup: Cleanup.Cleanup? = nil
local autoOn = false -- see setAuto in the header
local nextTargetIndex = 1
local lastQueueAttempt = -math.huge
local queueBusy = false
local stats = {
	throwsSent = 0,
	ultsSent = 0,
	queueJoins = 0,
	lastReason = nil :: string?,
	lastQueueReason = nil :: string?,
}

local function enabled(): boolean
	return RunService:IsStudio() and Config.Debug.autoDriver == true
end

-- Pure helpers ------------------------------------------------------------------------------------------------------

-- What a scenario name asks the driver to do.
function AutoDriver.modeFor(scenario: unknown): Mode
	if type(scenario) ~= "string" or scenario == "" then
		return "off"
	elseif scenario == DUEL_SCENARIO then
		return "duel"
	elseif string.sub(scenario, 1, #PRACTICE_PREFIX) == PRACTICE_PREFIX then
		return "practice"
	end
	return "fight"
end

-- The practice target to aim at: the one with TargetId `wanted`, else the nearest to `from` (nil when none).
function AutoDriver.pickTarget(list: { TargetInfo }, from: Vector3, wanted: string?): TargetInfo?
	if wanted ~= nil then
		for _, target in list do
			if target.id == wanted then
				return target
			end
		end
		return nil
	end
	local best: TargetInfo? = nil
	local bestDistance = math.huge
	for _, target in list do
		local distance = (target.position - from).Magnitude
		if distance < bestDistance then
			best, bestDistance = target, distance
		end
	end
	return best
end

-- The aim point of fireOnce("backstop"): on the practice backstop's front face (+X, toward the throw box), 1 stud
-- below its top, at `from`'s Z kept BACKSTOP_END_MARGIN inside its ends (its middle when `from` is nil).
function AutoDriver.backstopPoint(from: Vector3?): Vector3
	local box = WorldLayout.PracticeRange.backstop
	local half = box.size / 2
	local reach = math.max(half.Z - BACKSTOP_END_MARGIN, 0)
	local z = if from then math.clamp(from.Z, box.position.Z - reach, box.position.Z + reach) else box.position.Z
	return Vector3.new(box.position.X + half.X, box.position.Y + half.Y - BACKSTOP_TOP_MARGIN, z)
end

-- The next target of a round-robin over `list` (sorted by id), and the index after it.
function AutoDriver.nextInTurn(list: { TargetInfo }, index: number): (TargetInfo?, number)
	if #list == 0 then
		return nil, 1
	end
	local i = ((math.max(index, 1) - 1) % #list) + 1
	return list[i], i % #list + 1
end

-- Runtime helpers ---------------------------------------------------------------------------------------------------

local function localPlayer(): Player
	return Players.LocalPlayer
end

local function localRootPosition(): Vector3?
	local character = localPlayer().Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- The Studio test dummy of the current match (T2): its rig carries SD_MatchId like a player.
local function dummyAimPoint(): Vector3?
	local view = StateController.duel()
	if view == nil or not view.opponent.isTestDummy then
		return nil
	end
	local folder = Workspace:FindFirstChild(DUMMY_FOLDER)
	if folder == nil then
		return nil
	end
	for _, rig in folder:GetChildren() do
		if rig:IsA("Model") and rig:GetAttribute(ATTR_MATCH_ID) == view.matchId then
			local root = rig:FindFirstChild(DUMMY_ROOT)
			if root and root:IsA("BasePart") then
				return ThrowController.capsuleCentre(root.Position)
			end
		end
	end
	return nil
end

local function opponentPoint(): Vector3?
	return dummyAimPoint() or ThrowController.opponentAimPoint()
end

local function targetPoint(wanted: string?): (Vector3?, string?)
	local from = localRootPosition()
	if from == nil then
		return nil, nil
	end
	local target = AutoDriver.pickTarget(PracticeController.targets(), from, wanted)
	if target == nil then
		return nil, nil
	end
	return ThrowController.targetCentre(target.position), target.id
end

-- Where to throw for a command argument. Returns the point and a label (debug).
local function resolveAim(target: unknown): (Vector3?, string)
	local wanted = if type(target) == "string" then target else "auto"
	if wanted == "auto" then
		if ControlsController.isContextActive("Duel") then
			return opponentPoint(), "opponent"
		end
		local point, id = targetPoint(nil)
		return point, id or "target"
	elseif wanted == "opponent" then
		return opponentPoint(), "opponent"
	elseif wanted == "target" then
		local point, id = targetPoint(nil)
		return point, id or "target"
	elseif wanted == BACKSTOP then
		if not ControlsController.isContextActive("Practice") then
			return nil, BACKSTOP -- only from the practice throw box (a duel throw never aims at the lobby)
		end
		return AutoDriver.backstopPoint(localRootPosition()), BACKSTOP
	end
	local point, id = targetPoint(wanted)
	return point, id or wanted
end

local function inLobby(): boolean
	local player = localPlayer()
	local matchId = player:GetAttribute(ATTR_MATCH_ID)
	local phase = player:GetAttribute(ATTR_DUEL_PHASE)
	return (matchId == nil or matchId == "") and (phase == nil or phase == "")
end

local function tryQueueJoin()
	if queueBusy or not inLobby() or StateController.queue().state ~= "Idle" then
		return
	end
	local clock = os.clock()
	if clock - lastQueueAttempt < QUEUE_RETRY_SECONDS then
		return
	end
	lastQueueAttempt = clock
	queueBusy = true
	task.spawn(function()
		local ok, result = pcall(NetController.queueJoinAsync)
		queueBusy = false
		stats.queueJoins += 1
		if not ok then
			stats.lastQueueReason = tostring(result)
		elseif result.ok then
			stats.lastQueueReason = nil
		else
			stats.lastQueueReason = result.reason
		end
	end)
end

local function autoThrow(mode: string)
	if mode == "practice" then
		if not ControlsController.isContextActive("Practice") then
			return
		end
		local list = PracticeController.targets()
		local target, nextIndex = AutoDriver.nextInTurn(list, nextTargetIndex)
		if target == nil then
			return
		end
		local ok = ThrowController.throwAt(ThrowController.targetCentre(target.position))
		if ok then
			nextTargetIndex = nextIndex
			stats.throwsSent += 1
		end
		return
	end
	local view = StateController.duel()
	if view == nil or not LIVE_PHASES[view.phase] then
		return
	end
	local point = opponentPoint()
	if point ~= nil and ThrowController.throwAt(point) then
		stats.throwsSent += 1
	end
end

local function step(_dt: number, _clock: number): boolean
	local mode = AutoDriver.modeFor(Workspace:GetAttribute(ATTR_SCENARIO))
	if mode == "off" then
		return true
	end
	if mode == "duel" then
		tryQueueJoin()
	end
	if autoOn then
		autoThrow(mode)
	end
	return true
end

-- Public: commands --------------------------------------------------------------------------------------------------

-- One throw now (see the header for `target`). Returns { ok, reason?, aim, point? }.
function AutoDriver.fireOnce(target: unknown): Reply
	if not enabled() then
		return { ok = false, error = "the AutoDriver is off" }
	end
	local point, label = resolveAim(target)
	if point == nil then
		return { ok = false, error = `nothing to aim at ({label})` }
	end
	local ok, reason = ThrowController.throwAt(point)
	stats.lastReason = reason
	if ok then
		stats.throwsSent += 1
	end
	return { ok = ok, reason = reason, aim = label, point = point }
end

-- The ultimate toward the same aim as fireOnce. Returns { ok, reason?, aim }.
function AutoDriver.ultimateOnce(target: unknown): Reply
	if not enabled() then
		return { ok = false, error = "the AutoDriver is off" }
	end
	local point, label = resolveAim(target)
	if point == nil then
		return { ok = false, error = `nothing to aim at ({label})` }
	end
	local ok, reason = ThrowController.ultimateAt(point)
	stats.lastReason = reason
	if ok then
		stats.ultsSent += 1
	end
	return { ok = ok, reason = reason, aim = label }
end

-- Auto-fire on or off (it only acts while a scenario is set).
function AutoDriver.setAuto(on: boolean)
	autoOn = on
end

function AutoDriver.state(): Reply
	return {
		ok = true,
		enabled = enabled(),
		running = cleanup ~= nil,
		scenario = Workspace:GetAttribute(ATTR_SCENARIO),
		mode = AutoDriver.modeFor(Workspace:GetAttribute(ATTR_SCENARIO)),
		auto = autoOn,
		throwsSent = stats.throwsSent,
		ultsSent = stats.ultsSent,
		queueJoins = stats.queueJoins,
		lastReason = stats.lastReason,
		lastQueueReason = stats.lastQueueReason,
	}
end

-- Lifecycle

function AutoDriver.init()
	if not enabled() then
		return
	end
	local c = Cleanup.new()
	cleanup = c
	c:add(Scheduler.add(step, "render"))
	c:add(function()
		queueBusy = false
	end)
	log:info("ready (acts only while Workspace." .. ATTR_SCENARIO .. " is set)")
end

-- Not called by the bootstrap (the client lives for the session).
function AutoDriver.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return AutoDriver
