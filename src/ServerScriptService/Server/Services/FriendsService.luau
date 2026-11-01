--!strict
-- FriendsService (server only). 2026-10-31, the owner's plan step 1 (friends on the same team in Team matches):
-- who is friends with whom among the players in this server. On each join the server asks Roblox once for every other
-- player here (Player:IsFriendsWith, a web call, each in its own thread) and remembers the answer both ways; a call
-- that fails counts as not friends. areFriends(a, b) never yields: it only reads what was learned (MatchService deals
-- its Team matches by it). A player's answers go when they leave.
-- Dependencies are injectable (useDeps) so unit tests run with fake players and a fake isFriendsWith.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)

-- Types

export type Deps = {
	players: () -> { any },
	isFriendsWith: (player: any, userId: number) -> boolean, -- yields (a web call); may error
	spawn: (fn: (...any) -> ...any, ...any) -> (),
}

-- Module table

local FriendsService = {}

-- Private

local log = Log.new("Friends")
local deps: Deps? = nil
local friends: { [number]: { [number]: true } } = {} -- userId -> its friends here; only players still here have one

local function getDeps(): Deps
	local d = deps
	assert(d ~= nil, "[SD][Friends] used before init")
	return d
end

local function ask(player: any, otherId: number)
	local userId = player.UserId
	local ok, yes = pcall(getDeps().isFriendsWith, player, otherId)
	if not ok then
		log:warn(`IsFriendsWith({userId}, {otherId}) failed:`, yes)
		return
	end
	local mine, theirs = friends[userId], friends[otherId]
	if yes == true and mine ~= nil and theirs ~= nil then -- both still here after the call
		mine[otherId] = true
		theirs[userId] = true
	end
end

local function defaultDeps(): Deps
	return {
		players = function(): { any }
			return Players:GetPlayers()
		end,
		isFriendsWith = function(player: any, userId: number): boolean
			return player:IsFriendsWith(userId)
		end,
		spawn = function(fn: (...any) -> ...any, ...: any)
			task.spawn(fn, ...)
		end,
	}
end

-- Public

-- Uses these collaborators and forgets every answer (init() passes the real ones; tests fakes).
function FriendsService.useDeps(newDeps: Deps)
	deps = newDeps
	friends = {}
end

-- True when the two userIds are friends and both are in this server (as far as Roblox has answered yet).
function FriendsService.areFriends(a: number, b: number): boolean
	local mine = friends[a]
	return mine ~= nil and mine[b] == true
end

-- Lifecycle

function FriendsService.init()
	FriendsService.useDeps(defaultDeps())
end

function FriendsService.playerAdded(player: Player)
	local d = getDeps()
	local userId = player.UserId
	friends[userId] = {}
	for _, other in d.players() do
		if other.UserId ~= userId then
			d.spawn(ask, player, other.UserId)
		end
	end
end

function FriendsService.playerRemoving(player: Player)
	local userId = player.UserId
	for otherId in friends[userId] or {} do
		local theirs = friends[otherId]
		if theirs ~= nil then
			theirs[userId] = nil
		end
	end
	friends[userId] = nil
end

return FriendsService
