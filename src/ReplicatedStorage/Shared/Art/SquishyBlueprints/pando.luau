--!strict
-- Pando (Rare, Series 01, 2026-11-10): Claude Design's Pando ("Squishies 50 Lineup", sd/toys2.js) in E parts. Its real
-- look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this is the fallback and the size, sections
-- and motion every view reads. A slow-rise foam panda head, cocoa eye patches, a muzzle and nose, ears that wiggle
-- (sections EarL/EarR), a bamboo sprig that bobs (section Bamboo), big eyes, a cat mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's 1.5-1.7 like its
-- siblings), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.81, 0.1778
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

local COCOA = "6E5260"
-- Face (design face(): y 0, dx 0.08, eyeR 0.021 × 1.22, cat mouth mw 0.016 at 0.058 below, blush 0.135 / 0.04).
local EYE_X, EYE_Y, EYE_R = -0.08 * K, (0.1707 - Y0) * K, 0.0256 * K
local MOUTH_Y, MOUTH_W = (0.1116 - Y0) * K, 0.05 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Head",
				shape = "E",
				size = size(0.4, 0.3557, 0.38),
				pos = at(0, 0.1778, 0),
				color = "FFEBA6",
				body = true,
			},
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.1099, 0.0704, 0.0455),
				pos = at(-0.0003, 0.1277, 0.1754),
				color = "FFF8E6",
				contact = v(0, 0, 0.8),
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.032, 0.0219, 0.0171),
				pos = at(0, 0.1405, 0.1959),
				color = COCOA,
				look = "detail",
				contact = v(0, 0, 0.8),
				contactWith = "Muzzle",
			},
			-- The sprig as one E from its hinge to its leaves (the leaves hold on at their middle, its far end).
			{
				name = "Bamboo",
				shape = "E",
				size = size(0.1, 0.11, 0.1),
				pos = at(-0.0825, 0.3518, -0.1016),
				color = "8FD07A",
				section = "Bamboo",
				contact = v(-0.4, -0.8, -0.4), -- its low end toward the head's middle
			},
			{
				name = "BambooLeaves",
				shape = "E",
				size = size(0.0831, 0.0293, 0.0566),
				pos = at(-0.1075, 0.3799, -0.1271),
				color = "5DB861",
				section = "Bamboo",
				contact = v(-0.6, -1, -0.9), -- its low corner toward the stalk's middle
				contactWith = "Bamboo",
			},
		},
		pair({
			name = "PatchL",
			shape = "E",
			size = size(0.08, 0.0941, 0.0373),
			pos = at(0.0785, 0.1726, 0.1723),
			color = COCOA,
			look = "detail",
			contact = v(0, 0, 0.8),
		}),
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0828, 0.0847, 0.0509),
			pos = at(0.1399, 0.319, -0.0102),
			color = COCOA,
			section = "EarL",
			contact = v(0, -0.8, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.135 * K, (0.1307 - Y0) * K, 0.0192 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.1201, 0.3022, -0.0096), axis = "X", amp = 0.9, sign = -1, flap = { deg = 15 } }),
		{ Bamboo = { pivot = at(-0.0575, 0.3237, -0.0761), axis = "Z", amp = 1.0, sign = -1, flap = { deg = 10 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.55, widen 0.8, kRel 14, cRel 7.5, pitch 0.9) and flight (wheel); kRel 14
	-- is under the game's slowest release spring (Config MOTION_RANGES kRel 20), so it uses 20: still the slowest rise.
	motion = {
		squeeze = { depth = 0.55, widen = 0.8, kRel = 20, cRel = 7.5, pitch = 0.9 },
		feel = "foam",
		flight = { style = "wheel" },
	},
}

return blueprint
