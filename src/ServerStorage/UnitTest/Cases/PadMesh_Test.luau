--!strict
-- PadMesh_Test: unit tests for StarterPlayerScripts.Client.Anim.PadMesh (the path A giant-pad mesh layout).
-- Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §17.6.1, §17.12 Part 3), for each pad of the §17.6.1 table and both qualities:
--   * vertex and triangle counts within the hard caps (Config.Anim.giantPad maxVertices 1200 / maxTriangles 2400)
--     and within the per-quality budgets (High <= 1,000 / 2,000; Low <= 350 / 700);
--   * every triangle index is valid, no degenerate triangle, no NaN, unit normals;
--   * rest heights match the pad table (top at restTop, sides down to the floor, nothing outside the rounded
--     footprint); the outermost top ring is pinned and only it;
--   * top grid spacing: the nominal spacing spans the top, the centre row/column is evenly spaced at it;
--   * triangles face outward (their winding agrees with the explicit normals); flipWinding reverses them;
--   * RING_COUNT equals Config.Anim.giantPad.sideRings (validator G10 counts with it) and the pad table above equals
--     WorldLayout.GiantPads (what GiantPadController builds from).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

-- The design pads (phase 3 D5): the jelly shell 10.2 wide with its top at 6.2 (lobby.js:361), the marshmallow Ø10
-- puffy disc to 6.6 (lobby.js:364), the royal cushion 8.4 wide to 4.8 (lobby.js:384); the corner radii are WorldLayout's
-- readings (a round marshmallow: radius = half the footprint).
local PADS = {
	{ key = "jelly", footprint = 10.2, cornerRadius = 3.6, restTop = 6.2 },
	{ key = "marshmallow", footprint = 10, cornerRadius = 5, restTop = 6.6 },
	{ key = "royal", footprint = 8.4, cornerRadius = 3.0, restTop = 4.8 },
}
-- Per-quality budgets from §17.6.1 (the hard caps come from Config).
local BUDGET = {
	High = { vertices = 1000, triangles = 2000 },
	Low = { vertices = 350, triangles = 700 },
}
local EPS = 1e-6

local function insideFootprint(x: number, z: number, half: number, radius: number): boolean
	local ax, az = math.abs(x), math.abs(z)
	if ax > half + EPS or az > half + EPS then
		return false
	end
	local c = half - radius
	if ax <= c or az <= c then
		return true
	end
	local dx, dz = ax - c, az - c
	return dx * dx + dz * dz <= radius * radius + EPS
end

return function(t: Context)
	local expect = t.expect
	local PadMesh = t.requireClient("Anim/PadMesh")
	local Config = t.requireShared("Config")
	local G = Config.Anim.giantPad
	local QUALITIES: { [string]: number } = { High = G.gridHigh, Low = G.gridLow }

	local function build(pad: any, grid: number, flip: boolean?): any
		return PadMesh.build({
			footprint = pad.footprint,
			cornerRadius = pad.cornerRadius,
			restTop = pad.restTop,
			grid = grid,
			bevel = G.bevel,
			flipWinding = flip,
		})
	end

	t.test("vertex and triangle counts stay within the caps for both qualities", function()
		for quality, grid in QUALITIES do
			local vertices, triangles = PadMesh.counts(grid)
			expect.truthy(vertices <= G.maxVertices and triangles <= G.maxTriangles)
			expect.truthy(vertices <= BUDGET[quality].vertices and triangles <= BUDGET[quality].triangles)
			for _, pad in PADS do
				local layout = build(pad, grid)
				expect.equal(layout.vertexCount, vertices)
				expect.equal(layout.triangleCount, triangles)
				expect.equal(#layout.tris, 3 * triangles)
				expect.equal(layout.topCount, grid * grid)
			end
		end
	end)

	-- The controller builds from WorldLayout.GiantPads and validator G10 counts with Config.Anim.giantPad.sideRings:
	-- both must describe the mesh this module makes.
	t.test("the side rings and the pad table agree with Config (G10) and WorldLayout", function()
		expect.equal(PadMesh.RING_COUNT, G.sideRings)
		for _, grid in QUALITIES do
			local vertices, triangles = PadMesh.counts(grid)
			expect.equal(vertices, grid * grid + G.sideRings * 4 * (grid - 1))
			expect.equal(triangles, 2 * (grid - 1) * (grid - 1) + G.sideRings * 8 * (grid - 1))
		end
		local WorldLayout = t.requireShared("World/WorldLayout")
		for _, pad in PADS do
			local spec = WorldLayout.giantPad(pad.key)
			expect.truthy(spec ~= nil)
			expect.equal(spec.footprint, pad.footprint)
			expect.equal(spec.cornerRadius, pad.cornerRadius)
			expect.equal(spec.restTop, pad.restTop)
		end
	end)

	t.test("every triangle index is valid and no triangle is degenerate; no NaN; unit normals", function()
		for _, grid in QUALITIES do
			for _, pad in PADS do
				local layout = build(pad, grid)
				for _, index in layout.tris do
					expect.truthy(index % 1 == 0 and index >= 1 and index <= layout.vertexCount)
				end
				for k = 1, layout.triangleCount do
					local a, b, c = layout.tris[3 * k - 2], layout.tris[3 * k - 1], layout.tris[3 * k]
					expect.truthy(a ~= b and b ~= c and a ~= c)
				end
				for index = 1, layout.vertexCount do
					for _, list in { layout.px, layout.py, layout.pz } do
						expect.truthy(list[index] == list[index])
					end
					local nx, ny, nz = layout.nx[index], layout.ny[index], layout.nz[index]
					expect.near(math.sqrt(nx * nx + ny * ny + nz * nz), 1, 1e-6)
				end
			end
		end
	end)

	t.test("rest heights match the pad table and every vertex is inside the rounded footprint", function()
		for _, grid in QUALITIES do
			for _, pad in PADS do
				local layout = build(pad, grid)
				local top, low = -math.huge, math.huge
				for index = 1, layout.vertexCount do
					top = math.max(top, layout.py[index])
					low = math.min(low, layout.py[index])
					expect.truthy(
						insideFootprint(layout.px[index], layout.pz[index], pad.footprint / 2, pad.cornerRadius)
					)
				end
				expect.near(top, pad.restTop)
				expect.near(low, 0)
				for index = 1, layout.topCount do
					expect.near(layout.py[index], pad.restTop)
					expect.near(layout.ny[index], 1) -- flat top faces up at rest
				end
			end
		end
	end)

	t.test("the outermost top ring is pinned, and only it", function()
		for _, grid in QUALITIES do
			local layout = build(PADS[1], grid)
			local pinnedCount = 0
			for row = 1, grid do
				for col = 1, grid do
					local index = PadMesh.topIndex(grid, col, row)
					local edge = col == 1 or col == grid or row == 1 or row == grid
					expect.equal(layout.pinned[index], edge)
					if layout.pinned[index] then
						pinnedCount += 1
					end
				end
			end
			expect.equal(pinnedCount, 4 * (grid - 1))
			expect.equal(#layout.outerRing, 4 * (grid - 1))
		end
	end)

	t.test("top grid spacing: nominal spacing over the top, even along the centre lines", function()
		for _, grid in QUALITIES do
			for _, pad in PADS do
				local layout = build(pad, grid)
				expect.near(layout.spacing, (pad.footprint - 2 * layout.bevel) / (grid - 1))
				local middle = (grid + 1) // 2
				for k = 1, grid - 1 do
					local a, b = PadMesh.topIndex(grid, k, middle), PadMesh.topIndex(grid, k + 1, middle)
					expect.near(layout.px[b] - layout.px[a], layout.spacing, 1e-6)
					local c, d = PadMesh.topIndex(grid, middle, k), PadMesh.topIndex(grid, middle, k + 1)
					expect.near(layout.pz[d] - layout.pz[c], layout.spacing, 1e-6)
				end
				-- Elsewhere the rounded corners bend the grid, within limits.
				for row = 1, grid do
					for col = 1, grid - 1 do
						local a, b = PadMesh.topIndex(grid, col, row), PadMesh.topIndex(grid, col + 1, row)
						local dx, dz = layout.px[b] - layout.px[a], layout.pz[b] - layout.pz[a]
						local d = math.sqrt(dx * dx + dz * dz)
						expect.truthy(d >= 0.5 * layout.spacing and d <= 1.5 * layout.spacing)
					end
				end
			end
		end
	end)

	t.test("triangles face outward; flipWinding reverses every one", function()
		for _, grid in QUALITIES do
			for _, pad in PADS do
				local layout = build(pad, grid)
				local flipped = build(pad, grid, true)
				for k = 1, layout.triangleCount do
					local a, b, c = layout.tris[3 * k - 2], layout.tris[3 * k - 1], layout.tris[3 * k]
					local abx, aby, abz =
						layout.px[b] - layout.px[a], layout.py[b] - layout.py[a], layout.pz[b] - layout.pz[a]
					local acx, acy, acz =
						layout.px[c] - layout.px[a], layout.py[c] - layout.py[a], layout.pz[c] - layout.pz[a]
					local gx, gy, gz = aby * acz - abz * acy, abz * acx - abx * acz, abx * acy - aby * acx
					local ex = layout.nx[a] + layout.nx[b] + layout.nx[c]
					local ey = layout.ny[a] + layout.ny[b] + layout.ny[c]
					local ez = layout.nz[a] + layout.nz[b] + layout.nz[c]
					expect.truthy(gx * ex + gy * ey + gz * ez > 0)
					expect.equal(flipped.tris[3 * k - 2], a)
					expect.equal(flipped.tris[3 * k - 1], c)
					expect.equal(flipped.tris[3 * k], b)
				end
			end
		end
	end)

	t.test("topNormal: up on a flat top, tilted away from a raised neighbour", function()
		local grid = G.gridLow
		local layout = build(PADS[1], grid)
		local heights = table.create(layout.topCount, 0)
		local middle = (grid + 1) // 2
		local centre = PadMesh.topIndex(grid, middle, middle)
		local nx, ny, nz = PadMesh.topNormal(layout, heights, centre)
		expect.near(nx, 0)
		expect.near(ny, 1)
		expect.near(nz, 0)
		-- Raise the +X neighbour: the surface rises toward +X, so the normal leans toward -X.
		heights[PadMesh.topIndex(grid, middle + 1, middle)] = 0.3
		nx, ny, nz = PadMesh.topNormal(layout, heights, centre)
		expect.truthy(nx < 0 and ny > 0)
		expect.near(nz, 0)
		expect.near(math.sqrt(nx * nx + ny * ny + nz * nz), 1, 1e-6)
	end)
end
