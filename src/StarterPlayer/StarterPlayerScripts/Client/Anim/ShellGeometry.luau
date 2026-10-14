--!strict
-- ShellGeometry (client only; pure: no instances, connections, yields or clock reads). Spec phase2-squeeze §3.2: the
-- soft shell of a kneaded toy, as plain arrays for one EditableMesh. The caller (the knead screen) reads the toy's body
-- parts (attribute SD_Body: shape SD_Shape, CFrame relative to the model pivot, Size) and builds the mesh from these.
--
-- API
--   ShellGeometry.build(parts, quality) -> Shell
--     parts    { { shape = "E" | "B" | "RB", cframe = CFrame, size = Vector3, wax = boolean? } } in model space (studs,
--              relative to the pivot; the model faces -Z). wax (default true): the part carries the wax coat.
--     quality  "High" | "Low": about Config.Knead.shell.highVertices / lowVertices vertices for the whole toy.
--     Raises on an unknown shape or quality, a size that is not positive, or no parts.
--
-- Shape (the builder's analytic shapes, SquishyBuilder.luau:34-36, 105): E = the ellipsoid in the part's box, B = the
-- box, RB = the box ∩ the ellipsoid at 1.375 × the half size. Each part gets one closed cube grid (nx, ny, nz cuts along
-- its own X, Y, Z, all sides about one spacing long; never fewer than shell.minSegments), mapped onto its surface by the
-- ray from its centre: B and RB from the evenly cut cube, E through the equal-angle warp tan(g·π/4) so its cells stay
-- even. Neighbouring sides share their edge vertices, so a part is one closed shell; its vertex normals are the
-- surface's own (E: the ellipsoid gradient; B: the mean of the sides that meet there; RB: the ellipsoid where it rounds
-- the box, else as B). Every triangle is wound so that (b - a) x (c - a) points out of its part (the jelly skins'
-- convention, which renders outward).
-- The spacing is solved so the whole toy lands just under the quality's vertex budget (a closed grid has 2(nx·ny +
-- ny·nz + nz·nx) + 2 vertices and twice that minus 4 triangles).
--
-- UVs: one atlas, one tile per part (filled with the part's colour by the crack canvas). A tile holds the part's six
-- sides side by side (±X, ±Y, ±Z columns), each as big as the side's surface spans (measured along its centre lines),
-- and the tiles are shelf-packed into [0, 1]² at one common scale, shell.atlas[quality] texels wide with
-- shell.gutterTexels between rectangles, so a crack line is about as many texels wide anywhere on the toy. Vertices
-- are shared; the UVs are per face corner (uvs + faceUVs), so a side's edge keeps its own UVs (no seam split). UV
-- (0, 0) is the atlas' top left and v runs down, as EditableImage pixels (verify in Studio).
--
-- Bounds anchors (as Anim/JellySkin): 8 triangles with legs of shell.anchorLeg studs at the corners of the rest
-- bounds widened by shell.anchorReach·maxDim, so a stretch, a bulge or a pinch never changes the mesh bounds (the
-- MeshPart would rescale). They are wound to face inward, so a camera outside them never sees them.
--
-- Shell (every array 1-based; positions and normals in model space):
--   count             deforming vertices: 1..count; the 24 anchor vertices follow (anchorFirst = count + 1)
--   vertexTotal       count + 24
--   px, py, pz        rest positions (vertexTotal entries); nx, ny, nz unit rest normals (anchors: inward)
--   triCount          shell triangles; triTotal = triCount + 8 (the anchors last)
--   tris              triangle k = tris[3k - 2], tris[3k - 1], tris[3k]
--   uvs, uvCount      uv j = (uvs[2j - 1], uvs[2j])
--   faceUVs           the uv of corner m (1..3) of triangle k = faceUVs[3k - 3 + m]
--   vertexPart        vertex -> part index (count entries); triPart: triangle -> part index (triCount entries)
--   parts             per input part: { shape, wax, first, count, triFirst, triCount, segments = { nx, ny, nz },
--                     tile = { u0, v0, u1, v1 } }
--   restMin, restMax  the bounds of the deforming vertices; size, maxDim, minDim their box
--   boundsMin, boundsMax, center   the anchored bounds and their centre (the MeshPart's centre in model space)
--   quality, spacing  the build's quality and its target spacing (studs)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Quality = "High" | "Low"

export type PartInput = {
	shape: string,
	cframe: CFrame,
	size: Vector3,
	wax: boolean?,
}

export type ShellPart = {
	shape: string,
	wax: boolean,
	first: number,
	count: number,
	triFirst: number,
	triCount: number,
	segments: { number },
	tile: { number },
}

export type Shell = {
	quality: Quality,
	count: number,
	anchorFirst: number,
	vertexTotal: number,
	triCount: number,
	triTotal: number,
	px: { number },
	py: { number },
	pz: { number },
	nx: { number },
	ny: { number },
	nz: { number },
	tris: { number },
	uvCount: number,
	uvs: { number },
	faceUVs: { number },
	vertexPart: { number },
	triPart: { number },
	parts: { ShellPart },
	restMin: Vector3,
	restMax: Vector3,
	size: Vector3,
	maxDim: number,
	minDim: number,
	boundsMin: Vector3,
	boundsMax: Vector3,
	center: Vector3,
	spacing: number,
}

-- One side of the cube grid: the axis of its outward normal (1 = X, 2 = Y, 3 = Z) and its sign; a1 × a2 = the outward
-- normal (so the cell corners (0, 0), (1, 0), (1, 1) run counter-clockwise from outside); u, v = its UV axes (the two
-- other axes in order) and the tile column it goes in.
type Face = { axis: number, sign: number, a1: number, a2: number, u: number, v: number, column: number }

-- Constants

local SHELL = Config.Knead.shell
local RB_SPHERE_RADIUS = 1.375 -- the rounded box: Ball Ø2.75 ∩ Block 2³ in half-size units (SquishyBuilder.luau:105)
local QUARTER_PI = math.pi / 4
local ARC_SAMPLES = 16 -- the chords a side's span is measured with
local SOLVE_STEPS = 60 -- bisection steps for the spacing and the atlas scale
local ANCHOR_VERTICES = 24
local ANCHOR_TRIANGLES = 8
local SHAPES: { [string]: boolean } = { E = true, B = true, RB = true }

local FACES: { Face } = {
	{ axis = 1, sign = 1, a1 = 2, a2 = 3, u = 2, v = 3, column = 1 },
	{ axis = 1, sign = -1, a1 = 3, a2 = 2, u = 2, v = 3, column = 1 },
	{ axis = 2, sign = 1, a1 = 3, a2 = 1, u = 1, v = 3, column = 2 },
	{ axis = 2, sign = -1, a1 = 1, a2 = 3, u = 1, v = 3, column = 2 },
	{ axis = 3, sign = 1, a1 = 1, a2 = 2, u = 1, v = 2, column = 3 },
	{ axis = 3, sign = -1, a1 = 2, a2 = 1, u = 1, v = 2, column = 3 },
}

-- Module table

local ShellGeometry = {}

-- Private

-- The surface point of a shape (normalized space: half size = 1) on the ray through the cube point g (one coordinate
-- is ±1; `edge` marks the coordinates that are), with the normal direction in normalized space (not unit).
local function surface(
	shape: string,
	g1: number,
	g2: number,
	g3: number,
	edge1: boolean,
	edge2: boolean,
	edge3: boolean
): (number, number, number, number, number, number)
	if shape == "E" then
		local d1, d2, d3 = math.tan(g1 * QUARTER_PI), math.tan(g2 * QUARTER_PI), math.tan(g3 * QUARTER_PI)
		local length = math.sqrt(d1 * d1 + d2 * d2 + d3 * d3)
		local q1, q2, q3 = d1 / length, d2 / length, d3 / length
		return q1, q2, q3, q1, q2, q3
	end
	local scale = 1
	if shape == "RB" then
		scale = math.min(1, RB_SPHERE_RADIUS / math.sqrt(g1 * g1 + g2 * g2 + g3 * g3))
	end
	local q1, q2, q3 = g1 * scale, g2 * scale, g3 * scale
	if scale < 1 then
		return q1, q2, q3, q1, q2, q3 -- on the rounding ellipsoid
	end
	-- On the box: the mean of the sides that meet here.
	local m1 = if edge1 then math.sign(g1) else 0
	local m2 = if edge2 then math.sign(g2) else 0
	local m3 = if edge3 then math.sign(g3) else 0
	return q1, q2, q3, m1, m2, m3
end

-- The length of a side's centre line along `axis` (the side whose normal is `across`), in part space (studs).
local function span(shape: string, half: Vector3, axis: number, across: number): number
	local total = 0
	local lastX, lastY, lastZ = 0, 0, 0
	for step = 0, ARC_SAMPLES do
		local g = { 0, 0, 0 }
		g[axis] = -1 + 2 * step / ARC_SAMPLES
		g[across] = 1
		local q1, q2, q3 = surface(shape, g[1], g[2], g[3], false, false, false)
		local x, y, z = q1 * half.X, q2 * half.Y, q3 * half.Z
		if step > 0 then
			total += math.sqrt((x - lastX) ^ 2 + (y - lastY) ^ 2 + (z - lastZ) ^ 2)
		end
		lastX, lastY, lastZ = x, y, z
	end
	return total
end

-- The spans of a part along its X, Y, Z: the longest centre line of the sides that run along each axis.
local function partSpans(part: PartInput): { number }
	local half = part.size / 2
	local spans = {}
	for axis = 1, 3 do
		local longest = 0
		for across = 1, 3 do
			if across ~= axis then
				longest = math.max(longest, span(part.shape, half, axis, across))
			end
		end
		spans[axis] = longest
	end
	return spans
end

local function segmentsFor(spans: { number }, spacing: number): { number }
	local minimum = SHELL.minSegments
	return {
		math.max(minimum, math.floor(spans[1] / spacing + 0.5)),
		math.max(minimum, math.floor(spans[2] / spacing + 0.5)),
		math.max(minimum, math.floor(spans[3] / spacing + 0.5)),
	}
end

local function gridVertices(n: { number }): number
	return 2 * (n[1] * n[2] + n[2] * n[3] + n[3] * n[1]) + 2
end

-- The largest spacing-driven grid that fits `target` vertices for the whole toy (the minimum grids when none does).
local function solveSpacing(allSpans: { { number } }, target: number): number
	local function total(spacing: number): number
		local sum = 0
		for _, spans in allSpans do
			sum += gridVertices(segmentsFor(spans, spacing))
		end
		return sum
	end
	local longest = 0
	for _, spans in allSpans do
		longest = math.max(longest, spans[1], spans[2], spans[3])
	end
	local low, high = longest * 1e-4, longest * 4
	for _ = 1, SOLVE_STEPS do
		local middle = (low + high) / 2
		if total(middle) > target then
			low = middle
		else
			high = middle
		end
	end
	return high
end

-- One part's tile at atlas scale `k` (atlas units per stud) with `pad` between its six sides: the tile's width and
-- height and each side's rectangle { x, y, w, h } relative to the tile's corner. Columns: ±X (w = Y span, h = Z
-- span), ±Y (X, Z), ±Z (X, Y); + on top, - below.
local function tileLayout(spans: { number }, k: number, pad: number): (number, number, { { number } })
	local columns = {
		{ w = spans[2] * k, h = spans[3] * k },
		{ w = spans[1] * k, h = spans[3] * k },
		{ w = spans[1] * k, h = spans[2] * k },
	}
	local rects = {}
	local x = 0
	local height = 0
	for index, column in columns do
		height = math.max(height, 2 * column.h + pad)
		for faceIndex, face in FACES do
			if face.column == index then
				local y = if face.sign > 0 then 0 else column.h + pad
				rects[faceIndex] = { x, y, column.w, column.h }
			end
		end
		x += column.w + (if index < #columns then pad else 0)
	end
	return x, height, rects
end

-- Shelf-packs the tiles (tallest first) into [0, 1]² at scale k; returns each tile's corner, or nil when they do not
-- fit.
local function shelfPack(allSpans: { { number } }, k: number, pad: number): { { number } }?
	local sizes = {}
	local order = {}
	for index, spans in allSpans do
		local w, h = tileLayout(spans, k, pad)
		sizes[index] = { w, h }
		order[index] = index
	end
	table.sort(order, function(a, b)
		if sizes[a][2] ~= sizes[b][2] then
			return sizes[a][2] > sizes[b][2]
		end
		return a < b
	end)
	local corners = {}
	local x, y, rowHeight = pad, pad, 0
	for _, index in order do
		local w, h = sizes[index][1], sizes[index][2]
		if x + w + pad > 1 and x > pad then
			x, y, rowHeight = pad, y + rowHeight + pad, 0
		end
		if x + w + pad > 1 or y + h + pad > 1 then
			return nil
		end
		corners[index] = { x, y }
		x += w + pad
		rowHeight = math.max(rowHeight, h)
	end
	return corners
end

-- The largest common atlas scale at which every tile fits.
local function solveAtlasScale(allSpans: { { number } }, pad: number): number
	local low, high = 0, 1
	while shelfPack(allSpans, high, pad) ~= nil do
		high *= 2
	end
	for _ = 1, SOLVE_STEPS do
		local middle = (low + high) / 2
		if shelfPack(allSpans, middle, pad) ~= nil then
			low = middle
		else
			high = middle
		end
	end
	return low
end

local function checkInput(parts: { PartInput }, quality: Quality)
	if quality ~= "High" and quality ~= "Low" then
		error(`[SD][ShellGeometry] unknown quality {tostring(quality)} (High or Low)`, 3)
	end
	if type(parts) ~= "table" or #parts == 0 then
		error("[SD][ShellGeometry] build needs at least one part", 3)
	end
	for index, part in parts do
		if not SHAPES[part.shape] then
			error(`[SD][ShellGeometry] part {index}: unknown shape {tostring(part.shape)} (E, B or RB)`, 3)
		end
		local size = part.size
		if typeof(size) ~= "Vector3" or not (size.X > 0 and size.Y > 0 and size.Z > 0) then
			error(`[SD][ShellGeometry] part {index}: the size must be a Vector3 with every side > 0`, 3)
		end
		if typeof(part.cframe) ~= "CFrame" then
			error(`[SD][ShellGeometry] part {index}: cframe must be a CFrame`, 3)
		end
	end
end

-- Public

function ShellGeometry.build(parts: { PartInput }, quality: Quality): Shell
	checkInput(parts, quality)
	local target = if quality == "High" then SHELL.highVertices else SHELL.lowVertices
	local allSpans = {}
	for index, part in parts do
		allSpans[index] = partSpans(part)
	end
	local spacing = solveSpacing(allSpans, target)
	local pad = SHELL.gutterTexels / SHELL.atlas[quality]
	local k = solveAtlasScale(allSpans, pad)
	local corners = shelfPack(allSpans, k, pad) :: { { number } }

	local px: { number }, py: { number }, pz: { number } = {}, {}, {}
	local nx: { number }, ny: { number }, nz: { number } = {}, {}, {}
	local tris: { number }, uvs: { number }, faceUVs: { number } = {}, {}, {}
	local vertexPart: { number }, triPart: { number } = {}, {}
	local shellParts: { ShellPart } = {}
	local vertexCount, triCount, uvCount = 0, 0, 0
	local restMin, restMax = Vector3.one * math.huge, -Vector3.one * math.huge

	for index, part in parts do
		local n = segmentsFor(allSpans[index], spacing)
		local half = part.size / 2
		local cframe = part.cframe
		local first, triFirst = vertexCount + 1, triCount + 1
		local ids: { [number]: number } = {}
		local tileW, tileH, rects = tileLayout(allSpans[index], k, pad)
		local corner = corners[index]

		-- The vertex at lattice point (i1, i2, i3) (0..n per axis, on the cube's surface), created once.
		local function vertexAt(i1: number, i2: number, i3: number): number
			local key = i1 + (n[1] + 1) * (i2 + (n[2] + 1) * i3)
			local existing = ids[key]
			if existing then
				return existing
			end
			local g1, g2, g3 = 2 * i1 / n[1] - 1, 2 * i2 / n[2] - 1, 2 * i3 / n[3] - 1
			local e1, e2, e3 = i1 == 0 or i1 == n[1], i2 == 0 or i2 == n[2], i3 == 0 or i3 == n[3]
			local q1, q2, q3, m1, m2, m3 = surface(part.shape, g1, g2, g3, e1, e2, e3)
			local p = cframe:PointToWorldSpace(Vector3.new(q1 * half.X, q2 * half.Y, q3 * half.Z))
			local normal = cframe:VectorToWorldSpace(Vector3.new(m1 / half.X, m2 / half.Y, m3 / half.Z)).Unit
			vertexCount += 1
			local id = vertexCount
			ids[key] = id
			px[id], py[id], pz[id] = p.X, p.Y, p.Z
			nx[id], ny[id], nz[id] = normal.X, normal.Y, normal.Z
			vertexPart[id] = index
			restMin, restMax = restMin:Min(p), restMax:Max(p)
			return id
		end

		for faceIndex, face in FACES do
			local rect = rects[faceIndex]
			local nu, nv = n[face.u], n[face.v]
			local uvBase = uvCount
			for iv = 0, nv do
				for iu = 0, nu do
					uvCount += 1
					uvs[2 * uvCount - 1] = corner[1] + rect[1] + rect[3] * iu / nu
					uvs[2 * uvCount] = corner[2] + rect[2] + rect[4] * iv / nv
				end
			end
			-- Lattice coordinates of the side's grid point (s along a1, r along a2).
			local function lattice(s: number, r: number): (number, number, number)
				local c = { 0, 0, 0 }
				c[face.axis] = if face.sign > 0 then n[face.axis] else 0
				c[face.a1] = s
				c[face.a2] = r
				return c[1], c[2], c[3]
			end
			local function corner3(s: number, r: number): (number, number)
				local c1, c2, c3 = lattice(s, r)
				local c = { c1, c2, c3 }
				return vertexAt(c1, c2, c3), uvBase + 1 + c[face.u] + (nu + 1) * c[face.v]
			end
			for r = 0, n[face.a2] - 1 do
				for s = 0, n[face.a1] - 1 do
					local v00, t00 = corner3(s, r)
					local v10, t10 = corner3(s + 1, r)
					local v11, t11 = corner3(s + 1, r + 1)
					local v01, t01 = corner3(s, r + 1)
					local d1 = (px[v00] - px[v11]) ^ 2 + (py[v00] - py[v11]) ^ 2 + (pz[v00] - pz[v11]) ^ 2
					local d2 = (px[v10] - px[v01]) ^ 2 + (py[v10] - py[v01]) ^ 2 + (pz[v10] - pz[v01]) ^ 2
					local quad = if d1 <= d2
						then { v00, v10, v11, t00, t10, t11, v00, v11, v01, t00, t11, t01 }
						else { v00, v10, v01, t00, t10, t01, v10, v11, v01, t10, t11, t01 }
					for second = 0, 1 do
						triCount += 1
						local o = 6 * second
						tris[3 * triCount - 2], tris[3 * triCount - 1], tris[3 * triCount] =
							quad[o + 1], quad[o + 2], quad[o + 3]
						faceUVs[3 * triCount - 2], faceUVs[3 * triCount - 1], faceUVs[3 * triCount] =
							quad[o + 4], quad[o + 5], quad[o + 6]
						triPart[triCount] = index
					end
				end
			end
		end

		table.insert(shellParts, {
			shape = part.shape,
			wax = part.wax ~= false,
			first = first,
			count = vertexCount - first + 1,
			triFirst = triFirst,
			triCount = triCount - triFirst + 1,
			segments = n,
			tile = { corner[1], corner[2], corner[1] + tileW, corner[2] + tileH },
		})
	end

	-- The bounds anchors: legs of anchorLeg at the corners of the widened rest bounds, wound to face inward.
	local count, shellTriangles = vertexCount, triCount
	local size = restMax - restMin
	local maxDim = math.max(size.X, size.Y, size.Z)
	local reach = Vector3.one * SHELL.anchorReach * maxDim
	local low, high = restMin - reach, restMax + reach
	local center = (low + high) / 2
	local leg = SHELL.anchorLeg
	local firstTile = shellParts[1].tile
	uvCount += 1
	uvs[2 * uvCount - 1] = (firstTile[1] + firstTile[3]) / 2
	uvs[2 * uvCount] = (firstTile[2] + firstTile[4]) / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local a = Vector3.new(
					if sx < 0 then low.X else high.X,
					if sy < 0 then low.Y else high.Y,
					if sz < 0 then low.Z else high.Z
				)
				local b = a - Vector3.new(sx * leg, 0, 0)
				local c = a - Vector3.new(0, 0, sz * leg)
				if (b - a):Cross(c - a):Dot(a - center) > 0 then
					b, c = c, b
				end
				local inward = -Vector3.new(sx, sy, sz).Unit
				for _, p in { a, b, c } do
					vertexCount += 1
					px[vertexCount], py[vertexCount], pz[vertexCount] = p.X, p.Y, p.Z
					nx[vertexCount], ny[vertexCount], nz[vertexCount] = inward.X, inward.Y, inward.Z
				end
				triCount += 1
				tris[3 * triCount - 2], tris[3 * triCount - 1], tris[3 * triCount] =
					vertexCount - 2, vertexCount - 1, vertexCount
				faceUVs[3 * triCount - 2], faceUVs[3 * triCount - 1], faceUVs[3 * triCount] = uvCount, uvCount, uvCount
			end
		end
	end
	assert(
		vertexCount == count + ANCHOR_VERTICES and triCount == shellTriangles + ANCHOR_TRIANGLES,
		"[SD][ShellGeometry] the bounds anchors are 24 vertices and 8 triangles"
	)

	return {
		quality = quality,
		count = count,
		anchorFirst = count + 1,
		vertexTotal = vertexCount,
		triCount = shellTriangles,
		triTotal = triCount,
		px = px,
		py = py,
		pz = pz,
		nx = nx,
		ny = ny,
		nz = nz,
		tris = tris,
		uvCount = uvCount,
		uvs = uvs,
		faceUVs = faceUVs,
		vertexPart = vertexPart,
		triPart = triPart,
		parts = shellParts,
		restMin = restMin,
		restMax = restMax,
		size = size,
		maxDim = maxDim,
		minDim = math.min(size.X, size.Y, size.Z),
		boundsMin = low,
		boundsMax = high,
		center = center,
		spacing = spacing,
	}
end

return ShellGeometry
