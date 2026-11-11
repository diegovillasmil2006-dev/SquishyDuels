--!strict
-- GearLooksController (client only). Big job item 9 (2026-11-10; the owner's "Launcher and gear models: each tier its
-- own look"). The models: ReplicatedStorage.SD_Gear (tools/meshes/gear_models.py); the rules: Shared/GearLooks (pure);
-- the numbers, the owner's sheet and Claude's calls: Config/GearLooks.
-- Every client dresses every player from the replicated Player attribute SD_Gear (server-written, HighwayService):
-- * Worn on the body while in the lobby (never in a duel or a match, never dead; within wearStuds of the camera): the
--   held launcher in the left hand, the arm gear round the right lower arm, the armor round the chest. Each is a clone
--   of its tier's model, sized to its body part, every MeshPart welded to that part (a Weld whose C0 is where the piece
--   stood: nothing in the rig is touched), in Workspace.SD_ClientFx like the held squishy. The own pieces fade with
--   their body part in first person (its LocalTransparencyModifier, copied when it changes).
-- * The platform launcher: while its player is in the highway's throw area, an anchored clone on the deck floor
--   beside them (GearLooks.platformGoal), gliding after them.
-- One Anim/Scheduler "render" effect: who wears what is looked at again every refreshSeconds (a new tier, a respawn, a
-- body part the avatar loader swapped or resized, a duel, the distance); every frame the launchers follow, the own
-- pieces fade, and a piece whose body part is gone leaves at once (no loose bits at a respawn).
-- Public: init(), start(), destroy() (tests and leak checks; the bootstrap never calls it), debugState().

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local GearLooks = require(Shared.GearLooks)
local L = require(Shared.Config.GearLooks)
local Log = require(Shared.Util.Log)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)

-- Types

-- A worn piece: its body part and that part's size when it was fitted; the first-person fade it shows.
type Worn = { model: Model, part: BasePart, size: Vector3, tier: number, fade: number }
type Entry = {
	worn: { [string]: Worn }, -- by line (GearLooks.WORN)
	near: boolean, -- within the wear distance at the last look
	stand: Model?, -- the platform launcher on the deck
	standTier: number,
	side: number, -- the side it stands on (GearLooks.platformGoal)
	at: Vector3?, -- its floor point now, lane-local
}

-- Constants

local CLIENT_FX = "SD_ClientFx"
local ROOT_PART = "HumanoidRootPart"
local ATTR_PHASE = "SD_DuelPhase"
local ATTR_MATCH = "SD_MatchId"
local PLATFORM = "platform"
local OUTLINE = "Outline" -- a model's ink hull (tools/meshes/gear_models.py)
local ORIGIN = WorldLayout.Highway.origin

-- Module table

local GearLooksController = {}

-- State

local log = Log.new("GearLooks")
local cleanup: any = nil
local entries: { [Player]: Entry } = {}
local stepHandle: Scheduler.Handle? = nil
local lastRefresh = -math.huge

-- Private

local function clientFx(): Instance
	local folder = Workspace:FindFirstChild(CLIENT_FX)
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = CLIENT_FX
		created.Parent = Workspace
		folder = created
	end
	return folder :: Instance
end

local function cloneOf(line: string, tier: number): Model?
	local folder = ReplicatedStorage:FindFirstChild(GearLooks.FOLDER)
	local template = if folder then folder:FindFirstChild(GearLooks.modelName(line, tier)) else nil
	return if template and template:IsA("Model") then template:Clone() else nil
end

-- The body part a line sits on, and its entry of Config/GearLooks' mounts (R15, then R6).
local function mountOf(character: Model, line: string): (BasePart?, GearLooks.Mount?)
	for _, mount in (L :: any)[line].mounts do
		local part = character:FindFirstChild(mount.part)
		if part and part:IsA("BasePart") then
			return part, mount
		end
	end
	return nil, nil
end

-- Sizes a model axis by axis about its pivot (Model:ScaleTo only knows one number). Every piece's own axes are the
-- pivot's (the meshes are exported unturned; GearLooks_Test), so a piece's Size takes the same three numbers.
local function resize(model: Model, scale: Vector3)
	local pivot = model:GetPivot()
	for _, piece in model:GetChildren() do
		if piece:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(piece.CFrame)
			piece.Size *= scale
			piece.CFrame = pivot * (CFrame.new(rel.Position * scale) * rel.Rotation)
		end
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild(ROOT_PART) else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- The lobby: SD_DuelPhase and SD_MatchId are "" (or not set yet).
local function inLobby(player: Player): boolean
	local phase, match = player:GetAttribute(ATTR_PHASE), player:GetAttribute(ATTR_MATCH)
	return (phase == nil or phase == "") and (match == nil or match == "")
end

local function takeOff(entry: Entry, line: string)
	local worn = entry.worn[line]
	if worn then
		entry.worn[line] = nil
		worn.model:Destroy()
	end
end

local function putOn(entry: Entry, line: string, tier: number, part: BasePart, mount: GearLooks.Mount)
	local model = cloneOf(line, tier)
	if model == nil then
		return
	end
	local grip = model:GetAttribute("Grip")
	local offset, scale = GearLooks.mount(line, part.Size, mount, if typeof(grip) == "Vector3" then grip else nil)
	if scale ~= Vector3.one then
		resize(model, scale)
	end
	model:PivotTo(part.CFrame * offset)
	for _, piece in model:GetChildren() do
		if piece:IsA("BasePart") then
			local weld = Instance.new("Weld")
			weld.Part0 = part
			weld.Part1 = piece
			weld.C0 = part.CFrame:ToObjectSpace(piece.CFrame)
			weld.Parent = piece
			piece.Anchored = false
		end
	end
	model.Parent = clientFx()
	entry.worn[line] = { model = model, part = part, size = part.Size, tier = tier, fade = 0 }
end

local function removeStand(entry: Entry)
	local stand = entry.stand
	if stand then
		stand:Destroy()
	end
	entry.stand, entry.standTier, entry.at = nil, 0, nil
end

-- Moves a platform launcher toward its place beside its player (alpha 1: there at once).
local function follow(player: Player, entry: Entry, alpha: number)
	local stand, root = entry.stand, rootOf(player)
	if stand == nil or root == nil then
		return
	end
	local goal, side = GearLooks.platformGoal(ORIGIN:PointToObjectSpace(root.Position), entry.side)
	local at = entry.at
	local now = if at then at:Lerp(goal, alpha) else goal
	entry.side, entry.at = side, now
	stand:PivotTo(ORIGIN * CFrame.new(now))
end

local function clear(player: Player)
	local entry = entries[player]
	if entry == nil then
		return
	end
	entries[player] = nil
	for _, line in GearLooks.WORN do
		takeOff(entry, line)
	end
	removeStand(entry)
end

local function refresh()
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else nil
	local own = Players.LocalPlayer
	local seen: { [Player]: boolean } = {}
	for _, player in Players:GetPlayers() do
		seen[player] = true
		local entry = entries[player]
		if entry == nil then
			entry = { worn = {}, near = false, stand = nil, standTier = 0, side = 0, at = nil }
			entries[player] = entry
		end
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local root = rootOf(player)
		local near = false
		if character and humanoid and humanoid.Health > 0 and root and inLobby(player) then
			local reach = if entry.near then L.dropStuds else L.wearStuds
			near = player == own or eye == nil or (root.Position - eye).Magnitude <= reach
		end
		entry.near = near
		local tiers = GearLooks.unpack(player:GetAttribute(GearLooks.ATTRIBUTE))
		for _, line in GearLooks.WORN do
			local tier = if near then tiers[line] else 0
			local part: BasePart?, mount: GearLooks.Mount? = nil, nil
			if tier > 0 then
				part, mount = mountOf(character :: Model, line)
			end
			local worn = entry.worn[line]
			if
				worn
				and (worn.tier ~= tier or worn.part ~= part or worn.size ~= (part :: BasePart).Size or worn.model.Parent == nil)
			then
				takeOff(entry, line)
				worn = nil
			end
			if worn == nil and tier > 0 and part and mount then
				putOn(entry, line, tier, part, mount)
			end
		end
		local onDeck = near and GearLooks.onDeck(ORIGIN:PointToObjectSpace((root :: BasePart).Position), entry.stand ~= nil)
		local standTier = if onDeck then tiers[PLATFORM] else 0
		if entry.stand and entry.standTier ~= standTier then
			removeStand(entry)
		end
		if entry.stand == nil and standTier > 0 then
			local model = cloneOf(PLATFORM, standTier)
			if model then
				for _, piece in model:GetChildren() do
					if piece:IsA("BasePart") and piece.Name ~= OUTLINE then
						piece.CastShadow = true -- it stands on the floor: a shadow grounds it (the ink hull would double it)
					end
				end
				entry.stand, entry.standTier, entry.side = model, standTier, 0
				follow(player, entry, 1)
				model.Parent = clientFx()
			end
		end
	end
	for player in table.clone(entries) do
		if not seen[player] then
			clear(player)
		end
	end
end

local function step(dt: number): boolean
	local now = os.clock()
	if now - lastRefresh >= L.refreshSeconds then
		lastRefresh = now
		refresh()
	end
	local alpha = 1 - math.exp(-dt * L.platform.followRate)
	local own = Players.LocalPlayer
	for player, entry in entries do
		for line, worn in entry.worn do
			if worn.part.Parent == nil then
				takeOff(entry, line) -- the character went (a respawn): no loose pieces until the next look
			elseif player == own then
				local fade = worn.part.LocalTransparencyModifier
				if fade ~= worn.fade then
					worn.fade = fade
					for _, piece in worn.model:GetChildren() do
						if piece:IsA("BasePart") then
							piece.LocalTransparencyModifier = fade
						end
					end
				end
			end
		end
		follow(player, entry, alpha)
	end
	return true
end

-- Public

-- Studio checks: what every player shows on this client (the tiers, 0 = nothing).
function GearLooksController.debugState(): { [string]: any }
	local players: { [string]: any } = {}
	for player, entry in entries do
		local shown: { [string]: any } = { platform = entry.standTier, near = entry.near }
		for _, line in GearLooks.WORN do
			local worn = entry.worn[line]
			shown[line] = if worn then worn.tier else 0
		end
		players[tostring(player.UserId)] = shown
	end
	return { players = players, stepping = stepHandle ~= nil, enabled = L.enabled }
end

-- Lifecycle

function GearLooksController.init()
	cleanup = Cleanup.new()
end

function GearLooksController.start()
	local c = cleanup
	if c == nil or not L.enabled or stepHandle ~= nil then
		return
	end
	local lastError: any = nil
	stepHandle = Scheduler.add(function(dt: number): boolean
		local ok, why = pcall(step, dt)
		if not ok and why ~= lastError then
			lastError = why -- a failing frame is logged once, not sixty times a second
			log:error("gear looks update failed:", why)
		end
		return true
	end, "render")
	c:add(function()
		local handle = stepHandle
		if handle then
			handle:disconnect()
			stepHandle = nil
		end
		for player in table.clone(entries) do
			clear(player)
		end
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function GearLooksController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return GearLooksController
