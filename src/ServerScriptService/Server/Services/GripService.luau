--!strict
-- GripService (server only). DESIGN §17.2-§17.4, §17.3.1 step 8a, §17.3.4, §17.3.6, §17.6, §17.7, §17.9, §17.10.
-- Grip is a lobby-only stat: never a currency, never sold, never read by duel or matchmaking code (§17.2). This
-- service is its only runtime writer (§17.2 rule 2: GripService, ProfileSchema's migration and sanitize, and the
-- Studio DebugHooks through the debug* functions below). There is no Grip remote: Grip comes only from
--   * addFromSqueeze(p, tier) - step 8a of a squeeze SqueezeService accepted, after the earnings limit decided the
--     Coins, whether or not it paid. One Double Grip point is used when there is one (SqueezeLimit.spend on
--     grip.rested with Config.Grip.Rested) and the Grip is GripMath.squeezeGrip(trainer, tier) × Rested.mult when
--     doubled. The squeeze time is recorded so slow training never stacks with squeezing;
--   * the slow-training tick (§17.3.6): one server check per player every Afk.tickSeconds (players spread over the
--     window by userId; nothing the client sends starts or speeds it). A tick pays GripMath.afkGrip(trainer, tier)
--     only when, in this order: Grip and slow training are enabled and the server is not closing; the profile is
--     ready; the character is alive with a root part; not in a match (SD_DuelPhase == ""); the server-side root is
--     over a pad (WorldLayout.stationUnder with padMargin / heightAbove; a station disabled by SqueezeService's
--     stale-lobby check counts as no pad); that pad's tier is unlocked; the player was on the same pad at the
--     previous tick; no accepted squeeze since the previous tick; and the bank (grip.afk, SqueezeLimit.spend with
--     Config.Grip.Afk) has a point. A paid tick adds Grip only: never Coins, quests, stats.squeezes, SD_SqueezeAt,
--     onboarding or Double Grip, and it is never doubled. It reaches the client in the normal StateDelta batch.
-- Every gain is clamped to Config.Grip.maxGripPerEvent and the total to maxGrip (a clamp logs [SD][abuse]); a
-- rolling-hour counter per player logs [SD][abuse] above gripAlertPerHour (a log only, §17.9 #12). The profile write
-- itself (inside DataService.mutate) is arithmetic only; toasts, the level and LevelChanged follow once it is done.
-- Levels: the server-written Player attribute SD_GripLevel and LevelChanged(player, old, new, silent). When a profile
-- loads (DataService.Loaded) the level baseline is set silently (no level-up or rank-up toast, no broadcast, §17.7
-- "Load-time level jumps"); a later level-up sends grip.levelUp, grip.padUnlocked for every pad it opened, a
-- grip.rankUp broadcast to the players in the lobby (SD_DuelPhase == "") when the rank changed, and asks for a "soon"
-- save (§17.9 #7). Grip itself rides the autosave (StateService.markDirty(p, "grip") on every change).
-- Load toasts (on each Loaded): grip.headStart when the v1 -> v2 migration ran this session (DataService.migratedFrom)
-- and gave Grip; grip.welcome when Double Grip is full and either grew by welcomeBackMinGain since the last save or no
-- Grip was ever trained (reading: DESIGN lists the toast, not its trigger); else grip.welcomeBack when it grew by at
-- least welcomeBackMinGain. "Since the last save" = since the loaded profile's lastSeenAt (§3.9 stamps it on every
-- save snapshot). grip.intro when the total first rises above 0.
-- disableStation(id): called by SqueezeService's stale-lobby check (SqueezeService sits above this service, so the call
-- goes downward, §2.6); ticks skip that station.
-- Studio only (RunService:IsStudio() and Config.Debug.debugHooks): debugSetTotal / debugSetRested / debugSetAfkBank
-- (DebugHooks setGrip, setRested, setAfkBank), debugTick, debugSetTickSeconds, debugNotices, debugState.
-- Part 7: upgradeTrainer(p, targetLevel, expectedPrice), the TrainerUpgrade RF (§17.5, §17.10), is the only writer of
-- grip.trainer. In DESIGN order: (2) the argument range, then (4)-(7) replay / trainer.notNext / trainer.locked /
-- trainer.priceChanged, all through the pure GripMath.upgradeDecision, with (3) the ready profile (data.notReady)
-- checked between them; (8) a pending failed save, the server closing or a restart pending -> trainer.paused; (9)
-- SD_DuelPhase ~= "" -> inventory.lockedInDuel; (10) EconomyService.trySpend(p, cost, "trainer") (else
-- economy.notEnoughCoins; its "savePending" -> trainer.paused), then grip.trainer is set through DataService.mutate,
-- the grip field is marked, grip.trainerBought is sent, and the "now" save is awaited before the reply {trainer,
-- charged = true, savePending}. A replay (the target already owned: the stored trainer is the idempotency key, §3.4
-- trainer row) is ok {trainer, charged = false, savePending}. Every refusal carries charged = false. Nothing yields
-- between the spend and the trainer write. Coins are never added here, and nothing here is sold for Robux (§6.11).
-- Every Grip write goes through DataService.mutate (the data port), the one way to change a saved profile: a session
-- that no longer takes changes (not ready, or its final save already took its snapshot) earns nothing.
-- Dependencies are injectable (useDeps) so unit tests run with fake profiles, positions and clocks; players are only
-- used as table keys and handed back to the dependencies, so a test may use plain tables.
-- init() never yields; playerAdded / playerRemoving never yield.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local GripMath = require(Shared.GripMath)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local SqueezeLimit = require(Shared.SqueezeLimit)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

local Services = script.Parent
local CharacterService = require(Services.CharacterService)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local NetService = require(Services.NetService)
local ShutdownService = require(Services.ShutdownService)
local StateService = require(Services.StateService)

-- Types

export type LimitState = Types.GripTimerState
export type GripState = Types.GripState

-- What addFromSqueeze gave (the SqueezeResult fields grip, gripTotal and doubled). Reading: `grip` is what the total
-- really gained (less than the event only at maxGrip), like SqueezeResult.coins at the Coin cap.
export type SqueezeGain = { grip: number, gripTotal: number, doubled: boolean }

-- One slow-training tick: the Grip it paid and why (reasons: "off", "notReady", "noCharacter", "inMatch", "offPad",
-- "locked", "firstTick", "squeezed", "bankEmpty", "paid").
export type TickResult = { grip: number, reason: string, station: string? }

export type NoticeArgs = { [string]: string | number }
export type Notice = { userId: number, code: string, args: NoticeArgs?, at: number }

export type Deps = {
	clock: () -> number, -- measurement clock (os.clock): tick schedule, squeeze times, the anomaly window
	unixNow: () -> number, -- persistence clock (os.time): Double Grip and the slow-training bank
	statusOf: (player: any) -> string, -- DataService status: "loading" | "ready" | "offline" | "readonly"
	profileOf: (player: any) -> any, -- the profile table in memory (or nil); read only
	-- DataService.mutate through the data port: runs fn(profile) on a READY session that still takes changes and
	-- returns (true, fn's result), else (false, reason). Every Grip write goes through it (§3.9: a change made after
	-- the final save snapshot was taken would be lost, so mutate refuses it and nothing is earned).
	mutate: (player: any, fn: (profile: any) -> any) -> (boolean, any),
	rootOf: (player: any) -> (Vector3?, boolean), -- server-side root position, and whether the character is alive
	duelPhaseOf: (player: any) -> string, -- SD_DuelPhase ("" outside a match)
	isClosing: () -> boolean,
	markDirty: (player: any, field: string) -> (),
	requestSave: (player: any, reason: string) -> (),
	notify: (player: any, code: string, args: NoticeArgs?, kind: string) -> (),
	lobbyPlayers: () -> { any }, -- players outside a match (rank-up audience)
	setLevelAttribute: (player: any, level: number) -> (),
	migratedFrom: (player: any) -> number?, -- schema version a migration started from this session (nil = none)
	displayName: (player: any) -> string,
	-- Part 7 (the trainer purchase, upgradeTrainer):
	savePending: (player: any) -> boolean, -- a failed save is pending (DataService.isSavePending)
	isRestartPending: () -> boolean, -- ShutdownService.isRestartPending
	trySpend: (player: any, amount: number, reason: string) -> (boolean, string?), -- EconomyService.trySpend
	saveNow: (player: any) -> boolean, -- DataService.saveNowAsync (yields)
}

-- What upgradeTrainer answers: NetService.ok(Types.TrainerUpgradeResult) or NetService.err(reason, false).
export type UpgradeReply = { ok: boolean, data: Types.TrainerUpgradeResult?, reason: string?, charged: boolean? }

-- What one Grip write did (inside DataService.mutate): the gain, i.e. what the total really gained (less than the
-- event only at maxGrip; -1 = the slow-training bank had no point), the total before and after it, and whether
-- Double Grip doubled it.
type Written = { gain: number, before: number, after: number, doubled: boolean }

type Session = {
	player: any,
	level: number?, -- nil until the baseline is set (profile loaded)
	spread: number, -- 0..1: this player's place in the tick window
	nextTickAt: number, -- clock
	lastTickAt: number?, -- clock time of the previous tick
	lastStation: string?, -- the pad under the root at the previous tick
	lastSqueezeAt: number?, -- clock time of the last accepted squeeze
	gained: { [number]: number }, -- minute index -> Grip gained (rolling-hour anomaly counter)
	alerted: boolean,
	ticks: number,
	paidTicks: number,
	lastReason: string?,
}

-- Constants

local FIELD = "grip" -- StateDelta field (§17.10)
local ATTR_LEVEL = "SD_GripLevel"
local ATTR_PHASE = "SD_DuelPhase"
local STATUS_READY = "ready"
local STATUS_READONLY = "readonly"
local SAVE_SOON = "soon"
local SCHEMA_WITH_GRIP = 2 -- v1 -> v2 added grip (§17.10)
local MIN_LEVEL = 1
local LOOP_SECONDS = 0.25 -- how often the tick loop looks for players whose tick is due
local SPREAD_SLOTS = 100 -- players are spread over the tick window by userId % SPREAD_SLOTS
local MIN_DEBUG_TICK_SECONDS = 0.5
local ANOMALY_WINDOW_MINUTES = 60
local MAX_NOTICES = 100 -- Studio notice log length

local NOTICE_INTRO = "grip.intro"
local NOTICE_LEVEL_UP = "grip.levelUp"
local NOTICE_PAD_UNLOCKED = "grip.padUnlocked"
local NOTICE_RANK_UP = "grip.rankUp"
local NOTICE_HEAD_START = "grip.headStart"
local NOTICE_WELCOME = "grip.welcome"
local NOTICE_WELCOME_BACK = "grip.welcomeBack"
local NOTICE_TRAINER_BOUGHT = "grip.trainerBought"

-- The trainer purchase (Part 7, §17.5).
local REMOTE_TRAINER = "TrainerUpgrade"
local COIN_REASON_TRAINER = "trainer"
local CODE_INVALID = "net.invalid"
local CODE_NOT_READY = "data.notReady"
local CODE_PAUSED = "trainer.paused"
local CODE_IN_DUEL = "inventory.lockedInDuel"
local CODE_NOT_ENOUGH = "economy.notEnoughCoins"
local KIND_REPLAY = "replay"
local KIND_BUY = "buy"

-- Module table

local GripService = {}

-- Fired with (player, old, new, silent) whenever the player's Grip Level changes. old = 0 for the first baseline of a
-- session; silent = true for load baselines, debug changes marked silent and any drop (debug only).
GripService.LevelChanged = Signal.new() :: Signal.Signal<any, number, number, boolean>

-- Private

local log = Log.new("Grip")
local abuseLog = Log.new("abuse")
-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve these paths statically.
local dynamicRequire = require :: (ModuleScript) -> any

local sessions: { [any]: Session } = {}
local disabledStations: { [string]: boolean } = {}
local tickOverride: number? = nil
local notices: { Notice } = {}
local warned: { [string]: boolean } = {}
local cleanup: Cleanup.Cleanup? = nil
local loopThread: thread? = nil

local function warnOnce(key: string, ...: any)
	if not warned[key] then
		warned[key] = true
		log:warn(...)
	end
end

local function userIdOf(player: any): number
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok and type(id) == "number" then id else 0
end

local function duelPhaseAttribute(player: any): string
	if typeof(player) ~= "Instance" then
		return ""
	end
	local phase = (player :: Instance):GetAttribute(ATTR_PHASE)
	return if type(phase) == "string" then phase else ""
end

-- DataService.migratedFrom(p) (§17.10), read leniently like StateService's data port: DataService is looked up on first
-- use and a missing function means "no migration ran".
local dataServiceModule: any = nil
local dataServiceResolved = false
local function migratedFromDataService(player: any): number?
	if not dataServiceResolved then
		dataServiceResolved = true
		local module = Services:FindFirstChild("DataService")
		if module ~= nil and module:IsA("ModuleScript") then
			local ok, result = pcall(dynamicRequire, module)
			dataServiceModule = if ok then result else nil
		end
	end
	local fn = if type(dataServiceModule) == "table" then dataServiceModule.migratedFrom else nil
	if type(fn) ~= "function" then
		return nil
	end
	local ok, version = pcall(fn, player)
	return if ok and type(version) == "number" then version else nil
end

local function defaultDeps(): Deps
	return {
		clock = os.clock,
		unixNow = os.time,
		statusOf = function(player: any): string
			return StateService.dataPort().status(player)
		end,
		profileOf = function(player: any): any
			return StateService.dataPort().getProfile(player)
		end,
		mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
			return StateService.dataPort().mutate(player, fn)
		end,
		rootOf = function(player: any): (Vector3?, boolean)
			local root = CharacterService.getRoot(player)
			return if root then root.Position else nil, CharacterService.isAlive(player)
		end,
		duelPhaseOf = duelPhaseAttribute,
		isClosing = function(): boolean
			return ShutdownService.isClosing()
		end,
		markDirty = function(player: any, field: string)
			StateService.markDirty(player, field)
		end,
		requestSave = function(player: any, reason: string)
			StateService.dataPort().requestSave(player, reason)
		end,
		notify = function(player: any, code: string, args: NoticeArgs?, kind: string)
			NetService.notify(player, code, args, kind :: any)
		end,
		lobbyPlayers = function(): { any }
			local list: { any } = {}
			for _, player in Players:GetPlayers() do
				if duelPhaseAttribute(player) == "" then
					table.insert(list, player)
				end
			end
			return list
		end,
		setLevelAttribute = function(player: any, level: number)
			if typeof(player) == "Instance" then
				(player :: Instance):SetAttribute(ATTR_LEVEL, level)
			end
		end,
		migratedFrom = migratedFromDataService,
		displayName = function(player: any): string
			if typeof(player) == "Instance" and (player :: Instance):IsA("Player") then
				return (player :: Player).DisplayName
			end
			return tostring(player)
		end,
		savePending = function(player: any): boolean
			return StateService.dataPort().savePending(player)
		end,
		isRestartPending = function(): boolean
			return ShutdownService.isRestartPending()
		end,
		trySpend = function(player: any, amount: number, reason: string): (boolean, string?)
			return EconomyService.trySpend(player, amount, reason)
		end,
		saveNow = function(player: any): boolean
			return DataService.saveNowAsync(player)
		end,
	}
end

local deps: Deps = defaultDeps()

local function debugAllowed(): boolean
	return RunService:IsStudio() and Config.Debug.debugHooks
end

local function tickSeconds(): number
	return tickOverride or Config.Grip.Afk.tickSeconds
end

local function isFiniteNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isLimitState(v: unknown): boolean
	return type(v) == "table" and type((v :: any).value) == "number" and type((v :: any).at) == "number"
end

-- The profile's grip field, or nil when it is missing or malformed (fail closed: nothing is earned).
local function gripOf(profile: any): GripState?
	if type(profile) ~= "table" then
		return nil
	end
	local grip = profile.grip
	if
		type(grip) ~= "table"
		or not isFiniteNumber(grip.total)
		or not isFiniteNumber(grip.trainer)
		or not isLimitState(grip.rested)
		or not isLimitState(grip.afk)
	then
		warnOnce("noGripField", "a loaded profile has no valid grip field (ProfileSchema v2); Grip is paused for it")
		return nil
	end
	return grip :: GripState
end

-- The grip state of a READY profile (the only state that earns), or nil. For reading: writes go through writeGrip.
local function readyGrip(player: any): GripState?
	if deps.statusOf(player) ~= STATUS_READY then
		return nil
	end
	return gripOf(deps.profileOf(player))
end

-- Runs fn(grip) on the live grip field inside DataService.mutate (synchronous, no yields). Returns fn's result, or
-- nil when the session takes no changes (not ready, or its final save already started) or has no valid grip field.
local function writeGrip<T>(player: any, fn: (grip: GripState) -> T?): T?
	local ok, result = deps.mutate(player, function(profile: any): T?
		local grip = gripOf(profile)
		if grip == nil then
			return nil
		end
		return fn(grip)
	end)
	return if ok then result else nil
end

local function newSession(player: any): Session
	local spread = (math.abs(userIdOf(player)) % SPREAD_SLOTS) / SPREAD_SLOTS
	return {
		player = player,
		level = nil,
		spread = spread,
		nextTickAt = deps.clock() + spread * tickSeconds(),
		lastTickAt = nil,
		lastStation = nil,
		lastSqueezeAt = nil,
		gained = {},
		alerted = false,
		ticks = 0,
		paidTicks = 0,
		lastReason = nil,
	}
end

local function ensureSession(player: any): Session
	local session = sessions[player]
	if session == nil then
		session = newSession(player)
		sessions[player] = session
	end
	return session
end

-- Sends a toast and, in Studio, records it for the L3 runner (debugNotices).
local function notice(player: any, code: string, args: NoticeArgs?, kind: string)
	deps.notify(player, code, args, kind)
	if debugAllowed() then
		table.insert(notices, { userId = userIdOf(player), code = code, args = args, at = os.clock() })
		while #notices > MAX_NOTICES do
			table.remove(notices, 1)
		end
	end
end

-- Text of a Strings key, for toast arguments the client only formats (pad and rank names live in Strings; validator
-- G6 checks every pad and rank key exists, so the fallback never shows).
local function text(key: string, fallback: string): string
	return Strings.resolve(key) or fallback
end

-- A level-up that is not silent: toasts (the level, each pad it opened), the rank broadcast and a "soon" save.
local function announceLevelUp(session: Session, old: number, new: number)
	local player = session.player
	local levelArgs: NoticeArgs = { level = new }
	notice(player, NOTICE_LEVEL_UP, levelArgs, "success")
	local unlocks = GripMath.unlocks(old, new)
	for _, tier in unlocks.pads do
		local pad = Config.Grip.Pads[tier]
		local padArgs: NoticeArgs = {
			pad = text("grip.pad." .. pad.key, pad.key),
			coins = pad.coinBonus,
			mult = pad.gripPercent / 100,
		}
		notice(player, NOTICE_PAD_UNLOCKED, padArgs, "success")
	end
	local rank = unlocks.rank
	if rank ~= nil then
		local args: NoticeArgs = { name = deps.displayName(player), rank = text("grip.rank." .. rank.key, rank.key) }
		for _, other in deps.lobbyPlayers() do
			notice(other, NOTICE_RANK_UP, args, "info")
		end
	end
	deps.requestSave(player, SAVE_SOON)
end

-- Sets the session level, the attribute and LevelChanged; announces a real level-up.
local function setLevel(session: Session, level: number, silent: boolean)
	local old = session.level
	if old == level then
		return
	end
	session.level = level
	deps.setLevelAttribute(session.player, level)
	local quiet = silent or old == nil or level < (old :: number)
	GripService.LevelChanged:fire(session.player, old or 0, level, quiet)
	if not quiet then
		announceLevelUp(session, old :: number, level)
	end
end

local function levelFrom(session: Session, grip: GripState): number
	return session.level or GripMath.levelFor(grip.total)
end

-- Clamps one gain to [0, maxGripPerEvent] (whole Grip, GripMath.clampEvent). A clamp logs [SD][abuse].
local function clampEvent(session: Session, amount: number, source: string): number
	local clamped, wasClamped = GripMath.clampEvent(amount)
	if wasClamped then
		abuseLog:warn(
			`user {userIdOf(session.player)} {source}: {amount} Grip clamped to maxGripPerEvent {Config.Grip.maxGripPerEvent}`
		)
	end
	return clamped
end

-- Rolling-hour anomaly counter (§17.9 #12): logs once when the last hour's Grip passes gripAlertPerHour.
local function recordGain(session: Session, amount: number)
	local minute = math.floor(deps.clock() / 60)
	session.gained[minute] = (session.gained[minute] or 0) + amount
	local sum = 0
	for m, value in session.gained do
		if m <= minute - ANOMALY_WINDOW_MINUTES then
			session.gained[m] = nil
		else
			sum += value
		end
	end
	if sum > Config.Grip.gripAlertPerHour then
		if not session.alerted then
			session.alerted = true
			abuseLog:warn(
				`user {userIdOf(session.player)} gained {sum} Grip in the last hour (alert above {Config.Grip.gripAlertPerHour})`
			)
		end
	else
		session.alerted = false
	end
end

-- Adds an already clamped gain to the live total. Runs inside DataService.mutate, so it only does arithmetic (and
-- logs): the toasts, the level and LevelChanged follow in afterGain, once the write is done. Returns the total before.
local function addToTotal(session: Session, grip: GripState, amount: number): number
	local before = grip.total
	if amount > 0 then
		local maxGrip = Config.Grip.maxGrip
		if before + amount > maxGrip then
			abuseLog:warn(`user {userIdOf(session.player)}: Grip total clamped to maxGrip {maxGrip}`)
		end
		grip.total = GripMath.addGrip(before, amount)
	end
	return before
end

-- After a gain was written: the rolling-hour counter, the intro toast (the first Grip ever) and the level (toasts,
-- the rank broadcast, the "soon" save and LevelChanged, §17.7, §17.9 #7).
local function afterGain(session: Session, before: number, after: number, amount: number)
	if amount <= 0 then
		return
	end
	recordGain(session, amount)
	if before <= 0 and after > 0 then
		notice(session.player, NOTICE_INTRO, nil, "info")
	end
	setLevel(session, GripMath.levelFor(after), false)
end

-- `savedAt` = the loaded profile's lastSeenAt: the time of its last save (every save snapshot stamps it, §3.9). The
-- welcome toasts measure how much Double Grip grew since then (§17.3.4 "since the last save"); grip.rested.at is only
-- the last time a point was used, which a long session without squeezing leaves far before the save.
local function loadToasts(session: Session, grip: GripState, savedAt: unknown)
	local player = session.player
	local migrated = deps.migratedFrom(player)
	-- Reading: the head start is shown only when it gave Grip (a v1 profile with 0 squeezes starts at Lv 1).
	if migrated ~= nil and migrated < SCHEMA_WITH_GRIP and grip.total > 0 then
		local headArgs: NoticeArgs = { level = session.level or GripMath.levelFor(grip.total) }
		notice(player, NOTICE_HEAD_START, headArgs, "success")
	end
	local rested = Config.Grip.Rested
	if not (Config.Grip.enabled and rested.enabled) then
		return
	end
	local now = deps.unixNow()
	local current = SqueezeLimit.current(grip.rested, now, rested)
	-- Reading: a profile with no valid save time counts the growth since the last use (grip.rested.at); a save time in
	-- the future (another server's clock) counts as now, so it never shows a toast.
	local since = if isFiniteNumber(savedAt)
		then math.min(savedAt :: number, now)
		elseif isFiniteNumber(grip.rested.at) then grip.rested.at
		else now
	local gain = current - SqueezeLimit.current(grip.rested, since, rested)
	local minGain = Config.Grip.welcomeBackMinGain
	if current >= rested.burst and (gain >= minGain or grip.total <= 0) then
		local welcomeArgs: NoticeArgs = { mult = rested.mult }
		notice(player, NOTICE_WELCOME, welcomeArgs, "info")
	elseif gain >= minGain then
		local backArgs: NoticeArgs = { minutes = GripMath.restedMinutes(current) }
		notice(player, NOTICE_WELCOME_BACK, backArgs, "info")
	end
end

-- One slow-training tick for a session (the §17.3.6 checks, in order).
local function tickSession(session: Session): TickResult
	local player = session.player
	local now = deps.clock()
	local previousStation = session.lastStation
	local previousTickAt = session.lastTickAt
	session.lastTickAt = now
	session.lastStation = nil
	session.ticks += 1

	local function result(grip: number, reason: string, station: string?): TickResult
		session.lastReason = reason
		return { grip = grip, reason = reason, station = station }
	end

	-- 1. enabled, not closing
	local afk = Config.Grip.Afk
	if not (Config.Grip.enabled and afk.enabled) or deps.isClosing() then
		return result(0, "off")
	end
	-- 2. profile ready
	local grip = readyGrip(player)
	if grip == nil then
		return result(0, "notReady")
	end
	-- 3. alive with a root part
	local position, alive = deps.rootOf(player)
	if not alive or position == nil then
		return result(0, "noCharacter")
	end
	-- 4. not in a match (Matched starts at Preparing; Searching is allowed)
	if deps.duelPhaseOf(player) ~= "" then
		return result(0, "inMatch")
	end
	-- 5. on a pad (server WorldLayout; disabled stations count as none)
	local station = WorldLayout.stationUnder(position, afk.padMargin, afk.heightAbove)
	if station == nil or disabledStations[station.id] then
		return result(0, "offPad")
	end
	session.lastStation = station.id
	-- 6. the pad is unlocked
	if Config.Grip.Pads[station.tier] == nil or not GripMath.canUseTier(levelFrom(session, grip), station.tier) then
		return result(0, "locked", station.id)
	end
	-- 7. on the same pad at the previous tick
	if previousStation ~= station.id then
		return result(0, "firstTick", station.id)
	end
	-- 8. no accepted squeeze since the previous tick
	local squeezedAt = session.lastSqueezeAt
	if squeezedAt ~= nil and previousTickAt ~= nil and squeezedAt >= previousTickAt then
		return result(0, "squeezed", station.id)
	end
	-- 9. a bank point (the bank and the gain are one write through DataService.mutate)
	local written = writeGrip(player, function(live: GripState): Written
		local paid, bank = SqueezeLimit.spend(live.afk, deps.unixNow(), afk)
		live.afk = bank
		if not paid then
			return { gain = -1, before = live.total, after = live.total, doubled = false }
		end
		local amount = clampEvent(session, GripMath.afkGrip(live.trainer, station.tier), "slow training")
		local before = addToTotal(session, live, amount)
		return { gain = live.total - before, before = before, after = live.total, doubled = false }
	end)
	if written == nil then
		return result(0, "notReady", station.id) -- the session stopped taking changes (e.g. its final save started)
	elseif written.gain < 0 then
		return result(0, "bankEmpty", station.id)
	end
	deps.markDirty(player, FIELD)
	session.paidTicks += 1
	afterGain(session, written.before, written.after, written.gain)
	return result(written.gain, "paid", station.id)
end

local function reschedule(now: number)
	local interval = tickSeconds()
	for _, session in sessions do
		session.nextTickAt = now + session.spread * interval
	end
end

-- Public: queries -------------------------------------------------------------------------------------------------------

-- The player's Grip Level (1..maxLevel): the session baseline, else computed from a ready or read-only profile, else 1.
function GripService.levelOf(player: any): number
	local session = sessions[player]
	if session and session.level then
		return session.level
	end
	local status = deps.statusOf(player)
	if status == STATUS_READY or status == STATUS_READONLY then
		local grip = gripOf(deps.profileOf(player))
		if grip then
			return GripMath.levelFor(grip.total)
		end
	end
	return MIN_LEVEL
end

-- True when the player's level opens the pad tier (§17.3.1 step 6a). An unknown tier is never open (fail closed).
function GripService.canUseTier(player: any, tier: number): boolean
	if Config.Grip.Pads[tier] == nil then
		return false
	end
	return GripMath.canUseTier(GripService.levelOf(player), tier)
end

-- True when SqueezeService's stale-lobby check disabled this station.
function GripService.isStationDisabled(stationId: string): boolean
	return disabledStations[stationId] == true
end

-- Public: writers -------------------------------------------------------------------------------------------------------

-- Step 8a of an accepted squeeze at a station of `tier` (SqueezeService has checked everything else). Returns the
-- Grip given, the new total and whether Double Grip doubled it. Nothing is given unless the profile is ready.
function GripService.addFromSqueeze(player: any, tier: number): SqueezeGain
	local session = ensureSession(player)
	session.lastSqueezeAt = deps.clock()
	local grip = readyGrip(player)
	if grip == nil then
		return { grip = 0, gripTotal = 0, doubled = false }
	end
	if not Config.Grip.enabled or Config.Grip.Pads[tier] == nil then
		return { grip = 0, gripTotal = grip.total, doubled = false }
	end
	if session.level == nil then
		setLevel(session, GripMath.levelFor(grip.total), true) -- the Loaded baseline was missed: set it silently
	end
	-- Double Grip and the gain are one write through DataService.mutate.
	local written = writeGrip(player, function(live: GripState): Written
		local rested = Config.Grip.Rested
		local doubled = false
		if rested.enabled then
			local paid, state = SqueezeLimit.spend(live.rested, deps.unixNow(), rested)
			live.rested = state
			doubled = paid
		end
		local amount = clampEvent(session, GripMath.squeezeGrip(live.trainer, tier, doubled), "squeeze")
		local before = addToTotal(session, live, amount)
		return { gain = live.total - before, before = before, after = live.total, doubled = doubled }
	end)
	if written == nil then
		return { grip = 0, gripTotal = grip.total, doubled = false } -- the session stopped taking changes
	end
	deps.markDirty(player, FIELD)
	afterGain(session, written.before, written.after, written.gain)
	return { grip = written.gain, gripTotal = written.after, doubled = written.doubled }
end

-- The TrainerUpgrade RF (§17.5; see the header for the order of the checks). `targetLevel` = the trainer index to buy,
-- `expectedPrice` = the price the client showed (only compared, never charged). Yields only for the awaited "now" save
-- after a purchase. Returns NetService.ok({trainer, charged, savePending}) or NetService.err(reason, false).
function GripService.upgradeTrainer(player: any, targetLevel: any, expectedPrice: any): UpgradeReply
	local grip = readyGrip(player)
	local state: GripMath.UpgradeState = {
		trainer = if grip then grip.trainer else 1,
		level = GripService.levelOf(player),
	}
	local decision = GripMath.upgradeDecision(state, targetLevel, expectedPrice)
	-- (2) the argument range: upgradeDecision checks it before anything that reads the profile.
	if decision.reason == CODE_INVALID then
		return NetService.err(CODE_INVALID, false)
	end
	-- (3) the profile is ready (and its grip field valid).
	if grip == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	-- (4) replay: the target is already owned.
	if decision.kind == KIND_REPLAY then
		local replay: Types.TrainerUpgradeResult =
			{ trainer = grip.trainer, charged = false, savePending = deps.savePending(player) }
		return NetService.ok(replay)
	end
	-- (5)-(7) trainer.notNext / trainer.locked / trainer.priceChanged.
	if decision.kind ~= KIND_BUY then
		return NetService.err(decision.reason or CODE_INVALID, false)
	end
	-- (8) paused while a failed save is pending, the server closes or a restart is pending.
	if deps.savePending(player) or deps.isClosing() or deps.isRestartPending() then
		return NetService.err(CODE_PAUSED, false)
	end
	-- (9) not from Matched through Returning.
	if deps.duelPhaseOf(player) ~= "" then
		return NetService.err(CODE_IN_DUEL, false)
	end
	-- (10) the spend, then the trainer, with nothing yielding in between.
	local cost = decision.cost
	if cost > 0 then
		local spent, why = deps.trySpend(player, cost, COIN_REASON_TRAINER)
		if not spent then
			local code = if why == "savePending"
				then CODE_PAUSED
				elseif why == "notReady" then CODE_NOT_READY
				elseif why == "notEnoughCoins" then CODE_NOT_ENOUGH
				else CODE_INVALID
			return NetService.err(code, false)
		end
	end
	local target = targetLevel :: number
	local written = writeGrip(player, function(live: GripState): number
		live.trainer = math.max(live.trainer, target)
		return live.trainer
	end)
	if written == nil then
		-- Cannot happen without a yield after the spend (the session was ready a moment ago); logged loudly.
		log:error(`user {userIdOf(player)}: trainer {target} was paid ({cost} Coins) but could not be written`)
		return NetService.err(CODE_NOT_READY, false)
	end
	deps.markDirty(player, FIELD)
	local def = Config.Grip.Trainer[written]
	local args: NoticeArgs = {
		trainer = text("grip.trainer." .. def.key, def.key),
		grip = GripMath.squeezeGrip(written, 1),
	}
	notice(player, NOTICE_TRAINER_BOUGHT, args, "success")
	log:info(`user {userIdOf(player)} bought trainer {written} ({def.key}) for {cost} Coins`)
	local saved = deps.saveNow(player)
	local result: Types.TrainerUpgradeResult = { trainer = written, charged = true, savePending = not saved }
	return NetService.ok(result)
end

-- Fail closed for a station whose lobby instance disagrees with WorldLayout (SqueezeService's stale-lobby check):
-- slow-training ticks skip it from now on.
function GripService.disableStation(stationId: string)
	if not disabledStations[stationId] then
		disabledStations[stationId] = true
		-- info: the caller (SqueezeService's stale-lobby check) already warns with the reason
		log:info(`station {stationId} disabled: no slow training there until the lobby is rebuilt`)
	end
end

-- Sets the level baseline from the loaded profile, silently (no toasts or broadcast). With `withToasts` (a
-- DataService.Loaded event) the load toasts follow. Profiles that are not ready or read-only are left alone.
function GripService.refreshBaseline(player: any, withToasts: boolean?)
	local session = ensureSession(player)
	local status = deps.statusOf(player)
	if status ~= STATUS_READY and status ~= STATUS_READONLY then
		return
	end
	local profile = deps.profileOf(player)
	local grip = gripOf(profile)
	if grip == nil then
		return
	end
	setLevel(session, GripMath.levelFor(grip.total), true)
	if withToasts and status == STATUS_READY then
		loadToasts(session, grip, profile.lastSeenAt)
	end
end

-- Runs one slow-training tick for the player now (the loop does this every tickSeconds). Returns what it paid.
function GripService.tick(player: any): TickResult
	return tickSession(ensureSession(player))
end

-- Runs the ticks that are due at `now` (default deps.clock()). Called by the loop every LOOP_SECONDS. A session of a
-- Player who already left (one a late squeeze re-created after playerRemoving) is dropped instead.
function GripService.step(now: number?)
	local t = if now ~= nil then now else deps.clock()
	local interval = tickSeconds()
	for key, session in table.clone(sessions) do
		if typeof(key) == "Instance" and (key :: Instance).Parent == nil then
			sessions[key] = nil
		elseif t >= session.nextTickAt then
			session.nextTickAt += interval
			if session.nextTickAt <= t then
				session.nextTickAt = t + interval
			end
			local ok, err = pcall(tickSession, session)
			if not ok then
				log:error(`slow-training tick failed for user {userIdOf(session.player)}:`, err)
			end
		end
	end
end

-- Public: Studio debug (DebugHooks) -------------------------------------------------------------------------------------

-- setGrip: sets the total (clamped to [0, maxGrip], whole). A level change announces like a real gain unless silent.
function GripService.debugSetTotal(player: any, total: unknown, silent: boolean?): (boolean, string?)
	if not debugAllowed() then
		return false, "Studio only"
	end
	if type(total) ~= "number" or not isFiniteNumber(total) then
		return false, "total must be a finite number"
	end
	local newTotal = writeGrip(player, function(live: GripState): number
		live.total = GripMath.clampTotal(total)
		return live.total
	end)
	if newTotal == nil then
		return false, "profile not ready"
	end
	deps.markDirty(player, FIELD)
	setLevel(ensureSession(player), GripMath.levelFor(newTotal), silent == true)
	return true, nil
end

local function debugSetLimit(
	player: any,
	value: unknown,
	key: "rested" | "afk",
	cfg: { perHour: number, burst: number }
): (boolean, string?)
	if not debugAllowed() then
		return false, "Studio only"
	end
	if type(value) ~= "number" or value ~= value then
		return false, "value must be a number"
	end
	local state: LimitState = { value = math.clamp(value, 0, cfg.burst), at = deps.unixNow() }
	local written = writeGrip(player, function(live: GripState): boolean
		if key == "rested" then
			live.rested = state
		else
			live.afk = state
		end
		return true
	end)
	if written == nil then
		return false, "profile not ready"
	end
	deps.markDirty(player, FIELD)
	return true, nil
end

-- setRested: Double Grip points, clamped to [0, Rested.burst], refilling from now.
function GripService.debugSetRested(player: any, value: unknown): (boolean, string?)
	return debugSetLimit(player, value, "rested", Config.Grip.Rested)
end

-- setAfkBank: slow-training bank points, clamped to [0, Afk.burst], refilling from now.
function GripService.debugSetAfkBank(player: any, value: unknown): (boolean, string?)
	return debugSetLimit(player, value, "afk", Config.Grip.Afk)
end

-- Forces one slow-training tick now (L3: two calls on the same pad pay once, with no squeeze in between).
function GripService.debugTick(player: any): TickResult?
	if not debugAllowed() then
		return nil
	end
	return GripService.tick(player)
end

-- Overrides the tick interval (Studio tests; at least MIN_DEBUG_TICK_SECONDS; a very large value pauses the loop).
-- nil restores Config.Grip.Afk.tickSeconds. Every session is rescheduled from now.
function GripService.debugSetTickSeconds(seconds: unknown): (boolean, string?)
	if not debugAllowed() then
		return false, "Studio only"
	end
	if seconds == nil then
		tickOverride = nil
	elseif type(seconds) == "number" and seconds == seconds and seconds >= MIN_DEBUG_TICK_SECONDS then
		tickOverride = seconds
	else
		return false, `seconds must be nil or a number >= {MIN_DEBUG_TICK_SECONDS}`
	end
	reschedule(deps.clock())
	return true, nil
end

-- The toasts sent this session (Studio only, newest last, at most MAX_NOTICES). `clear` empties the log after reading.
function GripService.debugNotices(clear: boolean?): { Notice }
	local copy = table.clone(notices)
	if clear then
		table.clear(notices)
	end
	return copy
end

-- Small state view for Studio debug hooks.
function GripService.debugState(): { [string]: any }
	local players: { [string]: any } = {}
	local count = 0
	for _, session in sessions do
		count += 1
		players[tostring(userIdOf(session.player))] = {
			level = session.level,
			lastStation = session.lastStation,
			lastReason = session.lastReason,
			ticks = session.ticks,
			paidTicks = session.paidTicks,
			alerted = session.alerted,
		}
	end
	local disabled: { string } = {}
	for id in disabledStations do
		table.insert(disabled, id)
	end
	table.sort(disabled)
	return {
		sessions = count,
		tickSeconds = tickSeconds(),
		disabledStations = disabled,
		players = players,
	}
end

-- Public: tests -----------------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function GripService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Forgets every session, disabled station, notice and debug override (tests; not called by the bootstrap).
function GripService.reset()
	table.clear(sessions)
	table.clear(disabledStations)
	table.clear(notices)
	tickOverride = nil
end

-- Lifecycle -----------------------------------------------------------------------------------------------------------

function GripService.init()
	local c = Cleanup.new()
	cleanup = c
	-- The data port's signals cannot be disconnected one by one, so destroy() switches these handlers off instead.
	local active = true
	c:add(function()
		active = false
	end)
	local port = StateService.dataPort()
	port.onLoaded(function(player: any)
		if active then
			GripService.refreshBaseline(player, true)
		end
	end)
	port.onStatusChanged(function(player: any)
		if active then
			GripService.refreshBaseline(player, false)
		end
	end)
	-- The trainer purchase (Part 7, §17.5). NetService has already narrowed both arguments to whole numbers.
	c:add(NetService.onInvoke(REMOTE_TRAINER, function(player: Player, targetLevel: any, expectedPrice: any): any
		return GripService.upgradeTrainer(player, targetLevel, expectedPrice)
	end))
end

function GripService.start()
	if loopThread ~= nil then
		return
	end
	loopThread = task.spawn(function()
		while true do
			task.wait(LOOP_SECONDS)
			GripService.step()
		end
	end)
end

function GripService.playerAdded(player: Player)
	ensureSession(player)
	GripService.refreshBaseline(player, false) -- a profile that finished loading before this hook ran
end

function GripService.playerRemoving(player: Player)
	sessions[player] = nil
end

-- Not called by the bootstrap; stops the loop and drops everything (leak checks).
function GripService.destroy()
	local thread = loopThread
	loopThread = nil
	if thread and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
	local c = cleanup
	cleanup = nil
	if c then
		c:clean()
	end
	GripService.reset()
	GripService.LevelChanged:disconnectAll()
end

return GripService
