--!strict
-- SoftShell (client only). Spec phase2-squeeze §3.2: the knead shell's EditableMesh and MeshPart, built from an
-- Anim/ShellGeometry shell and written each frame from Anim/SoftBody. Inspect's knead screen (Controllers/
-- KneadController) owns one at a time (MeshQuota key "soft").
--
--   SoftShell.writeMesh(mesh, shell, flipV) -> Ids   pure over anything with AddVertex, AddNormal, AddUV, AddTriangle,
--     SetFaceNormals and SetFaceUVs (unit-tested with a stand-in): every shell vertex (the 24 bounds anchors included)
--     at its rest position minus shell.center (so the mesh's bounds centre is its origin, whatever convention the
--     MeshPart follows), one automatic normal per vertex (AddNormal with no value: the engine recomputes it as the
--     vertices move, spec §3.2), every UV (v -> 1 - v with flipV, Config.Knead.shell.uvFlipV), every triangle with its
--     vertices' normals and its face-corner UVs. Ids: vertex[i] = the mesh's id of shell vertex i, triangle[faceId] =
--     the shell triangle.
--   SoftShell.batch(ids, values, vertexIds, written, count, px, py, pz, center) -> number   fills the reused id and
--     position lists of one frame's moved vertices (shown position minus center) and trims them to `count`
--   SoftShell.create(shell, flipV) -> (Handle?, reason?)   yields (AssetService:CreateMeshPartAsync); any failure
--     cleans up and answers nil and the reason (the caller falls back). The MeshPart "SD_SoftShell" is unparented,
--     anchored, never collides, touches or is queried, casts no shadow, SmoothPlastic; the caller places it at the
--     model pivot × CFrame(shell.center) and gives it its texture.
--   handle:write(written, count, px, py, pz)   one frame: EditableMesh:BatchSetValues on the moved vertices (one call),
--     else SetPosition each (once BatchSetValues fails, for the rest of the session: verify in Studio)
--   handle:raycast(origin, direction) -> (triangle?, point?)   EditableMesh:RaycastLocal in mesh space (the direction's
--     length is the reach); the shell triangle hit (never a bounds anchor) and the point. Its barycentric output is not
--     read: the caller weighs the point against the triangle's current corners (KneadMath.barycentric).
--   handle:destroy()   the MeshPart and the EditableMesh (a destroyed mesh blanks its part, SuperMesh.luau:17-18)

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Log = require(ReplicatedStorage.Shared.Util.Log)
local ShellGeometry = require(script.Parent.ShellGeometry)

type Shell = ShellGeometry.Shell

export type Ids = {
	vertex: { number },
	triangle: { [number]: number },
}

type HandleData = {
	part: MeshPart,
	mesh: any,
	_shell: Shell,
	_ids: Ids,
	_center: Vector3,
	_batchIds: { number },
	_batchValues: { Vector3 },
	_batch: boolean,
	_dead: boolean,
}

local PART_NAME = "SD_SoftShell"
local MESH_OPTIONS = { -- as JellyRippleController's skin and Anim/SuperMesh
	CollisionFidelity = Enum.CollisionFidelity.Box,
	RenderFidelity = Enum.RenderFidelity.Precise,
}

local HandleClass = {}
HandleClass.__index = HandleClass

export type Handle = typeof(setmetatable({} :: HandleData, HandleClass))

local SoftShell = {}

local log = Log.new("SoftShell")
local batchWarned = false

-- Public: pure

function SoftShell.writeMesh(mesh: any, shell: Shell, flipV: boolean): Ids
	local total = shell.vertexTotal
	local center = shell.center
	local px, py, pz = shell.px, shell.py, shell.pz
	local vertexIds: { number } = table.create(total, 0)
	local normalIds: { number } = table.create(total, 0)
	for i = 1, total do
		vertexIds[i] = mesh:AddVertex(Vector3.new(px[i], py[i], pz[i]) - center)
		normalIds[i] = mesh:AddNormal()
	end
	local uvIds: { number } = table.create(shell.uvCount, 0)
	local uvs = shell.uvs
	for j = 1, shell.uvCount do
		local v = uvs[2 * j]
		uvIds[j] = mesh:AddUV(Vector2.new(uvs[2 * j - 1], if flipV then 1 - v else v))
	end
	local triangles: { [number]: number } = {}
	local tris, faceUVs = shell.tris, shell.faceUVs
	for k = 1, shell.triTotal do
		local a, b, c = tris[3 * k - 2], tris[3 * k - 1], tris[3 * k]
		local face = mesh:AddTriangle(vertexIds[a], vertexIds[b], vertexIds[c])
		mesh:SetFaceNormals(face, { normalIds[a], normalIds[b], normalIds[c] })
		mesh:SetFaceUVs(face, { uvIds[faceUVs[3 * k - 2]], uvIds[faceUVs[3 * k - 1]], uvIds[faceUVs[3 * k]] })
		triangles[face] = k
	end
	return { vertex = vertexIds, triangle = triangles }
end

function SoftShell.batch(
	ids: { number },
	values: { Vector3 },
	vertexIds: { number },
	written: { number },
	count: number,
	px: { number },
	py: { number },
	pz: { number },
	center: Vector3
): number
	local cx, cy, cz = center.X, center.Y, center.Z
	for k = 1, count do
		local i = written[k]
		ids[k] = vertexIds[i]
		values[k] = Vector3.new(px[i] - cx, py[i] - cy, pz[i] - cz)
	end
	for k = #ids, count + 1, -1 do
		ids[k] = nil
		values[k] = nil
	end
	return count
end

-- Public: the mesh

function SoftShell.create(shell: Shell, flipV: boolean): (Handle?, string?)
	local mesh: any = nil
	local ok, result = pcall(function(): any
		mesh = AssetService:CreateEditableMesh()
		if mesh == nil then
			error("CreateEditableMesh returned nil", 0)
		end
		local ids = SoftShell.writeMesh(mesh, shell, flipV)
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh), MESH_OPTIONS)
		if part == nil then
			error("CreateMeshPartAsync returned nil", 0)
		end
		return { ids = ids, part = part }
	end)
	if not ok then
		if mesh ~= nil then
			pcall(function()
				mesh:Destroy()
			end)
		end
		return nil, tostring(result)
	end
	local part: MeshPart = result.part
	part.Name = PART_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.new(1, 1, 1)
	local data: HandleData = {
		part = part,
		mesh = mesh,
		_shell = shell,
		_ids = result.ids,
		_center = shell.center,
		_batchIds = {},
		_batchValues = {},
		_batch = true,
		_dead = false,
	}
	return setmetatable(data, HandleClass), nil
end

function HandleClass.write(
	self: Handle,
	written: { number },
	count: number,
	px: { number },
	py: { number },
	pz: { number }
)
	if self._dead or count <= 0 then
		return
	end
	local ids, values = self._batchIds, self._batchValues
	local n = SoftShell.batch(ids, values, self._ids.vertex, written, count, px, py, pz, self._center)
	local mesh = self.mesh
	if self._batch then
		local ok, err = pcall(function()
			mesh:BatchSetValues(ids, values)
		end)
		if ok then
			return
		end
		self._batch = false
		if not batchWarned then
			batchWarned = true
			log:warn("EditableMesh:BatchSetValues failed, writing vertex by vertex:", err)
		end
	end
	for k = 1, n do
		mesh:SetPosition(ids[k], values[k])
	end
end

function HandleClass.raycast(self: Handle, origin: Vector3, direction: Vector3): (number?, Vector3?)
	if self._dead then
		return nil, nil
	end
	local mesh = self.mesh
	local ok, a, b = pcall(function(): (any, any)
		return mesh:RaycastLocal(origin, direction)
	end)
	if not ok then
		return nil, nil
	end
	local point: Vector3?, face: number? = nil, nil
	if typeof(a) == "Vector3" and type(b) == "number" then
		point, face = a, b
	elseif type(a) == "number" and typeof(b) == "Vector3" then
		face, point = a, b
	end
	if face == nil or point == nil then
		return nil, nil
	end
	local triangle = self._ids.triangle[face]
	if triangle == nil or triangle > self._shell.triCount then
		return nil, nil -- a bounds anchor
	end
	return triangle, point
end

function HandleClass.destroy(self: Handle)
	if self._dead then
		return
	end
	self._dead = true
	local mesh = self.mesh
	pcall(function()
		self.part:Destroy()
	end)
	pcall(function()
		mesh:Destroy()
	end)
end

return SoftShell
