--!strict
-- WorldLayout_Test: unit tests for ReplicatedStorage.Shared.World.WorldLayout. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §5.3, §5.11, §7.5-§7.8, §17.4, §17.6, §17.6.1): nine squeeze stations squeeze_01..09, unique, with
-- the §17 tiers (mats 1, Jelly 2, Marshmallow 3, Royal 4); the giant pads' §17.6.1 specs (collision boxes 6.8 / 6.6 /
-- 7.8, top 1.0) fit inside their rounded footprint and their gates; station keep-clear volumes never overlap and no
-- station body reaches into one; routes stay within §7.5 (< 5 s between activities) and the G-D pod exception
-- (<= 7.0 s); spawn routes are no longer than §7.7 / §17.6 state; every sign, prompt and nameplate key resolves in
-- Strings with the §7.7 / §17.7 texts; the practice range, collection, return points, audio zones and arena match
-- their DESIGN numbers. Feel pass (§18.8, §18.10 L1): the arena's wall stripe constants, TagCounts.SD_Ambient =
-- #lollipops + 3, and the grown practice audio zone that contains the whole throw box. First person (spec 2026-10-10
-- §3.5): no prompt (within its maxDistance) and no squeeze station (within stationRadius + radiusTolerance) reaches
-- into the practice throw box, so PracticeSqueeze can take F, E and ButtonX there.
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
	x: number,
	z: number,
	footprint: number,
	corner: number,
	restTop: number,
	collision: number,
	sink: number,
	gate: number,
	inset: number,
}

-- Constants (restated from DESIGN so a drifting layout is caught)

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

-- §17.6.1 pad specs.
local GIANT_PADS: { [string]: PadSpec } = {
	jelly = {
		station = "squeeze_07",
		tier = 2,
		x = -33,
		z = 37,
		footprint = 8,
		corner = 1.2,
		restTop = 1.5,
		collision = 6.8,
		sink = 0.5,
		gate = 12,
		inset = 0.6,
	},
	marshmallow = {
		station = "squeeze_08",
		tier = 3,
		x = -53,
		z = 37,
		footprint = 8,
		corner = 2.0,
		restTop = 1.6,
		collision = 6.6,
		sink = 0.6,
		gate = 12,
		inset = 0.7,
	},
	royal = {
		station = "squeeze_09",
		tier = 4,
		x = 38,
		z = 38,
		footprint = 9,
		corner = 1.0,
		restTop = 1.7,
		collision = 7.8,
		sink = 0.7,
		gate = 14,
		inset = 0.6,
	},
}
local COLLISION_TOP = 1.0
local GATE_CLEARANCE = 0.8
local CORNER_MARGIN = 0.1
local FLOAT_TOLERANCE = 1e-4 -- Vector3 components are single precision

-- Straight-line spawn routes DESIGN states (§7.7, §17.6), in studs; the layout's may not be longer.
local SPAWN = Vector3.new(0, 0, 40)
local SPAWN_ROUTES: { [string]: number } = {
	quests = 19.1,
	daily = 19.1,
	squeeze = 36.8,
	collection = 46.7,
	shop = 66.3,
	duel = 76.0,
	practice = 80.7,
	giftBox = 86.0,
	jellyPad = 33,
	marshmallowPad = 53,
	royalPad = 38,
}
local ROUTE_TOLERANCE = 0.5 -- studs (DESIGN rounds)

-- Exact texts (§7.6 prompts, §7.7 signs, §6.10 notes, §17.7 world keys).
local TEXTS: { [string]: string } = {
	["world.spawnLogo"] = "SQUISHY DUELS",
	["world.spawnSafe"] = "Safe zone: duels happen in the arena",
	["world.duelGateTitle"] = "DUEL ARENA",
	["world.duelGateSubtitle"] = "1v1 duels • Queue at the pad",
	["queue.boardTitle"] = "Duel Queue",
	["queue.boardWaiting"] = "Waiting: {count}",
	["queue.boardActive"] = "Duels in progress: {count} of {max}",
	["queue.boardHint"] = "Matches start automatically when an opponent is found.",
	["prompt.joinQueue"] = "Join 1v1 Queue",
	["prompt.leaveQueue"] = "Leave Queue",
	["world.squeezeTitle"] = "SQUEEZE ZONE",
	["world.squeezeSubtitle"] = "Squeeze your squishy to earn Coins",
	["practice.title"] = "PRACTICE RANGE",
	["practice.sign"] = "Practice range: targets don't pay Coins",
	["practice.targetName"] = "Foam Dummy",
	["box.standTitle"] = "SQUISHY BOXES",
	["box.standSubtitle"] = "Odds are listed before you open",
	["box.oddsTitle"] = "Box Odds",
	["box.restrictedNote"] = "Coin boxes aren't available on your account. You can buy any squishy directly in the Shop, "
		.. "and day 7 of Daily Rewards gives a free Treat Box.",
	["box.unknownNote"] = "Couldn't check box availability. Try again.",
	["prompt.seeBoxes"] = "See Boxes",
	["prompt.shopDirect"] = "Shop Squishies",
	["shop.title"] = "SHOP",
	["shop.subtitle"] = "Squishies for Coins",
	["collection.title"] = "MY COLLECTION",
	["collection.owned"] = "Owned",
	["collection.notOwned"] = "Not owned yet",
	["quest.title"] = "QUESTS",
	["daily.title"] = "DAILY REWARD",
	["daily.ready"] = "Ready to claim!",
	["daily.wait"] = "Next reward in {time}",
	["prompt.viewQuests"] = "View Quests",
	["prompt.dailyReward"] = "Daily Reward",
	["prompt.openShop"] = "Open Shop",
	["prompt.openCollection"] = "Open Collection",
	["prompt.inspect"] = "Inspect",
	["grip.gymTitle"] = "GRIP GYM",
	["grip.pad.foam"] = "Foam Mats",
	["grip.pad.jelly"] = "Jelly Pad",
	["grip.pad.marshmallow"] = "Marshmallow Pad",
	["grip.pad.royal"] = "Royal Cushion",
	["grip.padNeeds"] = "Needs Grip Lv {level}",
	["grip.signLocked"] = "Needs Grip Lv {level} · You: Lv {have}",
	["grip.signOpen"] = "Open · +{coins} Coins · x{mult} Grip",
}

-- Helpers

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 1e-6)
end

local function vectorNear(a: Vector3, b: Vector3, tolerance: number?): boolean
	return near(a.X, b.X, tolerance) and near(a.Y, b.Y, tolerance) and near(a.Z, b.Z, tolerance)
end

local function show(v: Vector3): string
	return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end

local function discBounds(name: string, disc: any): Bounds
	local r, h = disc.diameter / 2, disc.height / 2
	return {
		name = name,
		low = disc.position - Vector3.new(r, h, r),
		high = disc.position + Vector3.new(r, h, r),
	}
end

return function(t: Context)
	local WorldLayout = t.requireShared("World/WorldLayout")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local expect = t.expect

	local function boxBounds(name: string, box: any): Bounds
		local low, high = WorldLayout.boxBounds(box)
		return { name = name, low = low, high = high }
	end

	-- Every collidable station body DESIGN places in the lobby (§7.6, §7.7, §17.6) as world bounds.
	local function stationBodies(): { Bounds }
		local L = WorldLayout
		local bodies: { Bounds } = {
			boxBounds("QuestBoard.board", L.QuestBoard.board),
			discBounds("DailyStand.pedestal", L.DailyStand.pedestal),
			boxBounds("SqueezeZone.plinth", L.SqueezeZone.plinth),
			boxBounds("PracticeRange.backstop", L.PracticeRange.backstop),
			boxBounds("DuelGate.podium", L.DuelGate.podium),
			boxBounds("DuelGate.statusBoard", L.DuelGate.statusBoard),
			boxBounds("DuelGate.beam", L.DuelGate.beam),
			boxBounds("GiftBoxCounter.counter", L.GiftBoxCounter.counter),
			boxBounds("GiftBoxCounter.pedestal", L.GiftBoxCounter.pedestal),
			boxBounds("GiftBoxCounter.oddsBoard", L.GiftBoxCounter.oddsBoard),
			boxBounds("ShopCounter.counter", L.ShopCounter.counter),
			boxBounds("ShopCounter.backShelves", L.ShopCounter.backShelves),
			boxBounds("Collection.tier1", L.Collection.tier1),
			boxBounds("Collection.tier2", L.Collection.tier2),
			boxBounds("Collection.kiosk", L.Collection.kiosk),
		}
		for index, post in L.QuestBoard.posts do
			table.insert(bodies, boxBounds(`QuestBoard.posts[{index}]`, post))
		end
		for index, post in L.DuelGate.posts do
			table.insert(bodies, boxBounds(`DuelGate.posts[{index}]`, post))
		end
		for _, pedestal in L.Collection.pedestals do
			table.insert(bodies, boxBounds(`Collection.pedestals[{pedestal.slot}]`, pedestal))
		end
		for _, key in L.GiantPadKeys do
			local pad = L.GiantPads[key]
			table.insert(bodies, boxBounds(`GiantPads.{key}.collision`, pad.collision))
			table.insert(bodies, boxBounds(`GiantPads.{key}.signPost`, pad.signPost))
		end
		local blocks = L.Props.toyBlocks
		for index, position in blocks.positions do
			-- Only the bottom block collides (§7.7); reading: a 3-stud cube.
			local size = Vector3.new(blocks.footprint, blocks.footprint, blocks.footprint)
			table.insert(bodies, {
				name = `Props.toyBlocks[{index}]`,
				low = position - Vector3.new(size.X / 2, 0, size.Z / 2),
				high = position + Vector3.new(size.X / 2, size.Y, size.Z / 2),
			})
		end
		return bodies
	end

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
		-- Config.Grip.Pads is indexed by tier: the pad of each tier is the giant pad with that key.
		local pads = Config.Grip.Pads
		expect.equal(#pads, 4)
		expect.equal(pads[1].key, "foam")
		for key, spec in GIANT_PADS do
			expect.equal(WorldLayout.giantPadForStation(spec.station).key, key)
			expect.equal(pads[spec.tier].key, key)
		end
	end)

	t.test("the six mats sit at §7.6 X {-46, -36, -26} × Z {0, 14}, Ø8", function()
		local expected = {
			Vector3.new(-46, 0, 0),
			Vector3.new(-36, 0, 0),
			Vector3.new(-26, 0, 0),
			Vector3.new(-46, 0, 14),
			Vector3.new(-36, 0, 14),
			Vector3.new(-26, 0, 14),
		}
		for index, mat in WorldLayout.SqueezeZone.mats do
			local floor = Vector3.new(mat.position.X, 0, mat.position.Z)
			expect.truthy(vectorNear(floor, expected[index]))
			local station = WorldLayout.station(mat.id)
			expect.equal(station.halfSize, 4)
			expect.equal(station.top, WorldLayout.SqueezeZone.matHeight)
		end
	end)

	-- Giant pads (§17.6.1) ------------------------------------------------------------------------------------------

	t.test("giant pads match the §17.6.1 table (collision boxes 6.8 / 6.6 / 7.8, top 1.0)", function()
		local count = 0
		for key, spec in GIANT_PADS do
			count += 1
			local pad = WorldLayout.giantPad(key)
			expect.truthy(pad ~= nil)
			expect.equal(pad.key, key)
			expect.equal(pad.stationId, spec.station)
			expect.equal(pad.tier, spec.tier)
			expect.equal(pad.model, "GiantPad_" .. key)
			expect.truthy(vectorNear(pad.center, Vector3.new(spec.x, 0, spec.z)))
			expect.equal(pad.footprint, spec.footprint)
			expect.equal(pad.cornerRadius, spec.corner)
			expect.equal(pad.restTop, spec.restTop)
			expect.equal(pad.sinkDepth, spec.sink)
			expect.equal(pad.collisionTop, COLLISION_TOP)
			expect.truthy(vectorNear(pad.collision.size, Vector3.new(spec.collision, 1.0, spec.collision)))
			expect.truthy(vectorNear(pad.collision.position, Vector3.new(spec.x, 0.5, spec.z)))
			expect.equal(pad.gate.diameter, spec.gate)
			expect.equal(pad.gate.height, 9)
			expect.truthy(vectorNear(pad.gate.position, Vector3.new(spec.x, 4.5, spec.z)))
			-- The server measures squeezes from the collision box centre (§17.6.1).
			expect.equal(WorldLayout.station(spec.station).position, pad.collision.position)
			expect.equal(WorldLayout.station(spec.station).top, COLLISION_TOP)
		end
		expect.equal(count, #WorldLayout.GiantPadKeys)
		expect.deepEqual(WorldLayout.GiantPadKeys, { "jelly", "marshmallow", "royal" })
		expect.equal(WorldLayout.GiantPads.jelly.blueprintId, "giant_jelly")
		expect.equal(WorldLayout.GiantPads.marshmallow.blueprintId, "giant_marshmallow")
		expect.equal(WorldLayout.GiantPads.royal.blueprintId, "giant_cushion")
	end)

	t.test("every giant pad fits its gate and its collision box fits the rounded footprint", function()
		for _, key in WorldLayout.GiantPadKeys do
			local pad = WorldLayout.GiantPads[key]
			local f, r = pad.footprint / 2, pad.cornerRadius
			local b = pad.collision.size.X / 2
			-- Inset from the visual edge (0.7 for the puffy Marshmallow).
			expect.truthy(f - b >= GIANT_PADS[key].inset - FLOAT_TOLERANCE)
			-- The rounded corner is >= 0.8 inside the gate.
			local reach = (f - r) * math.sqrt(2) + r
			expect.truthy(pad.gate.diameter / 2 - reach >= GATE_CLEARANCE)
			-- Each collision-box corner lies inside the rounded footprint.
			if b > f - r then
				expect.truthy((b - (f - r)) * math.sqrt(2) <= r - CORNER_MARGIN + FLOAT_TOLERANCE)
			end
			expect.truthy(pad.collisionTop < pad.restTop)
			-- Every sign post stands outside its jelly radius.
			local post = pad.signPost.position
			expect.truthy(WorldLayout.horizontalDistance(post, pad.center) > pad.gate.diameter / 2)
		end
	end)

	-- Keep-clear volumes (§7.7 props rules 1 and 5, §17.6) ----------------------------------------------------------

	t.test("station keep-clear volumes never overlap each other", function()
		local volumes = {}
		for _, volume in WorldLayout.KeepClear do
			if volume.kind == "station" then
				table.insert(volumes, volume)
			end
		end
		expect.truthy(#volumes >= 17) -- 8 stands/zones + 9 squeeze stations
		local overlaps = {}
		for i = 1, #volumes do
			local a = volumes[i]
			local aLow, aHigh = a.position - a.size / 2, a.position + a.size / 2
			for j = i + 1, #volumes do
				local b = volumes[j]
				if WorldLayout.boundsOverlap(aLow, aHigh, b.position - b.size / 2, b.position + b.size / 2) then
					table.insert(overlaps, a.name .. " / " .. b.name)
				end
			end
		end
		if #overlaps > 0 then
			error("overlapping keep-clear volumes: " .. table.concat(overlaps, ", "))
		end
	end)

	t.test("every squeeze station and every stand approach has a keep-clear volume", function()
		local byName: { [string]: any } = {}
		for _, volume in WorldLayout.KeepClear do
			expect.falsy(byName[volume.name])
			byName[volume.name] = volume
			-- §7.7: the band between Y 0.5 and 24 (pods start above their collision box).
			local top = volume.position.Y + volume.size.Y / 2
			expect.truthy(near(top, 24))
		end
		for _, station in WorldLayout.Stations do
			local volume = byName[station.id]
			expect.truthy(volume ~= nil)
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
		local promenade = byName.promenade
		expect.equal(promenade.kind, "aisle")
		expect.truthy(near(promenade.size.X, 20)) -- X -10..10
	end)

	t.test("every prompt and every mat has a 5-stud keep-clear radius (§7.7 props rule 1)", function()
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
		for _, mat in WorldLayout.SqueezeZone.mats do
			table.insert(points, { name = mat.id, point = mat.position })
		end
		for _, entry in points do
			-- The box around the point, from Y 0.5 to 24, must lie inside one keep-clear volume.
			local covered = false
			for _, volume in WorldLayout.KeepClear do
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
			if body.high.Y <= 0.5 then
				continue -- floor coverings
			end
			for _, volume in WorldLayout.KeepClear do
				if volume.kind == "prompt" then
					continue -- a prompt volume holds its own station; Verify exempts station bodies
				end
				local low, high = volume.position - volume.size / 2, volume.position + volume.size / 2
				if WorldLayout.boundsOverlap(body.low, body.high, low, high) then
					table.insert(hits, body.name .. " in " .. volume.name)
				end
			end
		end
		if #hits > 0 then
			error("station bodies inside keep-clear volumes: " .. table.concat(hits, ", "))
		end
	end)

	-- Routes (§7.5, §7.7, §17.6) ------------------------------------------------------------------------------------

	t.test("route speed is the uniform WalkSpeed", function()
		expect.equal(WorldLayout.Routes.walkSpeed, Config.Duel.Rules.Movement.WalkSpeed)
		expect.equal(WorldLayout.Routes.maxSeconds, 5)
		expect.equal(WorldLayout.Routes.podMaxSeconds, 7.0)
	end)

	t.test("routes between activities stay under 5 s, pod routes within the G-D 7.0 s", function()
		local activities = WorldLayout.Activities
		expect.equal(#activities, 11)
		local worst, worstPod = 0, 0
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
				else
					worst = math.max(worst, shortest)
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
		-- §7.7: the longest station-to-station route is ≈ 79 studs (4.9 s); §17.6: Marshmallow -> gift box 7.0 s.
		expect.near(worst, 4.9, 0.05)
		expect.near(worstPod, 7.0, 0.05)
	end)

	t.test("spawn routes are no longer than DESIGN states", function()
		for _, activity in WorldLayout.Activities do
			local stated = SPAWN_ROUTES[activity.name]
			expect.truthy(stated ~= nil)
			local shortest = math.huge
			for _, point in activity.points do
				shortest = math.min(shortest, WorldLayout.horizontalDistance(SPAWN, point))
			end
			if shortest > stated + ROUTE_TOLERANCE then
				error(string.format("spawn -> %s is %.1f studs, DESIGN says %.1f", activity.name, shortest, stated))
			end
		end
		expect.truthy(vectorNear(WorldLayout.Spawn.location.position, Vector3.new(0, -0.45, 40)))
	end)

	t.test("every activity has a waypoint; squeeze points at the mat nearest the spawn", function()
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
		expect.truthy(nearest ~= nil)
		local waypoint = WorldLayout.waypoint("squeeze")
		expect.truthy(near(waypoint.X, (nearest :: Vector3).X) and near(waypoint.Z, (nearest :: Vector3).Z))
		expect.equal(WorldLayout.waypoint("nowhere"), nil)
	end)

	-- Signs, prompts and texts (§7.6, §7.7, §17.6, §17.7) -----------------------------------------------------------

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

	t.test("every §7.7 sign key and §7.6 prompt is placed in the world", function()
		local used: { [string]: boolean } = {}
		for _, key in WorldLayout.textKeys() do
			used[key] = true
		end
		local unplaced = {}
		for key in TEXTS do
			if not used[key] and key ~= "grip.pad.foam" then -- the Foam Mats have no pod sign
				table.insert(unplaced, key)
			end
		end
		table.sort(unplaced)
		if #unplaced > 0 then
			error("keys no sign, prompt or nameplate uses: " .. table.concat(unplaced, ", "))
		end
	end)

	t.test("world texts are the exact DESIGN §7.7 / §17.7 texts", function()
		local wrong = {}
		for key, text in TEXTS do
			if Strings.resolve(key) ~= text then
				table.insert(wrong, key)
			end
		end
		table.sort(wrong)
		if #wrong > 0 then
			error("texts differ from DESIGN: " .. table.concat(wrong, ", "))
		end
	end)

	t.test("signs: unique ids, static or live lines, never both, within the SurfaceGui budget", function()
		local ids: { [string]: boolean } = {}
		for _, sign in WorldLayout.Signs do
			expect.falsy(ids[sign.id])
			ids[sign.id] = true
			expect.truthy(#sign.lines >= 1)
			expect.truthy(near(sign.facing.Magnitude, 1, 1e-6))
			for _, line in sign.lines do
				expect.truthy(line.letterHeight > 0)
				-- One writer per label: a live label never carries SD_TextKey.
				if line.live then
					expect.equal(line.textKey, nil)
				else
					expect.truthy((line.textKey == nil) ~= (line.bakeKey == nil))
				end
			end
		end
		expect.truthy(#WorldLayout.Signs <= WorldLayout.Budgets.lobbySurfaceGuis)
	end)

	t.test("sign positions follow §7.7 and §17.6", function()
		local byId: { [string]: any } = {}
		for _, sign in WorldLayout.Signs do
			byId[sign.id] = sign
		end
		local expected: { [string]: Vector3 } = {
			-- §7.6 says (0, 0.03, 28); Y is lifted onto the carpet edge strips (next test), X and Z are DESIGN's.
			spawnPlate = Vector3.new(0, 0.095, 28),
			-- §7.7 says Y 12; raised to 13.5 so the statue in front of it no longer hides the subtitle.
			squeezeSign = Vector3.new(-59.7, 13.5, 6),
			practiceSign = Vector3.new(-42, 12, -51.7),
			boxStandSign = Vector3.new(40, 13.5, -42),
			oddsBoard = Vector3.new(29, 5, -50),
			shopSign = Vector3.new(40, 12, -21),
			collectionSign = Vector3.new(49, 12, 6),
			dailySign = Vector3.new(19.5, 7, 26),
			-- §7.6 says Y 8; raised to 11 so a character walking behind the podium passes under it.
			queueBoard = Vector3.new(0, 11, -51),
			pod_jelly = Vector3.new(-33, 11.5, 30.2),
			pod_marshmallow = Vector3.new(-53, 11.5, 30.2),
			pod_royal = Vector3.new(38, 11.5, 30.2),
		}
		for id, position in expected do
			local sign = byId[id]
			expect.truthy(sign ~= nil)
			if not vectorNear(sign.position, position) then
				error(`{id} is at {show(sign.position)}, DESIGN says {show(position)}`)
			end
		end
		expect.truthy(vectorNear(byId.squeezeSign.facing, Vector3.new(1, 0, 0)))
		expect.truthy(vectorNear(byId.pod_jelly.size, Vector3.new(8, 4, 0.4)))
		expect.truthy(vectorNear(byId.pod_royal.size, Vector3.new(8, 3, 0.4)))
	end)

	-- The squeeze sign hangs on the west shelves behind the Kitty Bread statue (§7.6: scale 7 on a 1-tall plinth; its
	-- ears reach about Y 11.1): the panel starts at Y 11 with its lines top-aligned (the subtitle's letters sit above
	-- Y 11.6) and ends under the awning.
	t.test("the squeeze sign clears the statue in front of it and stays under the awning", function()
		local sign: any = nil
		for _, entry in WorldLayout.Signs do
			if entry.id == "squeezeSign" then
				sign = entry
			end
		end
		expect.truthy(sign ~= nil)
		local bottom = sign.position.Y - sign.size.Y / 2
		local top = sign.position.Y + sign.size.Y / 2
		expect.truthy(bottom >= 11 - FLOAT_TOLERANCE)
		expect.truthy(top <= WorldLayout.Props.awnings.minY + FLOAT_TOLERANCE)
		expect.equal(sign.align, "top") -- the subtitle sits as high as it can
	end)

	-- §7.7 rule 3 / walkability: the queue status board is decor (no collision) over the walkable alcove behind the
	-- podium, so it must hang above a walking character (about 5.7 studs tall, 6.5 with a margin) and under the arch.
	t.test("the queue status board hangs above a walking character and under the arch sign", function()
		local low, high = WorldLayout.boxBounds(WorldLayout.DuelGate.statusBoard)
		expect.truthy(low.Y >= 6.5)
		local beam = WorldLayout.DuelGate.beam
		expect.truthy(high.Y < beam.position.Y - beam.size.Y / 2)
	end)

	-- The lollipops are decor; none may stand inside a station body (the NW one used to pierce the practice
	-- backstop). The head is a Ø6 disc 1 thick on the stick top, its flat sides facing the lobby centre.
	t.test("no lollipop stick or head reaches into a station body", function()
		local spec = WorldLayout.Props.lollipops
		local hits = {}
		for index, base in spec.positions do
			local stickR = spec.stickDiameter / 2
			local stick = {
				low = base + Vector3.new(-stickR, 0, -stickR),
				high = base + Vector3.new(stickR, spec.stickHeight, stickR),
			}
			local facing = Vector3.new(-base.X, 0, -base.Z).Unit
			local r, halfThick = spec.headDiameter / 2, spec.headThickness / 2
			local extent = Vector3.new(
				r * math.sqrt(1 - facing.X * facing.X) + halfThick * math.abs(facing.X),
				r,
				r * math.sqrt(1 - facing.Z * facing.Z) + halfThick * math.abs(facing.Z)
			)
			local headCentre = base + Vector3.new(0, spec.stickHeight, 0)
			local head = { low = headCentre - extent, high = headCentre + extent }
			for _, body in stationBodies() do
				for _, piece in { stick, head } do
					if WorldLayout.boundsOverlap(piece.low, piece.high, body.low, body.high) then
						table.insert(hits, `lollipop {index} in {body.name}`)
					end
				end
			end
		end
		if #hits > 0 then
			error(table.concat(hits, ", "))
		end
	end)

	-- §7.7: "SQUISHY DUELS" must be readable on the floor plate, so no floor covering may cover any of it.
	t.test("the logo floor plate shows above every floor covering it overlaps", function()
		local plate = WorldLayout.Spawn.logoPlate
		local plateLow, plateHigh = WorldLayout.boxBounds(plate)
		expect.truthy(near(plate.size.X, 24) and near(plate.size.Z, 8) and near(plate.position.Z, 28))
		local coverings = { WorldLayout.Promenade.carpet }
		for _, strip in WorldLayout.Promenade.edgeStrips do
			table.insert(coverings, strip)
		end
		local overlapped = 0
		for _, covering in coverings do
			local low, high = WorldLayout.boxBounds(covering)
			local sharesFloor = low.X < plateHigh.X
				and plateLow.X < high.X
				and low.Z < plateHigh.Z
				and plateLow.Z < high.Z
			if sharesFloor then
				overlapped += 1
				if not (plateLow.Y >= high.Y - FLOAT_TOLERANCE) then
					error(`the logo plate (Y {plateLow.Y}..{plateHigh.Y}) is under a covering whose top is {high.Y}`)
				end
			end
		end
		expect.equal(overlapped, 3) -- the carpet and both edge strips run under it
	end)

	-- §7.6: a stand built before its feature exists is inert, so its sign never offers a reward it cannot give.
	t.test("the daily sign's live Status line is built empty and written only by its owner", function()
		local status: any = nil
		for _, sign in WorldLayout.Signs do
			if sign.id == "dailySign" then
				for _, line in sign.lines do
					if line.name == "Status" then
						status = line
					end
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

	t.test("pod signs: SD_GripSign per tier, Title grip.pad.<key>, one Live line without a key", function()
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
	end)

	t.test("stand prompts sit on their stations with the §7.6 defaults", function()
		local stands = {
			{ WorldLayout.QuestBoard, "prompt.viewQuests", Vector3.new(-15.5, 3, 26), Vector3.new(-13, 0, 26) },
			{ WorldLayout.DailyStand, "prompt.dailyReward", Vector3.new(15, 3, 26), Vector3.new(13, 0, 26) },
			{ WorldLayout.GiftBoxCounter, "prompt.seeBoxes", Vector3.new(28.5, 3, -42), Vector3.new(26, 0, -42) },
			{ WorldLayout.ShopCounter, "prompt.openShop", Vector3.new(29.5, 3, -21), Vector3.new(26, 0, -21) },
			{ WorldLayout.DuelGate, "prompt.joinQueue", nil, Vector3.new(0, 0, -36) },
			{ WorldLayout.Collection, "prompt.openCollection", nil, Vector3.new(32, 0, 6) },
		} :: { { any } }
		for _, entry in stands do
			local stand, key, position, approach = entry[1], entry[2], entry[3], entry[4]
			expect.equal(stand.prompt.actionKey, key)
			expect.equal(stand.prompt.maxDistance, 10)
			expect.equal(stand.prompt.requiresLineOfSight, true)
			if position then
				expect.truthy(vectorNear(stand.prompt.position, position))
			end
			expect.truthy(vectorNear(stand.approach, approach))
		end
		expect.equal(WorldLayout.DuelGate.prompt.altActionKey, "prompt.leaveQueue")
		expect.equal(WorldLayout.GiftBoxCounter.prompt.altActionKey, "prompt.shopDirect")
	end)

	-- Practice range, collection, return points, audio zones -------------------------------------------------------

	t.test("practice range: 9 targets, 3 lanes × 12/20/28 studs, one moving (§5.11)", function()
		local range = WorldLayout.PracticeRange
		local targets = range.targets
		expect.equal(#targets, 9)
		local ids: { [string]: boolean } = {}
		local moving = 0
		for _, target in targets do
			expect.falsy(ids[target.id])
			ids[target.id] = true
			expect.truthy(table.find({ -47, -37, -27 }, target.position.Z) ~= nil)
			expect.truthy(table.find({ 12, 20, 28 }, target.distance) ~= nil)
			expect.equal(target.position.X, range.firingLineX - target.distance)
			expect.equal(target.nameKey, "practice.targetName")
			if target.moving then
				moving += 1
				expect.equal(target.distance, 20)
				expect.equal(target.position.Z, -37)
				expect.equal(target.railLength, 12)
				expect.equal(target.period, 9.42)
				-- Peak speed ≈ 4 studs/s.
				expect.near(target.railLength / 2 * 2 * math.pi / target.period, 4, 0.01)
			else
				expect.equal(target.railLength, 0)
				expect.equal(target.period, 0)
			end
		end
		expect.equal(moving, 1)
		expect.equal(range.firingLineX, -24)
		local low, high =
			range.throwBox.position - range.throwBox.size / 2, range.throwBox.position + range.throwBox.size / 2
		expect.truthy(vectorNear(low, Vector3.new(-24, 0, -54)))
		expect.truthy(vectorNear(high, Vector3.new(-16, 12, -20)))
		expect.equal(range.laneFloorTopY, 0.06)
	end)

	t.test("collection: 8 pedestals in slot order on the two tiers, Inspect within 12 studs", function()
		local pedestals = WorldLayout.Collection.pedestals
		expect.equal(#pedestals, 8)
		local zs = { -3, 2.5, 8, 13.5, -0.25, 5.25, 10.75, 16.25 }
		for index, pedestal in pedestals do
			expect.equal(pedestal.slot, index)
			expect.equal(pedestal.position.Z, zs[index])
			expect.equal(pedestal.position.X, if index <= 4 then 40 else 45)
			local bottom = pedestal.position.Y - pedestal.size.Y / 2
			expect.near(bottom, if index <= 4 then 2 else 4.5, 1e-6)
			expect.equal(pedestal.prompt.actionKey, "prompt.inspect")
			expect.equal(pedestal.prompt.maxDistance, 12)
			expect.equal(pedestal.prompt.requiresLineOfSight, false)
		end
	end)

	t.test("return points: slots 1 and 2 at (±6, 0, -24) facing +Z", function()
		local points = WorldLayout.ReturnPoints
		expect.equal(#points, 2)
		local xs: { [number]: boolean } = {}
		for index, point in points do
			expect.equal(point.slot, index)
			expect.equal(math.abs(point.position.X), 6)
			expect.equal(point.position.Z, -24)
			expect.equal(point.position.Y, 0)
			expect.truthy(vectorNear(point.facing, Vector3.new(0, 0, 1)))
			xs[point.position.X] = true
		end
		expect.truthy(xs[-6] and xs[6])
	end)

	t.test("audio zones follow §7.7 with the bigger §17.6 squeeze zone; the highest priority wins", function()
		local byId: { [string]: any } = {}
		for _, zone in WorldLayout.AudioZones do
			byId[zone.zoneId] = zone
		end
		expect.truthy(vectorNear(byId.lobby.position, Vector3.new(0, 20, 0)))
		expect.truthy(vectorNear(byId.lobby.size, Vector3.new(128, 40, 112)))
		expect.truthy(vectorNear(byId.squeeze.position, Vector3.new(-41, 15, 21)))
		expect.truthy(vectorNear(byId.squeeze.size, Vector3.new(38, 30, 62)))
		-- §18.8: (-42, 15, -37) / (36, 30, 34) grew to X -60..-16 so it covers the throw box too.
		expect.truthy(vectorNear(byId.practice.position, Vector3.new(-38, 15, -37)))
		expect.truthy(vectorNear(byId.practice.size, Vector3.new(44, 30, 34)))
		expect.equal(byId.lobby.priority, 1)
		expect.equal(byId.squeeze.musicMul, 0.8)
		expect.equal(byId.practice.musicMul, 0.6)
		expect.equal(WorldLayout.audioZoneAt(Vector3.new(-36, 3, 0)).zoneId, "squeeze")
		expect.equal(WorldLayout.audioZoneAt(Vector3.new(-33, 3, 37)).zoneId, "squeeze") -- the Grip Gym
		expect.equal(WorldLayout.audioZoneAt(Vector3.new(-40, 3, -37)).zoneId, "practice") -- the lanes (X -60..-24)
		expect.equal(WorldLayout.audioZoneAt(Vector3.new(0, 3, 40)).zoneId, "lobby")
		expect.equal(WorldLayout.audioZoneAt(Vector3.new(400, 3, 0)), nil)
		local arena = WorldLayout.Arena.audioZone
		expect.equal(arena.zoneId, "arena")
		expect.equal(arena.priority, 3)
		expect.truthy(vectorNear(arena.size, Vector3.new(120, 60, 152)))
	end)

	t.test("TagCounts agree with the data (§7.7, §17.6)", function()
		local counts = WorldLayout.TagCounts
		expect.equal(counts.SD_SqueezeStation, #WorldLayout.Stations)
		expect.equal(counts.SD_PracticeTarget, #WorldLayout.PracticeRange.targets)
		expect.equal(counts.SD_CollectionPedestal, #WorldLayout.Collection.pedestals)
		expect.equal(counts.SD_ReturnPoint, #WorldLayout.ReturnPoints)
		expect.equal(counts.SD_GiantPad, #WorldLayout.GiantPadKeys)
		expect.equal(counts.SD_GripGate, #WorldLayout.GiantPadKeys)
		expect.equal(counts.SD_GripSign, #WorldLayout.GiantPadKeys)
		expect.equal(#WorldLayout.Lobby.Boundaries, 4)
		expect.equal(counts.SD_Boundary, 4)
		expect.equal(counts.SD_AudioZone, 3)
		expect.equal(counts.SD_AudioZone, #WorldLayout.AudioZones)
		-- §18.5.1 A8: the lollipops, both gift boxes and the statue.
		expect.equal(counts.SD_Ambient, #WorldLayout.Props.lollipops.positions + 3)
		expect.equal(counts.SD_Ambient, 7)
		expect.equal(WorldLayout.Tags.Ambient, "SD_Ambient")
		expect.equal(WorldLayout.Attributes.AmbientKind, "SD_AmbientKind")
	end)

	-- Feel pass (§18.8) -------------------------------------------------------------------------------------------

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
		-- The lanes still belong to it, and its priority, music and ambience are unchanged.
		expect.equal(WorldLayout.audioZoneAt(Vector3.new(-58, 3, -37)).zoneId, "practice")
		expect.equal(practice.priority, 2)
		expect.equal(practice.musicKey, "music.lobby")
		expect.equal(practice.ambienceKey, "amb.lobby")
	end)

	-- First person (spec 2026-10-10 §3.5): in the throw box F, E and ButtonX are PracticeSqueeze's. The lobby Squeeze
	-- there only ever says "not at a pad", because no prompt and no squeeze station reaches into the box.
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
		expect.equal(#prompts, 14)
		for _, prompt in prompts do
			local gap = (prompt.position - closest(prompt.position)).Magnitude
			if gap <= prompt.maxDistance then
				error(`{prompt.actionKey} at {prompt.position} reaches the throw box ({gap} studs)`)
			end
		end
		local Squeeze = t.requireShared("Config").Squeeze
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
			{ heights = { 2, 4, 6 }, thickness = 0.5, proud = 0.1, insetX = 0.02 }
		)
		-- Every stripe edge lies on a 0.25 + 0.5k row of the jelly skin's wall grid.
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
		local station, distance = WorldLayout.nearestStation(Vector3.new(-26, 3.3, 14), 10)
		expect.equal(station.id, "squeeze_06")
		expect.truthy(distance < 4)
		local none, far = WorldLayout.nearestStation(Vector3.new(0, 3, 40), 10)
		expect.equal(none, nil)
		expect.equal(far, math.huge)

		local margin, above = Config.Grip.Afk.padMargin, Config.Grip.Afk.heightAbove
		expect.equal(WorldLayout.stationUnder(Vector3.new(-26, 3.3, 14), margin, above).id, "squeeze_06")
		expect.equal(WorldLayout.stationUnder(Vector3.new(-26, 3.3, 14 + 4 + margin + 0.5), margin, above), nil)
		expect.equal(WorldLayout.stationUnder(Vector3.new(-33, 4, 37), margin, above).id, "squeeze_07")
		expect.equal(WorldLayout.stationUnder(Vector3.new(-33 + 4.9, 4, 37 - 4.9), margin, above).id, "squeeze_07")
		expect.equal(WorldLayout.stationUnder(Vector3.new(-33, COLLISION_TOP + above + 0.5, 37), margin, above), nil)
		expect.equal(WorldLayout.stationUnder(Vector3.new(-33, 0.5, 37), margin, above), nil)
		expect.equal(WorldLayout.stationUnder(Vector3.new(38, 4, 38), margin, above).id, "squeeze_09")
		expect.equal(WorldLayout.stationUnder(Vector3.new(0, 3, 40), margin, above), nil)
	end)

	t.test("boxBounds rotates the quest board; contains and boundsOverlap are inclusive / strict", function()
		local low, high = WorldLayout.boxBounds(WorldLayout.QuestBoard.board)
		-- 9 wide, yawed 20° from facing +X: ≈ 3.3 studs deep on X, ≈ 8.7 on Z.
		expect.near(high.X - low.X, 9 * math.sin(math.rad(20)) + 0.6 * math.cos(math.rad(20)), 1e-3)
		expect.near(high.Z - low.Z, 9 * math.cos(math.rad(20)) + 0.6 * math.sin(math.rad(20)), 1e-3)
		local cf = WorldLayout.boxCFrame(WorldLayout.QuestBoard.board)
		expect.truthy(cf.LookVector.X > 0.9 and cf.LookVector.Z > 0.3)
		local volume = { position = Vector3.zero, size = Vector3.new(2, 2, 2) }
		expect.truthy(WorldLayout.contains(volume, Vector3.new(1, 1, 1)))
		expect.falsy(WorldLayout.contains(volume, Vector3.new(1.01, 0, 0)))
		local one = Vector3.new(1, 1, 1)
		expect.falsy(WorldLayout.boundsOverlap(-one, one, Vector3.new(1, -1, -1), Vector3.new(3, 1, 1)))
		expect.truthy(WorldLayout.boundsOverlap(-one, one, Vector3.new(0.9, -1, -1), Vector3.new(3, 1, 1)))
	end)

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
		expect.equal(WorldLayout.GiantPads.jelly.collisionTop, COLLISION_TOP)
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
				-- Open pad-to-pad lane X -6..6 (touching its edge is fine).
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
			-- 76 wide (§7.8 says 72): they meet the side walls' inner faces at X ±38, so nobody walks around them.
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

	-- The apron is decor (no collision), so the strip between each rail and its barrier wall needs its own floor: a
	-- player who hops a 3-tall rail must land on floor, not fall into the void.
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
		-- Floor pieces never overlap each other (touching faces only).
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
