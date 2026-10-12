--!strict
-- SoftShell_Test: unit tests for StarterPlayerScripts.Client.Anim.SoftShell, the knead shell's EditableMesh (spec
-- phase2-squeeze §3.2). Server only (ServerStorage.UnitTest). The mesh writing against a recording stand-in (the
-- EditableMesh itself is engine-only). Contract:
--   * every shell vertex (anchors included) is added at its rest position minus the shell's centre (the MeshPart's
--     centre), with one automatic normal (AddNormal with no value) per vertex;
--   * every shell UV is added, v flipped (1 - v) only with flipV; every triangle is added with its vertices, its three
--     normals and its three face-corner UVs, and its face id maps back to the shell triangle;
--   * a frame's batch lists the moved vertices' ids with their shown positions minus the centre.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local SoftShell = t.requireClient("Anim/SoftShell")
	local ShellGeometry = t.requireClient("Anim/ShellGeometry")
	local expect = t.expect

	local function recorder(): (any, any)
		local log = { vertices = {}, normals = {}, uvs = {}, triangles = {}, faceNormals = {}, faceUVs = {} }
		local target = {}
		function target.AddVertex(_self: any, p: Vector3): number
			table.insert(log.vertices, p)
			return 1000 + #log.vertices
		end
		function target.AddNormal(_self: any, normal: Vector3?): number
			table.insert(log.normals, normal or "auto")
			return 5000 + #log.normals
		end
		function target.AddUV(_self: any, uv: Vector2): number
			table.insert(log.uvs, uv)
			return 7000 + #log.uvs
		end
		function target.AddTriangle(_self: any, a: number, b: number, c: number): number
			table.insert(log.triangles, { a, b, c })
			return 90000 + #log.triangles
		end
		function target.SetFaceNormals(_self: any, face: number, ids: { number })
			log.faceNormals[face] = ids
		end
		function target.SetFaceUVs(_self: any, face: number, ids: { number })
			log.faceUVs[face] = ids
		end
		return target, log
	end

	local function shell(): any
		return ShellGeometry.build({
			{ shape = "E", cframe = CFrame.new(0, 0.5, 0), size = Vector3.new(2, 1, 1.5) },
			{ shape = "B", cframe = CFrame.new(0, -0.2, 0), size = Vector3.new(2.1, 0.4, 1.6) },
		}, "Low")
	end

	t.test("writeMesh: vertices around the centre, automatic normals, UVs, triangles with their corners", function()
		local s = shell()
		for _, flip in { false, true } do
			local target, log = recorder()
			local ids = SoftShell.writeMesh(target, s, flip)
			expect.equal(#log.vertices, s.vertexTotal)
			expect.equal(#log.normals, s.vertexTotal)
			for i = 1, s.vertexTotal do
				local rest = Vector3.new(s.px[i], s.py[i], s.pz[i]) - s.center
				expect.near((log.vertices[i] - rest).Magnitude, 0, 1e-5)
				expect.equal(log.normals[i], "auto")
				expect.equal(ids.vertex[i], 1000 + i)
			end
			expect.equal(#log.uvs, s.uvCount)
			for j = 1, s.uvCount do
				local v = s.uvs[2 * j]
				expect.near(log.uvs[j].X, s.uvs[2 * j - 1], 1e-6)
				expect.near(log.uvs[j].Y, if flip then 1 - v else v, 1e-6)
			end
			expect.equal(#log.triangles, s.triTotal)
			for k = 1, s.triTotal do
				local face = 90000 + k
				expect.equal(ids.triangle[face], k)
				for m = 1, 3 do
					local vertex = s.tris[3 * k - 3 + m]
					expect.equal(log.triangles[k][m], 1000 + vertex)
					expect.equal(log.faceNormals[face][m], 5000 + vertex)
					expect.equal(log.faceUVs[face][m], 7000 + s.faceUVs[3 * k - 3 + m])
				end
			end
		end
	end)

	t.test("batch: the moved vertices' ids and shown positions around the centre", function()
		local s = shell()
		local target = recorder()
		local ids = SoftShell.writeMesh(target, s, false)
		local px: { number }, py: { number }, pz: { number } = table.clone(s.px), table.clone(s.py), table.clone(s.pz)
		px[3] += 0.25
		pz[7] -= 0.5
		local written = { 3, 7 }
		local idList, values = {}, {}
		local count = SoftShell.batch(idList, values, ids.vertex, written, 2, px, py, pz, s.center)
		expect.equal(count, 2)
		expect.deepEqual(idList, { 1003, 1007 })
		expect.near((values[1] - (Vector3.new(px[3], py[3], pz[3]) - s.center)).Magnitude, 0, 1e-5)
		expect.near((values[2] - (Vector3.new(px[7], py[7], pz[7]) - s.center)).Magnitude, 0, 1e-5)
		-- A shorter frame trims the lists it reuses.
		count = SoftShell.batch(idList, values, ids.vertex, { 5 }, 1, px, py, pz, s.center)
		expect.equal(count, 1)
		expect.equal(#idList, 1)
		expect.equal(#values, 1)
	end)
end
