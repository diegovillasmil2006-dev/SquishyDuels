--!strict
--!native
-- CrackNetwork (client only; pure: no instances, connections, yields or clock reads). Spec phase2-squeeze §1.14, §3.4
-- "Crack canvas" 1-2: the crack lines of the design's shader (sqWax, design sd/squish.js:72-93) as a precomputed
-- network of line segments on an Anim/ShellGeometry shell. The crack canvas (an EditableImage colour atlas on the
-- shell's UVs) draws them from the changes reveal returns; there is no shader and no per-pixel Voronoi in Luau.
--
-- API
--   CrackNetwork.new(shell, feel) -> Network     an empty network; build it with buildStep
--   network:buildStep(triangles) -> boolean      builds up to that many more shell triangles (octave 1, then octave 2);
--                                                true once finished. Spread it over frames: the whole build is about
--                                                0.6 s (native) to 1.3 s (interpreted) for a 2,000-vertex shell
--                                                (offline, 2026-10-11). Cache the network per toy and quality.
--   CrackNetwork.build(shell, feel) -> Network   new + every buildStep at once
--   network:reveal(damage, touched, count) -> { Change }   after the coat cracked: re-tests the segments of the touched
--                                    vertices (WaxCoat.touched[1..touchedCount]) against the per-vertex damage
--                                    (WaxCoat.damage) and returns those whose shown step changed (built ones only:
--                                    when a build finishes late, reveal every vertex once)
--   network:reset()                  re-wax: every segment hidden again (alpha 0)
--   CrackNetwork.seed(ix, iy, iz) -> (x, y, z)   the jittered Voronoi seed of integer cell (ix, iy, iz)
--   CrackNetwork.edgeValue(ax, ay, az, bx, by, bz) -> number   the random value of the edge between two cells' seeds
--
-- Build. Rest space in the design frame (x and z negated), measured in crack cells: q = rest / (coats[feel].cell ×
-- maxDim) (squish.js:84, 175); octave 2 runs on q·octave2Scale + octave2Offset (squish.js:88). Seeds: one per integer
-- cell at cell + hash3(cell)·seedJitter + seedOffset, the nearest found in the 3×3×3 cells around (squish.js:71-79).
-- Each shell triangle is split n × n, n = ceil(the longest shell edge in the octave's cells × pointsPerCell) (proposal,
-- spec §3.4); on each small triangle the corners' nearest seeds are compared (marching triangles): where two differ,
-- the bisector |p - A|² = |p - B|² is linear along a side, so its crossing is exact; where all three differ, each
-- pair's bisector is kept inside the triangle where the third seed is farther (they meet where all three are
-- equidistant). Every end lies exactly on its bisector. On one shell triangle (flat) the pieces of one seed pair's
-- edge are collinear: touching pieces are merged into one segment. Each segment keeps both ends' UVs (per-face-corner
-- UVs: one tile), its octave, part and shell triangle, the barycentric weights of its middle in that triangle, the
-- cells of its two seeds and its edge value (a.y or b.y: the reveal threshold, squish.js:78, 88).
-- Reveal (squish.js:83-91). The crack value = the damage interpolated at the segment's middle. Nothing below
-- skipBelow. Octave 1: rv = smoothstep(revealLow + revealSpan·a.y, revealHigh + revealSpan·a.y, crack); octave 2 only
-- past octave2Gate: rv = smoothstep(octave2Low + octave2Span·b.y, octave2High + octave2Span·b.y, crack). A segment
-- shows alpha = rv floored to steps of alphaStep (proposal, spec §3.4: redraw it only on a new step).
-- Change = { segment, octave, part, u0, v0, u1, v1, alpha, previous, line, halo }. Draw (squish.js:92-93): a halo
-- (haloWidth × the line's width, octave 2 octave2HaloWidth) blended by `halo` (haloWhiten·alpha, octave 2 ×
-- octave2Halo) toward min(colour·haloMul + haloAdd, 1), then the line blended by `line` (lineAlpha·alpha, octave 2 ×
-- octave2Line) toward colour·lineDarken, colour = the part's. `previous` is the alpha already drawn, so the canvas can
-- blend only the difference. Not lines (spec §3.4 steps 5-6): the widening under pressure and the whitening by
-- crack·crackWhiten (a vertex colour).
--
-- Network (read only): count, cellSize (studs), finished, and per segment s: octave, part, tri, u0, v0, u1, v1, qx0,
-- qy0, qz0, qx1, qy1, qz1 (its ends in its octave's cell space), wa, wb, wc, cellAx / cellAy / cellAz and cellBx /
-- cellBy / cellBz (its seeds' cells), threshold, alpha (shown).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ShellGeometry = require(script.Parent.ShellGeometry)

type Shell = ShellGeometry.Shell

export type Change = {
	segment: number,
	octave: number,
	part: number,
	u0: number,
	v0: number,
	u1: number,
	v1: number,
	alpha: number,
	previous: number,
	line: number,
	halo: number,
}

-- A point of a small triangle: position in cell space, UV, weights in the shell triangle, nearest seed.
type Point = {
	x: number,
	y: number,
	z: number,
	u: number,
	v: number,
	wa: number,
	wb: number,
	wc: number,
	seed: number,
}

-- A piece of seeds a and b's edge on one small triangle, from p to q.
type Piece = { p: Point, q: Point, a: number, b: number }

-- A run of touching pieces along one edge: its ends p and q at parameters from <= to.
type Run = { from: number, to: number, p: Point, q: Point }

-- Seeds by packed cell key, numbered as first met; `around` caches each cell's 27 neighbouring seeds.
type Seeds = {
	ids: { [number]: number },
	around: { [number]: { number } },
	x: { number },
	y: { number },
	z: { number },
	cx: { number },
	cy: { number },
	cz: { number },
}

-- One octave's build state: its cell space, lattice split, seeds and the nearest seeds of the shared lattice points.
type Octave = {
	scale: number,
	offset: number,
	refine: number,
	seeds: Seeds,
	vertexSeed: { [number]: number },
	edgeSeed: { [number]: number },
}

type NetworkData = {
	shell: Shell,
	cellSize: number,
	count: number,
	octave: { number },
	part: { number },
	tri: { number },
	u0: { number },
	v0: { number },
	u1: { number },
	v1: { number },
	qx0: { number },
	qy0: { number },
	qz0: { number },
	qx1: { number },
	qy1: { number },
	qz1: { number },
	wa: { number },
	wb: { number },
	wc: { number },
	cellAx: { number },
	cellAy: { number },
	cellAz: { number },
	cellBx: { number },
	cellBy: { number },
	cellBz: { number },
	threshold: { number },
	alpha: { number },
	vertexSegments: { { number } },
	mark: { number },
	stamp: number,
	pieces: { Piece },
	octaves: { Octave },
	octaveIndex: number,
	nextTriangle: number,
	finished: boolean,
	lx: { number },
	ly: { number },
	lz: { number },
	lseed: { number },
}

-- Module tables

local NetworkClass = {}
NetworkClass.__index = NetworkClass

export type Network = typeof(setmetatable({} :: NetworkData, NetworkClass))

local CrackNetwork = {}

-- Constants

local LINES = Config.Wax.lines
local HASH_SCALE = 43758.5453 -- design: squish.js:71, 78
local KEY_OFFSET = 4096 -- packed cell keys stay exact in a double: (x + 4096)·8192² + (y + 4096)·8192 + (z + 4096)
local KEY_SPAN = 8192
local PAIR_SPAN = 2 ^ 24 -- a seed pair's key: smaller id × this + larger id
local MERGE_TOLERANCE = 1e-9 -- touching pieces' ends agree to this share of the edge's scale

-- Private

local function fract(x: number): number
	return x - math.floor(x)
end

local function smoothstep(a: number, b: number, x: number): number
	local u = math.clamp((x - a) / (b - a), 0, 1)
	return u * u * (3 - 2 * u)
end

-- Public: the design's Voronoi

-- sqH3 and the seed jitter (design: squish.js:71, 75).
function CrackNetwork.seed(ix: number, iy: number, iz: number): (number, number, number)
	local hx = fract(math.sin(ix * 127.1 + iy * 311.7 + iz * 74.7) * HASH_SCALE)
	local hy = fract(math.sin(ix * 269.5 + iy * 183.3 + iz * 246.1) * HASH_SCALE)
	local hz = fract(math.sin(ix * 113.5 + iy * 271.9 + iz * 124.6) * HASH_SCALE)
	local jitter, offset = LINES.seedJitter, LINES.seedOffset
	return ix + hx * jitter + offset, iy + hy * jitter + offset, iz + hz * jitter + offset
end

-- a.y: fract(sin(dot(c1 + c2, (12.9898, 78.233, 37.719)))·43758.5453) (design: squish.js:78).
function CrackNetwork.edgeValue(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	return fract(math.sin((ax + bx) * 12.9898 + (ay + by) * 78.233 + (az + bz) * 37.719) * HASH_SCALE)
end

-- Private: seeds and points

local function cellKey(ix: number, iy: number, iz: number): number
	return ((ix + KEY_OFFSET) * KEY_SPAN + (iy + KEY_OFFSET)) * KEY_SPAN + (iz + KEY_OFFSET)
end

local function seedId(seeds: Seeds, ix: number, iy: number, iz: number): number
	local key = cellKey(ix, iy, iz)
	local id = seeds.ids[key]
	if id == nil then
		id = #seeds.x + 1
		seeds.ids[key] = id
		local x, y, z = CrackNetwork.seed(ix, iy, iz)
		seeds.x[id], seeds.y[id], seeds.z[id] = x, y, z
		seeds.cx[id], seeds.cy[id], seeds.cz[id] = ix, iy, iz
	end
	return id
end

-- The nearest seed to (x, y, z) among the 3×3×3 cells around it, in the design's order (design: squish.js:72-77).
local function nearest(seeds: Seeds, x: number, y: number, z: number): number
	local ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
	local key = cellKey(ix, iy, iz)
	local list = seeds.around[key]
	if list == nil then
		list = table.create(27)
		for dz = -1, 1 do
			for dy = -1, 1 do
				for dx = -1, 1 do
					table.insert(list, seedId(seeds, ix + dx, iy + dy, iz + dz))
				end
			end
		end
		seeds.around[key] = list
	end
	local sx, sy, sz = seeds.x, seeds.y, seeds.z
	local best, bestD = 0, math.huge
	for _, id in list do
		local ex, ey, ez = sx[id] - x, sy[id] - y, sz[id] - z
		local d = ex * ex + ey * ey + ez * ez
		if d < bestD then
			best, bestD = id, d
		end
	end
	return best
end

-- |p - A|² - |p - B|² (negative nearer A).
local function bisect(seeds: Seeds, a: number, b: number, p: Point): number
	local ax, ay, az = p.x - seeds.x[a], p.y - seeds.y[a], p.z - seeds.z[a]
	local bx, by, bz = p.x - seeds.x[b], p.y - seeds.y[b], p.z - seeds.z[b]
	return ax * ax + ay * ay + az * az - (bx * bx + by * by + bz * bz)
end

-- p·(1 - t) + q·t (seed left 0).
local function along(p: Point, q: Point, t: number): Point
	local s = 1 - t
	return {
		x = p.x * s + q.x * t,
		y = p.y * s + q.y * t,
		z = p.z * s + q.z * t,
		u = p.u * s + q.u * t,
		v = p.v * s + q.v * t,
		wa = p.wa * s + q.wa * t,
		wb = p.wb * s + q.wb * t,
		wc = p.wc * s + q.wc * t,
		seed = 0,
	}
end

-- Where the bisector of seeds a (nearest at p) and b (nearest at q) crosses the side p -> q: exact, it is linear.
local function crossing(seeds: Seeds, p: Point, q: Point, a: number, b: number): Point
	local fp, fq = bisect(seeds, a, b, p), bisect(seeds, a, b, q)
	local t = if fp ~= fq then fp / (fp - fq) else 0.5
	return along(p, q, math.clamp(t, 0, 1))
end

-- Private: the network

-- A piece of a Voronoi edge found on one small triangle, waiting to be merged with its neighbours.
function NetworkClass._add(self: Network, p: Point, q: Point, a: number, b: number)
	table.insert(self.pieces, { p = p, q = q, a = a, b = b })
end

function NetworkClass._store(
	self: Network,
	seeds: Seeds,
	octave: number,
	triangle: number,
	p: Point,
	q: Point,
	a: number,
	b: number
)
	local s = self.count + 1
	self.count = s
	self.octave[s], self.tri[s], self.part[s] = octave, triangle, self.shell.triPart[triangle]
	self.u0[s], self.v0[s], self.u1[s], self.v1[s] = p.u, p.v, q.u, q.v
	self.qx0[s], self.qy0[s], self.qz0[s] = p.x, p.y, p.z
	self.qx1[s], self.qy1[s], self.qz1[s] = q.x, q.y, q.z
	self.wa[s], self.wb[s], self.wc[s] = (p.wa + q.wa) / 2, (p.wb + q.wb) / 2, (p.wc + q.wc) / 2
	self.cellAx[s], self.cellAy[s], self.cellAz[s] = seeds.cx[a], seeds.cy[a], seeds.cz[a]
	self.cellBx[s], self.cellBy[s], self.cellBz[s] = seeds.cx[b], seeds.cy[b], seeds.cz[b]
	self.threshold[s] =
		CrackNetwork.edgeValue(seeds.cx[a], seeds.cy[a], seeds.cz[a], seeds.cx[b], seeds.cy[b], seeds.cz[b])
	self.alpha[s] = 0
	local tris = self.shell.tris
	for m = 0, 2 do
		table.insert(self.vertexSegments[tris[3 * triangle - m]], s)
	end
end

-- One shell triangle is flat, so the pieces of one seed pair's edge on it are collinear: store each run of touching
-- pieces as one segment (fewer, longer lines for the canvas).
function NetworkClass._flush(self: Network, seeds: Seeds, octave: number, triangle: number)
	local groups: { [number]: { Piece } } = {}
	local order: { number } = {}
	for _, piece in self.pieces do
		local key = math.min(piece.a, piece.b) * PAIR_SPAN + math.max(piece.a, piece.b)
		local group = groups[key]
		if group == nil then
			group = {}
			groups[key] = group
			table.insert(order, key)
		end
		table.insert(group, piece)
	end
	table.clear(self.pieces)
	for _, key in order do
		local group = groups[key]
		-- Parameters along the edge (the direction of its longest piece).
		local longest, lx, ly, lz = -1, 0, 0, 0
		for _, piece in group do
			local dx, dy, dz = piece.q.x - piece.p.x, piece.q.y - piece.p.y, piece.q.z - piece.p.z
			local length = dx * dx + dy * dy + dz * dz
			if length > longest then
				longest, lx, ly, lz = length, dx, dy, dz
			end
		end
		local runs: { Run } = {}
		for _, piece in group do
			local sp = piece.p.x * lx + piece.p.y * ly + piece.p.z * lz
			local sq = piece.q.x * lx + piece.q.y * ly + piece.q.z * lz
			table.insert(
				runs,
				if sp <= sq
					then { from = sp, to = sq, p = piece.p, q = piece.q }
					else { from = sq, to = sp, p = piece.q, q = piece.p }
			)
		end
		table.sort(runs, function(r1: Run, r2: Run): boolean
			return r1.from < r2.from
		end)
		local tolerance = MERGE_TOLERANCE * math.max(longest, MERGE_TOLERANCE)
		local a, b = group[1].a, group[1].b
		local current = runs[1]
		for k = 2, #runs do
			local run = runs[k]
			if run.from <= current.to + tolerance then
				if run.to > current.to then
					current = { from = current.from, to = run.to, p = current.p, q = run.q }
				end
			else
				self:_store(seeds, octave, triangle, current.p, current.q, a, b)
				current = run
			end
		end
		self:_store(seeds, octave, triangle, current.p, current.q, a, b)
	end
end

-- The bisector of seeds x and y inside triangle (p0, p1, p2), where seed z is farther than both (design Voronoi edge).
function NetworkClass._edge(
	self: Network,
	seeds: Seeds,
	p0: Point,
	p1: Point,
	p2: Point,
	x: number,
	y: number,
	z: number
)
	-- Where |p - x|² = |p - y|² crosses the sides: f is linear, so at its sign changes.
	local corners = { p0, p1, p2 }
	local f = { bisect(seeds, x, y, p0), bisect(seeds, x, y, p1), bisect(seeds, x, y, p2) }
	local ends: { Point } = {}
	for k = 1, 3 do
		local m = k % 3 + 1
		local fk, fm = f[k], f[m]
		if (fk < 0 and fm >= 0) or (fk >= 0 and fm < 0) then
			table.insert(ends, along(corners[k], corners[m], fk / (fk - fm)))
		end
	end
	if #ends < 2 then
		return
	end
	local a, b = ends[1], ends[2]
	-- Keep the part nearer x than z: g = |p - x|² - |p - z|² <= 0, linear along the segment.
	local ga, gb = bisect(seeds, x, z, a), bisect(seeds, x, z, b)
	if ga > 0 and gb > 0 then
		return
	end
	if ga > 0 or gb > 0 then
		local cut = along(a, b, ga / (ga - gb))
		if ga > 0 then
			a = cut
		else
			b = cut
		end
	end
	self:_add(a, b, x, y)
end

-- Marching triangles on one small triangle (design Voronoi edges, squish.js:72-79).
function NetworkClass._march(self: Network, seeds: Seeds, p0: Point, p1: Point, p2: Point)
	local s0, s1, s2 = p0.seed, p1.seed, p2.seed
	if s0 == s1 and s1 == s2 then
		return
	end
	if s0 == s1 or s1 == s2 or s0 == s2 then
		-- Two seeds: the odd corner against the other two.
		local odd, x, y
		if s0 == s1 then
			odd, x, y = p2, p0, p1
		elseif s1 == s2 then
			odd, x, y = p0, p1, p2
		else
			odd, x, y = p1, p2, p0
		end
		local a, b = x.seed, odd.seed
		self:_add(crossing(seeds, x, odd, a, b), crossing(seeds, y, odd, a, b), a, b)
		return
	end
	-- Three seeds: each pair's bisector inside the triangle, kept where the third seed is farther (so the three meet
	-- where all three are equidistant, or, when that point is outside, two of them cross the triangle side by side).
	self:_edge(seeds, p0, p1, p2, s0, s1, s2)
	self:_edge(seeds, p0, p1, p2, s1, s2, s0)
	self:_edge(seeds, p0, p1, p2, s2, s0, s1)
end

-- One shell triangle of one octave: the nearest seeds on its split lattice, marching, merging.
function NetworkClass._triangle(self: Network, octaveIndex: number, t: number)
	local o = self.octaves[octaveIndex]
	local shell = self.shell
	local px, py, pz, tris, faceUVs, uvs = shell.px, shell.py, shell.pz, shell.tris, shell.faceUVs, shell.uvs
	local refine, scale, offset, seeds = o.refine, o.scale, o.offset, o.seeds
	local ia, ib, ic = tris[3 * t - 2], tris[3 * t - 1], tris[3 * t]
	local ax, ay, az = -px[ia] * scale + offset, py[ia] * scale + offset, -pz[ia] * scale + offset
	local bx, by, bz = -px[ib] * scale + offset, py[ib] * scale + offset, -pz[ib] * scale + offset
	local cx, cy, cz = -px[ic] * scale + offset, py[ic] * scale + offset, -pz[ic] * scale + offset
	local lx, ly, lz, lseed = self.lx, self.ly, self.lz, self.lseed
	local stride = refine + 1
	-- Lattice point (i, j) has weights ((refine - i - j) / refine, i / refine, j / refine) on (a, b, c).
	for i = 0, refine do
		for j = 0, refine - i do
			local w0, w1, w2 = (refine - i - j) / refine, i / refine, j / refine
			local x, y, z = ax * w0 + bx * w1 + cx * w2, ay * w0 + by * w1 + cy * w2, az * w0 + bz * w1 + cz * w2
			-- Shared points keep one nearest seed: a vertex by its id, an edge point by its edge and step.
			local vertex = if w0 == 1 then ia elseif w1 == 1 then ib elseif w2 == 1 then ic else nil
			local seed
			if vertex then
				seed = o.vertexSeed[vertex]
				if seed == nil then
					seed = nearest(seeds, x, y, z)
					o.vertexSeed[vertex] = seed
				end
			else
				local va, vb, step = 0, 0, -1
				if w2 == 0 then
					va, vb, step = ia, ib, i
				elseif w1 == 0 then
					va, vb, step = ia, ic, j
				elseif w0 == 0 then
					va, vb, step = ib, ic, j
				end
				if step >= 0 then
					if va > vb then
						va, vb, step = vb, va, refine - step
					end
					local key = (va * (shell.count + 1) + vb) * (refine + 1) + step
					seed = o.edgeSeed[key]
					if seed == nil then
						seed = nearest(seeds, x, y, z)
						o.edgeSeed[key] = seed
					end
				else
					seed = nearest(seeds, x, y, z)
				end
			end
			local L = i * stride + j + 1
			lx[L], ly[L], lz[L], lseed[L] = x, y, z, seed
		end
	end
	local ja, jb, jc = faceUVs[3 * t - 2], faceUVs[3 * t - 1], faceUVs[3 * t]
	local function point(i: number, j: number): Point
		local L = i * stride + j + 1
		local w0, w1, w2 = (refine - i - j) / refine, i / refine, j / refine
		return {
			x = lx[L],
			y = ly[L],
			z = lz[L],
			u = uvs[2 * ja - 1] * w0 + uvs[2 * jb - 1] * w1 + uvs[2 * jc - 1] * w2,
			v = uvs[2 * ja] * w0 + uvs[2 * jb] * w1 + uvs[2 * jc] * w2,
			wa = w0,
			wb = w1,
			wc = w2,
			seed = lseed[L],
		}
	end
	for i = 0, refine - 1 do
		for j = 0, refine - 1 - i do
			local sa, sb, sc = lseed[i * stride + j + 1], lseed[(i + 1) * stride + j + 1], lseed[i * stride + j + 2]
			if sa ~= sb or sb ~= sc then
				self:_march(seeds, point(i, j), point(i + 1, j), point(i, j + 1))
			end
			if i + j <= refine - 2 then
				local sd = lseed[(i + 1) * stride + j + 2]
				if sb ~= sd or sd ~= sc then
					self:_march(seeds, point(i + 1, j), point(i + 1, j + 1), point(i, j + 1))
				end
			end
		end
	end
	self:_flush(seeds, octaveIndex, t)
end

-- Public

function CrackNetwork.new(shell: Shell, feel: string): Network
	local coat = Config.Wax.coats[feel] or Config.Wax.coats[Config.Knead.defaultFeel]
	local cellSize = coat.cell * shell.maxDim
	local px, py, pz, tris = shell.px, shell.py, shell.pz, shell.tris
	local longest = 0
	for t = 1, shell.triCount do
		for m = 0, 2 do
			local a, b = tris[3 * t - m], tris[3 * t - (m + 1) % 3]
			longest = math.max(longest, (px[a] - px[b]) ^ 2 + (py[a] - py[b]) ^ 2 + (pz[a] - pz[b]) ^ 2)
		end
	end
	longest = math.sqrt(longest)
	local octaves: { Octave } = {}
	for octave = 1, 2 do
		local scale = if octave == 1 then 1 / cellSize else LINES.octave2Scale / cellSize
		octaves[octave] = {
			scale = scale,
			offset = if octave == 1 then 0 else LINES.octave2Offset,
			refine = math.max(1, math.ceil(longest * scale * LINES.pointsPerCell)),
			seeds = { ids = {}, around = {}, x = {}, y = {}, z = {}, cx = {}, cy = {}, cz = {} },
			vertexSeed = {},
			edgeSeed = {},
		}
	end
	local vertexSegments = table.create(shell.count)
	for i = 1, shell.count do
		vertexSegments[i] = {}
	end
	local data: NetworkData = {
		shell = shell,
		cellSize = cellSize,
		count = 0,
		octave = {},
		part = {},
		tri = {},
		u0 = {},
		v0 = {},
		u1 = {},
		v1 = {},
		qx0 = {},
		qy0 = {},
		qz0 = {},
		qx1 = {},
		qy1 = {},
		qz1 = {},
		wa = {},
		wb = {},
		wc = {},
		cellAx = {},
		cellAy = {},
		cellAz = {},
		cellBx = {},
		cellBy = {},
		cellBz = {},
		threshold = {},
		alpha = {},
		vertexSegments = vertexSegments,
		mark = {},
		stamp = 0,
		pieces = {},
		octaves = octaves,
		octaveIndex = 1,
		nextTriangle = 1,
		finished = shell.triCount == 0,
		lx = {},
		ly = {},
		lz = {},
		lseed = {},
	}
	return setmetatable(data, NetworkClass)
end

-- Builds up to `triangles` more shell triangles (all of octave 1, then octave 2); true once the network is finished.
function NetworkClass.buildStep(self: Network, triangles: number): boolean
	local budget = triangles
	local triCount = self.shell.triCount
	while not self.finished and budget > 0 do
		if self.nextTriangle > triCount then
			self.octaveIndex += 1
			self.nextTriangle = 1
			self.finished = self.octaveIndex > #self.octaves
			continue
		end
		self:_triangle(self.octaveIndex, self.nextTriangle)
		self.nextTriangle += 1
		budget -= 1
	end
	return self.finished
end

function CrackNetwork.build(shell: Shell, feel: string): Network
	local network = CrackNetwork.new(shell, feel)
	network:buildStep(math.huge)
	return network
end

function NetworkClass.reveal(self: Network, damage: { number }, touched: { number }, count: number): { Change }
	self.stamp += 1
	local stamp = self.stamp
	local mark, alpha, octave, threshold = self.mark, self.alpha, self.octave, self.threshold
	local wa, wb, wc, tri = self.wa, self.wb, self.wc, self.tri
	local tris = self.shell.tris
	local vertexSegments = self.vertexSegments
	local step = LINES.alphaStep
	local changes: { Change } = {}
	for k = 1, count do
		for _, s in vertexSegments[touched[k]] do
			if mark[s] == stamp then
				continue
			end
			mark[s] = stamp
			local t = tri[s]
			local crack = wa[s] * damage[tris[3 * t - 2]]
				+ wb[s] * damage[tris[3 * t - 1]]
				+ wc[s] * damage[tris[3 * t]]
			local rv = 0
			if crack >= LINES.skipBelow then
				local y = threshold[s]
				if octave[s] == 1 then
					rv = smoothstep(
						LINES.revealLow + LINES.revealSpan * y,
						LINES.revealHigh + LINES.revealSpan * y,
						crack
					)
				elseif crack > LINES.octave2Gate then
					rv = smoothstep(
						LINES.octave2Low + LINES.octave2Span * y,
						LINES.octave2High + LINES.octave2Span * y,
						crack
					)
				end
			end
			local shown = math.floor(rv / step + 1e-9) * step
			local previous = alpha[s]
			if shown ~= previous then
				alpha[s] = shown
				local second = octave[s] == 2
				table.insert(changes, {
					segment = s,
					octave = octave[s],
					part = self.part[s],
					u0 = self.u0[s],
					v0 = self.v0[s],
					u1 = self.u1[s],
					v1 = self.v1[s],
					alpha = shown,
					previous = previous,
					line = shown * LINES.lineAlpha * (if second then LINES.octave2Line else 1),
					halo = shown * LINES.haloWhiten * (if second then LINES.octave2Halo else 1),
				})
			end
		end
	end
	return changes
end

function NetworkClass.reset(self: Network)
	local alpha = self.alpha
	for s = 1, self.count do
		alpha[s] = 0
	end
end

return CrackNetwork
