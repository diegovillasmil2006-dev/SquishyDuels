--!strict
-- Server bootstrap (server only; the only server Script). DESIGN §2.6.
-- 1. Config.validate() plus the throw power budget of every catalog squishy (Logic/PowerBudget.check, §4.1, §5.8;
--    server-only, so Config.validate() cannot run it): problems stop the boot in Studio
--    (Config.Debug.failOnInvalidConfig); in a live server they are only warned here. Disabling invalid box, shop and
--    bundle entries (fail closed, §2.6) is the job of the services that own them (Parts 5 and 7); a squishy over its
--    power budget stays usable (DESIGN has no rule to disable it).
-- 2. Requires the services in layer order (plus the Studio-only modules whose Config.Debug flag is on).
-- 3. Runs each init() (synchronous wiring), then spawns each start() in order. In Studio
--    (Config.Debug.checkInitYield, §2.6 rule 3) each init runs in a coroutine and the boot errors if it yields.
-- 4. playerAdded(p) in layer order on join; playerRemoving(p) in reverse order on leave. Each hook is isolated: an
--    error or a yield in one is logged and never stops the hooks after it.
-- Services arrive part by part, so only the modules that exist are required; the missing ones are listed in
-- one info line.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log).new("Boot")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local PowerBudget = require(script.Logic.PowerBudget)

type Module = {
	init: (() -> ())?,
	start: (() -> ())?,
	playerAdded: ((player: Player) -> ())?,
	playerRemoving: ((player: Player) -> ())?,
}

-- Server layers (§2.6 rule 2). MonetizationService is first so ProcessReceipt is assigned before any yield.
-- GripService is its own layer between CharacterService and SqueezeService (§17.10 "Server layering", §17.11).
-- Phase 3: BaseService after CharacterService (its plot spawn replaces the lobby spawn once Phase 4 builds the plots).
-- Pens3 phase 1: PenService where CapsuleService was, after BaseService, GripService and EconomyService (it redraws
-- the base and pays Coins) and before SqueezeService; CapsuleService is no longer started (removed in phase 2).
-- Batch 3 (friends): FriendDuelService right after QueueService (it starts duels through it); ShowOffService last (it
-- reads the duel results, Grip levels and FriendDuelService's friend matches).
-- FFA/TDM v1 (2026-10-15): MatchMapService then MatchService after FriendDuelService: MatchService reads
-- CharacterService, CombatService, AbilityService, QueueService (state, Joined), NetService and MatchMapService.
-- Auto-clicker check (2026-10-16): AutoClickService right before SqueezeService, which requires it and asks it about
-- every squeeze (it reads profiles through StateService's data port).
-- Practice bot (2026-10-16): BotService right after FriendDuelService (it fills a lone player's 1v1 duel through
-- QueueService and plays through CombatService, DashService, AbilityService and DuelService).
local SERVICE_ORDER = {
	"MonetizationService",
	"NetService",
	"ShutdownService",
	"DataService",
	"StateService",
	"PolicyGateService",
	"EconomyService",
	"InventoryService",
	"WorldService",
	"CharacterService",
	"BaseService",
	"GripService",
	"PenService", -- pens3 phase 1: the pen pays every second and sells its spots (validates Config/Pen at init)
	"AutoClickService", -- 2026-10-16: the auto-clicker check SqueezeService asks first (validates its config at init)
	"SqueezeService",
	"PracticeService",
	"ArenaService",
	"CombatService",
	"AbilityService",
	"DashService", -- spec phase 5: the dash (needs CombatService's fighters and guards)
	"DoubleJumpService", -- 2026-10-15: the duel's double jump (needs CombatService's fighters)
	"LobbyMoveService", -- 2026-10-17: the lobby run's speed and the lobby slide (Config.LobbyMove)
	"DuelService",
	"QueueService",
	"FriendDuelService",
	"BotService", -- 2026-10-16: the 1v1 practice bot
	"MatchMapService", -- FFA/TDM v1 (2026-10-15): Diego's maps in Workspace.DuelMaps (read once at init)
	"MatchService", -- FFA/TDM v1: the in-server Free for All / Team Deathmatch (reads the duel services above)
	"MatchBotService", -- 2026-10-17: the FFA / TDM match bots (after MatchService: its init hands them over)
	"BoxService",
	"ShopService",
	"QuestService",
	"DailyRewardService",
	"TipService",
	"PreferencesService",
	"ShowOffService",
}

-- Studio only, appended after the services; each needs its Config.Debug flag (always false outside Studio).
local STUDIO_ORDER = { "DebugHooks", "TestHarness" }
local STUDIO_FLAGS: { [string]: boolean } = {
	DebugHooks = Config.Debug.debugHooks,
	TestHarness = Config.Debug.testHarness,
}

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve these paths statically.
local dynamicRequire = require :: (ModuleScript) -> any

-- 1. Config and the power budget
local problems = Config.validate()
for _, def in Catalog.list() do
	local _, budgetProblems = PowerBudget.check(def)
	for _, problem in budgetProblems do
		table.insert(problems, problem)
	end
end
if #problems > 0 then
	if Config.Debug.failOnInvalidConfig then
		for _, problem in problems do
			Log:error(problem)
		end
		error("[SD] Config invalid")
	end
	-- Live: warn and keep running. The owning services disable invalid box/shop/bundle entries (fail closed, §2.6).
	for _, problem in problems do
		Log:warn(problem)
	end
end

-- 2. Modules in layer order
local ORDER: { Module } = {}
local NAMES: { string } = {}
local notImplemented: { string } = {}

local function collect(folder: Instance?, folderName: string, names: { string })
	for _, name in names do
		local child = if folder then folder:FindFirstChild(name) else nil
		if child and child:IsA("ModuleScript") then
			table.insert(ORDER, dynamicRequire(child))
			table.insert(NAMES, name)
		else
			table.insert(notImplemented, folderName .. "/" .. name)
		end
	end
end

collect(script:FindFirstChild("Services"), "Services", SERVICE_ORDER)
if RunService:IsStudio() then
	local enabled: { string } = {}
	for _, name in STUDIO_ORDER do
		if STUDIO_FLAGS[name] then
			table.insert(enabled, name)
		end
	end
	collect(script:FindFirstChild("Studio"), "Studio", enabled)
end
if #notImplemented > 0 then
	Log:info("Not implemented yet (skipped):", table.concat(notImplemented, ", "))
end

-- 3. init (must not yield), then start
for i, svc in ORDER do
	local init = svc.init
	if init then
		if Config.Debug.checkInitYield then
			local co = coroutine.create(init)
			local ok, err = coroutine.resume(co)
			assert(ok, string.format("[SD] %s.init failed: %s", NAMES[i], tostring(err)))
			assert(coroutine.status(co) == "dead", string.format("[SD] init yielded: %s", NAMES[i]))
		else
			init()
		end
	end
end
for _, svc in ORDER do
	if svc.start then
		task.spawn(svc.start)
	end
end

-- 4. Players
-- Each hook runs in its own coroutine, so one service can never stop the services after it: a hook that errors is
-- logged and the loop goes on (on leave, DataService.playerRemoving must still release the profile even if a later
-- layer fails), and a hook that yields (§2.6 rule 5 forbids it) is logged and left to finish on its own while the
-- loop goes on without waiting, which keeps every join hook ahead of the leave hooks for the same player.
local function callHook(index: number, hookName: string, hook: (Player) -> (), player: Player)
	local co = coroutine.create(hook)
	local ok, err = coroutine.resume(co, player)
	if not ok then
		Log:error(string.format("%s.%s failed:", NAMES[index], hookName), debug.traceback(co, tostring(err)))
	elseif coroutine.status(co) ~= "dead" then
		Log:error(
			string.format("%s.%s yielded; hooks must spawn their async work (§2.6 rule 5)", NAMES[index], hookName)
		)
	end
end

local function added(player: Player)
	for i, svc in ORDER do
		local hook = svc.playerAdded
		if hook then
			callHook(i, "playerAdded", hook, player)
		end
	end
end

local function removing(player: Player)
	for i = #ORDER, 1, -1 do
		local hook = ORDER[i].playerRemoving
		if hook then
			callHook(i, "playerRemoving", hook, player)
		end
	end
end

Players.PlayerAdded:Connect(added)
Players.PlayerRemoving:Connect(removing)
for _, player in Players:GetPlayers() do
	task.spawn(added, player)
end
