--!strict
-- Pizza Pangolin (Rare, Lava Box, 2026-11-10): Claude Design's PizzaPangolin ("Squishies 50 Lineup",
-- sd/toys2.js:428-457) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, with
-- its 24 pizza-slice scales); this is the fallback and the size, sections and motion every view reads. A round pangolin
-- whose back is a shell of crust and cheese, a crust tail that curls (section Tail), small ears, paws, eyes, a smile,
-- cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 2.55, 0.1245
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.006, dx 0.062, eyeR 0.02 × 1.22, smile mw 0.016 at 0.064 below, blush 0.1 / 0.034).
local EYE_X, EYE_Y, EYE_R = -0.062 * K, (0.125 - Y0) * K, 0.0244 * K
local MOUTH_Y, MOUTH_W = (0.0609 - Y0) * K, 0.049 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.32, 0.249, 0.4564),
				pos = at(0, 0.1245, 0.0082),
				color = "F6D2A6",
				body = true,
			},
			-- The slice shell: the crust layer, then the cheese on it.
			{
				name = "Crust",
				shape = "E",
				size = size(0.36, 0.12, 0.38),
				pos = at(0, 0.21, -0.046),
				color = "E39B52",
				body = true,
			},
			{
				name = "Cheese",
				shape = "E",
				size = size(0.33, 0.1, 0.35),
				pos = at(0, 0.225, -0.05),
				color = "FFC94A",
				body = true,
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.0275, 0.0238, 0.0186),
				face = F(0, (0.0855 - Y0) * K, 0.6),
				color = Kit.INK,
				look = "detail",
			},
			{
				name = "Paws",
				shape = "E",
				size = size(0.26, 0.036, 0.29),
				pos = at(0, 0.021, 0.01),
				color = "F2C792",
				contact = v(0, 0.9, 0),
			},
			-- The tail curls out behind: its contact is the hinge, inside the body.
			{
				name = "Tail",
				shape = "E",
				size = size(0.169, 0.1262, 0.2108),
				pos = at(0.0255, 0.0831, -0.2811),
				color = "E39B52",
				section = "Tail",
				contact = v(0.3, 0.09, -0.86),
			},
		},
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0284, 0.0347, 0.0388),
			pos = at(0.1271, 0.1476, 0.1175),
			color = "E3A86E",
			contact = v(0.8, 0, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.1 * K, (0.091 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = {
		Tail = { pivot = at(0, 0.089, -0.19), axis = "Y", amp = 1.0, sign = 1, flap = { deg = 15 } },
	},
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.66, kRel 38, cRel 8.5, pitch 1) and flight (wheel).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 38, cRel = 8.5, pitch = 1 },
		feel = "foam",
		flight = { style = "wheel" },
	},
}

return blueprint
