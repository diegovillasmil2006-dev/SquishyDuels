--!strict
-- Client bootstrap (client only; the only LocalScript). DESIGN §2.6 "Client boot":
-- wait for the initial replication (game.Loaded; Roblox's own loading screen still covers it, and the Config
-- section modules are indexed directly) → Config.validate() (problems stop the boot in Studio through
-- Config.Debug.failOnInvalidConfig, are warned in a live server) →
-- UIController.showLoading() → NetController.connectAsync(Config.Net.Client.connectTimeoutSeconds = 30)
-- (on timeout: show `error.connect` and stop) → require the controllers in layer order → init() (in Studio,
-- Config.Debug.checkInitYield: errors if it yields) → StateController.loadSnapshotAsync() → spawn each start()
-- in order → UIController.hideLoading().
-- Controllers arrive part by part, so only the modules that exist are required and called; the missing ones
-- are listed in one info line. Assumed contracts for the later controllers (DESIGN does not name them):
-- connectAsync(timeout) returns true once connected; UIController.showError(reasonCode) and
-- UIController.hideLoading() exist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared:WaitForChild("Util"):WaitForChild("Log")).new("Boot")
local Config = require(Shared:WaitForChild("Config"))

type Module = {
	init: (() -> ())?,
	start: (() -> ())?,
}

-- Client layers, in the order of DESIGN §2.4: infrastructure (net, state, input, camera, sound, UI, notify),
-- world and characters, the aim/throw input layer, then the feature screens and duel visuals. A module requires only
-- the ones above it (§2.6 rule 2): ThrowController (aim, throw and ultimate input, under the practice and duel HUDs
-- that read its aim state, and the projectile and VFX layers that follow it) comes right after the character layers.
-- First person (spec 2026-10-10 §3.1, §7): FirstPersonController (the camera) and ViewmodelController (the hand
-- overlay) right after ThrowController; they init before PracticeController, whose ZoneChanged exists from its load.
-- Reading: §2.4 lists ThrowController after the screens; it sits here because those screens require it. Feature
-- screens never require each other.
-- Reading (Part 5): GripController and NameplateController come right after HudController, because the Grip card sits
-- in HudController's left column and is its DPadUp entry (§17.7, §17.11).
-- Feel pass (§18.10 L1): AmbientController (lobby background motion) right after GiantPadController;
-- JellyRippleController after VfxController, then SplatController, which requires the ripple (§18.4).
-- Part 6: CollectionController (the per-player Collection pedestal displays, §7.6) right after AmbientController in
-- the world layer; of the controllers it requires only StateController (plus SquishyCache, Scheduler, Tweens, the UI
-- helpers and shared modules).
-- Spec phase 5: DashController (the dash) right after ThrowController, whose windup and ultimate state it reads.
-- Feature 1 (2026-10-11): CatchController (the catch) right after ThrowController too, whose charge and hands it
-- drives; the overlay, the duel HUD, the projectiles and the VFX read it.
local CONTROLLER_ORDER = {
	"NetController",
	"StateController",
	"ControlsController",
	"CameraController",
	"SoundController",
	"UIController",
	"NotifyController",
	"WorldBinder",
	"GiantPadController",
	"AmbientController",
	"CollectionController",
	"HeldSquishyController",
	"CharacterAnimController",
	"ThrowController",
	"CatchController",
	"DashController",
	"FirstPersonController",
	"ViewmodelController",
	"SqueezeController",
	"PracticeController",
	"HudController",
	"GripController",
	"NameplateController",
	"InventoryController",
	"InspectController",
	"ShopController",
	"BoxController",
	"QuestController",
	"DailyController",
	"QueueController",
	"DuelController",
	"SettingsController",
	"OnboardingController",
	"ProjectileRenderer",
	"VfxController",
	"JellyRippleController",
	"SplatController",
}

-- Studio only, appended after the controllers; each needs its Config.Debug flag (always false outside Studio).
-- SoundPicker (§18.7) only creates its BindableFunction in init; no UI until the picker data is loaded in Play.
local STUDIO_ORDER = { "DebugHooks", "AutoDriver", "SoundPicker" }
local STUDIO_FLAGS: { [string]: boolean } = {
	DebugHooks = Config.Debug.debugHooks,
	AutoDriver = Config.Debug.autoDriver,
	SoundPicker = Config.Debug.soundPicker,
}

local CONNECT_ERROR_CODE = "error.connect"

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve these paths statically.
local dynamicRequire = require :: (ModuleScript) -> any

local controllersFolder = script:FindFirstChild("Controllers")
local studioFolder = if RunService:IsStudio() then script:FindFirstChild("Studio") else nil

local function load(folder: Instance?, name: string): any
	local child = if folder then folder:FindFirstChild(name) else nil
	if child and child:IsA("ModuleScript") then
		return dynamicRequire(child)
	end
	return nil
end

-- 1. Config
local problems = Config.validate()
if #problems > 0 then
	if Config.Debug.failOnInvalidConfig then
		for _, problem in problems do
			Log:error(problem)
		end
		error("[SD] Config invalid")
	end
	for _, problem in problems do
		Log:warn(problem)
	end
end

-- 2. Loading screen and connection
local UIController = load(controllersFolder, "UIController")
local NetController = load(controllersFolder, "NetController")

if UIController and UIController.showLoading then
	UIController.showLoading()
end
if NetController and NetController.connectAsync then
	local ok, connected = pcall(NetController.connectAsync, Config.Net.Client.connectTimeoutSeconds)
	if not ok or connected ~= true then
		Log:error("Could not connect to the game server:", if ok then "timed out" else connected)
		if UIController and UIController.showError then
			UIController.showError(CONNECT_ERROR_CODE)
		end
		return
	end
end

-- 3. Controllers in layer order
local ORDER: { Module } = {}
local NAMES: { string } = {}
local notImplemented: { string } = {}

local function collect(folder: Instance?, folderName: string, names: { string })
	for _, name in names do
		local module = load(folder, name)
		if module ~= nil then
			table.insert(ORDER, module)
			table.insert(NAMES, name)
		else
			table.insert(notImplemented, folderName .. "/" .. name)
		end
	end
end

collect(controllersFolder, "Controllers", CONTROLLER_ORDER)
if RunService:IsStudio() then
	local enabled: { string } = {}
	for _, name in STUDIO_ORDER do
		if STUDIO_FLAGS[name] then
			table.insert(enabled, name)
		end
	end
	collect(studioFolder, "Studio", enabled)
end
if #notImplemented > 0 then
	Log:info("Not implemented yet (skipped):", table.concat(notImplemented, ", "))
end

-- 4. init (must not yield)
for i, controller in ORDER do
	local init = controller.init
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

-- 5. First snapshot, then start, then hide the loading screen
local StateController = load(controllersFolder, "StateController")
if StateController and StateController.loadSnapshotAsync then
	-- A failing snapshot wait must never stop the boot: start() and hideLoading() below still run.
	local ok, err = pcall(StateController.loadSnapshotAsync)
	if not ok then
		Log:error("loadSnapshotAsync failed: " .. tostring(err))
	end
end
for _, controller in ORDER do
	if controller.start then
		task.spawn(controller.start)
	end
end
if UIController and UIController.hideLoading then
	UIController.hideLoading()
end
