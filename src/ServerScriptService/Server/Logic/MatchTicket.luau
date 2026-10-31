--!strict
-- MatchTicket (server only, pure): the TeleportData a lobby server sends with the players of one match to the match's
-- own reserved server (Diego's NEW MAPS FINALS SUPERPROMPT "one map per server", 2026-10-30; the owner's decisions:
-- matches leave the lobby server and players go back to the server they came from). The match server trusts nothing
-- in it: read() rebuilds it from checked fields only.
--   make(kind, mode, mapId, matchId, userIds, teams?, home) -> Ticket
--   read(data, maps) -> (Ticket?, why?)   maps = Shared.Maps.MapData.maps
-- kind "match" (mode "tdm" | "ffa") or "duel" (mode "1v1"); mapId a MapData id of that mode; 1..12 user ids; teams
-- by user id (JSON keys are strings, so tostring(userId)); home = the lobby server's JobId.

export type Ticket = {
	v: number,
	kind: string,
	mode: string,
	mapId: string,
	matchId: string,
	players: { number },
	teams: { [string]: string },
	home: string,
}

local MatchTicket = {}

MatchTicket.VERSION = 1
local MAX_PLAYERS = 12
local MAX_TEXT = 64
local MAP_MODE: { [string]: string } = { tdm = "tdm", ffa = "ffa", ["1v1"] = "duel" }
local KIND_OF: { [string]: string } = { tdm = "match", ffa = "match", ["1v1"] = "duel" }

local function text(v: unknown): boolean
	return type(v) == "string" and #v > 0 and #v <= MAX_TEXT
end

function MatchTicket.make(
	kind: string,
	mode: string,
	mapId: string,
	matchId: string,
	userIds: { number },
	teams: { [number]: string }?,
	home: string
): Ticket
	local byId: { [string]: string } = {}
	for userId, team in teams or {} do
		byId[tostring(userId)] = team
	end
	return {
		v = MatchTicket.VERSION,
		kind = kind,
		mode = mode,
		mapId = mapId,
		matchId = matchId,
		players = table.clone(userIds),
		teams = byId,
		home = home,
	}
end

function MatchTicket.read(data: unknown, maps: { [string]: any }): (Ticket?, string?)
	if type(data) ~= "table" then
		return nil, "no ticket"
	end
	local t = data :: any
	if t.v ~= MatchTicket.VERSION then
		return nil, "version"
	end
	local mode = t.mode
	if type(mode) ~= "string" or MAP_MODE[mode] == nil or t.kind ~= KIND_OF[mode] then
		return nil, "mode"
	end
	local map = if type(t.mapId) == "string" then maps[t.mapId] else nil
	if map == nil or map.mode ~= MAP_MODE[mode] then
		return nil, "map"
	end
	if not text(t.matchId) or not text(t.home) then
		return nil, "ids"
	end
	if type(t.players) ~= "table" then
		return nil, "players"
	end
	local players: { number } = {}
	for _, id in t.players do
		if type(id) ~= "number" or id ~= math.floor(id) or id < 1 or table.find(players, id) then
			return nil, "players"
		end
		table.insert(players, id)
	end
	if #players == 0 or #players > MAX_PLAYERS or #players ~= #t.players then
		return nil, "players"
	end
	local teams: { [string]: string } = {}
	if t.teams ~= nil then
		if type(t.teams) ~= "table" then
			return nil, "teams"
		end
		for key, team in t.teams do
			if type(key) ~= "string" or not table.find(players, tonumber(key)) or not text(team) then
				return nil, "teams"
			end
			teams[key] = team
		end
	end
	local ticket: Ticket = {
		v = MatchTicket.VERSION,
		kind = t.kind,
		mode = mode,
		mapId = t.mapId,
		matchId = t.matchId,
		players = players,
		teams = teams,
		home = t.home,
	}
	return ticket, nil
end

return MatchTicket
