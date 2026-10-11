--!strict
-- Kitty Bread (spec 2026-10-09 §4): the 3D Lab loaf. 23 visible parts + Root, 6 hidden squish-face parts, 8 hinged
-- parts in 3 sections (EarL, EarR, Tail). Authored in design studs (toys.js metres / 0.28, turned to face -Z, y from
-- the body centre) with the in-hand fit in `scale`.
-- Flatter loaf: a dough Body E with a crust cap E on top. The crust crosses the dough at about 45° just above the eyes
-- (the design's colour band), so the face sits on the dough. Smaller TRI ears tilted 28° with pink inner ears, three
-- tabby stripes on the top front, two front paws and a curled tail (2 E) on the back. The lobby statue is baked: it
-- keeps the old look until a lobby rebuild. Keep the part named Body and the height under 1.41 studs (lobby statue).

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

local DOUGH, CRUST = "F2C487", "D48D4C"

-- Face (design kitty face(): eyes y 0.035, dx 0.085, eyeR 0.024 × 1.22; cat mouth; blush bx 0.14).
local EYE_X, EYE_Y, EYE_R = -0.304, -0.009, 0.105
local MOUTH_Y, MOUTH_W = -0.159, 0.19

-- Ears: the base sits on the crust at x ±0.589 (z -0.107, toward the front), sunk 0.1; turned 28° outward.
local EAR_POS = v(-0.686, 0.598, -0.107)
local EAR_TILT = 28

local blueprint: Kit.Blueprint = {
	version = 2,
	scale = 0.74,
	parts = concat(
		{
			{ name = "Body", shape = "E", size = v(2.14, 1.06, 1.68), color = DOUGH, body = true },
			{
				name = "Crust",
				shape = "E",
				size = v(2.04, 0.72, 1.60),
				pos = v(0, 0.22, 0),
				color = CRUST,
				body = true,
			},
		},
		pair({
			name = "EarL",
			shape = "TRI",
			w = 0.50,
			h = 0.414,
			t = 0.20,
			pos = EAR_POS,
			rot = v(0, 0, EAR_TILT),
			color = CRUST,
			rigidity = 0.2,
			section = "EarL",
			contact = v(0, -1, 0),
		}),
		-- The pink inner ear stands 0.02 out of the ear's front face, turned with it. Not an attach part: a TRI is built
		-- as two halves, so "EarL" names no built part; its lower end sits in the crust instead.
		pair({
			name = "InnerEarL",
			shape = "E",
			size = v(0.24, 0.30, 0.06),
			pos = v(-0.658, 0.545, -0.217),
			rot = v(0, 0, EAR_TILT),
			color = "F5A9A0",
			section = "EarL",
			contact = v(0, -1, 0),
		}),
		-- Tabby stripes run front to back on the crust's top front, turned to its slope.
		pair({
			name = "StripeL",
			shape = "E",
			size = v(0.08, 0.04, 0.25),
			pos = v(-0.16, 0.518, -0.39),
			rot = v(-14.3, 0, 3.4),
			color = "B86A35",
			look = "detail",
			contact = v(0, -1, 0),
		}),
		{
			{
				name = "Stripe",
				shape = "E",
				size = v(0.08, 0.04, 0.30),
				pos = v(0, 0.529, -0.36),
				rot = v(-12.8, 0, 0),
				color = "B86A35",
				look = "detail",
				contact = v(0, -1, 0),
			},
		},
		pair({ name = "PawL", shape = "E", size = v(0.32, 0.21, 0.29), face = F(-0.357, -0.40, 0.65), color = "FCEBD0" }),
		-- Curled tail on the back (the design's 225° torus as two strokes), wagging about its root near the middle.
		{
			{
				name = "TailA",
				shape = "E",
				size = v(0.34, 0.16, 0.16),
				face = F(-0.18, 0.054, 0.55, "back"),
				rot = v(0, 0, 33.7),
				color = CRUST,
				section = "Tail",
			},
			{
				name = "TailB",
				shape = "E",
				size = v(0.34, 0.16, 0.16),
				face = F(-0.373, -0.026, 0.55, "back"),
				rot = v(0, 0, -78.8),
				color = CRUST,
				section = "Tail",
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.50, -0.116, 0.094),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		-- X and Z swing signs flip from the design (+1 there), as for every toy (spec §3.1).
		Kit.pairSection(
			"EarL",
			{ pivot = v(-0.657, 0.436, -0.15), axis = "X", amp = 0.9, sign = -1, flap = { deg = 15 } }
		),
		{ Tail = { pivot = v(-0.08, -0.013, 0.80), axis = "Z", amp = 1.2, sign = -1, flap = { deg = 15 } } }
	),
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.60, widen = 0.72, kRel = 34, cRel = 8.5, pitch = 1.0 },
		feel = "foam",
		flight = { style = "tumble" },
	},
}

return blueprint
