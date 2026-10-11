--!strict
-- PinewoodCamp: the cover of Pinewood Camp, the "Bloxy summer camp - plank deck, log walls, crates, voxel pines"
-- (design sd/blox.js, facts sd/main.js:442), for the arena registry (World/Arenas). Data only.
-- 1v1 set (phase 4 spec §4.3, D3): 2 Log Walls, 2 Crates and 2 Stumps per side, listed for Side B by their design
-- position (the mint team A, x < 0); World/Arenas maps them and point-reflects Side A. Dropped (spec §4.3): the
-- Watchtower (lane axis: the builder stands it behind each end, D1) and the centre Stump (lane axis). D10: each crate
-- pair (12.2 long) becomes one crate. The design stands every piece on its 0.6 deck (sd/blox.js:6); the game floor top
-- is Y 0, so pieces start at Y 0.

local Recipe = require(script.Parent.Recipe)

local block = Recipe.block

-- Log Wall (sd/blox.js:47-52; proxy 2.4 x 6.8 x 14, "full"): 3 logs C(1.2) x 14 along the wall at y 1.2 / 3.4 / 5.6,
-- staggered along their axis by -0.3 / 0 / 0.3, log ends C(1.05) x 0.2 at +-7.05, 2 stakes B(0.8, 7.4, 0.8) at
-- (1.6, 3.7, +-6). R1: height 6.8 -> 8, radii and heights x 8/6.8 (the stakes touch the bigger logs). R2: length
-- 14 -> 7.4 (spec §4.4), the stake spacing with it; the stagger shrinks to +-0.1 (spec §4.4) so the ends stay within 8.
local K = 8 / 6.8 -- R1
local LOG_LENGTH = 7.4 -- R2 (design 14, sd/blox.js:49)
local LEN = LOG_LENGTH / 14 -- R2 along the wall
local LOG_RADIUS = 1.2 * K -- design: sd/blox.js:49 C(1.2, 1.2, 14)
local LOG_HEIGHTS = { 1.2, 3.4, 5.6 } -- design: sd/blox.js:49
local LOG_STAGGER = 0.1 -- spec §4.4 (design 0.3, sd/blox.js:49)
local END_RADIUS = 1.05 * K -- design: sd/blox.js:49 C(1.05, 1.05, 0.2)
local END_THICKNESS = 0.2 -- design: sd/blox.js:49
local END_OFFSET = LOG_LENGTH / 2 + 0.05 -- design: sd/blox.js:49 (+-7.05 = the log's half length + 0.05)
local STAKE = Vector3.new(0.8, 7.4 * K, 0.8) -- design: sd/blox.js:50 B(0.8, 7.4, 0.8)
local STAKE_X = LOG_RADIUS + STAKE.X / 2 -- design: sd/blox.js:50 (x 1.6 = log radius 1.2 + half a stake)
local STAKE_Z = 6 * LEN -- design: sd/blox.js:50 (z +-6)

local function logWall(): { Recipe.Part }
	local parts: { Recipe.Part } = {}
	for index, height in LOG_HEIGHTS do
		local y = height * K
		local z = (index - 2) * LOG_STAGGER
		table.insert(
			parts,
			Recipe.rodZ(
				if index == 1 then "Body" else `Log{index}`,
				2 * LOG_RADIUS,
				LOG_LENGTH,
				0,
				y,
				z,
				"ArenaLogBark",
				"Wood"
			)
		)
		for side, sign in { -1, 1 } do
			table.insert(
				parts,
				Recipe.rodZ(
					`LogEnd{index}_{side}`,
					2 * END_RADIUS,
					END_THICKNESS,
					0,
					y,
					z + sign * END_OFFSET,
					"ArenaLogEnd",
					"Wood"
				)
			)
		end
	end
	for side, sign in { -1, 1 } do
		table.insert(parts, block(`Stake{side}`, STAKE, STAKE_X, STAKE.Y / 2, sign * STAKE_Z, "ArenaPlankDark", "Wood"))
	end
	return parts
end

-- Crate (sd/blox.js:53-57; proxy 6 x 6 x 12.2 for the pair, "full"): one B(6, 6, 6) crate (D10) with 2 frame boards
-- B(0.5, 6.1, 6.1) at x +-2.8 and 2 diagonal braces B(6.1, 0.7, 0.4) at z +-3.02, rolled 0.78 rad. R1: height 6 -> 8
-- (vertical x 8/6); the braces keep the design size (spec §4.4).
local CRATE_K = 8 / 6 -- R1
local CRATE = Vector3.new(6, 6 * CRATE_K, 6) -- design: sd/blox.js:55 B(6, 6, 6)
local FRAME = Vector3.new(0.5, 6.1 * CRATE_K, 6.1) -- design: sd/blox.js:55 B(0.5, 6.1, 6.1)
local FRAME_X = 2.8 -- design: sd/blox.js:55
local BRACE = Vector3.new(6.1, 0.7, 0.4) -- design: sd/blox.js:55 B(6.1, 0.7, 0.4)
local BRACE_Z = 3.02 -- design: sd/blox.js:55
local BRACE_ROLL = 0.78 -- design: sd/blox.js:55 (rotation z 0.78)

local CRATE_PARTS: { Recipe.Part } = {
	block("Body", CRATE, 0, CRATE.Y / 2, 0, "ArenaPlankLight", "WoodPlanks"),
	block("Frame1", FRAME, -FRAME_X, CRATE.Y / 2, 0, "ArenaPlankDark", "Wood"),
	block("Frame2", FRAME, FRAME_X, CRATE.Y / 2, 0, "ArenaPlankDark", "Wood"),
	Recipe.turned(
		"Brace1",
		BRACE,
		CFrame.new(0, CRATE.Y / 2, -BRACE_Z) * CFrame.Angles(0, 0, BRACE_ROLL),
		"ArenaPlankDark",
		"Wood"
	),
	Recipe.turned(
		"Brace2",
		BRACE,
		CFrame.new(0, CRATE.Y / 2, BRACE_Z) * CFrame.Angles(0, 0, BRACE_ROLL),
		"ArenaPlankDark",
		"Wood"
	),
}

-- Stump (sd/blox.js:58-62; "half cover", lower body only): C(3 top, 3.3 bottom) x 3.5 -> an upright cylinder of the
-- mean diameter 6.3 (a Roblox cylinder cannot taper); top disc C(2.7) x 0.15 at y 3.56; ring C(1.6) x 0.17 at y 3.57.
local STUMP_DIAMETER = 3 + 3.3 -- design: sd/blox.js:60 C(3, 3.3, 3.5): mean radius 3.15
local STUMP_HEIGHT = 3.5 -- design: sd/blox.js:60

local STUMP: { Recipe.Part } = {
	Recipe.disc("Body", STUMP_DIAMETER, STUMP_HEIGHT, 0, STUMP_HEIGHT / 2, 0, "ArenaLogBark", "Wood"),
	Recipe.disc("Top", 2 * 2.7, 0.15, 0, 3.56, 0, "ArenaLogEnd", "Wood"), -- design: sd/blox.js:60 C(2.7) x 0.15, y 3.56
	Recipe.disc("Ring", 2 * 1.6, 0.17, 0, 3.57, 0, "ArenaStumpRing", "Wood"), -- design: sd/blox.js:60, y 3.57
}

local LOG_WALL = logWall()

return {
	id = "pinewood_camp",
	templateName = "Arena_PinewoodCamp",
	generatorId = "arena_pinewood_camp",
	design = { file = "sd/blox.js", L = 170, W = 120 } :: Recipe.Design, -- design: sd/blox.js:6
	swapA = {} :: { [string]: string },
	-- Side B, by design position (x, z, ry) of the mint team (sd/blox.js:74-80 with sx = -1).
	cover = {
		{ name = "LogWall1", kind = "full", source = "sd/blox.js:76", x = -60, z = -28, ry = 0, parts = LOG_WALL },
		{ name = "LogWall2", kind = "full", source = "sd/blox.js:76", x = -60, z = 28, ry = 0, parts = LOG_WALL },
		{ name = "Crate1", kind = "full", source = "sd/blox.js:77", x = -30, z = -18, ry = -0.3, parts = CRATE_PARTS },
		{ name = "Crate2", kind = "full", source = "sd/blox.js:77", x = -30, z = 18, ry = 0.3, parts = CRATE_PARTS },
		{ name = "Stump1", kind = "low", source = "sd/blox.js:78", x = -42, z = -46, ry = 0, parts = STUMP },
		{ name = "Stump2", kind = "low", source = "sd/blox.js:78", x = -42, z = 46, ry = 0, parts = STUMP },
	},
}
