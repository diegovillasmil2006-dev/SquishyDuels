--!strict
-- PadMesh (client only; pure). The mesh layout of a giant squishy pad for path A (DESIGN §17.6.1): a rounded-square
-- slab whose flat top is a square grid of moving vertices, with fixed rim and side rings down to the floor and no
-- bottom faces. No instances: GiantPadController feeds the arrays to an EditableMesh.
--
-- Pad space: origin at the bottom centre (floor level), +Y up, X/Z across the footprint (the pad's own axes).
-- Footprint: a square of side `footprint` with plan-view corner radius `cornerRadius` (WorldLayout.GiantPads).
--   * Top grid: `grid` x `grid` vertices at Y = restTop, indices 1..grid^2 = (row - 1) * grid + col (col along +X,
--     row along +Z). The square grid is mapped radially onto the footprint inset by the top-edge bevel `bevel`, so
--     its outermost ring follows the rounded outline. Only top vertices move (up and down); the outermost ring is
--     pinned (layout.pinned), so the rim never tears.
--   * Rim and sides (fixed): ring 1 halfway round the bevel (45 degrees), ring 2 at the end of the bevel (the full
--     footprint outline, Y = restTop - bevel), ring 3 on the floor (Y = 0). Each ring has the same 4 * (grid - 1)
--     vertices as the top's outer ring, so neighbouring rings join as quads.
--   * Normals: one explicit normal per vertex (up on the top; the bevel and walls face outward). topNormal() gives
--     the normal of a moved top vertex from its 4 neighbours (one-sided at the grid edge).
--   * Triangles: every triangle is wound so that (b - a) x (c - a) agrees with its vertices' normals (outward);
--     `flipWinding` reverses all of them (a safety knob, Config.Anim.giantPad.flipWinding).
-- Counts: vertices = n^2 + 12 (n - 1); triangles = 2 (n - 1)^2 + 24 (n - 1). High (25): 913 / 1,728.
-- Low (13): 313 / 576. Caps (Config.Anim.giantPad.maxVertices / maxTriangles) are checked by PadMesh_Test.

-- Types

export type Spec = {
	footprint: number, -- side length of the square footprint (studs)
	cornerRadius: number, -- plan-view corner radius (studs), 0..footprint / 2
	restTop: number, -- visual top height above the floor at rest (studs)
	grid: number, -- top grid size n (n x n vertices), >= 3
	bevel: number, -- top-edge rounding radius (studs); clamped to restTop / 2 and footprint / 4
	flipWinding: boolean?,
}

export type Layout = {
	grid: number,
	topCount: number, -- n^2: top vertices are 1..topCount
	perimeter: number, -- vertices per ring: 4 (n - 1)
	ringCount: number, -- fixed rings below the top (3)
	vertexCount: number,
	triangleCount: number,
	spacing: number, -- nominal top grid spacing (studs), the dent model's dx
	bevel: number, -- the bevel actually used
	restTop: number,
	px: { number },
	py: { number },
	pz: { number },
	nx: { number },
	ny: { number },
	nz: { number },
	tris: { number }, -- flat: triangle k uses tris[3k - 2], tris[3k - 1], tris[3k] (vertex indices)
	pinned: { boolean }, -- top vertices: true on the outermost ring
	outerRing: { number }, -- top vertex indices around the outer ring, in ring order
}

-- Constants

local RING_COUNT = 3
local SIN45 = math.sqrt(0.5)

-- Module table

local PadMesh = {}
PadMesh.RING_COUNT = RING_COUNT

-- Private

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function sign(n: number): number
	return if n < 0 then -1 else 1
end

-- Distance from the centre to the outline of a rounded square (half-size b, corner radius r) along the unit
-- direction (dx, dz), and the outline's outward unit normal there.
local function outline(dx: number, dz: number, b: number, r: number): (number, number, number)
	local ax, az = math.abs(dx), math.abs(dz)
	local c = b - r
	if ax >= az then
		local t = b / ax
		if r <= 0 or t * az <= c then
			return t, sign(dx), 0
		end
	else
		local t = b / az
		if r <= 0 or t * ax <= c then
			return t, 0, sign(dz)
		end
	end
	-- Corner arc centred at (c, c) in the quadrant of (ax, az).
	local dot = (ax + az) * c
	local t = dot + math.sqrt(math.max(dot * dot - 2 * c * c + r * r, 0))
	local ox, oz = t * ax - c, t * az - c
	local length = math.sqrt(ox * ox + oz * oz)
	if length < 1e-9 then
		return t, sign(dx) * SIN45, sign(dz) * SIN45
	end
	return t, sign(dx) * ox / length, sign(dz) * oz / length
end

local function normalize(x: number, y: number, z: number): (number, number, number)
	local length = math.sqrt(x * x + y * y + z * z)
	if length < 1e-12 then
		return 0, 1, 0
	end
	return x / length, y / length, z / length
end

-- Top vertex indices around the outermost ring of an n x n grid (counter-clockwise seen from above is not assumed;
-- triangle winding is fixed per triangle).
local function outerRingOf(n: number): { number }
	local ring: { number } = {}
	for col = 1, n - 1 do -- row 1, +X
		table.insert(ring, col)
	end
	for row = 1, n - 1 do -- col n, +Z
		table.insert(ring, (row - 1) * n + n)
	end
	for col = n, 2, -1 do -- row n, -X
		table.insert(ring, (n - 1) * n + col)
	end
	for row = n, 2, -1 do -- col 1, -Z
		table.insert(ring, (row - 1) * n + 1)
	end
	return ring
end

-- Public

-- Vertex and triangle counts for an n x n top grid.
function PadMesh.counts(grid: number): (number, number)
	local m = grid - 1
	return grid * grid + 4 * m * RING_COUNT, 2 * m * m + 2 * 4 * m * RING_COUNT
end

-- Top-grid index of (col, row), both 1-based.
function PadMesh.topIndex(grid: number, col: number, row: number): number
	return (row - 1) * grid + col
end

function PadMesh.build(spec: Spec): Layout
	local n = spec.grid
	assert(type(n) == "number" and n >= 3 and n % 1 == 0, "[SD][PadMesh] grid must be an integer >= 3")
	local footprint, radius, restTop = spec.footprint, spec.cornerRadius, spec.restTop
	assert(isFinite(footprint) and footprint > 0, "[SD][PadMesh] footprint must be > 0")
	assert(isFinite(radius) and radius >= 0 and radius <= footprint / 2, "[SD][PadMesh] bad cornerRadius")
	assert(isFinite(restTop) and restTop > 0, "[SD][PadMesh] restTop must be > 0")
	assert(isFinite(spec.bevel) and spec.bevel >= 0, "[SD][PadMesh] bevel must be >= 0")

	local half = footprint / 2
	local bevel = math.min(spec.bevel, restTop / 2, footprint / 4)
	-- Ring profile: inset from the footprint outline and height, ring 0 = the top grid's outer ring.
	local insets = { bevel, bevel * (1 - SIN45), 0, 0 }
	local heights = { restTop, restTop - bevel * (1 - SIN45), restTop - bevel, 0 }
	-- Outward tilt of each ring's normal from straight up (radians): top, 45 degrees, wall, wall.
	local tilts = { 0, math.pi / 4, math.pi / 2, math.pi / 2 }

	local topCount = n * n
	local outerRing = outerRingOf(n)
	local perimeter = #outerRing
	local vertexCount, triangleCount = PadMesh.counts(n)
	local px: { number } = table.create(vertexCount, 0)
	local py: { number } = table.create(vertexCount, 0)
	local pz: { number } = table.create(vertexCount, 0)
	local nx: { number } = table.create(vertexCount, 0)
	local ny: { number } = table.create(vertexCount, 1)
	local nz: { number } = table.create(vertexCount, 0)
	local pinned: { boolean } = table.create(topCount, false)

	-- Top grid, mapped radially onto the footprint inset by the bevel.
	local b0 = half - insets[1]
	local r0 = math.max(radius - insets[1], 0)
	for row = 1, n do
		for col = 1, n do
			local index = (row - 1) * n + col
			local u = -1 + 2 * (col - 1) / (n - 1)
			local v = -1 + 2 * (row - 1) / (n - 1)
			local s = math.max(math.abs(u), math.abs(v))
			local x, z = 0, 0
			if s > 1e-12 then
				local length = math.sqrt(u * u + v * v)
				local dx, dz = u / length, v / length
				local t = outline(dx, dz, b0, r0)
				x, z = dx * s * t, dz * s * t
			end
			px[index], py[index], pz[index] = x, restTop, z
			nx[index], ny[index], nz[index] = 0, 1, 0
			pinned[index] = col == 1 or col == n or row == 1 or row == n
		end
	end

	-- Fixed rings 1..3, aligned with the outer ring's directions.
	for ring = 1, RING_COUNT do
		local inset = insets[ring + 1]
		local b = half - inset
		local r = math.max(radius - inset, 0)
		local tilt = tilts[ring + 1]
		for m, top in outerRing do
			local index = topCount + (ring - 1) * perimeter + m
			local length = math.sqrt(px[top] * px[top] + pz[top] * pz[top])
			local dx, dz = px[top] / length, pz[top] / length
			local t, ox, oz = outline(dx, dz, b, r)
			px[index], py[index], pz[index] = dx * t, heights[ring + 1], dz * t
			nx[index], ny[index], nz[index] = normalize(ox * math.sin(tilt), math.cos(tilt), oz * math.sin(tilt))
		end
	end

	-- Triangles.
	local tris: { number } = table.create(triangleCount * 3, 0)
	local count = 0
	local flip = spec.flipWinding == true
	local function add(a: number, b: number, c: number)
		-- Geometric normal (b - a) x (c - a) against the vertices' normals: swap b and c when they disagree.
		local abx, aby, abz = px[b] - px[a], py[b] - py[a], pz[b] - pz[a]
		local acx, acy, acz = px[c] - px[a], py[c] - py[a], pz[c] - pz[a]
		local gx = aby * acz - abz * acy
		local gy = abz * acx - abx * acz
		local gz = abx * acy - aby * acx
		local ex, ey, ez = nx[a] + nx[b] + nx[c], ny[a] + ny[b] + ny[c], nz[a] + nz[b] + nz[c]
		if (gx * ex + gy * ey + gz * ez < 0) ~= flip then
			b, c = c, b
		end
		tris[count * 3 + 1], tris[count * 3 + 2], tris[count * 3 + 3] = a, b, c
		count += 1
	end
	for row = 1, n - 1 do
		for col = 1, n - 1 do
			local a = (row - 1) * n + col
			local b = a + 1
			local c = a + n + 1
			local d = a + n
			add(a, d, c)
			add(a, c, b)
		end
	end
	for ring = 1, RING_COUNT do
		for m = 1, perimeter do
			local nextM = if m == perimeter then 1 else m + 1
			local upperA = if ring == 1 then outerRing[m] else topCount + (ring - 2) * perimeter + m
			local upperB = if ring == 1 then outerRing[nextM] else topCount + (ring - 2) * perimeter + nextM
			local lowerA = topCount + (ring - 1) * perimeter + m
			local lowerB = topCount + (ring - 1) * perimeter + nextM
			add(upperA, lowerA, lowerB)
			add(upperA, lowerB, upperB)
		end
	end
	assert(count == triangleCount, "[SD][PadMesh] triangle count mismatch")

	return {
		grid = n,
		topCount = topCount,
		perimeter = perimeter,
		ringCount = RING_COUNT,
		vertexCount = vertexCount,
		triangleCount = triangleCount,
		spacing = 2 * b0 / (n - 1),
		bevel = bevel,
		restTop = restTop,
		px = px,
		py = py,
		pz = pz,
		nx = nx,
		ny = ny,
		nz = nz,
		tris = tris,
		pinned = pinned,
		outerRing = outerRing,
	}
end

-- Unit normal of top vertex `index` when the top heights are rest + heights[i] (heights indexed like the top grid),
-- from its 4 neighbours (central differences; one-sided at the grid edge).
function PadMesh.topNormal(layout: Layout, heights: { number }, index: number): (number, number, number)
	local n = layout.grid
	local px, pz = layout.px, layout.pz
	local row = (index - 1) // n + 1
	local col = index - (row - 1) * n
	local left = if col > 1 then index - 1 else index
	local right = if col < n then index + 1 else index
	local down = if row > 1 then index - n else index
	local up = if row < n then index + n else index
	-- Tangents along +X (right - left) and +Z (up - down); the rest Y is the same on the whole top.
	local txx, txy, txz = px[right] - px[left], heights[right] - heights[left], pz[right] - pz[left]
	local tzx, tzy, tzz = px[up] - px[down], heights[up] - heights[down], pz[up] - pz[down]
	-- normal = tz x tx (points up on a flat top)
	return normalize(tzy * txz - tzz * txy, tzz * txx - tzx * txz, tzx * txy - tzy * txx)
end

return PadMesh
