--!strict
-- KillVfxBuilder: authors the kill effects library ReplicatedStorage.SD_KillVfx for the VFX Studio plugin (2026-10-16,
-- VillasmilGaming's Valorant-style kill banners and kill effects). Server only, Edit mode only; runtime code never
-- requires it. Like ThrowVfxBuilder and MoveVfxBuilder it is not one of Main's targets: VFX Studio is the editor of
-- record for these effects. This builder makes the first version (and a reset): build() returns a new, marked,
-- UNPARENTED Folder; the caller swaps it in. A rebuild drops every tweak made in VFX Studio since, so only rebuild to
-- reset.
--
-- One template per kill set (Art/KillStyle: standard for every Common and Uncommon squishy, and one for each squishy
-- above Uncommon). Every template is an invisible anchored Part, so VFX Studio can preview it once it is dragged into
-- Workspace; the runtime, Client/Anim/KillVfx, clones it as the effect's carrier.
--   Banner/<set>   the burst behind the kill banner. Made at banner scale: the banner's disc has a radius of 1 stud
--                  and the carrier's LookVector points away from the viewer (Front = into the screen). The runtime
--                  holds it in front of the killer's own camera, under the banner, scaled to the banner's size; every
--                  emitter is LockedToPart, so the burst stays on the banner while the camera moves.
--                  SD_MinTier (1-6) on an emitter: it plays only for that kill count and up (1 = every kill), so the
--                  6k banner layers everything. Preview in VFX Studio shows all the layers at once.
--   Kill/<set>     the kill effect at the K.O.'d player, seen by everyone nearby: world scale, UpVector = world up. It
--                  plays at the K.O. itself (the carrier at the K.O.'d player's HumanoidRootPart); its finisher emitters
--                  (EmitDelay 0.7) pop where the squishy vanishes. The "Floor" attachment is moved onto the floor
--                  under it at runtime (Anim/KillVfx), so the shock rings lie on the ground even after a jump.
-- VFX Studio's emit contract on every ParticleEmitter (the plugin's own trigger code): EmitDelay (s, default 0), then
-- EmitDuration > 0 = Enabled for that long, else Emit(EmitCount) (default 1).
-- Textures: the VFX Studio plugin's own texture library (public Image assets, each an AssetTable "img.kill.*" slot,
-- read here through AssetTable.image) plus engine built-ins (rbxasset://textures/particles/*). Flipbook sheets keep
-- the plugin library's grid (2 = Grid2x2, 4 = Grid4x4).
-- Particle counts: every banner template stays within Config.Vfx.Budgets.liveParticlesPerEffect (60) at its highest
-- tier, every kill template within Config.Vfx.KillFx.maxParticles (all its emitters, finisher included).
-- No gore (DESIGN brief): splats are candy, glaze, foam, water and fire, never blood.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Types

type Seq = { { number } } -- { time, value } or { time, value, envelope }

type Spec = {
	name: string,
	texture: string,
	color: { Color3 } | Color3,
	size: Seq,
	transparency: Seq,
	lifetime: { number },
	speed: { number },
	spread: Vector2?,
	drag: number?,
	accel: Vector3?,
	rotation: { number }?,
	rotSpeed: { number }?,
	lightEmission: number?,
	lightInfluence: number?,
	brightness: number?, -- default 1
	zOffset: number?,
	orientation: Enum.ParticleOrientation?,
	direction: Enum.NormalId?,
	squash: Seq?,
	grid: number?, -- flipbook: 2 or 4 (the sheet's grid)
	flipMode: Enum.ParticleFlipbookMode?, -- default OneShot
	emitCount: number,
	emitDelay: number?,
	emitDuration: number?,
	rate: number?,
	minTier: number?,
	locked: boolean?,
}

-- Constants

local GENERATOR_ID = "kill_vfx"
local VERSION = 3 -- 2: the first playtest: smaller, see-through world effects (they hid the players behind them), a candy pop on the standard one, a yellow bolt
-- 3 (2026-10-17, owner: "the kill effects don't do anything, make them insane"): big world effects at the K.O. itself
local ROOT_NAME = "SD_KillVfx"

local SETS = { "standard", "feather_storm", "sprinkle_blast", "cloudburst", "bubble_burst", "dragon_blaze" }

local ENGINE = {
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	sparkles = "rbxasset://textures/particles/sparkles_main.dds",
	embers = "rbxasset://textures/particles/fire_sparks_main.dds",
	dot = "rbxasset://textures/whiteCircle.png",
}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- VFX asset colours (VFX Studio is their editor), the same candy colours as Art/Palette and the squishies' accents.
local C = {
	White = hex("#FFFFFF"),
	Cream = hex("#FFF4E6"),
	Strawberry = hex("#FF8FB1"),
	Bubblegum = hex("#FFC7DA"),
	Mint = hex("#8EDFC4"),
	Lemon = hex("#FFD86B"),
	Sky = hex("#8CC8FF"),
	Lavender = hex("#B9A6E8"),
	BirdBlue = hex("#7CC0F5"),
	BirdSky = hex("#DDF0FF"),
	DonutDough = hex("#F6C27A"),
	Chocolate = hex("#7A4632"),
	CloudLilac = hex("#D5C8F6"),
	CloudMist = hex("#F3EFFF"),
	Rain = hex("#A8D8FF"),
	Bolt = hex("#FFE45C"), -- a candy-yellow bolt: white lightning vanished on the white clouds
	AxolotlPink = hex("#F9AFCB"),
	AxolotlDeep = hex("#F07FA8"),
	Aqua = hex("#9FE3E0"),
	BubbleGlass = hex("#E4FBFF"),
	DragonTeal = hex("#3FB8AF"),
	FireCore = hex("#FFB43B"),
	FireTip = hex("#FFE27A"),
	FireDeep = hex("#FF7A2F"),
}

-- Module table

local KillVfxBuilder = {}
KillVfxBuilder.GENERATOR_ID = GENERATOR_ID
KillVfxBuilder.VERSION = VERSION
KillVfxBuilder.ROOT_NAME = ROOT_NAME
KillVfxBuilder.SETS = SETS

-- Private

local textures: { [string]: string }? = nil
local assets: any = nil -- the AssetTable module build() reads (a test passes its own fresh copy)

-- The VFX Studio library textures, from their AssetTable slots (a missing id is a build error: never a blank texture).
local function tex(name: string): string
	local found = textures
	if found == nil then
		found = {}
		textures = found
	end
	local cached = (found :: { [string]: string })[name]
	if cached then
		return cached
	end
	local AssetTable = assets or require(ReplicatedStorage.Shared.AssetTable) :: any
	local content = AssetTable.image("img.kill." .. name)
	assert(type(content) == "string", `[KillVfxBuilder] AssetTable has no id for img.kill.{name}`)
	;(found :: { [string]: string })[name] = content
	return content
end

local function numberSeq(rows: Seq): NumberSequence
	local keys = {}
	for _, row in rows do
		table.insert(keys, NumberSequenceKeypoint.new(row[1], row[2], row[3] or 0))
	end
	return NumberSequence.new(keys)
end

local function colorSeq(colors: { Color3 } | Color3): ColorSequence
	if typeof(colors) == "Color3" then
		return ColorSequence.new(colors)
	end
	local list = colors :: { Color3 }
	if #list == 1 then
		return ColorSequence.new(list[1])
	end
	local keys = {}
	for i, c in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#list - 1), c))
	end
	return ColorSequence.new(keys)
end

local function emitter(spec: Spec): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = spec.name
	e.Texture = spec.texture
	e.Color = colorSeq(spec.color)
	e.Size = numberSeq(spec.size)
	e.Transparency = numberSeq(spec.transparency)
	e.Lifetime = NumberRange.new(spec.lifetime[1], spec.lifetime[2] or spec.lifetime[1])
	e.Speed = NumberRange.new(spec.speed[1], spec.speed[2] or spec.speed[1])
	e.Rate = spec.rate or 0
	e.SpreadAngle = spec.spread or Vector2.new(180, 180)
	e.Drag = spec.drag or 0
	e.Acceleration = spec.accel or Vector3.zero
	local rot = spec.rotation or { 0, 360 }
	e.Rotation = NumberRange.new(rot[1], rot[2] or rot[1])
	local rs = spec.rotSpeed or { 0, 0 }
	e.RotSpeed = NumberRange.new(rs[1], rs[2] or rs[1])
	if spec.squash then
		e.Squash = numberSeq(spec.squash)
	end
	e.LightEmission = spec.lightEmission or 0
	e.LightInfluence = spec.lightInfluence or 0
	e.ZOffset = spec.zOffset or 0
	e.Orientation = spec.orientation or Enum.ParticleOrientation.FacingCamera
	e.EmissionDirection = spec.direction or Enum.NormalId.Top
	e.LockedToPart = spec.locked == true
	e.Brightness = spec.brightness or 1
	if spec.grid == 2 or spec.grid == 4 then
		e.FlipbookLayout = if spec.grid == 2 then Enum.ParticleFlipbookLayout.Grid2x2 else Enum.ParticleFlipbookLayout.Grid4x4
		e.FlipbookMode = spec.flipMode or Enum.ParticleFlipbookMode.OneShot
		e.FlipbookStartRandom = spec.flipMode == Enum.ParticleFlipbookMode.Random
	end
	e.Enabled = false
	e:SetAttribute("EmitCount", spec.emitCount)
	if spec.emitDelay and spec.emitDelay > 0 then
		e:SetAttribute("EmitDelay", spec.emitDelay)
	end
	if spec.emitDuration and spec.emitDuration > 0 then
		e:SetAttribute("EmitDuration", spec.emitDuration)
	end
	if spec.minTier and spec.minTier > 1 then
		e:SetAttribute("SD_MinTier", spec.minTier)
	end
	return e
end

local function carrier(name: string, note: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part:SetAttribute("SD_Theme", note)
	return part
end

local function attachment(parent: Instance, name: string, position: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	a.Parent = parent
	return a
end

local function addAll(a: Attachment, specs: { Spec }, locked: boolean)
	for _, spec in specs do
		if locked then
			spec.locked = true
		end
		emitter(spec).Parent = a
	end
end

-- Shared pieces ----------------------------------------------------------------------------------------------------
-- Banner pieces are at banner scale (disc radius 1); they fly out of the screen plane (Front = away from the viewer).

local FRONT = Enum.NormalId.Front
local FLAT = Enum.ParticleOrientation.VelocityPerpendicular

-- A soft flash behind the disc at the hit.
local function bannerFlash(color: Color3, size: number?): Spec
	local s = size or 3
	return {
		name = "Flash",
		texture = tex("flash"),
		color = color,
		size = { { 0, s * 0.45 }, { 0.3, s }, { 1, s * 1.1 } },
		transparency = { { 0, 0.15 }, { 0.5, 0.5 }, { 1, 1 } },
		lifetime = { 0.28 },
		speed = { 0 },
		spread = Vector2.zero,
		lightEmission = 0.8,
		zOffset = -0.4,
		emitCount = 1,
	}
end

-- The cartoon impact splat behind the disc (candy, never blood).
local function bannerSplat(color: Color3, size: number, minTier: number?): Spec
	return {
		name = "Splat",
		texture = tex("splat"),
		color = color,
		size = { { 0, size * 0.55 }, { 0.25, size }, { 1, size * 1.12 } },
		transparency = { { 0, 0 }, { 0.55, 0.25 }, { 1, 1 } },
		lifetime = { 0.36 },
		speed = { 0 },
		spread = Vector2.zero,
		rotation = { 0, 360 },
		zOffset = -0.5,
		emitCount = 1,
		minTier = minTier,
	}
end

-- A thin ring that grows out of the disc.
local function bannerRing(name: string, color: Color3, from: number, to: number, life: number, minTier: number?, delay: number?): Spec
	return {
		name = name,
		texture = tex("shockRing"),
		color = color,
		size = { { 0, from }, { 1, to } },
		transparency = { { 0, 0.05 }, { 0.6, 0.4 }, { 1, 1 } },
		lifetime = { life },
		speed = { 0 },
		spread = Vector2.zero,
		lightEmission = 0.5,
		zOffset = -0.3,
		emitCount = 1,
		minTier = minTier,
		emitDelay = delay,
	}
end

-- The 5k/6k radial burst behind everything.
local function bannerRays(color: Color3, size: number, minTier: number): Spec
	return {
		name = "Rays",
		texture = tex("burst"),
		color = color,
		size = { { 0, size * 0.4 }, { 0.3, size }, { 1, size * 1.15 } },
		transparency = { { 0, 0.1 }, { 0.6, 0.45 }, { 1, 1 } },
		lifetime = { 0.55 },
		speed = { 0 },
		spread = Vector2.zero,
		rotation = { 0, 360 },
		rotSpeed = { -40, 40 },
		lightEmission = 0.6,
		zOffset = -0.6,
		emitCount = 1,
		minTier = minTier,
	}
end

-- Pieces flying out of the banner: `texture`, count, speed, size, life.
local function bannerBits(
	name: string,
	texture: string,
	color: { Color3 } | Color3,
	count: number,
	speed: { number },
	size: number,
	life: { number },
	extra: { minTier: number?, rotSpeed: { number }?, accel: Vector3?, delay: number?, squash: Seq?, light: number?, grid: number?, flipMode: Enum.ParticleFlipbookMode?, drag: number?, grow: boolean? }?
): Spec
	local e = extra or {}
	return {
		name = name,
		texture = texture,
		color = color,
		size = if e.grow then { { 0, size * 0.5 }, { 0.4, size }, { 1, size * 1.2 } } else { { 0, size * 0.6 }, { 0.15, size }, { 1, 0 } },
		transparency = { { 0, 0 }, { 0.7, 0.1 }, { 1, 1 } },
		lifetime = life,
		speed = speed,
		spread = Vector2.new(85, 85),
		drag = e.drag or 4,
		accel = e.accel,
		rotation = { 0, 360 },
		rotSpeed = e.rotSpeed or { -260, 260 },
		squash = e.squash,
		lightEmission = e.light or 0,
		zOffset = -0.2,
		direction = FRONT,
		grid = e.grid,
		flipMode = e.flipMode,
		emitCount = count,
		emitDelay = e.delay,
		minTier = e.minTier,
	}
end

-- World pieces (Kill/<set>): a flat ring on the floor under the vanish point (the carrier sits at the squishy, about
-- `drop` studs above the floor).
local function floorRing(name: string, texture: string, color: Color3, from: number, to: number, life: number, delay: number?): Spec
	return {
		name = name,
		texture = texture,
		color = color,
		size = { { 0, from }, { 1, to } },
		transparency = { { 0, 0.1 }, { 0.55, 0.45 }, { 1, 1 } },
		lifetime = { life },
		speed = { 0.01 },
		spread = Vector2.zero,
		lightEmission = 0.4,
		zOffset = 0.2,
		orientation = FLAT,
		direction = Enum.NormalId.Top,
		emitCount = 1,
		emitDelay = delay,
	}
end

local function worldBits(
	name: string,
	texture: string,
	color: { Color3 } | Color3,
	count: number,
	speed: { number },
	size: number,
	life: { number },
	extra: { accel: Vector3?, drag: number?, spread: Vector2?, direction: Enum.NormalId?, rotSpeed: { number }?, squash: Seq?, light: number?, grid: number?, flipMode: Enum.ParticleFlipbookMode?, grow: boolean?, delay: number?, influence: number? }?
): Spec
	local e = extra or {}
	return {
		name = name,
		texture = texture,
		color = color,
		size = if e.grow then { { 0, size * 0.45 }, { 0.35, size }, { 1, size * 1.25 } } else { { 0, size * 0.7 }, { 0.15, size }, { 1, 0 } },
		transparency = { { 0, 0 }, { 0.7, 0.1 }, { 1, 1 } },
		lifetime = life,
		speed = speed,
		spread = e.spread or Vector2.new(180, 180),
		drag = e.drag or 2,
		accel = e.accel,
		rotation = { 0, 360 },
		rotSpeed = e.rotSpeed or { -200, 200 },
		squash = e.squash,
		lightEmission = e.light or 0,
		lightInfluence = e.influence or 0,
		zOffset = 0.3,
		direction = e.direction or Enum.NormalId.Top,
		grid = e.grid,
		flipMode = e.flipMode,
		emitCount = count,
		emitDelay = e.delay,
	}
end

-- The banner templates ------------------------------------------------------------------------------------------------

local RANDOM = Enum.ParticleFlipbookMode.Random
local LOOP = Enum.ParticleFlipbookMode.Loop

local function bannerStandard(): Part
	local part = carrier("standard", "Candy Pop (Common and Uncommon): a candy splat, pastel stars and sparkles")
	local a = attachment(part, "Burst", Vector3.zero)
	addAll(a, {
		bannerFlash(C.White),
		bannerSplat(C.Strawberry, 3.2),
		bannerBits("StarsLemon", tex("sparkle"), C.Lemon, 5, { 7, 11 }, 0.42, { 0.45, 0.7 }),
		bannerBits("StarsPink", tex("sparkle"), C.Strawberry, 4, { 6, 10 }, 0.36, { 0.45, 0.7 }),
		bannerBits("StarsMint", tex("sparkle"), C.Mint, 4, { 6, 10 }, 0.36, { 0.45, 0.7 }),
		bannerBits("Candy", ENGINE.dot, { C.Bubblegum, C.Lemon }, 8, { 5, 9 }, 0.22, { 0.4, 0.6 }, { minTier = 3 }),
		bannerRing("Ring", C.Lemon, 2, 5, 0.35, 4),
		bannerRays(C.Lemon, 6, 5),
		bannerBits("Crown", tex("sparkle"), { C.White, C.Lemon }, 10, { 9, 14 }, 0.5, { 0.55, 0.85 }, { minTier = 6, light = 0.3 }),
		bannerBits("Twinkle", tex("twinkle"), C.White, 6, { 3, 6 }, 0.6, { 0.5, 0.8 }, { minTier = 6, delay = 0.12, light = 0.8 }),
	}, true)
	return part
end

local function bannerFeather(): Part
	local part = carrier("feather_storm", "Feather Storm (Birdie): sky flash, feathers whirling out, a wind ring")
	local a = attachment(part, "Burst", Vector3.zero)
	addAll(a, {
		bannerFlash(C.Sky),
		bannerSplat(C.BirdBlue, 3, 2),
		bannerBits("Feathers", tex("feather"), C.White, 8, { 6, 9 }, 0.5, { 0.7, 1.0 }, { rotSpeed = { -180, 180 }, drag = 5, accel = Vector3.new(0, -2, 0) }),
		bannerBits("FeathersBlue", tex("feather"), C.BirdBlue, 5, { 5, 8 }, 0.45, { 0.7, 1.0 }, { rotSpeed = { -180, 180 }, drag = 5, accel = Vector3.new(0, -2, 0) }),
		bannerBits("Sparkles", tex("sparkle"), C.White, 6, { 7, 11 }, 0.3, { 0.4, 0.6 }, { minTier = 2 }),
		bannerRing("WindRing", C.BirdSky, 2, 5.2, 0.4, 3),
		bannerBits("Storm", tex("feather"), { C.White, C.BirdSky }, 10, { 9, 13 }, 0.55, { 0.8, 1.1 }, { minTier = 5, rotSpeed = { -260, 260 }, drag = 4 }),
		bannerRays(C.BirdSky, 6, 5),
		bannerBits("Twinkle", tex("twinkle"), C.White, 8, { 4, 8 }, 0.6, { 0.5, 0.8 }, { minTier = 6, delay = 0.1, light = 0.8 }),
	}, true)
	return part
end

local function bannerSprinkle(): Part
	local part = carrier("sprinkle_blast", "Sprinkle Blast (Donut): a glaze splat, rainbow sprinkles, a donut ring")
	local a = attachment(part, "Burst", Vector3.zero)
	local spin = { rotSpeed = { -360, 360 } }
	addAll(a, {
		bannerFlash(C.Bubblegum),
		bannerSplat(C.Strawberry, 3.3),
		bannerBits("SprinklesLemon", tex("sprinkle"), C.Lemon, 4, { 7, 11 }, 0.34, { 0.5, 0.75 }, spin),
		bannerBits("SprinklesMint", tex("sprinkle"), C.Mint, 4, { 7, 11 }, 0.34, { 0.5, 0.75 }, spin),
		bannerBits("SprinklesSky", tex("sprinkle"), C.Sky, 4, { 7, 11 }, 0.34, { 0.5, 0.75 }, spin),
		bannerBits("SprinklesWhite", tex("sprinkle"), C.White, 4, { 7, 11 }, 0.34, { 0.5, 0.75 }, spin),
		{
			name = "DonutRing",
			texture = tex("softRing"),
			color = C.Strawberry,
			size = { { 0, 1.6 }, { 1, 4.4 } },
			transparency = { { 0, 0.1 }, { 0.6, 0.45 }, { 1, 1 } },
			lifetime = { 0.4 },
			speed = { 0 },
			spread = Vector2.zero,
			zOffset = -0.35,
			emitCount = 1,
			minTier = 3,
		},
		bannerBits("SprinkleRain", tex("sprinkle"), { C.Lemon, C.Mint, C.Sky, C.Strawberry }, 12, { 9, 14 }, 0.38, { 0.6, 0.9 }, { minTier = 5, rotSpeed = { -360, 360 } }),
		bannerRays(C.Lemon, 6, 5),
		bannerBits("Twinkle", tex("sparkle"), C.White, 6, { 4, 8 }, 0.4, { 0.5, 0.8 }, { minTier = 6, delay = 0.1, light = 0.5 }),
	}, true)
	return part
end

local function bannerCloud(): Part
	local part = carrier("cloudburst", "Cloudburst (Cloud Bunny): cloud puffs, rain streaks, lightning from 4k")
	local a = attachment(part, "Burst", Vector3.zero)
	local rain = attachment(part, "Rain", Vector3.new(0, 1.6, 0))
	addAll(a, {
		bannerFlash(C.CloudLilac),
		bannerBits("Clouds", tex("cloud"), C.White, 6, { 3, 5 }, 1.1, { 0.7, 1.0 }, { grow = true, rotSpeed = { -30, 30 }, drag = 3 }),
		bannerRing("MistRing", C.CloudMist, 2, 4.6, 0.4, 2),
		{
			name = "Lightning",
			texture = tex("lightning"),
			color = { C.White, C.Bolt },
			size = { { 0, 2.2 }, { 1, 2.4 } },
			transparency = { { 0, 0 }, { 0.5, 0 }, { 1, 1 } },
			lifetime = { 0.16, 0.22 },
			speed = { 0 },
			spread = Vector2.zero,
			rotation = { -40, 40 },
			lightEmission = 1,
			zOffset = -0.1,
			emitCount = 2,
			minTier = 4,
		},
		bannerRays(C.CloudLilac, 6, 5),
		bannerBits("Puffs", tex("puffs"), C.White, 6, { 5, 8 }, 1.0, { 0.6, 0.8 }, { minTier = 6, grid = 4, grow = true, drag = 4 }),
		bannerBits("Twinkle", tex("twinkle"), C.Bolt, 6, { 4, 8 }, 0.6, { 0.5, 0.8 }, { minTier = 6, delay = 0.1, light = 0.8 }),
	}, true)
	addAll(rain, {
		{
			name = "RainStreaks",
			texture = tex("sprinkle"),
			color = C.Rain,
			size = { { 0, 0.22 }, { 1, 0.22 } },
			transparency = { { 0, 0.1 }, { 0.8, 0.3 }, { 1, 1 } },
			lifetime = { 0.35, 0.5 },
			speed = { 7, 10 },
			spread = Vector2.new(12, 12),
			rotation = { 0, 0 }, -- the pill stands upright: a falling streak
			zOffset = -0.15,
			direction = Enum.NormalId.Bottom,
			emitCount = 8,
			emitDelay = 0.05,
			minTier = 2,
		},
	}, true)
	return part
end

local function bannerBubble(): Part
	local part = carrier("bubble_burst", "Bubble Burst (Cupcake Axolotl): bubbles, popping glints, hearts from 4k")
	local a = attachment(part, "Burst", Vector3.zero)
	addAll(a, {
		bannerFlash(C.Aqua),
		bannerSplat(C.AxolotlPink, 3, 2),
		{
			name = "Bubbles",
			texture = tex("bubble"),
			color = C.BubbleGlass,
			size = { { 0, 0.15 }, { 0.2, 0.42, 0.14 }, { 0.85, 0.48, 0.14 }, { 1, 0.62 } },
			transparency = { { 0, 0 }, { 0.85, 0.05 }, { 1, 1 } },
			lifetime = { 0.6, 0.95 },
			speed = { 5, 9 },
			spread = Vector2.new(85, 85),
			drag = 4,
			accel = Vector3.new(0, 3, 0),
			zOffset = -0.2,
			direction = FRONT,
			emitCount = 10,
		},
		bannerBits("Pops", tex("bubblePop"), C.White, 6, { 4, 7 }, 0.55, { 0.3, 0.45 }, { minTier = 3, grid = 2, flipMode = RANDOM, light = 0.3 }),
		bannerBits("Hearts", tex("heart"), C.AxolotlPink, 5, { 5, 8 }, 0.42, { 0.6, 0.9 }, { minTier = 4, rotSpeed = { -60, 60 } }),
		{
			name = "BubbleRing",
			texture = tex("softRing"),
			color = C.Aqua,
			size = { { 0, 1.8 }, { 1, 4.6 } },
			transparency = { { 0, 0.15 }, { 0.6, 0.5 }, { 1, 1 } },
			lifetime = { 0.4 },
			speed = { 0 },
			spread = Vector2.zero,
			zOffset = -0.35,
			emitCount = 1,
			minTier = 5,
		},
		bannerRays(C.AxolotlPink, 6, 6),
		bannerBits("BubbleStorm", tex("bubble"), C.BubbleGlass, 12, { 8, 12 }, 0.45, { 0.6, 0.9 }, { minTier = 6, accel = Vector3.new(0, 3, 0), rotSpeed = { 0, 0 } }),
	}, true)
	return part
end

local function bannerDragon(): Part
	local part = carrier("dragon_blaze", "Dragon's Blaze (Dragon): a fire burst, embers, teal dragon smoke, an explosion from 5k")
	local a = attachment(part, "Burst", Vector3.zero)
	addAll(a, {
		bannerFlash(C.FireCore),
		bannerBits("Fire", tex("fire"), C.White, 6, { 4, 7 }, 1.0, { 0.4, 0.6 }, { grid = 2, flipMode = LOOP, grow = true, rotSpeed = { -40, 40 }, drag = 4 }),
		bannerBits("Embers", ENGINE.embers, { C.FireTip, C.FireCore }, 12, { 7, 12 }, 0.18, { 0.6, 0.9 }, { light = 1, drag = 2, accel = Vector3.new(0, 4, 0) }),
		bannerBits("DragonSmoke", tex("tealSmoke"), C.White, 4, { 3, 5 }, 1.2, { 0.6, 0.85 }, { minTier = 3, grid = 4, grow = true, drag = 3, rotSpeed = { -30, 30 } }),
		bannerRing("FlameRing", C.FireCore, 2, 5.4, 0.35, 4),
		{
			name = "Explosion",
			texture = tex("explosion"),
			color = C.White,
			size = { { 0, 2.6 }, { 1, 3.6 } },
			transparency = { { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } },
			lifetime = { 0.5 },
			speed = { 0 },
			spread = Vector2.zero,
			rotation = { -20, 20 },
			zOffset = -0.45,
			grid = 4,
			emitCount = 1,
			minTier = 5,
		},
		bannerRays(C.FireTip, 6.4, 6),
		bannerBits("Blaze", tex("fire"), C.White, 6, { 8, 12 }, 1.2, { 0.45, 0.65 }, { minTier = 6, grid = 2, flipMode = LOOP, grow = true, drag = 4 }),
		bannerBits("EmberStorm", ENGINE.embers, { C.FireTip, C.FireDeep }, 12, { 10, 16 }, 0.2, { 0.7, 1.0 }, { minTier = 6, light = 1, delay = 0.08 }),
	}, true)
	return part
end

-- The kill effect templates (world) -----------------------------------------------------------------------------------
-- v3 (2026-10-17, "insane"): each plays at the K.O. itself (the carrier at the K.O.'d player's HumanoidRootPart, about 3
-- studs over the floor) and is built from the same beats: a core flash, a light pillar, two floor shock rings, a ring
-- in the air, the set's big themed burst, debris that falls or floats, and a finisher pop at 0.7 s where the squishy
-- vanishes (the elimination effect's moment). About 8-16 studs across, readable from across the arena.

local FINISH = 0.7 -- the finisher's EmitDelay: the elimination effect's vanish moment (Config.Anim.elimination 700 ms)
local UPRIGHT = Enum.ParticleOrientation.FacingCameraWorldUp
local PARALLEL = Enum.ParticleOrientation.VelocityParallel

-- A white-hot core flash.
local function coreFlash(color: Color3, size: number, delay: number?): Spec
	return {
		name = if delay then "FinishFlash" else "CoreFlash",
		texture = tex("flash"),
		color = { C.White, color },
		size = { { 0, size * 0.4 }, { 0.25, size }, { 1, size * 1.15 } },
		transparency = { { 0, 0 }, { 0.5, 0.35 }, { 1, 1 } },
		lifetime = { if delay then 0.22 else 0.26 },
		speed = { 0 },
		spread = Vector2.zero,
		lightEmission = 1,
		zOffset = 1.5,
		emitCount = 1,
		emitDelay = delay,
	}
end

-- A tall column of light (one stretched particle that stays upright).
local function pillar(color: Color3, width: number, life: number, delay: number?): Spec
	return {
		name = "Pillar",
		texture = tex("flash"),
		color = { C.White, color },
		size = { { 0, width * 0.5 }, { 0.15, width }, { 1, width * 0.7 } },
		squash = { { 0, 2.3 }, { 1, 2.6 } }, -- > 0: taller and thinner
		transparency = { { 0, 0.05 }, { 0.6, 0.35 }, { 1, 1 } },
		lifetime = { life },
		speed = { 0 },
		spread = Vector2.zero,
		rotation = { 0, 0 },
		lightEmission = 1,
		zOffset = 0.8,
		orientation = UPRIGHT,
		emitCount = 1,
		emitDelay = delay,
	}
end

-- Light streaks shooting up the pillar.
local function upStreaks(name: string, color: { Color3 } | Color3, count: number, speed: { number }, delay: number?): Spec
	return {
		name = name,
		texture = tex("sparkle"),
		color = color,
		size = { { 0, 0.8 }, { 0.2, 1.1 }, { 1, 0 } },
		squash = { { 0, 2.2 }, { 1, 2.2 } },
		transparency = { { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } },
		lifetime = { 0.35, 0.6 },
		speed = speed,
		spread = Vector2.new(18, 18),
		drag = 3,
		lightEmission = 0.9,
		zOffset = 1,
		orientation = PARALLEL,
		direction = Enum.NormalId.Top,
		emitCount = count,
		emitDelay = delay,
	}
end

-- A ring that grows in the air, facing the viewer.
local function airRing(name: string, color: Color3, from: number, to: number, life: number, delay: number?): Spec
	return {
		name = name,
		texture = tex("shockRing"),
		color = color,
		size = { { 0, from }, { 1, to } },
		transparency = { { 0, 0 }, { 0.6, 0.4 }, { 1, 1 } },
		lifetime = { life },
		speed = { 0 },
		spread = Vector2.zero,
		lightEmission = 0.7,
		zOffset = 1.2,
		emitCount = 1,
		emitDelay = delay,
	}
end

-- A big cartoon splat behind the burst (candy, glaze or fire coloured; never blood).
local function bigSplat(name: string, color: Color3, size: number, delay: number?): Spec
	return {
		name = name,
		texture = tex("splat"),
		color = color,
		size = { { 0, size * 0.5 }, { 0.2, size }, { 1, size * 1.1 } },
		transparency = { { 0, 0 }, { 0.55, 0.2 }, { 1, 1 } },
		lifetime = { 0.34 },
		speed = { 0 },
		spread = Vector2.zero,
		rotation = { 0, 360 },
		rotSpeed = { -90, 90 },
		zOffset = 0.9,
		emitCount = 1,
		emitDelay = delay,
	}
end

local function floorRings(a: Attachment, inner: Color3, outer: Color3, texture: string?)
	addAll(a, {
		floorRing("FloorShock", tex("shockRing"), inner, 1, 15, 0.45),
		floorRing("FloorShock2", texture or tex("softRing"), outer, 1, 10, 0.6, 0.08),
	}, false)
end

local function killStandard(): Part
	local part = carrier("standard", "Candy Pop (Common and Uncommon): a pastel candy explosion, a pink light pillar, star confetti, floor shockwaves")
	local core = attachment(part, "Burst", Vector3.zero)
	local column = attachment(part, "Pillar", Vector3.new(0, 4, 0))
	local floor = attachment(part, "Floor", Vector3.new(0, -2.9, 0))
	local function stars(name: string, color: Color3): Spec
		return worldBits(name, tex("sparkle"), color, 8, { 26, 42 }, 1.15, { 0.7, 1.1 }, { accel = Vector3.new(0, -26, 0), drag = 2.5, rotSpeed = { -400, 400 }, light = 0.3 })
	end
	addAll(core, {
		coreFlash(C.Strawberry, 9),
		bigSplat("SplatPink", C.Strawberry, 8),
		bigSplat("SplatLemon", C.Lemon, 6.5, 0.05),
		airRing("AirRing", C.Lemon, 1, 16, 0.35),
		stars("StarsLemon", C.Lemon),
		stars("StarsPink", C.Strawberry),
		stars("StarsMint", C.Mint),
		worldBits("Candy", ENGINE.dot, { C.Bubblegum, C.White }, 12, { 20, 34 }, 0.8, { 0.6, 0.9 }, { accel = Vector3.new(0, -30, 0), drag = 1.5 }),
		worldBits("Foam", ENGINE.smoke, { C.Strawberry, C.Bubblegum }, 8, { 8, 14 }, 3, { 0.5, 0.75 }, { grow = true, drag = 3, influence = 0.3 }),
		coreFlash(C.Lemon, 4, FINISH),
		worldBits("FinishStars", tex("sparkle"), { C.White, C.Lemon }, 8, { 10, 18 }, 0.9, { 0.4, 0.6 }, { drag = 4, light = 0.4, delay = FINISH }),
	}, false)
	addAll(column, { pillar(C.Strawberry, 4.6, 0.5), upStreaks("UpStreaks", { C.White, C.Lemon }, 10, { 30, 45 }) }, false)
	floorRings(floor, C.White, C.Strawberry)
	return part
end

local function killFeather(): Part
	local part = carrier("feather_storm", "Feather Storm (Birdie): a feather tornado shooting up, a sky pillar, a wind poof, wind shockwaves")
	local core = attachment(part, "Burst", Vector3.zero)
	local column = attachment(part, "Pillar", Vector3.new(0, 4, 0))
	local floor = attachment(part, "Floor", Vector3.new(0, -2.9, 0))
	local function feathers(name: string, color: Color3, count: number): Spec
		return {
			name = name,
			texture = tex("feather"),
			color = color,
			size = { { 0, 0.7 }, { 0.1, 1.4 }, { 1, 1.1 } },
			transparency = { { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } },
			lifetime = { 1.6, 2.4 },
			speed = { 22, 40 },
			spread = Vector2.new(40, 40),
			drag = 2.2,
			accel = Vector3.new(0, -5, 0),
			rotation = { 0, 360 },
			rotSpeed = { -300, 300 },
			lightInfluence = 0.2,
			zOffset = 0.6,
			direction = Enum.NormalId.Top,
			emitCount = count,
		}
	end
	addAll(core, {
		coreFlash(C.Sky, 9),
		worldBits("Poof", tex("puffs"), C.White, 5, { 4, 8 }, 4.2, { 0.55, 0.75 }, { grid = 4, grow = true, drag = 3, rotSpeed = { -40, 40 } }),
		airRing("WindRing", C.BirdSky, 1, 16, 0.4),
		feathers("FeathersUp", C.White, 22),
		feathers("FeathersBlue", C.BirdBlue, 14),
		worldBits("Burst", tex("feather"), { C.White, C.BirdSky }, 10, { 20, 32 }, 1.2, { 1.0, 1.5 }, { accel = Vector3.new(0, -6, 0), drag = 3, rotSpeed = { -300, 300 } }),
		worldBits("Sparkles", ENGINE.sparkles, C.Sky, 10, { 6, 12 }, 0.7, { 0.5, 0.8 }, { drag = 2, light = 0.6 }),
		coreFlash(C.BirdSky, 3.5, FINISH),
		worldBits("FinishFeathers", tex("feather"), C.White, 10, { 10, 18 }, 1.0, { 0.9, 1.3 }, { accel = Vector3.new(0, -4, 0), drag = 3, rotSpeed = { -300, 300 }, delay = FINISH }),
	}, false)
	addAll(column, { pillar(C.BirdBlue, 4.4, 0.55), upStreaks("WindStreaks", { C.White, C.Sky }, 12, { 32, 48 }) }, false)
	floorRings(floor, C.White, C.BirdBlue, tex("shockRing"))
	return part
end

local function killSprinkle(): Part
	local part = carrier("sprinkle_blast", "Sprinkle Blast (Donut): a sprinkle fountain that rains down, a glaze explosion, a donut shockwave on the floor")
	local core = attachment(part, "Burst", Vector3.zero)
	local column = attachment(part, "Pillar", Vector3.new(0, 4, 0))
	local floor = attachment(part, "Floor", Vector3.new(0, -2.9, 0))
	local function fountain(name: string, color: Color3): Spec
		return {
			name = name,
			texture = tex("sprinkle"),
			color = color,
			size = { { 0, 0.95 }, { 1, 0.85 } },
			transparency = { { 0, 0 }, { 0.85, 0.05 }, { 1, 1 } },
			lifetime = { 1.3, 1.8 },
			speed = { 32, 50 },
			spread = Vector2.new(35, 35),
			drag = 0.6,
			accel = Vector3.new(0, -48, 0),
			rotation = { 0, 360 },
			rotSpeed = { -500, 500 },
			lightInfluence = 0.2,
			zOffset = 0.5,
			direction = Enum.NormalId.Top,
			emitCount = 9,
		}
	end
	addAll(core, {
		coreFlash(C.Bubblegum, 9),
		bigSplat("GlazeSplat", C.Strawberry, 9),
		worldBits("Glaze", tex("splash"), C.Strawberry, 3, { 1, 3 }, 5.5, { 0.45, 0.6 }, { grid = 4, grow = true, drag = 2 }),
		airRing("DonutRing", C.Strawberry, 1, 16, 0.35),
		fountain("SprinklesLemon", C.Lemon),
		fountain("SprinklesMint", C.Mint),
		fountain("SprinklesSky", C.Sky),
		fountain("SprinklesPink", C.Strawberry),
		fountain("SprinklesWhite", C.White),
		worldBits("Stars", tex("sparkle"), C.Lemon, 8, { 16, 28 }, 1.0, { 0.5, 0.8 }, { drag = 3, light = 0.3 }),
		coreFlash(C.Strawberry, 3.5, FINISH),
		worldBits("FinishSprinkles", tex("sprinkle"), { C.Lemon, C.Mint, C.Sky }, 10, { 12, 20 }, 0.8, { 0.7, 1.0 }, { accel = Vector3.new(0, -30, 0), drag = 1, rotSpeed = { -400, 400 }, delay = FINISH }),
	}, false)
	addAll(column, { pillar(C.Strawberry, 4.6, 0.5), upStreaks("Streaks", { C.White, C.Bubblegum }, 8, { 30, 44 }) }, false)
	addAll(floor, {
		floorRing("DonutShock", tex("softRing"), C.Strawberry, 1, 16, 0.55),
		floorRing("DoughShock", tex("softRing"), C.DonutDough, 1, 11, 0.6, 0.06),
		floorRing("WhiteShock", tex("shockRing"), C.White, 1, 13, 0.4, 0.03),
	}, false)
	return part
end

local function killCloud(): Part
	local part = carrier("cloudburst", "Cloudburst (Cloud Bunny): a storm cloud gathers overhead, two lightning strikes, rain pours, a thunder shockwave")
	local core = attachment(part, "Burst", Vector3.zero)
	local sky = attachment(part, "Sky", Vector3.new(0, 8.5, 0))
	local bolt = attachment(part, "Bolt", Vector3.new(0, 4.2, 0))
	local floor = attachment(part, "Floor", Vector3.new(0, -2.9, 0))
	local function strike(name: string, delay: number): Spec
		return {
			name = name,
			texture = tex("lightning"),
			color = C.Bolt,
			size = { { 0, 8.5 }, { 1, 9 } }, -- from the cloud down to the squishy
			transparency = { { 0, 0 }, { 0.55, 0 }, { 1, 1 } },
			lifetime = { 0.2 },
			speed = { 0 },
			spread = Vector2.zero,
			rotation = { -12, 12 },
			lightEmission = 0.6, -- full emission washed the bolt out against a bright sky ...
			brightness = 3, -- ... so it glows by brightness instead
			zOffset = 1.4,
			orientation = UPRIGHT,
			emitCount = 1,
			emitDelay = delay,
		}
	end
	addAll(sky, {
		worldBits("StormCloud", tex("cloud"), { C.CloudMist, C.Lavender }, 7, { 6, 12 }, 5.5, { 1.3, 1.7 }, { grow = true, drag = 2.5, rotSpeed = { -20, 20 }, spread = Vector2.new(80, 80) }),
		{
			name = "Rain",
			texture = tex("sprinkle"),
			color = C.Rain,
			size = { { 0, 0.6 }, { 1, 0.6 } },
			squash = { { 0, 1.5 }, { 1, 1.5 } },
			transparency = { { 0, 0.1 }, { 0.85, 0.3 }, { 1, 1 } },
			lifetime = { 0.32, 0.42 },
			speed = { 30, 38 },
			spread = Vector2.new(16, 16),
			rotation = { 0, 0 },
			lightInfluence = 0.2,
			zOffset = 0.2,
			orientation = PARALLEL,
			direction = Enum.NormalId.Bottom,
			rate = 70,
			emitCount = 0,
			emitDuration = 0.6,
			emitDelay = 0.1,
		},
	}, false)
	addAll(bolt, { strike("Lightning", 0.04), strike("Lightning2", 0.26) }, false)
	addAll(core, {
		coreFlash(C.Bolt, 9),
		airRing("ThunderRing", C.CloudLilac, 1, 16, 0.4, 0.04),
		worldBits("Mist", tex("puffs"), C.CloudMist, 6, { 5, 10 }, 3.6, { 0.6, 0.85 }, { grid = 4, grow = true, drag = 3 }),
		worldBits("Sparkles", ENGINE.sparkles, C.Lavender, 12, { 10, 20 }, 1.0, { 0.5, 0.8 }, { drag = 2, light = 0.6 }),
		coreFlash(C.CloudLilac, 3.5, FINISH),
		worldBits("FinishPuff", tex("cloud"), C.White, 4, { 3, 6 }, 3, { 0.6, 0.8 }, { grow = true, drag = 3, delay = FINISH }),
	}, false)
	addAll(floor, {
		floorRing("ThunderShock", tex("shockRing"), C.Bolt, 1, 16, 0.4, 0.04),
		floorRing("MistShock", tex("softRing"), C.CloudLilac, 1, 11, 0.6, 0.1),
	}, false)
	return part
end

local function killBubble(): Part
	local part = carrier("bubble_burst", "Bubble Burst (Cupcake Axolotl): a giant bubble swallows the spot and pops, a water crown, a bubble fountain, hearts")
	local core = attachment(part, "Burst", Vector3.zero)
	local column = attachment(part, "Pillar", Vector3.new(0, 4, 0))
	local floor = attachment(part, "Floor", Vector3.new(0, -2.9, 0))
	addAll(core, {
		{
			name = "GiantBubble",
			texture = tex("bubble"),
			color = C.BubbleGlass,
			size = { { 0, 1 }, { 0.85, 10 }, { 1, 11 } },
			transparency = { { 0, 0.1 }, { 0.85, 0.2 }, { 1, 1 } },
			lifetime = { 0.42 },
			speed = { 0 },
			spread = Vector2.zero,
			lightInfluence = 0.1,
			zOffset = 1.2,
			emitCount = 1,
		},
		{
			name = "GiantPop",
			texture = tex("bubblePop"),
			color = C.White,
			size = { { 0, 10 }, { 1, 12.5 } },
			transparency = { { 0, 0 }, { 0.6, 0.3 }, { 1, 1 } },
			lifetime = { 0.3 },
			speed = { 0 },
			spread = Vector2.zero,
			lightEmission = 0.4,
			zOffset = 1.3,
			grid = 2,
			flipMode = Enum.ParticleFlipbookMode.OneShot,
			emitCount = 1,
			emitDelay = 0.4,
		},
		coreFlash(C.Aqua, 6, nil),
		worldBits("WaterCrown", tex("splash"), C.Aqua, 3, { 1, 3 }, 6, { 0.45, 0.6 }, { grid = 4, grow = true, drag = 2, delay = 0.4 }),
		{
			name = "BubbleFountain",
			texture = tex("bubble"),
			color = C.BubbleGlass,
			size = { { 0, 0.4 }, { 0.15, 1.2, 0.45 }, { 0.9, 1.4, 0.45 }, { 1, 1.8 } },
			transparency = { { 0, 0 }, { 0.9, 0.05 }, { 1, 1 } },
			lifetime = { 1.2, 1.9 },
			speed = { 10, 22 },
			spread = Vector2.new(60, 60),
			drag = 2.2,
			accel = Vector3.new(0, 7, 0),
			lightInfluence = 0.1,
			zOffset = 0.4,
			direction = Enum.NormalId.Top,
			emitCount = 26,
			emitDelay = 0.4,
		},
		worldBits("Hearts", tex("heart"), C.AxolotlDeep, 10, { 12, 20 }, 1.25, { 1.0, 1.4 }, { accel = Vector3.new(0, 4, 0), drag = 2, rotSpeed = { -60, 60 }, delay = 0.42 }),
		worldBits("Frosting", ENGINE.smoke, { C.AxolotlPink, C.Bubblegum }, 6, { 5, 9 }, 1.6, { 0.5, 0.75 }, { drag = 2, grow = true, influence = 0.3, delay = 0.4 }),
		airRing("PopRing", C.Aqua, 3, 17, 0.35, 0.4),
		coreFlash(C.AxolotlPink, 3.5, FINISH),
		worldBits("FinishBubbles", tex("bubble"), C.BubbleGlass, 8, { 8, 14 }, 1.0, { 0.7, 1.0 }, { accel = Vector3.new(0, 6, 0), drag = 2, rotSpeed = { 0, 0 }, delay = FINISH }),
	}, false)
	addAll(column, { pillar(C.Aqua, 4.4, 0.5, 0.4), upStreaks("BubbleStreaks", { C.White, C.Aqua }, 8, { 28, 40 }, 0.4) }, false)
	addAll(floor, {
		floorRing("WaterShock", tex("softRing"), C.Aqua, 1, 15, 0.55, 0.4),
		floorRing("PinkShock", tex("shockRing"), C.AxolotlPink, 1, 11, 0.5, 0.45),
	}, false)
	return part
end

local function killDragon(): Part
	local part = carrier("dragon_blaze", "Dragon's Blaze (Dragon): a fire pillar erupts, a cartoon explosion, teal dragon smoke, an ember storm, a scorch shockwave")
	local core = attachment(part, "Burst", Vector3.zero)
	local column = attachment(part, "Pillar", Vector3.new(0, 4, 0))
	local floor = attachment(part, "Floor", Vector3.new(0, -2.9, 0))
	addAll(core, {
		coreFlash(C.FireCore, 9.5),
		{
			name = "Explosion",
			texture = tex("explosion"),
			color = C.White,
			size = { { 0, 6 }, { 1, 8 } },
			transparency = { { 0, 0 }, { 0.75, 0.15 }, { 1, 1 } },
			lifetime = { 0.5 },
			speed = { 0 },
			spread = Vector2.zero,
			rotation = { -20, 20 },
			zOffset = 1,
			grid = 4,
			emitCount = 1,
		},
		{
			name = "FirePillar",
			texture = tex("fire"),
			color = C.White,
			size = { { 0, 3 }, { 0.3, 4.8 }, { 1, 3.4 } },
			transparency = { { 0, 0 }, { 0.75, 0.2 }, { 1, 1 } },
			lifetime = { 0.55, 0.8 },
			speed = { 16, 28 },
			spread = Vector2.new(14, 14),
			drag = 1.5,
			rotation = { -15, 15 },
			lightEmission = 0.3,
			zOffset = 0.8,
			direction = Enum.NormalId.Top,
			grid = 2,
			flipMode = LOOP,
			emitCount = 12,
		},
		worldBits("Fire", tex("fire"), C.White, 8, { 10, 18 }, 2.6, { 0.5, 0.75 }, { grid = 2, flipMode = LOOP, grow = true, drag = 2, rotSpeed = { -40, 40 } }),
		worldBits("Embers", ENGINE.embers, { C.FireTip, C.FireCore, C.FireDeep }, 28, { 18, 36 }, 0.55, { 0.9, 1.5 }, { accel = Vector3.new(0, -10, 0), drag = 1, light = 1 }),
		worldBits("DragonSmoke", tex("tealSmoke"), C.White, 5, { 4, 8 }, 3.6, { 0.9, 1.2 }, { grid = 4, grow = true, accel = Vector3.new(0, 5, 0), drag = 2, delay = 0.1, influence = 0.2 }),
		airRing("BlastRing", C.FireCore, 1, 17, 0.35),
		coreFlash(C.FireDeep, 4, FINISH),
		worldBits("FinishFire", tex("fire"), C.White, 6, { 8, 14 }, 1.8, { 0.4, 0.6 }, { grid = 2, flipMode = LOOP, grow = true, drag = 2, delay = FINISH }),
	}, false)
	addAll(column, { pillar(C.FireCore, 5, 0.55), upStreaks("EmberStreaks", { C.FireTip, C.FireCore }, 12, { 34, 52 }) }, false)
	addAll(floor, {
		floorRing("ScorchShock", tex("softRing"), C.FireCore, 1, 17, 0.55),
		floorRing("TealShock", tex("shockRing"), C.DragonTeal, 1, 12, 0.45, 0.05),
	}, false)
	return part
end

-- Public

local BANNERS: { [string]: () -> Part } = {
	standard = bannerStandard,
	feather_storm = bannerFeather,
	sprinkle_blast = bannerSprinkle,
	cloudburst = bannerCloud,
	bubble_burst = bannerBubble,
	dragon_blaze = bannerDragon,
}

local KILLS: { [string]: () -> Part } = {
	standard = killStandard,
	feather_storm = killFeather,
	sprinkle_blast = killSprinkle,
	cloudburst = killCloud,
	bubble_burst = killBubble,
	dragon_blaze = killDragon,
}

-- The library as a new, UNPARENTED Folder (marked when `Generated`, SDTools' root marker module, is given). `AssetTable`
-- is the module to read the texture ids from (default ReplicatedStorage.Shared.AssetTable).
function KillVfxBuilder.build(Generated: any?, AssetTable: any?): Folder
	textures = nil
	assets = AssetTable
	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root:SetAttribute(
		"SD_Note",
		"Kill banner bursts and kill effects for the VFX Studio plugin: drag a template into Workspace, select it and press Emit to preview. Banner/* emitters with SD_MinTier only play from that kill count up."
	)
	local banner = Instance.new("Folder")
	banner.Name = "Banner"
	banner.Parent = root
	local kill = Instance.new("Folder")
	kill.Name = "Kill"
	kill.Parent = root
	for _, id in SETS do
		BANNERS[id]().Parent = banner
		KILLS[id]().Parent = kill
	end
	if Generated then
		Generated.mark(root, GENERATOR_ID, VERSION)
	end
	return root
end

return KillVfxBuilder
