--!strict
-- Butter (spec 2026-10-09 §4): the 3D Lab wrapped butter stick. 18 visible parts + Root, 4 hidden squish-face parts
-- (the mouth is already open, so the squish set is the two chevrons only), no sections. Authored in design studs
-- (toys.js metres / 0.28, facing -Z, y from the block centre) with the in-hand fit in `scale`.
-- Soft RB block; a paper wrapper box on the lower half with a blue label band and a gold seal on the front; folded
-- paper ends (TRI) on both ends; a butter curl and a melt puddle on top. Open mouth + tongue (look mouthOpen); the
-- tongue is attached in front of the mouth so it never hides behind it. All parts are axis-aligned or turned about Y,
-- the squeeze axis, so the deformer keeps them exact.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

local PAPER = "FFF5DE"

-- Face (design butter face(): eyes y 0.065, dx 0.08, eyeR 0.022 × 1.22; open mouth 0.045 lower; blush bx 0.135).
local EYE_X, EYE_Y, EYE_R = -0.286, 0.232, 0.096

local blueprint: Kit.Blueprint = {
	version = 2,
	scale = 0.82,
	parts = concat(
		{
			{ name = "Body", shape = "RB", size = v(1.786, 0.929, 1.143), color = "FBE38C", body = true },
			-- The wrapper's top stays a little under the mouth; the band and the seal stand out of it.
			{
				name = "Wrapper",
				shape = "B",
				size = v(1.843, 0.449, 1.20),
				pos = v(0, -0.265, 0),
				color = PAPER,
				body = true,
			},
			{
				name = "Label",
				shape = "B",
				size = v(1.871, 0.129, 1.229),
				pos = v(0, -0.25, 0),
				color = "4A78D6",
				body = true,
			},
			{
				name = "Seal",
				shape = "E",
				size = v(0.243, 0.171, 0.043),
				attach = { to = "Label", offset = v(0, 0, -0.626) },
				color = "E8B84A",
				look = "detail",
			},
		},
		-- Folded paper ends: a flat triangle on each end, its middle plane just inside the wrapper.
		pair({
			name = "FoldL",
			shape = "TRI",
			w = 0.536,
			h = 0.25,
			t = 0.07,
			pos = v(-0.912, -0.332, 0),
			rot = v(0, 90, 0),
			color = "F0E2C2",
			look = "detail",
			contact = v(0, -1, 0),
		}),
		{
			{
				name = "Curl",
				shape = "E",
				size = v(0.40, 0.16, 0.26),
				pos = v(0.357, 0.494, -0.107),
				rot = v(0, 34, 0),
				color = "F6D35C",
				contact = v(0, -1, 0),
			},
			{
				name = "Melt",
				shape = "E",
				size = v(0.571, 0.086, 0.429),
				pos = v(-0.25, 0.454, 0.071),
				color = "FDE89A",
				contact = v(0, -1, 0),
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		{
			{
				name = "Mouth",
				shape = "E",
				size = v(0.155, 0.124, 0.052),
				face = F(0, 0.071, 0.6),
				color = Kit.MOUTH_OPEN,
				look = "mouthOpen",
			},
			{
				name = "Tongue",
				shape = "E",
				size = v(0.099, 0.062, 0.041),
				attach = { to = "Mouth", offset = v(0, -0.026, -0.015) },
				color = Kit.TONGUE,
				look = "mouthOpen",
			},
		},
		Kit.blush2(-0.482, 0.143, 0.094),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.62, widen = 0.70, kRel = 30, cRel = 9.5, pitch = 0.85 },
		feel = "foam",
		flight = { style = "tumble", amp = 0.7 },
	},
}

return blueprint
