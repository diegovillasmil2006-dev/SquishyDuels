--!strict
-- Peachy (Common, Series 01, 2026-11-10): Claude Design's Peachy ("Squishies 50 Lineup", sd/toys2.js) in E parts. Its
-- real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this is the fallback and the size,
-- sections and motion every view reads. A foam peach, a stem, a leaf that flicks (section Leaf), happy-arc eyes, a smile,
-- cheeks.

local Kit = require(script.Parent.Kit)

local v, concat = Kit.v, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's 1.5-1.7 like its
-- siblings), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.97, 0.1798
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.005, dx 0.068, eyeR 0.022 × 1.22 happy arcs, smile mw 0.02 at 0.04 below, blush 0.115).
local EYE_X, EYE_Y, EYE_R = -0.0676 * K, (0.1606 - Y0) * K, 0.0268 * K
local MOUTH_Y, MOUTH_W = (0.1144 - Y0) * K, 0.0581 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Peach",
				shape = "E",
				size = size(0.3596, 0.3595, 0.344),
				pos = at(-0.0002, 0.1798, 0),
				color = "FFC27A",
				body = true,
			},
			{
				name = "Stem",
				shape = "E",
				size = size(0.0209, 0.0324, 0.022),
				pos = at(0.0058, 0.3674, 0),
				color = "8A5A34",
				contact = v(0, -0.8, 0),
			},
			-- The leaf starts at its hinge, which sits inside this look's peach (the design's dome top is higher), and reaches
			-- down into it: its contact is just under the hinge, so the flick never pulls it off.
			{
				name = "Leaf",
				shape = "E",
				size = size(0.11, 0.09, 0.06),
				pos = at(0.045, 0.355, 0.01),
				color = "67C46A",
				section = "Leaf",
				contact = v(0.71, -0.56, 0.33),
			},
		},
		Kit.happyEyes(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.115 * K, (0.1305 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = {
		Leaf = { pivot = at(0.006, 0.355, 0), axis = "Z", amp = 1.2, sign = -1, flap = { deg = 15 } },
	},
	-- The design's CATALOG2 squeeze (depth 0.6, widen 0.72, kRel 30, cRel 8.5, pitch 1.05) and flight (wobble).
	motion = {
		squeeze = { depth = 0.6, widen = 0.72, kRel = 30, cRel = 8.5, pitch = 1.05 },
		feel = "foam",
		flight = { style = "wobble" },
	},
}

return blueprint
