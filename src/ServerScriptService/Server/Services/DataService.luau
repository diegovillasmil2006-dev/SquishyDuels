--!strict
-- DataService (server only). Profiles, the session lock and every save (DESIGN §3, §12 #14 #19, §17.10).
-- Layer: Net, Shutdown, Data (§2.6). It requires only lower layers (Logic, Data adapters, NetService for Notify,
-- ShutdownService for the close hook); services above it read and change profiles through this API and listen to
-- its signals.
--
-- Store selection (§3.1, selectStore): live -> PlayerData_v1 (persisted); Studio with Config.Data.studioMode =
--   "memory" (the default) -> InMemoryAdapter (persisted = false; the client shows "Studio test: progress is not
--   saved." while dataStatus is ready and not persisted); Studio with "datastore" -> PlayerData_v1_STUDIO after a
--   read-only boot probe (a "Studio access" error falls back to memory). Any userId <= 0 always uses memory. Boot
--   asserts when Studio would open a store whose name does not end in "_STUDIO" (DataStoreAdapter enforces it too).
-- Load (§3.8): per player, one KeyQueue job per attempt through UpdateAsync ONLY. The transform evaluates the lock
--   (Logic/SessionLock): "foreign" -> no write, wait 6 +- 2 s and retry until 45 s, then OFFLINE; a stored
--   schemaVersion above ProfileSchema.CURRENT -> no write, READONLY (shown, never saved); a stored value that is not
--   a table -> no write, READONLY with defaults (reading); otherwise the lock is written (a first-time key gets
--   defaults atomically) and ProfileSchema.load runs migrate -> reconcile -> sanitize. A load that fails after the
--   retries -> OFFLINE with defaults in memory, never saved, and a background retry every 60 s up to 5 times (it
--   also takes over a lock once it is stale). Status "ready" fires Loaded.
-- Save (§3.9): a job takes its snapshot when it STARTS (deepCopy, saveSeq + 1, lastSeenAt = now) and writes it only
--   if the lock is still ours and the stored saveSeq is not above the snapshot's (else lock lost -> READONLY +
--   Notify data.openedElsewhere). A ghost write leaves the stored saveSeq equal to ours, so the retry is accepted.
--   Reasons: "autosave" every 120 s (random first offset; delayed 15 s while the request budget is below 10),
--   "soon" one timer at max(now + 6, lastWriteAt + 6) that later requests join, "now" joins a queued save that has
--   not started (or queues one right behind the running one) and is awaited, "release" (leave, shutdown) removes
--   the lock and drops the session. Only ready sessions (and the release of a ready session) are ever written:
--   OFFLINE, READONLY and loading sessions never are, so defaults never overwrite unloaded data.
-- Leave and close (§3.12): playerRemoving -> releaseAsync (idempotent; concurrent calls share one job; a load in
--   progress is cancelled and unlocks the key if it got the lock). ShutdownService's only BindToClose runs
--   releaseAllAsync (every session in parallel, KeyQueue:dropPendingExceptLast) within Config.Data.closeDeadline.
--   Redundant jobs: a session never has more than one save that has not started (later requests join it), and a
--   release turns that queued save into the final write instead of queueing another one; dropPendingExceptLast is
--   the safety net for anything else still pending at close (every write is a full snapshot, so folding is safe).
-- Transforms are pure (no yields, grants or remotes; they capture locals only) and always return {userId} and the
--   metadata table, because omitting them clears them (§3.6, §12 #19).
--
-- API (module level; every function is safe before init and for unknown players):
--   getProfile(p) -> live profile table or nil (ready, OFFLINE defaults, READONLY view; nil while loading). Change it
--     only through mutate.
--   getStatus(p) -> "loading" | "ready" | "offline" | "readonly" | nil (no session)
--   dataStatus(p) -> Types.DataStatus {status, persisted, savePending} (StateDelta.dataStatus)
--   isReady(p) -> boolean;  isPersisted(p) -> boolean;  isSavePending(p) -> boolean
--   waitForProfileAsync(p, timeout?) -> profile of a READY session, or nil (left, OFFLINE, READONLY, timeout)
--   mutate(p, fn) -> (true, fn's result) | (false, reason): runs fn(profile) synchronously (no yields) on a ready
--     session; reasons data.notReady (loading or final snapshot taken), data.offline, data.readOnly, error.generic.
--     `update` is the same function.
--   requestSave(p, reason) ("autosave" | "soon" | "now" | "release"; never yields)
--   saveNowAsync(p) -> boolean (awaited "now" save);  releaseAsync(p) -> boolean;  releaseAllAsync() -> count
--   migratedFrom(p) -> the start version when this session's profile was migrated (e.g. 1), else nil (§17.10)
--   statusReason(p) -> why a session is not ready: OFFLINE "retrying" | "exhausted" (background retries used up),
--     READONLY "newer" | "lost" | "corrupt"; nil otherwise (StateService picks the banner from it)
--   addPendingReceipt(p, purchaseId) / isReceiptPending(p, purchaseId) (§3.9, §3.10; receipts land in Part 7)
--   getProfileByUserId(userId) (Studio debug);  counts() (Studio debug);  selection() -> the store real players use
--   inspect(p) (Studio debug): the session's save state (Inspect; soonAt = a scheduled "soon" save), or nil
--   debugReloadAsync(p, value?) (Studio only, memory store only): releases the session, optionally stores `value`
--     (e.g. a v1 fixture) under the player's key, and loads again through the real pipeline (DebugHooks loadProfile)
--   debugFailSaves(p, count) (Studio only, memory store only; §13.2 Part 7 "forced save failure"): the next `count`
--     writes of the player's key fail at once with a non-retried code ("105: Studio test forced save failure", logged
--     as an error like any fatal save failure), so savePending blocks spends until a later save succeeds; count 0
--     clears it (DebugHooks failSaves). Load and save behave exactly as for a real failure.
--   Signals: Loaded(player, profile, status) when a session first gets a profile (any status) and again when an
--     OFFLINE session swaps in its real profile; StatusChanged(player, dataStatus) on every status / savePending
--     change, and when an OFFLINE session's background retries run out (statusReason becomes "exhausted").
--   newCore(deps) builds an independent instance with injected clock, waits, randomness, stores and notify (tests).
-- Notify codes sent: data.waitingOtherServer (§3.8) and data.openedElsewhere (§3.9, lock lost). Reading: the status
--   texts of §3.13 (data.offlineRetrying, data.loadFailed, data.newerVersion, data.rejoin) are StateService's banners
--   (from dataStatus + statusReason) and "Progress loaded!" (data.loaded) is StateService's Notify, so DataService
--   does not send them as well (no duplicate toasts).
-- Readings: "waitingOtherServer" is sent once per load, not on every poll; a failed save of any reason sets
--   savePending (cleared by the next successful save) and, while the session is ready, schedules a "soon" retry;
--   playerRemoving defers the release by one resumption cycle so grants deferred by the higher layers' leave hooks
--   still land in the final snapshot; a player who joins while the server is closing is released as soon as the
--   load completes; dataStatus.persisted is the store's flag (memory = false) whatever the status; a stored value
--   that is not a table is left untouched and the session is READONLY with defaults ("corrupt"); a release retry
--   that finds no lock and the stored saveSeq and lastSeenAt equal to its own snapshot's is its own ghost write
--   (committed, reported failed), so it succeeds without writing again instead of reading as a lost lock; leaving
--   during an OFFLINE background retry waits for that retry, so a lock it got is given back before the release ends.

-- Services

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local DataStoreAdapter = require(Server.Data.DataStoreAdapter)
local InMemoryAdapter = require(Server.Data.InMemoryAdapter)
local KeyQueue = require(Server.Logic.KeyQueue)
local ProfileSchema = require(Server.Logic.ProfileSchema)
local SessionLock = require(Server.Logic.SessionLock)
local NetService = require(script.Parent.NetService)
local ShutdownService = require(script.Parent.ShutdownService)

-- Types

export type Status = Types.DataStatusName
export type DataStatus = Types.DataStatus
export type SaveReason = "autosave" | "soon" | "now" | "release"
export type Store = DataStoreAdapter.Store
export type NotifyFn = (player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?) -> ()

export type StoreSelection = { kind: "memory" | "datastore", name: string, probe: boolean }
export type SelectContext = { isStudio: boolean, studioMode: string, storeName: string, studioStoreName: string }

-- The Config.Data constants the core reads (overridable per core for tests).
export type DataConfig = {
	keyPrefix: string,
	autosaveInterval: number,
	autosaveBudgetFloor: number,
	autosaveBudgetRetrySeconds: number,
	saveSoonDelay: number,
	minWriteGap: number,
	lockStaleAfter: number,
	lockWaitMax: number,
	lockPoll: number,
	lockPollJitter: number,
	retryAttempts: number,
	retryCap: number,
	retryJitter: number,
	offlineRetry: number,
	offlineRetryCount: number,
	ErrorCodes: KeyQueue.ErrorCodes,
}

export type Signals = {
	Loaded: Signal.Signal<any, any, Status>,
	StatusChanged: Signal.Signal<any, DataStatus>,
}

export type CoreDeps = {
	now: () -> number, -- unix seconds (os.time)
	wait: (seconds: number) -> (), -- yields (task.wait)
	random: () -> number, -- [0, 1)
	storeFor: (userId: number) -> Store?, -- the adapter for this player (nil = unavailable -> OFFLINE)
	jobId: string?, -- game.JobId ("" in Studio -> "studio")
	newNonce: () -> string, -- 8 hex chars, once per player session
	notify: NotifyFn,
	isClosing: (() -> boolean)?,
	awaitStore: (() -> ())?, -- yields until the store choice is final (the Studio boot probe)
	isPresent: ((player: any) -> boolean)?, -- false once the player left (waitForProfileAsync)
	questExists: ((defId: string) -> boolean)?,
	config: { [string]: any }?, -- overrides for Config.Data values
	signals: Signals?,
	log: Log.Logger?,
	spawn: ((fn: () -> ()) -> ())?, -- default task.spawn
	defer: ((fn: () -> ()) -> ())?, -- default task.defer
}

type SaveJob = {
	reason: SaveReason,
	release: boolean,
	started: boolean,
	skip: boolean,
	snapshot: any,
	receipts: { string },
	ticket: KeyQueue.Ticket?,
	queueJob: KeyQueue.Job?,
}

type Session = {
	player: any,
	userId: number,
	key: string,
	queueKey: string,
	store: Store?,
	persisted: boolean,
	nonce: string,
	owner: string,
	status: Status,
	profile: any,
	saveSeq: number,
	lastWriteAt: number,
	savePending: boolean,
	cancelled: boolean,
	loadStarted: boolean,
	loadDone: boolean,
	loadFinished: Signal.Signal<>,
	releaseStarted: boolean,
	releaseJob: SaveJob?,
	finalSnapshot: boolean,
	dropped: boolean,
	droppedSignal: Signal.Signal<>,
	pendingSave: SaveJob?,
	soonAt: number?,
	nextAutosaveAt: number?,
	offlineRetryAt: number?,
	offlineRetriesLeft: number,
	retrying: boolean,
	retryFinished: Signal.Signal<>,
	waitingNotified: boolean,
	pendingReceipts: { [string]: boolean },
	migratedFrom: number?,
	readonlyReason: string?,
}

type LoadOutcome = {
	kind: "loaded" | "foreign" | "newer" | "corrupt" | "error",
	raw: any,
	stale: boolean,
	previousOwner: string?,
	class: KeyQueue.ErrorClass?,
	message: string?,
}

export type Inspect = {
	status: Status,
	owner: string,
	saveSeq: number,
	lastWriteAt: number,
	savePending: boolean,
	persisted: boolean,
	soonAt: number?,
	nextAutosaveAt: number?,
	offlineRetryAt: number?,
	offlineRetriesLeft: number,
	migratedFrom: number?,
	readonlyReason: string?,
	releasing: boolean,
}

export type Core = {
	Loaded: Signal.Signal<any, any, Status>,
	StatusChanged: Signal.Signal<any, DataStatus>,
	playerAdded: (player: any) -> (),
	playerRemoving: (player: any) -> (),
	loadAsync: (player: any) -> Status?,
	getProfile: (player: any) -> any,
	getStatus: (player: any) -> Status?,
	dataStatus: (player: any) -> DataStatus,
	isReady: (player: any) -> boolean,
	isPersisted: (player: any) -> boolean,
	isSavePending: (player: any) -> boolean,
	waitForProfileAsync: (player: any, timeout: number?) -> any,
	mutate: (player: any, fn: (profile: any) -> any) -> (boolean, any),
	requestSave: (player: any, reason: SaveReason) -> (),
	saveNowAsync: (player: any) -> boolean,
	releaseAsync: (player: any) -> boolean,
	releaseAllAsync: () -> number,
	migratedFrom: (player: any) -> number?,
	statusReason: (player: any) -> string?,
	addPendingReceipt: (player: any, purchaseId: string) -> (),
	isReceiptPending: (player: any, purchaseId: string) -> boolean,
	getProfileByUserId: (userId: number) -> any,
	debugReloadAsync: (player: any, value: any?) -> { [string]: any },
	debugFailSaves: (player: any, count: number, message: string) -> { [string]: any },
	tick: () -> (),
	inspect: (player: any) -> Inspect?,
	counts: () -> { [string]: number },
}

-- Constants

local MEMORY_STORE_NAME = "Memory"
local PROBE_KEY = "SD_StudioProbe" -- read-only probe (the transform cancels; nothing is written)
local TICK_SECONDS = 1
local WAIT_POLL_SECONDS = 0.25
local WAIT_EXTRA_SECONDS = 15 -- waitForProfileAsync default timeout = lockWaitMax + this
-- debugFailSaves: a non-retried DataStore code (§3.6), so the forced failure is immediate (the L3 runner whitelists
-- the error line that names it).
local FORCED_SAVE_FAILURE = "105: Studio test forced save failure"
local MAX_FORCED_FAILURES = 1000
local CONFIG_KEYS = {
	"keyPrefix",
	"autosaveInterval",
	"autosaveBudgetFloor",
	"autosaveBudgetRetrySeconds",
	"saveSoonDelay",
	"minWriteGap",
	"lockStaleAfter",
	"lockWaitMax",
	"lockPoll",
	"lockPollJitter",
	"retryAttempts",
	"retryCap",
	"retryJitter",
	"offlineRetry",
	"offlineRetryCount",
	"ErrorCodes",
}

-- Module table

local DataService = {}

DataService.Loaded = Signal.new() :: Signal.Signal<any, any, Status>
DataService.StatusChanged = Signal.new() :: Signal.Signal<any, DataStatus>

-- Private (module state, set in init/start)

local log = Log.new("Data")
local core: Core? = nil
local memoryStore: Store? = nil
local persistentStore: Store? = nil
local selection: StoreSelection? = nil
local storeDecided = true
local storeDecidedSignal = Signal.new() :: Signal.Signal<>

local function configWith(overrides: { [string]: any }?): DataConfig
	local merged: any = {}
	for _, key in CONFIG_KEYS do
		merged[key] = (Config.Data :: any)[key]
	end
	if overrides then
		for key, value in overrides do
			merged[key] = value
		end
	end
	return merged
end

-- A store that fails every request (a live server whose GetDataStore failed): sessions go OFFLINE and retry.
local function brokenStore(name: string, reason: string): Store
	return {
		name = name,
		kind = "datastore",
		persisted = true,
		updateAsync = function(_key: string, _transform: DataStoreAdapter.Transform): (any, DataStoreAdapter.KeyInfo?)
			error("DataStore unavailable: " .. reason, 0)
		end,
		budget = function(_kind: DataStoreAdapter.BudgetKind): number
			return 0
		end,
	}
end

-- Public: pure helpers ------------------------------------------------------------------------------------------------

-- Which store this server uses for real players (§3.1). userId <= 0 always uses memory (storeKindFor).
function DataService.selectStore(ctx: SelectContext): StoreSelection
	if ctx.isStudio then
		if ctx.studioMode == "datastore" then
			return { kind = "datastore", name = ctx.studioStoreName, probe = true }
		end
		return { kind = "memory", name = MEMORY_STORE_NAME, probe = false }
	end
	return { kind = "datastore", name = ctx.storeName, probe = false }
end

function DataService.storeKindFor(userId: number, chosen: StoreSelection): "memory" | "datastore"
	if userId <= 0 then
		return "memory"
	end
	return chosen.kind
end

-- Public: core ------------------------------------------------------------------------------------------------------

function DataService.newCore(deps: CoreDeps): Core
	local cfg = configWith(deps.config)
	local signals: Signals = deps.signals
		or {
			Loaded = Signal.new() :: Signal.Signal<any, any, Status>,
			StatusChanged = Signal.new() :: Signal.Signal<any, DataStatus>,
		}
	local logger = deps.log or log
	local runAsync: (fn: () -> ()) -> () = deps.spawn or function(fn: () -> ())
		task.spawn(fn)
	end
	local runDeferred: (fn: () -> ()) -> () = deps.defer or function(fn: () -> ())
		task.defer(fn)
	end
	local now = deps.now
	local sessions: { [any]: Session } = {}
	local closingAll = false

	local queue = KeyQueue.new({
		wait = deps.wait,
		random = deps.random,
		attempts = cfg.retryAttempts,
		cap = cfg.retryCap,
		jitter = cfg.retryJitter,
		codes = cfg.ErrorCodes,
		onRetry = function(name: string, attempt: number, class: KeyQueue.ErrorClass, message: string, delay: number)
			logger:warn(
				string.format(
					"%s failed (attempt %d, %s): %s; retrying in %.1f s",
					name,
					attempt,
					class,
					message,
					delay
				)
			)
		end,
	})

	local api = {} :: Core
	api.Loaded = signals.Loaded
	api.StatusChanged = signals.StatusChanged

	local function closing(): boolean
		return closingAll or (deps.isClosing ~= nil and deps.isClosing())
	end

	local function statusOf(session: Session): DataStatus
		return { status = session.status, persisted = session.persisted, savePending = session.savePending }
	end

	local function statusChanged(session: Session)
		if not session.dropped then
			signals.StatusChanged:fire(session.player, statusOf(session))
		end
	end

	-- §3.6: a request that failed with a class that is never retried (101-107, 403 / Studio access, 509, 511-513) is
	-- logged as an error; any other failure as a warning.
	local function logFailure(class: KeyQueue.ErrorClass?, text: string)
		if class == "fatal" or class == "studioAccess" then
			logger:error(text)
		else
			logger:warn(text)
		end
	end

	local function notify(session: Session, code: string, kind: Types.NotifyKind)
		if session.dropped then
			return
		end
		local ok, err = pcall(deps.notify :: any, session.player, code, nil, kind)
		if not ok then
			logger:warn("notify failed:", err)
		end
	end

	local function newSession(player: any): Session
		local userId = tonumber(player.UserId) or 0
		local nonce = deps.newNonce()
		local key = cfg.keyPrefix .. tostring(userId)
		return {
			player = player,
			userId = userId,
			key = key,
			queueKey = key,
			store = nil,
			persisted = false,
			nonce = nonce,
			owner = SessionLock.owner(deps.jobId, nonce),
			status = "loading",
			profile = nil,
			saveSeq = 0,
			lastWriteAt = -math.huge,
			savePending = false,
			cancelled = false,
			loadStarted = false,
			loadDone = false,
			loadFinished = Signal.new() :: Signal.Signal<>,
			releaseStarted = false,
			releaseJob = nil,
			finalSnapshot = false,
			dropped = false,
			droppedSignal = Signal.new() :: Signal.Signal<>,
			pendingSave = nil,
			soonAt = nil,
			nextAutosaveAt = nil,
			offlineRetryAt = nil,
			offlineRetriesLeft = cfg.offlineRetryCount,
			retrying = false,
			retryFinished = Signal.new() :: Signal.Signal<>,
			waitingNotified = false,
			pendingReceipts = {},
			migratedFrom = nil,
			readonlyReason = nil,
		}
	end

	local function dropSession(session: Session)
		if session.dropped then
			return
		end
		session.dropped = true
		session.cancelled = true
		if sessions[session.player] == session then
			sessions[session.player] = nil
		end
		session.droppedSignal:fire()
	end

	-- Announces a status change. With `profile`, it first swaps the session's profile in and then also fires Loaded,
	-- so every handler of either signal already sees the final status and profile.
	local function publish(session: Session, profile: any?)
		if profile ~= nil then
			session.profile = profile
		end
		statusChanged(session)
		if profile ~= nil and not session.dropped then
			signals.Loaded:fire(session.player, profile, session.status)
		end
	end

	-- Load ---------------------------------------------------------------------------------------------------------

	local function attemptLoad(session: Session): LoadOutcome
		local store = session.store
		if store == nil then
			return { kind = "error", raw = nil, stale = false, class = "retry", message = "no store" }
		end
		local userId = session.userId
		local owner = session.owner
		local captured: any = {}
		local ok, _, class, message = queue:run(session.queueKey, {
			name = "load " .. session.key,
			droppable = false,
			fn = function(): any
				table.clear(captured)
				store.updateAsync(session.key, function(value: any, info: DataStoreAdapter.KeyInfo?)
					local t = now()
					local metadata: { [string]: any } = if info then info.metadata else {}
					local lock = metadata.lock
					local decision = SessionLock.evaluate(lock, t, owner, cfg.lockStaleAfter, false)
					table.clear(captured)
					captured.decision = decision
					captured.previousOwner = if type(lock) == "table" and type(lock.o) == "string" then lock.o else nil
					if decision == "foreign" then
						return nil -- no write
					end
					if value ~= nil and type(value) ~= "table" then
						captured.corrupt = true
						return nil
					end
					if ProfileSchema.isNewer(value) then
						captured.newer = TableUtil.deepCopy(value)
						return nil
					end
					local written = if value ~= nil then value else ProfileSchema.defaults(t)
					captured.raw = TableUtil.deepCopy(written)
					local newMeta = table.clone(metadata)
					newMeta.lock = SessionLock.newLock(owner, t)
					return written, { userId }, newMeta
				end)
				return true
			end,
		})
		if not ok then
			return { kind = "error", raw = nil, stale = false, class = class :: any, message = message }
		end
		if captured.decision == nil then
			return { kind = "error", raw = nil, stale = false, class = "retry", message = "transform not called" }
		elseif captured.corrupt then
			return { kind = "corrupt", raw = nil, stale = false }
		elseif captured.newer ~= nil then
			return { kind = "newer", raw = captured.newer, stale = false }
		elseif captured.decision == "foreign" then
			return { kind = "foreign", raw = nil, stale = false, previousOwner = captured.previousOwner }
		end
		return {
			kind = "loaded",
			raw = captured.raw,
			stale = captured.decision == "stale",
			previousOwner = captured.previousOwner,
		}
	end

	-- Removes this session's lock and writes the stored value back unchanged (never our profile): a load that got
	-- the lock after its player left.
	local function unlockAsync(session: Session): boolean
		local store = session.store
		if store == nil then
			return false
		end
		local captured: any = { done = false }
		local ok = queue:run(session.queueKey, {
			name = "unlock " .. session.key,
			droppable = false,
			fn = function(): any
				captured.done = false
				store.updateAsync(session.key, function(value: any, info: DataStoreAdapter.KeyInfo?)
					local metadata: { [string]: any } = if info then info.metadata else {}
					captured.done = false
					local decision = SessionLock.evaluate(metadata.lock, now(), session.owner, cfg.lockStaleAfter, true)
					if decision ~= "mine" or value == nil then
						return nil
					end
					local newMeta = table.clone(metadata)
					newMeta.lock = nil
					captured.done = true
					return value, { session.userId }, newMeta
				end)
				return true
			end,
		})
		return ok and captured.done == true
	end

	-- OFFLINE (§3.13): defaults in memory (never saved) and, with `retries`, a background load every offlineRetry
	-- seconds. The status text is StateService's banner (statusReason "retrying" / "exhausted").
	local function goOffline(session: Session, why: string, retries: boolean, class: KeyQueue.ErrorClass?)
		local first = session.status ~= "offline"
		session.status = "offline"
		if not retries then
			session.offlineRetriesLeft = 0
		end
		session.offlineRetryAt = if session.offlineRetriesLeft > 0 then now() + cfg.offlineRetry else nil
		logFailure(class, `{session.key} OFFLINE ({why}); nothing is saved; retries left {session.offlineRetriesLeft}`)
		if first then
			publish(session, if session.profile == nil then ProfileSchema.defaults(now()) else nil)
		end
	end

	local function goReadonly(session: Session, reason: string, raw: any)
		session.status = "readonly"
		session.readonlyReason = reason
		session.soonAt = nil
		session.offlineRetryAt = nil
		local newProfile: any = nil
		if reason == "newer" then
			newProfile = ProfileSchema.load(raw, { now = now(), questExists = deps.questExists }).profile
			logger:warn(`{session.key} READONLY: stored schemaVersion {tostring(raw and raw.schemaVersion)} is newer`)
		elseif reason == "corrupt" then
			newProfile = ProfileSchema.defaults(now())
			logger:error(`{session.key} READONLY: the stored value is not a table; it is left untouched`)
		else
			logger:warn(`{session.key} READONLY: the session lock was lost`)
			notify(session, "data.openedElsewhere", "error")
		end
		publish(session, newProfile)
	end

	local function becomeReady(session: Session, outcome: LoadOutcome)
		local t = now()
		local result = ProfileSchema.load(outcome.raw, { now = t, questExists = deps.questExists })
		if #result.problems > 0 then
			logger:warn(`{session.key} fixed on load: {table.concat(result.problems, "; ")}`)
		end
		if outcome.stale then
			logger:info(`{session.key} took over a stale lock from {tostring(outcome.previousOwner)}`)
		end
		if result.migrated then
			logger:info(`{session.key} migrated from schema {result.fromVersion} to {ProfileSchema.CURRENT}`)
		end
		session.status = "ready"
		session.readonlyReason = nil
		session.offlineRetryAt = nil
		session.saveSeq = result.profile.saveSeq
		session.lastWriteAt = t -- the load wrote the lock
		session.migratedFrom = if result.migrated then result.fromVersion else nil
		session.nextAutosaveAt = t + deps.random() * cfg.autosaveInterval
		publish(session, result.profile)
	end

	local function finishLoad(session: Session)
		session.loadDone = true
		session.loadFinished:fire()
		if closing() and session.status == "ready" and not session.releaseStarted then
			runAsync(function()
				api.releaseAsync(session.player)
			end)
		end
	end

	local function runLoad(session: Session)
		if deps.awaitStore then
			deps.awaitStore()
		end
		if session.cancelled then
			finishLoad(session)
			return
		end
		local store = deps.storeFor(session.userId)
		session.store = store
		session.persisted = store ~= nil and store.persisted
		session.queueKey = (if store then store.name else "none") .. "/" .. session.key
		local deadline = now() + cfg.lockWaitMax
		while true do
			local outcome = attemptLoad(session)
			if session.cancelled then
				if outcome.kind == "loaded" then
					unlockAsync(session)
				end
				break
			end
			if outcome.kind == "loaded" then
				becomeReady(session, outcome)
				break
			elseif outcome.kind == "newer" then
				goReadonly(session, "newer", outcome.raw)
				break
			elseif outcome.kind == "corrupt" then
				goReadonly(session, "corrupt", nil)
				break
			elseif outcome.kind == "foreign" then
				if now() < deadline then
					if not session.waitingNotified then
						session.waitingNotified = true
						notify(session, "data.waitingOtherServer", "info")
					end
					deps.wait(cfg.lockPoll + (deps.random() * 2 - 1) * cfg.lockPollJitter)
					if session.cancelled then
						break
					end
					continue
				end
				goOffline(session, `lock held by {tostring(outcome.previousOwner)}`, true)
				break
			else
				goOffline(
					session,
					`{tostring(outcome.class)}: {tostring(outcome.message)}`,
					outcome.class ~= "shutdown",
					outcome.class
				)
				break
			end
		end
		finishLoad(session)
	end

	-- Runs the session's load once (a session dropped before it starts only finishes, without any request).
	local function startLoad(session: Session)
		if session.loadStarted then
			return
		end
		session.loadStarted = true
		runLoad(session)
	end

	-- One background retry of an OFFLINE session's load (§3.13). `retrying` stays true until a retry cancelled by a
	-- leave has given back the lock it got, so releaseAsync can wait for that (retryLoad below).
	local function retryLoadOnce(session: Session)
		session.offlineRetriesLeft -= 1
		local outcome = attemptLoad(session)
		if session.cancelled then
			if outcome.kind == "loaded" then
				unlockAsync(session)
			end
			return
		end
		session.retrying = false -- before any signal: statusReason reads it
		if outcome.kind == "loaded" then
			becomeReady(session, outcome) -- the real profile is swapped in; StateService says "Progress loaded!"
			return
		elseif outcome.kind == "newer" then
			goReadonly(session, "newer", outcome.raw)
			return
		elseif outcome.kind == "corrupt" then
			goReadonly(session, "corrupt", nil)
			return
		end
		if session.offlineRetriesLeft > 0 and outcome.class ~= "shutdown" then
			session.offlineRetryAt = now() + cfg.offlineRetry
		else
			session.offlineRetriesLeft = 0
			session.offlineRetryAt = nil
			logger:warn(`{session.key} stays OFFLINE: background retries used up`)
			statusChanged(session) -- statusReason is "exhausted" now (the "Please rejoin" banner)
		end
	end

	local function retryLoad(session: Session)
		local ok, err = pcall(function(): any
			retryLoadOnce(session)
			return nil
		end)
		if not ok then
			logger:error(`{session.key} background load failed:`, err)
		end
		session.retrying = false
		session.retryFinished:fire()
	end

	-- Save ---------------------------------------------------------------------------------------------------------

	local function finishSave(
		session: Session,
		job: SaveJob,
		ok: boolean,
		captured: any,
		class: KeyQueue.ErrorClass?,
		message: string?
	)
		if ok and type(captured) == "table" and captured.skipped then
			logger:debug(`{session.key} {job.reason} skipped: the session was not ready when it started`)
		elseif ok and type(captured) == "table" and captured.lost then
			if session.status == "ready" then
				goReadonly(session, "lost", nil)
			end
		elseif ok and type(captured) == "table" and captured.written then
			if captured.ghost then
				logger:info(`{session.key} {job.reason}: the write reported as failed had landed; not written again`)
			end
			session.saveSeq = job.snapshot.saveSeq
			session.lastWriteAt = now()
			if session.profile ~= nil then
				session.profile.saveSeq = job.snapshot.saveSeq
				session.profile.lastSeenAt = job.snapshot.lastSeenAt
			end
			for _, id in job.receipts do
				session.pendingReceipts[id] = nil
			end
			if session.savePending then
				session.savePending = false
				statusChanged(session)
			end
		else
			logFailure(
				class,
				`{session.key} {job.reason} save failed ({tostring(class)}: {tostring(message)}); the change stays in memory`
			)
			if not session.savePending then
				session.savePending = true
				statusChanged(session)
			end
			if not job.release and session.status == "ready" and session.soonAt == nil and not closing() then
				session.soonAt = math.max(now() + cfg.saveSoonDelay, session.lastWriteAt + cfg.minWriteGap)
			end
		end
		if job.release then
			dropSession(session)
		end
	end

	local function newSaveJob(session: Session, reason: SaveReason): SaveJob
		local job: SaveJob = {
			reason = reason,
			release = reason == "release",
			started = false,
			skip = false,
			snapshot = nil,
			receipts = {},
			ticket = nil,
			queueJob = nil,
		}
		local store = session.store
		local queueJob: KeyQueue.Job = {
			name = reason .. " " .. session.key,
			droppable = true,
			onStart = function()
				job.started = true
				if session.pendingSave == job then
					session.pendingSave = nil
				end
				if session.status ~= "ready" or session.profile == nil or store == nil then
					job.skip = true
					return
				end
				if job.release then
					session.finalSnapshot = true
				end
				session.soonAt = nil
				local snapshot = TableUtil.deepCopy(session.profile)
				snapshot.saveSeq = session.saveSeq + 1
				snapshot.lastSeenAt = now()
				job.snapshot = snapshot
				for id in session.pendingReceipts do
					table.insert(job.receipts, id)
				end
			end,
			fn = function(): any
				if job.skip or store == nil then
					return { skipped = true }
				end
				local snapshot = job.snapshot
				local release = job.release
				local captured: any = { lost = false, written = false }
				store.updateAsync(session.key, function(value: any, info: DataStoreAdapter.KeyInfo?)
					local t = now()
					local metadata: { [string]: any } = if info then info.metadata else {}
					captured.lost = false
					captured.written = false
					captured.ghost = false
					local storedSeq = if type(value) == "table" then tonumber(value.saveSeq) else nil
					if SessionLock.evaluate(metadata.lock, t, session.owner, cfg.lockStaleAfter, true) ~= "mine" then
						-- Reading: a final write that committed but reported failure (a ghost release) removed our
						-- lock itself. The stored value is then exactly our snapshot: nothing to write, not a lost lock.
						if
							release
							and type(metadata.lock) ~= "table"
							and storedSeq == snapshot.saveSeq
							and value.lastSeenAt == snapshot.lastSeenAt
						then
							captured.written = true
							captured.ghost = true
							return nil
						end
						captured.lost = true
						return nil
					end
					if storedSeq ~= nil and storedSeq > snapshot.saveSeq then
						captured.lost = true
						return nil
					end
					local newMeta = table.clone(metadata)
					newMeta.lock = if release then nil else SessionLock.newLock(session.owner, t)
					captured.written = true
					return snapshot, { session.userId }, newMeta
				end)
				return captured
			end,
			onFinish = function(ok: boolean, value: any, class: KeyQueue.ErrorClass?, message: string?)
				finishSave(session, job, ok, value, class, message)
			end,
		}
		job.queueJob = queueJob
		return job
	end

	-- The session's queued save that a new request may join: not started, and not folded away by
	-- dropPendingExceptLast (a folded job never runs, so joining it would never write).
	local function joinableSave(session: Session): SaveJob?
		local pending = session.pendingSave
		if pending == nil or pending.started then
			return nil
		end
		local ticket = pending.ticket
		if ticket ~= nil and ticket:isDropped() then
			session.pendingSave = nil
			return nil
		end
		return pending
	end

	local function startJob(session: Session, job: SaveJob)
		local queueJob = job.queueJob
		assert(queueJob ~= nil, "[SD][Data] save job without a queue job")
		job.ticket = queue:enqueue(session.queueKey, queueJob)
	end

	local function awaitJob(job: SaveJob): boolean
		local ticket = job.ticket
		if ticket == nil then
			return false
		end
		local ok, captured = ticket:await()
		return ok and type(captured) == "table" and captured.written == true
	end

	local function saveAsync(session: Session, reason: SaveReason): boolean
		if session.dropped or session.status ~= "ready" then
			return false
		end
		if session.releaseStarted then
			local releaseJob = session.releaseJob
			return if releaseJob then awaitJob(releaseJob) else false
		end
		local pending = joinableSave(session)
		local job: SaveJob
		if pending ~= nil then
			job = pending
		else
			job = newSaveJob(session, reason)
			session.pendingSave = job
			startJob(session, job)
		end
		return awaitJob(job)
	end

	local function budgetLow(session: Session): boolean
		local store = session.store
		if store == nil then
			return false
		end
		local floor = cfg.autosaveBudgetFloor
		local okWrite, write = pcall(function(): number
			return store.budget("write")
		end)
		local okRead, read = pcall(function(): number
			return store.budget("read")
		end)
		return (okWrite and type(write) == "number" and write < floor)
			or (okRead and type(read) == "number" and read < floor)
	end

	-- API ------------------------------------------------------------------------------------------------------------

	function api.loadAsync(player: any): Status?
		local session = sessions[player]
		if session == nil then
			session = newSession(player)
			sessions[player] = session
		end
		if not session.loadStarted then
			startLoad(session)
		elseif not session.loadDone then
			session.loadFinished:wait()
		end
		return if session.dropped then nil else session.status
	end

	function api.playerAdded(player: any)
		if sessions[player] ~= nil then
			return
		end
		local session = newSession(player)
		sessions[player] = session
		runAsync(function()
			startLoad(session)
		end)
	end

	function api.playerRemoving(player: any)
		runDeferred(function()
			api.releaseAsync(player)
		end)
	end

	function api.getProfile(player: any): any
		local session = sessions[player]
		return if session then session.profile else nil
	end

	function api.getStatus(player: any): Status?
		local session = sessions[player]
		return if session then session.status else nil
	end

	function api.dataStatus(player: any): DataStatus
		local session = sessions[player]
		if session == nil then
			return { status = "loading", persisted = false, savePending = false }
		end
		return statusOf(session)
	end

	function api.isReady(player: any): boolean
		local session = sessions[player]
		return session ~= nil and session.status == "ready"
	end

	function api.isPersisted(player: any): boolean
		local session = sessions[player]
		return session ~= nil and session.persisted
	end

	function api.isSavePending(player: any): boolean
		local session = sessions[player]
		return session ~= nil and session.savePending
	end

	function api.waitForProfileAsync(player: any, timeout: number?): any
		local deadline = now() + (if timeout ~= nil then timeout else cfg.lockWaitMax + WAIT_EXTRA_SECONDS)
		local seen = false
		while true do
			local session = sessions[player]
			if session then
				seen = true
				if session.status == "ready" then
					return session.profile
				elseif session.status ~= "loading" then
					return nil
				end
			elseif seen then
				return nil -- released
			end
			if deps.isPresent ~= nil and not deps.isPresent(player) then
				return nil
			end
			if now() >= deadline then
				return nil
			end
			deps.wait(WAIT_POLL_SECONDS)
		end
	end

	function api.mutate(player: any, fn: (profile: any) -> any): (boolean, any)
		local session = sessions[player]
		if session == nil or session.status == "loading" then
			return false, "data.notReady"
		elseif session.status == "offline" then
			return false, "data.offline"
		elseif session.status == "readonly" then
			return false, "data.readOnly"
		elseif session.finalSnapshot then
			return false, "data.notReady"
		end
		local ok, result = pcall(fn, session.profile)
		if not ok then
			logger:error(`mutate failed for {session.key}:`, result)
			return false, "error.generic"
		end
		return true, result
	end

	function api.requestSave(player: any, reason: SaveReason)
		local session = sessions[player]
		if session == nil or session.status ~= "ready" or session.dropped then
			return
		end
		if reason == "soon" then
			if session.soonAt == nil and not session.releaseStarted then
				session.soonAt = math.max(now() + cfg.saveSoonDelay, session.lastWriteAt + cfg.minWriteGap)
			end
		elseif reason == "release" then
			runAsync(function()
				api.releaseAsync(player)
			end)
		else
			runAsync(function()
				saveAsync(session, reason)
			end)
		end
	end

	function api.saveNowAsync(player: any): boolean
		local session = sessions[player]
		if session == nil then
			return false
		end
		return saveAsync(session, "now")
	end

	function api.releaseAsync(player: any): boolean
		local session = sessions[player]
		if session == nil then
			return true
		end
		if session.releaseStarted then
			local releaseJob = session.releaseJob
			if releaseJob then
				return awaitJob(releaseJob)
			end
			if not session.dropped then
				session.droppedSignal:wait()
			end
			return true
		end
		session.releaseStarted = true
		if session.status == "loading" then
			-- Cancel the load; it unlocks the key if it already got the lock. Never saved.
			session.cancelled = true
			if session.loadStarted and not session.loadDone then
				session.loadFinished:wait()
			end
			dropSession(session)
			return true
		elseif session.status ~= "ready" then
			-- OFFLINE / READONLY: never saved. A background retry still running is cancelled and waited for, so a
			-- lock it got is given back before the release ends.
			session.cancelled = true
			if session.retrying then
				session.retryFinished:wait()
			end
			dropSession(session)
			return true
		end
		local pending = joinableSave(session)
		local job: SaveJob
		if pending ~= nil then
			job = pending
			job.release = true -- the queued save becomes the final write (its snapshot is taken when it starts)
			job.reason = "release"
		else
			job = newSaveJob(session, "release")
			startJob(session, job)
		end
		session.pendingSave = nil
		session.releaseJob = job
		return awaitJob(job)
	end

	function api.releaseAllAsync(): number
		closingAll = true
		local players = {}
		for player in sessions do
			table.insert(players, player)
		end
		local remaining = #players
		if remaining == 0 then
			return 0
		end
		local allDone = Signal.new() :: Signal.Signal<>
		for _, player in players do
			runAsync(function()
				local ok, err = pcall(api.releaseAsync, player)
				if not ok then
					logger:error("release failed:", err)
				end
				remaining -= 1
				if remaining == 0 then
					allDone:fire()
				end
			end)
		end
		local dropped = queue:dropPendingExceptLast()
		if dropped > 0 then
			logger:info(`dropped {dropped} redundant save jobs while closing`)
		end
		if remaining > 0 then
			allDone:wait()
		end
		return #players
	end

	function api.migratedFrom(player: any): number?
		local session = sessions[player]
		return if session then session.migratedFrom else nil
	end

	function api.statusReason(player: any): string?
		local session = sessions[player]
		if session == nil then
			return nil
		elseif session.status == "offline" then
			local exhausted = session.offlineRetriesLeft <= 0 and not session.retrying
			return if exhausted then "exhausted" else "retrying"
		elseif session.status == "readonly" then
			return session.readonlyReason
		end
		return nil
	end

	function api.addPendingReceipt(player: any, purchaseId: string)
		local session = sessions[player]
		if session then
			session.pendingReceipts[purchaseId] = true
		end
	end

	function api.isReceiptPending(player: any, purchaseId: string): boolean
		local session = sessions[player]
		return session ~= nil and session.pendingReceipts[purchaseId] == true
	end

	function api.getProfileByUserId(userId: number): any
		for _, session in sessions do
			if session.userId == userId then
				return session.profile
			end
		end
		return nil
	end

	-- Studio debug (the caller gates it): only for a store that is not persisted (memory). Releases the session (its
	-- final write goes to memory), stores `value` under the player's key when given (no lock), then loads again
	-- through the real pipeline, so a v1 fixture is migrated exactly like a real one. Yields.
	function api.debugReloadAsync(player: any, value: any?): { [string]: any }
		local userId = tonumber(player.UserId) or 0
		local store = deps.storeFor(userId)
		if store == nil or store.persisted then
			return { ok = false, error = "only a memory store can be reloaded" }
		end
		if value ~= nil and type(value) ~= "table" then
			return { ok = false, error = "value must be a table or nil" }
		end
		if sessions[player] ~= nil then
			api.releaseAsync(player)
		end
		if value ~= nil then
			local key = cfg.keyPrefix .. tostring(userId)
			local stored = TableUtil.deepCopy(value)
			local ok, _, class, message = queue:run(store.name .. "/" .. key, {
				name = "debug store " .. key,
				droppable = false,
				fn = function(): any
					store.updateAsync(key, function(_old: any, info: DataStoreAdapter.KeyInfo?)
						local metadata: { [string]: any } = if info then table.clone(info.metadata) else {}
						metadata.lock = nil
						return stored, { userId }, metadata
					end)
					return true
				end,
			})
			if not ok then
				return { ok = false, error = `could not store the value ({tostring(class)}: {tostring(message)})` }
			end
		end
		local status = api.loadAsync(player)
		return { ok = status == "ready", status = status, migratedFrom = api.migratedFrom(player) }
	end

	-- Studio debug (the caller gates it): only for a store that is not persisted and can fail on purpose (the memory
	-- store's failNext). The next `count` requests on the player's key throw `message` (count 0 clears). Never yields.
	function api.debugFailSaves(player: any, count: number, message: string): { [string]: any }
		local session = sessions[player]
		local userId = tonumber(player.UserId) or 0
		local store: any = if session ~= nil and session.store ~= nil then session.store else deps.storeFor(userId)
		if store == nil or store.persisted or type(store.failNext) ~= "function" then
			return { ok = false, error = "only a memory store can fail saves on purpose" }
		end
		store.failNext(cfg.keyPrefix .. tostring(userId), count, message)
		return { ok = true, count = count }
	end

	-- Runs due "soon" saves, autosaves and OFFLINE background retries. Called every second by start(); tests call it
	-- after moving their fake clock.
	function api.tick()
		local t = now()
		if closing() then
			return
		end
		for _, session in table.clone(sessions) do
			if session.dropped or session.releaseStarted then
				continue
			end
			if session.status == "ready" then
				local soonAt = session.soonAt
				if soonAt ~= nil and t >= soonAt then
					session.soonAt = nil
					runAsync(function()
						saveAsync(session, "soon")
					end)
				end
				local autosaveAt = session.nextAutosaveAt
				if autosaveAt ~= nil and t >= autosaveAt and session.status == "ready" then
					if budgetLow(session) then
						session.nextAutosaveAt = t + cfg.autosaveBudgetRetrySeconds
					else
						session.nextAutosaveAt = t + cfg.autosaveInterval
						runAsync(function()
							saveAsync(session, "autosave")
						end)
					end
				end
			elseif session.status == "offline" then
				local retryAt = session.offlineRetryAt
				if retryAt ~= nil and t >= retryAt and not session.retrying and not session.cancelled then
					session.retrying = true
					session.offlineRetryAt = nil
					runAsync(function()
						retryLoad(session)
					end)
				end
			end
		end
	end

	function api.inspect(player: any): Inspect?
		local session = sessions[player]
		if session == nil then
			return nil
		end
		return {
			status = session.status,
			owner = session.owner,
			saveSeq = session.saveSeq,
			lastWriteAt = session.lastWriteAt,
			savePending = session.savePending,
			persisted = session.persisted,
			soonAt = session.soonAt,
			nextAutosaveAt = session.nextAutosaveAt,
			offlineRetryAt = session.offlineRetryAt,
			offlineRetriesLeft = session.offlineRetriesLeft,
			migratedFrom = session.migratedFrom,
			readonlyReason = session.readonlyReason,
			releasing = session.releaseStarted,
		}
	end

	function api.counts(): { [string]: number }
		local result = { loading = 0, ready = 0, offline = 0, readonly = 0, savePending = 0 }
		for _, session in sessions do
			result[session.status] += 1
			if session.savePending then
				result.savePending += 1
			end
		end
		result.queuedJobs = queue:pendingCount()
		return result
	end

	return api
end

-- Public: module API (delegates to the server's core; safe before init) ----------------------------------------------

function DataService.getProfile(player: Player): any
	return if core then core.getProfile(player) else nil
end

function DataService.getStatus(player: Player): Status?
	return if core then core.getStatus(player) else nil
end

function DataService.dataStatus(player: Player): DataStatus
	if core then
		return core.dataStatus(player)
	end
	return { status = "loading", persisted = false, savePending = false }
end

function DataService.isReady(player: Player): boolean
	return core ~= nil and core.isReady(player)
end

function DataService.isPersisted(player: Player): boolean
	return core ~= nil and core.isPersisted(player)
end

function DataService.isSavePending(player: Player): boolean
	return core ~= nil and core.isSavePending(player)
end

function DataService.waitForProfileAsync(player: Player, timeout: number?): any
	return if core then core.waitForProfileAsync(player, timeout) else nil
end

function DataService.mutate(player: Player, fn: (profile: any) -> any): (boolean, any)
	if core == nil then
		return false, "data.notReady"
	end
	return core.mutate(player, fn)
end

DataService.update = DataService.mutate

function DataService.requestSave(player: Player, reason: SaveReason)
	if core then
		core.requestSave(player, reason)
	end
end

function DataService.saveNowAsync(player: Player): boolean
	return core ~= nil and core.saveNowAsync(player)
end

function DataService.releaseAsync(player: Player): boolean
	return core == nil or core.releaseAsync(player)
end

function DataService.releaseAllAsync(): number
	return if core then core.releaseAllAsync() else 0
end

function DataService.migratedFrom(player: Player): number?
	return if core then core.migratedFrom(player) else nil
end

function DataService.statusReason(player: Player): string?
	return if core then core.statusReason(player) else nil
end

function DataService.addPendingReceipt(player: Player, purchaseId: string)
	if core then
		core.addPendingReceipt(player, purchaseId)
	end
end

function DataService.isReceiptPending(player: Player, purchaseId: string): boolean
	return core ~= nil and core.isReceiptPending(player, purchaseId)
end

function DataService.getProfileByUserId(userId: number): any
	return if core then core.getProfileByUserId(userId) else nil
end

function DataService.counts(): { [string]: number }
	return if core then core.counts() else {}
end

-- Studio debug (DebugHooks "profile"): the player's session save state (Inspect: saveSeq, lastWriteAt, savePending,
-- soonAt = when a scheduled "soon" save runs, ...), or nil without a session. Read only.
function DataService.inspect(player: Player): Inspect?
	return if core then core.inspect(player) else nil
end

-- Studio only (DebugHooks "loadProfile"): reloads the player's profile through the real load pipeline, from the
-- memory store, optionally after storing `value` (for example a v1 fixture) under the player's key. Yields.
function DataService.debugReloadAsync(player: Player, value: any?): { [string]: any }
	if not RunService:IsStudio() then
		return { ok = false, error = "Studio only" }
	end
	if core == nil then
		return { ok = false, error = "DataService is not initialised" }
	end
	return core.debugReloadAsync(player, value)
end

-- Studio only (RunService:IsStudio() and Config.Debug.debugHooks; DebugHooks "failSaves"): the next `count` writes of
-- the player's key in the memory store fail at once (a non-retried code), so savePending blocks spends; 0 clears.
function DataService.debugFailSaves(player: Player, count: number): { [string]: any }
	if not (RunService:IsStudio() and Config.Debug.debugHooks) then
		return { ok = false, error = "Studio only" }
	end
	if core == nil then
		return { ok = false, error = "DataService is not initialised" }
	end
	if
		type(count) ~= "number"
		or count ~= count
		or count < 0
		or count > MAX_FORCED_FAILURES
		or math.floor(count) ~= count
	then
		return { ok = false, error = `count must be a whole number from 0 to {MAX_FORCED_FAILURES}` }
	end
	return core.debugFailSaves(player, count, FORCED_SAVE_FAILURE)
end

-- The store this server picked for real players (nil before init).
function DataService.selection(): StoreSelection?
	return selection
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

local function questExistsFn(): ((defId: string) -> boolean)?
	local module = Shared:FindFirstChild("QuestDefs")
	if module == nil or not module:IsA("ModuleScript") then
		return nil -- Part 7: until QuestDefs exists every stored quest is kept
	end
	local requireAny = require :: (ModuleScript) -> any
	local ok, QuestDefs = pcall(requireAny, module)
	if not ok or type(QuestDefs) ~= "table" or type(QuestDefs.get) ~= "function" then
		log:warn("QuestDefs could not be used to check stored quests; every quest is kept")
		return nil
	end
	return function(defId: string): boolean
		return QuestDefs.get(defId) ~= nil
	end
end

local function decideStore()
	storeDecided = true
	storeDecidedSignal:fire()
end

function DataService.init()
	local isStudio = RunService:IsStudio()
	local chosen = DataService.selectStore({
		isStudio = isStudio,
		studioMode = Config.Data.studioMode,
		storeName = Config.Data.storeName,
		studioStoreName = Config.Data.studioStoreName,
	})
	if chosen.kind == "datastore" then
		DataStoreAdapter.assertSafeName(chosen.name, isStudio) -- §3.1 boot guard
		storeDecided = false -- opened (and in Studio probed) in start()
	end
	selection = chosen
	memoryStore = InMemoryAdapter.new(MEMORY_STORE_NAME)

	core = DataService.newCore({
		now = os.time,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		random = math.random,
		storeFor = function(userId: number): Store?
			if userId <= 0 or persistentStore == nil then
				return memoryStore
			end
			return persistentStore
		end,
		jobId = game.JobId,
		newNonce = function(): string
			return SessionLock.nonceFrom(HttpService:GenerateGUID(false))
		end,
		notify = function(player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
			NetService.notify(player, code, args, kind)
		end,
		isClosing = ShutdownService.isClosing,
		awaitStore = function()
			if not storeDecided then
				storeDecidedSignal:wait()
			end
		end,
		isPresent = function(player: any): boolean
			return typeof(player) == "Instance" and player.Parent ~= nil
		end,
		questExists = questExistsFn(),
		signals = { Loaded = DataService.Loaded, StatusChanged = DataService.StatusChanged },
		log = log,
	})

	ShutdownService.addCloseTask("DataService.releaseAll", function()
		DataService.releaseAllAsync()
	end)
	log:info(`store: {chosen.kind} {chosen.name}`)
end

-- Opens the DataStore (and in Studio probes it, read-only), then runs the save/retry tick every second.
function DataService.start()
	local chosen = selection
	if chosen ~= nil and chosen.kind == "datastore" and not storeDecided then
		local isStudio = RunService:IsStudio()
		local ok, result = pcall(DataStoreAdapter.open, chosen.name)
		if not ok then
			if isStudio then
				log:warn(`could not open {chosen.name} ({tostring(result)}); using memory: progress is not saved`)
			else
				log:error(`could not open {chosen.name}:`, result)
				persistentStore = brokenStore(chosen.name, tostring(result))
			end
		else
			persistentStore = result
			if chosen.probe then
				local probeOk, probeErr = pcall(function(): any
					result.updateAsync(PROBE_KEY, function(_value: any, _info: DataStoreAdapter.KeyInfo?): any
						return nil -- read only: nothing is written
					end)
					return nil
				end)
				if not probeOk then
					local class, code = KeyQueue.classify(tostring(probeErr), Config.Data.ErrorCodes)
					if class == "studioAccess" or code == 403 then
						persistentStore = nil
						log:warn("Studio has no API access; using memory: progress is not saved")
					else
						log:warn("store probe failed (keeping the DataStore):", probeErr)
					end
				end
			end
		end
		if persistentStore == nil then
			-- Studio fell back to memory (§3.1): report the store that is really used
			selection = { kind = "memory", name = MEMORY_STORE_NAME, probe = false }
		end
		decideStore()
	end
	while true do
		task.wait(TICK_SECONDS)
		local current = core
		if current then
			local ok, err = pcall(current.tick :: any)
			if not ok then
				log:error("tick failed:", err)
			end
		end
	end
end

function DataService.playerAdded(player: Player)
	if core then
		core.playerAdded(player)
	end
end

function DataService.playerRemoving(player: Player)
	if core then
		core.playerRemoving(player)
	end
end

return DataService
