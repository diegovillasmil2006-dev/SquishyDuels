--!strict
-- KneadController (client only; not a controller: no init or start, the bootstrap does not load it). Spec
-- phase2-squeeze §3.1-§3.10 with the user's decisions of 2026-10-11: Inspect is the knead screen (first and third person
-- unchanged). InspectController starts one per model it shows and talks to it through a few hooks; the knead itself
-- lives here and in the modules it drives:
--   the soft shell (Anim/ShellGeometry -> Anim/SoftShell: one EditableMesh MeshPart "SD_SoftShell" in the stage model,
--   MeshQuota key "soft"; the toy's E / B / RB body parts hide, every other part rides the shell through
--   SquishDeformer:setOffsets, and the deformer drives the shell as a solid part, so the rig's breathing and jiggle
--   scale it), the solver (Anim/SoftBody), the wax coat (Anim/WaxCoat), its crack lines (Anim/CrackNetwork, built a few
--   ms a frame; Anim/CrackCanvas draws them into the shell's EditableImage atlas), the flakes, the jolt and the re-wax
--   sparkle (Anim/FlakePool), the 2D layer (UI/KneadOverlay: vignette, wax HUD, fingertip ring), the panel's knead rows
--   and help (onView) and the wax sound (Controllers/KneadAudio).
--
--   KneadController.start(args) -> Handle?   nil when the toy has no shell body (no SD_Body part of shape E, B or RB)
--       or MeshQuota refuses the slot: Inspect keeps today's squeeze preview. The build runs on its own thread
--       (CreateMeshPartAsync yields); the first step() after it finishes swaps the toy to the shell ("live"). Any
--       failure, before or after (engine, budget, an error in a frame), undoes all of it and leaves today's Inspect with
--       one warning: never an error.
--   handle:step(dt, now)   InspectController's render effect, after the orbit (this frame's camera) and before the rig
--                          (the kicks and the face land in this frame's write)
--   handle:isLive()        the shell shows and the inputs knead
--   handle:pointerDown(position, touch) -> boolean   a press on the stage (InputObject.Position space): true when it
--                          hit the shell (the finger is down, the press is the knead's until pointerUp), false for the
--                          orbit
--   handle:pointerMove(position), handle:pointerUp(), handle:hover(position?)   (hover: the mouse, for the ring)
--   handle:crunch(on), handle:palms(on), handle:rewax()   the thumb crunch, the palm squeeze and the re-wax
--   handle:cancel()        every hold and press ends (focus lost, Cancel, the context off)
--   handle:debugState()    Studio checks: cracks/s, solver ms, build ms, the network, the quota, the wax switch
--   handle:destroy()       everything goes (the shell, its mesh and image, the quota slot, flakes, sounds, the rows)
-- Pure (unit-tested): readModel, nearestVertices, rides, restRay, inputKind, view, tiltTarget.
-- Tests: useDeps(overrides) swaps the engine-only surfaces (the shell's EditableMesh, the atlas' EditableImage, putting
-- the atlas on the shell, the sound player), so KneadWax_Test runs a handle in Edit mode.
--
-- The wax switch (user 2026-10-12: Config.Wax.enabled, or args.wax): off, a session keeps the soft body (the finger
-- knead with its dents and memory, the stretch off the edge, Q / palms, F / thumbs as a thumb press, R faces it front,
-- the vignette and the fingertip ring) and its sound (KneadAudio without the wax: the body loop, driven as if there
-- were no coat, and the thumps), and makes nothing of the wax: no CrackNetwork (none cached), no WaxCoat, no crack
-- lines (the CrackCanvas is still made and filled: it is the shell's colour atlas), no flakes, jolt or wax HUD, no
-- re-wax (rewax() does nothing), and the panel's view has no Coat row and no Re-wax, with press wording.
--
-- Readings (DESIGN silent; spec "proposal"):
-- * The shell's parts: SD_Body parts of shape E, B or RB that are not section parts (their pose changes); a W body part
--   or any other part rides. Its sizes are rest sizes (an RB part's Size over the deformer's kv). The parts are sorted
--   by name, so a clone of the same toy gives the same atlas tiles (the shell and line network are cached for one toy).
-- * Riders: each other part follows the shell vertex nearest its contact point (SD_Contact) or its centre, rigidly (the
--   design deforms face meshes per vertex, squish.js:142-143; spec §3.2). Section parts keep their base Offset while
--   they turn, and RB / solid riders do not ride (the deformer's mesh path only).
-- * Kicks: the soft kicks go to the rig's jiggle on its squeeze axis (KneadMath.kickPeak; the design jiggles on the kick
--   axis); the Squisher kicks are left out (no rig equivalent, spec §3.3 decision).
-- * The view: the orbit camera stands in for the toy's rotation. Knead home = yaw 0, pitch homePitch (R / ButtonY reset
--   goes there while live); a crunch not dragged eases toward the crunch pitch, its end eases home for settleSeconds,
--   a drag stops the settle. Under ReducedMotion the view never moves by itself (no tilt, no settle) and there is no
--   jolt; dents, memory, cracks, flakes (fewer, unspun) and sound stay.
-- * The jolt moves the whole model through the deformer's twist base (SquishDeformer:setTwistBase), in camera x / y.
-- * The help caption follows the last input type (Touch / Gamepad / else the keyboard). Gamepads have no finger knead
--   (no pointer); touch kneads with one finger and shows no ring (spec §3.6).
-- * Compact layout (Layout.layoutClass of the screen): the HUD shows the bar and the state only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local SquishyBlueprints = require(Shared.Art.SquishyBlueprints)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local CrackCanvas = require(Client.Anim.CrackCanvas)
local CrackNetwork = require(Client.Anim.CrackNetwork)
local FlakePool = require(Client.Anim.FlakePool)
local KneadMath = require(Client.Anim.KneadMath)
local MeshQuality = require(Client.Anim.MeshQuality)
local MeshQuota = require(Client.Anim.MeshQuota)
local ShellGeometry = require(Client.Anim.ShellGeometry)
local SoftBody = require(Client.Anim.SoftBody)
local SoftShell = require(Client.Anim.SoftShell)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local SquishRig = require(Client.Anim.SquishRig)
local WaxCoat = require(Client.Anim.WaxCoat)
local KneadFormat = require(Client.UI.KneadFormat)
local KneadOverlay = require(Client.UI.KneadOverlay)
local Layout = require(Client.UI.Layout)
local OrbitCamera = require(Client.UI.OrbitCamera)
local ViewportStage = require(Client.UI.ViewportStage)
local KneadAudio = require(script.Parent.KneadAudio)
local SoundController = require(script.Parent.SoundController)

-- Types

type Shell = ShellGeometry.Shell

-- The panel's knead rows, help and buttons (UI/InspectPanel's KneadView): coat nil (no Coat row) and rewax false with
-- the wax off; thumb = the thumb hold button's label.
export type View = { squeeze: string, coat: string?, help: string, thumb: string, rewax: boolean }

export type BodyPart = {
	part: BasePart,
	shape: string,
	cframe: CFrame, -- pivot space
	size: Vector3, -- rest size
	color: Color3,
}

export type Rider = { part: BasePart, point: Vector3 } -- point: its anchor, pivot space

export type Reading = {
	body: { BodyPart },
	riders: { Rider },
	faceMin: Vector3?,
	faceMax: Vector3?,
}

export type Args = {
	model: Model,
	def: Types.SquishyDef,
	stage: ViewportStage.Stage,
	orbit: OrbitCamera.State,
	rig: () -> SquishRig.Rig?, -- the model's rig now (takeRig may swap it)
	deformer: () -> SquishDeformer.Deformer?, -- the model's deformer now
	reattach: () -> (), -- the deformer again, after the shell joined or left the model
	onView: (view: View?) -> (), -- the panel's knead rows, buttons and help (nil: back to today's)
	reduced: () -> boolean, -- ReducedMotion
	wax: boolean?, -- the wax switch (user 2026-10-12): nil = Config.Wax.enabled
}

type State = "building" | "ready" | "live" | "off"

type Hit = { point: Vector3, normal: Vector3 }

-- What the build makes (owned by the handle's Cleanup once ready). The network and the coat only with the wax on.
type Kit = {
	shell: Shell,
	network: CrackNetwork.Network?,
	mesh: SoftShell.Handle,
	canvas: CrackCanvas.Canvas,
	body: SoftBody.Body,
	coat: WaxCoat.Coat?,
	anchors: { number }, -- per rider: its shell vertex
	colors: { Color3 }, -- per shell part
	all: { number }, -- 1..shell.count (the reveal after a late network build; empty with the wax off)
}

-- What going live makes. The flakes only with the wax on.
type Live = {
	overlay: KneadOverlay.Overlay,
	pool: FlakePool.Pool?,
	audio: KneadAudio.Audio,
	twistBase: CFrame, -- the model's pivot without the jolt
}

type HandleData = {
	_args: Args,
	_state: State,
	_reason: string?,
	_feel: string,
	_pitch: number,
	_squeezeDepth: number,
	_quality: ShellGeometry.Quality,
	_reading: Reading,
	_kit: Kit?,
	_live: Live?,
	_offsets: { [BasePart]: Vector3 },
	_cleanup: Cleanup.Cleanup,
	_rng: Random,
	_reattach: boolean,
	_dead: boolean,
	_wax: boolean, -- the wax switch (user 2026-10-12)
	-- input
	_pressing: boolean,
	_touch: boolean,
	_pointerAt: Vector2?,
	_moveTo: Vector2?,
	_hoverAt: Vector2?,
	_hoverDirty: boolean,
	_over: boolean,
	_ring: string,
	_ringAt: Vector2?,
	_crunching: boolean,
	_palms: boolean,
	_settleLeft: number,
	-- presentation
	_jolt: number,
	_jolted: boolean,
	_faceSquish: boolean,
	_hudLeft: number,
	_input: string,
	-- Studio checks
	_buildMs: number,
	_solveMs: number,
	_solveMaxMs: number,
	_rateTime: number,
	_rateFrom: number,
	_cracksPerSecond: number,
}

-- Constants

local KNEAD = Config.Knead
local VIEW = KNEAD.view
local WAX = Config.Wax
local CANVAS = WAX.canvas
local FLAKES = WAX.flakes
local UI_KNEAD = Config.UI.Knead
local QUOTA_KEY = "soft" -- MeshQuota (spec §3.2)
local PROFILE = "SD_Knead" -- the profiler scope of a live frame (spec §3.14: <= ~2 ms)
local HOME_PITCH_DEG = math.deg(VIEW.homePitchRad)
local CRUNCH_PITCH_DEG = math.deg(VIEW.crunchPitchRad)
local SHELL_SHAPES: { [string]: boolean } = { E = true, B = true, RB = true } -- ShellGeometry's shapes
local BUILD_CHUNK = 4 -- shell triangles per CrackNetwork:buildStep between two clock reads
local JOLT_MIN = 1e-5 -- du: below it the jolt stops (design: fp.js:480)
local RAY_REACH_DIMS = 4 -- a pointer ray reaches this many toy sizes past the pivot
local SOLVE_SMOOTHING = 0.1 -- the share of each frame in the mean solver ms
local GAMEPAD_PREFIX = "Gamepad"
local KEYBOARD = "Keyboard"
local WHITE = Color3.new(1, 1, 1)
local ATTR_BODY = "SD_Body"
local ATTR_SHAPE = "SD_Shape"
local ATTR_SECTION = "SD_Section"
local ATTR_RIGIDITY = "SD_Rigidity"
local ATTR_CONTACT = "SD_Contact"
local ATTR_FACE = "SD_Face"
local ATTR_SCALE = "SD_Scale"

-- Module tables

local HandleClass = {}
HandleClass.__index = HandleClass

export type Handle = typeof(setmetatable({} :: HandleData, HandleClass))

local KneadController = {}

-- Private

local log = Log.new("Knead")
-- One toy's shell and line network, kept for the next open of the same toy (the network takes seconds of frames). The
-- network only once a session with the wax on made it (none with the wax off).
type CacheEntry = { key: string, shell: Shell, network: CrackNetwork.Network? }
local cache: CacheEntry? = nil

-- The engine-only surfaces a handle touches; tests swap them (useDeps): the shell's EditableMesh, the crack atlas'
-- EditableImage, the atlas on the shell (Content) and the sound player KneadAudio plays through.
local REAL_DEPS = {
	Shell = SoftShell, -- create(shell, flipV) -> (Handle?, reason?)
	Canvas = CrackCanvas, -- new(shell, colors, size) -> Canvas?
	Texture = function(part: MeshPart, image: EditableImage)
		part.TextureContent = Content.fromObject(image)
	end,
	Sound = SoundController :: any, -- KneadAudio's player
}
type Deps = typeof(REAL_DEPS)
local deps: Deps = REAL_DEPS

-- The deformer's per-axis factor for a part of this rigidity (SquishDeformer: kv = 1 + (S - 1)·(1 - rigidity), R = 1).
local function kvOf(scale: Vector3, rigidity: number): Vector3
	return Vector3.one + (scale - Vector3.one) * (1 - rigidity)
end

local function byName(a: BodyPart, b: BodyPart): boolean
	return a.part.Name < b.part.Name
end

-- Public: pure ---------------------------------------------------------------------------------------------------------

-- The toy as the knead sees it, relative to the model pivot. `scale` is the deformer's scale now (an RB part's Size
-- carries it).
function KneadController.readModel(model: Model, scale: Vector3): Reading
	local pivot = model:GetPivot()
	local root = model.PrimaryPart
	local body: { BodyPart } = {}
	local riders: { Rider } = {}
	local lo: { number }? = nil
	local hi: { number }? = nil
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") or descendant == root then
			continue
		end
		local part = descendant :: BasePart
		local cframe = pivot:ToObjectSpace(part.CFrame)
		local shape = part:GetAttribute(ATTR_SHAPE)
		if
			part:GetAttribute(ATTR_BODY) == true
			and type(shape) == "string"
			and SHELL_SHAPES[shape]
			and part:GetAttribute(ATTR_SECTION) == nil
		then
			local size = part.Size
			if shape == "RB" and part:FindFirstChildWhichIsA("DataModelMesh") == nil then
				local rigidity = part:GetAttribute(ATTR_RIGIDITY)
				size = size / kvOf(scale, if type(rigidity) == "number" then math.clamp(rigidity, 0, 1) else 0)
			end
			table.insert(body, { part = part, shape = shape, cframe = cframe, size = size, color = part.Color })
		else
			local contact = part:GetAttribute(ATTR_CONTACT)
			local point = if typeof(contact) == "Vector3"
				then cframe:PointToWorldSpace(contact * part.Size / 2)
				else cframe.Position
			table.insert(riders, { part = part, point = point })
		end
		if part:GetAttribute(ATTR_FACE) == true then
			local half = part.Size / 2
			local min = lo or { math.huge, math.huge, math.huge }
			local max = hi or { -math.huge, -math.huge, -math.huge }
			lo, hi = min, max
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = cframe:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
						min[1], max[1] = math.min(min[1], corner.X), math.max(max[1], corner.X)
						min[2], max[2] = math.min(min[2], corner.Y), math.max(max[2], corner.Y)
						min[3], max[3] = math.min(min[3], corner.Z), math.max(max[3], corner.Z)
					end
				end
			end
		end
	end
	table.sort(body, byName)
	local reading: Reading = { body = body, riders = riders, faceMin = nil, faceMax = nil }
	if lo and hi then
		reading.faceMin = Vector3.new(lo[1], lo[2], lo[3])
		reading.faceMax = Vector3.new(hi[1], hi[2], hi[3])
	end
	return reading
end

-- The deforming shell vertex (1..shell.count) nearest each point.
function KneadController.nearestVertices(shell: Shell, points: { Vector3 }): { number }
	local px, py, pz = shell.px, shell.py, shell.pz
	local result: { number } = table.create(#points, 1)
	for k, point in points do
		local x, y, z = point.X, point.Y, point.Z
		local best, bestDistance = 1, math.huge
		for i = 1, shell.count do
			local dx, dy, dz = px[i] - x, py[i] - y, pz[i] - z
			local distance = dx * dx + dy * dy + dz * dz
			if distance < bestDistance then
				best, bestDistance = i, distance
			end
		end
		result[k] = best
	end
	return result
end

-- Writes each rider's offset (its anchor vertex's shown minus rest position, pivot space) into `offsets`.
function KneadController.rides(
	offsets: { [BasePart]: Vector3 },
	riders: { Rider },
	anchors: { number },
	shell: Shell,
	px: { number },
	py: { number },
	pz: { number }
)
	local rx, ry, rz = shell.px, shell.py, shell.pz
	for k, rider in riders do
		local i = anchors[k]
		offsets[rider.part] = Vector3.new(px[i] - rx[i], py[i] - ry[i], pz[i] - rz[i])
	end
end

-- A stage ray (world) in the shell's rest space: a rest point q shows at pivot · (q ∘ scale).
function KneadController.restRay(pivot: CFrame, scale: Vector3, origin: Vector3, direction: Vector3): (Vector3, Vector3)
	return pivot:PointToObjectSpace(origin) / scale, pivot:VectorToObjectSpace(direction) / scale
end

-- "Touch", "Gamepad" or "Keyboard" (the mouse and anything else) for UI/KneadFormat.help.
function KneadController.inputKind(inputType: Enum.UserInputType): string
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	end
	if string.sub(inputType.Name, 1, #GAMEPAD_PREFIX) == GAMEPAD_PREFIX then
		return "Gamepad"
	end
	return KEYBOARD
end

-- The panel's knead rows (spec §1.19), the help caption for that input, the thumb button's label and whether Re-wax
-- shows; with the wax off (user 2026-10-12; wax nil = Config.Wax.enabled) no Coat row, no Re-wax and press wording.
function KneadController.view(feel: string, input: string, wax: boolean?): View
	local on = if wax == nil then WAX.enabled else wax
	local rows = KneadFormat.rows(feel, on)
	return {
		squeeze = rows.squeeze,
		coat = rows.coat,
		help = KneadFormat.help(input, on),
		thumb = KneadFormat.thumb(on),
		rewax = on,
	}
end

-- Where the view eases by itself this frame (the pitch in degrees at yaw 0, and the rate), or nil: the settle home
-- first (fp.js:483), else the crunch tilt while not dragged (fp.js:484); never while dragged or under ReducedMotion.
function KneadController.tiltTarget(
	crunching: boolean,
	settleLeft: number,
	dragging: boolean,
	reduced: boolean
): (number?, number?)
	if reduced or dragging then
		return nil, nil
	end
	if settleLeft > 0 then
		return HOME_PITCH_DEG, VIEW.homeRate
	end
	if crunching then
		return CRUNCH_PITCH_DEG, VIEW.crunchRate
	end
	return nil, nil
end

-- Private: the handle ----------------------------------------------------------------------------------------------

-- Undoes everything (newest first, through the Cleanup) and stays off. `reattach`: the session goes on, so the
-- deformer is attached again without the shell.
local function teardown(self: Handle, reattach: boolean)
	if self._state == "off" then
		return
	end
	self._state = "off"
	self._reattach = reattach
	self._live = nil
	self._kit = nil
	self._pressing = false
	self._cleanup:clean()
end

local function fail(self: Handle, err: any)
	self._reason = tostring(err)
	log:warn("the knead stopped; today's squeeze from here:", err)
	teardown(self, true)
end

local function build(self: Handle)
	local started = os.clock()
	local mesh: SoftShell.Handle? = nil
	local canvas: CrackCanvas.Canvas? = nil
	local ok, result = pcall(function(): Kit?
		local args = self._args
		local reading = self._reading
		local inputs: { ShellGeometry.PartInput } = {}
		local names: { string } = {}
		local colors: { Color3 } = {}
		for k, part in reading.body do
			inputs[k] = { shape = part.shape, cframe = part.cframe, size = part.size }
			names[k] = part.part.Name
			colors[k] = part.color
		end
		local key = `{args.def.blueprintId}|{self._quality}|{args.model:GetAttribute(ATTR_SCALE)}|`
			.. table.concat(names, ",")
		local entry: CacheEntry
		local cached = cache
		if cached ~= nil and cached.key == key then
			entry = cached
		else
			entry = { key = key, shell = ShellGeometry.build(inputs, self._quality), network = nil }
			cache = entry
		end
		local shell = entry.shell
		-- The crack lines only with the wax on (user 2026-10-12): the cached network reset, else a new one, kept with the
		-- shell. With the wax off none is made or cached.
		local network: CrackNetwork.Network? = nil
		if self._wax then
			local kept = entry.network
			if kept then
				kept:reset()
				network = kept
			else
				local fresh = CrackNetwork.new(shell, self._feel)
				entry.network = fresh
				network = fresh
			end
		end
		local made, reason = deps.Shell.create(shell, KNEAD.shell.uvFlipV) -- yields
		mesh = made
		if self._dead then
			return nil
		end
		if made == nil then
			error(`no soft shell ({reason})`, 0)
		end
		local image = deps.Canvas.new(shell :: any, colors, KNEAD.shell.atlas[self._quality])
		canvas = image
		if image == nil then
			error("no EditableImage for the crack atlas", 0)
		end
		local points: { Vector3 } = {}
		for k, rider in reading.riders do
			points[k] = rider.point
		end
		local body = SoftBody.new(shell, {
			feel = self._feel,
			squeezeDepth = self._squeezeDepth,
			faceMin = reading.faceMin,
			faceMax = reading.faceMax,
			rng = self._rng,
		})
		local all: { number } = {}
		if network then
			all = table.create(shell.count, 0)
			for i = 1, shell.count do
				all[i] = i
			end
		end
		return {
			shell = shell,
			network = network,
			mesh = made,
			canvas = image,
			body = body,
			coat = if self._wax then WaxCoat.new(body, { rng = self._rng }) else nil, -- user 2026-10-12: the wax switch
			anchors = KneadController.nearestVertices(shell, points),
			colors = colors,
			all = all,
		}
	end)
	self._buildMs = (os.clock() - started) * 1000
	if ok and result ~= nil and not self._dead and self._state == "building" then
		local kit = result :: Kit
		self._cleanup:add(kit.mesh)
		self._cleanup:add(kit.canvas)
		self._kit = kit
		self._state = "ready"
		return
	end
	-- Closed while building, or a failure: nothing of it stays.
	if canvas then
		canvas:destroy()
	end
	if mesh then
		mesh:destroy()
	end
	if not ok and not self._dead then
		fail(self, result)
	end
end

-- The HUD now (Config.UI.Knead.refreshSeconds apart), compact on the compact layout; none with the wax off.
local function refreshHud(self: Handle, animate: boolean)
	local kit, live = self._kit, self._live
	local coat = if kit then kit.coat else nil
	if coat == nil or live == nil then
		return
	end
	live.overlay:setHud(KneadFormat.hud(coat.waxLeft, coat.crunchiness, coat.cracks), animate)
	local camera = Workspace.CurrentCamera
	local screen = if camera then camera.ViewportSize else Vector2.zero
	live.overlay:setCompact(screen.X > 0 and screen.Y > 0 and Layout.layoutClass(screen.X, screen.Y) == "compact")
end

-- The pointer's ray in the shell's rest space (nil without a laid-out stage; `inside`: only on the stage).
local function rayAt(
	self: Handle,
	kit: Kit,
	position: Vector2,
	pivot: CFrame,
	scale: Vector3,
	inside: boolean
): (Vector3?, Vector3?)
	local stage = self._args.stage
	local viewport = stage.viewport
	local size = viewport.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil, nil
	end
	local point = (position - viewport.AbsolutePosition) / size
	if inside and (point.X < 0 or point.X > 1 or point.Y < 0 or point.Y > 1) then
		return nil, nil
	end
	local camera = stage.camera
	local origin, direction = OrbitCamera.tapRay(camera.CFrame, camera.FieldOfView, size.X / size.Y, point)
	local reach = (origin - pivot.Position).Magnitude + RAY_REACH_DIMS * kit.shell.maxDim
	return KneadController.restRay(pivot, scale, origin, direction * reach)
end

-- The shell under a rest-space ray: the rest point and normal of the hit (squish.js:461-470), weighed against the
-- triangle's shown corners.
local function hitAt(kit: Kit, origin: Vector3, direction: Vector3): Hit?
	local shell, body = kit.shell, kit.body
	local center = shell.center
	local triangle, point = kit.mesh:raycast(origin - center, direction)
	if triangle == nil or point == nil then
		return nil
	end
	local tris = shell.tris
	local a, b, c = tris[3 * triangle - 2], tris[3 * triangle - 1], tris[3 * triangle]
	local px, py, pz = body.px, body.py, body.pz
	local wa, wb, wc = KneadMath.barycentric(
		point + center,
		Vector3.new(px[a], py[a], pz[a]),
		Vector3.new(px[b], py[b], pz[b]),
		Vector3.new(px[c], py[c], pz[c])
	)
	local restPoint, restNormal = body:restHit(a, b, c, wa, wb, wc)
	if restPoint == nil or restNormal == nil then
		return nil
	end
	return { point = restPoint, normal = restNormal }
end

local function scaleOf(self: Handle): Vector3
	local deformer = self._args.deformer()
	return if deformer then deformer:getScale() else Vector3.one
end

-- The shell joins the model, the body parts hide, the riders ride, the 2D layer, flakes (with the wax on) and sound
-- start, the panel shows the knead; each step's undo goes in the Cleanup (newest first on teardown).
local function goLive(self: Handle)
	local args = self._args
	local kit = self._kit :: Kit
	local c = self._cleanup
	local model = args.model
	local part = kit.mesh.part
	deps.Texture(part, kit.canvas.image)
	part.CFrame = model:GetPivot() * CFrame.new(kit.shell.center)
	self._state = "live" -- from here a teardown puts the model back
	part.Parent = model
	c:add(function()
		part.Parent = nil
		if self._reattach then
			args.reattach()
		end
	end)
	local hidden: { [BasePart]: number } = {}
	for _, body in self._reading.body do
		hidden[body.part] = body.part.Transparency
		body.part.Transparency = 1
	end
	c:add(function()
		for hiddenPart, transparency in hidden do
			hiddenPart.Transparency = transparency
		end
	end)
	args.reattach() -- the deformer now drives the shell as a solid part (the rig's scale)
	local twistBase = model:GetPivot()
	for _, rider in self._reading.riders do
		self._offsets[rider.part] = Vector3.zero
	end
	local deformer = args.deformer()
	if deformer then
		deformer:setOffsets(self._offsets)
	end
	c:add(function()
		local current = args.deformer()
		if current then
			current:setOffsets(nil)
			if self._jolted then
				current:setTwistBase(twistBase)
			end
		end
		local rig = args.rig()
		if self._faceSquish and rig then
			rig:setFace("normal")
		end
	end)
	OrbitCamera.setDefaults(args.orbit, 0, HOME_PITCH_DEG)
	c:add(function()
		OrbitCamera.setDefaults(args.orbit, args.def.inspect.yaw, args.def.inspect.pitch)
	end)
	local wax = self._wax -- user 2026-10-12: with the wax off no wax HUD, no flakes, the soft body sounds only
	local overlay = c:add(KneadOverlay.new(args.stage, { hud = wax }))
	local pool = if wax then c:add(FlakePool.new(args.stage.viewport, FLAKES.cap)) else nil
	local audio = c:add(KneadAudio.new(self._feel, self._pitch, { player = deps.Sound, rng = self._rng, wax = wax }))
	self._live = { overlay = overlay, pool = pool, audio = audio, twistBase = twistBase }
	self._input = KneadController.inputKind(UserInputService:GetLastInputType())
	args.onView(KneadController.view(self._feel, self._input, wax))
	c:add(function()
		args.onView(nil)
	end)
	c:add(UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local kind = KneadController.inputKind(inputType)
		if kind ~= self._input and self._state == "live" then
			self._input = kind
			args.onView(KneadController.view(self._feel, kind, self._wax))
		end
	end))
	refreshHud(self, false)
end

-- One sounding crack (fp.js:676-684): its burst, the jolt and the flakes.
local function crackFx(
	self: Handle,
	kit: Kit,
	live: Live,
	crack: WaxCoat.CrackEvent,
	pivot: CFrame,
	scale: Vector3,
	eye: CFrame, -- the stage camera
	studsPerDu: number,
	kz: number,
	reduced: boolean
)
	local coat, pool = kit.coat, live.pool
	if coat == nil or pool == nil then
		return -- (never: only the coat's cracks come here, and the coat comes with the flakes)
	end
	live.audio:crack(crack.E, crack.intact)
	self._jolt = FlakePool.joltAfter(self._jolt, crack.E, crack.intact, reduced)
	local shellPart = kit.shell.vertexPart[coat.cellVertex[crack.cell]]
	local specs = FlakePool.crackSpecs({
		E = crack.E,
		intact = crack.intact,
		position = pivot:PointToWorldSpace(crack.position * scale),
		normal = pivot:VectorToWorldSpace(crack.normal),
		color = kit.colors[shellPart] or WHITE,
		right = eye.RightVector,
		up = eye.UpVector,
		back = -eye.LookVector,
		studsPerDu = studsPerDu,
		kz = kz,
		reduced = reduced,
	}, self._rng)
	for _, spec in specs do
		pool:spawn(spec)
	end
end

-- The fingertip ring (html:59-62): the mouse over the shell, pressing or stretching; never for touch.
local function updateRing(self: Handle, kit: Kit, live: Live, pivot: CFrame, scale: Vector3)
	local state: string, at: Vector2? = "hidden", nil
	if self._pressing then
		if not self._touch then
			state = KneadMath.ringState(true, kit.body.pulling, true)
			at = self._pointerAt
		end
	else
		local hover = self._hoverAt
		if hover ~= nil then
			if self._hoverDirty then
				self._hoverDirty = false
				local origin, direction = rayAt(self, kit, hover, pivot, scale, true)
				self._over = origin ~= nil and direction ~= nil and hitAt(kit, origin, direction) ~= nil
			end
			state = KneadMath.ringState(false, false, self._over)
			at = hover
		end
	end
	if state ~= self._ring or at ~= self._ringAt then
		self._ring, self._ringAt = state, at
		live.overlay:setRing(state, at)
	end
end

-- One live frame.
local function frame(self: Handle, dt: number)
	local args = self._args
	local kit = self._kit :: Kit
	local live = self._live :: Live
	local body, coat, shell, network = kit.body, kit.coat, kit.shell, kit.network
	local reduced = args.reduced()
	local deformer = args.deformer()
	local scale = if deformer then deformer:getScale() else Vector3.one
	local pivot = args.model:GetPivot()
	local eye = args.stage.camera.CFrame
	local kz = KneadMath.kneadZoom(args.stage.viewport.AbsoluteSize, shell.size)
	local studsPerDu = KneadMath.duToStuds(shell.maxDim, kz)

	-- The press, once a frame like the orbit's drag (fp.js:636): knead while on the toy, stretch off it.
	local moveTo = self._moveTo
	if moveTo ~= nil and self._pressing then
		self._moveTo = nil
		local origin, direction = rayAt(self, kit, moveTo, pivot, scale, false)
		if origin ~= nil and direction ~= nil then
			local hit = if body.pulling then nil else hitAt(kit, origin, direction)
			if KneadMath.moveAction(body.pulling, hit ~= nil) == "fingerMove" and hit ~= nil then
				body:fingerMove(hit.point, hit.normal)
			else
				body:pullTo(origin, direction)
			end
		end
	end

	-- The view eases by itself (fp.js:482-484); a drag stops the settle (fp.js:603).
	local orbit = args.orbit
	if orbit.dragging then
		self._settleLeft = 0
	end
	local pitch, rate = KneadController.tiltTarget(self._crunching, self._settleLeft, orbit.dragging, reduced)
	if pitch ~= nil and rate ~= nil then
		local dYaw, dPitch = KneadMath.tilt(orbit.targetYaw, orbit.targetPitch, 0, pitch, rate, dt)
		OrbitCamera.rotate(orbit, dYaw, dPitch)
	end
	self._settleLeft = math.max(0, self._settleLeft - dt)

	-- The solver, the coat and the lines (spec §3.3, §3.4); the solver alone with the wax off (no coat, no network).
	local started = os.clock()
	if body.active or (coat ~= nil and coat.shine > 0) then
		if body:step(dt) then
			kit.mesh:write(body.written, body.writtenCount, body.px, body.py, body.pz)
			KneadController.rides(self._offsets, self._reading.riders, kit.anchors, shell, body.px, body.py, body.pz)
		end
		if coat and network then
			coat:step(dt)
			for _, crack in coat:takeEvents() do
				crackFx(self, kit, live, crack, pivot, scale, eye, studsPerDu, kz, reduced)
			end
			if coat.touchedCount > 0 then
				kit.canvas:queue(network:reveal(coat.damage, coat.touched, coat.touchedCount))
				coat:clearTouched()
			end
		end
	end
	local solveMs = (os.clock() - started) * 1000
	self._solveMs += (solveMs - self._solveMs) * SOLVE_SMOOTHING
	self._solveMaxMs = math.max(self._solveMaxMs, solveMs)
	if coat and network then
		if not network.finished then
			local budget = CANVAS.buildMsPerFrame[self._quality] / 1000
			local from = os.clock()
			repeat
				local finished = network:buildStep(BUILD_CHUNK)
			until finished or os.clock() - from >= budget
			if network.finished then
				kit.canvas:queue(network:reveal(coat.damage, kit.all, shell.count)) -- what cracked while it built
			end
		end
		kit.canvas:draw(CANVAS.drawPerFrame)
	end

	-- The body's events: the soft kicks to the rig's jiggle, the sound cues to the wax sound.
	local rig = args.rig()
	for _, event in body:takeEvents() do
		if event.kind == "kick" then
			if rig then
				rig:kick(KneadMath.kickPeak(event.amount or 0, self._feel))
			end
		elseif event.kind ~= "squisherKick" then
			live.audio:event(event)
		end
	end
	local squish = body.faceSquish
	if squish ~= self._faceSquish then
		self._faceSquish = squish
		if rig then
			rig:setFace(if squish then "squish" else "normal")
		end
	end
	-- No coat (the wax off, user 2026-10-12): the body bed driven as if there were none: drive 0, nothing intact.
	live.audio:frame(
		dt,
		body.active,
		if coat then coat.drive else 0,
		body.pressSignal,
		if coat then coat.waxLeft else 0
	)

	-- Flakes and the jolt (fp.js:480, 676-684); with the wax off there are none (no cracks raise the jolt).
	local pool = live.pool
	if pool then
		pool:step(dt)
	end
	if self._jolt > JOLT_MIN then
		local size = self._jolt * studsPerDu
		local offset = eye.RightVector * ((self._rng:NextNumber() - 0.5) * size)
			+ eye.UpVector * ((self._rng:NextNumber() - 0.5) * size)
		if deformer then
			deformer:setTwistBase(live.twistBase + offset, true)
		end
		self._jolted = true
		self._jolt = FlakePool.joltDecay(self._jolt, dt)
	elseif self._jolted then
		self._jolt, self._jolted = 0, false
		if deformer then
			deformer:setTwistBase(live.twistBase, true)
		end
	end

	-- The HUD (fp.js:697-702), the ring, the cracks a second.
	self._hudLeft -= dt
	if self._hudLeft <= 0 then
		self._hudLeft = UI_KNEAD.refreshSeconds
		refreshHud(self, true)
		self._hoverDirty = true -- the toy turns and moves under a still pointer
	end
	updateRing(self, kit, live, pivot, scale)
	self._rateTime += dt
	if self._rateTime >= 1 then
		local cracks = if coat then coat.cracks else 0
		self._cracksPerSecond = math.max(0, cracks - self._rateFrom) / self._rateTime
		self._rateFrom, self._rateTime = cracks, 0
	end
end

-- Handle methods -------------------------------------------------------------------------------------------------------

function HandleClass.step(self: Handle, dt: number, _now: number)
	if self._state == "ready" then
		local ok, err = pcall(function()
			goLive(self)
		end)
		if not ok then
			fail(self, err)
			return
		end
	end
	if self._state ~= "live" or dt <= 0 then
		return
	end
	debug.profilebegin(PROFILE)
	local ok, err = pcall(function()
		frame(self, dt)
	end)
	debug.profileend()
	if not ok then
		fail(self, err)
	end
end

function HandleClass.isLive(self: Handle): boolean
	return self._state == "live"
end

function HandleClass.pointerDown(self: Handle, position: Vector2, touch: boolean): boolean
	local kit = self._kit
	if self._state ~= "live" or kit == nil or self._pressing then
		return false
	end
	local ok, hit = pcall(function(): Hit?
		local origin, direction = rayAt(self, kit, position, self._args.model:GetPivot(), scaleOf(self), true)
		if origin == nil or direction == nil then
			return nil
		end
		return hitAt(kit, origin, direction)
	end)
	if not ok or hit == nil then
		return false
	end
	self._pressing, self._touch = true, touch
	self._pointerAt, self._moveTo = position, nil
	kit.body:fingerDown(hit.point, hit.normal)
	return true
end

function HandleClass.pointerMove(self: Handle, position: Vector2)
	if self._pressing then
		self._moveTo = position
		self._pointerAt = position
	end
end

function HandleClass.pointerUp(self: Handle)
	if not self._pressing then
		return
	end
	self._pressing = false
	self._moveTo = nil
	local kit = self._kit
	if kit then
		kit.body:fingerUp()
	end
	-- The mouse stays where it lifted: the ring shows "over" again if it is still on the toy (fp.js:621).
	self._hoverAt = if self._touch then nil else self._pointerAt
	self._hoverDirty = true
end

function HandleClass.hover(self: Handle, position: Vector2?)
	self._hoverAt = position
	self._hoverDirty = true
end

-- The thumb crunch held (fp.js:685-686): on ends the press and the palms and stops the spin; off eases home.
function HandleClass.crunch(self: Handle, on: boolean)
	local kit = self._kit
	if self._state ~= "live" or kit == nil or on == self._crunching then
		return
	end
	local body = kit.body
	self._crunching = on
	if on then
		self._pressing, self._moveTo = false, nil -- SoftBody lifts the finger silently
		if self._palms then
			self._palms = false
			body:palms(false)
		end
		self._args.orbit.inertia = 0
		self._settleLeft = 0
		body:thumbs(true)
	else
		body:thumbs(false)
		self._settleLeft = VIEW.settleSeconds
	end
end

-- The palm squeeze held (fp.js:609, 654): on ends the crunch (no settle).
function HandleClass.palms(self: Handle, on: boolean)
	local kit = self._kit
	if self._state ~= "live" or kit == nil or on == self._palms then
		return
	end
	local body = kit.body
	self._palms = on
	if on and self._crunching then
		self._crunching = false
		body:thumbs(false)
	end
	body:palms(on)
end

-- A fresh coat (fp.js:687): the cracks, lines and atlas reset, the sparkle sound and burst. Nothing with the wax off
-- (user 2026-10-12: no coat, network or flakes).
function HandleClass.rewax(self: Handle)
	local kit, live = self._kit, self._live
	if self._state ~= "live" or kit == nil or live == nil then
		return
	end
	local coat, network, pool = kit.coat, kit.network, live.pool
	if coat == nil or network == nil or pool == nil then
		return
	end
	coat:rewax()
	network:reset()
	kit.canvas:clear()
	kit.canvas:fill()
	live.audio:rewax()
	self._rateFrom = coat.cracks
	local scale = scaleOf(self)
	local shell = kit.shell
	local kz = KneadMath.kneadZoom(self._args.stage.viewport.AbsoluteSize, shell.size)
	local specs = FlakePool.sparkleSpecs(
		self._args.model:GetPivot():PointToWorldSpace(shell.center * scale),
		shell.size.X / 2 * scale.X,
		KneadMath.duToStuds(shell.maxDim, kz),
		self._rng,
		self._args.reduced()
	)
	for _, spec in specs do
		pool:spawn(spec)
	end
	refreshHud(self, true)
end

function HandleClass.cancel(self: Handle)
	self:pointerUp()
	self:crunch(false)
	self:palms(false)
	self._hoverAt = nil
	self._hoverDirty = true
end

-- With the wax off (wax false) the coat and network fields read as before the build (no cracks, no segments).
function HandleClass.debugState(self: Handle): { [string]: any }
	local kit = self._kit
	local live = self._live
	local coat = if kit then kit.coat else nil
	local network = if kit then kit.network else nil
	local pool = if live then live.pool else nil
	return {
		state = self._state,
		reason = self._reason,
		quality = self._quality,
		feel = self._feel,
		wax = self._wax,
		vertices = if kit then kit.shell.count else 0,
		triangles = if kit then kit.shell.triCount else 0,
		cracks = if coat then coat.cracks else 0,
		cracksPerSecond = self._cracksPerSecond,
		waxLeft = if coat then coat.waxLeft else 1,
		crunchiness = if coat then coat.crunchiness else 1,
		crunching = self._crunching,
		palms = self._palms,
		pressing = self._pressing,
		pulling = if kit then kit.body.pulling else false,
		faceSquish = self._faceSquish,
		networkFinished = if network then network.finished else false,
		segments = if network then network.count else 0,
		pendingLines = if kit then kit.canvas:pending() else 0,
		flakes = if pool then pool:count() else 0,
		jolt = self._jolt,
		buildMs = self._buildMs,
		solveMs = self._solveMs,
		solveMaxMs = self._solveMaxMs,
		quota = MeshQuota.holds(QUOTA_KEY),
	}
end

function HandleClass.destroy(self: Handle)
	self._dead = true
	teardown(self, false)
end

-- Public -----------------------------------------------------------------------------------------------------------------

-- Starts the knead on the model Inspect shows (see the header); nil keeps today's squeeze preview.
function KneadController.start(args: Args): Handle?
	local blueprint = SquishyBlueprints[args.def.blueprintId]
	local motion = if blueprint then blueprint.motion else nil
	if motion == nil then
		return nil
	end
	local deformer = args.deformer()
	local reading = KneadController.readModel(args.model, if deformer then deformer:getScale() else Vector3.one)
	if #reading.body == 0 then
		return nil
	end
	if not MeshQuota.tryAcquire(QUOTA_KEY) then
		log:debug("no soft mesh slot: today's squeeze")
		return nil
	end
	local data: HandleData = {
		_args = args,
		_state = "building",
		_reason = nil,
		_feel = motion.feel,
		_pitch = motion.squeeze.pitch or 1,
		_squeezeDepth = motion.squeeze.depth,
		_quality = MeshQuality.forCamera(Workspace.CurrentCamera) or "Low",
		_reading = reading,
		_kit = nil,
		_live = nil,
		_offsets = {},
		_cleanup = Cleanup.new(),
		_rng = Random.new(),
		_reattach = false,
		_dead = false,
		_wax = if args.wax == nil then WAX.enabled else args.wax,
		_pressing = false,
		_touch = false,
		_pointerAt = nil,
		_moveTo = nil,
		_hoverAt = nil,
		_hoverDirty = false,
		_over = false,
		_ring = "hidden",
		_ringAt = nil,
		_crunching = false,
		_palms = false,
		_settleLeft = 0,
		_jolt = 0,
		_jolted = false,
		_faceSquish = false,
		_hudLeft = 0,
		_input = KEYBOARD,
		_buildMs = 0,
		_solveMs = 0,
		_solveMaxMs = 0,
		_rateTime = 0,
		_rateFrom = 0,
		_cracksPerSecond = 0,
	}
	local self = setmetatable(data, HandleClass)
	self._cleanup:add(function()
		MeshQuota.release(QUOTA_KEY)
	end)
	task.spawn(build, self)
	return self
end

-- Test seam (Edit mode): replaces some of the engine-only surfaces (Shell, Canvas, Texture, Sound; nil = the real ones
-- again).
function KneadController.useDeps(overrides: { [string]: any }?)
	if overrides == nil then
		deps = REAL_DEPS
		return
	end
	local merged: { [string]: any } = table.clone(REAL_DEPS :: any)
	for key, value in overrides do
		assert(merged[key] ~= nil, `[SD][Knead] unknown dependency {key}`)
		merged[key] = value
	end
	deps = merged :: any
end

return KneadController
