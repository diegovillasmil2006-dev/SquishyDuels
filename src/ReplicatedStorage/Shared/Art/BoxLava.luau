--!strict
-- BoxLava (shared, data). The Lava Box's Cocoa Volcano for the box reveal (Claude Design BOXES zip 2026-11-10, sd/boxes.js
-- LavaBox, BOXES3 lava): the design's own meshes, imported from Blender into ReplicatedStorage.SD_Models.box_lava (Base =
-- the cake volcano, the cocoa rocks, the mini marshmallows, the face and the shine; Glow = the lava drips and the inner
-- glow; Lid = the toasted-marshmallow plug; LidGlow = its three flames; BaseOutline and LidOutline = the ink outlines as
-- shells). 1 unit = 1 stud, the design's size (its model scale included), the front +Z like the other blueprints, every
-- colour stored in the meshes (White keeps them). Sizes and centres: the Blender manifest (box_lava.json).
-- The lid turns about its own centre (the lid group): the reveal pops it up and spins it (UI/BoxReveal,
-- Config.Anim.boxReveal.lavaLid).

local v = Vector3.new
local HINGE_Y = 1.2164 -- the lid group's height (design metres / 0.28, the model scale included)

return table.freeze({
	kind = "lava",
	meshModel = "box_lava",
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
			size = v(3.3329, 1.3763, 3.0898),
			pos = v(0.0349, 0.6702, -0.0478),
			color = "White",
		},
		{
			name = "BaseOutline",
			node = "base",
			shape = "Mesh",
			size = v(3.4033, 1.4835, 3.1623),
			pos = v(0.0337, 0.6873, -0.0478),
			color = "White",
		},
		{
			name = "Glow",
			node = "base",
			shape = "Mesh",
			size = v(2.4598, 1.0173, 2.335),
			pos = v(-0.0892, 0.8864, -0.1684),
			color = "White",
		},
		{
			name = "Lid",
			node = "lid",
			shape = "Mesh",
			size = v(0.9471, 0.5014, 0.9471),
			pos = v(0, 1.4207 - HINGE_Y, 0),
			color = "White",
		},
		{
			name = "LidGlow",
			node = "lid",
			shape = "Mesh",
			size = v(1.3016, 0.8909, 0.5833),
			pos = v(0, 2.0264 - HINGE_Y, 0.0112),
			color = "White",
		},
		{
			name = "LidOutline",
			node = "lid",
			shape = "Mesh",
			size = v(1.3748, 1.3751, 1.0205),
			pos = v(0, 1.8209 - HINGE_Y, 0),
			color = "White",
		},
	},
	top = HINGE_Y, -- the seam: the inner light, the sparkles and the burst rise from it
	light = "BoxLavaLight",
	beam = "BoxLavaLight",
	-- open.burst (BOXES3 lava): embers, cream cubes, chocolate drops
	sparkles = { "BoxLavaEmber", "StickerBoxLavaEnd", "BoxLavaCream", "BoxLavaToast", "BoxLavaChoco" },
})
