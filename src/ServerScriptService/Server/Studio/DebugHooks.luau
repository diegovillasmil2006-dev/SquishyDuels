--!strict
-- DebugHooks (server only, Studio only). DESIGN §12 #21, §13.1, §13.4, §17.2 rule 2, §17.12.
-- Loaded by the server bootstrap only inside Studio and only while Config.Debug.debugHooks is on (it re-checks both and
-- does nothing otherwise). Creates the BindableFunction ServerStorage.SD_DebugServer for tests run through
-- execute_luau(Server):
--   SD_DebugServer:Invoke("counts")                 sessions (players), profiles by data status (+ DataService.counts()
--                                                   as `data`), queue, matches, projectiles, violations (+ net
--                                                   counters, arenas, dummies, Cleanup.liveCount(), closing, squeeze
--                                                   and Grip counters)
--   SD_DebugServer:Invoke("forceMatch", userId, "dummy")  that player vs a new TEST DUMMY (TestHarness), outside the
--                                                   queue; arms Workspace.SD_TestScenario ("forceMatch") when it is unset
--   SD_DebugServer:Invoke("scenario", name, ...)    sets SD_TestScenario = name and runs TestHarness.runScenario
--                                                   (dummy_duel, dummy_passive, dummy_leave, dummy_forfeit, restart,
--                                                   clear)
--   SD_DebugServer:Invoke("queue" | "arenas" | "net" | "dummies")   debug views of QueueService, ArenaService,
--                                                   NetService and TestHarness
--   SD_DebugServer:Invoke("forceArena", arenaId?)   every next match gets that arena (World/Arenas id, e.g.
--                                                   "pinewood_camp") while its template is usable; nil = random again
--                                                   (ArenaService.debugForceArena; phase 4 spec §5.6)
--   SD_DebugServer:Invoke("setAccepting", on)       QueueService.setAccepting
--   SD_DebugServer:Invoke("dummyThrows", on)        every dummy throws (true) or holds (false)
-- Part 5 (economy, saving, Grip):
--   SD_DebugServer:Invoke("profile", userId)        { status, persisted, savePending, saveScheduled (a "soon" save is
--                                                   due: DataService.inspect soonAt; nil without a session),
--                                                   migratedFrom, level, attrLevel, equipped, store =
--                                                   DataService.selection() {kind, name}, profile = a deep copy of the
--                                                   profile in memory }
--   SD_DebugServer:Invoke("setCoins", userId, n)    the balance becomes n, through EconomyService.debugSetCoins (Studio
--                                                   only, reason "debug": Coins keep one writer)
--   SD_DebugServer:Invoke("grant", userId, what)    what = a squishy id: EconomyService.grantSquishy(p, id, "grant");
--                                                   what = a number: grantCoins(p, n, "debug")
--   SD_DebugServer:Invoke("setGrip", userId, total, silent?)  GripService.debugSetTotal (a level change toasts like a
--                                                   real gain unless silent)
--   SD_DebugServer:Invoke("setRested", userId, v)   Double Grip points (GripService.debugSetRested)
--   SD_DebugServer:Invoke("setSqueezeLimit", userId, v)  squeeze Coins limit points (SqueezeService.debugSetLimit;
--                                                   dormant since spec 2026-10-11 §5: the hourly limit is off, so an
--                                                   empty limit still pays every squeeze)
--   (build plan Phase 6: setAfkBank, slowTick and tickSeconds went with slow training)
--   SD_DebugServer:Invoke("gripLog", clear?)        the Grip toasts sent this session { userId, code, args, at }
--   SD_DebugServer:Invoke("grip" | "squeeze")       GripService.debugState / SqueezeService.counts (with
--                                                   squeezeAlerts, the paid-squeeze alerts logged, spec 2026-10-12 §12)
--   SD_DebugServer:Invoke("toStation", userId, stationId)  moves the character to stand on that squeeze station
--                                                   (WorldLayout centre, top + 3 studs; CharacterService.teleportAsync):
--                                                   a squeeze there gets the pad's boost (the server finds the pad under
--                                                   the root; a squeeze anywhere else pays the base)
--   SD_DebugServer:Invoke("loadProfile", userId, value?)  reloads the player's profile through
--                                                   DataService.debugReloadAsync(p, value?) (memory store; `value` = a
--                                                   stored profile to load, e.g. a v1 fixture, so the real load
--                                                   pipeline migrates it)
-- Part 7 (boxes, shop, policy, Robux, quests, daily, tips; §13.1, §13.2 Part 7 L3):
--   SD_DebugServer:Invoke("setPolicy", userId, state)   PolicyGateService.debugSetState: "checking" | "eligible" |
--                                                   "restricted" | "unknown" at once (a running check is discarded)
--   SD_DebugServer:Invoke("policy")                 PolicyGateService.debugState(): every player's state and retries
--   SD_DebugServer:Invoke("simulateReceipt", userId, purchaseId)  MonetizationService.debugSimulateReceipt: the SAME
--                                                   ProcessReceipt core with a Studio-only fixture bundle (ProductId 0,
--                                                   never in Config.Monetization) -> { ok, decision = "PurchaseGranted"
--                                                   | "NotProcessedYet", coinsAdded }
--   SD_DebugServer:Invoke("monetization")           MonetizationService.debugState(): offered bundles, validated ids
--   SD_DebugServer:Invoke("failSaves", userId, count)  DataService.debugFailSaves: the next `count` writes of the
--                                                   player's key fail at once (memory store; 0 clears) -> savePending
--   SD_DebugServer:Invoke("setDaily", userId, lastClaimDay, streakDay)  DailyRewardService.debugSetState
--   SD_DebugServer:Invoke("quests", userId)         QuestService.debugState
--   SD_DebugServer:Invoke("questProgress", userId, questId, progress)  QuestService.debugSetProgress
--   SD_DebugServer:Invoke("questDay", userId, day?) QuestService.debugRollover (day nil = the service's choice)
--   SD_DebugServer:Invoke("tip", userId)            TipService.debugState
-- Every command returns a table { ok = boolean, ... }; an unknown command returns { ok = false, error = <text> }. These
-- are debug strings for tests, never shown to players. Collaborators that other parts own (DuelService, CombatService,
-- DataService's Studio hooks, the Part 7 services) are looked up when a command runs, so a missing one (or a missing
-- debug function) is reported in the reply instead of breaking the boot.
-- Owners own all (Config.Debug.ownersOwnAll, 2026-10-11): when a co-owner (OWNER_IDS) joins a Studio test, every
-- squishy they do not own yet is granted once their profile is ready (playerAdded; EconomyService.grantSquishy with
-- source "grant", so no onboarding step is completed). Once per join.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local TableUtil = require(Shared.Util.TableUtil)
local WorldLayout = require(Shared.World.WorldLayout)

local Server = script.Parent.Parent
local Services = Server.Services
local ArenaService = require(Services.ArenaService)
local CharacterService = require(Services.CharacterService)
local EconomyService = require(Services.EconomyService)
local GripService = require(Services.GripService)
local InventoryService = require(Services.InventoryService)
local NetService = require(Services.NetService)
local QueueService = require(Services.QueueService)
local ShutdownService = require(Services.ShutdownService)
local SqueezeService = require(Services.SqueezeService)
local StateService = require(Services.StateService)
local TestHarness = require(script.Parent.TestHarness)

-- Types

type Reply = { [string]: any }

-- Constants

local FUNCTION_NAME = "SD_DebugServer"
local ATTR_SCENARIO = "SD_TestScenario"
local ATTR_GRIP_LEVEL = "SD_GripLevel"
local DUMMY_KIND = "dummy"
local DEBUG_REASON = "debug"
local GRANT_SOURCE = "grant"
local STATUSES = { "loading", "ready", "offline", "readonly" }
-- Function names DuelService / CombatService may expose for a count (the first that exists is used).
local MATCH_COUNT_NAMES = { "matchCount", "activeMatchCount", "countMatches", "activeCount" }
local PROJECTILE_COUNT_NAMES = { "projectileCount", "activeProjectileCount", "countProjectiles" }
-- DataService's Studio reload hook (named in DataService's header).
local RELOAD_NAME = "debugReloadAsync"
-- toStation: the root part goes this high above the station top (an R15 root stands about 3 studs up).
local STAND_HEIGHT = 3
-- Owners own all: the co-owners jayyyyy2806 and VillasmilGaming.
local OWNER_IDS = { 8963996639, 136002404 }

-- Module table

local DebugHooks = {}

-- Private

local log = Log.new("DebugServer")
local dynamicRequire = require :: (ModuleScript) -> any
local cleanup: Cleanup.Cleanup? = nil

local function optionalService(name: string): any
	local module = Services:FindFirstChild(name)
	if module ~= nil and module:IsA("ModuleScript") then
		return dynamicRequire(module)
	end
	return nil
end

-- The first count function of `module` that exists and returns a number (or a table: its entry count). -1 = unknown.
local function countFrom(module: any, names: { string }): number
	if type(module) ~= "table" then
		return -1
	end
	for _, name in names do
		local fn = module[name]
		if type(fn) == "function" then
			local ok, value = pcall(fn)
			if ok and type(value) == "number" then
				return value
			elseif ok and type(value) == "table" then
				local n = 0
				for _ in value do
					n += 1
				end
				return n
			end
		end
	end
	return -1
end

-- The player with this userId, or (nil, an error reply).
local function playerOf(userId: unknown): (Player?, Reply?)
	if type(userId) ~= "number" then
		return nil, { ok = false, error = "needs a userId" }
	end
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return nil, { ok = false, error = `no player with userId {userId}` }
	end
	return player, nil
end

local function profileCounts(): { [string]: number }
	local port = StateService.dataPort()
	local byStatus: { [string]: number } = {}
	for _, status in STATUSES do
		byStatus[status] = 0
	end
	for _, player in Players:GetPlayers() do
		local status = port.status(player)
		byStatus[status] = (byStatus[status] or 0) + 1
	end
	return byStatus
end

local function coinsOf(player: Player): number?
	local profile = StateService.dataPort().getProfile(player)
	return if type(profile) == "table" and type(profile.coins) == "number" then profile.coins else nil
end

-- DataService.selection(): the store real players use ({ kind = "memory" | "datastore", name }), or nil.
local function storeSelection(): Reply?
	local dataService = optionalService("DataService")
	if type(dataService) ~= "table" or type(dataService.selection) ~= "function" then
		return nil
	end
	local ok, chosen = pcall(dataService.selection)
	if not ok or type(chosen) ~= "table" then
		return nil
	end
	return { kind = chosen.kind, name = chosen.name }
end

local function counts(): Reply
	local net = NetService.counts()
	local matches = countFrom(optionalService("DuelService"), MATCH_COUNT_NAMES)
	local profiles = profileCounts()
	local dataService = optionalService("DataService")
	local dataCounts = nil
	if type(dataService) == "table" and type(dataService.counts) == "function" then
		local ok, value = pcall(dataService.counts)
		dataCounts = if ok then value else nil
	end
	return {
		ok = true,
		sessions = #Players:GetPlayers(),
		profiles = profiles,
		profilesLoaded = profiles.ready + profiles.offline + profiles.readonly,
		data = dataCounts, -- DataService.counts(): data sessions by status, savePending, queued jobs
		store = storeSelection(),
		queue = QueueService.searchingCount(),
		matches = if matches >= 0 then matches else ArenaService.inUseCount(),
		matchesFrom = if matches >= 0 then "DuelService" else "ArenaService",
		projectiles = countFrom(optionalService("CombatService"), PROJECTILE_COUNT_NAMES),
		violations = net.violations,
		mutedNow = net.mutedNow,
		net = net,
		arenas = {
			inUse = ArenaService.inUseCount(),
			free = ArenaService.freeCount(),
			cloned = ArenaService.clonedCount(),
		},
		dummies = TestHarness.count(),
		cleanupLive = Cleanup.liveCount(),
		closing = ShutdownService.isClosing(),
		restartPending = ShutdownService.isRestartPending(),
		squeeze = SqueezeService.counts(),
		grip = GripService.debugState(),
	}
end

local function forceMatch(userId: unknown, kind: unknown): Reply
	if kind ~= DUMMY_KIND then
		return { ok = false, error = `forceMatch supports only "{DUMMY_KIND}"` }
	end
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	local scenario = Workspace:GetAttribute(ATTR_SCENARIO)
	if type(scenario) ~= "string" or scenario == "" then
		Workspace:SetAttribute(ATTR_SCENARIO, "forceMatch")
	end
	return TestHarness.startDuelAsync(player, { throwing = true, strafe = true })
end

local function forceArena(arenaId: unknown): Reply
	if arenaId ~= nil and type(arenaId) ~= "string" then
		return { ok = false, error = "forceArena needs an arena id or nil" }
	end
	local ok, problem = ArenaService.debugForceArena(arenaId :: string?)
	return { ok = ok, error = problem, arenas = ArenaService.debugState() }
end

local function scenario(name: unknown, ...: any): Reply
	if type(name) ~= "string" or name == "" then
		return { ok = false, error = "scenario needs a name" }
	end
	return TestHarness.runScenario(name, ...) -- sets SD_TestScenario = name (except clear / restart)
end

local function setAccepting(on: unknown): Reply
	if type(on) ~= "boolean" then
		return { ok = false, error = "setAccepting needs true or false" }
	end
	QueueService.setAccepting(on)
	return { ok = true }
end

local function dummyThrows(on: unknown): Reply
	if type(on) ~= "boolean" then
		return { ok = false, error = "dummyThrows needs true or false" }
	end
	TestHarness.setThrowing(on)
	return { ok = true }
end

-- Part 5 ----------------------------------------------------------------------------------------------------------------

local function profile(userId: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	local port = StateService.dataPort()
	local live = port.getProfile(player)
	local migratedFrom: any = nil
	local saveScheduled: boolean? = nil
	local dataService = optionalService("DataService")
	if type(dataService) == "table" and type(dataService.migratedFrom) == "function" then
		local ok, version = pcall(dataService.migratedFrom, player)
		migratedFrom = if ok then version else nil
	end
	if type(dataService) == "table" and type(dataService.inspect) == "function" then
		local ok, state = pcall(dataService.inspect, player)
		saveScheduled = if ok and type(state) == "table" then state.soonAt ~= nil else nil
	end
	return {
		ok = true,
		userId = player.UserId,
		status = port.status(player),
		persisted = port.persisted(player),
		savePending = port.savePending(player),
		saveScheduled = saveScheduled,
		migratedFrom = migratedFrom,
		level = GripService.levelOf(player),
		attrLevel = player:GetAttribute(ATTR_GRIP_LEVEL),
		equipped = player:GetAttribute("SD_Equipped"),
		store = storeSelection(),
		profile = if type(live) == "table" then TableUtil.deepCopy(live) else nil,
	}
end

local function setCoins(userId: unknown, amount: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	if type(amount) ~= "number" or amount ~= amount or amount < 0 or amount > Config.Economy.maxCoins then
		return { ok = false, error = "setCoins needs a number from 0 to maxCoins" }
	end
	local ok = EconomyService.debugSetCoins(player, math.floor(amount))
	return { ok = ok, coins = coinsOf(player), error = if ok then nil else "profile not ready" }
end

local function grant(userId: unknown, what: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	if type(what) == "number" then
		if what ~= what or what <= 0 then
			return { ok = false, error = "grant needs a positive number of Coins" }
		end
		local added, failure = EconomyService.grantCoins(player, math.floor(what), DEBUG_REASON)
		return { ok = failure == nil, coins = coinsOf(player), gained = added, error = failure }
	end
	if type(what) ~= "string" or not Catalog.isValidId(what) then
		return { ok = false, error = "grant needs a squishy id or a number of Coins" }
	end
	local result = EconomyService.grantSquishy(player, what, GRANT_SOURCE)
	return {
		ok = InventoryService.owns(player, what),
		added = result.added,
		copy = result.copy, -- pens3 phase 5: owned already, so one more copy
		error = result.refused,
	}
end

local function fromGrip(ok: boolean, err: string?): Reply
	return { ok = ok, error = err }
end

local function setGrip(userId: unknown, total: unknown, silent: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	local reply = fromGrip(GripService.debugSetTotal(player, total, silent == true))
	reply.level = GripService.levelOf(player)
	return reply
end

local function setRested(userId: unknown, value: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	return fromGrip(GripService.debugSetRested(player, value))
end

local function setSqueezeLimit(userId: unknown, value: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	return fromGrip(SqueezeService.debugSetLimit(player, value))
end

local function gripLog(clear: unknown): Reply
	return { ok = true, notices = GripService.debugNotices(clear == true) }
end

local function loadProfile(userId: unknown, value: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	if value ~= nil and type(value) ~= "table" then
		return { ok = false, error = "loadProfile value must be a table or nil" }
	end
	local dataService = optionalService("DataService")
	local fn = if type(dataService) == "table" then dataService[RELOAD_NAME] else nil
	if type(fn) ~= "function" then
		return { ok = false, error = `DataService has no Studio reload hook {RELOAD_NAME}(player, value?)` }
	end
	local ok, result = pcall(fn, player, if value then TableUtil.deepCopy(value) else nil)
	if not ok then
		return { ok = false, error = tostring(result) }
	end
	-- Whatever the hook returns: a table is passed on (with `ok`), anything else as `result` (only false fails).
	local reply: Reply = if type(result) == "table" then table.clone(result) else { result = result }
	if type(reply.ok) ~= "boolean" then
		reply.ok = result ~= false
	end
	reply.status = StateService.dataPort().status(player)
	return reply
end

local function toStation(userId: unknown, stationId: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	local station = if type(stationId) == "string" then WorldLayout.station(stationId) else nil
	if station == nil then
		return { ok = false, error = `unknown station {tostring(stationId)}` }
	end
	local target = Vector3.new(station.position.X, station.top + STAND_HEIGHT, station.position.Z)
	local root = CharacterService.getRoot(player)
	local facing = if root then root.CFrame.Rotation else CFrame.identity
	local moved, reason = CharacterService.teleportAsync(player, CFrame.new(target) * facing)
	if not moved then
		return { ok = false, error = `teleport failed: {tostring(reason)}` }
	end
	return { ok = true, station = station.id, tier = station.tier, x = target.X, y = target.Y, z = target.Z }
end

-- Part 7 ----------------------------------------------------------------------------------------------------------------

-- `serviceName.fnName(...)` when that service and function exist: (true, first, second) with the function's first two
-- results, or (false, error reply).
local function callService(serviceName: string, fnName: string, ...: any): (boolean, any, any)
	local service = optionalService(serviceName)
	if type(service) ~= "table" then
		return false, { ok = false, error = `{serviceName} is not available` }, nil
	end
	local fn = service[fnName]
	if type(fn) ~= "function" then
		return false, { ok = false, error = `{serviceName} has no debug function {fnName}` }, nil
	end
	local results = table.pack(pcall(fn, ...))
	if not results[1] then
		return false, { ok = false, error = tostring(results[2]) }, nil
	end
	return true, results[2], results[3]
end

-- A setter's results as a reply: a table is passed on (with `ok`, true unless it says otherwise), (boolean, error?)
-- becomes { ok, error }, anything else { ok = true, result }.
local function setterReply(serviceName: string, fnName: string, ...: any): Reply
	local called, first, second = callService(serviceName, fnName, ...)
	if not called then
		return first
	end
	if type(first) == "table" then
		local reply: Reply = table.clone(first)
		if type(reply.ok) ~= "boolean" then
			reply.ok = true
		end
		return reply
	elseif type(first) == "boolean" then
		return { ok = first, error = if first then nil else tostring(second or "refused") }
	elseif first == nil and second ~= nil then
		return { ok = false, error = tostring(second) } -- (nil, error)
	end
	return { ok = true, result = first }
end

-- A view's result as { ok = true, [key] = result } (a table that says ok = false is passed on as it is).
local function viewReply(key: string, serviceName: string, fnName: string, ...: any): Reply
	local called, first = callService(serviceName, fnName, ...)
	if not called then
		return first
	end
	if type(first) == "table" and first.ok == false then
		return first
	end
	return { ok = true, [key] = first }
end

local function setPolicy(userId: unknown, state: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	local reply = setterReply("PolicyGateService", "debugSetState", player, state)
	local _, current = callService("PolicyGateService", "state", player)
	reply.state = current
	return reply
end

local function simulateReceipt(userId: unknown, purchaseId: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	if type(purchaseId) ~= "string" or purchaseId == "" or #purchaseId > 64 then
		return { ok = false, error = "simulateReceipt needs a purchaseId string (1-64 characters)" }
	end
	return setterReply("MonetizationService", "debugSimulateReceipt", player, purchaseId)
end

local function failSaves(userId: unknown, count: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	local reply = setterReply("DataService", "debugFailSaves", player, count)
	reply.savePending = StateService.dataPort().savePending(player)
	return reply
end

local function setDaily(userId: unknown, lastClaimDay: unknown, streakDay: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	-- DailyRewardService.debugSetState takes {lastClaimDay?, streakDay?} (nil keeps a value).
	return setterReply(
		"DailyRewardService",
		"debugSetState",
		player,
		{ lastClaimDay = lastClaimDay, streakDay = streakDay }
	)
end

local function quests(userId: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	return viewReply("quests", "QuestService", "debugState", player)
end

local function questProgress(userId: unknown, questId: unknown, progress: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	return setterReply("QuestService", "debugSetProgress", player, questId, progress)
end

local function questDay(userId: unknown, day: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	return setterReply("QuestService", "debugRollover", player, day)
end

local function tip(userId: unknown): Reply
	local player, problem = playerOf(userId)
	if player == nil then
		return problem :: Reply
	end
	return viewReply("tip", "TipService", "debugState", player)
end

local COMMANDS: { [string]: (...any) -> Reply } = {
	counts = counts,
	forceMatch = forceMatch,
	forceArena = forceArena,
	scenario = scenario,
	setAccepting = setAccepting,
	dummyThrows = dummyThrows,
	queue = function(): Reply
		return { ok = true, queue = QueueService.debugState() }
	end,
	arenas = function(): Reply
		return { ok = true, arenas = ArenaService.debugState() }
	end,
	net = function(): Reply
		return { ok = true, net = NetService.counts() }
	end,
	dummies = function(): Reply
		return { ok = true, harness = TestHarness.debugState() }
	end,
	profile = profile,
	setCoins = setCoins,
	grant = grant,
	setGrip = setGrip,
	setRested = setRested,
	setSqueezeLimit = setSqueezeLimit,
	gripLog = gripLog,
	grip = function(): Reply
		return { ok = true, grip = GripService.debugState() }
	end,
	squeeze = function(): Reply
		return { ok = true, squeeze = SqueezeService.counts() }
	end,
	toStation = toStation,
	loadProfile = loadProfile,
	setPolicy = setPolicy,
	policy = function(): Reply
		return viewReply("policy", "PolicyGateService", "debugState")
	end,
	simulateReceipt = simulateReceipt,
	monetization = function(): Reply
		return viewReply("monetization", "MonetizationService", "debugState")
	end,
	failSaves = failSaves,
	setDaily = setDaily,
	quests = quests,
	questProgress = questProgress,
	questDay = questDay,
	tip = tip,
}

local function onInvoke(command: unknown, ...: any): Reply
	local handler = if type(command) == "string" then COMMANDS[command] else nil
	if handler == nil then
		return { ok = false, error = `unknown command {tostring(command)}` }
	end
	local ok, result = pcall(handler, ...)
	if not ok then
		log:warn(`command {command} failed:`, result)
		return { ok = false, error = tostring(result) }
	end
	return result
end

-- Lifecycle

function DebugHooks.init()
	if not (RunService:IsStudio() and Config.Debug.debugHooks) then
		return
	end
	local c = Cleanup.new()
	cleanup = c
	local existing = ServerStorage:FindFirstChild(FUNCTION_NAME)
	if existing then
		existing:Destroy()
	end
	local bindable = c:add(Instance.new("BindableFunction"))
	bindable.Name = FUNCTION_NAME
	bindable.OnInvoke = onInvoke
	bindable.Parent = ServerStorage
end

-- Owners own all (see the header). Never yields: the wait for the profile runs in its own thread.
function DebugHooks.playerAdded(player: Player)
	if not (RunService:IsStudio() and Config.Debug.ownersOwnAll) or not table.find(OWNER_IDS, player.UserId) then
		return
	end
	local dataService = optionalService("DataService")
	if type(dataService) ~= "table" or type(dataService.waitForProfileAsync) ~= "function" then
		log:warn("ownersOwnAll: DataService.waitForProfileAsync is missing; nothing granted")
		return
	end
	task.spawn(function()
		if dataService.waitForProfileAsync(player) == nil then
			return -- left, OFFLINE or READONLY: nothing is granted
		end
		local added = 0
		for _, def in Catalog.list() do
			-- Pens3 phase 5: a grant of an owned kind is a copy, so only the missing kinds are granted.
			if
				not InventoryService.owns(player, def.id)
				and EconomyService.grantSquishy(player, def.id, GRANT_SOURCE).added
			then
				added += 1
			end
		end
		log:info(`ownersOwnAll: user {player.UserId} got {added} squishies`)
	end)
end

-- Not called by the bootstrap; removes the hook (leak checks).
function DebugHooks.destroy()
	local c = cleanup
	cleanup = nil
	if c then
		c:clean()
	end
end

return DebugHooks
