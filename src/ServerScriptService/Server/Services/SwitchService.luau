--!strict
-- SwitchService (server only; 2026-11-10, big job item 3). The emergency switches of Config.Switches: one boolean per
-- feature in Roblox's experience configs (ConfigService), read live, so a broken feature can be closed in every
-- server from Creator Hub > Configs without a publish (LihFolk vault "Global State and Live Config": kill switches).
--   SwitchService.isOn(feature)        false only while the config key `switch_<feature>` is the boolean false
--   SwitchService.allows(remoteName)   false while the remote's feature is off (NetService's gate, set in init)
--   SwitchService.featureOf(remote)    the feature a remote belongs to, or nil
--   SwitchService.value(key)           any config key as stored, or nil (item 4: the live redeem codes, `codes`)
--   SwitchService.refused(player)      true when this player may get the "closed" toast now (rate limit)
--   SwitchService.debugSet(feature, on?)  Studio: ConfigService:SetTestingValue on this server (nil clears it)
--   SwitchService.debugState()
-- Rules: defaults in code (ON); a missing key, a wrong type or configs that never loaded all mean ON (the game runs
-- as built). A snapshot refreshes as soon as Roblox says newer values exist (kill switches refresh at once, the
-- vault's rule); every change is logged. init() does not yield; start() loads the snapshot.
-- Dependencies are injectable (useDeps) for unit tests.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)
local Switches = require(Shared.Config.Switches)
local NetService = require(script.Parent.NetService)

-- Types

-- The part of ConfigService and its snapshot this module uses.
export type Snapshot = {
	GetValue: (self: any, key: string) -> any,
	Refresh: (self: any) -> (),
	UpdateAvailable: any,
}
export type Deps = {
	getSnapshot: () -> Snapshot, -- ConfigService:GetConfigAsync() (may throw)
	setTesting: (key: string, value: any) -> (),
	clearTesting: (key: string) -> (),
	clock: () -> number,
}

-- Constants

local PREFIX = Switches.keyPrefix
local RETRY_SECONDS = 30 -- configs that could not load are tried again this often

-- Module table

local SwitchService = {}

-- Private

local log = Log.new("Switches")

local function defaultDeps(): Deps
	local ConfigService = game:GetService("ConfigService") :: any
	return {
		getSnapshot = function(): Snapshot
			return ConfigService:GetConfigAsync()
		end,
		setTesting = function(key: string, value: any)
			ConfigService:SetTestingValue(key, value)
		end,
		clearTesting = function(key: string)
			ConfigService:ClearTestingValue(key)
		end,
		clock = os.clock,
	}
end

local deps: Deps = defaultDeps()
local snapshot: Snapshot? = nil
-- What each key held when it was first read since the last load or refresh (NONE = no such key). Roblox writes a
-- warning into the server log for every GetValue of a key that does not exist, and NetService asks about a switch on
-- every request (a squeeze: up to 18 a second per player), so a key is read once and remembered (seen in a test game
-- 2026-11-10: one warning per squeeze).
local NONE = table.freeze({})
local values: { [string]: any } = {}
local featureByRemote: { [string]: string } = {}
local known: { [string]: boolean } = {} -- feature -> its last logged state
local lastNotice: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local started = false

for feature, remotes in Switches.features do
	known[feature] = true
	for _, remote in remotes do
		featureByRemote[remote] = feature
	end
end

-- Logs every switch whose state changed since the last look (the vault: changes logged).
local function logChanges()
	for feature, was in known do
		local now = SwitchService.isOn(feature)
		if now ~= was then
			known[feature] = now
			log:warn(`switch {PREFIX}{feature} is now {if now then "ON" else "OFF (its requests are refused)"}`)
		end
	end
end

-- Big job item 8 (2026-11-10): readers of a live value (the update countdown's date) hear every load and change.
local listeners: { () -> () } = {}

local function changed()
	logChanges()
	for _, listener in listeners do
		task.spawn(listener)
	end
end

local function load(): boolean
	local ok, result = pcall(deps.getSnapshot)
	if not ok then
		log:warn("configs unavailable, every switch stays ON:", result)
		return false
	end
	local snap = result :: Snapshot
	snapshot = snap
	table.clear(values)
	snap.UpdateAvailable:Connect(function()
		local refreshed, err = pcall(function()
			snap:Refresh()
		end)
		if not refreshed then
			log:warn("config refresh failed (the old values stay):", err)
		end
		table.clear(values)
		changed()
	end)
	changed()
	return true
end

-- Public

function SwitchService.featureOf(remoteName: string): string?
	return featureByRemote[remoteName]
end

-- ON unless the config key holds the boolean false. An unknown feature is ON (nothing can be closed by a typo).
function SwitchService.isOn(feature: string): boolean
	if Switches.features[feature] == nil then
		return true
	end
	return SwitchService.value(PREFIX .. feature) ~= false
end

function SwitchService.allows(remoteName: string): boolean
	local feature = featureByRemote[remoteName]
	return feature == nil or SwitchService.isOn(feature)
end

-- Any experience config key as stored (nil: no such key, or configs not loaded). The caller checks its type
-- (CodeService reads the live codes, the JSON key `codes`).
function SwitchService.value(key: string): any
	local snap = snapshot
	if snap == nil then
		return nil
	end
	local held = values[key]
	if held == nil then
		local ok, value = pcall(function(): any
			return snap:GetValue(key)
		end)
		held = if ok and value ~= nil then value else NONE
		values[key] = held
	end
	return if held == NONE then nil else held
end

-- True when `player` may be told now that a feature is closed (at most once every notifyEverySeconds).
function SwitchService.refused(player: Player): boolean
	local now = deps.clock()
	local last = lastNotice[player]
	if last ~= nil and now - last < Switches.notifyEverySeconds then
		return false
	end
	lastNotice[player] = now
	return true
end

-- Studio / the server console: this server only (ConfigService's testing values). on = nil clears the override.
function SwitchService.debugSet(feature: string, on: boolean?): (boolean, string?)
	if Switches.features[feature] == nil then
		return false, "no such switch"
	end
	local ok, err = pcall(function()
		if on == nil then
			deps.clearTesting(PREFIX .. feature)
		else
			deps.setTesting(PREFIX .. feature, on)
		end
	end)
	if ok and snapshot then
		pcall(function()
			(snapshot :: Snapshot):Refresh()
		end)
		table.clear(values)
		logChanges()
	end
	return ok, if ok then nil else tostring(err)
end

function SwitchService.debugState(): { [string]: any }
	local state: { [string]: any } = { loaded = snapshot ~= nil }
	for feature in Switches.features do
		state[feature] = SwitchService.isOn(feature)
	end
	return state
end

-- Tests: other dependencies (nil = the real ones) and a clean state.
function SwitchService.useDeps(overrides: { [string]: any }?)
	local d = defaultDeps() :: any
	for key, value in overrides or {} do
		d[key] = value
	end
	deps = d
	snapshot = nil
	table.clear(values)
	started = false
	table.clear(lastNotice)
	for feature in known do
		known[feature] = true
	end
end

-- Big job item 8: `listener` runs (in its own thread) after the configs load and after every change of them.
function SwitchService.onChanged(listener: () -> ())
	table.insert(listeners, listener)
end

-- Tests: loads the snapshot now (start() does it in the background, retrying).
function SwitchService.loadNow(): boolean
	return load()
end

function SwitchService.init()
	NetService.setGate(SwitchService.allows, function(player: Player)
		if SwitchService.refused(player) then
			NetService.notify(player, Switches.reason, nil, "info")
		end
	end, Switches.reason)
end

function SwitchService.start()
	if started then
		return
	end
	started = true
	while started and not load() do
		task.wait(RETRY_SECONDS)
	end
end

return SwitchService
