--!strict
-- StateController (client only). DESIGN §2.4, §2.6, §2.8, §5.4, §11.3, §11.6, §17.10. The client's local copy of what
-- the server sends, with Signals. Screens never poll it: they connect to its signals and update (§11.1).
--
-- * Profile store (Snapshot + versioned StateDelta, §2.7/§2.8): one monotonic `v`; a delta older than (or equal to)
--   the stored v is ignored; `full` replaces every field. Fields: coins, owned, equipped, stats, squeezeLimit, quests,
--   daily, settings, onboarding, policy, dataStatus, monetization, unseenReveals, practice, grip (§17.10); unknown
--   fields are kept as sent. Each known field is checked before it is stored (normalizeField): a value of the wrong
--   shape is dropped (a partial delta keeps the old value), coins become a whole number >= 0, settings are clamped
--   with Config.Data defaults filled in, dataStatus gets its booleans (and keeps `banner`, the server's Strings key of
--   the status banner, only when that key has a text). A field counts as changed only when its value
--   differs by value (deep compare), so screens are not refreshed by an identical resend; an equal value keeps the
--   old table.
--   Signals: Changed(field, value, old) and changed(field) -> (value, old) for every changed field;
--   ServerChanged(field, value, old) for every server change, even under a local override (below); Loaded once the
--   first full Snapshot is in. isApplyingFull() is true while the signals of a full Snapshot run (a replaced value,
--   e.g. a profile recovered after an OFFLINE start, is not a gain).
-- * Local overrides (reading of §11.6 "Settings ... applied instantly on the client"): setOverride(field, value)
--   makes get(field) return `value` until setOverride(field, nil); the server's own value stays readable through
--   serverValue(field). Used by SettingsController while a SetSettings save is pending, so every reader (sound
--   volumes, camera shake) follows a slider at once.
-- * New squishies (§11.6 "NEW (until first selected, session-local)"): the owned ids of the first full Snapshot are
--   the baseline; an id that appears later in this session is new until markOwnedSeen(id). A later full Snapshot
--   (data recovery) re-baselines without marking anything new. NewOwnedChanged(count). The tracker follows the owned
--   set as shown (below), so a squishy whose reveal is held is not "new" yet.
-- * Reveal holds (reading of §9.11 "no fake-outs"; Part 7 review fix): a box result reaches the client in a StateDelta
--   (Coins after the spend AND the duplicate refund, owned with the new squishy, a new unseenReveals entry) before its
--   reveal plays, often before the BoxOpen reply (the server's "now" save yields first). So every unseenReveals entry
--   that first appears in a partial state (not a full one) is held: get / coins() / owned() / changed(field) show
--   Coins without its refund and owned without its new squishy (the spend still shows at once) until
--   releaseReveal(requestId) (BoxController: the reveal reached its result, or closed as seen), until the entry is no
--   longer unseen, or after Config.UI.Boxes.revealHoldMaxSeconds (a reveal that never plays). A full state clears
--   every hold (a new baseline, like a rejoin). serverValue(field) and ServerChanged always carry the server's value.
--   The pure parts: hideHeldReveals, revealHoldStep.
-- * Typed reads with safe defaults: coins(), owned(), owns(id), equipped(), settings(), dataStatus(),
--   isProfileReady().
-- * loadSnapshotAsync() (§2.6): RequestSnapshot, one call in flight at a time, repeated every
--   Config.Net.Client.snapshotRetrySeconds while the server answers {status = "loading"}, for up to
--   snapshotWaitSeconds; a full StateDelta resolves it earlier. Reading: the boot waits only while the server is
--   actively answering "loading". An error Result, or no reply within one retry interval (a server without a profile
--   service, as in Part 4), lets the boot go on at once; a late Snapshot is still applied when it arrives.
-- * Queue (QueueStatus, §2.8): the owner's view {state, position, joinedAt, messageKey, counts} and the count-only
--   board broadcast (a payload without `state`) kept apart: queue() / QueueChanged, queueCounts() / QueueCountsChanged.
-- * Duel (DuelState = a full view on every phase change; ThrowImpact lives, and feature 1's CatchEvent "burst" lives;
--   UltimateCharge; DuelResult): duel() /
--   DuelChanged, lastResult() / DuelResultReceived. The view ends when the server clears the Player attribute
--   SD_DuelPhase (back in the lobby, §2.9): at once after Result/Returning/Cancelled/Void, otherwise once the view is
--   older than STALE_CLEAR_SECONDS (an attribute change racing a brand-new match's first DuelState never clears it).
--   A queue left on "Matched" when the duel ends becomes Idle locally.
-- * Lobby lock (§5.4, §11.1): from Matched through Returning, isLobbyLocked() is true (LobbyLockChanged): menus,
--   equip, Inspect, boxes and shop refuse to open.
-- The reducers (reduceProfile, normalizeField, trackNewOwned, reduceQueue, reduceDuel, lobbyLocked, deepEqual) are
-- pure and unit-tested in Edit mode.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local NetController = require(script.Parent.NetController)

-- Types

export type ProfileStore = {
	v: number,
	loaded: boolean,
	fields: { [string]: any },
}

export type QueueCounts = {
	searching: number,
	duelsInProgress: number,
	arenasFree: number,
}

export type QueueView = {
	state: Types.QueueState,
	position: number?,
	joinedAt: number?,
	messageKey: string?,
	searching: number,
	duelsInProgress: number,
	arenasFree: number,
}

export type Participant = Types.DuelParticipantView & { invulnUntil: number? }

export type DuelView = {
	matchId: string,
	phase: Types.DuelPhase,
	phaseEndsAt: number,
	you: Participant,
	opponent: Participant,
	arena: Types.DuelArenaView,
	rules: { [string]: any },
	charges: { [number]: number }, -- ultimate charge by userId (UltimateCharge)
	positioned: boolean, -- the match reached Positioning or later (the player was moved to the arena)
	receivedAt: number, -- os.clock() of the last DuelState
}

export type DuelEvent =
	{ kind: "state", state: any, now: number }
	| { kind: "impact", impact: any }
	| { kind: "charge", charge: any }
	| { kind: "cleared", now: number }

export type QueueKind = "owner" | "counts" | "invalid"

-- The new-squishy tracker (trackNewOwned): `baseline` = ids known before (nil until the first owned set arrives),
-- `fresh` = ids gained this session and not seen yet.
export type OwnedTracker = {
	baseline: { [string]: boolean }?,
	fresh: { [string]: boolean },
}

-- Constants

local QUEUE_STATES: { [string]: boolean } = { Idle = true, Searching = true, Matched = true }
-- Phase order; a DuelState never moves a match backwards (§5.4). Cancelled/Void can follow any phase.
local PHASE_ORDER: { [string]: number } = {
	Preparing = 1,
	Positioning = 2,
	Countdown = 3,
	Active = 4,
	SuddenDeath = 5,
	Result = 6,
	Returning = 7,
	Cancelled = 8,
	Void = 8,
}
local END_PHASES: { [string]: boolean } = { Result = true, Returning = true, Cancelled = true, Void = true }
local OUTCOMES: { [string]: boolean } = { win = true, loss = true, draw = true, cancelled = true, void = true }
-- reading (not in DESIGN): a cleared SD_DuelPhase only ends a view older than this, so an attribute change that races
-- a new match's first DuelState never wipes it (remote events and attribute replication are not ordered together).
local STALE_CLEAR_SECONDS = 1
local ATTR_DUEL_PHASE = "SD_DuelPhase"
local NET_CLIENT = Config.Net.Client
local ABILITIES = Config.Abilities
local DATA = Config.Data
local DATA_STATUSES: { [string]: boolean } = { loading = true, ready = true, offline = true, readonly = true }
local POLICY_STATES: { [string]: boolean } = { checking = true, eligible = true, restricted = true, unknown = true }
-- Known StateDelta fields (§2.8, §17.10) whose value must be a table; the others have their own check below.
local TABLE_FIELDS: { [string]: boolean } = {
	owned = true,
	stats = true,
	squeezeLimit = true,
	quests = true,
	daily = true,
	onboarding = true,
	monetization = true,
	unseenReveals = true,
	practice = true,
	grip = true,
}
local MAX_COMPARE_DEPTH = 16
-- Reveal holds (see the header): the fields shown without the held results, in fire order (sorted).
local FIELD_COINS = "coins"
local FIELD_OWNED = "owned"
local FIELD_UNSEEN = "unseenReveals"
local HELD_FIELDS: { string } = { FIELD_COINS, FIELD_OWNED }
local HELD_FIELD_SET: { [string]: boolean } = { [FIELD_COINS] = true, [FIELD_OWNED] = true }
local REVEAL_HOLD_MAX_SECONDS = Config.UI.Boxes.revealHoldMaxSeconds

-- Module table

local StateController = {}

-- Profile signals.
StateController.Changed = Signal.new() :: Signal.Signal<string, any, any>
StateController.ServerChanged = Signal.new() :: Signal.Signal<string, any, any>
StateController.Loaded = Signal.new() :: Signal.Signal<>
StateController.NewOwnedChanged = Signal.new() :: Signal.Signal<number>
-- Queue and duel signals: (new, old).
StateController.QueueChanged = Signal.new() :: Signal.Signal<QueueView, QueueView>
StateController.QueueCountsChanged = Signal.new() :: Signal.Signal<QueueCounts>
StateController.DuelChanged = Signal.new() :: Signal.Signal<DuelView?, DuelView?>
StateController.DuelResultReceived = Signal.new() :: Signal.Signal<Types.DuelResultPayload>
StateController.LobbyLockChanged = Signal.new() :: Signal.Signal<boolean>

-- Private

local log = Log.new("State")
local cleanup: Cleanup.Cleanup? = nil
local fieldSignals: { [string]: Signal.Signal<any, any> } = {}

local function emptyCounts(): QueueCounts
	return { searching = 0, duelsInProgress = 0, arenasFree = 0 }
end

local function idleQueue(counts: QueueCounts): QueueView
	return {
		state = "Idle",
		searching = counts.searching,
		duelsInProgress = counts.duelsInProgress,
		arenasFree = counts.arenasFree,
	}
end

local profile: ProfileStore = { v = 0, loaded = false, fields = {} }
local overrides: { [string]: any } = {}
local heldReveals: { [string]: thread } = {} -- held requestId -> its safety release (task.delay)
local heldView: { [string]: any }? = nil -- coins / owned as shown while something is held; nil = nothing held
local ownedTracker: OwnedTracker = { baseline = nil, fresh = {} }
local counts: QueueCounts = emptyCounts()
local queueView: QueueView = idleQueue(counts)
local duelView: DuelView? = nil
local lastResult: Types.DuelResultPayload? = nil
local locked = false
local endedMatches: { [string]: boolean } = {} -- match ids whose view ended (late messages are ignored)
local applyingFull = false -- true while the change signals of a full Snapshot / StateDelta run

local function isCount(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function countOr(value: unknown, fallback: number): number
	return if isCount(value) then math.floor(value :: number) else fallback
end

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function volume(value: unknown, fallback: number): number
	if not finite(value) then
		return fallback
	end
	return math.clamp(math.floor((value :: number) + 0.5), DATA.settingsMin, DATA.settingsMax)
end

local function countKeys(set: { [string]: boolean }): number
	local n = 0
	for _ in set do
		n += 1
	end
	return n
end

local function participantFrom(raw: unknown): Participant?
	if type(raw) ~= "table" then
		return nil
	end
	local t = raw :: any
	if not finite(t.userId) or (t.side ~= "A" and t.side ~= "B") then
		return nil
	end
	return {
		userId = t.userId,
		displayName = if type(t.displayName) == "string" then t.displayName else "",
		squishyId = if type(t.squishyId) == "string" then t.squishyId else Catalog.starterId(),
		side = t.side :: Types.Side,
		lives = if finite(t.lives) then t.lives else 0,
		ultReady = t.ultReady == true,
		isTestDummy = t.isTestDummy == true,
		invulnUntil = nil,
	}
end

local function chargeMaxFor(squishyId: string): number?
	local def = Catalog.get(squishyId)
	local ultimateId = if def then def.ultimateId else nil
	local ability = if ultimateId then ABILITIES[ultimateId] else nil
	return if ability then ability.chargeMax else nil
end

local function copyView(view: DuelView): DuelView
	local copy = table.clone(view)
	copy.you = table.clone(view.you)
	copy.opponent = table.clone(view.opponent)
	copy.charges = table.clone(view.charges)
	return copy
end

local function setLock()
	local now = StateController.lobbyLocked(queueView, duelView)
	if now ~= locked then
		locked = now
		StateController.LobbyLockChanged:fire(now)
	end
end

local function setQueue(newView: QueueView)
	local old = queueView
	queueView = newView
	StateController.QueueChanged:fire(newView, old)
	setLock()
end

local function setDuel(newView: DuelView?)
	local old = duelView
	if newView == old then
		return
	end
	duelView = newView
	StateController.DuelChanged:fire(newView, old)
	if newView == nil and queueView.state == "Matched" then
		setQueue(idleQueue(counts)) -- back in the lobby: Matched is over even if no Idle status came
	end
	setLock()
end

local function effective(field: string): any
	local override = overrides[field]
	if override ~= nil then
		return override
	end
	local view = heldView
	if view ~= nil and HELD_FIELD_SET[field] then
		return view[field] -- a held reveal's result is hidden (see the header)
	end
	return profile.fields[field]
end

local function fireChanged(field: string, value: any, previous: any)
	StateController.Changed:fire(field, value, previous)
	local signal = fieldSignals[field]
	if signal then
		signal:fire(value, previous)
	end
end

-- The held fields as shown now (to compare after a change).
local function shownHeldFields(): { [string]: any }
	return { [FIELD_COINS] = effective(FIELD_COINS), [FIELD_OWNED] = effective(FIELD_OWNED) }
end

-- Rebuilds heldView from the profile and the held requestIds.
local function recomputeHeld()
	if next(heldReveals) == nil then
		heldView = nil
		return
	end
	local fields = profile.fields
	local coins, owned =
		StateController.hideHeldReveals(fields[FIELD_COINS], fields[FIELD_OWNED], fields[FIELD_UNSEEN], heldReveals)
	heldView = { [FIELD_COINS] = coins, [FIELD_OWNED] = owned }
end

-- The new-squishy tracker step on the owned set as shown (held squishies are not new yet); fires NewOwnedChanged.
local function trackOwned(ownedChanged: boolean, full: boolean)
	local before = countKeys(ownedTracker.fresh)
	if ownedChanged or full or ownedTracker.baseline == nil then
		ownedTracker = StateController.trackNewOwned(ownedTracker, effective(FIELD_OWNED), full)
	end
	local after = countKeys(ownedTracker.fresh)
	if after ~= before or (ownedChanged and after > 0) then
		StateController.NewOwnedChanged:fire(after)
	end
end

-- Fires changed(field) for each held field whose shown value moved since `before`. Returns true when owned moved.
local function fireHeldChanges(before: { [string]: any }): boolean
	local ownedMoved = false
	for _, field in HELD_FIELDS do
		if overrides[field] == nil then
			local after = effective(field)
			if not StateController.deepEqual(before[field], after) then
				fireChanged(field, after, before[field])
				ownedMoved = ownedMoved or field == FIELD_OWNED
			end
		end
	end
	return ownedMoved
end

local function stopHold(requestId: string)
	local timer = heldReveals[requestId]
	heldReveals[requestId] = nil
	-- Never cancel the running timer itself (task.cancel throws "cannot cancel thread").
	if timer ~= nil and coroutine.status(timer) == "suspended" then
		task.cancel(timer)
	end
end

local function startHold(requestId: string)
	if heldReveals[requestId] ~= nil then
		return
	end
	heldReveals[requestId] = task.delay(REVEAL_HOLD_MAX_SECONDS, function()
		if StateController.releaseReveal(requestId) then
			log:info(`reveal {requestId} was not played within {REVEAL_HOLD_MAX_SECONDS} s; its result is shown`)
		end
	end)
end

local function applyProfile(v: number, fields: { [string]: any }, full: boolean?)
	local wasLoaded = profile.loaded
	local old = profile.fields
	local newStore, changed = StateController.reduceProfile(profile, v, fields, full)
	if newStore == profile then
		return
	end
	local shownBefore = shownHeldFields()
	profile = newStore
	-- Reveal holds (see the header): a new unseen result of a partial state is held; one no longer unseen is let go.
	local start, stop = StateController.revealHoldStep(
		heldReveals,
		old[FIELD_UNSEEN],
		newStore.fields[FIELD_UNSEEN],
		full == true,
		wasLoaded
	)
	for _, id in stop do
		stopHold(id)
	end
	for _, id in start do
		startHold(id)
	end
	recomputeHeld()
	-- coins / owned fire when their SHOWN value moved (a hold can change it with no server change, or hide one).
	local toFire = table.clone(changed)
	for _, field in HELD_FIELDS do
		if table.find(toFire, field) == nil and not StateController.deepEqual(shownBefore[field], effective(field)) then
			table.insert(toFire, field)
		end
	end
	table.sort(toFire)
	-- Handlers start synchronously (Util/Signal), so they can ask isApplyingFull() before their first yield.
	applyingFull = full == true
	local ownedMoved = false
	for _, field in toFire do
		local value, previous = newStore.fields[field], old[field]
		if table.find(changed, field) ~= nil then
			StateController.ServerChanged:fire(field, value, previous)
		end
		if overrides[field] == nil then
			if HELD_FIELD_SET[field] then
				local shown = effective(field)
				if not StateController.deepEqual(shownBefore[field], shown) then
					fireChanged(field, shown, shownBefore[field])
					ownedMoved = ownedMoved or field == FIELD_OWNED
				end
			else
				fireChanged(field, value, previous)
			end
		end
	end
	applyingFull = false
	trackOwned(ownedMoved, full == true)
	if newStore.loaded and not wasLoaded then
		StateController.Loaded:fire()
	end
end

local function onDuelEvent(event: DuelEvent)
	if event.kind == "state" and type(event.state) == "table" and endedMatches[(event.state :: any).matchId] then
		return -- a late DuelState of a match this client already left (e.g. Returning after SD_DuelPhase cleared)
	end
	local ok, result = pcall(StateController.reduceDuel, duelView, event)
	if not ok then
		log:error("duel state update failed:", result)
		return
	end
	local old = duelView
	if result == nil and old ~= nil then
		endedMatches[old.matchId] = true
	end
	setDuel(result)
end

-- Public: pure reducers ----------------------------------------------------------------------------------------------

-- Deep value equality of plain data (tables compared key by key, up to MAX_COMPARE_DEPTH levels).
function StateController.deepEqual(a: any, b: any): boolean
	local function equal(x: any, y: any, depth: number): boolean
		if x == y then
			return true
		end
		if type(x) ~= "table" or type(y) ~= "table" or depth > MAX_COMPARE_DEPTH then
			return false
		end
		for key, value in x do
			if not equal(value, y[key], depth + 1) then
				return false
			end
		end
		for key in y do
			if x[key] == nil then
				return false
			end
		end
		return true
	end
	return equal(a, b, 0)
end

-- Checks one state field before it is stored. Returns (true, value to store) or (false) for a value of the wrong
-- shape. Unknown fields are accepted as sent (a newer server may send more).
function StateController.normalizeField(field: string, value: any): (boolean, any)
	if value == nil then
		return false, nil
	end
	if field == "coins" then
		if not isCount(value) then
			return false, nil
		end
		return true, math.floor(value)
	elseif field == "equipped" then
		if type(value) ~= "string" or value == "" then
			return false, nil
		end
		return true, value
	elseif field == "policy" then
		if type(value) ~= "string" or not POLICY_STATES[value] then
			return false, nil
		end
		return true, value
	elseif field == "dataStatus" then
		if type(value) ~= "table" or type(value.status) ~= "string" or not DATA_STATUSES[value.status] then
			return false, nil
		end
		local status: Types.DataStatus = {
			status = value.status :: Types.DataStatusName,
			persisted = value.persisted ~= false,
			savePending = value.savePending == true,
			-- reading: the server's banner choice, a Strings key (dropped when it names no text)
			banner = if type(value.banner) == "string" and Strings.resolve(value.banner) ~= nil
				then value.banner
				else nil,
		}
		return true, status
	elseif field == "settings" then
		if type(value) ~= "table" then
			return false, nil
		end
		local defaults = DATA.DefaultSettings
		local settings: Types.Settings = {
			music = volume(value.music, defaults.music),
			sfx = volume(value.sfx, defaults.sfx),
			cameraShake = if type(value.cameraShake) == "boolean" then value.cameraShake else defaults.cameraShake,
			showTips = if type(value.showTips) == "boolean" then value.showTips else defaults.showTips,
		}
		return true, settings
	elseif TABLE_FIELDS[field] then
		if type(value) ~= "table" then
			return false, nil
		end
		return true, value
	end
	return true, value
end

-- Applies a Snapshot / StateDelta to a store. Returns the new store (the same table when nothing applies) and the
-- names of the fields whose value changed (sorted). A field of the wrong shape is not stored (normalizeField).
function StateController.reduceProfile(
	store: ProfileStore,
	v: number,
	fields: { [string]: any },
	full: boolean?
): (ProfileStore, { string })
	if not finite(v) or type(fields) ~= "table" then
		return store, {}
	end
	if v < store.v or (v == store.v and not full) then
		return store, {} -- older or repeated data (§2.7: the client ignores older data)
	end
	local newFields: { [string]: any } = if full then {} else table.clone(store.fields)
	for key, value in fields do
		if type(key) == "string" then
			local ok, normalized = StateController.normalizeField(key, value)
			if ok then
				newFields[key] = normalized
			end
		end
	end
	local changed: { string } = {}
	for key, value in newFields do
		local previous = store.fields[key]
		if previous ~= value then
			if StateController.deepEqual(previous, value) then
				newFields[key] = previous -- same content: keep the old table
			else
				table.insert(changed, key)
			end
		end
	end
	for key in store.fields do
		if newFields[key] == nil then
			table.insert(changed, key)
		end
	end
	table.sort(changed)
	return { v = v, loaded = store.loaded or full == true, fields = newFields }, changed
end

-- The new-squishy tracker step for an `owned` value. The first owned set (or any full Snapshot) becomes the baseline
-- and adds nothing new; afterwards every id that appears is new until seen. Ids no longer owned are dropped.
-- Returns a new tracker (the input is never modified).
function StateController.trackNewOwned(tracker: OwnedTracker, owned: any, full: boolean): OwnedTracker
	if type(owned) ~= "table" then
		return tracker
	end
	local ids: { [string]: boolean } = {}
	for id in owned do
		if type(id) == "string" then
			ids[id] = true
		end
	end
	local fresh: { [string]: boolean } = {}
	for id in tracker.fresh do
		if ids[id] then
			fresh[id] = true
		end
	end
	local baseline = tracker.baseline
	if baseline ~= nil and not full then
		for id in ids do
			if not baseline[id] then
				fresh[id] = true
			end
		end
	end
	return { baseline = ids, fresh = fresh }
end

-- The requestIds (`req`) of an unseenReveals list, as a set (malformed entries are skipped).
local function unseenIds(list: any): { [string]: boolean }
	local ids: { [string]: boolean } = {}
	if type(list) == "table" then
		for _, entry in list do
			if type(entry) == "table" and type(entry.req) == "string" then
				ids[entry.req] = true
			end
		end
	end
	return ids
end

-- Reveal holds (see the header): Coins and owned as shown while the results of the `held` requestIds are not
-- revealed. For each held unseenReveals entry (a boxLog entry {req, squishy, dup, refund, ...}): a duplicate's refund is
-- taken off the Coins (never below 0), a new squishy (dup == false) is left out of owned. The inputs are not changed;
-- an unchanged value is returned as the same table.
function StateController.hideHeldReveals(coins: any, owned: any, unseen: any, held: { [string]: any }): (any, any)
	if type(unseen) ~= "table" or next(held) == nil then
		return coins, owned
	end
	local refund = 0
	local hidden: { string } = {}
	for _, entry in unseen do
		if type(entry) == "table" and type(entry.req) == "string" and held[entry.req] ~= nil then
			if entry.dup == true then
				if isCount(entry.refund) then
					refund += math.floor(entry.refund)
				end
			elseif entry.dup == false and type(entry.squishy) == "string" then
				table.insert(hidden, entry.squishy)
			end
		end
	end
	local shownCoins = coins
	if refund > 0 and isCount(coins) then
		shownCoins = math.max(0, math.floor(coins) - refund)
	end
	local shownOwned = owned
	if #hidden > 0 and type(owned) == "table" then
		for _, id in hidden do
			if shownOwned[id] ~= nil then
				if shownOwned == owned then
					shownOwned = table.clone(owned)
				end
				shownOwned[id] = nil
			end
		end
	end
	return shownCoins, shownOwned
end

-- The reveal-hold step for one applied state (see the header). Returns (start, stop), sorted: `start` = requestIds
-- that are in `newUnseen` but not in `oldUnseen`, for a partial state applied after the first full one (nothing new
-- is held on the first load or any full state); `stop` = held ids no longer in `newUnseen` (seen), or every held id
-- for a full state.
function StateController.revealHoldStep(
	held: { [string]: any },
	oldUnseen: any,
	newUnseen: any,
	full: boolean,
	wasLoaded: boolean
): ({ string }, { string })
	local now = unseenIds(newUnseen)
	local start: { string } = {}
	local stop: { string } = {}
	for id in held do
		if full or not now[id] then
			table.insert(stop, id)
		end
	end
	if not full and wasLoaded then
		local before = unseenIds(oldUnseen)
		for id in now do
			if not before[id] and held[id] == nil then
				table.insert(start, id)
			end
		end
	end
	table.sort(start)
	table.sort(stop)
	return start, stop
end

-- Applies a QueueStatus payload. An owner update has a valid `state`; a count-only board payload has none.
function StateController.reduceQueue(
	view: QueueView,
	current: QueueCounts,
	payload: unknown
): (QueueView, QueueCounts, QueueKind)
	if type(payload) ~= "table" then
		return view, current, "invalid"
	end
	local p = payload :: any
	local newCounts: QueueCounts = {
		searching = countOr(p.searching, current.searching),
		duelsInProgress = countOr(p.duelsInProgress, current.duelsInProgress),
		arenasFree = countOr(p.arenasFree, current.arenasFree),
	}
	if p.state == nil then
		if not (isCount(p.searching) or isCount(p.duelsInProgress) or isCount(p.arenasFree)) then
			return view, current, "invalid"
		end
		local updated = table.clone(view)
		updated.searching = newCounts.searching
		updated.duelsInProgress = newCounts.duelsInProgress
		updated.arenasFree = newCounts.arenasFree
		return updated, newCounts, "counts"
	end
	if type(p.state) ~= "string" or not QUEUE_STATES[p.state] then
		return view, current, "invalid"
	end
	local newView: QueueView = {
		state = p.state :: Types.QueueState,
		position = if isCount(p.position) and p.position >= 1 then math.floor(p.position) else nil,
		joinedAt = if finite(p.joinedAt) then p.joinedAt else nil,
		messageKey = if type(p.messageKey) == "string" and p.messageKey ~= "" then p.messageKey else nil,
		searching = newCounts.searching,
		duelsInProgress = newCounts.duelsInProgress,
		arenasFree = newCounts.arenasFree,
	}
	return newView, newCounts, "owner"
end

-- Applies one duel event to the current view (nil = not in a match). Returns the new view (the same table when
-- nothing changes, nil when the match is over for this client).
function StateController.reduceDuel(view: DuelView?, event: DuelEvent): DuelView?
	if event.kind == "state" then
		local raw = event.state
		if type(raw) ~= "table" then
			return view
		end
		local s = raw :: any
		local phaseIndex = if type(s.phase) == "string" then PHASE_ORDER[s.phase] else nil
		if type(s.matchId) ~= "string" or phaseIndex == nil or not finite(s.phaseEndsAt) then
			return view
		end
		local you, opponent = participantFrom(s.you), participantFrom(s.opponent)
		if you == nil or opponent == nil then
			return view
		end
		local same = view ~= nil and view.matchId == s.matchId
		if same and view and phaseIndex < (PHASE_ORDER[view.phase] or 0) then
			return view -- a match never goes back a phase
		end
		local newView: DuelView = {
			matchId = s.matchId,
			phase = s.phase,
			phaseEndsAt = s.phaseEndsAt,
			you = you,
			opponent = opponent,
			arena = if type(s.arena) == "table" then s.arena else (if same and view then view.arena else {} :: any),
			rules = if type(s.rules) == "table" then s.rules else (if same and view then view.rules else {}),
			charges = if same and view then table.clone(view.charges) else {},
			positioned = (same and view ~= nil and view.positioned)
				or (phaseIndex >= PHASE_ORDER.Positioning and phaseIndex <= PHASE_ORDER.Returning),
			receivedAt = event.now,
		}
		if same and view then
			newView.you.invulnUntil = view.you.invulnUntil
			newView.opponent.invulnUntil = view.opponent.invulnUntil
		end
		return newView
	elseif event.kind == "impact" then
		local raw = event.impact
		if view == nil or type(raw) ~= "table" then
			return view
		end
		local impact = raw :: any
		if impact.kind ~= "player" or not finite(impact.victimId) or not finite(impact.livesLeft) then
			return view
		end
		local newView = copyView(view)
		local target: Participant? = nil
		if newView.you.userId == impact.victimId then
			target = newView.you
		elseif newView.opponent.userId == impact.victimId then
			target = newView.opponent
		end
		if target == nil then
			return view
		end
		target.lives = math.max(0, impact.livesLeft)
		if finite(impact.invulnUntil) then
			target.invulnUntil = impact.invulnUntil
		end
		return newView
	elseif event.kind == "charge" then
		local raw = event.charge
		if view == nil or type(raw) ~= "table" then
			return view
		end
		local c = raw :: any
		if not finite(c.ownerId) or not finite(c.charge) then
			return view
		end
		local newView = copyView(view)
		newView.charges[c.ownerId] = math.max(0, c.charge)
		for _, participant in { newView.you, newView.opponent } do
			if participant.userId == c.ownerId then
				local chargeMax = chargeMaxFor(participant.squishyId)
				participant.ultReady = chargeMax ~= nil and c.charge >= chargeMax
			end
		end
		return newView
	elseif event.kind == "cleared" then
		if view == nil then
			return nil
		end
		if END_PHASES[view.phase] or event.now - view.receivedAt > STALE_CLEAR_SECONDS then
			return nil
		end
		return view
	end
	return view
end

-- True from Matched through Returning (§5.4: menus, equip, Inspect, boxes and shop are blocked).
function StateController.lobbyLocked(queue: QueueView, duel: DuelView?): boolean
	return queue.state == "Matched" or duel ~= nil
end

-- True for a DuelResult payload the HUD can show.
function StateController.isValidResult(payload: unknown): boolean
	if type(payload) ~= "table" then
		return false
	end
	local r = payload :: any
	return type(r.matchId) == "string" and type(r.outcome) == "string" and OUTCOMES[r.outcome] == true
end

-- Public: profile --------------------------------------------------------------------------------------------------

-- The current value of a field: a local override when one is set, else the server's value.
function StateController.get(field: string): any
	return effective(field)
end

-- The server's own value of a field (ignores local overrides).
function StateController.serverValue(field: string): any
	return profile.fields[field]
end

function StateController.version(): number
	return profile.v
end

function StateController.isLoaded(): boolean
	return profile.loaded
end

-- True while the change signals of a full Snapshot / StateDelta run (the first load, or a profile recovered after an
-- OFFLINE start, §3.13): a value that moves then was replaced, not earned (the HUD shows no "+N" for it).
function StateController.isApplyingFull(): boolean
	return applyingFull
end

-- The per-field signal (value, old), created on first use. Fires for changes of the current value (get).
function StateController.changed(field: string): Signal.Signal<any, any>
	local signal = fieldSignals[field]
	if signal == nil then
		signal = Signal.new()
		fieldSignals[field] = signal
	end
	return signal
end

-- Sets (or with nil clears) a local override of a field; Changed / changed(field) fire when the current value moves.
function StateController.setOverride(field: string, value: any)
	local before = effective(field)
	overrides[field] = value
	local after = effective(field)
	if not StateController.deepEqual(before, after) then
		fireChanged(field, after, before)
	end
end

function StateController.hasOverride(field: string): boolean
	return overrides[field] ~= nil
end

-- Coins, or nil before the profile arrived.
function StateController.coins(): number?
	local coins = effective("coins")
	return if type(coins) == "number" then coins else nil
end

-- The owned map (squishyId -> entry); empty before the profile arrived.
function StateController.owned(): { [string]: any }
	local owned = effective("owned")
	return if type(owned) == "table" then owned else {}
end

function StateController.owns(squishyId: string): boolean
	return StateController.owned()[squishyId] ~= nil
end

-- The equipped squishy id (the starter until the profile says otherwise).
function StateController.equipped(): string
	local equipped = effective("equipped")
	return if type(equipped) == "string" and Catalog.isValidId(equipped) then equipped else Catalog.starterId()
end

-- The settings with every key present (Config.Data defaults until the profile arrived).
function StateController.settings(): Types.Settings
	local settings = effective("settings")
	if type(settings) == "table" then
		return settings
	end
	local defaults = DATA.DefaultSettings
	return {
		music = defaults.music,
		sfx = defaults.sfx,
		cameraShake = defaults.cameraShake,
		showTips = defaults.showTips,
	}
end

-- The data status, or nil while the server sent none (a server without profiles).
function StateController.dataStatus(): Types.DataStatus?
	local status = effective("dataStatus")
	return if type(status) == "table" then status else nil
end

-- True when the server holds a ready profile for this player (§3.13: not loading, offline or read-only).
function StateController.isProfileReady(): boolean
	local status = StateController.dataStatus()
	return status ~= nil and status.status == "ready"
end

-- Public: new squishies (session-local) ------------------------------------------------------------------------------

function StateController.isNewOwned(squishyId: string): boolean
	return ownedTracker.fresh[squishyId] == true
end

-- Ids gained this session and not seen yet, sorted.
function StateController.newOwnedIds(): { string }
	local ids = {}
	for id in ownedTracker.fresh do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function StateController.markOwnedSeen(squishyId: string)
	if ownedTracker.fresh[squishyId] then
		local fresh = table.clone(ownedTracker.fresh)
		fresh[squishyId] = nil
		ownedTracker = { baseline = ownedTracker.baseline, fresh = fresh }
		StateController.NewOwnedChanged:fire(countKeys(fresh))
	end
end

-- Public: reveal holds (see the header) ------------------------------------------------------------------------------

-- Shows the held result of `requestId` (its refund in the Coins, its new squishy in owned and as NEW). Returns true
-- when it was held. BoxController calls it once the reveal reached its result (or closed as seen).
function StateController.releaseReveal(requestId: string): boolean
	if type(requestId) ~= "string" or heldReveals[requestId] == nil then
		return false
	end
	local before = shownHeldFields()
	stopHold(requestId)
	recomputeHeld()
	if fireHeldChanges(before) then
		trackOwned(true, false)
	end
	return true
end

-- The held requestIds, sorted (debug views and tests).
function StateController.heldRevealIds(): { string }
	local ids = {}
	for id in heldReveals do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- §2.6 boot step: see the header. Returns true when a Snapshot (or a full StateDelta) is in.
function StateController.loadSnapshotAsync(): boolean
	if profile.loaded then
		return true
	end
	local deadline = os.clock() + NET_CLIENT.snapshotWaitSeconds
	local retry = NET_CLIENT.snapshotRetrySeconds
	while not profile.loaded and os.clock() < deadline do
		local sentAt = os.clock()
		local reply: NetController.Result? = nil
		local arrived = Signal.new()
		task.spawn(function()
			local result = NetController.requestSnapshotAsync()
			reply = result
			if result.ok and type(result.data) == "table" and result.data.status ~= "loading" then
				applyProfile(result.v, result.data, true)
			end
			arrived:fire()
		end)
		local loadedConnection = StateController.Loaded:once(function()
			arrived:fire()
		end)
		local timer = task.delay(retry, function()
			arrived:fire()
		end)
		if reply == nil and not profile.loaded then
			arrived:wait()
		end
		-- When the timer itself woke us (no reply in time), it is still mid-call (status "normal") and cannot be
		-- cancelled: task.cancel would throw "cannot cancel thread" and stop the client boot (Part 4 test play).
		if coroutine.status(timer) == "suspended" then
			task.cancel(timer)
		end
		loadedConnection:disconnect()
		arrived:destroy()
		if profile.loaded then
			return true
		end
		local result = reply
		if result == nil then
			log:info("no snapshot reply yet; the game starts and the snapshot is applied when it arrives")
			return false
		end
		if not result.ok then
			log:info("snapshot not available:", result.reason)
			return false
		end
		-- {status = "loading"}: ask again one retry interval after the last request.
		local wait = retry - (os.clock() - sentAt)
		if wait > 0 then
			task.wait(wait)
		end
	end
	return profile.loaded
end

-- Public: queue and duel -------------------------------------------------------------------------------------------

function StateController.queue(): QueueView
	return queueView
end

function StateController.queueCounts(): QueueCounts
	return counts
end

function StateController.duel(): DuelView?
	return duelView
end

function StateController.lastResult(): Types.DuelResultPayload?
	return lastResult
end

function StateController.isLobbyLocked(): boolean
	return locked
end

-- The ultimate charge of a participant (0 when none was sent).
function StateController.charge(userId: number): number
	local view = duelView
	return if view then view.charges[userId] or 0 else 0
end

-- Lifecycle --------------------------------------------------------------------------------------------------------

function StateController.init()
	local c = Cleanup.new()
	cleanup = c

	c:add(NetController.onStateDelta(function(v: number, fields: Types.StateDeltaFields, full: boolean?)
		applyProfile(v, fields :: any, full)
	end))
	c:add(NetController.onQueueStatus(function(payload: any)
		local newView, newCounts, kind = StateController.reduceQueue(queueView, counts, payload)
		if kind == "invalid" then
			return
		end
		local countsChanged = newCounts.searching ~= counts.searching
			or newCounts.duelsInProgress ~= counts.duelsInProgress
			or newCounts.arenasFree ~= counts.arenasFree
		counts = newCounts
		if kind == "owner" then
			setQueue(newView)
		else
			queueView = newView
		end
		if countsChanged or kind == "counts" then
			StateController.QueueCountsChanged:fire(newCounts)
		end
	end))
	c:add(NetController.onDuelState(function(state: any)
		onDuelEvent({ kind = "state", state = state, now = os.clock() })
	end))
	c:add(NetController.onThrowImpact(function(impact: any)
		onDuelEvent({ kind = "impact", impact = impact })
	end))
	-- Feature 1 (2026-10-11): a caught throw's burst costs the thrower a life (CatchEvent "burst" with livesLeft): the
	-- same reduction as a hit's ThrowImpact.
	c:add(NetController.onCatchEvent(function(event: any)
		if type(event) == "table" and event.phase == "burst" and type(event.livesLeft) == "number" then
			onDuelEvent({
				kind = "impact",
				impact = {
					kind = "player",
					victimId = event.throwerId,
					livesLeft = event.livesLeft,
					invulnUntil = event.invulnUntil,
				},
			})
		end
	end))
	c:add(NetController.onUltimateCharge(function(charge: any)
		onDuelEvent({ kind = "charge", charge = charge })
	end))
	c:add(NetController.onDuelResult(function(result: any)
		if StateController.isValidResult(result) then
			lastResult = result
			StateController.DuelResultReceived:fire(result)
		end
	end))

	local pendingClear: thread? = nil
	c:add(function()
		if pendingClear then
			task.cancel(pendingClear)
			pendingClear = nil
		end
	end)
	local player = Players.LocalPlayer
	if player then
		c:add(player:GetAttributeChangedSignal(ATTR_DUEL_PHASE):Connect(function()
			local phase = player:GetAttribute(ATTR_DUEL_PHASE)
			if phase == "" or phase == nil then
				onDuelEvent({ kind = "cleared", now = os.clock() })
				-- A view too new to clear now (see STALE_CLEAR_SECONDS) is cleared once it is old enough, if the
				-- player is still out of any match by then.
				if pendingClear then
					task.cancel(pendingClear)
				end
				pendingClear = task.delay(STALE_CLEAR_SECONDS * 2, function()
					pendingClear = nil
					local later = player:GetAttribute(ATTR_DUEL_PHASE)
					if later == "" or later == nil then
						onDuelEvent({ kind = "cleared", now = os.clock() })
					end
				end)
			end
		end))
	end
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function StateController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
	for id in table.clone(heldReveals) do
		stopHold(id)
	end
	heldView = nil
end

return StateController
