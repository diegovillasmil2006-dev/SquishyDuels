--!strict
-- PolicyGateService (server only). DESIGN §2.3, §2.6 (join), §2.8 (PolicyRetry), §6.10, §12 #17 and #20.
-- Paid-random-item eligibility per player: "checking" | "eligible" | "restricted" | "unknown" (Types.PolicyState).
-- * Join: the state is "checking" and one check is spawned (never more than one per player at a time):
--   pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player), Config.Monetization.Policy.attempts (3)
--   attempts; a table with a boolean ArePaidRandomItemsRestricted -> "eligible" (false) or "restricted" (true);
--   anything else (an error, a missing or non-boolean field) is a failed attempt, and after the last one the state is
--   "unknown". The check stops as soon as the player has left. The result is cached for the session.
--   Reading: waitSeconds[n] is waited after failed attempt n only when another attempt follows (2 s, then 4 s); the
--   last value (8 s) would only delay "unknown", so nothing is waited after the last attempt.
-- * The state reaches ONLY the owning client, as StateDelta.policy (StateService.setSessionField; it correlates with
--   region and age, so it is never an attribute, §12 #20). It is pushed on every change.
-- * canBuyPaidRandom(p) is true ONLY for "eligible": checking, unknown and restricted all fail closed (§6.10).
--   Regions and ages are never hardcoded.
-- * PolicyRetry (RE, no arguments) -> retry(p): accepted only in "unknown", at least manualRetryMinSeconds (30 s) after
--   the last attempt and at most manualRetryMaxPerSession (5) times per session; anything else is ignored. Reading: a
--   retry runs one attempt (no schedule of its own; the 30 s rule spaces them) and shows "checking" while it runs.
-- * Studio only (RunService:IsStudio() and Config.Debug.debugHooks, §12 #21): debugSetState(p, state) sets any state
--   at once (DebugHooks setPolicy); a check still running is discarded.
-- API: state(p) -> PolicyState ("checking" for a player without an entry: fail closed), canBuyPaidRandom(p),
--   retry(p) -> (accepted, why?), debugSetState(p, state) -> (ok, error?), debugState(). useDeps(overrides?) swaps the
--   collaborators (tests: the PolicyService fetch, the waits, the clock, presence, the state channel, spawn).
-- init() only registers the PolicyRetry handler (no yields); playerAdded spawns the check and never yields.

-- Services

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Types = require(Shared.Types)
local NetService = require(script.Parent.NetService)
local StateService = require(script.Parent.StateService)

-- Types

export type PolicyState = Types.PolicyState

export type Deps = {
	fetch: (player: any) -> any, -- PolicyService:GetPolicyInfoForPlayerAsync(player); yields and may throw
	wait: (seconds: number) -> (), -- yields (task.wait)
	clock: () -> number, -- os.clock: the PolicyRetry spacing (a measurement clock)
	isPresent: (player: any) -> boolean, -- false once the player left
	setState: (player: any, state: PolicyState) -> (), -- StateService.setSessionField(p, "policy", state)
	spawn: (fn: () -> ()) -> (), -- task.spawn
	debugAllowed: () -> boolean, -- Studio and Config.Debug.debugHooks
}

type Entry = {
	state: PolicyState,
	running: boolean, -- a check (join or retry) is running
	generation: number, -- bumped to discard a running check (debugSetState, leave)
	lastAttemptAt: number, -- clock() of the last GetPolicyInfoForPlayerAsync call (-inf before the first)
	manualRetries: number,
}

-- Constants

local POLICY = Config.Monetization.Policy
local REMOTE_RETRY = "PolicyRetry"
local FIELD_POLICY = "policy"
local STATE_CHECKING: PolicyState = "checking"
local STATE_ELIGIBLE: PolicyState = "eligible"
local STATE_RESTRICTED: PolicyState = "restricted"
local STATE_UNKNOWN: PolicyState = "unknown"
local STATES: { [string]: boolean } = { checking = true, eligible = true, restricted = true, unknown = true }

-- Module table

local PolicyGateService = {}

-- Private

local log = Log.new("PolicyGate")
local deps: Deps? = nil
local entries: { [any]: Entry } = {}

local function defaultDeps(): Deps
	return {
		fetch = function(player: any): any
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		clock = os.clock,
		isPresent = function(player: any): boolean
			return typeof(player) == "Instance" and player.Parent == Players
		end,
		setState = function(player: any, state: PolicyState)
			StateService.setSessionField(player, FIELD_POLICY, state)
		end,
		spawn = function(fn: () -> ())
			task.spawn(fn)
		end,
		debugAllowed = function(): boolean
			return RunService:IsStudio() and Config.Debug.debugHooks == true
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

local function userIdOf(player: any): string
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok then tostring(id) else "?"
end

local function setState(player: any, entry: Entry, state: PolicyState)
	entry.state = state
	local ok, err = pcall(function(): any
		getDeps().setState(player, state)
		return nil
	end)
	if not ok then
		log:warn("could not send the policy state:", err)
	end
end

-- One GetPolicyInfoForPlayerAsync call. Returns "eligible" / "restricted", or nil for anything else.
local function attempt(player: any, entry: Entry): PolicyState?
	entry.lastAttemptAt = getDeps().clock()
	local ok, info = pcall(getDeps().fetch, player)
	if not ok then
		log:debug(`user {userIdOf(player)}: policy check failed: {tostring(info)}`)
		return nil
	end
	local restricted = if type(info) == "table" then (info :: any).ArePaidRandomItemsRestricted else nil
	if type(restricted) ~= "boolean" then
		return nil
	end
	return if restricted then STATE_RESTRICTED else STATE_ELIGIBLE
end

-- Runs up to `attempts` checks (waiting between failed ones), then sets the state. Stops when the player left or the
-- check was discarded (generation changed).
local function runCheck(player: any, entry: Entry, attempts: number, generation: number)
	local result: PolicyState? = nil
	for n = 1, attempts do
		if entries[player] ~= entry or entry.generation ~= generation or not getDeps().isPresent(player) then
			if entry.generation == generation then
				entry.running = false
			end
			return
		end
		result = attempt(player, entry)
		if result ~= nil then
			break
		end
		if n < attempts then
			getDeps().wait(POLICY.waitSeconds[n] or 0)
		end
	end
	if entries[player] ~= entry or entry.generation ~= generation then
		return -- discarded (left, or a Studio debug state replaced it)
	end
	entry.running = false
	local final: PolicyState = result or STATE_UNKNOWN
	if final == STATE_UNKNOWN then
		log:info(`user {userIdOf(player)}: paid-random eligibility unknown after {attempts} attempt(s)`)
	end
	setState(player, entry, final)
end

local function startCheck(player: any, entry: Entry, attempts: number)
	entry.running = true
	local generation = entry.generation -- a later debugSetState or leave discards this check
	getDeps().spawn(function()
		local ok, err = pcall(function(): any
			runCheck(player, entry, attempts, generation)
			return nil
		end)
		if not ok then
			log:error(`policy check failed for user {userIdOf(player)}:`, err)
			if entries[player] == entry and entry.generation == generation then
				entry.running = false
				setState(player, entry, STATE_UNKNOWN)
			end
		end
	end)
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Replaces collaborators (fields not given keep their defaults; nil restores every default) and forgets every player.
function PolicyGateService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
	entries = {}
end

-- The player's state; "checking" for a player without an entry (fail closed).
function PolicyGateService.state(player: any): PolicyState
	local entry = entries[player]
	return if entry then entry.state else STATE_CHECKING
end

-- True ONLY for "eligible" (§6.10): checking, unknown and restricted are all treated as restricted.
function PolicyGateService.canBuyPaidRandom(player: any): boolean
	return PolicyGateService.state(player) == STATE_ELIGIBLE
end

-- PolicyRetry (§2.8, §6.10): only in "unknown", >= manualRetryMinSeconds since the last attempt, <= the session limit.
-- Returns (true) when a retry started, else (false, why) with why "state" | "running" | "tooSoon" | "limit".
function PolicyGateService.retry(player: any): (boolean, string?)
	local entry = entries[player]
	if entry == nil or entry.state ~= STATE_UNKNOWN then
		return false, "state"
	elseif entry.running then
		return false, "running"
	elseif getDeps().clock() - entry.lastAttemptAt < POLICY.manualRetryMinSeconds then
		return false, "tooSoon"
	elseif entry.manualRetries >= POLICY.manualRetryMaxPerSession then
		return false, "limit"
	end
	entry.manualRetries += 1
	setState(player, entry, STATE_CHECKING)
	startCheck(player, entry, 1)
	return true, nil
end

-- Studio only: sets the state at once (a running check is discarded). Returns (ok, error?).
function PolicyGateService.debugSetState(player: any, state: unknown): (boolean, string?)
	if not getDeps().debugAllowed() then
		return false, "Studio only"
	end
	if type(state) ~= "string" or not STATES[state] then
		return false, "state must be checking, eligible, restricted or unknown"
	end
	local entry = entries[player]
	if entry == nil then
		return false, "no policy entry for this player"
	end
	entry.generation += 1
	entry.running = false
	setState(player, entry, state :: PolicyState)
	return true, nil
end

-- Studio debug view: { [userId] = {state, running, manualRetries, secondsSinceAttempt} }.
function PolicyGateService.debugState(): { [string]: any }
	local view: { [string]: any } = {}
	local now = getDeps().clock()
	for player, entry in entries do
		view[userIdOf(player)] = {
			state = entry.state,
			running = entry.running,
			manualRetries = entry.manualRetries,
			secondsSinceAttempt = if entry.lastAttemptAt > -math.huge then now - entry.lastAttemptAt else nil,
		}
	end
	return view
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function PolicyGateService.init()
	NetService.on(REMOTE_RETRY, function(player: Player)
		local accepted, why = PolicyGateService.retry(player)
		if not accepted then
			log:debug(`user {player.UserId}: PolicyRetry ignored ({tostring(why)})`)
		end
	end)
end

function PolicyGateService.playerAdded(player: Player)
	if entries[player] ~= nil then
		return
	end
	local entry: Entry = {
		state = STATE_CHECKING,
		running = false,
		generation = 0,
		lastAttemptAt = -math.huge,
		manualRetries = 0,
	}
	entries[player] = entry
	setState(player, entry, STATE_CHECKING)
	startCheck(player, entry, POLICY.attempts)
end

function PolicyGateService.playerRemoving(player: Player)
	local entry = entries[player]
	if entry then
		entry.generation += 1
		entries[player] = nil
	end
end

return PolicyGateService
