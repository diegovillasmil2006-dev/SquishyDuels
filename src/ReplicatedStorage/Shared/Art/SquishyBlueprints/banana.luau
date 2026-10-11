--!strict
-- Banana (spec 2026-10-09 §4): the 3D Lab banana. 21 visible parts + Root, 6 hidden squish-face parts, no sections.
-- Authored in design studs (toys.js metres / 0.28, facing -Z, y from the body centre) with the in-hand fit in `scale`.
-- Squeeze axis Z (Catalog): every part is turned about Z only, so the deformer stays one exact linear map for it.
-- Slimmer and longer: 7 segments along the design arc (R 1.43 about (0, 1.34), ±43°) with the tube's taper, the eyes on
-- the centres of Seg±1 so they look straight ahead. Stem end segment green, olive stem + dark cap on +x (kept from the
-- old banana; the design has it on the other side), a brown tip nub on -x, 3 spots on the back, a clean face.

local Kit = require(script.Parent.Kit)

local v, F, concat = Kit.v, Kit.F, Kit.concat

local YELLOW = "FFE067"
local STEM_DEG = 60 -- the stem leaves the arc end steeper than its tangent (43°), so it stays inside the hand fit

-- Face (design banana face(): eyes y 0.012, dx 0.065, eyeR 0.019 × 1.22; smile 0.036 lower; blush bx 0.11).
local EYE_X, EYE_Y, EYE_R = -0.232, -0.046, 0.083
local MOUTH_Y, MOUTH_W = -0.175, 0.143

local function seg(name: string, x: number, y: number, deg: number, length: number, r: number, color: string?)
	return {
		name = name,
		shape = "E",
		size = v(length, 2 * r, 2 * r),
		pos = v(x, y, 0),
		rot = v(0, 0, deg),
		color = color or YELLOW,
		body = true,
	} :: Kit.PartSpec
end

local function spot(name: string, x: number, y: number, deg: number): Kit.PartSpec
	return {
		name = name,
		shape = "E",
		size = v(0.13, 0.09, 0.03),
		face = F(x, y, 0.6, "back"),
		rot = v(0, 0, deg),
		color = "8A6236",
		look = "detail",
	}
end

local blueprint: Kit.Blueprint = {
	version = 2,
	scale = 0.74,
	parts = concat(
		{
			-- Long segments (neighbours overlap by more than half) keep the dips between them under about 9% of
			-- the radius, so the arc reads smooth instead of as a row of beads.
			seg("Seg0", 0, -0.089, 0, 0.70, 0.268),
			seg("Seg+1", 0.235, -0.070, 9.45, 0.74, 0.268),
			seg("Seg-1", -0.235, -0.070, -9.45, 0.74, 0.261),
			seg("Seg+2", 0.523, 0.010, 21.49, 0.70, 0.255),
			seg("Seg-2", -0.523, 0.010, -21.49, 0.70, 0.240),
			seg("Seg+3", 0.789, 0.149, 33.52, 0.56, 0.217, "C9D85A"),
			seg("Seg-3", -0.789, 0.149, -33.52, 0.56, 0.197),
			-- Brown tip nub on the Seg-3 end, half out; its inner end stays inside.
			{
				name = "Tip",
				shape = "E",
				size = v(0.13, 0.12, 0.12),
				pos = v(-1.022, 0.303, 0),
				rot = v(0, 0, -33.52),
				color = "6B4A2B",
				contact = v(1, 0, 0),
			},
			-- Stem: starts 0.065 inside the Seg+3 end, leaves at STEM_DEG; the cap closes its far end.
			{
				name = "Stem",
				shape = "B",
				size = v(0.20, 0.12, 0.12),
				pos = v(1.040, 0.333, 0),
				rot = v(0, 0, STEM_DEG),
				color = "8C9A3E",
				contact = v(-1, 0, 0),
			},
			{
				name = "Cap",
				shape = "E",
				size = v(0.06, 0.14, 0.14),
				pos = v(1.095, 0.429, 0),
				rot = v(0, 0, STEM_DEG),
				color = "6B4A2B",
				contact = v(-1, 0, 0),
				contactWith = "Stem",
			},
			-- Spots on the back (the design's speckles, made big enough to read).
			spot("Spot1", -0.429, 0.018, 15),
			spot("Spot2", 0.179, -0.125, -10),
			spot("Spot3", 0.5, 0.09, 25),
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.393, -0.089, 0.079),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.70, widen = 0.55, kRel = 48, cRel = 9, pitch = 1.15 },
		feel = "foam",
		flight = { style = "spiral" },
	},
}

return blueprint
