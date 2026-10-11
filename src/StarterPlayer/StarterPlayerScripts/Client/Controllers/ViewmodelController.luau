--!strict
-- ViewmodelController (client only). The 3D Lab FP viewmodel (spec 2026-10-11 §3; design: sd/fp.js) on the local
-- player's first person, wherever it is (§3.8): while FirstPersonController.look() is set ("duel", "practice" or
-- "lobby", the player's own zoom into the head) and the local player has a held model, a full-screen ViewportFrame in
-- the controller-owned ScreenGui SD_Viewmodel (Config.FirstPerson.gui: DisplayOrder -1, under Roblox's TouchGui and
-- every HUD; ScreenInsets None; not in Config.UI.ScreenGuis) draws two arms (Anim/DesignArm, five parts each) and a
-- "Viewport" copy of the held squishy. The viewport is Active = false and Interactable = false, so a click at the
-- centre is never "over GUI" and touches pass through. Built at each show, destroyed at each hide: hidden, the gui is
-- disabled with 0 parts, no Scheduler job, no mirror and no hold on the world FOV.
--
-- Scene (§3.1): the overlay camera has vertical FOV fovDeg (70) at the origin looking down -Z (fp.js:28); it moves only
-- by the inverse of the whole overlay's idle drift and kick (ViewmodelMath.overlayCamera, fp.js:660). Light: §3.1's
-- closest option (ViewmodelMath.overlayLight). u = overlayStudsPerDu studs per du. The toy is built at u · toyLongestDu
-- / its longest side (fp.js:99; ViewmodelMath.toyBox of a scale-1 probe, once per toy), its box centred on its point.
-- Every motion is the design's: springs (ViewmodelMath.spring, fp.js:16-18) toward targets each frame (fp.js:390-479):
--   * hold (idle): the toy at held.pos breathing (fp.js:396), rotation held.rot; the hands at its sides (sides, rolls
--     ±arm.roll); empty: the hands at rest (X × side), the toy hidden; equip (each show, a new held model, and the toy
--     back in the hand after a throw): the toy from equipFrom at rest, scale backOut(min(1, t / equip.seconds)) (the
--     uniform scale is shown by distance, ViewmodelMath.scaledFrame; the rig's own squeeze stays in its deformer);
--   * squeeze (§3.4), in the hold only (as the design, fp.js:302): the mirrored rig's press amount c > 0: both palms on
--     the shown sides (ViewmodelMath.palms), the toy to the focus pose by the focus share (while c > 0 and
--     focus.lingerSeconds after), camera shake >= squeeze.shake·c;
--   * throws (§3.5): Anim/ThrowTracks by the toy's style, both hands from where they are, the toy's keys and its scale
--     keys, rolls (throwFx), shove's jitter and sling's and shove's shake, the Dragon's roar shake at the start
--     (throwFx.dragonRoarShake, fp.js:305); at the release the toy hides, the overlay kick (kick.release) and the world
--     FOV kick (throwFx.fovKick), shake >= throwFx.shake; at dur the hands go empty until the toy is back in the hand
--     (ThrowTracks.advance keeps step 2's server timing);
--   * Dragon Rush (§3.6): the charge pose over the telegraph (ult; the hands at its sides) and a Neon glow ball at the
--     toy (radius and opacity by the design), shake >= ult.shake·ch and the world FOV pulled by fovPullPerSecond; at
--     the release (ThrowController's "release" phase) the glow goes off at once and the camera reacts once (release
--     kick, FOV kick and shake, fp.js:331, 461) and the toy springs back to the hold (ours stays in the hand); a
--     cancel fades the glow by glowFadeRate.
-- World camera: the FOV goes base + fov·focus.worldFovPerUnit (the fov spring toward focus.worldFovTarget × the focus
-- share, 70° -> 64.5°) through CameraController.setFovOffset (one owner; base back exactly); the design's shake value
-- (falling shake.decayPerSecond a second) through CameraController.shake (ViewmodelMath.shakeFor) only when it rose
-- and settings.cameraShake is on. ReducedMotion: no world FOV change, no tremor or jitter, no breath, no idle drift or
-- kick on the overlay camera, no pop-in overshoot (it grows to 1 and stops), no Rush wobble or glow pulse (DESIGN
-- §9.12). Low tier (MeshQuality "Low" at show, first-person spec 2026-10-10 §5): no idle drift and no breath, so the
-- full-screen viewport only redraws while something acts (Studio 2026-10-11: the overlay cost about 5 ms a frame on a
-- PC while it redrew every frame).
-- One rig, two views (§3.4): HeldSquishyController.setMirror (one callback made at show) hands over the own model's
-- final out and the scale it put on top of the rig's (its idle, equip pop and overlays: none of them is the design's)
-- each frame; each step shows the rig's own S (that scale divided out) on the overlay copy with the toy's scale keys on
-- top (its deformer has no ceiling of its own, so sling's 1.75 shows; no twist target: the twist turns the toy's
-- frame). While mirrored the throw windup does not hold the rig (ThrowController). Every rig mirrored squeezes on
-- Config.FirstPerson.squeezeAxis ("X"); hiding gives it its Catalog axis back (both switch only at rest, SquishRig).
-- Squeezing: DuelSqueeze (Duel) presses the rig through Anim/HoldSqueeze (local only, no Coins) while the toy rests in
-- the hand (idle: no windup, Rush, pop-in or throw); otherwise it passes. PracticeSqueeze (Practice, above the lobby
-- actions) forwards every press while the overlay shows to the lobby Squeeze (ControlsController.pressAction), the paid
-- lobby squeeze (spec 2026-10-11 §5); hidden, it passes. Each sinks End / Cancel only for a Begin it took; a hide ends
-- what it took. Lobby squeezes come in through the mirror only. Touch: SD_ViewmodelPad (Config.FirstPerson.padGui, safe
-- insets) holds one invisible, non-selectable button over the toy's screen box (ViewmodelMath.touchPadRect), which
-- presses padAction() with that finger until it lifts (lobby HUD spec 2026-10-11 §2: the finger's InputObject goes with
-- the press, so the lobby squeeze keeps squeezing while it holds). Sounds: in duels only (elsewhere SqueezeFeel plays
-- them), sfx.squish on the rig's squish event and sfx.squeezeRelease on its pop end, 2D, at the toy's squeeze pitch × a
-- random 0.94-1.06.
-- init() starts Anim/SuperMesh.prepare (the arms' meshes, once per session) so the first overlay has them.
-- Kept from step 2 (spec 2026-10-11 §3.7): while the own invulnUntil (ThrowImpact) runs, the overlay shows at
-- invulnTransparency; lastReleasePoint() puts your own first-person projectile's start on the world camera's ray
-- through where the overlay toy was (ViewmodelMath.releasePoint); the TouchGui fallback (setTouchGuiFallback). Sleeve:
-- the duel side's colour (teamSleeves), colours.sleeve (mint) elsewhere; skin and cuff fixed.
-- Readings: "squeezing" is the mirrored press amount c > 0 (the design's palms down, fp.js:399, 412); the throw starts
-- from idle or the pop-in (a new windup also cuts a finished throw's follow-through short when the toy is back); a
-- cancelled windup goes back to the hold on the springs; the world FOV and the glow stop at a thousandth of a degree /
-- of opacity (below anything shown).
--
-- API
--   ViewmodelController.isShown() -> boolean   the overlay is up
--   ViewmodelController.lastReleasePoint() -> (Vector3?, number?)   the own projectile's start in first person: the
--       world point on the camera ray through the overlay toy where it left the hand, and the size factor D / D₀ (1
--       uncut; below 1 when cover cut the distance). ProjectileRenderer then uses handOffset = point - origin and
--       handScale = factor / flightScale. nil, nil when there is none for the current release.
--   ViewmodelController.toyScreenPoint() -> Vector2?   the overlay toy's centre on screen (pixels from the screen's top
--       left, as Camera:WorldToViewportPoint) for the "+N Coins" popup (spec 2026-10-11 §3.8); nil while hidden or while
--       the toy is out of the hand
--   ViewmodelController.padAction() -> string?   the action the touch pad presses: DuelSqueeze in a duel,
--       PracticeSqueeze in the throw box, the lobby Squeeze in the lobby look (nil while hidden)
--   ViewmodelController.pressPad(state, input?)  the touch pad's press with its finger's InputObject (lobby HUD spec
--       2026-10-11 §2: the lobby squeeze keeps squeezing while that finger holds the pad; tests, Studio)
--   ViewmodelController.debugPose(name?) -> boolean   freezes the overlay for pictures (spec 2026-10-11 §8): "idle",
--       "squeeze" (the rig pressed and held), "windup" (the cocked key), "release" (halfway through the strike),
--       "empty", "popin" (halfway through the pop-in), "rush" (halfway through the charge); nil lets it live again
--   ViewmodelController.setTouchGuiFallback(on)   raises Roblox's TouchGui over the overlay while it shows (when
--       DisplayOrder -1 does not sort under it); off by default
--   ViewmodelController.debugState() / useDeps(overrides?) / init() / destroy()
-- Require direction: it may require FirstPersonController, HeldSquishyController, ThrowController, ControlsController,
-- NetController, StateController, SoundController, UIController and CameraController, never ProjectileRenderer,
-- VfxController, DuelController or PracticeController.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local SquishyBlueprints = require(Shared.Art.SquishyBlueprints)

local Client = script.Parent.Parent
local DesignArm = require(Client.Anim.DesignArm)
local HoldSqueeze = require(Client.Anim.HoldSqueeze)
local MeshQuality = require(Client.Anim.MeshQuality)
local Scheduler = require(Client.Anim.Scheduler)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local SquishRig = require(Client.Anim.SquishRig)
local SuperMesh = require(Client.Anim.SuperMesh)
local ThrowTracks = require(Client.Anim.ThrowTracks)
local Tweens = require(Client.Anim.Tweens)
local ViewmodelMath = require(Client.Anim.ViewmodelMath)
local SquishyCache = require(Client.Models.SquishyCache)
local CameraController = require(script.Parent.CameraController)
local ControlsController = require(script.Parent.ControlsController)
local FirstPersonController = require(script.Parent.FirstPersonController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)
local UIController = require(script.Parent.UIController)

-- Types

type Kind = "equip" | "idle" | "throw" | "ult" | "empty"

type Toy = {
	id: string,
	model: Model,
	deformer: SquishDeformer.Deformer,
	centre: Vector3, -- ViewmodelMath.toyBox's centre in the pivot's space (studs, overlay scale)
	size: Vector3, -- its size (studs, overlay scale)
	hw: number, -- its half width (du): the design's H.hw (fp.js:101)
	ratio: number, -- overlay build scale ÷ held build scale (1): the release hand-off
	pitch: number, -- the design's squeeze pitch (the sounds)
}

-- One arm: the hand point and the roll on their springs (fp.js:73).
type Arm = {
	side: number,
	arm: DesignArm.Arm,
	frames: { [string]: CFrame }, -- DesignArm.partFrames' table, reused
	pos: Vector3, -- du
	vel: Vector3,
	roll: number,
	rollVel: number,
	shoulder: Vector3, -- du, this arm's side
	rest: Vector3, -- du, this arm's side
}

type Throw = {
	track: ThrowTracks.Track,
	clock: ThrowTracks.Clock,
	fromL: Vector3, -- the hands at the press (du): the tracks' first rows
	fromR: Vector3,
	time: number, -- track time this frame
	released: boolean,
	kicked: boolean, -- the release's kick and FOV kick are on
	roar: boolean, -- the Dragon's roar shake is still due (fp.js:305)
}

type Ult = { t: number, ch: number } -- seconds into the charge; the charge share 0-1 over the telegraph

type Pad = {
	gui: ScreenGui,
	button: TextButton,
	box: ViewmodelMath.Rect, -- reused
	rect: ViewmodelMath.Rect, -- reused
	layout: ViewmodelMath.TouchLayout?,
	layoutKey: Vector3?, -- (gui width, gui height, UI scale) the layout was made for
}

type Pose = { name: string, now: number }

type View = {
	cleanup: Cleanup.Cleanup,
	gui: ScreenGui,
	viewport: ViewportFrame,
	camera: Camera,
	left: Arm,
	right: Arm,
	toy: Toy?,
	toyShown: boolean,
	kind: Kind,
	kindT: number, -- seconds in the kind
	toyPos: Vector3, -- du: the toy's point (its box centre) on its springs (fp.js:94)
	toyVel: Vector3,
	toyRot: Vector3, -- design rotation (rx, ry, rz)
	toyRotVel: Vector3,
	sq: Vector3, -- the toy's scale keys on their spring
	sqVel: Vector3,
	scale: number, -- the pop-in's uniform scale
	focus: number, -- the focus share 0-1 (fp.js:78)
	focusVel: number,
	fov: number, -- the world FOV spring (fp.js:49), × focus.worldFovPerUnit degrees
	fovVel: number,
	fovHeld: boolean, -- CameraController holds our offset
	kick: number, -- the overlay kick spring's x (fp.js:49)
	kickVel: number,
	shake: number, -- the design's shake value (fp.js:50)
	since: number, -- seconds since the press amount was last above 0 (the focus linger)
	held: number, -- seconds the press amount has been above 0 (the tremor)
	throw: Throw?,
	ult: Ult?,
	rushReleased: boolean, -- the Rush released this frame: its camera reaction is due (fp.js:331, 461)
	glow: BasePart?,
	glowOpacity: number,
	random: Random,
	mirror: SquishRig.Out?, -- the own model's out (its table, refreshed in place each frame); nil = it rests
	mirrorScale: Vector3, -- what the held model put on top of the rig's S (its idle, pop-in and overlays)
	out: SquishRig.Out, -- what the overlay copy shows (the rig's own out with the scale keys)
	restOut: SquishRig.Out,
	placed: CFrame?, -- the toy model's last written pivot
	toyCam: Vector3?, -- the shown toy's point in camera space (studs), last frame it showed
	release: { at: number, point: Vector3, factor: number }?,
	axisRig: SquishRig.Rig?, -- the rig last set to the first-person axis
	presses: { [string]: number }, -- Begins taken per action (keys and the pad) and not yet ended
	pressRig: SquishRig.Rig?, -- the rig the running duel press went to
	pad: Pad?,
	padInput: InputObject?,
	ghost: number,
	-- Low tier (MeshQuality "Low" at show; first-person spec 2026-10-10 §5): no idle drift and no breath, so at rest
	-- nothing in the full-screen viewport changes and it does not redraw every frame.
	still: boolean,
	pose: Pose?,
	posedRig: SquishRig.Rig?, -- a rig a debug pose pressed or held
	touchGui: ScreenGui?, -- the fallback: Roblox's TouchGui and its own order
	touchGuiOrder: number,
}

-- Constants

local FP = Config.FirstPerson
local U = FP.overlayStudsPerDu
local SPRINGS = FP.springs
local HELD = FP.held
local EQUIP = FP.equip
local FOCUS = FP.focus
local SQUEEZE = FP.squeeze
local THROW = FP.throwFx
local ULT = FP.ult
local IDLE = FP.idle
local SHAKE = FP.shake
local ARM_ROLL = FP.arm.roll
local AXIS: SquishRig.Axis = FP.squeezeAxis :: SquishRig.Axis
local TELEGRAPH_S = Config.Abilities.dragon_rush.telegraphSeconds
local ROAR_TOY = "dragon" -- the design's Dragon roars as its throw starts (fp.js:305)
local EVENTS = SquishRig.EVENTS
local GUI_NAME = "SD_Viewmodel"
local PAD_GUI_NAME = "SD_ViewmodelPad"
local VIEWPORT_NAME = "Overlay"
local PAD_NAME = "SqueezePad"
local GLOW_NAME = "UltGlow"
local DUEL_ACTION = "DuelSqueeze"
local PRACTICE_ACTION = "PracticeSqueeze"
local LOBBY_ACTION = "Squeeze"
local FOV_OWNER = "Viewmodel"
local SOUND_SQUISH = "sfx.squish"
local SOUND_RELEASE = "sfx.squeezeRelease"
local PITCH_VARIANCE = 0.06 -- step 2 §3.5: × a random 0.94-1.06
local CLIENT_FX = "SD_ClientFx"
local PROFILE = "SD_Viewmodel" -- the profiler scope of the overlay step
local FOV_REST_DEG = 1e-3 -- reading: a world FOV offset below this is none (the hold ends, the base back exactly)
local GLOW_GONE = 1e-3 -- reading: a glow opacity below this is none
local POSES: { [string]: boolean } =
	{ idle = true, squeeze = true, windup = true, release = true, empty = true, popin = true, rush = true }
local ZERO = Vector3.zero

-- The side-effecting surfaces the overlay touches; tests swap them (useDeps).
local REAL_DEPS = {
	FirstPerson = FirstPersonController,
	Held = HeldSquishyController,
	Throw = ThrowController,
	Controls = ControlsController,
	Net = NetController,
	State = StateController,
	Sound = SoundController,
	UI = UIController,
	Camera = CameraController,
	Scheduler = Scheduler,
	Cache = SquishyCache,
	Deformer = SquishDeformer,
	Motion = Tweens, -- reducedMotion()
	Workspace = Workspace,
	Players = Players,
}
type Deps = typeof(REAL_DEPS)

-- Module table

local ViewmodelController = {}

-- Private

local log = Log.new("Viewmodel")
local deps: Deps = REAL_DEPS
local cleanup: Cleanup.Cleanup? = nil
local view: View? = nil
local ghostUntil = -math.huge -- server time: the own invulnUntil from ThrowImpact
local touchGuiFallback = false
local longest: { [string]: number } = {} -- per toy: the longest side of its scale-1 "Viewport" build's toyBox

local function localPlayer(): Player?
	return deps.Players.LocalPlayer
end

local function guarded(label: string, fn: () -> ...any)
	local ok, err = pcall(fn)
	if not ok then
		log:error(`{label} failed:`, err)
	end
end

local function playSound(key: string, toy: Toy)
	local ok, err = pcall(deps.Sound.play, key, { pitch = toy.pitch, variance = PITCH_VARIANCE })
	if not ok then
		log:warn(`sound {key} failed:`, err)
	end
end

local function sideOf(v: Vector3, side: number): Vector3
	return Vector3.new(v.X * side, v.Y, v.Z)
end

local function setKind(v: View, kind: Kind)
	v.kind = kind
	v.kindT = 0
end

-- The pop-in (fp.js:96-107): the toy springs up from equipFrom at rest; its scale grows by backOut over equip.seconds.
local function equip(v: View)
	setKind(v, "equip")
	v.toyPos, v.toyVel = FP.equipFrom, ZERO
end

-- The camera shake value rises to `value` (fp.js: shake = max(shake, value)).
local function raiseShake(v: View, value: number)
	if value > v.shake then
		v.shake = value
	end
end

-- The toy -------------------------------------------------------------------------------------------------------------

-- The longest side of a toy's scale-1 "Viewport" build (the design's box, fp.js:99), measured once per toy.
local function longestOf(id: string): number
	local known = longest[id]
	if known then
		return known
	end
	local probe = deps.Cache.clone(id, "Viewport", 1)
	local _, size = ViewmodelMath.toyBox(probe)
	probe:Destroy()
	local value = math.max(size.X, size.Y, size.Z, 1e-3)
	longest[id] = value
	return value
end

local function destroyToy(v: View)
	local toy = v.toy
	v.toy = nil
	v.toyShown = false
	v.placed = nil
	if toy then
		toy.deformer:destroy()
		toy.model:Destroy()
	end
end

-- The overlay copy of the local player's held squishy (unparented until it shows), largest side toyLongestDu.
local function buildToy(v: View, player: Player)
	destroyToy(v)
	local id = deps.Held.getSquishyId(player)
	local def = if id then Catalog.get(id) else nil
	if id == nil or def == nil then
		return
	end
	local scale = U * FP.toyLongestDu / longestOf(id) -- design: fp.js:99
	local model = deps.Cache.clone(id, "Viewport", scale)
	model:PivotTo(CFrame.identity)
	local centre, size = ViewmodelMath.toyBox(model)
	local blueprint = SquishyBlueprints[def.blueprintId]
	local squeeze = blueprint and (blueprint.motion :: SquishRig.Motion).squeeze
	v.toy = {
		id = id,
		model = model,
		-- No ceiling of its own: fillOut clamps the rig's part, and the design's scale keys go on top (sling 1.75).
		deformer = deps.Deformer.attach(model, { scaleMax = math.huge }),
		centre = centre,
		size = size,
		hw = size.X / 2 / U,
		ratio = scale,
		pitch = if squeeze and squeeze.pitch then squeeze.pitch else 1,
	}
	v.mirror, v.mirrorScale = nil, Vector3.one
end

local function showToy(v: View, on: boolean)
	local toy = v.toy
	local shown = on and toy ~= nil
	if shown == v.toyShown then
		return
	end
	v.toyShown = shown
	if toy then
		toy.model.Parent = if shown then v.viewport else nil
	end
end

-- The mirror (§3.4): the own model's final out and the scale on top of its rig's S each frame (kept, applied in the
-- step), nil = it rests. Sounds in duels.
local function onMirror(v: View, out: SquishRig.Out?, scale: Vector3)
	if view ~= v then
		return
	end
	v.mirror, v.mirrorScale = out, scale
	local toy = v.toy
	if out == nil or toy == nil or deps.FirstPerson.look() ~= "duel" then
		return -- lobby and practice squeezes sound through SqueezeFeel
	end
	local events = out.events
	if bit32.band(events, EVENTS.squish) ~= 0 then
		playSound(SOUND_SQUISH, toy)
	end
	if bit32.band(events, EVENTS.popEnd) ~= 0 then
		playSound(SOUND_RELEASE, toy)
	end
end

-- What the overlay copy shows this frame: the rig's own S (the held model's idle, pop-in and overlay scale divided out:
-- the design's toy has none of them, fp.js:396, 403) in the deformer's limits, the toy's scale keys on top.
local function fillOut(v: View): SquishRig.Out
	local src, scale = v.restOut, Vector3.one
	local mirror = v.mirror
	if mirror then
		src, scale = mirror, v.mirrorScale
	end
	local out = v.out
	out.S = deps.Deformer.clampScale(src.S / scale) * v.sq
	out.twist = src.twist
	out.face, out.blink, out.cheek = src.face, src.blink, src.cheek
	out.sections, out.sectionsOn = src.sections, src.sectionsOn
	return out
end

-- The rig: the first-person axis, presses ----------------------------------------------------------------------------

local function catalogAxis(player: Player): SquishRig.Axis?
	local id = deps.Held.getSquishyId(player)
	local def = if id then Catalog.get(id) else nil
	return if def then (def.anim.squeezeAxis :: any) :: SquishRig.Axis else nil
end

-- Every rig the overlay mirrors squeezes on the first-person axis (a rebuilt model has a new rig).
local function keepAxis(v: View, player: Player)
	local rig = deps.Held.getRig(player)
	if rig ~= v.axisRig then
		v.axisRig = rig
		if rig then
			rig:setAxis(AXIS)
		end
	end
end

-- The toy rests in the hand: a duel squeeze may start (no windup, Rush, pop-in or throw; not posed).
local function canSqueeze(v: View): boolean
	if v.kind ~= "idle" or not v.toyShown or v.pose ~= nil then
		return false
	end
	local tau, _, _, _, cancelled = deps.Throw.localWindup()
	local ultPhase = deps.Throw.localUlt()
	return (tau == nil or cancelled) and ultPhase == nil
end

-- Ends every press the overlay took (hide, a rebuilt model): the rig lets go as on a key release; a forwarded lobby
-- squeeze gets its End.
local function endPresses(v: View)
	local rig = v.pressRig
	local forwarded = v.presses[PRACTICE_ACTION] ~= nil
	v.pressRig = nil
	table.clear(v.presses)
	if rig then
		HoldSqueeze.finish(rig)
	end
	if forwarded then
		deps.Controls.pressAction(LOBBY_ACTION, Enum.UserInputState.End)
	end
end

-- Counts an End / Cancel against the Begins `action` took; false when it took none.
local function endTaken(v: View, action: string): boolean
	local taken: number? = v.presses[action]
	if taken == nil then
		return false
	end
	if taken > 1 then
		v.presses[action] = taken - 1
	else
		v.presses[action] = nil
	end
	return true
end

-- DuelSqueeze: the toy in the hand squeezes through HoldSqueeze (local only); otherwise the press passes.
local function duelHandler(state: Enum.UserInputState, _input: InputObject?): boolean?
	local v = view
	if v == nil then
		return false
	end
	if state == Enum.UserInputState.Begin then
		local player = localPlayer()
		local rig = if player and canSqueeze(v) then deps.Held.getRig(player) else nil
		if rig == nil then
			return false -- dropped, not queued: third-person flow and the other actions see it
		end
		if v.pressRig ~= rig then
			v.pressRig = rig
			HoldSqueeze.begin(rig) -- or merges into the running squeeze (the mashing cap)
		end
		v.presses[DUEL_ACTION] = (v.presses[DUEL_ACTION] or 0) + 1
		return true
	end
	if not endTaken(v, DUEL_ACTION) then
		return false
	end
	local player = localPlayer()
	if v.presses[DUEL_ACTION] == nil and player then
		local rig = v.pressRig
		v.pressRig = nil
		if rig and rig == deps.Held.getRig(player) then
			HoldSqueeze.finish(rig)
		end
	end
	return true
end

-- PracticeSqueeze (spec 2026-10-11 §5): while the overlay shows, the paid lobby squeeze. The key goes with the press,
-- so a held F, E or ButtonX keeps squeezing as in the lobby.
local function practiceHandler(state: Enum.UserInputState, input: InputObject?): boolean?
	local v = view
	if v == nil then
		return false
	end
	if state == Enum.UserInputState.Begin then
		v.presses[PRACTICE_ACTION] = (v.presses[PRACTICE_ACTION] or 0) + 1
		deps.Controls.pressAction(LOBBY_ACTION, state, input)
		return true
	end
	if not endTaken(v, PRACTICE_ACTION) then
		return false
	end
	deps.Controls.pressAction(LOBBY_ACTION, state, input)
	return true
end

-- Throws and the Rush ------------------------------------------------------------------------------------------------

-- The release hand-off point from where the toy last showed; nil when it never showed.
local function captureRelease(v: View, at: number)
	local toy, toyCam = v.toy, v.toyCam
	local camera = deps.Workspace.CurrentCamera
	if toy == nil or toyCam == nil or camera == nil or toyCam.Magnitude <= 0 then
		return
	end
	local cf = camera.CFrame
	local reach = toyCam.Magnitude / toy.ratio
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	local player = localPlayer()
	local character = if player then player.Character else nil
	if character then
		table.insert(ignore, character)
	end
	local fx = deps.Workspace:FindFirstChild(CLIENT_FX)
	if fx then
		table.insert(ignore, fx)
	end
	params.FilterDescendantsInstances = ignore
	local hit = deps.Workspace:Raycast(cf.Position, cf:VectorToWorldSpace(toyCam.Unit) * reach, params)
	local point, factor = ViewmodelMath.releasePoint(cf, toyCam, toy.ratio, if hit then hit.Distance else nil)
	v.release = { at = at, point = point, factor = factor }
end

-- empty -> equip once the toy is in the hand again, equip -> idle at its end, back to empty when it leaves the hand.
local function stepKind(v: View, holding: boolean)
	local kind = v.kind
	if kind == "throw" or kind == "ult" then
		return
	end
	if not holding then
		if kind ~= "empty" then
			setKind(v, "empty")
		end
	elseif kind == "empty" then
		equip(v)
	elseif kind == "equip" and v.kindT >= EQUIP.seconds then
		setKind(v, "idle")
	end
end

-- One frame of the local throw (ThrowController.localWindup): a new windup starts a track from where the hands are
-- (fp.js:305); the release (the server's releaseStart) hides the toy; at dur the hands go empty.
local function stepThrow(v: View, serverNow: number, holding: boolean)
	local tau, windup, releaseAt, releaseStart, cancelled = deps.Throw.localWindup()
	local throw = v.throw
	local fresh = tau ~= nil and releaseStart == nil and not cancelled
	local free = v.kind == "idle" or v.kind == "equip" or (throw ~= nil and throw.released)
	if fresh and free and holding and v.toy then
		throw = {
			track = ThrowTracks.get(ThrowTracks.styleOf((v.toy :: Toy).id)),
			clock = ThrowTracks.newClock(),
			fromL = v.left.pos,
			fromR = v.right.pos,
			time = 0,
			released = false,
			kicked = false,
			roar = (v.toy :: Toy).id == ROAR_TOY,
		}
		v.throw = throw
		v.release = nil
		setKind(v, "throw")
	end
	if throw == nil or v.kind ~= "throw" then
		return
	end
	local current = throw :: Throw
	if not current.released and (cancelled or tau == nil) then
		v.throw = nil -- cancelled (or gone without a release): back to the hold on the springs
		setKind(v, if holding then "idle" else "empty")
		return
	end
	current.time = ThrowTracks.advance(current.clock, current.track, tau, windup, releaseAt, serverNow)
	if not current.released and releaseStart ~= nil then
		current.released = true
		local release = v.release
		if release == nil or release.at ~= releaseStart then
			captureRelease(v, releaseStart) -- unless ProjectileRenderer already asked (lastReleasePoint)
		end
	end
	if current.time >= current.track.dur then
		v.throw = nil
		setKind(v, "empty")
	end
end

-- One frame of the local Dragon Rush's charge (ThrowController.localUlt): ch over the game's telegraph.
local function stepUlt(v: View, dt: number, serverNow: number, holding: boolean)
	local phase, telegraphEndsAt = deps.Throw.localUlt()
	local charging = phase == "cast" or phase == "telegraph"
	local ult = v.ult
	local kind: Kind = v.kind
	if charging and holding and v.toy and (kind == "idle" or kind == "equip" or kind == "ult") then
		if ult == nil then
			ult = { t = 0, ch = 0 }
			v.ult = ult
			setKind(v, "ult")
		end
		local u = ult :: Ult
		u.t += dt
		u.ch = math.min(1, u.ch + dt / TELEGRAPH_S)
		if telegraphEndsAt then
			u.ch = math.max(u.ch, math.clamp(1 - (telegraphEndsAt - serverNow) / TELEGRAPH_S, 0, 1))
		end
	elseif ult then
		v.ult = nil -- released or cancelled: the toy springs back to the hold
		v.rushReleased = phase == "release" -- a release's camera reaction comes in this frame's action (fp.js:331)
		if kind == ("ult" :: Kind) then
			setKind(v, if holding then "idle" else "empty")
		end
	end
end

-- The Rush's glow ball (fp.js:456-458, 466): at the toy, while charging; fading once over. No radius pulse under
-- ReducedMotion (DESIGN §9.12: nothing faster than 3 Hz).
local function stepGlow(v: View, dt: number, reduced: boolean)
	local ult = v.ult
	if ult then
		v.glowOpacity = ULT.glowOpacity * ViewmodelMath.ease(ult.ch)
	else
		v.glowOpacity *= math.exp(-ULT.glowFadeRate * dt)
		if v.glowOpacity < GLOW_GONE then
			v.glowOpacity = 0
		end
	end
	local glow = v.glow
	if glow == nil then
		if ult == nil then
			return
		end
		local part = Instance.new("Part")
		part.Name = GLOW_NAME
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
		part.Color = ULT.glowColour
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = v.viewport
		v.glow = part
		glow = part
	end
	local ball = glow :: BasePart
	if ult then
		local pulse = if reduced then 0 else ULT.glowPulse * math.sin(ULT.glowPulseRate * ult.t)
		local radius = ULT.glowRadius + pulse
		ball.Size = Vector3.one * (2 * radius * U)
		ball.CFrame = CFrame.new(v.toyPos * U) -- the toy's spring position before this frame's step (fp.js:457)
	end
	local transparency = 1 - v.glowOpacity
	if ball.Transparency ~= transparency then
		ball.Transparency = transparency
	end
end

-- The frame ------------------------------------------------------------------------------------------------------------

-- One hand on its springs toward `target` and `roll` (fp.js:73, 76); a debug pose puts it there.
local function stepArm(arm: Arm, target: Vector3, roll: number, dt: number, settle: boolean)
	if settle then
		arm.pos, arm.vel, arm.roll, arm.rollVel = target, ZERO, roll, 0
		return
	end
	arm.pos, arm.vel = ViewmodelMath.spring(arm.pos, arm.vel, target, SPRINGS.hand, dt)
	arm.roll, arm.rollVel = ViewmodelMath.spring(arm.roll, arm.rollVel, roll, SPRINGS.roll, dt)
end

-- The targets of one frame (fp.js:390-468) put on the springs (fp.js:470-478): the toy, its scale keys, the pop-in, the
-- two hands and their rolls. Returns whether the toy hides. `settle` (a debug pose) puts every spring on its target.
local function stepAction(v: View, dt: number, now: number, reduced: boolean, settle: boolean): boolean
	local toy = v.toy
	local hw = if toy then toy.hw else 0
	local src = v.mirror
	local c = if src then math.clamp(src.pressAmount, 0, 1) else 0
	if c > 0 then
		v.since = 0
		v.held += dt
	else
		v.since += dt
		v.held = 0
	end
	local kind = v.kind
	local resting = kind == "idle" -- the design squeezes and focuses only from idle (fp.js:302, 399)
	local wantFocus = resting and (c > 0 or v.since < FOCUS.lingerSeconds)
	v.focus, v.focusVel = ViewmodelMath.spring(v.focus, v.focusVel, if wantFocus then 1 else 0, SPRINGS.focus, dt)
	if settle then
		v.focus, v.focusVel = if wantFocus then 1 else 0, 0
	end
	local breath = if reduced or v.still then 0 else IDLE.breath * math.sin(IDLE.breathRate * now)
	local toyP = (HELD.pos + Vector3.new(0, breath, 0)):Lerp(FOCUS.pos, v.focus)
	local toyR = HELD.rot:Lerp(FOCUS.rot, v.focus)
	local sq = Vector3.one
	local scale = 1
	local left: Vector3?, right: Vector3? = nil, nil
	local lRoll, rRoll = ARM_ROLL, -ARM_ROLL
	local hide = false
	local throw, ult = v.throw, v.ult
	if kind == "equip" then
		local u = math.min(1, v.kindT / EQUIP.seconds)
		local grown = math.max(EQUIP.minScale, ViewmodelMath.backOut(u))
		scale = if reduced then math.min(1, grown) else grown -- ReducedMotion: no overshoot
	elseif kind == "throw" and throw then
		local track, t = throw.track, throw.time
		toyP, toyR = ThrowTracks.toyAt(track, t)
		sq = ThrowTracks.scaleAt(track, t)
		left, right = ThrowTracks.handsAt(track, t, throw.fromL, throw.fromR)
		rRoll = -(ARM_ROLL + (if t < track.rel then THROW.rollCocked else 0))
		lRoll = THROW.rollL
		if throw.roar then
			throw.roar = false
			raiseShake(v, THROW.dragonRoarShake) -- design: fp.js:181, 305
		end
		if track.name == "shove" and t < THROW.shoveUntil then
			local j = if reduced then 0 else THROW.shoveJitter
			toyP += Vector3.new(v.random:NextNumber(-j, j), v.random:NextNumber(-j, j), 0)
			raiseShake(v, THROW.shoveShake)
		elseif track.name == "sling" and t > THROW.slingFrom and t < THROW.slingUntil then
			raiseShake(v, THROW.slingShake * (t / THROW.slingUntil))
		end
		if throw.released then
			hide = true
			if not throw.kicked then
				throw.kicked = true
				v.toyPos = toyP -- design: fp.js:437
				v.kickVel += FP.kick.release
				v.fovVel += THROW.fovKick
				raiseShake(v, THROW.shake)
			end
		end
	elseif kind == "ult" and ult then
		local ch = ult.ch
		local e = ViewmodelMath.ease(ch)
		toyP = toyP:Lerp(ULT.pos, e)
		toyR = Vector3.new(ULT.pitch * e, 0, 0)
		local wobble = if reduced then 0 else ULT.wobble * math.sin(ULT.wobbleRate * ult.t) -- no 40 rad/s under RM
		sq = Vector3.new(1 + wobble * ch, 1 - ULT.squashY * ch, 1)
		if ch < 1 and not reduced then
			local j = ULT.jitter * ch
			toyP += Vector3.new(v.random:NextNumber(-j, j), v.random:NextNumber(-j, j), 0)
		end
		raiseShake(v, ULT.shake * ch)
		v.fovVel -= ULT.fovPullPerSecond * dt
	elseif kind == "empty" then
		left, right = v.left.rest, v.right.rest
		hide = true
	end
	if v.rushReleased then
		-- The Rush's release (design: fp.js:331, 461): the glow off at once, the overlay and world FOV kicks, the shake.
		v.rushReleased = false
		v.glowOpacity = 0
		v.kickVel += ULT.releaseKick
		v.fovVel += ULT.releaseFovKick
		raiseShake(v, ULT.releaseShake)
	end
	if resting and c > 0 and toy then
		local mirror = src :: SquishRig.Out
		local k = v.mirrorScale.X -- the rig's own X: S.X / k (palms reads only X)
		local dx
		left, right, lRoll, rRoll, dx = ViewmodelMath.palms(toyP, hw, mirror.S, k, c, v.held, now, reduced)
		toyP += Vector3.new(dx, 0, 0)
		raiseShake(v, SQUEEZE.shake * c)
	end
	if left == nil or right == nil then
		left, right = ViewmodelMath.sides(toyP, hw)
	end
	stepGlow(v, dt, reduced)
	-- The springs (fp.js:470-478).
	if settle then
		v.toyPos, v.toyVel, v.toyRot, v.toyRotVel, v.sq, v.sqVel = toyP, ZERO, toyR, ZERO, sq, ZERO
	else
		v.toyPos, v.toyVel = ViewmodelMath.spring(v.toyPos, v.toyVel, toyP, SPRINGS.toyPos, dt)
		v.toyRot, v.toyRotVel = ViewmodelMath.spring(v.toyRot, v.toyRotVel, toyR, SPRINGS.toyRot, dt)
		v.sq, v.sqVel = ViewmodelMath.spring(v.sq, v.sqVel, sq, SPRINGS.toyScale, dt)
	end
	v.scale = scale
	stepArm(v.left, left :: Vector3, lRoll, dt, settle)
	stepArm(v.right, right :: Vector3, rRoll, dt, settle)
	return hide
end

local function drawArm(arm: Arm)
	DesignArm.partFrames(arm.pos, arm.shoulder, arm.roll, arm.side, U, arm.frames)
	DesignArm.apply(arm.arm, arm.frames)
end

-- Writes the arms and the toy for this frame through the overlay camera `cameraCF`.
local function draw(v: View, cameraCF: CFrame)
	drawArm(v.left)
	drawArm(v.right)
	local toy = v.toy
	if toy == nil or not v.toyShown then
		return
	end
	-- The toy's point and rotation, the twist about its own Y, then the box centre (as shown) back onto the point.
	local out = fillOut(v)
	local frame = ViewmodelMath.toyFrame(v.toyPos, v.toyRot, U) * CFrame.Angles(0, out.twist, 0)
	local placed = ViewmodelMath.scaledFrame(frame, cameraCF.Position, v.scale) * CFrame.new(-toy.centre * out.S)
	if placed ~= v.placed then
		v.placed = placed
		toy.model:PivotTo(placed)
	end
	toy.deformer:apply(out)
	v.toyCam = cameraCF:PointToObjectSpace(frame.Position)
end

local function hidePad(v: View)
	local pad = v.pad
	if pad then
		pad.button.Visible = false
	end
	local input = v.padInput
	if input then
		v.padInput = nil
		ViewmodelController.pressPad(Enum.UserInputState.End, input)
	end
end

local function ensurePad(v: View): Pad
	local existing = v.pad
	if existing then
		return existing
	end
	local gui = deps.UI.screenGui(PAD_GUI_NAME, FP.padGui :: any)
	gui.Enabled = true
	local button = Instance.new("TextButton")
	button.Name = PAD_NAME
	button.Text = ""
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Selectable = false
	button.Visible = false
	button.Parent = gui
	local pad: Pad = {
		gui = gui,
		button = button,
		box = { x = 0, y = 0, w = 0, h = 0 },
		rect = { x = 0, y = 0, w = 0, h = 0 },
		layout = nil,
		layoutKey = nil,
	}
	v.pad = pad
	v.cleanup:add(button)
	v.cleanup:add(function()
		gui.Enabled = false
	end)
	v.cleanup:add(button.InputBegan:Connect(function(input: InputObject)
		if view == v and v.padInput == nil and input.UserInputType == Enum.UserInputType.Touch then
			v.padInput = input
			ViewmodelController.pressPad(Enum.UserInputState.Begin, input)
		end
	end))
	return pad
end

-- Touch only, while the toy shows: the pad over its screen box, clear of the touch controls; a lifted finger ends it.
local function stepPad(v: View, cameraCF: CFrame)
	local toy = v.toy
	if deps.Controls.preferredInput() ~= Enum.PreferredInput.Touch or toy == nil or not v.toyShown then
		hidePad(v)
		return
	end
	local input = v.padInput
	if
		input
		and (input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel)
	then
		v.padInput = nil
		ViewmodelController.pressPad(Enum.UserInputState.End, input)
	end
	local pad = ensurePad(v)
	local screen = v.viewport.AbsoluteSize
	local padSize = pad.gui.AbsoluteSize
	if screen.X <= 0 or screen.Y <= 0 or padSize.X <= 0 or padSize.Y <= 0 then
		return
	end
	local frame = ViewmodelMath.toyFrame(v.toyPos, v.toyRot, U)
	local box =
		ViewmodelMath.screenBox(cameraCF:ToObjectSpace(frame), toy.size * v.out.S * v.scale, screen, FP.fovDeg, pad.box)
	local uiScale = deps.UI.scale()
	local key = Vector3.new(padSize.X, padSize.Y, uiScale)
	if pad.layoutKey ~= key then
		pad.layoutKey = key
		pad.layout = deps.Controls.touchLayout(padSize, uiScale, nil)
	end
	local rect: ViewmodelMath.Rect? = nil
	if box then
		local offset = v.viewport.AbsolutePosition - pad.gui.AbsolutePosition
		box.x += offset.X
		box.y += offset.Y
		rect = ViewmodelMath.touchPadRect(box, padSize, pad.layout :: ViewmodelMath.TouchLayout, pad.rect)
	end
	if rect then
		-- The pad gui holds UIController's UIScale: offsets are in unscaled pixels.
		pad.button.Position = UDim2.fromOffset(rect.x / uiScale, rect.y / uiScale)
		pad.button.Size = UDim2.fromOffset(rect.w / uiScale, rect.h / uiScale)
		pad.button.Visible = true
	else
		pad.button.Visible = false
	end
end

local function sleeveColour(): Color3
	if deps.FirstPerson.look() == "duel" then
		local duel = deps.State.duel()
		local sleeve = if duel then (FP.teamSleeves :: any)[duel.you.side] else nil
		if sleeve then
			return sleeve
		end
	end
	return FP.colours.sleeve
end

local function recolour(v: View)
	local sleeve = sleeveColour()
	DesignArm.setColours(v.left.arm, sleeve)
	DesignArm.setColours(v.right.arm, sleeve)
end

local function setTouchGui(v: View, raise: boolean)
	if raise and v.touchGui == nil then
		local player = localPlayer()
		local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
		local touch = if playerGui then playerGui:FindFirstChild("TouchGui") else nil
		if touch and touch:IsA("ScreenGui") then
			v.touchGui, v.touchGuiOrder = touch, touch.DisplayOrder
			touch.DisplayOrder = FP.touchGuiFallbackOrder
		end
	elseif not raise and v.touchGui then
		local touch = v.touchGui :: ScreenGui
		v.touchGui = nil
		touch.DisplayOrder = v.touchGuiOrder
	end
end

-- The settings gate the camera shake shares with VfxController's.
local function shakeEnabled(): boolean
	local settings = deps.State.settings()
	return not (type(settings) == "table" and settings.cameraShake == false)
end

-- The world camera: the FOV offset through CameraController (none under ReducedMotion), and the shake when it rose.
local function stepWorldCamera(v: View, reduced: boolean, shakeFrom: number)
	local offset = if reduced then 0 else v.fov * FOCUS.worldFovPerUnit
	if math.abs(offset) < FOV_REST_DEG then
		offset = 0
	end
	if offset ~= 0 or v.fovHeld then
		v.fovHeld = deps.Camera.setFovOffset(FOV_OWNER, offset)
	end
	if v.shake > shakeFrom and not reduced and shakeEnabled() then
		local amplitudeDeg, seconds = ViewmodelMath.shakeFor(v.shake)
		local ok, err = pcall(deps.Camera.shake, amplitudeDeg, seconds)
		if not ok then
			log:warn("shake failed:", err)
		end
	end
end

-- A frozen debug pose (spec 2026-10-11 §8): the state it shows, set once (the step then runs with dt 0 at a fixed clock
-- and puts every spring on its target).
local function applyPose(v: View, name: string)
	local toy = v.toy
	local player = localPlayer()
	local rig = if player then deps.Held.getRig(player) else nil
	v.throw, v.ult = nil, nil
	setKind(v, if name == "empty" then "empty" else "idle")
	if rig and name == "squeeze" then
		v.posedRig = rig
		rig:press()
	end
	if (name == "windup" or name == "release") and toy then
		-- The design's throw does not squash the toy (fp.js:430-443): only the track's keys.
		local track = ThrowTracks.get(ThrowTracks.styleOf(toy.id))
		local fromL, fromR = ViewmodelMath.sides(HELD.pos, toy.hw)
		v.throw = {
			track = track,
			clock = ThrowTracks.newClock(),
			fromL = fromL,
			fromR = fromR,
			time = if name == "windup" then track.cock else (track.cock + track.rel) / 2,
			released = false,
			kicked = false,
			roar = false,
		}
		setKind(v, "throw")
	elseif name == "popin" then
		setKind(v, "equip")
		v.kindT = EQUIP.seconds / 2
	elseif name == "rush" then
		v.ult = { t = TELEGRAPH_S / 2, ch = 0.5 }
		setKind(v, "ult")
	end
end

local function step(v: View, dt: number, now: number): boolean
	if view ~= v then
		return false
	end
	local player = localPlayer()
	if player == nil then
		return true
	end
	debug.profilebegin(PROFILE)
	local serverNow = deps.Workspace:GetServerTimeNow()
	local reduced = deps.Motion.reducedMotion()
	keepAxis(v, player)
	local posed = v.pose
	if posed then
		dt, now = 0, posed.now -- frozen
	else
		local holding = v.toy ~= nil and deps.Held.isHolding(player)
		stepKind(v, holding)
		stepThrow(v, serverNow, holding)
		stepUlt(v, dt, serverNow, holding)
		v.kindT += dt
	end
	-- The camera springs first (fp.js:652): the kick back to rest, the world FOV toward the focus, the shake falling.
	v.kick, v.kickVel = ViewmodelMath.spring(v.kick, v.kickVel, 0, SPRINGS.kick, dt)
	v.fov, v.fovVel = ViewmodelMath.spring(v.fov, v.fovVel, FOCUS.worldFovTarget * v.focus, SPRINGS.fov, dt)
	v.shake = math.max(0, v.shake - SHAKE.decayPerSecond * dt)
	local shakeFrom = v.shake
	local hide = stepAction(v, dt, now, reduced, posed ~= nil)
	if posed then
		v.fov, v.fovVel, v.kick, v.kickVel = FOCUS.worldFovTarget * v.focus, 0, 0, 0
	end
	showToy(v, not hide)
	-- The low tier keeps the kick (an action) and drops the idle drift (its time held at 0: sin(0) = 0).
	local cameraCF = if reduced
		then CFrame.identity
		else ViewmodelMath.overlayCamera(if v.still then 0 else now, v.kick, U)
	v.camera.CFrame = cameraCF
	draw(v, cameraCF)
	stepWorldCamera(v, reduced, shakeFrom)
	local ghost = if serverNow < ghostUntil then FP.invulnTransparency else 0
	if ghost ~= v.ghost then
		v.ghost = ghost
		v.viewport.ImageTransparency = ghost
	end
	stepPad(v, cameraCF)
	debug.profileend()
	return true
end

-- Show and hide ---------------------------------------------------------------------------------------------------------

local function newArm(side: number, viewport: ViewportFrame): Arm
	return {
		side = side,
		arm = DesignArm.new(side, viewport, U),
		frames = {},
		pos = sideOf(FP.arm.startPos, side), -- design: fp.js:73
		vel = ZERO,
		roll = 0,
		rollVel = 0,
		shoulder = sideOf(FP.shoulder, side),
		rest = sideOf(FP.rest, side),
	}
end

local function newView(gui: ScreenGui, viewport: ViewportFrame, camera: Camera): View
	return {
		cleanup = Cleanup.new(),
		gui = gui,
		viewport = viewport,
		camera = camera,
		left = newArm(-1, viewport),
		right = newArm(1, viewport),
		toy = nil,
		toyShown = false,
		kind = "empty",
		kindT = 0,
		toyPos = FP.equipFrom,
		toyVel = ZERO,
		toyRot = HELD.rot,
		toyRotVel = ZERO,
		sq = Vector3.one,
		sqVel = ZERO,
		scale = 1,
		focus = 0,
		focusVel = 0,
		fov = 0,
		fovVel = 0,
		fovHeld = false,
		kick = 0,
		kickVel = 0,
		shake = 0,
		since = math.huge,
		held = 0,
		throw = nil,
		ult = nil,
		rushReleased = false,
		glow = nil,
		glowOpacity = 0,
		random = Random.new(),
		mirror = nil,
		mirrorScale = Vector3.one,
		out = SquishRig.newOut(),
		restOut = SquishRig.newOut(),
		placed = nil,
		toyCam = nil,
		release = nil,
		axisRig = nil,
		presses = {},
		pressRig = nil,
		pad = nil,
		padInput = nil,
		ghost = 0,
		still = MeshQuality.forCamera(deps.Workspace.CurrentCamera) == "Low",
		pose = nil,
		posedRig = nil,
		touchGui = nil,
		touchGuiOrder = 0,
	}
end

-- The overlay's ViewportFrame and camera in SD_Viewmodel (made once per gui, kept with 0 parts while hidden).
local function overlayOf(gui: ScreenGui): (ViewportFrame, Camera)
	local existing = gui:FindFirstChild(VIEWPORT_NAME)
	local existingCamera = if existing then existing:FindFirstChildOfClass("Camera") else nil
	if existing and existing:IsA("ViewportFrame") and existingCamera then
		return existing, existingCamera
	end
	local ambient, lightColor, lightDirection = ViewmodelMath.overlayLight()
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = VIEWPORT_NAME
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Active = false
	viewport.Interactable = false
	viewport.Selectable = false
	viewport.Ambient = ambient
	viewport.LightColor = lightColor
	viewport.LightDirection = lightDirection
	local camera = Instance.new("Camera")
	camera.FieldOfView = FP.fovDeg -- design: fp.js:28
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Parent = gui
	return viewport, camera
end

local function hide()
	local v = view
	if v == nil then
		return
	end
	view = nil
	local player = localPlayer()
	guarded("hide", function()
		endPresses(v)
		hidePad(v)
		local posedRig = v.posedRig
		if posedRig then
			HoldSqueeze.finish(posedRig)
		end
		local rig = if player then deps.Held.getRig(player) else nil
		local axis: SquishRig.Axis? = if player then catalogAxis(player) else nil
		if rig and axis and rig == v.axisRig then
			rig:setAxis(axis)
		end
		deps.Held.setMirror(nil)
		setTouchGui(v, false)
		deps.Camera.setFovOffset(FOV_OWNER, 0) -- the world FOV's base back exactly
	end)
	destroyToy(v)
	v.cleanup:clean()
	DesignArm.destroy(v.left.arm)
	DesignArm.destroy(v.right.arm)
	local glow = v.glow
	if glow then
		glow:Destroy()
	end
	v.viewport.ImageTransparency = 0
	v.gui.Enabled = false
end

local function show(player: Player)
	local gui = deps.UI.screenGui(GUI_NAME, FP.gui :: any)
	local viewport, camera = overlayOf(gui)
	local v = newView(gui, viewport, camera)
	view = v
	recolour(v)
	buildToy(v, player)
	v.cleanup:add(deps.Scheduler.add(function(dt: number, now: number): boolean
		return step(v, dt, now)
	end, "render"))
	deps.Held.setMirror(function(out: SquishRig.Out?, scale: Vector3)
		onMirror(v, out, scale)
	end)
	if v.toy and deps.Held.isHolding(player) then
		equip(v) -- design: fp.js:667
	end
	setTouchGui(v, touchGuiFallback and deps.Controls.preferredInput() == Enum.PreferredInput.Touch)
	gui.Enabled = true
end

-- Shown while a look is on and the local player has a held model.
local function refresh()
	local player = localPlayer()
	local want = player ~= nil and deps.FirstPerson.look() ~= nil and deps.Held.getModel(player) ~= nil
	if not want then
		hide()
	elseif view == nil then
		local ok, err = pcall(show :: any, player)
		if not ok then
			log:error("show failed:", err)
			hide()
		end
	else
		recolour(view :: View) -- the look may have changed (practice -> duel)
	end
end

local function onHeldChanged(model: Model?)
	local v = view
	if model == nil or v == nil then
		refresh()
		return
	end
	local player = localPlayer()
	if player then
		endPresses(v)
		v.posedRig = nil
		buildToy(v, player) -- a new model, a new rig (keepAxis) and a new box
		v.throw, v.ult = nil, nil
		if v.toy and deps.Held.isHolding(player) then
			equip(v) -- a new toy pops in (design: fp.js:96-107)
		else
			setKind(v, "empty")
		end
	end
end

-- Public -----------------------------------------------------------------------------------------------------------------

function ViewmodelController.isShown(): boolean
	return view ~= nil
end

function ViewmodelController.lastReleasePoint(): (Vector3?, number?)
	local v = view
	if v == nil then
		return nil, nil
	end
	local _, _, _, releaseStart = deps.Throw.localWindup()
	local release = v.release
	if releaseStart ~= nil and (release == nil or release.at ~= releaseStart) then
		captureRelease(v, releaseStart) -- asked before this frame's step saw the release
		release = v.release
	end
	if release then
		return release.point, release.factor
	end
	return nil, nil
end

function ViewmodelController.toyScreenPoint(): Vector2?
	local v = view
	local toyCam = if v and v.toyShown then v.toyCam else nil
	local camera = deps.Workspace.CurrentCamera
	if toyCam == nil or camera == nil then
		return nil
	end
	-- The overlay fills the screen (ScreenInsets None): the world camera's viewport is its pixel frame.
	return ViewmodelMath.screenPoint(toyCam, camera.ViewportSize, FP.fovDeg)
end

function ViewmodelController.padAction(): string?
	if view == nil then
		return nil
	end
	local look = deps.FirstPerson.look()
	if look == "duel" then
		return DUEL_ACTION
	elseif look == "practice" then
		return PRACTICE_ACTION
	elseif look == "lobby" then
		return LOBBY_ACTION
	end
	return nil
end

function ViewmodelController.pressPad(state: Enum.UserInputState, input: InputObject?): boolean
	local action = ViewmodelController.padAction()
	if action == nil then
		return false
	end
	return deps.Controls.pressAction(action, state, input)
end

function ViewmodelController.debugPose(name: string?): boolean
	local v = view
	if v == nil or (name ~= nil and not POSES[name]) then
		return false
	end
	local rig = v.posedRig
	v.posedRig = nil
	if rig then
		HoldSqueeze.finish(rig)
	end
	if name == nil then
		v.pose = nil
		v.throw, v.ult = nil, nil
		setKind(v, if v.toy then "idle" else "empty")
		return true
	end
	v.pose = { name = name, now = os.clock() }
	applyPose(v, name)
	return true
end

function ViewmodelController.setTouchGuiFallback(on: boolean)
	touchGuiFallback = on == true
	local v = view
	if v then
		setTouchGui(v, touchGuiFallback and deps.Controls.preferredInput() == Enum.PreferredInput.Touch)
	end
end

-- Studio debug hooks and tests.
function ViewmodelController.debugState(): { [string]: any }
	local v = view
	if v == nil then
		return { shown = false }
	end
	local function names(arm: Arm): { string }
		local list: { string } = {}
		for name in arm.arm.parts do
			table.insert(list, name)
		end
		table.sort(list)
		return list
	end
	local throw = v.throw
	local toy = v.toy
	local src = v.mirror
	return {
		shown = true,
		look = deps.FirstPerson.look(),
		kind = v.kind,
		toy = if toy then toy.id else nil,
		toyShown = v.toyShown,
		hw = if toy then toy.hw else nil,
		leftParts = names(v.left),
		rightParts = names(v.right),
		sleeve = v.right.arm.parts.sleeve.Color:ToHex(),
		skin = v.right.arm.parts.hand.Color:ToHex(),
		ghost = v.ghost,
		press = if src then src.pressAmount else 0,
		focus = v.focus,
		fov = v.fov,
		fovVelocity = v.fovVel,
		kick = v.kick,
		kickVelocity = v.kickVel,
		shake = v.shake,
		scale = v.scale,
		sq = v.sq,
		shownScale = if toy then toy.deformer:getScale() else nil, -- the scale the overlay copy's deformer shows
		throwing = throw ~= nil,
		released = throw ~= nil and throw.released,
		trackTime = if throw then throw.time else nil,
		ult = v.ult ~= nil,
		glow = v.glowOpacity,
		toyPos = v.toyPos,
		toyRot = v.toyRot,
		leftPos = v.left.pos,
		rightPos = v.right.pos,
		leftRoll = v.left.roll,
		rightRoll = v.right.roll,
		camera = v.camera.CFrame,
		pose = if v.pose then v.pose.name else nil,
		padShown = v.pad ~= nil and v.pad.button.Visible,
		touchGuiRaised = v.touchGui ~= nil,
		viewportParts = #v.viewport:GetDescendants(),
	}
end

-- Test seam (Edit mode): replaces some of the side-effecting surfaces (nil = the real ones again).
function ViewmodelController.useDeps(overrides: { [string]: any }?)
	if overrides == nil then
		deps = REAL_DEPS
		return
	end
	local merged: { [string]: any } = table.clone(REAL_DEPS :: any)
	for key, value in overrides do
		assert(merged[key] ~= nil, `[SD][Viewmodel] unknown dependency {key}`)
		merged[key] = value
	end
	deps = merged :: any
end

-- Lifecycle --------------------------------------------------------------------------------------------------------------

function ViewmodelController.init()
	local c = Cleanup.new()
	cleanup = c
	-- The arms' meshes once per session (SuperMesh.prepare yields), so the first overlay already has them.
	task.spawn(SuperMesh.prepare)
	c:add(hide) -- added first, so it runs last
	c:add(deps.Controls.bindAction(DUEL_ACTION, duelHandler))
	c:add(deps.Controls.bindAction(PRACTICE_ACTION, practiceHandler))
	c:add(deps.FirstPerson.LookChanged:connect(function()
		refresh()
	end))
	c:add(deps.Held.HeldChanged:connect(function(player: Player, model: Model?)
		if player == localPlayer() then
			onHeldChanged(model)
		end
	end))
	c:add(deps.Net.onThrowImpact(function(payload: any)
		local player = localPlayer()
		if
			type(payload) == "table"
			and player
			and payload.victimId == player.UserId
			and type(payload.invulnUntil) == "number"
		then
			ghostUntil = payload.invulnUntil
		end
	end))
	refresh()
	log:debug("ready")
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function ViewmodelController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
	ghostUntil = -math.huge
	touchGuiFallback = false
end

return ViewmodelController
