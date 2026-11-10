--!strict
-- BoxFrosty (shared, data). The Frosty Box's Sundae Igloo for the box reveal (Claude Design BOXES zip 2026-11-10,
-- `boxes:n` = its sd/boxes.js line n: FrostyBox boxes:130-157, BOXES3 frosty boxes:266): the design's own meshes,
-- imported from Blender into ReplicatedStorage.SD_Models.box_frosty (Base = the igloo, the snow, the face and the
-- shine; Glow = the inner glow; Lid = the mint scoop, its sprinkles, the cherry, the stem and the wafer; BaseOutline and
-- LidOutline = the design's ink outlines as shells). 1 unit = 1 stud, the design's size (its model scale 1.3 included),
-- the front +Z like the other blueprints. Sizes and centres: the Blender manifest (box_frosty.json).
-- The lid turns about its own centre (boxes:143: the lid group at y .226 m x 1.3): the reveal pops it up and spins it
-- (UI/BoxReveal, Config.Anim.boxReveal.frostyLid) instead of swinging it on a back hinge.

local v = Vector3.new
local HINGE_Y = 1.0493 -- boxes:143: 0.226 m x 1.3 / 0.28

return table.freeze({
	kind = "frosty",
	meshModel = "box_frosty",
	nodes = {
		base = { pos = v(0, 0, 0) },
		hinge = { pos = v(0, HINGE_Y, 0) },
		lid = { parent = "hinge", pos = v(0, 0, 0) },
	},
	order = { "base", "hinge", "lid" },
	parts = {
		{ name = "Base", node = "base", shape = "Mesh", size = v(3.764, 1.1891, 3.2329), pos = v(0.0331, 0.5566, 0), color = "White" },
		{
			name = "BaseOutline",
			node = "base",
			shape = "Mesh",
			size = v(3.8464, 1.2718, 3.3142),
			pos = v(0.0331, 0.5567, 0),
			color = "White",
		},
		{
			name = "Glow",
			node = "base",
			shape = "Mesh",
			size = v(1.5786, 0.0557, 1.5786),
			pos = v(0, 1.0957, 0),
			color = "BoxFrostyLight",
			material = "Neon",
		},
		{
			name = "Lid",
			node = "lid",
			shape = "Mesh",
			size = v(2.5244, 1.7213, 2.5478),
			pos = v(0.0239, 1.5864 - HINGE_Y, 0),
			color = "White",
		},
		{
			name = "LidOutline",
			node = "lid",
			shape = "Mesh",
			size = v(2.6058, 1.8003, 2.6287),
			pos = v(0.0237, 1.5868 - HINGE_Y, 0.0002),
			color = "White",
		},
	},
	top = HINGE_Y, -- the seam: the inner light, the sparkles and the burst rise from it
	light = "BoxFrostyLight",
	beam = "BoxFrostyBeam",
	-- open.burst (boxes:266): snowballs, ice cubes, sprinkle capsules
	sparkles = { "White", "BoxFrostyIce", "BoxFrostyMint", "BoxFrostySprinkle", "BoxFrostyLemon" },
})
