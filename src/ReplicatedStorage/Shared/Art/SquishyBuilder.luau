--!strict
-- SquishyBuilder: blueprint -> Model (DESIGN §8.1). Shared: the client runtime (Models/SquishyCache) and the
-- edit-time generators (statue, decor). The server never builds squishy visuals. Data in Art/SquishyBlueprints.
--
-- API
--   SquishyBuilder.build(blueprintId, mode, scale?, options?) -> Model
--     mode "Viewport": every part anchored, no welds (Inspect, inventory/shop cells, box reveal)
--          "World":    Root anchored, the other parts unanchored and welded to Root (projectiles, display, statue)
--          "Held":     nothing anchored, parts welded to Root (Root is welded to the hand by the caller, §9.5)
--     scale (default 1) multiplies the blueprint scale; the product is baked into every Size and position
--     (Model:ScaleTo is never used). The Model is unparented, named after the blueprint, PrimaryPart = "Root" at the
--     origin (the pivot). It faces -Z, so PivotTo(CFrame.lookAt(pos, target)) faces the target.
--     Errors on an unknown id, mode or scale or a broken blueprint (SquishyCache pcalls and shows a placeholder).
--     options.roundedBox: a BasePart to clone for RB parts, or false to force the B fallback (unit tests). Default:
--     ReplicatedStorage.SD_ShapeLibrary.RoundedBox if present, else B with one warning per session.
--     options.blueprint: a Blueprint table to build instead of the map's entry, named blueprintId (unit-test fixtures;
--     never cached).
--   SquishyBuilder.frontalRadius(blueprintId) -> number
--     0.5 * sqrt(W * H) of the body parts' front (X-Y) silhouette bounds at blueprint scale (build scale 1). Body parts
--     only (spec 2026-10-09 §3.3): ears, straws and gills must not shrink the flight model under its hit sphere.
--   SquishyBuilder.flightScale(blueprintId, throwRadius) -> number
--     throwRadius / frontalRadius: the `scale` to build the flight model with, so its frontal radius equals
--     throw.radius (§8.1 #9).
--
-- Construction (§8.1 rules 2-6)
--   Every visual part is a Part (Shape Block) with a SpecialMesh child "Mesh" (E Sphere, B Brick, W Wedge). TRI = two
--   W halves of size (t, h, w/2) at -w/4 / +w/4 with ry +TRI_HALF_YAW_DEG / -TRI_HALF_YAW_DEG ("Λ"; make the constant
--   negative if the smoke screenshot shows "V"). RB = a clone of the shape-library union with Size set and no mesh,
--   always pivot-centred and unrotated. Part.Size carries the full size; mesh Scale = (1, 1, 1) and Offset = 0 as
--   built. Root: invisible 0.2³ Part at the origin, no mesh. Every part: CanCollide/CanTouch/CanQuery false, Massless,
--   SmoothPlastic, CastShadow (visual parts without a `look` only: faces cast no shadow), CollisionGroup "SD_Cosmetic"
--   only when PhysicsService:IsCollisionGroupRegistered says it exists (else Default). No lights, GUIs, scripts,
--   decals, sounds. The squish-face set (look squishEye, squishMouth, tongue) is built with Transparency 1.
--   Face parts (face = F(x, y, embed)): an analytic ray along +Z through (x, y) is cast against every body part placed
--   so far (E: ray-ellipsoid in part space; B: slab test; RB: box ∩ sphere of normalized radius 1.375, or the box for
--   the B fallback). The front-most entry is the surface; the centre is pushed (embed - 0.5) * depth past it along the
--   ray (depth = size.Z, TRI t), so `embed` of the part's depth sits behind the surface and, with embed >= 0.5, the
--   centre lies inside that convex body part. Yaw: the part's -Z looks along the horizontal part of the surface
--   normal; then the part's own rot. face.side "back": the ray runs along -Z from behind instead, so the part sits on
--   the back and looks toward +Z (turned 180°). Attach parts: anchor CFrame * offset * rot.
--
-- Data contract for Anim/SquishDeformer (read from the parts at attach time; the builder never moves a part later):
--   * p, R = each part's CFrame relative to model:GetPivot() (= Root.CFrame);
--   * a part with a SpecialMesh child deforms through mesh Scale/Offset (base values read at attach);
--   * an RB union has no mesh and attribute SD_Shape = "RB": deform through Size (pivot-centred, unrotated);
--   * attribute SD_Rigidity (0-1) on the parts whose blueprint sets one (both TRI halves); missing = 0;
--   * the Root has no mesh and no SD_Shape, so it is ignored.
-- Other attributes (tests, presentation code): part SD_Shape ("E" | "B" | "W" | "RB", the shape actually built),
--   SD_Spec (blueprint part name; TRI halves are named "<name>_HalfL" / "<name>_HalfR"), SD_Body, SD_Face + SD_Embed,
--   SD_AttachedTo, SD_Group ("lid" on the gift box lid, "jaw" on the Rush head's lower jaw); model SD_BlueprintId,
--   SD_BlueprintVersion, SD_Scale (total scale), SD_Mode.
-- Squishy overhaul (spec 2026-10-09 §3.1; read by the rig, the deformer and the contact tests): part SD_Look (the face
--   state role), SD_Section (the hinged section's name; its pivot is in the blueprint's `sections`, × SD_Scale),
--   SD_Contact (Vector3 in the part's unit space: the spec's contact, or the back point (0, 0, 1) of face and attach
--   parts) and SD_ContactWith (the holder: the spec's contactWith, or an attach part's anchor; none = any body part);
--   model SD_HalfExtents (half the body parts' bounds, studs at build scale: where hands meet the surface).
-- Module state: a per-session layout/radius cache and the one-time missing-library warning. Requiring has no side
-- effects; instances are created only inside build().

-- Services

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Log = require(script.Parent.Parent.Util.Log)
local SquishyBlueprints = require(script.Parent.SquishyBlueprints)

-- Types

type Blueprint = SquishyBlueprints.Blueprint
type PartSpec = SquishyBlueprints.PartSpec
type FacePlacement = SquishyBlueprints.FacePlacement
type Section = SquishyBlueprints.Section

export type Mode = "Viewport" | "World" | "Held"
export type BuildOptions = {
	roundedBox: (BasePart | false)?,
	blueprint: Blueprint?,
}

type BuiltShape = "E" | "B" | "W" | "RB"

-- One laid-out part in blueprint units (scale 1), relative to the pivot.
type Laid = {
	name: string,
	spec: PartSpec,
	shape: BuiltShape,
	size: Vector3,
	cframe: CFrame,
}

-- A ray's span through one convex part: entry/exit distances along the ray and the outward normal at the entry.
type Span = { enter: number, exit: number, normal: Vector3 }

-- Constants

local ROOT_NAME = "Root"
local ROOT_SIZE = Vector3.new(0.2, 0.2, 0.2)
local MESH_NAME = "Mesh"
local COSMETIC_GROUP = "SD_Cosmetic"
local SHAPE_LIBRARY_NAME = "SD_ShapeLibrary"
local ROUNDED_BOX_NAME = "RoundedBox"
local RB_SPHERE_RADIUS = 1.375 -- Ball Ø2.75 ∩ Block 2³, in half-size units (§8.1 #6)
local TRI_HALF_YAW_DEG = 90 -- §8.1 #2: one constant to swap if the triangle renders as "V"
local EMBED_MIN = 0.5
local EMBED_MAX = 0.9
local RAY_START = 100 -- far outside every blueprint (blueprint units): z = -100 for the front, +100 for the back
local MIN_HORIZONTAL_NORMAL = 1e-4
local HEX_PATTERN = "^%x%x%x%x%x%x$"
local BACK_POINT = Vector3.new(0, 0, 1) -- the default contact of face and attach parts (unit space)

local ATTR_SHAPE = "SD_Shape"
local ATTR_SPEC = "SD_Spec"
local ATTR_RIGIDITY = "SD_Rigidity"
local ATTR_BODY = "SD_Body"
local ATTR_FACE = "SD_Face"
local ATTR_EMBED = "SD_Embed"
local ATTR_ATTACHED = "SD_AttachedTo"
local ATTR_GROUP = "SD_Group"
local ATTR_LOOK = "SD_Look"
local ATTR_SECTION = "SD_Section"
local ATTR_CONTACT = "SD_Contact"
local ATTR_CONTACT_WITH = "SD_ContactWith"
local ATTR_BLUEPRINT = "SD_BlueprintId"
local ATTR_VERSION = "SD_BlueprintVersion"
local ATTR_SCALE = "SD_Scale"
local ATTR_MODE = "SD_Mode"
local ATTR_HALF_EXTENTS = "SD_HalfExtents"

local MODES: { [string]: boolean } = { Viewport = true, World = true, Held = true }
local LOOKS: { [string]: boolean } = {
	eye = true,
	eyeArc = true,
	shine = true,
	mouth = true,
	mouthOpen = true,
	cheek = true,
	squishEye = true,
	squishMouth = true,
	tongue = true,
	detail = true,
}
local HIDDEN_LOOKS: { [string]: boolean } = { squishEye = true, squishMouth = true, tongue = true } -- the squish set
local AXES: { [string]: boolean } = { X = true, Y = true, Z = true }
local SIDES: { [string]: boolean } = { front = true, back = true }
local BUILT_SHAPES: { [string]: BuiltShape } = { E = "E", B = "B", W = "W", RB = "RB" }
local BODY_SHAPES: { [string]: boolean } = { E = true, B = true, RB = true }
local MESH_TYPES: { [string]: Enum.MeshType } = {
	E = Enum.MeshType.Sphere,
	B = Enum.MeshType.Brick,
	W = Enum.MeshType.Wedge,
}
-- Wedge corners in half-size units: full bottom face, tall edge at the back (+Z), slope facing front-up.
local WEDGE_CORNERS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(1, -1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(1, -1, 1),
	Vector3.new(-1, 1, 1),
	Vector3.new(1, 1, 1),
}

-- Module table

local SquishyBuilder = {}

-- Private

local log = Log.new("SquishyBuilder")
local warnedNoLibrary = false
local layoutCache: { [string]: { Laid } } = {}
local radiusCache: { [string]: number } = {}

local function problem(blueprintId: string, partName: string, message: string): string
	return string.format("[SD][SquishyBuilder] %s.%s: %s", blueprintId, partName, message)
end

local function isPositive(value: unknown): boolean
	return type(value) == "number" and value > 0 and value < math.huge
end

local function isFinite(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isPositiveVector(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local vector = value :: Vector3
	return isPositive(vector.X) and isPositive(vector.Y) and isPositive(vector.Z)
end

local function rotation(rot: Vector3?): CFrame
	if rot == nil then
		return CFrame.identity
	end
	return CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
end

local function getBlueprint(blueprintId: unknown): Blueprint
	local blueprint = if type(blueprintId) == "string" then SquishyBlueprints[blueprintId] else nil
	if blueprint == nil then
		error(string.format("[SD][SquishyBuilder] unknown blueprint %s", tostring(blueprintId)), 3)
	end
	return blueprint
end

local function isUnitPoint(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local point = value :: Vector3
	for _, axis in { point.X, point.Y, point.Z } do
		if not (isFinite(axis) and math.abs(axis) <= 1) then
			return false
		end
	end
	return true
end

-- Checks one part spec; `names` collects the names seen so far (unique per blueprint, TRI halves included).
-- `sections` is the blueprint's section map (empty when it has none).
local function validateSpec(
	blueprintId: string,
	spec: PartSpec,
	names: { [string]: boolean },
	sections: { [string]: Section }
)
	local name = spec.name
	if type(name) ~= "string" or name == "" then
		error(problem(blueprintId, "?", "every part needs a name"), 0)
	end
	local function check(ok: boolean, message: string)
		if not ok then
			error(problem(blueprintId, name, message), 0)
		end
	end
	local shape = spec.shape
	check(shape == "TRI" or BUILT_SHAPES[shape] ~= nil, `unknown shape {tostring(shape)}`)
	local partNames: { string } = if shape == "TRI" then { name .. "_HalfL", name .. "_HalfR" } else { name }
	for _, partName in partNames do
		check(names[partName] == nil and partName ~= ROOT_NAME, `duplicate part name {partName}`)
		names[partName] = true
	end
	check(type(spec.color) == "string" and string.match(spec.color, HEX_PATTERN) ~= nil, "color must be hex RRGGBB")
	if shape == "TRI" then
		check(isPositive(spec.w) and isPositive(spec.h) and isPositive(spec.t), "TRI needs w, h, t > 0")
	else
		check(isPositiveVector(spec.size), "size must be a Vector3 with every axis > 0")
	end
	check(spec.pos == nil or typeof(spec.pos) == "Vector3", "pos must be a Vector3")
	check(spec.rot == nil or typeof(spec.rot) == "Vector3", "rot must be a Vector3 (degrees)")
	local face = spec.face
	if face then
		check(isFinite(face.x) and isFinite(face.y), "face needs finite x and y")
		check(
			type(face.embed) == "number" and face.embed >= EMBED_MIN and face.embed <= EMBED_MAX,
			`face embed must be within {EMBED_MIN}-{EMBED_MAX}`
		)
		check(spec.pos == nil and spec.attach == nil, "a face part takes no pos or attach")
		check(face.side == nil or SIDES[face.side] == true, `face side {tostring(face.side)} is not front or back`)
	end
	local attach = spec.attach
	if attach then
		check(type(attach.to) == "string" and typeof(attach.offset) == "Vector3", "attach needs { to, offset }")
		check(spec.pos == nil and not spec.body, "an attached part takes no pos and is not a body part")
	end
	check(spec.body == nil or type(spec.body) == "boolean", "body must be a boolean")
	check(not spec.body or BODY_SHAPES[shape] == true, "a body part must be E, B or RB")
	local rigidity = spec.rigidity
	check(rigidity == nil or (type(rigidity) == "number" and rigidity >= 0 and rigidity <= 1), "rigidity must be 0-1")
	check(spec.group == nil or type(spec.group) == "string", "group must be a string")
	check(spec.look == nil or LOOKS[spec.look] == true, `unknown look {tostring(spec.look)}`)
	check(spec.section == nil or sections[spec.section] ~= nil, `unknown section {tostring(spec.section)}`)
	check(spec.contact == nil or isUnitPoint(spec.contact), "contact must be a Vector3 in unit space (-1 to 1)")
	check(spec.contactWith == nil or type(spec.contactWith) == "string", "contactWith must be a part name")
	if shape == "RB" then
		local pos = spec.pos or Vector3.zero
		local rot = spec.rot or Vector3.zero
		check(pos.Magnitude == 0 and rot.Magnitude == 0, "an RB must be centred on the pivot with no rotation")
		check(face == nil and attach == nil, "an RB must be centred on the pivot with no rotation")
	end
end

-- Checks the section map and the names the parts point at (after every part passed validateSpec).
local function validateSections(blueprintId: string, blueprint: Blueprint, sections: { [string]: Section })
	local used: { [string]: boolean } = {}
	local specNames: { [string]: boolean } = {}
	for _, spec in blueprint.parts do
		specNames[spec.name] = true
		if spec.section then
			used[spec.section] = true
		end
	end
	for _, spec in blueprint.parts do
		local holder = spec.contactWith
		if holder ~= nil and not specNames[holder] then
			error(problem(blueprintId, spec.name, `contactWith {holder} is not a part of this blueprint`), 0)
		end
	end
	for name, section in sections do
		local function check(ok: boolean, message: string)
			if not ok then
				error(problem(blueprintId, tostring(name), message), 0)
			end
		end
		check(type(name) == "string" and name ~= "" and type(section) == "table", "a section needs a name and a table")
		check(typeof(section.pivot) == "Vector3", "section pivot must be a Vector3")
		local pivot = section.pivot
		check(isFinite(pivot.X) and isFinite(pivot.Y) and isFinite(pivot.Z), "section pivot must be finite")
		check(AXES[section.axis] == true, `section axis {tostring(section.axis)} is not X, Y or Z`)
		check(isPositive(section.amp), "section amp must be > 0")
		check(section.sign == nil or section.sign == 1 or section.sign == -1, "section sign must be 1 or -1")
		check(section.maxDeg == nil or (isPositive(section.maxDeg) and section.maxDeg <= 90), "section maxDeg 0-90")
		local flap = section.flap
		check(
			flap == nil or (isPositive(flap.deg) and (flap.phase == nil or isFinite(flap.phase))),
			"section flap needs deg > 0 and a finite phase"
		)
		check(used[name] == true, "section has no parts")
	end
end

-- Ray math in a part's normalized space (half size = 1): o + t·d, t = distance along the model-space ray.

-- Dot products in doubles: Vector3:Dot rounds to float32, and b² - ac cancels badly 100 studs out (the surface of a
-- thin ellipsoid came out up to ~0.01 off, so thin face parts missed their body).
local function dot(p: Vector3, q: Vector3): number
	return p.X * q.X + p.Y * q.Y + p.Z * q.Z
end

local function sphereSpan(o: Vector3, d: Vector3, radius: number): Span?
	local a = dot(d, d)
	local b = dot(o, d)
	local c = dot(o, o) - radius * radius
	local disc = b * b - a * c
	if a <= 0 or disc < 0 then
		return nil
	end
	local root = math.sqrt(disc)
	local enter = (-b - root) / a
	return { enter = enter, exit = (-b + root) / a, normal = o + d * enter }
end

local function slab(o: number, d: number): (number, number)
	if math.abs(d) < 1e-12 then
		if math.abs(o) > 1 then
			return math.huge, -math.huge -- parallel and outside: empty
		end
		return -math.huge, math.huge
	end
	local t1, t2 = (-1 - o) / d, (1 - o) / d
	if t1 > t2 then
		return t2, t1
	end
	return t1, t2
end

local function boxSpan(o: Vector3, d: Vector3): Span?
	local x0, x1 = slab(o.X, d.X)
	local y0, y1 = slab(o.Y, d.Y)
	local z0, z1 = slab(o.Z, d.Z)
	local enter = math.max(x0, y0, z0)
	local exit = math.min(x1, y1, z1)
	if enter > exit then
		return nil
	end
	local normal = if enter == x0
		then Vector3.new(-math.sign(d.X), 0, 0)
		elseif enter == y0 then Vector3.new(0, -math.sign(d.Y), 0)
		else Vector3.new(0, 0, -math.sign(d.Z))
	return { enter = enter, exit = exit, normal = normal }
end

local function roundedBoxSpan(o: Vector3, d: Vector3): Span?
	local box = boxSpan(o, d)
	local ball = sphereSpan(o, d, RB_SPHERE_RADIUS)
	if box == nil or ball == nil then
		return nil
	end
	local fromBall = ball.enter > box.enter
	local enter = if fromBall then ball.enter else box.enter
	local exit = math.min(box.exit, ball.exit)
	if enter > exit then
		return nil
	end
	return { enter = enter, exit = exit, normal = if fromBall then ball.normal else box.normal }
end

-- The ray through (x, y) along `dir` (+1: from the front along +Z, -1: from the back along -Z) against one body part
-- (blueprint units). The normal comes back unit, in model space.
local function castBody(body: Laid, x: number, y: number, dir: number): Span?
	local half = body.size / 2
	local o = body.cframe:PointToObjectSpace(Vector3.new(x, y, -dir * RAY_START)) / half
	local d = body.cframe:VectorToObjectSpace(Vector3.zAxis * dir) / half
	local span: Span?
	if body.shape == "E" then
		span = sphereSpan(o, d, 1)
	elseif body.shape == "RB" then
		span = roundedBoxSpan(o, d)
	else
		span = boxSpan(o, d)
	end
	if span == nil then
		return nil
	end
	-- A normal in normalized space maps to part space by dividing by the half size (inverse transpose).
	local normal = body.cframe:VectorToWorldSpace(span.normal / half)
	return { enter = span.enter, exit = span.exit, normal = normal.Unit }
end

local function depthOf(spec: PartSpec): number
	if spec.shape == "TRI" then
		return spec.t :: number
	end
	return (spec.size :: Vector3).Z
end

-- §8.1 #6: the face part's CFrame (blueprint units). A back-side part (face.side "back") is placed by the ray from
-- behind, so its surface normal points toward +Z and the yaw below turns it 180°.
local function placeFace(blueprintId: string, spec: PartSpec, bodies: { Laid }): CFrame
	local face = spec.face :: FacePlacement
	local dir = if face.side == "back" then -1 else 1
	local best: Span? = nil
	for _, body in bodies do
		local span = castBody(body, face.x, face.y, dir)
		if span and (best == nil or span.enter < (best :: Span).enter) then
			best = span
		end
	end
	if best == nil then
		error(problem(blueprintId, spec.name, "the face ray hits no body part"), 0)
	end
	local hit = best :: Span
	local push = (face.embed - 0.5) * depthOf(spec)
	if push >= hit.exit - hit.enter then
		error(problem(blueprintId, spec.name, "embed pushes the centre out through the body"), 0)
	end
	local centre = Vector3.new(face.x, face.y, dir * (hit.enter + push - RAY_START))
	-- Yaw only: CFrame.Angles(0, ψ, 0).LookVector = (-sin ψ, 0, -cos ψ), so ψ = atan2(-nx, -nz) looks along the
	-- normal's horizontal part (ψ = 0, straight toward -Z, when the normal is nearly vertical; π on the back).
	local nx, nz = hit.normal.X, hit.normal.Z
	local yaw = if math.sqrt(nx * nx + nz * nz) > MIN_HORIZONTAL_NORMAL
		then math.atan2(-nx, -nz)
		elseif dir < 0 then math.pi
		else 0
	return CFrame.new(centre) * CFrame.Angles(0, yaw, 0) * rotation(spec.rot)
end

-- Appends the part(s) of one spec placed at `frame` (a TRI becomes its two W halves).
local function expand(out: { Laid }, spec: PartSpec, frame: CFrame, useRoundedBox: boolean)
	if spec.shape == "TRI" then
		local w, h, t = spec.w :: number, spec.h :: number, spec.t :: number
		local halfSize = Vector3.new(t, h, w / 2)
		local yaw = math.rad(TRI_HALF_YAW_DEG)
		table.insert(out, {
			name = spec.name .. "_HalfL",
			spec = spec,
			shape = "W",
			size = halfSize,
			cframe = frame * CFrame.new(-w / 4, 0, 0) * CFrame.Angles(0, yaw, 0),
		})
		table.insert(out, {
			name = spec.name .. "_HalfR",
			spec = spec,
			shape = "W",
			size = halfSize,
			cframe = frame * CFrame.new(w / 4, 0, 0) * CFrame.Angles(0, -yaw, 0),
		})
		return
	end
	local shape: BuiltShape = BUILT_SHAPES[spec.shape]
	if shape == "RB" and not useRoundedBox then
		shape = "B"
	end
	table.insert(out, { name = spec.name, spec = spec, shape = shape, size = spec.size :: Vector3, cframe = frame })
end

-- Every part of a blueprint at scale 1, relative to the pivot. Cached per (id, rounded box or fallback) unless
-- `fixture` (options.blueprint) is set.
local function layout(blueprintId: string, blueprint: Blueprint, useRoundedBox: boolean, fixture: boolean?): { Laid }
	local key = blueprintId .. (if useRoundedBox then "|RB" else "|B")
	local cached = if fixture then nil else layoutCache[key]
	if cached then
		return cached
	end
	if not isPositive(blueprint.scale) or type(blueprint.parts) ~= "table" then
		error(problem(blueprintId, "(blueprint)", "needs scale > 0 and a parts list"), 0)
	end
	local sections: { [string]: Section } = blueprint.sections or {}
	local names: { [string]: boolean } = {}
	for _, spec in blueprint.parts do
		validateSpec(blueprintId, spec, names, sections)
	end
	validateSections(blueprintId, blueprint, sections)

	local out: { Laid } = {}
	local bodies: { Laid } = {}
	local frames: { [string]: CFrame } = {} -- spec name -> placed frame (attach anchors)
	local function add(spec: PartSpec, frame: CFrame)
		frames[spec.name] = frame
		local first = #out + 1
		expand(out, spec, frame, useRoundedBox)
		if spec.body then
			for i = first, #out do
				table.insert(bodies, out[i])
			end
		end
	end

	-- Plain parts first, then face and attach parts in list order (§ module header of SquishyBlueprints).
	for _, spec in blueprint.parts do
		if spec.face == nil and spec.attach == nil then
			add(spec, CFrame.new(spec.pos or Vector3.zero) * rotation(spec.rot))
		end
	end
	for _, spec in blueprint.parts do
		local attach = spec.attach
		if spec.face then
			add(spec, placeFace(blueprintId, spec, bodies))
		elseif attach then
			local anchor: CFrame? = frames[attach.to]
			if anchor == nil then
				error(problem(blueprintId, spec.name, `attach anchor {attach.to} must be placed before it`), 0)
			end
			add(spec, (anchor :: CFrame) * CFrame.new(attach.offset) * rotation(spec.rot))
		end
	end

	if not fixture then
		layoutCache[key] = out
	end
	return out
end

-- Axis-aligned bounds of one laid part (exact for E, B, RB and W).
local function partBounds(laid: Laid): (Vector3, Vector3)
	local cf = laid.cframe
	local half = laid.size / 2
	if laid.shape == "W" then
		local minX, minY, minZ = math.huge, math.huge, math.huge
		local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
		for _, corner in WEDGE_CORNERS do
			local p = cf:PointToWorldSpace(corner * half)
			minX, minY, minZ = math.min(minX, p.X), math.min(minY, p.Y), math.min(minZ, p.Z)
			maxX, maxY, maxZ = math.max(maxX, p.X), math.max(maxY, p.Y), math.max(maxZ, p.Z)
		end
		return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
	end
	local x, y, z = cf.XVector * half.X, cf.YVector * half.Y, cf.ZVector * half.Z
	local extent: Vector3
	if laid.shape == "E" then
		extent = Vector3.new(
			math.sqrt(x.X * x.X + y.X * y.X + z.X * z.X),
			math.sqrt(x.Y * x.Y + y.Y * y.Y + z.Y * z.Y),
			math.sqrt(x.Z * x.Z + y.Z * y.Z + z.Z * z.Z)
		)
	else
		extent = Vector3.new(
			math.abs(x.X) + math.abs(y.X) + math.abs(z.X),
			math.abs(x.Y) + math.abs(y.Y) + math.abs(z.Y),
			math.abs(x.Z) + math.abs(y.Z) + math.abs(z.Z)
		)
	end
	return cf.Position - extent, cf.Position + extent
end

local function boundsSize(parts: { Laid }): Vector3
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, laid in parts do
		local lo, hi = partBounds(laid)
		minX, minY, minZ = math.min(minX, lo.X), math.min(minY, lo.Y), math.min(minZ, lo.Z)
		maxX, maxY, maxZ = math.max(maxX, hi.X), math.max(maxY, hi.Y), math.max(maxZ, hi.Z)
	end
	return Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
end

-- The body parts of a layout (every part when it has none).
local function bodiesOf(parts: { Laid }): { Laid }
	local bodies: { Laid } = {}
	for _, laid in parts do
		if laid.spec.body then
			table.insert(bodies, laid)
		end
	end
	return if #bodies > 0 then bodies else parts
end

local function needsRoundedBox(blueprint: Blueprint): boolean
	for _, spec in blueprint.parts do
		if spec.shape == "RB" then
			return true
		end
	end
	return false
end

-- The RB template to clone, or nil for the B fallback (§8.1 #2).
local function roundedBoxTemplate(options: BuildOptions?): BasePart?
	local override = if options then options.roundedBox else nil
	if override == false then
		return nil
	end
	if override ~= nil then
		if typeof(override) ~= "Instance" or not override:IsA("BasePart") then
			error("[SD][SquishyBuilder] options.roundedBox must be a BasePart or false", 3)
		end
		return override
	end
	local library = ReplicatedStorage:FindFirstChild(SHAPE_LIBRARY_NAME)
	local template = if library then library:FindFirstChild(ROUNDED_BOX_NAME) else nil
	if template and template:IsA("BasePart") then
		return template
	end
	if not warnedNoLibrary then
		warnedNoLibrary = true
		log:warn(
			`ReplicatedStorage.{SHAPE_LIBRARY_NAME}.{ROUNDED_BOX_NAME} is missing (run the "shapes" generator);`
				.. " rounded boxes are built as plain boxes"
		)
	end
	return nil
end

local function applyFlags(part: BasePart, anchored: boolean, collisionGroup: string?)
	part.Anchored = anchored
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false -- after CanCollide (CanQuery false needs a non-colliding part)
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.CastShadow = true
	if collisionGroup then
		part.CollisionGroup = collisionGroup
	end
end

local function makePart(laid: Laid, scale: number, template: BasePart?): BasePart
	local part: BasePart
	if laid.shape == "RB" then
		local clone = (template :: BasePart):Clone() :: BasePart?
		if clone == nil then
			error(problem("?", laid.name, "the RoundedBox template cannot be cloned (Archivable false)"), 0)
		end
		part = clone :: BasePart
		part:ClearAllChildren()
		for _, tag in part:GetTags() do
			part:RemoveTag(tag)
		end
		for attribute in part:GetAttributes() do
			part:SetAttribute(attribute, nil)
		end
	else
		local block = Instance.new("Part")
		block.Shape = Enum.PartType.Block
		local mesh = Instance.new("SpecialMesh")
		mesh.Name = MESH_NAME
		mesh.MeshType = MESH_TYPES[laid.shape]
		mesh.Scale = Vector3.one
		mesh.Offset = Vector3.zero
		mesh.Parent = block
		part = block
	end
	local spec = laid.spec
	part.Name = laid.name
	part.Size = laid.size * scale
	part.CFrame = CFrame.new(laid.cframe.Position * scale) * laid.cframe.Rotation
	part.Color = Color3.fromHex(spec.color)
	part.Transparency = if spec.look and HIDDEN_LOOKS[spec.look] then 1 else 0
	part:SetAttribute(ATTR_SHAPE, laid.shape)
	part:SetAttribute(ATTR_SPEC, spec.name)
	if spec.rigidity ~= nil then
		part:SetAttribute(ATTR_RIGIDITY, spec.rigidity)
	end
	if spec.body then
		part:SetAttribute(ATTR_BODY, true)
	end
	if spec.face then
		part:SetAttribute(ATTR_FACE, true)
		part:SetAttribute(ATTR_EMBED, spec.face.embed)
	end
	if spec.attach then
		part:SetAttribute(ATTR_ATTACHED, spec.attach.to)
	end
	if spec.group then
		part:SetAttribute(ATTR_GROUP, spec.group)
	end
	if spec.look then
		part:SetAttribute(ATTR_LOOK, spec.look)
	end
	if spec.section then
		part:SetAttribute(ATTR_SECTION, spec.section)
	end
	local contact = spec.contact or (if spec.face or spec.attach then BACK_POINT else nil)
	if contact then
		part:SetAttribute(ATTR_CONTACT, contact)
	end
	local holder = spec.contactWith or (if spec.attach then spec.attach.to else nil)
	if holder then
		part:SetAttribute(ATTR_CONTACT_WITH, holder)
	end
	return part
end

-- Public

function SquishyBuilder.build(blueprintId: string, mode: Mode, scale: number?, options: BuildOptions?): Model
	local fixture = if options then options.blueprint else nil
	local blueprint = if fixture then fixture else getBlueprint(blueprintId)
	if MODES[mode] ~= true then
		error(string.format("[SD][SquishyBuilder] unknown build mode %s", tostring(mode)), 2)
	end
	local factor = if scale == nil then 1 else scale
	if not isPositive(factor) then
		error(string.format("[SD][SquishyBuilder] scale must be a finite number > 0 (got %s)", tostring(scale)), 2)
	end
	local total = blueprint.scale * factor
	local template = if needsRoundedBox(blueprint) then roundedBoxTemplate(options) else nil
	local parts = layout(blueprintId, blueprint, template ~= nil, fixture ~= nil)
	local collisionGroup = if PhysicsService:IsCollisionGroupRegistered(COSMETIC_GROUP) then COSMETIC_GROUP else nil

	local model = Instance.new("Model")
	model.Name = blueprintId
	local root = Instance.new("Part")
	root.Name = ROOT_NAME
	root.Shape = Enum.PartType.Block
	root.Size = ROOT_SIZE
	root.CFrame = CFrame.identity
	root.Transparency = 1
	applyFlags(root, mode ~= "Held", collisionGroup)
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	for _, laid in parts do
		local part = makePart(laid, total, template)
		applyFlags(part, mode == "Viewport", collisionGroup)
		part.CastShadow = laid.spec.look == nil -- faces cast no shadow (§3.1)
		if mode ~= "Viewport" then
			-- A Weld with an explicit C0, never a WeldConstraint: a WeldConstraint captures the offset when the model
			-- enters the DataModel, and HeldSquishyController welds Root to the hand first, which left every part
			-- ~6.7 studs off the hand (play-checked 2026-10-05). C0 here is exact whatever the parenting order.
			local weld = Instance.new("Weld")
			weld.Name = "SD_PartWeld"
			weld.Part0 = root
			weld.Part1 = part
			weld.C0 = root.CFrame:ToObjectSpace(part.CFrame)
			weld.C1 = CFrame.identity
			weld.Parent = part
		end
		part.Parent = model
	end

	model:SetAttribute(ATTR_BLUEPRINT, blueprintId)
	model:SetAttribute(ATTR_VERSION, blueprint.version)
	model:SetAttribute(ATTR_SCALE, total)
	model:SetAttribute(ATTR_MODE, mode)
	model:SetAttribute(ATTR_HALF_EXTENTS, boundsSize(bodiesOf(parts)) * total / 2)
	return model
end

function SquishyBuilder.frontalRadius(blueprintId: string): number
	local cached = radiusCache[blueprintId]
	if cached then
		return cached
	end
	local blueprint = getBlueprint(blueprintId)
	local size = boundsSize(bodiesOf(layout(blueprintId, blueprint, true))) * blueprint.scale
	local radius = 0.5 * math.sqrt(size.X * size.Y)
	radiusCache[blueprintId] = radius
	return radius
end

function SquishyBuilder.flightScale(blueprintId: string, throwRadius: number): number
	if not isPositive(throwRadius) then
		error(string.format("[SD][SquishyBuilder] throwRadius must be > 0 (got %s)", tostring(throwRadius)), 2)
	end
	return throwRadius / SquishyBuilder.frontalRadius(blueprintId)
end

return SquishyBuilder
