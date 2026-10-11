--!strict
-- Toast (spec 2026-10-09 §4): the 3D Lab slice. 13 visible parts + Root, 6 hidden squish-face parts, no sections.
-- Authored in design studs (toys.js metres / 0.28, facing -Z) with the in-hand fit in `scale`. Pivot at the centre of
-- the base block (both RBs are pivot-centred), so the dome sits above it.
-- Taller slice with a higher dome: the crust (RB base + E dome) frames a toasted crumb (RB + E) that stands out of both
-- faces; a light front panel (a flat lens E flagged body) carries the face, so the crumb shows its toasted edge around
-- it (the design's radial gradient as two tones). The panel's rim stays inside the crumb, so only its middle shows.

local Kit = require(script.Parent.Kit)

local v, F, concat = Kit.v, Kit.F, Kit.concat

local CRUST, CRUMB = "C9803F", "F0CE8C"

-- Face (design toast face(): eyes y 0.205, dx 0.065, eyeR 0.022 × 1.22; smile 0.045 lower; blush bx 0.11).
local EYE_X, EYE_Y, EYE_R = -0.232, 0.297, 0.096
local MOUTH_Y, MOUTH_W = 0.136, 0.159

local blueprint: Kit.Blueprint = {
	version = 2,
	scale = 0.93,
	parts = concat(
		{
			{ name = "CrustBase", shape = "RB", size = v(1.372, 1.029, 0.428), color = CRUST, body = true },
			{ name = "CrumbBase", shape = "RB", size = v(1.106, 0.729, 0.50), color = CRUMB, body = true },
			{
				name = "CrustDome",
				shape = "E",
				size = v(1.668, 0.818, 0.428),
				pos = v(0, 0.672, 0),
				color = CRUST,
				body = true,
			},
			{
				name = "CrumbDome",
				shape = "E",
				size = v(1.354, 0.83, 0.50),
				pos = v(0, 0.515, 0),
				color = CRUMB,
				body = true,
			},
			-- Light front panel: centred 0.075 behind the crumb face, its front stands 0.05 out at the middle.
			{
				name = "Panel",
				shape = "E",
				size = v(1.12, 0.96, 0.25),
				face = F(0, 0.245, 0.8),
				color = "FDF0D3",
				body = true,
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.393, 0.19, 0.094),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.66, widen = 0.60, kRel = 40, cRel = 9, pitch = 0.9 },
		feel = "foam",
		flight = { style = "frisbee" },
	},
}

return blueprint
