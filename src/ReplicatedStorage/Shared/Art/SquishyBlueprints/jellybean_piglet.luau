--!strict
-- Jellybean Piglet (Common, Prism Box, 2026-11-10): Claude Design's JellybeanPiglet ("Squishies 50 Lineup",
-- sd/toys2.js:520-539) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this
-- is the fallback and the size, sections and motion every view reads. A pink jellybean body, a snout, ears that flip
-- (sections EarL/EarR), a curly tail that boings (section Tail), hooves, eyes, a smile, cheeks.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 4.0, 0.1069
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.014, dx 0.075, eyeR 0.021 × 1.22, smile mw 0.016 at 0.07 below, blush 0.125).
local EYE_X, EYE_Y, EYE_R = -0.075 * K, (0.1228 - Y0) * K, 0.0256 * K
local MOUTH_Y, MOUTH_W = (0.052 - Y0) * K, 0.0493 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3973, 0.2137, 0.2785),
				pos = at(0, 0.1069, 0),
				color = "FFB3CB",
				body = true,
			},
			-- The snout's back is inside the body.
			{
				name = "Snout",
				shape = "E",
				size = size(0.084, 0.0591, 0.0416),
				pos = at(0, 0.0846, 0.1276),
				color = "FF7FA6",
				contact = v(0, 0.25, 0.75),
			},
			{
				name = "Hooves",
				shape = "E",
				size = size(0.2695, 0.032, 0.1733),
				pos = at(0, 0.0208, 0),
				color = "FF9FBE",
				contact = v(0, 0.67, 0),
			},
			-- The tail reaches into the body from behind: its contact is the hinge, inside the body.
			{
				name = "Tail",
				shape = "E",
				size = size(0.0401, 0.0478, 0.05),
				pos = at(0, 0.1279, -0.1343),
				color = "FF8FB4",
				section = "Tail",
				contact = v(0, -0.08, -0.83),
			},
		},
		-- The ears' contact is their hinge, just inside the body's top.
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0897, 0.0697, 0.0571),
			pos = at(0.1028, 0.209, 0.0077), -- 0.018 into the body
			color = "FF8FB4",
			section = "EarL",
			contact = v(0.33, -0.75, 0.17),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.125 * K, (0.0928 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.0879, 0.1829, 0.003), axis = "X", amp = 1.1, sign = -1, flap = { deg = 15 } }),
		{ Tail = { pivot = at(0, 0.1259, -0.1135), axis = "Y", amp = 1.6, sign = 1, flap = { deg = 12 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.66, kRel 46, cRel 7.5, pitch 1.25) and flight (tumble).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 46, cRel = 7.5, pitch = 1.25 },
		feel = "jelly",
		flight = { style = "tumble" },
	},
}

return blueprint
