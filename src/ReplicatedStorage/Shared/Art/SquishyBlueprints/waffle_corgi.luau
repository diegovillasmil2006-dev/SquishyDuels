--!strict
-- Waffle Corgi (Uncommon, Halo Box, 2026-11-10): Claude Design's WaffleCorgi ("Squishies 50 Lineup",
-- sd/toys2.js:717-734) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes);
-- this is the fallback and the size, sections and motion every view reads. A long waffle loaf of a corgi with a butter
-- pat on top, big ears that flick (sections EarL/EarR), a stubby tail that wags (section Tail), a white muzzle and
-- nose, paws, eyes, a cat mouth, cheeks.
-- Hinges and contacts: the point deepest inside both the part and its holder (halo/gen_bp.mjs, |q| <= 0.84); a part is
-- moved toward its holder only where the design's spot left no room.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.12, 0.1232
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.03, dx 0.066, eyeR 0.021 × 1.22, cat mouth mw 0.014 at 0.068 below (on the muzzle), blush 0.115).
local EYE_X, EYE_Y, EYE_R = -0.066 * K, (0.1383 - Y0) * K, 0.0256 * K
local MOUTH_Y, MOUTH_W = (0.0692 - Y0) * K, 0.0447 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3596, 0.2463, 0.4976),
				pos = at(0, 0.1232, 0),
				color = "F0C080",
				body = true,
			},
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.1, 0.0659, 0.0504),
				pos = at(-0.0002, 0.0839, 0.2197), -- 0.015 toward its holder
				color = "FFFFFF",
				contact = v(0, 0.5, 0.67),
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.032, 0.0219, 0.0159),
				pos = at(-0.0001, 0.0882, 0.2468), -- 0.012 toward its holder
				color = "2A1A22",
				contact = v(0, 0, 0.83),
				contactWith = "Muzzle",
			},
			{
				name = "Paws",
				shape = "E",
				size = size(0.2571, 0.04, 0.3609),
				pos = at(0, 0.0233, 0),
				color = "FFF6E6",
				contact = v(0, 0.67, 0),
			},
			{
				-- the butter pat
				name = "Butter",
				shape = "E",
				size = size(0.0813, 0.024, 0.0741),
				pos = at(0, 0.2344, -0.0377), -- 0.007 toward its holder
				color = "FBE38C",
				contact = v(0, -0.83, 0),
			},
			{
				name = "Tail",
				shape = "E",
				size = size(0.064, 0.06, 0.0571),
				pos = at(0, 0.1448, -0.2282), -- 0.037 toward its holder
				color = "FFF6E6",
				section = "Tail",
				contact = v(0, -0.33, -0.75),
			},
		},
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0968, 0.0949, 0.0566),
			pos = at(0.0927, 0.2137, 0.1448), -- 0.011 toward its holder
			color = "E09A50",
			section = "EarL",
			contact = v(0.42, -0.67, 0.25),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.115 * K, (0.0983 - Y0) * K, 0.02 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.0725, 0.182, 0.1377), axis = "X", amp = 1, sign = -1, flap = { deg = 12 } }),
		{
			Tail = { pivot = at(0, 0.1348, -0.2068), axis = "Y", amp = 1.8, sign = 1, flap = { deg = 15 } },
		}
	),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.66, kRel 40, cRel 8.5, pitch 1.1) and flight (frisbee).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 40, cRel = 8.5, pitch = 1.1 },
		feel = "foam",
		flight = { style = "frisbee" },
	},
}

return blueprint
