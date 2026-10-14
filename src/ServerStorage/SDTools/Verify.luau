--!strict
-- Verify: checks a generated tree against its DESIGN contract (§1.7 step 4). Server only, Edit mode only
-- (ServerStorage.SDTools). Main runs verify() on the new, UNPARENTED tree before the swap: any problem aborts the
-- build with the place unchanged. Pure inspection: it never changes, parents or destroys anything.
-- The expectations are restated from DESIGN (§5.3, §7.6-§7.8, §8.1, §17.6, §18.5.1) instead of read from the
-- builders, so a builder that drifts from the contract is caught. What DESIGN keeps in World/WorldLayout is read from
-- there: the GripTier of every squeeze station. The giant pads, their Jelly gates and pod signs went in build plan
-- Phase 6 (their checks with them).
--
-- API
--   Verify.verify(target, root, deps?) -> { string }   one line per problem; empty means OK. Targets: "shapes",
--     "lobby", "capsules" (build plan Phase 4), "arena" (Candy Court) and the 5 design arenas
--     "arena_sweetshop_stadium", "arena_pinewood_camp", "arena_pillow_fort_park", "arena_bubble_reef_court",
--     "arena_arcade_toyworks" (phase 4 spec 2026-10-11 §5.4): every arena target meets the same gameplay rules;
--     ARENA_CONTRACTS holds what differs per target
--     deps.Shared       the injected Shared clone; "lobby" requires Strings and World/WorldLayout from it, "capsules"
--                       Catalog
--     deps.Strings      a Strings-like table (resolve(key) -> string?); takes precedence over deps.Shared
--     deps.WorldLayout  a WorldLayout-like table; takes precedence over deps.Shared (unit tests pass fakes)
--     deps.Catalog      a Catalog-like table (list() -> { {id} }); takes precedence over deps.Shared
--   Verify.afterSwap(target, root) -> { string }   checks that need the tree inside Workspace. Main runs it after the
--     swap and reports the lines as warnings without rolling back. Only "lobby" has them: the keep-clear test through
--     Workspace:GetPartBoundsInBox, which also sees parts no generator owns (e.g. the team's Workspace.SD_Manual),
--     and templateLeftovers.
--   Verify.templateLeftovers(workspaceLike, lobbyRoot) -> { string }   the place template's leftovers next to the
--     lobby (§1.9 #4, PROGRESS Part 3): a SpawnLocation outside the lobby root, or a part outside it whose top face
--     lies on the lobby floor plane (Y 0) across the lobby footprint, e.g. the template Baseplate (its top is Y 0, so
--     the two floors z-fight). Warnings only.
--   Verify.boxesOverlap(cfA, sizeA, cfB, sizeB, epsilon?) -> boolean   oriented boxes overlapping by more than
--     epsilon studs (separating-axis test)
--
-- Spatial checks before the swap: Workspace spatial queries only see parts inside Workspace, and the tree verified
-- here is unparented (the arena template never enters Workspace at all). So the keep-clear and open-lane tests apply
-- GetPartBoundsInBox's own rule (a part counts by its bounding box, i.e. its CFrame and Size) in plain Luau. A part
-- must reach more than OVERLAP_EPSILON into a volume: faces that only touch do not count.
--
-- Squish Island (lobby bases spec 2026-10-11 §2-§4, §7; Phase 4): 10 plots, each one SD_Base Model with a unique Plot
-- 1..10 holding exactly one SD_BaseSpawn SpawnLocation of its own plot (Neutral, Duration 0) and none of another; every
-- SD_BaseTint is "full" or "light"; the §7 render rules (nothing but a SpawnLocation is touched, parts under 2 studs
-- cast no shadow); the island's part budget (5,200).
-- Capsules (lobby bases spec §4, §5.1, §7; big-number progression spec §4): a Folder "Capsules" holding exactly
-- Capsule_<look> for the 10 tier looks (SD_Look = the look, SD_SeatY > 0, a live "Level" TextLabel, at most 16
-- parts), the Lock (a live "Price" TextLabel, at most 12 parts), and Squishy_<id> and Statue_<id> for every Catalog
-- squishy (at most 12 parts each); every part anchored, never touched, no shadow under 2 studs; no scripts.
--
-- Lobby keep-clear rule (§7.7 props rules 1, 3, 5): every SD_KeepClear part (like every SD_AudioZone part) is
-- invisible with CanCollide, CanQuery and CanTouch false, and no colliding part reaches into it, except
--   * floor coverings: parts whose top is at or below Y 0.5 (base slab, rugs, mats, carpet);
--   * station bodies: a part that carries a station tag (STATION_TAGS), or whose nearest ancestor Model below the
--     root holds a station-tagged instance (on itself or a descendant). Decor kept in its own Model is never exempt;
--   * SD_Boundary walls and SD_KeepClear volumes.
--
-- WorldLayout shapes accepted (any of these works):
--   tiers  WorldLayout.stationTier(stationId) -> number; or a station table in Stations / SqueezeStations / stations /
--          squeezeStations: a map stationId -> entry, or an array of entries with id / stationId / StationId; the
--          tier is entry.gripTier / GripTier / tier
-- Relative requires only (Shared modules come from deps).

local Workspace = game:GetService("Workspace")

local Generated = require(script.Parent.Generated)

-- Types

export type Deps = {
	Shared: Instance?,
	Strings: any?,
	WorldLayout: any?,
	Catalog: any?,
}

-- Problem collector: lines grouped by a short category so a repeated problem is listed at most MAX_LINES_PER_KEY
-- times, followed by one "... and N more" line.
type Report = {
	lines: { string },
	counts: { [string]: number },
}

-- WorldLayout, normalized.
type Layout = {
	tierOf: (stationId: string) -> number?,
}

type Range = { number } -- { min, max }

type ZoneSpec = {
	name: string,
	x: Range,
	z: Range,
	y: Range?,
}

type BoxSpec = {
	label: string,
	center: Vector3,
	size: Vector3,
	group: string, -- the collision group the barrier must be in
}

type TagCount = {
	tag: string,
	count: number,
}

-- What one arena target must meet besides the rules every arena shares (frame, barriers, zones, pads, lane, symmetry).
type ArenaContract = {
	rootName: string,
	arenaId: string?, -- the root's SD_ArenaId (design arenas); nil: not checked
	lowCover: boolean, -- cover Models carry SD_CoverKind; "low" ones top out at LOW_COVER_TOP (spec §4.2 R3)
	ownAxesWidth: boolean, -- a cover piece's width is measured along its Body's turn (R2), not the arena's axes
	maxDecorParts: number,
	maxSurfaceGuis: number?,
}

-- Constants

local MAX_LINES_PER_KEY = 8
local POSITION_TOLERANCE = 0.05 -- studs
local SIZE_TOLERANCE = 0.05 -- studs
local OVERLAP_EPSILON = 0.01 -- studs a part must reach into a volume to count
local DIRECTION_DOT = 0.99 -- cos(≈ 8°)

-- shapes (§8.1 rule 2)
local SHAPES_ROOT_NAME = "SD_ShapeLibrary"
local ROUNDED_BOX_NAME = "RoundedBox"
local ROUNDED_BOX_SIZE = Vector3.new(2, 2, 2)

-- Tags and attributes (§2.9, §17.10)
local TAG_SQUEEZE = "SD_SqueezeStation"
local TAG_PRACTICE_TARGET = "SD_PracticeTarget"
local TAG_PEDESTAL = "SD_CollectionPedestal"
local TAG_RETURN_POINT = "SD_ReturnPoint"
local TAG_BOX_STAND = "SD_BoxStand"
local TAG_SPAWN = "SD_LobbySpawn"
local TAG_SIGN = "SD_Sign"
local TAG_AUDIO_ZONE = "SD_AudioZone"
local TAG_KEEP_CLEAR = "SD_KeepClear"
local TAG_BOUNDARY = "SD_Boundary"
local TAG_AMBIENT = "SD_Ambient" -- lobby background motion (§18.5.1 A8)
local TAG_BASE = "SD_Base" -- a plot's Model (lobby bases spec §4)
local TAG_BASE_SPAWN = "SD_BaseSpawn" -- a plot's SpawnLocation
local ATTR_PLOT = "Plot"
local ATTR_BASE_TINT = "SD_BaseTint" -- "full" | "light": BaseService colours the part with its plot's colour
local ATTR_TEXT_KEY = "SD_TextKey"
local ATTR_AMBIENT_KIND = "SD_AmbientKind"
local ATTR_STATION_ID = "StationId"
local ATTR_GRIP_TIER = "GripTier"

-- lobby (§7.5-§7.7, §17.6)
local LOBBY_ROOT_NAME = "SD_Lobby"
local LOBBY_MAX_PARTS = 5200 -- lobby bases spec §7: the whole island (the plots' capsules come at runtime)
local LOBBY_MAX_SURFACE_GUIS = 64 -- phase 3 (D6): the design lobby's plates
local LOBBY_PEDESTALS = 14 -- phase 3 (D4): the design's curved shelf holds every squishy (lobby.js:278)
local LOBBY_MAX_LIGHTS = 8
local LOBBY_MAX_EMITTERS = 3
local MAX_ATOMIC_EXTENT = 64 -- studs: an Atomic station model streams as one piece
local WALKABLE_TOP = 0.5 -- parts whose top is at or below this are floor coverings (§7.7 rule 3)
local SQUEEZE_STATIONS = 6 -- squeeze_01..06, the Foam Mats (the giant pads' squeeze_07..09 went in Phase 6)
local PRACTICE_TARGETS = 4 -- lobby bases spec §3: 3 dummies and the moving target
local LOBBY_BASES = 10 -- lobby bases spec §2: 10 plots
local SMALL_PART = 2 -- lobby bases spec §7: parts under 2 studs cast no shadow
local STATION_ID_PATTERN = "^squeeze_%d%d$"
local AUDIO_ZONE_IDS = { "lobby", "squeeze", "practice" }
-- §18.5.1 A8: the 4 lollipops (spin), the daily gift box (spinBob), the counter gift box and the statue (breathe).
local AMBIENT_DECOR = 7
local AMBIENT_KINDS: { [string]: boolean } = { spin = true, spinBob = true, breathe = true }
local LOBBY_TAG_COUNTS: { TagCount } = {
	{ tag = TAG_SPAWN, count = 1 },
	{ tag = TAG_SQUEEZE, count = SQUEEZE_STATIONS },
	{ tag = "SD_PracticeZone", count = 1 },
	{ tag = TAG_PRACTICE_TARGET, count = PRACTICE_TARGETS },
	{ tag = "SD_QueuePodium", count = 1 },
	{ tag = "SD_QueueBoard", count = 1 },
	{ tag = TAG_BOX_STAND, count = 1 },
	{ tag = "SD_ShopCounter", count = 1 },
	{ tag = "SD_CollectionKiosk", count = 1 },
	{ tag = TAG_PEDESTAL, count = LOBBY_PEDESTALS },
	{ tag = "SD_QuestBoard", count = 1 },
	{ tag = "SD_DailyStand", count = 1 },
	{ tag = TAG_RETURN_POINT, count = 2 },
	{ tag = TAG_BOUNDARY, count = 4 },
	{ tag = TAG_AUDIO_ZONE, count = #AUDIO_ZONE_IDS },
	{ tag = TAG_AMBIENT, count = AMBIENT_DECOR },
	{ tag = TAG_BASE, count = LOBBY_BASES },
	{ tag = TAG_BASE_SPAWN, count = LOBBY_BASES },
}

-- capsules (lobby bases spec §4, §5.1, §7; big-number progression spec §4)
local CAPSULES_ROOT_NAME = "Capsules"
-- Progression spec §4: the 10 tier looks, in tier order (Config.Grip.Capsule.Tiers keys).
local CAPSULE_LOOKS =
	{ "foam", "jelly", "marshmallow", "gummy", "taffy", "caramel", "bubblegum", "rainbow", "crystal", "royal" }
local CAPSULE_MAX_PARTS = 16 -- spec §5.1: "about 16 parts"
local LOCK_MAX_PARTS = 12
local SQUISHY_MAX_PARTS = 12 -- spec §7 budget: a low-detail squishy or statue
local ATTR_LOOK = "SD_Look"
local ATTR_SEAT = "SD_SeatY"
-- Tags whose instances are station bodies (exempt from the keep-clear test, see the header).
local STATION_TAGS = {
	TAG_SPAWN,
	TAG_SQUEEZE,
	"SD_PracticeZone",
	TAG_PRACTICE_TARGET,
	"SD_QueuePodium",
	"SD_QueueBoard",
	TAG_BOX_STAND,
	"SD_ShopCounter",
	"SD_CollectionKiosk",
	TAG_PEDESTAL,
	"SD_QuestBoard",
	"SD_DailyStand",
	TAG_RETURN_POINT,
}
local PRACTICE_TARGET_ATTRIBUTES = {
	{ name = "Distance", kind = "number" },
	{ name = "Moving", kind = "boolean" },
	{ name = "RailLength", kind = "number" },
	{ name = "Period", kind = "number" },
}

-- arena (§5.3, §7.8)
local ARENA_CHILDREN = { "Origin", "Geometry", "Zones", "Spawns", "Decor", "Runtime" }
local ARENA_MAX_PARTS = 400
local COVER_PIECES = 12
local COVER_MIN_TOP = 8
local COVER_MAX_WIDTH = 8
-- Design arenas (phase 4 spec 2026-10-11 §4.2, §5.4): low "half cover" may be hopped on (D2), Decor holds the
-- out-of-bounds dressing, SurfaceGuis carry emblems and signs.
local LOW_COVER_TOP = { 3, 5 }
local ATTR_ARENA_ID = "SD_ArenaId"
local ATTR_COVER_KIND = "SD_CoverKind"
local DESIGN_ARENA_MAX_DECOR_PARTS = 260
local DESIGN_ARENA_MAX_SURFACE_GUIS = 24
local function designArena(rootName: string, arenaId: string): ArenaContract
	return {
		rootName = rootName,
		arenaId = arenaId,
		lowCover = true,
		ownAxesWidth = true,
		maxDecorParts = DESIGN_ARENA_MAX_DECOR_PARTS,
		maxSurfaceGuis = DESIGN_ARENA_MAX_SURFACE_GUIS,
	}
end
local ARENA_CONTRACTS: { [string]: ArenaContract } = {
	-- Candy Court (§5.3, §7.8): full cover only, measured along the arena axes; Decor "< 60".
	arena = { rootName = "Arena_CandyCourt", lowCover = false, ownAxesWidth = false, maxDecorParts = 59 },
	arena_sweetshop_stadium = designArena("Arena_SweetshopStadium", "sweetshop_stadium"),
	arena_pinewood_camp = designArena("Arena_PinewoodCamp", "pinewood_camp"),
	arena_pillow_fort_park = designArena("Arena_PillowFortPark", "pillow_fort_park"),
	arena_bubble_reef_court = designArena("Arena_BubbleReefCourt", "bubble_reef_court"),
	arena_arcade_toyworks = designArena("Arena_ArcadeToyworks", "arcade_toyworks"),
}
local PLAYABLE_HALF_X = 36
local PLAYABLE_HALF_Z = 52
local NEUTRAL_HALF_Z = 8
local FLOOR_TOP_TOLERANCE = 0.01
local FLOOR_SAMPLE_STEP = 2.5
-- Floor samples reach the barrier walls (X ±38, Z ±54): the strip behind each rail must be walkable floor too, or a
-- player who hops a rail falls into the void. Samples stay this far inside the walls.
local FLOOR_SAMPLE_HALF_X = 37.5
local FLOOR_SAMPLE_HALF_Z = 53.5
local DIVIDER_GROUP = "SD_Divider"
local DIVIDER_COUNT = 2
-- The other arena barriers (walls, ceiling). Roblox ignores CanQuery = false on a colliding part, so a collision group
-- that does not collide with Default is what keeps projectile rays off every barrier (§5.3, §7.8).
local BARRIER_GROUP = "SD_Barrier"
local BARRIER_COUNT = 5
local PAD_Z = 44
local PAD_MAX_TOP = 0.25 -- a pad is a thin disc on the floor
-- Open pad-to-pad lane: X -6..6 between the pads, above the floor paint, up to the barrier height.
local LANE_CENTER = Vector3.new(0, (0.5 + 40) / 2, 0)
local LANE_SIZE = Vector3.new(12, 40 - 0.5, 2 * PAD_Z)
local ARENA_ZONES: { ZoneSpec } = {
	{ name = "HalfA", x = { -36, 36 }, z = { -52, -8 } },
	{ name = "Neutral", x = { -36, 36 }, z = { -8, 8 } },
	{ name = "HalfB", x = { -36, 36 }, z = { 8, 52 } },
	{ name = "Bounds", x = { -38, 38 }, z = { -54, 54 }, y = { -15, 40 } },
}
local BARRIER_BOXES: { BoxSpec } = {
	{
		label = "side wall X+",
		center = Vector3.new(38.5, 20, 0),
		size = Vector3.new(1, 40, 110),
		group = BARRIER_GROUP,
	},
	{
		label = "side wall X-",
		center = Vector3.new(-38.5, 20, 0),
		size = Vector3.new(1, 40, 110),
		group = BARRIER_GROUP,
	},
	{ label = "end wall Z+", center = Vector3.new(0, 20, 54.5), size = Vector3.new(78, 40, 1), group = BARRIER_GROUP },
	{ label = "end wall Z-", center = Vector3.new(0, 20, -54.5), size = Vector3.new(78, 40, 1), group = BARRIER_GROUP },
	-- §7.8 gives only "ceiling at Y 40.5"; it spans the walls' outer faces.
	{ label = "ceiling", center = Vector3.new(0, 40.5, 0), size = Vector3.new(78, 1, 110), group = BARRIER_GROUP },
	-- §7.8 says 72 wide; they are 76 (X -38..38) so they meet the side walls and nobody walks around their ends
	-- into the neutral zone (§5.3).
	{ label = "divider Z+", center = Vector3.new(0, 20, 8), size = Vector3.new(76, 40, 1), group = DIVIDER_GROUP },
	{ label = "divider Z-", center = Vector3.new(0, 20, -8), size = Vector3.new(76, 40, 1), group = DIVIDER_GROUP },
}
-- Lobby floor plane and footprint (§7.5) for templateLeftovers.
local LOBBY_FLOOR_Y = 0
local LOBBY_FOOTPRINT_HALF = Vector3.new(70, 0, 70) -- lobby bases spec §2: Squish Square (Ø140), the floor at Y 0
local ARENA_AUDIO_ZONE_ID = "arena"
local ARENA_AUDIO_PRIORITY = 3

-- WorldLayout field names accepted (see the header).
local STATION_TABLES = { "Stations", "SqueezeStations", "stations", "squeezeStations" }
local STATION_ID_FIELDS = { "id", "stationId", "StationId" }
local TIER_FIELDS = { "gripTier", "GripTier", "tier" }

-- `require` with a runtime-chosen ModuleScript (the injected Shared clone); the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local Verify = {}

-- Private: reporting

local function newReport(): Report
	return { lines = {}, counts = {} }
end

local function note(report: Report, key: string, message: string)
	local count = (report.counts[key] or 0) + 1
	report.counts[key] = count
	if count <= MAX_LINES_PER_KEY then
		table.insert(report.lines, message)
	end
end

local function finishReport(report: Report): { string }
	local keys: { string } = {}
	for key, count in report.counts do
		if count > MAX_LINES_PER_KEY then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	for _, key in keys do
		table.insert(
			report.lines,
			string.format("... and %d more %q problem(s)", report.counts[key] - MAX_LINES_PER_KEY, key)
		)
	end
	return report.lines
end

local function expectFlag(report: Report, what: string, property: string, actual: unknown, expected: unknown)
	if actual ~= expected then
		note(
			report,
			property,
			string.format("%s.%s is %s, expected %s", what, property, tostring(actual), tostring(expected))
		)
	end
end

local function vec(v: Vector3): string
	return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end

-- Private: geometry

-- Axis-aligned bounds (in the frame `cframe` is expressed in) of a box with that CFrame and Size.
local function boxBounds(cframe: CFrame, size: Vector3): (Vector3, Vector3)
	local x, y, z = cframe.XVector, cframe.YVector, cframe.ZVector
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local extent = Vector3.new(
		math.abs(x.X) * hx + math.abs(y.X) * hy + math.abs(z.X) * hz,
		math.abs(x.Y) * hx + math.abs(y.Y) * hy + math.abs(z.Y) * hz,
		math.abs(x.Z) * hx + math.abs(y.Z) * hy + math.abs(z.Z) * hz
	)
	return cframe.Position - extent, cframe.Position + extent
end

-- Bounds of a part in `frame` space.
local function partBounds(part: BasePart, frame: CFrame): (Vector3, Vector3)
	return boxBounds(frame:ToObjectSpace(part.CFrame), part.Size)
end

-- Union of the parts' bounds in `frame` space; nil when there are no parts.
local function unionBounds(parts: { BasePart }, frame: CFrame): (Vector3?, Vector3?)
	local low: Vector3? = nil
	local high: Vector3? = nil
	for _, part in parts do
		local a, b = partBounds(part, frame)
		low = if low then low:Min(a) else a
		high = if high then high:Max(b) else b
	end
	return low, high
end

local function boundsOverlap(lowA: Vector3, highA: Vector3, lowB: Vector3, highB: Vector3, epsilon: number): boolean
	return lowA.X < highB.X - epsilon
		and lowB.X < highA.X - epsilon
		and lowA.Y < highB.Y - epsilon
		and lowB.Y < highA.Y - epsilon
		and lowA.Z < highB.Z - epsilon
		and lowB.Z < highA.Z - epsilon
end

-- Separating-axis test for two oriented boxes (CFrame + Size); true when they overlap by more than `epsilon`.
local function boxesOverlap(cfA: CFrame, sizeA: Vector3, cfB: CFrame, sizeB: Vector3, epsilon: number?): boolean
	local margin = epsilon or 0
	local axesA = { cfA.XVector, cfA.YVector, cfA.ZVector }
	local axesB = { cfB.XVector, cfB.YVector, cfB.ZVector }
	local halfA = { sizeA.X / 2, sizeA.Y / 2, sizeA.Z / 2 }
	local halfB = { sizeB.X / 2, sizeB.Y / 2, sizeB.Z / 2 }
	local offset = cfB.Position - cfA.Position

	local function separates(axis: Vector3): boolean
		local length = axis.Magnitude
		if length < 1e-6 then
			return false -- parallel edges: the face axes already cover this direction
		end
		local unit = axis / length
		local radiusA, radiusB = 0, 0
		for index = 1, 3 do
			radiusA += math.abs(axesA[index]:Dot(unit)) * halfA[index]
			radiusB += math.abs(axesB[index]:Dot(unit)) * halfB[index]
		end
		return math.abs(offset:Dot(unit)) >= radiusA + radiusB - margin
	end

	for index = 1, 3 do
		if separates(axesA[index]) or separates(axesB[index]) then
			return false
		end
	end
	for i = 1, 3 do
		for j = 1, 3 do
			if separates(axesA[i]:Cross(axesB[j])) then
				return false
			end
		end
	end
	return true
end

local function near(a: number, b: number, tolerance: number): boolean
	return math.abs(a - b) <= tolerance
end

local function nearVector(a: Vector3, b: Vector3, tolerance: number): boolean
	return near(a.X, b.X, tolerance) and near(a.Y, b.Y, tolerance) and near(a.Z, b.Z, tolerance)
end

-- Private: tree helpers

local function everything(root: Instance): { Instance }
	local all = root:GetDescendants()
	table.insert(all, 1, root)
	return all
end

local function tagged(all: { Instance }, tag: string): { Instance }
	local found: { Instance } = {}
	for _, instance in all do
		if instance:HasTag(tag) then
			table.insert(found, instance)
		end
	end
	return found
end

local function hasAnyTag(instance: Instance, tags: { string }): boolean
	for _, tag in tags do
		if instance:HasTag(tag) then
			return true
		end
	end
	return false
end

-- `instance` itself when it is a BasePart, plus every BasePart below it.
local function partsIn(instance: Instance?): { BasePart }
	local parts: { BasePart } = {}
	if instance == nil then
		return parts
	end
	if instance:IsA("BasePart") then
		table.insert(parts, instance :: BasePart)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant :: BasePart)
		end
	end
	return parts
end

-- The nearest Model at or above `instance`, stopping below `root` (nil when there is none).
local function nearestModel(instance: Instance, root: Instance): Model?
	local node: Instance? = instance
	while node ~= nil and node ~= root do
		if node:IsA("Model") then
			return node :: Model
		end
		node = node.Parent
	end
	return nil
end

local function describe(instance: Instance): string
	return instance:GetFullName()
end

local function shapeOf(part: BasePart): Enum.PartType?
	return if part:IsA("Part") then (part :: Part).Shape else nil
end

-- Private: shared modules

local function loadShared(shared: Instance?, path: { string }): (any, string?)
	local label = "Shared/" .. table.concat(path, "/")
	if shared == nil then
		return nil, label .. " cannot load: deps.Shared missing"
	end
	local node: Instance? = shared
	for _, name in path do
		node = if node then node:FindFirstChild(name) else nil
	end
	if node == nil or not node:IsA("ModuleScript") then
		return nil, label .. " not found"
	end
	local ok, result = pcall(dynamicRequire, node)
	if not ok then
		return nil, label .. " failed to load: " .. tostring(result)
	end
	return result, nil
end

local function pick(entry: { [any]: any }, names: { string }): any
	for _, name in names do
		local value = entry[name]
		if value ~= nil then
			return value
		end
	end
	return nil
end

-- An entry of `list` (map or array) for `key`: list[key] when that is a table, else the first table entry whose
-- `fields` hold `key`.
local function findEntry(list: any, key: string, fields: { string }): { [any]: any }?
	if type(list) ~= "table" then
		return nil
	end
	local direct = list[key]
	if type(direct) == "table" then
		return direct
	end
	for _, entry in list do
		if type(entry) == "table" then
			for _, field in fields do
				if entry[field] == key then
					return entry
				end
			end
		end
	end
	return nil
end

local function readLayout(module: any): Layout?
	if type(module) ~= "table" then
		return nil
	end
	local function tierOf(stationId: string): number?
		local lookup = module.stationTier
		if type(lookup) == "function" then
			local ok, value = pcall(lookup, stationId)
			if ok and type(value) == "number" then
				return value
			end
		end
		for _, name in STATION_TABLES do
			local entry = findEntry(module[name], stationId, STATION_ID_FIELDS)
			local tier = if entry then pick(entry, TIER_FIELDS) else nil
			if type(tier) == "number" then
				return tier
			end
		end
		return nil
	end
	return { tierOf = tierOf }
end

-- Private: generic checks

local function checkMarker(report: Report, target: string, root: Instance)
	local info = Generated.info(root)
	if info == nil then
		note(
			report,
			"marker",
			string.format(
				"root %s is not marked (tag %s with valid %s and %s)",
				root.Name,
				Generated.TAG,
				Generated.ATTR_ID,
				Generated.ATTR_VERSION
			)
		)
		return
	end
	if info.generatorId ~= target then
		note(
			report,
			"marker",
			string.format("root %s has %s %q, expected %q", root.Name, Generated.ATTR_ID, info.generatorId, target)
		)
	end
	if info.builtAt == "" then
		note(report, "marker", string.format("root %s has no %s", root.Name, Generated.ATTR_BUILT_AT))
	end
end

-- Every part of `instance` has CanCollide, CanQuery and CanTouch false.
local function expectInert(report: Report, key: string, what: string, instance: Instance)
	for _, part in partsIn(instance) do
		if part.CanCollide or part.CanQuery or part.CanTouch then
			note(
				report,
				key,
				string.format(
					"%s: %s must not collide, be queried or be touched (CanCollide %s, CanQuery %s, CanTouch %s)",
					what,
					describe(part),
					tostring(part.CanCollide),
					tostring(part.CanQuery),
					tostring(part.CanTouch)
				)
			)
		end
	end
end

-- Private: shapes (§8.1 rule 2)

local function verifyShapes(report: Report, root: Instance, _deps: Deps?)
	if not root:IsA("Folder") then
		note(report, "root", string.format("root is a %s, expected a Folder", root.ClassName))
	end
	if root.Name ~= SHAPES_ROOT_NAME then
		note(report, "root", string.format("root is named %q, expected %q", root.Name, SHAPES_ROOT_NAME))
	end

	local matches: { Instance } = {}
	for _, child in root:GetChildren() do
		if child.Name == ROUNDED_BOX_NAME then
			table.insert(matches, child)
		end
	end
	if #matches ~= 1 then
		note(report, "shapes", string.format("expected exactly one %s, found %d", ROUNDED_BOX_NAME, #matches))
		return
	end

	local box = matches[1]
	-- GeometryService:IntersectAsync makes an IntersectOperation; any PartOperation (CSG solid) is accepted.
	if not box:IsA("PartOperation") then
		note(
			report,
			"shapes",
			string.format("%s is a %s, expected a PartOperation (CSG solid)", ROUNDED_BOX_NAME, box.ClassName)
		)
		return
	end
	local solid = box :: PartOperation
	local delta = solid.Size - ROUNDED_BOX_SIZE
	if math.max(math.abs(delta.X), math.abs(delta.Y), math.abs(delta.Z)) > SIZE_TOLERANCE then
		note(
			report,
			"shapes",
			string.format(
				"%s.Size is %.3f x %.3f x %.3f, expected 2 x 2 x 2 (±%.2f)",
				ROUNDED_BOX_NAME,
				solid.Size.X,
				solid.Size.Y,
				solid.Size.Z,
				SIZE_TOLERANCE
			)
		)
	end
	expectFlag(report, ROUNDED_BOX_NAME, "UsePartColor", solid.UsePartColor, true)
	expectFlag(report, ROUNDED_BOX_NAME, "RenderFidelity", solid.RenderFidelity, Enum.RenderFidelity.Precise)
	expectFlag(report, ROUNDED_BOX_NAME, "CollisionFidelity", solid.CollisionFidelity, Enum.CollisionFidelity.Box)
	expectFlag(report, ROUNDED_BOX_NAME, "Anchored", solid.Anchored, true)
	expectFlag(report, ROUNDED_BOX_NAME, "CanCollide", solid.CanCollide, false)
	expectFlag(report, ROUNDED_BOX_NAME, "CanTouch", solid.CanTouch, false)
	expectFlag(report, ROUNDED_BOX_NAME, "CanQuery", solid.CanQuery, false)
end

-- Private: lobby (§7.5-§7.7, §17.6)

local function checkLobbyRoot(report: Report, root: Instance)
	if not root:IsA("Model") then
		note(report, "root", string.format("root is a %s, expected a Model", root.ClassName))
	elseif (root :: Model).ModelStreamingMode == Enum.ModelStreamingMode.Atomic then
		note(report, "root", "root is Atomic; the lobby root streams per station (ModelStreamingMode Default)")
	end
	if root.Name ~= LOBBY_ROOT_NAME then
		note(report, "root", string.format("root is named %q, expected %q", root.Name, LOBBY_ROOT_NAME))
	end
end

local function checkTagCounts(report: Report, all: { Instance })
	for _, expected in LOBBY_TAG_COUNTS do
		local found = #tagged(all, expected.tag)
		if found ~= expected.count then
			note(report, "tags", string.format("tag %s: expected %d, found %d", expected.tag, expected.count, found))
		end
	end
	for _, tag in { TAG_SIGN, TAG_KEEP_CLEAR } do
		if #tagged(all, tag) == 0 then
			note(report, "tags", string.format("tag %s: expected at least 1, found 0", tag))
		end
	end
end

local function checkSqueezeStations(report: Report, all: { Instance }, layout: Layout?)
	local seen: { [string]: boolean } = {}
	for _, station in tagged(all, TAG_SQUEEZE) do
		local id = station:GetAttribute(ATTR_STATION_ID)
		if type(id) ~= "string" or string.match(id, STATION_ID_PATTERN) == nil then
			note(
				report,
				"StationId",
				string.format(
					"%s %s has StationId %s (expected squeeze_NN)",
					TAG_SQUEEZE,
					describe(station),
					tostring(id)
				)
			)
			continue
		end
		if seen[id] then
			note(report, "StationId", string.format("%s: StationId %s is used twice", TAG_SQUEEZE, id))
		end
		seen[id] = true
		local tier = station:GetAttribute(ATTR_GRIP_TIER)
		if type(tier) ~= "number" then
			note(report, "GripTier", string.format("station %s has no %s", id, ATTR_GRIP_TIER))
		elseif layout then
			local expected = layout.tierOf(id)
			if expected == nil then
				note(report, "WorldLayout", string.format("WorldLayout has no GripTier for station %s", id))
			elseif expected ~= tier then
				note(
					report,
					"GripTier",
					string.format("station %s has %s %d, WorldLayout says %d", id, ATTR_GRIP_TIER, tier, expected)
				)
			end
		end
	end
	for index = 1, SQUEEZE_STATIONS do
		local id = string.format("squeeze_%02d", index)
		if not seen[id] then
			note(report, "StationId", string.format("%s: no station has StationId %s", TAG_SQUEEZE, id))
		end
	end
end

local function checkPracticeTargets(report: Report, all: { Instance })
	local ids: { [any]: boolean } = {}
	local moving = 0
	for _, target in tagged(all, TAG_PRACTICE_TARGET) do
		local id = target:GetAttribute("TargetId")
		if type(id) ~= "string" and type(id) ~= "number" then
			note(
				report,
				TAG_PRACTICE_TARGET,
				string.format("%s %s has no TargetId", TAG_PRACTICE_TARGET, describe(target))
			)
		elseif ids[id] then
			note(
				report,
				TAG_PRACTICE_TARGET,
				string.format("%s: TargetId %s is used twice", TAG_PRACTICE_TARGET, tostring(id))
			)
		else
			ids[id] = true
		end
		for _, attribute in PRACTICE_TARGET_ATTRIBUTES do
			local value = target:GetAttribute(attribute.name)
			if type(value) ~= attribute.kind then
				note(
					report,
					TAG_PRACTICE_TARGET,
					string.format(
						"%s %s: %s is %s, expected a %s",
						TAG_PRACTICE_TARGET,
						describe(target),
						attribute.name,
						tostring(value),
						attribute.kind
					)
				)
			end
		end
		if target:GetAttribute("Moving") == true then
			moving += 1
		end
	end
	if moving ~= 1 then
		note(
			report,
			TAG_PRACTICE_TARGET,
			string.format("%s: expected exactly 1 with Moving = true, found %d", TAG_PRACTICE_TARGET, moving)
		)
	end
end

-- Every instance with `tag` has a unique integer Slot 1..count.
local function checkSlots(report: Report, all: { Instance }, tag: string, count: number)
	local seen: { [number]: boolean } = {}
	for _, instance in tagged(all, tag) do
		local slot = instance:GetAttribute("Slot")
		if type(slot) ~= "number" or slot ~= math.floor(slot) or slot < 1 or slot > count then
			note(
				report,
				tag,
				string.format("%s %s has Slot %s, expected 1..%d", tag, describe(instance), tostring(slot), count)
			)
		elseif seen[slot] then
			note(report, tag, string.format("%s: Slot %d is used twice", tag, slot))
		else
			seen[slot] = true
		end
	end
end

local function checkSpawnAndStands(report: Report, all: { Instance })
	for _, spawn in tagged(all, TAG_SPAWN) do
		if not spawn:IsA("SpawnLocation") then
			note(
				report,
				TAG_SPAWN,
				string.format("%s %s is a %s, expected a SpawnLocation", TAG_SPAWN, describe(spawn), spawn.ClassName)
			)
		else
			local location = spawn :: SpawnLocation
			expectFlag(report, describe(location), "Duration", location.Duration, 0)
			expectFlag(report, describe(location), "Neutral", location.Neutral, true)
		end
	end
	for _, stand in tagged(all, TAG_BOX_STAND) do
		local boxId = stand:GetAttribute("BoxId")
		if type(boxId) ~= "string" or boxId == "" then
			note(report, TAG_BOX_STAND, string.format("%s %s has no BoxId", TAG_BOX_STAND, describe(stand)))
		end
	end
end

local function checkVolumes(report: Report, all: { Instance })
	local zoneIds: { [string]: boolean } = {}
	for _, zone in tagged(all, TAG_AUDIO_ZONE) do
		local id = zone:GetAttribute("ZoneId")
		if type(id) ~= "string" or not table.find(AUDIO_ZONE_IDS, id) then
			note(
				report,
				TAG_AUDIO_ZONE,
				string.format("%s %s has ZoneId %s", TAG_AUDIO_ZONE, describe(zone), tostring(id))
			)
		elseif zoneIds[id] then
			note(report, TAG_AUDIO_ZONE, string.format("%s: ZoneId %s is used twice", TAG_AUDIO_ZONE, id))
		else
			zoneIds[id] = true
		end
		if type(zone:GetAttribute("Priority")) ~= "number" then
			note(report, TAG_AUDIO_ZONE, string.format("%s %s has no Priority", TAG_AUDIO_ZONE, describe(zone)))
		end
		expectInert(report, TAG_AUDIO_ZONE, TAG_AUDIO_ZONE, zone)
	end
	for _, wall in tagged(all, TAG_BOUNDARY) do
		if not wall:IsA("BasePart") then
			note(report, TAG_BOUNDARY, string.format("%s %s is not a part", TAG_BOUNDARY, describe(wall)))
			continue
		end
		local part = wall :: BasePart
		expectFlag(report, describe(part), "Transparency", part.Transparency, 1)
		expectFlag(report, describe(part), "CanCollide", part.CanCollide, true)
		expectFlag(report, describe(part), "CanQuery", part.CanQuery, false)
		expectFlag(report, describe(part), "CanTouch", part.CanTouch, false)
	end
	for _, volume in tagged(all, TAG_KEEP_CLEAR) do
		if not volume:IsA("BasePart") then
			note(report, "keep-clear", string.format("%s %s is not a part", TAG_KEEP_CLEAR, describe(volume)))
			continue
		end
		local part = volume :: BasePart
		expectFlag(report, describe(part), "Transparency", part.Transparency, 1)
		expectInert(report, "keep-clear", TAG_KEEP_CLEAR, part)
	end
end

local function checkTextKeys(report: Report, all: { Instance }, strings: any)
	local resolve = if type(strings) == "table" then strings.resolve else nil
	if type(resolve) ~= "function" then
		note(report, "Strings", "Strings.resolve is not available: SD_TextKey values were not checked")
		return
	end
	local function exists(key: string): boolean
		local ok, text = pcall(resolve, key)
		return ok and type(text) == "string"
	end
	for _, instance in all do
		local key = instance:GetAttribute(ATTR_TEXT_KEY)
		if key == nil then
			continue
		end
		if type(key) ~= "string" or key == "" then
			note(
				report,
				ATTR_TEXT_KEY,
				string.format(
					"%s on %s is %s, expected a Strings key",
					ATTR_TEXT_KEY,
					describe(instance),
					tostring(key)
				)
			)
		elseif not exists(key) then
			note(
				report,
				ATTR_TEXT_KEY,
				string.format("%s %q on %s does not exist in Strings", ATTR_TEXT_KEY, key, describe(instance))
			)
		end
	end
	for _, sign in tagged(all, TAG_SIGN) do
		local keyed = sign:GetAttribute(ATTR_TEXT_KEY) ~= nil
		if not keyed then
			for _, descendant in sign:GetDescendants() do
				if descendant:GetAttribute(ATTR_TEXT_KEY) ~= nil then
					keyed = true
					break
				end
			end
		end
		if not keyed then
			note(report, ATTR_TEXT_KEY, string.format("%s %s carries no %s", TAG_SIGN, describe(sign), ATTR_TEXT_KEY))
		end
	end
end

-- §18.1 #3 / §18.5.1 A8: the client turns or breathes SD_Ambient decor locally, so every part of it must stay out of
-- collisions, queries and touches, and its SD_AmbientKind must be one the client knows. Reading: DESIGN asks Verify
-- only for the count; the inert and kind checks guard the same exception.
local function checkAmbient(report: Report, all: { Instance })
	for _, decor in tagged(all, TAG_AMBIENT) do
		local kind = decor:GetAttribute(ATTR_AMBIENT_KIND)
		if type(kind) ~= "string" or not AMBIENT_KINDS[kind] then
			note(
				report,
				TAG_AMBIENT,
				string.format("%s %s has %s %s", TAG_AMBIENT, describe(decor), ATTR_AMBIENT_KIND, tostring(kind))
			)
		end
		expectInert(report, TAG_AMBIENT, TAG_AMBIENT .. " (moved by the client)", decor)
	end
end

-- Models below the root that hold a station-tagged instance, plus the station-tagged instances themselves.
local function stationHolders(all: { Instance }, root: Instance): { [Instance]: boolean }
	local holders: { [Instance]: boolean } = {}
	for _, instance in all do
		if instance ~= root and hasAnyTag(instance, STATION_TAGS) then
			holders[instance] = true
			local node: Instance? = instance
			while node ~= nil and node ~= root do
				if node:IsA("Model") then
					holders[node] = true
				end
				node = node.Parent
			end
		end
	end
	return holders
end

-- True when `part` (inside the lobby `root`, or anywhere when `root` is not its ancestor) must stay out of
-- keep-clear volumes.
local function isKeepClearCandidate(part: BasePart, root: Instance, holders: { [Instance]: boolean }): boolean
	if not part.CanCollide or part:HasTag(TAG_KEEP_CLEAR) or part:HasTag(TAG_BOUNDARY) then
		return false
	end
	local _, high = boxBounds(part.CFrame, part.Size)
	if high.Y <= WALKABLE_TOP then
		return false
	end
	if part:IsDescendantOf(root) then
		if holders[part] then
			return false
		end
		local model = nearestModel(part, root)
		if model and holders[model] then
			return false
		end
	end
	return true
end

local function checkKeepClear(report: Report, all: { Instance }, root: Instance)
	local holders = stationHolders(all, root)
	type Candidate = { part: BasePart, low: Vector3, high: Vector3 }
	local candidates: { Candidate } = {}
	for _, instance in all do
		if instance:IsA("BasePart") and isKeepClearCandidate(instance :: BasePart, root, holders) then
			local part = instance :: BasePart
			local low, high = boxBounds(part.CFrame, part.Size)
			table.insert(candidates, { part = part, low = low, high = high })
		end
	end
	for _, volume in tagged(all, TAG_KEEP_CLEAR) do
		if not volume:IsA("BasePart") then
			continue
		end
		local box = volume :: BasePart
		local low, high = boxBounds(box.CFrame, box.Size)
		for _, candidate in candidates do
			if
				boundsOverlap(low, high, candidate.low, candidate.high, OVERLAP_EPSILON)
				and boxesOverlap(box.CFrame, box.Size, candidate.part.CFrame, candidate.part.Size, OVERLAP_EPSILON)
			then
				note(
					report,
					"keep-clear",
					string.format("keep-clear: %s reaches into %s", describe(candidate.part), describe(box))
				)
			end
		end
	end
end

local function checkPrompts(report: Report, all: { Instance }, root: Instance)
	for _, instance in all do
		if not instance:IsA("ProximityPrompt") then
			continue
		end
		local prompt = instance :: ProximityPrompt
		if prompt.Enabled then
			note(
				report,
				"ProximityPrompt",
				string.format(
					"ProximityPrompt %s is enabled; stand prompts are built disabled (WorldBinder enables them)",
					describe(prompt)
				)
			)
		end
		local model = nearestModel(prompt, root)
		if model == nil or model.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then
			note(
				report,
				"ProximityPrompt",
				string.format("ProximityPrompt %s is not inside an Atomic station model", describe(prompt))
			)
		else
			local low, high = unionBounds(partsIn(model), CFrame.identity)
			if low and high then
				local extent = high - low
				if math.max(extent.X, extent.Y, extent.Z) >= MAX_ATOMIC_EXTENT then
					note(
						report,
						"ProximityPrompt",
						string.format(
							"Atomic station model %s is %s studs, expected < %d",
							describe(model),
							vec(extent),
							MAX_ATOMIC_EXTENT
						)
					)
				end
			end
		end
	end
end

-- Lobby bases spec §4: one Model per plot with a unique Plot 1..LOBBY_BASES, holding exactly one SpawnLocation of its own
-- plot and none of another; SD_BaseTint only "full" or "light".
local function checkBases(report: Report, all: { Instance })
	local seen: { [number]: boolean } = {}
	for _, base in tagged(all, TAG_BASE) do
		if not base:IsA("Model") then
			note(
				report,
				TAG_BASE,
				string.format("%s %s is a %s, expected a Model", TAG_BASE, describe(base), base.ClassName)
			)
		end
		local plot = base:GetAttribute(ATTR_PLOT)
		if type(plot) ~= "number" or plot ~= math.floor(plot) or plot < 1 or plot > LOBBY_BASES then
			note(
				report,
				TAG_BASE,
				string.format(
					"%s %s has Plot %s, expected 1..%d",
					TAG_BASE,
					describe(base),
					tostring(plot),
					LOBBY_BASES
				)
			)
			continue
		end
		if seen[plot] then
			note(report, TAG_BASE, string.format("%s: Plot %d is used twice", TAG_BASE, plot))
		end
		seen[plot] = true
		local own = 0
		local others: { [string]: number } = {}
		for _, descendant in base:GetDescendants() do
			if descendant:HasTag(TAG_BASE_SPAWN) then
				local spawnPlot = descendant:GetAttribute(ATTR_PLOT)
				if spawnPlot == plot then
					own += 1
				else
					others[tostring(spawnPlot)] = (others[tostring(spawnPlot)] or 0) + 1
				end
			end
		end
		if own ~= 1 then
			note(
				report,
				TAG_BASE_SPAWN,
				string.format("%s holds %d %s of Plot %d, expected 1", describe(base), own, TAG_BASE_SPAWN, plot)
			)
		end
		for other, count in others do
			note(
				report,
				TAG_BASE_SPAWN,
				string.format("%s holds %d %s of Plot %s, expected 0", describe(base), count, TAG_BASE_SPAWN, other)
			)
		end
	end
	for _, spawn in tagged(all, TAG_BASE_SPAWN) do
		if not spawn:IsA("SpawnLocation") then
			note(
				report,
				TAG_BASE_SPAWN,
				string.format(
					"%s %s is a %s, expected a SpawnLocation",
					TAG_BASE_SPAWN,
					describe(spawn),
					spawn.ClassName
				)
			)
		else
			local location = spawn :: SpawnLocation
			expectFlag(report, describe(location), "Duration", location.Duration, 0)
			expectFlag(report, describe(location), "Neutral", location.Neutral, true)
		end
	end
	for _, instance in all do
		local tint = instance:GetAttribute(ATTR_BASE_TINT)
		if tint ~= nil and tint ~= "full" and tint ~= "light" then
			note(
				report,
				ATTR_BASE_TINT,
				string.format(
					"%s has %s %s, expected full or light",
					describe(instance),
					ATTR_BASE_TINT,
					tostring(tint)
				)
			)
		end
	end
end

-- Lobby bases spec §7 render rules: nothing but a SpawnLocation is touched; a part under SMALL_PART studs casts no
-- shadow. `spawns` false: no part is touched at all (the capsule templates).
local function checkRenderRules(report: Report, all: { Instance }, spawns: boolean)
	for _, instance in all do
		if not instance:IsA("BasePart") then
			continue
		end
		local part = instance :: BasePart
		if part.CanTouch and not (spawns and part:IsA("SpawnLocation")) then
			note(report, "CanTouch", string.format("%s is touched (spec §7: CanTouch off)", describe(part)))
		end
		if part.CastShadow and math.max(part.Size.X, part.Size.Y, part.Size.Z) < SMALL_PART then
			note(
				report,
				"CastShadow",
				string.format("%s casts a shadow (spec §7: off under %d studs)", describe(part), SMALL_PART)
			)
		end
	end
end

local function checkLobbyBudgets(report: Report, all: { Instance })
	local parts, guis, lights, emitters = 0, 0, 0, 0
	for _, instance in all do
		if instance:IsA("BasePart") then
			parts += 1
		elseif instance:IsA("SurfaceGui") then
			guis += 1
		elseif instance:IsA("Light") then
			lights += 1
			if (instance :: Light).Shadows then
				note(report, "lights", string.format("light %s casts shadows", describe(instance)))
			end
		elseif instance:IsA("ParticleEmitter") then
			emitters += 1
		elseif instance:IsA("LuaSourceContainer") then
			note(report, "scripts", string.format("generated trees hold no scripts: %s", describe(instance)))
		end
	end
	if parts > LOBBY_MAX_PARTS then
		note(report, "budget", string.format("lobby has %d parts, budget %d", parts, LOBBY_MAX_PARTS))
	end
	if guis > LOBBY_MAX_SURFACE_GUIS then
		note(report, "budget", string.format("lobby has %d SurfaceGuis, budget %d", guis, LOBBY_MAX_SURFACE_GUIS))
	end
	if lights > LOBBY_MAX_LIGHTS then
		note(report, "budget", string.format("lobby has %d lights, budget %d", lights, LOBBY_MAX_LIGHTS))
	end
	if emitters > LOBBY_MAX_EMITTERS then
		note(report, "budget", string.format("lobby has %d particle emitters, budget %d", emitters, LOBBY_MAX_EMITTERS))
	end
end

local function verifyLobby(report: Report, root: Instance, deps: Deps?)
	local strings = if deps then deps.Strings else nil
	if strings == nil then
		local loaded, err = loadShared(if deps then deps.Shared else nil, { "Strings" })
		strings = loaded
		if err then
			note(report, "Strings", err)
		end
	end
	local layoutModule = if deps then deps.WorldLayout else nil
	if layoutModule == nil then
		local loaded, err = loadShared(if deps then deps.Shared else nil, { "World", "WorldLayout" })
		layoutModule = loaded
		if err then
			note(report, "WorldLayout", err .. ": GripTier was not checked")
		end
	end
	local layout = readLayout(layoutModule)

	local all = everything(root)
	checkLobbyRoot(report, root)
	checkTagCounts(report, all)
	checkSqueezeStations(report, all, layout)
	checkPracticeTargets(report, all)
	checkSlots(report, all, TAG_PEDESTAL, LOBBY_PEDESTALS)
	checkSlots(report, all, TAG_RETURN_POINT, 2)
	checkSpawnAndStands(report, all)
	checkVolumes(report, all)
	if strings ~= nil then
		checkTextKeys(report, all, strings)
	end
	checkAmbient(report, all)
	checkKeepClear(report, all, root)
	checkPrompts(report, all, root)
	checkLobbyBudgets(report, all)
	checkBases(report, all)
	checkRenderRules(report, all, true)
end

-- Private: capsules (lobby bases spec §4, §5.1, §7; big-number progression spec §4)

-- True when `model` holds a TextLabel `name` without SD_TextKey (a live label: BaseService writes it).
local function hasLiveLabel(model: Instance, name: string): boolean
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("TextLabel")
			and descendant.Name == name
			and descendant:GetAttribute(ATTR_TEXT_KEY) == nil
		then
			return true
		end
	end
	return false
end

local function verifyCapsules(report: Report, root: Instance, deps: Deps?)
	if not root:IsA("Folder") then
		note(report, "root", string.format("root is a %s, expected a Folder", root.ClassName))
	end
	if root.Name ~= CAPSULES_ROOT_NAME then
		note(report, "root", string.format("root is named %q, expected %q", root.Name, CAPSULES_ROOT_NAME))
	end
	local catalog = if deps then deps.Catalog else nil
	if catalog == nil then
		local loaded, err = loadShared(if deps then deps.Shared else nil, { "Catalog" })
		catalog = loaded
		if err then
			note(report, "Catalog", err .. ": the squishy and statue templates were not checked")
		end
	end
	type Spec = { maxParts: number, label: string?, look: string? }
	local expected: { [string]: Spec } = {}
	for _, look in CAPSULE_LOOKS do
		expected["Capsule_" .. look] = { maxParts = CAPSULE_MAX_PARTS, label = "Level", look = look }
	end
	expected.Lock = { maxParts = LOCK_MAX_PARTS, label = "Price" }
	local squishiesKnown = type(catalog) == "table" and type(catalog.list) == "function"
	if squishiesKnown then
		for _, def in catalog.list() do
			expected["Squishy_" .. def.id] = { maxParts = SQUISHY_MAX_PARTS }
			expected["Statue_" .. def.id] = { maxParts = SQUISHY_MAX_PARTS }
		end
	end
	for _, child in root:GetChildren() do
		local squishyLike = string.sub(child.Name, 1, 8) == "Squishy_" or string.sub(child.Name, 1, 7) == "Statue_"
		if expected[child.Name] == nil and (squishiesKnown or not squishyLike) then
			note(report, "templates", string.format("unexpected template %s", child.Name))
		end
	end
	for name, spec in expected do
		local model = root:FindFirstChild(name)
		if model == nil then
			note(report, "templates", string.format("%s is missing", name))
			continue
		end
		if not model:IsA("Model") then
			note(report, "templates", string.format("%s is a %s, expected a Model", name, model.ClassName))
			continue
		end
		local parts = #partsIn(model)
		if parts == 0 or parts > spec.maxParts then
			note(report, "budget", string.format("%s has %d parts, at most %d", name, parts, spec.maxParts))
		end
		local label = spec.label
		if label ~= nil and not hasLiveLabel(model, label) then
			note(report, "labels", string.format("%s has no live %s label", name, label))
		end
		local look = spec.look
		if look ~= nil then
			local actual = model:GetAttribute(ATTR_LOOK)
			if actual ~= look then
				note(
					report,
					ATTR_LOOK,
					string.format("%s has %s %s, expected %s", name, ATTR_LOOK, tostring(actual), look)
				)
			end
			local seat = model:GetAttribute(ATTR_SEAT)
			if type(seat) ~= "number" or seat <= 0 then
				note(
					report,
					ATTR_SEAT,
					string.format("%s has %s %s, expected a height", name, ATTR_SEAT, tostring(seat))
				)
			end
		end
	end
	local all = everything(root)
	for _, instance in all do
		if instance:IsA("BasePart") and not (instance :: BasePart).Anchored then
			note(report, "Anchored", string.format("%s is not anchored", describe(instance)))
		elseif instance:IsA("LuaSourceContainer") then
			note(report, "scripts", string.format("generated trees hold no scripts: %s", describe(instance)))
		end
	end
	checkRenderRules(report, all, false)
end

-- Private: arena (§5.3, §7.8)

local function checkArenaTree(report: Report, root: Instance, all: { Instance }, contract: ArenaContract)
	if not root:IsA("Model") then
		note(report, "root", string.format("root is a %s, expected a Model", root.ClassName))
	elseif (root :: Model).ModelStreamingMode == Enum.ModelStreamingMode.Atomic then
		note(report, "root", "root is Atomic; only cover pieces are Atomic (§5.3)")
	end
	if root.Name ~= contract.rootName then
		note(report, "root", string.format("root is named %q, expected %q", root.Name, contract.rootName))
	end
	local arenaId = root:GetAttribute(ATTR_ARENA_ID)
	if contract.arenaId ~= nil and arenaId ~= contract.arenaId then
		note(
			report,
			"root",
			string.format(
				"root %s has %s %s, expected %q",
				root.Name,
				ATTR_ARENA_ID,
				if type(arenaId) == "string" then string.format("%q", arenaId) else tostring(arenaId),
				contract.arenaId
			)
		)
	end
	for _, name in ARENA_CHILDREN do
		if root:FindFirstChild(name) == nil then
			note(report, "root", string.format("missing %s", name))
		end
	end
	for _, child in root:GetChildren() do
		if not table.find(ARENA_CHILDREN, child.Name) then
			note(report, "root", string.format("unexpected child %s", describe(child)))
		end
	end

	local parts, dividers, barriers, surfaceGuis = 0, 0, 0, 0
	for _, instance in all do
		if instance:IsA("SurfaceGui") then
			surfaceGuis += 1
		end
		if instance:IsA("LuaSourceContainer") then
			note(report, "forbidden", string.format("no scripts allowed: %s", describe(instance)))
		elseif instance:IsA("ProximityPrompt") then
			note(report, "forbidden", string.format("no ProximityPrompts allowed: %s", describe(instance)))
		elseif instance:IsA("Light") then
			note(report, "forbidden", string.format("no dynamic lights allowed: %s", describe(instance)))
		end
		if instance:IsA("SpawnLocation") then
			note(report, "forbidden", string.format("no SpawnLocations allowed: %s", describe(instance)))
		end
		if instance:IsA("BasePart") then
			local part = instance :: BasePart
			parts += 1
			if part.Material == Enum.Material.Neon then
				note(report, "Neon", string.format("no Neon in the arena: %s", describe(part)))
			end
			if part.CollisionGroup == DIVIDER_GROUP then
				dividers += 1
			elseif part.CollisionGroup == BARRIER_GROUP then
				barriers += 1
			end
		end
	end
	if parts > ARENA_MAX_PARTS then
		note(report, "budget", string.format("template has %d parts, budget %d", parts, ARENA_MAX_PARTS))
	end
	local maxSurfaceGuis = contract.maxSurfaceGuis
	if maxSurfaceGuis ~= nil and surfaceGuis > maxSurfaceGuis then
		note(report, "budget", string.format("template has %d SurfaceGuis, budget %d", surfaceGuis, maxSurfaceGuis))
	end
	for _, group in
		{
			{ name = DIVIDER_GROUP, expected = DIVIDER_COUNT, found = dividers },
			{ name = BARRIER_GROUP, expected = BARRIER_COUNT, found = barriers },
		}
	do
		if group.found ~= group.expected then
			note(
				report,
				group.name,
				string.format(
					"expected %d parts in collision group %s, found %d",
					group.expected,
					group.name,
					group.found
				)
			)
		end
	end

	local runtime = root:FindFirstChild("Runtime")
	if runtime and #runtime:GetChildren() > 0 then
		note(report, "Runtime", string.format("Runtime must be empty, it has %d children", #runtime:GetChildren()))
	end

	local zones = tagged(all, TAG_AUDIO_ZONE)
	if #zones ~= 1 then
		note(report, TAG_AUDIO_ZONE, string.format("expected 1 %s, found %d", TAG_AUDIO_ZONE, #zones))
	else
		local zone = zones[1]
		if
			zone:GetAttribute("ZoneId") ~= ARENA_AUDIO_ZONE_ID
			or zone:GetAttribute("Priority") ~= ARENA_AUDIO_PRIORITY
		then
			note(
				report,
				TAG_AUDIO_ZONE,
				string.format(
					"%s %s: expected ZoneId %q and Priority %d",
					TAG_AUDIO_ZONE,
					describe(zone),
					ARENA_AUDIO_ZONE_ID,
					ARENA_AUDIO_PRIORITY
				)
			)
		end
	end
end

-- Returns the Origin frame every other arena check measures in (identity when Origin is missing).
local function checkOrigin(report: Report, root: Instance): CFrame
	local origin = root:FindFirstChild("Origin")
	if origin == nil or not origin:IsA("BasePart") then
		note(report, "Origin", "Origin is missing or not a part")
		return CFrame.identity
	end
	local part = origin :: BasePart
	if root:IsA("Model") and (root :: Model).PrimaryPart ~= part then
		note(report, "Origin", "the root's PrimaryPart is not Origin")
	end
	if part.CFrame.YVector.Y < DIRECTION_DOT then
		note(report, "Origin", "Origin is tilted; its up axis must be world up")
	end
	return part.CFrame
end

local function checkFloor(report: Report, solid: { BasePart }, frame: CFrame)
	type Bounds = { low: Vector3, high: Vector3 }
	local floors: { Bounds } = {}
	for _, part in solid do
		if part.CanCollide then
			local low, high = partBounds(part, frame)
			if near(high.Y, 0, FLOOR_TOP_TOLERANCE) then
				table.insert(floors, { low = low, high = high })
			end
		end
	end
	local function covered(x: number, z: number): boolean
		for _, floor in floors do
			if floor.low.X <= x and x <= floor.high.X and floor.low.Z <= z and z <= floor.high.Z then
				return true
			end
		end
		return false
	end
	-- The whole court out to the barrier walls: the halves, the neutral band and the strips behind the rails.
	local missing = 0
	local first: string? = nil
	for x = -FLOOR_SAMPLE_HALF_X, FLOOR_SAMPLE_HALF_X + 1e-6, FLOOR_SAMPLE_STEP do
		for z = -FLOOR_SAMPLE_HALF_Z, FLOOR_SAMPLE_HALF_Z + 1e-6, FLOOR_SAMPLE_STEP do
			if not covered(x, z) then
				missing += 1
				first = first or string.format("(%g, %g)", x, z)
			end
		end
	end
	if missing > 0 then
		note(
			report,
			"floor",
			string.format(
				"floor: %d sample point(s) inside the barrier walls (X ±%g, Z ±%g) have no colliding Geometry floor "
					.. "with its top at Y 0, first %s",
				missing,
				FLOOR_SAMPLE_HALF_X,
				FLOOR_SAMPLE_HALF_Z,
				first or "?"
			)
		)
	end
end

-- A cover piece's width: the longer side of its parts' bounds along the arena's axes, or (ownAxes, spec §4.2 R2: the
-- arena-axes box of an 8-stud wall turned 20 degrees is 8.4 wide) along its Body's turn about the arena's up axis.
local function coverWidth(piece: Model, parts: { BasePart }, frame: CFrame, ownAxes: boolean): number
	local measure = frame
	local body = piece.PrimaryPart or piece:FindFirstChild("Body")
	if ownAxes and body ~= nil and body:IsA("BasePart") then
		-- A Block or Ball Body keeps its LookVector level; an upright (rolled) Cylinder too.
		local look = frame:VectorToObjectSpace(body.CFrame.LookVector)
		if math.abs(look.Y) < DIRECTION_DOT then
			measure = frame * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
		end
	end
	local low, high = unionBounds(parts, measure)
	if low == nil or high == nil then
		return 0
	end
	return math.max(high.X - low.X, high.Z - low.Z)
end

local function checkCover(report: Report, geometry: Instance, frame: CFrame, contract: ArenaContract)
	local folder = geometry:FindFirstChild("Cover")
	if folder == nil then
		note(report, "cover", "Geometry/Cover is missing")
		return
	end
	local pieces: { Model } = {}
	for _, child in folder:GetChildren() do
		if child:IsA("Model") then
			table.insert(pieces, child :: Model)
		else
			note(report, "cover", string.format("%s is a %s, expected a cover Model", describe(child), child.ClassName))
		end
	end
	if #pieces ~= COVER_PIECES then
		note(report, "cover", string.format("cover: expected %d pieces, found %d", COVER_PIECES, #pieces))
	end

	local coverParts: { BasePart } = {}
	for _, piece in pieces do
		local parts = partsIn(piece)
		local low, high = unionBounds(parts, frame)
		if low == nil or high == nil then
			note(report, "cover", string.format("cover %s has no parts", describe(piece)))
			continue
		end
		if piece.ModelStreamingMode ~= Enum.ModelStreamingMode.Atomic then
			note(report, "cover", string.format("cover %s is not Atomic", describe(piece)))
		end
		local kind = piece:GetAttribute(ATTR_COVER_KIND)
		if contract.lowCover and kind ~= "full" and kind ~= "low" then
			note(
				report,
				"cover",
				string.format('cover %s has no %s ("full" or "low")', describe(piece), ATTR_COVER_KIND)
			)
		end
		if contract.lowCover and kind == "low" then
			if high.Y < LOW_COVER_TOP[1] - POSITION_TOLERANCE or high.Y > LOW_COVER_TOP[2] + POSITION_TOLERANCE then
				note(
					report,
					"cover",
					string.format(
						"cover %s: low cover top %.2f is outside %g..%g",
						describe(piece),
						high.Y,
						LOW_COVER_TOP[1],
						LOW_COVER_TOP[2]
					)
				)
			end
		elseif high.Y < COVER_MIN_TOP - POSITION_TOLERANCE then
			note(
				report,
				"cover",
				string.format("cover %s: top %.2f is below %d", describe(piece), high.Y, COVER_MIN_TOP)
			)
		end
		local width = coverWidth(piece, parts, frame, contract.ownAxesWidth)
		if width > COVER_MAX_WIDTH + SIZE_TOLERANCE then
			note(
				report,
				"cover",
				string.format("cover %s is %.2f wide, wider than %d", describe(piece), width, COVER_MAX_WIDTH)
			)
		end
		if low.Z < NEUTRAL_HALF_Z - POSITION_TOLERANCE and high.Z > -NEUTRAL_HALF_Z + POSITION_TOLERANCE then
			note(report, "cover", string.format("cover %s reaches into the neutral zone (Z -8..8)", describe(piece)))
		end
		if
			low.X < -PLAYABLE_HALF_X - POSITION_TOLERANCE
			or high.X > PLAYABLE_HALF_X + POSITION_TOLERANCE
			or low.Z < -PLAYABLE_HALF_Z - POSITION_TOLERANCE
			or high.Z > PLAYABLE_HALF_Z + POSITION_TOLERANCE
		then
			note(report, "cover", string.format("cover %s is outside the playable area", describe(piece)))
		end
		for _, part in parts do
			if not part.CanCollide then
				note(report, "cover", string.format("cover part %s does not collide", describe(part)))
			end
			table.insert(coverParts, part)
		end
	end

	-- Point symmetry through the centre: every cover part has a twin at (-x, y, -z) with the same class, shape and
	-- size.
	for _, part in coverParts do
		local position = frame:PointToObjectSpace(part.CFrame.Position)
		local mirrored = Vector3.new(-position.X, position.Y, -position.Z)
		local twin = false
		for _, other in coverParts do
			if
				other.ClassName == part.ClassName
				and shapeOf(other) == shapeOf(part)
				and nearVector(other.Size, part.Size, SIZE_TOLERANCE)
				and nearVector(frame:PointToObjectSpace(other.CFrame.Position), mirrored, POSITION_TOLERANCE)
			then
				twin = true
				break
			end
		end
		if not twin then
			note(
				report,
				"symmetry",
				string.format(
					"point symmetry: %s at %s has no twin at %s",
					describe(part),
					vec(position),
					vec(mirrored)
				)
			)
		end
	end
end

local function checkLane(report: Report, solid: { BasePart }, frame: CFrame)
	local lane = frame * CFrame.new(LANE_CENTER)
	for _, part in solid do
		if boxesOverlap(lane, LANE_SIZE, part.CFrame, part.Size, OVERLAP_EPSILON) then
			note(
				report,
				"lane",
				string.format("open lane: %s blocks the pad-to-pad lane (X -6..6, Z -44..44)", describe(part))
			)
		end
	end
end

local function checkBarriers(report: Report, barriers: Instance?, frame: CFrame)
	if barriers == nil then
		note(report, "Barriers", "Geometry/Barriers is missing")
		return
	end
	local parts = partsIn(barriers)
	for _, part in parts do
		local what = describe(part)
		if part.Transparency ~= 1 or not part.CanCollide or part.CanQuery or not part.Anchored then
			note(
				report,
				"Barriers",
				string.format(
					"Barriers: %s must be Transparency 1, CanCollide true, CanQuery false, Anchored "
						.. "(is %.2f, %s, %s, %s)",
					what,
					part.Transparency,
					tostring(part.CanCollide),
					tostring(part.CanQuery),
					tostring(part.Anchored)
				)
			)
		end
	end
	for _, spec in BARRIER_BOXES do
		local match: BasePart? = nil
		for _, part in parts do
			local low, high = partBounds(part, frame)
			if
				nearVector((low + high) / 2, spec.center, POSITION_TOLERANCE)
				and nearVector(high - low, spec.size, SIZE_TOLERANCE)
			then
				match = part
				break
			end
		end
		if match == nil then
			note(
				report,
				"Barriers",
				string.format("Barriers: no %s (centre %s, size %s)", spec.label, vec(spec.center), vec(spec.size))
			)
		elseif match.CollisionGroup ~= spec.group then
			note(
				report,
				spec.group,
				string.format(
					"%s is in collision group %s, expected %s",
					describe(match),
					match.CollisionGroup,
					spec.group
				)
			)
		end
	end
end

local function checkGeometry(report: Report, root: Instance, frame: CFrame, contract: ArenaContract)
	local geometry = root:FindFirstChild("Geometry")
	if geometry == nil then
		return -- reported by checkArenaTree
	end
	local barriers = geometry:FindFirstChild("Barriers")
	local solid: { BasePart } = {}
	for _, part in partsIn(geometry) do
		if barriers and part:IsDescendantOf(barriers) then
			continue
		end
		table.insert(solid, part)
		if not part.CanQuery then
			note(
				report,
				"Geometry",
				string.format("Geometry part %s has CanQuery false (projectiles must hit it)", describe(part))
			)
		end
		if not part.Anchored then
			note(report, "Geometry", string.format("Geometry part %s is not Anchored", describe(part)))
		end
	end
	if #solid == 0 then
		note(report, "Geometry", "Geometry has no parts outside Barriers")
	end
	checkFloor(report, solid, frame)
	checkCover(report, geometry, frame, contract)
	checkLane(report, solid, frame)
	checkBarriers(report, barriers, frame)
end

local function checkZones(report: Report, root: Instance, frame: CFrame)
	local zones = root:FindFirstChild("Zones")
	if zones == nil then
		return -- reported by checkArenaTree
	end
	for _, spec in ARENA_ZONES do
		local zone = zones:FindFirstChild(spec.name)
		if zone == nil or not zone:IsA("BasePart") then
			note(report, "Zones", string.format("Zones/%s is missing or not a part", spec.name))
			continue
		end
		local part = zone :: BasePart
		local relative = frame:ToObjectSpace(part.CFrame)
		if math.abs(relative.XVector.X) < DIRECTION_DOT or math.abs(relative.YVector.Y) < DIRECTION_DOT then
			note(report, "Zones", string.format("Zones/%s is rotated; zones are read as axis-aligned boxes", spec.name))
		end
		local low, high = boxBounds(relative, part.Size)
		local ranges: { { label: string, actual: Range, expected: Range? } } = {
			{ label = "X", actual = { low.X, high.X }, expected = spec.x },
			{ label = "Z", actual = { low.Z, high.Z }, expected = spec.z },
			{ label = "Y", actual = { low.Y, high.Y }, expected = spec.y },
		}
		for _, range in ranges do
			local expected = range.expected
			if
				expected
				and not (
					near(range.actual[1], expected[1], POSITION_TOLERANCE)
					and near(range.actual[2], expected[2], POSITION_TOLERANCE)
				)
			then
				note(
					report,
					"Zones",
					string.format(
						"Zones/%s spans %s %.2f..%.2f, expected %g..%g",
						spec.name,
						range.label,
						range.actual[1],
						range.actual[2],
						expected[1],
						expected[2]
					)
				)
			end
		end
	end
	for _, part in partsIn(zones) do
		if part.Transparency ~= 1 then
			note(report, "Zones", string.format("zone %s is visible", describe(part)))
		end
	end
	expectInert(report, "Zones", "Zones", zones)
end

local function checkSpawns(report: Report, root: Instance, frame: CFrame)
	local spawns = root:FindFirstChild("Spawns")
	if spawns == nil then
		return -- reported by checkArenaTree
	end
	local found: { [string]: Vector3 } = {}
	for _, spec in { { name = "PadA", z = -PAD_Z, facing = 1 }, { name = "PadB", z = PAD_Z, facing = -1 } } do
		local pad = spawns:FindFirstChild(spec.name)
		if pad == nil or not pad:IsA("BasePart") then
			note(report, "Spawns", string.format("Spawns/%s is missing or not a part", spec.name))
			continue
		end
		local part = pad :: BasePart
		local relative = frame:ToObjectSpace(part.CFrame)
		local position = relative.Position
		found[spec.name] = position
		if not (near(position.X, 0, POSITION_TOLERANCE) and near(position.Z, spec.z, POSITION_TOLERANCE)) then
			note(
				report,
				"Spawns",
				string.format("Spawns/%s is at %s, expected X 0, Z %d", spec.name, vec(position), spec.z)
			)
		end
		local _, high = boxBounds(relative, part.Size)
		if position.Y < -POSITION_TOLERANCE or high.Y > PAD_MAX_TOP then
			note(
				report,
				"Spawns",
				string.format("Spawns/%s does not lie on the floor (centre %s)", spec.name, vec(position))
			)
		end
		if relative.LookVector.Z * spec.facing < DIRECTION_DOT then
			note(
				report,
				"Spawns",
				string.format(
					"Spawns/%s faces %s, expected %sZ",
					spec.name,
					vec(relative.LookVector),
					if spec.facing > 0 then "+" else "-"
				)
			)
		end
	end
	local a, b = found.PadA, found.PadB
	if a and b and not near((a - b).Magnitude, 2 * PAD_Z, POSITION_TOLERANCE * 2) then
		note(
			report,
			"Spawns",
			string.format("the pads are %.2f studs apart, expected %d", (a - b).Magnitude, 2 * PAD_Z)
		)
	end
end

local function checkDecor(report: Report, root: Instance, contract: ArenaContract)
	local decor = root:FindFirstChild("Decor")
	if decor == nil then
		return -- reported by checkArenaTree
	end
	local parts = partsIn(decor)
	if #parts > contract.maxDecorParts then
		note(report, "Decor", string.format("Decor has %d parts, budget %d", #parts, contract.maxDecorParts))
	end
	for _, part in parts do
		if part.CanCollide or part.CanQuery then
			note(
				report,
				"Decor",
				string.format("Decor part %s must have CanCollide and CanQuery false", describe(part))
			)
		end
	end
end

-- The checks of an arena target with this contract.
local function arenaVerifier(contract: ArenaContract): (report: Report, root: Instance, deps: Deps?) -> ()
	return function(report: Report, root: Instance, _deps: Deps?)
		local all = everything(root)
		checkArenaTree(report, root, all, contract)
		local frame = checkOrigin(report, root)
		checkGeometry(report, root, frame, contract)
		checkZones(report, root, frame)
		checkSpawns(report, root, frame)
		checkDecor(report, root, contract)
	end
end

-- Target id -> target-specific checks.
local CHECKS: { [string]: (report: Report, root: Instance, deps: Deps?) -> () } = {
	shapes = verifyShapes,
	lobby = verifyLobby,
	capsules = verifyCapsules,
}
for target, contract in ARENA_CONTRACTS do
	CHECKS[target] = arenaVerifier(contract)
end

-- Public

-- True when two oriented boxes overlap by more than `epsilon` studs along every separating axis (default 0: any
-- overlap; faces that only touch never count). The boxes are given by CFrame and Size, like a part's bounds.
Verify.boxesOverlap = boxesOverlap

function Verify.verify(target: string, root: Instance?, deps: Deps?): { string }
	local report = newReport()
	if typeof(root) ~= "Instance" then
		note(report, "root", string.format("target %q: no root to verify", tostring(target)))
		return finishReport(report)
	end
	local check = CHECKS[target]
	if check == nil then
		note(report, "root", string.format("no verifier for target %q", tostring(target)))
		return finishReport(report)
	end
	checkMarker(report, target, root)
	check(report, root, deps)
	return finishReport(report)
end

-- The place template's leftovers next to the lobby root (see the header): one line per SpawnLocation outside the
-- lobby, and per part outside it whose top face lies on the lobby floor plane across the lobby footprint. Pure
-- inspection of `workspaceLike`'s descendants (a plain Folder works in tests).
function Verify.templateLeftovers(workspaceLike: Instance, lobbyRoot: Instance): { string }
	local lines: { string } = {}
	for _, instance in workspaceLike:GetDescendants() do
		if
			not instance:IsA("BasePart")
			or instance:IsA("Terrain")
			or instance == lobbyRoot
			or instance:IsDescendantOf(lobbyRoot)
		then
			continue
		end
		local part = instance :: BasePart
		if part:IsA("SpawnLocation") then
			table.insert(
				lines,
				string.format(
					"%s is a SpawnLocation outside the lobby: players may spawn there instead of the lobby spawn "
						.. "(remove the template one, PROGRESS Part 3)",
					describe(part)
				)
			)
			continue
		end
		local low, high = boxBounds(part.CFrame, part.Size)
		local onFloorPlane = near(high.Y, LOBBY_FLOOR_Y, FLOOR_TOP_TOLERANCE)
		local acrossLobby = low.X < -LOBBY_FOOTPRINT_HALF.X
			and high.X > LOBBY_FOOTPRINT_HALF.X
			and low.Z < -LOBBY_FOOTPRINT_HALF.Z
			and high.Z > LOBBY_FOOTPRINT_HALF.Z
		if onFloorPlane and acrossLobby then
			table.insert(
				lines,
				string.format(
					"%s has its top at Y %.2f across the lobby: it z-fights with the lobby floor (remove the template "
						.. "Baseplate and the project file's Workspace node, PROGRESS Part 3)",
					describe(part),
					high.Y
				)
			)
		end
	end
	return lines
end

-- Checks that need `root` inside Workspace (after the swap). Returns warning lines; never throws for a missing
-- check. Lobby: the keep-clear test through Workspace:GetPartBoundsInBox. It covers every part in Workspace, so
-- parts no generator owns (Workspace.SD_Manual) are reported too; the lobby's own station bodies and floor
-- coverings are exempt as in verify(). Each hit is confirmed with boxesOverlap so touching faces don't count. Then
-- templateLeftovers.
function Verify.afterSwap(target: string, root: Instance): { string }
	local report = newReport()
	if target ~= "lobby" then
		return finishReport(report)
	end
	if not root:IsDescendantOf(Workspace) then
		note(report, "keep-clear", "keep-clear (GetPartBoundsInBox) skipped: the lobby is not inside Workspace")
		return finishReport(report)
	end
	for _, line in Verify.templateLeftovers(Workspace, root) do
		note(report, "template", line)
	end
	local all = everything(root)
	local holders = stationHolders(all, root)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _, volume in tagged(all, TAG_KEEP_CLEAR) do
		if not volume:IsA("BasePart") then
			continue
		end
		local box = volume :: BasePart
		params.FilterDescendantsInstances = { box, Workspace.Terrain }
		for _, part in Workspace:GetPartBoundsInBox(box.CFrame, box.Size, params) do
			if
				isKeepClearCandidate(part, root, holders)
				and boxesOverlap(box.CFrame, box.Size, part.CFrame, part.Size, OVERLAP_EPSILON)
			then
				note(
					report,
					"keep-clear",
					string.format("keep-clear (GetPartBoundsInBox): %s reaches into %s", describe(part), describe(box))
				)
			end
		end
	end
	return finishReport(report)
end

return Verify
