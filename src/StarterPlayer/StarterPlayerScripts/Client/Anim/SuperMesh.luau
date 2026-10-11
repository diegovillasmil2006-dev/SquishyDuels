--!strict
-- SuperMesh (client only): the 3D Lab's rounded-block shape for the first-person arms (spec 2026-10-11 §3.2), a
-- superellipsoid of exponent n built at runtime (nothing is uploaded).
--
-- Geometry (design: kit.js:41-71, fp.js:65): three.js's SphereGeometry(1, 28, 20) vertex grid (Config.FirstPerson.arm.
-- segments; (28 + 1) × (20 + 1) vertices with the seam and pole duplicates, 28 × (2 · 20 - 2) triangles in three's
-- index order), each unit direction d moved to d · superR(d) (kit.js:41-46, called as fp.js:65 does: n = m) with the
-- half-extents a = b = c = 0.5: the unit shape, size 1 × 1 × 1, so a part of Size s spans s (a scaled superellipsoid
-- keeps its exponent; the design builds each part at its own size, so only where the 609 vertices sit on the same
-- surface differs). Normals: the design's two tangent steps of e = 0.003 (kit.js:51-66). Front faces are
-- counter-clockwise seen from outside, as in three.js; the outline hull is the same mesh with every triangle reversed
-- and the same normals (spec §3.2: an inverted hull, not DoubleSided).
--
-- Mesh path: prepare() makes, once per session, ONE shape mesh of exponent MESH_EXPONENT (the hand's 7) and its hull
-- (AssetService:CreateEditableMesh, writeMesh, then CreateMeshPartAsync(Content.fromObject)) and keeps each MeshPart as
-- a template; newPart clones it for every n, so the thumb (design 5) and the cuff (design 8) take the hand's roundness.
-- Why: the client's EditableMesh budget held about 8 meshes on a PC in Studio (2026-10-11), shared with the giant pads
-- (3) and the jelly ripple (1); one mesh per exponent (6) pushed two of those onto their path B. A mesh must stay alive
-- while its MeshPart shows (destroying it blanks the part, Studio 2026-10-11). Any error or nil on the way (no
-- EditableMesh access, the device's budget, an engine error, a copy that lost its mesh) turns the path off for the
-- session with one warning,
-- and every part is the fallback: a clone of ReplicatedStorage.SD_ShapeLibrary.RoundedBox, else a Block. prepare()
-- yields (CreateMeshPartAsync); newPart never does: the first newPart before any prepare() starts it in its own thread
-- and gets the fallback, so a caller that wants the mesh on its first parts runs prepare() first (from a start()).
--
-- API
--   SuperMesh.geometry(n) -> Geometry       pure; cached per n for the session (1-based indices)
--   SuperMesh.hullTriangles(geometry) -> { { number } }   the triangles with reversed winding (a new list)
--   SuperMesh.writeMesh(mesh, geometry, hull?)   adds the geometry to an EditableMesh (or anything with its AddVertex,
--       AddNormal, AddTriangle and SetFaceNormals): one vertex and one normal per position, each triangle with its
--       three normals; the hull's triangles reversed
--   SuperMesh.prepare() -> boolean          yields; tries the mesh path once per session (later and concurrent calls
--       wait for that try) and answers meshReady()
--   SuperMesh.meshReady() -> boolean        the mesh path works this session
--   SuperMesh.newPart(n, size, hull?) -> BasePart?   an unparented part of the shape sized `size` (studs): with the mesh
--       path a MeshPart (the hull when `hull`); without it the fallback, and nil for a hull (no outline without the mesh
--       path). Every part is anchored, massless, SmoothPlastic, never collides, touches or is queried and casts no
--       shadow; colour and name are the caller's.
-- Require direction: Shared Config and Util/Log only.

-- Services

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)

-- Types

export type Geometry = {
	n: number,
	positions: { Vector3 },
	normals: { Vector3 },
	triangles: { { number } },
}

type MeshState = "untried" | "building" | "ready" | "failed"

-- Constants

local SEGMENTS = Config.FirstPerson.arm.segments -- design: fp.js:65
local HALF = 0.5 -- the unit shape's half-extents
local TANGENT_STEP = 0.003 -- design: kit.js:52
local POLE_DOT = 0.95 -- design: kit.js:56
local MESH_EXPONENT = 7 -- design: fp.js:65 (rb's default n, the hand, forearm and sleeve); see the header
local SHAPE_LIBRARY_NAME = "SD_ShapeLibrary"
local ROUNDED_BOX_NAME = "RoundedBox"
local MESH_OPTIONS = { -- as JellyRippleController's skin
	CollisionFidelity = Enum.CollisionFidelity.Box,
	RenderFidelity = Enum.RenderFidelity.Precise,
}

-- Module table

local SuperMesh = {}

-- Private

local log = Log.new("SuperMesh")
local cache: { [number]: Geometry } = {}
local state: MeshState = "untried"
local templates: { [string]: MeshPart } = {} -- by templateKey
local editables: { any } = {} -- every EditableMesh made, kept for the session

-- The design's superR (kit.js:41-45).
local function superR(d: Vector3, a: number, b: number, c: number, n: number, m: number): number
	local xz = (math.abs(d.X / a) ^ n + math.abs(d.Z / c) ^ n) ^ (m / n)
	local yy = math.abs(d.Y / b) ^ m
	return (xz + yy) ^ (-1 / m)
end

-- superF (kit.js:46) as fp.js:65 calls it (n = m), for the unit shape.
local function surface(d: Vector3, n: number): Vector3
	return d * superR(d, HALF, HALF, HALF, n, n)
end

local function roundedBox(): BasePart?
	local library = ReplicatedStorage:FindFirstChild(SHAPE_LIBRARY_NAME)
	local template = if library then library:FindFirstChild(ROUNDED_BOX_NAME) else nil
	return if template and template:IsA("BasePart") then template else nil
end

-- Every exponent shares the one shape (and the one hull): see the header.
local function templateKey(_n: number, hull: boolean?): string
	return if hull then `{MESH_EXPONENT}_outline` else tostring(MESH_EXPONENT)
end

-- One template MeshPart: the unit shape of exponent n (or its hull) in a new EditableMesh. Errors on any failure.
local function buildTemplate(n: number, hull: boolean)
	local editable: any = AssetService:CreateEditableMesh()
	if editable == nil then
		error("CreateEditableMesh returned nil", 0)
	end
	table.insert(editables, editable)
	SuperMesh.writeMesh(editable, SuperMesh.geometry(n), hull)
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(editable), MESH_OPTIONS)
	if part == nil then
		error("CreateMeshPartAsync returned nil", 0)
	end
	templates[templateKey(n, hull)] = part
	-- newPart clones the template: the copy must still show this mesh.
	local probe = part:Clone()
	local kept = (probe.MeshContent :: any).Object == editable
	probe:Destroy()
	if not kept then
		error("a copy of the MeshPart lost its EditableMesh", 0)
	end
end

local function buildAll()
	buildTemplate(MESH_EXPONENT, false)
	buildTemplate(MESH_EXPONENT, true)
end

local function discardAll()
	for key, part in templates do
		part:Destroy()
		templates[key] = nil
	end
	for _, editable in editables do
		pcall(function()
			editable:Destroy()
		end)
	end
	table.clear(editables)
end

local function finish(part: BasePart, size: Vector3): BasePart
	part.Size = size
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	return part
end

-- Public

function SuperMesh.geometry(n: number): Geometry
	local cached = cache[n]
	if cached then
		return cached
	end
	local ws, hs = SEGMENTS[1], SEGMENTS[2]
	local positions, normals, triangles = {}, {}, {}
	local grid: { { number } } = {}
	for iy = 0, hs do
		local row = {}
		local theta = math.pi * iy / hs
		for ix = 0, ws do
			local phi = 2 * math.pi * ix / ws
			-- three.js SphereGeometry's vertex (radius 1), then the design's warp (kit.js:53-66).
			local d =
				Vector3.new(-math.cos(phi) * math.sin(theta), math.cos(theta), math.sin(phi) * math.sin(theta)).Unit
			local up = if math.abs(d.Y) > POLE_DOT then Vector3.xAxis else Vector3.yAxis
			local t1 = up:Cross(d).Unit
			local t2 = d:Cross(t1)
			local p = surface(d, n)
			local a = surface((d + t1 * TANGENT_STEP).Unit, n) - p
			local b = surface((d + t2 * TANGENT_STEP).Unit, n) - p
			local normal = a:Cross(b)
			if normal.Magnitude < 1e-8 then -- design: kit.js:63 (lengthSq < 1e-16)
				normal = d
			end
			table.insert(positions, p)
			table.insert(normals, normal.Unit)
			table.insert(row, #positions)
		end
		grid[iy] = row
	end
	-- three.js SphereGeometry's index order (no degenerate triangle at the poles).
	for iy = 0, hs - 1 do
		for ix = 1, ws do
			local a, b = grid[iy][ix + 1], grid[iy][ix]
			local c, d = grid[iy + 1][ix], grid[iy + 1][ix + 1]
			if iy ~= 0 then
				table.insert(triangles, { a, b, d })
			end
			if iy ~= hs - 1 then
				table.insert(triangles, { b, c, d })
			end
		end
	end
	local geometry = { n = n, positions = positions, normals = normals, triangles = triangles }
	cache[n] = geometry
	return geometry
end

function SuperMesh.hullTriangles(geometry: Geometry): { { number } }
	local out = table.create(#geometry.triangles)
	for i, tri in geometry.triangles do
		out[i] = { tri[1], tri[3], tri[2] }
	end
	return out
end

function SuperMesh.writeMesh(mesh: any, geometry: Geometry, hull: boolean?)
	local count = #geometry.positions
	local vertexIds: { number } = table.create(count, 0)
	local normalIds: { number } = table.create(count, 0)
	for i, p in geometry.positions do
		vertexIds[i] = mesh:AddVertex(p)
		normalIds[i] = mesh:AddNormal(geometry.normals[i])
	end
	local triangles: { { number } } = if hull then SuperMesh.hullTriangles(geometry) else geometry.triangles
	for _, tri in triangles do
		local a, b, c = tri[1], tri[2], tri[3]
		local face = mesh:AddTriangle(vertexIds[a], vertexIds[b], vertexIds[c])
		mesh:SetFaceNormals(face, { normalIds[a], normalIds[b], normalIds[c] })
	end
end

function SuperMesh.prepare(): boolean
	if state == "untried" then
		state = "building"
		local ok, err = pcall(buildAll :: () -> any)
		if ok then
			state = "ready"
		else
			discardAll()
			state = "failed"
			log:warn(`EditableMesh path off for this session, the arms use the rounded box: {err}`)
		end
	end
	while state == "building" do
		task.wait()
	end
	return state == "ready"
end

function SuperMesh.meshReady(): boolean
	return state == "ready"
end

function SuperMesh.newPart(n: number, size: Vector3, hull: boolean?): BasePart?
	assert(type(n) == "number" and n >= 1, "[SD][SuperMesh] n must be a number >= 1")
	if state == "untried" then
		task.spawn(SuperMesh.prepare)
	end
	local template = if state == "ready" then templates[templateKey(n, hull)] else nil
	if template then
		return finish(template:Clone(), size)
	elseif hull then
		return nil -- no outline without the mesh path
	end
	local box = roundedBox()
	if box then
		return finish(box:Clone(), size)
	end
	local block = Instance.new("Part")
	block.Shape = Enum.PartType.Block
	return finish(block, size)
end

return SuperMesh
