--!strict
-- Divine Loaf (Legendary, Halo Box, 2026-11-10): Claude Design's DivineLoaf ("Squishies 50 Lineup",
-- sd/toys2.js:773-797) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes);
-- this is the fallback and the size, sections and motion every view reads. A pearly royal loaf with a gold crown and
-- its gem, ears that flick (sections EarL/EarR), wings that flutter (sections WingL/WingR), a curled tail (section
-- Tail), paws, big eyes, a cat mouth, cheeks.
-- Hinges and contacts: the point deepest inside both the part and its holder (halo/gen_bp.mjs, |q| <= 0.84); a part is
-- moved toward its holder only where the design's spot left no room.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.3, 0.2228
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y -0.01, dx 0.09, eyeR 0.026 × 1.22 big eyes, cat mouth mw 0.024 at 0.05 below, blush 0.16).
local EYE_X, EYE_Y, EYE_R = -0.09 * K, (0.1862 - Y0) * K, 0.0317 * K
local MOUTH_Y, MOUTH_W = (0.1334 - Y0) * K, 0.067 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.4399, 0.4225, 0.3399),
				pos = at(0, 0.2228, 0),
				color = "FFFDF8",
				body = true,
			},
			{
				name = "Crown",
				shape = "E",
				size = size(0.144, 0.0761, 0.144),
				pos = at(0, 0.431, 0), -- 0.033 toward its holder
				color = "F4D27A",
				contact = v(0, -0.83, 0),
			},
			{
				name = "Gem",
				shape = "E",
				size = size(0.028, 0.032, 0.0139),
				pos = at(0, 0.4394, 0.065), -- 0.005 toward its holder
				color = "C7A0FF",
				contact = v(0, -0.33, 0.75),
				contactWith = "Crown",
			},
			{
				name = "Tail",
				shape = "E",
				size = size(0.1331, 0.1415, 0.0534),
				pos = at(0.0833, 0.1777, -0.151),
				color = "FFF6EE",
				section = "Tail",
				contact = v(0.42, 0.25, -0.67),
			},
		},
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.1028, 0.1068, 0.0682),
			pos = at(0.1622, 0.3773, 0.0001),
			color = "FFF6EE",
			section = "EarL",
			contact = v(0.5, -0.67, 0),
		}),
		pair({
			name = "WingL",
			shape = "E",
			size = size(0.0741, 0.1196, 0.0653),
			pos = at(0.1451, 0.292, -0.114), -- 0.050 toward its holder
			color = "FFFFFF",
			section = "WingL",
			contact = v(0.5, -0.33, -0.58),
		}),
		pair({
			name = "PawL",
			shape = "E",
			size = size(0.0965, 0.0757, 0.0731),
			pos = at(0.0971, 0.0716, 0.0935), -- 0.020 toward its holder
			color = "FFF6EE",
			contact = v(0.33, 0.58, 0.5),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.16 * K, (0.1512 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.1365, 0.3417, 0.0001), axis = "X", amp = 0.9, sign = -1, flap = { deg = 12 } }),
		Kit.pairSection("WingL", { pivot = at(0.1266, 0.272, -0.0949), axis = "Y", amp = 1.4, sign = 1, flap = { deg = 15 } }),
		{
			Tail = { pivot = at(0.0556, 0.1954, -0.1332), axis = "Z", amp = 1.2, sign = -1, flap = { deg = 12 } },
		}
	),
	-- The design's CATALOG2 squeeze (depth 0.6, widen 0.72, kRel 30, cRel 8, pitch 0.9) and flight (upright).
	motion = {
		squeeze = { depth = 0.6, widen = 0.72, kRel = 30, cRel = 8, pitch = 0.9 },
		feel = "foam",
		flight = { style = "upright" },
	},
}

return blueprint
