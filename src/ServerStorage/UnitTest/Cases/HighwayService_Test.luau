--!strict
-- HighwayService_Test: unit tests for ServerScriptService.Server.Services.HighwayService (pens3 phase 13: the throw for
-- distance; work/pens3/PLAN.md "PHASE 13" with the owner's corrections, work/pens3/p13v2/NOTES.md; p13v4: the TikTok
-- throw, work/pens3/p13v4/SPEC.md 2, 3, 5) with injected fakes: plain-table players and profiles, a fake clock and
-- server clock with a timer queue (task.delay), recorded grants, Grip, gifts, saves, board writes, pings and
-- HighwayLanded fires. Server only (ServerStorage.UnitTest).
-- Contract:
--   * HighwayThrow(clientTime "serverTime", fastSeconds "integer") (RF; p13v3: the client's speed report, handed to
--     the auto-clicker check's speed rule); its Config.Net entry {rate = 14, burst = 30}; p13v4: HighwayLanded (s2c,
--     the owner, one table: Types.HighwayLanding);
--   * the refusal order: (1) clientTime not a finite number -> net.invalid; (2) the auto-clicker check
--     (AutoClickService.checkThrow), which sees every arrival, even during a flight -> its reason; (3) no READY profile
--     -> data.notReady; (4) p13v4: an open flight: within the grace of its landing it settles and the press goes on;
--     else the press asks for a boost -> ok / highway.noFuel / highway.inFlight; (5) the server-side root not in the
--     throw area -> highway.notInArea; (6) a pending failed save, closing or a restart -> highway.paused; (7)
--     SD_DuelPhase set -> inventory.lockedInDuel. Every refusal carries charged = false and writes nothing;
--   * p13v4 a throw: the reply is the flight plan (HighwayMath.newPlan from the lane-local root, released
--     releaseSeconds after the arrival), PERFECT graded at the arrival less half the ping (at most 0.25 s), power x4;
--     nothing is paid at the press;
--   * p13v4 the settle at the landing (task.delay; a boost moves it, a stale one does nothing): it pays in full every
--     time (owner 2026-10-16: no limits): landingCoins(SV, studs, rings) Coins ("highway") and
--     GripService.addFromHighway(pay.grip); best and biome rise (only up), with a "soon" save and the highway field
--     sent; the biome gifts once each, in the throw that first reaches the biome; the Food Bag every 150 s of flight
--     time; the launch board (the last 3 throws of anyone, newest first, and the server best; start() writes the empty
--     board); then HighwayLanded to the owner. playerRemoving settles an open flight without firing.

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
	local SERVER_START = 1_800_000_000.5 -- the PERFECT bar reads 0.625 here: a plain throw
	-- A world position in the middle of the throw area where a standing character's root is (3 over the deck top at
	-- y 2.5; curve.js), and the same lane-local.
	local MIDDLE = WorldLayout.Highway.throwArea.position
	local ON_DECK = (WorldLayout.Highway.origin * CFrame.new(MIDDLE.X, 5.5, MIDDLE.Z)).Position
	local ON_DECK_LOCAL = WorldLayout.Highway.origin:PointToObjectSpace(ON_DECK)

	type Timer = { at: number, fn: () -> () }
	type World = {
		a: any,
		b: any,
		profiles: { [any]: any },
		status: { [any]: string },
		phase: { [any]: string },
		roots: { [any]: Vector3? },
		levels: { [any]: number },
		pings: { [any]: number },
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
		timers: { Timer },
		landed: { { player: any, landing: any } },
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
			pings = {},
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
			timers = {},
			landed = {},
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
			pingOf = function(player: any): number
				return w.pings[player] or 0
			end,
			after = function(seconds: number, fn: () -> ())
				table.insert(w.timers, { at = w.serverNow + seconds, fn = fn })
			end,
			fireLanded = function(player: any, landing: any)
				table.insert(w.landed, { player = player, landing = landing })
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

	-- Moves both clocks on and runs the timers due by then, in time order (task.delay).
	local function advance(w: World, seconds: number)
		w.serverNow += seconds
		w.clock += seconds
		while true do
			local due: number? = nil
			for index, timer in w.timers do
				if timer.at <= w.serverNow and (due == nil or timer.at < w.timers[due :: number].at) then
					due = index
				end
			end
			if due == nil then
				return
			end
			(table.remove(w.timers, due) :: Timer).fn()
		end
	end

	-- On to a moment the PERFECT bar is not green (a plain throw; the fakes' ping is 0).
	local function plainTime(w: World)
		while HighwayMath.isPerfect(w.serverNow) do
			advance(w, 0.05)
		end
	end

	-- Past the plan's landing (its settle runs), then on to a plain moment.
	local function land(w: World, plan: any)
		advance(w, math.max(plan.landsAt - w.serverNow, 0) + 0.01)
		plainTime(w)
	end

	-- A plain throw that lands: its plan.
	local function throwAndLand(w: World, player: any): any
		local reply = HighwayService.throw(player, w.serverNow)
		assert(reply.ok, `the throw went ({tostring(reply.reason)})`)
		land(w, reply.data)
		return reply.data
	end

	local function lastLanding(w: World): any
		local entry = w.landed[#w.landed]
		return if entry then entry.landing else nil
	end

	-- The first server time at or after `from` where the PERFECT bar is at its middle (rising or falling).
	local function perfectCentre(from: number): number
		local best, bestGap = from, math.huge
		for step = 0, 3200 do
			local at = from + step * 0.0005
			local gap = math.abs(HighwayMath.barAt(at) - 0.5)
			if gap < bestGap then
				best, bestGap = at, gap
			end
			if gap < 1e-3 then
				return at
			end
		end
		return best
	end

	t.test("HighwayThrow takes a serverTime and a speed report; p13v4 HighwayLanded goes to the owner", function()
		local spec = Remotes.SPEC.HighwayThrow
		expect.equal(spec.kind, "RemoteFunction")
		expect.equal(spec.dir, "c2s")
		expect.deepEqual(
			spec.args,
			{ { name = "clientTime", type = "serverTime" }, { name = "fastSeconds", type = "integer" } }
		)
		expect.deepEqual(Config.Net.Remotes.HighwayThrow, { rate = 14, burst = 30 })
		expect.truthy(table.find(Config.Economy.CoinReasons, "highway") ~= nil)
		local landed = Remotes.SPEC.HighwayLanded
		expect.equal(landed.kind, "RemoteEvent")
		expect.equal(landed.dir, "s2c")
		expect.equal(landed.audience, "owner")
		expect.deepEqual(landed.args, { { name = "landing", type = "table" } })
	end)

	t.test("p13v4: a throw answers its flight plan and pays nothing until it lands", function()
		local w = fresh()
		local reply = HighwayService.throw(w.a, SERVER_START)
		expect.equal(reply.ok, true)
		local core = HighwayMath.newPlan(900, ON_DECK_LOCAL, SERVER_START + H.flight.releaseSeconds)
		expect.deepEqual(reply.data, {
			id = 1,
			perfect = false,
			x0 = core.x0,
			arcs = core.arcs,
			roll = core.roll,
			studs = 213,
			biome = 1,
			landsAt = core.landsAt,
			fuel = 1,
			boosted = false,
			charged = false,
			savePending = false,
		})
		expect.deepEqual(w.grants, {})
		expect.deepEqual(w.grip, {})
		expect.deepEqual(w.soonSaves, {})
		expect.deepEqual(w.landed, {})
		expect.equal(w.writes, 0)
		expect.deepEqual(w.profiles[w.a].highway, { best = 0, biome = 1 })
		expect.equal(#w.timers, 1)
		expect.near(w.timers[1].at, core.landsAt, 1e-6) -- the settle waits for the landing
		expect.equal(w.checks, 1)
		finish()
	end)

	t.test(
		"p13v4: the landing pays 0.5 SV a stud (+10 % a ring), 60 squeezes of Grip, saves, fires HighwayLanded",
		function()
			local w = fresh()
			local plan = HighwayService.throw(w.a, SERVER_START).data
			advance(w, plan.landsAt - w.serverNow - 0.01)
			expect.deepEqual(w.grants, {}) -- not yet
			advance(w, 0.02)
			expect.deepEqual(w.grants, { { player = w.a, amount = 1065, reason = "highway" } }) -- 0.5 x 213 x SV 10
			expect.deepEqual(w.grip, { { player = w.a, squeezes = 60 } })
			expect.deepEqual(w.profiles[w.a].highway, { best = 213, biome = 1 })
			expect.deepEqual(w.soonSaves, { w.a })
			expect.truthy(table.find(w.dirty, "highway") ~= nil)
			expect.equal(#w.landed, 1)
			expect.equal(w.landed[1].player, w.a)
			expect.deepEqual(w.landed[1].landing, {
				id = 1,
				studs = 213,
				biome = 1,
				coins = 1065,
				grip = 600, -- the fake: 60 squeezes x 10
				best = 213,
				newBest = true,
				reached = nil,
				gifts = {},
				food = nil,
				rings = {},
				bullseye = false,
				perfect = false,
				boosts = 0,
			})
			-- A throw through a ring pays its share: a PERFECT throw at Lv 1 (257 studs) flies through ring 1.
			w.serverNow = perfectCentre(w.serverNow)
			local perfect = HighwayService.throw(w.a, w.serverNow).data
			expect.equal(perfect.perfect, true)
			expect.equal(perfect.studs, 257)
			expect.equal(perfect.id, 2)
			land(w, perfect)
			local landing = lastLanding(w)
			expect.deepEqual(landing.rings, { 1 })
			expect.equal(landing.coins, HighwayMath.landingCoins(10, 257, 1)) -- floor(0.5 x 257 x 1.1 x 10)
			expect.equal(landing.coins, 1413)
			expect.equal(landing.perfect, true)
			expect.equal(w.grants[2].amount, 1413)
			finish()
		end
	)

	t.test("p13v4: PERFECT is graded at the arrival less half the ping (at most 0.25 s)", function()
		local w = fresh()
		local centre = perfectCentre(SERVER_START)
		local function graded(arrival: number, ping: number): boolean
			w.serverNow = arrival
			w.pings[w.a] = ping
			local reply = HighwayService.throw(w.a, arrival)
			assert(reply.ok, tostring(reply.reason))
			land(w, reply.data)
			return reply.data.perfect
		end
		expect.truthy(graded(centre, 0))
		expect.falsy(graded(centre + 0.15, 0)) -- 0.15 s past the middle: out of the 0.08 s half-window
		expect.truthy(graded(perfectCentre(w.serverNow) + 0.15, 0.3)) -- pressed 0.15 s before it arrived
		-- A 1 s ping counts as 0.25 s one way, not 0.5 s (0.25 s apart: more than the 0.08 s half-window).
		expect.truthy(graded(perfectCentre(w.serverNow) + 0.25, 1))
		expect.falsy(graded(perfectCentre(w.serverNow) + 0.5, 1))
		expect.falsy(graded(perfectCentre(w.serverNow) + 0.15, -4)) -- a broken ping counts as 0
		expect.falsy(graded(perfectCentre(w.serverNow) + 0.15, 0 / 0))
		finish()
	end)

	t.test(
		"p13v3: the speed report every arrival carries reaches the auto-clicker check, a refused one's too",
		function()
			local w = fresh()
			expect.equal(HighwayService.throw(w.a, SERVER_START, 4).ok, true)
			expectRefused(HighwayService.throw(w.a, SERVER_START, 2), "highway.inFlight") -- a double tap at the throw
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

	t.test("p13v4 boost: a press during the own flight boosts once (x4 power), then noFuel; nothing written", function()
		local w = fresh()
		local plan = HighwayService.throw(w.a, SERVER_START).data
		local release = plan.arcs[1].startAt
		advance(w, release + 0.19 - w.serverNow)
		expectRefused(HighwayService.throw(w.a, w.serverNow), "highway.inFlight") -- too soon after the release
		advance(w, release + 1 - w.serverNow)
		local reply = HighwayService.throw(w.a, w.serverNow)
		expect.equal(reply.ok, true)
		local boosted = reply.data
		local expected = HighwayMath.boost(plan, 900, w.serverNow) :: any
		expect.equal(boosted.id, 1) -- the same throw
		expect.equal(boosted.boosted, true)
		expect.equal(boosted.fuel, 0)
		expect.equal(boosted.studs, 257) -- landing(900 x 4)
		expect.equal(boosted.biome, 1)
		expect.deepEqual(boosted.arcs, expected.arcs)
		expect.equal(boosted.landsAt, expected.landsAt)
		expect.equal(boosted.charged, false)
		expect.equal(plan.boosted, false) -- the first reply is untouched
		expectRefused(HighwayService.throw(w.a, w.serverNow + 0.1), "highway.noFuel")
		expect.equal(w.writes, 0)
		expect.deepEqual(w.grants, {})
		expect.equal(w.checks, 4) -- every press saw the auto-clicker check
		-- The settle of the old landing is stale: nothing until the boosted landing.
		expect.truthy(plan.landsAt < boosted.landsAt)
		advance(w, plan.landsAt + 0.01 - w.serverNow)
		expect.deepEqual(w.grants, {})
		advance(w, boosted.landsAt + 0.01 - w.serverNow)
		expect.equal(#w.grants, 1)
		local landing = lastLanding(w)
		expect.equal(landing.studs, 257)
		expect.equal(landing.boosts, 1)
		expect.deepEqual(landing.rings, HighwayMath.ringsHit(boosted))
		expect.equal(landing.coins, HighwayMath.landingCoins(10, 257, #landing.rings))
		expect.equal(#w.landed, 1)
		finish()
	end)

	t.test("p13v4 boost: refused while rolling (inFlight), and the next throw has its fuel again", function()
		local w = fresh()
		local plan = HighwayService.throw(w.a, SERVER_START).data
		expect.truthy(plan.roll > 0.2) -- 213 studs roll a little
		local airEnd = HighwayMath.airEnd(plan)
		advance(w, airEnd + 0.05 - w.serverNow)
		expectRefused(HighwayService.throw(w.a, w.serverNow), "highway.inFlight")
		advance(w, airEnd - 0.1 - w.serverNow) -- (time does not go back: the clocks only move on in play)
		land(w, plan)
		local again = HighwayService.throw(w.a, w.serverNow).data
		expect.equal(again.fuel, 1)
		expect.equal(again.id, 2)
		finish()
	end)

	t.test("p13v4: a press within the grace of the landing settles it, then throws", function()
		local w = fresh()
		local plan = HighwayService.throw(w.a, SERVER_START).data
		advance(w, plan.landsAt - H.inFlightGraceSeconds + 0.02 - w.serverNow)
		plainTime(w)
		expect.deepEqual(w.grants, {})
		local reply = HighwayService.throw(w.a, w.serverNow)
		expect.equal(reply.ok, true)
		expect.equal(reply.data.id, 2)
		expect.equal(reply.data.boosted, false)
		expect.equal(#w.grants, 1) -- the first throw landed
		expect.equal(lastLanding(w).id, 1)
		land(w, reply.data) -- the first throw's own timer is stale: it pays once
		expect.equal(#w.grants, 2)
		expect.equal(#w.landed, 2)
		expect.equal(lastLanding(w).id, 2)
		-- Another player throws at the same time (no queue).
		expect.equal(HighwayService.throw(w.b, w.serverNow).ok, true)
		expect.equal(HighwayService.throw(w.a, w.serverNow).ok, true)
		finish()
	end)

	t.test(
		"refusals in order: invalid, the cheat check, not ready, the flight, not in the area, paused, duel",
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
			expect.deepEqual(w.timers, {})
			local plan = HighwayService.throw(w.a, SERVER_START).data
			-- The flight before the area and paused; paused before the duel.
			w.savePending = true
			w.roots[w.a] = WorldLayout.Highway.origin.Position
			expectRefused(HighwayService.throw(w.a, SERVER_START), "highway.inFlight")
			w.savePending = false
			w.status[w.a] = "offline"
			expectRefused(HighwayService.throw(w.a, SERVER_START), "data.notReady") -- before the flight
			w.status[w.a] = "ready"
			land(w, plan)
			w.savePending = true
			expectRefused(HighwayService.throw(w.a, w.serverNow), "highway.notInArea")
			w.roots[w.a] = ON_DECK
			w.phase[w.a] = "Active"
			expectRefused(HighwayService.throw(w.a, w.serverNow), "highway.paused")
			finish()
		end
	)

	t.test("every landing pays in full: 100 throws back to back each pay 213 studs (no time share, no cap)", function()
		local w = fresh()
		for _ = 1, 100 do
			local plan = throwAndLand(w, w.a)
			expect.equal(plan.studs, 213)
		end
		expect.equal(#w.grants, 100)
		for _, grant in w.grants do
			expect.equal(grant.amount, 1065)
		end
		expect.equal(w.profiles[w.a].coins, 106_500)
		finish()
	end)

	t.test("Grip Lv 100: 403 studs in Bakery Town pay 0.5 SV a stud with the rings, reaching biome 2", function()
		local w = fresh()
		w.levels[w.a] = 100
		w.profiles[w.a].pen.items[1].level = 11 -- 10 x 1.15^10 = 40.5 Coins a second: SV 40.5
		local sv = PenMath.squeezeValue(w.profiles[w.a].pen)
		local plan = throwAndLand(w, w.a)
		expect.equal(plan.studs, 403)
		expect.equal(plan.biome, 2)
		local landing = lastLanding(w)
		expect.deepEqual(landing.rings, HighwayMath.ringsHit(plan))
		expect.equal(landing.coins, math.floor(0.5 * 403 * (1 + 0.1 * #landing.rings) * sv))
		expect.equal(landing.reached, 2)
		expect.deepEqual(landing.gifts, {})
		expect.deepEqual(w.profiles[w.a].highway, { best = 403, biome = 2 })
		expect.equal(PenMath.levelCap(w.profiles[w.a].highway), 20) -- Bakery Town's food is on sale
		-- A shorter throw later keeps the best and the biome (they only rise).
		w.levels[w.a] = 1
		throwAndLand(w, w.a)
		local short = lastLanding(w)
		expect.equal(short.newBest, false)
		expect.equal(short.coins, HighwayMath.landingCoins(sv, 213, #short.rings)) -- the shorter throw pays less
		expect.truthy(short.coins < landing.coins)
		expect.equal(short.best, 403)
		expect.equal(short.reached, nil)
		expect.deepEqual(w.profiles[w.a].highway, { best = 403, biome = 2 })
		finish()
	end)

	-- The Grip level that throws `studs` far or more (power() is 900 x 1.05^(Lv - 1); any whole level).
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

	t.test("the biome gifts once each, at the landing that first reaches the biome (SIM:205)", function()
		local w = fresh()
		w.levels[w.a] = levelFor(800) -- Boba Lagoon
		local plan = HighwayService.throw(w.a, w.serverNow).data
		expect.deepEqual(w.squishies, {}) -- not at the press
		land(w, plan)
		local landing = lastLanding(w)
		expect.equal(landing.reached, 3)
		expect.deepEqual(landing.gifts, { "boba_bear", "boba_bear", "boba_bear" })
		expect.deepEqual(kinds(w), { "boba_bear", "boba_bear", "boba_bear" })
		throwAndLand(w, w.a) -- Boba Lagoon again: nothing more
		expect.equal(#w.squishies, 3)
		w.levels[w.a] = levelFor(6000) -- past Lava Volcano and Rainbow Road into Divine Heaven at once
		throwAndLand(w, w.a)
		local far = lastLanding(w)
		expect.equal(far.reached, 7)
		expect.deepEqual(far.gifts, { "bird", "cloud_bunny", "cloud_bunny", "cloud_bunny" })
		w.levels[w.a] = levelFor(8500) -- the Golden Gates: biome 8, no gift there
		throwAndLand(w, w.a)
		local gates = lastLanding(w)
		expect.equal(gates.studs, 8500)
		expect.equal(gates.biome, 7) -- it pays as Divine Heaven
		expect.equal(gates.reached, 8)
		expect.deepEqual(gates.gifts, {})
		expect.deepEqual(w.profiles[w.a].highway, { best = 8500, biome = 8 })
		expect.equal(#w.squishies, 7)
		-- Another player's gifts are their own.
		throwAndLand(w, w.b)
		expect.equal(lastLanding(w).reached, nil)
		expect.equal(#w.squishies, 7)
		finish()
	end)

	t.test("the Food Bag: every 150 s of flight time, 50 SV of the weakest squishy's band food", function()
		local w = fresh()
		local seconds, throws, bag = 0, 0, nil
		local flight = 0
		while bag == nil and throws < 1000 do
			local pressed = w.serverNow
			local plan = throwAndLand(w, w.a)
			flight = plan.landsAt - pressed -- the release + the air + the roll
			throws += 1
			seconds += flight
			bag = lastLanding(w).food
		end
		expect.truthy(seconds >= H.foodBag.seconds)
		expect.truthy(seconds - flight < H.foodBag.seconds) -- the throw that crossed it
		expect.deepEqual(bag, { id = "candy_drop", count = 1 }) -- max(1, floor(50 x 10 / 400))
		expect.equal(w.profiles[w.a].food.candy_drop, 1)
		expect.truthy(table.find(w.dirty, "food") ~= nil)
		-- The next bag comes after another 150 s, never sooner.
		local next = 0
		for _ = 1, throws - 2 do
			throwAndLand(w, w.a)
			if lastLanding(w).food then
				next += 1
			end
		end
		expect.equal(next, 0)
		finish()
	end)

	-- Verification fix: the landing names the pieces really added under Food.maxPieces, and no bag when none fit.
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
			throwAndLand(w, w.a)
			bag = lastLanding(w).food
			if bag ~= nil then
				break
			end
		end
		expect.deepEqual(bag, { id = "candy_drop", count = 5 })
		expect.equal(profile.food.candy_drop, max)
		table.clear(w.dirty)
		local seconds = 0
		while seconds < H.foodBag.seconds do -- the next bag's 150 s, its stock full
			local pressed = w.serverNow
			local plan = throwAndLand(w, w.a)
			expect.equal(lastLanding(w).food, nil)
			seconds += plan.landsAt - pressed
		end
		expect.equal(profile.food.candy_drop, max)
		expect.equal(table.find(w.dirty, "food"), nil)
		finish()
	end)

	t.test("the launch board: the last 3 landings of everyone, newest first, and the server best", function()
		local w = fresh()
		HighwayService.start()
		local empty = w.boards[#w.boards]
		expect.equal(empty.Last1Who, Strings.highway.board.empty)
		expect.equal(empty.Last1Distance, "")
		expect.equal(empty.BestWho, "")
		local function studs(n: number): string
			return Strings.format(Strings.highway.studs, { distance = Format.distance(n) })
		end
		local count = #w.boards
		local kai = HighwayService.throw(w.a, w.serverNow).data -- Kai 213
		expect.equal(#w.boards, count) -- written at the landing, not the press
		land(w, kai)
		w.levels[w.b] = 100
		throwAndLand(w, w.b) -- Mia 403
		throwAndLand(w, w.a) -- Kai 213
		throwAndLand(w, w.a) -- Kai 213
		local board = w.boards[#w.boards]
		expect.deepEqual(board, {
			Last1Who = "Kai",
			Last1Distance = studs(213),
			Last2Who = "Kai",
			Last2Distance = studs(213),
			Last3Who = "Mia",
			Last3Distance = studs(403),
			BestWho = "Mia",
			BestDistance = studs(403),
		})
		-- A refused press writes nothing.
		count = #w.boards
		w.roots[w.a] = nil
		HighwayService.throw(w.a, w.serverNow)
		expect.equal(#w.boards, count)
		finish()
	end)

	t.test("p13v4: leaving mid-flight settles the throw without firing; its timer then does nothing", function()
		local w = fresh()
		local plan = HighwayService.throw(w.a, SERVER_START).data
		advance(w, 1)
		HighwayService.playerRemoving(w.a)
		expect.equal(#w.grants, 1)
		expect.deepEqual(w.profiles[w.a].highway, { best = 213, biome = 1 })
		expect.deepEqual(w.landed, {})
		land(w, plan)
		expect.equal(#w.grants, 1)
		expect.deepEqual(w.landed, {})
		-- Leaving with no flight changes nothing.
		HighwayService.playerRemoving(w.b)
		expect.equal(#w.grants, 1)
		finish()
	end)

	t.test("p13v4: a landing whose profile is not ready grants nothing and fires nothing", function()
		local w = fresh()
		local plan = HighwayService.throw(w.a, SERVER_START).data
		w.status[w.a] = "offline"
		land(w, plan)
		expect.deepEqual(w.grants, {})
		expect.deepEqual(w.grip, {})
		expect.deepEqual(w.landed, {})
		w.status[w.a] = "ready"
		expect.equal(HighwayService.throw(w.a, w.serverNow).ok, true) -- the flight is over
		finish()
	end)
end
