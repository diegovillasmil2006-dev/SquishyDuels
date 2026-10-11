--!strict
-- WorldLayout: every coordinate, size and tier of the lobby (DESIGN §7.5-§7.7, the Grip pods of §17.6 and the giant
-- pads of §17.6.1) and of the arena template (§5.3, §7.8), as frozen data, plus small pure helpers. Shared: required
-- by the edit-time generators and Verify (through the injected Shared clone; no requires here) and at runtime
-- (station positions and tiers, return points, waypoints, zones). Requiring it has no side effects: it only builds
-- and deep-freezes plain tables.
--
-- Frames and units (studs):
-- * Lobby: world coordinates. Floor top Y = 0. North = -Z. The spawn faces -Z, toward the duel gate (§7.5).
-- * Arena: relative to the template's `Origin` part (floor centre, floor top Y = 0); long axis = Z; Side A = Z < 0
--   ("Strawberry side"), Side B = Z > 0 ("Mint side"). The slot origins live in Config.Duel.Arena.SlotOrigins.
-- * Box: `position` = centre; `size` = W × H × D in the part's own frame; `facing` = the unit direction its Front
--   (-Z) face looks toward, i.e. CFrame.lookAt(position, position + facing) (boxCFrame). Without `facing`, or with a
--   vertical one (floor plates), the part is not rotated and `size` is world X × Y × Z, as in DESIGN's tables.
-- * Disc: an upright cylinder (`position` = centre, `diameter`, `height`). Roblox Cylinder parts have their axis on
--   X, so builders rotate them 90° about Z.
-- * Volume: an axis-aligned invisible box (`position` = centre, `size`): keep-clear volumes, zones, audio zones,
--   boundaries, the practice throw box.
-- * `color` fields are Art/Palette token names (builders use Palette[color]). `*Key` fields are Strings keys, except
--   `musicKey` / `ambienceKey` (AssetTable sound slots).
-- * A squeeze station's `tier` is its GripTier (§17.4): 1 = Foam Mats, 2-4 = the giant pads. Server and client read
--   the tier here by stationId (stationTier), never from the client or the GripTier attribute (§17.6).
-- Values DESIGN does not state are marked "reading (not in DESIGN, provisional)".

-- Types

export type Box = {
	position: Vector3,
	size: Vector3,
	facing: Vector3?,
	color: string?,
}

export type Disc = {
	position: Vector3,
	diameter: number,
	height: number,
	color: string?,
}

export type Volume = {
	name: string,
	position: Vector3,
	size: Vector3,
}

export type KeepClearVolume = Volume & {
	-- station: in front of a station, never containing its body; station volumes never overlap each other.
	-- aisle: a walkway; may overlap stations. prompt: the §7.7 5-stud radius around a ProximityPrompt (as a box); it
	-- holds its own station's body (Verify exempts station bodies) and may overlap any other volume.
	kind: "aisle" | "station" | "prompt",
}

export type Prompt = {
	actionKey: string, -- ProximityPrompt.ActionText
	altActionKey: string?, -- the toggled (Leave Queue) or locally relabelled (Shop Squishies) text
	position: Vector3, -- where the prompt's Attachment sits
	maxDistance: number,
	requiresLineOfSight: boolean,
}

export type SignLine = {
	name: string, -- TextLabel name (stable for binders and Verify)
	textKey: string?, -- static text: the label carries SD_TextKey = textKey (WorldBinder writes it)
	bakeKey: string?, -- no SD_TextKey: the builder bakes Strings.format(bakeKey, bakeArgs or its own args)
	bakeArgs: { [string]: number }?,
	live: boolean, -- a runtime binder rewrites this label (never two writers: live labels have no SD_TextKey)
	clientKeys: { string }?, -- other Strings keys a binder writes into this label
	letterHeight: number, -- target letter height in studs (§7.7); builders fit with TextScaled + a size cap
	font: "heading" | "body", -- heading = FredokaOne, body = BuilderSansBold (§7.7)
}

export type Sign = {
	id: string,
	owner: string, -- the station model the sign belongs to (it streams with it)
	part: string?, -- the station part that carries the SurfaceGui instead of a separate panel
	position: Vector3,
	size: Vector3,
	facing: Vector3, -- unit normal of the readable face; (0, 1, 0) for floor plates
	face: "Front" | "Top",
	textUp: Vector3?, -- floor plates only: the direction the top of the text points
	tag: string?, -- extra tag besides SD_Sign (SD_GripSign)
	tier: number?, -- SD_GripSign: GripTier
	align: ("center" | "top")?, -- vertical placement of the lines on the panel (default "center")
	lines: { SignLine },
}

export type Station = {
	id: string, -- "squeeze_01".."squeeze_09"
	tier: number, -- GripTier
	kind: "mat" | "giant",
	model: string,
	position: Vector3, -- the point the server measures from: mat centre / giant pad collision box centre
	top: number, -- Y of the standing surface: mat top / collision top
	halfSize: number, -- mats: radius; giant pads: half the square footprint
	padKey: string?, -- giant pads: "jelly" | "marshmallow" | "royal"
}

export type Gate = Disc & { transparency: number }

export type GiantPad = {
	key: string,
	stationId: string,
	tier: number,
	model: string, -- "GiantPad_<key>", Atomic, tagged SD_GiantPad (GripTier, PadKey)
	blueprintId: string, -- Art/SquishyBlueprints body + face
	center: Vector3, -- floor point under the pad centre
	footprint: number, -- square side of the visual pad
	cornerRadius: number,
	restTop: number, -- visual top at rest
	sinkDepth: number,
	collision: Box, -- the invisible station box (Transparency 1, CanCollide true, CanTouch false)
	collisionTop: number,
	faceDirection: Vector3,
	look: { body: string, top: string, accent: string?, transparency: number },
	gate: Gate, -- the jelly cylinder, tagged SD_GripGate (GripTier)
	signPost: Box,
	signId: string,
	tileSpacing: number, -- path B quilted tiles (§17.6.1)
	tileSize: Vector3,
	tilesPerSide: number,
}

export type Target = {
	id: string, -- TargetId
	lane: number,
	distance: number, -- studs from the firing line
	position: Vector3, -- floor point under the target (rail centre for the moving one)
	moving: boolean,
	railLength: number, -- along Z, centred on `position`; 0 = static
	period: number, -- seconds; 0 = static
	nameKey: string, -- nameplate text (a target, never shown as a player)
}

export type Pedestal = {
	slot: number, -- 1-8, catalog order
	position: Vector3,
	size: Vector3,
	prompt: Prompt,
}

export type AudioZone = Volume & {
	zoneId: string,
	priority: number,
	musicKey: string,
	musicMul: number,
	ambienceKey: string,
}

export type Activity = {
	name: string,
	points: { Vector3 }, -- floor points a player walks to (approach points, mat or pad centres)
	pod: boolean, -- a Grip pod: the G-D route exception applies (§17.0, §17.6)
}

export type ReturnPoint = {
	slot: number,
	position: Vector3, -- floor point
	facing: Vector3,
}

-- Constants

local NORTH = Vector3.new(0, 0, -1)
local SOUTH = Vector3.new(0, 0, 1)
local EAST = Vector3.new(1, 0, 0)
local WEST = Vector3.new(-1, 0, 0)
local UP = Vector3.new(0, 1, 0)

local KEEP_CLEAR_BOTTOM = 0.5 -- §7.7 props rule 3: nothing collidable between Y 0.5 and 24 above walkable floor
local KEEP_CLEAR_TOP = 24
local KEEP_CLEAR_MARGIN = 0.5 -- reading: gap left between a keep-clear volume and a station body
local POD_KEEP_CLEAR_LIFT = 0.1 -- pod volumes start this far above the collision top, so the station box is outside
local PROMPT_KEEP_CLEAR_RADIUS = 5 -- §7.7 props rule 1: "5-stud radius around every prompt" (kept as a 10 × 10 box)
local PROMPT_DISTANCE = 10 -- §7.6 prompt defaults (V)
local INSPECT_DISTANCE = 12 -- §7.6 collection pedestals

local QUEST_YAW_DEG = 20 -- §7.6: the quest board faces +X, yawed 20° toward the spawn (+Z)
local QUEST_FACING = Vector3.new(math.cos(math.rad(QUEST_YAW_DEG)), 0, math.sin(math.rad(QUEST_YAW_DEG)))

-- Private: builders of plain data ---------------------------------------------------------------------------------

-- An axis-aligned volume from its bounds.
local function span(name: string, minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number)
	return {
		name = name,
		position = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2),
		size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ),
	}
end

local function keepClear(
	name: string,
	kind: "aisle" | "station" | "prompt",
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	minY: number?
): KeepClearVolume
	local volume = span(name, minX, maxX, minY or KEEP_CLEAR_BOTTOM, KEEP_CLEAR_TOP, minZ, maxZ)
	return {
		name = volume.name,
		kind = kind,
		position = volume.position,
		size = volume.size,
	}
end

local function prompt(actionKey: string, position: Vector3, altActionKey: string?): Prompt
	return {
		actionKey = actionKey,
		altActionKey = altActionKey,
		position = position,
		maxDistance = PROMPT_DISTANCE,
		requiresLineOfSight = true,
	}
end

local function line(name: string, textKey: string, letterHeight: number, font: "heading" | "body"): SignLine
	return { name = name, textKey = textKey, live = false, letterHeight = letterHeight, font = font }
end

local function liveLine(name: string, bakeKey: string?, letterHeight: number, clientKeys: { string }?): SignLine
	return {
		name = name,
		bakeKey = bakeKey,
		live = true,
		clientKeys = clientKeys,
		letterHeight = letterHeight,
		font = "body",
	}
end

-- A point `right` studs along the box's right vector and `forward` studs along its facing, at height `y`.
local function offsetFrom(center: Vector3, facing: Vector3, right: number, forward: number, y: number): Vector3
	local rightVector = facing:Cross(UP) -- CFrame.lookAt's RightVector = LookVector × UpVector
	local flat = center + rightVector * right + facing * forward
	return Vector3.new(flat.X, y, flat.Z)
end

-- Private: lobby frame, perimeter and boundaries (§7.5, §7.7) ------------------------------------------------------

local Lobby = {
	floorTopY = 0,
	footprint = { minX = -64, maxX = 64, minZ = -56, maxZ = 56 }, -- 128 × 112
	interior = { minX = -60, maxX = 60, minZ = -52, maxZ = 52 }, -- walkable; shelving fills the outer 4 studs
	baseSlab = { position = Vector3.new(0, -1, 0), size = Vector3.new(148, 2, 132), color = "Vanilla" } :: Box,
	spawnCamera = Vector3.new(0, 9, 52), -- the default camera ≈ 12 studs behind the spawn (§7.7 sightlines)
	Shelves = {
		unitSize = Vector3.new(16, 16, 4), -- W × H × D: Cocoa wood, pastel back panel, jars, mini squishies (scale 0.8)
		color = "Cocoa",
		archGap = { minX = -14, maxX = 14 }, -- the north wall stays open here for the duel arch
		-- Runs along the walls: a straight line through the middle of the 4-deep strip, `facing` into the lobby.
		-- Builders tile each run with units and cut the last one to fit. Reading: the north runs stop at |X| = 22
		-- (not 14) so the toy-block stacks at (±20, 0, -53) do not stand inside a shelf.
		runs = {
			{ name = "NorthWest", from = Vector3.new(-64, 0, -54), to = Vector3.new(-22, 0, -54), facing = SOUTH },
			{ name = "NorthEast", from = Vector3.new(22, 0, -54), to = Vector3.new(64, 0, -54), facing = SOUTH },
			{ name = "South", from = Vector3.new(-64, 0, 54), to = Vector3.new(64, 0, 54), facing = NORTH },
			{ name = "West", from = Vector3.new(-62, 0, -52), to = Vector3.new(-62, 0, 52), facing = EAST },
			{ name = "East", from = Vector3.new(62, 0, -52), to = Vector3.new(62, 0, 52), facing = WEST },
		},
	},
	-- Invisible walls (§7.7): Transparency 1, CanCollide true, CanQuery false, CanTouch false, tag SD_Boundary.
	-- Reading: walls stand on the floor (Y 0..60).
	Boundaries = {
		span("WestWall", -68, -64, 0, 60, -66, 66),
		span("EastWall", 64, 68, 0, 60, -66, 66),
		span("NorthWall", -66, 66, 0, 60, -60, -56),
		span("SouthWall", -66, 66, 0, 60, 56, 60),
	} :: { Volume },
}

-- Private: stations (§7.6) -----------------------------------------------------------------------------------------

local Spawn = {
	model = "Spawn",
	tag = "SD_LobbySpawn",
	-- SpawnLocation: top Y 0.05, Neutral, Duration 0 (no forcefield), faces -Z.
	location = {
		position = Vector3.new(0, -0.45, 40),
		size = Vector3.new(12, 1, 8),
		facing = NORTH,
		color = "Bubblegum",
	} :: Box,
	top = 0.05,
	-- Logo floor plate 24 × 0.05 × 8 at (0, ·, 28). Reading: DESIGN's Y 0.03 puts its top (0.055) under the promenade
	-- carpet (top 0.06) and edge strips (top 0.07) it overlaps, hiding the middle of "SQUISHY DUELS"; it lies on the
	-- strips instead (Y 0.07..0.12). Decor: it never collides.
	logoPlate = { position = Vector3.new(0, 0.095, 28), size = Vector3.new(24, 0.05, 8), color = "Cream" } :: Box,
}

local Promenade = {
	carpet = { position = Vector3.new(0, 0.03, -6), size = Vector3.new(16, 0.06, 84), color = "Bubblegum" } :: Box, -- Z -48..36
	-- Cream edge strips 0.4 wide. Reading: just outside the carpet's long edges, 0.07 tall so they never z-fight it.
	edgeStrips = {
		{ position = Vector3.new(-8.2, 0.035, -6), size = Vector3.new(0.4, 0.07, 84), color = "Cream" },
		{ position = Vector3.new(8.2, 0.035, -6), size = Vector3.new(0.4, 0.07, 84), color = "Cream" },
	} :: { Box },
}

local questBoard: Box = { position = Vector3.new(-17, 4.5, 26), size = Vector3.new(9, 6, 0.6), facing = QUEST_FACING }
local QuestBoard = {
	model = "QuestBoard",
	tag = "SD_QuestBoard",
	board = questBoard, -- Cardboard centre, Cocoa frame, three note cards (decor on the board face)
	-- Reading: two 0.6-wide posts behind the board ends, floor to the board middle.
	posts = {
		{
			position = offsetFrom(questBoard.position, QUEST_FACING, -4, -0.5, 2.25),
			size = Vector3.new(0.6, 4.5, 0.6),
			facing = QUEST_FACING,
			color = "Cocoa",
		},
		{
			position = offsetFrom(questBoard.position, QUEST_FACING, 4, -0.5, 2.25),
			size = Vector3.new(0.6, 4.5, 0.6),
			facing = QUEST_FACING,
			color = "Cocoa",
		},
	} :: { Box },
	approach = Vector3.new(-13, 0, 26),
	prompt = prompt("prompt.viewQuests", Vector3.new(-15.5, 3, 26)),
}

local DailyStand = {
	model = "DailyStand",
	tag = "SD_DailyStand",
	pedestal = { position = Vector3.new(17, 0.75, 26), diameter = 6, height = 1.5, color = "Lemon" } :: Disc,
	-- The gift box at scale 1.5 on the pedestal top, slow client spin.
	giftBox = { blueprintId = "gift_box", scale = 1.5, position = Vector3.new(17, 1.5, 26), facing = WEST },
	approach = Vector3.new(13, 0, 26),
	prompt = prompt("prompt.dailyReward", Vector3.new(15, 3, 26)),
}

-- Mats squeeze_01..06: X ∈ {-46, -36, -26} × Z ∈ {0, 14}, numbered west to east, Z = 0 row first (reading).
local MAT_DIAMETER = 8
local MAT_HEIGHT = 0.3
local MAT_ROW_Z = { 0, 14 }
local MAT_COLUMN_X = { -46, -36, -26 }
local mats: { { id: string, position: Vector3 } } = {}
for _, z in MAT_ROW_Z do
	for _, x in MAT_COLUMN_X do
		table.insert(mats, {
			id = string.format("squeeze_%02d", #mats + 1),
			position = Vector3.new(x, MAT_HEIGHT / 2, z),
		})
	end
end

local SqueezeZone = {
	model = "SqueezeZone",
	rug = { position = Vector3.new(-41, 0.03, 6), size = Vector3.new(38, 0.06, 32), color = "MintCream" } :: Box, -- X -60..-22, Z -10..22
	mats = mats, -- tag SD_SqueezeStation (StationId, GripTier = 1); no ProximityPrompt in the zone
	matDiameter = MAT_DIAMETER,
	matHeight = MAT_HEIGHT,
	matColor = "Bubblegum",
	matRimColor = "White",
	matRimWidth = 0.4, -- reading
	pulseColor = "Lemon", -- 0.15 s pulse on an accepted squeeze (§7.6)
	-- Kitty Bread built at scale 7 (≈ 10.5 tall) on the plinth, facing +X; decor above 3 studs: CanCollide/CanQuery false.
	statue = { blueprintId = "kitty_bread", scale = 7, position = Vector3.new(-55, 1, 6), facing = EAST },
	plinth = { position = Vector3.new(-55, 0.5, 6), size = Vector3.new(6, 1, 6), color = "Cream" } :: Box,
	sparkle = Vector3.new(-55, 6, 6), -- ambient sparkle emitter at the statue (reading: its middle)
}

-- Practice range (§5.11, §7.6): 3 lanes × 3 distances, one moving target (middle lane, 20 studs).
local FIRING_LINE_X = -24
local LANE_Z = { -47, -37, -27 }
local TARGET_DISTANCES = { 12, 20, 28 }
local MOVING_LANE = 2
local MOVING_DISTANCE = 20
local MOVING_RAIL_LENGTH = 12 -- ±6 along Z
local MOVING_PERIOD = 9.42 -- seconds (peak ≈ 4 studs/s)
local targets: { Target } = {}
for lane, z in LANE_Z do
	for _, distance in TARGET_DISTANCES do
		local moving = lane == MOVING_LANE and distance == MOVING_DISTANCE
		table.insert(targets, {
			id = string.format("target_%02d", #targets + 1),
			lane = lane,
			distance = distance,
			position = Vector3.new(FIRING_LINE_X - distance, 0, z),
			moving = moving,
			railLength = if moving then MOVING_RAIL_LENGTH else 0,
			period = if moving then MOVING_PERIOD else 0,
			nameKey = "practice.targetName",
		})
	end
end

local PracticeRange = {
	model = "PracticeRange",
	zoneTag = "SD_PracticeZone",
	targetTag = "SD_PracticeTarget",
	laneFloor = { position = Vector3.new(-42, 0.03, -37), size = Vector3.new(36, 0.06, 34), color = "LaneLilac" } :: Box, -- X -60..-24, Z -54..-20
	laneFloorTopY = 0.06,
	firingLine = {
		position = Vector3.new(FIRING_LINE_X, 0.035, -37),
		size = Vector3.new(0.6, 0.07, 34),
		color = "Lemon",
	} :: Box,
	firingLineX = FIRING_LINE_X,
	throwBox = span("ThrowBox", -24, -16, 0, 12, -54, -20), -- SD_PracticeZone, invisible
	throwDirection = WEST,
	laneZ = LANE_Z,
	laneWidth = 10,
	distances = TARGET_DISTANCES,
	targets = targets, -- anchored; the target hitbox is the player capsule (§5.11)
	targetColor = "Lavender",
	backstop = { position = Vector3.new(-59, 6, -37), size = Vector3.new(2, 12, 34), color = "Sky" } :: Box,
	-- Gumdrop hedge, 2.5 tall (balls Ø2.5, uniform), open at the east end.
	hedge = { from = Vector3.new(-62, 0, -16), to = Vector3.new(-26, 0, -16), ballDiameter = 2.5, color = "Mint" },
	approach = Vector3.new(-22, 0, -37),
}

local DuelGate = {
	model = "DuelGate",
	podiumTag = "SD_QueuePodium",
	boardTag = "SD_QueueBoard",
	queuePad = { position = Vector3.new(0, 0.1, -34), diameter = 14, height = 0.2, color = "Bubblegum" } :: Disc,
	queuePadRingColor = "Cream",
	podium = { position = Vector3.new(0, 1.75, -42), size = Vector3.new(3, 3.5, 2), color = "Cream" } :: Box,
	posts = {
		{ position = Vector3.new(-11, 9, -52), size = Vector3.new(3, 18, 3), color = "Cream" },
		{ position = Vector3.new(11, 9, -52), size = Vector3.new(3, 18, 3), color = "Cream" },
	} :: { Box },
	beam = { position = Vector3.new(0, 20, -52), size = Vector3.new(25, 4, 3), color = "Strawberry" } :: Box, -- Strawberry/Cream stripes
	-- Status board 16 × 8 × 0.6 at (0, ·, -51). Reading: centre Y 11, not DESIGN's 8: the board is decor (no collision)
	-- and the alcove between the arch posts is walkable, so at Y 4..12 a character walked through its bottom edge;
	-- Y 7..15 clears a tall avatar and stays under the arch sign (Y 17.35 with its frame).
	statusBoard = {
		position = Vector3.new(0, 11, -51),
		size = Vector3.new(16, 8, 0.6),
		facing = SOUTH,
		color = "Cream",
	} :: Box,
	approach = Vector3.new(0, 0, -36),
	-- "Join 1v1 Queue" / "Leave Queue" on the podium (toggle). Reading: on the podium's south face.
	prompt = prompt("prompt.joinQueue", Vector3.new(0, 3, -41), "prompt.leaveQueue"),
}

local GiftBoxCounter = {
	model = "GiftBoxCounter",
	tag = "SD_BoxStand",
	boxId = "snack", -- reading: SD_BoxStand's BoxId = the first paid box (Boxes land in Part 7)
	counter = { position = Vector3.new(29.5, 1.75, -42), size = Vector3.new(3, 3.5, 12), color = "Strawberry" } :: Box, -- front X 28
	counterFrontX = 28,
	-- The only Neon in the lobby: a small rim on the counter top (§7.3). Reading: 0.1 tall around the top edge.
	neonRim = { position = Vector3.new(29.5, 3.55, -42), size = Vector3.new(3.1, 0.1, 12.1), color = "Strawberry" } :: Box,
	pedestal = { position = Vector3.new(40, 0.5, -42), size = Vector3.new(9, 1, 9), color = "Cream" } :: Box,
	giftBox = { blueprintId = "gift_box", scale = 4, position = Vector3.new(40, 1, -42), facing = WEST },
	oddsBoard = { position = Vector3.new(29, 5, -50), size = Vector3.new(7, 8, 0.5), facing = SOUTH, color = "Cream" } :: Box,
	approach = Vector3.new(26, 0, -42),
	-- Restricted/unknown clients relabel it locally to "Shop Squishies".
	prompt = prompt("prompt.seeBoxes", Vector3.new(28.5, 3, -42), "prompt.shopDirect"),
}

local ShopCounter = {
	model = "ShopCounter",
	tag = "SD_ShopCounter",
	-- L-counter, front at X 29. Reading: the L's short return leg (decor) stays east of X 29.
	counter = { position = Vector3.new(30.5, 1.75, -21), size = Vector3.new(3, 3.5, 14), color = "Cocoa" } :: Box,
	counterFrontX = 29,
	backShelves = { position = Vector3.new(58, 5, -21), size = Vector3.new(2, 10, 16), color = "Cocoa" } :: Box, -- with jars
	approach = Vector3.new(26, 0, -21),
	prompt = prompt("prompt.openShop", Vector3.new(29.5, 3, -21)),
}

-- Collection: pedestals in catalog order, tier 1 = slots 1-4, tier 2 = slots 5-8 (left to right for a viewer
-- facing +X, i.e. rising Z).
local TIER1_TOP = 2
local TIER2_TOP = 4.5
local PEDESTAL_SIZE = Vector3.new(3, 0.4, 3)
local pedestals: { Pedestal } = {}
local function addPedestals(x: number, top: number, zs: { number })
	for _, z in zs do
		local position = Vector3.new(x, top + PEDESTAL_SIZE.Y / 2, z)
		table.insert(pedestals, {
			slot = #pedestals + 1,
			position = position,
			size = PEDESTAL_SIZE,
			prompt = {
				actionKey = "prompt.inspect",
				position = position + Vector3.new(0, PEDESTAL_SIZE.Y / 2, 0),
				maxDistance = INSPECT_DISTANCE,
				requiresLineOfSight = false,
			},
		})
	end
end
addPedestals(40, TIER1_TOP, { -3, 2.5, 8, 13.5 })
addPedestals(45, TIER2_TOP, { -0.25, 5.25, 10.75, 16.25 })

local Collection = {
	model = "Collection",
	kioskTag = "SD_CollectionKiosk",
	pedestalTag = "SD_CollectionPedestal",
	tier1 = { position = Vector3.new(40, 1, 6), size = Vector3.new(4, TIER1_TOP, 24), color = "Cream" } :: Box,
	tier2 = { position = Vector3.new(45, 2.25, 6), size = Vector3.new(4, TIER2_TOP, 24), color = "Cream" } :: Box,
	pedestals = pedestals,
	squishyScale = 2.5, -- client-built per player: owned = full colour, unowned = Lavender silhouette
	buildStuds = 60, -- models built/animated only within this distance
	ownedKey = "collection.owned",
	notOwnedKey = "collection.notOwned",
	kiosk = { position = Vector3.new(35, 1.75, 6), size = Vector3.new(2, 3.5, 3), color = "Strawberry" } :: Box,
	approach = Vector3.new(32, 0, 6),
	prompt = prompt("prompt.openCollection", Vector3.new(34, 3, 6)), -- reading: on the kiosk's west face
}

-- Private: Grip pods and giant pads (§17.6, §17.6.1) ---------------------------------------------------------------

local function giantPad(spec: {
	key: string,
	stationId: string,
	tier: number,
	x: number,
	z: number,
	footprint: number,
	cornerRadius: number,
	restTop: number,
	sinkDepth: number,
	collisionSide: number,
	faceDirection: Vector3,
	look: { body: string, top: string, accent: string?, transparency: number },
	gateDiameter: number,
	gateColor: string,
}): GiantPad
	local collisionTop = 1.0
	return {
		key = spec.key,
		stationId = spec.stationId,
		tier = spec.tier,
		model = "GiantPad_" .. spec.key,
		blueprintId = "giant_" .. (if spec.key == "royal" then "cushion" else spec.key),
		center = Vector3.new(spec.x, 0, spec.z),
		footprint = spec.footprint,
		cornerRadius = spec.cornerRadius,
		restTop = spec.restTop,
		sinkDepth = spec.sinkDepth,
		collision = {
			position = Vector3.new(spec.x, collisionTop / 2, spec.z),
			size = Vector3.new(spec.collisionSide, collisionTop, spec.collisionSide),
		},
		collisionTop = collisionTop,
		faceDirection = spec.faceDirection,
		look = spec.look,
		gate = {
			position = Vector3.new(spec.x, 4.5, spec.z),
			diameter = spec.gateDiameter,
			height = 9,
			color = spec.gateColor,
			transparency = 0.55, -- built CanCollide/CanQuery/CanTouch false; WorldBinder closes it locally (§17.6)
		},
		signPost = { position = Vector3.new(spec.x, 5.5, 30.4), size = Vector3.new(0.6, 11, 0.6), color = "Cocoa" },
		signId = "pod_" .. spec.key,
		tileSpacing = 1.0,
		tileSize = Vector3.new(2, 1, 2),
		tilesPerSide = math.round(spec.footprint / 1.0),
	}
end

local GIANT_PAD_KEYS = { "jelly", "marshmallow", "royal" }

local GiantPads: { [string]: GiantPad } = {
	jelly = giantPad({
		key = "jelly",
		stationId = "squeeze_07",
		tier = 2,
		x = -33,
		z = 37,
		footprint = 8,
		cornerRadius = 1.2,
		restTop = 1.5,
		sinkDepth = 0.5,
		collisionSide = 6.8,
		faceDirection = EAST, -- toward the spawn side
		look = { body = "Mint", top = "MintCream", transparency = 0.15 }, -- reading: MintCream = "lighter Mint top"
		gateDiameter = 12,
		gateColor = "Mint",
	}),
	marshmallow = giantPad({
		key = "marshmallow",
		stationId = "squeeze_08",
		tier = 3,
		x = -53,
		z = 37,
		footprint = 8,
		cornerRadius = 2.0, -- puffy
		restTop = 1.6,
		sinkDepth = 0.6,
		collisionSide = 6.6,
		faceDirection = EAST,
		look = { body = "Cream", top = "Cream", accent = "Lavender", transparency = 0 }, -- Lavender bottom band
		gateDiameter = 12,
		gateColor = "Lavender",
	}),
	royal = giantPad({
		key = "royal",
		stationId = "squeeze_09",
		tier = 4,
		x = 38,
		z = 38,
		footprint = 9,
		cornerRadius = 1.0,
		restTop = 1.7,
		sinkDepth = 0.7, -- softest
		collisionSide = 7.8,
		faceDirection = WEST, -- toward the promenade
		look = { body = "Lemon", top = "Lemon", accent = "Strawberry", transparency = 0 }, -- piping + centre tuft
		gateDiameter = 14,
		gateColor = "Strawberry",
	}),
}

local Pods = {
	gym = {
		model = "GripGym",
		rug = { position = Vector3.new(-43, 0.03, 37), size = Vector3.new(34, 0.06, 22), color = "MintCream" } :: Box, -- X -60..-26, Z 26..48
		padKeys = { "jelly", "marshmallow" },
	},
	royal = {
		model = "RoyalPod",
		rug = { position = Vector3.new(38, 0.03, 38), size = Vector3.new(22, 0.06, 22), color = "Bubblegum" } :: Box, -- X 27..49, Z 27..49
		padKeys = { "royal" },
	},
}

-- Private: stations list (§6.3, §17.6) -----------------------------------------------------------------------------

local Stations: { Station } = {}
for _, mat in mats do
	table.insert(Stations, {
		id = mat.id,
		tier = 1,
		kind = "mat",
		model = SqueezeZone.model,
		position = mat.position,
		top = MAT_HEIGHT,
		halfSize = MAT_DIAMETER / 2,
	})
end
for _, key in GIANT_PAD_KEYS do
	local pad = GiantPads[key]
	table.insert(Stations, {
		id = pad.stationId,
		tier = pad.tier,
		kind = "giant",
		model = pad.model,
		position = pad.collision.position,
		top = pad.collisionTop,
		halfSize = pad.footprint / 2,
		padKey = pad.key,
	})
end

-- Private: other lobby data ----------------------------------------------------------------------------------------

local ReturnPoints: { ReturnPoint } = {
	{ slot = 1, position = Vector3.new(-6, 0, -24), facing = SOUTH }, -- reading: Slot 1 = west
	{ slot = 2, position = Vector3.new(6, 0, -24), facing = SOUTH },
}

local Props = {
	-- 4 giant lollipops: Ø6 disc head on a 0.6 × 14 stick. Reading: head 1 thick, centred on the stick top.
	-- Reading: the NW one stands at X -55, not DESIGN's -58: at -58 its stick ran through the practice backstop
	-- (X -60..-58, Z -54..-20) and its head cut into the backstop's top; at -55 the head (facing the centre) ends at
	-- X -57.4.
	lollipops = {
		positions = {
			Vector3.new(-55, 0, -50),
			Vector3.new(58, 0, -50),
			Vector3.new(-58, 0, 50),
			Vector3.new(58, 0, 50),
		},
		stickDiameter = 0.6,
		stickHeight = 14,
		headDiameter = 6,
		headThickness = 1,
	},
	-- Toy-block stacks flanking the arch; only the bottom block collides. Reading: 3 × 3 footprint.
	toyBlocks = { positions = { Vector3.new(-20, 0, -53), Vector3.new(20, 0, -53) }, footprint = 3 },
	awnings = { minY = 16, maxY = 19 }, -- striped Fabric, CanCollide false
	bunting = { minY = 15, maxY = 17 }, -- between the lollipops
	-- Rules (§7.7): decor taller than 3 studs is CanCollide = false and CanQuery = false; no Neon decor; nothing
	-- squishy-coloured near the practice lanes.
	collidableMaxHeight = 3,
}

-- Every static SurfaceGui sign (one SurfaceGui each; §7.7 table and §17.6 pod signs).
local Signs: { Sign } = {
	{
		id = "spawnPlate",
		owner = Spawn.model,
		part = "logoPlate",
		position = Spawn.logoPlate.position,
		size = Spawn.logoPlate.size,
		facing = UP,
		face = "Top",
		textUp = NORTH, -- readable from the spawn, facing -Z
		lines = {
			line("Logo", "world.spawnLogo", 3.0, "heading"),
			line("Safe", "world.spawnSafe", 1.0, "body"), -- under the logo
		},
	},
	{
		-- Reading: a thin panel on the beam's south face (the beam's front is Z -50.5), 4.7 tall so DESIGN's 2.4-stud
		-- title and 1.0-stud subtitle both fit (a 3.8-stud panel clipped the subtitle); it overhangs the 4-tall beam by
		-- 0.35 above and below.
		id = "duelArch",
		owner = DuelGate.model,
		position = Vector3.new(0, 20, -50.4),
		size = Vector3.new(24, 4.7, 0.2),
		facing = SOUTH,
		face = "Front",
		lines = {
			line("Title", "world.duelGateTitle", 2.4, "heading"),
			line("Subtitle", "world.duelGateSubtitle", 1.0, "body"),
		},
	},
	{
		id = "queueBoard",
		owner = DuelGate.model,
		part = "statusBoard",
		position = DuelGate.statusBoard.position,
		size = DuelGate.statusBoard.size,
		facing = SOUTH,
		face = "Front",
		lines = {
			line("Title", "queue.boardTitle", 2.0, "heading"),
			liveLine("Waiting", "queue.boardWaiting", 0.8),
			liveLine("Active", "queue.boardActive", 0.8),
			line("Hint", "queue.boardHint", 0.6, "body"),
		},
	},
	{
		-- West shelf face. Reading: centre Y 13.5 (Y 11..16, just under the awning) instead of DESIGN's 12, with the
		-- lines top-aligned: the Kitty Bread statue (ears up to Y 11.1) stands in front of the sign and hid the bottom
		-- of the subtitle from the plaza.
		id = "squeezeSign",
		owner = SqueezeZone.model,
		position = Vector3.new(-59.7, 13.5, 6),
		size = Vector3.new(20, 5, 0.4), -- reading
		facing = EAST,
		face = "Front",
		align = "top",
		lines = {
			line("Title", "world.squeezeTitle", 2.4, "heading"),
			line("Subtitle", "world.squeezeSubtitle", 1.0, "body"),
		},
	},
	{
		id = "practiceSign",
		owner = PracticeRange.model,
		position = Vector3.new(-42, 12, -51.7), -- north shelf face
		size = Vector3.new(23, 5, 0.4), -- reading
		facing = SOUTH,
		face = "Front",
		lines = {
			line("Title", "practice.title", 2.4, "heading"),
			line("Subtitle", "practice.sign", 1.0, "body"),
		},
	},
	{
		id = "boxStandSign",
		owner = GiftBoxCounter.model,
		position = Vector3.new(40, 13.5, -42),
		size = Vector3.new(19.5, 5, 0.4), -- reading (Z -51.75..-32.25, clear of the north shelves)
		facing = WEST,
		face = "Front",
		lines = {
			line("Title", "box.standTitle", 2.4, "heading"),
			line("Subtitle", "box.standSubtitle", 1.0, "body"),
		},
	},
	{
		id = "oddsBoard",
		owner = GiftBoxCounter.model,
		part = "oddsBoard",
		position = GiftBoxCounter.oddsBoard.position,
		size = GiftBoxCounter.oddsBoard.size,
		facing = SOUTH,
		face = "Front",
		lines = {
			line("Title", "box.oddsTitle", 1.0, "heading"),
			-- Odds lines are generated from Boxes (Part 7); restricted/unknown clients show a note instead (§6.10).
			liveLine("Body", nil, 0.6, { "box.restrictedNote", "box.unknownNote" }),
		},
	},
	{
		id = "shopSign",
		owner = ShopCounter.model,
		position = Vector3.new(40, 12, -21),
		size = Vector3.new(12, 5, 0.4), -- reading
		facing = WEST,
		face = "Front",
		lines = {
			line("Title", "shop.title", 2.4, "heading"),
			line("Subtitle", "shop.subtitle", 1.0, "body"),
		},
	},
	{
		id = "collectionSign",
		owner = Collection.model,
		position = Vector3.new(49, 12, 6),
		size = Vector3.new(20, 4, 0.4), -- reading
		facing = WEST,
		face = "Front",
		lines = { line("Title", "collection.title", 2.4, "heading") },
	},
	{
		id = "questBoard",
		owner = QuestBoard.model,
		part = "board",
		position = questBoard.position,
		size = questBoard.size,
		facing = QUEST_FACING,
		face = "Front",
		align = "top", -- the title sits above the note cards
		lines = { line("Title", "quest.title", 2.0, "heading") }, -- reading: 2.0 so "QUESTS" fits the 9-stud board
	},
	{
		id = "dailySign",
		owner = DailyStand.model,
		position = Vector3.new(19.5, 7, 26),
		size = Vector3.new(7, 3, 0.4),
		facing = WEST,
		face = "Front",
		lines = {
			-- Reading: 1.0, not 2.2: "DAILY REWARD" must fit the 7-stud sign DESIGN gives (1.0 ≈ 311 of 334 px).
			line("Title", "daily.title", 1.0, "heading"),
			-- Built empty: the stand stays inert until the daily feature registers its UI (§7.6), so the sign never says
			-- "Ready to claim!" with nothing to claim; its owner writes daily.ready / daily.wait.
			liveLine("Status", nil, 0.6, { "daily.ready", "daily.wait" }),
		},
	},
}

-- Practice floor labels (§7.6 "with floor labels"). Reading: one per distance column, on the lane 1 / lane 2 border,
-- 2.5 studs in front of the targets, readable from the throw box (text top toward -X). Baked, no SD_TextKey.
for _, distance in TARGET_DISTANCES do
	table.insert(Signs, {
		id = string.format("practiceFloor%d", distance),
		owner = PracticeRange.model,
		position = Vector3.new(FIRING_LINE_X - distance + 2.5, 0.07, (LANE_Z[1] + LANE_Z[2]) / 2),
		size = Vector3.new(1.4, 0.02, 4),
		facing = UP,
		face = "Top",
		textUp = WEST,
		lines = {
			{
				name = "Label",
				bakeKey = "practice.distanceLabel",
				bakeArgs = { distance = distance },
				live = false,
				letterHeight = 0.8,
				font = "body",
			},
		},
	})
end

-- Pod signs (§17.6): `Title` is static (SD_TextKey grip.pad.<key>), `Live` has no SD_TextKey (baked with
-- Strings.format(grip.padNeeds, {level = Config.Grip.Pads[tier].level}), then written only by the SD_GripSign binder).
for _, key in GIANT_PAD_KEYS do
	local pad = GiantPads[key]
	local lines: { SignLine } = {}
	if key == "jelly" then
		table.insert(lines, line("Heading", "grip.gymTitle", 1.4, "heading")) -- the Grip Gym's only title
	end
	table.insert(lines, line("Title", "grip.pad." .. key, 1.0, "heading"))
	table.insert(lines, liveLine("Live", "grip.padNeeds", 0.6, { "grip.signLocked", "grip.signOpen" }))
	table.insert(Signs, {
		id = pad.signId,
		owner = if key == "royal" then Pods.royal.model else Pods.gym.model,
		position = Vector3.new(pad.center.X, 11.5, 30.2),
		size = Vector3.new(8, if key == "jelly" then 4 else 3, 0.4),
		facing = NORTH,
		face = "Front",
		tag = "SD_GripSign",
		tier = pad.tier,
		lines = lines,
	})
end

-- Keep-clear volumes (§7.7 props rule 1 and 5; §17.6): the generator reports collidable parts inside them. Station
-- volumes sit in front of each station (on its approach) and never contain its body; pod volumes cover the jelly
-- gate footprint above the collision box. Station volumes never overlap each other. Prompt volumes (below) add the
-- 5-stud radius around every prompt. Reading: the aisles between station footprints are the promenade and the
-- station approach volumes.
local KeepClear: { KeepClearVolume } = {
	-- Promenade: X -10..10 from the podium (Z -41, minus the margin) to the carpet's south end (Z 36).
	keepClear("promenade", "aisle", -10, 10, -41 + KEEP_CLEAR_MARGIN, 36),
	keepClear("spawn", "station", -6, 6, 36, 44),
	keepClear("questBoard", "station", -14.5, -8, 21, 31),
	keepClear("dailyStand", "station", 8, 14 - KEEP_CLEAR_MARGIN, 21, 31),
	keepClear("duelGate", "station", -5, 5, -41 + KEEP_CLEAR_MARGIN, -31),
	keepClear("giftBoxCounter", "station", 21, 28 - KEEP_CLEAR_MARGIN, -47, -37),
	keepClear("shopCounter", "station", 21, 29 - KEEP_CLEAR_MARGIN, -26, -16),
	keepClear("collection", "station", 27, 34 - KEEP_CLEAR_MARGIN, -6, 18), -- kiosk approach + pedestal aisle
	keepClear("practiceRange", "station", -24, -16, -51, -20), -- the throw box inside the walls
}
for _, mat in mats do
	local p = mat.position
	-- A 5-stud radius around each mat centre (neighbouring mats are 10 apart, so the volumes only touch).
	table.insert(KeepClear, keepClear(mat.id, "station", p.X - 5, p.X + 5, p.Z - 5, p.Z + 5))
end
for _, key in GIANT_PAD_KEYS do
	local pad = GiantPads[key]
	local radius = pad.gate.diameter / 2
	local c = pad.center
	table.insert(
		KeepClear,
		keepClear(
			pad.stationId,
			"station",
			c.X - radius,
			c.X + radius,
			c.Z - radius,
			c.Z + radius,
			pad.collisionTop + POD_KEEP_CLEAR_LIFT
		)
	)
end
-- §7.7 props rule 1: the 5-stud radius around every prompt (each stand prompt and the 8 Inspect prompts), as boxes
-- from Y 0.5 to 24. They hold their own station's body, which the keep-clear test exempts, so they catch decor and
-- the team's Workspace.SD_Manual parts crowding a prompt.
local function promptKeepClear(name: string, point: Vector3)
	local r = PROMPT_KEEP_CLEAR_RADIUS
	table.insert(KeepClear, keepClear(name, "prompt", point.X - r, point.X + r, point.Z - r, point.Z + r))
end
promptKeepClear("prompt_questBoard", QuestBoard.prompt.position)
promptKeepClear("prompt_dailyStand", DailyStand.prompt.position)
promptKeepClear("prompt_duelGate", DuelGate.prompt.position)
promptKeepClear("prompt_giftBoxCounter", GiftBoxCounter.prompt.position)
promptKeepClear("prompt_shopCounter", ShopCounter.prompt.position)
promptKeepClear("prompt_collection", Collection.prompt.position)
for _, pedestal in pedestals do
	promptKeepClear(string.format("prompt_pedestal%d", pedestal.slot), pedestal.prompt.position)
end

-- Audio zones (§7.7, the bigger squeeze zone of §17.6): highest priority wins. The practice zone grew in the feel
-- pass (§18.8): X -60..-16 now covers the throw box (X -24..-16, Z -54..-20) as well as the lanes.
local function audioZone(
	zoneId: string,
	position: Vector3,
	size: Vector3,
	priority: number,
	musicKey: string,
	musicMul: number,
	ambienceKey: string
): AudioZone
	return {
		name = zoneId,
		zoneId = zoneId,
		position = position,
		size = size,
		priority = priority,
		musicKey = musicKey,
		musicMul = musicMul,
		ambienceKey = ambienceKey,
	}
end

local AudioZones: { AudioZone } = {
	audioZone("lobby", Vector3.new(0, 20, 0), Vector3.new(128, 40, 112), 1, "music.lobby", 1.0, "amb.lobby"),
	audioZone("squeeze", Vector3.new(-41, 15, 21), Vector3.new(38, 30, 62), 2, "music.lobby", 0.8, "amb.lobby"),
	audioZone("practice", Vector3.new(-38, 15, -37), Vector3.new(44, 30, 34), 2, "music.lobby", 0.6, "amb.lobby"),
}

-- Activities and their walk points (routes, waypoints). The squeeze zone counts each mat; the Grip pods are separate
-- activities because of the G-D exception (§17.0).
local matPoints: { Vector3 } = {}
for _, mat in mats do
	table.insert(matPoints, Vector3.new(mat.position.X, 0, mat.position.Z))
end
local Activities: { Activity } = {
	{ name = "quests", points = { QuestBoard.approach }, pod = false },
	{ name = "daily", points = { DailyStand.approach }, pod = false },
	{ name = "squeeze", points = matPoints, pod = false },
	{ name = "collection", points = { Collection.approach }, pod = false },
	{ name = "shop", points = { ShopCounter.approach }, pod = false },
	{ name = "duel", points = { DuelGate.approach }, pod = false },
	{ name = "practice", points = { PracticeRange.approach }, pod = false },
	{ name = "giftBox", points = { GiftBoxCounter.approach }, pod = false },
}
for _, key in GIANT_PAD_KEYS do
	table.insert(Activities, { name = key .. "Pad", points = { GiantPads[key].center }, pod = true })
end

-- Waypoint targets (floor points): onboarding, "Show me" and unlock waypoints. "squeeze" = the mat nearest the spawn.
local Waypoints: { [string]: Vector3 } = {
	spawn = Vector3.new(0, 0, 40),
	quests = QuestBoard.approach,
	daily = DailyStand.approach,
	squeeze = Vector3.new(-26, 0, 14),
	collection = Collection.approach,
	shop = ShopCounter.approach,
	duel = DuelGate.approach,
	practice = PracticeRange.approach,
	giftBox = GiftBoxCounter.approach,
}
for _, key in GIANT_PAD_KEYS do
	Waypoints[key .. "Pad"] = GiantPads[key].center
end

-- Private: arena template (§5.3, §7.8) -----------------------------------------------------------------------------

local ARENA_HALF_X = 36
local ARENA_HALF_Z = 52
local NEUTRAL_HALF_Z = 8
local ZONE_MIN_Y = -15
local ZONE_MAX_Y = 40

local floorBands: { Box } = {}
for index = 1, 13 do
	table.insert(floorBands, {
		position = Vector3.new(0, -2, -ARENA_HALF_Z + 4 + (index - 1) * 8),
		size = Vector3.new(72, 4, 8),
		color = if index % 2 == 1 then "LavenderMilkA" else "LavenderMilkB",
	})
end

-- One side's cover (Side B as DESIGN lists it); Side A is the point reflection (x, z) -> (-x, -z).
type CoverPart = { shape: "Block" | "Cylinder" | "Ball", position: Vector3, size: Vector3, color: string }
type CoverPiece = { name: string, side: "A" | "B", kind: string, parts: { CoverPart } }

local function coverPieces(side: "A" | "B", sign: number): { CoverPiece }
	local pieces: { CoverPiece } = {}
	local function at(x: number, y: number, z: number): Vector3
		return Vector3.new(x * sign, y, z * sign)
	end
	for index, x in { -9, 9 } do
		table.insert(pieces, {
			name = string.format("%s_Wall%d", side, index),
			side = side,
			kind = "wall", -- 3 Cream stripes on the faces (decor)
			parts = { { shape = "Block", position = at(x, 4, 20), size = Vector3.new(6, 8, 2.5), color = "Blueberry" } },
		})
	end
	for index, x in { -20, 20 } do
		table.insert(pieces, {
			name = string.format("%s_Gumdrop%d", side, index),
			side = side,
			kind = "gumdrop", -- cylinder Ø5 × 7.5 + Ball Ø5 dome, total 10 (equator 7.5: nobody lands on the dome)
			parts = {
				{ shape = "Cylinder", position = at(x, 3.75, 30), size = Vector3.new(5, 7.5, 5), color = "Mint" },
				{ shape = "Ball", position = at(x, 7.5, 30), size = Vector3.new(5, 5, 5), color = "Mint" },
			},
		})
	end
	for index, x in { -24, 24 } do
		table.insert(pieces, {
			name = string.format("%s_Block%d", side, index),
			side = side,
			kind = "block", -- Z 11..17, Cream cap on top, total 8.6
			parts = {
				{ shape = "Block", position = at(x, 4, 14), size = Vector3.new(6, 8, 6), color = "Blueberry" },
				{ shape = "Block", position = at(x, 8.3, 14), size = Vector3.new(6.2, 0.6, 6.2), color = "Cream" },
			},
		})
	end
	return pieces
end

local cover: { CoverPiece } = coverPieces("B", 1)
for _, piece in coverPieces("A", -1) do
	table.insert(cover, piece)
end

local Arena = {
	templateName = "Arena_CandyCourt", -- ServerStorage.SD_Templates
	generatorId = "arena",
	origin = { position = Vector3.zero, size = Vector3.new(1, 1, 1) } :: Box, -- PrimaryPart `Origin`; reading: 1-stud part
	halfX = ARENA_HALF_X, -- playable X ±36
	halfZ = ARENA_HALF_Z, -- playable Z ±52
	neutralHalfZ = NEUTRAL_HALF_Z, -- neutral zone Z -8..8, full width
	padDistance = 88,
	openLaneHalfX = 6, -- pad-to-pad lane X -6..6 has no cover
	minCoverHeight = 8, -- jump is 7.2
	maxCoverWidth = 8,
	floorBands = floorBands, -- 13 bands 72 × 4 × 8 across the court, top Y 0
	-- Reading (not in DESIGN): collidable floor strips (`Geometry/Floor`, top Y 0, the apron colour) from the edge of
	-- the bands out to the barrier walls (X ±36..±38, Z ±52..±54). Without them the 1.2-stud strip between a rail's
	-- outer face and its wall had no floor (the apron below does not collide), so a player who hopped a rail fell
	-- through into the void.
	gutters = {
		span("GutterWest", -38, -36, -4, 0, -54, 54),
		span("GutterEast", 36, 38, -4, 0, -54, 54),
		span("GutterEndA", -36, 36, -4, 0, -54, -52),
		span("GutterEndB", -36, 36, -4, 0, 52, 54),
	} :: { Volume },
	-- Neutral band: Cream/Strawberry diagonal "no-step" stripes with Ink edge lines; the midline sits on top.
	-- Reading: overlays 0.05 thick (Y 0..0.05); the midline 0.06 (Y 0..0.06) so they never z-fight.
	neutralBand = { position = Vector3.new(0, 0.025, 0), size = Vector3.new(72, 0.05, 16), color = "Cream" } :: Box,
	neutralStripeColor = "Strawberry",
	neutralEdgeColor = "Ink",
	midline = { position = Vector3.new(0, 0.03, 0), size = Vector3.new(72, 0.06, 1), color = "White" } :: Box,
	-- 2-wide border strips inside the rails, per side (reading: along both side rails and the end rail of the half).
	sideTints = {
		A = {
			{ position = Vector3.new(-35, 0.025, -30), size = Vector3.new(2, 0.05, 44), color = "Bubblegum" },
			{ position = Vector3.new(35, 0.025, -30), size = Vector3.new(2, 0.05, 44), color = "Bubblegum" },
			{ position = Vector3.new(0, 0.025, -51), size = Vector3.new(68, 0.05, 2), color = "Bubblegum" },
		} :: { Box },
		B = {
			{ position = Vector3.new(-35, 0.025, 30), size = Vector3.new(2, 0.05, 44), color = "MintCream" },
			{ position = Vector3.new(35, 0.025, 30), size = Vector3.new(2, 0.05, 44), color = "MintCream" },
			{ position = Vector3.new(0, 0.025, 51), size = Vector3.new(68, 0.05, 2), color = "MintCream" },
		} :: { Box },
	},
	-- Pads (plain Parts, not SpawnLocations): `Spawns/PadA` faces +Z, `Spawns/PadB` faces -Z.
	pads = {
		A = {
			name = "PadA",
			position = Vector3.new(0, 0.05, -44),
			diameter = 8,
			height = 0.1,
			facing = SOUTH,
			color = "Bubblegum",
		},
		B = {
			name = "PadB",
			position = Vector3.new(0, 0.05, 44),
			diameter = 8,
			height = 0.1,
			facing = NORTH,
			color = "MintCream",
		},
	},
	cover = cover, -- 12 pieces, each an Atomic sub-model in `Geometry`
	-- The Cream stripes on each cover wall (§18.3.4, moved from ArenaBuilder with identical values): Stripe_n centred
	-- `heights[n]` above the wall's bottom, `thickness` tall, (wall X - insetX) wide and (wall Z + proud) deep, so 0.01
	-- inside each X face and 0.05 proud of each big face. The jelly ripple's skin puts a grid row on every stripe edge.
	wallStripes = { heights = { 2, 4, 6 }, thickness = 0.5, proud = 0.1, insetX = 0.02 },
	-- Low walls 0.8 thick × 3 tall at X ±36.4 and Z ±52.4, tinted per side (reading: the side rails split at Z 0).
	rails = {
		{
			name = "A_RailWest",
			position = Vector3.new(-36.4, 1.5, -26.4),
			size = Vector3.new(0.8, 3, 52.8),
			color = "Strawberry",
		},
		{
			name = "A_RailEast",
			position = Vector3.new(36.4, 1.5, -26.4),
			size = Vector3.new(0.8, 3, 52.8),
			color = "Strawberry",
		},
		{
			name = "A_RailEnd",
			position = Vector3.new(0, 1.5, -52.4),
			size = Vector3.new(72, 3, 0.8),
			color = "Strawberry",
		},
		{
			name = "B_RailWest",
			position = Vector3.new(-36.4, 1.5, 26.4),
			size = Vector3.new(0.8, 3, 52.8),
			color = "Mint",
		},
		{
			name = "B_RailEast",
			position = Vector3.new(36.4, 1.5, 26.4),
			size = Vector3.new(0.8, 3, 52.8),
			color = "Mint",
		},
		{ name = "B_RailEnd", position = Vector3.new(0, 1.5, 52.4), size = Vector3.new(72, 3, 0.8), color = "Mint" },
	} :: { Box & { name: string } },
	-- `Geometry/Barriers`: Transparency 1, CanCollide true, CanQuery false, collision group `barrierGroup`. Roblox
	-- ignores CanQuery = false on a colliding part, so the group is what keeps projectile rays (Default group) from
	-- hitting the walls and the ceiling: it collides only with SD_Characters, like SD_Divider.
	barriers = {
		span("WallWest", -39, -38, 0, 40, -55, 55),
		span("WallEast", 38, 39, 0, 40, -55, 55),
		span("WallEndA", -39, 39, 0, 40, -55, -54),
		span("WallEndB", -39, 39, 0, 40, 54, 55),
		span("Ceiling", -39, 39, 40, 41, -55, 55), -- ceiling at Y 40.5
	} :: { Volume },
	barrierGroup = "SD_Barrier", -- reading (not in DESIGN §5.3's group list); registered by WorldService
	-- Dividers at Z ±8, 40 tall, collision group SD_Divider (collides only with SD_Characters). Reading: 76 wide
	-- (X -38..38, meeting the side walls) instead of DESIGN's 72: at 72 they ended at X ±36, so a player on top of a
	-- 3-tall side rail (or behind it) could walk around a divider's end into the neutral zone (§5.3: players cannot).
	dividers = {
		span("DividerA", -38, 38, 0, 40, -8.5, -7.5),
		span("DividerB", -38, 38, 0, 40, 7.5, 8.5),
	} :: { Volume },
	-- `Zones` (CanCollide/CanQuery/CanTouch false; the server reads only CFrame and Size). Reading: all four zones
	-- use the Bounds height Y -15..40.
	zones = {
		HalfA = span("HalfA", -ARENA_HALF_X, ARENA_HALF_X, ZONE_MIN_Y, ZONE_MAX_Y, -ARENA_HALF_Z, -NEUTRAL_HALF_Z),
		Neutral = span("Neutral", -ARENA_HALF_X, ARENA_HALF_X, ZONE_MIN_Y, ZONE_MAX_Y, -NEUTRAL_HALF_Z, NEUTRAL_HALF_Z),
		HalfB = span("HalfB", -ARENA_HALF_X, ARENA_HALF_X, ZONE_MIN_Y, ZONE_MAX_Y, NEUTRAL_HALF_Z, ARENA_HALF_Z),
		Bounds = span("Bounds", -38, 38, ZONE_MIN_Y, ZONE_MAX_Y, -54, 54), -- playable box + 2
	} :: { [string]: Volume },
	-- Apron 120 × 4 × 152, top -0.05, so the camera behind a pad sees floor, not void. Not a Palette token.
	apron = { position = Vector3.new(0, -2.05, 0), size = Vector3.new(120, 4, 152) } :: Box,
	apronColorHex = "#EBE3F3",
	-- `Decor`: CanCollide/CanQuery false; 4 lollipops (height 18) on the apron, gumdrop stacks; < 60 parts.
	decor = {
		lollipops = {
			Vector3.new(-46, 0, -62),
			Vector3.new(46, 0, -62),
			Vector3.new(-46, 0, 62),
			Vector3.new(46, 0, 62),
		},
		lollipopHeight = 18,
		maxParts = 59,
	},
	-- Reading: the arena audio box is centred on the court, Y -15..45.
	audioZone = audioZone("arena", Vector3.new(0, 15, 0), Vector3.new(120, 60, 152), 3, "music.duel", 1.0, "amb.arena"),
	maxParts = 400,
}

-- Module table -----------------------------------------------------------------------------------------------------

local WorldLayout = {
	Lobby = Lobby,
	Spawn = Spawn,
	Promenade = Promenade,
	QuestBoard = QuestBoard,
	DailyStand = DailyStand,
	SqueezeZone = SqueezeZone,
	PracticeRange = PracticeRange,
	DuelGate = DuelGate,
	GiftBoxCounter = GiftBoxCounter,
	ShopCounter = ShopCounter,
	Collection = Collection,
	Pods = Pods,
	GiantPads = GiantPads, -- keyed by pad key; GiantPadKeys gives the order
	GiantPadKeys = GIANT_PAD_KEYS,
	Stations = Stations, -- squeeze_01..09 in id order
	ReturnPoints = ReturnPoints,
	Props = Props,
	Signs = Signs,
	KeepClear = KeepClear,
	AudioZones = AudioZones,
	Activities = Activities,
	Waypoints = Waypoints,
	-- Straight-line routes at WalkSpeed 16 (= Config.Duel.Rules.Movement.WalkSpeed; real paths ≈ +10%).
	Routes = {
		walkSpeed = 16,
		maxSeconds = 5, -- between any two activities (§7.5)
		podMaxSeconds = 7.0, -- G-D exception: routes that involve a Grip pod (Marshmallow Pad -> gift box = 7.0 s)
	},
	Budgets = {
		lobbyParts = 2500,
		lobbySurfaceGuis = 30, -- Verify fails above this (§17.6)
		lobbyDynamicLights = 8, -- none casting shadows
		lobbyAmbientEmitters = 3,
		arenaParts = Arena.maxParts,
		arenaDecorParts = Arena.decor.maxParts,
	},
	-- Exact tag counts the lobby generator self-checks (§7.7, §17.6).
	TagCounts = {
		SD_LobbySpawn = 1,
		SD_SqueezeStation = 9,
		SD_PracticeZone = 1,
		SD_PracticeTarget = 9,
		SD_QueuePodium = 1,
		SD_QueueBoard = 1,
		SD_BoxStand = 1,
		SD_ShopCounter = 1,
		SD_CollectionKiosk = 1,
		SD_CollectionPedestal = 8,
		SD_QuestBoard = 1,
		SD_DailyStand = 1,
		SD_ReturnPoint = 2,
		SD_GripGate = 3,
		SD_GripSign = 3,
		SD_GiantPad = 3,
		SD_Boundary = #Lobby.Boundaries, -- 4 invisible walls
		SD_AudioZone = #AudioZones, -- lobby, squeeze, practice
		-- Lobby background motion (§18.5.1 A8): the 4 lollipops, both gift boxes and the statue.
		SD_Ambient = #Props.lollipops.positions + 3,
	},
	-- Tag and attribute names (§2.9, §17.10).
	Tags = {
		Generated = "SD_Generated",
		LobbySpawn = "SD_LobbySpawn",
		SqueezeStation = "SD_SqueezeStation",
		PracticeZone = "SD_PracticeZone",
		PracticeTarget = "SD_PracticeTarget",
		QueuePodium = "SD_QueuePodium",
		QueueBoard = "SD_QueueBoard",
		BoxStand = "SD_BoxStand",
		ShopCounter = "SD_ShopCounter",
		CollectionKiosk = "SD_CollectionKiosk",
		CollectionPedestal = "SD_CollectionPedestal",
		QuestBoard = "SD_QuestBoard",
		DailyStand = "SD_DailyStand",
		ReturnPoint = "SD_ReturnPoint",
		Sign = "SD_Sign",
		AudioZone = "SD_AudioZone",
		KeepClear = "SD_KeepClear",
		Boundary = "SD_Boundary",
		GripGate = "SD_GripGate",
		GripSign = "SD_GripSign",
		GiantPad = "SD_GiantPad",
		-- Reading (§18.5.1 A8 names the tag and attribute; §18.8 lists only the count): here so LobbyBuilder and
		-- AmbientController share one spelling.
		Ambient = "SD_Ambient",
	},
	Attributes = {
		StationId = "StationId",
		GripTier = "GripTier",
		PadKey = "PadKey",
		TargetId = "TargetId",
		Distance = "Distance",
		Moving = "Moving",
		RailLength = "RailLength",
		Period = "Period",
		BoxId = "BoxId",
		Slot = "Slot",
		TextKey = "SD_TextKey",
		ZoneId = "ZoneId",
		Priority = "Priority",
		MusicKey = "MusicKey",
		AmbienceKey = "AmbienceKey",
		MusicMul = "MusicMul",
		AmbientKind = "SD_AmbientKind", -- reading (see Tags.Ambient): "spin" | "spinBob" | "breathe" (§18.5.1 A8)
	},
	Arena = Arena,
}

-- Private: lookups ---------------------------------------------------------------------------------------------------

local stationById: { [string]: Station } = {}
local stationIds: { string } = {}
for _, station in Stations do
	stationById[station.id] = station
	table.insert(stationIds, station.id)
end
local padByStation: { [string]: GiantPad } = {}
for _, key in GIANT_PAD_KEYS do
	padByStation[GiantPads[key].stationId] = GiantPads[key]
end
table.freeze(stationIds) -- handed out as is by stationIds()

local function deepFreeze(value: any)
	if type(value) ~= "table" or table.isfrozen(value) then
		return
	end
	table.freeze(value)
	for key, child in value do
		deepFreeze(key)
		deepFreeze(child)
	end
end

-- Public -----------------------------------------------------------------------------------------------------------

-- The squeeze station with this id, or nil.
function WorldLayout.station(id: string): Station?
	return stationById[id]
end

-- The GripTier of a station (1 = Foam Mats, 2-4 = giant pads), or nil for an unknown id.
function WorldLayout.stationTier(id: string): number?
	local station = stationById[id]
	return if station then station.tier else nil
end

-- Every station id, in order (frozen list).
function WorldLayout.stationIds(): { string }
	return stationIds
end

-- The giant pad with this key ("jelly", "marshmallow", "royal"), or nil.
function WorldLayout.giantPad(key: string): GiantPad?
	return GiantPads[key]
end

-- The giant pad whose collision box is this station, or nil (Foam Mats and unknown ids).
function WorldLayout.giantPadForStation(stationId: string): GiantPad?
	return padByStation[stationId]
end

-- The station whose `position` is nearest to `position` within `maxDistance` (3D distance), and that distance.
-- Returns nil, math.huge when none is that close. Other players' mat pulse: Config.Squeeze.stationRadius +
-- radiusTolerance (the squeeze's own pad is stationUnder's, spec 2026-10-11 §5).
function WorldLayout.nearestStation(position: Vector3, maxDistance: number): (Station?, number)
	local best: Station? = nil
	local bestDistance = math.huge
	for _, station in Stations do
		local distance = (station.position - position).Magnitude
		if distance <= maxDistance and distance < bestDistance then
			best = station
			bestDistance = distance
		end
	end
	return best, bestDistance
end

-- The station a root part at `position` stands on (§17.3.6 #5): over a mat (radius + margin) or over a giant pad's
-- footprint (half-size + margin on X and on Z), with its height between the station top and top + heightAbove.
-- Config.Grip.Afk gives margin (padMargin) and heightAbove.
function WorldLayout.stationUnder(position: Vector3, margin: number, heightAbove: number): Station?
	for _, station in Stations do
		local dx = position.X - station.position.X
		local dz = position.Z - station.position.Z
		local reach = station.halfSize + margin
		local over = if station.kind == "mat"
			then dx * dx + dz * dz <= reach * reach
			else math.abs(dx) <= reach and math.abs(dz) <= reach
		if over and position.Y >= station.top and position.Y <= station.top + heightAbove then
			return station
		end
	end
	return nil
end

-- True when `point` lies inside the axis-aligned volume (faces included).
function WorldLayout.contains(volume: { position: Vector3, size: Vector3 }, point: Vector3): boolean
	local d = point - volume.position
	local h = volume.size / 2
	return math.abs(d.X) <= h.X and math.abs(d.Y) <= h.Y and math.abs(d.Z) <= h.Z
end

-- The lobby audio zone with the highest priority that contains `position`, or nil outside the lobby.
function WorldLayout.audioZoneAt(position: Vector3): AudioZone?
	local best: AudioZone? = nil
	for _, zone in AudioZones do
		if WorldLayout.contains(zone, position) and (best == nil or zone.priority > best.priority) then
			best = zone
		end
	end
	return best
end

-- The CFrame of a Box: rotated so its Front face looks along `facing`, unless `facing` is nil or vertical.
function WorldLayout.boxCFrame(box: { position: Vector3, facing: Vector3? }): CFrame
	local facing = box.facing
	if facing == nil or math.abs(facing.Y) > 0.99 then
		return CFrame.new(box.position)
	end
	return CFrame.lookAt(box.position, box.position + facing)
end

-- The world axis-aligned bounds (min, max) of a Box, rotation included.
function WorldLayout.boxBounds(box: { position: Vector3, size: Vector3, facing: Vector3? }): (Vector3, Vector3)
	local cf = WorldLayout.boxCFrame(box)
	local h = box.size / 2
	local extent = Vector3.new(
		math.abs(cf.RightVector.X) * h.X + math.abs(cf.UpVector.X) * h.Y + math.abs(cf.LookVector.X) * h.Z,
		math.abs(cf.RightVector.Y) * h.X + math.abs(cf.UpVector.Y) * h.Y + math.abs(cf.LookVector.Y) * h.Z,
		math.abs(cf.RightVector.Z) * h.X + math.abs(cf.UpVector.Z) * h.Y + math.abs(cf.LookVector.Z) * h.Z
	)
	return box.position - extent, box.position + extent
end

-- True when two axis-aligned bounds share volume (touching faces do not count).
function WorldLayout.boundsOverlap(aMin: Vector3, aMax: Vector3, bMin: Vector3, bMax: Vector3): boolean
	return aMin.X < bMax.X
		and bMin.X < aMax.X
		and aMin.Y < bMax.Y
		and bMin.Y < aMax.Y
		and aMin.Z < bMax.Z
		and bMin.Z < aMax.Z
end

-- Distance between two points on the floor plane (Y ignored).
function WorldLayout.horizontalDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Straight-line walking time between two floor points at Routes.walkSpeed.
function WorldLayout.routeSeconds(a: Vector3, b: Vector3): number
	return WorldLayout.horizontalDistance(a, b) / WorldLayout.Routes.walkSpeed
end

-- The floor point of a waypoint target ("duel", "giftBox", "squeeze", "jellyPad", ...), or nil.
function WorldLayout.waypoint(name: string): Vector3?
	return Waypoints[name]
end

-- Every Strings key the generated world shows (sign lines, prompts, nameplates), sorted and without duplicates.
function WorldLayout.textKeys(): { string }
	local seen: { [string]: boolean } = {}
	local keys: { string } = {}
	local function add(key: string?)
		if key ~= nil and not seen[key] then
			seen[key] = true
			table.insert(keys, key)
		end
	end
	for _, sign in Signs do
		for _, entry in sign.lines do
			add(entry.textKey)
			add(entry.bakeKey)
			local clientKeys = entry.clientKeys
			if clientKeys then
				for _, key in clientKeys do
					add(key)
				end
			end
		end
	end
	for _, stand in { QuestBoard, DailyStand, DuelGate, GiftBoxCounter, ShopCounter, Collection } :: { any } do
		add(stand.prompt.actionKey)
		add(stand.prompt.altActionKey)
	end
	for _, pedestal in pedestals do
		add(pedestal.prompt.actionKey)
	end
	for _, target in targets do
		add(target.nameKey)
	end
	add(Collection.ownedKey)
	add(Collection.notOwnedKey)
	table.sort(keys)
	return keys
end

deepFreeze(WorldLayout)

return WorldLayout
