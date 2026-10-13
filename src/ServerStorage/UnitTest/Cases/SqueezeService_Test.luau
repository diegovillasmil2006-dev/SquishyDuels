--!strict
-- SqueezeService_Test: unit tests for ServerScriptService.Server.Services.SqueezeService (and its GripService step 8a)
-- with injected fakes: fake clocks, a fake profile, fake positions; the "player" is a plain table. Server only
-- (ServerStorage.UnitTest). Edit mode: init() is never called, so no remote is touched.
-- Contract (DESIGN §6.3, §17.3.1 steps 6a / 8a, §17.6, §17.10, §17.12 Part 5 "SqueezeService with fakes"; squeeze
-- anywhere, spec 2026-10-11 §5):
--   * SqueezeRequest takes no argument: the server finds the pad under its own root position (SqueezeRules.padUnder)
--     and ignores anything the client sends;
--   * an accepted squeeze on a mat pays the squeeze value (Phase 3, spec 2026-10-12 §3: the best capsule's
--     CapsuleMath.squeezeValue, whatever squishy is held or pad stood on), trains the highest capsule level's power,
--     counts stats.squeezes, sets SD_SqueezeAt (server time), fires Squeezed and replies ok; a paid one pushes the
--     capsules with the server's own root position (CapsuleService.push decides whether that is home);
--   * off every pad, on a pad still locked for the player's level, on a pad the lobby does not have or one the
--     stale-lobby check disabled, the squeeze pays the same and reports tier 1 (Squeezed with tier 1);
--     only a dead character is refused (squeeze.noCharacter), and a player in a match;
--   * the shipped hourly limit is off: every accepted squeeze pays (with the limit switched on, an empty one would give
--     0 Coins while Grip still rises);
--   * every click pays (2026-10-06): 12 presses in 1 s all pay Coins and Grip; a 13th in the same second is
--     squeeze.tooFast with no Coins, no Grip and no stats; clicking at 12/s for a minute pays every press; a steady
--     20 requests/s is never dropped; a 25/s macro is capped at 12 accepted per second (after the burst) and its
--     excess above 20/s is dropped silently;
--   * exactly 1 Double Grip point is used per accepted squeeze;
--   * an OFFLINE profile earns nothing (data.notReady), nor does a session whose final save started (mutate refuses);
--   * nextAt is in server time: serverNow + max(0, 1 - tokens) x cycleSeconds;
--   * the stale-lobby check disables a station whose GripTier disagrees with WorldLayout (no boost, no slow training);
--   * one player's paid squeezes above Config.Grip.squeezeAlertPerHour in a rolling hour log one [SD][abuse] warning
--     (spec 2026-10-12 §12; log only: the squeezes still pay); the alert re-arms once the hour's squeezes are back
--     under it.

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
	local CapsuleMath = t.requireShared("CapsuleMath")
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
		pushes: { Vector3 }, -- CapsuleService.push calls (the root positions)
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
				trainer = 1,
				rested = { value = 0, at = UNIX_START },
				afk = { value = Config.Grip.Afk.burst, at = UNIX_START },
			},
			capsules = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } }, -- a new player's
		}
	end

	-- What one own squeeze pays this profile (Phase 3): the squeeze value and the highest capsule level's power.
	local function valueOf(world: any): number
		return CapsuleMath.squeezeValue(world.profile.capsules)
	end
	local function gripOf(world: any): number
		return CapsuleMath.squeezeGrip(world.profile.capsules)
	end

	local function fresh(): World
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
			pushes = {},
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
			rootOf = rootOf,
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
			pushCapsules = function(_player: any, rootPosition: Vector3)
				table.insert(world.pushes, rootPosition)
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

	local function setLevel(world: World, level: number)
		world.profile.grip.total = Config.Grip.LevelTotals[level]
		GripService.refreshBaseline(world.player, false)
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
		expect.deepEqual(world.pushes, { world.position }) -- a paid squeeze pushes the capsules from the server's root
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

	t.test("own squeezes pay the best capsule's value and the highest level's power (x mult doubled)", function()
		local world = fresh()
		-- Lv 21 Toast: 461 × 1; Lv 5 Dragon: 16 × 64 = 1,024 (the best); an empty Lv 30 capsule: the highest level.
		local list: { any } =
			{ { level = 21, squishyId = "toast" }, { level = 5, squishyId = "dragon" }, { level = 30 } }
		world.profile.capsules = { slots = 3, list = list }
		local plain = SqueezeService.request(world.player)
		expect.equal(plain.coins, 1_024)
		expect.equal(plain.grip, CapsuleMath.power(30))
		expect.equal(plain.doubled, false)
		world.profile.grip.rested = { value = 1, at = UNIX_START }
		world.clock.advance(SQ.cycleSeconds)
		world.server.advance(SQ.cycleSeconds)
		local doubled = SqueezeService.request(world.player)
		expect.equal(doubled.coins, 1_024) -- Double Grip doubles Grip only
		expect.equal(doubled.doubled, REST.enabled)
		expect.equal(doubled.grip, (CapsuleMath.power(30) :: number) * (if REST.enabled then REST.mult else 1))
		finish()
	end)

	t.test("a refused squeeze pushes no capsule; a paid one pushes with the server's root, not the client's", function()
		local world = fresh()
		world.phase = "Active" -- in a match: squeeze.inDuel
		expect.equal(SqueezeService.request(world.player).reason, "squeeze.inDuel")
		world.phase = ""
		world.alive = false
		world.clock.advance(1)
		expect.equal(SqueezeService.request(world.player).reason, "squeeze.noCharacter")
		expect.equal(#world.pushes, 0)
		world.alive = true
		world.position = Vector3.new(5, 3, -120) -- anywhere: CapsuleService decides whether it is home
		world.clock.advance(1)
		local forged = (SqueezeService.request :: any)(world.player, Vector3.zero)
		expect.equal(forged.ok, true)
		expect.deepEqual(world.pushes, { Vector3.new(5, 3, -120) })
		finish()
	end)

	-- Squeeze anywhere (spec 2026-10-11 §5) ---------------------------------------------------------------------------

	-- One accepted squeeze that paid the base (tier 1; Phase 3: every squeeze pays the squeeze value and the highest
	-- capsule level's Grip, so only the tier the quests see differs).
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

	t.test("a pad still locked for the player's level pays the base, never its bonus", function()
		local world = fresh()
		world.position = onStation("squeeze_09") -- the Royal Cushion (tier 4) at Lv 1
		expectBase(world, SqueezeService.request(world.player))
		finish()
	end)

	t.test(
		"the client's station id is ignored: the pad is the server's own (an extra argument changes nothing)",
		function()
			local world = fresh()
			setLevel(world, Config.Grip.Pads[#Config.Grip.Pads].level)
			world.position = onStation("squeeze_01")
			local forged = (SqueezeService.request :: any)(world.player, "squeeze_09")
			expect.equal(forged.ok, true)
			expect.equal(forged.coins, valueOf(world))
			expect.equal(world.squeezed[1].tier, 1)
			finish()
		end
	)

	t.test("a pad the lobby does not have gives no boost: the base is paid", function()
		local world = fresh()
		setLevel(world, Config.Grip.Pads[3].level)
		world.position = onStation("squeeze_08")
		world.untagged.squeeze_08 = true
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

	-- Every click pays (2026-10-06) ---------------------------------------------------------------------------------

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

	t.test("12 presses in 1 s all pay Coins and Grip", function()
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

	t.test("a 13th press in the same second: squeeze.tooFast, no Coins, no Grip, no stats", function()
		local world = fresh()
		local replies = click(world, SQ.bucketCapacity, 0) -- a burst of 12 at once: all pay
		for _, result in replies do
			expect.equal(result.ok, true)
		end
		local coins, grip = world.profile.coins, world.profile.grip.total
		local limit = world.profile.squeezeLimit.value
		local thirteenth = SqueezeService.request(world.player)
		expect.equal(thirteenth.ok, false)
		expect.equal(thirteenth.reason, "squeeze.tooFast")
		expect.equal(thirteenth.coins, 0)
		expect.equal(thirteenth.grip, 0)
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

	t.test("clicking at 12 per second for a minute: every press pays, nothing is dropped", function()
		local world = fresh()
		local count = 60 * SQ.bucketCapacity
		local replies, dropped = click(world, count, SQ.cycleSeconds)
		expect.equal(dropped, 0)
		expect.equal(#replies, count)
		for i, result in replies do
			if not result.ok then
				error(`press {i}: {tostring(result.reason)}`)
			end
		end
		expect.equal(world.profile.stats.squeezes, count)
		expect.equal(SqueezeService.counts().dropped, 0)
		finish()
	end)

	t.test("a steady 20 requests per second is never dropped by the flood guard", function()
		local world = fresh()
		local count = 30 * SQ.floodPerSecond
		local replies, dropped = click(world, count, 1 / SQ.floodPerSecond)
		expect.equal(dropped, 0)
		expect.equal(#replies, count)
		finish()
	end)

	t.test("a 25/s macro: at most 12 accepted per second after the burst, the excess above 20/s dropped", function()
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
	end)

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

	-- Phase 3 (spec 2026-10-12 §3, §10): was "pays the Coin bonus and its Grip percent"; pads stay until Phase 6.
	t.test("the Marshmallow Pad at its level pays like anywhere else and still reports its tier", function()
		local world = fresh()
		setLevel(world, Config.Grip.Pads[3].level)
		local gripBefore = world.profile.grip.total
		world.position = onStation("squeeze_08")
		local result = SqueezeService.request(world.player)
		expect.equal(result.ok, true)
		expect.equal(result.coins, valueOf(world))
		expect.equal(result.grip, gripOf(world))
		expect.equal(world.profile.grip.total, gripBefore + result.grip)
		expect.equal(world.squeezed[1].tier, 3) -- the quests (starter_jelly) still see the pad
		finish()
	end)

	t.test(
		"a stale station is disabled: no boost for squeezes there (the base is paid) and no slow training",
		function()
			local world = fresh()
			setLevel(world, Config.Grip.Pads[2].level)
			local problems = SqueezeService.applyStationCheck(function(id: string): (boolean, unknown)
				if id == "squeeze_07" then
					return true, 1 -- the lobby says tier 1, WorldLayout says 2
				elseif id == "squeeze_03" then
					return false, nil -- missing from the lobby
				end
				return true, WorldLayout.stationTier(id)
			end, { "squeeze_10" })
			local kinds: { [string]: string } = {}
			for _, problem in problems do
				kinds[problem.id] = problem.kind
			end
			expect.deepEqual(kinds, { squeeze_07 = "stale", squeeze_03 = "missing", squeeze_10 = "unknown" })
			expect.truthy(SqueezeService.isStationDisabled("squeeze_07"))
			expect.truthy(SqueezeService.isStationDisabled("squeeze_03"))
			expect.truthy(GripService.isStationDisabled("squeeze_07"))
			expect.falsy(SqueezeService.isStationDisabled("squeeze_01"))
			world.position = onStation("squeeze_07")
			expectBase(world, SqueezeService.request(world.player))
			-- Slow training skips it too.
			GripService.tick(world.player)
			wait(world, Config.Grip.Afk.tickSeconds)
			expect.equal(GripService.tick(world.player).reason, "offPad")
			finish()
		end
	)

	t.test("paid squeezes above squeezeAlertPerHour in a rolling hour: one alert (log only), re-armed after", function()
		local world = fresh()
		local each = valueOf(world)
		local crossing = Config.Grip.squeezeAlertPerHour + 1 -- the squeeze that takes the hour above the alert
		local function alerts(): number
			return SqueezeService.counts().squeezeAlerts
		end
		click(world, crossing - 1, SQ.cycleSeconds) -- the hour's paid squeezes reach the alert, not above it
		expect.equal(world.profile.stats.squeezes, crossing - 1)
		expect.equal(alerts(), 0)
		wait(world, SQ.cycleSeconds)
		local over = SqueezeService.request(world.player)
		expect.equal(over.ok, true)
		expect.equal(over.coins, each) -- log only: it still pays
		expect.equal(alerts(), 1)
		click(world, 24, SQ.cycleSeconds) -- still above: no second line
		expect.equal(alerts(), 1)
		-- An hour later the counter has emptied (re-armed): crossing again logs again.
		wait(world, 3600)
		click(world, crossing, SQ.cycleSeconds)
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
end
