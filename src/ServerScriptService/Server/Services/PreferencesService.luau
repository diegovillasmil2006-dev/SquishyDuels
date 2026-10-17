--!strict
-- PreferencesService (server only). DESIGN §2.3, §2.8 (SetSettings, OnboardingStep), §3.2, §11.6 (Settings), §11.8.
-- Settings and onboarding flags, kept in the profile (profile.settings, profile.onboarding) and saved "soon" (§3.9).
-- * SetSettings (RE): the payload is checked by Util/Validate.settings (a table of at most 4 keys from music, sfx,
--   cameraShake, showTips; volumes whole numbers clamped to 0-100; booleans); anything else is dropped. Only the keys
--   sent change. The client applies settings at once and debounces the remote (1.5 s, §11.6); the server only stores.
--   Reading: "reduced motion" is Roblox's own GuiService.ReducedMotionEnabled (§9.12), read on the client (the
--   Settings screen's switch is session-only); an in-game saved toggle is an unapproved proposal (§16), so it is not
--   a profile setting.
-- * OnboardingStep (RE): the client may record only its own steps (Config.Onboarding recordedBy = "client": welcome,
--   inspect; NetService already narrows the id). Part 7 reading (DESIGN §11.8 has a "Skip tutorial" link but no
--   remote for onboarding.skipped): the id Config.Onboarding.skipStepId ("skip") sets onboarding.skipped = true
--   instead of marking a step (skip(p): idempotent, a "soon" save, never Coins, the done steps are kept so a later
--   "Replay tutorial" stays local). Server-observed steps are recorded through markStep(p, id) by the
--   wiring below: squeeze (SqueezeService.Squeezed, first accepted squeeze), pen (EconomyService.CoinsChanged: the
--   first spend with reason "pen", a pen spot bought at the sign; pens3 phase 1, was Batch 1's capsule step), firstBox
--   (EconomyService.SquishyGranted from a box or the shop), duel (QueueService.Joined, when that signal exists).
--   Recording is idempotent and never pays Coins (§11.8).
-- * A READY session changes through DataService.mutate (the data port) and asks for a "soon" save. An OFFLINE /
--   READONLY session keeps the change in its in-memory view only (DataService never saves it, §3.9); a loading one has
--   no profile yet and ignores the call.
-- This is the top server layer (§2.6), so it may listen to every service below it; the optional ones (SqueezeService,
-- QueueService) are looked up in init and skipped when missing. Collaborators are reached through `deps` (useDeps in
-- tests).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Types = require(Shared.Types)
local Validate = require(Shared.Util.Validate)
local EconomyService = require(script.Parent.EconomyService)
local NetService = require(script.Parent.NetService)
local StateService = require(script.Parent.StateService)

-- Types

export type Deps = {
	data: StateService.DataPort,
	markDirty: (player: any, field: string) -> (),
}

-- Constants

local REMOTE_SETTINGS = "SetSettings"
local REMOTE_STEP = "OnboardingStep"
local STATUS_READY = "ready"
local STATUS_OFFLINE = "offline"
local STATUS_READONLY = "readonly"
local SAVE_SOON = "soon"
local STEP_SQUEEZE = "squeeze"
local STEP_FIRST_BOX = "firstBox"
local STEP_PEN = "pen"
local PEN_REASON = "pen" -- PenService's Coin reason: its spends are the pen spots (its pay is a grant)
local STEP_DUEL = "duel"
local FIRST_BOX_SOURCES: { [string]: boolean } = { box = true, shop = true }
local SETTING_KEYS = { "music", "sfx", "cameraShake", "showTips" }

local STEP_RECORDER: { [string]: string } = {}
for _, step in Config.Onboarding.Steps do
	STEP_RECORDER[step.id] = step.recordedBy
end

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve these paths statically.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local PreferencesService = {}

-- Private

local log = Log.new("Preferences")
local deps: Deps? = nil

local function defaultDeps(): Deps
	return {
		data = StateService.dataPort(),
		markDirty = function(player: any, field: string)
			StateService.markDirty(player, field)
		end,
	}
end

local function getDeps(): Deps
	local current = deps
	if current then
		return current
	end
	local created = defaultDeps()
	deps = created
	return created
end

local function optionalModule(name: string): any
	local module = script.Parent:FindFirstChild(name)
	if module ~= nil and module:IsA("ModuleScript") then
		local ok, result = pcall(dynamicRequire, module)
		if ok then
			return result
		end
		log:warn(`{name} failed to load:`, result)
	end
	return nil
end

local function connect(signal: any, handler: (...any) -> ()): boolean
	if type(signal) == "table" and type(signal.connect) == "function" then
		signal:connect(handler)
		return true
	end
	return false
end

-- Runs fn(profile) and returns (fn's result, saveable): through mutate on a READY session, directly on the in-memory
-- view of an OFFLINE / READONLY one (never saved); (nil, false) while loading or when the session takes no changes.
local function edit(player: any, fn: (profile: any) -> boolean): (boolean, boolean)
	local data = getDeps().data
	local status = data.status(player)
	if status == STATUS_READY then
		local ok, changed = data.mutate(player, fn)
		return ok and changed == true, true
	elseif status == STATUS_OFFLINE or status == STATUS_READONLY then
		local profile = data.getProfile(player)
		if type(profile) == "table" then
			return fn(profile), false
		end
	end
	return false, false
end

-- After a change landed: the state field and, for a ready session, a "soon" save.
local function changed(player: any, field: string, saveable: boolean)
	local d = getDeps()
	d.markDirty(player, field)
	if saveable then
		d.data.requestSave(player, SAVE_SOON)
	end
end

local function settingsOf(profile: any): { [string]: any }
	local settings = profile.settings
	if type(settings) ~= "table" then
		settings = table.clone(Config.Data.DefaultSettings)
		profile.settings = settings
	end
	return settings
end

local function onboardingOf(profile: any): { [string]: any }
	local onboarding = profile.onboarding
	if type(onboarding) ~= "table" then
		onboarding = { v = Config.Onboarding.version, done = {}, skipped = false }
		profile.onboarding = onboarding
	end
	if type(onboarding.done) ~= "table" then
		onboarding.done = {}
	end
	return onboarding
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Uses these collaborators (nil = the real ones; tests).
function PreferencesService.useDeps(newDeps: Deps?)
	deps = newDeps
end

-- The player's settings (a copy; the Config defaults without a profile).
function PreferencesService.getSettings(player: any): Types.Settings
	local profile = getDeps().data.getProfile(player)
	local source = if type(profile) == "table" and type(profile.settings) == "table"
		then profile.settings
		else Config.Data.DefaultSettings
	return table.clone(source) :: any
end

-- Applies a SetSettings payload (unknown, checked here). Returns true when the payload was valid (even if nothing
-- changed). Only the keys sent change; a valid change is saved "soon" for a ready profile.
function PreferencesService.setSettings(player: any, payload: unknown): boolean
	local patch = Validate.settings(payload)
	if patch == nil then
		return false
	end
	local values = patch :: { [string]: any }
	local didChange, saveable = edit(player, function(profile: any): boolean
		local settings = settingsOf(profile)
		local any = false
		for _, key in SETTING_KEYS do
			local value = values[key]
			if value ~= nil and settings[key] ~= value then
				settings[key] = value
				any = true
			end
		end
		return any
	end)
	if didChange then
		changed(player, "settings", saveable)
	end
	return true -- also while loading: nothing to store yet (the client keeps its own copy)
end

-- True when the onboarding step is recorded for the player.
function PreferencesService.isStepDone(player: any, stepId: string): boolean
	local profile = getDeps().data.getProfile(player)
	if type(profile) ~= "table" or type(profile.onboarding) ~= "table" then
		return false
	end
	local done = profile.onboarding.done
	return type(done) == "table" and done[stepId] == true
end

-- Records an onboarding step (any Config.Onboarding step id). Idempotent. Returns true when it was newly recorded.
function PreferencesService.markStep(player: any, stepId: string): boolean
	if STEP_RECORDER[stepId] == nil then
		log:warn(`markStep: unknown step {tostring(stepId)}`)
		return false
	end
	local recorded, saveable = edit(player, function(profile: any): boolean
		local onboarding = onboardingOf(profile)
		if onboarding.done[stepId] == true then
			return false
		end
		onboarding.done[stepId] = true
		return true
	end)
	if recorded then
		changed(player, "onboarding", saveable)
	end
	return recorded
end

-- "Skip tutorial" (§11.8): sets onboarding.skipped = true. Idempotent ("soon" save only when it changed), never pays
-- Coins and never marks a step. Returns true when newly set.
function PreferencesService.skip(player: any): boolean
	local skipped, saveable = edit(player, function(profile: any): boolean
		local onboarding = onboardingOf(profile)
		if onboarding.skipped == true then
			return false
		end
		onboarding.skipped = true
		return true
	end)
	if skipped then
		changed(player, "onboarding", saveable)
	end
	return skipped
end

-- The OnboardingStep remote: only steps the client records (welcome, inspect), or the skip id
-- (Config.Onboarding.skipStepId), which skips the tutorial. Returns true when something was newly recorded.
function PreferencesService.clientStep(player: any, stepId: unknown): boolean
	if type(stepId) ~= "string" then
		return false
	end
	if stepId == Config.Onboarding.skipStepId then
		return PreferencesService.skip(player)
	end
	if STEP_RECORDER[stepId] ~= "client" then
		return false
	end
	return PreferencesService.markStep(player, stepId)
end

-- Server-observed onboarding steps (§11.8), wired in init.

-- EconomyService.CoinsChanged: the first pen spot bought (a spend, delta < 0, with reason "pen"; the pen's pay has the
-- same reason with delta > 0) completes "pen" (pens3 phase 1).
function PreferencesService.onCoinsChanged(player: any, _coins: number, delta: number, reason: string)
	if reason == PEN_REASON and delta < 0 then
		PreferencesService.markStep(player, STEP_PEN)
	end
end

-- EconomyService.SquishyGranted: the first squishy from a box or the shop completes "firstBox" (the first box always
-- gives a new squishy: the starter is in no box).
function PreferencesService.onSquishyGranted(player: any, _id: string, source: string)
	if FIRST_BOX_SOURCES[source] then
		PreferencesService.markStep(player, STEP_FIRST_BOX)
	end
end

-- SqueezeService.Squeezed (every accepted squeeze): completes "squeeze".
function PreferencesService.onSqueezed(player: any)
	PreferencesService.markStep(player, STEP_SQUEEZE)
end

-- QueueService.Joined (an accepted QueueJoin), when that signal exists: completes "duel".
function PreferencesService.onQueueJoined(player: any)
	PreferencesService.markStep(player, STEP_DUEL)
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function PreferencesService.init()
	NetService.on(REMOTE_SETTINGS, function(player: Player, payload: any)
		PreferencesService.setSettings(player, payload)
	end)
	NetService.on(REMOTE_STEP, function(player: Player, stepId: any)
		PreferencesService.clientStep(player, stepId)
	end)
	EconomyService.CoinsChanged:connect(PreferencesService.onCoinsChanged)
	EconomyService.SquishyGranted:connect(PreferencesService.onSquishyGranted)
	local SqueezeService = optionalModule("SqueezeService")
	if SqueezeService and not connect(SqueezeService.Squeezed, PreferencesService.onSqueezed) then
		log:warn("SqueezeService.Squeezed missing: the onboarding step squeeze is not recorded")
	end
	local QueueService = optionalModule("QueueService")
	if QueueService and not connect(QueueService.Joined, PreferencesService.onQueueJoined) then
		log:info("QueueService.Joined missing: the onboarding step duel is not recorded yet")
	end
end

return PreferencesService
