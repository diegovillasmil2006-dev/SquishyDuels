--!strict
-- WorldService (server only). DESIGN §2.3, §5.3, §1.7, §2.9, §7.7.
-- * init() registers the collision groups of §5.3 (plus SD_Barrier) through PhysicsService and sets their
--   collidability:
--     SD_Characters  set on character descendants (by CharacterService); collides as Default does, and with
--                    SD_Divider and SD_Barrier; never with SD_Cosmetic
--     SD_Divider     the invisible arena divider walls; collides ONLY with SD_Characters (projectiles are analytic
--                    and pass through)
--     SD_Barrier     the arena's other invisible walls and its ceiling (reading, not in §5.3's list): collides ONLY
--                    with SD_Characters, so Default-group projectile rays skip them (Roblox ignores CanQuery = false
--                    on a colliding part)
--     SD_Cosmetic    held squishies and VFX (set by the SquishyBuilder); collides with nothing, itself included
--   Registration happens at runtime, so it never edits the place.
-- * init() then finds the generated roots (§1.5, §1.7): Workspace.SD_Lobby (SD_GeneratorId "lobby") and
--   ServerStorage.SD_Templates.Arena_CandyCourt ("arena"). A root counts only when it carries the generator marks
--   (tag SD_Generated + the matching SD_GeneratorId); a marked root under another name in the same place is accepted
--   too. If one is missing it logs "World not built: run the generator" once and sets the Workspace attribute
--   SD_WorldMissing = true (false when both exist). Dependent features ask worldReady() / arenaTemplate() and
--   disable themselves honestly (queue.unavailable, §1.7).
-- * The design arenas (phase 4 spec 2026-10-11 §5.3): every World/Arenas arena besides Candy Court whose template
--   (SD_Templates.<templateName>, or any child there) carries its generator marks and SD_ArenaId = its id is in
--   arenaTemplates() with Candy Court, so ArenaService can pick it. One that is missing is logged once ("not in the
--   rotation") and never blocks worldReady(), which still needs only the lobby and Candy Court.
-- * The runtime NEVER builds or rebuilds the world (§1.2 #6): this module creates no world instances.
-- * Lookups are indexed once from the lobby root (the server always has the whole place; nothing streams out):
--   station(id) is the lobby instance whose StationId attribute is `id` (squeeze stations, §2.9); stations(tag) the
--   lobby instances with that tag; inZone(p, tag) whether the player's HumanoidRootPart is inside one of the lobby
--   volumes with that tag (a BasePart's oriented box, or a Model's bounding box). Instances outside the lobby root
--   (Workspace.SD_Manual, arena clones) are never returned. Arena children are addressed by path (§2.9).
-- init() never yields.

-- Services

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Arenas = require(ReplicatedStorage.Shared.World.Arenas)
local Log = require(ReplicatedStorage.Shared.Util.Log)

-- Types

-- The part of PhysicsService this module uses (a fake with the same methods works in unit tests).
export type PhysicsLike = {
	IsCollisionGroupRegistered: (self: any, name: string) -> boolean,
	RegisterCollisionGroup: (self: any, name: string) -> (),
	CollisionGroupSetCollidable: (self: any, name1: string, name2: string, collidable: boolean) -> (),
	GetRegisteredCollisionGroups: (self: any) -> { any },
}

-- What findRoots() found. `missing` lists the generator ids whose root is absent ("lobby", "arena"); `arenas` holds
-- every arena template found by World/Arenas id (Candy Court as "candy_court"), `missingArenas` the design arena ids
-- not found (in World/Arenas order).
export type Roots = {
	lobby: Instance?,
	arena: Instance?,
	arenas: { [string]: Instance },
	missing: { string },
	missingArenas: { string },
}

-- Constants

local DEFAULT_GROUP = "Default"
local TAG_GENERATED = "SD_Generated"
local ATTR_GENERATOR_ID = "SD_GeneratorId"
local ATTR_ARENA_ID = "SD_ArenaId"
local ATTR_STATION_ID = "StationId"
local ATTR_WORLD_MISSING = "SD_WorldMissing"
local LOBBY_NAME = "SD_Lobby"
local LOBBY_ID = "lobby"
local TEMPLATES_NAME = "SD_Templates"
local ARENA_NAME = "Arena_CandyCourt"
local ARENA_ID = "arena"
local ROOT_PART = "HumanoidRootPart"

-- Module table

local WorldService = {}

-- Collision group names (§5.3). Read-only.
WorldService.CollisionGroups = table.freeze({
	Characters = "SD_Characters",
	Divider = "SD_Divider",
	Barrier = "SD_Barrier",
	Cosmetic = "SD_Cosmetic",
})

-- Where the generated roots live (§1.5). Read-only.
WorldService.Roots = table.freeze({
	lobby = table.freeze({ container = "Workspace", name = LOBBY_NAME, generatorId = LOBBY_ID }),
	arena = table.freeze({ container = "ServerStorage." .. TEMPLATES_NAME, name = ARENA_NAME, generatorId = ARENA_ID }),
})

-- Private

local log = Log.new("World")
local GROUPS = WorldService.CollisionGroups

local lobbyRoot: Instance? = nil
local arenaRoot: Instance? = nil
local arenaRoots: { [string]: Instance } = {} -- every arena template by World/Arenas id
local byTag: { [string]: { Instance } } = {}
local byStationId: { [string]: Instance? } = {}

-- Every registered group name (Default included), whatever else the place registered.
local function registeredNames(physics: PhysicsLike): { string }
	local names = { DEFAULT_GROUP }
	for _, info in physics:GetRegisteredCollisionGroups() do
		local name = if type(info) == "table" then info.name else nil
		if type(name) == "string" and not table.find(names, name) then
			table.insert(names, name)
		end
	end
	return names
end

-- True when `instance` carries the generator marks of `generatorId` (§1.7 root markers).
local function isGeneratedRoot(instance: Instance, generatorId: string): boolean
	return instance:HasTag(TAG_GENERATED) and instance:GetAttribute(ATTR_GENERATOR_ID) == generatorId
end

-- The marked root of `generatorId` among `container`'s children: the child named `name` first, then any other
-- marked child.
local function findMarkedChild(container: Instance?, name: string, generatorId: string): Instance?
	if container == nil then
		return nil
	end
	local named = container:FindFirstChild(name)
	if named and isGeneratedRoot(named, generatorId) then
		return named
	end
	for _, child in container:GetChildren() do
		if isGeneratedRoot(child, generatorId) then
			return child
		end
	end
	return nil
end

-- The design arena template of `def` among `container`'s children: the child named def.templateName first, then any
-- other child, as long as it carries def's generator marks and SD_ArenaId = def.id.
local function findArenaTemplate(container: Instance?, def: Arenas.ArenaDef): Instance?
	if container == nil then
		return nil
	end
	local function matches(child: Instance): boolean
		return isGeneratedRoot(child, def.generatorId) and child:GetAttribute(ATTR_ARENA_ID) == def.id
	end
	local named = container:FindFirstChild(def.templateName)
	if named and matches(named) then
		return named
	end
	for _, child in container:GetChildren() do
		if matches(child) then
			return child
		end
	end
	return nil
end

-- Builds the tag and StationId indexes from the lobby root (one pass).
local function index(root: Instance?)
	byTag = {}
	byStationId = {}
	if root == nil then
		return
	end
	local function visit(instance: Instance)
		local tags = instance:GetTags()
		if #tags == 0 then
			return
		end
		for _, tag in tags do
			local list = byTag[tag]
			if list == nil then
				list = {}
				byTag[tag] = list
			end
			table.insert(list, instance)
		end
		local stationId = instance:GetAttribute(ATTR_STATION_ID)
		if type(stationId) == "string" then
			if byStationId[stationId] == nil then
				byStationId[stationId] = instance
			else
				log:warn(`duplicate StationId {stationId} in the lobby; the first one is used`)
			end
		end
	end
	visit(root)
	for _, descendant in root:GetDescendants() do
		visit(descendant)
	end
	-- Deterministic order: by StationId when present, else by full name.
	for _, list in byTag do
		table.sort(list, function(a: Instance, b: Instance): boolean
			local ia, ib = a:GetAttribute(ATTR_STATION_ID), b:GetAttribute(ATTR_STATION_ID)
			if type(ia) == "string" and type(ib) == "string" and ia ~= ib then
				return ia < ib
			end
			return a:GetFullName() < b:GetFullName()
		end)
	end
end

-- Public

-- Registers the §5.3 groups and SD_Barrier (when missing) and applies their collidability. Returns the problems found
-- (an empty list = every rule applied). Used by init() with the real PhysicsService; tests pass a fake.
function WorldService.applyCollisionRules(physics: PhysicsLike): { string }
	local problems: { string } = {}
	for _, name in { GROUPS.Characters, GROUPS.Divider, GROUPS.Barrier, GROUPS.Cosmetic } do
		if not physics:IsCollisionGroupRegistered(name) then
			local ok, err = pcall(function(): any
				physics:RegisterCollisionGroup(name)
				return nil
			end)
			if not ok then
				table.insert(problems, `could not register collision group {name}: {err}`)
			end
		end
	end
	if #problems > 0 then
		return problems
	end

	local function set(a: string, b: string, collidable: boolean)
		local ok, err = pcall(function(): any
			physics:CollisionGroupSetCollidable(a, b, collidable)
			return nil
		end)
		if not ok then
			table.insert(problems, `could not set {a} x {b} = {collidable}: {err}`)
		end
	end

	for _, name in registeredNames(physics) do
		-- Cosmetic collides with nothing (itself included).
		set(GROUPS.Cosmetic, name, false)
		-- The divider and the other arena barriers collide only with characters.
		set(GROUPS.Divider, name, name == GROUPS.Characters)
		set(GROUPS.Barrier, name, name == GROUPS.Characters)
	end
	-- Characters behave like Default otherwise: the floor, each other.
	set(GROUPS.Characters, DEFAULT_GROUP, true)
	set(GROUPS.Characters, GROUPS.Characters, true)
	return problems
end

-- Finds the generated roots below the given containers (the real Workspace and ServerStorage at boot; plain folders
-- in tests). Never creates anything.
function WorldService.findRoots(workspaceLike: Instance, serverStorageLike: Instance): Roots
	local lobby = findMarkedChild(workspaceLike, LOBBY_NAME, LOBBY_ID)
	local templates = serverStorageLike:FindFirstChild(TEMPLATES_NAME)
	local arena = findMarkedChild(templates, ARENA_NAME, ARENA_ID)
	local missing: { string } = {}
	if lobby == nil then
		table.insert(missing, LOBBY_ID)
	end
	if arena == nil then
		table.insert(missing, ARENA_ID)
	end
	local arenas: { [string]: Instance } = {}
	local missingArenas: { string } = {}
	if arena ~= nil then
		arenas[Arenas.DEFAULT_ID] = arena
	end
	for _, id in Arenas.ids do
		if id == Arenas.DEFAULT_ID then
			continue
		end
		local found = findArenaTemplate(templates, Arenas.byId[id])
		if found then
			arenas[id] = found
		else
			table.insert(missingArenas, id)
		end
	end
	return { lobby = lobby, arena = arena, arenas = arenas, missing = missing, missingArenas = missingArenas }
end

-- Uses these roots for every lookup (init() passes what findRoots() found; tests pass in-memory trees). nil clears.
-- `arenas` (arena id -> template) defaults to Candy Court alone. Never writes attributes or logs.
function WorldService.useWorld(lobby: Instance?, arena: Instance?, arenas: { [string]: Instance }?)
	lobbyRoot = lobby
	arenaRoot = arena
	if arenas ~= nil then
		arenaRoots = table.clone(arenas)
	else
		arenaRoots = {}
		if arena ~= nil then
			arenaRoots[Arenas.DEFAULT_ID] = arena
		end
	end
	index(lobby)
end

function WorldService.init()
	for _, problem in WorldService.applyCollisionRules(PhysicsService :: any) do
		log:error(problem)
	end
	local roots = WorldService.findRoots(Workspace, ServerStorage)
	WorldService.useWorld(roots.lobby, roots.arena, roots.arenas)
	local missing = #roots.missing > 0
	Workspace:SetAttribute(ATTR_WORLD_MISSING, missing)
	if missing then
		log:warn(`World not built: run the generator (missing: {table.concat(roots.missing, ", ")})`)
	end
	if #roots.missingArenas > 0 then
		log:warn(`arena templates not built, not in the rotation: {table.concat(roots.missingArenas, ", ")}`)
	end
end

-- True when both generated roots (lobby and arena template) exist.
function WorldService.worldReady(): boolean
	return lobbyRoot ~= nil and arenaRoot ~= nil
end

-- The generated lobby root (Workspace.SD_Lobby), or nil when it is missing.
function WorldService.lobby(): Instance?
	return lobbyRoot
end

-- The arena template (ServerStorage.SD_Templates.Arena_CandyCourt), or nil when it is missing. Clone it; never
-- change it (ArenaService, §5.3).
function WorldService.arenaTemplate(): Instance?
	return arenaRoot
end

-- Every arena template by World/Arenas id: Candy Court ("candy_court") and the design arenas found (a new table).
-- Clone them; never change them (ArenaService).
function WorldService.arenaTemplates(): { [string]: Instance }
	return table.clone(arenaRoots)
end

-- The lobby instance whose StationId attribute is `id` ("squeeze_01"...), or nil.
function WorldService.station(id: string): Instance?
	return byStationId[id]
end

-- Every lobby instance with `tag` (a new list; ordered by StationId, then by full name). Empty when none.
function WorldService.stations(tag: string): { Instance }
	local list = byTag[tag]
	return if list then table.clone(list) else {}
end

-- True when `point` is inside `volume`: a BasePart's oriented box, or a Model's bounding box. Other classes: false.
function WorldService.containsPoint(volume: Instance, point: Vector3): boolean
	local cframe: CFrame, size: Vector3
	if volume:IsA("BasePart") then
		cframe, size = volume.CFrame, volume.Size
	elseif volume:IsA("Model") then
		cframe, size = volume:GetBoundingBox()
	else
		return false
	end
	local localPoint = cframe:PointToObjectSpace(point)
	local half = size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

-- The first lobby volume with `tag` that contains `point`, or nil.
function WorldService.zoneAt(point: Vector3, tag: string): Instance?
	local list = byTag[tag]
	if list == nil then
		return nil
	end
	for _, volume in list do
		if WorldService.containsPoint(volume, point) then
			return volume
		end
	end
	return nil
end

-- True when the player's character root (server position) is inside a lobby volume with `tag` (e.g.
-- SD_PracticeZone). False without a character or root.
function WorldService.inZone(player: Player, tag: string): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild(ROOT_PART) else nil
	if root == nil or not root:IsA("BasePart") then
		return false
	end
	return WorldService.zoneAt(root.Position, tag) ~= nil
end

return WorldService
