--!strict
-- SqueezeService_Test: unit tests for ServerScriptService.Server.Services.SqueezeService (and its GripService step 8a)
-- with injected fakes: fake clocks, a fake profile, fake positions; the "player" is a plain table. Server only
-- (ServerStorage.UnitTest). Edit mode: init() is never called, so no remote is touched.
-- Contract (DESIGN §6.3, §17.3.1 steps 6a / 8a, §17.6, §17.10, §17.12 Part 5 "SqueezeService with fakes"; squeeze
-- anywhere, spec 2026-10-11 §5):
--   * SqueezeRequest takes only the client's speed report (p13v3, for the auto-clicker check's speed rule): the
--     server finds the pad under its own root position (SqueezeRules.padUnder) and ignores anything else;
--   * an accepted squeeze on a mat pays the squeeze value (pens3 phase 1: the pen's PenMath.squeezeValue, whole,
--     whatever squishy is held or pad stood on; a capsule counts for nothing), trains its floor in Grip, counts
--     stats.squeezes, sets SD_SqueezeAt (server time), fires Squeezed and replies ok; an argument the client sends is
--     ignored (no capsule push any more);
--   * off every pad, on a pad the lobby does not have or one the stale-lobby check disabled, the squeeze pays the same
--     and reports tier 1 (Squeezed with tier 1); since the giant pads went (build plan Phase 6) every station is a
--     tier-1 Foam Mat (squeeze_01..06);
--     only a dead character is refused (squeeze.noCharacter), and a player in a match;
--   * the shipped hourly limit is off: every accepted squeeze pays (with the limit switched on, an empty one would give
--     0 Coins while Grip still rises);
--   * squeezes pay up to the hold rhythm (Batch 1 #2, replacing every click pays): the bucket's presses all pay Coins
--     and Grip; one more is squeeze.tooFast with no Coins, no Grip and no stats; holding for a minute
--     pays every press; clicking at 12/s for a minute pays only the hold rhythm (2 + 60 / 0.45 at most, the rest
--     tooFast, none dropped); a steady 20 requests/s is never dropped; a 25/s macro is capped at 1 accepted per
--     cycleSeconds (after the bucket) and its excess above 20/s is dropped silently;
--   * exactly 1 Double Grip point is used per accepted squeeze;
--   * an OFFLINE profile earns nothing (data.notReady), nor does a session whose final save started (mutate refuses);
--   * nextAt is in server time: serverNow + max(0, 1 - tokens) x cycleSeconds;
--   * the stale-lobby check disables a station whose GripTier disagrees with WorldLayout (no boost; Phase 6: slow
--     training is gone, so GripService has nothing to disable);
--   * one player's paid squeezes above Config.Grip.squeezeAlertPerHour in a rolling hour log one [SD][abuse] warning
--     (spec 2026-10-12 §12; log only: the squeezes still pay; 8,000 since Batch 1 #2, so only riding the paid cap for
--     a whole hour passes it); the alert re-arms once the hour's squeezes are back under it;
--   * auto-clicker check (2026-10-16): every request goes to AutoClickService.check first with its os.clock arrival
--     time; a reason back is the reply (squeeze.autoClick / squeeze.tooFast) with no Coins, no Grip, no stats and no
--     token of the paid cap used; wired to the real AutoClickService (enforce = "full"), a steady
--     10/s macro is caught (one squeeze.autoClick, then a silent penalty) and a minute's hold never is (review fix
--     2026-10-16: 19/s is the client ceiling's rhythm, never judged). The other cases switch it off. P13v3 (owner
--     2026-10-18: "Yes, above 20 a second"): the speed report a request carries reaches the check; wired, an
--     auto-clicker at 36 a second through the client's 18 sends a second (Shared/PressSpeed's report on each) is
--     caught once (squeeze.superFast).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local SqueezeService = t.requireServer("Services/SqueezeService")
	local GripService = t.requireServer("Services/GripService")
	local FakeClock = t.requireFake("FakeClock")
	local PenMath = t.requireShared("PenMath")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")

	local SQ = Config.Squeeze
	local LIMIT = Config.Economy.SqueezeLimit
	local REST = Config.Grip.Rested
	local UNIX_START = 1_800_000_000
	local SERVER_START = 1_800_000_000.25

	type World = {
		clock: any,
		unix: any,
		server: any,
		player: any,
		status: string,
		profile: any,
		position: Vector3?,
		alive: boolean,
		phase: string,
		equipped: string,
		untagged: { [string]: boolean },
		replies: { any },
		squeezeAt: number?,
		squeezed: { { id: string, coins: number, tier: number } },
		dirty: { string },
		frozen: boolean, -- the session takes no more changes (its final save took its snapshot): mutate refuses
	}

	local function onStation(id: string): Vector3
		local station = WorldLayout.station(id)
		return Vector3.new(station.position.X, station.top + 3, station.position.Z)
	end

	local function newProfile(): any
		return {
			coins = 0,
			stats = { squeezes = 0, coinsEarned = 0 },
			squeezeLimit = { value = LIMIT.burst, at = UNIX_START },
			quests = { day = 1, swapsUsed = 0, active = {} },
			starter = { progress = {}, claimed = {} },
			grip = {
				total = 0,
				rested = { value = 0, at = UNIX_START },
			},
			-- Pens3 phase 1: a new player's pen, Kitty Bread in the 3 free spots.
			pen = {
				spots = 3,
				nextId = 2,
				items = { { id = 1, kind = "kitty_bread", form = 0, level = 1, coat = 0, slot = 1, locked = false } },
			},
		}
	end

	-- What one own squeeze pays this profile (pens3 phase 1): the pen's squeeze value and its floor in Grip.
	local function valueOf(world: any): number
		return PenMath.rewardCoins(1, PenMath.squeezeValue(world.profile.pen))
	end
	local function gripOf(world: any): number
		return PenMath.squeezeGrip(world.profile.pen)
	end

	-- `autoClick` = SqueezeService's AutoClickService.check dependency (auto-clicker check 2026-10-16); nil = off.
	local function fresh(autoClick: ((player: any, now: number, fastSeconds: number?) -> string?)?): World
		local world: World = {
			clock = FakeClock.new(500),
			unix = FakeClock.new(UNIX_START),
			server = FakeClock.new(SERVER_START),
			player = { UserId = 7, DisplayName = "Squeezer" },
			status = "ready",
			profile = newProfile(),
			position = onStation("squeeze_01"),
			alive = true,
			phase = "",
			equipped = Catalog.starterId(),
			untagged = {},
			replies = {},
			squeezeAt = nil,
			squeezed = {},
			dirty = {},
			frozen = false,
		}
		local function status(_player: any): string
			return world.status
		end
		local function profileOf(_player: any): any
			return world.profile
		end
		-- Like DataService.mutate: a READY session that still takes changes only.
		local function mutate(_player: any, fn: (profile: any) -> any): (boolean, any)
			if world.status ~= "ready" or world.frozen then
				return false, "data.notReady"
			end
			return true, fn(world.profile)
		end
		local function rootOf(_player: any): (Vector3?, boolean)
			return world.position, world.alive
		end
		local function phaseOf(_player: any): string
			return world.phase
		end
		local function markDirty(_player: any, field: string)
			table.insert(world.dirty, field)
		end
		SqueezeService.reset()
		GripService.reset()
		SqueezeService.Squeezed:disconnectAll()
		SqueezeService.Squeezed:connect(function(_player: any, id: string, coins: number, tier: number)
			table.insert(world.squeezed, { id = id, coins = coins, tier = tier })
		end)
		GripService.useDeps({
			clock = world.clock.now,
			unixNow = world.unix.now,
			statusOf = status,
			profileOf = profileOf,
			mutate = mutate,
			duelPhaseOf = phaseOf,
			isClosing = function(): boolean
				return false
			end,
			markDirty = markDirty,
			requestSave = function() end,
			notify = function() end,
			lobbyPlayers = function(): { any }
				return {}
			end,
			setLevelAttribute = function() end,
			migratedFrom = function(): number?
				return nil
			end,
			displayName = function(): string
				return "Squeezer"
			end,
		})
		SqueezeService.useDeps({
			clock = world.clock.now,
			unixNow = world.unix.now,
			serverNow = world.server.now,
			statusOf = status,
			profileOf = profileOf,
			mutate = mutate,
			stationTagged = function(id: string): boolean
				return not world.untagged[id]
			end,
			rootOf = rootOf,
			duelPhaseOf = phaseOf,
			equippedOf = function(_player: any): string
				return world.equipped
			end,
			grantCoins = function(_player: any, amount: number, reason: string): number
				assert(reason == "squeeze", "squeeze Coins use the reason squeeze")
				-- Like EconomyService: clamped at maxCoins, the return value is what was really added.
				local added = math.min(amount, Config.Economy.maxCoins - world.profile.coins)
				world.profile.coins += added
				world.profile.stats.coinsEarned += added
				return added
			end,
			markDirty = markDirty,
			setSqueezeAt = function(_player: any, at: number)
				world.squeezeAt = at
			end,
			reply = function(_player: any, result: any)
				table.insert(world.replies, result)
			end,
			-- Auto-clicker check (2026-10-16): off unless a case passes one (the cases at the end).
			autoClick = autoClick or function(_player: any, _now: number): string?
				return nil
			end,
		})
		GripService.playerAdded(world.player)
		return world
	end

	local function finish()
		SqueezeService.reset()
		SqueezeService.useDeps(nil)
		SqueezeService.Squeezed:disconnectAll()
		GripService.reset()
		GripService.useDeps(nil)
	end

	local function wait(world: World, seconds: number)
		world.clock.advance(seconds)
		world.unix.advance(seconds)
		world.server.advance(seconds)
	end

	t.test("an accepted squeeze at a mat pays Coins, trains Grip and replies ok", function()
		local world = fresh()
		local result = SqueezeService.request(world.player)
		local coins = valueOf(world)
		expect.equal(coins, 10) -- a new player's squeeze (spec 2026-10-12 §9)
		expect.truthy(result ~= nil)
		expect.equal(result.ok, true)
		expect.equal(result.coins, coins)
		expect.equal(result.total, coins)
		expect.equal(world.profile.coins, coins)
		expect.equal(result.grip, gripOf(world))
		expect.equal(result.gripTotal, world.profile.grip.total)
		expect.equal(result.doubled, false)
		expect.equal(result.limit, if LIMIT.enabled then LIMIT.burst - 1 else LIMIT.burst) -- off: spec 2026-10-11 §5
		expect.equal(world.profile.stats.squeezes, 1)
		expect.equal(world.squeezeAt, world.server.now())
		expect.deepEqual(world.squeezed, { { id = world.equipped, coins = coins, tier = 1 } })
		expect.equal(#world.replies, 1)
		expect.truthy(table.find(world.dirty, "stats") ~= nil)
		expect.truthy(table.find(world.dirty, "squeezeLimit") ~= nil)
		expect.truthy(table.find(world.dirty, "grip") ~= nil)
		finish()
	end)

	t.test("the reply's coins are what the balance really gained (at the Coin cap)", function()
		local world = fresh()
		world.profile.coins = Config.Economy.maxCoins - 1
		local result = SqueezeService.request(world.player)
		expect.equal(result.ok, true)
		expect.equal(result.coins, 1)
		expect.equal(result.total, Config.Economy.maxCoins)
		expect.equal(world.squeezed[1].coins, 1)
		expect.equal(result.grip, gripOf(world)) -- Grip never depends on the Coin cap
		finish()
	end)

	-- Phase 3 (spec 2026-10-12 §3): was "the equipped squishy's rarity sets the Coins".
	t.test("the held squishy no longer changes the Coins: every squeeze pays the squeeze value", function()
		local world = fresh()
		world.equipped = "dragon"
		local result = SqueezeService.request(world.player)
		expect.equal(result.coins, valueOf(world))
		expect.equal(world.squeezed[1].id, "dragon") -- the quests still see the held squishy
		finish()
	end)

	t.test("own squeezes pay the pen's squeeze value, whole, and train its floor in Grip (x mult doubled)", function()
		local world = fresh()
		-- Pens3 phase 1: Kitty Bread Lv 2 (11.5) + Dragon (640) = 651.5 a squeeze; a capsule counts for nothing.
		world.profile.pen.items[1].level = 2
		table.insert(
			world.profile.pen.items,
			{ id = 2, kind = "dragon", form = 0, level = 1, coat = 0, slot = 2, locked = false }
		)
		world.profile.capsules = { slots = 1, list = { { level = 100, squishyId = "dragon" } } }
		local plain = SqueezeService.request(world.player)
		expect.equal(plain.coins, 651)
		expect.equal(plain.grip, 651)
		expect.equal(plain.doubled, false)
		world.profile.grip.rested = { value = 1, at = UNIX_START }
		world.clock.advance(SQ.cycleSeconds)
		world.server.advance(SQ.cycleSeconds)
		local doubled = SqueezeService.request(world.player)
		expect.equal(doubled.coins, 651) -- Double Grip doubles Grip only
		expect.equal(doubled.doubled, REST.enabled)
		expect.equal(doubled.grip, 651 * (if REST.enabled then REST.mult else 1))
		finish()
	end)

	t.test("refusals pay nothing; an argument the client sends is ignored", function()
		local world = fresh()
		world.phase = "Active" -- in a match: squeeze.inDuel
		expect.equal(SqueezeService.request(world.player).reason, "squeeze.inDuel")
		world.phase = ""
		world.alive = false
		world.clock.advance(1)
		expect.equal(SqueezeService.request(world.player).reason, "squeeze.noCharacter")
		expect.equal(world.profile.coins, 0)
		world.alive = true
		world.position = Vector3.new(5, 3, -120) -- anywhere: a squeeze pays the same everywhere
		world.clock.advance(1)
		local forged = (SqueezeService.request :: any)(world.player, Vector3.zero)
		expect.equal(forged.ok, true)
		expect.equal(forged.coins, valueOf(world))
		finish()
	end)

	-- Squeeze anywhere (spec 2026-10-11 §5) ---------------------------------------------------------------------------

	-- One accepted squeeze that paid the base (tier 1; every squeeze pays the squeeze value and, since pens3 phase 1,
	-- its floor in Grip; since Phase 6 every station is tier 1 too).
	local function expectBase(world: World, result: any)
		expect.equal(result.ok, true)
		expect.equal(result.coins, valueOf(world))
		expect.equal(result.grip, gripOf(world))
		expect.equal(world.squeezed[#world.squeezed].tier, 1)
	end

	t.test("off every pad the squeeze pays the base (tier 1), Grip and quests included", function()
		local world = fresh()
		world.position = Vector3.new(0, 3, 40) -- the spawn: no pad under it
		expectBase(world, SqueezeService.request(world.player))
		expect.equal(world.profile.stats.squeezes, 1)
		expect.truthy(world.profile.grip.total > 0)
		finish()
	end)

	t.test("the giant pads' stations are gone (Phase 6): squeeze_07..09 are not WorldLayout stations", function()
		for _, id in { "squeeze_07", "squeeze_08", "squeeze_09" } do
			expect.equal(WorldLayout.station(id), nil)
		end
		expect.equal(#WorldLayout.stationIds(), 6)
	end)

	t.test(
		"the client's station id is ignored: the pad is the server's own (an extra argument changes nothing)",
		function()
			local world = fresh()
			world.position = onStation("squeeze_01")
			local forged = (SqueezeService.request :: any)(world.player, "squeeze_06")
			expect.equal(forged.ok, true)
			expect.equal(forged.coins, valueOf(world))
			expect.equal(world.squeezed[1].tier, 1)
			finish()
		end
	)

	t.test("a pad the lobby does not have gives no boost: the base is paid", function()
		local world = fresh()
		world.position = onStation("squeeze_02")
		world.untagged.squeeze_02 = true
		expectBase(world, SqueezeService.request(world.player))
		finish()
	end)

	t.test("the shipped hourly limit is off: an empty limit state still pays full Coins, and Grip rises", function()
		local world = fresh()
		expect.falsy(LIMIT.enabled)
		world.profile.squeezeLimit = { value = 0, at = UNIX_START }
		local result = SqueezeService.request(world.player)
		expect.equal(result.ok, true)
		expect.equal(result.coins, valueOf(world))
		expect.equal(world.profile.squeezeLimit.value, 0) -- the dormant limit state is left alone
		expect.equal(result.grip, gripOf(world))
		expect.truthy(world.profile.grip.total > 0)
		expect.equal(world.profile.stats.squeezes, 1) -- still counts for stats and quests
		expect.equal(#world.squeezed, 1)
		finish()
	end)

	-- The paid cap (Batch 1 #2: squeezes pay up to the hold rhythm) ---------------------------------------------------

	-- `count` requests at mat squeeze_01, `spacing` seconds apart; returns (replies in order, drops).
	local function click(world: World, count: number, spacing: number): ({ any }, number)
		local replies, dropped = {}, 0
		for i = 1, count do
			local result = SqueezeService.request(world.player)
			if result == nil then
				dropped += 1
			else
				table.insert(replies, result)
			end
			if i < count and spacing > 0 then
				wait(world, spacing)
			end
		end
		return replies, dropped
	end

	t.test("the bucket's presses all pay Coins and Grip", function()
		local world = fresh()
		local coinsEach = valueOf(world)
		local replies, dropped = click(world, SQ.bucketCapacity, 1 / SQ.bucketCapacity)
		expect.equal(dropped, 0)
		expect.equal(#replies, SQ.bucketCapacity)
		local grip = 0
		for i, result in replies do
			if not result.ok or result.coins ~= coinsEach or result.grip <= 0 then
				error(
					`press {i}: ok {tostring(result.ok)} {tostring(result.reason)}, {result.coins} Coins, {result.grip} Grip`
				)
			end
			grip += result.grip
		end
		expect.equal(world.profile.coins, coinsEach * SQ.bucketCapacity)
		expect.equal(world.profile.grip.total, grip)
		expect.equal(world.profile.stats.squeezes, SQ.bucketCapacity)
		expect.equal(#world.squeezed, SQ.bucketCapacity)
		finish()
	end)

	t.test("one press over the bucket: squeeze.tooFast, no Coins, no Grip, no stats", function()
		local world = fresh()
		local replies = click(world, SQ.bucketCapacity, 0) -- the bucket's burst at once: all pay
		for _, result in replies do
			expect.equal(result.ok, true)
		end
		local coins, grip = world.profile.coins, world.profile.grip.total
		local limit = world.profile.squeezeLimit.value
		local over = SqueezeService.request(world.player)
		expect.equal(over.ok, false)
		expect.equal(over.reason, "squeeze.tooFast")
		expect.equal(over.coins, 0)
		expect.equal(over.grip, 0)
		expect.equal(world.profile.coins, coins)
		expect.equal(world.profile.grip.total, grip)
		expect.equal(world.profile.squeezeLimit.value, limit)
		expect.equal(world.profile.stats.squeezes, SQ.bucketCapacity)
		expect.equal(#world.squeezed, SQ.bucketCapacity)
		-- One cycle later the cap has a token again.
		wait(world, SQ.cycleSeconds)
		expect.equal(SqueezeService.request(world.player).ok, true)
		finish()
	end)

	t.test(
		"holding (one press every Hold.repeatSeconds) for a minute: every press pays the squeeze value of the pen",
		function()
			local world = fresh()
			local spacing = Config.Grip.Hold.repeatSeconds
			local count = math.floor(60 / spacing)
			local replies, dropped = click(world, count, spacing)
			expect.equal(dropped, 0)
			expect.equal(#replies, count)
			for i, result in replies do
				if not result.ok then
					error(`press {i}: {tostring(result.reason)}`)
				end
			end
			expect.equal(world.profile.stats.squeezes, count)
			expect.equal(world.profile.coins, count * valueOf(world))
			finish()
		end
	)

	t.test(
		"clicking at 12 per second for a minute pays only the hold rhythm: no Coins and no Grip for the rest",
		function()
			local world = fresh()
			local replies, dropped = click(world, 60 * 12, 1 / 12)
			expect.equal(dropped, 0)
			local paid = 0
			for i, result in replies do
				if result.ok then
					paid += 1
				elseif result.reason ~= "squeeze.tooFast" or result.coins ~= 0 or result.grip ~= 0 then
					error(`press {i}: {tostring(result.reason)}, {result.coins} Coins, {result.grip} Grip`)
				end
			end
			local cap = SQ.bucketCapacity + math.floor(60 / SQ.cycleSeconds + 1e-6)
			expect.truthy(paid <= cap)
			expect.truthy(paid >= cap - 2)
			expect.equal(world.profile.coins, paid * valueOf(world))
			expect.equal(world.profile.stats.squeezes, paid)
			expect.equal(SqueezeService.counts().dropped, 0)
			finish()
		end
	)

	t.test("a steady 20 requests per second is never dropped by the flood guard", function()
		local world = fresh()
		local count = 30 * SQ.floodPerSecond
		local replies, dropped = click(world, count, 1 / SQ.floodPerSecond)
		expect.equal(dropped, 0)
		expect.equal(#replies, count)
		finish()
	end)

	t.test(
		"a 25/s macro: at most 1 accepted per cycleSeconds after the bucket, the excess above 20/s dropped",
		function()
			local world = fresh()
			local seconds = 30
			local replies, dropped = click(world, seconds * 25, 1 / 25)
			local accepted = 0
			for _, result in replies do
				if result.ok then
					accepted += 1
				else
					expect.equal(result.reason, "squeeze.tooFast")
					expect.equal(result.coins, 0)
					expect.equal(result.grip, 0)
				end
			end
			local perSecond = 1 / SQ.cycleSeconds
			expect.truthy(accepted <= SQ.bucketCapacity + math.floor(seconds * perSecond + 1e-6))
			expect.truthy(accepted >= math.floor(seconds * perSecond) - 1)
			expect.truthy(dropped > 0) -- the flood guard dropped the excess silently
			expect.equal(#replies, accepted + (SqueezeService.counts().rejected["squeeze.tooFast"] or 0))
			expect.equal(world.profile.stats.squeezes, accepted)
			finish()
		end
	)

	t.test("no hourly limit: 400 squeezes from a nearly empty limit state all pay Coins and Grip", function()
		local world = fresh()
		world.profile.squeezeLimit = { value = 5, at = UNIX_START }
		local replies = click(world, 400, SQ.cycleSeconds)
		local coinsEach = valueOf(world)
		expect.equal(#replies, 400)
		for i, result in replies do
			if not result.ok or result.coins ~= coinsEach or result.grip <= 0 then
				error(`squeeze {i}: ok {tostring(result.ok)} {tostring(result.reason)}, {result.coins} Coins`)
			end
		end
		expect.equal(world.profile.coins, 400 * coinsEach)
		expect.equal(world.profile.stats.squeezes, 400)
		finish()
	end)

	t.test("exactly one Double Grip point per accepted squeeze", function()
		local world = fresh()
		world.profile.grip.rested = { value = 10, at = UNIX_START }
		local base = gripOf(world)
		for i = 1, 3 do
			local result = SqueezeService.request(world.player)
			expect.equal(result.ok, true)
			expect.equal(result.doubled, REST.enabled)
			expect.equal(result.grip, if REST.enabled then base * REST.mult else base)
			expect.near(world.profile.grip.rested.value, if REST.enabled then 10 - i else 10, 1e-6)
			-- Only the clocks of the bucket move: Double Grip gets no refill in between.
			world.clock.advance(SQ.cycleSeconds)
			world.server.advance(SQ.cycleSeconds)
		end
		finish()
	end)

	t.test("an OFFLINE or loading profile earns nothing", function()
		for _, status in { "offline", "loading", "readonly" } do
			local world = fresh()
			world.status = status
			local result = SqueezeService.request(world.player)
			expect.equal(result.ok, false)
			expect.equal(result.reason, "data.notReady")
			expect.equal(world.profile.coins, 0)
			expect.equal(world.profile.grip.total, 0)
			expect.equal(world.profile.stats.squeezes, 0)
			expect.equal(#world.squeezed, 0)
			finish()
		end
	end)

	t.test("a session that takes no more changes (final save started) earns nothing: data.notReady", function()
		local world = fresh()
		world.frozen = true -- still "ready", but DataService.mutate refuses every change now
		local result = SqueezeService.request(world.player)
		expect.equal(result.ok, false)
		expect.equal(result.reason, "data.notReady")
		expect.equal(result.coins, 0)
		expect.equal(result.grip, 0)
		expect.equal(world.profile.coins, 0)
		expect.equal(world.profile.grip.total, 0)
		expect.equal(world.profile.stats.squeezes, 0)
		expect.equal(world.profile.squeezeLimit.value, LIMIT.burst)
		expect.equal(world.squeezeAt, nil)
		expect.equal(#world.squeezed, 0)
		finish()
	end)

	t.test("nextAt is in server time", function()
		local world = fresh()
		local first = SqueezeService.request(world.player)
		expect.truthy(first.nextAt > 1e9) -- a GetServerTimeNow() value, not os.clock()
		expect.near(first.nextAt, world.server.now(), 1e-6) -- tokens are still there
		local last = first
		for _ = 2, SQ.bucketCapacity do
			last = SqueezeService.request(world.player)
		end
		expect.equal(last.ok, true)
		expect.near(last.nextAt, world.server.now() + SQ.cycleSeconds, 1e-6) -- the cap's bucket is empty
		local rejected = SqueezeService.request(world.player)
		expect.equal(rejected.reason, "squeeze.tooFast")
		expect.near(rejected.nextAt, world.server.now() + SQ.cycleSeconds, 1e-6)
		wait(world, SQ.cycleSeconds / 2)
		local later = SqueezeService.request(world.player)
		expect.equal(later.ok, false)
		expect.near(later.nextAt, world.server.now() + SQ.cycleSeconds / 2, 1e-6)
		finish()
	end)

	t.test(
		"a dead or missing character (squeeze.noCharacter) or a player in a match: rejected, nothing earned",
		function()
			local world = fresh()
			-- One request per second, so the flood guard never drops one.
			local function ask(): any
				wait(world, 1)
				return SqueezeService.request(world.player)
			end
			world.alive = false
			expect.equal(ask().reason, "squeeze.noCharacter")
			world.alive = true
			world.position = nil
			expect.equal(ask().reason, "squeeze.noCharacter")
			world.position = onStation("squeeze_01")
			world.phase = "Preparing"
			local inMatch = ask()
			expect.equal(inMatch.ok, false)
			expect.equal(inMatch.reason, "squeeze.inDuel")
			expect.equal(world.profile.grip.total, 0)
			expect.equal(world.profile.coins, 0)
			expect.equal(#world.squeezed, 0)
			-- Back in the lobby it works.
			world.phase = ""
			expect.equal(ask().ok, true)
			finish()
		end
	)

	t.test("a stale station is disabled: no boost for squeezes there (the base is paid)", function()
		local world = fresh()
		local problems = SqueezeService.applyStationCheck(function(id: string): (boolean, unknown)
			if id == "squeeze_02" then
				return true, 2 -- the lobby says tier 2, WorldLayout says 1
			elseif id == "squeeze_03" then
				return false, nil -- missing from the lobby
			end
			return true, WorldLayout.stationTier(id)
		end, { "squeeze_10" })
		local kinds: { [string]: string } = {}
		for _, problem in problems do
			kinds[problem.id] = problem.kind
		end
		expect.deepEqual(kinds, { squeeze_02 = "stale", squeeze_03 = "missing", squeeze_10 = "unknown" })
		expect.truthy(SqueezeService.isStationDisabled("squeeze_02"))
		expect.truthy(SqueezeService.isStationDisabled("squeeze_03"))
		expect.falsy(SqueezeService.isStationDisabled("squeeze_01"))
		world.position = onStation("squeeze_02")
		expectBase(world, SqueezeService.request(world.player))
		finish()
	end)

	t.test("paid squeezes above squeezeAlertPerHour in a rolling hour: one alert (log only), re-armed after", function()
		local world = fresh()
		local each = valueOf(world)
		local alertAt = Config.Grip.squeezeAlertPerHour
		expect.equal(alertAt, 3600 / SQ.cycleSeconds) -- Batch 1 #2: the paid cap's whole hour (exactly 8000)
		local function alerts(): number
			return SqueezeService.counts().squeezeAlerts
		end
		-- Rides the paid cap from 0.1 s into a minute (the alert counts whole minutes): the bucket, then one press per
		-- cycleSeconds, alertAt paid squeezes in all inside 60 whole minutes (one more a cycle later still lands 0.35 s
		-- before the last of them ends).
		local function ride()
			local now = world.clock.now()
			wait(world, (math.floor(now / 60) + 1) * 60 + 0.1 - now)
			click(world, SQ.bucketCapacity, 0)
			wait(world, SQ.cycleSeconds)
			click(world, alertAt - SQ.bucketCapacity, SQ.cycleSeconds)
		end
		ride() -- the hour's paid squeezes reach the alert, not above it
		expect.equal(world.profile.stats.squeezes, alertAt)
		expect.equal(alerts(), 0)
		wait(world, SQ.cycleSeconds)
		local over = SqueezeService.request(world.player)
		expect.equal(over.ok, true)
		expect.equal(over.coins, each) -- log only: it still pays
		expect.equal(alerts(), 1)
		click(world, 24, SQ.cycleSeconds) -- no second line
		expect.equal(alerts(), 1)
		-- An hour later the counter has emptied (re-armed): crossing again logs again.
		wait(world, 3600)
		ride()
		wait(world, SQ.cycleSeconds)
		expect.equal(SqueezeService.request(world.player).ok, true)
		expect.equal(alerts(), 2)
		finish()
	end)

	t.test("a lobby that matches WorldLayout disables nothing", function()
		fresh()
		local problems = SqueezeService.checkStations(function(id: string): (boolean, unknown)
			return true, WorldLayout.stationTier(id)
		end)
		expect.equal(#problems, 0)
		finish()
	end)

	-- Auto-clicker check (2026-10-16) --------------------------------------------------------------------------------

	t.test(
		"AutoClickService is asked first, with the arrival time; its reason is the reply and costs nothing",
		function()
			local asked: { number } = {}
			local answer: string? = "squeeze.autoClick"
			local world = fresh(function(_player: any, now: number): string?
				table.insert(asked, now)
				return answer
			end)
			local refused = SqueezeService.request(world.player)
			expect.deepEqual(asked, { world.clock.now() })
			expect.equal(refused.ok, false)
			expect.equal(refused.reason, "squeeze.autoClick")
			expect.equal(refused.coins, 0)
			expect.equal(refused.grip, 0)
			expect.near(refused.nextAt, world.server.now(), 1e-6) -- the paid cap's tokens are all still there
			answer = "squeeze.tooFast" -- the penalty
			expect.equal(SqueezeService.request(world.player).reason, "squeeze.tooFast")
			expect.equal(world.profile.coins, 0)
			expect.equal(world.profile.grip.total, 0)
			expect.equal(world.profile.stats.squeezes, 0)
			expect.equal(#world.squeezed, 0)
			expect.equal(world.squeezeAt, nil)
			-- Let through again: the whole bucket pays at once (the refusals used no token).
			answer = nil
			local replies = click(world, SQ.bucketCapacity, 0)
			for _, result in replies do
				expect.equal(result.ok, true)
			end
			expect.equal(world.profile.stats.squeezes, SQ.bucketCapacity)
			finish()
		end
	)

	-- A world whose SqueezeService asks the real AutoClickService, on the test's clocks; its kicks and bans are only
	-- counted, never real.
	local function wiredWorld(): (World, { kicks: number, bans: number })
		local AutoClickService = t.requireServer("Services/AutoClickService")
		local world = fresh(AutoClickService.check)
		local seen = { kicks = 0, bans = 0 }
		AutoClickService.reset()
		AutoClickService.useDeps({
			unixNow = world.unix.now,
			isStudio = function(): boolean
				return false
			end,
			profileOf = function(): any
				return world.profile
			end,
			mutate = function(_player: any, fn: (profile: any) -> any): (boolean, any)
				return true, fn(world.profile)
			end,
			requestSave = function() end,
			banningEnabled = function(): boolean
				return true
			end,
			ban = function(): (boolean, string?)
				seen.bans += 1
				return true, nil
			end,
			kick = function(): (boolean, string?)
				seen.kicks += 1
				return true, nil
			end,
			inGame = function(): boolean
				return false
			end,
			later = function(fn: () -> ())
				fn()
			end,
			rules = function(): any
				local copy = table.clone(Config.Net.AutoClick)
				copy.enforce = "full" -- the owner's steps (review fix 2026-10-16: the live value starts at "log")
				return copy
			end,
		})
		return world, seen
	end

	local function unwire()
		local AutoClickService = t.requireServer("Services/AutoClickService")
		AutoClickService.reset()
		AutoClickService.useDeps(nil)
		finish()
	end

	t.test(
		"wired: a steady 10/s macro is caught once (squeeze.autoClick), then pays nothing during the penalty",
		function()
			local world, seen = wiredWorld()
			local AUTO = Config.Net.AutoClick
			local perSecond = 10
			local replies = click(world, 60 * perSecond, 1 / perSecond)
			local caughtAt: number? = nil
			local warnings = 0
			for i, result in replies do
				if result.reason == "squeeze.autoClick" then
					warnings += 1
					caughtAt = caughtAt or i
				end
			end
			expect.equal(warnings, 1) -- one short warning; the penalty is silent (squeeze.tooFast)
			local index = caughtAt :: number
			expect.truthy(index ~= nil and index <= AUTO.windowIntervals + 1) -- rule B's first window
			for i = index + 1, #replies do
				if replies[i].ok then
					error(`press {i} paid during the penalty`) -- the 20 s after the catch are inside the 30 s penalty
				end
			end
			expect.equal(world.profile.autoClick.step, 1)
			expect.near(world.profile.autoClick.at, world.unix.now() - (#replies - index) / perSecond, 1e-3)
			expect.equal(seen.kicks, 0) -- step 1 only warns
			expect.equal(seen.bans, 0)
			unwire()
		end
	)

	t.test("p13v3: the speed report a SqueezeRequest carries reaches AutoClickService (the speed rule)", function()
		local handed: { any } = {}
		local world = fresh(function(_player: any, _now: number, fastSeconds: number?): string?
			table.insert(handed, fastSeconds or "none")
			return nil
		end)
		SqueezeService.request(world.player, 3)
		SqueezeService.request(world.player, 0)
		expect.deepEqual(handed, { 3, 0 })
		-- The handler init registers hands it on too (captured from NetService.on, init stopped right there).
		local NetService: any = t.requireServer("Services/NetService")
		local real = NetService.on
		local handlers: { [string]: any } = {}
		NetService.on = function(name: string, handler: any)
			handlers[name] = handler
			error("captured")
		end
		local ok, why = pcall(SqueezeService.init)
		NetService.on = real
		expect.falsy(ok)
		expect.truthy(string.find(tostring(why), "captured", 1, true) ~= nil)
		handlers.SqueezeRequest(world.player, 5)
		expect.deepEqual(handed, { 3, 0, 5 })
		finish()
	end)

	t.test(
		"p13v3 wired: 36 presses a second through the client's 18 sends is caught once (squeeze.superFast)",
		function()
			local world = wiredWorld()
			local PressSpeed = t.requireShared("PressSpeed")
			local sends = Config.Net.AutoClick.clientPressesPerSecond
			local client = PressSpeed.new()
			local warnings, first, sent = 0, nil, 0
			for i = 1, 10 * 2 * sends do -- 36 presses a second, every 2nd one sent with its report
				PressSpeed.press(client, world.clock.now())
				if i % 2 == 0 then
					local result = SqueezeService.request(world.player, client.peak)
					PressSpeed.sent(client)
					sent += 1
					if result ~= nil and result.reason == "squeeze.superFast" then
						warnings += 1
						first = first or sent
					end
				end
				wait(world, 1 / (2 * sends))
			end
			expect.equal(warnings, 1)
			expect.truthy(first ~= nil and first <= 4 * sends) -- inside the first 4 s
			expect.equal(world.profile.autoClick.step, 1)
			unwire()
		end
	)

	t.test("wired: holding for a minute (the hold rhythm) is never judged and every press pays", function()
		local world = wiredWorld()
		local spacing = Config.Grip.Hold.repeatSeconds
		local count = math.floor(60 / spacing)
		local replies = click(world, count, spacing)
		for i, result in replies do
			if not result.ok then
				error(`press {i}: {tostring(result.reason)}`)
			end
		end
		expect.equal(world.profile.stats.squeezes, count)
		expect.equal(world.profile.autoClick, nil) -- no strike was ever written
		unwire()
	end)
end
