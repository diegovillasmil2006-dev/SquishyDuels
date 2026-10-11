--!strict
-- JellySkin (client only; pure: no instances, connections, yields or clock reads). DESIGN §18.3.4-§18.3.8: the jelly
-- ripple's skin layout and its math. JellyRippleController feeds the arrays to an EditableMesh, drives a Sim per skin
-- and does every instance write; everything here is testable in Edit mode.
--
-- Spaces. Arena layouts are in arena space: WorldLayout.Arena coordinates (origin on the floor top at the court centre,
-- +Z from PadA to PadB); arenaFrame(padA, padB, floorY) maps them to the world from the DuelState numbers. The backstop
-- layout is in backstop space (origin at its box centre, axis-aligned); backstopFrame() maps it to the world. Mesh
-- space = layout space - layout.center (the centre of the anchored bounds).
--
-- Pieces. arenaPieces(): the 12 WorldLayout cover pieces (walls, blocks, gumdrops), each with its Body box (centre,
-- size), the bounds of all its parts (the block's Cap, the gumdrop's dome) and its bottom centre (path B pivot).
--
-- Layout (arenaLayout(quality, options?), backstopLayout(quality)). Every skinned face has its own vertices on a
-- cols x rows grid with its outer ring pinned, so edges meet their neighbours and never tear:
--   * wall big faces (+Z / -Z, 6 x 8): wallCols columns; rows every wallRowStuds at y = wallRowStuds / 2 + k ·
--     wallRowStuds (0.25 + 0.5k) plus fixed rim rows at y = 0 and y = 8, so every stripe edge (heights ± thickness / 2,
--     WorldLayout.Arena.wallStripes) is a grid row. Triangles inside a stripe band are Cream, the rest the wall colour.
--   * wall sides (+X / -X, 2.5 x 8): wallSideCols columns, the same rows, one colour.
--   * wall top (+Y, 6 x 2.5): wallTopCols x wallTopRows (High), or 4 fixed corners (Low: hits there get a ring).
--   * block sides (4 faces, 6 x 8): blockCols x blockRows, one colour; the top (under the Cap) and bottoms are left out.
--   * backstop: the front +X face is backstop.colsHigh x rowsHigh (cols across its Z, rows up its Y; Low: colsLow x
--     rowsLow); the other 5 faces are fixed corners. One colour (the backstop's WorldLayout colour), no vertex colours.
--   * bounds anchors: 8 tiny triangles at the rest bounds widened by boundsMargin, and further where a skinned piece
--     can reach while it dents (clampOut along its face normals) and jiggles (jiggleReach), so a bulge, a jiggle or a
--     collapse never changes the mesh bounds (U, S3). Reading: the backstop skin gets them too (it collapses at rest
--     as well).
--   Face axes: u along the columns, v along the rows, u x v = the outward normal; every triangle is wound so that
--   (b - a) x (c - a) points along its vertices' normal (the giant pads' PadMesh convention, which renders outward).
--   counts(quality, options?) gives the arena totals from the formulas: High 5,368 / 9,000, Low 2,488 / 3,728.
--   options.walls = false leaves the walls out (Config.Anim.jellyRipple.vertexColors off: walls use path B and only
--   the one-colour blocks are skinned).
--
-- Hits (the server's contact point and normal, converted to layout space by the caller):
--   * classify(pieces, p, n): what a "geometry" hit in arena space touched (§18.3.4 event flow, step 2): "floor"
--     (n.Y > floorNormalMinY within FLOOR_TOLERANCE of the floor top), "round" (a gumdrop: path B), "face" (a Body box
--     face of a wall or block, with its name and (u, v)), "edge" (on a wall or block but on no face: an edge, a Cap)
--     or "other" (a rail, a gutter, anything else). Whether a "face" is skinned is the layout's (faceOf, Face.moves).
--   * findPiece(pieces, p): the piece whose parts' bounds, widened by PIECE_TOLERANCE, hold p (the nearest one).
--   * hitFace(piece, p, n): the Body box face whose outward normal is closest to n, if n·normal >= edgeNormalMinDot and
--     p lies on it (within FACE_TOLERANCE of its plane: the stripes stand 0.05 proud; within EDGE_TOLERANCE of its
--     edges), with p's (u, v) on that face. No face for an edge hit, a Cap or a point off the Body.
--   * findFace(layout, p, n): findPiece + hitFace, then that face of the layout (nil when it is not skinned).
--   * rayPiece(pieces, origin, dir, studs) / rayFace(layout, ...): the first Body box face the ray enters within
--     `studs` (Dragon Rush lanes: from the lane end E, the swept sphere's centre, for radius + rushProbeMarginStuds).
--
-- Waves: each skinned face is an Anim/PadDent grid (faceGrid) with dentParams(): no contacts, impulses only; the
-- spring is springOmega / springZeta, the coupling waveSpeed = 2 x waveStudsPerSecond (PadDent's coupling is a quarter
-- of the Laplacian, so a wave moves at c / 2), heights clamped to [-clampIn, clampOut] along the outward normal.
-- impulseFor(r, isRush, reduced) gives the hit's (speed, radius); faceNormal(face, h, k) a moved vertex's normal from
-- its 4 neighbours along the face axes. ReducedMotion: PadDent's c = 0 and zeta = 1, impulse x reducedImpulseScale.
--
-- Sim (newSim): the per-skin bookkeeping JellyRippleController drives each frame. impulse() wakes a face (and asks for
-- the piece's swap-in the first time in "onHit" mode); step() steps the awake faces with the write budget
-- (writesPerFrame vertex writes; a face that wrote more than what is left steps every other frame with both frames'
-- dt, the giant pads' rule; dentParams' maxDt is 2 × the Scheduler's, so no time is lost), snaps a face to rest
-- faceSeconds (Rush rushFaceSeconds) after its last impulse or once its dent sleeps, and asks for a piece's swap-out
-- exactly when the last of its faces sleeps and its jiggle rests. At most maxActiveFaces ripple at once; another one
-- snaps the face with the oldest impulse to rest. The instance work goes through the SimIO callbacks; swap-in and
-- swap-out writes are not part of the budget.
--
-- Whole-piece jiggle (path A, on top of the dent; user test 2026-10-07 "too weak, need more animation like 10x";
-- Config.Anim.jellyRipple.jiggle): impulse(..., jiggle) also kicks the hit piece's Wobble (below) with
-- jiggleAmount(kind, r, isRush, reduced): amount × the throw's radius scale (impulseFor's), rushAmount for a Dragon
-- Rush, backstopAmount on the practice backstop, 0 under ReducedMotion (no jiggle at all). Every vertex of a jiggling
-- piece is drawn at q ∘ K + T, q its dented position (rest + normal · h) and (K, T) = Wobble:map(base, size): every
-- axis scales by S about its pivot P, q' = P + (q - P) · S. Y scales about the Body's bottom (the bottom row never
-- moves vertically, so the piece never lifts off or sinks); a horizontal axis about its centre, except the lead face's
-- axis, which scales about the lead face's plane.
-- The lead face keeps every vertex <= 3 Hz (§9.12). A dented face whose plane the jiggle moves (by its distance from
-- the pivot × (S - 1)) shows the sum of that 2.2 Hz shift and its dent, and where the two nearly cancel their two
-- frequencies beat into 3.5-9 Hz wiggles (scratch simulations and review, 2026-10-07: a second hit on the opposite or
-- an adjacent face while the piece still jiggled). So a piece has at most one dented face while it moves, and that
-- face's plane never moves: the lead face is the face of a jiggling hit on the piece at rest (no awake face, no
-- jiggle); while the piece moves, a hit on the lead face dents it and kicks the jiggle, and a hit on any other face only
-- kicks the jiggle (along that face's axis; the lead's axis keeps its pivot). The lead face moves only with its dent
-- (h · S has the dent's zero crossings); every other face moves with the jiggle alone (<= 2.5 Hz). Pivots are taken
-- only from rest (Wobble:pivot), so the map never jumps. The wall top (+Y) can never hold still (Y scales about the
-- bottom; its dent beat at 3.4 Hz with a later kick in the scratch runs), so a jiggling hit there on a piece at rest
-- gives it NO_LEAD: it only kicks the jiggle, and so does every hit until the piece rests. A jiggle-free hit
-- (ReducedMotion) dents as before and gives the piece no lead; no jiggle is kicked while a face other than the lead
-- ripples.
-- step() steps the jiggles and ends one that settled, passed faceSeconds (Rush rushFaceSeconds) after its last kick,
-- or is running under ReducedMotion. A piece that stays shown after its jiggle ends waits ("resting") for one
-- whole-piece write at rest; one that does not swaps out. Whole pieces go through io.writePiece within the jiggle
-- budget per step (jiggle.writesPerFrame, writesPerFrameLow on a Low layout): jiggling and resting pieces, the
-- longest-unwritten first, one piece even over the budget when nothing was written yet. The map is taken when a piece
-- is written whole and kept as the map it is drawn with (jiggleMap): a piece left out keeps its last shape, and the
-- dent writes of its faces (and retire, and offset) use that same map, so a piece is never drawn with two maps. A face
-- of a piece written whole this step only refreshes its normals (the positions come with the whole write). At most
-- jiggle.maxPieces jiggle at once; another one stops the one with the oldest kick. offset() includes the jiggle along
-- the face normal (splats ride it; the in-plane slide of a bulge is not followed). The rest normals are kept under the
-- jiggle (an axis-aligned scale keeps a flat face's normal).
--
-- Path B (whole-piece squash wobble, §18.3.5): squashAxis(n) is the arena axis closest to the normal;
-- squashScale(x, axis, share?, keepHeight?) is c = 1 + x on it and the bulge on the others: for a horizontal axis
-- c^-share up and c^-(1 - share) across, for Y c^-0.5 on both (share 0.5 when omitted, the old w = 1 / sqrt(c));
-- keepHeight holds Y at 1 (a block skin under its real Cap). pathBAmount(kind, isRush, reduced, radius?) is amount
-- (walls, blocks) or roundAmount (gumdrops) × the throw's radius scale, × rushScale for Dragon Rush, ×
-- pathB.reducedScale under ReducedMotion, at most maxAmount; the spring (pathBSpring) is omega / zeta (zeta = 1 under
-- ReducedMotion: a small rise and fall) kicked with kickSpeed(amount, omega, zeta), so the squash peaks at `amount` on
-- its first swing (about 100 ms after the hit).
-- newWobble(spec?): one piece's wobble (path B by default, or jiggleSpec(kind) for path A), a spring on x per arena
-- axis (Util/Spring.integrate), so hits along different axes add up without a jump; |x| <= maxAmount for all axes
-- together (a clamped wobble loses its outward speed); scale() is the product of the three squashes (wobbleScale);
-- pivot(axis, side) sets where an axis scales about (from rest only); calm() is ReducedMotion turning on mid-wobble
-- (zeta = 1, speed dropped: it returns to rest without crossing it). Reading: one spring per axis (DESIGN names one x per hit axis; a second hit along another axis keeps the first one's
-- motion instead of switching axes mid-wobble).
--
-- Also: boxMismatch (the 0.02-stud mismatch guard; corners matched order-free, so a turned box of the same shape
-- matches), sampleFace (a face's height at (u, v), for splats riding the wave), surfaceOffset (path B's surface shift
-- at a point) and wobblePitch (the sfx.jellyWobble pitch, §18.6).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Spring = require(Shared.Util.Spring)
local Arenas = require(Shared.World.Arenas)
local WorldLayout = require(Shared.World.WorldLayout)

local PadDent = require(script.Parent.PadDent)

-- Types

export type Quality = "High" | "Low"
export type Axis = "X" | "Y" | "Z"
export type FaceName = string -- "+X" | "-X" | "+Y" | "-Y" | "+Z" | "-Z" (the outward axis)
export type HitClass = "floor" | "round" | "face" | "edge" | "other"

export type Piece = {
	index: number,
	name: string, -- WorldLayout piece name ("B_Wall1"), or "Backstop"
	kind: string, -- "wall" | "block" | "gumdrop" | "backstop"
	center: Vector3, -- the Body box centre
	size: Vector3, -- the Body box size (upright)
	boundsMin: Vector3, -- every part of the piece (the block's Cap, the gumdrop's dome)
	boundsMax: Vector3,
	base: Vector3, -- the Body's bottom centre (path B pivot)
	color: string, -- the Body's Palette token
	skinned: boolean, -- has faces in this layout
	faces: { number }, -- layout face indices
	first: number, -- the piece's first layout vertex (0 when not skinned)
	count: number, -- its vertex count
	collapse: Vector3, -- where its vertices go when collapsed (the Body centre)
}

export type Face = {
	index: number,
	piece: number,
	name: FaceName,
	kind: string, -- "wallBig" | "wallSide" | "wallTop" | "blockSide" | "backstopFront" | "fixed"
	moves: boolean, -- false: corners only (never rippled)
	center: Vector3, -- on the face plane
	normal: Vector3, -- outward, unit
	uAxis: Vector3,
	vAxis: Vector3,
	width: number, -- extent along u
	height: number, -- extent along v
	cols: number,
	rows: number,
	spacing: number, -- column spacing (PadDent dx)
	spacingZ: number, -- nominal row spacing (PadDent dz)
	rowVs: { number }, -- v of each row (the wall rims make rows uneven)
	us: { number }, -- per face vertex k = (row - 1) * cols + col
	vs: { number },
	pinned: { boolean },
	first: number, -- layout index of vertex k = 1
	count: number,
}

export type Layout = {
	kind: string, -- "arena" | "backstop"
	quality: Quality,
	pieces: { Piece },
	faces: { Face },
	faceOf: { [number]: { [string]: number } }, -- piece index -> face name -> face index
	vertexCount: number,
	triangleCount: number,
	px: { number },
	py: { number },
	pz: { number },
	nx: { number },
	ny: { number },
	nz: { number },
	tris: { number }, -- flat: triangle k uses tris[3k - 2], tris[3k - 1], tris[3k]
	triColors: { string }?, -- Palette token per triangle; nil = one colour (meshColor, no vertex colours)
	meshColor: string, -- Palette token of the MeshPart ("White" when vertex colours carry the colour)
	anchorFirst: number,
	anchorCount: number,
	restMin: Vector3, -- rest bounds of the faces
	restMax: Vector3,
	boundsMin: Vector3, -- with the anchors
	boundsMax: Vector3,
	center: Vector3, -- centre of the anchored bounds
}

export type LayoutOptions = { walls: boolean? }

-- The instance side of a Sim (JellyRippleController): swap a piece in (rest positions written, real parts hidden),
-- swap it out (rest normals, collapse, real parts shown), write a face's changed vertices (dent.written[1..count],
-- face-local indices; heights dent.h; drawn at (rest + normal · h) ∘ K + T while its piece jiggles, else rest + normal
-- · h; normalsOnly: the positions come with this step's whole-piece write, refresh the normals only), and write every
-- vertex of a jiggling piece at (rest + normal · h) ∘ K + T (h from faceHeights, 0 for a face at rest).
export type SimIO = {
	swapIn: (piece: Piece) -> (),
	swapOut: (piece: Piece) -> (),
	writeFace: (
		face: Face,
		dent: PadDent.Dent,
		count: number,
		K: Vector3?,
		T: Vector3?,
		normalsOnly: boolean?
	) -> (),
	writePiece: (piece: Piece, K: Vector3, T: Vector3) -> (),
}

export type SimOptions = {
	always: boolean?, -- skinMode "always": pieces stay shown (no swap-in or swap-out)
	maxActiveFaces: number?,
	writesPerFrame: number?,
	params: PadDent.Params?,
	jiggleMaxPieces: number?,
	jiggleWritesPerFrame: number?,
}

-- A whole-piece squash spring (path B's wobble, path A's jiggle): omega, zeta, |x| <= maxAmount over all axes
-- together, the vertical share of the bulge and whether the piece keeps its height (squashScale).
export type WobbleSpec = {
	omega: number,
	zeta: number,
	maxAmount: number,
	share: number,
	keepHeight: boolean,
}

type WobbleData = {
	spec: WobbleSpec,
	x: Vector3, -- the squash on each arena axis
	v: Vector3,
	side: Vector3, -- per horizontal axis: the side (+1 / -1) of the face it scales about until it rests; 0 = centre
	omega: number,
	zeta: number,
}

type JiggleRun = {
	wobble: Wobble,
	active: boolean, -- its wobble runs
	resting: boolean, -- stopped while the piece stays shown: its whole-piece write at rest is still to come
	untilAt: number,
	lastHit: number,
	writtenAt: number, -- the step of its last whole-piece write (0 = never)
	K: Vector3, -- the map its vertices are drawn with now (identity at rest)
	T: Vector3,
}

type FaceRun = {
	dent: PadDent.Dent,
	active: boolean,
	untilAt: number,
	lastImpulse: number,
	skip: boolean,
	pendingDt: number,
	lastWrites: number,
}

type SimData = {
	layout: Layout,
	io: SimIO,
	always: boolean,
	maxActive: number,
	writesPerFrame: number,
	params: PadDent.Params,
	runs: { [number]: FaceRun },
	active: { number }, -- awake face indices, in wake order
	pieceActive: { [number]: number }, -- piece index -> awake faces
	swapped: { [number]: boolean }, -- piece index -> its skin shows
	expired: { number }, -- scratch (reused)
	writes: number, -- vertex writes of the last step
	jiggles: { [number]: JiggleRun }, -- piece index -> its jiggle
	jiggling: { number }, -- jiggling piece indices, in kick order
	resting: { number }, -- pieces whose stopped jiggle still waits for its whole-piece write at rest
	lead: { [number]: number }, -- piece index -> its lead face, or NO_LEAD (see the header); nil = none
	jiggleMax: number,
	jiggleBudget: number,
	steps: number,
	whole: { [number]: boolean }, -- scratch: pieces written whole this step
	order: { number }, -- scratch: jiggling and resting pieces, the longest-unwritten first
	ended: { number }, -- scratch: jiggles that ended this step
	jiggleWrites: number, -- whole-piece vertex writes of the last step
}

-- Constants

local RIPPLE = Config.Anim.jellyRipple
local PATH_B = RIPPLE.pathB
local JIGGLE = RIPPLE.jiggle
local STRIPES = WorldLayout.Arena.wallStripes
local NO_CONTACTS: { PadDent.Contact } = table.freeze({})

local STRIPE_COLOR = "Cream" -- reading: ArenaBuilder's stripe colour
local WHITE = "White"
-- Reading (tolerances, not in DESIGN): a contact point counts as on a piece within PIECE_TOLERANCE of its parts' bounds
-- (the block's Cap stands 0.6 above its Body), on a face within FACE_TOLERANCE of its plane (stripes stand 0.05 proud)
-- and EDGE_TOLERANCE beyond its edges (float error).
local PIECE_TOLERANCE = 0.75
local FACE_TOLERANCE = 0.3
local EDGE_TOLERANCE = 0.1
-- §18.3.4 step 2: a floor hit lies within 0.2 studs of the floor top (the Markings paint sits up to 0.06 above it).
local FLOOR_TOLERANCE = 0.2
-- The PadDent mapping (§18.3.4): sinkDepth 0.3 + clampExtra 0.2 = clampIn; the contact-only values are unused.
local SINK_DEPTH = 0.3
local UNUSED_CONTACT_RADIUS = 1
-- Impulse speed scales with the throw radius against this reference (studs; §18.3.4 "clamp(r / 1.0, ...)").
local REFERENCE_RADIUS = 1.0
local DEFAULT_RADIUS = 1.0 -- an unknown projId (§18.3.1)
-- Reading: a wobble (path B, or the path A jiggle) is at rest when |x| is under the deformer's rest epsilon and |v|
-- under this (1/s).
local PATH_B_REST_SPEED = 0.05
local SPLIT_EVEN = 0.5 -- squashScale's bulge share when none is given (the old w = 1 / sqrt(c) on both other axes)
-- sfx.jellyWobble pitch (§18.6): clamp(1.1 - 0.05 · r, 0.85, 1.1).
local WOBBLE_PITCH_BASE = 1.1
local WOBBLE_PITCH_PER_STUD = 0.05
local WOBBLE_PITCH_MIN = 0.85
local WOBBLE_PITCH_MAX = 1.1
local ANCHOR_SIZE = 0.01 -- studs: the legs of a bounds anchor triangle
local NO_LEAD = 0 -- Sim.lead: a moving piece none of whose faces may dent (see the header)
local ANCHOR_VERTICES = 24
local ANCHOR_TRIANGLES = 8
local AXIS_VECTORS: { [string]: Vector3 } = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }
local AXIS_NAMES: { Axis } = { "X", "Y", "Z" }
local WALL_FACES: { FaceName } = { "+Z", "-Z", "+X", "-X", "+Y" }
local BLOCK_FACES: { FaceName } = { "+Z", "-Z", "+X", "-X" }
local BOX_FACES: { FaceName } = { "+X", "-X", "+Y", "-Y", "+Z", "-Z" }
local BACKSTOP_FIXED: { FaceName } = { "-X", "+Y", "-Y", "+Z", "-Z" }

-- Face frames on a unit box: outward normal, u and v (u x v = normal).
local FACE_AXES: { [string]: { n: Vector3, u: Vector3, v: Vector3 } } = {
	["+X"] = { n = Vector3.xAxis, u = -Vector3.zAxis, v = Vector3.yAxis },
	["-X"] = { n = -Vector3.xAxis, u = Vector3.zAxis, v = Vector3.yAxis },
	["+Y"] = { n = Vector3.yAxis, u = Vector3.xAxis, v = -Vector3.zAxis },
	["-Y"] = { n = -Vector3.yAxis, u = Vector3.xAxis, v = Vector3.zAxis },
	["+Z"] = { n = Vector3.zAxis, u = Vector3.xAxis, v = Vector3.yAxis },
	["-Z"] = { n = -Vector3.zAxis, u = -Vector3.xAxis, v = Vector3.yAxis },
}

-- Module tables

local SimClass = {}
SimClass.__index = SimClass

export type Sim = typeof(setmetatable({} :: SimData, SimClass))

local WobbleClass = {}
WobbleClass.__index = WobbleClass

export type Wobble = typeof(setmetatable({} :: WobbleData, WobbleClass))

local JellySkin = {}
JellySkin.PIECE_TOLERANCE = PIECE_TOLERANCE
JellySkin.FACE_TOLERANCE = FACE_TOLERANCE
JellySkin.FLOOR_TOLERANCE = FLOOR_TOLERANCE

-- Private: geometry ---------------------------------------------------------------------------------------------------

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function absVector(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end

-- A face of the box (centre, size): centre on the plane, normal, u, v, width (along u) and height (along v).
local function boxFace(
	center: Vector3,
	size: Vector3,
	name: string
): (Vector3, Vector3, Vector3, Vector3, number, number)
	local axes = FACE_AXES[name]
	assert(axes, `[SD][JellySkin] unknown face {name}`)
	local half = size / 2
	local n, u, v = axes.n, axes.u, axes.v
	local onPlane = center + n * absVector(n):Dot(half)
	return onPlane, n, u, v, absVector(u):Dot(size), absVector(v):Dot(size)
end

local function gridFor(quality: Quality): any
	return if quality == "Low" then RIPPLE.gridLow else RIPPLE.gridHigh
end

-- Rows of a wall face `height` tall: rim rows at both ends and rows every `rowStuds` from rowStuds / 2.
local function rimRows(height: number, rowStuds: number): { number }
	local rows = { -height / 2 }
	local count = math.floor(height / rowStuds + 0.5)
	for k = 0, count - 1 do
		table.insert(rows, -height / 2 + rowStuds / 2 + k * rowStuds)
	end
	table.insert(rows, height / 2)
	return rows
end

local function uniformRows(height: number, rows: number): { number }
	local list: { number } = {}
	for k = 1, rows do
		table.insert(list, -height / 2 + (k - 1) * height / (rows - 1))
	end
	return list
end

-- True when the v-range [v0, v1] of a wall face `height` tall lies inside a stripe band.
local function inStripe(v0: number, v1: number, height: number): boolean
	local y0, y1 = v0 + height / 2, v1 + height / 2
	for _, at in STRIPES.heights do
		local lo, hi = at - STRIPES.thickness / 2, at + STRIPES.thickness / 2
		if y0 >= lo - 1e-6 and y1 <= hi + 1e-6 then
			return true
		end
	end
	return false
end

-- The pieces of WorldLayout.Arena.cover, in its order.
local function buildArenaPieces(): { Piece }
	local pieces: { Piece } = {}
	for index, spec in WorldLayout.Arena.cover do
		local body = spec.parts[1]
		local low, high = body.position - body.size / 2, body.position + body.size / 2
		for _, part in spec.parts do
			low = low:Min(part.position - part.size / 2)
			high = high:Max(part.position + part.size / 2)
		end
		table.insert(pieces, {
			index = index,
			name = spec.name,
			kind = spec.kind,
			center = body.position,
			size = body.size,
			boundsMin = low,
			boundsMax = high,
			base = body.position - Vector3.new(0, body.size.Y / 2, 0),
			color = body.color,
			skinned = false,
			faces = {},
			first = 0,
			count = 0,
			collapse = body.position,
		})
	end
	return pieces
end

local function copyPieces(source: { Piece }): { Piece }
	local list: { Piece } = {}
	for _, piece in source do
		local copy = table.clone(piece)
		copy.faces = {}
		table.insert(list, copy)
	end
	return list
end

local arenaPiecesCache: { Piece }? = nil

-- Private: whole-piece springs ----------------------------------------------------------------------------------------

local jiggleSpecs: { [string]: WobbleSpec } = {}
local pathBSpecCache: WobbleSpec? = nil

-- Path A's jiggle spring for a piece kind: the backstop's |x| cap is maxAmount × backstopAmount / amount (its amounts
-- are all that much smaller); a block keeps its height (its Cap stays a real part, so a taller or shorter skin would
-- poke through it or open a gap under it).
local function jiggleSpec(kind: string): WobbleSpec
	local cached = jiggleSpecs[kind]
	if cached then
		return cached
	end
	local spec: WobbleSpec = table.freeze({
		omega = JIGGLE.omega,
		zeta = JIGGLE.zeta,
		maxAmount = if kind == "backstop"
			then JIGGLE.maxAmount * JIGGLE.backstopAmount / JIGGLE.amount
			else JIGGLE.maxAmount,
		share = JIGGLE.verticalShare,
		keepHeight = kind == "block",
	})
	jiggleSpecs[kind] = spec
	return spec
end

-- Path B's wobble spring (the same bulge split as the jiggle: one feel for both paths).
local function pathBSpec(): WobbleSpec
	local cached = pathBSpecCache
	if cached then
		return cached
	end
	local spec: WobbleSpec = table.freeze({
		omega = PATH_B.omega,
		zeta = PATH_B.zeta,
		maxAmount = PATH_B.maxAmount,
		share = JIGGLE.verticalShare,
		keepHeight = false,
	})
	pathBSpecCache = spec
	return spec
end

-- The box a skinned piece can reach while it dents and jiggles (layout space): its Body box with every face pushed
-- out by clampOut, under any jiggle of `spec`. Conservative: per axis the scale s = c · B with the own squash c within
-- 1 ± maxAmount and the bulge B of the other axes within (1 ± maxAmount)^-e (e: the largest exponent squashScale gives
-- that axis), the pivot P at the centre or either face (the bottom for Y); the mapped coordinate P + (q - P) · s is
-- linear in each of q, P and s, so its extremes are among the corners of those ranges.
local function jiggleReach(piece: Piece, spec: WobbleSpec): (Vector3, Vector3)
	local m = spec.maxAmount
	local out = RIPPLE.clampOut
	local low: { number } = {}
	local high: { number } = {}
	for index, axis in AXIS_NAMES do
		local unit = AXIS_VECTORS[axis]
		local centre = piece.base:Dot(unit)
		local half = piece.size:Dot(unit) / 2
		local qs: { number }, pivots: { number }, scales: { number }
		if axis == "Y" then
			qs, pivots = { centre, centre + piece.size.Y + out }, { centre }
			if spec.keepHeight then
				scales = { 1 }
			else
				local e = 2 * spec.share
				scales = { (1 - m) * (1 + m) ^ -e, (1 + m) * (1 - m) ^ -e }
			end
		else
			local e = (1 - spec.share) + SPLIT_EVEN
			qs, pivots = { centre - half - out, centre + half + out }, { centre - half, centre, centre + half }
			scales = { (1 - m) * (1 + m) ^ -e, (1 + m) * (1 - m) ^ -e }
		end
		local lo, hi = math.huge, -math.huge
		for _, q in qs do
			for _, p in pivots do
				for _, s in scales do
					local mapped = p + (q - p) * s
					lo, hi = math.min(lo, mapped), math.max(hi, mapped)
				end
			end
		end
		low[index], high[index] = lo, hi
	end
	return Vector3.new(low[1], low[2], low[3]), Vector3.new(high[1], high[2], high[3])
end

-- Private: layout building --------------------------------------------------------------------------------------------

type Builder = {
	layout: Layout,
}

local function newLayout(kind: string, quality: Quality, pieces: { Piece }, colored: boolean, meshColor: string): Layout
	return {
		kind = kind,
		quality = quality,
		pieces = pieces,
		faces = {},
		faceOf = {},
		vertexCount = 0,
		triangleCount = 0,
		px = {},
		py = {},
		pz = {},
		nx = {},
		ny = {},
		nz = {},
		tris = {},
		triColors = if colored then {} else nil,
		meshColor = meshColor,
		anchorFirst = 0,
		anchorCount = 0,
		restMin = Vector3.one * math.huge,
		restMax = -Vector3.one * math.huge,
		boundsMin = Vector3.zero,
		boundsMax = Vector3.zero,
		center = Vector3.zero,
	}
end

local function addVertex(layout: Layout, p: Vector3, n: Vector3): number
	local index = layout.vertexCount + 1
	layout.vertexCount = index
	layout.px[index], layout.py[index], layout.pz[index] = p.X, p.Y, p.Z
	layout.nx[index], layout.ny[index], layout.nz[index] = n.X, n.Y, n.Z
	return index
end

local function addTriangle(layout: Layout, a: number, b: number, c: number, color: string)
	local tris = layout.tris
	local k = layout.triangleCount + 1
	layout.triangleCount = k
	tris[3 * k - 2], tris[3 * k - 1], tris[3 * k] = a, b, c
	local colors = layout.triColors
	if colors then
		colors[k] = color
	end
end

-- Adds one face grid (cols uniform across the width, rows at rowVs) to the layout.
local function addFace(
	layout: Layout,
	piece: Piece,
	name: FaceName,
	kind: string,
	cols: number,
	rowVs: { number },
	spacingZ: number,
	moves: boolean,
	striped: boolean
)
	local center, n, u, v, width, height = boxFace(piece.center, piece.size, name)
	local rows = #rowVs
	local spacing = width / (cols - 1)
	local face: Face = {
		index = #layout.faces + 1,
		piece = piece.index,
		name = name,
		kind = kind,
		moves = moves,
		center = center,
		normal = n,
		uAxis = u,
		vAxis = v,
		width = width,
		height = height,
		cols = cols,
		rows = rows,
		spacing = spacing,
		spacingZ = spacingZ,
		rowVs = rowVs,
		us = table.create(cols * rows, 0),
		vs = table.create(cols * rows, 0),
		pinned = table.create(cols * rows, false),
		first = layout.vertexCount + 1,
		count = cols * rows,
	}
	for row = 1, rows do
		for col = 1, cols do
			local k = (row - 1) * cols + col
			local uu = -width / 2 + (col - 1) * spacing
			local vv = rowVs[row]
			face.us[k], face.vs[k] = uu, vv
			face.pinned[k] = not moves or col == 1 or col == cols or row == 1 or row == rows
			local p = center + u * uu + v * vv
			addVertex(layout, p, n)
			layout.restMin = layout.restMin:Min(p)
			layout.restMax = layout.restMax:Max(p)
		end
	end
	local first = face.first
	for row = 1, rows - 1 do
		local color = if striped and inStripe(rowVs[row], rowVs[row + 1], height) then STRIPE_COLOR else piece.color
		for col = 1, cols - 1 do
			local a = first + (row - 1) * cols + col - 1
			local b = a + 1
			local c = b + cols
			local d = a + cols
			addTriangle(layout, a, b, c, color)
			addTriangle(layout, a, c, d, color)
		end
	end
	table.insert(layout.faces, face)
	table.insert(piece.faces, face.index)
	local map = layout.faceOf[piece.index]
	if map == nil then
		map = {}
		layout.faceOf[piece.index] = map
	end
	map[name] = face.index
end

local function beginPiece(layout: Layout, piece: Piece)
	piece.skinned = true
	piece.first = layout.vertexCount + 1
end

local function endPiece(layout: Layout, piece: Piece)
	piece.count = layout.vertexCount - piece.first + 1
end

-- The 8 bounds anchors at the rest bounds widened by `margin` and by what every skinned piece can reach while it dents
-- and jiggles (jiggleReach), then the layout bounds and centre.
local function addAnchors(layout: Layout, margin: number, color: string)
	local low = layout.restMin - Vector3.one * margin
	local high = layout.restMax + Vector3.one * margin
	for _, piece in layout.pieces do
		if piece.skinned then
			local reachLow, reachHigh = jiggleReach(piece, jiggleSpec(piece.kind))
			low, high = low:Min(reachLow), high:Max(reachHigh)
		end
	end
	layout.anchorFirst = layout.vertexCount + 1
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = Vector3.new(
					if sx < 0 then low.X else high.X,
					if sy < 0 then low.Y else high.Y,
					if sz < 0 then low.Z else high.Z
				)
				local normal = Vector3.new(sx, sy, sz).Unit
				local b = corner - Vector3.new(sx * ANCHOR_SIZE, 0, 0)
				local c = corner - Vector3.new(0, 0, sz * ANCHOR_SIZE)
				if (b - corner):Cross(c - corner):Dot(normal) < 0 then
					b, c = c, b
				end
				local ia = addVertex(layout, corner, normal)
				local ib = addVertex(layout, b, normal)
				local ic = addVertex(layout, c, normal)
				addTriangle(layout, ia, ib, ic, color)
			end
		end
	end
	layout.anchorCount = layout.vertexCount - layout.anchorFirst + 1
	layout.boundsMin = low
	layout.boundsMax = high
	layout.center = (low + high) / 2
end

-- Public: pieces and frames -------------------------------------------------------------------------------------------

-- The 12 arena cover pieces (WorldLayout.Arena.cover order), not skinned. Shared: do not change them.
function JellySkin.arenaPieces(): { Piece }
	local cached = arenaPiecesCache
	if cached == nil then
		local built = buildArenaPieces()
		arenaPiecesCache = built
		return built
	end
	return cached
end

-- The cover pieces of the duel view's arena (phase 4 spec 2026-10-11 D9): Candy Court's (arenaPieces) for its id or no
-- id; none for any other arena, whose cover is not Candy Court's (no skin is built there: its floor hits keep the
-- double ring and its cover hits get one ring).
function JellySkin.arenaPiecesFor(arenaId: string?): { Piece }
	if arenaId == nil or arenaId == Arenas.DEFAULT_ID then
		return JellySkin.arenaPieces()
	end
	return {}
end

-- The arena frame from the DuelState numbers (§18.3.4): +Z from PadA to PadB (flattened), +Y up, origin at the pads'
-- XZ midpoint on floorY (the pads sit 0.05 above the floor).
function JellySkin.arenaFrame(padA: CFrame, padB: CFrame, floorY: number): CFrame
	local a, b = padA.Position, padB.Position
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local zAxis = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.zAxis
	local yAxis = Vector3.yAxis
	local xAxis = yAxis:Cross(zAxis)
	return CFrame.fromMatrix(Vector3.new((a.X + b.X) / 2, floorY, (a.Z + b.Z) / 2), xAxis, yAxis, zAxis)
end

-- The practice backstop's frame (its WorldLayout box centre, axis-aligned) and box.
function JellySkin.backstopFrame(): CFrame
	return CFrame.new(WorldLayout.PracticeRange.backstop.position)
end

function JellySkin.backstopSize(): Vector3
	return WorldLayout.PracticeRange.backstop.size
end

local function boxCorners(frame: CFrame, size: Vector3): { Vector3 }
	local corners: { Vector3 } = {}
	for _, sx in { -0.5, 0.5 } do
		for _, sy in { -0.5, 0.5 } do
			for _, sz in { -0.5, 0.5 } do
				table.insert(corners, frame:PointToWorldSpace(size * Vector3.new(sx, sy, sz)))
			end
		end
	end
	return corners
end

-- How far apart two boxes are (studs): the largest distance from a corner of either box to the nearest corner of the
-- other; 0 for the same box, also when it is described turned (a Cylinder part lies on its side). The mismatch guard
-- keeps a piece on path B when its real Body is more than mismatchStuds away from WorldLayout.
function JellySkin.boxMismatch(aFrame: CFrame, aSize: Vector3, bFrame: CFrame, bSize: Vector3): number
	local a, b = boxCorners(aFrame, aSize), boxCorners(bFrame, bSize)
	local worst = 0
	for pass = 1, 2 do
		local from, to = if pass == 1 then a else b, if pass == 1 then b else a
		for _, p in from do
			local nearest = math.huge
			for _, q in to do
				nearest = math.min(nearest, (p - q).Magnitude)
			end
			worst = math.max(worst, nearest)
		end
	end
	return worst
end

-- Public: layouts -----------------------------------------------------------------------------------------------------

-- Vertex and triangle totals of the arena skin, from the formulas (JellySkin_Test checks them against the built
-- layout and the Config caps).
function JellySkin.counts(quality: Quality, options: LayoutOptions?): (number, number)
	local g = gridFor(quality)
	local walls, blocks = 0, 0
	local wallHeight = 0
	for _, piece in JellySkin.arenaPieces() do
		if piece.kind == "wall" then
			walls += 1
			wallHeight = piece.size.Y
		elseif piece.kind == "block" then
			blocks += 1
		end
	end
	local function grid(cols: number, rows: number): (number, number)
		return cols * rows, 2 * (cols - 1) * (rows - 1)
	end
	local rows = math.floor(wallHeight / g.wallRowStuds + 0.5) + 2
	local bigV, bigT = grid(g.wallCols, rows)
	local sideV, sideT = grid(g.wallSideCols, rows)
	local topV, topT = grid(2, 2)
	if g.wallTopCols >= 2 and g.wallTopRows >= 2 then
		topV, topT = grid(g.wallTopCols, g.wallTopRows)
	end
	local blockV, blockT = grid(g.blockCols, g.blockRows)
	local withWalls = options == nil or options.walls ~= false
	local vertices = ANCHOR_VERTICES + blocks * #BLOCK_FACES * blockV
	local triangles = ANCHOR_TRIANGLES + blocks * #BLOCK_FACES * blockT
	if withWalls then
		vertices += walls * (2 * bigV + 2 * sideV + topV)
		triangles += walls * (2 * bigT + 2 * sideT + topT)
	end
	return vertices, triangles
end

-- The arena skin layout (arena space). Pieces are copies of arenaPieces() with their faces filled in.
function JellySkin.arenaLayout(quality: Quality, options: LayoutOptions?): Layout
	local g = gridFor(quality)
	local withWalls = options == nil or options.walls ~= false
	local pieces = copyPieces(JellySkin.arenaPieces())
	local blockColor = "Blueberry"
	for _, piece in pieces do
		if piece.kind == "block" then
			blockColor = piece.color
			break
		end
	end
	local layout = newLayout("arena", quality, pieces, withWalls, if withWalls then WHITE else blockColor)
	for _, piece in pieces do
		if piece.kind == "wall" and withWalls then
			beginPiece(layout, piece)
			local rows = rimRows(piece.size.Y, g.wallRowStuds)
			for _, name in WALL_FACES do
				if name == "+Z" or name == "-Z" then
					addFace(layout, piece, name, "wallBig", g.wallCols, rows, g.wallRowStuds, true, true)
				elseif name == "+X" or name == "-X" then
					addFace(layout, piece, name, "wallSide", g.wallSideCols, rows, g.wallRowStuds, true, false)
				elseif g.wallTopCols >= 2 and g.wallTopRows >= 2 then
					local topRows = uniformRows(piece.size.Z, g.wallTopRows)
					local dz = piece.size.Z / (g.wallTopRows - 1)
					addFace(layout, piece, name, "wallTop", g.wallTopCols, topRows, dz, true, false)
				else
					addFace(layout, piece, name, "fixed", 2, uniformRows(piece.size.Z, 2), piece.size.Z, false, false)
				end
			end
			endPiece(layout, piece)
		elseif piece.kind == "block" then
			beginPiece(layout, piece)
			local rows = uniformRows(piece.size.Y, g.blockRows)
			local dz = piece.size.Y / (g.blockRows - 1)
			for _, name in BLOCK_FACES do
				addFace(layout, piece, name, "blockSide", g.blockCols, rows, dz, true, false)
			end
			endPiece(layout, piece)
		end
	end
	addAnchors(layout, RIPPLE.boundsMargin, blockColor)
	return layout
end

-- The practice backstop as a piece (backstop space: origin at its box centre), not skinned.
local function buildBackstopPiece(): Piece
	local spec = WorldLayout.PracticeRange.backstop
	local size = spec.size
	return {
		index = 1,
		name = "Backstop",
		kind = "backstop",
		center = Vector3.zero,
		size = size,
		boundsMin = -size / 2,
		boundsMax = size / 2,
		base = Vector3.new(0, -size.Y / 2, 0),
		color = spec.color or WHITE,
		skinned = false,
		faces = {},
		first = 0,
		count = 0,
		collapse = Vector3.zero,
	}
end

local backstopPieceCache: Piece? = nil

-- The practice backstop piece (backstop space), not skinned. Shared: do not change it.
function JellySkin.backstopPiece(): Piece
	local cached = backstopPieceCache
	if cached == nil then
		local built = buildBackstopPiece()
		backstopPieceCache = built
		return built
	end
	return cached
end

-- A Body box face of a piece: (centre on its plane, outward normal, u axis, v axis, width along u, height along v),
-- in the piece's layout space.
function JellySkin.boxFaceFrame(piece: Piece, name: FaceName): (Vector3, Vector3, Vector3, Vector3, number, number)
	return boxFace(piece.center, piece.size, name)
end

-- The outward normal of a box face name ("+X" ... "-Z"), in layout space.
function JellySkin.faceNormalOf(name: FaceName): Vector3
	local axes = FACE_AXES[name]
	assert(axes, `[SD][JellySkin] unknown face {name}`)
	return axes.n
end

-- The six box face names, in a fixed order (debug pokes may name a face by its number in this list).
JellySkin.BOX_FACES = table.freeze(table.clone(BOX_FACES))

-- The practice backstop's skin layout (backstop space: origin at its box centre).
function JellySkin.backstopLayout(quality: Quality): Layout
	local backstop = RIPPLE.backstop
	local piece = buildBackstopPiece()
	local size = piece.size
	local color = piece.color
	local layout = newLayout("backstop", quality, { piece }, false, color)
	local cols = if quality == "Low" then backstop.colsLow else backstop.colsHigh
	local rows = if quality == "Low" then backstop.rowsLow else backstop.rowsHigh
	beginPiece(layout, piece)
	addFace(layout, piece, "+X", "backstopFront", cols, uniformRows(size.Y, rows), size.Y / (rows - 1), true, false)
	for _, name in BACKSTOP_FIXED do
		local _, _, _, _, _, height = boxFace(piece.center, piece.size, name)
		addFace(layout, piece, name, "fixed", 2, uniformRows(height, 2), height, false, false)
	end
	endPiece(layout, piece)
	addAnchors(layout, RIPPLE.boundsMargin, color)
	return layout
end

-- The PadDent grid of a face (face-local u, v; outer ring pinned, or every vertex for a fixed face).
function JellySkin.faceGrid(face: Face): PadDent.Grid
	return {
		cols = face.cols,
		rows = face.rows,
		spacing = face.spacing,
		spacingZ = face.spacingZ,
		xs = face.us,
		zs = face.vs,
		pinned = face.pinned,
	}
end

-- The ripple's PadDent parameters (§18.3.4 mapping) from Config.Anim.jellyRipple.
function JellySkin.dentParams(): PadDent.Params
	local sink = math.min(SINK_DEPTH, RIPPLE.clampIn)
	return {
		sinkDepth = sink,
		radius = UNUSED_CONTACT_RADIUS,
		pressOmega = RIPPLE.springOmega,
		releaseOmega = RIPPLE.springOmega,
		releaseZeta = RIPPLE.springZeta,
		waveSpeed = 2 * RIPPLE.waveStudsPerSecond,
		substep = RIPPLE.substep,
		-- A face over the write budget steps every other frame with both frames' dt (§18.3.4), so one step may be
		-- twice the Scheduler's clamp; a clamp at the Scheduler's maxDt would drop time and slow the wave below 40 fps.
		-- PadDent substeps at `substep`, so the longer step stays stable.
		maxDt = 2 * Config.Anim.Scheduler.maxDt,
		clampUp = RIPPLE.clampOut,
		clampExtra = RIPPLE.clampIn - sink,
		sleepEpsilon = RIPPLE.sleepEpsilon,
		activeMargin = RIPPLE.activeMargin,
	}
end

-- Public: hits --------------------------------------------------------------------------------------------------------

-- The piece whose parts' bounds, widened by PIECE_TOLERANCE, hold `p` (the nearest when several do), or nil.
function JellySkin.findPiece(pieces: { Piece }, p: Vector3): Piece?
	local best: Piece? = nil
	local bestDistance = math.huge
	for _, piece in pieces do
		local outside = (piece.boundsMin - p):Max(p - piece.boundsMax):Max(Vector3.zero)
		local distance = outside.Magnitude
		if distance <= PIECE_TOLERANCE and distance < bestDistance then
			best, bestDistance = piece, distance
		end
	end
	return best
end

-- The Body box face of `piece` hit at `p` with normal `n` (see the header), and p's (u, v) on it; nil for an edge
-- hit (no face normal within edgeNormalMinDot of n) or a point off that face.
function JellySkin.hitFace(piece: Piece, p: Vector3, n: Vector3): (FaceName?, number, number)
	if n.Magnitude < 1e-6 then
		return nil, 0, 0
	end
	local unit = n.Unit
	local bestName: FaceName? = nil
	local bestDot = -math.huge
	for _, name in BOX_FACES do
		local dot = unit:Dot(FACE_AXES[name].n)
		if dot > bestDot then
			bestName, bestDot = name, dot
		end
	end
	if bestName == nil or bestDot < RIPPLE.edgeNormalMinDot then
		return nil, 0, 0
	end
	local center, normal, u, v, width, height = boxFace(piece.center, piece.size, bestName)
	local offset = p - center
	if math.abs(offset:Dot(normal)) > FACE_TOLERANCE then
		return nil, 0, 0
	end
	local uu, vv = offset:Dot(u), offset:Dot(v)
	if math.abs(uu) > width / 2 + EDGE_TOLERANCE or math.abs(vv) > height / 2 + EDGE_TOLERANCE then
		return nil, 0, 0
	end
	return bestName, uu, vv
end

-- findPiece + hitFace on a layout: (the skinned face or nil, u, v, the piece or nil).
function JellySkin.findFace(layout: Layout, p: Vector3, n: Vector3): (Face?, number, number, Piece?)
	local piece = JellySkin.findPiece(layout.pieces, p)
	if piece == nil then
		return nil, 0, 0, nil
	end
	local name, u, v = JellySkin.hitFace(piece, p, n)
	if name == nil then
		return nil, 0, 0, piece
	end
	local map = layout.faceOf[piece.index]
	local index = if map then map[name] else nil
	if index == nil then
		return nil, u, v, piece
	end
	return layout.faces[index], u, v, piece
end

-- What a "geometry" hit at arena-space point `p` with normal `n` touched (see the header): (class, piece, face name,
-- u, v). The floor is tested first (a hit at the foot of a wall with an upward normal is a floor hit).
function JellySkin.classify(pieces: { Piece }, p: Vector3, n: Vector3): (HitClass, Piece?, FaceName?, number, number)
	if n.Magnitude > 1e-6 and n.Unit.Y > RIPPLE.floorNormalMinY and math.abs(p.Y) <= FLOOR_TOLERANCE then
		return "floor", nil, nil, 0, 0
	end
	local piece = JellySkin.findPiece(pieces, p)
	if piece == nil then
		return "other", nil, nil, 0, 0
	end
	if piece.kind == "gumdrop" then
		return "round", piece, nil, 0, 0
	end
	local name, u, v = JellySkin.hitFace(piece, p, n)
	if name == nil then
		return "edge", piece, nil, 0, 0
	end
	return "face", piece, name, u, v
end

-- The first Body box face a ray from `origin` along `dir` enters within `studs`: (piece, face name, u, v, distance),
-- or nil.
function JellySkin.rayPiece(
	pieces: { Piece },
	origin: Vector3,
	dir: Vector3,
	studs: number
): (Piece?, FaceName?, number, number, number)
	if dir.Magnitude < 1e-6 or not (studs > 0) then
		return nil, nil, 0, 0, 0
	end
	local unit = dir.Unit
	local bestPiece: Piece? = nil
	local bestName: FaceName? = nil
	local bestT, bestU, bestV = math.huge, 0, 0
	for _, piece in pieces do
		for _, name in BOX_FACES do
			local center, normal, u, v, width, height = boxFace(piece.center, piece.size, name)
			local denominator = unit:Dot(normal)
			if denominator < -1e-9 then
				local t = (center - origin):Dot(normal) / denominator
				if t >= 0 and t <= studs and t < bestT then
					local offset = origin + unit * t - center
					local uu, vv = offset:Dot(u), offset:Dot(v)
					if math.abs(uu) <= width / 2 + 1e-6 and math.abs(vv) <= height / 2 + 1e-6 then
						bestPiece, bestName, bestT, bestU, bestV = piece, name, t, uu, vv
					end
				end
			end
		end
	end
	if bestPiece == nil then
		return nil, nil, 0, 0, 0
	end
	return bestPiece, bestName, bestU, bestV, bestT
end

-- rayPiece on a layout: (the skinned face or nil, u, v, the piece or nil).
function JellySkin.rayFace(
	layout: Layout,
	origin: Vector3,
	dir: Vector3,
	studs: number
): (Face?, number, number, Piece?)
	local piece, name, u, v = JellySkin.rayPiece(layout.pieces, origin, dir, studs)
	if piece == nil or name == nil then
		return nil, 0, 0, nil
	end
	local map = layout.faceOf[piece.index]
	local index = if map then map[name] else nil
	return if index then layout.faces[index] else nil, u, v, piece
end

-- Public: waves -------------------------------------------------------------------------------------------------------

-- The impulse of a hit (§18.3.4): (speed inward in studs/s, radius in studs) for a throw of radius r, or a Dragon Rush
-- lane; ReducedMotion scales the speed by reducedImpulseScale.
function JellySkin.impulseFor(radius: number?, isRush: boolean, reduced: boolean): (number, number)
	local speed, reach
	if isRush then
		speed, reach = RIPPLE.rushImpulseSpeed, RIPPLE.rushImpulseRadius
	else
		local r = if type(radius) == "number" and isFinite(radius) and radius > 0 then radius else DEFAULT_RADIUS
		speed = RIPPLE.impulseSpeed * math.clamp(r / REFERENCE_RADIUS, RIPPLE.impulseScaleMin, RIPPLE.impulseScaleMax)
		reach = math.clamp(RIPPLE.impulseRadiusPerStud * r, RIPPLE.impulseRadiusMin, RIPPLE.impulseRadiusMax)
	end
	if reduced then
		speed *= RIPPLE.reducedImpulseScale
	end
	return speed, reach
end

-- The normal of face vertex k (face-local index) with heights h (face-local), from its 4 neighbours along the face
-- axes (one-sided at the grid edge). Layout space, unit.
function JellySkin.faceNormal(face: Face, h: { number }, k: number): Vector3
	local cols, rows = face.cols, face.rows
	local row = (k - 1) // cols + 1
	local col = k - (row - 1) * cols
	local left = if col > 1 then k - 1 else k
	local right = if col < cols then k + 1 else k
	local down = if row > 1 then k - cols else k
	local up = if row < rows then k + cols else k
	local us, vs = face.us, face.vs
	local du = us[right] - us[left]
	local dv = vs[up] - vs[down]
	local slopeU = if du > 0 then (h[right] - h[left]) / du else 0
	local slopeV = if dv > 0 then (h[up] - h[down]) / dv else 0
	return (face.normal - face.uAxis * slopeU - face.vAxis * slopeV).Unit
end

-- A face's height at (u, v) (bilinear between its grid vertices; clamped to the face).
function JellySkin.sampleFace(face: Face, h: { number }, u: number, v: number): number
	local cols, rows = face.cols, face.rows
	local cu = math.clamp((u - face.us[1]) / face.spacing, 0, cols - 1)
	local col = math.min(math.floor(cu), cols - 2) + 1
	local fu = cu - (col - 1)
	local rowVs = face.rowVs
	local row = 1
	while row < rows - 1 and v > rowVs[row + 1] do
		row += 1
	end
	local span = rowVs[row + 1] - rowVs[row]
	local fv = if span > 0 then math.clamp((v - rowVs[row]) / span, 0, 1) else 0
	local k = (row - 1) * cols + col
	local a, b = h[k], h[k + 1]
	local c, d = h[k + cols], h[k + cols + 1]
	return (a + (b - a) * fu) * (1 - fv) + (c + (d - c) * fu) * fv
end

-- Public: path B ------------------------------------------------------------------------------------------------------

-- The arena axis closest to a (layout-space) normal.
function JellySkin.squashAxis(n: Vector3): Axis
	local ax, ay, az = math.abs(n.X), math.abs(n.Y), math.abs(n.Z)
	if ay >= ax and ay >= az then
		return "Y"
	end
	return if ax >= az then "X" else "Z"
end

-- The squash S for x along `axis` (see the header): c = 1 + x on the axis; for a horizontal axis c^-share up and
-- c^-(1 - share) across, for Y c^-0.5 on X and Z, so c times the bulge is always 1 (the volume is kept); keepHeight
-- holds Y at 1. share defaults to 0.5 (the old w = 1 / sqrt(c) on both other axes).
function JellySkin.squashScale(x: number, axis: Axis, share: number?, keepHeight: boolean?): Vector3
	local c = 1 + x
	if axis == "Y" then
		local w = 1 / math.sqrt(c)
		return Vector3.new(w, if keepHeight then 1 else c, w)
	end
	local up = if share == nil then SPLIT_EVEN else share
	local vertical = if keepHeight then 1 else c ^ -up
	local across = c ^ -(1 - up)
	if axis == "X" then
		return Vector3.new(c, vertical, across)
	end
	return Vector3.new(across, vertical, c)
end

-- The throw's radius scale of a hit (impulseFor's): clamp(r / 1.0, impulseScaleMin, impulseScaleMax).
local function radiusScale(radius: number?): number
	local r = if type(radius) == "number" and isFinite(radius) and radius > 0 then radius else DEFAULT_RADIUS
	return math.clamp(r / REFERENCE_RADIUS, RIPPLE.impulseScaleMin, RIPPLE.impulseScaleMax)
end

-- The path B squash amount for a piece kind (§18.3.5; the jiggle's feel since the user test of 2026-10-07): amount or
-- roundAmount × the throw's radius scale, × rushScale for Dragon Rush, × reducedScale under ReducedMotion (a small rise
-- and fall), at most maxAmount.
function JellySkin.pathBAmount(kind: string, isRush: boolean, reduced: boolean, radius: number?): number
	local amount = if kind == "gumdrop" then PATH_B.roundAmount else PATH_B.amount
	if isRush then
		amount *= PATH_B.rushScale
	else
		amount *= radiusScale(radius)
	end
	if reduced then
		amount *= PATH_B.reducedScale
	end
	return math.min(amount, PATH_B.maxAmount)
end

-- The path B spring (omega, zeta); zeta = 1 under ReducedMotion (no wobble).
function JellySkin.pathBSpring(reduced: boolean): (number, number)
	return PATH_B.omega, if reduced then 1 else PATH_B.zeta
end

-- The first swing of a spring kicked from rest with a unit speed: e^(-zeta·omega·t) · sin(omega_d · t) / omega_d at
-- its peak, t = atan2(omega_d, zeta·omega) / omega_d (zeta >= 1: t · e^(-omega·t) at t = 1 / omega).
local function firstSwing(omega: number, zeta: number): number
	if zeta >= 1 then
		return 1 / (omega * math.exp(1))
	end
	local damped = omega * math.sqrt(1 - zeta * zeta)
	local t = math.atan2(damped, zeta * omega) / damped
	return math.exp(-zeta * omega * t) * math.sin(damped * t) / damped
end

-- The velocity kick (negative = squash along the hit axis) that makes a spring at rest swing to -amount on its first
-- swing (about 100 ms later at omega 14).
function JellySkin.kickSpeed(amount: number, omega: number, zeta: number): number
	return -amount / firstSwing(omega, zeta)
end

-- True when a wobble's axis has come to rest.
function JellySkin.pathBSettled(x: number, v: number): boolean
	return math.abs(x) < Config.Anim.deform.restEpsilon and math.abs(v) < PATH_B_REST_SPEED
end

-- The scale of a piece squashed by x.X, x.Y and x.Z along the three arena axes (the product of the three squashes;
-- share and keepHeight as in squashScale).
function JellySkin.wobbleScale(x: Vector3, share: number?, keepHeight: boolean?): Vector3
	return JellySkin.squashScale(x.X, "X", share, keepHeight)
		* JellySkin.squashScale(x.Y, "Y", share, keepHeight)
		* JellySkin.squashScale(x.Z, "Z", share, keepHeight)
end

-- How far a point `p` of a piece scaled by S about `base` moved along `n` (all in the pivot's space): the surface
-- shift under a splat on path B.
function JellySkin.surfaceOffset(base: Vector3, S: Vector3, p: Vector3, n: Vector3): number
	local relative = p - base
	return (relative * (S - Vector3.one)):Dot(n)
end

-- The sfx.jellyWobble pitch multiplier for a throw of radius r (§18.6).
function JellySkin.wobblePitch(radius: number?): number
	local r = if type(radius) == "number" and isFinite(radius) then radius else DEFAULT_RADIUS
	return math.clamp(WOBBLE_PITCH_BASE - WOBBLE_PITCH_PER_STUD * r, WOBBLE_PITCH_MIN, WOBBLE_PITCH_MAX)
end

-- Public: the whole-piece jiggle (path A) -----------------------------------------------------------------------------

-- The jiggle spring of a piece kind (see jiggleSpec above).
JellySkin.jiggleSpec = jiggleSpec

-- Path B's spring (see pathBSpec above).
JellySkin.pathBSpec = pathBSpec

-- The jiggle amount of a path A hit on a piece of `kind` (see the header); 0 under ReducedMotion.
function JellySkin.jiggleAmount(kind: string, radius: number?, isRush: boolean, reduced: boolean): number
	if reduced then
		return 0
	end
	local amount = if isRush then JIGGLE.rushAmount else JIGGLE.amount * radiusScale(radius)
	if kind == "backstop" then
		amount *= JIGGLE.backstopAmount / JIGGLE.amount
	end
	return math.min(amount, jiggleSpec(kind).maxAmount)
end

-- Where a point q of a jiggling piece is drawn: q ∘ K + T (layout space), (K, T) from Wobble:map.
function JellySkin.jiggledPoint(q: Vector3, K: Vector3, T: Vector3): Vector3
	return q * K + T
end

-- The box a skinned piece can reach while it dents and jiggles (layout space; the bounds anchors hold it).
function JellySkin.jiggleReach(piece: Piece): (Vector3, Vector3)
	return jiggleReach(piece, jiggleSpec(piece.kind))
end

-- Wobble (path B, and the path A jiggle) ------------------------------------------------------------------------------

-- One piece's wobble, at rest (see the header): path B's spring, or `spec` (jiggleSpec(kind) for path A).
function JellySkin.newWobble(spec: WobbleSpec?): Wobble
	local chosen = if spec then spec else pathBSpec()
	local data: WobbleData = {
		spec = chosen,
		x = Vector3.zero,
		v = Vector3.zero,
		side = Vector3.zero,
		omega = chosen.omega,
		zeta = chosen.zeta,
	}
	return setmetatable(data, WobbleClass)
end

-- True when every axis has come to rest.
function WobbleClass.settled(self: Wobble): boolean
	return self.x == Vector3.zero and self.v == Vector3.zero
end

-- Where `axis` scales about (map) from now until the whole wobble rests again: the face on `side` (+1 / -1) of a
-- horizontal axis, or its centre (0); Y always scales about the bottom. Taken only while the whole wobble rests: a
-- moving wobble keeps its pivots, since moving one would make the drawn piece jump.
function WobbleClass.pivot(self: Wobble, axis: Axis, side: number)
	if axis == "Y" or not self:settled() then
		return
	end
	local unit = AXIS_VECTORS[axis]
	local s = if side > 0 then 1 elseif side < 0 then -1 else 0
	self.side = self.side * (Vector3.one - unit) + unit * s
end

-- A hit along `axis` with this squash amount (pathBAmount, jiggleAmount): a kick that swings x to -amount on its first
-- swing. ReducedMotion sets zeta = 1 (no wobble) until the next hit without it. `side`: pivot(axis, side) first (taken
-- only from rest; nil = keep the pivots).
function WobbleClass.hit(self: Wobble, axis: Axis, amount: number, reduced: boolean, side: number?)
	local spec = self.spec
	self.omega, self.zeta = spec.omega, if reduced then 1 else spec.zeta
	if side ~= nil then
		self:pivot(axis, side)
	end
	self.v += AXIS_VECTORS[axis] * JellySkin.kickSpeed(amount, self.omega, self.zeta)
end

-- ReducedMotion turned on while the wobble moves: no more swings. zeta = 1 and the speed is dropped, so it returns to
-- rest without crossing it (a gentle fall, as a ReducedMotion hit gives), until the next hit without ReducedMotion.
function WobbleClass.calm(self: Wobble)
	if self.zeta >= 1 then
		return
	end
	self.zeta = 1
	self.v = Vector3.zero
end

-- One axis after a step: exactly 0 once settled.
local function settleAxis(x: number, v: number): (number, number)
	if JellySkin.pathBSettled(x, v) then
		return 0, 0
	end
	return x, v
end

-- Advances every axis by dt (Util/Spring's substep rule); |x| <= maxAmount over all axes (a clamped wobble loses its
-- outward speed); once every axis has settled the pivots go back to the centre.
function WobbleClass.step(self: Wobble, dt: number)
	if self.x == Vector3.zero and self.v == Vector3.zero then
		return
	end
	local x, v = Spring.integrate(self.x, self.v, Vector3.zero, self.omega, self.zeta, dt)
	local limit = self.spec.maxAmount
	local size = x.Magnitude
	if size > limit then
		local unit = x / size
		x = unit * limit
		local outward = v:Dot(unit)
		if outward > 0 then
			v -= unit * outward
		end
	end
	local xx, vx = settleAxis(x.X, v.X)
	local xy, vy = settleAxis(x.Y, v.Y)
	local xz, vz = settleAxis(x.Z, v.Z)
	self.x, self.v = Vector3.new(xx, xy, xz), Vector3.new(vx, vy, vz)
	if self:settled() then
		self.side = Vector3.zero
	end
end

-- The squash on each arena axis now.
function WobbleClass.amounts(self: Wobble): Vector3
	return self.x
end

-- The piece's scale now (about its pivot, in arena axes).
function WobbleClass.scale(self: Wobble): Vector3
	return JellySkin.wobbleScale(self.x, self.spec.share, self.spec.keepHeight)
end

-- The jiggle as an axis-aligned affine map q -> q ∘ K + T for a piece with this bottom centre `base` and Body `size`
-- (layout space): every axis scales by S (scale(): its own squash times the other axes' bulge) about its pivot P (the
-- face on its side for a horizontal axis with one, else the centre; the bottom for Y). So q' = P + (q - P) · S, i.e.
-- K = S and T = P · (1 - S): a face on its axis's pivot plane moves only with its dent (h · S), the bottom row stays
-- at base.Y, and at rest K = 1 and T = 0.
function WobbleClass.map(self: Wobble, base: Vector3, size: Vector3): (Vector3, Vector3)
	local S = self:scale()
	local P = base + self.side * size / 2
	return S, P * (Vector3.one - S)
end

-- Back to rest at once.
function WobbleClass.reset(self: Wobble)
	self.x, self.v, self.side = Vector3.zero, Vector3.zero, Vector3.zero
end

-- Sim -----------------------------------------------------------------------------------------------------------------

local function removeFrom(list: { number }, value: number)
	local at = table.find(list, value)
	if at then
		table.remove(list, at)
	end
end

local function removeActive(self: Sim, faceIndex: number)
	removeFrom(self.active, faceIndex)
end

local function isJiggling(self: Sim, pieceIndex: number): boolean
	local run = self.jiggles[pieceIndex]
	return run ~= nil and run.active
end

-- The map a piece's vertices are drawn with now (the one of its last whole-piece write) while it jiggles or waits for
-- its write at rest; nil when it is drawn at rest.
local function mapOf(self: Sim, pieceIndex: number): (Vector3?, Vector3?)
	local run = self.jiggles[pieceIndex]
	if run == nil or not (run.active or run.resting) then
		return nil, nil
	end
	return run.K, run.T
end

-- Forgets the map a piece is drawn with (it is collapsed or dropped: the next swap-in draws it at rest).
local function forgetMap(self: Sim, pieceIndex: number)
	local run = self.jiggles[pieceIndex]
	if run == nil then
		return
	end
	if run.resting then
		run.resting = false
		removeFrom(self.resting, pieceIndex)
	end
	run.K, run.T = Vector3.one, Vector3.zero
end

-- Puts an awake face to rest: its dent snaps to rest; the rest heights are written (with the map its piece is drawn
-- with) when the piece stays shown (other awake faces, its jiggle, "always" mode, or keepShown: the piece is being hit
-- right now).
local function retire(self: Sim, faceIndex: number, keepShown: boolean?)
	local run = self.runs[faceIndex]
	if run == nil or not run.active then
		return
	end
	run.active = false
	run.skip = false
	run.pendingDt = 0
	run.lastWrites = 0
	local face = self.layout.faces[faceIndex]
	local left = (self.pieceActive[face.piece] or 1) - 1
	self.pieceActive[face.piece] = left
	local count = run.dent:snapToRest()
	local jiggling = isJiggling(self, face.piece)
	if count > 0 and (self.always or left > 0 or keepShown == true or jiggling) then
		local K, T = mapOf(self, face.piece)
		self.io.writeFace(face, run.dent, count, K, T)
	end
end

local function swapOutIdle(self: Sim, pieceIndex: number)
	if
		self.always
		or not self.swapped[pieceIndex]
		or (self.pieceActive[pieceIndex] or 0) > 0
		or isJiggling(self, pieceIndex)
	then
		return
	end
	self.swapped[pieceIndex] = false
	forgetMap(self, pieceIndex)
	self.io.swapOut(self.layout.pieces[pieceIndex])
end

-- Stops a piece's jiggle at once. A piece that stays shown (awake faces, or "always" mode) keeps the shape it is drawn
-- with until its whole-piece write at rest, which step() makes within the budget; otherwise the caller swaps it out
-- (swapOutIdle) and the next swap-in draws it at rest.
local function stopJiggle(self: Sim, pieceIndex: number)
	local run = self.jiggles[pieceIndex]
	if run == nil or not run.active then
		return
	end
	run.active = false
	run.wobble:reset()
	removeFrom(self.jiggling, pieceIndex)
	local drawn = run.K ~= Vector3.one or run.T ~= Vector3.zero
	local shown = self.always or ((self.pieceActive[pieceIndex] or 0) > 0 and self.swapped[pieceIndex] == true)
	if drawn and shown then
		if not run.resting then
			run.resting = true
			table.insert(self.resting, pieceIndex)
		end
	else
		forgetMap(self, pieceIndex)
	end
end

-- The side (+1 / -1) of a face along its squash axis; 0 for Y (the bottom pivot never moves).
local function sideOf(normal: Vector3, axis: Axis): number
	if axis == "Y" then
		return 0
	end
	return if normal:Dot(AXIS_VECTORS[axis]) >= 0 then 1 else -1
end

-- True when no face of the piece ripples but `lead` (a jiggle then cannot beat with the dent of another face).
local function onlyLeadAwake(self: Sim, pieceIndex: number, lead: number): boolean
	for _, faceIndex in self.layout.pieces[pieceIndex].faces do
		local run = self.runs[faceIndex]
		if faceIndex ~= lead and run ~= nil and run.active then
			return false
		end
	end
	return true
end

-- Kicks a piece's jiggle along the axis of the hit `face`; the lead face's axis scales about the lead face (pivots are
-- taken only from rest, see Wobble:pivot; NO_LEAD: every axis about its centre, Y about the bottom).
local function kickJiggle(self: Sim, face: Face, lead: number, amount: number, now: number, seconds: number)
	local pieceIndex = face.piece
	local piece = self.layout.pieces[pieceIndex]
	local run = self.jiggles[pieceIndex]
	if run == nil then
		local made: JiggleRun = {
			wobble = JellySkin.newWobble(jiggleSpec(piece.kind)),
			active = false,
			resting = false,
			untilAt = 0,
			lastHit = -math.huge,
			writtenAt = 0,
			K = Vector3.one,
			T = Vector3.zero,
		}
		self.jiggles[pieceIndex] = made
		run = made
	end
	local current = run :: JiggleRun
	if not current.active then
		-- At most jiggleMax jiggle: the one with the oldest kick stops (and swaps out when nothing else holds it).
		while #self.jiggling >= self.jiggleMax and #self.jiggling > 0 do
			local oldest, oldestAt = self.jiggling[1], math.huge
			for _, index in self.jiggling do
				local other = self.jiggles[index]
				if other.lastHit < oldestAt then
					oldest, oldestAt = index, other.lastHit
				end
			end
			stopJiggle(self, oldest)
			swapOutIdle(self, oldest)
		end
		current.active = true
		current.untilAt = 0
		current.writtenAt = 0
		if current.resting then
			current.resting = false
			removeFrom(self.resting, pieceIndex)
		end
		table.insert(self.jiggling, pieceIndex)
	end
	current.lastHit = now
	current.untilAt = math.max(current.untilAt, now + seconds)
	local leadFace = self.layout.faces[lead]
	if leadFace then
		local leadAxis: Axis = JellySkin.squashAxis(leadFace.normal)
		current.wobble:pivot(leadAxis, sideOf(leadFace.normal, leadAxis))
	end
	current.wobble:hit(JellySkin.squashAxis(face.normal), amount, false)
end

-- A Sim over a layout (see the header).
function JellySkin.newSim(layout: Layout, io: SimIO, options: SimOptions?): Sim
	local opts: SimOptions = options or {}
	local data: SimData = {
		layout = layout,
		io = io,
		always = opts.always == true,
		maxActive = opts.maxActiveFaces or RIPPLE.maxActiveFaces,
		writesPerFrame = opts.writesPerFrame or RIPPLE.writesPerFrame,
		params = opts.params or JellySkin.dentParams(),
		runs = {},
		active = {},
		pieceActive = {},
		swapped = {},
		expired = {},
		writes = 0,
		jiggles = {},
		jiggling = {},
		resting = {},
		lead = {},
		jiggleMax = opts.jiggleMaxPieces or JIGGLE.maxPieces,
		jiggleBudget = opts.jiggleWritesPerFrame
			or (if layout.quality == "Low" then JIGGLE.writesPerFrameLow else JIGGLE.writesPerFrame),
		steps = 0,
		whole = {},
		order = {},
		ended = {},
		jiggleWrites = 0,
	}
	return setmetatable(data, SimClass)
end

-- A hit on face `faceIndex` at (u, v): (speed, radius) from impulseFor; the face stays awake at most `seconds` after
-- its last impulse. `jiggle` (jiggleAmount; nil or 0 = none) also kicks the piece's whole-piece jiggle, which ends at
-- most `seconds` after its last kick. While the piece moves, only its lead face dents: a hit on another face only
-- kicks the jiggle (see the header). Returns false for a face that never moves.
function SimClass.impulse(
	self: Sim,
	faceIndex: number,
	u: number,
	v: number,
	speed: number,
	radius: number,
	now: number,
	seconds: number,
	jiggle: number?
): boolean
	local face = self.layout.faces[faceIndex]
	if face == nil or not face.moves then
		return false
	end
	local pieceIndex = face.piece
	local kicks = jiggle ~= nil and jiggle > 0
	-- The lead face: the face of a jiggling hit on the piece at rest; NO_LEAD when the jiggle cannot hold that face's
	-- plane still (the wall top: Y scales about the bottom), so no face dents while the piece moves.
	if (self.pieceActive[pieceIndex] or 0) == 0 and not isJiggling(self, pieceIndex) then
		if not kicks then
			self.lead[pieceIndex] = nil
		else
			self.lead[pieceIndex] = if JellySkin.squashAxis(face.normal) == "Y" then NO_LEAD else faceIndex
		end
	end
	local lead = self.lead[pieceIndex]
	local kick = kicks and lead ~= nil and onlyLeadAwake(self, pieceIndex, lead)
	if not self.always and not self.swapped[pieceIndex] then
		self.swapped[pieceIndex] = true
		self.io.swapIn(self.layout.pieces[pieceIndex])
	end
	if kick and faceIndex ~= lead then
		kickJiggle(self, face, lead :: number, jiggle :: number, now, seconds)
		return true
	end
	local run = self.runs[faceIndex]
	if run == nil then
		local made: FaceRun = {
			dent = PadDent.new(JellySkin.faceGrid(face), self.params),
			active = false,
			untilAt = 0,
			lastImpulse = -math.huge,
			skip = false,
			pendingDt = 0,
			lastWrites = 0,
		}
		self.runs[faceIndex] = made
		run = made
	end
	local current = run :: FaceRun
	if not current.active then
		-- At most maxActiveFaces awake: the one with the oldest impulse snaps to rest (its piece swaps out unless it is
		-- the one being hit, or it still jiggles).
		while #self.active >= self.maxActive do
			local oldest, oldestAt = self.active[1], math.huge
			for _, index in self.active do
				local other = self.runs[index]
				if other.lastImpulse < oldestAt then
					oldest, oldestAt = index, other.lastImpulse
				end
			end
			local oldestPiece = self.layout.faces[oldest].piece
			removeActive(self, oldest)
			retire(self, oldest, oldestPiece == pieceIndex)
			if oldestPiece ~= pieceIndex then
				swapOutIdle(self, oldestPiece)
			end
		end
		current.active = true
		table.insert(self.active, faceIndex)
		self.pieceActive[pieceIndex] = (self.pieceActive[pieceIndex] or 0) + 1
	end
	current.lastImpulse = now
	current.untilAt = math.max(current.untilAt, now + seconds)
	current.dent:impulse(u, v, speed, radius)
	if kick then
		kickJiggle(self, face, lead :: number, jiggle :: number, now, seconds)
	end
	return true
end

-- Steps every awake face and jiggle by dt (see the header). Returns the face vertex writes made (swap and whole-piece
-- writes not counted; jiggleWrites holds the whole-piece ones).
function SimClass.step(self: Sim, dt: number, now: number, reduced: boolean): number
	self.steps += 1
	self.jiggleWrites = 0
	local list = self.active
	local expired = self.expired
	local expiredCount = 0
	local kept = 0
	for i = 1, #list do
		local faceIndex = list[i]
		local run = self.runs[faceIndex]
		if now >= run.untilAt or run.dent:isAsleep() then
			expiredCount += 1
			expired[expiredCount] = faceIndex
		else
			kept += 1
			list[kept] = faceIndex
		end
	end
	for i = #list, kept + 1, -1 do
		list[i] = nil
	end
	for i = 1, expiredCount do
		retire(self, expired[i])
	end
	-- Jiggles: step, then end the settled and timed-out ones (all of them under ReducedMotion).
	local jiggling = self.jiggling
	local ended = self.ended
	local endedCount = 0
	local jiggleKept = 0
	for i = 1, #jiggling do
		local pieceIndex = jiggling[i]
		local run = self.jiggles[pieceIndex]
		if not reduced then
			run.wobble:step(dt)
		end
		if reduced or now >= run.untilAt or run.wobble:settled() then
			endedCount += 1
			ended[endedCount] = pieceIndex
		else
			jiggleKept += 1
			jiggling[jiggleKept] = pieceIndex
		end
	end
	for i = #jiggling, jiggleKept + 1, -1 do
		jiggling[i] = nil
	end
	for i = 1, endedCount do
		stopJiggle(self, ended[i])
	end
	-- Whole-piece writes this step: the jiggling pieces (at their map now) and the resting ones still shown (at rest),
	-- the longest-unwritten first, within the budget (one piece even over it when nothing was written yet). A piece
	-- left out keeps the map it is drawn with, and its faces' writes use that map too, so it is never drawn with two.
	local order = self.order
	local candidates = 0
	for pass = 1, 2 do
		local source = if pass == 1 then jiggling else self.resting
		for i = 1, #source do
			local pieceIndex = source[i]
			if pass == 2 and not self.always and (self.pieceActive[pieceIndex] or 0) == 0 then
				continue -- it swaps out at the end of this step instead
			end
			local at = self.jiggles[pieceIndex].writtenAt
			local j = candidates
			while j >= 1 and self.jiggles[order[j]].writtenAt > at do
				order[j + 1] = order[j]
				j -= 1
			end
			order[j + 1] = pieceIndex
			candidates += 1
		end
	end
	for i = #order, candidates + 1, -1 do
		order[i] = nil
	end
	local whole = self.whole
	table.clear(whole)
	local room = self.jiggleBudget
	local chosen = 0
	for i = 1, candidates do
		local pieceIndex = order[i]
		local piece = self.layout.pieces[pieceIndex]
		if chosen == 0 or piece.count <= room then
			whole[pieceIndex] = true
			room -= piece.count
			chosen += 1
			local run = self.jiggles[pieceIndex]
			run.writtenAt = self.steps
			if run.active then
				run.K, run.T = run.wobble:map(piece.base, piece.size)
			else
				run.K, run.T = Vector3.one, Vector3.zero
			end
		end
	end
	-- Faces.
	local budget = self.writesPerFrame
	local written = 0
	for i = 1, kept do
		local faceIndex = list[i]
		local run = self.runs[faceIndex]
		if run.lastWrites > budget and not run.skip then
			run.skip = true
			run.pendingDt += dt
			continue
		end
		run.skip = false
		local frameDt = dt + run.pendingDt
		run.pendingDt = 0
		local count = run.dent:step(frameDt, NO_CONTACTS, reduced)
		if count > 0 then
			local face = self.layout.faces[faceIndex]
			local K, T = mapOf(self, face.piece)
			self.io.writeFace(face, run.dent, count, K, T, whole[face.piece] == true)
		end
		run.lastWrites = count
		written += count
		budget = math.max(0, budget - count)
	end
	-- Whole pieces, with this step's heights.
	for i = 1, candidates do
		local pieceIndex = order[i]
		if whole[pieceIndex] then
			local run = self.jiggles[pieceIndex]
			local piece = self.layout.pieces[pieceIndex]
			self.io.writePiece(piece, run.K, run.T)
			self.jiggleWrites += piece.count
			if run.resting then
				run.resting = false
				removeFrom(self.resting, pieceIndex)
			end
		end
	end
	for i = 1, expiredCount do
		swapOutIdle(self, self.layout.faces[expired[i]].piece)
		expired[i] = 0
	end
	for i = 1, endedCount do
		swapOutIdle(self, ended[i])
		ended[i] = 0
	end
	self.writes = written
	return written
end

-- The visible surface height (studs along the face's outward normal) at (u, v) of a face, with the jiggle map its
-- piece is drawn with; 0 when both are at rest.
function SimClass.offset(self: Sim, faceIndex: number, u: number, v: number): number
	local face = self.layout.faces[faceIndex]
	if face == nil then
		return 0
	end
	local run = self.runs[faceIndex]
	local h = if run ~= nil and run.active then JellySkin.sampleFace(face, run.dent.h, u, v) else 0
	local K, T = mapOf(self, face.piece)
	if K == nil or T == nil then
		return h
	end
	local p = face.center + face.uAxis * u + face.vAxis * v
	return ((p + face.normal * h) * K + T - p):Dot(face.normal)
end

-- A face's dent heights (face-local, dent.h) while it ripples; nil at rest (heights 0).
function SimClass.faceHeights(self: Sim, faceIndex: number): { number }?
	local run = self.runs[faceIndex]
	if run == nil or not run.active then
		return nil
	end
	return run.dent.h
end

-- True while the face ripples.
function SimClass.isActive(self: Sim, faceIndex: number): boolean
	local run = self.runs[faceIndex]
	return run ~= nil and run.active
end

-- True while the piece jiggles.
function SimClass.isJiggling(self: Sim, pieceIndex: number): boolean
	return isJiggling(self, pieceIndex)
end

-- The jiggle map (K, T) the piece is drawn with (its last whole-piece write) while it jiggles or waits for its write
-- at rest; nil when it is drawn at rest.
function SimClass.jiggleMap(self: Sim, pieceIndex: number): (Vector3?, Vector3?)
	return mapOf(self, pieceIndex)
end

-- The piece's lead face (see the header) while it moves: a face index, 0 (NO_LEAD: no face of it may dent) or nil
-- (none: it moves without a jiggle, or rests).
function SimClass.leadFace(self: Sim, pieceIndex: number): number?
	return self.lead[pieceIndex]
end

-- True while the piece shows its skin (swapped in; always true in "always" mode once marked).
function SimClass.isSwapped(self: Sim, pieceIndex: number): boolean
	return self.always or self.swapped[pieceIndex] == true
end

function SimClass.activeCount(self: Sim): number
	return #self.active
end

function SimClass.jiggleCount(self: Sim): number
	return #self.jiggling
end

-- Pieces whose stopped jiggle still waits for its whole-piece write at rest.
function SimClass.restingCount(self: Sim): number
	return #self.resting
end

function SimClass.swappedCount(self: Sim): number
	local count = 0
	for _, on in self.swapped do
		if on then
			count += 1
		end
	end
	return count
end

-- Forgets a piece at once (streamed out, or its skin is gone): its faces and its jiggle stop without any write and it
-- is no longer swapped in. No callbacks: the caller collapses or restores it.
function SimClass.dropPiece(self: Sim, pieceIndex: number)
	for _, faceIndex in self.layout.pieces[pieceIndex].faces do
		local run = self.runs[faceIndex]
		if run and run.active then
			run.active = false
			run.skip = false
			run.pendingDt = 0
			run.lastWrites = 0
			run.dent:snapToRest()
			removeActive(self, faceIndex)
		end
	end
	local jiggle = self.jiggles[pieceIndex]
	if jiggle then
		if jiggle.active then
			jiggle.active = false
			jiggle.wobble:reset()
			removeFrom(self.jiggling, pieceIndex)
		end
		forgetMap(self, pieceIndex)
	end
	self.lead[pieceIndex] = nil
	self.pieceActive[pieceIndex] = 0
	self.swapped[pieceIndex] = false
end

-- Forgets everything without callbacks (the skin is being destroyed).
function SimClass.reset(self: Sim)
	for pieceIndex in self.layout.pieces do
		self:dropPiece(pieceIndex)
	end
	table.clear(self.active)
	table.clear(self.jiggling)
	table.clear(self.resting)
	table.clear(self.lead)
end

return JellySkin
