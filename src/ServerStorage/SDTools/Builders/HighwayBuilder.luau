--!strict
-- HighwayBuilder: builds the highway Workspace.SD_Highway (pens3 phase 12, 2026-10-17; work/pens3/PLAN.md "PHASE 12"):
-- the lobby design v6's launch deck, lane, distance markers, biome arches, ground and Golden Gates as parts, the world
-- phase 13's throws land on; since phase 12b (2026-10-18, the owner: "the biomes have to be themed too, like, not just
-- plain terrain and color changes") each biome's scenery too; since phase 13 (2026-10-18, the owner: "it should be a
-- general area where they walk up and everybody can throw") the deck has no launch spots, its top is one open throw
-- area (WorldLayout.Highway.throwArea), and the launch board has 3 last-throw rows and the server best (owner
-- 2026-10-15: "The launch gate board shows the last throws and the server best"; the server writes them, pens3
-- phase 13 HighwayService); since p13v4 (owner 2026-10-19: copy the TikTok duck throw, its "BUBBLE RINGS" and
-- BULLSEYE targets; work/pens3/p13v4/SPEC.md 3.5) each biome's 3 flight rings and 2 BULLSEYE pads
-- (WorldLayout.Highway.rings / pads), and every biome Persistent. Server only, Edit mode only (ServerStorage.SDTools);
-- called by Main's pipeline (target
-- "highway"), never at runtime. Contract (Generated.BuildContext / BuildResult): build(ctx) returns { ok, root,
-- warnings, error } with the new tree UNPARENTED and marked GeneratorId "highway"; it never parents anything into the
-- place. Relative requires, or modules of the injected ctx.Shared clone (never an absolute require).
--
-- Sources (v6, approved by the owner as the lobby source): `HK:n` = highway-kit.js line n (the lane pieces), `LK:n` =
-- lobby-kit.js (the deck pieces, and the geometry helpers box / cyl / cylX / cylZ / torY / rrect / slab, LK:20-38),
-- `L:n` = layout.json (where each piece stands), `K:n` = kit.json (sizes, materials, zones), `P3D:n` = "Squishy Lobby
-- 3D.html" (what the SurfaceGuis show), `CHK:n` = check/CHECK.md, PR3:36 (the Golden Gates at 8,500).
-- Data: the placement, the throw area, the board's rows and the biome looks are Shared World/WorldLayout.Highway (the
-- lane-local frame,
-- WorldLayout.highwayCFrame: d studs from the start line is z = -d); the biome starts and the Golden Gates are
-- Config.Economy.Highway (checked by Config/ValidateHighway first); colours Art/Palette (Highway*), text Strings
-- (highway.*); where the scenery stands, the rows of the sibling HighwayScenery (v6's L:488-1599 entries 1:1). The
-- pieces' own shapes are here, each number with its design line; "reading" marks what v6 leaves open.
--
-- Port (v6 is meshes, one per material per piece, K:4; this is parts): box(w, h, d, x, y0, z) a Block whose bottom is
-- y0; cyl an upright Cylinder; cylX / cylZ a Cylinder along X / Z; sph a Ball; torY(R, t) around a solid core a collar
-- (a Cylinder 2(R + t) wide and 2t tall, Kit/Props' rule); a torus arc Props.rods; a rounded-rectangle slab two crossed
-- Blocks and 4 corner Cylinders; the deck's trim ring 4 bars and 3 Blocks a corner; arrowShape (LK:39) a Block and 2
-- Wedges; the wings' flat shape (HK:9) 5 triangles of 2 Wedges; a lathe stacked Cylinders (lathe(): one between each
-- two given heights, the profile's radius at its middle); a scaled sphere and cloud() (HK:7) ellipsoids (a Sphere
-- SpecialMesh, Kit/Props.ellipsoid); a dodecahedron a Ball of its radius.
-- Readings: RainbowLane's 256 x 8 strip texture (K:413) is drawn as its 7 bands (HK:14: 9/64 of the lane each, the last
-- 10/64), so nothing needs uploading; the bands stop 0.1 short of the edges, under the glow strips (one face per
-- plane, Flicker_Test); the lathe tapers of the Golden Gates' pillars are left out (HK:90); 8 rods per torus arc.
-- Scenery readings (phase 12b, each at its builder): a lathe's cap shell (the hill's icing, the sundae's sauce) is the
-- top tiers in the cap's material; the gumdrop canopy is phase 10's (BaseService TREE: a Cylinder under an ellipsoid);
-- the lamp's swirl tori are Props.lollipop's stepped discs; the croissant's fat torus arc a row of Balls; the volcano's
-- crater rim a ring of Blocks; the cup's pearls (inside the opaque cup, invisible in v6 too) are left out.
--
-- Tree:
--   SD_Highway (Model, WorldPivot = WorldLayout.Highway.origin, marked SD_Generated / highway / VERSION)
--     Deck (Model, Persistent: K:7881-7883 Plaza and LaunchGate are persistent zones)
--       launch_platform_01 (+ the L:2 light), watch_steps_01..02, launch_gate_01 (the CANDY MEADOW banner, the launch
--       board SD_LaunchBoard with its 8 empty live lines, the gate_mascot slot), candy_fence_01..04
--     Biome_1_CM .. Biome_7_DH (Models, Biome = n, WorldPivot at the biome's start; K:7887 one zone per biome)
--       lane_tile_NN / rr_rainbow_lane_NN, lane_rail_NN, distance_marker_NN (Distance), biome_ground_NN,
--       biome_arch_NN (Scale), the scenery (HighwayScenery's rows, named by their v6 ids: lv_volcano_01 with the L:4
--       light), dh_golden_gates_01 (+ the L:5 light), p13v4 flight_ring_NN (Distance; 01..21) and flight_pad_NN
--       (Distance; 01..14): each an Atomic Model (K:7887). P13v4 [P]: every biome Model Persistent (the chase camera
--       flies up to 8,500 studs from the character; streamed-out biomes would show an empty sky).
--   Every placed piece is a Model with SD_Piece = its v6 piece, named and numbered as v6 names it (L:20-1599).
-- Rules: every part anchored and untouched; only the deck's v6 "walk" pieces (the platform, the watch steps)
--   collide: nobody stands anywhere else, so v6's "walk" lane and ground and its "block" gate, fences, rails, arches
--   and scenery are decor until a phase needs them (the lane is a squishy-only surface, K:1700; the rings and pads are
--   decor too: the server decides every ring hit and BULLSEYE, Shared/HighwayMath); parts under 2 studs
--   cast no shadow (the lobby's rule); every SurfaceGui at PixelsPerStud 25, hidden beyond 150 studs (K:7873); static
--   lines tagged SD_Sign with SD_TextKey (WorldBinder re-applies them), live lines neither.
-- Not built here (later phases): boosters, traps and reward bubbles (phases 15 and 17), the platform launchers, the
--   effects (fx_twinkle, the volcano's fx_smoke), the animations (BoardPop, MascotIdle; SpotSquish went with the
--   spots).

local Generated = require(script.Parent.Parent.Generated)
local Prims = require(script.Parent.Parent.Kit.Prims)
local Props = require(script.Parent.Parent.Kit.Props)
local HighwayScenery = require(script.Parent.HighwayScenery)

-- Types

type BuildContext = Generated.BuildContext
type BuildResult = Generated.BuildResult
type Flags = Prims.Flags
type Row = HighwayScenery.Row

type Deps = {
	Strings: any,
	Palette: any,
	Config: any,
	WorldLayout: any,
	SquishyBuilder: any,
	Format: any,
	ValidateHighway: any,
}

type State = {
	deps: Deps,
	H: any, -- WorldLayout.Highway
	A: any, -- WorldLayout.Attributes
	origin: CFrame,
	warnings: { string },
	counts: { [string]: number }, -- v6 piece -> how many are placed so far (their NN)
}

-- A text line on a SurfaceGui canvas (see line()).
type Line = {
	name: string,
	text: string,
	key: string?, -- a static line's Strings key (SD_Sign + SD_TextKey)
	x: number,
	y: number,
	width: number,
	px: number, -- the design's letter size in px at DESIGN_PPU
	color: Color3,
	stroke: Color3?,
}

-- Constants

local GENERATOR_ID = "highway"
local VERSION = 4 -- 1: phase 12, the deck and the lane; 2: phase 12b, the biome scenery; 3: phase 13, no spots, rows
-- 4: p13v4, the rings and BULLSEYE pads; biomes Persistent
local ROOT_NAME = "SD_Highway"
local DECK_NAME = "Deck"

local SMALL_PART = 2 -- the lobby's render rule: parts under 2 studs cast no shadow
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's X axis onto the frame's Y
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- a Cylinder's X axis onto the frame's -Z (its Right face looks front)
local TURNED = CFrame.Angles(0, math.pi, 0) -- L "rot": 180 (the gate, the markers, the arches, the Golden Gates)
local ARC_SEGMENTS = 8 -- reading: a torus arc as 8 rods (the lobby's donut arch has 6)
local ROD_OVERLAP = 1.06 -- Kit/Props: arc pieces overlap a little so the joints never gap

local GUI_PIXELS_PER_STUD = 25 -- K:7873
local GUI_MAX_DISTANCE = 150 -- K:7873: "hidden beyond 150 studs"
local GUI_LIGHT_INFLUENCE = 0.15 -- the lobby's signs (Kit/Signs)
local DESIGN_PPU = 40 -- P3D:221 canvasPlane: the design's px are 40 a stud
local STROKE_SHARE = 0.11 -- P3D:239: lineWidth 0.22 x size, centred on the outline, so half of it shows
local LINE_BOX = 1.25 -- a line's box, in letter heights (Kit/Signs)
local FONT = Enum.Font.FredokaOne -- P3D:237-238 "700 Fredoka" (Kit/Signs' heading font)

-- Pens3 phase 13: the board's LAST rows (reading: under v6's LAST THROW heading at y 0.33, one row each 0.17 of the
-- canvas, letters 30 design px so a row's box stays inside its step; buildBoard).
local ROW_TOP = 0.5
local ROW_STEP = 0.17
local ROW_PX = 30

-- P13v4 [P] the looks (Claude Design has not drawn them): a ring is WorldLayout.Highway.ringSegments glowing rods
-- (HighwayGlow, Neon); a pad is 3 flat discs on the lane's top, white-pink-white (radius padRadius, then 10 and 5;
-- thicker toward the middle so each shows over the one below). A ring per biome RINGS_PER_BIOME, pads PADS_PER_BIOME.
local LANE_TOP = 1 -- HighwayBuilder's lane tiles: y 0..1
local RING_TOKEN = "HighwayGlow"
local PAD_DISCS = {
	{ radius = 15, thickness = 0.2, token = "HighwayFrosting" },
	{ radius = 10, thickness = 0.3, token = "HighwayStrawPink" },
	{ radius = 5, thickness = 0.4, token = "HighwayFrosting" },
}
local RINGS_PER_BIOME = 3
local PADS_PER_BIOME = 2

local MASCOT_BLUEPRINT = "kitty_bread" -- K:985, :1000: "Diego's existing Kitty Bread model" (Art/SquishyBlueprints)
local MASCOT_WIDTH = 11 -- LK:175: scaled to 11 studs wide
local MASCOT_AT = Vector3.new(0, 50, 0.2) -- LK:173, gate-local: on top of the board's back (y 41..50)

-- K materials as Roblox materials (K:73 Gold "Reflectance 0.2", K:80 Glow "Neon", K:432 Marble, K:438 AngelWhite).
local MATERIALS: { [string]: Enum.Material } = {
	HighwayGlow = Enum.Material.Neon,
	HighwayMarble = Enum.Material.Marble,
}
local REFLECTANCE: { [string]: number } = { HighwayGold = 0.2, HighwayAngelWhite = 0.1 }

-- The scenery's v6 K materials by name (K:7-444 "hex" / "roblox"): its Palette token, Roblox material and shine. A
-- part's `token` may name one of these instead of a Palette token (look()).
local KIT: { [string]: { token: string, material: Enum.Material?, reflectance: number? } } = {
	Frosting = { token = "HighwayFrosting" }, -- K:7
	CandyGrass = { token = "HighwayCandyGrass" }, -- K:13
	Wafer = { token = "HighwayWafer" }, -- K:25
	PinkIcing = { token = "HighwayPinkIcing" }, -- K:31
	Lilac = { token = "HighwayLilac" }, -- K:55
	Berry = { token = "HighwayBerry" }, -- K:61
	Gold = { token = "HighwayGold", reflectance = 0.2 }, -- K:73 "SmoothPlastic, Reflectance 0.2"
	Glow = { token = "HighwayGlow", material = Enum.Material.Neon }, -- K:80 "Neon (no Light)"
	Crust = { token = "HighwayCrust" }, -- K:336
	StrawPink = { token = "HighwayStrawPink" }, -- K:348
	MilkTea = { token = "HighwayMilkTea" }, -- K:361
	Snow = { token = "HighwaySnow", material = Enum.Material.Snow }, -- K:374 "Snow"
	BerrySauce = { token = "HighwayBerrySauce", reflectance = 0.1 }, -- K:386 "SmoothPlastic, Reflectance 0.1"
	Basalt = { token = "HighwayBasalt", material = Enum.Material.Basalt }, -- K:392 "Basalt"
	LavaGlow = { token = "HighwayLavaGlow", material = Enum.Material.Neon }, -- K:398 "Neon"
	StarGold = { token = "HighwayStarGold", material = Enum.Material.Neon }, -- K:419 "Neon"
	Cloud = { token = "HighwayCloud" }, -- K:426
	Marble = { token = "HighwayMarble", material = Enum.Material.Marble }, -- K:432 "Marble"
	GoldCloud = { token = "HighwayGoldCloud" }, -- K:444
}

-- L:2 L1_launch on launch_platform/light_anchor (LK:163 (0, 7, 0)); L:4 L3_volcano on lv_volcano/light_anchor (HK:71
-- (0, 66, 0)); L:5 L4_heaven on dh_golden_gates/light_anchor (HK:96 (0, 45, -4)). No shadows (L:2, :4, :5).
local LIGHTS = {
	launch = { name = "L1_launch", token = "HighwayLightLaunch", brightness = 1.2, range = 22 },
	volcano = { name = "L3_volcano", token = "HighwayLightVolcano", brightness = 2, range = 60 },
	heaven = { name = "L4_heaven", token = "HighwayLightHeaven", brightness = 1.5, range = 50 },
}

-- HK:9 wing(s): the flat wing shape (x, y) x s; WING_TRIANGLES fan it from its one inward corner (5) (its 8th point
-- lies on the edge 6-0, so 5 triangles cover it).
local WING =
	{ { 0, 0 }, { 0.45, 0.2 }, { 0.85, 0.75 }, { 1, 1.5 }, { 0.7, 1.35 }, { 0.55, 1 }, { 0.3, 0.9 }, { 0.15, 0.45 } }
local WING_TRIANGLES = { { 6, 7, 1 }, { 6, 1, 2 }, { 6, 2, 3 }, { 6, 3, 4 }, { 6, 4, 5 } } -- 1-based into WING

-- `require` with a runtime-chosen ModuleScript (the injected Shared clone); the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local HighwayBuilder = {}
HighwayBuilder.GENERATOR_ID = GENERATOR_ID
HighwayBuilder.VERSION = VERSION
HighwayBuilder.ROOT_NAME = ROOT_NAME

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

-- Deps field -> the module's path in Shared.
local DEP_PATHS: { [string]: string } = {
	Strings = "Strings",
	Palette = "Art/Palette",
	Config = "Config",
	WorldLayout = "World/WorldLayout",
	SquishyBuilder = "Art/SquishyBuilder",
	Format = "Util/Format",
	ValidateHighway = "Config/ValidateHighway",
}

local function loadDeps(shared: Instance): (Deps?, string?)
	local loaded: { [string]: any } = {}
	for name, path in DEP_PATHS do
		local module, err = requirePath(shared, path)
		if module == nil then
			return nil, err
		end
		loaded[name] = module
	end
	return loaded :: any, nil
end

-- Why the data cannot be built (nil when it can): Config's problems, a biome count that differs from WorldLayout's
-- looks or HighwayScenery's, a biome edge off the 50-stud lane pieces or the 100-stud markers, a Strings key or Palette
-- token missing; p13v4: the rings (RINGS_PER_BIOME a biome, each inside its biome, in passing order, clear of the
-- lane's top) and the pads (PADS_PER_BIOME a biome, each with its radius inside its biome), their tokens.
local function dataProblem(deps: Deps): string?
	local problems = deps.ValidateHighway(deps.Config)
	if #problems > 0 then
		return "Config.Economy.Highway: " .. table.concat(problems, "; ")
	end
	local H, C = deps.WorldLayout.Highway, deps.Config.Economy.Highway
	if #H.biomes ~= #C.starts then
		return string.format("WorldLayout.Highway has %d biome looks for %d biomes", #H.biomes, #C.starts)
	end
	if #HighwayScenery.biomes ~= #C.starts then
		return string.format("HighwayScenery has the scenery of %d biomes for %d", #HighwayScenery.biomes, #C.starts)
	end
	for index, start in C.starts do
		if start % H.tileLength ~= 0 or start % H.markerEvery ~= 0 then
			return string.format("biome %d starts at %d, off the %d-stud lane pieces", index, start, H.markerEvery)
		end
	end
	if C.gatesAt % H.tileLength ~= 0 then
		return string.format("the Golden Gates at %d are off the %d-stud lane pieces", C.gatesAt, H.tileLength)
	end
	local keys = table.clone(H.textKeys)
	for _, biome in H.biomes do
		table.insert(keys, biome.nameKey)
	end
	for _, key in keys do
		if deps.Strings.resolve(key) == nil then
			return "Strings has no text for " .. key
		end
	end
	-- P13v4: the rings and the pads.
	local function inside(biome: any, low: number, high: number): boolean
		local start = if type(biome) == "number" then C.starts[biome] else nil
		return start ~= nil and low >= start and high < (C.starts[biome + 1] or C.gatesAt)
	end
	local rings, pads, last = {}, {}, -math.huge
	for index, ring in H.rings do
		if not inside(ring.biome, ring.d, ring.d) or ring.d <= last then
			return string.format("ring %d (d %s) is not inside its biome in passing order", index, tostring(ring.d))
		end
		if ring.y - H.ringRadius - H.ringTube <= LANE_TOP then
			return string.format("ring %d (d %d) does not clear the lane's top", index, ring.d)
		end
		last = ring.d
		rings[ring.biome] = (rings[ring.biome] or 0) + 1
	end
	for index, pad in H.pads do
		if not inside(pad.biome, pad.d - H.padRadius, pad.d + H.padRadius) then
			return string.format("pad %d (d %s) is not inside its biome", index, tostring(pad.d))
		end
		pads[pad.biome] = (pads[pad.biome] or 0) + 1
	end
	for index in C.starts do
		if rings[index] ~= RINGS_PER_BIOME or pads[index] ~= PADS_PER_BIOME then
			return string.format("biome %d needs %d rings and %d pads", index, RINGS_PER_BIOME, PADS_PER_BIOME)
		end
	end
	local tokens = { RING_TOKEN }
	for _, disc in PAD_DISCS do
		table.insert(tokens, disc.token)
	end
	for _, token in tokens do
		if typeof(deps.Palette[token]) ~= "Color3" then
			return "Art/Palette has no colour token " .. token
		end
	end
	return nil
end

local function color(state: State, token: string): Color3
	local value = state.deps.Palette[token]
	if typeof(value) ~= "Color3" then
		error(string.format("[SD][HighwayBuilder] Art/Palette has no colour token %s", tostring(token)), 0)
	end
	return value
end

-- A Palette token's or a KIT material's colour, Roblox material (nil: SmoothPlastic) and shine.
local function look(state: State, token: string): (Color3, Enum.Material?, number)
	local kit = KIT[token]
	if kit then
		return color(state, kit.token), kit.material, kit.reflectance or 0
	end
	return color(state, token), MATERIALS[token], REFLECTANCE[token] or 0
end

-- Private: parts in a piece's frame (LK:20-38 helpers) -------------------------------------------------------------

local function part(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	size: Vector3,
	cframe: CFrame,
	flags: Flags?,
	shape: Enum.PartType?
): Part
	local paint, material, shine = look(state, token)
	local made = Prims.part({
		name = name,
		size = size,
		cframe = cframe,
		color = paint,
		material = material,
		shape = shape,
		flags = flags or "decor",
		parent = parent,
	})
	made.Reflectance = shine
	return made
end

-- box(w, h, d, x, y0, z) (LK:20): a Block w x h x d, its bottom at y0, centred on (x, z) of the frame `f`.
local function box(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	f: CFrame,
	size: Vector3,
	x: number,
	y0: number,
	z: number,
	flags: Flags?
): Part
	return part(state, parent, name, token, size, f * CFrame.new(x, y0 + size.Y / 2, z), flags)
end

-- A Block of `size` centred on (x, y, z) of `f` (three.js BoxGeometry at a position).
local function block(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	f: CFrame,
	size: Vector3,
	x: number,
	y: number,
	z: number,
	flags: Flags?
): Part
	return part(state, parent, name, token, size, f * CFrame.new(x, y, z), flags)
end

-- cyl(r, h, x, y0, z) (LK:21): an upright Cylinder of radius r, its bottom at y0.
local function cyl(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	f: CFrame,
	r: number,
	h: number,
	x: number,
	y0: number,
	z: number
): Part
	local size = Vector3.new(h, 2 * r, 2 * r)
	return part(
		state,
		parent,
		name,
		token,
		size,
		f * CFrame.new(x, y0 + h / 2, z) * UPRIGHT,
		nil,
		Enum.PartType.Cylinder
	)
end

-- cylZ(r, len, x, y, z) (LK:23): a Cylinder along Z centred on (x, y, z); its Right face looks at the frame's front.
local function cylZ(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	f: CFrame,
	r: number,
	len: number,
	x: number,
	y: number,
	z: number
): Part
	local size = Vector3.new(len, 2 * r, 2 * r)
	return part(state, parent, name, token, size, f * CFrame.new(x, y, z) * ALONG_Z, nil, Enum.PartType.Cylinder)
end

-- cylX(r, len, x, y, z) (LK:22): a Cylinder along X centred on (x, y, z).
local function cylX(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	f: CFrame,
	r: number,
	len: number,
	x: number,
	y: number,
	z: number
): Part
	local size = Vector3.new(len, 2 * r, 2 * r)
	return part(state, parent, name, token, size, f * CFrame.new(x, y, z), nil, Enum.PartType.Cylinder)
end

-- sph(r, x, y, z) (LK:59): a Ball.
local function sph(state: State, parent: Instance, name: string, token: string, f: CFrame, r: number, at: Vector3): Part
	return part(state, parent, name, token, Vector3.one * 2 * r, f * CFrame.new(at), nil, Enum.PartType.Ball)
end

-- A scaled sphere: an ellipsoid of `size` centred on `at` in the frame `f` (Kit/Props.ellipsoid, a Sphere SpecialMesh).
local function ellipsoid(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	f: CFrame,
	size: Vector3,
	at: Vector3
): Part
	local paint, material, shine = look(state, token)
	local made = Props.ellipsoid(parent, name, size, f * CFrame.new(at), paint)
	made.Material = material or made.Material
	made.Reflectance = shine
	return made
end

-- cloud(spec) (HK:7): each [r, x, y, z, sy = 0.7] a sphere of radius r squashed to sy tall, an ellipsoid.
local function cloud(state: State, parent: Instance, name: string, token: string, f: CFrame, spec: { { number } })
	for _, s in spec do
		local r, sy = s[1], s[5] or 0.7
		ellipsoid(state, parent, name, token, f, Vector3.new(2 * r, 2 * r * sy, 2 * r), Vector3.new(s[2], s[3], s[4]))
	end
end

-- torY(R, t, x, y, z) (LK:24) around a solid core: a collar, a Cylinder 2(R + t) wide and 2t tall centred on (x, y, z).
local function collar(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	f: CFrame,
	R: number,
	t: number,
	x: number,
	y: number,
	z: number
): Part
	local size = Vector3.new(2 * t, 2 * (R + t), 2 * (R + t))
	return part(state, parent, name, token, size, f * CFrame.new(x, y, z) * UPRIGHT, nil, Enum.PartType.Cylinder)
end

-- lathe(points) (LK:25), the design's {r, y} profile, as stacked upright Cylinders: one between each two of `heights`
-- (rising), its radius the profile's at the tier's middle (on the profile's rising edges; flat and falling ones are
-- its top, bottom and crater).
local function lathe(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	f: CFrame,
	profile: { { number } },
	heights: { number }
)
	for index = 1, #heights - 1 do
		local y0, y1 = heights[index], heights[index + 1]
		local y = (y0 + y1) / 2
		local radius: number? = nil
		for k = 1, #profile - 1 do
			local a, b = profile[k], profile[k + 1]
			if radius == nil and b[2] > a[2] and y >= a[2] and y <= b[2] then
				radius = a[1] + (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2])
			end
		end
		assert(radius, string.format("[SD][HighwayBuilder] %s: the lathe has no edge at y %s", name, tostring(y)))
		cyl(state, parent, name, token, f, radius, y1 - y0, 0, y0, 0)
	end
end

-- slab(rrect(w, d, r), h, y0) (LK:26-33) centred on (0, z) of `f`: two crossed Blocks and a Cylinder in each corner.
-- `inset` pulls the crossed Blocks' inner faces in (the corners still cover the gap): two slabs rounded on the same
-- corner centres (the deck's top and skirt) then keep their hidden inner faces apart (Flicker_Test). Returns the long
-- Block (it carries a piece's attachments).
local function rrectSlab(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	f: CFrame,
	w: number,
	d: number,
	r: number,
	h: number,
	y0: number,
	z: number,
	flags: Flags?,
	inset: number?
): Part
	local c = f * CFrame.new(0, y0 + h / 2, z)
	local pull = 2 * (inset or 0)
	local main = part(state, parent, name, token, Vector3.new(w, h, d - 2 * r - pull), c, flags)
	part(state, parent, name, token, Vector3.new(w - 2 * r - pull, h, d), c, flags)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = c * CFrame.new(sx * (w / 2 - r), 0, sz * (d / 2 - r)) * UPRIGHT
			part(state, parent, name, token, Vector3.new(h, 2 * r, 2 * r), corner, flags, Enum.PartType.Cylinder)
		end
	end
	return main
end

-- Blocks along an arc of `radius` in the frame `c`'s XZ plane, `width` across and `height` tall, from angle `a0`
-- (radians from +X toward +Z) over `sweep`.
local function arcBlocks(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	c: CFrame,
	radius: number,
	width: number,
	height: number,
	a0: number,
	sweep: number,
	segments: number,
	flags: Flags?
)
	local step = sweep / segments
	local length = 2 * radius * math.sin(step / 2) * ROD_OVERLAP
	for index = 0, segments - 1 do
		local a = a0 + (index + 0.5) * step
		local at = c * CFrame.new(radius * math.cos(a), 0, radius * math.sin(a)) * CFrame.Angles(0, -a, 0)
		part(state, parent, name, token, Vector3.new(width, height, length), at, flags)
	end
end

-- A flat triangle a, b, c (world points) `thickness` thick as two WedgeParts (the usual right-triangle split: the
-- longest edge is cut at the foot of its height).
local function triangle(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	thickness: number
)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	for _, half in
		{
			{
				size = Vector3.new(thickness, height, math.abs(ab:Dot(back))),
				cf = CFrame.fromMatrix((a + b) / 2, right, up, back),
			},
			{
				size = Vector3.new(thickness, height, math.abs(ac:Dot(back))),
				cf = CFrame.fromMatrix((a + c) / 2, -right, up, -back),
			},
		}
	do
		local wedge = Prims.wedge(name, half.size, half.cf, color(state, token), "decor", parent)
		wedge.Reflectance = REFLECTANCE[token] or 0
	end
end

-- Props.rods with the token's material and shine.
local function rods(
	state: State,
	parent: Instance,
	name: string,
	token: string,
	radius: number,
	tube: number,
	frame: CFrame,
	arc: number
)
	for _, rod in Props.rods(parent, name, radius, tube, frame, color(state, token), ARC_SEGMENTS, arc) do
		rod.Material = MATERIALS[token] or rod.Material
		rod.Reflectance = REFLECTANCE[token] or 0
	end
end

-- A PointLight (no shadows) on an Attachment "light_anchor" of `host` at `at` (world).
local function light(state: State, host: BasePart, at: CFrame, spec: any)
	local attachment = Instance.new("Attachment")
	attachment.Name = "light_anchor"
	attachment.CFrame = host.CFrame:ToObjectSpace(at)
	local pointLight = Instance.new("PointLight")
	pointLight.Name = spec.name
	pointLight.Color = color(state, spec.token)
	pointLight.Brightness = spec.brightness
	pointLight.Range = spec.range
	pointLight.Shadows = false
	pointLight.Parent = attachment
	attachment.Parent = host
end

-- Private: SurfaceGuis (P3D:221-241 gui()) ----------------------------------------------------------------------

-- A SurfaceGui on `face` of `host` (that face `faceSize` studs) with a centred canvas `canvas` studs (the design's gui
-- plane); returns the canvas Frame.
local function canvasOn(
	host: BasePart,
	face: Enum.NormalId,
	faceSize: Vector2,
	canvas: Vector2,
	background: Color3?
): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = GUI_PIXELS_PER_STUD
	gui.MaxDistance = GUI_MAX_DISTANCE
	gui.LightInfluence = GUI_LIGHT_INFLUENCE
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local frame = Instance.new("Frame")
	frame.Name = "Canvas"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(canvas.X / faceSize.X, canvas.Y / faceSize.Y)
	frame.BackgroundColor3 = background or Color3.new(1, 1, 1)
	frame.BackgroundTransparency = if background then 0 else 1
	frame.BorderSizePixel = 0
	frame.Parent = gui
	gui.Parent = host
	return frame
end

-- A line centred at (x, y) shares of the canvas (P3D:237 text()), `width` share wide, letters the design's px, scaled
-- down to fit when longer (TextScaled under that cap: CHK:12's cut-off arch name fits).
local function line(canvas: Frame, canvasHeight: number, spec: Line): TextLabel
	local letterStuds = spec.px / DESIGN_PPU
	local letterPx = math.clamp(math.floor(letterStuds * GUI_PIXELS_PER_STUD + 0.5), 1, 100)
	local label = Instance.new("TextLabel")
	label.Name = spec.name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(spec.x, spec.y)
	label.Size = UDim2.fromScale(spec.width, math.min(1, LINE_BOX * letterStuds / canvasHeight))
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = FONT
	label.Text = spec.text
	label.TextColor3 = spec.color
	label.TextSize = letterPx
	label.TextScaled = true
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = letterPx
	constraint.MinTextSize = 1
	constraint.Parent = label
	if spec.stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = spec.stroke
		stroke.Thickness = math.max(1, math.floor(STROKE_SHARE * letterPx + 0.5))
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
	end
	if spec.key then
		label:AddTag("SD_Sign")
		label:SetAttribute("SD_TextKey", spec.key)
	end
	label.Parent = canvas
	return label
end

-- Private: pieces ------------------------------------------------------------------------------------------------

-- A new placed piece: a Model named as v6 numbers it (`<piece>_NN`, in build order, or v6's own `id`), SD_Piece =
-- `piece`.
local function newPiece(state: State, piece: string, atomic: boolean, id: string?): Model
	state.counts[piece] = (state.counts[piece] or 0) + 1
	local model = Prims.model(id or string.format("%s_%02d", piece, state.counts[piece]), nil, atomic)
	model:SetAttribute(state.A.Piece, piece)
	return model
end

-- Pivots `model` on `frame` (after its parts: an empty Model's pivot moves when parts arrive) and parents it.
local function place(model: Model, frame: CFrame, parent: Instance)
	model.WorldPivot = frame
	model.Parent = parent
end

-- launch_platform (LK:158-164, L:20): the 30 x 15 deck.
local function buildPlatform(state: State, deck: Instance)
	local f = state.origin * CFrame.new(state.H.deck.platform)
	local model = newPiece(state, "launch_platform", false)
	local top = rrectSlab(state, model, "deck_top", "HighwayBiscuit", f, 30, 15, 2, 2, 0, -1.25, "solid")
	rrectSlab(state, model, "deck_skirt", "HighwayPinkIcing", f, 30.4, 15.4, 2.2, 1.5, 0, -1.25, "solid", Prims.LAYER)
	-- deck_trim: the ring between rrect(30.3, 15.3, 2.1) and rrect(29.1, 14.1, 1.5), 0.3 tall from y 1.8 (both rrects
	-- round their corners on (±13.05, ±5.55), so the ring is 0.6 wide all round), and the step
	-- box(20, 1, 1.5, 0, 0, 7).
	local ring = f * CFrame.new(0, 1.95, -1.25)
	for _, sz in { -1, 1 } do
		block(state, model, "deck_trim", "HighwayFrosting", ring, Vector3.new(26.1, 0.3, 0.6), 0, 0, sz * 7.35, "solid")
		block(
			state,
			model,
			"deck_trim",
			"HighwayFrosting",
			ring,
			Vector3.new(0.6, 0.3, 11.1),
			sz * 14.85,
			0,
			0,
			"solid"
		)
	end
	for _, corner in { { 13.05, 5.55, 0 }, { -13.05, 5.55, 0.5 }, { -13.05, -5.55, 1 }, { 13.05, -5.55, 1.5 } } do
		local c = ring * CFrame.new(corner[1], 0, corner[2])
		arcBlocks(
			state,
			model,
			"deck_trim",
			"HighwayFrosting",
			c,
			1.8,
			0.6,
			0.3,
			corner[3] * math.pi,
			math.pi / 2,
			3,
			"solid"
		)
	end
	box(state, model, "deck_trim", "HighwayFrosting", f, Vector3.new(20, 1, 1.5), 0, 0, 7, "solid")
	light(state, top, f * CFrame.new(0, 7, 0), LIGHTS.launch) -- LK:163 light_anchor
	place(model, f, deck)
end

-- watch_steps (LK:177-181, L:31-32): step seats facing the launches.
local function buildWatchSteps(state: State, deck: Instance, spec: any)
	local f = state.origin * CFrame.new(spec.position) * CFrame.Angles(0, spec.yaw, 0)
	local model = newPiece(state, "watch_steps", false)
	box(state, model, "tier_1", "HighwayFrosting", f, Vector3.new(16, 1.5, 9), 0, 0, 0, "solid")
	box(state, model, "tier_2", "HighwayPinkIcing", f, Vector3.new(16, 1.5, 6), 0, 1.5, 1.5, "solid")
	box(state, model, "tier_3", "HighwayMintIcing", f, Vector3.new(16, 1.5, 3), 0, 3, 3, "solid")
	place(model, f, deck)
end

-- The launch board's SurfaceGui (P3D:281-292): its static lines and the empty live ones (WorldLayout.Highway.
-- boardSlots). Pens3 phase 13: the LAST column holds boardRows rows (Last1 on top, the newest), each the thrower's name
-- beside its distance on one line (a reading of v6's one LAST THROW: its ink name, its white distance with the ink
-- stroke, at row size); the SERVER BEST column keeps v6's two lines.
local function buildBoard(state: State, board: BasePart)
	local S = state.deps.Strings
	local canvas = canvasOn(board, Enum.NormalId.Front, Vector2.new(22, 7), Vector2.new(21, 6.4))
	local ink, white = color(state, "HighwayInk"), color(state, "HighwayWhite")
	local heading = color(state, "HighwayBoardHeading")
	local lines: { Line } = {
		{
			name = "Title",
			text = S.resolve("highway.board.title"),
			key = "highway.board.title",
			x = 0.5,
			y = 0.13,
			width = 1,
			px = 30,
			color = color(state, "HighwayBerry"),
		},
		{
			name = "LastHeading",
			text = S.resolve("highway.board.lastThrow"),
			key = "highway.board.lastThrow",
			x = 0.27,
			y = 0.33,
			width = 0.46,
			px = 24,
			color = heading,
		},
		{
			name = "BestHeading",
			text = S.resolve("highway.board.serverBest"),
			key = "highway.board.serverBest",
			x = 0.75,
			y = 0.33,
			width = 0.46,
			px = 24,
			color = heading,
		},
		{ name = "BestWho", text = "", x = 0.75, y = 0.55, width = 0.46, px = 34, color = ink },
		{
			name = "BestDistance",
			text = "",
			x = 0.75,
			y = 0.8,
			width = 0.46,
			px = 52,
			color = color(state, "HighwayLemon"),
			stroke = ink,
		},
	}
	for row = 1, state.H.boardRows do
		local y = ROW_TOP + (row - 1) * ROW_STEP
		table.insert(
			lines,
			{ name = `Last{row}Who`, text = "", x = 0.15, y = y, width = 0.26, px = ROW_PX, color = ink }
		)
		table.insert(lines, {
			name = `Last{row}Distance`,
			text = "",
			x = 0.39,
			y = y,
			width = 0.2,
			px = ROW_PX,
			color = white,
			stroke = ink,
		})
	end
	for _, spec in lines do
		line(canvas, 6.4, spec)
	end
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.AnchorPoint = Vector2.new(0.5, 0.5)
	divider.Position = UDim2.fromScale(0.5, 0.6)
	divider.Size = UDim2.fromScale(0.1 / 21, 0.64)
	divider.BackgroundColor3 = color(state, "HighwayBoardDivider")
	divider.BorderSizePixel = 0
	divider.Parent = canvas
end

-- How wide (along its own X) the visible parts of a model built at the origin are (LobbyBuilder's modelSize).
local function widthOf(model: Model): number
	local low, high = math.huge, -math.huge
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			local cf, half = descendant.CFrame, descendant.Size / 2
			local extent = math.abs(cf.XVector.X) * half.X
				+ math.abs(cf.YVector.X) * half.Y
				+ math.abs(cf.ZVector.X) * half.Z
			low, high = math.min(low, cf.Position.X - extent), math.max(high, cf.Position.X + extent)
		end
	end
	return if low == math.huge then 0 else high - low
end

-- The Kitty Bread mascot (LK:173-175): Diego's blueprint built anchored ("Viewport": no welds), 11 studs wide, standing
-- on the gate's top and facing the deck. When it cannot be built, an empty Model keeps the slot, with a warning.
local function buildMascot(state: State, gate: Model, g: CFrame)
	local build = state.deps.SquishyBuilder.build
	local ok, result = pcall(build, MASCOT_BLUEPRINT, "Viewport", 1)
	if ok and typeof(result) == "Instance" and result:IsA("Model") then
		local width = widthOf(result)
		result:Destroy() -- the measuring build: never print it after this
		ok, result = pcall(build, MASCOT_BLUEPRINT, "Viewport", MASCOT_WIDTH / math.max(width, 1e-3))
	end
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		table.insert(
			state.warnings,
			"gate_mascot: the Kitty Bread mascot could not be built, its slot is empty: " .. tostring(result)
		)
		Prims.model("gate_mascot", gate, false, g * CFrame.new(MASCOT_AT))
		return
	end
	local model = result :: Model
	local low = Prims.lowestY(model) -- built around its pivot (the Root) at the origin, facing -Z
	model:PivotTo(g * CFrame.new(MASCOT_AT - Vector3.new(0, if low == math.huge then 0 else low, 0)))
	model.Name = "gate_mascot"
	model.Parent = gate
end

-- launch_gate (LK:165-176, L:33): the start line, turned 180° so its banner and board look at the deck.
local function buildGate(state: State, deck: Instance)
	local g = state.origin * CFrame.new(state.H.deck.gate) * TURNED
	local model = newPiece(state, "launch_gate", false)
	for _, x in { -16, 16 } do
		cyl(state, model, "gate_legs", "HighwayFrosting", g, 1.75, 38, x, 0, 0)
		cyl(state, model, "gate_trim", "HighwayLemon", g, 2.3, 1.2, x, 0, 0)
		for y = 3, 35, 4 do
			collar(state, model, "leg_stripes", "HighwayPinkIcing", g, 1.8, 0.32, x, y, 0)
		end
	end
	for _, x in { -6, 6 } do
		cyl(state, model, "gate_legs", "HighwayFrosting", g, 0.12, 1.6, x, 36.4, 0)
	end
	box(state, model, "gate_trim", "HighwayLemon", g, Vector3.new(24, 9, 1), 0, 41, 0.2)
	box(state, model, "arch_beam", "HighwayLilac", g, Vector3.new(36, 3, 3.2), 0, 38, 0)
	local first = state.H.biomes[1]
	local banner = block(state, model, "biome_banner", "HighwayPinkIcing", g, Vector3.new(14, 3, 0.4), 0, 35, 0)
	local canvas = canvasOn(
		banner,
		Enum.NormalId.Front,
		Vector2.new(14, 3),
		Vector2.new(13.6, 2.6),
		color(state, "HighwaySignFace")
	)
	line(canvas, 2.6, {
		name = "Name",
		text = state.deps.Strings.resolve(first.nameKey),
		key = first.nameKey,
		x = 0.5,
		y = 0.55,
		width = 1,
		px = 70, -- P3D:279
		color = color(state, first.nameColor),
		stroke = color(state, "HighwayInk"),
	})
	local board = block(state, model, "board_screen", "HighwaySignFace", g, Vector3.new(22, 7, 0.3), 0, 45.5, -0.45)
	board:AddTag(state.deps.WorldLayout.Tags.LaunchBoard)
	buildBoard(state, board)
	buildMascot(state, model, g)
	place(model, g, deck)
end

-- candy_fence (LK:229-234, L:34-37): between the gate's legs.
local function buildFence(state: State, deck: Instance, x: number)
	local f = state.origin * CFrame.new(x, 0, 0)
	local model = newPiece(state, "candy_fence", false)
	for _, px in { -3.2, 3.2 } do
		cyl(state, model, "fence_posts", "HighwayFrosting", f, 0.3, 3, px, 0, 0)
		for _, y in { 0.5, 1.5, 2.5 } do
			collar(state, model, "fence_candy", "HighwayPinkIcing", f, 0.32, 0.08, px, y, 0)
		end
	end
	for _, y in { 1.2, 2.4 } do
		cylX(state, model, "fence_candy", "HighwayPinkIcing", f, 0.18, 6.4, 0, y, 0)
	end
	place(model, f, deck)
end

local function buildDeck(state: State, root: Instance)
	local deck = Prims.model(DECK_NAME, nil, false)
	deck.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	buildPlatform(state, deck)
	for _, spec in state.H.deck.watchSteps do
		buildWatchSteps(state, deck, spec)
	end
	buildGate(state, deck)
	for _, x in state.H.deck.fences do
		buildFence(state, deck, x)
	end
	place(deck, state.origin, root)
end

-- lane_tile (HK:20) or, in Rainbow Road, rr_rainbow_lane (HK:75), and its two lane_rail (HK:21, L:459-460) for the 50
-- studs from `d0`.
local function buildLane(state: State, zone: Instance, look: any, d0: number)
	local f = state.origin * CFrame.new(0, 0, -(d0 + state.H.tileLength / 2))
	local lane: Model
	if look.rainbow then
		lane = newPiece(state, "rr_rainbow_lane", true)
		-- The strip's 7 bands start at floor(i x 64 / 7) of its 64 px (HK:14) across the lane's 30 studs.
		for band = 1, 7 do
			local left = -15 + 30 * math.floor((band - 1) * 64 / 7) / 64
			local right = if band == 7 then 15 else -15 + 30 * math.floor(band * 64 / 7) / 64
			left, right = math.max(left, -14.9), math.min(right, 14.9) -- under the glow strips (reading, header)
			local token = "HighwayRainbow" .. band
			box(state, lane, "rainbow_lane", token, f, Vector3.new(right - left, 1, 50), (left + right) / 2, 0, 0)
		end
		for _, x in { -15.2, 15.2 } do
			box(state, lane, "lane_glow", "HighwayGlow", f, Vector3.new(0.6, 1.1, 50), x, 0, 0)
		end
	else
		lane = newPiece(state, "lane_tile", true)
		box(state, lane, "lane_top", look.laneTop, f, Vector3.new(26, 1, 50), 0, 0, 0)
		for _, x in { -14, 14 } do
			box(state, lane, "lane_edges", look.laneEdge, f, Vector3.new(2, 1.04, 50), x, 0, 0)
		end
		for z = -20, 20, 10 do
			box(state, lane, "lane_edges", look.laneEdge, f, Vector3.new(0.8, 1.06, 4), 0, 0, z)
		end
	end
	place(lane, f, zone)
	for _, x in { -14, 14 } do
		local r = state.origin * CFrame.new(x, 1.04, -(d0 + state.H.tileLength / 2))
		local rail = newPiece(state, "lane_rail", true)
		cylZ(state, rail, "rail", look.rail, r, 0.6, 50, 0, 1.2, 0)
		for z = -20, 20, 20 do
			box(state, rail, "rail", look.rail, r, Vector3.new(0.5, 1, 0.5), 0, 0, z)
		end
		place(rail, r, zone)
	end
end

-- distance_marker (HK:22, L:476): `d` studs out at x 19, turned to face back up the lane; its face shows the distance
-- and "studs" (P3D:275).
local function buildMarker(state: State, zone: Instance, look: any, d: number)
	local H = state.H
	local f = state.origin * CFrame.new(H.markerX, if look.sky then H.skyLift else 0, -d) * TURNED
	local model = newPiece(state, "distance_marker", true)
	cyl(state, model, "marker_post", "HighwayFrosting", f, 0.35, 7, 0, 0, 0)
	cylZ(state, model, "marker_board", look.marker, f, 1.8, 0.4, 0, 7.6, 0.1)
	local face = cylZ(state, model, "marker_face", "HighwaySignFace", f, 1.5, 0.42, 0, 7.6, -0.02)
	local canvas = canvasOn(face, Enum.NormalId.Right, Vector2.new(3, 3), Vector2.new(2.8, 2.8))
	local S = state.deps.Strings
	line(canvas, 2.8, {
		name = "Distance",
		-- shortcut: Format.coins groups digits like the design's toLocaleString below 100,000 (markers stop at 8,400);
		-- phase 13's Format.distance can take over.
		text = S.format(S.resolve("highway.marker.distance") :: string, { distance = state.deps.Format.coins(d) }),
		x = 0.5,
		y = 0.47,
		width = 1,
		px = if d >= 1000 then 30 else 40, -- P3D:275
		color = color(state, "HighwayInk"),
	})
	line(canvas, 2.8, {
		name = "Unit",
		text = S.resolve("highway.marker.unit"),
		key = "highway.marker.unit",
		x = 0.5,
		y = 0.74,
		width = 1,
		px = 15,
		color = color(state, "HighwayMarkerUnit"),
	})
	model:SetAttribute(state.A.Distance, d)
	place(model, f, zone)
end

-- biome_arch (HK:23-27, L:533 ...): at the biome's start, turned to face the deck, scaled per biome (K:3136 archScale).
local function buildArch(state: State, zone: Instance, look: any, d: number)
	local s = look.arch.scale
	local f = state.origin * CFrame.new(0, if look.sky then state.H.skyLift else 0, -d) * TURNED
	local model = newPiece(state, "biome_arch", true)
	local main, trim = look.arch.main, look.arch.trim
	for _, x in { -18, 18 } do
		box(state, model, "arch_legs", main, f, Vector3.new(3, 22, 3) * s, x * s, 0, 0)
		sph(state, model, "arch_trim", trim, f, 1.8 * s, Vector3.new(x, 27.2, 0) * s)
		box(state, model, "arch_trim", trim, f, Vector3.new(3.6, 1, 3.6) * s, x * s, 0, 0)
	end
	box(state, model, "arch_legs", main, f, Vector3.new(40, 4, 3) * s, 0, 22 * s, 0)
	box(state, model, "arch_trim", trim, f, Vector3.new(25.4, 6.2, 0.4) * s, 0, 26.2 * s, 0.4 * s)
	local name = block(state, model, "arch_name", "HighwaySignFace", f, Vector3.new(24, 5, 0.5) * s, 0, 29.3 * s, 0)
	local canvas = canvasOn(name, Enum.NormalId.Front, Vector2.new(24, 5) * s, Vector2.new(23.4, 4.4) * s)
	line(canvas, 4.4 * s, {
		name = "Name",
		text = state.deps.Strings.resolve(look.nameKey),
		key = look.nameKey,
		x = 0.5,
		y = 0.55,
		width = 1,
		px = 110 * s, -- P3D:274
		color = color(state, look.nameColor),
		stroke = color(state, "HighwayInk"),
	})
	model:SetAttribute("Scale", s)
	place(model, f, zone)
end

-- biome_ground (HK:28, L:478 ...): a 400 x 100 slab whose top is 0.1 under the lane's foot, from `d0`.
local function buildGround(state: State, zone: Instance, look: any, d0: number)
	local f = state.origin * CFrame.new(0, -2.1, -(d0 + 50))
	local model = newPiece(state, "biome_ground", true)
	box(state, model, "ground", look.ground, f, Vector3.new(400, 2, 100), 0, 0, 0)
	place(model, f, zone)
end

-- dh_golden_gates (HK:89-97, L:1597): the highway's end at Config.Economy.Highway.gatesAt (PR3:36), 1 up, turned.
local function buildGoldenGates(state: State, zone: Instance, d: number)
	local f = state.origin * CFrame.new(0, state.H.skyLift, -d) * TURNED
	local model = newPiece(state, "dh_golden_gates", true)
	-- gates_pillars: the lathe [[0,0],[3.6,0],[3.6,1.6],[2.8,2.2],[2.6,38],[3.4,39],[3.4,40.5],[0,40.5]] at x ±16: its
	-- foot, its shaft (radius 2.7, the mean of 2.8 and 2.6) and its top.
	for _, x in { -16, 16 } do
		cyl(state, model, "gates_pillars", "HighwayMarble", f, 3.6, 1.6, x, 0, 0)
		cyl(state, model, "gates_pillars", "HighwayMarble", f, 2.7, 37.4, x, 1.6, 0)
		cyl(state, model, "gates_pillars", "HighwayMarble", f, 3.4, 1.5, x, 39, 0)
	end
	rods(state, model, "gates_gold", "HighwayGold", 16, 1.2, f * CFrame.new(0, 40.5, 0), math.pi)
	local bar = box(state, model, "gates_gold", "HighwayGold", f, Vector3.new(32, 1.2, 1.2), 0, 30, 0)
	for index = 0, 8 do
		box(state, model, "gate_bars", "HighwayGold", f, Vector3.new(0.6, 30, 0.6), -12 + index * 3, 0, 0)
	end
	-- gates_wings: ext(wing(10), 0.6) mirrored, moved (±5, 46, 0): its middle plane z 0.3.
	for _, s in { -1, 1 } do
		local points: { Vector3 } = {}
		for _, p in WING do
			table.insert(points, (f * CFrame.new(s * (p[1] * 10 + 5), p[2] * 10 + 46, 0.3)).Position)
		end
		for _, tri in WING_TRIANGLES do
			triangle(
				state,
				model,
				"gates_wings",
				"HighwayAngelWhite",
				points[tri[1]],
				points[tri[2]],
				points[tri[3]],
				0.6
			)
		end
	end
	rods(
		state,
		model,
		"gates_halo",
		"HighwayGlow",
		5,
		0.5,
		f * CFrame.new(0, 60, 0) * CFrame.Angles(math.pi / 2, 0, 0),
		2 * math.pi
	)
	light(state, bar, f * CFrame.new(0, 45, -4), LIGHTS.heaven) -- HK:96 light_anchor
	place(model, f, zone)
end

-- Private: the biome scenery (pens3 phase 12b; where each piece stands: HighwayScenery) -------------------------------
-- Each builder makes a v6 piece's parts in its frame `f` (bottom centre, front -Z), named as K names them, in K's
-- materials (KIT) or the row's tint.

-- gumdrop_tree (LK:235-239, K:1253; Candy Meadow reuses the lobby's, HK:30): the trunk, its 3 striped tori as collars,
-- the canopy in the row's GumdropTint read as phase 10 reads it (BaseService TREE): a Cylinder r 3 from 4.6 to 6 under
-- an ellipsoid 6 x 4.2 x 6 from 4.6 to 8.8 (the lathe's r 2.7 at 7.3 and 2 at 8.2; the ellipsoid has 2.9 and 2.1).
local function gumdropTree(state: State, model: Model, f: CFrame, row: Row)
	local tint = row.tint or "HighwayPinkIcing" -- K:123 GumdropTint's own colour
	cyl(state, model, "trunk", "Frosting", f, 0.6, 5, 0, 0, 0)
	for _, y in { 1.2, 2.4, 3.6 } do
		collar(state, model, "trunk_stripes", "PinkIcing", f, 0.64, 0.14, 0, y, 0)
	end
	cyl(state, model, "canopy", tint, f, 3, 1.4, 0, 4.6, 0)
	ellipsoid(state, model, "canopy", tint, f, Vector3.new(6, 4.2, 6), Vector3.new(0, 6.7, 0))
end

-- lollipop_lamp (LK:240-244, K:1283): the pole, the Neon candy disc facing the front and its swirl, 2 tori on the
-- candy's front (R 1, tube 0.18; R 0.45, tube 0.15) read as Props.lollipop reads swirl rings: discs stepped LAYER out
-- of the candy's face, each ring pink out to R + tube with the candy's Glow again inside R - tube.
local LAMP_SWIRL = {
	{ name = "lamp_swirl", token = "PinkIcing", r = 1.18 },
	{ name = "lamp_candy", token = "Glow", r = 0.82 },
	{ name = "lamp_swirl", token = "PinkIcing", r = 0.6 },
	{ name = "lamp_candy", token = "Glow", r = 0.3 },
}
local function lollipopLamp(state: State, model: Model, f: CFrame, _row: Row)
	cyl(state, model, "lamp_pole", "Frosting", f, 0.35, 8.2, 0, 0, 0)
	cylZ(state, model, "lamp_candy", "Glow", f, 1.6, 0.6, 0, 9.2, 0)
	for index, disc in LAMP_SWIRL do
		local z = -0.3 - (index - 0.5) * Prims.LAYER -- the candy's front face is z -0.3
		cylZ(state, model, disc.name, disc.token, f, disc.r, Prims.LAYER, 0, 9.2, z)
	end
end

-- candy_hill (LK:245-248, K:1313): the hill lathe in its 5 tiers, the 2 above its icing's lower edge (LK:247: y 11.73,
-- read at the tier line 11.5) in the icing's Frosting: the icing shell, 0.3 over the top, is read as the hill's top.
local HILL = { { 0, 0 }, { 20, 0 }, { 18, 3 }, { 15, 7.5 }, { 10.5, 11.5 }, { 6, 14 }, { 0, 15 } } -- LK:246
local function candyHill(state: State, model: Model, f: CFrame, _row: Row)
	lathe(state, model, "hill_body", "CandyGrass", f, HILL, { 0, 3, 7.5, 11.5 })
	lathe(state, model, "hill_icing", "Frosting", f, HILL, { 11.5, 14, 15 })
end

-- bt_bread_house (HK:43-46, K:2044): the 16 x 8 x 12 loaf house, its half-round roof (HK:44: a half Cylinder r 6 along
-- X on the walls; here the whole Cylinder, its lower half inside the walls) and its chimney; the door, 2 windows and
-- the eave band in Frosting.
local function breadHouse(state: State, model: Model, f: CFrame, _row: Row)
	box(state, model, "house_crust", "Crust", f, Vector3.new(16, 8, 12), 0, 0, 0)
	cylX(state, model, "house_crust", "Crust", f, 6, 16, 0, 8, 0)
	box(state, model, "house_crust", "Crust", f, Vector3.new(1.6, 4, 1.6), 4.5, 11, 2)
	box(state, model, "house_trim", "Frosting", f, Vector3.new(3, 5, 0.3), 0, 0, -6.1)
	for _, x in { -5, 5 } do
		box(state, model, "house_trim", "Frosting", f, Vector3.new(2.6, 2.6, 0.3), x, 3.5, -6.1)
	end
	box(state, model, "house_trim", "Frosting", f, Vector3.new(16.4, 0.6, 12.4), 0, 7.7, 0)
end

-- bt_croissant_hill (HK:47, K:2070): TorusGeometry(14, 6.5, arc 2.6) laid flat, turned 90° + 1.3 rad, its middle 2.5
-- up (half sunk in the ground), read as 7 Balls of the tube's 13 studs along its arc, the end ones half a tube radius
-- in from the cut ends so the horns reach about where v6's do (34.0 x 27.3 across, K: 34.6 x 26).
local CROISSANT_BALLS = 7
local function croissantHill(state: State, model: Model, f: CFrame, _row: Row)
	local c = f * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, math.pi / 2 + 1.3, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	local inset = 0.5 * 6.5 / 14
	for k = 0, CROISSANT_BALLS - 1 do
		local a = inset + (2.6 - 2 * inset) * k / (CROISSANT_BALLS - 1)
		sph(state, model, "croissant", "Wafer", c, 6.5, Vector3.new(14 * math.cos(a), 14 * math.sin(a), 0))
	end
end

-- bl_cup_island (HK:52-57, K:2176): the milk-tea cup (lathe r 7 to 9 over 24) in 4 tiers, its dome lid (a half sphere
-- r 9.3 squashed to 0.45: the whole ellipsoid, its lower half inside the cup's top) and the straw leaning 0.3 rad. Its
-- 5 pearls (HK:56: r 1.4 at y 1.4, at most 6.1 from the axis) lie inside the opaque cup (r 7): unseen in v6 too, not
-- built.
local CUP = { { 0, 0 }, { 7, 0 }, { 9, 24 }, { 0, 24 } } -- HK:53
local function cupIsland(state: State, model: Model, f: CFrame, _row: Row)
	lathe(state, model, "cup", "MilkTea", f, CUP, { 0, 6, 12, 18, 24 })
	ellipsoid(state, model, "cup_lid", "Frosting", f, Vector3.new(18.6, 2 * 9.3 * 0.45, 18.6), Vector3.new(0, 24, 0))
	local straw = f * CFrame.new(2.2, 30, 0) * CFrame.Angles(0, 0, 0.3) * UPRIGHT
	part(state, model, "cup_straw", "StrawPink", Vector3.new(18, 1.8, 1.8), straw, nil, Enum.PartType.Cylinder)
end

-- fd_popsicle (HK:63, K:2328): the ice pop, ext(rrect(4, 8, 1.8), 1.5) standing from y 3 to 11, as the rounded slab
-- turned upright (rrectSlab in a frame whose Y is the pop's thickness), in the row's PopsicleTint; its stick.
local function popsicle(state: State, model: Model, f: CFrame, row: Row)
	local upright = f * CFrame.new(0, 7, 0) * CFrame.Angles(math.pi / 2, 0, 0)
	rrectSlab(state, model, "popsicle", row.tint or "HighwayPinkIcing", upright, 4, 8, 1.8, 1.5, -0.75, 0) -- K:297
	box(state, model, "popsicle_stick", "Wafer", f, Vector3.new(0.7, 3.4, 0.35), 0, 0, 0)
end

-- fd_sundae_peak (HK:62, K:2298): the Snow peak lathe in 9 tiers of at most 6 studs, the 4 above the berry sauce's
-- lower edge (HK:62: y 28.5) in BerrySauce (the sauce shell, 0.25 over the top, read as the peak's top), the cherry on
-- top.
local PEAK = { { 0, 0 }, { 30, 0 }, { 24, 10 }, { 16, 22 }, { 9, 32 }, { 3, 38 }, { 0, 39 } } -- HK:62
local function sundaePeak(state: State, model: Model, f: CFrame, _row: Row)
	lathe(state, model, "peak", "Snow", f, PEAK, { 0, 5, 10, 16, 22, 28.5 })
	lathe(state, model, "peak_sauce", "BerrySauce", f, PEAK, { 28.5, 32, 35, 38, 39 })
	sph(state, model, "peak_cherry", "Berry", f, 2.4, Vector3.new(0, 41, 0))
end

-- lv_basalt_rock (HK:73, K:2475): 3 dodecahedra of Basalt, each a Ball of its radius.
local function basaltRock(state: State, model: Model, f: CFrame, _row: Row)
	sph(state, model, "rocks", "Basalt", f, 3, Vector3.new(0, 2.4, 0))
	sph(state, model, "rocks", "Basalt", f, 2, Vector3.new(3.2, 1.5, 1))
	sph(state, model, "rocks", "Basalt", f, 1.5, Vector3.new(-2.8, 1.1, -1.2))
end

-- lv_volcano (HK:68-72, K:2446): the 66-tall Basalt lathe, its slope in 12 tiers of 5 to 6 studs up to the crater
-- floor (y 61), its crater rim (HK:69: out r 16 at 62 to r 12 at 66, in to r 10 at 63) a ring of 8 Blocks from 61 to
-- 66 (r 11 to 14.5); the LavaGlow lake (HK:70 cyl(10.2, 0.4) at 61) only where v6 shows it: HK:69's crater floor is a
-- funnel (y 61 + 0.2 r) over the lake's top (61.4) beyond r 2, so here it is that r 2 middle on the flat floor at 61;
-- the 5 lava streams down the slope (2.4 x 0.5 x 50 boxes tilted 0.967 rad, 1.26 rad apart) and the biome's light on
-- its light_anchor (L:4). fx_smoke comes with the effects.
local VOLCANO = { { 0, 0 }, { 60, 0 }, { 45, 20 }, { 28, 45 }, { 16, 62 }, { 12, 66 }, { 10, 63 }, { 0, 61 } } -- HK:69
local function volcano(state: State, model: Model, f: CFrame, _row: Row)
	lathe(state, model, "volcano", "Basalt", f, VOLCANO, { 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 61 })
	-- The rim's Blocks are as long as the outer octagon's sides (r 14.5): arcBlocks' centre-line length would leave a
	-- V notch between each two on a ring this thick.
	local rimLength = 2 * 14.5 * math.tan(math.pi / ARC_SEGMENTS)
	for index = 0, ARC_SEGMENTS - 1 do
		local a = (index + 0.5) * 2 * math.pi / ARC_SEGMENTS
		local at = f * CFrame.new(12.75 * math.cos(a), 63.5, 12.75 * math.sin(a)) * CFrame.Angles(0, -a, 0)
		part(state, model, "volcano", "Basalt", Vector3.new(3.5, 5, rimLength), at)
	end
	local lake = cyl(state, model, "volcano_lava", "LavaGlow", f, 2, 0.4, 0, 61, 0)
	for index = 0, 4 do
		local a = index * 1.26 + 0.4
		local stream = f
			* CFrame.new(math.sin(a) * 31, 41, math.cos(a) * 31)
			* CFrame.Angles(0, a, 0)
			* CFrame.Angles(0.967, 0, 0)
		part(state, model, "volcano_lava", "LavaGlow", Vector3.new(2.4, 0.5, 50), stream)
	end
	light(state, lake, f * CFrame.new(0, 66, 0), LIGHTS.volcano)
end

-- rr_cloud_bank (HK:79, K:2608): 6 Cloud spheres squashed to 0.7 (cloud()).
local CLOUD_BANK =
	{ { 10, 0, 6, 0 }, { 8, 9, 4, 2 }, { 7, -9, 3.5, 1 }, { 6, 3, 9, -3 }, { 6, -4, 8, 4 }, { 5, 14, 2.5, -3 } }
local function cloudBank(state: State, model: Model, f: CFrame, _row: Row)
	cloud(state, model, "cloud_bank", "Cloud", f, CLOUD_BANK)
end

-- rr_planet (HK:80, K:2630): the Lilac planet (r 18, 18 up) and its StarGold ring (TorusGeometry(28, 1.4) flattened to
-- 0.12 across: a flat band 2.8 wide and 0.336 thick) tilted 0.35 rad past flat, read as a ring of 16 Blocks.
local PLANET_RING_BLOCKS = 16
local function planet(state: State, model: Model, f: CFrame, _row: Row)
	sph(state, model, "planet", "Lilac", f, 18, Vector3.new(0, 18, 0))
	local ring, thick = f * CFrame.new(0, 18, 0) * CFrame.Angles(0.35, 0, 0), 2 * 1.4 * 0.12
	arcBlocks(state, model, "planet_ring", "StarGold", ring, 28, 2.8, thick, 0, 2 * math.pi, PLANET_RING_BLOCKS)
end

-- dh_marble_pillar (HK:98, K:2797): the Marble lathe read as the Golden Gates' pillars are (its 2 short tapers left
-- out: the foot r 2.2 to 1, the shaft r 1.45 to 13.5, the top r 2 to 14.4) and its gold torus (r 1.5, tube 0.22 at
-- 13.2) a collar.
local PILLAR = { { 0, 0 }, { 2.2, 0 }, { 2.2, 1 }, { 1.5, 1.5 }, { 1.4, 13 }, { 2, 13.5 }, { 2, 14.4 }, { 0, 14.4 } }
local function marblePillar(state: State, model: Model, f: CFrame, _row: Row)
	lathe(state, model, "pillar", "Marble", f, PILLAR, { 0, 1, 13.5, 14.4 })
	collar(state, model, "pillar_gold", "Gold", f, 1.5, 0.22, 0, 13.2, 0)
end

-- dh_gold_cloud (HK:99, K:2823): 5 GoldCloud spheres squashed to 0.45 / 0.5 (cloud()).
local GOLD_CLOUD = {
	{ 12, 0, 4, 0, 0.45 },
	{ 9, 12, 3, 3, 0.45 },
	{ 9, -12, 3, -2, 0.45 },
	{ 7, 4, 6, -8, 0.5 },
	{ 7, -5, 5.5, 8, 0.5 },
}
local function goldCloud(state: State, model: Model, f: CFrame, _row: Row)
	cloud(state, model, "gold_cloud", "GoldCloud", f, GOLD_CLOUD)
end

-- v6 kind -> its builder.
local SCENERY: { [string]: (State, Model, CFrame, Row) -> () } = {
	gumdrop_tree = gumdropTree,
	lollipop_lamp = lollipopLamp,
	candy_hill = candyHill,
	bt_bread_house = breadHouse,
	bt_croissant_hill = croissantHill,
	bl_cup_island = cupIsland,
	fd_popsicle = popsicle,
	fd_sundae_peak = sundaePeak,
	lv_basalt_rock = basaltRock,
	lv_volcano = volcano,
	rr_cloud_bank = cloudBank,
	rr_planet = planet,
	dh_marble_pillar = marblePillar,
	dh_gold_cloud = goldCloud,
}

-- The biome's scenery (HighwayScenery's rows): each row's piece an Atomic Model named by its v6 id, on its v6 point in
-- the lane-local frame (L:1: z + 62) turned by its yaw; the clouds under v6's gates (d 8,350, L:1597-1599) follow
-- ours (Config gatesAt, PR3:36).
local function buildScenery(state: State, zone: Instance, index: number)
	local S = HighwayScenery
	local shift = state.deps.Config.Economy.Highway.gatesAt - S.v6GatesAt
	for _, row in S.biomes[index] do
		local kind = string.match(row.id, "^(.+)_%d+$")
		local build = if kind then SCENERY[kind] else nil
		assert(kind and build, "[SD][HighwayBuilder] HighwayScenery: no builder for " .. row.id)
		local z = row.at.Z + S.v6Zero
		if S.gateSupports[row.id] then
			z -= shift
		end
		local f = state.origin * CFrame.new(row.at.X, row.at.Y, z) * CFrame.Angles(0, math.rad(row.rot), 0)
		local model = newPiece(state, kind, true, row.id)
		build(state, model, f, row)
		place(model, f, zone)
	end
end

-- P13v4: a flight ring (WorldLayout.Highway.rings): its rods around the lane's axis at (0, y) d studs down the lane.
local function buildRing(state: State, zone: Instance, ring: any)
	local H = state.H
	local f = state.origin * CFrame.new(0, ring.y, -ring.d)
	local model = newPiece(state, "flight_ring", true)
	local glow = color(state, RING_TOKEN)
	for _, rod in Props.rods(model, "ring_rod", H.ringRadius, H.ringTube, f, glow, H.ringSegments) do
		rod.Material = MATERIALS[RING_TOKEN]
	end
	model:SetAttribute(state.A.Distance, ring.d)
	place(model, f, zone)
end

-- P13v4: a BULLSEYE pad (WorldLayout.Highway.pads): PAD_DISCS flat on the lane's top, d studs down the lane.
local function buildPad(state: State, zone: Instance, pad: any)
	local f = state.origin * CFrame.new(0, 0, -pad.d)
	local model = newPiece(state, "flight_pad", true)
	for _, disc in PAD_DISCS do
		cyl(state, model, "pad_disc", disc.token, f, disc.radius, disc.thickness, 0, LANE_TOP, 0)
	end
	model:SetAttribute(state.A.Distance, pad.d)
	place(model, f, zone)
end

-- The biomes in Config's order: each its own Model (K:7887) holding its lane, rails, markers, ground, arch and scenery.
local function buildBiomes(state: State, root: Instance)
	local H, C = state.H, state.deps.Config.Economy.Highway
	for index, look in H.biomes do
		local start = C.starts[index]
		local stop = C.starts[index + 1] or C.gatesAt
		local zone = Prims.model(look.model, nil, false)
		zone.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- p13v4 [P]: the chase camera (see the header)
		zone:SetAttribute(state.A.Biome, index)
		for d0 = start, stop - H.tileLength, H.tileLength do
			buildLane(state, zone, look, d0)
		end
		for d = math.max(start, H.markerEvery), stop - 1, H.markerEvery do
			buildMarker(state, zone, look, d)
		end
		if look.ground then
			for d0 = start, stop - 100, 100 do
				buildGround(state, zone, look, d0)
			end
		end
		if look.arch then
			buildArch(state, zone, look, start)
		end
		buildScenery(state, zone, index)
		if index == #H.biomes then
			buildGoldenGates(state, zone, C.gatesAt)
		end
		for _, ring in H.rings do
			if ring.biome == index then
				buildRing(state, zone, ring)
			end
		end
		for _, pad in H.pads do
			if pad.biome == index then
				buildPad(state, zone, pad)
			end
		end
		place(zone, state.origin * CFrame.new(0, 0, -start), root)
	end
end

-- The render rules on the finished tree: parts under SMALL_PART studs cast no shadow (Prims leaves every part
-- untouched; the mascot's own parts too).
local function applyRenderRules(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanTouch = false
			if math.max(descendant.Size.X, descendant.Size.Y, descendant.Size.Z) < SMALL_PART then
				descendant.CastShadow = false
			end
		end
	end
end

-- The report line: the parts of the deck and of every biome, its pieces against v6's cap.
local function report(state: State, root: Instance): string
	local parts: { string } = {}
	local total = 0
	for _, child in root:GetChildren() do
		local n = Prims.countParts(child)
		total += n
		if child.Name == DECK_NAME then
			table.insert(parts, string.format("%s %d parts", child.Name, n))
		else
			local pieces = 0
			for _, piece in child:GetChildren() do
				if piece:GetAttribute(state.A.Piece) ~= nil then
					pieces += 1
				end
			end
			table.insert(parts, string.format("%s %d parts / %d pieces", child.Name, n, pieces))
		end
	end
	local guis, lights = 0, 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("SurfaceGui") then
			guis += 1
		elseif descendant:IsA("Light") then
			lights += 1
		end
	end
	return string.format(
		"highway report: %s (cap %d pieces a biome); %d parts in all, %d SurfaceGuis, %d lights",
		table.concat(parts, ", "),
		state.H.maxPiecesPerBiome,
		total,
		guis,
		lights
	)
end

-- Public ---------------------------------------------------------------------------------------------------------

-- Builds the new highway tree, unparented and marked. Never changes the place. May throw on a broken data entry (Main
-- reports it as "build threw"); the half-built tree is destroyed with ctx.scratch.
function HighwayBuilder.build(ctx: BuildContext): BuildResult
	local warnings: { string } = {}
	local deps, depsError = loadDeps(ctx.Shared)
	if deps == nil then
		return failure(warnings, depsError or "could not load Shared modules")
	end
	local problem = dataProblem(deps)
	if problem then
		return failure(warnings, problem)
	end
	local H = deps.WorldLayout.Highway
	local root = Prims.model(ROOT_NAME, nil, false)
	local handedOver = false
	ctx.scratch:add(function()
		if not handedOver then
			root:Destroy()
		end
	end)
	local state: State = {
		deps = deps,
		H = H,
		A = deps.WorldLayout.Attributes,
		origin = H.origin,
		warnings = warnings,
		counts = {},
	}
	buildDeck(state, root)
	buildBiomes(state, root)
	applyRenderRules(root)
	root.WorldPivot = H.origin
	table.insert(warnings, report(state, root))
	Generated.mark(root, GENERATOR_ID, VERSION)
	handedOver = true
	return { ok = true, root = root, warnings = warnings, error = nil }
end

return HighwayBuilder
