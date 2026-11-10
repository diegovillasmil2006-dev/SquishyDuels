--!strict
-- Parfait Wyvern (Exclusive, shown Legendary; Frosty Box, 2026-11-10): Claude Design's ParfaitWyvern ("Squishies 50
-- Lineup", sd/toys2.js:305-326) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own
-- meshes: the layered parfait glass, the sugar wings); this is the fallback and the size, sections and motion every
-- view reads. A parfait glass on its foot with pink and blueberry layers under the cream, sugar wings that flutter
-- (sections WingL/WingR), a pink tail that curls (section Tail), whipped cream and a blueberry on top, big eyes, a
-- smile, cheeks.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.75 studs, a little
-- bigger than the Commons like the Dragon and Cosmo), turned 180° about Y and re-based on the glass's middle (design
-- y = Y0, the slot model's pivot).
local K, Y0 = 2.77, 0.261
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.405, dx 0.076, eyeR 0.025 × 1.22 big eyes, smile mw 0.022 at 0.046 below, blush 0.13).
local EYE_X, EYE_Y, EYE_R = -0.076 * K, (0.405 - Y0) * K, 0.0305 * K
local MOUTH_Y, MOUTH_W = (0.3559 - Y0) * K, 0.0625 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			-- The glass's bowl (the cream layer the face sits on).
			{
				name = "Bowl",
				shape = "E",
				size = size(0.368, 0.384, 0.368),
				pos = at(0, 0.33, 0),
				color = "FFF6EE",
				body = true,
			},
			-- The design's layers as bands a little wider than the bowl: pink low, blueberry higher.
			{
				name = "PinkLayer",
				shape = "E",
				size = size(0.3, 0.12, 0.3),
				pos = at(0, 0.2, 0),
				color = "FF8FAE",
				body = true,
			},
			{
				name = "BlueberryLayer",
				shape = "E",
				size = size(0.38, 0.05, 0.38),
				pos = at(0, 0.31, 0),
				color = "A8A2F2",
				body = true,
			},
			{
				name = "Stem",
				shape = "E",
				size = size(0.1, 0.1, 0.1),
				pos = at(0, 0.08, 0),
				color = "E7B676",
				body = true,
			},
			{
				name = "Foot",
				shape = "E",
				size = size(0.24, 0.06, 0.24),
				pos = at(0, 0.03, 0),
				color = "E7B676",
				body = true,
			},
			{
				name = "Cream",
				shape = "E",
				size = size(0.1302, 0.0748, 0.1302),
				pos = at(0, 0.5474, 0),
				color = "FFF8F0",
				contact = v(0, -0.9, 0),
			},
			{
				name = "Berry",
				shape = "E",
				size = size(0.044, 0.044, 0.0418),
				pos = at(0, 0.598, 0),
				color = "7E78E0",
				contact = v(0, -1, 0),
				contactWith = "Cream",
			},
			-- The tail reaches into the glass from behind: its contact is the hinge, inside the bowl.
			{
				name = "Tail",
				shape = "E",
				size = size(0.22, 0.13, 0.22),
				pos = at(0.07, 0.21, -0.18),
				color = "FF8FAE",
				section = "Tail",
				contact = v(0.455, 0.154, -0.727),
			},
		},
		-- Each wing reaches into the bowl's side: its contact is the hinge, inside the bowl.
		pair({
			name = "WingL",
			shape = "E",
			size = size(0.17, 0.25, 0.06),
			pos = at(0.18, 0.4, -0.1),
			color = "FFDD88",
			section = "WingL",
			contact = v(0.588, -0.56, -0.167),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.13 * K, (0.37 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("WingL", { pivot = at(0.13, 0.33, -0.095), axis = "Y", amp = 1.4, sign = 1, flap = { deg = 25 } }),
		{ Tail = { pivot = at(0.02, 0.22, -0.1), axis = "Y", amp = 0.9, sign = 1, flap = { deg = 10 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.64, kRel 40, cRel 7.5, pitch 0.95) and flight (glide).
	motion = {
		squeeze = { depth = 0.62, widen = 0.64, kRel = 40, cRel = 7.5, pitch = 0.95 },
		feel = "jelly",
		flight = { style = "glide" },
	},
}

return blueprint
