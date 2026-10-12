--!strict
-- ArcadeToyworks: the cover of Arcade Toyworks, the "Toy workshop arcade - studded brick walls, cabinets, claw
-- machine" (design sd/arenas2.js:177-259, facts sd/main.js:453-456), for the arena registry (World/Arenas). Data only.
-- 1v1 set (phase 4 spec §4.3, D3): 4 Brick Walls and 2 Arcade Cabinets per side, listed for Side B by their design
-- position (the mint team A, x < 0); World/Arenas maps them and point-reflects Side A. The cabinets reach the
-- pad-to-pad lane and are slid out of it (R5, World/Arenas). Dropped (spec §4.3): the Claw Machine (lane and pad: the
-- builder stands it behind each end, D1), the 4 Toy Blocks (2 on the lane axis; the other 2 fit but the part budget is
-- tightest here, D5). D10: each cabinet pair becomes one cabinet whose screen faces the lane; the builder adds the
-- screen's pixel invader and "PLAY".

local Recipe = require(script.Parent.Recipe)

local block = Recipe.block

-- Brick Wall (sd/arenas2.js:189-195; proxy 12 x 7.5 x 4, "full"): bricks rb(3.9, 2.25, 4) in 3 rows at y 1.15 + 2.3c:
-- rows 0 and 2 at x -4 / 0 / 4, row 1 at x -2 / 2 plus green bricks at x +-6; studs C(0.75) x 0.6 on top (y 7.2).
-- Spec §4.4: bricks x 2/3 wide (2.6) and x 1.11 tall (2.5) so the wall is 8 long; the green end bricks become half
-- bricks (1.3) that keep the stagger inside 8 (D10); 3 studs on the top row (the design's 12 trimmed for the budget,
-- D5); top 8.1 with the studs.
local BRICK = Vector3.new(2.6, 2.5, 4) -- spec §4.4; design: sd/arenas2.js:189 rb(3.9, 2.25, 4)
local HALF_BRICK = Vector3.new(1.3, 2.5, 4) -- spec §4.4 (D10)
local PITCH = 2.67 -- spec §4.4: x -2.67 / 0 / 2.67 (design -4 / 0 / 4, x 2/3)
local ROW_Y = { 1.25, 3.75, 6.25 } -- spec §4.4 (design 1.15 + 2.3c, sd/arenas2.js:192)
local ROW_COLORS = { "ArenaBrickSky", "ArenaButter", "ArenaViolet" } -- design: sd/arenas2.js:191 bS / bY / bL
local STUD_DIAMETER = 2 * 0.75 -- design: sd/arenas2.js:189 C(0.75, 0.75, 0.6)
local STUD_HEIGHT = 0.6 -- design: sd/arenas2.js:189

local function brickWall(): { Recipe.Part }
	local parts: { Recipe.Part } = {
		-- Row 0: the centre brick is the Body.
		block("Body", BRICK, 0, ROW_Y[1], 0, ROW_COLORS[1]),
		block("Brick1_1", BRICK, -PITCH, ROW_Y[1], 0, ROW_COLORS[1]),
		block("Brick1_3", BRICK, PITCH, ROW_Y[1], 0, ROW_COLORS[1]),
		-- Row 1: two bricks offset half a pitch, and the green half bricks at the ends (design x +-6, sd/arenas2.js:193).
		block("Brick2_1", BRICK, -PITCH / 2, ROW_Y[2], 0, ROW_COLORS[2]),
		block("Brick2_2", BRICK, PITCH / 2, ROW_Y[2], 0, ROW_COLORS[2]),
		block("GreenBrick1", HALF_BRICK, -(4 - HALF_BRICK.X / 2), ROW_Y[2], 0, "ArenaBrickGreen"),
		block("GreenBrick2", HALF_BRICK, 4 - HALF_BRICK.X / 2, ROW_Y[2], 0, "ArenaBrickGreen"),
		-- Row 2.
		block("Brick3_1", BRICK, -PITCH, ROW_Y[3], 0, ROW_COLORS[3]),
		block("Brick3_2", BRICK, 0, ROW_Y[3], 0, ROW_COLORS[3]),
		block("Brick3_3", BRICK, PITCH, ROW_Y[3], 0, ROW_COLORS[3]),
	}
	local top = ROW_Y[3] + BRICK.Y / 2
	for index, x in { -PITCH, 0, PITCH } do
		table.insert(
			parts,
			Recipe.disc(`Stud{index}`, STUD_DIAMETER, STUD_HEIGHT, x, top + STUD_HEIGHT / 2, 0, "ArenaViolet")
		)
	end
	return parts
end

-- Arcade Cabinet (sd/arenas2.js:197-207; proxy 5 x 9.4 x 8.6 for the pair, "full"): one cabinet (D10), design size:
-- body rb(5, 8.6, 4.2) at y 4.3; marquee rb(5.3, 1.7, 1.6) at (0, 8.6, 1.3) (glow -> plain, D6); screen 3.8 x 2.9 at
-- (0, 6.4, 2.16) tilted -0.2 rad; control deck rb(5.3, 0.9, 2.2) at (0, 4.6, 2.6); joystick shaft C(0.16) x 1.1 at
-- (-1.3, 5.5, 2.6) and ball SPH(0.5) at y 6.1; 3 buttons C(0.35) x 0.3 at x 0.2 + 0.85i, y 5.1, z 2.7. The front
-- (screen and controls) is the piece's +Z; the screen's SurfaceGui is the builder's.
local function cabinet(color: string): { Recipe.Part }
	return {
		block("Body", Vector3.new(5, 8.6, 4.2), 0, 4.3, 0, color), -- design: sd/arenas2.js:201
		-- design: sd/arenas2.js:201; 0.03 forward so its front clears the body's (flicker, user bug report 2026-10-11)
		block("Marquee", Vector3.new(5.3, 1.7, 1.6), 0, 8.6, 1.3 + 0.03, "ArenaGlowCream"),
		Recipe.turned(
			"Screen",
			Vector3.new(3.8, 2.9, 0.1),
			CFrame.new(0, 6.4, 2.16) * CFrame.Angles(-0.2, 0, 0),
			"ArenaCabinetScreen"
		), -- design: sd/arenas2.js:202 (a plane; 0.1 thick here)
		block("Controls", Vector3.new(5.3, 0.9, 2.2), 0, 4.6, 2.6, "ArenaPlum"), -- design: sd/arenas2.js:203
		Recipe.disc("JoystickShaft", 2 * 0.16, 1.1, -1.3, 5.5, 2.6, "ArenaInk"), -- design: sd/arenas2.js:203
		Recipe.ball("JoystickBall", 2 * 0.5, -1.3, 6.1, 2.6, "ArenaStrawberryRed"), -- design: sd/arenas2.js:203
		Recipe.disc("Button1", 2 * 0.35, 0.3, 0.2, 5.1, 2.7, "ArenaButter"), -- design: sd/arenas2.js:204
		Recipe.disc("Button2", 2 * 0.35, 0.3, 1.05, 5.1, 2.7, "ArenaTeamMint"), -- design: sd/arenas2.js:204
		Recipe.disc("Button3", 2 * 0.35, 0.3, 1.9, 5.1, 2.7, "ArenaSky"), -- design: sd/arenas2.js:204
	}
end

local BRICK_WALL = brickWall()

return {
	id = "arcade_toyworks",
	templateName = "Arena_ArcadeToyworks",
	generatorId = "arena_arcade_toyworks",
	design = { file = "sd/arenas2.js", L = 168, W = 124 } :: Recipe.Design, -- design: sd/arenas2.js:10
	swapA = {} :: { [string]: string },
	-- Side B, by design position (x, z, ry) of the mint team (sd/arenas2.js:223-230 with sx = -1).
	cover = {
		{
			name = "BrickFwd1",
			kind = "full",
			source = "sd/arenas2.js:226",
			x = -24,
			z = -28,
			ry = -0.3,
			parts = BRICK_WALL,
		},
		{
			name = "BrickFwd2",
			kind = "full",
			source = "sd/arenas2.js:226",
			x = -24,
			z = 28,
			ry = 0.3,
			parts = BRICK_WALL,
		},
		{
			name = "BrickFlank1",
			kind = "full",
			source = "sd/arenas2.js:227",
			x = -48,
			z = -46,
			ry = 0,
			parts = BRICK_WALL,
		},
		{
			name = "BrickFlank2",
			kind = "full",
			source = "sd/arenas2.js:227",
			x = -48,
			z = 46,
			ry = 0,
			parts = BRICK_WALL,
		},
		-- design: sd/arenas2.js:228 (the S pair sky, the N pair violet for the mint team). D10: of each back-to-back pair
		-- (sd/arenas2.js:200, one cabinet facing +z, one turned pi) the one facing the lane is kept.
		{
			name = "Cabinet1",
			kind = "full",
			source = "sd/arenas2.js:228",
			x = -40,
			z = -14,
			ry = 0,
			parts = cabinet("ArenaSky"),
		},
		{
			name = "Cabinet2",
			kind = "full",
			source = "sd/arenas2.js:228",
			x = -40,
			z = 14,
			ry = math.pi,
			parts = cabinet("ArenaViolet"),
		},
	},
}
