--!strict
-- Gift box: box stand (scale 4), daily stand (1.5), box reveal (1). The lid group pops via mesh Offset. Ribbon names
-- BoxRibbonZ/X (box centre) and LidRibbonZ/X (lid centre); lid parts carry group "lid".

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Box",
				shape = "B",
				size = v(2.0, 1.5, 2.0),
				pos = v(0, -0.15, 0),
				color = "FF8FB1",
				body = true,
			},
			{
				name = "BoxRibbonZ",
				shape = "B",
				size = v(0.36, 1.52, 2.02),
				pos = v(0, -0.15, 0),
				color = "8EDFC4",
			},
			{
				name = "BoxRibbonX",
				shape = "B",
				size = v(2.02, 1.52, 0.36),
				pos = v(0, -0.15, 0),
				color = "8EDFC4",
			},
			{
				name = "Lid",
				shape = "B",
				size = v(2.16, 0.42, 2.16),
				pos = v(0, 0.80, 0),
				color = "FFC7DA",
				group = "lid",
			},
			{
				name = "LidRibbonZ",
				shape = "B",
				size = v(0.38, 0.44, 2.18),
				pos = v(0, 0.80, 0),
				color = "8EDFC4",
				group = "lid",
			},
			{
				name = "LidRibbonX",
				shape = "B",
				size = v(2.18, 0.44, 0.38),
				pos = v(0, 0.80, 0),
				color = "8EDFC4",
				group = "lid",
			},
		},
		pair({
			name = "BowL",
			shape = "E",
			size = v(0.70, 0.40, 0.30),
			pos = v(-0.32, 1.18, 0),
			rot = v(0, 0, 25),
			color = "8EDFC4",
			group = "lid",
		}),
		{
			{
				name = "Knot",
				shape = "E",
				size = v(0.30, 0.28, 0.30),
				pos = v(0, 1.12, 0),
				color = "6CCFAE",
				group = "lid",
			},
		}
	),
}

return blueprint
