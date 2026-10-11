--!strict
-- Mochi Fox (Uncommon, new; spec 2026-10-09 §4): the 3D Lab MochiFox (sd/toys.js) in E/TRI parts. A cream mochi body
-- with a flared base, an orange hood overlay (top and back), TRI ears with cream inners (sections EarL/EarR), a 4-E tail
-- curling round its left with a white tip (section Tail), a sakura pin, happy-arc eyes. 24 visible + 6 hidden
-- squish-face parts + Root.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design units (toys.js metres, face +Z) to studs at scale 1: K studs per unit, turned 180° about Y (x -> -x, z -> -z)
-- and re-based so the pivot sits at the body's middle (design y = Y0).
local K, Y0 = 2.65, 0.02
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

local CREAM, ORANGE = "FFF8EF", "F39A4C"
-- Face (design face(): y 0.03, dx 0.075, eyeR 0.022 × 1.22 happy arcs, cat mouth mw 0.02 × 1.11 at 0.04 below, blush
-- 0.13 / 0.022, br 0.028 × 1.1).
local EYE_X, EYE_Y, EYE_R = -0.075 * K, (0.03 - Y0) * K, 0.0268 * K
local MOUTH_Y, MOUTH_W = (-0.01 - Y0) * K, 0.05 * K
-- Hood: the body ellipsoid × 0.955, moved up 0.0375 and back 0.0294, so it shows above the plane y = 0.333 + 0.515 z
-- (body-normalised): the design's orange mask (top and back, a cream face and sides).
local HOOD_CENTRE = at(0, 0.0475, -0.0294)
-- Ears: thin TRI plates, bases sunk 0.027 under the hood at x ±0.13, tilted 16° out (the design's 0.28 rad) and turned
-- 20° out about Y, so both edges lean in (a point, not a slab) and the side view shows a narrow triangle like the
-- design's flattened cone; the hinge 0.015 up the ear. Follow-up fix 2026-10-10: tilted 30° with t 0.06 the near ear
-- read as a flat brown block from the reveal's angle. EAR_CENTRE = base centre + R·(0, h/2, 0), EAR_PIVOT = base centre
-- + R·(0, 0.015, 0), the inner ear = EAR_CENTRE + R·(0, -0.012, -0.02) (design units, R = the ear's rot).
local EAR_CENTRE = at(0.1493, 0.2073, 0)
local EAR_ROT = v(0, 20, 16)
local EAR_PIVOT = at(0.1351, 0.1544, 0.0052)
local TAIL_ROOT = at(0, 0.06, -0.19)
-- Sakura pin on the hood's top-front at the fox's right (design x -0.075, z 0.1), facing out along the hood normal.
local PIN = at(-0.0754, 0.1557, 0.1009)
local PIN_ROT = v(62.2, -12.2, 0)

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.51, 0.3, 0.456),
				pos = at(0, 0.01, 0),
				color = CREAM,
				body = true,
			},
			-- The base is the sagging mochi bottom: a little wider than the body, crossing it at a clear angle.
			{
				name = "Base",
				shape = "E",
				size = size(0.524, 0.17, 0.47),
				pos = at(0, -0.06, 0),
				color = CREAM,
				body = true,
			},
			{
				name = "Hood",
				shape = "E",
				size = size(0.487, 0.2866, 0.4354),
				pos = HOOD_CENTRE,
				color = ORANGE,
				body = true,
			},
		},
		pair({
			name = "EarL",
			shape = "TRI",
			w = 0.13 * K,
			h = 0.14 * K,
			t = 0.03 * K,
			pos = EAR_CENTRE,
			rot = EAR_ROT,
			color = ORANGE,
			section = "EarL",
			contact = v(0, -0.8, 0),
		}),
		pair({
			name = "InnerEarL",
			shape = "E",
			size = size(0.06, 0.09, 0.02),
			pos = EAR_CENTRE + size(-0.0037, -0.0115, -0.0199),
			rot = EAR_ROT,
			color = "FFE7D2",
			section = "EarL",
			contact = v(0, 0, 0.8),
			contactWith = "EarL",
		}),
		-- Tail: 4 segments along the design curve (root at the back, round the fox's left, tip forward); each overlaps the
		-- one before it, the first holds the hinge.
		{
			{
				name = "Tail1",
				shape = "E",
				size = size(0.18, 0.11, 0.11),
				pos = at(0.055, 0.056, -0.23),
				rot = v(0, 33.5, 4),
				color = ORANGE,
				section = "Tail",
				contact = v(0.8, 0, 0),
			},
			{
				name = "Tail2",
				shape = "E",
				size = size(0.17, 0.145, 0.145),
				pos = at(0.185, 0.055, -0.235),
				rot = v(0, -28, -4),
				color = ORANGE,
				section = "Tail",
				contact = v(0.8, 0, 0),
				contactWith = "Tail1",
			},
			{
				name = "Tail3",
				shape = "E",
				size = size(0.13, 0.13, 0.16),
				pos = at(0.27, 0.07, -0.13),
				rot = v(8, 16, 0),
				color = ORANGE,
				section = "Tail",
				contact = v(0, 0, 0.8),
				contactWith = "Tail2",
			},
			{
				name = "Tail4",
				shape = "E",
				size = size(0.09, 0.09, 0.13),
				pos = at(0.268, 0.095, -0.03),
				rot = v(22, -25, 0),
				color = "FFFFFF",
				section = "Tail",
				contact = v(0, 0, 0.7),
				contactWith = "Tail3",
			},
			-- Sakura pin: two crossed petals (a 4-petal flower) and a yellow centre in front.
			{
				name = "PetalA",
				shape = "E",
				size = size(0.058, 0.02, 0.01),
				pos = PIN,
				rot = PIN_ROT,
				color = "FFB3C8",
				look = "detail",
				contact = v(0, 0, 1),
			},
			{
				name = "PetalB",
				shape = "E",
				size = size(0.058, 0.02, 0.01),
				pos = PIN,
				rot = PIN_ROT + v(0, 0, 90),
				color = "FFB3C8",
				look = "detail",
				contact = v(0, 0, 1),
			},
			{
				name = "PinCentre",
				shape = "E",
				size = size(0.016, 0.016, 0.012),
				attach = { to = "PetalA", offset = size(0, 0, -0.006) },
				color = "FFD25E",
				look = "detail",
			},
		},
		Kit.happyEyes(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.13 * K, (0.008 - Y0) * K, 0.0308 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = EAR_PIVOT, axis = "X", amp = 1.0, sign = -1, flap = { deg = 15 } }),
		-- The tail wraps the body, so its swing is held to 20° to limit clipping.
		{ Tail = { pivot = TAIL_ROOT, axis = "Y", amp = 0.9, maxDeg = 20, flap = { deg = 15 } } }
	),
	-- §4 row (spec 2026-10-09): tumble with a stretch pulse to 1.15 along travel.
	motion = {
		squeeze = { depth = 0.55, widen = 0.80, kRel = 26, cRel = 8, pitch = 1.2 },
		feel = "mochi",
		flight = { style = "tumble", pulse = 1.15 },
	},
}

return blueprint
