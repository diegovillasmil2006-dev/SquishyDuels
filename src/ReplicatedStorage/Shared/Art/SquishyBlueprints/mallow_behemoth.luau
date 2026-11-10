--!strict
-- Mallow Behemoth (Legendary, Lava Box, 2026-11-10): Claude Design's MallowBehemoth ("Squishies 50 Lineup",
-- sd/toys2.js:484-503) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, with
-- the glowing cracks); this is the fallback and the size, sections and motion every view reads. A giant toasted
-- marshmallow with a roasting stick carrying a mini mallow (rigid, the design's still group), stubby arms that flap
-- (sections ArmL/ArmR), feet, big eyes, an open mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.75 studs with its
-- stick: the Legendary is held large like Dragon and Cosmo), turned 180° about Y and re-based on the body's middle
-- (design y = Y0, the slot model's pivot).
local K, Y0 = 2.75, 0.2155
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y -0.01, dx 0.09, eyeR 0.028 × 1.22 big eyes, open mouth mw 0.028 at 0.056 below, blush 0.155).
local EYE_X, EYE_Y, EYE_R = -0.09 * K, (0.2 - Y0) * K, 0.0342 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Mallow",
				shape = "E",
				size = size(0.4871, 0.429, 0.4515),
				pos = at(0, 0.2155, 0.0037),
				color = "FFFBF4",
				body = true,
			},
			-- The toasted top (the design browns the marshmallow by height).
			{
				name = "Toast",
				shape = "E",
				size = size(0.47, 0.12, 0.44),
				pos = at(0, 0.38, 0),
				color = "EDB06A",
				body = true,
			},
			-- The roasting stick stays rigid (the design's still group); its bottom end is inside the body's top. Straight up
			-- from the design's stick foot (toys2.js:491), 0.26 long: a turned stick keeps its turn while a squeeze shears the mini
			-- mallow off its line (the real model's stick is tilted like the design).
			{
				name = "Stick",
				shape = "E",
				size = size(0.04, 0.26, 0.04),
				pos = at(-0.06, 0.5135, -0.05),
				color = "C8955A",
				rigidity = 1,
				contact = v(0, -0.95, 0),
			},
			{
				-- Skewered on the stick near its top (toys2.js:494).
				name = "MiniMallow",
				shape = "E",
				size = size(0.0626, 0.0601, 0.0626),
				attach = { to = "Stick", offset = size(0, 0.09, 0) },
				contact = v(0, 0, 0), -- its middle on the stick's line
				color = "F2C27E",
				rigidity = 1,
			},
			{
				name = "Feet",
				shape = "E",
				size = size(0.2951, 0.056, 0.0951),
				pos = at(0, 0.028, 0.14),
				color = "F2C88E",
				contact = v(0, 0.9, 0.5),
			},
		},
		-- Each arm reaches into the body's side: its contact is the hinge, inside the body.
		pair({
			name = "ArmL",
			shape = "E",
			size = size(0.0894, 0.1046, 0.084),
			pos = at(0.253, 0.1497, 0.04),
			color = "FFF4E6",
			section = "ArmL",
			contact = v(0.63, 0.58, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		{
			{
				name = "Mouth",
				shape = "E",
				size = size(0.0466, 0.0371, 0.0159),
				face = F(0, (0.1442 - Y0) * K, 0.6),
				color = Kit.MOUTH_OPEN,
				look = "mouthOpen",
			},
			{
				name = "Tongue",
				shape = "E",
				size = size(0.0298, 0.0186, 0.0125),
				attach = { to = "Mouth", offset = size(0, -0.008, -0.003) },
				color = Kit.TONGUE,
				look = "mouthOpen",
			},
		},
		Kit.blush2(-0.155 * K, (0.164 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = Kit.pairSection("ArmL", { pivot = at(0.225, 0.18, 0.04), axis = "Z", amp = 1.2, sign = -1, flap = { deg = 15 } }),
	-- The design's CATALOG2 squeeze (depth 0.56, widen 0.82, kRel 24, cRel 7.5, pitch 0.75) and flight (upright).
	motion = {
		squeeze = { depth = 0.56, widen = 0.82, kRel = 24, cRel = 7.5, pitch = 0.75 },
		feel = "mochi",
		flight = { style = "upright" },
	},
}

return blueprint
