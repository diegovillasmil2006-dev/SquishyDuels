--!strict
-- PinewoodCamp: builds the arena template "Arena_PinewoodCamp", the "Bloxy summer camp - plank deck, log walls,
-- crates, voxel pines" (design sd/blox.js, facts sd/main.js:442-444; phase 4 spec 2026-10-11 §2.2, §4.5, §4.6).
-- Server only, Edit mode only (ServerStorage.SDTools); Main's target "arena_pinewood_camp" runs build(ctx) and swaps
-- the tree into ServerStorage.SD_Templates. ArenaKit makes the gameplay frame (Candy Court's) and the cover (World/
-- Arenas); this module adds the art:
--   Floor     19 planks along the court (the design's deck planks turned to run along it), out to the walls
--   Markings  the design's paint: white lines, mint / strawberry end and team lines, dashed centre circle, diamond
--             spawn marks (ArenaKit.court)
--   Rails     the split-rail fence in the gutter (posts about every 10, two rails)
--   Decor     the grass apron, the two watchtowers behind the ends (D1), the camp scoreboards, 3 log cabins, the
--             campfire, 6 lanterns and a seeded voxel forest with rocks, bushes and grass patches.
-- Every design number carries its sd/blox.js line; out-of-bounds items keep their distance beyond the court edge
-- (spec §4.6, ArenaKit.at) and stay inside the 190-stud apron. Plain colours only (D6: the fire and lanterns do not
-- glow). Same arena lighting as every arena (D8: the design's own sky and fog, sd/fp.js:25-31, are not used).

local ArenaKit = require(script.Parent.ArenaKit)

-- Types

type Kit = ArenaKit.Kit

-- Constants

local ARENA_ID = "pinewood_camp"
local HALF_PI = math.pi / 2

-- Floor (sd/blox.js:28): planks 3.92 wide on a 4 pitch, alternating plank_mid / plank_light; here 4 wide (the floor
-- must be continuous) and 4 deep like every arena floor.
local PLANK_WIDTH = 4 -- design: sd/blox.js:28 (pitch 4)
local PLANK_COLORS = { "ArenaPlankMid", "ArenaPlankLight" } -- design: sd/blox.js:28 (k % 2 ? plank : plank2)

-- Court paint (sd/blox.js:31-37).
local COURT: ArenaKit.CourtStyle = {
	line = "ArenaPaintWhite", -- design: sd/blox.js:18 paint_white
	sideWidth = 0.8, -- design: sd/blox.js:34
	endWidth = 0.8, -- design: sd/blox.js:34
	endA = "ArenaTeamStrawberry", -- design: sd/blox.js:34 (berry end line at +x, the strawberry team)
	endB = "ArenaTeamMint",
	centreWidth = 2, -- design: sd/blox.js:33
	edgeWidth = 0.8, -- design: sd/blox.js:33
	zoneWidth = 0.8, -- design: sd/blox.js:37
	teamA = "ArenaTeamStrawberry",
	teamB = "ArenaTeamMint",
	halfA = "ArenaPlankLight",
	halfB = "ArenaPlankLight",
	circle = "dashes", -- design: sd/blox.js:35
	padMarker = "diamond", -- design: sd/blox.js:37
}

-- Fence (sd/blox.js:40-45): posts B(1.2, 5, 1.2) about every 10, rails B(len, 0.6, 0.5) at y 1.8 and 3.8, 3 beyond the
-- design court; here on the gutter's centre line (X +-37, Z +-53).
local FENCE_X = 37
local FENCE_Z = 53
local POST = Vector3.new(1.2, 5, 1.2) -- design: sd/blox.js:42
local POST_SPACING = 10 -- design: sd/blox.js:42 (n = round(len / 10))
local RAIL_HEIGHT = 0.6 -- design: sd/blox.js:42 B(len, 0.6, 0.5)
local RAIL_DEPTH = 0.5
local RAIL_YS = { 1.8, 3.8 } -- design: sd/blox.js:42

-- Watchtower (sd/blox.js:63-73), a backdrop behind each end (D1): the mint one behind Side B. Spec §4.6: off the centre
-- line so the scoreboard behind it stays visible, its front edge past |Z| 58.
local TOWER_SPOT = Vector2.new(-15, 66) -- spec §4.6 (Side B; Side A is its point reflection)
local TOWER_ROOF_RADIUS = 8.2 -- design: sd/blox.js:69 ConeGeometry(8.2, 5, 4), turned 45 deg: a square pyramid
local TOWER_ROOF_HEIGHT = 5
local TOWER_ROOF_Y = 17.6 -- design: sd/blox.js:69 (cone centre)

-- Scoreboard signs (sd/blox.js:117-122) at Z +-74 (spec §4.6: behind the towers), facing the court.
local BOARD_Z = 74

-- Log cabins (sd/blox.js:94-106): design spots (x, z, ry); the third one is moved in to X 80 to fit the apron
-- (spec §4.6: the design's distance would put it at X 88, its back at 97).
local CABINS = {
	{ x = -48, z = -94, ry = 0 }, -- design: sd/blox.js:106
	{ x = 52, z = -100, ry = -0.25 }, -- design: sd/blox.js:106
	{ x = 0, z = 112, ry = math.pi, gameX = 80 }, -- design: sd/blox.js:106; spec §4.6
}

-- Campfire (sd/blox.js:108-115) at design (0, -W / 2 - 22).
local CAMPFIRE = { x = 0, z = -82 } -- design: sd/blox.js:108
local FLAMES = { -- design: sd/blox.js:112 [x, z, r, h, colour] (4-sided cones: square pyramids)
	{ x = 0, z = 0, radius = 1.6, height = 4.2, color = "ArenaFireCore" },
	{ x = 0.8, z = 0.4, radius = 1.1, height = 3.2, color = "ArenaFireTip" },
	{ x = -0.7, z = -0.3, radius = 1.0, height = 2.8, color = "ArenaFireTip" },
	{ x = 0.1, z = -0.7, radius = 0.9, height = 2.4, color = "ArenaFireCore" },
}

-- Lanterns (sd/blox.js:123-124) at the fence corners and the long sides' middles: here just outside the barrier walls.
local LANTERNS = { { -39, -55 }, { 39, -55 }, { -39, 55 }, { 39, 55 }, { -39, 0 }, { 39, 0 } } -- spec §4.6

-- Forest (sd/blox.js:82-92): the design scatters 95 voxel trees (62% pines), 40 rocks and bushes and 70 grass patches
-- with rng(21). Here the same recipes, seeded the same way, in the band between the court and the apron edge, clear of
-- the other props (spec §4.6: about 20 trees).
local TREES = 20
local ROCKS = 8
local PATCHES = 8
local SEED = 21 -- design: sd/blox.js:13 rng(21)
local SCATTER_HALF = 86 -- tree centres stay inside the apron (95) with their leaves
local CLEAR_X, CLEAR_Z = 48, 64 -- outside the court, its fence and the lanterns
-- Props the scatter keeps away from: { x, z, radius } (game).
local KEEP_AWAY = {
	{ -70, 29.4, 18 }, -- cabin 1
	{ -76, -31.8, 18 }, -- cabin 2
	{ 80, 0, 18 }, -- cabin 3
	{ -58, 0, 15 }, -- campfire and benches
	{ -15, 66, 10 }, -- towers
	{ 15, -66, 10 },
	{ 0, 74, 15 }, -- scoreboards
	{ 0, -74, 15 },
}

-- Module table

local PinewoodCamp = {}
PinewoodCamp.GENERATOR_ID = "arena_pinewood_camp"
PinewoodCamp.VERSION = 1
PinewoodCamp.ROOT_NAME = "Arena_PinewoodCamp"
PinewoodCamp.ARENA_ID = ARENA_ID

-- Private

local function buildFloor(k: Kit)
	local count = math.round(2 * (k.layout.halfX + 2) / PLANK_WIDTH) -- 19 planks across X +-38
	local length = 2 * (k.layout.halfZ + 2)
	for index = 1, count do
		local x = -(k.layout.halfX + 2) + (index - 0.5) * PLANK_WIDTH
		ArenaKit.part(
			k,
			k.floor,
			string.format("Plank_%02d", index),
			Vector3.new(PLANK_WIDTH, 4, length),
			CFrame.new(x, -2, 0),
			PLANK_COLORS[(index - 1) % 2 + 1],
			"solid"
		)
	end
end

local function fenceLine(k: Kit, name: string, from: Vector3, to: Vector3, posts: { [string]: boolean })
	local length = (to - from).Magnitude
	local count = math.round(length / POST_SPACING)
	for index = 0, count do
		local point = from:Lerp(to, index / count)
		local key = string.format("%.1f,%.1f", point.X, point.Z)
		if not posts[key] then -- corner posts are shared by two lines
			posts[key] = true
			ArenaKit.part(
				k,
				k.rails,
				string.format("Post_%s", key),
				POST,
				CFrame.new(point.X, POST.Y / 2, point.Z),
				"ArenaPlankDark",
				"solid"
			)
		end
	end
	local centre = (from + to) / 2
	local along = to - from
	local turn = CFrame.Angles(0, math.atan2(-along.Z, along.X), 0) -- the rail's X along the line
	for index, y in RAIL_YS do
		ArenaKit.part(
			k,
			k.rails,
			`{name}Rail{index}`,
			Vector3.new(length, RAIL_HEIGHT, RAIL_DEPTH),
			CFrame.new(centre.X, y, centre.Z) * turn,
			"ArenaPlankMid",
			"solid"
		)
	end
end

local function buildFence(k: Kit)
	local posts: { [string]: boolean } = {}
	local corners = {
		Vector3.new(-FENCE_X, 0, -FENCE_Z),
		Vector3.new(FENCE_X, 0, -FENCE_Z),
		Vector3.new(FENCE_X, 0, FENCE_Z),
		Vector3.new(-FENCE_X, 0, FENCE_Z),
	}
	for index, name in { "EndA", "East", "EndB", "West" } do
		fenceLine(k, name, corners[index], corners[index % 4 + 1], posts)
	end
end

-- The watchtower (sd/blox.js:63-73), design size, in its team colour.
local function tower(k: Kit, name: string, x: number, z: number, team: string)
	local model, frame = ArenaKit.group(k, name, x, z, ArenaKit.yaw(0))
	ArenaKit.box(k, model, frame, "Base", Vector3.new(8, 6, 8), 0, 0, 0, "ArenaPlankMid") -- design: sd/blox.js:65
	for index, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		ArenaKit.box(
			k,
			model,
			frame,
			`Leg{index}`,
			Vector3.new(1.2, 15, 1.2),
			corner[1] * 4.2,
			0,
			corner[2] * 4.2,
			"ArenaPlankDark"
		) -- design: sd/blox.js:66
	end
	ArenaKit.box(k, model, frame, "Floor", Vector3.new(10, 0.8, 10), 0, 10, 0, "ArenaPlankLight") -- design: :67
	for index, sign in { -1, 1 } do
		ArenaKit.box(k, model, frame, `RailZ{index}`, Vector3.new(10, 1.6, 0.5), 0, 10.8, sign * 4.8, "ArenaPlankDark")
		ArenaKit.box(k, model, frame, `RailX{index}`, Vector3.new(0.5, 1.6, 10), sign * 4.8, 10.8, 0, "ArenaPlankDark")
	end -- design: sd/blox.js:68
	-- The 4-sided cone turned 45 deg (sd/blox.js:69) is a square pyramid with sides radius * sqrt 2 on the axes.
	ArenaKit.pyramid(
		k,
		model,
		"Roof",
		TOWER_ROOF_RADIUS * math.sqrt(2),
		TOWER_ROOF_HEIGHT,
		frame * CFrame.new(0, TOWER_ROOF_Y - TOWER_ROOF_HEIGHT / 2, 0),
		team
	)
	ArenaKit.box(k, model, frame, "Flag", Vector3.new(1.4, 3, 0.3), 0, 20, 0, team) -- design: sd/blox.js:70
end

-- The camp scoreboard sign (sd/blox.js:117-122) at (0, z), turned `yaw` (its front, local +Z, faces the court).
local function scoreboard(k: Kit, name: string, z: number, yaw: number)
	local model, frame = ArenaKit.group(k, name, 0, z, yaw)
	for index, sign in { -1, 1 } do
		ArenaKit.box(k, model, frame, `Post{index}`, Vector3.new(1.6, 18, 1.6), sign * 10, 0, 0, "ArenaTrunk")
	end -- design: sd/blox.js:119
	ArenaKit.box(k, model, frame, "Board", Vector3.new(24, 9, 1.4), 0, 10, 0, "ArenaPlankLight") -- design: :120
	ArenaKit.box(k, model, frame, "Cap", Vector3.new(25.5, 1.2, 1.8), 0, 19.4, 0, "ArenaPlankDark") -- design: :120
	for index, sign in { -1, 1 } do
		ArenaKit.box(
			k,
			model,
			frame,
			`TeamPanel{index}`,
			Vector3.new(9, 5, 0.3),
			sign * 5.5,
			12,
			0.85,
			if sign < 0 then "ArenaTeamMint" else "ArenaTeamStrawberry"
		) -- design: sd/blox.js:121
	end
end

-- A log cabin (sd/blox.js:94-106), its front (door, windows, porch) toward local +Z. The front's log rows, log ends
-- and window sills are left out for the part budget (D5).
local function cabin(k: Kit, name: string, x: number, z: number, yaw: number)
	local model, frame = ArenaKit.group(k, name, x, z, yaw)
	ArenaKit.box(k, model, frame, "Walls", Vector3.new(28, 12, 18), 0, 0, 0, "ArenaLogBark") -- design: :96
	ArenaKit.box(k, model, frame, "Door", Vector3.new(4.5, 8, 0.6), 0, 0, 9.4, "ArenaPlankDark") -- design: :99
	for index, sign in { -1, 1 } do
		ArenaKit.box(k, model, frame, `Window{index}`, Vector3.new(5, 4, 0.5), sign * 8.5, 5, 9.6, "ArenaCabinWindow")
		ArenaKit.part(
			k,
			model,
			`Roof{index}`,
			Vector3.new(30, 1.4, 12),
			frame * CFrame.new(0, 15.2, sign * 4.6) * CFrame.Angles(sign * 0.62, 0, 0),
			"ArenaCabinRoof"
		) -- design: sd/blox.js:101
	end -- design: sd/blox.js:100
	ArenaKit.box(k, model, frame, "Gable", Vector3.new(28, 5.6, 12), 0, 12, 0, "ArenaLogBark") -- design: :102
	ArenaKit.box(k, model, frame, "Chimney", Vector3.new(3, 8, 3), 9, 14, -3, "ArenaChimneyStone") -- design: :103
	ArenaKit.box(k, model, frame, "Porch", Vector3.new(6, 0.8, 4), 0, 0, 11.2, "ArenaPlankDark") -- design: :104
end

-- The campfire (sd/blox.js:108-115): 9 stones, the fire log, 4 flames, the tripod and pot, 2 log benches.
local function campfire(k: Kit, random: () -> number)
	local x, z = ArenaKit.at(k, CAMPFIRE.x, CAMPFIRE.z)
	local model, frame = ArenaKit.group(k, "Campfire", x, z, ArenaKit.yaw(0))
	for index = 0, 8 do
		local a = index / 9 * 2 * math.pi
		ArenaKit.part(
			k,
			model,
			`Stone{index + 1}`,
			Vector3.new(1.8, 1.2, 1.4),
			frame * CFrame.new(math.cos(a) * 3.2, 0.6, math.sin(a) * 3.2) * CFrame.Angles(0, -a, 0),
			"ArenaRock"
		) -- design: sd/blox.js:109
	end
	-- design: sd/blox.js:110: two logs whose Euler turns both end up along z (one log shows).
	ArenaKit.rod(
		k,
		model,
		"Log",
		1.1,
		5.5,
		frame * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, HALF_PI, 0),
		"ArenaLogBark"
	)
	for index, flame in FLAMES do
		ArenaKit.pyramid(
			k,
			model,
			`Flame{index}_`,
			flame.radius * math.sqrt(2),
			flame.height,
			frame * CFrame.new(flame.x, 0.8, flame.z) * CFrame.Angles(0, random() * 3, 0),
			flame.color
		) -- design: sd/blox.js:111-112 (flames group at y 0.8, random turn r() * 3)
	end
	for index, a in { 0, 2.1, 4.2 } do
		ArenaKit.part(
			k,
			model,
			`TripodLeg{index}`,
			Vector3.new(0.35, 9.5, 0.35),
			frame
				* CFrame.new(math.cos(a) * 1.6, 4.4, math.sin(a) * 1.6)
				* CFrame.Angles(math.sin(a) * -0.32, 0, math.cos(a) * 0.32),
			"ArenaIron"
		) -- design: sd/blox.js:113
	end
	ArenaKit.disc(k, model, "Pot", 1.1 + 0.9, 1.4, frame:PointToWorldSpace(Vector3.new(0, 5.6, 0)), "ArenaIron") -- :114
	for index, sign in { -1, 1 } do
		ArenaKit.rod(
			k,
			model,
			`Bench{index}`,
			2,
			9,
			frame * CFrame.new(sign * 9, 1.4, 2) * CFrame.Angles(0, sign * 0.3, 0),
			"ArenaLogBark"
		) -- design: sd/blox.js:115 (log C(1, 1, 9) along the bench's x)
	end
end

local function lanterns(k: Kit)
	for index, spot in LANTERNS do
		local model, frame = ArenaKit.group(k, `Lantern{index}`, spot[1], spot[2], 0)
		ArenaKit.box(k, model, frame, "Post", Vector3.new(1, 9, 1), 0, 0, 0, "ArenaPlankDark") -- design: :124
		ArenaKit.box(k, model, frame, "Cage", Vector3.new(2, 2.2, 2), 0, 9, 0, "ArenaIron") -- design: :124
		-- The design's glow box (1.4 x 1.6 x 1.4, sd/blox.js:124) sits inside the opaque cage, unseen: left out.
	end
end

-- A pine or an oak (sd/blox.js:83-87), size factor `scale`, turned `turn`.
local function tree(
	k: Kit,
	parent: Instance,
	name: string,
	x: number,
	z: number,
	pine: boolean,
	scale: number,
	turn: number
)
	local model, frame = ArenaKit.group(k, name, x, z, turn)
	local s = scale
	if pine then
		ArenaKit.box(k, model, frame, "Trunk", Vector3.new(2.2 * s, 7 * s, 2.2 * s), 0, 0, 0, "ArenaTrunk")
		for index, leaf in { { 11, 5, 5.5 }, { 8, 4.5, 9.5 }, { 5, 4, 13 } } do
			ArenaKit.part(
				k,
				model,
				`Leaves{index}`,
				Vector3.new(leaf[1] * s, leaf[2] * s, leaf[1] * s),
				frame * CFrame.new(0, leaf[3] * s, 0) * CFrame.Angles(0, leaf[3] * 0.3, 0),
				"ArenaPineLeaves"
			) -- design: sd/blox.js:85 (centre at y * k, turned ry + y * 0.3)
		end
	else
		ArenaKit.box(k, model, frame, "Trunk", Vector3.new(2.6 * s, 8 * s, 2.6 * s), 0, 0, 0, "ArenaTrunk")
		for index, leaf in { { 13, 9, 12, 0, 0 }, { 7, 6, 15, 4, 3 } } do
			ArenaKit.part(
				k,
				model,
				`Leaves{index}`,
				Vector3.new(leaf[1] * s, leaf[2] * s, leaf[1] * s),
				frame * CFrame.new(leaf[4] * s, leaf[3] * s, leaf[5] * s),
				"ArenaOakLeaves"
			) -- design: sd/blox.js:86
		end
	end
	model.Parent = parent
end

-- A seeded spot in the band around the court, clear of the props in KEEP_AWAY (nil after too many tries).
local function scatterSpot(random: () -> number, margin: number): (number?, number?)
	for _ = 1, 200 do
		local x = (random() * 2 - 1) * SCATTER_HALF
		local z = (random() * 2 - 1) * SCATTER_HALF
		local clear = math.abs(x) >= CLEAR_X or math.abs(z) >= CLEAR_Z
		for _, spot in KEEP_AWAY do
			if (Vector2.new(x, z) - Vector2.new(spot[1], spot[2])).Magnitude < spot[3] + margin then
				clear = false
			end
		end
		if clear then
			return x, z
		end
	end
	return nil, nil
end

local function forest(k: Kit, random: () -> number)
	local woods = ArenaKit.model(k.decor, "Forest", CFrame.identity)
	for index = 1, TREES do
		local x, z = scatterSpot(random, 6)
		if x == nil or z == nil then
			table.insert(k.warnings, "Pinewood forest: no room for every tree")
			break
		end
		local pine = random() < 0.62 -- design: sd/blox.js:85
		local scale = 0.8 + random() * 0.6 -- design: sd/blox.js:84
		tree(k, woods, string.format("Tree%02d", index), x, z, pine, scale, random() * math.pi)
	end
	for index = 1, ROCKS do
		local x, z = scatterSpot(random, 2)
		if x == nil or z == nil then
			break
		end
		local s = 1 + random() * 2.5 -- design: sd/blox.js:91
		ArenaKit.part(
			k,
			woods,
			if index % 2 == 0 then `Rock{index}` else `Bush{index}`,
			Vector3.new(2.6 * s, 1.6 * s, 2 * s),
			CFrame.new(x, 0.5 * s, z) * CFrame.Angles(random() * 0.3, random() * 3, random() * 0.3),
			if index % 2 == 0 then "ArenaRock" else "ArenaOakLeaves"
		) -- design: sd/blox.js:91-92 (rocks and bushes alternate)
	end
	for index = 1, PATCHES do
		local x, z = scatterSpot(random, 0)
		if x == nil or z == nil then
			break
		end
		ArenaKit.part(
			k,
			woods,
			`GrassPatch{index}`,
			Vector3.new(6 + random() * 14, 0.08, 6 + random() * 14),
			CFrame.new(x, -0.01, z) * CFrame.Angles(0, random() * 3, 0),
			"ArenaGrassDark"
		) -- design: sd/blox.js:25 (on the apron, whose top is -0.05)
	end
end

local function art(k: Kit)
	buildFloor(k)
	ArenaKit.court(k, COURT)
	buildFence(k)
	tower(k, "WatchtowerB", TOWER_SPOT.X, TOWER_SPOT.Y, "ArenaTeamMint")
	tower(k, "WatchtowerA", -TOWER_SPOT.X, -TOWER_SPOT.Y, "ArenaTeamStrawberry")
	scoreboard(k, "ScoreboardB", BOARD_Z, ArenaKit.yaw(HALF_PI)) -- design: sd/blox.js:118 (turned -sx * pi / 2)
	scoreboard(k, "ScoreboardA", -BOARD_Z, ArenaKit.yaw(-HALF_PI))
	for index, spot in CABINS do
		local x, z = ArenaKit.at(k, spot.x, spot.z)
		cabin(k, `Cabin{index}`, spot.gameX or x, z, ArenaKit.yaw(spot.ry))
	end
	local random = ArenaKit.rng(SEED)
	campfire(k, random)
	lanterns(k)
	forest(k, random)
end

-- Public

-- Builds the new template tree, unparented and marked (Generated contract). Never yields, never changes the place.
function PinewoodCamp.build(ctx: ArenaKit.BuildContext): ArenaKit.BuildResult
	return ArenaKit.build(ctx, {
		arenaId = ARENA_ID,
		generatorId = PinewoodCamp.GENERATOR_ID,
		version = PinewoodCamp.VERSION,
		rootName = PinewoodCamp.ROOT_NAME,
		apron = "ArenaGrass", -- design: sd/blox.js:23 floor_base grass
		padA = "ArenaPlankLight",
		padB = "ArenaPlankLight",
		jellyTransparency = 1 - 0.12, -- design: sd/blox.js:38 (opacity 0.12)
	}, art)
end

return PinewoodCamp
