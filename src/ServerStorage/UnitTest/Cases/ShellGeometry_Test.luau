--!strict
-- ShellGeometry_Test: unit tests for StarterPlayerScripts.Client.Anim.ShellGeometry (spec phase2-squeeze §3.2). Server
-- only (ServerStorage.UnitTest). Pure: arrays only, no instances. Run on the body parts of Butter (an RB block and two
-- boxes), Banana (7 ellipsoids turned about Z), Kitty Bread and Donut (20 ellipsoids):
--   * one closed shell per part: every edge is in exactly two of its triangles, once each way, and (b - a) x (c - a)
--     points out of the part;
--   * every vertex lies on its part's analytic surface (E ellipsoid, B box, RB box ∩ the 1.375 ellipsoid, as
--     SquishyBuilder) with a unit normal pointing out of it;
--   * the vertex budget: High between 85% and 100% of Config.Knead.shell.highVertices, Low of lowVertices, each side of
--     each part cut at least minSegments times;
--   * per-face-corner UVs: every corner of a part's triangle maps inside that part's tile, the tiles fit in [0, 1]² and
--     never overlap, and the texel density stays even (every triangle within 2x of the median, linearly);
--   * 8 bounds anchors after the shell: tiny triangles (legs anchorLeg) at the rest bounds widened by
--     anchorReach·maxDim, wound to face inward; boundsMin / boundsMax / center are their box;
--   * part order and flags: vertexPart / triPart index the input parts, wax defaults to true;
--   * bad input (an unknown shape or quality, a size that is not positive, no parts) raises.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local RB_SPHERE_RADIUS = 1.375 -- SquishyBuilder.luau:105
local SURFACE_EPS = 1e-3 -- normalized units
local TOYS = { "butter", "banana", "kitty_bread", "donut" }

return function(t: Context)
	local ShellGeometry = t.requireClient("Anim/ShellGeometry")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local SHELL = Config.Knead.shell

	-- The plain body parts of a blueprint (body, placed by pos / rot, not face- or attach-placed) at the blueprint's
	-- scale, as SquishyBuilder lays them out: CFrame.new(pos)·Angles(rot), positions and sizes × scale.
	local function bodyParts(id: string): { any }
		local blueprint = Blueprints[id]
		local scale = blueprint.scale
		local parts = {}
		for _, spec in blueprint.parts do
			if spec.body and spec.face == nil and spec.attach == nil then
				local rot = spec.rot or Vector3.zero
				local cframe = CFrame.new((spec.pos or Vector3.zero) * scale)
					* CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
				table.insert(parts, { shape = spec.shape, cframe = cframe, size = spec.size * scale })
			end
		end
		return parts
	end

	local function vertex(shell: any, i: number): Vector3
		return Vector3.new(shell.px[i], shell.py[i], shell.pz[i])
	end

	-- The point in the part's normalized space (half size = 1).
	local function normalized(part: any, p: Vector3): Vector3
		return part.cframe:PointToObjectSpace(p) / (part.size / 2)
	end

	-- How far p is from the part's surface along the ray from its centre (0 = on it), normalized units.
	local function surfaceError(part: any, q: Vector3): number
		local box = math.max(math.abs(q.X), math.abs(q.Y), math.abs(q.Z))
		if part.shape == "E" then
			return math.abs(q.Magnitude - 1)
		elseif part.shape == "B" then
			return math.abs(box - 1)
		end
		return math.abs(math.max(box, q.Magnitude / RB_SPHERE_RADIUS) - 1)
	end

	local function cross(a: Vector3, b: Vector3): Vector3
		return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
	end

	local function triangle(shell: any, k: number): (number, number, number)
		return shell.tris[3 * k - 2], shell.tris[3 * k - 1], shell.tris[3 * k]
	end

	t.test("build: a closed shell per part, each edge in two of its triangles, wound outward", function()
		for _, id in TOYS do
			local parts = bodyParts(id)
			for _, quality in { "High", "Low" } do
				local shell = ShellGeometry.build(parts, quality)
				expect.equal(#shell.parts, #parts)
				for index, info in shell.parts do
					local part = parts[index]
					local edges: { [string]: number } = {}
					for k = info.triFirst, info.triFirst + info.triCount - 1 do
						local a, b, c = triangle(shell, k)
						for _, v in { a, b, c } do
							expect.truthy(v >= info.first and v < info.first + info.count)
						end
						for _, e in { { a, b }, { b, c }, { c, a } } do
							local key = `{e[1]}>{e[2]}`
							edges[key] = (edges[key] or 0) + 1
						end
						local pa, pb, pc = vertex(shell, a), vertex(shell, b), vertex(shell, c)
						local n = cross(pb - pa, pc - pa)
						expect.truthy(n.Magnitude > 0)
						expect.truthy(n:Dot((pa + pb + pc) / 3 - part.cframe.Position) > 0)
					end
					for key, count in edges do
						local a, b = string.match(key, "^(%d+)>(%d+)$")
						expect.equal(count, 1) -- never the same direction twice
						expect.equal(edges[`{b}>{a}`], 1) -- and its twin once the other way
					end
				end
			end
		end
	end)

	t.test("every vertex lies on its part's analytic surface with a unit normal pointing out of it", function()
		for _, id in TOYS do
			local parts = bodyParts(id)
			local shell = ShellGeometry.build(parts, "High")
			for index, info in shell.parts do
				local part = parts[index]
				for i = info.first, info.first + info.count - 1 do
					local p = vertex(shell, i)
					local n = Vector3.new(shell.nx[i], shell.ny[i], shell.nz[i])
					expect.near(surfaceError(part, normalized(part, p)), 0, SURFACE_EPS)
					expect.near(n.Magnitude, 1, 1e-4)
					expect.truthy(n:Dot(p - part.cframe.Position) > 0)
					expect.equal(shell.vertexPart[i], index)
				end
			end
		end
	end)

	t.test("budget: 85-100% of highVertices / lowVertices, each side cut at least minSegments times", function()
		for _, id in TOYS do
			local parts = bodyParts(id)
			local targets: { [string]: number } = { High = SHELL.highVertices, Low = SHELL.lowVertices }
			for quality, target in targets do
				local shell = ShellGeometry.build(parts, quality)
				expect.equal(shell.quality, quality)
				expect.equal(shell.count, shell.anchorFirst - 1)
				expect.truthy(shell.count <= target)
				expect.truthy(shell.count >= 0.85 * target)
				local sum = 0
				for _, info in shell.parts do
					local n = info.segments
					for _, axis in { 1, 2, 3 } do
						expect.truthy(n[axis] >= SHELL.minSegments)
					end
					-- a closed cube grid: V = 2(nx·ny + ny·nz + nz·nx) + 2, F = 2V - 4
					expect.equal(info.count, 2 * (n[1] * n[2] + n[2] * n[3] + n[3] * n[1]) + 2)
					expect.equal(info.triCount, 2 * info.count - 4)
					sum += info.count
				end
				expect.equal(sum, shell.count)
			end
		end
	end)

	t.test("UVs: corners inside their part's tile, tiles inside [0, 1]² apart, even texel density", function()
		for _, id in TOYS do
			local parts = bodyParts(id)
			local shell = ShellGeometry.build(parts, "High")
			local ratios = {}
			for k = 1, shell.triCount do
				local tile = shell.parts[shell.triPart[k]].tile
				local uv = {}
				for m = 1, 3 do
					local j = shell.faceUVs[3 * k - 3 + m]
					local u, v = shell.uvs[2 * j - 1], shell.uvs[2 * j]
					expect.truthy(u >= tile[1] - 1e-9 and u <= tile[3] + 1e-9)
					expect.truthy(v >= tile[2] - 1e-9 and v <= tile[4] + 1e-9)
					uv[m] = Vector3.new(u, v, 0)
				end
				local a, b, c = triangle(shell, k)
				local area3 = cross(vertex(shell, b) - vertex(shell, a), vertex(shell, c) - vertex(shell, a)).Magnitude
				local areaUV = cross(uv[2] - uv[1], uv[3] - uv[1]).Magnitude
				table.insert(ratios, math.sqrt(areaUV / area3))
			end
			table.sort(ratios)
			local median = ratios[(#ratios + 1) // 2]
			expect.truthy(ratios[1] >= median / 2)
			expect.truthy(ratios[#ratios] <= median * 2)
			for i, a in shell.parts do
				local ta = a.tile
				expect.truthy(ta[1] >= 0 and ta[2] >= 0 and ta[3] <= 1 and ta[4] <= 1)
				expect.truthy(ta[1] < ta[3] and ta[2] < ta[4])
				for j = i + 1, #shell.parts do
					local tb = shell.parts[j].tile
					local apart = ta[3] <= tb[1] or tb[3] <= ta[1] or ta[4] <= tb[2] or tb[4] <= ta[2]
					expect.truthy(apart)
				end
			end
		end
	end)

	t.test("bounds anchors: 8 tiny inward triangles at the rest bounds widened by anchorReach·maxDim", function()
		local shell = ShellGeometry.build(bodyParts("butter"), "High")
		local restMin, restMax = Vector3.one * math.huge, -Vector3.one * math.huge
		for i = 1, shell.count do
			restMin, restMax = restMin:Min(vertex(shell, i)), restMax:Max(vertex(shell, i))
		end
		expect.near((shell.restMin - restMin).Magnitude, 0, 1e-6)
		expect.near((shell.restMax - restMax).Magnitude, 0, 1e-6)
		local size = restMax - restMin
		expect.near(shell.maxDim, math.max(size.X, size.Y, size.Z), 1e-6)
		local reach = Vector3.one * SHELL.anchorReach * shell.maxDim
		expect.near((shell.boundsMin - (restMin - reach)).Magnitude, 0, 1e-6)
		expect.near((shell.boundsMax - (restMax + reach)).Magnitude, 0, 1e-6)
		expect.near((shell.center - (shell.boundsMin + shell.boundsMax) / 2).Magnitude, 0, 1e-6)
		expect.equal(shell.vertexTotal, shell.count + 24)
		expect.equal(shell.triTotal, shell.triCount + 8)
		local corners = 0
		for k = shell.triCount + 1, shell.triTotal do
			local a, b, c = triangle(shell, k)
			for _, v in { a, b, c } do
				expect.truthy(v >= shell.anchorFirst and v <= shell.vertexTotal)
			end
			local pa, pb, pc = vertex(shell, a), vertex(shell, b), vertex(shell, c)
			local onCorner = true
			for _, axis in { "X", "Y", "Z" } do
				local value = (pa :: any)[axis]
				onCorner = onCorner
					and (
						math.abs(value - (shell.boundsMin :: any)[axis]) < 1e-6
						or math.abs(value - (shell.boundsMax :: any)[axis]) < 1e-6
					)
			end
			if onCorner then
				corners += 1
			end
			expect.near((pb - pa).Magnitude, SHELL.anchorLeg, 1e-6)
			expect.near((pc - pa).Magnitude, SHELL.anchorLeg, 1e-6)
			for _, p in { pb, pc } do -- the legs stay inside the anchored box
				expect.truthy(p.X >= shell.boundsMin.X - 1e-9 and p.X <= shell.boundsMax.X + 1e-9)
				expect.truthy(p.Z >= shell.boundsMin.Z - 1e-9 and p.Z <= shell.boundsMax.Z + 1e-9)
			end
			expect.truthy(cross(pb - pa, pc - pa):Dot(pa - shell.center) < 0) -- faces inward
		end
		expect.equal(corners, 8)
	end)

	t.test("parts keep their order (vertexPart, triPart); wax defaults to true and passes through", function()
		local parts = bodyParts("butter")
		parts[2].wax = false
		local shell = ShellGeometry.build(parts, "Low")
		expect.equal(shell.parts[1].wax, true)
		expect.equal(shell.parts[2].wax, false)
		expect.equal(shell.parts[3].wax, true)
		for index, info in shell.parts do
			expect.equal(info.shape, parts[index].shape)
			for k = info.triFirst, info.triFirst + info.triCount - 1 do
				expect.equal(shell.triPart[k], index)
			end
		end
		expect.equal(shell.parts[1].first, 1)
		expect.equal(shell.parts[2].first, shell.parts[1].count + 1)
	end)

	t.test("bad input raises: an unknown shape or quality, a size that is not positive, no parts", function()
		local part = { shape = "E", cframe = CFrame.new(), size = Vector3.one }
		expect.throws(function()
			ShellGeometry.build({ part }, "Ultra" :: any)
		end, "quality")
		expect.throws(function()
			ShellGeometry.build({ { shape = "W", cframe = CFrame.new(), size = Vector3.one } }, "High")
		end, "shape")
		expect.throws(function()
			ShellGeometry.build({ { shape = "B", cframe = CFrame.new(), size = Vector3.new(1, 0, 1) } }, "High")
		end, "size")
		expect.throws(function()
			ShellGeometry.build({}, "High")
		end, "part")
	end)

	-- Shape "M": a model slot's uploaded body (fromMesh), from the plain arrays SoftShell.meshData reads. Three closed
	-- shells, the small ones first in the file: "biggest first" has work to do. Wound as (b - a) x (c - a) = out.
	local OCTA_TRIS = { 1, 3, 5, 3, 2, 5, 2, 4, 5, 4, 1, 5, 3, 1, 6, 2, 3, 6, 4, 2, 6, 1, 4, 6 }
	local TETRA_TRIS = { 1, 2, 4, 1, 4, 3, 1, 3, 2, 2, 3, 4 }
	local BIG_COLOUR = Color3.new(0.8, 0.5, 0.25)
	local SMALL_COLOUR = Color3.new(0.2, 0.3, 0.4)
	local INK = Color3.new(0.1, 0.05, 0.1)

	local function meshFixture(): any
		local positions: { Vector3 } = {}
		local colors: { Color3 } = {}
		local tris: { number } = {}
		local function shell(points: { Vector3 }, faces: { number }, colour: Color3)
			local base = #positions
			for _, p in points do
				table.insert(positions, p)
				table.insert(colors, colour)
			end
			for _, index in faces do
				table.insert(tris, base + index)
			end
		end
		local function tetra(at: Vector3, r: number): { Vector3 }
			return {
				at + Vector3.new(r, r, r),
				at + Vector3.new(-r, -r, r),
				at + Vector3.new(-r, r, -r),
				at + Vector3.new(r, -r, -r),
			}
		end
		shell(tetra(Vector3.new(3, 0, 0), 0.2), TETRA_TRIS, SMALL_COLOUR)
		shell({
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 1, 0),
			Vector3.new(0, -1, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
		}, OCTA_TRIS, BIG_COLOUR)
		shell(tetra(Vector3.new(-3, 0, 0), 0.2), TETRA_TRIS, SMALL_COLOUR)
		return { positions = positions, colors = colors, tris = tris }
	end

	-- The fixture's box is 6.4 x 2 x 2 around the origin; the part doubles it and sits at y = 1.
	local PART = { cframe = CFrame.new(0, 1, 0), size = Vector3.new(12.8, 4, 4) }

	t.test("fromMesh: the mesh fills the part's box, one part per closed shell, biggest first, colours kept", function()
		local shell = ShellGeometry.fromMesh(meshFixture(), PART, "High")
		expect.equal(shell.quality, "High")
		expect.equal(shell.count, 14)
		expect.equal(shell.triCount, 16)
		expect.near((shell.restMin - Vector3.new(-6.4, -1, -2)).Magnitude, 0, 1e-5)
		expect.near((shell.restMax - Vector3.new(6.4, 3, 2)).Magnitude, 0, 1e-5)
		expect.equal(#shell.parts, 3)
		expect.equal(shell.parts[1].count, 6)
		expect.equal(shell.parts[1].triCount, 8)
		expect.equal(shell.parts[1].first, 1)
		expect.equal(shell.parts[2].first, 7)
		expect.equal(shell.parts[3].first, 11)
		expect.equal(shell.parts[1].wax, false)
		for index, info in shell.parts do
			expect.equal(info.shape, "M")
			for i = info.first, info.first + info.count - 1 do
				expect.equal(shell.vertexPart[i], index)
				expect.equal(shell.colors[i], if index == 1 then BIG_COLOUR else SMALL_COLOUR)
			end
			for k = info.triFirst, info.triFirst + info.triCount - 1 do
				expect.equal(shell.triPart[k], index)
				for m = 0, 2 do
					expect.equal(shell.vertexPart[shell.tris[3 * k - m]], index)
				end
			end
		end
	end)

	t.test("fromMesh: unit normals out of the shell, one shared UV, the bounds anchors as build", function()
		local shell = ShellGeometry.fromMesh(meshFixture(), PART, "Low")
		for i = 1, shell.parts[1].count do
			local out = Vector3.new(shell.px[i], shell.py[i] - 1, shell.pz[i])
			local normal = Vector3.new(shell.nx[i], shell.ny[i], shell.nz[i])
			expect.near(normal.Magnitude, 1, 1e-5)
			expect.truthy(normal:Dot(out) > 0)
		end
		expect.equal(shell.uvCount, 1)
		for k = 1, 3 * shell.triTotal do
			expect.equal(shell.faceUVs[k], 1)
		end
		expect.equal(shell.anchorFirst, shell.count + 1)
		expect.equal(shell.vertexTotal, shell.count + 24)
		expect.equal(shell.triTotal, shell.triCount + 8)
		local reach = Vector3.one * Config.Knead.shell.anchorReach * shell.maxDim
		expect.near((shell.boundsMin - (shell.restMin - reach)).Magnitude, 0, 1e-5)
		expect.near((shell.boundsMax - (shell.restMax + reach)).Magnitude, 0, 1e-5)
		expect.equal(shell.hull, nil)
	end)

	t.test("fromMesh with an outline: a dark copy of the biggest shells, pushed out, faces turned, after the anchors", function()
		local outline = { thickness = 0.1, color = INK, shells = 1 }
		local shell = ShellGeometry.fromMesh(meshFixture(), PART, "High", outline)
		expect.equal(shell.count, 14) -- only the shell deforms; the copy follows it
		expect.equal(shell.triCount, 16)
		expect.equal(shell.hull.first, shell.count + 25)
		expect.equal(shell.hull.count, 6)
		expect.equal(shell.hull.thickness, 0.1)
		expect.equal(shell.vertexTotal, shell.count + 24 + 6)
		expect.equal(shell.triTotal, shell.triCount + 8 + 8)
		for i = 1, 6 do
			local copy = shell.hull.first + i - 1
			local rest = Vector3.new(shell.px[i], shell.py[i], shell.pz[i])
			local normal = Vector3.new(shell.nx[i], shell.ny[i], shell.nz[i])
			expect.near((Vector3.new(shell.px[copy], shell.py[copy], shell.pz[copy]) - (rest + normal * 0.1)).Magnitude, 0, 1e-5)
			expect.equal(shell.colors[copy], INK)
		end
		local offset = shell.hull.first - 1
		for j = 1, 8 do
			local k = shell.triCount + 8 + j
			expect.equal(shell.tris[3 * k - 2], shell.tris[3 * j - 2] + offset)
			expect.equal(shell.tris[3 * k - 1], shell.tris[3 * j] + offset)
			expect.equal(shell.tris[3 * k], shell.tris[3 * j - 1] + offset)
		end
	end)

	t.test("fromMesh: the outline's shells count: 2 covers the 2 biggest, 99 stops at all of them", function()
		local two = ShellGeometry.fromMesh(meshFixture(), PART, "High", { thickness = 0.1, color = INK, shells = 2 })
		expect.equal(two.hull.count, 10)
		expect.equal(two.vertexTotal, two.count + 24 + 10)
		expect.equal(two.triTotal, two.triCount + 8 + 12)
		for j = 1, 12 do
			local k = two.triCount + 8 + j
			expect.equal(two.tris[3 * k - 2], two.tris[3 * j - 2] + two.hull.first - 1)
		end
		local all = ShellGeometry.fromMesh(meshFixture(), PART, "High", { thickness = 0.1, color = INK, shells = 99 })
		expect.equal(all.hull.count, all.count)
		expect.equal(all.triTotal, all.triCount + 8 + all.triCount)
	end)

	t.test("fromMesh: each axis fits on its own, in a turned part", function()
		-- The fixture's box is 6.4 x 2 x 2; a quarter turn about Y sends the part's X to world -Z and its Z to world X.
		local part = { cframe = CFrame.new(1, 2, 3) * CFrame.Angles(0, math.rad(90), 0), size = Vector3.new(3.2, 1, 8) }
		local shell = ShellGeometry.fromMesh(meshFixture(), part, "High")
		expect.near((shell.restMin - Vector3.new(1 - 4, 2 - 0.5, 3 - 1.6)).Magnitude, 0, 1e-4)
		expect.near((shell.restMax - Vector3.new(1 + 4, 2 + 0.5, 3 + 1.6)).Magnitude, 0, 1e-4)
		-- The biggest shell's (0, 1, 0) stays on the part's own up, at half the part's height.
		local top = -math.huge
		for i = 1, shell.parts[1].count do
			top = math.max(top, shell.py[i])
		end
		expect.near(top, 2.5, 1e-4)
	end)

	t.test("fromMesh: bad input raises: no triangles, a flat mesh, a size that is not positive", function()
		expect.throws(function()
			ShellGeometry.fromMesh({ positions = {}, colors = {}, tris = {} }, PART, "High")
		end, "mesh")
		expect.throws(function()
			ShellGeometry.fromMesh(meshFixture(), { cframe = CFrame.new(), size = Vector3.new(1, 0, 1) }, "High")
		end, "size")
		expect.throws(function()
			local flat = {
				positions = { Vector3.new(0, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0) },
				colors = { BIG_COLOUR, BIG_COLOUR, BIG_COLOUR },
				tris = { 1, 2, 3 },
			}
			ShellGeometry.fromMesh(flat, PART, "High")
		end, "mesh")
	end)
end
