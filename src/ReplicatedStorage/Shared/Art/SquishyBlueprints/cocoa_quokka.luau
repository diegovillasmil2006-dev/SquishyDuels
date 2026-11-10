--!strict
-- Cocoa Quokka (Common, Lava Box, 2026-11-10): Claude Design's CocoaQuokka ("Squishies 50 Lineup", sd/toys2.js:339-359)
-- in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this is the fallback and
-- the size, sections and motion every view reads. A smiling quokka head in a coral mug of hot cocoa with two
-- marshmallows, round ears that wobble (sections EarL/EarR), a muzzle and nose, paws on the rim, eyes, a smile, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the head's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 4.1, 0.2592
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.268, dx 0.06, eyeR 0.02 × 1.22, smile mw 0.024 at 0.054 below with a tongue, blush 0.104).
local EYE_X, EYE_Y, EYE_R = -0.06 * K, (0.268 - Y0) * K, 0.0244 * K
local MOUTH_Y, MOUTH_W = (0.2127 - Y0) * K, 0.067 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Head",
				shape = "E",
				size = size(0.2692, 0.2315, 0.2482),
				pos = at(0, 0.2592, -0.01),
				color = "F4DDBE",
				body = true,
			},
			{
				name = "Mug",
				shape = "E",
				size = size(0.292, 0.2, 0.292),
				pos = at(0, 0.095, 0),
				color = "F0786A",
				body = true,
			},
			{
				name = "Cocoa",
				shape = "E",
				size = size(0.256, 0.014, 0.256),
				pos = at(0, 0.163, 0),
				color = "7A4A32",
				body = true,
			},
			{
				name = "Handle",
				shape = "E",
				size = size(0.06, 0.12, 0.03),
				pos = at(0.165, 0.09, 0),
				color = "F0786A",
				body = true,
			},
			{
				name = "MallowA",
				shape = "E",
				size = size(0.044, 0.036, 0.044),
				pos = at(0.09, 0.17, 0.06),
				color = "FFFFFF",
				body = true,
			},
			{
				name = "MallowB",
				shape = "E",
				size = size(0.044, 0.036, 0.044),
				pos = at(-0.085, 0.172, 0.05),
				color = "FFFFFF",
				body = true,
			},
			-- The muzzle is a ray target for the nose and the mouth.
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.1, 0.0674, 0.0475),
				face = F(0, (0.2274 - Y0) * K, 0.7),
				color = "FFF1E0",
				body = true,
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.03, 0.0216, 0.0138),
				face = F(0, (0.2376 - Y0) * K, 0.6),
				color = Kit.INK,
				look = "detail",
			},
			{
				name = "Tongue",
				shape = "E",
				size = size(0.0266, 0.032, 0.0224),
				face = F(-0.0067 * K, (0.1874 - Y0) * K, 0.6),
				color = Kit.TONGUE,
				look = "detail",
			},
		},
		-- The ears' contact is just under the hinge, inside the head.
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0687, 0.0702, 0.0422),
			pos = at(0.1, 0.3497, -0.0102),
			color = "B07E50",
			section = "EarL",
			contact = v(0.54, -0.52, -0.06),
		}),
		pair({
			name = "InnerEarL",
			shape = "E",
			size = size(0.0423, 0.043, 0.0249),
			attach = { to = "EarL", offset = size(0, 0.0003, -0.011) },
			color = "F2B8A8",
			section = "EarL",
		}),
		pair({
			name = "PawL",
			shape = "E",
			size = size(0.052, 0.036, 0.0418),
			pos = at(0.06, 0.1691, 0.1008), -- resting on the mug rim, a little into it
			color = "E9C79E",
			contact = v(0.5, -0.7, 0.5),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.104 * K, (0.232 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.pairSection("EarL", { pivot = at(0.0826, 0.3364, -0.0097), axis = "X", amp = 0.9, sign = -1, flap = { deg = 15 } }),
	-- The design's CATALOG2 squeeze (depth 0.66, widen 0.6, kRel 40, cRel 8.5, pitch 1.1) and flight (upright).
	motion = {
		squeeze = { depth = 0.66, widen = 0.6, kRel = 40, cRel = 8.5, pitch = 1.1 },
		feel = "foam",
		flight = { style = "upright" },
	},
}

return blueprint
