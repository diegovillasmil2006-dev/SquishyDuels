--!strict
-- WorldLayout: every coordinate, size and tier of the lobby and of the arena template (§5.3, §7.8), as frozen data,
-- plus small pure helpers. Shared: required by the edit-time generators and Verify (through the injected Shared
-- clone; no requires here) and at runtime (station positions and tiers, return points, waypoints, zones). Requiring
-- it has no side effects: it only builds and deep-freezes plain tables.
--
-- The lobby is the Claude Design hub (user decision 2026-10-11 "build the design's lobby"; design package sd/lobby.js,
-- phase 3 spec decisions D1-D14): a 232 × 184 hub with 12 stations around the spawn medallion. Design numbers carry
-- `-- design: lobby.js:<line>`; values the design does not state are marked "reading (not in design)" and parts the
-- game needs that the design has no place for "NOT IN DESIGN". This module holds what the game reads (stations,
-- stands, prompts, pads, targets, signs, volumes, routes) and the design's station frames; the lobby generator
-- (SDTools LobbyBuilder) puts the design's decor around them in the same frames.
--
-- Frames and units (studs):
-- * Lobby: world coordinates. Floor top Y = 0. North = -Z. The spawn medallion is at the origin; players spawn
--   facing north, toward the duel gate (lobby.js:119-120; main.js:486 "Spawn eye").
-- * Station frames (StationFrames, stationFrame(id)): the design's st() groups (lobby.js:112, 119-130), a station at
--   (x, 0, z) turned by `yaw` (three.js rotation.y = CFrame.Angles(0, yaw, 0)); its local +Z, its front, faces the hub
--   centre. A design point (lx, ly, lz) of a station is stationFrame(id) * Vector3.new(lx, ly, lz); nested design
--   groups (grp(), lobby.js:19) multiply in the same way.
-- * Arena: relative to the template's `Origin` part (floor centre, floor top Y = 0); long axis = Z; Side A = Z < 0
--   ("Strawberry side"), Side B = Z > 0 ("Mint side"). The slot origins live in Config.Duel.Arena.SlotOrigins.
-- * Box: `position` = centre; `size` = W × H × D in the part's own frame; `facing` = the unit direction its Front
--   (-Z) face looks toward, i.e. CFrame.lookAt(position, position + facing); else `yaw`, a turn about +Y like a design
--   part's (CFrame.Angles(0, yaw, 0)). With neither, or with a vertical facing (floor plates), the part is not rotated
--   and `size` is world X × Y × Z (boxCFrame).
-- * Disc: an upright cylinder (`position` = centre, `diameter`, `height`). Roblox Cylinder parts have their axis on
--   X, so builders rotate them 90° about Z.
-- * Volume: an invisible box (`position` = centre, `size`), axis-aligned unless it has a `yaw` (the keep-clear aisles
--   along the design's diagonal paths): keep-clear volumes, zones, audio zones, boundaries, the practice throw box.
-- * `color` fields are Art/Palette token names (builders use Palette[color]). `*Key` fields are Strings keys, except
--   `musicKey` / `ambienceKey` (AssetTable sound slots).
-- * A squeeze station's `tier` is its GripTier (§17.4): 1 = Foam Mats, 2-4 = the giant pads. Server and client read
--   the tier here by stationId (stationTier), never from the client or the GripTier attribute (§17.6).

-- Types

export type Box = {
	position: Vector3,
	size: Vector3,
	facing: Vector3?,
	yaw: number?,
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
	-- aisle: a walkway (a path); may overlap stations. prompt: the §7.7 5-stud radius around a ProximityPrompt (as a
	-- box); it holds its own station's body (Verify exempts station bodies) and may overlap any other volume.
	kind: "aisle" | "station" | "prompt",
	yaw: number?, -- a turn about +Y (the aisles follow their paths)
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
	color: string?, -- the line's own Palette token on a design plate (default: the plate's `color`)
}

-- A design text plate (lobby.js:26-33): a plane with no wood frame, an optional rounded background with an optional
-- border, text in its own colour.
export type PlateStyle = {
	background: string?, -- Palette token of the rounded background; nil = text only (design o.bg null)
	border: string?, -- Palette token of the border (7 px of the 512-px canvas); nil = none (o.border null)
	round: number?, -- corner radius as a share of the plate's short side (design default 0.24)
	color: string, -- Palette token of the text (o.fg; design default ink)
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
	cframe: CFrame?, -- an exact panel frame (Front face = -Z, the readable side), e.g. a plate lying on a tilted top
	plate: PlateStyle?, -- a design plate (no wood frame); nil = the §7.7 sign look
	logo: boolean?, -- the spawn medallion's round logo (lobby.js:149-155)
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
	blueprintId: string, -- Art/SquishyBlueprints giant_* (kept for tools; the design pads have no faces, D5)
	frame: CFrame, -- the design's pad group (lobby.js:359, 363, 383): its base decor is placed in this frame
	center: Vector3, -- floor point under the pad centre (Y 0: the pad's mesh and tiles are measured from the floor)
	footprint: number, -- side of the visual pad (its rounded square, or its circle for a corner radius of half of it)
	cornerRadius: number,
	restTop: number, -- visual top at rest: the design's standing surface
	sinkDepth: number,
	collision: Box, -- the invisible station box (Transparency 1, CanCollide true, CanTouch false)
	collisionTop: number, -- restTop - sinkDepth: feet sink to it on the dented top
	look: { body: string, top: string, transparency: number },
	gate: Gate, -- the jelly cylinder, tagged SD_GripGate (GripTier); invisible (D5)
	signId: string,
	tileSpacing: number, -- path B quilted tiles (§17.6.1), only those inside the rounded footprint are built
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
	nameKey: string, -- the target's name for tools and the hit label (a target, never shown as a player)
}

export type Pedestal = {
	slot: number, -- 1-14, catalog order
	position: Vector3, -- the centre of the pedestal cylinder
	size: Vector3, -- diameter × height × diameter
	facing: Vector3, -- where its squishy looks: its bay's front (lobby.js:269)
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

export type StationFrame = {
	position: Vector3, -- the station centre on the floor
	yaw: number, -- rotation.y (radians)
}

export type Path = {
	id: string, -- the station id it leads to
	from: Vector3, -- on the promenade, radius 31 from the hub centre
	to: Vector3, -- the station end: the approach point
	width: number,
}

-- Constants

local NORTH = Vector3.new(0, 0, -1)
local SOUTH = Vector3.new(0, 0, 1)
local EAST = Vector3.new(1, 0, 0)
local UP = Vector3.new(0, 1, 0)

local KEEP_CLEAR_BOTTOM = 0.5 -- §7.7 props rule 3: nothing collidable between Y 0.5 and 24 above walkable floor
local KEEP_CLEAR_TOP = 24
local KEEP_CLEAR_LIFT = 0.1 -- mat and pad volumes start this far above the standing surface (the body stays out)
local PROMPT_KEEP_CLEAR_RADIUS = 5 -- §7.7 props rule 1: "5-stud radius around every prompt" (kept as a 10 × 10 box)
local PROMPT_DISTANCE = 10 -- §7.6 prompt defaults (V)
local INSPECT_DISTANCE = 12 -- §7.6 collection pedestals
local APPROACH_DEPTH = 8 -- reading (not in design): a stand's keep-clear volume runs this far back along its path
local APPROACH_OVERRUN = 0.5 -- reading: and this far past the path's end, so the end lies inside it, not on a face
local APPROACH_WIDTH = 8 -- reading: as wide as a path (lobby.js:139)
-- Reading: the practice aisle stops this far short of the range entry (72, 62), where its corner meets the range
-- floor's west edge (X 73, lobby.js:402); the range's own volume covers the entry.
local PRACTICE_AISLE_TRIM = 3

-- Private: builders of plain data ---------------------------------------------------------------------------------

-- An axis-aligned volume from its bounds.
local function span(name: string, minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number)
	return {
		name = name,
		position = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2),
		size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ),
	}
end

-- A keep-clear volume over the floor point `center`: `width` along its local X, `depth` along its local Z, turned by
-- `yaw`, from `minY` (default Y 0.5) to Y 24.
local function keepClearAt(
	name: string,
	kind: "aisle" | "station" | "prompt",
	center: Vector3,
	width: number,
	depth: number,
	yaw: number?,
	minY: number?
): KeepClearVolume
	local bottom = minY or KEEP_CLEAR_BOTTOM
	return {
		name = name,
		kind = kind,
		position = Vector3.new(center.X, (bottom + KEEP_CLEAR_TOP) / 2, center.Z),
		size = Vector3.new(width, KEEP_CLEAR_TOP - bottom, depth),
		yaw = yaw,
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

-- Private: the design's station frames (lobby.js:112, 119-130) ---------------------------------------------------

local function newFrame(x: number, z: number, yaw: number?): StationFrame
	-- design: lobby.js:112 (st(): ry = atan2(-x, -z) unless given, so the local +Z faces the hub centre)
	return { position = Vector3.new(x, 0, z), yaw = if yaw ~= nil then yaw else math.atan2(-x, -z) }
end

local HUB_HALF_X = 116 -- design: lobby.js:101 (LOBBY.W 232 / 2)
local HUB_HALF_Z = 92 -- design: lobby.js:101 (LOBBY.D 184 / 2)

local StationFrames: { [string]: StationFrame } = {
	spawn = newFrame(0, 0, 0), -- design: lobby.js:119
	duel = newFrame(0, -66), -- design: lobby.js:120
	box = newFrame(-58, -46), -- design: lobby.js:121
	shop = newFrame(58, -46), -- design: lobby.js:122
	collection = newFrame(-86, 4), -- design: lobby.js:123
	quests = newFrame(84, -14), -- design: lobby.js:124
	daily = newFrame(84, 20), -- design: lobby.js:125
	squeeze = newFrame(-58, 52), -- design: lobby.js:126
	grip = newFrame(-2, 70), -- design: lobby.js:127
	royal = newFrame(46, 58), -- design: lobby.js:128
	practice = newFrame(88, 62, -math.pi / 2), -- design: lobby.js:129
	kit = newFrame(-HUB_HALF_X + 20, -HUB_HALF_Z + 6, 0), -- design: lobby.js:130
}

-- The CFrame of a station frame.
local function frameCF(id: string): CFrame
	local frame = StationFrames[id]
	return CFrame.new(frame.position) * CFrame.Angles(0, frame.yaw, 0)
end

-- A nested design group (grp(), lobby.js:19) of a station: at (x, y, z) in the station, turned by `yaw`.
local function groupCF(id: string, x: number, y: number, z: number, yaw: number?): CFrame
	return frameCF(id) * CFrame.new(x, y, z) * CFrame.Angles(0, yaw or 0, 0)
end

-- A station-local design point in the world.
local function at(id: string, x: number, y: number, z: number): Vector3
	return frameCF(id) * Vector3.new(x, y, z)
end

-- The world direction of a station's front (its local +Z) turned by a further local yaw.
local function frontOf(id: string, yaw: number?): Vector3
	local total = StationFrames[id].yaw + (yaw or 0)
	return Vector3.new(math.sin(total), 0, math.cos(total))
end

-- A design text plate's panel frame: the design plane faces its local +Z, a Roblox panel reads on its Front (-Z), so
-- the panel turns half a turn about its own +Y.
local function plateCF(frame: CFrame): CFrame
	return frame * CFrame.Angles(0, math.pi, 0)
end

-- Private: the hub (lobby.js:101, 115, 426-438) --------------------------------------------------------------------

local Lobby = {
	floorTopY = 0, -- design: lobby.js:115 (floor_base top)
	footprint = { minX = -HUB_HALF_X, maxX = HUB_HALF_X, minZ = -HUB_HALF_Z, maxZ = HUB_HALF_Z }, -- 232 × 184
	-- Walkable: inside the 3-deep kit walls centred on the hub edge (design: lobby.js:430, rb(16, 10, 3)).
	interior = { minX = -114.5, maxX = 114.5, minZ = -90.5, maxZ = 90.5 },
	baseSlab = { position = Vector3.new(0, -1, 0), size = Vector3.new(322, 2, 274), color = "LobbyFloor" } :: Box, -- design: lobby.js:115 (W + 90, 2, D + 90)
	spawnCamera = Vector3.new(0, 5.5, 12.1), -- design: main.js:486 "Spawn eye" (metres / 0.28)
	-- Invisible walls (§7.7): Transparency 1, CanCollide true, CanQuery false, CanTouch false, tag SD_Boundary.
	-- Reading (not in design): just outside the kit walls and their pillars (Ø4.2 on the hub edge, lobby.js:434), so a
	-- player who climbs a wall cap stays in the hub; they stand on the floor (Y 0..60).
	Boundaries = {
		span("WestWall", -122.5, -118.5, 0, 60, -98.5, 98.5),
		span("EastWall", 118.5, 122.5, 0, 60, -98.5, 98.5),
		span("NorthWall", -122.5, 122.5, 0, 60, -98.5, -94.5),
		span("SouthWall", -122.5, 122.5, 0, 60, 94.5, 98.5),
	} :: { Volume },
}

-- Paths from the promenade to every station but the spawn and the kit (lobby.js:133-140): from radius 31 toward the
-- station's centre (or its entry) to `foot + 1` short of it (to its entry), 11 wide to the duel gate, else 8.
local PATH_START_RADIUS = 31 -- design: lobby.js:139
local PATH_WIDTH = 8 -- design: lobby.js:139
local DUEL_PATH_WIDTH = 11 -- design: lobby.js:139
local PATH_STATIONS: { { id: string, foot: number, entry: Vector3? } } = {
	{ id = "duel", foot = 26 }, -- design: lobby.js:120
	{ id = "box", foot = 12 }, -- design: lobby.js:121
	{ id = "shop", foot = 16 }, -- design: lobby.js:122
	{ id = "collection", foot = 18 }, -- design: lobby.js:123
	{ id = "quests", foot = 11 }, -- design: lobby.js:124
	{ id = "daily", foot = 9 }, -- design: lobby.js:125
	{ id = "squeeze", foot = 23 }, -- design: lobby.js:126
	{ id = "grip", foot = 23 }, -- design: lobby.js:127
	{ id = "royal", foot = 13 }, -- design: lobby.js:128
	{ id = "practice", foot = 20, entry = Vector3.new(72, 0, 62) }, -- design: lobby.js:129
}
local Paths: { Path } = {}
local pathEnds: { [string]: Vector3 } = {}
for _, entry in PATH_STATIONS do
	local target = entry.entry or StationFrames[entry.id].position
	local direction = Vector3.new(target.X, 0, target.Z).Unit
	local inset = if entry.entry then 0 else entry.foot + 1 -- design: lobby.js:138
	local path: Path = {
		id = entry.id,
		from = direction * PATH_START_RADIUS,
		to = target - direction * inset,
		width = if entry.id == "duel" then DUEL_PATH_WIDTH else PATH_WIDTH,
	}
	table.insert(Paths, path)
	pathEnds[entry.id] = path.to
end

local Promenade = {
	-- Flat rings around the spawn (lobby.js:142): a curb ring 22.6..33.4 under a path ring 23.4..32.6.
	curb = { inner = 22.6, outer = 33.4, top = 0.06 }, -- design: lobby.js:142
	path = { inner = 23.4, outer = 32.6, top = 0.1 }, -- design: lobby.js:142
	curbExtra = 1.8, -- design: lobby.js:134 (a path's curb is 1.8 wider than the path)
}

-- Private: stations -------------------------------------------------------------------------------------------------

local Spawn = {
	model = "Spawn",
	tag = "SD_LobbySpawn",
	-- spawn_medallion C(14, 14.5, 0.7): Ø29 at the bottom, top Y 0.7 (design: lobby.js:147).
	medallion = { position = Vector3.new(0, 0.35, 0), diameter = 29, height = 0.7, color = "LobbyTrimWhite" } :: Disc,
	-- Reading (not in design: the medallion is the spawn, lobby.js:147): an invisible SpawnLocation inside it, its top
	-- flush with the medallion's, facing north to the duel gate (main.js:486 "Spawn eye"). Neutral, Duration 0.
	location = {
		position = Vector3.new(0, 0.35, 0),
		size = Vector3.new(12, 0.7, 8),
		facing = NORTH,
		color = "LobbyTrimWhite",
	} :: Box,
	top = 0.7, -- design: lobby.js:147
	-- paint_spawn_logo: a circle r 12.8 lying on the medallion at Y 0.72 (design: lobby.js:149-155). The builder's
	-- plate is a thin invisible square that carries the logo's Top SurfaceGui.
	logoPlate = { position = Vector3.new(0, 0.72, 0), size = Vector3.new(25.6, 0.04, 25.6) } :: Box,
	-- wayfinding_post at (19, 0, 19) turned -π/4 (design: lobby.js:157); one arrow per destination (lobby.js:159-166).
	post = groupCF("spawn", 19, 0, 19, -math.pi / 4),
	arrows = {} :: { { key: string, textKey: string, color: string, frame: CFrame } },
}
-- design: lobby.js:159 (destinations, colours) and 161 (arm i at y 5.4 + 1.75 i, its +X toward the station).
for index, arrow in
	{
		{ key = "duel", textKey = "world.arrowDuel", color = "LobbyMint" },
		{ key = "shop", textKey = "world.arrowShop", color = "LobbyButter" },
		{ key = "box", textKey = "world.arrowBoxes", color = "LobbyStrawberry" },
		{ key = "squeeze", textKey = "world.arrowSqueeze", color = "LobbySky" },
		{ key = "grip", textKey = "world.arrowGrip", color = "LobbyViolet" },
		{ key = "practice", textKey = "world.arrowRange", color = "LobbyRangeArrow" },
	}
do
	local target = StationFrames[arrow.key].position
	local angle = math.atan2(target.Z - 19, target.X - 19) -- design: lobby.js:161 (aims at the station centre)
	local frame = Spawn.post * CFrame.new(0, 5.4 + (index - 1) * 1.75, 0) * CFrame.Angles(0, -angle + math.pi / 4, 0)
	table.insert(Spawn.arrows, { key = arrow.key, textKey = arrow.textKey, color = arrow.color, frame = frame })
end

-- Duel gate + queue (lobby.js:120, 169-204). Frame (0, -66), yaw 0: world = local + (0, 0, -66).
local DuelGate = {
	model = "DuelGate",
	podiumTag = "SD_QueuePodium",
	boardTag = "SD_QueueBoard",
	-- queue_stage rb(48, 1.6, 30): the stage floor, top 1.6 (design: lobby.js:172).
	stage = { position = at("duel", 0, 0.8, 0), size = Vector3.new(48, 1.6, 30), color = "LobbyCushionCream" } :: Box,
	-- The queue podium (SD_QueuePodium) is the design's queue_stage_step rb(22, 0.8, 5) (design: lobby.js:173).
	podium = {
		position = at("duel", 0, 0.4, 16.6),
		size = Vector3.new(22, 0.8, 5),
		color = "LobbyCushionCream",
	} :: Box,
	-- NOT IN DESIGN (D11): the live queue board (SD_QueueBoard) as a valance plate under the gate's badge, between the
	-- curtains, below the badge disc (Y 18.6) and above the arch's walkway (clear height 13.4 over the stage).
	statusBoard = { position = at("duel", 0, 16.7, -7), size = Vector3.new(12, 3.4, 0.2), facing = SOUTH } :: Box,
	approach = pathEnds.duel, -- the duel path's end (design: lobby.js:136-140)
	-- "Join 1v1 Queue" / "Leave Queue" (toggle). Reading: at the step's front centre (its front at local z 19.1).
	prompt = prompt("prompt.joinQueue", at("duel", 0, 2, 19.6), "prompt.leaveQueue"),
}

-- Squishy box (lobby.js:121, 206-233). The SD_BoxStand is the design's reveal pedestal (its interaction).
local BOX_ODDS = groupCF("box", -10, 1.4, 2.5, 0.55) -- odds_board group (design: lobby.js:221)
local GiftBoxCounter = {
	model = "GiftBoxCounter",
	tag = "SD_BoxStand",
	boxId = "snack", -- reading: SD_BoxStand's BoxId = the first paid box (Boxes land in Part 7)
	dais = { position = at("box", 0, 0.7, 0), diameter = 23.2, height = 1.4, color = "LobbyLilac" } :: Disc, -- design: lobby.js:209 (C(11, 11.6, 1.4))
	-- reveal_pedestal_body C(2.6, 3.1, 2.6) at the pedestal group (0, 1.4, 6.6) + (0, 1.3, 0) (design: lobby.js:217-218).
	stand = { position = at("box", 0, 2.7, 6.6), diameter = 6.2, height = 2.6, color = "LobbyTrimWhite" } :: Disc,
	-- odds_board_panel rb(7.6, 5.8, 0.6) at the board's (0, 5.4, 0), its face toward the board's front (design:
	-- lobby.js:221-224). BoxController finds it by name ("OddsBoard") next to the stand part.
	oddsBoard = {
		position = BOX_ODDS * Vector3.new(0, 5.4, 0),
		size = Vector3.new(7.6, 5.8, 0.6),
		facing = frontOf("box", 0.55),
		color = "LobbyCushionCream",
	} :: Box,
	oddsFrame = BOX_ODDS,
	mysteryBox = groupCF("box", 0, 1.4, -3), -- the "GiftBox" model's pivot: mystery_box (design: lobby.js:210)
	approach = pathEnds.box,
	-- Restricted/unknown clients relabel it locally to "Shop Squishies". Reading: 0.6 in front of the pedestal.
	prompt = prompt("prompt.seeBoxes", at("box", 0, 3, 10.3), "prompt.shopDirect"),
}

-- Shop counter (lobby.js:122, 235-261).
local ShopCounter = {
	model = "ShopCounter",
	tag = "SD_ShopCounter",
	floor = { position = at("shop", 0, 0.4, 0), size = Vector3.new(30, 0.8, 18), yaw = StationFrames.shop.yaw } :: Box, -- design: lobby.js:238
	-- shop_counter rb(22, 4.4, 5): the SD_ShopCounter (design: lobby.js:243).
	counter = {
		position = at("shop", 0, 3, 1),
		size = Vector3.new(22, 4.4, 5),
		facing = frontOf("shop"),
		color = "LobbyWafer",
	} :: Box,
	turntable = groupCF("shop", 9, 0.8, 9.5), -- preview_turntable (design: lobby.js:255)
	approach = pathEnds.shop,
	prompt = prompt("prompt.openShop", at("shop", 0, 3.4, 4.3)), -- reading: in front of the SHOP plate (lobby.js:250)
}

-- Collection display (lobby.js:123, 263-284): 7 bays on an arc of radius 15 around (0, 3), 2 shelves each, the 14
-- squishies in catalog order (D4: the game's Catalog order; slot i is bay (i - 1) // 2, lower shelf first).
local BAY_RADIUS = 15 -- design: lobby.js:265
local bays: { CFrame } = {}
for k = 0, 6 do
	local a = math.rad(-60 + k * 20) -- design: lobby.js:269
	table.insert(bays, groupCF("collection", math.sin(a) * BAY_RADIUS, 0.8, 3 - math.cos(a) * BAY_RADIUS, -a))
end
local KIOSK = groupCF("collection", 12, 0.8, 7, -0.7) -- inventory_kiosk (design: lobby.js:274)
local PEDESTAL_DIAMETER = 2.8 -- design: lobby.js:280 (C(1.3, 1.4, 0.7))
local PEDESTAL_HEIGHT = 0.7 -- design: lobby.js:280
local pedestals: { Pedestal } = {}
for slot = 1, 14 do -- design: lobby.js:278 (all 14 CATALOG toys)
	local i = slot - 1
	local bay = bays[i // 2 + 1]
	local y = (if i % 2 == 1 then 9.6 else 4) + 0.3 -- design: lobby.js:279
	local position = bay * Vector3.new(0, y + 0.35, 0.3) -- design: lobby.js:280
	local look = bay.LookVector
	table.insert(pedestals, {
		slot = slot,
		position = position,
		size = Vector3.new(PEDESTAL_DIAMETER, PEDESTAL_HEIGHT, PEDESTAL_DIAMETER),
		facing = Vector3.new(-look.X, 0, -look.Z), -- the bay's front: its local +Z faces the arc centre
		prompt = {
			actionKey = "prompt.inspect",
			position = position + Vector3.new(0, PEDESTAL_HEIGHT / 2, 0),
			maxDistance = INSPECT_DISTANCE,
			requiresLineOfSight = false,
		},
	})
end

local Collection = {
	model = "Collection",
	kioskTag = "SD_CollectionKiosk",
	pedestalTag = "SD_CollectionPedestal",
	floor = {
		position = at("collection", 0, 0.4, -2),
		size = Vector3.new(38, 0.8, 26),
		yaw = StationFrames.collection.yaw,
	} :: Box, -- design: lobby.js:266
	bays = bays, -- collection_bay_0..6 frames (design: lobby.js:269)
	pedestals = pedestals,
	-- Client-built per player: owned = full colour, unowned = Lavender silhouette. Reading: the design's toys are 2.6
	-- tall (lobby.js:281); 1.75 stands a Kitty-Bread-sized blueprint (about 1.5 at scale 1) at that height, one scale for
	-- every squishy so their sizes stay comparable.
	squishyScale = 1.75,
	buildStuds = 60, -- models built/animated only within this distance
	ownedKey = "collection.owned",
	notOwnedKey = "collection.notOwned",
	-- kiosk_body rb(3.4, 4.6, 2.4): the SD_CollectionKiosk (design: lobby.js:275).
	kiosk = {
		position = KIOSK * Vector3.new(0, 2.3, 0),
		size = Vector3.new(3.4, 4.6, 2.4),
		facing = frontOf("collection", -0.7),
		color = "LobbyViolet",
	} :: Box,
	kioskFrame = KIOSK,
	approach = pathEnds.collection,
	prompt = prompt("prompt.openCollection", KIOSK * Vector3.new(0, 3, 1.9)), -- reading: 0.7 in front of the kiosk
}

-- Quest board (lobby.js:124, 286-309).
local QuestBoard = {
	model = "QuestBoard",
	tag = "SD_QuestBoard",
	floor = { position = at("quests", 0, 0.4, 0), size = Vector3.new(22, 0.8, 11), yaw = StationFrames.quests.yaw } :: Box, -- design: lobby.js:289
	-- quest_cork rb(19, 12, 1): the SD_QuestBoard (design: lobby.js:291).
	board = {
		position = at("quests", 0, 9, -1.6),
		size = Vector3.new(19, 12, 1),
		facing = frontOf("quests"),
		color = "LobbyCork",
	} :: Box,
	approach = pathEnds.quests,
	prompt = prompt("prompt.viewQuests", at("quests", 0, 4.5, 0.2)), -- reading: in front of the cork, under the cards
}

-- Daily reward (lobby.js:125, 311-333). The SD_DailyStand is the design's dais.
local DailyStand = {
	model = "DailyStand",
	tag = "SD_DailyStand",
	pedestal = { position = at("daily", 0, 0.6, 0), diameter = 15.2, height = 1.2, color = "LobbyLilac" } :: Disc, -- design: lobby.js:314 (C(7.2, 7.6, 1.2))
	gift = groupCF("daily", 0, 1.2, 0), -- the "GiftBox" model's pivot: daily_gift (design: lobby.js:315)
	approach = pathEnds.daily,
	prompt = prompt("prompt.dailyReward", at("daily", 0, 2.5, 8.2)), -- reading: 0.6 in front of the dais
}

-- Squeeze zone (lobby.js:126, 335-352): 6 foam mats on a ring of radius 14 around the statue, mats 1-6 =
-- squeeze_01..06 (the design's foam_mat_1..6).
local MAT_RING_RADIUS = 14 -- design: lobby.js:343
local MAT_DIAMETER = 7.6 -- design: lobby.js:341 (superF 3.8)
local MAT_THICKNESS = 1.5 -- design: lobby.js:341 (superF 0.75 up and down)
local MAT_CENTER_Y = 1.3 -- design: lobby.js:343-344 (mat group at Y 0.6, foam_mat at its 0.7)
local MAT_TOP = MAT_CENTER_Y + MAT_THICKNESS / 2 -- 2.05
local mats: { { id: string, position: Vector3, frame: CFrame } } = {}
for k = 0, 5 do
	local a = (k / 6) * 2 * math.pi + math.pi / 6 -- design: lobby.js:343
	local frame =
		groupCF("squeeze", math.cos(a) * MAT_RING_RADIUS, 0.6, math.sin(a) * MAT_RING_RADIUS, -a + math.pi / 2)
	table.insert(mats, {
		id = string.format("squeeze_%02d", k + 1),
		position = frame * Vector3.new(0, 0.7, 0),
		frame = frame,
	})
end

local SqueezeZone = {
	model = "SqueezeZone",
	floor = { position = at("squeeze", 0, 0.3, 0), diameter = 46, height = 0.6, color = "LobbyCourtMint" } :: Disc, -- design: lobby.js:338 (C(22.4, 23, 0.6))
	mats = mats, -- tag SD_SqueezeStation (StationId, GripTier = 1); no ProximityPrompt in the zone
	matDiameter = MAT_DIAMETER,
	matThickness = MAT_THICKNESS,
	matHeight = MAT_TOP, -- the mats' top above the lobby floor (the standing surface)
	matColor = "LobbyCushionCream", -- design: lobby.js:344
	matRimColor = "LobbyStrawberry", -- design: lobby.js:344
	pulseColor = "Lemon", -- 0.15 s pulse on an accepted squeeze (§7.6)
	-- The giant Kitty Bread, 13 tall (toyAt: max(height, 0.8 × width) = 13), on the plinth, turned 0.25 (design:
	-- lobby.js:351). Decor: CanCollide/CanQuery false. The builder scales the blueprint to that height.
	statue = {
		blueprintId = "kitty_bread",
		height = 13,
		position = at("squeeze", 0, 2.8, 0),
		facing = frontOf("squeeze", 0.25),
	},
	plinth = { position = at("squeeze", 0, 1.4, 0), diameter = 13.6, height = 2.8, color = "LobbyTrimWhite" } :: Disc, -- design: lobby.js:339 (C(6, 6.8, 2.8))
	sparkle = at("squeeze", 0, 9.3, 0), -- reading: the statue's middle (2.8 + 13 / 2)
}

-- Practice range (lobby.js:129, 399-421; D3). Frame (88, 62) turned -90°: world X = 88 - local z, Z = 62 + local x.
-- Throwers stand at local +Z (west) and throw toward local -Z = world +X. The game's 9 targets (3 lanes × 12/20/28
-- studs, one moving, §5.11) stand on the design's 3 lanes, measured from the design's firing line.
local FIRING_LINE_X = 79 -- design: lobby.js:403 (range_firing_line_paint at local z 9)
local LANE_Z = { 52, 62, 72 } -- design: lobby.js:404-406 (local x -10 / 0 / 10)
local TARGET_DISTANCES = { 12, 20, 28 }
local THROW_DIRECTION = EAST
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
			position = Vector3.new(FIRING_LINE_X, 0, z) + THROW_DIRECTION * distance,
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
	-- range_floor rb(38, 0.6, 42) at local (0, 0.3, -6), turned: X 73..115, Z 43..81 (design: lobby.js:402).
	laneFloor = { position = Vector3.new(94, 0.3, 62), size = Vector3.new(42, 0.6, 38), color = "LobbyCourtMint" } :: Box,
	laneFloorTopY = 0.6,
	-- range_firing_line_paint B(32, 0.08, 1.2) at local (0, 0.64, 9): X 78.4..79.6, Z 46..78 (design: lobby.js:403).
	firingLine = {
		position = Vector3.new(FIRING_LINE_X, 0.64, 62),
		size = Vector3.new(1.2, 0.08, 32),
		color = "LobbyTrimWhite",
	} :: Box,
	firingLineX = FIRING_LINE_X,
	-- Reading (D3): the throw box runs 8 deep behind the firing line across the range floor, so the practice path's
	-- end (72, 62) lies inside it.
	throwBox = span("ThrowBox", 71, 79, 0, 12, 43, 81), -- SD_PracticeZone, invisible
	throwDirection = THROW_DIRECTION,
	laneZ = LANE_Z,
	laneWidth = 10, -- design: lobby.js:404 (throw spots 10 apart)
	distances = TARGET_DISTANCES,
	targets = targets, -- anchored; the target hitbox is the player capsule (§5.11)
	-- Reading (D3): each target is dressed as the design's bullseye board (lobby.js:406-409); its centre stands this
	-- far above the floor point, on the upper half of the player capsule the server tests (floor+0..6.1), so a
	-- bullseye hit is a capsule hit (the design's 7.6 put the board above the capsule).
	boardHeight = 4.6,
	-- The "Backstop" part (jelly ripple, splats): inside the design's pillow wall (lobby.js:412-413, pillows X
	-- 110.5..113.5, Y 0..9.2), its front 0.5 behind the pillow fronts so the pillows stand out of it, between the
	-- strawberry frames (Z 44.4..79.6), from the range floor up.
	backstop = {
		position = Vector3.new(112.25, 4.9, 62),
		size = Vector3.new(2.5, 8.6, 35.2),
		color = "LobbyCushionCream",
	} :: Box,
	-- Reading: practice projectiles expire outside this box (the throw box's west edge to the hub's east edge, the
	-- range floor's width, the arena zones' height Y -15..40).
	bounds = span("Bounds", 71, 116, -15, 40, 43, 81),
	boardFrame = groupCF("practice", -16, 0.6, 12, 0.5), -- range_board (design: lobby.js:415)
	approach = pathEnds.practice, -- the practice path's end, the design's entry (72, 62) (lobby.js:129)
}

-- Private: Grip pods and giant pads (§17.6, §17.6.1; D5) -------------------------------------------------------------

-- Reading (D5): the gates are invisible (Config.Grip.Gate transparencies 1); a closed one still stops a too-low
-- level locally. They are tall enough that a jump from a pad's white base (Y 2.2) cannot clear them.
local GATE_DIAMETER = 14
local GATE_HEIGHT = 14

local function giantPad(spec: {
	key: string,
	stationId: string,
	tier: number,
	frame: CFrame,
	footprint: number,
	cornerRadius: number,
	restTop: number,
	sinkDepth: number,
	collisionSide: number,
	look: { body: string, top: string, transparency: number },
}): GiantPad
	local center = Vector3.new(spec.frame.Position.X, 0, spec.frame.Position.Z)
	local collisionTop = spec.restTop - spec.sinkDepth
	return {
		key = spec.key,
		stationId = spec.stationId,
		tier = spec.tier,
		model = "GiantPad_" .. spec.key,
		blueprintId = "giant_" .. (if spec.key == "royal" then "cushion" else spec.key),
		frame = spec.frame,
		center = center,
		footprint = spec.footprint,
		cornerRadius = spec.cornerRadius,
		restTop = spec.restTop,
		sinkDepth = spec.sinkDepth,
		collision = {
			position = Vector3.new(center.X, collisionTop / 2, center.Z),
			size = Vector3.new(spec.collisionSide, collisionTop, spec.collisionSide),
		},
		collisionTop = collisionTop,
		look = spec.look,
		gate = {
			position = Vector3.new(center.X, GATE_HEIGHT / 2, center.Z),
			diameter = GATE_DIAMETER,
			height = GATE_HEIGHT,
			color = "LobbyTrimWhite",
			transparency = 1, -- built CanCollide/CanQuery/CanTouch false; WorldBinder closes it locally (§17.6)
		},
		signId = "pod_" .. spec.key,
		tileSpacing = 1.0,
		tileSize = Vector3.new(2, 1, 2),
		tilesPerSide = math.round(spec.footprint / 1.0),
	}
end

local GIANT_PAD_KEYS = { "jelly", "marshmallow", "royal" }

-- Readings: the corner radius of an n = 3 superellipse pad is the rounded square with the same diagonal reach
-- (3.6 for the jelly shell, 3.0 for the cushion); the marshmallow is round (radius = half its footprint). Collision
-- boxes keep G8's rules (inside the rounded footprint, 0.8 inside the gate).
local GiantPads: { [string]: GiantPad } = {
	jelly = giantPad({
		key = "jelly",
		stationId = "squeeze_07",
		tier = 2,
		frame = groupCF("grip", -11, 0.8, 0), -- jelly_pad (design: lobby.js:359)
		footprint = 10.2, -- design: lobby.js:361 (jelly_shell rb(10.2, 4, 10.2, 3))
		cornerRadius = 3.6,
		restTop = 6.2, -- design: lobby.js:361 (shell top: grip floor 0.8 + 3.4 + 2)
		sinkDepth = 0.5, -- §17.6.1
		collisionSide = 7.8,
		look = { body = "LobbyJellyShell", top = "LobbyJellyShell", transparency = 0.38 }, -- design: lobby.js:79 (opacity .62)
	}),
	marshmallow = giantPad({
		key = "marshmallow",
		stationId = "squeeze_08",
		tier = 3,
		frame = groupCF("grip", 11, 0.8, 0), -- marshmallow_pad (design: lobby.js:363)
		footprint = 10, -- design: lobby.js:364 (superF(5, 2.2, 5): Ø10)
		cornerRadius = 5,
		restTop = 6.6, -- design: lobby.js:364 (0.8 + 3.6 + 2.2)
		sinkDepth = 0.6, -- §17.6.1
		collisionSide = 6.8,
		look = { body = "LobbyMarshmallow", top = "LobbyMarshmallow", transparency = 0 }, -- design: lobby.js:79
	}),
	royal = giantPad({
		key = "royal",
		stationId = "squeeze_09",
		tier = 4,
		frame = groupCF("royal", 0, 2, 0), -- royal_cushion (design: lobby.js:383)
		footprint = 8.4, -- design: lobby.js:384 (royal_cushion_body rb(8.4, 2.8, 8.4, 3))
		cornerRadius = 3.0,
		restTop = 4.8, -- design: lobby.js:384 (2 + 1.4 + 1.4)
		sinkDepth = 0.7, -- §17.6.1 (softest)
		collisionSide = 6.4,
		look = { body = "LobbyRoyalVelvet", top = "LobbyRoyalVelvet", transparency = 0 }, -- design: lobby.js:77
	}),
}

local Pods = {
	gym = {
		model = "GripGym",
		floor = {
			position = at("grip", 0, 0.4, 0),
			size = Vector3.new(44, 0.8, 24),
			yaw = StationFrames.grip.yaw,
			color = "LobbyLilac",
		} :: Box, -- design: lobby.js:357
		padKeys = { "jelly", "marshmallow" },
	},
	royal = {
		model = "RoyalPod",
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
		top = MAT_TOP,
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

-- Reading (not in design): on the floor in front of the queue step, beside the duel path's end, facing the hub.
local ReturnPoints: { ReturnPoint } = {
	{ slot = 1, position = at("duel", -6, 0, 24), facing = SOUTH }, -- reading: Slot 1 = west
	{ slot = 2, position = at("duel", 6, 0, 24), facing = SOUTH },
}

local Props = {
	-- The 4 corner lollipops (design: lobby.js:468): a stick 24 tall, a disk of radius 7 facing ±Z with swirl rings,
	-- (ca, cb) colours per corner. The client spins them about the stick (D12: Lollipop1..4 keep the game's motion).
	lollipops = {
		positions = {
			Vector3.new(-HUB_HALF_X + 12, 0, -HUB_HALF_Z + 12), -- design: lobby.js:468 (NW)
			Vector3.new(HUB_HALF_X - 12, 0, -HUB_HALF_Z + 12), -- NE
			Vector3.new(-HUB_HALF_X + 12, 0, HUB_HALF_Z - 12), -- SW
			Vector3.new(HUB_HALF_X - 12, 0, HUB_HALF_Z - 12), -- SE
		},
		colors = {
			{ "LobbyStrawberry", "LobbyMint" }, -- design: lobby.js:468
			{ "LobbyMint", "LobbyButter" },
			{ "LobbyViolet", "LobbyStrawberry" },
			{ "LobbyButter", "LobbySky" },
		},
		height = 24, -- design: lobby.js:468
		radius = 7, -- design: lobby.js:468
	},
	-- Rules (§7.7): decor taller than 3 studs is CanCollide = false and CanQuery = false; Neon only on the lit state
	-- rings (D7); nothing squishy-coloured near the practice lanes.
	collidableMaxHeight = 3,
}

-- A design text plate sign: one line of `textKey` (or a baked `bakeKey`) at 0.56 × the plate's height (lobby.js:30)
-- on a plate of `w` × `h` whose design plane has the frame `frame`.
local function plateSign(
	id: string,
	owner: string,
	frame: CFrame,
	w: number,
	h: number,
	key: string,
	style: PlateStyle,
	opts: { bake: { [string]: number }?, letter: number? }?
): Sign
	local cf = plateCF(frame)
	local letter = if opts and opts.letter then opts.letter else 0.56 * h
	local bake = if opts then opts.bake else nil
	return {
		id = id,
		owner = owner,
		position = cf.Position,
		size = Vector3.new(w, h, 0.05),
		facing = cf.LookVector,
		face = "Front",
		cframe = cf,
		plate = style,
		lines = {
			if bake
				then {
					name = "Text",
					bakeKey = key,
					bakeArgs = bake,
					live = false,
					letterHeight = letter,
					font = "heading",
				}
				else line("Text", key, letter, "heading"),
		},
	}
end

-- Plate styles (lobby.js:29: bg default #FFF9F1 with a 7-px ink border, round 0.24; `null` removes either).
local PLATE_BOXED: PlateStyle = { background = "LobbyPlate", border = "LobbyInk", round = 0.24, color = "LobbyInk" }
local PLATE_TEXT: PlateStyle = { color = "LobbyInk" }

-- Every static SurfaceGui sign: the design's plates (D6, D10) and the game's live boards (D11).
local Signs: { Sign } = {
	{
		-- The spawn logo on the medallion (lobby.js:149-155): "Squishy" over "Duels" in a dashed ring, text top north.
		id = "spawnLogo",
		owner = Spawn.model,
		part = "logoPlate",
		position = Spawn.logoPlate.position,
		size = Spawn.logoPlate.size,
		facing = UP,
		face = "Top",
		textUp = NORTH,
		logo = true,
		lines = {
			-- 150 / 170 px of the 1024-px canvas on 25.6 studs (lobby.js:153).
			{
				name = "Top",
				textKey = "world.logoTop",
				live = false,
				letterHeight = 3.75,
				font = "heading",
				color = "LobbyInk",
			},
			{
				name = "Bottom",
				textKey = "world.logoBottom",
				live = false,
				letterHeight = 4.25,
				font = "heading",
				color = "LobbyStrawberry",
			},
		},
	},
	plateSign("gateBadge", DuelGate.model, groupCF("duel", 0, 24, -4.35), 8.8, 3, "world.gateBadge", PLATE_TEXT), -- design: lobby.js:184
	plateSign(
		"teamMint",
		DuelGate.model,
		groupCF("duel", -6.5, 1.65, 17.1),
		4.6,
		1.5,
		"world.teamMint",
		{ background = "LobbyMint", round = 0.24, color = "White" }
	), -- design: lobby.js:196
	plateSign(
		"teamStrawberry",
		DuelGate.model,
		groupCF("duel", 6.5, 1.65, 17.1),
		6.4,
		1.5,
		"world.teamStrawberry",
		{ background = "LobbyStrawberry", round = 0.24, color = "White" }
	), -- design: lobby.js:196
	{
		-- NOT IN DESIGN (D11): the live queue board on the valance under the badge.
		id = "queueBoard",
		owner = DuelGate.model,
		part = "statusBoard",
		position = DuelGate.statusBoard.position,
		size = DuelGate.statusBoard.size,
		facing = SOUTH,
		face = "Front",
		plate = PLATE_BOXED,
		lines = {
			line("Title", "queue.boardTitle", 1.0, "heading"),
			liveLine("Waiting", "queue.boardWaiting", 0.7),
			liveLine("Active", "queue.boardActive", 0.7),
		},
	},
	{
		-- The mystery box's "?" (lobby.js:216: 3.4 × 3.4, the box group's (0, 4.4, 5.06), 300 px of 512, round .5),
		-- carried by a plate part inside the breathing "GiftBox" model.
		id = "mysteryBox",
		owner = GiftBoxCounter.model,
		part = "mysteryPlate",
		position = plateCF(GiftBoxCounter.mysteryBox * CFrame.new(0, 4.4, 5.06)).Position,
		size = Vector3.new(3.4, 3.4, 0.05),
		facing = frontOf("box"),
		face = "Front",
		cframe = plateCF(GiftBoxCounter.mysteryBox * CFrame.new(0, 4.4, 5.06)),
		plate = { background = "LobbyPlate", border = "LobbyInk", round = 0.5, color = "LobbyStrawberry" },
		lines = { line("Text", "world.mysteryBox", 300 / 512 * 3.4, "heading") },
	},
	{
		-- The odds board (lobby.js:221-228): its cream panel carries the game's odds title and live lines (D10, D11);
		-- the design's bars are placeholders ("% from live config").
		id = "oddsBoard",
		owner = GiftBoxCounter.model,
		part = "oddsBoard",
		position = GiftBoxCounter.oddsBoard.position,
		size = GiftBoxCounter.oddsBoard.size,
		facing = frontOf("box", 0.55),
		face = "Front",
		align = "top",
		plate = PLATE_TEXT,
		lines = {
			line("Title", "box.oddsTitle", 54 / 440 * 5.2, "heading"), -- design: lobby.js:225 (54 px of 440 on 5.2 studs)
			-- Odds lines are generated from Boxes (Part 7); restricted/unknown clients show a note instead (§6.10).
			liveLine("Body", nil, 34 / 440 * 5.2, { "box.restrictedNote", "box.unknownNote" }), -- lobby.js:226 (34 px)
		},
	},
	plateSign("shopPlate", ShopCounter.model, groupCF("shop", 0, 3.1, 3.62), 7, 2.2, "shop.title", PLATE_BOXED), -- design: lobby.js:250
	plateSign(
		"kioskPlate",
		Collection.model,
		KIOSK * CFrame.new(0, 4.98, 0.15) * CFrame.Angles(-math.pi / 2 + 0.35, 0, 0),
		3.8,
		1.2,
		"world.collectionKiosk",
		PLATE_BOXED
	), -- design: lobby.js:276 (lying on the kiosk's tilted top)
	plateSign("questsTitle", QuestBoard.model, groupCF("quests", 0, 17.4, -1.06), 8.6, 2.4, "quest.title", PLATE_TEXT), -- design: lobby.js:295
	plateSign(
		"questsDaily",
		QuestBoard.model,
		groupCF("quests", -6, 13.6, -1.0),
		4.6,
		1.3,
		"world.questsDaily",
		{ background = "LobbyTrimWhite", round = 0.24, color = "LobbyInk" }
	), -- design: lobby.js:298
	plateSign(
		"questsWeekly",
		QuestBoard.model,
		groupCF("quests", 0, 13.6, -1.0),
		4.6,
		1.3,
		"world.questsWeekly",
		{ background = "LobbyTrimWhite", round = 0.24, color = "LobbyInk" }
	),
	plateSign(
		"questsDuels",
		QuestBoard.model,
		groupCF("quests", 6, 13.6, -1.0),
		4.6,
		1.3,
		"world.questsDuels",
		{ background = "LobbyTrimWhite", round = 0.24, color = "LobbyInk" }
	),
	{
		-- NOT IN DESIGN (D11): the daily stand's title and live Status line on a design-style plate at the dais front.
		-- The "DAILY REWARD" title keeps the co-owner's 0.9-stud letters on the old sign's 7-stud width (kept on purpose:
		-- the user's rule 2026-10-11 never undoes the partner's work). Status is built empty: the stand stays inert until
		-- the daily feature registers its UI (§7.6); its owner writes daily.ready / wait.
		id = "dailyStatus",
		owner = DailyStand.model,
		position = plateCF(groupCF("daily", 0, 1.1, 7.65)).Position,
		size = Vector3.new(7, 2, 0.05),
		facing = frontOf("daily"),
		face = "Front",
		cframe = plateCF(groupCF("daily", 0, 1.1, 7.65)),
		plate = PLATE_BOXED,
		lines = {
			line("Title", "daily.title", 0.9, "heading"),
			liveLine("Status", nil, 0.6, { "daily.ready", "daily.wait" }),
		},
	},
	plateSign(
		"kittyBreadPlate",
		SqueezeZone.model,
		groupCF("squeeze", 0, 1.6, 6.75),
		5,
		1.2,
		"squishy.kittyBread.name",
		PLATE_BOXED
	), -- design: lobby.js:340
	-- range_board plates (lobby.js:418): "PRACTICE" in butter over "no duel coins" in white, on the plum panel.
	plateSign(
		"practiceBoard",
		PracticeRange.model,
		PracticeRange.boardFrame * CFrame.new(0, 7.6, 0.45),
		6.6,
		1.5,
		"world.practiceBoard",
		{ color = "LobbyButter" }
	),
	plateSign(
		"practiceNoCoins",
		PracticeRange.model,
		PracticeRange.boardFrame * CFrame.new(0, 5.8, 0.45),
		6.6,
		1.2,
		"world.practiceNoCoins",
		{ color = "White" }
	),
}

-- The wayfinding arrows' names on both faces of each board (lobby.js:165: 4.6 × 1.15 at the arm's (2.9, 0, ±0.33),
-- the back one turned π, no background, ink).
local ARROW_NAMES: { [string]: string } = {
	duel = "Duel",
	shop = "Shop",
	box = "Boxes",
	squeeze = "Squeeze",
	grip = "Grip",
	practice = "Range",
}
for _, arrow in Spawn.arrows do
	local name = "arrow" .. ARROW_NAMES[arrow.key]
	table.insert(
		Signs,
		plateSign(
			name .. "Front",
			Spawn.model,
			arrow.frame * CFrame.new(2.9, 0, 0.33),
			4.6,
			1.15,
			arrow.textKey,
			PLATE_TEXT
		)
	)
	table.insert(
		Signs,
		plateSign(
			name .. "Back",
			Spawn.model,
			arrow.frame * CFrame.new(2.9, 0, -0.33) * CFrame.Angles(0, math.pi, 0),
			4.6,
			1.15,
			arrow.textKey,
			PLATE_TEXT
		)
	)
end

-- The daily calendar's day numbers (lobby.js:322-326): 7 tiles on an arc of radius 10 around (0, 2), each number
-- 0.32 in front of its tile, 1.2 × 1.2, no background.
for d = 0, 6 do
	local a = math.rad(-48 + d * 16) -- design: lobby.js:323
	local x, z = math.sin(a) * 10, -math.cos(a) * 10 + 2 -- design: lobby.js:323
	local frame = groupCF("daily", x + math.sin(-a) * 0.32, 5, z + math.cos(-a) * 0.32, -a) -- design: lobby.js:326
	table.insert(
		Signs,
		plateSign(
			string.format("dailyDay%d", d + 1),
			DailyStand.model,
			frame,
			1.2,
			1.2,
			"world.number",
			PLATE_TEXT,
			{ bake = { n = d + 1 } }
		)
	)
end

-- The foam mats' numbers (lobby.js:348): on each mat's meter side, 1.1 × 1.1, round .5.
for index, mat in mats do
	table.insert(
		Signs,
		plateSign(
			string.format("matNumber%d", index),
			SqueezeZone.model,
			mat.frame * CFrame.new(0, 6.3, 5.66),
			1.1,
			1.1,
			"world.number",
			{ background = "LobbyPlate", border = "LobbyInk", round = 0.5, color = "LobbyInk" },
			{ bake = { n = index } }
		)
	)
end

-- Pod signs (§17.6): `Title` is static (SD_TextKey grip.pad.<key>), `Live` has no SD_TextKey (baked with
-- Strings.format(grip.padNeeds, {level = Config.Grip.Pads[tier].level}), then written only by the SD_GripSign binder).
-- The design's "Jelly Pad" / "Marshmallow Pad" plates sit on the bases' fronts (lobby.js:367, 1 tall); reading: 2.4
-- tall so the Live line fits under the title. NOT IN DESIGN: the Royal Cushion's sign on its upper dais' front.
for _, key in GIANT_PAD_KEYS do
	local pad = GiantPads[key]
	local frame = if key == "royal" then groupCF("royal", 0, 2.2, 10) else pad.frame * CFrame.new(0, 1.2, 6.06) -- design: lobby.js:367 (the base's front face)
	local cf = plateCF(frame)
	table.insert(Signs, {
		id = pad.signId,
		owner = if key == "royal" then Pods.royal.model else Pods.gym.model,
		position = cf.Position,
		size = Vector3.new(if key == "marshmallow" then 7 else 5.6, 2.4, 0.05), -- design: lobby.js:367 (5.4 / 7 wide)
		facing = cf.LookVector,
		face = "Front",
		cframe = cf,
		plate = if key == "royal" then PLATE_BOXED else PLATE_TEXT,
		tag = "SD_GripSign",
		tier = pad.tier,
		lines = {
			line("Title", "grip.pad." .. key, 0.9, "heading"),
			liveLine("Live", "grip.padNeeds", 0.5, { "grip.signLocked", "grip.signOpen" }),
		},
	})
end

-- Keep-clear volumes (§7.7 props rules 1 and 5; §17.6): the generator reports collidable parts inside them. Station
-- volumes cover the floor in front of each stand (its path's last 8 studs) and never contain its body; mat and pad
-- volumes start above the standing surface; station volumes never overlap each other. Aisles follow the paths, as wide
-- as their curbs. Prompt volumes add the 5-stud radius around every prompt.
local KeepClear: { KeepClearVolume } = {
	keepClearAt("spawn", "station", Vector3.zero, 16, 16), -- reading: the spawn area on the medallion
}
for _, path in Paths do
	local delta = path.to - path.from
	local length = delta.Magnitude - (if path.id == "practice" then PRACTICE_AISLE_TRIM else 0)
	local yaw = -math.atan2(delta.Z, delta.X) -- design: lobby.js:134 (a path box's yaw)
	table.insert(
		KeepClear,
		keepClearAt(
			"path_" .. path.id,
			"aisle",
			path.from + delta.Unit * (length / 2),
			length,
			path.width + Promenade.curbExtra,
			yaw
		)
	)
end
-- A stand's volume: the last APPROACH_DEPTH studs of its path and APPROACH_OVERRUN past its end (the approach point).
local function approachVolume(name: string, pathId: string): KeepClearVolume
	local finish = pathEnds[pathId]
	local direction = Vector3.new(finish.X, 0, finish.Z).Unit
	local yaw = -math.atan2(direction.Z, direction.X)
	local depth = APPROACH_DEPTH + APPROACH_OVERRUN
	return keepClearAt(
		name,
		"station",
		finish - direction * (APPROACH_DEPTH - APPROACH_OVERRUN) / 2,
		depth,
		APPROACH_WIDTH,
		yaw
	)
end
table.insert(KeepClear, approachVolume("duelGate", "duel"))
table.insert(KeepClear, approachVolume("giftBoxCounter", "box"))
table.insert(KeepClear, approachVolume("shopCounter", "shop"))
table.insert(KeepClear, approachVolume("collection", "collection"))
table.insert(KeepClear, approachVolume("questBoard", "quests"))
table.insert(KeepClear, approachVolume("dailyStand", "daily"))
-- The practice throw box, above the range floor and the firing line paint.
table.insert(KeepClear, keepClearAt("practiceRange", "station", Vector3.new(75, 0, 62), 8, 38, nil, 0.7))
for _, mat in mats do
	table.insert(
		KeepClear,
		keepClearAt(mat.id, "station", mat.position, 10, 10, nil, MAT_TOP + KEEP_CLEAR_LIFT) -- mats 14 apart: no overlap
	)
end
for _, key in GIANT_PAD_KEYS do
	local pad = GiantPads[key]
	table.insert(
		KeepClear,
		keepClearAt(
			pad.stationId,
			"station",
			pad.center,
			pad.gate.diameter,
			pad.gate.diameter,
			nil,
			pad.collisionTop + KEEP_CLEAR_LIFT
		)
	)
end
-- §7.7 props rule 1: the 5-stud radius around every prompt (each stand prompt and the 14 Inspect prompts), as boxes
-- from Y 0.5 to 24. They hold their own station's body, which the keep-clear test exempts, so they catch decor and
-- the team's Workspace.SD_Manual parts crowding a prompt.
local function promptKeepClear(name: string, point: Vector3)
	local r = PROMPT_KEEP_CLEAR_RADIUS
	table.insert(KeepClear, keepClearAt(name, "prompt", point, 2 * r, 2 * r))
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

-- Audio zones (§7.7): highest priority wins. The lobby zone is the whole hub, the squeeze zone the design's squeeze
-- circle (lobby.js:338: Ø46), the practice zone the range floor with its throw box (X 71..116, Z 43..81; §18.8: it
-- covers the throw box).
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
	audioZone("lobby", Vector3.new(0, 20, 0), Vector3.new(232, 40, 184), 1, "music.lobby", 1.0, "amb.lobby"),
	audioZone("squeeze", Vector3.new(-58, 15, 52), Vector3.new(46, 30, 46), 2, "music.lobby", 0.8, "amb.lobby"),
	audioZone("practice", Vector3.new(93.5, 15, 62), Vector3.new(45, 30, 38), 2, "music.lobby", 0.6, "amb.lobby"),
}

-- Activities and their walk points (routes, waypoints): the stands' approaches are their paths' ends; the squeeze
-- zone counts each mat; the Grip pods are separate activities because of the G-D exception (§17.0).
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
local nearestMat = matPoints[1]
for _, point in matPoints do
	if point.Magnitude < nearestMat.Magnitude then
		nearestMat = point
	end
end
local Waypoints: { [string]: Vector3 } = {
	spawn = Vector3.zero,
	quests = QuestBoard.approach,
	daily = DailyStand.approach,
	squeeze = nearestMat,
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
	StationFrames = StationFrames, -- the design's station frames (lobby.js:119-130); stationFrame(id) gives the CFrame
	Paths = Paths, -- lobby.js:133-140, in station order
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
	-- User decision 2026-10-11: build the design's lobby (phase 3 spec D1). Its worst route, gift box <-> practice
	-- entry, is 156 studs = 9.75 s, so the §7.5 limits (5 s, pods 7 s) become 10 s and 12 s.
	Routes = {
		walkSpeed = 16,
		maxSeconds = 10, -- between any two activities (§7.5; D1)
		podMaxSeconds = 12, -- G-D exception: routes that involve a Grip pod (D1)
	},
	Budgets = {
		lobbyParts = 2500,
		lobbySurfaceGuis = 64, -- Verify fails above this (§17.6; D6: the design's plates)
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
		SD_CollectionPedestal = #pedestals, -- 14 (D4)
		SD_QuestBoard = 1,
		SD_DailyStand = 1,
		SD_ReturnPoint = 2,
		SD_GripGate = 3,
		SD_GripSign = 3,
		SD_GripLock = 3, -- the design's lock + rope per pad, shown while its gate is closed (D5)
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
		-- Phase 3 (D5): a pad's design lock + rope (a Model with GripTier); WorldBinder shows it while the gate is closed
		-- for the local player.
		GripLock = "SD_GripLock",
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

-- The CFrame of a design station frame ("spawn", "duel", "box", ..., "kit"; lobby.js:112, 119-130), or nil: a design
-- point (x, y, z) of that station is stationFrame(id) * Vector3.new(x, y, z).
function WorldLayout.stationFrame(id: string): CFrame?
	if StationFrames[id] == nil then
		return nil
	end
	return frameCF(id)
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

-- True when `point` lies inside the volume (faces included): axis-aligned, or turned by its `yaw` about +Y.
function WorldLayout.contains(volume: { position: Vector3, size: Vector3 }, point: Vector3): boolean
	local d = point - volume.position
	local yaw = (volume :: any).yaw -- KeepClearVolume.yaw (other volumes have none)
	if yaw ~= nil and yaw ~= 0 then
		d = CFrame.Angles(0, yaw, 0):VectorToObjectSpace(d)
	end
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

-- The CFrame of a Box: rotated so its Front face looks along `facing`, unless `facing` is nil or vertical; else
-- turned by its `yaw` about +Y (a design part's rotation.y).
function WorldLayout.boxCFrame(box: { position: Vector3, facing: Vector3? }): CFrame
	local facing = box.facing
	if facing ~= nil and math.abs(facing.Y) <= 0.99 then
		return CFrame.lookAt(box.position, box.position + facing)
	end
	local yaw = (box :: any).yaw -- Box.yaw (boxes without one are not turned)
	if type(yaw) == "number" then
		return CFrame.new(box.position) * CFrame.Angles(0, yaw, 0)
	end
	return CFrame.new(box.position)
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
