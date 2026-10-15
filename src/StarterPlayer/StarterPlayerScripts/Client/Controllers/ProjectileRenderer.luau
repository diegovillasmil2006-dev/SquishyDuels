--!strict
-- ProjectileRenderer (client only). DESIGN §5.1, §9.7, §9.8 (projectile row), §9.15, §5.11.
-- Cosmetic projectiles from ThrowStarted only (never predicted): the server simulates with no Parts, and the client
-- draws a squishy on the same analytic path (ProjectileMath, workspace:GetServerTimeNow()).
--
-- * Appears at releaseAt (server time). A ThrowStarted that arrives late fast-forwards: the position is always a
--   function of server time. Path P(τ) = ProjectileMath.settledPositionAt(origin, velocity, gravity, τ, offset), τ =
--   now - releaseAt, offset = thrower's held squishy at the release - origin (it starts in the hand and settles on the
--   server path within ≈ 160 ms); the model scale blends from the hand size to the flight size with the same factor.
-- * Model: SquishyCache.clone(squishyId, "World", flightScale) with flightScale = SquishyBuilder.flightScale(blueprint,
--   payload.radius), so the drawn frontal radius equals the hit radius (§8.1 #9). Pooled per (squishy, scale): idle
--   models are unparented and kept (reading: up to IDLE_PER_KEY per key), with their SquishDeformer attached once.
-- * Orientation CFrame.lookAt(P, P + V), face leading; flightSpin adds only roll about the travel axis ("wobble" ±8°,
--   "roll" 360°/s, Config.Anim.throw; now the fallback of the flight styles below). Speed stretch S = (0.94, 0.94,
--   1.12) along travel (deformer, pivot space).
-- * Readability: Ink outline Highlight (OutlineTransparency 0.15, FillTransparency 1, DepthMode Occluded, created and
--   destroyed per use, within the client Highlight budget) and a shadow disc (FxPool part, Ink, Transparency 0.7,
--   1.1× the flight diameter at the floor shrinking to 0.4× with height) at the arena floorY (StateController duel
--   view) or the practice lane floor (PracticeTargets.FLOOR_Y); no per-frame raycast.
-- * Trails per rarity (Art/RarityStyle), FxPool trails (cap 8 active): an own or duel projectile takes a trail from
--   another player's practice projectile when the cap is full. Comet / twin-ribbon / ember particles ride along on a
--   pooled emitter. 6 air puffs at the hand at the release (Config.Vfx.Effects.throwReleasePuffs). Commons keep no
--   trail (§0.3 #3).
-- * Release (§18.4.5), in the same first-drawn-frame gate as the puffs (tau < PUFF_WINDOW, so a fast-forwarded
--   projectile gets none): an air ring for every rarity (Anim/FxShapes.ring at the hand facing the velocity, 0 ->
--   ThrowRing.toStuds in ThrowRing.seconds, White, Transparency transparencyFrom -> 1; none under ReducedMotion) and
--   sfx.throw, 3D at the hand (another thrower's throw is an `other = "throw"` sound: distance and count limits).
-- * Impact (ThrowImpact, the server's position and normal only): "player" / "target": splat along the normal for
--   90 ms (0.55 along, 1.4 across, Quad Out), then shrink to 0 in 120 ms (reading: the deformer floor is 0.5, so the
--   last half of the shrink is a fade); "geometry" / "expired" / "fizzle": a small splat and a 200 ms fade. A
--   projectile with no impact message disappears ProjectileMaxLifetime + EXPIRE_GRACE after its release.
-- * Impact flash (§18.4.2): on a "player" / "target" impact the projectile's own outline Highlight turns its fill White
--   and FillTransparency goes 1 -> ImpactFlash.fillFrom -> 1 over ImpactFlash.ms (no new Highlight).
-- * Hit-stop (§18.4.4, Anim/HitStop): when this client holds the hit (the local victim or thrower; the key is the
--   projId, so VfxController and this module share one hold), the splat starts at its contact squash (u = 0.35 of the
--   splat phase), stays there for the hold, then plays on; the flash stays at its peak (fillFrom) for the hold, then
--   fades out (flashElapsed). Everyone else sees the impact as before.
-- * Contact hold (reading, cosmetic only): the server's ThrowImpact arrives about half a round trip after the drawn
--   projectile reaches the surface, so each frame a ray along the drawn step (Default group, excluding characters,
--   SD_ClientFx and Studio test dummies; arena barriers and dividers are skipped by their groups, decor by CanQuery)
--   stops the model against the floor, cover or the backstop instead of letting it sink through. It decides nothing:
--   no splat and no puff until the server's ThrowImpact (at the server's position); a hold with no impact message
--   within CONTACT_WAIT_SECONDS is removed quietly. Players are never stopped on (the server decides hits).
-- * Match end: when the duel view ends (Result, Returning, Cancelled, Void) every duel projectile still in flight is
--   removed at once; one whose splat has started (the match-ending hit: its ThrowImpact and DuelState(Result) arrive
--   in the same frame) plays it out. When the view goes away (back in the lobby) every duel projectile is removed and
--   the idle pool is emptied. Practice projectiles end by impact or lifetime.
-- * Flight styles (squishy overhaul spec 2026-10-09 §3.2, option A: the face always leads; the server path never
--   changes). Each pooled model owns one Anim/SquishRig (made with the model, from its blueprint's `motion`), which
--   this module alone steps. Every projectile shows the squish face all flight long and is posed
--   poseAt(P, V, roll, nod) = frameAt(P, V, roll)·Angles(nod, 0, 0), roll / nod / pulse being SquishRig.flightPose of
--   τ (one Root write a frame, as before). The stretch pulse along travel and the section flaps go only to the detailed
--   models: at most Config.Vfx.Budgets.flightDetailModels (flightDetailModelsLow when MeshQuality.forCamera() is not
--   "High"; none under ReducedMotion), re-picked every DETAIL_RANK_SECONDS among the flying ones whose style has a
--   pulse or flaps for their sections, incoming first (dot(V, camera - P) > 0), then by distance, the local player's own
--   one last. Those step their rig and write it in one SquishDeformer:apply (in the "SD_Rigs" profiler scope, spec
--   §5); the others keep today's setScale (it
--   sleeps once the hand blend settles). A model leaving the detail (re-pick, contact, impact) writes its section base
--   once. ReducedMotion (read at ThrowStarted) or a toy without a motion row: today's flightSpin, no nod, pulse or flap.
--   A pool return resets the rig and rests the deformer (resetModel): no squish face or turned ear on the next throw.
-- * First person (spec 2026-10-10 §3.6, §3.10; FirstPersonController.isActive, duel or practice): the local player's
--   own throw starts at ViewmodelController.lastReleasePoint (the point on the camera ray through the overlay toy) with
--   handScale = factor / flightScale (startPoint, handStart: the same size on screen with or without the cover cut),
--   and its release ring is drawn at Config.FirstPerson.ownRingScale. Every projectile within nearFade.to (4.5 studs)
--   of the camera fades (Anim/NearFade: parts and outline Highlight), except the own one in its first 0.2 s in flight;
--   at impact the near fade is a max with the splat fade (partFade), so it never brings the splat back. The local
--   first-person victim gets no white impact fill (impactFlashOn). Third person is unchanged.
-- * Feature 1 (2026-10-11; design: the combat-effects page "Squishy Combat FP v2.html", html:243, 333-338, 604-605;
--   Shared/ThrowCharge, Config.Vfx.Charge / Catch): ThrowStarted.power (the server's charge) widens and lengthens the
--   rarity trail (trailFactors), grows the release puffs and ring; from whiteRingFrom the grown ring takes the toy's
--   accent with a smaller White one inside it (design: html:335), from powerRingFrom an accent ring crosses the path
--   powerRingAheadStuds ahead of the hand (html:338; no ring under ReducedMotion, as before). In flight a charged
--   throw whose rarity trail has no emitter of its own (Commons too) sheds accent specks (ThrowCharge.speckRate,
--   within Effects.projectileParticles; halved under ReducedMotion). A caught throw (CatchController.Caught; no
--   ThrowImpact comes) stops its trail and specks and flies from where it was caught into the catcher's hands (a
--   point holdForwardStuds in front of and holdUpStuds above its root, facing where the catcher looks) over
--   flyInSeconds, then shakes and squashes there as the crush does (Anim/ChargePoses.crushShape) until
--   CatchController.Burst removes it (the burst's effects are VfxController's; a caught toy with no Burst goes
--   CAUGHT_GRACE after its burstAt). A first-person catcher sees it in the overlay instead: its world copy goes at once.
-- Impact puffs, rings, hit flashes and Dragon Rush visuals are VfxController's.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local PracticeTargets = require(Shared.Practice.PracticeTargets)
local ProjectileMath = require(Shared.ProjectileMath)
local RarityStyle = require(Shared.Art.RarityStyle)
local Signal = require(Shared.Util.Signal)
local SquishyBlueprints = require(Shared.Art.SquishyBlueprints)
local SquishyBuilder = require(Shared.Art.SquishyBuilder)
local ThrowCharge = require(Shared.ThrowCharge)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ChargePoses = require(Client.Anim.ChargePoses)
local FxPool = require(Client.Anim.FxPool)
local FxShapes = require(Client.Anim.FxShapes)
local HitStop = require(Client.Anim.HitStop)
local MeshQuality = require(Client.Anim.MeshQuality)
local NearFade = require(Client.Anim.NearFade)
local Scheduler = require(Client.Anim.Scheduler)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local SquishRig = require(Client.Anim.SquishRig)
local Tweens = require(Client.Anim.Tweens)
local SquishyCache = require(Client.Models.SquishyCache)
local CatchController = require(script.Parent.CatchController)
local FirstPersonController = require(script.Parent.FirstPersonController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)
local ViewmodelController = require(script.Parent.ViewmodelController)

-- Types

export type FlightSample = {
	position: Vector3,
	velocity: Vector3,
	scale: Vector3, -- deformer scale in pivot space (stretch along -Z = travel)
	roll: number, -- radians about the travel axis
	nod: number, -- radians about the model's own X axis (the face still leads)
	pulse: number, -- the stretch pulse along travel (1 = none); drawn on the detailed models only
}

-- A blueprint's motion.flight (spec 2026-10-09 §3.2): the style name, the wobble / nod size, a pulse peak.
export type FlightStyle = { style: string, amp: number?, pulse: number? }

export type SplatSample = {
	scale: Vector3, -- pivot space: Z along the impact normal
	fade: number, -- 0 (opaque) .. 1 (gone)
	done: boolean,
}

type Impact = {
	startedClock: number,
	position: Vector3,
	normal: Vector3,
	major: boolean,
	flash: boolean, -- the fill flashes White (impactFlashOn)
	fromScale: Vector3,
	holdStart: number?, -- this client's hit-stop for the impact (HitStop.trigger), nil = none
}

-- A drawn projectile resting against a surface while the server's ThrowImpact is on its way.
type Contact = {
	clock: number, -- os.clock() when it touched
	position: Vector3,
}

type Projectile = {
	projId: number,
	payload: Types.ThrowStartedPayload,
	def: Types.SquishyDef?,
	thrower: Player?,
	own: boolean, -- the local player's
	high: boolean, -- own or duel projectile: keeps trails over other players' practice projectiles
	duel: boolean,
	matchId: string?,
	flightScale: number,
	poolKey: string,
	spinKind: string,
	flight: FlightStyle?, -- nil: today's flightSpin (ReducedMotion, or no motion row)
	wantsDetail: boolean, -- the style has a pulse or flaps for this toy (wantsDetail)
	detailed: boolean, -- has one of the detail slots (pulse and flaps)
	detailKey: number, -- detailKey() at the last pick
	model: Model?,
	root: BasePart?,
	deformer: SquishDeformer.Deformer?,
	rig: SquishRig.Rig?,
	out: SquishRig.Out?,
	parts: { BasePart },
	highlight: Highlight?,
	shadow: BasePart?,
	trails: { Trail },
	emitter: ParticleEmitter?,
	spawned: boolean,
	handOffset: Vector3,
	handScale: number,
	near: number, -- the first-person near fade last written (0 in third person)
	floorY: number,
	impact: Impact?,
	contact: Contact?,
	lastPosition: Vector3,
	lastVelocity: Vector3,
	lastScale: Vector3,
	power: number, -- feature 1: ThrowStarted.power (0 = uncharged)
	caught: Caught?, -- feature 1: caught, flying into the catcher's hands
}

-- Feature 1: a caught throw's drawn toy (server times but startClock).
type Caught = {
	catcherId: number,
	at: number,
	burstAt: number,
	startClock: number,
	from: Vector3,
}

type PoolEntry = {
	model: Model,
	deformer: SquishDeformer.Deformer,
	parts: { BasePart },
	rig: SquishRig.Rig?, -- made with the model (nil without a motion row)
	out: SquishRig.Out?,
}

-- Constants

local THROW_ANIM = Config.Anim.throw
local VFX = Config.Vfx
local HIT = VFX.Hit
local RULES = Config.Duel.Rules
local SETTLE_TAU = THROW_ANIM.pathSettleTau
local STRETCH = THROW_ANIM.speedStretch
local WOBBLE_RAD = math.rad(THROW_ANIM.wobbleRollDeg)
local ROLL_RAD_PER_S = math.rad(THROW_ANIM.rollDegPerSecond)
local FOLDER_NAME = "SD_ClientFx"
local PROJECTILE_FOLDER = "Projectiles"
-- reading (not in DESIGN, provisional): the wobble roll's frequency (Hz).
local WOBBLE_HZ = 2
-- reading: the shadow reaches its smallest size this high above the floor (studs).
local SHADOW_FULL_HEIGHT = 12
local SHADOW_THICKNESS = 0.05
local SHADOW_LIFT = 0.03 -- above the floor top, so it never z-fights
-- reading: a projectile with no ThrowImpact disappears this long after its lifetime ended.
local EXPIRE_GRACE = 0.5
-- reading: idle models kept per (squishy, scale) key; more are destroyed.
local IDLE_PER_KEY = 4
-- reading: the projectile Highlights leave this many of the client budget to VfxController (victim flash + ghost).
local HIGHLIGHT_RESERVE = 4
local HIGHLIGHT_CAP = VFX.Budgets.highlights - HIGHLIGHT_RESERVE
-- reading: the small splat of a geometry / expired / fizzle impact.
local MINOR_ALONG = 0.75
local MINOR_ACROSS = 1.2
local SPLAT_S = HIT.splatMs / 1000
local SHRINK_S = HIT.shrinkMs / 1000
local MINOR_FADE_S = HIT.minorFadeMs / 1000
-- The deformer clamps every axis to Config.Anim.deform.scaleMin; the shrink goes there, then fades.
local SHRINK_TO = Config.Anim.deform.scaleMin
local PUFF_LIFETIME = VFX.Effects.throwReleaseLifetime
local PUFF_COUNT = VFX.Effects.throwReleasePuffs
-- reading: release puffs only when the projectile is drawn within this long of its release (not fast-forwarded).
local PUFF_WINDOW = 0.1
-- reading: below the floor by this much a projectile with no impact message is dropped.
local FLOOR_DROP_STUDS = 30
-- reading (not in DESIGN, provisional): contact hold. A held projectile with no ThrowImpact after this long is removed;
-- the held centre sits this fraction of the radius off the surface; the exclusion list is rebuilt this often.
local CONTACT_WAIT_SECONDS = 0.5
local CONTACT_EMBED = 0.5
local CONTACT_REFRESH_SECONDS = 0.5
local CONTACT_MIN_STEP = 1e-3
local TEST_DUMMIES_FOLDER = "SD_TestDummies" -- Studio T2 dummies (server TestHarness)
local MAJOR_KINDS: { [string]: boolean } = { player = true, target = true }
-- Feel pass (§18.4).
local THROW_RING = VFX.ThrowRing
local IMPACT_FLASH = VFX.ImpactFlash
-- Feature 1 (2026-10-11): the charge's power and the catch (Config.Vfx.Charge / Catch).
local CHARGE_VFX = VFX.Charge
local CATCH_VFX = VFX.Catch
local CAUGHT_GRACE = 0.5 -- reading: a caught toy with no Burst goes this long after its burstAt
local CONTACT_HOLD_U = 0.35 -- §18.4.4: the splat sample held during a hit-stop (fraction of the splat phase)
local SOUND_THROW = "sfx.throw"
local ENDED_PHASES: { [string]: boolean } = { Result = true, Returning = true, Cancelled = true, Void = true }
-- Flight styles (squishy overhaul spec 2026-10-09 §3.2).
local FLIGHT_STYLES = Config.Anim.rig.flight
local BUDGETS = VFX.Budgets
-- reading (provisional): the detailed flight models are picked again this often (as the held models' re-rank).
local DETAIL_RANK_SECONDS = 0.25
local DETAIL_GROUP_STUDS = 1e5 -- detailKey: keeps the incoming / other / own groups apart (studs)
local PROFILE_RIGS = "SD_Rigs" -- the profiler scope of rig stepping and writes (spec §5)

-- Module table

local ProjectileRenderer = {}

-- Fired with (projId, position) when a projectile is first drawn (tests, debug).
ProjectileRenderer.Spawned = Signal.new() :: Signal.Signal<number, Vector3>

-- Private

local log = Log.new("Projectiles")
local cleanup: Cleanup.Cleanup? = nil
local live: { [number]: Projectile } = {}
local idle: { [string]: { PoolEntry } } = {}
local highlights = 0
local stats = { spawned = 0, impacts = 0, expired = 0, reused = 0, built = 0, held = 0, heldTimeouts = 0, caught = 0 }
local connections: { Signal.Connection } = {}
local folder: Folder? = nil
local contactParams: RaycastParams? = nil
local contactRefreshedAt = -math.huge
local rankedAt = -math.huge -- os.clock() of the last detail pick
local detailScratch: { Projectile } = {} -- reused by every pick
local random = Random.new() -- feature 1: the caught toy's shake

-- Pure helpers ------------------------------------------------------------------------------------------------------

local function ease(alpha: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): number
	return TweenService:GetValue(math.clamp(alpha, 0, 1), style, direction)
end

-- Settle factor e^(-τ/τ0) of the hand offset and the hand-to-flight scale blend (1 at the release, → 0).
function ProjectileRenderer.settleFactor(tau: number): number
	if not (tau > 0) then
		return 1
	end
	return math.exp(-tau / SETTLE_TAU)
end

-- Roll about the travel axis τ seconds into the flight for a Catalog flightSpin.
function ProjectileRenderer.rollAt(spin: string, tau: number): number
	if spin == "roll" then
		return ROLL_RAD_PER_S * tau
	end
	return WOBBLE_RAD * math.sin(2 * math.pi * WOBBLE_HZ * tau)
end

-- Where and how a projectile is drawn τ seconds after its release (§9.7). handScale = the hand model's size relative
-- to the flight model (the deformer scale at the release). With a blueprint flight style (spec 2026-10-09 §3.2) the
-- roll, nod and pulse are SquishRig.flightPose of τ; without one (`flight` nil) the roll is the Catalog flightSpin
-- `spin`, with no nod and no pulse.
function ProjectileRenderer.flightSample(
	payload: Types.ThrowStartedPayload,
	tau: number,
	handOffset: Vector3,
	handScale: number,
	spin: string,
	flight: FlightStyle?
): FlightSample
	local t = math.max(tau, 0)
	local position = ProjectileMath.settledPositionAt(payload.origin, payload.velocity, payload.gravity, t, handOffset)
	local velocity = ProjectileMath.velocityAt(payload.velocity, payload.gravity, t)
	local k = ProjectileRenderer.settleFactor(t)
	local size = 1 + (handScale - 1) * k
	local roll, nod, pulse = ProjectileRenderer.rollAt(spin, t), 0, 1
	if flight then
		roll, nod, pulse = SquishRig.flightPose(flight.style, t, false, flight.amp, flight.pulse)
	end
	return {
		position = position,
		velocity = velocity,
		scale = STRETCH * size,
		roll = roll,
		nod = nod,
		pulse = pulse,
	}
end

-- The drawn sample at a server time (render interpolation: the position is a pure function of server time, so a
-- late or hitching frame lands on the same path). nil before the release.
function ProjectileRenderer.sampleAtTime(
	payload: Types.ThrowStartedPayload,
	serverTime: number,
	handOffset: Vector3,
	handScale: number,
	spin: string,
	flight: FlightStyle?
): FlightSample?
	local tau = serverTime - payload.releaseAt
	if tau < 0 then
		return nil
	end
	return ProjectileRenderer.flightSample(payload, tau, handOffset, handScale, spin, flight)
end

-- Where a drawn projectile of `radius` rests when its step ray touched a surface at `hitPosition` with `hitNormal`.
function ProjectileRenderer.contactPosition(hitPosition: Vector3, hitNormal: Vector3, radius: number): Vector3
	local n = if hitNormal.Magnitude > 1e-6 then hitNormal.Unit else Vector3.yAxis
	return hitPosition + n * (radius * CONTACT_EMBED)
end

-- Shadow disc diameter for a projectile of `radius` at `height` studs above the floor: 1.1× the flight diameter at
-- the floor, shrinking to 0.4× at SHADOW_FULL_HEIGHT and above (Config.Vfx.Projectile).
function ProjectileRenderer.shadowDiameter(radius: number, height: number): number
	local u = math.clamp(height / SHADOW_FULL_HEIGHT, 0, 1)
	local factor = VFX.Projectile.shadowScaleLow + (VFX.Projectile.shadowScaleHigh - VFX.Projectile.shadowScaleLow) * u
	return 2 * radius * factor
end

-- The impact squash `elapsed` seconds after the impact, from the flight scale `from` (pivot space, Z = the normal).
-- major ("player" / "target"): splat (0.55 along, 1.4 across, Quad Out, 90 ms), then shrink (120 ms) and fade.
-- minor: a small splat (90 ms), then a 200 ms fade.
function ProjectileRenderer.splatSample(elapsed: number, major: boolean, from: Vector3?): SplatSample
	local start = from or Vector3.one
	local along = if major then HIT.splatAlong else MINOR_ALONG
	local across = if major then HIT.splatAcross else MINOR_ACROSS
	local splat = Vector3.new(across, across, along)
	if elapsed < SPLAT_S then
		local u = ease(elapsed / SPLAT_S, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		return { scale = start:Lerp(splat, u), fade = 0, done = false }
	end
	local tail = if major then SHRINK_S else MINOR_FADE_S
	local u = math.clamp((elapsed - SPLAT_S) / tail, 0, 1)
	if major then
		local shrink = splat:Lerp(Vector3.one * SHRINK_TO, u)
		return { scale = shrink, fade = u, done = u >= 1 }
	end
	return { scale = splat, fade = u, done = u >= 1 }
end

-- The splat clock of an impact (seconds into splatSample). Without a hit-stop it is the time since the impact. With
-- one (holdElapsed = HitStop.elapsed(holdStart, now): the time since the impact minus the hold) it starts at the
-- contact squash, CONTACT_HOLD_U (0.35) of the splat phase, stays there for the hold, then plays on (§18.4.4).
function ProjectileRenderer.impactElapsed(clockElapsed: number, holdElapsed: number?): number
	if holdElapsed == nil then
		return math.max(clockElapsed, 0)
	end
	return CONTACT_HOLD_U * SPLAT_S + math.max(holdElapsed, 0)
end

-- The impact flash's FillTransparency `t` seconds into a "player" / "target" impact (§18.4.2): 1 -> fillFrom at half
-- of ImpactFlash.ms -> 1 at ms (linear), 1 outside it.
function ProjectileRenderer.flashFill(t: number): number
	local length = IMPACT_FLASH.ms / 1000
	if not (t > 0) or t >= length then
		return 1
	end
	local half = length / 2
	local u = if t <= half then t / half else (length - t) / half
	return 1 - (1 - IMPACT_FLASH.fillFrom) * u
end

-- The flash clock of an impact (seconds into flashFill). Without a hit-stop it is the time since the impact. With one
-- (holdElapsed as for impactElapsed) the flash shows its peak (fillFrom) all through the hold, then fades out on the
-- second half of its curve. Reading: §18.4.4 freezes the projectile at contact, so its flash freezes at its peak too.
function ProjectileRenderer.flashElapsed(clockElapsed: number, holdElapsed: number?): number
	if holdElapsed == nil then
		return math.max(clockElapsed, 0)
	end
	return IMPACT_FLASH.ms / 2000 + math.max(holdElapsed, 0)
end

-- True while the projectile should still be in the air with no impact message (§5.2 ProjectileMaxLifetime).
function ProjectileRenderer.inLifetime(tau: number, lifetime: number?): boolean
	return tau <= (lifetime or RULES.ProjectileMaxLifetime) + EXPIRE_GRACE
end

-- A lookAt frame that never degenerates (straight up or down travel uses X as up).
function ProjectileRenderer.frameAt(position: Vector3, direction: Vector3, roll: number): CFrame
	local dir = if direction.Magnitude > 1e-6 then direction.Unit else Vector3.new(0, 0, -1)
	local up = if math.abs(dir.Y) > 0.999 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + dir, up) * CFrame.Angles(0, 0, roll)
end

-- The drawn flight pose (spec 2026-10-09 §3.2, option A): frameAt nodded about the model's own X axis, so the face
-- (-Z) stays within the nod of the travel direction.
function ProjectileRenderer.poseAt(position: Vector3, direction: Vector3, roll: number, nod: number): CFrame
	local frame = ProjectileRenderer.frameAt(position, direction, roll)
	if nod == 0 then
		return frame
	end
	return frame * CFrame.Angles(nod, 0, 0)
end

-- The stretch pulse along travel (pivot Z), volume kept: (1/√pulse, 1/√pulse, pulse).
function ProjectileRenderer.pulseScale(pulse: number): Vector3
	if pulse == 1 or not (pulse > 0) then
		return Vector3.one
	end
	local across = 1 / math.sqrt(pulse)
	return Vector3.new(across, across, pulse)
end

-- Whether a toy's flight needs one of the detailed models: its style has a stretch pulse (its own, or the toy's
-- motion.flight.pulse), or flaps and the toy has sections to flap.
function ProjectileRenderer.wantsDetail(flight: FlightStyle?, sections: { [string]: any }?): boolean
	local spec = if flight then FLIGHT_STYLES[flight.style] else nil
	if flight == nil or spec == nil then
		return false
	end
	local pulse = spec.pulseAmp ~= nil or (spec.pulseHz ~= nil and flight.pulse ~= nil)
	local flaps = spec.flapHz ~= nil and sections ~= nil and next(sections) ~= nil
	return pulse or flaps
end

-- The order the detailed models are picked in, smallest first: the incoming ones (dot(V, camera - P) > 0) by distance,
-- then the others by distance, the local player's own one last (seen from behind).
function ProjectileRenderer.detailKey(
	position: Vector3,
	velocity: Vector3,
	cameraPosition: Vector3,
	own: boolean
): number
	local toCamera = cameraPosition - position
	local distance = math.min(toCamera.Magnitude, DETAIL_GROUP_STUDS - 1)
	local group = if own then 2 elseif velocity:Dot(toCamera) > 0 then 0 else 1
	return group * DETAIL_GROUP_STUDS + distance
end

-- How many projectiles get the pulse and flaps: flightDetailModels, flightDetailModelsLow unless the quality is
-- "High" (nil in the first frames counts as Low), none under ReducedMotion.
function ProjectileRenderer.detailBudget(quality: string?, reduced: boolean): number
	if reduced then
		return 0
	end
	return if quality == "High" then BUDGETS.flightDetailModels else BUDGETS.flightDetailModelsLow
end

-- Back to rest for the pool (spec 2026-10-09 §3.2 ownership): the rig (flight, face lock, sections, springs) and the
-- model (face, looks, sections, scale), so the next throw never starts with a squish face or a turned ear.
function ProjectileRenderer.resetModel(deformer: SquishDeformer.Deformer, rig: SquishRig.Rig?)
	if rig then
		rig:reset()
	end
	deformer:rest()
end

-- First person (spec 2026-10-10 §3.6, §3.10) ------------------------------------------------------------------------

-- Where a projectile leaves the hand, and its size factor against a held-size model. The local player's own throw in
-- first person (ownFirstPerson) starts at ViewmodelController.lastReleasePoint when it has one for this release (the
-- point on the camera ray through the overlay toy, and D / D₀: below 1 when cover cut the distance); everything else
-- at the thrower's held model, factor 1. nil: no hand (the projectile starts on the server path).
function ProjectileRenderer.startPoint(
	ownFirstPerson: boolean,
	fpPoint: Vector3?,
	fpFactor: number?,
	heldPoint: Vector3?
): (Vector3?, number)
	if ownFirstPerson and fpPoint ~= nil then
		return fpPoint, fpFactor or 1
	end
	return heldPoint, 1
end

-- The hand offset and hand scale (flightSample) of a projectile leaving the hand at `point` with size `factor`:
-- point - origin and factor / flightScale (factor 1 at the held model: the start as before first person).
function ProjectileRenderer.handStart(
	origin: Vector3,
	point: Vector3,
	factor: number,
	flightScale: number
): (Vector3, number)
	return point - origin, factor / math.max(flightScale, 0.01)
end

-- The release ring's size factor: Config.FirstPerson.ownRingScale for the local player's own first-person throw (it
-- starts a few studs from the eyes), else 1.
function ProjectileRenderer.ringScale(ownFirstPerson: boolean): number
	return if ownFirstPerson then Config.FirstPerson.ownRingScale else 1
end

-- The near fade of a projectile drawn at `position` (Anim/NearFade): 0 in third person (`eye` nil), else by its
-- distance from the camera, except the local player's own one (`own`) for its first 0.2 s after the release.
function ProjectileRenderer.nearFadeAt(eye: Vector3?, position: Vector3, own: boolean, sinceRelease: number): number
	if eye == nil then
		return 0
	end
	return NearFade.projectile((position - eye).Magnitude, own, sinceRelease)
end

-- The parts' LocalTransparencyModifier at impact: the splat fade, never lowered by the near fade (their max). The splat
-- of a hit lands 2.1-2.7 studs from a first-person victim's eyes, and stepImpact writes it every frame.
function ProjectileRenderer.partFade(splatFade: number, near: number): number
	return math.max(splatFade, near)
end

-- The outline Highlight's OutlineTransparency and FillTransparency with the near fade: both move toward 1 by `near`
-- (`fill`: the impact flash's value or Config.Vfx.Projectile.fillTransparency). A Highlight may not follow the parts'
-- LocalTransparencyModifier.
function ProjectileRenderer.outlineFade(near: number, fill: number): (number, number)
	return NearFade.toward(VFX.Projectile.outlineTransparency, near), NearFade.toward(fill, near)
end

-- Whether an impact flashes the projectile's fill White (§18.4.2): every "player" / "target" impact, except for the
-- local victim in first person, where it would be a white blob filling the view (§3.10).
function ProjectileRenderer.impactFlashOn(kind: string, localIsVictim: boolean, firstPerson: boolean): boolean
	return MAJOR_KINDS[kind] == true and not (localIsVictim and firstPerson)
end

-- Feature 1 (pure): ThrowStarted.power as a charge 0..1 (nil, not a number or not finite = 0, an uncharged throw).
function ProjectileRenderer.powerOf(power: unknown): number
	if type(power) ~= "number" or power ~= power or power == math.huge or power == -math.huge then
		return 0
	end
	return math.clamp(power :: number, 0, 1)
end

-- Feature 1 (pure): a caught toy's drawn point `elapsed` seconds (client clock) after the catch reached this client:
-- from where it was caught into the catcher's hands over Catch.flyInSeconds (Quad Out), then in the hands; where it
-- was caught when the catcher has no hands here (nil).
function ProjectileRenderer.caughtAt(from: Vector3, hands: Vector3?, elapsed: number): Vector3
	if hands == nil then
		return from
	end
	local u = math.clamp(elapsed / CATCH_VFX.flyInSeconds, 0, 1)
	return from:Lerp(hands, 1 - (1 - u) * (1 - u))
end

-- Runtime helpers ---------------------------------------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function fxFolder(): Folder
	local current = folder
	if current and current.Parent ~= nil then
		return current
	end
	local root = Workspace:FindFirstChild(FOLDER_NAME)
	if root == nil then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = Workspace
		root = created
	end
	local existing = (root :: Instance):FindFirstChild(PROJECTILE_FOLDER)
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = PROJECTILE_FOLDER
	made.Parent = root
	folder = made
	return made
end

local function track(connection: Signal.Connection)
	table.insert(connections, connection)
	local c = cleanup
	if c then
		c:add(connection)
	end
end

-- Contact-hold ray params: Default group (arena barriers and dividers never collide with it), excluding every
-- character, the client FX and the Studio test dummies. The exclusion list is rebuilt at most every
-- CONTACT_REFRESH_SECONDS (characters respawn).
local function contactRaycastParams(): RaycastParams
	local clock = os.clock()
	local params = contactParams
	if params ~= nil and clock - contactRefreshedAt <= CONTACT_REFRESH_SECONDS then
		return params
	end
	local p = params or RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.CollisionGroup = "Default"
	p.IgnoreWater = true
	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			table.insert(exclude, character)
		end
	end
	for _, name in { FOLDER_NAME, TEST_DUMMIES_FOLDER } do
		local child = Workspace:FindFirstChild(name)
		if child then
			table.insert(exclude, child)
		end
	end
	p.FilterDescendantsInstances = exclude
	contactParams = p
	contactRefreshedAt = clock
	return p
end

local function floorYFor(duel: boolean): number
	if duel then
		local view = StateController.duel()
		local arena = view and view.arena
		local y = arena and arena.floorY
		if type(y) == "number" then
			return y
		end
	end
	return PracticeTargets.FLOOR_Y
end

local function poolKeyOf(squishyId: string, scale: number): string
	return string.format("%s|%.4f", squishyId, scale)
end

local function partsOf(model: Model): { BasePart }
	local list: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= model.PrimaryPart then
			table.insert(list, descendant)
		end
	end
	return list
end

-- The flight rig of a squishy's model, from its blueprint's motion row (nil without one).
local function newRig(squishyId: string): (SquishRig.Rig?, SquishRig.Out?)
	local def = Catalog.get(squishyId)
	local blueprint = if def then SquishyBlueprints[def.blueprintId] else nil
	local motion = if blueprint then blueprint.motion else nil
	if def == nil or blueprint == nil or motion == nil then
		return nil, nil
	end
	local rig = SquishRig.new(motion, {
		axis = def.anim.squeezeAxis,
		rarity = def.rarity :: string,
		sections = blueprint.sections,
		foamRecoveryT = def.anim.foamRecoveryT,
		blink = false, -- the squish face all flight long
	})
	return rig, SquishRig.newOut()
end

local function takeModel(squishyId: string, scale: number, key: string): PoolEntry?
	local list = idle[key]
	while list and #list > 0 do
		local entry = table.remove(list) :: PoolEntry
		if entry.model.PrimaryPart ~= nil then
			stats.reused += 1
			return entry
		end
		entry.deformer:destroy()
		entry.model:Destroy()
	end
	local ok, built = pcall(function(): Model
		return SquishyCache.clone(squishyId, "World", scale)
	end)
	if not ok or typeof(built) ~= "Instance" or not (built :: Instance):IsA("Model") then
		log:warn(`no flight model for {squishyId}:`, built)
		return nil
	end
	local model = built :: Model
	if model.PrimaryPart == nil then
		model:Destroy()
		log:warn(`no flight model for {squishyId}: no Root`)
		return nil
	end
	stats.built += 1
	local deformer = SquishDeformer.attach(model)
	local rig, out = newRig(squishyId)
	return { model = model, deformer = deformer, parts = partsOf(model), rig = rig, out = out }
end

local function putModel(key: string, entry: PoolEntry)
	ProjectileRenderer.resetModel(entry.deformer, entry.rig)
	for _, part in entry.parts do
		part.LocalTransparencyModifier = 0
	end
	entry.model.Parent = nil
	local list = idle[key]
	if list == nil then
		list = {}
		idle[key] = list
	end
	local bucket = list :: { PoolEntry }
	if #bucket >= IDLE_PER_KEY then
		entry.deformer:destroy()
		entry.model:Destroy()
		return
	end
	table.insert(bucket, entry)
end

local function emptyPool()
	for _, list in idle do
		for _, entry in list do
			entry.deformer:destroy()
			entry.model:Destroy()
		end
	end
	table.clear(idle)
end

local function releaseTrails(p: Projectile)
	local pool = FxPool.default()
	for _, trail in p.trails do
		pool:release(trail)
	end
	table.clear(p.trails)
	local emitter = p.emitter
	if emitter then
		p.emitter = nil
		pool:release(emitter)
	end
end

-- Frees one trail slot by taking the trails of another player's practice projectile (§9.7: culled first).
local function stealTrailSlot(except: Projectile): boolean
	for _, other in live do
		if other ~= except and not other.high and #other.trails > 0 then
			releaseTrails(other)
			return true
		end
	end
	return false
end

local function attachTrails(p: Projectile, root: BasePart)
	local def = p.def
	if def == nil then
		return
	end
	local kind = def.visuals.trail
	local style = RarityStyle.trail(kind)
	if style == nil then
		return
	end
	local accent = Color3.fromHex(def.visuals.accent)
	local colors = RarityStyle.trailColorSequence(style.kind, accent)
	local pool = FxPool.default()
	-- Feature 1: a charged throw's trail is wider and longer (design: html:243).
	local widthFactor, lifeFactor = ThrowCharge.trailFactors(p.power)
	local half = style.width * widthFactor / 2
	for _, offset in style.offsets do
		local props = {
			Lifetime = style.lifetime * lifeFactor,
			Transparency = NumberSequence.new(style.transparencyFrom, style.transparencyTo),
			WidthScale = NumberSequence.new(1, style.widthScaleTo),
			Color = colors,
			FaceCamera = style.faceCamera,
			MaxLength = style.maxLength,
			LightEmission = style.lightEmission,
		}
		local a0, a1 = Vector3.new(offset, half, 0), Vector3.new(offset, -half, 0)
		local trail = pool:acquireTrail(root, a0, a1, props)
		if trail == nil and p.high and stealTrailSlot(p) then
			trail = pool:acquireTrail(root, a0, a1, props)
		end
		if trail then
			table.insert(p.trails, trail)
		end
	end
	local emitterStyle = style.emitter
	if emitterStyle then
		local texture = (VFX.Textures :: any)[emitterStyle.texture]
		if type(texture) == "string" then
			local emitter = pool:acquireEmitter({
				Texture = texture,
				Rate = emitterStyle.rate,
				Lifetime = NumberRange.new(emitterStyle.lifetimeMin, emitterStyle.lifetimeMax),
				Speed = NumberRange.new(0.5, 1.5),
				SpreadAngle = Vector2.new(180, 180),
				Size = NumberSequence.new(0.25, 0),
				Color = colors or ColorSequence.new(accent),
				LightEmission = style.lightEmission,
			})
			local attachment = emitter.Parent
			if attachment and attachment:IsA("Attachment") then
				attachment.WorldPosition = root.Position -- not where the pooled emitter was last used
			end
			emitter.Enabled = true
			p.emitter = emitter
		end
	end
end

-- Feature 1: a charged throw sheds specks in flight (design: html:605) when its rarity trail has no emitter of its own
-- (the comet / twin-ribbon / ember ones already shed theirs); on p.emitter, so the flight moves it and the impact,
-- the catch and the removal end it as the rarity emitter's.
local function attachSpecks(p: Projectile, root: BasePart)
	local def = p.def
	if def == nil or p.emitter ~= nil then
		return
	end
	local style = RarityStyle.trail(def.visuals.trail)
	local rate = ThrowCharge.speckRate(p.power, style ~= nil and style.emitter ~= nil)
	if Tweens.reducedMotion() then
		rate *= VFX.reducedParticleMultiplier
	end
	if not (rate > 0) then
		return
	end
	local emitter = FxPool.default():acquireEmitter({
		Texture = VFX.Textures.sparkles,
		Rate = rate,
		Lifetime = NumberRange.new(CHARGE_VFX.speckLifetimeMin, CHARGE_VFX.speckLifetimeMax), -- design: html:605
		Speed = NumberRange.new(0, CHARGE_VFX.speckSpeed),
		SpreadAngle = Vector2.new(180, 180),
		Drag = CHARGE_VFX.speckDrag,
		Size = NumberSequence.new(2 * CHARGE_VFX.speckSize, 0), -- the design's radius, as the billboard's width
		Color = ColorSequence.new(Color3.fromHex(def.visuals.accent)),
	})
	local attachment = emitter.Parent
	if attachment and attachment:IsA("Attachment") then
		attachment.WorldPosition = root.Position
	end
	emitter.Enabled = true
	p.emitter = emitter
end

local function makeShadow(p: Projectile): BasePart
	local part = FxPool.default():acquirePart({
		Name = "Shadow",
		Shape = Enum.PartType.Cylinder,
		Color = Palette.Ink,
		Transparency = VFX.Projectile.shadowTransparency,
		Size = Vector3.new(SHADOW_THICKNESS, 1, 1),
	})
	p.shadow = part
	return part
end

local function makeHighlight(p: Projectile, model: Model)
	if highlights >= HIGHLIGHT_CAP then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "Outline"
	highlight.FillTransparency = VFX.Projectile.fillTransparency
	highlight.OutlineTransparency = VFX.Projectile.outlineTransparency
	highlight.OutlineColor = Palette.Ink
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	highlights += 1
	p.highlight = highlight
end

local function handPosition(thrower: Player?): Vector3?
	if thrower == nil then
		return nil
	end
	local held = HeldSquishyController.getModel(thrower)
	if held and held.Parent ~= nil then
		return held:GetPivot().Position
	end
	return nil
end

-- The release beat on the projectile's first drawn frame: the air puffs (§9.15), the air ring for every rarity (its
-- size × ringScale) and the whoosh (§18.4.5), all at the hand. Feature 1: the charge's power grows them and adds the
-- accent rings (ThrowCharge.release; design: html:335-338; see the header).
local function releaseBeat(p: Projectile, ringScale: number)
	local from = p.payload.origin + p.handOffset
	local release = ThrowCharge.release(p.power)
	local puffs = math.floor(PUFF_COUNT * release.puffs + 0.5) -- design: html:336
	if puffs > 0 then
		FxPool.default():emit(from, puffs, {
			Texture = VFX.Textures.smoke,
			Lifetime = NumberRange.new(PUFF_LIFETIME * 0.8, PUFF_LIFETIME),
			Speed = NumberRange.new(2, 4),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new(0.3, 0),
			Color = ColorSequence.new(Palette.White),
		})
	end
	if not Tweens.reducedMotion() then
		local velocity = p.payload.velocity
		local ring = THROW_RING.toStuds * ringScale
		local accent = if p.def then Color3.fromHex(p.def.visuals.accent) else Palette.White
		-- design: html:335 (the toy-coloured ring grows with c; from whiteRingFrom a smaller white one joins it)
		local grown = if release.whiteRing then accent else Palette.White
		FxShapes.ring(from, velocity, ring * release.ring, THROW_RING.seconds, grown, THROW_RING.transparencyFrom)
		if release.whiteRing then
			local inner = ring * CHARGE_VFX.whiteRingShare
			FxShapes.ring(from, velocity, inner, THROW_RING.seconds, Palette.White, THROW_RING.transparencyFrom)
		end
		if release.powerRing and velocity.Magnitude > 1e-6 then
			-- design: html:338 (across the path, ahead of the hand; the design's own size, first person too)
			local ahead = from + velocity.Unit * CHARGE_VFX.powerRingAheadStuds
			local seconds = CHARGE_VFX.powerRingSeconds
			FxShapes.ring(ahead, velocity, release.powerRingStuds, seconds, accent, THROW_RING.transparencyFrom)
		end
	end
	-- Own sounds priority 1; another thrower's is an "other" sound (SoundController gives it -1: dropped first).
	local options: SoundController.PlayOptions = { at = from }
	if p.own then
		options.priority = 1
	else
		options.other = "throw"
	end
	local ok, err = pcall(SoundController.play, SOUND_THROW, options)
	if not ok then
		log:warn("throw sound failed:", err)
	end
end

local function spawnVisual(p: Projectile, tau: number, at: Vector3?)
	p.spawned = true
	local entry = takeModel(p.payload.squishyId, p.flightScale, p.poolKey)
	if entry == nil then
		return
	end
	local model = entry.model
	p.model = model
	p.root = model.PrimaryPart
	p.deformer = entry.deformer
	p.parts = entry.parts
	p.rig, p.out = entry.rig, entry.out
	local ownFirstPerson = p.own and FirstPersonController.isActive()
	if at == nil and tau < SETTLE_TAU * 4 then
		local fpPoint, fpFactor = nil, nil
		if ownFirstPerson then
			fpPoint, fpFactor = ViewmodelController.lastReleasePoint()
		end
		local hand, factor = ProjectileRenderer.startPoint(ownFirstPerson, fpPoint, fpFactor, handPosition(p.thrower))
		if hand then
			p.handOffset, p.handScale = ProjectileRenderer.handStart(p.payload.origin, hand, factor, p.flightScale)
		end
	end
	local sample = ProjectileRenderer.flightSample(p.payload, tau, p.handOffset, p.handScale, p.spinKind, p.flight)
	local position = at or sample.position
	local root = p.root :: BasePart
	root.CFrame = ProjectileRenderer.poseAt(position, sample.velocity, sample.roll, sample.nod)
	local rig = entry.rig
	if rig then
		-- The squish face all flight long (§3.2); the pulse and flaps wait for a detail slot.
		rig:setReduced(p.flight == nil)
		rig:setDetail("near")
		rig:flight()
		entry.deformer:setFace("squish")
	end
	entry.deformer:setScale(sample.scale)
	rankedAt = -math.huge -- pick the detailed models again on the next frame
	model.Parent = fxFolder()
	makeHighlight(p, model)
	makeShadow(p)
	if at == nil then
		attachTrails(p, root)
		attachSpecks(p, root)
		if tau < PUFF_WINDOW then
			releaseBeat(p, ProjectileRenderer.ringScale(ownFirstPerson))
		end
	end
	p.lastPosition = position
	p.lastVelocity = sample.velocity
	p.lastScale = sample.scale
	stats.spawned += 1
	ProjectileRenderer.Spawned:fire(p.projId, position)
end

local function removeProjectile(p: Projectile)
	if live[p.projId] == p then
		live[p.projId] = nil
	end
	releaseTrails(p)
	local highlight = p.highlight
	if highlight then
		p.highlight = nil
		highlight:Destroy()
		highlights = math.max(highlights - 1, 0)
	end
	local shadow = p.shadow
	if shadow then
		p.shadow = nil
		FxPool.default():release(shadow)
	end
	local model, deformer = p.model, p.deformer
	local rig, out = p.rig, p.out
	p.detailed = false
	p.rig, p.out = nil, nil
	if model and deformer then
		p.model, p.deformer = nil, nil
		if model.PrimaryPart ~= nil then
			putModel(p.poolKey, { model = model, deformer = deformer, parts = p.parts, rig = rig, out = out })
		else
			deformer:destroy()
			model:Destroy()
		end
	end
end

-- Gives or takes one of the detail slots (pulse and flaps). A model leaving it writes its section base once, so it
-- never keeps a flap angle (spec 2026-10-09 §3.2 tier drop).
local function setDetailed(p: Projectile, on: boolean)
	if p.detailed == on then
		return
	end
	p.detailed = on
	local rig, deformer = p.rig, p.deformer
	if rig == nil or deformer == nil then
		return
	end
	if on then
		rig:setDetail("hero")
	else
		rig:setDetail("near")
		deformer:setSections(nil)
	end
end

local function byDetailKey(a: Projectile, b: Projectile): boolean
	return a.detailKey < b.detailKey
end

-- Picks the detailed models among the flying ones (wantsDetail), every DETAIL_RANK_SECONDS or after a spawn.
local function pickDetailed(clock: number)
	if clock - rankedAt < DETAIL_RANK_SECONDS then
		return
	end
	rankedAt = clock
	local camera = Workspace.CurrentCamera
	local from = if camera then camera.CFrame.Position else nil
	local budget = ProjectileRenderer.detailBudget(MeshQuality.forCamera(camera), Tweens.reducedMotion())
	local localPlayer = Players.LocalPlayer
	for _, p in live do
		local flying = p.spawned and p.impact == nil and p.contact == nil and p.rig ~= nil
		if from ~= nil and budget > 0 and p.wantsDetail and flying then
			local own = p.thrower ~= nil and p.thrower == localPlayer
			p.detailKey = ProjectileRenderer.detailKey(p.lastPosition, p.lastVelocity, from, own)
			table.insert(detailScratch, p)
		else
			setDetailed(p, false)
		end
	end
	if #detailScratch > 1 then
		table.sort(detailScratch, byDetailKey)
	end
	for index, p in detailScratch do
		setDetailed(p, index <= budget)
	end
	table.clear(detailScratch)
end

local function setFade(p: Projectile, fade: number)
	for _, part in p.parts do
		part.LocalTransparencyModifier = fade
	end
end

-- The first-person near fade before the impact (§3.10): the parts carry no other fade then, so it is written (with the
-- outline's) only when it changed: never in third person, where it stays 0.
local function setNear(p: Projectile, near: number)
	if near == p.near then
		return
	end
	p.near = near
	setFade(p, near)
	local highlight = p.highlight
	if highlight then
		highlight.OutlineTransparency, highlight.FillTransparency =
			ProjectileRenderer.outlineFade(near, VFX.Projectile.fillTransparency)
	end
end

-- The shadow disc under `position` on the floor (its size shrinking with the height).
local function placeShadow(p: Projectile, position: Vector3)
	local shadow = p.shadow
	if shadow then
		local height = position.Y - p.floorY
		local d = ProjectileRenderer.shadowDiameter(p.payload.radius, height)
		shadow.Size = Vector3.new(SHADOW_THICKNESS, d, d)
		shadow.CFrame = CFrame.new(position.X, p.floorY + SHADOW_LIFT, position.Z) * CFrame.Angles(0, 0, math.pi / 2)
	end
end

local function startImpact(
	p: Projectile,
	position: Vector3,
	normal: Vector3?,
	major: boolean,
	flash: boolean,
	holdStart: number?
)
	if p.impact ~= nil then
		return
	end
	setDetailed(p, false) -- the splat keeps the squish face, not the flaps
	local n = normal
	if n == nil or n.Magnitude < 1e-6 then
		local v = p.lastVelocity
		n = if v.Magnitude > 1e-6 then -v.Unit else Vector3.yAxis
	end
	p.impact = {
		startedClock = os.clock(),
		position = position,
		normal = (n :: Vector3).Unit,
		major = major,
		flash = flash,
		fromScale = p.lastScale,
		holdStart = holdStart,
	}
	local highlight = p.highlight
	if flash and highlight then
		highlight.FillColor = Palette.White -- the impact flash (§18.4.2); FillTransparency follows in stepImpact
	end
	for _, trail in p.trails do
		trail.Enabled = false
	end
	local emitter = p.emitter
	if emitter then
		emitter.Enabled = false
	end
	local shadow = p.shadow
	if shadow then
		shadow.Transparency = 1
	end
end

-- `eye`: the camera while first person is on (the near fade), else nil.
local function stepImpact(p: Projectile, eye: Vector3?): boolean
	local impact = p.impact :: Impact
	local clock = os.clock()
	local holdStart = impact.holdStart
	local sinceImpact = clock - impact.startedClock
	local holdElapsed = if holdStart ~= nil then HitStop.elapsed(holdStart, clock) else nil
	local elapsed = ProjectileRenderer.impactElapsed(sinceImpact, holdElapsed)
	local root, deformer = p.root, p.deformer
	if root == nil or deformer == nil then
		return false
	end
	local sample = ProjectileRenderer.splatSample(elapsed, impact.major, impact.fromScale)
	-- -Z (the face) looks into the surface, so the pivot Z axis is the normal.
	local radius = p.payload.radius
	local at = impact.position + impact.normal * (radius * HIT.splatAlong * 0.5)
	-- The near fade covers every splat, the own one too: its 0.2 s grace is for the start at the hand only.
	local near = ProjectileRenderer.nearFadeAt(eye, at, false, 0)
	local highlight = p.highlight
	if highlight and (impact.flash or near ~= p.near) then
		local fill = if impact.flash
			then ProjectileRenderer.flashFill(ProjectileRenderer.flashElapsed(sinceImpact, holdElapsed))
			else VFX.Projectile.fillTransparency
		highlight.OutlineTransparency, highlight.FillTransparency = ProjectileRenderer.outlineFade(near, fill)
	end
	p.near = near
	root.CFrame = CFrame.lookAt(
		at,
		at - impact.normal,
		if math.abs(impact.normal.Y) > 0.999 then Vector3.xAxis else Vector3.yAxis
	)
	deformer:setScale(sample.scale)
	setFade(p, ProjectileRenderer.partFade(sample.fade, near))
	return not sample.done
end

-- `eye`: the camera while first person is on (the near fade), else nil.
local function stepFlight(p: Projectile, now: number, dt: number, eye: Vector3?): boolean
	local tau = now - p.payload.releaseAt
	if not p.spawned then
		if tau < 0 then
			return true -- not released yet
		end
		spawnVisual(p, tau, nil)
		if p.model == nil then
			return false
		end
	end
	if not ProjectileRenderer.inLifetime(tau) then
		stats.expired += 1
		startImpact(p, p.lastPosition, nil, false, false)
		return true
	end
	local contact = p.contact
	if contact ~= nil then
		-- Resting against a surface until the server's ThrowImpact arrives (onThrowImpact ends the hold).
		if os.clock() - contact.clock > CONTACT_WAIT_SECONDS then
			stats.heldTimeouts += 1
			return false
		end
		setNear(p, ProjectileRenderer.nearFadeAt(eye, contact.position, p.own, tau))
		return true
	end
	local sample = ProjectileRenderer.sampleAtTime(p.payload, now, p.handOffset, p.handScale, p.spinKind, p.flight)
		or ProjectileRenderer.flightSample(p.payload, 0, p.handOffset, p.handScale, p.spinKind, p.flight)
	if sample.position.Y < p.floorY - FLOOR_DROP_STUDS then
		stats.expired += 1
		return false
	end
	local root, deformer = p.root, p.deformer
	if root == nil or deformer == nil or root.Parent == nil then
		return false
	end
	local position = sample.position
	local step = position - p.lastPosition
	if step.Magnitude > CONTACT_MIN_STEP then
		local hit = Workspace:Raycast(p.lastPosition, step, contactRaycastParams())
		if hit then
			position = ProjectileRenderer.contactPosition(hit.Position, hit.Normal, p.payload.radius)
			p.contact = { clock = os.clock(), position = position }
			stats.held += 1
			for _, trail in p.trails do
				trail.Enabled = false
			end
			setDetailed(p, false)
		end
	end
	sample.position = position
	root.CFrame = ProjectileRenderer.poseAt(sample.position, sample.velocity, sample.roll, sample.nod)
	setNear(p, ProjectileRenderer.nearFadeAt(eye, sample.position, p.own, tau))
	local rig, out = p.rig, p.out
	local drawn = sample.scale
	if p.detailed and rig and out then
		-- A detailed model: the rig's flaps and squish face in one write, the stretch pulse on top.
		debug.profilebegin(PROFILE_RIGS)
		rig:step(dt, out)
		drawn = out.S * sample.scale * ProjectileRenderer.pulseScale(sample.pulse)
		out.S = drawn
		deformer:apply(out)
		debug.profileend()
	else
		deformer:setScale(drawn)
	end
	local emitter = p.emitter
	if emitter then
		local attachment = emitter.Parent
		if attachment and attachment:IsA("Attachment") then
			attachment.WorldPosition = sample.position
		end
	end
	placeShadow(p, sample.position)
	p.lastPosition = sample.position
	p.lastVelocity = sample.velocity
	p.lastScale = drawn
	return true
end

-- Feature 1: the catcher's hands in the world (a point holdForwardStuds in front of and holdUpStuds above its root)
-- and where it looks; nil when the catcher has no root here.
local function catcherHands(catcherId: number): (Vector3?, Vector3?)
	local catcher = Players:GetPlayerByUserId(catcherId)
	local character = catcher and catcher.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	local frame = root.CFrame
	return (frame * CFrame.new(0, CATCH_VFX.holdUpStuds, -CATCH_VFX.holdForwardStuds)).Position, frame.LookVector
end

-- Feature 1: a caught toy flies into the catcher's hands, then shakes and squashes there until its Burst (header).
-- `eye`: the camera while first person is on (the near fade), else nil.
local function stepCaught(p: Projectile, now: number, eye: Vector3?): boolean
	local caught = p.caught :: Caught
	if now > caught.burstAt + CAUGHT_GRACE then
		return false
	end
	local root, deformer = p.root, p.deformer
	if root == nil or deformer == nil or root.Parent == nil then
		return false
	end
	local hands, look = catcherHands(caught.catcherId)
	local position = ProjectileRenderer.caughtAt(caught.from, hands, os.clock() - caught.startClock)
	local scale, shake = ChargePoses.crushShape(now - caught.at, Tweens.reducedMotion())
	if shake > 0 then
		local a = shake * p.payload.radius -- crushShape's shake is in toy radii
		position += Vector3.new(random:NextNumber(-a, a), random:NextNumber(-a, a), random:NextNumber(-a, a))
	end
	root.CFrame = ProjectileRenderer.frameAt(position, look or p.lastVelocity, 0)
	deformer:setScale(scale)
	setNear(p, ProjectileRenderer.nearFadeAt(eye, position, false, 0))
	placeShadow(p, position)
	p.lastPosition = position
	p.lastScale = scale
	return true
end

local function step(dt: number, clock: number): boolean
	local now = serverNow()
	pickDetailed(clock)
	-- First person (§3.10): the near fade measures from the camera; third person has none (eye nil).
	local camera = Workspace.CurrentCamera
	local eye = if camera and FirstPersonController.isActive() then camera.CFrame.Position else nil
	for projId, p in live do
		local ok, keep = pcall(function(): boolean
			if p.impact ~= nil then
				return stepImpact(p, eye)
			elseif p.caught ~= nil then
				return stepCaught(p, now, eye) -- feature 1: no lifetime check, the Burst ends it
			end
			return stepFlight(p, now, dt, eye)
		end)
		if not ok then
			log:error(`projectile {projId} failed:`, keep)
			removeProjectile(p)
		elseif not keep then
			removeProjectile(p)
		end
	end
	return true
end

-- Remote events -----------------------------------------------------------------------------------------------------

local function onThrowStarted(raw: unknown)
	local payload = ThrowController.parseThrowStarted(raw)
	if payload == nil or live[payload.projId] ~= nil then
		return
	end
	local def = Catalog.get(payload.squishyId)
	local blueprintId = if def then def.blueprintId else payload.squishyId
	local okScale, scale = pcall(SquishyBuilder.flightScale, blueprintId, payload.radius)
	local flightScale = if okScale and type(scale) == "number" and scale > 0 then scale else 1
	local thrower = Players:GetPlayerByUserId(payload.throwerId)
	local duel = payload.kind ~= "practice"
	-- The blueprint's flight style; ReducedMotion keeps today's flightSpin (§3.2).
	local blueprint = if def then SquishyBlueprints[def.blueprintId] else nil
	local motion = if blueprint then blueprint.motion else nil
	local flight: FlightStyle? = if motion and not Tweens.reducedMotion() then motion.flight else nil
	live[payload.projId] = {
		projId = payload.projId,
		payload = payload,
		def = def,
		thrower = thrower,
		own = thrower ~= nil and thrower == Players.LocalPlayer,
		high = duel or thrower == Players.LocalPlayer,
		duel = duel,
		matchId = payload.matchId,
		flightScale = flightScale,
		poolKey = poolKeyOf(payload.squishyId, flightScale),
		spinKind = if def then def.visuals.flightSpin else "wobble",
		flight = flight,
		wantsDetail = ProjectileRenderer.wantsDetail(flight, if blueprint then blueprint.sections else nil),
		detailed = false,
		detailKey = 0,
		model = nil,
		root = nil,
		deformer = nil,
		rig = nil,
		out = nil,
		parts = {},
		highlight = nil,
		shadow = nil,
		trails = {},
		emitter = nil,
		spawned = false,
		handOffset = Vector3.zero,
		handScale = 1,
		near = 0,
		floorY = floorYFor(duel),
		impact = nil,
		contact = nil,
		lastPosition = payload.origin,
		lastVelocity = payload.velocity,
		lastScale = Vector3.one,
		power = ProjectileRenderer.powerOf(payload.power),
		caught = nil,
	}
end

local function onThrowImpact(raw: unknown)
	local impact = ThrowController.parseImpact(raw)
	if impact == nil then
		return
	end
	local p = live[impact.projId]
	if p == nil then
		return -- not ours to draw (e.g. a Dragon Rush lane, or a projectile we never saw)
	end
	stats.impacts += 1
	if not p.spawned then
		spawnVisual(p, math.max(Workspace:GetServerTimeNow() - p.payload.releaseAt, 0), impact.position)
		if p.model == nil then
			removeProjectile(p)
			return
		end
	end
	-- The hit-stop (§18.4.4): only the local victim or thrower; the projId key shares the hold with VfxController.
	local localPlayer = Players.LocalPlayer
	local localIsVictim = impact.kind == "player" and localPlayer ~= nil and impact.victimId == localPlayer.UserId
	local localIsThrower = p.thrower ~= nil and p.thrower == localPlayer
	local seconds = HitStop.secondsFor(impact.kind, impact.eliminated, localIsVictim, localIsThrower)
	local holdStart = if seconds ~= nil
		then HitStop.trigger(impact.projId, seconds, os.clock(), Tweens.reducedMotion())
		else nil
	local flash = ProjectileRenderer.impactFlashOn(impact.kind, localIsVictim, FirstPersonController.isActive())
	startImpact(p, impact.position, impact.normal, MAJOR_KINDS[impact.kind] == true, flash, holdStart)
end

-- Feature 1: a throw was caught (CatchController.Caught): its trail and specks stop and it flies into the catcher's
-- hands (stepCaught); a first-person local catcher draws it in the overlay, so the world copy goes at once.
local function onCaught(event: CatchController.Event)
	local p = live[event.projId]
	if p == nil or p.impact ~= nil or p.caught ~= nil then
		return
	end
	if not p.spawned then
		spawnVisual(p, math.max(Workspace:GetServerTimeNow() - p.payload.releaseAt, 0), event.position)
	end
	local localPlayer = Players.LocalPlayer
	local ownCatch = localPlayer ~= nil and event.catcherId == localPlayer.UserId
	if p.model == nil or (ownCatch and FirstPersonController.isActive()) then
		removeProjectile(p)
		return
	end
	setDetailed(p, false)
	p.contact = nil
	for _, trail in p.trails do
		trail.Enabled = false
	end
	local emitter = p.emitter
	if emitter then
		emitter.Enabled = false
	end
	p.caught = {
		catcherId = event.catcherId,
		at = event.at,
		burstAt = event.burstAt,
		startClock = os.clock(),
		from = p.lastPosition,
	}
	stats.caught += 1
end

-- Feature 1: the caught toy bursts (CatchController.Burst): gone (the burst's effects are VfxController's).
local function onBurst(event: CatchController.Event)
	local p = live[event.projId]
	if p ~= nil and p.impact == nil then
		removeProjectile(p)
	end
end

-- Removes the duel projectiles at a match end (ProjectileRenderer.removeOnMatchEnd), and empties the idle pool when
-- out of a match.
local function clearDuel(outOfMatch: boolean)
	for _, p in live do
		if p.duel and ProjectileRenderer.removeOnMatchEnd(p.impact ~= nil, outOfMatch) then
			removeProjectile(p)
		end
	end
	if outOfMatch then
		emptyPool()
	end
end

local function onDuelChanged(view: any, old: any)
	if view == nil then
		if old ~= nil then
			clearDuel(true)
		end
		return
	end
	if ENDED_PHASES[view.phase] or (old ~= nil and old.matchId ~= view.matchId) then
		clearDuel(false)
	end
	for _, p in live do
		if p.duel and not p.spawned then
			p.floorY = floorYFor(true)
		end
	end
end

-- Public ------------------------------------------------------------------------------------------------------------

-- Pure (unit-tested): whether a duel projectile is removed at once when the match ends. The match-ending hit's
-- ThrowImpact and DuelState(Result) arrive together, so a projectile whose splat has started finishes it (≈ 210 ms,
-- stepImpact); only the ones still in flight go. Out of a match (the view is gone: back in the lobby) everything goes.
function ProjectileRenderer.removeOnMatchEnd(impactStarted: boolean, outOfMatch: boolean): boolean
	return outOfMatch or not impactStarted
end

-- The contact-hold ray params (Default group; characters, SD_ClientFx and the Studio test dummies excluded; rebuilt at
-- most every CONTACT_REFRESH_SECONDS). SplatController's visible-surface probe uses the same exclusions (§18.4.1).
function ProjectileRenderer.contactParams(): RaycastParams
	return contactRaycastParams()
end

-- Live Highlights drawn by projectiles (VfxController keeps the client total within Config.Vfx.Budgets.highlights).
function ProjectileRenderer.highlightCount(): number
	return highlights
end

-- Feature 1: a catcher's hands in the world and where it looks (nil, nil without its root here): where its caught toy
-- is held and bursts (VfxController draws the burst there).
function ProjectileRenderer.catcherHands(catcherId: number): (Vector3?, Vector3?)
	return catcherHands(catcherId)
end

-- The last drawn position of a live projectile (nil when unknown or not drawn yet).
function ProjectileRenderer.positionOf(projId: number): Vector3?
	local p = live[projId]
	return if p and p.spawned then p.lastPosition else nil
end

-- Studio / debug counters: projectiles rendered (and detailed), pooled models, trails, highlights, live connections.
function ProjectileRenderer.counts(): { [string]: any }
	local rendered, waiting, detailed, caught = 0, 0, 0, 0
	for _, p in live do
		if p.caught ~= nil then
			caught += 1
		end
		if p.spawned then
			rendered += 1
		else
			waiting += 1
		end
		if p.detailed then
			detailed += 1
		end
	end
	local pooled, keys = 0, 0
	for _, list in idle do
		keys += 1
		pooled += #list
	end
	local connected = 0
	for _, connection in connections do
		if connection.connected then
			connected += 1
		end
	end
	return {
		rendered = rendered,
		waiting = waiting,
		detailed = detailed, -- with the pulse and flaps (spec 2026-10-09 §3.2)
		pooled = pooled,
		poolKeys = keys,
		highlights = highlights,
		trails = FxPool.default():activeCount("trail"),
		spawnedTotal = stats.spawned,
		impacts = stats.impacts,
		expired = stats.expired,
		contactHolds = stats.held,
		contactTimeouts = stats.heldTimeouts,
		modelsBuilt = stats.built,
		modelsReused = stats.reused,
		connections = connected,
		caught = caught, -- feature 1: caught toys drawn in a catcher's hands now
		caughtTotal = stats.caught,
	}
end

-- Removes every projectile and empties the pool (leak checks).
function ProjectileRenderer.clear()
	for _, p in live do
		removeProjectile(p)
	end
	emptyPool()
end

-- Lifecycle

function ProjectileRenderer.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(Scheduler.add(step, "render"))
	track(NetController.on("ThrowStarted", onThrowStarted))
	track(NetController.on("ThrowImpact", onThrowImpact))
	track(CatchController.Caught:connect(onCaught))
	track(CatchController.Burst:connect(onBurst))
	track(StateController.DuelChanged:connect(onDuelChanged))
	c:add(function()
		ProjectileRenderer.clear()
		table.clear(connections)
		contactParams = nil
		local current = folder
		folder = nil
		if current then
			current:Destroy()
		end
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function ProjectileRenderer.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return ProjectileRenderer
