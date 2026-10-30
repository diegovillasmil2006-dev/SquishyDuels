--!strict
-- PortalService (server only). Diego's FULL FINAL lobby (owner 2026-10-30, "Yes, start step 3"): his portal travel and
-- practice-arena safety (zip src/server/PracticePortal.server.luau, as delivered), on the game's own remote and
-- highway rules:
-- * Touching a portal's Markers.PortalTrigger (Shared/SquishyLobby/Portal.Links: the hub's Portal and HighwayPortal,
--   the arena's ReturnPortal) fires PortalTrip("enter", link) to the traveller, whose client plays the pull-in movie
--   (PortalController); after Portal.PullTime the character moves to the other portal's Markers.ArrivalSpawn and gets
--   PortalTrip("arrive", link). A player gets one trip per Portal.Cooldown.
-- * The HIGHWAY portal goes through HighwayAccessService, like the HUD's HIGHWAY button: its refusals (data not ready,
--   no character, no deck, closing, in a duel or a queue) toast before any movie, and go() picks the free deck point
--   (facing down the lane) after it; a refusal by then cancels the movie.
-- * Back from the highway: any part tagged Portal.RETURN_TAG (the LobbyPortal on the highway's deck, a copy of
--   Hub.HighwayPortal tagged HubFX.CLONE_TAG) plays the pull-in into that copy, then the player pops out of
--   Hub.HighwayPortal.
-- * Arena safety: the SafetyNet under the practice island and a height check put anyone who falls back at the arena's
--   spawn (fellOff, pure).
-- start() never runs before the lobby is in Workspace (it waits); init() only reads the lobby layout.

-- Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local HubFX = require(Shared.SquishyLobby.HubFX)
local Log = require(Shared.Util.Log)
local Portal = require(Shared.SquishyLobby.Portal)
local PracticeRange = require(Shared.SquishyLobby.PracticeRange)

local Services = script.Parent
local HighwayAccessService = require(Services.HighwayAccessService)
local NetService = require(Services.NetService)

-- Constants

local REMOTE = "PortalTrip"
local LOBBY_NAME = "SquishyDuelsLobby"
local HIGHWAY_LINK = "HighwayPortal"
local PRACTICE_LINK = "Portal"
local RETURN_LINK = "HighwayReturn"
local NOTIFY_KIND = "warn"
-- zip PracticePortal.server.luau:126-135: the height check's box round the arena centre and its drop.
local CHECK_SECONDS = 0.25
local CHECK_HALF_X = 80
local CHECK_HALF_Z = 90
local CHECK_DROP = 25

-- Module table

local PortalService = {}

-- Private

local log = Log.new("Portal")
local busy: { [Player]: boolean } = {}
local lobby: Instance? = nil

-- Where a link lands: the other portal's ArrivalSpawn, 1.5 up (zip :24-31).
local function destination(link: any): CFrame?
	local to = if lobby and link.to then HubFX.resolve(lobby, link.to) else nil
	local markers = to and to:FindFirstChild("Markers")
	local spawn = markers and markers:FindFirstChild("ArrivalSpawn")
	return if spawn and spawn:IsA("BasePart") then spawn.CFrame * CFrame.new(0, 1.5, 0) else nil
end

local function playerFrom(hit: BasePart): (Player?, Model?)
	local char = hit:FindFirstAncestorOfClass("Model")
	local player = char and Players:GetPlayerFromCharacter(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not player or busy[player] or not hum or hum.Health <= 0 then
		return nil, nil
	end
	return player, char
end

-- Diego's char:PivotTo, unseated first and stilled after (HighwayAccessService's move).
local function move(char: Model, cf: CFrame)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Sit then
		hum.Sit = false
	end
	char:PivotTo(cf)
	for _, part in char:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function release(player: Player)
	task.delay(Portal.Cooldown, function()
		busy[player] = nil
	end)
end

-- One trip through a hub or arena portal (zip :50-70); the highway's goes through HighwayAccessService.
local function trip(name: string, link: any, hit: BasePart)
	local player, char = playerFrom(hit)
	if not player or not char then
		return
	end
	if name == HIGHWAY_LINK then
		local code = HighwayAccessService.refusal(player)
		if code then
			busy[player] = true
			NetService.notify(player, code, nil, NOTIFY_KIND)
			release(player)
			return
		end
	end
	busy[player] = true
	NetService.fire(REMOTE, player, "enter", name)
	task.wait(Portal.PullTime)
	if name == HIGHWAY_LINK then
		local reply: any = HighwayAccessService.go(player)
		if reply and reply.ok then
			NetService.fire(REMOTE, player, "arrive", name)
		else
			NetService.fire(REMOTE, player, "cancel", name)
			if reply and type(reply.reason) == "string" then
				NetService.notify(player, reply.reason, nil, NOTIFY_KIND)
			end
		end
	else
		local cf = destination(link)
		if not cf then
			log:warn(`{name}: no destination`)
			NetService.fire(REMOTE, player, "cancel", name)
		elseif player.Parent and char.Parent then
			move(char, cf)
			if name == PRACTICE_LINK then
				PracticeRange.resetScore(player) -- zip :66: a fresh score on every trip to the arena
			end
			NetService.fire(REMOTE, player, "arrive", name)
		end
	end
	release(player)
end

-- Highway -> lobby (zip :73-104): a RETURN_TAG part inside a portal copy plays the pull-in into it; any other one
-- flashes out. Either way the player pops out of Hub.HighwayPortal.
local function portalModelOf(part: BasePart): Instance?
	local markers = part.Parent
	local m = if markers and markers.Name == "Markers" then markers.Parent else nil
	return if m and m:IsA("Model") and m:FindFirstChild("Markers") and (m :: any).Markers:FindFirstChild("PortalCenter")
		then m
		else nil
end

local function hookReturn(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	part.CanTouch = true
	local pm = portalModelOf(part)
	part.Touched:Connect(function(hit: BasePart)
		local player, char = playerFrom(hit)
		if not player or not char then
			return
		end
		busy[player] = true
		if pm then
			NetService.fire(REMOTE, player, "enter", RETURN_LINK)
			task.wait(Portal.PullTime)
		else
			NetService.fire(REMOTE, player, "leave", RETURN_LINK)
			task.wait(0.4)
		end
		local cf = destination(Portal.Links[RETURN_LINK])
		if cf and player.Parent and char.Parent then
			move(char, cf)
			NetService.fire(REMOTE, player, "arrive", RETURN_LINK)
		else
			NetService.fire(REMOTE, player, "cancel", RETURN_LINK)
		end
		release(player)
	end)
end

-- Public: pure ------------------------------------------------------------------------------------------------------

-- The arena height check (zip :133-135): inside the box round the arena centre and more than CHECK_DROP under its floor.
function PortalService.fellOff(position: Vector3, center: Vector3, floorY: number): boolean
	local d = position - center
	return math.abs(d.X) < CHECK_HALF_X and math.abs(d.Z) < CHECK_HALF_Z and position.Y < floorY - CHECK_DROP
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function PortalService.start()
	local found = Workspace:WaitForChild(LOBBY_NAME)
	lobby = found
	for name, link in Portal.Links do
		if not link.from then
			continue
		end
		local from = HubFX.resolve(found, link.from)
		local markers = from and from:FindFirstChild("Markers")
		local trigger = markers and markers:FindFirstChild("PortalTrigger")
		if not trigger or not trigger:IsA("BasePart") then
			log:warn(`no PortalTrigger for {name}`)
			continue
		end
		trigger.CanTouch = true
		trigger.Touched:Connect(function(hit: BasePart)
			trip(name, link, hit)
		end)
	end
	for _, part in CollectionService:GetTagged(Portal.RETURN_TAG) do
		hookReturn(part)
	end
	CollectionService:GetInstanceAddedSignal(Portal.RETURN_TAG):Connect(hookReturn)

	-- Arena safety (zip :108-138): the force-field walls block the edges; these catch anything that slips through.
	local arena = found:FindFirstChild("PracticeArena")
	local returnPortal = arena and arena:FindFirstChild("ReturnPortal")
	local arenaMarkers = arena and arena:FindFirstChild("Markers")
	if not (returnPortal and arenaMarkers) then
		log:warn("no PracticeArena: no arena safety")
	else
		local spawnCF = (returnPortal :: any).Markers.ArrivalSpawn.CFrame * CFrame.new(0, 1.5, 0)
		local center = (arenaMarkers :: any).ArenaCenter.Position
		local function rescue(char: Model)
			char:PivotTo(spawnCF)
			local root = char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
		local net = arenaMarkers:FindFirstChild("SafetyNet")
		if net and net:IsA("BasePart") then
			net.CanTouch = true
			net.Touched:Connect(function(hit: BasePart)
				local char = hit:FindFirstAncestorOfClass("Model")
				if char and Players:GetPlayerFromCharacter(char) then
					rescue(char)
				end
			end)
		end
		local acc = 0
		RunService.Heartbeat:Connect(function(dt: number)
			acc += dt
			if acc < CHECK_SECONDS then
				return
			end
			acc = 0
			for _, p in Players:GetPlayers() do
				local char = p.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if char and root and root:IsA("BasePart") and PortalService.fellOff(root.Position, center, center.Y) then
					rescue(char)
				end
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		busy[p] = nil
	end)
end

return PortalService
