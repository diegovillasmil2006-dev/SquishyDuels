--!strict
-- Dragon Rush head (built at ≈ 3.2 by the VFX code): 19 parts + Root. Mouth toward -Z. §8.2 gives only the part list:
-- designed here, ≈ 1.10 wide × 1.78 long at scale 1 (≈ 3.5 × 5.7 studs at the ≈ 3.2 build scale, narrower than the
-- 8-stud Rush lane); LowerJaw carries group "jaw". Face kit v1. Recoloured to the 3D Lab Dragon (spec 2026-10-09 §4):
-- mint body, light muzzle, cream-gold horns, lilac mane; the shapes are unchanged.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Head",
				shape = "E",
				size = v(1.10, 0.92, 1.04),
				pos = v(0, 0.10, 0.30),
				color = "5ECBA8",
				body = true,
			},
			{
				name = "Snout",
				shape = "E",
				size = v(0.72, 0.40, 0.84),
				pos = v(0, 0.06, -0.44),
				color = "A9EBD4",
				body = true,
			},
			{
				name = "UpperJaw",
				shape = "W",
				size = v(0.62, 0.16, 0.74),
				pos = v(0, -0.12, -0.44),
				color = "A9EBD4",
			},
			{
				name = "LowerJaw",
				shape = "W",
				size = v(0.58, 0.16, 0.70),
				pos = v(0, -0.30, -0.38),
				rot = v(0, 0, 180),
				color = "4FBE9B",
				group = "jaw",
			},
		},
		pair({
			name = "HornL",
			shape = "TRI",
			w = 0.22,
			h = 0.46,
			t = 0.14,
			pos = v(-0.32, 0.62, 0.48),
			rot = v(20, 0, 15),
			color = "FFE2A0",
		}),
		Kit.eyes(-0.27, 0.26, v(0.17, 0.21, 0.08)),
		pair({
			name = "BrowL",
			shape = "W",
			size = v(0.30, 0.08, 0.12),
			face = F(-0.27, 0.42, 0.6),
			rot = v(0, 0, -20),
			color = "3BA58A",
		}),
		pair({
			name = "NostrilL",
			shape = "E",
			size = v(0.10, 0.07, 0.04),
			face = F(-0.12, 0.14, 0.6),
			color = "2F7D68",
		}),
		{
			{
				name = "ManeCentre",
				shape = "E",
				size = v(0.34, 0.56, 0.30),
				pos = v(0, 0.62, 0.62),
				rot = v(35, 0, 0),
				color = "B892F0",
			},
		},
		pair({
			name = "ManeL",
			shape = "E",
			size = v(0.26, 0.44, 0.24),
			pos = v(-0.22, 0.54, 0.74),
			rot = v(35, 0, 20),
			color = "C6A3F4",
		})
	),
}

return blueprint
