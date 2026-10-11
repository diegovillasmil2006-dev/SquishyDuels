--!strict
-- GiantPadController (client only). DESIGN §17.6.1. Presentation only: the giant squishy pads (Jelly, Marshmallow,
-- Royal) dent under every character standing on them and rise back with a slow wave. The server never deforms
-- anything; collision is the invisible `Collision` box; rewards never depend on any of this.
--
-- Pads: every streamed-in Model tagged SD_GiantPad (attribute PadKey) with its geometry from WorldLayout.GiantPads
-- (centre, footprint, corner radius, restTop, collisionTop, sinkDepth, look, tile grid). The pad frame is the floor
-- point under its centre, axis-aligned (the pad is square, so its yaw never matters).
-- Dent model: Anim/PadDent with Config.Anim.giantPad and the pad's sinkDepth, for both paths.
--
-- Path B (always built at edit time, the fallback): `Body` holds a grid of quilted tiles (Parts with a Sphere
-- SpecialMesh, Size = WorldLayout tileSize, centred on the tilesPerSide x tilesPerSide grid at tileSpacing). Each
-- written tile gets mesh.Offset = (0, h, 0) and mesh.Scale = (1/sqrt(s), s, 1/sqrt(s)) with
-- s = 1 - tileSquash * clamp(-h / sinkDepth, tileSquashMin, 1). Parts never move (§9.3). `Face` stays still.
--
-- Path A (preferred; feasibility passed 2026-10-05, needs M15 in live servers): when the pad has streamed in and the
-- camera is within createStuds (120), one EditableMesh per pad (at most maxMeshes = 3, created one at a time) from
-- the pure Anim/PadMesh layout, with explicit per-vertex normals (AddNormal + SetFaceNormals); a MeshPart from
-- AssetService:CreateMeshPartAsync(Content.fromObject(mesh)) in Workspace.SD_ClientFx (Anchored, no collision,
-- query or touch, SD_Cosmetic when registered, SmoothPlastic, the pad's body colour and transparency); then `Body` is
-- hidden on this client only (its parts' Transparency = 1, restored if the mesh goes away), except its accent parts
-- (attribute SD_PadAccent: the Marshmallow's band, the Royal Cushion's tuft tile), which stay over the one-colour
-- mesh; an accent tile follows the mesh height under it (plus ACCENT_LIFT, so it shows as a button). Mesh space is
-- centred on the rest bounding box (Y from -restTop/2), so the MeshPart sits at the pad frame + restTop/2. Top-grid
-- vertices move with SetPosition (rest + h, never accumulated) and their normals, and their neighbours', are
-- recomputed (PadMesh.topNormal) and written with SetNormal in the same pass. Any failure or error while creating
-- (nil included, pcall + nil check), Config.Anim.giantPad.pathA = false, or Config.Debug.forcePadPathB /
-- debugForceFailure(true), switches THAT pad (by pad key) to path B for the session with one log line
-- "giant pad <key>: path B (<reason>)"; the failure outlives stream-out, so there is no retry when the pad streams
-- back in. The MeshPart and EditableMesh are destroyed only on stream-out (or a quality rebuild); beyond
-- simulateStuds the mesh is kept and not stepped.
--
-- Per frame (Scheduler "render" phase):
--   * Contacts: every player's character whose HumanoidRootPart is over the pad's rounded footprint and 0..contactHeight
--     studs above its collision top; the contact point is the midpoint of LeftFoot/RightFoot (R15), else the root's
--     X/Z; at most maxContacts per pad, nearest the camera first. A changed SD_SqueezeAt on a character adds the
--     squeezeDip for squeezeDipSeconds (the first value seen never does).
--   * Culling: a pad is stepped only within simulateStuds (80) of the camera and while its bounding sphere is on
--     screen; otherwise it keeps its last shape, and coming back on screen with no contacts snaps it to rest in one
--     write. Only pads with contacts or still moving are candidates, and at most maxSimulated (2) of them, nearest the
--     camera, step in a frame; the others hold their shape until they get a slot.
--   * Write budget, in vertex writes (one top vertex's height: its SetPosition plus the SetNormal refreshes it
--     causes; path B: one tile): a pad whose last step wrote more than writesPerPad (400), or more than what is left
--     of writesPerClient (600) this frame, steps every other frame (with the two frames' dt, clamped by PadDent).
--     Snaps to rest come after the steps and are charged to the same budget: a snap runs when it fits what is left,
--     or when nothing was written yet this frame; otherwise the pad holds its shape and snaps on a later frame.
--   * Quality: High (gridHigh) unless the screen is the compact layout (Config.UI.Breakpoints) or the device is
--     touch-only; and once per session, if the average frame time stays above downgradeFrameMs for downgradeSeconds
--     while a pad is being stepped, every mesh is rebuilt at Low (gridLow).
--   * ReducedMotion (GuiService.ReducedMotionEnabled): no ripple and no overshoot; the dent still follows the feet.
-- Feel pass (DESIGN §18.5.1 A5, §18.3.4):
--   * Landing thump: a character's root that falls at <= giantPad.landing.minFallSpeed (18 studs/s) and then slows to
--     >= landedVy (-2) adds landingExtra(vy) = clamp(perSpeed · |vy|, min, max) studs (0.04-0.14; × 0.5 under
--     ReducedMotion) for landing.seconds (0.12 s) through the same per-character pulse as the squeeze dip (the larger
--     of two running pulses wins); PadDent's clamp already follows a contact's extra. No pad footstep sound (§17.14).
--   * Shared mesh budget: before creating an EditableMesh a pad takes a slot of Anim/MeshQuota (key "pad:<key>"; at
--     most Config.Vfx.Budgets.editableMeshes per client, shared with the jelly ripple's skin) and gives it back when its
--     mesh goes; a refused slot is a path A failure like any other (path B for that pad this session, one log line;
--     pathABlocker). The High / Low rule is Anim/MeshQuality (forCamera), shared with the ripple; the once-per-session
--     slow-frame downgrade stays here.

-- Services

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
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
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local MeshQuality = require(Client.Anim.MeshQuality)
local MeshQuota = require(Client.Anim.MeshQuota)
local PadDent = require(Client.Anim.PadDent)
local PadMesh = require(Client.Anim.PadMesh)
local Scheduler = require(Client.Anim.Scheduler)

-- Types

export type Quality = "High" | "Low"

-- A Util/Cleanup as stored in records (its generic add<T>() trips the exact record comparison of the type checker).
type Trove = {
	add: (self: any, item: any) -> any,
	clean: (self: any) -> (),
}

type MeshState = "none" | "creating" | "ready"

-- An accent tile that follows the mesh in path A: its SpecialMesh and the top-grid vertex under it.
type AccentFollower = {
	mesh: SpecialMesh,
	index: number,
}

type PathA = {
	editable: any, -- EditableMesh
	part: MeshPart,
	layout: PadMesh.Layout,
	dent: PadDent.Dent,
	vertexIds: { number },
	normalIds: { number },
	centerY: number,
	quality: Quality,
	-- Reused by every write (no per-frame tables): normalStamp[i] == stampFrame marks top vertex i for a normal
	-- refresh this write; normalList holds those indices.
	normalStamp: { number },
	normalList: { number },
	stampFrame: number,
	accents: { AccentFollower },
}

-- An accent tile of Body (SD_PadAccent with a tile mesh), in pad space.
type AccentTile = {
	mesh: SpecialMesh,
	x: number,
	z: number,
}

type Pad = {
	key: string,
	spec: any, -- WorldLayout GiantPad
	model: Model,
	frame: CFrame,
	center: Vector3, -- bounding sphere centre
	sphereRadius: number,
	cleanup: Trove,
	removed: boolean,
	-- path B
	tileMeshes: { [number]: { SpecialMesh } },
	tileDent: PadDent.Dent,
	bodyParts: { BasePart }, -- hidden in path A (accent parts are not listed)
	bodyTransparency: { [BasePart]: number },
	bodyHidden: boolean,
	accentTiles: { AccentTile },
	-- path A
	pathAFailed: boolean,
	meshState: MeshState,
	pathA: PathA?,
	-- simulation
	contacts: { PadDent.Contact },
	distance: number,
	culled: boolean, -- not stepped last frame because out of range or off screen
	needsSnap: boolean, -- back on screen with no contacts: snaps to rest once the write budget allows
	skip: boolean,
	pendingDt: number,
	lastWrites: number,
}

type Body = {
	character: Model,
	root: BasePart,
	x: number, -- contact point (world X/Z)
	z: number,
	rootY: number,
	extra: number,
	cameraDistance: number,
}

-- Constants

local G = Config.Anim.giantPad
local LANDING = G.landing
local MAX_DT = Config.Anim.Scheduler.maxDt
local TAG_GIANT_PAD = "SD_GiantPad"
local QUOTA_PREFIX = "pad:" -- MeshQuota key of a pad's mesh: "pad:jelly", "pad:marshmallow", "pad:royal"
local QUOTA_REFUSED = "mesh quota full (Config.Vfx.Budgets.editableMeshes)"
local REDUCED_LANDING = 0.5 -- §18.5.1 A5: the landing thump × 0.5 under ReducedMotion
-- Reading: a fall last seen longer ago than this (the pads were all culled meanwhile, so no frame looked at it) is
-- forgotten, so an old fall never thumps a later step onto a pad.
local FALL_STALE_SECONDS = 0.25
local ATTR_PAD_KEY = "PadKey"
local ATTR_SQUEEZE_AT = "SD_SqueezeAt"
local ATTR_PAD_ACCENT = "SD_PadAccent" -- set by the lobby generator on Body parts path A keeps visible
local CLIENT_FX = "SD_ClientFx"
local COSMETIC_GROUP = "SD_Cosmetic"
local BODY_NAME = "Body"
local ROOT_PART = "HumanoidRootPart"
local TILE_SIZE_TOLERANCE = 0.05 -- studs
local TILE_GRID_TOLERANCE = 0.25 -- fraction of the tile spacing
-- Reading (not in DESIGN; a look detail): in path A an accent tile rides this far above the mesh height under it, so
-- the top of its ellipsoid shows over the mesh as a small button (about 1.3 studs wide for a 2 × 1 × 2 tile).
local ACCENT_LIFT = 0.12

-- Module table

local GiantPadController = {}

-- Private

local log = Log.new("GiantPad")
local cleanup: Cleanup.Cleanup? = nil
local pads: { [Model]: Pad } = {}
local quality: Quality = "High"
local qualityChosen = false
local downgraded = false
local creating = false
local forceFailure = false
local slowWindow, slowFrames = 0, 0
local lastSqueezeAt: { [Model]: any } = setmetatable({}, { __mode = "k" }) :: any
local pulseUntil: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local pulseExtra: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- the running pulse's extra dip
local fallPeak: { [Model]: number? } = setmetatable({}, { __mode = "k" }) :: any -- fastest fall (vy) since it began
local fallSeenAt: { [Model]: number? } = setmetatable({}, { __mode = "k" }) :: any -- the last frame that looked at it
-- Pad key -> why path A failed. Kept for the session (a pad that streams out and back in stays on path B).
local failedKeys: { [string]: string } = {}
-- Per-frame character records, reused frame to frame (characterBodies).
local bodyPool: { Body } = {}

local function clientFxFolder(): Instance
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

local function paletteColor(token: string?, fallback: Color3): Color3
	local value = if token then (Palette :: any)[token] else nil
	return if typeof(value) == "Color3" then value else fallback
end

-- Inside the rounded-square footprint (half-size `half`, corner radius `radius`), pad-local X/Z.
local function insideFootprint(x: number, z: number, half: number, radius: number): boolean
	local ax, az = math.abs(x), math.abs(z)
	if ax > half or az > half then
		return false
	end
	local c = half - radius
	if ax <= c or az <= c then
		return true
	end
	local dx, dz = ax - c, az - c
	return dx * dx + dz * dz <= radius * radius
end

-- Picks the session quality once the viewport has a real size (it can read 1 x 1 in the first frames): the shared
-- editable-mesh rule (Anim/MeshQuality: Low on the compact layout or a touch-only device).
local function chooseQuality(camera: Camera)
	if qualityChosen then
		return
	end
	local picked = MeshQuality.forCamera(camera)
	if picked == nil then
		return
	end
	qualityChosen = true
	if picked == "Low" then
		quality = "Low"
	end
end

-- Starts (or extends) a character's extra dip: the squeeze dip or the landing thump. While one runs, the larger extra
-- and the later end win.
local function startPulse(character: Model, extra: number, seconds: number, now: number)
	local untilAt = pulseUntil[character]
	local active = untilAt ~= nil and now < untilAt
	pulseExtra[character] = math.max(if active then pulseExtra[character] or 0 else 0, extra)
	pulseUntil[character] = math.max(if active then untilAt :: number else now, now + seconds)
end

-- Path B ------------------------------------------------------------------------------------------------------------

local function writeTiles(pad: Pad, dent: PadDent.Dent, count: number)
	local sink = pad.spec.sinkDepth
	local squashK = G.pathB.tileSquash
	local squashMin = G.pathB.tileSquashMin
	local h = dent.h
	local written = dent.written
	for k = 1, count do
		local index = written[k]
		local meshes = pad.tileMeshes[index]
		if meshes then
			local height = h[index]
			local squash = 1 - squashK * math.clamp(-height / sink, squashMin, 1)
			local wide = 1 / math.sqrt(squash)
			local offset = Vector3.new(0, height, 0)
			local scale = Vector3.new(wide, squash, wide)
			for _, mesh in meshes do
				mesh.Offset = offset
				mesh.Scale = scale
			end
		end
	end
end

local function resetTiles(pad: Pad)
	local count = pad.tileDent:snapToRest()
	writeTiles(pad, pad.tileDent, count)
	for _, meshes in pad.tileMeshes do
		for _, mesh in meshes do
			mesh.Offset = Vector3.zero
			mesh.Scale = Vector3.one
		end
	end
end

-- The tiles of `Body`: Parts with a Sphere SpecialMesh, of the layout's tile size, on the tile grid.
local function findTiles(pad: Pad, body: Instance)
	local spec = pad.spec
	local n = spec.tilesPerSide
	local spacing = spec.tileSpacing
	local origin = -(n - 1) * spacing / 2
	local found = 0
	for _, descendant in body:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end
		local mesh = descendant:FindFirstChildOfClass("SpecialMesh")
		if mesh == nil or mesh.MeshType ~= Enum.MeshType.Sphere then
			continue
		end
		if (descendant.Size - spec.tileSize).Magnitude > TILE_SIZE_TOLERANCE then
			continue
		end
		local localPosition = pad.frame:PointToObjectSpace(descendant.Position)
		local colF = (localPosition.X - origin) / spacing + 1
		local rowF = (localPosition.Z - origin) / spacing + 1
		local col, row = math.round(colF), math.round(rowF)
		if
			col < 1
			or col > n
			or row < 1
			or row > n
			or math.abs(colF - col) > TILE_GRID_TOLERANCE
			or math.abs(rowF - row) > TILE_GRID_TOLERANCE
		then
			continue
		end
		local index = (row - 1) * n + col
		local list = pad.tileMeshes[index]
		if list == nil then
			list = {}
			pad.tileMeshes[index] = list
		end
		table.insert(list, mesh)
		found += 1
	end
	if found == 0 then
		log:warn(`giant pad {pad.key}: no quilted tiles found in Body; path B shows a still cushion`)
	end
end

local function setBodyHidden(pad: Pad, hidden: boolean)
	if pad.bodyHidden == hidden then
		return
	end
	pad.bodyHidden = hidden
	for _, part in pad.bodyParts do
		if part.Parent ~= nil then
			if hidden then
				part.Transparency = 1
			else
				part.Transparency = pad.bodyTransparency[part] or 0
			end
		end
	end
end

-- Path A ------------------------------------------------------------------------------------------------------------

local function destroyPathA(pad: Pad)
	local pathA = pad.pathA
	pad.pathA = nil
	if pad.meshState == "ready" then
		pad.meshState = "none"
	end
	if pathA then
		pathA.part:Destroy()
		pcall(function()
			pathA.editable:Destroy()
		end)
		MeshQuota.release(QUOTA_PREFIX .. pad.key)
		-- Accent tiles go back to path B's rest look; path B writes them again when they move.
		for _, accent in pathA.accents do
			accent.mesh.Offset = Vector3.zero
			accent.mesh.Scale = Vector3.one
		end
	end
	if not pad.removed then
		setBodyHidden(pad, false)
	end
end

-- Path B for this pad key for the rest of the session, with one log line per key (§17.6.1).
local function failPathA(pad: Pad, reason: string)
	pad.pathAFailed = true
	if failedKeys[pad.key] ~= nil then
		return
	end
	failedKeys[pad.key] = reason
	log:warn(`giant pad {pad.key}: path B ({reason})`)
end

-- Writes the `count` changed top vertices (dent.written) and refreshes the normals of those vertices and of their
-- 4 neighbours, each once, then moves the accent tiles. No table or closure is created per call.
local function writeMesh(pathA: PathA, count: number)
	local layout = pathA.layout
	local dent = pathA.dent
	local editable = pathA.editable
	local h = dent.h
	local written = dent.written
	local px, py, pz = layout.px, layout.py, layout.pz
	local centerY = pathA.centerY
	local n = layout.grid
	local stamp = pathA.normalStamp
	local list = pathA.normalList
	local frame = pathA.stampFrame + 1
	pathA.stampFrame = frame
	local listed = 0
	for k = 1, count do
		local index = written[k]
		editable:SetPosition(pathA.vertexIds[index], Vector3.new(px[index], py[index] + h[index] - centerY, pz[index]))
		local row = (index - 1) // n + 1
		local col = index - (row - 1) * n
		if stamp[index] ~= frame then
			stamp[index] = frame
			listed += 1
			list[listed] = index
		end
		if col > 1 and stamp[index - 1] ~= frame then
			stamp[index - 1] = frame
			listed += 1
			list[listed] = index - 1
		end
		if col < n and stamp[index + 1] ~= frame then
			stamp[index + 1] = frame
			listed += 1
			list[listed] = index + 1
		end
		if row > 1 and stamp[index - n] ~= frame then
			stamp[index - n] = frame
			listed += 1
			list[listed] = index - n
		end
		if row < n and stamp[index + n] ~= frame then
			stamp[index + n] = frame
			listed += 1
			list[listed] = index + n
		end
	end
	for k = 1, listed do
		local index = list[k]
		local nx, ny, nz = PadMesh.topNormal(layout, h, index)
		editable:SetNormal(pathA.normalIds[index], Vector3.new(nx, ny, nz))
	end
	for _, accent in pathA.accents do
		accent.mesh.Offset = Vector3.new(0, h[accent.index] + ACCENT_LIFT, 0)
	end
end

-- The top-grid vertex nearest pad-space (x, z).
local function nearestTopVertex(layout: PadMesh.Layout, x: number, z: number): number
	local best, bestDistance = 1, math.huge
	for index = 1, layout.topCount do
		local dx, dz = layout.px[index] - x, layout.pz[index] - z
		local distance = dx * dx + dz * dz
		if distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

-- Builds the EditableMesh from a PadMesh layout. Returns the mesh and the per-vertex vertex / normal ids.
local function buildEditable(layout: PadMesh.Layout, centerY: number): (any, { number }, { number })
	local editable: any = AssetService:CreateEditableMesh()
	if editable == nil then
		error("CreateEditableMesh returned nil", 0)
	end
	local ok, err = pcall(function(): any
		local vertexIds: { number } = table.create(layout.vertexCount, 0)
		local normalIds: { number } = table.create(layout.vertexCount, 0)
		for index = 1, layout.vertexCount do
			vertexIds[index] =
				editable:AddVertex(Vector3.new(layout.px[index], layout.py[index] - centerY, layout.pz[index]))
			normalIds[index] = editable:AddNormal(Vector3.new(layout.nx[index], layout.ny[index], layout.nz[index]))
		end
		local tris = layout.tris
		for k = 1, layout.triangleCount do
			local a, b, c = tris[3 * k - 2], tris[3 * k - 1], tris[3 * k]
			local face = editable:AddTriangle(vertexIds[a], vertexIds[b], vertexIds[c])
			editable:SetFaceNormals(face, { normalIds[a], normalIds[b], normalIds[c] })
		end
		return { vertexIds, normalIds }
	end)
	if not ok then
		pcall(function()
			editable:Destroy()
		end)
		error(err, 0)
	end
	local ids = err :: any
	return editable, ids[1], ids[2]
end

local function createPathA(pad: Pad)
	-- The switches and the shared mesh quota first (§18.3.4): any blocker is a path A failure (path B this session).
	local blocker = GiantPadController.pathABlocker(pad.key)
	if blocker ~= nil then
		failPathA(pad, blocker)
		return
	end
	local quotaKey = QUOTA_PREFIX .. pad.key
	pad.meshState = "creating"
	creating = true
	local wanted = quality
	local spec = pad.spec
	local centerY = spec.restTop / 2
	local editable: any = nil
	local ok, result = pcall(function(): any
		local layout = PadMesh.build({
			footprint = spec.footprint,
			cornerRadius = spec.cornerRadius,
			restTop = spec.restTop,
			grid = if wanted == "Low" then G.gridLow else G.gridHigh,
			bevel = G.bevel,
			flipWinding = G.flipWinding,
		})
		local vertexIds, normalIds
		editable, vertexIds, normalIds = buildEditable(layout, centerY)
		local part = AssetService:CreateMeshPartAsync(Content.fromObject(editable))
		if part == nil then
			error("CreateMeshPartAsync returned nil", 0)
		end
		return { layout = layout, vertexIds = vertexIds, normalIds = normalIds, part = part }
	end)
	creating = false
	if not ok then
		if editable ~= nil then
			pcall(function()
				editable:Destroy()
			end)
		end
		MeshQuota.release(quotaKey)
		pad.meshState = "none"
		failPathA(pad, tostring(result))
		return
	end
	local part: MeshPart = result.part
	if pad.removed or wanted ~= quality then
		-- Streamed out, or the quality changed while creating: drop this one (a new one may be built later).
		part:Destroy()
		pcall(function()
			editable:Destroy()
		end)
		MeshQuota.release(quotaKey)
		pad.meshState = "none"
		return
	end
	local setupOk, setupErr = pcall(function(): any
		part.Name = "SD_GiantPad_" .. pad.key
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = paletteColor(spec.look.body, Palette.Cream)
		part.Transparency = spec.look.transparency
		if cosmeticRegistered() then
			part.CollisionGroup = COSMETIC_GROUP
		end
		part.CFrame = pad.frame * CFrame.new(0, centerY, 0)
		part.Parent = clientFxFolder()
		local dent = PadDent.new({
			cols = result.layout.grid,
			rows = result.layout.grid,
			spacing = result.layout.spacing,
			xs = table.move(result.layout.px, 1, result.layout.topCount, 1, {}),
			zs = table.move(result.layout.pz, 1, result.layout.topCount, 1, {}),
			pinned = result.layout.pinned,
		}, PadDent.paramsFrom(G, spec.sinkDepth, MAX_DT))
		local accents: { AccentFollower } = {}
		for _, tile in pad.accentTiles do
			table.insert(accents, { mesh = tile.mesh, index = nearestTopVertex(result.layout, tile.x, tile.z) })
		end
		pad.pathA = {
			editable = editable,
			part = part,
			layout = result.layout,
			dent = dent,
			vertexIds = result.vertexIds,
			normalIds = result.normalIds,
			centerY = centerY,
			quality = wanted,
			normalStamp = table.create(result.layout.topCount, 0),
			normalList = table.create(result.layout.topCount, 0),
			stampFrame = 0,
			accents = accents,
		}
		return nil
	end)
	if not setupOk then
		pad.pathA = nil
		part:Destroy()
		pcall(function()
			editable:Destroy()
		end)
		MeshQuota.release(quotaKey)
		pad.meshState = "none"
		failPathA(pad, tostring(setupErr))
		return
	end
	pad.meshState = "ready"
	resetTiles(pad)
	setBodyHidden(pad, true)
	for _, accent in (pad.pathA :: PathA).accents do
		accent.mesh.Offset = Vector3.new(0, ACCENT_LIFT, 0)
	end
end

local function meshCount(): number
	local count = 0
	for _, pad in pads do
		if pad.meshState ~= "none" then
			count += 1
		end
	end
	return count
end

-- Binding -----------------------------------------------------------------------------------------------------------

local function bindPad(model: Model, ic: Trove)
	local key = model:GetAttribute(ATTR_PAD_KEY)
	local spec = if type(key) == "string" then WorldLayout.giantPad(key) else nil
	if spec == nil then
		log:warn(`{model:GetFullName()} has no known PadKey; not animated`)
		return
	end
	local frame = CFrame.new(spec.center)
	local half = spec.footprint / 2
	local pad: Pad = {
		key = spec.key,
		spec = spec,
		model = model,
		frame = frame,
		center = spec.center + Vector3.new(0, spec.restTop / 2, 0),
		sphereRadius = math.sqrt(2) * half + spec.restTop,
		cleanup = ic,
		removed = false,
		tileMeshes = {},
		tileDent = PadDent.new(
			PadDent.regularGrid(spec.tilesPerSide, spec.tilesPerSide, spec.tileSpacing, false),
			PadDent.paramsFrom(G, spec.sinkDepth, MAX_DT)
		),
		bodyParts = {},
		bodyTransparency = {},
		bodyHidden = false,
		accentTiles = {},
		pathAFailed = failedKeys[spec.key] ~= nil, -- a failure earlier this session: path B, no retry
		meshState = "none",
		pathA = nil,
		contacts = {},
		distance = math.huge,
		culled = true,
		needsSnap = false,
		skip = false,
		pendingDt = 0,
		lastWrites = 0,
	}
	local body = model:FindFirstChild(BODY_NAME)
	if body then
		for _, descendant in body:GetDescendants() do
			if not descendant:IsA("BasePart") then
				continue
			end
			if descendant:GetAttribute(ATTR_PAD_ACCENT) == true then
				-- Stays visible over the path A mesh; a tile (Sphere SpecialMesh) also follows the mesh height.
				local mesh = descendant:FindFirstChildOfClass("SpecialMesh")
				if mesh and mesh.MeshType == Enum.MeshType.Sphere then
					local localPosition = frame:PointToObjectSpace(descendant.Position)
					table.insert(pad.accentTiles, { mesh = mesh, x = localPosition.X, z = localPosition.Z })
				end
			else
				table.insert(pad.bodyParts, descendant)
				pad.bodyTransparency[descendant] = descendant.Transparency
			end
		end
		findTiles(pad, body)
	else
		log:warn(`giant pad {pad.key} has no Body`)
	end
	pads[model] = pad
	ic:add(function()
		pad.removed = true
		if pads[model] == pad then
			pads[model] = nil
		end
		destroyPathA(pad)
	end)
end

-- Per frame ---------------------------------------------------------------------------------------------------------

local function byCameraDistance(a: Body, b: Body): boolean
	return a.cameraDistance < b.cameraDistance
end

-- Every player's character as a contact candidate, nearest the camera first. The records live in bodyPool and are
-- reused frame to frame (records past the current player count are dropped, so no character is held on to).
local function characterBodies(cameraPosition: Vector3, now: number, reduced: boolean): { Body }
	local count = 0
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character == nil then
			continue
		end
		local root = character:FindFirstChild(ROOT_PART)
		if root == nil or not root:IsA("BasePart") then
			continue
		end
		local x, z = root.Position.X, root.Position.Z
		local left = character:FindFirstChild("LeftFoot")
		local right = character:FindFirstChild("RightFoot")
		if left and right and left:IsA("BasePart") and right:IsA("BasePart") then
			x = (left.Position.X + right.Position.X) / 2
			z = (left.Position.Z + right.Position.Z) / 2
		end
		-- Squeeze pulse: a changed SD_SqueezeAt (never the first value seen).
		local squeezeAt = character:GetAttribute(ATTR_SQUEEZE_AT)
		local current = if squeezeAt == nil then false else squeezeAt
		local seen = lastSqueezeAt[character]
		if seen == nil then
			lastSqueezeAt[character] = current -- first sight: no pulse
		elseif seen ~= current then
			lastSqueezeAt[character] = current
			if current ~= false then
				startPulse(character, G.squeezeDip, G.squeezeDipSeconds, now)
			end
		end
		-- Landing thump (§18.5.1 A5): a fast fall that has just stopped.
		local peak: number? = fallPeak[character]
		local seenAt: number? = fallSeenAt[character]
		if peak ~= nil and (seenAt == nil or now - seenAt > FALL_STALE_SECONDS) then
			peak = nil
		end
		local nextPeak, landedVy = GiantPadController.landingStep(peak, root.AssemblyLinearVelocity.Y)
		fallPeak[character] = nextPeak
		fallSeenAt[character] = now
		if landedVy ~= nil then
			local thump = GiantPadController.landingExtra(landedVy) * (if reduced then REDUCED_LANDING else 1)
			startPulse(character, thump, LANDING.seconds, now)
		end
		local pulse = pulseUntil[character]
		local extra = if pulse and now < pulse then pulseExtra[character] or 0 else 0
		local cameraDistance = (root.Position - cameraPosition).Magnitude
		count += 1
		local record = bodyPool[count]
		if record == nil then
			bodyPool[count] = {
				character = character,
				root = root,
				x = x,
				z = z,
				rootY = root.Position.Y,
				extra = extra,
				cameraDistance = cameraDistance,
			}
		else
			record.character = character
			record.root = root
			record.x = x
			record.z = z
			record.rootY = root.Position.Y
			record.extra = extra
			record.cameraDistance = cameraDistance
		end
	end
	for index = #bodyPool, count + 1, -1 do
		bodyPool[index] = nil
	end
	table.sort(bodyPool, byCameraDistance)
	return bodyPool
end

local function gatherContacts(pad: Pad, bodies: { Body })
	local contacts = pad.contacts
	table.clear(contacts)
	local spec = pad.spec
	local half = spec.footprint / 2
	local origin = pad.frame.Position
	local bottom = origin.Y + spec.collisionTop
	for _, body in bodies do
		if #contacts >= G.maxContacts then
			break
		end
		local above = body.rootY - bottom
		if above < 0 or above > G.contactHeight then
			continue
		end
		local rx, rz = body.root.Position.X - origin.X, body.root.Position.Z - origin.Z
		if not insideFootprint(rx, rz, half, spec.cornerRadius) then
			continue
		end
		table.insert(contacts, {
			x = body.x - origin.X,
			z = body.z - origin.Z,
			extra = if body.extra > 0 then body.extra else nil,
		})
	end
end

local function activeDent(pad: Pad): PadDent.Dent
	local pathA = pad.pathA
	return if pathA then pathA.dent else pad.tileDent
end

local function writeDent(pad: Pad, count: number)
	if count <= 0 then
		return
	end
	local pathA = pad.pathA
	if pathA then
		writeMesh(pathA, count)
	else
		writeTiles(pad, pad.tileDent, count)
	end
end

local function downgradeToLow()
	if downgraded or quality == "Low" then
		downgraded = true
		return
	end
	downgraded = true
	quality = "Low"
	log:info("giant pads rebuilt at Low quality for this session (slow frames)")
	for _, pad in pads do
		if pad.pathA then
			destroyPathA(pad)
		end
	end
end

local function byPadDistance(a: Pad, b: Pad): boolean
	return a.distance < b.distance
end

local function step(dt: number, now: number): boolean
	local camera = Workspace.CurrentCamera
	if camera == nil or next(pads) == nil then
		return true
	end
	chooseQuality(camera)
	local cameraCFrame = camera.CFrame
	local cameraPosition = cameraCFrame.Position
	local viewport = camera.ViewportSize
	local tanHalf = math.tan(math.rad(camera.FieldOfView) / 2)
	local reduced = GuiService.ReducedMotionEnabled
	local bodies: { Body }? = nil

	local candidates: { Pad } = {}
	local snaps: { Pad } = {}
	for _, pad in pads do
		pad.distance = (pad.center - cameraPosition).Magnitude
		-- Path A creation: streamed in, within createStuds, one at a time, at most maxMeshes.
		if
			qualityChosen
			and not pad.pathAFailed
			and pad.meshState == "none"
			and not creating
			and pad.distance <= G.createStuds
			and meshCount() < G.maxMeshes
		then
			task.spawn(createPathA, pad)
		end
		-- Culling.
		local visible = false
		if pad.distance <= G.simulateStuds then
			local screen = camera:WorldToViewportPoint(pad.center)
			visible =
				GiantPadController.sphereOnScreen(screen.X, screen.Y, screen.Z, pad.sphereRadius, viewport, tanHalf)
		end
		if not visible then
			pad.culled = true
			continue
		end
		local list = bodies or characterBodies(cameraPosition, now, reduced)
		bodies = list
		gatherContacts(pad, list)
		local dent = activeDent(pad)
		if pad.culled then
			pad.culled = false
			pad.needsSnap = #pad.contacts == 0
		end
		if #pad.contacts > 0 then
			pad.needsSnap = false -- stepping takes over
		end
		if pad.needsSnap then
			table.insert(snaps, pad)
		elseif #pad.contacts > 0 or not dent:isAsleep() then
			table.insert(candidates, pad)
		end
	end

	table.sort(candidates, byPadDistance)
	local budget = G.writesPerClient
	local stepped = 0
	for index, pad in candidates do
		if index > G.maxSimulated then
			break -- holds its shape until it gets a slot
		end
		stepped += 1
		local heavy = pad.lastWrites > G.writesPerPad or pad.lastWrites > budget
		if heavy and not pad.skip then
			pad.skip = true
			pad.pendingDt += dt
			continue
		end
		pad.skip = false
		local frameDt = dt + pad.pendingDt
		pad.pendingDt = 0
		local dent = activeDent(pad)
		local count = dent:step(frameDt, pad.contacts, reduced)
		writeDent(pad, count)
		pad.lastWrites = count
		budget = math.max(0, budget - count)
	end

	-- Snaps to rest, nearest first, charged to the same budget (see the header).
	table.sort(snaps, byPadDistance)
	for _, pad in snaps do
		local dent = activeDent(pad)
		local pending = dent:restWriteCount()
		if GiantPadController.snapFits(pending, G.writesPerClient - budget, budget) then
			local count = dent:snapToRest()
			writeDent(pad, count)
			budget = math.max(0, budget - count)
			pad.needsSnap = false
			pad.lastWrites = 0
		end
	end

	-- Automatic downgrade: average frame time above downgradeFrameMs for downgradeSeconds while a pad is stepped.
	if stepped > 0 and not downgraded then
		slowWindow += dt
		slowFrames += 1
		if slowWindow >= G.downgradeSeconds then
			local averageMs = slowWindow / slowFrames * 1000
			slowWindow, slowFrames = 0, 0
			if averageMs > G.downgradeFrameMs then
				downgradeToLow()
			end
		end
	else
		slowWindow, slowFrames = 0, 0
	end
	return true
end

-- Public ------------------------------------------------------------------------------------------------------------

-- Pure: whether a bounding sphere is on screen, from Camera:WorldToViewportPoint of its centre (screenX, screenY in
-- pixels, depth in studs), its radius, the viewport size and tan(FieldOfView / 2) (vertical).
function GiantPadController.sphereOnScreen(
	screenX: number,
	screenY: number,
	depth: number,
	radius: number,
	viewport: Vector2,
	tanHalfFov: number
): boolean
	if depth < -radius then
		return false -- wholly behind the camera
	end
	if depth <= radius then
		return true -- the camera is inside or right next to it
	end
	local pixels = radius * viewport.Y / (2 * depth * tanHalfFov)
	return screenX >= -pixels
		and screenX <= viewport.X + pixels
		and screenY >= -pixels
		and screenY <= viewport.Y + pixels
end

-- Pure: whether a snap to rest of `pending` vertex writes runs this frame, after `spent` writes and with `left` of the
-- per-client budget remaining: when it fits what is left, or when nothing was written yet (a snap cannot be split,
-- so a pad bigger than the whole budget still snaps on a frame of its own).
function GiantPadController.snapFits(pending: number, spent: number, left: number): boolean
	return pending <= left or spent <= 0
end

-- Pure (§18.5.1 A5): the landing thump's extra dip, in studs, for a fall at `vy` (studs/s, negative = down):
-- clamp(giantPad.landing.perSpeed · |vy|, landing.min, landing.max). The caller halves it under ReducedMotion.
function GiantPadController.landingExtra(vy: number): number
	if vy ~= vy then
		return 0
	end
	return math.clamp(LANDING.perSpeed * math.abs(vy), LANDING.min, LANDING.max)
end

-- Pure (§18.5.1 A5): one frame of a character's landing detection. `peak` is the fastest fall (most negative vy) seen
-- since the root first fell at <= -landing.minFallSpeed (nil while it has not), `vy` the root's vertical speed now.
-- Returns the new peak and, on the frame the root slows to >= landing.landedVy, the peak to thump with (once).
function GiantPadController.landingStep(peak: number?, vy: number): (number?, number?)
	if vy ~= vy then
		return peak, nil
	end
	if vy <= -LANDING.minFallSpeed then
		return math.min(peak or vy, vy), nil
	end
	if peak ~= nil and vy >= LANDING.landedVy then
		return nil, peak
	end
	return peak, nil
end

-- Why path A cannot start for the pad `key` now, or nil when it may: Config.Anim.giantPad.pathA off, a debug flag, or
-- a refused slot of the shared editable-mesh quota (Anim/MeshQuota, key "pad:<key>"; §18.3.4). Any reason is a path A
-- failure: that pad uses path B for the session. A nil answer means the pad now holds its quota slot, which
-- destroyPathA (or a failed create) gives back. `quota` is a private MeshQuota.new(limit) (unit tests); nil uses the
-- client's shared one.
function GiantPadController.pathABlocker(key: string, quota: MeshQuota.Quota?): string?
	if G.pathA == false then
		return "Config.Anim.giantPad.pathA is off"
	end
	if forceFailure or Config.Debug.forcePadPathB then
		return "forced by a debug flag"
	end
	local quotaKey = QUOTA_PREFIX .. key
	local granted = if quota then quota:tryAcquire(quotaKey) else MeshQuota.tryAcquire(quotaKey)
	if not granted then
		return QUOTA_REFUSED
	end
	return nil
end

-- The reason path A failed for this pad key this session (that pad stays on path B), or nil.
function GiantPadController.pathAFailure(key: string): string?
	return failedKeys[key]
end

-- The current mesh quality ("High" or "Low").
function GiantPadController.quality(): Quality
	return quality
end

-- Sets the mesh quality (e.g. the UI switches to the compact layout). Existing meshes are rebuilt on a change.
function GiantPadController.setQuality(value: Quality)
	qualityChosen = true
	if value == quality then
		return
	end
	quality = value
	for _, pad in pads do
		if pad.pathA then
			destroyPathA(pad)
		end
	end
end

-- Studio check (L3 §17.12, through DebugHooks "padPathB"): forces every mesh created from now on to fail, so its pad
-- switches to path B with one log line. Turning it on also drops the existing meshes, so every pad in range tries
-- once more (and fails) on the next frame. Turning it off forgets this session's path A failures, so every pad in
-- range tries path A once more (a Studio check only; live clients never call it).
function GiantPadController.debugForceFailure(on: boolean)
	forceFailure = on
	if on then
		for _, pad in pads do
			if pad.pathA then
				destroyPathA(pad)
			end
		end
	else
		table.clear(failedKeys)
		for _, pad in pads do
			pad.pathAFailed = false
		end
	end
end

-- Small table for Studio debug hooks and tests: per pad key its path, mesh state, sleep and lowest height.
function GiantPadController.debugState(): { [string]: any }
	local state: { [string]: any } = { quality = quality, downgraded = downgraded }
	for _, pad in pads do
		local dent = activeDent(pad)
		local lowest = 0
		for index = 1, dent:size() do
			lowest = math.min(lowest, dent:height(index))
		end
		state[pad.key] = {
			path = if pad.pathA then "A" else "B",
			pathAFailed = pad.pathAFailed,
			meshState = pad.meshState,
			meshQuality = if pad.pathA then pad.pathA.quality else nil,
			contacts = #pad.contacts,
			asleep = dent:isAsleep(),
			lowest = lowest,
			distance = pad.distance,
			lastWrites = pad.lastWrites,
		}
	end
	return state
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function GiantPadController.init()
	local c = Cleanup.new()
	cleanup = c
	local bound: { [Instance]: Trove } = {}
	local function added(instance: Instance)
		if bound[instance] or not instance:IsA("Model") then
			return
		end
		local ic = Cleanup.new()
		bound[instance] = ic :: any
		local ok, err = pcall(function(): any
			bindPad(instance :: Model, ic :: any)
			return nil
		end)
		if not ok then
			log:error(`could not bind {instance:GetFullName()}:`, err)
		end
	end
	local function removed(instance: Instance)
		local ic = bound[instance]
		if ic then
			bound[instance] = nil
			ic:clean()
		end
	end
	c:add(CollectionService:GetInstanceAddedSignal(TAG_GIANT_PAD):Connect(added))
	c:add(CollectionService:GetInstanceRemovedSignal(TAG_GIANT_PAD):Connect(removed))
	for _, instance in CollectionService:GetTagged(TAG_GIANT_PAD) do
		added(instance)
	end
	c:add(Scheduler.add(step, "render"))
	c:add(function()
		for instance in table.clone(bound) do
			removed(instance)
		end
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function GiantPadController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return GiantPadController
