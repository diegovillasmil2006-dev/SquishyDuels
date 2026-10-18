--!strict
-- HighwayService_Test: unit tests for ServerScriptService.Server.Services.HighwayService (pens3 phase 13: the throw for
-- distance; work/pens3/PLAN.md "PHASE 13" with the owner's corrections, work/pens3/p13v2/NOTES.md) with injected fakes:
-- plain-table players and profiles, a fake clock and server clock, recorded grants, Grip, gifts, saves and board
-- writes. Server only (ServerStorage.UnitTest).
-- Contract:
--   * HighwayThrow(clientTime "serverTime", fastSeconds "integer") (RF; p13v3: the client's speed report, handed to
--     the auto-clicker check's speed rule); its Config.Net entry {rate = 14, burst = 30} (the
--     THROW presses: the client sends them all, so the auto-clicker check sees the rhythm; one throw in flight is the
--     service's own);
--   * the refusal order (PenBuySpot's shape): (1) clientTime not a finite number -> net.invalid; (2) the auto-clicker
--     check (AutoClickService.checkThrow), which sees every arrival, even during a flight -> its reason; (3) no READY
--     profile -> data.notReady; (4) the decision: a throw in flight -> highway.inFlight; the server-side root not in
--     the throw area (owner 2026-10-18: one open area, no spots) -> highway.notInArea; (5) a pending failed save,
--     closing or a restart -> highway.paused; (6) SD_DuelPhase set -> inventory.lockedInDuel. Every refusal carries
--     charged = false and writes nothing;
--   * a throw: power = HighwayMath.power(Grip Lv), the landing and its flight from HighwayMath; it pays in full every
--     time (owner 2026-10-16: no limits; no time share, no daily cap): landingCoins(SV, studs) Coins ("highway"; p13v3,
--     owner 2026-10-18: by distance, farther pays more) and
--     GripService.addFromHighway(pay.grip); best and biome rise (only up), with a "soon" save and the highway field
--     sent; the next throw waits for the landing (one in flight, less the grace);
--   * the biome gifts once each, in the throw that first reaches the biome (a throw past two biomes gives both);
--   * the Food Bag: every 150 s of flight time of paid throws, 50 SV of the weakest placed squishy's band food into
--     profile.food (sent);
--   * the launch board (owner 2026-10-15): the last 3 throws of anyone in the server, newest first, and the server
--     best, written by the server; start() writes the empty board.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local HighwayService = t.requireServer("Services/HighwayService")
	local Config = t.requireShared("Config")
	local Remotes = t.requireShared("Remotes")
	local HighwayMath = t.requireShared("HighwayMath")
	local PenMath = t.requireShared("PenMath")
	local Strings = t.requireShared("Strings")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local Format = t.requireShared("Util/Format")
	local H = Config.Economy.Highway
	local SERVER_START = 1_800_000_000.5
	-- A world position in the middle of the throw area (a standing character's root).
	local ON_DECK = (WorldLayout.Highway.origin * CFrame.new(WorldLayout.Highway.throwArea.position)).Position

	type World = {
		a: any,
		b: any,
		profiles: { [any]: any },
		status: { [any]: string },
		phase: { [any]: string },
		roots: { [any]: Vector3? },
		levels: { [any]: number },
		clock: number,
		serverNow: number,
		savePending: boolean,
		closing: boolean,
		restart: boolean,
		cheat: string?, -- what checkThrow answers
		checks: number,
		reports: { any }, -- p13v3: the speed report each checkThrow was handed
		grants: { { player: any, amount: number, reason: string } },
		grip: { { player: any, squeezes: number } },
		squishies: { { player: any, kind: string } },
		soonSaves: { any },
		dirty: { string },
		writes: number,
		boards: { { [string]: string } },
	}

	local function noFood(): any
		local food = {}
		for _, def in Config.Economy.Food.foods do
			food[def.id] = 0
		end
		return food
	end

	local function newProfile(): any
		return {
			coins = 0,
			pen = {
				spots = 3,
				nextId = 2,
				items = { { id = 1, kind = "kitty_bread", form = 0, level = 1, coat = 0, slot = 1, locked = false } },
				shelfRows = 1,
				top = false,
			},
			food = noFood(),
			highway = { best = 0, biome = 1 },
		}
	end

	local function fresh(): World
		local w: World = {
			a = { UserId = 1, DisplayName = "Kai" },
			b = { UserId = 2, DisplayName = "Mia" },
			profiles = {},
			status = {},
			phase = {},
			roots = {},
			levels = {},
			clock = 100,
			serverNow = SERVER_START,
			savePending = false,
			closing = false,
			restart = false,
			cheat = nil,
			checks = 0,
			reports = {},
			grants = {},
			grip = {},
			squishies = {},
			soonSaves = {},
			dirty = {},
			writes = 0,
			boards = {},
		}
		HighwayService.reset()
		HighwayService.useDeps({
			statusOf = function(player: any): string
				return w.status[player] or "loading"
			end,
			profileOf = function(player: any): any
				return w.profiles[player]
			end,
			mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
				if w.status[player] ~= "ready" then
					return false, "data.notReady"
				end
				w.writes += 1
				return true, fn(w.profiles[player])
			end,
			savePending = function(): boolean
				return w.savePending
			end,
			isClosing = function(): boolean
				return w.closing
			end,
			isRestartPending = function(): boolean
				return w.restart
			end,
			duelPhaseOf = function(player: any): string
				return w.phase[player] or ""
			end,
			clock = function(): number
				return w.clock
			end,
			serverNow = function(): number
				return w.serverNow
			end,
			rootOf = function(player: any): Vector3?
				return w.roots[player]
			end,
			gripLevel = function(player: any): number
				return w.levels[player] or 1
			end,
			grantCoins = function(player: any, amount: number, reason: string): number
				w.profiles[player].coins += amount
				table.insert(w.grants, { player = player, amount = amount, reason = reason })
				return amount
			end,
			addGrip = function(player: any, squeezes: number): number
				table.insert(w.grip, { player = player, squeezes = squeezes })
				return squeezes * 10
			end,
			grantSquishy = function(player: any, kind: string): boolean
				table.insert(w.squishies, { player = player, kind = kind })
				return true
			end,
			checkThrow = function(_player: any, _now: number, fastSeconds: number?): string?
				w.checks += 1
				table.insert(w.reports, fastSeconds or "none")
				return w.cheat
			end,
			requestSave = function(player: any, reason: string)
				expect.equal(reason, "soon")
				table.insert(w.soonSaves, player)
			end,
			markDirty = function(_player: any, field: string)
				table.insert(w.dirty, field)
			end,
			nameOf = function(player: any): string
				return player.DisplayName
			end,
			writeBoard = function(lines: { [string]: string })
				table.insert(w.boards, table.clone(lines))
			end,
		})
		for _, player in { w.a, w.b } do
			w.profiles[player] = newProfile()
			w.status[player] = "ready"
			w.roots[player] = ON_DECK
			HighwayService.playerAdded(player)
		end
		return w
	end

	local function finish()
		HighwayService.reset()
		HighwayService.useDeps(nil)
	end

	local function expectRefused(reply: any, reason: string)
		expect.equal(reply.ok, false)
		expect.equal(reply.reason, reason)
		expect.equal(reply.charged, false)
	end

	-- Past the player's flight (the next throw may go).
	local function land(w: World, studs: number)
		local seconds = HighwayMath.flight(studs).total
		w.clock += seconds
		w.serverNow += seconds
	end

	t.test(
		"HighwayThrow takes a serverTime and a speed report; its Net entry holds the client's THROW presses",
		function()
			local spec = Remotes.SPEC.HighwayThrow
			expect.equal(spec.kind, "RemoteFunction")
			expect.equal(spec.dir, "c2s")
			expect.deepEqual(
				spec.args,
				{ { name = "clientTime", type = "serverTime" }, { name = "fastSeconds", type = "integer" } }
			)
			expect.deepEqual(Config.Net.Remotes.HighwayThrow, { rate = 14, burst = 30 })
			expect.truthy(table.find(Config.Economy.CoinReasons, "highway") ~= nil)
		end
	)

	t.test("a throw at Grip Lv 1: 21 studs pay 0.5 SV a stud, 60 squeezes of Grip, best saved, the reply", function()
		local w = fresh()
		local reply = HighwayService.throw(w.a, SERVER_START)
		expect.equal(reply.ok, true)
		local plan = HighwayMath.flight(21)
		expect.deepEqual(reply.data, {
			studs = 21,
			biome = 1,
			power = 2,
			flight = plan.total,
			landsAt = SERVER_START + plan.total,
			coins = 105, -- 0.5 x 21 studs x the least squeeze value (10)
			grip = 600, -- the fake: 60 squeezes x 10
			best = 21,
			newBest = true,
			reached = nil,
			gifts = {},
			food = nil,
			charged = false,
			savePending = false,
		})
		expect.deepEqual(w.grants, { { player = w.a, amount = 105, reason = "highway" } })
		expect.deepEqual(w.grip, { { player = w.a, squeezes = 60 } })
		expect.deepEqual(w.profiles[w.a].highway, { best = 21, biome = 1 })
		expect.deepEqual(w.soonSaves, { w.a })
		expect.truthy(table.find(w.dirty, "highway") ~= nil)
		expect.equal(w.checks, 1)
		finish()
	end)

	t.test(
		"p13v3: the speed report every arrival carries reaches the auto-clicker check, a refused one's too",
		function()
			local w = fresh()
			expect.equal(HighwayService.throw(w.a, SERVER_START, 4).ok, true)
			expectRefused(HighwayService.throw(w.a, SERVER_START, 2), "highway.inFlight")
			expectRefused(HighwayService.throw(w.a, 0 / 0, 9), "net.invalid") -- a broken request never reaches it
			w.cheat = "highway.superFast"
			expectRefused(HighwayService.throw(w.a, SERVER_START, 30), "highway.superFast") -- the speed rule's catch
			expect.deepEqual(w.reports, { 4, 2, 30 })
			-- The handler init registers hands it on too (captured from NetService.onInvoke).
			local NetService: any = t.requireServer("Services/NetService")
			local real = NetService.onInvoke
			local handlers: { [string]: any } = {}
			NetService.onInvoke = function(name: string, handler: any): () -> ()
				handlers[name] = handler
				return function() end
			end
			local ok, why = pcall(HighwayService.init)
			NetService.onInvoke = real
			expect.truthy(ok, why)
			handlers.HighwayThrow(w.a, SERVER_START, 7)
			expect.deepEqual(w.reports, { 4, 2, 30, 7 })
			finish()
		end
	)

	t.test("one throw in flight: a press before the landing is highway.inFlight (nothing written)", function()
		local w = fresh()
		expect.equal(HighwayService.throw(w.a, SERVER_START).ok, true)
		local writes, saves = w.writes, #w.soonSaves
		local plan = HighwayMath.flight(21)
		w.clock += plan.total - H.inFlightGraceSeconds - 0.01
		expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.inFlight")
		expect.equal(w.writes, writes)
		expect.equal(#w.soonSaves, saves)
		expect.equal(#w.grants, 1)
		expect.equal(w.checks, 2) -- the auto-clicker check saw it too
		-- Another player throws at the same time (no queue).
		expect.equal(HighwayService.throw(w.b, SERVER_START).ok, true)
		w.clock += 0.02 -- the grace: the landing is close enough
		expect.equal(HighwayService.throw(w.a, SERVER_START).ok, true)
		finish()
	end)

	t.test(
		"refusals in order: invalid, the cheat check, not ready, in flight, not in the area, paused, duel",
		function()
			local w = fresh()
			for _, bad in { "1", 0 / 0, math.huge, false } :: { any } do
				expectRefused(HighwayService.throw(w.a, bad), "net.invalid")
			end
			expect.equal(w.checks, 0) -- a broken request never reaches the check
			w.cheat = "highway.tooFast"
			expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.tooFast")
			w.cheat = nil
			w.status[w.a] = "offline"
			expectRefused(HighwayService.throw(w.a, SERVER_START), "data.notReady")
			w.status[w.a] = "ready"
			w.roots[w.a] = nil -- no living character
			expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.notInArea")
			w.roots[w.a] = WorldLayout.Highway.origin.Position -- on the start line, not the deck
			expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.notInArea")
			local edge = WorldLayout.Highway.throwArea.size.X / 2 + H.areaMarginStuds / 2
			w.roots[w.a] = (WorldLayout.Highway.origin * CFrame.new(
				WorldLayout.Highway.throwArea.position + Vector3.new(edge, 0, 0)
			)).Position -- just past the deck's edge: inside the margin
			w.savePending = true
			expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.paused")
			w.savePending = false
			w.closing = true
			expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.paused")
			w.closing = false
			w.restart = true
			expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.paused")
			w.restart = false
			w.phase[w.a] = "Active"
			expectRefused(HighwayService.throw(w.a, SERVER_START), "inventory.lockedInDuel")
			w.phase[w.a] = ""
			expect.equal(w.writes, 0)
			expect.deepEqual(w.grants, {})
			expect.deepEqual(w.soonSaves, {})
			expect.equal(HighwayService.throw(w.a, SERVER_START).ok, true)
			-- Verification fix: the decision (in flight, then the area) before paused, and paused before the duel.
			w.savePending = true
			expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.inFlight")
			land(w, 21)
			w.roots[w.a] = WorldLayout.Highway.origin.Position
			expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.notInArea")
			w.roots[w.a] = ON_DECK
			w.phase[w.a] = "Active"
			expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.paused")
			finish()
		end
	)

	t.test("every landing pays in full: 100 throws back to back each pay 21 studs (no time share, no cap)", function()
		local w = fresh()
		for _ = 1, 100 do
			expect.equal(HighwayService.throw(w.a, SERVER_START).ok, true)
			land(w, 21)
		end
		expect.equal(#w.grants, 100)
		for _, grant in w.grants do
			expect.equal(grant.amount, 105)
		end
		expect.equal(w.profiles[w.a].coins, 10_500)
		finish()
	end)

	t.test("Grip Lv 100: 328 studs in Bakery Town pay 0.5 SV a stud, reaching biome 2 (no gift there)", function()
		local w = fresh()
		w.levels[w.a] = 100
		w.profiles[w.a].pen.items[1].level = 11 -- 10 x 1.15^10 = 40.5 Coins a second: SV 40.5
		local sv = PenMath.squeezeValue(w.profiles[w.a].pen)
		local reply = HighwayService.throw(w.a, SERVER_START)
		expect.equal(reply.data.studs, 328)
		expect.equal(reply.data.biome, 2)
		expect.equal(reply.data.coins, math.floor(0.5 * 328 * sv))
		expect.equal(reply.data.reached, 2)
		expect.deepEqual(reply.data.gifts, {})
		expect.deepEqual(w.profiles[w.a].highway, { best = 328, biome = 2 })
		expect.equal(PenMath.levelCap(w.profiles[w.a].highway), 20) -- Bakery Town's food is on sale now
		-- A shorter throw later keeps the best and the biome (they only rise).
		land(w, 328)
		w.levels[w.a] = 1
		local short = HighwayService.throw(w.a, SERVER_START)
		expect.equal(short.data.newBest, false)
		expect.equal(short.data.coins, math.floor(0.5 * 21 * sv)) -- the same pen: the shorter throw pays less
		expect.equal(short.data.best, 328)
		expect.deepEqual(w.profiles[w.a].highway, { best = 328, biome = 2 })
		finish()
	end)

	-- The Grip level that throws `studs` far or more (power() is 2 x 1.1^(Lv - 1); any whole level).
	local function levelFor(studs: number): number
		local level = 1
		while HighwayMath.landing(HighwayMath.power(level)) < studs do
			level += 1
		end
		return level
	end

	local function kinds(w: World): { string }
		local list = {}
		for _, given in w.squishies do
			table.insert(list, given.kind)
		end
		return list
	end

	t.test("the biome gifts once each, in the throw that first reaches the biome (SIM:205)", function()
		local w = fresh()
		w.levels[w.a] = levelFor(800) -- Boba Lagoon
		local reply = HighwayService.throw(w.a, SERVER_START)
		expect.equal(reply.data.reached, 3)
		expect.deepEqual(reply.data.gifts, { "boba_bear", "boba_bear", "boba_bear" })
		expect.deepEqual(kinds(w), { "boba_bear", "boba_bear", "boba_bear" })
		land(w, reply.data.studs)
		HighwayService.throw(w.a, SERVER_START) -- Boba Lagoon again: nothing more
		expect.equal(#w.squishies, 3)
		land(w, reply.data.studs)
		w.levels[w.a] = levelFor(6000) -- past Lava Volcano and Rainbow Road into Divine Heaven at once
		local far = HighwayService.throw(w.a, SERVER_START)
		expect.equal(far.data.reached, 7)
		expect.deepEqual(far.data.gifts, { "bird", "cloud_bunny", "cloud_bunny", "cloud_bunny" })
		land(w, far.data.studs)
		w.levels[w.a] = levelFor(8500) -- the Golden Gates: biome 8, no gift there
		local gates = HighwayService.throw(w.a, SERVER_START)
		expect.equal(gates.data.studs, 8500)
		expect.equal(gates.data.biome, 7) -- it pays as Divine Heaven
		expect.equal(gates.data.reached, 8)
		expect.deepEqual(gates.data.gifts, {})
		expect.deepEqual(w.profiles[w.a].highway, { best = 8500, biome = 8 })
		expect.equal(#w.squishies, 7)
		-- Another player's gifts are their own.
		expect.equal(HighwayService.throw(w.b, SERVER_START).data.reached, nil)
		expect.equal(#w.squishies, 7)
		finish()
	end)

	t.test("the Food Bag: every 150 s of flight time, 50 SV of the weakest squishy's band food", function()
		local w = fresh()
		local seconds, throws, bag = 0, 0, nil
		while bag == nil and throws < 1000 do
			local reply = HighwayService.throw(w.a, SERVER_START)
			throws += 1
			seconds += reply.data.flight
			bag = reply.data.food
			land(w, reply.data.studs)
		end
		expect.truthy(seconds >= H.foodBag.seconds)
		expect.truthy(seconds - HighwayMath.flight(21).total < H.foodBag.seconds) -- the throw that crossed it
		expect.deepEqual(bag, { id = "candy_drop", count = 1 }) -- max(1, floor(50 x 10 / 400))
		expect.equal(w.profiles[w.a].food.candy_drop, 1)
		expect.truthy(table.find(w.dirty, "food") ~= nil)
		-- The next bag comes after another 150 s, never sooner.
		local next = 0
		for _ = 1, throws - 2 do
			local reply = HighwayService.throw(w.a, SERVER_START)
			if reply.data.food then
				next += 1
			end
			land(w, reply.data.studs)
		end
		expect.equal(next, 0)
		finish()
	end)

	-- Verification fix: the reply names the pieces really added under Food.maxPieces, and no bag when none fit.
	t.test("the Food Bag gives what fits under Food.maxPieces and says so; a full stock gets no bag", function()
		local w = fresh()
		local profile = w.profiles[w.a]
		-- A strong squishy beside the Lv 1 one: the bag is far more than fits (the weakest's food, Candy Drop).
		table.insert(
			profile.pen.items,
			{ id = 2, kind = "dragon", form = 2, level = 70, coat = 7, slot = 2, locked = false }
		)
		profile.pen.nextId = 3
		local max = Config.Economy.Food.maxPieces
		profile.food.candy_drop = max - 5
		local bag = nil
		for _ = 1, 1000 do
			local reply = HighwayService.throw(w.a, SERVER_START)
			land(w, reply.data.studs)
			bag = reply.data.food
			if bag ~= nil then
				break
			end
		end
		expect.deepEqual(bag, { id = "candy_drop", count = 5 })
		expect.equal(profile.food.candy_drop, max)
		table.clear(w.dirty)
		local seconds = 0
		while seconds < H.foodBag.seconds do -- the next bag's 150 s, its stock full
			local reply = HighwayService.throw(w.a, SERVER_START)
			expect.equal(reply.data.food, nil)
			seconds += reply.data.flight
			land(w, reply.data.studs)
		end
		expect.equal(profile.food.candy_drop, max)
		expect.equal(table.find(w.dirty, "food"), nil)
		finish()
	end)

	t.test("the launch board: the last 3 throws of everyone, newest first, and the server best", function()
		local w = fresh()
		HighwayService.start()
		local empty = w.boards[#w.boards]
		expect.equal(empty.Last1Who, Strings.highway.board.empty)
		expect.equal(empty.Last1Distance, "")
		expect.equal(empty.BestWho, "")
		local function studs(n: number): string
			return Strings.format(Strings.highway.studs, { distance = Format.distance(n) })
		end
		HighwayService.throw(w.a, SERVER_START) -- Kai 21
		w.levels[w.b] = 100
		HighwayService.throw(w.b, SERVER_START) -- Mia 328
		land(w, 328)
		HighwayService.throw(w.a, SERVER_START) -- Kai 21
		land(w, 328)
		HighwayService.throw(w.a, SERVER_START) -- Kai 21
		local board = w.boards[#w.boards]
		expect.deepEqual(board, {
			Last1Who = "Kai",
			Last1Distance = studs(21),
			Last2Who = "Kai",
			Last2Distance = studs(21),
			Last3Who = "Mia",
			Last3Distance = studs(328),
			BestWho = "Mia",
			BestDistance = studs(328),
		})
		-- A refused press writes nothing.
		local count = #w.boards
		HighwayService.throw(w.a, SERVER_START)
		expect.equal(#w.boards, count)
		finish()
	end)
end
