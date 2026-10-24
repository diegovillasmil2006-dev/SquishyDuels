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
--   * pens3 phase 1 (wb, owner 2026-10-17: the pen is the whole base): Bases.pen.steps holds K's tier per spot count
--     (K:4084-4169: 3-5 Wafer, 6-9 Mint, 10-12 Royal); no pen fence any more (no front z, gate gap or segment); the
--     squishies' floor `walk` is the plot's floor inside its own fence and back wall (x ±21, z -24.4..25), the spawn
--     on it; the PEN SPACE sign at (10, 0, 20.3) facing the gate side; the spawn at local z 22.5, facing the pen;
--   * wb: the gate at the front-right corner (16.2, 0, 24), its posts inside the fence and clear of the Donut Arch,
--     the lamps at the walk floor's front corners (±19.25, 0, 18.5), the trees by the side fences (±18, 0, 0), all
--     facing the gate side, inside every plot; the +X tree gold, the -X one pink (K:4170-4189 "adds");
--   * wb: Bases.props (the spawn, the arch's pillars, the mailbox, the flower box, the bench and the planter, as
--     LobbyBuilder builds them) stand on the plot, none in the shelf (the bench and the planter moved out to x ±17),
--     and every one is inside a walk block (`blocks`: the front row, the shelf row, the 2 trees);
--   * pens3 phase 11: the SHELF SPOTS sign at (-10, 0, 20.4) facing the gate side (L:189, K:4240: right of the gate);
--     the shelf (L:194 base_shelf_01, at v6 local z 16 on every base) at (0, 0, -16) facing the gate side, its front (6
--     deep, LK:184, and its locks) the shelf row block's front; its 8 cubbies (LK:188 slot_1..8) in K's order
--     (K:4194-4203: 2, 3, 1, 4, 6, 7, 5, 8, two to a row) and the TOP spot over its top, all inside every plot;
--   * pens3 phase 12: the highway (lobby design v6: L = layout.json, LK = lobby-kit.js, K = kit.json) is placed from
--     one origin, outside the island's sea and clear of the arena slots, distance d = d studs down its LookVector;
--     its launch deck is v6's (L:20, :31-37, v6 z + 62: v6 measures d from its gate at z -62, L:1); pens3 phase 13
--     (owner 2026-10-18): no launch spots, the deck top is one open throw area (the 30 x 15 platform top, 12 high),
--     and the launch board has 3 last-throw rows and the server best; 7 biome looks in Config's order with v6's tints
--     (L:458-1597, K:3136),
--     every colour a Palette token, the sky biomes without ground, the arches from biome 2 at v6's scales;
--   * p13v4 (owner 2026-10-19: the TikTok throw): 3 flight rings and 2 BULLSEYE pads a biome, as SPEC 3.3's placement
--     rule gives them (re-derived here from Config), inside their biomes, in passing order, clear of the lane's top;
--   * access2 (owner 2026-10-18 "Both": walk to the highway's launch deck, and a quick button): the north wall is
--     two pieces round a gap at x 0 as wide as the bridge with its rails; the bridge (a PLACEHOLDER: v6 has none)
--     runs 8 wide from the sea inside the wall to the front of the deck's back step (LK:158-164), a gentle ramp;
--   * the arena (§5.3, §7.8) is unchanged.
-- Pure data: runs in Edit mode on the Shared clone.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

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

local POSITION_TOLERANCE = 0.01 -- studs; the design numbers are restated with two decimals
local FLOAT_TOLERANCE = 1e-4 -- Vector3 components are single precision

-- Hub spawn routes (from the spawn at the Monument's centre to each stand's approach; squeeze to the seat nearest the
-- spawn), in studs: Diego's Neon Sugar lobby's distances (2026-10-24; a station moved farther out fails).
local SPAWN = Vector3.zero
local SPAWN_ROUTES: { [string]: number } = {
	quests = 37.0,
	daily = 25.3,
	squeeze = 30.1,
	collection = 37.5,
	shop = 31.0,
	duel = 21.5,
	practice = 21.0,
	giftBox = 29.9,
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
		.. "and day 7 of Daily Rewards gives a free Royal Box.",
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

return function(t: Context)
	local WorldLayout = t.requireShared("World/WorldLayout")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local Catalog = t.requireShared("Catalog")
	local expect = t.expect

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
			expect.equal(#lobby.Boundaries, 5) -- access2: the north wall in two, round the bridge's gap
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

	t.test("the six squeeze stations are the seats around Diego's BunCat: 3.4 square, top 2.5 (Neon Sugar)", function()
		-- Diego's BunCat at 270° r 38 (his lobby_manifest): 6 seats 9.6 from the bun, 30° + 60° k around it.
		local expected = {
			Vector3.new(-38, 0, -9.6),
			Vector3.new(-46.3138, 0, -4.8),
			Vector3.new(-29.6862, 0, -4.8),
			Vector3.new(-46.3138, 0, 4.8),
			Vector3.new(-29.6862, 0, 4.8),
			Vector3.new(-38, 0, 9.6),
		}
		expect.equal(#WorldLayout.SqueezeZone.mats, 6)
		expect.near(WorldLayout.SqueezeZone.matHeight, 2.5, 1e-9) -- the seat tops: plaza 0.6 + 0.4 + 1.2 + 0.3
		for index, mat in WorldLayout.SqueezeZone.mats do
			expect.equal(mat.id, string.format("squeeze_%02d", index))
			if not flatNear(mat.position, expected[index], POSITION_TOLERANCE) then
				error(`{mat.id} is at {show(mat.position)}, Diego's seat is at {show(expected[index])}`)
			end
			expect.near(mat.position.Y, 1.75, FLOAT_TOLERANCE) -- 0.75 under the seat top, as the old mats' centre
			local station = WorldLayout.station(mat.id)
			expect.near(station.halfSize, 1.7, 1e-9)
			expect.equal(station.top, WorldLayout.SqueezeZone.matHeight)
			expect.equal(station.position, mat.position)
		end
	end)

	-- Keep-clear volumes (§7.7 props rules 1 and 5) ------------------------------------------------------------------

	-- Neon Sugar lobby (2026-10-23): the station keep-clear volumes and path aisles were the retired LobbyBuilder's
	-- prop rules for the old island; Diego's lobby is placed as built, so their overlap and coverage tests went.

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

	-- (Neon Sugar lobby: the station-body keep-clear test went with the retired LobbyBuilder's keep-clear rules.)

	-- Routes (D1: the design's worst real route) ----------------------------------------------------------------------

	-- Movement overhaul (2026-10-17): the lobby runs at Config.LobbyMove.walkSpeed (20) and duels at 22; the routes stay
	-- timed at the old 16, never faster than the lobby run (so every limit below still holds, with room to spare).
	t.test("routes are timed no faster than the lobby run; limits are the design's worst routes (D1)", function()
		expect.truthy(WorldLayout.Routes.walkSpeed <= Config.LobbyMove.walkSpeed)
		expect.equal(WorldLayout.Routes.maxSeconds, 10) -- box <-> practice 156 studs = 9.75 s (phase 3 spec A2)
		expect.equal((WorldLayout.Routes :: any).podMaxSeconds, nil) -- the pod exception went with the pods (Phase 6)
	end)

	t.test("routes between activities stay under 10 s; the worst is quests <-> collection", function()
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
		-- Neon Sugar lobby: the worst is the quest board <-> the index shelf, across Diego's plaza (68.87 studs, 4.3 s).
		expect.near(worst, 68.87 / 16, 0.01)
		expect.truthy(worstPair == "quests/collection" or worstPair == "collection/quests")
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
		"every activity has a waypoint; approaches are the stand markers; squeeze: the nearest seat",
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
			-- Neon Sugar lobby: a stand's approach is its stand marker's floor point, in front of Diego's piece; the duel
			-- gate's is 5.5 in front of the podium at the Monument (2026-10-24).
			local markers: { [string]: { any } } = {
				box = { WorldLayout.GiftBoxCounter, Vector3.new(21.1707, 0, 21.1708) },
				shop = { WorldLayout.ShopCounter, Vector3.new(0, 0, 31.03) },
				collection = { WorldLayout.Collection, Vector3.new(-26.5165, 0, 26.5165) },
				quests = { WorldLayout.QuestBoard, Vector3.new(0, 0, -37.04) },
				daily = { WorldLayout.DailyStand, Vector3.new(17.918, 0, -17.9181) },
				duel = { WorldLayout.DuelGate, Vector3.new(0, 0, 21.5) },
			}
			for id, entry in markers do
				if not flatNear(entry[1].approach, entry[2], 1e-6) then
					error(`{id}: approach {show(entry[1].approach)}, expected {show(entry[2])}`)
				end
			end
			-- The practice approach is the throw spot, inside the throw box before Diego's runway.
			expect.truthy(flatNear(WorldLayout.PracticeRange.approach, Vector3.new(21, 0, 0), 1e-6))
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

	-- (Neon Sugar lobby: the old island's plate placement test went with the retired LobbyBuilder; Diego's plates
	-- are his Label_* parts.)


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
		"practice range: Diego's runway east (Z 0), 4 still targets 6/11/16/21 past the firing line at X 25, throws +X",
		function()
			local range = WorldLayout.PracticeRange
			local targets = range.targets
			expect.equal(#targets, 4) -- Diego's 4 targets (owner 2026-10-23: they stand still)
			expect.equal(range.firingLineX, 25) -- the runway's west end
			expect.truthy(vectorNear(range.throwDirection, Vector3.new(1, 0, 0)))
			local ids: { [string]: boolean } = {}
			for index, target in targets do
				expect.equal(target.id, string.format("target_%02d", index))
				expect.falsy(ids[target.id])
				ids[target.id] = true
				expect.equal(target.position.Z, 0)
				expect.equal(target.distance, ({ 6, 11, 16, 21 })[index])
				expect.equal(target.position.X, range.firingLineX + target.distance) -- Diego's posts at X 31/36/41/46
				expect.equal(target.nameKey, "practice.targetName")
				expect.falsy(target.moving)
				expect.equal(target.railLength, 0)
				expect.equal(target.period, 0)
			end
			-- The throw box: X 17..25 before the runway, Z -6..6, Y 0..12; the approach (throw spot) inside it.
			local low, high =
				range.throwBox.position - range.throwBox.size / 2, range.throwBox.position + range.throwBox.size / 2
			expect.truthy(vectorNear(low, Vector3.new(17, 0, -6)))
			expect.truthy(vectorNear(high, Vector3.new(25, 12, 6)))
			expect.truthy(WorldLayout.contains(range.throwBox, range.approach + Vector3.new(0, 3, 0)))
			expect.equal(range.laneFloorTopY, 0.9) -- Diego's runway top
			-- The backstop is Diego's cushion wall at the runway's east end: X 49..51, Y 0.9..5.7, Z -4.8..4.8.
			local backLow, backHigh = WorldLayout.boxBounds(range.backstop)
			expect.truthy(vectorNear(backLow, Vector3.new(49, 0.9, -4.8), 1e-3))
			expect.truthy(vectorNear(backHigh, Vector3.new(51, 5.7, 4.8), 1e-3))
			expect.truthy(backLow.X > range.firingLineX + 21) -- past the farthest target
			-- Every target root and the throw box lie inside the projectile bounds.
			for _, target in targets do
				local root = target.position + Vector3.new(0, range.laneFloorTopY + 3, 0)
				expect.truthy(WorldLayout.contains(range.bounds, root))
			end
			expect.truthy(WorldLayout.contains(range.bounds, range.throwBox.position))
		end
	)

	t.test(
		"collection: 14 pedestals in catalog order on the first 14 slots of Diego's IndexShelf, facing their unit's front",
		function()
			local pedestals = WorldLayout.Collection.pedestals
			expect.equal(#pedestals, 14)
			expect.equal(#Catalog.list(), 14)
			-- Diego's IndexShelf (315°, r 41): 3 units, slot tiles 1.8 x 0.25 x 1.6 with tops at 7.65 (top row) and
			-- 4.65; read from the hub, top row first, left to right (owner 2026-10-23: "Small squishies on slots").
			local middle = Vector3.new(0.7071, 0, -0.7071) -- the middle unit's front, toward the hub
			for index, pedestal in pedestals do
				expect.equal(pedestal.slot, index)
				expect.near(pedestal.position.Y + pedestal.size.Y / 2, if index <= 9 then 7.65 else 4.65, 1e-4)
				expect.truthy(vectorNear(pedestal.size, Vector3.new(1.8, 0.25, 1.8), 1e-6))
				expect.near(pedestal.facing.Magnitude, 1, 1e-6)
				expect.near(pedestal.facing.Y, 0, 1e-9)
				expect.truthy(pedestal.facing:Dot(middle) > 0.9) -- every unit faces the hub, the side ones turned in
				local toShelf = Vector3.new(pedestal.position.X, 0, pedestal.position.Z)
				expect.truthy(math.abs(toShelf.Magnitude - 41) < 9) -- on the shelf, around 41 from the hub
				expect.equal(pedestal.prompt.actionKey, "prompt.inspect")
				expect.equal(pedestal.prompt.maxDistance, 12)
				expect.equal(pedestal.prompt.requiresLineOfSight, false)
			end
			-- Left to right along the top row, as the hub sees it.
			local right = Vector3.new(-0.7071, 0, -0.7071)
			for index = 2, 9 do
				expect.truthy(pedestals[index].position:Dot(right) > pedestals[index - 1].position:Dot(right))
			end
			expect.equal(WorldLayout.Collection.buildStuds, 60)
			expect.truthy(WorldLayout.Collection.squishyScale > 0)
		end
	)

	t.test(
		"return points: slots 1 and 2 at (∓6, 0.6, 19) on the plaza beside the duel podium, facing south",
		function()
			local points = WorldLayout.ReturnPoints
			expect.equal(#points, 2)
			for index, point in points do
				expect.equal(point.slot, index)
				expect.equal(point.position.X, if index == 1 then -6 else 6) -- Slot 1 west
				expect.equal(point.position.Z, 19)
				expect.near(point.position.Y, 0.6, FLOAT_TOLERANCE) -- Diego's plaza top
				expect.truthy(vectorNear(point.facing, Vector3.new(0, 0, 1)))
				-- In front of the Monument (its base reaches Z 12.5), clear of the podium (X -2.7..2.7).
				expect.truthy(point.position.Z > 12.5 and math.abs(point.position.X) > 2.7 + 1)
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
			-- Neon Sugar lobby: the lobby zone covers Diego's island to its shallow water (r 206), from the garden up.
			expect.truthy(vectorNear(byId.lobby.position, Vector3.new(0, 18, 0)))
			expect.truthy(vectorNear(byId.lobby.size, Vector3.new(420, 40, 420)))
			-- The squeeze zone is around Diego's BunCat and its seats; the practice zone his runway with the throw box.
			expect.truthy(vectorNear(byId.squeeze.position, Vector3.new(-38, 15, 0), 1e-4))
			expect.truthy(vectorNear(byId.squeeze.size, Vector3.new(32, 30, 32)))
			expect.truthy(vectorNear(byId.practice.position, Vector3.new(36, 15, 0)))
			expect.truthy(vectorNear(byId.practice.size, Vector3.new(40, 30, 26)))
			expect.equal(byId.lobby.priority, 1)
			expect.equal(byId.squeeze.musicMul, 0.8)
			expect.equal(byId.practice.musicMul, 0.6)
			for _, mat in WorldLayout.SqueezeZone.mats do
				expect.equal(WorldLayout.audioZoneAt(mat.position + Vector3.new(0, 3, 0)).zoneId, "squeeze")
			end
			expect.equal(WorldLayout.audioZoneAt(Vector3.new(37, 3, 0)).zoneId, "practice") -- the runway
			expect.equal(WorldLayout.audioZoneAt(WorldLayout.PracticeRange.throwBox.position).zoneId, "practice")
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
		expect.equal(#WorldLayout.Lobby.Boundaries, 5)
		expect.equal(counts.SD_Boundary, 5)
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

	-- Pens3 phase 1 (wb, owner 2026-10-17): the pen is the whole base; K's steps only give the tier now.
	t.test("wb: the pen is the whole base: K's tiers by spot count, the plot's fenced floor, no pen fence", function()
		local pen = WorldLayout.Bases.pen
		expect.equal(pen.frontZ, nil) -- no pen fence: no front, gate gap or segment
		expect.equal(pen.gateWidth, nil)
		expect.equal(pen.segment, nil)
		expect.equal(pen.edgeMargin, 0.8)
		expect.deepEqual(pen.steps, { -- K:4084-4169 steps[cap].tier
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
		})
		-- The floor inside the plot's own fence (posts 0.8 wide, fenceInset in from the 44 × 52 plinth's sides and
		-- front) and its back wall (1.6 deep): LobbyBuilder's numbers.
		local bases = WorldLayout.Bases
		expect.deepEqual(pen.walk, { minX = -21, maxX = 21, minZ = -24.4, maxZ = 25 })
		expect.near(pen.walk.maxX, bases.width / 2 - bases.fenceInset - 0.4, 1e-9)
		expect.near(pen.walk.maxZ, bases.depth / 2 - bases.fenceInset - 0.4, 1e-9)
		expect.near(pen.walk.minZ, -bases.depth / 2 + 1.6, 1e-9)
		local spawn = bases.spawn.Position
		expect.truthy(math.abs(spawn.X) < pen.walk.maxX and spawn.Z > pen.walk.minZ and spawn.Z < pen.walk.maxZ)
		local sign = pen.signs.pen
		expect.truthy(vectorNear(sign.Position, Vector3.new(10, 0, 20.3)))
		expect.truthy(vectorNear(sign.LookVector, Vector3.new(0, 0, 1), 1e-6)) -- its face toward the gate side
		for index = 1, 10 do
			expect.truthy(WorldLayout.inPlot(index, (WorldLayout.plotFrame(index) :: CFrame) * sign.Position))
		end
	end)

	-- Wb: the gate and the tier decor round the whole base (K:4170-4189 "adds"; owner 2026-10-17: both name signs).
	t.test(
		"wb: the gate at the front-right corner, 2 lamps at the floor's front corners, 2 trees by the sides",
		function()
			local pen = WorldLayout.Bases.pen
			local toward = Vector3.new(0, 0, 1) -- every piece's front faces the gate side, like the sign
			-- Beside the Donut Arch, never behind its name sign (9 wide at x ±4.5): its posts (x ±4 from its middle,
			-- r 0.6, their balls r 0.8) inside the plot's fence and clear of the arch's pillars (x ±8..10).
			expect.truthy(vectorNear(pen.gate.Position, Vector3.new(16.2, 0, 24)))
			expect.truthy(vectorNear(pen.gate.LookVector, toward, 1e-6))
			expect.truthy(
				pen.gate.Position.X + 4.8 <= pen.walk.maxX + 1e-4 and pen.gate.Position.Z + 0.8 <= pen.walk.maxZ
			)
			expect.truthy(pen.gate.Position.X - 4.6 > 10)
			expect.equal(#pen.lamps, 2)
			expect.equal(#pen.trees, 2)
			for index, side in { 1, -1 } do
				local lamp = pen.lamps[index]
				expect.truthy(vectorNear(lamp.Position, Vector3.new(side * 19.25, 0, 18.5)))
				expect.truthy(vectorNear(lamp.LookVector, toward, 1e-6))
				expect.truthy(math.abs(lamp.Position.X) + 1.6 <= pen.walk.maxX) -- its candy (r 1.6) inside the fence
				local tree = pen.trees[index]
				expect.truthy(vectorNear(tree.at.Position, Vector3.new(side * 18, 0, 0)))
				expect.truthy(vectorNear(tree.at.LookVector, toward, 1e-6))
				expect.truthy(math.abs(tree.at.Position.X) + 3 <= pen.walk.maxX) -- its canopy (r 3) by the side fence
			end
			-- L:192-193: the +X tree in the Royal post's gold, the -X one in its pink rail colour.
			expect.equal(pen.trees[1].color, "PenFenceRoyalPost")
			expect.equal(pen.trees[2].color, "PenFenceRoyalRail")
			for index = 1, 10 do
				local frame = WorldLayout.plotFrame(index) :: CFrame
				for _, at in { pen.gate, pen.lamps[1], pen.lamps[2], pen.trees[1].at, pen.trees[2].at } do
					expect.truthy(WorldLayout.inPlot(index, frame * at.Position))
				end
			end
		end
	)

	-- Pens3 phase 11: the shelf, its cubbies, the TOP spot and the SHELF SPOTS sign (lobby design v6, turned).
	t.test("pens3 phase 11: the SHELF SPOTS sign, the shelf at the plot's back, its cubbies in K's order", function()
		local pen = WorldLayout.Bases.pen
		local toward = Vector3.new(0, 0, 1)
		local sign = pen.signs.shelf
		expect.truthy(vectorNear(sign.Position, Vector3.new(-10, 0, 20.4)))
		expect.truthy(vectorNear(sign.LookVector, toward, 1e-6))
		local shelf = pen.shelf
		expect.truthy(vectorNear(shelf.at.Position, Vector3.new(0, 0, -16)))
		expect.truthy(vectorNear(shelf.at.LookVector, toward, 1e-6))
		-- Wb: its front (3 studs in front of its middle) with the glass locks before it (L:247: 0.125 out, 0.15 thick)
		-- is the front of the shelf row's walk block (rounded out to 0.05).
		local front = shelf.at * Vector3.new(0, 0, -3.25)
		local row = nil
		for _, block in pen.blocks do
			if block.name == "shelfRow" then
				row = block
			end
		end
		expect.near(front.Z, (row :: any).maxZ, 1e-6)
		-- LK:188's slots in K's order, two to a row: the middle pair below, the outer pair below, then the same above.
		local want = {
			Vector3.new(-3.3, 1, -0.5),
			Vector3.new(3.3, 1, -0.5),
			Vector3.new(-9.9, 1, -0.5),
			Vector3.new(9.9, 1, -0.5),
			Vector3.new(-3.3, 8.3, -0.5),
			Vector3.new(3.3, 8.3, -0.5),
			Vector3.new(-9.9, 8.3, -0.5),
			Vector3.new(9.9, 8.3, -0.5),
		}
		expect.equal(#shelf.cubbies, 8)
		expect.equal(#shelf.cubbies, Config.Economy.Pen.shelfMaxRows * Config.Economy.Pen.shelfRowSpots)
		for index, at in want do
			expect.truthy(vectorNear(shelf.cubbies[index], at))
		end
		expect.truthy(shelf.top.Y > 15.6) -- over the shelf's top (LK:186: 15.6 tall)
		for index = 1, 10 do
			local frame = WorldLayout.plotFrame(index) :: CFrame
			expect.truthy(WorldLayout.inPlot(index, frame * sign.Position))
			for _, x in { -13.7, 13.7 } do -- the shelf's corners (27.4 wide)
				for _, z in { -3, 3 } do
					expect.truthy(WorldLayout.inPlot(index, frame * (shelf.at * Vector3.new(x, 0, z))))
				end
			end
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
	-- Pens3 phase 12: the highway ----------------------------------------------------------------------------------

	t.test(
		"pens3 phase 12: the highway lies outside the island and the arena slots; d studs is down its LookVector",
		function()
			local H = WorldLayout.Highway
			local origin: CFrame = H.origin
			expect.near(origin.LookVector.Y, 0, FLOAT_TOLERANCE) -- a level lane
			local gates = Config.Economy.Highway.gatesAt
			local far = WorldLayout.highwayCFrame(0, 0, gates)
			expect.truthy(vectorNear(far.Position, origin.Position + origin.LookVector * gates, 1e-2))
			expect.truthy(vectorNear(far.LookVector, origin.LookVector))
			local marker = WorldLayout.highwayCFrame(19, 1, 100)
			expect.truthy(vectorNear(marker.Position, (origin * CFrame.new(19, 1, -100)).Position, 1e-3))
			-- The footprint: the ground 400 wide (HK:28) from the watch steps 60 behind the start line to the Golden
			-- Gates' pillars (radius 3.6, HK:90) past gatesAt; its world bounds (conservative for a turned origin).
			local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
			for _, x in { -200, 200 } do
				for _, d in { -60, gates + 4 } do
					local p = WorldLayout.highwayCFrame(x, 0, d).Position
					low, high = low:Min(p), high:Max(p)
				end
			end
			low -= Vector3.new(0, 10, 0)
			high += Vector3.new(0, 70, 0)
			local slab = WorldLayout.Lobby.baseSlab
			local half = slab.size / 2 + Vector3.new(0, 100, 0)
			expect.falsy(WorldLayout.boundsOverlap(low, high, slab.position - half, slab.position + half))
			local apron = WorldLayout.Arena.apron.size / 2 + Vector3.new(0, 100, 0)
			for _, slot in Config.Duel.Arena.SlotOrigins do
				expect.falsy(WorldLayout.boundsOverlap(low, high, slot - apron, slot + apron))
			end
		end
	)

	t.test("pens3 phase 13: the launch deck is v6's (L:20, :31-37) with one open throw area, no spots", function()
		local H = WorldLayout.Highway
		local deck = H.deck
		expect.truthy(vectorNear(deck.platform, Vector3.new(0, 0.5, 35.5))) -- L:20 (0, 0.5, -26.5)
		-- Owner 2026-10-18 ("a general area where they walk up and everybody can throw"): v6's L:21-30 spots are gone.
		expect.equal(deck.spots, nil)
		expect.equal(deck.spotSize, nil)
		expect.equal(deck.launcherMount, nil)
		expect.equal(deck.playerStand, nil)
		expect.equal(WorldLayout.Tags.LaunchSpot, nil)
		-- The throw area: the deck top (y 0.5 + its 2-stud slab, LK:159; 30 x 15 centred 1.25 toward the gate), 12
		-- high.
		local area = H.throwArea
		expect.truthy(vectorNear(area.size, Vector3.new(30, 12, 15)))
		expect.near(area.position.Y - area.size.Y / 2, deck.platform.Y + 2, FLOAT_TOLERANCE)
		expect.near(area.position.Z, deck.platform.Z - 1.25, FLOAT_TOLERANCE)
		expect.near(area.position.X, 0, FLOAT_TOLERANCE)
		expect.truthy(area.position.Z - area.size.Z / 2 > 0) -- all of it behind the start line
		-- The board: 3 last-throw rows, newest first, and the server best.
		expect.equal(H.boardRows, 3)
		expect.deepEqual(H.boardSlots, {
			"Last1Who",
			"Last1Distance",
			"Last2Who",
			"Last2Distance",
			"Last3Who",
			"Last3Distance",
			"BestWho",
			"BestDistance",
		})
		expect.deepEqual(deck.fences, { -10.5, -3.5, 3.5, 10.5 }) -- L:34-37
		expect.equal(#deck.watchSteps, 2) -- L:31-32
		expect.truthy(vectorNear(deck.watchSteps[1].position, Vector3.new(21, 0.5, 50)))
		expect.near(deck.watchSteps[1].yaw, math.rad(38.9), FLOAT_TOLERANCE)
		expect.truthy(vectorNear(deck.watchSteps[2].position, Vector3.new(-21, 0.5, 50)))
		expect.near(deck.watchSteps[2].yaw, math.rad(-38.9), FLOAT_TOLERANCE)
		expect.equal(H.laneWidth, 30) -- K:1693
		expect.equal(H.tileLength, 50)
		expect.equal(H.markerEvery, 100) -- K:1748, L:476
		expect.equal(H.markerX, 19) -- L:476
		expect.equal(H.maxPiecesPerBiome, 600) -- spec.txt:157
	end)

	-- P13v4 (owner 2026-10-19: the TikTok throw's rings and targets; work/pens3/p13v4/SPEC.md 3.3).
	t.test("p13v4: 3 rings and 2 BULLSEYE pads a biome, by the placement rule, inside it, clear of the lane", function()
		local H = WorldLayout.Highway
		local C = Config.Economy.Highway
		local F = C.flight
		expect.equal(H.ringRadius, 10)
		expect.equal(H.ringTube, 0.6)
		expect.equal(H.ringSegments, 12)
		expect.equal(H.padRadius, 15)
		local function row(d: number, y: number, biome: number): any
			return { d = d, y = y, biome = biome }
		end
		expect.deepEqual(H.rings, {
			row(81, 55.2, 1),
			row(162, 52.5, 1),
			row(243, 19.7, 1),
			row(426, 61, 2),
			row(552, 44.7, 2),
			row(678, 14.9, 2),
			row(965, 51.6, 3),
			row(1130, 34.9, 3),
			row(1295, 12, 3),
			row(1725, 45.6, 4),
			row(1950, 30, 4),
			row(2175, 12, 4),
			row(2830, 43.1, 5),
			row(3160, 28.1, 5),
			row(3490, 12, 5),
			row(4420, 38.4, 6),
			row(4840, 24.7, 6),
			row(5260, 12, 6),
			row(6495, 33.4, 7),
			row(6990, 21.3, 7),
			row(7485, 12, 7),
		})
		local pads = {}
		for _, pad in H.pads do
			table.insert(pads, { pad.d, pad.biome })
		end
		expect.deepEqual(pads, {
			{ 135, 1 },
			{ 255, 1 },
			{ 525, 2 },
			{ 725, 2 },
			{ 1115, 3 },
			{ 1395, 3 },
			{ 1950, 4 },
			{ 2350, 4 },
			{ 3175, 5 },
			{ 3775, 5 },
			{ 4900, 6 },
			{ 5700, 6 },
			{ 7125, 7 },
			{ 8125, 7 },
		})
		-- The rule, re-derived: C = the plain arc from the throw area's middle (d -34.25, y 5.5 + releaseUp = 7) of a
		-- throw landing at the biome's end e; c = min(e, C's carry); ring k at round(s + (c - s) x 0.3 / 0.6 / 0.9),
		-- its centre C's height there (0.1), at least 12. Pads at 0.45 and 0.85 of each biome.
		local from, y0, clear = -H.throwArea.position.Z, 5.5 + F.releaseUp, 2
		for index, start in C.starts do
			local stop = C.starts[index + 1] or C.gatesAt
			local carry = math.min(math.clamp(F.carryShare * stop, F.carryMin, F.carryMax), stop)
			local peak = math.min(F.peakShare * (carry - from), F.peakMax)
			local c = math.min(stop, carry)
			for k, share in { 0.3, 0.6, 0.9 } do
				local ring = H.rings[3 * (index - 1) + k]
				local d = math.round(start + (c - start) * share)
				local u = (d - from) / (carry - from)
				local y = y0 + (clear - y0) * u + 4 * peak * u * (1 - u)
				expect.equal(ring.d, d)
				expect.near(ring.y, math.max(math.round(y * 10) / 10, 12), 1e-9)
				expect.equal(ring.biome, index)
				expect.truthy(ring.d >= start and ring.d < stop)
				expect.truthy(ring.y - H.ringRadius - H.ringTube > 1) -- clears the lane's top (y 1)
			end
			for k, share in { 0.45, 0.85 } do
				local pad = H.pads[2 * (index - 1) + k]
				expect.equal(pad.d, math.round(start + (stop - start) * share))
				expect.equal(pad.biome, index)
				expect.truthy(pad.d - H.padRadius >= start and pad.d + H.padRadius <= stop) -- the whole pad inside
			end
		end
		for index = 2, #H.rings do
			expect.truthy(H.rings[index].d > H.rings[index - 1].d) -- in passing order
		end
		expect.truthy(table.isfrozen(H.rings) and table.isfrozen(H.rings[1]) and table.isfrozen(H.pads[1]))
	end)

	t.test("pens3 phase 12: 7 biome looks in Config's order with v6's tints, sky biomes without ground", function()
		local Palette = t.requireShared("Art/Palette")
		local biomes = WorldLayout.Highway.biomes
		expect.equal(#biomes, #Config.Economy.Highway.starts)
		local models =
			{ "Biome_1_CM", "Biome_2_BT", "Biome_3_BL", "Biome_4_FD", "Biome_5_LV", "Biome_6_RR", "Biome_7_DH" }
		-- L:533, :616, :723, :895, :1130, :1397 (0: the launch gate's banner, L:33)
		local scales = { 0, 1, 1.1, 1.2, 1.3, 1.45, 1.6 }
		local hex =
			{ -- the lane top, the lane edge, the rails, the markers, the ground (L:458-1397; RR's top is rainbow)
				{ "FFE3EF", "FF8FBF", "FFF6EC", "FF8FBF", "9EE89B" },
				{ "F2C487", "C9803F", "FFF6EC", "E8A55A", "F3D9A4" },
				{ "EED6B8", "3FCFC0", "FFF6EC", "3FCFC0", "7FD8D0" },
				{ "D9F3FF", "8FD8FF", "FFFFFF", "8FD8FF", "F4FBFF" },
				{ "4A3B4F", "FF6A3D", "2E2230", "FF6A3D", "3A2C3A" },
				{ "", "", "FFFFFF", "B98CFF", "" },
				{ "FFFDF6", "FFD45C", "FFD45C", "FFD45C", "" },
			}
		local function hexOf(token: string?): string
			if token == nil then
				return ""
			end
			local color = Palette[token]
			expect.equal(typeof(color), "Color3")
			return string.upper(color:ToHex())
		end
		local keys: { [string]: boolean } = {}
		for _, key in WorldLayout.textKeys() do
			keys[key] = true
		end
		for index, biome in biomes do
			expect.equal(biome.model, models[index])
			expect.truthy(keys[biome.nameKey])
			hexOf(biome.nameColor)
			local row = hex[index]
			expect.deepEqual({
				hexOf(biome.laneTop),
				hexOf(biome.laneEdge),
				hexOf(biome.rail),
				hexOf(biome.marker),
				hexOf(biome.ground),
			}, row)
			expect.equal(biome.rainbow == true, index == 6) -- rr_rainbow_lane (L:990)
			expect.equal(biome.sky == true, index >= 6) -- K:3432, :3492 sky: no ground; markers and arches 1 up
			if index == 1 then
				expect.equal(biome.arch, nil) -- its arch is the launch gate's banner (L:33)
			else
				expect.near(biome.arch.scale, scales[index], FLOAT_TOLERANCE)
				hexOf(biome.arch.main)
				hexOf(biome.arch.trim)
			end
		end
		for _, key in
			{ "highway.board.title", "highway.board.lastThrow", "highway.board.serverBest", "highway.marker.unit" }
		do
			expect.truthy(keys[key])
		end
	end)

	-- Wb: what LobbyBuilder stands on each plot's floor, and the walk blocks that keep the squishies off it.
	t.test("wb: the plot's props stand on its floor, none in the shelf, each inside a walk block", function()
		local bases = WorldLayout.Bases
		local pen = bases.pen
		local names = {}
		for _, prop in bases.props do
			table.insert(names, prop.name)
		end
		table.sort(names)
		expect.deepEqual(names, {
			"BirdieNestPlanter",
			"ChocolateFlowerBox",
			"GatePillar",
			"GatePillar",
			"KittyLoafMailbox",
			"Spawn",
			"ToastBench",
		})
		local function overlaps(a: any, b: any): boolean
			return a.minX < b.maxX and b.minX < a.maxX and a.minZ < b.maxZ and b.minZ < a.maxZ
		end
		-- The shelf's footprint (27.4 × 6 at z -16, LK:184).
		local shelf = { minX = -13.7, maxX = 13.7, minZ = -19, maxZ = -13 }
		local walk = pen.walk
		for _, prop in bases.props do
			expect.truthy(math.abs(prop.minX) <= bases.width / 2 and math.abs(prop.maxX) <= bases.width / 2)
			expect.truthy(prop.minZ >= -bases.depth / 2 and prop.maxZ <= bases.depth / 2 + 0.4) -- a pillar: 0.4 out
			if overlaps(prop, shelf) then
				error(`{prop.name} pokes into the shelf`)
			end
			-- The part on the squishies' floor lies inside one walk block.
			local onFloor = {
				minX = math.max(prop.minX, walk.minX),
				maxX = math.min(prop.maxX, walk.maxX),
				minZ = math.max(prop.minZ, walk.minZ),
				maxZ = math.min(prop.maxZ, walk.maxZ),
			}
			local inside = false
			for _, block in pen.blocks do
				if
					onFloor.minX >= block.minX
					and onFloor.maxX <= block.maxX
					and onFloor.minZ >= block.minZ
					and onFloor.maxZ <= block.maxZ
				then
					inside = true
				end
			end
			if not inside then
				error(`{prop.name} is in no walk block`)
			end
		end
		-- The front row, the shelf row and the 2 trees' canopies (r 3 round each tree).
		expect.equal(#pen.blocks, 4)
		for _, tree in pen.trees do
			local at = tree.at.Position
			local found = false
			for _, block in pen.blocks do
				if
					block.minX <= at.X - 3
					and block.maxX >= at.X + 3
					and block.minZ <= at.Z - 3
					and block.maxZ >= at.Z + 3
				then
					found = true
				end
			end
			expect.truthy(found)
		end
	end)

	-- Access2 (owner 2026-10-18 "Both"): the walk to the highway's launch deck. PLACEHOLDER: v6 has no bridge (its deck
	-- joins the plaza, L:20-37), so the numbers are readings, except where the bridge meets the deck: the front face of
	-- the platform's back step, box(20, 1, 1.5, 0, 0, 7) on the platform (LK:158-164: top 1 up, front 7.75 back).
	t.test(
		"access2: the north wall opens round the bridge; the bridge runs from the sea to the deck's back step",
		function()
			local lobby = WorldLayout.Lobby
			local bridge = lobby.bridge
			local walls: { [string]: any } = {}
			for _, wall in lobby.Boundaries do
				walls[wall.name] = wall
			end
			expect.equal(walls.NorthWall, nil)
			local west, east = walls.NorthWallWest, walls.NorthWallEast
			expect.truthy(west ~= nil and east ~= nil)
			local wLow, wHigh = west.position - west.size / 2, west.position + west.size / 2
			local eLow, eHigh = east.position - east.size / 2, east.position + east.size / 2
			-- Together the old wall (x -218..218, z -222..-218, y -4..60), but the gap.
			expect.near(wLow.X, -218, FLOAT_TOLERANCE)
			expect.near(eHigh.X, 218, FLOAT_TOLERANCE)
			for _, box in { { wLow, wHigh }, { eLow, eHigh } } do
				expect.near(box[1].Z, -222, FLOAT_TOLERANCE)
				expect.near(box[2].Z, -218, FLOAT_TOLERANCE)
				expect.near(box[1].Y, -4, FLOAT_TOLERANCE)
				expect.near(box[2].Y, 60, FLOAT_TOLERANCE)
			end
			-- The gap: on the bridge's line, at least as wide as the bridge with its rails (the plots' 0.8 fence posts
			-- either side of the 8-stud walk, LobbyBuilder).
			expect.equal(bridge.width, 8) -- spec §2: the paths' width
			expect.near((wHigh.X + eLow.X) / 2, bridge.x, FLOAT_TOLERANCE)
			expect.truthy(eLow.X - wHigh.X >= bridge.width + 2 * 0.8)
			expect.near(bridge.gapHalf, eLow.X - bridge.x, FLOAT_TOLERANCE)
			-- From the sea's top inside the wall (past the shallow water), through the gap, to the deck's back step.
			local seaTop = lobby.baseSlab.position.Y + lobby.baseSlab.size.Y / 2
			expect.near(bridge.fromTop, seaTop, FLOAT_TOLERANCE)
			expect.truthy(bridge.fromZ > wHigh.Z and bridge.fromZ < -WorldLayout.Island.shallow.radius)
			local H = WorldLayout.Highway
			local step = H.origin * (H.deck.platform + Vector3.new(0, 1, 7.75))
			expect.near(bridge.toZ, step.Z, FLOAT_TOLERANCE)
			expect.near(bridge.toTop, step.Y, FLOAT_TOLERANCE)
			expect.near(bridge.x, step.X, FLOAT_TOLERANCE)
			expect.truthy(bridge.toZ < wLow.Z) -- past the wall
			-- A gentle ramp: a few degrees (Roblox walks up to 89°; kids should not notice it).
			local slope = math.deg(math.atan2(bridge.toTop - bridge.fromTop, bridge.fromZ - bridge.toZ))
			expect.truthy(slope > 0 and slope < 10)
		end
	)
end
