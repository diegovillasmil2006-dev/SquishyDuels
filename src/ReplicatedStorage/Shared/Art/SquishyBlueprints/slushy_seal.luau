--!strict
-- Slushy Seal (Common, Frosty Box, 2026-11-10): Claude Design's SlushySeal ("Squishies 50 Lineup", sd/toys2.js:198-220)
-- in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this is the fallback and
-- the size, sections and motion every view reads. A round white seal sitting in blue slush in a cup with a blue band,
-- flippers that flap (sections FlipperL/FlipperR), a tail that flicks (section Tail), a muzzle and nose, big eyes, a
-- cat mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the seal's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 3.86, 0.2658
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.262, dx 0.064, eyeR 0.023 × 1.22 big eyes, cat mouth mw 0.014 at 0.056 below, blush 0.11).
local EYE_X, EYE_Y, EYE_R = -0.064 * K, (0.262 - Y0) * K, 0.0281 * K
local MOUTH_Y, MOUTH_W = (0.2054 - Y0) * K, 0.05 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Seal",
				shape = "E",
				size = size(0.2992, 0.2684, 0.2797),
				pos = at(0, 0.2658, 0),
				color = "F4F9FF",
				body = true,
			},
			{
				name = "Slush",
				shape = "E",
				size = size(0.376, 0.1252, 0.3767),
				pos = at(0, 0.1376, 0),
				color = "8ED3FA",
				body = true,
			},
			{
				name = "Cup",
				shape = "E",
				size = size(0.352, 0.132, 0.352),
				pos = at(0, 0.066, 0),
				color = "F2F9FF",
				body = true,
			},
			-- The cup's band, a little wider than this look's round cup so it shows.
			{
				name = "Band",
				shape = "E",
				size = size(0.36, 0.024, 0.36),
				pos = at(0, 0.06, 0),
				color = "7CC8F2",
				body = true,
			},
			-- The muzzle is a ray target for the nose and the mouth.
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.0999, 0.0647, 0.0461),
				face = F(0, (0.224 - Y0) * K, 0.7),
				color = "FFFFFF",
				body = true,
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.03, 0.0198, 0.0139),
				face = F(0, (0.2317 - Y0) * K, 0.6),
				color = Kit.INK,
				look = "detail",
			},
			-- The tail reaches into the seal from behind: its contact is the hinge, inside the seal.
			{
				name = "Tail",
				shape = "E",
				size = size(0.11, 0.07, 0.08),
				pos = at(0, 0.205, -0.135),
				color = "B9D0EA",
				section = "Tail",
				contact = v(0, 0, -0.875),
			},
		},
		-- Each flipper reaches into the seal's side: its contact is the hinge, inside the seal.
		pair({
			name = "FlipperL",
			shape = "E",
			size = size(0.08, 0.13, 0.04),
			pos = at(0.14, 0.18, 0.03),
			color = "B9D0EA",
			section = "FlipperL",
			contact = v(0.625, 0.615, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.11 * K, (0.232 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("FlipperL", { pivot = at(0.115, 0.22, 0.03), axis = "Z", amp = 1.4, sign = -1, flap = { deg = 20 } }),
		{ Tail = { pivot = at(0, 0.205, -0.1), axis = "X", amp = 1.2, sign = -1, flap = { deg = 12 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.64, widen 0.66, kRel 46, cRel 8, pitch 1.2) and flight (face).
	motion = {
		squeeze = { depth = 0.64, widen = 0.66, kRel = 46, cRel = 8, pitch = 1.2 },
		feel = "mochi",
		flight = { style = "face" },
	},
}

return blueprint
