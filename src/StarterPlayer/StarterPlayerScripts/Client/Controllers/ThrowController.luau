--!strict
-- ThrowController (client only). DESIGN §5.6, §5.9, §5.10, §9.7, §9.10 (caster poses), §11.6 (cooldown hooks), §12 #8.
-- Aim, throw and ultimate input; the predicted windup only (the projectile appears only from ThrowStarted, drawn by
-- ProjectileRenderer). The server decides everything; this module sends intent and animates.
--
-- Throw (Duel context in Active/SuddenDeath, or the Practice context; keys in ControlsController):
--   * Aim (§5.10): mouse ray (Camera:ViewportPointToRay at the mouse; the screen centre in shift lock) or the centre
--     crosshair (touch, gamepad); a raycast in the Default collision group that leaves out the local character and
--     Workspace.SD_ClientFx (arena barriers and dividers are skipped by their groups). A ray that hits nothing (open
--     sky) aims at the opponent's distance in a duel, the farthest practice target in practice (missReach), capped at
--     Config.Combat.Aim.maxRayStuds (200). Reading (user test, Part 4): a plain 200 studs made every press just above
--     the opponent a lob far past the ~90-stud court ("it throws the squishy to the moon"). That point is only the
--     aim state's now: a throw whose ray hits nothing leaves along the crosshair (missDirection, user bug report
--     2026-10-11: aimed well above the opponent, the solved arc to that point in the air still went "all the way
--     up"; the Combat FP design throws along the camera direction too), unless aim assist moved the point.
--   * Aim assist (Config.Combat.AimAssist; gamepad 4°, touch 5°, 50%; off for keyboard/mouse), applied once at throw
--     time: when the opponent's capsule centre (practice: the nearest practice target, reading; a duel bot: its rig in
--     Workspace.SD_Bots) is inside the cone and in line of sight, the aim point moves `strength` of the way toward it.
--   * aimDir = ProjectileMath.solveLaunchDir(originHint, aimPoint, speed, g) (a ray that hit nothing: the ray's own
--     direction), then clamped to the pitch band [-35°, +65°] and, in practice, into the 75° cone around the range
--     forward (+X) (limitDirection: clampPitch / clampToCone).
--   * ThrowRequest(seq, aimDir, originHint = HRP.CFrame * ReleaseOffset, clientTime = GetServerTimeNow()) through
--     NetController.throwRequest (its per-remote seq counter, local shape checks and token buckets); a request the
--     NetController drops locally starts no windup.
--   * Readiness: the server accepts a press when releaseAt = press + windup >= nextThrowAt - 0.05, so the client
--     treats readyAt = nextThrowAt - windup as "cooldown over" (reading: §9.5 "pop-in when the cooldown ends" and the
--     ring fill use it). A press up to Rules.InputBufferSeconds (0.15) before readyAt (or before a Dragon Rush root
--     ends) is buffered; an earlier press is dropped once readyAt is known (bufferKeeps, pure). One throw is in flight
--     at a time (no second request before ThrowStarted / ThrowRejected). A CAS Cancel drops the hold, the buffer and a
--     charge; a sent request is never cancelled. A ThrowRejected nextThrowAt that is not finite or lies more than
--     REJECT_AHEAD_SECONDS ahead never blocks the client: it is ignored (defensive: the server keeps nextThrowAt
--     finite, §5.2).
--   * Hold to charge (feature 1, 2026-10-11, user-approved plan; Rules.HoldToCharge, was HoldToRepeat; Config.Combat.
--     Charge, Shared/ThrowCharge; design: the combat-effects page "Squishy Combat FP v2.html", html:323-341, 393-394,
--     437, 463, 498-517): holding Throw charges c 0 -> 1 over Charge.seconds from the moment the throw is ready (no
--     request in flight, no windup, no root, the cooldown over, the hands free: canCharge); letting go throws with that
--     charge. A press during the cooldown that is still held when the throw becomes ready starts charging then; one let
--     go before that still throws, uncharged, at readyAt when it was at most InputBufferSeconds early (the buffer). Every
--     throw first sends ChargeStart(clientTime): at the charge's start, or right before an uncharged throw, so the
--     server's own record is always this throw's; the server measures the charge (Logic/ThrowRules) and the client only
--     uses its own c to solve the aim for the faster throw (speed × ThrowCharge.speedFactor), so the throw lands on the
--     reticle. While charging: walk speed × Charge.walkFactor (written on the own Humanoid, put back unless something
--     else changed it), the charge tone (sfx.chargeLoop, pitch and volume by ThrowCharge.tone) and sfx.chargeFull the
--     moment it is full; the reticle and the first-person overlay read getAimState / localCharge. A catch press
--     (CatchController: cancelCharge, setHandsBusy), an ultimate press, a lost context or a death drops the charge
--     without a throw. Rules.HoldToCharge false: every press throws at once, uncharged.
--   * Touch and gamepad aim from the screen centre, so in the Duel and Practice contexts the camera sits over the right
--     shoulder: Humanoid.CameraOffset = HRP:VectorToObjectSpace(camRight × 1.75) every frame (§5.10; reading: gamepad
--     too, "same as touch"), restored to its saved value when the context ends or the input switches to mouse, and
--     off while first person suppresses it (setShoulderSuppressed, first-person spec 2026-10-10 §3.1).
--   * Windup (§9.7): throwWindup weight 0 -> 1 (Quad Out) by 0.6 W, then held cocked; the held squishy's rig is held
--     at c = 1 - 0.10 × weight (windupHold; direct, no spring, widened by the toy's own widen; from the rig's depth at
--     the press, so a throw pressed mid-squeeze never pops, first-person spec 2026-10-10 §3.5) and shows the squish
--     face once cocked (squishy overhaul spec 2026-10-09 §3.2), both told before the rig steps (the overlay's prepare,
--     windupRigHold), so they show in the same frame. On the own ThrowStarted (matched by seq) the rest of
--     the windup is time-warped onto releaseAt (rate clamped [0.5, 3]); at releaseAt the arm snaps to throwRelease
--     (70 ms, Quint Out), follows to throwFollow (to W + 250 ms, Quad Out) and returns (weight 1 -> 0 by W + 450 ms,
--     Sine InOut), and the held model hides until readyAt, then pops in (0.6 -> 1, spring ω 16, ζ 0.55).
--     ThrowRejected, or no answer 600 ms after the windup completed, cancels: weight -> 0 in 120 ms, no projectile
--     (the rig lets go and springs back).
--   * Sounds (§18.4.5, §18.6): the local player's pop-in ("throw ready again") plays sfx.pop 3D at the own held
--     squishy; a ThrowRejected answering the own pending request plays ui.error (its 250 ms cooldown is
--     SoundController's). Other players' pop-ins and stale rejections stay silent (popInSound / rejectSound, pure).
--   * Other throwers (ThrowStarted with another throwerId): windup scheduled on releaseAt - W (or joined midway),
--     else straight to release + follow-through; their held model hides and pops in the same way.
--   * Full-body throws (2026-10-15 throw overhaul): an R15 thrower's throw layer plays its toy's style clip
--     (Anim/ThrowMotion, by Anim/ThrowTracks.styleOf; on the windup / release clock and weights above, so the server's
--     timing is unchanged), the legs too when it stood still as the windup began (setStyle); from the release the
--     throwing hand trails a smear in the toy's accent (Anim/ThrowVfx "HandSwoosh", none on a hidden hand). R6 and
--     the ultimate caster keep the poses.
-- Ultimate (Dragon Rush, §5.9, §9.10; the Epic ultimates, spec phase 5): Q / ButtonL2 / touch, when the locked squishy
--   has an ultimateId and the charge is full (duel; UltimateCharge) or the practice cooldown (10 s) ran out.
--   UltimateRequest(seq, flat aim, clientTime). Predicted ultCharge pose until the telegraph (cancelled if none within
--   600 ms); telegraph: ultCharge held, the caster is rooted (no throws) until telegraphEndsAt + that ability's
--   recoverySeconds (the event's ultimateId; none = Dragon Rush, eventAbility); release: arms snap to throwRelease
--   (80 ms), then the rushRecovery hunch, weight -> 0 in 400 ms; cancel: blend out. Every ultimate uses this caster
--   pose (spec phase 5: the design has none of its own). A release's own projIds (the lane, the roller, the bubble,
--   each Flock Volley bird, each Rain Check drop) are remembered for HitConfirmed.
-- Hooks for the HUD (cooldown display): getAimState() every frame (reticle position in viewport pixels,
--   ready / cooling / blocked + reason code, readyAt, nextThrowAt, progress), getUltState(), and the signals
--   CooldownChanged(readyAt, nextThrowAt), Rejected(reason, nextThrowAt), HitConfirmed(impact) (an own throw, or an
--   own Dragon Rush lane, hit a player or a practice target). Touch buttons (ControlsController) get their cooldown
--   look from here; the reticle and hit marker are drawn from getAimState / HitConfirmed by DuelController (duel) and
--   PracticeController (practice range).
-- Hooks for the first-person hand (spec 2026-10-10 §3.6): localWindup() and localUlt(), the local windup and Dragon
--   Rush as plain values (duel or practice), read every frame; the records stay private.
-- Match view and ultimate charges: StateController (duel(), DuelChanged, charge(userId)); remote events through
-- NetController.on.
-- No lobby stat is read here: throws use only the match snapshot's squishy (duel) or SD_Equipped (practice).
-- FFA/TDM v1 (2026-10-15; the 12-player Free for All / Team Deathmatch, SPEC C5/C6): a third kind, "match", while the
--   Duel input context is on and StateController.match() is set (no duel view): the same live-phase rule (Active, the
--   Countdown's last instant; overtime is "Active"), the match's own squishy (you.squishyId), cooldown multiplier 1,
--   nothing while knocked out (you.alive false: "throw.context"), no own half (the server keeps the throw inside the
--   map's Bounds); aim assist and the missing-ray reach anchor on every live enemy (StateController.enemyIds: FFA
--   everyone else, TDM the other team), never on the practice targets; the ultimate needs its charge, as in a duel,
--   never the practice cooldown. MatchChanged resets the cooldown at a new match and at Active and ends the windups at
--   the match's end, as DuelChanged does. No new top-level local (module fields and StateController calls only).
-- Power-ups v1.1 (2026-10-16, SPEC P3): in a match the context carries the own power-ups from the view's you.buffs
--   (StateController.buffMultiplier): rapid throw's cooldownMultiplier (Config.Match.PowerUps.kinds.rapidThrow) and
--   throw boost's speedMultiplier (kinds.throwBoost), 1 while they are off. The aim is solved for the boosted speed
--   (throwDirection: speed × ThrowCharge.speedFactor(c) × speedMultiplier, as the server's launch), so the faster
--   throw still lands on the reticle. The cooldown gate stays the server's nextThrowAt from ThrowStarted, which the
--   server already works out with rapid throw's multiplier, so the client is never looser than the server (a pickup in
--   the middle of a cooldown does not shorten that cooldown on either side). Other players' boosted throws need
--   nothing here: ThrowStarted carries their velocity (ProjectileRenderer draws it). Still no new top-level local.
--   Review fixes (2026-10-16): the throw boost is read for the moment the request reaches the server (half the ping
--   plus Config.Combat.Lag.halfPingExtraSeconds after the press, where the server reads it), so a throw pressed as
--   the boost ends is solved for the speed it is launched at. In a match the client mirrors the server's
--   Rules.MaxActiveProjectilesPerPlayer (throw.tooMany): while that many own throws fly (ThrowStarted until their
--   ThrowImpact, or OWN_PROJECTILE_SECONDS), a press sends nothing and starts no windup (atThrowCap; the reticle shows
--   "cooling"); a held Throw starts charging once one lands, a tap is dropped. Duels and practice are unchanged.
--   Integration (2026-10-16): the match context's cooldownMultiplier is the server's own number for a live rapid
--   throw (rapidCooldownMultiplier, pure: MatchService's throwCooldownMultiplier, kinds.rapidThrow.cooldownMultiplier
--   kept at or above CooldownClamp.Min / the clamped catalog cooldown, so the cooldown is exactly CooldownClamp.Min),
--   read at the request's arrival like the throw boost; still informational (the gate is the server's nextThrowAt).
-- Aim arc (2026-10-16, jayyyyy's yes; AimArcController draws it): fire()'s origin + direction moved, unchanged, into
--   launchFor (one path for a real throw and the preview), the launch speed into launchSpeed (pure: the toy's speed ×
--   ThrowCharge.speedFactor(c) × the throw boost, ThrowRules' own launch). chargePreview() is the throw a release right
--   now would launch while a charge runs: launchFor's origin and direction × launchSpeed for the charge the server will
--   measure, the toy's gravity and radius. The arc's every-frame launchFor does not count in stats.assisted (assisted's
--   `count`). Still no new top-level local (module fields only).

-- Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local ProjectileMath = require(Shared.ProjectileMath)
local Signal = require(Shared.Util.Signal)
local Spring = require(Shared.Util.Spring)
local Strings = require(Shared.Strings)
local ThrowCharge = require(Shared.ThrowCharge)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local SquishRig = require(Client.Anim.SquishRig)
local ThrowMotion = require(Client.Anim.ThrowMotion)
local ThrowTracks = require(Client.Anim.ThrowTracks)
local ThrowVfx = require(Client.Anim.ThrowVfx)
local CharacterAnimController = require(script.Parent.CharacterAnimController)
local ControlsController = require(script.Parent.ControlsController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)

-- Types

export type AimStateName = "hidden" | "ready" | "cooling" | "blocked"
export type AimState = {
	state: AimStateName,
	reason: string?, -- blocked: "throw.context" (wrong place / phase), "throw.direction", "throw.rooted" (§2.10 reason codes)
	screenPosition: Vector2, -- reticle position in viewport pixels (GetMouseLocation space; subtract the GUI inset)
	centered: boolean, -- true on touch, gamepad and shift lock (the reticle sits at the screen centre)
	aimPoint: Vector3?,
	readyAt: number, -- server time from which a press is accepted
	nextThrowAt: number, -- server time, from the server
	progress: number, -- 0 (just thrown) .. 1 (ready)
	kind: ("duel" | "practice" | "match")?,
	-- Feature 1 (2026-10-11): the local charge c (0 when not charging), whether it is full, and the held toy's colour
	-- (its Catalog accent) for the reticle's charge fill.
	charging: boolean,
	charge: number,
	chargeFull: boolean,
	chargeColor: Color3?,
}

-- Aim arc (2026-10-16): the throw a release right now would launch (chargePreview): the server's launch (origin,
-- velocity, the toy's gravity and radius; ProjectileMath.positionAt draws its path), the local charge c and the toy's
-- accent for the looks.
export type ChargePreview = {
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	radius: number,
	charge: number,
	color: Color3?,
}

export type UltState = {
	available: boolean, -- the locked squishy has an ultimate
	charge: number,
	chargeMax: number,
	ready: boolean,
	practiceReadyAt: number,
	rooted: boolean,
}

-- One pose frame of the throw / ultimate layer: blend `from` -> `to` by u, at `weight`; `squash` = 0..1 of the held
-- squishy's anticipation squash.
-- 2026-10-15: `phase` ("windup" / "release") and `t` (windup share u, or seconds since the release) drive the
-- full-body clip (Anim/ThrowMotion); the ultimate's samples have none.
export type Sample = {
	from: string,
	to: string,
	u: number,
	weight: number,
	squash: number,
	phase: string?,
	t: number?,
}

-- A throw animation of one character.
export type Windup = {
	windup: number, -- W, seconds
	tau: number, -- animation time since the windup started (0..W)
	remote: boolean, -- true: time-mapped onto releaseAt (other throwers, late answers)
	releaseAt: number?, -- server time, known after ThrowStarted
	releaseStart: number?, -- server time the release visual began
	deadline: number, -- server time: an unanswered windup cancels after this
	cancelled: boolean,
	cancelElapsed: number,
	cancelFrom: Sample?,
	last: Sample?,
	finished: boolean,
	popAt: number?, -- server time the held squishy pops back in (readyAt), known after ThrowStarted
	squishyId: string?, -- 2026-10-15: the thrown toy (setStyle)
	style: string?, -- its throw style (Anim/ThrowTracks), whose full-body clip plays (Anim/ThrowMotion)
	legs: boolean?, -- the clip moves the legs too (the thrower stood still as the windup began)
	swooshed: boolean?, -- the hand smear has started
}

export type ThrowStarted = Types.ThrowStartedPayload
export type ThrowImpact = Types.ThrowImpactPayload
export type UltimateEvent = Types.UltimateEventPayload
export type MatchView = StateController.DuelView

type Ctx = {
	kind: "duel" | "practice" | "match", -- FFA/TDM v1: "match"
	def: Types.SquishyDef,
	cooldownMultiplier: number,
	speedMultiplier: number?, -- power-ups v1.1: throw boost in a match (nil = 1)
}

type UltAnim = {
	phase: "cast" | "telegraph" | "release" | "cancel",
	ultimateId: string, -- Config.Abilities key (spec phase 5)
	recoverySeconds: number, -- that ability's
	startedClock: number, -- os.clock() of the cast / cancel start
	telegraphEndsAt: number?,
	releaseStart: number?, -- server time
	cancelFrom: number, -- weight when the cancel began
	weight: number,
	finished: boolean,
}

type PopIn = { spring: Spring.Spring<number>, untilClock: number }

type Pending = { seq: number, sentAt: number, windup: number }

-- An own projectile remembered for hit confirmation; a Dragon Rush lane can hit more than once. Power-ups v1.1 review
-- fix: `throw` = an own throw (ThrowStarted), the kind the server's MaxActiveProjectilesPerPlayer counts.
type OwnProjectile = { untilAt: number, lane: boolean, throw: boolean? }

type Shoulder = { humanoid: Humanoid, saved: Vector3 }

-- Feature 1: the local charge, from server time `startAt`; `sent` = its ChargeStart left (else the server measures 0,
-- so the aim is solved uncharged too); `full` = the full ping played; `color` the held toy's accent.
type Charge = { startAt: number, sent: boolean, full: boolean, color: Color3? }

-- Feature 1: the walk speed written while charging, put back at the end unless something else changed it.
type WalkHold = { humanoid: Humanoid, saved: number, written: number }

-- Constants

local THROW_ANIM = Config.Anim.throw
local POSES = Config.Anim.poses
local HELD = Config.Anim.held
local COMBAT = Config.Combat
local RULES = Config.Duel.Rules
local RUSH_VFX = Config.Vfx.DragonRush
local HITBOX = COMBAT.Hitbox
local LAYER_THROW = "throw"
local LEGS_MAX_SPEED = 4 -- studs/s: a thrower moving faster keeps its run (no legs in the clip)
local SWOOSH_SECONDS = 0.26 -- the hand smear from the release
local LAYER_ULT = "ult"
local THROW_PRIORITY = POSES.throwWindup.priority or 2
local OVERLAY_THROW = "throw"
local OVERLAY_POP = "popIn"
local HIDE_REASON = "thrown"
local ATTR_EQUIPPED = "SD_Equipped"
local CLIENT_FX = "SD_ClientFx"
local BOTS_FOLDER = "SD_Bots" -- BotService: a duel bot's rig, named after the bot
local SNAP_S = THROW_ANIM.releaseSnapMs / 1000
local FOLLOW_S = THROW_ANIM.followEndMs / 1000
local RETURN_S = THROW_ANIM.returnEndMs / 1000
local CANCEL_S = THROW_ANIM.cancelBlendMs / 1000
local COCKED_S = THROW_ANIM.cockedHoldMaxMs / 1000
local REACH = THROW_ANIM.windupReachFraction
local DUEL_END_BLEND_S = Config.Anim.joints.duelEndBlendMs / 1000
-- Capsule centre above the HRP: (bottomOffset + topOffset) / 2 (§5.5).
local CAPSULE_CENTRE_Y = (HITBOX.bottomOffset + HITBOX.topOffset) / 2
-- The capsule's lowest point is the floor: HRP height above the floor = radius - bottomOffset (3.0 studs).
local HRP_ABOVE_FLOOR = HITBOX.radius - HITBOX.bottomOffset
local RANGE = WorldLayout.PracticeRange
local RANGE_FORWARD = Vector3.new(RANGE.throwDirection.X, 0, RANGE.throwDirection.Z).Unit
-- reading (not in DESIGN, provisional): the client stays 1° inside the server's practice cone (rounding margin).
local CONE_MARGIN_DEG = 1
-- reading (not in DESIGN, provisional): the predicted ultCharge pose blends in over this long.
local ULT_CAST_BLEND_S = 0.15
-- reading: release to rushRecovery hunch after the 80 ms arm snap.
local ULT_HUNCH_S = 0.1
local ULT_RECOVERY_BLEND_S = RUSH_VFX.recoveryBlendMs / 1000
local ULT_SNAP_S = RUSH_VFX.releaseArmSnapMs / 1000
local ULT_CAST_MAX_S = RUSH_VFX.castPredictMaxMs / 1000
-- An own projectile is remembered this long for hit confirmation.
local OWN_PROJECTILE_SECONDS = RULES.ProjectileMaxLifetime + 2
-- reading (not in DESIGN): a ThrowRejected nextThrowAt further ahead than the longest cooldown plus this margin is
-- not a cooldown and is ignored (defensive: the server keeps nextThrowAt finite, §5.2).
local REJECT_AHEAD_SECONDS = RULES.CooldownClamp.Max + 1
local SHOULDER_STUDS = COMBAT.Aim.touchShoulderOffsetStuds
local PHASE_THROW: { [string]: boolean } = { Active = true, SuddenDeath = true }
local PHASE_ENDED: { [string]: boolean } = { Result = true, Returning = true, Cancelled = true, Void = true }
local POP_SETTLE = 0.002
local POP_MAX_SECONDS = 1
local SOUND_POP = "sfx.pop" -- the local throw is ready again (§18.6)
local SOUND_REJECTED = "ui.error" -- an own ThrowRejected (§18.4.5)
-- Feature 1 (2026-10-11): the charge tone and the full-charge ping (design: html:323, 514, 517).
local SOUND_CHARGE_LOOP = "sfx.chargeLoop"
local SOUND_CHARGE_FULL = "sfx.chargeFull"
local CHARGE_TONE_STOP_MS = Config.Audio.charge.stopFadeMs

-- Module table

local ThrowController = {}

ThrowController.CooldownChanged = Signal.new() :: Signal.Signal<number, number>
ThrowController.Rejected = Signal.new() :: Signal.Signal<string, number>
ThrowController.HitConfirmed = Signal.new() :: Signal.Signal<ThrowImpact>

-- Private state

local log = Log.new("Throw")
local cleanup: Cleanup.Cleanup? = nil
local match: MatchView? = nil
local lastSeq = 0
local nextThrowAt = 0
local readyAt = 0
local lastReleaseAt = 0
local pending: Pending? = nil
local holdDown = false
local bufferedAt: number? = nil
local charge: Charge? = nil -- feature 1: the running charge (hold Throw)
local chargeTone: SoundController.Loop? = nil
local walkHold: WalkHold? = nil
local handsBusyUntil = -math.huge -- feature 1: server time: an open catch window or a crush (setHandsBusy)
local windups: { [Player]: Windup } = {}
local ults: { [Player]: UltAnim } = {}
local hiddenUntil: { [Player]: number } = {}
local popIns: { [Player]: PopIn } = {}
local ownProjectiles: { [number]: OwnProjectile } = {} -- projId -> forget-after (server time)
local shoulder: Shoulder? = nil
local shoulderSuppressed = false -- first person is on (setShoulderSuppressed)
local practiceUltReadyAt = 0
local rootedUntil = 0
local aimParams: RaycastParams? = nil
local aimCharacter: Model? = nil
local aimState: AimState = {
	state = "hidden",
	reason = nil,
	screenPosition = Vector2.zero,
	centered = true,
	aimPoint = nil,
	readyAt = 0,
	nextThrowAt = 0,
	progress = 1,
	kind = nil,
	charging = false,
	charge = 0,
	chargeFull = false,
	chargeColor = nil,
}
local stats = { throwsSent = 0, ultsSent = 0, accepted = 0, rejected = 0, cancelled = 0, assisted = 0 }
local connections: { Signal.Connection } = {}

-- Pure helpers ------------------------------------------------------------------------------------------------------

local function ease(alpha: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): number
	return TweenService:GetValue(math.clamp(alpha, 0, 1), style, direction)
end

local function newSample(from: string, to: string, u: number, weight: number, squash: number): Sample
	return { from = from, to = to, u = u, weight = weight, squash = squash }
end

-- Windup ("charge") curve (§9.7): weight 0 -> 1 (Quad Out) by windupReachFraction × W, then held at 1 (cocked).
function ThrowController.windupWeight(tau: number, windup: number): number
	if not (windup > 0) then
		return 1
	end
	return ease(tau / (REACH * windup), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

-- Time-warp rate of the rest of the windup onto releaseAt (§9.7), clamped to [timeWarpMin, timeWarpMax].
-- remainingReal <= 0 means releaseAt has passed: the fastest rate (the release then snaps).
function ThrowController.warpRate(remainingAnim: number, remainingReal: number): number
	if not (remainingReal > 0) then
		return THROW_ANIM.timeWarpMax
	end
	return math.clamp(math.max(remainingAnim, 0) / remainingReal, THROW_ANIM.timeWarpMin, THROW_ANIM.timeWarpMax)
end

-- Pose during the windup at animation time tau.
function ThrowController.windupSample(tau: number, windup: number): Sample
	local weight = ThrowController.windupWeight(tau, windup)
	local sample = newSample("throwWindup", "throwWindup", 0, weight, weight)
	sample.phase = "windup"
	sample.t = if windup > 0 then math.clamp(tau / windup, 0, 1) else 1
	return sample
end

-- The held squishy during a windup with anticipation squash `squash` (0-1, the sample's): the value its rig is held at
-- (1 -> anticipationC 0.90 on the squeeze axis) and whether it is cocked (the squish face shows from then on).
-- First-person spec 2026-10-10 §3.5: the hold starts from the rig's depth at the throw press, yPress (default 1), as
-- windupHold(squash) + (yPress - 1)·(1 - squash), so a throw pressed mid-squeeze eases from where the toy is to 0.90
-- and never pops; with yPress = 1 the value is exactly the plain one.
function ThrowController.windupHold(squash: number, yPress: number?): (number, boolean)
	local s = if squash == squash then math.clamp(squash, 0, 1) else 0
	local from = if yPress ~= nil and yPress == yPress then yPress else 1
	return 1 + (THROW_ANIM.anticipationC - 1) * s + (from - 1) * (1 - s), s >= 1
end

-- One windup frame on the held squishy's rig, told before the rig steps (the overlay's prepare): holds it at
-- windupHold(squash, yPress) and turns the squish face on once cocked (off again if it is not any more). Returns whether
-- it is cocked now; pass that back as `cocked` the next frame. `mirrored` (the first-person overlay shows this rig):
-- no hold and no face, and a hold already made is let go (spec 2026-10-11 §3.5; the design's throw does not squash the
-- toy, fp.js:430-443), so the rig goes on with its own squeeze; returns false.
function ThrowController.windupRigHold(
	rig: SquishRig.Rig,
	squash: number,
	cocked: boolean,
	yPress: number?,
	mirrored: boolean?
): boolean
	if mirrored then
		rig:clearHold()
		if cocked then
			rig:setFace("normal")
		end
		return false
	end
	local c, nowCocked = ThrowController.windupHold(squash, yPress)
	rig:hold(c)
	if nowCocked ~= cocked then
		rig:setFace(if nowCocked then "squish" else "normal")
	end
	return nowCocked
end

-- Pose t seconds after the release (§9.7): snap to throwRelease (Quint Out), follow to throwFollow (Quad Out), then
-- the weight returns to 0 (Sine InOut). Returns the sample and whether the throw animation is over.
local function releasePose(t: number): (Sample, boolean)
	if t < SNAP_S then
		local u = ease(t / SNAP_S, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		return newSample("throwWindup", "throwRelease", u, 1, 0), false
	elseif t < FOLLOW_S then
		local u = ease((t - SNAP_S) / (FOLLOW_S - SNAP_S), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		return newSample("throwRelease", "throwFollow", u, 1, 0), false
	elseif t < RETURN_S then
		local k = ease((t - FOLLOW_S) / (RETURN_S - FOLLOW_S), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		return newSample("throwFollow", "throwFollow", 0, 1 - k, 0), false
	end
	return newSample("throwFollow", "throwFollow", 0, 0, 0), true
end

function ThrowController.releaseSample(t: number): (Sample, boolean)
	local sample, done = releasePose(t)
	sample.phase = "release"
	sample.t = t
	return sample, done
end

-- A windup that starts now. `deadline` = server time after which an unanswered windup cancels.
function ThrowController.newWindup(windup: number, deadline: number, remote: boolean?): Windup
	return {
		windup = windup,
		tau = 0,
		remote = remote == true,
		releaseAt = nil,
		releaseStart = nil,
		deadline = deadline,
		cancelled = false,
		cancelElapsed = 0,
		cancelFrom = nil,
		last = nil,
		finished = false,
		popAt = nil,
	}
end

-- 2026-10-15: the full-body clip a windup plays (Anim/ThrowMotion): its toy's throw style, and the legs too when the
-- thrower stands still as it begins (a running throw keeps its run). `root` nil = no legs.
function ThrowController.setStyle(w: Windup, squishyId: string?, root: BasePart?)
	w.squishyId = squishyId
	w.style = if squishyId then ThrowTracks.styleOf(squishyId) else nil
	local v = if root then root.AssemblyLinearVelocity else nil
	w.legs = v ~= nil and Vector3.new(v.X, 0, v.Z).Magnitude < LEGS_MAX_SPEED
end

-- Cancels a windup (rejected / unanswered): its last pose fades out over cancelBlendMs.
function ThrowController.cancelWindup(w: Windup)
	if w.cancelled or w.finished then
		return
	end
	w.cancelled = true
	w.cancelElapsed = 0
	w.cancelFrom = w.last or ThrowController.windupSample(w.tau, w.windup)
end

-- A windup record as plain values (tau, W, releaseAt, releaseStart, cancelled); nil, nil, nil, nil, false for none
-- (localWindup; first-person spec 2026-10-10 §3.6).
function ThrowController.windupValues(w: Windup?): (number?, number?, number?, number?, boolean)
	if w == nil then
		return nil, nil, nil, nil, false
	end
	return w.tau, w.windup, w.releaseAt, w.releaseStart, w.cancelled
end

-- An ultimate record as plain values (phase, telegraphEndsAt, releaseStart, ultimateId); nil, nil, nil, nil for none
-- (localUlt).
function ThrowController.ultValues(ult: UltAnim?): (string?, number?, number?, string?)
	if ult == nil then
		return nil, nil, nil, nil
	end
	return ult.phase, ult.telegraphEndsAt, ult.releaseStart, ult.ultimateId
end

-- Advances one throw animation by dt at server time `serverNow`. Returns the pose to show (nil = nothing yet, e.g. a
-- remote windup scheduled for later) and marks w.finished when it is over.
function ThrowController.stepWindup(w: Windup, dt: number, serverNow: number): Sample?
	if w.finished then
		return nil
	end
	if w.cancelled then
		w.cancelElapsed += dt
		local from = w.cancelFrom or ThrowController.windupSample(w.tau, w.windup)
		local k = 1 - math.clamp(w.cancelElapsed / CANCEL_S, 0, 1)
		if k <= 0 then
			w.finished = true
		end
		local sample = newSample(from.from, from.to, from.u, from.weight * k, from.squash * k)
		sample.phase, sample.t = from.phase, from.t
		w.last = sample
		return sample
	end
	local releaseAt = w.releaseAt
	if releaseAt ~= nil and serverNow >= releaseAt then
		if w.releaseStart == nil then
			-- On time (we were ticking toward it) the release starts exactly at releaseAt; a late answer starts it now.
			w.releaseStart = if serverNow - releaseAt <= math.max(dt, 1 / 30) then releaseAt else serverNow
		end
		local sample, done = ThrowController.releaseSample(serverNow - (w.releaseStart :: number))
		w.finished = done
		w.last = sample
		return sample
	end
	if w.remote then
		if releaseAt == nil then
			return nil
		end
		local startAt = releaseAt - w.windup
		if serverNow < startAt then
			return nil
		end
		w.tau = math.clamp(serverNow - startAt, 0, w.windup)
	else
		local rate = 1
		if releaseAt ~= nil then
			rate = ThrowController.warpRate(w.windup - w.tau, releaseAt - serverNow)
		end
		w.tau = math.min(w.tau + dt * rate, w.windup)
		if releaseAt == nil and serverNow > w.deadline then
			local sample = ThrowController.windupSample(w.tau, w.windup)
			w.last = sample
			ThrowController.cancelWindup(w)
			return sample
		end
	end
	local sample = ThrowController.windupSample(w.tau, w.windup)
	w.last = sample
	return sample
end

-- Ultimate caster pose for the release phase, t seconds after telegraphEndsAt: snap ultCharge -> throwRelease, then
-- throwRelease -> rushRecovery, held through the recovery, then the weight -> 0 over recoveryBlendMs.
function ThrowController.ultReleaseSample(t: number, recoverySeconds: number): (Sample, boolean)
	if t < ULT_SNAP_S then
		local u = ease(t / ULT_SNAP_S, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		return newSample("ultCharge", "throwRelease", u, 1, 0), false
	end
	local hunchEnd = ULT_SNAP_S + ULT_HUNCH_S
	if t < hunchEnd then
		local u = ease((t - ULT_SNAP_S) / ULT_HUNCH_S, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		return newSample("throwRelease", "rushRecovery", u, 1, 0), false
	end
	local holdEnd = math.max(recoverySeconds, hunchEnd)
	if t < holdEnd then
		return newSample("rushRecovery", "rushRecovery", 0, 1, 0), false
	end
	local k = math.clamp((t - holdEnd) / ULT_RECOVERY_BLEND_S, 0, 1)
	return newSample("rushRecovery", "rushRecovery", 0, 1 - k, 0), k >= 1
end

-- Joint angles in degrees for the blend from pose `from` to pose `to` by u (a joint missing in one pose counts as 0).
function ThrowController.blendDegrees(from: string, to: string, u: number, rig: string): { [string]: Vector3 }
	local a = if rig == "R6" then POSES[from].R6 else POSES[from].R15
	local b = if rig == "R6" then POSES[to].R6 else POSES[to].R15
	local out: { [string]: Vector3 } = {}
	for joint, va in a do
		out[joint] = va:Lerp(b[joint] or Vector3.zero, u)
	end
	for joint, vb in b do
		local present: Vector3? = out[joint]
		if present == nil then
			out[joint] = vb * u
		end
	end
	return out
end

-- 2026-10-15: the full-body clip's joint degrees for a throw sample (R15 with a styled windup), else nil (the
-- ultimate, R6, or a windup with no style: blendDegrees).
function ThrowController.motionDegrees(sample: Sample, rig: string, w: Windup?): { [string]: Vector3 }?
	if rig ~= "R15" or w == nil or w.style == nil or sample.t == nil then
		return nil
	end
	local legs = w.legs == true
	if sample.phase == "windup" then
		return ThrowMotion.windup(w.style :: string, sample.t :: number, legs)
	elseif sample.phase == "release" then
		return ThrowMotion.release(w.style :: string, sample.t :: number, legs)
	end
	return nil
end

-- Clamps a direction's pitch to [minDeg, maxDeg] (keeps its heading) and returns a unit vector. A vertical or zero
-- input keeps `fallbackForward`'s heading.
function ThrowController.clampPitch(dir: Vector3, minDeg: number, maxDeg: number, fallbackForward: Vector3?): Vector3
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local heading: Vector3
	if flat.Magnitude > 1e-6 then
		heading = flat.Unit
	else
		local f = fallbackForward or Vector3.new(0, 0, -1)
		local ff = Vector3.new(f.X, 0, f.Z)
		heading = if ff.Magnitude > 1e-6 then ff.Unit else Vector3.new(0, 0, -1)
	end
	local pitch = if dir.Magnitude > 1e-9 then math.deg(math.atan2(dir.Y, flat.Magnitude)) else 0
	local clamped = math.rad(math.clamp(pitch, minDeg, maxDeg))
	return heading * math.cos(clamped) + Vector3.yAxis * math.sin(clamped)
end

-- Turns a direction's heading into the cone of `coneDeg` around `forward` (horizontal), keeping its pitch. Unit result.
function ThrowController.clampToCone(dir: Vector3, forward: Vector3, coneDeg: number): Vector3
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local f = Vector3.new(forward.X, 0, forward.Z).Unit
	local unit = if dir.Magnitude > 1e-9 then dir.Unit else f
	if flat.Magnitude < 1e-6 then
		return unit
	end
	local heading = flat.Unit
	local angle = math.deg(math.acos(math.clamp(heading:Dot(f), -1, 1)))
	if angle <= coneDeg then
		return unit
	end
	-- Rotate f by ±coneDeg about world up toward the original side.
	local side = if f:Cross(heading).Y >= 0 then 1 else -1
	local rotated = CFrame.fromAxisAngle(Vector3.yAxis, side * math.rad(coneDeg)):VectorToWorldSpace(f)
	local pitch = math.atan2(unit.Y, Vector3.new(unit.X, 0, unit.Z).Magnitude)
	return rotated * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
end

-- A throw direction kept inside the pitch band and, in practice, the range cone (the server's checks, §5.5). Used for
-- a solved aim and, as it is, for a throw whose aim ray hit nothing (it leaves along the crosshair, see the header).
function ThrowController.limitDirection(raw: Vector3, forward: Vector3, practice: boolean): Vector3
	local dir = ThrowController.clampPitch(raw, COMBAT.Throw.pitchMinDeg, COMBAT.Throw.pitchMaxDeg, forward)
	if practice then
		dir = ThrowController.clampToCone(dir, RANGE_FORWARD, COMBAT.Throw.practiceConeDeg - CONE_MARGIN_DEG)
	end
	return dir
end

-- Aim assist (§5.10): when `target` is inside the cone of `coneDeg` around the aim ray, the aim point moves `strength`
-- of the way toward it. Returns the new aim point and whether it moved.
function ThrowController.applyAimAssist(
	rayOrigin: Vector3,
	rayDir: Vector3,
	aimPoint: Vector3,
	target: Vector3,
	coneDeg: number,
	strength: number
): (Vector3, boolean)
	local toTarget = target - rayOrigin
	if toTarget.Magnitude < 1e-6 or rayDir.Magnitude < 1e-9 or not (strength > 0) then
		return aimPoint, false
	end
	local angle = math.deg(math.acos(math.clamp(rayDir.Unit:Dot(toTarget.Unit), -1, 1)))
	if angle > coneDeg then
		return aimPoint, false
	end
	return aimPoint:Lerp(target, math.clamp(strength, 0, 1)), true
end

-- True when a camera ray's hit becomes the aim point: a hit no farther than missAt + margin (missAt = missReach). A
-- farther hit (user bug 2026-10-15: the NEXT arena slot 160-200 studs behind the opponent; the arc to it went "to the
-- sky") counts like open sky, so the throw leaves along the crosshair. No hit: false. missAt >= maxReach (nothing to
-- anchor on): every hit counts, as before. Pure.
function ThrowController.aimHits(hitDistance: number?, missAt: number, margin: number, maxReach: number): boolean
	if hitDistance == nil then
		return false
	end
	return missAt >= maxReach or hitDistance <= missAt + margin
end

-- Flat ultimate direction from `from` toward `to`; the fallback heading when they are (almost) above each other.
function ThrowController.flatAim(from: Vector3, to: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if flat.Magnitude > 1e-3 then
		return flat.Unit
	end
	local f = Vector3.new(fallback.X, 0, fallback.Z)
	return if f.Magnitude > 1e-6 then f.Unit else Vector3.new(0, 0, -1)
end

-- Distance along a ray (origin, direction) that hit nothing: the farthest anchor's horizontal distance measured along
-- the ray's flat direction, converted to a distance along the ray, at most `maxReach`. No anchor ahead, or a ray
-- within ~3° of vertical, gives `maxReach`. Pure.
function ThrowController.missReach(origin: Vector3, direction: Vector3, anchors: { Vector3 }, maxReach: number): number
	if direction.Magnitude < 1e-6 then
		return maxReach
	end
	local dir = direction.Unit
	local flatLen = Vector3.new(dir.X, 0, dir.Z).Magnitude
	if flatLen < 0.05 then
		return maxReach
	end
	local flatUnit = Vector3.new(dir.X, 0, dir.Z) / flatLen
	local farthest = 0
	for _, anchor in anchors do
		local ahead = flatUnit:Dot(Vector3.new(anchor.X - origin.X, 0, anchor.Z - origin.Z))
		if ahead > farthest then
			farthest = ahead
		end
	end
	if farthest <= 0 then
		return maxReach
	end
	return math.min(maxReach, farthest / flatLen)
end

-- Cooldown ring progress at `now`: 0 at the last release, 1 at readyAt (1 when there is no cooldown to show).
function ThrowController.cooldownProgress(now: number, releasedAt: number, ready: number): number
	if now >= ready or ready <= releasedAt then
		return 1
	end
	return math.clamp((now - releasedAt) / (ready - releasedAt), 0, 1)
end

-- Input buffer (§5.2 InputBufferSeconds): a press at `pressedAt` still counts while the moment the throw becomes
-- possible (`readyAt`) is at most `bufferSeconds` after it. A readyAt already in the past keeps it.
function ThrowController.bufferKeeps(pressedAt: number, readyAt: number, bufferSeconds: number): boolean
	return readyAt - pressedAt <= bufferSeconds + 1e-9
end

-- Feature 1 (hold to charge, pure): what one frame does with the Throw button while no charge runs. `held` = the
-- button is down (hold to charge on), `charging` = a charge runs, `ready` = a throw may start now (canCharge),
-- `buffered` = a press is waiting, `keeps` = that press is within the input buffer of the moment the throw becomes
-- possible. "start" = start charging (a held press once the throw is ready), "throw" = throw now, uncharged (a press
-- let go before it was ready, inside the buffer), "drop" = forget the press (let go too early), nil = wait.
function ThrowController.holdStep(
	held: boolean,
	charging: boolean,
	ready: boolean,
	buffered: boolean,
	keeps: boolean
): ("start" | "throw" | "drop")?
	if charging then
		return nil -- the release throws it (onThrowInput)
	end
	if held then
		return if ready then "start" else nil
	end
	if not buffered then
		return nil
	end
	if not keeps then
		return "drop"
	end
	return if ready then "throw" else nil
end

-- The sound of a held squishy popping back in (§18.6): sfx.pop for the local player's own throw only.
function ThrowController.popInSound(isLocal: boolean): string?
	return if isLocal then SOUND_POP else nil
end

-- The sound of a ThrowRejected (§18.4.5): ui.error when it answers the own pending request (seq matches), else nil.
function ThrowController.rejectSound(seq: number, pendingSeq: number?): string?
	return if pendingSeq ~= nil and seq == pendingSeq then SOUND_REJECTED else nil
end

-- A ThrowRejected nextThrowAt the client adopts: finite and at most `aheadSeconds` after `now`; else nil (ignored).
function ThrowController.acceptedNextThrowAt(value: unknown, now: number, aheadSeconds: number): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	if value > now + aheadSeconds then
		return nil
	end
	return value
end

-- Touch / gamepad shoulder offset (§5.10): camRight × studs in the HumanoidRootPart's object space (the space of
-- Humanoid.CameraOffset).
function ThrowController.shoulderOffset(rootFrame: CFrame, cameraRight: Vector3, studs: number): Vector3
	local right = Vector3.new(cameraRight.X, 0, cameraRight.Z)
	if right.Magnitude < 1e-6 then
		return Vector3.zero
	end
	return rootFrame:VectorToObjectSpace(right.Unit * studs)
end

-- Whether the shoulder offset applies (§5.10): in the Duel or Practice context on touch or gamepad, and not while
-- first person suppresses it (first-person spec 2026-10-10 §3.1: it would put the eye outside the head).
function ThrowController.shoulderApplies(inContext: boolean, input: Enum.PreferredInput, suppressed: boolean): boolean
	return inContext and input ~= Enum.PreferredInput.KeyboardAndMouse and not suppressed
end

-- Pure on a humanoid passed in (unit-tested): one frame of the shoulder offset. `offset` nil (or a different humanoid)
-- puts the saved CameraOffset back; otherwise the CameraOffset is saved once per humanoid and `offset` written.
-- Returns the record to keep (nil when nothing is applied).
function ThrowController.shoulderStep(current: Shoulder?, humanoid: Humanoid?, offset: Vector3?): Shoulder?
	if current and (offset == nil or current.humanoid ~= humanoid) then
		if current.humanoid.Parent ~= nil then
			current.humanoid.CameraOffset = current.saved
		end
		current = nil
	end
	if offset == nil or humanoid == nil then
		return nil
	end
	local record = current or { humanoid = humanoid, saved = humanoid.CameraOffset }
	humanoid.CameraOffset = offset
	return record
end

-- Capsule centre of a character whose HumanoidRootPart is at `rootPosition` (§5.5).
function ThrowController.capsuleCentre(rootPosition: Vector3): Vector3
	return rootPosition + Vector3.new(0, CAPSULE_CENTRE_Y, 0)
end

-- Capsule centre of a practice target standing on `base` (its floor point): the same capsule as a player.
function ThrowController.targetCentre(base: Vector3): Vector3
	return base + Vector3.new(0, HRP_ABOVE_FLOOR + CAPSULE_CENTRE_Y, 0)
end

-- Payload readers (server data, still type-checked before use) --------------------------------------------------

local function isVector(v: unknown): boolean
	return typeof(v) == "Vector3"
end

local function isNumber(v: unknown): boolean
	return type(v) == "number" and v == v
end

function ThrowController.parseThrowStarted(raw: unknown): ThrowStarted?
	if type(raw) ~= "table" then
		return nil
	end
	local t = raw :: any
	if
		not isNumber(t.projId)
		or not isNumber(t.throwerId)
		or type(t.squishyId) ~= "string"
		or not isVector(t.origin)
		or not isVector(t.velocity)
		or not isNumber(t.gravity)
		or not isNumber(t.radius)
		or not isNumber(t.releaseAt)
	then
		return nil
	end
	return t :: ThrowStarted
end

function ThrowController.parseImpact(raw: unknown): ThrowImpact?
	if type(raw) ~= "table" then
		return nil
	end
	local t = raw :: any
	if not isNumber(t.projId) or type(t.kind) ~= "string" or not isVector(t.position) then
		return nil
	end
	if t.normal ~= nil and not isVector(t.normal) then
		return nil
	end
	if t.knockbackDir ~= nil and not isVector(t.knockbackDir) then
		return nil
	end
	return t :: ThrowImpact
end

-- Spec phase 5: a list field of an ultimate event (shots, drops) holds at most this many entries.
local MAX_EVENT_ITEMS = 16

-- True when `list` is nil, or an array of at most MAX_EVENT_ITEMS tables that each pass `check`.
local function listOf(list: unknown, check: (any) -> boolean): boolean
	if list == nil then
		return true
	end
	if type(list) ~= "table" or #(list :: any) > MAX_EVENT_ITEMS then
		return false
	end
	for _, item in list :: any do
		if type(item) ~= "table" or not check(item) then
			return false
		end
	end
	return true
end

local function validShot(s: any): boolean
	return isNumber(s.projId)
		and isVector(s.origin)
		and isVector(s.dir)
		and isNumber(s.length)
		and isNumber(s.releaseAt)
end

local function validDrop(d: any): boolean
	return isNumber(d.projId) and isVector(d.position) and isNumber(d.shadowAt) and isNumber(d.landAt)
end

function ThrowController.parseUltimateEvent(raw: unknown): UltimateEvent?
	if type(raw) ~= "table" then
		return nil
	end
	local t = raw :: any
	if
		type(t.phase) ~= "string"
		or not isNumber(t.casterId)
		or not isVector(t.origin)
		or not isVector(t.dir)
		or not isNumber(t.length)
		or not isNumber(t.radius)
		or not isNumber(t.telegraphEndsAt)
	then
		return nil
	end
	-- Spec phase 5: the optional fields of the Epic ultimates.
	if
		(t.ultimateId ~= nil and type(t.ultimateId) ~= "string")
		or (t.center ~= nil and not isVector(t.center))
		or not listOf(t.shots, validShot)
		or not listOf(t.drops, validDrop)
	then
		return nil
	end
	return t :: UltimateEvent
end

-- Spec phase 5: an ultimate event's ability, (id, Config.Abilities entry): its ultimateId, or Dragon Rush for an event
-- with none (sent before the Epic ultimates existed); nil, nil for an id this client does not know.
function ThrowController.eventAbility(event: UltimateEvent): (string?, any)
	local id = event.ultimateId or "dragon_rush"
	local ability = (Config.Abilities :: any)[id]
	if ability == nil then
		return nil, nil
	end
	return id, ability
end

-- Runtime helpers ---------------------------------------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function localPlayer(): Player
	return Players.LocalPlayer
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function aliveRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return rootOf(player)
end

local function track(connection: Signal.Connection)
	table.insert(connections, connection)
	local c = cleanup
	if c then
		c:add(connection)
	end
end

local function equippedDef(): Types.SquishyDef?
	local id = localPlayer():GetAttribute(ATTR_EQUIPPED)
	return Catalog.get(id) or Catalog.get(Catalog.starterId())
end

local function rulesNumber(key: string, default: number): number
	local m = match
	local rules = m and m.rules
	local value = if type(rules) == "table" then rules[key] else nil
	return if type(value) == "number" then value else default
end

-- The throw context now: duel (Active / SuddenDeath, or the Countdown's last instant) or practice. nil + reason code.
local function throwContext(now: number): (Ctx?, string?)
	if ControlsController.isContextActive("Duel") then
		local m = match
		if m == nil then
			-- FFA/TDM v1: a 12-player match has its own view (see the header); knocked out, nothing is thrown.
			local mv = StateController.match()
			if mv == nil or not mv.you.alive then
				return nil, "throw.context"
			end
			local matchLive = PHASE_THROW[mv.phase] == true or (mv.phase == "Countdown" and now >= mv.phaseEndsAt)
			local matchDef = if matchLive
				then Catalog.get(mv.you.squishyId) or Catalog.get(Catalog.starterId())
				else nil
			if matchDef == nil then
				return nil, "throw.context"
			end
			-- Power-ups v1.1 (see the header): rapid throw and throw boost while they live, else 1. Review fix: the
			-- throw boost as the server reads it, when a request sent now arrives. Integration (2026-10-16): the rapid
			-- throw too, as the server's number (rapidCooldownMultiplier), read at that same moment.
			local okPing, ping = pcall(function(): any
				return localPlayer():GetNetworkPing()
			end)
			local arrival = now
				+ (if okPing and isNumber(ping) and ping > 0 then ping / 2 else 0)
				+ COMBAT.Lag.halfPingExtraSeconds
			local matchCtx: Ctx = {
				kind = "match",
				def = matchDef,
				cooldownMultiplier = ThrowController.rapidCooldownMultiplier(
					StateController.buffMultiplier(mv, "rapidThrow", "cooldownMultiplier", arrival),
					matchDef.throw.cooldown,
					RULES.CooldownClamp
				),
				speedMultiplier = StateController.buffMultiplier(mv, "throwBoost", "speedMultiplier", arrival),
			}
			return matchCtx, nil
		end
		local live = PHASE_THROW[m.phase] == true or (m.phase == "Countdown" and now >= m.phaseEndsAt)
		if not live then
			return nil, "throw.context"
		end
		local def = Catalog.get(m.you.squishyId) or Catalog.get(Catalog.starterId())
		if def == nil then
			return nil, "throw.context"
		end
		local multiplier = if m.phase == "SuddenDeath"
			then rulesNumber("SuddenDeathCooldownMultiplier", RULES.SuddenDeathCooldownMultiplier)
			else 1
		return { kind = "duel", def = def, cooldownMultiplier = multiplier }, nil
	elseif ControlsController.isContextActive("Practice") then
		local def = equippedDef()
		if def == nil then
			return nil, "throw.context"
		end
		return { kind = "practice", def = def, cooldownMultiplier = 1 }, nil
	end
	return nil, "throw.context"
end

-- Own half + tolerance (§5.6 #5), from the DuelState arena zones. True when unknown (the server decides).
local function insideOwnHalf(position: Vector3): boolean
	local m = match
	if m == nil then
		return true
	end
	local zones = m.arena and m.arena.zones
	local zone = zones and zones["Half" .. tostring(m.you.side)]
	if zone == nil or typeof(zone.cframe) ~= "CFrame" or typeof(zone.size) ~= "Vector3" then
		return true
	end
	local p = zone.cframe:PointToObjectSpace(position)
	local half = zone.size / 2 + Vector3.one * COMBAT.Throw.zoneToleranceStuds
	return math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z
end

-- The duel opponent's body: its character, or a duel bot's rig (a bot is no Player; user bug 2026-10-30: aim assist
-- pulled toward the bot's pad, wherever the bot was).
local function opponentBody(): Model?
	local m = match
	if m == nil then
		return nil
	end
	local opponent = Players:GetPlayerByUserId(m.opponent.userId)
	if opponent then
		return opponent.Character
	end
	local bots = Workspace:FindFirstChild(BOTS_FOLDER)
	local rig = if bots then bots:FindFirstChild(m.opponent.displayName) else nil
	return if rig and rig:IsA("Model") then rig else nil
end

local function opponentCentre(): Vector3?
	local body = opponentBody()
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return ThrowController.capsuleCentre(root.Position)
	end
	-- No body to find (e.g. the Studio test dummy): the opponent's pad.
	local m = match
	local pads = m and m.arena and m.arena.pads
	local otherSide = if m and m.you.side == "A" then "B" else "A"
	local pad = pads and pads["Pad" .. otherSide]
	if typeof(pad) == "CFrame" then
		return ThrowController.targetCentre((pad :: CFrame).Position)
	end
	return nil
end

-- FFA/TDM v1: every enemy of the match (StateController.enemyIds) standing in the view and alive here, as its capsule
-- centre and character (aim assist, the missing ray's reach). Empty outside a match.
function ThrowController.enemyTargets(): { { centre: Vector3, model: Instance? } }
	local list: { { centre: Vector3, model: Instance? } } = {}
	local view = StateController.match()
	if view == nil then
		return list
	end
	for _, userId in StateController.enemyIds(view) do
		local participant = StateController.matchParticipant(view, userId)
		local enemy = if participant and participant.alive then Players:GetPlayerByUserId(userId) else nil
		local root = if enemy then aliveRoot(enemy) else nil
		if enemy and root then
			table.insert(list, { centre = ThrowController.capsuleCentre(root.Position), model = enemy.Character })
		end
	end
	return list
end

-- Practice target floor points (tagged models, streamed in), with their models.
local function practiceTargets(): { { model: Model, base: Vector3 } }
	local list = {}
	for _, instance in CollectionService:GetTagged(RANGE.targetTag) do
		if instance:IsA("Model") then
			table.insert(list, { model = instance, base = instance:GetPivot().Position })
		end
	end
	return list
end

local function refreshAimParams(): RaycastParams
	local params = aimParams
	local character = localPlayer().Character
	if params == nil or aimCharacter ~= character then
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.CollisionGroup = "Default"
		p.IgnoreWater = true
		local exclude: { Instance } = {}
		if character then
			table.insert(exclude, character)
		end
		local fx = Workspace:FindFirstChild(CLIENT_FX)
		if fx then
			table.insert(exclude, fx)
		end
		p.FilterDescendantsInstances = exclude
		aimParams = p
		aimCharacter = character
		params = p
	end
	return params :: RaycastParams
end

-- Where a missing aim ray ends (see the header): the anchors' farthest horizontal distance along the ray's flat
-- direction, turned into a distance along the ray; `maxReach` when there is no anchor ahead or the ray is (nearly)
-- vertical.
local function missReachFor(ray: Ray): number
	local anchors: { Vector3 } = {}
	if match ~= nil then
		local centre = opponentCentre()
		if centre then
			table.insert(anchors, centre)
		end
	elseif StateController.match() ~= nil then
		for _, target in ThrowController.enemyTargets() do -- FFA/TDM v1: the enemies, never the practice targets
			table.insert(anchors, target.centre)
		end
	else
		for _, target in practiceTargets() do
			table.insert(anchors, target.base)
		end
	end
	return ThrowController.missReach(ray.Origin, ray.Direction, anchors, COMBAT.Aim.maxRayStuds)
end

-- The aim ray and point from the camera (mouse or centre); the last value is false when the ray hit nothing.
local function cameraAim(): (Vector3?, Vector2, boolean, Ray?, boolean)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil, Vector2.zero, true, nil, false
	end
	local viewport = camera.ViewportSize
	local centered = ControlsController.preferredInput() ~= Enum.PreferredInput.KeyboardAndMouse
		or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	local screen = if centered then viewport / 2 else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local reach = COMBAT.Aim.maxRayStuds
	local result = Workspace:Raycast(ray.Origin, ray.Direction * reach, refreshAimParams())
	local missAt = missReachFor(ray)
	local hit =
		ThrowController.aimHits(if result then result.Distance else nil, missAt, COMBAT.Aim.farHitMarginStuds, reach)
	local point = if hit and result then result.Position else ray.Origin + ray.Direction.Unit * missAt
	return point, screen, centered, ray, hit
end

local function hasLineOfSight(from: Vector3, to: Vector3, targetModel: Instance?): boolean
	local offset = to - from
	local result = Workspace:Raycast(from, offset, refreshAimParams())
	if result == nil then
		return true
	end
	return targetModel ~= nil and result.Instance:IsDescendantOf(targetModel)
end

-- Aim assist at throw time for gamepad and touch (§5.10). Aim arc (2026-10-16): `count` false (the arc's preview) leaves
-- stats.assisted to real throws.
local function assisted(ctx: Ctx, ray: Ray?, aimPoint: Vector3, count: boolean?): Vector3
	if ray == nil then
		return aimPoint
	end
	local input = ControlsController.preferredInput()
	local spec = COMBAT.AimAssist[input.Name]
	if spec == nil or not spec.enabled then
		return aimPoint
	end
	local candidates: { { centre: Vector3, model: Instance? } } = {}
	if ctx.kind == "duel" then
		local centre = opponentCentre()
		if centre then
			table.insert(candidates, { centre = centre, model = opponentBody() })
		end
	elseif ctx.kind == "match" then
		candidates = ThrowController.enemyTargets() -- FFA/TDM v1: every live enemy
	else
		for _, target in practiceTargets() do
			local model: Instance? = target.model
			table.insert(candidates, { centre = ThrowController.targetCentre(target.base), model = model })
		end
	end
	local best: Vector3? = nil
	local bestAngle = math.huge
	for _, candidate in candidates do
		local to = candidate.centre - ray.Origin
		if to.Magnitude > 1e-6 then
			local angle = math.deg(math.acos(math.clamp(ray.Direction.Unit:Dot(to.Unit), -1, 1)))
			if
				angle <= spec.coneDeg
				and angle < bestAngle
				and hasLineOfSight(ray.Origin, candidate.centre, candidate.model)
			then
				best, bestAngle = candidate.centre, angle
			end
		end
	end
	if best == nil then
		return aimPoint
	end
	local point, moved = ThrowController.applyAimAssist(
		ray.Origin,
		ray.Direction,
		aimPoint,
		best :: Vector3,
		spec.coneDeg,
		spec.strength
	)
	if moved and count ~= false then
		stats.assisted += 1
	end
	return point
end

local function originHintOf(root: BasePart): Vector3
	return (root.CFrame * CFrame.new(COMBAT.ReleaseOffset)).Position
end

-- Aim arc (2026-10-16, pure): a throw's launch speed (studs/s), the one ThrowRules gives it: the toy's speed ×
-- ThrowCharge.speedFactor(c) × the throw boost (nil = 1). Its velocity = the unit direction × this.
function ThrowController.launchSpeed(throw: { speed: number }, c: number, speedMultiplier: number?): number
	return throw.speed * ThrowCharge.speedFactor(c) * (speedMultiplier or 1)
end

-- Feature 1: solved for the charged speed (ThrowCharge.speedFactor(c)), the speed the server gives this throw.
-- Power-ups v1.1: times the context's throw boost (a match only; 1 otherwise).
local function throwDirection(ctx: Ctx, origin: Vector3, aimPoint: Vector3, forward: Vector3, c: number): Vector3
	local throw = ctx.def.throw
	local speed = ThrowController.launchSpeed(throw, c, ctx.speedMultiplier)
	local raw = ProjectileMath.solveLaunchDir(origin, aimPoint, speed, throw.gravity)
	return ThrowController.limitDirection(raw, forward, ctx.kind == "practice")
end

-- Held squishy: anticipation squash on its rig, hide at release, pop-in at readyAt ---------------------------------

-- The windup holds the held squishy's rig at windupHold (no spring, so it follows the time-warped windup) with the
-- squish face while cocked; once the windup is over the rig lets go and springs back. The hold is set in the overlay's
-- prepare, before the rig steps, so it shows in the same frame. It starts from the rig's depth at the first prepare
-- (the throw press), so a throw pressed mid-squeeze never pops (first-person spec 2026-10-10 §3.5). While the local
-- player's first-person overlay mirrors the rig there is no hold (windupRigHold's `mirrored`, spec 2026-10-11 §3.5).
local function setSquashOverlay(player: Player, w: Windup)
	local cocked = false
	local yPress: number? = nil
	local function live(): boolean
		return windups[player] == w and not w.finished and w.releaseStart == nil
	end
	HeldSquishyController.setOverlay(player, OVERLAY_THROW, {
		prepare = function(_dt: number, _now: number)
			local rig = HeldSquishyController.getRig(player)
			if live() and rig then
				local mirrored = player == localPlayer() and HeldSquishyController.isMirrored()
				if yPress == nil and not mirrored then
					yPress = rig:squeezeY()
				end
				local sample = w.last
				cocked =
					ThrowController.windupRigHold(rig, if sample then sample.squash else 0, cocked, yPress, mirrored)
			end
		end,
		step = function(_dt: number, _now: number): (Vector3, number, boolean)
			return Vector3.one, 0, live()
		end,
		removed = function()
			local rig = HeldSquishyController.getRig(player)
			if rig then
				rig:clearHold()
				if cocked then
					rig:setFace("normal")
				end
			end
		end,
	})
end

local function hideHeld(player: Player, untilServer: number)
	HeldSquishyController.setHidden(player, HIDE_REASON, true)
	HeldSquishyController.setOverlay(player, OVERLAY_POP, nil)
	popIns[player] = nil
	hiddenUntil[player] = untilServer
end

local function playSound(key: string, options: SoundController.PlayOptions?)
	local ok, err = pcall(SoundController.play, key, options)
	if not ok then
		log:warn(`sound {key} failed:`, err)
	end
end

local function popIn(player: Player)
	hiddenUntil[player] = nil
	HeldSquishyController.setHidden(player, HIDE_REASON, false)
	local sound = ThrowController.popInSound(player == localPlayer())
	if sound then
		local held = HeldSquishyController.getModel(player)
		local at: BasePart? = if held then held.PrimaryPart else rootOf(player)
		playSound(sound, { at = at, priority = 1 })
	end
	local state: PopIn = {
		spring = Spring.new(HELD.popInFrom, HELD.popInOmega, HELD.popInZeta, 1),
		untilClock = os.clock() + POP_MAX_SECONDS,
	}
	popIns[player] = state
	HeldSquishyController.setOverlay(player, OVERLAY_POP, {
		step = function(dt: number, _now: number): (Vector3, number, boolean)
			local s = state.spring:step(dt)
			local keep = popIns[player] == state
				and os.clock() < state.untilClock
				and not state.spring:isSettled(POP_SETTLE)
			if not keep and popIns[player] == state then
				popIns[player] = nil
			end
			return Vector3.one * math.max(s, 0.05), 0, keep
		end,
	})
end

local function showHeldNow(player: Player)
	hiddenUntil[player] = nil
	popIns[player] = nil
	HeldSquishyController.setHidden(player, HIDE_REASON, false)
	HeldSquishyController.setOverlay(player, OVERLAY_POP, nil)
end

-- Joint layers ------------------------------------------------------------------------------------------------------

local function applyLayer(player: Player, id: string, sample: Sample?, w: Windup?)
	local layer = CharacterAnimController.getLayer(player)
	if layer == nil then
		return
	end
	if sample == nil or not (sample.weight > 0.001) then
		if layer:has(id) then
			layer:clear(id)
		end
		return
	end
	local rig = layer:getRig()
	if rig == nil or not layer:isReady() then
		return
	end
	local degrees = ThrowController.motionDegrees(sample, rig, w)
		or ThrowController.blendDegrees(sample.from, sample.to, sample.u, rig)
	local anyLayer: any = layer
	anyLayer:setAngles(id, "override", degrees, sample.weight, THROW_PRIORITY)
end

local function fadeLayers(player: Player)
	local layer = CharacterAnimController.getLayer(player)
	if layer == nil then
		return
	end
	for _, id in { LAYER_THROW, LAYER_ULT } do
		if layer:has(id) then
			layer:blendWeight(id, 0, DUEL_END_BLEND_S, true)
		end
	end
end

-- 2026-10-15: the throwing hand's smear from the release (Anim/ThrowVfx "HandSwoosh"), in the toy's accent; none on a
-- hidden hand (the local first person hides the body) or a rig without a right hand.
local function releaseSwoosh(player: Player, w: Windup)
	local character = player.Character
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if hand == nil or not hand:IsA("BasePart") or hand.LocalTransparencyModifier > 0.5 then
		return
	end
	local def = if w.squishyId then Catalog.get(w.squishyId) else nil
	local accent = if def then Color3.fromHex(def.visuals.accent) else nil
	local ok, err = pcall(ThrowVfx.swoosh, hand, { accent = accent, seconds = SWOOSH_SECONDS })
	if not ok then
		log:warn("hand swoosh failed:", err)
	end
end

-- Throwing ----------------------------------------------------------------------------------------------------------

local function ownWindupBusy(): boolean
	local w = windups[localPlayer()]
	return w ~= nil and not w.finished and not w.cancelled and w.releaseStart == nil
end

local function isRooted(now: number): boolean
	if now < rootedUntil then
		return true
	end
	local ult = ults[localPlayer()]
	return ult ~= nil and (ult.phase == "cast" or ult.phase == "telegraph")
end

-- Feature 1: the hands are busy with a catch (an open window or a crush; CatchController.setHandsBusy).
local function handsBusy(now: number): boolean
	return now < handsBusyUntil
end

-- Aim arc (2026-10-16): where a throw of `ctx` from `root` leaves, exactly as fire() sends it: the origin hint and the
-- unit direction, or nil, nil and a reason code when it cannot be thrown. `aimPoint` nil = the camera aim now (with aim
-- assist); `level` = the charge the server will measure (0 uncharged); `countAssist` false = the arc's preview (the
-- assist counter is for real throws). Moved out of fire() unchanged.
function ThrowController.launchFor(
	ctx: Ctx,
	root: BasePart,
	aimPoint: Vector3?,
	ray: Ray?,
	level: number,
	countAssist: boolean
): (Vector3?, Vector3?, string?)
	if ctx.kind == "duel" and not insideOwnHalf(root.Position) then
		return nil, nil, "throw.context"
	end
	local point = aimPoint
	local aimRay = ray
	local missed = false -- the camera ray hit nothing (open sky): the throw leaves along the crosshair (see the header)
	if point == nil then
		local camPoint, _, _, camRay, hit = cameraAim()
		point, aimRay, missed = camPoint, camRay, not hit
	end
	if point == nil then
		return nil, nil, "throw.direction"
	end
	if aimPoint == nil then
		local unassisted = point :: Vector3
		point = assisted(ctx, aimRay, unassisted, countAssist)
		if point ~= unassisted then
			missed = false -- aim assist found a target: aim at it
		end
	end
	local origin = originHintOf(root)
	local dir = if missed and aimRay
		then ThrowController.limitDirection(aimRay.Direction, root.CFrame.LookVector, ctx.kind == "practice")
		else throwDirection(ctx, origin, point :: Vector3, root.CFrame.LookVector, level)
	return origin, dir, nil
end

-- Sends one throw toward `aimPoint` (nil = the current camera aim). Returns false and a reason code when it cannot.
-- Feature 1: `c` = the local charge (0 = uncharged); `chargeSent` = its ChargeStart already left. An uncharged throw
-- first sends ChargeStart at the same clientTime, so the server's charge record is always this throw's (c = 0).
local function fire(ctx: Ctx, aimPoint: Vector3?, ray: Ray?, c: number?, chargeSent: boolean?): (boolean, string?)
	local player = localPlayer()
	local root = aliveRoot(player)
	if root == nil then
		return false, "throw.context"
	end
	local level = if chargeSent then c or 0 else 0
	local origin, dir, reason = ThrowController.launchFor(ctx, root, aimPoint, ray, level, true)
	if origin == nil or dir == nil then
		return false, reason
	end
	local now = serverNow()
	local windup = ctx.def.throw.windup
	if not chargeSent then
		NetController.chargeStart(now) -- feature 1: a fresh record (c = 0) for an uncharged throw
	end
	local seq = NetController.throwRequest(dir, origin, now)
	if seq == nil then
		return false, "net.rateLimited" -- dropped locally (bucket or shape check): nothing was sent
	end
	lastSeq = seq
	stats.throwsSent += 1
	pending = { seq = seq, sentAt = now, windup = windup }
	bufferedAt = nil
	local w = ThrowController.newWindup(windup, now + windup + COCKED_S, false)
	ThrowController.setStyle(w, ctx.def.id, root)
	windups[player] = w
	setSquashOverlay(player, w)
	return true, nil
end

local function readyFor(ctx: Ctx): number
	return nextThrowAt - ctx.def.throw.windup
end

-- Power-ups v1.1 review fix (pure): a throw of context `kind` waits while `live` own throws fly and the server's
-- MaxActiveProjectilesPerPlayer (`max`) would refuse one more; a match only (duels and practice keep the server's
-- throw.tooMany answer, as before).
function ThrowController.projectileCapped(kind: string, live: number, max: number): boolean
	return kind == "match" and live >= max
end

-- Power-ups v1.1 review fix: projectileCapped with the own throws in the air now (see the header).
function ThrowController.atThrowCap(kind: string): boolean
	if kind ~= "match" then
		return false
	end
	local live = 0
	for _, own in ownProjectiles do
		if own.throw then
			live += 1
		end
	end
	return ThrowController.projectileCapped(kind, live, RULES.MaxActiveProjectilesPerPlayer)
end

-- Power-ups v1.1 integration (2026-10-16, pure): the throw cooldown multiplier the server hands ThrowRules for a live
-- rapid throw (MatchService's throwCooldownMultiplier, the same steps): `multiplier` (StateController.buffMultiplier of
-- kinds.rapidThrow.cooldownMultiplier; 1 or more is kept as it is), at or above clamp.Min / the clamped catalog
-- `cooldown` (nil: clamp.Min), so ThrowRules' clamp(cooldown) × it is the shortest cooldown, clamp.Min.
function ThrowController.rapidCooldownMultiplier(
	multiplier: number,
	cooldown: number?,
	clamp: { Min: number, Max: number }
): number
	if multiplier >= 1 then
		return multiplier
	end
	local seconds = if type(cooldown) == "number" then cooldown else clamp.Min
	return math.max(multiplier, clamp.Min / math.clamp(seconds, clamp.Min, clamp.Max))
end

-- Feature 1: a throw may start charging (or fire) now: nothing in flight, no windup, no root, the cooldown over and
-- the hands free. Power-ups v1.1 review fix: and, in a match, fewer own throws flying than the server allows.
local function canCharge(ctx: Ctx, now: number): boolean
	return pending == nil
		and not ownWindupBusy()
		and not isRooted(now)
		and not handsBusy(now)
		and now >= readyFor(ctx)
		and not ThrowController.atThrowCap(ctx.kind)
end

-- Feature 1: the walk speed while charging (Charge.walkFactor, design: html:437), written on the own Humanoid; put back
-- at the end unless something else (the server's freeze or root) changed it meanwhile.
local function chargeWalk(on: boolean)
	local current = walkHold
	if on then
		if current ~= nil then
			return
		end
		local character = localPlayer().Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or not (humanoid.WalkSpeed > 0) then
			return
		end
		local saved = humanoid.WalkSpeed
		humanoid.WalkSpeed = ThrowCharge.walkSpeed(saved)
		walkHold = { humanoid = humanoid, saved = saved, written = humanoid.WalkSpeed }
	elseif current ~= nil then
		walkHold = nil
		local humanoid = current.humanoid
		if humanoid.Parent ~= nil and math.abs(humanoid.WalkSpeed - current.written) < 1e-3 then
			humanoid.WalkSpeed = current.saved
		end
	end
end

-- Feature 1: the charge tone while charging (ThrowCharge.tone: pitch and volume by c; nil stops it).
local function setChargeTone(c: number?, elapsed: number)
	if c == nil then
		local tone = chargeTone
		chargeTone = nil
		if tone then
			tone:stop(CHARGE_TONE_STOP_MS)
		end
		return
	end
	if chargeTone == nil then
		local ok, loop = pcall(SoundController.playLoop, SOUND_CHARGE_LOOP, { volume = 0, priority = 1 })
		chargeTone = if ok then loop else nil
	end
	local tone = chargeTone
	if tone then
		local pitch, volume = ThrowCharge.tone(c, elapsed)
		tone:setPitch(pitch)
		tone:setVolume(volume)
	end
end

-- Feature 1: drops the running charge without a throw (a catch press, an ultimate, a lost context).
local function dropCharge()
	charge = nil
	chargeWalk(false)
	setChargeTone(nil, 0)
end

-- Feature 1: starts charging now (the throw is ready): ChargeStart(now) to the server, the walk speed, the tone.
local function startCharge(ctx: Ctx, now: number)
	local sent = NetController.chargeStart(now)
	charge = { startAt = now, sent = sent, full = false, color = Color3.fromHex(ctx.def.visuals.accent) }
	bufferedAt = nil
	chargeWalk(true)
	setChargeTone(0, 0)
end

-- Feature 1: lets go of a charge: the throw with its c (0 when its ChargeStart never left).
local function releaseCharge(ctx: Ctx, now: number)
	local running = charge
	if running == nil then
		return
	end
	local c = ThrowCharge.level(running.startAt, now)
	dropCharge()
	fire(ctx, nil, nil, c, running.sent)
end

-- A press, a held button or a buffered press: throws when allowed and ready (Rules.HoldToCharge false: a press throws
-- at once, uncharged).
local function tryThrow(fromPress: boolean): boolean
	local now = serverNow()
	local ctx = throwContext(now)
	if ctx == nil then
		return false
	end
	if pending ~= nil or ownWindupBusy() or isRooted(now) or handsBusy(now) then
		if fromPress then
			bufferedAt = now -- kept by step() only if the throw becomes possible within the buffer
		end
		return true
	end
	if ThrowController.atThrowCap(ctx.kind) then
		return true -- power-ups v1.1 review fix: refused here (nothing sent, no windup, not buffered)
	end
	local ready = readyFor(ctx)
	if now >= ready then
		fire(ctx, nil, nil)
		return true
	end
	if
		fromPress
		and ThrowController.bufferKeeps(now, ready, rulesNumber("InputBufferSeconds", RULES.InputBufferSeconds))
	then
		bufferedAt = now
	end
	return true
end

-- Feature 1 (hold to charge): a press starts the charge when the throw is ready (else step() starts it once ready while
-- it is held, or the buffer throws it uncharged when it was let go in time); the release throws the charge.
local function onThrowInput(inputState: Enum.UserInputState, _input: InputObject?): boolean?
	local holdToCharge = RULES.HoldToCharge == true
	if inputState == Enum.UserInputState.Begin then
		holdDown = true
		if not holdToCharge then
			return tryThrow(true)
		end
		local now = serverNow()
		local ctx = throwContext(now)
		if ctx == nil then
			return false
		end
		if charge == nil and canCharge(ctx, now) then
			startCharge(ctx, now)
		elseif charge == nil then
			bufferedAt = now -- step(): charge once ready while held; else the buffer rule
		end
		return true
	elseif inputState == Enum.UserInputState.End then
		holdDown = false
		if holdToCharge and charge ~= nil then
			local now = serverNow()
			local ctx = throwContext(now)
			if ctx then
				releaseCharge(ctx, now)
			else
				dropCharge()
			end
		end
		return false
	elseif inputState == Enum.UserInputState.Cancel then
		holdDown = false
		bufferedAt = nil
		dropCharge()
	end
	return false
end

-- Ultimate ----------------------------------------------------------------------------------------------------------

local function abilityOf(def: Types.SquishyDef): any
	local id = def.ultimateId
	return if id then (Config.Abilities :: any)[id] else nil
end

local function tryUltimate(aimPoint: Vector3?): (boolean, string?)
	local now = serverNow()
	local ctx = throwContext(now)
	if ctx == nil then
		return false, "throw.context"
	end
	local ability = abilityOf(ctx.def)
	if ability == nil then
		return false, "ult.notReady"
	end
	local player = localPlayer()
	if ctx.kind == "duel" or ctx.kind == "match" then -- FFA/TDM v1: the charge, never the practice cooldown
		if StateController.charge(player.UserId) < ability.chargeMax then
			return false, "ult.notReady"
		end
	elseif now < practiceUltReadyAt then
		return false, "ult.notReady"
	end
	if isRooted(now) or ownWindupBusy() or pending ~= nil or handsBusy(now) then
		return false, "ult.notReady"
	end
	local root = aliveRoot(player)
	if root == nil then
		return false, "throw.context"
	end
	-- Feature 1 (build choice 2026-10-11, NOT IN DESIGN: the design has no ultimate): an ultimate drops a running
	-- charge (no throw).
	dropCharge()
	local point = aimPoint
	if point == nil then
		point = cameraAim()
	end
	local target = point or (root.Position + root.CFrame.LookVector * 10)
	local dir = ThrowController.flatAim(root.Position, target, root.CFrame.LookVector)
	if ctx.kind == "practice" then
		local coned = ThrowController.clampToCone(dir, RANGE_FORWARD, COMBAT.Throw.practiceConeDeg - CONE_MARGIN_DEG)
		dir = Vector3.new(coned.X, 0, coned.Z).Unit
	end
	if NetController.ultimateRequest(dir, now) == nil then
		return false, "net.rateLimited"
	end
	stats.ultsSent += 1
	ults[player] = {
		phase = "cast",
		ultimateId = ctx.def.ultimateId or "dragon_rush",
		recoverySeconds = ability.recoverySeconds,
		startedClock = os.clock(),
		telegraphEndsAt = nil,
		releaseStart = nil,
		cancelFrom = 0,
		weight = 0,
		finished = false,
	}
	return true, nil
end

local function onUltInput(inputState: Enum.UserInputState, _input: InputObject?): boolean?
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	local ok = tryUltimate(nil)
	return ok
end

local function stepUlt(ult: UltAnim, dt: number, now: number, recoverySeconds: number): Sample?
	if ult.finished then
		return nil
	end
	if ult.phase == "cast" then
		local elapsed = os.clock() - ult.startedClock
		if elapsed > ULT_CAST_MAX_S then
			ult.phase = "cancel"
			ult.startedClock = os.clock()
			ult.cancelFrom = ult.weight
		else
			ult.weight = math.clamp(elapsed / ULT_CAST_BLEND_S, 0, 1)
			return newSample("ultCharge", "ultCharge", 0, ult.weight, 0)
		end
	end
	if ult.phase == "telegraph" then
		local ends = ult.telegraphEndsAt or now
		if now < ends then
			ult.weight = math.min(1, ult.weight + dt / ULT_CAST_BLEND_S)
			return newSample("ultCharge", "ultCharge", 0, ult.weight, 0)
		end
		ult.phase = "release"
		ult.releaseStart = ends
	end
	if ult.phase == "release" then
		local sample, done = ThrowController.ultReleaseSample(now - (ult.releaseStart or now), recoverySeconds)
		ult.finished = done
		return sample
	end
	-- cancel
	local k = 1 - math.clamp((os.clock() - ult.startedClock) / CANCEL_S, 0, 1)
	if k <= 0 then
		ult.finished = true
	end
	return newSample("ultCharge", "ultCharge", 0, ult.cancelFrom * k, 0)
end

-- Remote events -----------------------------------------------------------------------------------------------------

local function forgetOwnProjectiles(now: number)
	for projId, own in ownProjectiles do
		if now > own.untilAt then
			ownProjectiles[projId] = nil
		end
	end
end

local function onThrowStarted(raw: unknown)
	local payload = ThrowController.parseThrowStarted(raw)
	if payload == nil then
		return
	end
	local thrower = Players:GetPlayerByUserId(payload.throwerId)
	local def = Catalog.get(payload.squishyId)
	local windup = if def then def.throw.windup else Config.Combat.PowerBudget.baseline.windup
	local nextAt = if isNumber(payload.nextThrowAt) then payload.nextThrowAt else payload.releaseAt
	-- The held squishy is hidden from the release until the cooldown ends (readyAt), then pops back in.
	local popAt = math.max(nextAt - windup, payload.releaseAt)
	if thrower == nil then
		return -- e.g. the Studio test dummy: no character animation
	end
	local w = windups[thrower]
	if thrower == localPlayer() then
		ownProjectiles[payload.projId] =
			{ untilAt = payload.releaseAt + OWN_PROJECTILE_SECONDS, lane = false, throw = true }
		local p = pending
		if p and payload.seq == p.seq then
			pending = nil
			stats.accepted += 1
		end
		if w == nil or w.finished or w.cancelled or w.releaseAt ~= nil then
			-- An answer after the windup was cancelled (or a second throw on top): show the release.
			w = ThrowController.newWindup(windup, math.huge, true)
			windups[thrower] = w
		end
		nextThrowAt = nextAt
		readyAt = nextAt - windup
		lastReleaseAt = payload.releaseAt
		ThrowController.CooldownChanged:fire(readyAt, nextThrowAt)
	else
		w = ThrowController.newWindup(windup, math.huge, true)
		windups[thrower] = w
		setSquashOverlay(thrower, w)
	end
	local current = w :: Windup
	if current.style == nil then
		ThrowController.setStyle(current, payload.squishyId, rootOf(thrower))
	end
	current.releaseAt = payload.releaseAt
	current.popAt = popAt
end

local function onThrowRejected(seq: unknown, reason: unknown, nextAt: unknown)
	if type(seq) ~= "number" then
		return
	end
	local code = if type(reason) == "string" then reason else "error.generic"
	local p = pending
	local sound = ThrowController.rejectSound(seq, if p then p.seq else nil)
	if sound then
		playSound(sound, nil)
	end
	if p and p.seq == seq then
		pending = nil
		bufferedAt = nil
		stats.rejected += 1
		local w = windups[localPlayer()]
		if w then
			ThrowController.cancelWindup(w)
		end
	end
	local now = serverNow()
	local adopted = ThrowController.acceptedNextThrowAt(nextAt, now, REJECT_AHEAD_SECONDS)
	if adopted ~= nil then
		nextThrowAt = adopted
		local ctx = throwContext(now)
		local windup = if ctx then ctx.def.throw.windup else 0
		readyAt = nextThrowAt - windup
		ThrowController.CooldownChanged:fire(readyAt, nextThrowAt)
	end
	ThrowController.Rejected:fire(code, nextThrowAt)
end

local function onThrowImpact(raw: unknown)
	local impact = ThrowController.parseImpact(raw)
	if impact == nil then
		return
	end
	local own = ownProjectiles[impact.projId]
	if own ~= nil then
		if not own.lane then
			ownProjectiles[impact.projId] = nil -- a throw ends at its first impact; a lane flies on
		end
		if impact.kind == "player" or impact.kind == "target" then
			ThrowController.HitConfirmed:fire(impact)
		end
	end
end

-- Spec phase 5: remembers a release's own projectiles for HitConfirmed (each bird and drop is its own projId).
local function rememberOwnUlt(event: UltimateEvent, ability: any)
	local speed = if isNumber(event.speed) and event.speed > 0 then event.speed else ability.speed
	local projId = event.projId
	if isNumber(projId) then
		ownProjectiles[projId :: number] = {
			untilAt = event.telegraphEndsAt + math.max(event.length, 0) / speed + OWN_PROJECTILE_SECONDS,
			lane = ability.kind == "lane" or ability.kind == "roller", -- they fly on through the player they hit
		}
	end
	local shots: { Types.UltimateShot } = event.shots or {}
	for _, shot in shots do
		ownProjectiles[shot.projId] = {
			untilAt = shot.releaseAt + math.max(shot.length, 0) / speed + OWN_PROJECTILE_SECONDS,
			lane = false,
		}
	end
	local drops: { Types.UltimateDrop } = event.drops or {}
	for _, drop in drops do
		ownProjectiles[drop.projId] = { untilAt = drop.landAt + OWN_PROJECTILE_SECONDS, lane = false }
	end
end

local function onUltimateEvent(raw: unknown)
	local event = ThrowController.parseUltimateEvent(raw)
	if event == nil then
		return
	end
	local caster = Players:GetPlayerByUserId(event.casterId)
	if caster == nil then
		return
	end
	local ultimateId, ability = ThrowController.eventAbility(event)
	if ultimateId == nil or ability == nil then
		return
	end
	local current = ults[caster]
	local now = serverNow()
	if event.phase == "telegraph" then
		local weight = if current and not current.finished then current.weight else 0
		ults[caster] = {
			phase = "telegraph",
			ultimateId = ultimateId,
			recoverySeconds = ability.recoverySeconds,
			startedClock = os.clock(),
			telegraphEndsAt = event.telegraphEndsAt,
			releaseStart = nil,
			cancelFrom = 0,
			weight = weight,
			finished = false,
		}
		if caster == localPlayer() then
			rootedUntil = event.telegraphEndsAt + ability.recoverySeconds
			if not ControlsController.isContextActive("Duel") then
				practiceUltReadyAt = now + ability.practiceCooldownSeconds
			end
		end
	elseif event.phase == "release" then
		if caster == localPlayer() then
			rememberOwnUlt(event, ability)
		end
		if current == nil or current.finished then
			ults[caster] = {
				phase = "release",
				ultimateId = ultimateId,
				recoverySeconds = ability.recoverySeconds,
				startedClock = os.clock(),
				telegraphEndsAt = event.telegraphEndsAt,
				releaseStart = math.max(event.telegraphEndsAt, now - 0.05),
				cancelFrom = 0,
				weight = 1,
				finished = false,
			}
		else
			current.telegraphEndsAt = event.telegraphEndsAt
		end
	elseif event.phase == "cancel" then
		if current and not current.finished then
			current.phase = "cancel"
			current.startedClock = os.clock()
			current.cancelFrom = current.weight
		end
		if caster == localPlayer() then
			rootedUntil = now
		end
	end
end

local function endMatchVisuals()
	pending = nil
	bufferedAt = nil
	holdDown = false
	dropCharge() -- feature 1
	handsBusyUntil = -math.huge
	for player, w in windups do
		w.finished = true
		fadeLayers(player)
	end
	table.clear(windups)
	for player in ults do
		fadeLayers(player)
	end
	table.clear(ults)
	for player in table.clone(hiddenUntil) do
		showHeldNow(player)
	end
	rootedUntil = 0
end

local function setMatch(view: MatchView?)
	local previous = match
	match = view
	if view == nil then
		if previous ~= nil then
			endMatchVisuals()
			nextThrowAt, readyAt, lastReleaseAt = 0, 0, 0
		end
	elseif PHASE_ENDED[view.phase] then
		if previous == nil or not PHASE_ENDED[previous.phase] then
			endMatchVisuals()
		end
	else
		-- A new match, or the start of Active (the server resets nextThrowAt then): no cooldown carried over.
		local newMatch = previous == nil or previous.matchId ~= view.matchId
		local activeStart = view.phase == "Active" and previous ~= nil and not PHASE_THROW[previous.phase]
		if newMatch or activeStart then
			nextThrowAt, readyAt, lastReleaseAt = 0, 0, 0
		end
	end
end

-- Frame step --------------------------------------------------------------------------------------------------------

local function updateAim(now: number)
	local ctx, reason = throwContext(now)
	local inContext = ControlsController.isContextActive("Duel") or ControlsController.isContextActive("Practice")
	local state = aimState
	-- Feature 1: the charge for the reticle (its fill in the toy's colour, the pulse at full).
	local running = charge
	state.charging = running ~= nil
	state.charge = if running then ThrowCharge.level(running.startAt, now) else 0
	state.chargeFull = running ~= nil and ThrowCharge.isFull(state.charge)
	state.chargeColor = if running then running.color else nil
	if not inContext then
		state.state = "hidden"
		state.reason = nil
		state.kind = nil
		state.aimPoint = nil
		return
	end
	local point, screen, centered, ray = cameraAim()
	state.screenPosition = screen
	state.centered = centered
	state.aimPoint = point
	state.kind = if ctx then ctx.kind else nil
	local windup = if ctx then ctx.def.throw.windup else 0
	state.readyAt = nextThrowAt - windup
	state.nextThrowAt = nextThrowAt
	state.progress = ThrowController.cooldownProgress(now, lastReleaseAt, nextThrowAt - windup)
	local player = localPlayer()
	local root = aliveRoot(player)
	if ctx == nil or root == nil then
		state.state = "blocked"
		state.reason = reason or "throw.context"
	elseif isRooted(now) then
		state.state = "blocked"
		state.reason = "throw.rooted"
	elseif handsBusy(now) then
		state.state = "blocked"
		state.reason = "throw.busy" -- feature 1: a catch window or a crush
	elseif ctx.kind == "duel" and not insideOwnHalf(root.Position) then
		state.state = "blocked"
		state.reason = "throw.context"
	elseif ctx.kind == "practice" and point ~= nil and ray ~= nil then
		local flat = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
		local angle = if flat.Magnitude > 1e-3
			then math.deg(math.acos(math.clamp(flat.Unit:Dot(RANGE_FORWARD), -1, 1)))
			else 0
		if angle > COMBAT.Throw.practiceConeDeg then
			state.state = "blocked"
			state.reason = "throw.direction"
		else
			state.state = if now < state.readyAt or pending ~= nil then "cooling" else "ready"
			state.reason = nil
		end
	else
		-- Power-ups v1.1 review fix: in a match, "cooling" too while the own throws in the air are at the server's cap.
		local waiting = now < state.readyAt or pending ~= nil or ThrowController.atThrowCap(ctx.kind)
		state.state = if waiting then "cooling" else "ready"
		state.reason = nil
	end
end

local function updateTouch(now: number)
	local ctx = throwContext(now)
	local def = if ctx then ctx.def else nil
	local ability = if def then abilityOf(def) else nil
	ControlsController.setTouchAvailable("Ultimate", ability ~= nil)
	if def == nil then
		ControlsController.setTouchState("Throw", 1, nil)
		return
	end
	local ready = nextThrowAt - def.throw.windup
	local progress = ThrowController.cooldownProgress(now, lastReleaseAt, ready)
	local label: string? = nil
	if progress < 1 then
		local template = Strings.resolve("common.secondsShort")
		if template then
			label = Strings.format(template, { seconds = string.format("%.1f", math.max(ready - now, 0)) })
		end
	end
	ControlsController.setTouchState("Throw", progress, label)
	if ability ~= nil then
		local ult = ThrowController.getUltState()
		local ultLabel: string? = nil
		local ultProgress = 1
		if ult.ready then
			ultLabel = Strings.resolve("duel.ultReady")
		elseif ctx and (ctx.kind == "duel" or ctx.kind == "match") then
			ultProgress = math.clamp(ult.charge / math.max(ult.chargeMax, 1), 0, 1)
			local template = Strings.resolve("common.percent")
			if template then
				ultLabel = Strings.format(template, { value = math.floor(ultProgress * 100) })
			end
		else
			local cooldown = ability.practiceCooldownSeconds
			ultProgress = 1 - math.clamp((practiceUltReadyAt - now) / math.max(cooldown, 0.01), 0, 1)
		end
		ControlsController.setTouchState("Ultimate", ultProgress, ultLabel)
	end
end

local function restoreShoulder()
	shoulder = ThrowController.shoulderStep(shoulder, nil, nil)
end

-- §5.10 shoulder offset for centre aim (touch, gamepad) in the Duel and Practice contexts; off while first person
-- suppresses it (setShoulderSuppressed).
local function updateShoulder()
	local inContext = ControlsController.isContextActive("Duel") or ControlsController.isContextActive("Practice")
	local camera = Workspace.CurrentCamera
	local player = localPlayer()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(player)
	local offset: Vector3? = nil
	if
		ThrowController.shoulderApplies(inContext, ControlsController.preferredInput(), shoulderSuppressed)
		and camera ~= nil
		and root ~= nil
	then
		offset = ThrowController.shoulderOffset(root.CFrame, camera.CFrame.RightVector, SHOULDER_STUDS)
	end
	shoulder = ThrowController.shoulderStep(shoulder, humanoid, offset)
end

local function stepThrowers(dt: number, now: number)
	for player, w in windups do
		if player.Parent == nil then
			windups[player] = nil
			continue
		end
		local wasReleased = w.releaseStart ~= nil
		local sample = ThrowController.stepWindup(w, dt, now)
		if not wasReleased and w.releaseStart ~= nil then
			hideHeld(player, w.popAt or now)
		end
		applyLayer(player, LAYER_THROW, sample, w)
		if sample and sample.phase == "release" and not w.swooshed and not w.cancelled then
			w.swooshed = true
			releaseSwoosh(player, w)
		end
		if w.finished then
			windups[player] = nil
			if player == localPlayer() and w.cancelled then
				stats.cancelled += 1
				local p = pending
				if p and p.sentAt + p.windup + COCKED_S < now then
					pending = nil -- unanswered: give the input back
				end
			end
		end
	end
	for player, untilAt in hiddenUntil do
		if player.Parent == nil then
			hiddenUntil[player] = nil
		elseif now >= untilAt then
			popIn(player)
		end
	end
	for player in popIns do
		if player.Parent == nil then
			popIns[player] = nil
		end
	end
	for player, ult in ults do
		if player.Parent == nil then
			ults[player] = nil
			continue
		end
		local sample = stepUlt(ult, dt, now, ult.recoverySeconds)
		applyLayer(player, LAYER_ULT, sample)
		if ult.finished then
			ults[player] = nil
		end
	end
end

-- Feature 1: one frame of the charge: dropped when it may not go on (no context, a root, the hands busy, dead), else
-- its tone, and the full ping once (design: html:514).
local function stepCharge(now: number)
	local running = charge
	if running == nil then
		return
	end
	local ctx = throwContext(now)
	if ctx == nil or isRooted(now) or handsBusy(now) or aliveRoot(localPlayer()) == nil then
		dropCharge()
		return
	end
	local c = ThrowCharge.level(running.startAt, now)
	setChargeTone(c, now - running.startAt)
	if ThrowCharge.isFull(c) and not running.full then
		running.full = true
		playSound(SOUND_CHARGE_FULL, { priority = 1 })
	end
end

local function step(dt: number, _clock: number): boolean
	local now = serverNow()
	stepCharge(now)
	updateAim(now)
	-- Hold to charge and the input buffer (§5.2; feature 1, ThrowController.holdStep).
	if bufferedAt ~= nil or (holdDown and charge == nil and RULES.HoldToCharge) then
		local ctx = throwContext(now)
		if ctx == nil then
			bufferedAt = nil
		else
			local held = holdDown and RULES.HoldToCharge == true
			local pressed = bufferedAt
			local buffer = rulesNumber("InputBufferSeconds", RULES.InputBufferSeconds)
			local ready = readyFor(ctx)
			-- Power-ups v1.1 review fix: a press let go while the own throws are at the server's cap is dropped.
			local keeps = pressed == nil
				or (
					not ThrowController.atThrowCap(ctx.kind)
					and ThrowController.bufferKeeps(pressed, math.max(ready, rootedUntil), buffer)
				)
			local action = ThrowController.holdStep(held, charge ~= nil, canCharge(ctx, now), pressed ~= nil, keeps)
			if action == "start" then
				startCharge(ctx, now)
			elseif action == "throw" then
				bufferedAt = nil
				fire(ctx, nil, nil)
			elseif action == "drop" then
				bufferedAt = nil -- pressed too early: the cooldown (or the root) ended long after it
			end
		end
	end
	stepThrowers(dt, now)
	updateShoulder()
	updateTouch(now)
	forgetOwnProjectiles(now)
	return true
end

-- Public ------------------------------------------------------------------------------------------------------------

-- The reticle / cooldown state of this frame (read-only; updated every render frame while a throw context is on).
function ThrowController.getAimState(): AimState
	return aimState
end

function ThrowController.getUltState(): UltState
	local now = serverNow()
	local ctx = throwContext(now)
	local def = if ctx then ctx.def else nil
	local ability = if def then abilityOf(def) else nil
	local charge = StateController.charge(localPlayer().UserId)
	local chargeMax = if ability then ability.chargeMax else 100
	local ready = false
	if ability ~= nil and ctx ~= nil then
		if ctx.kind == "duel" or ctx.kind == "match" then
			ready = charge >= chargeMax and not isRooted(now)
		else
			ready = now >= practiceUltReadyAt and not isRooted(now)
		end
	end
	return {
		available = ability ~= nil,
		charge = charge,
		chargeMax = chargeMax,
		ready = ready,
		practiceReadyAt = practiceUltReadyAt,
		rooted = isRooted(now),
	}
end

-- The local player's windup, duel or practice (one local windup path), as plain values: (tau, W, releaseAt,
-- releaseStart, cancelled) while its record lives, else nil, nil, nil, nil, false. Nothing writable leaves the module
-- (the first-person hand's throw track reads it every frame; spec 2026-10-10 §3.6).
function ThrowController.localWindup(): (number?, number?, number?, number?, boolean)
	return ThrowController.windupValues(windups[localPlayer()])
end

-- The local player's ultimate animation, duel or practice, as plain values: (phase "cast" | "telegraph" | "release" |
-- "cancel", telegraphEndsAt, releaseStart, ultimateId) while it lives, else nil, nil, nil, nil.
function ThrowController.localUlt(): (string?, number?, number?, string?)
	return ThrowController.ultValues(ults[localPlayer()])
end

-- Feature 1: the local charge as plain values, (c 0-1, seconds since it started, full) while one runs, else nil, nil,
-- false (the first-person overlay's charge pose reads it every frame).
function ThrowController.localCharge(): (number?, number?, boolean)
	local running = charge
	if running == nil then
		return nil, nil, false
	end
	local now = serverNow()
	local c = ThrowCharge.level(running.startAt, now)
	return c, math.max(0, now - running.startAt), ThrowCharge.isFull(c)
end

-- Aim arc (2026-10-16, AimArcController reads it every frame): while a charge runs in a throw context, the throw that
-- letting go now would launch: launchFor's origin and direction (the camera aim, aim assist, the missed-ray rule) ×
-- launchSpeed for the charge the server will measure (releaseCharge's: c when its ChargeStart left, else 0), the toy's
-- gravity and radius, c and the toy's accent. nil when no charge runs or nothing could be thrown now.
function ThrowController.chargePreview(): ChargePreview?
	local running = charge
	if running == nil then
		return nil
	end
	local now = serverNow()
	local ctx = throwContext(now)
	local root = aliveRoot(localPlayer())
	if ctx == nil or root == nil then
		return nil
	end
	local c = ThrowCharge.level(running.startAt, now)
	local level = if running.sent then c else 0
	local origin, dir = ThrowController.launchFor(ctx, root, nil, nil, level, false)
	if origin == nil or dir == nil then
		return nil
	end
	local throw = ctx.def.throw
	return {
		origin = origin,
		velocity = dir * ThrowController.launchSpeed(throw, level, ctx.speedMultiplier),
		gravity = throw.gravity,
		radius = throw.radius,
		charge = c,
		color = running.color,
	}
end

-- Feature 1: drops a running charge without a throw (CatchController: a catch press cancels a charge, design:
-- html:344). The button must be pressed again to charge.
function ThrowController.cancelCharge()
	if charge ~= nil then
		dropCharge()
	end
	holdDown = false
	bufferedAt = nil
end

-- Feature 1: the hands are busy until server time `untilAt` (CatchController: an open catch window, a crush): no
-- charge, throw or ultimate before; a later time only extends it.
function ThrowController.setHandsBusy(untilAt: number)
	if untilAt == untilAt and untilAt > handsBusyUntil then
		handsBusyUntil = untilAt
	end
end

-- Feature 1: whether the hands are busy now (the dash's gate, the overlay).
function ThrowController.handsBusy(): boolean
	return handsBusy(serverNow())
end

-- Feature 1: whether an ultimate roots the local player now (its telegraph or recovery; CatchController's gate reads it
-- every frame, so it skips getUltState's charge and ability work).
function ThrowController.rootedNow(): boolean
	return isRooted(serverNow())
end

-- First person (spec 2026-10-10 §3.1, set by FirstPersonController while it is on, duel or practice): no shoulder
-- offset; the saved CameraOffset goes back at once. This module stays the only writer of Humanoid.CameraOffset.
function ThrowController.setShoulderSuppressed(on: boolean)
	shoulderSuppressed = on == true
	if shoulderSuppressed then
		restoreShoulder()
	end
end

function ThrowController.isShoulderSuppressed(): boolean
	return shoulderSuppressed
end

-- The local player's current duel view (StateController.duel(); nil outside a match).
function ThrowController.getMatch(): MatchView?
	return StateController.duel()
end

-- True when projId is one of the local player's live projectiles.
function ThrowController.isOwnProjectile(projId: number): boolean
	return ownProjectiles[projId] ~= nil
end

-- Studio AutoDriver / debug: one throw at a world point (same rules as a press: context, phase, cooldown, one in
-- flight). Returns false and a reason code when it cannot throw now.
function ThrowController.throwAt(point: Vector3): (boolean, string?)
	local now = serverNow()
	local ctx, reason = throwContext(now)
	if ctx == nil then
		return false, reason
	end
	if pending ~= nil or ownWindupBusy() or isRooted(now) or now < readyFor(ctx) or handsBusy(now) then
		return false, "throw.cooldown"
	end
	if ThrowController.atThrowCap(ctx.kind) then
		return false, "throw.tooMany" -- power-ups v1.1 review fix: the server's reason
	end
	return fire(ctx, point, nil)
end

-- Studio AutoDriver / debug: the ultimate toward a world point.
function ThrowController.ultimateAt(point: Vector3): (boolean, string?)
	return tryUltimate(point)
end

-- Where to aim at the opponent (capsule centre, or the opponent's pad when no character is found).
function ThrowController.opponentAimPoint(): Vector3?
	return opponentCentre()
end

-- Studio / debug counters.
function ThrowController.counts(): { [string]: any }
	local live = 0
	for _, connection in connections do
		if connection.connected then
			live += 1
		end
	end
	local animating = 0
	for _ in windups do
		animating += 1
	end
	local hidden = 0
	for _ in hiddenUntil do
		hidden += 1
	end
	local own = 0
	for _ in ownProjectiles do
		own += 1
	end
	return {
		ownProjectiles = own,
		shoulderOffset = shoulder ~= nil,
		aim = aimState.state,
		throwsSent = stats.throwsSent,
		ultsSent = stats.ultsSent,
		accepted = stats.accepted,
		rejected = stats.rejected,
		cancelled = stats.cancelled,
		assisted = stats.assisted,
		seq = lastSeq,
		pending = pending ~= nil,
		windups = animating,
		hiddenHeld = hidden,
		connections = live,
	}
end

-- Lifecycle

function ThrowController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(ControlsController.bindAction("Throw", onThrowInput))
	c:add(ControlsController.bindAction("PracticeThrow", onThrowInput))
	c:add(ControlsController.bindAction("Ultimate", onUltInput))
	c:add(ControlsController.bindAction("PracticeUltimate", onUltInput))
	c:add(Scheduler.add(step, "render"))
	c:add(ControlsController.ContextChanged:connect(function(context: string, on: boolean)
		if (context == "Duel" or context == "Practice") and not on then
			holdDown = false
			bufferedAt = nil
			dropCharge() -- feature 1
		end
	end))
	track(StateController.DuelChanged:connect(function(view: MatchView?)
		setMatch(view)
	end))
	-- FFA/TDM v1: the 12-player match view gets setMatch's cooldown reset and end visuals (its `match` stays the duel's).
	track(
		StateController.MatchChanged:connect(function(view: StateController.MatchView?, old: StateController.MatchView?)
			if view == nil then
				if old ~= nil then
					endMatchVisuals()
					nextThrowAt, readyAt, lastReleaseAt = 0, 0, 0
				end
			elseif PHASE_ENDED[view.phase] then
				if old == nil or not PHASE_ENDED[old.phase] then
					endMatchVisuals()
				end
			else
				local newMatch = old == nil or old.matchId ~= view.matchId
				local activeStart = view.phase == "Active" and old ~= nil and not PHASE_THROW[old.phase]
				if newMatch or activeStart then
					nextThrowAt, readyAt, lastReleaseAt = 0, 0, 0
				end
			end
		end)
	)
	track(NetController.on("ThrowStarted", onThrowStarted))
	track(NetController.on("ThrowRejected", onThrowRejected))
	track(NetController.on("ThrowImpact", onThrowImpact))
	track(NetController.on("UltimateEvent", onUltimateEvent))
	match = StateController.duel()
	c:add(function()
		endMatchVisuals()
		restoreShoulder()
		table.clear(connections)
		table.clear(ownProjectiles)
		table.clear(popIns)
		match = nil
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function ThrowController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return ThrowController
