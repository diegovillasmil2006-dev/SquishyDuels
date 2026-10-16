--!strict
-- SqueezeService (server only). DESIGN §6.3, §17.3.1 (step 8a), §17.6 ("One source for the pad tier"),
-- §17.9 #1-#3, §17.10 (SqueezeResult, server-time nextAt), §12 #4-#7 and #16, §2.8, §2.9 (SD_SqueezeAt).
-- SqueezeRequest() (no argument, spec 2026-10-11 §5: squeeze anywhere in the lobby) gathers the server's own facts
-- and lets the pure Logic/SqueezeRules.decide run the §6.3 order (flood guard; profile ready; a living character; not
-- in a match; the tier; the paid-squeeze cap; the earnings limit, off as shipped). The client sends nothing: the
-- pad comes from the server-side root position (SqueezeRules.padUnder, the "standing on it" test; a pad
-- the stale-lobby check disabled or the lobby does not have counts as none), and off a pad the squeeze pays tier 1
-- (base Coins and Grip, no pad bonus; every station is tier 1 since the giant pads went). The tier, the position,
-- the equipped squishy, the timing and every amount are the server's. No squeeze timer; squeezes pay up to the hold
-- rhythm (Batch 1 #2; Config.Squeeze: 2 at once, then 1 per 0.45 s): over it -> squeeze.tooFast with no Coins, no Grip
-- and no capsule push.
-- Auto-clicker check (2026-10-16): before anything else every request goes to AutoClickService.check(p, os.clock) (the
-- server's own arrival time; floods included). A reason back (squeeze.autoClick on a catch, squeeze.tooFast during its
-- penalty) is the reply at once, like any rejection: no Coins, no Grip, no stats, no capsule push, no token used. The
-- strikes, kicks and bans are AutoClickService's.
--   * dropped (flood guard) -> nothing, no reply; a flood is logged once ([SD][abuse]) when SqueezeRules says so;
--   * rejected -> SqueezeResult{ok = false, coins = 0, total, limit, reason, nextAt, grip = 0, gripTotal, doubled =
--     false}; no token used before step 7 and nothing earned (squeeze.noCharacter, squeeze.inDuel, data.notReady);
--   * accepted -> the new profile.squeezeLimit and stats.squeezes + 1 are written through DataService.mutate (a
--     session that stopped taking changes, e.g. its final save started, is answered data.notReady and earns
--     nothing); Grip through GripService.addFromSqueeze(p, tier) (step 8a, whether or not it paid); Coins (the squeeze
--     value, CapsuleMath.squeezeValue(profile.capsules), when paid, else emptyCoins; spec 2026-10-12 §3, Phase 3: the
--     held squishy and the pad no longer change it) through EconomyService.grantCoins(p, n, "squeeze"); a paid one
--     also pushes the player's capsules (CapsuleService.push with the server-side root position: only inside their
--     own base, lobby spec 2026-10-11 §6); the character attribute
--     SD_SqueezeAt = server time (others see the squeeze, their Foam Mat pulses); Squeezed(p, squishyId, coins, tier)
--     for the layers above (QuestService, Part 7: onSqueezed(p, id)); then SqueezeResult{ok = true, coins,
--     total, limit, nextAt, grip, gripTotal, doubled}. `coins` is what the balance really gained (0 at the Coin cap).
-- nextAt is a server time (§17.10): workspace:GetServerTimeNow() + max(0, 1 - tokens) × cycleSeconds, from the os.clock
-- bucket (with a full cap it is simply now). `limit` is the squeeze Coins limit's whole points left (dormant while the
-- limit is off). Accepted squeezes ride the autosave (§3.4: no idempotency key; the cap bounds them).
-- Squeeze alert (spec 2026-10-12 §12, like GripService's gripAlertPerHour; was a squeeze Coins alert): a rolling-hour
-- counter per player of the paid squeezes logs one [SD][abuse] warning when it passes Config.Grip.squeezeAlertPerHour;
-- a log only (the squeezes still pay); it re-arms once the hour's squeezes are back under it. counts().squeezeAlerts
-- counts them.
-- The equipped squishy comes from InventoryService (the server record); one that is not owned or not in the Catalog
-- falls back to the starter (§6.3 step 6, §12 #4).
-- Stale-lobby check (init, after WorldService indexed the lobby): every WorldLayout station is compared with its tagged
-- lobby instance. A GripTier attribute that differs from WorldLayout logs "stale lobby: rebuild" and disables the
-- station here (no boost: a squeeze there pays the base; build plan Phase 6: slow training, which GripService also
-- disabled there, is gone). Reading: a station missing from the lobby is disabled the same
-- way (fail closed; a lobby that was never built logs one line), and a tagged station unknown to WorldLayout is
-- logged (it can never be used: WorldLayout has no position or tier for it). This check lives here because
-- WorldService is a duel-path file (§17.6).
-- Studio only (Config.Debug.debugHooks): debugSetLimit (DebugHooks setSqueezeLimit) and debugState.
-- Dependencies are injectable (useDeps) for unit tests; players are only table keys handed back to the dependencies.
-- init() never yields; the request handler never yields.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local CapsuleMath = require(Shared.CapsuleMath)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local SqueezeLimit = require(Shared.SqueezeLimit)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

local Server = script.Parent.Parent
local SqueezeRules = require(Server.Logic.SqueezeRules)

local Services = script.Parent
local AutoClickService = require(Services.AutoClickService)
local CapsuleService = require(Services.CapsuleService)
local CharacterService = require(Services.CharacterService)
local EconomyService = require(Services.EconomyService)
local GripService = require(Services.GripService)
local InventoryService = require(Services.InventoryService)
local NetService = require(Services.NetService)
local StateService = require(Services.StateService)
local WorldService = require(Services.WorldService)

-- Types

-- The SqueezeResult payload (§2.8, §17.10).
export type SqueezeResult = Types.SqueezeResultPayload

export type Deps = {
	clock: () -> number, -- os.clock: the flood guard and the reward bucket
	unixNow: () -> number, -- os.time: the earnings limit
	serverNow: () -> number, -- workspace:GetServerTimeNow(): nextAt and SD_SqueezeAt
	statusOf: (player: any) -> string, -- "loading" | "ready" | "offline" | "readonly"
	profileOf: (player: any) -> any, -- the profile table in memory (or nil); read only
	-- DataService.mutate through the data port: fn(profile) on a READY session that still takes changes ->
	-- (true, fn's result), else (false, reason). The squeeze limit and stats.squeezes are written through it.
	mutate: (player: any, fn: (profile: any) -> any) -> (boolean, any),
	stationTagged: (stationId: string) -> boolean, -- the station exists in the generated lobby
	rootOf: (player: any) -> (Vector3?, boolean), -- server-side root position, and whether the character is alive
	duelPhaseOf: (player: any) -> string, -- SD_DuelPhase ("" outside a match)
	equippedOf: (player: any) -> string, -- the server's equipped squishy (owned, else the starter)
	grantCoins: (player: any, amount: number, reason: string) -> number, -- the Coins really added
	markDirty: (player: any, field: string) -> (),
	setSqueezeAt: (player: any, at: number) -> (),
	reply: (player: any, result: SqueezeResult) -> (),
	pushCapsules: (player: any, rootPosition: Vector3) -> (), -- CapsuleService.push (a paid squeeze)
	autoClick: (player: any, now: number) -> string?, -- AutoClickService.check: nil, or the reason to refuse with
}

-- One problem the stale-lobby check found.
export type StationProblem = {
	id: string,
	kind: "stale" | "missing" | "unknown", -- tier differs / not in the lobby / tagged but not in WorldLayout
	found: any?, -- the GripTier attribute the lobby has (stale) or nil
	expected: number?, -- the WorldLayout tier
}

type Session = {
	state: SqueezeRules.State,
	squeezes: { [number]: number }, -- minute index -> paid squeezes (rolling-hour squeeze alert)
	alerted: boolean,
}

type Stats = {
	accepted: number,
	paid: number,
	dropped: number,
	rejected: { [string]: number },
	squeezeAlerts: number, -- squeeze alerts logged (squeezeAlertPerHour)
}

-- Constants

local REMOTE_REQUEST = "SqueezeRequest"
local REMOTE_RESULT = "SqueezeResult"
local COIN_REASON = "squeeze"
local STATUS_READY = "ready"
local ATTR_PHASE = "SD_DuelPhase"
local ATTR_SQUEEZE_AT = "SD_SqueezeAt"
local ATTR_STATION_ID = WorldLayout.Attributes.StationId
local ATTR_GRIP_TIER = WorldLayout.Attributes.GripTier
local TAG_STATION = WorldLayout.Tags.SqueezeStation
local FIELD_STATS = "stats"
local FIELD_LIMIT = "squeezeLimit"
local REASON_NOT_READY = "data.notReady"
local NO_REASON = "none" -- counts() key for a rejection without a reason
local ALERT_WINDOW_MINUTES = 60 -- the squeeze alert's rolling hour (GripService's anomaly window)

-- Module table

local SqueezeService = {}

-- Fired with (player, squishyId, coins, tier) for every accepted squeeze (coins = what the balance gained; tier = the
-- station's GripTier from WorldLayout). QuestService (Part 7) counts squeezes from it.
SqueezeService.Squeezed = Signal.new() :: Signal.Signal<any, string, number, number>

-- Private

local log = Log.new("Squeeze")
local abuseLog = Log.new("abuse")

local sessions: { [any]: Session } = {}
local disabledStations: { [string]: boolean } = {}
local stats: Stats = { accepted = 0, paid = 0, dropped = 0, rejected = {}, squeezeAlerts = 0 }

local function duelPhaseAttribute(player: any): string
	if typeof(player) ~= "Instance" then
		return ""
	end
	local phase = (player :: Instance):GetAttribute(ATTR_PHASE)
	return if type(phase) == "string" then phase else ""
end

local function userIdOf(player: any): number
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok and type(id) == "number" then id else 0
end

local function defaultDeps(): Deps
	return {
		clock = os.clock,
		unixNow = os.time,
		serverNow = function(): number
			return Workspace:GetServerTimeNow()
		end,
		statusOf = function(player: any): string
			return StateService.dataPort().status(player)
		end,
		profileOf = function(player: any): any
			return StateService.dataPort().getProfile(player)
		end,
		mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
			return StateService.dataPort().mutate(player, fn)
		end,
		stationTagged = function(stationId: string): boolean
			return WorldService.station(stationId) ~= nil
		end,
		rootOf = function(player: any): (Vector3?, boolean)
			local root = CharacterService.getRoot(player)
			return if root then root.Position else nil, CharacterService.isAlive(player)
		end,
		duelPhaseOf = duelPhaseAttribute,
		equippedOf = function(player: any): string
			local id = InventoryService.getEquipped(player)
			if Catalog.isValidId(id) and InventoryService.owns(player, id) then
				return id
			end
			return Catalog.starterId()
		end,
		grantCoins = function(player: any, amount: number, reason: string): number
			local added = EconomyService.grantCoins(player, amount, reason)
			return added
		end,
		markDirty = function(player: any, field: string)
			StateService.markDirty(player, field)
		end,
		setSqueezeAt = function(player: any, at: number)
			if typeof(player) == "Instance" and (player :: Instance):IsA("Player") then
				local character = (player :: Player).Character
				if character then
					character:SetAttribute(ATTR_SQUEEZE_AT, at)
				end
			end
		end,
		reply = function(player: any, result: SqueezeResult)
			NetService.fire(REMOTE_RESULT, player, result)
		end,
		pushCapsules = function(player: any, rootPosition: Vector3)
			CapsuleService.push(player, rootPosition)
		end,
		autoClick = AutoClickService.check,
	}
end

local deps: Deps = defaultDeps()

local function debugAllowed(): boolean
	return RunService:IsStudio() and Config.Debug.debugHooks
end

local function sessionOf(player: any, now: number): Session
	local session = sessions[player]
	if session == nil then
		session = { state = SqueezeRules.newState(now), squeezes = {}, alerted = false }
		sessions[player] = session
	end
	return session
end

local function isLimitState(v: unknown): boolean
	return type(v) == "table" and type((v :: any).value) == "number" and type((v :: any).at) == "number"
end

-- The pad the server-side root stands on (SqueezeRules.padUnder), or nil: off every pad, no living character, or a pad
-- the lobby does not have or the stale-lobby check disabled (no boost there). Never a station id from the client.
local function padAt(rootPosition: Vector3?): SqueezeRules.StationInfo?
	local station = if rootPosition then SqueezeRules.padUnder(rootPosition) else nil
	if station == nil or disabledStations[station.id] or not deps.stationTagged(station.id) then
		return nil
	end
	return { tier = station.tier }
end

-- Rolling-hour squeeze alert (spec 2026-10-12 §12): logs once when the last hour's paid squeezes pass
-- Config.Grip.squeezeAlertPerHour, and re-arms once they are back under it.
local function recordSqueeze(player: any, session: Session)
	local minute = math.floor(deps.clock() / 60)
	session.squeezes[minute] = (session.squeezes[minute] or 0) + 1
	local sum = 0
	for m, value in session.squeezes do
		if m <= minute - ALERT_WINDOW_MINUTES then
			session.squeezes[m] = nil
		else
			sum += value
		end
	end
	local alertAbove = Config.Grip.squeezeAlertPerHour
	if sum <= alertAbove then
		session.alerted = false
	elseif not session.alerted then
		session.alerted = true
		stats.squeezeAlerts += 1
		abuseLog:warn(`user {userIdOf(player)} made {sum} paid squeezes in the last hour (alert above {alertAbove})`)
	end
end

local function coinsOf(profile: any): number
	return if type(profile) == "table" and type(profile.coins) == "number" then profile.coins else 0
end

local function gripTotalOf(profile: any): number
	local grip = if type(profile) == "table" then profile.grip else nil
	return if type(grip) == "table" and type(grip.total) == "number" then grip.total else 0
end

-- Whole points of the squeeze Coins limit left at `osNow`.
local function limitPoints(limit: Types.SqueezeLimitState, osNow: number): number
	return math.floor(SqueezeLimit.current(limit, osNow, Config.Economy.SqueezeLimit))
end

local function countRejection(reason: string?)
	local key = reason or NO_REASON
	stats.rejected[key] = (stats.rejected[key] or 0) + 1
end

-- Logs and disables the stations of a stale-lobby check.
local function applyStationProblems(problems: { StationProblem })
	local missing: { string } = {}
	for _, problem in problems do
		if problem.kind == "stale" then
			log:warn(
				`stale lobby: rebuild ({problem.id} has GripTier {tostring(problem.found)}, WorldLayout says {tostring(
					problem.expected
				)}); station disabled`
			)
			SqueezeService.disableStation(problem.id)
		elseif problem.kind == "missing" then
			table.insert(missing, problem.id)
			SqueezeService.disableStation(problem.id)
		else
			log:warn(`stale lobby: rebuild (a tagged squeeze station {problem.id} is not in WorldLayout; never used)`)
		end
	end
	if #missing == #WorldLayout.stationIds() then
		log:warn("no squeeze station in the lobby (world not built)")
	elseif #missing > 0 then
		log:warn(`stale lobby: rebuild (missing from the lobby: {table.concat(missing, ", ")}); stations disabled`)
	end
end

-- Public: pure checks (unit-tested) ------------------------------------------------------------------------------------

-- Compares every WorldLayout station with the lobby. `lookup(id)` returns (exists in the lobby, its GripTier
-- attribute); `taggedIds` lists the StationId of every tagged lobby station (optional). Returns the problems, in
-- WorldLayout order, then the unknown tagged ids. Changes nothing.
function SqueezeService.checkStations(
	lookup: (stationId: string) -> (boolean, unknown),
	taggedIds: { string }?
): { StationProblem }
	local problems: { StationProblem } = {}
	for _, id in WorldLayout.stationIds() do
		local expected = WorldLayout.stationTier(id)
		local exists, found = lookup(id)
		if not exists then
			table.insert(problems, { id = id, kind = "missing", found = nil, expected = expected })
		elseif found ~= expected then
			table.insert(problems, { id = id, kind = "stale", found = found, expected = expected })
		end
	end
	if taggedIds then
		for _, id in taggedIds do
			if WorldLayout.station(id) == nil then
				table.insert(problems, { id = id, kind = "unknown", found = nil, expected = nil })
			end
		end
	end
	return problems
end

-- Runs checkStations and fails closed on what it found: stale and missing stations are disabled (here and in
-- GripService) and every problem is logged. Returns the problems. init() calls it with the lobby WorldService indexed.
function SqueezeService.applyStationCheck(
	lookup: (stationId: string) -> (boolean, unknown),
	taggedIds: { string }?
): { StationProblem }
	local problems = SqueezeService.checkStations(lookup, taggedIds)
	applyStationProblems(problems)
	return problems
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Handles one SqueezeRequest (the NetService handler calls this after the §2.7 checks). Replies through deps.reply and
-- returns the reply, or nil when the flood guard dropped the request. The request carries nothing: the pad is found
-- from the server's own root position.
function SqueezeService.request(player: any): SqueezeResult?
	local now = deps.clock()
	local osNow = deps.unixNow()
	local serverNow = deps.serverNow()
	local session = sessionOf(player, now)

	local status = deps.statusOf(player)
	local profile = deps.profileOf(player)
	local ready = status == STATUS_READY and type(profile) == "table" and isLimitState(profile.squeezeLimit)
	local limit: Types.SqueezeLimitState = if ready then profile.squeezeLimit else { value = 0, at = osNow }

	local function reject(reason: string?, nextAt: number): SqueezeResult
		countRejection(reason)
		local rejected: SqueezeResult = {
			ok = false,
			coins = 0,
			total = coinsOf(profile),
			limit = if ready then limitPoints(limit, osNow) else 0,
			reason = reason,
			nextAt = nextAt,
			grip = 0,
			gripTotal = gripTotalOf(profile),
			doubled = false,
		}
		deps.reply(player, rejected)
		return rejected
	end

	-- Auto-clicker check (2026-10-16): first, on the arrival time; a refusal uses no token of the paid cap.
	local autoClickReason = deps.autoClick(player, now)
	if autoClickReason ~= nil then
		return reject(autoClickReason, serverNow + SqueezeRules.secondsUntilNext(session.state.bucket, now))
	end

	local position, alive = deps.rootOf(player)
	local root = if alive then position else nil
	local equipped = deps.equippedOf(player)

	local decision = SqueezeRules.decide({
		now = now,
		osNow = osNow,
		serverNow = serverNow,
		state = session.state,
		profileReady = ready,
		station = padAt(root),
		rootPosition = root,
		inMatch = deps.duelPhaseOf(player) ~= "",
		baseCoins = CapsuleMath.squeezeValue(if ready then profile.capsules else nil),
		limit = limit,
	})
	session.state = decision.state

	if decision.logFlood then
		abuseLog:warn(
			`user {userIdOf(player)} flooded {REMOTE_REQUEST}: more than {Config.Squeeze.floodLogDrops} drops in {Config.Squeeze.floodLogWindowSeconds} s`
		)
	end
	if decision.outcome == "dropped" then
		stats.dropped += 1
		return nil
	end

	if decision.outcome == "rejected" then
		return reject(decision.reason, decision.nextAt)
	end

	-- Accepted (steps 8, 8a, 9). Nothing below yields, so the in-memory change is one step. The limit and the stats
	-- go through DataService.mutate; a session that stopped taking changes since the checks above (its final save
	-- already took its snapshot) earns nothing (reading: data.notReady, the profile-not-ready code of step 2).
	local tier = decision.tier
	local committed = deps.mutate(player, function(live: any): boolean
		live.squeezeLimit = decision.limit
		local profileStats = live.stats
		if type(profileStats) == "table" and type(profileStats.squeezes) == "number" then
			profileStats.squeezes += 1
		end
		return true
	end)
	if not committed then
		return reject(REASON_NOT_READY, decision.nextAt)
	end
	local gain = GripService.addFromSqueeze(player, tier)
	local gained = if decision.coins > 0 then deps.grantCoins(player, decision.coins, COIN_REASON) else 0
	deps.markDirty(player, FIELD_STATS)
	deps.markDirty(player, FIELD_LIMIT)
	deps.setSqueezeAt(player, serverNow)
	stats.accepted += 1
	if decision.paid then
		stats.paid += 1
		recordSqueeze(player, session)
		deps.pushCapsules(player, root :: Vector3)
	end
	SqueezeService.Squeezed:fire(player, equipped, gained, tier)

	local accepted: SqueezeResult = {
		ok = true,
		coins = gained,
		total = coinsOf(deps.profileOf(player)),
		limit = limitPoints(decision.limit, osNow),
		reason = nil,
		nextAt = decision.nextAt,
		grip = gain.grip,
		gripTotal = gain.gripTotal,
		doubled = gain.doubled,
	}
	deps.reply(player, accepted)
	return accepted
end

-- Fail closed for a station that disagrees with WorldLayout (or is missing from the lobby): no squeezes here.
function SqueezeService.disableStation(stationId: string)
	disabledStations[stationId] = true
end

-- True when the stale-lobby check disabled this station.
function SqueezeService.isStationDisabled(stationId: string): boolean
	return disabledStations[stationId] == true
end

-- Counters for Studio debug hooks and logs.
function SqueezeService.counts(): { [string]: any }
	local disabled: { string } = {}
	for id in disabledStations do
		table.insert(disabled, id)
	end
	table.sort(disabled)
	return {
		accepted = stats.accepted,
		paid = stats.paid,
		dropped = stats.dropped,
		rejected = table.clone(stats.rejected),
		squeezeAlerts = stats.squeezeAlerts,
		disabledStations = disabled,
	}
end

-- Public: Studio debug (DebugHooks) -------------------------------------------------------------------------------------

-- setSqueezeLimit: the squeeze Coins limit points, clamped to [0, burst], refilling from now (L3: with the limit off
-- since spec 2026-10-11 §5 the state is dormant, so an empty one shows that every squeeze still pays).
function SqueezeService.debugSetLimit(player: any, value: unknown): (boolean, string?)
	if not debugAllowed() then
		return false, "Studio only"
	end
	if type(value) ~= "number" or value ~= value then
		return false, "value must be a number"
	end
	local state = { value = math.clamp(value, 0, Config.Economy.SqueezeLimit.burst), at = deps.unixNow() }
	local written = deps.mutate(player, function(live: any): boolean
		live.squeezeLimit = state
		return true
	end)
	if not written then
		return false, "profile not ready"
	end
	deps.markDirty(player, FIELD_LIMIT)
	return true, nil
end

-- Public: tests -----------------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function SqueezeService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Forgets every session, disabled station and counter (tests; not called by the bootstrap).
function SqueezeService.reset()
	table.clear(sessions)
	table.clear(disabledStations)
	stats = { accepted = 0, paid = 0, dropped = 0, rejected = {}, squeezeAlerts = 0 }
end

-- Lifecycle -----------------------------------------------------------------------------------------------------------

function SqueezeService.init()
	NetService.on(REMOTE_REQUEST, function(player: Player)
		SqueezeService.request(player)
	end)
	-- WorldService.init ran first (layer order): the lobby index is ready.
	local tagged: { string } = {}
	for _, instance in WorldService.stations(TAG_STATION) do
		local id = instance:GetAttribute(ATTR_STATION_ID)
		if type(id) == "string" then
			table.insert(tagged, id)
		end
	end
	SqueezeService.applyStationCheck(function(stationId: string): (boolean, unknown)
		local instance = WorldService.station(stationId)
		if instance == nil then
			return false, nil
		end
		return true, instance:GetAttribute(ATTR_GRIP_TIER)
	end, tagged)
end

function SqueezeService.playerRemoving(player: Player)
	sessions[player] = nil
end

-- Not called by the bootstrap; drops everything (leak checks).
function SqueezeService.destroy()
	SqueezeService.reset()
	SqueezeService.Squeezed:disconnectAll()
end

return SqueezeService
