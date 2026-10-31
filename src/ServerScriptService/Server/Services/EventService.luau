--!strict
-- EventService (server only). 2026-10-31 (owner: candy rain, "Yes, build it"; LihFolk check: Grow a Garden's shared
-- timer). Runs the timed events of Shared/EventSchedule (Config.Events) in lobby servers only (a match server has no
-- hub).
-- * Candy rain: while it is live, candies (Workspace.SD_Candies, Model "Candy") drop on spots of the ring around the
--   dragon Monument, Config.Events.CandyRain.perPlayer for each player in the server spread over the event
--   (EventSchedule.candiesDue, at most MAX_PER_TICK a tick). A spot whose floor is higher than maxFloorY (a bench, a
--   stall) is skipped for another. A server that first sees an event already running spreads it over what is left.
--   Each candy carries SD_LandAt (server time): the client plays its drop until then; from then the nearest living
--   player whose SERVER root is within grabRadius gets it (EventSchedule.grabber; nothing comes from a client), at
--   most grabCap a player per event. It pays EventSchedule.candyCoins(the grabber's pen rate) through
--   EconomyService.grantCoins(.., "event"); CandyGrab tells the grabber { coins, position } for the coin flight. A
--   candy nobody grabs (or that pays nothing: a profile still loading) goes after lifeSeconds.
-- * The start of any event: one "event.<kind>Start" toast to everyone, once per event.
-- * Golden luck needs nothing here: BoxService asks EventSchedule.boxForm when it draws.
-- One Heartbeat connection, working every TICK seconds.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local EVENTS = require(Shared.Config.Events)
local EventSchedule = require(Shared.EventSchedule)
local Palette = require(Shared.Art.Palette)
local PenMath = require(Shared.PenMath)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MatchServerService = require(script.Parent.MatchServerService)
local NetService = require(script.Parent.NetService)

-- Constants

local CANDY = EVENTS.CandyRain
local TICK = 0.1
local MAX_PER_TICK = 3 -- a join mid-event adds its share over a second, not in one burst
local SPOT_TRIES = 8
local FOLDER_NAME = "SD_Candies"
local LOBBY_NAME = "SquishyDuelsLobby"
local ATTR_LAND = "SD_LandAt"
local REMOTE_GRAB = "CandyGrab"
local CODE_START_PREFIX = "event." -- + kind + "Start": Strings.event.<kind>Start
local REASON = "event"
-- Strong lobby colours: the pastel ones (and sky blue) washed out on the square's pale floor in the test games.
local COLORS = { Palette.LobbyStrawberryRed, Palette.LobbyRoyalVelvet, Palette.LobbyMint, Palette.LobbyButter }

-- Types

type Candy = { model: Model, position: Vector3, landAt: number }

-- Module table

local EventService = {}

-- Private

local random = Random.new()
local folder: Folder? = nil
local candies: { Candy } = {}
local grabs: { [Player]: number } = {} -- candies each player got this event
local eventIndex: number? = nil -- the live event this server has seen
local seenAt = 0 -- how far into that event this server first saw it (0 when it was running at the start)
local spawned = 0

-- A spot on the square's floor (the candy's centre), or nil when every try hit a prop.
local function spot(): Vector3?
	local lobby = Workspace:FindFirstChild(LOBBY_NAME)
	if lobby == nil then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { lobby }
	for _ = 1, SPOT_TRIES do
		local x, z = EventSchedule.ringPoint(random:NextNumber(), random:NextNumber())
		local hit = Workspace:Raycast(Vector3.new(x, CANDY.centre.Y + 120, z), Vector3.new(0, -200, 0), params)
		if hit and hit.Position.Y <= CANDY.maxFloorY then
			return hit.Position + Vector3.new(0, CANDY.size / 2, 0)
		end
	end
	return nil
end

-- Stand-in look until Diego draws one (his to-do): a ball in a lobby colour with the wrapper's twists through it.
local function buildCandy(position: Vector3, landAt: number): Model
	local model = Instance.new("Model")
	model.Name = "Candy"
	local color = COLORS[random:NextInteger(1, #COLORS)]
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.one * CANDY.size
	body.Color = color
	local wrap = Instance.new("Part")
	wrap.Name = "Wrap"
	wrap.Shape = Enum.PartType.Cylinder
	wrap.Size = Vector3.new(CANDY.size * 1.9, CANDY.size * 0.45, CANDY.size * 0.45)
	wrap.Color = color
	for _, part in { body, wrap } do
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = CFrame.new(position)
		part.Parent = model
	end
	model.PrimaryPart = body
	model:SetAttribute(ATTR_LAND, landAt)
	return model
end

-- The server positions of the living players who may still grab this event.
local function reachable(): { [Player]: Vector3 }
	local list: { [Player]: Vector3 } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and (grabs[player] or 0) < CANDY.grabCap then
			list[player] = root.Position
		end
	end
	return list
end

-- Pays `player` for `candy`; false when nothing was paid (the candy stays for someone else).
local function grab(player: Player, candy: Candy): boolean
	local profile = DataService.getProfile(player)
	local coins = EventSchedule.candyCoins(PenMath.rate(if profile then profile.pen else nil))
	local paid = EconomyService.grantCoins(player, coins, REASON)
	if paid <= 0 then
		return false
	end
	grabs[player] = (grabs[player] or 0) + 1
	NetService.fire(REMOTE_GRAB, player, { coins = paid, position = candy.position })
	return true
end

local function dropCandies(t: number, state: EventSchedule.State)
	-- Counted from when this server first saw the event: a server started mid-event spreads the whole share evenly over
	-- what is left of it (MAX_PER_TICK caps the pace), never a burst of what fell before it existed.
	local elapsed = (t - state.startsAt - seenAt) * EVENTS.liveSeconds / (EVENTS.liveSeconds - seenAt)
	local due = math.min(EventSchedule.candiesDue(#Players:GetPlayers(), elapsed, spawned), MAX_PER_TICK)
	for _ = 1, due do
		spawned += 1 -- counted even without a spot, so a crowded square never floods later
		local position = spot()
		if position then
			local landAt = t + CANDY.fallSeconds
			local model = buildCandy(position, landAt)
			model.Parent = folder
			table.insert(candies, { model = model, position = position, landAt = landAt })
		end
	end
end

local function tick()
	local t = Workspace:GetServerTimeNow()
	local state = EventSchedule.at(t)
	if state.live and eventIndex ~= state.index then
		eventIndex, seenAt, spawned = state.index, t - state.startsAt, 0
		table.clear(grabs)
		NetService.notifyAll(CODE_START_PREFIX .. state.kind .. "Start")
	end
	if state.live and state.kind == "candyRain" then
		dropCandies(t, state)
	end
	if #candies == 0 then
		return
	end
	local reach = reachable()
	for i = #candies, 1, -1 do
		local candy = candies[i]
		local gone = t >= candy.landAt + CANDY.lifeSeconds
		if not gone and t >= candy.landAt then
			local player = EventSchedule.grabber(candy.position, reach, CANDY.grabRadius)
			if player and grab(player, candy) then
				gone = true
				if (grabs[player] or 0) >= CANDY.grabCap then
					reach[player] = nil
				end
			end
		end
		if gone then
			candy.model:Destroy()
			table.remove(candies, i)
		end
	end
end

-- Lifecycle

function EventService.init()
	if MatchServerService.isMatchServer() then
		return
	end
	local made = Instance.new("Folder")
	made.Name = FOLDER_NAME
	made.Parent = Workspace
	folder = made
end

function EventService.start()
	if folder == nil then
		return
	end
	local waited = 0
	RunService.Heartbeat:Connect(function(dt: number)
		waited += dt
		if waited < TICK then
			return
		end
		waited = 0
		tick()
	end)
end

function EventService.playerRemoving(player: Player)
	grabs[player] = nil
end

return EventService
