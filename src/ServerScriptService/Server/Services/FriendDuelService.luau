--!strict
-- FriendDuelService (server only). Batch 3 (friends, review #6; user decisions 2026-10-14): picking who to duel.
-- * The duel pads (Q1 A): the 10 queue pads under the Duel tower (WorldLayout.QueuePads). Config.Social.Pads.checkHz
--   times a second (tick) every player who may stand (a real Player in the game, alive, not Matched in the queue and
--   with an empty SD_DuelPhase) whose HumanoidRootPart (the server's position) is on a pad counts as standing there;
--   Logic/DuelPads decides. A ring uses the design's colours (lobby.js:197-199): off = the built pebble look, on = the
--   pad's team colour, ready = butter gold, the lit ones Neon (D7). What lights it is new: the design lit the rings by
--   how full the queue was and marked the pad states presentation only (lobby.js:88); here a ring lights when someone
--   stands on its pad and the pads start duels (the user's choice, Q1 A). The server paints the rings, so every client
--   sees them. A player alone on a pad hears "Get a friend on the strawberry (mint) pad across from you to duel!"; when
--   both pads of a lane are taken both hear "Duel with {name} in 3 seconds! Step off to cancel." After the hold,
--   QueueService.startDirect starts the duel (the queue's own checks for both; a Searching ticket is dropped; the
--   queue's "Opponent found" banner names the opponent); a cooldown or a full arena is tried again on the next check
--   (the full arena toasted once); any other refusal is toasted once and waits until the lane's owners change.
-- * Rematch: on DuelService.MatchEnded, a finished duel (outcome win or draw, nobody bailed) between two real players
--   still in the server offers a rematch for Config.Social.Rematch.windowSeconds: the Player attribute SD_RematchWith
--   (the opponent's userId) on both. RematchRequest (no arguments) sets the caller's own SD_RematchWant to that userId
--   while the offer lasts, and clears it again when it is already set (the card closed by hand takes the wish back,
--   DuelController); once both want each other, each check calls startDirect until it works or the window ends
--   (the players may still be returning or in the 3 s requeue cooldown). An offer clears (attributes too) when it
--   starts, expires, when either player leaves, and when either joins the queue or another duel (QueueService.Joined).
-- * isFriendMatch(matchId): the matches started here (pads and Rematch), for ShowOffService's Duel Buddies badge.
-- Rewards are DuelRewards' as for any duel (the same-pair cut included, Q2 A). Nothing here takes an argument from a
-- client but the press itself; positions are the server's.
-- Dependencies are injectable (useDeps) so unit tests run with fake players, roots and a fake startDirect. init() and
-- the player hooks never yield.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

local Services = script.Parent
local CharacterService = require(Services.CharacterService)
local DuelService = require(Services.DuelService)
local NetService = require(Services.NetService)
local QueueService = require(Services.QueueService)
local WorldService = require(Services.WorldService)
local DuelPads = require(Services.Parent.Logic.DuelPads)

-- Types

export type Deps = {
	now: () -> number, -- server time
	players: () -> { any },
	rootPosition: (player: any) -> Vector3?, -- the HumanoidRootPart's position, nil without one
	canStand: (player: any) -> boolean, -- alive, not Matched, not in a duel phase
	startDirect: (a: any, b: any) -> (boolean, any), -- QueueService.startDirect
	notify: (player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?) -> (),
	setGlow: (pad: number, look: string) -> (),
}

type Offer = { opponent: any, untilAt: number }

-- Constants

local PADS: { any } = WorldLayout.QueuePads
local PAD_CONFIG = Config.Social.Pads
local WINDOW_SECONDS = Config.Social.Rematch.windowSeconds
local ATTR_WITH = "SD_RematchWith"
local ATTR_WANT = "SD_RematchWant"
local ATTR_PHASE = "SD_DuelPhase"
local RING_NAME = "queue_pad_ring"
local RING_SNAP_STUDS = 1 -- a ring binds to the pad whose centre is this close (horizontally)
local CODE_WAIT_MINT = "duel.padWaitingMint"
local CODE_WAIT_STRAWBERRY = "duel.padWaitingStrawberry"
local CODE_READY = "duel.padReady"
local CODE_COOLDOWN = "queue.cooldown"
local CODE_WAITING_ARENA = "queue.waitingArena"
local GLOW_COLORS: { [string]: Color3 } = {
	mint = Palette.LobbyMint,
	strawberry = Palette.LobbyStrawberry,
	ready = Palette.LobbyButter,
}

-- Module table

local FriendDuelService = {}

-- Private

local log = Log.new("FriendDuel")
local deps: Deps? = nil
local padState = DuelPads.new()
local offers: { [any]: Offer } = {}
local friendMatches: { [string]: boolean } = {}
local arenaToasted: { [string]: boolean } = {}

local function getDeps(): Deps
	local d = deps
	assert(d ~= nil, "[SD][FriendDuel] used before init")
	return d
end

local function inGame(player: any): boolean
	return player ~= nil and player.Parent == Players
end

local function remember(match: any)
	local matchId = if type(match) == "table" then match.matchId else match
	if type(matchId) == "string" then
		friendMatches[matchId] = true
	end
end

local function clearOffer(player: any)
	if offers[player] ~= nil then
		offers[player] = nil
		player:SetAttribute(ATTR_WITH, nil)
		player:SetAttribute(ATTR_WANT, nil)
	end
end

local function startPads(effect: DuelPads.Effect, byId: { [number]: any })
	local d = getDeps()
	local mint, berry = byId[effect.mint :: number], byId[effect.strawberry :: number]
	if mint == nil or berry == nil then
		return -- one left meanwhile: the next check frees the pad
	end
	local pair = `{mint.UserId}:{berry.UserId}`
	local ok, result = d.startDirect(mint, berry)
	if ok then
		remember(result) -- no toast: the queue's "Opponent found" banner names the opponent
		arenaToasted[pair] = nil
	elseif result == CODE_COOLDOWN or result == CODE_WAITING_ARENA then
		DuelPads.retry(padState, effect.lane :: number)
		if result == CODE_WAITING_ARENA and not arenaToasted[pair] then
			arenaToasted[pair] = true
			d.notify(mint, result, nil, "info")
			d.notify(berry, result, nil, "info")
		end
	else
		d.notify(mint, tostring(result), nil, "warn")
		d.notify(berry, tostring(result), nil, "warn")
	end
end

local function stepRematches(now: number)
	local d = getDeps()
	for player, offer in table.clone(offers) do
		if offers[player] ~= offer then
			continue -- cleared earlier in this pass
		end
		local opponent = offer.opponent
		if now >= offer.untilAt or not inGame(opponent) then
			clearOffer(player)
			continue
		end
		local both = offers[opponent] ~= nil
			and player:GetAttribute(ATTR_WANT) == opponent.UserId
			and opponent:GetAttribute(ATTR_WANT) == player.UserId
		if both and player.UserId < opponent.UserId then
			local ok, match = d.startDirect(player, opponent)
			if ok then
				remember(match)
				clearOffer(player)
				clearOffer(opponent)
			end
		end
	end
end

local function defaultDeps(): Deps
	return {
		now = function(): number
			return Workspace:GetServerTimeNow()
		end,
		players = function(): { any }
			return Players:GetPlayers()
		end,
		rootPosition = function(player: any): Vector3?
			local root = CharacterService.getRoot(player)
			return if root then root.Position else nil
		end,
		canStand = function(player: any): boolean
			local phase = player:GetAttribute(ATTR_PHASE)
			return CharacterService.isAlive(player)
				and QueueService.state(player) ~= "Matched"
				and (phase == nil or phase == "")
		end,
		startDirect = QueueService.startDirect,
		notify = function(player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
			NetService.notify(player, code, args, kind)
		end,
		setGlow = function(_pad: number, _look: string) end, -- init binds the lobby's rings
	}
end

-- Public -------------------------------------------------------------------------------------------------------------

-- Uses these collaborators and clears every pad, offer and friend match (init() passes the real ones; tests fakes).
function FriendDuelService.useDeps(newDeps: Deps)
	deps = newDeps
	padState = DuelPads.new()
	offers = {}
	friendMatches = {}
	arenaToasted = {}
end

-- The lobby's queue_pad_ring parts under `container` (the DuelGate model), each bound to the pad its centre sits on.
-- Returns setGlow(pad, look) and how many rings were bound. "off" puts back the ring's own colour and material.
function FriendDuelService.bindRings(container: Instance?): ((pad: number, look: string) -> (), number)
	local rings: { [number]: { part: BasePart, color: Color3, material: Enum.Material } } = {}
	local bound = 0
	local parts: { Instance } = if container then container:GetDescendants() else {}
	for _, part in parts do
		if part:IsA("BasePart") and part.Name == RING_NAME then
			for index, pad in PADS do
				local offset = part.Position - pad.position
				if rings[index] == nil and Vector2.new(offset.X, offset.Z).Magnitude <= RING_SNAP_STUDS then
					rings[index] = { part = part, color = part.Color, material = part.Material }
					bound += 1
					break
				end
			end
		end
	end
	local function setGlow(pad: number, look: string)
		local ring = rings[pad]
		if ring == nil then
			return
		end
		local color = GLOW_COLORS[if look == "on" then PADS[pad].team else look]
		ring.part.Color = color or ring.color
		ring.part.Material = if color then Enum.Material.Neon else ring.material
	end
	return setGlow, bound
end

-- One check: who stands on which pad (DuelPads.step, its effects), then the rematches.
function FriendDuelService.tick()
	local d = getDeps()
	local now = d.now()
	local byId: { [number]: any } = {}
	local standing: { [number]: number } = {}
	for _, player in d.players() do
		byId[player.UserId] = player
		local position = if d.canStand(player) then d.rootPosition(player) else nil
		local pad = if position then DuelPads.padAt(PADS, position, PAD_CONFIG) else nil
		if pad ~= nil then
			standing[player.UserId] = pad
		end
	end
	for _, effect in DuelPads.step(padState, PADS, standing, now, PAD_CONFIG) do
		if effect.kind == "glow" then
			d.setGlow(effect.pad :: number, effect.look or "off")
		elseif effect.kind == "waiting" then
			local player = byId[effect.userId :: number]
			if player then
				-- A mint stander needs a friend on the strawberry pad, and the other way round.
				d.notify(player, if effect.team == "mint" then CODE_WAIT_STRAWBERRY else CODE_WAIT_MINT, nil, "info")
			end
		elseif effect.kind == "ready" then
			-- The countdown: each hears who and that stepping off cancels.
			local mint, berry = byId[effect.mint :: number], byId[effect.strawberry :: number]
			if mint and berry then
				local seconds: string | number = PAD_CONFIG.holdSeconds
				d.notify(mint, CODE_READY, { name = berry.DisplayName, seconds = seconds }, "info")
				d.notify(berry, CODE_READY, { name = mint.DisplayName, seconds = seconds }, "info")
			end
		elseif effect.kind == "start" then
			startPads(effect, byId)
		end
	end
	stepRematches(now)
end

-- DuelService.MatchEnded: offers a rematch both ways after a finished duel between two real players in the server.
function FriendDuelService.handleMatchEnded(summary: any)
	if type(summary) ~= "table" or (summary.outcome ~= "win" and summary.outcome ~= "draw") then
		return
	end
	if type(summary.bailers) ~= "table" or #summary.bailers > 0 or type(summary.participants) ~= "table" then
		return
	end
	local a, b = summary.participants[1], summary.participants[2]
	for _, part in { a, b } do
		if type(part) ~= "table" or part.isTestDummy == true or not inGame(part.player) then
			return
		end
	end
	local untilAt = getDeps().now() + WINDOW_SECONDS
	for _, pair in { { a.player, b.player }, { b.player, a.player } } do
		local player, opponent = pair[1], pair[2]
		offers[player] = { opponent = opponent, untilAt = untilAt }
		player:SetAttribute(ATTR_WITH, opponent.UserId)
		player:SetAttribute(ATTR_WANT, nil)
	end
end

-- RematchRequest: the caller wants the offered rematch, or takes the wish back when it is already set (nothing
-- without a live offer).
function FriendDuelService.requestRematch(player: any)
	local offer = offers[player]
	if offer ~= nil and getDeps().now() < offer.untilAt then
		local opponentId = offer.opponent.UserId
		player:SetAttribute(ATTR_WANT, if player:GetAttribute(ATTR_WANT) == opponentId then nil else opponentId)
	end
end

-- Drops the player's rematch offer and their opponent's (QueueService.Joined: they queued or started another duel).
function FriendDuelService.cancelRematch(player: any)
	local offer = offers[player]
	if offer ~= nil then
		clearOffer(offer.opponent)
		clearOffer(player)
	end
end

-- True for a match started on the duel pads or by Rematch (ShowOffService: Duel Buddies).
function FriendDuelService.isFriendMatch(matchId: string): boolean
	return friendMatches[matchId] == true
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------

function FriendDuelService.init()
	local d = defaultDeps()
	local lobby = WorldService.lobby()
	local setGlow, bound =
		FriendDuelService.bindRings(if lobby then lobby:FindFirstChild(WorldLayout.DuelGate.model) else nil)
	if bound < #PADS then
		log:warn(`only {bound} of {#PADS} duel pad rings found: those pads work without their light`)
	end
	d.setGlow = setGlow
	FriendDuelService.useDeps(d)
	NetService.on("RematchRequest", function(player: Player)
		FriendDuelService.requestRematch(player)
	end)
	DuelService.MatchEnded:connect(FriendDuelService.handleMatchEnded)
	QueueService.Joined:connect(FriendDuelService.cancelRematch)
end

function FriendDuelService.start()
	local interval = 1 / PAD_CONFIG.checkHz
	while true do
		task.wait(interval)
		local ok, err = pcall(function(): any
			FriendDuelService.tick()
			return nil
		end)
		if not ok then
			log:error("tick failed:", err)
		end
	end
end

function FriendDuelService.playerRemoving(player: Player)
	FriendDuelService.cancelRematch(player)
end

return FriendDuelService
