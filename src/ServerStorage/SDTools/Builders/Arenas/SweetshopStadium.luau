--!strict
-- SweetshopStadium: builds the arena template "Arena_SweetshopStadium", the "Bakery sports court - wafer walls, layer
-- cake, marshmallows" (design sd/arena.js, facts sd/main.js:438-440; phase 4 spec 2026-10-11 §2.1, §4.5, §4.6).
-- Server only, Edit mode only (ServerStorage.SDTools); Main's target "arena_sweetshop_stadium" runs build(ctx) and
-- swaps the tree into ServerStorage.SD_Templates. ArenaKit makes the gameplay frame (Candy Court's) and the cover
-- (World/Arenas); this module adds the art:
--   Floor     the mint and strawberry court halves, out to the walls
--   Markings  the design's white lines, team lines, centre ring and ring spawn marks (ArenaKit.court)
--   Rails     the cream perimeter cushions with their team-coloured caps, in the gutter
--   Decor     the cream apron, a Layer Cake behind each end (D1), the cupcake scoreboards, the side lollipops, 4 candy-cane
--             light poles, the stands with a seeded gumdrop crowd and the gumdrop columns.
-- Every design number carries its sd/arena.js line; out-of-bounds items keep their distance beyond the court edge
-- (spec §4.6, ArenaKit.at) and stay inside the 190-stud apron. Plain colours only (D6: the lamps and screens do not
-- glow). Tori are flat discs and lathes are cylinders or ellipsoids (spec §4.6, not feasible with parts).

local ArenaKit = require(script.Parent.ArenaKit)

-- Types

type Kit = ArenaKit.Kit

-- Constants

local ARENA_ID = "sweetshop_stadium"
local HALF_PI = math.pi / 2

local COURT: ArenaKit.CourtStyle = {
	line = "ArenaTrimWhite", -- design: sd/arena.js:18 court_line
	sideWidth = 1, -- design: sd/arena.js:29
	endWidth = 1, -- design: sd/arena.js:29 (end lines in the line colour)
	endA = "ArenaTrimWhite",
	endB = "ArenaTrimWhite",
	centreWidth = 2.2, -- design: sd/arena.js:30
	edgeWidth = 0.8, -- design: sd/arena.js:31
	zoneWidth = 0.8, -- design: sd/arena.js:32
	teamA = "ArenaTeamStrawberry", -- design: sd/arena.js:19 team_strawberry
	teamB = "ArenaTeamMint",
	halfA = "ArenaCourtStrawberry", -- design: sd/arena.js:27 court_teamB_strawberry
	halfB = "ArenaCourtMint", -- design: sd/arena.js:26 court_teamA_mint
	circle = "ring", -- design: sd/arena.js:34 ring(10, 11.2)
	padMarker = "ring", -- design: sd/arena.js:38
}

-- Perimeter cushions (sd/arena.js:43-51): rb(L / 2, 3.2, 3) cushions on the long sides, rb(3, 3.2, W) on the ends, team
-- caps 0.9 tall 0.3 deeper at y 3.25 (the side caps 1 shorter). Spec §4.5: 1.6 deep in the 2-stud gutter, the caps
-- deeper outward so they stay inside it.
local CUSHION_DEPTH = 1.6 -- spec §4.5 (design 3)
local CUSHION_HEIGHT = 3.2 -- design: sd/arena.js:45
local CAP_DEPTH = CUSHION_DEPTH * 3.3 / 3 -- design: sd/arena.js:46 (3.3 over a 3-deep cushion)
local CAP_HEIGHT = 0.9 -- design: sd/arena.js:46
local CAP_Y = 3.25 -- design: sd/arena.js:46
local CAP_SHORTER = 1 -- design: sd/arena.js:46 (L / 2 - 1)

-- Layer Cake (sd/arena.js:63-79), a backdrop behind each end (D1), its icing in that end's team colour. Spec §4.2 R7:
-- the front edge (the bottom rim, r 6.5 + 0.5) at |Z| 58.
local CAKE_Z = 65
local TIERS = { { 6.5, 4 }, { 5, 4 }, { 3.6, 3.4 } } -- design: sd/arena.js:66 { radius, height }
local ICING_EXTRA = 0.12 -- design: sd/arena.js:68 (r + 0.12, 0.7 tall)
local ICING_HEIGHT = 0.7
local RIM_TUBE = 0.5 -- design: sd/arena.js:69 TorusGeometry(r, 0.5): a flat disc of the torus' outer size
local DRIPS_PER_TIER = 6 -- design: sd/arena.js:71 has 18 per tier; a third for the part budget (D5)
local DRIP_RADIUS = 0.32 -- design: sd/arena.js:71 CapsuleGeometry(0.32, 0.6 + (k % 3) * 0.5)

-- Cupcake scoreboards (sd/arena.js:103-115) behind the cakes, at 0.9 scale (spec §4.6: the frosting stays inside the
-- apron).
local CUPCAKE_Z = 83 -- spec §4.6
local CUPCAKE_SCALE = 0.9

-- Lollipop landmarks (sd/arena.js:116-122) off the long sides, the candy facing the court.
local LOLLIPOP_STICK_HEIGHT = 26 -- design: sd/arena.js:118 C(0.7) x 26
-- The candy disc C(8) x 2 with 4 swirl tori a side (r 7.2 / 5.6 / 4.0 / 2.4, tube 0.55, strawberry / mint): as
-- concentric discs, each thicker than the one around it so every band shows on both faces.
local SWIRL_RADII = { 7.2, 5.6, 4.0, 2.4 } -- design: sd/arena.js:121
local SWIRL_TUBE = 0.55

-- Light poles (sd/arena.js:123-130): 13 cane segments C(0.8) x 2, white and red, and a lamp at y 27 facing the centre.
local POLE_SEGMENTS = 13 -- design: sd/arena.js:126

-- Stands (sd/arena.js:94-101): 4 tiers a side 4.5 deep at 7 + 4.5k beyond the court, h = 2.5 + 2.6k, sponge / cream;
-- 116 long (spec §4.6: the design's 200 over a 180 court); a seeded gumdrop crowd (the design's rng(5)), 30 a side
-- (spec §4.6, the design has about 290).
local STAND_LENGTH = 116 -- spec §4.6
local CROWD_PER_SIDE = 30
local CROWD_COLORS = { "ArenaTeamStrawberry", "ArenaTeamMint", "ArenaButter", "ArenaViolet", "ArenaCrowdBlue" } -- :94
local CROWD_SEED = 5 -- design: sd/arena.js:94 rng(5)

-- Gumdrop columns (sd/arena.js:52-54): lathe r 3, 6 tall; the corners in team colour, the long sides' middles cream.
-- Here just outside the walls (the design's sit on the cushion line, half inside the court); the end middles are left
-- out (spec §4.6: they would stand behind the pads in the Countdown camera).
local COLUMNS = { { -39, -55 }, { 39, -55 }, { -39, 55 }, { 39, 55 }, { -39, 0 }, { 39, 0 } }

-- Module table

local SweetshopStadium = {}
SweetshopStadium.GENERATOR_ID = "arena_sweetshop_stadium"
SweetshopStadium.VERSION = 1
SweetshopStadium.ROOT_NAME = "Arena_SweetshopStadium"
SweetshopStadium.ARENA_ID = ARENA_ID

-- Private

local function buildRails(k: Kit)
	local halfX, halfZ = k.layout.halfX, k.layout.halfZ
	local x = halfX + CUSHION_DEPTH / 2
	for _, side in { "A", "B" } do
		local sign = if side == "A" then -1 else 1
		local team = if side == "A" then "ArenaTeamStrawberry" else "ArenaTeamMint"
		for index, sx in { -1, 1 } do
			ArenaKit.part(
				k,
				k.rails,
				`{side}_Cushion{index}`,
				Vector3.new(CUSHION_DEPTH, CUSHION_HEIGHT, halfZ),
				CFrame.new(sx * (x + ArenaKit.LAYER), CUSHION_HEIGHT / 2, sign * halfZ / 2), -- the cap's face in front
				"ArenaCushionCream",
				"solid"
			) -- design: sd/arena.js:45
			ArenaKit.part(
				k,
				k.rails,
				`{side}_Cap{index}`,
				Vector3.new(CAP_DEPTH, CAP_HEIGHT, halfZ - CAP_SHORTER),
				CFrame.new(sx * (halfX + CAP_DEPTH / 2), CAP_Y, sign * halfZ / 2),
				team,
				"solid"
			) -- design: sd/arena.js:46
		end
		local endWidth = 2 * (halfX + CUSHION_DEPTH) -- closes the corners
		ArenaKit.part(
			k,
			k.rails,
			`{side}_CushionEnd`,
			Vector3.new(endWidth, CUSHION_HEIGHT, CUSHION_DEPTH),
			CFrame.new(0, CUSHION_HEIGHT / 2, sign * (halfZ + CUSHION_DEPTH / 2 + ArenaKit.LAYER)),
			"ArenaCushionCream",
			"solid"
		) -- design: sd/arena.js:49
		ArenaKit.part(
			k,
			k.rails,
			`{side}_CapEnd`,
			Vector3.new(endWidth - CAP_SHORTER, CAP_HEIGHT, CAP_DEPTH),
			CFrame.new(0, CAP_Y, sign * (halfZ + CAP_DEPTH / 2)),
			team,
			"solid"
		) -- design: sd/arena.js:50
	end
end

-- The Layer Cake (sd/arena.js:63-79) standing at (0, z): 3 tiers, icing bands, cream rims, drips, the strawberry.
local function cake(k: Kit, name: string, z: number, icing: string)
	local model, frame = ArenaKit.group(k, name, 0, z, 0)
	local y = 0
	for index, tier in TIERS do
		local radius, height = tier[1], tier[2]
		ArenaKit.disc(
			k,
			model,
			`Tier{index}`,
			2 * radius,
			height,
			frame:PointToWorldSpace(Vector3.new(0, y + height / 2, 0)),
			"ArenaCakeSponge"
		)
		ArenaKit.disc(
			k,
			model,
			`Icing{index}`,
			2 * (radius + ICING_EXTRA),
			ICING_HEIGHT,
			frame:PointToWorldSpace(Vector3.new(0, y + height - ICING_HEIGHT / 2 + ArenaKit.LAYER, 0)), -- over the tier top
			icing
		) -- design: sd/arena.js:68
		ArenaKit.disc(
			k,
			model,
			`Rim{index}`,
			2 * (radius + RIM_TUBE),
			2 * RIM_TUBE,
			frame:PointToWorldSpace(Vector3.new(0, y + height, 0)),
			"ArenaWaferCream"
		) -- design: sd/arena.js:69
		for drip = 0, DRIPS_PER_TIER - 1 do
			local step = drip * 3 -- the design's k = 0, 3, 6, ... of its 18
			local a = step / 18 * 2 * math.pi + (index - 1)
			local length = 0.6 + (drip % 3) * 0.5 + 2 * DRIP_RADIUS
			ArenaKit.disc(
				k,
				model,
				`Drip{index}_{drip + 1}`,
				2 * DRIP_RADIUS,
				length,
				frame:PointToWorldSpace(
					Vector3.new(
						math.cos(a) * (radius + 0.1),
						y + height - 0.9 - (drip % 3) * 0.25,
						math.sin(a) * (radius + 0.1)
					)
				),
				"ArenaWaferCream"
			) -- design: sd/arena.js:71
		end
		y += height
	end
	-- The upside-down lathe strawberry (r 1.9, 3.4 tall, from y - 0.2) and its 5 leaves (sd/arena.js:75-77).
	ArenaKit.ellipsoid(
		k,
		model,
		"Strawberry",
		Vector3.new(3.8, 3.4, 3.8),
		frame * CFrame.new(0, y - 0.2 + 1.7, 0),
		"ArenaStrawberryRed"
	)
	for leaf = 0, 4 do
		local a = leaf / 5 * 2 * math.pi
		ArenaKit.ellipsoid(
			k,
			model,
			`Leaf{leaf + 1}`,
			Vector3.new(2.2, 0.5, 1.0),
			frame * CFrame.new(math.cos(a) * 0.9, y + 3.3, math.sin(a) * 0.9) * CFrame.Angles(0, -a, 0.3),
			"ArenaFrogGreen"
		) -- design: sd/arena.js:77 SphereGeometry(1) scaled (1.1, 0.25, 0.5)
	end
end

-- The cupcake scoreboard (sd/arena.js:103-115) at (0, z); sx is the design's end sign (-1 for the mint end).
local function cupcake(k: Kit, name: string, z: number, sx: number, liner: string)
	local s = CUPCAKE_SCALE
	local model, frame = ArenaKit.group(k, name, 0, z, ArenaKit.yaw(0))
	ArenaKit.disc(k, model, "Liner", (12 + 9.5) * s, 12 * s, frame:PointToWorldSpace(Vector3.new(0, 6 * s, 0)), liner) -- :105
	ArenaKit.ellipsoid(
		k,
		model,
		"Frosting",
		Vector3.new(26, 16, 26) * s,
		frame * CFrame.new(0, 12 * s, 0),
		"ArenaWaferCream"
	) -- design: sd/arena.js:109 superF(13, 8, 13)
	local board = frame * CFrame.new(-sx * 9 * s, 19 * s, 0) * CFrame.Angles(0, -sx * HALF_PI, 0) -- design: :110
	ArenaKit.part(k, model, "Frame", Vector3.new(18, 8, 1.4) * s, board, "ArenaPlum") -- design: sd/arena.js:111
	ArenaKit.part(
		k,
		model,
		"Screen",
		Vector3.new(15.5, 5.8, 0.2) * s,
		board * CFrame.new(0, 0, 0.75 * s),
		"ArenaScoreboardScreen"
	) -- design: sd/arena.js:112
	for index, sign in { -1, 1 } do
		ArenaKit.part(
			k,
			model,
			`TeamPanel{index}`,
			Vector3.new(6, 3, 0.1) * s,
			board * CFrame.new(sign * 4 * s, 0, 0.88 * s),
			if sign < 0 then "ArenaTeamMint" else "ArenaTeamStrawberry"
		) -- design: sd/arena.js:113
	end
	ArenaKit.ball(k, model, "Cherry", 4 * s, frame:PointToWorldSpace(Vector3.new(0, 25.5 * s, 0)), "ArenaStrawberryRed") -- :114
end

-- The lollipop landmark (sd/arena.js:116-122) at (x, 0), its candy facing the court along X.
local function lollipop(k: Kit, name: string, x: number)
	local model, frame = ArenaKit.group(k, name, x, 0, 0)
	ArenaKit.disc(
		k,
		model,
		"Stick",
		1.4,
		LOLLIPOP_STICK_HEIGHT,
		frame:PointToWorldSpace(Vector3.new(0, LOLLIPOP_STICK_HEIGHT / 2, 0)),
		"ArenaCushionCream"
	) -- design: sd/arena.js:118
	local candy = frame * CFrame.new(0, LOLLIPOP_STICK_HEIGHT, 0) -- a Cylinder's axis is its X: the court direction
	local bands = { { radius = 8, color = "ArenaWaferCream" } } -- design: sd/arena.js:120 C(8) x 2, cream
	for index, radius in SWIRL_RADII do
		local swirl = if index % 2 == 1 then "ArenaTeamStrawberry" else "ArenaTeamMint"
		table.insert(bands, { radius = radius + SWIRL_TUBE, color = swirl })
		table.insert(bands, { radius = radius - SWIRL_TUBE, color = "ArenaWaferCream" })
	end
	for index, band in bands do
		ArenaKit.rod(k, model, `Candy{index}`, 2 * band.radius, 2 + 0.1 * (index - 1), candy, band.color)
	end
end

-- The candy-cane light pole (sd/arena.js:123-130) at (x, z), its lamp facing the court's centre.
local function lightPole(k: Kit, name: string, x: number, z: number)
	local model, frame = ArenaKit.group(k, name, x, z, math.atan2(-x, -z))
	local height = POLE_SEGMENTS * 2
	ArenaKit.disc(
		k,
		model,
		"Pole",
		1.6,
		height,
		frame:PointToWorldSpace(Vector3.new(0, height / 2, 0)),
		"ArenaCaneWhite"
	)
	for segment = 1, POLE_SEGMENTS - 1, 2 do -- the red segments (k odd)
		ArenaKit.disc(
			k,
			model,
			`Stripe{(segment + 1) // 2}`,
			1.7,
			2,
			frame:PointToWorldSpace(Vector3.new(0, 1 + segment * 2, 0)),
			"ArenaStrawberryRed"
		) -- design: sd/arena.js:126
	end
	local lamp = frame * CFrame.new(0, 27, 0) -- design: sd/arena.js:127 (facing the centre)
	ArenaKit.part(k, model, "LampHousing", Vector3.new(7, 3, 2.4), lamp, "ArenaPlum") -- design: sd/arena.js:128
	ArenaKit.part(k, model, "LampFace", Vector3.new(6, 2.2, 0.3), lamp * CFrame.new(0, 0, 1.15), "ArenaLampGlow") -- :129
end

-- The stands on both long sides (sd/arena.js:94-101) with a seeded gumdrop crowd.
local function stands(k: Kit)
	local random = ArenaKit.rng(CROWD_SEED)
	for _, sz in { -1, 1 } do
		local model, frame = ArenaKit.group(k, if sz < 0 then "StandsWest" else "StandsEast", 0, 0, 0)
		local placed = 0
		for tier = 0, 3 do
			local x = sz * (k.layout.halfX + 7 + tier * 4.5) -- design: sd/arena.js:97
			local height = 2.5 + tier * 2.6
			ArenaKit.box(
				k,
				model,
				frame,
				`Tier{tier + 1}`,
				Vector3.new(4.5, height, STAND_LENGTH),
				x,
				0,
				0,
				if tier % 2 == 1 then "ArenaWaferCream" else "ArenaCakeSponge"
			) -- design: sd/arena.js:98
			local seats = CROWD_PER_SIDE // 4 + (if tier < CROWD_PER_SIDE % 4 then 1 else 0) -- 8, 8, 7, 7
			for seat = 1, seats do
				local z = (seat - 0.5) / seats * STAND_LENGTH - STAND_LENGTH / 2 + (random() - 0.5)
				local scale = 0.85 + random() * 0.35 -- design: sd/arena.js:99
				local color = CROWD_COLORS[math.floor(random() * #CROWD_COLORS) + 1]
				placed += 1
				ArenaKit.ellipsoid(
					k,
					model,
					string.format("Gumdrop%02d", placed),
					Vector3.new(2.4, 4.9, 2.4) * scale, -- the lathe gumdrop r 1.2 x 2.45, its lower half in the tier
					CFrame.new(x, height, z),
					color
				)
			end
		end
	end
end

local function columns(k: Kit)
	for index, spot in COLUMNS do
		local model, frame = ArenaKit.group(k, `GumdropColumn{index}`, spot[1], spot[2], 0)
		local color = if spot[2] == 0
			then "ArenaCushionCream"
			elseif spot[2] > 0 then "ArenaTeamMint"
			else "ArenaTeamStrawberry"
		-- The lathe (r 3 at the foot, 2.7 at 4.2, a dome to 6): a cylinder and an ellipsoid dome.
		ArenaKit.disc(k, model, "Base", 6, 4.2, frame:PointToWorldSpace(Vector3.new(0, 2.1, 0)), color) -- :52
		ArenaKit.ellipsoid(k, model, "Dome", Vector3.new(5.4, 3.6, 5.4), frame * CFrame.new(0, 4.2, 0), color) -- :52
	end
end

local function art(k: Kit)
	ArenaKit.floorHalves(k, "ArenaCourtStrawberry", "ArenaCourtMint")
	ArenaKit.court(k, COURT)
	buildRails(k)
	cake(k, "LayerCakeB", CAKE_Z, "ArenaTeamMint")
	cake(k, "LayerCakeA", -CAKE_Z, "ArenaTeamStrawberry")
	cupcake(k, "CupcakeScoreboardB", CUPCAKE_Z, -1, "ArenaTeamMint")
	cupcake(k, "CupcakeScoreboardA", -CUPCAKE_Z, 1, "ArenaTeamStrawberry")
	for index, z in { -91, 91 } do
		local x = ArenaKit.at(k, 0, z) -- design: sd/arena.js:117 (z = +-(W / 2 + 26))
		lollipop(k, `Lollipop{index}`, x)
	end
	for index, spot in { { -104, -88 }, { 104, -88 }, { -104, 88 }, { 104, 88 } } do
		local x, z = ArenaKit.at(k, spot[1], spot[2]) -- design: sd/arena.js:125
		lightPole(k, `LightPole{index}`, x, z)
	end
	stands(k)
	columns(k)
end

-- Public

-- Builds the new template tree, unparented and marked (Generated contract). Never yields, never changes the place.
function SweetshopStadium.build(ctx: ArenaKit.BuildContext): ArenaKit.BuildResult
	return ArenaKit.build(ctx, {
		arenaId = ARENA_ID,
		generatorId = SweetshopStadium.GENERATOR_ID,
		version = SweetshopStadium.VERSION,
		rootName = SweetshopStadium.ROOT_NAME,
		apron = "ArenaFloorCream", -- design: sd/arena.js:25 floor_base
		padA = "ArenaCourtStrawberry",
		padB = "ArenaCourtMint",
		jellyTransparency = 1 - 0.13, -- design: sd/arena.js:41 (opacity 0.13)
	}, art)
end

return SweetshopStadium
