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
	floorY: number
): Flight
	local flightScale = flightScaleOf(squishyId, if kind == "roller" then radius / FX.rollerScaleTo else radius)
	local flight: Flight = {
		projId = projId,
		kind = kind,
		casterId = casterId,
		model = newModel(squishyId, flightScale),
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
		if root and kind == "volley" then
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

local function startRain(event: Types.UltimateEventPayload, ability: any, squishyId: string)
	local center = event.center
	local drops = event.drops
	if center == nil or drops == nil then
		return
	end
	local floorY = center.Y
	local releaseAt = event.telegraphEndsAt
	local casterRoot = rootOf(event.casterId)
	local from = if casterRoot then casterRoot.Position + Vector3.new(0, 1.8, 0) else event.origin
	local top = center + Vector3.new(0, FX.bunnyHeight, 0)
	local lobSeconds = (top - from).Magnitude / math.max(ability.speed, 1)
	local def = Catalog.get(squishyId)
	local bunnyScale = flightScaleOf(squishyId, if def then def.throw.radius else 1) -- the toy at its flight size
	local rain: Rain = {
		casterId = event.casterId,
		center = center,
		floorY = floorY,
		releaseAt = releaseAt,
		zone = makeDisc(ZONE_NAME, center + Vector3.new(0, FX.laneLift, 0), ability.radius, Palette.UltRainZone, 1),
		bunny = newModel(squishyId, bunnyScale),
		bunnyScale = bunnyScale,
		from = from,
		lobSeconds = lobSeconds,
		arrived = false,
		drizzle = nil,
		drops = {},
		endsAt = releaseAt + math.max(FX.zoneSeconds, lobSeconds + FX.hoverSeconds),
	}
	for _, drop in drops do
		table.insert(rain.drops, {
			position = drop.position,
			shadowAt = drop.shadowAt,
			landAt = drop.landAt,
			shadow = nil,
			drop = nil,
			landed = false,
		})
		rain.endsAt = math.max(rain.endsAt, drop.landAt + FX.splashRingSeconds)
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
	if zone then
		if t > FX.zoneSeconds then
			rain.zone = nil
			releasePart(zone)
		else
			local s = if reduced then 0.5 else UltFx.pulse(t, FX.zonePulseHz)
			local opacity = FX.zoneOpacity * FX.zoneFill * (0.55 + 0.45 * s) -- design: fx.js:146-151
			zone.Transparency = 1 - opacity * math.clamp((FX.zoneSeconds - t) / (FX.zoneSeconds * 0.15), 0, 1)
		end
	end
	local bunny = rain.bunny
	if bunny then
		local top = rain.center + Vector3.new(0, FX.bunnyHeight, 0)
		if t < rain.lobSeconds then
			local k = math.clamp(t / rain.lobSeconds, 0, 1)
			local p = rain.from:Lerp(top, k) + Vector3.new(0, math.sin(math.pi * k) * FX.bunnyArcStuds, 0)
			bunny:PivotTo(CFrame.new(p))
		else
			local ht = t - rain.lobSeconds
			if not rain.arrived then
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
			if ht > FX.hoverSeconds then
				rain.bunny = nil
				bunny:Destroy()
				local drizzle = rain.drizzle
				if drizzle then
					rain.drizzle = nil
					FxPool.default():release(drizzle)
				end
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
	for _, drop in rain.drops do
		if drop.landed then
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
		return
	end
	local cast = casts[casterId]
	casts[casterId] = nil
	if event.phase == "cancel" then
		if cast and cast.stopCharge then
			cast.stopCharge(Config.Audio.trackedStopFadeMs)
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
			flyOn = kind == "roller",
			untilAt = untilAt + FORGET_AFTER_SECONDS,
		}
	end
	if kind == "volley" then
		local shots: { Types.UltimateShot } = event.shots or {}
		for _, shot in shots do
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
				floorY
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
		startRain(event, ability, squishyId)
		local drops: { Types.UltimateDrop } = event.drops or {}
		for _, drop in drops do
			remember(drop.projId, drop.landAt)
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
	return { flights = n, rains = #rains, lanes = #lanes }
end

return UltFx
