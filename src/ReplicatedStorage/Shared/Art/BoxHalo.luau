--!strict
-- BoxHalo (shared, data). The Halo Box's Heavenly Bun Shrine for the box reveal (Claude Design BOXES zip 2026-11-10,
-- sd/boxes.js HaloBox, BOXES3 halo): the design's own meshes, imported from Blender into ReplicatedStorage.SD_Models.box_halo
-- (Base = the golden brioche bun on its cloud, the pearl trim, the big feather wings, the face and the shine; Glow = the
-- inner glow; Lid = the bun-top lid with its brioche knot, pearl seeds, gold rim and the floating winged halo;
-- BaseOutline and LidOutline = the ink outlines as shells). 1 unit = 1 stud, the design's size (its model scale
-- included), the front +Z like the other blueprints, every colour stored in the meshes (White keeps them). Sizes and
-- centres: the Blender manifest (box_halo.json).
-- The lid turns about its own centre (the lid group): the reveal pops it up and spins it (UI/BoxReveal,
-- Config.Anim.boxReveal.haloLid).

local v = Vector3.new
local HINGE_Y = 0.8571 -- the lid group's height (design metres / 0.28, the model scale included)

return table.freeze({
	kind = "halo",
	meshModel = "box_halo",
	nodes = {
		base = { pos = v(0, 0, 0) },
		hinge = { pos = v(0, HINGE_Y, 0) },
		lid = { parent = "hinge", pos = v(0, 0, 0) },
	},
	order = { "base", "hinge", "lid" },
	parts = {
		{
			name = "Base",
			node = "base",
			shape = "Mesh",
			size = v(3.8076, 1.3167, 2.6842),
			pos = v(-0.0004, 0.6569, 0.024),
			color = "White",
		},
		{
			name = "BaseOutline",
			node = "base",
			shape = "Mesh",
			size = v(3.8846, 1.4016, 2.7668),
			pos = v(-0.0001, 0.6568, 0.0239),
			color = "White",
		},
		{
			name = "Glow",
			node = "base",
			shape = "Mesh",
			size = v(1.6964, 0.0536, 1.6964),
			pos = v(0, 0.8929, 0),
			color = "White",
		},
		{
			name = "Lid",
			node = "lid",
			shape = "Mesh",
			size = v(2.3661, 1.8071, 2.3661),
			pos = v(0, 1.7294 - HINGE_Y, 0),
			color = "White",
		},
		{
			name = "LidOutline",
			node = "lid",
			shape = "Mesh",
			size = v(2.4511, 1.8918, 2.4511),
			pos = v(0, 1.7293 - HINGE_Y, 0),
			color = "White",
		},
	},
	top = HINGE_Y, -- the seam: the inner light, the sparkles and the burst rise from it
	light = "BoxHaloLight",
	beam = "BoxHaloLight",
	-- open.burst (BOXES3 halo): white feather petals, gold and white sparks, gold coins
	sparkles = { "White", "BoxHaloCream", "BoxHaloGold", "BoxHaloCoin" },
})
