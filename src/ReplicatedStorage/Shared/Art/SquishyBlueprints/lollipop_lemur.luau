--!strict
-- Lollipop Lemur (Uncommon, Prism Box, 2026-11-10): Claude Design's LollipopLemur ("Squishies 50 Lineup",
-- sd/toys2.js:560-583) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, the
-- stick leaning back with its swirl and star); this is the fallback and the size, sections and motion every view reads.
-- A lavender body, a muzzle, ears that flick (sections EarL/EarR), a lollipop tail that sways like a metronome (section
-- Tail: the stick straight up from behind the body, the candy on its line), feet, eyes, a cat mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side, the lollipop included,
-- about 1.6 studs), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.95, 0.1542
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.022, dx 0.066, eyeR 0.029 × 1.22 big eyes, cat mouth mw 0.012 at 0.062 below, blush 0.11).
local EYE_X, EYE_Y, EYE_R = -0.066 * K, (0.1653 - Y0) * K, 0.0354 * K
local MOUTH_Y, MOUTH_W = (0.102 - Y0) * K, 0.042 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.2994, 0.3083, 0.2781),
				pos = at(0, 0.1542, 0),
				color = "E6E0FA",
				body = true,
			},
			-- The muzzle's back is inside the body.
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.08, 0.0594, 0.0384),
				pos = at(0, 0.1147, 0.1282),
				color = "FFFFFF",
				contact = v(0, 0.33, 0.75),
			},
			{
				name = "Feet",
				shape = "E",
				size = size(0.1771, 0.032, 0.0647),
				pos = at(0, 0.036, 0.0826),
				color = "B9AEE0",
				contact = v(0, 0.5, 0.67),
			},
			-- The lollipop stick stands straight up with its foot inside the body's back, thick enough that the candy stays on it
			-- as the tail sways (the real model's is thin and leans back).
			{
				name = "Stick",
				shape = "E",
				size = size(0.06, 0.31, 0.06),
				pos = at(0, 0.2383, -0.11),
				color = "FFF8F0",
				section = "Tail",
				contact = v(0, -0.5, -0.5), -- the hinge, inside the body
			},
			{
				-- The candy disc faces back, on the stick's line near its top.
				name = "Candy",
				shape = "E",
				size = size(0.17, 0.17, 0.03),
				attach = { to = "Stick", offset = size(0, 0.08, 0) },
				contact = v(0, 0, 0), -- its middle on the stick
				color = "FF8FC8",
				section = "Tail",
			},
		},
		-- The ears' contact is their hinge, just inside the body's top.
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0551, 0.0578, 0.0309),
			pos = at(0.1098, 0.2566, 0),
			color = "B9AEE0",
			section = "EarL",
			contact = v(0.67, -0.5, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.11 * K, (0.1253 - Y0) * K, 0.02 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.0915, 0.2422, 0), axis = "X", amp = 0.8, sign = -1, flap = { deg = 15 } }),
		{ Tail = { pivot = at(0, 0.1608, -0.1025), axis = "Z", amp = 1.0, sign = -1, flap = { deg = 12 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.66, kRel 40, cRel 8, pitch 1.2) and flight (spiral).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 40, cRel = 8, pitch = 1.2 },
		feel = "plush",
		flight = { style = "spiral" },
	},
}

return blueprint
