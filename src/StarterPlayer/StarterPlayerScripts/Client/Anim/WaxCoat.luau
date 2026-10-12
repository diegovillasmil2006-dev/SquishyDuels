--!strict
--!native
-- WaxCoat (client only; pure: no instances, connections, yields or clock reads; dt injected). Spec phase2-squeeze
-- §1.13, §3.4: the port of the 3D Lab's wax coat crack model (design sd/squish.js:230-309, 626-633) on a SoftBody.
-- Numbers in Config.Wax (and the pan gain in Config.Knead.sounds), each with its squish.js line.
--
-- API
--   WaxCoat.new(body, options?) -> Coat   body = an Anim/SoftBody; options.rng = a Random (default Random.new())
--   coat:step(dt) -> number               one frame, after body:step; returns the cracks that sounded. Call it every
--                                         frame while body.active or coat.shine > 0.
--   coat:rewax()                          a fresh coat (squish.js:305-309); rewaxCount +1 (reset the crack lines)
--   coat:takeEvents() -> { CrackEvent }   the sounding cracks since the last call
--   coat:clearTouched()                   forget touched[1..touchedCount] (after the crack lines read them)
--
-- Cells (squish.js:231-266): Poisson-disk samples over the coat's vertices (the shell parts with wax), at least
-- spacing = cells.spacing·maxDim apart, visited part by part in a shuffled order, at most cells.maxCells; each with a
-- threshold th = coats[feel].th·thScale·exp(thSpread·gauss), its neighbours (nbStart / nbList, CSR: the cells within
-- neighbourRadius·spacing) and its footprint (footStart / footVertex / footWeight: the coat vertices within
-- footprintRadius·spacing, weight (1 - d² / rc²)²).
-- Each frame the body moved (squish.js:273-298): a cell's normal is its rest normal + (the one-ring face normal now -
-- at rest), as the design's normals (squish.js:602-607), on the cell vertices only; its load = bend·(the chord to last
-- frame's normal) + |Δ|x|| / rF (x = the body's spring displacement); s = s·exp(-relax·dt) + load·(worn + (1 - worn)·I).
-- Every cell past th cracks, biggest s / th first: E, a stress drop and a new th; only the first `sounding` go on to
-- crunchiness, wear, damage (footprint), cascades (neighbours) and an event. waxLeft = the mean I before the cracks;
-- drive = min(1, strain / dt / cells / driveStrain), the audio beds' (squish.js:632). When the body snaps to rest the
-- cells' normals go back to rest, m to 0 and their stress halves (squish.js:646). The damage stays until re-wax.
--
-- Readable state (never write it; tests set cellS / cellTh / cellI): cellCount, spacing, cellVertex, cellS, cellTh,
-- cellI, cellM, cellNx / cellNy / cellNz (last frame's normal), nbStart, nbList, footStart, footVertex, footWeight,
-- cracks, waxLeft, crunchiness (the design's `local`: the HUD's Crunchy / Crackled / Soft), shine, drive, damage (per
-- shell vertex, 0..1: the crack value of the lines and the whitening), touched[1..touchedCount] (vertices whose damage
-- rose since clearTouched), rewaxCount, body, rng.
-- CrackEvent = { E, intact (the cell's I after the crack), pan (clamp((x - ctr.x) / (s.x / 2), -1, 1)·
-- Config.Knead.sounds.pan in the design frame: the viewer's right > 0), position and normal (the cell's vertex now,
-- model space: flakes start there, fp.js:683), cell }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SoftBody = require(script.Parent.SoftBody)

type Body = SoftBody.Body

export type Options = { rng: Random? }

export type CrackEvent = {
	E: number,
	intact: number,
	pan: number,
	position: Vector3,
	normal: Vector3,
	cell: number,
}

type CoatData = {
	body: Body,
	rng: Random,
	thBase: number,
	wear: number,
	spacing: number,
	cellCount: number,
	cellVertex: { number },
	cellS: { number },
	cellTh: { number },
	cellI: { number },
	cellM: { number },
	cellNx: { number },
	cellNy: { number },
	cellNz: { number },
	-- rest normal (the shell's) and the rest one-ring face normal per cell
	restNx: { number },
	restNy: { number },
	restNz: { number },
	ringNx: { number },
	ringNy: { number },
	ringNz: { number },
	ringStart: { number },
	ringTris: { number },
	nbStart: { number },
	nbList: { number },
	footStart: { number },
	footVertex: { number },
	footWeight: { number },
	damage: { number },
	touched: { number },
	touchedCount: number,
	touchedMark: { boolean },
	candidates: { number },
	cracks: number,
	waxLeft: number,
	crunchiness: number,
	shine: number,
	drive: number,
	restSeen: number,
	rewaxCount: number,
	events: { CrackEvent },
}

-- Module tables

local CoatClass = {}
CoatClass.__index = CoatClass

export type Coat = typeof(setmetatable({} :: CoatData, CoatClass))

local WaxCoat = {}

-- Constants

local WAX = Config.Wax
local CELLS = WAX.cells
local STRESS = WAX.stress
local CRACKS = WAX.cracks
local PAN = Config.Knead.sounds.pan
local GRID_OFFSET = 1024 -- the design's grid key: ((x + 1024)·2048 + (y + 1024))·2048 + (z + 1024) (squish.js:232)
local GRID_SPAN = 2048

-- Private

local function gridKey(x: number, y: number, z: number): number
	return ((x + GRID_OFFSET) * GRID_SPAN + (y + GRID_OFFSET)) * GRID_SPAN + (z + GRID_OFFSET)
end

-- The design's normal deviate (squish.js:18).
local function gauss(rng: Random): number
	local u = 0
	while u == 0 do
		u = rng:NextNumber()
	end
	return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * rng:NextNumber())
end

-- The face-normal sum over a cell's one-ring at positions (px, py, pz), not normalized.
local function ringNormal(
	tris: { number },
	ringTris: { number },
	from: number,
	to: number,
	px: { number },
	py: { number },
	pz: { number }
): (number, number, number)
	local sx, sy, sz = 0, 0, 0
	for j = from, to do
		local t = ringTris[j]
		local a, b, c = tris[3 * t - 2], tris[3 * t - 1], tris[3 * t]
		local ex, ey, ez = px[b] - px[a], py[b] - py[a], pz[b] - pz[a]
		local fx, fy, fz = px[c] - px[a], py[c] - py[a], pz[c] - pz[a]
		sx += ey * fz - ez * fy
		sy += ez * fx - ex * fz
		sz += ex * fy - ey * fx
	end
	return sx, sy, sz
end

-- Public

function WaxCoat.new(body: Body, options: Options?): Coat
	local shell = body.shell
	local n = shell.count
	local rng: Random = if options and options.rng then options.rng else Random.new()
	local coatRow = WAX.coats[body.feel]
	local thBase = coatRow.th * WAX.thScale
	local px, py, pz = shell.px, shell.py, shell.pz
	local function onCoat(i: number): boolean
		return shell.parts[shell.vertexPart[i]].wax
	end

	-- Poisson-disk cells, part by part in a shuffled order (squish.js:232-249).
	local dc = CELLS.spacing * body.maxDim
	local inv, dc2 = 1 / dc, dc * dc
	local maxCells = CELLS.maxCells
	local grid: { [number]: { number } } = {}
	local cellVertex = {}
	local cellTh = {}
	for _, part in shell.parts do
		if not part.wax or #cellVertex >= maxCells then
			continue
		end
		local order = table.create(part.count, 0)
		for k = 1, part.count do
			order[k] = part.first + k - 1
		end
		for k = part.count, 2, -1 do
			local j = math.floor(rng:NextNumber() * k) + 1
			order[k], order[j] = order[j], order[k]
		end
		for _, i in order do
			local x, y, z = px[i], py[i], pz[i]
			local gx, gy, gz = math.floor(x * inv), math.floor(y * inv), math.floor(z * inv)
			local ok = true
			for a = -1, 1 do
				for b = -1, 1 do
					for e = -1, 1 do
						local list = grid[gridKey(gx + a, gy + b, gz + e)]
						if list and ok then
							for _, c in list do
								local v = cellVertex[c]
								if (px[v] - x) ^ 2 + (py[v] - y) ^ 2 + (pz[v] - z) ^ 2 < dc2 then
									ok = false
									break
								end
							end
						end
					end
				end
			end
			if not ok then
				continue
			end
			table.insert(cellVertex, i)
			local count = #cellVertex
			cellTh[count] = thBase * math.exp(CELLS.thSpread * gauss(rng))
			local key = gridKey(gx, gy, gz)
			local list = grid[key]
			if list then
				table.insert(list, count)
			else
				grid[key] = { count }
			end
			if count >= maxCells then
				break
			end
		end
	end
	local cellCount = #cellVertex

	-- Neighbours within neighbourRadius·dc (squish.js:250-251), CSR.
	local nb2 = (CELLS.neighbourRadius * dc) ^ 2
	local neighbours: { { number } } = table.create(cellCount)
	for k = 1, cellCount do
		neighbours[k] = {}
	end
	for a = 1, cellCount do
		local va = cellVertex[a]
		for b = a + 1, cellCount do
			local vb = cellVertex[b]
			if (px[va] - px[vb]) ^ 2 + (py[va] - py[vb]) ^ 2 + (pz[va] - pz[vb]) ^ 2 < nb2 then
				table.insert(neighbours[a], b)
				table.insert(neighbours[b], a)
			end
		end
	end
	local nbStart, nbList = table.create(cellCount + 1, 0), {}
	for k = 1, cellCount do
		nbStart[k] = #nbList + 1
		for _, j in neighbours[k] do
			table.insert(nbList, j)
		end
	end
	nbStart[cellCount + 1] = #nbList + 1

	-- Footprints: the coat vertices within footprintRadius·dc, weight (1 - d² / rc²)² (squish.js:252-265), CSR.
	local rc = CELLS.footprintRadius * dc
	local rc2, ir = rc * rc, 1 / rc
	local cellGrid: { [number]: { number } } = {}
	for k, v in cellVertex do
		local key = gridKey(math.floor(px[v] * ir), math.floor(py[v] * ir), math.floor(pz[v] * ir))
		local list = cellGrid[key]
		if list then
			table.insert(list, k)
		else
			cellGrid[key] = { k }
		end
	end
	local feet: { { number } } = table.create(cellCount)
	for k = 1, cellCount do
		feet[k] = {}
	end
	for i = 1, n do
		if not onCoat(i) then
			continue
		end
		local x, y, z = px[i], py[i], pz[i]
		local gx, gy, gz = math.floor(x * ir), math.floor(y * ir), math.floor(z * ir)
		for a = -1, 1 do
			for b = -1, 1 do
				for e = -1, 1 do
					local list = cellGrid[gridKey(gx + a, gy + b, gz + e)]
					if list == nil then
						continue
					end
					for _, k in list do
						local v = cellVertex[k]
						local d2 = (px[v] - x) ^ 2 + (py[v] - y) ^ 2 + (pz[v] - z) ^ 2
						if d2 < rc2 then
							local q = 1 - d2 / rc2
							table.insert(feet[k], i)
							table.insert(feet[k], q * q)
						end
					end
				end
			end
		end
	end
	local footStart, footVertex, footWeight = table.create(cellCount + 1, 0), {}, {}
	for k = 1, cellCount do
		footStart[k] = #footVertex + 1
		local list = feet[k]
		for j = 1, #list, 2 do
			table.insert(footVertex, list[j])
			table.insert(footWeight, list[j + 1])
		end
	end
	footStart[cellCount + 1] = #footVertex + 1

	-- Each cell's one-ring triangles, its rest normal and its rest one-ring normal.
	local cellOf: { [number]: number } = {}
	for k, v in cellVertex do
		cellOf[v] = k
	end
	local rings: { { number } } = table.create(cellCount)
	for k = 1, cellCount do
		rings[k] = {}
	end
	local tris = shell.tris
	for t = 1, shell.triCount do
		for m = 0, 2 do
			local k = cellOf[tris[3 * t - m]]
			if k then
				table.insert(rings[k], t)
			end
		end
	end
	local ringStart, ringTris = table.create(cellCount + 1, 0), {}
	local restNx, restNy, restNz = table.create(cellCount, 0), table.create(cellCount, 0), table.create(cellCount, 0)
	local ringNx, ringNy, ringNz = table.create(cellCount, 0), table.create(cellCount, 0), table.create(cellCount, 0)
	for k = 1, cellCount do
		ringStart[k] = #ringTris + 1
		for _, t in rings[k] do
			table.insert(ringTris, t)
		end
		local v = cellVertex[k]
		restNx[k], restNy[k], restNz[k] = shell.nx[v], shell.ny[v], shell.nz[v]
		local sx, sy, sz = ringNormal(tris, ringTris, ringStart[k], #ringTris, px, py, pz)
		local l = math.sqrt(sx * sx + sy * sy + sz * sz)
		if l == 0 then
			l = 1
		end
		ringNx[k], ringNy[k], ringNz[k] = sx / l, sy / l, sz / l
	end
	ringStart[cellCount + 1] = #ringTris + 1

	local data: CoatData = {
		body = body,
		rng = rng,
		thBase = thBase,
		wear = coatRow.wear,
		spacing = dc,
		cellCount = cellCount,
		cellVertex = cellVertex,
		cellS = table.create(cellCount, 0),
		cellTh = cellTh,
		cellI = table.create(cellCount, 1),
		cellM = table.create(cellCount, 0),
		cellNx = table.clone(restNx),
		cellNy = table.clone(restNy),
		cellNz = table.clone(restNz),
		restNx = restNx,
		restNy = restNy,
		restNz = restNz,
		ringNx = ringNx,
		ringNy = ringNy,
		ringNz = ringNz,
		ringStart = ringStart,
		ringTris = ringTris,
		nbStart = nbStart,
		nbList = nbList,
		footStart = footStart,
		footVertex = footVertex,
		footWeight = footWeight,
		damage = table.create(n, 0),
		touched = {},
		touchedCount = 0,
		touchedMark = table.create(n, false),
		candidates = {},
		cracks = 0,
		waxLeft = 1,
		crunchiness = 1,
		shine = 0,
		drive = 0,
		restSeen = body.restCount,
		rewaxCount = 0,
		events = {},
	}
	return setmetatable(data, CoatClass)
end

-- Private

-- A crack's damage on its footprint (design: squish.js:267-270).
function CoatClass._damage(self: Coat, k: number, E: number)
	local a = CRACKS.damage * E
	local damage, touched, mark = self.damage, self.touched, self.touchedMark
	local footVertex, footWeight = self.footVertex, self.footWeight
	for j = self.footStart[k], self.footStart[k + 1] - 1 do
		local i = footVertex[j]
		local v = damage[i] + a * footWeight[j]
		damage[i] = if v > 1 then 1 else v
		if not mark[i] then
			mark[i] = true
			self.touchedCount += 1
			touched[self.touchedCount] = i
		end
	end
end

-- The cells' load and cracks for one frame of the body (design: squish.js:273-298); returns the cracks that sounded.
function CoatClass._load(self: Coat, dt: number): number
	local body = self.body
	local shell = body.shell
	local tris = shell.tris
	local px, py, pz = body.px, body.py, body.pz
	local xs, ys, zs = body.xs, body.ys, body.zs
	local iRF = 1 / body.rF
	local relax = math.exp(-dt * STRESS.relax)
	local bend, worn = STRESS.bend, STRESS.worn
	local cellVertex, cellS, cellTh, cellI, cellM = self.cellVertex, self.cellS, self.cellTh, self.cellI, self.cellM
	local cellNx, cellNy, cellNz = self.cellNx, self.cellNy, self.cellNz
	local restNx, restNy, restNz = self.restNx, self.restNy, self.restNz
	local ringNx, ringNy, ringNz = self.ringNx, self.ringNy, self.ringNz
	local ringStart, ringTris = self.ringStart, self.ringTris
	local candidates = self.candidates
	local count = self.cellCount
	local sum, intact, found = 0, 0, 0
	for k = 1, count do
		local i = cellVertex[k]
		local sx, sy, sz = ringNormal(tris, ringTris, ringStart[k], ringStart[k + 1] - 1, px, py, pz)
		local l = math.sqrt(sx * sx + sy * sy + sz * sz)
		if l == 0 then
			l = 1
		end
		local nx = restNx[k] + sx / l - ringNx[k]
		local ny = restNy[k] + sy / l - ringNy[k]
		local nz = restNz[k] + sz / l - ringNz[k]
		local ln = math.sqrt(nx * nx + ny * ny + nz * nz)
		if ln == 0 then
			ln = 1
		end
		nx, ny, nz = nx / ln, ny / ln, nz / ln
		local ang = math.sqrt(math.max(0, 2 - 2 * (nx * cellNx[k] + ny * cellNy[k] + nz * cellNz[k])))
		local m = math.sqrt(xs[i] * xs[i] + ys[i] * ys[i] + zs[i] * zs[i])
		local st = bend * ang + math.abs(m - cellM[k]) * iRF
		cellNx[k], cellNy[k], cellNz[k] = nx, ny, nz
		cellM[k] = m
		sum += st
		intact += cellI[k]
		local s = cellS[k] * relax + st * (worn + (1 - worn) * cellI[k])
		cellS[k] = s
		if s > cellTh[k] then
			found += 1
			candidates[found] = k
		end
	end
	self.waxLeft = if count > 0 then intact / count else 1
	self.drive = if count > 0 then math.min(1, sum / dt / count / WAX.driveStrain) else 0
	if found == 0 then
		return 0
	end
	if found > 1 then
		table.sort(candidates, function(a: number, b: number): boolean
			return cellS[a] / cellTh[a] > cellS[b] / cellTh[b]
		end)
	end
	local rng = self.rng
	local sounded = 0
	for q = 1, found do
		local k = candidates[q]
		local I = cellI[k]
		local E = math.clamp(
			cellS[k] / cellTh[k] * math.exp(CRACKS.energySpread * gauss(rng)),
			CRACKS.energyMin,
			CRACKS.energyMax
		) * (CRACKS.energyWorn + (1 - CRACKS.energyWorn) * I)
		cellS[k] = math.max(0, cellS[k] - cellTh[k] * rng:NextNumber(CRACKS.dropMin, 1))
		cellTh[k] = self.thBase * math.exp(CELLS.thSpread * gauss(rng))
		if q > CRACKS.sounding then
			continue
		end
		sounded += 1
		self.crunchiness += (I - self.crunchiness) * CRACKS.crunchinessRate
		I = math.max(0, I - self.wear * E)
		cellI[k] = I
		self:_damage(k, E)
		self.cracks += 1
		for j = self.nbStart[k], self.nbStart[k + 1] - 1 do
			local o = self.nbList[j]
			cellS[o] += cellTh[o] * CRACKS.cascade * rng:NextNumber() * cellI[o]
		end
		local i = cellVertex[k]
		local x = -shell.px[i] -- the rest x, design frame (squish.js:319)
		table.insert(self.events, {
			E = E,
			intact = I,
			pan = math.clamp((x - body.ctrX) / (body.sizeX * 0.5), -1, 1) * PAN,
			position = Vector3.new(px[i], py[i], pz[i]),
			normal = Vector3.new(cellNx[k], cellNy[k], cellNz[k]),
			cell = k,
		})
	end
	table.clear(candidates)
	return sounded
end

-- Public

function CoatClass.step(self: Coat, dt: number): number
	local body = self.body
	if body.restCount ~= self.restSeen then
		-- The body snapped to rest (design: squish.js:646).
		self.restSeen = body.restCount
		for k = 1, self.cellCount do
			self.cellNx[k], self.cellNy[k], self.cellNz[k] = self.restNx[k], self.restNy[k], self.restNz[k]
			self.cellM[k] = 0
			self.cellS[k] *= 0.5
		end
	end
	local sounded = 0
	if body.active and dt > 0 and self.cellCount > 0 then
		sounded = self:_load(dt)
	end
	self.shine = math.max(0, self.shine - dt * WAX.shineDecay)
	return sounded
end

-- design: squish.js:305-309
function CoatClass.rewax(self: Coat)
	local damage = self.damage
	for i = 1, #damage do
		damage[i] = 0
	end
	for k = 1, self.cellCount do
		self.cellI[k] = 1
		self.cellS[k] = 0
	end
	self.cracks = 0
	self.waxLeft = 1
	self.crunchiness = 1
	self.shine = 1
	self.rewaxCount += 1
	self:clearTouched()
end

function CoatClass.takeEvents(self: Coat): { CrackEvent }
	local events = self.events
	self.events = {}
	return events
end

function CoatClass.clearTouched(self: Coat)
	local mark = self.touchedMark
	for k = 1, self.touchedCount do
		mark[self.touched[k]] = false
	end
	self.touchedCount = 0
end

return WaxCoat
