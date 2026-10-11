--!strict
-- NetService (server only). DESIGN §2.3, §2.6, §2.7, §2.8, §12 #1-#3.
-- * init() creates ReplicatedStorage.SD_Remotes from Remotes.SPEC (Remotes.createServer) and wraps every client ->
--   server remote once. Services register handlers with on(name, handler) (RemoteEvents) and onInvoke(name, handler)
--   (RemoteFunctions); a handler can be registered before or after init and is looked up on every call.
-- * Every client call runs the §2.7 handler order before any game code sees it:
--     (1) player not muted -> (2) per-remote token bucket (Config.Net.Remotes) and the global cap per player
--     (Config.Net.Global, 30/s burst 80) -> (3) select("#", ...) <= maxArgs -> (4) every argument narrowed by its
--     Remotes.SPEC type through Util/Validate (typeof, finite numbers, serverTime bound, id patterns and lengths,
--     table key cap) -> seq replay check -> (5)(6) the service handler (game-state checks and the action).
--   A rate-limit hit, a wrong argument count or an invalid argument is a violation. More than
--   Config.Net.Abuse.violations violations inside windowSeconds mute that player's C->S remotes for muteSeconds and
--   log [SD][abuse] (no kicks in v1: Config.Net.kickOnAbuse = false). Muted calls are dropped without counting.
-- * Handlers receive (player, ...validated arguments) in SPEC order; the values are already narrowed (a Vector3 is
--   finite, an id matches its pattern), but handlers still do their own game-state checks and never trust amounts,
--   outcomes, origins or timers from the client (§2.7, §12 #3). A handler error is caught (xpcall) and logged with a
--   traceback; a RemoteFunction then returns error.generic. The client never sees a thrown error.
-- * RemoteFunction results are Result<T> (§2.7): an invoke handler returns NetService.ok(data) or
--   NetService.err(reason, charged?) (any other return value is wrapped as ok data); NetService fills `v` from the
--   version provider that StateService sets in Part 5 (setVersionProvider; 0 until then). A remote marked
--   oneInFlight rejects a second call while the first runs (net.rateLimited, not a violation).
-- * Reading (seq, §12 #2 "integer seq with monotonic replay rejection"): for an argument named "seq", a value that is
--   not above the last accepted seq of that player on that remote is dropped as a replay. The counter is per player
--   and per remote for the whole session (never reset by a match), so the client keeps one rising counter per remote
--   for its session. A replay is dropped silently and counted as `staleSeq`, not as a violation (an honest client
--   never sends one; counting it would let a client-side counter bug mute a player). The < lastSeq + 1000 window is
--   ThrowRules' check (§5.6 #2), not repeated here.
-- * fire / fireAll / fireMany / notify send server -> client remotes. A recipient that is not a Player in Players (the
--   Studio test dummy, a player who left) is skipped silently, so callers can pass match participants as they are.
-- * Studio: counts() feeds ServerStorage.SD_DebugServer counts() (violations, drops, mutes).
-- The pure argument checks (validateArg, validateArgs) and the per-player guard (Guard.new) are exposed for unit
-- tests; they take an injectable clock and never touch Players.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local Validate = require(Shared.Util.Validate)

-- Types

export type Handler = (player: Player, ...any) -> ()
export type InvokeHandler = (player: Player, ...any) -> any
export type Result = Types.Result<any>

-- What the guard decided for one call. Only "ok" reaches a handler.
export type Verdict = "ok" | "muted" | "rateLimited" | "badArgCount" | "invalid" | "staleSeq"

export type RateEntry = { rate: number, burst: number, oneInFlight: boolean? }
export type AbuseRules = { violations: number, windowSeconds: number, muteSeconds: number }

export type GuardDeps = {
	clock: (() -> number)?, -- default os.clock (a measurement clock: rate limits never need server time)
	spec: { [string]: Remotes.RemoteSpec }?, -- default Remotes.SPEC
	rates: { [string]: RateEntry }?, -- default Config.Net.Remotes
	global: RateEntry?, -- default Config.Net.Global
	abuse: AbuseRules?, -- default Config.Net.Abuse
	onMute: ((key: any, name: string, mutedUntil: number) -> ())?,
}

export type GuardStats = {
	calls: number,
	accepted: number,
	violations: number,
	rateLimited: number,
	badArgCount: number,
	invalid: number,
	staleSeq: number,
	mutedDrops: number,
	mutes: number,
}

type KeyState = {
	violations: { number }, -- clock times of recent violations (pruned to the window)
	total: number, -- every violation of this key this session
	mutedUntil: number,
	seq: { [string]: number }, -- remote name -> last accepted seq
}

type GuardData = {
	_clock: () -> number,
	_spec: { [string]: Remotes.RemoteSpec },
	_rates: { [string]: RateEntry },
	_abuse: AbuseRules,
	_onMute: ((key: any, name: string, mutedUntil: number) -> ())?,
	_limiters: { [string]: RateLimiter.RateLimiter },
	_global: RateLimiter.RateLimiter,
	_states: { [any]: KeyState },
	_stats: GuardStats,
}

-- Constants

local NOTIFY_REMOTE = "Notify"
local SEQ_ARG_NAME = "seq"
-- Protocol guards for the generic argument types (reading, DESIGN gives no numbers: no C->S remote sends a free string
-- in v1; SetSettings sends a table of at most 4 keys, which its handler checks exactly through Validate.settings).
local MAX_STRING_LENGTH = 64
local MAX_TABLE_KEYS = 16
-- Used only if a C->S remote has no Config.Net.Remotes entry (Config.validate() reports that as a problem).
local FALLBACK_RATE: RateEntry = table.freeze({ rate = 1, burst = 3 })

local REASON_RATE_LIMITED = "net.rateLimited"
local REASON_INVALID = "net.invalid"
local REASON_GENERIC = "error.generic"

-- Onboarding step ids the client may report (Config.Onboarding: recordedBy = "client"), plus the "Skip tutorial" id
-- (Config.Onboarding.skipStepId, Part 7 reading: PreferencesService sets onboarding.skipped instead of marking a step).
local CLIENT_STEP_IDS: { string } = {}
for _, step in Config.Onboarding.Steps do
	if step.recordedBy == "client" then
		table.insert(CLIENT_STEP_IDS, step.id)
	end
end
table.insert(CLIENT_STEP_IDS, Config.Onboarding.skipStepId)
table.freeze(CLIENT_STEP_IDS)

-- Module table

local NetService = {}

-- Private: argument validation ---------------------------------------------------------------------------------------

type Check = (value: unknown) -> (boolean, any)

local function fromNarrow(narrow: (unknown) -> any?): Check
	return function(value: unknown): (boolean, any)
		local narrowed = narrow(value)
		return narrowed ~= nil, narrowed
	end
end

local function checkBoolean(value: unknown): (boolean, any)
	return type(value) == "boolean", value
end

local function checkString(value: unknown): (boolean, any)
	local s = Validate.string(value, MAX_STRING_LENGTH)
	return s ~= nil, s
end

-- A table with at most MAX_TABLE_KEYS keys. Its shape is the handler's job (e.g. Validate.settings).
local function checkTable(value: unknown): (boolean, any)
	if type(value) ~= "table" then
		return false, nil
	end
	local count = 0
	for _ in value :: { [unknown]: unknown } do
		count += 1
		if count > MAX_TABLE_KEYS then
			return false, nil
		end
	end
	return true, value
end

local function checkStepId(value: unknown): (boolean, any)
	local s = Validate.oneOf(value, CLIENT_STEP_IDS)
	return s ~= nil, s
end

-- One check per Remotes.ArgType. reasonCode / messageCode are server -> client only, so they have no check here and
-- fail closed if a C->S remote ever declares them.
local CHECKS: { [string]: Check } = {
	integer = fromNarrow(function(v: unknown): any?
		return Validate.integer(v)
	end),
	number = fromNarrow(function(v: unknown): any?
		return Validate.number(v)
	end),
	serverTime = fromNarrow(Validate.serverTime),
	boolean = checkBoolean,
	string = checkString,
	table = checkTable,
	Vector3 = fromNarrow(Validate.vector3),
	squishyId = fromNarrow(Validate.squishyId),
	boxId = fromNarrow(Validate.boxId),
	bundleKey = fromNarrow(Validate.bundleKey),
	passKey = fromNarrow(Validate.passKey),
	requestId = fromNarrow(Validate.requestId),
	revealRequestId = fromNarrow(Validate.ackRevealId),
	questId = fromNarrow(Validate.questId),
	stepId = checkStepId,
}

-- Private: guard -------------------------------------------------------------------------------------------------------

local GuardClass = {}
GuardClass.__index = GuardClass

export type Guard = typeof(setmetatable({} :: GuardData, GuardClass))

local function newStats(): GuardStats
	return {
		calls = 0,
		accepted = 0,
		violations = 0,
		rateLimited = 0,
		badArgCount = 0,
		invalid = 0,
		staleSeq = 0,
		mutedDrops = 0,
		mutes = 0,
	}
end

local function stateOf(self: Guard, key: any): KeyState
	local state = self._states[key]
	if state == nil then
		state = { violations = {}, total = 0, mutedUntil = -math.huge, seq = {} }
		self._states[key] = state
	end
	return state
end

local function limiterFor(self: Guard, name: string): RateLimiter.RateLimiter
	local existing: RateLimiter.RateLimiter? = self._limiters[name]
	if existing then
		return existing
	end
	local entry = self._rates[name] or FALLBACK_RATE
	local limiter = RateLimiter.new(entry.rate, entry.burst, self._clock)
	self._limiters[name] = limiter
	return limiter
end

-- Records one violation; mutes the key when the window holds more than the threshold. Returns the verdict.
local function violate(self: Guard, key: any, state: KeyState, name: string, verdict: Verdict, now: number): Verdict
	local stats = self._stats
	stats.violations += 1
	if verdict == "rateLimited" then
		stats.rateLimited += 1
	elseif verdict == "badArgCount" then
		stats.badArgCount += 1
	else
		stats.invalid += 1
	end
	state.total += 1
	local list = state.violations
	table.insert(list, now)
	local cutoff = now - self._abuse.windowSeconds
	while #list > 0 and list[1] <= cutoff do
		table.remove(list, 1)
	end
	if #list > self._abuse.violations then
		state.mutedUntil = now + self._abuse.muteSeconds
		table.clear(list)
		stats.mutes += 1
		local onMute = self._onMute
		if onMute then
			onMute(key, name, state.mutedUntil)
		end
	end
	return verdict
end

-- Runs §2.7 steps 1-4 for one call of remote `name` by `key` with `n` arguments. Returns the verdict and, when it is
-- "ok", the narrowed arguments (an array of #spec.args values, in SPEC order).
function GuardClass.check(self: Guard, key: any, name: string, n: number, ...: any): (Verdict, { any }?)
	local stats = self._stats
	stats.calls += 1
	local spec = self._spec[name]
	local now = self._clock()
	local state = stateOf(self, key)

	-- (1) muted
	if now < state.mutedUntil then
		stats.mutedDrops += 1
		return "muted", nil
	end
	-- Not a client -> server remote of the contract: invalid (never happens through init's wiring).
	if spec == nil or spec.dir ~= "c2s" then
		return violate(self, key, state, name, "invalid", now), nil
	end
	-- (2) per-remote bucket, then the global cap
	if not limiterFor(self, name):take(key) or not self._global:take(key) then
		return violate(self, key, state, name, "rateLimited", now), nil
	end
	-- (3) argument count
	local maxArgs = spec.maxArgs or #spec.args
	if n > maxArgs then
		return violate(self, key, state, name, "badArgCount", now), nil
	end
	-- (4) every argument narrowed by its SPEC type
	local args = table.create(#spec.args)
	local seqValue: number? = nil
	for i, argSpec in spec.args do
		local value = if i <= n then select(i, ...) else nil
		if value == nil and argSpec.optional then
			args[i] = nil
			continue
		end
		local check = CHECKS[argSpec.type]
		local ok, narrowed = false, nil
		if check then
			ok, narrowed = check(value)
		end
		if not ok then
			return violate(self, key, state, name, "invalid", now), nil
		end
		args[i] = narrowed
		if argSpec.name == SEQ_ARG_NAME and argSpec.type == "integer" then
			seqValue = narrowed
		end
	end
	-- seq replay check (see the header reading): dropped, not a violation.
	if seqValue ~= nil then
		local last = state.seq[name]
		if last ~= nil and seqValue <= last then
			stats.staleSeq += 1
			return "staleSeq", nil
		end
		state.seq[name] = seqValue
	end
	stats.accepted += 1
	return "ok", args
end

-- Counts a violation found after the payload checks (e.g. a game-level payload rule such as ThrowRules' seq window).
function GuardClass.report(self: Guard, key: any, name: string)
	violate(self, key, stateOf(self, key), name, "invalid", self._clock())
end

-- True while the key is muted.
function GuardClass.isMuted(self: Guard, key: any): boolean
	local state = self._states[key]
	return state ~= nil and self._clock() < state.mutedUntil
end

-- Violations of this key this session.
function GuardClass.violationsOf(self: Guard, key: any): number
	local state = self._states[key]
	return if state then state.total else 0
end

-- Number of keys muted right now.
function GuardClass.mutedCount(self: Guard): number
	local now = self._clock()
	local count = 0
	for _, state in self._states do
		if now < state.mutedUntil then
			count += 1
		end
	end
	return count
end

-- Forgets everything about a key (its buckets start full again). Call on PlayerRemoving.
function GuardClass.reset(self: Guard, key: any)
	self._states[key] = nil
	for _, limiter in self._limiters do
		limiter:reset(key)
	end
	self._global:reset(key)
end

-- A copy of the counters.
function GuardClass.stats(self: Guard): GuardStats
	return table.clone(self._stats)
end

-- Private: runtime -----------------------------------------------------------------------------------------------------

local log = Log.new("Net")
local abuseLog = Log.new("abuse")

local guard: Guard? = nil
local remotes: { [string]: Instance } = {}
local eventHandlers: { [string]: Handler } = {}
local invokeHandlers: { [string]: InvokeHandler } = {}
local inFlight: { [Player]: { [string]: boolean } } = {}
local versionProvider: ((player: Player) -> number)? = nil
local warnedUnready: { [string]: boolean } = {}
local runtimeStats = { handlerErrors = 0, unhandled = 0, sent = 0, skippedRecipients = 0 }

local function traceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

local function versionOf(player: Player): number
	local provider = versionProvider
	if provider == nil then
		return 0
	end
	local ok, v = pcall(provider, player)
	if ok and type(v) == "number" then
		return v
	end
	return 0
end

-- A Player still in the game (the Studio test dummy is a table and is never a recipient).
local function isLivePlayer(player: any): boolean
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
end

local function logMute(key: any, name: string, mutedUntil: number)
	local who = if typeof(key) == "Instance" and key:IsA("Player") then key.UserId else tostring(key)
	abuseLog:warn(
		string.format(
			"user %s muted for %ds after more than %d violations in %ds (last remote %s), until",
			tostring(who),
			Config.Net.Abuse.muteSeconds,
			Config.Net.Abuse.violations,
			Config.Net.Abuse.windowSeconds,
			name
		),
		mutedUntil
	)
end

local function getGuard(): Guard
	local existing = guard
	if existing then
		return existing
	end
	local created = NetService.newGuard({ onMute = logMute })
	guard = created
	return created
end

local function errorResult(player: Player, reason: string): Result
	return { ok = false, v = versionOf(player), reason = reason }
end

-- Turns a handler's return value into a Result with `v` (never mutates the handler's table).
local function toResult(player: Player, value: any): Result
	if type(value) == "table" and type(value.ok) == "boolean" then
		if value.ok then
			return { ok = true, v = versionOf(player), data = value.data }
		end
		local reason = if type(value.reason) == "string" then value.reason else REASON_GENERIC
		local charged = if type(value.charged) == "boolean" then value.charged else nil
		return { ok = false, v = versionOf(player), reason = reason, charged = charged }
	end
	return { ok = true, v = versionOf(player), data = value }
end

local function handleEvent(name: string, argCount: number, player: Player, n: number, ...: any)
	local verdict, args = getGuard():check(player, name, n, ...)
	if verdict ~= "ok" or args == nil then
		return
	end
	local handler = eventHandlers[name]
	if handler == nil then
		runtimeStats.unhandled += 1
		return
	end
	local ok, err = xpcall(function(): any
		handler(player, table.unpack(args, 1, argCount))
		return nil
	end, traceback)
	if not ok then
		runtimeStats.handlerErrors += 1
		log:error(`handler {name} failed for user {player.UserId}:`, err)
	end
end

local function handleInvoke(
	name: string,
	argCount: number,
	oneInFlight: boolean,
	player: Player,
	n: number,
	...: any
): Result
	local verdict, args = getGuard():check(player, name, n, ...)
	if verdict == "muted" or verdict == "rateLimited" then
		return errorResult(player, REASON_RATE_LIMITED)
	elseif verdict ~= "ok" or args == nil then
		return errorResult(player, REASON_INVALID)
	end
	local handler = invokeHandlers[name]
	if handler == nil then
		runtimeStats.unhandled += 1
		return errorResult(player, REASON_GENERIC)
	end
	local running: { [string]: boolean } = inFlight[player] or {}
	if oneInFlight then
		if running[name] then
			return errorResult(player, REASON_RATE_LIMITED)
		end
		inFlight[player] = running
		running[name] = true
	end
	local ok, value = xpcall(function(): any
		return handler(player, table.unpack(args, 1, argCount))
	end, traceback)
	if oneInFlight then
		running[name] = nil
	end
	if not ok then
		runtimeStats.handlerErrors += 1
		log:error(`invoke handler {name} failed for user {player.UserId}:`, value)
		return errorResult(player, REASON_GENERIC)
	end
	return toResult(player, value)
end

-- The server -> client remote `name`, or nil before init (one warning per name).
local function s2cRemote(name: string): Instance?
	local spec = Remotes.SPEC[name]
	assert(spec ~= nil and spec.dir == "s2c", `[SD][Net] {name} is not a server -> client remote`)
	local remote: Instance? = remotes[name]
	if not remote and not warnedUnready[name] then
		warnedUnready[name] = true
		log:warn(`{name} fired before NetService.init; dropped`)
	end
	return remote
end

-- Public: pure checks (unit-tested) ------------------------------------------------------------------------------------

-- Narrows one value by a Remotes.ArgType. Returns (true, narrowed) or (false, nil). Unknown types fail closed.
function NetService.validateArg(argType: string, value: unknown): (boolean, any)
	local check = CHECKS[argType]
	if check == nil then
		return false, nil
	end
	return check(value)
end

-- Steps 3-4 for remote `name` without rate limits or seq: (true, args) or (false, reason) with reason
-- "unknownRemote", "badArgCount" or "invalid".
function NetService.validateArgs(name: string, ...: any): (boolean, any)
	local spec = Remotes.SPEC[name]
	if spec == nil or spec.dir ~= "c2s" then
		return false, "unknownRemote"
	end
	local n = select("#", ...)
	if n > (spec.maxArgs or #spec.args) then
		return false, "badArgCount"
	end
	local args = table.create(#spec.args)
	for i, argSpec in spec.args do
		local value = if i <= n then select(i, ...) else nil
		if value == nil and argSpec.optional then
			continue
		end
		local ok, narrowed = NetService.validateArg(argSpec.type, value)
		if not ok then
			return false, "invalid"
		end
		args[i] = narrowed
	end
	return true, args
end

-- A new guard (rate limits, argument checks, seq, violations and mutes) with injectable dependencies.
function NetService.newGuard(deps: GuardDeps?): Guard
	local d: GuardDeps = deps or {}
	local clock = d.clock or os.clock
	local global = d.global or Config.Net.Global
	local self: GuardData = {
		_clock = clock,
		_spec = d.spec or Remotes.SPEC,
		_rates = d.rates or Config.Net.Remotes,
		_abuse = d.abuse or Config.Net.Abuse,
		_onMute = d.onMute,
		_limiters = {},
		_global = RateLimiter.new(global.rate, global.burst, clock),
		_states = {},
		_stats = newStats(),
	}
	return setmetatable(self, GuardClass)
end

NetService.Reasons = table.freeze({
	rateLimited = REASON_RATE_LIMITED,
	invalid = REASON_INVALID,
	generic = REASON_GENERIC,
})

-- Public: results ------------------------------------------------------------------------------------------------------

-- A successful invoke result (NetService adds `v`).
function NetService.ok(data: any?): any
	return { ok = true, data = data }
end

-- A failed invoke result with a §2.10 reason code (NetService adds `v`). `charged = false` is what allows the client to
-- add "No Coins were spent".
function NetService.err(reason: string, charged: boolean?): any
	return { ok = false, reason = reason, charged = charged }
end

-- StateService (Part 5) provides the per-player state version used as Result.v. Until then v = 0.
function NetService.setVersionProvider(provider: ((player: Player) -> number)?)
	versionProvider = provider
end

-- Public: handlers -----------------------------------------------------------------------------------------------------

-- Registers the handler of a client -> server RemoteEvent (one per remote; a new one replaces the old with a warning).
-- Returns a function that removes this handler.
function NetService.on(name: string, handler: Handler): () -> ()
	local spec = Remotes.SPEC[name]
	assert(spec ~= nil and spec.dir == "c2s", `[SD][Net] {name} is not a client -> server remote`)
	assert(spec.kind == "RemoteEvent", `[SD][Net] {name} is a RemoteFunction: use onInvoke`)
	assert(type(handler) == "function", "[SD][Net] handler must be a function")
	if eventHandlers[name] ~= nil then
		log:warn(`handler for {name} replaced`)
	end
	eventHandlers[name] = handler
	return function()
		if eventHandlers[name] == handler then
			eventHandlers[name] = nil
		end
	end
end

-- Registers the handler of a client -> server RemoteFunction. The handler returns NetService.ok(data) or
-- NetService.err(reason, charged?) (or plain data). Returns a function that removes this handler.
function NetService.onInvoke(name: string, handler: InvokeHandler): () -> ()
	local spec = Remotes.SPEC[name]
	assert(spec ~= nil and spec.dir == "c2s", `[SD][Net] {name} is not a client -> server remote`)
	assert(spec.kind == "RemoteFunction", `[SD][Net] {name} is a RemoteEvent: use on`)
	assert(type(handler) == "function", "[SD][Net] handler must be a function")
	if invokeHandlers[name] ~= nil then
		log:warn(`invoke handler for {name} replaced`)
	end
	invokeHandlers[name] = handler
	return function()
		if invokeHandlers[name] == handler then
			invokeHandlers[name] = nil
		end
	end
end

-- Public: sending ------------------------------------------------------------------------------------------------------

-- Fires a server -> client remote to one player. Returns false (and sends nothing) when `player` is not a Player in the
-- game (the Studio test dummy, someone who left) or before init.
function NetService.fire(name: string, player: any, ...: any): boolean
	local remote = s2cRemote(name)
	if remote == nil then
		return false
	end
	if not isLivePlayer(player) then
		runtimeStats.skippedRecipients += 1
		return false
	end
	(remote :: RemoteEvent):FireClient(player, ...)
	runtimeStats.sent += 1
	return true
end

-- Fires a server -> client remote to every player.
function NetService.fireAll(name: string, ...: any)
	local remote = s2cRemote(name)
	if remote == nil then
		return
	end
	(remote :: RemoteEvent):FireAllClients(...)
	runtimeStats.sent += 1
end

-- Fires a server -> client remote to each listed player once (non-players and duplicates are skipped). Returns how
-- many players it reached.
function NetService.fireMany(name: string, players: { any }, ...: any): number
	local seen: { [any]: boolean } = {}
	local count = 0
	for _, player in players do
		if not seen[player] then
			seen[player] = true
			if NetService.fire(name, player, ...) then
				count += 1
			end
		end
	end
	return count
end

-- Notify(code, args?, kind) to one player (§2.8). kind defaults to "info".
function NetService.notify(player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?): boolean
	return NetService.fire(NOTIFY_REMOTE, player, code, args, kind or "info")
end

-- Notify(code, args?, kind) to every player.
function NetService.notifyAll(code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
	NetService.fireAll(NOTIFY_REMOTE, code, args, kind or "info")
end

-- Public: state --------------------------------------------------------------------------------------------------------

-- The remote instance `name` (nil before init).
function NetService.remote(name: string): Instance?
	return remotes[name]
end

-- True while the player's client -> server remotes are muted.
function NetService.isMuted(player: Player): boolean
	return getGuard():isMuted(player)
end

-- Counts one violation for the player (a payload rule a service checks itself, e.g. ThrowRules' flag `violation`);
-- it counts towards the mute like the ones NetService finds.
function NetService.reportViolation(player: Player, name: string)
	getGuard():report(player, name)
end

-- Violations of this player this session.
function NetService.violationsOf(player: Player): number
	return getGuard():violationsOf(player)
end

-- Counters for Studio debug hooks and logs.
function NetService.counts(): { [string]: number }
	local g = getGuard()
	local stats = g:stats()
	return {
		calls = stats.calls,
		accepted = stats.accepted,
		violations = stats.violations,
		rateLimited = stats.rateLimited,
		badArgCount = stats.badArgCount,
		invalid = stats.invalid,
		staleSeq = stats.staleSeq,
		mutedDrops = stats.mutedDrops,
		mutes = stats.mutes,
		mutedNow = g:mutedCount(),
		handlerErrors = runtimeStats.handlerErrors,
		unhandled = runtimeStats.unhandled,
		sent = runtimeStats.sent,
		skippedRecipients = runtimeStats.skippedRecipients,
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function NetService.init()
	getGuard()
	remotes = Remotes.createServer()
	for name, spec in Remotes.SPEC do
		if spec.dir ~= "c2s" then
			continue
		end
		local remote = remotes[name]
		local argCount = #spec.args
		if spec.kind == "RemoteFunction" then
			local entry = Config.Net.Remotes[name]
			local oneInFlight = entry ~= nil and entry.oneInFlight == true
			(remote :: RemoteFunction).OnServerInvoke = function(player: Player, ...: any): any
				return handleInvoke(name, argCount, oneInFlight, player, select("#", ...), ...)
			end
		else
			(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, ...: any)
				handleEvent(name, argCount, player, select("#", ...), ...)
			end)
		end
	end
end

function NetService.playerRemoving(player: Player)
	getGuard():reset(player)
	inFlight[player] = nil
end

return NetService
