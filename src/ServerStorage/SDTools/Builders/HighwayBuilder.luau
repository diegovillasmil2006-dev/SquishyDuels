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
-- (highway.*). The pieces' own shapes are here, each number with its design line; "reading" marks what v6 leaves open.
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
--
-- Highway v2 (owner 2026-10-23: "rebuild from Claude Design's sketches when they come"; the delivery "3D highway zones
-- model.zip", Spec v2): each zone is Claude Design's (sibling HighwayZones builds the kit HighwayKit: floor, walls,
-- outside, props, set pieces, light streams, particles); this module keeps the deck, the lane (in the zone's colour
-- and material), the markers, the rings, the pads and the name arches (Design's: pillars and a name beam). It replaced
-- v6's scenery (HighwayScenery), arches and Golden Gates, and the 2026-10-22 stand-in walls.
--
-- Tree:
--   SD_Highway (Model, WorldPivot = WorldLayout.Highway.origin, marked SD_Generated / highway / VERSION)
--     Deck (Model, Persistent: K:7881-7883 Plaza and LaunchGate are persistent zones)
--       launch_platform_01 (+ the L:2 light), watch_steps_01..02, launch_gate_01 (the CANDY MEADOW banner, the launch
--       board SD_LaunchBoard with its 8 empty live lines, the gate_mascot slot), candy_fence_01..04
--     Biome_1_CM .. Biome_7_DH (Models, Biome = n, WorldPivot at the biome's start; K:7887 one zone per biome)
--       lane_tile_NN / rr_rainbow_lane_NN, lane_rail_NN, distance_marker_NN (Distance), biome_arch_NN (zones 2-7; Lava
--       Volcano's with its light), HighwayZones' zone_floor / zone_wall / zone_outside / zone_fx and the kit's props
--       (named after them: lollipop_tree_NN, golden_gates_NN with its light ...), p13v4 flight_ring_NN (Distance;
--       01..21) and flight_pad_NN (Distance; 01..14): each an Atomic Model (K:7887). P13v4 [P]: every biome Model
--       Persistent (the chase camera flies up to 8,500 studs from the character; streamed-out biomes would show an
--       empty sky).
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
local HighwayZones = require(script.Parent.HighwayZones)

-- Types

type BuildContext = Generated.BuildContext
type BuildResult = Generated.BuildResult
type Flags = Prims.Flags

type Deps = {
	Strings: any,
	Palette: any,
	Config: any,
	WorldLayout: any,
	SquishyBuilder: any,
	Format: any,
	ValidateHighway: any,
	AssetTable: any,
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
-- 1: phase 12, the deck and the lane; 2: phase 12b, the biome scenery; 3: phase 13, no spots, rows; 4: p13v4, the rings
-- and BULLSEYE pads, biomes Persistent; 5-6: the 2026-10-22 stand-in; 7: Claude Design's highway v2 (2026-10-23).
local VERSION = 7
local CHECKER_KEY = "img.highway.floorChecker" -- AssetTable: Design's floor checker (HighwayZones)
local ARCH_FLOOR_Y = -0.1 -- the name arch stands on the zone floor (HighwayZones' Y0)
local ROOT_NAME = "SD_Highway"
local DECK_NAME = "Deck"

local SMALL_PART = 2 -- the lobby's render rule: parts under 2 studs cast no shadow
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's X axis onto the frame's Y
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- a Cylinder's X axis onto the frame's -Z (its Right face looks front)
local TURNED = CFrame.Angles(0, math.pi, 0) -- L "rot": 180 (the gate, the markers, the arches, the Golden Gates)
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
-- Owner 2026-10-22 ("blocky ish, kind of like lego textures", Steal an Egg): every plain part is Plastic, its blocks
-- studded on top (the deck, the lane, the markers; the zones are Claude Design's materials, HighwayZones).
local LEGO = Enum.Material.Plastic

-- L:2 L1_launch on launch_platform/light_anchor (LK:163 (0, 7, 0)), no shadows. The highway's other two lights are
-- Claude Design's (Spec v2): under Lava Volcano's name arch (buildArch) and on the Golden Gates (HighwayZones).
local LIGHTS = {
	launch = { name = "L1_launch", token = "HighwayLightLaunch", brightness = 1.2, range = 22 },
}

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
	AssetTable = "AssetTable",
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
-- looks, a kit zone (HighwayZones) that is not its biome (count, from, to) or has a piece in the flight tube, a biome
-- edge off the 50-stud lane pieces or the 100-stud markers, a Strings key or Palette token missing; p13v4: the rings
-- (RINGS_PER_BIOME a biome, each inside its biome, in passing order, clear of the lane's top) and the pads
-- (PADS_PER_BIOME a biome, each with its radius inside its biome), their tokens.
local function dataProblem(deps: Deps): string?
	local problems = deps.ValidateHighway(deps.Config)
	if #problems > 0 then
		return "Config.Economy.Highway: " .. table.concat(problems, "; ")
	end
	local H, C = deps.WorldLayout.Highway, deps.Config.Economy.Highway
	if #H.biomes ~= #C.starts then
		return string.format("WorldLayout.Highway has %d biome looks for %d biomes", #H.biomes, #C.starts)
	end
	local ok, zones = pcall(HighwayZones.zones, deps.Palette)
	if not ok then
		return "the highway kit: " .. tostring(zones)
	end
	if #zones ~= #C.starts then
		return string.format("the highway kit has %d zones for %d biomes", #zones, #C.starts)
	end
	for index, z in zones do
		if z.from ~= C.starts[index] or z.to ~= (C.starts[index + 1] or C.gatesAt) then
			return string.format("kit zone %d (%s) runs %d-%d, its biome does not", index, z.name, z.from, z.to)
		end
		local hits = HighwayZones.tubeHits(z)
		if #hits > 0 then
			return string.format("kit zone %d has pieces in the flight tube: %s", index, table.concat(hits, ", "))
		end
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

-- A Palette token's colour, Roblox material (nil: the Lego look) and shine.
local function look(state: State, token: string): (Color3, Enum.Material?, number)
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
		material = material or LEGO,
		shape = shape,
		flags = flags or "decor",
		parent = parent,
	})
	made.Reflectance = shine
	if material == nil and made.Shape == Enum.PartType.Block then
		made.TopSurface = Enum.SurfaceType.Studs -- owner 2026-10-22: the Lego look of Steal an Egg
	end
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

-- A built part in a kit colour (hex) and Roblox material (Claude Design's highway v2), its top plain.
local function kitPaint(p: BasePart, hex: string, mat: string): BasePart
	p.Color = HighwayZones.paint(hex, mat)
	p.Material = (Enum.Material :: any)[mat]
	p.TopSurface = Enum.SurfaceType.Smooth
	return p
end

-- lane_tile (HK:20) or, in Rainbow Road, rr_rainbow_lane, and its two lane_rail (HK:21, L:459-460) for the 50 studs from
-- `d0`. Highway v2 (Claude Design 2026-10-23: the lane, rails, signs, rings and pads "stay as they are; only their
-- colour and material change per zone"): kit zone `z`'s lane and rail colours and materials; the rainbow lane is its 6
-- stripes of 5 studs; the lane's edges a shade darker, its dashes the rail's.
local function buildLane(state: State, zone: Instance, z: any, d0: number)
	local f = state.origin * CFrame.new(0, 0, -(d0 + state.H.tileLength / 2))
	local lane: Model
	if z.lane.stripes then
		lane = newPiece(state, "rr_rainbow_lane", true)
		for i, hex in z.lane.stripes do
			kitPaint(box(state, lane, "rainbow_lane", "HighwayWhite", f, Vector3.new(5, 1, 50), -12.5 + (i - 1) * 5, 0, 0), hex, z.lane.m)
		end
	else
		lane = newPiece(state, "lane_tile", true)
		kitPaint(box(state, lane, "lane_top", "HighwayWhite", f, Vector3.new(26, 1, 50), 0, 0, 0), z.lane.c, z.lane.m)
		for _, x in { -14, 14 } do
			kitPaint(box(state, lane, "lane_edges", "HighwayWhite", f, Vector3.new(2, 1.04, 50), x, 0, 0), HighwayZones.Core.tone(z.lane.c, -0.12), z.lane.m)
		end
		for dz = -20, 20, 10 do
			kitPaint(box(state, lane, "lane_edges", "HighwayWhite", f, Vector3.new(0.8, 1.06, 4), 0, 0, dz), z.rail.c, z.rail.m)
		end
	end
	place(lane, f, zone)
	for _, x in { -14, 14 } do
		local r = state.origin * CFrame.new(x, 1.04, -(d0 + state.H.tileLength / 2))
		local rail = newPiece(state, "lane_rail", true)
		kitPaint(cylZ(state, rail, "rail", "HighwayWhite", r, 0.6, 50, 0, 1.2, 0), z.rail.c, z.rail.m)
		for dz = -20, 20, 20 do
			kitPaint(box(state, rail, "rail", "HighwayWhite", r, Vector3.new(0.5, 1, 0.5), 0, 0, dz), z.rail.c, z.rail.m)
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

-- biome_arch (Claude Design highway v2, kit-build.js:237-243): at the zone's start, two pillars at x +-57 and the name
-- beam 126 x 8 x 6 at y nameArchY (72, or the walls' top + 8), the zone's name on its deck-facing face (white, ink
-- outline: textTex's 84 px of 130), the strip under it on the deck side; Lava Volcano's PointLight under the beam
-- (Spec v2: 1 of the highway's 3 lights).
local function buildArch(state: State, zone: Instance, look: any, z: any, d: number)
	local A = z.arch
	local wallTop = 0
	for _, t in z.tiers do
		wallTop = math.max(wallTop, t.y1)
	end
	local B = math.max(72, wallTop + 8)
	local f = state.origin * CFrame.new(0, ARCH_FLOOR_Y, -d)
	local model = newPiece(state, "biome_arch", true)
	local function piece(name: string, hex: string, mat: string, size: Vector3, x: number, y: number, dz: number): BasePart
		return kitPaint(box(state, model, name, "HighwayWhite", f, size, x, y - size.Y / 2, dz), hex, mat)
	end
	-- 2 LAYER thinner and shorter than Design's 6 x (B + 8) x 6: flush, they flickered with the beam and the walls.
	local trim = 2 * Prims.LAYER
	for _, x in { -57, 57 } do
		piece("arch_pillar", A.pillar, A.pillarM, Vector3.new(6 - trim, B + 8 - trim, 6 - trim), x, (B + 8 - trim) / 2, 0)
	end
	local beam = piece("arch_beam", A.beam, A.beamM, Vector3.new(126, 8, 6), 0, B + 4, 0)
	piece("arch_strip", A.strip, A.stripM, Vector3.new(120, 1.2, 0.4), 0, B + 0.6, 3.2)
	local canvas = canvasOn(beam, Enum.NormalId.Back, Vector2.new(126, 8), Vector2.new(124, 7))
	line(canvas, 7, {
		name = "Name",
		text = state.deps.Strings.resolve(look.nameKey),
		key = look.nameKey,
		x = 0.5,
		y = 0.54,
		width = 1,
		px = 208, -- 84 / 130 of the 8-stud beam: 5.2 studs at DESIGN_PPU
		color = color(state, "White"),
		stroke = color(state, "HighwayKitInk"),
	})
	for _, l in z.fx.lights do
		if l.where == "nameArch" then
			local at = Instance.new("Attachment")
			at.Name = "light_anchor"
			at.Position = Vector3.new(0, -6, 0)
			local pointLight = Instance.new("PointLight")
			pointLight.Name = "L_arch"
			pointLight.Color = Color3.fromHex(l.c)
			pointLight.Range = l.range
			pointLight.Brightness = l.brightness
			pointLight.Shadows = false
			pointLight.Parent = at
			at.Parent = beam
		end
	end
	place(model, f, zone)
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

-- The biomes in Config's order: each its own Model (K:7887) holding its lane, rails, markers, name arch and, since
-- highway v2, Claude Design's zone (HighwayZones: floor, walls, outside, props, set pieces, light streams, particles).
-- Yields (HighwayZones' unions).
local function buildBiomes(state: State, root: Instance)
	local H, C = state.H, state.deps.Config.Economy.Highway
	local kitZones = HighwayZones.zones(state.deps.Palette)
	local ctx: HighwayZones.Ctx = {
		origin = state.origin,
		newPiece = function(piece: string, atomic: boolean, id: string?): Model
			return newPiece(state, piece, atomic, id)
		end,
		place = place,
		checker = state.deps.AssetTable.image(CHECKER_KEY),
		textures = state.deps.Config.Vfx.Textures,
		warnings = state.warnings,
	}
	for index, look in H.biomes do
		local z = kitZones[index]
		local start = C.starts[index]
		local stop = C.starts[index + 1] or C.gatesAt
		local zone = Prims.model(look.model, nil, false)
		zone.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- p13v4 [P]: the chase camera (see the header)
		zone:SetAttribute(state.A.Biome, index)
		for d0 = start, stop - H.tileLength, H.tileLength do
			buildLane(state, zone, z, d0)
		end
		for d = math.max(start, H.markerEvery), stop - 1, H.markerEvery do
			buildMarker(state, zone, look, d)
		end
		if z.arch then
			buildArch(state, zone, look, z, start)
		end
		HighwayZones.dress(ctx, z, zone)
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
