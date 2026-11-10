--!strict
-- Ice Pop Beaver (Uncommon, Frosty Box, 2026-11-10): Claude Design's IcePopBeaver ("Squishies 50 Lineup",
-- sd/toys2.js:222-240) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this
-- is the fallback and the size, sections and motion every view reads. A cream ice-pop body with its chocolate-dipped top,
-- small round ears (sections EarL/EarR), the pop stick as its paddling tail (section Tail), a nose, eyes, a smile,
-- cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the pop's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 3.86, 0.1989
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y -0.004, dx 0.062, eyeR 0.021 × 1.22, smile mw 0.015 at 0.046 below, blush 0.1).
local EYE_X, EYE_Y, EYE_R = -0.062 * K, (0.1939 - Y0) * K, 0.0256 * K
local MOUTH_Y, MOUTH_W = (0.1446 - Y0) * K, 0.047 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Pop",
				shape = "E",
				size = size(0.2999, 0.3979, 0.17),
				pos = at(0, 0.1989, 0),
				color = "F6CFA0",
				body = true,
			},
			-- The chocolate dip over the top (the design colours it by height; here a brown cap a little wider).
			{
				name = "Dip",
				shape = "E",
				size = size(0.304, 0.17, 0.174),
				pos = at(0, 0.322, 0),
				color = "A0623A",
				body = true,
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.038, 0.026, 0.0173),
				face = F(0, (0.1679 - Y0) * K, 0.6),
				color = Kit.INK,
				look = "detail",
			},
			-- The stick reaches into the pop from behind: its contact is the hinge, inside the pop.
			{
				name = "Tail",
				shape = "E",
				size = size(0.072, 0.07, 0.17),
				pos = at(0, 0.1, -0.12),
				color = "EBCB92",
				section = "Tail",
				contact = v(0, 0, -0.765),
			},
		},
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.061, 0.063, 0.0381),
			pos = at(0.1129, 0.3714, 0),
			color = "8E5532",
			section = "EarL",
			contact = v(0.51, -0.29, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.1 * K, (0.1619 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.0974, 0.3623, 0), axis = "X", amp = 0.8, sign = -1, flap = { deg = 15 } }),
		{ Tail = { pivot = at(0, 0.1, -0.055), axis = "X", amp = 1.0, sign = -1, flap = { deg = 12 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.66, widen 0.6, kRel 42, cRel 9, pitch 1.0) and flight (frisbee).
	motion = {
		squeeze = { depth = 0.66, widen = 0.6, kRel = 42, cRel = 9, pitch = 1.0 },
		feel = "foam",
		flight = { style = "frisbee" },
	},
}

return blueprint
