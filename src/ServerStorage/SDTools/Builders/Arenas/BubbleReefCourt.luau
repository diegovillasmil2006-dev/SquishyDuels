--!strict
-- BubbleReefCourt: builds the arena template "Arena_BubbleReefCourt", the "Dry aquarium court - sponge walls, giant
-- clam, sea-glass pillars, brain coral" (design sd/arenas2.js:116-175, facts sd/main.js:449-452; phase 4 spec
-- 2026-10-11 §2.4, §4.5, §4.6). Server only, Edit mode only (ServerStorage.SDTools); Main's target
-- "arena_bubble_reef_court" runs build(ctx) and swaps the tree into ServerStorage.SD_Templates. ArenaKit makes the
-- gameplay frame (Candy Court's) and the cover (World/Arenas); this module adds the art:
--   Floor     the aqua and coral court halves, out to the walls
--   Markings  the design's white lines, mint / strawberry end and team lines, centre ring and ring spawn marks
--   Rails     low reef-rock rails in the gutter
--   Decor     the sand apron, the pebble border on the rails, a Giant Clam behind each end (D1), the aquarium tanks along
--             both long sides (glass, water, kelp, tube coral, bubbles, fish) and the reef end walls with their
--             porthole scoreboards.
-- Every design number carries its sd/arenas2.js line; out-of-bounds items keep their distance beyond the court edge
-- (spec §4.6, ArenaKit.at) and stay inside the 190-stud apron; random scatter uses the design's rng(41). Plain colours
-- only (D6: the water does not glow). Superellipsoids are ellipsoids and tori flat discs (spec §4.6). The wavy court
-- lines (sd/arenas2.js:125) are left out for the part budget (D5).

local ArenaKit = require(script.Parent.ArenaKit)

-- Types

type Kit = ArenaKit.Kit

-- Constants

local ARENA_ID = "bubble_reef_court"
local HALF_PI = math.pi / 2

local COURT: ArenaKit.CourtStyle = {
	line = "White", -- design: sd/arenas2.js:121 wave_white #FFFFFF (the court() line colour, :124)
	sideWidth = 1, -- design: sd/arenas2.js:21
	endWidth = 1,
	endA = "ArenaTeamStrawberry", -- design: sd/arenas2.js:21
	endB = "ArenaTeamMint",
	centreWidth = 2.2, -- design: sd/arenas2.js:22
	edgeWidth = 0.8,
	zoneWidth = 0.8, -- design: sd/arenas2.js:26
	teamA = "ArenaTeamStrawberry",
	teamB = "ArenaTeamMint",
	halfA = "ArenaCourtCoral", -- design: sd/arenas2.js:121 court_coral
	halfB = "ArenaCourtAqua", -- design: sd/arenas2.js:121 court_aqua
	circle = "ring", -- design: sd/arenas2.js:23
	padMarker = "ring", -- design: sd/arenas2.js:27
}

-- Rails: the design has no rail, only a pebble border (sd/arenas2.js:126); spec §4.5: low reef-rock rails 1.5 tall in
-- the gutter, with the pebbles (pills 3-4 x 1.6-2.2 x 2.6-3.2 every 3.4, in pebble / reef rock / warm rock) along them
-- as decor, about 40.
local RAIL_DEPTH = 1.2
local RAIL_HEIGHT = 1.5
local PEBBLES = 40
local PEBBLE_COLORS = { "ArenaPebble", "ArenaReefRock", "ArenaReefRockWarm" } -- design: sd/arenas2.js:126

-- Giant Clam (sd/arenas2.js:134-141), a backdrop behind each end (D1), opening toward the court; spec §4.6: (0, +-65.5).
local CLAM_Z = 65.5
local SHELL = Vector3.new(14, 3, 12.4) -- design: sd/arenas2.js:134 superF(7, 2.6, 6.2) halves -> flattened ellipsoids
local HINGE = Vector3.new(-6.6, 4.7, 0) -- design: sd/arenas2.js:139
local HINGE_OPEN = 0.95 -- design: sd/arenas2.js:139

-- Aquarium tanks (sd/arenas2.js:150-159) along both long sides: glass 12 beyond the court edge, the water box centred 33
-- beyond (16 deep, 36 tall); 190 long here (the design's L + 90 cut to the apron, spec §4.6), posts every 34.5; kelp 5,
-- tube corals 3, bubbles 8, fish 4 a side (spec §4.6).
local TANK_LENGTH = 190
local TANK_HEIGHT = 36 -- design: sd/arenas2.js:153
local GLASS_BEYOND = 12 -- design: sd/arenas2.js:152 zg = W / 2 + 12
local WATER_BEYOND = 33 -- design: sd/arenas2.js:152 zw = W / 2 + 33
local WATER_DEPTH = 16 -- design: sd/arenas2.js:153
local POST_SPACING = 34.5 -- design: sd/arenas2.js:155
local KELP, CORALS, BUBBLES, FISH = 5, 3, 8, 4
local FISH_COLORS = { "ArenaButter", "ArenaFishOrange", "ArenaSky", "ArenaFishPink" } -- design: sd/arenas2.js:160
local SEED = 41 -- design: sd/arenas2.js:119 rng(41)

-- Reef end walls (sd/arenas2.js:164-172) 24 beyond each end: 8 boulders (the design's 16), here 4 each side of the
-- clam so none stands in front of it, and a porthole scoreboard at y 24 facing the court.
local BOULDER_X = { 12, 20, 28, 36 } -- each side of the end's centre line
local END_BEYOND = 24 -- design: sd/arenas2.js:165 (L / 2 + 24)

-- Module table

local BubbleReefCourt = {}
BubbleReefCourt.GENERATOR_ID = "arena_bubble_reef_court"
BubbleReefCourt.VERSION = 1
BubbleReefCourt.ROOT_NAME = "Arena_BubbleReefCourt"
BubbleReefCourt.ARENA_ID = ARENA_ID

-- Private

local function buildRails(k: Kit)
	local halfX, halfZ = k.layout.halfX, k.layout.halfZ
	for _, side in { "A", "B" } do
		local sign = if side == "A" then -1 else 1
		for index, sx in { -1, 1 } do
			ArenaKit.part(
				k,
				k.rails,
				`{side}_Rock{index}`,
				Vector3.new(RAIL_DEPTH, RAIL_HEIGHT, halfZ),
				CFrame.new(sx * (halfX + RAIL_DEPTH / 2), RAIL_HEIGHT / 2, sign * halfZ / 2),
				"ArenaReefRock",
				"solid"
			)
		end
		ArenaKit.part(
			k,
			k.rails,
			`{side}_RockEnd`,
			Vector3.new(2 * (halfX + RAIL_DEPTH), RAIL_HEIGHT, RAIL_DEPTH),
			CFrame.new(0, RAIL_HEIGHT / 2, sign * (halfZ + RAIL_DEPTH / 2)),
			"ArenaReefRock",
			"solid"
		)
	end
end

-- The pebble border (sd/arenas2.js:126) along the rails: seeded pebble sizes and turns, evenly round the court.
local function pebbles(k: Kit, random: () -> number)
	local model = ArenaKit.model(k.decor, "PebbleBorder", CFrame.identity)
	local halfX = k.layout.halfX + RAIL_DEPTH / 2
	local halfZ = k.layout.halfZ + RAIL_DEPTH / 2
	local perimeter = 4 * (halfX + halfZ)
	for index = 1, PEBBLES do
		local d = (index - 0.5) / PEBBLES * perimeter
		local x, z = 0, 0
		if d < 2 * halfX then
			x, z = -halfX + d, -halfZ
		elseif d < 2 * halfX + 2 * halfZ then
			x, z = halfX, -halfZ + (d - 2 * halfX)
		elseif d < 4 * halfX + 2 * halfZ then
			x, z = halfX - (d - 2 * halfX - 2 * halfZ), halfZ
		else
			x, z = -halfX, halfZ - (d - 4 * halfX - 2 * halfZ)
		end
		local size = Vector3.new(3 + random(), 1.6 + random() * 0.6, 2.6 + random() * 0.6) -- design: sd/arenas2.js:126
		ArenaKit.ellipsoid(
			k,
			model,
			string.format("Pebble%02d", index),
			size,
			CFrame.new(x, 0.7, z) * CFrame.Angles(0, random() * 3, 0), -- design: sd/arenas2.js:126 (y DECK + 0.7)
			PEBBLE_COLORS[(index - 1) % #PEBBLE_COLORS + 1]
		)
	end
end

-- The Giant Clam (sd/arenas2.js:134-141) at (0, z), opening toward local +x (the court).
local function clam(k: Kit, name: string, z: number, ry: number)
	local model, frame = ArenaKit.group(k, name, 0, z, ArenaKit.yaw(ry))
	ArenaKit.part(k, model, "RockBase", Vector3.new(15, 2.4, 13), frame * CFrame.new(0, 1.2, 0), "ArenaReefRock") -- :137
	-- The lower shell: the lower half of the superellipsoid under y 4.6, as a flattened ellipsoid just below it.
	ArenaKit.ellipsoid(
		k,
		model,
		"ShellBottom",
		SHELL,
		frame * CFrame.new(0, 4.6 - SHELL.Y / 2 + 0.5, 0),
		"ArenaClamShell"
	)
	ArenaKit.ellipsoid(k, model, "Inner", Vector3.new(10, 1.6, 9), frame * CFrame.new(0.6, 4.7, 0), "ArenaClamInner") -- design: sd/arenas2.js:138 pill(10, 1.6, 9)
	ArenaKit.ball(k, model, "Pearl", 2 * 2.3, frame:PointToWorldSpace(Vector3.new(1, 6.6, 0)), "ArenaPearl") -- :138
	-- The upper shell, flipped and hinged at the back, opened 0.95 rad (sd/arenas2.js:139).
	local hinge = frame * CFrame.new(HINGE) * CFrame.Angles(0, 0, HINGE_OPEN)
	ArenaKit.ellipsoid(k, model, "ShellTop", SHELL, hinge * CFrame.new(6.6, SHELL.Y / 2 - 0.5, 0), "ArenaClamShell")
end

-- One aquarium tank along the long side `sz` (+1 = +X).
local function aquarium(k: Kit, sz: number, random: () -> number)
	local halfX = k.layout.halfX
	local glassX = sz * (halfX + GLASS_BEYOND)
	local waterX = sz * (halfX + WATER_BEYOND)
	local model = ArenaKit.model(k.decor, if sz < 0 then "AquariumWest" else "AquariumEast", CFrame.new(glassX, 0, 0))
	local half = TANK_LENGTH / 2
	ArenaKit.part(
		k,
		model,
		"Water",
		Vector3.new(WATER_DEPTH, TANK_HEIGHT, TANK_LENGTH),
		CFrame.new(waterX, TANK_HEIGHT / 2, 0),
		"ArenaAquariumWater"
	) -- design: sd/arenas2.js:153
	local glass = ArenaKit.part(
		k,
		model,
		"Glass",
		Vector3.new(0.5, TANK_HEIGHT, TANK_LENGTH),
		CFrame.new(glassX, TANK_HEIGHT / 2, 0),
		"ArenaTankGlass",
		"decor",
		nil,
		Enum.Material.Glass
	)
	glass.Transparency = 1 - 0.18 -- design: sd/arenas2.js:121 tank_glass opacity 0.18
	glass.CastShadow = false
	for index, y in { 0.9, 35.6 } do
		ArenaKit.part(
			k,
			model,
			`Rail{index}`,
			Vector3.new(3, 1.8, TANK_LENGTH + 2),
			CFrame.new(glassX, y, 0),
			"ArenaTrimWhite"
		) -- design: sd/arenas2.js:154 rb(L + 92, 1.8, 3)
	end
	local posts = math.floor(TANK_LENGTH / POST_SPACING)
	for index = 0, posts do
		ArenaKit.part(
			k,
			model,
			`Post{index + 1}`,
			Vector3.new(3.2, TANK_HEIGHT, 2.4),
			CFrame.new(glassX, TANK_HEIGHT / 2, -half + index * TANK_LENGTH / posts),
			"ArenaTrimWhite"
		) -- design: sd/arenas2.js:155 B(2.4, 36, 3.2)
	end
	-- Inside the tank (between the glass and the water): kelp, tube corals with their rocks, bubbles, fish.
	local function inside(depth: number): number
		return glassX + sz * depth
	end
	for index = 1, KELP do
		local height = 10 + random() * 20 -- design: sd/arenas2.js:156
		local z = -half + (index - 0.5) / KELP * TANK_LENGTH + (random() - 0.5) * 4
		ArenaKit.part(
			k,
			model,
			`Kelp{index}`,
			Vector3.new(0.5, height, 1.4),
			CFrame.new(inside(5 + random() * 8), height / 2, z) * CFrame.Angles(0, 0, (random() - 0.5) * 0.25),
			if index % 2 == 0 then "ArenaKelpDark" else "ArenaKelp"
		) -- design: sd/arenas2.js:156 (a stack of rb(1.4, 2.6, 0.5) segments as one blade)
	end
	for index = 1, CORALS do
		local z = (random() - 0.5) * (TANK_LENGTH - 20)
		local x = inside(4 + random() * 8)
		for tube = 1, 2 do
			local height = 3 + random() * 5 -- design: sd/arenas2.js:157 C(0.8, 1, 3 + r * 5)
			ArenaKit.disc(
				k,
				model,
				`Coral{index}_{tube}`,
				1.8,
				height,
				Vector3.new(x + (random() - 0.5) * 3, height / 2, z + (random() - 0.5) * 3),
				if index % 2 == 0 then "ArenaTubeCoralLilac" else "ArenaTubeCoralOrange"
			)
		end
		ArenaKit.part(
			k,
			model,
			`CoralRock{index}`,
			Vector3.new(5 + random() * 4, 3 + random() * 2, 4 + random() * 3),
			CFrame.new(x + sz * 3, 1.4, z) * CFrame.Angles(0, random() * 3, 0),
			if index % 2 == 0 then "ArenaReefRockWarm" else "ArenaReefRock"
		) -- design: sd/arenas2.js:157 rb(5-9, 3-5, 4-7)
	end
	for index = 1, BUBBLES do
		ArenaKit.ball(
			k,
			model,
			`Bubble{index}`,
			2 * (0.25 + random() * 0.5),
			Vector3.new(inside(2 + random() * 9), 3 + random() * 30, (random() - 0.5) * (TANK_LENGTH - 10)),
			"ArenaBubble"
		) -- design: sd/arenas2.js:158
	end
	for index = 1, FISH do
		local s = 1 + random() * 0.8 -- design: sd/arenas2.js:161
		local facing = if random() < 0.5 then 1 else -1 -- swims toward +z or -z
		local body = CFrame.new(inside(6 + random() * 6), 7 + random() * 22, (random() - 0.5) * (TANK_LENGTH - 30))
		local color = FISH_COLORS[(index - 1) % #FISH_COLORS + 1]
		-- design: sd/arenas2.js:161 body pill(4k, 2.6k, 1.6k) along the swim, cone tail behind, a dark eye in front
		ArenaKit.ellipsoid(k, model, `Fish{index}`, Vector3.new(1.6, 2.6, 4) * s, body, color)
		ArenaKit.wedge(
			k,
			model,
			`FishTail{index}`,
			Vector3.new(0.4, 2.6, 2) * s,
			body * CFrame.new(0, 0, -facing * 2.6 * s) * CFrame.Angles(0, if facing > 0 then math.pi else 0, 0),
			color
		)
		ArenaKit.ball(
			k,
			model,
			`FishEye{index}`,
			0.6 * s,
			body:PointToWorldSpace(Vector3.new(-sz * 0.75 * s, 0.35 * s, facing * 1.1 * s)),
			"ArenaInk"
		)
	end
end

-- A reef end wall (sd/arenas2.js:164-172) 24 beyond the end `sign` (+1 = +Z): boulders and the porthole scoreboard.
local function reefEnd(k: Kit, sign: number, random: () -> number)
	local z = sign * (k.layout.halfZ + END_BEYOND)
	local model, frame =
		ArenaKit.group(k, if sign > 0 then "ReefEndB" else "ReefEndA", 0, z, if sign > 0 then math.pi else 0)
	local index = 0
	for _, side in { -1, 1 } do
		for _, x in BOULDER_X do
			index += 1
			local size = Vector3.new(10 + random() * 10, 6 + random() * 10, 10 + random() * 8) -- design: :166
			ArenaKit.part(
				k,
				model,
				`Boulder{index}`,
				size,
				frame * CFrame.new(side * x, 3 + random() * 6, -random() * 6) * CFrame.Angles(0, random() * 3, 0),
				"ArenaReefRock"
			) -- design: sd/arenas2.js:166 (y 3 + r * 6, spread along the end; local +Z faces the court, so back is -Z)
		end
	end
	-- Porthole at y 24 facing the court (local -Z here): plum disc C(9) x 2, gold rim torus (r 9, tube 1.2) as a gold
	-- disc behind it, 8 gold bolts at r 9, two team panels (sd/arenas2.js:168-171).
	local port = frame * CFrame.new(0, 24, 0) * CFrame.Angles(0, HALF_PI, 0) -- a Cylinder's axis (X) toward the court
	ArenaKit.rod(k, model, "PortholeBack", 18, 2, port, "ArenaPlum") -- design: sd/arenas2.js:169
	ArenaKit.rod(k, model, "PortholeRim", 2 * (9 + 1.2), 1.6, port * CFrame.new(0.3, 0, 0), "ArenaGold") -- :169
	for bolt = 0, 7 do
		local a = bolt / 8 * 2 * math.pi
		ArenaKit.ball(
			k,
			model,
			`Bolt{bolt + 1}`,
			1.4,
			(port * CFrame.new(-1.1, math.sin(a) * 9, math.cos(a) * 9)).Position,
			"ArenaGold"
		) -- design: sd/arenas2.js:170
	end
	for index, side in { -1, 1 } do
		ArenaKit.part(
			k,
			model,
			`TeamPanel{index}`,
			Vector3.new(0.2, 4, 5.4),
			port * CFrame.new(-1.15, 0, side * 3.2),
			if side < 0 then "ArenaTeamMint" else "ArenaTeamStrawberry"
		) -- design: sd/arenas2.js:171
	end
end

local function art(k: Kit)
	ArenaKit.floorHalves(k, "ArenaCourtCoral", "ArenaCourtAqua")
	ArenaKit.court(k, COURT)
	buildRails(k)
	local random = ArenaKit.rng(SEED)
	pebbles(k, random)
	clam(k, "GiantClamB", CLAM_Z, 0) -- design: sd/arenas2.js:145 (team A, ry 0)
	clam(k, "GiantClamA", -CLAM_Z, math.pi) -- design: sd/arenas2.js:127 (team B = team A turned 180 deg)
	aquarium(k, -1, random)
	aquarium(k, 1, random)
	reefEnd(k, 1, random)
	reefEnd(k, -1, random)
end

-- Public

-- Builds the new template tree, unparented and marked (Generated contract). Never yields, never changes the place.
function BubbleReefCourt.build(ctx: ArenaKit.BuildContext): ArenaKit.BuildResult
	return ArenaKit.build(ctx, {
		arenaId = ARENA_ID,
		generatorId = BubbleReefCourt.GENERATOR_ID,
		version = BubbleReefCourt.VERSION,
		rootName = BubbleReefCourt.ROOT_NAME,
		apron = "ArenaReefSand", -- design: sd/arenas2.js:122 floor_base sand
		padA = "ArenaCourtCoral",
		padB = "ArenaCourtAqua",
		jellyTransparency = 1 - 0.12, -- design: sd/arenas2.js:29 (opacity 0.12)
	}, art)
end

return BubbleReefCourt
