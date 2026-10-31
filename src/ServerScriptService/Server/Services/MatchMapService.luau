--!strict
-- MatchMapService (server only). SPEC D14 (FFA/TDM v1, 2026-10-15): the registry of Diego's maps in Workspace.SquishyMaps
-- that Free for All / Team Deathmatch matches are played on inside the lobby server, one match per map.
-- * init() copies his sky maps (ServerStorage.SquishyMaps, NEW MAPS FINALS 2026-10-30) into the folder
--   (placeTemplates), then reads its children once (FindFirstChild, no yield). A map is a Model with the attributes Mode
--   ("TDM" / "FFA") and MapCode. Per map:
--   - centre = the model's pivot position; its floor top is the pivot's Y (floorY);
--   - footprint = its FootprintX / FootprintZ attributes (a sky map), else Config.Match.Maps.footprint[Mode] (X x Z);
--     startRadius = StormMath.startRadius(footprint);
--   - the Bounds zone the combat code reads (Types.ArenaZone): the footprint around the centre, axis-aligned, from
--     floorY + Maps.boundsBottomOffset to floorY + Maps.boundsTop (throw arcs, platforms up to 29 studs, the super
--     jump; the kill line is MovementRules' floorY + KillYOffset);
--   - Include-list RaycastParams / OverlapParams of every collidable BasePart in the map (the _COL proxies, all
--     MeshParts, and the floor), CollisionGroup Default, built once; critic fix (2026-10-15): the OverlapParams leave
--     out meshes and unions without Box collision fidelity (boxQueryParts: a box query sees a Hull ramp's whole box);
--   - the spawn pads: instances named *_Spawn_Red_* / *_Spawn_Blue_* (TDM; Red is Config.Match.teamNames[1], Blue
--     [2]) or *_Spawn_Ffa_* (FFA; the ".001" copies too), matched without case: their box (a Model's
--     GetBoundingBox, a part's CFrame and Size); the map's MatchSpawns set is built from them;
--   - the power-up pads *_PowerUp_Pad_* (positions only; unused in v1). Power-ups v1.1 (2026-10-16): also `powerUps`,
--     one PowerUpPad per pad: its instance name (the client's Collect animation finds it by name), its box centre and
--     its top (powerUpPad: the highest top of its collidable parts, Diego's *_COL; none: the box's bottom), which
--     MatchService's pickup test reads;
--   - raycast(origin, direction) -> hit position with the map's RaycastParams (MatchSpawns' storm respawn).
--   A map without the attributes, the footprint or the pads its mode needs (TDM: a Red and a Blue pad; FFA: a pad) is
--   skipped with one warning.
-- * acquire(modeId, matchId) -> a random free map of that mode (nil when every one is in use); release(record) frees it;
--   hasMode(modeId) -> whether this server has any map of that mode. A rescan keeps every map a running match holds in
--   use (review fix 2026-10-15). A map added at runtime needs a server restart: the Studio command bar has its own
--   require cache, so a scan() from there reads into a separate copy of this module.
-- The pure helpers (modeOf, padKind, boundsFor, pickFree, boxQueryParts, powerUpPad) and recordFrom on an unparented
-- model are unit-tested; useMaps(records) replaces the registry (tests).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local StormMath = require(Shared.StormMath)
local Types = require(Shared.Types)
local MatchSpawns = require(script.Parent.Parent.Logic.MatchSpawns)

-- Types

export type Zone = Types.ArenaZone
export type PadKind = "Red" | "Blue" | "Ffa" | "PowerUp"
-- Power-ups v1.1 (2026-10-16): one power-up pad: its instance name, its box centre and the height a player stands on.
export type PowerUpPad = { name: string, position: Vector3, top: number }

export type MapRecord = {
	model: Instance?,
	name: string, -- the model's name (MatchState mapName)
	code: string, -- the MapCode attribute (MatchState mapCode; the client's MapLighting / MapAnimations_<code>)
	modeId: string, -- "ffa" | "tdm" (Config.Match.Modes key)
	centre: Vector3,
	floorY: number,
	footprint: Vector3,
	startRadius: number,
	bounds: Zone,
	raycastParams: RaycastParams,
	overlapParams: OverlapParams,
	pads: { MatchSpawns.Pad },
	spawns: MatchSpawns.SpawnSet,
	powerUpPads: { Vector3 },
	powerUps: { PowerUpPad }?, -- power-ups v1.1 (the same pads, in the same order; nil in an older record)
	raycast: MatchSpawns.Raycast,
	inUse: boolean,
	matchId: string?,
}

-- Constants

-- Diego's NEW MAPS FINALS (2026-10-30): his Team / Free for All sky maps live in ServerStorage.SquishyMaps (SDTools
-- "sky_maps", each built at its own sky spot); init() copies them into Workspace.SquishyMaps, which scan() reads.
local FOLDER_NAME = "SquishyMaps"
local ATTR_FOOTPRINT_X, ATTR_FOOTPRINT_Z = "FootprintX", "FootprintZ" -- a sky map's own floor size
local ATTR_MODE = "Mode"
local ATTR_CODE = "MapCode"
local COLLISION_GROUP = "Default" -- the projectile rule of §5.3, as the duel arenas
-- Lowercased name pieces -> pad kind (SPEC D14; the first match wins).
local PAD_NAMES: { { piece: string, kind: PadKind } } = {
	{ piece = "_spawn_red", kind = "Red" },
	{ piece = "_spawn_blue", kind = "Blue" },
	{ piece = "_spawn_ffa", kind = "Ffa" },
	{ piece = "_powerup_pad", kind = "PowerUp" },
}

-- Module table

local MatchMapService = {}

-- Private

local log = Log.new("MatchMap")
local records: { MapRecord } = {}

local function boxOf(instance: Instance): (CFrame?, Vector3?)
	if instance:IsA("Model") then
		local cf, size = instance:GetBoundingBox()
		return cf, size
	elseif instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end
	return nil, nil
end

-- Every pad under `root` (a matched instance is not searched further). Power-ups v1.1: `records` gets each power-up
-- pad's PowerUpPad too.
local function collectPads(
	root: Instance,
	teams: { string },
	pads: { MatchSpawns.Pad },
	powerUps: { Vector3 },
	records: { PowerUpPad }
)
	for _, child in root:GetChildren() do
		local kind = MatchMapService.padKind(child.Name)
		local cf, size = boxOf(child)
		if kind ~= nil and cf ~= nil and size ~= nil then
			if kind == "PowerUp" then
				table.insert(powerUps, cf.Position)
				table.insert(records, MatchMapService.powerUpPad(child, cf, size))
			else
				local team = if kind == "Red" then teams[1] elseif kind == "Blue" then teams[2] else nil
				table.insert(pads, { cframe = cf, size = size, team = team })
			end
		else
			collectPads(child, teams, pads, powerUps, records)
		end
	end
end

-- Power-ups v1.1: the highest point of a part's box (any rotation), in world Y.
local function partTop(part: BasePart): number
	local cf, size = part.CFrame, part.Size
	local reach = math.abs(cf.RightVector.Y) * size.X
		+ math.abs(cf.UpVector.Y) * size.Y
		+ math.abs(cf.LookVector.Y) * size.Z
	return cf.Position.Y + reach / 2
end

local function collidableParts(model: Instance): { Instance }
	local list: { Instance } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.CanCollide then
			table.insert(list, descendant)
		end
	end
	return list
end

-- A mesh or union's collision fidelity (nil when it can't be read).
local function fidelityOf(part: Instance): EnumItem?
	local ok, fidelity = pcall(function(): any
		return (part :: any).CollisionFidelity
	end)
	return if ok and typeof(fidelity) == "EnumItem" then fidelity else nil
end

-- Critic fix (2026-10-15): the parts the box queries may see. OverlapParams queries (ThrowRules' spawn-overlap
-- fizzle, AbilityService's ult room, the movement guard's inside-cover probe) test each part's box, and a mesh's box is
-- its shape only with Box collision fidelity. Diego's ramps, stairs and round props are Hull (his import guide), so
-- their box covers the whole volume over the slope: a player on a ramp would fizzle every throw and get ult.noRoom.
-- Those meshes stay in the RaycastParams (casts test the real shape); Parts and Box meshes are kept here.
function MatchMapService.boxQueryParts(parts: { Instance }): { Instance }
	local list: { Instance } = {}
	for _, part in parts do
		local mesh = part:IsA("MeshPart") or part:IsA("PartOperation")
		if not mesh or fidelityOf(part) == Enum.CollisionFidelity.Box then
			table.insert(list, part)
		end
	end
	return list
end

local function hasTeam(pads: { MatchSpawns.Pad }, team: string): boolean
	for _, pad in pads do
		if pad.team == team then
			return true
		end
	end
	return false
end

-- Public: pure helpers (unit-tested) -----------------------------------------------------------------------------------

-- The Config.Match.Modes key of a map's Mode attribute ("TDM" -> "tdm", "FFA" -> "ffa"), or nil.
function MatchMapService.modeOf(value: unknown, cfg: any?): string?
	if type(value) ~= "string" then
		return nil
	end
	local c = cfg or Config.Match
	local modeId = string.lower(value)
	return if c.Modes[modeId] ~= nil then modeId else nil
end

-- What an instance name says it is: a Red / Blue / FFA spawn pad, a power-up pad, or nothing.
function MatchMapService.padKind(name: string): PadKind?
	local lower = "_" .. string.lower(name) -- a name that starts with "Spawn_Red" counts too
	for _, entry in PAD_NAMES do
		if string.find(lower, entry.piece, 1, true) ~= nil then
			return entry.kind
		end
	end
	return nil
end

-- The Bounds zone of a map: its footprint around the centre, from floorY + boundsBottomOffset to floorY + boundsTop.
function MatchMapService.boundsFor(centre: Vector3, floorY: number, footprint: Vector3, cfg: any?): Zone
	local maps = (cfg or Config.Match).Maps
	local bottom, top = maps.boundsBottomOffset, maps.boundsTop
	return {
		cframe = CFrame.new(centre.X, floorY + (top + bottom) / 2, centre.Z),
		size = Vector3.new(footprint.X, top - bottom, footprint.Z),
	}
end

-- Power-ups v1.1 (2026-10-16): one power-up pad's record from its instance and its box (boxOf: a Model's bounding box,
-- a part's CFrame and Size). The top a player stands on is the highest top of its collidable parts (the instance
-- itself when it is a part; Diego's pads stand on their *_COL proxy, under the floating pickup the box also holds);
-- with none, the box's bottom (a pad that does not collide lies on the floor under it).
function MatchMapService.powerUpPad(instance: Instance, cframe: CFrame, size: Vector3): PowerUpPad
	local top: number? = nil
	local parts: { Instance } = if instance:IsA("BasePart") then { instance } else instance:GetDescendants()
	for _, part in parts do
		if part:IsA("BasePart") and (part :: BasePart).CanCollide then
			local y = partTop(part :: BasePart)
			if top == nil or y > top then
				top = y
			end
		end
	end
	return {
		name = instance.Name,
		position = cframe.Position,
		top = if top ~= nil then top else cframe.Position.Y - size.Y / 2,
	}
end

-- A random free record of `modeId` (r in [0, 1)), or nil.
function MatchMapService.pickFree(list: { MapRecord }, modeId: string, r: number): MapRecord?
	local free: { MapRecord } = {}
	for _, record in list do
		if record.modeId == modeId and not record.inUse then
			table.insert(free, record)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[math.clamp(math.floor(r * #free) + 1, 1, #free)]
end

-- One map's record, or (nil, why) when it can't host a match.
function MatchMapService.recordFrom(model: Instance, cfg: any?): (MapRecord?, string?)
	local c = cfg or Config.Match
	if not model:IsA("Model") then
		return nil, "not a Model"
	end
	local modeAttribute = model:GetAttribute(ATTR_MODE)
	local modeId = MatchMapService.modeOf(modeAttribute, c)
	if modeId == nil then
		return nil, `unknown Mode {tostring(modeAttribute)}`
	end
	local footprint = c.Maps.footprint[string.upper(modeId)]
	local fx, fz = model:GetAttribute(ATTR_FOOTPRINT_X), model:GetAttribute(ATTR_FOOTPRINT_Z)
	if type(fx) == "number" and type(fz) == "number" then
		footprint = Vector3.new(fx, 0, fz) -- a sky map carries its own size (they differ per map)
	end
	if typeof(footprint) ~= "Vector3" then
		return nil, `no Config.Match.Maps.footprint for {string.upper(modeId)}`
	end
	local pads: { MatchSpawns.Pad } = {}
	local powerUps: { Vector3 } = {}
	local powerUpRecords: { PowerUpPad } = {}
	collectPads(model, c.teamNames, pads, powerUps, powerUpRecords)
	if c.Modes[modeId].teams then
		if not (hasTeam(pads, c.teamNames[1]) and hasTeam(pads, c.teamNames[2])) then
			return nil, "a Red and a Blue spawn pad are needed"
		end
	elseif #pads == 0 then
		return nil, "no FFA spawn pad"
	end
	local pivot = (model :: Model):GetPivot()
	local centre = pivot.Position
	local floorY = pivot.Y
	local include = collidableParts(model)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = include
	raycastParams.CollisionGroup = COLLISION_GROUP
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = MatchMapService.boxQueryParts(include) -- critic fix: no Hull boxes
	overlapParams.CollisionGroup = COLLISION_GROUP
	local code = model:GetAttribute(ATTR_CODE)
	local record: MapRecord = {
		model = model,
		name = model.Name,
		code = if type(code) == "string" and code ~= "" then code else model.Name,
		modeId = modeId,
		centre = centre,
		floorY = floorY,
		footprint = footprint,
		startRadius = StormMath.startRadius(footprint),
		bounds = MatchMapService.boundsFor(centre, floorY, footprint, c),
		raycastParams = raycastParams,
		overlapParams = overlapParams,
		pads = pads,
		spawns = MatchSpawns.build(pads, centre, floorY, modeId, c),
		powerUpPads = powerUps,
		powerUps = powerUpRecords,
		raycast = function(origin: Vector3, direction: Vector3): Vector3?
			local result = Workspace:Raycast(origin, direction, raycastParams)
			return if result then result.Position else nil
		end,
		inUse = false,
		matchId = nil,
	}
	return record, nil
end

-- Public: registry -----------------------------------------------------------------------------------------------------

-- Reads every map of `folder` (default Workspace.SquishyMaps) into the registry. Returns how many maps it holds. A map a
-- running match holds stays held by it (one match per map), so a rescan never frees a map in use.
function MatchMapService.scan(folder: Instance?, cfg: any?): number
	local root = folder or Workspace:FindFirstChild(FOLDER_NAME)
	local held: { [Instance]: MapRecord } = {}
	for _, old in records do
		if old.inUse and old.model ~= nil then
			held[old.model :: Instance] = old
		end
	end
	records = {}
	if root == nil then
		log:warn(`Workspace.{FOLDER_NAME} is missing: no Free for All / Team Deathmatch match can start`)
		return 0
	end
	for _, child in root:GetChildren() do
		local ok, record, why = pcall(MatchMapService.recordFrom, child, cfg)
		if ok and record then
			local old = held[child]
			if old then
				record.inUse = true
				record.matchId = old.matchId
			end
			table.insert(records, record)
		else
			log:warn(`map {child.Name} skipped: {if ok then why else record}`)
		end
	end
	log:info(`{#records} match maps ready`)
	return #records
end

-- A random free map of `modeId`, now held by `matchId`; nil when every one is in use.
function MatchMapService.acquire(modeId: string, matchId: string, r: number?): MapRecord?
	local record = MatchMapService.pickFree(records, modeId, if r ~= nil then r else math.random())
	if record then
		record.inUse = true
		record.matchId = matchId
	end
	return record
end

-- One match per server (2026-10-30): the free map whose MapCode is `code`, now held by `matchId`; nil when it is
-- missing or in use (a match server plays the map its ticket names).
function MatchMapService.acquireCode(code: string, matchId: string): MapRecord?
	for _, record in records do
		if record.code == code and not record.inUse then
			record.inUse = true
			record.matchId = matchId
			return record
		end
	end
	return nil
end

-- Frees the map. The match holds the record it acquired; a rescan since then made a new record of the same model,
-- which is freed too.
function MatchMapService.release(record: MapRecord?)
	if record == nil then
		return
	end
	local matchId = record.matchId
	record.inUse = false
	record.matchId = nil
	if matchId == nil or record.model == nil then
		return
	end
	for _, current in records do
		if current ~= record and current.model == record.model and current.matchId == matchId then
			current.inUse = false
			current.matchId = nil
		end
	end
end

function MatchMapService.hasMode(modeId: string): boolean
	for _, record in records do
		if record.modeId == modeId then
			return true
		end
	end
	return false
end

-- The registry (read-only use).
function MatchMapService.list(): { MapRecord }
	return records
end

-- Replaces the registry (tests).
function MatchMapService.useMaps(list: { MapRecord })
	records = list
end

-- Studio debug view.
function MatchMapService.debugState(): { [string]: any }
	local list = {}
	for _, record in records do
		table.insert(list, {
			name = record.name,
			code = record.code,
			modeId = record.modeId,
			pads = #record.pads,
			inUse = record.inUse,
			matchId = record.matchId,
		})
	end
	return { maps = list }
end

-- Lifecycle

-- Copies every Team / Free for All map of `templates` (ServerStorage.SquishyMaps) that `into` lacks into `into`
-- (Workspace.SquishyMaps, made when missing). Returns how many it copied. The 1v1 ones stay (ArenaService's).
function MatchMapService.placeTemplates(templates: Instance?, into: Instance?): number
	if templates == nil then
		return 0
	end
	local folder = into or Workspace:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		local made = Instance.new("Folder")
		made.Name = FOLDER_NAME
		made.Parent = Workspace
		folder = made
	end
	local copied = 0
	for _, template in templates:GetChildren() do
		local mode = template:GetAttribute(ATTR_MODE)
		if (mode == "TDM" or mode == "FFA") and (folder :: Instance):FindFirstChild(template.Name) == nil then
			template:Clone().Parent = folder
			copied += 1
		end
	end
	return copied
end

function MatchMapService.init()
	MatchMapService.placeTemplates(ServerStorage:FindFirstChild(FOLDER_NAME), nil)
	MatchMapService.scan(nil, nil)
end

return MatchMapService
