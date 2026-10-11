--!strict
-- BubbleReefCourt: the cover of Bubble Reef Court, the "Dry aquarium court - sponge walls, giant clam, sea-glass
-- pillars, brain coral" (design sd/arenas2.js:116-175, facts sd/main.js:449-452), for the arena registry
-- (World/Arenas). Data only.
-- 1v1 set (phase 4 spec §4.3, D3): 3 Sponge Walls, 2 Sea-glass Pillars and 1 Brain Coral per side, listed for Side B
-- by their design position (the design's team A, sd/arenas2.js:145-148); World/Arenas maps them and point-reflects
-- Side A, which is exactly the design's own rotational symmetry (sd/arenas2.js:127 place()). The first pillar reaches
-- the pad-to-pad lane and is slid out of it (R5, World/Arenas). Dropped (spec §4.3): the Giant Clam (lane and pad: the
-- builder stands it behind each end, D1), brain coral 1 (lane) and 3 (on the pad).

local Recipe = require(script.Parent.Recipe)

local block = Recipe.block

-- Sponge Wall (sd/arenas2.js:128-133; proxy 12 x 7 x 4.2, "full"): rb(12, 7, 4.2) at y 3.5; 3 top lumps
-- pill(3.4 / 4.2 / 2.4, 1.6, 3.6) at x -3.6 / 1 / 4.6, y 7; 26 pores SPH(0.35-0.7) flattened on both faces (z +-2.12).
-- R2: length 12 -> 8 (x 2/3, lumps with it). R1 (spec §4.4): the body 7.2 tall, the lumps centred on its top, top 8.
local LEN = 8 / 12 -- R2
local BODY = Vector3.new(12 * LEN, 7.2, 4.2) -- spec §4.4; design: sd/arenas2.js:130 rb(12, 7, 4.2)
local LUMPS = { { x = -3.6, width = 3.4 }, { x = 1, width = 4.2 }, { x = 4.6, width = 2.4 } } -- design: sd/arenas2.js:130
local LUMP_HEIGHT = 1.6 -- design: sd/arenas2.js:130 pill(w, 1.6, 3.6)
local LUMP_DEPTH = 3.6 -- design: sd/arenas2.js:130
local PORE_Z = 2.12 -- design: sd/arenas2.js:131 (f * 2.12)
local PORE_THICKNESS = 0.3 -- design: sd/arenas2.js:131 (spheres flattened to 0.4 of their size)
-- Pore spots (x, y, diameter): NOT IN DESIGN (the design scatters 26 at random with rng(41)); 3 per face, sizes in the
-- design's range (r 0.35-0.7, sd/arenas2.js:131), spread over the face.
local PORES = {
	{ face = 1, x = -2.4, y = 2.0, diameter = 1.1 },
	{ face = 1, x = 0.6, y = 4.6, diameter = 1.4 },
	{ face = 1, x = 2.6, y = 2.8, diameter = 0.8 },
	{ face = -1, x = -1.8, y = 4.2, diameter = 0.9 },
	{ face = -1, x = 1.4, y = 1.6, diameter = 1.2 },
	{ face = -1, x = 2.9, y = 5.6, diameter = 0.7 },
}

local function spongeWall(): { Recipe.Part }
	local parts: { Recipe.Part } = { block("Body", BODY, 0, BODY.Y / 2, 0, "ArenaSponge") }
	for index, lump in LUMPS do
		table.insert(
			parts,
			block(
				`Lump{index}`,
				Vector3.new(lump.width * LEN, LUMP_HEIGHT, LUMP_DEPTH),
				lump.x * LEN,
				BODY.Y,
				0,
				"ArenaSponge"
			)
		)
	end
	for index, pore in PORES do
		table.insert(
			parts,
			Recipe.rodZ(
				`Pore{index}`,
				pore.diameter,
				PORE_THICKNESS,
				pore.x,
				pore.y,
				pore.face * PORE_Z,
				"ArenaSpongePore"
			)
		)
	end
	return parts
end

-- Sea-glass Pillar (sd/arenas2.js:144; proxy cylinder r 3 x 9.6, "full cover, narrow"): hexagonal prism C(2.6 top,
-- 3 bottom, 9, 6 sides) at y 4.5, hex cap C(2.75, 2.6, 0.7) at y 9.3, 5 barnacles SPH(0.5) on r 2.75. A Roblox part
-- cannot be a hexagon or taper: a regular hexagon of circumradius R is the union of 3 blocks R x (R * sqrt 3) turned
-- 0 / 60 / 120 deg, with R the mean radius 2.8 (spec §4.4) and the cap's 2.75; the design's hexagon has a corner on
-- its local +z (three.js CylinderGeometry), and so does this one.
local PILLAR_RADIUS = (2.6 + 3) / 2 -- design: sd/arenas2.js:144 C(2.6, 3, 9, 6), mean
local PILLAR_HEIGHT = 9 -- design: sd/arenas2.js:144
local CAP_RADIUS = 2.75 -- design: sd/arenas2.js:144 C(2.75, 2.6, 0.7, 6)
local CAP_HEIGHT = 0.7 -- design: sd/arenas2.js:144
local CAP_Y = 9.3 -- design: sd/arenas2.js:144
local BARNACLE = 2 * 0.5 -- design: sd/arenas2.js:144 SPH(0.5)
local BARNACLE_RADIUS = 2.75 -- design: sd/arenas2.js:144 (cos a * 2.75)
-- Barnacle spots (angle in degrees, height): NOT IN DESIGN (random in the design: angle r() * TAU, height 1 + r() * 6,
-- sd/arenas2.js:144); spread evenly around and up the pillar.
local BARNACLES = { { 20, 1.6 }, { 95, 5.4 }, { 170, 3.0 }, { 245, 6.4 }, { 320, 2.4 } }
local SQRT3 = math.sqrt(3)

local function hexagon(prefix: string, radius: number, height: number, y: number, color: string): { Recipe.Part }
	local parts: { Recipe.Part } = {}
	for index, degrees in { 0, 60, 120 } do
		table.insert(
			parts,
			Recipe.turned(
				if prefix == "" and index == 1 then "Body" else `{if prefix == "" then "Prism" else prefix}{index}`,
				Vector3.new(radius * SQRT3, height, radius),
				CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(degrees), 0),
				color
			)
		)
	end
	return parts
end

local function pillar(): { Recipe.Part }
	local parts = hexagon("", PILLAR_RADIUS, PILLAR_HEIGHT, PILLAR_HEIGHT / 2, "ArenaSeaGlass")
	for _, part in hexagon("Cap", CAP_RADIUS, CAP_HEIGHT, CAP_Y, "ArenaSeaGlassTop") do
		table.insert(parts, part)
	end
	for index, spot in BARNACLES do
		local angle = math.rad(spot[1])
		table.insert(
			parts,
			Recipe.ball(
				`Barnacle{index}`,
				BARNACLE,
				math.sin(angle) * BARNACLE_RADIUS,
				spot[2],
				math.cos(angle) * BARNACLE_RADIUS,
				"ArenaTrimWhite"
			)
		)
	end
	return parts
end

-- Brain Coral (sd/arenas2.js:142-143; "half cover", lower body only): the upper half of a 7.6 x 3.4 superellipsoid
-- dome -> a Ø7.6 ball sunk 0.4 into the floor (spec §4.4 R4: top 3.4); its base torus (r 3.8, tube 0.45) -> a disc,
-- capped at Ø8 (spec §4.4). The wrinkles are NOT FEASIBLE with parts.
local BRAIN_DIAMETER = 2 * 3.8 -- design: sd/arenas2.js:142 superF(3.8, 3.4, 3.8)
local BRAIN_TOP = 3.4 -- design: sd/arenas2.js:142

local BRAIN: { Recipe.Part } = {
	Recipe.ball("Body", BRAIN_DIAMETER, 0, BRAIN_TOP - BRAIN_DIAMETER / 2, 0, "ArenaBrainCoral"),
	Recipe.disc("Base", 8, 0.6, 0, 0.3, 0, "ArenaReefRockWarm"), -- spec §4.4; design: sd/arenas2.js:143 TOR(3.8, 0.45)
}

local SPONGE = spongeWall()
local PILLAR = pillar()

return {
	id = "bubble_reef_court",
	templateName = "Arena_BubbleReefCourt",
	generatorId = "arena_bubble_reef_court",
	design = { file = "sd/arenas2.js", L = 184, W = 136 } :: Recipe.Design, -- design: sd/arenas2.js:9
	swapA = {} :: { [string]: string },
	-- Side B, by design position (x, z, ry) of team A (sd/arenas2.js:145-148).
	cover = {
		{ name = "Sponge1", kind = "full", source = "sd/arenas2.js:146", x = -28, z = -26, ry = 0.5, parts = SPONGE },
		{ name = "Sponge2", kind = "full", source = "sd/arenas2.js:146", x = -62, z = 32, ry = -0.25, parts = SPONGE },
		{ name = "Sponge3", kind = "full", source = "sd/arenas2.js:146", x = -24, z = 40, ry = -0.65, parts = SPONGE },
		{ name = "Pillar1", kind = "full", source = "sd/arenas2.js:148", x = -38, z = 14, ry = 0, parts = PILLAR },
		{ name = "Pillar2", kind = "full", source = "sd/arenas2.js:148", x = -68, z = -38, ry = 0, parts = PILLAR },
		-- design brain coral 2 (sd/arenas2.js:147): brain 1 sits on the lane and brain 3 on the pad (spec §4.3)
		{ name = "Brain1", kind = "low", source = "sd/arenas2.js:147", x = -40, z = -48, ry = 0, parts = BRAIN },
	},
}
