--!strict
-- PadDent (client only; pure, time injected). The dent model of the giant squishy pads (DESIGN §17.6.1), and since the
-- feel pass (§18.3.4) the wave model of the jelly ripple on walls and cover (impulses, no contacts); since the giant
-- pads went (build plan Phase 6) the ripple is its only user. No instances, connections, yields or
-- clock reads: the caller passes dt and the contacts. The ripple builds its Params from Config.Anim.jellyRipple
-- (JellySkin.dentParams).
--
-- Model (all heights h are offsets from the rest surface, studs; negative = sunk):
--   * Contacts: points {x, z} in pad space (studs from the pad centre), optional `extra` depth (squeeze pulse).
--   * Dent shape: target t = -(sinkDepth + extra) * w(r / R), w(x) = (1 - x^2)^2 for x < 1, else 0. With several
--     contacts a vertex takes the deepest target (max, not sum).
--   * Sinking in (t < 0 and h > t): critically damped spring, omega = pressOmega (no wobble).
--   * Everything else (rising back, or a released vertex): underdamped spring omega = releaseOmega, zeta =
--     releaseZeta (the slow wave and its overshoot).
--   * Neighbour coupling on top: a += c^2 * (mean of the 4 neighbours - h) / dx^2, c = waveSpeed. A missing neighbour
--     (grid edge) counts as the vertex itself; pinned vertices (path A outer ring) stay at 0 and are read as 0.
--     That coupling is a quarter of the discrete Laplacian, so a wave really travels at c / 2 (§18.3.4).
--   * Per-axis spacing (§18.3.4, the ripple's wall rows): with a row spacing dz other than the column spacing dx the
--     coupling is c^2 * ((meanX - h) / dx^2 + (meanZ - h) / dz^2) / 2 (meanX = mean of left/right, meanZ = mean of
--     down/up). With dz = dx that is the formula above, and the code then runs the original expression, so a
--     one-spacing grid gets bit-for-bit the same numbers.
--   * Impulses (§18.3.4): impulse(x, z, speed, radius) adds v -= speed * w(r / radius) to every non-pinned vertex
--     within `radius` of (x, z) and wakes them; the springs and the coupling then carry the wave.
--   * Semi-implicit Euler in equal substeps <= `substep` (1/120 s); dt is clamped to maxDt (1/20 s). Neighbours are
--     read from the previous substep (Jacobi), so the vertex order never matters.
--   * Heights are clamped to [-(sinkDepth + extra) - clampExtra, clampUp], `extra` being the largest squeeze-pulse
--     depth among this step's contacts (0 without one), so the pulse's extra dip shows in full. A vertex that would
--     sink below the floor stops there and loses its downward velocity; a vertex already below it (released from a
--     deeper pulse) is never pulled up by the clamp, the springs bring it back. Above clampUp it stops and loses its
--     upward velocity.
--   * ReducedMotion (step's third argument): no ripple (c = 0) and no overshoot (release zeta = 1).
--   * Sleep: only vertices within R + activeMargin of a contact, still moving (|h| > sleepEpsilon or |v| >
--     sleepEpsilon) or next to a moving vertex are stepped. A still vertex snaps to exactly 0. A vertex is reported
--     as written only when its h moved more than writeEpsilon from the value last reported (or snapped to rest), so a
--     settled pad reports zero writes and the caller writes rest + h (never an accumulated value, §9.1 #2).
--
-- Usage:
--   local dent = PadDent.new({ cols = 25, rows = 25, spacing = 0.3, xs = xs, zs = zs, pinEdge = true }, params)
--   local count = dent:step(dt, contacts, reducedMotion)
--   for k = 1, count do local i = dent.written[k]; write(i, dent.h[i]) end
--   dent:impulse(x, z, speed, radius) -- a hit: the next step() carries it

-- Types

export type Contact = {
	x: number,
	z: number,
	extra: number?, -- extra depth (studs) added to sinkDepth for this contact (squeeze pulse)
}

export type Grid = {
	cols: number,
	rows: number,
	spacing: number, -- nominal distance between grid neighbours (studs), used by the coupling term
	spacingZ: number?, -- nominal distance between rows (studs); default `spacing`
	xs: { number }?, -- vertex positions in pad space (index = (row - 1) * cols + col); default: regular grid on 0
	zs: { number }?,
	pinned: { boolean }?, -- true = never moves
	pinEdge: boolean?, -- pins the outermost ring (path A)
}

export type Params = {
	sinkDepth: number,
	radius: number,
	pressOmega: number,
	releaseOmega: number,
	releaseZeta: number,
	waveSpeed: number,
	substep: number,
	maxDt: number,
	clampUp: number,
	clampExtra: number,
	sleepEpsilon: number,
	activeMargin: number,
	maxContacts: number?,
	writeEpsilon: number?, -- default sleepEpsilon / 4
}

type DentData = {
	count: number,
	cols: number,
	rows: number,
	spacing: number,
	spacingZ: number,
	xs: { number },
	zs: { number },
	pinned: { boolean },
	params: Params,
	writeEpsilon: number,
	-- How far a vertex may sit from its nominal grid position (studs); widens the contact index windows.
	maxWarp: number,
	originX: number,
	originZ: number,
	nLeft: { number },
	nRight: { number },
	nDown: { number },
	nUp: { number },
	h: { number },
	v: { number },
	acc: { number },
	shown: { number },
	target: { number },
	targetList: { number },
	targetCount: number,
	stamp: number,
	activeStamp: { number },
	active: { number },
	activeCount: number,
	moving: { number },
	movingCount: number,
	written: { number },
	writtenCount: number,
	asleep: boolean,
}

-- Module tables

local DentClass = {}
DentClass.__index = DentClass

export type Dent = typeof(setmetatable({} :: DentData, DentClass))

local PadDent = {}

-- Private

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function checkPositive(name: string, value: number)
	assert(type(value) == "number" and isFinite(value) and value > 0, `[SD][PadDent] {name} must be a number > 0`)
end

-- Grid column/row of a vertex index.
local function colRow(cols: number, index: number): (number, number)
	local row = (index - 1) // cols + 1
	return index - (row - 1) * cols, row
end

-- Adds a vertex to this step's active list (once per step; pinned vertices never).
local function markActive(self: Dent, index: number)
	if self.activeStamp[index] ~= self.stamp and not self.pinned[index] then
		self.activeStamp[index] = self.stamp
		local count = self.activeCount + 1
		self.activeCount = count
		self.active[count] = index
	end
end

-- The grid index window (col0, col1, row0, row1) that holds every vertex within `reach` studs of (x, z). The step
-- loops over it inline (no per-contact closures in the per-frame path).
local function window(self: Dent, x: number, z: number, reach: number): (number, number, number, number)
	local spacing = self.spacing
	local spacingZ = self.spacingZ
	local widened = reach + self.maxWarp
	local col0 = math.max(1, math.floor((x - widened - self.originX) / spacing) + 1)
	local col1 = math.min(self.cols, math.ceil((x + widened - self.originX) / spacing) + 1)
	local row0 = math.max(1, math.floor((z - widened - self.originZ) / spacingZ) + 1)
	local row1 = math.min(self.rows, math.ceil((z + widened - self.originZ) / spacingZ) + 1)
	return col0, col1, row0, row1
end

-- Public

-- The dent shape w(x) = (1 - x^2)^2 for 0 <= x < 1, else 0.
function PadDent.shape(x: number): number
	local ax = math.abs(x)
	if ax >= 1 then
		return 0
	end
	local s = 1 - ax * ax
	return s * s
end

-- Target height at a pad-space point for a set of contacts: the deepest single dent (max, not sum).
function PadDent.targetAt(x: number, z: number, contacts: { Contact }, sinkDepth: number, radius: number): number
	local t = 0
	for _, contact in contacts do
		local dx, dz = x - contact.x, z - contact.z
		local w = PadDent.shape(math.sqrt(dx * dx + dz * dz) / radius)
		if w > 0 then
			local depth = -(sinkDepth + (contact.extra or 0)) * w
			if depth < t then
				t = depth
			end
		end
	end
	return t
end

function PadDent.new(grid: Grid, params: Params): Dent
	local cols, rows, spacing = grid.cols, grid.rows, grid.spacing
	local spacingZ = if grid.spacingZ == nil then spacing else grid.spacingZ
	assert(type(cols) == "number" and cols >= 1 and cols % 1 == 0, "[SD][PadDent] cols must be an integer >= 1")
	assert(type(rows) == "number" and rows >= 1 and rows % 1 == 0, "[SD][PadDent] rows must be an integer >= 1")
	checkPositive("spacing", spacing)
	checkPositive("spacingZ", spacingZ)
	checkPositive("sinkDepth", params.sinkDepth)
	checkPositive("radius", params.radius)
	checkPositive("pressOmega", params.pressOmega)
	checkPositive("releaseOmega", params.releaseOmega)
	checkPositive("releaseZeta", params.releaseZeta)
	checkPositive("substep", params.substep)
	checkPositive("maxDt", params.maxDt)
	checkPositive("sleepEpsilon", params.sleepEpsilon)
	assert(params.waveSpeed >= 0, "[SD][PadDent] waveSpeed must be >= 0")

	local count = cols * rows
	local originX = -(cols - 1) * spacing / 2
	local originZ = -(rows - 1) * spacingZ / 2
	local xs: { number } = table.create(count, 0)
	local zs: { number } = table.create(count, 0)
	local pinned: { boolean } = table.create(count, false)
	local maxWarp = 0
	for index = 1, count do
		local col, row = colRow(cols, index)
		local nx = originX + (col - 1) * spacing
		local nz = originZ + (row - 1) * spacingZ
		local x = if grid.xs then grid.xs[index] else nx
		local z = if grid.zs then grid.zs[index] else nz
		assert(type(x) == "number" and type(z) == "number" and isFinite(x) and isFinite(z), "[SD][PadDent] bad vertex")
		xs[index], zs[index] = x, z
		maxWarp = math.max(maxWarp, math.abs(x - nx), math.abs(z - nz))
		local edge = col == 1 or col == cols or row == 1 or row == rows
		pinned[index] = (grid.pinEdge == true and edge) or (grid.pinned ~= nil and grid.pinned[index] == true)
	end

	-- Neighbour indices; a missing neighbour is the vertex itself.
	local nLeft: { number } = table.create(count, 0)
	local nRight: { number } = table.create(count, 0)
	local nDown: { number } = table.create(count, 0)
	local nUp: { number } = table.create(count, 0)
	for index = 1, count do
		local col, row = colRow(cols, index)
		nLeft[index] = if col > 1 then index - 1 else index
		nRight[index] = if col < cols then index + 1 else index
		nDown[index] = if row > 1 then index - cols else index
		nUp[index] = if row < rows then index + cols else index
	end

	local self: DentData = {
		count = count,
		cols = cols,
		rows = rows,
		spacing = spacing,
		spacingZ = spacingZ,
		xs = xs,
		zs = zs,
		pinned = pinned,
		params = params,
		writeEpsilon = params.writeEpsilon or params.sleepEpsilon / 4,
		maxWarp = maxWarp,
		originX = originX,
		originZ = originZ,
		nLeft = nLeft,
		nRight = nRight,
		nDown = nDown,
		nUp = nUp,
		h = table.create(count, 0),
		v = table.create(count, 0),
		acc = table.create(count, 0),
		shown = table.create(count, 0),
		target = table.create(count, 0),
		targetList = {},
		targetCount = 0,
		stamp = 0,
		activeStamp = table.create(count, 0),
		active = {},
		activeCount = 0,
		moving = {},
		movingCount = 0,
		written = {},
		writtenCount = 0,
		asleep = true,
	}
	return setmetatable(self, DentClass)
end

-- Advances the model by dt (clamped to [0, maxDt]) with these contacts. Returns the number of vertices whose height
-- must be written this frame; their indices are dent.written[1..count] and their heights dent.h[index].
function DentClass.step(self: Dent, dt: number, contacts: { Contact }, reducedMotion: boolean?): number
	self.writtenCount = 0
	if not (dt > 0) then -- also NaN
		return 0
	end
	local p = self.params
	dt = math.min(dt, p.maxDt)
	local sink, radius = p.sinkDepth, p.radius
	local maxContacts = p.maxContacts or #contacts
	local contactCount = math.min(#contacts, maxContacts)

	-- 1. Targets: clear last step's, then the deepest dent per vertex.
	local target = self.target
	local targetList = self.targetList
	for k = 1, self.targetCount do
		target[targetList[k]] = 0
	end
	local targetCount = 0
	local pinned = self.pinned
	local xs, zs = self.xs, self.zs
	local cols = self.cols
	local r2 = radius * radius
	local maxExtra = 0
	for c = 1, contactCount do
		local contact = contacts[c]
		local extra = contact.extra or 0
		if extra > maxExtra then
			maxExtra = extra
		end
		local depth = sink + extra
		local cx, cz = contact.x, contact.z
		local col0, col1, row0, row1 = window(self, cx, cz, radius)
		for row = row0, row1 do
			local base = (row - 1) * cols
			for col = col0, col1 do
				local index = base + col
				if not pinned[index] then
					local dx, dz = xs[index] - cx, zs[index] - cz
					local d2 = dx * dx + dz * dz
					if d2 <= r2 then
						local s = 1 - d2 / r2
						local t = -depth * s * s
						if t < target[index] then
							if target[index] == 0 then
								targetCount += 1
								targetList[targetCount] = index
							end
							target[index] = t
						end
					end
				end
			end
		end
	end
	self.targetCount = targetCount

	-- 2. Active set: near a contact, still moving, or next to a moving vertex.
	self.stamp += 1
	self.activeCount = 0
	local reach = radius + p.activeMargin
	local reach2 = reach * reach
	for c = 1, contactCount do
		local contact = contacts[c]
		local cx, cz = contact.x, contact.z
		local col0, col1, row0, row1 = window(self, cx, cz, reach)
		for row = row0, row1 do
			local base = (row - 1) * cols
			for col = col0, col1 do
				local index = base + col
				local dx, dz = xs[index] - cx, zs[index] - cz
				if dx * dx + dz * dz <= reach2 then
					markActive(self, index)
				end
			end
		end
	end
	local nLeft, nRight, nDown, nUp = self.nLeft, self.nRight, self.nDown, self.nUp
	local moving = self.moving
	for k = 1, self.movingCount do
		local index = moving[k]
		markActive(self, index)
		markActive(self, nLeft[index])
		markActive(self, nRight[index])
		markActive(self, nDown[index])
		markActive(self, nUp[index])
	end
	local active = self.active
	local activeCount = self.activeCount
	if activeCount == 0 then
		self.movingCount = 0
		self.asleep = contactCount == 0
		return 0
	end

	-- 3. Substeps (semi-implicit Euler, Jacobi neighbours).
	local substeps = math.max(1, math.ceil(dt / p.substep - 1e-9))
	local hs = dt / substeps
	local pressOmega = p.pressOmega
	local press2 = pressOmega * pressOmega
	local pressDamp = 2 * pressOmega -- zeta = 1
	local releaseOmega = p.releaseOmega
	local release2 = releaseOmega * releaseOmega
	local releaseZeta = if reducedMotion then 1 else p.releaseZeta
	local releaseDamp = 2 * releaseZeta * releaseOmega
	local waveSpeed = if reducedMotion then 0 else p.waveSpeed
	local coupling = waveSpeed * waveSpeed / (self.spacing * self.spacing)
	-- Per-axis spacing (the ripple's walls): the two halves of the coupling; unused when the spacings are equal.
	local uniform = self.spacingZ == self.spacing
	local couplingX = coupling * 0.5
	local couplingZ = waveSpeed * waveSpeed / (self.spacingZ * self.spacingZ) * 0.5
	local lo = -(sink + maxExtra) - p.clampExtra
	local hi = p.clampUp
	local h, v, acc = self.h, self.v, self.acc
	for _ = 1, substeps do
		for k = 1, activeCount do
			local index = active[k]
			local height = h[index]
			local t = target[index]
			local a
			if t < 0 and height > t then
				a = -press2 * (height - t) - pressDamp * v[index]
			else
				a = -release2 * (height - t) - releaseDamp * v[index]
			end
			if coupling > 0 then
				if uniform then
					local mean = (h[nLeft[index]] + h[nRight[index]] + h[nDown[index]] + h[nUp[index]]) * 0.25
					a += coupling * (mean - height)
				else
					local meanX = (h[nLeft[index]] + h[nRight[index]]) * 0.5
					local meanZ = (h[nDown[index]] + h[nUp[index]]) * 0.5
					a += couplingX * (meanX - height) + couplingZ * (meanZ - height)
				end
			end
			acc[index] = a
		end
		for k = 1, activeCount do
			local index = active[k]
			local velocity = v[index] + acc[index] * hs
			local height = h[index] + velocity * hs
			if height < lo and velocity < 0 then
				-- Stops at the floor, or where it already was when that is below the floor (after a squeeze pulse).
				height = math.min(h[index], lo)
				velocity = 0
			elseif height > hi then
				height = hi
				if velocity > 0 then
					velocity = 0
				end
			end
			v[index] = velocity
			h[index] = height
		end
	end

	-- 4. Sleep bookkeeping and the write list.
	local eps = p.sleepEpsilon
	local writeEps = self.writeEpsilon
	local shown = self.shown
	local written = self.written
	local writtenCount = 0
	local movingCount = 0
	for k = 1, activeCount do
		local index = active[k]
		local height = h[index]
		if math.abs(height) > eps or math.abs(v[index]) > eps then
			movingCount += 1
			moving[movingCount] = index
		else
			height = 0
			h[index] = 0
			v[index] = 0
		end
		local last = shown[index]
		if (height == 0 and last ~= 0) or math.abs(height - last) > writeEps then
			shown[index] = height
			writtenCount += 1
			written[writtenCount] = index
		end
	end
	self.movingCount = movingCount
	self.writtenCount = writtenCount
	self.asleep = movingCount == 0 and contactCount == 0
	return writtenCount
end

-- Adds a hit (§18.3.4): v -= speed * w(r / radius), w(x) = (1 - x^2)^2, on every non-pinned vertex within `radius`
-- studs of (x, z) (grid space). Those vertices wake, so the next step() moves them and carries the wave. A positive
-- speed pushes inward (negative h). Returns how many vertices were kicked (0 for a point off the grid, a radius <= 0,
-- a zero speed or a value that is not a finite number).
function DentClass.impulse(self: Dent, x: number, z: number, speed: number, radius: number): number
	if not (isFinite(x) and isFinite(z) and isFinite(speed) and isFinite(radius)) or radius <= 0 or speed == 0 then
		return 0
	end
	local col0, col1, row0, row1 = window(self, x, z, radius)
	local r2 = radius * radius
	local xs, zs, pinned, v = self.xs, self.zs, self.pinned, self.v
	local moving = self.moving
	local movingCount = self.movingCount
	local cols = self.cols
	local kicked = 0
	for row = row0, row1 do
		local base = (row - 1) * cols
		for col = col0, col1 do
			local index = base + col
			if not pinned[index] then
				local dx, dz = xs[index] - x, zs[index] - z
				local d2 = dx * dx + dz * dz
				if d2 < r2 then
					local s = 1 - d2 / r2
					v[index] -= speed * s * s
					-- A vertex already listed is listed twice; the next step's active set takes each once.
					movingCount += 1
					moving[movingCount] = index
					kicked += 1
				end
			end
		end
	end
	self.movingCount = movingCount
	if kicked > 0 then
		self.asleep = false
	end
	return kicked
end

-- Snaps every vertex to rest at once (a pad back on screen with no contacts). Returns the number of vertices to write
-- (dent.written[1..count]), i.e. those not already shown at rest.
function DentClass.snapToRest(self: Dent): number
	local h, v, shown, written = self.h, self.v, self.shown, self.written
	local writtenCount = 0
	for index = 1, self.count do
		h[index] = 0
		v[index] = 0
		if shown[index] ~= 0 then
			shown[index] = 0
			writtenCount += 1
			written[writtenCount] = index
		end
	end
	for k = 1, self.targetCount do
		self.target[self.targetList[k]] = 0
	end
	self.targetCount = 0
	self.movingCount = 0
	self.writtenCount = writtenCount
	self.asleep = true
	return writtenCount
end

-- True when nothing moves and no contact was given on the last step (the pad writes nothing until touched again).
function DentClass.isAsleep(self: Dent): boolean
	return self.asleep
end

-- Height of one vertex (studs from rest).
function DentClass.height(self: Dent, index: number): number
	return self.h[index]
end

-- Number of vertices still moving after the last step (they are stepped next frame even without contacts).
function DentClass.movingVertexCount(self: Dent): number
	return self.movingCount
end

-- Vertex count of the grid.
function DentClass.size(self: Dent): number
	return self.count
end

return PadDent
