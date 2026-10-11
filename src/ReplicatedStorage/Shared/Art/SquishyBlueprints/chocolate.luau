--!strict
-- Chocolate (Uncommon; 3D Lab redesign, spec 2026-10-09 §4): 21 parts + Root, 6 hidden squish-face parts, no sections.
-- A dark rounded bar with 2 x 2 pillow squares front and back, a red wrapper on the lower half with a gold foil strip
-- above it, a cream label carrying the face (face kit v2, no eye-whites) and a seam on the back.
-- Authored in design studs (the 3D Lab's metres / 0.28, turned to face -Z, centred on the bar); `scale` fits the hand.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

local SQUARE = v(0.43, 0.30, 0.17)
local SQUARE_X, SQUARE_UPPER_Y, SQUARE_LOWER_Y = -0.243, 0.589, 0.268
local SQUARE_COLOR = "7A4532"
local LABEL_Y = -0.446
local EYE_X, EYE_Y, EYE_R = -0.161, -0.40, 0.074
local MOUTH_Y, MOUTH_W = -0.514, 0.127

-- One pillow square pair on the front, or on the back (side "back").
local function squares(name: string, y: number, side: ("front" | "back")?): { Kit.PartSpec }
	return pair({
		name = name,
		shape = "E",
		size = SQUARE,
		face = F(SQUARE_X, y, 0.6, side),
		color = SQUARE_COLOR,
		look = "detail",
	})
end

local blueprint: Kit.Blueprint = {
	version = 2,
	scale = 0.97,
	parts = concat(
		{
			{ name = "Bar", shape = "RB", size = v(1.07, 1.57, 0.36), color = "6E3D2B", body = true },
			{
				name = "Wrapper",
				shape = "B",
				size = v(1.13, 0.765, 0.41),
				pos = v(0, -0.44, 0),
				color = "D8475E",
				body = true,
			},
			-- The gold strip shows above the wrapper's top edge; its bottom sits in the bar.
			{
				name = "Foil",
				shape = "B",
				size = v(1.10, 0.14, 0.385),
				pos = v(0, -0.02, 0),
				color = "E8B84A",
				contact = v(0, -1, 0),
			},
		},
		squares("SquareUpperL", SQUARE_UPPER_Y),
		squares("SquareLowerL", SQUARE_LOWER_Y),
		squares("SquareBackUpperL", SQUARE_UPPER_Y, "back"),
		squares("SquareBackLowerL", SQUARE_LOWER_Y, "back"),
		{
			{
				name = "Seam",
				shape = "B",
				size = v(0.07, 0.66, 0.04),
				face = F(0, LABEL_Y, 0.6, "back"),
				color = "B8364C",
				look = "detail",
			},
			-- The label is a face-ray target for the face parts listed after it.
			{
				name = "Label",
				shape = "E",
				size = v(0.70, 0.50, 0.114),
				face = F(0, LABEL_Y, 0.75),
				color = "FFF1DC",
				body = true,
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.257, -0.479, 0.055),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.68, widen = 0.58, kRel = 42, cRel = 9, pitch = 0.8 },
		feel = "foam",
		flight = { style = "frisbee" },
	},
}

return blueprint
