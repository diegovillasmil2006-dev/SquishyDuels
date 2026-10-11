--!strict
-- TestHarness (server only, Studio only). DESIGN §12 #21, §13.1, §13.4 T2.
-- The TEST DUMMY opponent for T2 (one real player + a dummy): an R15 rig built with
-- Players:CreateHumanoidModelFromDescriptionAsync (a minimal welded rig if that fails), labelled with
-- Strings.duel.testDummy ("TEST DUMMY (Studio)"), placed in Workspace.SD_TestDummies, collision group SD_Characters,
-- physics owned by the server. It is NEVER in Players, NEVER in the real queue (QueueService.join refuses anything that
-- is not a Player), and NEVER rewarded (it is flagged isTestDummy; DuelService/DuelRewards skip it, and NetService never
-- sends it anything).
-- Gate (§12 #21): RunService:IsStudio() AND Config.Debug.testHarness AND the Workspace attribute SD_TestScenario set to
-- a non-empty string (set from execute_luau(Server), or by SD_DebugServer scenario()/forceMatch(), §13.4). Without all
-- three nothing is built.
--
-- The narrow interface DuelService / CombatService see (a Player-shaped table, so the server code paths for players
-- run unchanged): kind = "testDummy", isTestDummy = true, UserId / userId (negative), Name / DisplayName / displayName,
-- Character / character (the rig), Parent (the Workspace.SD_TestDummies folder while it exists, nil after removal:
-- "present" checks such as CharacterService.teleportAsync and DuelService read `Parent ~= nil`; it is never Players, so
-- a `Parent == Players` check can never mistake it for a real player), squishyId (the starter), GetAttribute /
-- SetAttribute (stored on the rig, so SD_MatchId / SD_DuelPhase show in the Explorer), GetNetworkPing() = 0,
-- RequestStreamAroundAsync (no-op), IsA() = false (it is not a Player instance), CharacterAdded / CharacterRemoving
-- (Connect-able, never fired: the dummy does not respawn), getRoot(). newDummy(rig, parent) builds this adapter alone
-- (unit-tested).
-- Throws: while its match is Active or SuddenDeath, a throwing dummy faces its opponent and calls
-- CombatService.requestThrow(dummy, seq, aimDir, originHint, clientTime) every THROW_EVERY_SECONDS, the same server
-- function the ThrowRequest remote uses (aim from ProjectileMath.solveLaunchDir, so it lands where a player's reticle
-- would); a strafing dummy walks side to side within its half. It never throws outside a match.
-- Scenarios (runScenario / SD_DebugServer scenario(name, ...)):
--   dummy_duel [userId]          the player (default: the first one) vs a throwing, strafing dummy
--   dummy_passive [userId]       same, the dummy stands still and never throws
--   dummy_leave [userId, s]      dummy duel; after s seconds (default 25) the dummy leaves (the leave path)
--   dummy_forfeit [userId, s]    dummy duel; after s seconds (default 25) the dummy forfeits
--   restart [s]                  simulates ServerRestartScheduled s seconds ahead (default 120)
--   clear                        removes every dummy and clears SD_TestScenario
-- A dummy is removed DUMMY_LINGER_SECONDS after its match is over, or once its opponent left the game and it is out of
-- its match.
-- Debug strings here are for tests, never shown to players (the dummy's label is the Strings text).

-- Services

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local ProjectileMath = require(Shared.ProjectileMath)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local Server = script.Parent.Parent
local Services = Server.Services
local CharacterService = require(Services.CharacterService)
local QueueService = require(Services.QueueService)
local ShutdownService = require(Services.ShutdownService)
local WorldService = require(Services.WorldService)

-- Types

type ConnectionLike = { Connected: boolean, Disconnect: (self: any) -> () }
type SignalLike = {
	Connect: (self: any, fn: (...any) -> ()) -> ConnectionLike,
	Once: (self: any, fn: (...any) -> ()) -> ConnectionLike,
}

export type Dummy = {
	kind: string,
	isTestDummy: boolean,
	UserId: number,
	userId: number,
	Name: string,
	DisplayName: string,
	displayName: string,
	Character: Model?,
	character: Model?,
	Parent: Instance?,
	squishyId: string,
	CharacterAdded: SignalLike,
	CharacterRemoving: SignalLike,
	GetAttribute: (self: Dummy, name: string) -> any,
	SetAttribute: (self: Dummy, name: string, value: any) -> (),
	GetNetworkPing: (self: Dummy) -> number,
	RequestStreamAroundAsync: (self: Dummy, position: Vector3, timeout: number?) -> (),
	IsA: (self: Dummy, className: string) -> boolean,
	getRoot: (self: Dummy) -> BasePart?,
	-- Harness state
	throwing: boolean,
	strafe: boolean,
	opponent: any,
	seq: number,
	wasInMatch: boolean,
	alive: boolean,
	attributes: { [string]: any },
}

export type StartOptions = { throwing: boolean?, strafe: boolean? }

-- Constants

local ATTR_SCENARIO = "SD_TestScenario"
local ATTR_PHASE = "SD_DuelPhase"
local FOLDER_NAME = "SD_TestDummies"
local RIG_PREFIX = "SD_TestDummy_"
local ROOT_PART = "HumanoidRootPart"
local FIRST_USER_ID = -100001 -- far below Studio's local test players (-1, -2, ...)
local SPAWN_OFFSET = Vector3.new(8, 4, 0) -- from the duel gate approach point
local THROW_EVERY_SECONDS = 1.5 -- above every catalog cooldown, so a throw is never early
local STRAFE_STUDS = 8
local STRAFE_EVERY_SECONDS = 2
local DEFAULT_SCENARIO_DELAY = 25
local DEFAULT_RESTART_SECONDS = 120
local DUMMY_LINGER_SECONDS = 2
local STEP_SECONDS = 0.25
local ACTIVE_PHASES = { Active = true, SuddenDeath = true }
local FALLBACK_HIP_HEIGHT = 2

-- Module table

local TestHarness = {}

-- Private

local log = Log.new("TestHarness")
local dynamicRequire = require :: (ModuleScript) -> any
local dummies: { Dummy } = {}
local nextUserId = FIRST_USER_ID

local function optionalService(name: string): any
	local module = Services:FindFirstChild(name)
	if module ~= nil and module:IsA("ModuleScript") then
		return dynamicRequire(module)
	end
	return nil
end

local function codeEnabled(): boolean
	return RunService:IsStudio() and Config.Debug.testHarness == true
end

local function armed(): boolean
	local scenario = Workspace:GetAttribute(ATTR_SCENARIO)
	return type(scenario) == "string" and scenario ~= ""
end

local function newSignalLike(): SignalLike
	local inner = Signal.new()
	local function wrap(connection: Signal.Connection): ConnectionLike
		local wrapped = { Connected = true }
		function wrapped.Disconnect(_self: any)
			wrapped.Connected = false
			connection:disconnect()
		end
		return wrapped :: any
	end
	return {
		Connect = function(_self: any, fn: (...any) -> ()): ConnectionLike
			return wrap(inner:connect(fn))
		end,
		Once = function(_self: any, fn: (...any) -> ()): ConnectionLike
			return wrap(inner:once(fn))
		end,
	}
end

local function getFolder(): Instance
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = Workspace
		folder = created
	end
	return folder :: Instance
end

local function weld(part0: BasePart, part1: BasePart, c0: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = c0
	w.Parent = part1
end

-- A minimal R15-flagged rig: root, torso and head welded with explicit C0s (used when the avatar service fails).
local function buildFallbackRig(): Model
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = ROOT_PART
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.Parent = model
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.Parent = model
	weld(root, torso, CFrame.identity)
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Parent = model
	weld(root, head, CFrame.new(0, 1.6, 0))
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = FALLBACK_HIP_HEIGHT
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function buildRigAsync(): Model
	local description = Instance.new("HumanoidDescription")
	local ok, result = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if ok and typeof(result) == "Instance" and result:IsA("Model") then
		return result
	end
	log:warn("avatar rig failed; using the minimal rig:", result)
	return buildFallbackRig()
end

local function rootOf(ref: any): BasePart?
	if type(ref) == "table" and ref.isTestDummy == true then
		return (ref :: Dummy):getRoot()
	end
	if typeof(ref) == "Instance" and ref:IsA("Player") then
		return CharacterService.getRoot(ref)
	end
	return nil
end

local function phaseOf(dummy: Dummy): string
	local phase = dummy:GetAttribute(ATTR_PHASE)
	if type(phase) == "string" and phase ~= "" then
		return phase
	end
	local DuelService = optionalService("DuelService")
	if DuelService ~= nil and type(DuelService.getMatch) == "function" then
		local ok, match = pcall(DuelService.getMatch, dummy)
		if ok and type(match) == "table" and type(match.phase) == "string" then
			return match.phase
		end
	end
	return ""
end

-- The launch direction a player's reticle on `target` would give (ProjectileMath, the same solve as the client).
local function aimDirection(origin: Vector3, target: Vector3, squishyId: string): Vector3
	local def = Catalog.get(squishyId) or Catalog.get(Catalog.starterId())
	if def ~= nil then
		return ProjectileMath.solveLaunchDir(origin, target, def.throw.speed, def.throw.gravity)
	end
	local delta = target - origin
	return if delta.Magnitude > 1e-3 then delta.Unit else Vector3.new(0, 0, 1)
end

local warnedNoThrow = false

local function throwAt(dummy: Dummy, target: BasePart)
	local root = dummy:getRoot()
	if root == nil then
		return
	end
	local flatTarget = Vector3.new(target.Position.X, root.Position.Y, target.Position.Z)
	if (flatTarget - root.Position).Magnitude > 1e-3 then
		root.CFrame = CFrame.lookAt(root.Position, flatTarget)
	end
	local origin = (root.CFrame * CFrame.new(Config.Combat.ReleaseOffset)).Position
	local dir = aimDirection(origin, target.Position, dummy.squishyId)
	local CombatService = optionalService("CombatService")
	if CombatService == nil or type(CombatService.requestThrow) ~= "function" then
		if not warnedNoThrow then
			warnedNoThrow = true
			log:warn("CombatService.requestThrow missing; the dummy cannot throw")
		end
		return
	end
	dummy.seq += 1
	local ok, err = pcall(CombatService.requestThrow, dummy, dummy.seq, dir, origin, Workspace:GetServerTimeNow())
	if not ok then
		log:warn("dummy throw failed:", err)
	end
end

local function destroyDummy(dummy: Dummy)
	if not dummy.alive then
		return
	end
	dummy.alive = false
	local rig = dummy.Character
	dummy.Character = nil
	dummy.character = nil
	dummy.Parent = nil
	if rig then
		rig:Destroy()
	end
	local index = table.find(dummies, dummy)
	if index then
		table.remove(dummies, index)
	end
end

-- The dummy's life: throws and strafes while Active, leaves after its match or when its opponent left.
local function run(dummy: Dummy)
	local nextThrowAt = 0
	local nextStrafeAt = 0
	local strafeSign = 1
	local anchor: Vector3? = nil
	local overAt: number? = nil
	while dummy.alive do
		task.wait(STEP_SECONDS)
		local now = os.clock()
		local phase = phaseOf(dummy)
		local opponent = dummy.opponent
		local opponentGone = opponent ~= nil and typeof(opponent) == "Instance" and opponent.Parent ~= Players
		if phase ~= "" then
			dummy.wasInMatch = true
			overAt = nil
		elseif dummy.wasInMatch and overAt == nil then
			overAt = now + DUMMY_LINGER_SECONDS
		end
		if (overAt ~= nil and now >= overAt) or (opponentGone and phase == "") then
			destroyDummy(dummy)
			break
		end
		local root = dummy:getRoot()
		local character = dummy.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if not ACTIVE_PHASES[phase] or root == nil then
			anchor = nil
			continue
		end
		if anchor == nil then
			anchor = root.Position
		end
		if dummy.strafe and humanoid and anchor and now >= nextStrafeAt then
			nextStrafeAt = now + STRAFE_EVERY_SECONDS
			strafeSign = -strafeSign
			humanoid:MoveTo(anchor + Vector3.new(STRAFE_STUDS * strafeSign, 0, 0))
		end
		local target = rootOf(opponent)
		if dummy.throwing and target and now >= nextThrowAt then
			nextThrowAt = now + THROW_EVERY_SECONDS
			throwAt(dummy, target)
		end
	end
end

local function makeDummy(rig: Model, parent: Instance): Dummy
	local label = Strings.duel.testDummy
	local userId = nextUserId
	nextUserId -= 1
	local attributes: { [string]: any } = {}
	local dummy: Dummy
	dummy = {
		kind = "testDummy",
		isTestDummy = true,
		UserId = userId,
		userId = userId,
		Name = label,
		DisplayName = label,
		displayName = label,
		Character = rig,
		character = rig,
		Parent = parent,
		squishyId = Catalog.starterId(),
		CharacterAdded = newSignalLike(),
		CharacterRemoving = newSignalLike(),
		GetAttribute = function(self: Dummy, name: string): any
			local model = self.Character
			if model ~= nil and model.Parent ~= nil then
				return model:GetAttribute(name)
			end
			return self.attributes[name]
		end,
		SetAttribute = function(self: Dummy, name: string, value: any)
			self.attributes[name] = value
			local model = self.Character
			if model ~= nil and model.Parent ~= nil then
				model:SetAttribute(name, value)
			end
		end,
		GetNetworkPing = function(_self: Dummy): number
			return 0
		end,
		RequestStreamAroundAsync = function(_self: Dummy, _position: Vector3, _timeout: number?) end,
		IsA = function(_self: Dummy, _className: string): boolean
			return false
		end,
		getRoot = function(self: Dummy): BasePart?
			local model = self.Character
			local root = if model then model:FindFirstChild(ROOT_PART) else nil
			if root ~= nil and root:IsA("BasePart") and root:IsDescendantOf(Workspace) then
				return root
			end
			return nil
		end,
		throwing = true,
		strafe = true,
		opponent = nil,
		seq = 0,
		wasInMatch = false,
		alive = true,
		attributes = attributes,
	}
	return dummy
end

-- Public ---------------------------------------------------------------------------------------------------------------

-- True when the harness may act right now (Studio, Config.Debug.testHarness, SD_TestScenario set).
function TestHarness.enabled(): boolean
	return codeEnabled() and armed()
end

-- True for a test dummy adapter.
function TestHarness.isDummy(value: any): boolean
	return type(value) == "table" and value.isTestDummy == true and value.kind == "testDummy"
end

-- The adapter alone, around an existing rig, with `parent` as its Parent (spawnDummyAsync passes
-- Workspace.SD_TestDummies). Never builds or parents anything; each call takes the next negative userId.
function TestHarness.newDummy(rig: Model, parent: Instance): Dummy
	return makeDummy(rig, parent)
end

-- Builds and places a dummy (yields while the avatar loads). Returns (dummy) or (nil, why).
function TestHarness.spawnDummyAsync(position: Vector3?): (Dummy?, string?)
	if not codeEnabled() then
		return nil, "the test harness is off (Studio + Config.Debug.testHarness only)"
	end
	if not armed() then
		return nil, `set Workspace attribute {ATTR_SCENARIO} first`
	end
	local rig = buildRigAsync()
	local folder = getFolder()
	local dummy = makeDummy(rig, folder)
	rig.Name = RIG_PREFIX .. tostring(-dummy.userId)
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = dummy.DisplayName
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
		humanoid.NameDisplayDistance = 150
	end
	local spawnAt = position or (WorldLayout.DuelGate.approach + SPAWN_OFFSET)
	rig:PivotTo(CFrame.new(spawnAt))
	local okGroup, registered = pcall(function(): boolean
		return PhysicsService:IsCollisionGroupRegistered(WorldService.CollisionGroups.Characters)
	end)
	if okGroup and registered then
		CharacterService.applyCollisionGroup(rig)
	end
	rig.Parent = folder
	local root = dummy:getRoot()
	if root then
		pcall(function(): any
			root:SetNetworkOwner(nil)
			return nil
		end)
	end
	table.insert(dummies, dummy)
	task.spawn(run, dummy)
	log:info(`spawned dummy {dummy.userId}`)
	return dummy, nil
end

-- Starts a duel between `player` and a new dummy through QueueService.forceMatch. Returns a reply table.
function TestHarness.startDuelAsync(player: Player?, options: StartOptions?): { [string]: any }
	if player == nil or player.Parent ~= Players then
		return { ok = false, error = "no such player" }
	end
	local dummy, why = TestHarness.spawnDummyAsync(nil)
	if dummy == nil then
		return { ok = false, error = why }
	end
	local opts: StartOptions = options or {}
	dummy.throwing = opts.throwing ~= false
	dummy.strafe = opts.strafe ~= false
	dummy.opponent = player
	local ok, match = QueueService.forceMatch(player, dummy)
	if not ok then
		destroyDummy(dummy)
		return { ok = false, error = `match did not start: {tostring(match)}` }
	end
	local matchId = if type(match) == "table" then match.matchId elseif type(match) == "string" then match else nil
	return { ok = true, matchId = matchId, dummyUserId = dummy.userId }
end

-- The dummy leaves the game the way a player does: the duel-side leave hooks run for it (in the bootstrap's reverse
-- order), then the rig is removed. Falls back to DuelService.forfeit when DuelService has no leave hook.
function TestHarness.leave(dummy: Dummy)
	for _, name in { "DuelService", "AbilityService", "CombatService" } do
		local service = optionalService(name)
		if service ~= nil and type(service.playerRemoving) == "function" then
			local ok, err = pcall(service.playerRemoving, dummy)
			if not ok then
				log:warn(`{name} leave hook failed for the dummy:`, err)
			end
		elseif name == "DuelService" and service ~= nil and type(service.forfeit) == "function" then
			pcall(service.forfeit, dummy, "leave")
		end
	end
	destroyDummy(dummy)
end

-- The dummy forfeits (DuelService.forfeit); the rig stays until its match is over.
function TestHarness.forfeit(dummy: Dummy): boolean
	local DuelService = optionalService("DuelService")
	if DuelService == nil or type(DuelService.forfeit) ~= "function" then
		return false
	end
	local ok, err = pcall(DuelService.forfeit, dummy, "forfeit")
	if not ok then
		log:warn("dummy forfeit failed:", err)
	end
	return ok
end

-- Turns throwing on or off for every dummy.
function TestHarness.setThrowing(on: boolean)
	for _, dummy in dummies do
		dummy.throwing = on
	end
end

-- Removes every dummy (each leaves through the leave path when it is in a match).
function TestHarness.clear()
	for _, dummy in table.clone(dummies) do
		if phaseOf(dummy) ~= "" then
			TestHarness.leave(dummy)
		else
			destroyDummy(dummy)
		end
	end
end

-- Live dummies.
function TestHarness.dummies(): { Dummy }
	return table.clone(dummies)
end

function TestHarness.count(): number
	return #dummies
end

-- Runs a named scenario (see the header). Yields while a dummy spawns. Returns a reply table.
function TestHarness.runScenario(name: string, ...: any): { [string]: any }
	if not codeEnabled() then
		return { ok = false, error = "the test harness is off" }
	end
	local args = table.pack(...)
	local function playerArg(): Player?
		local userId = args[1]
		if type(userId) == "number" then
			return Players:GetPlayerByUserId(userId)
		end
		return Players:GetPlayers()[1]
	end
	local function delayArg(): number
		local seconds = args[2]
		return if type(seconds) == "number" and seconds >= 0 then seconds else DEFAULT_SCENARIO_DELAY
	end

	if name == "clear" then
		TestHarness.clear()
		Workspace:SetAttribute(ATTR_SCENARIO, "")
		return { ok = true }
	elseif name == "restart" then
		local seconds = if type(args[1]) == "number" then args[1] else DEFAULT_RESTART_SECONDS
		return { ok = ShutdownService.debugScheduleRestart(seconds) }
	end

	Workspace:SetAttribute(ATTR_SCENARIO, name)
	if name == "dummy_duel" or name == "dummy_passive" then
		local passive = name == "dummy_passive"
		return TestHarness.startDuelAsync(playerArg(), { throwing = not passive, strafe = not passive })
	elseif name == "dummy_leave" or name == "dummy_forfeit" then
		local reply = TestHarness.startDuelAsync(playerArg(), { throwing = true, strafe = true })
		if not reply.ok then
			return reply
		end
		local seconds = delayArg()
		local dummyUserId = reply.dummyUserId
		task.delay(seconds, function()
			for _, dummy in dummies do
				if dummy.userId == dummyUserId then
					if name == "dummy_leave" then
						TestHarness.leave(dummy)
					else
						TestHarness.forfeit(dummy)
					end
					return
				end
			end
		end)
		reply.after = seconds
		return reply
	end
	return { ok = false, error = `unknown scenario {name}` }
end

-- Studio debug view.
function TestHarness.debugState(): { [string]: any }
	local list = {}
	for _, dummy in dummies do
		local root = dummy:getRoot()
		table.insert(list, {
			userId = dummy.userId,
			phase = phaseOf(dummy),
			throwing = dummy.throwing,
			seq = dummy.seq,
			opponent = if typeof(dummy.opponent) == "Instance" and dummy.opponent:IsA("Player")
				then (dummy.opponent :: Player).UserId
				else nil,
			position = if root then root.Position else nil,
		})
	end
	return { enabled = TestHarness.enabled(), scenario = Workspace:GetAttribute(ATTR_SCENARIO), dummies = list }
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function TestHarness.init()
	if not codeEnabled() then
		return
	end
	log:info(`ready (arm with Workspace attribute {ATTR_SCENARIO}; scenarios via SD_DebugServer)`)
end

return TestHarness
