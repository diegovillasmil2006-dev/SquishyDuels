--!strict
-- GlobalQueueService (server only). One queue per mode shared by every lobby server (owner 2026-11-01: "every time you
-- hit queue, it pairs you with people playing the game across all of the servers"; LihFolk "Matchmaking Queues with
-- MemoryStore"). On in live lobby servers only (MatchServerService.canSend: Config.Match.Servers on, not Studio, not a
-- match server); off, the 1v1 and match queues pair inside this server as before.
-- * QueueService (1v1) and MatchService (Team / Free for All) keep their own tickets (screens, locks, toasts) and also
--   call enqueue(player, mode) and forget(player). The shared ticket is one key per player (user id) in the sorted map
--   SD_Q_<mode>: {s = "w" waiting | "c" claimed | "x" cancelled, h = home JobId, at = os.time(), m = match id, ct =
--   claim time}.
-- * One leader at a time (a lease in SD_Lease, renewed every LEASE_RENEW s, taken over TTL after a crash) reads every
--   mode each CYCLE s. Logic/GlobalMatch picks the groups; each ticket is claimed with a compare-and-set (only "w"); a
--   failed claim puts the group's others back. A full claim gets one reserved server id (GUID) written for each home
--   server in SD_Assign[home], then the tickets go. A claim older than CLAIM_STUCK (a leader that crashed in between)
--   goes back to waiting.
-- * A lobby with players in the shared queue reads its SD_Assign key every POLL s: its players still waiting for that
--   mode leave their own queue quietly and go to the match's server (MatchServerService.sendTo, no map: the match
--   server plays MATCH FOUND, the map vote and the bots).
-- * cancel(player) (yields): true when the player is out of the shared queue, false when a match claimed them first
--   (QueueService's practice bot asks before it starts).
-- * Coming back from a match server with Play Again / Queue Again (TeleportData.requeue, MatchServerService.goHome)
--   joins that queue again once the character is here.

-- Services

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)
local Log = require(ReplicatedStorage.Shared.Util.Log)
local GlobalMatch = require(script.Parent.Parent.Logic.GlobalMatch)
local MatchServerService = require(script.Parent.MatchServerService)
local NetService = require(script.Parent.NetService)

-- Constants

local POLL = 1 -- seconds between this lobby's reads of its assignments (and the loop's step)
local CYCLE = 2 -- seconds between the leader's matching rounds
local LEASE_TTL = 15
local LEASE_RENEW = 5
-- shortcut: a crashed lobby's tickets linger this long (a match server then waits waitSeconds for them); refresh live
-- tickets if that shows up.
local TICKET_TTL = 300
local CANCEL_TTL = 30
local ASSIGN_TTL = 60
local CLAIM_STUCK = 20
local LISTEN_AFTER_CLAIM = 30 -- a cancel that found a claim keeps reading assignments this long
local REQUEUE_DELAY = 3 -- after the character appears (the profile and the lobby first)
local CODE_JOIN_FAILED = "match.joinFailed"

-- Module table

local GlobalQueueService = {}

-- Private

local log = Log.new("GlobalQueue")
local prefix = "SD_"
local mine: { [Player]: string } = {} -- this server's players in the shared queue, by mode
local handled: { [string]: number } = {} -- "<match id>:<user id>" -> os.clock() it was handled
local listenUntil = 0

local function sizes(): { [string]: number }
	local out: { [string]: number } = { ["1v1"] = 2 }
	for id: any, mode: any in Config.Match.Modes do
		out[id] = mode.maxPlayers
	end
	return out
end

local function queueOf(mode: string): MemoryStoreSortedMap
	return MemoryStoreService:GetSortedMap(`{prefix}Q_{mode}`)
end

local function assignments(): MemoryStoreHashMap
	return MemoryStoreService:GetHashMap(`{prefix}Assign`)
end

-- QueueService and MatchService require this module, so they are reached lazily.
local function queues(): (any, any)
	return require(script.Parent.QueueService) :: any, require(script.Parent.MatchService) :: any
end

local function stillWaiting(player: Player, mode: string): boolean
	local QueueService, MatchService = queues()
	if mode == "1v1" then
		return QueueService.state(player) == "Searching"
	end
	return MatchService.queued(player) == mode
end

local function handOff(player: Player, mode: string)
	local QueueService, MatchService = queues()
	if mode == "1v1" then
		QueueService.handOff(player)
	else
		MatchService.handOff(player)
	end
end

-- Lobby side: this server's players of the assignments go to their match's server.
local function deliver(entries: unknown)
	if type(entries) ~= "table" then
		return
	end
	local trips: { [string]: { entry: any, players: { Player } } } = {}
	for _, entry in entries :: { any } do
		local key = `{entry.m}:{entry.u}`
		if handled[key] == nil then
			handled[key] = os.clock()
			local player = Players:GetPlayerByUserId(entry.u)
			if player and stillWaiting(player, entry.mode) then
				mine[player] = nil
				handOff(player, entry.mode)
				local trip = trips[entry.m] or { entry = entry, players = {} }
				table.insert(trip.players, player)
				trips[entry.m] = trip
			end
		end
	end
	for matchId, trip in trips do
		task.spawn(function()
			local e = trip.entry
			if not MatchServerService.sendTo(e.sid, e.mode, matchId, e.all, trip.players) then
				for _, player in trip.players do
					NetService.notify(player, CODE_JOIN_FAILED, nil, "warn")
				end
			end
		end)
	end
end

local function poll()
	local now = os.clock()
	for key, at in handled do
		if now - at > ASSIGN_TTL * 2 then
			handled[key] = nil
		end
	end
	local ok, entries = pcall(function(): any
		return assignments():GetAsync(game.JobId)
	end)
	if ok then
		deliver(entries)
	else
		log:warn("reading the assignments failed:", entries)
	end
end

-- Leader side ----------------------------------------------------------------------------------------------------------

local function holdLease(): boolean
	local me = game.JobId
	local ok, result = pcall(function(): any
		return MemoryStoreService:GetHashMap(`{prefix}Lease`):UpdateAsync("leader", function(old: any): any
			if old == nil or old == me then
				return me
			end
			return nil
		end, LEASE_TTL)
	end)
	return ok and result == me
end

-- Claims every ticket of `group` for `matchId` (only waiting ones); on any failure the claimed ones go back.
local function claim(map: MemoryStoreSortedMap, group: { GlobalMatch.Ticket }, matchId: string, now: number): boolean
	local done: { GlobalMatch.Ticket } = {}
	for _, ticket in group do
		local ok, result = pcall(function(): any
			return (map:UpdateAsync(tostring(ticket.u), function(old: any): any
				if type(old) == "table" and old.s == "w" then
					return { s = "c", h = old.h, at = old.at, m = matchId, ct = now }
				end
				return nil
			end, TICKET_TTL))
		end)
		if not (ok and result) then
			for _, back in done do
				pcall(function()
					map:UpdateAsync(tostring(back.u), function(old: any): any
						if type(old) == "table" and old.m == matchId then
							return { s = "w", h = old.h, at = old.at }
						end
						return nil
					end, TICKET_TTL)
				end)
			end
			return false
		end
		table.insert(done, ticket)
	end
	return true
end

-- One reserved server id for the match, written to every home server of its players.
local function assign(mode: string, matchId: string, group: { GlobalMatch.Ticket }, now: number)
	local serverId = HttpService:GenerateGUID(false)
	local all: { number } = {}
	for _, ticket in group do
		table.insert(all, ticket.u)
	end
	local byHome: { [string]: { any } } = {}
	local homes = 0
	for _, ticket in group do
		local list = byHome[ticket.h]
		if list == nil then
			list = {}
			byHome[ticket.h] = list
			homes += 1
		end
		table.insert(list, { u = ticket.u, m = matchId, sid = serverId, mode = mode, all = all, t = now })
	end
	log:info(`{mode} {matchId}: {#all} players from {homes} servers`)
	for home, list in byHome do
		local ok, err = pcall(function()
			assignments():UpdateAsync(home, function(old: any): any
				local out = {}
				for _, entry in if type(old) == "table" then old else {} do
					if type(entry) == "table" and type(entry.t) == "number" and now - entry.t < ASSIGN_TTL then
						table.insert(out, entry)
					end
				end
				table.move(list, 1, #list, #out + 1, out)
				return out
			end, ASSIGN_TTL)
		end)
		if not ok then
			log:warn(`assigning {mode} {matchId} to server {home} failed:`, err)
		end
	end
end

local function runMode(mode: string, size: number, now: number)
	local map = queueOf(mode)
	local ok, items = pcall(function(): any
		return map:GetRangeAsync(Enum.SortDirection.Ascending, 200)
	end)
	if not ok or type(items) ~= "table" then
		log:warn(`reading the {mode} queue failed:`, items)
		return
	end
	local waiting: { GlobalMatch.Ticket } = {}
	for _, item in items do
		local u, v = tonumber(item.key), item.value
		if u and type(v) == "table" and type(v.h) == "string" and type(v.at) == "number" then
			if v.s == "w" then
				table.insert(waiting, { u = u, at = v.at, h = v.h })
			elseif v.s == "c" and type(v.ct) == "number" and now - v.ct > CLAIM_STUCK then
				pcall(function()
					map:UpdateAsync(item.key, function(old: any): any
						if type(old) == "table" and old.s == "c" and old.m == v.m then
							return { s = "w", h = old.h, at = old.at }
						end
						return nil
					end, TICKET_TTL)
				end)
			end
		end
	end
	for _, group in GlobalMatch.groups(waiting, now, size, Config.Match.gatherSeconds) do
		local matchId = HttpService:GenerateGUID(false)
		if claim(map, group, matchId, now) then
			assign(mode, matchId, group, now)
			for _, ticket in group do
				pcall(function()
					map:RemoveAsync(tostring(ticket.u))
				end)
			end
		end
	end
end

local function cycle()
	local now = os.time()
	for mode, size in sizes() do
		runMode(mode, size, now)
	end
end

-- Public

-- True when the queues of this server go through the shared queue.
function GlobalQueueService.on(): boolean
	return MatchServerService.canSend()
end

-- `player` waits for `mode` ("1v1", "tdm", "ffa") in the shared queue (written in the background).
function GlobalQueueService.enqueue(player: Player, mode: string)
	mine[player] = mode
	local value = { s = "w", h = game.JobId, at = os.time() }
	task.spawn(function()
		local ok, err = pcall(function()
			-- lihfolk-ignore: datastore-setasync-player (a MemoryStore queue ticket, not saved data: a new join replaces it)
			queueOf(mode):SetAsync(tostring(player.UserId), value, TICKET_TTL)
		end)
		if not ok then
			log:warn(`user {player.UserId} could not join the shared {mode} queue:`, err)
		end
	end)
end

-- Yields. True when `player` is out of the shared queue (or never was in it), false when a match claimed them first
-- (their assignment still comes).
function GlobalQueueService.cancel(player: Player): boolean
	local mode = mine[player]
	mine[player] = nil
	if mode == nil then
		return true
	end
	local claimed = false
	local ok, err = pcall(function()
		queueOf(mode):UpdateAsync(tostring(player.UserId), function(old: any): any
			claimed = type(old) == "table" and old.s == "c"
			if type(old) == "table" and old.s == "w" then
				return { s = "x", h = old.h, at = old.at }
			end
			return nil
		end, CANCEL_TTL)
	end)
	if not ok then
		log:warn(`cancelling user {player.UserId} in the shared {mode} queue failed:`, err)
	end
	if claimed then
		listenUntil = os.clock() + LISTEN_AFTER_CLAIM
	end
	return not claimed
end

-- `player` left their own queue: out of the shared one too (in the background).
function GlobalQueueService.forget(player: Player)
	if mine[player] ~= nil then
		task.spawn(GlobalQueueService.cancel, player)
	end
end

-- Studio checks: the store names' prefix ("SD_" live), a leader round and a lobby read now.
function GlobalQueueService.usePrefix(newPrefix: string)
	prefix = newPrefix
end
GlobalQueueService.cycleOnce = cycle
GlobalQueueService.pollOnce = poll

-- Lifecycle

function GlobalQueueService.init() end

function GlobalQueueService.start()
	if not GlobalQueueService.on() then
		return
	end
	local nextLease, nextCycle, leader = 0, 0, false
	while true do
		task.wait(POLL)
		local now = os.clock()
		if now >= nextLease then
			nextLease = now + LEASE_RENEW
			leader = holdLease()
		end
		if leader and now >= nextCycle then
			nextCycle = now + CYCLE
			local ok, err = pcall(cycle)
			if not ok then
				log:error("matching round failed:", err)
			end
		end
		if next(mine) ~= nil or now < listenUntil then
			local ok, err = pcall(poll)
			if not ok then
				log:error("assignment read failed:", err)
			end
		end
	end
end

function GlobalQueueService.playerAdded(player: Player)
	if not GlobalQueueService.on() then
		return
	end
	local ok, joinData = pcall(function(): any
		return player:GetJoinData()
	end)
	local data = if ok and type(joinData) == "table" then joinData.TeleportData else nil
	local mode = if type(data) == "table" then data.requeue else nil
	if type(mode) ~= "string" or sizes()[mode] == nil then
		return
	end
	task.spawn(function()
		if player.Character == nil then
			player.CharacterAdded:Wait()
		end
		task.wait(REQUEUE_DELAY)
		if player.Parent ~= Players then
			return
		end
		local QueueService, MatchService = queues()
		if mode == "1v1" then
			QueueService.join(player)
		else
			MatchService.join(player, mode)
		end
	end)
end

function GlobalQueueService.playerRemoving(player: Player)
	GlobalQueueService.forget(player)
end

return GlobalQueueService
