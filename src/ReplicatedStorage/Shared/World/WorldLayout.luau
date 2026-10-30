--!strict
-- WorldLayout: every coordinate, size and tier of the lobby and of the arena template (§5.3, §7.8), as frozen data,
-- plus small pure helpers. Shared: required by the edit-time generators and Verify (through the injected Shared
-- clone; no requires here) and at runtime (station positions and tiers, return points, waypoints, zones, plots).
-- Requiring it has no side effects: it only builds and deep-freezes plain tables.
--
-- The lobby is Squish Island (lobby bases spec 2026-10-11 §2-§4, §7; build plan Phase 4): a round island (grass to
-- r 160, a sand beach to r 176, then the sea) with Squish Square, the hub (Ø140, raised 0.9 above the garden, white
-- curb), at its centre: the duel stage under the duel tower in the middle, the stations in the hub sectors between
-- the 10 paths, and 10 bases in a ring (gates at r 96, backs at r 148) on those paths. The stations keep the Claude
-- Design hub's look (design package sd/lobby.js, phase 3 decisions D1-D14), made compact enough for their sector; a
-- design number carries `-- design: lobby.js:<line>`, an island number `-- spec §<n>` (the lobby bases spec), and a
-- value neither gives is a "reading". This module holds what the game reads (stations, stands, prompts, pads, targets,
-- signs, volumes, routes, plots) and the station frames; the lobby generator (SDTools LobbyBuilder) builds the decor
-- around them in the same frames.
--
-- Frames and units (studs):
-- * Lobby: world coordinates. The hub and base floors have their top at Y 0; the garden lies 0.9 lower (§2). North
--   = -Z. The island centre is the origin: the duel stage and the hub spawn's medallion.
-- * Compass angles (§2's map): clockwise from north, direction (sin a, 0, -cos a). Path k (1..10) runs on angle
--   (k - 1) × 36° from the stage edge (r 22) to plot k's gate (r 96); the hub sectors lie between them, centred on
--   18° + 36° × j. Nothing collidable stands on a path (the generator checks it).
-- * Station frames (StationFrames, stationFrame(id)): a station at (x, 0, z) turned by `yaw` (CFrame.Angles(0, yaw,
--   0)); its local +Z, its front, faces the hub centre unless a yaw is given (the practice range). A station-local
--   point (lx, ly, lz) is stationFrame(id) * Vector3.new(lx, ly, lz); nested groups multiply the same way.
-- * Bases (Neon Sugar part 4): plot i's frame (plotFrame(i)) is Diego's Pen_i at its floor's top, turned like a station
--   frame, local +Z toward the hub: the arch at local z +25.6, the shelf at -21.1.
-- * Arena: relative to the template's `Origin` part (floor centre, floor top Y = 0); long axis = Z; Side A = Z < 0
--   ("Strawberry side"), Side B = Z > 0 ("Mint side"). The slot origins live in Config.Duel.Arena.SlotOrigins.
-- * Box: `position` = centre; `size` = W × H × D in the part's own frame; `facing` = the unit direction its Front
--   (-Z) face looks toward, i.e. CFrame.lookAt(position, position + facing); else `yaw`, a turn about +Y like a design
--   part's (CFrame.Angles(0, yaw, 0)). With neither, or with a vertical facing (floor plates), the part is not rotated
--   and `size` is world X × Y × Z (boxCFrame).
-- * Disc: an upright cylinder (`position` = centre, `diameter`, `height`). Roblox Cylinder parts have their axis on
--   X, so builders rotate them 90° about Z.
-- * Volume: an invisible box (`position` = centre, `size`), axis-aligned unless it has a `yaw` (the keep-clear aisles
--   along the paths): keep-clear volumes, zones, audio zones, boundaries, the practice throw box.
-- * `color` fields are Art/Palette token names (builders use Palette[color]). `*Key` fields are Strings keys, except
--   `musicKey` / `ambienceKey` (AssetTable sound slots).
-- * A squeeze station's `tier` is its GripTier (§17.4): 1 = Foam Mats, the only stations since the giant pads, their
--   Grip gym and Royal pod went (build plan Phase 6). Server and client read the tier here by stationId
--   (stationTier), never from the client or the GripTier attribute (§17.6).

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
	tag: string?, -- an extra tag besides SD_Sign (no sign has one since the pod signs went, build plan Phase 6)
	tier: number?, -- with `tag`: its GripTier attribute
	align: ("center" | "top")?, -- vertical placement of the lines on the panel (default "center")
	cframe: CFrame?, -- an exact panel frame (Front face = -Z, the readable side), e.g. a plate lying on a tilted top
	plate: PlateStyle?, -- a design plate (no wood frame); nil = the §7.7 sign look
	logo: boolean?, -- the spawn medallion's round logo (lobby.js:149-155)
	lines: { SignLine },
}

export type Station = {
	id: string, -- "squeeze_01".."squeeze_06"
	tier: number, -- GripTier
	model: string,
	position: Vector3, -- the point the server measures from: the mat centre
	top: number, -- Y of the standing surface: the mat top
	halfSize: number, -- the mat's radius
}

export type Target = {
	id: string, -- TargetId
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
	points: { Vector3 }, -- floor points a player walks to (approach points, mat centres)
}

export type ReturnPoint = {
	slot: number,
	position: Vector3, -- floor point
	facing: Vector3,
}

-- Batch 3: one queue pad as the game reads it (QueuePads): its top centre, its team and its lane (1..5).
export type QueuePad = { position: Vector3, team: "mint" | "strawberry", lane: number }

export type StationFrame = {
	position: Vector3, -- the station centre on the floor
	yaw: number, -- rotation.y (radians)
}

export type Path = {
	id: string, -- "plot1".."plot10": the plot it leads to
	from: Vector3, -- on the stage edge (r 22)
	to: Vector3, -- the plot's gate (r 96)
	width: number,
}

-- Pens3 phase 1: the pen at one spot count (Bases.pen.steps; wb: only its tier, the pen is the whole base).
export type PenStep = { tier: number }
-- Pens3 phase 12: one biome's look on the highway (Highway.biomes; Palette tokens). `rainbow`: rr_rainbow_lane instead
-- of a tinted lane_tile; `sky`: no ground, the markers and the arch Highway.skyLift up; `arch` nil: the launch gate's
-- banner names the biome.
export type HighwayBiome = {
	model: string,
	nameKey: string,
	nameColor: string,
	laneTop: string?,
	laneEdge: string?,
	rainbow: boolean?,
	rail: string,
	marker: string,
	ground: string?,
	sky: boolean?,
	arch: { main: string, trim: string, scale: number }?,
}

-- Constants

local NORTH = Vector3.new(0, 0, -1)
local SOUTH = Vector3.new(0, 0, 1)
local EAST = Vector3.new(1, 0, 0)
local UP = Vector3.new(0, 1, 0)

local KEEP_CLEAR_BOTTOM = 0.5 -- §7.7 props rule 3: nothing collidable between Y 0.5 and 24 above walkable floor
local KEEP_CLEAR_TOP = 24
local KEEP_CLEAR_LIFT = 0.1 -- mat, pad and stage volumes start this far above the standing surface (the body stays out)
local PROMPT_KEEP_CLEAR_RADIUS = 5 -- §7.7 props rule 1: "5-stud radius around every prompt" (kept as a 10 × 10 box)
local PROMPT_DISTANCE = 10 -- §7.6 prompt defaults (V)
local INSPECT_DISTANCE = 12 -- §7.6 collection pedestals
-- Reading (not in spec): a stand's approach point (where a player uses it, the route and waypoint target) lies
-- APPROACH_STEP in front of the stand's front edge, and its keep-clear volume (as wide as a path) runs from
-- APPROACH_GAP in front of that edge to APPROACH_DEPTH further out, toward the hub centre.
local APPROACH_STEP = 3
local APPROACH_GAP = 0.5
local APPROACH_DEPTH = 8
local APPROACH_WIDTH = 8

-- The island (lobby bases spec §2).
local HUB_RADIUS = 70 -- spec §2: Squish Square Ø140
local STAGE_RADIUS = 22 -- spec §2: the duel stage Ø44
local PATH_WIDTH = 8 -- spec §2: the paths are 8 wide
local BASE_COUNT = 10 -- spec §1 #9
local SECTOR_DEGREES = 360 / BASE_COUNT -- 36: the plots, and their paths, 36° apart (§2)
local BASE_GATE_RADIUS = 96 -- spec §2
local BASE_BACK_RADIUS = 148 -- spec §2
local BASE_DEPTH = BASE_BACK_RADIUS - BASE_GATE_RADIUS -- 52
-- Access2 (owner 2026-10-18 "Both"): the north wall's gap, either side of the bridge's line: its 8-stud walk, the
-- plots' 0.8 fence posts and their 1.1 caps (LobbyBuilder), with a hair to spare.
local BRIDGE_GAP_HALF = PATH_WIDTH / 2 + 1

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

-- The horizontal unit direction of a compass angle in degrees (clockwise from north, -Z).
local function compass(degrees: number): Vector3
	local a = math.rad(degrees)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

-- Private: station frames -----------------------------------------------------------------------------------------

local function newFrame(x: number, z: number, yaw: number?): StationFrame
	-- design: lobby.js:112 (st(): ry = atan2(-x, -z) unless given, so the local +Z faces the hub centre)
	return { position = Vector3.new(x, 0, z), yaw = if yaw ~= nil then yaw else math.atan2(-x, -z) }
end

-- A station in a hub sector: `radius` studs out on compass angle `degrees`, its front toward the hub centre.
local function polarFrame(radius: number, degrees: number): StationFrame
	local p = compass(degrees) * radius
	return newFrame(p.X, p.Z)
end

-- Spec §3: the stations in the sectors between the paths (centred on 18° + 36° j). Readings: each station's radius,
-- the farthest out its sector lets it stand between the paths. Squeeze (270°) reaches into the garden; the practice
-- range runs east (+X) along its sector's middle, so throws still go toward +X (D3). The Grip gym (126°) and the Royal
-- pod (306°) went with the giant pads (build plan Phase 6): their sectors stay open.
local StationFrames: { [string]: StationFrame } = {
	spawn = newFrame(0, 0, 0), -- the stage centre; the hub spawn faces north
	duel = newFrame(0, 0, 0), -- the duel stage under the tower (spec §2), local +Z = south
	shop = polarFrame(56, 18), -- spec §3: 18°
	box = polarFrame(52, 54), -- spec §3: 54°
	practice = newFrame(70, 0, -math.pi / 2), -- spec §3: 90°; local +Z = west (the throwers), -Z = east (the throws)
	quests = polarFrame(53, 162), -- spec §3: 162°
	daily = polarFrame(50, 198), -- spec §3: 198°
	collection = polarFrame(56, 234), -- spec §3: 234°
	squeeze = polarFrame(78, 270), -- spec §3: 270°
	fountain = polarFrame(48, 342), -- spec §3: 342° (a prop, not a station)
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

-- A plate lying on the floor at `position`, its text's top toward `up` (horizontal), read from above.
local function floorPlateFrame(position: Vector3, up: Vector3): CFrame
	return CFrame.fromMatrix(position, up:Cross(UP), up, UP)
end

-- Private: the island (spec §2) -------------------------------------------------------------------------------------

local Island = {
	hub = { radius = HUB_RADIUS, top = 0, height = 0.9, color = "HubTile" }, -- spec §2: Ø140, raised 0.9; §8 tiles
	-- Reading: the white curb (§2, §8) is a 1-stud band around the hub, Prims.LAYER under its floor.
	curb = { radius = HUB_RADIUS + 1, color = "White" },
	-- Reading: the hub's paths (spec §2's paths, carried across the square to the stage) in the second tile colour.
	paving = { from = STAGE_RADIUS, to = HUB_RADIUS - 0.2, color = "HubTileB" },
	grass = { radius = 160, top = -0.9, color = "IslandGrass" }, -- spec §2, §8
	grassEdge = { radius = 162, color = "IslandGrassEdge" }, -- reading: a 2-stud darker edge (§8 grass edge)
	beach = { radius = 176, top = -1.2, color = "IslandSand" }, -- spec §2: the beach r 160-176; §8 sand
	shallow = { radius = 192, top = -1.5, color = "IslandShallow" }, -- reading: shallow water around the beach (§8)
	pathTop = -0.8, -- reading: the garden paths stand 0.1 proud of the grass
	pathColor = "HubTileB",
}

local Lobby = {
	floorTopY = 0, -- the hub and base floors
	hubRadius = HUB_RADIUS,
	stageRadius = STAGE_RADIUS,
	-- The sea (§8): a slab under the island, top Y -1.6. Reading: ±222, so the arena slots' aprons (Config.Duel.Arena,
	-- X ≥ 225) never lie on it (ArenaService_Test reads this size).
	baseSlab = { position = Vector3.new(0, -2.6, 0), size = Vector3.new(444, 2, 444), color = "IslandSea" } :: Box,
	-- Invisible walls (§7.7): Transparency 1, CanCollide true, CanQuery false, CanTouch false, tag SD_Boundary.
	-- Reading: just inside the sea's edge, so nobody walks off the sea into the void; from under the sea to Y 60.
	Boundaries = {
		span("WestWall", -222, -218, -4, 60, -222, 222),
		span("EastWall", 218, 222, -4, 60, -222, 222),
		-- Access2: the north wall in two, open round the bridge (bridge.gapHalf either side of its line).
		span("NorthWallWest", -218, -BRIDGE_GAP_HALF, -4, 60, -222, -218),
		span("NorthWallEast", BRIDGE_GAP_HALF, 218, -4, 60, -222, -218),
		span("SouthWall", -218, 218, -4, 60, 218, 222),
	} :: { Volume },
	-- Access2 (owner 2026-10-18 "Both": walk to the highway's launch deck, and a quick HIGHWAY button): the bridge.
	-- Neon Sugar part 6 (owner 2026-10-24 "yes, build part 6 like that"): built in Studio as
	-- SquishyDuelsLobby.AddedByIntegration.HighwayWalk.Bridge in Diego's colours (his path tiles, magenta posts with cyan
	-- tips and a purple rail inside its 9 studs, lavender legs). One straight ramp along x 0 from the north edge of the
	-- new path behind Pen 7 (z -164, his pen paths' top 0.5), through the north wall's gap to the top front edge of the
	-- deck's back step (HighwayBuilder launch_platform: box(20, 1, 1.5, 0, 0, 7) on Highway.deck.platform, LK:158-164:
	-- Highway.origin z -300 + 35.5 + 7.75; y 0.5 + 1), so nobody steps up from it.
	bridge = {
		x = 0,
		fromZ = -164,
		fromTop = 0.5,
		toZ = -256.75,
		toTop = 1.5,
		width = 9, -- its rails stand inside it
		gapHalf = BRIDGE_GAP_HALF,
	},
}

-- Spec §2: 10 paths, 8 wide, from the stage edge across the square and the garden to each plot's gate.
local Paths: { Path } = {}
for index = 1, BASE_COUNT do
	local out = compass((index - 1) * SECTOR_DEGREES)
	table.insert(Paths, {
		id = "plot" .. index,
		from = out * STAGE_RADIUS,
		to = out * BASE_GATE_RADIUS,
		width = PATH_WIDTH,
	})
end

-- A stand's approach: the point APPROACH_STEP in front of its front edge (`front`, station-local z), its frame's
-- front direction, for the keep-clear volume.
local function approachOf(id: string, front: number): Vector3
	return at(id, 0, 0, front + APPROACH_STEP)
end

-- Private: stations -------------------------------------------------------------------------------------------------

-- The hub spawn: the design's spawn medallion (lobby.js:147-155) as a smaller disc on the stage centre with the logo.
local Spawn = {
	model = "Spawn",
	tag = "SD_LobbySpawn",
	-- Reading: Ø12, 0.3 tall on the stage (top 0.8): top Y 1.1.
	medallion = { position = Vector3.new(0, 0.95, 0), diameter = 12, height = 0.3, color = "LobbyTrimWhite" } :: Disc,
	-- Reading: an invisible SpawnLocation inside it, its top flush with the medallion's, facing north (the hub spawn,
	-- for a player without a plot). Neutral, Duration 0.
	location = {
		position = Vector3.new(0, 0.95, 0),
		size = Vector3.new(6, 0.3, 6),
		facing = NORTH,
		color = "LobbyTrimWhite",
	} :: Box,
	top = 1.1,
	-- The logo's plate (lobby.js:149-155): a thin invisible square on the medallion that carries the logo.
	logoPlate = { position = Vector3.new(0, 1.12, 0), size = Vector3.new(11.2, 0.04, 11.2) } :: Box,
}

-- The duel stage + queue (spec §2: "Duel stage Ø 44, under the tower, same 10 queue pads"; lobby.js:169-204). Frame
-- (0, 0), yaw 0: world = local.
local DuelGate = {
	model = "DuelGate",
	podiumTag = "SD_QueuePodium",
	boardTag = "SD_QueueBoard",
	-- Spec §2: the stage Ø44; reading: 0.8 tall (one step up from the square).
	stage = {
		position = Vector3.new(0, 0.4, 0),
		diameter = 2 * STAGE_RADIUS,
		height = 0.8,
		color = "LobbyCushionCream",
	} :: Disc,
	stageTop = 0.8,
	-- The queue podium (SD_QueuePodium): reading, a round step on the stage's south side, between the south pillars.
	podium = { position = at("duel", 0, 1.2, 15), diameter = 5, height = 0.8, color = "LobbyCushionCream" } :: Disc,
	-- NOT IN DESIGN (D11): the live queue board (SD_QueueBoard) under the crossbar between the south pillars.
	statusBoard = { position = at("duel", 0, 13.2, 12), size = Vector3.new(12, 3.4, 0.2), facing = SOUTH } :: Box,
	approach = Vector3.new(0, 0, 21.5), -- Neon Sugar lobby: 5.5 in front of the podium on the plaza (X 0, Z 16)
	-- "Join 1v1 Queue" / "Leave Queue" (toggle). Reading: 0.5 in front of the podium.
	prompt = prompt("prompt.joinQueue", at("duel", 0, 2.6, 18), "prompt.leaveQueue"),
}

-- Squishy box (lobby.js:121, 206-233), compact (reading: the dais Ø20 and a 0.8 mystery box fit the 54° sector).
local BOX_ODDS = groupCF("box", -7, 1.4, 2, 0.5) -- odds_board group (design: lobby.js:221; reading: moved in)
local GiftBoxCounter = {
	model = "GiftBoxCounter",
	tag = "SD_BoxStand",
	boxId = "snack", -- reading: SD_BoxStand's BoxId = the first paid box (Boxes land in Part 7)
	dais = { position = at("box", 0, 0.7, 0), diameter = 20, height = 1.4, color = "LobbyLilac" } :: Disc, -- lobby.js:209 (reading: Ø20)
	-- reveal_pedestal_body C(2.6, 3.1, 2.6) on the dais (design: lobby.js:217-218; reading: z 5.6).
	stand = { position = at("box", 0, 2.7, 5.6), diameter = 6.2, height = 2.6, color = "LobbyTrimWhite" } :: Disc,
	-- odds_board_panel (design: lobby.js:221-224; reading: 5.6 wide). BoxController finds it by name ("OddsBoard").
	oddsBoard = {
		position = BOX_ODDS * Vector3.new(0, 5.4, 0),
		size = Vector3.new(5.6, 5.8, 0.6),
		facing = frontOf("box", 0.5),
		color = "LobbyCushionCream",
	} :: Box,
	oddsFrame = BOX_ODDS,
	mysteryBox = groupCF("box", 0, 1.4, -3.2), -- the "GiftBox" model's pivot: mystery_box (design: lobby.js:210)
	mysteryScale = 0.8, -- reading: the design's box at 0.8 (8 × 6.4 × 8)
	approach = Vector3.new(19.092, 0, 19.092), -- FULL FINAL lobby: Diego's Hub.MysteryBox.Markers.Prompt
	-- Restricted/unknown clients relabel it locally to "Shop Squishies". Reading: 0.6 in front of the pedestal.
	prompt = prompt("prompt.seeBoxes", at("box", 0, 3, 9.3), "prompt.shopDirect"),
}

-- Shop counter (lobby.js:122, 235-261), compact (reading: a 22-wide stall with an 8-stripe awning).
local ShopCounter = {
	model = "ShopCounter",
	tag = "SD_ShopCounter",
	floor = { position = at("shop", 0, 0.4, -1), size = Vector3.new(22, 0.8, 14), yaw = StationFrames.shop.yaw } :: Box, -- design: lobby.js:238 (reading: 22 × 14)
	-- shop_counter rb(22, 4.4, 5): the SD_ShopCounter (design: lobby.js:243; reading: 14 wide, 4 deep).
	counter = {
		position = at("shop", 0, 3, 1.5),
		size = Vector3.new(14, 4.4, 4),
		facing = frontOf("shop"),
		color = "LobbyWafer",
	} :: Box,
	turntable = groupCF("shop", 7.8, 0, 8.2), -- preview_turntable (design: lobby.js:255; reading: on the square)
	approach = Vector3.new(0, 0, 31), -- FULL FINAL lobby: Diego's Hub.Shop.Markers.Prompt
	prompt = prompt("prompt.openShop", at("shop", 0, 3.4, 4.3)), -- reading: in front of the SHOP plate (lobby.js:250)
}

-- Collection display (lobby.js:123, 263-284), compact: 7 bays on an arc of radius 12 (reading; the design's 15)
-- around (0, 2), 2 shelves each, the 14 squishies in catalog order (D4: slot i is bay (i - 1) // 2, lower shelf first).
local BAY_RADIUS = 12
local BAY_CENTER_Z = 2
local bays: { CFrame } = {}
for k = 0, 6 do
	local a = math.rad(-60 + k * 20) -- design: lobby.js:269
	table.insert(
		bays,
		groupCF("collection", math.sin(a) * BAY_RADIUS, 0.8, BAY_CENTER_Z - math.cos(a) * BAY_RADIUS, -a)
	)
end
local KIOSK = groupCF("collection", 9, 0, 6, -0.6) -- inventory_kiosk (design: lobby.js:274; reading: on the square)
-- Neon Sugar lobby (owner 2026-10-23, "Small squishies on slots"): the 14 squishies stand on the first 14 slot tiles of
-- Diego's IndexShelf (his lobby_manifest, Hub.IndexShelf "Slots"), top row first, left to right as seen from the hub;
-- each faces its shelf unit's front. The SD_CollectionPedestal markers sit on the same tiles (top centre, front).
local PEDESTAL_DIAMETER = 1.8 -- Diego's slot tile, 1.8 x 0.25 x 1.6
local PEDESTAL_HEIGHT = 0.25
local SLOT_TOPS: { { Vector3 } } = {
	{ Vector3.new(-19.7731, 7.65, 34.2597), Vector3.new(0.3944, 0, -0.9189) },
	{ Vector3.new(-22.1623, 7.65, 33.2343), Vector3.new(0.3944, 0, -0.9189) },
	{ Vector3.new(-24.5516, 7.65, 32.2089), Vector3.new(0.3944, 0, -0.9189) },
	{ Vector3.new(-26.4458, 7.65, 30.1227), Vector3.new(0.7071, 0, -0.7071) },
	{ Vector3.new(-28.2843, 7.65, 28.2843), Vector3.new(0.7071, 0, -0.7071) },
	{ Vector3.new(-30.1227, 7.65, 26.4458), Vector3.new(0.7071, 0, -0.7071) },
	{ Vector3.new(-32.2089, 7.65, 24.5516), Vector3.new(0.9189, 0, -0.3944) },
	{ Vector3.new(-33.2343, 7.65, 22.1623), Vector3.new(0.9189, 0, -0.3944) },
	{ Vector3.new(-34.2597, 7.65, 19.7731), Vector3.new(0.9189, 0, -0.3944) },
	{ Vector3.new(-19.7731, 4.65, 34.2597), Vector3.new(0.3944, 0, -0.9189) },
	{ Vector3.new(-22.1623, 4.65, 33.2343), Vector3.new(0.3944, 0, -0.9189) },
	{ Vector3.new(-24.5516, 4.65, 32.2089), Vector3.new(0.3944, 0, -0.9189) },
	{ Vector3.new(-26.4458, 4.65, 30.1227), Vector3.new(0.7071, 0, -0.7071) },
	{ Vector3.new(-28.2843, 4.65, 28.2843), Vector3.new(0.7071, 0, -0.7071) },
}
local pedestals: { Pedestal } = {}
for slot, entry in SLOT_TOPS do
	local position = entry[1] - Vector3.new(0, PEDESTAL_HEIGHT / 2, 0)
	table.insert(pedestals, {
		slot = slot,
		position = position,
		size = Vector3.new(PEDESTAL_DIAMETER, PEDESTAL_HEIGHT, PEDESTAL_DIAMETER),
		facing = entry[2].Unit,
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
		position = at("collection", 0, 0.4, -4.7),
		size = Vector3.new(25.2, 0.8, 15.4),
		yaw = StationFrames.collection.yaw,
	} :: Box, -- design: lobby.js:266 (reading: under the arc only)
	bays = bays, -- collection_bay_0..6 frames (design: lobby.js:269)
	bayRadius = BAY_RADIUS,
	bayCenterZ = BAY_CENTER_Z, -- the arc's centre (station-local z)
	bayWidth = 4.2, -- reading: the design's 5.6 bays narrowed to the smaller arc
	pedestals = pedestals,
	-- Client-built per player: owned = full colour, unowned = Lavender silhouette. Reading: the design's toys are 2.6
	-- tall (lobby.js:281); 1.75 stands a Kitty-Bread-sized blueprint (about 1.5 at scale 1) at that height, one scale for
	-- every squishy so their sizes stay comparable.
	-- Neon Sugar lobby: Diego's slots are 2.6 apart with about 2.4 clear above each tile, so the toys are smaller.
	squishyScale = 1.2,
	buildStuds = 60, -- models built/animated only within this distance
	ownedKey = "collection.owned",
	notOwnedKey = "collection.notOwned",
	-- kiosk_body rb(3.4, 4.6, 2.4): the SD_CollectionKiosk (design: lobby.js:275).
	kiosk = {
		position = KIOSK * Vector3.new(0, 2.3, 0),
		size = Vector3.new(3.4, 4.6, 2.4),
		facing = frontOf("collection", -0.6),
		color = "LobbyViolet",
	} :: Box,
	kioskFrame = KIOSK,
	approach = Vector3.new(-26.5165, 0, 26.5165), -- Neon Sugar lobby: the kiosk marker, 3.5 in front of IndexShelf
	prompt = prompt("prompt.openCollection", KIOSK * Vector3.new(0, 3, 1.9)), -- reading: 0.7 in front of the kiosk
}

-- Quest board (lobby.js:124, 286-309): the design's board as it is.
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
	approach = Vector3.new(0, 0, -36), -- FULL FINAL lobby: Diego's Hub.QuestBoard.Markers.Prompt
	prompt = prompt("prompt.viewQuests", at("quests", 0, 4.5, 0.2)), -- reading: in front of the cork, under the cards
}

-- Daily reward (lobby.js:125, 311-333): the design's dais as it is. The SD_DailyStand is the dais.
local DailyStand = {
	model = "DailyStand",
	tag = "SD_DailyStand",
	pedestal = { position = at("daily", 0, 0.6, 0), diameter = 15.2, height = 1.2, color = "LobbyLilac" } :: Disc, -- design: lobby.js:314 (C(7.2, 7.6, 1.2))
	gift = groupCF("daily", 0, 1.2, 0), -- the "GiftBox" model's pivot: daily_gift (design: lobby.js:315)
	approach = Vector3.new(17.678, 0, -17.678), -- FULL FINAL lobby: Diego's Hub.DailyReward.Markers.Prompt
	prompt = prompt("prompt.dailyReward", at("daily", 0, 2.5, 8.2)), -- reading: 0.6 in front of the dais
}

-- Squeeze zone (lobby.js:126, 335-352): the design's ring of 6 foam mats (radius 14) around the giant Kitty Bread, on a
-- Ø40 floor (reading; the design's 46) that reaches from the square into the garden, so its top stays 0.6.
local MAT_DIAMETER = 7.6 -- design: lobby.js:341 (superF 3.8)
local MAT_THICKNESS = 1.5 -- design: lobby.js:341 (superF 0.75 up and down)
-- FULL FINAL lobby (2026-10-30): the 6 squeeze stations are the seats around Diego's Kitty Bread (his rbxmx,
-- Hub.KittyBread "Seats" 2.6 round, "SeatTops" top 2.5): a station's top is the seat top, its position 0.75 under it
-- as the old mats'; same order as the bun cat's seats were (by angle round the cat).
local MAT_TOP = 2.5
local SEAT_HALF = 1.3
local SEAT_TOPS = {
	Vector3.new(-38, 2.5, -11),
	Vector3.new(-47.526, 2.5, -5.5),
	Vector3.new(-28.474, 2.5, -5.5),
	Vector3.new(-47.526, 2.5, 5.5),
	Vector3.new(-28.474, 2.5, 5.5),
	Vector3.new(-38, 2.5, 11),
}
local mats: { { id: string, position: Vector3, frame: CFrame } } = {}
for k, seatTop in SEAT_TOPS do
	local position = seatTop - Vector3.new(0, 0.75, 0)
	table.insert(mats, {
		id = string.format("squeeze_%02d", k),
		position = position,
		frame = CFrame.new(position),
	})
end

local SqueezeZone = {
	model = "SqueezeZone",
	-- design: lobby.js:338 (C(22.4, 23, 0.6)); reading: Ø40, from the garden (Y -0.9) up to the design's top 0.6
	floor = { position = at("squeeze", 0, -0.15, 0), diameter = 40, height = 1.5, color = "LobbyCourtMint" } :: Disc,
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

-- Practice range (lobby.js:129, 399-421; D3; spec §3: "44-st lane", "3 dummies"): one lane east along its sector's
-- middle (Z 0), so throws go toward +X as before. Frame (70, 0) turned -90°: world X = 70 - local z, Z = local x.
-- Throwers stand at local +Z (west) and throw toward local -Z = world +X. Reading (spec §3 + the moving target the game
-- keeps, §5.11): 3 static dummies 12 / 28 / 34 studs past the firing line and the moving one at 20. The lane's east
-- end (X 91) keeps the pillow wall 2 studs clear of plots 3 and 4, whose gates flank it (72° and 108°).
-- Neon Sugar lobby (2026-10-23): Diego's TargetRange (his lobby_manifest, Hub.TargetRange): a runway X 25..49, Z -5..5,
-- top 0.9, thrown along +X from its west end (the firing line, X 25) at his 4 targets standing still (owner: "Keep
-- Diego's") at X 31 / 36 / 41 / 46, into his cushion wall at X 49..51.
local FIRING_LINE_X = 25
local TARGET_DISTANCES = { 6, 11, 16, 21 }
local THROW_DIRECTION = EAST
local THROW_SPOT = Vector3.new(21, 0, 0) -- inside the throw box, 4 behind the firing line
local RANGE_BOARD = Vector3.new(45, 0, 8.5) -- reading: by the throw box's back corner
local targets: { Target } = {}
for _, distance in TARGET_DISTANCES do
	table.insert(targets, {
		id = string.format("target_%02d", #targets + 1),
		distance = distance,
		position = Vector3.new(FIRING_LINE_X, 0, 0) + THROW_DIRECTION * distance,
		moving = false,
		railLength = 0,
		period = 0,
		nameKey = "practice.targetName",
	})
end

local PracticeRange = {
	model = "PracticeRange",
	zoneTag = "SD_PracticeZone",
	targetTag = "SD_PracticeTarget",
	-- range_floor (design: lobby.js:402); reading: X 46..91, Z -10..10, from the garden (Y -0.9) up to the top 0.6.
	laneFloor = { position = Vector3.new(68.5, -0.15, 0), size = Vector3.new(45, 1.5, 20), color = "LobbyCourtMint" } :: Box,
	laneFloorTopY = 0.9, -- Diego's runway top
	-- range_firing_line_paint B(32, 0.08, 1.2) (design: lobby.js:403; reading: across the 20-wide lane).
	firingLine = {
		position = Vector3.new(FIRING_LINE_X, 0.64, 0),
		size = Vector3.new(1.2, 0.08, 20),
		color = "LobbyTrimWhite",
	} :: Box,
	firingLineX = FIRING_LINE_X,
	-- Reading (D3): the throw box runs 8 deep behind the firing line across the lane, so the approach lies inside it.
	throwBox = span("ThrowBox", 17, 25, 0, 12, -6, 6), -- SD_PracticeZone, invisible (Neon Sugar: before the runway)
	throwDirection = THROW_DIRECTION,
	distances = TARGET_DISTANCES,
	targets = targets, -- anchored; the target hitbox is the player capsule (§5.11)
	-- Reading (D3): each target is dressed as the design's bullseye board (lobby.js:406-409); its centre stands this
	-- far above the floor point, on the upper half of the player capsule the server tests (floor+0..6.1), so a
	-- bullseye hit is a capsule hit (the design's 7.6 put the board above the capsule).
	boardHeight = 4.6,
	-- The "Backstop" part (jelly ripple, splats): inside the design's pillow wall (lobby.js:412-413, pillows X
	-- 88.5..91.5, Y 0..9.2), its front 0.5 behind the pillow fronts so the pillows stand out of it, from the lane top
	-- up; the design's size (the jelly ripple's grid is tuned to it).
	-- Neon Sugar lobby: Diego's cushion wall (X 49..51, Y 0.9..5.7, Z -4.8..4.8).
	backstop = {
		position = Vector3.new(50, 3.3, 0),
		size = Vector3.new(2, 4.8, 9.6),
		color = "LobbyCushionCream",
	} :: Box,
	-- Practice projectiles expire outside this box (the throw box's west edge to past the cushion wall, the ropes
	-- either side, the arena zones' height Y -15..40).
	bounds = span("Bounds", 17, 54, -15, 40, -12, 12),
	-- range_board (design: lobby.js:415): reading, its front (local +Z, the plates' side) toward the throw spot.
	boardFrame = CFrame.lookAt(RANGE_BOARD, 2 * RANGE_BOARD - THROW_SPOT),
	approach = THROW_SPOT,
}

-- Private: stations list (§6.3, §17.6) -----------------------------------------------------------------------------

local Stations: { Station } = {}
for _, mat in mats do
	table.insert(Stations, {
		id = mat.id,
		tier = 1,
		model = SqueezeZone.model,
		position = mat.position,
		top = MAT_TOP,
		halfSize = SEAT_HALF,
	})
end

-- Private: other lobby data ----------------------------------------------------------------------------------------

-- Batch 3 (review #6, the duel pads; Services/FriendDuelService): the 10 queue pads as the game reads them, each with
-- its top centre, its team and its lane (a mint pad and the strawberry pad across from it). Neon Sugar lobby (owner
-- 2026-10-24, "On the Monument stage"): 2 rows of 5 on Diego's Monument base (top 2.3), in front of its pillars: the
-- mint row 5.2 south of the centre, the strawberry row 10, lanes 1..5 left to right from the plaza (X -9.6 .. 9.6, 4.8
-- apart). The pads (0.5 tall, Ø3.6 squares) and their queue_pad_ring parts are in the lobby's DuelGate model.
local MONUMENT_BASE_TOP = 2.3
local QUEUE_PAD_HEIGHT = 0.5
local QueuePads: { QueuePad } = {}
for _, team in { "mint", "strawberry" } do
	for lane = 1, 5 do
		table.insert(QueuePads, {
			position = Vector3.new(
				-9.6 + (lane - 1) * 4.8,
				MONUMENT_BASE_TOP + QUEUE_PAD_HEIGHT,
				if team == "mint" then 5.2 else 10
			),
			team = team,
			lane = lane,
		})
	end
end

-- On the plaza (top 0.6) beside the duel podium in front of the Monument, facing south (players come back from a
-- duel here).
local PLAZA_TOP = 0.6
local ReturnPoints: { ReturnPoint } = {
	{ slot = 1, position = Vector3.new(-6, PLAZA_TOP, 19), facing = SOUTH }, -- Slot 1 = west
	{ slot = 2, position = Vector3.new(6, PLAZA_TOP, 19), facing = SOUTH },
}

local LOLLIPOP_RADIUS = 86 -- reading: in the garden, between two plots' paths
local Props = {
	-- The 4 lollipops (design: lobby.js:468): a stick 24 tall, a disk of radius 7 facing ±Z with swirl rings, (ca, cb)
	-- colours each. The client spins them about the stick (D12: Lollipop1..4 keep the game's motion). Reading
	-- (island): on the garden grass (Y -0.9) in four sectors.
	lollipops = {
		positions = {
			compass(54) * LOLLIPOP_RADIUS + Vector3.new(0, Island.grass.top, 0),
			compass(126) * LOLLIPOP_RADIUS + Vector3.new(0, Island.grass.top, 0),
			compass(234) * LOLLIPOP_RADIUS + Vector3.new(0, Island.grass.top, 0),
			compass(342) * LOLLIPOP_RADIUS + Vector3.new(0, Island.grass.top, 0),
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

-- Private: the bases (Neon Sugar lobby part 4, 2026-10-24) ----------------------------------------------------------

-- The game's plots are Diego's 12 pens (Workspace.SquishyDuelsLobby.Pens.Pen_01..12, tag SD_Base, attribute Plot):
-- Pen_01 at (0, 0, 126), each next one 30° on toward +X (his README). Plot i's frame is Pen_i's pivot at its floor's
-- top (y 1.6), turned like a station frame: its local +Z toward the hub, the arch at z +25.6. Every plot-local number
-- below is read from his pens in Studio (all 12 alike).
local PEN_COUNT = 12
local PEN_RADIUS = 126
local PEN_FLOOR_TOP = 1.6
local baseFrames: { CFrame } = {}
local baseModels: { string } = {}
for index = 1, PEN_COUNT do
	local yaw = math.rad((index - 1) * 360 / PEN_COUNT)
	local at = Vector3.new(math.sin(yaw) * PEN_RADIUS, PEN_FLOOR_TOP, math.cos(yaw) * PEN_RADIUS)
	baseFrames[index] = CFrame.new(at) * CFrame.Angles(0, yaw + math.pi, 0)
	baseModels[index] = string.format("Pen_%02d", index)
end

-- His shelf's cubbies (ShelfSlots.ShelfSlot_01..12): 4 a row, left to right as seen from the pen floor, bottom row
-- first, 7.5 apart and rows 7 apart; cubby k's display pad top in the shelf's frame (Bases.pen.shelf.at).
local SHELF_COLUMNS = 4
local shelfCubbies: { Vector3 } = {}
for k = 1, 12 do
	local column, row = (k - 1) % SHELF_COLUMNS, (k - 1) // SHELF_COLUMNS
	shelfCubbies[k] = Vector3.new(11.25 - 7.5 * column, 2.7 + 7 * row, 0)
end

-- Wb: a plot-local floor rectangle (x and z studs): the squishies' floor, a walk block.
export type FloorRect = { name: string?, minX: number, maxX: number, minZ: number, maxZ: number }
local Bases = {
	width = 42, -- his pen's Base slab, 42 × 54 round its pivot
	depth = 54,
	-- Pens3 phase 1, wb (owner 2026-10-17, "whole base, like Ride a Pet, each time they upgrade they can put more
	-- squishies"): the pen is the whole base from the start and buying PEN SPACE adds squishies, never fence.
	-- steps[spots].tier = the lobby design v6 tier at that many open spots (kit.json K:4084-4169: 1 Wafer, 2 Mint, 3
	-- Royal): the gate posts' colour. edgeMargin = how far a walking squishy keeps from the floor's edges.
	pen = {
		edgeMargin = 0.8,
		steps = {
			[3] = { tier = 1 },
			[4] = { tier = 1 },
			[5] = { tier = 1 },
			[6] = { tier = 2 },
			[7] = { tier = 2 },
			[8] = { tier = 2 },
			[9] = { tier = 2 },
			[10] = { tier = 3 },
			[11] = { tier = 3 },
			[12] = { tier = 3 },
		} :: { [number]: PenStep },
		-- The squishies' floor: his Markers.WalkArea (37.6 × 41.6 at z 3.6, between his fence, shelf and arch); nothing
		-- stands inside it, so no blocks.
		walk = { minX = -18.8, maxX = 18.8, minZ = -17.2, maxZ = 24.4 } :: FloorRect,
		blocks = {} :: { FloorRect },
		-- Each board row's buy spot (BaseService's invisible Face: the row's prompt and glint), just past the right edge
		-- of his board (SignFace, 12.8 × 8 centred at (16, 4.9, 30.86), its front toward the path) at the height of the
		-- row's BUY button (his canvas, 80 px a stud: row 1's centre 1.6 studs under the top, row 2's 5.45), facing the
		-- path. Owner 2026-10-24: row 1 PEN SPACE, row 2 SHELF SPOTS.
		signs = {
			pen = CFrame.new(23.2, 7.3, 30.86) * CFrame.Angles(0, math.pi, 0),
			shelf = CFrame.new(23.2, 3.45, 30.86) * CFrame.Angles(0, math.pi, 0),
		},
		-- His shelf at the plot's back: `at` = its frame on the cubbies' pads (z -21.1), turned like the gate (its front
		-- toward the arch); `cubbies` above. Cubby k is pen slot maxSpots + k (Neon Sugar part 5: one cubby a buy):
		-- the shelf spots in 1..11, the TOP spot in 12. `labelOver` = a coin label's centre over its pad's top (on the
		-- board between the rows, 8.4..9.4 up) and `labelZ` its depth (0.2 in front of the shelf's
		-- front, z -18.4).
		shelf = {
			at = CFrame.new(0, 0, -21.1) * CFrame.Angles(0, math.pi, 0),
			cubbies = shelfCubbies,
			labelOver = 6.2,
			labelZ = -2.9,
		},
		-- The gate with the owner's photo (owner 2026-10-24, "Keep the photo gate sign"): outside the fence at the
		-- pen's front-left, across the arch from his board, on the grass (1.6 under the floor), facing the path.
		gate = CFrame.new(-16, -PEN_FLOOR_TOP, 30.86) * CFrame.Angles(0, math.pi, 0),
		-- The most parts BaseService draws for one pen: the gate's 8 and the 2 buy spots.
		maxParts = 10,
	},
	models = baseModels, -- plot i's Model (tag SD_Base, attribute Plot)
	frames = baseFrames, -- plot i's frame (plotFrame(i))
}

-- Every static SurfaceGui sign: the design's plates (D6, D10), the game's live boards (D11), the bases' name signs.
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
			-- 150 / 170 px of the 1024-px canvas (lobby.js:153), on the 11.2-stud plate.
			{
				name = "Top",
				textKey = "world.logoTop",
				live = false,
				letterHeight = 150 / 1024 * 11.2,
				font = "heading",
				color = "LobbyInk",
			},
			{
				name = "Bottom",
				textKey = "world.logoBottom",
				live = false,
				letterHeight = 170 / 1024 * 11.2,
				font = "heading",
				color = "LobbyStrawberry",
			},
		},
	},
	-- design: lobby.js:184 ("DUELS" on the gate's badge); reading: on the tower deck's south face.
	plateSign("gateBadge", "DuelTower", groupCF("duel", 0, 36.75, 15.56), 10, 2.8, "world.gateBadge", PLATE_TEXT),
	-- design: lobby.js:196 (the team plates); reading: lying on the stage beside each team's pads.
	plateSign(
		"teamMint",
		DuelGate.model,
		floorPlateFrame(at("duel", -16.5, 0.85, 0), NORTH),
		4.6,
		1.5,
		"world.teamMint",
		{ background = "LobbyMint", round = 0.24, color = "White" }
	),
	plateSign(
		"teamStrawberry",
		DuelGate.model,
		floorPlateFrame(at("duel", 16.5, 0.85, 0), NORTH),
		6.4,
		1.5,
		"world.teamStrawberry",
		{ background = "LobbyStrawberry", round = 0.24, color = "White" }
	),
	{
		-- NOT IN DESIGN (D11): the live queue board under the crossbar between the south pillars.
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
		-- carried by a plate part inside the breathing "GiftBox" model; scaled with the box.
		id = "mysteryBox",
		owner = GiftBoxCounter.model,
		part = "mysteryPlate",
		position = plateCF(GiftBoxCounter.mysteryBox * CFrame.new(0, 4.4 * 0.8, 5.06 * 0.8)).Position,
		size = Vector3.new(3.4 * 0.8, 3.4 * 0.8, 0.05),
		facing = frontOf("box"),
		face = "Front",
		cframe = plateCF(GiftBoxCounter.mysteryBox * CFrame.new(0, 4.4 * 0.8, 5.06 * 0.8)),
		plate = { background = "LobbyPlate", border = "LobbyInk", round = 0.5, color = "LobbyStrawberry" },
		lines = { line("Text", "world.mysteryBox", 300 / 512 * 3.4 * 0.8, "heading") },
	},
	{
		-- The odds board (lobby.js:221-228): its cream panel carries the game's odds title and live lines (D10, D11);
		-- the design's bars are placeholders ("% from live config").
		id = "oddsBoard",
		owner = GiftBoxCounter.model,
		part = "oddsBoard",
		position = GiftBoxCounter.oddsBoard.position,
		size = GiftBoxCounter.oddsBoard.size,
		facing = frontOf("box", 0.5),
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
	-- Spec §2: "SQUISH SQUARE" painted on the ground in a ring at r 26-36; reading: two plates on the north and south
	-- paths at r 31, read from the stage.
	plateSign(
		"squishSquareNorth",
		"Hub",
		floorPlateFrame(compass(0) * 31 + Vector3.new(0, 0.08, 0), compass(0)),
		18,
		3,
		"world.squishSquare",
		PLATE_TEXT
	),
	plateSign(
		"squishSquareSouth",
		"Hub",
		floorPlateFrame(compass(180) * 31 + Vector3.new(0, 0.08, 0), compass(180)),
		18,
		3,
		"world.squishSquare",
		PLATE_TEXT
	),
}

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

-- Keep-clear volumes (§7.7 props rules 1 and 5; §17.6): the generator reports collidable parts inside them. Station
-- volumes cover the floor in front of each stand (its approach) and never contain its body; mat, pad and stage volumes
-- start above the standing surface; station volumes never overlap each other. The aisles are the 10 paths (8 wide),
-- from the stage edge to the gates: nothing collidable stands on them (the generator fails the build otherwise).
-- Prompt volumes add the 5-stud radius around every prompt.
local KeepClear: { KeepClearVolume } = {
	-- reading: the spawn area on the medallion, above its top
	keepClearAt("spawn", "station", Vector3.zero, 12, 12, nil, Spawn.top + KEEP_CLEAR_LIFT),
}
for _, path in Paths do
	local delta = path.to - path.from
	table.insert(
		KeepClear,
		keepClearAt(
			"path_" .. path.id,
			"aisle",
			(path.from + path.to) / 2,
			delta.Magnitude,
			path.width,
			-math.atan2(delta.Z, delta.X) -- a path box's yaw (lobby.js:134)
		)
	)
end
-- A stand's volume: from APPROACH_GAP in front of its front edge (station-local z `front`) APPROACH_DEPTH outward.
local function approachVolume(name: string, id: string, front: number, minY: number?): KeepClearVolume
	local depth = APPROACH_DEPTH + APPROACH_GAP
	local center = at(id, 0, 0, front + APPROACH_GAP + depth / 2)
	return keepClearAt(name, "station", center, APPROACH_WIDTH, depth, StationFrames[id].yaw, minY)
end
table.insert(KeepClear, approachVolume("duelGate", "duel", 17.5, DuelGate.stageTop + KEEP_CLEAR_LIFT)) -- the podium's front
table.insert(KeepClear, approachVolume("giftBoxCounter", "box", 10))
table.insert(KeepClear, approachVolume("shopCounter", "shop", 6))
table.insert(KeepClear, approachVolume("collection", "collection", 3))
table.insert(KeepClear, approachVolume("questBoard", "quests", 5.5))
table.insert(KeepClear, approachVolume("dailyStand", "daily", 7.6))
-- The practice throw box, above the lane floor and the firing line paint.
table.insert(KeepClear, keepClearAt("practiceRange", "station", Vector3.new(48, 0, 0), 8, 20, nil, 0.7))
for _, mat in mats do
	table.insert(
		KeepClear,
		keepClearAt(mat.id, "station", mat.position, 10, 10, nil, MAT_TOP + KEEP_CLEAR_LIFT) -- mats 14 apart: no overlap
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

-- Audio zones (§7.7): highest priority wins. The lobby zone is the whole island, the squeeze zone the squeeze floor
-- (Ø40), the practice zone the lane with its throw box (X 44..93; §18.8: it covers the throw box).
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
	-- Neon Sugar lobby (2026-10-23): Diego's island to its shallow water (radius 206), his BunCat, his TargetRange.
	audioZone("lobby", Vector3.new(0, 18, 0), Vector3.new(420, 40, 420), 1, "music.lobby", 1.0, "amb.lobby"),
	audioZone("squeeze", Vector3.new(-38, 15, 0), Vector3.new(32, 30, 32), 2, "music.lobby", 0.8, "amb.lobby"),
	audioZone("practice", Vector3.new(36, 15, 0), Vector3.new(40, 30, 26), 2, "music.lobby", 0.6, "amb.lobby"),
}

-- Activities and their walk points (routes, waypoints): the stands' approaches; the squeeze zone counts each mat.
local matPoints: { Vector3 } = {}
for _, mat in mats do
	table.insert(matPoints, Vector3.new(mat.position.X, 0, mat.position.Z))
end
local Activities: { Activity } = {
	{ name = "quests", points = { QuestBoard.approach } },
	{ name = "daily", points = { DailyStand.approach } },
	{ name = "squeeze", points = matPoints },
	{ name = "collection", points = { Collection.approach } },
	{ name = "shop", points = { ShopCounter.approach } },
	{ name = "duel", points = { DuelGate.approach } },
	{ name = "practice", points = { PracticeRange.approach } },
	{ name = "giftBox", points = { GiftBoxCounter.approach } },
}

-- Waypoint targets (floor points): onboarding and the "show me the way" waypoints. "squeeze" = the mat nearest the
-- spawn.
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
	-- Reading: overlays 0.05 thick (Y 0..0.05); the midline 0.11 (Y 0..0.11), the stripes between (top 0.08): each
	-- layer 0.03 above the one under it (closer they flicker, user bug report 2026-10-11; SDTools Kit/Prims.LAYER), the
	-- midline 0.06 shorter than the band so their ends never meet.
	neutralBand = { position = Vector3.new(0, 0.025, 0), size = Vector3.new(72, 0.05, 16), color = "Cream" } :: Box,
	neutralStripeColor = "Strawberry",
	neutralEdgeColor = "Ink",
	midline = { position = Vector3.new(0, 0.055, 0), size = Vector3.new(71.94, 0.11, 1), color = "White" } :: Box,
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
	-- `heights[n]` above the wall's bottom, `thickness` tall, (wall X - insetX) wide and (wall Z + proud) deep, so 0.03
	-- inside each X face (0.01 flickered, user bug report 2026-10-11) and 0.05 proud of each big face. The jelly
	-- ripple's skin puts a grid row on every stripe edge.
	wallStripes = { heights = { 2, 4, 6 }, thickness = 0.5, proud = 0.1, insetX = 0.06 },
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

-- Private: the highway (pens3 phase 12) ----------------------------------------------------------------------------

-- The lobby design v6 (approved by the owner as the lobby source; work/pens3/PLAN.md "PHASE 12"): `L:n` = layout.json
-- line n, `LK:n` / `HK:n` = lobby-kit.js / highway-kit.js line n, `K:n` = kit.json line n. The game reads the origin,
-- the throw area and the biome looks here; the edit-time generator SDTools HighwayBuilder builds every piece from
-- them (the pieces' own shapes live in the builder, each number with its design line). The biome starts and the
-- Golden Gates are gameplay numbers: Config.Economy.Highway.
-- Lane-local frame: origin * (x, y, z): x to the right looking down the lane, y up from the lane's foot, z = -d (d =
-- studs from the start line, the launch gate, down the lane; highwayCFrame). v6 measures d from its gate at z -62
-- (L:1 "z = -62 - d"), so a v6 point (x, y, z) is the lane-local point (x, y, z + 62); its yaws (L "rot") are kept.
local Highway = {
	-- Reading (PLAN phase 12: the new lobby moves the whole highway by changing this one value): the start line north
	-- of the island, past the sea's edge (±222, Lobby.baseSlab) and clear of the arena slots (X 320/520,
	-- Config.Duel.Arena), facing north (-Z) down the lane. The deck behind it reaches z -242 (the watch steps), the
	-- ground (±200) z -4,300 and the Golden Gates z -8,800.
	origin = CFrame.new(0, 0, -300),
	laneWidth = 30, -- K:1693 lane_tile: a 26-stud top between two 2-stud edges (HK:20)
	tileLength = 50, -- K:1693 lane_tile, K:1719 lane_rail: 50-stud pieces end to end (L:458 ff)
	markerEvery = 100, -- K:1748 "Distance sign every 100 studs" (L:476-477: d 100, 200, ...)
	markerX = 19, -- L:476 (x 19, turned 180°: its face looks back up the lane)
	maxPiecesPerBiome = 600, -- the v6 spec's limit per biome ("≤ 600 placed", spec.txt:157)
	skyLift = 1, -- L:1110, :1130, :1372, :1397, :1597: the sky biomes' markers, arches and the Golden Gates stand 1 up
	deck = {
		platform = Vector3.new(0, 0.5, 35.5), -- L:20 launch_platform (0, 0.5, -26.5)
		-- Pens3 phase 13 (owner 2026-10-18: "it should be a general area where they walk up and everybody can throw"):
		-- no launch spots any more (v6's L:21-30); the deck top is one open throw area (throwArea below).
		watchSteps = {
			{ position = Vector3.new(21, 0.5, 50), yaw = math.rad(38.9) }, -- L:31 watch_steps_01 (21, 0.5, -12)
			{ position = Vector3.new(-21, 0.5, 50), yaw = math.rad(-38.9) }, -- L:32
		},
		gate = Vector3.zero, -- L:33 launch_gate (0, 0, -62), turned 180°: its banner and board look at the deck
		fences = { -10.5, -3.5, 3.5, 10.5 }, -- L:34-37 candy_fence x (z -62, not turned): between the gate's legs
	},
	-- Pens3 phase 13: the one open throw area (owner 2026-10-15 "One big launch area where everyone throws at the same
	-- time, with no waiting or queue"; 2026-10-18 "a general area where they walk up and everybody can throw"): the
	-- deck top as a box, lane-local: L:20's 30 x 15 platform top (y 0.5 + its 2-stud slab, LK:159, centred 1.25 toward
	-- the gate, as HighwayBuilder lays it), 12 studs high [P] (a standing or jumping character's root stays inside).
	-- Anyone whose root is in it may throw (the server checks it, Config.Economy.Highway.areaMarginStuds bigger).
	throwArea = { position = Vector3.new(0, 8.5, 34.25), size = Vector3.new(30, 12, 15) },
	-- The launch board's live lines (LK:172 board_screen, P3D:281-292), built empty; the server writes them (pens3
	-- phase 13, owner 2026-10-15 "The launch gate board shows the last throws and the server best"): the last
	-- boardRows throws of anyone in the server, newest first (LastNWho / LastNDistance, N = 1 the newest), and the
	-- server best (BestWho / BestDistance). [P] 3 rows: what the board's LAST column has room for at the design's
	-- letter size.
	boardRows = 3,
	boardSlots = {
		"Last1Who",
		"Last1Distance",
		"Last2Who",
		"Last2Distance",
		"Last3Who",
		"Last3Distance",
		"BestWho",
		"BestDistance",
	},
	-- K:3136-3529 (the biome table) and the v6 tints (L:458-1397), in Config.Economy.Highway.starts' order.
	biomes = {
		{ -- 1 Candy Meadow (L:458-480)
			model = "Biome_1_CM",
			nameKey = "highway.biome.candyMeadow",
			nameColor = "HighwayPinkIcing",
			laneTop = "HighwayCandyLane",
			laneEdge = "HighwayPinkIcing",
			rail = "HighwayFrosting",
			marker = "HighwayPinkIcing",
			ground = "HighwayCandyGrass",
		},
		{ -- 2 Bakery Town (L:498-538)
			model = "Biome_2_BT",
			nameKey = "highway.biome.bakeryTown",
			nameColor = "HighwayBiome2",
			laneTop = "HighwayBiscuit",
			laneEdge = "HighwayCrust",
			rail = "HighwayFrosting",
			marker = "HighwayBiome2",
			ground = "HighwayBakeryGround",
			arch = { main = "HighwayBiome2", trim = "HighwayFrosting", scale = 1 }, -- L:533
		},
		{ -- 3 Boba Lagoon (L:567-623)
			model = "Biome_3_BL",
			nameKey = "highway.biome.bobaLagoon",
			nameColor = "HighwayBiome3",
			laneTop = "HighwayMilkTea",
			laneEdge = "HighwayBiome3",
			rail = "HighwayFrosting",
			marker = "HighwayBiome3",
			ground = "HighwayWater",
			arch = { main = "HighwayBiome3", trim = "HighwayMilkTea", scale = 1.1 }, -- L:616
		},
		{ -- 4 Frozen Dessert Peaks (L:653-733)
			model = "Biome_4_FD",
			nameKey = "highway.biome.frozenDessertPeaks",
			nameColor = "HighwayBiome4",
			laneTop = "HighwayFrostLane",
			laneEdge = "HighwayBiome4",
			rail = "HighwayWhite",
			marker = "HighwayBiome4",
			ground = "HighwaySnow",
			arch = { main = "HighwayBiome4", trim = "HighwayWhite", scale = 1.2 }, -- L:723
		},
		{ -- 5 Lava Volcano (L:790-910)
			model = "Biome_5_LV",
			nameKey = "highway.biome.lavaVolcano",
			nameColor = "HighwayBiome5",
			laneTop = "HighwayLavaLane",
			laneEdge = "HighwayBiome5",
			rail = "HighwayLavaRail",
			marker = "HighwayBiome5",
			ground = "HighwayBasalt",
			arch = { main = "HighwayBiome5", trim = "HighwayBasalt", scale = 1.3 }, -- L:895
		},
		{ -- 6 Rainbow Road (L:990-1130): the rainbow lane in the sky, no ground (K:3432)
			model = "Biome_6_RR",
			nameKey = "highway.biome.rainbowRoad",
			nameColor = "HighwayLilac",
			rainbow = true,
			rail = "HighwayWhite",
			marker = "HighwayLilac",
			sky = true,
			arch = { main = "HighwayLilac", trim = "HighwayLemon", scale = 1.45 }, -- L:1130
		},
		{ -- 7 Divine Heaven (L:1222-1597): to the Golden Gates, no ground (K:3492)
			model = "Biome_7_DH",
			nameKey = "highway.biome.divineHeaven",
			nameColor = "HighwayBiome7",
			laneTop = "HighwaySignFace",
			laneEdge = "HighwayBiome7",
			rail = "HighwayBiome7",
			marker = "HighwayBiome7",
			sky = true,
			arch = { main = "HighwaySignFace", trim = "HighwayBiome7", scale = 1.6 }, -- L:1397
		},
	} :: { HighwayBiome },
	-- The texts the highway shows besides the biome names (the launch board's static lines, the markers' unit).
	textKeys = { "highway.board.title", "highway.board.lastThrow", "highway.board.serverBest", "highway.marker.unit" },
	-- P13v4 (owner 2026-10-19: the TikTok throw, "BUBBLE RINGS 0/3" and the BULLSEYE targets; work/pens3/p13v4/SPEC.md
	-- 3.3, the numbers from its spec/curve.js): 3 rings a biome, in passing order, each `d` studs down the lane, its
	-- centre `y` above the lane's foot, centred on the lane (x 0), its axis along the lane. [P] The placement rule: C =
	-- the plain arc (HighwayMath.arc) from the throw area's middle (d -34.25, y 7: a standing root 5.5 + releaseUp) of
	-- a throw landing at the biome's end e; c = min(e, C's carry); ring k at round(s + (c - s) x 0.3 / 0.6 / 0.9) (s
	-- the biome's start), its centre C's height there (to 0.1), at least 12 (so it clears the lane). A squishy flying
	-- within ringRadius of a centre goes through it (HighwayMath.ringsHit). HighwayBuilder builds each as a glowing
	-- ring of ringSegments rods, ringTube thick. [P] radius, tube, rods.
	ringRadius = 10,
	ringTube = 0.6,
	ringSegments = 12,
	rings = {
		{ d = 81, y = 55.2, biome = 1 },
		{ d = 162, y = 52.5, biome = 1 },
		{ d = 243, y = 19.7, biome = 1 },
		{ d = 426, y = 61, biome = 2 },
		{ d = 552, y = 44.7, biome = 2 },
		{ d = 678, y = 14.9, biome = 2 },
		{ d = 965, y = 51.6, biome = 3 },
		{ d = 1130, y = 34.9, biome = 3 },
		{ d = 1295, y = 12, biome = 3 },
		{ d = 1725, y = 45.6, biome = 4 },
		{ d = 1950, y = 30, biome = 4 },
		{ d = 2175, y = 12, biome = 4 },
		{ d = 2830, y = 43.1, biome = 5 },
		{ d = 3160, y = 28.1, biome = 5 },
		{ d = 3490, y = 12, biome = 5 },
		{ d = 4420, y = 38.4, biome = 6 },
		{ d = 4840, y = 24.7, biome = 6 },
		{ d = 5260, y = 12, biome = 6 },
		{ d = 6495, y = 33.4, biome = 7 },
		{ d = 6990, y = 21.3, biome = 7 },
		{ d = 7485, y = 12, biome = 7 },
	} :: { { d: number, y: number, biome: number } },
	-- [P] 2 BULLSEYE pads a biome (the video lands on targets; where they lie is a reading): at 0.45 and 0.85 of each
	-- biome, round(s + (e - s) x share), flat on the lane; a landing within padRadius of one is a BULLSEYE
	-- (HighwayMath.bullseye; a pop only, no reward).
	padRadius = 15,
	pads = {
		{ d = 135, biome = 1 },
		{ d = 255, biome = 1 },
		{ d = 525, biome = 2 },
		{ d = 725, biome = 2 },
		{ d = 1115, biome = 3 },
		{ d = 1395, biome = 3 },
		{ d = 1950, biome = 4 },
		{ d = 2350, biome = 4 },
		{ d = 3175, biome = 5 },
		{ d = 3775, biome = 5 },
		{ d = 4900, biome = 6 },
		{ d = 5700, biome = 6 },
		{ d = 7125, biome = 7 },
		{ d = 8125, biome = 7 },
	} :: { { d: number, biome: number } },
}

-- Module table -----------------------------------------------------------------------------------------------------

local WorldLayout = {
	Lobby = Lobby,
	Island = Island, -- the island's ground: the hub, its curb and paving, grass, beach, shallow water (spec §2, §8)
	StationFrames = StationFrames, -- the station frames (spec §3); stationFrame(id) gives the CFrame
	Paths = Paths, -- the 10 paths, stage edge -> gate, plot order (spec §2)
	Spawn = Spawn,
	QuestBoard = QuestBoard,
	DailyStand = DailyStand,
	SqueezeZone = SqueezeZone,
	PracticeRange = PracticeRange,
	DuelGate = DuelGate,
	GiftBoxCounter = GiftBoxCounter,
	ShopCounter = ShopCounter,
	Collection = Collection,
	Stations = Stations, -- squeeze_01..06 in id order
	ReturnPoints = ReturnPoints,
	QueuePads = QueuePads, -- Batch 3: the duel pads (pad index = LobbyBuilder's ring order k + 1)
	Props = Props,
	Signs = Signs,
	KeepClear = KeepClear,
	AudioZones = AudioZones,
	Activities = Activities,
	Waypoints = Waypoints,
	Bases = Bases, -- the island's 10 plots (plotFrame / inPlot)
	-- Straight-line routes at WalkSpeed 16 (= Config.Duel.Rules.Movement.WalkSpeed; real paths ≈ +10%).
	-- User decision 2026-10-11 (phase 3 spec D1): 10 s between activities (its 12 s Grip pod exception went with the
	-- pods, build plan Phase 6).
	Routes = {
		walkSpeed = 16,
		maxSeconds = 10, -- between any two activities (§7.5; D1)
	},
	Budgets = {
		-- Spec §7 part budget, checked by the lobby generator with every plot at its worst (pens3 phase 3: its static
		-- parts + a full pen, Bases.pen.maxParts): the whole island, the hub (everything but the bases, the garden, the
		-- beach and the sky), one base, and the garden + beach + sky. [P] baseParts: 220 held the capsules; a plot's 80
		-- static parts + the 190 of a full pen (phase 10: with its gate and tier III decor) need 270; phase 11: + the
		-- shelf at its worst (Bases.pen.maxParts 196) 276.
		islandParts = 5200,
		hubParts = 2000,
		baseParts = 280,
		gardenParts = 1000,
		lobbySurfaceGuis = 64, -- Verify fails above this (§17.6; D6: the design's plates)
		lobbyDynamicLights = 8, -- none casting shadows (2 used: the FIX 1 lamps)
		-- the statue + 13 halos; about 60 live particles island-wide, on top of Config.Vfx liveParticlesTotal (FxPool's
		-- own bursts only)
		lobbyAmbientEmitters = 14,
		arenaParts = Arena.maxParts,
		arenaDecorParts = Arena.decor.maxParts,
	},
	-- Exact tag counts the lobby generator self-checks (§7.7, §17.6).
	TagCounts = {
		SD_LobbySpawn = 1,
		SD_SqueezeStation = 6,
		SD_PracticeZone = 1,
		SD_PracticeTarget = #targets, -- 4: 3 dummies and the moving target (spec §3)
		SD_QueuePodium = 1,
		SD_QueueBoard = 1,
		SD_BoxStand = 1,
		SD_ShopCounter = 1,
		SD_CollectionKiosk = 1,
		SD_CollectionPedestal = #pedestals, -- 14 (D4)
		SD_QuestBoard = 1,
		SD_DailyStand = 1,
		SD_ReturnPoint = 2,
		SD_Boundary = #Lobby.Boundaries, -- 5 invisible walls (access2: the north one in two, round the bridge)
		SD_AudioZone = #AudioZones, -- lobby, squeeze, practice
		-- Lobby background motion (§18.5.1 A8): the 4 lollipops, both gift boxes and the statue.
		SD_Ambient = #Props.lollipops.positions + 3,
		SD_Base = PEN_COUNT, -- one Model per plot: Diego's pens
		SD_BaseSpawn = PEN_COUNT, -- one SpawnLocation per plot, in front of its arch
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
		-- Reading (§18.5.1 A8 names the tag and attribute; §18.8 lists only the count): here so LobbyBuilder and
		-- AmbientController share one spelling.
		Ambient = "SD_Ambient",
		-- A plot's Model (attribute Plot): BaseService shows its owner's name, colour and pen on it.
		Base = "SD_Base",
		-- A plot's SpawnLocation (attribute Plot): BaseService spawns the plot's owner there.
		BaseSpawn = "SD_BaseSpawn",
		-- FIX 1 (2026-10-14): the lobby's halo emitters (LobbyBuilder); AmbientController lowers their Rate under
		-- ReducedMotion.
		Sparkle = "SD_Sparkle",
		-- Pens3 phase 12 (HighwayBuilder): the launch board (phase 13: no launch spots any more, owner 2026-10-18).
		LaunchBoard = "SD_LaunchBoard",
	},
	Attributes = {
		StationId = "StationId",
		GripTier = "GripTier",
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
		Plot = "Plot", -- Tags.Base and Tags.BaseSpawn: the plot index 1..12
		-- "full" | "light": an old-lobby base part (Verify). Diego's pens have none: no plot colours (owner 2026-10-24).
		BaseTint = "SD_BaseTint",
		-- Pens3 phase 12 (HighwayBuilder): a biome Model's index 1..7 and a placed piece Model's v6 piece name.
		Biome = "Biome",
		Piece = "SD_Piece",
	},
	Arena = Arena,
	-- Pens3 phase 12: the highway (origin, deck, biome looks; highwayCFrame).
	Highway = Highway,
}

-- Private: lookups ---------------------------------------------------------------------------------------------------

local stationById: { [string]: Station } = {}
local stationIds: { string } = {}
for _, station in Stations do
	stationById[station.id] = station
	table.insert(stationIds, station.id)
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

-- The GripTier of a station (1 = Foam Mats), or nil for an unknown id.
function WorldLayout.stationTier(id: string): number?
	local station = stationById[id]
	return if station then station.tier else nil
end

-- Every station id, in order (frozen list).
function WorldLayout.stationIds(): { string }
	return stationIds
end

-- The CFrame of a station frame ("spawn", "duel", "shop", ..., "fountain"; StationFrames), or nil: a station-local
-- point (x, y, z) is stationFrame(id) * Vector3.new(x, y, z).
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

-- The station a root part at `position` stands on (§17.3.6 #5): over a mat (radius + margin), with its height between
-- the station top and top + heightAbove.
-- Config.Squeeze gives margin (padMargin) and heightAbove (Config.Grip.Afk's until slow training went, Phase 6).
function WorldLayout.stationUnder(position: Vector3, margin: number, heightAbove: number): Station?
	for _, station in Stations do
		local dx = position.X - station.position.X
		local dz = position.Z - station.position.Z
		local reach = station.halfSize + margin
		local over = dx * dx + dz * dz <= reach * reach
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

-- The floor point of a waypoint target ("duel", "giftBox", "squeeze", ...), or nil.
function WorldLayout.waypoint(name: string): Vector3?
	return Waypoints[name]
end

-- The frame of plot `index` (1..12, Bases): a plot point (x, y, z) is plotFrame(index) * Vector3.new(x, y, z); nil for
-- anything else.
function WorldLayout.plotFrame(index: number): CFrame?
	return Bases.frames[index]
end

-- True when `position` lies over plot `index`'s footprint (width × depth, edges included; height ignored). False for
-- an unknown plot.
function WorldLayout.inPlot(index: number, position: Vector3): boolean
	local frame: CFrame? = Bases.frames[index]
	if frame == nil then
		return false
	end
	local p = frame:PointToObjectSpace(position)
	return math.abs(p.X) <= Bases.width / 2 and math.abs(p.Z) <= Bases.depth / 2
end

-- Pens3 phase 12: the world CFrame of the highway's lane-local point (x, y, -d): `d` studs from the start line down
-- the lane (Highway.origin's LookVector), `x` to its right, `y` up from the lane's foot; the lane's own turn.
function WorldLayout.highwayCFrame(x: number, y: number, d: number): CFrame
	return Highway.origin * CFrame.new(x, y, -d)
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
	for _, biome in Highway.biomes do
		add(biome.nameKey)
	end
	for _, key in Highway.textKeys do
		add(key)
	end
	table.sort(keys)
	return keys
end

deepFreeze(WorldLayout)

return WorldLayout
