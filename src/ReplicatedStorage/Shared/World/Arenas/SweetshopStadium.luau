--!strict
-- SweetshopStadium: the cover of Sweetshop Stadium, the "Bakery sports court - wafer walls, layer cake, marshmallows"
-- (design sd/arena.js, facts sd/main.js:438), for the arena registry (World/Arenas). Data only.
-- 1v1 set (phase 4 spec §4.3, D3): 4 Wafer Walls and 2 Marshmallows per side, listed for Side B by their design
-- position (the mint team A, x < 0); World/Arenas maps them and point-reflects Side A. Dropped (spec §4.3): the Layer
-- Cake (on the pad-to-pad lane: the builder stands it behind each end, D1) and the centre Marshmallow (lane axis).
-- Recipes (spec §4.4) keep the design's sizes except the named R1/R2 rules; colours are Art/Palette tokens.

local Recipe = require(script.Parent.Recipe)

local block = Recipe.block

-- Wafer Wall (sd/arena.js:56-62; proxy 12 x 7 x 3, "full cover"): five layers stacked from the floor, wafer
-- rb(len, h, 3) and cream rb(len - 0.4, h + 0.1, 2.6), 10 grooves rb(0.35, 6.4, 0.25) at x = 2.3i, y 3.5, z +-1.5.
-- R1: height 7 -> 8, every vertical size x 8/7. R2: length 12 -> 8 (the cream keeps its 0.4 inset); 3 grooves per face
-- at the design's 2.3 spacing (x 0, +-2.3) fit the shorter wall (the design's +-4.6 ones fall outside it).
local K = 8 / 7 -- R1
local WAFER_LENGTH = 8 -- R2 (design 12, sd/arena.js:56)
local WAFER_DEPTH = 3 -- design: sd/arena.js:59
local CREAM_INSET = 0.4 -- design: sd/arena.js:59 (len - 0.4)
local CREAM_DEPTH = 2.6 -- design: sd/arena.js:59
local CREAM_EXTRA = 0.1 -- design: sd/arena.js:59 (h + 0.1)
local LAYERS = { 2.2, 0.5, 1.8, 0.5, 2.0 } -- design: sd/arena.js:59 (wafer, cream, wafer, cream, wafer)
local GROOVE = Vector3.new(0.35, 6.4 * K, 0.25) -- design: sd/arena.js:60 rb(0.35, 6.4, 0.25), R1
local GROOVE_Y = 3.5 * K -- design: sd/arena.js:60, R1
local GROOVE_PITCH = 2.3 -- design: sd/arena.js:60 (x = i * 2.3)
local GROOVE_Z = 1.5 -- design: sd/arena.js:60 (fz * 1.5)

local function wafer(): { Recipe.Part }
	local parts: { Recipe.Part } = {}
	local y = 0
	local creams, wafers = 0, 0
	for index, height in LAYERS do
		local isWafer = index % 2 == 1
		local name: string
		if isWafer then
			wafers += 1
			name = if wafers == 1 then "Body" else `Wafer{wafers}`
		else
			creams += 1
			name = `Cream{creams}`
		end
		local centre = (y + height / 2) * K
		if isWafer then
			table.insert(
				parts,
				block(name, Vector3.new(WAFER_LENGTH, height * K, WAFER_DEPTH), 0, centre, 0, "ArenaWafer")
			)
		else
			local size = Vector3.new(WAFER_LENGTH - CREAM_INSET, (height + CREAM_EXTRA) * K, CREAM_DEPTH)
			table.insert(parts, block(name, size, 0, centre, 0, "ArenaWaferCream"))
		end
		y += height
	end
	local groove = 0
	for _, side in { -1, 1 } do
		for step = -1, 1 do
			groove += 1
			table.insert(
				parts,
				block(`Groove{groove}`, GROOVE, step * GROOVE_PITCH, GROOVE_Y, side * GROOVE_Z, "ArenaWaferGroove")
			)
		end
	end
	return parts
end

-- Marshmallow (sd/arena.js:80-85; "half cover", blocks the lower body only): a 6 x 3.5 superellipsoid -> an upright
-- cylinder of the same size; its band (torus r 3.02, tube 0.35, at mid height) -> a disc of the torus' outer size.
local MALLOW_DIAMETER = 6 -- design: sd/arena.js:82 superF(3, 1.75, 3)
local MALLOW_HEIGHT = 3.5 -- design: sd/arena.js:82
local BAND_DIAMETER = 2 * (3.02 + 0.35) -- design: sd/arena.js:83 torus r 3.02, tube 0.35
local BAND_HEIGHT = 2 * 0.35 -- design: sd/arena.js:83 (tube diameter)

local MALLOW: { Recipe.Part } = {
	Recipe.disc("Body", MALLOW_DIAMETER, MALLOW_HEIGHT, 0, MALLOW_HEIGHT / 2, 0, "ArenaMarshmallow"),
	Recipe.disc("Band", BAND_DIAMETER, BAND_HEIGHT, 0, MALLOW_HEIGHT / 2, 0, "ArenaLilac"),
}

local WAFER = wafer()
local HALF_PI = math.pi / 2

return {
	id = "sweetshop_stadium",
	templateName = "Arena_SweetshopStadium",
	generatorId = "arena_sweetshop_stadium",
	design = { file = "sd/arena.js", L = 180, W = 130 } :: Recipe.Design, -- design: sd/arena.js:10
	swapA = {} :: { [string]: string },
	-- Side B, by design position (x, z, ry) of the mint team (sd/arena.js:86-92 with sx = -1).
	cover = {
		{
			name = "WaferBack1",
			kind = "full",
			source = "sd/arena.js:88",
			x = -64,
			z = -32,
			ry = HALF_PI,
			parts = WAFER,
		},
		{ name = "WaferBack2", kind = "full", source = "sd/arena.js:88", x = -64, z = 32, ry = HALF_PI, parts = WAFER },
		{
			name = "WaferFwd1",
			kind = "full",
			source = "sd/arena.js:89",
			x = -30,
			z = -20,
			ry = HALF_PI - 0.35,
			parts = WAFER,
		},
		{
			name = "WaferFwd2",
			kind = "full",
			source = "sd/arena.js:89",
			x = -30,
			z = 20,
			ry = HALF_PI + 0.35,
			parts = WAFER,
		},
		{ name = "Mallow1", kind = "low", source = "sd/arena.js:91", x = -42, z = -50, ry = 0, parts = MALLOW },
		{ name = "Mallow2", kind = "low", source = "sd/arena.js:91", x = -42, z = 50, ry = 0, parts = MALLOW },
	},
}
