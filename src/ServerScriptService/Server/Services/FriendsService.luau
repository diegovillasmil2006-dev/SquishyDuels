--!strict
-- FriendsService (server only). 2026-10-31, the owner's plan step 1 (friends on the same team in Team matches):
-- who is friends with whom among the players in this server. On each join the server asks Roblox once for every other
-- player here (Player:IsFriendsWithAsync, a web call, each in its own thread) and remembers the answer both ways; a call
-- that fails counts as not friends. areFriends(a, b) never yields: it only reads what was learned (MatchService deals
-- its Team matches by it). A player's answers go when they leave.
-- Friend Boost (plan step 2, Config.Social.FriendBoost): penMult(player) = 1 + perFriend x their friends here (at most
-- maxFriends), what PenService multiplies the pen's pay by; the Player attribute SD_FriendBoost holds the same boost
-- in whole percent (0 without a friend here) for the client's pill, set again whenever a friend arrives or leaves.
-- Dependencies are injectable (useDeps) so unit tests run with fake players and a fake isFriendsWith.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)

-- Types

export type Deps = {
	players: () -> { any },
	isFriendsWith: (player: any, userId: number) -> boolean, -- yields (a web call); may error
	spawn: (fn: (...any) -> ...any, ...any) -> (),
}

-- Constants

local BOOST = Config.Social.FriendBoost
local ATTR_BOOST = "SD_FriendBoost"

-- Module table

local FriendsService = {}

-- Private

local log = Log.new("Friends")
local deps: Deps? = nil
local friends: { [number]: { [number]: true } } = {} -- userId -> its friends here; only players still here have one
local playerOf: { [number]: any } = {}

local function getDeps(): Deps
	local d = deps
	assert(d ~= nil, "[SD][Friends] used before init")
	return d
end

local function boostOf(userId: number): number
	local count = 0
	for _ in friends[userId] or {} do
		count += 1
	end
	return BOOST.perFriend * math.min(count, BOOST.maxFriends)
end

local function publish(userId: number)
	local player = playerOf[userId]
	if player ~= nil then
		player:SetAttribute(ATTR_BOOST, math.floor(boostOf(userId) * 100 + 0.5))
	end
end

local function ask(player: any, otherId: number)
	local userId = player.UserId
	local ok, yes = pcall(getDeps().isFriendsWith, player, otherId)
	if not ok then
		log:warn(`IsFriendsWithAsync({userId}, {otherId}) failed:`, yes)
		return
	end
	local mine, theirs = friends[userId], friends[otherId]
	if yes == true and mine ~= nil and theirs ~= nil then -- both still here after the call
		mine[otherId] = true
		theirs[userId] = true
		publish(userId)
		publish(otherId)
	end
end

local function defaultDeps(): Deps
	return {
		players = function(): { any }
			return Players:GetPlayers()
		end,
		isFriendsWith = function(player: any, userId: number): boolean
			return player:IsFriendsWithAsync(userId) -- IsFriendsWith is the deprecated name
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
	playerOf = {}
end

-- True when the two userIds are friends and both are in this server (as far as Roblox has answered yet).
function FriendsService.areFriends(a: number, b: number): boolean
	local mine = friends[a]
	return mine ~= nil and mine[b] == true
end

-- Friend Boost: what the player's pen pay is multiplied by (1 without a friend here).
function FriendsService.penMult(player: any): number
	return 1 + boostOf(player.UserId)
end

-- Lifecycle

function FriendsService.init()
	FriendsService.useDeps(defaultDeps())
end

function FriendsService.playerAdded(player: Player)
	local d = getDeps()
	local userId = player.UserId
	friends[userId] = {}
	playerOf[userId] = player
	publish(userId)
	for _, other in d.players() do
		if other.UserId ~= userId then
			d.spawn(ask, player, other.UserId)
		end
	end
end

function FriendsService.playerRemoving(player: Player)
	local userId = player.UserId
	local mine = friends[userId] or {}
	friends[userId] = nil
	playerOf[userId] = nil
	for otherId in mine do
		local theirs = friends[otherId]
		if theirs ~= nil then
			theirs[userId] = nil
			publish(otherId)
		end
	end
end

return FriendsService
