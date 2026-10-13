--!strict
-- GripService_Test: unit tests for ServerScriptService.Server.Services.GripService with injected fakes (fake clocks,
-- a fake profile, fake positions; the "player" is a plain table). Server only (ServerStorage.UnitTest). Edit mode:
-- start() is never called; ticks run through GripService.tick.
-- Contract (DESIGN §17.3.1 step 8a, §17.3.4, §17.3.6, §17.7, §17.12 Part 5 "GripService slow training with fakes"):
--   * slow training: off any pad -> 0; on a locked pad -> 0; first tick on a pad -> 0, second ->
--     floor(squeezeGrip x percentPerTick / 100); in a match, dead or OFFLINE -> 0; an accepted squeeze in the window ->
--     0; an empty bank -> 0 and the bank refills perHour; 30 minutes nonstop pay exactly what SqueezeLimit predicts; a
--     tick never changes Coins, quests, stats.squeezes or grip.rested; a disabled station pays nothing; an AFK-only
--     profile that reaches Lv 5 through ticks keeps its starter progress and Coins;
--   * a squeeze uses exactly one Double Grip point and doubles its Grip; no point, no doubling; nothing when not ready
--     or when the session takes no more changes (every write goes through mutate); the total stops at maxGrip and the
--     gain says what it really gained; step() drops the session of a player who already left;
--   * Phase 3 (spec 2026-10-12 §3, §10): an own squeeze trains the power of the highest capsule level (an empty
--     capsule counts; 10 without capsules), whatever the trainer or the pad; a capsule squeeze (addFromCapsule) trains
--     its power, never doubled and without a Double Grip point; Grip events above gripAlertPerHour in a rolling hour
--     set the anomaly alert, which re-arms an hour later;
--   * a load sets the level silently (no level-up or rank-up toast), with grip.headStart after a v1 -> v2 migration;
--     grip.welcomeBack only when Double Grip grew by welcomeBackMinGain since the last save (lastSeenAt, §17.3.4);
--   * a level-up toasts grip.levelUp and grip.padUnlocked, broadcasts grip.rankUp to the lobby players and asks for a
--     "soon" save;
--   * Part 7 trainer upgrades (§17.5, §17.12): a buy charges once ("trainer"), sets grip.trainer, toasts
--     grip.trainerBought, awaits one "now" save and replies {trainer, charged = true, savePending}; an identical retry
--     is a replay (charged = false, no charge); every refusal code with charged = false: net.invalid (range, before
--     the ready check), data.notReady, trainer.notNext (8 at trainer 1), trainer.locked, trainer.priceChanged,
--     trainer.paused (savePending, closing, restart), inventory.lockedInDuel, economy.notEnoughCoins; an AFK-only
--     profile that reaches Lv 5 through ticks keeps its starter progress and Coins with QuestService wired.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local GripService = t.requireServer("Services/GripService")
	local FakeClock = t.requireFake("FakeClock")
	local CapsuleMath = t.requireShared("CapsuleMath")
	local Config = t.requireShared("Config")
	local GripMath = t.requireShared("GripMath")
	local SqueezeLimit = t.requireShared("SqueezeLimit")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local TableUtil = t.requireShared("Util/TableUtil")

	local AFK = Config.Grip.Afk
	local REST = Config.Grip.Rested
	local UNIX_START = 1_800_000_000

	type World = {
		clock: any,
		unix: any,
		player: any,
		status: string,
		profile: any,
		position: Vector3?,
		alive: boolean,
		phase: string,
		closing: boolean,
		frozen: boolean, -- the session takes no more changes (its final save took its snapshot): mutate refuses
		dirty: { string },
		saves: { string },
		notices: { { player: any, code: string, args: any } },
		levelAttr: number?,
		levelChanges: { { old: number, new: number, silent: boolean } },
		migratedFrom: number?,
		lobby: { any },
		-- Part 7 (the trainer purchase)
		savePending: boolean,
		restart: boolean,
		saveOk: boolean,
		nowSaves: number,
		spends: { { amount: number, reason: string } },
	}

	-- A standing root position over a station (its top + 3 studs, like an R15 root).
	local function onStation(id: string): Vector3
		local station = WorldLayout.station(id)
		return Vector3.new(station.position.X, station.top + 3, station.position.Z)
	end

	local function newProfile(unixNow: number): any
		return {
			coins = 50,
			stats = { squeezes = 7, coinsEarned = 50 },
			quests = { day = 3, swapsUsed = 0, active = { { id = "q3_1", progress = 1, goal = 5, done = false } } },
			starter = { progress = { squeeze = 2 }, claimed = {} },
			grip = {
				total = 0,
				trainer = 1,
				rested = { value = 0, at = unixNow },
				afk = { value = AFK.burst, at = unixNow },
			},
			capsules = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } }, -- a new player's
		}
	end

	-- Grip of one own squeeze for this profile (Phase 3: the highest capsule level's power).
	local function ownGrip(world: any): number
		return CapsuleMath.squeezeGrip(world.profile.capsules)
	end

	local function fresh(): World
		local world: World = {
			clock = FakeClock.new(1000),
			unix = FakeClock.new(UNIX_START),
			player = { UserId = 42, DisplayName = "Tester" },
			status = "ready",
			profile = newProfile(UNIX_START),
			position = onStation("squeeze_01"),
			alive = true,
			phase = "",
			closing = false,
			frozen = false,
			dirty = {},
			saves = {},
			notices = {},
			levelAttr = nil,
			levelChanges = {},
			migratedFrom = nil,
			lobby = {},
			savePending = false,
			restart = false,
			saveOk = true,
			nowSaves = 0,
			spends = {},
		}
		world.lobby = { world.player }
		GripService.reset()
		GripService.LevelChanged:disconnectAll()
		GripService.LevelChanged:connect(function(_player: any, old: number, new: number, silent: boolean)
			table.insert(world.levelChanges, { old = old, new = new, silent = silent })
		end)
		GripService.useDeps({
			clock = world.clock.now,
			unixNow = world.unix.now,
			statusOf = function(_player: any): string
				return world.status
			end,
			profileOf = function(_player: any): any
				return world.profile
			end,
			-- Like DataService.mutate: a READY session that still takes changes only.
			mutate = function(_player: any, fn: (profile: any) -> any): (boolean, any)
				if world.status ~= "ready" or world.frozen then
					return false, "data.notReady"
				end
				return true, fn(world.profile)
			end,
			rootOf = function(_player: any): (Vector3?, boolean)
				return world.position, world.alive
			end,
			duelPhaseOf = function(_player: any): string
				return world.phase
			end,
			isClosing = function(): boolean
				return world.closing
			end,
			markDirty = function(_player: any, field: string)
				table.insert(world.dirty, field)
			end,
			requestSave = function(_player: any, reason: string)
				table.insert(world.saves, reason)
			end,
			notify = function(player: any, code: string, args: any, _kind: string)
				table.insert(world.notices, { player = player, code = code, args = args })
			end,
			lobbyPlayers = function(): { any }
				return world.lobby
			end,
			setLevelAttribute = function(_player: any, level: number)
				world.levelAttr = level
			end,
			migratedFrom = function(_player: any): number?
				return world.migratedFrom
			end,
			displayName = function(player: any): string
				return player.DisplayName
			end,
			-- Part 7: like EconomyService.trySpend / DataService.saveNowAsync over the same fake profile.
			savePending = function(_player: any): boolean
				return world.savePending
			end,
			isRestartPending = function(): boolean
				return world.restart
			end,
			trySpend = function(_player: any, amount: number, reason: string): (boolean, string?)
				if world.status ~= "ready" or world.frozen then
					return false, "notReady"
				elseif world.savePending then
					return false, "savePending"
				elseif world.profile.coins < amount then
					return false, "notEnoughCoins"
				end
				world.profile.coins -= amount
				table.insert(world.spends, { amount = amount, reason = reason })
				return true, nil
			end,
			saveNow = function(_player: any): boolean
				world.nowSaves += 1
				return world.saveOk
			end,
		})
		GripService.playerAdded(world.player)
		return world
	end

	local function finish()
		GripService.reset()
		GripService.useDeps(nil)
		GripService.LevelChanged:disconnectAll()
	end

	-- Advances both clocks by `seconds` (the tick window and the bank).
	local function wait(world: World, seconds: number)
		world.clock.advance(seconds)
		world.unix.advance(seconds)
	end

	local function codes(world: World): { string }
		local list = {}
		for _, n in world.notices do
			table.insert(list, n.code)
		end
		return list
	end

	local function expectedAfk(trainer: number, tier: number): number
		local perSqueeze =
			math.floor(Config.Grip.Trainer[trainer].gripPerSqueeze * Config.Grip.Pads[tier].gripPercent / 100)
		return math.floor(perSqueeze * AFK.percentPerTick / 100)
	end

	-- Slow training ---------------------------------------------------------------------------------------------------

	t.test("off any pad: no slow training", function()
		local world = fresh()
		world.position = Vector3.new(0, 3, 0) -- the spawn, far from every pad
		expect.equal(GripService.tick(world.player).reason, "offPad")
		wait(world, AFK.tickSeconds)
		local result = GripService.tick(world.player)
		expect.equal(result.grip, 0)
		expect.equal(result.reason, "offPad")
		expect.equal(world.profile.grip.total, 0)
		finish()
	end)

	t.test("first tick on a pad pays nothing, the second pays floor(squeezeGrip x percentPerTick / 100)", function()
		local world = fresh()
		local first = GripService.tick(world.player)
		expect.equal(first.grip, 0)
		expect.equal(first.reason, "firstTick")
		wait(world, AFK.tickSeconds)
		local second = GripService.tick(world.player)
		expect.equal(second.reason, "paid")
		expect.equal(second.grip, expectedAfk(1, 1))
		expect.equal(second.grip, GripMath.afkGrip(1, 1))
		expect.equal(world.profile.grip.total, expectedAfk(1, 1))
		expect.truthy(table.find(world.dirty, "grip") ~= nil)
		finish()
	end)

	t.test("on a locked pad: no slow training", function()
		local world = fresh()
		world.position = onStation("squeeze_07") -- the Jelly Pad (tier 2) at Lv 1
		for _ = 1, 3 do
			local result = GripService.tick(world.player)
			expect.equal(result.grip, 0)
			expect.equal(result.reason, "locked")
			wait(world, AFK.tickSeconds)
		end
		expect.equal(world.profile.grip.total, 0)
		finish()
	end)

	t.test("an unlocked giant pad pays its tier's rate", function()
		local world = fresh()
		world.profile.grip.total = Config.Grip.LevelTotals[Config.Grip.Pads[3].level] -- Marshmallow level
		GripService.refreshBaseline(world.player, false)
		world.position = onStation("squeeze_08")
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		local result = GripService.tick(world.player)
		expect.equal(result.reason, "paid")
		expect.equal(result.grip, expectedAfk(1, 3))
		finish()
	end)

	t.test("in a match, dead or OFFLINE: no slow training", function()
		local world = fresh()
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		world.phase = "Active"
		expect.equal(GripService.tick(world.player).reason, "inMatch")
		world.phase = ""
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		world.alive = false
		expect.equal(GripService.tick(world.player).reason, "noCharacter")
		world.alive = true
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		world.status = "offline"
		expect.equal(GripService.tick(world.player).reason, "notReady")
		expect.equal(world.profile.grip.total, 0)
		finish()
	end)

	t.test("an accepted squeeze since the previous tick: no slow training", function()
		local world = fresh()
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds / 2)
		local gain = GripService.addFromSqueeze(world.player, 1)
		local afterSqueeze = world.profile.grip.total
		expect.equal(afterSqueeze, gain.grip)
		wait(world, AFK.tickSeconds / 2)
		local result = GripService.tick(world.player)
		expect.equal(result.grip, 0)
		expect.equal(result.reason, "squeezed")
		expect.equal(world.profile.grip.total, afterSqueeze)
		-- The window after that has no squeeze: it pays again.
		wait(world, AFK.tickSeconds)
		expect.equal(GripService.tick(world.player).reason, "paid")
		finish()
	end)

	t.test("an empty bank pays nothing, and it refills perHour", function()
		local world = fresh()
		world.profile.grip.afk = { value = 0, at = UNIX_START }
		GripService.tick(world.player)
		wait(world, 1)
		local empty = GripService.tick(world.player)
		expect.equal(empty.grip, 0)
		expect.equal(empty.reason, "bankEmpty")
		-- One point refills in 3600 / perHour seconds (20 s at 180/h, "3 a minute").
		wait(world, 3600 / AFK.perHour)
		local refilled = GripService.tick(world.player)
		expect.equal(refilled.reason, "paid")
		-- What the empty tick saw (1 s of refill) is left after the paid one used its whole point.
		expect.near(world.profile.grip.afk.value, AFK.perHour / 3600, 1e-6)
		finish()
	end)

	t.test("30 minutes nonstop pay exactly the ticks SqueezeLimit predicts", function()
		for _, startBank in { AFK.burst, 10 } do
			local world = fresh()
			world.profile.grip.afk = { value = startBank, at = UNIX_START }
			local predicted = { value = startBank, at = UNIX_START }
			local predictedPaid, paid = 0, 0
			local ticks = math.floor(1800 / AFK.tickSeconds)
			for i = 0, ticks do
				local result = GripService.tick(world.player)
				if i > 0 then -- the first tick on a pad never pays (and never touches the bank)
					local ok
					ok, predicted = SqueezeLimit.spend(predicted, world.unix.now(), AFK)
					if ok then
						predictedPaid += 1
					end
				end
				if result.reason == "paid" then
					paid += 1
				end
				wait(world, AFK.tickSeconds)
			end
			expect.equal(paid, predictedPaid)
			expect.equal(world.profile.grip.total, paid * expectedAfk(1, 1))
			expect.truthy(paid > 0)
			if startBank == 10 then
				expect.truthy(paid < ticks) -- the bank limited it
			end
			finish()
		end
	end)

	t.test("a tick never changes Coins, quests, starter tasks, stats.squeezes or Double Grip", function()
		local world = fresh()
		world.profile.grip.rested = { value = 37, at = UNIX_START }
		local before = TableUtil.deepCopy(world.profile)
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		expect.equal(GripService.tick(world.player).reason, "paid")
		expect.equal(world.profile.coins, before.coins)
		expect.deepEqual(world.profile.stats, before.stats)
		expect.deepEqual(world.profile.quests, before.quests)
		expect.deepEqual(world.profile.starter, before.starter)
		expect.deepEqual(world.profile.grip.rested, before.grip.rested)
		finish()
	end)

	t.test("a disabled station pays no slow-training tick", function()
		local world = fresh()
		GripService.disableStation("squeeze_01")
		expect.truthy(GripService.isStationDisabled("squeeze_01"))
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		local result = GripService.tick(world.player)
		expect.equal(result.grip, 0)
		expect.equal(result.reason, "offPad")
		finish()
	end)

	t.test("walking from one pad to another restarts the count", function()
		local world = fresh()
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		world.position = onStation("squeeze_02")
		expect.equal(GripService.tick(world.player).reason, "firstTick")
		wait(world, AFK.tickSeconds)
		expect.equal(GripService.tick(world.player).reason, "paid")
		finish()
	end)

	t.test("an AFK-only profile that reaches Lv 5 through ticks keeps its starter progress and Coins", function()
		local world = fresh()
		local target = Config.Grip.LevelTotals[5]
		world.profile.grip.total = target - 1
		GripService.refreshBaseline(world.player, false)
		local before = TableUtil.deepCopy(world.profile)
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		expect.equal(GripService.tick(world.player).reason, "paid")
		expect.equal(GripService.levelOf(world.player), 5)
		expect.equal(world.levelAttr, 5)
		expect.equal(world.profile.coins, before.coins)
		expect.deepEqual(world.profile.starter, before.starter)
		expect.deepEqual(world.profile.quests, before.quests)
		expect.equal(world.profile.stats.squeezes, before.stats.squeezes)
		expect.truthy(table.find(codes(world), "grip.levelUp") ~= nil)
		finish()
	end)

	t.test("slow training is off while the server closes", function()
		local world = fresh()
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		world.closing = true
		expect.equal(GripService.tick(world.player).reason, "off")
		finish()
	end)

	t.test("step() ticks a player once per tickSeconds", function()
		local world = fresh()
		local start = world.clock.now()
		for _ = 1, math.floor(AFK.tickSeconds * 3 / 0.25) + 1 do
			GripService.step(world.clock.now())
			wait(world, 0.25)
		end
		local paid = world.profile.grip.total / expectedAfk(1, 1)
		-- Three windows: the first tick only records the pad, the next ones pay (2 or 3 depending on the spread).
		expect.truthy(paid >= 2 and paid <= 3)
		expect.truthy(world.clock.now() - start >= AFK.tickSeconds * 3)
		finish()
	end)

	-- Squeezes ---------------------------------------------------------------------------------------------------------

	t.test("a squeeze uses exactly one Double Grip point and trains x mult", function()
		local world = fresh()
		world.profile.grip.rested = { value = 5, at = UNIX_START }
		local base = ownGrip(world)
		for i = 1, 3 do
			local gain = GripService.addFromSqueeze(world.player, 1)
			expect.equal(gain.doubled, REST.enabled)
			expect.equal(gain.grip, if REST.enabled then base * REST.mult else base)
			expect.near(world.profile.grip.rested.value, if REST.enabled then 5 - i else 5, 1e-6)
		end
		expect.equal(world.profile.grip.total, 3 * (if REST.enabled then base * REST.mult else base))
		finish()
	end)

	-- Phase 3: a pad no longer changes an own squeeze's Grip (was GripMath.squeezeGrip(trainer, tier): 15 on Jelly).
	t.test("without a Double Grip point a squeeze trains the base Grip, on a pad too", function()
		local world = fresh()
		local gain = GripService.addFromSqueeze(world.player, 2)
		expect.equal(gain.doubled, false)
		expect.equal(gain.grip, ownGrip(world))
		expect.equal(gain.grip, 10) -- a new player's capsule: CP(1)
		expect.equal(gain.gripTotal, world.profile.grip.total)
		expect.near(world.profile.grip.rested.value, 0, 1e-6)
		finish()
	end)

	t.test(
		"an own squeeze trains the highest capsule level's power (an empty capsule counts), x mult doubled",
		function()
			local world = fresh()
			local list: { any } = {
				{ level = 12, squishyId = "kitty_bread" },
				{ level = 31 },
				{ level = 4, squishyId = "dragon" },
			}
			world.profile.capsules = { slots = 3, list = list }
			world.profile.grip.trainer = #Config.Grip.Trainer -- the trainer no longer matters either
			local plain = GripService.addFromSqueeze(world.player, 4)
			expect.equal(plain.grip, CapsuleMath.power(31))
			world.profile.grip.rested = { value = 3, at = UNIX_START }
			local doubled = GripService.addFromSqueeze(world.player, 1)
			expect.equal(doubled.doubled, REST.enabled)
			expect.equal(
				doubled.grip,
				if REST.enabled then CapsuleMath.power(31) * REST.mult else CapsuleMath.power(31)
			)
			-- Without any capsule field the squeeze trains CP(1), the starter capsule's.
			world.profile.capsules = nil
			expect.equal(GripService.addFromSqueeze(world.player, 1).grip, 10 * (if REST.enabled then REST.mult else 1))
			finish()
		end
	)

	t.test("a capsule squeeze trains its power: never doubled, no Double Grip point used, quests untouched", function()
		local world = fresh()
		world.profile.grip.rested = { value = 5, at = UNIX_START }
		local before = TableUtil.deepCopy(world.profile)
		local power = CapsuleMath.power(23) :: number
		expect.equal(GripService.addFromCapsule(world.player, power), power)
		expect.equal(world.profile.grip.total, power)
		expect.deepEqual(world.profile.grip.rested, before.grip.rested)
		expect.equal(world.profile.coins, before.coins)
		expect.deepEqual(world.profile.quests, before.quests)
		expect.deepEqual(world.profile.stats, before.stats)
		expect.truthy(table.find(world.dirty, "grip") ~= nil)
		expect.equal(GripService.levelOf(world.player), GripMath.levelFor(power))
		-- It is not an own squeeze: slow training on a pad still pays after it.
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		GripService.addFromCapsule(world.player, power)
		expect.equal(GripService.tick(world.player).reason, "paid")
		-- Not ready, or a session that takes no more changes: nothing.
		world.status = "offline"
		expect.equal(GripService.addFromCapsule(world.player, power), 0)
		world.status = "ready"
		world.frozen = true
		expect.equal(GripService.addFromCapsule(world.player, power), 0)
		finish()
	end)

	t.test("nothing is trained while the profile is not ready", function()
		local world = fresh()
		world.profile.grip.rested = { value = 5, at = UNIX_START }
		for _, status in { "loading", "offline", "readonly" } do
			world.status = status
			local gain = GripService.addFromSqueeze(world.player, 1)
			expect.equal(gain.grip, 0)
			expect.equal(gain.doubled, false)
		end
		expect.equal(world.profile.grip.total, 0)
		expect.near(world.profile.grip.rested.value, 5, 1e-6)
		finish()
	end)

	t.test("a session that takes no more changes (final save started) earns nothing and changes nothing", function()
		local world = fresh()
		world.profile.grip.rested = { value = 5, at = UNIX_START }
		GripService.tick(world.player) -- first tick on the pad
		wait(world, AFK.tickSeconds)
		local before = TableUtil.deepCopy(world.profile.grip)
		world.frozen = true -- still "ready", but DataService.mutate refuses every change now
		local tick = GripService.tick(world.player)
		expect.equal(tick.grip, 0)
		expect.equal(tick.reason, "notReady")
		local gain = GripService.addFromSqueeze(world.player, 1)
		expect.equal(gain.grip, 0)
		expect.equal(gain.doubled, false)
		expect.deepEqual(world.profile.grip, before)
		expect.equal(table.find(world.dirty, "grip"), nil)
		finish()
	end)

	t.test("the total never passes maxGrip, and the gain is what it really gained", function()
		local world = fresh()
		local cap = Config.Grip.maxGrip
		world.profile.grip.total = cap - 3
		GripService.refreshBaseline(world.player, false)
		expect.truthy(ownGrip(world) > 3)
		local gain = GripService.addFromSqueeze(world.player, 1)
		expect.equal(world.profile.grip.total, cap)
		expect.equal(gain.gripTotal, cap)
		expect.equal(gain.grip, 3)
		finish()
	end)

	t.test("step() drops the session of a player who already left (a late squeeze re-created it)", function()
		local world = fresh()
		local gone = Instance.new("Folder") -- like a Player after PlayerRemoving: Parent = nil
		GripService.addFromSqueeze(gone, 1)
		expect.equal(GripService.debugState().sessions, 2)
		GripService.step(world.clock.now())
		expect.equal(GripService.debugState().sessions, 1)
		gone:Destroy()
		finish()
	end)

	t.test("an unknown tier trains nothing and is never open", function()
		local world = fresh()
		expect.equal(GripService.addFromSqueeze(world.player, #Config.Grip.Pads + 1).grip, 0)
		expect.falsy(GripService.canUseTier(world.player, #Config.Grip.Pads + 1))
		expect.truthy(GripService.canUseTier(world.player, 1))
		expect.falsy(GripService.canUseTier(world.player, 2))
		finish()
	end)

	-- Phase 3: Grip events now reach maxGripPerEvent (CP(100) × 2), so the alert can be crossed again (spec 2026-10-12
	-- §12: gripAlertPerHour = 43,212 of the biggest events). Events at maxGripPerEvent, one more than the alert holds.
	t.test("Grip above gripAlertPerHour in a rolling hour sets the anomaly alert; it re-arms an hour later", function()
		local world = fresh()
		local key = tostring(world.player.UserId)
		local event = Config.Grip.maxGripPerEvent
		local events = Config.Grip.gripAlertPerHour // event -- exactly the alert: not above it
		expect.equal(events * event, Config.Grip.gripAlertPerHour)
		for _ = 1, events do
			GripService.addFromCapsule(world.player, event)
		end
		expect.equal(world.profile.grip.total, Config.Grip.gripAlertPerHour)
		expect.falsy(GripService.debugState().players[key].alerted)
		GripService.addFromCapsule(world.player, event) -- the hour passes the alert
		expect.truthy(GripService.debugState().players[key].alerted)
		-- An hour later the counter only holds the new gain: the alert re-arms.
		wait(world, 3600 + 60)
		GripService.addFromCapsule(world.player, 1)
		expect.falsy(GripService.debugState().players[key].alerted)
		finish()
	end)

	-- Levels and toasts ------------------------------------------------------------------------------------------------

	t.test("a load sets the level silently; a migrated profile gets only the head-start toast", function()
		local world = fresh()
		world.profile.grip.total = 200000 -- Lv 12 (v1 head start: 20,000 old squeezes x 10)
		world.profile.grip.rested = { value = REST.burst, at = UNIX_START }
		world.migratedFrom = 1
		GripService.refreshBaseline(world.player, true)
		local level = GripMath.levelFor(200000)
		expect.equal(GripService.levelOf(world.player), level)
		expect.equal(world.levelAttr, level)
		expect.deepEqual(codes(world), { "grip.headStart" })
		expect.equal(world.notices[1].args.level, level)
		expect.truthy(#world.levelChanges >= 1)
		expect.equal(world.levelChanges[#world.levelChanges].new, level)
		for _, change in world.levelChanges do
			expect.equal(change.silent, true)
		end
		expect.equal(#world.saves, 0)
		finish()
	end)

	t.test("a new account with full Double Grip gets the welcome toast on load", function()
		local world = fresh()
		world.profile.grip.rested = { value = REST.burst, at = UNIX_START }
		GripService.refreshBaseline(world.player, true)
		if REST.enabled then
			expect.deepEqual(codes(world), { "grip.welcome" })
		end
		finish()
	end)

	t.test("Double Grip that grew by welcomeBackMinGain gives the welcome-back toast", function()
		local world = fresh()
		local stored = 100
		-- Away long enough to gain exactly welcomeBackMinGain points (not full).
		local away = Config.Grip.welcomeBackMinGain * 3600 / REST.perHour
		world.profile.grip.rested = { value = stored, at = UNIX_START - away }
		world.profile.grip.total = 5000
		world.profile.lastSeenAt = UNIX_START - away -- saved when the player left
		GripService.refreshBaseline(world.player, true)
		if REST.enabled then
			expect.deepEqual(codes(world), { "grip.welcomeBack" })
			expect.equal(world.notices[1].args.minutes, GripMath.restedMinutes(stored + Config.Grip.welcomeBackMinGain))
		end
		finish()
	end)

	-- §17.3.4: the toast counts the growth "since the last save" (lastSeenAt), not since the last Double Grip use.
	t.test("a short absence after a long session without squeezing gives no welcome-back toast", function()
		local world = fresh()
		local stored = 100
		local minGain = Config.Grip.welcomeBackMinGain
		-- The last Double Grip point was used long enough ago to grow by 2 x minGain (still not full), but the last
		-- save (the player leaving) was only 5 minutes ago.
		local sinceUse = 2 * minGain * 3600 / REST.perHour
		local sinceSave = 300
		world.profile.grip.rested = { value = stored, at = UNIX_START - sinceUse }
		world.profile.grip.total = 5000
		world.profile.lastSeenAt = UNIX_START - sinceSave
		expect.truthy(sinceSave * REST.perHour / 3600 < minGain) -- the growth since the save is under the threshold
		expect.truthy(stored + 2 * minGain < REST.burst) -- and Double Grip is not full
		GripService.refreshBaseline(world.player, true)
		expect.deepEqual(codes(world), {})
		finish()
	end)

	t.test("a save time in the future never gives a welcome-back toast", function()
		local world = fresh()
		local away = 2 * Config.Grip.welcomeBackMinGain * 3600 / REST.perHour
		world.profile.grip.rested = { value = 100, at = UNIX_START - away }
		world.profile.grip.total = 5000
		world.profile.lastSeenAt = UNIX_START + 600 -- another server's clock ran ahead
		GripService.refreshBaseline(world.player, true)
		expect.deepEqual(codes(world), {})
		finish()
	end)

	t.test("a level-up toasts the level and the opened pad, and asks for a soon save", function()
		local world = fresh()
		local padLevel = Config.Grip.Pads[2].level
		world.profile.grip.total = Config.Grip.LevelTotals[padLevel] - 1
		GripService.refreshBaseline(world.player, false)
		expect.equal(#world.notices, 0)
		GripService.addFromSqueeze(world.player, 1)
		expect.equal(GripService.levelOf(world.player), padLevel)
		local list = codes(world)
		expect.truthy(table.find(list, "grip.levelUp") ~= nil)
		expect.truthy(table.find(list, "grip.padUnlocked") ~= nil)
		expect.falsy(table.find(list, "grip.rankUp") ~= nil)
		expect.deepEqual(world.saves, { "soon" })
		local change = world.levelChanges[#world.levelChanges]
		expect.equal(change.new, padLevel)
		expect.equal(change.silent, false)
		finish()
	end)

	t.test("a new rank is broadcast to every lobby player", function()
		local world = fresh()
		local other = { UserId = 43, DisplayName = "Other" }
		world.lobby = { world.player, other }
		local rankLevel = Config.Grip.Ranks[2].level
		world.profile.grip.total = Config.Grip.LevelTotals[rankLevel] - 1
		GripService.refreshBaseline(world.player, false)
		GripService.addFromSqueeze(world.player, 1)
		local reached: { any } = {}
		for _, n in world.notices do
			if n.code == "grip.rankUp" then
				table.insert(reached, n.player)
				expect.equal(n.args.name, "Tester")
			end
		end
		expect.equal(#reached, 2)
		expect.truthy(table.find(reached, other) ~= nil)
		finish()
	end)

	t.test("the first Grip ever shows the intro toast once", function()
		local world = fresh()
		GripService.addFromSqueeze(world.player, 1)
		GripService.addFromSqueeze(world.player, 1)
		local count = 0
		for _, code in codes(world) do
			if code == "grip.intro" then
				count += 1
			end
		end
		expect.equal(count, 1)
		finish()
	end)

	-- Trainer upgrades (Part 7, §17.5, §17.12 Part 7) -----------------------------------------------------------------

	local TRAINER = Config.Grip.Trainer

	-- A ready profile at trainer `trainer`, Grip Level `level` and `coins` Coins.
	local function trainerWorld(trainer: number, level: number, coins: number): World
		local world = fresh()
		world.profile.grip.trainer = trainer
		world.profile.grip.total = Config.Grip.LevelTotals[level]
		world.profile.coins = coins
		GripService.refreshBaseline(world.player, false)
		expect.equal(GripService.levelOf(world.player), level)
		return world
	end

	local function expectRefused(reply: any, reason: string)
		expect.equal(reply.ok, false)
		expect.equal(reply.reason, reason)
		expect.equal(reply.charged, false)
	end

	t.test("trainer: a buy charges once, sets grip.trainer, toasts, saves now and replies charged", function()
		local cost, gate = TRAINER[2].cost, TRAINER[2].level
		local world = trainerWorld(1, gate, cost + 5)
		local reply = GripService.upgradeTrainer(world.player, 2, cost)
		expect.equal(reply.ok, true)
		expect.deepEqual(reply.data, { trainer = 2, charged = true, savePending = false })
		expect.equal(world.profile.grip.trainer, 2)
		expect.equal(world.profile.coins, 5)
		expect.deepEqual(world.spends, { { amount = cost, reason = "trainer" } })
		expect.equal(world.nowSaves, 1)
		expect.truthy(table.find(world.dirty, "grip") ~= nil)
		local bought = nil
		for _, n in world.notices do
			if n.code == "grip.trainerBought" then
				bought = n
			end
		end
		expect.truthy(bought ~= nil)
		expect.equal(bought.args.trainer, "Sponge Ball")
		expect.equal(bought.args.grip, GripMath.squeezeGrip(2, 1))
		finish()
	end)

	t.test("trainer: two identical buys charge once; the second is a replay with charged = false", function()
		local cost, gate = TRAINER[2].cost, TRAINER[2].level
		local world = trainerWorld(1, gate, cost * 3)
		expect.equal(GripService.upgradeTrainer(world.player, 2, cost).data.charged, true)
		local replay = GripService.upgradeTrainer(world.player, 2, cost)
		expect.equal(replay.ok, true)
		expect.deepEqual(replay.data, { trainer = 2, charged = false, savePending = false })
		expect.equal(world.profile.coins, cost * 2)
		expect.equal(#world.spends, 1)
		expect.equal(world.nowSaves, 1) -- a replay saves nothing
		-- A replay answers the best trainer owned, whatever price it carries.
		expect.equal(GripService.upgradeTrainer(world.player, 2, 0).data.trainer, 2)
		finish()
	end)

	t.test("trainer: TrainerUpgrade(8, 150000) at trainer 1 is trainer.notNext", function()
		local world = trainerWorld(1, Config.Grip.maxLevel, 1_000_000)
		expectRefused(GripService.upgradeTrainer(world.player, 8, TRAINER[8].cost), "trainer.notNext")
		expectRefused(GripService.upgradeTrainer(world.player, 3, TRAINER[3].cost), "trainer.notNext")
		expect.equal(world.profile.grip.trainer, 1)
		expect.equal(#world.spends, 0)
		finish()
	end)

	t.test("trainer: a level below the gate is trainer.locked; a price mismatch is trainer.priceChanged", function()
		local cost, gate = TRAINER[2].cost, TRAINER[2].level
		local low = trainerWorld(1, gate - 1, cost * 2)
		expectRefused(GripService.upgradeTrainer(low.player, 2, cost), "trainer.locked")
		expect.equal(#low.spends, 0)
		finish()
		local world = trainerWorld(1, gate, cost * 2)
		expectRefused(GripService.upgradeTrainer(world.player, 2, cost - 1), "trainer.priceChanged")
		expectRefused(GripService.upgradeTrainer(world.player, 2, 0), "trainer.priceChanged")
		expect.equal(world.profile.coins, cost * 2)
		expect.equal(world.profile.grip.trainer, 1)
		finish()
	end)

	t.test("trainer: out-of-range arguments are net.invalid, checked before the profile", function()
		local world = trainerWorld(1, Config.Grip.maxLevel, 1_000_000)
		world.status = "offline" -- step 2 comes before step 3
		for _, args in { { 1, 0 }, { #TRAINER + 1, 0 }, { 0, 0 }, { 2, -1 }, { 2.5, 1000 }, { 2, 0 / 0 } } do
			expectRefused(GripService.upgradeTrainer(world.player, args[1], args[2]), "net.invalid")
		end
		finish()
	end)

	t.test("trainer: a profile that is not ready is data.notReady and changes nothing", function()
		local cost, gate = TRAINER[2].cost, TRAINER[2].level
		local world = trainerWorld(1, gate, cost)
		world.status = "offline"
		expectRefused(GripService.upgradeTrainer(world.player, 2, cost), "data.notReady")
		world.status = "loading"
		expectRefused(GripService.upgradeTrainer(world.player, 2, cost), "data.notReady")
		expect.equal(world.profile.coins, cost)
		expect.equal(world.profile.grip.trainer, 1)
		finish()
	end)

	t.test("trainer: savePending, closing or a pending restart is trainer.paused", function()
		local cost, gate = TRAINER[2].cost, TRAINER[2].level
		local world = trainerWorld(1, gate, cost)
		world.savePending = true
		expectRefused(GripService.upgradeTrainer(world.player, 2, cost), "trainer.paused")
		world.savePending = false
		world.closing = true
		expectRefused(GripService.upgradeTrainer(world.player, 2, cost), "trainer.paused")
		world.closing = false
		world.restart = true
		expectRefused(GripService.upgradeTrainer(world.player, 2, cost), "trainer.paused")
		expect.equal(world.profile.coins, cost)
		expect.equal(#world.spends, 0)
		finish()
	end)

	t.test("trainer: from Matched through Returning is inventory.lockedInDuel", function()
		local cost, gate = TRAINER[2].cost, TRAINER[2].level
		local world = trainerWorld(1, gate, cost)
		for _, phase in { "Preparing", "Active", "Returning" } do
			world.phase = phase
			expectRefused(GripService.upgradeTrainer(world.player, 2, cost), "inventory.lockedInDuel")
		end
		expect.equal(world.profile.coins, cost)
		finish()
	end)

	t.test("trainer: too few Coins is economy.notEnoughCoins and nothing changes", function()
		local cost, gate = TRAINER[2].cost, TRAINER[2].level
		local world = trainerWorld(1, gate, cost - 1)
		expectRefused(GripService.upgradeTrainer(world.player, 2, cost), "economy.notEnoughCoins")
		expect.equal(world.profile.coins, cost - 1)
		expect.equal(world.profile.grip.trainer, 1)
		expect.equal(world.nowSaves, 0)
		finish()
	end)

	t.test("trainer: a failed now save keeps the purchase and replies savePending", function()
		local cost, gate = TRAINER[2].cost, TRAINER[2].level
		local world = trainerWorld(1, gate, cost)
		world.saveOk = false
		local reply = GripService.upgradeTrainer(world.player, 2, cost)
		expect.deepEqual(reply.data, { trainer = 2, charged = true, savePending = true })
		expect.equal(world.profile.grip.trainer, 2)
		expect.equal(world.profile.coins, 0)
		finish()
	end)

	-- Phase 3 (spec 2026-10-12 §3, §10): own squeezes train the capsules' power; a trainer only feeds slow training now
	-- (trainers go in Phase 6). Was: a better trainer trains more Grip per squeeze.
	t.test("trainer: a better trainer no longer changes an own squeeze's Grip", function()
		local cost, gate = TRAINER[2].cost, TRAINER[2].level
		local world = trainerWorld(1, gate, cost)
		GripService.upgradeTrainer(world.player, 2, cost)
		expect.equal(world.profile.grip.trainer, 2)
		local before = world.profile.grip.total
		local gain = GripService.addFromSqueeze(world.player, 1)
		expect.equal(gain.grip, ownGrip(world) * (if gain.doubled then REST.mult else 1))
		expect.equal(world.profile.grip.total, before + gain.grip)
		finish()
	end)

	t.test("Part 7: an AFK-only profile reaching Lv 5 keeps starter progress and Coins with quests wired", function()
		local world = fresh()
		local QuestService = t.requireServer("Services/QuestService")
		local questNotices: { string } = {}
		QuestService.useDeps({
			data = {
				getProfile = function(_player: any): any
					return world.profile
				end,
				status = function(_player: any): string
					return world.status
				end,
				persisted = function(_player: any): boolean
					return true
				end,
				savePending = function(_player: any): boolean
					return false
				end,
				statusReason = function(_player: any): string?
					return nil
				end,
				mutate = function(_player: any, fn: (profile: any) -> any): (boolean, any)
					if world.status ~= "ready" then
						return false, "data.notReady"
					end
					return true, fn(world.profile)
				end,
				requestSave = function(_player: any, _reason: string) end,
				onLoaded = function(_handler: any) end,
				onStatusChanged = function(_handler: any) end,
			},
			markDirty = function(_player: any, _field: string) end,
			notify = function(_player: any, code: string)
				table.insert(questNotices, code)
			end,
			grantCoins = function(_player: any, amount: number, _reason: string): (number, string?)
				world.profile.coins += amount
				return amount, nil
			end,
			unixNow = world.unix.now,
			onlinePlayers = function(): { any }
				return { world.player }
			end,
		})
		QuestService.init() -- wired to every source it listens to; GripService is not one of them
		QuestService.ensureQuests(world.player) -- today's quests, as after a profile load
		world.profile.starter = { progress = { starter_squeeze = 2, starter_jelly = 3 }, claimed = {} }
		local target = Config.Grip.LevelTotals[5]
		world.profile.grip.total = target - 1
		GripService.refreshBaseline(world.player, false)
		local before = TableUtil.deepCopy(world.profile)
		GripService.tick(world.player)
		wait(world, AFK.tickSeconds)
		expect.equal(GripService.tick(world.player).reason, "paid")
		expect.equal(GripService.levelOf(world.player), 5)
		for _ = 1, 3 do -- more ticks at Lv 5, still on the pad
			wait(world, AFK.tickSeconds)
			GripService.tick(world.player)
		end
		GripService.refreshBaseline(world.player, true) -- a reload: the silent baseline and the load toasts
		QuestService.ensureQuests(world.player) -- a load never moves progress either
		expect.equal(world.profile.coins, before.coins)
		expect.deepEqual(world.profile.starter, before.starter)
		expect.deepEqual(world.profile.quests, before.quests)
		expect.equal(#questNotices, 0)
		QuestService.destroy()
		QuestService.useDeps(nil)
		finish()
	end)
end
