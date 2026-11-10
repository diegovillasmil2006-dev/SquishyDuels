--!strict
-- BoxPrism (shared, data). The Prism Box's Star Jar for the box reveal (Claude Design BOXES zip 2026-11-10, sd/boxes.js
-- PrismBox, BOXES3 prism): the design's own meshes, imported from Blender into ReplicatedStorage.SD_Models.box_prism (Base =
-- the star-shaped jar, the rainbow belt, the crystal clusters, the face and the shine; Glow = the inner glow; Lid = the
-- star cap with its rainbow-arch handle, cloud puffs and gold star; BaseOutline and LidOutline = the ink outlines as
-- shells). 1 unit = 1 stud, the design's size (its model scale included), the front +Z like the other blueprints, every
-- colour stored in the meshes (White keeps them). Sizes and centres: the Blender manifest (box_prism.json).
-- The lid turns about its own centre (the lid group): the reveal pops it up and spins it (UI/BoxReveal,
-- Config.Anim.boxReveal.prismLid).

local v = Vector3.new
local HINGE_Y = 1.4393 -- the lid group's height (design metres / 0.28, the model scale included)

return table.freeze({
	kind = "prism",
	meshModel = "box_prism",
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
			size = v(2.8196, 1.5893, 2.719),
			pos = v(0, 0.691, 0.1425),
			color = "White",
		},
		{
			name = "BaseOutline",
			node = "base",
			shape = "Mesh",
			size = v(2.884, 1.6527, 2.7575),
			pos = v(0, 0.6918, 0.1301),
			color = "White",
		},
		{
			name = "Glow",
			node = "base",
			shape = "Mesh",
			size = v(2.3362, 0.0557, 2.2316),
			pos = v(0, 1.4857, 0.1076),
			color = "White",
		},
		{
			name = "Lid",
			node = "lid",
			shape = "Mesh",
			size = v(2.944, 1.2838, 2.8124),
			pos = v(0, 2.0812 - HINGE_Y, 0.1352),
			color = "White",
		},
		{
			name = "LidOutline",
			node = "lid",
			shape = "Mesh",
			size = v(3.0085, 1.3485, 2.8766),
			pos = v(0, 2.0811 - HINGE_Y, 0.1355),
			color = "White",
		},
	},
	top = HINGE_Y, -- the seam: the inner light, the sparkles and the burst rise from it
	light = "BoxPrismLight",
	beam = "BoxPrismLight",
	-- open.burst (BOXES3 prism): rainbow stars, white and gold sparks, mint and sky spheres
	sparkles = { "BoxPrismPink", "BoxPrismYellow", "BoxPrismMint", "BoxPrismSky", "StickerBoxPrismEnd", "BoxPrismGold" },
})
