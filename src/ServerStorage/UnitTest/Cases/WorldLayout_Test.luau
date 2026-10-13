--!strict
-- WorldLayout_Test: unit tests for ReplicatedStorage.Shared.World.WorldLayout. Server only (ServerStorage.UnitTest).
-- Contract: the lobby is the Claude Design hub (design package sd/lobby.js; user decision 2026-10-11 "build the
-- design's lobby", phase 3 spec decisions D1-D14). The numbers below are restated from lobby.js (each with its line)
-- and turned into world points with the design's own frame maths (lobby.js:112: a station's local +Z faces the hub
-- centre; three.js rotation.y = CFrame.Angles(0, yaw, 0)), so a drift in WorldLayout is caught:
--   * 12 station frames (lobby.js:119-130), 10 paths from radius 31 (lobby.js:133-140), the 232 × 184 hub;
--   * nine squeeze stations squeeze_01..09 with the §17.4 tiers: the six foam mats on the design ring
--     (lobby.js:342-344), the giant pads on the design pads (D5: Jelly, Marshmallow, Royal Cushion), each collision box
--     inside its rounded footprint and its (invisible) gate;
--   * keep-clear volumes (yawed with their paths) never overlap between stations and hold no station body;
--   * routes within the design's worst real route (D1: 10 s, pods 12 s; was §7.5's 5 s), spawn routes no longer than
--     the design's distances;
--   * every sign, prompt and plate key resolves in Strings; the design plate words (D10) and the game's live lines;
--     the plates sit where lobby.js puts them; within the 64-SurfaceGui budget (D6);
--   * practice range on the design lanes, throws toward +X (D3); 14 collection pedestals facing their bays (D4);
--     return points, audio zones, the corner lollipops, TagCounts;
--   * first person: no prompt and no squeeze station reaches into the practice throw box;
--   * Phase 3 bases (lobby bases spec 2026-10-11 §2, §4; data only): 10 plots 36° apart around the hub centre, gates
--     at radius 96 and backs at 148, facing the hub, 44 × 52, the capsule pads and the spawn inside, no two plots
--     sharing ground; inPlot is the footprint only, never an unknown plot;
--   * the arena (§5.3, §7.8) is unchanged.
-- Pure data: runs in Edit mode on the Shared clone.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

type Bounds = { name: string, low: Vector3, high: Vector3 }
type PadSpec = {
	station: string,
	tier: number,
	center: Vector3,
	footprint: number,
	corner: number,
	restTop: number,
	collision: number,
	sink: number,
}

-- Constants (restated from the design so a drifting layout is caught)

local TIERS: { [string]: number } = {
	squeeze_01 = 1,
	squeeze_02 = 1,
	squeeze_03 = 1,
	squeeze_04 = 1,
	squeeze_05 = 1,
	squeeze_06 = 1,
	squeeze_07 = 2,
	squeeze_08 = 3,
	squeeze_09 = 4,
}

-- Station centres and yaws (lobby.js:112, 119-130); nil yaw = atan2(-x, -z), the front facing the hub centre.
local FRAMES: { [string]: { x: number, z: number, yaw: number? } } = {
	spawn = { x = 0, z = 0, yaw = 0 }, -- lobby.js:119
	duel = { x = 0, z = -66 }, -- lobby.js:120
	box = { x = -58, z = -46 }, -- lobby.js:121
	shop = { x = 58, z = -46 }, -- lobby.js:122
	collection = { x = -86, z = 4 }, -- lobby.js:123
	quests = { x = 84, z = -14 }, -- lobby.js:124
	daily = { x = 84, z = 20 }, -- lobby.js:125
	squeeze = { x = -58, z = 52 }, -- lobby.js:126
	grip = { x = -2, z = 70 }, -- lobby.js:127
	royal = { x = 46, z = 58 }, -- lobby.js:128
	practice = { x = 88, z = 62, yaw = -math.pi / 2 }, -- lobby.js:129
	kit = { x = -96, z = -86, yaw = 0 }, -- lobby.js:130 (-116 + 20, -92 + 6)
}

-- Path ends (lobby.js:136-140: radius 31 toward the station or its entry, ending foot + 1 short of its centre).
local PATH_ENDS: { [string]: Vector3 } = {
	duel = Vector3.new(0, 0, -39),
	box = Vector3.new(-47.81, 0, -37.92),
	shop = Vector3.new(44.68, 0, -35.44),
	collection = Vector3.new(-67.02, 0, 3.12),
	quests = Vector3.new(72.16, 0, -12.03),
	daily = Vector3.new(74.27, 0, 17.68),
	squeeze = Vector3.new(-40.13, 0, 35.98),
	grip = Vector3.new(-1.31, 0, 46.01),
	royal = Vector3.new(37.3, 0, 47.03),
	practice = Vector3.new(72, 0, 62),
}

-- The giant pad table (D5): design centres (lobby.js:359, 363, 383), footprints and rest tops (lobby.js:361, 364,
-- 384); corner radii and collision boxes are the readings that keep G8's rules; sinkDepth is §17.6.1's.
local GIANT_PADS: { [string]: PadSpec } = {
	jelly = {
		station = "squeeze_07",
		tier = 2,
		center = Vector3.new(8.9955, 0, 70.3142),
		footprint = 10.2,
		corner = 3.6,
		restTop = 6.2,
		collision = 7.8,
		sink = 0.5,
	},
	marshmallow = {
		station = "squeeze_08",
		tier = 3,
		center = Vector3.new(-12.9955, 0, 69.6858),
		footprint = 10,
		corner = 5,
		restTop = 6.6,
		collision = 6.8,
		sink = 0.6,
	},
	royal = {
		station = "squeeze_09",
		tier = 4,
		center = Vector3.new(46, 0, 58),
		footprint = 8.4,
		corner = 3.0,
		restTop = 4.8,
		collision = 6.4,
		sink = 0.7,
	},
}
local GATE_DIAMETER = 14 -- reading (D5): invisible; the design shows its lock and rope instead
local GATE_HEIGHT = 14 -- reading: taller than a jump from a pad's base
local GATE_CLEARANCE = 0.8
local CORNER_MARGIN = 0.1
local POSITION_TOLERANCE = 0.01 -- studs; the design numbers are restated with two decimals
local FLOAT_TOLERANCE = 1e-4 -- Vector3 components are single precision

-- Spawn routes (from the medallion centre to the path ends, B.2 table; pods to their centres; squeeze to the mat
-- nearest the spawn), in studs; the layout's may not be longer.
local SPAWN = Vector3.zero
local SPAWN_ROUTES: { [string]: number } = {
	quests = 73.2,
	daily = 76.3,
	squeeze = 63.9,
	collection = 67.1,
	shop = 57.0,
	duel = 39.0,
	practice = 95.0,
	giftBox = 61.0,
	jellyPad = 70.9,
	marshmallowPad = 70.9,
	royalPad = 74.0,
}
local ROUTE_TOLERANCE = 0.1

-- Exact texts: the design's plate words (D10, new keys) and the game's live lines and prompts it keeps.
local TEXTS: { [string]: string } = {
	["world.logoTop"] = "Squishy", -- lobby.js:153
	["world.logoBottom"] = "Duels", -- lobby.js:153
	["world.arrowDuel"] = "DUEL", -- lobby.js:159
	["world.arrowShop"] = "SHOP",
	["world.arrowBoxes"] = "BOXES",
	["world.arrowSqueeze"] = "SQUEEZE",
	["world.arrowGrip"] = "GRIP",
	["world.arrowRange"] = "RANGE",
	["world.gateBadge"] = "DUELS", -- lobby.js:184
	["world.teamMint"] = "MINT", -- lobby.js:196
	["world.teamStrawberry"] = "STRAWBERRY", -- lobby.js:196
	["world.mysteryBox"] = "?", -- lobby.js:216
	["world.collectionKiosk"] = "Collection", -- lobby.js:276
	["world.questsDaily"] = "Daily", -- lobby.js:296
	["world.questsWeekly"] = "Weekly",
	["world.questsDuels"] = "Duels",
	["world.number"] = "{n}", -- lobby.js:326, 348
	["world.practiceBoard"] = "PRACTICE", -- lobby.js:418
	["world.practiceNoCoins"] = "no duel coins", -- lobby.js:418
	["shop.title"] = "SHOP", -- lobby.js:250
	["quest.title"] = "QUESTS", -- lobby.js:295
	["squishy.kittyBread.name"] = "Kitty Bread", -- lobby.js:340
	["grip.pad.jelly"] = "Jelly Pad", -- lobby.js:367
	["grip.pad.marshmallow"] = "Marshmallow Pad", -- lobby.js:367
	["grip.pad.royal"] = "Royal Cushion",
	-- The game's live lines and prompts (D10, D11).
	["queue.boardTitle"] = "Duel Queue",
	["queue.boardWaiting"] = "Waiting: {count}",
	["queue.boardActive"] = "Duels in progress: {count} of {max}",
	["box.oddsTitle"] = "Box Odds",
	["box.restrictedNote"] = "Coin boxes aren't available on your account. You can buy any squishy directly in the Shop, "
		.. "and day 7 of Daily Rewards gives a free Treat Box.",
	["box.unknownNote"] = "Couldn't check box availability. Try again.",
	["daily.ready"] = "Ready to claim!",
	["daily.wait"] = "Next reward in {time}",
	["grip.padNeeds"] = "Needs Grip Lv {level}",
	["grip.signLocked"] = "Needs Grip Lv {level} · You: Lv {have}",
	["grip.signOpen"] = "Open · +{coins} Coins · x{mult} Grip",
	["prompt.joinQueue"] = "Join 1v1 Queue",
	["prompt.leaveQueue"] = "Leave Queue",
	["prompt.seeBoxes"] = "See Boxes",
	["prompt.shopDirect"] = "Shop Squishies",
	["prompt.openShop"] = "Open Shop",
	["prompt.openCollection"] = "Open Collection",
	["prompt.viewQuests"] = "View Quests",
	["prompt.dailyReward"] = "Daily Reward",
	["prompt.inspect"] = "Inspect",
	["collection.owned"] = "Owned",
	["collection.notOwned"] = "Not owned yet",
}

-- Helpers

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-6)
end

local function vectorNear(a: Vector3, b: Vector3, tolerance: number?): boolean
	return near(a.X, b.X, tolerance) and near(a.Y, b.Y, tolerance) and near(a.Z, b.Z, tolerance)
end

local function flatNear(a: Vector3, b: Vector3, tolerance: number?): boolean
	return near(a.X, b.X, tolerance) and near(a.Z, b.Z, tolerance)
end

local function show(v: Vector3): string
	return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end

-- The design frame of a station (lobby.js:112).
local function frameOf(id: string): CFrame
	local spec = FRAMES[id]
	local yaw = if spec.yaw ~= nil then spec.yaw else math.atan2(-spec.x, -spec.z)
	return CFrame.new(spec.x, 0, spec.z) * CFrame.Angles(0, yaw, 0)
end

-- A design point: station `id`, then nested groups { x, y, z, yaw } (lobby.js grp()), then a local point.
local function design(id: string, groups: { { number } }, x: number, y: number, z: number): Vector3
	local frame = frameOf(id)
	for _, group in groups do
		frame = frame * CFrame.new(group[1], group[2], group[3]) * CFrame.Angles(0, group[4] or 0, 0)
	end
	return frame * Vector3.new(x, y, z)
end

-- The design front (local +Z) of a station turned by a local yaw.
local function frontOf(id: string, extraYaw: number?): Vector3
	return frameOf(id):VectorToWorldSpace(CFrame.Angles(0, extraYaw or 0, 0):VectorToWorldSpace(Vector3.new(0, 0, 1)))
end

local function discBounds(name: string, disc: any): Bounds
	local r, h = disc.diameter / 2, disc.height / 2
	return {
		name = name,
		low = disc.position - Vector3.new(r, h, r),
		high = disc.position + Vector3.new(r, h, r),
	}
end

-- The 4 corners on the floor plane and the Y range of a (possibly yawed) keep-clear volume.
local function footprintOf(volume: any): ({ Vector2 }, number, number)
	local cf = CFrame.new(volume.position) * CFrame.Angles(0, volume.yaw or 0, 0)
	local h = volume.size / 2
	local corners: { Vector2 } = {}
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local p = cf * Vector3.new(sx * h.X, 0, sz * h.Z)
			table.insert(corners, Vector2.new(p.X, p.Z))
		end
	end
	return corners, volume.position.Y - h.Y, volume.position.Y + h.Y
end

-- Separating axes on the floor plane (yawed volumes) plus the Y ranges: true when two volumes share volume.
local function volumesOverlap(a: any, b: any): boolean
	local ca, aLow, aHigh = footprintOf(a)
	local cb, bLow, bHigh = footprintOf(b)
	if aHigh <= bLow + 1e-6 or bHigh <= aLow + 1e-6 then
		return false
	end
	local function axesOf(corners: { Vector2 }): { Vector2 }
		return { (corners[2] - corners[1]).Unit, (corners[3] - corners[1]).Unit }
	end
	for _, axes in { axesOf(ca), axesOf(cb) } do
		for _, axis in axes do
			local minA, maxA, minB, maxB = math.huge, -math.huge, math.huge, -math.huge
			for _, p in ca do
				local d = p:Dot(axis)
				minA, maxA = math.min(minA, d), math.max(maxA, d)
			end
			for _, p in cb do
				local d = p:Dot(axis)
				minB, maxB = math.min(minB, d), math.max(maxB, d)
			end
			if maxA <= minB + 1e-6 or maxB <= minA + 1e-6 then
				return false
			end
		end
	end
	return true
end

-- An upright disc body (centre, radius, Y range) against a (possibly yawed) volume: true when they share volume.
local function discOverlaps(body: any, volume: any): boolean
	local bodyLow, bodyHigh = body.position.Y - body.size.Y / 2, body.position.Y + body.size.Y / 2
	local h = volume.size / 2
	if bodyHigh <= volume.position.Y - h.Y + 1e-6 or volume.position.Y + h.Y <= bodyLow + 1e-6 then
		return false
	end
	local frame = CFrame.new(volume.position) * CFrame.Angles(0, volume.yaw or 0, 0)
	local p = frame:PointToObjectSpace(Vector3.new(body.position.X, volume.position.Y, body.position.Z))
	local dx = p.X - math.clamp(p.X, -h.X, h.X)
	local dz = p.Z - math.clamp(p.Z, -h.Z, h.Z)
	return dx * dx + dz * dz < (body.radius - 1e-6) ^ 2
end

return function(t: Context)
	local WorldLayout = t.requireShared("World/WorldLayout")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local Catalog = t.requireShared("Catalog")
	local expect = t.expect

	-- A station body as an oriented volume (a yawed or facing Box keeps its own axes; a Disc is its square).
	local function boxBody(name: string, box: any): any
		local cf = WorldLayout.boxCFrame(box)
		local look = cf.LookVector
		return { name = name, position = box.position, size = box.size, yaw = math.atan2(-look.X, -look.Z) }
	end
	local function discBody(name: string, disc: any): any
		local bounds = discBounds(name, disc)
		return { name = name, position = disc.position, size = bounds.high - bounds.low, radius = disc.diameter / 2 }
	end

	-- The collidable station bodies WorldLayout places (the stands, floors and pads the builder makes solid).
	local function stationBodies(): { any }
		local L = WorldLayout
		local bodies: { any } = {
			boxBody("DuelGate.stage", L.DuelGate.stage),
			boxBody("DuelGate.podium", L.DuelGate.podium),
			discBody("GiftBoxCounter.dais", L.GiftBoxCounter.dais),
			discBody("GiftBoxCounter.stand", L.GiftBoxCounter.stand),
			boxBody("GiftBoxCounter.oddsBoard", L.GiftBoxCounter.oddsBoard),
			boxBody("ShopCounter.floor", L.ShopCounter.floor),
			boxBody("ShopCounter.counter", L.ShopCounter.counter),
			boxBody("Collection.kiosk", L.Collection.kiosk),
			boxBody("QuestBoard.floor", L.QuestBoard.floor),
			boxBody("QuestBoard.board", L.QuestBoard.board),
			discBody("DailyStand.pedestal", L.DailyStand.pedestal),
			discBody("SqueezeZone.floor", L.SqueezeZone.floor),
			discBody("SqueezeZone.plinth", L.SqueezeZone.plinth),
			boxBody("PracticeRange.laneFloor", L.PracticeRange.laneFloor),
			boxBody("PracticeRange.backstop", L.PracticeRange.backstop),
			boxBody("Pods.gym.floor", L.Pods.gym.floor),
		}
		for _, key in L.GiantPadKeys do
			local pad = L.GiantPads[key]
			table.insert(bodies, boxBody(`GiantPads.{key}.collision`, pad.collision))
		end
		return bodies
	end

	-- The hub and its frames (lobby.js:101, 112-130) -------------------------------------------------------------

	t.test(
		"the hub is the design's 232 × 184 with its base slab; boundaries stand just outside the kit walls",
		function()
			local lobby = WorldLayout.Lobby
			expect.equal(lobby.footprint.minX, -116) -- lobby.js:101
			expect.equal(lobby.footprint.maxX, 116)
			expect.equal(lobby.footprint.minZ, -92)
			expect.equal(lobby.footprint.maxZ, 92)
			expect.equal(lobby.floorTopY, 0)
			expect.truthy(vectorNear(lobby.baseSlab.size, Vector3.new(322, 2, 274))) -- lobby.js:115
			expect.truthy(vectorNear(lobby.baseSlab.position, Vector3.new(0, -1, 0)))
			expect.equal(#lobby.Boundaries, 4)
			for _, wall in lobby.Boundaries do
				local low, high = wall.position - wall.size / 2, wall.position + wall.size / 2
				-- Outside the kit walls (3 deep on the hub edge, pillars Ø4.2 on it: lobby.js:430, 434).
				local outside = low.X >= 118.1 or high.X <= -118.1 or low.Z >= 94.1 or high.Z <= -94.1
				expect.truthy(outside)
				expect.truthy(low.Y <= 0 and high.Y >= 60)
			end
		end
	)

	t.test("station frames follow lobby.js:119-130; stationFrame maps station-local design points", function()
		for id, spec in FRAMES do
			local frame = WorldLayout.StationFrames[id]
			expect.truthy(frame ~= nil)
			expect.truthy(vectorNear(frame.position, Vector3.new(spec.x, 0, spec.z)))
			local yaw = if spec.yaw ~= nil then spec.yaw else math.atan2(-spec.x, -spec.z)
			expect.near(frame.yaw, yaw, 1e-9)
			local cf = WorldLayout.stationFrame(id)
			expect.truthy(vectorNear(cf * Vector3.new(3, 1, 2), frameOf(id) * Vector3.new(3, 1, 2), FLOAT_TOLERANCE))
		end
		-- The design's own spot checks (phase 3 spec B.2): the box front and the practice range turned west.
		expect.truthy(flatNear(frontOf("box"), Vector3.new(0.7835, 0, 0.6214), 1e-4))
		expect.truthy(flatNear(frontOf("practice"), Vector3.new(-1, 0, 0), 1e-6))
		expect.equal(WorldLayout.stationFrame("nowhere"), nil)
	end)

	t.test(
		"paths run from radius 31 to the station ends, 11 wide to the duel gate, else 8 (lobby.js:133-140)",
		function()
			expect.equal(#WorldLayout.Paths, 10)
			local seen: { [string]: boolean } = {}
			for _, path in WorldLayout.Paths do
				seen[path.id] = true
				local stated = PATH_ENDS[path.id]
				expect.truthy(stated)
				if not flatNear(path.to, stated, POSITION_TOLERANCE) then
					error(`path {path.id} ends at {show(path.to)}, the design says {show(stated)}`)
				end
				expect.near(Vector3.new(path.from.X, 0, path.from.Z).Magnitude, 31, 1e-4)
				expect.equal(path.width, if path.id == "duel" then 11 else 8)
			end
			for id in PATH_ENDS do
				expect.truthy(seen[id])
			end
			-- The promenade rings (lobby.js:142).
			local promenade = WorldLayout.Promenade
			expect.equal(promenade.curb.inner, 22.6)
			expect.equal(promenade.curb.outer, 33.4)
			expect.equal(promenade.path.inner, 23.4)
			expect.equal(promenade.path.outer, 32.6)
		end
	)

	-- Stations and tiers ------------------------------------------------------------------------------------------

	t.test("stations are squeeze_01..09, unique and in id order", function()
		local ids = WorldLayout.stationIds()
		expect.equal(#ids, 9)
		expect.equal(#WorldLayout.Stations, 9)
		local seen: { [string]: boolean } = {}
		for index, station in WorldLayout.Stations do
			expect.equal(station.id, string.format("squeeze_%02d", index))
			expect.equal(ids[index], station.id)
			expect.falsy(seen[station.id])
			seen[station.id] = true
			expect.equal(WorldLayout.station(station.id), station)
		end
		expect.equal(WorldLayout.station("squeeze_10"), nil)
		expect.truthy(table.isfrozen(ids)) -- handed out shared: no caller may change it
	end)

	t.test("station tiers match DESIGN §17.4 (mats 1, Jelly 2, Marshmallow 3, Royal 4)", function()
		for id, tier in TIERS do
			expect.equal(WorldLayout.stationTier(id), tier)
			expect.equal(WorldLayout.station(id).kind, if tier == 1 then "mat" else "giant")
		end
		expect.equal(WorldLayout.stationTier("squeeze_00"), nil)
		expect.equal(WorldLayout.stationTier("practice"), nil)
		expect.equal(WorldLayout.giantPadForStation("squeeze_01"), nil)
		local pads = Config.Grip.Pads
		expect.equal(#pads, 4)
		expect.equal(pads[1].key, "foam")
		for key, spec in GIANT_PADS do
			expect.equal(WorldLayout.giantPadForStation(spec.station).key, key)
			expect.equal(pads[spec.tier].key, key)
		end
	end)

	t.test("the six foam mats sit on the design ring at radius 14 (lobby.js:342-344), Ø7.6, top 2.05", function()
		-- Appendix A4 of the phase 3 spec (world X, Z), mats 1-6.
		local expected = {
			Vector3.new(-60.88, 0, 38.3),
			Vector3.new(-47.58, 0, 42.65),
			Vector3.new(-44.69, 0, 56.35),
			Vector3.new(-55.12, 0, 65.7),
			Vector3.new(-68.42, 0, 61.35),
			Vector3.new(-71.31, 0, 47.65),
		}
		expect.equal(#WorldLayout.SqueezeZone.mats, 6)
		expect.equal(WorldLayout.SqueezeZone.matDiameter, 7.6) -- lobby.js:341 (superF 3.8)
		-- Zone floor top 0.6 + mat centre 0.7 + half height 0.75 (lobby.js:338, 343-344).
		expect.near(WorldLayout.SqueezeZone.matHeight, 2.05, 1e-9)
		for index, mat in WorldLayout.SqueezeZone.mats do
			expect.equal(mat.id, string.format("squeeze_%02d", index))
			if not flatNear(mat.position, expected[index], POSITION_TOLERANCE) then
				error(`{mat.id} is at {show(mat.position)}, the design says {show(expected[index])}`)
			end
			expect.near(mat.position.Y, 1.3, FLOAT_TOLERANCE) -- the mat centre: 0.6 + 0.7
			local station = WorldLayout.station(mat.id)
			expect.near(station.halfSize, 3.8, 1e-9)
			expect.equal(station.top, WorldLayout.SqueezeZone.matHeight)
			expect.equal(station.position, mat.position)
		end
	end)

	-- Giant pads (D5) ------------------------------------------------------------------------------------------------

	t.test(
		"giant pads match the design pads (D5): centre, footprint, rest top, collision top = rest top - sink",
		function()
			local count = 0
			for key, spec in GIANT_PADS do
				count += 1
				local pad = WorldLayout.giantPad(key)
				expect.truthy(pad ~= nil)
				expect.equal(pad.key, key)
				expect.equal(pad.stationId, spec.station)
				expect.equal(pad.tier, spec.tier)
				expect.equal(pad.model, "GiantPad_" .. key)
				if not vectorNear(pad.center, spec.center, POSITION_TOLERANCE) then
					error(`{key} is at {show(pad.center)}, the design says {show(spec.center)}`)
				end
				expect.near(pad.footprint, spec.footprint, 1e-9)
				expect.near(pad.cornerRadius, spec.corner, 1e-9)
				expect.near(pad.restTop, spec.restTop, 1e-9)
				expect.near(pad.sinkDepth, spec.sink, 1e-9)
				expect.near(pad.collisionTop, spec.restTop - spec.sink, 1e-9)
				expect.truthy(
					vectorNear(
						pad.collision.size,
						Vector3.new(spec.collision, pad.collisionTop, spec.collision),
						FLOAT_TOLERANCE
					)
				)
				expect.truthy(
					vectorNear(
						pad.collision.position,
						Vector3.new(spec.center.X, pad.collisionTop / 2, spec.center.Z),
						POSITION_TOLERANCE
					)
				)
				expect.equal(pad.gate.diameter, GATE_DIAMETER)
				expect.equal(pad.gate.height, GATE_HEIGHT)
				expect.equal(pad.gate.transparency, 1) -- invisible: the lock and rope show instead (D5)
				expect.truthy(
					vectorNear(pad.gate.position, Vector3.new(spec.center.X, GATE_HEIGHT / 2, spec.center.Z), 1e-3)
				)
				-- The server measures squeezes from the collision box centre (§17.6.1).
				expect.equal(WorldLayout.station(spec.station).position, pad.collision.position)
				expect.equal(WorldLayout.station(spec.station).top, pad.collisionTop)
			end
			expect.equal(count, #WorldLayout.GiantPadKeys)
			expect.deepEqual(WorldLayout.GiantPadKeys, { "jelly", "marshmallow", "royal" })
			expect.equal(WorldLayout.GiantPads.jelly.blueprintId, "giant_jelly")
			expect.equal(WorldLayout.GiantPads.royal.blueprintId, "giant_cushion")
		end
	)

	t.test("every giant pad fits its gate; its collision box fits the rounded footprint; pads stay 20 apart", function()
		for _, key in WorldLayout.GiantPadKeys do
			local pad = WorldLayout.GiantPads[key]
			local f, r = pad.footprint / 2, pad.cornerRadius
			local b = pad.collision.size.X / 2
			expect.truthy(f - b >= 0.6 - FLOAT_TOLERANCE) -- the collision box stays inside the visual edge
			local reach = (f - r) * math.sqrt(2) + r
			expect.truthy(pad.gate.diameter / 2 - reach >= GATE_CLEARANCE)
			if b > f - r then
				expect.truthy((b - (f - r)) * math.sqrt(2) <= r - CORNER_MARGIN + FLOAT_TOLERANCE)
			end
			expect.truthy(pad.collisionTop < pad.restTop)
		end
		local keys = WorldLayout.GiantPadKeys
		for i = 1, #keys do
			for j = i + 1, #keys do
				local a, b = WorldLayout.GiantPads[keys[i]], WorldLayout.GiantPads[keys[j]]
				expect.truthy(WorldLayout.horizontalDistance(a.center, b.center) >= 20)
			end
		end
	end)

	-- Keep-clear volumes (§7.7 props rules 1 and 5) ------------------------------------------------------------------

	t.test("station keep-clear volumes never overlap each other (yawed volumes included)", function()
		local volumes = {}
		for _, volume in WorldLayout.KeepClear do
			if volume.kind == "station" then
				table.insert(volumes, volume)
			end
		end
		expect.truthy(#volumes >= 17) -- 7 stands/zones + 9 squeeze stations + the spawn
		local overlaps = {}
		for i = 1, #volumes do
			for j = i + 1, #volumes do
				if volumesOverlap(volumes[i], volumes[j]) then
					table.insert(overlaps, volumes[i].name .. " / " .. volumes[j].name)
				end
			end
		end
		if #overlaps > 0 then
			error("overlapping keep-clear volumes: " .. table.concat(overlaps, ", "))
		end
	end)

	t.test("every squeeze station, stand approach and path has a keep-clear volume", function()
		local byName: { [string]: any } = {}
		for _, volume in WorldLayout.KeepClear do
			expect.falsy(byName[volume.name])
			byName[volume.name] = volume
			local top = volume.position.Y + volume.size.Y / 2
			expect.truthy(near(top, 24))
		end
		for _, station in WorldLayout.Stations do
			local volume = byName[station.id]
			expect.truthy(volume ~= nil)
			-- Pads and mats: the volume starts above the standing surface (the station body stays outside).
			expect.truthy(volume.position.Y - volume.size.Y / 2 > station.top)
			expect.truthy(WorldLayout.contains(volume, Vector3.new(station.position.X, 12, station.position.Z)))
		end
		for _, stand in
			{
				WorldLayout.QuestBoard,
				WorldLayout.DailyStand,
				WorldLayout.DuelGate,
				WorldLayout.GiftBoxCounter,
				WorldLayout.ShopCounter,
				WorldLayout.Collection,
				WorldLayout.PracticeRange,
			} :: { any }
		do
			local approach = stand.approach + Vector3.new(0, 3, 0)
			local inside = false
			for _, volume in WorldLayout.KeepClear do
				if volume.kind == "station" and WorldLayout.contains(volume, approach) then
					inside = true
				end
			end
			if not inside then
				error(`{stand.model}: approach {show(stand.approach)} is in no station keep-clear volume`)
			end
		end
		-- Each path is an aisle along its own direction (yawed).
		for _, path in WorldLayout.Paths do
			local aisle = byName["path_" .. path.id]
			expect.truthy(aisle ~= nil)
			expect.equal(aisle.kind, "aisle")
			local middle = (path.from + path.to) / 2 + Vector3.new(0, 3, 0)
			expect.truthy(WorldLayout.contains(aisle, middle))
			expect.near(aisle.size.Z, path.width + 1.8, 1e-6) -- the curb width (lobby.js:134)
		end
	end)

	t.test("every prompt has a 5-stud keep-clear radius (§7.7 props rule 1)", function()
		local points: { { name: string, point: Vector3 } } = {}
		for _, stand in
			{
				WorldLayout.QuestBoard,
				WorldLayout.DailyStand,
				WorldLayout.DuelGate,
				WorldLayout.GiftBoxCounter,
				WorldLayout.ShopCounter,
				WorldLayout.Collection,
			} :: { any }
		do
			table.insert(points, { name = stand.model, point = stand.prompt.position })
		end
		for _, pedestal in WorldLayout.Collection.pedestals do
			table.insert(points, { name = `pedestal {pedestal.slot}`, point = pedestal.prompt.position })
		end
		for _, entry in points do
			local covered = false
			for _, volume in WorldLayout.KeepClear do
				if volume.yaw ~= nil and volume.yaw ~= 0 then
					continue
				end
				local low, high = volume.position - volume.size / 2, volume.position + volume.size / 2
				local p = entry.point
				if
					low.X <= p.X - 5 + 1e-6
					and high.X >= p.X + 5 - 1e-6
					and low.Z <= p.Z - 5 + 1e-6
					and high.Z >= p.Z + 5 - 1e-6
					and low.Y <= 0.5 + 1e-6
					and high.Y >= 24 - 1e-6
				then
					covered = true
				end
			end
			if not covered then
				error(`{entry.name}: no keep-clear volume covers 5 studs around {show(entry.point)}`)
			end
		end
	end)

	t.test("no station body reaches into a station or aisle keep-clear volume", function()
		local hits = {}
		for _, body in stationBodies() do
			if body.position.Y + body.size.Y / 2 <= 0.5 then
				continue -- floor coverings
			end
			for _, volume in WorldLayout.KeepClear do
				if volume.kind == "prompt" then
					continue -- a prompt volume holds its own station; Verify exempts station bodies
				end
				if if body.radius then discOverlaps(body, volume) else volumesOverlap(body, volume) then
					table.insert(hits, body.name .. " in " .. volume.name)
				end
			end
		end
		if #hits > 0 then
			error("station bodies inside keep-clear volumes: " .. table.concat(hits, ", "))
		end
	end)

	-- Routes (D1: the design's worst real route) ----------------------------------------------------------------------

	t.test("route speed is the uniform WalkSpeed; limits are the design's worst routes (D1)", function()
		expect.equal(WorldLayout.Routes.walkSpeed, Config.Duel.Rules.Movement.WalkSpeed)
		expect.equal(WorldLayout.Routes.maxSeconds, 10) -- box <-> practice 156 studs = 9.75 s (phase 3 spec A2)
		expect.equal(WorldLayout.Routes.podMaxSeconds, 12)
	end)

	t.test(
		"routes between activities stay under 10 s, pod routes within 12 s; the worst is box <-> practice",
		function()
			local activities = WorldLayout.Activities
			expect.equal(#activities, 11)
			local worst, worstPod = 0, 0
			local worstPair = ""
			local tooLong = {}
			for i = 1, #activities do
				for j = i + 1, #activities do
					local a, b = activities[i], activities[j]
					local shortest = math.huge
					for _, p in a.points do
						for _, q in b.points do
							shortest = math.min(shortest, WorldLayout.routeSeconds(p, q))
						end
					end
					local pod = a.pod or b.pod
					if pod then
						worstPod = math.max(worstPod, shortest)
					elseif shortest > worst then
						worst = shortest
						worstPair = a.name .. "/" .. b.name
					end
					local limit = if pod then WorldLayout.Routes.podMaxSeconds else WorldLayout.Routes.maxSeconds
					local ok = if pod then shortest <= limit else shortest < limit
					if not ok then
						table.insert(tooLong, string.format("%s -> %s %.2f s", a.name, b.name, shortest))
					end
				end
			end
			if #tooLong > 0 then
				error("routes over the limit: " .. table.concat(tooLong, ", "))
			end
			expect.near(worst, 156.0 / 16, 0.01)
			expect.truthy(worstPair == "practice/giftBox" or worstPair == "giftBox/practice")
			expect.truthy(worstPod <= 12)
		end
	)

	t.test("spawn routes are no longer than the design states", function()
		for _, activity in WorldLayout.Activities do
			local stated = SPAWN_ROUTES[activity.name]
			expect.truthy(stated ~= nil)
			local shortest = math.huge
			for _, point in activity.points do
				shortest = math.min(shortest, WorldLayout.horizontalDistance(SPAWN, point))
			end
			if shortest > stated + ROUTE_TOLERANCE then
				error(string.format("spawn -> %s is %.1f studs, the design says %.1f", activity.name, shortest, stated))
			end
		end
		-- The spawn: an invisible SpawnLocation in the medallion, top flush with it (Y 0.7, lobby.js:147).
		local location = WorldLayout.Spawn.location
		expect.truthy(flatNear(location.position, Vector3.zero, 1e-6))
		expect.near(location.position.Y + location.size.Y / 2, 0.7, FLOAT_TOLERANCE)
		expect.equal(WorldLayout.Spawn.top, 0.7)
		expect.truthy(vectorNear(location.facing, Vector3.new(0, 0, -1)))
	end)

	t.test(
		"every activity has a waypoint; approaches are the path ends; squeeze points at the mat nearest the spawn",
		function()
			for _, activity in WorldLayout.Activities do
				expect.truthy(WorldLayout.waypoint(activity.name) ~= nil)
			end
			local nearest, best = nil, math.huge
			for _, mat in WorldLayout.SqueezeZone.mats do
				local distance = WorldLayout.horizontalDistance(SPAWN, mat.position)
				if distance < best then
					nearest, best = mat.position, distance
				end
			end
			local waypoint = WorldLayout.waypoint("squeeze")
			expect.truthy(flatNear(waypoint, nearest :: Vector3, 1e-6))
			expect.equal(WorldLayout.waypoint("nowhere"), nil)
			local approaches: { [string]: any } = {
				duel = WorldLayout.DuelGate,
				box = WorldLayout.GiftBoxCounter,
				shop = WorldLayout.ShopCounter,
				collection = WorldLayout.Collection,
				quests = WorldLayout.QuestBoard,
				daily = WorldLayout.DailyStand,
				practice = WorldLayout.PracticeRange,
			}
			for id, stand in approaches do
				if not flatNear(stand.approach, PATH_ENDS[id], POSITION_TOLERANCE) then
					error(`{id}: approach {show(stand.approach)}, the path ends at {show(PATH_ENDS[id])}`)
				end
			end
			expect.truthy(flatNear(WorldLayout.waypoint("spawn"), Vector3.zero, 1e-6))
		end
	)

	-- Signs, prompts and texts (D6, D10, D11) -------------------------------------------------------------------------

	t.test("every sign, prompt and nameplate key resolves in Strings", function()
		local missing = {}
		for _, key in WorldLayout.textKeys() do
			local text = Strings.resolve(key)
			if type(text) ~= "string" or text == "" then
				table.insert(missing, key)
			end
		end
		if #missing > 0 then
			error("missing Strings keys: " .. table.concat(missing, ", "))
		end
	end)

	t.test("every design plate word and every kept live line is placed in the world", function()
		local used: { [string]: boolean } = {}
		for _, key in WorldLayout.textKeys() do
			used[key] = true
		end
		local unplaced = {}
		for key in TEXTS do
			if not used[key] then
				table.insert(unplaced, key)
			end
		end
		table.sort(unplaced)
		if #unplaced > 0 then
			error("keys no sign, prompt or plate uses: " .. table.concat(unplaced, ", "))
		end
	end)

	t.test("world texts are the design's words (D10) and the game's live texts", function()
		local wrong = {}
		for key, text in TEXTS do
			if Strings.resolve(key) ~= text then
				table.insert(wrong, key)
			end
		end
		table.sort(wrong)
		if #wrong > 0 then
			error("texts differ: " .. table.concat(wrong, ", "))
		end
	end)

	t.test("signs: unique ids, static or live lines, never both, within the 64-SurfaceGui budget (D6)", function()
		local ids: { [string]: boolean } = {}
		for _, sign in WorldLayout.Signs do
			expect.falsy(ids[sign.id])
			ids[sign.id] = true
			expect.truthy(#sign.lines >= 1)
			expect.truthy(near(sign.facing.Magnitude, 1, 1e-5))
			for _, line in sign.lines do
				expect.truthy(line.letterHeight > 0)
				if line.live then
					expect.equal(line.textKey, nil)
				else
					expect.truthy((line.textKey == nil) ~= (line.bakeKey == nil))
				end
			end
		end
		expect.equal(WorldLayout.Budgets.lobbySurfaceGuis, 64)
		expect.truthy(#WorldLayout.Signs <= WorldLayout.Budgets.lobbySurfaceGuis)
		expect.truthy(#WorldLayout.Signs >= 40) -- the design's plates (about 45 with the game's live boards)
	end)

	t.test("the design plates sit where lobby.js puts them, facing their station fronts", function()
		local byId: { [string]: any } = {}
		for _, sign in WorldLayout.Signs do
			byId[sign.id] = sign
		end
		local expected: { [string]: { point: Vector3, facing: Vector3 } } = {
			gateBadge = { point = design("duel", {}, 0, 24, -4.35), facing = frontOf("duel") }, -- lobby.js:184
			teamMint = { point = design("duel", {}, -6.5, 1.65, 17.1), facing = frontOf("duel") }, -- lobby.js:196
			teamStrawberry = { point = design("duel", {}, 6.5, 1.65, 17.1), facing = frontOf("duel") },
			shopPlate = { point = design("shop", {}, 0, 3.1, 3.62), facing = frontOf("shop") }, -- lobby.js:250
			questsTitle = { point = design("quests", {}, 0, 17.4, -1.06), facing = frontOf("quests") }, -- lobby.js:295
			questsDaily = { point = design("quests", {}, -6, 13.6, -1.0), facing = frontOf("quests") }, -- lobby.js:298
			kittyBreadPlate = { point = design("squeeze", {}, 0, 1.6, 6.75), facing = frontOf("squeeze") }, -- lobby.js:340
			practiceBoard = {
				point = design("practice", { { -16, 0.6, 12, 0.5 } }, 0, 7.6, 0.45),
				facing = frontOf("practice", 0.5),
			}, -- lobby.js:415-418
			arrowDuelFront = {
				point = design("spawn", { { 19, 0, 19, -math.pi / 4 } }, 0, 5.4, 0)
					+ Vector3.new(-0.2181, 0, -0.9759) * 2.9
					+ Vector3.new(0.9759, 0, -0.2181) * 0.33,
				facing = Vector3.new(0.9759, 0, -0.2181),
			}, -- lobby.js:157-165: arm +X toward the duel gate, plate 2.9 along it, 0.33 out of the board
		}
		for id, want in expected do
			local sign = byId[id]
			if sign == nil then
				error(`no sign {id}`)
			end
			if not vectorNear(sign.position, want.point, POSITION_TOLERANCE) then
				error(`{id} is at {show(sign.position)}, lobby.js puts it at {show(want.point)}`)
			end
			if not vectorNear(sign.facing, want.facing, 1e-3) then
				error(`{id} faces {show(sign.facing)}, expected {show(want.facing)}`)
			end
		end
		-- The daily calendar's 7 day numbers and the squeeze zone's 6 mat numbers.
		local days, mats = 0, 0
		for _, sign in WorldLayout.Signs do
			if string.sub(sign.id, 1, 8) == "dailyDay" then
				days += 1
			elseif string.sub(sign.id, 1, 9) == "matNumber" then
				mats += 1
			end
		end
		expect.equal(days, 7)
		expect.equal(mats, 6)
	end)

	t.test("the daily sign's live Status line is built empty and written only by its owner", function()
		local status: any = nil
		for _, sign in WorldLayout.Signs do
			for _, line in sign.lines do
				if line.name == "Status" then
					expect.equal(status, nil) -- one Status label in the DailyStand
					expect.equal(sign.owner, WorldLayout.DailyStand.model)
					status = line
				end
			end
		end
		expect.truthy(status ~= nil)
		expect.truthy(status.live)
		expect.equal(status.textKey, nil)
		expect.equal(status.bakeKey, nil)
		expect.truthy(table.find(status.clientKeys, "daily.ready") ~= nil)
		expect.truthy(table.find(status.clientKeys, "daily.wait") ~= nil)
	end)

	t.test(
		"pod signs: SD_GripSign per tier, Title grip.pad.<key>, one Live line, within 12 studs of their pad",
		function()
			local tiers: { [number]: boolean } = {}
			local count = 0
			for _, sign in WorldLayout.Signs do
				if sign.tag ~= "SD_GripSign" then
					continue
				end
				count += 1
				expect.falsy(tiers[sign.tier])
				tiers[sign.tier] = true
				local pad = WorldLayout.giantPadForStation(string.format("squeeze_%02d", sign.tier + 5))
				expect.equal(sign.id, pad.signId)
				expect.truthy(WorldLayout.horizontalDistance(sign.position, pad.center) <= 12) -- WorldBinder.padNear
				local titles, lives = 0, 0
				for _, line in sign.lines do
					if line.name == "Title" then
						titles += 1
						expect.equal(line.textKey, "grip.pad." .. pad.key)
					elseif line.name == "Live" then
						lives += 1
						expect.equal(line.textKey, nil)
						expect.equal(line.bakeKey, "grip.padNeeds")
						expect.truthy(line.live)
					end
				end
				expect.equal(titles, 1)
				expect.equal(lives, 1)
			end
			expect.equal(count, 3)
		end
	)

	t.test("stand prompts sit on their stations with the §7.6 defaults", function()
		local stands = {
			{ WorldLayout.QuestBoard, "prompt.viewQuests", design("quests", {}, 0, 4.5, 0.2) },
			{ WorldLayout.DailyStand, "prompt.dailyReward", design("daily", {}, 0, 2.5, 8.2) },
			{ WorldLayout.GiftBoxCounter, "prompt.seeBoxes", design("box", {}, 0, 3, 10.3) },
			{ WorldLayout.ShopCounter, "prompt.openShop", design("shop", {}, 0, 3.4, 4.3) },
			{ WorldLayout.DuelGate, "prompt.joinQueue", design("duel", {}, 0, 2, 19.6) },
			{
				WorldLayout.Collection,
				"prompt.openCollection",
				design("collection", { { 12, 0.8, 7, -0.7 } }, 0, 3, 1.9),
			},
		} :: { { any } }
		for _, entry in stands do
			local stand, key, position = entry[1], entry[2], entry[3]
			expect.equal(stand.prompt.actionKey, key)
			expect.equal(stand.prompt.maxDistance, 10)
			expect.equal(stand.prompt.requiresLineOfSight, true)
			if not vectorNear(stand.prompt.position, position, POSITION_TOLERANCE) then
				error(`{stand.model}: prompt at {show(stand.prompt.position)}, expected {show(position)}`)
			end
		end
		expect.equal(WorldLayout.DuelGate.prompt.altActionKey, "prompt.leaveQueue")
		expect.equal(WorldLayout.GiftBoxCounter.prompt.altActionKey, "prompt.shopDirect")
		-- The stands themselves are the design's parts (lobby.js:173, 218, 243, 275, 291, 314).
		expect.truthy(vectorNear(WorldLayout.DuelGate.podium.position, design("duel", {}, 0, 0.4, 16.6), 1e-3))
		expect.truthy(vectorNear(WorldLayout.DuelGate.podium.size, Vector3.new(22, 0.8, 5), 1e-6))
		expect.truthy(vectorNear(WorldLayout.GiftBoxCounter.stand.position, design("box", {}, 0, 2.7, 6.6), 1e-3))
		expect.equal(WorldLayout.GiftBoxCounter.stand.diameter, 6.2)
		expect.equal(WorldLayout.GiftBoxCounter.boxId, "snack")
		expect.truthy(vectorNear(WorldLayout.ShopCounter.counter.position, design("shop", {}, 0, 3, 1), 1e-3))
		expect.truthy(vectorNear(WorldLayout.ShopCounter.counter.size, Vector3.new(22, 4.4, 5), 1e-6))
		expect.truthy(
			vectorNear(
				WorldLayout.Collection.kiosk.position,
				design("collection", { { 12, 0.8, 7, -0.7 } }, 0, 2.3, 0),
				1e-3
			)
		)
		expect.truthy(vectorNear(WorldLayout.QuestBoard.board.position, design("quests", {}, 0, 9, -1.6), 1e-3))
		expect.truthy(vectorNear(WorldLayout.QuestBoard.board.size, Vector3.new(19, 12, 1), 1e-6))
		expect.truthy(vectorNear(WorldLayout.DailyStand.pedestal.position, design("daily", {}, 0, 0.6, 0), 1e-3))
		expect.equal(WorldLayout.DailyStand.pedestal.diameter, 15.2)
	end)

	-- Practice range, collection, return points, audio zones -----------------------------------------------------

	t.test(
		"practice range: 9 targets on the design lanes, 12/20/28 studs past the design firing line, throws +X (D3)",
		function()
			local range = WorldLayout.PracticeRange
			local targets = range.targets
			expect.equal(#targets, 9)
			-- Lanes = the design's three throw spots / targets (lobby.js:404-406: local x -10/0/10 -> world Z 52/62/72);
			-- the firing line paint at local z 9 -> world X 79 (lobby.js:403); throwers face local -Z = world +X.
			expect.equal(range.firingLineX, 79)
			expect.truthy(vectorNear(range.throwDirection, Vector3.new(1, 0, 0)))
			local ids: { [string]: boolean } = {}
			local moving = 0
			for _, target in targets do
				expect.falsy(ids[target.id])
				ids[target.id] = true
				expect.truthy(table.find({ 52, 62, 72 }, target.position.Z) ~= nil)
				expect.truthy(table.find({ 12, 20, 28 }, target.distance) ~= nil)
				expect.equal(target.position.X, range.firingLineX + target.distance)
				expect.equal(target.nameKey, "practice.targetName")
				if target.moving then
					moving += 1
					expect.equal(target.distance, 20)
					expect.equal(target.position.Z, 62)
					expect.equal(target.railLength, 12)
					expect.equal(target.period, 9.42)
				else
					expect.equal(target.railLength, 0)
					expect.equal(target.period, 0)
				end
			end
			expect.equal(moving, 1)
			-- The throw box: X 71..79 behind the firing line, across the range floor (Z 43..81), Y 0..12 (D3 reading).
			local low, high =
				range.throwBox.position - range.throwBox.size / 2, range.throwBox.position + range.throwBox.size / 2
			expect.truthy(vectorNear(low, Vector3.new(71, 0, 43)))
			expect.truthy(vectorNear(high, Vector3.new(79, 12, 81)))
			expect.truthy(WorldLayout.contains(range.throwBox, range.approach + Vector3.new(0, 3, 0)))
			-- The range floor (lobby.js:402: rb(38, 0.6, 42) turned -90°: X 73..115, Z 43..81), top 0.6.
			local floorLow, floorHigh = WorldLayout.boxBounds(range.laneFloor)
			expect.truthy(vectorNear(floorLow, Vector3.new(73, 0, 43), 1e-3))
			expect.truthy(vectorNear(floorHigh, Vector3.new(115, 0.6, 81), 1e-3))
			expect.equal(range.laneFloorTopY, 0.6)
			-- The backstop: the design's pillow wall (lobby.js:412-413, front X 110.5) holds the Backstop part 0.5 behind
			-- the pillow fronts, between the frames (Z 44.4..79.6), Y 0.6..9.2.
			local backLow, backHigh = WorldLayout.boxBounds(range.backstop)
			expect.truthy(vectorNear(backLow, Vector3.new(111, 0.6, 44.4), 1e-3))
			expect.truthy(vectorNear(backHigh, Vector3.new(113.5, 9.2, 79.6), 1e-3))
			-- Every target root and the throw box lie inside the projectile bounds.
			for _, target in targets do
				for _, dz in { -target.railLength / 2, 0, target.railLength / 2 } do
					local root = target.position + Vector3.new(0, range.laneFloorTopY + 3, dz)
					expect.truthy(WorldLayout.contains(range.bounds, root))
				end
			end
			expect.truthy(WorldLayout.contains(range.bounds, range.throwBox.position))
		end
	)

	t.test(
		"collection: 14 pedestals in catalog order on the 7 design bays (lobby.js:269-281), facing the bays (D4)",
		function()
			local pedestals = WorldLayout.Collection.pedestals
			expect.equal(#pedestals, 14)
			expect.equal(#Catalog.list(), 14)
			for index, pedestal in pedestals do
				expect.equal(pedestal.slot, index)
				local i = index - 1
				local bay = i // 2
				local a = math.rad(-60 + 20 * bay) -- lobby.js:269
				local y = (if i % 2 == 1 then 9.6 else 4) + 0.3 -- lobby.js:279
				local group = { 15 * math.sin(a), 0.8, 3 - 15 * math.cos(a), -a }
				local want = design("collection", { group }, 0, y + 0.35, 0.3) -- lobby.js:280
				if not vectorNear(pedestal.position, want, POSITION_TOLERANCE) then
					error(`pedestal {index} is at {show(pedestal.position)}, lobby.js puts it at {show(want)}`)
				end
				expect.truthy(vectorNear(pedestal.facing, frontOf("collection", -a), 1e-4))
				expect.truthy(vectorNear(pedestal.size, Vector3.new(2.8, 0.7, 2.8), 1e-6)) -- C(1.3, 1.4, 0.7)
				expect.equal(pedestal.prompt.actionKey, "prompt.inspect")
				expect.equal(pedestal.prompt.maxDistance, 12)
				expect.equal(pedestal.prompt.requiresLineOfSight, false)
				expect.truthy(vectorNear(pedestal.prompt.position, pedestal.position + Vector3.new(0, 0.35, 0), 1e-5))
			end
			expect.equal(WorldLayout.Collection.buildStuds, 60)
			expect.truthy(WorldLayout.Collection.squishyScale > 0)
		end
	)

	t.test("return points: slots 1 and 2 at (±6, 0, -42) facing +Z, in front of the queue step (reading)", function()
		local points = WorldLayout.ReturnPoints
		expect.equal(#points, 2)
		local xs: { [number]: boolean } = {}
		for index, point in points do
			expect.equal(point.slot, index)
			expect.equal(math.abs(point.position.X), 6)
			expect.equal(point.position.Z, -42)
			expect.equal(point.position.Y, 0)
			expect.truthy(vectorNear(point.facing, Vector3.new(0, 0, 1)))
			xs[point.position.X] = true
		end
		expect.truthy(xs[-6] and xs[6])
	end)

	t.test(
		"audio zones: the hub, the squeeze circle, the range with its throw box; the highest priority wins",
		function()
			local byId: { [string]: any } = {}
			for _, zone in WorldLayout.AudioZones do
				byId[zone.zoneId] = zone
			end
			expect.truthy(vectorNear(byId.lobby.position, Vector3.new(0, 20, 0)))
			expect.truthy(vectorNear(byId.lobby.size, Vector3.new(232, 40, 184)))
			expect.truthy(vectorNear(byId.squeeze.position, Vector3.new(-58, 15, 52)))
			expect.truthy(vectorNear(byId.squeeze.size, Vector3.new(46, 30, 46)))
			expect.truthy(vectorNear(byId.practice.position, Vector3.new(93.5, 15, 62)))
			expect.truthy(vectorNear(byId.practice.size, Vector3.new(45, 30, 38)))
			expect.equal(byId.lobby.priority, 1)
			expect.equal(byId.squeeze.musicMul, 0.8)
			expect.equal(byId.practice.musicMul, 0.6)
			expect.equal(WorldLayout.audioZoneAt(Vector3.new(-47.58, 3, 42.65)).zoneId, "squeeze") -- mat 2
			expect.equal(WorldLayout.audioZoneAt(Vector3.new(99, 3, 62)).zoneId, "practice") -- the lanes
			expect.equal(WorldLayout.audioZoneAt(Vector3.new(0, 3, 0)).zoneId, "lobby")
			expect.equal(WorldLayout.audioZoneAt(Vector3.new(400, 3, 0)), nil)
			local arena = WorldLayout.Arena.audioZone
			expect.equal(arena.zoneId, "arena")
			expect.equal(arena.priority, 3)
			expect.truthy(vectorNear(arena.size, Vector3.new(120, 60, 152)))
		end
	)

	t.test("TagCounts agree with the data", function()
		local counts = WorldLayout.TagCounts
		expect.equal(counts.SD_SqueezeStation, #WorldLayout.Stations)
		expect.equal(counts.SD_PracticeTarget, #WorldLayout.PracticeRange.targets)
		expect.equal(counts.SD_CollectionPedestal, #WorldLayout.Collection.pedestals)
		expect.equal(counts.SD_CollectionPedestal, 14)
		expect.equal(counts.SD_ReturnPoint, #WorldLayout.ReturnPoints)
		expect.equal(counts.SD_GiantPad, #WorldLayout.GiantPadKeys)
		expect.equal(counts.SD_GripGate, #WorldLayout.GiantPadKeys)
		expect.equal(counts.SD_GripSign, #WorldLayout.GiantPadKeys)
		expect.equal(counts.SD_GripLock, #WorldLayout.GiantPadKeys) -- the design's lock + rope per pad (D5)
		expect.equal(WorldLayout.Tags.GripLock, "SD_GripLock")
		expect.equal(#WorldLayout.Lobby.Boundaries, 4)
		expect.equal(counts.SD_Boundary, 4)
		expect.equal(counts.SD_AudioZone, 3)
		expect.equal(counts.SD_AudioZone, #WorldLayout.AudioZones)
		expect.equal(counts.SD_Ambient, #WorldLayout.Props.lollipops.positions + 3)
		expect.equal(counts.SD_Ambient, 7)
		expect.equal(WorldLayout.Tags.Ambient, "SD_Ambient")
		expect.equal(WorldLayout.Attributes.AmbientKind, "SD_AmbientKind")
	end)

	t.test("the corner lollipops: 4 at (±104, ±80), 24 tall, radius 7 (lobby.js:468)", function()
		local lollipops = WorldLayout.Props.lollipops
		expect.deepEqual(lollipops.positions, {
			Vector3.new(-104, 0, -80),
			Vector3.new(104, 0, -80),
			Vector3.new(-104, 0, 80),
			Vector3.new(104, 0, 80),
		})
		expect.equal(lollipops.height, 24)
		expect.equal(lollipops.radius, 7)
		expect.equal(#lollipops.colors, 4)
	end)

	t.test("the practice audio zone contains the whole throw box, so its sounds play there (§18.8)", function()
		local practice: any = nil
		for _, zone in WorldLayout.AudioZones do
			if zone.zoneId == "practice" then
				practice = zone
			end
		end
		expect.truthy(practice ~= nil)
		local box = WorldLayout.PracticeRange.throwBox
		local half = box.size / 2
		for _, dx in { -1, 1 } do
			for _, dy in { -1, 1 } do
				for _, dz in { -1, 1 } do
					local corner = box.position + Vector3.new(dx * half.X, dy * half.Y, dz * half.Z)
					expect.truthy(WorldLayout.contains(practice, corner))
					expect.equal(WorldLayout.audioZoneAt(corner + Vector3.new(-dx, -dy, -dz) * 0.01).zoneId, "practice")
				end
			end
		end
		expect.equal(practice.priority, 2)
		expect.equal(practice.musicKey, "music.lobby")
		expect.equal(practice.ambienceKey, "amb.lobby")
	end)

	-- First person (spec 2026-10-10 §3.5): in the throw box F, E and ButtonX are PracticeSqueeze's.
	t.test("the practice throw box is out of reach of every prompt and every squeeze station", function()
		local box = WorldLayout.PracticeRange.throwBox
		local low, high = box.position - box.size / 2, box.position + box.size / 2
		local function closest(point: Vector3): Vector3
			return point:Max(low):Min(high)
		end
		local prompts: { any } = {}
		local L = WorldLayout
		for _, stand in
			{ L.QuestBoard, L.DailyStand, L.DuelGate, L.GiftBoxCounter, L.ShopCounter, L.Collection } :: { any }
		do
			table.insert(prompts, stand.prompt)
		end
		for _, pedestal in L.Collection.pedestals do
			table.insert(prompts, pedestal.prompt)
		end
		expect.equal(#prompts, 20)
		for _, prompt in prompts do
			local gap = (prompt.position - closest(prompt.position)).Magnitude
			if gap <= prompt.maxDistance then
				error(`{prompt.actionKey} at {prompt.position} reaches the throw box ({gap} studs)`)
			end
		end
		local Squeeze = Config.Squeeze
		local reach = Squeeze.stationRadius + Squeeze.radiusTolerance
		for _, station in WorldLayout.Stations do
			local gap = WorldLayout.horizontalDistance(station.position, closest(station.position))
			if gap <= reach then
				error(`{station.id} reaches the throw box ({gap} studs)`)
			end
		end
	end)

	t.test("the arena wall stripe constants match ArenaBuilder's (§7.8, §18.3.4)", function()
		expect.deepEqual(
			WorldLayout.Arena.wallStripes,
			{ heights = { 2, 4, 6 }, thickness = 0.5, proud = 0.1, insetX = 0.06 }
		)
		local stripes = WorldLayout.Arena.wallStripes
		for _, height in stripes.heights do
			for _, edge in { height - stripes.thickness / 2, height + stripes.thickness / 2 } do
				local k = (edge - 0.25) / 0.5
				expect.near(k, math.floor(k + 0.5), 1e-9)
			end
		end
	end)

	-- Helpers -------------------------------------------------------------------------------------------------------

	t.test("nearestStation and stationUnder find the pad a player stands on", function()
		local mat6 = WorldLayout.station("squeeze_06")
		local standing = Vector3.new(mat6.position.X, mat6.top + 3, mat6.position.Z)
		local station, distance = WorldLayout.nearestStation(standing, 10)
		expect.equal(station.id, "squeeze_06")
		expect.truthy(distance < 4)
		local none, far = WorldLayout.nearestStation(Vector3.new(0, 3, 0), 10)
		expect.equal(none, nil)
		expect.equal(far, math.huge)

		local margin, above = Config.Grip.Afk.padMargin, Config.Grip.Afk.heightAbove
		expect.equal(WorldLayout.stationUnder(standing, margin, above).id, "squeeze_06")
		local off = standing + Vector3.new(3.8 + margin + 0.5, 0, 0)
		expect.equal(WorldLayout.stationUnder(off, margin, above), nil)
		local jelly = WorldLayout.GiantPads.jelly
		local onJelly = Vector3.new(jelly.center.X, jelly.collisionTop + 3, jelly.center.Z)
		expect.equal(WorldLayout.stationUnder(onJelly, margin, above).id, "squeeze_07")
		-- On the white base in front of the pad (Y 2.2): below the collision top, so not on the pad.
		expect.equal(WorldLayout.stationUnder(Vector3.new(jelly.center.X, 2.2 + 3, jelly.center.Z), margin, above), nil)
		expect.equal(WorldLayout.stationUnder(onJelly + Vector3.new(0, above + 0.5, 0), margin, above), nil)
		local royal = WorldLayout.GiantPads.royal
		expect.equal(
			WorldLayout.stationUnder(Vector3.new(royal.center.X, royal.collisionTop + 3, royal.center.Z), margin, above).id,
			"squeeze_09"
		)
		expect.equal(WorldLayout.stationUnder(Vector3.new(0, 3, 0), margin, above), nil)
	end)

	t.test(
		"boxCFrame turns yawed and facing boxes; contains honours a volume's yaw; boundsOverlap is strict",
		function()
			-- The quest cork faces the quests station front (lobby.js:124, 291).
			local board = WorldLayout.QuestBoard.board
			local cf = WorldLayout.boxCFrame(board)
			expect.truthy(vectorNear(cf.LookVector, frontOf("quests"), 1e-4))
			local low, high = WorldLayout.boxBounds(board)
			local front = frontOf("quests")
			local alongX = math.abs(front.Z) * 19 + math.abs(front.X) * 1
			expect.near(high.X - low.X, alongX, 1e-3)
			-- A yawed box (Box.yaw = rotation.y).
			local yawed = { position = Vector3.zero, size = Vector3.new(10, 2, 2), yaw = math.pi / 2 }
			local yLow, yHigh = WorldLayout.boxBounds(yawed)
			expect.near(yHigh.Z - yLow.Z, 10, 1e-4)
			expect.near(yHigh.X - yLow.X, 2, 1e-4)
			-- A yawed volume: its own axes decide.
			local volume = { position = Vector3.zero, size = Vector3.new(10, 2, 2), yaw = math.pi / 4 }
			expect.truthy(WorldLayout.contains(volume, Vector3.new(3, 0, -3)))
			expect.falsy(WorldLayout.contains(volume, Vector3.new(3, 0, 3)))
			local plain = { position = Vector3.zero, size = Vector3.new(2, 2, 2) }
			expect.truthy(WorldLayout.contains(plain, Vector3.new(1, 1, 1)))
			expect.falsy(WorldLayout.contains(plain, Vector3.new(1.01, 0, 0)))
			local one = Vector3.new(1, 1, 1)
			expect.falsy(WorldLayout.boundsOverlap(-one, one, Vector3.new(1, -1, -1), Vector3.new(3, 1, 1)))
			expect.truthy(WorldLayout.boundsOverlap(-one, one, Vector3.new(0.9, -1, -1), Vector3.new(3, 1, 1)))
		end
	)

	t.test("the layout is frozen", function()
		expect.throws(function()
			(WorldLayout :: any).Stations = {}
		end)
		expect.throws(function()
			(WorldLayout.GiantPads.jelly :: any).collisionTop = 0.6
		end)
		expect.throws(function()
			table.insert(WorldLayout.Stations, {})
		end)
		expect.near(WorldLayout.GiantPads.jelly.collisionTop, 5.7, 1e-9)
	end)

	-- Bases (lobby bases spec 2026-10-11 §2, §4; Phase 3 data) --------------------------------------------------------

	t.test("10 plots 36° apart around the hub centre: gates at r 96, backs at r 148, facing the hub", function()
		local bases = WorldLayout.Bases
		expect.truthy(vectorNear(bases.center, Vector3.zero)) -- the hub centre (the spawn medallion)
		expect.equal(bases.width, 44)
		expect.equal(bases.depth, 52)
		expect.equal(#bases.frames, 10)
		for index = 1, 10 do
			local frame = WorldLayout.plotFrame(index) :: CFrame
			local angle = math.rad((index - 1) * 36) -- compass angle, clockwise from north (-Z)
			local outward = Vector3.new(math.sin(angle), 0, -math.cos(angle))
			-- CFrames are float32: turned points match to 1e-3, like the other turned design points.
			expect.truthy(flatNear(frame * bases.gate, outward * 96, 1e-3))
			expect.truthy(flatNear(frame * Vector3.new(0, 0, -bases.depth / 2), outward * 148, 1e-3))
			expect.truthy(vectorNear(frame:VectorToWorldSpace(Vector3.new(0, 0, 1)), -outward, 1e-6)) -- local +Z: hub
			expect.near(frame.Position.Y, 0, 1e-9)
		end
		expect.truthy(flatNear((WorldLayout.plotFrame(1) :: CFrame).Position, Vector3.new(0, 0, -122), 1e-6)) -- north
		expect.truthy(flatNear((WorldLayout.plotFrame(6) :: CFrame).Position, Vector3.new(0, 0, 122), 1e-6)) -- south
		expect.equal(WorldLayout.plotFrame(0), nil)
		expect.equal(WorldLayout.plotFrame(11), nil)
	end)

	t.test(
		"a plot holds its 4 capsule pads (x ±13, z -8 / +8) and its spawn facing the gate; plots share no ground",
		function()
			local bases = WorldLayout.Bases
			expect.deepEqual(bases.capsulePads, {
				Vector3.new(-13, 0, -8),
				Vector3.new(13, 0, -8),
				Vector3.new(-13, 0, 8),
				Vector3.new(13, 0, 8),
			})
			expect.equal(bases.capsulePadSize, 8)
			expect.truthy(vectorNear(bases.spawn.Position, Vector3.new(0, 0, -16))) -- 42 studs behind the gate
			expect.truthy(vectorNear(bases.spawn.LookVector, Vector3.new(0, 0, 1), 1e-6)) -- toward the gate
			local half = bases.capsulePadSize / 2
			for index = 1, 10 do
				local frame = WorldLayout.plotFrame(index) :: CFrame
				for _, pad in bases.capsulePads do
					for _, corner in { Vector3.new(-half, 0, -half), Vector3.new(half, 0, half) } do
						expect.truthy(WorldLayout.inPlot(index, frame * (pad + corner)))
					end
				end
				expect.truthy(WorldLayout.inPlot(index, (frame * bases.spawn).Position))
				-- No corner of a plot lies on its neighbours' ground.
				for _, corner in { { -22, -26 }, { 22, -26 }, { -22, 26 }, { 22, 26 } } do
					local point = frame * Vector3.new(corner[1], 0, corner[2])
					for _, other in { index % 10 + 1, (index + 8) % 10 + 1 } do
						expect.falsy(WorldLayout.inPlot(other, point))
					end
				end
			end
		end
	)

	t.test("inPlot: the plot's footprint at any height; nothing for the hub or an unknown plot", function()
		local frame = WorldLayout.plotFrame(3) :: CFrame
		expect.truthy(WorldLayout.inPlot(3, frame * Vector3.new(0, 3, 0)))
		expect.truthy(WorldLayout.inPlot(3, frame * Vector3.new(0, 40, 0))) -- height is ignored
		-- Just inside a corner: float32 turns an exact edge point a hair either way.
		expect.truthy(WorldLayout.inPlot(3, frame * Vector3.new(21.99, 3, 25.99)))
		expect.falsy(WorldLayout.inPlot(3, frame * Vector3.new(0, 3, 26.5))) -- just out through the gate
		expect.falsy(WorldLayout.inPlot(3, frame * Vector3.new(22.5, 3, 0))) -- just past the side fence line
		for index = 1, 10 do
			expect.falsy(WorldLayout.inPlot(index, Vector3.new(0, 3, 0))) -- the hub centre is no plot
		end
		expect.falsy(WorldLayout.inPlot(11, frame * Vector3.new(0, 3, 0)))
		expect.falsy(WorldLayout.inPlot(0, Vector3.zero))
		expect.equal(WorldLayout.Tags.BaseSpawn, "SD_BaseSpawn")
		expect.equal(WorldLayout.Attributes.Plot, "Plot")
		expect.equal(WorldLayout.TagCounts.SD_BaseSpawn, nil) -- the island is built in Phase 4
	end)

	-- Arena (§5.3, §7.8) --------------------------------------------------------------------------------------------

	t.test("arena: pads 88 apart facing each other, zones per §5.3", function()
		local arena = WorldLayout.Arena
		local a, b = arena.pads.A, arena.pads.B
		expect.equal(a.name, "PadA")
		expect.equal(b.name, "PadB")
		expect.near((a.position - b.position).Magnitude, 88, 1e-6)
		expect.truthy(vectorNear(a.facing, Vector3.new(0, 0, 1)))
		expect.truthy(vectorNear(b.facing, Vector3.new(0, 0, -1)))
		local function span(zone: any): (Vector3, Vector3)
			return zone.position - zone.size / 2, zone.position + zone.size / 2
		end
		local expected: { [string]: { Vector3 } } = {
			HalfA = { Vector3.new(-36, -15, -52), Vector3.new(36, 40, -8) },
			Neutral = { Vector3.new(-36, -15, -8), Vector3.new(36, 40, 8) },
			HalfB = { Vector3.new(-36, -15, 8), Vector3.new(36, 40, 52) },
			Bounds = { Vector3.new(-38, -15, -54), Vector3.new(38, 40, 54) },
		}
		for name, range in expected do
			local low, high = span(arena.zones[name])
			if not (vectorNear(low, range[1]) and vectorNear(high, range[2])) then
				error(`Zones/{name} spans {show(low)}..{show(high)}`)
			end
		end
	end)

	t.test(
		"arena cover: 12 pieces, point-symmetric, >= 8 tall, <= 8 wide, out of the neutral zone and the lane",
		function()
			local arena = WorldLayout.Arena
			expect.equal(#arena.cover, 12)
			local parts = {}
			for _, piece in arena.cover do
				local low, high = nil :: Vector3?, nil :: Vector3?
				for _, part in piece.parts do
					local pLow, pHigh = part.position - part.size / 2, part.position + part.size / 2
					low = if low then low:Min(pLow) else pLow
					high = if high then high:Max(pHigh) else pHigh
					table.insert(parts, part)
				end
				local l, h = low :: Vector3, high :: Vector3
				expect.truthy(h.Y >= arena.minCoverHeight)
				expect.truthy(math.max(h.X - l.X, h.Z - l.Z) <= arena.maxCoverWidth)
				expect.truthy(l.Z >= arena.neutralHalfZ or h.Z <= -arena.neutralHalfZ)
				expect.truthy(l.X >= arena.openLaneHalfX or h.X <= -arena.openLaneHalfX)
				expect.truthy(math.abs(l.X) <= arena.halfX and math.abs(h.X) <= arena.halfX)
			end
			for _, part in parts do
				local mirrored = Vector3.new(-part.position.X, part.position.Y, -part.position.Z)
				local twin = false
				for _, other in parts do
					if
						other.shape == part.shape
						and vectorNear(other.size, part.size)
						and vectorNear(other.position, mirrored)
					then
						twin = true
					end
				end
				if not twin then
					error(`cover part at {show(part.position)} has no point-symmetric twin`)
				end
			end
		end
	)

	t.test("arena floor, barriers and apron follow §7.8", function()
		local arena = WorldLayout.Arena
		expect.equal(#arena.floorBands, 13)
		local minZ, maxZ = math.huge, -math.huge
		for _, band in arena.floorBands do
			expect.near(band.position.Y + band.size.Y / 2, 0, FLOAT_TOLERANCE)
			expect.truthy(vectorNear(band.size, Vector3.new(72, 4, 8)))
			minZ = math.min(minZ, band.position.Z - 4)
			maxZ = math.max(maxZ, band.position.Z + 4)
		end
		expect.equal(minZ, -52)
		expect.equal(maxZ, 52)
		expect.equal(#arena.dividers, 2)
		for _, divider in arena.dividers do
			expect.equal(math.abs(divider.position.Z), 8)
			expect.truthy(vectorNear(divider.size, Vector3.new(76, 40, 1)))
			expect.near(divider.position.X, 0, FLOAT_TOLERANCE)
		end
		local wallInner = math.huge
		for _, barrier in arena.barriers do
			if barrier.name == "WallWest" or barrier.name == "WallEast" then
				wallInner = math.min(wallInner, math.abs(barrier.position.X) - barrier.size.X / 2)
			end
		end
		expect.near(wallInner, 38, FLOAT_TOLERANCE)
		expect.equal(arena.barrierGroup, "SD_Barrier")
		local apronTop = arena.apron.position.Y + arena.apron.size.Y / 2
		expect.near(apronTop, -0.05, FLOAT_TOLERANCE)
		expect.truthy(vectorNear(arena.apron.size, Vector3.new(120, 4, 152)))
		expect.equal(arena.maxParts, 400)
	end)

	t.test("arena: collidable floor with its top at Y 0 reaches the barrier walls", function()
		local arena = WorldLayout.Arena
		local floors = {}
		for _, band in arena.floorBands do
			table.insert(floors, band)
		end
		for _, gutter in arena.gutters do
			expect.near(gutter.position.Y + gutter.size.Y / 2, 0, FLOAT_TOLERANCE)
			table.insert(floors, gutter)
		end
		local missing = {}
		for x = -37.5, 37.5, 2.5 do
			for z = -53.5, 53.5, 2.5 do
				local point = Vector3.new(x, -0.5, z)
				local covered = false
				for _, floor in floors do
					if WorldLayout.contains(floor, point) then
						covered = true
						break
					end
				end
				if not covered then
					table.insert(missing, show(point))
				end
			end
		end
		if #missing > 0 then
			error(`{#missing} floor points uncovered, first {missing[1]}`)
		end
		for i = 1, #floors do
			for j = i + 1, #floors do
				local a, b = floors[i], floors[j]
				expect.falsy(
					WorldLayout.boundsOverlap(
						a.position - a.size / 2,
						a.position + a.size / 2,
						b.position - b.size / 2,
						b.position + b.size / 2
					)
				)
			end
		end
	end)
end
