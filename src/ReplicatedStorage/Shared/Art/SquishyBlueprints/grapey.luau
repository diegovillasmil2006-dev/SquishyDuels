--!strict
-- Grapey (Uncommon, Series 01, 2026-11-10): Claude Design's Grapey ("Squishies 50 Lineup", sd/toys2.js) in E parts. Its
-- real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, the grape bumps in the body); this is the
-- fallback and the size, sections and motion every view reads. A jelly grape bunch, a stem and tendril, a leaf that
-- springs (section Leaf), big eyes, a smile, cheeks.

local Kit = require(script.Parent.Kit)

local v, concat = Kit.v, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's 1.5-1.7 like its
-- siblings), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.49, 0.2015
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y -0.012, dx 0.072, eyeR 0.023 × 1.22 big eyes, smile mw 0.02 at 0.044 below, blush 0.122).
local EYE_X, EYE_Y, EYE_R = -0.072 * K, (0.1668 - Y0) * K, 0.0281 * K
local MOUTH_Y, MOUTH_W = (0.1225 - Y0) * K, 0.0581 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Bunch",
				shape = "E",
				size = size(0.4017, 0.4031, 0.3871),
				pos = at(0.0088, 0.2015, -0.0022),
				color = "B27AEB",
				body = true,
			},
			{
				name = "Stem",
				shape = "E",
				size = size(0.0338, 0.0693, 0.0289),
				pos = at(0.0074, 0.4234, -0.0135),
				color = "8A5A34",
				contact = v(0, -0.8, 0),
			},
			-- The tendril and leaf sit a little lower than the design's (their roots touch the bunch in this look).
			{
				name = "Tendril",
				shape = "E",
				size = size(0.048, 0.0462, 0.0136),
				pos = at(-0.0392, 0.41, -0.012),
				color = "7FD27A",
				contact = v(0, -1, 0),
			},
			{
				name = "Leaf",
				shape = "E",
				-- Thicker than the design's and reaching into the bunch: it holds its hinge, and its contact is just under
				-- the hinge, so the spring never pulls it off.
				size = size(0.0942, 0.06, 0.0956),
				pos = at(0.0375, 0.395, -0.0352),
				color = "6CC56A",
				section = "Leaf",
				contact = v(0.63, -0.83, -0.49),
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.122 * K, (0.1368 - Y0) * K, 0.0249 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = {
		-- The design's hinge (0.008, 0.414, -0.012) is just above this look's bunch: the pivot sits 0.019 lower, inside it.
		Leaf = { pivot = at(0.008, 0.395, -0.012), axis = "Z", amp = 1.1, sign = -1, flap = { deg = 15 } },
	},
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.68, kRel 48, cRel 6.8, pitch 1.2) and flight (tumble).
	motion = {
		squeeze = { depth = 0.62, widen = 0.68, kRel = 48, cRel = 6.8, pitch = 1.2 },
		feel = "jelly",
		flight = { style = "tumble" },
	},
}

return blueprint
