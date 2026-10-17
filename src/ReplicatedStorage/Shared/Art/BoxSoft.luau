--!strict
-- BoxSoft (shared, data). UI FINAL R7 (G7.9): the Soft box (our Snack Box) of Diego's box stage, buildSoft
-- (uploads/box-stage.html stage:101-127), in the design's units for Art/BoxBuilder: the white polka cube (stage:104:
-- 2 x 1.5 x 2 at y .75) with its pink satin ribbons (stage:105-107), the face (stage:108-113), the lid on its hinge at
-- the back (stage:114-117), the two cat ears (stage:118-124) and the bow (stage:88-98, 125).
-- Nearest primitives (Roblox limits, stated): rounded boxes are blocks; the polka texture is the gradient's top
-- colour with the 4 visible big dots of each face as white discs (the small .35 dots and the ink hulls are not
-- drawn); the eye and mouth arcs are flat ink ellipsoids; the cones are Tri prisms; the bow's tori are ellipsoids.

local v = Vector3.new
local DOT = v(0.23, 0.23, 0.04) -- stage:59: r 22 of a 256 px tile, repeat 1.5 on a 2-unit face
local DOT_ALPHA = 0.1 -- rgba(255,255,255,.9)

local parts: { any } = {
	{ name = "Body", node = "base", shape = "Block", size = v(2, 1.5, 2), pos = v(0, 0.75, 0), color = "BoxSoftPolka" },
	{
		name = "RibbonX",
		node = "base",
		shape = "Block",
		size = v(2.04, 1.52, 0.36),
		pos = v(0, 0.75, 0),
		color = "BoxSoftRibbon",
	},
	{
		name = "RibbonZ",
		node = "base",
		shape = "Block",
		size = v(0.36, 1.52, 2.04),
		pos = v(0, 0.75, 0),
		color = "BoxSoftRibbon",
	},
	-- stage:108-113: the face at (0, .72, 1.02): the closed eyes, the smile, the blush (opacity .8)
	{
		name = "EyeL",
		node = "face",
		shape = "Ellipsoid",
		size = v(0.31, 0.07, 0.04),
		pos = v(-0.5, 0.05, 0),
		color = "StickerInk",
	},
	{
		name = "EyeR",
		node = "face",
		shape = "Ellipsoid",
		size = v(0.31, 0.07, 0.04),
		pos = v(0.5, 0.05, 0),
		color = "StickerInk",
	},
	{
		name = "Mouth",
		node = "face",
		shape = "Ellipsoid",
		size = v(0.22, 0.06, 0.04),
		pos = v(0, -0.12, 0),
		color = "StickerInk",
	},
	{
		name = "BlushL",
		node = "face",
		shape = "Ellipsoid",
		size = v(0.31, 0.19, 0.02),
		pos = v(-0.62, -0.12, 0),
		color = "BoxSoftBlush",
		transparency = 0.2,
	},
	{
		name = "BlushR",
		node = "face",
		shape = "Ellipsoid",
		size = v(0.31, 0.19, 0.02),
		pos = v(0.62, -0.12, 0),
		color = "BoxSoftBlush",
		transparency = 0.2,
	},
	-- stage:114-117: the lid (its frame is the hinge's, at the lid's centre)
	{
		name = "LidBody",
		node = "lid",
		shape = "Block",
		size = v(2.22, 0.5, 2.22),
		pos = v(0, 0.22, 0),
		color = "BoxSoftPolka",
	},
	{
		name = "LidRibbonX",
		node = "lid",
		shape = "Block",
		size = v(2.26, 0.52, 0.38),
		pos = v(0, 0.22, 0),
		color = "BoxSoftRibbon",
	},
	{
		name = "LidRibbonZ",
		node = "lid",
		shape = "Block",
		size = v(0.38, 0.52, 2.26),
		pos = v(0, 0.22, 0),
		color = "BoxSoftRibbon",
	},
	-- stage:120-122: each ear a cone (r .3, h .5) with its pink inner cone in front
	{ name = "EarL", node = "earL", shape = "Tri", size = v(0.6, 0.5, 0.3), pos = v(0, 0.25, 0), color = "BoxSoftEar" },
	{
		name = "EarInnerL",
		node = "earL",
		shape = "Tri",
		size = v(0.34, 0.32, 0.1),
		pos = v(0, 0.22, 0.12),
		rot = v(0.18, 0, 0),
		color = "BoxSoftEarInner",
	},
	{ name = "EarR", node = "earR", shape = "Tri", size = v(0.6, 0.5, 0.3), pos = v(0, 0.25, 0), color = "BoxSoftEar" },
	{
		name = "EarInnerR",
		node = "earR",
		shape = "Tri",
		size = v(0.34, 0.32, 0.1),
		pos = v(0, 0.22, 0.12),
		rot = v(0.18, 0, 0),
		color = "BoxSoftEarInner",
	},
	-- stage:88-98: the bow (loops r .34 tube .12 scaled (1, .75, 1), tails, knot)
	{
		name = "LoopL",
		node = "bow",
		shape = "Ellipsoid",
		size = v(0.92, 0.69, 0.24),
		pos = v(-0.36, 0.22, 0),
		rot = v(0, 0.35, 0.55),
		color = "BoxSoftRibbon",
	},
	{
		name = "LoopR",
		node = "bow",
		shape = "Ellipsoid",
		size = v(0.92, 0.69, 0.24),
		pos = v(0.36, 0.22, 0),
		rot = v(0, -0.35, -0.55),
		color = "BoxSoftRibbon",
	},
	{
		name = "TailL",
		node = "bow",
		shape = "Block",
		size = v(0.2, 0.62, 0.06),
		pos = v(-0.2, -0.12, 0.28),
		rot = v(0.3, 0, 0.45),
		color = "BoxSoftRibbon",
	},
	{
		name = "TailR",
		node = "bow",
		shape = "Block",
		size = v(0.2, 0.62, 0.06),
		pos = v(0.2, -0.12, 0.28),
		rot = v(0.3, 0, -0.45),
		color = "BoxSoftRibbon",
	},
	{
		name = "Knot",
		node = "bow",
		shape = "Ellipsoid",
		size = v(0.396, 0.324, 0.36),
		pos = v(0, 0.16, 0),
		color = "BoxSoftRibbon",
	},
}

-- The big dots off the ribbons: four per side face (at +-.667 across, .25 / 1.25 up) and four on the lid's top.
for _, face in { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } } do
	for _, across in { -0.667, 0.667 } do
		for _, up in { 0.25, 1.25 } do
			local nx, nz = face[1], face[2]
			table.insert(parts, {
				name = `Dot{#parts}`,
				node = "base",
				shape = "Ellipsoid",
				size = if nx ~= 0 then v(0.04, DOT.Y, DOT.X) else DOT,
				pos = v(if nx ~= 0 then nx * 1.0 else across, up, if nz ~= 0 then nz * 1.0 else across),
				color = "White",
				transparency = DOT_ALPHA,
			})
		end
	end
end
for _, x in { -0.74, 0.74 } do
	for _, z in { -0.74, 0.74 } do
		table.insert(parts, {
			name = `Dot{#parts}`,
			node = "lid",
			shape = "Ellipsoid",
			size = v(DOT.X, 0.04, DOT.Y),
			pos = v(x, 0.47, z),
			color = "White",
			transparency = DOT_ALPHA,
		})
	end
end

return table.freeze({
	kind = "soft",
	nodes = {
		base = { pos = v(0, 0, 0) },
		face = { parent = "base", pos = v(0, 0.72, 1.02) },
		hinge = { pos = v(0, 1.5, -1.08) }, -- stage:114: the lid turns about the back edge
		lid = { parent = "hinge", pos = v(0, 0, 1.08) },
		earL = { parent = "lid", pos = v(-0.78, 0.45, -0.55), rot = v(0, 0, 0.25) }, -- stage:120: rotation.z = -sx .25
		earR = { parent = "lid", pos = v(0.78, 0.45, -0.55), rot = v(0, 0, -0.25) },
		bow = { parent = "lid", pos = v(0, 0.56, 0) }, -- stage:125
	},
	order = { "base", "face", "hinge", "lid", "earL", "earR", "bow" },
	parts = parts,
	top = 1.5, -- stage:126
	light = "BoxSoftLight",
	beam = "StickerFxIce", -- stage:126: #9EF7FF
	sparkles = { "White", "BoxSoftPart", "BoxSoftPolka", "StickerCoinText" },
})
