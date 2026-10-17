--!strict
-- WorldLayout_Test: unit tests for ReplicatedStorage.Shared.World.WorldLayout. Server only (ServerStorage.UnitTest).
-- Contract: the lobby is Squish Island (lobby bases spec 2026-10-11 §2-§4, §7-§8; build plan Phase 4) with the stations
-- of the Claude Design hub (design package sd/lobby.js, phase 3 spec decisions D1-D14) in its hub sectors. The island
-- numbers are restated from the spec (each with its §), the station-local numbers from lobby.js (each with its line)
-- or as the island's readings, and turned into world points with the design's own frame maths (lobby.js:112: a
-- station's local +Z faces the hub centre; three.js rotation.y = CFrame.Angles(0, yaw, 0)), so a drift in WorldLayout
-- is caught:
--   * the island (Squish Square Ø140 at Y 0, grass to r 160 at Y -0.9, the beach to r 176, the sea) and its
--     boundaries; 10 station frames in the hub sectors (§3: centred on 18° + 36° j, readings for the radii; the Grip
--     gym's 126° and the Royal pod's 306° went with the giant pads, build plan Phase 6); 10 paths,
--     8 wide, from the stage edge (r 22) to each plot's gate (r 96), 36° apart;
--   * six squeeze stations squeeze_01..06, tier 1: the six foam mats on the design ring of radius 14
--     (lobby.js:342-344) around the squeeze frame; the giant pads, their gates, pods, pod signs and lock decor are gone
--     (Phase 6);
--   * keep-clear volumes (yawed with their paths) never overlap between stations and hold no station body; the path
--     aisles are the paths themselves (8 wide);
--   * routes within the design's worst real route (D1: 10 s; was §7.5's 5 s), hub spawn routes no longer
--     than the island's distances; a plot's spawn 116 studs and its gate 74 from the stage (§2);
--   * every sign, prompt and plate key resolves in Strings; the design plate words (D10), the island's "SQUISH
--     SQUARE" (§2) and the game's live lines; the plates sit where the island puts them; within the 64-SurfaceGui
--     budget (D6); every plot's name sign hangs under its gate, reading "Open plot" as built (§4);
--   * the practice range: one lane east (Z 0), 4 targets, throws toward +X (§3, D3); 14 collection pedestals facing
--     their bays (D4); return points on the stage, audio zones over the island, the lollipops in the garden,
--     TagCounts (10 SD_Base, 10 SD_BaseSpawn since Phase 4);
--   * first person: no prompt and no squeeze station reaches into the practice throw box;
--   * bases (§2, §4, §8): 10 plots 36° apart around the hub centre, gates at radius 96 and backs at 148, facing the
--     hub, 44 × 52, the spawn inside (pens3 phase 3: no capsule pads, spots or statue), no two plots sharing ground, a
--     colour per plot and the open grey; inPlot is the footprint only, never an unknown plot;
--   * pens3 phase 1: Bases.pen is lobby design v6's base.pen (K:4084-4189) turned into the plot frame: front z 19, an
--     8-stud gate gap, 4-stud segments, the steps 3..12 exactly as K has them, every step inside the plot; the PEN
--     SPACE sign at (10, 0, 20.3) facing the gate side; the spawn at local z 22.5 between the gate and the pen,
--     facing the pen;
--   * the arena (§5.3, §7.8) is unchanged.
-- Pure data: runs in Edit mode on the Shared clone.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

type Bounds = { name: string, low: Vector3, high: Vector3 }

-- Constants (restated from the design so a drifting layout is caught)

local TIERS: { [string]: number } = {
	squeeze_01 = 1,
	squeeze_02 = 1,
	squeeze_03 = 1,
	squeeze_04 = 1,
	squeeze_05 = 1,
	squeeze_06 = 1,
}

-- A floor point `radius` studs out on compass angle `degrees` (lobby bases spec §2: clockwise from north, -Z).
local function polar(radius: number, degrees: number): Vector3
	local a = math.rad(degrees)
	return Vector3.new(radius * math.sin(a), 0, -radius * math.cos(a))
end

-- Station frames (spec §3: each station in the hub sector centred on its compass angle, 18° + 36° j; the radius is a
-- reading: the farthest out the sector lets it stand between its two paths). nil yaw = atan2(-x, -z), the front
-- facing the hub centre (lobby.js:112).
local FRAMES: { [string]: { r: number, deg: number, yaw: number? } } = {
	spawn = { r = 0, deg = 0, yaw = 0 }, -- the stage centre (§2)
	duel = { r = 0, deg = 0, yaw = 0 }, -- the duel stage under the tower (§2)
	shop = { r = 56, deg = 18 }, -- §3
	box = { r = 52, deg = 54 }, -- §3
	practice = { r = 70, deg = 90, yaw = -math.pi / 2 }, -- §3; the range runs east (+X) along its sector's middle
	quests = { r = 53, deg = 162 }, -- §3
	daily = { r = 50, deg = 198 }, -- §3
	collection = { r = 56, deg = 234 }, -- §3
	squeeze = { r = 78, deg = 270 }, -- §3 (reaches into the garden)
	fountain = { r = 48, deg = 342 }, -- §3: the Butter Fountain (a prop)
}

-- Where each stand is used (its approach): APPROACH_STEP in front of the stand's front edge (station-local z).
local APPROACH_FRONTS: { [string]: number } = {
	duel = 17.5, -- the podium's front (Ø5 at z 15)
	box = 10, -- the dais edge (Ø20)
	shop = 6, -- the stall floor's front
	collection = 3, -- the shelf floor's front
	quests = 5.5, -- the floor's front
	daily = 7.6, -- the dais edge (Ø15.2)
}
local APPROACH_STEP = 3 -- reading (not in spec)

local POSITION_TOLERANCE = 0.01 -- studs; the design numbers are restated with two decimals
local FLOAT_TOLERANCE = 1e-4 -- Vector3 components are single precision

-- Hub spawn routes (from the medallion centre to each stand's approach; squeeze to the mat
-- nearest the spawn), in studs: the island's distances when Phase 4 was built (a station moved farther out fails).
local SPAWN = Vector3.zero
local SPAWN_ROUTES: { [string]: number } = {
	quests = 44.5,
	daily = 39.4,
	squeeze = 64.0,
	collection = 50.0,
	shop = 47.0,
	duel = 20.5,
	practice = 48.0,
	giftBox = 39.0,
}
local ROUTE_TOLERANCE = 0.1

-- Exact texts: the design's plate words (D10, new keys) and the game's live lines and prompts it keeps.
local TEXTS: { [string]: string } = {
	["world.logoTop"] = "Squishy", -- lobby.js:153
	["world.logoBottom"] = "Duels", -- lobby.js:153
	["world.squishSquare"] = "SQUISH SQUARE", -- lobby bases spec §2 (the design's path arrows are gone: §2's paths
	-- lead to the plots)
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
	-- The game's live lines and prompts (D10, D11).
	["queue.boardTitle"] = "Duel Queue",
	["queue.boardWaiting"] = "Waiting: {count}",
	["queue.boardActive"] = "Duels in progress: {count} of {max}",
	["box.oddsTitle"] = "Box Odds",
	-- Pens3 phase 5: restricted accounts open the Coin boxes in a fixed order (was "aren't available").
	["box.restrictedNote"] = "Coin boxes open in a fixed order on your account, so you see the next squishy first, "
		.. "and day 7 of Daily Rewards gives a free Treat Box.",
	["box.unknownNote"] = "Couldn't check box availability. Try again.",
	["daily.ready"] = "Ready to claim!",
	["daily.wait"] = "Next reward in {time}",
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
	["base.openPlot"] = "Open plot", -- lobby bases spec §4: an open plot's name sign
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

-- The frame of a station (lobby.js:112: its local +Z faces the hub centre unless a yaw is given).
local function frameOf(id: string): CFrame
	local spec = FRAMES[id]
	local p = polar(spec.r, spec.deg)
	local yaw = if spec.yaw ~= nil then spec.yaw else math.atan2(-p.X, -p.Z)
	return CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, yaw, 0)
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
	return dx * dx + dz * dz < (body.radius - 0.01) ^ 2 -- touching never counts (Verify's OVERLAP_EPSILON)
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
			discBody("DuelGate.stage", L.DuelGate.stage),
			discBody("DuelGate.podium", L.DuelGate.podium),
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
		}
		return bodies
	end

	-- The island and its frames (lobby bases spec §2-§3) ------------------------------------------------------------

	t.test(
		"the island: Squish Square Ø140 at Y 0 with its curb, grass to r 160 at Y -0.9, the beach to r 176, the sea",
		function()
			local island, lobby = WorldLayout.Island, WorldLayout.Lobby
			expect.equal(island.hub.radius, 70) -- §2: Ø140
			expect.equal(island.hub.top, 0)
			expect.equal(island.hub.height, 0.9) -- §2: raised 0.9 above the garden
			expect.equal(island.curb.radius, 71) -- reading: a 1-stud white curb (§2, §8)
			expect.equal(island.grass.radius, 160) -- §2
			expect.equal(island.grass.top, -0.9)
			expect.equal(island.beach.radius, 176) -- §2: the beach r 160-176
			expect.truthy(island.beach.top < island.grass.top)
			expect.truthy(island.shallow.radius > island.beach.radius and island.shallow.top < island.beach.top)
			expect.equal(lobby.floorTopY, 0) -- the hub and the plots
			expect.equal(lobby.hubRadius, 70)
			expect.equal(lobby.stageRadius, 22) -- §2: the duel stage Ø44
			expect.equal(lobby.footprint, nil) -- the design hub's 232 × 184 rectangle is gone
			-- The sea: a slab under everything, wider than the shallow water, its top under the water's.
			local sea = lobby.baseSlab
			local seaTop = sea.position.Y + sea.size.Y / 2
			expect.truthy(seaTop < island.shallow.top)
			expect.truthy(sea.size.X / 2 >= island.shallow.radius and sea.size.Z / 2 >= island.shallow.radius)
			expect.truthy(sea.size.X / 2 < 225) -- the arena slots' aprons (X >= 225) never lie on it (ArenaService_Test)
			expect.equal(#lobby.Boundaries, 4)
			for _, wall in lobby.Boundaries do
				local low, high = wall.position - wall.size / 2, wall.position + wall.size / 2
				-- Out past the shallow water (and so past every plot, r 150 at its back corners), on the sea.
				local outside = low.X >= 192 or high.X <= -192 or low.Z >= 192 or high.Z <= -192
				expect.truthy(outside)
				expect.truthy(low.Y <= seaTop and high.Y >= 60)
			end
		end
	)

	t.test("station frames sit in the hub sectors (spec §3); stationFrame maps station-local points", function()
		for id, spec in FRAMES do
			local frame = WorldLayout.StationFrames[id]
			expect.truthy(frame ~= nil)
			local p = polar(spec.r, spec.deg)
			if not flatNear(frame.position, p, FLOAT_TOLERANCE) then
				error(`{id} is at {show(frame.position)}, expected {show(p)}`)
			end
			expect.near(frame.position.Y, 0, 1e-9)
			local yaw = if spec.yaw ~= nil then spec.yaw else math.atan2(-p.X, -p.Z)
			expect.near(frame.yaw, yaw, 1e-6) -- the frame's position is a float32 Vector3
			local cf = WorldLayout.stationFrame(id)
			expect.truthy(vectorNear(cf * Vector3.new(3, 1, 2), frameOf(id) * Vector3.new(3, 1, 2), FLOAT_TOLERANCE))
			if spec.r > 0 and id ~= "practice" then
				expect.near((spec.deg - 18) % 36, 0, 1e-9) -- the middle of a sector, between two paths
			end
		end
		local count = 0
		for _ in WorldLayout.StationFrames do
			count += 1
		end
		expect.equal(count, 10)
		expect.equal(WorldLayout.stationFrame("grip"), nil) -- the Grip gym went with the giant pads (Phase 6)
		expect.equal(WorldLayout.stationFrame("royal"), nil) -- and the Royal pod
		-- Spot checks: the box faces the hub centre; the practice range turned west, so throws go east (D3).
		expect.truthy(flatNear(frontOf("box"), -polar(1, 54), 1e-4))
		expect.truthy(flatNear(frontOf("practice"), Vector3.new(-1, 0, 0), 1e-6))
		expect.equal(WorldLayout.stationFrame("nowhere"), nil)
		expect.equal(WorldLayout.stationFrame("kit"), nil) -- the design hub's kit corner is gone (an island has none)
	end)

	t.test("10 paths, 8 wide, from the stage edge (r 22) to each plot's gate (r 96), 36° apart (spec §2)", function()
		expect.equal(#WorldLayout.Paths, 10)
		for index, path in WorldLayout.Paths do
			expect.equal(path.id, "plot" .. index)
			local out = polar(1, (index - 1) * 36)
			if not flatNear(path.from, out * 22, 1e-4) or not flatNear(path.to, out * 96, 1e-4) then
				error(`path {path.id} runs {show(path.from)} -> {show(path.to)}`)
			end
			expect.equal(path.width, 8)
			-- The path ends at its plot's gate.
			expect.truthy(flatNear(path.to, (WorldLayout.plotFrame(index) :: CFrame) * WorldLayout.Bases.gate, 1e-3))
		end
		expect.equal(WorldLayout.Promenade, nil) -- the design's promenade rings are gone: the stage is the centre
	end)

	-- Stations and tiers ------------------------------------------------------------------------------------------

	t.test("stations are squeeze_01..06, unique and in id order", function()
		local ids = WorldLayout.stationIds()
		expect.equal(#ids, 6)
		expect.equal(#WorldLayout.Stations, 6)
		local seen: { [string]: boolean } = {}
		for index, station in WorldLayout.Stations do
			expect.equal(station.id, string.format("squeeze_%02d", index))
			expect.equal(ids[index], station.id)
			expect.falsy(seen[station.id])
			seen[station.id] = true
			expect.equal(WorldLayout.station(station.id), station)
		end
		expect.equal(WorldLayout.station("squeeze_07"), nil) -- the giant pads' stations went in Phase 6
		expect.equal(WorldLayout.station("squeeze_10"), nil)
		expect.truthy(table.isfrozen(ids)) -- handed out shared: no caller may change it
	end)

	t.test(
		"station tiers match DESIGN §17.4: every station is a tier-1 Foam Mat (the giant pads went, Phase 6)",
		function()
			for id, tier in TIERS do
				expect.equal(WorldLayout.stationTier(id), tier)
			end
			expect.equal(WorldLayout.stationTier("squeeze_00"), nil)
			expect.equal(WorldLayout.stationTier("squeeze_09"), nil)
			expect.equal(WorldLayout.stationTier("practice"), nil)
			local pads = Config.Grip.Pads
			expect.equal(#pads, 1)
			expect.equal(pads[1].key, "foam")
			for _, name in { "GiantPads", "GiantPadKeys", "Pods", "giantPad", "giantPadForStation" } do
				expect.equal((WorldLayout :: any)[name], nil)
			end
		end
	)

	t.test("the six foam mats sit on the design ring at radius 14 (lobby.js:342-344), Ø7.6, top 2.05", function()
		-- The design ring around the squeeze frame (270°, r 78; its front faces east, toward the hub), mats 1-6.
		local expected = {
			Vector3.new(-71, 0, -12.12),
			Vector3.new(-64, 0, 0),
			Vector3.new(-71, 0, 12.12),
			Vector3.new(-85, 0, 12.12),
			Vector3.new(-92, 0, 0),
			Vector3.new(-85, 0, -12.12),
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

	-- Keep-clear volumes (§7.7 props rules 1 and 5) ------------------------------------------------------------------

	t.test("station keep-clear volumes never overlap each other (yawed volumes included)", function()
		local volumes = {}
		for _, volume in WorldLayout.KeepClear do
			if volume.kind == "station" then
				table.insert(volumes, volume)
			end
		end
		expect.truthy(#volumes >= 14) -- 7 stands/zones + 6 squeeze stations + the spawn
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
			expect.near(aisle.size.Z, path.width, 1e-6) -- spec §2: the path itself, 8 wide (no curb on the island)
			expect.near(aisle.size.X, (path.to - path.from).Magnitude, 1e-4) -- from the stage edge to the gate
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

	-- Movement overhaul (2026-10-17): the lobby runs at Config.LobbyMove.walkSpeed (20) and duels at 22; the routes stay
	-- timed at the old 16, never faster than the lobby run (so every limit below still holds, with room to spare).
	t.test("routes are timed no faster than the lobby run; limits are the design's worst routes (D1)", function()
		expect.truthy(WorldLayout.Routes.walkSpeed <= Config.LobbyMove.walkSpeed)
		expect.equal(WorldLayout.Routes.maxSeconds, 10) -- box <-> practice 156 studs = 9.75 s (phase 3 spec A2)
		expect.equal((WorldLayout.Routes :: any).podMaxSeconds, nil) -- the pod exception went with the pods (Phase 6)
	end)

	t.test("routes between activities stay under 10 s; the worst is practice <-> squeeze", function()
		local activities = WorldLayout.Activities
		expect.equal(#activities, 8)
		local worst = 0
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
				if shortest > worst then
					worst = shortest
					worstPair = a.name .. "/" .. b.name
				end
				if shortest >= WorldLayout.Routes.maxSeconds then
					table.insert(tooLong, string.format("%s -> %s %.2f s", a.name, b.name, shortest))
				end
			end
		end
		if #tooLong > 0 then
			error("routes over the limit: " .. table.concat(tooLong, ", "))
		end
		-- Squish Island: the worst is practice <-> squeeze, across the hub (112 studs, 7 s).
		expect.near(worst, 112.0 / 16, 0.01)
		expect.truthy(worstPair == "practice/squeeze" or worstPair == "squeeze/practice")
	end)

	t.test("hub spawn routes are no longer than the island's distances", function()
		for _, activity in WorldLayout.Activities do
			local stated = SPAWN_ROUTES[activity.name]
			expect.truthy(stated ~= nil)
			local shortest = math.huge
			for _, point in activity.points do
				shortest = math.min(shortest, WorldLayout.horizontalDistance(SPAWN, point))
			end
			if shortest > stated + ROUTE_TOLERANCE then
				error(string.format("spawn -> %s is %.1f studs, the island says %.1f", activity.name, shortest, stated))
			end
		end
		-- The hub spawn: an invisible SpawnLocation in the medallion on the stage (top 0.8 + 0.3), flush with it.
		local location = WorldLayout.Spawn.location
		expect.truthy(flatNear(location.position, Vector3.zero, 1e-6))
		expect.near(location.position.Y + location.size.Y / 2, 1.1, FLOAT_TOLERANCE)
		expect.equal(WorldLayout.Spawn.top, 1.1)
		expect.truthy(vectorNear(location.facing, Vector3.new(0, 0, -1)))
	end)

	t.test(
		"every activity has a waypoint; approaches stand 3 in front of each stand, off the paths; squeeze: nearest mat",
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
			}
			for id, stand in approaches do
				local want = design(id, {}, 0, 0, APPROACH_FRONTS[id] + APPROACH_STEP)
				if not flatNear(stand.approach, want, POSITION_TOLERANCE) then
					error(`{id}: approach {show(stand.approach)}, expected {show(want)}`)
				end
			end
			-- The practice approach is the throw spot, inside the throw box on the lane.
			expect.truthy(flatNear(WorldLayout.PracticeRange.approach, Vector3.new(48, 0, 0), 1e-6))
			-- Nobody waits on a path: no approach lies in a path aisle.
			approaches.practice = WorldLayout.PracticeRange
			for id, stand in approaches do
				for _, volume in WorldLayout.KeepClear do
					if
						volume.kind == "aisle" and WorldLayout.contains(volume, stand.approach + Vector3.new(0, 3, 0))
					then
						error(`{id}: approach {show(stand.approach)} lies on {volume.name}`)
					end
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

	t.test("the design plates sit where the island puts them, facing their station fronts", function()
		local byId: { [string]: any } = {}
		for _, sign in WorldLayout.Signs do
			byId[sign.id] = sign
		end
		local UP = Vector3.new(0, 1, 0)
		-- The practice board stands by the throw box's back corner (45, 0, 8.5), its plates toward the throw spot.
		local board, spot = Vector3.new(45, 0, 8.5), Vector3.new(48, 0, 0)
		local towardSpot = (spot - board).Unit
		local expected: { [string]: { point: Vector3, facing: Vector3 } } = {
			-- lobby.js:184 "DUELS"; reading: on the tower deck's south face (§2: the deck at 36).
			gateBadge = { point = design("duel", {}, 0, 36.75, 15.56), facing = frontOf("duel") },
			-- lobby.js:196 the team plates; reading: lying on the stage beside each team's queue pads.
			teamMint = { point = Vector3.new(-16.5, 0.85, 0), facing = UP },
			teamStrawberry = { point = Vector3.new(16.5, 0.85, 0), facing = UP },
			shopPlate = { point = design("shop", {}, 0, 3.1, 3.62), facing = frontOf("shop") }, -- lobby.js:250
			questsTitle = { point = design("quests", {}, 0, 17.4, -1.06), facing = frontOf("quests") }, -- lobby.js:295
			questsDaily = { point = design("quests", {}, -6, 13.6, -1.0), facing = frontOf("quests") }, -- lobby.js:298
			kittyBreadPlate = { point = design("squeeze", {}, 0, 1.6, 6.75), facing = frontOf("squeeze") }, -- lobby.js:340
			practiceBoard = { point = board + Vector3.new(0, 7.6, 0) + towardSpot * 0.45, facing = towardSpot }, -- lobby.js:418
			-- §2 "SQUISH SQUARE" on the ground; reading: on the north and south paths at r 31, read from the stage.
			squishSquareNorth = { point = Vector3.new(0, 0.08, -31), facing = UP },
			squishSquareSouth = { point = Vector3.new(0, 0.08, 31), facing = UP },
		}
		for id, want in expected do
			local sign = byId[id]
			if sign == nil then
				error(`no sign {id}`)
			end
			if not vectorNear(sign.position, want.point, POSITION_TOLERANCE) then
				error(`{id} is at {show(sign.position)}, the island puts it at {show(want.point)}`)
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

	t.test("the pod signs went with the giant pads (Phase 6): no sign carries an extra tag or a GripTier", function()
		for _, sign in WorldLayout.Signs do
			expect.equal(sign.tag, nil)
			expect.equal(sign.tier, nil)
			expect.falsy(string.sub(sign.id, 1, 4) == "pod_")
		end
	end)

	t.test("stand prompts sit on their stations with the §7.6 defaults", function()
		local stands = {
			{ WorldLayout.QuestBoard, "prompt.viewQuests", design("quests", {}, 0, 4.5, 0.2) },
			{ WorldLayout.DailyStand, "prompt.dailyReward", design("daily", {}, 0, 2.5, 8.2) },
			{ WorldLayout.GiftBoxCounter, "prompt.seeBoxes", design("box", {}, 0, 3, 9.3) }, -- 0.6 before the pedestal
			{ WorldLayout.ShopCounter, "prompt.openShop", design("shop", {}, 0, 3.4, 4.3) },
			{ WorldLayout.DuelGate, "prompt.joinQueue", design("duel", {}, 0, 2.6, 18) }, -- 0.5 before the podium
			{
				WorldLayout.Collection,
				"prompt.openCollection",
				design("collection", { { 9, 0, 6, -0.6 } }, 0, 3, 1.9), -- reading: the kiosk on the square
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
		-- The stands: the design's parts (lobby.js:173, 218, 243, 275, 291, 314), compact where the island needs it.
		-- Reading: the queue podium is a round step (Ø5) on the stage's south side.
		expect.truthy(vectorNear(WorldLayout.DuelGate.podium.position, design("duel", {}, 0, 1.2, 15), 1e-3))
		expect.equal(WorldLayout.DuelGate.podium.diameter, 5)
		expect.truthy(vectorNear(WorldLayout.GiftBoxCounter.stand.position, design("box", {}, 0, 2.7, 5.6), 1e-3))
		expect.equal(WorldLayout.GiftBoxCounter.stand.diameter, 6.2)
		expect.equal(WorldLayout.GiftBoxCounter.boxId, "snack")
		-- Reading: the shop counter 14 wide and 4 deep in its 22-wide stall.
		expect.truthy(vectorNear(WorldLayout.ShopCounter.counter.position, design("shop", {}, 0, 3, 1.5), 1e-3))
		expect.truthy(vectorNear(WorldLayout.ShopCounter.counter.size, Vector3.new(14, 4.4, 4), 1e-6))
		expect.truthy(
			vectorNear(
				WorldLayout.Collection.kiosk.position,
				design("collection", { { 9, 0, 6, -0.6 } }, 0, 2.3, 0),
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
		"practice range: one lane east (Z 0), 4 targets 12/20/28/34 past the firing line at X 52, throws +X (§3, D3)",
		function()
			local range = WorldLayout.PracticeRange
			local targets = range.targets
			expect.equal(#targets, 4) -- spec §3: 3 dummies, plus the moving target the game keeps (§5.11)
			expect.equal(range.firingLineX, 52) -- reading: the lane's west end, so the targets fit before the backstop
			expect.truthy(vectorNear(range.throwDirection, Vector3.new(1, 0, 0)))
			local ids: { [string]: boolean } = {}
			local moving = 0
			for index, target in targets do
				expect.equal(target.id, string.format("target_%02d", index))
				expect.falsy(ids[target.id])
				ids[target.id] = true
				expect.equal(target.position.Z, 0)
				expect.equal(target.distance, ({ 12, 20, 28, 34 })[index])
				expect.equal(target.position.X, range.firingLineX + target.distance)
				expect.equal(target.nameKey, "practice.targetName")
				if target.moving then
					moving += 1
					expect.equal(target.distance, 20)
					expect.equal(target.railLength, 12)
					expect.equal(target.period, 9.42)
				else
					expect.equal(target.railLength, 0)
					expect.equal(target.period, 0)
				end
			end
			expect.equal(moving, 1)
			-- The throw box: X 44..52 behind the firing line, across the lane (Z -10..10), Y 0..12 (D3 reading).
			local low, high =
				range.throwBox.position - range.throwBox.size / 2, range.throwBox.position + range.throwBox.size / 2
			expect.truthy(vectorNear(low, Vector3.new(44, 0, -10)))
			expect.truthy(vectorNear(high, Vector3.new(52, 12, 10)))
			expect.truthy(WorldLayout.contains(range.throwBox, range.approach + Vector3.new(0, 3, 0)))
			-- The lane floor X 46..91, Z -10..10, from the garden (Y -0.9) to its top 0.6; §3's "44-st lane".
			local floorLow, floorHigh = WorldLayout.boxBounds(range.laneFloor)
			expect.truthy(vectorNear(floorLow, Vector3.new(46, -0.9, -10), 1e-3))
			expect.truthy(vectorNear(floorHigh, Vector3.new(91, 0.6, 10), 1e-3))
			expect.truthy(floorHigh.X - floorLow.X >= 44)
			expect.equal(range.laneFloorTopY, 0.6)
			-- The backstop at the lane's east end, the design's size (the jelly ripple's grid is tuned to it): X 89..91.5,
			-- Y 0.6..9.2, Z -17.6..17.6, past the farthest target; its pillow wall stays clear of plots 3 and 4.
			local backLow, backHigh = WorldLayout.boxBounds(range.backstop)
			expect.truthy(vectorNear(backLow, Vector3.new(89, 0.6, -17.6), 1e-3))
			expect.truthy(vectorNear(backHigh, Vector3.new(91.5, 9.2, 17.6), 1e-3))
			expect.truthy(backLow.X > range.firingLineX + 34)
			for _, plot in { 3, 4 } do -- the wall's ends (Z ±21) stay 1.5 studs or more off those plots
				for _, z in { -21, 21 } do
					local corner = Vector3.new(backHigh.X + 0.1, 0, z)
					local frame = WorldLayout.plotFrame(plot) :: CFrame
					local p = frame:PointToObjectSpace(corner)
					local outside =
						math.max(math.abs(p.X) - WorldLayout.Bases.width / 2, p.Z - WorldLayout.Bases.depth / 2)
					expect.truthy(outside >= 1.5)
				end
			end
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
		"collection: 14 pedestals in catalog order on the 7 bays of the design arc (lobby.js:269-281), facing them (D4)",
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
				local group = { 12 * math.sin(a), 0.8, 2 - 12 * math.cos(a), -a } -- reading: the design arc at r 12 around z 2
				local want = design("collection", { group }, 0, y + 0.35, 0.3) -- lobby.js:280
				if not vectorNear(pedestal.position, want, POSITION_TOLERANCE) then
					error(`pedestal {index} is at {show(pedestal.position)}, the island puts it at {show(want)}`)
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

	t.test(
		"return points: slots 1 and 2 at (∓6, 0.8, 19) on the stage's south side, facing south (reading)",
		function()
			local points = WorldLayout.ReturnPoints
			expect.equal(#points, 2)
			for index, point in points do
				expect.equal(point.slot, index)
				expect.equal(point.position.X, if index == 1 then -6 else 6) -- Slot 1 west
				expect.equal(point.position.Z, 19)
				expect.near(point.position.Y, 0.8, FLOAT_TOLERANCE) -- the stage top
				expect.truthy(vectorNear(point.facing, Vector3.new(0, 0, 1)))
				-- On the stage, beside the podium, off the south path's aisle (it starts at the stage edge).
				expect.truthy(
					Vector3.new(point.position.X, 0, point.position.Z).Magnitude < WorldLayout.Lobby.stageRadius
				)
			end
		end
	)

	t.test(
		"audio zones: the island, the squeeze floor, the range with its throw box; the highest priority wins",
		function()
			local byId: { [string]: any } = {}
			for _, zone in WorldLayout.AudioZones do
				byId[zone.zoneId] = zone
			end
			-- The lobby zone covers the whole island with its plots (r 150 at their back corners), from the garden up.
			expect.truthy(vectorNear(byId.lobby.position, Vector3.new(0, 18, 0)))
			expect.truthy(vectorNear(byId.lobby.size, Vector3.new(360, 40, 360)))
			-- The squeeze zone is the Ø40 squeeze floor's square; the practice zone the lane with its throw box.
			expect.truthy(vectorNear(byId.squeeze.position, Vector3.new(-78, 15, 0), 1e-4))
			expect.truthy(vectorNear(byId.squeeze.size, Vector3.new(40, 30, 40)))
			expect.truthy(vectorNear(byId.practice.position, Vector3.new(68.5, 15, 0)))
			expect.truthy(vectorNear(byId.practice.size, Vector3.new(49, 30, 40)))
			expect.equal(byId.lobby.priority, 1)
			expect.equal(byId.squeeze.musicMul, 0.8)
			expect.equal(byId.practice.musicMul, 0.6)
			expect.equal(WorldLayout.audioZoneAt(Vector3.new(-64, 3, 0)).zoneId, "squeeze") -- mat 2
			expect.equal(WorldLayout.audioZoneAt(Vector3.new(75, 3, 0)).zoneId, "practice") -- the lane
			expect.equal(WorldLayout.audioZoneAt(Vector3.new(0, 3, 0)).zoneId, "lobby")
			for index = 1, 10 do -- every plot hears the lobby
				local back = (WorldLayout.plotFrame(index) :: CFrame) * Vector3.new(21, 2, -25)
				expect.equal(WorldLayout.audioZoneAt(back).zoneId, "lobby")
			end
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
		expect.equal(counts.SD_SqueezeStation, 6)
		-- The giant pads' tags went with them (Phase 6).
		for _, tag in { "SD_GiantPad", "SD_GripGate", "SD_GripSign", "SD_GripLock" } do
			expect.equal(counts[tag], nil)
		end
		for _, name in { "GiantPad", "GripGate", "GripSign", "GripLock" } do
			expect.equal((WorldLayout.Tags :: any)[name], nil)
		end
		expect.equal((WorldLayout.Attributes :: any).PadKey, nil)
		expect.equal(#WorldLayout.Lobby.Boundaries, 4)
		expect.equal(counts.SD_Boundary, 4)
		expect.equal(counts.SD_AudioZone, 3)
		expect.equal(counts.SD_AudioZone, #WorldLayout.AudioZones)
		expect.equal(counts.SD_Ambient, #WorldLayout.Props.lollipops.positions + 3)
		expect.equal(counts.SD_Ambient, 7)
		expect.equal(counts.SD_PracticeTarget, 4)
		expect.equal(counts.SD_Base, 10) -- Phase 4: one Model per plot (spec §4)
		expect.equal(counts.SD_BaseSpawn, 10) -- and its SpawnLocation
		expect.equal(WorldLayout.Tags.Base, "SD_Base")
		expect.equal(WorldLayout.Tags.Ambient, "SD_Ambient")
		expect.equal(WorldLayout.Attributes.AmbientKind, "SD_AmbientKind")
	end)

	t.test(
		"the lollipops: 4 in the garden at r 86 (54°, 126°, 234°, 342°), 24 tall, radius 7 (lobby.js:468)",
		function()
			local lollipops = WorldLayout.Props.lollipops
			expect.equal(#lollipops.positions, 4)
			for index, degrees in { 54, 126, 234, 342 } do
				local want = polar(86, degrees) + Vector3.new(0, WorldLayout.Island.grass.top, 0) -- on the grass
				if not vectorNear(lollipops.positions[index], want, 1e-4) then
					error(`lollipop {index} is at {show(lollipops.positions[index])}, expected {show(want)}`)
				end
				-- In the middle of a sector: its disk (radius 7) stays clear of every path (4 either side of its line).
				local p = Vector3.new(want.X, 0, want.Z)
				for _, path in WorldLayout.Paths do
					local dir = (path.to - path.from).Unit
					local along = p:Dot(dir)
					if along > 0 then
						expect.truthy((p - dir * along).Magnitude - lollipops.radius > path.width / 2)
					end
				end
			end
			expect.equal(lollipops.height, 24)
			expect.equal(lollipops.radius, 7)
			expect.equal(#lollipops.colors, 4)
		end
	)

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

		local margin, above = Config.Squeeze.padMargin, Config.Squeeze.heightAbove -- Phase 6: was Config.Grip.Afk
		expect.equal(WorldLayout.stationUnder(standing, margin, above).id, "squeeze_06")
		local off = standing + Vector3.new(3.8 + margin + 0.5, 0, 0)
		expect.equal(WorldLayout.stationUnder(off, margin, above), nil)
		-- Too high above the mat top, or below it: not on it.
		expect.equal(WorldLayout.stationUnder(standing + Vector3.new(0, above, 0), margin, above), nil)
		expect.equal(WorldLayout.stationUnder(standing - Vector3.new(0, 3.5, 0), margin, above), nil)
		-- Where the Grip gym's Jelly Pad stood (126°, r 42.5; gone since Phase 6): no station.
		local a = math.rad(126)
		local gym = Vector3.new(42.5 * math.sin(a), 6, -42.5 * math.cos(a))
		expect.equal(WorldLayout.stationUnder(gym, margin, above), nil)
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
			(WorldLayout.Stations[1] :: any).top = 0.6
		end)
		expect.throws(function()
			table.insert(WorldLayout.Stations, {})
		end)
		expect.near(WorldLayout.Stations[1].top, WorldLayout.SqueezeZone.matHeight, 1e-9)
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

	t.test("a plot holds its spawn facing the pen (no capsule pads, spots or statue); plots share no ground", function()
		local bases = WorldLayout.Bases
		for _, gone in { "capsulePads", "capsulePadSize", "capsulePadTop", "capsuleSpots", "statue", "statueHeight" } do
			expect.equal((bases :: any)[gone], nil) -- pens3 phase 3
		end
		-- Pens3 phase 1: between the gate (z 26) and the pen's front (z 19), facing the pen.
		expect.truthy(vectorNear(bases.spawn.Position, Vector3.new(0, 0, 22.5)))
		expect.truthy(vectorNear(bases.spawn.LookVector, Vector3.new(0, 0, -1), 1e-6))
		for index = 1, 10 do
			local frame = WorldLayout.plotFrame(index) :: CFrame
			expect.truthy(WorldLayout.inPlot(index, (frame * bases.spawn).Position))
			-- No corner of a plot lies on its neighbours' ground.
			for _, corner in { { -22, -26 }, { 22, -26 }, { -22, 26 }, { 22, 26 } } do
				local point = frame * Vector3.new(corner[1], 0, corner[2])
				for _, other in { index % 10 + 1, (index + 8) % 10 + 1 } do
					expect.falsy(WorldLayout.inPlot(other, point))
				end
			end
		end
	end)

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
		expect.equal(WorldLayout.TagCounts.SD_BaseSpawn, 10) -- Phase 4 builds the island: one per plot
	end)

	t.test("a plot's spawn stands 77.5 studs from the stage edge and its gate 74 (spec §2), facing its pen", function()
		local bases = WorldLayout.Bases
		local stage = WorldLayout.Lobby.stageRadius
		for index = 1, 10 do
			local frame = WorldLayout.plotFrame(index) :: CFrame
			local spawn = frame * bases.spawn
			expect.near(Vector3.new(spawn.Position.X, 0, spawn.Position.Z).Magnitude - stage, 77.5, 1e-3)
			local gate = frame * bases.gate
			expect.near(Vector3.new(gate.X, 0, gate.Z).Magnitude - stage, 74, 1e-3)
			expect.truthy(vectorNear(spawn.LookVector, frame.LookVector, 1e-4)) -- away from the hub, to the pen
		end
	end)

	-- Pens3 phase 1: the pen (lobby design v6 kit.json base.pen, K:4084-4189), in the plot frame.
	t.test("pens3 phase 1: Bases.pen is v6's pen turned into the plot frame; every step fits the plot", function()
		local pen = WorldLayout.Bases.pen
		expect.equal(pen.frontZ, 19) -- K frontZ -19, turned 180°
		expect.equal(pen.gateWidth, 8)
		expect.equal(pen.segment, 4)
		expect.equal(pen.edgeMargin, 0.8)
		expect.deepEqual(pen.steps, {
			[3] = { w = 16, d = 12, tier = 1, fence = 12, backWall = "fence" },
			[4] = { w = 16, d = 16, tier = 1, fence = 14, backWall = "fence" },
			[5] = { w = 24, d = 16, tier = 1, fence = 18, backWall = "fence" },
			[6] = { w = 24, d = 20, tier = 2, fence = 20, backWall = "fence" },
			[7] = { w = 24, d = 24, tier = 2, fence = 22, backWall = "fence" },
			[8] = { w = 24, d = 28, tier = 2, fence = 24, backWall = "fence" },
			[9] = { w = 24, d = 32, tier = 2, fence = 20, backWall = "shelf" },
			[10] = { w = 24, d = 32, tier = 3, fence = 20, backWall = "shelf" },
			[11] = { w = 24, d = 32, tier = 3, fence = 20, backWall = "shelf" },
			[12] = { w = 24, d = 32, tier = 3, fence = 20, backWall = "shelf" },
		})
		local bases = WorldLayout.Bases
		for spots = 3, 12 do
			local step = pen.steps[spots]
			-- K's fence count: the perimeter in segments, less the gate gap; from 9 spots the back is the shelf.
			local back = if step.backWall == "shelf" then step.w else 0
			expect.equal((2 * step.w + 2 * step.d - pen.gateWidth - back) / pen.segment, step.fence)
			expect.truthy(step.w / 2 <= bases.width / 2 and pen.frontZ - step.d >= -bases.depth / 2)
		end
		expect.truthy(pen.frontZ < bases.spawn.Position.Z and bases.spawn.Position.Z < bases.depth / 2)
		local sign = pen.signs.pen
		expect.truthy(vectorNear(sign.Position, Vector3.new(10, 0, 20.3)))
		expect.truthy(vectorNear(sign.LookVector, Vector3.new(0, 0, 1), 1e-6)) -- its face toward the gate side
		for index = 1, 10 do
			expect.truthy(WorldLayout.inPlot(index, (WorldLayout.plotFrame(index) :: CFrame) * sign.Position))
		end
	end)

	t.test(
		"every plot's name sign hangs under its gate arch, reads toward the hub, built as base.openPlot (§4)",
		function()
			local bases = WorldLayout.Bases
			local byId: { [string]: any } = {}
			for _, sign in WorldLayout.Signs do
				byId[sign.id] = sign
			end
			for index = 1, 10 do
				local sign = byId["baseSign" .. index]
				expect.truthy(sign ~= nil)
				expect.equal(sign.owner, bases.models[index])
				expect.equal(sign.part, "nameSign")
				local frame = WorldLayout.plotFrame(index) :: CFrame
				expect.truthy(vectorNear(sign.position, frame * bases.nameSign.position, 1e-3))
				expect.truthy(vectorNear(sign.facing, -frame.LookVector, 1e-4))
				expect.equal(#sign.lines, 1)
				local line = sign.lines[1]
				expect.equal(line.name, "Owner") -- BaseService writes the owner's display name here
				expect.truthy(line.live)
				expect.equal(line.bakeKey, "base.openPlot")
			end
			-- Between the gate's pillars (16 apart) and at the gate line.
			expect.truthy(math.abs(bases.nameSign.position.X) + bases.nameSign.size.X / 2 <= bases.gateWidth / 2)
			expect.truthy(math.abs(bases.nameSign.position.Z - bases.gate.Z) <= 1)
			expect.equal(bases.gateWidth, 16) -- §4
			expect.equal(Strings.resolve("base.openPlot"), "Open plot")
		end
	)

	t.test("each plot has its own Palette colour and light shade (spec §8); an open plot is grey (§4)", function()
		local Palette = t.requireShared("Art/Palette")
		local bases = WorldLayout.Bases
		expect.equal(#bases.colors, 10)
		local seen: { [string]: boolean } = {}
		for index, colors in bases.colors do
			for _, which in { "full", "light" } do
				expect.equal(typeof(Palette[colors[which]]), "Color3")
			end
			local hex = (Palette[colors.full] :: Color3):ToHex()
			expect.falsy(seen[hex])
			seen[hex] = true
			expect.equal(bases.models[index], string.format("Base_%02d", index))
		end
		expect.equal(bases.colors[1].full, "BaseRed") -- §8: B1 red .. B10 pink
		expect.equal(bases.colors[10].full, "BasePink")
		expect.deepEqual(bases.openColors, { full = "BaseOpen", light = "BaseOpenLight" })
		expect.equal(typeof(Palette.BaseOpen), "Color3")
		expect.equal(typeof(Palette.BaseOpenLight), "Color3")
		expect.equal(WorldLayout.Attributes.BaseTint, "SD_BaseTint")
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
