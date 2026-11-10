--!strict
-- Gelato Narwhal (Epic, Frosty Box, 2026-11-10): Claude Design's GelatoNarwhal ("Squishies 50 Lineup",
-- sd/toys2.js:283-303) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, with
-- the waffle-cone horn and the speckles); this is the fallback and the size, sections and motion every view reads. A
-- round gelato narwhal, white underneath and blue on top, a waffle horn that stays rigid (the design's note), flukes
-- that flick (section Tail), flippers (sections FlipperL/FlipperR), big eyes, a smile, cheeks.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 3.25, 0.1672
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0, dx 0.08, eyeR 0.025 × 1.22 big eyes, smile mw 0.022 at 0.046 below, blush 0.135).
local EYE_X, EYE_Y, EYE_R = -0.08 * K, (0.1543 - Y0) * K, 0.0305 * K
local MOUTH_Y, MOUTH_W = (0.1062 - Y0) * K, 0.0625 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Narwhal",
				shape = "E",
				size = size(0.4, 0.3343, 0.42),
				pos = at(0, 0.1672, 0),
				color = "F2FBFF",
				body = true,
			},
			-- The blue top and back (the design tints the gelato by height and by the back's normal).
			{
				name = "Cap",
				shape = "E",
				size = size(0.404, 0.22, 0.41),
				pos = at(0, 0.23, -0.02),
				color = "8CCDEB",
				body = true,
			},
			-- The waffle horn, leaning forward like the design's; rigid, its bottom end inside the body.
			{
				name = "Horn",
				shape = "E",
				size = size(0.06, 0.18, 0.06),
				pos = at(0, 0.35, 0.09),
				color = "E9B46C",
				rigidity = 1,
				contact = v(0, -0.9, 0),
			},
			-- The flukes reach into the body from behind: their contact is the hinge, inside the body.
			{
				name = "Tail",
				shape = "E",
				size = size(0.17, 0.045, 0.13),
				pos = at(0, 0.105, -0.22),
				color = "8CCDEB",
				section = "Tail",
				contact = v(0, 0.22, -0.846),
			},
		},
		-- Each flipper reaches into the body's side: its contact is the hinge, inside the body.
		pair({
			name = "FlipperL",
			shape = "E",
			size = size(0.11, 0.12, 0.065),
			pos = at(0.185, 0.08, 0.05),
			color = "9FD8F0",
			section = "FlipperL",
			contact = v(0.636, 0.5, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.135 * K, (0.1243 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("FlipperL", { pivot = at(0.15, 0.11, 0.05), axis = "Z", amp = 1.3, sign = -1, flap = { deg = 20 } }),
		{ Tail = { pivot = at(0, 0.11, -0.165), axis = "X", amp = 1.4, sign = -1, flap = { deg = 12 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.66, kRel 44, cRel 7.5, pitch 1.15) and flight (face).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 44, cRel = 7.5, pitch = 1.15 },
		feel = "mochi",
		flight = { style = "face" },
	},
}

return blueprint
