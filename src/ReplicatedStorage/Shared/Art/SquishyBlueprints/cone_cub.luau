--!strict
-- Cone Cub (Common, Frosty Box, 2026-11-10): Claude Design's ConeCub ("Squishies 50 Lineup", sd/toys2.js:179-196) in E
-- parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this is the fallback and the
-- size, sections and motion every view reads. A bear-face ice-cream scoop on a waffle cone with its rim, round ears that
-- wobble (sections EarL/EarR), a muzzle and nose, two paws on the rim, eyes, a cat mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the scoop's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 3.57, 0.2805
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.3, dx 0.066, eyeR 0.021 × 1.22, cat mouth mw 0.015 at 0.054 below, blush 0.115).
local EYE_X, EYE_Y, EYE_R = -0.066 * K, (0.3 - Y0) * K, 0.0256 * K
local MOUTH_Y, MOUTH_W = (0.2444 - Y0) * K, 0.05 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Scoop",
				shape = "E",
				size = size(0.31, 0.269, 0.3),
				pos = at(0, 0.2805, 0),
				color = "F7D2A2",
				body = true,
			},
			-- The waffle cone as a narrow E under the rim (the slot's lathe cone tapers to its tip).
			{
				name = "Cone",
				shape = "E",
				size = size(0.2, 0.22, 0.2),
				pos = at(0, 0.11, 0),
				color = "E9B46C",
				body = true,
			},
			{
				name = "Rim",
				shape = "E",
				size = size(0.28, 0.0266, 0.28),
				pos = at(0, 0.19, 0),
				color = "D49650",
				body = true,
			},
			-- The muzzle is a ray target for the nose and the mouth.
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.104, 0.0715, 0.0437),
				face = F(0, (0.2591 - Y0) * K, 0.7),
				color = "FFF0D8",
				body = true,
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.0304, 0.0219, 0.0177),
				face = F(0, (0.2678 - Y0) * K, 0.6),
				color = Kit.INK,
				look = "detail",
			},
		},
		-- The ears' contact is just under the hinge, inside the scoop.
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0798, 0.081, 0.0463),
			pos = at(0.1096, 0.3892, -0.0104),
			color = "C07A48",
			section = "EarL",
			contact = v(0.54, -0.52, -0.06),
		}),
		pair({
			name = "InnerEarL",
			shape = "E",
			size = size(0.0497, 0.0503, 0.027),
			attach = { to = "EarL", offset = size(0, 0.0007, -0.013) },
			color = "F6C49A",
			section = "EarL",
		}),
		-- The paws sit a little further in than the design's, so their backs touch the scoop in this E-part look.
		pair({
			name = "PawL",
			shape = "E",
			size = size(0.06, 0.04, 0.0457),
			pos = at(0.058, 0.206, 0.115),
			color = "F9DDB8",
			contact = v(0, 0.4, 1),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.115 * K, (0.264 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.pairSection("EarL", { pivot = at(0.088, 0.368, -0.009), axis = "X", amp = 0.9, sign = -1, flap = { deg = 15 } }),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.68, kRel 36, cRel 8.5, pitch 1.1) and flight (spiral).
	motion = {
		squeeze = { depth = 0.62, widen = 0.68, kRel = 36, cRel = 8.5, pitch = 1.1 },
		feel = "foam",
		flight = { style = "spiral" },
	},
}

return blueprint
