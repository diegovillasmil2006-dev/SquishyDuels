--!strict
-- LobbyMoveService (server only; 2026-10-17, VillasmilGaming: "change the movement a little bit in the lobby", the lobby
-- reference video: a quicker run and power slides). Numbers in Config.LobbyMove.
-- * The lobby run: a character that spawns outside a duel or a match (the player's SD_MatchId and SD_DuelPhase empty)
--   gets Humanoid.WalkSpeed = walkSpeed. DuelService and MatchService save what a fighter had and give it back after,
--   so the lobby speed comes back with them.
-- * SlideRequest(clientTime): the slider's own client already moves (its HumanoidRootPart is its own) and plays the
--   slide; this checks it (validate, pure: in the lobby, alive, at least cooldownSeconds - cooldownToleranceSeconds
--   since its last accepted slide) and stamps the character's SD_SlideAt with the server time, which every client
--   watches to show the pose, the dust and the sound (Client/Controllers/LobbyMoveController). A refused request
--   changes nothing (a bad payload never reaches here: NetService checks the argument types and the rate).
-- Per player (userId): lastSlideAt; playerRemoving forgets it. Tests swap the clock with useDeps.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local NetService = require(script.Parent.NetService)

-- Types

export type Facts = {
	inLobby: boolean, -- no match id, no duel phase
	alive: boolean,
	now: number,
	lastSlideAt: number,
}

-- Constants

local MOVE = Config.LobbyMove
local SLIDE = MOVE.Slide
local REMOTE_REQUEST = "SlideRequest"
local ATTR_SLIDE_AT = "SD_SlideAt"
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_DUEL_PHASE = "SD_DuelPhase"

-- Module table

local LobbyMoveService = {}

-- Private

local lastSlide: { [number]: number } = {} -- userId -> server time of the last accepted slide
local connections: { [number]: RBXScriptConnection } = {}
local deps = {
	now = function(): number
		return Workspace:GetServerTimeNow()
	end,
}

local function textOf(value: unknown): string
	return if type(value) == "string" then value else ""
end

-- Pure ---------------------------------------------------------------------------------------------------------------

-- Whether the player's server-written attributes say it is in the lobby (no match, no duel phase).
function LobbyMoveService.inLobby(matchId: unknown, phase: unknown): boolean
	return textOf(matchId) == "" and textOf(phase) == ""
end

-- The reason a slide is refused, or nil when it is accepted.
function LobbyMoveService.validate(facts: Facts): string?
	if not facts.inLobby then
		return "slide.context"
	end
	if not facts.alive then
		return "slide.dead"
	end
	if facts.now < facts.lastSlideAt + SLIDE.cooldownSeconds - SLIDE.cooldownToleranceSeconds then
		return "slide.cooldown"
	end
	return nil
end

-- Private: runtime ---------------------------------------------------------------------------------------------------

local function humanoidOf(character: Model?): Humanoid?
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function setLobbySpeed(player: Player, character: Model)
	local function apply(humanoid: Humanoid)
		if humanoid.Parent ~= character or player.Character ~= character then
			return
		end
		if not LobbyMoveService.inLobby(player:GetAttribute(ATTR_MATCH_ID), player:GetAttribute(ATTR_DUEL_PHASE)) then
			return -- a duel or a match spawn sets its own movement
		end
		humanoid.WalkSpeed = MOVE.walkSpeed
	end
	local humanoid = humanoidOf(character)
	if humanoid then
		apply(humanoid)
		return
	end
	local connection: RBXScriptConnection
	connection = character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Humanoid") then
			connection:Disconnect()
			apply(child)
		end
	end)
	task.delay(10, function()
		connection:Disconnect()
	end)
end

-- Accepts or refuses one slide. Returns (accepted, reason?).
function LobbyMoveService.requestSlide(player: Player, _clientTime: unknown): (boolean, string?)
	local now = deps.now()
	local character = player.Character
	local humanoid = humanoidOf(character)
	local facts: Facts = {
		inLobby = LobbyMoveService.inLobby(player:GetAttribute(ATTR_MATCH_ID), player:GetAttribute(ATTR_DUEL_PHASE)),
		alive = character ~= nil and humanoid ~= nil and humanoid.Health > 0,
		now = now,
		lastSlideAt = lastSlide[player.UserId] or -math.huge,
	}
	local reason = LobbyMoveService.validate(facts)
	if reason ~= nil then
		return false, reason
	end
	lastSlide[player.UserId] = now
	;(character :: Model):SetAttribute(ATTR_SLIDE_AT, now)
	return true, nil
end

-- Swaps the clock (tests); nil restores it.
function LobbyMoveService.useDeps(newDeps: { now: (() -> number)? }?)
	deps.now = if newDeps and newDeps.now
		then newDeps.now
		else function(): number
			return Workspace:GetServerTimeNow()
		end
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function LobbyMoveService.init()
	NetService.on(REMOTE_REQUEST, function(player: Player, clientTime: any)
		LobbyMoveService.requestSlide(player, clientTime)
	end)
end

function LobbyMoveService.playerAdded(player: Player)
	local old = connections[player.UserId]
	if old then
		old:Disconnect()
	end
	connections[player.UserId] = player.CharacterAdded:Connect(function(character: Model)
		setLobbySpeed(player, character)
	end)
	local character = player.Character
	if character then
		setLobbySpeed(player, character)
	end
end

function LobbyMoveService.playerRemoving(player: Player)
	lastSlide[player.UserId] = nil
	local connection = connections[player.UserId]
	if connection then
		connection:Disconnect()
		connections[player.UserId] = nil
	end
end

-- Not called by the bootstrap; tests and leak checks.
function LobbyMoveService.destroy()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(lastSlide)
	LobbyMoveService.useDeps(nil)
end

return LobbyMoveService
