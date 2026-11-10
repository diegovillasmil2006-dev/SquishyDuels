--!strict
-- Berry Jelly (Common, Series 01, 2026-11-10): Claude Design's BerryJelly ("Squishies 50 Lineup", sd/toys2.js) in E parts.
-- Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this is the fallback and the size,
-- sections and motion every view reads. A jelly strawberry body, a 5-leaf calyx + stem that bounce together (section
-- Calyx), big eyes, an open mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, concat = Kit.v, Kit.F, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's 1.5-1.7 like its
-- siblings), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 4.1, 0.1729
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0, dx 0.07, eyeR 0.022 × 1.22, open mouth mw 0.02 at 0.042 below, blush 0.118 / 0.03).
local EYE_X, EYE_Y, EYE_R = -0.07 * K, (0.1738 - Y0) * K, 0.0268 * K
local CALYX = at(0, 0.3418, 0)

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Berry",
				shape = "E",
				size = size(0.3435, 0.3458, 0.3256),
				pos = at(0, 0.1729, 0),
				color = "FF8FB1",
				body = true,
			},
			{
				name = "Calyx",
				shape = "E",
				size = size(0.1669, 0.0332, 0.1595),
				pos = at(0.0004, 0.3418, -0.008),
				color = "5CC46A",
				section = "Calyx",
				contact = v(0, -0.8, 0),
			},
			{
				name = "Stem",
				shape = "E",
				size = size(0.0321, 0.0488, 0.026),
				pos = at(0.0062, 0.3641, -0.0043),
				color = "4FA650",
				section = "Calyx",
				contact = v(0, -0.8, 0),
				contactWith = "Calyx",
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		{
			{
				name = "Mouth",
				shape = "E",
				size = size(0.0333, 0.0239, 0.0162),
				face = F(0, (0.1327 - Y0) * K, 0.6),
				color = Kit.MOUTH_OPEN,
				look = "mouthOpen",
			},
			{
				name = "Tongue",
				shape = "E",
				size = size(0.0213, 0.0124, 0.0101),
				attach = { to = "Mouth", offset = size(0, -0.0057, -0.003) },
				color = Kit.TONGUE,
				look = "mouthOpen",
			},
		},
		Kit.blush2(-0.118 * K, (0.1438 - Y0) * K, 0.0174 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = {
		Calyx = { pivot = CALYX, axis = "X", amp = 0.8, sign = -1, flap = { deg = 15 } },
	},
	-- The design's CATALOG2 squeeze (depth 0.6, widen 0.7, kRel 50, cRel 6.5, pitch 1.25) and flight (tumble).
	motion = {
		squeeze = { depth = 0.6, widen = 0.7, kRel = 50, cRel = 6.5, pitch = 1.25 },
		feel = "jelly",
		flight = { style = "tumble" },
	},
}

return blueprint
