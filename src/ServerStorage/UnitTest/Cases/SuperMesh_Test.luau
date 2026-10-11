--!strict
-- SuperMesh_Test: unit tests for StarterPlayerScripts.Client.Anim.SuperMesh (spec 2026-10-11 §3.2). Server only
-- (ServerStorage.UnitTest). Pure geometry, a recording stand-in for an EditableMesh, and parts (nothing is parented):
--   * geometry(n) is the design's unit superellipsoid (kit.js:41-71): three's SphereGeometry grid of 28 × 20 segments
--     (609 vertices, 1064 triangles) in three's index order, every vertex on |2x|^n + |2y|^n + |2z|^n = 1 (half-extents
--     exactly 0.5), unit normals pointing out along the surface's gradient, and the same table for the same n;
--   * hullTriangles reverses every triangle's winding;
--   * writeMesh puts a geometry into an EditableMesh: one vertex and one normal per position, every triangle with its
--     three normals; the hull with every triangle reversed (same normals);
--   * newPart(n, size) gives an anchored, never colliding, touching or queried, shadowless SmoothPlastic part of that
--     size (the fallback while meshReady() is false); newPart(n, size, true) gives no hull without the mesh path;
--   * prepare() tries the mesh path once per session (offline it is never there: no EditableMesh in Lune); with it,
--     newPart gives MeshParts, the hull too, all on one shape mesh and one hull mesh (the EditableMesh budget).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local SuperMesh = t.requireClient("Anim/SuperMesh")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local SEGMENTS = Config.FirstPerson.arm.segments

	t.test("geometry(n): the 28 × 20 superellipsoid of exponent n, half-extents 0.5, normals out", function()
		expect.deepEqual(SEGMENTS, { 28, 20 })
		for _, n in { 5, 7, 8 } do
			local g = SuperMesh.geometry(n)
			expect.equal(#g.positions, (28 + 1) * (20 + 1))
			expect.equal(#g.normals, #g.positions)
			expect.equal(#g.triangles, 28 * (2 * 20 - 2))
			local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
			for i, p in g.positions do
				local f = math.abs(2 * p.X) ^ n + math.abs(2 * p.Y) ^ n + math.abs(2 * p.Z) ^ n
				expect.near(f, 1, 1e-5) -- Vector3 holds float32
				local normal = g.normals[i]
				expect.near(normal.Magnitude, 1, 1e-6)
				expect.truthy(normal:Dot(p) > 0)
				lo, hi = lo:Min(p), hi:Max(p)
			end
			-- The poles and the equator's four grid points reach the half-extents: the unit mesh is exactly 1 × 1 × 1, so
			-- MeshPart.Size is the part's size.
			expect.near(hi.Y, 0.5, 1e-9)
			expect.near(lo.Y, -0.5, 1e-9)
			expect.near(hi.X, 0.5, 1e-6)
			expect.near(lo.X, -0.5, 1e-6)
			expect.near(hi.Z, 0.5, 1e-6)
			expect.near(lo.Z, -0.5, 1e-6)
			for _, tri in g.triangles do
				expect.equal(#tri, 3)
				for _, index in tri do
					expect.truthy(index >= 1 and index <= #g.positions)
				end
			end
			expect.equal(SuperMesh.geometry(n), g) -- cached for the session
		end
	end)

	t.test("the design's winding faces out, and hullTriangles reverses it", function()
		local g = SuperMesh.geometry(7)
		local outward = 0
		for _, tri in g.triangles do
			local a, b, c = g.positions[tri[1]], g.positions[tri[2]], g.positions[tri[3]]
			local face = (b - a):Cross(c - a)
			if face.Magnitude > 1e-9 and face:Dot(a + b + c) > 0 then
				outward += 1
			end
		end
		expect.equal(outward, #g.triangles)
		local hull = SuperMesh.hullTriangles(g)
		expect.equal(#hull, #g.triangles)
		for i, tri in g.triangles do
			expect.deepEqual(hull[i], { tri[1], tri[3], tri[2] })
		end
	end)

	t.test("geometry(n) keeps three's SphereGeometry index order and the surface's own normals", function()
		for _, n in { 5, 7, 8 } do
			local g = SuperMesh.geometry(n)
			-- Row 0 has only (b, c, d) triangles, the middle rows (a, b, d) then (b, c, d), the last row only (a, b, d);
			-- indices 1-based, 29 vertices a row.
			expect.deepEqual(g.triangles[1], { 1, 30, 31 })
			expect.deepEqual(g.triangles[2], { 2, 31, 32 })
			expect.deepEqual(g.triangles[29], { 31, 30, 60 })
			expect.deepEqual(g.triangles[30], { 30, 59, 60 })
			expect.deepEqual(g.triangles[#g.triangles], { 580, 579, 609 })
			-- The design's normal (two tangent steps of 0.003, kit.js:52-64) lies on the gradient of
			-- |2x|^n + |2y|^n + |2z|^n.
			local function slope(v: number): number
				return n * 2 * math.abs(2 * v) ^ (n - 1) * math.sign(v)
			end
			for i, p in g.positions do
				local gradient = Vector3.new(slope(p.X), slope(p.Y), slope(p.Z)).Unit
				expect.truthy(gradient:Dot(g.normals[i]) > 0.999)
			end
		end
	end)

	t.test(
		"writeMesh: a vertex and a normal per position, each triangle with its normals; the hull reversed",
		function()
			local function recorder()
				local log = { vertices = {}, normals = {}, triangles = {}, faceNormals = {} }
				local target = {}
				function target.AddVertex(_self: any, p: Vector3): number
					table.insert(log.vertices, p)
					return 1000 + #log.vertices
				end
				function target.AddNormal(_self: any, normal: Vector3): number
					table.insert(log.normals, normal)
					return 5000 + #log.normals
				end
				function target.AddTriangle(_self: any, a: number, b: number, c: number): number
					table.insert(log.triangles, { a, b, c })
					return 9000 + #log.triangles
				end
				function target.SetFaceNormals(_self: any, face: number, ids: { number })
					log.faceNormals[face] = ids
				end
				return target, log
			end
			local g = SuperMesh.geometry(8)
			for _, hull in { false, true } do
				local target, log = recorder()
				SuperMesh.writeMesh(target, g, hull)
				expect.equal(#log.vertices, #g.positions)
				expect.equal(#log.normals, #g.positions)
				for i, p in g.positions do
					expect.equal(log.vertices[i], p)
					expect.equal(log.normals[i], g.normals[i]) -- the hull keeps the body's normals
				end
				expect.equal(#log.triangles, #g.triangles)
				for k, tri in g.triangles do
					local a, b, c = tri[1], tri[2], tri[3]
					if hull then
						b, c = c, b
					end
					expect.deepEqual(log.triangles[k], { 1000 + a, 1000 + b, 1000 + c })
					expect.deepEqual(log.faceNormals[9000 + k], { 5000 + a, 5000 + b, 5000 + c })
				end
			end
		end
	)

	t.test("newPart: a plain anchored part of the size; no hull without the mesh path", function()
		local size = Vector3.new(0.4, 0.376, 0.448)
		local part = SuperMesh.newPart(7, size)
		expect.truthy(part ~= nil and part:IsA("BasePart"))
		local p = part :: BasePart
		expect.near((p.Size - size).Magnitude, 0, 1e-5)
		expect.truthy(p.Anchored)
		expect.falsy(p.CanCollide)
		expect.falsy(p.CanTouch)
		expect.falsy(p.CanQuery)
		expect.falsy(p.CastShadow)
		expect.equal(p.Material, Enum.Material.SmoothPlastic)
		expect.equal(p.Parent, nil)
		p:Destroy()
		if not SuperMesh.meshReady() then
			expect.equal(SuperMesh.newPart(7, size, true), nil)
		end
	end)

	t.test(
		"prepare(): one try per session; newPart then gives MeshParts and hulls, or the fallback and no hull",
		function()
			local ready = SuperMesh.prepare()
			expect.equal(type(ready), "boolean")
			expect.equal(SuperMesh.prepare(), ready) -- remembered: no second try
			expect.equal(SuperMesh.meshReady(), ready)
			local size = Vector3.new(0.144, 0.16, 0.248)
			for _, n in { 5, 7, 8 } do
				for _, hull in { false, true } do
					local part = SuperMesh.newPart(n, size, hull)
					if hull and not ready then
						expect.equal(part, nil)
					else
						expect.truthy(part ~= nil and part:IsA("BasePart"))
						local p = part :: BasePart
						expect.equal(p:IsA("MeshPart"), ready)
						expect.near((p.Size - size).Magnitude, 0, 1e-5)
						expect.truthy(p.Anchored)
						expect.falsy(p.CanCollide)
						expect.falsy(p.CanTouch)
						expect.falsy(p.CanQuery)
						expect.falsy(p.CastShadow)
						expect.equal(p.Material, Enum.Material.SmoothPlastic)
						expect.equal(p.Parent, nil)
						p:Destroy()
					end
				end
			end
			-- The client's EditableMesh budget (about 8 meshes on a PC in Studio, 2026-10-11, shared with the giant
			-- pads and the jelly ripple): the session makes one shape and one hull, every exponent uses them.
			if ready then
				for _, hull in { false, true } do
					local shared: any = nil
					for _, n in { 5, 7, 8 } do
						local p = SuperMesh.newPart(n, size, hull) :: MeshPart
						local object = (p.MeshContent :: any).Object
						shared = shared or object
						expect.equal(object, shared)
						p:Destroy()
					end
				end
			end
		end
	)
end
