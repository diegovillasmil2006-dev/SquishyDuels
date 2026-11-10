--!strict
-- UltFx (client only). The four Epic ultimates' world visuals (spec phase 5 §1.5-§1.8; design: fp.js:236-372; numbers
-- in Config.Vfx.Ultimates and Config.Abilities, colours in Art/Palette Ult* and Art/RarityStyle). Drawn only from the
-- server's UltimateEvent numbers (VfxController hands every event whose ability is not a lane here) and ended by its
-- ThrowImpact messages: nothing here decides anything.
-- * Wind-up (telegraph): sfx.ultCharge.<squishy> at the caster (tracked: a cancel stops it). The design shows no ground
--   warning before the release (spec §4 #3); the caster's pose is ThrowController's (the Dragon's charge pose).
-- * Release: sfx.ultRelease at the caster, then by kind:
--   Flock Volley: each bird (the caster's squishy at its flight size) from its shot's releaseAt along its server path
--     with the design's glide arc and wobble and a roll, growing from growFrom in growSeconds, with its rarity trail.
--   Sprinkle Roller: the 6 × 60 lane plate (UltSprinkleLane, opacity 0.25) for laneSeconds, and the Donut rolling on its
--     edge along the lane at `speed` (scale 0.5 -> 2.3 × its flight size by backOut in 0.3 s, so its width is the
--     lane's; spin capped at 720°/s; tilt 0.5 + 0.12·sin(9t) rad) shedding sprinkles in the five sprinkle colours.
--   Rain Check: the zone disc (radius 7, UltRainZone, pulsing at zonePulseHz) for zoneSeconds; the bunny lobbed from the
--     caster to bunnyHeight over the centre, then hovering (scale 1 -> 3.2 by backOut, a slow bob and yaw) with its
--     drizzle for hoverSeconds (sfx.ultCloudHover as it parks); each drop: its shadow (radius 1.6, UltRainShadow, pulse
--     held to 3 Hz) from shadowAt for shadowSeconds, then the drop falling from over the centre to its point along k²
--     in fallSeconds, then a splash ring, 8 puffs and sfx.ultRainDrop.
--   Gravity Well (Cosmo, Series 01; design: sd/lab50.js:273-293): a one-drop rain drawn as a well: the zone disc
--     (UltWellZone, pulsing) until the pop, Cosmo flying to wellHoverStuds over the centre in wellLobSeconds and
--     spinning there, 6 beads (its colours) spiralling in from the ring to the centre, and at the pop 40 stars, a gold
--     and a lilac ring and sfx.ultBubblePop.
--   Geyser Line (Gelato Narwhal, Frosty Box 2026-11-10; design: sd/lab50.js:295-307): a 3-drop rain in a line drawn as
--     geysers: no zone and no hovering toy; each drop's frost circle (UltGeyserFrost, its dropHitRadius, pulsing) from
--     shadowAt until it erupts at landAt, then an ice column rising and sinking (geyserColumnSeconds), 18 ice cubes, a
--     white ring and sfx.ultRainDrop (a stand-in for the design's splat).
--   Layer Cake Shockwave (Parfait Wyvern; design: sd/lab50.js:309-325): from the telegraph a glowing landing spot at
--     the caster's feet and the wyvern leaping up from the caster, landing on its spot at the release (26 sugar petals,
--     sfx.ultBubblePop as the design's boom); then each ring (the release's shots: pink, cream, blueberry) a wall of
--     shockRingSegments pieces growing from its releaseAt at the ability's speed out to its length; the wyvern flies
--     back shockReturnAfter after landing. A cancel takes the spot and the wyvern away.
--   Fondue Flood (Lava Cake Hippo, Lava Box 2026-11-10; design: sd/lab50.js:324-339): a shockwave that fills a fan:
--     through the wind-up the fan outline (UltFanTelegraph, pulsing, with a bright rim); at the release the molten flood
--     (UltFondue) fills it at the ability's speed with glowing drops at its front, holds, then sinks and fades.
--   Campfire Ring (Mallow Behemoth; design: sd/lab50.js:340-357): a 6-drop rain around the caster drawn as flames: the
--     slam's ring out to the flames' ring, each drop's ember glow (UltFlameHot, its dropHitRadius, pulsing) until it
--     lights, then a flame (UltFlame, a bright tip) rising and falling with embers.
--   Bubble Pop: the Axolotl in its bubble shell (UltBubbleShell) on the design's 0.9 m arc; at its server end (a hit
--     or its pop) the pop ring (6 studs), 26 puffs and sfx.ultBubblePop. Bubble Pop bounce (2026-10-16): with the
--     release's `bounce` the path turns there onto the bounce leg (the Axolotl faces its new way) and the arc spans the
--     whole flight. Batch B (owner 2026-10-17: "the Frog's bounce look from the design"): as the drawn bubble turns,
--     the Strawberry Frog's bounce pass (fp.js:239): bounceHearts hearts (img.kill.heart) in its two colours going up,
--     a white ring on the floor under it and sfx.pop (bouncePassed, once a flight).
-- * A bird's or the bubble's model goes at its ThrowImpact (the hit itself, its puffs, knockback and hit-stop are
--   VfxController's, as for a throw); the roller rolls on to its end. Cancel stops the charge sound.
-- * ReducedMotion: no pulse, roll, wobble or bob (FxPool halves the particles).
-- API (VfxController): onEvent(event, ultimateId, ability, deps), projectile(projId) -> ProjInfo?, impact(impact),
-- step(now), clear(), counts(); pure helpers (unit-tested): glidePoint, arcPoint, bouncePassed, rollerScale, lanePlate,
-- dropPoint, pulse.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local RarityStyle = require(Shared.Art.RarityStyle)
local SquishyBuilder = require(Shared.Art.SquishyBuilder)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local SquishyCache = require(Client.Models.SquishyCache)
local FxPool = require(script.Parent.FxPool)
local FxShapes = require(script.Parent.FxShapes)
local ViewmodelMath = require(script.Parent.ViewmodelMath)

-- Types

-- What VfxController lends: its sound calls and the ReducedMotion flag.
export type Deps = {
	play: (key: string, options: { [string]: any }?) -> (),
	playTracked: (key: string, options: { [string]: any }?) -> ((fadeMs: number?) -> ())?,
	reduced: () -> boolean,
}

-- One of an Epic ultimate's projectiles, for VfxController's impact handling.
export type ProjInfo = {
	casterId: number,
	squishyId: string,
	ultimateId: string,
	knockbackMultiplier: number,
	flyOn: boolean, -- the roller flies on through the player it hits
	untilAt: number, -- server time to forget it
}

-- Bubble Pop bounce (2026-10-16): past `at` studs along the flight the path goes on from `origin` along `dir`.
export type Bounce = { at: number, origin: Vector3, dir: Vector3 }

type Flight = {
	projId: number,
	kind: string, -- "volley" | "roller" | "bubble"
	casterId: number,
	model: Model?,
	shell: BasePart?,
	trail: Trail?,
	emitters: { ParticleEmitter },
	origin: Vector3,
	dir: Vector3,
	length: number,
	speed: number,
	releaseAt: number,
	floorY: number,
	flightScale: number,
	halfHeight: number, -- the roller's half height at scale 1
	endAt: number?, -- server time it ended (its ThrowImpact)
	endPosition: Vector3?,
	popped: boolean,
	bounce: Bounce?, -- the bubble's bounce (`length` is then both legs)
	bounced: boolean, -- batch B: its bounce look has played
}

type Drop = {
	position: Vector3,
	shadowAt: number,
	landAt: number,
	shadow: BasePart?,
	drop: BasePart?,
	landed: boolean,
	column: BasePart?, -- Geyser Line: its ice column after it erupts
	flame: BasePart?, -- Campfire Ring: its flame after it lights
	flameCore: BasePart?,
}

type Rain = {
	casterId: number,
	center: Vector3,
	floorY: number,
	releaseAt: number,
	zone: BasePart?,
	bunny: Model?,
	bunnyScale: number, -- the bunny's flight size
	from: Vector3,
	lobSeconds: number,
	arrived: boolean,
	drizzle: ParticleEmitter?,
	drops: { Drop },
	endsAt: number,
	-- Gravity Well (Cosmo, Series 01): the same show with the zone until the pop, Cosmo spinning over it and the
	-- beads spiralling in instead of the drops (drawn from its one drop's times).
	well: boolean,
	zoneSeconds: number,
	hoverSeconds: number,
	beads: { BasePart },
	-- Geyser Line (Frosty Box): no zone and no toy; each drop is a frost circle, then a geyser (dropHitRadius wide).
	geyser: boolean,
	geyserRadius: number,
	-- Campfire Ring (Lava Box): no zone and no toy; the slam ring, then each drop an ember glow and a flame.
	campfire: boolean,
	slammed: boolean,
}

-- Layer Cake Shockwave (Frosty Box, 2026-11-10): the landing spot, the leaping wyvern and the cake rings of one cast.
type CakeRing = { startAt: number, length: number, color: Color3, parts: { BasePart } }
type Shock = {
	casterId: number,
	center: Vector3, -- the caster's feet (the rings' centre, on the floor)
	startAt: number, -- server time the wind-up was drawn from
	landAt: number, -- the release (telegraphEndsAt)
	speed: number,
	from: Vector3,
	spot: BasePart?,
	toy: Model?,
	toyHalf: number, -- the toy's half height at its flight size
	landed: boolean,
	rings: { CakeRing },
	endsAt: number,
	-- Fondue Flood (Lava Box): a fan instead of rings (no toy, no spot).
	fan: boolean,
	dir: Vector3,
	halfAngle: number,
	length: number,
	tele: { BasePart },
	rim: { BasePart },
	flood: { BasePart },
	lastDrip: number,
}

type Cast = {
	casterId: number,
	ultimateId: string,
	stopCharge: ((fadeMs: number?) -> ())?,
}

-- Constants

local FX = Config.Vfx.Ultimates
local TEXTURES = Config.Vfx.Textures
local DROP_FADE_SECONDS = 0.15 -- reading: a drawn piece fades this long when its part of the show ends
local FORGET_AFTER_SECONDS = 5 -- reading: a projectile's info stays this long past its flight for late impacts
local RAIN_SHADOW_SECONDS = Config.Abilities.rain_check.shadowSeconds :: number -- set (Config.validate checks it)
local SHELL_NAME = "SD_UltBubble"
local LANE_NAME = "SD_UltLane"
local ZONE_NAME = "SD_UltZone"
local SHADOW_NAME = "SD_UltShadow"
local DROP_NAME = "SD_UltDrop"
local LANE_THICKNESS = 0.1
local DISC_THICKNESS = 0.1
local WELL_ID = "gravity_well" -- Cosmo's (Config.Abilities): a one-drop rain drawn as a well
local GEYSER_ID = "geyser_line" -- Gelato Narwhal's (Config.Abilities): a rain in a line drawn as geysers
local COLUMN_NAME = "SD_UltGeyser"
local CAMPFIRE_ID = "campfire_ring" -- Mallow Behemoth's (Config.Abilities): a rain on a ring drawn as flames
local FLAME_NAME = "SD_UltFlame"
local FAN_NAME = "SD_UltFondue"
local PUFF_ID = "puff_burst" -- Gummy Pufferfish's (Config.Abilities): a volley of gummy spikes in a full circle
local SPIKE_NAME = "SD_UltSpike"
local SPIKE_COLORS = { Palette.UltSpikePink, Palette.UltSpikeOrange, Palette.UltSpikeYellow, Palette.UltSpikeMint } -- design: sd/lab50.js:362
local PEN_ID = "prism_pen" -- Candyglass Qilin's (Config.Abilities): a one-drop rain whose area is a triangle
local PANEL_NAME = "SD_UltPrismPanel"
local PEN_COLORS = { Palette.UltPrismMint, Palette.UltPrismLilac, Palette.UltPrismPeach } -- design: sd/lab50.js:378
local FLAME_COLORS = { Palette.UltFlame, Palette.UltFlameHot, Palette.UltFlameCore } -- design: sd/lab50.js:355
local DRIP_COLORS = { Palette.UltFanTelegraph, Palette.UltFondueGlow, Palette.UltFondue } -- design: sd/lab50.js:335
local SPOT_NAME = "SD_UltCakeSpot"
local CAKE_NAME = "SD_UltCakeRing"
local CAKE_COLORS = { Palette.UltCakePink, Palette.UltCakeCream, Palette.UltCakeBlueberry } -- design: sd/lab50.js:310
local GEYSER_CUBES = { Palette.White, Palette.UltGeyserFrost, Palette.UltGeyserBlue } -- design: sd/lab50.js:302
local PETAL_COLORS = { Palette.UltCakePink, Palette.UltCakeSpot, Palette.White } -- design: sd/lab50.js:318
local WELL_RADIUS = Config.Abilities.gravity_well.radius :: number -- set (Config.validate checks it)
local BEAD_NAME = "SD_UltBead"
local BEAD_COLORS = {
	Palette.CosmoBeadPink,
	Palette.CosmoBeadGold,
	Palette.CosmoBeadMint,
	Palette.CosmoBeadBlue,
	Palette.CosmoBeadLilac,
	Palette.CosmoBeadPeach,
} -- design: sd/lab50.js:274
local SPRINKLE_COLORS = {
	Palette.White,
	Palette.UltSprinkleBlue,
	Palette.UltSprinkleYellow,
	Palette.UltSprinkleLane,
	Palette.UltSprinkleGreen,
} -- design: fp.js:243
local SOUND_RELEASE = "sfx.ultRelease"
local SOUND_HOVER = "sfx.ultCloudHover"
local SOUND_DROP = "sfx.ultRainDrop"
local SOUND_POP = "sfx.ultBubblePop"
local SOUND_BOUNCE = "sfx.pop" -- design: fp.js:239 (the Frog's bounce pass: sfx.pop())
local HEART_IMAGE = "img.kill.heart" -- the design's 'heart' burst shape (fp.js:239) as a particle
local SOUND_CHARGE_PREFIX = "sfx.ultCharge."
local OTHER_PRIORITY = -1 -- another player's ultimate sounds drop first (§18.6)
local BIG_PRIORITY = 3

-- Module table

local UltFx = {}

-- Private state

local casts: { [number]: Cast } = {}
local flights: { [number]: Flight } = {}
local infos: { [number]: ProjInfo } = {}
local rains: { Rain } = {}
local shocks: { [number]: Shock } = {} -- Layer Cake Shockwave, by caster
local lanes: { { part: BasePart, untilClock: number } } = {}
local deps: Deps? = nil

-- Pure helpers ------------------------------------------------------------------------------------------------------

-- The design's glide (fp.js:241): the server path plus sin(πk)·arc and sin(wobbleRate·k)·wobble up, k = t / duration.
function UltFx.glidePoint(origin: Vector3, dir: Vector3, speed: number, t: number, duration: number): Vector3
	local k = if duration > 0 then math.clamp(t / duration, 0, 1) else 1
	local lift = math.sin(math.pi * k) * FX.glideArcStuds + math.sin(k * FX.glideWobbleRate) * FX.glideWobbleStuds
	return origin + dir * speed * math.max(t, 0) + Vector3.new(0, lift, 0)
end

-- A plain sine arc over the server path (the bubble: fp.js:241, arc 0.9 m). Bubble Pop bounce (2026-10-16): with
-- `bounce` the path turns onto the bounce leg past bounce.at studs; the arc spans the whole flight (k = t / duration).
function UltFx.arcPoint(
	origin: Vector3,
	dir: Vector3,
	speed: number,
	t: number,
	duration: number,
	arc: number,
	bounce: Bounce?
): Vector3
	local k = if duration > 0 then math.clamp(t / duration, 0, 1) else 1
	local studs = speed * math.max(t, 0)
	local onPath = if bounce and studs > bounce.at
		then bounce.origin + bounce.dir * (studs - bounce.at)
		else origin + dir * studs
	return onPath + Vector3.new(0, math.sin(math.pi * k) * arc, 0)
end

-- Batch B (2026-10-17): whether a drawn bubble `along` seconds into its flight has reached its bounce (false without).
function UltFx.bouncePassed(speed: number, along: number, bounce: Bounce?): boolean
	return bounce ~= nil and speed * along >= bounce.at
end

-- The roller's scale t seconds after its release: rollerScaleFrom -> rollerScaleTo by the design's backOut.
function UltFx.rollerScale(t: number): number
	local u = math.clamp(t / FX.rollerGrowSeconds, 0, 1)
	return FX.rollerScaleFrom + (FX.rollerScaleTo - FX.rollerScaleFrom) * ViewmodelMath.backOut(u)
end

-- The lane plate: 2R wide, `length` long, on the floor (+ laneLift), centred on the lane, looking along it.
function UltFx.lanePlate(
	origin: Vector3,
	dir: Vector3,
	length: number,
	radius: number,
	floorY: number
): (CFrame, Vector3)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local along = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(0, 0, -1)
	local middle = Vector3.new(origin.X, floorY + FX.laneLift, origin.Z) + along * (length / 2)
	return CFrame.lookAt(middle, middle + along), Vector3.new(2 * radius, LANE_THICKNESS, length)
end

-- A drop t seconds into its fall from `top` to `to` (k², design: fp.js:371).
function UltFx.dropPoint(top: Vector3, to: Vector3, t: number, fall: number): Vector3
	local k = if fall > 0 then math.clamp(t / fall, 0, 1) else 1
	return top:Lerp(to, k * k)
end

-- 0..1, a sine pulse at `hz` (0.5 at t = 0).
function UltFx.pulse(t: number, hz: number): number
	return 0.5 + 0.5 * math.sin(2 * math.pi * hz * t)
end

-- Private ----------------------------------------------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function isReduced(): boolean
	local d = deps
	return d ~= nil and d.reduced()
end

local function play(key: string, at: Vector3?, casterId: number)
	local d = deps
	if d == nil then
		return
	end
	local localPlayer = Players.LocalPlayer
	local own = localPlayer ~= nil and localPlayer.UserId == casterId
	d.play(key, { at = at, priority = if own then BIG_PRIORITY else OTHER_PRIORITY })
end

local function rootOf(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function squishyOf(ultimateId: string): string?
	for _, def in Catalog.list() do
		if def.ultimateId == ultimateId then
			return def.id
		end
	end
	return nil
end

local function flightScaleOf(squishyId: string, radius: number): number
	local def = Catalog.get(squishyId)
	if def == nil or not (radius > 0) then
		return 1
	end
	local ok, scale = pcall(SquishyBuilder.flightScale, def.blueprintId, radius)
	return if ok and type(scale) == "number" and scale > 0 then scale else 1
end

local function newModel(squishyId: string, scale: number): Model?
	local ok, model = pcall(function(): Model?
		return SquishyCache.clone(squishyId, "World", scale)
	end)
	if not ok or typeof(model) ~= "Instance" then
		return nil
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	return model
end

local function fxFolder(): Instance
	local folder = Workspace:FindFirstChild("SD_ClientFx")
	return folder or Workspace
end

local function particleProps(color: Color3, size: number, lifetime: number, speed: number): FxPool.Props
	return {
		Texture = TEXTURES.smoke,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new(size, 0),
		Lifetime = NumberRange.new(lifetime * 0.7, lifetime * 1.3), -- design: fx.js:104-105
		Speed = NumberRange.new(speed * 0.45, speed * 1.2), -- design: fx.js:104
		SpreadAngle = Vector2.new(180, 180),
		Rate = 0,
	}
end

local function burst(
	at: Vector3,
	count: number,
	colors: { Color3 },
	size: number,
	lifetime: number,
	speed: number,
	gravity: number
)
	local pool = FxPool.default()
	local each = math.max(1, math.floor(count / #colors))
	for _, color in colors do
		local props = particleProps(color, size, lifetime, speed)
		props.Acceleration = Vector3.new(0, gravity, 0)
		pool:emit(at, each, props)
	end
end

local function releasePart(part: BasePart)
	FxPool.default():release(part)
end

local function endFlight(flight: Flight)
	local model = flight.model
	if model then
		flight.model = nil
		model:Destroy()
	end
	local shell = flight.shell
	if shell then
		flight.shell = nil
		shell:Destroy()
	end
	local trail = flight.trail
	if trail then
		flight.trail = nil
		FxPool.default():release(trail)
	end
	for _, emitter in flight.emitters do
		FxPool.default():release(emitter)
	end
	table.clear(flight.emitters)
	flights[flight.projId] = nil
end

local function pop(flight: Flight, at: Vector3)
	if flight.popped then
		return
	end
	flight.popped = true
	local floorPoint = Vector3.new(at.X, flight.floorY, at.Z)
	FxShapes.ring(
		floorPoint,
		Vector3.yAxis,
		FX.popRingToStuds,
		FX.popRingSeconds,
		Palette.UltBubblePop,
		FX.popTransparencyFrom
	)
	burst(
		at,
		FX.popPuffs,
		{ Palette.UltBubbleFoam, Palette.UltBubblePink, Palette.UltBubblePop },
		FX.popSize,
		FX.popLifetime,
		FX.popSpeed,
		FX.popGravity
	)
	play(SOUND_POP, at, flight.casterId)
end

-- Batch B (owner 2026-10-17): the Strawberry Frog's bounce pass (design: fp.js:239) where the bubble turns (`at`, the
-- drawn bubble): the hearts going up from it (the burst's normal (0, 1, 0): the upper half only), the white ring on
-- the floor under it, sfx.pop.
local function bounceLook(flight: Flight, at: Vector3)
	FxShapes.ring(
		Vector3.new(at.X, flight.floorY, at.Z),
		Vector3.yAxis,
		FX.bounceRingToStuds,
		FX.bounceRingSeconds,
		Palette.White,
		FX.bounceTransparencyFrom
	)
	local pool = FxPool.default()
	local colors = { Palette.UltBounceHeartRed, Palette.UltBounceHeartGreen }
	local each = math.max(1, math.floor(FX.bounceHearts / #colors))
	for _, color in colors do
		local props = particleProps(color, FX.bounceHeartSize, FX.bounceHeartLifetime, FX.bounceHeartSpeed)
		props.Texture = AssetTable.image(HEART_IMAGE) or TEXTURES.smoke
		props.SpreadAngle = Vector2.new(90, 90)
		pool:emit(at, each, props)
	end
	play(SOUND_BOUNCE, at, flight.casterId)
end

local function attachTrail(flight: Flight, root: BasePart, squishyId: string)
	local def = Catalog.get(squishyId)
	local style = if def then RarityStyle.trail(def.visuals.trail) else nil
	if def == nil or style == nil then
		return
	end
	local accent = Color3.fromHex(def.visuals.accent)
	local half = style.width / 2
	flight.trail = FxPool.default():acquireTrail(root, Vector3.new(0, half, 0), Vector3.new(0, -half, 0), {
		Lifetime = style.lifetime,
		Transparency = NumberSequence.new(style.transparencyFrom, style.transparencyTo),
		WidthScale = NumberSequence.new(1, style.widthScaleTo),
		Color = RarityStyle.trailColorSequence(style.kind, accent),
		FaceCamera = style.faceCamera,
		MaxLength = style.maxLength,
		LightEmission = style.lightEmission,
	})
end

-- Puff Burst (2026-11-10; design: sd/lab50.js:364): one gummy spike, a capsule along its flight (its look Z axis).
local function spikeModel(color: Color3): Model
	local model = Instance.new("Model")
	model.Name = SPIKE_NAME
	local part = Instance.new("Part")
	part.Name = SPIKE_NAME
	part.Size = Vector3.new(FX.spikeWidthStuds, FX.spikeWidthStuds, FX.spikeLengthStuds)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = model
	model.PrimaryPart = part
	return model
end

-- Puff Burst's lanes: the flat directions of a full-circle volley (UltRules.volleyDirs: the first on the aim).
local function circleDirs(dir: Vector3, count: number): { Vector3 }
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local aim = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.new(0, 0, -1)
	local dirs: { Vector3 } = {}
	for index = 0, count - 1 do
		dirs[index + 1] = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(360 * index / count)):VectorToWorldSpace(aim)
	end
	return dirs
end

local function newFlight(
	kind: string,
	casterId: number,
	squishyId: string,
	projId: number,
	origin: Vector3,
	dir: Vector3,
	length: number,
	speed: number,
	radius: number,
	releaseAt: number,
	floorY: number,
	spike: Color3? -- Puff Burst (2026-11-10): a gummy spike of this colour instead of the toy
): Flight
	local flightScale = if spike
		then 1
		else flightScaleOf(squishyId, if kind == "roller" then radius / FX.rollerScaleTo else radius)
	local flight: Flight = {
		projId = projId,
		kind = kind,
		casterId = casterId,
		model = if spike then spikeModel(spike) else newModel(squishyId, flightScale),
		shell = nil,
		trail = nil,
		emitters = {},
		origin = origin,
		dir = dir,
		length = length,
		speed = math.max(speed, 1e-3),
		releaseAt = releaseAt,
		floorY = floorY,
		flightScale = flightScale,
		halfHeight = 0,
		endAt = nil,
		endPosition = nil,
		popped = false,
		bounce = nil,
		bounced = false,
	}
	local model = flight.model
	if model then
		flight.halfHeight = model:GetExtentsSize().Y / 2 / math.max(flightScale, 1e-3)
		model.Parent = fxFolder()
		local root = model.PrimaryPart
		if root and kind == "volley" and spike == nil then
			attachTrail(flight, root, squishyId)
		end
	end
	if kind == "bubble" then
		local shell = Instance.new("Part")
		shell.Name = SHELL_NAME
		shell.Shape = Enum.PartType.Ball
		shell.Size = Vector3.one * (2 * FX.bubbleRadius)
		shell.Color = Palette.UltBubbleShell
		shell.Transparency = FX.bubbleTransparency
		shell.Material = Enum.Material.SmoothPlastic
		shell.Anchored = true
		shell.CanCollide = false
		shell.CanQuery = false
		shell.CanTouch = false
		shell.CastShadow = false
		shell.CFrame = CFrame.new(origin)
		shell.Parent = fxFolder()
		flight.shell = shell
	elseif kind == "roller" then
		local pool = FxPool.default()
		for _, color in SPRINKLE_COLORS do
			local props = particleProps(color, FX.sprinkleSize, FX.sprinkleLifetime, FX.sprinkleSpeedMax)
			props.Speed = NumberRange.new(FX.sprinkleSpeedMin, FX.sprinkleSpeedMax)
			props.SpreadAngle = Vector2.new(35, 35)
			props.Acceleration = Vector3.new(0, FX.sprinkleGravity, 0)
			props.Rate = FX.sprinkleChance * 60 / #SPRINKLE_COLORS -- the design's 90% a frame at 60 fps, shared
			props.Texture = TEXTURES.sparkles
			local emitter = pool:acquireEmitter(props)
			table.insert(flight.emitters, emitter)
		end
	end
	flights[projId] = flight
	return flight
end

local function stepFlight(flight: Flight, now: number): boolean
	local t = now - flight.releaseAt
	local duration = flight.length / flight.speed
	local model = flight.model
	local reduced = isReduced()
	if t < 0 then
		if model then
			model:PivotTo(CFrame.new(0, -1000, 0)) -- out of sight until its release
		end
		return true
	end
	local endAt = flight.endAt
	if endAt ~= nil and now >= endAt then
		if flight.kind == "bubble" then
			pop(
				flight,
				flight.endPosition
					or UltFx.arcPoint(
						flight.origin,
						flight.dir,
						flight.speed,
						t,
						duration,
						FX.bubbleArcStuds,
						flight.bounce
					)
			)
		end
		endFlight(flight)
		return false
	end
	if t > duration + FX.lingerSeconds then
		if flight.kind == "bubble" then
			-- the path's end (arc 0 there), past the bounce when it has one
			pop(flight, UltFx.arcPoint(flight.origin, flight.dir, flight.speed, duration, duration, 0, flight.bounce))
		end
		endFlight(flight)
		return false
	end
	local along = math.min(t, duration)
	local position: Vector3
	local frame: CFrame
	if flight.kind == "volley" then
		position = UltFx.glidePoint(flight.origin, flight.dir, flight.speed, along, duration)
		local roll = if reduced then 0 else FX.glideRollRad * math.sin(FX.glideRollRate * t)
		frame = CFrame.lookAt(position, position + flight.dir) * CFrame.Angles(0, 0, roll)
		if model then
			local grow = math.clamp(t / FX.growSeconds, 0, 1)
			local scale = flight.flightScale * (FX.growFrom + (1 - FX.growFrom) * grow)
			if math.abs(model:GetScale() - scale) > 1e-3 then
				model:ScaleTo(scale)
			end
		end
	elseif flight.kind == "roller" then
		local scale = UltFx.rollerScale(t)
		local onFloor = flight.origin + flight.dir * flight.speed * along
		position = Vector3.new(onFloor.X, flight.floorY + flight.halfHeight * flight.flightScale * scale, onFloor.Z)
		local side = flight.dir:Cross(Vector3.yAxis)
		local spin = math.rad(FX.rollerSpinDegPerSecond) * t
		local tilt = FX.rollerTiltRad
			+ (if reduced then 0 else FX.rollerTiltWobbleRad * math.sin(FX.rollerTiltRate * t))
		frame = CFrame.fromAxisAngle(flight.dir, tilt) * CFrame.lookAt(position, position + side).Rotation
		frame = CFrame.new(position) * frame.Rotation * CFrame.Angles(0, 0, -spin)
		if model then
			local wanted = flight.flightScale * scale
			if math.abs(model:GetScale() - wanted) > 1e-3 then
				model:ScaleTo(wanted)
			end
		end
		for _, emitter in flight.emitters do
			local attachment = emitter.Parent
			if attachment and attachment:IsA("Attachment") then
				attachment.WorldCFrame = CFrame.new(position)
			end
			emitter.Enabled = t <= duration
		end
	else -- bubble
		local bounce = flight.bounce
		position = UltFx.arcPoint(flight.origin, flight.dir, flight.speed, along, duration, FX.bubbleArcStuds, bounce)
		local heading = if bounce and flight.speed * along > bounce.at then bounce.dir else flight.dir
		frame = CFrame.lookAt(position, position + heading)
		if not flight.bounced and UltFx.bouncePassed(flight.speed, along, bounce) then
			flight.bounced = true
			bounceLook(flight, position)
		end
		local shell = flight.shell
		if shell then
			shell.CFrame = CFrame.new(position)
		end
	end
	if model then
		model:PivotTo(frame)
	end
	return true
end

local function makeDisc(name: string, center: Vector3, radius: number, color: Color3, transparency: number): BasePart
	local part = FxPool.default():acquirePart({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(DISC_THICKNESS, 2 * radius, 2 * radius),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), -- a cylinder lies along X: stand it on its side
		Color = color,
		Transparency = transparency,
		Material = Enum.Material.SmoothPlastic,
	})
	return part
end

local function startRain(
	event: Types.UltimateEventPayload,
	ability: any,
	squishyId: string,
	well: boolean,
	geyser: boolean,
	campfire: boolean
)
	local center = event.center
	local drops = event.drops
	if center == nil or drops == nil then
		return
	end
	local floorY = center.Y
	local releaseAt = event.telegraphEndsAt
	local casterRoot = rootOf(event.casterId)
	local from = if casterRoot then casterRoot.Position + Vector3.new(0, 1.8, 0) else event.origin
	local top = center + Vector3.new(0, if well then FX.wellHoverStuds else FX.bunnyHeight, 0)
	-- The well: Cosmo reaches its spot in the design's 0.5 s whatever the distance (sd/lab50.js:280).
	local lobSeconds = if well then FX.wellLobSeconds else (top - from).Magnitude / math.max(ability.speed, 1)
	local def = Catalog.get(squishyId)
	local bunnyScale = flightScaleOf(squishyId, if def then def.throw.radius else 1) -- the toy at its flight size
	-- The well's zone and hover last until its pop (its one drop's landAt).
	local popIn = if well and drops[1] then math.max(drops[1].landAt - releaseAt, 0) else 0
	local rain: Rain = {
		casterId = event.casterId,
		center = center,
		floorY = floorY,
		releaseAt = releaseAt,
		zone = if geyser or campfire
			then nil
			else makeDisc(
				ZONE_NAME,
				center + Vector3.new(0, FX.laneLift, 0),
				ability.radius,
				if well then Palette.UltWellZone else Palette.UltRainZone,
				1
			),
		bunny = if geyser or campfire then nil else newModel(squishyId, bunnyScale),
		bunnyScale = bunnyScale,
		from = from,
		lobSeconds = lobSeconds,
		arrived = false,
		drizzle = nil,
		drops = {},
		endsAt = releaseAt + math.max(FX.zoneSeconds, lobSeconds + FX.hoverSeconds),
		well = well,
		zoneSeconds = if well then popIn else FX.zoneSeconds,
		hoverSeconds = if well then math.max(popIn - lobSeconds, 0) else FX.hoverSeconds,
		beads = {},
		geyser = geyser,
		geyserRadius = ability.dropHitRadius or ability.radius,
		campfire = campfire,
		slammed = false,
	}
	if geyser or campfire then
		rain.endsAt = releaseAt -- no zone and no toy over it (design: sd/lab50.js:295-307): only circles and geysers
	end
	if well then
		rain.endsAt = releaseAt + popIn + FX.wellRingLilacSeconds
		for index = 1, FX.wellBeadCount do
			table.insert(
				rain.beads,
				FxPool.default():acquirePart({
					Name = BEAD_NAME,
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * (2 * FX.wellBeadRadius),
					Color = BEAD_COLORS[(index - 1) % #BEAD_COLORS + 1],
					CFrame = CFrame.new(center),
					Transparency = 0,
					Material = Enum.Material.SmoothPlastic,
				})
			)
		end
	end
	for _, drop in drops do
		table.insert(rain.drops, {
			position = drop.position,
			shadowAt = drop.shadowAt,
			landAt = drop.landAt,
			shadow = nil,
			drop = nil,
			landed = false,
		})
		rain.endsAt = math.max(
			rain.endsAt,
			drop.landAt
				+ (
					if geyser
						then math.max(FX.geyserColumnSeconds, FX.geyserRingSeconds)
						elseif campfire then FX.campfireFlameSeconds
						else FX.splashRingSeconds
				)
		)
	end
	local bunny = rain.bunny
	if bunny then
		bunny.Parent = fxFolder()
	end
	table.insert(rains, rain)
end

local function stepRain(rain: Rain, now: number): boolean
	local t = now - rain.releaseAt
	local reduced = isReduced()
	local zone = rain.zone
	local zoneSeconds = math.max(rain.zoneSeconds, 1e-3)
	if zone then
		if t > zoneSeconds then
			rain.zone = nil
			releasePart(zone)
		else
			local s = if reduced then 0.5 else UltFx.pulse(t, FX.zonePulseHz)
			local opacity = FX.zoneOpacity * FX.zoneFill * (0.55 + 0.45 * s) -- design: fx.js:146-151
			-- Rain Check fades over its last 15%; the well stays bright until its pop.
			local fade = if rain.well then 1 else math.clamp((zoneSeconds - t) / (zoneSeconds * 0.15), 0, 1)
			zone.Transparency = 1 - opacity * fade
		end
	end
	local bunny = rain.bunny
	if bunny then
		local top = rain.center + Vector3.new(0, if rain.well then FX.wellHoverStuds else FX.bunnyHeight, 0)
		if t < rain.lobSeconds then
			local k = math.clamp(t / rain.lobSeconds, 0, 1)
			local p = rain.from:Lerp(top, k) + Vector3.new(0, math.sin(math.pi * k) * FX.bunnyArcStuds, 0)
			bunny:PivotTo(CFrame.new(p))
		else
			local ht = t - rain.lobSeconds
			if not rain.arrived and rain.well then
				rain.arrived = true -- the well: no hover sound, no drizzle (the design spins Cosmo over the zone)
			elseif not rain.arrived then
				rain.arrived = true
				play(SOUND_HOVER, top, rain.casterId)
				local props = particleProps(Palette.UltRainDrizzle, FX.drizzleSize, FX.drizzleLifetime, FX.drizzleSpeed)
				props.Rate = FX.drizzleRate
				props.SpreadAngle = Vector2.new(0, 0)
				props.EmissionDirection = Enum.NormalId.Bottom
				props.Acceleration = Vector3.new(0, FX.drizzleGravity, 0)
				props.Shape = Enum.ParticleEmitterShape.Box
				local emitter = FxPool.default():acquireEmitter(props)
				local attachment = emitter.Parent
				if attachment and attachment:IsA("Attachment") then
					attachment.WorldCFrame = CFrame.new(top - Vector3.new(0, FX.drizzleDropStuds, 0))
				end
				emitter.Enabled = true
				rain.drizzle = emitter
			end
			if ht > rain.hoverSeconds then
				rain.bunny = nil
				bunny:Destroy()
				local drizzle = rain.drizzle
				if drizzle then
					rain.drizzle = nil
					FxPool.default():release(drizzle)
				end
			elseif rain.well then
				-- design: sd/lab50.js:282 (a small bob, spinning 9 rad/s)
				local bob = if reduced then 0 else 0.03 / 0.28 * math.sin(ht * 8)
				local spin = if reduced then 0 else ht * FX.wellSpinRate
				bunny:PivotTo(CFrame.new(top + Vector3.new(0, bob, 0)) * CFrame.Angles(0, spin, 0))
			else
				local grow = 1 + FX.bunnyGrow * ViewmodelMath.backOut(math.clamp(ht / FX.bunnyGrowSeconds, 0, 1))
				local wanted = rain.bunnyScale * grow
				if math.abs(bunny:GetScale() - wanted) > 1e-3 then
					bunny:ScaleTo(wanted)
				end
				local bob = if reduced then 0 else math.sin(ht * FX.bunnyBobRate) * FX.bunnyBobStuds
				local roll = if reduced then 0 else 0.08 * math.sin(2 * ht) -- design: fp.js:266
				bunny:PivotTo(CFrame.new(top + Vector3.new(0, bob, 0)) * CFrame.Angles(0, ht * 0.6, roll))
			end
		end
	end
	if rain.campfire and not rain.slammed and now >= rain.releaseAt + FX.campfireSlamAt then
		-- design: sd/lab50.js:349. The slam: a ring from the caster out to the flames' ring.
		rain.slammed = true
		local first = rain.drops[1]
		local reach = if first then Vector3.new(first.position.X - rain.center.X, 0, first.position.Z - rain.center.Z).Magnitude else 1
		FxShapes.ring(
			Vector3.new(rain.center.X, rain.floorY, rain.center.Z),
			Vector3.yAxis,
			2 * reach,
			FX.campfireSlamSeconds,
			Palette.UltFlame,
			FX.campfireSlamTransparencyFrom
		)
		play(SOUND_POP, rain.center, rain.casterId)
	end
	for _, drop in rain.drops do
		if rain.campfire then
			-- design: sd/lab50.js:351-355. The ember glow pulses from shadowAt until the flame lights at landAt; the flame then
			-- rises and falls (sin(uπ) of its size over campfireFlameSeconds) and the embers burst.
			local floorPoint = Vector3.new(drop.position.X, rain.floorY, drop.position.Z)
			if not drop.landed and now >= drop.shadowAt and now < drop.landAt then
				local glow = drop.shadow
				if glow == nil then
					glow = makeDisc(
						SHADOW_NAME,
						floorPoint + Vector3.new(0, FX.laneLift * 2, 0),
						rain.geyserRadius,
						Palette.UltFlameHot,
						1
					)
					drop.shadow = glow
				end
				local s = if reduced then 0.5 else UltFx.pulse(now - drop.shadowAt, FX.campfireGlowHz);
				(glow :: BasePart).Transparency = 1 - FX.campfireGlowOpacity * (0.55 + 0.45 * s)
			elseif not drop.landed and now >= drop.landAt then
				drop.landed = true
				local glow = drop.shadow
				drop.shadow = nil
				if glow then
					releasePart(glow)
				end
				drop.flame = FxPool.default():acquirePart({
					Name = FLAME_NAME,
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 0.05,
					CFrame = CFrame.new(floorPoint),
					Color = Palette.UltFlame,
					Transparency = 0,
					Material = Enum.Material.Neon,
				})
				drop.flameCore = FxPool.default():acquirePart({
					Name = FLAME_NAME,
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 0.05,
					CFrame = CFrame.new(floorPoint),
					Color = Palette.UltFlameCore,
					Transparency = 0,
					Material = Enum.Material.Neon,
				})
				burst(
					floorPoint + Vector3.new(0, 0.2 / 0.28, 0),
					FX.campfireEmbers,
					FLAME_COLORS,
					FX.campfireEmberSize,
					FX.campfireEmberLifetime,
					FX.campfireEmberSpeed,
					FX.campfireEmberGravity
				)
				play(SOUND_DROP, floorPoint, rain.casterId)
			end
			local flame, core = drop.flame, drop.flameCore
			if flame and core then
				local u = (now - drop.landAt) / FX.campfireFlameSeconds
				if u >= 1 then
					drop.flame = nil
					drop.flameCore = nil
					releasePart(flame)
					releasePart(core)
				else
					local s = math.sin(math.clamp(u, 0, 1) * math.pi)
					local w = math.max(0.05, 2 * rain.geyserRadius * FX.campfireFlameWidthShare * s)
					flame.Size = Vector3.one * w
					flame.CFrame = CFrame.new(floorPoint + Vector3.new(0, w / 2, 0))
					local c = math.max(0.05, w * FX.campfireCoreShare)
					core.Size = Vector3.one * c
					core.CFrame = CFrame.new(floorPoint + Vector3.new(0, w * 0.8 + c * 0.35, 0)) -- the flame's bright tip
				end
			end
			continue
		end
		if rain.geyser then
			-- design: sd/lab50.js:300-304. The frost circle pulses until the eruption; then the column rises and sinks
			-- (sin(uπ) of its height over geyserColumnSeconds), the cubes burst, the white ring opens.
			local floorPoint = Vector3.new(drop.position.X, rain.floorY, drop.position.Z)
			if not drop.landed and now >= drop.shadowAt and now < drop.landAt then
				local circle = drop.shadow
				if circle == nil then
					circle = makeDisc(
						SHADOW_NAME,
						floorPoint + Vector3.new(0, FX.laneLift * 2, 0),
						rain.geyserRadius,
						Palette.UltGeyserFrost,
						1
					)
					drop.shadow = circle
				end
				local s = if reduced then 0.5 else UltFx.pulse(now - drop.shadowAt, FX.zonePulseHz);
				(circle :: BasePart).Transparency = 1 - FX.geyserCircleOpacity * FX.zoneFill * 2 * (0.55 + 0.45 * s)
			elseif not drop.landed and now >= drop.landAt then
				drop.landed = true
				local circle = drop.shadow
				drop.shadow = nil
				if circle then
					releasePart(circle)
				end
				drop.column = FxPool.default():acquirePart({
					Name = COLUMN_NAME,
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(0.05, 2 * rain.geyserRadius * FX.geyserColumnShare, 2 * rain.geyserRadius * FX.geyserColumnShare),
					CFrame = CFrame.new(floorPoint) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Palette.UltGeyserColumn,
					Transparency = 0.15,
					Material = Enum.Material.Ice,
				})
				burst(
					floorPoint + Vector3.new(0, 0.15 / 0.28, 0),
					FX.geyserCubes,
					GEYSER_CUBES,
					FX.geyserCubeSize,
					FX.geyserCubeLifetime,
					FX.geyserCubeSpeed,
					FX.geyserCubeGravity
				)
				FxShapes.ring(
					floorPoint,
					Vector3.yAxis,
					2 * rain.geyserRadius * FX.geyserRingScale,
					FX.geyserRingSeconds,
					Palette.White,
					FX.geyserRingTransparencyFrom
				)
				play(SOUND_DROP, floorPoint, rain.casterId)
			end
			local column = drop.column
			if column then
				local u = (now - drop.landAt) / FX.geyserColumnSeconds
				if u >= 1 then
					drop.column = nil
					releasePart(column)
				else
					local h = math.max(0.05, math.sin(math.clamp(u, 0, 1) * math.pi) * FX.geyserColumnHeight)
					local width = 2 * rain.geyserRadius * FX.geyserColumnShare
					column.Size = Vector3.new(h, width, width)
					column.CFrame = CFrame.new(floorPoint + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
				end
			end
			continue
		end
		if drop.landed then
			continue
		end
		if rain.well then
			-- design: sd/lab50.js:283-291. The beads spiral in from the ring (radius R·(1 - pull·k²), spinning faster);
			-- at the pop: the stars, a gold and a lilac ring and the pop sound.
			local span = math.max(drop.landAt - rain.releaseAt, 1e-3)
			if now >= drop.landAt then
				drop.landed = true
				for _, bead in rain.beads do
					releasePart(bead)
				end
				table.clear(rain.beads)
				local at = Vector3.new(drop.position.X, rain.floorY, drop.position.Z)
				FxShapes.ring(
					at,
					Vector3.yAxis,
					FX.wellRingGoldTo,
					FX.wellRingGoldSeconds,
					Palette.UltWellGold,
					FX.wellRingTransparencyFrom
				)
				FxShapes.ring(
					at,
					Vector3.yAxis,
					FX.wellRingLilacTo,
					FX.wellRingLilacSeconds,
					Palette.CosmoBeadLilac,
					FX.wellRingTransparencyFrom
				)
				burst(
					at + Vector3.new(0, 0.35 / 0.28, 0),
					FX.wellPopStars,
					BEAD_COLORS,
					FX.wellPopSize,
					FX.wellPopLifetime,
					FX.wellPopSpeed,
					FX.wellPopGravity
				)
				play(SOUND_POP, at, rain.casterId)
				continue
			end
			local ts = math.max(now - rain.releaseAt, 0)
			local k = math.clamp(ts / span, 0, 1)
			local ring = (1 - FX.wellBeadPull * k * k) * WELL_RADIUS
			-- angle: ∫(spin + gain·k) dt = spin·t + gain·t²/(2·span)
			local swept = FX.wellBeadSpin * ts + FX.wellBeadSpinGain * ts * ts / (2 * span)
			for index, bead in rain.beads do
				local a = (index - 1) / #rain.beads * 2 * math.pi + swept
				local bob = if reduced then 0 else FX.wellBeadBobStuds * math.sin(2 * a)
				bead.CFrame = CFrame.new(
					drop.position.X + math.cos(a) * ring,
					rain.floorY + FX.wellBeadHeight + bob,
					drop.position.Z + math.sin(a) * ring
				)
			end
			continue
		end
		if now >= drop.landAt then
			drop.landed = true
			local shadow, part = drop.shadow, drop.drop
			drop.shadow, drop.drop = nil, nil
			if shadow then
				releasePart(shadow)
			end
			if part then
				releasePart(part)
			end
			local at = Vector3.new(drop.position.X, rain.floorY, drop.position.Z)
			FxShapes.ring(
				at,
				Vector3.yAxis,
				FX.splashRingToStuds,
				FX.splashRingSeconds,
				Palette.UltRainDrop,
				FX.splashTransparencyFrom
			)
			burst(
				at,
				FX.splashPuffs,
				{ Palette.UltRainDrop, Palette.White },
				FX.splashSize,
				FX.splashLifetime,
				FX.splashSpeed,
				0
			)
			play(SOUND_DROP, at, rain.casterId)
			continue
		end
		local shadowEnds = drop.shadowAt + RAIN_SHADOW_SECONDS
		if now >= drop.shadowAt and now < shadowEnds then
			local shadow = drop.shadow
			if shadow == nil then
				shadow = makeDisc(
					SHADOW_NAME,
					drop.position + Vector3.new(0, FX.laneLift * 2, 0),
					FX.shadowRadius,
					Palette.UltRainShadow,
					1
				)
				drop.shadow = shadow
			end
			local s = if reduced then 0.5 else UltFx.pulse(now - drop.shadowAt, FX.shadowPulseHz);
			(shadow :: BasePart).Transparency = 1 - FX.shadowOpacity * (0.55 + 0.45 * s)
		elseif now >= shadowEnds then
			local shadow = drop.shadow
			if shadow then
				drop.shadow = nil
				releasePart(shadow)
			end
			local part = drop.drop
			if part == nil then
				part = FxPool.default():acquirePart({
					Name = DROP_NAME,
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * (2 * FX.dropRadius),
					Color = Palette.UltRainDrop,
					Transparency = 0,
					Material = Enum.Material.SmoothPlastic,
				})
				drop.drop = part
			end
			local topPoint = Vector3.new(
				rain.center.X,
				rain.floorY + Config.Abilities.rain_check.laneHeightAboveFloor,
				rain.center.Z
			)
			local at = UltFx.dropPoint(topPoint, drop.position, now - shadowEnds, drop.landAt - shadowEnds);
			(part :: BasePart).CFrame = CFrame.new(at)
		end
	end
	return now < rain.endsAt + DROP_FADE_SECONDS
end

-- Layer Cake Shockwave (Frosty Box, 2026-11-10; design: sd/lab50.js:309-325): the cast's spot and wyvern from the wind-up.
local function startShock(event: Types.UltimateEventPayload, ability: any, squishyId: string): Shock
	local casterRoot = rootOf(event.casterId)
	local center = event.origin
	if ability.fill then
		-- Fondue Flood: no toy and no spot; the fan outline shows through the wind-up (design: sd/lab50.js:326-332).
		local aim = Vector3.new(event.dir.X, 0, event.dir.Z)
		local fanShock: Shock = {
			casterId = event.casterId,
			center = center,
			startAt = math.min(serverNow(), event.telegraphEndsAt),
			landAt = event.telegraphEndsAt,
			speed = math.max(ability.speed, 1e-3),
			from = center,
			spot = nil,
			toy = nil,
			toyHalf = 0,
			landed = false,
			rings = {},
			endsAt = event.telegraphEndsAt + FX.fanSinkFrom + FX.fanSinkSeconds,
			fan = true,
			dir = if aim.Magnitude > 1e-6 then aim.Unit else Vector3.zAxis,
			halfAngle = math.rad((ability.fanDeg or 120) / 2),
			length = ability.maxLength,
			tele = {},
			rim = {},
			flood = {},
			lastDrip = 0,
		}
		shocks[event.casterId] = fanShock
		return fanShock
	end
	local def = Catalog.get(squishyId)
	local toyScale = flightScaleOf(squishyId, if def then def.throw.radius else 1)
	local toy = newModel(squishyId, toyScale)
	local toyHalf = 0.5
	if toy then
		local _, size = toy:GetBoundingBox()
		toyHalf = size.Y / 2
		toy.Parent = fxFolder()
	end
	local now = serverNow()
	local shock: Shock = {
		casterId = event.casterId,
		center = center,
		startAt = math.min(now, event.telegraphEndsAt),
		landAt = event.telegraphEndsAt,
		speed = math.max(ability.speed, 1e-3),
		from = if casterRoot then casterRoot.Position + Vector3.new(0, 1.8, 0) else center + Vector3.new(0, 3, 0),
		spot = makeDisc(SPOT_NAME, center + Vector3.new(0, FX.laneLift * 2, 0), FX.shockSpotRadius, Palette.UltCakeSpot, 1),
		toy = toy,
		toyHalf = toyHalf,
		landed = false,
		rings = {},
		endsAt = event.telegraphEndsAt + FX.shockReturnAfter + FX.shockReturnSeconds,
		fan = false,
		dir = Vector3.zAxis,
		halfAngle = 0,
		length = 0,
		tele = {},
		rim = {},
		flood = {},
		lastDrip = 0,
	}
	shocks[event.casterId] = shock
	return shock
end

local function endShock(shock: Shock)
	local spot = shock.spot
	shock.spot = nil
	if spot then
		releasePart(spot)
	end
	local toy = shock.toy
	shock.toy = nil
	if toy then
		toy:Destroy()
	end
	for _, ring in shock.rings do
		for _, part in ring.parts do
			releasePart(part)
		end
		table.clear(ring.parts)
	end
	for _, list in { shock.tele, shock.rim, shock.flood } do
		for _, part in list do
			releasePart(part)
		end
		table.clear(list)
	end
	if shocks[shock.casterId] == shock then
		shocks[shock.casterId] = nil
	end
end

-- One ring's wall at radius `r` (its pieces made on first use): each piece a chord of the circle facing the centre.
local function placeRing(shock: Shock, ring: CakeRing, r: number, fade: number)
	local n = FX.shockRingSegments
	if #ring.parts == 0 then
		for _ = 1, n do
			table.insert(
				ring.parts,
				FxPool.default():acquirePart({
					Name = CAKE_NAME,
					Size = Vector3.one,
					CFrame = CFrame.new(shock.center),
					Color = ring.color,
					Transparency = 0,
					Material = Enum.Material.SmoothPlastic,
				})
			)
		end
	end
	local chord = 2 * r * math.sin(math.pi / n) * 1.05
	local middle = shock.center + Vector3.new(0, FX.shockRingHeight / 2, 0)
	for index, part in ring.parts do
		local a = (index - 1) / n * 2 * math.pi
		local p = middle + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		part.Size = Vector3.new(math.max(chord, 0.05), FX.shockRingHeight, FX.shockRingThickness)
		part.CFrame = CFrame.lookAt(p, middle)
		part.Transparency = 1 - fade
	end
end

-- The fan's slices at radius `r` (made on first use): each a flat slice from the centre along its bisector.
local function placeFan(shock: Shock, parts: { BasePart }, r: number, color: Color3, transparency: number, lift: number)
	local n = FX.fanSlices
	if #parts == 0 then
		for _ = 1, n do
			table.insert(
				parts,
				FxPool.default():acquirePart({
					Name = FAN_NAME,
					Size = Vector3.one,
					CFrame = CFrame.new(shock.center),
					Color = color,
					Transparency = 1,
					Material = Enum.Material.SmoothPlastic,
				})
			)
		end
	end
	local a0 = math.atan2(shock.dir.Z, shock.dir.X)
	local step = 2 * shock.halfAngle / n
	local width = math.max(2 * r * math.sin(step / 2) * 1.08, 0.05)
	for index, part in parts do
		local a = a0 - shock.halfAngle + (index - 0.5) * step
		local along = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = shock.center + along * (r / 2) + Vector3.new(0, lift, 0)
		part.Size = Vector3.new(width, FX.fanThickness, math.max(r, 0.05))
		part.CFrame = CFrame.lookAt(p, p + along)
		part.Transparency = transparency
	end
end

-- The fan's bright rim at its edge (the two sides and the arc), as thin pieces (vault: a warning reads with a rim).
local function placeRim(shock: Shock, transparency: number)
	local n = FX.fanSlices
	if #shock.rim == 0 then
		for _ = 1, n + 2 do
			table.insert(
				shock.rim,
				FxPool.default():acquirePart({
					Name = FAN_NAME,
					Size = Vector3.one,
					CFrame = CFrame.new(shock.center),
					Color = Palette.White,
					Transparency = 1,
					Material = Enum.Material.Neon,
				})
			)
		end
	end
	local r = shock.length
	local a0 = math.atan2(shock.dir.Z, shock.dir.X)
	local step = 2 * shock.halfAngle / n
	local lift = Vector3.new(0, FX.laneLift * 3, 0)
	for index = 1, n do
		local a = a0 - shock.halfAngle + (index - 0.5) * step
		local p = shock.center + Vector3.new(math.cos(a), 0, math.sin(a)) * r + lift
		local part = shock.rim[index]
		part.Size = Vector3.new(2 * r * math.sin(step / 2) * 1.05, FX.fanThickness, FX.fanRimStuds)
		part.CFrame = CFrame.lookAt(p, shock.center + lift)
		part.Transparency = transparency
	end
	for side = 0, 1 do
		local a = a0 + (if side == 0 then -shock.halfAngle else shock.halfAngle)
		local along = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = shock.center + along * (r / 2) + lift
		local part = shock.rim[n + 1 + side]
		part.Size = Vector3.new(FX.fanRimStuds, FX.fanThickness, r)
		part.CFrame = CFrame.lookAt(p, p + along)
		part.Transparency = transparency
	end
end

-- Fondue Flood: the outline through the wind-up, then the flood (design: sd/lab50.js:330-338).
local function stepFan(shock: Shock, now: number): boolean
	local reduced = isReduced()
	if now < shock.landAt then
		local s = if reduced then 0.5 else UltFx.pulse(now - shock.startAt, FX.fanTelePulseHz)
		local opacity = FX.fanTeleOpacity * (0.75 + 0.25 * s)
		placeFan(shock, shock.tele, shock.length, Palette.UltFanTelegraph, 1 - opacity, FX.laneLift * 2)
		placeRim(shock, 1 - math.min(1, opacity * 2.5))
		return true
	end
	if not shock.landed then
		shock.landed = true
		for _, list in { shock.tele, shock.rim } do
			for _, part in list do
				releasePart(part)
			end
			table.clear(list)
		end
		play(SOUND_DROP, shock.center, shock.casterId)
	end
	local t = now - shock.landAt
	local r = math.min(math.max(shock.speed * t, 0.05), shock.length)
	local k = math.clamp((t - FX.fanSinkFrom) / FX.fanSinkSeconds, 0, 1)
	placeFan(shock, shock.flood, r * (1 - FX.fanShrink * k), Palette.UltFondue, k, FX.laneLift * 2 - FX.fanSinkStuds * k)
	if r < shock.length and not reduced and now - shock.lastDrip >= FX.fanDripEvery then
		shock.lastDrip = now
		local a = math.atan2(shock.dir.Z, shock.dir.X) + (math.random() * 2 - 1) * shock.halfAngle
		local at = shock.center + Vector3.new(math.cos(a), 0, math.sin(a)) * r + Vector3.new(0, 0.05 / 0.28, 0)
		burst(at, 2, DRIP_COLORS, FX.fanDripSize, FX.fanDripLifetime, FX.fanDripSpeed, FX.fanDripGravity)
	end
	return now < shock.endsAt
end

local function stepShock(shock: Shock, now: number): boolean
	if shock.fan then
		return stepFan(shock, now)
	end
	local reduced = isReduced()
	local spot = shock.spot
	if spot then
		if now >= shock.landAt then
			shock.spot = nil
			releasePart(spot)
		else
			local s = if reduced then 0.5 else UltFx.pulse(now - shock.startAt, FX.zonePulseHz)
			spot.Transparency = 1 - FX.zoneOpacity * (0.55 + 0.45 * s)
		end
	end
	local toy = shock.toy
	local land = shock.center + Vector3.new(0, shock.toyHalf, 0)
	local up = shock.center + Vector3.new(0, FX.shockLeapStuds, 0)
	if toy then
		local span = math.max(shock.landAt - shock.startAt, 1e-3)
		local rise = span * FX.shockRiseShare
		local t = now - shock.startAt
		if t < rise then
			-- design: lab50.js:316 (cos01 ease up, spinning)
			local k = (1 - math.cos(math.pi * math.clamp(t / rise, 0, 1))) / 2
			local spin = if reduced then 0 else t * FX.shockSpinRate
			toy:PivotTo(CFrame.new(shock.from:Lerp(up, k)) * CFrame.Angles(0, spin, 0))
		elseif now < shock.landAt then
			local k = math.clamp((t - rise) / math.max(span - rise, 1e-3), 0, 1)
			toy:PivotTo(CFrame.new(up:Lerp(land, k * k))) -- lab50.js:317 (falls along k²)
		else
			local back = now - shock.landAt - FX.shockReturnAfter
			if back < 0 then
				toy:PivotTo(CFrame.new(land))
			else
				local k = math.clamp(back / FX.shockReturnSeconds, 0, 1)
				local e = (1 - math.cos(math.pi * k)) / 2
				toy:PivotTo(CFrame.new(land:Lerp(shock.from, e) + Vector3.new(0, math.sin(math.pi * k) * 0.5 / 0.28, 0)))
				if k >= 1 then
					shock.toy = nil
					toy:Destroy()
				end
			end
		end
	end
	if not shock.landed and now >= shock.landAt then
		shock.landed = true
		burst(
			shock.center + Vector3.new(0, 0.2 / 0.28, 0),
			FX.shockPetals,
			PETAL_COLORS,
			FX.shockPetalSize,
			FX.shockPetalLifetime,
			FX.shockPetalSpeed,
			FX.shockPetalGravity
		)
		play(SOUND_POP, shock.center, shock.casterId)
	end
	for _, ring in shock.rings do
		local tt = now - ring.startAt
		if tt < 0 then
			continue
		end
		local r = FX.shockRingStartStuds + shock.speed * tt
		if r >= ring.length then
			for _, part in ring.parts do
				releasePart(part)
			end
			table.clear(ring.parts)
			ring.startAt = math.huge -- done
		else
			placeRing(shock, ring, r, math.clamp((ring.length - r) / (ring.length * 0.15), 0, 1))
		end
	end
	return now < shock.endsAt
end

-- Puff Burst (Prism Box, 2026-11-10; design: sd/lab50.js:362-366): the 8 lanes pulse through the wind-up and fade after.
type SpikeLanes = { parts: { BasePart }, startAt: number, releaseAt: number }
local spikeLanes: { SpikeLanes } = {}

local function startSpikeLanes(event: Types.UltimateEventPayload, ability: any)
	local floorY = event.origin.Y - ability.laneHeightAboveFloor
	local set: SpikeLanes = { parts = {}, startAt = serverNow(), releaseAt = event.telegraphEndsAt }
	for _, dir in circleDirs(event.dir, ability.count or 8) do
		local cframe, size = UltFx.lanePlate(event.origin, dir, ability.maxLength, FX.spikeLaneHalfWidth, floorY)
		table.insert(
			set.parts,
			FxPool.default():acquirePart({
				Name = LANE_NAME,
				Size = size,
				CFrame = cframe,
				Color = Palette.UltSpikeLane,
				Transparency = 1,
				Material = Enum.Material.Neon,
			})
		)
	end
	table.insert(spikeLanes, set)
end

local function stepSpikeLanes(set: SpikeLanes, now: number): boolean
	local opacity
	if now < set.releaseAt then
		local span = math.max(set.releaseAt - set.startAt, 1e-3)
		local k = math.clamp((now - set.startAt) / span, 0, 1)
		local s = if isReduced() then 0 else math.sin(2 * math.pi * FX.spikeLanePulseHz * (now - set.startAt))
		opacity = math.clamp(FX.spikeLaneOpacity * k + 0.1 * s, 0, 1)
	else
		opacity = math.max(0, FX.spikeLaneOpacity - (now - set.releaseAt))
	end
	for _, part in set.parts do
		part.Transparency = 1 - opacity
	end
	return now < set.releaseAt + FX.spikeLaneFadeSeconds
end

-- Prism Pen (Prism Box, 2026-11-10; design: sd/lab50.js:376-388): the triangle around the drop (corners at the ability's
-- triangleDeg, its dropHitRadius away), a pulsing outline and a rising candy panel on each side, open at the corners;
-- at the drop's landAt the panels shatter into candy cubes and a white ring flashes out to the corners.
type Pen = {
	casterId: number,
	center: Vector3,
	radius: number,
	startAt: number,
	landAt: number,
	sides: { { panel: BasePart, outline: BasePart, middle: Vector3, along: Vector3, length: number, color: Color3 } },
	shattered: boolean,
}
local pens: { Pen } = {}

local function startPen(event: Types.UltimateEventPayload, ability: any)
	local center = event.center
	local drop = event.drops and event.drops[1]
	if center == nil or drop == nil then
		return
	end
	local radius = ability.dropHitRadius or ability.radius
	local degrees = ability.triangleDeg or 0
	local corners: { Vector3 } = {}
	for index = 0, 2 do
		local angle = math.rad(degrees + 120 * index)
		corners[index + 1] = Vector3.new(center.X + math.cos(angle) * radius, center.Y, center.Z + math.sin(angle) * radius)
	end
	local pen: Pen = {
		casterId = event.casterId,
		center = center,
		radius = radius,
		startAt = event.telegraphEndsAt,
		landAt = drop.landAt,
		sides = {},
		shattered = false,
	}
	for index = 1, 3 do
		local a, b = corners[index], corners[index % 3 + 1]
		local along = (b - a).Unit
		local length = math.max((b - a).Magnitude - 2 * FX.penCornerGapStuds, 0.1)
		local middle = a:Lerp(b, 0.5)
		local color = PEN_COLORS[index]
		table.insert(pen.sides, {
			panel = FxPool.default():acquirePart({
				Name = PANEL_NAME,
				Size = Vector3.new(FX.penPanelThickStuds, FX.penPanelHeightStuds, length),
				CFrame = CFrame.lookAt(middle, middle + along),
				Color = color,
				Transparency = 0,
				Material = Enum.Material.SmoothPlastic,
			}),
			outline = FxPool.default():acquirePart({
				Name = PANEL_NAME,
				Size = Vector3.new(FX.penOutlineWidthStuds, LANE_THICKNESS, length),
				CFrame = CFrame.lookAt(middle + Vector3.new(0, FX.laneLift, 0), middle + Vector3.new(0, FX.laneLift, 0) + along),
				Color = color,
				Transparency = 1,
				Material = Enum.Material.Neon,
			}),
			middle = middle,
			along = along,
			length = length,
			color = color,
		})
	end
	table.insert(pens, pen)
end

local function endPen(pen: Pen)
	for _, side in pen.sides do
		releasePart(side.panel)
		releasePart(side.outline)
	end
	table.clear(pen.sides)
end

local function stepPen(pen: Pen, now: number): boolean
	if now < pen.landAt then
		local span = math.max(pen.landAt - pen.startAt, 1e-3)
		local t = math.max(now - pen.startAt, 0)
		local k = (1 - math.cos(math.pi * math.clamp(t / span, 0, 1))) / 2 -- cos01 (lab50.js:387)
		local s = if isReduced() then 0 else math.sin(2 * math.pi * FX.penOutlinePulseHz * t)
		for _, side in pen.sides do
			local y = -FX.penPanelSinkStuds + FX.penPanelRiseStuds * k
			local at = side.middle + Vector3.new(0, y, 0)
			side.panel.CFrame = CFrame.lookAt(at, at + side.along)
			side.outline.Transparency = 1 - math.clamp(FX.penOutlineOpacity + FX.penOutlinePulse * s, 0, 1)
		end
		return true
	end
	if not pen.shattered then
		pen.shattered = true
		for _, side in pen.sides do
			burst(
				side.middle + Vector3.new(0, 0.25 / 0.28, 0),
				FX.penCubes,
				{ side.color, Palette.White },
				FX.penCubeSize,
				FX.penCubeLifetime,
				FX.penCubeSpeed,
				FX.penCubeGravity
			)
		end
		endPen(pen)
		FxShapes.ring(
			pen.center,
			Vector3.yAxis,
			2 * pen.radius,
			FX.penFlashSeconds,
			Palette.White,
			FX.penFlashTransparencyFrom
		)
		play(SOUND_POP, pen.center, pen.casterId)
	end
	return false
end

-- Public -------------------------------------------------------------------------------------------------------------

-- One UltimateEvent of a non-lane ultimate (VfxController has parsed it and found its ability).
function UltFx.onEvent(event: Types.UltimateEventPayload, ultimateId: string, ability: any, d: Deps)
	deps = d
	local casterId = event.casterId
	local squishyId = squishyOf(ultimateId) or ""
	local root = rootOf(casterId)
	local at = if root then root.Position else event.origin
	if event.phase == "telegraph" then
		local old = casts[casterId]
		if old and old.stopCharge then
			old.stopCharge(nil)
		end
		local localPlayer = Players.LocalPlayer
		local own = localPlayer ~= nil and localPlayer.UserId == casterId
		casts[casterId] = {
			casterId = casterId,
			ultimateId = ultimateId,
			stopCharge = d.playTracked(SOUND_CHARGE_PREFIX .. squishyId, {
				at = root or at,
				priority = if own then BIG_PRIORITY else OTHER_PRIORITY,
			}),
		}
		if ability.kind == "shockwave" then
			local old = shocks[casterId]
			if old then
				endShock(old)
			end
			startShock(event, ability, squishyId) -- the leap and the landing spot show through the wind-up
		end
		if ultimateId == PUFF_ID then
			startSpikeLanes(event, ability)
		end
		return
	end
	local cast = casts[casterId]
	casts[casterId] = nil
	if event.phase == "cancel" then
		if cast and cast.stopCharge then
			cast.stopCharge(Config.Audio.trackedStopFadeMs)
		end
		local shock = shocks[casterId]
		if shock then
			endShock(shock)
		end
		return
	end
	-- release
	play(SOUND_RELEASE, at, casterId)
	local kind = ability.kind
	local floorY = event.origin.Y - ability.laneHeightAboveFloor
	local function remember(projId: number, untilAt: number)
		infos[projId] = {
			casterId = casterId,
			squishyId = squishyId,
			ultimateId = ultimateId,
			knockbackMultiplier = ability.knockbackMultiplier,
			flyOn = kind == "roller" or kind == "shockwave", -- the cake rings grow on past a hit too
			untilAt = untilAt + FORGET_AFTER_SECONDS,
		}
	end
	if kind == "volley" then
		local shots: { Types.UltimateShot } = event.shots or {}
		for index, shot in shots do
			newFlight(
				"volley",
				casterId,
				squishyId,
				shot.projId,
				shot.origin,
				shot.dir,
				shot.length,
				event.speed,
				event.radius,
				shot.releaseAt,
				floorY,
				if ultimateId == PUFF_ID then SPIKE_COLORS[(index - 1) % #SPIKE_COLORS + 1] else nil
			)
			remember(shot.projId, shot.releaseAt + shot.length / math.max(event.speed, 1))
		end
	elseif kind == "roller" or kind == "bubble" then
		local projId = event.projId
		if projId == nil then
			return
		end
		local flight = newFlight(
			kind,
			casterId,
			squishyId,
			projId,
			event.origin,
			event.dir,
			event.length,
			event.speed,
			event.radius,
			event.telegraphEndsAt,
			floorY
		)
		-- Bubble Pop bounce (2026-10-16): the server's bounce leg, read only when it has the right shape.
		local b: any = event.bounce
		if
			kind == "bubble"
			and type(b) == "table"
			and typeof(b.origin) == "Vector3"
			and typeof(b.dir) == "Vector3"
			and type(b.length) == "number"
			and b.length >= 0
		then
			flight.bounce = { at = event.length, origin = b.origin, dir = b.dir }
			flight.length = event.length + b.length
		end
		remember(projId, event.telegraphEndsAt + flight.length / math.max(event.speed, 1))
		if kind == "roller" then
			local cframe, size = UltFx.lanePlate(event.origin, event.dir, ability.maxLength, event.radius, floorY)
			local part = FxPool.default():acquirePart({
				Name = LANE_NAME,
				Size = size,
				CFrame = cframe,
				Color = Palette.UltSprinkleLane,
				Transparency = FX.laneTransparency,
				Material = Enum.Material.SmoothPlastic,
			})
			table.insert(lanes, { part = part, untilClock = os.clock() + FX.laneSeconds })
		end
	elseif kind == "rain" then
		if ultimateId == PEN_ID then
			startPen(event, ability)
		else
			startRain(event, ability, squishyId, ultimateId == WELL_ID, ultimateId == GEYSER_ID, ultimateId == CAMPFIRE_ID)
		end
		local drops: { Types.UltimateDrop } = event.drops or {}
		for _, drop in drops do
			remember(drop.projId, drop.landAt)
		end
	elseif kind == "shockwave" then
		-- Layer Cake Shockwave: the wind-up's shock (or a new one when the telegraph was missed) and its rings.
		local shock = shocks[casterId] or startShock(event, ability, squishyId)
		local shots: { Types.UltimateShot } = event.shots or {}
		for index, shot in shots do
			table.insert(shock.rings, {
				startAt = shot.releaseAt,
				length = shot.length,
				color = CAKE_COLORS[(index - 1) % #CAKE_COLORS + 1],
				parts = {},
			})
			local ends = shot.releaseAt + shot.length / shock.speed
			shock.endsAt = math.max(shock.endsAt, ends)
			remember(shot.projId, ends)
		end
	end
end

-- An Epic ultimate's projectile (a bird, the roller, the bubble, a drop), or nil.
function UltFx.projectile(projId: number): ProjInfo?
	return infos[projId]
end

-- A ThrowImpact: ends the drawn bird or bubble (a hit or its server end); the roller rolls on to its own end.
function UltFx.impact(impact: Types.ThrowImpactPayload)
	local flight = flights[impact.projId]
	if flight == nil then
		return
	end
	if flight.kind == "roller" and (impact.kind == "player" or impact.kind == "target") then
		return
	end
	flight.endAt = serverNow()
	flight.endPosition = impact.position
end

-- One frame (VfxController's step).
function UltFx.step(now: number)
	for _, flight in table.clone(flights) do
		local ok, keep = pcall(stepFlight, flight, now)
		if not ok or not keep then
			endFlight(flight)
		end
	end
	for index = #rains, 1, -1 do
		local rain = rains[index]
		local ok, keep = pcall(stepRain, rain, now)
		if not ok or not keep then
			table.remove(rains, index)
			if rain.zone then
				releasePart(rain.zone)
			end
			if rain.bunny then
				rain.bunny:Destroy()
			end
			if rain.drizzle then
				FxPool.default():release(rain.drizzle)
			end
			for _, drop in rain.drops do
				if drop.shadow then
					releasePart(drop.shadow)
				end
				if drop.drop then
					releasePart(drop.drop)
				end
			end
			for _, bead in rain.beads do
				releasePart(bead)
			end
			table.clear(rain.beads)
			for _, drop in rain.drops do
				if drop.column then
					releasePart(drop.column)
					drop.column = nil
				end
				if drop.flame then
					releasePart(drop.flame)
					drop.flame = nil
				end
				if drop.flameCore then
					releasePart(drop.flameCore)
					drop.flameCore = nil
				end
			end
		end
	end
	for _, shock in table.clone(shocks) do
		local ok, keep = pcall(stepShock, shock, now)
		if not ok or not keep then
			endShock(shock)
		end
	end
	for index = #spikeLanes, 1, -1 do
		local set = spikeLanes[index]
		local ok, keep = pcall(stepSpikeLanes, set, now)
		if not ok or not keep then
			table.remove(spikeLanes, index)
			for _, part in set.parts do
				releasePart(part)
			end
		end
	end
	for index = #pens, 1, -1 do
		local pen = pens[index]
		local ok, keep = pcall(stepPen, pen, now)
		if not ok or not keep then
			table.remove(pens, index)
			endPen(pen)
		end
	end
	local clock = os.clock()
	for index = #lanes, 1, -1 do
		local lane = lanes[index]
		if clock >= lane.untilClock then
			table.remove(lanes, index)
			releasePart(lane.part)
		end
	end
	for projId, info in infos do
		if now > info.untilAt then
			infos[projId] = nil
		end
	end
end

-- Removes everything at once (match end, leak checks).
function UltFx.clear()
	for _, cast in casts do
		if cast.stopCharge then
			cast.stopCharge(nil)
		end
	end
	table.clear(casts)
	for _, flight in table.clone(flights) do
		endFlight(flight)
	end
	UltFx.step(math.huge)
	table.clear(infos)
end

-- Studio / debug counts.
function UltFx.counts(): { [string]: number }
	local n = 0
	for _ in flights do
		n += 1
	end
	local cakes = 0
	for _ in shocks do
		cakes += 1
	end
	return { flights = n, rains = #rains, lanes = #lanes, shocks = cakes, spikeLanes = #spikeLanes, pens = #pens }
end

return UltFx
