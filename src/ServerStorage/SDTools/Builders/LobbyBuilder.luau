--!strict
-- LobbyBuilder: builds the lobby Workspace.SD_Lobby as the Claude Design hub (design package sd/lobby.js; user decision
-- 2026-10-11 "build the design's lobby", phase 3 spec decisions D1-D14), with the game's stations, Grip pods (§17.6)
-- and giant pads (§17.6.1) inside it. Server only, Edit mode only (ServerStorage.SDTools); called by Main's pipeline
-- (target "lobby"), never at runtime. Contract (Generated.BuildContext / BuildResult): build(ctx) returns
-- { ok, root, warnings, error } with the new tree UNPARENTED and marked GeneratorId "lobby"; it never parents anything
-- into the place. Relative requires, or modules of the injected ctx.Shared clone (never an absolute require).
--
-- Data: what the game reads (stations, stands, prompts, pads, targets, signs, volumes, the station frames) comes from
-- Shared World/WorldLayout; colours are Art/Palette tokens ("Lobby kit"); text is Shared Strings (the design's plate
-- words are world.* keys, D10); the giant pads' Live line uses Config.Grip.Pads[tier].level; the queue board uses
-- Config.Duel.Arena.MaxSlots; the pedestal bands use Art/RarityStyle (D9) in Catalog order (D4). The design's decor is
-- built here, in each station's design frame (WorldLayout.stationFrame: lobby.js:112, 119-130), every number with its
-- `-- design: lobby.js:<line>`; "reading" marks a value the design leaves open, "NOT IN DESIGN" a part the game needs.
-- Kit/Props maps the design's primitives to parts (rounded boxes, cylinders, rings as collars or annuli, gumdrops).
--
-- Static default states (D14): each station is built as the design shows its first state (lobby.js:120-129, "set"):
-- the box Available (reveal ring lit), the shop Purchasable (turntable ring lit), the daily gift Ready (ring lit), the
-- queue empty (no lights: D2, presentation only), the squeeze meters full, the quest cards in progress, the royal pod
-- Locked, every lock + rope shown (WorldBinder hides them per viewer, D5). Left to state binders: the queue lights and
-- portal, the box lid / beam / rope / reveal toy, the shop's lock / check, the quest stamps, the daily lid / check /
-- clock, the squeeze meters, the royal crown and ring. Neon only on the lit state rings (D7); no outlines (D8); the
-- scale avatars, labels, cameras and footprint rings are never built (spec B.15).
--
-- Tree (station models with a prompt are Atomic and < 64 studs, so a prompt and its SurfaceGui stream together, §7.7):
--   SD_Lobby (Model, ModelStreamingMode Default, marked SD_Generated / lobby / VERSION)
--     Ground       base slab, floor seams, paths and the promenade rings (lobby.js:115-116, 133-142)
--     Boundaries   4 invisible walls (SD_Boundary)
--     Spawn        medallion, rim, logo plate (spawn logo sign), SpawnLocation (SD_LobbySpawn), wayfinding post
--     DuelGate     stage, step = podium (SD_QueuePodium + prompt), arch, slot board, 10 queue pads, queue board
--                  valance (SD_QueueBoard, NOT IN DESIGN), ReturnPoint1/2 (SD_ReturnPoint, Slot)
--     GiftBoxCounter dais, GiftBox (the mystery box, SD_Ambient breathe), reveal pedestal (SD_BoxStand, BoxId + prompt)
--                  with its ring, OddsBoard (Title + live Body)
--     ShopCounter  floor, back wall and shelves, counter (SD_ShopCounter + prompt), awning, display case, turntable,
--                  the design's toys
--     Collection   floor, 7 bays, 14 pedestals (SD_CollectionPedestal, Slot + Inspect prompt; the squishies are
--                  client-built) with rarity bands, kiosk (SD_CollectionKiosk + prompt)
--     QuestBoard   floor, posts, cork (SD_QuestBoard + prompt), frame, header, 9 cards
--     DailyStand   dais (SD_DailyStand + prompt), GiftBox (SD_Ambient spinBob), ring, 7-day calendar, Status plate
--     SqueezeZone  floor, plinth, Statue (Kitty Bread, SD_Ambient breathe) + StatueSparkle, 6 foam mats
--                  (SD_SqueezeStation, StationId, GripTier 1) with meters
--     PracticeRange LaneFloor, FiringLine, ThrowBox (SD_PracticeZone), Backstop (in the pillow wall), Targets (9
--                  SD_PracticeTarget bullseye boards: TargetId, Distance, Moving, RailLength, Period; "Body" mesh),
--                  rope rails, board
--     GripGym / RoyalPod  floors, white bases / daises, jelly gates (SD_GripGate, invisible), lock + rope decor
--                  (SD_GripLock, GripTier), pod signs (SD_GripSign) and GiantPad_<key> (Atomic, SD_GiantPad: GripTier,
--                  PadKey): Collision (the invisible station box, SD_SqueezeStation) and Body (the design pad: base,
--                  quilted tiles inside the rounded footprint, SD_PadAccent parts path A keeps visible); no Face (D5)
--     Kit          perimeter walls, pillars, shelves, windows, hedges, lamps, trees, benches, the kit sample bay
--     Decor        Lollipop1..4 (Atomic, SD_Ambient spin)
--     KeepClear / AudioZones (Folders) invisible volumes
-- Lobby background motion (§18.5.1 A8, D12): Decor/Lollipop1..4 "spin", DailyStand/GiftBox "spinBob",
-- GiftBoxCounter/GiftBox and SqueezeZone/Statue "breathe" (SD_Ambient + SD_AmbientKind); none of their parts
-- collides, is queried or is touched. Every ProximityPrompt is created DISABLED (WorldBinder enables a stand's prompt
-- only when its UI exists, §7.6) with SD_TextKey (and SD_AltTextKey). Signs: Kit/Signs (static lines SD_Sign +
-- SD_TextKey; baked/live lines without SD_TextKey); the design's plates have no wood frame (Kit/Signs plate).
-- Self-check (§7.7): exact tag counts (WorldLayout.TagCounts), unique StationIds, one moving target, every prompt
-- disabled, inert SD_Ambient decor, part and SurfaceGui budgets; any problem fails the build. The keep-clear test
-- (oriented boxes, station models' own parts exempt as in Verify) and a part-count report come back as warnings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Generated = require(script.Parent.Parent.Generated)
local Prims = require(script.Parent.Parent.Kit.Prims)
local Props = require(script.Parent.Parent.Kit.Props)
local Signs = require(script.Parent.Parent.Kit.Signs)
local Verify = require(script.Parent.Parent.Verify)

local BARRIER_GROUP = "SD_Barrier" -- the invisible walls' collision group (see buildGround)

-- Types

type BuildContext = Generated.BuildContext
type BuildResult = Generated.BuildResult

type Deps = {
	Strings: any,
	Palette: any,
	Config: any,
	GripPads: { any },
	WorldLayout: any,
	SquishyBuilder: any,
	RarityStyle: any,
	Catalog: any,
}

type State = {
	deps: Deps,
	L: any, -- World/WorldLayout
	root: Model,
	warnings: { string },
	style: Signs.Style,
	models: { [string]: Instance }, -- station model name -> model (sign owners)
	hosts: { [string]: BasePart }, -- "<owner>/<part>" -> the part that carries a sign
	template: BasePart?, -- ReplicatedStorage.SD_ShapeLibrary.RoundedBox
	warnedTemplate: boolean,
}

-- Constants

local GENERATOR_ID = "lobby"
local VERSION = 2 -- phase 3: the design hub
local ROOT_NAME = "SD_Lobby"

local SHAPE_LIBRARY_NAME = "SD_ShapeLibrary"
local ROUNDED_BOX_NAME = "RoundedBox"

local ATTR_ALT_TEXT_KEY = "SD_AltTextKey" -- the toggled (Leave Queue) / relabelled (Shop Squishies) prompt text
local ATTR_PAD_ACCENT = "SD_PadAccent" -- a giant pad Body part path A keeps visible (GiantPadController)
-- SD_AmbientKind values (§18.5.1 A8; Anim/AmbientMath reads the same three).
local AMBIENT_SPIN = "spin" -- the lollipops
local AMBIENT_SPIN_BOB = "spinBob" -- the daily gift box
local AMBIENT_BREATHE = "breathe" -- the mystery box and the statue

local SIGN_STYLE_TOKENS = { panel = "Cream", frame = "Cocoa", text = "Ink", stroke = "Cream" } -- §7.7 (non-plate signs)
-- Design materials (lobby.js:73-81) as Palette tokens.
local QUEST_CARD_TOKENS = { "LobbyQuestMint", "LobbyQuestButter", "LobbyQuestPink" } -- design: lobby.js:296 (colCols)
local QUEST_BAR_TOKENS = { "LobbyMint", "LobbyQuestBar", "LobbyStrawberry" } -- design: lobby.js:296 (colInk)
local QUEST_FILLS = { 0.75, 0.4, 0.15 } -- design: lobby.js:303 (Available)
-- design: lobby.js:300 ((r() - 0.5) × 0.08 with r = rng(11), kit.js:5-8; reproduced, cards c = 1..3, k = 1..3)
local QUEST_CARD_TILTS = { { 0.0009, 0.0024, 0.0086 }, { 0.0072, 0.0281, 0.003 }, { -0.0336, 0.0024, 0.0086 } }
local SHOP_GIFT_TOKENS = { "LobbyMint", "LobbyButter", "LobbyViolet", "LobbySky", "LobbyStrawberry" } -- lobby.js:241
local RANK_TOKENS = { "LobbyRankGrey", "LobbyMint", "LobbySky", "LobbyViolet", "LobbyButter", "LobbyStrawberry" } -- 370
local SHELF_BLOB_TOKENS = { "LobbyStrawberry", "LobbyButter", "LobbySky", "LobbyViolet" } -- design: lobby.js:439
local HEDGE_TOKENS = { "LobbyMint", "LobbyStrawberry", "LobbyButter", "LobbyViolet" } -- design: lobby.js:443
-- The corner lollipops' swirl colours (design: lobby.js:468), in WorldLayout.Props.lollipops order.
local LOLLIPOP_STICK = "LobbyTrimWhite"
-- Practice targets (D3): the design's bullseye boards (lobby.js:406-409) on the game's 9 targets.
local TARGET_RINGS = { -- design: lobby.js:409 (the inner ring discs, outer to inner)
	{ radius = 2.4, token = "LobbyStrawberry" },
	{ radius = 1.7, token = "LobbyTrimWhite" },
	{ radius = 1, token = "LobbyStrawberryRed" },
}
local TARGET_RING_STEP = 0.12 -- design: lobby.js:409
local TARGET_POLE_OVERLAP = 0.45 -- design: lobby.js:407-408 (the pole's top, 7.15, is 0.45 under the board centre)
local RAIL = { width = 0.4, height = 0.07, token = "LobbyPlum" } -- NOT IN DESIGN: the moving target's rail (§5.11)
-- World kit decor the design places between the paths (lobby.js:445-467: mids nudged off the station cameras),
-- reproduced (phase 3 spec B.14): cotton trees (pink, k 1.05), candy lamps, wafer benches (x, z, yaw).
local TREES = { Vector3.new(-10.15, 0, -39.72), Vector3.new(36.51, 0, 18.65), Vector3.new(-40.84, 0, 3.63) }
local LAMPS = { Vector3.new(40.98, 0, 1.41), Vector3.new(31.21, 0, 26.59), Vector3.new(-39.02, 0, -12.59) }
local BENCHES = {
	{ -11.14, -43.6, 3.3917 },
	{ 44.99, -0.8, 1.5886 },
	{ 35.21, 28.03, 0.8985 },
	{ 9.86, 43.91, 0.221 },
}
-- Statue sparkle (§7.7 "ambient sparkle at the statue"): rate, lifetime and texture from Config.Vfx; the look below.
local SPARKLE = {
	token = "Lemon",
	size = 0.5,
	speedMin = 8,
	speedMax = 10,
	drag = 2, -- from the statue's middle they drift 4-5 studs out (past its surface), slow down and fade
	spread = Vector2.new(180, 180),
}
local RETURN_MARKER_SIZE = Vector3.new(2, 0.2, 2)
local PAD_TILE_INSET = 0.5 -- reading: quilted tiles whose centre lies this far inside the rounded footprint
local PAD_TUFT = Vector3.new(0.76, 0.4, 0.76) -- reading: the royal tufts (SPH 0.38, lobby.js:386) pressed to buttons

-- `require` with a runtime-chosen ModuleScript (the injected Shared clone); the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local LobbyBuilder = {}
LobbyBuilder.GENERATOR_ID = GENERATOR_ID
LobbyBuilder.VERSION = VERSION
LobbyBuilder.ROOT_NAME = ROOT_NAME

-- Private: setup -----------------------------------------------------------------------------------------------------

local function failure(warnings: { string }, message: string): BuildResult
	return { ok = false, root = nil, warnings = warnings, error = message }
end

-- Requires the module at `path` ("Art/Palette") inside the injected Shared clone.
local function requirePath(shared: Instance, path: string): (any, string?)
	local node: Instance? = shared
	for segment in string.gmatch(path, "[^/]+") do
		node = if node then node:FindFirstChild(segment) else nil
	end
	if node == nil or not node:IsA("ModuleScript") then
		return nil, string.format("deps.Shared has no %s module", path)
	end
	local ok, result = pcall(dynamicRequire, node :: ModuleScript)
	if not ok then
		return nil, string.format("could not load Shared %s: %s", path, tostring(result))
	end
	return result, nil
end

local function loadDeps(shared: Instance): (Deps?, string?)
	local loaded: { [string]: any } = {}
	for _, entry in
		{
			{ "Strings", "Strings" },
			{ "Palette", "Art/Palette" },
			{ "SquishyBuilder", "Art/SquishyBuilder" },
			{ "RarityStyle", "Art/RarityStyle" },
			{ "Catalog", "Catalog" },
			{ "Config", "Config" },
			{ "WorldLayout", "World/WorldLayout" },
		}
	do
		local module, err = requirePath(shared, entry[2])
		if module == nil then
			return nil, err
		end
		loaded[entry[1]] = module
	end
	local config = loaded.Config
	local grip = if type(config) == "table" then config.Grip else nil
	if type(grip) ~= "table" or type(grip.Pads) ~= "table" then
		return nil, "Config.Grip.Pads is missing"
	end
	return {
		Strings = loaded.Strings,
		Palette = loaded.Palette,
		Config = config,
		GripPads = grip.Pads,
		WorldLayout = loaded.WorldLayout,
		SquishyBuilder = loaded.SquishyBuilder,
		RarityStyle = loaded.RarityStyle,
		Catalog = loaded.Catalog,
	},
		nil
end

local function color(state: State, token: string?): Color3
	local value = if token then state.deps.Palette[token] else nil
	if typeof(value) ~= "Color3" then
		error(string.format("[SD][LobbyBuilder] Art/Palette has no colour token %s", tostring(token)), 0)
	end
	return value
end

-- Every Strings key the build bakes or tags (sign lines, prompts). Sorted, without duplicates.
local function neededKeys(L: any): { string }
	local list: { string } = {}
	for _, sign in L.Signs do
		Signs.keysOf(sign, list)
	end
	for _, stand in { L.QuestBoard, L.DailyStand, L.DuelGate, L.GiftBoxCounter, L.ShopCounter, L.Collection } do
		table.insert(list, stand.prompt.actionKey)
		if stand.prompt.altActionKey then
			table.insert(list, stand.prompt.altActionKey)
		end
	end
	for _, pedestal in L.Collection.pedestals do
		table.insert(list, pedestal.prompt.actionKey)
	end
	local seen: { [string]: boolean } = {}
	local keys: { string } = {}
	for _, key in list do
		if not seen[key] then
			seen[key] = true
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

local function missingKeys(deps: Deps): { string }
	local missing: { string } = {}
	for _, key in neededKeys(deps.WorldLayout) do
		if deps.Strings.resolve(key) == nil then
			table.insert(missing, key)
		end
	end
	return missing
end

-- Private: small builders ---------------------------------------------------------------------------------------------

-- A design point in a frame: (x, y, z) then the design's Euler XYZ turn (three.js rotation = CFrame.Angles).
local function at(frame: CFrame, x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
	return frame * CFrame.new(x, y, z) * CFrame.Angles(rx or 0, ry or 0, rz or 0)
end

local function stationCF(state: State, id: string): CFrame
	return state.L.stationFrame(id) :: CFrame
end

-- A design rounded box (rb, lobby.js:10) through Kit/Props; warns once when the shape library is missing.
local function rb(
	state: State,
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	token: string,
	flags: Prims.Flags?,
	n: number?
): BasePart
	local part, missing = Props.rb(state.template, parent, name, size, cframe, color(state, token), flags, n)
	if missing and not state.warnedTemplate then
		state.warnedTemplate = true
		table.insert(
			state.warnings,
			string.format(
				"ReplicatedStorage.%s.%s is missing (run the shapes generator): the design's rounded boxes are plain boxes",
				SHAPE_LIBRARY_NAME,
				ROUNDED_BOX_NAME
			)
		)
	end
	return part
end

-- A design cylinder C(r0, r1, h) (lobby.js:13): `radius` is its bottom radius r1; its axis is the frame's Y.
local function cyl(
	state: State,
	parent: Instance,
	name: string,
	radius: number,
	height: number,
	cframe: CFrame,
	token: string,
	flags: Prims.Flags?
): Part
	return Props.cylinder(parent, name, 2 * radius, height, cframe, color(state, token), flags)
end

-- A collar standing in for a design torus TOR(R, t) around a solid core (Kit/Props header): 2·(R + t) wide, `height`
-- tall, centred on `cframe` (its axis the frame's Y).
local function collar(
	state: State,
	parent: Instance,
	name: string,
	ringRadius: number,
	tube: number,
	height: number,
	cframe: CFrame,
	token: string
): Part
	-- Prims.LAYER below the given place: a collar flush with its core's top would fight it and flicker; the core's
	-- face wins, the collar shows as the band around it (user bug report 2026-10-11).
	local sunk = cframe * CFrame.new(0, -Prims.LAYER, 0)
	return Props.cylinder(parent, name, 2 * (ringRadius + tube), height, sunk, color(state, token))
end

local function ball(
	state: State,
	parent: Instance,
	name: string,
	radius: number,
	position: Vector3,
	token: string
): Part
	return Props.ball(parent, name, 2 * radius, position, color(state, token))
end

-- A part from a WorldLayout Box ({ position, size, facing?, yaw?, color? }).
local function boxPart(
	state: State,
	name: string,
	box: any,
	parent: Instance,
	flags: Prims.Flags?,
	token: string?
): Part
	return Prims.part({
		name = name,
		size = box.size,
		cframe = state.L.boxCFrame(box),
		color = color(state, token or box.color),
		flags = flags,
		parent = parent,
	})
end

-- An invisible volume from a WorldLayout Volume ({ name?, position, size, yaw? }).
local function volumePart(name: string, volume: any, parent: Instance): Part
	return Prims.part({
		name = name,
		size = volume.size,
		cframe = CFrame.new(volume.position) * CFrame.Angles(0, volume.yaw or 0, 0),
		flags = "volume",
		parent = parent,
	})
end

local function station(state: State, name: string, atomic: boolean): Model
	local model = Prims.model(name, state.root, atomic)
	state.models[name] = model
	return model
end

-- A DISABLED prompt from a WorldLayout Prompt, on `host`.
local function addPrompt(state: State, host: BasePart, spec: any): ProximityPrompt
	local prompt = Prims.prompt(host, spec.position, {
		actionText = state.deps.Strings.resolve(spec.actionKey) or "",
		textKey = spec.actionKey,
		maxDistance = spec.maxDistance,
		lineOfSight = spec.requiresLineOfSight,
	})
	if spec.altActionKey then
		prompt:SetAttribute(ATTR_ALT_TEXT_KEY, spec.altActionKey)
	end
	return prompt
end

-- Moves every part of `model` rigidly so its pivot (PrimaryPart, else WorldPivot) lands on `target`. Welds keep their
-- C0/C1 (they are relative), so a SquishyBuilder model stays assembled.
local function moveModel(model: Model, target: CFrame)
	local primary = model.PrimaryPart
	local pivot = if primary then primary.CFrame else model.WorldPivot
	local delta = target * pivot:Inverse()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CFrame = delta * descendant.CFrame
		end
	end
	if primary == nil then
		model.WorldPivot = target
	end
end

-- The size of the visible parts of a model built at the origin (its own axes).
local function modelSize(model: Model): Vector3
	local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local cf, half = part.CFrame, part.Size / 2
			local extent = Vector3.new(
				math.abs(cf.XVector.X) * half.X + math.abs(cf.YVector.X) * half.Y + math.abs(cf.ZVector.X) * half.Z,
				math.abs(cf.XVector.Y) * half.X + math.abs(cf.YVector.Y) * half.Y + math.abs(cf.ZVector.Y) * half.Z,
				math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
			)
			low = low:Min(cf.Position - extent)
			high = high:Max(cf.Position + extent)
		end
	end
	return if low.X == math.huge then Vector3.zero else high - low
end

-- A squishy toy like the design's toyAt (lobby.js:35-39): built with Art/SquishyBuilder ("World" mode) so that
-- max(height, 0.8 × width) = `tall`, its lowest point on `bottom`, its face looking along `facing`. A builder
-- failure is a warning (the station still works), never a crash.
local function placeToy(
	state: State,
	name: string,
	blueprintId: string,
	bottom: Vector3,
	facing: Vector3,
	tall: number,
	parent: Instance
): Model?
	local build = state.deps.SquishyBuilder.build
	local ok, probe = pcall(build, blueprintId, "World", 1)
	if not ok or typeof(probe) ~= "Instance" or not probe:IsA("Model") then
		table.insert(
			state.warnings,
			string.format("%s: SquishyBuilder.build(%q) failed: %s", name, blueprintId, tostring(probe))
		)
		return nil
	end
	local size = modelSize(probe :: Model)
	probe:Destroy()
	local measure = math.max(size.Y, 0.8 * size.X)
	if measure <= 0 then
		table.insert(state.warnings, string.format("%s: blueprint %s has no visible parts", name, blueprintId))
		return nil
	end
	local model = build(blueprintId, "World", tall / measure) :: Model
	local lowest = Prims.lowestY(model) -- the model is built around its pivot at the origin
	local standing = if lowest == math.huge then 0 else lowest
	moveModel(model, Prims.facing(bottom - Vector3.new(0, standing, 0), facing))
	model.Name = name
	model.Parent = parent
	return model
end

-- Marks decor the client moves (§18.5.1 A8): SD_Ambient + SD_AmbientKind. A model the builder could not make (nil) is
-- left out, so the exact SD_Ambient count of the self-check reports it.
local function markAmbient(state: State, model: Model?, kind: string)
	if model == nil then
		return
	end
	local L = state.L
	Prims.tag(model, L.Tags.Ambient, { [L.Attributes.AmbientKind] = kind })
end

-- The world direction a design group's front (+Z) looks along.
local function frontOf(frame: CFrame): Vector3
	return frame:VectorToWorldSpace(Vector3.zAxis)
end

-- Private: hub --------------------------------------------------------------------------------------------------------

local function buildGround(state: State)
	local L = state.L
	local ground = Prims.model("Ground", state.root, false)
	boxPart(state, "floor_base", L.Lobby.baseSlab, ground, "solid") -- design: lobby.js:115
	-- design: lobby.js:116 (tile seams every 12 studs from 8 inside the hub edge, 0.25 wide, 0.03 thick)
	local box = L.Lobby.footprint
	local seam = color(state, "LobbySeam")
	local depth, width = box.maxZ - box.minZ, box.maxX - box.minX
	local x = box.minX + 8
	while x < box.maxX do
		Prims.part({
			name = "floor_tile_line",
			size = Vector3.new(0.25, 0.03, depth),
			cframe = CFrame.new(x, 0.015, 0),
			color = seam,
			flags = "decor",
			shadow = false,
			parent = ground,
		})
		x += 12
	end
	local z = box.minZ + 8
	while z < box.maxZ do
		Prims.part({
			name = "floor_tile_line",
			size = Vector3.new(width, 0.03, 0.25),
			cframe = CFrame.new(0, 0.015, z),
			color = seam,
			flags = "decor",
			shadow = false,
			parent = ground,
		})
		z += 12
	end
	-- Paths (lobby.js:134): a curb box w + 1.8 wide (0.08 thick) under the path box (0.1), each with a round end.
	for _, path in L.Paths do
		local delta = path.to - path.from
		local frame = CFrame.new((path.from + path.to) / 2) * CFrame.Angles(0, -math.atan2(delta.Z, delta.X), 0)
		local length = delta.Magnitude
		local curbWidth = path.width + L.Promenade.curbExtra
		local curbTop = 0.1 - Prims.LAYER -- under the path's 0.1 top (0.08 flickered)
		Prims.part({
			name = "paint_path_curb",
			size = Vector3.new(length, curbTop, curbWidth),
			cframe = frame + Vector3.new(0, curbTop / 2, 0),
			color = color(state, "LobbyCurb"),
			flags = "decor",
			shadow = false,
			parent = ground,
		})
		Prims.part({
			name = "paint_path",
			size = Vector3.new(length - 2 * Prims.LAYER, 0.1, path.width), -- ends clear the curb's (flicker)
			cframe = frame + Vector3.new(0, 0.05, 0),
			color = color(state, "LobbyPath"),
			flags = "decor",
			shadow = false,
			parent = ground,
		})
		cyl(
			state,
			ground,
			"paint_path_curb",
			curbWidth / 2,
			curbTop,
			CFrame.new(path.to + Vector3.new(0, curbTop / 2, 0)),
			"LobbyCurb"
		)
		cyl(
			state,
			ground,
			"paint_path",
			path.width / 2,
			0.1,
			CFrame.new(path.to + Vector3.new(0, 0.05, 0)),
			"LobbyPath"
		)
	end
	-- The promenade rings (lobby.js:142): curb 22.6-33.4 under path 23.4-32.6, as stacked discs whose inner parts are
	-- covered by discs of the colour inside them (reading: no flat-ring primitive).
	local P = L.Promenade
	local layers = {
		{ name = "paint_promenade_curb", radius = P.curb.outer, top = P.curb.top, token = "LobbyCurb" },
		{ name = "paint_promenade", radius = P.path.outer, top = P.path.top, token = "LobbyPath" },
		{ name = "paint_promenade_curb", radius = P.path.inner, top = P.path.top + Prims.LAYER, token = "LobbyCurb" },
		{
			name = "paint_promenade_floor",
			radius = P.curb.inner,
			top = P.path.top + 2 * Prims.LAYER,
			token = "LobbyFloor",
		},
	}
	for _, layer in layers do
		cyl(state, ground, layer.name, layer.radius, layer.top, CFrame.new(0, layer.top / 2, 0), layer.token)
	end
	local walls = Prims.folder("Boundaries", state.root)
	for _, wall in L.Lobby.Boundaries do
		local part = Prims.part({
			name = wall.name,
			size = wall.size,
			cframe = CFrame.new(wall.position),
			flags = "barrier",
			parent = walls,
		})
		Prims.tag(part, L.Tags.Boundary)
		-- Roblox ignores CanQuery = false on a colliding part: in the Default group these 60-stud walls caught the aim
		-- ray, so a practice throw aimed high flew up to a point on the wall (user bug report 2026-10-11, "it goes all
		-- the way up"). The arena walls' group (ArenaBuilder.BARRIER_GROUP) collides only with SD_Characters.
		local ok, err = pcall(function()
			part.CollisionGroup = BARRIER_GROUP
		end)
		if not ok then
			table.insert(state.warnings, string.format("could not set %s.CollisionGroup: %s", part.Name, tostring(err)))
		end
	end
end

local function buildSpawn(state: State)
	local L = state.L
	local S = L.Spawn
	local model = station(state, S.model, true)
	local F = stationCF(state, "spawn")
	local medallion = S.medallion
	cyl(
		state,
		model,
		"spawn_medallion",
		medallion.diameter / 2,
		medallion.height,
		CFrame.new(medallion.position),
		medallion.color,
		"solid"
	) -- design: lobby.js:147
	-- spawn_medallion_rim TOR(14.25, 0.55) at the top edge (lobby.js:148): a strawberry collar flush with the top.
	collar(state, model, "spawn_medallion_rim", 14.25, 0.55, 1.1, at(F, 0, S.top - 0.55, 0), "LobbyStrawberry")
	local box = S.location
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Size = box.size
	spawn.CFrame = L.boxCFrame(box)
	spawn.Color = color(state, box.color)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Transparency = 1 -- reading: the design's medallion is the spawn (lobby.js:147)
	spawn.CastShadow = false
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.CanQuery = true
	spawn.CanTouch = true -- a SpawnLocation keeps its default touch
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0 -- no forcefield (§7.6)
	spawn.Enabled = true
	spawn.Parent = model
	Prims.tag(spawn, L.Tags.LobbySpawn)
	-- The logo's floor plate (lobby.js:149-155): invisible, it carries the logo SurfaceGui.
	state.hosts[S.model .. "/logoPlate"] = Prims.part({
		name = "paint_spawn_logo",
		size = S.logoPlate.size,
		cframe = CFrame.new(S.logoPlate.position),
		transparency = 1,
		shadow = false,
		flags = "decor",
		parent = model,
	})
	-- The wayfinding post (lobby.js:157-158) and its six arrows (159-164).
	local post = S.post
	cyl(state, model, "wayfinding_pole", 0.85, 16, at(post, 0, 8, 0), "LobbyTrimWhite") -- design: lobby.js:158
	ball(state, model, "wayfinding_finial", 1.1, at(post, 0, 16.4, 0).Position, "LobbyStrawberry")
	cyl(state, model, "wayfinding_base", 2.6, 0.8, at(post, 0, 0.4, 0), "LobbyPlum")
	for _, arrow in S.arrows do
		Props.arrow(model, arrow.frame, color(state, arrow.color))
	end
end

-- Private: stations ---------------------------------------------------------------------------------------------------

local function buildDuelGate(state: State)
	local L = state.L
	local gate = L.DuelGate
	local model = station(state, gate.model, true)
	local F = stationCF(state, "duel")
	rb(state, model, "queue_stage", gate.stage.size, L.boxCFrame(gate.stage), gate.stage.color, "solid", 4) -- lobby.js:172
	rb(state, model, "queue_stage_trim", Vector3.new(48.8, 0.6, 30.8), at(F, 0, 0.3, 0), "LobbyPlum", "solid", 6)
	-- The podium (SD_QueuePodium) is the design's queue_stage_step (lobby.js:173).
	local podium =
		rb(state, model, "queue_stage_step", gate.podium.size, L.boxCFrame(gate.podium), gate.podium.color, "solid", 4)
	Prims.tag(podium, gate.podiumTag)
	addPrompt(state, podium, gate.prompt)
	for _, e in { -1, 1 } do
		local team = if e < 0 then "LobbyMint" else "LobbyStrawberry" -- design: lobby.js:175
		rb(state, model, "gate_pillar", Vector3.new(6, 26, 6), at(F, e * 15, 14.6, -9), team, "solid", 4) -- lobby.js:176
		for _, y in { 5.5, 17 } do
			rb(
				state,
				model,
				"gate_pillar_band",
				Vector3.new(7, 1.6, 7),
				at(F, e * 15, y, -9),
				"LobbyTrimWhite",
				"decor",
				5
			)
		end
		Props.gumdrop(model, "gate_pillar_cap", at(F, e * 15, 27.6, -9), 0.95, color(state, team)) -- design: lobby.js:177
		-- design: lobby.js:178; Prims.LAYER up so its top clears the pennant's (flicker)
		cyl(state, model, "gate_flag_pole", 0.25, 7, at(F, e * 15, 37 + Prims.LAYER, -9), "LobbyTrimWhite")
		Prims.part({
			name = "gate_pennant",
			size = Vector3.new(4.2, 2.6, 0.2),
			cframe = at(F, e * 15 + e * 2.2, 39.2, -9),
			color = color(state, team),
			flags = "decor",
			parent = model,
		})
		cyl(state, model, "slot_board_post", 0.4, 8, at(F, e * 10, 30.8, -9), "LobbyGold") -- design: lobby.js:179
		rb(
			state,
			model,
			"gate_curtain",
			Vector3.new(3.4, 22, 1.6),
			at(F, e * 10.6, 12.6, -9.4),
			"LobbyRoyalVelvet",
			"decor",
			3
		)
		rb(state, model, "gate_curtain_tie", Vector3.new(4, 1, 2.2), at(F, e * 10.6, 9, -9.4), "LobbyGold", "decor", 6)
	end
	rb(state, model, "gate_lintel", Vector3.new(38, 6, 7), at(F, 0, 24, -9), "LobbyPlum", "decor", 4) -- lobby.js:182
	rb(state, model, "gate_lintel_trim", Vector3.new(39, 1, 7.6), at(F, 0, 20.6, -9), "LobbyGold", "decor", 6)
	cyl(state, model, "gate_badge", 5.4, 1.6, at(F, 0, 24, -5.2, math.pi / 2), "LobbyButter") -- design: lobby.js:183
	-- gate_badge_rim TOR(5.4, 0.4) at z -4.4 (lobby.js:183): a gold collar around the badge, flush with its front.
	collar(state, model, "gate_badge_rim", 5.4, 0.4, 0.8, at(F, 0, 24, -4.8, math.pi / 2), "LobbyGold")
	rb(state, model, "slot_board", Vector3.new(28, 4.6, 1.4), at(F, 0, 37, -9), "LobbyPlum", "decor", 5) -- lobby.js:187
	for i = 0, 9 do -- design: lobby.js:188 (off: trim white, D2)
		cyl(state, model, "slot_light", 0.95, 0.5, at(F, -11.25 + i * 2.5, 37, -8.2, math.pi / 2), "LobbyTrimWhite")
	end
	rb(state, model, "slot_divider", Vector3.new(0.5, 3.4, 0.6), at(F, 0, 37, -8.2), "LobbyTrimWhite", "decor", 4)
	for _, e in { -1, 1 } do -- design: lobby.js:190-195 (5 mint pads west, 5 strawberry pads east)
		for i = 0, 4 do
			local x, z = e * 6.5, -3 + i * 3.8
			cyl(state, model, "queue_pad", 1.8, 0.5, at(F, x, 1.85, z), "LobbyTrimWhite", "solid")
			-- queue_pad_ring TOR(1.75, 0.28) at 2.05: a collar flush with the pad top (off: pebble, D2).
			collar(state, model, "queue_pad_ring", 1.75, 0.28, 0.56, at(F, x, 2.1 - 0.28, z), "LobbyPebble")
			cyl(
				state,
				model,
				"queue_pad_paint",
				0.9,
				0.08,
				at(F, x, 2.12, z),
				if e < 0 then "LobbyCourtMint" else "LobbyCourtStrawberry"
			)
		end
	end
	-- NOT IN DESIGN (D11): the live queue board (SD_QueueBoard) as a plum valance under the badge.
	local board = boxPart(state, "StatusBoard", gate.statusBoard, model, "decor", "LobbyPlum")
	Prims.tag(board, gate.boardTag)
	state.hosts[gate.model .. "/statusBoard"] = board
	for _, point in L.ReturnPoints do
		local position = point.position + Vector3.new(0, RETURN_MARKER_SIZE.Y / 2, 0)
		local marker = Prims.part({
			name = "ReturnPoint" .. point.slot,
			size = RETURN_MARKER_SIZE,
			cframe = Prims.facing(position, point.facing),
			flags = "volume",
			parent = model,
		})
		Prims.tag(marker, L.Tags.ReturnPoint, { [L.Attributes.Slot] = point.slot })
	end
end

local function buildGiftBoxCounter(state: State)
	local L = state.L
	local stand = L.GiftBoxCounter
	local model = station(state, stand.model, true)
	local F = stationCF(state, "box")
	local dais = stand.dais
	cyl(state, model, "box_dais", dais.diameter / 2, dais.height, CFrame.new(dais.position), dais.color, "solid") -- lobby.js:209
	collar(state, model, "box_dais_trim", 11.3, 0.45, 0.9, at(F, 0, 1.4 - 0.45, 0), "LobbyGold") -- design: lobby.js:209
	-- The mystery box (lobby.js:210-216): "GiftBox", breathing (D12); its lid stays shut (Available).
	local bx = stand.mysteryBox
	local box = Prims.model("GiftBox", model, false, bx)
	rb(state, box, "box_body", Vector3.new(10, 8, 10), at(bx, 0, 4, 0), "LobbyStrawberry", "decor", 6) -- lobby.js:211
	for _, size in { Vector3.new(2.2, 8.06, 10.12), Vector3.new(10.12, 8.06, 2.2) } do
		Prims.part({
			name = "box_ribbon",
			size = size,
			cframe = at(bx, 0, 4, 0),
			color = color(state, "LobbyButter"),
			flags = "decor",
			parent = box,
		})
	end
	local lid = at(bx, 0, 8, -5) -- box_lid_hinge (lobby.js:212)
	rb(state, box, "box_lid", Vector3.new(10.9, 2, 10.9), at(lid, 0, 1, 5), "LobbyStrawberry", "decor", 6) -- lobby.js:213
	for _, size in { Vector3.new(2.3, 2.06, 11), Vector3.new(11, 2.06, 2.3) } do
		Prims.part({
			name = "box_lid_ribbon",
			size = size,
			cframe = at(lid, 0, 1, 5),
			color = color(state, "LobbyButter"),
			flags = "decor",
			parent = box,
		})
	end
	for _, e in { -1, 1 } do -- design: lobby.js:214 (TOR(1.6, 0.6) loops; reading: ellipsoid lobes)
		Props.ellipsoid(
			box,
			"box_bow_loop",
			Vector3.new(4.4, 4.4, 1.2),
			at(lid, e * 1.7, 3.1, 5, 0, 0, e * 0.7),
			color(state, "LobbyButter")
		)
	end
	ball(state, box, "box_bow_knot", 0.9, at(lid, 0, 2.6, 5).Position, "LobbyButter") -- design: lobby.js:215
	-- The "?" plate (lobby.js:216) is a sign carried by this invisible plate inside the breathing box.
	for _, sign in L.Signs do
		if sign.id == "mysteryBox" then
			state.hosts[stand.model .. "/mysteryPlate"] = Prims.part({
				name = "sign_plate",
				size = sign.size,
				cframe = sign.cframe,
				transparency = 1,
				shadow = false,
				flags = "decor",
				parent = box,
			})
		end
	end
	for _, part in box:GetDescendants() do
		if part:IsA("BasePart") then
			Prims.cosmetic(part)
		end
	end
	markAmbient(state, box, AMBIENT_BREATHE)
	-- The reveal pedestal (lobby.js:217-219) is the SD_BoxStand; its ring is lit mint (Available, D7).
	local standDisc = stand.stand
	local pedestal = cyl(
		state,
		model,
		"reveal_pedestal_body",
		standDisc.diameter / 2,
		standDisc.height,
		CFrame.new(standDisc.position),
		standDisc.color,
		"solid"
	)
	Prims.tag(pedestal, stand.tag, { [L.Attributes.BoxId] = stand.boxId })
	addPrompt(state, pedestal, stand.prompt)
	local ped = at(F, 0, 1.4, 6.6) -- reveal_pedestal group (lobby.js:217)
	local ring = collar(state, model, "reveal_ring", 2.8, 0.3, 0.6, at(ped, 0, 2.6 - 0.3, 0), "LobbyMint") -- lobby.js:219
	ring.Material = Enum.Material.Neon
	-- The odds board (lobby.js:221-228): two gold posts and the cream panel "OddsBoard" (BoxController's).
	local ob = stand.oddsFrame
	for _, e in { -1, 1 } do
		cyl(state, model, "odds_post", 0.3, 7, at(ob, e * 3.4, 3.5, 0), "LobbyGold") -- design: lobby.js:222
	end
	state.hosts[stand.model .. "/oddsBoard"] = boxPart(state, "OddsBoard", stand.oddsBoard, model, "decor")
end

local function buildShopCounter(state: State)
	local L = state.L
	local stand = L.ShopCounter
	local model = station(state, stand.model, true)
	local F = stationCF(state, "shop")
	rb(state, model, "shop_floor", stand.floor.size, L.boxCFrame(stand.floor), "LobbyCushionCream", "solid", 4) -- 238
	rb(state, model, "shop_backwall", Vector3.new(28, 15, 1.6), at(F, 0, 8.3, -6.5), "LobbyCourtStrawberry", "solid", 4)
	rb(
		state,
		model,
		"shop_backwall_cap",
		Vector3.new(28.6, 1.2, 2.4),
		at(F, 0, 16.2, -6.5),
		"LobbyStrawberry",
		"decor",
		6
	)
	for _, y in { 7, 11.5 } do -- design: lobby.js:240
		rb(state, model, "shop_shelf", Vector3.new(24, 0.6, 2.6), at(F, 0, y, -5.2), "LobbyTrimWhite", "decor", 6)
	end
	for i = 0, 9 do -- design: lobby.js:242
		local y, x = if i < 5 then 7.3 else 11.8, -9.6 + (i % 5) * 4.8
		rb(
			state,
			model,
			"shop_gift_box",
			Vector3.new(2.6, 2.4, 2),
			at(F, x, y + 1.2, -5.2),
			SHOP_GIFT_TOKENS[i % 5 + 1],
			"decor",
			6
		)
		Prims.part({
			name = "shop_gift_ribbon",
			size = Vector3.new(0.5, 2.46, 2.06),
			cframe = at(F, x, y + 1.2, -5.2),
			color = color(state, "LobbyTrimWhite"),
			flags = "decor",
			parent = model,
		})
	end
	-- The counter (lobby.js:243) is the SD_ShopCounter.
	local counter = rb(
		state,
		model,
		"shop_counter",
		stand.counter.size,
		L.boxCFrame(stand.counter),
		stand.counter.color,
		"solid",
		4
	)
	Prims.tag(counter, stand.tag)
	addPrompt(state, counter, stand.prompt)
	for i = -4, 4 do -- design: lobby.js:244
		rb(
			state,
			model,
			"shop_counter_groove",
			Vector3.new(0.45, 3.4, 0.4),
			at(F, i * 2.3, 3, 3.55),
			"LobbyWaferGroove",
			"decor",
			4
		)
	end
	rb(state, model, "shop_counter_top", Vector3.new(23.4, 0.8, 6), at(F, 0, 5.6, 1), "LobbyTrimWhite", "solid", 6) -- 245
	for _, e in { -1, 1 } do
		cyl(state, model, "awning_post", 0.45, 13.4, at(F, e * 12.6, 7.4, 6.2), "LobbyTrimWhite") -- design: lobby.js:246
	end
	for i = 0, 9 do -- design: lobby.js:247-248
		local stripe = if i % 2 == 1 then "LobbyMint" else "LobbyTrimWhite"
		Prims.part({
			name = "awning_stripe",
			size = Vector3.new(2.64, 0.5, 13),
			cframe = at(F, -11.88 + i * 2.64, 15, -0.1, 0.28),
			color = color(state, stripe),
			flags = "decor",
			parent = model,
		})
		Props.ellipsoid(
			model,
			"awning_scallop",
			Vector3.new(2.6, 1.6, 0.5),
			at(F, -11.88 + i * 2.64, 13, 6.3),
			color(state, stripe)
		)
	end
	cyl(state, model, "shop_coin_emblem", 3.6, 0.9, at(F, 0, 20.4, -6.5, math.pi / 2), "LobbyGold") -- design: lobby.js:249
	-- shop_coin_ring TOR(2.6, 0.3) on the coin's face (lobby.js:249): a thin annulus of the inner coin colour.
	Props.annulus(
		model,
		"shop_coin_ring",
		4.6,
		5.8,
		at(F, 0, 20.4, -6.0, math.pi / 2),
		0.05,
		color(state, "LobbyCoinInner"),
		color(state, "LobbyGold")
	)
	rb(
		state,
		model,
		"display_case_base",
		Vector3.new(10.4, 0.6, 4.4),
		at(F, -5.4, 6.3, 1),
		"LobbyTrimWhite",
		"decor",
		6
	)
	Prims.part({
		name = "display_case_glass",
		size = Vector3.new(10, 3.6, 4), -- design: lobby.js:251 (opacity 0.26)
		cframe = at(F, -5.4, 8.4, 1),
		color = color(state, "LobbyGlass"),
		transparency = 0.74,
		shadow = false,
		flags = "decor",
		parent = model,
	})
	for i = 0, 2 do -- design: lobby.js:252
		cyl(state, model, "display_case_riser", 1.2, 0.3, at(F, -8.6 + i * 3.2, 6.75, 1), "LobbyLilac")
	end
	for i = 0, 5 do -- design: lobby.js:253
		cyl(state, model, "coin_stack", 0.9, 0.35, at(F, 7.6 + (i % 2) * 0.12, 6.1 + i * 0.36, 1.6), "LobbyGold")
	end
	cyl(state, model, "coin_single", 0.9, 0.35, at(F, 9.6, 6.1, 0.4, 0.3, 0, 0.2), "LobbyGold") -- design: lobby.js:254
	-- The preview turntable (lobby.js:255-257); its ring is lit butter (Purchasable, D7).
	local tt = stand.turntable
	cyl(state, model, "turntable_base", 3.3, 1.4, at(tt, 0, 0.7, 0), "LobbyTrimWhite", "solid")
	local ring = collar(state, model, "turntable_ring", 3.1, 0.3, 0.6, at(tt, 0, 1.4 - 0.3, 0), "LobbyButter")
	ring.Material = Enum.Material.Neon
	-- The design's toys (lobby.js:260): Toast, Banana and Chocolate in the case, Butter on the turntable.
	for i, toy in { { "toast", 1.5 }, { "banana", 1.2 }, { "chocolate", 1.6 } } :: { { any } } do
		local base = at(F, -8.6 + (i - 1) * 3.2, 6.9, 1, 0, 0.2)
		placeToy(state, "shop_toy_" .. toy[1], toy[1], base.Position, frontOf(base), toy[2], model)
	end
	local turn = at(tt, 0, 1.4, 0, 0, 0.4)
	placeToy(state, "turntable_toy", "butter", turn.Position, frontOf(turn), 2.4, model)
end

local function buildCollection(state: State)
	local L = state.L
	local stand = L.Collection
	local model = station(state, stand.model, true)
	local F = stationCF(state, "collection")
	rb(state, model, "collection_floor", stand.floor.size, L.boxCFrame(stand.floor), "LobbyCushionCream", "solid", 4) -- 266
	for _, bay in stand.bays do -- design: lobby.js:269-271
		rb(state, model, "bay_backboard", Vector3.new(5.6, 15, 1.2), at(bay, 0, 7.5, -1.6), "LobbyLilac", "solid", 4)
		rb(state, model, "bay_cap", Vector3.new(6.2, 1.2, 2.2), at(bay, 0, 15.2, -1.4), "LobbyViolet", "decor", 6)
		for _, y in { 4, 9.6 } do
			rb(state, model, "bay_shelf", Vector3.new(5.4, 0.6, 3.2), at(bay, 0, y, 0), "LobbyTrimWhite", "decor", 6)
		end
	end
	for k = 0, 7 do -- design: lobby.js:273
		local a = math.rad(-70 + k * 20)
		cyl(
			state,
			model,
			"bay_divider",
			0.5,
			15.6,
			at(F, math.sin(a) * 16.5, 8.6, 3 - math.cos(a) * 16.5),
			"LobbyTrimWhite"
		)
	end
	local defs = state.deps.Catalog.list()
	for _, pedestal in stand.pedestals do -- design: lobby.js:278-280 (D4: every squishy, catalog order)
		local part = Props.cylinder(
			model,
			"collection_pedestal",
			pedestal.size.X,
			pedestal.size.Y,
			CFrame.new(pedestal.position),
			color(state, "LobbyTrimWhite"),
			"solid"
		)
		Prims.tag(part, stand.pedestalTag, { [L.Attributes.Slot] = pedestal.slot })
		addPrompt(state, part, pedestal.prompt)
		-- collection_rarity_rim TOR(1.35, 0.18) (lobby.js:280): a collar flush with the pedestal top, in the game's
		-- rarity colour (D9).
		local def = defs[pedestal.slot]
		local rarity = if def then state.deps.RarityStyle.get(def.rarity) else nil
		local top = pedestal.position.Y + pedestal.size.Y / 2
		Props.cylinder(
			model,
			string.format("collection_rarity_rim_%02d", pedestal.slot),
			2 * (1.35 + 0.18),
			0.36,
			CFrame.new(pedestal.position.X, top - 0.18 - Prims.LAYER, pedestal.position.Z), -- the pedestal top wins
			if rarity then rarity.color else color(state, "LobbyTrimWhite")
		)
	end
	-- The inventory kiosk (lobby.js:274-276): the SD_CollectionKiosk.
	local ks = stand.kioskFrame
	local kiosk =
		rb(state, model, "kiosk_body", stand.kiosk.size, L.boxCFrame(stand.kiosk), stand.kiosk.color, "solid", 5)
	Prims.tag(kiosk, stand.kioskTag)
	addPrompt(state, kiosk, stand.prompt)
	rb(state, model, "kiosk_top", Vector3.new(4.2, 0.5, 3), at(ks, 0, 4.7, 0, -0.35), "LobbyTrimWhite", "decor", 6)
end

local function buildQuestBoard(state: State)
	local L = state.L
	local stand = L.QuestBoard
	local model = station(state, stand.model, true)
	local F = stationCF(state, "quests")
	rb(state, model, "quest_floor", stand.floor.size, L.boxCFrame(stand.floor), "LobbyCushionCream", "solid", 4) -- 289
	for _, e in { -1, 1 } do
		cyl(state, model, "quest_post", 0.8, 16, at(F, e * 10.4, 8.8, -1.6), "LobbyWafer", "solid") -- lobby.js:290
	end
	-- The cork (lobby.js:291) is the SD_QuestBoard.
	local board =
		rb(state, model, "quest_cork", stand.board.size, L.boxCFrame(stand.board), stand.board.color, "solid", 4)
	Prims.tag(board, stand.tag)
	addPrompt(state, board, stand.prompt)
	-- The capsule frame (lobby.js:292-294): rods whose ends hide in the corner knobs.
	for _, y in { 2.6, 15.4 } do
		cyl(state, model, "quest_frame", 0.75, 19.4, at(F, 0, y, -1.4, 0, 0, math.pi / 2), "LobbyStrawberry")
	end
	for _, e in { -1, 1 } do
		cyl(state, model, "quest_frame", 0.75, 12.8, at(F, e * 10, 9, -1.4), "LobbyStrawberry")
	end
	for _, corner in { { -10, 2.6 }, { 10, 2.6 }, { -10, 15.4 }, { 10, 15.4 } } do
		ball(state, model, "quest_frame_knob", 1.05, at(F, corner[1], corner[2], -1.4).Position, "LobbyTrimWhite")
	end
	rb(state, model, "quest_header", Vector3.new(10, 3, 1), at(F, 0, 17.4, -1.6), "LobbyButter", "decor", 5) -- 295
	for c = 0, 2 do -- design: lobby.js:297-306 (Available: cards in progress, no stamps)
		local x = -6 + c * 6
		for k = 0, 2 do
			local y = 11.1 - k * 3.2
			local tilt = QUEST_CARD_TILTS[c + 1][k + 1]
			rb(
				state,
				model,
				"quest_card",
				Vector3.new(5, 2.7, 0.24),
				at(F, x, y, -1.0, 0, 0, tilt),
				QUEST_CARD_TOKENS[c + 1],
				"decor",
				8
			)
			ball(state, model, "quest_pin", 0.32, at(F, x, y + 1.05, -0.8).Position, "LobbyStrawberryRed")
			Prims.part({
				name = "quest_bar_line",
				size = Vector3.new(3.8, 0.42, 0.1),
				cframe = at(F, x, y - 0.6, -0.84),
				color = color(state, "LobbySeam"),
				flags = "decor",
				parent = model,
			})
			local fill = QUEST_FILLS[k + 1]
			Prims.part({
				name = "quest_bar_fill_line",
				-- Prims.LAYER past the bar's left end: the two end faces met (flicker)
				size = Vector3.new(3.8 * fill + Prims.LAYER, 0.42 + 2 * Prims.LAYER, 0.12),
				cframe = at(F, x - 1.9 * (1 - fill) - Prims.LAYER / 2, y - 0.6, -0.8), -- 0.02 out: backs apart
				color = color(state, QUEST_BAR_TOKENS[c + 1]),
				flags = "decor",
				parent = model,
			})
		end
	end
end

local function buildDailyStand(state: State)
	local L = state.L
	local stand = L.DailyStand
	local model = station(state, stand.model, true)
	local F = stationCF(state, "daily")
	-- The dais (lobby.js:314) is the SD_DailyStand.
	local dais = stand.pedestal
	local pedestal =
		cyl(state, model, "daily_dais", dais.diameter / 2, dais.height, CFrame.new(dais.position), dais.color, "solid")
	Prims.tag(pedestal, stand.tag)
	addPrompt(state, pedestal, stand.prompt)
	collar(state, model, "daily_dais_trim", 7.4, 0.36, 0.72, at(F, 0, 1.2 - 0.36, 0), "LobbyGold") -- lobby.js:314
	-- The gift (lobby.js:315-319): "GiftBox", spinning and bobbing (D12); its lid stays shut (Ready).
	local g = stand.gift
	local gift = Prims.model("GiftBox", model, false, g)
	rb(state, gift, "gift_body", Vector3.new(6.6, 5, 6.6), at(g, 0, 2.5, 0), "LobbyMint", "decor", 6) -- lobby.js:316
	-- The ribbons stand Prims.LAYER proud of the body on every side (0.02 flickered).
	local ribbonHeight, ribbonLength = 5 + 2 * Prims.LAYER, 6.6 + 2 * Prims.LAYER
	for _, size in { Vector3.new(1.4, ribbonHeight, ribbonLength), Vector3.new(ribbonLength, ribbonHeight, 1.4) } do
		Prims.part({
			name = "gift_ribbon",
			size = size,
			cframe = at(g, 0, 2.5, 0),
			color = color(state, "LobbyButter"),
			flags = "decor",
			parent = gift,
		})
	end
	local lid = at(g, 0, 5, -3.3) -- gift_lid_hinge (lobby.js:317)
	rb(state, gift, "gift_lid", Vector3.new(7.2, 1.5, 7.2), at(lid, 0, 0.75, 3.3), "LobbyMint", "decor", 6) -- lobby.js:318
	Prims.part({
		name = "gift_lid_ribbon",
		size = Vector3.new(1.5, 1.5 + 2 * Prims.LAYER, 7.3),
		cframe = at(lid, 0, 0.75, 3.3),
		color = color(state, "LobbyButter"),
		flags = "decor",
		parent = gift,
	})
	for _, e in { -1, 1 } do -- design: lobby.js:319 (TOR(1.1, 0.42) loops; reading: ellipsoid lobes)
		Props.ellipsoid(
			gift,
			"gift_bow_loop",
			Vector3.new(3.04, 3.04, 0.84),
			at(lid, e * 1.2, 2.2, 3.3, 0, 0, e * 0.7),
			color(state, "LobbyButter")
		)
	end
	ball(state, gift, "gift_bow_knot", 0.6, at(lid, 0, 1.8, 3.3).Position, "LobbyButter")
	for _, part in gift:GetDescendants() do
		if part:IsA("BasePart") then
			Prims.cosmetic(part)
		end
	end
	markAmbient(state, gift, AMBIENT_SPIN_BOB)
	-- daily_ring TOR(5.6, 0.3) on the dais (lobby.js:320), lit butter (Ready, D7): a thin annulus.
	local ring = Props.annulus(
		model,
		"daily_ring",
		10.6,
		11.8,
		at(F, 0, 1.2 + 0.24, 0),
		0.24,
		color(state, "LobbyButter"),
		color(state, dais.color)
	)
	ring.Material = Enum.Material.Neon
	-- The 7-day calendar (lobby.js:322-328); days 1-3 carry their check (static art).
	for d = 0, 6 do
		local a = math.rad(-48 + d * 16)
		local x, z = math.sin(a) * 10, -math.cos(a) * 10 + 2
		rb(
			state,
			model,
			"calendar_tile",
			Vector3.new(2.6, 3.2, 0.6),
			at(F, x, 4.4, z, 0, -a),
			if d == 3 then "LobbyButter" else "LobbyCushionCream",
			"decor",
			6
		)
		cyl(state, model, "calendar_post", 0.3, 4, at(F, x, 2, z), "LobbyTrimWhite")
		if d < 3 then
			Props.checkIcon(
				state.template,
				model,
				at(F, x + math.sin(-a) * 0.5, 3.6, z + math.cos(-a) * 0.5, 0, -a),
				0.32,
				color(state, "LobbyMint")
			)
		end
	end
end

-- The statue's ambient sparkle (§7.7): one emitter on an Attachment of the plinth at WorldLayout's sparkle point.
-- Built-in texture and rates from Config.Vfx (one of the ≤ 3 ambient emitters, §7.7 budget); no light emission.
local function buildStatueSparkle(state: State, host: BasePart, point: Vector3)
	local vfx = state.deps.Config.Vfx
	local attachment = Instance.new("Attachment")
	attachment.Name = "Sparkle"
	attachment.CFrame = CFrame.new(host.CFrame:PointToObjectSpace(point))
	attachment.Parent = host
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "StatueSparkle"
	emitter.Texture = vfx.Textures.sparkles
	emitter.Rate = vfx.Effects.statueSparkleRate
	emitter.Lifetime = NumberRange.new(vfx.Effects.statueSparkleLifetime)
	emitter.Speed = NumberRange.new(SPARKLE.speedMin, SPARKLE.speedMax)
	emitter.Drag = SPARKLE.drag
	emitter.SpreadAngle = SPARKLE.spread
	emitter.Size = NumberSequence.new(SPARKLE.size)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(color(state, SPARKLE.token))
	emitter.LightEmission = 0 -- §7.1 pillar 5: nothing glows unless it is gameplay
	emitter.LockedToPart = false
	emitter.Enabled = true
	emitter.Parent = attachment
end

local function buildSqueezeZone(state: State)
	local L = state.L
	local zone = L.SqueezeZone
	local model = station(state, zone.model, true)
	local F = stationCF(state, "squeeze")
	cyl(
		state,
		model,
		"squeeze_floor",
		zone.floor.diameter / 2,
		zone.floor.height,
		CFrame.new(zone.floor.position),
		zone.floor.color,
		"solid"
	) -- 338
	collar(state, model, "squeeze_floor_rim", 22.6, 0.45, 0.9, at(F, 0, 0.6 - 0.45, 0), "LobbyTrimWhite") -- lobby.js:338
	local plinth = cyl(
		state,
		model,
		"statue_plinth",
		zone.plinth.diameter / 2,
		zone.plinth.height,
		CFrame.new(zone.plinth.position),
		zone.plinth.color,
		"solid"
	) -- 339
	collar(state, model, "statue_plinth_band", 6.4, 0.5, 1, at(F, 0, 2.2, 0), "LobbyStrawberry") -- design: lobby.js:339
	local statue = zone.statue
	local kitty = placeToy(state, "Statue", statue.blueprintId, statue.position, statue.facing, statue.height, model)
	markAmbient(state, kitty, AMBIENT_BREATHE)
	buildStatueSparkle(state, plinth, zone.sparkle)
	for _, mat in zone.mats do -- design: lobby.js:342-348 (Ready: the meters full)
		local foam = Props.cylinder(
			model,
			"foam_mat",
			zone.matDiameter,
			zone.matThickness,
			CFrame.new(mat.position),
			color(state, zone.matColor),
			"solid"
		)
		local attributes: { [string]: any } = { [L.Attributes.StationId] = mat.id, [L.Attributes.GripTier] = 1 }
		Prims.tag(foam, L.Tags.SqueezeStation, attributes)
		local mg = mat.frame -- foam_mat_<k> group (lobby.js:343)
		collar(state, model, "foam_mat_rim", 3.75, 0.42, 0.84, at(mg, 0, 0.7, 0), zone.matRimColor) -- lobby.js:344
		cyl(state, model, "foam_mat_center_paint", 2.1, 0.08, at(mg, 0, 1.46, 0), "LobbyCourtStrawberry") -- lobby.js:345
		cyl(state, model, "refill_post", 0.45, 5, at(mg, 0, 2.5, 5.2), "LobbyTrimWhite") -- design: lobby.js:346
		rb(state, model, "refill_meter", Vector3.new(1.3, 3.4, 0.8), at(mg, 0, 4, 5.2), "LobbyPlum", "decor", 5)
		Prims.part({
			name = "refill_fill",
			size = Vector3.new(0.8, 2.8, 0.3), -- design: lobby.js:347
			cframe = at(mg, 0, 4, 5.62),
			color = color(state, "LobbyMint"),
			flags = "decor",
			parent = model,
		})
	end
end

local function buildTarget(state: State, parent: Instance, target: any)
	local L = state.L
	local range = L.PracticeRange
	local base = Vector3.new(target.position.X, range.laneFloorTopY, target.position.Z)
	local pivot = Prims.facing(base, -range.throwDirection) -- the board faces the thrower (D3)
	local model = Prims.model("Target_" .. target.id, parent, false, pivot)
	Prims.tag(model, L.Tags.PracticeTarget, {
		[L.Attributes.TargetId] = target.id,
		[L.Attributes.Distance] = target.distance,
		[L.Attributes.Moving] = target.moving,
		[L.Attributes.RailLength] = target.railLength,
		[L.Attributes.Period] = target.period,
	})
	local h = range.boardHeight
	cyl(state, model, "target_base", 2.4, 0.7, at(pivot, 0, 0.35, 0), "LobbyPlum") -- design: lobby.js:407
	local poleTop = h - TARGET_POLE_OVERLAP
	cyl(state, model, "target_pole", 0.35, poleTop - 0.65, at(pivot, 0, (0.65 + poleTop) / 2, 0), "LobbyTrimWhite")
	-- The outer ring disc is "Body" (PracticeController squashes its mesh): a Cylinder SpecialMesh facing the thrower.
	local board = at(pivot, 0, h, 0, 0, math.pi / 2) -- the part's X axis along the board's normal
	Prims.meshPart(
		"Body",
		Enum.MeshType.Cylinder,
		Vector3.new(0.5, 6.2, 6.2),
		board,
		color(state, "LobbyTrimWhite"),
		"decor",
		model
	)
	for index, ring in TARGET_RINGS do
		Props.cylinder(
			model,
			"target_ring_disc",
			2 * ring.radius,
			0.5,
			at(pivot, 0, h, -index * TARGET_RING_STEP, math.pi / 2), -- toward the thrower (the pivot's -Z)
			color(state, ring.token)
		)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			Prims.cosmetic(part)
		end
	end
	if target.moving and target.railLength > 0 then
		Prims.part({
			name = "Rail_" .. target.id,
			size = Vector3.new(RAIL.width, RAIL.height, target.railLength),
			cframe = CFrame.new(base + Vector3.new(0, RAIL.height / 2, 0)),
			color = color(state, RAIL.token),
			flags = "decor",
			parent = parent,
		})
	end
end

local function buildPracticeRange(state: State)
	local L = state.L
	local range = L.PracticeRange
	local model = station(state, range.model, true)
	local F = stationCF(state, "practice")
	boxPart(state, "LaneFloor", range.laneFloor, model, "solid") -- design: lobby.js:402
	boxPart(state, "FiringLine", range.firingLine, model, "solid") -- design: lobby.js:403
	for _, x in { -10, 0, 10 } do -- design: lobby.js:404 (throw spots: flat rings 1.6-2.4)
		Props.annulus(
			model,
			"range_throw_spot_paint",
			3.2,
			4.8,
			at(F, x, 0.66, 12),
			0.06,
			color(state, "LobbyTrimWhite"),
			color(state, "LobbyCourtMint")
		)
	end
	Prims.tag(volumePart("ThrowBox", range.throwBox, model), range.zoneTag)
	local targets = Prims.folder("Targets", model)
	for _, target in range.targets do
		buildTarget(state, targets, target)
	end
	-- The pillow wall (lobby.js:412-413) holds the Backstop part (WorldLayout, the jelly ripple's box).
	for row = 0, 2 do
		for i = 0, 5 do
			local token = if (i + row) % 2 == 1 then "LobbyCushionCream" else "LobbyLilac"
			-- Rows overlap 0.2: every other row sits Prims.LAYER deeper, and the pillows reach 2 * Prims.LAYER past the
			-- Backstop's back and top, so no two faces meet (flicker). The fronts stay at the design's X 110.5.
			local back = 2 * Prims.LAYER
			rb(
				state,
				model,
				"backstop_pillow",
				Vector3.new(6.4, 3.2 + back, 3 + back),
				at(F, -16 + i * 6.4 + (row % 2) * 3.2 - 1.6, 1.6 + row * 3, -24 - back / 2 - (row % 2) * Prims.LAYER),
				token,
				"decor",
				3
			)
		end
	end
	for _, e in { -1, 1 } do
		rb(
			state,
			model,
			"backstop_frame",
			Vector3.new(2, 10.6, 3.4),
			at(F, e * 18.6, 5.3, -24),
			"LobbyStrawberry",
			"decor",
			5
		)
		Props.ropeLine(
			state.template,
			model,
			F,
			{ { e * 18, 10 }, { e * 18, -2 }, { e * 18, -14 } },
			3.2,
			color(state, "LobbyGold"),
			color(state, "LobbyVelvetRope")
		) -- 414
	end
	boxPart(state, "Backstop", range.backstop, model, "solid")
	local sb = range.boardFrame -- range_board (lobby.js:415-417)
	for _, e in { -1, 1 } do
		cyl(state, model, "range_board_post", 0.3, 6, at(sb, e * 3.2, 3, 0), "LobbyTrimWhite")
	end
	rb(state, model, "range_board_panel", Vector3.new(7.6, 4.2, 0.8), at(sb, 0, 6.6, 0), "LobbyPlum", "decor", 5)
end

-- Private: Grip pods and giant pads -----------------------------------------------------------------------------------

-- Whether the floor point (x, z) of pad space lies inside the pad's rounded footprint shrunk by `inset`.
local function insideFootprint(pad: any, x: number, z: number, inset: number): boolean
	local half = pad.footprint / 2 - inset
	local r = math.max(pad.cornerRadius - inset, 0)
	local dx, dz = math.abs(x) - (half - r), math.abs(z) - (half - r)
	if dx <= 0 or dz <= 0 then
		return math.abs(x) <= half and math.abs(z) <= half
	end
	return dx * dx + dz * dz <= r * r
end

-- GiantPad_<key>: Collision (the station) and Body (the design pad: base, quilted tiles, accents) (§17.6.1, D5).
-- `bottom`: the surface the pad stands on (the white base's top, or the royal upper dais).
local function buildGiantPad(state: State, pad: any, parent: Instance, bottomY: number)
	local L = state.L
	local look = pad.look
	local floor = CFrame.new(pad.center.X, 0, pad.center.Z)
	local model = Prims.model(pad.model, parent, true, floor)
	Prims.tag(model, L.Tags.GiantPad, { [L.Attributes.GripTier] = pad.tier, [L.Attributes.PadKey] = pad.key })
	local collision = Prims.part({
		name = "Collision",
		size = pad.collision.size,
		cframe = CFrame.new(pad.collision.position),
		flags = "solid",
		shadow = false,
		transparency = 1,
		parent = model,
	})
	Prims.tag(collision, L.Tags.SqueezeStation, {
		[L.Attributes.StationId] = pad.stationId,
		[L.Attributes.GripTier] = pad.tier,
	})

	local body = Prims.model("Body", model, false, floor)
	local bodyColor = color(state, look.body)
	local tileTop = pad.restTop - pad.tileSize.Y / 2 -- tile centres; their tops are the rest top
	local baseHeight = tileTop - bottomY
	local baseFrame = floor * CFrame.new(0, bottomY + baseHeight / 2, 0)
	local base: BasePart
	if pad.cornerRadius * 2 >= pad.footprint then -- round (the marshmallow, lobby.js:364)
		base = Props.cylinder(body, "Base", pad.footprint, baseHeight, baseFrame, bodyColor)
	else -- design: lobby.js:361, 384 (rb(…, 3) shells)
		base = rb(
			state,
			body,
			"Base",
			Vector3.new(pad.footprint, baseHeight, pad.footprint),
			baseFrame,
			look.body,
			"decor",
			3
		)
	end
	base.Transparency = look.transparency
	local frame = pad.frame -- the design's pad group
	if pad.key == "jelly" then
		-- jelly_core inside the translucent shell (lobby.js:360).
		rb(state, body, "jelly_core", Vector3.new(8.6, 3, 8.6), at(frame, 0, 2.6, 0), "LobbyJellyCore", "decor", 3)
	end
	local n = pad.tilesPerSide
	local middle = (n + 1) / 2
	local topColor = color(state, look.top)
	for row = 1, n do
		for column = 1, n do
			local x, z = (column - middle) * pad.tileSpacing, (row - middle) * pad.tileSpacing
			if not insideFootprint(pad, x, z, PAD_TILE_INSET) then
				continue
			end
			local tile = Prims.meshPart(
				string.format("Tile_%02d_%02d", row, column),
				Enum.MeshType.Sphere,
				pad.tileSize,
				floor * CFrame.new(x, tileTop, z),
				topColor,
				"decor",
				body
			)
			tile.Transparency = look.transparency
		end
	end
	-- Accents (SD_PadAccent): path A keeps them over its one-colour mesh (GiantPadController).
	local accents: { BasePart } = {}
	if pad.key == "jelly" then -- design: lobby.js:362 (two shines on the shell top)
		table.insert(
			accents,
			rb(
				state,
				body,
				"jelly_shine",
				Vector3.new(5.4, 0.3, 1.2),
				at(frame, -1.8, 5.4, 2.8),
				"LobbyTrimWhite",
				"decor",
				4
			)
		)
		table.insert(
			accents,
			rb(
				state,
				body,
				"jelly_shine",
				Vector3.new(1.2, 0.3, 3.4),
				at(frame, -4, 5.3, 0.6),
				"LobbyTrimWhite",
				"decor",
				4
			)
		)
	elseif pad.key == "marshmallow" then -- design: lobby.js:365 (the toasted top C(3.6, 3.6, 0.2) at 5.72)
		table.insert(
			accents,
			Props.ellipsoid(
				body,
				"mallow_toast_top",
				Vector3.new(7.2, 0.2, 7.2),
				at(frame, 0, 5.72, 0),
				color(state, "LobbyMallowCenter")
			)
		)
	elseif pad.key == "royal" then -- design: lobby.js:385-386 (gold piping and five tufts)
		for _, e in { -1, 1 } do
			table.insert(
				accents,
				rb(
					state,
					body,
					"royal_piping",
					Vector3.new(8.4, 0.4, 0.4),
					at(frame, 0, 1.4, e * 4.05),
					"LobbyGold",
					"decor",
					6
				)
			)
			table.insert(
				accents,
				rb(
					state,
					body,
					"royal_piping",
					Vector3.new(0.4, 0.4, 8.4),
					at(frame, e * 4.05, 1.4, 0),
					"LobbyGold",
					"decor",
					6
				)
			)
		end
		for _, tuft in { { 0, 0 }, { 2.2, 2.2 }, { -2.2, 2.2 }, { 2.2, -2.2 }, { -2.2, -2.2 } } do
			table.insert(
				accents,
				Props.ellipsoid(
					body,
					"royal_tuft",
					PAD_TUFT,
					at(frame, tuft[1], 2.75, tuft[2]),
					color(state, "LobbyGold")
				)
			)
		end
	end
	for _, accent in accents do
		accent:SetAttribute(ATTR_PAD_ACCENT, true)
	end
	for _, part in body:GetDescendants() do
		if part:IsA("BasePart") then
			Prims.cosmetic(part)
		end
	end
end

-- The pad's jelly gate (SD_GripGate): open and invisible as built (D5); WorldBinder closes it locally (§17.6).
local function buildGate(state: State, pad: any, parent: Instance)
	local L = state.L
	local gate = Prims.disc(
		"Gate_" .. pad.key,
		pad.gate.diameter,
		pad.gate.height,
		pad.gate.position,
		color(state, pad.gate.color),
		"decor",
		parent
	)
	gate.Transparency = pad.gate.transparency
	gate.CastShadow = false
	Prims.tag(gate, L.Tags.GripGate, { [L.Attributes.GripTier] = pad.tier })
end

-- The design's lock + rope (lobby.js:52-58, 65-70) as one SD_GripLock model pivoted on its pad (D5): shown as built,
-- WorldBinder hides it per viewer once the level is high enough.
local function buildLock(
	state: State,
	pad: any,
	parent: Instance,
	lockFrame: CFrame,
	k: number,
	ropeFrame: CFrame,
	rope: { { number } },
	ropeHeight: number
)
	local L = state.L
	local model = Prims.model("Lock_" .. pad.key, parent, false, pad.frame)
	Prims.tag(model, L.Tags.GripLock, { [L.Attributes.GripTier] = pad.tier })
	Props.lockIcon(state.template, model, lockFrame, k, color(state, "LobbyGold"), color(state, "LobbyInk"))
	Props.ropeLine(
		state.template,
		model,
		ropeFrame,
		rope,
		ropeHeight,
		color(state, "LobbyGold"),
		color(state, "LobbyVelvetRope")
	)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			Prims.cosmetic(part)
		end
	end
end

local function buildGripGym(state: State)
	local L = state.L
	local pod = L.Pods.gym
	local model = station(state, pod.model, false)
	local F = stationCF(state, "grip")
	rb(state, model, "grip_floor", pod.floor.size, L.boxCFrame(pod.floor), pod.floor.color, "solid", 4) -- lobby.js:357
	for i = 0, 4 do -- design: lobby.js:358
		Prims.part({
			name = "grip_floor_line",
			size = Vector3.new(42, 0.05, 0.5),
			cframe = at(F, 0, 0.82, -9 + i * 4.5),
			color = color(state, "LobbyTrimWhite"),
			flags = "decor",
			shadow = false,
			parent = model,
		})
	end
	for _, key in pod.padKeys do
		local pad = L.GiantPads[key]
		local frame = pad.frame -- jelly_pad / marshmallow_pad (lobby.js:359, 363)
		rb(
			state,
			model,
			if key == "jelly" then "jelly_base" else "mallow_base",
			Vector3.new(12, 1.4, 12),
			at(frame, 0, 0.7, 0),
			"LobbyTrimWhite",
			"solid",
			4
		) -- lobby.js:360, 364
		buildGiantPad(state, pad, model, frame.Position.Y + 1.4)
		local pips = if key == "jelly" then 3 else 5 -- design: lobby.js:366
		for i = 0, pips - 1 do
			ball(
				state,
				model,
				"level_pip",
				0.42,
				at(frame, -((pips - 1) * 1.1) / 2 + i * 1.1, 1.75, 5.3).Position,
				"LobbyButter"
			)
		end
		if key == "marshmallow" then
			-- mallow_toast_ring TOR(4.1, 0.55) at 5.55 (lobby.js:365); reading: a toasted band at the top edge.
			Props.cylinder(
				model,
				"mallow_toast_ring",
				10.4,
				0.6,
				at(frame, 0, 4.9, 0),
				color(state, "LobbyMallowToast")
			)
		end
		buildGate(state, pad, model)
		buildLock(state, pad, model, at(frame, 0, 9.5, 0), 1, frame, { { -6.5, 6.8 }, { 6.5, 6.8 } }, 3) -- lobby.js:372-373
	end
	-- The rank tower between the pads (lobby.js:368-371).
	local rk = at(F, 0, 0.8, -7)
	cyl(state, model, "rank_base", 0.8, 1, at(rk, 0, 0.5, 0), "LobbyPlum")
	for i, token in RANK_TOKENS do
		rb(state, model, "rank_tier", Vector3.new(3, 1.6, 1.2), at(rk, 0, 1.8 + (i - 1) * 1.8, 0), token, "decor", 6)
	end
	ball(state, model, "rank_finial", 1.1, at(rk, 0, 12.8, 0).Position, "LobbyGold")
end

local function buildRoyalPod(state: State)
	local L = state.L
	local pod = L.Pods.royal
	local model = station(state, pod.model, false)
	local F = stationCF(state, "royal")
	cyl(state, model, "royal_dais", 13, 1, at(F, 0, 0.5, 0), "LobbyPlum", "solid") -- design: lobby.js:381
	cyl(state, model, "royal_dais_upper", 9.8, 1, at(F, 0, 1.5, 0), "LobbyRoyalVelvet", "solid")
	collar(state, model, "royal_dais_trim", 12.7, 0.32, 0.64, at(F, 0, 1 - 0.32, 0), "LobbyGold") -- design: lobby.js:382
	collar(state, model, "royal_dais_trim", 9.6, 0.32, 0.64, at(F, 0, 2 - 0.32, 0), "LobbyGold")
	local pad = L.GiantPads.royal
	buildGiantPad(state, pad, model, 2) -- the cushion stands on the upper dais (lobby.js:383)
	local cg = pad.frame
	for _, c in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do -- design: lobby.js:387 (tassels hang from the corners)
		Props.cone(model, "royal_tassel", 0.5, 1.6, at(cg, c[1] * 4.2, 0.5, c[2] * 4.2), color(state, "LobbyGold"))
		ball(state, model, "royal_tassel_knot", 0.4, at(cg, c[1] * 4.2, 1.4, c[2] * 4.2).Position, "LobbyGold")
	end
	for _, c in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do -- design: lobby.js:388 (the canopy)
		cyl(state, model, "canopy_post", 0.55, 15, at(F, c[1] * 7.4, 9.5, c[2] * 7.4), "LobbyGold")
		rb(
			state,
			model,
			"canopy_curtain",
			Vector3.new(1.8, 12, 1.8),
			at(F, c[1] * 7.4, 10, c[2] * 7.4),
			"LobbyRoyalVelvet",
			"decor",
			3
		)
		rb(
			state,
			model,
			"canopy_curtain_tie",
			Vector3.new(2.4, 0.8, 2.4),
			at(F, c[1] * 7.4, 8, c[2] * 7.4),
			"LobbyGold",
			"decor",
			6
		)
	end
	-- canopy_dome: a half sphere r 11 squashed to 0.55 (lobby.js:389); reading: four stacked discs (no hemisphere).
	local domeHeight = 11 * 0.55
	for step = 0, 3 do
		local bottom = step * domeHeight / 4
		local radius = 11 * math.sqrt(1 - (bottom / domeHeight) ^ 2)
		cyl(
			state,
			model,
			"canopy_dome",
			radius,
			domeHeight / 4,
			at(F, 0, 17 + bottom + domeHeight / 8, 0),
			"LobbyLilac"
		)
	end
	collar(state, model, "canopy_dome_rim", 11, 0.5, 1, at(F, 0, 17, 0), "LobbyGold") -- design: lobby.js:390
	ball(state, model, "canopy_finial", 1.2, at(F, 0, 23.4, 0).Position, "LobbyGold") -- design: lobby.js:391
	Props.cone(model, "canopy_finial_tip", 0.6, 2.4, at(F, 0, 25.4, 0), color(state, "LobbyGold"))
	-- royal_ring TOR(9, 0.3) on the upper dais (lobby.js:393), unlit (Locked): a thin annulus.
	Props.annulus(
		model,
		"royal_ring",
		17.4,
		18.6,
		at(F, 0, 2 + 0.24, 0),
		0.24,
		color(state, "LobbyButter"),
		color(state, "LobbyRoyalVelvet")
	)
	buildGate(state, pad, model)
	buildLock(
		state,
		pad,
		model,
		at(F, 0, 10.5, 9),
		1.1,
		F,
		{ { -9, 11.2 }, { -4.5, 13 }, { 4.5, 13 }, { 9, 11.2 } },
		3.4
	) -- 394
end

-- Private: kit, decor, signs, volumes ---------------------------------------------------------------------------------

local function buildKit(state: State)
	local L = state.L
	local model = Prims.model("Kit", state.root, false)
	local box = L.Lobby.footprint
	local hx, hz = box.maxX, box.maxZ
	-- Perimeter walls (lobby.js:426-438): per side n = round(L / 16) modules, pillars at every boundary.
	local function side(x0: number, z0: number, x1: number, z1: number, nx: number, nz: number)
		local length = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
		local n = math.floor(length / 16 + 0.5)
		local ry = -math.atan2(z1 - z0, x1 - x0)
		for i = 0, n - 1 do
			local t = (i + 0.5) / n
			local x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
			local frame = CFrame.new(x, 0, z) * CFrame.Angles(0, ry, 0)
			rb(
				state,
				model,
				"kit_wall_module",
				Vector3.new(16, 10, 3),
				frame * CFrame.new(0, 5, 0),
				"LobbyCushionCream",
				"solid",
				4
			)
			rb(
				state,
				model,
				"kit_wall_cap",
				Vector3.new(16.4, 1.4, 3.8),
				frame * CFrame.new(0, 10.4, 0),
				"LobbyStrawberry",
				"decor",
				6
			)
			if i % 3 == 1 then -- design: lobby.js:431 (shelf modules)
				for _, y in { 3.4, 6.8 } do
					local shelf = CFrame.new(x + nx * 2.6, y, z + nz * 2.6) * CFrame.Angles(0, ry, 0)
					Prims.part({
						name = "kit_wall_shelf",
						size = Vector3.new(13, 0.6, 2.6),
						cframe = shelf,
						color = color(state, "LobbyTrimWhite"),
						flags = "decor",
						parent = model,
					})
					for k = 0, 4 do
						local o = -5 + k * 2.5
						local bx, bz = x + math.cos(ry) * o + nx * 2.6, z - math.sin(ry) * o + nz * 2.6
						local shape = (k + i) % 3
						local token = SHELF_BLOB_TOKENS[(k + i + (if y > 4 then 1 else 0)) % 4 + 1]
						if shape == 0 then
							ball(state, model, "kit_shelf_toy_blob", 0.9, Vector3.new(bx, y + 1.2, bz), token)
						elseif shape == 1 then
							rb(
								state,
								model,
								"kit_shelf_toy_blob",
								Vector3.new(1.8, 1.6, 1.6),
								CFrame.new(bx, y + 1.1, bz) * CFrame.Angles(0, ry + 0.3, 0),
								token,
								"decor",
								4
							)
						else -- GUM × 0.3 (reading: a whole pebble on the shelf, no hidden half)
							Props.ellipsoid(
								model,
								"kit_shelf_toy_blob",
								Vector3.new(1.86, 1.8, 1.86),
								CFrame.new(bx, y + 0.3 + 0.9, bz),
								color(state, token)
							)
						end
					end
				end
			end
			if i % 3 == 2 then -- design: lobby.js:432 (window modules: a sky disc in a white frame)
				local facing = CFrame.lookAt(Vector3.new(x, 5.8, z), Vector3.new(x + nx, 5.8, z + nz))
					* CFrame.Angles(-math.pi / 2, 0, 0)
				Props.cylinder(
					model,
					"kit_window_frame",
					2 * (3.5 + 0.45),
					0.2,
					facing * CFrame.new(0, 1.55, 0),
					color(state, "LobbyTrimWhite")
				)
				Props.cylinder(
					model,
					"kit_window_sky",
					6.8,
					0.3,
					facing * CFrame.new(0, 1.6 + Prims.LAYER, 0), -- its back face clears the frame's (flicker)
					color(state, "LobbyWindowSky")
				)
			end
		end
		for i = 0, n do -- design: lobby.js:434
			local t = i / n
			local x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
			cyl(state, model, "kit_wall_pillar", 2.1, 12.6, CFrame.new(x, 6.3, z), "LobbyLilac", "solid")
			Props.gumdrop(model, "kit_pillar_gumdrop", CFrame.new(x, 12.6, z), 0.6, color(state, "LobbyMint"))
		end
	end
	side(-hx, -hz, hx, -hz, 0, 1) -- design: lobby.js:436
	side(-hx, hz, hx, hz, 0, -1)
	side(-hx, -hz, -hx, hz, 1, 0)
	side(hx, -hz, hx, hz, -1, 0)
	-- Promenade hedges (lobby.js:441-443): gumdrops at radius 35.6 every 0.115 rad, none within 0.24 rad of a path.
	local pathAngles: { number } = {}
	for _, path in L.Paths do
		table.insert(pathAngles, math.atan2(path.to.Z, path.to.X))
	end
	local a, i = 0, 0
	while a < 2 * math.pi do
		local near = false
		for _, p in pathAngles do
			if math.abs(math.atan2(math.sin(a - p), math.cos(a - p))) < 0.24 then
				near = true
			end
		end
		if not near then
			local scale = 0.42 + (i % 3) * 0.05
			Props.gumdrop(
				model,
				"kit_gumdrop_hedge",
				CFrame.new(math.cos(a) * 35.6, 0, math.sin(a) * 35.6),
				scale,
				color(state, HEDGE_TOKENS[i % 4 + 1])
			)
		end
		a += 0.115
		i += 1
	end
	-- Trees, lamps and benches between the paths (lobby.js:445-467; positions reproduced, see TREES).
	for index, foot in TREES do
		Props.cottonTree(
			model,
			"kit_cotton_tree" .. index,
			foot,
			1.05,
			color(state, "LobbyCandyStick"),
			color(state, "LobbyCottonPink")
		)
	end
	for _, foot in LAMPS do -- design: lobby.js:458
		for k = 0, 6 do
			cyl(
				state,
				model,
				if k % 2 == 1 then "kit_candy_lamp_stripe" else "kit_candy_lamp_pole",
				0.55,
				2,
				CFrame.new(foot + Vector3.new(0, 1 + k * 2, 0)),
				if k % 2 == 1 then "LobbyStrawberryRed" else "LobbyTrimWhite"
			)
		end
		ball(state, model, "kit_candy_lamp_globe", 1.5, foot + Vector3.new(0, 15.5, 0), "LobbyLampGlow")
		cyl(state, model, "kit_candy_lamp_pole", 1.6, 0.8, CFrame.new(foot + Vector3.new(0, 14.2, 0)), "LobbyTrimWhite")
	end
	for _, bench in BENCHES do -- design: lobby.js:462
		local frame = CFrame.new(bench[1], 0, bench[2]) * CFrame.Angles(0, bench[3], 0)
		rb(
			state,
			model,
			"kit_wafer_bench",
			Vector3.new(9, 1.2, 3),
			frame * CFrame.new(0, 2.2, 0),
			"LobbyWafer",
			"decor",
			5
		)
		for _, e in { -1, 1 } do
			rb(
				state,
				model,
				"kit_wafer_bench_leg",
				Vector3.new(1, 1.8, 2.6),
				frame * CFrame.new(e * 3, 0.9, 0),
				"LobbyWaferGroove",
				"decor",
				5
			)
		end
	end
	-- The kit sample bay (lobby.js:469-474).
	local K = stationCF(state, "kit")
	rb(state, model, "kit_sample_plinth", Vector3.new(26, 0.8, 9), at(K, 0, 0.4, 2), "LobbyCushionCream", "solid", 4)
	rb(state, model, "kit_sample_wall", Vector3.new(6, 7, 2), at(K, -8, 4.3, 0), "LobbyCushionCream", "decor", 4)
	rb(state, model, "kit_sample_cap", Vector3.new(6.3, 1, 2.5), at(K, -8, 8.2, 0), "LobbyStrawberry", "decor", 6)
	Props.gumdrop(model, "kit_sample_gumdrop", at(K, 0, 0.8, 2), 0.55, color(state, "LobbyMint"))
	Props.gumdrop(model, "kit_sample_gumdrop", at(K, 3.4, 0.8, 3), 0.42, color(state, "LobbyStrawberry"))
	rb(state, model, "kit_sample_bench", Vector3.new(6, 1, 2.4), at(K, 9, 2, 2), "LobbyWafer", "decor", 5)
	for _, e in { -1, 1 } do
		rb(
			state,
			model,
			"kit_sample_bench_leg",
			Vector3.new(0.8, 1.6, 2),
			at(K, 9 + e * 2.4, 1.3, 2),
			"LobbyWaferGroove",
			"decor",
			5
		)
	end
end

local function buildDecor(state: State)
	local L = state.L
	local model = Prims.model("Decor", state.root, false)
	local lollipops = L.Props.lollipops
	for index, foot in lollipops.positions do -- design: lobby.js:468
		local swirl = lollipops.colors[index]
		local lollipop = Props.lollipop(model, "Lollipop" .. index, foot, lollipops.height, lollipops.radius, {
			stick = color(state, LOLLIPOP_STICK),
			a = color(state, swirl[1]),
			b = color(state, swirl[2]),
		})
		for _, part in lollipop:GetDescendants() do
			if part:IsA("BasePart") then
				Prims.cosmetic(part)
			end
		end
		-- §18.5.1 A8: the client spins it about its pivot (the stick's foot), so it streams as one piece.
		lollipop.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		markAmbient(state, lollipop, AMBIENT_SPIN)
	end
end

local function buildSigns(state: State)
	local L = state.L
	local maxSlots = state.deps.Config.Duel.Arena.MaxSlots
	for _, sign in L.Signs do
		local owner: Instance? = state.models[sign.owner]
		if owner == nil then
			error(string.format("[SD][LobbyBuilder] sign %s: no station model %q", sign.id, tostring(sign.owner)), 0)
		end
		local host: BasePart? = nil
		if sign.part then
			host = state.hosts[sign.owner .. "/" .. sign.part]
			if host == nil then
				error(
					string.format("[SD][LobbyBuilder] sign %s: no host part %s/%s", sign.id, sign.owner, sign.part),
					0
				)
			end
		end
		if sign.logo then
			local lineColors: { Color3 } = {}
			for _, line in sign.lines do
				table.insert(lineColors, color(state, line.color))
			end
			Signs.logo(state.deps.Strings, sign, {
				host = host :: BasePart,
				-- design: lobby.js:150-154 (the disc, the dashed ring, the inner disc, the stars)
				colors = {
					disc = color(state, "LobbyPlate"),
					ring = color(state, "LobbyMint"),
					inner = color(state, "LobbyPath"),
					star = color(state, "LobbyButter"),
				},
				lineColors = lineColors,
			})
			continue
		end
		local bakeArgs: { [string]: any } = { count = 0, max = maxSlots }
		if sign.tier ~= nil then
			local gripPad = state.deps.GripPads[sign.tier]
			bakeArgs.level = if gripPad then gripPad.level else nil
		end
		local plate: Signs.PlateStyle? = nil
		local style = sign.plate
		if style then
			plate = {
				background = if style.background then color(state, style.background) else nil,
				border = if style.border then color(state, style.border) else nil,
				round = style.round,
				text = color(state, style.color),
			}
		end
		Signs.build(state.deps.Strings, sign, {
			style = state.style,
			host = host,
			bakeArgs = bakeArgs,
			align = sign.align,
			parent = owner,
			plate = plate,
		})
	end
end

local function buildVolumes(state: State)
	local L = state.L
	local keepClear = Prims.folder("KeepClear", state.root)
	for _, volume in L.KeepClear do
		Prims.tag(volumePart(volume.name, volume, keepClear), L.Tags.KeepClear)
	end
	local audio = Prims.folder("AudioZones", state.root)
	for _, zone in L.AudioZones do
		local A = L.Attributes
		Prims.tag(volumePart(zone.name, zone, audio), L.Tags.AudioZone, {
			[A.ZoneId] = zone.zoneId,
			[A.Priority] = zone.priority,
			[A.MusicKey] = zone.musicKey,
			[A.AmbienceKey] = zone.ambienceKey,
			[A.MusicMul] = zone.musicMul,
		})
	end
end

-- Private: self-check -------------------------------------------------------------------------------------------------

local function everything(root: Instance): { Instance }
	local list = root:GetDescendants()
	table.insert(list, 1, root)
	return list
end

-- Exact tag counts, unique station ids, one moving target, disabled prompts, budgets (§7.7, §17.6).
local function selfCheck(state: State): ({ string }, number, number, number)
	local L = state.L
	local problems: { string } = {}
	local all = everything(state.root)
	local counts: { [string]: number } = {}
	local stationIds: { [string]: boolean } = {}
	local parts, guis, prompts, moving = 0, 0, 0, 0
	for _, instance in all do
		for _, tag in instance:GetTags() do
			counts[tag] = (counts[tag] or 0) + 1
		end
		if instance:IsA("BasePart") then
			parts += 1
		elseif instance:IsA("SurfaceGui") then
			guis += 1
		elseif instance:IsA("ProximityPrompt") then
			prompts += 1
			if instance.Enabled then
				table.insert(problems, instance:GetFullName() .. " is enabled (prompts start disabled, §7.6)")
			end
		end
		if instance:HasTag(L.Tags.SqueezeStation) then
			local id = instance:GetAttribute(L.Attributes.StationId)
			if type(id) ~= "string" or stationIds[id] then
				table.insert(problems, string.format("StationId %s is missing or repeated", tostring(id)))
			else
				stationIds[id] = true
			end
		end
		if instance:HasTag(L.Tags.PracticeTarget) and instance:GetAttribute(L.Attributes.Moving) == true then
			moving += 1
		end
		-- §18.1 #3: the client moves SD_Ambient decor locally, so none of it may collide, be queried or be touched.
		if instance:IsA("BasePart") and (instance.CanCollide or instance.CanQuery or instance.CanTouch) then
			local holder = instance:FindFirstAncestorWhichIsA("Model")
			while holder ~= nil and holder ~= state.root do
				if holder:HasTag(L.Tags.Ambient) then
					table.insert(
						problems,
						instance:GetFullName() .. " is SD_Ambient decor that collides, is queried or touched"
					)
					break
				end
				holder = holder:FindFirstAncestorWhichIsA("Model")
			end
		end
	end
	local tags = {}
	for tag in L.TagCounts do
		table.insert(tags, tag)
	end
	table.sort(tags)
	for _, tag in tags do
		local expected = L.TagCounts[tag]
		if (counts[tag] or 0) ~= expected then
			table.insert(problems, string.format("%s: %d tagged, expected %d", tag, counts[tag] or 0, expected))
		end
	end
	if moving ~= 1 then
		table.insert(problems, string.format("%d moving practice targets, expected 1", moving))
	end
	if parts > L.Budgets.lobbyParts then
		table.insert(problems, string.format("%d parts, budget %d", parts, L.Budgets.lobbyParts))
	end
	if guis > L.Budgets.lobbySurfaceGuis then
		table.insert(problems, string.format("%d SurfaceGuis, budget %d", guis, L.Budgets.lobbySurfaceGuis))
	end
	return problems, parts, guis, prompts
end

-- Station bodies, exempt from the keep-clear test as in Verify: every instance with a station tag (every
-- WorldLayout.TagCounts tag but SD_Boundary, SD_AudioZone and SD_Ambient, which is decor, not a station) and every
-- Model between it and the root.
local function stationHolders(state: State): { [Instance]: boolean }
	local L = state.L
	local holders: { [Instance]: boolean } = {}
	for _, instance in state.root:GetDescendants() do
		local isStation = false
		for _, tag in instance:GetTags() do
			if
				L.TagCounts[tag] ~= nil
				and tag ~= L.Tags.Boundary
				and tag ~= L.Tags.AudioZone
				and tag ~= L.Tags.Ambient
			then
				isStation = true
				break
			end
		end
		if isStation then
			holders[instance] = true
			local node: Instance? = instance.Parent
			while node ~= nil and node ~= state.root do
				if node:IsA("Model") then
					holders[node] = true
				end
				node = node.Parent
			end
		end
	end
	return holders
end

-- The nearest Model at or above `instance`, below `root`.
local function nearestModel(instance: Instance, root: Instance): Instance?
	local node: Instance? = instance
	while node ~= nil and node ~= root do
		if node:IsA("Model") then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- §7.7 props rule 5 on the unparented tree (spatial queries need the Workspace, so this is Verify's oriented-box test):
-- every collidable part, station bodies excepted, that reaches into a keep-clear volume. One warning per pair.
local function keepClearReport(state: State): { string }
	local L = state.L
	local holders = stationHolders(state)
	local volumes: { BasePart } = {}
	local solids: { BasePart } = {}
	for _, instance in state.root:GetDescendants() do
		if instance:IsA("BasePart") then
			if instance:HasTag(L.Tags.KeepClear) then
				table.insert(volumes, instance)
			elseif instance.CanCollide and not instance:HasTag(L.Tags.Boundary) then
				local model = nearestModel(instance, state.root)
				if not holders[instance] and not (model and holders[model]) then
					table.insert(solids, instance)
				end
			end
		end
	end
	local lines: { string } = {}
	for _, volume in volumes do
		for _, part in solids do
			if Verify.boxesOverlap(volume.CFrame, volume.Size, part.CFrame, part.Size) then
				table.insert(
					lines,
					string.format("keep-clear %s: collidable %s inside", volume.Name, part:GetFullName())
				)
			end
		end
	end
	return lines
end

-- Public --------------------------------------------------------------------------------------------------------------

-- Builds the new lobby tree, unparented and marked. Never changes the place. May throw on a broken WorldLayout entry
-- (Main reports it as "build threw"); the half-built tree is destroyed with ctx.scratch.
function LobbyBuilder.build(ctx: BuildContext): BuildResult
	local warnings: { string } = {}
	local root = Prims.model(ROOT_NAME, nil, false, CFrame.identity)
	local handedOver = false
	ctx.scratch:add(function()
		if not handedOver then
			root:Destroy()
		end
	end)

	local deps, depsError = loadDeps(ctx.Shared)
	if deps == nil then
		return failure(warnings, depsError or "could not load Shared modules")
	end
	local missing = missingKeys(deps)
	if #missing > 0 then
		return failure(warnings, "Strings has no text for: " .. table.concat(missing, ", "))
	end

	local library = ReplicatedStorage:FindFirstChild(SHAPE_LIBRARY_NAME)
	local roundedBox = if library then library:FindFirstChild(ROUNDED_BOX_NAME) else nil
	local palette = deps.Palette
	local state: State = {
		deps = deps,
		L = deps.WorldLayout,
		root = root,
		warnings = warnings,
		style = {
			panel = palette[SIGN_STYLE_TOKENS.panel],
			frame = palette[SIGN_STYLE_TOKENS.frame],
			text = palette[SIGN_STYLE_TOKENS.text],
			stroke = palette[SIGN_STYLE_TOKENS.stroke],
		},
		models = {},
		hosts = {},
		template = if roundedBox and roundedBox:IsA("BasePart") then roundedBox else nil,
		warnedTemplate = false,
	}

	buildGround(state)
	buildSpawn(state)
	buildDuelGate(state)
	buildGiftBoxCounter(state)
	buildShopCounter(state)
	buildCollection(state)
	buildQuestBoard(state)
	buildDailyStand(state)
	buildSqueezeZone(state)
	buildPracticeRange(state)
	buildGripGym(state)
	buildRoyalPod(state)
	buildKit(state)
	buildDecor(state)
	buildSigns(state) -- after every station model and host part exists
	buildVolumes(state)

	local problems, parts, guis, prompts = selfCheck(state)
	if #problems > 0 then
		return failure(
			warnings,
			string.format("lobby self-check found %d problem(s): %s", #problems, table.concat(problems, "; "))
		)
	end
	for _, line in keepClearReport(state) do
		table.insert(warnings, line)
	end
	table.insert(
		warnings,
		string.format(
			"lobby report: %d parts (budget %d), %d SurfaceGuis (budget %d), %d prompts (all disabled)",
			parts,
			state.L.Budgets.lobbyParts,
			guis,
			state.L.Budgets.lobbySurfaceGuis,
			prompts
		)
	)

	Generated.mark(root, GENERATOR_ID, VERSION)
	handedOver = true
	return { ok = true, root = root, warnings = warnings, error = nil }
end

return LobbyBuilder
