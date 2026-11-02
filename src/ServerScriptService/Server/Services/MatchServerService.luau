--!strict
-- MatchServerService (server only). One match per server: the owner, 2026-10-30, "every match its a different
-- server"; Diego's NEW MAPS FINALS SUPERPROMPT "Server flow: one map per server"; decided 2026-10-15/17: matches leave
-- the lobby server and players go back to the server they came from. Config.Match.Servers.
-- * Lobby side: sendTo(serverId, mode, matchId, all, players) teleports this server's players of a match the shared
--   queue made (GlobalQueueService, 2026-11-01: players from every server) to its reserved server (TeleportOptions.
--   ReservedServerId = the leader's GUID: every lobby of the match uses the same one, so they all land together) with
--   a ticket (Logic/MatchTicket as TeleportData, no map: the match server picks it). canSend() says whether this
--   server sends matches away at all (on, live, not a match server).
-- * Match side (a reserved server: PrivateServerId set, PrivateServerOwnerId 0; Workspace attribute SD_MatchServer for
--   the client): the first valid ticket a player brings names the match (the server trusts only MatchTicket.read);
--   each player's own ticket names the lobby server they came from. Once every ticket player is in with a character
--   (or waitSeconds after the first arrived), settleSeconds later it starts: a Team / Free for All match by putting
--   them all in this server's own queue (MatchService: MATCH FOUND, the map vote, the bots, as in a lobby), a 1v1
--   through QueueService.startHosted (on the ticket's map, if it names one). When nobody here has a match (SD_MatchId)
--   for homeAfterSeconds (the end screen, a Rematch), everyone goes home.
-- * goHome(player, requeue?) (owner 2026-11-01: "if they hit go back to lobby again, they teleport to the main lobby
--   where all of the squishies and pens are"): the end screen's LOBBY, the 1v1 result's X, Play Again and Queue Again
--   send that player at once to the lobby server they came from (else any lobby server); `requeue` = the mode they
--   join again there (GlobalQueueService).
-- * A teleport that fails after it started (TeleportInitFailed) is tried once more for that player. A failed trip to a
--   lobby server (closed once its players all left, error 771) goes to any lobby server, now and from then on.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)
local Log = require(ReplicatedStorage.Shared.Util.Log)
local MapData = require(ReplicatedStorage.Shared.Maps.MapData)
local MatchTicket = require(script.Parent.Parent.Logic.MatchTicket)

-- Constants

local ATTR_MATCH_ID = "SD_MatchId" -- set by MatchService and DuelService on a player in a match
local ATTR_MATCH_SERVER = "SD_MatchServer" -- on the Workspace of a match server (the client's LOBBY / X go home)
local POLL_SECONDS = 1

-- Module table

local MatchServerService = {}

-- Private

local log = Log.new("MatchServer")
local ticket: MatchTicket.Ticket? = nil
local homes: { [number]: string } = {} -- user id -> the JobId of the lobby server they came from
local gone: { [string]: boolean } = {} -- lobby servers a trip home could not reach
local leaving: { [Player]: boolean } = {}
local firstArrivalAt: number? = nil
local started = false
local idleSince: number? = nil
local retried: { [Player]: boolean } = {}

local function cfg(): any
	return Config.Match.Servers
end

local function busy(): boolean
	for _, player in Players:GetPlayers() do
		local id = player:GetAttribute(ATTR_MATCH_ID)
		if type(id) == "string" and id ~= "" then
			return true
		end
	end
	return false
end

-- The ticket's players who are here with a character.
local function arrived(t: MatchTicket.Ticket): ({ Player }, boolean)
	local list: { Player } = {}
	for _, userId in t.players do
		local player = Players:GetPlayerByUserId(userId)
		if player and player.Character then
			table.insert(list, player)
		end
	end
	return list, #list == #t.players
end

local function teleport(players: { Player }, options: TeleportOptions?): (boolean, any)
	return pcall(function()
		return TeleportService:TeleportAsync(game.PlaceId, players, options)
	end)
end

-- Options for a trip home: to `home` unless it is gone (else any lobby server), with `requeue` as TeleportData.
local function homeOptions(home: string?, requeue: string?): TeleportOptions
	local options = Instance.new("TeleportOptions")
	if home and not gone[home] then
		options.ServerInstanceId = home
	end
	if requeue then
		options:SetTeleportData({ requeue = requeue })
	end
	return options
end

-- `players` (who share `home`) go there, else to any lobby server.
local function trip(players: { Player }, home: string?, requeue: string?)
	for _, player in players do
		leaving[player] = true
	end
	local options = homeOptions(home, requeue)
	local ok, err = teleport(players, options)
	if not ok and options.ServerInstanceId ~= "" then
		log:warn("going home to the lobby server failed, any lobby then:", err)
		gone[options.ServerInstanceId] = true
		ok, err = teleport(players, homeOptions(nil, requeue))
	end
	if not ok then
		log:error("going home failed:", err)
		for _, player in players do
			leaving[player] = nil
		end
	end
end

-- Everyone here (not already leaving) back to the lobby server they came from.
local function sendHome()
	local byHome: { [string]: { Player } } = {}
	for _, player in Players:GetPlayers() do
		if not leaving[player] then
			local home = homes[player.UserId] or ""
			local list = byHome[home] or {}
			table.insert(list, player)
			byHome[home] = list
		end
	end
	for home, players in byHome do
		trip(players, if home ~= "" then home else nil, nil)
	end
end

local function startHosted(t: MatchTicket.Ticket, players: { Player })
	if t.kind == "duel" then
		local ArenaService = require(script.Parent.ArenaService) :: any
		local QueueService = require(script.Parent.QueueService) :: any
		if #players < 2 then
			log:warn(`1v1 {t.matchId}: the opponent never arrived`)
			sendHome()
			return
		end
		if t.mapId ~= "" then
			ArenaService.prefer(t.mapId)
		end
		local ok, result, why = pcall(QueueService.startHosted, players[1], players[2], true)
		if not ok or not result then
			log:error(`1v1 {t.matchId} could not start:`, if ok then why else result)
			sendHome()
		end
		return
	end
	-- Team / Free for All: this server's own queue starts at once with everyone here (MATCH FOUND, vote, bots).
	local MatchService = require(script.Parent.MatchService) :: any
	local joined = 0
	for _, player in players do
		local ok, result = pcall(MatchService.join, player, t.mode)
		if ok and result then
			joined += 1
		end
	end
	if joined == 0 then
		log:error(`{t.mode} {t.matchId}: nobody could join this server's queue`)
		sendHome()
	end
end

local function step(now: number)
	local t = ticket
	if t == nil then
		return
	end
	if not started then
		local players, all = arrived(t)
		if #players == 0 then
			return
		end
		firstArrivalAt = firstArrivalAt or now
		if all or now - (firstArrivalAt :: number) >= cfg().waitSeconds then
			started = true
			task.wait(cfg().settleSeconds)
			startHosted(t, (arrived(t)))
		end
		return
	end
	if busy() then
		idleSince = nil
	elseif idleSince == nil then
		idleSince = now
	elseif now - idleSince >= cfg().homeAfterSeconds then
		idleSince = now -- once more later if a teleport fails
		sendHome()
	end
end

local function onPlayerAdded(player: Player)
	local ok, joinData = pcall(function(): any
		return player:GetJoinData()
	end)
	local read, why = MatchTicket.read(if ok and type(joinData) == "table" then joinData.TeleportData else nil, MapData.maps)
	if read == nil then
		log:warn(`user {player.UserId} came without a valid ticket ({why})`)
		return
	end
	homes[player.UserId] = read.home
	if ticket == nil then
		ticket = read
		log:info(`match server for {read.kind} {read.matchId} on {if read.mapId ~= "" then read.mapId else "a vote"} ({#read.players} players)`)
	end
end

-- Public

-- True in a reserved server (a match server), false in a public lobby server, Studio and a VIP server.
function MatchServerService.isMatchServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- Whether this server sends its matches away (on, a live lobby server).
function MatchServerService.canSend(): boolean
	return cfg().enabled == true and not RunService:IsStudio() and not MatchServerService.isMatchServer()
end

-- Lobby side: this server's `players` of match `matchId` go to its reserved server `serverId` (a GUID); `all` = every
-- player of the match (user ids, every server). True when the teleport started.
function MatchServerService.sendTo(serverId: string, mode: string, matchId: string, all: { number }, players: { Player }): boolean
	if #players == 0 then
		return false
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerId = serverId
	options:SetTeleportData(MatchTicket.make(if mode == "1v1" then "duel" else "match", mode, "", matchId, all, nil, game.JobId))
	local ok, err = teleport(players, options)
	if not ok then
		log:warn(`teleporting {matchId} failed:`, err)
		return false
	end
	log:info(`{mode} {matchId}: {#players} of {#all} players sent from here`)
	return true
end

-- Match side: `player` goes back to the lobby now (see the header); `requeue` = a mode to join again there.
function MatchServerService.goHome(player: Player, requeue: unknown)
	if not MatchServerService.isMatchServer() or leaving[player] then
		return
	end
	local mode = if type(requeue) == "string" then string.lower(requeue) else nil
	if mode ~= "1v1" and (mode == nil or Config.Match.Modes[mode] == nil) then
		mode = nil
	end
	trip({ player }, homes[player.UserId], mode)
end

-- Lifecycle

function MatchServerService.init()
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string, _placeId: number, options: TeleportOptions?)
		log:warn(`teleport of user {player.UserId} failed ({result.Name}): {message}`)
		-- The lobby server we came from has closed (it empties when its players all leave for a match, error 771):
		-- this and every later trip home there go to any lobby server instead (keeping a requeue).
		local again = options
		if options and options.ServerInstanceId ~= "" then
			gone[options.ServerInstanceId] = true
			local data: any = options:GetTeleportData()
			again = homeOptions(nil, if type(data) == "table" then data.requeue else nil)
		end
		if not retried[player] and player.Parent == Players then
			retried[player] = true
			local ok, err = teleport({ player }, again)
			if not ok then
				log:warn(`retry for user {player.UserId} failed:`, err)
				leaving[player] = nil
			end
		else
			leaving[player] = nil -- the idle loop tries again later
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		retried[player] = nil
		leaving[player] = nil
	end)
	if not MatchServerService.isMatchServer() then
		return
	end
	Workspace:SetAttribute(ATTR_MATCH_SERVER, true)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

function MatchServerService.start()
	if not MatchServerService.isMatchServer() then
		return
	end
	while true do
		local ok, err = pcall(step, os.clock())
		if not ok then
			log:error("match server step failed:", err)
		end
		task.wait(POLL_SECONDS)
	end
end

return MatchServerService
