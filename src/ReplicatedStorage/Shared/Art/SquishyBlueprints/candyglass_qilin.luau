--!strict
-- Candyglass Qilin (Legendary, Prism Box, 2026-11-10): Claude Design's CandyglassQilin ("Squishies 50 Lineup",
-- sd/toys2.js:630-657) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, with
-- the candyglass panels); this is the fallback and the size, sections and motion every view reads. A pearly qilin on a
-- cloud, a muzzle, crystal antlers, a mane (section Mane) and a tail (section Tail) that flow, golden hooves, big eyes,
-- a smile, cheeks.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.75 studs: the
-- Legendary is held large like Dragon and Cosmo), turned 180° about Y and re-based on the body's middle (design y = Y0,
-- the slot model's pivot).
local K, Y0 = 3.4, 0.2558
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.245, dx 0.078, eyeR 0.025 × 1.22 big eyes, smile mw 0.018 at 0.068 below, blush 0.13).
local EYE_X, EYE_Y, EYE_R = -0.078 * K, (0.26 - Y0) * K, 0.0305 * K
local MOUTH_Y, MOUTH_W = (0.1908 - Y0) * K, 0.0537 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3785, 0.3283, 0.3563),
				pos = at(0, 0.2558, 0),
				color = "FFF6FB",
				body = true,
			},
			{
				name = "Cloud",
				shape = "E",
				size = size(0.49, 0.12, 0.4174),
				pos = at(0, 0.06, -0.0021),
				color = "FFFFFF",
				body = true,
			},
			-- The muzzle's back is inside the body.
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.1099, 0.0699, 0.0514),
				pos = at(0, 0.2032, 0.1613),
				color = "FFF8EE",
				contact = v(0, 0.33, 0.75),
			},
			{
				name = "Hooves",
				shape = "E",
				size = size(0.1971, 0.044, 0.0609),
				pos = at(0, 0.1431, 0.1201), -- set into the body's front bottom
				color = "F4C95D",
				contact = v(0, 0.5, 0.67),
			},
			-- The mane and the tail reach into the body: their contact is the hinge, inside the body.
			{
				name = "Mane",
				shape = "E",
				size = size(0.0533, 0.132, 0.1685),
				pos = at(0, 0.4028, -0.1062),
				color = "FFB3C8",
				section = "Mane",
				contact = v(0, -0.67, -0.33),
			},
			{
				name = "Tail",
				shape = "E",
				size = size(0.1404, 0.189, 0.1398),
				pos = at(0.046, 0.2537, -0.2024), -- 0.03 into the body
				color = "FFB3C8",
				section = "Tail",
				contact = v(0.08, 0, -0.83),
			},
		},
		-- The crystal antlers stand in the head's top.
		pair({
			name = "AntlerL",
			shape = "E",
			size = size(0.03, 0.1, 0.03),
			pos = at(0.0605, 0.4238, 0.0173), -- set into the head's top
			color = "C7A0FF",
			contact = v(0.08, -0.83, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.13 * K, (0.225 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = {
		Mane = { pivot = at(0, 0.3588, -0.0781), axis = "X", amp = 1.0, sign = -1, flap = { deg = 12 } },
		Tail = { pivot = at(0.0401, 0.2537, -0.1442), axis = "Y", amp = 1.0, sign = 1, flap = { deg = 12 } },
	},
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.66, kRel 40, cRel 7.5, pitch 1.05) and flight (glide).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 40, cRel = 7.5, pitch = 1.05 },
		feel = "plush",
		flight = { style = "glide" },
	},
}

return blueprint
