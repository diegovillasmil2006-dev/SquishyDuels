--!strict
-- QueueService (server only). DESIGN §2.3, §2.8 (QueueJoin, QueueLeave, ReportIdle, QueueStatus), §5.4, §11.6, §12.
-- One 1v1 FIFO queue for this server. Ticket = {userId, player, joinedAt (server time), priority (1 = requeued at the
-- front after an opponent's bail), rating (nil: the rating hook is off, pure FIFO), lastOpponentUserId}; order is
-- priority descending, then joinedAt, then userId. Lobby stats never enter a ticket or a pairing decision (§5.4).
--
-- Entry points: the podium prompt and the HUD Duel button both call the QueueJoin remote (the podium prompt is a
-- client stand prompt: QueueController registers the SD_QueuePodium handler with WorldBinder and fires QueueJoin /
-- QueueLeave; reading of §5.4 + §7.6 "stand prompts only open UI", so the server never handles the prompt itself and
-- a press can never count twice). QueueJoin checks, in §2.8 order: a real Player (the Studio test dummy is never in
-- the real queue, §12 #21); not closing and accepting (queue.unavailable) and no restart pending (queue.paused); the
-- arena template exists (queue.unavailable); not queued and not in a match (queue.alreadyQueued); character alive
-- (queue.notReady, reading: §2.8 names no code for it; Strings has reason.queue.notReady "Wait until your character
-- has loaded, then try again."); requeue cooldown (queue.cooldown: Config.Duel.Rules
-- RequeueCooldownSeconds after any match, BailRequeueCooldownSeconds after a bail). Closing answers queue.paused
-- (Matchmaker.joinCheck); setAccepting(false) answers queue.unavailable. The equipped squishy is snapshot
-- by DuelService at Preparing. An OFFLINE/READONLY profile may join with the duel.noRewardsOffline warning (Part 5,
-- when DataService exists). Result data: {position}. An accepted join fires QueueService.Joined(player).
-- QueueLeave and ReportIdle remove a Searching ticket (Notify queue.left / queue.removedIdle); a Matched player's
-- request is ignored (§5.4 edge cases). QueueMaxSeconds removes a ticket with queue.timedOut {minutes}.
--
-- The queue rules themselves are Logic/Matchmaker's (pure): ticket order, joinCheck (the QueueJoin checks above),
-- pair, isTimedOut and cooldownUntil. Pairing runs on ticket add, on ArenaService.SlotReleased and every
-- PairIntervalSeconds: Matchmaker.pair(tickets, now, free slots), then for each pair: acquire a slot (§5.4 "pair only
-- if ArenaService.acquire() returns a slot"), hand it off (ArenaService.handoff) and call
-- DuelService.startMatch(a, b, slot). On success both players are Matched (lobby actions locked: isLocked()); on
-- failure the slot is released and both tickets stay queued (held back START_RETRY_SECONDS so a failing pair does
-- not spin).
-- Matched -> Idle: when DuelService no longer has a match for the player (DuelService.getMatch nil and the player's
-- SD_DuelPhase / SD_MatchId attributes empty, after MATCHED_GRACE_SECONDS), with the 3 s requeue cooldown.
-- DuelService.MatchEnded (read leniently by readMatchEnded): a bailer gets the 15 s cooldown; the players to requeue
-- (summary.requeueUserIds, or for a Cancelled match with a known bailer every other participant) go back in at the
-- front once their match is over, unless the server is closing, a restart is pending or summary.noRequeue is set.
--
-- QueueStatus (§2.8): the owner gets {state, position?, searching, duelsInProgress, arenasFree, joinedAt?,
-- messageKey?} on every change (messageKey: queue.noOpponent after NoOpponentHintSeconds alone, queue.waitingArena
-- when no arena is free); everyone gets the count-only {searching, duelsInProgress, arenasFree} for the podium board
-- when the counts change, at most Config.Net.Broadcast.queueStatusMaxHz (a payload without `state` is the board
-- update). duelsInProgress counts arena slots in use (Result and Returning included), the board shows it "of MaxSlots".
-- ShutdownService: RestartScheduled clears every ticket with queue.paused and pauses joins; Closing clears the queue.
-- All collaborators are reached through `deps` (useDeps in tests; init() builds the real ones), so the queue rules are
-- unit-tested without Players, remotes or DuelService.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local Services = script.Parent
local ArenaService = require(Services.ArenaService)
local CharacterService = require(Services.CharacterService)
local NetService = require(Services.NetService)
local ShutdownService = require(Services.ShutdownService)
local Matchmaker = require(Services.Parent.Logic.Matchmaker)

-- Types

export type QueueState = Types.QueueState

export type Ticket = {
	userId: number,
	player: any,
	joinedAt: number,
	priority: number,
	rating: number?,
	lastOpponentUserId: number?,
	holdUntil: number?, -- a failed start holds the ticket back until then
}

export type ArenaDeps = {
	available: () -> boolean,
	freeCount: () -> number,
	inUseCount: () -> number,
	acquire: () -> any?,
	release: (slot: any) -> (),
	handoff: (slot: any?) -> (),
}

export type DuelDeps = {
	startMatch: (a: any, b: any, slot: any) -> (any, any),
	inMatch: (player: any) -> boolean,
}

export type Deps = {
	now: () -> number, -- server time
	isPlayer: (player: any) -> boolean, -- a real Player in the game
	isAlive: (player: any) -> boolean,
	arena: ArenaDeps,
	duel: DuelDeps?, -- nil until DuelService exists: nobody is paired
	fire: (name: string, player: any, payload: any) -> (),
	fireAll: (name: string, payload: any) -> (),
	notify: (player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?) -> (),
	closing: () -> boolean,
	restartPending: () -> boolean,
	dataStatus: ((player: any) -> string?)?,
	defer: (fn: () -> ()) -> (),
	log: Logger?, -- default [SD][Queue] (tests record instead of printing)
}

-- What this module logs through.
export type Logger = {
	warn: (self: any, ...any) -> (),
	error: (self: any, ...any) -> (),
}

-- What readMatchEnded understood from a DuelService.MatchEnded call.
export type EndedInfo = {
	matchId: string?,
	outcome: string?,
	participants: { number },
	bailers: { number },
	requeue: { number },
	noRequeue: boolean,
}

type Record = {
	player: any,
	userId: number,
	state: QueueState,
	ticket: Ticket?,
	messageKey: string?,
	matchedAt: number?,
	matchId: string?,
	lastOpponentUserId: number?,
	cooldownUntil: number,
	requeueFront: boolean,
	lastStatus: string?,
}

-- Constants

local Matchmaking = Config.Duel.Matchmaking

local REMOTE_STATUS = "QueueStatus"
local ATTR_PHASE = "SD_DuelPhase"
local ATTR_MATCH_ID = "SD_MatchId"
local SECONDS_PER_MINUTE = 60
-- Reading (robustness, not in DESIGN): a Matched player is released to Idle only after this long, so a DuelService
-- that registers its match a moment after startMatch returns never frees the player early.
local MATCHED_GRACE_SECONDS = 2
-- Reading: after a failed startMatch both tickets wait this long before they are paired again.
local START_RETRY_SECONDS = 2

local NORMAL_PRIORITY = Matchmaking.NormalPriority
local REQUEUE_PRIORITY = Matchmaking.RequeuePriority

local CODE_LEFT = "queue.left"
local CODE_IDLE = "queue.removedIdle"
local CODE_TIMED_OUT = "queue.timedOut"
local CODE_PAUSED = "queue.paused"
local CODE_UNAVAILABLE = "queue.unavailable"
local CODE_NOT_READY = "queue.notReady"
local CODE_NO_OPPONENT = "queue.noOpponent"
local CODE_WAITING_ARENA = "queue.waitingArena"
local CODE_NO_REWARDS = "duel.noRewardsOffline"

-- readMatchEnded vocabulary.
local ENDED_NESTED_KEYS = { "outcome", "state", "match", "summary" }
local ENDED_TEXT_KEYS = { "kind", "outcome", "phase", "endPhase", "result" }
local ENDING_WORDS = table.freeze({
	win = true,
	loss = true,
	draw = true,
	cancelled = true,
	void = true,
	result = true,
	returning = true,
})

-- Module table

local QueueService = {}

-- Fired with (player) after every accepted QueueJoin (the ticket is in the queue). Layers above listen to it
-- (PreferencesService records the onboarding step "duel", §11.8); this module never knows who listens.
QueueService.Joined = Signal.new() :: Signal.Signal<any>

-- Private

local log: Logger = Log.new("Queue") :: any
local dynamicRequire = require :: (ModuleScript) -> any

local deps: Deps? = nil
local records: { [any]: Record } = {}
local queue: { Ticket } = {}
local accepting = true
local closed = false
local pairing = false
local pairAgain = false
local lastCompanyAt = -math.huge -- last time two or more tickets were waiting
local lastBroadcast: string? = nil
local lastBroadcastAt = -math.huge

local function getDeps(): Deps
	local d = deps
	assert(d ~= nil, "[SD][Queue] used before init")
	return d
end

local function logger(): Logger
	local d = deps
	return if d ~= nil and d.log ~= nil then d.log else log
end

local function userIdOf(ref: any): number?
	if type(ref) == "number" then
		return ref
	elseif typeof(ref) == "Instance" then
		return if ref:IsA("Player") then ref.UserId else nil
	elseif type(ref) == "table" then
		local id = ref.userId or ref.UserId
		if type(id) == "number" then
			return id
		end
		if ref.player ~= nil and ref.player ~= ref then
			return userIdOf(ref.player)
		end
	end
	return nil
end

local function attributeOf(ref: any, name: string): any
	if typeof(ref) == "Instance" then
		return ref:GetAttribute(name)
	elseif type(ref) == "table" and type(ref.GetAttribute) == "function" then
		local ok, value = pcall(ref.GetAttribute, ref, name)
		return if ok then value else nil
	end
	return nil
end

local function attributeInMatch(player: any): boolean
	local phase = attributeOf(player, ATTR_PHASE)
	local matchId = attributeOf(player, ATTR_MATCH_ID)
	return (type(phase) == "string" and phase ~= "") or (type(matchId) == "string" and matchId ~= "")
end

local function inMatch(player: any): boolean
	local duel = getDeps().duel
	if duel ~= nil then
		local ok, result = pcall(duel.inMatch, player)
		if ok and result then
			return true
		end
	end
	return attributeInMatch(player)
end

local function positionOf(ticket: Ticket): number?
	return table.find(queue, ticket)
end

local function recordByUserId(userId: number): (any, Record?)
	for player, record in records do
		if record.userId == userId then
			return player, record
		end
	end
	return nil, nil
end

local function counts(): Types.QueueCountsPayload
	local d = getDeps()
	return {
		searching = #queue,
		duelsInProgress = d.arena.inUseCount(),
		arenasFree = d.arena.freeCount(),
	}
end

local function statusOf(record: Record): Types.QueueStatusPayload
	local c = counts()
	local payload: Types.QueueStatusPayload = {
		state = record.state,
		searching = c.searching,
		duelsInProgress = c.duelsInProgress,
		arenasFree = c.arenasFree,
	}
	local ticket = record.ticket
	if record.state == "Searching" and ticket ~= nil then
		payload.position = positionOf(ticket)
		payload.joinedAt = ticket.joinedAt
		payload.messageKey = record.messageKey
	end
	return payload
end

-- Sends the owner status when it changed (or always with force).
local function sendStatus(record: Record, force: boolean)
	local payload = statusOf(record)
	local fingerprint = table.concat({
		payload.state,
		tostring(payload.position),
		tostring(payload.searching),
		tostring(payload.duelsInProgress),
		tostring(payload.arenasFree),
		tostring(payload.joinedAt),
		tostring(payload.messageKey),
	}, "|")
	if force or fingerprint ~= record.lastStatus then
		record.lastStatus = fingerprint
		getDeps().fire(REMOTE_STATUS, record.player, payload)
	end
end

local function sendSearchingStatuses()
	for _, ticket in queue do
		local record = records[ticket.player]
		if record then
			sendStatus(record, false)
		end
	end
end

local function broadcastCounts(now: number, force: boolean)
	local c = counts()
	local fingerprint = `{c.searching}|{c.duelsInProgress}|{c.arenasFree}`
	local minInterval = 1 / Config.Net.Broadcast.queueStatusMaxHz
	if (force or fingerprint ~= lastBroadcast) and now - lastBroadcastAt >= minInterval then
		lastBroadcast = fingerprint
		lastBroadcastAt = now
		getDeps().fireAll(REMOTE_STATUS, c)
	end
end

local function removeTicket(player: any): boolean
	for index, ticket in queue do
		if ticket.player == player then
			table.remove(queue, index)
			return true
		end
	end
	return false
end

local function addTicket(record: Record, priority: number, now: number): Ticket
	local ticket: Ticket = {
		userId = record.userId,
		player = record.player,
		joinedAt = now,
		priority = priority,
		rating = nil, -- rating hook (§5.4): none in v1, pure FIFO
		lastOpponentUserId = record.lastOpponentUserId,
		holdUntil = nil,
	}
	removeTicket(record.player)
	table.insert(queue, ticket)
	queue = Matchmaker.order(queue :: any) :: any -- priority desc, joinedAt, userId (§5.4)
	record.state = "Searching"
	record.ticket = ticket
	record.messageKey = nil
	return ticket
end

-- Removes a Searching ticket, notifies with `code` (when given) and sends the Idle status. False when not Searching.
local function dropTicket(record: Record, code: string?, args: Types.NotifyArgs?, kind: Types.NotifyKind?): boolean
	if record.state ~= "Searching" then
		return false
	end
	removeTicket(record.player)
	record.state = "Idle"
	record.ticket = nil
	record.messageKey = nil
	local d = getDeps()
	if code ~= nil then
		d.notify(record.player, code, args, kind)
	end
	sendStatus(record, true)
	sendSearchingStatuses()
	return true
end

local function dropAll(code: string?, kind: Types.NotifyKind?)
	for _, ticket in table.clone(queue) do
		local record = records[ticket.player]
		if record then
			dropTicket(record, code, nil, kind)
		else
			removeTicket(ticket.player)
		end
	end
end

-- Why `record` may not enter the queue now (nil = it may): setAccepting(false), then Matchmaker.joinCheck (§2.8
-- order). `checkAlive` and `checkCooldown` are off for a requeue at the front. Matchmaker answers queue.unavailable
-- for a missing live character too; that one case becomes queue.notReady (see the header reading).
local function refusal(record: Record, now: number, checkAlive: boolean, checkCooldown: boolean): string?
	local d = getDeps()
	if not accepting then
		return CODE_UNAVAILABLE
	end
	local info: Matchmaker.JoinInfo = {
		closing = closed or d.closing(),
		paused = d.restartPending(),
		arenaAvailable = d.arena.available(),
		isTestDummy = not d.isPlayer(record.player),
		queued = record.state ~= "Idle",
		inMatch = inMatch(record.player),
		alive = (not checkAlive) or d.isAlive(record.player),
		cooldownUntil = if checkCooldown then record.cooldownUntil else nil,
	}
	local ok, why = Matchmaker.joinCheck(info, now)
	if ok then
		return nil
	end
	if why == CODE_UNAVAILABLE and info.arenaAvailable and not info.isTestDummy and not info.alive then
		return CODE_NOT_READY
	end
	return why or CODE_UNAVAILABLE
end

local function markMatched(player: any, opponent: any, match: any, now: number)
	local record = records[player]
	if record == nil then
		return -- the Studio test dummy has no record
	end
	removeTicket(player)
	record.state = "Matched"
	record.ticket = nil
	record.messageKey = nil
	record.matchedAt = now
	record.matchId = if type(match) == "table" and type(match.matchId) == "string"
		then match.matchId
		elseif type(match) == "string" then match
		else nil
	record.lastOpponentUserId = userIdOf(opponent)
	record.requeueFront = false
	sendStatus(record, true)
end

-- Acquires a slot, hands it off and asks DuelService to start. Returns (true, match) or (false, why).
local function startMatchWith(a: any, b: any): (boolean, any)
	local d = getDeps()
	local duel = d.duel
	if duel == nil then
		return false, "noDuelService"
	end
	local slot = d.arena.acquire()
	if slot == nil then
		return false, "noArena"
	end
	d.arena.handoff(slot)
	local ok, match, why = pcall(duel.startMatch, a, b, slot)
	d.arena.handoff(nil)
	if not ok then
		logger():error("DuelService startMatch failed:", match)
		d.arena.release(slot)
		return false, "error"
	end
	if match == nil or match == false then
		d.arena.release(slot)
		return false, why or "refused"
	end
	return true, match
end

local function pairOnce(): number
	local d = getDeps()
	if #queue < 2 or d.duel == nil or closed or not accepting or d.closing() or d.restartPending() then
		return 0
	end
	local now = d.now()
	local entries: { Ticket } = {}
	for _, ticket in queue do
		if ticket.holdUntil == nil or now >= ticket.holdUntil then
			table.insert(entries, ticket)
		end
	end
	if #entries < 2 then
		return 0
	end
	local started = 0
	for _, pair in Matchmaker.pair(entries :: any, now, d.arena.freeCount()) do
		if d.arena.freeCount() <= 0 then
			break
		end
		local a: Ticket, b: Ticket = pair.a :: any, pair.b :: any
		-- Both must still be waiting (an earlier start in this loop may have yielded).
		if positionOf(a) ~= nil and positionOf(b) ~= nil then
			local ok, match = startMatchWith(a.player, b.player)
			if ok then
				markMatched(a.player, b.player, match, now)
				markMatched(b.player, a.player, match, now)
				started += 1
			else
				logger():warn(`could not start a match for users {a.userId} and {b.userId}: {tostring(match)}`)
				a.holdUntil = now + START_RETRY_SECONDS
				b.holdUntil = now + START_RETRY_SECONDS
			end
		end
	end
	if started > 0 then
		sendSearchingStatuses()
	end
	return started
end

-- Matched -> Idle once the match is over, with the requeue cooldown (or straight back to the front when requeued).
local function reconcile(now: number)
	for player, record in records do
		if
			record.state == "Matched"
			and now - (record.matchedAt or now) >= MATCHED_GRACE_SECONDS
			and not inMatch(player)
		then
			record.state = "Idle"
			record.matchedAt = nil
			record.matchId = nil
			record.cooldownUntil = math.max(record.cooldownUntil, Matchmaker.cooldownUntil(now, false))
			if record.requeueFront then
				record.requeueFront = false
				if refusal(record, now, false, false) == nil then
					addTicket(record, REQUEUE_PRIORITY, now)
				end
			end
			sendStatus(record, true)
		end
	end
end

local function expireTickets(now: number)
	local minutes = Matchmaking.QueueMaxSeconds / SECONDS_PER_MINUTE
	for _, ticket in table.clone(queue) do
		if Matchmaker.isTimedOut(ticket :: any, now) then
			local record = records[ticket.player]
			if record then
				local args: Types.NotifyArgs = { minutes = minutes }
				dropTicket(record, CODE_TIMED_OUT, args, "warn")
			else
				removeTicket(ticket.player)
			end
		end
	end
end

local function updateHints(now: number)
	if #queue >= 2 then
		lastCompanyAt = now
	end
	local free = getDeps().arena.freeCount()
	for _, ticket in queue do
		local record = records[ticket.player]
		if record then
			local key: string? = nil
			if #queue == 1 then
				local aloneSince = math.max(ticket.joinedAt, lastCompanyAt)
				if now - aloneSince >= Matchmaking.NoOpponentHintSeconds then
					key = CODE_NO_OPPONENT
				end
			elseif free <= 0 then
				key = CODE_WAITING_ARENA
			end
			record.messageKey = key
		end
	end
end

local function onClosing()
	closed = true
	dropAll(nil, nil)
end

local function onRestartScheduled()
	dropAll(CODE_PAUSED, "warn")
end

local function connectSignal(signal: any, handler: (...any) -> ()): boolean
	if type(signal) ~= "table" then
		return false
	end
	if type(signal.connect) == "function" then
		signal:connect(handler)
		return true
	elseif type(signal.Connect) == "function" then
		signal:Connect(handler)
		return true
	end
	return false
end

local function optionalModule(folder: Instance?, name: string): any
	local module = if folder then folder:FindFirstChild(name) else nil
	if module ~= nil and module:IsA("ModuleScript") then
		return dynamicRequire(module)
	end
	return nil
end

local function duelDeps(DuelService: any): DuelDeps?
	if type(DuelService) ~= "table" or type(DuelService.startMatch) ~= "function" then
		return nil
	end
	return {
		startMatch = function(a: any, b: any, slot: any): (any, any)
			return DuelService.startMatch(a, b, slot)
		end,
		inMatch = function(player: any): boolean
			if type(DuelService.getMatch) == "function" then
				local match = DuelService.getMatch(player)
				return match ~= nil and match ~= false
			end
			return false
		end,
	}
end

local function dataStatusOf(DataService: any): ((player: any) -> string?)?
	if type(DataService) ~= "table" or type(DataService.getStatus) ~= "function" then
		return nil
	end
	return function(player: any): string?
		local ok, status = pcall(DataService.getStatus, player)
		if not ok then
			return nil
		end
		if type(status) == "table" then
			status = status.status
		end
		return if type(status) == "string" then status else nil
	end
end

local function defaultDeps(): Deps
	local DuelService = optionalModule(Services, "DuelService")
	return {
		now = function(): number
			return Workspace:GetServerTimeNow()
		end,
		isPlayer = function(player: any): boolean
			return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
		end,
		isAlive = function(player: any): boolean
			return CharacterService.isAlive(player)
		end,
		arena = {
			available = ArenaService.available,
			freeCount = ArenaService.freeCount,
			inUseCount = ArenaService.inUseCount,
			acquire = function(): any?
				return ArenaService.acquire()
			end,
			release = function(slot: any)
				ArenaService.release(slot)
			end,
			handoff = function(slot: any?)
				ArenaService.handoff(slot)
			end,
		},
		duel = duelDeps(DuelService),
		fire = function(name: string, player: any, payload: any)
			NetService.fire(name, player, payload)
		end,
		fireAll = function(name: string, payload: any)
			NetService.fireAll(name, payload)
		end,
		notify = function(player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
			NetService.notify(player, code, args, kind)
		end,
		closing = ShutdownService.isClosing,
		restartPending = ShutdownService.isRestartPending,
		dataStatus = dataStatusOf(optionalModule(Services, "DataService")),
		defer = function(fn: () -> ())
			task.defer(fn)
		end,
	}
end

-- Public: pure helpers (unit-tested) -----------------------------------------------------------------------------------

-- Reads a DuelService.MatchEnded call leniently (the signal's payload is DuelService's to define). Every table argument
-- is searched, together with its nested `outcome`, `state`, `match` and `summary` tables (two levels), for: matchId;
-- the ending (an `outcome` / `kind` / `phase` / `endPhase` / `result` text such as "cancelled", "Cancelled", "void",
-- "win"); participants / players (Players, records with .player / .userId, userIds, or a DuelRules side-keyed
-- {A = participant, B = participant} table, which also gives the side -> userId map); the bailer (bailerUserId, bailer,
-- bailedUserId, forfeiterUserId, leaverUserId or a bailers list; a side "A" / "B" is mapped through the participants);
-- the players to requeue (requeueUserIds or requeue, same forms); noRequeue. A cancelled match with a known bailer and
-- no requeue list requeues every other participant (§5.2 rule 5).
function QueueService.readMatchEnded(...: any): EndedInfo
	local tables: { { [any]: any } } = {}
	local seen: { [any]: boolean } = {}
	local function collect(value: any, depth: number)
		if type(value) ~= "table" or seen[value] or depth > 2 then
			return
		end
		seen[value] = true
		table.insert(tables, value)
		for _, key in ENDED_NESTED_KEYS do
			collect(value[key], depth + 1)
		end
	end
	for i = 1, select("#", ...) do
		collect((select(i, ...)), 0)
	end
	local function pick(names: { string }): any
		for _, t in tables do
			for _, name in names do
				local value = t[name]
				if value ~= nil then
					return value
				end
			end
		end
		return nil
	end

	-- Side -> userId from side-keyed participant tables (DuelRules MatchState) or records carrying .side.
	local sideToUserId: { [string]: number } = {}
	for _, t in tables do
		local parts = t.participants
		if type(parts) == "table" then
			for key, part in parts do
				if type(part) == "table" then
					local id = userIdOf(part)
					local side = if key == "A" or key == "B" then key else part.side
					if id ~= nil and (side == "A" or side == "B") then
						sideToUserId[side] = id
					end
				end
			end
		end
	end
	local function idOf(ref: any): number?
		if ref == "A" or ref == "B" then
			return sideToUserId[ref]
		end
		return userIdOf(ref)
	end
	local function idList(value: any): { number }
		local out: { number } = {}
		if value == nil then
			return out
		end
		local single = idOf(value)
		if single ~= nil then
			table.insert(out, single)
			return out
		end
		if type(value) == "table" then
			for _, item in value do
				local id = idOf(item)
				if id ~= nil and not table.find(out, id) then
					table.insert(out, id)
				end
			end
		end
		return out
	end
	local function addAll(into: { number }, from: { number })
		for _, id in from do
			if not table.find(into, id) then
				table.insert(into, id)
			end
		end
	end

	-- The ending: the first known ending word among the text fields (an Effect's own kind "ended" is skipped).
	local outcomeText: string? = nil
	for _, t in tables do
		for _, name in ENDED_TEXT_KEYS do
			local value = t[name]
			if type(value) == "string" and ENDING_WORDS[string.lower(value)] then
				outcomeText = value
				break
			end
		end
		if outcomeText ~= nil then
			break
		end
	end

	local matchId = pick({ "matchId" })
	local participants = idList(pick({ "participants", "players" }))
	addAll(participants, idList({ pick({ "a" }), pick({ "b" }) }))
	local bailers = idList(pick({ "bailers" }))
	addAll(bailers, idList(pick({ "bailerUserId", "bailer", "bailedUserId", "forfeiterUserId", "leaverUserId" })))
	local requeue = idList(pick({ "requeueUserIds", "requeue" }))
	local noRequeue = pick({ "noRequeue" }) == true
	if
		#requeue == 0
		and not noRequeue
		and #bailers > 0
		and outcomeText ~= nil
		and string.lower(outcomeText) == "cancelled"
	then
		for _, id in participants do
			if not table.find(bailers, id) then
				table.insert(requeue, id)
			end
		end
	end
	return {
		matchId = if type(matchId) == "string" then matchId else nil,
		outcome = outcomeText,
		participants = participants,
		bailers = bailers,
		requeue = requeue,
		noRequeue = noRequeue,
	}
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Uses these collaborators and clears every queue state (init() passes the real ones; tests pass fakes).
function QueueService.useDeps(newDeps: Deps)
	deps = newDeps
	records = {}
	queue = {}
	accepting = true
	closed = false
	pairing = false
	pairAgain = false
	lastCompanyAt = -math.huge
	lastBroadcast = nil
	lastBroadcastAt = -math.huge
end

-- QueueJoin (§2.8): a Result-shaped table {ok = true, data = {position}} or {ok = false, reason}.
function QueueService.join(player: any): { [string]: any }
	local d = getDeps()
	local record = records[player]
	if record == nil then
		return { ok = false, reason = CODE_UNAVAILABLE }
	end
	local now = d.now()
	local why = refusal(record, now, true, true)
	if why ~= nil then
		return { ok = false, reason = why }
	end
	local ticket = addTicket(record, NORMAL_PRIORITY, now)
	local status = if d.dataStatus then d.dataStatus(player) else nil
	if status == "offline" or status == "readonly" then
		d.notify(player, CODE_NO_REWARDS, nil, "warn")
	end
	local position = positionOf(ticket) or #queue
	sendStatus(record, true)
	sendSearchingStatuses()
	d.defer(QueueService.pairNow)
	QueueService.Joined:fire(player)
	return { ok = true, data = { position = position } }
end

-- QueueLeave (§2.8): removes a Searching ticket (queue.left by default). Matched or Idle: ignored. Returns true when a
-- ticket was removed.
function QueueService.leave(player: any, code: string?): boolean
	local record = records[player]
	if record == nil then
		return false
	end
	return dropTicket(record, code or CODE_LEFT, nil, "info")
end

-- ReportIdle (§2.8): a Searching ticket is removed with queue.removedIdle.
function QueueService.reportIdle(player: any): boolean
	local record = records[player]
	if record == nil then
		return false
	end
	return dropTicket(record, CODE_IDLE, nil, "warn")
end

-- DuelService.MatchEnded handler (connected in init; public so an integration can feed it a summary directly): the
-- bailer gets BailRequeueCooldownSeconds; the players to requeue go back in at the front when their match is over
-- (or at once when they are already Idle), unless noRequeue, closing or a pending restart.
function QueueService.handleMatchEnded(...: any)
	local d = getDeps()
	local info = QueueService.readMatchEnded(...)
	local now = d.now()
	for _, userId in info.bailers do
		local _, record = recordByUserId(userId)
		if record then
			record.cooldownUntil = math.max(record.cooldownUntil, Matchmaker.cooldownUntil(now, true))
			record.requeueFront = false
		end
	end
	if info.noRequeue or closed or d.closing() or d.restartPending() then
		return
	end
	for _, userId in info.requeue do
		local _, record = recordByUserId(userId)
		if record and not table.find(info.bailers, userId) then
			if record.state == "Matched" then
				record.requeueFront = true -- goes back in when the match is over (reconcile)
			elseif record.state == "Idle" and refusal(record, now, false, false) == nil then
				addTicket(record, REQUEUE_PRIORITY, now)
				sendStatus(record, true)
			end
		end
	end
end

-- Opens or closes the queue (§2.3). Closing it removes every ticket with queue.unavailable.
function QueueService.setAccepting(on: boolean)
	accepting = on
	if not on then
		dropAll(CODE_UNAVAILABLE, "warn")
	end
end

-- Puts a player back in at the front (priority 1), skipping the cooldown. False when it may not enter now.
function QueueService.requeueFront(player: any): boolean
	local record = records[player]
	if record == nil then
		return false
	end
	local now = getDeps().now()
	if refusal(record, now, false, false) ~= nil then
		return false
	end
	addTicket(record, REQUEUE_PRIORITY, now)
	sendStatus(record, true)
	sendSearchingStatuses()
	getDeps().defer(QueueService.pairNow)
	return true
end

-- Raises the player's requeue cooldown to at least now + seconds.
function QueueService.setCooldown(player: any, seconds: number)
	local record = records[player]
	if record then
		record.cooldownUntil = math.max(record.cooldownUntil, getDeps().now() + seconds)
	end
end

-- Studio only (DebugHooks / TestHarness, §12 #21): starts a match between `a` and `b` outside the queue (b may be the
-- test dummy, which is never queued). Removes a's ticket first. Returns (ok, match or why); (false, "studioOnly") on a
-- live server.
function QueueService.forceMatch(a: any, b: any): (boolean, any)
	if not RunService:IsStudio() then
		return false, "studioOnly"
	end
	local recordA = records[a]
	if (recordA and recordA.state == "Matched") or inMatch(a) or inMatch(b) then
		return false, "alreadyInMatch"
	end
	if recordA and recordA.state == "Searching" then
		dropTicket(recordA, nil, nil, nil)
	end
	local recordB = records[b]
	if recordB and recordB.state == "Searching" then
		dropTicket(recordB, nil, nil, nil)
	end
	local ok, match = startMatchWith(a, b)
	if ok then
		local now = getDeps().now()
		markMatched(a, b, match, now)
		markMatched(b, a, match, now)
	end
	return ok, match
end

-- Pairs waiting tickets now (re-entrant calls while a start is running are folded into one more pass). Returns how
-- many matches started.
function QueueService.pairNow(): number
	if pairing then
		pairAgain = true
		return 0
	end
	pairing = true
	local started = 0
	repeat
		pairAgain = false
		local ok, result = pcall(pairOnce)
		if ok then
			started += result
		else
			logger():error("pairing failed:", result)
		end
	until not pairAgain
	pairing = false
	return started
end

-- One queue step (every PairIntervalSeconds): finished matches, time-outs, pairing, hints, statuses, board.
function QueueService.tick()
	local d = getDeps()
	local now = d.now()
	reconcile(now)
	expireTickets(now)
	QueueService.pairNow()
	updateHints(now)
	sendSearchingStatuses()
	broadcastCounts(now, false)
end

-- "Idle", "Searching" or "Matched".
function QueueService.state(player: any): QueueState
	local record = records[player]
	return if record then record.state else "Idle"
end

-- 1-based queue position while Searching, else nil.
function QueueService.position(player: any): number?
	local record = records[player]
	local ticket = if record then record.ticket else nil
	return if ticket then positionOf(ticket) else nil
end

-- Tickets waiting.
function QueueService.searchingCount(): number
	return #queue
end

-- True from Matched through Returning: lobby actions (equip, Inspect, boxes, shop, squeeze) are locked (§5.4).
function QueueService.isLocked(player: any): boolean
	local record = records[player]
	return (record ~= nil and record.state == "Matched") or inMatch(player)
end

-- The count-only board payload.
function QueueService.counts(): Types.QueueCountsPayload
	return counts()
end

-- Studio debug view.
function QueueService.debugState(): { [string]: any }
	local tickets = {}
	for index, ticket in queue do
		table.insert(tickets, {
			position = index,
			userId = ticket.userId,
			priority = ticket.priority,
			waited = getDeps().now() - ticket.joinedAt,
		})
	end
	local matched = {}
	for _, record in records do
		if record.state == "Matched" then
			table.insert(matched, { userId = record.userId, matchId = record.matchId })
		end
	end
	return { accepting = accepting and not closed, tickets = tickets, matched = matched }
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function QueueService.init()
	QueueService.useDeps(defaultDeps())
	NetService.onInvoke("QueueJoin", function(player: Player): any
		return QueueService.join(player)
	end)
	NetService.on("QueueLeave", function(player: Player)
		QueueService.leave(player)
	end)
	NetService.on("ReportIdle", function(player: Player)
		QueueService.reportIdle(player)
	end)
	ShutdownService.Closing:connect(onClosing)
	ShutdownService.RestartScheduled:connect(onRestartScheduled)
	ArenaService.SlotReleased:connect(function()
		getDeps().defer(QueueService.pairNow)
	end)
	local DuelService = optionalModule(Services, "DuelService")
	if DuelService == nil then
		log:warn("DuelService missing: players can queue but no match starts")
	elseif not connectSignal(DuelService.MatchEnded, QueueService.handleMatchEnded) then
		log:warn("DuelService.MatchEnded missing: bail cooldowns and front requeues are off")
	end
end

function QueueService.start()
	local interval = Matchmaking.PairIntervalSeconds
	while true do
		task.wait(interval)
		local ok, err = pcall(function(): any
			QueueService.tick()
			return nil
		end)
		if not ok then
			log:error("tick failed:", err)
		end
	end
end

function QueueService.playerAdded(player: Player)
	if records[player] ~= nil then
		return
	end
	records[player] = {
		player = player,
		userId = player.UserId,
		state = "Idle",
		ticket = nil,
		messageKey = nil,
		matchedAt = nil,
		matchId = nil,
		lastOpponentUserId = nil,
		cooldownUntil = -math.huge,
		requeueFront = false,
		lastStatus = nil,
	}
	getDeps().fire(REMOTE_STATUS, player, counts()) -- the podium board for the newcomer
end

function QueueService.playerRemoving(player: Player)
	local record = records[player]
	if record == nil then
		return
	end
	records[player] = nil
	if removeTicket(player) then
		sendSearchingStatuses()
	end
end

return QueueService
