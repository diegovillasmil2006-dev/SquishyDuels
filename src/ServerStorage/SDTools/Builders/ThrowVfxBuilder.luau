--!strict
-- ThrowVfxBuilder: authors the throw effects library ReplicatedStorage.SD_ThrowVfx for the VFX Studio plugin
-- (2026-10-15, VillasmilGaming's throw overhaul). Server only, Edit mode only; runtime code never requires it.
-- Not one of Main's targets: VFX Studio is the editor of record for these effects. This builder makes the first version
-- (and a reset): build() returns a new, marked, UNPARENTED Folder; the caller swaps it in. A rebuild drops every tweak
-- made in VFX Studio since, so only rebuild to reset.
--
-- Layout (every template is an invisible anchored Part, so VFX Studio can preview it once it is dragged into Workspace;
-- the runtime, Client/Anim/ThrowVfx, clones it as the effect's carrier):
--   Trails/<squishyId>  one per Catalog squishy: Trails between Attachment pairs (FaceCamera ribbons, or twisting ones
--                       when the Part has SD_FollowRoll) and flight ParticleEmitters (SD_Role "flight": on while it
--                       flies). Sizes are for a throw radius of 1 stud; the runtime scales them by the throw's radius.
--   Bursts/<name>       one-shot effects: Release, Bounce, Land, Skid, Settle, Poof, HandSwoosh. Their Attachment Y
--                       axis is the surface normal (Bounce, Land, Skid, Settle).
-- VFX Studio's emit contract on every ParticleEmitter (the plugin's own trigger code, read 2026-10-15): EmitDelay
-- (s, default 0), then EmitDuration > 0 = Enabled for that long, else Emit(EmitCount) (default 1). Our own attributes:
--   SD_Role   "flight" (Trails: on while flying) | "while" (Skid: on while sliding) | nil (a burst emitter)
--   SD_Tint   "accent": the runtime recolours it in the throw's squishy accent (accent -> lighter)
--   SD_Feels  comma list of Config.Anim.rig.feels names (foam, mochi, jelly, plush): only toys of these feels emit it
-- Textures: engine built-ins only (verified AssetFetchStatus Success in Studio 2026-10-15), no uploads.

-- Types

type Seq = { { number } } -- { time, value } or { time, value, envelope }

export type EmitterSpec = {
	name: string,
	texture: string,
	color: { Color3 } | Color3,
	size: Seq,
	transparency: Seq,
	lifetime: { number },
	speed: { number },
	rate: number?,
	spread: Vector2?,
	drag: number?,
	accel: Vector3?,
	rotation: { number }?,
	rotSpeed: { number }?,
	squash: Seq?,
	lightEmission: number?,
	lightInfluence: number?,
	zOffset: number?,
	orientation: Enum.ParticleOrientation?,
	direction: Enum.NormalId?,
	emitCount: number?,
	emitDelay: number?,
	emitDuration: number?,
	role: string?,
	tint: string?,
	feels: string?,
	locked: boolean?,
}

export type RibbonSpec = {
	name: string,
	offset: number, -- sideways (X) centre offset, studs at radius 1
	width: number, -- studs at radius 1
	colors: { Color3 },
	transparency: Seq,
	lifetime: number,
	lightEmission: number?,
	faceCamera: boolean?,
	texture: string?,
	widthTo: number?,
	tint: string?,
}

export type TrailSpec = {
	id: string,
	theme: string,
	followRoll: boolean?,
	ribbons: { RibbonSpec },
	emitters: { EmitterSpec },
}

-- Constants

local GENERATOR_ID = "throw_vfx"
local VERSION = 1
local ROOT_NAME = "SD_ThrowVfx"

local TEX = {
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	sparkles = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	embers = "rbxasset://textures/particles/fire_sparks_main.dds",
	shock = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	core = "rbxasset://textures/particles/explosion01_core_main.dds",
	glow = "rbxasset://textures/glow.png",
	star = "rbxasset://textures/particles/sparkles_main.dds", -- sparkle.png shows dark edges unless additive
	dot = "rbxasset://textures/whiteCircle.png",
}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- VFX asset colours (VFX Studio is their editor). Squishy accents are the Catalog's.
local C = {
	White = hex("#FFFFFF"),
	Cream = hex("#FFF4E6"),
	Vanilla = hex("#F6E3CC"),
	Dust = hex("#F4E6D3"),
	Lemon = hex("#FFD86B"),
	ButterGlint = hex("#FFE27A"),
	GlowCream = hex("#FFF1C2"),
	LampGlow = hex("#FFF6DC"),
	Strawberry = hex("#FF8FB1"),
	Bubblegum = hex("#FFC7DA"),
	Mint = hex("#8EDFC4"),
	Sky = hex("#8CC8FF"),
	Lavender = hex("#B9A6E8"),
	Glass = hex("#E4F6FF"),
	SeaGlass = hex("#9FE3C9"),
	Cocoa = hex("#6B4A3A"),
	Caramel = hex("#C98F4B"),
	Wafer = hex("#E5B06C"),
	Chip = hex("#4A2C20"),
	Crust = hex("#A86A2C"),
	Syrup = hex("#B5651D"),
	MilkTea = hex("#F2C98F"),
	Pearl = hex("#2B2233"),
	FireCore = hex("#FFB43B"),
	FireTip = hex("#FFE27A"),
	FireDeep = hex("#FF7A2F"),
	DragonTeal = hex("#3FB8AF"),
	Soot = hex("#3B3640"),
	Peel = hex("#E9D45A"),
	Petal = hex("#FFC7DA"),
	PetalDeep = hex("#FF9ABF"),
	Seed = hex("#FFF1C2"),
}

-- Module table

local ThrowVfxBuilder = {}
ThrowVfxBuilder.GENERATOR_ID = GENERATOR_ID
ThrowVfxBuilder.VERSION = VERSION
ThrowVfxBuilder.ROOT_NAME = ROOT_NAME
ThrowVfxBuilder.TEXTURES = TEX

-- Private

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

local function carrier(name: string): Part
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
	return part
end

local function attachment(parent: Instance, name: string, position: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	a.Parent = parent
	return a
end

function ThrowVfxBuilder.emitter(spec: EmitterSpec): ParticleEmitter
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
	e.Enabled = false
	e.Brightness = 1
	if spec.emitCount then
		e:SetAttribute("EmitCount", spec.emitCount)
	end
	if spec.emitDelay then
		e:SetAttribute("EmitDelay", spec.emitDelay)
	end
	if spec.emitDuration then
		e:SetAttribute("EmitDuration", spec.emitDuration)
	end
	if spec.role then
		e:SetAttribute("SD_Role", spec.role)
	end
	if spec.tint then
		e:SetAttribute("SD_Tint", spec.tint)
	end
	if spec.feels then
		e:SetAttribute("SD_Feels", spec.feels)
	end
	return e
end

local function ribbon(part: Part, spec: RibbonSpec)
	local half = spec.width / 2
	local top = attachment(part, spec.name .. "Top", Vector3.new(spec.offset, half, 0))
	local bottom = attachment(part, spec.name .. "Bottom", Vector3.new(spec.offset, -half, 0))
	local t = Instance.new("Trail")
	t.Name = spec.name
	t.Attachment0 = top
	t.Attachment1 = bottom
	t.Color = colorSeq(spec.colors)
	t.Transparency = numberSeq(spec.transparency)
	t.Lifetime = spec.lifetime
	t.MinLength = 0.05
	t.MaxLength = 0 -- no cap: the lifetime is the length
	t.WidthScale = NumberSequence.new(1, spec.widthTo or 0.05)
	t.FaceCamera = spec.faceCamera ~= false
	t.LightEmission = spec.lightEmission or 0
	t.LightInfluence = 0 -- unlit: the exact toon colours on any sky
	t.Brightness = 1
	if spec.texture then
		t.Texture = spec.texture
		t.TextureMode = Enum.TextureMode.Stretch
	end
	if spec.tint then
		t:SetAttribute("SD_Tint", spec.tint)
	end
	t.Enabled = true
	t.Parent = part
end

-- Shared flight pieces -----------------------------------------------------------------------------------------------

local FADE: Seq = { { 0, 0.1 }, { 0.55, 0.35 }, { 1, 1 } }
local CORE_FADE: Seq = { { 0, 0 }, { 0.4, 0.5 }, { 1, 1 } }

local function core(colors: { Color3 }?, width: number?, lifetime: number?): RibbonSpec
	return {
		name = "Core",
		offset = 0,
		width = width or 0.32,
		colors = colors or { C.White, C.LampGlow },
		transparency = CORE_FADE,
		lifetime = lifetime or 0.18,
		lightEmission = 0.35,
		widthTo = 0.1,
	}
end

local function sparkles(name: string, color: { Color3 } | Color3, rate: number, size: number?): EmitterSpec
	local s = size or 0.45
	return {
		name = name,
		texture = TEX.star,
		color = color,
		size = { { 0, 0 }, { 0.2, s }, { 1, 0 } },
		transparency = { { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } },
		lifetime = { 0.35, 0.7 },
		speed = { 0.5, 2.5 },
		rate = rate,
		drag = 3,
		rotation = { 0, 360 },
		rotSpeed = { -180, 180 },
		lightEmission = 0.35,
		zOffset = 0.5,
		role = "flight",
		emitDuration = 1.5,
	}
end

local function puffs(
	name: string,
	color: { Color3 } | Color3,
	rate: number,
	sizeFrom: number,
	sizeTo: number,
	alpha: number
): EmitterSpec
	return {
		name = name,
		texture = TEX.smoke,
		color = color,
		size = { { 0, sizeFrom }, { 1, sizeTo } },
		transparency = { { 0, alpha }, { 0.6, (alpha + 1) / 2 }, { 1, 1 } },
		lifetime = { 0.5, 0.85 },
		speed = { 0.4, 1.6 },
		rate = rate,
		drag = 2,
		accel = Vector3.new(0, 1.5, 0),
		rotation = { 0, 360 },
		rotSpeed = { -40, 40 },
		lightInfluence = 0.4,
		role = "flight",
		emitDuration = 1.5,
	}
end

-- Small dots: crumbs, sprinkles, pearls, drops, petals (squash > 0 widens them, < 0 stretches them tall).
local function dots(
	name: string,
	color: { Color3 } | Color3,
	rate: number,
	size: number,
	gravity: number,
	squash: number?,
	lifetime: { number }?
): EmitterSpec
	return {
		name = name,
		texture = TEX.dot,
		color = color,
		size = { { 0, size }, { 0.8, size * 0.9 }, { 1, 0 } },
		transparency = { { 0, 0 }, { 0.8, 0 }, { 1, 1 } },
		lifetime = lifetime or { 0.5, 0.9 },
		speed = { 1.5, 4 },
		rate = rate,
		drag = 1.5,
		accel = Vector3.new(0, -gravity, 0),
		rotation = { 0, 360 },
		rotSpeed = { -220, 220 },
		squash = if squash then { { 0, squash }, { 1, squash } } else nil,
		lightInfluence = 0.5,
		zOffset = 0.3,
		role = "flight",
		emitDuration = 1.5,
	}
end

local function glowBubbles(name: string, color: { Color3 } | Color3, rate: number, size: number): EmitterSpec
	return {
		name = name,
		texture = TEX.dot, -- glow.png shows a dark rim unless additive
		color = color,
		size = { { 0, 0 }, { 0.15, size }, { 0.85, size * 1.1 }, { 1, 0 } },
		transparency = { { 0, 0.35 }, { 0.8, 0.5 }, { 1, 1 } },
		lifetime = { 0.6, 1.1 },
		speed = { 0.6, 2 },
		rate = rate,
		drag = 2.5,
		accel = Vector3.new(0, 3, 0),
		lightEmission = 0.3,
		zOffset = 0.3,
		role = "flight",
		emitDuration = 1.5,
	}
end

local function ribbonOf(colors: { Color3 }, width: number, lifetime: number, offset: number?, name: string?): RibbonSpec
	return {
		name = name or "Ribbon",
		offset = offset or 0,
		width = width,
		colors = colors,
		transparency = FADE,
		lifetime = lifetime,
		lightEmission = 0,
	}
end

local function feathers(): EmitterSpec
	return {
		name = "Feathers",
		texture = TEX.dot,
		color = { C.White, C.Glass },
		size = { { 0, 0.32 }, { 0.85, 0.3 }, { 1, 0 } },
		transparency = { { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } },
		lifetime = { 1, 1.5 },
		speed = { 1, 3 },
		rate = 6,
		drag = 3.5,
		accel = Vector3.new(0, -3, 0),
		rotation = { 0, 360 },
		rotSpeed = { -90, 90 },
		squash = { { 0, 0.62 }, { 1, 0.62 } },
		lightInfluence = 0.4,
		zOffset = 0.3,
		role = "flight",
		emitDuration = 1.5,
	}
end

local function petals(): EmitterSpec
	return {
		name = "Petals",
		texture = TEX.dot,
		color = { C.Petal, C.PetalDeep },
		size = { { 0, 0.26 }, { 0.85, 0.24 }, { 1, 0 } },
		transparency = { { 0, 0 }, { 0.75, 0.1 }, { 1, 1 } },
		lifetime = { 1, 1.6 },
		speed = { 1, 2.5 },
		rate = 10,
		drag = 3,
		accel = Vector3.new(0.6, -2.5, 0),
		rotation = { 0, 360 },
		rotSpeed = { -160, 160 },
		squash = { { 0, 0.45 }, { 0.5, -0.2 }, { 1, 0.45 } },
		lightInfluence = 0.4,
		zOffset = 0.3,
		role = "flight",
		emitDuration = 1.5,
	}
end

local function flames(): EmitterSpec
	return {
		name = "Flames",
		texture = TEX.fire,
		color = { C.FireTip, C.FireCore, C.FireDeep },
		size = { { 0, 1.2 }, { 0.5, 0.9 }, { 1, 0.15 } },
		transparency = { { 0, 0.1 }, { 0.6, 0.35 }, { 1, 1 } },
		lifetime = { 0.22, 0.38 },
		speed = { 0.5, 2 },
		rate = 34,
		drag = 2,
		accel = Vector3.new(0, 4, 0),
		rotation = { 0, 360 },
		rotSpeed = { -120, 120 },
		lightEmission = 0.55,
		zOffset = 0.4,
		role = "flight",
		emitDuration = 1.5,
	}
end

local function embers(): EmitterSpec
	return {
		name = "Embers",
		texture = TEX.embers,
		color = { C.FireTip, C.FireCore },
		size = { { 0, 0.5 }, { 1, 0 } },
		transparency = { { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } },
		lifetime = { 0.5, 0.9 },
		speed = { 2, 5 },
		rate = 16,
		drag = 2,
		accel = Vector3.new(0, 5, 0),
		lightEmission = 0.6,
		zOffset = 0.5,
		role = "flight",
		emitDuration = 1.5,
	}
end

-- The 14 signature trails (Catalog accents; rarity sets how rich: Common one ribbon and two emitters, Uncommon a
-- core, Epic twin ribbons or three emitters, Exclusive everything).
local TRAILS: { TrailSpec } = {
	{
		id = "kitty_bread",
		theme = "Fresh-baked: a warm crust ribbon, flour puffs and crumbs",
		ribbons = { ribbonOf({ hex("#D98E47"), C.Vanilla }, 0.95, 0.28) },
		emitters = {
			puffs("FlourPuffs", C.Cream, 12, 0.35, 0.95, 0.45),
			dots("Crumbs", { C.Caramel, C.Crust }, 9, 0.16, 28, 0.25),
		},
	},
	{
		id = "toast",
		theme = "Buttered toast: a golden ribbon, crumbs and butter glints",
		ribbons = { ribbonOf({ hex("#C9853F"), C.Lemon, C.GlowCream }, 0.9, 0.28) },
		emitters = {
			dots("Crumbs", { C.Crust, C.Caramel }, 10, 0.15, 30, 0.3),
			sparkles("ButterGlints", C.ButterGlint, 6, 0.4),
		},
	},
	{
		id = "banana",
		theme = "Banana spiral: two twisting peel ribbons and sunny sparkles",
		followRoll = true,
		ribbons = {
			{
				name = "PeelA",
				offset = 0.5,
				width = 0.5,
				colors = { hex("#FFE066"), C.LampGlow },
				transparency = FADE,
				lifetime = 0.34,
				lightEmission = 0,
				faceCamera = false,
			},
			{
				name = "PeelB",
				offset = -0.5,
				width = 0.5,
				colors = { C.Peel, C.LampGlow },
				transparency = FADE,
				lifetime = 0.34,
				lightEmission = 0,
				faceCamera = false,
			},
		},
		emitters = {
			sparkles("SunSparkles", { C.FireTip, C.White }, 9, 0.45),
			dots("PeelBits", C.Peel, 5, 0.14, 18, 0.4),
		},
	},
	{
		id = "butter",
		theme = "Melting butter: a wide glossy ribbon, golden drips and shimmer",
		ribbons = { ribbonOf({ C.Lemon, C.GlowCream, C.Cream }, 1.15, 0.34), core({ C.White, C.GlowCream }) },
		emitters = {
			dots("MeltDrops", { C.Lemon, C.FireTip }, 10, 0.2, 38, -0.45, { 0.5, 0.8 }),
			sparkles("Shimmer", C.GlowCream, 12, 0.5),
		},
	},
	{
		id = "chocolate",
		theme = "Hot cocoa: a rich cocoa-to-caramel ribbon, cocoa dust and chocolate chips",
		ribbons = { ribbonOf({ hex("#7A4632"), C.Caramel, C.Wafer }, 1.05, 0.32), core({ C.Wafer, C.Cream }) },
		emitters = {
			puffs("CocoaDust", C.Cocoa, 10, 0.4, 1.1, 0.5),
			dots("Chips", { C.Chip, C.Cocoa }, 8, 0.2, 32, 0.15),
		},
	},
	{
		id = "bird",
		theme = "Birdie glide: two wingtip streams, drifting feathers and sky sparkles",
		ribbons = {
			ribbonOf({ hex("#7CC0F5"), C.Glass, C.White }, 0.42, 0.42, 0.75, "WingL"),
			ribbonOf({ hex("#7CC0F5"), C.Glass, C.White }, 0.42, 0.42, -0.75, "WingR"),
			core({ C.White, C.Glass }, 0.3, 0.2),
		},
		emitters = {
			feathers(),
			sparkles("SkySparkles", { C.White, hex("#7CC0F5") }, 10, 0.45),
		},
	},
	{
		id = "donut",
		theme = "Sprinkle donut: a strawberry-glaze ribbon and rainbow sprinkles",
		ribbons = { ribbonOf({ hex("#FF8FB1"), C.Bubblegum, C.Cream }, 1.05, 0.32), core() },
		emitters = {
			dots("SprinkleMint", C.Mint, 5, 0.17, 26, 0.7),
			dots("SprinkleLemon", C.Lemon, 5, 0.17, 26, 0.7),
			dots("SprinkleSky", C.Sky, 5, 0.17, 26, 0.7),
			dots("SprinkleLavender", C.Lavender, 5, 0.17, 26, 0.7),
			sparkles("Glaze", C.White, 6, 0.4),
		},
	},
	{
		id = "dragon",
		theme = "Dragon comet: a teal-to-fire ribbon, roaring flames, embers and smoke",
		ribbons = {
			{
				name = "Ribbon",
				offset = 0,
				width = 1.3,
				colors = { C.FireTip, C.FireCore, C.FireDeep }, -- teal -> orange went through olive
				transparency = { { 0, 0.05 }, { 0.5, 0.3 }, { 1, 1 } },
				lifetime = 0.4,
				lightEmission = 0.12,
			},
			core({ C.White, C.DragonTeal }, 0.45, 0.24),
		},
		emitters = { flames(), embers(), puffs("Smoke", C.Soot, 8, 0.7, 1.7, 0.55) },
	},
	{
		id = "boba_bear",
		theme = "Boba tea: a milk-tea ribbon, tapioca pearls and milk puffs",
		ribbons = { ribbonOf({ hex("#B07A52"), C.MilkTea, C.Cream }, 0.95, 0.3) },
		emitters = {
			dots("Pearls", C.Pearl, 6, 0.24, 34, nil, { 0.6, 0.9 }),
			puffs("MilkPuffs", C.Cream, 7, 0.3, 0.8, 0.5),
		},
	},
	{
		id = "pancake_pup",
		theme = "Pancake stack: an amber syrup ribbon, syrup drips and butter glints",
		ribbons = { ribbonOf({ hex("#C8752A"), C.FireCore, C.GlowCream }, 0.95, 0.3) },
		emitters = {
			dots("SyrupDrips", { C.Syrup, hex("#C8752A") }, 8, 0.2, 40, -0.5, { 0.45, 0.7 }),
			sparkles("ButterGlints", C.ButterGlint, 5, 0.4),
		},
	},
	{
		id = "mochi_fox",
		theme = "Mochi fox: a peach-to-sakura ribbon, drifting petals and soft glints",
		ribbons = { ribbonOf({ hex("#F39A4C"), C.Petal, C.Cream }, 1.0, 0.34), core({ C.White, C.Petal }) },
		emitters = { petals(), sparkles("Glints", C.White, 6, 0.38) },
	},
	{
		id = "strawberry_frog",
		theme = "Jelly frog: a strawberry-to-leaf ribbon, jelly bubbles and seeds",
		ribbons = { ribbonOf({ hex("#FF9AA8"), C.Bubblegum, C.Mint }, 1.0, 0.32), core({ C.White, C.Bubblegum }) },
		emitters = {
			glowBubbles("JellyBubbles", { C.Bubblegum, C.White }, 9, 0.5),
			dots("Seeds", C.Seed, 6, 0.12, 22, 0.35),
		},
	},
	{
		id = "cloud_bunny",
		theme = "Cloud bunny: a pastel rainbow ribbon, fluffy cloud puffs and star twinkles",
		ribbons = {
			ribbonOf({ hex("#D5C8F6"), C.Sky, C.Mint, C.Lemon }, 1.1, 0.4),
			core({ C.White, hex("#D5C8F6") }, 0.34, 0.22),
		},
		emitters = {
			puffs("Clouds", { C.White, hex("#EDE6FB") }, 10, 0.9, 2.2, 0.3),
			sparkles("Stars", { C.LampGlow, C.White }, 10, 0.55),
		},
	},
	{
		id = "cupcake_axolotl",
		theme = "Cupcake axolotl: twin frosting streams, sea-glass bubbles and sprinkle dots",
		ribbons = {
			ribbonOf({ hex("#F9AFCB"), C.Bubblegum, C.SeaGlass }, 0.5, 0.38, 0.55, "FrostingL"),
			ribbonOf({ C.SeaGlass, C.Glass, hex("#F9AFCB") }, 0.5, 0.38, -0.55, "FrostingR"),
			core({ C.White, hex("#F9AFCB") }, 0.3, 0.2),
		},
		emitters = {
			glowBubbles("Bubbles", { C.SeaGlass, C.White }, 9, 0.45),
			dots("Frosting", { C.White, C.Bubblegum }, 6, 0.14, 20, 0.2),
			sparkles("Glints", C.White, 6, 0.4),
		},
	},
	-- Series 01 (2026-11-10): Claude Design's CATALOG2 trails (sd/toys2.js T(a, b, width, life, shape, colours, rate)).
	-- The live library may be tuned in VFX Studio, so these 6 were built and copied in alone.
	{
		id = "berry_jelly",
		theme = "Berry jelly: a pink jelly ribbon and jelly drops with seeds",
		ribbons = { ribbonOf({ hex("#FFC2D4"), hex("#FF7AA5"), hex("#FF5C8E") }, 0.9, 0.34), core({ C.White, hex("#FFC2D4") }) },
		emitters = { dots("JellyDrops", { hex("#FF5C8E"), hex("#FF7AA5"), hex("#FFE39A") }, 8, 0.16, 20, -0.4) },
	},
	{
		id = "peachy",
		theme = "Peachy: a peach-to-coral ribbon, drifting peach petals and a leaf or two",
		ribbons = { ribbonOf({ hex("#FFD977"), hex("#FFA868"), hex("#FF8E7A") }, 0.95, 0.34), core({ C.White, hex("#FFD977") }) },
		emitters = { dots("Petals", { hex("#FF9F7A"), hex("#FFD977"), hex("#67C46A") }, 7, 0.16, 6, 0.5, { 0.6, 1.0 }) },
	},
	{
		id = "grapey",
		theme = "Grapey: a grape-purple ribbon and little grape beads",
		ribbons = { ribbonOf({ hex("#E0AAFF"), hex("#B27AEB"), hex("#A45AE0") }, 0.9, 0.36), core({ C.White, hex("#E0AAFF") }) },
		emitters = {
			glowBubbles("Grapes", { hex("#B27AEB"), hex("#8A4FD1") }, 8, 0.4),
			dots("Leaves", hex("#6CC56A"), 3, 0.14, 10, 0.5),
		},
	},
	{
		id = "bao_buddy",
		theme = "Bao buddy: a pearl-white ribbon and rising steam puffs",
		ribbons = { ribbonOf({ C.White, hex("#F4E8F7"), hex("#E9DCF0") }, 1.15, 0.42), core({ C.White, C.White }) },
		emitters = { puffs("Steam", { C.White, hex("#FFF1E3") }, 9, 0.6, 1.6, 0.3) },
	},
	{
		id = "pando",
		theme = "Pando: a warm honey ribbon and drifting bamboo leaves",
		ribbons = { ribbonOf({ hex("#FFF3C4"), hex("#FFD27A"), hex("#FFB347") }, 0.95, 0.36), core({ C.White, hex("#FFF3C4") }) },
		emitters = { dots("BambooLeaves", { hex("#7CC77A"), hex("#FFE08A") }, 7, 0.16, 6, 0.5, { 0.6, 1.0 }) },
	},
	{
		id = "cosmo",
		theme = "Cosmo: twin lilac-to-sky streams, a stardust of bead colours and white star sparkles",
		ribbons = {
			ribbonOf({ hex("#C7A0FF"), hex("#A8B4FF"), hex("#8AB8FF") }, 0.6, 0.5, 0.45, "OrbitL"),
			ribbonOf({ hex("#8AB8FF"), hex("#A8B4FF"), hex("#C7A0FF") }, 0.6, 0.5, -0.45, "OrbitR"),
			core({ C.White, hex("#C7A0FF") }, 0.32, 0.22),
		},
		emitters = {
			sparkles("Stardust", { hex("#FF9FC7"), hex("#FFD36B"), hex("#8FE3C2"), hex("#8AB8FF"), hex("#C7A0FF") }, 14, 0.5),
			sparkles("Sparkle", C.White, 8, 0.35),
		},
	},
	-- Frosty Box (2026-11-10): Claude Design's CATALOG2 round 2 trails (sd/toys2.js:868-874). Built and copied in alone,
	-- like Series 01's.
	{
		id = "cone_cub",
		theme = "Cone Cub: a cream-to-waffle ribbon and waffle crumbs",
		ribbons = { ribbonOf({ hex("#FFF1DC"), hex("#F7D2A2"), hex("#E9B46C") }, 0.9, 0.34), core({ C.White, hex("#FFF1DC") }) },
		emitters = { dots("WaffleCrumbs", { hex("#E9B46C"), hex("#F7D2A2"), C.White }, 8, 0.16, 20, -0.4) },
	},
	{
		id = "slushy_seal",
		theme = "Slushy Seal: a frost-to-slush blue ribbon and slush bits",
		ribbons = { ribbonOf({ hex("#DDF4FF"), hex("#8ED3FA"), hex("#7CC8F2") }, 0.95, 0.36), core({ C.White, hex("#DDF4FF") }) },
		emitters = { dots("Slush", { hex("#8ED3FA"), C.White, hex("#7CC8F2") }, 8, 0.16, 20, -0.4) },
	},
	{
		id = "ice_pop_beaver",
		theme = "Ice Pop Beaver: a cream-to-chocolate ribbon, chocolate drips and a leaf",
		ribbons = { ribbonOf({ hex("#F6CFA0"), hex("#A0623A") }, 0.9, 0.32), core({ C.White, hex("#F6CFA0") }) },
		emitters = { dots("ChocolateDrips", { hex("#A0623A"), hex("#F6CFA0"), hex("#6CC56A") }, 8, 0.16, 20, -0.4) },
	},
	{
		id = "mint_chip_mouse",
		theme = "Mint Chip Mouse: a mint ribbon and chocolate chips",
		ribbons = { ribbonOf({ hex("#D6F8E7"), hex("#9AE4C2") }, 0.95, 0.36), core({ C.White, hex("#D6F8E7") }) },
		emitters = { dots("Chips", { hex("#5A3A2E"), hex("#9AE4C2"), C.White }, 8, 0.16, 20, -0.4) },
	},
	{
		id = "sundae_manatee",
		theme = "Sundae Manatee: a lavender-to-syrup ribbon, syrup drops, cherries and cream",
		ribbons = { ribbonOf({ hex("#E8E4FC"), hex("#8A4F3A") }, 1.1, 0.4), core({ C.White, hex("#E8E4FC") }) },
		emitters = { dots("SyrupDrops", { hex("#8A4F3A"), hex("#F0445E"), hex("#FFF8F0") }, 8, 0.16, 20, -0.4) },
	},
	{
		id = "gelato_narwhal",
		theme = "Gelato Narwhal: a frost-blue ribbon, ice cubes and white sparkles",
		ribbons = { ribbonOf({ hex("#E8F8FF"), hex("#8CCDEB") }, 1.1, 0.44), core({ C.White, hex("#E8F8FF") }) },
		emitters = {
			dots("IceCubes", { C.White, hex("#8CCDEB"), hex("#E9B46C") }, 10, 0.16, 20, -0.4),
			sparkles("Sparkle", C.White, 8, 0.35),
		},
	},
	{
		id = "parfait_wyvern",
		theme = "Parfait Wyvern: twin cream-to-pink layer streams, sugar petals and gold sparkles",
		ribbons = {
			ribbonOf({ hex("#FFF3E6"), hex("#FF8FAE") }, 0.65, 0.5, 0.45, "LayerL"),
			ribbonOf({ hex("#FF8FAE"), hex("#FFF3E6") }, 0.65, 0.5, -0.45, "LayerR"),
			core({ C.White, hex("#FFF3E6") }, 0.32, 0.22),
		},
		emitters = {
			dots("Petals", { hex("#FF8FAE"), hex("#FFDD88"), hex("#A8A2F2"), C.White }, 12, 0.16, 6, 0.5, { 0.6, 1.0 }),
			sparkles("Sugar", hex("#FFDD88"), 8, 0.35),
		},
	},
	-- Lava Box (2026-11-10): Claude Design's CATALOG2 round 3 trails (sd/toys2.js). Built and copied in alone, like
	-- the Frosty Box's.
	{
		id = "cocoa_quokka",
		theme = "Cocoa Quokka: a milk-to-cocoa ribbon, cocoa drops and mini marshmallows",
		ribbons = { ribbonOf({ hex("#FFE6D0"), hex("#7A4A32") }, 0.9, 0.34), core({ C.White, hex("#FFE6D0") }) },
		emitters = { dots("CocoaDrops", { hex("#7A4A32"), C.White, hex("#F0786A") }, 8, 0.16, 18, -0.4) },
	},
	{
		id = "cinder_bun",
		theme = "Cinder Bun: a dough-to-crust ribbon, toast crumbs and a little smoke",
		ribbons = { ribbonOf({ hex("#F6CE94"), hex("#A2603A") }, 0.95, 0.34), core({ C.White, hex("#F6CE94") }) },
		emitters = { dots("Crumbs", { hex("#DB9852"), hex("#FFB35A"), hex("#E9E4EE") }, 8, 0.16, 20, -0.4) },
	},
	{
		id = "smore_skunk",
		theme = "S'more Skunk: a mallow-to-chocolate ribbon and graham crumbs",
		ribbons = { ribbonOf({ hex("#FFF6EC"), hex("#8E5E48") }, 1.0, 0.38), core({ C.White, hex("#FFF6EC") }) },
		emitters = { dots("Graham", { hex("#DCA466"), hex("#FFF6EC"), hex("#8E5E48") }, 8, 0.16, 22, -0.4) },
	},
	{
		id = "cayenne_kiwi",
		theme = "Cayenne Kiwi: a hot orange ribbon and rising embers",
		ribbons = { ribbonOf({ hex("#FFD08A"), hex("#FF8A3C") }, 0.9, 0.36), core({ C.White, hex("#FFD08A") }) },
		emitters = { dots("Embers", { hex("#FF8A3C"), hex("#FFC24A"), hex("#FFD08A") }, 8, 0.16, 24, 0.5) },
	},
	{
		id = "pizza_pangolin",
		theme = "Pizza Pangolin: a cheese-to-crust ribbon, cheese bits and pepperoni",
		ribbons = { ribbonOf({ hex("#FFE2A0"), hex("#E39B52") }, 1.1, 0.4), core({ C.White, hex("#FFE2A0") }) },
		emitters = { dots("Toppings", { hex("#FFC94A"), hex("#E39B52"), hex("#C8503F") }, 8, 0.16, 24, -0.4) },
	},
	{
		id = "lava_cake_hippo",
		theme = "Lava Cake Hippo: a molten ribbon, glowing drops and embers",
		ribbons = { ribbonOf({ hex("#FFC46B"), hex("#9C5E40") }, 1.1, 0.44), core({ C.White, hex("#FFC46B") }) },
		emitters = {
			dots("GlowDrops", { hex("#FF9A3C"), hex("#FFC46B"), hex("#9C5E40") }, 10, 0.16, 20, -0.4),
			sparkles("Embers", hex("#FFC46B"), 8, 0.35),
		},
	},
	{
		id = "mallow_behemoth",
		theme = "Mallow Behemoth: twin mallow-to-toast streams, embers and gold sparkles",
		ribbons = {
			ribbonOf({ hex("#FFF1E0"), hex("#EDB06A") }, 0.65, 0.5, 0.45, "ToastL"),
			ribbonOf({ hex("#EDB06A"), hex("#FFF1E0") }, 0.65, 0.5, -0.45, "ToastR"),
			core({ C.White, hex("#FFF1E0") }, 0.32, 0.22),
		},
		emitters = {
			dots("Embers", { hex("#FFB347"), hex("#FF8A3C"), hex("#FFF1E0") }, 12, 0.16, 6, 0.5, { 0.6, 1.0 }),
			sparkles("Gold", hex("#FFE7A0"), 8, 0.35),
		},
	},
	-- Prism Box (2026-11-10): Claude Design's CATALOG2 round 4 trails (sd/toys2.js:884-890). Built and copied in alone,
	-- like the Lava Box's.
	{
		id = "taffy_tadpole",
		theme = "Taffy Tadpole: a pink-to-blue taffy ribbon and little stars",
		ribbons = { ribbonOf({ hex("#FFD6EA"), hex("#B8D8FF") }, 0.9, 0.36), core({ C.White, hex("#FFD6EA") }) },
		emitters = { dots("Stars", { hex("#FFB3D1"), hex("#B8D8FF"), hex("#FFE27A") }, 8, 0.16, 20, -0.4) },
	},
	{
		id = "jellybean_piglet",
		theme = "Jellybean Piglet: a pink ribbon and rainbow jellybeans",
		ribbons = { ribbonOf({ hex("#FFD6E4"), hex("#FF8FB4") }, 0.9, 0.34), core({ C.White, hex("#FFD6E4") }) },
		emitters = { dots("Jellybeans", { hex("#FF8FB4"), hex("#FFE27A"), hex("#8FE3C2"), hex("#C7A0FF") }, 8, 0.16, 22, -0.4) },
	},
	{
		id = "cotton_candy_alpaca",
		theme = "Cotton Candy Alpaca: a wide pink-to-blue fluff ribbon and fluff puffs",
		ribbons = { ribbonOf({ hex("#FFF0F8"), hex("#B8CFFF") }, 1.1, 0.5), core({ C.White, hex("#FFF0F8") }) },
		emitters = { dots("Fluff", { hex("#FFB8DA"), hex("#B8CFFF"), C.White }, 8, 0.16, 26, -0.2) },
	},
	{
		id = "lollipop_lemur",
		theme = "Lollipop Lemur: a pink swirl ribbon and sugar stars",
		ribbons = { ribbonOf({ hex("#FFD6EE"), hex("#FF8FC8") }, 0.9, 0.36), core({ C.White, hex("#FFD6EE") }) },
		emitters = { dots("Stars", { hex("#FF8FC8"), C.White, hex("#FFE27A") }, 8, 0.16, 22, -0.4) },
	},
	{
		id = "gumball_goat",
		theme = "Gumball Goat: a white-to-red ribbon and rainbow gumballs",
		ribbons = { ribbonOf({ C.White, hex("#F2667A") }, 0.95, 0.38), core({ C.White, hex("#FFE0E5") }) },
		emitters = { dots("Gumballs", { hex("#FF7AA5"), hex("#FFD36B"), hex("#8FE3C2"), hex("#8AB8FF"), hex("#C7A0FF") }, 10, 0.16, 26, -0.4) },
	},
	{
		id = "gummy_pufferfish",
		theme = "Gummy Pufferfish: a yellow-to-pink gummy ribbon, gummy bits and white sparkles",
		ribbons = { ribbonOf({ hex("#FFE27A"), hex("#FF7AA5") }, 1.0, 0.42), core({ C.White, hex("#FFE27A") }) },
		emitters = {
			dots("Gummies", { hex("#FF7AA5"), hex("#FFB36B"), hex("#FFE27A"), hex("#8FE3C2") }, 10, 0.16, 28, -0.4),
			sparkles("Sparkle", C.White, 8, 0.35),
		},
	},
	{
		id = "candyglass_qilin",
		theme = "Candyglass Qilin: twin pearl-to-lilac streams, candyglass stars and white sparkles",
		ribbons = {
			ribbonOf({ hex("#F2E8FF"), hex("#C7A0FF") }, 0.65, 0.5, 0.45, "PrismL"),
			ribbonOf({ hex("#C7A0FF"), hex("#F2E8FF") }, 0.65, 0.5, -0.45, "PrismR"),
			core({ C.White, hex("#F2E8FF") }, 0.32, 0.22),
		},
		emitters = {
			dots("Candyglass", { hex("#BDEFE0"), hex("#D8C8FF"), hex("#FFD3B5"), hex("#FFE27A") }, 12, 0.16, 6, 0.5, { 0.6, 1.0 }),
			sparkles("Sparkle", C.White, 8, 0.35),
		},
	},
	-- Halo Box (2026-11-10): Claude Design's CATALOG2 round 5 trails (sd/toys2.js:892-898). Built and copied in alone,
	-- like the Prism Box's.
	{
		id = "meringue_chick",
		theme = "Meringue Chick: a cream-to-gold ribbon and meringue petals",
		ribbons = { ribbonOf({ hex("#FFFDF6"), hex("#F4D9A0") }, 0.85, 0.36), core({ C.White, hex("#FFFDF6") }) },
		emitters = { dots("Petals", { C.White, hex("#F4D9A0"), hex("#FFE7A0") }, 8, 0.16, 20, -0.4) },
	},
	{
		id = "cream_puff_kitten",
		theme = "Cream Puff Kitten: a cream-to-golden ribbon and cream puffs",
		ribbons = { ribbonOf({ hex("#FFF4E2"), hex("#E9B66E") }, 0.95, 0.38), core({ C.White, hex("#FFF4E2") }) },
		emitters = { dots("Cream", { C.White, hex("#E9B66E"), hex("#FFF1C9") }, 8, 0.16, 22, -0.4) },
	},
	{
		id = "bumble_bun",
		theme = "Bumble Bun: a honey ribbon and honey drops",
		ribbons = { ribbonOf({ hex("#FFE9A8"), hex("#E8A23A") }, 0.9, 0.38), core({ C.White, hex("#FFE9A8") }) },
		emitters = { dots("Honey", { hex("#F0A830"), hex("#FFE9A8"), C.White }, 8, 0.16, 22, -0.4) },
	},
	{
		id = "waffle_corgi",
		theme = "Waffle Corgi: a waffle ribbon and waffle crumbs",
		ribbons = { ribbonOf({ hex("#FAE3B4"), hex("#E5A85C") }, 0.9, 0.36), core({ C.White, hex("#FAE3B4") }) },
		emitters = { dots("Waffle", { hex("#E5A85C"), hex("#FFF1A8"), C.White }, 8, 0.16, 22, -0.4) },
	},
	{
		id = "custard_cherub",
		theme = "Custard Cherub: a custard-to-gold ribbon, petals and warm sparkles",
		ribbons = { ribbonOf({ hex("#FFF8E0"), hex("#F4D27A") }, 1.0, 0.44), core({ C.White, hex("#FFF8E0") }) },
		emitters = {
			dots("Petals", { C.White, hex("#F4D27A"), hex("#FFF1C4") }, 10, 0.16, 24, -0.4),
			sparkles("Sparkle", hex("#FFF1C9"), 8, 0.35),
		},
	},
	{
		id = "souffle_seraph",
		theme = "Souffle Seraph: twin cream-to-gold streams, feather petals and white sparkles",
		ribbons = {
			ribbonOf({ hex("#FFF4D6"), hex("#F4D27A") }, 0.65, 0.48, 0.45, "HaloL"),
			ribbonOf({ hex("#F4D27A"), hex("#FFF4D6") }, 0.65, 0.48, -0.45, "HaloR"),
			core({ C.White, hex("#FFF4D6") }, 0.32, 0.22),
		},
		emitters = {
			dots("Feathers", { C.White, hex("#F4D27A"), hex("#FFE7A8") }, 12, 0.16, 6, 0.5, { 0.6, 1.0 }),
			sparkles("Sparkle", C.White, 8, 0.35),
		},
	},
	{
		id = "divine_loaf",
		theme = "Divine Loaf: twin pearl-to-gold streams, gold and lilac stars and warm sparkles",
		ribbons = {
			ribbonOf({ hex("#FFFDF8"), hex("#F4D27A") }, 0.7, 0.52, 0.5, "RoyalL"),
			ribbonOf({ hex("#F4D27A"), hex("#FFFDF8") }, 0.7, 0.52, -0.5, "RoyalR"),
			core({ C.White, hex("#FFFDF8") }, 0.34, 0.24),
		},
		emitters = {
			dots("Stars", { hex("#F4D27A"), C.White, hex("#D8C8FF") }, 14, 0.16, 6, 0.5, { 0.6, 1.0 }),
			sparkles("Sparkle", hex("#FFF1C9"), 10, 0.35),
		},
	},
	-- Christmas (big job item 11, 2026-11-10; the design's CATALOG2 trails: Elk a #F2C48C b #C98A4E with white, red,
	-- green and cookie stars; Puffin a #FFFFFF b #F04A5E, twin, red, white and green stars and a white sparkle).
	{
		id = "gingersnap_elk",
		theme = "Gingersnap Elk: a cookie-to-ginger ribbon, icing and gumdrop bits and warm sparkles",
		ribbons = { ribbonOf({ hex("#F2C48C"), hex("#C98A4E") }, 1.0, 0.44), core({ C.White, hex("#F2C48C") }) },
		emitters = {
			dots("Gumdrops", { C.White, hex("#F04A5E"), hex("#5DCB8A"), hex("#C98A4E") }, 10, 0.16, 24, -0.4),
			sparkles("Sparkle", hex("#FFF1C9"), 8, 0.35),
		},
	},
	{
		id = "peppermint_puffin",
		theme = "Peppermint Puffin: twin white-to-red peppermint streams, red, white and green bits and white sparkles",
		ribbons = {
			ribbonOf({ C.White, hex("#F04A5E") }, 0.65, 0.48, 0.45, "MintL"),
			ribbonOf({ hex("#F04A5E"), C.White }, 0.65, 0.48, -0.45, "MintR"),
			core({ C.White, hex("#BFF5E0") }, 0.32, 0.22),
		},
		emitters = {
			dots("Mints", { hex("#F04A5E"), C.White, hex("#5DCB8A") }, 12, 0.16, 6, 0.5, { 0.6, 1.0 }),
			sparkles("Sparkle", C.White, 8, 0.35),
		},
	},
}
ThrowVfxBuilder.TRAILS = TRAILS

local function buildTrail(spec: TrailSpec): Part
	local part = carrier(spec.id)
	part:SetAttribute("SD_Theme", spec.theme)
	part:SetAttribute("SD_FollowRoll", spec.followRoll == true)
	for _, r in spec.ribbons do
		ribbon(part, r)
	end
	local emit = attachment(part, "Emit", Vector3.zero)
	for _, e in spec.emitters do
		ThrowVfxBuilder.emitter(e).Parent = emit
	end
	return part
end

-- Bursts -------------------------------------------------------------------------------------------------------------

local function ring(
	name: string,
	color: Color3,
	sizeTo: number,
	lifetime: number,
	flat: boolean,
	delay: number?
): EmitterSpec
	return {
		name = name,
		texture = TEX.shock,
		color = color,
		size = { { 0, sizeTo * 0.15 }, { 1, sizeTo } },
		transparency = { { 0, 0.15 }, { 0.5, 0.45 }, { 1, 1 } },
		lifetime = { lifetime },
		speed = { if flat then 0.01 else 0 },
		spread = Vector2.zero,
		lightEmission = 0.3,
		zOffset = 0.2,
		orientation = if flat
			then Enum.ParticleOrientation.VelocityPerpendicular
			else Enum.ParticleOrientation.FacingCamera,
		emitCount = 1,
		emitDelay = delay,
	}
end

local function burstPart(name: string, note: string): (Part, Attachment)
	local part = carrier(name)
	part:SetAttribute("SD_Theme", note)
	local a = attachment(part, "Burst", Vector3.zero)
	return part, a
end

local function addAll(a: Attachment, specs: { EmitterSpec })
	for _, e in specs do
		ThrowVfxBuilder.emitter(e).Parent = a
	end
end
local function buildBursts(): { Part }
	local out: { Part } = {}

	-- Release: the air pops off the hand (the old FxShapes ring stays ProjectileRenderer's).
	local release, ra = burstPart("Release", "At the hand on the release: air puffs, accent sparks and speed streaks")
	addAll(ra, {
		{
			name = "AirPuffs",
			texture = TEX.smoke,
			color = C.White,
			size = { { 0, 0.5 }, { 1, 1.4 } },
			transparency = { { 0, 0.35 }, { 1, 1 } },
			lifetime = { 0.25, 0.4 },
			speed = { 6, 11 },
			drag = 8,
			emitCount = 7,
			lightInfluence = 0.3,
		},
		{
			name = "Sparks",
			texture = TEX.star,
			color = C.White,
			size = { { 0, 0.6 }, { 1, 0 } },
			transparency = { { 0, 0 }, { 1, 0.6 } },
			lifetime = { 0.25, 0.45 },
			speed = { 10, 17 },
			drag = 6,
			rotSpeed = { -300, 300 },
			lightEmission = 0.5,
			zOffset = 0.5,
			emitCount = 9,
			tint = "accent",
		},
		{
			name = "Streaks",
			texture = TEX.dot,
			color = C.White,
			size = { { 0, 0.22 }, { 1, 0 } },
			transparency = { { 0, 0.1 }, { 1, 1 } },
			lifetime = { 0.14, 0.24 },
			speed = { 20, 30 },
			drag = 4,
			squash = { { 0, -2.5 }, { 1, -1.5 } },
			orientation = Enum.ParticleOrientation.VelocityParallel,
			lightEmission = 0.4,
			emitCount = 6,
		},
	})
	table.insert(out, release)

	-- Bounce: every hop on a surface (Y = the normal).
	local bounce, ba = burstPart("Bounce", "Every bounce: a dust skirt, a flat ring and a few accent bits")
	addAll(ba, {
		{
			name = "Dust",
			texture = TEX.smoke,
			color = C.Dust,
			size = { { 0, 0.5 }, { 1, 1.5 } },
			transparency = { { 0, 0.3 }, { 0.5, 0.6 }, { 1, 1 } },
			lifetime = { 0.35, 0.6 },
			speed = { 5, 9 },
			spread = Vector2.new(82, 82),
			drag = 6,
			accel = Vector3.new(0, 2, 0),
			rotSpeed = { -60, 60 },
			lightInfluence = 0.5,
			emitCount = 8,
		},
		ring("Ring", C.White, 4.5, 0.3, true),
		{
			name = "Bits",
			texture = TEX.dot,
			color = C.White,
			size = { { 0, 0.22 }, { 1, 0 } },
			transparency = { { 0, 0 }, { 1, 0.2 } },
			lifetime = { 0.35, 0.55 },
			speed = { 8, 13 },
			spread = Vector2.new(45, 45),
			accel = Vector3.new(0, -45, 0),
			zOffset = 0.3,
			emitCount = 6,
			tint = "accent",
		},
	})
	table.insert(out, bounce)

	-- Land: the first, heavy touch-down (material flavours by SD_Feels).
	local land, la = burstPart("Land", "The first touch-down: a big dust skirt, a double ring and the toy's own splash")
	addAll(la, {
		{
			name = "Dust",
			texture = TEX.smoke,
			color = C.Dust,
			size = { { 0, 0.8 }, { 1, 2.3 } },
			transparency = { { 0, 0.2 }, { 0.5, 0.55 }, { 1, 1 } },
			lifetime = { 0.45, 0.8 },
			speed = { 7, 13 },
			spread = Vector2.new(84, 84),
			drag = 5,
			accel = Vector3.new(0, 2.5, 0),
			rotSpeed = { -60, 60 },
			lightInfluence = 0.5,
			emitCount = 14,
		},
		ring("Ring", C.White, 7, 0.34, true),
		ring("RingLate", C.White, 4, 0.3, true, 0.06),
		{
			name = "Splash",
			texture = TEX.dot,
			color = C.White,
			size = { { 0, 0.32 }, { 1, 0.05 } },
			transparency = { { 0, 0 }, { 1, 0.3 } },
			lifetime = { 0.4, 0.65 },
			speed = { 10, 17 },
			spread = Vector2.new(50, 50),
			accel = Vector3.new(0, -50, 0),
			squash = { { 0, -0.6 }, { 1, 0 } },
			orientation = Enum.ParticleOrientation.VelocityParallel,
			lightEmission = 0,
			zOffset = 0.3,
			emitCount = 12,
			tint = "accent",
			feels = "jelly,mochi",
		},
		{
			name = "Crumbs",
			texture = TEX.dot,
			color = C.White,
			size = { { 0, 0.22 }, { 1, 0.1 } },
			transparency = { { 0, 0 }, { 1, 0.3 } },
			lifetime = { 0.45, 0.7 },
			speed = { 9, 15 },
			spread = Vector2.new(55, 55),
			accel = Vector3.new(0, -55, 0),
			rotSpeed = { -300, 300 },
			zOffset = 0.3,
			emitCount = 10,
			tint = "accent",
			feels = "foam",
		},
		{
			name = "Fluff",
			texture = TEX.smoke,
			color = C.White,
			size = { { 0, 0.6 }, { 1, 1.6 } },
			transparency = { { 0, 0.2 }, { 1, 1 } },
			lifetime = { 0.5, 0.9 },
			speed = { 3, 6 },
			spread = Vector2.new(70, 70),
			drag = 3,
			accel = Vector3.new(0, 1.5, 0),
			emitCount = 8,
			feels = "plush",
		},
		{
			name = "Stars",
			texture = TEX.star,
			color = C.White,
			size = { { 0, 0.55 }, { 1, 0 } },
			transparency = { { 0, 0 }, { 1, 0.5 } },
			lifetime = { 0.35, 0.6 },
			speed = { 6, 11 },
			spread = Vector2.new(60, 60),
			drag = 5,
			rotSpeed = { -300, 300 },
			lightEmission = 0.5,
			zOffset = 0.5,
			emitCount = 6,
			tint = "accent",
		},
	})
	table.insert(out, land)

	-- Skid: on while it slides or rolls along a surface (VFX Studio previews it for EmitDuration).
	local skid, sa = burstPart("Skid", "While it slides or rolls: a low dust trail")
	addAll(sa, {
		{
			name = "SkidDust",
			texture = TEX.smoke,
			color = C.Dust,
			size = { { 0, 0.4 }, { 1, 1.2 } },
			transparency = { { 0, 0.4 }, { 1, 1 } },
			lifetime = { 0.35, 0.6 },
			speed = { 1, 3 },
			spread = Vector2.new(70, 70),
			drag = 4,
			accel = Vector3.new(0, 1.5, 0),
			rotSpeed = { -60, 60 },
			lightInfluence = 0.5,
			rate = 22,
			emitDuration = 1,
			role = "while",
		},
	})
	table.insert(out, skid)

	-- Settle: it comes to rest, flattens face-up and peels back up.
	local settle, sea = burstPart("Settle", "At rest: a soft puff and accent twinkles")
	addAll(sea, {
		{
			name = "SoftPuff",
			texture = TEX.smoke,
			color = C.White,
			size = { { 0, 0.6 }, { 1, 1.5 } },
			transparency = { { 0, 0.45 }, { 1, 1 } },
			lifetime = { 0.4, 0.6 },
			speed = { 2, 4 },
			spread = Vector2.new(80, 80),
			drag = 4,
			emitCount = 5,
		},
		{
			name = "Twinkle",
			texture = TEX.star,
			color = C.White,
			size = { { 0, 0 }, { 0.3, 0.6 }, { 1, 0 } },
			transparency = { { 0, 0 }, { 1, 0.3 } },
			lifetime = { 0.45, 0.75 },
			speed = { 1.5, 3.5 },
			spread = Vector2.new(60, 60),
			drag = 2,
			accel = Vector3.new(0, 2, 0),
			rotSpeed = { -200, 200 },
			lightEmission = 0.5,
			zOffset = 0.5,
			emitCount = 6,
			emitDelay = 0.08,
			tint = "accent",
		},
	})
	table.insert(out, settle)

	-- Poof: it leaves (the end of the ground sequence).
	local poof, pa = burstPart("Poof", "It leaves: a cartoon poof cloud, accent stars and a ring")
	addAll(pa, {
		{
			name = "Cloud",
			texture = TEX.smoke,
			color = C.White,
			size = { { 0, 0.8 }, { 0.4, 1.7 }, { 1, 2 } },
			transparency = { { 0, 0.1 }, { 0.6, 0.45 }, { 1, 1 } },
			lifetime = { 0.4, 0.65 },
			speed = { 4, 8 },
			drag = 6,
			accel = Vector3.new(0, 3, 0),
			rotSpeed = { -90, 90 },
			lightInfluence = 0.3,
			emitCount = 12,
		},
		{
			name = "Stars",
			texture = TEX.star,
			color = C.White,
			size = { { 0, 0.7 }, { 1, 0 } },
			transparency = { { 0, 0 }, { 1, 0.4 } },
			lifetime = { 0.4, 0.7 },
			speed = { 7, 12 },
			drag = 4.5,
			rotSpeed = { -300, 300 },
			lightEmission = 0.5,
			zOffset = 0.6,
			emitCount = 10,
			tint = "accent",
		},
		ring("Ring", C.White, 5, 0.28, false),
	})
	table.insert(out, poof)

	-- HandSwoosh: the smear on the throwing hand (third person); its attachments move onto the hand.
	local swoosh = carrier("HandSwoosh")
	swoosh:SetAttribute("SD_Theme", "The throwing hand's smear: white into the squishy's accent")
	ribbon(swoosh, {
		name = "Swoosh",
		offset = 0,
		width = 1.1,
		colors = { C.White, C.White },
		transparency = { { 0, 0.2 }, { 0.5, 0.55 }, { 1, 1 } },
		lifetime = 0.16,
		lightEmission = 0.3,
		widthTo = 0.2,
		tint = "accent",
	})
	table.insert(out, swoosh)
	return out
end

-- Public

-- The library as a new, UNPARENTED Folder (marked when `Generated`, SDTools' root marker module, is given).
function ThrowVfxBuilder.build(Generated: any?): Folder
	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root:SetAttribute(
		"SD_Note",
		"Throw VFX for the VFX Studio plugin: drag a template into Workspace, select it and press Emit / Trail to preview."
	)
	local trails = Instance.new("Folder")
	trails.Name = "Trails"
	trails.Parent = root
	for _, spec in TRAILS do
		buildTrail(spec).Parent = trails
	end
	local bursts = Instance.new("Folder")
	bursts.Name = "Bursts"
	bursts.Parent = root
	for _, part in buildBursts() do
		part.Parent = bursts
	end
	if Generated then
		Generated.mark(root, GENERATOR_ID, VERSION)
	end
	return root
end

return ThrowVfxBuilder
