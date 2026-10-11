--!strict
-- ArenaKit: the shared frame and helpers of the 5 design arena generators in Builders/Arenas (phase 4 spec 2026-10-11
-- §5.2). Server only, Edit mode only (ServerStorage.SDTools); called by each arena builder's build(ctx), which Main's
-- pipeline runs and swaps into ServerStorage.SD_Templates. ArenaBuilder (Candy Court) is untouched and shares nothing
-- with this module except the contract.
--
-- ArenaKit.build(ctx, spec, art) makes the whole tree UNPARENTED, marked with spec.generatorId / spec.version and
-- SD_ArenaId = spec.arenaId, in Candy Court's layout (ArenaBuilder's header): every gameplay volume comes from
-- WorldLayout.Arena (origin, barriers and their groups, dividers, zones, the audio zone, pads), so every arena keeps
-- Candy Court's frame exactly (spec §3.4); the cover comes from World/Arenas (Atomic Models "Cover_<name>", PrimaryPart
-- Body, attribute SD_CoverKind "full" | "low", WorldPivot = the piece's floor frame). The arena's own art(kit) then
-- fills Geometry/Floor (top Y 0 out to the barrier walls), Geometry/Markings, Geometry/Rails (inside the 2-stud
-- gutter, <= 5 tall) and Decor; the kit adds the apron and the two boundary jelly planes to Decor itself.
-- Flags (Kit/Prims presets): "solid" floor, rails, cover (collide + query); "marking" thin floor paint (query only, no
-- shadow); "decor" (nothing collides, is queried or touched); "volume" zones and Origin (invisible); "barrier" walls.
-- No Neon, no lights, no scripts, no prompts (spec D6): glows are plain colours. Colours are Art/Palette tokens
-- (a missing token fails the build with its name); words come from Strings (Kit/Signs); the star and heart emblems
-- are symbol glyphs.
-- Helpers take the kit first: ArenaKit.part(k, parent, name, size, cframe, token, flags?, shape?, material?) etc.
-- CornerWedgePart (pyramid roofs): its apex sits over the corner CORNER_APEX of its base, per the Roblox part shape;
-- if a roof shows inverted in Studio, flip that one constant.

local Generated = require(script.Parent.Parent.Parent.Generated)
local Prims = require(script.Parent.Parent.Parent.Kit.Prims)
local Signs = require(script.Parent.Parent.Parent.Kit.Signs)

-- Types

export type BuildContext = Generated.BuildContext
export type BuildResult = Generated.BuildResult

export type Flags = "solid" | "marking" | "decor" | "volume" | "barrier"

-- What an arena builder hands build().
export type Spec = {
	arenaId: string,
	generatorId: string,
	version: number,
	rootName: string,
	apron: string, -- Palette token of the decor floor (the design's floor base)
	padA: string, -- pad colours (NOT IN DESIGN: the half's floor colour, spec §4.5)
	padB: string,
	jellyTransparency: number, -- 1 - the design's boundary_jelly opacity
}

export type Kit = {
	def: any, -- World/Arenas ArenaDef
	design: any, -- Recipe.Design
	recipe: any, -- World/Arenas/Recipe
	palette: any, -- Art/Palette
	layout: any, -- WorldLayout.Arena (the gameplay frame)
	strings: any, -- Strings
	sL: number, -- the design's court scales (spec §1)
	sW: number,
	root: Model,
	floor: Folder,
	markings: Folder,
	rails: Folder,
	cover: Folder,
	decor: Folder,
	warnings: { string },
}

-- The court lines of a design (spec §4.5): sizes are design studs; positions follow the court.
export type CourtStyle = {
	line: string, -- line colour token
	sideWidth: number,
	endWidth: number,
	endA: string, -- end line colour, Side A (strawberry end) / Side B (mint end)
	endB: string,
	centreWidth: number,
	edgeWidth: number, -- the team lines on the dividers (the design's centre edges)
	zoneWidth: number, -- the spawn zone lines
	teamA: string, -- strawberry
	teamB: string, -- mint
	halfA: string, -- the half's floor colour (the spawn marker's inner disc)
	halfB: string,
	circle: "ring" | "dashes",
	padMarker: "ring" | "diamond",
}

-- Constants

local ATTR_ARENA_ID = "SD_ArenaId"
local ATTR_COVER_KIND = "SD_CoverKind"
local DIVIDER_GROUP = "SD_Divider" -- as ArenaBuilder.DIVIDER_GROUP (§5.3)
local DEFAULT_BARRIER_GROUP = "SD_Barrier" -- as ArenaBuilder.BARRIER_GROUP; WorldLayout.Arena.barrierGroup when set
local AUDIO_ZONE_TAG = "SD_AudioZone"
local ZONE_ORDER = { "HalfA", "Neutral", "HalfB", "Bounds" }
local HIDDEN_TOKEN = "Cream" -- invisible parts (Origin, zones, barriers) keep a colour for whoever shows them
local CORNER_APEX = Vector3.new(1, 0, -1) -- a CornerWedgePart's apex is over its (+X, -Z) base corner
-- Floor paint (spec §4.5): lines 0.04 thick on the floor (top 0.04), the centre circle above them, spawn markers on
-- the pad top (0.1) stacked 0.015 apart; all far below the lane check's Y 0.5.
local LINE_THICKNESS = 0.04
local CIRCLE_TOPS = { 0.06, 0.065 } -- alternate segments, so neighbours never share a plane
local MARKER_THICKNESS = 0.02
local MARKER_TOPS = { 0.12, 0.135, 0.15 }
local CIRCLE_SEGMENTS = 16 -- spec §4.5
local CIRCLE_DASHES = 12 -- sd/blox.js:35 has 24 dashes on r 10; at r 5.2 half as many keep its gaps
-- Design court numbers shared by all five (sd/arena.js:29-38, sd/blox.js:33-37, sd/arenas2.js:21-27).
local LINE_INSET = 1.5 -- design: side and end lines 1.5 inside the court edge (W / 2 - 1.5)
local CIRCLE_INNER = 10 -- design: centre circle ring(10, 11.2)
local CIRCLE_OUTER = 11.2
local DASH = Vector3.new(2.4, LINE_THICKNESS, 0.8) -- design: sd/blox.js:35 B(2.4, 0.04, 0.8)
local ZONE_AHEAD = 10 -- design: spawn zone lines 10 in front of the spawns (sd/arena.js:32, sd/arenas2.js:26)
local RING_OUTER = 2 * 2.6 -- design: spawn marker ring(1.9, 2.6) + dot ring(0, 0.8) (sd/arena.js:38)
local RING_INNER = 2 * 1.9
local RING_DOT = 2 * 0.8
local DIAMOND = 4.4 -- design: sd/blox.js:37 B(4.4, 0.06, 4.4) turned 45 deg
-- Boundary jelly (design: sd/arena.js:41, sd/blox.js:38, sd/arenas2.js:29: a plane (W - 2) x 9 at y 4.5 on the
-- centre line): spec §4.5 puts one on each divider (Z +-8), where players really stop.
local JELLY_HEIGHT = 9
local JELLY_THICKNESS = 0.1
-- Emblems (the design's extruded star / heart, sd/arenas2.js:13-14): symbol glyphs, not words.
local GLYPH_PIXELS_PER_STUD = 25
local GLYPH_LIGHT_INFLUENCE = 0.15 -- as Kit/Signs (§7.7)
local GLYPH_STROKE_PX = 3

-- `require` with a runtime-chosen ModuleScript (the injected Shared clone); the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local ArenaKit = {}
ArenaKit.STAR = "★" -- design: sd/arenas2.js:13 starGeo
ArenaKit.HEART = "♥" -- design: sd/arenas2.js:14 heartGeo
ArenaKit.CORNER_APEX = CORNER_APEX

-- Private

local function failure(warnings: { string }, message: string): BuildResult
	return { ok = false, root = nil, warnings = warnings, error = message }
end

local function loadShared(shared: Instance?, path: { string }): (any, string?)
	local label = "Shared/" .. table.concat(path, "/")
	local node: Instance? = shared
	for _, name in path do
		node = if node then node:FindFirstChild(name) else nil
	end
	if node == nil or not node:IsA("ModuleScript") then
		return nil, "ctx.Shared has no " .. label .. " module"
	end
	local ok, result = pcall(dynamicRequire, node)
	if not ok then
		return nil, "could not load " .. label .. ": " .. tostring(result)
	end
	return result, nil
end

type Deps = {
	palette: any,
	layout: any,
	arenas: any,
	recipe: any,
	strings: any,
}

local function loadDeps(shared: Instance?): (Deps?, string?)
	local loaded: { [string]: any } = {}
	for _, entry in
		{
			{ key = "palette", path = { "Art", "Palette" } },
			{ key = "layout", path = { "World", "WorldLayout" } },
			{ key = "arenas", path = { "World", "Arenas" } },
			{ key = "recipe", path = { "World", "Arenas", "Recipe" } },
			{ key = "strings", path = { "Strings" } },
		}
	do
		local module, problem = loadShared(shared, entry.path)
		if module == nil then
			return nil, problem
		end
		loaded[entry.key] = module
	end
	if type(loaded.layout.Arena) ~= "table" then
		return nil, "Shared/World/WorldLayout has no Arena table"
	end
	return {
		palette = loaded.palette,
		layout = loaded.layout.Arena,
		arenas = loaded.arenas,
		recipe = loaded.recipe,
		strings = loaded.strings,
	},
		nil
end

local function prims(flags: Flags?): Prims.Flags
	if flags == "marking" or flags == nil then
		return "decor"
	end
	return flags :: any
end

-- Sets a barrier's collision group; returns a warning when it could not be set (Verify then reports the part).
local function setGroup(part: BasePart, group: string): string?
	local ok, err = pcall(function()
		part.CollisionGroup = group
	end)
	if ok then
		return nil
	end
	return string.format("could not set %s.CollisionGroup = %q: %s", part.Name, group, tostring(err))
end

local function boxPart(k: Kit, parent: Instance, name: string, box: any, token: string, flags: Flags): Part
	return ArenaKit.part(k, parent, name, box.size, CFrame.new(box.position), token, flags)
end

local function buildBarriers(k: Kit, geometry: Folder)
	local barriers = Prims.folder("Barriers", geometry)
	local group = k.layout.barrierGroup or DEFAULT_BARRIER_GROUP
	for _, volume in k.layout.barriers do
		local problem = setGroup(boxPart(k, barriers, volume.name, volume, HIDDEN_TOKEN, "barrier"), group)
		if problem then
			table.insert(k.warnings, problem)
		end
	end
	for _, volume in k.layout.dividers do
		local problem = setGroup(boxPart(k, barriers, volume.name, volume, HIDDEN_TOKEN, "barrier"), DIVIDER_GROUP)
		if problem then
			table.insert(k.warnings, problem)
		end
	end
end

local function buildZones(k: Kit)
	local zones = Prims.folder("Zones", k.root)
	for _, name in ZONE_ORDER do
		local volume = k.layout.zones[name]
		if volume == nil then
			error(`WorldLayout.Arena.zones has no {name}`, 0)
		end
		boxPart(k, zones, name, volume, HIDDEN_TOKEN, "volume")
	end
	local spec = k.layout.audioZone
	local audio = boxPart(k, zones, "Audio", spec, HIDDEN_TOKEN, "volume")
	audio:AddTag(AUDIO_ZONE_TAG)
	audio:SetAttribute("ZoneId", spec.zoneId)
	audio:SetAttribute("Priority", spec.priority)
	audio:SetAttribute("MusicKey", spec.musicKey)
	audio:SetAttribute("AmbienceKey", spec.ambienceKey)
	audio:SetAttribute("MusicMul", spec.musicMul)
end

-- Pads exactly as ArenaBuilder's (rolled cylinders, LookVector = the facing), in the arena's colours.
local function buildSpawns(k: Kit, spec: Spec)
	local spawns = Prims.folder("Spawns", k.root)
	for _, side in { "A", "B" } do
		local token = if side == "A" then spec.padA else spec.padB
		local pad = k.layout.pads[side]
		local facing: Vector3 = pad.facing
		local yaw = math.atan2(-facing.X, -facing.Z) -- LookVector of a yaw θ is (-sin θ, 0, -cos θ)
		ArenaKit.part(
			k,
			spawns,
			pad.name,
			Vector3.new(pad.height, pad.diameter, pad.diameter),
			CFrame.new(pad.position) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.pi / 2),
			token,
			"decor",
			Enum.PartType.Cylinder
		)
	end
end

local function buildCover(k: Kit)
	for _, piece in k.def.cover do
		local frame = CFrame.new(piece.position) * CFrame.Angles(0, piece.yaw, 0)
		local model = Prims.model("Cover_" .. piece.name, nil, true, frame)
		model:SetAttribute(ATTR_COVER_KIND, piece.kind)
		local body: BasePart? = nil
		for _, spec in piece.parts do
			local shape = (Enum.PartType :: any)[spec.shape] :: Enum.PartType
			local material = if spec.material then (Enum.Material :: any)[spec.material] :: Enum.Material else nil
			local made =
				ArenaKit.part(k, model, spec.name, spec.size, frame * spec.cframe, spec.color, "solid", shape, material)
			body = body or made
		end
		if body == nil then
			error(`cover {piece.name} has no parts`, 0)
		end
		model.PrimaryPart = body
		model.Parent = k.cover
	end
end

local function buildDecorBase(k: Kit, spec: Spec)
	boxPart(k, k.decor, "Apron", { position = Vector3.new(0, -2.05, 0), size = k.def.apron }, spec.apron, "decor")
	local width = (k.design.W - 2) * k.sW -- design: the jelly plane is W - 2 wide
	for _, side in { "A", "B" } do
		local z = if side == "A" then -k.layout.neutralHalfZ else k.layout.neutralHalfZ
		local jelly = ArenaKit.part(
			k,
			k.decor,
			"BoundaryJelly" .. side,
			Vector3.new(width, JELLY_HEIGHT, JELLY_THICKNESS),
			CFrame.new(0, JELLY_HEIGHT / 2, z),
			"White",
			"decor"
		)
		jelly.Transparency = spec.jellyTransparency
		jelly.CastShadow = false
	end
end

-- Public: build

-- Builds the arena's tree (see the header). Never yields and never changes the place.
function ArenaKit.build(ctx: BuildContext, spec: Spec, art: (k: Kit) -> ()): BuildResult
	local warnings: { string } = {}
	local deps, depsError = loadDeps(ctx.Shared)
	if deps == nil then
		return failure(warnings, depsError or "Shared modules missing")
	end
	local def = deps.arenas.get(spec.arenaId)
	if def == nil or def.cover == nil or def.design == nil then
		return failure(warnings, `World/Arenas has no design arena {spec.arenaId}`)
	end
	if def.generatorId ~= spec.generatorId or def.templateName ~= spec.rootName then
		return failure(warnings, `World/Arenas names {spec.arenaId} {def.templateName} / {def.generatorId}`)
	end

	-- The root is destroyed with the scratch unless Main has taken it over (handedOver).
	local root = Instance.new("Model")
	root.Name = spec.rootName
	root.ModelStreamingMode = Enum.ModelStreamingMode.Default -- §5.3: the root is not Atomic
	local handedOver = false
	ctx.scratch:add(function()
		if not handedOver then
			root:Destroy()
		end
	end)

	local ok, err = pcall(function(): string?
		local sL, sW = deps.recipe.scales(def.design)
		local geometry = Prims.folder("Geometry", root)
		local k: Kit = {
			def = def,
			design = def.design,
			recipe = deps.recipe,
			palette = deps.palette,
			layout = deps.layout,
			strings = deps.strings,
			sL = sL,
			sW = sW,
			root = root,
			floor = Prims.folder("Floor", geometry),
			markings = Prims.folder("Markings", geometry),
			rails = Prims.folder("Rails", geometry),
			cover = Prims.folder("Cover", geometry),
			decor = nil :: any,
			warnings = warnings,
		}
		root.PrimaryPart = boxPart(k, root, "Origin", deps.layout.origin, HIDDEN_TOKEN, "volume")
		buildCover(k)
		buildBarriers(k, geometry)
		buildZones(k)
		buildSpawns(k, spec)
		k.decor = Prims.folder("Decor", root)
		buildDecorBase(k, spec)
		Prims.folder("Runtime", root)
		art(k)
		return nil
	end)
	if not ok then
		return failure(warnings, `{spec.rootName}: {tostring(err)}`)
	end

	root:SetAttribute(ATTR_ARENA_ID, spec.arenaId)
	Generated.mark(root, spec.generatorId, spec.version)
	handedOver = true
	return { ok = true, root = root, warnings = warnings, error = nil }
end

-- Public: parts

-- The Palette colour of `token`; a missing token is an error (the build fails with its name).
function ArenaKit.color(k: Kit, token: string): Color3
	local value = k.palette[token]
	if typeof(value) ~= "Color3" then
		error(`Palette has no colour {token}`, 0)
	end
	return value
end

-- An anchored Part (Kit/Prims) with the flags of `flags` (default "decor").
function ArenaKit.part(
	k: Kit,
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	token: string,
	flags: Flags?,
	shape: Enum.PartType?,
	material: Enum.Material?
): Part
	local part = Prims.part({
		name = name,
		size = size,
		cframe = cframe,
		color = ArenaKit.color(k, token),
		material = material,
		shape = shape,
		flags = prims(flags),
		shadow = if flags == "marking" then false else nil,
	})
	if flags == "marking" then
		part.CanQuery = true -- floor paint: projectiles hit it like the floor (Verify: Geometry is queryable)
	end
	part.Parent = parent
	return part
end

-- An upright cylinder (diameter across X and Z, `height` along Y) centred at `centre`.
function ArenaKit.disc(
	k: Kit,
	parent: Instance,
	name: string,
	diameter: number,
	height: number,
	centre: Vector3,
	token: string,
	flags: Flags?,
	material: Enum.Material?
): Part
	return ArenaKit.part(
		k,
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		Prims.upright(centre),
		token,
		flags,
		Enum.PartType.Cylinder,
		material
	)
end

-- A cylinder whose axis runs along `frame`'s X axis.
function ArenaKit.rod(
	k: Kit,
	parent: Instance,
	name: string,
	diameter: number,
	length: number,
	frame: CFrame,
	token: string,
	flags: Flags?,
	material: Enum.Material?
): Part
	return ArenaKit.part(
		k,
		parent,
		name,
		Vector3.new(length, diameter, diameter),
		frame,
		token,
		flags,
		Enum.PartType.Cylinder,
		material
	)
end

function ArenaKit.ball(
	k: Kit,
	parent: Instance,
	name: string,
	diameter: number,
	centre: Vector3,
	token: string,
	flags: Flags?
): Part
	return ArenaKit.part(k, parent, name, Vector3.one * diameter, CFrame.new(centre), token, flags, Enum.PartType.Ball)
end

-- A decor ellipsoid (a Part with a Sphere SpecialMesh, Kit/Prims.meshPart): the design's superellipsoids and pills.
function ArenaKit.ellipsoid(k: Kit, parent: Instance, name: string, size: Vector3, cframe: CFrame, token: string): Part
	return Prims.meshPart(name, Enum.MeshType.Sphere, size, cframe, ArenaKit.color(k, token), "decor", parent)
end

-- A decor wedge (Wedge SpecialMesh): full bottom face, tall edge at the back (+Z), slope facing front-up (as
-- Art/SquishyBuilder's W shape).
function ArenaKit.wedge(k: Kit, parent: Instance, name: string, size: Vector3, cframe: CFrame, token: string): Part
	return Prims.meshPart(name, Enum.MeshType.Wedge, size, cframe, ArenaKit.color(k, token), "decor", parent)
end

-- A decor isosceles triangle in `frame`'s XY plane (two wedge halves, as Art/SquishyBuilder's TRI): base `width` along
-- X at the frame's origin, apex `height` up its Y, `thickness` along Z.
function ArenaKit.triangle(
	k: Kit,
	parent: Instance,
	name: string,
	width: number,
	height: number,
	thickness: number,
	frame: CFrame,
	token: string
)
	local half = Vector3.new(thickness, height, width / 2)
	local centre = frame * CFrame.new(0, height / 2, 0)
	ArenaKit.wedge(
		k,
		parent,
		name .. "L",
		half,
		centre * CFrame.new(-width / 4, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
		token
	)
	ArenaKit.wedge(
		k,
		parent,
		name .. "R",
		half,
		centre * CFrame.new(width / 4, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
		token
	)
end

-- A decor square pyramid: base `side` x `side` (axis-aligned in `frame`), apex `height` above the base centre at
-- `frame`'s origin; four CornerWedgeParts whose apex corners meet on the axis.
function ArenaKit.pyramid(
	k: Kit,
	parent: Instance,
	name: string,
	side: number,
	height: number,
	frame: CFrame,
	token: string
)
	local size = Vector3.new(side / 2, height, side / 2)
	for index = 0, 3 do
		local turn = CFrame.Angles(0, index * math.pi / 2, 0)
		local apex = turn:VectorToWorldSpace(CORNER_APEX) -- the apex corner's direction after the turn
		local quadrant = Vector3.new(-math.sign(math.round(apex.X)), 0, -math.sign(math.round(apex.Z)))
		local wedge = Instance.new("CornerWedgePart")
		wedge.Name = `{name}{index + 1}`
		wedge.Size = size
		wedge.CFrame = frame * CFrame.new(quadrant.X * side / 4, height / 2, quadrant.Z * side / 4) * turn
		wedge.Color = ArenaKit.color(k, token)
		wedge.Material = Enum.Material.SmoothPlastic
		wedge.Anchored = true
		wedge.CastShadow = true
		wedge.CanCollide = false
		wedge.CanTouch = false
		wedge.CanQuery = false
		wedge.Parent = parent
	end
end

-- A non-Atomic Model for one decor prop, pivoted at `pivot`.
function ArenaKit.model(parent: Instance, name: string, pivot: CFrame): Model
	return Prims.model(name, parent, false, pivot)
end

-- A decor prop Model in Decor whose frame stands at game (x, z) on the floor, turned `yaw`: the design's group, whose
-- children keep their design-local coordinates (props stay at player scale, spec §4.1). Returns the Model and frame.
function ArenaKit.group(k: Kit, name: string, x: number, z: number, yaw: number): (Model, CFrame)
	local frame = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	return ArenaKit.model(k.decor, name, frame), frame
end

-- A decor block like the design's box(w, h, d, ..., x, y, z, ry) (sd/blox.js:22): its bottom at local y.
function ArenaKit.box(
	k: Kit,
	parent: Instance,
	frame: CFrame,
	name: string,
	size: Vector3,
	x: number,
	y: number,
	z: number,
	token: string,
	ry: number?
): Part
	return ArenaKit.part(
		k,
		parent,
		name,
		size,
		frame * CFrame.new(x, y + size.Y / 2, z) * CFrame.Angles(0, ry or 0, 0),
		token,
		"decor"
	)
end

-- Public: positions

-- The game (X, Z) of a design decor point (spec §4.6, World/Arenas/Recipe.decorAt).
function ArenaKit.at(k: Kit, x: number, z: number): (number, number)
	return k.recipe.decorAt(k.design, x, z)
end

-- The game yaw of a design yaw (spec §1: + 90 deg).
function ArenaKit.yaw(ry: number): number
	return ry + math.pi / 2
end

-- (a * b) mod 2^32 for 32-bit unsigned a and b, exact in doubles (16-bit halves).
local function mul32(a: number, b: number): number
	local aHigh, aLow = a // 65536, a % 65536
	local cross = (aHigh * (b % 65536) + aLow * (b // 65536)) % 65536
	return (cross * 65536 + aLow * (b % 65536)) % 4294967296
end

-- The design's seeded generator (sd/kit.js:5-8, mulberry32 on unsigned 32-bit values): the same stream as the design
-- for the same seed. Each call returns a number in [0, 1).
function ArenaKit.rng(seed: number): () -> number
	local state = seed % 4294967296
	return function(): number
		state = (state + 0x6D2B79F5) % 4294967296
		local t = mul32(bit32.bxor(state, bit32.rshift(state, 15)), bit32.bor(1, state))
		t = bit32.bxor((t + mul32(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(61, t))) % 4294967296, t)
		return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
	end
end

-- Public: text

-- A symbol glyph (ArenaKit.STAR / HEART) filling `face` of `part`, in `token` with an `outline` stroke (the design's
-- toon outline), at most `letterHeight` studs tall.
function ArenaKit.glyph(
	k: Kit,
	part: BasePart,
	face: Enum.NormalId,
	text: string,
	token: string,
	outline: string,
	letterHeight: number
): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Glyph" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = GLYPH_PIXELS_PER_STUD
	gui.LightInfluence = GLYPH_LIGHT_INFLUENCE
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	local label = Instance.new("TextLabel")
	label.Name = "Glyph"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = ArenaKit.color(k, token)
	label.TextStrokeTransparency = 1
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = math.floor(letterHeight * GLYPH_PIXELS_PER_STUD)
	constraint.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = ArenaKit.color(k, outline)
	stroke.Thickness = GLYPH_STROKE_PX
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = part
	return gui
end

-- A one-line sign on `face` of `part`: the Strings text of `textKey` (static: SD_Sign + SD_TextKey, so WorldBinder
-- re-applies it), through Kit/Signs, `letterHeight` studs tall.
function ArenaKit.sign(
	k: Kit,
	part: BasePart,
	face: Enum.NormalId,
	textKey: string,
	token: string,
	outline: string,
	letterHeight: number
): SurfaceGui
	local style = {
		panel = part.Color,
		frame = part.Color,
		text = ArenaKit.color(k, token),
		stroke = ArenaKit.color(k, outline),
	}
	local lines = { { name = "Text", textKey = textKey, live = false, letterHeight = letterHeight, font = "heading" } }
	return Signs.surface(k.strings, part, face, lines :: any, style)
end

-- Public: court

-- The design's court lines on the game court (spec §4.5), in Geometry/Markings: side and end lines inset as designed,
-- the centre line, the team lines on the dividers (Z +8 mint, -8 strawberry), the spawn zone lines 10 in front of the
-- pads, the centre circle (a 16-segment ring, or Pinewood's dashes) and one spawn marker on each pad.
function ArenaKit.court(k: Kit, style: CourtStyle)
	local layout = k.layout
	local markings = k.markings
	local sideX = layout.halfX - LINE_INSET * k.sW
	local endZ = layout.halfZ - LINE_INSET * k.sL
	local span = 2 * (sideX - style.sideWidth / 2) -- lines across the court stop at the side lines
	local y = LINE_THICKNESS / 2
	for _, sign in { -1, 1 } do
		local tag = if sign < 0 then "A" else "B"
		ArenaKit.part(
			k,
			markings,
			"SideLine" .. (if sign < 0 then "West" else "East"),
			Vector3.new(style.sideWidth, LINE_THICKNESS, 2 * endZ + style.endWidth),
			CFrame.new(sign * sideX, y, 0),
			style.line,
			"marking"
		)
		ArenaKit.part(
			k,
			markings,
			"EndLine" .. tag,
			Vector3.new(span, LINE_THICKNESS, style.endWidth),
			CFrame.new(0, y, sign * endZ),
			if sign < 0 then style.endA else style.endB,
			"marking"
		)
		ArenaKit.part(
			k,
			markings,
			"TeamLine" .. tag,
			Vector3.new(span, LINE_THICKNESS, style.edgeWidth),
			CFrame.new(0, y, sign * layout.neutralHalfZ),
			if sign < 0 then style.teamA else style.teamB,
			"marking"
		)
		ArenaKit.part(
			k,
			markings,
			"SpawnZoneLine" .. tag,
			Vector3.new(span, LINE_THICKNESS, style.zoneWidth),
			CFrame.new(0, y, sign * (layout.padDistance / 2 - ZONE_AHEAD)),
			style.line,
			"marking"
		)
	end
	ArenaKit.part(
		k,
		markings,
		"CentreLine",
		Vector3.new(span, LINE_THICKNESS, style.centreWidth),
		CFrame.new(0, y, 0),
		style.line,
		"marking"
	)

	-- Centre circle: design r 10 .. 11.2 scaled with the court along its length (spec §4.5).
	local inner, outer = CIRCLE_INNER * k.sL, CIRCLE_OUTER * k.sL
	if style.circle == "ring" then
		local width = outer - inner
		local length = 2 * outer * math.sin(math.pi / CIRCLE_SEGMENTS) + 0.02
		for index = 1, CIRCLE_SEGMENTS do
			local angle = (index - 0.5) * 2 * math.pi / CIRCLE_SEGMENTS
			local top = CIRCLE_TOPS[index % 2 + 1]
			ArenaKit.part(
				k,
				markings,
				string.format("Circle_%02d", index),
				Vector3.new(length, top, width),
				CFrame.Angles(0, angle, 0) * CFrame.new(0, top / 2, -(inner + outer) / 2),
				style.line,
				"marking"
			)
		end
	else
		for index = 1, CIRCLE_DASHES do
			local angle = (index - 1) * 2 * math.pi / CIRCLE_DASHES
			local top = CIRCLE_TOPS[index % 2 + 1]
			ArenaKit.part(
				k,
				markings,
				string.format("CircleDash_%02d", index),
				Vector3.new(DASH.X, top, DASH.Z),
				CFrame.Angles(0, angle, 0) * CFrame.new(0, top / 2, -inner),
				style.line,
				"marking"
			)
		end
	end

	-- Spawn markers on the pads (the design's 5 spawns per side are 5v5 only: one marker per pad).
	for _, side in { "A", "B" } do
		local pad = layout.pads[side]
		local team = if side == "A" then style.teamA else style.teamB
		local half = if side == "A" then style.halfA else style.halfB
		local base = Vector3.new(pad.position.X, 0, pad.position.Z)
		if style.padMarker == "diamond" then
			ArenaKit.part(
				k,
				markings,
				"SpawnMarker" .. side,
				Vector3.new(DIAMOND, MARKER_THICKNESS, DIAMOND),
				CFrame.new(base + Vector3.new(0, MARKER_TOPS[1] - MARKER_THICKNESS / 2, 0))
					* CFrame.Angles(0, math.pi / 4, 0),
				team,
				"marking"
			)
		else
			local rings = {
				{ diameter = RING_OUTER, color = team },
				{ diameter = RING_INNER, color = half },
				{ diameter = RING_DOT, color = team },
			}
			for index, ring in rings do
				ArenaKit.disc(
					k,
					markings,
					`SpawnMarker{side}_{index}`,
					ring.diameter,
					MARKER_THICKNESS,
					base + Vector3.new(0, MARKER_TOPS[index] - MARKER_THICKNESS / 2, 0),
					ring.color,
					"marking"
				)
			end
		end
	end
end

-- Two floor slabs out to the barrier walls (X +-38, Z +-54, top Y 0): Side A (Z < 0) and Side B in their half colours.
function ArenaKit.floorHalves(k: Kit, tokenA: string, tokenB: string, material: Enum.Material?)
	local halfX = k.layout.halfX + 2 -- the barrier walls (Bounds)
	local halfZ = k.layout.halfZ + 2
	for _, side in { "A", "B" } do
		local sign = if side == "A" then -1 else 1
		ArenaKit.part(
			k,
			k.floor,
			"Half" .. side,
			Vector3.new(2 * halfX, 4, halfZ),
			CFrame.new(0, -2, sign * halfZ / 2),
			if side == "A" then tokenA else tokenB,
			"solid",
			nil,
			material
		)
	end
end

return ArenaKit
