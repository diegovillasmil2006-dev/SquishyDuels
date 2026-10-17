--!strict
-- BoxRoyal (shared, data). UI FINAL R7 (G7.9): the Royal box (our Treat Box) of Diego's box stage, buildRoyal
-- (uploads/box-stage.html stage:157-187), in the design's units for Art/BoxBuilder: the velvet chest (stage:160: 2.4 x
-- 1.3 x 1.6) with its gold base, trim, bands, feet and posts (stage:161-165), the front plate, gem and keyhole
-- (stage:166-168), the seam glow (stage:169), the half-round lid on its back hinge (stage:170-173) with its gold rings
-- (stage:174-175) and gems (stage:177), and the turning crown (stage:178-185).
-- Nearest primitives (Roblox limits, stated): the velvet is Fabric (no sheen), the gold plain (no metal in a
-- viewport); the half cylinder is LID_SLATS slats with flat elliptic end caps; each half torus is RING_SEGMENTS
-- blocks; the octahedron gems are blocks turned 45°; the crown's cones are ellipsoids.

local v = Vector3.new
local GOLD = "StickerGoldMid" -- stage:78: #FFC23A
local VELVET = "BoxRoyalVelvet"
local LID_SLATS = 10
local RING_SEGMENTS = 8
local LID_RADIUS = 0.8 -- stage:171
local LID_SQUASH = 0.62 -- stage:172
local GEMS = { "BoxRoyalGemCyan", "BoxRoyalGemPink", "BoxRoyalGemGreen", "BoxRoyalGemYellow" } -- stage:176

local parts: { any } = {
	{
		name = "Velvet",
		node = "base",
		shape = "Block",
		size = v(2.4, 1.3, 1.6),
		pos = v(0, 0.65, 0),
		color = VELVET,
		material = "Fabric",
	},
	{ name = "GoldBase", node = "base", shape = "Block", size = v(2.5, 0.16, 1.7), pos = v(0, 0.08, 0), color = GOLD },
	{ name = "GoldTop", node = "base", shape = "Block", size = v(2.48, 0.12, 1.68), pos = v(0, 1.26, 0), color = GOLD },
	{
		name = "BandL",
		node = "base",
		shape = "Block",
		size = v(0.16, 1.32, 1.66),
		pos = v(-0.85, 0.65, 0),
		color = GOLD,
	},
	{
		name = "BandR",
		node = "base",
		shape = "Block",
		size = v(0.16, 1.32, 1.66),
		pos = v(0.85, 0.65, 0),
		color = GOLD,
	},
	{ name = "Plate", node = "base", shape = "Block", size = v(0.52, 0.62, 0.1), pos = v(0, 0.9, 0.82), color = GOLD },
	{
		name = "Gem",
		node = "base",
		shape = "Block",
		size = v(0.22, 0.22, 0.12),
		pos = v(0, 1.0, 0.9),
		rot = v(0, 0, math.pi / 4),
		color = "BoxRoyalGemPink",
	},
	{
		name = "Keyhole",
		node = "base",
		shape = "Cylinder",
		size = v(0.1, 0.01, 0.1),
		pos = v(0, 0.76, 0.875),
		rot = v(math.pi / 2, 0, 0),
		color = "BoxRoyalKeyhole",
	},
	{
		name = "Seam",
		node = "base",
		shape = "Block",
		size = v(2.34, 0.03, 1.54),
		pos = v(0, 1.31, 0),
		color = "BoxRoyalSeam",
		transparency = 1, -- stage:169: opacity 0 until the idle lights it (stage:311)
	},
	{
		name = "LidFlat",
		node = "lid",
		shape = "Block",
		size = v(2.4, 0.05, 1.6),
		pos = v(0, 0.02, 0),
		color = VELVET,
		material = "Fabric",
	},
	{
		name = "CapL",
		node = "lid",
		shape = "Ellipsoid",
		size = v(0.04, 2 * LID_RADIUS * LID_SQUASH, 2 * LID_RADIUS),
		pos = v(-1.18, 0.02, 0),
		color = VELVET,
		material = "Fabric",
	},
	{
		name = "CapR",
		node = "lid",
		shape = "Ellipsoid",
		size = v(0.04, 2 * LID_RADIUS * LID_SQUASH, 2 * LID_RADIUS),
		pos = v(1.18, 0.02, 0),
		color = VELVET,
		material = "Fabric",
	},
	{
		name = "LidGemL",
		node = "lid",
		shape = "Block",
		size = v(0.18, 0.18, 0.1),
		pos = v(-0.45, 0.52, 0.12),
		rot = v(0, 0.4, math.pi / 4),
		color = GEMS[1],
	},
	{
		name = "LidGemR",
		node = "lid",
		shape = "Block",
		size = v(0.18, 0.18, 0.1),
		pos = v(0.45, 0.52, 0.12),
		rot = v(0, 0.4, math.pi / 4),
		color = GEMS[3],
	},
	{
		name = "CrownBand",
		node = "crown",
		shape = "Cylinder",
		size = v(0.64, 0.22, 0.64),
		pos = v(0, 0.11, 0),
		color = GOLD,
	},
	{
		name = "CrownGem",
		node = "crown",
		shape = "Ball",
		size = v(0.18, 0.18, 0.18),
		pos = v(0, 0.12, 0.33),
		color = GEMS[2],
	},
}

-- stage:164-165: the four feet and corner posts.
for _, x in { -1.2, 1.2 } do
	for _, z in { -0.8, 0.8 } do
		table.insert(parts, {
			name = `Foot{#parts}`,
			node = "base",
			shape = "Ball",
			size = v(0.26, 0.26, 0.26),
			pos = v(x, 0.12, z),
			color = GOLD,
		})
		table.insert(parts, {
			name = `Post{#parts}`,
			node = "base",
			shape = "Block",
			size = v(0.14, 1.28, 0.14),
			pos = v(x, 0.66, z),
			color = GOLD,
		})
	end
end

-- A point of the lid's half ellipse at angle `phi` (0 = the front edge, pi = the back), in the lid's frame.
local function arcPoint(radius: number, phi: number): (number, number)
	return radius * math.cos(phi), 0.02 + radius * LID_SQUASH * math.sin(phi)
end

-- `count` blocks `length` long along X following the half ellipse of `radius`, `thick` deep, at x.
local function arc(
	prefix: string,
	count: number,
	radius: number,
	thick: number,
	length: number,
	x: number,
	color: string,
	material: string?
)
	for k = 1, count do
		local z0, y0 = arcPoint(radius, math.pi * (k - 1) / count)
		local z1, y1 = arcPoint(radius, math.pi * k / count)
		local dz, dy = z1 - z0, y1 - y0
		local chord = math.sqrt(dz * dz + dy * dy)
		table.insert(parts, {
			name = `{prefix}{k}`,
			node = "lid",
			shape = "Block",
			size = v(length, thick, chord + 0.02),
			pos = v(x, (y0 + y1) / 2, (z0 + z1) / 2),
			rot = v(math.atan2(-dy, dz), 0, 0),
			color = color,
			material = material,
		})
	end
end

-- stage:171-172: the lid's half cylinder (r .8, 2.4 long, .62 high).
arc("Slat", LID_SLATS, LID_RADIUS - 0.04, 0.08, 2.4, 0, VELVET, "Fabric")
-- stage:174-175: the three rings (r .82, tube .065) and the two end rings (r .8, tube .07).
for index, x in { -0.85, 0, 0.85 } do
	arc(`Ring{index}_`, RING_SEGMENTS, 0.82, 0.13, 0.13, x, GOLD)
end
for index, x in { -1.21, 1.21 } do
	arc(`EndRing{index}_`, RING_SEGMENTS, 0.8, 0.14, 0.14, x, GOLD)
end

-- stage:180-184: the crown's five points and their gems.
for i = 0, 4 do
	local a = (i / 5) * math.pi * 2
	table.insert(parts, {
		name = `Point{i + 1}`,
		node = "crown",
		shape = "Ellipsoid",
		size = v(0.18, 0.26, 0.18),
		pos = v(math.cos(a) * 0.3, 0.33, math.sin(a) * 0.3),
		color = GOLD,
	})
	table.insert(parts, {
		name = `PointGem{i + 1}`,
		node = "crown",
		shape = "Ball",
		size = v(0.11, 0.11, 0.11),
		pos = v(math.cos(a) * 0.3, 0.48, math.sin(a) * 0.3),
		color = GEMS[i % 4 + 1],
	})
end

return table.freeze({
	kind = "royal",
	nodes = {
		base = { pos = v(0, 0, 0) },
		hinge = { pos = v(0, 1.3, -0.8) }, -- stage:170: the lid turns about the back edge
		lid = { parent = "hinge", pos = v(0, 0, 0.8) },
		crown = { parent = "lid", pos = v(0, 0.5, 0) }, -- stage:178
	},
	order = { "base", "hinge", "lid", "crown" },
	parts = parts,
	top = 1.3, -- stage:186
	light = "BoxRoyalLight",
	beam = "Lemon", -- stage:186: #FFD86B
	sparkles = { "StickerCoinText", "White", "BoxRoyalSheen", "StickerFxIce", "StickerGoldMid" },
})
