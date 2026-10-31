--!strict
-- SkyMapBuilder (SDTools target "sky_maps"): Diego's 11 sky maps (NEW MAPS FINALS zip, 2026-10-30) built from
-- Shared.Maps.MapData + MapLayout as his 3D demos draw them ("Squishy Duels {Duel,TDM,FFA} Demo.dc.html": loadMap,
-- decorate, face, skyProp, buildClouds), into one Folder ServerStorage.SquishyMaps of Models named after each map (CookieCounter). Runtime code
-- clones them (MatchMapService: Team / Free for All at their own spot; ArenaService: the 1v1 maps into its slots).
-- Each map floats in the sky: its north-west floor corner at SLOT(i) (Y 300), the floor top at local Y 0.
-- Folders (his SUPERPROMPT): Floor, Structures, Colliders, InvisibleWalls, Spawns, Routes, Decor, Sky, Ambient; a 1v1
-- map nests Floor/Structures/Colliders and Barriers (= InvisibleWalls) in Geometry and adds Origin, Zones and
-- Spawns/PadA/PadB (ArenaService's frame). Power-up pads are not built (the zip says IGNORE POWERUPS); MapData keeps them.
-- Readings where the demo can't be copied 1:1 in Roblox:
--   * toon shading -> SmoothPlastic; his stud canvas -> MaterialVariant SquishyMapStud (MapStud.png, 8 studs a tile,
--     tinted by the part colour like his smat); the floor canvas -> 2 Textures (FloorCheck tinted theme.grid, FloorStud)
--   * his BackSide outline meshes -> ReplicatedStorage.SquishyOutlineMeshes (his HullBox/HullCylinder/HullSphere,
--     inward faces), sized like his outl(): sides + t, top + t, bottom -0.08 (centre boxes: + t all round)
--   * round walls/covers -> cylinders (maps.json, SUPERPROMPT) with his face; a still invisible collider holds the
--     collision while the visible one squishes (MapFX)
--   * stairs -> his 6 steps (no collision) + a smooth WedgePart ramp (his rampTop line)
--   * wires -> Beams with a Bezier sag (his TubeGeometry curves); the torus donut -> 16 balls (his old Roblox builder)
--   * cones (crayon tips, pencil tip) -> ellipsoids (his old Roblox builder); flags -> 2 mirrored wedges each
-- Pure helpers (unit-tested): slotCorner(index), wedgeCFrame(element, corner).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Generated = require(script.Parent.Parent.Generated)

local dynamicRequire = require :: (ModuleScript) -> any

local SkyMapBuilder = {}

SkyMapBuilder.VERSION = 1
SkyMapBuilder.TARGET = "sky_maps"
SkyMapBuilder.ROOT_NAME = "SquishyMaps"
SkyMapBuilder.STUD_VARIANT = "SquishyMapStud"
SkyMapBuilder.TAG_PREFIX = "SquishyFX_" -- his SquishyMapFX tags (MapFX reads them)

-- Uploaded 2026-10-30 (tools/maps/make_assets.mjs, docs/new-maps/textures).
local FLOOR_CHECK = "rbxassetid://75578035159252"
local FLOOR_STUD = "rbxassetid://72408158301076"
local MAP_STUD = "rbxassetid://137735286152608"

local SKY_Y = 300 -- SUPERPROMPT: platform floor at Y ~300 or higher
local ROW_Z = 3000 -- south of the lobby (Z -300..300), away from the highway (Z < -280)
local SPACING = 800 -- his builder's Spacing
local FIRST_X = -2800

local DECK_H, WALL_H, COVER_H, STEPS = 10, 16, 4, 6
local T = 0.32 -- his outline thickness
local UP = CFrame.Angles(0, 0, math.pi / 2) -- a Roblox cylinder's axis is X: this stands it up

local function hex(h: string): Color3
	return Color3.fromHex(h)
end
local INK = hex("#1c1530")
local WHITE = Color3.new(1, 1, 1)

-- His mix(a, b, t): per channel on 0..255, rounded.
local function mix(a: Color3, b: Color3, t: number): Color3
	local function ch(x: number, y: number): number
		return math.floor(x * 255 + (y * 255 - x * 255) * t + 0.5)
	end
	return Color3.fromRGB(ch(a.R, b.R), ch(a.G, b.G), ch(a.B, b.B))
end

-- The north-west floor corner of map number `index` (MapData.order), in world studs.
function SkyMapBuilder.slotCorner(index: number): Vector3
	return Vector3.new(FIRST_X + (index - 1) * SPACING, SKY_Y, ROW_Z)
end

-- A map's Model name: his name without spaces ("Cookie Counter" -> "CookieCounter"), as the old maps were named.
function SkyMapBuilder.modelName(map: any): string
	return (string.gsub(map.name, "%s", ""))
end

-- The ramp under a stair: a WedgePart whose slope climbs along local +Z (its tall face at +Z) from the floor to the
-- deck, over the stair's footprint. `corner` = the map's corner.
local CLIMB: { [string]: Vector3 } =
	{ n = Vector3.new(0, 0, -1), s = Vector3.new(0, 0, 1), e = Vector3.new(1, 0, 0), w = Vector3.new(-1, 0, 0) }
function SkyMapBuilder.wedgeCFrame(e: any, corner: Vector3): (CFrame, Vector3)
	local dir = CLIMB[e.stairUp]
	local ns = e.stairUp == "n" or e.stairUp == "s"
	local run, width = if ns then e.d else e.w, if ns then e.w else e.d
	local c = corner + Vector3.new(e.x + e.w / 2, DECK_H / 2, e.z + e.d / 2)
	return CFrame.lookAt(c, c - dir), Vector3.new(width, DECK_H, run)
end

-- Builder state for one map.
type Ctx = {
	corner: Vector3,
	hulls: Instance?,
	F: { [string]: Instance },
	parts: number,
}

type PartOpts = {
	name: string?,
	shape: Enum.PartType?,
	stud: boolean?, -- his smat (stud canvas); default plain (tmat)
	collide: boolean?, -- default false
	transparency: number?,
	shadow: boolean?, -- default: collide
	neon: boolean?,
	sphereMesh: boolean?, -- an ellipsoid (SpecialMesh Sphere fills the part's box)
	wedge: boolean?,
}

local function newPart(ctx: Ctx, parent: Instance, size: Vector3, cf: CFrame, color: Color3, o: PartOpts?): BasePart
	local opts: PartOpts = o or {}
	local p: BasePart
	if opts.wedge then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if opts.shape then
			part.Shape = opts.shape
		end
		p = part
	end
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = if opts.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	if opts.stud then
		p.MaterialVariant = SkyMapBuilder.STUD_VARIANT
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = opts.transparency or 0
	local collide = opts.collide == true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.CastShadow = if opts.shadow ~= nil then opts.shadow else collide
	if opts.sphereMesh then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Name = opts.name or "Part"
	p.Parent = parent
	ctx.parts += 1
	return p
end

-- One of his hull meshes ("HullBox" / "HullCylinder" / "HullSphere") at `cf`, `size` (nil when not installed).
local function hull(ctx: Ctx, parent: Instance, kind: string, cf: CFrame, size: Vector3): BasePart?
	local source = ctx.hulls and ctx.hulls:FindFirstChild(kind)
	if source == nil or not source:IsA("BasePart") then
		return nil
	end
	local h = source:Clone()
	h.Anchored = true
	h.CanCollide = false
	h.CanQuery = false
	h.CanTouch = false
	h.CastShadow = false
	h.Color = INK
	h.Material = Enum.Material.SmoothPlastic
	h.Size = size
	h.CFrame = cf
	h.Name = "Outline"
	h.Parent = parent
	ctx.parts += 1
	return h
end

type BoxOpts = {
	name: string?,
	t: number?, -- outline thickness (0.32); 0 = none
	center: boolean?, -- centred on `at` instead of standing on it
	plain: boolean?, -- tmat (no stud canvas)
	collide: boolean?,
	cf: CFrame?, -- the box's rotation (around its centre)
	hullParent: Instance?,
	hullOnSelf: boolean?, -- the hull becomes the part's child (MapFX moves it with the part)
	transparency: number?,
	shadow: boolean?,
}

-- His box(w, hh, d, col, o): standing on `at` (o.center: centred on it), stud canvas, ink hull o.t.
local function box(ctx: Ctx, parent: Instance, w: number, hh: number, d: number, color: Color3, at: Vector3, o: BoxOpts?): BasePart
	local opts: BoxOpts = o or {}
	local centre = if opts.center then at else at + Vector3.new(0, hh / 2, 0)
	local rot = opts.cf or CFrame.identity
	local cf = CFrame.new(centre) * rot
	local p = newPart(ctx, parent, Vector3.new(w, hh, d), cf, color, {
		name = opts.name,
		stud = not opts.plain,
		collide = opts.collide,
		transparency = opts.transparency,
		shadow = opts.shadow,
	})
	local t = opts.t or 0.32
	if t > 0 then
		if opts.center then
			hull(ctx, opts.hullParent or parent, "HullBox", cf, Vector3.new(w + 2 * t, hh + 2 * t, d + 2 * t))
		else
			local hcf = CFrame.new(at + Vector3.new(0, (hh + t) / 2 - 0.08, 0)) * rot
			hull(ctx, opts.hullParent or parent, "HullBox", hcf, Vector3.new(w + 2 * t, hh + t, d + 2 * t))
		end
	end
	return p
end

-- His cyl(r, hh, col, o): a standing cylinder on `at` (o.center: centred), plain, ink hull o.t.
local function cyl(ctx: Ctx, parent: Instance, r: number, hh: number, color: Color3, at: Vector3, o: BoxOpts?): BasePart
	local opts: BoxOpts = o or {}
	local centre = if opts.center then at else at + Vector3.new(0, hh / 2, 0)
	local cf = CFrame.new(centre) * (opts.cf or CFrame.identity) * UP
	local p = newPart(ctx, parent, Vector3.new(hh, 2 * r, 2 * r), cf, color, {
		name = opts.name,
		shape = Enum.PartType.Cylinder,
		collide = opts.collide,
		transparency = opts.transparency,
		shadow = opts.shadow,
	})
	local t = opts.t or 0.32
	local hullParent = if opts.hullOnSelf then p else opts.hullParent or parent
	if t > 0 then
		if opts.center then
			hull(ctx, hullParent, "HullCylinder", cf, Vector3.new(hh + 2 * t, 2 * (r + t), 2 * (r + t)))
		else
			local hcf = CFrame.new(at + Vector3.new(0, (hh + t) / 2 - 0.08, 0)) * (opts.cf or CFrame.identity) * UP
			hull(ctx, hullParent, "HullCylinder", hcf, Vector3.new(hh + t, 2 * (r + t), 2 * (r + t)))
		end
	end
	return p
end

-- His ball(r, col, o): centred on `at`, ink hull o.t (0.25). `scale` stretches it into an ellipsoid.
local function ball(ctx: Ctx, parent: Instance, r: number, color: Color3, at: Vector3, o: BoxOpts?, scale: Vector3?): BasePart
	local opts: BoxOpts = o or {}
	local s = scale or Vector3.one
	local cf = CFrame.new(at) * (opts.cf or CFrame.identity)
	local size = Vector3.new(2 * r * s.X, 2 * r * s.Y, 2 * r * s.Z)
	local p = newPart(ctx, parent, size, cf, color, {
		name = opts.name,
		shape = if scale then nil else Enum.PartType.Ball,
		sphereMesh = scale ~= nil,
		transparency = opts.transparency,
		shadow = opts.shadow,
	})
	local t = opts.t or 0.25
	if t > 0 then
		hull(ctx, opts.hullParent or parent, "HullSphere", cf, size + Vector3.new(2 * t, 2 * t, 2 * t) * s)
	end
	return p
end

local function tag(instance: Instance, kind: string, attrs: { [string]: any }?)
	CollectionService:AddTag(instance, SkyMapBuilder.TAG_PREFIX .. kind)
	if attrs then
		for k, v in attrs do
			instance:SetAttribute(k, v)
		end
	end
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- A small group (a prop, a knob, a flag, a cloud): Atomic, so a streaming client gets it whole for MapFX to move.
local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m.Parent = parent
	return m
end

-- A wire from a to b sagging `depth` at the middle (his TubeGeometry r .13 through sag(t)): a Beam, its Attachments on
-- `holder`.
local function wire(holder: BasePart, a: Vector3, b: Vector3, depth: number)
	local span = b - a
	local flat = Vector3.new(span.X, 0, span.Z)
	local along = flat.Unit * (flat.Magnitude / 3)
	local h = depth / 0.75 -- a cubic Bezier with both handles down h sags 0.75 h at the middle
	local d0 = along - Vector3.new(0, h, 0)
	local d1 = along + Vector3.new(0, h, 0)
	local a0 = Instance.new("Attachment")
	a0.Name = "WireA"
	a0.WorldCFrame = CFrame.lookAt(a, a + d0.Unit) * CFrame.Angles(0, math.pi / 2, 0) -- Attachment X axis = d0
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Name = "WireB"
	a1.WorldCFrame = CFrame.lookAt(b, b + d1.Unit) * CFrame.Angles(0, math.pi / 2, 0)
	a1.Parent = holder
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.CurveSize0 = d0.Magnitude
	beam.CurveSize1 = d1.Magnitude
	beam.Color = ColorSequence.new(INK)
	beam.Width0 = 0.26
	beam.Width1 = 0.26
	beam.FaceCamera = true
	beam.Segments = 12
	beam.LightInfluence = 1
	beam.Transparency = NumberSequence.new(0)
	beam.Name = "Wire"
	beam.Parent = holder
end

-- His face(mesh, r, hh, ang): eyes, shines, blush and smile on a round wall, facing `ang` (around Y), parented to
-- `vis` so MapFX squishes them with it. `bottom` = the wall's bottom centre.
local function face(ctx: Ctx, vis: BasePart, bottom: Vector3, r0: number, hh: number, ang: number)
	local r = r0 * 1.05
	local y = hh * 0.62
	local er = math.clamp(r * 0.12, 0.32, 1.1)
	local rot = CFrame.Angles(0, ang, 0)
	local function at(x: number, yy: number, z: number): Vector3
		return bottom + rot:VectorToWorldSpace(Vector3.new(x, yy, z))
	end
	local function ell(color: Color3, sx: number, sy: number, sz: number, pos: Vector3)
		-- his eyeG is a unit sphere scaled (sx, sy, sz): an ellipsoid 2s across
		newPart(ctx, vis, Vector3.new(2 * sx, 2 * sy, 2 * sz), CFrame.new(pos) * rot, color, { name = "Face", sphereMesh = true })
	end
	for _, s in { -1, 1 } do
		ell(INK, er, er * 1.15, er, at(s * r * 0.32, y, r * 0.96))
		ell(WHITE, er * 0.36, er * 0.36, er * 0.36, at(s * r * 0.32 - er * 0.3, y + er * 0.4, r * 0.96 + er * 0.75))
		ell(hex("#ff9bb8"), er * 1.4, er * 0.7, er * 0.35, at(s * r * 0.58, y - er * 1.5, r * 0.88))
	end
	-- the smile: his half torus (radius er .75, tube .24 of it) turned upside down, as 4 short rods
	local mr, tube = er * 0.75, er * 0.75 * 0.24
	local cy, cz = y - er * 1.1, r * 0.98
	for k = 0, 3 do
		local a0, a1 = math.pi + k * math.pi / 4, math.pi + (k + 1) * math.pi / 4
		local p0 = at(math.cos(a0) * mr, cy + math.sin(a0) * mr, cz)
		local p1 = at(math.cos(a1) * mr, cy + math.sin(a1) * mr, cz)
		newPart(ctx, vis, Vector3.new((p1 - p0).Magnitude + tube, 2 * tube, 2 * tube), CFrame.lookAt((p0 + p1) / 2, p1) * CFrame.Angles(0, math.pi / 2, 0), INK, { name = "Face" })
	end
end

-- His skyProp(kind, pal, i): one floating prop, built around the origin of a Model at `pos`.
local function skyProp(ctx: Ctx, parent: Instance, kind: string, pal: { string }, i: number): Model
	local g = model("SkyProp", parent)
	local pick = hex(pal[i % #pal + 1])
	local v = i % 3
	local O = Vector3.zero
	local function V(x: number, y: number, z: number): Vector3
		return O + Vector3.new(x, y, z)
	end
	if kind == "cookie" then
		if v == 0 then
			cyl(ctx, g, 6, 2, hex("#e8b47c"), V(0, 0, 0), { center = true, t = 0.3 })
			for k = 0, 6 do
				local a, rr = k * 0.9, 1.5 + (k % 3) * 1.3
				ball(ctx, g, 0.7, hex("#6b3f2a"), V(math.cos(a) * rr, 1, math.sin(a) * rr), { t = 0.1 })
			end
		elseif v == 1 then
			-- his TorusGeometry(5, 2.3) donut as a ring of balls, with his capsule sprinkles on top
			for k = 0, 15 do
				local a = k / 16 * math.pi * 2
				ball(ctx, g, 2.3, pick, V(math.cos(a) * 5, 0, math.sin(a) * 5), { t = 0.25 })
			end
			for k = 0, 9 do
				local a = k * 0.63
				newPart(ctx, g, Vector3.new(0.44, 1.24, 0.44), CFrame.new(V(math.cos(a) * 5, 2.2, math.sin(a) * 5)) * CFrame.Angles(math.pi / 2, 0, a * 2), hex(pal[(k + 1) % #pal + 1]), { name = "Sprinkle", sphereMesh = true })
			end
		else
			box(ctx, g, 5, 5, 5, hex("#fffaf2"), V(0, 0, 0), { center = true })
		end
	elseif kind == "bubble" then
		if v == 0 then
			ball(ctx, g, 4, hex("#ffe066"), V(0, 0, 0), { t = 0.3 }, Vector3.new(1.3, 0.9, 1))
			ball(ctx, g, 2.6, hex("#ffe066"), V(2.8, 3.2, 0), { t = 0.3 })
			ball(ctx, g, 1, hex("#ff9a3c"), V(5.6, 3, 0), { t = 0.15 }, Vector3.new(1, 0.9, 0.9))
			for _, s in { -1, 1 } do
				ball(ctx, g, 0.42, INK, V(4.4, 3.8, s * 1.2), { t = 0 })
			end
		elseif v == 1 then
			ball(ctx, g, 5, hex("#dff4ff"), V(0, 0, 0), { t = 0.15, transparency = 0.5 })
			ball(ctx, g, 1, WHITE, V(-2, 2.5, 3), { t = 0 })
		else
			box(ctx, g, 8, 3, 5, pick, V(0, 0, 0), { center = true })
		end
	elseif kind == "crayon" then
		if v == 2 then
			ball(ctx, g, 4, pick, V(0, 0, 0), { t = 0.3 }, Vector3.new(1.3, 0.7, 1.1))
		else
			cyl(ctx, g, 1.5, 12, pick, V(0, 0, 0), { center = true })
			cyl(ctx, g, 1.62, 3, mix(pick, INK, 0.25), V(0, -3, 0), { center = true, t = 0.15 })
			ball(ctx, g, 1.5, pick, V(0, 7.4, 0), { t = 0.25 }, Vector3.new(0.87, 1.07, 0.87))
		end
	else -- book
		if v == 2 then
			cyl(ctx, g, 0.9, 13, hex("#ffd36b"), V(0, 0, 0), { center = true })
			ball(ctx, g, 0.9, hex("#f2c38b"), V(0, 7.6, 0), { t = 0.2 }, Vector3.new(0.9, 1.33, 0.9))
			cyl(ctx, g, 0.95, 1.6, hex("#ff9fb2"), V(0, -7.3, 0), { center = true })
		else
			box(ctx, g, 10, 2.6, 7, pick, V(0, 0, 0), { center = true })
			box(ctx, g, 9.4, 2, 6.6, hex("#fffaf0"), V(0.5, 0, 0), { center = true, t = 0.05 })
		end
	end
	g.WorldPivot = CFrame.new(O)
	return g
end

-- One map's Model, built at `corner` (its north-west floor corner).
function SkyMapBuilder.buildMap(map: any, MapLayout: any, corner: Vector3, hulls: Instance?): (Model, number)
	local W, H = map.W, map.H
	local th: { [string]: Color3 } = {}
	for k, v in map.theme do
		th[k] = hex(v)
	end
	local duel = map.mode == "duel"
	local root = Instance.new("Model")
	root.Name = SkyMapBuilder.modelName(map) -- "CookieCounter" (his name without spaces, like the old maps)
	local ctx: Ctx = { corner = corner, hulls = hulls, F = {}, parts = 0 }
	local geometry: Instance = root
	if duel then
		geometry = folder("Geometry", root)
	end
	for _, name in { "Floor", "Structures", "Colliders" } do
		ctx.F[name] = folder(name, geometry)
	end
	ctx.F.InvisibleWalls = folder(if duel then "Barriers" else "InvisibleWalls", geometry)
	for _, name in { "Spawns", "Routes", "Decor", "Sky", "Ambient" } do
		ctx.F[name] = folder(name, root)
	end
	local F = ctx.F
	local function P(x: number, y: number, z: number): Vector3
		return corner + Vector3.new(x, y, z)
	end
	local L = MapLayout.build(map)

	-- floor: his box (W, 5, H) with the floor canvas on top and theme.footer sides, ink hull below the top
	local floorTop = newPart(ctx, F.Floor, Vector3.new(W, 0.2, H), CFrame.new(P(W / 2, -0.1, H / 2)), th.floor, { name = "Floor", collide = true })
	for _, layer in { { FLOOR_CHECK, th.grid, 1 }, { FLOOR_STUD, WHITE, 2 } } do
		local tex = Instance.new("Texture")
		tex.Texture = layer[1] :: string
		tex.Color3 = layer[2] :: Color3
		tex.ZIndex = layer[3] :: number
		tex.Face = Enum.NormalId.Top
		tex.StudsPerTileU = 8
		tex.StudsPerTileV = 8
		tex.Parent = floorTop
	end
	newPart(ctx, F.Floor, Vector3.new(W, 4.8, H), CFrame.new(P(W / 2, -2.6, H / 2)), th.footer, { name = "FloorBody", collide = true })
	hull(ctx, F.Floor, "HullBox", CFrame.new(P(W / 2, -2.8, H / 2)), Vector3.new(W + 1.2, 5.6, H + 1.2))
	-- his drawFloor ink border: 1 stud wide just inside the edge
	for _, b in { { W / 2, 0.5, W, 1 }, { W / 2, H - 0.5, W, 1 }, { 0.5, H / 2, 1, H }, { W - 0.5, H / 2, 1, H } } do
		newPart(ctx, F.Floor, Vector3.new(b[3], 0.04, b[4]), CFrame.new(P(b[1], 0.02, b[2])), INK, { name = "FloorBorder" })
	end
	-- rim (his decorate): (W + 12, 5, H + 12), top at -0.7, plain mix(floor, footer, .22)
	local RIM = L.RIM
	newPart(ctx, F.Floor, Vector3.new(W + RIM * 2, 5, H + RIM * 2), CFrame.new(P(W / 2, -3.2, H / 2)), mix(th.floor, th.footer, 0.22), { name = "Rim", collide = true })
	hull(ctx, F.Floor, "HullBox", CFrame.new(P(W / 2, -3.5, H / 2)), Vector3.new(W + RIM * 2 + 1.2, 5.6, H + RIM * 2 + 1.2))
	-- SUPERPROMPT: 120-stud invisible walls at the platform edge
	for _, w in { { W / 2, -1, W + 4, 2 }, { W / 2, H + 1, W + 4, 2 }, { -1, H / 2, 2, H + 4 }, { W + 1, H / 2, 2, H + 4 } } do
		local wall = newPart(ctx, F.InvisibleWalls, Vector3.new(w[3], 120, w[4]), CFrame.new(P(w[1], 60, w[2])), WHITE, { name = "InvisibleWall", collide = true, transparency = 1, shadow = false })
		wall.CollisionGroup = "SD_Barrier" -- like the old arenas' walls: stops players only, never a throw's ray
	end

	-- elements (his loadMap)
	local spawnIndex = 0
	local phaseRng = Random.new(#map.id * 7919 + string.byte(map.id, 2))
	for _, e in map.elements do
		local base = if e.level == 2 then DECK_H else 0
		local cx, cz = e.x + e.w / 2, e.z + e.d / 2
		local t = e.type
		local ph = phaseRng:NextNumber() * 10
		if t == "zone" then
			local z: BasePart
			if e.round then
				z = newPart(ctx, F.Floor, Vector3.new(0.05, e.w, e.w), CFrame.new(P(cx, base + 0.12, cz)) * UP, th.zone, { name = "Zone", shape = Enum.PartType.Cylinder, transparency = 0.08 })
			else
				z = newPart(ctx, F.Floor, Vector3.new(e.w, 0.05, e.d), CFrame.new(P(cx, base + 0.12, cz)), th.zone, { name = "Zone", transparency = 0.08 })
			end
			tag(z, "Shimmer", { Phase = ph, Speed = 1.6 })
		elseif t == "spawnA" or t == "spawnB" or t == "spawn" then
			local col = hex(if t == "spawnA" then "#ff6b8a" elseif t == "spawnB" then "#4fb0ff" else "#ffc93c")
			local name
			if t == "spawn" then
				spawnIndex += 1
				name = string.format("Spawn_Ffa_%02d", spawnIndex)
			else
				name = if t == "spawnA" then "Spawn_Red" else "Spawn_Blue"
			end
			local plate = newPart(ctx, F.Spawns, Vector3.new(e.w, 0.05, e.d), CFrame.new(P(cx, 0.2, cz)), col, { name = name, transparency = 0.55 })
			if t ~= "spawn" then
				plate:SetAttribute("Team", if t == "spawnA" then "Pink" else "Blue")
			end
			local pulse = newPart(ctx, F.Spawns, Vector3.new(e.w, 0.05, e.d), CFrame.new(P(cx, 0.26, cz)), col, { name = "SpawnPulse", transparency = 0.5 })
			tag(pulse, "Pulse", { Phase = ph, Speed = 0.5 })
			for _, fr in { { e.w, 0.8, cx, e.z + 0.4 }, { e.w, 0.8, cx, e.z + e.d - 0.4 }, { 0.8, e.d, e.x + 0.4, cz }, { 0.8, e.d, e.x + e.w - 0.4, cz } } do
				box(ctx, F.Spawns, fr[1], 0.35, fr[2], col, P(fr[3], 0, fr[4]), { name = "SpawnFrame", t = 0.12, plain = true })
			end
		elseif t == "pad" then
			continue -- IGNORE POWERUPS (the zip's name): the Squish Pods design comes later; MapData keeps the spots
		elseif t == "wall" or t == "cover" then
			local hh = e.height or (if t == "wall" then WALL_H else COVER_H)
			local col = if t == "wall" then th.wall else th.cover
			local capCol = th.cap or mix(col, WHITE, 0.3)
			local name = if t == "wall" then "Wall" else "Cover"
			if e.round then
				local r = e.w / 2
				local bottom = P(cx, base, cz)
				cyl(ctx, F.Colliders, r, hh, col, bottom, { name = name .. "Collider", t = 0, collide = true, transparency = 1, shadow = false })
				-- the hull, cap and face follow the visible part (his outl adds them to the mesh): they are its children
				local vis = cyl(ctx, F.Structures, r, hh, col, bottom, { name = "Round" .. name, hullOnSelf = true })
				if t == "wall" then
					cyl(ctx, vis, r + 0.25, 1.4, capCol, bottom + Vector3.new(0, hh - 1, 0), { name = "Cap", t = 0.22 })
				end
				if math.abs(cx - W / 2) < 0.5 then
					face(ctx, vis, bottom, r, hh, math.pi / 2)
					face(ctx, vis, bottom, r, hh, -math.pi / 2)
				else
					face(ctx, vis, bottom, r, hh, if cx < W / 2 then math.pi / 2 else -math.pi / 2)
				end
				tag(vis, "Squish", { Amp = if t == "wall" then 0.035 else 0.07, Speed = 1.6, Phase = ph })
			else
				box(ctx, F.Structures, e.w, hh, e.d, col, P(cx, base, cz), { name = name, collide = true })
				if t == "wall" then
					box(ctx, F.Structures, e.w + 0.5, 1.4, e.d + 0.5, capCol, P(cx, base + hh - 1, cz), { name = "Cap", t = 0.22, collide = true })
				end
			end
		elseif t == "deck" then
			if e.round then
				local r = e.w / 2
				local centre = P(cx, DECK_H - 0.8, cz)
				local collider = cyl(ctx, F.Colliders, r, 1.6, th.deck, centre, { name = "DeckCollider", center = true, t = 0, collide = true, transparency = 1, shadow = false })
				local slab = model("RoundDeck", F.Structures)
				cyl(ctx, slab, r, 1.6, th.deck, centre, { name = "Slab", center = true })
				for k = 0, 7 do
					local a = k / 8 * math.pi * 2
					local stripeCol = if k % 2 == 1 then WHITE else mix(th.deck, hex("#ff8fb0"), 0.45)
					box(ctx, slab, r * 0.8, 0.25, 1.4, stripeCol, centre + Vector3.new(math.cos(a) * r * 0.5, 0.9, math.sin(a) * r * 0.5), { name = "Stripe", center = true, t = 0.1, cf = CFrame.Angles(0, -a, 0) })
				end
				slab.WorldPivot = CFrame.new(centre)
				if e.spin then
					-- his spinY 0.45 rad/s: the slab turns on screens (MapFX); the still collider carries players
					tag(slab, "SpinY", { Speed = 0.45 })
					collider.AssemblyAngularVelocity = Vector3.new(0, 0.45, 0)
				end
			elseif e.solid then
				box(ctx, F.Structures, e.w, DECK_H, e.d, th.deck, P(cx, 0, cz), { name = "Block", collide = true })
			else
				local st = 1.6
				box(ctx, F.Structures, e.w, st, e.d, th.deck, P(cx, DECK_H - st / 2, cz), { name = "Deck", center = true, collide = true })
				local ps = math.min(3, e.w * 0.3, e.d * 0.3)
				local cols = math.max(2, math.floor(e.w / 26 + 0.5) + 1)
				local rows = math.max(2, math.floor(e.d / 26 + 0.5) + 1)
				local pc = mix(th.deck, INK, 0.15)
				for a = 0, cols - 1 do
					for b = 0, rows - 1 do
						if not (a > 0 and a < cols - 1 and b > 0 and b < rows - 1) then
							local px = e.x + ps / 2 + (e.w - ps) * a / (cols - 1)
							local pz = e.z + ps / 2 + (e.d - ps) * b / (rows - 1)
							box(ctx, F.Structures, ps, DECK_H - st, ps, pc, P(px, 0, pz), { name = "Pillar", t = 0.2, collide = true })
						end
					end
				end
			end
		elseif t == "stair" then
			local steps = model("Stair", F.Structures)
			for j = 0, STEPS - 1 do
				local x, z, ww, dd = e.x, e.z, e.w, e.d
				local f, g = j / STEPS, 1 / STEPS
				if e.stairUp == "n" then
					z, dd = e.z + e.d * (1 - f - g), e.d * g
				elseif e.stairUp == "s" then
					z, dd = e.z + e.d * f, e.d * g
				elseif e.stairUp == "e" then
					x, ww = e.x + e.w * f, e.w * g
				else
					x, ww = e.x + e.w * (1 - f - g), e.w * g
				end
				local col = if j % 2 == 1 then th.stair else mix(th.stair, WHITE, 0.4)
				local step = box(ctx, steps, ww, DECK_H * (j + 1) / STEPS, dd, col, P(x + ww / 2, 0, z + dd / 2), { name = "Step", t = 0.22 })
				tag(step, "Chase", { Index = j, Count = STEPS, Phase = ph / 10 })
			end
			local cf, size = SkyMapBuilder.wedgeCFrame(e, corner)
			newPart(ctx, F.Colliders, size, cf, WHITE, { name = "Ramp", wedge = true, collide = true, transparency = 1, shadow = false })
		end
	end

	-- sparkles (his loadMap end)
	for _, q in L.sparkles do
		local s = newPart(ctx, F.Ambient, Vector3.new(0.64, 0.64, 0.64), CFrame.new(P(q.x, 1, q.z)) * CFrame.Angles(math.pi / 4, 0, math.pi / 4), hex(q.c), { name = "Sparkle", neon = true, shadow = false })
		tag(s, "Spark", { Phase = q.ph, Speed = q.sp })
	end

	-- his decorate(): fence posts + knobs + light wires, bulbs, bunting, splats, sky props, ambient bits
	local posts: { BasePart } = {}
	for i, p in L.posts do
		local post = box(ctx, F.Decor, 1.2, 10, 1.2, th.wall, P(p[1], -0.7, p[2]), { name = "LightPost", t = 0.18, shadow = false })
		posts[i] = post
		local km = model("Knob", F.Decor)
		box(ctx, km, 2, 2, 2, th.cover, P(p[1], 9.9, p[2]), { name = "Knob", center = true, t = 0.18, shadow = false })
		km.WorldPivot = CFrame.new(P(p[1], 9.9, p[2]))
		tag(km, "Bob", { Amp = 0.35, Speed = 2.2, Phase = (i - 1) * 0.6 })
	end
	for i, p in L.posts do
		local q = L.posts[i % #L.posts + 1]
		wire(posts[i], P(p[1], MapLayout.sag(0), p[2]), P(q[1], MapLayout.sag(1), q[2]), MapLayout.sag(0) - MapLayout.sag(0.5))
	end
	for i, b in L.bulbs do
		local bp = newPart(ctx, F.Decor, Vector3.new(1, 1, 1), CFrame.new(P(b.x, b.y, b.z)), hex(b.c), { name = "Bulb", shape = Enum.PartType.Ball, neon = true, shadow = false })
		tag(bp, "Bulb", { Index = i - 1, BaseColor = hex(b.c) })
	end
	local TEAMC = { hex("#ff8fb0"), hex("#78bfff") }
	for _, bt in L.bunting do
		local col = TEAMC[bt.team + 1]
		local x = bt.x
		local ends: { BasePart } = {}
		for _, z in { bt.z0, bt.z1 } do
			table.insert(ends, box(ctx, F.Decor, 1.4, 15, 1.4, col, P(x, -0.7, z), { name = "FlagPost", t = 0.2, shadow = false }))
			local tm = model("FlagTop", F.Decor)
			box(ctx, tm, 2.6, 2.6, 2.6, WHITE, P(x, 14.6, z), { name = "Top", center = true, t = 0.2, shadow = false })
			tm.WorldPivot = CFrame.new(P(x, 14.6, z))
			tag(tm, "Bob", { Amp = 0.4, Speed = 2, Phase = z })
		end
		for k = 1, bt.nF - 1 do
			local tt = k / bt.nF
			local hang = P(x, MapLayout.bsag(tt), bt.z0 + (bt.z1 - bt.z0) * tt)
			local fm = model("Flag", F.Decor)
			local fc = if k % 2 == 1 then col else WHITE
			-- his ConeGeometry(1, 2.2, 3) flattened to .22 and pointing down, as two wedges (left and right halves)
			for _, side in { -1, 1 } do
				local cf = CFrame.new(hang + Vector3.new(0, -1.1, side * 0.45)) * CFrame.Angles(math.pi, if side > 0 then 0 else math.pi, 0)
				newPart(ctx, fm, Vector3.new(0.44, 2.2, 0.9), cf, fc, { name = "Pennant", wedge = true, shadow = false })
			end
			fm.WorldPivot = CFrame.new(hang)
			tag(fm, "Flag", { Speed = 2.4, Phase = k * 0.5 })
		end
		wire(ends[1], P(x, MapLayout.bsag(0), bt.z0), P(x, MapLayout.bsag(1), bt.z1), MapLayout.bsag(0) - MapLayout.bsag(0.5))
	end
	for _, s in L.splats do
		newPart(ctx, F.Floor, Vector3.new(0.04, 2 * s.r, 2 * s.r), CFrame.new(P(s.x, 0.06, s.z)) * UP, hex(s.c), { name = "Splat", shape = Enum.PartType.Cylinder, transparency = 0.6 })
	end
	for _, q in L.sky do
		local g = skyProp(ctx, F.Sky, map.deco.sky, map.deco.pal, q.i)
		g:ScaleTo(q.s)
		g:PivotTo(CFrame.new(P(q.x, q.y, q.z)) * CFrame.fromEulerAnglesXYZ(q.rx, q.ry, q.rz))
		tag(g, "Float", { Amp = q.amp, Speed = q.sp, Phase = q.ph, Spin = q.rs, RX = q.rx, RY = q.ry })
	end
	local A = map.deco.amb
	for _, q in L.amb do
		local p: BasePart
		if A == "sprinkle" then
			p = newPart(ctx, F.Ambient, Vector3.new(0.4, 1.2, 0.4), CFrame.new(P(q.x, q.y0, q.z)), hex(q.c), { name = "Ambient", sphereMesh = true, shadow = false })
		elseif A == "bubble" then
			p = newPart(ctx, F.Ambient, Vector3.new(1.4, 1.4, 1.4), CFrame.new(P(q.x, q.y0, q.z)), hex("#e3f6ff"), { name = "Ambient", shape = Enum.PartType.Ball, transparency = 0.45, shadow = false })
		elseif A == "confetti" then
			p = newPart(ctx, F.Ambient, Vector3.new(1, 0.7, 0.05), CFrame.new(P(q.x, q.y0, q.z)), hex(q.c), { name = "Ambient", shadow = false })
		else -- paper
			p = newPart(ctx, F.Ambient, Vector3.new(1.6, 0.06, 1.1), CFrame.new(P(q.x, q.y0, q.z)), hex("#fffdf5"), { name = "Ambient", shadow = false })
		end
		tag(p, "Amb", { Span = q.span, Up = q.up, Speed = q.sp, Phase = q.ph, WobbleF = q.wf, WobbleA = q.wa, RotX = q.rx, RotY = q.ry, Scale = q.s })
	end

	-- his buildClouds(): 34 blocky clouds around the map's corner (Math.random there; seeded here)
	local cr = MapLayout.srng(map.id .. ":clouds")
	local function rnd(a: number, b: number): number
		return a + cr() * (b - a)
	end
	for _ = 1, 34 do
		local cm = model("Cloud", F.Sky)
		local n = 3 + math.floor(cr() * 4)
		local baseR = rnd(10, 24)
		local a, d = cr() * math.pi * 2, rnd(260, 820)
		local origin = P(math.cos(a) * d, rnd(-160, 60), math.sin(a) * d)
		for j = 0, n - 1 do
			local r = baseR * rnd(0.6, 1.1)
			box(ctx, cm, r * 1.5, r * 0.9, r * 1.3, WHITE, origin + Vector3.new((j - n / 2) * baseR * 0.9, rnd(-3, 6), rnd(-6, 6)), { name = "Puff", center = true, plain = true, t = r * 0.06, shadow = false })
		end
		cm.WorldPivot = CFrame.new(origin)
		tag(cm, "Cloud", { Speed = rnd(1.5, 4), Phase = cr() * 6, CornerX = corner.X, BuildX = origin.X })
	end

	-- bot lanes (SUPERPROMPT: invisible Route_<n>_<i>)
	for li, route in map.botRoutes do
		for k, pt in route.points do
			local p = newPart(ctx, F.Routes, Vector3.new(1, 1, 1), CFrame.new(P(pt[1], 2, pt[2])), WHITE, { name = `Route_{li}_{k}`, transparency = 1 })
			p:SetAttribute("Lane", li)
			p:SetAttribute("Order", k)
		end
	end

	-- the 1v1 frame ArenaService reads: Origin (floor centre, floorY), Zones, Spawns/PadA + PadB
	if duel then
		local origin = newPart(ctx, root, Vector3.new(1, 1, 1), CFrame.new(P(W / 2, 0, H / 2)), WHITE, { name = "Origin", transparency = 1 })
		root.PrimaryPart = origin
		local zones = folder("Zones", root)
		local function zone(name: string, x0: number, x1: number, z0: number, z1: number)
			newPart(ctx, zones, Vector3.new(x1 - x0, 55, z1 - z0), CFrame.new(P((x0 + x1) / 2, 12.5, (z0 + z1) / 2)), WHITE, { name = name, transparency = 1 })
		end
		-- the 1v1 maps are open (his Duel demo: no halves): each side's "half" is the whole floor (throws, dashes,
		-- ultimates and the bot use it as is), the Neutral band sits far under the map so nobody is ever in it, and
		-- FreeRoam tells the movement guard to keep only the Bounds (CombatService).
		zone("HalfA", 0, W, 0, H)
		zone("HalfB", 0, W, 0, H)
		newPart(ctx, zones, Vector3.new(1, 1, 1), CFrame.new(P(W / 2, -500, H / 2)), WHITE, { name = "Neutral", transparency = 1 })
		zone("Bounds", -2, W + 2, -2, H + 2)
		root:SetAttribute("FreeRoam", true)
		for _, e in map.elements do
			if e.type == "spawnA" or e.type == "spawnB" then
				local c = P(e.x + e.w / 2, 0.1, e.z + e.d / 2)
				local look = P(W / 2, 0.1, H / 2)
				newPart(ctx, F.Spawns, Vector3.new(4, 0.2, 4), CFrame.lookAt(c, Vector3.new(look.X, c.Y, look.Z)), WHITE, { name = if e.type == "spawnA" then "PadA" else "PadB", transparency = 1 })
			end
		end
	end

	root:SetAttribute("MapId", map.id)
	root:SetAttribute("MapCode", map.id)
	root:SetAttribute("MapName", map.name)
	root:SetAttribute("MapSub", map.sub)
	root:SetAttribute("Mode", string.upper(map.mode))
	root:SetAttribute("FootprintX", W)
	root:SetAttribute("FootprintZ", H)
	root.WorldPivot = CFrame.new(P(W / 2, 0, H / 2))
	return root, ctx.parts
end

-- SDTools build: every map of MapData.order into a Folder SquishyMaps (generated root "sky_maps").
function SkyMapBuilder.build(ctx: Generated.BuildContext): Generated.BuildResult
	local warnings: { string } = {}
	local maps = ctx.Shared:FindFirstChild("Maps")
	if maps == nil then
		return { ok = false, root = nil, warnings = warnings, error = "Shared has no Maps folder" }
	end
	local dataModule, layoutModule = maps:FindFirstChild("MapData"), maps:FindFirstChild("MapLayout")
	if dataModule == nil or layoutModule == nil then
		return { ok = false, root = nil, warnings = warnings, error = "Shared.Maps needs MapData and MapLayout" }
	end
	local MapData = dynamicRequire(dataModule :: ModuleScript)
	local MapLayout = dynamicRequire(layoutModule :: ModuleScript)
	local hulls = ReplicatedStorage:FindFirstChild("SquishyOutlineMeshes")
	if hulls == nil then
		table.insert(warnings, "ReplicatedStorage.SquishyOutlineMeshes is missing: the maps have no ink outlines")
	end
	local root = Instance.new("Folder")
	root.Name = SkyMapBuilder.ROOT_NAME
	for index, id in MapData.order do
		local mapModel, parts = SkyMapBuilder.buildMap(MapData.maps[id], MapLayout, SkyMapBuilder.slotCorner(index), hulls)
		mapModel.Parent = root
		if parts > 2500 then
			table.insert(warnings, `{mapModel.Name} has {parts} parts (SUPERPROMPT budget ~2,500)`)
		end
		task.wait() -- keep Studio responsive between maps
	end
	Generated.mark(root, SkyMapBuilder.TARGET, SkyMapBuilder.VERSION)
	return { ok = true, root = root, warnings = warnings, error = nil }
end

return SkyMapBuilder
