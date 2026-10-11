--!strict
-- CharacterService (server only). DESIGN §2.3, §5.3, §7.6, §2.6.
-- * Lobby spawn: every player's RespawnLocation is the lobby SpawnLocation tagged SD_LobbySpawn (found through
--   WorldService in the generated lobby). Without one (world not built) Roblox's default spawning is left alone and
--   one warning is logged.
-- * Collision group: every BasePart of a character, including parts added later (accessories, tools, layered
--   clothing), is put in SD_Characters (§5.3: only characters collide with the arena dividers). If WorldService could
--   not register that group, characters stay in Default (one warning) instead of writing an unregistered name.
-- * Died: fired once per character when its Humanoid dies, with (player, character).
-- * teleportAsync(p, cf): stream-safe teleport (§5.3 arenas are ~600 studs away): asks the engine to stream the
--   target area to that player (Player:RequestStreamAroundAsync, failures ignored), then, if the same character is
--   still alive, unseats it, pivots it to `cf` and clears its velocity. Returns true when the character was moved.
-- * getRoot(p) / getHumanoid(p) / isAlive(p): the current character's HumanoidRootPart / Humanoid / Health > 0.
-- playerAdded/playerRemoving never yield (§2.6 rule 5). Combat never touches Health (§5.2); nothing here does either.

-- Services

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Cleanup = require(ReplicatedStorage.Shared.Util.Cleanup)
local Config = require(ReplicatedStorage.Shared.Config)
local Log = require(ReplicatedStorage.Shared.Util.Log)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local WorldService = require(script.Parent.WorldService)

-- Types

-- A Util/Cleanup as stored in records (its generic add<T>() trips the exact record comparison of the type checker).
type Trove = {
	add: (self: any, item: any) -> any,
	clean: (self: any) -> (),
}

type Entry = {
	player: Player,
	cleanup: Trove, -- player-lifetime connections
	character: Model?,
	characterCleanup: Trove?, -- the current character's connections
}

-- Constants

local TAG_LOBBY_SPAWN = "SD_LobbySpawn"
local ROOT_PART = "HumanoidRootPart"
local CHARACTERS_GROUP = WorldService.CollisionGroups.Characters
-- How long a teleport waits for the target area to stream to the player before moving the character anyway
-- (§5.4: RequestStreamAroundAsync(pad, 3), in pcall).
local STREAM_TIMEOUT_SECONDS = Config.Duel.Positioning.StreamAroundTimeoutSeconds

-- Module table

local CharacterService = {}

-- Fired with (player, character) once when that character's Humanoid dies.
CharacterService.Died = Signal.new() :: Signal.Signal<Player, Model>

-- Private

local log = Log.new("Character")
local entries: { [Player]: Entry } = {}
local lobbySpawn: SpawnLocation? = nil
local warnedNoSpawn = false
-- SD_Characters once WorldService registered it (checked at init); nil = leave characters in Default.
local characterGroup: string? = nil

local function liveCharacter(player: Player): Model?
	local character = player.Character
	if character and character:IsDescendantOf(Workspace) then
		return character
	end
	return nil
end

-- The lobby SpawnLocation tagged SD_LobbySpawn in the generated lobby (the first one), or nil.
local function findLobbySpawn(): SpawnLocation?
	for _, instance in WorldService.stations(TAG_LOBBY_SPAWN) do
		if instance:IsA("SpawnLocation") then
			return instance
		end
	end
	return nil
end

local function applySpawn(player: Player)
	if lobbySpawn then
		player.RespawnLocation = lobbySpawn
	elseif not warnedNoSpawn then
		warnedNoSpawn = true
		log:warn("no SD_LobbySpawn SpawnLocation in the lobby; using Roblox's default spawning")
	end
end

local function bindHumanoid(entry: Entry, character: Model, humanoid: Humanoid, c: Trove)
	local fired = false
	c:add(humanoid.Died:Connect(function()
		if fired or entry.character ~= character then
			return
		end
		fired = true
		CharacterService.Died:fire(entry.player, character)
	end))
end

local function unbindCharacter(entry: Entry)
	local c = entry.characterCleanup
	entry.characterCleanup = nil
	entry.character = nil
	if c then
		c:clean()
	end
end

local function bindCharacter(entry: Entry, character: Model)
	if entry.character == character then
		return
	end
	unbindCharacter(entry)
	local c = Cleanup.new()
	entry.character = character
	entry.characterCleanup = c :: any

	if characterGroup then
		local group = characterGroup
		CharacterService.applyCollisionGroup(character, group)
		c:add(CharacterService.watchCollisionGroup(character, group))
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		bindHumanoid(entry, character, humanoid, c :: any)
	else
		-- The Humanoid normally exists at CharacterAdded; bind it when it arrives otherwise (no yield).
		local waiting: RBXScriptConnection? = nil
		waiting = character.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Humanoid") and entry.character == character then
				if waiting then
					waiting:Disconnect()
				end
				bindHumanoid(entry, character, child, c :: any)
			end
		end)
		c:add(waiting)
	end
	c:add(character.Destroying:Connect(function()
		if entry.character == character then
			unbindCharacter(entry)
		end
	end))
end

-- Public

-- Puts every BasePart of `character` (now) in `group` (default SD_Characters). Returns how many parts it set. Parts
-- added later: watchCollisionGroup.
function CharacterService.applyCollisionGroup(character: Instance, group: string?): number
	local name = group or CHARACTERS_GROUP
	local count = 0
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = name
			count += 1
		end
	end
	return count
end

-- Puts every BasePart added to `character` from now on in `group` (default SD_Characters). Returns the connection.
function CharacterService.watchCollisionGroup(character: Instance, group: string?): RBXScriptConnection
	local name = group or CHARACTERS_GROUP
	return character.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = name
		end
	end)
end

-- The current character's HumanoidRootPart, or nil (no character, or not in the Workspace).
function CharacterService.getRoot(player: Player): BasePart?
	local character = liveCharacter(player)
	local root = if character then character:FindFirstChild(ROOT_PART) else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- The current character's Humanoid, or nil.
function CharacterService.getHumanoid(player: Player): Humanoid?
	local character = liveCharacter(player)
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

-- True when the player has a character in the Workspace whose Humanoid has Health > 0.
function CharacterService.isAlive(player: Player): boolean
	local humanoid = CharacterService.getHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0
end

-- The lobby SpawnLocation in use (nil when the lobby has none).
function CharacterService.lobbySpawn(): SpawnLocation?
	return lobbySpawn
end

-- Streams the area around `cf` to the player, then moves the same, still-alive character there (unseated, velocity
-- cleared). Yields. Returns (moved, reason?) with reason "noCharacter", "characterChanged" or "dead" when it did not
-- move. `streamTimeout` defaults to STREAM_TIMEOUT_SECONDS.
function CharacterService.teleportAsync(player: Player, cf: CFrame, streamTimeout: number?): (boolean, string?)
	local character = liveCharacter(player)
	if character == nil or CharacterService.getRoot(player) == nil then
		return false, "noCharacter"
	end
	if not CharacterService.isAlive(player) then
		return false, "dead"
	end
	local ok, err = pcall(function(): any
		player:RequestStreamAroundAsync(cf.Position, streamTimeout or STREAM_TIMEOUT_SECONDS)
		return nil
	end)
	if not ok then
		log:warn(`stream request for {player.Name} failed; teleporting anyway:`, err)
	end
	if player.Parent == nil or liveCharacter(player) ~= character then
		return false, "characterChanged"
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return false, "dead"
	end
	if humanoid.Sit then
		humanoid.Sit = false
	end
	character:PivotTo(cf)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	return true, nil
end

-- Lifecycle

function CharacterService.init()
	-- WorldService.init() ran first (layer order): the lobby index is ready and the groups are registered.
	lobbySpawn = findLobbySpawn()
	local ok, registered = pcall(function(): boolean
		return PhysicsService:IsCollisionGroupRegistered(CHARACTERS_GROUP)
	end)
	if ok and registered then
		characterGroup = CHARACTERS_GROUP
	else
		log:warn(`collision group {CHARACTERS_GROUP} is not registered; characters stay in Default`)
	end
end

function CharacterService.playerAdded(player: Player)
	if entries[player] then
		return
	end
	local c = Cleanup.new()
	local entry: Entry = { player = player, cleanup = c :: any, character = nil, characterCleanup = nil }
	entries[player] = entry
	applySpawn(player)
	c:add(player.CharacterAdded:Connect(function(character: Model)
		bindCharacter(entry, character)
	end))
	c:add(player.CharacterRemoving:Connect(function(character: Model)
		if entry.character == character then
			unbindCharacter(entry)
		end
	end))
	c:add(function()
		unbindCharacter(entry)
	end)
	local current = player.Character
	if current then
		bindCharacter(entry, current)
	end
end

function CharacterService.playerRemoving(player: Player)
	local entry = entries[player]
	if entry == nil then
		return
	end
	entries[player] = nil
	entry.cleanup:clean()
end

-- Not called by the bootstrap; used by leak checks.
function CharacterService.destroy()
	for player in table.clone(entries) do
		CharacterService.playerRemoving(player)
	end
	CharacterService.Died:disconnectAll()
end

return CharacterService
