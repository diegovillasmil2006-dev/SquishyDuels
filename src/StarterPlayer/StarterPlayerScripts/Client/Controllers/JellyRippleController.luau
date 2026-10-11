--!strict
-- JellyRippleController (client only). DESIGN §18.3 (jelly ripple on walls and cover), §18.1, §18.6 (sfx.jellyWobble),
-- §18.9, §9.1 #5, §9.12. The only owner of surface responses: where a squishy hits a wall or a cover block, that face
-- dents in, springs back and sends a soft wave to its edges (path A); round gumdrops, and every piece path A cannot
-- take, squash and wobble as a whole with a ring (path B); the floor gets a double ring, rails, caps and edges one ring.
-- Cosmetic only: started by the server's ThrowImpact (and the UltimateEvent lane numbers), drawn on this screen only;
-- the real cover used for collisions never moves.
--
-- Listens to ThrowStarted (radius, practice flag and thrower per projId; dropped at the impact or
-- ProjectileMaxLifetime + 5 s after the release), ThrowImpact, UltimateEvent (a release's lane dir and radius per
-- projId) and StateController.DuelChanged; one Scheduler render effect (step) does everything else. Piece presence is
-- polled every presencePollSeconds inside step (no other connections).
--
-- Places (a frame from layout space to the world, and the real pieces streamed in there):
--   * "arena": while the duel view is positioned (Positioning .. Result), from DuelState numbers only:
--     JellySkin.arenaFrame(PadA, PadB, floorY); pieces Workspace.SD_ArenaSlots.Arena_<slot>.Geometry.Cover.Cover_<name>.
--     Ends at Returning, Cancelled, Void or when the view is gone. Candy Court only (phase 4 spec 2026-10-11 D9): in
--     another arena (DuelState arena.arenaId) the place has no pieces (JellySkin.arenaPiecesFor) and no skin is built;
--     its floor hits keep the double ring and its cover hits get one ring.
--   * "backstop": Workspace.SD_Lobby.PracticeRange.Backstop (reading: LobbyBuilder's names), only while there is no
--     duel view.
--   A real piece is bound when it has streamed in; its Body is checked against WorldLayout (mismatchStuds): a piece
--   off by more never gets the skin (path B only).
--
-- Path A, the jelly skin (§18.3.4): at most one skin at a time, key "arena" or "backstop", each needing a slot of
-- Anim/MeshQuota first. The arena skin is built when the view is positioned; the backstop skin when the camera is
-- within backstop.createStuds of it (destroyed beyond destroyStuds, and as soon as a duel view appears). The layout is
-- JellySkin's (quality from Anim/MeshQuality; walls left out when vertexColors is off); the EditableMesh is filled at
-- <= buildMsPerFrame per frame (vertices, then triangles with their normals and vertex colours, then every piece is
-- collapsed in "onHit" mode), then AssetService:CreateMeshPartAsync(Content.fromObject(mesh), {Box, Precise}) makes
-- the MeshPart in Workspace.SD_ClientFx (Anchored, Massless, CanCollide/CanQuery/CanTouch false, SD_Cosmetic,
-- SmoothPlastic, Color White under vertex colours, else the layout colour). Mesh space = layout space - layout.center.
--   * skinMode "onHit" (default): at rest a piece's skin vertices sit collapsed on its Body centre and the real parts
--     show. A hit swaps the piece in (its rest positions are written; its real Body and Stripe_n parts, or the
--     backstop, get LocalTransparencyModifier = 1 and CastShadow = false; a block's Cap stays) and kicks the face's
--     PadDent (JellySkin Sim). When every face of the piece has slept (faceSeconds after its last impulse) its rest
--     normals are written, the real parts show again and it collapses. "always": bound pieces show their skin for the
--     whole duel (the real parts stay hidden).
--   * Camera guard ("onHit" only; reading of §18.3.4's S2 risk): the default camera's Popper stops treating a part as
--     a wall once its LocalTransparencyModifier hides it, and the skin is CanCollide false, so a swapped-in piece behind
--     the player could let the camera pop through it and fill the view. So a piece whose Body (widened by
--     CAMERA_GUARD_PAD) touches the camera's line (focus to CAMERA_GUARD_BEYOND past the camera, blocksCamera) is
--     never swapped in: that hit uses path B. Each frame a shown piece that comes onto the line is swapped out at once
--     (its faces snap to rest). counts().stats.cameraGuards counts both. "always" mode has no guard (S2 decides it).
--   * Each frame the Sim steps the awake faces within writesPerFrame vertex writes (a vertex write = its SetPosition
--     plus the SetNormal refreshes it causes, JellySkin.faceNormal); swap writes are counted apart.
--   * Whole-piece jiggle (user test 2026-10-07, "too weak, need more animation like 10x"; JellySkin's header,
--     Config.Anim.jellyRipple.jiggle): every path A hit also kicks the hit piece's jiggle (JellySkin.jiggleAmount; none
--     under ReducedMotion), a jelly-cube squash and stretch of the whole piece that never lifts it off the floor.
--     While the piece moves only its first hit face (the lead) dents; a hit on another of its faces only kicks the
--     jiggle (a second dent would beat with the jiggle faster than 3 Hz, §9.12). While it jiggles, the Sim has every
--     vertex of the piece rewritten (writePiece: SetPosition only, the rest and dent normals are kept) within
--     jiggle.writesPerFrame per frame (writesPerFrameLow at Low), at most jiggle.maxPieces at once, plus one write
--     at rest when a jiggle ends while the piece stays shown; the piece swaps out only when its faces sleep and its
--     jiggle rests. counts().stats.jiggleWrites counts those writes.
--   * Failures (§17.6.1's rule): an error or nil while creating, adding or setting up, a refused quota, pathA = false,
--     Config.Debug.forceRipplePathB or debugForcePathB(true) switch that key to path B for the session, with one log
--     line "jelly ripple <key>: path B (<reason>)" and no retry; an error while the skin runs destroys it, shows the
--     real parts and does the same. Reading: an error while adding at High rebuilds once at Low first (§18.3.4 "retry
--     once at Low").
--
-- Hits (ThrowImpact kind "geometry"; other kinds get nothing here):
--   * In the arena (JellySkin.classify in arena space): floor -> double ring; a skinned face of a bound piece whose skin
--     is ready -> path A; a face that never moves (the wall top at Low) -> one ring; a gumdrop, or a face path A cannot
--     take -> path B; an edge, a Cap, a rail or anything else -> one ring.
--   * No normal (a Dragon Rush lane end E, the swept sphere's centre): JellySkin.rayPiece from E along the lane's dir
--     for its radius + rushProbeMarginStuds -> a Rush impulse on that face (path A, else B); nothing when no face is hit.
--   * The practice backstop: its front face gets path A when its skin is ready, any other backstop hit one ring.
--   * Elsewhere: an upward normal (floorNormalMinY) -> double ring, a practice one at PracticeTargets.FLOOR_Y (the
--     payload carries the projectile centre, §18.3.1); anything else nothing (lobby props: none in this pass).
-- Path B (§18.3.5): a SpecialMesh child on every part of the piece (Brick, Cylinder for a Cylinder part, Sphere for a
--   Ball; reading: a piece with any other kind of part gets a ring instead, so no real part is ever resized or moved),
--   then SquishDeformer.attach(model, {includePrimary = true, pivot = its Body's bottom centre in arena axes}); a
--   JellySkin wobble per piece (JellySkin.pathBAmount with the throw's radius: the jiggle's feel); at most
--   pathB.maxPieces wobble at once (a new one stops the oldest); plus one ring.
-- Rings (§18.3.6): Anim/FxShapes.ring, White; floor: floorDiameters[1] now and floorDiameters[2] floorDelay later (from
--   this effect's step), at most Effects.impactRings; others coverDiameter. ReducedMotion: one ring.
-- ReducedMotion (§18.1): path A no wave (c = 0), zeta = 1, impulse × reducedImpulseScale, no jiggle (one running when
--   it turns on stops); path B amount × pathB.reducedScale, zeta = 1 (a small rise and fall; a wobble running when it
--   turns on is calmed: no more swings, a gentle return to rest); one ring. Sounds never change.
-- Sound (§18.6): sfx.jellyWobble at the impact on the first frame >= wobbleAfterImpactMs after a hit that starts a
--   ripple (path A or B), pitch × JellySkin.wobblePitch(r); priority 1, another player's practice throw -1 (reading).
-- On real parts only LocalTransparencyModifier, CastShadow and our own SpecialMesh children (Scale/Offset) are written,
-- and all are restored (guarding Parent ~= nil) when the place ends, on clear() and on a failure.
--
-- Public: offsetAt(worldPoint, normal) -> studs (the visible surface's offset along the normal there: path A's face
-- height with its piece's jiggle, or path B's shift; 0 when nothing moves; SplatController rides it; reading: a
-- splat follows the jiggle along the normal only, not the bulge's slide along the face (about 0.4 studs at the edge
-- of a 6-stud face for a normal throw, none at its centre), since offsetAt returns one number), isHidden(part),
-- clear() (the leak-check reset; the same as the duel view ending), counts(), blocksCamera(focus, eye, boxCFrame,
-- boxSize) (pure, the camera guard), and the Studio hooks debugForcePathB(on) and debugPoke(pieceName, face, u, v).

-- Services

local AssetService = game:GetService("AssetService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local PracticeTargets = require(Shared.Practice.PracticeTargets)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local FxShapes = require(Client.Anim.FxShapes)
local JellySkin = require(Client.Anim.JellySkin)
local MeshQuality = require(Client.Anim.MeshQuality)
local MeshQuota = require(Client.Anim.MeshQuota)
local PadDent = require(Client.Anim.PadDent)
local Scheduler = require(Client.Anim.Scheduler)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local Tweens = require(Client.Anim.Tweens)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)

-- Types

type ThrowInfo = { radius: number, practice: boolean, own: boolean, untilAt: number }
type LaneInfo = { dir: Vector3, radius: number, untilAt: number }

-- A real piece streamed in at a place: its container (the cover Model, or the backstop part), its Body, the parts the
-- skin hides and what they were before.
type Real = {
	container: Instance,
	body: BasePart,
	hide: { BasePart },
	saved: { [BasePart]: { ltm: number, shadow: boolean } },
	hidden: boolean,
	mismatch: boolean,
}

type Place = {
	key: string, -- "arena" | "backstop"
	frame: CFrame, -- layout space -> world
	pieces: { JellySkin.Piece },
	reals: { [number]: Real }, -- piece index -> its streamed-in real piece
	matchId: string?,
	slot: number?,
}

type Stage = "vertices" | "triangles" | "collapse" | "creating" | "ready" | "dead"

type Skin = {
	key: string,
	place: Place,
	quality: JellySkin.Quality,
	layout: JellySkin.Layout,
	always: boolean,
	stage: Stage,
	cursor: number,
	editable: any, -- EditableMesh
	part: MeshPart?,
	vertexIds: { number },
	normalIds: { number },
	colorIds: { [string]: number },
	pieceOf: { number }, -- layout vertex -> piece index (0 = a bounds anchor)
	sim: JellySkin.Sim?,
	shown: { [number]: boolean }, -- piece index -> its skin shows (rest positions written, real parts hidden)
	center: Vector3,
	stamp: { number }, -- normal refresh marks (layout index), reused by every write
	stampList: { number },
	stampFrame: number,
	triedLow: boolean,
}

type Wobbler = {
	container: Model,
	place: Place,
	pieceIndex: number,
	kind: string,
	deformer: SquishDeformer.Deformer,
	meshes: { SpecialMesh },
	wobble: JellySkin.Wobble,
	pivot: CFrame, -- world: the Body's bottom centre, arena axes
	boxFrame: CFrame, -- the model's bounding box at setup (offsetAt)
	boxSize: Vector3,
	active: boolean,
	lastHit: number,
}

type PendingSound = { dueAt: number, at: Vector3, pitch: number, priority: number }
type PendingRing = { dueAt: number, position: Vector3, normal: Vector3, diameter: number, seconds: number }

type Outcome = "A" | "B" | "ring" | "none"

-- Constants

local RIPPLE = Config.Anim.jellyRipple
local RINGS = RIPPLE.rings
local PATH_B = RIPPLE.pathB
local BACKSTOP = RIPPLE.backstop
local IMPACT_RINGS = Config.Vfx.Effects.impactRings
local MAX_LIFETIME = Config.Duel.Rules.ProjectileMaxLifetime
local WOBBLE_DELAY = Config.Audio.wobbleAfterImpactMs / 1000
local SOUND_WOBBLE = "sfx.jellyWobble"
local KEY_ARENA = "arena"
local KEY_BACKSTOP = "backstop"
local CLIENT_FX = "SD_ClientFx"
local COSMETIC_GROUP = "SD_Cosmetic"
local ARENA_CONTAINER = "SD_ArenaSlots" -- ArenaService's names
local ARENA_PREFIX = "Arena_"
local COVER_PREFIX = "Cover_" -- ArenaBuilder's names
local BODY_NAME = "Body"
local STRIPE_PREFIX = "Stripe_"
local LOBBY_ROOT = "SD_Lobby" -- LobbyBuilder's names
local BACKSTOP_NAME = "Backstop"
local MESH_NAME = "SD_JellyMesh" -- our path B SpecialMesh children
local ENDED_PHASES: { [string]: boolean } = { Returning = true, Cancelled = true, Void = true }
local DEFAULT_RADIUS = 1.0 -- an unknown projId (§18.3.1)
local SLACK_SECONDS = 5 -- projId records live ProjectileMaxLifetime + this after the release (§18.3.1)
-- Reading (not in DESIGN): a hit counts as in the arena within this many studs outside its playable box.
local ARENA_MARGIN = 6
local ARENA_TOP = 40
-- Camera guard (reading, see the header): the camera line counts this far past the camera (the default camera stops
-- just in front of what it hits), and a piece's Body this much wider on every side (its stripes, the camera's near
-- plane).
local CAMERA_GUARD_BEYOND = 2
local CAMERA_GUARD_PAD = 0.5
local FIRST_PERSON_STUDS = 1e-3 -- a camera this close to its focus has no line to guard
local BUILD_CLOCK_EVERY = 32 -- mesh adds between two clock reads while building
local OWN_PRIORITY = 1 -- §18.6: layered after sfx.impactSoft (VfxController plays it at priority 1)
local OTHERS_PRIORITY = -1 -- another player's practice throw (dropped first)
local MESH_TYPES: { [Enum.PartType]: Enum.MeshType } = {
	[Enum.PartType.Block] = Enum.MeshType.Brick,
	[Enum.PartType.Cylinder] = Enum.MeshType.Cylinder,
	[Enum.PartType.Ball] = Enum.MeshType.Sphere,
}

-- Module table

local JellyRippleController = {}

-- Private

local log = Log.new("JellyRipple")
local cleanup: Cleanup.Cleanup? = nil
local throws: { [number]: ThrowInfo } = {}
local lanes: { [number]: LaneInfo } = {}
local duelView: any = nil
local arena: Place? = nil
local backstop: Place? = nil
local skin: Skin? = nil
local wobblers: { [Model]: Wobbler } = {}
local pendingSounds: { PendingSound } = {}
local pendingRings: { PendingRing } = {}
local liveRings: { [any]: boolean } = {}
local hiddenParts: { [BasePart]: boolean } = {}
local failed: { [string]: string } = {}
local forced = false
local pollAt = -math.huge
local stats = {
	impacts = 0,
	pathA = 0,
	pathB = 0,
	rings = 0,
	sounds = 0,
	swapWrites = 0,
	faceWrites = 0,
	jiggleWrites = 0, -- whole-piece vertex writes of the path A jiggle
	cameraGuards = 0, -- path A hits sent to path B, or ripples ended early, because the piece held the camera
}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function reduced(): boolean
	return Tweens.reducedMotion()
end

local function clientFx(): Instance
	local folder = Workspace:FindFirstChild(CLIENT_FX)
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = CLIENT_FX
		created.Parent = Workspace
		folder = created
	end
	return folder :: Instance
end

local function cosmeticRegistered(): boolean
	local ok, registered = pcall(function(): boolean
		return PhysicsService:IsCollisionGroupRegistered(COSMETIC_GROUP)
	end)
	return ok and registered == true
end

local function paletteColor(token: string?): Color3
	local value = if token then (Palette :: any)[token] else nil
	return if typeof(value) == "Color3" then value else Palette.White
end

local function localUserId(): number?
	local player = Players.LocalPlayer
	return if player then player.UserId else nil
end

-- Real parts -----------------------------------------------------------------------------------------------------------

local function setHidden(real: Real, hidden: boolean)
	if real.hidden == hidden then
		return
	end
	real.hidden = hidden
	for _, part in real.hide do
		if hidden then
			if real.saved[part] == nil then
				real.saved[part] = { ltm = part.LocalTransparencyModifier, shadow = part.CastShadow }
			end
			hiddenParts[part] = true
			if part.Parent ~= nil then
				part.LocalTransparencyModifier = 1
				part.CastShadow = false
			end
		else
			hiddenParts[part] = nil
			local saved = real.saved[part]
			if saved and part.Parent ~= nil then
				part.LocalTransparencyModifier = saved.ltm
				part.CastShadow = saved.shadow
			end
		end
	end
end

-- The parts a piece's skin stands in for: the Body and a wall's Stripe_n parts (a block's Cap stays real).
local function hideListOf(container: Instance, body: BasePart, kind: string): { BasePart }
	local list: { BasePart } = { body }
	if kind == "wall" then
		for _, child in container:GetChildren() do
			if child:IsA("BasePart") and string.sub(child.Name, 1, #STRIPE_PREFIX) == STRIPE_PREFIX then
				table.insert(list, child)
			end
		end
	end
	return list
end

local function bindReal(place: Place, piece: JellySkin.Piece, container: Instance, body: BasePart): Real
	local expectedFrame = place.frame * CFrame.new(piece.center)
	local mismatch = JellySkin.boxMismatch(body.CFrame, body.Size, expectedFrame, piece.size) > RIPPLE.mismatchStuds
	return {
		container = container,
		body = body,
		hide = hideListOf(container, body, piece.kind),
		saved = {},
		hidden = false,
		mismatch = mismatch,
	}
end

-- Path B ------------------------------------------------------------------------------------------------------------

local function stopWobbler(wobbler: Wobbler)
	wobbler.wobble:reset()
	wobbler.active = false
	pcall(function()
		wobbler.deformer:rest()
	end)
end

local function destroyWobbler(wobbler: Wobbler)
	if wobblers[wobbler.container] == wobbler then
		wobblers[wobbler.container] = nil
	end
	pcall(function()
		wobbler.deformer:destroy()
	end)
	for _, mesh in wobbler.meshes do
		mesh:Destroy()
	end
	table.clear(wobbler.meshes)
end

local function destroyWobblersOf(place: Place, pieceIndex: number?)
	for _, wobbler in table.clone(wobblers) do
		if wobbler.place == place and (pieceIndex == nil or wobbler.pieceIndex == pieceIndex) then
			destroyWobbler(wobbler)
		end
	end
end

-- The Body's bottom centre with the place's axes: path B squashes about it, so a piece never sinks into the floor.
local function bottomPivot(place: Place, body: BasePart): CFrame
	local up = place.frame.UpVector
	local cf = body.CFrame
	local half = body.Size / 2
	local extent = math.abs(cf.RightVector:Dot(up)) * half.X
		+ math.abs(cf.UpVector:Dot(up)) * half.Y
		+ math.abs(cf.LookVector:Dot(up)) * half.Z
	return place.frame.Rotation + (body.Position - up * extent)
end

-- Path B's setup on a piece (once per place): a SpecialMesh on every part, then the deformer. Nil when the piece has a
-- part a SpecialMesh cannot shape (reading: the deformer would resize or move it, which real parts never allow).
local function setupWobbler(place: Place, pieceIndex: number, real: Real): Wobbler?
	local container = real.container
	if not container:IsA("Model") then
		return nil
	end
	local model = container :: Model
	local plain: { Part } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			if not descendant:IsA("Part") or MESH_TYPES[(descendant :: Part).Shape] == nil then
				return nil
			end
			table.insert(plain, descendant :: Part)
		end
	end
	local meshes: { SpecialMesh } = {}
	for _, part in plain do
		if part:FindFirstChildWhichIsA("DataModelMesh") == nil then
			local mesh = Instance.new("SpecialMesh")
			mesh.Name = MESH_NAME
			mesh.MeshType = MESH_TYPES[part.Shape]
			mesh.Scale = Vector3.one
			mesh.Parent = part
			table.insert(meshes, mesh)
		end
	end
	local pivot = bottomPivot(place, real.body)
	local ok, deformer = pcall(SquishDeformer.attach, model, { includePrimary = true, pivot = pivot })
	if not ok then
		for _, mesh in meshes do
			mesh:Destroy()
		end
		log:warn(`path B could not attach to {model:GetFullName()}:`, deformer)
		return nil
	end
	local boxFrame, boxSize = model:GetBoundingBox()
	local wobbler: Wobbler = {
		container = model,
		place = place,
		pieceIndex = pieceIndex,
		kind = place.pieces[pieceIndex].kind,
		deformer = deformer,
		meshes = meshes,
		wobble = JellySkin.newWobble(),
		pivot = pivot,
		boxFrame = boxFrame,
		boxSize = boxSize,
		active = false,
		lastHit = -math.huge,
	}
	wobblers[model] = wobbler
	return wobbler
end

local function activeWobblerCount(): number
	local count = 0
	for _, wobbler in wobblers do
		if wobbler.active then
			count += 1
		end
	end
	return count
end

-- Kicks path B on a piece (a throw of `radius`). Returns false when the piece cannot wobble (not streamed in, or not
-- shapeable).
local function wobblePiece(
	place: Place,
	piece: JellySkin.Piece,
	localNormal: Vector3,
	isRush: boolean,
	radius: number,
	now: number
): boolean
	local real = place.reals[piece.index]
	if real == nil or not real.container:IsA("Model") then
		return false
	end
	local wobbler: Wobbler? = wobblers[real.container :: Model]
	if wobbler == nil then
		wobbler = setupWobbler(place, piece.index, real)
		if wobbler == nil then
			return false
		end
	end
	local current = wobbler :: Wobbler
	if not current.active then
		while activeWobblerCount() >= PATH_B.maxPieces do
			local oldest: Wobbler? = nil
			for _, other in wobblers do
				if other.active and (oldest == nil or other.lastHit < (oldest :: Wobbler).lastHit) then
					oldest = other
				end
			end
			if oldest == nil then
				break
			end
			stopWobbler(oldest)
		end
	end
	local isReduced = reduced()
	current.wobble:hit(
		JellySkin.squashAxis(localNormal),
		JellySkin.pathBAmount(piece.kind, isRush, isReduced, radius),
		isReduced
	)
	current.active = true
	current.lastHit = now
	return true
end

local function stepWobblers(dt: number)
	local isReduced = reduced()
	for _, wobbler in wobblers do
		if not wobbler.active then
			continue
		end
		if isReduced then
			-- ReducedMotion turned on mid-wobble: no more swings, a gentle return to rest (as a ReducedMotion hit gives).
			wobbler.wobble:calm()
		end
		wobbler.wobble:step(dt)
		local ok, err = pcall(function()
			if wobbler.wobble:settled() then
				wobbler.active = false
				wobbler.deformer:rest()
			else
				wobbler.deformer:setScale(wobbler.wobble:scale())
			end
		end)
		if not ok then
			log:warn("a path B wobble failed:", err)
			destroyWobbler(wobbler)
		end
	end
end

-- Rings and sounds ---------------------------------------------------------------------------------------------------

local function startRing(position: Vector3, normal: Vector3, diameter: number, seconds: number)
	local ok, ring = pcall(FxShapes.ring, position, normal, diameter, seconds, Palette.White, RINGS.transparencyFrom)
	if ok and ring ~= nil then
		liveRings[ring] = true
		stats.rings += 1
	elseif not ok then
		log:warn("ring failed:", ring)
	end
end

local function coverRing(position: Vector3, normal: Vector3)
	startRing(position, normal, RINGS.coverDiameter, RINGS.coverSeconds)
end

-- The floor's "puddle": the first ring now, the next ones floorDelay apart (from step; ReducedMotion: one).
local function floorRings(position: Vector3, normal: Vector3, now: number)
	local diameters = RINGS.floorDiameters
	local count = math.min(#diameters, IMPACT_RINGS)
	if reduced() then
		count = math.min(count, 1)
	end
	if count < 1 then
		return
	end
	startRing(position, normal, diameters[1], RINGS.floorSeconds)
	for k = 2, count do
		table.insert(pendingRings, {
			dueAt = now + RINGS.floorDelay * (k - 1),
			position = position,
			normal = normal,
			diameter = diameters[k],
			seconds = RINGS.floorSeconds,
		})
	end
end

local function queueWobbleSound(at: Vector3, radius: number, priority: number, now: number)
	table.insert(pendingSounds, {
		dueAt = now + WOBBLE_DELAY,
		at = at,
		pitch = JellySkin.wobblePitch(radius),
		priority = priority,
	})
end

local function runPending(now: number)
	if #pendingRings > 0 then
		local kept = {}
		for _, ring in pendingRings do
			if now >= ring.dueAt then
				startRing(ring.position, ring.normal, ring.diameter, ring.seconds)
			else
				table.insert(kept, ring)
			end
		end
		pendingRings = kept
	end
	if #pendingSounds > 0 then
		local kept = {}
		for _, sound in pendingSounds do
			if now >= sound.dueAt then
				stats.sounds += 1
				local ok, err = pcall(SoundController.play, SOUND_WOBBLE, {
					at = sound.at,
					pitch = sound.pitch,
					priority = sound.priority,
				})
				if not ok then
					log:warn(`sound {SOUND_WOBBLE} failed:`, err)
				end
			else
				table.insert(kept, sound)
			end
		end
		pendingSounds = kept
	end
	for ring in liveRings do
		if (ring :: any).done == true then
			liveRings[ring] = nil
		end
	end
end

-- Path A: the skin -------------------------------------------------------------------------------------------------

local function restPosition(layout: JellySkin.Layout, i: number): Vector3
	return Vector3.new(layout.px[i], layout.py[i], layout.pz[i])
end

local function restNormal(layout: JellySkin.Layout, i: number): Vector3
	return Vector3.new(layout.nx[i], layout.ny[i], layout.nz[i])
end

-- Rest positions of a piece's vertices (it shows).
local function writePieceRest(s: Skin, piece: JellySkin.Piece)
	local editable = s.editable
	for i = piece.first, piece.first + piece.count - 1 do
		editable:SetPosition(s.vertexIds[i], restPosition(s.layout, i) - s.center)
	end
	stats.swapWrites += piece.count
end

-- Rest normals and the collapse point for a piece's vertices (it is invisible; the real parts show).
local function writePieceCollapsed(s: Skin, piece: JellySkin.Piece)
	local editable = s.editable
	local at = piece.collapse - s.center
	for i = piece.first, piece.first + piece.count - 1 do
		editable:SetNormal(s.normalIds[i], restNormal(s.layout, i))
		editable:SetPosition(s.vertexIds[i], at)
	end
	stats.swapWrites += piece.count
end

local function showPiece(s: Skin, pieceIndex: number)
	local piece = s.layout.pieces[pieceIndex]
	local real = s.place.reals[pieceIndex]
	if s.shown[pieceIndex] or not piece.skinned or real == nil then
		return
	end
	local wobbler = if real.container:IsA("Model") then wobblers[real.container :: Model] else nil
	if wobbler and wobbler.active then
		stopWobbler(wobbler)
	end
	writePieceRest(s, piece)
	s.shown[pieceIndex] = true
	setHidden(real, true)
end

local function collapsePiece(s: Skin, pieceIndex: number)
	local piece = s.layout.pieces[pieceIndex]
	if not s.shown[pieceIndex] then
		return
	end
	s.shown[pieceIndex] = false
	writePieceCollapsed(s, piece)
	local real = s.place.reals[pieceIndex]
	if real then
		setHidden(real, false)
	end
end

-- Camera guard (see the header): true when the real piece lies on the current camera's line (blocksCamera).
local function holdsCamera(real: Real, focus: Vector3, eye: Vector3): boolean
	local body = real.body
	if body.Parent == nil then
		return false
	end
	return JellyRippleController.blocksCamera(focus, eye, body.CFrame, body.Size)
end

-- The current camera's focus and position, or nil without a camera.
local function cameraLine(): (Vector3?, Vector3?)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil, nil
	end
	return camera.Focus.Position, camera.CFrame.Position
end

-- Ends a shown piece's ripple at once: its faces snap to rest and its real parts show again, so the camera stops at
-- them again.
local function dropShown(s: Skin, pieceIndex: number)
	local sim = s.sim
	if sim then
		sim:dropPiece(pieceIndex)
	end
	collapsePiece(s, pieceIndex)
	stats.cameraGuards += 1
end

-- Each frame in "onHit" mode: a shown piece that now lies on the camera's line is swapped out at once.
local function guardCamera(s: Skin)
	if s.always or s.stage ~= "ready" then
		return
	end
	local focus, eye = cameraLine()
	if focus == nil or eye == nil then
		return
	end
	for pieceIndex, shown in s.shown do
		local real = s.place.reals[pieceIndex]
		if shown and real and holdsCamera(real, focus, eye) then
			dropShown(s, pieceIndex)
		end
	end
end

-- Writes a face's changed vertices (dent.written, face-local; at (rest + normal · h) ∘ K + T while the piece jiggles)
-- and refreshes the normals of those vertices and of their 4 neighbours, each once (no table or closure per call).
-- normalsOnly: the piece is written whole this step (writePiece), so only the normals are refreshed here.
local function writeFace(
	s: Skin,
	face: JellySkin.Face,
	dent: PadDent.Dent,
	count: number,
	K: Vector3?,
	T: Vector3?,
	normalsOnly: boolean?
)
	local layout = s.layout
	local editable = s.editable
	local h, written = dent.h, dent.written
	local first, cols, rows = face.first, face.cols, face.rows
	local normal = face.normal
	local center = s.center
	local stamp, list = s.stamp, s.stampList
	local mark = s.stampFrame + 1
	s.stampFrame = mark
	local listed = 0
	local positions = normalsOnly ~= true
	for j = 1, count do
		local k = written[j]
		local i = first + k - 1
		if positions then
			local q = restPosition(layout, i) + normal * h[k]
			if K ~= nil and T ~= nil then
				q = q * K + T
			end
			editable:SetPosition(s.vertexIds[i], q - center)
		end
		local row = (k - 1) // cols + 1
		local col = k - (row - 1) * cols
		for neighbour = 0, 4 do
			local other = k
			if neighbour == 1 then
				other = if col > 1 then k - 1 else 0
			elseif neighbour == 2 then
				other = if col < cols then k + 1 else 0
			elseif neighbour == 3 then
				other = if row > 1 then k - cols else 0
			elseif neighbour == 4 then
				other = if row < rows then k + cols else 0
			end
			if other > 0 and stamp[first + other - 1] ~= mark then
				stamp[first + other - 1] = mark
				listed += 1
				list[listed] = other
			end
		end
	end
	for j = 1, listed do
		local k = list[j]
		editable:SetNormal(s.normalIds[first + k - 1], JellySkin.faceNormal(face, h, k))
	end
	stats.faceWrites += count
end

-- Every vertex of a jiggling piece at (rest + normal · h) ∘ K + T, h its face's dent heights (0 for a face at rest).
-- Positions only: the normals stay the rest and dent ones (an axis-aligned scale keeps a flat face's normal).
local function writePiece(s: Skin, piece: JellySkin.Piece, K: Vector3, T: Vector3)
	local layout = s.layout
	local editable = s.editable
	local center = s.center
	local sim = s.sim
	for _, faceIndex in piece.faces do
		local face = layout.faces[faceIndex]
		local h = if sim then sim:faceHeights(faceIndex) else nil
		local normal = face.normal
		local first = face.first
		for k = 1, face.count do
			local i = first + k - 1
			local q = restPosition(layout, i)
			if h then
				q += normal * h[k]
			end
			editable:SetPosition(s.vertexIds[i], q * K + T - center)
		end
	end
	stats.jiggleWrites += piece.count
end

local function newIO(s: Skin): JellySkin.SimIO
	return {
		swapIn = function(piece: JellySkin.Piece)
			showPiece(s, piece.index)
		end,
		swapOut = function(piece: JellySkin.Piece)
			collapsePiece(s, piece.index)
		end,
		writeFace = function(
			face: JellySkin.Face,
			dent: PadDent.Dent,
			count: number,
			K: Vector3?,
			T: Vector3?,
			normalsOnly: boolean?
		)
			writeFace(s, face, dent, count, K, T, normalsOnly)
		end,
		writePiece = function(piece: JellySkin.Piece, K: Vector3, T: Vector3)
			writePiece(s, piece, K, T)
		end,
	}
end

local function destroySkin()
	local s = skin
	if s == nil then
		return
	end
	skin = nil
	s.stage = "dead"
	local sim = s.sim
	if sim then
		sim:reset()
	end
	for _, real in s.place.reals do
		setHidden(real, false)
	end
	local part = s.part
	s.part = nil
	if part then
		part:Destroy()
	end
	pcall(function()
		s.editable:Destroy()
	end)
	MeshQuota.release(s.key)
end

-- Path B for `key` for the rest of the session, one log line per key.
local function failKey(key: string, reason: string)
	local s = skin
	if s and s.key == key then
		destroySkin()
	end
	if failed[key] ~= nil then
		return
	end
	failed[key] = reason
	log:warn(`jelly ripple {key}: path B ({reason})`)
end

-- Why path A may not be built for `key` now, or nil.
local function blocker(): string?
	if RIPPLE.pathA == false then
		return "Config.Anim.jellyRipple.pathA is off"
	end
	if forced or Config.Debug.forceRipplePathB then
		return "forced by a debug flag"
	end
	return nil
end

local function newSkin(key: string, place: Place, quality: JellySkin.Quality): Skin
	local layout = if key == KEY_ARENA
		then JellySkin.arenaLayout(quality, { walls = RIPPLE.vertexColors ~= false })
		else JellySkin.backstopLayout(quality)
	local editable: any = AssetService:CreateEditableMesh()
	if editable == nil then
		error("CreateEditableMesh returned nil", 0)
	end
	local pieceOf: { number } = table.create(layout.vertexCount, 0)
	for _, piece in layout.pieces do
		if piece.skinned then
			for i = piece.first, piece.first + piece.count - 1 do
				pieceOf[i] = piece.index
			end
		end
	end
	return {
		key = key,
		place = place,
		quality = quality,
		layout = layout,
		always = RIPPLE.skinMode == "always",
		stage = "vertices",
		cursor = 1,
		editable = editable,
		part = nil,
		vertexIds = table.create(layout.vertexCount, 0),
		normalIds = table.create(layout.vertexCount, 0),
		colorIds = {},
		pieceOf = pieceOf,
		sim = nil,
		shown = {},
		center = layout.center,
		stamp = table.create(layout.vertexCount, 0),
		stampList = table.create(layout.vertexCount, 0),
		stampFrame = 0,
		triedLow = quality == "Low",
	}
end

local function startSkin(key: string, place: Place)
	local reason = blocker()
	if reason then
		failKey(key, reason)
		return
	end
	local quality = MeshQuality.forCamera(Workspace.CurrentCamera)
	if quality == nil then
		return -- the viewport is not real yet: asked again on the next poll
	end
	if not MeshQuota.tryAcquire(key) then
		failKey(key, "mesh quota full (Config.Vfx.Budgets.editableMeshes)")
		return
	end
	local wanted: JellySkin.Quality = if quality == "Low" then "Low" else "High"
	local ok, made = pcall(function(): Skin
		return newSkin(key, place, wanted)
	end)
	if not ok then
		MeshQuota.release(key)
		failKey(key, tostring(made))
		return
	end
	skin = made
end

-- The MeshPart, made once the mesh is filled (CreateMeshPartAsync yields, so it runs in its own thread).
local function createPart(s: Skin)
	local ok, result = pcall(function(): any
		return AssetService:CreateMeshPartAsync(Content.fromObject(s.editable), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
		})
	end)
	if s.stage == "dead" or skin ~= s then
		if ok and typeof(result) == "Instance" then
			result:Destroy()
		end
		return
	end
	if not ok or result == nil then
		failKey(s.key, if ok then "CreateMeshPartAsync returned nil" else tostring(result))
		return
	end
	local part = result :: MeshPart
	local setupOk, setupErr = pcall(function()
		part.Name = "SD_JellySkin_" .. s.key
		part.Anchored = true
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = paletteColor(s.layout.meshColor)
		-- Reading: the skin casts the shadow of a swapped-in piece (its real parts stop casting one).
		part.CastShadow = true
		if cosmeticRegistered() then
			part.CollisionGroup = COSMETIC_GROUP
		end
		part.CFrame = s.place.frame * CFrame.new(s.center)
		part.Parent = clientFx()
	end)
	if not setupOk then
		part:Destroy()
		failKey(s.key, tostring(setupErr))
		return
	end
	s.part = part
	s.sim = JellySkin.newSim(s.layout, newIO(s), { always = s.always })
	s.stage = "ready"
	if s.always then
		for index, real in s.place.reals do
			if not real.mismatch then
				showPiece(s, index)
			end
		end
	end
end

-- Fills the mesh for at most buildMsPerFrame; returns when the time is up or the stage is done.
local function buildStep(s: Skin)
	local layout = s.layout
	local editable = s.editable
	local deadline = os.clock() + RIPPLE.buildMsPerFrame / 1000
	local n = 0
	local function timeUp(): boolean
		n += 1
		return n % BUILD_CLOCK_EVERY == 0 and os.clock() >= deadline
	end
	if s.stage == "vertices" then
		local i = s.cursor
		while i <= layout.vertexCount do
			s.vertexIds[i] = editable:AddVertex(restPosition(layout, i) - s.center)
			s.normalIds[i] = editable:AddNormal(restNormal(layout, i))
			i += 1
			if timeUp() then
				s.cursor = i
				return
			end
		end
		s.stage = "triangles"
		s.cursor = 1
		local colors = layout.triColors
		if colors then
			for _, token in colors do
				if s.colorIds[token] == nil then
					s.colorIds[token] = editable:AddColor(paletteColor(token), 1)
				end
			end
		end
	end
	if s.stage == "triangles" then
		local tris = layout.tris
		local colors = layout.triColors
		local k = s.cursor
		while k <= layout.triangleCount do
			local a, b, c = tris[3 * k - 2], tris[3 * k - 1], tris[3 * k]
			local face = editable:AddTriangle(s.vertexIds[a], s.vertexIds[b], s.vertexIds[c])
			editable:SetFaceNormals(face, { s.normalIds[a], s.normalIds[b], s.normalIds[c] })
			if colors then
				local id = s.colorIds[colors[k]]
				editable:SetFaceColors(face, { id, id, id })
			end
			k += 1
			if timeUp() then
				s.cursor = k
				return
			end
		end
		s.stage = "collapse"
		s.cursor = 1
	end
	if s.stage == "collapse" then
		-- "onHit": every piece starts collapsed (added at rest first, so no triangle is ever made degenerate).
		local i = s.cursor
		while i <= layout.vertexCount do
			local index = s.pieceOf[i]
			if index > 0 and not s.always then
				editable:SetPosition(s.vertexIds[i], layout.pieces[index].collapse - s.center)
			end
			i += 1
			if timeUp() then
				s.cursor = i
				return
			end
		end
		if s.always then
			-- "always": pieces not streamed in (or mismatched) stay collapsed until they are bound.
			for _, piece in layout.pieces do
				local real = s.place.reals[piece.index]
				if piece.skinned and (real == nil or real.mismatch) then
					for v = piece.first, piece.first + piece.count - 1 do
						editable:SetPosition(s.vertexIds[v], piece.collapse - s.center)
					end
				end
			end
		end
		s.stage = "creating"
		task.spawn(createPart, s)
	end
end

local function stepSkin(s: Skin, dt: number, now: number, isReduced: boolean)
	if s.stage == "vertices" or s.stage == "triangles" or s.stage == "collapse" then
		local ok, err = pcall(function(): any
			buildStep(s)
			return nil
		end)
		if not ok then
			if not s.triedLow then
				-- §18.3.4: retry once at Low (a size limit), then path B.
				local place = s.place
				destroySkin()
				local retryOk, retry = pcall(function(): Skin
					return newSkin(s.key, place, "Low")
				end)
				if retryOk and MeshQuota.tryAcquire(s.key) then
					retry.triedLow = true
					skin = retry
					log:info(`jelly ripple {s.key}: rebuilding at Low ({tostring(err)})`)
				else
					if retryOk then
						pcall(function()
							retry.editable:Destroy()
						end)
					end
					failKey(s.key, tostring(err))
				end
			else
				failKey(s.key, tostring(err))
			end
		end
		return
	end
	local sim = s.sim
	if s.stage ~= "ready" or sim == nil then
		return
	end
	local ok, err = pcall(function()
		sim:step(dt, now, isReduced)
	end)
	if not ok then
		failKey(s.key, tostring(err))
	end
end

-- Places ----------------------------------------------------------------------------------------------------------

-- Ends a place: its skin, its wobbles, every hidden part shown again.
local function endPlace(place: Place)
	local s = skin
	if s and s.place == place then
		destroySkin()
	end
	destroyWobblersOf(place, nil)
	for _, real in place.reals do
		setHidden(real, false)
	end
	table.clear(place.reals)
	if arena == place then
		arena = nil
	end
	if backstop == place then
		backstop = nil
	end
end

-- A piece that streamed out (or was replaced): its skin collapses without a write to the gone parts, its wobble goes.
local function unbindReal(place: Place, index: number)
	local real = place.reals[index]
	if real == nil then
		return
	end
	place.reals[index] = nil
	local s = skin
	if s and s.place == place then
		local sim = s.sim
		if sim then
			sim:dropPiece(index)
		end
		if s.shown[index] then
			s.shown[index] = false
			if s.stage == "ready" then
				pcall(writePieceCollapsed, s, s.layout.pieces[index])
			end
		end
	end
	setHidden(real, false)
	destroyWobblersOf(place, index)
end

-- The arena view's frame, slot, match and arena id (nil while the view is not positioned or has ended; the arena id is
-- nil when the view names none).
local function arenaWanted(view: any): (CFrame?, number?, string?, string?)
	if type(view) ~= "table" or view.positioned ~= true or ENDED_PHASES[view.phase] then
		return nil, nil, nil, nil
	end
	local a = view.arena
	if type(a) ~= "table" or type(a.pads) ~= "table" or type(a.floorY) ~= "number" or type(a.slot) ~= "number" then
		return nil, nil, nil, nil
	end
	local padA, padB = a.pads.PadA, a.pads.PadB
	if typeof(padA) ~= "CFrame" or typeof(padB) ~= "CFrame" then
		return nil, nil, nil, nil
	end
	local arenaId = if type(a.arenaId) == "string" then a.arenaId else nil
	return JellySkin.arenaFrame(padA, padB, a.floorY), a.slot, view.matchId, arenaId
end

local function coverFolder(slot: number): Instance?
	local container = Workspace:FindFirstChild(ARENA_CONTAINER)
	local clone = if container then container:FindFirstChild(ARENA_PREFIX .. slot) else nil
	local geometry = if clone then clone:FindFirstChild("Geometry") else nil
	return if geometry then geometry:FindFirstChild("Cover") else nil
end

local function backstopPart(): BasePart?
	local lobby = Workspace:FindFirstChild(LOBBY_ROOT)
	local range = if lobby then lobby:FindFirstChild(WorldLayout.PracticeRange.model) else nil
	local part = if range then range:FindFirstChild(BACKSTOP_NAME) else nil
	return if part and part:IsA("BasePart") then part else nil
end

-- Binds the arena pieces that streamed in and drops the ones that went.
local function pollArenaPieces(place: Place)
	local cover = if place.slot then coverFolder(place.slot) else nil
	for _, piece in place.pieces do
		local model = if cover then cover:FindFirstChild(COVER_PREFIX .. piece.name) else nil
		local body = if model then (model :: Instance):FindFirstChild(BODY_NAME) else nil
		local current: Real? = place.reals[piece.index]
		local present = model ~= nil and body ~= nil and body:IsA("BasePart")
		if current and (not present or current.container ~= model or current.body ~= body) then
			unbindReal(place, piece.index)
			current = nil
		end
		if current == nil and present then
			local real = bindReal(place, piece, model :: Instance, body :: BasePart)
			place.reals[piece.index] = real
			local s = skin
			if s and s.place == place and s.always and s.stage == "ready" and not real.mismatch then
				showPiece(s, piece.index)
			end
		end
	end
end

local function pollBackstopPiece(place: Place)
	local part = backstopPart()
	local piece = place.pieces[1]
	local current: Real? = place.reals[1]
	if current and current.body ~= part then
		unbindReal(place, 1)
		current = nil
	end
	if current == nil and part ~= nil then
		place.reals[1] = bindReal(place, piece, part, part)
		local s = skin
		if s and s.place == place and s.always and s.stage == "ready" and not place.reals[1].mismatch then
			showPiece(s, 1)
		end
	end
end

-- Which places and which skin are wanted now (see the header); called on every poll and on DuelChanged.
local function reconcile()
	-- Arena.
	local frame, slot, matchId, arenaId = arenaWanted(duelView)
	local current = arena
	if current and (frame == nil or current.matchId ~= matchId or current.slot ~= slot) then
		endPlace(current)
		current = nil
	end
	if current == nil and frame ~= nil then
		current = {
			key = KEY_ARENA,
			frame = frame,
			pieces = JellySkin.arenaPiecesFor(arenaId),
			reals = {},
			matchId = matchId,
			slot = slot,
		}
		arena = current
	end
	if current then
		pollArenaPieces(current)
	end
	-- Backstop: only while there is no duel view (released at Preparing, before the arena asks for its slot).
	local camera = Workspace.CurrentCamera
	local distance = if camera
		then (camera.CFrame.Position - JellySkin.backstopFrame().Position).Magnitude
		else math.huge
	local s = skin
	local holding = s ~= nil and s.key == KEY_BACKSTOP
	local near = distance <= (if holding then BACKSTOP.destroyStuds else BACKSTOP.createStuds)
	local place = backstop
	if duelView ~= nil then
		if place then
			endPlace(place)
			place = nil
		end
	else
		if place == nil then
			place = {
				key = KEY_BACKSTOP,
				frame = JellySkin.backstopFrame(),
				pieces = { JellySkin.backstopPiece() },
				reals = {},
			}
			backstop = place
		end
		pollBackstopPiece(place :: Place)
	end
	-- The skin.
	s = skin
	if s then
		local keep = (s.key == KEY_ARENA and s.place == arena)
			or (s.key == KEY_BACKSTOP and s.place == backstop and near and duelView == nil)
		if not keep then
			destroySkin()
		end
	end
	if skin == nil then
		if arena and failed[KEY_ARENA] == nil and #arena.pieces > 0 then
			startSkin(KEY_ARENA, arena :: Place)
		elseif backstop and duelView == nil and near and failed[KEY_BACKSTOP] == nil then
			local b = backstop :: Place
			if b.reals[1] ~= nil then
				startSkin(KEY_BACKSTOP, b)
			end
		end
	end
end

-- Hits ------------------------------------------------------------------------------------------------------------

-- Path A on a face of a piece: "A" (rippling), "fixed" (a face that never moves: one ring) or "unavailable".
local function tryPathA(
	place: Place,
	piece: JellySkin.Piece,
	faceName: string,
	u: number,
	v: number,
	isRush: boolean,
	radius: number,
	now: number
): string
	local s = skin
	local real = place.reals[piece.index]
	if s == nil or s.place ~= place or s.stage ~= "ready" or s.sim == nil or real == nil or real.mismatch then
		return "unavailable"
	end
	if not s.always then
		-- Camera guard: a piece on the camera's line keeps its real parts (path B), so the camera still stops at it.
		local focus, eye = cameraLine()
		if focus ~= nil and eye ~= nil and holdsCamera(real, focus, eye) then
			if s.shown[piece.index] then
				dropShown(s, piece.index)
			else
				stats.cameraGuards += 1
			end
			return "unavailable"
		end
	end
	local map = s.layout.faceOf[piece.index]
	local faceIndex = if map then map[faceName] else nil
	if faceIndex == nil then
		return "unavailable"
	end
	local face = s.layout.faces[faceIndex]
	if not face.moves then
		return "fixed"
	end
	local isReduced = reduced()
	local speed, reach = JellySkin.impulseFor(radius, isRush, isReduced)
	local jiggle = JellySkin.jiggleAmount(piece.kind, radius, isRush, isReduced)
	local seconds = if isRush then RIPPLE.rushFaceSeconds else RIPPLE.faceSeconds
	local sim = s.sim :: JellySkin.Sim
	local ok, err = pcall(function()
		sim:impulse(faceIndex, u, v, speed, reach, now, seconds, jiggle)
	end)
	if not ok then
		failKey(s.key, tostring(err))
		return "unavailable"
	end
	return "A"
end

-- One surface response at a face or piece hit in a place (layout space p and n; the world point and normal for the
-- ring and the sound). Returns what was shown.
local function respond(
	place: Place,
	class: string, -- a JellySkin.HitClass
	piece: JellySkin.Piece?,
	faceName: string?,
	u: number,
	v: number,
	localNormal: Vector3,
	worldPoint: Vector3,
	worldNormal: Vector3,
	isRush: boolean,
	radius: number,
	priority: number,
	now: number
): Outcome
	if class == "floor" then
		floorRings(worldPoint, place.frame.UpVector, now)
		return "ring"
	end
	if piece == nil or class == "edge" or class == "other" then
		coverRing(worldPoint, worldNormal)
		return "ring"
	end
	if class == "face" and faceName ~= nil then
		local result = tryPathA(place, piece, faceName, u, v, isRush, radius, now)
		if result == "A" then
			stats.pathA += 1
			queueWobbleSound(worldPoint, radius, priority, now)
			return "A"
		elseif result == "fixed" or piece.kind == "backstop" then
			coverRing(worldPoint, worldNormal)
			return "ring"
		end
	end
	if wobblePiece(place, piece, localNormal, isRush, radius, now) then
		stats.pathB += 1
		coverRing(worldPoint, worldNormal)
		queueWobbleSound(worldPoint, radius, priority, now)
		return "B"
	end
	coverRing(worldPoint, worldNormal)
	return "ring"
end

local function inArena(p: Vector3): boolean
	local layout = WorldLayout.Arena
	return math.abs(p.X) <= layout.halfX + ARENA_MARGIN
		and math.abs(p.Z) <= layout.halfZ + ARENA_MARGIN
		and p.Y >= -ARENA_MARGIN
		and p.Y <= ARENA_TOP
end

-- A "geometry" impact with a normal (see the header).
local function geometryHit(position: Vector3, normal: Vector3, info: ThrowInfo?, now: number): Outcome
	local radius = if info then info.radius else DEFAULT_RADIUS
	local priority = if info and info.practice and not info.own then OTHERS_PRIORITY else OWN_PRIORITY
	local place = arena
	if place then
		local p = place.frame:PointToObjectSpace(position)
		if inArena(p) then
			local n = place.frame:VectorToObjectSpace(normal)
			local class, piece, faceName, u, v = JellySkin.classify(place.pieces, p, n)
			return respond(place, class, piece, faceName, u, v, n, position, normal, false, radius, priority, now)
		end
	end
	local range = backstop
	if range then
		local p = range.frame:PointToObjectSpace(position)
		local piece = JellySkin.findPiece(range.pieces, p)
		if piece then
			local n = range.frame:VectorToObjectSpace(normal)
			local faceName, u, v = JellySkin.hitFace(piece, p, n)
			local class: JellySkin.HitClass = if faceName then "face" else "edge"
			return respond(range, class, piece, faceName, u, v, n, position, normal, false, radius, priority, now)
		end
	end
	if normal.Magnitude > 1e-6 and normal.Unit.Y > RIPPLE.floorNormalMinY then
		local at = if info and info.practice
			then Vector3.new(position.X, PracticeTargets.FLOOR_Y, position.Z)
			else position
		floorRings(at, Vector3.yAxis, now)
		return "ring"
	end
	return "none"
end

-- A Dragon Rush lane that ended on cover at E (no normal): the face about the lane radius ahead of E.
local function rushHit(lane: LaneInfo, endpoint: Vector3, now: number): Outcome
	local place = arena
	if place == nil then
		return "none"
	end
	local origin = place.frame:PointToObjectSpace(endpoint)
	local dir = place.frame:VectorToObjectSpace(lane.dir)
	local piece, faceName, u, v, distance =
		JellySkin.rayPiece(place.pieces, origin, dir, lane.radius + RIPPLE.rushProbeMarginStuds)
	if piece == nil or faceName == nil then
		return "none"
	end
	local localNormal = JellySkin.faceNormalOf(faceName)
	local worldPoint = place.frame:PointToWorldSpace(origin + dir.Unit * distance)
	local worldNormal = place.frame:VectorToWorldSpace(localNormal)
	local class: JellySkin.HitClass = if piece.kind == "gumdrop" then "round" else "face"
	return respond(
		place,
		class,
		piece,
		faceName,
		u,
		v,
		localNormal,
		worldPoint,
		worldNormal,
		true,
		lane.radius,
		OWN_PRIORITY,
		now
	)
end

-- Remote events ---------------------------------------------------------------------------------------------------

local function onThrowStarted(raw: unknown)
	local payload = ThrowController.parseThrowStarted(raw)
	if payload == nil then
		return
	end
	local t = payload :: any
	throws[payload.projId] = {
		radius = if payload.radius > 0 then payload.radius else DEFAULT_RADIUS,
		practice = t.kind == "practice",
		own = payload.throwerId == localUserId(),
		untilAt = payload.releaseAt + MAX_LIFETIME + SLACK_SECONDS,
	}
end

local function onUltimateEvent(raw: unknown)
	local event = ThrowController.parseUltimateEvent(raw)
	if event == nil or event.phase ~= "release" or type(event.projId) ~= "number" then
		return
	end
	if event.dir.Magnitude < 1e-6 or not (event.radius > 0) then
		return
	end
	lanes[event.projId :: number] = {
		dir = event.dir,
		radius = event.radius,
		untilAt = event.telegraphEndsAt + MAX_LIFETIME + SLACK_SECONDS,
	}
end

-- One impact (also a Studio poke). Returns what was shown.
local function handleImpact(impact: any, now: number): Outcome
	if impact.kind ~= "geometry" then
		return "none"
	end
	stats.impacts += 1
	local info = throws[impact.projId]
	throws[impact.projId] = nil
	local normal = impact.normal
	if typeof(normal) == "Vector3" and (normal :: Vector3).Magnitude > 1e-6 then
		return geometryHit(impact.position, normal :: Vector3, info, now)
	end
	local lane = lanes[impact.projId]
	lanes[impact.projId] = nil
	if lane then
		return rushHit(lane, impact.position, now)
	end
	return "none"
end

local function onThrowImpact(raw: unknown)
	local impact = ThrowController.parseImpact(raw)
	if impact == nil then
		return
	end
	if impact.kind ~= "geometry" then
		-- Any impact ends a throw; a Dragon Rush lane flies on through players and ends with expired or fizzle.
		throws[impact.projId] = nil
		if impact.kind == "expired" or impact.kind == "fizzle" then
			lanes[impact.projId] = nil
		end
		return
	end
	local ok, err = pcall(handleImpact, impact, os.clock())
	if not ok then
		log:warn("an impact response failed:", err)
	end
end

local function onDuelChanged(view: any, _old: any)
	duelView = view
	local ok, err = pcall(function(): any
		reconcile()
		return nil
	end)
	if not ok then
		log:warn("the duel view change failed:", err)
	end
end

-- Frame step ------------------------------------------------------------------------------------------------------

local function step(dt: number, now: number): boolean
	if now >= pollAt then
		pollAt = now + RIPPLE.presencePollSeconds
		local ok, err = pcall(function(): any
			reconcile()
			return nil
		end)
		if not ok then
			log:warn("presence poll failed:", err)
		end
	end
	local isReduced = reduced()
	local s = skin
	if s then
		stepSkin(s, dt, now, isReduced)
	end
	local current = skin
	if current then
		local ok, err = pcall(function(): any
			guardCamera(current)
			return nil
		end)
		if not ok then
			failKey(current.key, tostring(err)) -- like any error while the skin runs: real parts back, path B
		end
	end
	stepWobblers(dt)
	runPending(now)
	local server = serverNow()
	for projId, info in throws do
		if server > info.untilAt then
			throws[projId] = nil
		end
	end
	for projId, lane in lanes do
		if server > lane.untilAt then
			lanes[projId] = nil
		end
	end
	return true
end

-- Public ----------------------------------------------------------------------------------------------------------

-- One slab of a segment-versus-box test along one box axis: the segment p + d·t (t in [tMin, tMax]) narrowed to where
-- that axis lies within [-half, half]. An empty range comes back as tMin > tMax.
local function slab(p: number, d: number, half: number, tMin: number, tMax: number): (number, number)
	if math.abs(d) < 1e-9 then
		if p < -half or p > half then
			return 1, 0
		end
		return tMin, tMax
	end
	local t1, t2 = (-half - p) / d, (half - p) / d
	if t1 > t2 then
		t1, t2 = t2, t1
	end
	return math.max(tMin, t1), math.min(tMax, t2)
end

-- Camera guard (pure): whether a box (a piece's Body, widened by CAMERA_GUARD_PAD on every side) touches the camera's
-- line, from its focus to CAMERA_GUARD_BEYOND studs past the camera. That is where the default camera stops in front
-- of a wall (or, with the wall hidden, looks through it). False when the camera sits on its focus (first person).
function JellyRippleController.blocksCamera(focus: Vector3, eye: Vector3, boxCFrame: CFrame, boxSize: Vector3): boolean
	local line = eye - focus
	local length = line.Magnitude
	if length < FIRST_PERSON_STUDS then
		return false
	end
	local finish = eye + line / length * CAMERA_GUARD_BEYOND
	local p = boxCFrame:PointToObjectSpace(focus)
	local d = boxCFrame:PointToObjectSpace(finish) - p
	local half = boxSize / 2 + Vector3.one * CAMERA_GUARD_PAD
	local tMin, tMax = slab(p.X, d.X, half.X, 0, 1)
	tMin, tMax = slab(p.Y, d.Y, half.Y, tMin, tMax)
	tMin, tMax = slab(p.Z, d.Z, half.Z, tMin, tMax)
	return tMin <= tMax
end

-- The visible surface's offset (studs, along `normal`) at a world point: a rippling face's height there with its
-- piece's jiggle (path A) or a wobbling piece's shift (path B); 0 when nothing moves there. Splats add it to their
-- lift (§18.4.1).
function JellyRippleController.offsetAt(worldPoint: Vector3, normal: Vector3): number
	local s = skin
	local sim = if s and s.stage == "ready" then s.sim else nil
	if sim and (sim:activeCount() > 0 or sim:jiggleCount() > 0 or sim:restingCount() > 0) then
		local frame = (s :: Skin).place.frame
		local p = frame:PointToObjectSpace(worldPoint)
		local n = frame:VectorToObjectSpace(normal)
		local face, u, v = JellySkin.findFace((s :: Skin).layout, p, n)
		if face and (sim:isActive(face.index) or sim:jiggleMap(face.piece) ~= nil) then
			return sim:offset(face.index, u, v)
		end
	end
	for _, wobbler in wobblers do
		if wobbler.active then
			local q = wobbler.boxFrame:PointToObjectSpace(worldPoint)
			local half = wobbler.boxSize / 2 + Vector3.one * JellySkin.PIECE_TOLERANCE
			if math.abs(q.X) <= half.X and math.abs(q.Y) <= half.Y and math.abs(q.Z) <= half.Z then
				local p = wobbler.pivot:PointToObjectSpace(worldPoint)
				local n = wobbler.pivot:VectorToObjectSpace(normal)
				return JellySkin.surfaceOffset(Vector3.zero, wobbler.wobble:scale(), p, n)
			end
		end
	end
	return 0
end

-- True while the skin stands in for this real part (it is hidden on this screen only).
function JellyRippleController.isHidden(part: BasePart): boolean
	return hiddenParts[part] == true
end

-- The leak-check reset (like VfxController.clear()), the same as the duel view ending: the skin and its quota slot go,
-- every hidden part shows again, every wobble rests and loses its meshes, pending rings and sounds are dropped and the
-- rings this module started stop. The places are found again on the next poll.
function JellyRippleController.clear()
	destroySkin()
	local a, b = arena, backstop
	if a then
		endPlace(a)
	end
	if b then
		endPlace(b)
	end
	for _, wobbler in table.clone(wobblers) do
		destroyWobbler(wobbler)
	end
	table.clear(pendingSounds)
	table.clear(pendingRings)
	for ring in table.clone(liveRings) do
		pcall(function()
			(ring :: any):stop()
		end)
	end
	table.clear(liveRings)
	table.clear(throws)
	table.clear(lanes)
	pollAt = -math.huge
end

-- Studio counters (DebugHooks "counts", juice check 12).
function JellyRippleController.counts(): { [string]: any }
	local s = skin
	local sim = if s then s.sim else nil
	local hidden = 0
	for _ in hiddenParts do
		hidden += 1
	end
	local wobblerCount = 0
	for _ in wobblers do
		wobblerCount += 1
	end
	local rings = 0
	for _ in liveRings do
		rings += 1
	end
	return {
		skin = if s then s.key else nil,
		stage = if s then s.stage else nil,
		quality = if s then s.quality else nil,
		activeFaces = if sim then sim:activeCount() else 0,
		jiggling = if sim then sim:jiggleCount() else 0,
		swapped = if sim then sim:swappedCount() else 0,
		hiddenParts = hidden,
		wobbling = activeWobblerCount(),
		wobblers = wobblerCount,
		rings = rings,
		pendingRings = #pendingRings,
		pendingSounds = #pendingSounds,
		meshQuota = MeshQuota.count(),
		failures = table.clone(failed),
		forced = forced,
		arena = arena ~= nil,
		backstop = backstop ~= nil,
		stats = table.clone(stats),
	}
end

-- Studio (DebugHooks "ripplePathB", S12): on = path B everywhere (a skin that exists goes, with one log line per key
-- as it is asked for); off = path A again (this session's failures are forgotten; the next poll rebuilds).
function JellyRippleController.debugForcePathB(on: boolean): { [string]: any }
	forced = on == true
	if forced then
		local s = skin
		if s then
			failKey(s.key, "forced by a debug flag")
		end
	else
		table.clear(failed)
	end
	pollAt = -math.huge
	return { ok = true, forced = forced }
end

-- Studio (DebugHooks "ripplePoke", S7, S10): one hit on a cover piece's face at (u, v) with no throw, as a radius-1.0
-- throw would land there. `pieceName` is a WorldLayout cover name ("B_Wall1") or "Backstop"; `face` a face name ("+Z")
-- or its number in JellySkin.BOX_FACES. Returns { ok = true, path = "A" | "B" | "ring" | "none" }, or false and why.
function JellyRippleController.debugPoke(pieceName: string, face: string | number, u: number, v: number): (any, string?)
	local place = if pieceName == "Backstop" then backstop else arena
	if place == nil then
		return false, if pieceName == "Backstop" then "the backstop is not here" else "no duel arena"
	end
	local piece: JellySkin.Piece? = nil
	for _, candidate in (place :: Place).pieces do
		if candidate.name == pieceName then
			piece = candidate
		end
	end
	if piece == nil then
		return false, `unknown piece {pieceName}`
	end
	local faceName = if type(face) == "number" then JellySkin.BOX_FACES[face] else face
	if type(faceName) ~= "string" or table.find(JellySkin.BOX_FACES, faceName) == nil then
		return false, `unknown face {tostring(face)}`
	end
	local center, normal, uAxis, vAxis = JellySkin.boxFaceFrame(piece :: JellySkin.Piece, faceName)
	local frame = (place :: Place).frame
	local point = frame:PointToWorldSpace(center + uAxis * u + vAxis * v)
	local outcome = geometryHit(point, frame:VectorToWorldSpace(normal), nil, os.clock())
	return { ok = true, path = outcome }, nil
end

-- Lifecycle

function JellyRippleController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(Scheduler.add(step, "render"))
	c:add(NetController.on("ThrowStarted", onThrowStarted))
	c:add(NetController.on("ThrowImpact", onThrowImpact))
	c:add(NetController.on("UltimateEvent", onUltimateEvent))
	c:add(StateController.DuelChanged:connect(onDuelChanged))
	c:add(function()
		JellyRippleController.clear()
	end)
	duelView = StateController.duel()
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function JellyRippleController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return JellyRippleController
