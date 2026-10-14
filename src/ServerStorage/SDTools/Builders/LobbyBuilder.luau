--!strict
-- LobbyBuilder: builds the lobby Workspace.SD_Lobby as Squish Island (lobby bases spec 2026-10-11 §2-§4, §7-§8; build
-- plan Phase 4): the island, Squish Square with the duel stage under the duel tower, the stations in the hub sectors
-- (the Claude Design hub's stations, design package sd/lobby.js, phase 3 decisions D1-D14, made compact), the garden,
-- the beach, the sky and the 10 bases (the Grip pods and giant pads went in build plan Phase 6). Server only, Edit
-- mode only (ServerStorage.SDTools); called by Main's pipeline (target "lobby"), never at runtime. Contract
-- (Generated.BuildContext / BuildResult): build(ctx) returns { ok, root, warnings, error } with the new tree
-- UNPARENTED and marked GeneratorId "lobby"; it never parents anything into the place. Relative requires, or modules
-- of the injected ctx.Shared clone (never an absolute require).
--
-- Data: what the game reads (stations, stands, prompts, pads, targets, signs, volumes, plots, the station frames, the
-- island's radii) comes from Shared World/WorldLayout; colours are Art/Palette tokens ("Lobby kit", "Squish Island");
-- text is Shared Strings (the design's plate words are world.* keys, D10; the bases' signs base.*); the queue board
-- uses Config.Duel.Arena.MaxSlots; the pedestal bands use
-- Art/RarityStyle (D9) in Catalog order (D4). The decor is built here, in each station's frame
-- (WorldLayout.stationFrame) or a plot's (WorldLayout.plotFrame), every design number with its
-- `-- design: lobby.js:<line>`, an island number with `-- spec §<n>`; "reading" marks a value neither gives, "NOT IN
-- DESIGN" a part the game needs. Kit/Props maps the design's primitives to parts.
--
-- Static default states (D14): each station is built as the design shows its first state (lobby.js:120-129, "set"):
-- the box Available (reveal ring lit), the shop Purchasable (turntable ring lit), the daily gift Ready (ring lit), the
-- queue empty (no lights: D2, presentation only), the squeeze meters full, the quest cards in progress. Every plot is
-- built open: grey, "Open plot",
-- no capsules (BaseService shows the owner's name, colour, capsules and statue at runtime). Neon only on the lit state
-- rings (D7) and the design's lit refill fills (lobby.js:347-350); no outlines (D8).
-- The lobby look upgrade (user OK 2026-10-14, numbers in Kit/WorldLook): FIX 1, the lamps SpawnLamp and ShopLamp
-- and the halos BoxSparkle, ShopSparkle, DailySparkle and a GateSparkle on each plot's NameSign (SD_Sparkle);
-- FIX 2, the finishes (WorldLook.finish) on the whole tree after the build. FIX 3 (round 1): the Donut Arch gates, the
-- tower pillars, the lollipops, the cupcake trees' cups and frosting and the Cloud Bunny clouds are clones of
-- ServerStorage.SD_MeshLibrary's MeshParts (the user's Blender import, WorldLook.MESHES) once it is marked approved
-- (WorldLook.MESH_APPROVED, after Roblox's check); until then, and for a set the library lacks, today's parts, with a
-- warning.
--
-- Tree (station models with a prompt are Atomic and < 64 studs, so a prompt and its SurfaceGui stream together, §7.7):
--   SD_Lobby (Model, ModelStreamingMode Default, marked SD_Generated / lobby / VERSION)
--     Island      the sea, the shallow water, the beach, the grass and its edge (spec §2, §8)
--     Boundaries  4 invisible walls at the sea's edge (SD_Boundary)
--     Hub         Squish Square: its floor, curb and paths (the sign owner of the painted "SQUISH SQUARE")
--     Spawn       the medallion on the stage centre, its rim, the logo plate, the hub SpawnLocation (SD_LobbySpawn),
--                 SpawnLamp under the tower deck
--     DuelGate    the duel stage, the queue podium (SD_QueuePodium + prompt), 10 queue pads, the queue board
--                 (SD_QueueBoard), ReturnPoint1/2 (SD_ReturnPoint, Slot)
--     DuelTower   the landmark (spec §2, §7): 4 pillars, the deck with the DUELS badge, the Dragon Spire
--     GiftBoxCounter dais, GiftBox (the mystery box, SD_Ambient breathe), reveal pedestal (SD_BoxStand, BoxId + prompt)
--                 with its ring, OddsBoard (Title + live Body), BoxSparkle over the box
--     ShopCounter  floor, back wall and shelves, counter (SD_ShopCounter + prompt), awning, display case, turntable,
--                  the design's toys, ShopLamp under the awning, ShopSparkle over the turntable's toy
--     Collection   floor, 7 bays on an arc, 14 pedestals (SD_CollectionPedestal, Slot + Inspect prompt; the squishies
--                  are client-built) with rarity bands, kiosk (SD_CollectionKiosk + prompt)
--     QuestBoard   floor, posts, cork (SD_QuestBoard + prompt), frame, header, 9 cards
--     DailyStand   dais (SD_DailyStand + prompt), GiftBox (SD_Ambient spinBob), ring, 7-day calendar, Status plate,
--                  DailySparkle over the gift
--     SqueezeZone  floor, plinth, Statue (Kitty Bread, SD_Ambient breathe) + StatueSparkle, 6 foam mats
--                  (SD_SqueezeStation, StationId, GripTier 1) with meters
--     PracticeRange LaneFloor, FiringLine, ThrowBox (SD_PracticeZone), Backstop (in the pillow wall, on its footing),
--                  Targets (3 dummies and the moving target, SD_PracticeTarget bullseye boards: TargetId, Distance,
--                  Moving, RailLength, Period; "Body" mesh), rope rails, board
--     HubDecor     the Butter Fountain, the chocolate bar benches, the pancake stack tables (spec §3, §7)
--     Garden       the 10 garden paths, Boba pearl bollards, Mochi Fox lanterns, cupcake trees, the Toast Stack Tower,
--                  the Banana Slide, the Frog Lily Pond and the lily pads on the sea (spec §7)
--     Sky          6 Cloud Bunny clouds (spec §7)
--     Decor        Lollipop1..4 (Atomic, SD_Ambient spin), in the garden
--     Bases        Base_01..Base_10 (SD_Base, Plot): plinth floor (studs, SD_BaseTint light) and rim (full), white
--                  fence with posts every 8 studs and caps (full), the Donut Arch gate (16 wide, icing full) with its
--                  name sign (live line Owner; GateSparkle over the arch), the back wall (44 × 9, cap full), the statue
--                  plinth, the 4 capsule pads
--                  (Slot), the plot's SpawnLocation (SD_BaseSpawn, Plot) and its props (spec §4, §7)
--     KeepClear / AudioZones (Folders) invisible volumes
-- Lobby background motion (§18.5.1 A8, D12): Decor/Lollipop1..4 "spin", DailyStand/GiftBox "spinBob",
-- GiftBoxCounter/GiftBox and SqueezeZone/Statue "breathe" (SD_Ambient + SD_AmbientKind); none of their parts
-- collides, is queried or is touched. Every ProximityPrompt is created DISABLED (WorldBinder enables a stand's prompt
-- only when its UI exists, §7.6) with SD_TextKey (and SD_AltTextKey). Signs: Kit/Signs (static lines SD_Sign +
-- SD_TextKey; baked/live lines without SD_TextKey); the design's plates have no wood frame (Kit/Signs plate).
-- Render rules (spec §7), applied to the whole tree at the end: nothing but a SpawnLocation is touched; parts under 2
-- studs cast no shadow; decor nobody walks on never collides (Kit/Prims "decor").
-- Self-check (§7.7, spec §7): exact tag counts (WorldLayout.TagCounts), unique StationIds, one moving target, every
-- prompt disabled, inert SD_Ambient decor, the SurfaceGui budget, one plot Model and one SpawnLocation per plot, the
-- render rules, nothing collidable standing on a path (the 10 path volumes: the paths stay 8 wide), and the part budget
-- per zone (WorldLayout.Budgets) with every plot's capsules at their worst case (Builders/CapsuleBuilder's templates);
-- any problem fails the build. The keep-clear test (oriented boxes, station models' own parts exempt as in Verify) and
-- a part-count report per zone come back as warnings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CapsuleBuilder = require(script.Parent.CapsuleBuilder)
local Generated = require(script.Parent.Parent.Generated)
local Prims = require(script.Parent.Parent.Kit.Prims)
local Props = require(script.Parent.Parent.Kit.Props)
local Signs = require(script.Parent.Parent.Kit.Signs)
local Verify = require(script.Parent.Parent.Verify)
local WorldLook = require(script.Parent.Parent.Kit.WorldLook)

local BARRIER_GROUP = "SD_Barrier" -- the invisible walls' collision group (see buildIsland)

-- Types

type BuildContext = Generated.BuildContext
type BuildResult = Generated.BuildResult

type Deps = {
	Strings: any,
	Palette: any,
	Config: any,
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
	meshes: { [string]: { [string]: MeshPart } | false }, -- FIX 3: each WorldLook.MESHES set's pieces, or false
}

-- A prop part: a primitive (`kind`), its name, size, CFrame in the prop's frame and Palette token.
type PropPart = { kind: "block" | "cyl" | "ball" | "egg", name: string, size: Vector3, cframe: CFrame, token: string }

-- Constants

local GENERATOR_ID = "lobby"
local VERSION = 6 -- 3: Phase 4, Squish Island; 4: Phase 6, no Grip pods, giant pads or Jelly gates; 5: look upgrade;
-- 6: the Blender mesh library, round 1 (falls back to parts)
local ROOT_NAME = "SD_Lobby"

local SHAPE_LIBRARY_NAME = "SD_ShapeLibrary"
local ROUNDED_BOX_NAME = "RoundedBox"

local ATTR_ALT_TEXT_KEY = "SD_AltTextKey" -- the toggled (Leave Queue) / relabelled (Shop Squishies) prompt text
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
-- The lollipops' stick and disk colour (design: lobby.js:468), their swirl colours in WorldLayout.Props.lollipops.
local LOLLIPOP_STICK = "LobbyTrimWhite"
-- Practice targets (D3): the design's bullseye boards (lobby.js:406-409) on the game's targets.
local TARGET_RINGS = { -- design: lobby.js:409 (the inner ring discs, outer to inner)
	{ radius = 2.4, token = "LobbyStrawberry" },
	{ radius = 1.7, token = "LobbyTrimWhite" },
	{ radius = 1, token = "LobbyStrawberryRed" },
}
local TARGET_RING_STEP = 0.12 -- design: lobby.js:409
local TARGET_POLE_OVERLAP = 0.45 -- design: lobby.js:407-408 (the pole's top, 7.15, is 0.45 under the board centre)
local RAIL = { width = 0.4, height = 0.07, token = "LobbyPlum" } -- NOT IN DESIGN: the moving target's rail (§5.11)
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

-- The duel tower (spec §2: 4 pillars 7 × 7 at (±14, ±14), deck at 36, a blocky Dragon on top, about 68 tall).
-- Reading: the pillars at (±12, ±12) so they stand on the stage and leave the 10 paths clear; mint on the west, strawberry
-- on the east like the queue pads; the Dragon Spire is the game's Dragon toy on a stepped spire.
local TOWER = {
	pillar = 7,
	pillarAt = 12,
	deckBottom = 35,
	deckTop = 38.5,
	deckSide = 31,
	dragonTall = 22, -- toyAt measure: its top reaches about 68
	bandY = { 8, 20, 30 },
}
local QUEUE_PAD_RING = 10 -- reading: the 10 queue pads (design: lobby.js:190-195) on a ring around the medallion

-- Spec §7 render rules.
local SMALL_PART = 2 -- parts under 2 studs cast no shadow
local WALKABLE_TOP = 0.5 -- a colliding part whose top is at or below this is floor (§7.7 rule 3; Verify's rule)

-- Zones of the part budget (spec §7): root children that are the garden, the beach and the sky; the plots' folder; the
-- hub is everything else.
local GARDEN_ZONE: { [string]: boolean } = { Island = true, Boundaries = true, Garden = true, Sky = true, Decor = true }
local BASES_FOLDER = "Bases"

-- Base layout (spec §4; plot-local, +Z toward the hub, the plinth's top Y 0). Readings where §4 gives no number.
local BASE_RIM_DROP = Prims.LAYER -- the full-colour rim's top lies this far under the floor's
local FENCE_POST = Vector3.new(0.8, 3, 0.8)
local FENCE_CAP = Vector3.new(1.1, 0.5, 1.1)
local FENCE_RAIL_Y = { 1.2, 2.4 }
local FENCE_RAIL = 0.35
local FENCE_SIDE_Z = { -18, -10, -2, 6, 14, 22 } -- posts every 8 studs (spec §4) along each side
local FENCE_FRONT_X = 15 -- a post between the gate and each front corner
local BACK_WALL = Vector3.new(44, 9, 1.6) -- spec §4
local GATE_PILLAR = Vector3.new(2, 7, 2) -- reading: dough pillars 2 wide, 7 tall
local DONUT_TUBE = 1.3 -- reading: the arch is half a donut, its tube this thick
local SPAWN_PAD = Vector3.new(4, 0.2, 4)
local STATUE_PLINTH = { diameter = 6, height = 1.2 }

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
	return {
		Strings = loaded.Strings,
		Palette = loaded.Palette,
		Config = loaded.Config,
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

-- FIX 1 (user OK 2026-10-14): an Attachment `name` of `host` at the world point `point`, world-upright (Top = up
-- even on a Cylinder host, whose X axis is up).
local function upright(name: string, host: BasePart, point: Vector3): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.CFrame = host.CFrame:ToObjectSpace(CFrame.new(point))
	attachment.Parent = host
	return attachment
end

-- A shadowless PointLight `name` (WorldLook.LAMPS[name]) at `point`.
local function lamp(state: State, name: string, host: BasePart, point: Vector3)
	local spec = WorldLook.LAMPS[name]
	local light = Instance.new("PointLight")
	light.Name = name
	light.Color = color(state, spec.token)
	light.Brightness = spec.brightness
	light.Range = spec.range
	light.Shadows = false -- Verify fails a shadowed light
	light.Parent = upright(name, host, point)
end

-- A twinkle halo `name` (WorldLook.HALO, `size` or the recipe's) at `point` over a static `host`, tagged
-- WorldLayout.Tags.Sparkle (AmbientController's ReducedMotion). LightEmission 0: additive blending washes out on the
-- cream lobby.
local function halo(state: State, name: string, host: BasePart, point: Vector3, size: number?)
	local recipe = WorldLook.HALO
	local peak = size or recipe.size
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Texture = state.deps.Config.Vfx.Textures.sparkles -- built-in rbxasset, no upload (AssetTable §14.3)
	emitter.Rate = recipe.rate
	emitter.Lifetime = NumberRange.new(recipe.lifetime)
	emitter.Speed = recipe.speed
	emitter.Drag = recipe.drag
	emitter.SpreadAngle = recipe.spread
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Size = NumberSequence.new({ -- held like the transparency, so it reads for most of its life
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.15, peak),
		NumberSequenceKeypoint.new(0.7, peak),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.2),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Color = ColorSequence.new(color(state, recipe.token))
	emitter.LightEmission = 0
	emitter.LockedToPart = false
	emitter.Parent = upright(name, host, point)
	Prims.tag(emitter, state.L.Tags.Sparkle)
end

-- FIX 3: each WorldLook.MESHES set's pieces from ServerStorage.SD_MeshLibrary (the user's Blender import, used only
-- once marked approved), or false: that set is built from today's parts, with a warning (as rb() warns for a missing
-- RoundedBox).
local function resolveMeshes(state: State)
	local library = ServerStorage:FindFirstChild(WorldLook.MESH_LIBRARY)
	if library == nil then
		table.insert(
			state.warnings,
			string.format(
				"ServerStorage.%s is missing (import the Blender meshes): today's shapes",
				WorldLook.MESH_LIBRARY
			)
		)
	elseif library:GetAttribute(WorldLook.MESH_APPROVED) ~= true then
		table.insert(
			state.warnings,
			string.format(
				"ServerStorage.%s waits for Roblox's check (%s is not true yet): today's shapes",
				WorldLook.MESH_LIBRARY,
				WorldLook.MESH_APPROVED
			)
		)
		library = nil
	end
	local sets: { string } = {}
	for set in WorldLook.MESHES do
		table.insert(sets, set)
	end
	table.sort(sets) -- deterministic warnings
	for _, set in sets do
		local templates = WorldLook.meshTemplates(library, WorldLook.MESHES[set])
		state.meshes[set] = templates or false
		if library and templates == nil then
			table.insert(
				state.warnings,
				string.format(
					"%s has no usable %s (missing piece or turned import): built from parts",
					WorldLook.MESH_LIBRARY,
					set
				)
			)
		end
	end
end

-- FIX 3: the set's library pieces in `frame`, each in its Palette token (`tokens` by piece name). Decor (the
-- Prims.roundedBox flags) unless `solid`.
local function placeMeshes(
	state: State,
	set: string,
	frame: CFrame,
	tokens: { [string]: string },
	parent: Instance,
	solid: boolean?
): { [string]: BasePart }
	local templates = state.meshes[set] :: { [string]: MeshPart }
	local made: { [string]: BasePart } = {}
	for _, piece in WorldLook.MESHES[set] do
		local part, failed = Prims.roundedBox(
			templates[piece.name],
			piece.name,
			piece.size,
			frame * CFrame.new(piece.center),
			color(state, tokens[piece.name]),
			parent
		)
		if failed then -- never grey boxes in place of a library piece
			error(string.format("[SD][LobbyBuilder] could not clone %s.%s", WorldLook.MESH_LIBRARY, piece.name), 0)
		end
		if piece.noShadow then
			part.CastShadow = false
		end
		if solid then
			part.CanCollide = true
			part.CanQuery = true
		end
		local boxed = pcall(function()
			(part :: MeshPart).CollisionFidelity = Enum.CollisionFidelity.Box -- a solid pillar collides as a block
		end)
		if solid and not boxed then -- PLAN §8: then the user sets Box once on the library's piece
			local fix = string.format(
				"could not set CollisionFidelity Box on %s: set it once on %s.%s",
				piece.name,
				WorldLook.MESH_LIBRARY,
				piece.name
			)
			if not table.find(state.warnings, fix) then
				table.insert(state.warnings, fix)
			end
		end
		made[piece.name] = part
	end
	return made
end

-- The world direction a design group's front (+Z) looks along.
local function frontOf(frame: CFrame): Vector3
	return frame:VectorToWorldSpace(Vector3.zAxis)
end

-- Private: the island and the square ---------------------------------------------------------------------------------

-- An upright disc `radius` wide whose top is `top` and whose bottom is `bottom`, centred on the floor point `centre`.
local function slab(
	state: State,
	parent: Instance,
	name: string,
	radius: number,
	bottom: number,
	top: number,
	centre: Vector3,
	token: string,
	flags: Prims.Flags?
): Part
	local height = top - bottom
	return cyl(state, parent, name, radius, height, CFrame.new(centre.X, bottom + height / 2, centre.Z), token, flags)
end

-- The sea, the shallow water, the beach and the grass (spec §2, §8): the sea is WorldLayout.Lobby.baseSlab; the round
-- layers stand on it, each top Prims.LAYER or more above the one under it. Then the boundaries at the sea's edge.
local function buildIsland(state: State)
	local L = state.L
	local I = L.Island
	local model = Prims.model("Island", state.root, false)
	local sea = boxPart(state, "sea", L.Lobby.baseSlab, model, "solid")
	local seaTop = sea.Position.Y + sea.Size.Y / 2
	local bottom = seaTop - 1 -- reading: every layer reaches 1 stud into the sea
	slab(state, model, "shallow_water", I.shallow.radius, bottom, I.shallow.top, Vector3.zero, I.shallow.color, "solid")
	slab(state, model, "beach", I.beach.radius, bottom, I.beach.top, Vector3.zero, I.beach.color, "solid")
	slab(
		state,
		model,
		"grass_edge",
		I.grassEdge.radius,
		bottom,
		I.grass.top - Prims.LAYER,
		Vector3.zero,
		I.grassEdge.color,
		"solid"
	)
	slab(state, model, "grass", I.grass.radius, bottom, I.grass.top, Vector3.zero, I.grass.color, "solid")
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
		-- Roblox ignores CanQuery = false on a colliding part: in the Default group these walls would catch the aim ray
		-- (user bug report 2026-10-11, "it goes all the way up"). The barrier group collides only with SD_Characters.
		local ok, err = pcall(function()
			part.CollisionGroup = BARRIER_GROUP
		end)
		if not ok then
			table.insert(state.warnings, string.format("could not set %s.CollisionGroup: %s", part.Name, tostring(err)))
		end
	end
end

-- Squish Square (spec §2): the raised floor, the white curb under its edge and the paths across it to the stage.
local function buildHub(state: State)
	local L = state.L
	local I = L.Island
	local model = station(state, "Hub", false)
	local hub = I.hub
	slab(state, model, "hub_floor", hub.radius, hub.top - hub.height, hub.top, Vector3.zero, hub.color, "solid")
	-- Prims.LAYER under the floor's top: the curb shows as a white band around the square and as its side.
	slab(
		state,
		model,
		"hub_curb",
		I.curb.radius,
		hub.top - hub.height,
		hub.top - Prims.LAYER,
		Vector3.zero,
		I.curb.color,
		"solid"
	)
	for _, path in L.Paths do
		local dir = (path.to - path.from).Unit
		local from, to = dir * I.paving.from, dir * I.paving.to
		Prims.part({
			name = "hub_path",
			size = Vector3.new((to - from).Magnitude, Prims.LAYER, path.width),
			cframe = CFrame.new((from + to) / 2 + Vector3.new(0, hub.top + Prims.LAYER / 2, 0))
				* CFrame.Angles(0, -math.atan2(dir.Z, dir.X), 0),
			color = color(state, I.paving.color),
			flags = "decor",
			shadow = false,
			parent = model,
		})
	end
end

-- The hub spawn (lobby.js:147-155): the medallion on the stage centre, its rim, the invisible SpawnLocation and the
-- logo's plate.
local function buildSpawn(state: State)
	local L = state.L
	local S = L.Spawn
	local model = station(state, S.model, true)
	local medallion = S.medallion
	local medallionPart = cyl(
		state,
		model,
		"spawn_medallion",
		medallion.diameter / 2,
		medallion.height,
		CFrame.new(medallion.position),
		medallion.color,
		"solid"
	) -- design: lobby.js:147
	-- FIX 1: 3 under the tower deck's underside (always in shade, seen from the hub), over the medallion.
	lamp(state, "SpawnLamp", medallionPart, at(stationCF(state, "duel"), 0, TOWER.deckBottom - 3, 0).Position)
	-- spawn_medallion_rim (lobby.js:148): a strawberry collar around the medallion, Prims.LAYER under its top.
	collar(
		state,
		model,
		"spawn_medallion_rim",
		medallion.diameter / 2,
		0.4,
		medallion.height,
		CFrame.new(medallion.position),
		"LobbyStrawberry"
	)
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
end

-- Private: stations ---------------------------------------------------------------------------------------------------

-- The duel stage (spec §2) with the design's queue (lobby.js:169-204): the stage, its podium and 10 queue pads, the
-- queue board and the return points. Atomic (it holds the prompt), so it stays under 64 studs.
local function buildDuelGate(state: State)
	local L = state.L
	local gate = L.DuelGate
	local model = station(state, gate.model, true)
	local F = stationCF(state, "duel")
	local stage = gate.stage
	cyl(state, model, "queue_stage", stage.diameter / 2, stage.height, CFrame.new(stage.position), stage.color, "solid")
	-- queue_stage_trim (lobby.js:172): a plum band around the stage, Prims.LAYER under its top.
	collar(
		state,
		model,
		"queue_stage_trim",
		stage.diameter / 2,
		0.4,
		stage.height,
		CFrame.new(stage.position),
		"LobbyPlum"
	)
	local podium = gate.podium
	local step = cyl(
		state,
		model,
		"queue_stage_step",
		podium.diameter / 2,
		podium.height,
		CFrame.new(podium.position),
		podium.color,
		"solid"
	) -- the design's step (lobby.js:173) as the podium (SD_QueuePodium)
	Prims.tag(step, gate.podiumTag)
	addPrompt(state, step, gate.prompt)
	collar(
		state,
		model,
		"queue_stage_step_trim",
		podium.diameter / 2,
		0.3,
		podium.height,
		CFrame.new(podium.position),
		"LobbyGold"
	)
	-- The 10 queue pads (lobby.js:190-195): mint on the west half, strawberry on the east, between the paths.
	for k = 0, 9 do
		local a = math.rad(18 + 36 * k)
		local x, z = QUEUE_PAD_RING * math.sin(a), -QUEUE_PAD_RING * math.cos(a)
		local mint = x < 0
		local top = gate.stageTop
		cyl(state, model, "queue_pad", 1.8, 0.5, at(F, x, top + 0.25, z), "LobbyTrimWhite", "solid")
		-- queue_pad_ring TOR(1.75, 0.28): a collar flush with the pad top (off: pebble, D2).
		collar(state, model, "queue_pad_ring", 1.75, 0.28, 0.56, at(F, x, top + 0.5 - 0.28, z), "LobbyPebble")
		cyl(
			state,
			model,
			"queue_pad_paint",
			0.9,
			0.08,
			at(F, x, top + 0.52, z),
			if mint then "LobbyCourtMint" else "LobbyCourtStrawberry"
		)
	end
	-- NOT IN DESIGN (D11): the live queue board (SD_QueueBoard) under the tower's crossbar.
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

-- The duel tower (spec §2, §7 "Dragon Spire"): the island's landmark over the stage. Decor above the stage's pillars:
-- only the pillars collide.
local function buildDuelTower(state: State)
	local L = state.L
	local model = station(state, "DuelTower", false)
	local F = stationCF(state, "duel")
	local top = L.DuelGate.stageTop
	local height = TOWER.deckBottom - top
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local team = if sx < 0 then "LobbyMint" else "LobbyStrawberry"
			local x, z = sx * TOWER.pillarAt, sz * TOWER.pillarAt
			if state.meshes.TowerPillar then -- FIX 3: the design's rounded pillar (rb n 4) as a Blender mesh, solid
				placeMeshes(state, "TowerPillar", at(F, x, top + height / 2, z), { tower_pillar = team }, model, true)
			else
				rb(
					state,
					model,
					"tower_pillar",
					Vector3.new(TOWER.pillar, height, TOWER.pillar),
					at(F, x, top + height / 2, z),
					team,
					"solid",
					4
				)
			end
			for _, y in TOWER.bandY do
				rb(
					state,
					model,
					"tower_pillar_band",
					Vector3.new(TOWER.pillar + 0.6, 1.4, TOWER.pillar + 0.6),
					at(F, x, y, z),
					"LobbyTrimWhite",
					"decor",
					5
				)
			end
		end
	end
	local deck = TOWER.deckTop - TOWER.deckBottom
	rb(
		state,
		model,
		"tower_deck",
		Vector3.new(TOWER.deckSide, deck, TOWER.deckSide),
		at(F, 0, TOWER.deckBottom + deck / 2, 0),
		"LobbyPlum",
		"decor",
		6
	)
	Prims.part({
		name = "tower_deck_trim",
		size = Vector3.new(TOWER.deckSide + 0.6, 0.6, TOWER.deckSide + 0.6),
		cframe = at(F, 0, TOWER.deckBottom + 0.3 - Prims.LAYER, 0), -- its top clears the deck's bottom face
		color = color(state, "LobbyGold"),
		flags = "decor",
		parent = model,
	})
	-- A low parapet on the deck's four edges (blocky, spec §1 #4).
	local edge = TOWER.deckSide / 2 - 0.6
	for _, side in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local alongX = side[1] == 0
		rb(
			state,
			model,
			"tower_parapet",
			if alongX then Vector3.new(TOWER.deckSide, 1.6, 1.2) else Vector3.new(1.2, 1.6, TOWER.deckSide - 2.4),
			at(F, side[1] * edge, TOWER.deckTop + 0.8, side[2] * edge),
			"LobbyButter",
			"decor",
			6
		)
	end
	-- The spire: two stepped blocks with gold trims, the Dragon on top.
	local spireTop = TOWER.deckTop
	for index, side in { 16, 11 } do
		rb(
			state,
			model,
			"tower_spire",
			Vector3.new(side, 3, side),
			at(F, 0, spireTop + 1.5, 0),
			if index == 1 then "LobbyLilac" else "LobbyViolet",
			"decor",
			6
		)
		Prims.part({
			name = "tower_spire_trim",
			size = Vector3.new(side + 0.4, 0.5, side + 0.4),
			cframe = at(F, 0, spireTop + 3 - 0.25 - Prims.LAYER, 0),
			color = color(state, "LobbyGold"),
			flags = "decor",
			parent = model,
		})
		spireTop += 3
	end
	-- The crossbar between the south pillars that carries the queue board.
	Prims.part({
		name = "tower_crossbar",
		size = Vector3.new(2 * TOWER.pillarAt - TOWER.pillar, 1.2, 1.2),
		cframe = at(F, 0, 15.6, TOWER.pillarAt),
		color = color(state, "LobbyGold"),
		flags = "decor",
		parent = model,
	})
	local base = at(F, 0, spireTop, 0)
	placeToy(state, "TowerDragon", "dragon", base.Position, frontOf(base), TOWER.dragonTall, model)
end

-- The squishy box (lobby.js:206-233), compact: the design's dais, mystery box (at WorldLayout's mysteryScale), reveal
-- pedestal and odds board.
local function buildGiftBoxCounter(state: State)
	local L = state.L
	local stand = L.GiftBoxCounter
	local model = station(state, stand.model, true)
	local F = stationCF(state, "box")
	local dais = stand.dais
	-- design: lobby.js:209
	local daisPart =
		cyl(state, model, "box_dais", dais.diameter / 2, dais.height, CFrame.new(dais.position), dais.color, "solid")
	collar(
		state,
		model,
		"box_dais_trim",
		dais.diameter / 2 - 0.3,
		0.45,
		0.9,
		at(F, 0, dais.height - 0.45, 0),
		"LobbyGold"
	)
	-- The mystery box (lobby.js:210-216) at scale S: "GiftBox", breathing (D12); its lid stays shut (Available). The
	-- ribbons keep the design's 0.03 margins (unscaled) so no two faces share a plane.
	local S = stand.mysteryScale
	local bx = stand.mysteryBox
	local box = Prims.model("GiftBox", model, false, bx)
	local body = Vector3.new(10, 8, 10) * S
	rb(state, box, "box_body", body, at(bx, 0, body.Y / 2, 0), "LobbyStrawberry", "decor", 6) -- lobby.js:211
	for _, size in
		{
			Vector3.new(2.2 * S, body.Y + 0.06, body.Z + 0.12),
			Vector3.new(body.X + 0.12, body.Y + 0.06, 2.2 * S),
		}
	do
		Prims.part({
			name = "box_ribbon",
			size = size,
			cframe = at(bx, 0, body.Y / 2, 0),
			color = color(state, "LobbyButter"),
			flags = "decor",
			parent = box,
		})
	end
	local lid = at(bx, 0, body.Y, -body.Z / 2) -- box_lid_hinge (lobby.js:212)
	local lidSize = Vector3.new(10.9, 2, 10.9) * S
	rb(state, box, "box_lid", lidSize, at(lid, 0, lidSize.Y / 2, body.Z / 2), "LobbyStrawberry", "decor", 6) -- lobby.js:213
	for _, size in
		{
			Vector3.new(2.3 * S, lidSize.Y + 0.06, lidSize.Z + 0.1),
			Vector3.new(lidSize.X + 0.1, lidSize.Y + 0.06, 2.3 * S),
		}
	do
		Prims.part({
			name = "box_lid_ribbon",
			size = size,
			cframe = at(lid, 0, lidSize.Y / 2, body.Z / 2),
			color = color(state, "LobbyButter"),
			flags = "decor",
			parent = box,
		})
	end
	for _, e in { -1, 1 } do -- design: lobby.js:214 (TOR(1.6, 0.6) loops; reading: ellipsoid lobes)
		Props.ellipsoid(
			box,
			"box_bow_loop",
			Vector3.new(4.4, 4.4, 1.2) * S,
			at(lid, e * 1.7 * S, 3.1 * S, body.Z / 2, 0, 0, e * 0.7),
			color(state, "LobbyButter")
		)
	end
	ball(state, box, "box_bow_knot", 0.9 * S, at(lid, 0, 2.6 * S, body.Z / 2).Position, "LobbyButter") -- lobby.js:215
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
	-- FIX 1: the halo on the dais (the box breathes), 1.5 over the bow's top (6.4 + 2.48 + 1.76 = 10.64 over bx).
	halo(state, "BoxSparkle", daisPart, at(bx, 0, 12.1, 0).Position)
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
	local top = standDisc.position.Y + standDisc.height / 2
	local ring = collar(
		state,
		model,
		"reveal_ring",
		2.8,
		0.3,
		0.6,
		CFrame.new(standDisc.position.X, top - 0.3, standDisc.position.Z),
		"LobbyMint"
	) -- lobby.js:219
	ring.Material = Enum.Material.Neon
	-- The odds board (lobby.js:221-228): two gold posts and the cream panel "OddsBoard" (BoxController's).
	local ob = stand.oddsFrame
	local postX = stand.oddsBoard.size.X / 2 - 0.4
	for _, e in { -1, 1 } do
		cyl(state, model, "odds_post", 0.3, 7, at(ob, e * postX, 3.5, 0), "LobbyGold") -- design: lobby.js:222
	end
	state.hosts[stand.model .. "/oddsBoard"] = boxPart(state, "OddsBoard", stand.oddsBoard, model, "decor")
end

-- The shop (lobby.js:235-261) as a compact stall: the design's floor, back wall, shelves of gift boxes, counter,
-- awning, coin emblem, display case of toys and preview turntable, at the stall's size.
local function buildShopCounter(state: State)
	local L = state.L
	local stand = L.ShopCounter
	local model = station(state, stand.model, true)
	local F = stationCF(state, "shop")
	rb(state, model, "shop_floor", stand.floor.size, L.boxCFrame(stand.floor), "LobbyCushionCream", "solid", 4) -- 238
	rb(state, model, "shop_backwall", Vector3.new(20, 13, 1.4), at(F, 0, 7.3, -6.8), "LobbyCourtStrawberry", "solid", 4)
	rb(state, model, "shop_backwall_cap", Vector3.new(20.6, 1, 2), at(F, 0, 14.3, -6.8), "LobbyStrawberry", "decor", 6)
	for _, y in { 6, 10 } do -- design: lobby.js:240
		rb(state, model, "shop_shelf", Vector3.new(18, 0.6, 2.2), at(F, 0, y, -5.6), "LobbyTrimWhite", "decor", 6)
	end
	for i = 0, 7 do -- design: lobby.js:242 (two rows of 4)
		local y, x = if i < 4 then 6.3 else 10.3, -6.75 + (i % 4) * 4.5
		rb(
			state,
			model,
			"shop_gift_box",
			Vector3.new(2.4, 2.2, 1.8),
			at(F, x, y + 1.1, -5.6),
			SHOP_GIFT_TOKENS[i % 5 + 1],
			"decor",
			6
		)
		Prims.part({
			name = "shop_gift_ribbon",
			size = Vector3.new(0.5, 2.26, 1.86),
			cframe = at(F, x, y + 1.1, -5.6),
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
	lamp(state, "ShopLamp", counter, at(F, 0, 11.5, 2).Position) -- FIX 1: under the awning (scallops 12.6)
	for i = -3, 3 do -- design: lobby.js:244
		rb(
			state,
			model,
			"shop_counter_groove",
			Vector3.new(0.45, 3.4, 0.4),
			at(F, i * 2, 3, 3.55),
			"LobbyWaferGroove",
			"decor",
			4
		)
	end
	rb(state, model, "shop_counter_top", Vector3.new(15, 0.8, 4.6), at(F, 0, 5.6, 1.5), "LobbyTrimWhite", "solid", 6) -- 245
	local awningEdge = 10.4
	for _, e in { -1, 1 } do
		cyl(state, model, "awning_post", 0.45, 13.4, at(F, e * awningEdge, 7.5, 5.2), "LobbyTrimWhite") -- lobby.js:246
	end
	for i = 0, 7 do -- design: lobby.js:247-248 (stripes edge to edge)
		local stripe = if i % 2 == 1 then "LobbyMint" else "LobbyTrimWhite"
		local x = -3.5 * 2.64 + i * 2.64
		Prims.part({
			name = "awning_stripe",
			size = Vector3.new(2.64, 0.5, 12),
			cframe = at(F, x, 14.4, -0.4, 0.28),
			color = color(state, stripe),
			flags = "decor",
			parent = model,
		})
		Props.ellipsoid(model, "awning_scallop", Vector3.new(2.6, 1.6, 0.5), at(F, x, 12.6, 5.6), color(state, stripe))
	end
	cyl(state, model, "shop_coin_emblem", 2.8, 0.9, at(F, 0, 17.6, -6.8, math.pi / 2), "LobbyGold") -- design: lobby.js:249
	-- shop_coin_ring TOR(2.6, 0.3) on the coin's face (lobby.js:249): a thin annulus of the inner coin colour.
	Props.annulus(
		model,
		"shop_coin_ring",
		3.6,
		4.5,
		at(F, 0, 17.6, -6.3, math.pi / 2),
		0.05,
		color(state, "LobbyCoinInner"),
		color(state, "LobbyGold")
	)
	-- The display case (lobby.js:250-254) on the counter's left end, the coins on its right.
	rb(state, model, "display_case_base", Vector3.new(6.4, 0.6, 3), at(F, -3.8, 6.3, 1.5), "LobbyTrimWhite", "decor", 6)
	Prims.part({
		name = "display_case_glass",
		size = Vector3.new(6, 3.2, 2.6), -- design: lobby.js:251 (opacity 0.26)
		cframe = at(F, -3.8, 8.2, 1.5),
		color = color(state, "LobbyGlass"),
		transparency = 0.74,
		shadow = false,
		flags = "decor",
		parent = model,
	})
	for i = 0, 1 do -- design: lobby.js:252
		cyl(state, model, "display_case_riser", 1.2, 0.3, at(F, -5.4 + i * 3.2, 6.75, 1.5), "LobbyLilac")
	end
	for i = 0, 4 do -- design: lobby.js:253
		cyl(state, model, "coin_stack", 0.9, 0.35, at(F, 4 + (i % 2) * 0.12, 6.2 + i * 0.36, 2), "LobbyGold")
	end
	cyl(state, model, "coin_single", 0.9, 0.35, at(F, 6, 6.2, 0.6, 0.3, 0, 0.2), "LobbyGold") -- design: lobby.js:254
	-- The preview turntable (lobby.js:255-257) on the square at the stall's front corner; its ring is lit butter
	-- (Purchasable, D7).
	local tt = stand.turntable
	local turntablePart = cyl(state, model, "turntable_base", 3.3, 1.4, at(tt, 0, 0.7, 0), "LobbyTrimWhite", "solid")
	local ring = collar(state, model, "turntable_ring", 3.1, 0.3, 0.6, at(tt, 0, 1.4 - 0.3, 0), "LobbyButter")
	ring.Material = Enum.Material.Neon
	-- FIX 1: the halo over the turntable's toy (Butter, at most 2.4 tall on the 1.4 turntable: top 3.8 at most).
	halo(state, "ShopSparkle", turntablePart, at(tt, 0, 5.3, 0).Position)
	-- The design's toys (lobby.js:260): Toast and Banana in the case, Butter on the turntable.
	for i, toy in { { "toast", 1.5 }, { "banana", 1.2 } } :: { { any } } do
		local base = at(F, -5.4 + (i - 1) * 3.2, 6.9, 1.5, 0, 0.2)
		placeToy(state, "shop_toy_" .. toy[1], toy[1], base.Position, frontOf(base), toy[2], model)
	end
	local turn = at(tt, 0, 1.4, 0, 0, 0.4)
	placeToy(state, "turntable_toy", "butter", turn.Position, frontOf(turn), 2.4, model)
end

-- The collection (lobby.js:263-284) as a compact stall: 7 bays on WorldLayout's arc, 14 pedestals, the kiosk.
local function buildCollection(state: State)
	local L = state.L
	local stand = L.Collection
	local model = station(state, stand.model, true)
	local F = stationCF(state, "collection")
	rb(state, model, "collection_floor", stand.floor.size, L.boxCFrame(stand.floor), "LobbyCushionCream", "solid", 4) -- 266
	local w = stand.bayWidth
	for _, bay in stand.bays do -- design: lobby.js:269-271
		rb(state, model, "bay_backboard", Vector3.new(w, 15, 1.2), at(bay, 0, 7.5, -1.6), "LobbyLilac", "solid", 4)
		rb(state, model, "bay_cap", Vector3.new(w + 0.6, 1.2, 2.2), at(bay, 0, 15.2, -1.4), "LobbyViolet", "decor", 6)
		for _, y in { 4, 9.6 } do
			rb(
				state,
				model,
				"bay_shelf",
				Vector3.new(w - 0.2, 0.6, 3.2),
				at(bay, 0, y, 0),
				"LobbyTrimWhite",
				"decor",
				6
			)
		end
	end
	local dividerRadius = stand.bayRadius + 1.5 -- design: lobby.js:273 (between the backboards)
	for k = 0, 7 do -- design: lobby.js:273
		local a = math.rad(-70 + k * 20)
		cyl(
			state,
			model,
			"bay_divider",
			0.5,
			16.4, -- from the square, so the end ones past the floor's corners still stand on something
			at(F, math.sin(a) * dividerRadius, 8.2, stand.bayCenterZ - math.cos(a) * dividerRadius),
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
	-- The inventory kiosk (lobby.js:274-276): the SD_CollectionKiosk, on the square in front of the shelves.
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
	-- FIX 1: the halo on the dais (the gift spins and bobs), 1.5 over the bow's top (5 + 2.2 + 1.52 = 8.72 over g).
	halo(state, "DailySparkle", pedestal, at(g, 0, 10.3, 0).Position)
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
-- Built-in texture and rates from Config.Vfx (one of the lobby's 14 emitters, Verify); no light emission.
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
	collar(
		state,
		model,
		"squeeze_floor_rim",
		zone.floor.diameter / 2 - 0.4,
		0.45,
		0.9,
		at(F, 0, 0.6 - 0.45, 0),
		"LobbyTrimWhite"
	) -- lobby.js:338
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
			material = Enum.Material.Neon, -- design: lobby.js:347-350 (glow, the Ready meter always lit)
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

-- The practice range (lobby.js:399-421; D3; spec §3): one lane east along its sector's middle (WorldLayout), the
-- design's throw spot, bullseye targets, pillow wall around the Backstop, rope rails and board.
local function buildPracticeRange(state: State)
	local L = state.L
	local range = L.PracticeRange
	local model = station(state, range.model, true)
	local F = stationCF(state, "practice")
	boxPart(state, "LaneFloor", range.laneFloor, model, "solid") -- design: lobby.js:402
	boxPart(state, "FiringLine", range.firingLine, model, "solid") -- design: lobby.js:403
	-- The throw spot (lobby.js:404: a flat ring 1.6-2.4) at the approach, on the lane.
	local spot = range.approach
	Props.annulus(
		model,
		"range_throw_spot_paint",
		3.2,
		4.8,
		CFrame.new(spot.X, range.laneFloorTopY + 0.06, spot.Z),
		0.06,
		color(state, "LobbyTrimWhite"),
		color(state, "LobbyCourtMint")
	)
	Prims.tag(volumePart("ThrowBox", range.throwBox, model), range.zoneTag)
	local targets = Prims.folder("Targets", model)
	for _, target in range.targets do
		buildTarget(state, targets, target)
	end
	-- The pillow wall (lobby.js:412-413) holds the Backstop part (WorldLayout, the jelly ripple's box). Its fronts stand
	-- 0.5 in front of the Backstop's (station-local z, the frame's -Z is the throws' direction).
	local front = F:PointToObjectSpace(range.backstop.position).Z + range.backstop.size.X / 2 + 0.5
	for row = 0, 2 do
		for i = 0, 5 do
			local token = if (i + row) % 2 == 1 then "LobbyCushionCream" else "LobbyLilac"
			-- Rows overlap 0.2: every other row sits Prims.LAYER deeper, and the pillows reach 2 * Prims.LAYER past the
			-- Backstop's back and top, so no two faces meet (flicker).
			local back = 2 * Prims.LAYER
			rb(
				state,
				model,
				"backstop_pillow",
				Vector3.new(6.4, 3.2 + back, 3 + back),
				at(
					F,
					-16 + i * 6.4 + (row % 2) * 3.2 - 1.6,
					1.6 + row * 3,
					front - 1.5 - back / 2 - (row % 2) * Prims.LAYER
				),
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
			at(F, e * 18.6, 5.3, front - 1.5),
			"LobbyStrawberry",
			"decor",
			5
		)
		-- Rope rails along the lane (lobby.js:414), on its floor 0.6 inside its edges.
		local edge = range.laneFloor.size.Z / 2 - 0.6
		Props.ropeLine(
			state.template,
			model,
			F * CFrame.new(0, range.laneFloorTopY, 0),
			{ { e * edge, 14 }, { e * edge, -2 }, { e * edge, -18 } },
			3.2,
			color(state, "LobbyGold"),
			color(state, "LobbyVelvetRope")
		)
	end
	boxPart(state, "Backstop", range.backstop, model, "solid")
	-- Reading (island): the lane is 20 wide and the design's pillow wall 42, so a footing under the wall and its frames
	-- (42 × 4, from the garden up to Prims.LAYER under the lane's top) carries its ends past the lane's edges.
	local footingTop = range.laneFloorTopY - Prims.LAYER
	local grass = L.Island.grass.top
	Prims.part({
		name = "backstop_footing",
		size = Vector3.new(4, footingTop - grass, 42),
		cframe = CFrame.new(range.backstop.position.X - 0.25, (footingTop + grass) / 2, range.backstop.position.Z),
		color = color(state, range.laneFloor.color),
		flags = "solid",
		parent = model,
	})
	local sb = range.boardFrame -- range_board (lobby.js:415-417)
	for _, e in { -1, 1 } do
		cyl(state, model, "range_board_post", 0.3, 6, at(sb, e * 3.2, 3, 0), "LobbyTrimWhite")
	end
	rb(state, model, "range_board_panel", Vector3.new(7.6, 4.2, 0.8), at(sb, 0, 6.6, 0), "LobbyPlum", "decor", 5)
end

-- Private: props, the garden, the sky and the bases (spec §4, §7) ------------------------------------------------------

-- A prop part (PropPart) list placed in `frame` as a Model `name` under `parent`: blocks, upright cylinders (size.X the
-- diameter, size.Y the height), balls (size.X) and ellipsoids. Decor unless the part says solid.
local function prop(
	state: State,
	parent: Instance,
	name: string,
	frame: CFrame,
	parts: { PropPart },
	solid: { [string]: boolean }?
): Model
	local model = Prims.model(name, parent, false, frame)
	for _, p in parts do
		local cf = frame * p.cframe
		local c = color(state, p.token)
		local flags: Prims.Flags = if solid and solid[p.name] then "solid" else "decor"
		if p.kind == "block" then
			Prims.part({ name = p.name, size = p.size, cframe = cf, color = c, flags = flags, parent = model })
		elseif p.kind == "cyl" then
			Props.cylinder(model, p.name, p.size.X, p.size.Y, cf, c, flags)
		elseif p.kind == "ball" then
			Props.ball(model, p.name, p.size.X, cf.Position, c, flags)
		else
			Props.ellipsoid(model, p.name, p.size, cf, c, flags)
		end
	end
	return model
end

local function p(
	kind: "block" | "cyl" | "ball" | "egg",
	name: string,
	size: Vector3,
	cframe: CFrame,
	token: string
): PropPart
	return { kind = kind, name = name, size = size, cframe = cframe, token = token }
end

local V, C = Vector3.new, CFrame.new

-- Spec §7 props, readings of their shapes (the spec names each prop and its part count only). Each stands on its
-- frame's origin (the ground), its front along the frame's +Z.
local FOUNTAIN: { PropPart } = { -- Butter Fountain (hub 342°)
	p("cyl", "fountain_basin", V(12, 1.2, 0), C(0, 0.6, 0), "LobbyTrimWhite"),
	p("cyl", "fountain_water", V(11, 0.05, 0), C(0, 1.225, 0), "IslandShallow"),
	p("cyl", "fountain_column", V(1.6, 3, 0), C(0, 2.7, 0), "LobbyTrimWhite"),
	p("cyl", "fountain_bowl", V(5, 0.5, 0), C(0, 4.45, 0), "LobbyTrimWhite"),
	p("cyl", "fountain_bowl_water", V(4.4, 0.05, 0), C(0, 4.725, 0), "IslandShallow"),
	p("block", "fountain_butter", V(2.2, 1, 1.6), C(0, 5.25, 0), "LobbyButter"),
	p("ball", "fountain_drip", V(0.5, 0, 0), C(2.3, 4.5, 0), "LobbyButter"),
	p("ball", "fountain_drip", V(0.5, 0, 0), C(-1.2, 4.5, 2), "LobbyButter"),
	p("ball", "fountain_drip", V(0.5, 0, 0), C(-1.2, 4.5, -2), "LobbyButter"),
}
local BENCH: { PropPart } = { -- Chocolate bar bench (hub ×6)
	p("block", "bench_seat", V(6, 0.8, 2), C(0, 1.6, 0), "Cocoa"),
	p("block", "bench_groove", V(0.15, 0.86, 2.06), C(-1.5, 1.6, 0), "ArenaTrunk"),
	p("block", "bench_groove", V(0.15, 0.86, 2.06), C(1.5, 1.6, 0), "ArenaTrunk"),
	p("block", "bench_leg", V(0.8, 1.2, 1.6), C(-2.4, 0.6, 0), "Cocoa"),
	p("block", "bench_leg", V(0.8, 1.2, 1.6), C(2.4, 0.6, 0), "Cocoa"),
	p("block", "bench_back", V(6, 2, 0.5), C(0, 3, -0.75), "Cocoa"),
}
local TABLE: { PropPart } = { -- Pancake Stack table (hub ×4)
	p("cyl", "table_leg", V(0.8, 1.6, 0), C(0, 0.8, 0), "LobbyWaferGroove"),
	p("cyl", "table_pancake", V(4.4, 0.5, 0), C(0, 1.85, 0), "LobbyWafer"),
	p("cyl", "table_pancake", V(4.4, 0.5, 0), C(0, 2.35, 0), "LobbyMallowToast"),
	p("cyl", "table_pancake", V(4.4, 0.5, 0), C(0, 2.85, 0), "LobbyWafer"),
	p("cyl", "table_syrup", V(3.4, 0.1, 0), C(0, 3.15, 0), "LobbyWaferGroove"),
	p("block", "table_butter", V(1.2, 0.5, 1.2), C(0, 3.45, 0), "LobbyButter"),
}
local LANTERN: { PropPart } = { -- Mochi Fox lantern (the 10 path mouths)
	p("cyl", "lantern_post", V(0.5, 5, 0), C(0, 2.5, 0), "LobbyTrimWhite"),
	p("ball", "lantern_fox", V(2.2, 0, 0), C(0, 5.8, 0), "LobbyRangeArrow"),
	p("egg", "lantern_ear", V(0.6, 1, 0.4), C(-0.6, 6.9, 0), "LobbyRangeArrow"),
	p("egg", "lantern_ear", V(0.6, 1, 0.4), C(0.6, 6.9, 0), "LobbyRangeArrow"),
	p("ball", "lantern_snout", V(0.9, 0, 0), C(0, 5.6, 1), "LobbyCushionCream"),
}
local BOLLARD: { PropPart } = { -- Boba pearl bollard (×4 along each path)
	p("cyl", "bollard_post", V(0.6, 1.4, 0), C(0, 0.7, 0), "LobbyCushionCream"),
	p("ball", "bollard_pearl", V(1.2, 0, 0), C(0, 1.8, 0), "ArenaInk"),
}
local FROSTING = { "LobbyCottonPink", "LobbyMint", "LobbyButter" }
local function cupcakeTree(index: number): { PropPart } -- Cupcake tree (garden, gaps between bases, beach)
	return {
		p("cyl", "tree_trunk", V(0.9, 4, 0), C(0, 2, 0), "HubWood"),
		p("cyl", "tree_cup", V(4, 1.8, 0), C(0, 4.9, 0), "LobbyWafer"),
		p("egg", "tree_frosting", V(4.6, 2.8, 4.6), C(0, 6.6, 0), FROSTING[index % #FROSTING + 1]),
		p("ball", "tree_cherry", V(0.9, 0, 0), C(0, 8.3, 0), "LobbyStrawberryRed"),
	}
end
local TOAST_TOWER: { PropPart } = { -- Toast Stack Tower (garden 18°)
	p("block", "toast_slice", V(5.6, 1.1, 5.6), C(0, 0.55, 0), "LobbyWafer"),
	p("block", "toast_slice", V(5.6, 1.1, 5.6), C(0, 1.7, 0) * CFrame.Angles(0, 0.35, 0), "LobbyMallowToast"),
	p("block", "toast_slice", V(5.6, 1.1, 5.6), C(0, 2.85, 0) * CFrame.Angles(0, 0.7, 0), "LobbyWafer"),
	p("block", "toast_slice", V(5.6, 1.1, 5.6), C(0, 4, 0) * CFrame.Angles(0, 1.05, 0), "LobbyMallowToast"),
	p("block", "toast_slice", V(5.6, 1.1, 5.6), C(0, 5.15, 0) * CFrame.Angles(0, 1.4, 0), "LobbyWafer"),
	p("block", "toast_butter", V(2.4, 0.7, 2.4), C(0, 6.05, 0) * CFrame.Angles(0, 0.6, 0), "LobbyButter"),
}
local SLIDE_TOP = 6 -- the Banana Slide's platform height
local SLIDE: { PropPart } = { -- Banana Slide (garden; reading: 162°, the range has 90°)
	p("block", "slide_platform", V(3, 0.5, 3), C(7.5, SLIDE_TOP, 0), "LobbyWaferGroove"),
	p("block", "slide_leg", V(0.5, SLIDE_TOP, 0.5), C(8.75, SLIDE_TOP / 2, -1.25), "LobbyWaferGroove"),
	p("block", "slide_leg", V(0.5, SLIDE_TOP, 0.5), C(8.75, SLIDE_TOP / 2, 1.25), "LobbyWaferGroove"),
	p("block", "slide_rung", V(0.3, 0.3, 2.5), C(8.75, 1.5, 0), "LobbyWaferGroove"),
	p("block", "slide_rung", V(0.3, 0.3, 2.5), C(8.75, 3, 0), "LobbyWaferGroove"),
	p("block", "slide_rung", V(0.3, 0.3, 2.5), C(8.75, 4.5, 0), "LobbyWaferGroove"),
	p("ball", "slide_tip", V(1.4, 0, 0), C(-0.3, 0.6, 0), "LobbyWaferGroove"),
}
local CLOUD: { PropPart } = { -- Cloud Bunny cloud (sky ×6)
	p("ball", "cloud_puff", V(7, 0, 0), C(-5, 0, 0), "White"),
	p("ball", "cloud_puff", V(9, 0, 0), C(0, 1, 0), "White"),
	p("ball", "cloud_puff", V(7, 0, 0), C(5, 0, 0), "White"),
	p("egg", "cloud_ear", V(1.4, 4.5, 1), C(-1.6, 6.5, 0), "White"),
	p("egg", "cloud_ear", V(1.4, 4.5, 1), C(1.6, 6.5, 0), "White"),
}
-- Base props (spec §4: the Kitty Loaf mailbox, the Toast bench, the Chocolate flower box, the Birdie nest planter).
local MAILBOX: { PropPart } = {
	p("block", "mailbox_post", V(0.5, 3, 0.5), C(0, 1.5, 0), "LobbyTrimWhite"),
	p("block", "mailbox_loaf", V(2.2, 1.6, 1.4), C(0, 3.8, 0), "LobbyWafer"),
	p("egg", "mailbox_crust", V(2.3, 0.9, 1.5), C(0, 4.6, 0), "LobbyWaferGroove"),
	p("egg", "mailbox_ear", V(0.5, 0.7, 0.3), C(-0.6, 5.1, 0), "LobbyWaferGroove"),
	p("egg", "mailbox_ear", V(0.5, 0.7, 0.3), C(0.6, 5.1, 0), "LobbyWaferGroove"),
	p("block", "mailbox_flag", V(0.15, 0.9, 0.6), C(1.2, 4.2, 0.3), "LobbyStrawberry"),
}
local TOAST_BENCH: { PropPart } = {
	p("block", "toast_bench_seat", V(5, 0.6, 1.8), C(0, 1.6, 0), "LobbyWafer"),
	p("block", "toast_bench_leg", V(0.6, 1.3, 1.4), C(-1.9, 0.65, 0), "LobbyWaferGroove"),
	p("block", "toast_bench_leg", V(0.6, 1.3, 1.4), C(1.9, 0.65, 0), "LobbyWaferGroove"),
	p("block", "toast_bench_back", V(5, 2.6, 0.5), C(0, 3.2, -0.65), "LobbyWafer"),
	p("egg", "toast_bench_crust", V(5.4, 1.4, 0.6), C(0, 4.5, -0.65), "LobbyWaferGroove"),
}
local FLOWER_BOX: { PropPart } = {
	p("block", "flower_box", V(5, 1.2, 1.8), C(0, 0.6, 0), "Cocoa"),
	p("block", "flower_box_line", V(0.15, 1.26, 1.86), C(-0.85, 0.6, 0), "ArenaTrunk"),
	p("block", "flower_box_line", V(0.15, 1.26, 1.86), C(0.85, 0.6, 0), "ArenaTrunk"),
	p("ball", "flower", V(0.9, 0, 0), C(-1.6, 1.5, 0), "LobbyStrawberry"),
	p("ball", "flower", V(0.9, 0, 0), C(0, 1.5, 0), "LobbyButter"),
	p("ball", "flower", V(0.9, 0, 0), C(1.6, 1.5, 0), "LobbySky"),
}
local PLANTER: { PropPart } = {
	p("cyl", "planter_pot", V(3, 1.6, 0), C(0, 0.8, 0), "LobbySky"),
	p("cyl", "planter_nest", V(3.4, 0.6, 0), C(0, 1.9, 0), "HubWood"),
	p("egg", "planter_egg", V(0.7, 0.9, 0.7), C(-0.6, 2.4, 0.2), "White"),
	p("egg", "planter_egg", V(0.7, 0.9, 0.7), C(0.5, 2.4, -0.3), "LobbySky"),
	p("egg", "planter_egg", V(0.7, 0.9, 0.7), C(0.2, 2.4, 0.6), "LobbyButter"),
	p("egg", "planter_leaf", V(1.6, 0.4, 0.8), C(-1.6, 1.9, 0) * CFrame.Angles(0, 0, 0.5), "ArenaOakLeaves"),
	p("egg", "planter_leaf", V(1.6, 0.4, 0.8), C(1.6, 1.9, 0) * CFrame.Angles(0, 0, -0.5), "ArenaOakLeaves"),
}

-- A frame on the ground `radius` out on compass angle `degrees`, its +Z toward the island centre, at height `y`.
local function groundFrame(radius: number, degrees: number, y: number, lateral: number?): CFrame
	local a = math.rad(degrees)
	local out = Vector3.new(math.sin(a), 0, -math.cos(a))
	local side = Vector3.new(math.cos(a), 0, math.sin(a))
	local point = out * radius + side * (lateral or 0) + Vector3.new(0, y, 0)
	return CFrame.lookAt(point, point + out) -- LookVector outward: the frame's +Z faces the centre
end

-- Readings: the hub decor between the paths (spec §3, §7), clear of the stations, their approaches and the range.
local BENCHES = { { 18, 30 }, { 54, 30 }, { 162, 30 }, { 198, 30 }, { 234, 30 }, { 342, 30 } } -- { compass °, radius }
local TABLES = { { 126, 29 }, { 270, 44 }, { 306, 40 }, { 306, 54 } }
local GARDEN_RADIUS = 84 -- reading: the middle of the garden ring (r 70-96)
local CUPCAKE_GARDEN = { 54, 126, 234, 342 } -- beside the lollipops, 8 studs either side
local CUPCAKE_GAPS = { 122, 140 } -- between the bases (on the sector lines)
local CUPCAKE_BEACH = 168
local SEA_LILY_PADS = { 40, 130, 220, 310 }

-- The Butter Fountain, the chocolate bar benches and the pancake stack tables (spec §3, §7).
local function buildHubDecor(state: State)
	local L = state.L
	local model = Prims.model("HubDecor", state.root, false)
	prop(state, model, "ButterFountain", stationCF(state, "fountain"), FOUNTAIN, { fountain_basin = true })
	for index, spot in BENCHES do
		prop(state, model, "ChocolateBench" .. index, groundFrame(spot[2], spot[1], L.Island.hub.top), BENCH)
	end
	for index, spot in TABLES do
		prop(state, model, "PancakeTable" .. index, groundFrame(spot[2], spot[1], L.Island.hub.top), TABLE)
	end
end

-- The garden ring and the beach (spec §2, §7): the 10 paths, their bollards and lanterns, the cupcake trees, the Toast
-- Stack Tower, the Banana Slide, the Frog Lily Pond and the lily pads on the sea.
local function buildGarden(state: State)
	local L = state.L
	local I = L.Island
	local model = Prims.model("Garden", state.root, false)
	local grass = I.grass.top
	for index, path in L.Paths do
		local dir = (path.to - path.from).Unit
		-- From under the hub's curb to under the plot's rim (both overhang the path's ends).
		local from, to = dir * (L.Lobby.hubRadius + 0.5), path.to + dir * 0.5
		Prims.part({
			name = "garden_path",
			size = Vector3.new((to - from).Magnitude, I.pathTop - grass, path.width),
			cframe = CFrame.new((from + to) / 2 + Vector3.new(0, (grass + I.pathTop) / 2, 0))
				* CFrame.Angles(0, -math.atan2(dir.Z, dir.X), 0),
			color = color(state, I.pathColor),
			flags = "solid",
			shadow = false,
			parent = model,
		})
		local degrees = (index - 1) * 360 / #L.Paths
		for _, radius in { 77, 89 } do
			for _, side in { -1, 1 } do
				prop(
					state,
					model,
					"BobaBollard",
					groundFrame(radius, degrees, grass, side * (path.width / 2 + 1)),
					BOLLARD
				)
			end
		end
		prop(
			state,
			model,
			"MochiFoxLantern",
			groundFrame(L.Lobby.hubRadius + 3, degrees, grass, path.width / 2 + 2),
			LANTERN
		)
	end
	local trees = 0
	local function tree(frame: CFrame)
		trees += 1
		if state.meshes.CupcakeTree then -- FIX 3: the Blender cup and frosting; the trunk and the cherry stay parts
			local parts = cupcakeTree(trees)
			local m = prop(state, model, "CupcakeTree", frame, { parts[1], parts[4] })
			placeMeshes(
				state,
				"CupcakeTree",
				frame,
				{ CupcakeTree_Cup = parts[2].token, CupcakeTree_Frosting = parts[3].token },
				m
			)
		else
			prop(state, model, "CupcakeTree", frame, cupcakeTree(trees))
		end
	end
	for _, degrees in CUPCAKE_GARDEN do
		for _, side in { -1, 1 } do
			tree(groundFrame(GARDEN_RADIUS - 4, degrees, grass, side * 8))
		end
	end
	for k = 0, #L.Paths - 1 do
		local degrees = 18 + k * 36
		for _, radius in CUPCAKE_GAPS do
			tree(groundFrame(radius, degrees, grass))
		end
		tree(groundFrame(CUPCAKE_BEACH, degrees, I.beach.top))
	end
	prop(state, model, "ToastStackTower", groundFrame(GARDEN_RADIUS, 18, grass), TOAST_TOWER)
	-- The slide: its chute is a quarter of a ring from the platform down to the grass (Kit/Props rods, banana yellow).
	local slide = prop(state, model, "BananaSlide", groundFrame(GARDEN_RADIUS, 162, grass), SLIDE)
	Props.rods(
		slide,
		"slide_chute",
		7,
		1.1,
		groundFrame(GARDEN_RADIUS, 162, grass) * CFrame.new(0, SLIDE_TOP + 0.5, 0) * CFrame.Angles(0, 0, -math.pi / 2),
		color(state, "LobbyButter"),
		5,
		math.pi / 2
	)
	-- The pond: water in a stone ring (Kit/Props annulus: the ring and the water disc on it), lily pads, the frog.
	local pondFrame = groundFrame(GARDEN_RADIUS, 198, grass)
	local pond = Prims.model("FrogLilyPond", model, false, pondFrame)
	Props.annulus(
		pond,
		"pond_rim",
		15,
		16.4,
		pondFrame * CFrame.new(0, 0.15, 0),
		0.15,
		color(state, "LobbyCushionCream"),
		color(state, "IslandShallow")
	)
	local water = 0.15 + Prims.LAYER
	for index, spot in { { -3, 2 }, { 3.5, -1 }, { 0, -4 } } do
		Props.cylinder(
			pond,
			"pond_lily_pad",
			2.6,
			0.06,
			pondFrame * CFrame.new(spot[1], water + 0.03 + index * Prims.LAYER, spot[2]),
			color(state, "ArenaFrogGreen")
		)
	end
	local frogBase = pondFrame * CFrame.new(0, water + 0.06 + 3 * Prims.LAYER, -4)
	placeToy(state, "PondFrog", "strawberry_frog", frogBase.Position, frogBase.LookVector * -1, 3, pond)
	local seaTop = L.Lobby.baseSlab.position.Y + L.Lobby.baseSlab.size.Y / 2
	for _, degrees in SEA_LILY_PADS do
		Props.cylinder(
			model,
			"sea_lily_pad",
			3,
			0.06,
			groundFrame(200, degrees, seaTop + 0.03),
			color(state, "ArenaFrogGreen")
		)
	end
end

-- The Cloud Bunny clouds (spec §7: sky ×6). Readings: 60° apart, r 110-130, Y 62-74; they cast no shadow.
local function buildSky(state: State)
	local model = Prims.model("Sky", state.root, false)
	for k = 0, 5 do
		local frame = groundFrame(110 + (k % 2) * 20, 30 + k * 60, 62 + (k % 3) * 6)
		local cloud: Model
		if state.meshes.CloudBunny then -- FIX 3: the Blender Cloud Bunny (its ears as the design draws them)
			cloud = Prims.model("CloudBunny", model, false, frame)
			placeMeshes(state, "CloudBunny", frame, { CloudBunny = "White" }, cloud)
		else
			cloud = prop(state, model, "CloudBunny", frame, CLOUD)
		end
		for _, part in cloud:GetDescendants() do
			if part:IsA("BasePart") then
				part.CastShadow = false
			end
		end
	end
end

-- One plot (spec §4): see the header. Built open (grey, "Open plot"); BaseService colours, names and fills it.
local function buildBase(state: State, index: number, folder: Instance)
	local L = state.L
	local B = L.Bases
	local name = B.models[index]
	local F = L.plotFrame(index) :: CFrame
	local model = Prims.model(name, folder, false, F)
	state.models[name] = model
	Prims.tag(model, L.Tags.Base, { [L.Attributes.Plot] = index })
	local open = B.openColors
	local function tint(part: BasePart, which: string)
		part:SetAttribute(L.Attributes.BaseTint, which)
	end
	local halfW, halfD = B.width / 2, B.depth / 2
	local grassDepth = -L.Island.grass.top -- the plinth reaches down to the grass
	local rim = Prims.part({
		name = "Rim",
		size = Vector3.new(B.width, grassDepth - BASE_RIM_DROP, B.depth),
		cframe = F * CFrame.new(0, -(grassDepth + BASE_RIM_DROP) / 2, 0),
		color = color(state, open.full),
		flags = "solid",
		parent = model,
	})
	tint(rim, "full")
	local floor = Prims.part({
		name = "Floor",
		size = Vector3.new(B.width - 2, grassDepth, B.depth - 2),
		cframe = F * CFrame.new(0, -grassDepth / 2, 0),
		color = color(state, open.light),
		material = Enum.Material.Plastic,
		flags = "solid",
		parent = model,
	})
	floor.TopSurface = Enum.SurfaceType.Studs -- spec §7: Roblox's own Studs surface
	tint(floor, "light")
	-- The back wall (44 × 9) with its cap in the plot's colour.
	local wallZ = -halfD + BACK_WALL.Z / 2
	Prims.part({
		name = "BackWall",
		size = BACK_WALL,
		cframe = F * CFrame.new(0, BACK_WALL.Y / 2, wallZ),
		color = color(state, "LobbyCushionCream"),
		flags = "solid",
		parent = model,
	})
	local cap = Prims.part({
		name = "BackWallCap",
		size = Vector3.new(BACK_WALL.X + 0.6, 0.8, BACK_WALL.Z + 0.6),
		cframe = F * CFrame.new(0, BACK_WALL.Y + 0.4, wallZ),
		color = color(state, open.full),
		flags = "decor",
		parent = model,
	})
	tint(cap, "full")
	-- The fence: white posts every 8 studs with caps in the plot's colour, two white rails, the gate's gap left open.
	local inset = B.fenceInset
	local postX, frontZ = halfW - inset, halfD - inset
	local posts: { Vector3 } = {}
	for _, side in { -1, 1 } do
		for _, z in FENCE_SIDE_Z do
			table.insert(posts, Vector3.new(side * postX, 0, z))
		end
		table.insert(posts, Vector3.new(side * postX, 0, frontZ))
		table.insert(posts, Vector3.new(side * FENCE_FRONT_X, 0, frontZ))
	end
	for _, post in posts do
		Prims.part({
			name = "FencePost",
			size = FENCE_POST,
			cframe = F * CFrame.new(post + Vector3.new(0, FENCE_POST.Y / 2, 0)),
			color = color(state, "LobbyTrimWhite"),
			flags = "solid",
			parent = model,
		})
		tint(
			Prims.part({
				name = "FenceCap",
				size = FENCE_CAP,
				cframe = F * CFrame.new(post + Vector3.new(0, FENCE_POST.Y + FENCE_CAP.Y / 2, 0)),
				color = color(state, open.full),
				flags = "decor",
				parent = model,
			}),
			"full"
		)
	end
	local gateEdge = B.gateWidth / 2 + GATE_PILLAR.X -- the gate pillars' outer faces
	local backZ = wallZ + BACK_WALL.Z / 2
	for _, y in FENCE_RAIL_Y do
		for _, side in { -1, 1 } do
			local sideLength = frontZ - backZ
			Prims.part({
				name = "FenceRail",
				size = Vector3.new(FENCE_RAIL, FENCE_RAIL, sideLength),
				cframe = F * CFrame.new(side * postX, y, (frontZ + backZ) / 2),
				color = color(state, "LobbyTrimWhite"),
				flags = "solid",
				parent = model,
			})
			local frontLength = postX - gateEdge
			Prims.part({
				name = "FenceRail",
				size = Vector3.new(frontLength, FENCE_RAIL, FENCE_RAIL),
				cframe = F * CFrame.new(side * (gateEdge + frontLength / 2), y, frontZ),
				color = color(state, "LobbyTrimWhite"),
				flags = "solid",
				parent = model,
			})
		end
	end
	-- The Donut Arch gate (spec §4, §7): dough pillars and half a donut over the 16-wide gap, its icing in the plot's
	-- colour with sprinkles, the name sign hanging under it.
	local gateZ = frontZ
	for _, side in { -1, 1 } do
		Props.cylinder(
			model,
			"GatePillar",
			GATE_PILLAR.X,
			GATE_PILLAR.Y,
			F * CFrame.new(side * (B.gateWidth / 2 + GATE_PILLAR.X / 2), GATE_PILLAR.Y / 2, gateZ),
			color(state, "LobbyWafer"),
			"solid"
		)
	end
	local archRadius = B.gateWidth / 2 + GATE_PILLAR.X / 2
	local arch = F * CFrame.new(0, GATE_PILLAR.Y, gateZ) -- the ring's plane: the gate's, around its local Z
	if state.meshes.DonutArch then -- FIX 3: the Blender donut, its icing on both faces, the design's sprinkles
		local made = placeMeshes(state, "DonutArch", arch, {
			DonutArch_Dough = "LobbyWafer",
			DonutArch_Icing = open.full,
			DonutArch_Sprinkles_White = "White",
			DonutArch_Sprinkles_Sky = "LobbySky",
			DonutArch_Sprinkles_Butter = "LobbyButter",
			DonutArch_Sprinkles_Mint = "LobbyMint",
		}, model)
		tint(made.DonutArch_Icing, "full")
	else
		Props.rods(model, "GateDough", archRadius, DONUT_TUBE, arch, color(state, "LobbyWafer"), 6, math.pi)
		for _, rod in
			Props.rods(
				model,
				"GateIcing",
				archRadius,
				DONUT_TUBE + 0.15,
				arch * CFrame.Angles(0, 0, math.pi / 6),
				color(state, open.full),
				5, -- not the dough's 6: no icing rod shares a dough rod's end planes (Flicker_Test)
				2 * math.pi / 3
			)
		do
			tint(rod, "full")
		end
		for k, token in { "LobbyButter", "LobbySky", "White", "LobbyMint", "LobbyButter", "White" } do
			local a = math.rad(45 + (k - 1) * 18)
			local r = archRadius + DONUT_TUBE + 0.1
			Prims.part({
				name = "GateSprinkle",
				size = Vector3.new(0.3, 0.3, 0.8),
				cframe = arch * CFrame.new(r * math.cos(a), r * math.sin(a), 0) * CFrame.Angles(0, 0, a),
				color = color(state, token),
				flags = "decor",
				parent = model,
			})
		end
	end
	local sign = B.nameSign
	local board = Prims.part({
		name = "NameSign",
		size = sign.size,
		cframe = F * CFrame.new(sign.position) * CFrame.Angles(0, math.pi, 0), -- its Front reads toward the hub
		color = color(state, "LobbyPlate"),
		flags = "decor",
		parent = model,
	})
	state.hosts[name .. "/nameSign"] = board
	local chainTop = GATE_PILLAR.Y + archRadius - DONUT_TUBE
	local chainBottom = sign.position.Y + sign.size.Y / 2
	for _, side in { -1, 1 } do
		Prims.part({
			name = "NameSignChain",
			size = Vector3.new(0.15, chainTop - chainBottom, 0.15),
			cframe = F * CFrame.new(side * 3, (chainTop + chainBottom) / 2, sign.position.Z),
			color = color(state, "LobbyGold"),
			flags = "decor",
			parent = model,
		})
	end
	-- FIX 1: the halo 1.2 over the arch's top, against the sky (seen from the plot's spawn and from the hub).
	local archHalo = F * CFrame.new(0, GATE_PILLAR.Y + archRadius + DONUT_TUBE + 1.2, gateZ)
	halo(state, "GateSparkle", board, archHalo.Position, WorldLook.HALO.gateSize) -- seen from about 44 studs
	-- The capsule pads (8 × 8, Slot) and the statue's plinth.
	for slot, pad in B.capsulePads do
		local part = Prims.part({
			name = "Pad" .. slot,
			size = Vector3.new(B.capsulePadSize, B.capsulePadTop, B.capsulePadSize),
			cframe = F * CFrame.new(pad + Vector3.new(0, B.capsulePadTop / 2, 0)),
			color = color(state, "LobbyTrimWhite"),
			flags = "solid",
			parent = model,
		})
		part:SetAttribute(L.Attributes.Slot, slot)
	end
	local statue = (F * B.statue).Position
	Props.cylinder(
		model,
		"StatuePlinth",
		STATUE_PLINTH.diameter,
		STATUE_PLINTH.height,
		CFrame.new(statue - Vector3.new(0, STATUE_PLINTH.height / 2, 0)),
		color(state, "LobbyTrimWhite"),
		"solid"
	)
	-- The plot's spawn (BaseService: the owner spawns here), invisible, flush with the floor.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = SPAWN_PAD
	spawn.CFrame = F * B.spawn * CFrame.new(0, -SPAWN_PAD.Y / 2, 0)
	spawn.Transparency = 1
	spawn.CastShadow = false
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.CanQuery = true
	spawn.CanTouch = true -- a SpawnLocation keeps its default touch
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Enabled = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
	spawn.Parent = model
	Prims.tag(spawn, L.Tags.BaseSpawn, { [L.Attributes.Plot] = index })
	-- Props (spec §4): the mailbox and the flower box by the gate, the bench and the planter by the back wall.
	prop(state, model, "KittyLoafMailbox", F * CFrame.new(17, 0, 21) * CFrame.Angles(0, math.pi, 0), MAILBOX)
	prop(state, model, "ChocolateFlowerBox", F * CFrame.new(-17, 0, 21), FLOWER_BOX)
	prop(state, model, "ToastBench", F * CFrame.new(15.5, 0, -19), TOAST_BENCH)
	prop(state, model, "BirdieNestPlanter", F * CFrame.new(-15.5, 0, -19), PLANTER)
end

local function buildBases(state: State)
	local folder = Prims.folder(BASES_FOLDER, state.root)
	for index = 1, #state.L.Bases.frames do
		buildBase(state, index, folder)
	end
end

-- Private: decor, signs, volumes ---------------------------------------------------------------------------------------

local function buildDecor(state: State)
	local L = state.L
	local model = Prims.model("Decor", state.root, false)
	local lollipops = L.Props.lollipops
	for index, foot in lollipops.positions do -- design: lobby.js:468
		local swirl = lollipops.colors[index]
		local lollipop: Model
		if state.meshes.Lollipop then -- FIX 3: the Blender stick, disk and raised swirl rings (the design's h 24, r 7)
			lollipop = Prims.model("Lollipop" .. index, model, false, CFrame.new(foot))
			placeMeshes(state, "Lollipop", CFrame.new(foot), {
				Lollipop_White = LOLLIPOP_STICK,
				Lollipop_RingA = swirl[1],
				Lollipop_RingB = swirl[2],
			}, lollipop)
		else
			lollipop = Props.lollipop(model, "Lollipop" .. index, foot, lollipops.height, lollipops.radius, {
				stick = color(state, LOLLIPOP_STICK),
				a = color(state, swirl[1]),
				b = color(state, swirl[2]),
			})
		end
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

-- Private: render rules and self-check ---------------------------------------------------------------------------------

-- Spec §7 render rules on the finished tree: nothing but a SpawnLocation is touched; parts under SMALL_PART studs cast
-- no shadow.
local function applyRenderRules(root: Instance)
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") then
			if not part:IsA("SpawnLocation") then
				part.CanTouch = false
			end
			if math.max(part.Size.X, part.Size.Y, part.Size.Z) < SMALL_PART then
				part.CastShadow = false
			end
		end
	end
end

local function everything(root: Instance): { Instance }
	local list = root:GetDescendants()
	table.insert(list, 1, root)
	return list
end

-- Whether a colliding part stands on a path (an aisle volume's CFrame and size): an upright cylinder or a ball by its
-- round footprint, anything else by its box (Verify.boxesOverlap). Touching never counts.
local function onPath(part: BasePart, volume: CFrame, size: Vector3): boolean
	local cf, s = part.CFrame, part.Size
	local shape = if part:IsA("Part") then part.Shape else Enum.PartType.Block
	local round = shape == Enum.PartType.Ball or (shape == Enum.PartType.Cylinder and math.abs(cf.XVector.Y) > 0.99)
	if not round then
		return Verify.boxesOverlap(volume, size, cf, s, 0.01)
	end
	local radius = if shape == Enum.PartType.Ball then s.X / 2 else math.min(s.Y, s.Z) / 2
	local halfHeight = if shape == Enum.PartType.Ball then radius else s.X / 2
	local p = volume:PointToObjectSpace(cf.Position)
	local h = size / 2
	if math.abs(p.Y) >= h.Y + halfHeight - 0.01 then
		return false
	end
	local dx, dz = math.max(math.abs(p.X) - h.X, 0), math.max(math.abs(p.Z) - h.Z, 0)
	return dx * dx + dz * dz < (radius - 0.01) ^ 2
end

-- The part counts of the budget zones (spec §7): the hub, the garden (GARDEN_ZONE) and each plot's static parts.
type Zones = { hub: number, garden: number, bases: { number } }
local function zoneParts(root: Instance): Zones
	local zones: Zones = { hub = 0, garden = 0, bases = {} }
	for _, child in root:GetChildren() do
		if child.Name == BASES_FOLDER then
			for _, base in child:GetChildren() do
				table.insert(zones.bases, Prims.countParts(base))
			end
		elseif GARDEN_ZONE[child.Name] then
			zones.garden += Prims.countParts(child)
		else
			zones.hub += Prims.countParts(child)
		end
	end
	return zones
end

-- Exact tag counts, unique station ids, one moving target, disabled prompts, the plots, the render rules, clear
-- paths and the budgets (§7.7, §17.6, spec §4, §7). `worstPlot`: the parts a plot's capsules, squishies and statue add
-- at their worst (CapsuleBuilder.worstPlotParts).
local function selfCheck(state: State, worstPlot: number): ({ string }, Zones, number, number)
	local L = state.L
	local problems: { string } = {}
	local all = everything(state.root)
	local counts: { [string]: number } = {}
	local stationIds: { [string]: boolean } = {}
	local plots: { [number]: boolean } = {}
	local guis, prompts, moving = 0, 0, 0
	local solids: { BasePart } = {}
	for _, instance in all do
		for _, tag in instance:GetTags() do
			counts[tag] = (counts[tag] or 0) + 1
		end
		if instance:IsA("BasePart") then
			local part = instance :: BasePart
			if part.CanTouch and not part:IsA("SpawnLocation") then
				table.insert(problems, part:GetFullName() .. " is touched (spec §7: CanTouch off)")
			end
			if part.CastShadow and math.max(part.Size.X, part.Size.Y, part.Size.Z) < SMALL_PART then
				table.insert(problems, part:GetFullName() .. " casts a shadow (spec §7: off under 2 studs)")
			end
			local top = part.Position.Y
				+ math.abs(part.CFrame.XVector.Y) * part.Size.X / 2
				+ math.abs(part.CFrame.YVector.Y) * part.Size.Y / 2
				+ math.abs(part.CFrame.ZVector.Y) * part.Size.Z / 2
			if
				part.CanCollide
				and top > WALKABLE_TOP
				and not part:HasTag(L.Tags.Boundary)
				and not part:HasTag(L.Tags.KeepClear)
			then
				table.insert(solids, part)
			end
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
		-- Spec §4: one Model per plot, holding the plot's one SpawnLocation (BaseService finds both by Plot).
		if instance:HasTag(L.Tags.Base) then
			local plot = instance:GetAttribute(L.Attributes.Plot)
			if type(plot) ~= "number" or L.plotFrame(plot) == nil or plots[plot] then
				table.insert(
					problems,
					string.format("%s has Plot %s (missing, unknown or repeated)", instance.Name, tostring(plot))
				)
			else
				plots[plot] = true
				local spawns = 0
				for _, d in instance:GetDescendants() do
					if
						d:HasTag(L.Tags.BaseSpawn)
						and d:IsA("SpawnLocation")
						and d:GetAttribute(L.Attributes.Plot) == plot
					then
						spawns += 1
					end
				end
				if spawns ~= 1 then
					table.insert(
						problems,
						string.format("%s holds %d spawns of its plot, expected 1", instance.Name, spawns)
					)
				end
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
	if guis > L.Budgets.lobbySurfaceGuis then
		table.insert(problems, string.format("%d SurfaceGuis, budget %d", guis, L.Budgets.lobbySurfaceGuis))
	end
	-- Spec §2: the paths stay 8 wide: nothing collidable stands on one (no station exemption).
	for _, volume in L.KeepClear do
		if volume.kind ~= "aisle" then
			continue
		end
		local cf = CFrame.new(volume.position) * CFrame.Angles(0, volume.yaw or 0, 0)
		local reach = (volume.size / 2).Magnitude
		for _, part in solids do
			if
				(part.Position - volume.position).Magnitude <= reach + part.Size.Magnitude / 2
				and onPath(part, cf, volume.size)
			then
				table.insert(problems, string.format("%s stands on %s", part:GetFullName(), volume.name))
			end
		end
	end
	-- Spec §7 part budget, every plot at its worst.
	local zones = zoneParts(state.root)
	local B = L.Budgets
	local total = zones.hub + zones.garden
	if zones.hub > B.hubParts then
		table.insert(problems, string.format("the hub has %d parts, budget %d", zones.hub, B.hubParts))
	end
	if zones.garden > B.gardenParts then
		table.insert(
			problems,
			string.format("the garden, beach and sky have %d parts, budget %d", zones.garden, B.gardenParts)
		)
	end
	for index, parts in zones.bases do
		local worst = parts + worstPlot
		total += worst
		if worst > B.baseParts then
			table.insert(
				problems,
				string.format(
					"plot %d has %d parts at its worst (%d + %d), budget %d",
					index,
					worst,
					parts,
					worstPlot,
					B.baseParts
				)
			)
		end
	end
	if total > B.islandParts then
		table.insert(problems, string.format("the island has %d parts at its worst, budget %d", total, B.islandParts))
	end
	return problems, zones, guis, prompts
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
	-- The plots' worst case (spec §7) from the capsule templates themselves, built in memory and thrown away.
	local templates = CapsuleBuilder.build({ scratch = ctx.scratch, Shared = ctx.Shared })
	if not templates.ok or templates.root == nil then
		return failure(warnings, "capsule templates (the plots' budget): " .. tostring(templates.error))
	end
	local worstPlot = CapsuleBuilder.worstPlotParts(templates.root, #deps.WorldLayout.Bases.capsulePads)
	templates.root:Destroy()

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
		meshes = {},
	}
	resolveMeshes(state)

	buildIsland(state)
	buildHub(state)
	buildSpawn(state)
	buildDuelGate(state)
	buildDuelTower(state)
	buildGiftBoxCounter(state)
	buildShopCounter(state)
	buildCollection(state)
	buildQuestBoard(state)
	buildDailyStand(state)
	buildSqueezeZone(state)
	buildPracticeRange(state)
	buildHubDecor(state)
	buildGarden(state)
	buildSky(state)
	buildDecor(state)
	buildBases(state)
	buildSigns(state) -- after every station model and host part exists
	buildVolumes(state)
	WorldLook.finish(root, deps.Palette) -- FIX 2: the finishes by colour
	applyRenderRules(root)

	local problems, zones, guis, prompts = selfCheck(state, worstPlot)
	if #problems > 0 then
		return failure(
			warnings,
			string.format("lobby self-check found %d problem(s): %s", #problems, table.concat(problems, "; "))
		)
	end
	for _, line in keepClearReport(state) do
		table.insert(warnings, line)
	end
	local B = state.L.Budgets
	local bases, worst = 0, 0
	for _, parts in zones.bases do
		bases += parts
		worst = math.max(worst, parts + worstPlot)
	end
	table.insert(
		warnings,
		string.format(
			"lobby report: hub %d parts (budget %d), garden/beach/sky %d (budget %d), %d plots %d static + %d each at "
				.. "their worst, the worst plot %d (budget %d), the island at its worst %d (budget %d); %d SurfaceGuis "
				.. "(budget %d), %d prompts (all disabled)",
			zones.hub,
			B.hubParts,
			zones.garden,
			B.gardenParts,
			#zones.bases,
			bases,
			worstPlot,
			worst,
			B.baseParts,
			zones.hub + zones.garden + bases + #zones.bases * worstPlot,
			B.islandParts,
			guis,
			B.lobbySurfaceGuis,
			prompts
		)
	)

	Generated.mark(root, GENERATOR_ID, VERSION)
	handedOver = true
	return { ok = true, root = root, warnings = warnings, error = nil }
end

return LobbyBuilder
