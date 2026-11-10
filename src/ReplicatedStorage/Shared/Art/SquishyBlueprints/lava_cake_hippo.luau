--!strict
-- Lava Cake Hippo (Epic, Lava Box, 2026-11-10): Claude Design's LavaCakeHippo ("Squishies 50 Lineup",
-- sd/toys2.js:459-482) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this
-- is the fallback and the size, sections and motion every view reads. A chocolate lava-cake hippo with cream on top and a
-- strawberry, a jaw that drops open on the molten middle (section Jaw, with its two teeth), ears and a tail that flick
-- (sections EarL/EarR, Tail), nostrils, big eyes, no mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 3.55, 0.1545
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.07, dx 0.085, eyeR 0.022 × 1.22 big eyes, no mouth, blush 0.145 / 0.052).
local EYE_X, EYE_Y, EYE_R = -0.085 * K, (0.219 - Y0) * K, 0.0268 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3983, 0.309, 0.4007),
				pos = at(0, 0.1545, 0.0109),
				color = "9C5E40",
				body = true,
			},
			-- The cream top (the design fades the cake to cream above its middle).
			{
				name = "Cream",
				shape = "E",
				size = size(0.36, 0.12, 0.36),
				pos = at(0, 0.27, 0),
				color = "F6E8DC",
				body = true,
			},
			{
				name = "Molten",
				shape = "E",
				size = size(0.15, 0.06, 0.0953),
				pos = at(0, 0.113, 0.15),
				color = "FF8A30",
				body = true,
			},
			-- The jaw hangs under the snout; its contact is the hinge, inside the body.
			{
				name = "Jaw",
				shape = "E",
				size = size(0.2167, 0.09, 0.192),
				pos = at(0, 0.077, 0.125),
				color = "9C5E40",
				section = "Jaw",
				contact = v(0, 0.46, 0.82),
			},
			{
				name = "Strawberry",
				shape = "E",
				size = size(0.052, 0.064, 0.0495),
				pos = at(0.03, 0.335, -0.03),
				color = "F0445E",
				contact = v(0, -0.9, 0),
			},
			{
				name = "Leaves",
				shape = "E",
				size = size(0.052, 0.0162, 0.0567),
				attach = { to = "Strawberry", offset = size(-0.0066, 0.029, 0) },
				contact = v(0, -1, 0), -- its underside on the berry
				color = "5CC46A",
			},
			-- The tail's contact is its hinge, just inside the body's back.
			{
				name = "Tail",
				shape = "E",
				size = size(0.0301, 0.0549, 0.0543),
				pos = at(0.004, 0.1465, -0.2015),
				color = "9C5E40",
				section = "Tail",
				contact = v(0, 0, -0.9),
			},
		},
		pair({
			name = "ToothL",
			shape = "B",
			size = size(0.014, 0.03, 0.01), -- taller: the lower half is set into the jaw
			attach = { to = "Jaw", offset = size(-0.05, 0.029, -0.045) }, -- set into the jaw's top front
			contact = v(0.3, -0.9, 0.3),
			color = "FFFFFF",
			section = "Jaw",
		}),
		pair({
			name = "NostrilL",
			shape = "E",
			size = size(0.0194, 0.0139, 0.0091),
			face = F(-0.035 * K, (0.149 - Y0) * K, 0.5),
			color = "6E3E2A",
			look = "detail",
		}),
		-- The ears' contact is just under the hinge, inside the body.
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0432, 0.0486, 0.0312),
			pos = at(0.127, 0.2801, -0.03),
			color = "8E5236",
			section = "EarL",
			contact = v(0.6, -0.5, -0.05),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.blush2(-0.145 * K, (0.167 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.1152, 0.2726, -0.0292), axis = "X", amp = 1, sign = -1, flap = { deg = 15 } }),
		{
			Jaw = { pivot = at(0, 0.0975, 0.046), axis = "X", amp = 3.2, sign = -1, flap = { deg = 10 } },
			Tail = { pivot = at(0.004, 0.1465, -0.1771), axis = "Z", amp = 1.6, sign = -1, flap = { deg = 15 } },
		}
	),
	-- The design's CATALOG2 squeeze (depth 0.6, widen 0.72, kRel 32, cRel 8, pitch 0.85) and flight (face).
	motion = {
		squeeze = { depth = 0.6, widen = 0.72, kRel = 32, cRel = 8, pitch = 0.85 },
		feel = "foam",
		flight = { style = "face" },
	},
}

return blueprint
