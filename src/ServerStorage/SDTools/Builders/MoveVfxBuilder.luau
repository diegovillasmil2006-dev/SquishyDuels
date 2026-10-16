--!strict
-- MoveVfxBuilder: authors the movement effects library ReplicatedStorage.SD_MoveVfx for the VFX Studio plugin
-- (2026-10-15, VillasmilGaming's dash + double jump overhaul). Server only, Edit mode only; runtime code never requires
-- it. Like ThrowVfxBuilder it is not one of Main's targets: VFX Studio is the editor of record for these effects. This
-- builder makes the first version (and a reset): build() returns a new, marked, UNPARENTED Folder; the caller swaps it
-- in. A rebuild drops every tweak made in VFX Studio since, so only rebuild to reset.
--
-- Layout (every template is an invisible anchored Part, so VFX Studio can preview it once it is dragged into Workspace;
-- the runtime, Client/Anim/MoveVfx, clones it as the effect's carrier). Carrier frames: LookVector = the move's
-- direction (the dash) or the character's facing (the double jump), UpVector = world up.
--   Dash/Start        burst at the push-off foot: a flat team ring, a white ring, dust kicked back, pebbles, streaks,
--                     team sparkles; at the waist a flash and radial zip lines.
--   Dash/Body         hold on the HumanoidRootPart while the dash runs: a tall team ribbon, a white core, two thin wind
--                     ribbons; "while" team motes, speed specks and wisps.
--   Dash/Skid         hold on the floor under the dasher: a flat skid mark ribbon, "while" dust and kicked-up bits.
--   Dash/Plant        burst at the plant foot: dust sprayed forward, a ring, sparkles, bits.
--   Dash/SpeedLines   hold in front of the dasher's own camera (first person): eight "while" streak emitters around the
--                     view, flying past the screen edges.
--   DoubleJump/Burst  burst at the feet: two flat air rings (white, team), cloud puffs, team stars, down streaks; a waist
--                     flash.
--   DoubleJump/Body   hold on the HumanoidRootPart while it rises: "while" team sparkles and white twinkles.
--   DoubleJump/FootTrail  a Trail and its two attachments, moved onto each foot by the runtime for the flip.
--   DoubleJump/Land   burst on the floor where a double jump lands: a dust skirt, a ring, a few sparkles.
-- VFX Studio's emit contract on every ParticleEmitter (as ThrowVfxBuilder): EmitDelay (s, default 0), then
-- EmitDuration > 0 = Enabled for that long, else Emit(EmitCount) (default 1). Our own attributes:
--   SD_Role   "while": on while its hold runs (Handle:setOn) | nil: a burst emitter (plays once when its effect starts)
--   SD_Tint   "team": the runtime recolours it in the mover's team tint (side A Strawberry, side B Mint)
--   SD_TintFirst (trails): true = tint -> white with age, else white -> tint
-- Textures: engine built-ins only (ThrowVfxBuilder.TEXTURES, verified in Studio 2026-10-15), no uploads.

local ThrowVfxBuilder = require(script.Parent.ThrowVfxBuilder)

type EmitterSpec = ThrowVfxBuilder.EmitterSpec

-- Constants

local GENERATOR_ID = "move_vfx"
local VERSION = 3 -- 2: the first playtest's polish (warmer, stronger dust; a team ring on the landing); 3: bolder speed lines
local ROOT_NAME = "SD_MoveVfx"
local TEX = ThrowVfxBuilder.TEXTURES
local WAIST = 2.6 -- the HumanoidRootPart's centre over the floor is 3; the flash sits a little lower
local SPEED_LINES = 8 -- streak emitters around the own view
local SPEED_RADIUS = 3.4 -- studs from the view axis
local SPEED_AHEAD = 9 -- studs in front of the camera

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- VFX asset colours (VFX Studio is their editor); the team tint comes from Art/Palette at runtime.
local C = {
	White = hex("#FFFFFF"),
	Cream = hex("#FFF4E6"),
	Dust = hex("#E9D3B8"), -- warm enough to read on the pastel arena floors (the cream of v1 vanished on them)
	DustDeep = hex("#D2B48F"),
	Cloud = hex("#F7F4FF"),
	LampGlow = hex("#FFF6DC"),
}

-- Module table

local MoveVfxBuilder = {}
MoveVfxBuilder.GENERATOR_ID = GENERATOR_ID
MoveVfxBuilder.VERSION = VERSION
MoveVfxBuilder.ROOT_NAME = ROOT_NAME
MoveVfxBuilder.SPEED_LINES = SPEED_LINES

-- Private

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

local function attachment(parent: Instance, name: string, position: Vector3, orientation: Vector3?): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	if orientation then
		a.Orientation = orientation
	end
	a.Parent = parent
	return a
end

local function addAll(a: Attachment, specs: { EmitterSpec })
	for _, spec in specs do
		ThrowVfxBuilder.emitter(spec).Parent = a
	end
end

-- A Trail between two attachments `width` apart: vertical (a ribbon you see from the side) or flat (along the X axis,
-- lying on the floor).
local function ribbon(
	part: Instance,
	name: string,
	centre: Vector3,
	width: number,
	flat: boolean,
	props: {
		colors: { Color3 }?,
		transparency: { { number } },
		lifetime: number,
		lightEmission: number?,
		widthTo: number?,
		faceCamera: boolean?,
		tint: boolean?,
		tintFirst: boolean?,
	}
): Trail
	local half = if flat then Vector3.new(width / 2, 0, 0) else Vector3.new(0, width / 2, 0)
	local a0 = attachment(part, name .. "A", centre + half)
	local a1 = attachment(part, name .. "B", centre - half)
	local t = Instance.new("Trail")
	t.Name = name
	t.Attachment0 = a0
	t.Attachment1 = a1
	local colors = props.colors or { C.White, C.White }
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
	end
	t.Color = ColorSequence.new(keys)
	local tkeys = {}
	for _, row in props.transparency do
		table.insert(tkeys, NumberSequenceKeypoint.new(row[1], row[2]))
	end
	t.Transparency = NumberSequence.new(tkeys)
	t.Lifetime = props.lifetime
	t.MinLength = 0.05
	t.MaxLength = 0
	t.WidthScale = NumberSequence.new(1, props.widthTo or 0.1)
	t.FaceCamera = props.faceCamera == true
	t.LightEmission = props.lightEmission or 0
	t.LightInfluence = 0
	t.Brightness = 1
	if props.tint then
		t:SetAttribute("SD_Tint", "team")
		t:SetAttribute("SD_TintFirst", props.tintFirst == true)
	end
	t.Enabled = true
	t.Parent = part
	return t
end

-- Shared pieces --------------------------------------------------------------------------------------------------------

local function flatRing(name: string, color: Color3, from: number, to: number, lifetime: number, extra: {
	delay: number?,
	tint: boolean?,
	alpha: number?,
	light: number?,
}?): EmitterSpec
	local e = extra or {}
	return {
		name = name,
		texture = TEX.shock,
		color = color,
		size = { { 0, from }, { 1, to } },
		transparency = { { 0, e.alpha or 0.1 }, { 0.55, 0.45 }, { 1, 1 } },
		lifetime = { lifetime },
		speed = { 0.01 },
		spread = Vector2.zero,
		lightEmission = e.light or 0.45,
		zOffset = 0.2,
		orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		direction = Enum.NormalId.Top,
		emitCount = 1,
		emitDelay = e.delay,
		tint = if e.tint then "team" else nil,
	}
end

local function flash(name: string, size: number, lifetime: number, tint: boolean): EmitterSpec
	return {
		name = name,
		texture = TEX.glow,
		color = C.White,
		size = { { 0, size * 0.3 }, { 0.25, size }, { 1, size * 0.6 } },
		transparency = { { 0, 0.15 }, { 0.4, 0.45 }, { 1, 1 } },
		lifetime = { lifetime },
		speed = { 0 },
		spread = Vector2.zero,
		rotation = { 0, 360 },
		lightEmission = 1, -- glow.png is additive-only (a dark rim otherwise)
		zOffset = 1,
		emitCount = 1,
		tint = if tint then "team" else nil,
	}
end

local function sparkles(name: string, count: number, speed: { number }, size: number, spread: Vector2?): EmitterSpec
	return {
		name = name,
		texture = TEX.star,
		color = C.White,
		size = { { 0, 0 }, { 0.2, size }, { 1, 0 } },
		transparency = { { 0, 0 }, { 0.75, 0.15 }, { 1, 1 } },
		lifetime = { 0.35, 0.6 },
		speed = speed,
		spread = spread,
		drag = 5,
		rotation = { 0, 360 },
		rotSpeed = { -320, 320 },
		lightEmission = 0.6,
		zOffset = 0.6,
		emitCount = count,
		tint = "team",
	}
end

local function streaks(
	name: string,
	count: number,
	direction: Enum.NormalId,
	spread: Vector2,
	speed: { number },
	size: number?
): EmitterSpec
	return {
		name = name,
		texture = TEX.dot,
		color = C.White,
		size = { { 0, size or 0.2 }, { 1, 0 } },
		transparency = { { 0, 0.05 }, { 1, 1 } },
		lifetime = { 0.12, 0.2 },
		speed = speed,
		spread = spread,
		drag = 5,
		squash = { { 0, -3 }, { 1, -1.6 } },
		orientation = Enum.ParticleOrientation.VelocityParallel,
		direction = direction,
		lightEmission = 0.5,
		zOffset = 0.4,
		emitCount = count,
	}
end

-- Dash ---------------------------------------------------------------------------------------------------------------

local function dashStart(): Part
	local part = carrier("Start", "The push-off: rings on the floor, dust kicked back, streaks, sparkles, a waist flash")
	local feet = attachment(part, "Burst", Vector3.new(0, 0.1, 0))
	addAll(feet, {
		flatRing("Ring", C.White, 0.8, 9, 0.32, { tint = true }),
		flatRing("RingLate", C.White, 0.5, 5.5, 0.28, { delay = 0.05, alpha = 0.2 }),
		{
			name = "KickDust",
			texture = TEX.smoke,
			color = { C.Dust, C.DustDeep },
			size = { { 0, 0.9 }, { 1, 2.6 } },
			transparency = { { 0, 0.12 }, { 0.5, 0.5 }, { 1, 1 } },
			lifetime = { 0.4, 0.7 },
			speed = { 10, 18 },
			spread = Vector2.new(35, 18),
			drag = 6,
			accel = Vector3.new(0, 3, 0),
			rotSpeed = { -80, 80 },
			lightInfluence = 0.5,
			direction = Enum.NormalId.Back, -- the carrier looks along the dash: Back = behind the dasher
			emitCount = 14,
		},
		{
			name = "Pebbles",
			texture = TEX.dot,
			color = { C.Cream, C.DustDeep },
			size = { { 0, 0.24 }, { 1, 0.12 } },
			transparency = { { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } },
			lifetime = { 0.35, 0.55 },
			speed = { 12, 20 },
			spread = Vector2.new(40, 30),
			accel = Vector3.new(0, -60, 0),
			rotSpeed = { -300, 300 },
			lightInfluence = 0.5,
			zOffset = 0.3,
			direction = Enum.NormalId.Back,
			emitCount = 10,
		},
		streaks("Streaks", 10, Enum.NormalId.Back, Vector2.new(12, 8), { 30, 45 }),
		sparkles("Sparkles", 10, { 6, 14 }, 0.8),
	})
	local waist = attachment(part, "Waist", Vector3.new(0, WAIST, 0))
	addAll(waist, {
		flash("Flash", 4.5, 0.14, true),
		streaks("Zip", 8, Enum.NormalId.Top, Vector2.new(180, 180), { 25, 35 }, 0.16),
	})
	return part
end

local function dashBody(): Part
	local part = carrier("Body", "While it dashes, on the HumanoidRootPart: team ribbon, white core, wind lines, motes")
	ribbon(part, "Main", Vector3.zero, 2.2, false, {
		transparency = { { 0, 0.15 }, { 0.6, 0.5 }, { 1, 1 } },
		lifetime = 0.26,
		lightEmission = 0.35,
		widthTo = 0.2,
		faceCamera = true,
		tint = true,
		tintFirst = true,
	})
	ribbon(part, "Core", Vector3.zero, 0.9, false, {
		colors = { C.White, C.LampGlow },
		transparency = { { 0, 0.15 }, { 0.5, 0.5 }, { 1, 1 } },
		lifetime = 0.16,
		lightEmission = 0.6,
		widthTo = 0.1,
		faceCamera = true,
	})
	ribbon(part, "WindHigh", Vector3.new(0, 1.6, 0), 0.24, false, {
		transparency = { { 0, 0.2 }, { 1, 1 } },
		lifetime = 0.28,
		lightEmission = 0.4,
		widthTo = 0.05,
		faceCamera = true,
	})
	ribbon(part, "WindLow", Vector3.new(0, -1.9, 0), 0.2, false, {
		transparency = { { 0, 0.25 }, { 1, 1 } },
		lifetime = 0.26,
		lightEmission = 0.4,
		widthTo = 0.05,
		faceCamera = true,
		tint = true,
	})
	local emit = attachment(part, "Emit", Vector3.zero)
	addAll(emit, {
		{
			name = "Motes",
			texture = TEX.star,
			color = C.White,
			size = { { 0, 0 }, { 0.2, 0.55 }, { 1, 0 } },
			transparency = { { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } },
			lifetime = { 0.3, 0.55 },
			speed = { 1, 4 },
			rate = 45,
			drag = 3,
			rotSpeed = { -200, 200 },
			lightEmission = 0.6,
			zOffset = 0.5,
			role = "while",
			emitDuration = 0.3,
			tint = "team",
		},
		{
			name = "Specks",
			texture = TEX.dot,
			color = C.White,
			size = { { 0, 0.14 }, { 1, 0 } },
			transparency = { { 0, 0.1 }, { 1, 1 } },
			lifetime = { 0.12, 0.2 },
			speed = { 14, 24 },
			rate = 60,
			spread = Vector2.new(25, 40),
			squash = { { 0, -2.5 }, { 1, -1.2 } },
			orientation = Enum.ParticleOrientation.VelocityParallel,
			direction = Enum.NormalId.Back,
			lightEmission = 0.5,
			zOffset = 0.4,
			role = "while",
			emitDuration = 0.3,
		},
		{
			name = "Wisps",
			texture = TEX.smoke,
			color = C.White,
			size = { { 0, 0.8 }, { 1, 1.8 } },
			transparency = { { 0, 0.6 }, { 1, 1 } },
			lifetime = { 0.25, 0.4 },
			speed = { 1, 3 },
			rate = 30,
			drag = 3,
			rotSpeed = { -60, 60 },
			lightInfluence = 0.3,
			role = "while",
			emitDuration = 0.3,
		},
	})
	return part
end

local function dashSkid(): Part
	local part = carrier("Skid", "While it dashes, on the floor under it: a skid mark, dust and kicked-up bits")
	ribbon(part, "SkidMark", Vector3.new(0, 0.06, 0), 1.3, true, {
		colors = { C.DustDeep, C.Dust },
		transparency = { { 0, 0.45 }, { 0.6, 0.7 }, { 1, 1 } },
		lifetime = 0.45,
		widthTo = 0.3,
	})
	local emit = attachment(part, "Emit", Vector3.new(0, 0.15, 0))
	addAll(emit, {
		{
			name = "SkidDust",
			texture = TEX.smoke,
			color = { C.Dust, C.DustDeep },
			size = { { 0, 0.6 }, { 1, 1.8 } },
			transparency = { { 0, 0.22 }, { 1, 1 } },
			lifetime = { 0.3, 0.55 },
			speed = { 2, 5 },
			rate = 55,
			spread = Vector2.new(50, 20),
			drag = 4,
			accel = Vector3.new(0, 2, 0),
			rotSpeed = { -60, 60 },
			lightInfluence = 0.5,
			direction = Enum.NormalId.Back,
			role = "while",
			emitDuration = 0.3,
		},
		{
			name = "SkidBits",
			texture = TEX.dot,
			color = { C.Cream, C.DustDeep },
			size = { { 0, 0.18 }, { 1, 0.08 } },
			transparency = { { 0, 0 }, { 1, 0.4 } },
			lifetime = { 0.3, 0.5 },
			speed = { 6, 11 },
			rate = 25,
			spread = Vector2.new(35, 35),
			accel = Vector3.new(0, -50, 0),
			lightInfluence = 0.5,
			zOffset = 0.3,
			direction = Enum.NormalId.Back,
			role = "while",
			emitDuration = 0.3,
		},
	})
	return part
end

local function dashPlant(): Part
	local part = carrier("Plant", "The plant: dust sprayed forward, a ring, sparkles and bits")
	local feet = attachment(part, "Burst", Vector3.new(0, 0.1, 0))
	addAll(feet, {
		{
			name = "Dust",
			texture = TEX.smoke,
			color = { C.Dust, C.DustDeep },
			size = { { 0, 0.8 }, { 1, 2.2 } },
			transparency = { { 0, 0.15 }, { 0.5, 0.5 }, { 1, 1 } },
			lifetime = { 0.35, 0.6 },
			speed = { 6, 11 },
			spread = Vector2.new(50, 15),
			drag = 6,
			accel = Vector3.new(0, 2.5, 0),
			rotSpeed = { -60, 60 },
			lightInfluence = 0.5,
			direction = Enum.NormalId.Front,
			emitCount = 10,
		},
		flatRing("Ring", C.White, 0.6, 5, 0.26, { tint = true, alpha = 0.2 }),
		sparkles("Sparkles", 6, { 4, 8 }, 0.6, Vector2.new(70, 70)),
		{
			name = "Bits",
			texture = TEX.dot,
			color = { C.Cream, C.DustDeep },
			size = { { 0, 0.2 }, { 1, 0.1 } },
			transparency = { { 0, 0 }, { 1, 0.3 } },
			lifetime = { 0.3, 0.5 },
			speed = { 7, 12 },
			spread = Vector2.new(40, 30),
			accel = Vector3.new(0, -55, 0),
			lightInfluence = 0.5,
			zOffset = 0.3,
			direction = Enum.NormalId.Front,
			emitCount = 6,
		},
	})
	return part
end

local function dashSpeedLines(): Part
	local part =
		carrier("SpeedLines", "The dasher's own view: streaks around the screen edges, flying past the camera")
	for i = 1, SPEED_LINES do
		local angle = (i - 1) / SPEED_LINES * 2 * math.pi + math.pi / SPEED_LINES
		local a = attachment(
			part,
			"Line" .. i,
			Vector3.new(math.cos(angle) * SPEED_RADIUS, math.sin(angle) * SPEED_RADIUS * 0.75, 0)
		)
		addAll(a, {
			{
				name = "Streak",
				texture = TEX.dot,
				color = C.White,
				size = { { 0, 0.14 }, { 1, 0.08 } },
				transparency = { { 0, 1 }, { 0.2, 0.3 }, { 1, 1 } },
				lifetime = { 0.12, 0.16 },
				speed = { 60, 80 },
				rate = 28,
				spread = Vector2.new(6, 6),
				squash = { { 0, -6 }, { 1, -4 } },
				orientation = Enum.ParticleOrientation.VelocityParallel,
				direction = Enum.NormalId.Back, -- the carrier looks along the view: Back = toward the camera
				lightEmission = 0.5,
				role = "while",
				emitDuration = 0.3,
			},
		})
	end
	part:SetAttribute("SD_Ahead", SPEED_AHEAD)
	return part
end

-- Double jump ----------------------------------------------------------------------------------------------------------

local function jumpBurst(): Part
	local part = carrier("Burst", "The second jump's push on the air: rings, cloud puffs, team stars, down streaks")
	local feet = attachment(part, "Burst", Vector3.zero)
	addAll(feet, {
		flatRing("AirRing", C.White, 1, 10, 0.38),
		flatRing("AirRingTeam", C.White, 0.6, 6, 0.3, { delay = 0.06, tint = true }),
		{
			name = "Clouds",
			texture = TEX.smoke,
			color = { C.White, C.Cloud },
			size = { { 0, 1 }, { 0.4, 2 }, { 1, 2.4 } },
			transparency = { { 0, 0.15 }, { 0.6, 0.5 }, { 1, 1 } },
			lifetime = { 0.45, 0.75 },
			speed = { 6, 12 },
			spread = Vector2.new(75, 75),
			drag = 6,
			accel = Vector3.new(0, 1.5, 0),
			rotSpeed = { -90, 90 },
			lightInfluence = 0.3,
			direction = Enum.NormalId.Bottom,
			emitCount = 12,
		},
		sparkles("Stars", 10, { 8, 14 }, 0.9),
		streaks("DownStreaks", 10, Enum.NormalId.Bottom, Vector2.new(25, 25), { 30, 45 }),
	})
	local waist = attachment(part, "Waist", Vector3.new(0, WAIST, 0))
	addAll(waist, { flash("Flash", 3.5, 0.12, true) })
	return part
end

local function jumpBody(): Part
	local part = carrier("Body", "While the second jump rises, on the HumanoidRootPart: team sparkles and twinkles")
	local emit = attachment(part, "Emit", Vector3.zero)
	addAll(emit, {
		{
			name = "Sparkle",
			texture = TEX.star,
			color = C.White,
			size = { { 0, 0 }, { 0.2, 0.55 }, { 1, 0 } },
			transparency = { { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } },
			lifetime = { 0.35, 0.6 },
			speed = { 1, 3 },
			rate = 40,
			drag = 2,
			rotSpeed = { -200, 200 },
			lightEmission = 0.6,
			zOffset = 0.5,
			role = "while",
			emitDuration = 0.4,
			tint = "team",
		},
		{
			name = "Twinkle",
			texture = TEX.dot,
			color = C.White,
			size = { { 0, 0.14 }, { 1, 0 } },
			transparency = { { 0, 0.1 }, { 1, 1 } },
			lifetime = { 0.3, 0.5 },
			speed = { 0.5, 2 },
			rate = 30,
			drag = 2,
			accel = Vector3.new(0, -4, 0),
			lightEmission = 0.5,
			zOffset = 0.4,
			role = "while",
			emitDuration = 0.4,
		},
	})
	return part
end

local function jumpFootTrail(): Part
	local part = carrier("FootTrail", "The flip's foot arcs: its trail and attachments move onto each foot")
	ribbon(part, "Arc", Vector3.zero, 0.7, false, {
		transparency = { { 0, 0.15 }, { 0.6, 0.55 }, { 1, 1 } },
		lifetime = 0.3,
		lightEmission = 0.4,
		widthTo = 0.05,
		faceCamera = true,
		tint = true,
		tintFirst = true,
	})
	return part
end

local function jumpLand(): Part
	local part = carrier("Land", "Where a double jump lands: a soft dust skirt, a ring and a few sparkles")
	local feet = attachment(part, "Burst", Vector3.new(0, 0.1, 0))
	addAll(feet, {
		{
			name = "Dust",
			texture = TEX.smoke,
			color = { C.Dust, C.DustDeep },
			size = { { 0, 0.9 }, { 1, 2.3 } },
			transparency = { { 0, 0.12 }, { 0.5, 0.5 }, { 1, 1 } },
			lifetime = { 0.4, 0.65 },
			speed = { 8, 12 },
			spread = Vector2.new(85, 85),
			drag = 6,
			accel = Vector3.new(0, 2, 0),
			rotSpeed = { -60, 60 },
			lightInfluence = 0.5,
			emitCount = 14,
		},
		flatRing("Ring", C.White, 0.6, 5.5, 0.26, { alpha = 0.15, tint = true }),
		sparkles("Sparkles", 5, { 3, 6 }, 0.55, Vector2.new(60, 60)),
	})
	return part
end

-- Public

function MoveVfxBuilder.build(Generated: any?): Folder
	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root:SetAttribute(
		"SD_Note",
		"Dash + double jump VFX for the VFX Studio plugin: drag a template into Workspace, select it and press Emit / Trail to preview."
	)
	local dash = Instance.new("Folder")
	dash.Name = "Dash"
	dash.Parent = root
	for _, part in { dashStart(), dashBody(), dashSkid(), dashPlant(), dashSpeedLines() } do
		part.Parent = dash
	end
	local jump = Instance.new("Folder")
	jump.Name = "DoubleJump"
	jump.Parent = root
	for _, part in { jumpBurst(), jumpBody(), jumpFootTrail(), jumpLand() } do
		part.Parent = jump
	end
	if Generated then
		Generated.mark(root, GENERATOR_ID, VERSION)
	end
	return root
end

return MoveVfxBuilder
