--!strict
-- StateService (server only). DESIGN §2.3, §2.6, §2.7 (state versioning), §2.8 (RequestSnapshot, StateDelta),
-- §3.1 / §3.13 / §11.3 (data status), §17.10 (the grip field), §12 #20.
-- The one state channel to a client. It projects the player's profile (DataService) plus session data into a
-- Snapshot and sends versioned StateDelta batches:
-- * RequestSnapshot (RF): {status = "loading"} while the profile loads, else the full Snapshot. Result.v (NetService's
--   version provider, set in init) is this player's state version.
-- * DataService.StatusChanged / Loaded -> one full StateDelta(v + 1, every field, true) the first time the player has
--   a profile, and again whenever DataService swaps in another profile table (an OFFLINE session that loaded on a
--   retry, §3.13), then Notify("data.loaded") "Progress loaded!" (only this module sends it); any other status change
--   -> dataStatus.
-- * Changes: services call markDirty(p, field) (EconomyService, InventoryService and PreferencesService here; from the
--   layers above SqueezeService, GripService, ...). Dirty fields are flushed once per frame (task.defer) as one
--   StateDelta(v + 1, changedFields); a field goes out only when its value really changed (deep compare with what this
--   client last got). Reading (§2.8 "pushes on every change" without trusting every writer to mark): a sweep every
--   SWEEP_SECONDS compares every field too, so a change nobody marked still reaches the client within a second.
-- * No partial StateDelta goes out before the client got a full state (a full StateDelta or a Snapshot reply): a
--   client holding a newer partial version would drop its first full Snapshot as "older data" (§2.7).
-- * Session fields (not in the profile, set by their owners through setSessionField): policy (PolicyGateService,
--   Part 7; "checking" until set, §6.10), monetization ({bundles = {}, passes = {}} until set: no bundle is offered
--   while every productId is nil, §6.11) and practice (PracticeService's session stats; {throws = 0, hits = 0,
--   accuracy = 0} until set, which is what a session with no practice throw has: Types.Snapshot holds every field).
-- * dataStatus = Types.DataStatus {status, persisted, savePending, banner?}. `banner` (reading) is the Strings key of
--   the honest status banner (bannerFor, from the status, persisted and DataService.statusReason): Studio memory mode
--   (ready, persisted = false) data.studioMemory "Studio test: progress is not saved." (§3.1, §11.3); OFFLINE
--   data.offlineRetrying, and data.loadFailed once the background retries are used up (reading: §11.3's "Data load
--   failed" line, which ends with "Please rejoin."); READONLY data.newerVersion (newer schema), data.rejoin (lock lost)
--   or data.loadFailed (a stored value that is not a profile, or no reason). DataService sends none of these texts.
-- * grip = {total, rested} (§17.10), copied from profile.grip (build plan Phase 6: an old save's slow-training
--   bank, grip.afk, and its trainer, grip.trainer, are not sent); StateService is not a duel-path file.
-- * capsules = profile.capsules {slots, list} as stored (build plan Phase 5: the owner's capsule card, the squeeze
--   value of the reward texts and the owner's capsule pops; CapsuleService marks it on every change).
--
-- dataPort() is the one reading of DataService for this layer (EconomyService, InventoryService and
-- PreferencesService use it as their default, and so do services above them). portFrom(source) builds the same port
-- over any object with DataService's API (the module, or a core from DataService.newCore in tests):
--   getProfile(p) -> the live profile table (ready, OFFLINE defaults, READONLY view; nil while loading); status(p) ->
--   "loading" | "ready" | "offline" | "readonly" (no session, or anything unknown, reads as loading: fail closed);
--   persisted(p) / savePending(p); statusReason(p) (why a session is not ready: "retrying" | "exhausted" | "newer" |
--   "lost" | "corrupt" | nil); mutate(p, fn) -> (ok, fn's result | reason): fn(profile) runs synchronously on a READY
--   session only (the one way to change a saved profile, §3.9, §3.11); requestSave(p, reason);
--   onLoaded(handler(p)) / onStatusChanged(handler(p)).
-- useDeps(deps) swaps every collaborator (tests); init() wires the real ones. playerAdded / playerRemoving never yield.
-- A player who left never gets a session again (a late StatusChanged, e.g. from a failed final save, or a late
-- markDirty would otherwise leave one behind).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)
local DataService = require(script.Parent.DataService)
local NetService = require(script.Parent.NetService)

-- Types

-- The DataService reading every service of this layer uses (see the header).
export type DataPort = {
	getProfile: (player: any) -> any?, -- the live profile table, nil while loading
	status: (player: any) -> string, -- "loading" | "ready" | "offline" | "readonly"
	persisted: (player: any) -> boolean,
	savePending: (player: any) -> boolean,
	statusReason: (player: any) -> string?, -- why a session is OFFLINE / READONLY (DataService.statusReason)
	mutate: (player: any, fn: (profile: any) -> any) -> (boolean, any), -- READY sessions only
	requestSave: (player: any, reason: string) -> (),
	onLoaded: (handler: (player: any) -> ()) -> (),
	onStatusChanged: (handler: (player: any) -> ()) -> (),
}

export type Deps = {
	data: DataPort,
	fire: (name: string, player: any, ...any) -> (),
	notify: (player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?) -> (),
	isPlayer: (player: any) -> boolean, -- a player a session may be created for
	defer: (fn: () -> ()) -> (),
}

type Session = {
	v: number,
	fullSent: boolean,
	lastSent: { [string]: any },
	dirty: { [string]: boolean },
	values: { [string]: any }, -- session fields
	profileRef: any?, -- the profile table of the last full send
	lastStatus: string?,
}

-- Constants

-- Every StateDelta field (§2.8, §17.10), in send order.
local FIELDS: { string } = {
	"coins",
	"owned",
	"equipped",
	"stats",
	"squeezeLimit",
	"quests",
	"daily",
	"settings",
	"onboarding",
	"policy",
	"dataStatus",
	"monetization",
	"unseenReveals",
	"practice",
	"grip",
	"capsules",
}
local FIELD_SET: { [string]: boolean } = {}
for _, field in FIELDS do
	FIELD_SET[field] = true
end
local SESSION_FIELDS: { [string]: boolean } = { policy = true, monetization = true, practice = true }

local STATUS_LOADING = "loading"
local STATUS_READY = "ready"
local STATUS_OFFLINE = "offline"
local STATUS_READONLY = "readonly"
local KNOWN_STATUS: { [string]: boolean } = { loading = true, ready = true, offline = true, readonly = true }

local REMOTE_DELTA = "StateDelta"
local REMOTE_SNAPSHOT = "RequestSnapshot"
local NOTICE_LOADED = "data.loaded"
local BANNER_STUDIO_MEMORY = "data.studioMemory"
local BANNER_OFFLINE = "data.offlineRetrying"
local BANNER_LOAD_FAILED = "data.loadFailed"
local BANNER_NEWER = "data.newerVersion"
local BANNER_REJOIN = "data.rejoin"
local REASON_EXHAUSTED = "exhausted"
local REASON_NEWER = "newer"
local REASON_LOST = "lost"

local DEFAULT_POLICY: Types.PolicyState = "checking"
local DEFAULT_MONETIZATION = table.freeze({ bundles = table.freeze({}), passes = table.freeze({}) })
local DEFAULT_PRACTICE = table.freeze({ throws = 0, hits = 0, accuracy = 0 })
local SWEEP_SECONDS = 1 -- reading: the safety-net compare of every field (see the header)

-- Module table

local StateService = {}

-- Private

local log = Log.new("State")
local deps: Deps? = nil
local sessions: { [any]: Session } = {}
local departed: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local flushScheduled = false
local sweeping = false

local function connect(signal: any, handler: (player: any) -> ())
	signal:connect(function(player: any)
		handler(player)
	end)
end

local function defaultDeps(): Deps
	return {
		data = StateService.portFrom(DataService),
		fire = function(name: string, player: any, ...: any)
			NetService.fire(name, player, ...)
		end,
		notify = function(player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
			NetService.notify(player, code, args, kind)
		end,
		isPlayer = function(player: any): boolean
			return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
		end,
		defer = function(fn: () -> ())
			task.defer(fn)
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

local function newSession(): Session
	return {
		v = 0,
		fullSent = false,
		lastSent = {},
		dirty = {},
		values = {},
		profileRef = nil,
		lastStatus = nil,
	}
end

-- The player's session; created for a player in the game (never for one who already left).
local function sessionOf(player: any, create: boolean): Session?
	local session = sessions[player]
	if session == nil and create and not departed[player] and getDeps().isPlayer(player) then
		session = newSession()
		sessions[player] = session
	end
	return session
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function statusView(player: any): Types.DataStatus
	local data = getDeps().data
	local status = data.status(player)
	local persisted = data.persisted(player)
	return {
		status = status :: Types.DataStatusName,
		persisted = persisted,
		savePending = data.savePending(player),
		banner = StateService.bannerFor(status, persisted, data.statusReason(player)),
	}
end

-- The profile the client is shown (nil while loading).
local function profileFor(player: any, status: string): any?
	if status == STATUS_LOADING then
		return nil
	end
	local profile = getDeps().data.getProfile(player)
	return if type(profile) == "table" then profile else nil
end

local function listOf(value: any): { any }
	return if type(value) == "table" then value else {}
end

-- One field as it is now (may share tables with the profile; copied before it is sent or remembered).
local function rawField(field: string, profile: any, values: { [string]: any }, status: Types.DataStatus): any
	if field == "dataStatus" then
		return status
	elseif field == "policy" then
		return if values.policy ~= nil then values.policy else DEFAULT_POLICY
	elseif field == "monetization" then
		return if values.monetization ~= nil then values.monetization else DEFAULT_MONETIZATION
	elseif field == "practice" then
		return if values.practice ~= nil then values.practice else DEFAULT_PRACTICE
	elseif type(profile) ~= "table" then
		return nil
	elseif field == "quests" then
		local quests = listOf(profile.quests) :: any
		return { day = quests.day, swapsUsed = quests.swapsUsed, active = quests.active, starter = profile.starter }
	elseif field == "unseenReveals" then
		local list = {}
		for _, entry in listOf(profile.boxLog) do
			if type(entry) == "table" and entry.seen == false then
				table.insert(list, entry)
			end
		end
		return list
	elseif field == "grip" then
		local grip = profile.grip
		if type(grip) ~= "table" then
			return nil
		end
		return { total = grip.total, rested = grip.rested }
	end
	return profile[field]
end

local function allFields(profile: any, values: { [string]: any }, status: Types.DataStatus): { [string]: any }
	local fields: { [string]: any } = {}
	for _, field in FIELDS do
		local value = rawField(field, profile, values, status)
		if value ~= nil then
			fields[field] = TableUtil.deepCopy(value)
		end
	end
	return fields
end

-- Remembers `fields` as what the client now holds in full.
local function markFull(session: Session, fields: { [string]: any }, profile: any, status: string)
	session.fullSent = true
	session.lastSent = fields
	session.profileRef = profile
	session.lastStatus = status
	table.clear(session.dirty)
end

local function sendFull(player: any, session: Session, profile: any, status: Types.DataStatus)
	local fields = allFields(profile, session.values, status)
	session.v += 1
	markFull(session, fields, profile, status.status)
	getDeps().fire(REMOTE_DELTA, player, session.v, fields, true)
end

-- Sends the fields among `candidates` whose value changed since the client last got them. Returns true when sent.
local function flushPlayer(player: any, session: Session, candidates: { string }): boolean
	table.clear(session.dirty)
	if not session.fullSent then
		return false -- the first full state carries everything
	end
	local status = statusView(player)
	local profile = profileFor(player, status.status)
	local changed: { [string]: any } = {}
	local any = false
	for _, field in candidates do
		local value = rawField(field, profile, session.values, status)
		-- A field that became nil cannot be sent in a partial delta (nil values vanish); it keeps its last value.
		if value ~= nil and not deepEqual(value, session.lastSent[field]) then
			local copy = TableUtil.deepCopy(value)
			changed[field] = copy
			session.lastSent[field] = copy
			any = true
		end
	end
	if not any then
		return false
	end
	session.v += 1
	getDeps().fire(REMOTE_DELTA, player, session.v, changed)
	return true
end

local function dirtyFields(session: Session): { string }
	local candidates: { string } = {}
	for _, field in FIELDS do
		if session.dirty[field] then
			table.insert(candidates, field)
		end
	end
	return candidates
end

local function flushAll()
	for player, session in table.clone(sessions) do
		if next(session.dirty) ~= nil then
			local ok, err = pcall(flushPlayer, player, session, dirtyFields(session))
			if not ok then
				log:error("StateDelta flush failed:", err)
			end
		end
	end
end

local function scheduleFlush()
	if flushScheduled then
		return
	end
	flushScheduled = true
	getDeps().defer(function()
		flushScheduled = false
		flushAll()
	end)
end

-- Status bookkeeping shared by Loaded, StatusChanged and the sweep: a new (or swapped-in) profile table gets a full
-- send; anything else only refreshes dataStatus. An OFFLINE session that became ready gets "Progress loaded!" (§3.13).
local function checkStatus(player: any, session: Session)
	local previous = session.lastStatus
	local status = statusView(player)
	local profile = profileFor(player, status.status)
	if profile ~= nil and (not session.fullSent or profile ~= session.profileRef) then
		sendFull(player, session, profile, status)
	elseif session.fullSent then
		session.lastStatus = status.status
		session.dirty.dataStatus = true
		scheduleFlush()
	end
	if previous == STATUS_OFFLINE and status.status == STATUS_READY then
		getDeps().notify(player, NOTICE_LOADED, nil, "success")
	end
end

-- Public: pure helpers (unit-tested) -----------------------------------------------------------------------------------

-- A DataService status as one of "loading" / "ready" / "offline" / "readonly"; nil (no session) or anything unknown
-- reads as "loading", which allows nothing (fail closed).
function StateService.normalizeStatus(value: unknown): string
	if type(value) == "string" and KNOWN_STATUS[value] then
		return value
	end
	return STATUS_LOADING
end

-- The Strings key of the status banner the client shows, or nil for none (§3.1, §3.13, §11.3; see the header).
-- `reason` is DataService.statusReason.
function StateService.bannerFor(status: string, persisted: boolean, reason: string?): string?
	if status == STATUS_READY then
		return if persisted then nil else BANNER_STUDIO_MEMORY
	elseif status == STATUS_OFFLINE then
		return if reason == REASON_EXHAUSTED then BANNER_LOAD_FAILED else BANNER_OFFLINE
	elseif status == STATUS_READONLY then
		if reason == REASON_NEWER then
			return BANNER_NEWER
		elseif reason == REASON_LOST then
			return BANNER_REJOIN
		end
		return BANNER_LOAD_FAILED
	end
	return nil
end

-- Every field of a Snapshot for this profile, session values and data status (fresh copies; a profile field the
-- profile lacks, such as grip on a table that was never reconciled, is left out).
function StateService.project(profile: any, values: { [string]: any }?, status: Types.DataStatus): { [string]: any }
	return allFields(profile, values or {}, status)
end

-- The StateDelta field names, in send order.
function StateService.fields(): { string }
	return table.clone(FIELDS)
end

-- The data port over an object with DataService's API: the DataService module, or a core (DataService.newCore).
function StateService.portFrom(source: any): DataPort
	return {
		getProfile = function(player: any): any?
			local profile = source.getProfile(player)
			return if type(profile) == "table" then profile else nil
		end,
		status = function(player: any): string
			return StateService.normalizeStatus(source.getStatus(player))
		end,
		persisted = function(player: any): boolean
			return source.isPersisted(player) == true
		end,
		savePending = function(player: any): boolean
			return source.isSavePending(player) == true
		end,
		statusReason = function(player: any): string?
			local reason = source.statusReason(player)
			return if type(reason) == "string" then reason else nil
		end,
		mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
			return source.mutate(player, fn)
		end,
		requestSave = function(player: any, reason: string)
			source.requestSave(player, reason)
		end,
		onLoaded = function(handler: (player: any) -> ())
			connect(source.Loaded, handler)
		end,
		onStatusChanged = function(handler: (player: any) -> ())
			connect(source.StatusChanged, handler)
		end,
	}
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Uses these collaborators (nil = the real ones) and forgets every session (tests).
function StateService.useDeps(newDeps: Deps?)
	deps = newDeps
	sessions = {}
	departed = setmetatable({}, { __mode = "k" }) :: any
	flushScheduled = false
end

-- The DataService reading for this layer (see the header). EconomyService, InventoryService and PreferencesService
-- use it as their default.
function StateService.dataPort(): DataPort
	return getDeps().data
end

-- The player's state version (Result.v and the last StateDelta's v); 0 before anything was sent.
function StateService.version(player: any): number
	local session = sessions[player]
	return if session then session.v else 0
end

-- The full Snapshot, or nil while the profile is loading.
function StateService.snapshot(player: any): { [string]: any }?
	local session = sessionOf(player, true) or newSession()
	local status = statusView(player)
	local profile = profileFor(player, status.status)
	if profile == nil then
		return nil
	end
	return allFields(profile, session.values, status)
end

-- The RequestSnapshot reply (§2.8): ok(Snapshot) or ok({status = "loading"}). A Snapshot reply counts as the
-- client's full state (later changes go out as partial StateDeltas).
function StateService.requestSnapshot(player: any): any
	local session = sessionOf(player, true)
	local status = statusView(player)
	local profile = profileFor(player, status.status)
	if session == nil or profile == nil then
		local loading: Types.SnapshotLoading = { status = "loading" }
		return NetService.ok(loading)
	end
	local fields = allFields(profile, session.values, status)
	markFull(session, fields, profile, status.status)
	return NetService.ok(fields)
end

-- Marks one field (nil = every field) of the player as changed; it is sent with the next batch (this frame).
function StateService.markDirty(player: any, field: string?)
	local session = sessionOf(player, true)
	if session == nil then
		return
	end
	if field == nil then
		for _, name in FIELDS do
			session.dirty[name] = true
		end
	elseif FIELD_SET[field] then
		session.dirty[field] = true
	else
		log:warn(`markDirty: unknown field {field}`)
		return
	end
	scheduleFlush()
end

-- Sends the pending changes now (one player, or everyone). Returns true when a StateDelta went out (one player).
function StateService.flush(player: any?): boolean
	if player == nil then
		flushAll()
		return false
	end
	local session = sessions[player]
	if session == nil or next(session.dirty) == nil then
		return false
	end
	return flushPlayer(player, session, dirtyFields(session))
end

-- DataService.Loaded: the full state (once per profile table).
function StateService.loaded(player: any)
	local session = sessionOf(player, true)
	if session then
		checkStatus(player, session)
	end
end

-- DataService.StatusChanged: dataStatus (or the full state when the profile table is new).
function StateService.statusChanged(player: any)
	local session = sessionOf(player, true)
	if session then
		checkStatus(player, session)
	end
end

-- Sets a session field that is not part of the profile: "policy", "monetization" or "practice" (their owners call
-- it on every change). The value is copied.
function StateService.setSessionField(player: any, field: string, value: any)
	assert(SESSION_FIELDS[field], `[SD][State] {field} is not a session field`)
	local session = sessionOf(player, true)
	if session == nil then
		return
	end
	session.values[field] = TableUtil.deepCopy(value)
	session.dirty[field] = true
	scheduleFlush()
end

-- Compares every field of every player with what the client has and sends the differences (the sweep; it also
-- notices a profile table nobody announced).
function StateService.sweep()
	for player, session in table.clone(sessions) do
		local ok, err = pcall(function(): any
			local status = getDeps().data.status(player)
			if status ~= session.lastStatus or not session.fullSent then
				checkStatus(player, session)
			end
			if session.fullSent then
				flushPlayer(player, session, FIELDS)
			end
			return nil
		end)
		if not ok then
			log:error("state sweep failed:", err)
		end
	end
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function StateService.init()
	local d = getDeps()
	NetService.setVersionProvider(function(player: Player): number
		return StateService.version(player)
	end)
	NetService.onInvoke(REMOTE_SNAPSHOT, function(player: Player): any
		return StateService.requestSnapshot(player)
	end)
	d.data.onStatusChanged(StateService.statusChanged)
	d.data.onLoaded(StateService.loaded)
end

function StateService.start()
	if sweeping then
		return
	end
	sweeping = true
	while sweeping do
		task.wait(SWEEP_SECONDS)
		StateService.sweep()
	end
end

function StateService.playerAdded(player: Player)
	departed[player] = nil
	if sessions[player] == nil then
		sessions[player] = newSession()
	end
end

function StateService.playerRemoving(player: Player)
	sessions[player] = nil
	departed[player] = true
end

-- Not called by the bootstrap; used by leak checks.
function StateService.destroy()
	sweeping = false
	sessions = {}
end

return StateService
