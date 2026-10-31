--!strict
-- MatchServerService (server only). One match per server: the owner, 2026-10-30, "every match its a different
-- server"; Diego's NEW MAPS FINALS SUPERPROMPT "Server flow: one map per server"; decided 2026-10-15/17: matches leave
-- the lobby server and players go back to the server they came from. Config.Match.Servers.
-- * Lobby side: send(kind, mode, mapId, matchId, players, teams?) reserves a server of this place
--   (TeleportService:ReserveServer) and teleports the match's players there with a ticket (Logic/MatchTicket as
--   TeleportData). It answers false when it did not send (off, Studio, already a match server, a failed reserve or
--   teleport): the caller plays the match here as before. canSend() says beforehand whether it would try.
-- * Match side (a reserved server: PrivateServerId set, PrivateServerOwnerId 0): the first valid ticket a player brings
--   names the match (the server trusts only MatchTicket.read). Once every ticket player is in with a character (or
--   waitSeconds after the first arrived), settleSeconds later it starts it on the ticket's map: Team / Free for All
--   through MatchService.startHosted (the lobby's teams; bots fill the rest), a 1v1 through QueueService.startHosted
--   on ArenaService.prefer(mapId). When nobody here has a match (SD_MatchId) for homeAfterSeconds (the end screen, a
--   Rematch), everyone goes home: the lobby server the ticket names, else any lobby server.
-- * A teleport that fails after it started (TeleportInitFailed) is tried once more for that player.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)
local Log = require(ReplicatedStorage.Shared.Util.Log)
local MapData = require(ReplicatedStorage.Shared.Maps.MapData)
local MatchTicket = require(script.Parent.Parent.Logic.MatchTicket)

-- Constants

local ATTR_MATCH_ID = "SD_MatchId" -- set by MatchService and DuelService on a player in a match
local POLL_SECONDS = 1

-- Module table

local MatchServerService = {}

-- Private

local log = Log.new("MatchServer")
local ticket: MatchTicket.Ticket? = nil
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

-- Everyone here back to the ticket's lobby server, else to any lobby server.
local function sendHome()
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end
	local home = ticket and ticket.home
	if home then
		local options = Instance.new("TeleportOptions")
		options.ServerInstanceId = home
		local ok, err = teleport(players, options)
		if ok then
			return
		end
		log:warn("going home to the lobby server failed, any lobby then:", err)
	end
	local ok, err = teleport(players, nil)
	if not ok then
		log:error("going home failed:", err)
	end
end

local function startHosted(t: MatchTicket.Ticket, players: { Player })
	local ok, result, why
	if t.kind == "duel" then
		local ArenaService = require(script.Parent.ArenaService) :: any
		local QueueService = require(script.Parent.QueueService) :: any
		if #players < 2 then
			log:warn(`1v1 {t.matchId}: the opponent never arrived`)
			sendHome()
			return
		end
		ArenaService.prefer(t.mapId)
		ok, result, why = pcall(QueueService.startHosted, players[1], players[2], true)
	else
		local MatchService = require(script.Parent.MatchService) :: any
		ok, result, why = pcall(MatchService.startHosted, players, t.mode, t.mapId, t.matchId, t.teams)
	end
	if not ok or not result then
		log:error(`{t.kind} {t.matchId} on {t.mapId} could not start:`, if ok then why else result)
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
	if ticket ~= nil then
		return
	end
	local ok, joinData = pcall(function(): any
		return player:GetJoinData()
	end)
	local read, why = MatchTicket.read(if ok and type(joinData) == "table" then joinData.TeleportData else nil, MapData.maps)
	if read then
		ticket = read
		log:info(`match server for {read.kind} {read.matchId} on {read.mapId} ({#read.players} players)`)
	else
		log:warn(`user {player.UserId} came without a valid ticket ({why})`)
	end
end

-- Public

-- True in a reserved server (a match server), false in a public lobby server, Studio and a VIP server.
function MatchServerService.isMatchServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

-- Whether send() would try (on, a live lobby server).
function MatchServerService.canSend(): boolean
	return cfg().enabled == true and not RunService:IsStudio() and not MatchServerService.isMatchServer()
end

-- Lobby side: the players (Player instances) go to a new server of this place for this match. `teams` = team name by
-- player (Team Deathmatch). True when the teleport started; false = play it here.
function MatchServerService.send(
	kind: string,
	mode: string,
	mapId: string,
	matchId: string,
	players: { Player },
	teams: { [any]: string }?
): boolean
	if not MatchServerService.canSend() or #players == 0 then
		return false
	end
	local okReserve, code = pcall(function(): any
		return (TeleportService:ReserveServer(game.PlaceId))
	end)
	if not okReserve or type(code) ~= "string" then
		log:warn(`reserving a server for {matchId} failed:`, code)
		return false
	end
	local userIds: { number } = {}
	local teamOf: { [number]: string } = {}
	for _, player in players do
		table.insert(userIds, player.UserId)
		local team = teams and teams[player]
		if type(team) == "string" then
			teamOf[player.UserId] = team
		end
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	options:SetTeleportData(MatchTicket.make(kind, mode, mapId, matchId, userIds, teamOf, game.JobId))
	local ok, err = teleport(players, options)
	if not ok then
		log:warn(`teleporting {matchId} failed, it plays here:`, err)
		return false
	end
	log:info(`{kind} {matchId} on {mapId}: {#players} players sent to their own server`)
	return true
end

-- Lifecycle

function MatchServerService.init()
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string, _placeId: number, options: TeleportOptions?)
		log:warn(`teleport of user {player.UserId} failed ({result.Name}): {message}`)
		if not retried[player] and player.Parent == Players then
			retried[player] = true
			local ok, err = teleport({ player }, options)
			if not ok then
				log:warn(`retry for user {player.UserId} failed:`, err)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		retried[player] = nil
	end)
	if not MatchServerService.isMatchServer() then
		return
	end
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
