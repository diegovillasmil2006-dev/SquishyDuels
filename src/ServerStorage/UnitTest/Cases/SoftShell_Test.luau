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

	-- A model slot's uploaded body: colours stored in the mesh and the dark copy that follows it (ShellGeometry.fromMesh).
	local INK = Color3.new(0.1, 0.05, 0.1)
	local TAN = Color3.new(0.8, 0.5, 0.25)

	local function meshShell(): any
		local positions = {
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 1, 0),
			Vector3.new(0, -1, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
		}
		local tris = { 1, 3, 5, 3, 2, 5, 2, 4, 5, 4, 1, 5, 3, 1, 6, 2, 3, 6, 4, 2, 6, 1, 4, 6 }
		return ShellGeometry.fromMesh(
			{ positions = positions, colors = table.create(6, TAN), tris = tris },
			{ cframe = CFrame.new(), size = Vector3.new(2, 2, 2) },
			"High",
			{ thickness = 0.1, color = INK, shells = 1 }
		)
	end

	local function colourRecorder(): (any, any)
		local target, log = recorder()
		log.colors, log.faceColors = {}, {}
		function target.AddColor(_self: any, color: Color3, alpha: number): number
			table.insert(log.colors, { color = color, alpha = alpha })
			return 3000 + #log.colors
		end
		function target.SetFaceColors(_self: any, face: number, ids: { number })
			log.faceColors[face] = ids
		end
		return target, log
	end

	t.test("writeMesh: a mesh body's stored colours per vertex, opaque, on every face corner", function()
		local s = meshShell()
		local target, log = colourRecorder()
		SoftShell.writeMesh(target, s, false)
		expect.equal(#log.colors, s.vertexTotal)
		for i = 1, s.vertexTotal do
			expect.equal(log.colors[i].color, s.colors[i])
			expect.equal(log.colors[i].alpha, 1)
		end
		for k = 1, s.triTotal do
			local face = 90000 + k
			for m = 1, 3 do
				expect.equal(log.faceColors[face][m], 3000 + s.tris[3 * k - 3 + m])
			end
		end
	end)

	t.test("writeMesh: a ray on the dark copy counts as the body's triangle, a bounds anchor stays one", function()
		local s = meshShell()
		local target = colourRecorder()
		local ids = SoftShell.writeMesh(target, s, false)
		for j = 1, 8 do
			expect.equal(ids.triangle[90000 + s.triCount + 8 + j], j)
		end
		expect.equal(ids.triangle[90000 + s.triCount + 1], s.triCount + 1)
	end)

	t.test("hullBatch: the moved body vertices' copies, pushed out along the rest normal, after the batch", function()
		local s = meshShell()
		local target = colourRecorder()
		local ids = SoftShell.writeMesh(target, s, false)
		local px: { number }, py: { number }, pz: { number } = table.clone(s.px), table.clone(s.py), table.clone(s.pz)
		px[2] += 0.25
		local idList, values = {}, {}
		local count = SoftShell.batch(idList, values, ids.vertex, { 2 }, 1, px, py, pz, s.center)
		count = SoftShell.hullBatch(idList, values, count, ids.vertex, s, { 2 }, 1, px, py, pz)
		expect.equal(count, 2)
		expect.equal(idList[2], ids.vertex[s.hull.first + 1])
		local normal = Vector3.new(s.nx[2], s.ny[2], s.nz[2])
		local shown = Vector3.new(px[2], py[2], pz[2]) + normal * 0.1 - s.center
		expect.near((values[2] - shown).Magnitude, 0, 1e-5)
		-- No copy: nothing added.
		local plain = shell()
		local plainIds = SoftShell.writeMesh((recorder()), plain, false)
		local a, b = {}, {}
		local n = SoftShell.batch(a, b, plainIds.vertex, { 1 }, 1, plain.px, plain.py, plain.pz, plain.center)
		expect.equal(SoftShell.hullBatch(a, b, n, plainIds.vertex, plain, { 1 }, 1, plain.px, plain.py, plain.pz), 1)
	end)

	t.test("hullBatch: a moved vertex outside the covered shells has no copy", function()
		local positions = {
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 1, 0),
			Vector3.new(0, -1, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
			Vector3.new(0.1, 0.1, 0.1),
			Vector3.new(-0.1, -0.1, 0.1),
			Vector3.new(-0.1, 0.1, -0.1),
			Vector3.new(0.1, -0.1, -0.1),
		}
		local tris = {
			1, 3, 5, 3, 2, 5, 2, 4, 5, 4, 1, 5, 3, 1, 6, 2, 3, 6, 4, 2, 6, 1, 4, 6,
			7, 8, 10, 7, 10, 9, 7, 9, 8, 8, 9, 10,
		}
		local s = ShellGeometry.fromMesh(
			{ positions = positions, colors = table.create(10, TAN), tris = tris },
			{ cframe = CFrame.new(), size = Vector3.new(2, 2, 2) },
			"High",
			{ thickness = 0.1, color = INK, shells = 1 }
		)
		expect.equal(s.count, 10)
		expect.equal(s.hull.count, 6)
		local target = colourRecorder()
		local ids = SoftShell.writeMesh(target, s, false)
		local idList, values = {}, {}
		local count = SoftShell.batch(idList, values, ids.vertex, { 2, 8 }, 2, s.px, s.py, s.pz, s.center)
		count = SoftShell.hullBatch(idList, values, count, ids.vertex, s, { 2, 8 }, 2, s.px, s.py, s.pz)
		expect.equal(count, 3)
		expect.equal(idList[3], ids.vertex[s.hull.first + 1])
	end)

	t.test("handle:write moves the body's vertex and its dark copy in a real EditableMesh", function()
		local s = meshShell()
		local handle, reason = SoftShell.create(s, false)
		if handle == nil then
			warn(`[SoftShell_Test] no EditableMesh here, skipped: {reason}`)
			return
		end
		local ok, err = pcall(function()
			local px: { number } = table.clone(s.px)
			px[2] += 0.25
			handle:write({ 2 }, 1, px, s.py, s.pz)
			local ids = handle._ids.vertex
			local body = handle.mesh:GetPosition(ids[2])
			expect.near((body - (Vector3.new(px[2], s.py[2], s.pz[2]) - s.center)).Magnitude, 0, 1e-4)
			local normal = Vector3.new(s.nx[2], s.ny[2], s.nz[2])
			local copy = handle.mesh:GetPosition(ids[s.hull.first + 1])
			expect.near((copy - (body + normal * 0.1)).Magnitude, 0, 1e-4)
			-- The same with BatchSetValues out: the vertex-by-vertex loop moves the copy too.
			handle._batch = false
			px[2] += 0.25
			handle:write({ 2 }, 1, px, s.py, s.pz)
			body = handle.mesh:GetPosition(ids[2])
			expect.near((body - (Vector3.new(px[2], s.py[2], s.pz[2]) - s.center)).Magnitude, 0, 1e-4)
			copy = handle.mesh:GetPosition(ids[s.hull.first + 1])
			expect.near((copy - (body + normal * 0.1)).Magnitude, 0, 1e-4)
		end)
		handle:destroy()
		if not ok then
			error(err, 0)
		end
	end)

	t.test("meshData: an EditableMesh's points, colours and triangles as plain arrays; a 4-corner face is 2 triangles", function()
		local function standIn(faces: { [number]: { number } }): any
			local mesh = {}
			local points = {
				[41] = Vector3.new(1, 0, 0),
				[52] = Vector3.new(0, 1, 0),
				[63] = Vector3.new(0, 0, 1),
				[74] = Vector3.new(1, 1, 0),
			}
			local colors = { [7] = TAN, [8] = INK, [9] = TAN, [10] = INK }
			function mesh.GetVertices(_self: any): { number }
				return { 41, 52, 63, 74 }
			end
			function mesh.GetPosition(_self: any, id: number): Vector3
				return points[id]
			end
			function mesh.GetFaces(_self: any): { number }
				local list = {}
				for face in faces do
					table.insert(list, face)
				end
				return list
			end
			function mesh.GetFaceVertices(_self: any, face: number): { number }
				return faces[face]
			end
			function mesh.GetFaceColors(_self: any, face: number): { number }
				return if #faces[face] == 4 then { 7, 8, 9, 10 } else { 7, 8, 9 }
			end
			function mesh.GetColor(_self: any, id: number): Color3
				return colors[id]
			end
			return mesh
		end
		local data = SoftShell.meshData(standIn({ [100] = { 63, 41, 52 } }))
		expect.equal(#data.positions, 4)
		expect.deepEqual(data.tris, { 3, 1, 2 })
		expect.equal(data.positions[3], Vector3.new(0, 0, 1))
		expect.equal(data.colors[3], TAN) -- vertex 63 is the face's first corner, colour 7
		expect.equal(data.colors[1], INK)
		local quad = SoftShell.meshData(standIn({ [100] = { 63, 41, 52, 74 } }))
		expect.deepEqual(quad.tris, { 3, 1, 2, 3, 2, 4 })
		expect.equal(quad.colors[4], INK) -- its 4th corner, colour 10
	end)
end
