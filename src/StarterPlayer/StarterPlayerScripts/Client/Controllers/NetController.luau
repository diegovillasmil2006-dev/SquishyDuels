--!strict
-- NetController (client only). DESIGN §2.4, §2.6, §2.7, §2.8, §12. The client side of NetService.
-- * connectAsync(timeout): waits (Remotes.waitClientAsync) until ReplicatedStorage.SD_Remotes holds every SPEC remote;
--   true once connected, false on timeout (the bootstrap then shows `error.connect` and stops).
-- * Outgoing: fire(name, ...) for C->S RemoteEvents, invokeAsync(name, ...) for C->S RemoteFunctions (returns a
--   Result, never throws), plus typed wrappers (queueJoinAsync, throwRequest, ...). Before anything is sent:
--     1. the name must be a C->S remote of that kind (a wrong call is a bug: warned once per remote, dropped);
--     2. the argument count must equal the SPEC and each argument must pass the same shape checks as the server
--        (Util/Validate: finite numbers, integers, Coin amounts, Vector3, ids) -> else dropped locally, reason
--        `net.invalid`;
--     3. the same token buckets as the server (Config.Net.Remotes + Config.Net.Global, §2.7 step 2), so an honest
--        client that mashes a button never earns an abuse violation: an empty bucket drops locally, `net.rateLimited`;
--     4. oneInFlight RemoteFunctions (BoxOpen, ShopBuy) refuse a second call while one runs (`net.rateLimited`).
--   A local refusal never reaches the server. Results always have the §2.7 shape {ok, v, data | reason}.
--   RemoteFunctions wait for the reply; when Config.Net.Client.invokeTimeoutSeconds exists (reading: not in DESIGN,
--   asked for) a call that outlives it returns `error.generic` and the late reply is dropped.
-- * Incoming: on(name, handler) for S->C events (any time, even before connecting); each handler runs in its own
--   thread (Util/Signal), so one failing handler never stops the others. Typed on* wrappers for every S->C remote.
-- * seq numbers (ThrowRequest, UltimateRequest, DashRequest, §5.6 #2): nextSeq(name) counts from 1 per remote for the
--   session.
--   Reading: one counter per remote, so a long run of throws can never push the next ultimate's seq past the
--   server's `< lastSeq + 1000` window.
-- * Studio (Config.Debug.netCallCounter): outgoing call counts per remote, callCounts() (debug hooks, leak tests).
-- The server never calls InvokeClient and there are no UnreliableRemoteEvents in v1 (§2.7).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Remotes)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local Validate = require(Shared.Util.Validate)

-- Types

export type Result = { ok: boolean, v: number, data: any?, reason: string?, charged: boolean? }
export type Connection = Signal.Connection

-- Constants

local NET = Config.Net
local GLOBAL_KEY = "*"
local REASON_INVALID = "net.invalid"
local REASON_RATE = "net.rateLimited"
local REASON_GENERIC = "error.generic"
local REASON_CONNECT = "error.connect"

-- Shape checks per Remotes.ArgType (the same narrowing the server does, §2.7 step 4).
local ARG_CHECKS: { [string]: (unknown) -> boolean } = {
	integer = function(v)
		return Validate.integer(v) ~= nil
	end,
	number = function(v)
		return Validate.number(v) ~= nil
	end,
	serverTime = function(v)
		return Validate.serverTime(v) ~= nil
	end,
	coins = function(v)
		return Validate.coins(v) ~= nil
	end,
	boolean = function(v)
		return type(v) == "boolean"
	end,
	string = function(v)
		return type(v) == "string"
	end,
	table = function(v)
		return type(v) == "table"
	end,
	Vector3 = function(v)
		return Validate.vector3(v) ~= nil
	end,
	squishyId = function(v)
		return Validate.squishyId(v) ~= nil
	end,
	boxId = function(v)
		return Validate.boxId(v) ~= nil
	end,
	bundleKey = function(v)
		return Validate.bundleKey(v) ~= nil
	end,
	passKey = function(v)
		return Validate.passKey(v) ~= nil
	end,
	requestId = function(v)
		return Validate.requestId(v) ~= nil
	end,
	revealRequestId = function(v)
		return Validate.ackRevealId(v) ~= nil
	end,
	questId = function(v)
		return Validate.questId(v) ~= nil
	end,
	stepId = function(v)
		return type(v) == "string"
	end,
	reasonCode = function(v)
		return type(v) == "string"
	end,
	messageCode = function(v)
		return type(v) == "string"
	end,
}

-- Module table

local NetController = {}

-- Private

local log = Log.new("Net")
local remotes: { [string]: Instance }? = nil
local incoming: { [string]: Signal.Signal<...any> } = {}
local inFlight: { [string]: boolean } = {}
local seqs: { [string]: number } = {}
local counts: { [string]: number } = {}
local warnedBugs: { [string]: boolean } = {}
local limiters: { [string]: RateLimiter.RateLimiter } = {}
local globalLimiter: RateLimiter.RateLimiter? = nil

local function warnOnce(key: string, ...: any)
	if not warnedBugs[key] then
		warnedBugs[key] = true
		log:warn(...)
	end
end

local function localFailure(reason: string): Result
	return { ok = false, v = 0, reason = reason }
end

local function limiterFor(name: string): RateLimiter.RateLimiter?
	local limiter = limiters[name]
	if limiter then
		return limiter
	end
	local rate = NET.Remotes[name]
	if rate == nil then
		return nil
	end
	local created = RateLimiter.new(rate.rate, rate.burst)
	limiters[name] = created
	return created
end

-- Takes one token from the remote's bucket, then one from the global bucket (§2.7 step 2 order).
local function takeTokens(name: string): boolean
	local limiter = limiterFor(name)
	if limiter and not limiter:take(name) then
		return false
	end
	local global = globalLimiter
	if global == nil then
		local created = RateLimiter.new(NET.Global.rate, NET.Global.burst)
		globalLimiter = created
		return created:take(GLOBAL_KEY)
	end
	return global:take(GLOBAL_KEY)
end

local function count(name: string)
	if Config.Debug.netCallCounter then
		counts[name] = (counts[name] or 0) + 1
	end
end

local function signalFor(name: string): Signal.Signal<...any>
	local signal = incoming[name]
	if signal == nil then
		signal = Signal.new()
		incoming[name] = signal
	end
	return signal
end

-- Checks name, kind, argument count and shapes. Returns the problem (a reason code) or nil.
local function precheck(name: string, kind: Remotes.Kind, args: { any }, n: number): string?
	local spec = Remotes.SPEC[name]
	if spec == nil or spec.dir ~= "c2s" or spec.kind ~= kind then
		warnOnce("kind:" .. name, `{name} is not a client -> server {kind}; nothing sent`)
		return REASON_INVALID
	end
	local problem = NetController.checkArgs(name, args, n)
	if problem then
		warnOnce("args:" .. name, `{name}: {problem}; nothing sent`)
		return REASON_INVALID
	end
	return nil
end

-- Public: pure helpers (unit-tested)

-- Checks a C->S call's arguments against Remotes.SPEC: count equal to the declared arguments, each of its type.
-- Returns nil when valid, else a short problem description (debug text, never shown to players).
function NetController.checkArgs(name: string, args: { any }, n: number): string?
	local spec = Remotes.SPEC[name]
	if spec == nil then
		return "unknown remote"
	end
	if n ~= #spec.args then
		return `expected {#spec.args} argument(s), got {n}`
	end
	for i, argSpec in spec.args do
		local value = args[i]
		if value == nil then
			if not argSpec.optional then
				return `argument {i} ({argSpec.name}) is missing`
			end
		else
			local check = ARG_CHECKS[argSpec.type]
			if check == nil or not check(value) then
				return `argument {i} ({argSpec.name}) is not a valid {argSpec.type}`
			end
		end
	end
	return nil
end

-- Normalizes a RemoteFunction reply into the §2.7 Result shape. Anything malformed becomes `error.generic`.
function NetController.normalizeResult(reply: unknown): Result
	if type(reply) ~= "table" then
		return localFailure(REASON_GENERIC)
	end
	local t = reply :: { [string]: any }
	local v = if type(t.v) == "number" and t.v == t.v then t.v else 0
	if t.ok == true then
		return { ok = true, v = v, data = t.data }
	elseif t.ok == false then
		local reason = if type(t.reason) == "string" and t.reason ~= "" then t.reason else REASON_GENERIC
		return { ok = false, v = v, reason = reason, charged = if type(t.charged) == "boolean" then t.charged else nil }
	end
	return localFailure(REASON_GENERIC)
end

-- Public: connection

function NetController.connectAsync(timeout: number): boolean
	if remotes ~= nil then
		return true
	end
	local found = Remotes.waitClientAsync(timeout)
	if found == nil then
		return false
	end
	remotes = found
	for name, spec in Remotes.SPEC do
		if spec.dir == "s2c" then
			local remote = found[name]
			if remote and remote:IsA("RemoteEvent") then
				local signal = signalFor(name)
				remote.OnClientEvent:Connect(function(...: any)
					signal:fire(...)
				end)
			end
		end
	end
	return true
end

function NetController.isConnected(): boolean
	return remotes ~= nil
end

-- Public: outgoing

-- Fires a C->S RemoteEvent. Returns true when it was sent.
function NetController.fire(name: string, ...: any): boolean
	local n = select("#", ...)
	local args = { ... }
	if precheck(name, "RemoteEvent", args, n) then
		return false
	end
	local found = remotes
	local remote = if found then found[name] else nil
	if remote == nil or not remote:IsA("RemoteEvent") then
		return false
	end
	if not takeTokens(name) then
		return false
	end
	count(name)
	remote:FireServer(table.unpack(args, 1, n))
	return true
end

-- Invokes a C->S RemoteFunction and returns its Result (yields; never throws).
function NetController.invokeAsync(name: string, ...: any): Result
	local n = select("#", ...)
	local args = { ... }
	local problem = precheck(name, "RemoteFunction", args, n)
	if problem then
		return localFailure(problem)
	end
	local found = remotes
	local remote = if found then found[name] else nil
	if remote == nil or not remote:IsA("RemoteFunction") then
		return localFailure(REASON_CONNECT)
	end
	local rate = NET.Remotes[name]
	local single = rate ~= nil and rate.oneInFlight == true
	if single and inFlight[name] then
		return localFailure(REASON_RATE)
	end
	if not takeTokens(name) then
		return localFailure(REASON_RATE)
	end
	count(name)
	if single then
		inFlight[name] = true
	end

	local timeout = (NET.Client :: any).invokeTimeoutSeconds
	local done = Signal.new()
	local settled = false
	local result: Result = localFailure(REASON_GENERIC)
	local function settle(value: Result)
		if settled then
			return
		end
		settled = true
		result = value
		done:fire()
	end
	task.spawn(function()
		local ok, reply = pcall(function(): any
			return (remote :: RemoteFunction):InvokeServer(table.unpack(args, 1, n))
		end)
		if single then
			inFlight[name] = nil
		end
		if ok then
			settle(NetController.normalizeResult(reply))
		else
			log:warn(`{name} failed:`, reply)
			settle(localFailure(REASON_GENERIC))
		end
	end)
	if type(timeout) == "number" and timeout > 0 then
		task.delay(timeout, function()
			if not settled then
				log:warn(`{name} timed out after {timeout} s`)
				settle(localFailure(REASON_GENERIC))
			end
		end)
	end
	if not settled then
		done:wait()
	end
	done:destroy()
	return result
end

-- The next seq number for a remote (1, 2, 3, ...; per remote, for the session).
function NetController.nextSeq(name: string): number
	local seq = (seqs[name] or 0) + 1
	seqs[name] = seq
	return seq
end

-- Typed C->S wrappers (§2.8).

function NetController.requestSnapshotAsync(): Result
	return NetController.invokeAsync("RequestSnapshot")
end

function NetController.queueJoinAsync(): Result
	return NetController.invokeAsync("QueueJoin")
end

function NetController.queueLeave(): boolean
	return NetController.fire("QueueLeave")
end

function NetController.duelForfeit(): boolean
	return NetController.fire("DuelForfeit")
end

function NetController.reportIdle(): boolean
	return NetController.fire("ReportIdle")
end

-- Sends ThrowRequest with the next seq. Returns the seq, or nil when nothing was sent.
function NetController.throwRequest(aimDir: Vector3, originHint: Vector3, clientTime: number): number?
	local seq = NetController.nextSeq("ThrowRequest")
	return if NetController.fire("ThrowRequest", seq, aimDir, originHint, clientTime) then seq else nil
end

-- Sends UltimateRequest with the next seq. Returns the seq, or nil when nothing was sent.
function NetController.ultimateRequest(aimDir: Vector3, clientTime: number): number?
	local seq = NetController.nextSeq("UltimateRequest")
	return if NetController.fire("UltimateRequest", seq, aimDir, clientTime) then seq else nil
end

-- Sends DashRequest (spec phase 5) with the next seq. Returns the seq, or nil when nothing was sent.
function NetController.dashRequest(dir: Vector3, clientTime: number): number?
	local seq = NetController.nextSeq("DashRequest")
	return if NetController.fire("DashRequest", seq, dir, clientTime) then seq else nil
end

-- Feature 1 (2026-10-11): the charge throw's start and the catch press, each the press time only. True when sent.
function NetController.chargeStart(clientTime: number): boolean
	return NetController.fire("ChargeStart", clientTime)
end

function NetController.catchRequest(clientTime: number): boolean
	return NetController.fire("CatchRequest", clientTime)
end

function NetController.equipSquishyAsync(squishyId: string): Result
	return NetController.invokeAsync("EquipSquishy", squishyId)
end

-- No argument (spec 2026-10-11 §5): the server finds the pad under the player itself.
function NetController.squeezeRequest(): boolean
	return NetController.fire("SqueezeRequest")
end

-- Public: incoming

-- Connects a handler to a S->C remote (works before connectAsync). Returns a connection with :disconnect().
function NetController.on(name: string, handler: (...any) -> ()): Connection
	local spec = Remotes.SPEC[name]
	assert(spec ~= nil and spec.dir == "s2c", `[SD][Net] {tostring(name)} is not a server -> client remote`)
	return signalFor(name):connect(handler)
end

function NetController.onStateDelta(handler: Types.StateDeltaHandler): Connection
	return NetController.on("StateDelta", handler)
end

function NetController.onNotify(handler: Types.NotifyHandler): Connection
	return NetController.on("Notify", handler)
end

function NetController.onSqueezeResult(handler: (Types.SqueezeResultPayload) -> ()): Connection
	return NetController.on("SqueezeResult", handler)
end

-- Owner updates (QueueStatusPayload) and the count-only board broadcast (QueueCountsPayload) share this remote.
function NetController.onQueueStatus(handler: (any) -> ()): Connection
	return NetController.on("QueueStatus", handler)
end

function NetController.onDuelState(handler: (Types.DuelStateView) -> ()): Connection
	return NetController.on("DuelState", handler)
end

function NetController.onThrowStarted(handler: (Types.ThrowStartedPayload) -> ()): Connection
	return NetController.on("ThrowStarted", handler)
end

function NetController.onThrowRejected(handler: Types.ThrowRejectedHandler): Connection
	return NetController.on("ThrowRejected", handler)
end

function NetController.onThrowImpact(handler: (Types.ThrowImpactPayload) -> ()): Connection
	return NetController.on("ThrowImpact", handler)
end

function NetController.onUltimateEvent(handler: (Types.UltimateEventPayload) -> ()): Connection
	return NetController.on("UltimateEvent", handler)
end

function NetController.onUltimateCharge(handler: (Types.UltimateChargePayload) -> ()): Connection
	return NetController.on("UltimateCharge", handler)
end

function NetController.onDashStarted(handler: (Types.DashStartedPayload) -> ()): Connection
	return NetController.on("DashStarted", handler)
end

function NetController.onCatchEvent(handler: (Types.CatchEventPayload) -> ()): Connection
	return NetController.on("CatchEvent", handler)
end

function NetController.onDuelResult(handler: (Types.DuelResultPayload) -> ()): Connection
	return NetController.on("DuelResult", handler)
end

-- Public: Studio counters

-- Outgoing calls per remote since boot (Studio only, Config.Debug.netCallCounter; empty otherwise).
function NetController.callCounts(): { [string]: number }
	return table.clone(counts)
end

return NetController
