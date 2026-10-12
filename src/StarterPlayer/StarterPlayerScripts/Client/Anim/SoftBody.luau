--!strict
--!native
-- SoftBody (client only; pure: no instances, connections, yields or clock reads; dt injected). Spec phase2-squeeze
-- §1.3-§1.12, §3.3: the port of the 3D Lab's SoftSquish (design sd/squish.js:129-658), the knead screen's per-vertex
-- soft body, on an Anim/ShellGeometry shell. Every number is in Config.Knead with its squish.js line; the few formula
-- constants below cite theirs.
--
-- Frames. Inputs and outputs are in the shell's model space (the toy faces -Z). Inside, every formula runs in the
-- design frame (the model turned 180° about Y: x and z negated), where the toy faces +Z as the design's toys do, so
-- "front", "the left thumb" and "toward the camera" keep the design's meaning (spec "Axes").
--
-- API
--   SoftBody.new(shell, options) -> Body
--     options.feel           a Config.Knead.feels key (the blueprint's motion.feel); unknown -> defaultFeel (foam)
--     options.squeezeDepth   the toy's motion.squeeze.depth (the palms' depth, squish.js:392)
--     options.faceMin / faceMax   the bounds of the toy's face parts (model space); without them the design's fallback
--     options.rng            a Random for the crunch jitter (default Random.new())
--   body:fingerDown(point, normal)  press a finger at a rest-space surface point (body:restHit maps a raycast hit)
--   body:fingerMove(point, normal)  knead: slide it; the path is stamped into the memory field with smear
--   body:pullTo(origin, direction)  the finger left the silhouette: stretch toward this ray (rest space)
--   body:fingerUp(silent?)          let go (also ends a stretch)
--   body:palms(on), body:thumbs(on) the palm squeeze and the thumb crunch, held
--   body:step(dt) -> boolean        one frame; true when a shown position moved (written lists them)
--   body:restHit(a, b, c, wa, wb, wc) -> (Vector3?, Vector3?)   a raycast hit (its triangle's vertex ids and
--                                   barycentric weights) to the rest point and normal (squish.js:461-470)
--   body:thumbTip(k) -> Vector3?    thumb k's tip, the bottom of its dent (1 = A, the viewer's left; 2 = B)
--   body:brush(k) -> BrushInfo?     brush slot k (1..brushSlots), model space
--   body:displacement(i), body:memory(i) -> Vector3   vertex i's spring displacement and memory, model space
--   body:pullVector() -> Vector3    the stretch, model space
--   body:takeEvents() -> { Event }  the kicks and sound cues since the last call (below)
--   SoftBody.profile(s, q2, beta, pw), SoftBody.slowRise(age, rise), SoftBody.crunchTarget(t): the design formulas
--
-- Readable state (never write it): px, py, pz (shown positions, model space, for vertices 1..shell.count; the anchors
-- never move), written[1..writtenCount] (the vertices this step moved), press (min(1, |x| / dF) per vertex, for
-- shading), active, faceSquish, palmC, palmD, crunchP, pulling, pullLength, holding, since, pressSignal (the audio's
-- press amount, squish.js:633), inflation (the bulge) and shownInflation (the one this step's positions use),
-- restCount (+1 each time it snaps to rest), center, size, maxDim, minDim, rF, dF, cap, maxPull, rP, eps, writeEps, J
-- (lumps), age, stamps (memory stamps so far), xs / ys / zs (displacement, design frame), sleeping (per vertex: at
-- rest exactly, only the bulge moves it).
--
-- Events (takeEvents), in call order, at the design's call sites:
--   { kind = "kick", amount, axis = "X" | "Y" | "Z" }  the soft jiggle kick (squish.js:321); the rig converts it
--   { kind = "squisherKick", amount }                   the Squisher's velocity kick (toys.js:442)
--   { kind = "press", brush, pan }, { kind = "release", brush, amount, pan }, { kind = "air", amount, pan },
--   { kind = "snap", amount, slipped, pan }             the wax engine's cues (squish.js:796-945); brush = "finger" |
--                                                       "palm" | "thumb"
--   pan = clamp((x - ctr.x) / (s.x / 2), -1, 1)·Config.Knead.sounds.pan in the design frame (the viewer's right > 0).
--   The design's finger-slide squish (squish.js:340) is silent with the wax coat (squish.js:910-911): not sent.
--
-- Speed (spec §3.3): flat arrays and --!native; only awake vertices are stepped: one with no memory, no brush within
-- reach, no pinch and no stretch that is within eps of rest snaps to rest and sleeps (then only the bulge moves it);
-- a vertex is written only when its shown position moved more than writeEps. Shown positions are clamped into the
-- shell's anchored bounds, so the MeshPart never rescales (proposal). A dt longer than Config.Anim.Scheduler.maxDt is
-- clamped. Left to the caller (spec §3.3): normals (the engine's), the whole-toy jiggle (the rig, from the kicks) and
-- the wax coat (Anim/WaxCoat reads this body).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ShellGeometry = require(script.Parent.ShellGeometry)

-- Types

type Shell = ShellGeometry.Shell
type Feel = typeof(Config.Knead.feels.foam)

export type Options = {
	feel: string?,
	squeezeDepth: number,
	faceMin: Vector3?,
	faceMax: Vector3?,
	rng: Random?,
}

export type Event = {
	kind: string,
	amount: number?,
	axis: string?,
	brush: string?,
	pan: number?,
	slipped: boolean?,
}

export type BrushInfo = {
	kind: string,
	live: boolean,
	on: boolean,
	centre: Vector3,
	direction: Vector3,
	radius: number,
	falloff: number,
	depth: number,
	depthMax: number,
	power: number,
	beta: number,
	amount: number,
}

-- One brush slot (design: squish.js:193, 313-317), design frame: centre c, press direction u (into the toy), radius r,
-- depth falloff T, depth d and its speed v, the target depth dMax, profile power pw, rim beta, age t, amount amt, and
-- its unstamped strokes (12 numbers each: from, to, u at from, u at to). While it stays put, the static part of its
-- dent (everything but the depth d) is cached: liveG per vertex for the live dent (OUTSIDE past the cut-off), and
-- stampG for its memory stamp on the stampCount vertices of stampList; a move or a new placement clears them.
type Brush = {
	kind: string,
	live: boolean,
	on: boolean,
	cx: number,
	cy: number,
	cz: number,
	ux: number,
	uy: number,
	uz: number,
	r: number,
	T: number,
	ir2: number,
	iT2: number,
	d: number,
	v: number,
	dMax: number,
	pw: number,
	beta: number,
	t: number,
	amt: number,
	strokes: { number },
	strokeCount: number,
	liveG: { number },
	stampList: { number },
	stampG: { number },
	stampCount: number,
	liveValid: boolean,
	stampValid: boolean,
}

type BodyData = {
	shell: Shell,
	count: number,
	feel: string,
	F: Feel,
	squeezeDepth: number,
	rng: Random,
	-- the box, design frame (squish.js:171-174)
	minX: number,
	minY: number,
	minZ: number,
	maxX: number,
	maxY: number,
	maxZ: number,
	ctrX: number,
	ctrY: number,
	ctrZ: number,
	sizeX: number,
	sizeY: number,
	sizeZ: number,
	center: Vector3,
	size: Vector3,
	maxDim: number,
	minDim: number,
	rF: number,
	dF: number,
	cap: number,
	maxPull: number,
	rP: number,
	eps: number,
	writeEps: number,
	-- per vertex: rest (design frame), rest (model space, the shell's own arrays), lumps, state, output
	rx: { number },
	ry: { number },
	rz: { number },
	rnx: { number },
	rny: { number },
	rnz: { number },
	restX: { number },
	restY: { number },
	restZ: { number },
	J: { number },
	xs: { number },
	ys: { number },
	zs: { number },
	vxs: { number },
	vys: { number },
	vzs: { number },
	mxs: { number },
	mys: { number },
	mzs: { number },
	age: { number },
	aw: { number },
	sleeping: { boolean },
	px: { number },
	py: { number },
	pz: { number },
	press: { number },
	written: { number },
	writtenCount: number,
	area: number,
	frontList: { number },
	faceX: number,
	faceY: number,
	faceZ: number,
	faceR: number,
	-- the pinch field at P = 1 (design frame), set when the crunch starts
	kx: { number },
	ky: { number },
	kz: { number },
	-- brushes and gestures
	brushes: { Brush },
	lb: { number },
	lbBrush: { Brush },
	finger: number,
	palmL: number,
	palmR: number,
	thumbA: number,
	thumbB: number,
	holding: boolean,
	pulling: boolean,
	gx: number,
	gy: number,
	gz: number,
	pux: number,
	puy: number,
	puz: number,
	pvx: number,
	pvy: number,
	pvz: number,
	pullLength: number,
	crunchOn: boolean,
	crunchT: number,
	crunchK: number,
	crunchP: number,
	ju: number,
	jv: number,
	pinchX: number,
	g0: number,
	shift: number,
	-- frame state
	active: boolean,
	idleT: number,
	since: number,
	inflation: number,
	shownInflation: number,
	palmC: number,
	palmD: number,
	faceSquish: boolean,
	pressSignal: number,
	restCount: number,
	stamps: number,
	events: { Event },
}

-- Module tables

local BodyClass = {}
BodyClass.__index = BodyClass

export type Body = typeof(setmetatable({} :: BodyData, BodyClass))

local SoftBody = {}

-- Constants

local KNEAD = Config.Knead
local FINGER = KNEAD.finger
local PALM = KNEAD.palm
local THUMB = KNEAD.thumb
local DEPTH = KNEAD.depth
local MEMORY = KNEAD.memory
local PULL = KNEAD.pull
local CRUNCH = KNEAD.crunch
local PINCH = KNEAD.pinch
local KICKS = KNEAD.kicks
local SOUNDS = KNEAD.sounds
local FACE = KNEAD.face
local BULGE = KNEAD.bulge
local BRUSH_SLOTS = KNEAD.brushSlots
local SPRING_SUBSTEPS = KNEAD.springSubstepsPerSecond
local MAX_DT = Config.Anim.Scheduler.maxDt

local LIVE_CUTOFF = 7 -- the live dent is cut off past s or q2 = 7 (design: squish.js:578, 580)
local STAMP_CUTOFF = 6 -- the stamp past 6 (design: squish.js:496, 498)
local ABOVE = 0.25 -- above the contact (h < 0) the depth term falls off 4× slower (design: squish.js:495, 577)
local MIN_STAMP = 1e-9 -- a smaller stamp is skipped (design: squish.js:503)
local PRESSED_DEPTH = 1e-7 -- a brush stamps while deeper (design: squish.js:536)
local MIN_MOVE = 1e-7 -- a shorter finger move is ignored (design: squish.js:336)
local MIN_PULL = 1e-9 -- design: squish.js:357, 544
local MIN_SIZE = 1e-6 -- design: squish.js:172, 553
local MIN_NORMAL_SQ = 1e-8 -- design: squish.js:468
local MIN_THUMB_MOVE_SQ = 1e-12 -- design: squish.js:453
local NO_MEMORY = 1e9 -- the age of a vertex with no memory (design: squish.js:165, 645)
local OUTSIDE = math.huge -- a cached dent entry for a vertex past the cut-off
local STROKE = 12 -- numbers a stroke
local LB = 11 -- numbers a packed live brush: c (3), u (3), ir2, iT2, d, beta, pw
-- proposal (PadDent's writeEpsilon rule, Anim/PadDent): a vertex is rewritten once its shown position moved more than
-- eps × this.
local WRITE_SHARE = 0.25

-- The pinch constants (read by _pinchField).
local RIDGE_BASE = PINCH.ridgeBase
local RIDGE_WIDTH = PINCH.ridgeWidth
local CENTRE_Y = PINCH.centreY
local DIP_START = PINCH.dipStart
local DIP_SPAN = PINCH.dipSpan
local DIP_BASE = PINCH.dipBase
local FRONT_START = PINCH.frontStart
local FRONT_SPAN = PINCH.frontSpan
local DX_BASE = PINCH.dxBase
local DX_FLOOR = PINCH.dxFloor
local DX_WIDTH = PINCH.dxWidth

-- Private: the design's helpers (squish.js:14-26)

local function clamp01(x: number): number
	return if x < 0 then 0 elseif x > 1 then 1 else x
end

-- sm: smoothstep on [0, 1] (design: squish.js:15)
local function smooth(x: number): number
	x = clamp01(x)
	return x * x * (3 - 2 * x)
end

-- ease: the cosine ease (design: squish.js:16)
local function ease(t: number): number
	return 0.5 - 0.5 * math.cos(math.pi * clamp01(t))
end

-- The design's value-noise hash and its smoothed noise (design: squish.js:20-26).
local function hash(x: number, y: number, z: number): number
	local s = math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453
	return s - math.floor(s)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function vnoise(x: number, y: number, z: number): number
	local ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
	local fx, fy, fz = x - ix, y - iy, z - iz
	fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
	local function h(a: number, b: number, c: number): number
		return hash(ix + a, iy + b, iz + c)
	end
	return lerp(
		lerp(lerp(h(0, 0, 0), h(1, 0, 0), fx), lerp(h(0, 1, 0), h(1, 1, 0), fx), fy),
		lerp(lerp(h(0, 0, 1), h(1, 0, 1), fx), lerp(h(0, 1, 1), h(1, 1, 1), fx), fy),
		fz
	)
end

-- The dominant axis of a press direction (design: squish.js:320).
local function axisOf(ux: number, uy: number, uz: number): string
	local x, y, z = math.abs(ux), math.abs(uy), math.abs(uz)
	return if x > y and x > z then "X" elseif y > z then "Y" else "Z"
end

local function newBrush(n: number): Brush
	return {
		kind = "finger",
		live = false,
		on = false,
		cx = 0,
		cy = 0,
		cz = 0,
		ux = 0,
		uy = 0,
		uz = 0,
		r = 1,
		T = 1,
		ir2 = 1,
		iT2 = 1,
		d = 0,
		v = 0,
		dMax = 1,
		pw = 1,
		beta = 0.5,
		t = 0,
		amt = 1,
		strokes = {},
		strokeCount = 0,
		liveG = table.create(n, OUTSIDE),
		stampList = table.create(n, 0),
		stampG = table.create(n, 0),
		stampCount = 0,
		liveValid = false,
		stampValid = false,
	}
end

-- Public: the design formulas

-- The live dent's shape at sideways s = (distance / r)² and depth q2 = (h / T)² (h above the contact × 0.25): its value
-- is d·profile·J (design: squish.js:575-584). Past 7 on either it is 0.
function SoftBody.profile(s: number, q2: number, beta: number, pw: number): number
	if s > LIVE_CUTOFF or q2 > LIVE_CUTOFF then
		return 0
	end
	return math.exp(-(if pw == 1 then s else s * math.sqrt(s)) - q2) * (1 - beta * s)
end

-- The share of a memory still shown at `age` (design: squish.js:500, 562-566).
function SoftBody.slowRise(age: number, rise: number): number
	if age >= rise then
		return 0
	end
	return 1 - smooth(age / rise)
end

-- The thumb crunch's target at `t` seconds into the crunch (design: squish.js:444-447).
function SoftBody.crunchTarget(t: number): number
	local period = CRUNCH.period
	local cycle = math.floor(t / period)
	local phase = t / period - cycle
	local low = if cycle > 0 then CRUNCH.low else 0
	if phase < CRUNCH.pressEnd then
		return low + (1 - low) * ease(phase / CRUNCH.pressEnd)
	elseif phase < CRUNCH.holdEnd then
		return 1
	end
	return 1 - CRUNCH.releaseDrop * ease((phase - CRUNCH.holdEnd) / (1 - CRUNCH.holdEnd))
end

-- Public: construction

function SoftBody.new(shell: Shell, options: Options): Body
	assert(type(options) == "table", "[SD][SoftBody] new needs options")
	local squeezeDepth = options.squeezeDepth
	assert(
		type(squeezeDepth) == "number" and squeezeDepth >= 0 and squeezeDepth < 1,
		"[SD][SoftBody] options.squeezeDepth must be in [0, 1)"
	)
	local feel = if type(options.feel) == "string" and KNEAD.feels[options.feel] ~= nil
		then options.feel :: string
		else KNEAD.defaultFeel
	local F: Feel = KNEAD.feels[feel]
	local n = shell.count

	-- The box (design: squish.js:171-174): model bounds turned into the design frame (x and z negated).
	local restMin, restMax = shell.restMin, shell.restMax
	local sizeX, sizeY, sizeZ = restMax.X - restMin.X, restMax.Y - restMin.Y, restMax.Z - restMin.Z
	local maxDim = math.max(sizeX, sizeY, sizeZ, MIN_SIZE)
	local minDim = math.max(math.min(sizeX, sizeY, sizeZ), MIN_SIZE)
	local rF = FINGER.radius * maxDim
	local eps = KNEAD.restEpsilon * maxDim

	local rx, ry, rz = table.create(n, 0), table.create(n, 0), table.create(n, 0)
	local rnx, rny, rnz = table.create(n, 0), table.create(n, 0), table.create(n, 0)
	local J = table.create(n, 1)
	local fq = 1 / (KNEAD.lumpScale * rF)
	for i = 1, n do
		rx[i], ry[i], rz[i] = -shell.px[i], shell.py[i], -shell.pz[i]
		rnx[i], rny[i], rnz[i] = -shell.nx[i], shell.ny[i], -shell.nz[i]
		J[i] = 1 - F.lump * 0.5 + F.lump * vnoise(rx[i] * fq, ry[i] * fq, rz[i] * fq) -- squish.js:177
	end

	-- The body: the biggest shell by vertex count; its area weights (a third of each triangle) feed the bulge
	-- (design: squish.js:178-186). frontPoint picks among its front vertices (squish.js:475).
	local bodyPart = 1
	for index, part in shell.parts do
		if part.count > shell.parts[bodyPart].count then
			bodyPart = index
		end
	end
	local aw = table.create(n, 0)
	local area = 0
	local tris = shell.tris
	for k = 1, shell.triCount do
		if shell.triPart[k] == bodyPart then
			local a, b, c = tris[3 * k - 2], tris[3 * k - 1], tris[3 * k]
			local ex, ey, ez = rx[b] - rx[a], ry[b] - ry[a], rz[b] - rz[a]
			local fx, fy, fz = rx[c] - rx[a], ry[c] - ry[a], rz[c] - rz[a]
			local cx, cy, cz = ey * fz - ez * fy, ez * fx - ex * fz, ex * fy - ey * fx
			local third = math.sqrt(cx * cx + cy * cy + cz * cz) * 0.5 / 3
			area += 3 * third
			aw[a] += third
			aw[b] += third
			aw[c] += third
		end
	end
	local frontList = {}
	for i = 1, n do
		if shell.vertexPart[i] == bodyPart and rnz[i] >= CRUNCH.frontMinZ then
			table.insert(frontList, i)
		end
	end

	-- The face centre and radius (design: squish.js:189-192), from the face parts' bounds when given.
	local minX, maxX = -restMax.X, -restMin.X
	local minZ, maxZ = -restMax.Z, -restMin.Z
	local ctrX, ctrY, ctrZ = (minX + maxX) / 2, (restMin.Y + restMax.Y) / 2, (minZ + maxZ) / 2
	local faceX, faceY, faceZ = ctrX, ctrY + FACE.fallbackLift * sizeY, maxZ
	local faceR = FACE.fallbackRadius * sizeX
	if options.faceMin and options.faceMax then
		local middle = (options.faceMin + options.faceMax) / 2
		faceX, faceY, faceZ = -middle.X, middle.Y, -middle.Z
		faceR = math.max((options.faceMax - options.faceMin).Magnitude * 0.5, FACE.minRadius * sizeX)
	end

	local brushes = {}
	for q = 1, BRUSH_SLOTS do
		brushes[q] = newBrush(n)
	end
	local sleeping = table.create(n, true)

	local data: BodyData = {
		shell = shell,
		count = n,
		feel = feel,
		F = F,
		squeezeDepth = squeezeDepth,
		rng = options.rng or Random.new(),
		minX = minX,
		minY = restMin.Y,
		minZ = minZ,
		maxX = maxX,
		maxY = restMax.Y,
		maxZ = maxZ,
		ctrX = ctrX,
		ctrY = ctrY,
		ctrZ = ctrZ,
		sizeX = sizeX,
		sizeY = sizeY,
		sizeZ = sizeZ,
		center = (restMin + restMax) / 2,
		size = restMax - restMin,
		maxDim = maxDim,
		minDim = minDim,
		rF = rF,
		dF = math.min(FINGER.depthOfRadius * rF, FINGER.depthOfMinDim * minDim),
		cap = MEMORY.capOfRadius * rF,
		maxPull = F.pull * maxDim,
		rP = F.pullR * maxDim,
		eps = eps,
		writeEps = eps * WRITE_SHARE,
		rx = rx,
		ry = ry,
		rz = rz,
		rnx = rnx,
		rny = rny,
		rnz = rnz,
		restX = shell.px,
		restY = shell.py,
		restZ = shell.pz,
		J = J,
		xs = table.create(n, 0),
		ys = table.create(n, 0),
		zs = table.create(n, 0),
		vxs = table.create(n, 0),
		vys = table.create(n, 0),
		vzs = table.create(n, 0),
		mxs = table.create(n, 0),
		mys = table.create(n, 0),
		mzs = table.create(n, 0),
		age = table.create(n, NO_MEMORY),
		aw = aw,
		sleeping = sleeping,
		px = table.move(shell.px, 1, n, 1, table.create(n, 0)),
		py = table.move(shell.py, 1, n, 1, table.create(n, 0)),
		pz = table.move(shell.pz, 1, n, 1, table.create(n, 0)),
		press = table.create(n, 0),
		written = table.create(n, 0),
		writtenCount = 0,
		area = math.max(area, MIN_SIZE),
		frontList = frontList,
		faceX = faceX,
		faceY = faceY,
		faceZ = faceZ,
		faceR = faceR,
		kx = table.create(n, 0),
		ky = table.create(n, 0),
		kz = table.create(n, 0),
		brushes = brushes,
		lb = table.create(BRUSH_SLOTS * LB, 0),
		lbBrush = table.create(BRUSH_SLOTS),
		finger = 0,
		palmL = 0,
		palmR = 0,
		thumbA = 0,
		thumbB = 0,
		holding = false,
		pulling = false,
		gx = 0,
		gy = 0,
		gz = 0,
		pux = 0,
		puy = 0,
		puz = 0,
		pvx = 0,
		pvy = 0,
		pvz = 0,
		pullLength = 0,
		crunchOn = false,
		crunchT = 0,
		crunchK = -1,
		crunchP = 0,
		ju = 0,
		jv = 0,
		pinchX = ctrX,
		g0 = 1,
		shift = 0,
		active = false,
		idleT = 0,
		since = 9, -- design: squish.js:198
		inflation = 0,
		shownInflation = 0,
		palmC = 0,
		palmD = 0,
		faceSquish = false,
		pressSignal = 0,
		restCount = 0,
		stamps = 0,
		events = {},
	}
	return setmetatable(data, BodyClass)
end

-- Private: events, brushes

function BodyClass._event(self: Body, event: Event)
	table.insert(self.events, event)
end

function BodyClass._kick(self: Body, amount: number, axis: string)
	self:_event({ kind = "kick", amount = amount, axis = axis })
end

function BodyClass._squisherKick(self: Body, amount: number)
	self:_event({ kind = "squisherKick", amount = amount })
end

-- design: squish.js:319
function BodyClass._pan(self: Body, x: number): number
	return math.clamp((x - self.ctrX) / (self.sizeX * 0.5), -1, 1) * SOUNDS.pan
end

function BodyClass._wake(self: Body)
	self.active = true
	self.idleT = 0
end

-- A free slot, else the shallowest released one, else the first (design: squish.js:312).
function BodyClass._slot(self: Body): number
	local best = 0
	for q = 1, BRUSH_SLOTS do
		local b = self.brushes[q]
		if not b.live then
			return q
		end
		if not b.on and (best == 0 or b.d < self.brushes[best].d) then
			best = q
		end
	end
	return if best > 0 then best else 1
end

-- design: squish.js:313-317
function BodyClass._set(
	self: Body,
	kind: string,
	cx: number,
	cy: number,
	cz: number,
	ux: number,
	uy: number,
	uz: number,
	r: number,
	T: number,
	dMax: number,
	pw: number,
	beta: number
): number
	local index = self:_slot()
	local b = self.brushes[index]
	local length = math.sqrt(ux * ux + uy * uy + uz * uz)
	if length == 0 then
		length = 1
	end
	b.kind, b.live, b.on = kind, true, true
	b.cx, b.cy, b.cz = cx, cy, cz
	b.ux, b.uy, b.uz = ux / length, uy / length, uz / length
	b.r, b.T, b.ir2, b.iT2 = r, T, 1 / (r * r), 1 / (T * T)
	b.dMax, b.pw, b.beta = dMax, pw, beta
	b.t, b.d, b.v, b.amt = 0, 0, 0, 1
	b.strokeCount = 0
	b.liveValid, b.stampValid = false, false
	self:_wake()
	return index
end

-- A stroke from the brush's centre and direction to (bx, by, bz) and (vx, vy, vz), stamped next step.
local function pushStroke(b: Brush, bx: number, by: number, bz: number, vx: number, vy: number, vz: number)
	local s = b.strokes
	local o = b.strokeCount * STROKE
	s[o + 1], s[o + 2], s[o + 3] = b.cx, b.cy, b.cz
	s[o + 4], s[o + 5], s[o + 6] = bx, by, bz
	s[o + 7], s[o + 8], s[o + 9] = b.ux, b.uy, b.uz
	s[o + 10], s[o + 11], s[o + 12] = vx, vy, vz
	b.strokeCount += 1
end

-- The body's front vertex nearest to (ctr.x + u·spanX·s.x, ctr.y + w·spanY·s.y) in x and y, with its rest normal
-- (design: squish.js:472-478). Design frame.
function BodyClass._frontPoint(self: Body, u: number, w: number): (number, number, number, number, number, number)
	local tx = self.ctrX + u * CRUNCH.spanX * self.sizeX
	local ty = self.ctrY + w * CRUNCH.spanY * self.sizeY
	local best, bestD = 0, math.huge
	local rx, ry = self.rx, self.ry
	for _, i in self.frontList do
		local dx, dy = rx[i] - tx, ry[i] - ty
		local d = dx * dx + dy * dy
		if d < bestD then
			best, bestD = i, d
		end
	end
	if best == 0 then
		return self.ctrX, self.ctrY, self.maxZ, 0, 0, 1
	end
	return rx[best], ry[best], self.rz[best], self.rnx[best], self.rny[best], self.rnz[best]
end

-- Private: the memory field (design: squish.js:488-517)

-- Stamps brush b at c (press direction u) into the memory, with the step's sideways move (dd) as smear.
function BodyClass._write(
	self: Body,
	cx: number,
	cy: number,
	cz: number,
	ux: number,
	uy: number,
	uz: number,
	b: Brush,
	ddx: number,
	ddy: number,
	ddz: number
)
	self.stamps += 1
	local F = self.F
	local rise = F.rise
	local val0 = b.d * (1 - F.fast)
	local ir2, iT2 = b.ir2, b.iT2
	local p15 = b.pw ~= 1
	local beta = b.beta
	local cap = self.cap
	local cap2 = cap * cap
	local keep = MEMORY.keepBelow
	local smearMin = MEMORY.smearMin
	local sideways = MEMORY.smearSideways
	local moved = ddx ~= 0 or ddy ~= 0 or ddz ~= 0
	if moved then
		local along = ddx * ux + ddy * uy + ddz * uz
		ddx, ddy, ddz = (ddx - along * ux) * F.smear, (ddy - along * uy) * F.smear, (ddz - along * uz) * F.smear
	end
	local rx, ry, rz, J = self.rx, self.ry, self.rz, self.J
	local mxs, mys, mzs, age = self.mxs, self.mys, self.mzs, self.age
	for i = 1, self.count do
		local vx, vy, vz = rx[i] - cx, ry[i] - cy, rz[i] - cz
		local hh = vx * ux + vy * uy + vz * uz
		local ha = if hh > 0 then hh else hh * ABOVE
		local q = ha * ha * iT2
		if q > STAMP_CUTOFF then
			continue
		end
		local tx, ty, tz = vx - hh * ux, vy - hh * uy, vz - hh * uz
		local s = (tx * tx + ty * ty + tz * tz) * ir2
		if s > STAMP_CUTOFF then
			continue
		end
		local rim = 1 - beta * s
		local val = val0 * math.exp(-(if p15 then s * math.sqrt(s) else s) - q) * (if rim > 0 then rim else 0) * J[i]
		local a = age[i]
		local R2 = 0
		if a < rise then
			local r = a / rise
			R2 = 1 - r * r * (3 - 2 * r)
		end
		local mx, my, mz = mxs[i] * R2, mys[i] * R2, mzs[i] * R2
		local cur = mx * ux + my * uy + mz * uz
		local es = if moved then math.exp(-s * sideways - q) else 0
		if (val <= MIN_STAMP or val <= cur * keep) and es < smearMin then
			continue
		end
		if val > cur then
			local e = val - cur
			mx, my, mz = mx + ux * e, my + uy * e, mz + uz * e
		end
		if es >= smearMin then
			mx, my, mz = mx + ddx * es, my + ddy * es, mz + ddz * es
		end
		local l2 = mx * mx + my * my + mz * mz
		if l2 > cap2 then
			local k = cap / math.sqrt(l2)
			mx, my, mz = mx * k, my * k, mz * k
		end
		mxs[i], mys[i], mzs[i] = mx, my, mz
		age[i] = 0
	end
end

-- A held brush stamping its own point (squish.js:536): _write with no move (so no smear), the static part of the
-- stamp, exp(-f(s) - q)·max(0, 1 - beta·s)·J, cached on the vertices inside the cut-off while the brush stays put.
function BodyClass._writeStill(self: Body, b: Brush)
	local rx, ry, rz, J = self.rx, self.ry, self.rz, self.J
	local list, G = b.stampList, b.stampG
	if not b.stampValid then
		local cx, cy, cz, ux, uy, uz = b.cx, b.cy, b.cz, b.ux, b.uy, b.uz
		local ir2, iT2, beta, p15 = b.ir2, b.iT2, b.beta, b.pw ~= 1
		local count = 0
		for i = 1, self.count do
			local vx, vy, vz = rx[i] - cx, ry[i] - cy, rz[i] - cz
			local hh = vx * ux + vy * uy + vz * uz
			local ha = if hh > 0 then hh else hh * ABOVE
			local q = ha * ha * iT2
			if q > STAMP_CUTOFF then
				continue
			end
			local tx, ty, tz = vx - hh * ux, vy - hh * uy, vz - hh * uz
			local s = (tx * tx + ty * ty + tz * tz) * ir2
			if s > STAMP_CUTOFF then
				continue
			end
			local rim = 1 - beta * s
			count += 1
			list[count] = i
			G[count] = math.exp(-(if p15 then s * math.sqrt(s) else s) - q) * (if rim > 0 then rim else 0) * J[i]
		end
		b.stampCount = count
		b.stampValid = true
	end
	self.stamps += 1
	local F = self.F
	local rise = F.rise
	local val0 = b.d * (1 - F.fast)
	local ux, uy, uz = b.ux, b.uy, b.uz
	local cap = self.cap
	local cap2 = cap * cap
	local keep = MEMORY.keepBelow
	local mxs, mys, mzs, age = self.mxs, self.mys, self.mzs, self.age
	for k = 1, b.stampCount do
		local i = list[k]
		local val = val0 * G[k]
		local a = age[i]
		local R2 = 0
		if a < rise then
			local r = a / rise
			R2 = 1 - r * r * (3 - 2 * r)
		end
		local mx, my, mz = mxs[i] * R2, mys[i] * R2, mzs[i] * R2
		local cur = mx * ux + my * uy + mz * uz
		if val <= MIN_STAMP or val <= cur * keep then
			continue
		end
		if val > cur then
			local e = val - cur
			mx, my, mz = mx + ux * e, my + uy * e, mz + uz * e
		end
		local l2 = mx * mx + my * my + mz * mz
		if l2 > cap2 then
			local scale = cap / math.sqrt(l2)
			mx, my, mz = mx * scale, my * scale, mz * scale
		end
		mxs[i], mys[i], mzs[i] = mx, my, mz
		age[i] = 0
	end
end

-- design: squish.js:511-517
function BodyClass._stroke(self: Body, b: Brush, o: number)
	local s = b.strokes
	local ax, ay, az = s[o + 1], s[o + 2], s[o + 3]
	local dx, dy, dz = s[o + 4] - ax, s[o + 5] - ay, s[o + 6] - az
	local uax, uay, uaz = s[o + 7], s[o + 8], s[o + 9]
	local ubx, uby, ubz = s[o + 10], s[o + 11], s[o + 12]
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	local steps = math.max(1, math.ceil(length / (self.rF * MEMORY.stampSpacing)))
	for k = 1, steps do
		local t = k / steps
		local ux, uy, uz = lerp(uax, ubx, t), lerp(uay, uby, t), lerp(uaz, ubz, t)
		local l = math.sqrt(ux * ux + uy * uy + uz * uz)
		if l == 0 then
			l = 1
		end
		self:_write(
			ax + dx * t,
			ay + dy * t,
			az + dz * t,
			ux / l,
			uy / l,
			uz / l,
			b,
			dx / steps,
			dy / steps,
			dz / steps
		)
	end
end

-- The plastic share of a pull, written into the memory (design: squish.js:376-388).
function BodyClass._plastic(self: Body, k: number)
	local rise = self.F.rise
	local gx, gy, gz = self.gx, self.gy, self.gz
	local vx, vy, vz = self.pvx * k, self.pvy * k, self.pvz * k
	local rp = self.rP * (1 + PULL.radiusGrowth * self.pullLength / self.maxPull)
	local irp2 = 1 / (rp * rp)
	local rx, ry, rz = self.rx, self.ry, self.rz
	local mxs, mys, mzs, age = self.mxs, self.mys, self.mzs, self.age
	for i = 1, self.count do
		local dx, dy, dz = rx[i] - gx, ry[i] - gy, rz[i] - gz
		local w = math.exp(-(dx * dx + dy * dy + dz * dz) * irp2)
		if w < PULL.plasticWeightMin then
			continue
		end
		local R2 = SoftBody.slowRise(age[i], rise)
		mxs[i], mys[i], mzs[i] = mxs[i] * R2 + vx * w, mys[i] * R2 + vy * w, mzs[i] * R2 + vz * w
		age[i] = 0
	end
end

-- Private: gestures

function BodyClass._pullEnd(self: Body, silent: boolean?, slipped: boolean)
	if not self.pulling then
		return
	end
	local a = math.clamp(self.pullLength / self.maxPull, 0, 1)
	if self.F.plastic > 0 and a > PULL.plasticMin then
		self:_plastic(self.F.plastic)
	end
	self.pulling = false
	self.pullLength = 0
	self.pvx, self.pvy, self.pvz = 0, 0, 0
	self:_kick(KICKS.pullEnd.soft * a + KICKS.pullEnd.softBase, axisOf(self.pux, self.puy, self.puz))
	self:_squisherKick(KICKS.pullEnd.squisher * a)
	if not silent then
		local pan = self:_pan(self.gx)
		self:_event({ kind = "snap", amount = a, slipped = slipped, pan = pan })
		self:_event({ kind = "air", amount = SOUNDS.snapAir * a, pan = pan })
	end
	self:_wake()
end

-- The pinch field at P = 1 for every vertex (design: squish.js:549-574): compress between the thumbs, ridge out
-- toward the camera, fold the top down, swell and curl the ends. Every term is linear in P (its amplitudes are),
-- so a frame adds P × this, the design's own sum. Set when the crunch starts: its centre, g0 and shift hold until the
-- next one.
function BodyClass._pinchField(self: Body)
	local sx, sy, sz = self.sizeX, self.sizeY, self.sizeZ
	local pcy, pcz = self.ctrY, self.ctrZ
	local pmx, pg0, psh = self.pinchX, self.g0, self.shift
	local piF, piHy, piHz, piW2 = 1 / (PINCH.pullIn * sx), 2 / sy, 2 / sz, 2 / sx
	local phR, pdip = PINCH.ridge * sz, PINCH.dip * sy
	local pbz, pby, peb = PINCH.curlZ * sz, PINCH.curlY * sy, PINCH.swell
	local pW2g = 1 / math.max(MIN_SIZE, sx * 0.5 - pg0)
	local rx, ry, rz = self.rx, self.ry, self.rz
	local kx, ky, kz = self.kx, self.ky, self.kz
	for i = 1, self.count do
		local px, py, pz = rx[i], ry[i], rz[i]
		local tx, ty, tz = 0, 0, 0
		local s = px - pmx
		local as = if s < 0 then -s else s
		local yN, zN = (py - pcy) * piHy, (pz - pcz) * piHz
		local fr = smooth((zN + FRONT_START) / FRONT_SPAN)
		local yc = yN - CENTRE_Y
		local dx
		if as < pg0 then
			dx = -psh * s / pg0
			local qq = 1 - (as / pg0) * (as / pg0)
			tz += phR * qq * qq * (RIDGE_BASE + (1 - RIDGE_BASE) * fr) * math.exp(-yc * yc * RIDGE_WIDTH)
			ty -= pdip * qq * smooth((yN + DIP_START) / DIP_SPAN) * (DIP_BASE + (1 - DIP_BASE) * fr)
		else
			local oo = (as - pg0) * piF
			local e = peb * smooth((as - pg0) * pW2g)
			dx = -(if s < 0 then -1 else 1) * psh * math.exp(-oo * oo)
			ty += (py - pcy) * e
			tz += (pz - pcz) * e
		end
		local wy = math.exp(-yc * yc * DX_WIDTH)
		tx += dx * (DX_BASE + (1 - DX_BASE) * fr) * (DX_FLOOR + (1 - DX_FLOOR) * wy)
		local e2 = s * piW2
		local ee = e2 * e2
		tz += pbz * ee
		ty += pby * ee
		kx[i], ky[i], kz[i] = tx, ty, tz
	end
end

-- One frame of the crunch rhythm: P and the thumbs (design: squish.js:441-458).
function BodyClass._crunchStep(self: Body, dt: number)
	if self.crunchOn then
		self.crunchT += dt
		local cycle = math.floor(self.crunchT / CRUNCH.period)
		if cycle ~= self.crunchK then
			self.crunchK = cycle
			local rng = self.rng
			self.ju = if cycle > 0 then rng:NextNumber(-CRUNCH.jitterU, CRUNCH.jitterU) else 0
			self.jv = if cycle > 0 then rng:NextNumber(-CRUNCH.jitterV, CRUNCH.jitterV) else 0
		end
		local target = SoftBody.crunchTarget(self.crunchT)
		self.crunchP += (target - self.crunchP) * math.min(1, dt * CRUNCH.follow)
		local P = self.crunchP
		local u = CRUNCH.gap - CRUNCH.slide * P
		local w = CRUNCH.height + self.jv
		for side = 1, 2 do
			local index = if side == 1 then self.thumbA else self.thumbB
			if index == 0 then
				continue
			end
			local b = self.brushes[index]
			local sign = if side == 1 then -1 else 1 -- A at -u, B at +u (design: squish.js:450)
			local hx, hy, hz, nx, ny, nz = self:_frontPoint(sign * u + self.ju, w)
			local dx, dy, dz = b.cx - hx, b.cy - hy, b.cz - hz
			if dx * dx + dy * dy + dz * dz > MIN_THUMB_MOVE_SQ then
				pushStroke(b, hx, hy, hz, -nx, -ny, -nz)
			end
			if b.cx ~= hx or b.cy ~= hy or b.cz ~= hz or b.ux ~= -nx or b.uy ~= -ny or b.uz ~= -nz then
				b.liveValid, b.stampValid = false, false
			end
			b.cx, b.cy, b.cz = hx, hy, hz
			b.ux, b.uy, b.uz = -nx, -ny, -nz
			b.amt = CRUNCH.startAmount + (1 - CRUNCH.startAmount) * P
		end
		self:_wake()
	elseif self.crunchP > 0 then
		local P = self.crunchP
		P -= P * math.min(1, dt * CRUNCH.releaseRate / math.max(CRUNCH.releaseMinRise, self.F.rise))
		self.crunchP = if P < CRUNCH.snap then 0 else P
	end
end

-- Snaps every vertex to rest and stops (design: squish.js:644-652). WaxCoat sees restCount change.
function BodyClass._rest(self: Body)
	local n = self.count
	local xs, ys, zs, vxs, vys, vzs = self.xs, self.ys, self.zs, self.vxs, self.vys, self.vzs
	local mxs, mys, mzs, age = self.mxs, self.mys, self.mzs, self.age
	local px, py, pz, press, written = self.px, self.py, self.pz, self.press, self.written
	local restX, restY, restZ, sleeping = self.restX, self.restY, self.restZ, self.sleeping
	for i = 1, n do
		xs[i], ys[i], zs[i], vxs[i], vys[i], vzs[i] = 0, 0, 0, 0, 0, 0
		mxs[i], mys[i], mzs[i] = 0, 0, 0
		age[i] = NO_MEMORY
		press[i] = 0
		sleeping[i] = true
		px[i], py[i], pz[i] = restX[i], restY[i], restZ[i]
		written[i] = i
	end
	self.writtenCount = n
	self.inflation = 0
	self.shownInflation = 0
	self.active = false
	self.idleT = 0
	self.faceSquish = false
	self.restCount += 1
end

-- Public: gestures (model space in, design frame inside)

function BodyClass.fingerDown(self: Body, point: Vector3, normal: Vector3)
	if self.finger ~= 0 or self.pulling then
		self:fingerUp(true)
	end
	local F = self.F
	local index = self:_set(
		"finger",
		-point.X,
		point.Y,
		-point.Z,
		normal.X,
		-normal.Y,
		normal.Z,
		self.rF,
		self.rF * FINGER.falloff,
		self.dF,
		1,
		F.beta
	)
	self.finger = index
	local b = self.brushes[index]
	self:_kick(KICKS.fingerDown.soft, axisOf(b.ux, b.uy, b.uz))
	self:_squisherKick(KICKS.fingerDown.squisher)
	self:_event({ kind = "press", brush = "finger", pan = self:_pan(b.cx) })
end

function BodyClass.fingerMove(self: Body, point: Vector3, normal: Vector3)
	if self.pulling then
		return
	end
	if self.finger == 0 then
		self:fingerDown(point, normal)
		return
	end
	local b = self.brushes[self.finger]
	local hx, hy, hz = -point.X, point.Y, -point.Z
	local ux, uy, uz = normal.X, -normal.Y, normal.Z -- -(design normal)
	local length = math.sqrt(ux * ux + uy * uy + uz * uz)
	if length == 0 then
		length = 1
	end
	ux, uy, uz = ux / length, uy / length, uz / length
	local dx, dy, dz = hx - b.cx, hy - b.cy, hz - b.cz
	local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
	if distance < MIN_MOVE then
		return
	end
	if distance < self.rF * MEMORY.maxStrokeOfRadius then
		pushStroke(b, hx, hy, hz, ux, uy, uz)
	end
	b.cx, b.cy, b.cz = hx, hy, hz
	b.ux, b.uy, b.uz = ux, uy, uz
	b.liveValid, b.stampValid = false, false
	self:_wake()
end

-- design: squish.js:344-359
function BodyClass.pullTo(self: Body, origin: Vector3, direction: Vector3)
	if not self.pulling then
		if self.finger == 0 then
			return
		end
		local b = self.brushes[self.finger]
		self.pulling = true
		self.gx, self.gy, self.gz = b.cx, b.cy, b.cz
		self.pux, self.puy, self.puz = b.ux, b.uy, b.uz
		self.pvx, self.pvy, self.pvz = 0, 0, 0
		self.pullLength = 0
		b.on = false
		b.strokeCount = 0
		self.finger = 0
		self:_squisherKick(KICKS.pullStart.squisher)
	end
	local ox, oy, oz = -origin.X, origin.Y, -origin.Z
	local dx, dy, dz = -direction.X, direction.Y, -direction.Z
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	if length == 0 then
		return
	end
	dx, dy, dz = dx / length, dy / length, dz / length
	local t = (self.gx - ox) * dx + (self.gy - oy) * dy + (self.gz - oz) * dz
	local vx, vy, vz = ox + dx * t - self.gx, oy + dy * t - self.gy, oz + dz * t - self.gz
	local L = math.sqrt(vx * vx + vy * vy + vz * vz)
	local maxPull = self.maxPull
	if L > maxPull * PULL.slip then
		self:_pullEnd(false, true)
		return
	end
	local Ls = maxPull * math.tanh(L / maxPull)
	if L > MIN_PULL then
		local k = Ls / L
		vx, vy, vz = vx * k, vy * k, vz * k
	end
	self.pvx, self.pvy, self.pvz = vx, vy, vz
	self.pullLength = Ls
	self:_wake()
end

-- design: squish.js:360-366
function BodyClass.fingerUp(self: Body, silent: boolean?)
	if self.pulling then
		self:_pullEnd(silent, false)
		return
	end
	if self.finger == 0 then
		return
	end
	local b = self.brushes[self.finger]
	b.on = false
	b.strokeCount = 0
	self.finger = 0
	local a = math.clamp(b.d / b.dMax, SOUNDS.fingerUpMin, 1)
	local pan = self:_pan(b.cx)
	self:_kick(KICKS.fingerUp.soft, axisOf(b.ux, b.uy, b.uz))
	self:_squisherKick(KICKS.fingerUp.squisher)
	if not silent then
		self:_event({ kind = "release", brush = "finger", amount = a, pan = pan })
		self:_event({ kind = "air", amount = a * SOUNDS.fingerAir, pan = pan })
	end
end

-- design: squish.js:389-404
function BodyClass.palms(self: Body, on: boolean)
	if on then
		if self.palmL ~= 0 then
			return
		end
		local sx = self.sizeX
		local r = PALM.radius * math.min(self.sizeY, self.sizeZ)
		local T = PALM.falloff * sx
		local dMax = math.min(PALM.depthOfX * sx, (1 - self.squeezeDepth) * PALM.depthOfSqueeze * sx)
		local beta = self.F.beta * PALM.betaShare
		self.palmL = self:_set("palm", self.minX, self.ctrY, self.ctrZ, 1, 0, 0, r, T, dMax, PALM.power, beta)
		self.palmR = self:_set("palm", self.maxX, self.ctrY, self.ctrZ, -1, 0, 0, r, T, dMax, PALM.power, beta)
		self.holding = true
		self:_kick(KICKS.palmsOn.soft, "X")
		self:_squisherKick(KICKS.palmsOn.squisher)
		self:_event({ kind = "press", brush = "palm", pan = 0 })
	else
		if self.palmL == 0 then
			return
		end
		local a = math.clamp(self.palmC, SOUNDS.palmsOffMin, 1)
		self.brushes[self.palmL].on = false
		self.brushes[self.palmR].on = false
		self.palmL, self.palmR = 0, 0
		self.holding = false
		self:_kick(KICKS.palmsOff.soft, "X")
		self:_squisherKick(KICKS.palmsOff.squisher)
		self:_event({ kind = "release", brush = "palm", amount = a, pan = 0 })
		self:_event({ kind = "air", amount = a, pan = 0 })
	end
end

-- design: squish.js:419-440
function BodyClass.thumbs(self: Body, on: boolean)
	if on then
		if self.crunchOn then
			return
		end
		if self.finger ~= 0 or self.pulling then
			self:fingerUp(true)
		end
		local rT = THUMB.radius * self.maxDim
		local depth = math.min(THUMB.depthOfRadius * rT, THUMB.depthOfMinDim * self.minDim)
		local beta = self.F.beta * THUMB.betaShare
		self.crunchOn = true
		self.crunchT = 0
		self.crunchK = -1
		self.ju, self.jv = 0, 0
		self.pinchX = self.ctrX
		self.g0 = CRUNCH.gap * CRUNCH.spanX * self.sizeX
		self.shift = CRUNCH.slide * CRUNCH.spanX * self.sizeX
		self:_pinchField()
		local ax, ay, az, anx, any, anz = self:_frontPoint(-CRUNCH.gap, CRUNCH.height)
		local bx, by, bz, bnx, bny, bnz = self:_frontPoint(CRUNCH.gap, CRUNCH.height)
		self.thumbA = self:_set("thumb", ax, ay, az, -anx, -any, -anz, rT, rT * THUMB.falloff, depth, 1, beta)
		self.thumbB = self:_set("thumb", bx, by, bz, -bnx, -bny, -bnz, rT, rT * THUMB.falloff, depth, 1, beta)
		self.brushes[self.thumbA].amt = CRUNCH.startAmount
		self.brushes[self.thumbB].amt = CRUNCH.startAmount
		self:_kick(KICKS.thumbsOn.soft, "Z")
		self:_squisherKick(KICKS.thumbsOn.squisher)
		self:_event({ kind = "press", brush = "thumb", pan = 0 })
	else
		if not self.crunchOn then
			return
		end
		self.crunchOn = false
		for _, index in { self.thumbA, self.thumbB } do
			if index ~= 0 then
				self.brushes[index].on = false
			end
		end
		self.thumbA, self.thumbB = 0, 0
		self:_kick(KICKS.thumbsOff.soft, "Z")
		self:_squisherKick(KICKS.thumbsOff.squisher)
		self:_event({ kind = "release", brush = "thumb", amount = SOUNDS.thumbsOff, pan = 0 })
		self:_event({ kind = "air", amount = SOUNDS.thumbsOff, pan = 0 })
		self:_wake()
	end
end

-- Public: one frame (design: squish.js:520-643)

function BodyClass.step(self: Body, dt: number): boolean
	self.writtenCount = 0
	if not self.active or dt <= 0 then
		return false
	end
	if dt > MAX_DT then
		dt = MAX_DT
	end
	local F = self.F
	local rise = F.rise
	self:_crunchStep(dt)
	local pOn = self.pulling
	local crunchOn = self.crunchOn
	local pressed = pOn or crunchOn

	-- Brushes: depth on its spring, retire, stamp, pack the live ones (squish.js:526-540).
	local brushes, lb, lbBrush = self.brushes, self.lb, self.lbBrush
	local nl, palmMax, palmD = 0, 0, 0
	local nb = math.max(1, math.ceil(dt * DEPTH.substepsPerSecond))
	local hb = dt / nb
	local kD, cD = DEPTH.spring[1], DEPTH.spring[2]
	for q = 1, BRUSH_SLOTS do
		local b = brushes[q]
		if not b.live then
			continue
		end
		b.t += dt
		local target = 0
		if b.on then
			pressed = true
			local finger = b.kind ~= "palm"
			local delay = if finger then DEPTH.delayFinger else DEPTH.delayPalm
			if b.t > delay then
				local ramp = if finger then DEPTH.riseFinger else DEPTH.risePalm
				target = b.dMax
					* b.amt
					* smooth((b.t - delay) / ramp)
					* (DEPTH.settle + (1 - DEPTH.settle) * smooth((b.t - delay) / DEPTH.creepSeconds))
			end
		end
		local d, v = b.d, b.v
		for _ = 1, nb do
			v += (kD * (target - d) - cD * v) * hb
			d += v * hb
		end
		b.d, b.v = d, v
		if not b.on and d < b.dMax * DEPTH.retireDepth and math.abs(v) < b.dMax * DEPTH.retireSpeed then
			b.live = false
			b.d, b.v = 0, 0
			b.strokeCount = 0
			continue
		end
		if b.kind == "palm" then
			palmMax = math.max(palmMax, d / b.dMax)
			palmD = math.max(palmD, d)
		end
		if b.on and d > PRESSED_DEPTH then
			if b.strokeCount > 0 then
				for s = 0, b.strokeCount - 1 do
					self:_stroke(b, s * STROKE)
				end
				b.strokeCount = 0
			else
				self:_writeStill(b)
			end
		else
			b.strokeCount = 0
		end
		local o = nl * LB
		lb[o + 1], lb[o + 2], lb[o + 3] = b.cx, b.cy, b.cz
		lb[o + 4], lb[o + 5], lb[o + 6] = b.ux, b.uy, b.uz
		lb[o + 7], lb[o + 8], lb[o + 9], lb[o + 10], lb[o + 11] = b.ir2, b.iT2, d, b.beta, b.pw
		nl += 1
		lbBrush[nl] = b
	end

	-- The stretch field (squish.js:541-547).
	local gx, gy, gz, pvx, pvy, pvz = 0, 0, 0, 0, 0, 0
	local ihx, ihy, ihz, irp2, nkK = 0, 0, 0, 0, 0
	local tug = PULL.tug
	if pOn then
		gx, gy, gz = self.gx, self.gy, self.gz
		pvx, pvy, pvz = self.pvx, self.pvy, self.pvz
		local L = self.pullLength
		local Lp = math.max(L, MIN_PULL)
		local rp = self.rP * (1 + PULL.radiusGrowth * L / self.maxPull)
		ihx, ihy, ihz = pvx / Lp, pvy / Lp, pvz / Lp
		irp2 = 1 / (rp * rp)
		nkK = F.neck * PULL.neckGain * math.min(1, L / rp)
	end

	-- The pinch field: P × the field at P = 1, set when the crunch started (squish.js:549-574).
	local P = self.crunchP
	local pin = P > PINCH.active
	local kx, ky, kz = self.kx, self.ky, self.kz

	-- Every vertex: target = memory + pinch + brushes + stretch, its spring, the bulge (squish.js:555-601).
	local k, c = F.k, F.c
	local ns = math.max(1, math.ceil(dt * SPRING_SUBSTEPS))
	local h = dt / ns
	local infl = self.inflation
	self.shownInflation = infl
	local iF = 1 / (BULGE.dentShare * self.dF)
	local iD = 1 / self.dF
	local eps = self.eps
	local eV = eps * KNEAD.movingEpsilon
	local writeEps = self.writeEps
	local allAwake = pin or pOn
	local rx, ry, rz, rnx, rny, rnz = self.rx, self.ry, self.rz, self.rnx, self.rny, self.rnz
	local restX, restY, restZ, J, aw = self.restX, self.restY, self.restZ, self.J, self.aw
	local xs, ys, zs, vxs, vys, vzs = self.xs, self.ys, self.zs, self.vxs, self.vys, self.vzs
	local mxs, mys, mzs, age, sleeping = self.mxs, self.mys, self.mzs, self.age, self.sleeping
	local outX, outY, outZ, press, written = self.px, self.py, self.pz, self.press, self.written
	local shell = self.shell
	local loX, loY, loZ = shell.boundsMin.X, shell.boundsMin.Y, shell.boundsMin.Z
	local hiX, hiY, hiZ = shell.boundsMax.X, shell.boundsMax.Y, shell.boundsMax.Z
	local vol, moving, mem, wc = 0, false, false, 0
	for i = 1, self.count do
		local px, py, pz = rx[i], ry[i], rz[i]
		local tx, ty, tz = 0, 0, 0
		local acted = allAwake
		local a = age[i]
		if a < rise then
			a += dt
			age[i] = a
			if a < rise then
				local r = a / rise
				local R2 = 1 - r * r * (3 - 2 * r)
				tx, ty, tz = mxs[i] * R2, mys[i] * R2, mzs[i] * R2
				mem = true
				acted = true
			else
				mxs[i], mys[i], mzs[i] = 0, 0, 0
			end
		end
		if pin then
			tx, ty, tz = tx + P * kx[i], ty + P * ky[i], tz + P * kz[i]
		end
		for q = 0, nl - 1 do
			local o = q * LB
			local b = lbBrush[q + 1]
			local G = b.liveG
			local g
			if b.liveValid then
				g = G[i]
				if g == OUTSIDE then
					continue
				end
			else
				local vx, vy, vz = px - lb[o + 1], py - lb[o + 2], pz - lb[o + 3]
				local hh = vx * lb[o + 4] + vy * lb[o + 5] + vz * lb[o + 6]
				local ha = if hh > 0 then hh else hh * ABOVE
				local q2 = ha * ha * lb[o + 8]
				local ex, ey, ez = vx - hh * lb[o + 4], vy - hh * lb[o + 5], vz - hh * lb[o + 6]
				local s = (ex * ex + ey * ey + ez * ez) * lb[o + 7]
				if q2 > LIVE_CUTOFF or s > LIVE_CUTOFF then
					G[i] = OUTSIDE
					continue
				end
				g = math.exp(-(if lb[o + 11] == 1 then s else s * math.sqrt(s)) - q2) * (1 - lb[o + 10] * s) * J[i]
				G[i] = g
			end
			acted = true
			local ux, uy, uz = lb[o + 4], lb[o + 5], lb[o + 6]
			local val = lb[o + 9] * g
			if val > 0 then
				local pr = tx * ux + ty * uy + tz * uz
				if val > pr then
					local e = val - pr
					tx, ty, tz = tx + ux * e, ty + uy * e, tz + uz * e
				end
			else
				tx, ty, tz = tx + ux * val, ty + uy * val, tz + uz * val
			end
		end
		if pOn then
			local dx, dy, dz = px - gx, py - gy, pz - gz
			local w = math.exp(-(dx * dx + dy * dy + dz * dz) * irp2)
			local al = dx * ihx + dy * ihy + dz * ihz
			local nk = nkK * w * (1 - w)
			local ww = w + tug * (1 - w)
			tx += pvx * ww - (dx - ihx * al) * nk
			ty += pvy * ww - (dy - ihy * al) * nk
			tz += pvz * ww - (dz - ihz * al) * nk
		end
		local nx, ny, nz = rnx[i], rny[i], rnz[i]
		local dx, dy, dz
		if not acted and sleeping[i] then
			-- Asleep at rest: only the bulge moves it.
			dx, dy, dz = nx * infl, ny * infl, nz * infl
		else
			local x, y, z = xs[i], ys[i], zs[i]
			local vx, vy, vz = vxs[i], vys[i], vzs[i]
			for _ = 1, ns do
				vx += (k * (tx - x) - c * vx) * h
				vy += (k * (ty - y) - c * vy) * h
				vz += (k * (tz - z) - c * vz) * h
				x += vx * h
				y += vy * h
				z += vz * h
			end
			local still = math.abs(tx - x) + math.abs(ty - y) + math.abs(tz - z) <= eps
				and math.abs(vx) + math.abs(vy) + math.abs(vz) <= eV
			if not still then
				moving = true
			end
			if still and not acted then
				-- Nothing acts on it and it is within eps of rest: snap it there and let it sleep.
				x, y, z, vx, vy, vz = 0, 0, 0, 0, 0, 0
				sleeping[i] = true
			else
				sleeping[i] = false
			end
			xs[i], ys[i], zs[i] = x, y, z
			vxs[i], vys[i], vzs[i] = vx, vy, vz
			local w = aw[i]
			if w > 0 then
				local dn = -(x * nx + y * ny + z * nz)
				if dn > 0 then
					vol += dn * w
				end
			end
			local mag = math.sqrt(x * x + y * y + z * z)
			local fr = infl * (1 - math.min(1, mag * iF))
			dx, dy, dz = x + nx * fr, y + ny * fr, z + nz * fr
			press[i] = math.min(1, mag * iD)
		end
		-- Shown in model space (x and z back), inside the anchored bounds.
		local ox, oy, oz = restX[i] - dx, restY[i] + dy, restZ[i] - dz
		ox = if ox < loX then loX elseif ox > hiX then hiX else ox
		oy = if oy < loY then loY elseif oy > hiY then hiY else oy
		oz = if oz < loZ then loZ elseif oz > hiZ then hiZ else oz
		if math.abs(ox - outX[i]) + math.abs(oy - outY[i]) + math.abs(oz - outZ[i]) > writeEps then
			outX[i], outY[i], outZ[i] = ox, oy, oz
			wc += 1
			written[wc] = i
		end
	end
	self.writtenCount = wc
	for q = 1, nl do
		lbBrush[q].liveValid = true -- every vertex has its cached dent now
	end

	-- The bulge, the press amounts and the squish face (squish.js:611-623).
	self.inflation = infl + (F.gamma * vol / self.area - infl) * math.min(1, dt * BULGE.rate)
	self.palmC, self.palmD = palmMax, palmD
	self.since = if pressed then 0 else self.since + dt
	local faceSquish = palmMax > (if self.faceSquish then FACE.palmOff else FACE.palmOn)
	local f = if self.finger ~= 0 then brushes[self.finger] else nil
	if f and f.d > f.dMax * FACE.fingerDepth then
		local dx, dy, dz = f.cx - self.faceX, f.cy - self.faceY, f.cz - self.faceZ
		if self.feel == "jelly" or math.sqrt(dx * dx + dy * dy + dz * dz) < self.faceR * FACE.reach then
			faceSquish = true
		end
	end
	if pOn and self.pullLength > self.maxPull * FACE.pull then
		faceSquish = true
	end
	if P > FACE.crunch then
		faceSquish = true
	end
	self.faceSquish = faceSquish
	self.pressSignal = if pressed then math.max(palmMax, P, if f then f.d / f.dMax else 0) else 0

	-- Sleep 0.12 s after everything settled (squish.js:640-642).
	if
		nl == 0
		and not pOn
		and not crunchOn
		and P <= 0
		and not mem
		and not moving
		and math.abs(self.inflation) < eps
	then
		self.idleT += dt
		if self.idleT > KNEAD.sleepSeconds then
			self:_rest()
		end
	else
		self.idleT = 0
	end
	return self.writtenCount > 0
end

-- Public: readings

-- A raycast hit on the shell (its triangle's vertices a, b, c and barycentric weights) in rest space: the point and
-- the normalized rest normal, model space (design: squish.js:461-470). nil when the normals cancel.
function BodyClass.restHit(
	self: Body,
	a: number,
	b: number,
	c: number,
	wa: number,
	wb: number,
	wc: number
): (Vector3?, Vector3?)
	local shell = self.shell
	local px, py, pz, nx, ny, nz = shell.px, shell.py, shell.pz, shell.nx, shell.ny, shell.nz
	local x = px[a] * wa + px[b] * wb + px[c] * wc
	local y = py[a] * wa + py[b] * wb + py[c] * wc
	local z = pz[a] * wa + pz[b] * wb + pz[c] * wc
	local mx = nx[a] * wa + nx[b] * wb + nx[c] * wc
	local my = ny[a] * wa + ny[b] * wb + ny[c] * wc
	local mz = nz[a] * wa + nz[b] * wb + nz[c] * wc
	local l2 = mx * mx + my * my + mz * mz
	if l2 < MIN_NORMAL_SQ then
		return nil, nil
	end
	local l = math.sqrt(l2)
	return Vector3.new(x, y, z), Vector3.new(mx / l, my / l, mz / l)
end

-- Thumb k's tip: its centre + u·d, the bottom of its dent (design: squish.js:459).
function BodyClass.thumbTip(self: Body, k: number): Vector3?
	local index = if k == 1 then self.thumbA elseif k == 2 then self.thumbB else 0
	if index == 0 then
		return nil
	end
	local b = self.brushes[index]
	return Vector3.new(-(b.cx + b.ux * b.d), b.cy + b.uy * b.d, -(b.cz + b.uz * b.d))
end

function BodyClass.brush(self: Body, k: number): BrushInfo?
	local b = self.brushes[k]
	if b == nil then
		return nil
	end
	return {
		kind = b.kind,
		live = b.live,
		on = b.on,
		centre = Vector3.new(-b.cx, b.cy, -b.cz),
		direction = Vector3.new(-b.ux, b.uy, -b.uz),
		radius = b.r,
		falloff = b.T,
		depth = b.d,
		depthMax = b.dMax,
		power = b.pw,
		beta = b.beta,
		amount = b.amt,
	}
end

function BodyClass.displacement(self: Body, i: number): Vector3
	return Vector3.new(-self.xs[i], self.ys[i], -self.zs[i])
end

function BodyClass.memory(self: Body, i: number): Vector3
	return Vector3.new(-self.mxs[i], self.mys[i], -self.mzs[i])
end

function BodyClass.pullVector(self: Body): Vector3
	return Vector3.new(-self.pvx, self.pvy, -self.pvz)
end

function BodyClass.takeEvents(self: Body): { Event }
	local events = self.events
	self.events = {}
	return events
end

return SoftBody
