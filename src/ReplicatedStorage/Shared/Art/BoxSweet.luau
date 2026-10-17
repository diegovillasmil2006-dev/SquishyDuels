--!strict
-- BoxSweet (shared, data). UI FINAL R7 (G7.9): the Sweet box of Diego's box stage, buildSweet (uploads/box-stage.html
-- stage:128-156), in the design's units for Art/BoxBuilder: the striped drum (stage:130: r 1.1 -> 1.02, 1.3 high,
-- 24 stripes #FFB8DA / #D7B4FF: 8 a tile, repeat 3), the mint band (stage:131), the cream rim and its 12 drips
-- (stage:132-137), the dome lid on its centre hinge (stage:138-140), the 90 sprinkles (stage:141-149) and the cherry
-- (stage:150-154).
-- Nearest primitives (Roblox limits, stated): the drum is 24 upright staves round a core (no taper, no white stripe
-- lines); the tori are flat cylinders; the capsules are ellipsoids; the stem's tube is two thin cylinders; the
-- sprinkles sit where a fixed seed puts them (the design's are random each open).

local v = Vector3.new
local STRIPES = 24
local STAVE_RADIUS = 1.06 -- the drum's mean radius (1.1 top, 1.02 bottom)
local SPRINKLES = 90
local SPRINKLE_SEED = 90
local SPRINKLE_COLORS =
	{ "StickerCoinText", "BoxSoftEar", "White", "BoxSprinkleGreen", "BoxSprinklePurple", "BoxSprinkleRed" }

local parts: { any } = {
	{
		name = "Core",
		node = "base",
		shape = "Cylinder",
		size = v(2.04, 1.3, 2.04),
		pos = v(0, 0.65, 0),
		color = "BoxSweetStripeB",
	},
	{
		name = "Band",
		node = "base",
		shape = "Cylinder",
		size = v(2.28, 0.2, 2.28),
		pos = v(0, 0.08, 0),
		color = "BoxSweetBand",
	},
	{
		name = "Rim",
		node = "base",
		shape = "Cylinder",
		size = v(2.54, 0.34, 2.54),
		pos = v(0, 1.3, 0),
		color = "BoxSweetCream",
	},
	-- stage:139-140: the dome (a half sphere r 1.16 scaled .58 high; its lower half stays inside the drum) and its cream
	{ name = "Dome", node = "lid", shape = "Ellipsoid", size = v(2.32, 1.3456, 2.32), color = "BoxSweetDome" },
	{
		name = "LidCream",
		node = "lid",
		shape = "Cylinder",
		size = v(2.48, 0.24, 2.48),
		pos = v(0, 0.02, 0),
		color = "BoxSweetCream",
	},
	-- stage:150-154: the cherry, its stem along the curve (0,.42) -> (.05,.7) -> (.25,.82) and its shine
	{
		name = "Cherry",
		node = "cherry",
		shape = "Ball",
		size = v(0.52, 0.52, 0.52),
		pos = v(0, 0.22, 0),
		color = "BoxSweetCherry",
	},
	{
		name = "StemLow",
		node = "cherry",
		shape = "Cylinder",
		size = v(0.07, 0.27, 0.07),
		pos = v(0.035, 0.55, 0),
		rot = v(0, 0, -0.263),
		color = "BoxSweetStem",
	},
	{
		name = "StemHigh",
		node = "cherry",
		shape = "Cylinder",
		size = v(0.07, 0.23, 0.07),
		pos = v(0.16, 0.75, 0),
		rot = v(0, 0, -0.91),
		color = "BoxSweetStem",
	},
	{
		name = "Shine",
		node = "cherry",
		shape = "Ball",
		size = v(0.1, 0.1, 0.1),
		pos = v(-0.09, 0.32, 0.18),
		color = "White",
	},
}

-- stage:62-65: the stripes, alternating, facing out.
local staveWidth = 2 * math.pi * STAVE_RADIUS / STRIPES + 0.01
for i = 0, STRIPES - 1 do
	local a = (i + 0.5) / STRIPES * 2 * math.pi
	table.insert(parts, {
		name = `Stripe{i + 1}`,
		node = "base",
		shape = "Block",
		size = v(staveWidth, 1.3, 0.08),
		pos = v(math.sin(a) * STAVE_RADIUS, 0.65, math.cos(a) * STAVE_RADIUS),
		rot = v(0, a, 0),
		color = if i % 2 == 0 then "BoxSweetStripeB" else "BoxSweetStripeA",
	})
end

-- stage:134-137: the 12 drips under the rim (capsules r .075, length L).
for i = 0, 11 do
	local a = (i / 12) * math.pi * 2 + 0.2
	local length = 0.18 + ((i * 37) % 7) * 0.05
	table.insert(parts, {
		name = `Drip{i + 1}`,
		node = "base",
		shape = "Ellipsoid",
		size = v(0.15, length + 0.15, 0.15),
		pos = v(math.cos(a) * 1.12, 1.24 - length / 2, math.sin(a) * 1.12),
		rot = v(0, -a, 0),
		color = "BoxSweetCream",
	})
end

-- stage:141-148: the sprinkles on the dome (capsules r .028, .11 long), each along its own tangent.
local rng = Random.new(SPRINKLE_SEED)
for i = 0, SPRINKLES - 1 do
	local u = rng:NextNumber() * math.pi * 2
	local w = math.acos(1 - rng:NextNumber() * 0.92)
	local n = v(math.sin(w) * math.cos(u), math.cos(w), math.sin(w) * math.sin(u))
	local p = v(n.X * 1.17, n.Y * 1.17 * 0.58, n.Z * 1.17)
	local along = v(math.cos(i), 0, math.sin(i)):Cross(n)
	along = if along.Magnitude > 1e-6 then along.Unit else v(1, 0, 0)
	local rx, ry, rz = CFrame.fromMatrix(Vector3.zero, n:Cross(along).Unit, along):ToEulerAnglesXYZ()
	table.insert(parts, {
		name = `Sprinkle{i + 1}`,
		node = "lid",
		shape = "Ellipsoid",
		size = v(0.056, 0.166, 0.056),
		pos = p,
		rot = v(rx, ry, rz),
		color = SPRINKLE_COLORS[i % #SPRINKLE_COLORS + 1],
	})
end

return table.freeze({
	kind = "sweet",
	nodes = {
		base = { pos = v(0, 0, 0) },
		hinge = { pos = v(0, 1.3, 0) }, -- stage:138: the dome rocks about its centre (and rises, stage:335)
		lid = { parent = "hinge", pos = v(0, 0, 0) },
		cherry = { parent = "lid", pos = v(0, 0.72, 0) }, -- stage:150
	},
	order = { "base", "hinge", "lid", "cherry" },
	parts = parts,
	top = 1.3, -- stage:155
	light = "BoxSweetLight",
	beam = "BoxSweetBeam",
	sparkles = SPRINKLE_COLORS,
})
