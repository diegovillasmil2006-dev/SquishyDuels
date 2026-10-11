--!strict
-- LobbyBuilder: builds the lobby Workspace.SD_Lobby (DESIGN §7.5-§7.7, the Grip pods of §17.6, the giant pads of
-- §17.6.1) as simple placeholder shapes. Server only, Edit mode only (ServerStorage.SDTools); called by Main's
-- pipeline (target "lobby"), never at runtime. Contract (Generated.BuildContext / BuildResult): build(ctx) returns
-- { ok, root, warnings, error } with the new tree UNPARENTED and marked GeneratorId "lobby"; it never parents anything
-- into the place. Relative requires, or modules of the injected ctx.Shared clone (never an absolute require).
--
-- Data: every coordinate, size, colour token, tag count and Strings key comes from Shared World/WorldLayout (the one
-- layout source the runtime reads too); colours are Art/Palette tokens; text is Shared Strings; the giant pads' Live
-- line uses Config.Grip.Pads[tier].level; the queue board uses Config.Duel.Arena.MaxSlots. The builder only adds
-- placeholder art details WorldLayout leaves open (shelf boards, awning tilt, target dummy shape, note cards, the
-- generator face fallback), each a named constant below.
--
-- Tree (each station an Atomic sub-model < 64 studs, so a prompt and its SurfaceGui stream together, §7.7):
--   SD_Lobby (Model, ModelStreamingMode Default, marked SD_Generated / lobby / VERSION)
--     Ground      base slab (Vanilla)                         Boundaries (Folder) 4 invisible walls, SD_Boundary
--     Shelves     5 perimeter runs (Kit/Props)                Promenade   carpet + Cream edge strips
--     Spawn       SpawnLocation (SD_LobbySpawn, Neutral, Duration 0) + logo floor plate sign
--     SqueezeZone rug, 6 mats (SD_SqueezeStation, StationId, GripTier 1), plinth + Kitty Bread statue (scale 7) with
--                 its ambient sparkle (one ParticleEmitter, Config.Vfx), sign
--     PracticeRange lane floor, firing line, ThrowBox (SD_PracticeZone), backstop, 9 target models
--                 (SD_PracticeTarget: TargetId, Distance, Moving, RailLength, Period) with nameplates, rail, hedge,
--                 sign, floor distance labels
--     DuelGate    queue pad, podium (SD_QueuePodium + prompt), arch, StatusBoard (SD_QueueBoard sign),
--                 ReturnPoint1/2 (SD_ReturnPoint, Slot)
--     GiftBoxCounter counter (SD_BoxStand, BoxId + prompt), neon rim, pedestal + gift_box (scale 4), odds board, sign
--     ShopCounter counter (SD_ShopCounter + prompt), back shelves, sign
--     Collection  two tiers, 8 pedestals (SD_CollectionPedestal, Slot + Inspect prompt; the squishy models are
--                 client-built later), kiosk (SD_CollectionKiosk + prompt), sign
--     QuestBoard  board sign (SD_QuestBoard + prompt), posts, three note cards
--     DailyStand  pedestal (SD_DailyStand + prompt) + gift_box (scale 1.5), sign
--     GripGym / RoyalPod  rug, jelly gates (SD_GripGate, GripTier), sign posts, pod signs (SD_GripSign: "Title"
--                 with SD_TextKey + "Live" without), and GiantPad_<key> (Atomic, SD_GiantPad: GripTier, PadKey):
--                   Collision  the invisible station box (SD_SqueezeStation, StationId, GripTier)
--                   Body       path B quilted cushion: rounded base (SD_ShapeLibrary.RoundedBox clone, fallback a Brick
--                              mesh) + tilesPerSide² tiles (Sphere SpecialMesh, tileSize, tileSpacing apart), pivot
--                              at the bottom centre; nothing collides, is queried or touched (group SD_Cosmetic).
--                              Accent parts (the Marshmallow's Lavender band, the Royal Cushion's tuft tile) carry
--                              SD_PadAccent = true: path A keeps them visible over its one-colour mesh
--                   Face       the face parts of the pad's blueprint (Art/SquishyBlueprints giant_*), or a small
--                              generator face when that blueprint is missing; on the side toward faceDirection
--     Decor       4 lollipops (Atomic), 2 toy-block stacks       KeepClear / AudioZones (Folders) invisible volumes
-- Lobby background motion (§18.5.1 A8): the models the client turns or breathes (AmbientController) carry the tag
-- SD_Ambient with SD_AmbientKind (WorldLayout.Tags.Ambient / Attributes.AmbientKind): Decor/Lollipop1..4 "spin",
-- DailyStand/GiftBox "spinBob", GiftBoxCounter/GiftBox and SqueezeZone/Statue "breathe". Each is an Atomic streaming
-- unit (the lollipops are made Atomic here; the others sit in Atomic station models) and none of their parts collides,
-- is queried or is touched (decor flags, SquishyBuilder parts), which the self-check enforces. The audio zone volumes
-- (practice included) are built from WorldLayout.AudioZones as they are.
-- Every ProximityPrompt is created DISABLED (WorldBinder enables a stand's prompt only when its UI exists, §7.6); its
-- ActionText is baked from Strings and its key is kept as SD_TextKey (and SD_AltTextKey for the toggled/relabelled
-- text). Signs: Kit/Signs (static lines SD_Sign + SD_TextKey; baked/live lines without SD_TextKey).
-- Self-check (§7.7): exact tag counts (WorldLayout.TagCounts), unique StationIds, one moving target, every prompt
-- disabled, inert SD_Ambient decor, part and SurfaceGui budgets; any problem fails the build. The keep-clear test (station models' own parts
-- exempt, as in Verify) and a part-count report come back as warnings (Verify decides).
-- Omitted on purpose (art scope: simple shapes, modest decor; DESIGN §7.6 / §7.7 / §17.6.1 still list them): jars
-- and mini squishies on the shelves, bunting, the Royal Cushion piping, the shop's toy cash register.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Generated = require(script.Parent.Parent.Generated)
local Prims = require(script.Parent.Parent.Kit.Prims)
local Props = require(script.Parent.Parent.Kit.Props)
local Signs = require(script.Parent.Parent.Kit.Signs)

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
}

type State = {
	deps: Deps,
	L: any, -- World/WorldLayout
	root: Model,
	warnings: { string },
	style: Signs.Style,
	models: { [string]: Instance }, -- station model name -> model (sign owners)
	hosts: { [string]: BasePart }, -- "<owner>/<part>" -> the station part that carries a sign
	roundedBox: BasePart?,
	warnedRoundedBox: boolean,
}

-- Constants

local GENERATOR_ID = "lobby"
local VERSION = 1
local ROOT_NAME = "SD_Lobby"

local SHAPE_LIBRARY_NAME = "SD_ShapeLibrary"
local ROUNDED_BOX_NAME = "RoundedBox"

local ATTR_FACE = "SD_Face" -- set by Art/SquishyBuilder on face parts
local ATTR_ATTACHED = "SD_AttachedTo" -- set by Art/SquishyBuilder on parts attached to a face part (shines)
local ATTR_ALT_TEXT_KEY = "SD_AltTextKey" -- the toggled (Leave Queue) / relabelled (Shop Squishies) prompt text
local ATTR_PAD_ACCENT = "SD_PadAccent" -- a giant pad Body part path A keeps visible (GiantPadController)
-- SD_AmbientKind values (§18.5.1 A8; Anim/AmbientMath reads the same three).
local AMBIENT_SPIN = "spin" -- the lollipops
local AMBIENT_SPIN_BOB = "spinBob" -- the daily gift box
local AMBIENT_BREATHE = "breathe" -- the counter gift box and the statue

-- Art details WorldLayout leaves open (placeholders; the team replaces looks later).
local SIGN_STYLE_TOKENS = { panel = "Cream", frame = "Cocoa", text = "Ink", stroke = "Cream" } -- §7.7
local SHELF_PANEL_TOKENS = { "Bubblegum", "MintCream", "LaneLilac" } -- pastel back panels
local SHELF_AWNING_TOKENS = { "Strawberry", "Cream" } -- striped awnings
local SHELF_CANDY_TOKENS = { "Mint", "Lemon", "Lavender", "Bubblegum" }
local NO_CANDY_RUNS = { NorthWest = true, West = true } -- §7.7 rule 4: nothing squishy-coloured near the lanes
local LOLLIPOP_TOKENS = { stick = "White", head = "Strawberry", swirl = "Cream" }
-- §7.7 props rule 4 (nothing squishy-coloured near the practice lanes): DESIGN's NW lollipop (-58, 0, -50) stands on
-- the lane floor behind the targets, so a lollipop on or beside the lane floor uses colours no squishy body has
-- (Strawberry is the Donut's icing).
local RANGE_LOLLIPOP_TOKENS = { stick = "White", head = "Blueberry", swirl = "LaneLilac" }
local RANGE_MARGIN = 4 -- studs around the practice lane floor that count as "near the lanes"
local TOY_BLOCK_TOKENS = { "Sky", "Cream", "Lavender" } -- the west stack stands by the practice range
local QUEUE_RING_GROWTH = 1 -- the Cream ring under the queue pad is this much wider
local MAT_RIM_HEIGHT_FACTOR = 0.8 -- the white rim is a little lower than the mat
local HEDGE_SPACING_FACTOR = 0.8 -- gumdrops this fraction of a diameter apart (overlapping)
local RETURN_MARKER_SIZE = Vector3.new(2, 0.2, 2)
local QUEST_BOARD_TOKEN = "Vanilla" -- Cardboard centre (§7.3)
local QUEST_NOTE_TOKENS = { "White", "Cream", "MintCream" }
local QUEST_NOTE_SIZE = Vector3.new(2.2, 2.0, 0.08)
local QUEST_NOTE_SPACING = 2.8
local QUEST_NOTE_Y = -1.3 -- board-local, below the title (the board sign is top-aligned in WorldLayout)
local PEDESTAL_TOKEN = "Lavender"
-- Statue sparkle (§7.7 "ambient sparkle at the statue"): rate, lifetime and texture from Config.Vfx; the look below.
local SPARKLE = {
	token = "Lemon",
	size = 0.5,
	speedMin = 8,
	speedMax = 10,
	drag = 2, -- from the statue's middle they drift 4-5 studs out (past its surface), slow down and fade
	spread = Vector2.new(180, 180),
}
-- Practice target "Foam Dummy" (§5.11: its hitbox is the player capsule, about 2.6 wide and 6.1 tall).
local TARGET_BASE = { diameter = 3, height = 0.2, token = "Cream" }
local TARGET_BODY_SIZE = Vector3.new(2.6, 4.2, 2.6)
local TARGET_HEAD_DIAMETER = 2
local TARGET_HEAD_SINK = 0.7 -- the head overlaps the body top by this much
local TARGET_RING = { diameter = 1.6, thickness = 0.1, y = 2.6, token = "Cream" }
local TARGET_DOT = { diameter = 0.7, thickness = 0.12, token = "Sky" }
local TARGET_NAMEPLATE = { size = Vector3.new(3.6, 0.9, 0.2), y = 6.9, letter = 0.6 }
local RAIL = { width = 0.4, height = 0.07, token = "Sky" }
-- Giant pads (§17.6.1 path B): accents WorldLayout names per pad look.
local PAD_ACCENT_STYLE = { marshmallow = "band", royal = "tuft" } -- Lavender bottom band; Strawberry centre tuft
local PAD_BAND_HEIGHT = 0.35
local PAD_BAND_GROWTH = 0.12
-- Generator face (used only when the pad's blueprint is missing): the §8.1 #7 face kit, scaled for a giant pad.
local FACE_KIT = {
	pupil = "2B1E26",
	shine = "FFFFFF",
	mouth = "7A2E3E",
	blush = "FF9FB8",
	eyeSize = Vector3.new(0.5, 0.62, 0.9), -- lateral × height × depth
	eyeLateral = 1.1,
	eyeOut = 0.12, -- eye centre this far outside the side plane
	eyeYFactor = 0.42, -- eye height = restTop × this
	shineSize = Vector3.new(0.16, 0.16, 0.1),
	shineOffset = Vector3.new(0.1, 0.14, 0.38), -- toward own left, up, out from the eye centre
	mouthSize = Vector3.new(0.42, 0.22, 0.6),
	mouthDrop = 0.32,
	mouthOut = 0.05,
	blushSize = Vector3.new(0.6, 0.26, 0.5),
	blushLateral = 1.95,
	blushDrop = 0.25,
	blushOut = 0.02,
}

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
	for name, path in
		{
			Strings = "Strings",
			Palette = "Art/Palette",
			SquishyBuilder = "Art/SquishyBuilder",
			Config = "Config",
			WorldLayout = "World/WorldLayout",
		} :: { [string]: string }
	do
		local module, err = requirePath(shared, path)
		if module == nil then
			return nil, err
		end
		loaded[name] = module
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

-- Every Strings key the build bakes or tags (sign lines, prompts, nameplates). Sorted, without duplicates.
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
	for _, target in L.PracticeRange.targets do
		table.insert(list, target.nameKey)
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

local function flat(v: Vector3): Vector3
	local h = Vector3.new(v.X, 0, v.Z)
	return if h.Magnitude > 1e-6 then h.Unit else Vector3.new(0, 0, -1)
end

-- A part from a WorldLayout Box ({ position, size, facing?, color? }).
local function boxPart(
	state: State,
	name: string,
	box: any,
	parent: Instance,
	flags: Prims.Flags?,
	token: string?,
	material: Enum.Material?
): Part
	return Prims.part({
		name = name,
		size = box.size,
		cframe = state.L.boxCFrame(box),
		color = color(state, token or box.color),
		material = material,
		flags = flags,
		parent = parent,
	})
end

-- An upright cylinder from a WorldLayout Disc ({ position, diameter, height, color? }).
local function discPart(
	state: State,
	name: string,
	disc: any,
	parent: Instance,
	flags: Prims.Flags?,
	token: string?
): Part
	return Prims.disc(name, disc.diameter, disc.height, disc.position, color(state, token or disc.color), flags, parent)
end

-- An invisible volume from a WorldLayout Volume ({ name?, position, size }).
local function volumePart(name: string, volume: any, parent: Instance): Part
	return Prims.part({
		name = name,
		size = volume.size,
		cframe = CFrame.new(volume.position),
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

-- Builds a squishy blueprint (Art/SquishyBuilder, "World" mode) standing on the surface point `surface`, facing
-- `facing`. A builder failure is a warning (the station still works), never a crash.
local function placeSquishy(state: State, name: string, spec: any, parent: Instance): Model?
	local ok, result = pcall(state.deps.SquishyBuilder.build, spec.blueprintId, "World", spec.scale)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		table.insert(
			state.warnings,
			string.format("%s: SquishyBuilder.build(%q) failed: %s", name, tostring(spec.blueprintId), tostring(result))
		)
		return nil
	end
	local model = result :: Model
	local lowest = Prims.lowestY(model) -- the model is built around its pivot at the origin
	local standing = if lowest == math.huge then 0 else lowest
	moveModel(model, Prims.facing(spec.position - Vector3.new(0, standing, 0), spec.facing))
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

-- Private: sections ---------------------------------------------------------------------------------------------------

local function buildGround(state: State)
	local L = state.L
	local ground = Prims.model("Ground", state.root, false)
	boxPart(state, "BaseSlab", L.Lobby.baseSlab, ground, "solid")
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
	end
end

local function buildShelves(state: State)
	local L = state.L
	local shelves = L.Lobby.Shelves
	local model = Prims.model("Shelves", state.root, false)
	local panels, awnings, candy = {}, {}, {}
	for _, token in SHELF_PANEL_TOKENS do
		table.insert(panels, color(state, token))
	end
	for _, token in SHELF_AWNING_TOKENS do
		table.insert(awnings, color(state, token))
	end
	for _, token in SHELF_CANDY_TOKENS do
		table.insert(candy, color(state, token))
	end
	local awningY = { L.Props.awnings.minY, L.Props.awnings.maxY }
	for _, run in shelves.runs do
		Props.shelfRun(model, run.name, run.from, run.to, run.facing, shelves.unitSize, awningY, {
			body = color(state, shelves.color),
			panels = panels,
			awnings = awnings,
			candy = if NO_CANDY_RUNS[run.name] then nil else candy,
		})
	end
end

local function buildPromenade(state: State)
	local L = state.L
	local model = Prims.model("Promenade", state.root, false)
	boxPart(state, "Carpet", L.Promenade.carpet, model, "solid")
	for index, strip in L.Promenade.edgeStrips do
		boxPart(state, "EdgeStrip" .. index, strip, model, "solid")
	end
end

local function buildSpawn(state: State)
	local L = state.L
	local model = station(state, L.Spawn.model, true)
	local box = L.Spawn.location
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Size = box.size
	spawn.CFrame = L.boxCFrame(box)
	spawn.Color = color(state, box.color)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.BottomSurface = Enum.SurfaceType.Smooth
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
	-- The logo plate is decor (no tiny step to trip on); it carries the floor sign.
	state.hosts[L.Spawn.model .. "/logoPlate"] = boxPart(state, "LogoPlate", L.Spawn.logoPlate, model, "decor")
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
	boxPart(state, "Rug", zone.rug, model, "solid")
	for _, entry in L.Stations do
		if entry.kind ~= "mat" then
			continue
		end
		local p = entry.position
		local mat = Prims.disc(
			"Mat_" .. entry.id,
			zone.matDiameter,
			zone.matHeight,
			Vector3.new(p.X, zone.matHeight / 2, p.Z),
			color(state, zone.matColor),
			"solid",
			model
		)
		Prims.tag(mat, L.Tags.SqueezeStation, {
			[L.Attributes.StationId] = entry.id,
			[L.Attributes.GripTier] = entry.tier,
		})
		local rimHeight = zone.matHeight * MAT_RIM_HEIGHT_FACTOR
		Prims.disc(
			"MatRim_" .. entry.id,
			zone.matDiameter + 2 * zone.matRimWidth,
			rimHeight,
			Vector3.new(p.X, rimHeight / 2, p.Z),
			color(state, zone.matRimColor),
			"decor",
			model
		)
	end
	local plinth = boxPart(state, "Plinth", zone.plinth, model, "solid")
	markAmbient(state, placeSquishy(state, "Statue", zone.statue, model), AMBIENT_BREATHE)
	buildStatueSparkle(state, plinth, zone.sparkle)
end

local function buildTarget(state: State, parent: Instance, target: any, floorTop: number, facing: Vector3)
	local L = state.L
	local base = Vector3.new(target.position.X, floorTop, target.position.Z)
	local pivot = Prims.facing(base, facing)
	local model = Prims.model("Target_" .. target.id, parent, false, pivot)
	Prims.tag(model, L.Tags.PracticeTarget, {
		[L.Attributes.TargetId] = target.id,
		[L.Attributes.Distance] = target.distance,
		[L.Attributes.Moving] = target.moving,
		[L.Attributes.RailLength] = target.railLength,
		[L.Attributes.Period] = target.period,
	})
	local targetColor = color(state, L.PracticeRange.targetColor)
	Prims.disc(
		"Base",
		TARGET_BASE.diameter,
		TARGET_BASE.height,
		base + Vector3.new(0, TARGET_BASE.height / 2, 0),
		color(state, TARGET_BASE.token),
		"decor",
		model
	)
	local bodyBottom = TARGET_BASE.height
	Prims.meshPart(
		"Body",
		Enum.MeshType.Sphere,
		TARGET_BODY_SIZE,
		pivot * CFrame.new(0, bodyBottom + TARGET_BODY_SIZE.Y / 2, 0),
		targetColor,
		"decor",
		model
	)
	local headY = bodyBottom + TARGET_BODY_SIZE.Y - TARGET_HEAD_SINK + TARGET_HEAD_DIAMETER / 2
	Prims.part({
		name = "Head",
		shape = Enum.PartType.Ball,
		size = Vector3.one * TARGET_HEAD_DIAMETER,
		cframe = pivot * CFrame.new(0, headY, 0),
		color = targetColor,
		flags = "decor",
		parent = model,
	})
	-- Bullseye on the body front (local -Z). A cylinder runs along its X axis: turn it to point along the facing.
	local radius = TARGET_BODY_SIZE.X / 2
	local function bullseye(name: string, diameter: number, thickness: number, out: number, token: string)
		Prims.part({
			name = name,
			shape = Enum.PartType.Cylinder,
			size = Vector3.new(thickness, diameter, diameter),
			cframe = pivot * CFrame.new(0, TARGET_RING.y, -(radius - 0.05 + out)) * CFrame.Angles(0, math.rad(90), 0),
			color = color(state, token),
			flags = "decor",
			parent = model,
		})
	end
	bullseye("Ring", TARGET_RING.diameter, TARGET_RING.thickness, 0, TARGET_RING.token)
	bullseye("Dot", TARGET_DOT.diameter, TARGET_DOT.thickness, 0.02, TARGET_DOT.token)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			Prims.cosmetic(part)
		end
	end
	Signs.build(state.deps.Strings, {
		id = "Nameplate",
		position = base + Vector3.new(0, TARGET_NAMEPLATE.y, 0),
		size = TARGET_NAMEPLATE.size,
		facing = facing,
		face = "Front",
		lines = {
			{
				name = "Name",
				textKey = target.nameKey,
				live = false,
				letterHeight = TARGET_NAMEPLATE.letter,
				font = "body",
			},
		},
	}, { style = state.style, frame = false, parent = model })
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
	boxPart(state, "LaneFloor", range.laneFloor, model, "solid")
	boxPart(state, "FiringLine", range.firingLine, model, "solid")
	local zone = volumePart("ThrowBox", range.throwBox, model)
	Prims.tag(zone, range.zoneTag)
	boxPart(state, "Backstop", range.backstop, model, "solid")
	local targets = Prims.folder("Targets", model)
	local facing = -flat(range.throwDirection) -- the dummies face the thrower
	for _, target in range.targets do
		buildTarget(state, targets, target, range.laneFloorTopY, facing)
	end
	local hedge = range.hedge
	Props.gumdropHedge(
		model,
		"Hedge",
		hedge.from,
		hedge.to,
		hedge.ballDiameter,
		hedge.ballDiameter * HEDGE_SPACING_FACTOR,
		color(state, hedge.color)
	)
end

local function buildDuelGate(state: State)
	local L = state.L
	local gate = L.DuelGate
	local model = station(state, gate.model, true)
	local pad = gate.queuePad
	discPart(state, "QueuePad", pad, model, "solid")
	Prims.disc(
		"QueuePadRing",
		pad.diameter + QUEUE_RING_GROWTH,
		pad.height * 0.8,
		Vector3.new(pad.position.X, pad.height * 0.4, pad.position.Z),
		color(state, gate.queuePadRingColor),
		"decor",
		model
	)
	local podium = boxPart(state, "Podium", gate.podium, model, "solid")
	Prims.tag(podium, gate.podiumTag)
	addPrompt(state, podium, gate.prompt)
	for index, post in gate.posts do
		boxPart(state, if index == 1 then "PostWest" else "PostEast", post, model, "solid")
	end
	boxPart(state, "Beam", gate.beam, model, "decor") -- Y 18-22: out of reach, kept out of camera occlusion
	local board = boxPart(state, "StatusBoard", gate.statusBoard, model, "decor")
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
	local counter = boxPart(state, "Counter", stand.counter, model, "solid")
	Prims.tag(counter, stand.tag, { [L.Attributes.BoxId] = stand.boxId })
	addPrompt(state, counter, stand.prompt)
	-- §7.3: the only Neon in the lobby, a small rim on the counter top.
	boxPart(state, "NeonRim", stand.neonRim, model, "decor", nil, Enum.Material.Neon)
	boxPart(state, "Pedestal", stand.pedestal, model, "solid")
	markAmbient(state, placeSquishy(state, "GiftBox", stand.giftBox, model), AMBIENT_BREATHE)
	state.hosts[stand.model .. "/oddsBoard"] = boxPart(state, "OddsBoard", stand.oddsBoard, model, "decor")
end

local function buildShopCounter(state: State)
	local L = state.L
	local stand = L.ShopCounter
	local model = station(state, stand.model, true)
	local counter = boxPart(state, "Counter", stand.counter, model, "solid", nil, Enum.Material.Wood)
	Prims.tag(counter, stand.tag)
	addPrompt(state, counter, stand.prompt)
	boxPart(state, "BackShelves", stand.backShelves, model, "solid", nil, Enum.Material.WoodPlanks)
end

local function buildCollection(state: State)
	local L = state.L
	local stand = L.Collection
	local model = station(state, stand.model, true)
	boxPart(state, "Tier1", stand.tier1, model, "solid")
	boxPart(state, "Tier2", stand.tier2, model, "solid")
	for _, pedestal in stand.pedestals do
		local part = Prims.part({
			name = "Pedestal" .. pedestal.slot,
			size = pedestal.size,
			cframe = CFrame.new(pedestal.position),
			color = color(state, PEDESTAL_TOKEN),
			flags = "solid",
			parent = model,
		})
		Prims.tag(part, stand.pedestalTag, { [L.Attributes.Slot] = pedestal.slot })
		addPrompt(state, part, pedestal.prompt)
	end
	local kiosk = boxPart(state, "Kiosk", stand.kiosk, model, "solid")
	Prims.tag(kiosk, stand.kioskTag)
	addPrompt(state, kiosk, stand.prompt)
end

local function buildQuestBoard(state: State)
	local L = state.L
	local stand = L.QuestBoard
	local model = station(state, stand.model, true)
	local board = boxPart(state, "Board", stand.board, model, "solid", QUEST_BOARD_TOKEN, Enum.Material.Cardboard)
	Prims.tag(board, stand.tag)
	addPrompt(state, board, stand.prompt)
	state.hosts[stand.model .. "/board"] = board
	for index, post in stand.posts do
		boxPart(state, if index == 1 then "PostLeft" else "PostRight", post, model, "solid", nil, Enum.Material.Wood)
	end
	local front = -stand.board.size.Z / 2 - QUEST_NOTE_SIZE.Z / 2
	for index, token in QUEST_NOTE_TOKENS do
		Prims.part({
			name = "Note" .. index,
			size = QUEST_NOTE_SIZE,
			cframe = board.CFrame * CFrame.new((index - 2) * QUEST_NOTE_SPACING, QUEST_NOTE_Y, front),
			color = color(state, token),
			flags = "decor",
			parent = model,
		})
	end
end

local function buildDailyStand(state: State)
	local L = state.L
	local stand = L.DailyStand
	local model = station(state, stand.model, true)
	local pedestal = discPart(state, "Pedestal", stand.pedestal, model, "solid")
	Prims.tag(pedestal, stand.tag)
	addPrompt(state, pedestal, stand.prompt)
	markAmbient(state, placeSquishy(state, "GiftBox", stand.giftBox, model), AMBIENT_SPIN_BOB)
end

-- The face of a giant pad: the face parts of its blueprint, or the generator face when the blueprint is missing.
local function buildPadFace(state: State, pad: any, face: Model)
	local direction = flat(pad.faceDirection)
	local ok, result = pcall(state.deps.SquishyBuilder.build, pad.blueprintId, "Viewport", 1)
	if ok and typeof(result) == "Instance" and result:IsA("Model") then
		local built = result :: Model
		local lowest = Prims.lowestY(built)
		local frame = Prims.facing(pad.center, direction) * CFrame.new(0, if lowest == math.huge then 0 else -lowest, 0)
		local moved = 0
		for _, child in built:GetChildren() do
			if
				child:IsA("BasePart")
				and (child:GetAttribute(ATTR_FACE) == true or child:GetAttribute(ATTR_ATTACHED) ~= nil)
			then
				child.CFrame = frame * child.CFrame
				child.Parent = face
				moved += 1
			end
		end
		built:Destroy()
		if moved > 0 then
			return
		end
		table.insert(
			state.warnings,
			string.format("%s: blueprint %s has no face parts; built the generator face", pad.model, pad.blueprintId)
		)
	else
		table.insert(
			state.warnings,
			string.format(
				"%s: blueprint %s not built (%s); built the generator face",
				pad.model,
				tostring(pad.blueprintId),
				tostring(result)
			)
		)
	end

	local kit = FACE_KIT
	local left = Vector3.new(0, 1, 0):Cross(direction) -- the pad's own left as it looks along `direction`
	local side = pad.center + direction * (pad.footprint / 2)
	local eyeY = pad.restTop * kit.eyeYFactor
	local function feature(name: string, size: Vector3, position: Vector3, hex: string)
		local part = Prims.meshPart(
			name,
			Enum.MeshType.Sphere,
			size,
			Prims.facing(position, direction),
			Color3.fromHex(hex),
			"decor",
			face
		)
		Prims.cosmetic(part)
	end
	for _, sideSign in { 1, -1 } do
		local suffix = if sideSign == 1 then "L" else "R"
		local eye = side + left * (kit.eyeLateral * sideSign) + direction * kit.eyeOut + Vector3.new(0, eyeY, 0)
		feature("Eye" .. suffix, kit.eyeSize, eye, kit.pupil)
		local shine = eye
			+ left * kit.shineOffset.X
			+ Vector3.new(0, kit.shineOffset.Y, 0)
			+ direction * kit.shineOffset.Z
		feature("Shine" .. suffix, kit.shineSize, shine, kit.shine)
		local blush = side
			+ left * (kit.blushLateral * sideSign)
			+ direction * kit.blushOut
			+ Vector3.new(0, eyeY - kit.blushDrop, 0)
		feature("Blush" .. suffix, kit.blushSize, blush, kit.blush)
	end
	feature(
		"Mouth",
		kit.mouthSize,
		side + direction * kit.mouthOut + Vector3.new(0, eyeY - kit.mouthDrop, 0),
		kit.mouth
	)
end

-- GiantPad_<key>: Collision (the station), Body (path B quilted cushion), Face (§17.6.1).
local function buildGiantPad(state: State, pad: any, parent: Instance)
	local L = state.L
	local look = pad.look
	local bottom = CFrame.new(pad.center.X, 0, pad.center.Z)
	local model = Prims.model(pad.model, parent, true, bottom)
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

	local body = Prims.model("Body", model, false, bottom)
	local tileHeight = pad.tileSize.Y
	local baseHeight = pad.restTop - tileHeight / 2 -- tile centres sit on the base top; tile tops at restTop
	local base, usedFallback = Prims.roundedBox(
		state.roundedBox,
		"Base",
		Vector3.new(pad.footprint, baseHeight, pad.footprint),
		bottom * CFrame.new(0, baseHeight / 2, 0),
		color(state, look.body),
		body
	)
	base.Transparency = look.transparency
	if usedFallback and not state.warnedRoundedBox then
		state.warnedRoundedBox = true
		table.insert(
			state.warnings,
			string.format(
				"ReplicatedStorage.%s.%s is missing (run the shapes generator): giant pad bases are plain boxes",
				SHAPE_LIBRARY_NAME,
				ROUNDED_BOX_NAME
			)
		)
	end
	local accentStyle = PAD_ACCENT_STYLE[pad.key]
	if accentStyle == "band" and look.accent then
		local band = Prims.roundedBox(
			state.roundedBox,
			"Band",
			Vector3.new(pad.footprint + PAD_BAND_GROWTH, PAD_BAND_HEIGHT, pad.footprint + PAD_BAND_GROWTH),
			bottom * CFrame.new(0, PAD_BAND_HEIGHT / 2, 0),
			color(state, look.accent),
			body
		)
		band:SetAttribute(ATTR_PAD_ACCENT, true)
	end
	local n = pad.tilesPerSide
	local middle = (n + 1) / 2
	local topColor = color(state, look.top)
	local tuftColor = if accentStyle == "tuft" and look.accent then color(state, look.accent) else nil
	for row = 1, n do
		for column = 1, n do
			local isTuft = tuftColor ~= nil and row == middle and column == middle
			local tile = Prims.meshPart(
				string.format("Tile_%02d_%02d", row, column),
				Enum.MeshType.Sphere,
				pad.tileSize,
				bottom * CFrame.new((column - middle) * pad.tileSpacing, baseHeight, (row - middle) * pad.tileSpacing),
				if isTuft then tuftColor :: Color3 else topColor,
				"decor",
				body
			)
			tile.Transparency = look.transparency
			if isTuft then
				tile:SetAttribute(ATTR_PAD_ACCENT, true)
			end
		end
	end
	for _, part in body:GetDescendants() do
		if part:IsA("BasePart") then
			Prims.cosmetic(part)
		end
	end

	local face = Prims.model("Face", model, false, bottom)
	buildPadFace(state, pad, face)
end

local function buildGrip(state: State)
	local L = state.L
	for _, podKey in { "gym", "royal" } do
		local pod = L.Pods[podKey]
		local model = station(state, pod.model, false)
		boxPart(state, "Rug", pod.rug, model, "solid")
		for _, key in pod.padKeys do
			local pad = L.GiantPads[key]
			local gate = Prims.disc(
				"Gate_" .. key,
				pad.gate.diameter,
				pad.gate.height,
				pad.gate.position,
				color(state, pad.gate.color),
				"decor", -- CanCollide/CanQuery/CanTouch false: WorldBinder closes it locally (§17.6)
				model
			)
			gate.Transparency = pad.gate.transparency
			gate.CastShadow = false
			Prims.tag(gate, L.Tags.GripGate, { [L.Attributes.GripTier] = pad.tier })
			boxPart(state, "SignPost_" .. key, pad.signPost, model, "decor", nil, Enum.Material.Wood)
			buildGiantPad(state, pad, model)
		end
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
		local bakeArgs: { [string]: any } = { count = 0, max = maxSlots }
		if sign.tier ~= nil then
			local gripPad = state.deps.GripPads[sign.tier]
			bakeArgs.level = if gripPad then gripPad.level else nil
		end
		Signs.build(state.deps.Strings, sign, {
			style = state.style,
			host = host,
			bakeArgs = bakeArgs,
			align = sign.align,
			parent = owner,
		})
	end
end

local function buildDecor(state: State)
	local L = state.L
	local model = Prims.model("Decor", state.root, false)
	local lollipops = L.Props.lollipops
	local function lollipopStyle(tokens: { stick: string, head: string, swirl: string }): Props.LollipopStyle
		return {
			stick = color(state, tokens.stick),
			head = color(state, tokens.head),
			swirl = color(state, tokens.swirl),
		}
	end
	local style = lollipopStyle(LOLLIPOP_TOKENS)
	local rangeStyle = lollipopStyle(RANGE_LOLLIPOP_TOKENS)
	local laneLow, laneHigh = L.boxBounds(L.PracticeRange.laneFloor)
	local function nearLanes(position: Vector3): boolean
		return position.X >= laneLow.X - RANGE_MARGIN
			and position.X <= laneHigh.X + RANGE_MARGIN
			and position.Z >= laneLow.Z - RANGE_MARGIN
			and position.Z <= laneHigh.Z + RANGE_MARGIN
	end
	for index, position in lollipops.positions do
		local lollipop = Props.lollipop(model, "Lollipop" .. index, position, -flat(position), {
			stickDiameter = lollipops.stickDiameter,
			stickHeight = lollipops.stickHeight,
			headDiameter = lollipops.headDiameter,
			headThickness = lollipops.headThickness,
		}, if nearLanes(position) then rangeStyle else style)
		-- §18.5.1 A8: the client spins it about its pivot (the stick's foot), so it streams as one piece.
		lollipop.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		markAmbient(state, lollipop, AMBIENT_SPIN)
	end
	local blockColors = {}
	for _, token in TOY_BLOCK_TOKENS do
		table.insert(blockColors, color(state, token))
	end
	for index, position in L.Props.toyBlocks.positions do
		Props.toyBlocks(model, "ToyBlocks" .. index, position, L.Props.toyBlocks.footprint, blockColors)
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

local function bounds(part: BasePart): (Vector3, Vector3)
	local cf, half = part.CFrame, part.Size / 2
	local extent = Vector3.new(
		math.abs(cf.XVector.X) * half.X + math.abs(cf.YVector.X) * half.Y + math.abs(cf.ZVector.X) * half.Z,
		math.abs(cf.XVector.Y) * half.X + math.abs(cf.YVector.Y) * half.Y + math.abs(cf.ZVector.Y) * half.Z,
		math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
	)
	return cf.Position - extent, cf.Position + extent
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

-- §7.7 props rule 5 on the unparented tree (spatial queries need the Workspace, so this is the same test on bounding
-- boxes): every collidable part, station bodies excepted, whose box shares volume with a keep-clear volume. One
-- warning per pair.
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
		local vMin, vMax = bounds(volume)
		for _, part in solids do
			local pMin, pMax = bounds(part)
			if L.boundsOverlap(vMin, vMax, pMin, pMax) then
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
		roundedBox = if roundedBox and roundedBox:IsA("BasePart") then roundedBox else nil,
		warnedRoundedBox = false,
	}

	buildGround(state)
	buildShelves(state)
	buildPromenade(state)
	buildSpawn(state)
	buildSqueezeZone(state)
	buildPracticeRange(state)
	buildDuelGate(state)
	buildGiftBoxCounter(state)
	buildShopCounter(state)
	buildCollection(state)
	buildQuestBoard(state)
	buildDailyStand(state)
	buildGrip(state)
	buildSigns(state) -- after every station model and host part exists
	buildDecor(state)
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
