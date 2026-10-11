--!strict
-- PillowFortPark: the cover of Pillow Fort Park, the "Plush playroom - quilted court, pillow walls, blanket fort,
-- giant sofa" (design sd/arenas2.js:45-114, facts sd/main.js:445-448), for the arena registry (World/Arenas). Data
-- only.
-- 1v1 set (phase 4 spec §4.3, D3): the 2 forward and 2 back Pillow Walls and 2 Plush Blocks per side, listed for
-- Side B by their design position (the mint team A, x < 0); World/Arenas maps them and point-reflects Side A (whose
-- pillow tops take the strawberry print, swapA). Dropped (spec §4.3): the Pillow Fort (lane axis and pad: the builder
-- stands it behind each end, D1), the 3 Beanbags (on or across the lane), the flank walls and the far Plush Blocks.
-- The builder adds the Plush Blocks' star and heart patches.

local Recipe = require(script.Parent.Recipe)

local block, ball = Recipe.block, Recipe.ball

-- Pillow Wall (sd/arenas2.js:61-66; proxy 13 x 7 x 4.8, "full"): bottom pill(13, 3.9, 4.8) at y 1.95; top
-- pill(12.4, 3.7, 4.5) at (0.3, 5.2) (top 7.05); corner nubs pill(1.8, 1.4, 2.4) at the layer ends (x +-6.3 / 0.3 +-6);
-- buttons SPH(0.42) at z +-2.3 on both layers. R1: height 7.05 -> 8, every vertical size x 8/7.05. R2: length with
-- the nubs 14.4 -> 8 (spec §4.4: pillows 6.4 / 6.1 long, nubs Ø1.6 balls centred on the pillow ends). The design's
-- 0.03 tilt of the top pillow is dropped (spec §4.4). Rounded pills become blocks and balls (R4).
local K = 8 / 7.05 -- R1
local BOTTOM = Vector3.new(6.4, 3.9 * K, 4.8) -- spec §4.4; design: sd/arenas2.js:63 pill(13, 3.9, 4.8)
local BOTTOM_Y = 1.95 * K -- design: sd/arenas2.js:63
local TOP = Vector3.new(6.1, 3.7 * K, 4.5) -- spec §4.4; design: sd/arenas2.js:63 pill(12.4, 3.7, 4.5)
local TOP_X = 0.15 -- design: sd/arenas2.js:63 (x 0.3, halved with the length, spec §4.4)
local TOP_Y = 5.2 * K -- design: sd/arenas2.js:63
local NUB = 1.6 -- spec §4.4 (design pill(1.8, 1.4, 2.4), sd/arenas2.js:64)
local BOTTOM_NUB_X = 3.2 -- spec §4.4 (design +-6.3, sd/arenas2.js:64)
local TOP_NUB_X = 3.05 -- spec §4.4 (design 0.3 +- 6, sd/arenas2.js:64)
local BUTTON = 2 * 0.42 -- design: sd/arenas2.js:64 SPH(0.42)
local BUTTON_Z = 2.3 -- design: sd/arenas2.js:64

local function pillowWall(): { Recipe.Part }
	return {
		block("Body", BOTTOM, 0, BOTTOM_Y, 0, "ArenaCushionCream", "Fabric"),
		block("Top", TOP, TOP_X, TOP_Y, 0, "ArenaPillowMintPrint", "Fabric"),
		ball("Nub1", NUB, -BOTTOM_NUB_X, BOTTOM_Y, 0, "ArenaCushionCream", "Fabric"),
		ball("Nub2", NUB, BOTTOM_NUB_X, BOTTOM_Y, 0, "ArenaCushionCream", "Fabric"),
		ball("Nub3", NUB, TOP_X - TOP_NUB_X, TOP_Y, 0, "ArenaCushionCream", "Fabric"),
		ball("Nub4", NUB, TOP_X + TOP_NUB_X, TOP_Y, 0, "ArenaCushionCream", "Fabric"),
		ball("Button1", BUTTON, 0, BOTTOM_Y, -BUTTON_Z, "ArenaTrimWhite"),
		ball("Button2", BUTTON, 0, BOTTOM_Y, BUTTON_Z, "ArenaTrimWhite"),
		ball("Button3", BUTTON, TOP_X, TOP_Y, -BUTTON_Z, "ArenaTrimWhite"),
		ball("Button4", BUTTON, TOP_X, TOP_Y, BUTTON_Z, "ArenaTrimWhite"),
	}
end

-- Plush Block (sd/arenas2.js:80; "half cover"): rb(4.4) cube at y 2.2, design size (spec §4.4); its star and heart
-- patches are SurfaceGui glyphs the builder adds.
local PLUSH = 4.4 -- design: sd/arenas2.js:80 rb(4.4, 4.4, 4.4)

local function plush(color: string): { Recipe.Part }
	return { block("Body", Vector3.one * PLUSH, 0, PLUSH / 2, 0, color, "Fabric") }
end

local PILLOW_WALL = pillowWall()
local HALF_PI = math.pi / 2

return {
	id = "pillow_fort_park",
	templateName = "Arena_PillowFortPark",
	generatorId = "arena_pillow_fort_park",
	design = { file = "sd/arenas2.js", L = 176, W = 128 } :: Recipe.Design, -- design: sd/arenas2.js:8
	-- Side A (the design's strawberry team B) wears the strawberry print (sd/arenas2.js:62 pm = team < 0 ? pA : pB).
	swapA = { ArenaPillowMintPrint = "ArenaPillowStrawberryPrint" } :: { [string]: string },
	-- Side B, by design position (x, z, ry) of the mint team (sd/arenas2.js:81-89 with sx = -1).
	cover = {
		{
			name = "PillowFwd1",
			kind = "full",
			source = "sd/arenas2.js:84",
			x = -26,
			z = -24,
			ry = -0.46,
			parts = PILLOW_WALL,
		},
		{
			name = "PillowFwd2",
			kind = "full",
			source = "sd/arenas2.js:84",
			x = -26,
			z = 24,
			ry = 0.46,
			parts = PILLOW_WALL,
		},
		{
			name = "PillowBack1",
			kind = "full",
			source = "sd/arenas2.js:86",
			x = -70,
			z = -30,
			ry = HALF_PI,
			parts = PILLOW_WALL,
		},
		{
			name = "PillowBack2",
			kind = "full",
			source = "sd/arenas2.js:86",
			x = -70,
			z = 30,
			ry = HALF_PI,
			parts = PILLOW_WALL,
		},
		-- design: sd/arenas2.js:88 plush_block_S (violet, ry 0.3, star in front) and _N (sky, ry -0.3, heart in front)
		{
			name = "Plush1",
			kind = "low",
			source = "sd/arenas2.js:88",
			x = -52,
			z = -18,
			ry = 0.3,
			parts = plush("ArenaViolet"),
		},
		{
			name = "Plush2",
			kind = "low",
			source = "sd/arenas2.js:88",
			x = -52,
			z = 18,
			ry = -0.3,
			parts = plush("ArenaSky"),
		},
	},
}
