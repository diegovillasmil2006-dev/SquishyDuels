--!strict
-- ViewmodelController (client only). The 3D Lab FP viewmodel (spec 2026-10-11 §3; design: sd/fp.js) on the local
-- player's first person, wherever it is (§3.8): while FirstPersonController.look() is set ("duel", "practice" or
-- "lobby", the player's own zoom into the head) and the local player has a held model, a full-screen ViewportFrame in
-- the controller-owned ScreenGui SD_Viewmodel (Config.FirstPerson.gui: DisplayOrder -1, under Roblox's TouchGui and
-- every HUD; ScreenInsets None; not in Config.UI.ScreenGuis) draws two arms and a "Viewport" copy of the held squishy.
-- The arms are the local player's own R15 arms (Anim/OwnArm: copies of the character's hands, lower and upper arms,
-- with its Shirt; user decision 2026-10-11), or the design's (Anim/DesignArm, five parts each) when the character has
-- none usable; every ownArms.recheckSeconds a changed avatar signature rebuilds them on the same springs. The viewport
-- is Active = false and Interactable = false, so a click at the
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
--     cancel fades the glow by glowFadeRate. Spec phase 5: every ultimate does the same, its charge share over its own
--     telegraph (the design's wind-up, ultTelegraphSeconds) and its glow in the design's colour: Dragon's orange,
--     else its squishy's rarity colour from Art/RarityStyle (fp.js:460, ultGlowColour).
-- World camera: the FOV goes base + fov·focus.worldFovPerUnit (the fov spring toward focus.worldFovTarget × the focus
-- share, 70° -> 64.5°) through CameraController.setFovOffset (one owner; base back exactly), plus the movement overhaul's
-- speed FOV (2026-10-17: MoveFeelController.fovOffset, relayed here while the overlay shows: setFovRelay at show and
-- hide), and the overlay camera takes MoveFeelController.overlaySway (the hands bob, sway and roll with the run); the
-- design's shake value
-- (falling shake.decayPerSecond a second) through CameraController.shake (ViewmodelMath.shakeFor) only when it rose
-- and settings.cameraShake is on. ReducedMotion: no world FOV change, no tremor or jitter, no breath, no idle drift or
-- kick on the overlay camera, no pop-in overshoot (it grows to 1 and stops), no Rush wobble or glow pulse (DESIGN
-- §9.12). Low tier (MeshQuality "Low" at show, first-person spec 2026-10-10 §5): no idle drift and no breath, so the
-- full-screen viewport only redraws while something acts (Studio 2026-10-11: the overlay cost about 5 ms a frame on a
-- PC while it redrew every frame). Phone speed fix (2026-10-16, NOT IN DESIGN): on the low tier the overlay's step
-- (hands, toy, specks) also runs at most Config.FirstPerson.lowTier.stepHz times a second (ViewmodelMath.throttle; the
-- skipped frames' time goes to the next step, so the springs, tracks, showcases and specks keep their timing; a debug
-- pose steps every frame; stepHz 0 = off). The world FOV spring, the world camera and the touch pad still step every
-- frame with that frame's own time (the whole screen's zoom and a lifted finger are never a frame late). Batch B
-- (owner 2026-10-17): the low tier also spawns lowTier.speckShare of the throw / catch specks (spawnSpecksAt; the
-- Inspect showcases keep every speck).
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
-- what it took. Lobby squeezes come in through the mirror only; their puffs, release sparkles and Dragon steam, the
-- equip pop's puffs and the own elimination burst through setMirror's fx (owner 2026-10-26: at the hidden own model
-- they floated in the air), drawn as specks and a ring on the toy (mirrorFx; NOT IN DESIGN: the design's squeeze has
-- none). Touch: SD_ViewmodelPad
-- (Config.FirstPerson.padGui, safe insets) holds one invisible, non-selectable button over the toy's screen box
-- (ViewmodelMath.touchPadRect), which
-- presses padAction() with that finger until it lifts (lobby HUD spec 2026-10-11 §2: the finger's InputObject goes with
-- the press, so the lobby squeeze keeps squeezing while it holds). Sounds: in duels only (elsewhere SqueezeFeel plays
-- them), sfx.squish on the rig's squish event and sfx.squeezeRelease on its pop end, 2D, at the toy's squeeze pitch × a
-- random 0.94-1.06.
-- init() starts Anim/SuperMesh.prepare (the arms' meshes, once per session) so the first overlay has them.
-- Kept from step 2 (spec 2026-10-11 §3.7): while the own invulnUntil (ThrowImpact) runs, the overlay shows at
-- invulnTransparency; lastReleasePoint() puts your own first-person projectile's start on the world camera's ray
-- through where the overlay toy was (ViewmodelMath.releasePoint); the TouchGui fallback (setTouchGuiFallback). Sleeve:
-- the duel side's colour (teamSleeves), colours.sleeve (mint) elsewhere; skin and cuff fixed (the design arms only:
-- own arms wear the player's own shirt).
-- Readings: "squeezing" is the mirrored press amount c > 0 (the design's palms down, fp.js:399, 412); the throw starts
-- from idle or the pop-in (a new windup also cuts a finished throw's follow-through short when the toy is back); a
-- cancelled windup goes back to the hold on the springs; the world FOV and the glow stop at a thousandth of a degree /
-- of opacity (below anything shown).
-- Inspect showcases (final polish 2026-10-11; design: fp.js:111-194, 304-306, 405-412, 656): HandInspect (R; ButtonL1
-- and the overlay's own touch Inspect button are build choices, NOT IN DESIGN) plays the held toy's showcase
-- (Anim/InspectTracks) while the overlay shows in the lobby look or the practice range and the toy rests in the hand
-- (idle: no windup, ultimate, pop-in, throw or squeeze, not posed); never in a duel. Each frame of it: the toy's offset
-- on the hold point, its rotation, its scale keys and both hands on the track's targets (the springs do the rest, as
-- every action), the rolls ±arm.roll; each event fires once as t passes it: its sound (2D; the material ones at the
-- toy's pitch), its kick on the design's squash spring (the toy's kRel / cRel, shown as (w, y, w) on the overlay copy,
-- toys.js:442-455), its camera shake and its specks (Anim/Specks drawn as small parts in the overlay: particles draw
-- nothing in a ViewportFrame; Neon for the design's unlit sparks and embers). At dur the hold comes back with the
-- rotation spring set to the wrapped last key (fp.js:412; reading: the design's one-frame pull toward the unwrapped
-- key, a frame-rate-dependent flick, is not kept). User decision 2026-10-11: a squeeze (the mirrored press), a throw
-- windup, an ultimate, the toy leaving the hand or a look other than lobby / practice cancels it back to the hold, the
-- rotation spring wrapped first (no unwinding of the turns). ReducedMotion: the showcase plays (asked for), without the
-- kicks and the shake, with half the specks (Config.Vfx.reducedParticleMultiplier). debugInspect(t) freezes it at t
-- for pictures (no event fires). The touch Inspect button (UI/Components/Button, the "inspect" glyph, common.inspect)
-- sits in SD_ViewmodelPad at the bottom middle (ViewmodelMath.inspectButtonRect, Config.UI.Touch.inspectButtonInset)
-- while touch is the input and the look is lobby or practice; a press while the toy is busy does nothing (as R).
-- Feature 1 (2026-10-11; design: the combat-effects page "Squishy Combat FP v2.html", html:<line>; the poses are
-- Anim/ChargePoses', the effect parts Anim/ChargeFx's, the numbers Config.FirstPerson.v2 / charge / catch / crush):
--   * charge (ThrowController.localCharge, from the hold, idle, the pop-in or a showcase): the toy to the right and
--     cocked, the right hand under it, the left hand away and back to steady it, the jitter near full, the toy's squash
--     scale and the squish face at full (its face is shown over the mirrored rig's), the glow ball in the toy's accent,
--     the orbit from 0.4, the white shell, the camera shake and a ring every 0.32 s at full, a white ring the moment
--     it is full, sparks gathering in (Anim/Specks "gather"); the world FOV narrows by Charge.fovNarrowDeg × c on the
--     same FOV spring as the focus (design: html:463). The release that follows plays the throw track from that pose;
--     its kick and FOV kick grow with the charge (ThrowCharge.release; design: html:333), with rings and sparks at the
--     hand from c 0.45 and the hit-stop at full (design: html:335-339).
--   * catch (CatchController.localCatch "open"): the hands open in front, the toy tucked away below (design:
--     html:528-533); back to the hold when the window closes.
--   * crush ("crush" / "after"): the caught toy (a "Viewport" copy of the thrower's squishy, crush.toyScale of the held
--     one) arrives on its own spring, shakes, wobbles and squashes between the two palms (the overlay's two-palm
--     squeeze pose on it, ViewmodelMath.palms), its "wow" then squish face, its glow, orbit and specks, the camera
--     shake rising; the catch's kick, FOV kick, ring and sparks when it arrives (design: html:351-353); at burstAt the
--     burst: specks, three rings, the FOV kick, the kick and the hands thrown apart (design: html:554-561), the toy
--     gone; empty hands until the hands are back, then the held toy pops in. The flash, the sounds and the hit-stops
--     are CatchController's; during any hit-stop the overlay runs at v2.hitStopTimeScale (design: html:422).
--   ReducedMotion: no jitter, wobble, pulse or flicker, half the specks (as the showcases).
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
--   ViewmodelController.inspect() -> boolean   starts the held toy's Inspect showcase now when it may (HandInspect, the
--       touch Inspect button, Studio); false when it may not
--   ViewmodelController.debugInspect(t?) -> boolean   freezes the held toy's showcase at t seconds for pictures (every
--       spring on its target, no event); nil lets the overlay live again (as debugPose(nil))
--   ViewmodelController.debugState() / useDeps(overrides?) / init() / destroy()
-- Require direction: it may require FirstPersonController, HeldSquishyController, ThrowController, CatchController
-- (feature 1), ControlsController, NetController, StateController, SoundController, UIController and CameraController,
-- never ProjectileRenderer, VfxController, DuelController or PracticeController.

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
local Palette = require(Shared.Art.Palette)
local SquishyBlueprints = require(Shared.Art.SquishyBlueprints)
local Strings = require(Shared.Strings)
local ThrowCharge = require(Shared.ThrowCharge)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local ChargeFx = require(Client.Anim.ChargeFx)
local ChargePoses = require(Client.Anim.ChargePoses)
local DesignArm = require(Client.Anim.DesignArm)
local HitStop = require(Client.Anim.HitStop)
local HoldSqueeze = require(Client.Anim.HoldSqueeze)
local InspectTracks = require(Client.Anim.InspectTracks)
local MeshQuality = require(Client.Anim.MeshQuality)
local OwnArm = require(Client.Anim.OwnArm)
local Scheduler = require(Client.Anim.Scheduler)
local Specks = require(Client.Anim.Specks)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local SquishRig = require(Client.Anim.SquishRig)
local SuperMesh = require(Client.Anim.SuperMesh)
local ThrowTracks = require(Client.Anim.ThrowTracks)
local Tweens = require(Client.Anim.Tweens)
local ViewmodelMath = require(Client.Anim.ViewmodelMath)
local SquishyCache = require(Client.Models.SquishyCache)
local CameraController = require(script.Parent.CameraController)
local CatchController = require(script.Parent.CatchController)
local ControlsController = require(script.Parent.ControlsController)
local FirstPersonController = require(script.Parent.FirstPersonController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)
local UIController = require(script.Parent.UIController)

-- Types

type Kind = "equip" | "idle" | "throw" | "ult" | "empty" | "inspect" | "charge" | "catch" | "crush"

-- Feature 1: the caught toy on the overlay (the crush), its own spring, and whether it burst.
type Caught = {
	id: string,
	model: Model,
	deformer: SquishDeformer.Deformer,
	centre: Vector3,
	hw: number, -- its half width (du)
	radius: number, -- its longest half side (du): the effects' unit
	colours: { Color3 },
	pos: Vector3, -- du, on its spring
	vel: Vector3,
	out: SquishRig.Out,
	burstAt: number, -- server time
	burst: boolean,
	arrived: boolean, -- the catch's kick and effects played
}

type Toy = {
	id: string,
	model: Model,
	deformer: SquishDeformer.Deformer,
	centre: Vector3, -- ViewmodelMath.toyBox's centre in the pivot's space (studs, overlay scale)
	size: Vector3, -- its size (studs, overlay scale)
	hw: number, -- its half width (du): the design's H.hw (fp.js:101)
	ratio: number, -- overlay build scale ÷ held build scale (1): the release hand-off
	pitch: number, -- the design's squeeze pitch (the sounds)
	-- Final polish 2026-10-11: the design's squash spring a kick moves (toys.js:442-455): its release spring and widen.
	squash: { number }, -- { kRel, cRel }
	widen: number,
	colours: { Color3 }, -- its own specks: its Catalog accent and white (the design's per-toy pcols stand-in)
}

-- One Inspect showcase running (final polish 2026-10-11): its track, the seconds into it and the events fired so far.
type Inspect = { track: InspectTracks.Track, t: number, fired: number }

-- One speck on screen: its numbers (Anim/Specks) and its part in the overlay.
type Speck = { state: Specks.Speck, part: BasePart }

-- One arm: the hand point and the roll on their springs (fp.js:73); its parts are the player's own (own) or the
-- design's (arm), one of the two.
type Arm = {
	side: number,
	arm: DesignArm.Arm?,
	own: OwnArm.Arm?,
	frames: { [string]: CFrame }, -- the partFrames table (OwnArm's or DesignArm's), reused
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
	power: number, -- feature 1: the charge it was thrown with (0 = uncharged)
}

-- Seconds into the charge; the charge share 0-1 over the telegraph (`telegraph` s); the glow's colour.
type Ult = { t: number, ch: number, telegraph: number, colour: Color3 }

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
	ownArms: OwnArm.Arms?, -- the own arms' model (nil: the design arms)
	armsKey: string, -- OwnArm.signature of the character the arms were built from
	armsWhy: string?, -- why the design arms show (OwnArm's reason; nil with own arms)
	armsCheckIn: number, -- seconds to the next signature check
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
	-- Phone speed fix (2026-10-16): the low tier's step cap (ViewmodelMath.throttle's phase) and the seconds the skipped
	-- frames owe the next step.
	stepPhase: number,
	stepOwed: number,
	pose: Pose?,
	posedRig: SquishRig.Rig?, -- a rig a debug pose pressed or held
	touchGui: ScreenGui?, -- the fallback: Roblox's TouchGui and its own order
	touchGuiOrder: number,
	-- Final polish 2026-10-11: the Inspect showcase, its specks, the design's squash spring (y around 1, toys.js:446)
	-- and the touch Inspect button (made at its first show).
	inspect: Inspect?,
	specks: { Speck },
	squashY: number,
	squashVel: number,
	inspectButton: Button.Button?,
	-- Feature 1: the charge (its level and seconds this frame, the full ring's timer and whether the white ring fired,
	-- the sparks owed), the orbit's turn, the face shown over the mirrored rig's, the effect parts and the caught toy.
	chargeC: number,
	chargeT: number,
	chargeRingIn: number,
	chargeFull: boolean,
	speckDebt: number,
	orbitAngle: number,
	faceOverride: SquishRig.Face?,
	fx: ChargeFx.ChargeFx,
	caught: Caught?,
	catchT: number, -- seconds since the press ("catch") or the catch ("crush")
}

-- Constants

local LIGHT_POP = 0.4 -- 2026-10-15: an uncharged release's share of the charged burst and sparks ...
local LIGHT_POP_SIZE = 0.45 -- ... and of its burst's speck size (Play check: full-size specks read as blobs)

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
local OWN_ARMS = FP.ownArms
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
-- Final polish 2026-10-11: the Inspect showcases.
local INSPECT_ACTION = "HandInspect"
local INSPECT_LOOKS: { [string]: boolean } = { lobby = true, practice = true } -- never in a duel
local INSPECT_POSE = "inspect"
local INSPECT_BUTTON_NAME = "Viewmodel_InspectButton"
local SPECK_NAME = "InspectSpeck"
local REDUCED_SPECKS = Config.Vfx.reducedParticleMultiplier
-- The own squeeze's and equip pop's effects (HeldSquishyController.mirrorFx, owner 2026-10-26). NOT IN DESIGN (its
-- first-person squeeze has no specks): the world effect's count and colour as the design's own toy specks, "puffs" and
-- "steam" as pc (fp.js:171), "sparkles" as the sparkle burst (fp.js:189).
local MIRROR_PUFFS = table.freeze({
	kind = "burst",
	count = 0,
	shape = "puff",
	speed = 0.35,
	size = 0.006,
	life = 0.6,
	gravity = -0.6,
	drag = 3,
}) :: any
local MIRROR_SPARKLES = table.freeze({
	kind = "burst",
	count = 0,
	shape = "spark",
	speed = 0.3,
	size = 0.006,
	life = 0.6,
	gravity = 0,
}) :: any
local NOSTRIL_PREFIX = "Nostril" -- the Dragon's steam comes out of these parts (as SqueezeFeel's)
-- Phone speed fix (2026-10-16): the low tier's step cap (Config.FirstPerson.lowTier.stepHz; 0 = off, every frame).
local LOW_STEP_S = ViewmodelMath.stepInterval(FP.lowTier.stepHz)
local MIN_PART = 0.001 -- studs: Roblox's smallest part size (a speck's first and last frames are smaller)
local SQUASH_REST, SQUASH_REST_SPEED = 0.002, 0.01 -- the squash spring is at rest (design: toys.js:452)
local INSPECT_INSET = Config.UI.Touch.inspectButtonInset
-- Feature 1 (2026-10-11): the charge, the catch and the crush (Config.FirstPerson.v2 / charge / catch / crush).
local V2 = FP.v2
local CHARGE = FP.charge
local CATCH_FP = FP.catch
local CRUSH = FP.crush
local CAUGHT_NAME = "CaughtToy"

-- The side-effecting surfaces the overlay touches; tests swap them (useDeps).
local REAL_DEPS = {
	FirstPerson = FirstPersonController,
	Held = HeldSquishyController,
	Throw = ThrowController,
	Catch = CatchController, -- feature 1: localCatch()
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
	Move = require(script.Parent.MoveFeelController), -- 2026-10-17: the speed FOV and the hands' sway
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
	if kind ~= "inspect" and v.inspect then
		-- User decision 2026-10-11: anything else ends a showcase back on the springs; the rotation spring is wrapped
		-- first, so the toy never unwinds the showcase's turns (the design's wrapRot, fp.js:109).
		v.inspect = nil
		v.toyRot = InspectTracks.wrap(v.toyRot)
	end
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
		squash = if squeeze then { squeeze.kRel, squeeze.cRel } else { 1, 1 },
		widen = if squeeze then squeeze.widen else 0,
		colours = { Color3.fromHex(def.visuals.accent), Palette.White },
	}
	v.mirror, v.mirrorScale = nil, Vector3.one
	v.squashY, v.squashVel = 1, 0
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
-- the design's toy has none of them, fp.js:396, 403) in the deformer's limits, the toy's scale keys on top, and the
-- design's squash node (w, y, w) a showcase event kicked (toys.js:454-455; 1 at rest).
local function fillOut(v: View): SquishRig.Out
	local src, scale = v.restOut, Vector3.one
	local mirror = v.mirror
	if mirror then
		src, scale = mirror, v.mirrorScale
	end
	local out = v.out
	local toy = v.toy
	local squash = if toy and v.squashY ~= 1 then InspectTracks.squashScale(v.squashY, toy.widen) else Vector3.one
	out.S = deps.Deformer.clampScale(src.S / scale) * v.sq * squash
	out.twist = src.twist
	-- Feature 1: the squish face of a full charge shows over the rig's own (design: html:511).
	out.face, out.blink, out.cheek = v.faceOverride or src.face, src.blink, src.cheek
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

-- Inspect showcases (final polish 2026-10-11) ---------------------------------------------------------------------

-- The toy rests in the hand in a look with showcases (the lobby look, the practice range): one may start (no windup,
-- ultimate, pop-in, throw or squeeze; not posed; the held toy has one).
local function canInspect(v: View): boolean
	local toy = v.toy
	if toy == nil or not canSqueeze(v) or not INSPECT_LOOKS[deps.FirstPerson.look() or ""] then
		return false
	end
	local mirror = v.mirror
	return (mirror == nil or mirror.pressAmount <= 0) and InspectTracks.get(toy.id) ~= nil
end

local function startInspect(v: View): boolean
	if not canInspect(v) then
		return false
	end
	local track = InspectTracks.get((v.toy :: Toy).id) :: InspectTracks.Track
	setKind(v, "inspect")
	v.inspect = { track = track, t = 0, fired = 0 }
	return true
end

-- A showcase event's specks (Anim/Specks) as small parts in the overlay (particles draw nothing in a ViewportFrame):
-- Neon for the design's unlit sparks and embers, round but the cubes.
-- Feature 1: also the charge's and the crush's specks, at `at` (du) in `colours`, at most `cap` live in all.
local function spawnSpecksAt(
	v: View,
	spec: Specks.Spec,
	at: Vector3,
	colours: { Color3 },
	reduced: boolean,
	cap: number?
)
	if cap ~= nil and #v.specks >= cap then
		return
	end
	-- Phone speed fix (batch B, owner 2026-10-17 "do it": throws make half the sparkles): the low tier spawns
	-- lowTier.speckShare of the duel hands' specks (charge, release, catch, crush); an Inspect showcase keeps them all.
	local low = v.still and v.kind ~= "inspect"
	local share = (if reduced then REDUCED_SPECKS else 1) * (if low then FP.lowTier.speckShare else 1)
	local list = Specks.spawn(spec, at, v.random, share, colours)
	for _, state in list do
		if cap ~= nil and #v.specks >= cap then
			break
		end
		local part = Instance.new("Part")
		part.Name = SPECK_NAME
		part.Shape = if state.shape == "cube" then Enum.PartType.Block else Enum.PartType.Ball
		part.Material = if state.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.Color = state.colour
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Size = Vector3.one * MIN_PART
		part.CFrame = CFrame.new(state.p * U)
		part.Parent = v.viewport
		table.insert(v.specks, { state = state, part = part :: BasePart })
	end
end

local function spawnSpecks(v: View, spec: Specks.Spec, toy: Toy, reduced: boolean)
	spawnSpecksAt(v, spec, v.toyPos, toy.colours, reduced, nil)
end

-- The specks fly and shrink (fx.js:131-139); a speck past its life goes.
local function stepSpecks(v: View, dt: number)
	local list = v.specks
	for i = #list, 1, -1 do
		local speck = list[i]
		local state = speck.state
		if Specks.step(state, dt) then
			speck.part.Size = Vector3.one * math.max(2 * Specks.radius(state) * U, MIN_PART)
			speck.part.CFrame = CFrame.new(state.p * U) * Specks.rotation(state)
		else
			speck.part:Destroy()
			table.remove(list, i)
		end
	end
end

local function clearSpecks(v: View)
	for _, speck in v.specks do
		speck.part:Destroy()
	end
	table.clear(v.specks)
end

-- One showcase event (design: vEv, fp.js:169-194): its sound (2D; the material sounds at the toy's pitch), its kick on
-- the squash spring (toys.js:442), its camera shake and its specks. ReducedMotion: no kick, half the specks (the shake
-- is held back by stepWorldCamera).
local function fireEvent(v: View, name: string, reduced: boolean)
	local recipe = InspectTracks.recipe(name)
	local toy = v.toy
	if recipe == nil or toy == nil then
		return
	end
	if recipe.pitched then
		playSound(recipe.sound, toy)
	else
		local ok, err = pcall(deps.Sound.play, recipe.sound, nil)
		if not ok then
			log:warn(`sound {recipe.sound} failed:`, err)
		end
	end
	local kick = recipe.kick
	if kick and not reduced then
		v.squashVel += kick
	end
	local shake = recipe.shake
	if shake then
		raiseShake(v, shake)
	end
	local spec = recipe.specks
	if spec then
		spawnSpecks(v, spec, toy, reduced)
	end
end

-- One frame of the showcase (fp.js:405-412): back to the hold on a squeeze or a look without showcases (user decision
-- 2026-10-11), its events as t passes them, the hold back at dur with the rotation spring on the wrapped last key.
local function stepInspect(v: View, dt: number, reduced: boolean)
	local inspect = v.inspect
	if inspect == nil or v.kind ~= "inspect" then
		return
	end
	local mirror = v.mirror
	if (mirror and mirror.pressAmount > 0) or not INSPECT_LOOKS[deps.FirstPerson.look() or ""] then
		setKind(v, "idle")
		return
	end
	inspect.t += dt
	local track = inspect.track
	local due = InspectTracks.firedBy(track, inspect.t)
	while inspect.fired < due do
		inspect.fired += 1
		fireEvent(v, track.events[inspect.fired].name, reduced)
	end
	if inspect.t >= track.dur then
		local _, last = InspectTracks.toyAt(track, track.dur)
		v.inspect = nil
		v.toyRot = InspectTracks.wrap(last) -- design: fp.js:412
		setKind(v, "idle")
	end
end

-- HandInspect (R; ButtonL1): the held toy's showcase when it may start; otherwise the press passes.
local function inspectHandler(state: Enum.UserInputState, _input: InputObject?): boolean?
	if state ~= Enum.UserInputState.Begin then
		return false
	end
	return ViewmodelController.inspect()
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
	-- Feature 1: the charge, the open hands and the crush end by their own steps.
	if kind == "throw" or kind == "ult" or kind == "charge" or kind == "catch" or kind == "crush" then
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
	-- A windup also ends a running Inspect showcase (user decision 2026-10-11; setKind wraps its rotation spring).
	-- Feature 1: and a released charge, whose level the throw keeps (its kicks grow with it).
	local free = v.kind == "idle"
		or v.kind == "equip"
		or v.kind == "inspect"
		or v.kind == "charge"
		or (throw ~= nil and throw.released)
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
			power = if v.kind == "charge" then v.chargeC else 0,
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

-- One frame of the local ultimate's charge (ThrowController.localUlt): ch over that ultimate's telegraph.
local function stepUlt(v: View, dt: number, serverNow: number, holding: boolean)
	local phase, telegraphEndsAt, _, ultimateId = deps.Throw.localUlt()
	local charging = phase == "cast" or phase == "telegraph"
	local ult = v.ult
	local kind: Kind = v.kind
	if charging and holding and v.toy and (kind == "idle" or kind == "equip" or kind == "ult" or kind == "inspect") then
		if ult == nil then
			ult = {
				t = 0,
				ch = 0,
				telegraph = ViewmodelController.ultTelegraphSeconds(ultimateId),
				colour = ViewmodelController.ultGlowColour(ultimateId),
			}
			v.ult = ult
			setKind(v, "ult")
		end
		local u = ult :: Ult
		u.t += dt
		u.ch = math.min(1, u.ch + dt / u.telegraph)
		if telegraphEndsAt then
			u.ch = math.max(u.ch, math.clamp(1 - (telegraphEndsAt - serverNow) / u.telegraph, 0, 1))
		end
	elseif ult then
		v.ult = nil -- released or cancelled: the toy springs back to the hold
		v.rushReleased = phase == "release" -- a release's camera reaction comes in this frame's action (fp.js:331)
		if kind == ("ult" :: Kind) then
			setKind(v, if holding then "idle" else "empty")
		end
	end
end

-- Feature 1: the charge, the catch and the crush -----------------------------------------------------------------------

-- One frame of the local charge (ThrowController.localCharge): from the hold (idle, the pop-in, a showcase) the kind
-- becomes "charge"; a charge dropped without a throw goes back to the hold on the springs (a release turns it into the
-- throw in stepThrow, before this).
local function stepCharge(v: View, holding: boolean)
	local c, t = deps.Throw.localCharge()
	local kind: Kind = v.kind
	local fromHold = kind == "idle" or kind == "equip" or kind == "inspect" or kind == "charge"
	if c ~= nil and holding and v.toy and fromHold then
		if kind ~= "charge" then
			setKind(v, "charge")
			v.chargeRingIn, v.chargeFull, v.speckDebt = 0, false, 0
		end
		v.chargeC, v.chargeT = c, t or 0
	elseif kind == "charge" then
		setKind(v, if holding then "idle" else "empty")
		v.chargeC = 0
	end
end

local function destroyCaught(v: View)
	local caught = v.caught
	v.caught = nil
	if caught then
		caught.deformer:destroy()
		caught.model:Destroy()
	end
end

-- The caught toy's overlay copy: a "Viewport" build of the thrower's squishy at crush.toyScale of the held toy's size
-- (design: html:348), arriving from crush.from at crush.fromVelocity (design: html:349).
local function buildCaught(v: View, id: string, burstAt: number, hold: Vector3): Caught?
	destroyCaught(v)
	local def = Catalog.get(id)
	if def == nil then
		return nil
	end
	local scale = U * FP.toyLongestDu * CRUSH.toyScale / longestOf(id)
	local model = deps.Cache.clone(id, "Viewport", scale)
	model.Name = CAUGHT_NAME
	model:PivotTo(CFrame.identity)
	local centre, size = ViewmodelMath.toyBox(model)
	local caught: Caught = {
		id = id,
		model = model,
		deformer = deps.Deformer.attach(model, { scaleMax = math.huge }),
		centre = centre,
		hw = size.X / 2 / U,
		radius = math.max(size.X, size.Y, size.Z) / 2 / U,
		colours = { Color3.fromHex(def.visuals.accent), Palette.White },
		pos = hold + ChargePoses.map(CRUSH.from - V2.hold),
		vel = ChargePoses.map(CRUSH.fromVelocity),
		out = SquishRig.newOut(),
		burstAt = burstAt,
		burst = false,
		arrived = false,
	}
	model.Parent = v.viewport
	v.caught = caught
	return caught
end

-- One frame of the local catch (CatchController.localCatch): "open" -> the open hands; "crush" / "after" -> the crush
-- (the caught toy built on its first frame); nothing -> the hold again (after a crush the toy is already back).
local function stepCatch(v: View, holding: boolean)
	local phase, t, id, burstAt = deps.Catch.localCatch()
	local kind: Kind = v.kind
	if phase == "crush" or phase == "after" then
		if kind ~= "crush" then
			v.throw, v.ult = nil, nil
			setKind(v, "crush")
			if phase == "crush" and id and burstAt then
				buildCaught(v, id, burstAt, HELD.pos)
			end
		end
		v.catchT = t or 0
	elseif phase == "open" then
		if kind ~= "catch" and kind ~= "crush" then
			v.throw = nil -- a finished throw's follow-through is cut (the catch never starts in a windup)
			setKind(v, "catch")
		end
		v.catchT = t or 0
	elseif kind == "catch" or kind == "crush" then
		destroyCaught(v)
		setKind(v, if holding then "idle" else "empty")
	end
end

-- A design size (its metres) round a toy of `radius` du (in its toy radii, ChargePoses.size).
local function around(metres: number, radius: number): number
	return ChargePoses.size(metres) * radius
end

-- An own effect the held model hands over while mirrored (HeldSquishyController.mirrorFx): specks in `colour` on the
-- toy you see (the hidden own model's world particles floated in the air); the steam from the copy's Nostril* parts.
-- The own elimination burst (VfxController, owner 2026-10-26): "confetti" as the crush burst's pieces and "ring" as its
-- first ring (design: html:557, 559), round the toy.
local function mirrorFx(v: View, kind: string, count: number, colour: Color3)
	local toy = v.toy
	if toy == nil or count <= 0 then
		return
	end
	local radius = FP.toyLongestDu / 2
	if kind == "ring" then
		local r = CRUSH.rings[1]
		v.fx:ring(v.toyPos, colour, around(r[1], radius), around(r[2], radius), r[3])
		return
	end
	local spec = table.clone(if kind == "sparkles" then MIRROR_SPARKLES else MIRROR_PUFFS)
	local reduced = deps.Motion.reducedMotion()
	if kind == "confetti" then
		spec.shape = "cube"
		spec.speed = around(CRUSH.burstSpeed, radius)
		spec.size = around(CRUSH.burstSize, radius)
		spec.life = CRUSH.burstLife
		spec.gravity = 0
		spec.drag = CRUSH.burstDrag
	elseif kind == "steam" then
		local nostrils: { BasePart } = {}
		for _, d in toy.model:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, #NOSTRIL_PREFIX) == NOSTRIL_PREFIX then
				table.insert(nostrils, d)
			end
		end
		if #nostrils > 0 then
			for i, nostril in nostrils do -- the puffs shared out as SqueezeFeel's round-robin
				spec.count = count // #nostrils + (if i <= count % #nostrils then 1 else 0)
				spawnSpecksAt(v, spec, nostril.Position / U, { colour }, reduced, nil)
			end
			return
		end
	end
	spec.count = count
	spawnSpecksAt(v, spec, v.toyPos, { colour }, reduced, nil)
end

-- The charge's effects at the toy (design: html:508-514): glow, white shell, orbit, gathering sparks, the white ring
-- the moment it is full and a ring every ringEvery at full.
local function chargeEffects(v: View, toy: Toy, pose: ChargePoses.ChargePose, dt: number, reduced: boolean)
	local radius = FP.toyLongestDu / 2
	local at = v.toyPos
	local accent = toy.colours[1]
	v.fx:glow(at, radius * pose.glowScale, accent, pose.glow)
	v.fx:outline(at, radius * CHARGE.outlineScale, pose.outline)
	v.orbitAngle += dt * pose.orbitSpin
	v.fx:orbit(at, radius, v.orbitAngle, pose.orbitScale, toy.colours, pose.orbit)
	if pose.sparkRate > 0 then
		v.speckDebt += dt * pose.sparkRate
		local count = math.floor(v.speckDebt)
		if count > 0 then
			v.speckDebt -= count
			spawnSpecksAt(v, {
				kind = "gather",
				count = count,
				shape = "spark",
				size = around(CHARGE.sparkSizeMax, radius),
				sizeMin = around(CHARGE.sparkSizeMin, radius),
				life = CHARGE.sparkLife,
				gravity = 0,
				drag = 0,
				distMin = around(CHARGE.sparkDistMin, radius),
				distMax = around(CHARGE.sparkDistMax, radius),
				gather = CHARGE.sparkGather,
			}, at, toy.colours, reduced, CHARGE.sparkMaxLive)
		end
	else
		v.speckDebt = 0
	end
	if pose.full then
		if not v.chargeFull then
			v.chargeFull = true
			local from, to = around(CHARGE.fullRingFrom, radius), around(CHARGE.fullRingTo, radius)
			v.fx:ring(at, Palette.White, from, to, CHARGE.fullRingSeconds) -- design: html:514
		end
		v.chargeRingIn -= dt
		if v.chargeRingIn <= 0 then
			v.chargeRingIn = CHARGE.ringEvery
			v.fx:ring(at, accent, around(CHARGE.ringFrom, radius), around(CHARGE.ringTo, radius), CHARGE.ringSeconds)
		end
	end
end

-- The release of a charged throw at the right hand (design: html:335-339): from whiteRingFrom two rings, a burst and
-- sparks that grow with the charge; the thrower's hit-stop at full. 2026-10-15 throw overhaul: an uncharged throw gets
-- a light pop too (one small ring in the toy's colour, LIGHT_POP of the base burst and sparks; no white ring, no
-- hit-stop), so every throw leaves the hand with a snap.
local function releaseEffects(v: View, power: number, release: ThrowCharge.Release, reduced: boolean)
	local toy = v.toy
	if toy == nil then
		return
	end
	local radius = FP.toyLongestDu / 2
	local at = v.right.pos
	local r = CHARGE.release
	if not (power > 0) then
		v.fx:ring(at, toy.colours[1], around(r.ringFrom, radius), around(r.ringTo, radius), r.ringSeconds)
		spawnSpecksAt(v, {
			kind = "burst",
			count = math.max(1, math.floor(r.burst * LIGHT_POP + 0.5)),
			shape = "sphere",
			speed = around(r.burstSpeed, radius),
			size = around(r.burstSize, radius) * LIGHT_POP_SIZE,
			life = r.burstLife,
			gravity = 0,
		}, at, toy.colours, reduced, nil)
		spawnSpecksAt(v, {
			kind = "burst",
			count = math.max(1, math.floor(r.sparks * LIGHT_POP + 0.5)),
			shape = "spark",
			speed = around(r.sparkSpeed * r.sparkSpeedBase, radius),
			size = around(r.sparkSize, radius),
			life = r.sparkLife,
			gravity = 0,
			drag = r.sparkDrag,
		}, at, toy.colours, reduced, nil)
		return
	end
	if release.whiteRing then
		local to = around(r.ringTo + r.ringGain * power, radius)
		v.fx:ring(at, toy.colours[1], around(r.ringFrom, radius), to, r.ringSeconds)
		v.fx:ring(at, Palette.White, around(r.whiteFrom, radius), around(r.whiteTo, radius), r.whiteSeconds)
	end
	spawnSpecksAt(v, {
		kind = "burst",
		count = r.burst + math.floor(r.burstGain * power + 0.5),
		shape = "sphere",
		speed = around(r.burstSpeed + r.burstSpeedGain * power, radius),
		size = around(r.burstSize, radius),
		life = r.burstLife,
		gravity = 0,
	}, at, toy.colours, reduced, nil)
	spawnSpecksAt(v, {
		kind = "burst",
		count = r.sparks + math.floor(r.sparksGain * power + 0.5),
		shape = "spark",
		speed = around(r.sparkSpeed * (r.sparkSpeedBase + power), radius),
		size = around(r.sparkSize, radius),
		life = r.sparkLife,
		gravity = 0,
		drag = r.sparkDrag,
	}, at, toy.colours, reduced, nil)
	local hold = release.hitStop
	if hold ~= nil then
		HitStop.trigger("chargeThrow:" .. tostring(os.clock()), hold, os.clock(), reduced) -- design: html:339
	end
end

-- The catch arriving in the hands (design: html:351-353): the kick, the FOV kick, the shake, a ring and sparks.
local function catchArrived(v: View, caught: Caught, reduced: boolean)
	caught.arrived = true
	v.kickVel += CATCH_FP.recoil * V2.kickPerRecoil
	v.fovVel += CATCH_FP.fovKick
	raiseShake(v, CATCH_FP.shake)
	local at = HELD.pos + ChargePoses.map(CATCH_FP.ringAt - V2.hold)
	local r = caught.radius
	v.fx:ring(at, caught.colours[1], around(CATCH_FP.ringFrom, r), around(CATCH_FP.ringTo, r), CATCH_FP.ringSeconds)
	spawnSpecksAt(v, {
		kind = "burst",
		count = CATCH_FP.sparks,
		shape = "spark",
		speed = around(CATCH_FP.sparkSpeed, r),
		size = around(CATCH_FP.sparkSize, r),
		life = CATCH_FP.sparkLife,
		gravity = 0,
	}, at, caught.colours, reduced, nil)
end

-- The burst (design: html:554-561): the caught toy goes, its pieces, sparks, puffs and white bits fly, three rings, the
-- FOV kick, the kick, the shake and the hands thrown apart.
local function burstCaught(v: View, caught: Caught, at: Vector3, reduced: boolean)
	caught.burst = true
	caught.model.Parent = nil
	v.fx:glow(at, 0, caught.colours[1], 0)
	v.fx:orbit(at, caught.radius, 0, 1, caught.colours, false)
	local r = caught.radius
	local speed, size = around(CRUSH.burstSpeed, r), around(CRUSH.burstSize, r)
	local function burst(count: number, shape: Specks.Shape, colours: { Color3 }?, s: number, sz: number, life: number)
		spawnSpecksAt(v, {
			kind = "burst",
			count = count,
			shape = shape,
			colours = colours,
			speed = s,
			size = sz,
			life = life,
			gravity = 0,
			drag = CRUSH.burstDrag,
		}, at, caught.colours, reduced, nil)
	end
	local white = { Palette.White }
	burst(CRUSH.burstPieces, "cube", nil, speed, size, CRUSH.burstLife)
	burst(CRUSH.burstSparks, "spark", nil, speed * CRUSH.sparkSpeedShare, size * CRUSH.sparkSizeShare, CRUSH.sparkLife)
	burst(CRUSH.burstPuffs, "sphere", white, speed * CRUSH.puffSpeedShare, size * CRUSH.puffSizeShare, CRUSH.puffLife)
	burst(CRUSH.burstWhite, "sphere", white, around(CRUSH.whiteSpeed, r), around(CRUSH.whiteSize, r), CRUSH.whiteLife)
	local colours = { caught.colours[1], Palette.White, caught.colours[1] }
	for i, ring in CRUSH.rings do
		v.fx:ring(at, colours[i] or Palette.White, around(ring[1], r), around(ring[2], r), ring[3])
	end
	v.fovVel += CRUSH.burstFovKick
	v.kickVel += CRUSH.burstRecoil * V2.kickPerRecoil
	raiseShake(v, CRUSH.burstShake)
	local push = ChargePoses.map(CRUSH.burstHands)
	v.right.vel += push
	v.left.vel += Vector3.new(-push.X, push.Y, push.Z)
end

-- The caught toy this frame: on its spring toward the crush's point, shaken, squashed and faced as the pose says
-- (design: html:539-543), drawn at its own frame (no pop-in scale).
local function drawCaught(caught: Caught, pose: ChargePoses.CrushPose, dt: number): Vector3
	caught.pos, caught.vel = ViewmodelMath.spring(caught.pos, caught.vel, pose.toy, CRUSH.spring, dt)
	local at = caught.pos + pose.shake
	local out = caught.out
	out.S = deps.Deformer.clampScale(pose.scale)
	out.face = pose.face :: SquishRig.Face
	local frame = ViewmodelMath.toyFrame(at, HELD.rot, U)
	caught.model:PivotTo(frame * CFrame.new(-caught.centre * out.S))
	caught.deformer:apply(out)
	return at
end

-- The crush's effects at the caught toy (design: html:544-550): glow, orbit and specks.
local function crushEffects(
	v: View,
	caught: Caught,
	pose: ChargePoses.CrushPose,
	at: Vector3,
	dt: number,
	reduced: boolean
)
	local r = caught.radius
	v.fx:glow(at, r * pose.glowScale, caught.colours[1], pose.glow)
	v.orbitAngle += dt * pose.orbitSpin
	v.fx:orbit(at, r, v.orbitAngle, 1, caught.colours, pose.orbit)
	if pose.speckRate > 0 then
		v.speckDebt += dt * pose.speckRate
		local count = math.floor(v.speckDebt)
		if count > 0 then
			v.speckDebt -= count
			local spread = CRUSH.speckSpeed
			spawnSpecksAt(v, {
				kind = "emit",
				count = count,
				shape = "cube",
				velMin = Vector3.new(-around(spread.X, r), 0, -around(spread.Z, r)), -- design: html:550
				velMax = Vector3.new(around(spread.X, r), around(spread.Y, r), around(spread.Z, r)),
				size = around(CRUSH.speckSizeMax, r),
				sizeMin = around(CRUSH.speckSizeMin, r),
				life = CRUSH.speckLife,
				gravity = 0,
			}, at, caught.colours, reduced, CRUSH.speckMaxLive)
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
		if ball.Color ~= ult.colour then
			ball.Color = ult.colour -- spec phase 5: each ultimate's own glow colour
		end
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
		sq = ThrowTracks.scaleAt(track, t) * ThrowTracks.flairAt(track, t) -- 2026-10-15: squash and stretch
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
				-- Feature 1: a charged throw kicks harder (ThrowCharge.release; design: html:333-339).
				local release = ThrowCharge.release(throw.power)
				v.kickVel += FP.kick.release * release.kick
				v.fovVel += THROW.fovKick * release.fovKick
				raiseShake(v, THROW.shake)
				releaseEffects(v, throw.power, release, reduced)
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
	elseif kind == "inspect" and v.inspect then
		-- The showcase (design: fp.js:408-410): the toy's offset on the hold point, its rotation and scale keys, and
		-- each hand from its rest toward the toy's side by the blend (both with the row's offset).
		local inspect = v.inspect :: Inspect
		local offset, rot = InspectTracks.toyAt(inspect.track, inspect.t)
		toyP += offset
		toyR = rot
		sq = InspectTracks.scaleAt(inspect.track, inspect.t)
		local sideL, sideR = ViewmodelMath.sides(toyP, hw)
		left, right = InspectTracks.handsAt(inspect.track, inspect.t, sideL, sideR, v.left.rest, v.right.rest)
	elseif kind == "empty" then
		left, right = v.left.rest, v.right.rest
		hide = true
	elseif kind == "charge" and toy then
		-- Feature 1: the charge (design: html:498-517; Anim/ChargePoses).
		local sideL, sideR = ViewmodelMath.sides(toyP, hw)
		local frame = { hold = toyP, sideL = sideL, sideR = sideR, restL = v.left.rest, restR = v.right.rest }
		local pose = ChargePoses.charge(v.chargeC, v.chargeT, frame, if settle then nil else v.random, reduced)
		toyP, sq = pose.toy, pose.scale
		left, right, lRoll, rRoll = pose.left, pose.right, pose.lRoll, pose.rRoll
		v.faceOverride = if pose.squish then "squish" else nil
		raiseShake(v, pose.shake)
		chargeEffects(v, toy, pose, dt, reduced)
	elseif kind == "catch" then
		-- Feature 1: the open hands (design: html:528-533).
		local sideL, sideR = ViewmodelMath.sides(toyP, hw)
		local frame = { hold = toyP, sideL = sideL, sideR = sideR, restL = v.left.rest, restR = v.right.rest }
		local pose = ChargePoses.catch(v.catchT, frame)
		toyP, left, right, lRoll, rRoll = pose.toy, pose.left, pose.right, pose.lRoll, pose.rRoll
	elseif kind == "crush" then
		-- Feature 1: the crush, then empty hands with the own toy back at the hold until the hands are free (design:
		-- html:535-569).
		local caught = v.caught
		if caught and not caught.burst then
			local sideL, sideR = ViewmodelMath.sides(toyP, hw)
			local frame = { hold = toyP, sideL = sideL, sideR = sideR, restL = v.left.rest, restR = v.right.rest }
			local pose = ChargePoses.crush(v.catchT, frame, if settle then nil else v.random, reduced)
			toyP = pose.held
			hide = true -- design: html:575 (the held toy hides while crushing)
			local at = drawCaught(caught, pose, dt)
			if not caught.arrived then
				catchArrived(v, caught, reduced)
			end
			crushEffects(v, caught, pose, at, dt, reduced)
			local l, r, lr, rr = ViewmodelMath.palms(at, caught.hw, pose.scale, 1, pose.press, v.catchT, now, reduced)
			left, right, lRoll, rRoll = l + pose.shake, r + pose.shake, lr, rr
			raiseShake(v, pose.cameraShake)
			if deps.Workspace:GetServerTimeNow() >= caught.burstAt then
				burstCaught(v, caught, at, reduced)
			end
		else
			left, right = v.left.rest, v.right.rest -- design: html:566
		end
	end
	-- Feature 1: the charge's and the crush's effect parts only show in their kinds; the face only while charging.
	if kind ~= "charge" then
		v.faceOverride = nil
		v.fx:outline(toyP, 0, false)
		if kind ~= "crush" or v.caught == nil or (v.caught :: Caught).burst then
			v.fx:glow(toyP, 0, Palette.White, 0)
			v.fx:orbit(toyP, 0, 0, 1, {}, false)
		end
	end
	v.fx:step(dt)
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
	-- The design's squash spring (toys.js:443-452): back to 1 on the toy's release spring after a showcase event's kick
	-- (fireEvent); held at exactly 1 at rest, so the low tier has nothing to redraw.
	if toy and (v.squashY ~= 1 or v.squashVel ~= 0) then
		if settle then
			v.squashY, v.squashVel = 1, 0
		else
			v.squashY, v.squashVel = ViewmodelMath.spring(v.squashY, v.squashVel, 1, toy.squash, dt)
			if math.abs(v.squashY - 1) < SQUASH_REST and math.abs(v.squashVel) < SQUASH_REST_SPEED then
				v.squashY, v.squashVel = 1, 0
			end
		end
	end
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
	local own = arm.own
	if own then
		OwnArm.partFrames(own, arm.pos, arm.shoulder, arm.roll, U, arm.frames)
		OwnArm.apply(own, arm.frames)
		return
	end
	local design = arm.arm
	if design then
		DesignArm.partFrames(arm.pos, arm.shoulder, arm.roll, arm.side, U, arm.frames)
		DesignArm.apply(design, arm.frames)
	end
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

-- The touch Inspect button (final polish 2026-10-11, build choice: the design's page has an "Inspect R" button in its
-- bottom bar, fp.js:562): on touch, in a look with showcases, at the bottom middle of the pad gui (anchored by its
-- bottom middle, inspectButtonInset up), then kept clear of the touch controls once its size is known
-- (ViewmodelMath.inspectButtonRect).
local function stepInspectButton(v: View)
	local button = v.inspectButton
	local wanted = v.toy ~= nil
		and v.pose == nil
		and deps.Controls.preferredInput() == Enum.PreferredInput.Touch
		and INSPECT_LOOKS[deps.FirstPerson.look() or ""] == true
	if not wanted then
		if button then
			button.root.Visible = false
		end
		return
	end
	local pad = ensurePad(v)
	if button == nil then
		local made = Button.new({
			name = INSPECT_BUTTON_NAME,
			text = Strings.common.inspect,
			kind = "secondary",
			icon = "inspect",
			parent = pad.gui,
			onActivated = function()
				ViewmodelController.inspect()
			end,
		})
		made.root.AnchorPoint = Vector2.new(0.5, 1)
		made.root.Position = UDim2.new(0.5, 0, 1, -INSPECT_INSET)
		made.root.ZIndex = 2 -- over the squeeze pad when the toy passes behind it (the pop-in)
		v.inspectButton = made
		v.cleanup:add(made)
		button = made
	end
	local shown = button :: Button.Button
	shown.root.Visible = true
	local padSize, size = pad.gui.AbsoluteSize, shown.root.AbsoluteSize
	if padSize.X <= 0 or padSize.Y <= 0 or size.X <= 0 or size.Y <= 0 then
		return -- not laid out yet: the bottom middle meanwhile
	end
	local uiScale = deps.UI.scale()
	local layout = pad.layout or deps.Controls.touchLayout(padSize, uiScale, nil)
	local rect = ViewmodelMath.inspectButtonRect(padSize, size, INSPECT_INSET * uiScale, layout)
	-- The pad gui holds UIController's UIScale: offsets are in unscaled pixels (the anchor is the bottom middle).
	local position = UDim2.fromOffset((rect.x + rect.w / 2) / uiScale, (rect.y + rect.h) / uiScale)
	if shown.root.Position ~= position then
		shown.root.Position = position
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

-- The design arms' sleeve (own arms wear the player's own shirt).
local function recolour(v: View)
	local sleeve = sleeveColour()
	for _, arm in { v.left, v.right } do
		local design = arm.arm
		if design then
			DesignArm.setColours(design, sleeve)
		end
	end
end

local function destroyArms(v: View)
	local own = v.ownArms
	v.ownArms = nil
	if own then
		OwnArm.destroy(own)
	end
	for _, arm in { v.left, v.right } do
		local design = arm.arm
		arm.arm, arm.own = nil, nil
		if design then
			DesignArm.destroy(design)
		end
		table.clear(arm.frames)
	end
end

-- The arms' parts: the player's own (Anim/OwnArm) when the character has usable R15 arms, else the design's
-- (Anim/DesignArm, the sleeve recoloured). The springs (hand, roll) are kept: a rebuild mid-throw does not jump.
local function buildArms(v: View, player: Player)
	destroyArms(v)
	local character = player.Character
	v.armsKey = OwnArm.signature(character)
	v.armsCheckIn = OWN_ARMS.recheckSeconds
	local ok: boolean, arms: any, why: any = pcall(OwnArm.make, character, v.viewport, U)
	if ok and arms then
		v.ownArms, v.armsWhy = arms, nil
		v.left.own, v.right.own = arms.left, arms.right
		return
	end
	if not ok then
		log:warn("own arms failed:", arms)
	end
	v.armsWhy = if ok then why else "error"
	v.left.arm = DesignArm.new(-1, v.viewport, U)
	v.right.arm = DesignArm.new(1, v.viewport, U)
	recolour(v)
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
	local offset = if reduced then 0 else v.fov * FOCUS.worldFovPerUnit + deps.Move.fovOffset()
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
			power = 0,
		}
		setKind(v, "throw")
	elseif name == "popin" then
		setKind(v, "equip")
		v.kindT = EQUIP.seconds / 2
	elseif name == "rush" then
		v.ult = { t = TELEGRAPH_S / 2, ch = 0.5, telegraph = TELEGRAPH_S, colour = ULT.glowColour }
		setKind(v, "ult")
	end
end

-- The world FOV spring toward the focus (fp.js:652). Feature 1: a charge narrows the world FOV on the same spring
-- (Charge.fovNarrowDeg × c; design: html:463). Phone speed fix (2026-10-16): it gets every frame's own time, also on a
-- frame where the low tier skips the overlay's step.
local function stepFov(v: View, dt: number)
	local chargeFov = if v.kind == "charge" then ThrowCharge.fovOffset(v.chargeC) / FOCUS.worldFovPerUnit else 0
	v.fov, v.fovVel = ViewmodelMath.spring(v.fov, v.fovVel, FOCUS.worldFovTarget * v.focus + chargeFov, SPRINGS.fov, dt)
end

local function step(v: View, dt: number, now: number): boolean
	if view ~= v then
		return false
	end
	local player = localPlayer()
	if player == nil then
		return true
	end
	-- Phone speed fix (2026-10-16): the low tier steps the overlay at most lowTier.stepHz times a second, with the time
	-- it skipped; the world FOV, the world camera and the touch pad step every frame with the frame's own time.
	local frameDt, due = dt, true
	if v.still and v.pose == nil then
		local phase
		due, phase = ViewmodelMath.throttle(v.stepPhase, dt, LOW_STEP_S)
		v.stepPhase = phase
		v.stepOwed += dt
		if due then
			dt, v.stepOwed = v.stepOwed, 0
		end
	end
	debug.profilebegin(PROFILE)
	local serverNow = deps.Workspace:GetServerTimeNow()
	local reduced = deps.Motion.reducedMotion()
	if not due then
		stepFov(v, if HitStop.holding(os.clock()) then frameDt * V2.hitStopTimeScale else frameDt)
		stepWorldCamera(v, reduced, v.shake) -- no new shake: only the overlay's step raises it
		stepPad(v, v.camera.CFrame)
		debug.profileend()
		return true
	end
	keepAxis(v, player)
	-- The avatar's looks (spec phase1-arms §3.8): a change rebuilds the arms (late appearance, an outfit, own <-> design).
	v.armsCheckIn -= dt
	if v.armsCheckIn <= 0 then
		v.armsCheckIn = OWN_ARMS.recheckSeconds
		if OwnArm.signature(player.Character) ~= v.armsKey then
			buildArms(v, player)
		end
	end
	local posed = v.pose
	if posed then
		dt, now, frameDt = 0, posed.now, 0 -- frozen
	else
		-- Feature 1: a hit-stop (a full charge's release, a catch, a burst) slows the overlay (design: html:422).
		if HitStop.holding(os.clock()) then
			dt *= V2.hitStopTimeScale
			frameDt *= V2.hitStopTimeScale
		end
		local holding = v.toy ~= nil and deps.Held.isHolding(player)
		stepKind(v, holding)
		stepThrow(v, serverNow, holding)
		stepUlt(v, dt, serverNow, holding)
		stepCharge(v, holding)
		stepCatch(v, holding)
		v.kindT += dt
	end
	-- The camera springs first (fp.js:652): the kick back to rest, the world FOV toward the focus (with the frame's own
	-- time: phone speed fix 2026-10-16), the shake falling.
	v.kick, v.kickVel = ViewmodelMath.spring(v.kick, v.kickVel, 0, SPRINGS.kick, dt)
	stepFov(v, frameDt)
	v.shake = math.max(0, v.shake - SHAKE.decayPerSecond * dt)
	local shakeFrom = v.shake
	if posed == nil then
		stepInspect(v, dt, reduced) -- after shakeFrom: an event's shake reaches the world camera as an action's does
	end
	local hide = stepAction(v, dt, now, reduced, posed ~= nil)
	if posed then
		v.fov, v.fovVel, v.kick, v.kickVel = FOCUS.worldFovTarget * v.focus, 0, 0, 0
	end
	stepSpecks(v, dt)
	showToy(v, not hide)
	-- The low tier keeps the kick (an action) and drops the idle drift (its time held at 0: sin(0) = 0).
	local cameraCF = if reduced
		then CFrame.identity
		else ViewmodelMath.overlayCamera(if v.still then 0 else now, v.kick, U) * deps.Move.overlaySway(U)
	v.camera.CFrame = cameraCF
	draw(v, cameraCF)
	stepWorldCamera(v, reduced, shakeFrom)
	local ghost = if serverNow < ghostUntil then FP.invulnTransparency else 0
	if ghost ~= v.ghost then
		v.ghost = ghost
		v.viewport.ImageTransparency = ghost
	end
	stepPad(v, cameraCF)
	stepInspectButton(v)
	debug.profileend()
	return true
end

-- Show and hide ---------------------------------------------------------------------------------------------------------

local function newArm(side: number): Arm
	return {
		side = side,
		arm = nil, -- buildArms makes the parts
		own = nil,
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
		left = newArm(-1),
		right = newArm(1),
		ownArms = nil,
		armsKey = "",
		armsWhy = nil,
		armsCheckIn = 0,
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
		stepPhase = LOW_STEP_S, -- the first frame steps
		stepOwed = 0,
		pose = nil,
		posedRig = nil,
		touchGui = nil,
		touchGuiOrder = 0,
		inspect = nil,
		specks = {},
		squashY = 1,
		squashVel = 0,
		inspectButton = nil,
		chargeC = 0,
		chargeT = 0,
		chargeRingIn = 0,
		chargeFull = false,
		speckDebt = 0,
		orbitAngle = 0,
		faceOverride = nil,
		fx = ChargeFx.new(viewport, U),
		caught = nil,
		catchT = 0,
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
		deps.Move.setFovRelay(false) -- the speed FOV is MoveFeelController's own again
	end)
	destroyToy(v)
	destroyCaught(v) -- feature 1
	v.fx:destroy()
	v.cleanup:clean()
	destroyArms(v)
	clearSpecks(v) -- the viewport stays (overlayOf): nothing of the showcase is left in it
	local glow = v.glow
	if glow then
		glow:Destroy()
	end
	v.viewport.ImageTransparency = 0
	v.gui.Enabled = false
end

local function show(player: Player)
	deps.Move.setFovRelay(true) -- the speed FOV comes through this overlay's own FOV hold (stepWorldCamera)
	local gui = deps.UI.screenGui(GUI_NAME, FP.gui :: any)
	local viewport, camera = overlayOf(gui)
	local v = newView(gui, viewport, camera)
	view = v
	buildArms(v, player)
	buildToy(v, player)
	v.cleanup:add(deps.Scheduler.add(function(dt: number, now: number): boolean
		return step(v, dt, now)
	end, "render"))
	deps.Held.setMirror(function(out: SquishRig.Out?, scale: Vector3)
		onMirror(v, out, scale)
	end, function(kind: string, count: number, colour: Color3)
		mirrorFx(v, kind, count, colour)
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
		v.faceOverride = nil -- feature 1
		if v.toy and deps.Held.isHolding(player) then
			equip(v) -- a new toy pops in (design: fp.js:96-107)
		else
			setKind(v, "empty")
		end
	end
end

-- Public -----------------------------------------------------------------------------------------------------------------

-- Spec phase 5: an ultimate's wind-up, the design's `charge` (Config.Abilities telegraphSeconds); none = Dragon Rush.
function ViewmodelController.ultTelegraphSeconds(ultimateId: string?): number
	local ability = (Config.Abilities :: any)[ultimateId or "dragon_rush"]
	return if ability then ability.telegraphSeconds else TELEGRAPH_S
end

-- Spec phase 5: the wind-up glow's colour (design: fp.js:460): Dragon's orange (Config.FirstPerson.ult.glowColour),
-- else the rarity colour of the squishy that owns the ultimate (Art/RarityStyle; the design's own rarity colours are
-- not used, user decision 2026-10-11).
function ViewmodelController.ultGlowColour(ultimateId: string?): Color3
	local id = ultimateId or "dragon_rush"
	if id == "dragon_rush" then
		return ULT.glowColour
	end
	for _, def in Catalog.list() do
		if def.ultimateId == id then
			local style = require(Shared.Art.RarityStyle).get(def.rarity)
			return if style then style.color else ULT.glowColour
		end
	end
	return ULT.glowColour
end

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

function ViewmodelController.inspect(): boolean
	local v = view
	return v ~= nil and startInspect(v)
end

function ViewmodelController.debugInspect(t: number?): boolean
	local v = view
	if v == nil then
		return false
	end
	if t == nil then
		return ViewmodelController.debugPose(nil)
	end
	local toy = v.toy
	local track = if toy then InspectTracks.get(toy.id) else nil
	if track == nil or t ~= t then
		return false
	end
	ViewmodelController.debugPose(nil) -- lets go of another pose first (its rig press)
	local at = math.clamp(t, 0, track.dur)
	v.pose = { name = INSPECT_POSE, now = os.clock() }
	setKind(v, "inspect")
	v.inspect = { track = track, t = at, fired = InspectTracks.firedBy(track, at) } -- frozen: no event fires
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
		local own, design = arm.own, arm.arm
		local parts: { [string]: BasePart } = if own then own.parts elseif design then design.parts else {}
		for name in parts do
			table.insert(list, name)
		end
		table.sort(list)
		return list
	end
	local throw = v.throw
	local toy = v.toy
	local src = v.mirror
	local rightOwn, rightDesign = v.right.own, v.right.arm
	local handPart: BasePart? = if rightOwn then rightOwn.hand elseif rightDesign then rightDesign.parts.hand else nil
	return {
		shown = true,
		look = deps.FirstPerson.look(),
		kind = v.kind,
		toy = if toy then toy.id else nil,
		toyShown = v.toyShown,
		hw = if toy then toy.hw else nil,
		arms = if v.ownArms then "own" else "design",
		armsWhy = v.armsWhy,
		leftParts = names(v.left),
		rightParts = names(v.right),
		sleeve = if rightDesign then rightDesign.parts.sleeve.Color:ToHex() else nil,
		skin = if handPart then handPart.Color:ToHex() else nil,
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
		inspecting = v.inspect ~= nil,
		inspectTime = if v.inspect then v.inspect.t else nil,
		inspectFired = if v.inspect then v.inspect.fired else nil,
		specks = #v.specks,
		squash = v.squashY,
		inspectButton = v.inspectButton ~= nil and v.inspectButton.root.Visible,
		charge = v.chargeC, -- feature 1
		caught = if v.caught then v.caught.id else nil,
		caughtBurst = v.caught ~= nil and v.caught.burst,
		fxRings = v.fx:ringCount(),
		padShown = v.pad ~= nil and v.pad.button.Visible,
		touchGuiRaised = v.touchGui ~= nil,
		viewportParts = #v.viewport:GetDescendants(),
		lowTier = v.still, -- phone speed fix 2026-10-16: the overlay's step cap is on (unless lowTier.stepHz is 0)
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
	c:add(deps.Controls.bindAction(INSPECT_ACTION, inspectHandler))
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
