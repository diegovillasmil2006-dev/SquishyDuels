--!strict
-- VfxController (client only). DESIGN §9.8, §9.9, §9.10 (world visuals), §9.12, §9.15, §18.4 (duel juice), §18.6.
-- Every effect is triggered only by the server (ThrowImpact, UltimateEvent); nothing here changes competitive state.
-- Built-in particle textures only (Config.Vfx.Textures, rbxasset:// engine files), pooled through Anim/FxPool, no
-- dynamic lights, all parts cosmetic (FxPool: CanCollide/CanQuery/CanTouch false, SD_Cosmetic).
--
-- Impacts (§9.8): "player" / "target": 14 puffs (half the thrower's squishy accent, half white) and a shockwave ring
--   (Anim/FxShapes.ring: 0 -> ringToStuds wide in 0.25 s, Transparency 0.3 -> 1) facing the normal; "geometry": 4
--   puffs in the splat colour (SplatMath.color of the accent) + 4 white (§18.4.2, Hit.geometryPuffs); "expired" /
--   "fizzle": 6 white puffs. (The projectile's own splat is ProjectileRenderer's; wall splats are SplatController's;
--   surface ripples and rings are JellyRippleController's.)
-- Hit-stop (§18.4.4, Anim/HitStop): only the local victim of a "player" impact or the local thrower (a Dragon Rush
--   lane's caster from rushProjIds) gets a hold (hit 60 ms, elimination 100 ms, practice target 40 ms for the thrower;
--   never for geometry, never for spectators, never under ReducedMotion). During the hold the victim's flinch shows at
--   full weight and the victim's flash holds at FillTransparency 0.6 (ProjectileRenderer holds the projectile's
--   contact squash). When the hold ends (HitStop.after; runDue in this module's step) the puffs and ring, the own
--   vignette, the shake, the FOV punch, the flinch kick, the held boing and the elimination sequence start. Never
--   waiting: the knockback, the sounds, the HUD, other projectiles, input and the camera.
-- FOV punch (§18.4.3, CameraController.punch): the local thrower only; hit dealt −2.5° (50 / 200 ms), elimination
--   dealt −3.5° (60 / 260 ms), practice target −1.2° (50 / 180 ms); the shake's gates (ReducedMotion, settings).
-- Victim's held squishy boing (§18.4.2; squishy overhaul spec 2026-10-09 §3.2): HeldSquishyController.react(victim,
--   "hit", 1), on every client, after the hold: the held model's own rig shows the squish face for 0.3 s and kicks its
--   feel jiggle so the squash peaks at 0.15 whatever the toy (the rig owns the ReducedMotion rule).
-- Victim, on every client: flinch spring (layer "vfxFlinch"); white hit-flash Highlight (FillTransparency 0.6 -> 1
--   over 0.15 s), then a steady ghost Highlight (white, FillTransparency 0.75, no pulse) until invulnUntil.
-- Victim, own screen: an edge vignette in the thrower's accent (<= 20% opacity, 80 ms in / 300 ms out; UIGradient
--   frames, no image), camera shake 0.5° / 200 ms (CameraController.shake; off under ReducedMotion or
--   settings.cameraShake = false), and the knockback, once, on the own HumanoidRootPart: 22 studs/s along
--   knockbackDir plus 8 up (Config.Duel.Rules.Knockback), × knockbackMultiplier (1.5) for a Dragon Rush hit.
-- Elimination (§9.9, registry by effectId: standard, epic_pending -> playStandard; Config.Anim.elimination):
--   0-150 ms big flinch + "OUT!" billboard above the head (scale pop); 150-700 ms dizzy pose with sway, the held
--   squishy wobbles; 700-1100 ms pastel foam-confetti (18 + 12 sparkles, Strawberry / Mint / Lemon), 10 tumbling
--   confetti parts (§18.4.6, Config.Vfx.Confetti: Strawberry / Mint / Lemon / Sky, never Danger; ReducedMotion 5, no
--   spin), sfx.elimination (2D for the two duelists, 3D at the victim for the rest) with the knockout duck for the two
--   duelists, and the held squishy shrinks away; at 1100 ms a white pop ring (0 -> 3 studs, 0.25 s) where it vanished.
--   The body is never faded. The held squishy comes back when the player's SD_DuelPhase is
--   Returning or "" (back in the lobby). The eliminator sees a "K.O.!" banner; the eliminated player's camera shakes
--   0.6° / 250 ms.
-- Sounds (§18.6, SoundController, silent while the slot ids are nil): sfx.impactBoing at a "player" / "target" hit,
--   sfx.impactSoft at "geometry" / "expired" / "fizzle" (the last two × softImpactMinorVolume), both on the contact
--   frame; Dragon Rush: sfx.dragonTelegraph (tracked, stopped with a trackedStopFadeMs fade on cancel), the optional
--   sfx.dragonRoar 2D for the caster and the other duelist, the "telegraph" duck for the targeted duelist while the
--   telegraph runs, sfx.throwDragon at the release, sfx.dragonChomp at E. Reading: a lane that ends on cover plays its
--   chomp, not sfx.impactSoft (one sound per action). Priorities (§18.6): impacts 2 (boing) / 1 (soft), Dragon 3;
--   another player's throw or Rush (the local player is not the thrower, the victim or the thrower's duel opponent,
--   e.g. a practice throw nearby) plays at -1, dropped first (soundPriority; reading: an unknown thrower keeps them).
-- Studio: debugJuice(name, opts) plays one juice piece locally with a fake payload and no remote (DebugHooks "juice").
-- Dragon Rush (§9.10), only from UltimateEvent numbers: telegraph = stadium indicator (rect 2R × 0.1 × length at the
--   O-E midpoint + two Ø2R cylinder caps at O and E, at floorY + 0.05, Danger at 0.35) with a fill strip growing O ->
--   E (0.6), a gentle edge pulse (off under ReducedMotion); the caster's held Dragon horns tint teal -> orange and
--   ember sparks rise at the hand. Release = the dragon_head_vfx model (Config.Vfx.DragonRush.headScale) flies O -> E
--   at `speed` with an ember trail, jaw open from 70% of the way; at E the jaw chomps (100 ms), a foam/ember puff and
--   an impact ring sized exactly to R, the indicator fades in 250 ms (transparency only increases), camera shake
--   0.8° / 260 ms within R + 10 studs of E. Cancel = "Interrupted!" over the lane, the lane fades in 200 ms, no head.
--   floorY = origin.Y - laneHeightAboveFloor (the lane height is fixed above the floor, §5.9).
-- First person (spec 2026-10-10 §3.10; FirstPersonController and Anim/NearFade by inline requires, no new top-level
--   local): no SD_HitFlash ghost on the own character while first person is on (ghostWanted: a Highlight can draw on
--   the hidden body); the local first-person victim's impact puffs and ring at a quarter (impactScale, majorBurst);
--   every Dragon Rush head fades for a first-person viewer within 4.5 studs of the camera, and the local caster's own
--   one is clear until 3 studs travelled and solid at 8 (NearFade.rushHead), as a max with the end fade, through the
--   head's kept part list (Rush.fadeHead, made once at the head's build).
-- Arena lighting (§7.4 client zone presets, §7.8 Lighting "client Arena preset"): once the duel view reaches
--   Positioning (the player is moved to the arena) Lighting.SD_Grade Contrast / Saturation and the Atmosphere Density
--   tween to Config.Vfx.ZonePresets.Arena over tweenSeconds; when the view ends (back in the lobby) they tween back to
--   the values saved on entry. Instant under ReducedMotion. Client-side only (never replicated); a missing SD_Grade
--   or Atmosphere is skipped.
-- The reticle and the attacker's hit marker are HUD: DuelController's in a duel, PracticeController's on the range
-- (ui.hitConfirm is theirs too).
-- ReducedMotion: no shake, punch, hit-stop or pulse, no scale pops, fades capped (Anim/Tweens), particle counts halved
-- (FxPool), 5 confetti parts without spin; the held boing follows the held rig's ReducedMotion rule (its squish face
-- without the jiggle). Sounds never change with ReducedMotion.
-- Highlights stay within Config.Vfx.Budgets.highlights together with ProjectileRenderer's.
-- Part 8 (layout pass, §11.2): the "K.O.!" banner (TextScaled, so it always fits) sits 30% down, or lower on a short
-- screen so it never covers the duel HUD's top bar where the opponent's life pip pops (koBannerCenterY, pure,
-- unit-tested at 667×375, 1280×720, 1920×1080 and the largest text). Reading (audited, unchanged): the hit vignette's
-- four edge bands are non-interactive (Active false) and cover 18% from each edge at <= 20% opacity, so they never
-- take a tap or hide a button.
-- Foam fix 2 (2026-10-09): koBannerUntil() is the os.clock() at which the eliminator's "K.O.!" banner has gone (from the
-- impact, counting this client's hit-stop, so it is known before the banner shows; koBannerEndsAt, pure). The duel
-- result card (DuelController) waits until then, so the banner, which draws over SD_Modal, never sits on its title.

-- Services

local Lighting = game:GetService("Lighting")
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
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local FxPool = require(Client.Anim.FxPool)
local FxShapes = require(Client.Anim.FxShapes)
local HitStop = require(Client.Anim.HitStop)
local Scheduler = require(Client.Anim.Scheduler)
local SplatMath = require(Client.Anim.SplatMath)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local Tweens = require(Client.Anim.Tweens)
local SquishyCache = require(Client.Models.SquishyCache)
local CameraController = require(script.Parent.CameraController)
local CharacterAnimController = require(script.Parent.CharacterAnimController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local NetController = require(script.Parent.NetController)
local ProjectileRenderer = require(script.Parent.ProjectileRenderer)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)

-- Types

-- One part of the Dragon Rush indicator: its frame and size (cylinder caps lie on their side: axis = world up).
export type PartSpec = { cframe: CFrame, size: Vector3 }
export type RushIndicator = {
	rect: PartSpec,
	capO: PartSpec,
	capE: PartSpec,
	floorY: number,
	endpoint: Vector3, -- E at lane height
	midpoint: Vector3, -- on the floor
	dir: Vector3, -- flat unit direction
}

type Effect = {
	step: (dt: number, now: number) -> boolean, -- now = server time; false = done
	stop: () -> (),
}

type ProjInfo = { squishyId: string, throwerId: number, untilAt: number }

type Rush = {
	casterId: number,
	indicator: RushIndicator,
	parts: { BasePart }, -- rect, capO, capE
	fill: BasePart,
	telegraphEndsAt: number,
	telegraphStart: number,
	speed: number,
	length: number,
	origin: Vector3,
	phase: "telegraph" | "release" | "fade",
	head: Model?,
	headDeformer: SquishDeformer.Deformer?,
	-- Writes the head's LocalTransparencyModifier from its end fade (spec 2026-10-10 §3.10); made at the head's build.
	fadeHead: ((endFade: number) -> ())?,
	jaw: { weld: Weld, base: CFrame, hinge: Vector3 }?,
	headEmitter: ParticleEmitter?,
	sparks: ParticleEmitter?,
	horns: { { part: BasePart, color: Color3 } },
	arrivedAt: number?, -- server time the head reached E
	fadeStart: number?, -- os.clock()
	fadeSeconds: number,
	label: BillboardGui?,
	telegraphStop: ((fadeMs: number?) -> ())?, -- the tracked telegraph sound
	duckRelease: (() -> ())?, -- the "telegraph" music duck (targeted duelist only)
}

type Ghost = {
	player: Player,
	highlight: Highlight,
	flashStart: number, -- os.clock()
	held: boolean, -- the flash reads HitStop.elapsed (this client holds the hit)
	invulnUntil: number, -- server time
}

type Eliminated = { player: Player, restored: boolean }

-- The lighting values a zone preset sets (nil = that instance is missing).
export type LightingValues = { contrast: number?, saturation: number?, density: number? }

-- One FOV punch (Config.Vfx.Punch.*).
export type PunchSpec = { fovDeg: number, attackMs: number, releaseMs: number }

-- What this client adds to an impact (hitJuice): the hit-stop hold, the attacker's punch, who is involved.
export type HitJuice = {
	stopSeconds: number?,
	punch: PunchSpec?,
	localIsVictim: boolean,
	localIsThrower: boolean,
}

-- One puff burst of a geometry impact: `count` puffs in `color`.
export type PuffSpec = { color: Color3, count: number }

-- One elimination confetti part at its launch (confettiLaunch).
export type ConfettiPiece = {
	velocity: Vector3, -- studs/s
	axis: Vector3, -- spin axis (unit)
	spinDeg: number, -- °/s (0 under ReducedMotion)
	color: Color3,
}

-- A Studio juice piece another controller adds (SplatController's "splat").
export type JuiceHook = (opts: { [string]: any }?) -> (boolean, string?)

-- Constants

local VFX = Config.Vfx
local HIT = VFX.Hit
local SHAKE = VFX.Shake
local RUSH_VFX = VFX.DragonRush
local ELIM = Config.Anim.elimination
local KNOCKBACK = Config.Duel.Rules.Knockback
local RUSH = Config.Abilities.dragon_rush
local TEXTURES = VFX.Textures
local LAYER_FLINCH = "vfxFlinch"
local LAYER_DIZZY = "vfxDizzy"
local OVERLAY_ELIMINATED = "eliminated"
local HIDE_ELIMINATED = "eliminated"
local ATTR_DUEL_PHASE = "SD_DuelPhase"
local GUI_NAME = "SD_Vfx"
-- reading (not in DESIGN, provisional): the vignette / K.O. ScreenGui sits just under SD_Overlay (30).
local GUI_DISPLAY_ORDER = 29
local MAJOR_KINDS: { [string]: boolean } = { player = true, target = true }
local ENDED_PHASES: { [string]: boolean } = { Result = true, Returning = true, Cancelled = true, Void = true }
local ZONE_PRESETS = VFX.ZonePresets
local GRADE_NAME = "SD_Grade" -- the ColorCorrectionEffect default.project.json puts under Lighting (§7.4)
-- reading: puffs sit this far off the hit surface (rings too, in FxShapes).
local SURFACE_LIFT = 0.05
-- Feel pass (§18.4, §18.6).
local HIT_STOP = VFX.HitStop
local PUNCH = VFX.Punch
local CONFETTI = VFX.Confetti
local AUDIO = Config.Audio
local CONFETTI_PART_COLORS = { Palette.Strawberry, Palette.Mint, Palette.Lemon, Palette.Sky }
local REDUCED_CONFETTI_PARTS = 5 -- §18.1: ReducedMotion keeps 5 pieces, no spin
local SOUND_BOING = "sfx.impactBoing"
local SOUND_SOFT = "sfx.impactSoft"
local SOUND_ELIMINATION = "sfx.elimination"
local SOUND_TELEGRAPH = "sfx.dragonTelegraph"
local SOUND_ROAR = "sfx.dragonRoar"
local SOUND_RUSH_RELEASE = "sfx.throwDragon"
local SOUND_CHOMP = "sfx.dragonChomp"
local SOFT_MINOR_KINDS: { [string]: boolean } = { expired = true, fizzle = true }
-- Sound priorities (§18.6): 1 own sounds, 2 hit cues, 3 big moments; other players' sounds -1 (dropped first).
local SOFT_PRIORITY = 1
local BOING_PRIORITY = 2
local BIG_PRIORITY = 3
local OTHER_SOUND_PRIORITY = -1
-- reading: puff look (smoke texture), lifetimes inside the §9.15 impact budget.
local PUFF_LIFETIME = NumberRange.new(0.3, 0.45)
local PUFF_SPEED = NumberRange.new(4, 7)
local PUFF_SIZE = NumberSequence.new(0.45, 0)
local MINOR_PUFF_LIFETIME = NumberRange.new(0.15, HIT.minorFadeMs / 1000)
-- Victim highlights (§9.8).
local GHOST_COLOR = Palette.White
local FLASH_S = HIT.flashSeconds
-- reading: the vignette's gradient covers this fraction of the screen from each edge.
local VIGNETTE_DEPTH = 0.18
-- Elimination phases (§9.9, ms).
local ELIM_FLINCH_S = ELIM.flinchEndMs / 1000
local ELIM_DIZZY_S = ELIM.dizzyEndMs / 1000
local ELIM_END_S = ELIM.endMs / 1000
-- reading: the dizzy pose blends in and out over this long.
local DIZZY_BLEND_S = 0.1
-- reading: the "OUT!" / "K.O.!" texts stay this long, then fade.
local OUT_LABEL_S = 1.6
local KO_BANNER_S = 1.2
-- Part 8 (readings: the banner's look as built, 50% × 12% of the screen, 30% down; its place keeps the duel HUD's top
-- bar clear, VfxController.koBannerCenterY). The bar is DuelController's SD_DuelHud.TopBar (stable names).
local KO_BANNER_WIDTH = 0.5
local KO_BANNER_HEIGHT = 0.12
local KO_BANNER_Y = 0.3
local KO_BANNER_GAP_PX = 8
local KO_BANNER_EDGE_PX = 12
local DUEL_HUD_GUI = "SD_DuelHud"
local DUEL_TOP_BAR = "TopBar"
local POP_FROM = 1.3
local POP_MS = 250
-- reading: the held squishy's wobble while dizzy (scale amplitude, Hz).
local WOBBLE_AMP = 0.08
local WOBBLE_HZ = 4
local CONFETTI_COLORS = { Palette.Strawberry, Palette.Mint, Palette.Lemon }
-- Dragon Rush.
local HORN_PREFIX = "Horn"
local HORN_HOT = Color3.fromHex("#FF9F1C") -- reading: the "orange" of §9.10 = the Exclusive rarity orange
local FILL_WIDTH_FRACTION = 0.6 -- reading: the progress strip is narrower than the lane so the Danger edge shows
local FILL_LIFT = 0.02
local PULSE_HZ = 2 -- reading: <= 3 Hz flash rule (§9.12)
local PULSE_AMPLITUDE = 0.12
local JAW_OPEN_DEG = -30 -- reading: the lower jaw opens 30° (front down) from 70% of the way
local JAW_OPEN_FROM = 0.5 -- reading: it starts opening here and is fully open at jawOpenAt
local HEAD_LINGER_S = 0.15 -- reading: the head stays at E this long after the chomp
local HEAD_TRAIL_RATE = 40 -- reading: ember trail particles per second (inside the 60-particle Rush budget)
local IMPACT_PUFFS = 15 -- reading: foam + embers at E (15 each), and 30 embers at the release (§9.10)
local RING_SECONDS = HIT.ringSeconds

-- Module table

local VfxController = {}

-- Fired with (victimId, attackerId?) when an elimination effect starts (tests, debug).
VfxController.Eliminated = Signal.new() :: Signal.Signal<number, number?>

-- Private

local log = Log.new("Vfx")
local cleanup: Cleanup.Cleanup? = nil
local effects: { Effect } = {}
local projectiles: { [number]: ProjInfo } = {}
local rushProjIds: { [number]: ProjInfo } = {} -- Dragon Rush lane projId -> caster (squishyId unused)
local rushes: { [number]: Rush } = {} -- by casterId
local ghosts: { [Player]: Ghost } = {}
local eliminated: { [Player]: Eliminated } = {}
local gui: ScreenGui? = nil
local vignette: { Frame }? = nil
local connections: { Signal.Connection } = {}
local stats = {
	impacts = 0,
	hits = 0,
	eliminations = 0,
	rushes = 0,
	knockbacks = 0,
	holds = 0,
	punches = 0,
	confettiParts = 0,
}
local savedLighting: LightingValues? = nil -- the lobby values, saved on arena entry
local lightingTweens: { Tween } = {}
local heldFlinches: { [Player]: boolean } = {} -- flinch pose held at full weight until the hold ends
local juiceHooks: { [string]: JuiceHook } = {}
local debugSerial = 0
local koUntil = 0 -- foam fix 2: os.clock() when the "K.O.!" banner shown or on its way has gone (0 = none)

-- Pure helpers ------------------------------------------------------------------------------------------------------

-- The Dragon Rush stadium indicator from the UltimateEvent numbers (§9.10): a flat rect 2R wide and `length` long
-- centred on the O-E midpoint, plus Ø2R cylinder caps at O and E, at floorY + indicatorYOffset.
function VfxController.rushIndicator(
	origin: Vector3,
	dir: Vector3,
	length: number,
	radius: number,
	laneHeight: number?
): RushIndicator
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local unit = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(0, 0, -1)
	local floorY = origin.Y - (laneHeight or RUSH.laneHeightAboveFloor)
	local y = floorY + RUSH_VFX.indicatorYOffset
	local o = Vector3.new(origin.X, y, origin.Z)
	local e = o + unit * length
	local mid = (o + e) / 2
	local width = 2 * radius
	local function cap(at: Vector3): PartSpec
		return { cframe = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2), size = Vector3.new(0.1, width, width) }
	end
	return {
		rect = { cframe = CFrame.lookAt(mid, mid + unit), size = Vector3.new(width, 0.1, math.max(length, 0.05)) },
		capO = cap(o),
		capE = cap(e),
		floorY = floorY,
		endpoint = origin + unit * length,
		midpoint = mid,
		dir = unit,
	}
end

-- Dragon head position `elapsed` seconds after the release: O -> E at `speed`, stopping at E. Returns the position
-- and the fraction of the way (0..1).
function VfxController.rushHeadAt(
	origin: Vector3,
	dir: Vector3,
	length: number,
	speed: number,
	elapsed: number
): (Vector3, number)
	local travelled = math.clamp(speed * math.max(elapsed, 0), 0, math.max(length, 0))
	local fraction = if length > 1e-6 then travelled / length else 1
	return origin + dir * travelled, fraction
end

-- Lower jaw angle (degrees, negative = open) at a fraction of the way; closed again (chomp) chompElapsed seconds
-- after the arrival.
function VfxController.jawAngle(fraction: number, chompElapsed: number?): number
	if chompElapsed ~= nil then
		local u = math.clamp(chompElapsed / (RUSH_VFX.jawChompMs / 1000), 0, 1)
		return JAW_OPEN_DEG * (1 - u)
	end
	local open = RUSH_VFX.jawOpenAt
	local u = math.clamp((fraction - JAW_OPEN_FROM) / math.max(open - JAW_OPEN_FROM, 1e-3), 0, 1)
	return JAW_OPEN_DEG * u
end

-- Knockback velocity for a victim (§5.2): horizontal along the flattened direction, plus vertical, × multiplier.
function VfxController.knockbackVelocity(direction: Vector3, multiplier: number): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local unit = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.zero
	return unit * KNOCKBACK.Horizontal * multiplier + Vector3.new(0, KNOCKBACK.Vertical * multiplier, 0)
end

-- The elimination effect for an effectId (registry, §9.9); unknown ids play the standard one.
function VfxController.eliminationEffect(effectId: string?): string
	if effectId == "epic_pending" and not ELIM.epicEnabled then
		return "standard"
	end
	if effectId == "standard" or effectId == "epic_pending" then
		return effectId :: string
	end
	return "standard"
end

-- True when the duel view calls for the Arena lighting preset: the match reached Positioning (the player was moved
-- to the arena) and the view still exists (it ends back in the lobby).
function VfxController.arenaLightingWanted(view: any): boolean
	return type(view) == "table" and view.positioned == true
end

-- The lighting goals for a zone change: the Arena preset on entry, else the values saved on entry (nil = nothing to
-- restore).
function VfxController.lightingGoals(inArena: boolean, saved: LightingValues?): LightingValues?
	if inArena then
		local arena = ZONE_PRESETS.Arena
		return { contrast = arena.contrast, saturation = arena.saturation, density = arena.atmosphereDensity }
	end
	return saved
end

-- Who gets the duel juice of an impact on this client (§18.4.3, §18.4.4): the hit-stop for the local victim of a
-- "player" impact or the local thrower (hit 0.06 s, elimination 0.10 s; a practice "target": the thrower, 0.04 s),
-- never for geometry or spectators, never under ReducedMotion; the FOV punch for the local thrower only (hit dealt,
-- elimination dealt, practice target), off under ReducedMotion or with the camera shake setting off.
function VfxController.hitJuice(
	kind: string,
	eliminated: boolean?,
	localId: number?,
	victimId: number?,
	throwerId: number?,
	isReduced: boolean?,
	shakeOn: boolean?
): HitJuice
	local localIsVictim = kind == "player" and localId ~= nil and victimId == localId
	local localIsThrower = localId ~= nil and throwerId == localId and not localIsVictim
	local stopSeconds = if isReduced == true
		then nil
		else HitStop.secondsFor(kind, eliminated, localIsVictim, localIsThrower)
	local punch: PunchSpec? = nil
	if localIsThrower and isReduced ~= true and shakeOn ~= false then
		if kind == "player" then
			punch = if eliminated == true then PUNCH.elimDealt else PUNCH.hitDealt
		elseif kind == "target" then
			punch = PUNCH.practiceHit
		end
	end
	return {
		stopSeconds = stopSeconds,
		punch = punch,
		localIsVictim = localIsVictim,
		localIsThrower = localIsThrower,
	}
end

-- The puffs of a "geometry" impact (§18.4.2): Hit.geometryPuffs.accent in the splat colour of the thrower's accent
-- (SplatMath.color: whitened, never red) plus Hit.geometryPuffs.white in white.
function VfxController.geometryPuffs(accent: Color3): { PuffSpec }
	return {
		{ color = SplatMath.color(accent), count = HIT.geometryPuffs.accent },
		{ color = Palette.White, count = HIT.geometryPuffs.white },
	}
end

-- The elimination confetti parts at their launch (§18.4.6, Config.Vfx.Confetti), from `rng` (a Random): up upMin-upMax
-- plus outward outMin-outMax studs/s in a random heading, a random spin axis at spinMinDeg-spinMaxDeg °/s, colours
-- Strawberry / Mint / Lemon / Sky in turn (never Danger). ReducedMotion: 5 pieces, no spin.
function VfxController.confettiLaunch(rng: Random, isReduced: boolean?): { ConfettiPiece }
	local count = if isReduced == true then math.min(REDUCED_CONFETTI_PARTS, CONFETTI.parts) else CONFETTI.parts
	local pieces: { ConfettiPiece } = {}
	for index = 1, count do
		local heading = rng:NextNumber(0, 2 * math.pi)
		local out = rng:NextNumber(CONFETTI.outMin, CONFETTI.outMax)
		local up = rng:NextNumber(CONFETTI.upMin, CONFETTI.upMax)
		local axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
		table.insert(pieces, {
			velocity = Vector3.new(math.cos(heading) * out, up, math.sin(heading) * out),
			axis = if axis.Magnitude > 1e-3 then axis.Unit else Vector3.yAxis,
			spinDeg = if isReduced == true then 0 else rng:NextNumber(CONFETTI.spinMinDeg, CONFETTI.spinMaxDeg),
			color = CONFETTI_PART_COLORS[(index - 1) % #CONFETTI_PART_COLORS + 1],
		})
	end
	return pieces
end

-- One confetti step of dt seconds: drag e^(-dragPerSecond · dt), then gravity, then the move. Returns the new position
-- and velocity.
function VfxController.confettiStep(position: Vector3, velocity: Vector3, dt: number): (Vector3, Vector3)
	local v = velocity * math.exp(-CONFETTI.dragPerSecond * dt) - Vector3.new(0, CONFETTI.gravity * dt, 0)
	return position + v * dt, v
end

-- A confetti part's Transparency `t` seconds after its launch: 0, then -> 1 over the last fadeSeconds of its lifetime.
-- The second value is true once its lifetime is over.
function VfxController.confettiTransparency(t: number): (number, boolean)
	local fade = math.max(CONFETTI.fadeSeconds, 1e-3)
	return math.clamp((t - (CONFETTI.lifetime - fade)) / fade, 0, 1), t >= CONFETTI.lifetime
end

-- Who hears what of a Dragon Rush telegraph (§18.6): the optional roar (2D) for the caster and the other duelist; the
-- "telegraph" music duck only for the targeted duelist (the local player's duel opponent is the caster).
function VfxController.rushListener(casterId: number, localId: number?, opponentId: number?): (boolean, boolean)
	local isCaster = localId ~= nil and casterId == localId
	local targeted = not isCaster and opponentId ~= nil and opponentId == casterId
	return isCaster or targeted, targeted
end

-- The priority of an impact or Dragon Rush sound on this client (§18.6): `base` when the local player is involved
-- (the thrower or caster, the victim, or the thrower is the local player's duel opponent), else -1 (another player's
-- sound, dropped first). Reading: an unknown thrower or local player keeps `base`.
function VfxController.soundPriority(
	base: number,
	throwerId: number?,
	victimId: number?,
	localId: number?,
	opponentId: number?
): number
	if throwerId == nil or localId == nil then
		return base
	elseif throwerId == localId or victimId == localId or (opponentId ~= nil and throwerId == opponentId) then
		return base
	end
	return OTHER_SOUND_PRIORITY
end

-- Part 8 (§11.2): the "K.O.!" banner's centre (px from the top of SD_Vfx, a full-bleed gui without UIScale) on a
-- screen `screenHeight` tall. The banner is KO_BANNER_HEIGHT of the screen tall and sits KO_BANNER_Y down, or lower so
-- that even at its pop (POP_FROM) it starts KO_BANNER_GAP_PX under `barBottom` (the duel HUD's top bar's bottom in the
-- same px; nil = no bar on screen), so the opponent's lives stay visible as one pops; never past KO_BANNER_EDGE_PX
-- from the bottom (then the bar is left behind it, as before).
function VfxController.koBannerCenterY(screenHeight: number, barBottom: number?): number
	local h = if screenHeight == screenHeight and screenHeight > 0 and screenHeight < math.huge then screenHeight else 0
	local half = h * KO_BANNER_HEIGHT * POP_FROM / 2
	local y = h * KO_BANNER_Y
	if barBottom and barBottom == barBottom and math.abs(barBottom) < math.huge then
		y = math.max(y, barBottom + KO_BANNER_GAP_PX + half)
	end
	return math.max(h * KO_BANNER_Y, math.min(y, h - KO_BANNER_EDGE_PX - half))
end

-- Foam fix 2: the os.clock() at which a "K.O.!" banner has gone when it shows after a hit-stop of `holdSeconds` (nil,
-- negative or bad = none) from `clock`.
function VfxController.koBannerEndsAt(clock: number, holdSeconds: number?): number
	local hold = holdSeconds
	local wait = if hold and hold == hold and hold > 0 and hold < math.huge then hold else 0
	return clock + wait + KO_BANNER_S
end

-- Foam fix 2: the os.clock() at which the eliminator's "K.O.!" banner (showing, or waiting for this client's hit-stop)
-- has gone; 0 when there is none. DuelController holds the result card until then.
function VfxController.koBannerUntil(): number
	return koUntil
end

-- First person (spec 2026-10-10 §3.10): whether a hit puts the white SD_HitFlash ghost on the victim. Not on the own
-- character in first person: a Highlight can still draw on a body hidden by LocalTransparencyModifier (a white body
-- when you look down); the hand in the overlay shows the safe time instead (ViewmodelController).
function VfxController.ghostWanted(victimIsLocal: boolean, firstPerson: boolean): boolean
	return not (victimIsLocal and firstPerson)
end

-- First person (§3.10): the size of a "player" / "target" impact burst on this client. The local first-person victim's
-- lands 2-3 studs from the eyes: Config.FirstPerson.victimImpactScale (a quarter); everyone else's 1.
function VfxController.impactScale(localIsVictim: boolean, firstPerson: boolean): number
	return if localIsVictim and firstPerson then Config.FirstPerson.victimImpactScale else 1
end

-- The "player" / "target" impact burst at `scale` (§9.8): the accent and white puff counts (Hit.puffs × scale,
-- rounded, at least one of each) and the shockwave ring's width (Hit.ringToStuds × scale). Scale 1 is the full burst.
function VfxController.majorBurst(scale: number): (number, number, number)
	local total = math.max(math.floor(HIT.puffs * scale + 0.5), 2)
	local accent = math.floor(total / 2)
	return accent, total - accent, HIT.ringToStuds * scale
end

-- Runtime helpers ---------------------------------------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function reduced(): boolean
	return Tweens.reducedMotion()
end

local function text(key: string, args: { [string]: any }?): string
	local template = Strings.resolve(key)
	return if template then Strings.format(template, args) else ""
end

local function track(connection: Signal.Connection)
	table.insert(connections, connection)
	local c = cleanup
	if c then
		c:add(connection)
	end
end

local function addEffect(effect: Effect)
	table.insert(effects, effect)
end

local function accentOf(squishyId: string?): Color3
	local def = if squishyId then Catalog.get(squishyId) else nil
	return if def then Color3.fromHex(def.visuals.accent) else Palette.White
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The settings gate the shake and the FOV punch share (§9.12, §18.4.3).
local function shakeEnabled(): boolean
	local settings = StateController.get("settings")
	return not (type(settings) == "table" and settings.cameraShake == false)
end

local function shake(spec: { amplitudeDeg: number, ms: number })
	if reduced() or not shakeEnabled() then
		return
	end
	local ok, err = pcall(CameraController.shake, math.min(spec.amplitudeDeg, SHAKE.maxAmplitudeDeg), spec.ms / 1000)
	if not ok then
		log:warn("camera shake failed:", err)
	end
end

local function highlightRoom(): boolean
	local ours = 0
	for _ in ghosts do
		ours += 1
	end
	return ProjectileRenderer.highlightCount() + ours < VFX.Budgets.highlights
end

local function ensureGui(): ScreenGui?
	local current = gui
	if current and current.Parent ~= nil then
		return current
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = GUI_NAME
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = GUI_DISPLAY_ORDER
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.Parent = playerGui
	gui = screen
	vignette = nil
	return screen
end

-- Four edge frames whose UIGradient goes from opaque at the screen edge to clear inward. The side frames span only
-- between the top and bottom bands, so no corner is covered twice (opacity stays <= vignetteMaxOpacity everywhere).
local function ensureVignette(): { Frame }?
	local frames = vignette
	if frames then
		return frames
	end
	local screen = ensureGui()
	if screen == nil then
		return nil
	end
	local made: { Frame } = {}
	local middle = 1 - 2 * VIGNETTE_DEPTH
	local specs = {
		{ pos = UDim2.fromScale(0, 0), size = UDim2.fromScale(1, VIGNETTE_DEPTH), rotation = 90 }, -- top
		{ pos = UDim2.fromScale(0, 1 - VIGNETTE_DEPTH), size = UDim2.fromScale(1, VIGNETTE_DEPTH), rotation = -90 },
		{ pos = UDim2.fromScale(0, VIGNETTE_DEPTH), size = UDim2.fromScale(VIGNETTE_DEPTH, middle), rotation = 0 }, -- left
		{
			pos = UDim2.fromScale(1 - VIGNETTE_DEPTH, VIGNETTE_DEPTH),
			size = UDim2.fromScale(VIGNETTE_DEPTH, middle),
			rotation = 180,
		},
	}
	for index, spec in specs do
		local frame = Instance.new("Frame")
		frame.Name = "Vignette" .. index
		frame.Position = spec.pos
		frame.Size = spec.size
		frame.BorderSizePixel = 0
		frame.BackgroundTransparency = 1
		frame.Active = false
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = spec.rotation
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = frame
		frame.Parent = screen
		table.insert(made, frame)
	end
	vignette = made
	return made
end

local function playVignette(color: Color3)
	local frames = ensureVignette()
	if frames == nil then
		return
	end
	local peak = 1 - math.min(HIT.vignetteMaxOpacity, VFX.Flash.maxOverlayOpacity)
	local inMs = math.max(HIT.vignetteInMs, VFX.Flash.minPeakMs)
	for _, frame in frames do
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 1
		local tweenIn = Tweens.fade(frame, { BackgroundTransparency = peak }, inMs)
		local connection: RBXScriptConnection
		connection = tweenIn.Completed:Connect(function()
			connection:Disconnect()
			if frame.Parent ~= nil then
				Tweens.fade(frame, { BackgroundTransparency = 1 }, HIT.vignetteOutMs)
			end
		end)
	end
end

local function particleProps(color: Color3, lifetime: NumberRange?, texture: string?): FxPool.Props
	return {
		Texture = texture or TEXTURES.smoke,
		Lifetime = lifetime or PUFF_LIFETIME,
		Speed = PUFF_SPEED,
		SpreadAngle = Vector2.new(180, 180),
		Size = PUFF_SIZE,
		Color = ColorSequence.new(color),
		LightEmission = 0,
	}
end

-- A flat ring (Anim/FxShapes: a pooled flat ellipsoid on its own Scheduler effect) at `position` with its thin axis
-- along `normal`, growing 0 -> diameter while it fades from transparencyFrom (default ringTransparencyFrom) to 1 over
-- `seconds`. Tracked here as an effect, so clear() stops this module's rings (and no one else's).
local function ring(
	position: Vector3,
	normal: Vector3,
	diameter: number,
	seconds: number,
	color: Color3,
	transparencyFrom: number?
)
	local shape = FxShapes.ring(position, normal, diameter, seconds, color, transparencyFrom)
	addEffect({
		step = function(_dt: number, _now: number): boolean
			return not shape.done
		end,
		stop = function()
			shape:stop()
		end,
	})
end

local function playSound(key: string, options: SoundController.PlayOptions?)
	local ok, err = pcall(SoundController.play, key, options)
	if not ok then
		log:warn(`sound {key} failed:`, err)
	end
end

-- The local player's duel opponent (nil outside a duel).
local function opponentUserId(): number?
	local view = StateController.duel()
	return if view and view.opponent then view.opponent.userId else nil
end

-- This client's priority for a sound of `throwerId`'s throw or Rush (soundPriority).
local function soundPriorityFor(base: number, throwerId: number?, victimId: number?): number
	local localPlayer = Players.LocalPlayer
	local localId = if localPlayer then localPlayer.UserId else nil
	return VfxController.soundPriority(base, throwerId, victimId, localId, opponentUserId())
end

local function punchCamera(spec: PunchSpec)
	if reduced() or not shakeEnabled() then
		return
	end
	local ok, started = pcall(CameraController.punch, spec.fovDeg, spec.attackMs, spec.releaseMs)
	if not ok then
		log:warn("FOV punch failed:", started)
	elseif started == true then
		stats.punches += 1
	end
end

-- Impacts and hits --------------------------------------------------------------------------------------------------

-- `scale`: the major burst's size on this client (impactScale: a quarter for the local first-person victim).
local function impactBurst(impact: Types.ThrowImpactPayload, accent: Color3, scale: number)
	local pool = FxPool.default()
	local normal = impact.normal or Vector3.yAxis
	local at = impact.position + normal * SURFACE_LIFT
	if MAJOR_KINDS[impact.kind] then
		local accentPuffs, whitePuffs, ringStuds = VfxController.majorBurst(scale)
		pool:emit(at, accentPuffs, particleProps(accent))
		pool:emit(at, whitePuffs, particleProps(Palette.White))
		ring(impact.position, normal, ringStuds, RING_SECONDS, Palette.White)
	elseif impact.kind == "geometry" then
		for _, puff in VfxController.geometryPuffs(accent) do
			pool:emit(at, puff.count, particleProps(puff.color, MINOR_PUFF_LIFETIME))
		end
	else
		pool:emit(at, HIT.minorPuffs, particleProps(Palette.White, MINOR_PUFF_LIFETIME))
	end
end

-- The impact sound, on the contact frame (§18.6): a boing for "player" / "target", a soft thud for the rest (expired
-- and fizzle quieter); another player's throw at -1 (soundPriority). A Dragon Rush lane's end plays its chomp instead
-- (arriveRush).
local function impactSound(impact: Types.ThrowImpactPayload, lane: boolean, throwerId: number?)
	local victimId = if type(impact.victimId) == "number" then impact.victimId :: number else nil
	if MAJOR_KINDS[impact.kind] then
		local priority = soundPriorityFor(BOING_PRIORITY, throwerId, victimId)
		playSound(SOUND_BOING, { at = impact.position, priority = priority })
	elseif not lane then
		local volume = if SOFT_MINOR_KINDS[impact.kind] then AUDIO.softImpactMinorVolume else nil
		local priority = soundPriorityFor(SOFT_PRIORITY, throwerId, victimId)
		playSound(SOUND_SOFT, { at = impact.position, priority = priority, volume = volume })
	end
end

local function flinch(player: Player, amount: number?)
	local layer = CharacterAnimController.getLayer(player)
	if layer then
		local ok, err = pcall(function()
			layer:kick(LAYER_FLINCH, "flinch", amount)
		end)
		if not ok then
			log:warn("flinch failed:", err)
		end
	end
end

-- During a hit-stop the victim's flinch shows at full weight (a plain pose layer); the kick replaces it at the end.
local function holdFlinch(player: Player)
	local layer = CharacterAnimController.getLayer(player)
	if layer == nil then
		return
	end
	local ok, err = pcall(function()
		layer:setPose(LAYER_FLINCH, "flinch", 1)
	end)
	if ok then
		heldFlinches[player] = true
	else
		log:warn("flinch hold failed:", err)
	end
end

local function releaseHeldFlinch(player: Player, kick: boolean)
	if not heldFlinches[player] then
		return
	end
	heldFlinches[player] = nil
	if kick then
		flinch(player, 1)
		return
	end
	local layer = CharacterAnimController.getLayer(player)
	if layer and layer:has(LAYER_FLINCH) then
		layer:clear(LAYER_FLINCH)
	end
end

local function removeGhost(player: Player)
	local ghost = ghosts[player]
	if ghost then
		ghosts[player] = nil
		ghost.highlight:Destroy()
	end
end

local function showGhost(player: Player, invulnUntil: number, held: boolean)
	local character = player.Character
	if character == nil then
		return
	end
	local ghost = ghosts[player]
	if ghost == nil then
		if not highlightRoom() then
			return
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = "SD_HitFlash"
		highlight.FillColor = GHOST_COLOR
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillTransparency = HIT.flashFillFrom
		highlight.Adornee = character
		highlight.Parent = character
		ghost = {
			player = player,
			highlight = highlight,
			flashStart = os.clock(),
			held = held,
			invulnUntil = invulnUntil,
		}
		ghosts[player] = ghost
	else
		ghost.flashStart = os.clock()
		ghost.held = held
		ghost.invulnUntil = invulnUntil
		ghost.highlight.Adornee = character
		if ghost.highlight.Parent ~= character then
			ghost.highlight.Parent = character
		end
	end
end

local function stepGhosts(now: number)
	for player, ghost in ghosts do
		local highlight = ghost.highlight
		if highlight.Parent == nil or player.Parent == nil then
			ghosts[player] = nil
			highlight:Destroy()
			continue
		end
		-- A held hit keeps its flash at FillTransparency 0.6 for the whole hold (§18.4.4).
		local t = if ghost.held then HitStop.elapsed(ghost.flashStart, os.clock()) else os.clock() - ghost.flashStart
		if t < FLASH_S then
			-- Hit flash: 0.6 -> 1 over 0.15 s.
			highlight.FillTransparency = HIT.flashFillFrom + (1 - HIT.flashFillFrom) * (t / FLASH_S)
		elseif now < ghost.invulnUntil then
			highlight.FillTransparency = HIT.invulnFillTransparency
		else
			removeGhost(player)
		end
	end
end

local function applyKnockback(impact: Types.ThrowImpactPayload, multiplier: number)
	local player = Players.LocalPlayer
	local root = rootOf(player)
	if root == nil then
		return
	end
	local direction = impact.knockbackDir or (root.Position - impact.position)
	local push = VfxController.knockbackVelocity(direction, multiplier)
	local current = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(push.X, math.max(current.Y, 0) + push.Y, push.Z)
	stats.knockbacks += 1
end

-- Elimination -------------------------------------------------------------------------------------------------------

local function billboardText(adornee: BasePart, label: string, color: Color3, lifetime: number)
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local board = Instance.new("BillboardGui")
	board.Name = "SD_VfxText"
	board.Adornee = adornee
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.Size = UDim2.fromScale(5, 1.8)
	board.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	board.ResetOnSpawn = false
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	textLabel.TextScaled = true
	textLabel.TextColor3 = color
	textLabel.Text = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.Ink
	stroke.Thickness = 3
	stroke.Parent = textLabel
	local scale = Instance.new("UIScale")
	scale.Parent = textLabel
	textLabel.Parent = board
	board.Parent = playerGui
	Tweens.scale(
		scale,
		POP_FROM,
		1,
		{ ms = POP_MS, style = Enum.EasingStyle.Back, direction = Enum.EasingDirection.Out }
	)
	local started = os.clock()
	local done = false
	addEffect({
		step = function(_dt: number, _now: number): boolean
			if done then
				return false
			end
			local t = os.clock() - started
			if t >= lifetime then
				done = true
				board:Destroy()
				return false
			end
			local fadeFrom = lifetime * 0.75
			if t > fadeFrom then
				local u = (t - fadeFrom) / (lifetime - fadeFrom)
				textLabel.TextTransparency = u
				stroke.Transparency = u
			end
			return true
		end,
		stop = function()
			if not done then
				done = true
				board:Destroy()
			end
		end,
	})
end

-- The bottom of the duel HUD's top bar in `screen`'s px (both guis' AbsolutePositions share one space), or nil while
-- it is not on screen.
local function duelBarBottom(screen: ScreenGui): number?
	local playerGui = screen.Parent
	local hud = playerGui and playerGui:FindFirstChild(DUEL_HUD_GUI)
	if hud == nil or not hud:IsA("ScreenGui") or not hud.Enabled then
		return nil
	end
	local bar = hud:FindFirstChild(DUEL_TOP_BAR)
	if bar == nil or not bar:IsA("GuiObject") or not bar.Visible or bar.AbsoluteSize.Y <= 0 then
		return nil
	end
	return bar.AbsolutePosition.Y + bar.AbsoluteSize.Y - screen.AbsolutePosition.Y
end

local function koBanner()
	local screen = ensureGui()
	if screen == nil then
		koUntil = 0
		return
	end
	koUntil = VfxController.koBannerEndsAt(os.clock(), nil)
	local label = Instance.new("TextLabel")
	label.Name = "Vfx_KoBanner"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Part 8: under the duel HUD's top bar on a short screen (VfxController.koBannerCenterY), 30% down otherwise (also
	-- while the gui has no size yet, just made).
	local height = screen.AbsoluteSize.Y
	label.Position = if height > 0
		then UDim2.new(0.5, 0, 0, math.floor(VfxController.koBannerCenterY(height, duelBarBottom(screen)) + 0.5))
		else UDim2.fromScale(0.5, KO_BANNER_Y)
	label.Size = UDim2.fromScale(KO_BANNER_WIDTH, KO_BANNER_HEIGHT)
	label.BackgroundTransparency = 1
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextScaled = true
	label.TextColor3 = Palette.Lemon
	label.Text = text("combat.ko")
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.Ink
	stroke.Thickness = 4
	stroke.Parent = label
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = Config.UI.TextSize.Countdown
	size.Parent = label
	local scale = Instance.new("UIScale")
	scale.Parent = label
	label.Parent = screen
	Tweens.scale(
		scale,
		POP_FROM,
		1,
		{ ms = POP_MS, style = Enum.EasingStyle.Back, direction = Enum.EasingDirection.Out }
	)
	local started = os.clock()
	local done = false
	addEffect({
		step = function(_dt: number, _now: number): boolean
			if done then
				return false
			end
			local t = os.clock() - started
			if t >= KO_BANNER_S then
				done = true
				label:Destroy()
				return false
			end
			local fadeFrom = KO_BANNER_S * 0.7
			if t > fadeFrom then
				local u = (t - fadeFrom) / (KO_BANNER_S - fadeFrom)
				label.TextTransparency = u
				stroke.Transparency = u
			end
			return true
		end,
		stop = function()
			if not done then
				done = true
				label:Destroy()
			end
		end,
	})
end

local function confetti(at: Vector3)
	local pool = FxPool.default()
	local each = math.floor(ELIM.confettiParticles / #CONFETTI_COLORS)
	for _, color in CONFETTI_COLORS do
		pool:emit(at, each, {
			Texture = TEXTURES.smoke,
			Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(5, 9),
			SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new(0.5, 0),
			Color = ColorSequence.new(color),
			Acceleration = Vector3.new(0, -10, 0),
		})
	end
	pool:emit(at, ELIM.sparkles, {
		Texture = TEXTURES.sparkles,
		Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.6, 0),
		Color = ColorSequence.new(Palette.Lemon),
	})
end

-- The tumbling confetti parts (§18.4.6): FxPool parts launched from `at`, one effect for all of them; gone after
-- Confetti.lifetime, fading over its last fadeSeconds.
local function confettiParts(at: Vector3)
	local pool = FxPool.default()
	local rng = Random.new()
	local pieces = VfxController.confettiLaunch(rng, reduced())
	local parts: { BasePart } = {}
	local positions: { Vector3 } = {}
	local velocities: { Vector3 } = {}
	local rotations: { CFrame } = {}
	for index, piece in pieces do
		local rotation = CFrame.fromAxisAngle(piece.axis, rng:NextNumber(0, 2 * math.pi))
		parts[index] = pool:acquirePart({
			Name = "Confetti",
			Color = piece.color,
			Size = CONFETTI.size,
			Transparency = 0,
			CFrame = CFrame.new(at) * rotation,
		})
		positions[index] = at
		velocities[index] = piece.velocity
		rotations[index] = rotation
	end
	stats.confettiParts += #parts
	local started = os.clock()
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		for _, part in parts do
			pool:release(part)
		end
		table.clear(parts)
	end
	addEffect({
		step = function(dt: number, _now: number): boolean
			if done then
				return false
			end
			local transparency, over = VfxController.confettiTransparency(os.clock() - started)
			if over then
				finish()
				return false
			end
			for index, part in parts do
				local piece = pieces[index]
				local position, velocity = VfxController.confettiStep(positions[index], velocities[index], dt)
				positions[index], velocities[index] = position, velocity
				if piece.spinDeg ~= 0 then
					rotations[index] = CFrame.fromAxisAngle(piece.axis, math.rad(piece.spinDeg) * dt) * rotations[index]
				end
				part.CFrame = CFrame.new(position) * rotations[index]
				part.Transparency = transparency
			end
			return true
		end,
		stop = finish,
	})
end

-- sfx.elimination at 700 ms (§18.6): 2D for the two duelists, who also get the knockout duck; 3D at the victim for
-- everyone else.
local function eliminationSound(victim: Player, attackerId: number?, at: Vector3?)
	local localPlayer = Players.LocalPlayer
	local duelist = victim == localPlayer
		or (attackerId ~= nil and localPlayer ~= nil and attackerId == localPlayer.UserId)
	if duelist then
		playSound(SOUND_ELIMINATION, { priority = BIG_PRIORITY })
		local ok, err = pcall(SoundController.duckFor, "knockout", AUDIO.Ducking.knockoutSeconds)
		if not ok then
			log:warn("knockout duck failed:", err)
		end
	else
		playSound(SOUND_ELIMINATION, { at = at, priority = BIG_PRIORITY })
	end
end

local function playStandard(player: Player, attackerId: number?)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = rootOf(player)
	local anchor: BasePart? = if head and head:IsA("BasePart") then head else root
	flinch(player, 1)
	if anchor then
		billboardText(anchor, text("combat.out"), Palette.Strawberry, OUT_LABEL_S)
	end
	if player == Players.LocalPlayer then
		shake(SHAKE.eliminated)
	end
	if attackerId ~= nil and attackerId == Players.LocalPlayer.UserId then
		koBanner()
	end
	eliminated[player] = { player = player, restored = false }
	local started = os.clock()
	local confettiDone = false
	local finished = false
	local lastAt: Vector3? = nil -- where the held squishy was at the confetti (the pop ring's fallback)
	local wobbleState = { scale = 1 }
	HeldSquishyController.setOverlay(player, OVERLAY_ELIMINATED, {
		step = function(_dt: number, _now: number): (Vector3, number, boolean)
			local s = wobbleState.scale
			return Vector3.one * s, 0, not finished
		end,
	})
	addEffect({
		step = function(_dt: number, _now: number): boolean
			if finished then
				return false
			end
			local t = os.clock() - started
			local layer = CharacterAnimController.getLayer(player)
			-- Dizzy with sway from the end of the flinch until dizzyEndMs, blended in and out.
			local dizzy = 0
			if t >= ELIM_FLINCH_S and t < ELIM_DIZZY_S + DIZZY_BLEND_S then
				local into = math.clamp((t - ELIM_FLINCH_S) / DIZZY_BLEND_S, 0, 1)
				local out = math.clamp((ELIM_DIZZY_S + DIZZY_BLEND_S - t) / DIZZY_BLEND_S, 0, 1)
				dizzy = math.min(into, out)
			end
			if layer then
				if dizzy > 0 then
					if layer:has(LAYER_DIZZY) then
						layer:setWeight(LAYER_DIZZY, dizzy)
					else
						layer:setPose(LAYER_DIZZY, "dizzy", dizzy)
					end
				elseif layer:has(LAYER_DIZZY) then
					layer:clear(LAYER_DIZZY)
				end
			end
			-- Held squishy: wobbles while dizzy, then shrinks away and hides.
			if t < ELIM_DIZZY_S then
				local amplitude = if reduced() then 0 else WOBBLE_AMP
				wobbleState.scale = 1 + amplitude * math.sin(2 * math.pi * WOBBLE_HZ * t)
			else
				local u = math.clamp((t - ELIM_DIZZY_S) / (ELIM_END_S - ELIM_DIZZY_S), 0, 1)
				wobbleState.scale = 1 - (1 - Config.Anim.deform.scaleMin) * u
				if not confettiDone then
					confettiDone = true
					local held = HeldSquishyController.getModel(player)
					local at = if held then held:GetPivot().Position elseif root then root.Position else nil
					if at then
						confetti(at)
						confettiParts(at)
					end
					lastAt = at
					eliminationSound(player, attackerId, at)
				end
			end
			if t >= ELIM_END_S then
				-- The pop ring where the squishy vanishes (§18.4.6).
				local held = HeldSquishyController.getModel(player)
				local popAt = if held then held:GetPivot().Position else lastAt
				if popAt then
					ring(popAt, Vector3.yAxis, CONFETTI.popRingStuds, CONFETTI.popRingSeconds, Palette.White)
				end
				finished = true
				HeldSquishyController.setHidden(player, HIDE_ELIMINATED, true)
				HeldSquishyController.setOverlay(player, OVERLAY_ELIMINATED, nil)
				return false
			end
			return true
		end,
		stop = function()
			if not finished then
				finished = true
				HeldSquishyController.setOverlay(player, OVERLAY_ELIMINATED, nil)
				local layer = CharacterAnimController.getLayer(player)
				if layer and layer:has(LAYER_DIZZY) then
					layer:clear(LAYER_DIZZY)
				end
			end
		end,
	})
	stats.eliminations += 1
	VfxController.Eliminated:fire(player.UserId, attackerId)
end

local ELIMINATION_REGISTRY: { [string]: (Player, number?) -> () } = {
	standard = playStandard,
	epic_pending = playStandard,
}

-- The held squishy comes back once the eliminated player is Returning or back in the lobby.
local function restoreEliminated()
	for player, entry in eliminated do
		local phase = player:GetAttribute(ATTR_DUEL_PHASE)
		if player.Parent == nil or phase == nil or phase == "" or phase == "Returning" then
			eliminated[player] = nil
			if player.Parent ~= nil and not entry.restored then
				entry.restored = true
				HeldSquishyController.setHidden(player, HIDE_ELIMINATED, false)
			end
		end
	end
end

-- Dragon Rush -------------------------------------------------------------------------------------------------------

local function rushPart(spec: PartSpec, shape: Enum.PartType, color: Color3, transparency: number): BasePart
	return FxPool.default():acquirePart({
		Name = "RushLane",
		Shape = shape,
		Color = color,
		Transparency = transparency,
		Size = spec.size,
		CFrame = spec.cframe,
	})
end

local function hornsOf(player: Player): { { part: BasePart, color: Color3 } }
	local list = {}
	local held = HeldSquishyController.getModel(player)
	if held == nil then
		return list
	end
	for _, descendant in held:GetDescendants() do
		if descendant:IsA("BasePart") and string.sub(descendant.Name, 1, #HORN_PREFIX) == HORN_PREFIX then
			table.insert(list, { part = descendant, color = descendant.Color })
		end
	end
	return list
end

local function restoreHorns(rush: Rush)
	for _, horn in rush.horns do
		if horn.part.Parent ~= nil then
			horn.part.Color = horn.color
		end
	end
	table.clear(rush.horns)
end

-- Releases the telegraph duck and, when stopTelegraph, stops the tracked telegraph sound with its short fade.
local function endRushAudio(rush: Rush, stopTelegraph: boolean)
	local release = rush.duckRelease
	if release then
		rush.duckRelease = nil
		local ok, err = pcall(release :: () -> ...any)
		if not ok then
			log:warn("telegraph duck release failed:", err)
		end
	end
	local stop = rush.telegraphStop
	if stopTelegraph and stop then
		rush.telegraphStop = nil
		local ok, err = pcall(stop :: (number?) -> ...any, AUDIO.trackedStopFadeMs)
		if not ok then
			log:warn("telegraph sound stop failed:", err)
		end
	end
end

-- The telegraph sounds (§18.6): the tracked telegraph at O for everyone, the optional roar (2D) for the caster and
-- the other duelist, and the "telegraph" music duck for the targeted duelist until the release or the cancel.
local function startTelegraphAudio(rush: Rush?, event: Types.UltimateEventPayload)
	if rush == nil then
		return
	end
	local telegraphPriority = soundPriorityFor(BIG_PRIORITY, event.casterId, nil)
	local ok, stop =
		pcall(SoundController.playTracked, SOUND_TELEGRAPH, { at = event.origin, priority = telegraphPriority })
	if ok then
		rush.telegraphStop = stop
	else
		log:warn("telegraph sound failed:", stop)
	end
	local localPlayer = Players.LocalPlayer
	local roar, targeted =
		VfxController.rushListener(event.casterId, if localPlayer then localPlayer.UserId else nil, opponentUserId())
	if roar then
		playSound(SOUND_ROAR, { priority = BIG_PRIORITY })
	end
	if targeted then
		local okDuck, release = pcall(SoundController.duck, "telegraph")
		if okDuck then
			rush.duckRelease = release
		else
			log:warn("telegraph duck failed:", release)
		end
	end
end

local function releaseRush(rush: Rush)
	endRushAudio(rush, true)
	local pool = FxPool.default()
	for _, part in rush.parts do
		pool:release(part)
	end
	table.clear(rush.parts)
	pool:release(rush.fill)
	local emitter = rush.headEmitter
	if emitter then
		rush.headEmitter = nil
		pool:release(emitter)
	end
	local sparks = rush.sparks
	if sparks then
		rush.sparks = nil
		pool:release(sparks)
	end
	local head = rush.head
	if head then
		rush.head = nil
		rush.fadeHead = nil
		local deformer = rush.headDeformer
		if deformer then
			deformer:destroy()
		end
		head:Destroy()
	end
	local label = rush.label
	if label then
		rush.label = nil
		label:Destroy()
	end
	restoreHorns(rush)
	if rushes[rush.casterId] == rush then
		rushes[rush.casterId] = nil
	end
end

local function startRushFade(rush: Rush, seconds: number)
	if rush.phase == "fade" then
		return
	end
	rush.phase = "fade"
	rush.fadeStart = os.clock()
	rush.fadeSeconds = seconds
	restoreHorns(rush)
	local sparks = rush.sparks
	if sparks then
		rush.sparks = nil
		FxPool.default():release(sparks)
	end
end

local function buildHead(rush: Rush)
	local ok, built = pcall(function(): Model
		return SquishyCache.clone("dragon_head_vfx", "World", RUSH_VFX.headScale)
	end)
	if not ok or typeof(built) ~= "Instance" then
		log:warn("dragon head model failed:", built)
		return
	end
	local head = built :: Model
	local root = head.PrimaryPart
	if root == nil then
		head:Destroy()
		return
	end
	for _, descendant in head:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("SD_Group") == "jaw" then
			local weld = descendant:FindFirstChildWhichIsA("Weld")
			if weld then
				local base = weld.C0
				rush.jaw = {
					weld = weld,
					base = base,
					hinge = base.Position + Vector3.new(0, 0, descendant.Size.Z / 2),
				}
			end
			break
		end
	end
	root.CFrame = CFrame.lookAt(rush.origin, rush.origin + rush.indicator.dir)
	local parent = Workspace:FindFirstChild("SD_ClientFx") or Workspace
	head.Parent = parent
	rush.head = head
	rush.headDeformer = SquishDeformer.attach(head)
	-- First person (spec 2026-10-10 §3.10): the head's fade on this client, as the max of its end fade and, while first
	-- person is on, the local caster's fade-in by the distance travelled and the near fade from the camera
	-- (Anim/NearFade.rushHead). Resolved once here (inline requires: this module gets no new top-level local), the parts
	-- kept (never read per frame), the modifier written only when it changes.
	local FirstPersonController = require(script.Parent.FirstPersonController)
	local NearFade = require(Client.Anim.NearFade)
	local headParts: { BasePart } = {}
	for _, descendant in head:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(headParts, descendant)
		end
	end
	local localPlayer = Players.LocalPlayer
	local isCaster = localPlayer ~= nil and rush.casterId == localPlayer.UserId
	local written = 0
	rush.fadeHead = function(endFade: number)
		local fade = endFade
		local camera = Workspace.CurrentCamera
		if camera and FirstPersonController.isActive() then
			local at = root.Position
			local travelled = (at - rush.origin).Magnitude
			fade = NearFade.rushHead(endFade, travelled, (camera.CFrame.Position - at).Magnitude, isCaster, true)
		end
		if fade ~= written then
			written = fade
			for _, part in headParts do
				part.LocalTransparencyModifier = fade
			end
		end
	end
	local emitter = FxPool.default():acquireEmitter({
		Texture = TEXTURES.fire,
		Rate = HEAD_TRAIL_RATE,
		Lifetime = NumberRange.new(0.25, 0.4),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(60, 60),
		Size = NumberSequence.new(0.6, 0),
		Color = ColorSequence.new(HORN_HOT),
	})
	emitter.Enabled = true
	rush.headEmitter = emitter
	FxPool.default():emit(rush.origin, RUSH_VFX.releaseEmbers, {
		Texture = TEXTURES.fire,
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(120, 120),
		Size = NumberSequence.new(0.5, 0),
		Color = ColorSequence.new(HORN_HOT),
	})
end

local function arriveRush(rush: Rush)
	local indicator = rush.indicator
	local e = indicator.endpoint
	local floorPoint = Vector3.new(e.X, indicator.floorY, e.Z)
	local pool = FxPool.default()
	local radius = indicator.rect.size.X / 2
	pool:emit(e, IMPACT_PUFFS, {
		Texture = TEXTURES.smoke,
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(radius * 0.8, radius * 1.6),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.8, 0),
		Color = ColorSequence.new(Palette.Cream),
	})
	pool:emit(e, IMPACT_PUFFS, {
		Texture = TEXTURES.fire,
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(radius * 0.8, radius * 1.6),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new(0.5, 0),
		Color = ColorSequence.new(HORN_HOT),
	})
	ring(floorPoint, Vector3.yAxis, 2 * radius, RING_SECONDS, Palette.Danger)
	playSound(SOUND_CHOMP, { at = e, priority = soundPriorityFor(BIG_PRIORITY, rush.casterId, nil) })
	local localRoot = rootOf(Players.LocalPlayer)
	if localRoot and (localRoot.Position - e).Magnitude <= radius + SHAKE.dragonRushNearby.extraStuds then
		shake(SHAKE.dragonRushNearby)
	end
	local emitter = rush.headEmitter
	if emitter then
		emitter.Enabled = false
	end
end

local function stepRush(rush: Rush, now: number): boolean
	local indicator = rush.indicator
	local edge = RUSH_VFX.indicatorEdgeTransparency
	local fillT = RUSH_VFX.indicatorFillTransparency
	if rush.phase == "telegraph" or rush.phase == "release" then
		-- Edge pulse (static under ReducedMotion).
		local pulse = if reduced() then 0 else PULSE_AMPLITUDE * (0.5 + 0.5 * math.sin(2 * math.pi * PULSE_HZ * now))
		for _, part in rush.parts do
			part.Transparency = edge + pulse
		end
	end
	if rush.phase == "telegraph" then
		local span = math.max(rush.telegraphEndsAt - rush.telegraphStart, 1e-3)
		local progress = math.clamp((now - rush.telegraphStart) / span, 0, 1)
		local length = math.max(rush.length * progress, 0.05)
		local o = indicator.capO.cframe.Position
		local centre = o + indicator.dir * (length / 2) + Vector3.new(0, FILL_LIFT, 0)
		rush.fill.Size = Vector3.new(indicator.rect.size.X * FILL_WIDTH_FRACTION, 0.1, length)
		rush.fill.CFrame = CFrame.lookAt(centre, centre + indicator.dir)
		rush.fill.Transparency = fillT
		-- Horns heat up teal -> orange; ember sparks at the hand.
		for _, horn in rush.horns do
			if horn.part.Parent ~= nil then
				horn.part.Color = horn.color:Lerp(HORN_HOT, progress)
			end
		end
		local sparks = rush.sparks
		local caster = Players:GetPlayerByUserId(rush.casterId)
		local held = caster and HeldSquishyController.getModel(caster)
		if sparks and held then
			local attachment = sparks.Parent
			if attachment and attachment:IsA("Attachment") then
				attachment.WorldPosition = held:GetPivot().Position
			end
		end
		if now >= rush.telegraphEndsAt and rush.head == nil then
			-- No release message yet: keep the full lane up until it comes (or the cancel).
			rush.fill.Size = Vector3.new(indicator.rect.size.X * FILL_WIDTH_FRACTION, 0.1, rush.length)
		end
		return true
	end
	if rush.phase == "release" then
		local head = rush.head
		if head == nil then
			buildHead(rush)
			head = rush.head
		end
		local elapsed = now - rush.telegraphEndsAt
		local position, fraction =
			VfxController.rushHeadAt(rush.origin, indicator.dir, rush.length, rush.speed, elapsed)
		if head and head.PrimaryPart then
			(head.PrimaryPart :: BasePart).CFrame = CFrame.lookAt(position, position + indicator.dir)
		end
		local fadeHead = rush.fadeHead
		if fadeHead then
			fadeHead(0) -- no end fade yet: in first person the caster's fade-in and the near fade
		end
		local emitter = rush.headEmitter
		if emitter then
			local attachment = emitter.Parent
			if attachment and attachment:IsA("Attachment") then
				attachment.WorldPosition = position
			end
		end
		local arrived = rush.arrivedAt
		if arrived == nil and fraction >= 1 then
			rush.arrivedAt = now
			arrived = now
			arriveRush(rush)
		end
		local jaw = rush.jaw
		if jaw and jaw.weld.Parent ~= nil then
			local angle = VfxController.jawAngle(fraction, if arrived then now - arrived else nil)
			local hinge = CFrame.new(jaw.hinge)
			jaw.weld.C0 = hinge * CFrame.Angles(math.rad(angle), 0, 0) * hinge:Inverse() * jaw.base
		end
		if arrived ~= nil and now - arrived >= HEAD_LINGER_S then
			startRushFade(rush, RUSH_VFX.indicatorFadeMs / 1000)
		end
		return true
	end
	-- fade: transparency only increases.
	local u = math.clamp((os.clock() - (rush.fadeStart or os.clock())) / math.max(rush.fadeSeconds, 1e-3), 0, 1)
	for _, part in rush.parts do
		part.Transparency = math.max(part.Transparency, edge + (1 - edge) * u)
	end
	rush.fill.Transparency = math.max(rush.fill.Transparency, fillT + (1 - fillT) * u)
	local fadeHead = rush.fadeHead
	if fadeHead then
		fadeHead(u)
	end
	local label = rush.label
	if label then
		local textLabel = label:FindFirstChildWhichIsA("TextLabel")
		if textLabel then
			textLabel.TextTransparency = u
		end
	end
	return u < 1
end

local function onUltimateEvent(raw: unknown)
	local event = ThrowController.parseUltimateEvent(raw)
	if event == nil then
		return
	end
	local current = rushes[event.casterId]
	if event.phase == "telegraph" then
		if current then
			releaseRush(current)
		end
		local indicator = VfxController.rushIndicator(event.origin, event.dir, event.length, event.radius)
		local parts = {
			rushPart(indicator.rect, Enum.PartType.Block, Palette.Danger, RUSH_VFX.indicatorEdgeTransparency),
			rushPart(indicator.capO, Enum.PartType.Cylinder, Palette.Danger, RUSH_VFX.indicatorEdgeTransparency),
			rushPart(indicator.capE, Enum.PartType.Cylinder, Palette.Danger, RUSH_VFX.indicatorEdgeTransparency),
		}
		local fill = FxPool.default():acquirePart({
			Name = "RushFill",
			Color = Palette.White,
			Transparency = RUSH_VFX.indicatorFillTransparency,
			Size = Vector3.new(0.1, 0.1, 0.1),
			CFrame = indicator.capO.cframe,
		})
		local caster = Players:GetPlayerByUserId(event.casterId)
		local sparks = FxPool.default():acquireEmitter({
			Texture = TEXTURES.fire,
			Rate = RUSH_VFX.handSparkRate,
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(40, 40),
			Size = NumberSequence.new(0.3, 0),
			Color = ColorSequence.new(HORN_HOT),
		})
		sparks.Enabled = caster ~= nil
		local now = serverNow()
		rushes[event.casterId] = {
			casterId = event.casterId,
			indicator = indicator,
			parts = parts,
			fill = fill,
			telegraphEndsAt = event.telegraphEndsAt,
			telegraphStart = math.min(now, event.telegraphEndsAt),
			speed = if type(event.speed) == "number" and event.speed > 0 then event.speed else RUSH.speed,
			length = event.length,
			origin = event.origin,
			phase = "telegraph",
			head = nil,
			headDeformer = nil,
			fadeHead = nil,
			jaw = nil,
			headEmitter = nil,
			sparks = sparks,
			horns = if caster then hornsOf(caster) else {},
			arrivedAt = nil,
			fadeStart = nil,
			fadeSeconds = 0,
			label = nil,
			telegraphStop = nil,
			duckRelease = nil,
		}
		stats.rushes += 1
		startTelegraphAudio(rushes[event.casterId], event)
	elseif event.phase == "release" then
		local releasePriority = soundPriorityFor(BIG_PRIORITY, event.casterId, nil)
		playSound(SOUND_RUSH_RELEASE, { at = event.origin, priority = releasePriority })
		if current then
			endRushAudio(current, false) -- the telegraph is over: the duck goes; the sound plays out
		end
		if type(event.projId) == "number" then
			local speed = if type(event.speed) == "number" and event.speed > 0 then event.speed else RUSH.speed
			rushProjIds[event.projId] = {
				squishyId = "",
				throwerId = event.casterId,
				untilAt = event.telegraphEndsAt + math.max(event.length, 0) / speed + 5,
			}
		end
		if current and current.phase == "telegraph" then
			current.phase = "release"
			current.telegraphEndsAt = event.telegraphEndsAt
			restoreHorns(current)
			local sparks = current.sparks
			if sparks then
				current.sparks = nil
				FxPool.default():release(sparks)
			end
		end
	elseif event.phase == "cancel" then
		if current then
			endRushAudio(current, true)
		end
		if current and current.phase == "telegraph" then
			local board = Instance.new("BillboardGui")
			board.Name = "SD_RushInterrupted"
			board.Adornee = current.parts[1]
			board.AlwaysOnTop = true
			board.LightInfluence = 0
			board.Size = UDim2.fromScale(8, 2)
			board.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
			label.TextScaled = true
			label.TextColor3 = Palette.White
			label.Text = text(RUSH.cancelKey or "ability.interrupted")
			local stroke = Instance.new("UIStroke")
			stroke.Color = Palette.Ink
			stroke.Thickness = 3
			stroke.Parent = label
			label.Parent = board
			local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
			board.Parent = playerGui
			current.label = board
			startRushFade(current, RUSH_VFX.cancelFadeMs / 1000)
		end
	end
end

local function stepRushes(now: number)
	for casterId, rush in rushes do
		local ok, keep = pcall(stepRush, rush, now)
		if not ok then
			log:error("Dragon Rush visual failed:", keep)
			releaseRush(rush)
		elseif not keep then
			releaseRush(rush)
		end
		if rushes[casterId] == rush and Players:GetPlayerByUserId(casterId) == nil and rush.phase == "telegraph" then
			startRushFade(rush, RUSH_VFX.cancelFadeMs / 1000)
		end
	end
end

-- Remote events -----------------------------------------------------------------------------------------------------

local function onThrowStarted(raw: unknown)
	local payload = ThrowController.parseThrowStarted(raw)
	if payload == nil then
		return
	end
	projectiles[payload.projId] = {
		squishyId = payload.squishyId,
		throwerId = payload.throwerId,
		untilAt = payload.releaseAt + Config.Duel.Rules.ProjectileMaxLifetime + 5,
	}
end

-- One server impact (or a Studio fake one: debugOnly skips the knockback). The sounds, the knockback, the held flinch
-- pose and the held flash start now; everything else waits for this client's hit-stop, when it has one (§18.4.4).
local function handleImpact(impact: Types.ThrowImpactPayload, debugOnly: boolean?)
	stats.impacts += 1
	local info = projectiles[impact.projId]
	projectiles[impact.projId] = nil
	local rushInfo = rushProjIds[impact.projId]
	local rushCaster = if rushInfo then rushInfo.throwerId else nil
	if rushInfo ~= nil and not MAJOR_KINDS[impact.kind] then
		rushProjIds[impact.projId] = nil -- the lane ended (a lane flies on through the players it hits)
	end
	local accent = if info then accentOf(info.squishyId) else Palette.White
	local attackerId = if info then info.throwerId else rushCaster
	impactSound(impact, rushCaster ~= nil, attackerId)
	local localPlayer = Players.LocalPlayer
	local localId = if localPlayer then localPlayer.UserId else nil
	local isReduced = reduced()
	local juice = VfxController.hitJuice(
		impact.kind,
		impact.eliminated,
		localId,
		impact.victimId,
		attackerId,
		isReduced,
		shakeEnabled()
	)
	local holdStart: number? = nil
	local stopSeconds = juice.stopSeconds
	if stopSeconds ~= nil then
		-- A throw ends at its first impact, so its projId is also ProjectileRenderer's key (the first asker registers);
		-- a lane can hit more than once and only this module asks for it, so it goes unkeyed.
		local key = if rushCaster ~= nil then nil else impact.projId
		holdStart = HitStop.trigger(key, stopSeconds, os.clock(), isReduced)
		if holdStart ~= nil then
			stats.holds += 1
		end
	end
	local held = holdStart ~= nil
	local function afterHold(fn: () -> ())
		if held then
			HitStop.after(fn)
		else
			fn()
		end
	end
	-- First person (spec 2026-10-10 §3.10), an inline require: this module gets no new top-level local.
	local firstPerson = require(script.Parent.FirstPersonController).isActive()
	if rushCaster == nil then
		local scale = VfxController.impactScale(juice.localIsVictim, firstPerson)
		afterHold(function()
			impactBurst(impact, accent, scale)
		end)
	end
	local punch = juice.punch
	if impact.kind ~= "player" or type(impact.victimId) ~= "number" then
		if punch ~= nil then
			local spec: PunchSpec = punch
			afterHold(function()
				punchCamera(spec) -- a practice target hit
			end)
		end
		return
	end
	stats.hits += 1
	if impact.eliminated == true and attackerId ~= nil and attackerId == localId then
		-- Foam fix 2: this client's "K.O.!" banner comes after the hold; the duel result card waits for it from now.
		koUntil = VfxController.koBannerEndsAt(os.clock(), if held then stopSeconds else nil)
	end
	local victim = Players:GetPlayerByUserId(impact.victimId :: number)
	if victim ~= nil then
		local invulnUntil = if type(impact.invulnUntil) == "number" then impact.invulnUntil :: number else serverNow()
		if VfxController.ghostWanted(victim == localPlayer, firstPerson) then
			showGhost(victim, invulnUntil, held)
		end
		if held then
			holdFlinch(victim)
		else
			flinch(victim, 1)
		end
		if victim == localPlayer and debugOnly ~= true then
			applyKnockback(impact, if rushCaster ~= nil then RUSH.knockbackMultiplier else 1)
		end
		afterHold(function()
			releaseHeldFlinch(victim, true)
			HeldSquishyController.react(victim, "hit", 1) -- the held boing: the held model's own rig (§3.2)
			if victim == Players.LocalPlayer then
				local rushAccent = if rushCaster ~= nil then Palette.Danger else accent
				playVignette(rushAccent)
				shake(SHAKE.hitReceived)
			end
			if punch then
				punchCamera(punch)
			end
			if impact.eliminated == true then
				local effect = ELIMINATION_REGISTRY[VfxController.eliminationEffect(impact.effectId)]
				effect(victim, attackerId)
			end
		end)
	else
		afterHold(function()
			if punch then
				punchCamera(punch)
			end
			if impact.eliminated == true and attackerId ~= nil and attackerId == localId then
				koBanner() -- e.g. the Studio test dummy: no character here, but the eliminator still sees K.O.!
			end
		end)
	end
end

local function onThrowImpact(raw: unknown)
	local impact = ThrowController.parseImpact(raw)
	if impact == nil then
		return
	end
	handleImpact(impact, false)
end

-- Arena lighting (§7.4) ---------------------------------------------------------------------------------------------

local function lightingInstances(): (ColorCorrectionEffect?, Atmosphere?)
	local grade = Lighting:FindFirstChild(GRADE_NAME)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	return if grade and grade:IsA("ColorCorrectionEffect") then grade else nil, atmosphere
end

local function applyLighting(goals: LightingValues)
	for _, tween in lightingTweens do
		tween:Cancel()
	end
	table.clear(lightingTweens)
	local grade, atmosphere = lightingInstances()
	local ms = if reduced() then 0 else ZONE_PRESETS.tweenSeconds * 1000
	local function set(instance: Instance, values: { [string]: any })
		if ms > 0 then
			table.insert(lightingTweens, Tweens.play(instance, ms, values, Enum.EasingStyle.Sine))
		else
			for property, value in values do
				(instance :: any)[property] = value
			end
		end
	end
	local contrast, saturation, density = goals.contrast, goals.saturation, goals.density
	if grade and contrast ~= nil and saturation ~= nil then
		set(grade, { Contrast = contrast, Saturation = saturation })
	end
	if atmosphere and density ~= nil then
		set(atmosphere, { Density = density })
	end
end

-- Arena entry saves the lobby values and applies the preset; leaving restores what was saved.
local function setArenaLighting(inArena: boolean)
	if inArena == (savedLighting ~= nil) then
		return
	end
	if inArena then
		local grade, atmosphere = lightingInstances()
		savedLighting = {
			contrast = if grade then grade.Contrast else nil,
			saturation = if grade then grade.Saturation else nil,
			density = if atmosphere then atmosphere.Density else nil,
		}
	end
	local goals = VfxController.lightingGoals(inArena, savedLighting)
	if not inArena then
		savedLighting = nil
	end
	if goals then
		applyLighting(goals)
	end
end

local function clearMatchEffects()
	for player in table.clone(ghosts) do
		removeGhost(player)
	end
	for _, rush in table.clone(rushes) do
		startRushFade(rush, RUSH_VFX.cancelFadeMs / 1000)
	end
end

local function onDuelChanged(view: any, old: any)
	local ok, err = pcall(function(): any
		setArenaLighting(VfxController.arenaLightingWanted(view))
		return nil
	end)
	if not ok then
		log:warn("arena lighting change failed:", err)
	end
	if view == nil then
		if old ~= nil then
			clearMatchEffects()
		end
		return
	end
	if ENDED_PHASES[view.phase] and (old == nil or not ENDED_PHASES[old.phase]) then
		for player in table.clone(ghosts) do
			removeGhost(player)
		end
	end
end

-- Frame step --------------------------------------------------------------------------------------------------------

local function onDueError(err: any)
	log:error("a hit-stop follow-up failed:", err)
end

local function step(dt: number, clock: number): boolean
	local now = serverNow()
	-- What waited for the hit-stop starts first (its effects step from this frame on).
	HitStop.runDue(clock, onDueError)
	stepGhosts(now)
	stepRushes(now)
	restoreEliminated()
	local count = #effects
	local kept = 0
	for index = 1, count do
		local effect = effects[index]
		local ok, alive = pcall(effect.step, dt, now)
		if not ok then
			log:error("an effect failed:", alive)
			pcall(effect.stop)
		elseif alive == true then
			kept += 1
			effects[kept] = effect
		end
	end
	-- Effects added during this frame's steps (e.g. the elimination's pop ring) are kept as they are.
	for index = count + 1, #effects do
		kept += 1
		effects[kept] = effects[index]
	end
	for index = #effects, kept + 1, -1 do
		effects[index] = nil
	end
	for projId, info in projectiles do
		if now > info.untilAt then
			projectiles[projId] = nil
		end
	end
	for projId, info in rushProjIds do
		if now > info.untilAt then
			rushProjIds[projId] = nil
		end
	end
	return true
end

-- Public ------------------------------------------------------------------------------------------------------------

-- Studio / debug counters.
function VfxController.counts(): { [string]: any }
	local ghostCount, rushCount, elimCount = 0, 0, 0
	for _ in ghosts do
		ghostCount += 1
	end
	for _ in rushes do
		rushCount += 1
	end
	for _ in eliminated do
		elimCount += 1
	end
	local heldCount = 0
	for _ in heldFlinches do
		heldCount += 1
	end
	local connected = 0
	for _, connection in connections do
		if connection.connected then
			connected += 1
		end
	end
	local pool = FxPool.default()
	return {
		effects = #effects,
		ghosts = ghostCount,
		rushes = rushCount,
		eliminatedHidden = elimCount,
		impacts = stats.impacts,
		hits = stats.hits,
		eliminations = stats.eliminations,
		rushesShown = stats.rushes,
		knockbacks = stats.knockbacks,
		holds = stats.holds,
		punches = stats.punches,
		confettiParts = stats.confettiParts,
		hitStopPending = HitStop.pending(),
		heldFlinches = heldCount,
		rings = FxShapes.count(),
		poolEmitters = pool:activeCount("emitter"),
		poolParts = pool:activeCount("part"),
		connections = connected,
	}
end

-- Studio: adds (or replaces, or with nil removes) a debugJuice piece another controller owns (SplatController's
-- "splat"), so this module never requires a controller booted after it.
function VfxController.setJuiceHook(name: string, hook: JuiceHook?)
	if hook then
		juiceHooks[name] = hook
	else
		juiceHooks[name] = nil
	end
end

-- Studio (DebugHooks "juice"): plays one juice piece locally with a fake payload and no remote. Names: "hitstop"
-- (opts.seconds, default the hit hold), "punch" (opts.kind: hitDealt / elimDealt / practiceHit), "confetti" (the
-- elimination confetti at the local held squishy), "victim" (a fake hit on the local player: hold, held flash and
-- flinch, then boing, vignette and shake; opts.eliminated plays the elimination too; no knockback), plus the hooks
-- other controllers add ("splat"). Returns whether it played and, when not, why.
function VfxController.debugJuice(name: string, opts: { [string]: any }?): (boolean, string?)
	local options: { [string]: any } = opts or {}
	local hook = juiceHooks[name]
	if hook then
		return hook(options)
	end
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return false, "no local player"
	end
	if name == "hitstop" then
		local seconds = if type(options.seconds) == "number" then options.seconds else HIT_STOP.playerHit
		local start = HitStop.trigger(nil, seconds, os.clock(), reduced())
		if start == nil then
			return false, "no hold (ReducedMotion, or the window is full)"
		end
		return true, nil
	elseif name == "punch" then
		local kind = if type(options.kind) == "string" then options.kind else "hitDealt"
		local spec = (PUNCH :: any)[kind]
		if type(spec) ~= "table" or type(spec.fovDeg) ~= "number" then
			return false, `unknown punch kind {kind}`
		end
		return CameraController.punch(spec.fovDeg, spec.attackMs, spec.releaseMs), nil
	end
	local root = rootOf(localPlayer)
	if root == nil then
		return false, "no character"
	end
	if name == "confetti" then
		local held = HeldSquishyController.getModel(localPlayer)
		local at = if held then held:GetPivot().Position else root.Position + Vector3.new(0, 2, 0)
		confetti(at)
		confettiParts(at)
		return true, nil
	elseif name == "victim" then
		debugSerial += 1
		local projId = -debugSerial -- never a server projId
		local squishyId = HeldSquishyController.getSquishyId(localPlayer)
		projectiles[projId] = { squishyId = squishyId or "", throwerId = 0, untilAt = serverNow() + 5 }
		local impact: Types.ThrowImpactPayload = {
			projId = projId,
			kind = "player",
			position = root.Position + Vector3.new(0, 1, 0),
			normal = root.CFrame.LookVector,
			victimId = localPlayer.UserId,
			invulnUntil = serverNow() + 1,
			eliminated = options.eliminated == true,
			effectId = "standard",
		}
		handleImpact(impact, true)
		return true, nil
	end
	return false, `unknown juice {name}`
end

-- Stops every running effect (leak checks), drops what waits for the hit-stop and puts held flinches back.
function VfxController.clear()
	HitStop.clear()
	koUntil = 0
	for player in table.clone(heldFlinches) do
		releaseHeldFlinch(player, false)
	end
	for _, effect in effects do
		pcall(effect.stop)
	end
	table.clear(effects)
	for player in table.clone(ghosts) do
		removeGhost(player)
	end
	for _, rush in table.clone(rushes) do
		releaseRush(rush)
	end
	for player, entry in eliminated do
		if player.Parent ~= nil and not entry.restored then
			HeldSquishyController.setHidden(player, HIDE_ELIMINATED, false)
		end
	end
	table.clear(eliminated)
	table.clear(projectiles)
	table.clear(rushProjIds)
	pcall(function(): any
		setArenaLighting(false)
		return nil
	end)
end

-- Lifecycle

function VfxController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(Scheduler.add(step, "render"))
	track(NetController.on("ThrowStarted", onThrowStarted))
	track(NetController.on("ThrowImpact", onThrowImpact))
	track(NetController.on("UltimateEvent", onUltimateEvent))
	track(StateController.DuelChanged:connect(onDuelChanged))
	c:add(function()
		VfxController.clear()
		table.clear(connections)
		local screen = gui
		gui = nil
		vignette = nil
		if screen then
			screen:Destroy()
		end
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function VfxController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return VfxController
