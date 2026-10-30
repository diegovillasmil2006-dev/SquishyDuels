--!strict
-- HighwayAccessService_Test: ServerScriptService.Server.Services.HighwayAccessService (access2, owner 2026-10-18
-- "Both": the bridge to walk to the highway's launch deck, plus a quick HIGHWAY button; the owner 2026-10-18: no
-- launch spots, the deck is one open area where everybody throws). Server only (ServerStorage.UnitTest). Edit mode:
-- init() is never called; every dependency is a fake (useDeps), the deck's area comes from a HighwayBuilder build.
-- Contract:
--   * GoHighway() takes no argument (no remote names a place, a player or a spot), a RemoteFunction limited by
--     Config.Net (a trip every 2 s, a burst of 2, one at a time);
--   * refusals in PenBuySpot's order, nothing moved, charged = false: data.notReady, then the decision
--     (highway.noCharacter, highway.closed while the world has no deck), then highway.paused (the server closing or
--     a restart pending), highway.inDuel (a duel or a match: SD_DuelPhase), highway.inQueue (the 1v1 queue or a match
--     queue); every code has a text; never a "busy" refusal (Check 2026-10-18 item 2: "the button never says busy");
--   * the deck streams in first, then every check runs again (a duel, a queue, a pause or a death meanwhile stops the
--     trip), and the pick and the move follow with no yield between (two trips at once never take one place);
--   * a trip: the character goes to the first free point of the deck's top nearest its middle (a box a character
--     tall above the floor holds no colliding part but its own), standing on the floor under that point (never into
--     a part), facing down the lane; a deck with no free point sends it onto the bridge's walk beside the deck; the
--     reply is ok {charged = false, savePending = false};
--   * the points: a grid inside the deck's top with a margin from its edges, nearest the middle first; on the deck as
--     HighwayBuilder builds it (the 30 x 15 top at y 2.5, lane-local (0, 2.5, 34.25), LK:158-164) they all lie inside
--     the top, off its trim ring; the bridge's points run down its walk's middle from the deck end.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local ServerStorage = game:GetService("ServerStorage")

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local TOLERANCE = 1e-3

return function(t: Context)
	local expect = t.expect
	local Service = t.requireServer("Services/HighwayAccessService")
	local NetService = t.requireServer("Services/NetService")
	local Config = t.requireShared("Config")
	local Remotes = t.requireShared("Remotes")
	local Strings = t.requireShared("Strings")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local FakeClock = t.requireFake("FakeClock")

	-- A deck top 30 x 15 centred on (0, 2.5, -265.75), -Z down the lane (the built deck's, see the last case).
	local DECK = { frame = CFrame.new(0, 2.5, -265.75), size = Vector2.new(30, 15) }
	local STAND = 3.1 -- the fake character's stand height (the root's height over its feet)

	type World = {
		player: any,
		character: any,
		status: string,
		phase: string,
		queue: string,
		matchQueue: string?,
		closing: boolean,
		restart: boolean,
		hasCharacter: boolean,
		deck: any,
		blocked: (cf: CFrame) -> boolean,
		floor: (point: Vector3) -> number?,
		boxes: { { cf: CFrame, size: Vector3 } },
		streams: { Vector3 },
		during: () -> (), -- what happens in the world while the deck streams in (the stream yields)
		moves: { CFrame },
	}

	local function fresh(): World
		local w: World = {
			player = { UserId = 7 },
			character = { Name = "Character" },
			status = "ready",
			phase = "",
			queue = "Idle",
			matchQueue = nil,
			closing = false,
			restart = false,
			hasCharacter = true,
			deck = DECK,
			blocked = function()
				return false
			end,
			floor = function()
				return 2.5
			end,
			boxes = {},
			streams = {},
			during = function() end,
			moves = {},
		}
		Service.useDeps({
			statusOf = function()
				return w.status
			end,
			duelPhaseOf = function()
				return w.phase
			end,
			queueState = function()
				return w.queue
			end,
			matchQueued = function()
				return w.matchQueue
			end,
			isClosing = function()
				return w.closing
			end,
			isRestartPending = function()
				return w.restart
			end,
			character = function(): (any, number?)
				if not w.hasCharacter then
					return nil, nil
				end
				return w.character, STAND
			end,
			deck = function()
				return w.deck
			end,
			floorAt = function(point: Vector3, character: any): number?
				expect.equal(character, w.character)
				return w.floor(point)
			end,
			isClear = function(cf: CFrame, size: Vector3, character: any): boolean
				expect.equal(character, w.character)
				table.insert(w.boxes, { cf = cf, size = size })
				return not w.blocked(cf)
			end,
			stream = function(player: any, at: Vector3)
				expect.equal(player, w.player)
				table.insert(w.streams, at)
				w.during()
			end,
			move = function(character: any, cf: CFrame)
				expect.equal(character, w.character)
				table.insert(w.moves, cf)
			end,
		})
		return w
	end

	local function refused(w: World, code: string)
		local reply = Service.go(w.player)
		expect.equal(reply.ok, false)
		expect.equal(reply.reason, code)
		expect.equal(reply.charged, false)
		expect.equal(#w.moves, 0)
	end

	t.test("GoHighway takes no argument; a RemoteFunction, a trip every 2 s (burst 2), one at a time", function()
		local spec = Remotes.SPEC.GoHighway
		expect.equal(spec.kind, "RemoteFunction")
		expect.equal(spec.dir, "c2s")
		expect.deepEqual(spec.args, {})
		expect.deepEqual(Config.Net.Remotes.GoHighway, { rate = 0.5, burst = 2, oneInFlight = true })
		local clock = FakeClock.new(100)
		local guard = NetService.newGuard({ clock = clock.now })
		local player = { UserId = 9 }
		expect.equal(guard:check(player, "GoHighway", 0), "ok")
		expect.equal(guard:check(player, "GoHighway", 0), "ok")
		expect.equal(guard:check(player, "GoHighway", 0), "rateLimited")
		expect.equal(guard:check({ UserId = 10 }, "GoHighway", 1, "spot 3"), "badArgCount") -- it names nothing
	end)

	t.test(
		"refusals in PenBuySpot's order, nothing moved: not ready, the decision, paused, in a duel, queued",
		function()
			local w = fresh()
			-- what Diego's HIGHWAY portal asks before its movie (PortalService), then the same go()
			local function refusedBoth(world: World, code: string)
				expect.equal(Service.refusal(world.player), code)
				refused(world, code)
			end
			w.status, w.hasCharacter, w.deck, w.closing, w.phase, w.queue =
				"loading", false, nil, true, "Active", "Searching"
			refusedBoth(w, "data.notReady")
			w.status = "ready"
			refusedBoth(w, "highway.noCharacter")
			w.hasCharacter = true
			refusedBoth(w, "highway.closed") -- the place has no SD_Highway deck
			w.deck = DECK
			refusedBoth(w, "highway.paused") -- the server is closing
			w.closing, w.restart = false, true
			refusedBoth(w, "highway.paused") -- a restart is pending
			w.restart = false
			refusedBoth(w, "highway.inDuel") -- a duel or a match
			w.phase = ""
			refusedBoth(w, "highway.inQueue") -- the 1v1 queue (Searching, then Matched)
			w.queue = "Matched"
			refusedBoth(w, "highway.inQueue")
			w.queue, w.matchQueue = "Idle", "ffa"
			refusedBoth(w, "highway.inQueue") -- a Free for All / Team Deathmatch queue
			w.matchQueue = nil
			expect.equal(#w.streams, 0) -- nothing streams in for a refused trip
			expect.equal(Service.refusal(w.player), nil)
			local reply = Service.go(w.player)
			expect.equal(reply.ok, true)
			expect.deepEqual(reply.data, { charged = false, savePending = false })
			expect.equal(#w.moves, 1)
			-- The deck's middle streamed in once, before the move.
			expect.equal(#w.streams, 1)
			expect.near((w.streams[1] - DECK.frame.Position).Magnitude, 0, TOLERANCE)
			Service.useDeps(nil)
		end
	)

	t.test("every check runs again once the deck has streamed in: a change meanwhile stops the trip", function()
		local changes: { { code: string, change: (w: World) -> () } } = {
			{
				code = "highway.noCharacter", -- died or respawned on the way
				change = function(w: World)
					w.hasCharacter = false
				end,
			},
			{
				code = "highway.paused",
				change = function(w: World)
					w.closing = true
				end,
			},
			{
				code = "highway.inDuel", -- matched and put on an arena pad meanwhile
				change = function(w: World)
					w.phase = "Positioning"
				end,
			},
			{
				code = "highway.inQueue", -- joined the 1v1 queue and got matched meanwhile
				change = function(w: World)
					w.queue = "Matched"
				end,
			},
			{
				code = "highway.inQueue", -- joined a match queue meanwhile
				change = function(w: World)
					w.matchQueue = "tdm"
				end,
			},
		}
		for _, case in changes do
			local w = fresh()
			w.during = function()
				case.change(w)
			end
			refused(w, case.code)
			expect.equal(#w.streams, 1)
		end
		Service.useDeps(nil)
	end)

	t.test("two trips at once never land on one place: the second picks after the first has moved", function()
		local w = fresh()
		local other = { player = { UserId = 8 }, character = { Name = "Other" } }
		local at: { [any]: Vector3 } = {} -- where each character stands once moved
		local function whose(player: any): any
			return if player == other.player then other.character else w.character
		end
		local nested = false
		Service.useDeps({
			statusOf = function()
				return "ready"
			end,
			duelPhaseOf = function()
				return ""
			end,
			queueState = function()
				return "Idle"
			end,
			matchQueued = function()
				return nil
			end,
			isClosing = function()
				return false
			end,
			isRestartPending = function()
				return false
			end,
			character = function(player: any): (any, number?)
				return whose(player), STAND
			end,
			deck = function()
				return DECK
			end,
			floorAt = function(): number?
				return 2.5
			end,
			isClear = function(cf: CFrame, size: Vector3, character: any): boolean
				for who, p in at do
					local d = p - cf.Position
					if who ~= character and math.abs(d.X) < size.X and math.abs(d.Z) < size.Z then
						return false
					end
				end
				return true
			end,
			-- While the first trip's deck streams in, the other player's whole trip happens.
			stream = function(player: any)
				if player == w.player and not nested then
					nested = true
					expect.equal(Service.go(other.player).ok, true)
				end
			end,
			move = function(character: any, cf: CFrame)
				at[character] = cf.Position
			end,
		})
		expect.equal(Service.go(w.player).ok, true)
		local mine, theirs = at[w.character] :: Vector3?, at[other.character] :: Vector3?
		if mine == nil or theirs == nil then
			error("a trip did not move its character")
		end
		expect.truthy(Vector2.new(mine.X - theirs.X, mine.Z - theirs.Z).Magnitude >= 3 - TOLERANCE)
		Service.useDeps(nil)
	end)

	t.test("every refusal has a text", function()
		for _, code in
			{
				"data.notReady",
				"highway.noCharacter",
				"highway.closed",
				"highway.paused",
				"highway.inDuel",
				"highway.inQueue",
			}
		do
			expect.truthy(Strings.resolve("reason." .. code) ~= nil)
			expect.truthy(Strings.reasonText(code) == Strings.resolve("reason." .. code))
		end
	end)

	t.test(
		"a trip: the first clear point nearest the deck's middle, standing on its floor, facing down the lane",
		function()
			local w = fresh()
			local reply = Service.go(w.player)
			expect.equal(reply.ok, true)
			local cf = w.moves[1]
			local first = Service.points(DECK)[1]
			-- Feet on the floor under the point (the fake's 2.5), the root STAND higher; facing the deck frame's -Z.
			expect.near((cf.Position - Vector3.new(first.X, 2.5 + STAND, first.Z)).Magnitude, 0, TOLERANCE)
			expect.near(cf.LookVector:Dot(DECK.frame.LookVector), 1, TOLERANCE)
			expect.near(cf.UpVector.Y, 1, TOLERANCE)
			-- The clear box: at least a character's size, from just over the floor up.
			local box = w.boxes[1]
			expect.truthy(box.size.X >= 2 and box.size.Z >= 2 and box.size.Y >= 5)
			local bottom = box.cf.Position.Y - box.size.Y / 2
			expect.truthy(bottom > 2.5 and bottom < 2.5 + 0.5)
			expect.near(box.cf.Position.X, first.X, TOLERANCE)
			expect.near(box.cf.Position.Z, first.Z, TOLERANCE)
			Service.useDeps(nil)
		end
	)

	t.test(
		"taken points are passed over; a deck with none free sends the trip onto the bridge, never refused",
		function()
			local w = fresh()
			local points = Service.points(DECK)
			local taken = 0
			w.blocked = function(cf: CFrame): boolean
				-- Everything but the last point is taken (other players, a launcher).
				local last = points[#points]
				local free = math.abs(cf.Position.X - last.X) < TOLERANCE
					and math.abs(cf.Position.Z - last.Z) < TOLERANCE
				if not free then
					taken += 1
				end
				return not free
			end
			local reply = Service.go(w.player)
			expect.equal(reply.ok, true)
			expect.equal(taken, #points - 1)
			expect.near(w.moves[1].Position.X, points[#points].X, TOLERANCE)
			expect.near(w.moves[1].Position.Z, points[#points].Z, TOLERANCE)
			-- A floor too high or missing under a point (a launcher on it, a hole) is passed over too.
			local y = fresh()
			y.floor = function(point: Vector3): number?
				if math.abs(point.X - points[1].X) < TOLERANCE and math.abs(point.Z - points[1].Z) < TOLERANCE then
					return 2.5 + 3 -- something tall stands there
				elseif math.abs(point.X - points[2].X) < TOLERANCE and math.abs(point.Z - points[2].Z) < TOLERANCE then
					return nil
				end
				return 2.9 -- a low launch spot's top: still the deck's floor
			end
			expect.equal(Service.go(y.player).ok, true)
			expect.near(y.moves[1].Position.X, points[3].X, TOLERANCE)
			expect.near(y.moves[1].Position.Y, 2.9 + STAND, TOLERANCE)
			-- No free point on the deck (a crowd standing between the points, launchers): the first free point down the
			-- bridge's walk from the deck end, on the walk's own floor, facing down the lane. Never "busy".
			local onDeck = function(cf: CFrame): boolean
				return math.abs(cf.Position.Z - DECK.frame.Position.Z) <= DECK.size.Y / 2
			end
			local bridge = Service.bridgePoints()
			local z = fresh()
			z.floor = function(point: Vector3): number?
				return point.Y -- every point's own floor: the deck's top, the bridge walk's top
			end
			z.blocked = function(cf: CFrame): boolean
				-- The deck is full, and someone stands on the bridge's first point too.
				local first = Vector2.new(cf.Position.X - bridge[1].X, cf.Position.Z - bridge[1].Z)
				return onDeck(cf) or first.Magnitude < TOLERANCE
			end
			expect.equal(Service.go(z.player).ok, true)
			expect.near((z.moves[1].Position - (bridge[2] + Vector3.new(0, STAND, 0))).Magnitude, 0, TOLERANCE)
			expect.near(z.moves[1].LookVector:Dot(DECK.frame.LookVector), 1, TOLERANCE)
			-- Everything taken (more bodies than a 10-player server holds): still a trip, to the bridge's first point.
			local all = fresh()
			all.blocked = function()
				return true
			end
			expect.equal(Service.go(all.player).ok, true)
			expect.near((all.moves[1].Position - (bridge[1] + Vector3.new(0, STAND, 0))).Magnitude, 0, TOLERANCE)
			Service.useDeps(nil)
		end
	)

	t.test("a crowd standing between the points: the gap left on the deck is still found", function()
		-- 6 bodies 4 wide with the arms, 5 tall, 1 deep at x -9 / 0 / 9, z -3 / 3 on the deck (the verifier's crowd).
		local bodies: { { at: Vector3, half: Vector3 } } = {}
		for _, x in { -9, 0, 9 } do
			for _, z in { -3, 3 } do
				table.insert(bodies, { at = DECK.frame * Vector3.new(x, 2.5, z), half = Vector3.new(2, 2.5, 0.5) })
			end
		end
		local function overlaps(cf: CFrame, size: Vector3): boolean
			local c, h = cf.Position, size / 2
			for _, b in bodies do
				local d = b.at - c
				if
					math.abs(d.X) < b.half.X + h.X
					and math.abs(d.Y) < b.half.Y + h.Y
					and math.abs(d.Z) < b.half.Z + h.Z
				then
					return true
				end
			end
			return false
		end
		local w = fresh()
		w.floor = function(point: Vector3): number?
			-- The ray down from over the point meets a body standing there first.
			return if overlaps(CFrame.new(point + Vector3.new(0, 4, 0)), Vector3.new(0.01, 8, 0.01)) then 7.5 else 2.5
		end
		w.blocked = function(cf: CFrame): boolean
			return overlaps(cf, Vector3.new(3, 5.5, 3))
		end
		expect.equal(Service.go(w.player).ok, true)
		local p = DECK.frame:PointToObjectSpace(w.moves[1].Position)
		expect.truthy(math.abs(p.X) <= DECK.size.X / 2 and math.abs(p.Z) <= DECK.size.Y / 2) -- on the deck
		expect.falsy(overlaps(CFrame.new(w.moves[1].Position), Vector3.new(2, 5, 1))) -- inside nobody
		Service.useDeps(nil)
	end)

	t.test(
		"bridgePoints: down the middle of the bridge's walk from the deck end, on its top, deck end first",
		function()
			local spec = WorldLayout.Lobby.bridge
			local deckEnd = Vector3.new(spec.x, spec.toTop, spec.toZ)
			local islandEnd = Vector3.new(spec.x, spec.fromTop, spec.fromZ)
			local length = (islandEnd - deckEnd).Magnitude
			local points = Service.bridgePoints()
			expect.truthy(#points >= 10)
			local last = 0
			for _, point in points do
				local s = (point - deckEnd).Magnitude
				-- On the walk's top centre line, a body's half-depth (1.5) or more inside either end.
				expect.near((deckEnd + (islandEnd - deckEnd).Unit * s - point).Magnitude, 0, TOLERANCE)
				expect.truthy(s >= 1.5 - TOLERANCE and s <= length - 1.5 + TOLERANCE)
				expect.truthy(s > last)
				last = s
			end
		end
	)

	t.test("points: a grid inside the deck's top, 2 studs in from its edges, nearest the middle first", function()
		local points = Service.points(DECK)
		expect.truthy(#points >= 20) -- far more than a server's 10 players
		local seen: { [string]: boolean } = {}
		local last = -1
		for _, point in points do
			local p = DECK.frame:PointToObjectSpace(point)
			expect.near(p.Y, 0, TOLERANCE) -- on the top's plane
			expect.truthy(math.abs(p.X) <= DECK.size.X / 2 - 2 + TOLERANCE)
			expect.truthy(math.abs(p.Z) <= DECK.size.Y / 2 - 2 + TOLERANCE)
			local d = Vector2.new(p.X, p.Z).Magnitude
			expect.truthy(d >= last - TOLERANCE)
			last = d
			local key = string.format("%.2f,%.2f", p.X, p.Z)
			expect.falsy(seen[key])
			seen[key] = true
		end
		-- Neighbours 1.5 studs apart (half a body's room, so a gap between players is found); the clear box, not the
		-- spacing, keeps bodies apart.
		for i = 1, #points do
			for j = i + 1, #points do
				expect.truthy((points[i] - points[j]).Magnitude >= 1.5 - TOLERANCE)
			end
		end
		expect.deepEqual(Service.points(DECK), points) -- deterministic
	end)

	t.test(
		"deckArea: the deck's top as HighwayBuilder builds it (30 x 15 at y 2.5, LK:158-164), -Z down the lane",
		function()
			local source = ServerStorage:FindFirstChild("SDTools")
			if source == nil then
				error("ServerStorage.SDTools not found")
			end
			local tools = source:Clone()
			local builders = tools:FindFirstChild("Builders") :: Instance
			local HighwayBuilder = dynamicRequire(builders:FindFirstChild("HighwayBuilder") :: ModuleScript)
			local Cleanup = t.requireShared("Util/Cleanup")
			local scratch = Cleanup.new()
			local result = HighwayBuilder.build({ scratch = scratch, Shared = t.Shared })
			scratch:clean()
			if not result.ok then
				tools:Destroy()
				error("HighwayBuilder.build failed: " .. tostring(result.error))
			end
			local H = WorldLayout.Highway
			local area = Service.deckArea(result.root:FindFirstChild("Deck") :: Instance, H.origin)
			expect.truthy(area ~= nil)
			local centre = H.origin * (H.deck.platform + Vector3.new(0, 2, -1.25)) -- the top's middle (LK:159)
			expect.near((area.frame.Position - centre).Magnitude, 0, TOLERANCE)
			expect.near(area.frame.LookVector:Dot(H.origin.LookVector), 1, TOLERANCE)
			expect.near(area.size.X, 30, TOLERANCE)
			expect.near(area.size.Y, 15, TOLERANCE)
			-- Every point stands on the top, inside the trim ring (0.6 wide, 0.1 over the top at the rim).
			for _, point in Service.points(area) do
				local p = area.frame:PointToObjectSpace(point)
				expect.truthy(math.abs(p.X) <= 15 - 0.6 - 1 and math.abs(p.Z) <= 7.5 - 0.6 - 1)
			end
			expect.equal(Service.deckArea(Instance.new("Model"), H.origin), nil) -- no deck_top parts: no deck
			result.root:Destroy()
			tools:Destroy()
		end
	)
end
