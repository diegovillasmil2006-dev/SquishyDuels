--!strict
-- Cream Puff Kitten (Common, Halo Box, 2026-11-10): Claude Design's CreamPuffKitten ("Squishies 50 Lineup",
-- sd/toys2.js:685-698) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes);
-- this is the fallback and the size, sections and motion every view reads. A golden choux puff on a ring of cream, ears
-- that flick (sections EarL/EarR), eyes, a cat mouth, cheeks.
-- Hinges and contacts: the point deepest inside both the part and its holder (halo/gen_bp.mjs, |q| <= 0.84); a part is
-- moved toward its holder only where the design's spot left no room.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 4.25, 0.1343
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.02, dx 0.068, eyeR 0.021 × 1.22, cat mouth mw 0.015 at 0.038 below, blush 0.115).
local EYE_X, EYE_Y, EYE_R = -0.068 * K, (0.1421 - Y0) * K, 0.0256 * K
local MOUTH_Y, MOUTH_W = (0.1012 - Y0) * K, 0.047 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3412, 0.2686, 0.3206),
				pos = at(0, 0.1343, 0),
				color = "F0C98A",
				body = true,
			},
			{
				-- the cream squeezing out round the middle
				name = "Cream",
				shape = "E",
				size = size(0.376, 0.032, 0.376),
				pos = at(0, 0.0561, 0),
				color = "FFFFFF",
				contact = v(0, 0.5, 0),
			},
		},
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.09, 0.0888, 0.0595),
			pos = at(0.1062, 0.238, 0.0098),
			color = "E9B66E",
			section = "EarL",
			contact = v(0.5, -0.58, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.115 * K, (0.1161 - Y0) * K, 0.021 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.0837, 0.2121, 0.0098), axis = "X", amp = 0.9, sign = -1, flap = { deg = 12 } })
	),
	-- The design's CATALOG2 squeeze (depth 0.6, widen 0.74, kRel 32, cRel 8, pitch 1.15) and flight (tumble).
	motion = {
		squeeze = { depth = 0.6, widen = 0.74, kRel = 32, cRel = 8, pitch = 1.15 },
		feel = "mochi",
		flight = { style = "tumble" },
	},
}

return blueprint
