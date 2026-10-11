--!strict
-- Strawberry Frog (Uncommon, new; spec 2026-10-09 §4): the 3D Lab StrawberryFrog (sd/toys.js) in E parts. Berry + tip E
-- (the taper) and two eye bumps, all body; big eyes on the bumps; 4 seeds; a 3-leaf calyx + stem that bounce together
-- (section Calyx); feet with toe bars. 24 visible + 6 hidden squish-face parts + Root.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design units (toys.js metres, face +Z) to studs at scale 1: K studs per unit, turned 180° about Y (x -> -x, z -> -z)
-- and re-based so the pivot sits at the body's middle (design y = Y0).
local K, Y0 = 3.6, 0.03
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

local RED, GREEN, STEM, SEED = "EE4A5C", "6CC56A", "4FA650", "FFE07A"
-- Face (design face(): y 0.18, dx 0.095, eyeR 0.03 × 1.22, smile mw 0.036 × 1.11 at 0.105 below, blush 0.15 / 0.1).
local EYE_X, EYE_Y, EYE_R = -0.095 * K, (0.18 - Y0) * K, 0.0366 * K
local MOUTH_Y, MOUTH_W = (0.075 - Y0) * K, 0.1 * K -- a little wider than the design's, to read at duel distance
local CALYX = at(0, 0.19, -0.04) -- sunk into the berry top, so every leaf root stays inside

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Berry",
				shape = "E",
				size = size(0.41, 0.33, 0.38),
				pos = at(0, 0.05, 0),
				color = RED,
				body = true,
			},
			{
				name = "Tip",
				shape = "E",
				size = size(0.24, 0.2, 0.22),
				pos = at(0, -0.08, 0),
				color = RED,
				body = true,
			},
		},
		pair({
			name = "EyeBumpL",
			shape = "E",
			size = size(0.136, 0.136, 0.136),
			pos = at(0.095, 0.17, 0.045),
			color = RED,
			body = true,
		}),
		-- Calyx: the stem first (it holds the section pivot), then 3 drooping leaves (front-left, front-right, back).
		{
			{
				name = "Stem",
				shape = "E",
				size = size(0.024, 0.075, 0.024),
				pos = CALYX + size(-0.008, 0.028, 0.005),
				rot = v(11, 0, 21),
				color = STEM,
				section = "Calyx",
				contact = v(0, -0.8, 0),
			},
		},
		-- Leaves tilt up 10° (the design's droop hid them behind the eye bumps); each root sits on the calyx centre.
		pair({
			name = "LeafL",
			shape = "E",
			size = size(0.11, 0.02, 0.055),
			pos = CALYX + size(-0.047, 0.0095, -0.027),
			rot = v(0, 150, 10),
			color = GREEN,
			section = "Calyx",
			contact = v(-0.7, 0, 0),
		}),
		{
			{
				name = "LeafBack",
				shape = "E",
				size = size(0.11, 0.02, 0.055),
				pos = CALYX + size(0, 0.0095, 0.054),
				rot = v(0, -90, 10),
				color = GREEN,
				section = "Calyx",
				contact = v(-0.7, 0, 0),
			},
		},
		pair({
			name = "FootL",
			shape = "E",
			size = size(0.1, 0.04, 0.09),
			pos = at(0.07, -0.165, 0.085),
			color = GREEN,
			contact = v(0.4, 0.6, 0.6),
		}),
		pair({
			name = "ToeL",
			shape = "E",
			size = size(0.085, 0.03, 0.03),
			pos = at(0.07, -0.167, 0.13),
			color = GREEN,
			contact = v(0, 0, 0.8),
			contactWith = "FootL",
		}),
		-- Face: big eyes on the bumps, a smile, cheeks; then 4 seeds kept off the face (2 low front, 2 on the sides).
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.15 * K, (0.08 - Y0) * K, 0.0286 * K),
		pair({
			name = "SeedLowL",
			shape = "E",
			size = size(0.026, 0.038, 0.014),
			face = F(-0.06 * K, (-0.07 - Y0) * K, 0.6),
			color = SEED,
			look = "detail",
		}),
		pair({
			name = "SeedSideL",
			shape = "E",
			size = size(0.026, 0.038, 0.014),
			face = F(-0.175 * K, (-0.005 - Y0) * K, 0.6),
			color = SEED,
			look = "detail",
		}),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = {
		Calyx = { pivot = CALYX, axis = "X", amp = 0.7, sign = -1, flap = { deg = 15 } },
	},
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 52, cRel = 8, pitch = 1.3 },
		feel = "jelly",
		flight = { style = "hop" },
	},
}

return blueprint
