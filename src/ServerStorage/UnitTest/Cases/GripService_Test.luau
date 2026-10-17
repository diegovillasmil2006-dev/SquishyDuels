--!strict
-- GripService_Test: unit tests for ServerScriptService.Server.Services.GripService with injected fakes (fake clocks,
-- a fake profile; the "player" is a plain table). Server only (ServerStorage.UnitTest). Edit mode: start() is never
-- called.
-- Contract (DESIGN §17.3.1 step 8a, §17.3.4, §17.7, §17.12 Part 5):
--   * slow training and the trainers are gone (build plan Phase 6): no tick, no bank, no disabled stations, no
--     upgradeTrainer; a profile without grip.afk or grip.trainer (every new save) trains Grip;
--   * a squeeze uses exactly one Double Grip point and doubles its Grip; no point, no doubling; nothing when not ready
--     or when the session takes no more changes (every write goes through mutate); the total stops at maxGrip and the
--     gain says what it really gained; step() drops the session of a player who already left;
--   * pens3 phase 1: an own squeeze trains PenMath.squeezeGrip(profile.pen), the floor of the pen's squeeze value (10
--     without a pen; a capsule counts for nothing), whatever the pad; a capsule squeeze (addFromCapsule, unused since
--     pens3 phase 1, removed in phase 2) trains its power, never doubled and without a Double Grip point; Grip events
--     above gripAlertPerHour in a rolling hour set the anomaly alert, which re-arms an hour later;
--   * a load sets the level silently (no level-up or rank-up toast), with grip.headStart after a v1 -> v2 migration;
--     grip.welcomeBack only when Double Grip grew by welcomeBackMinGain since the last save (lastSeenAt, §17.3.4);
--   * a level-up toasts grip.levelUp (grip.padUnlocked went with the giant pads, build plan Phase 6), broadcasts
--     grip.rankUp to the lobby players and asks for a "soon" save; an unknown tier (only tier 1, the Foam Mats, is
--     left) trains nothing and GripService.canUseTier is gone;
--   * a capsule-only profile that reaches Lv 5 keeps its starter progress and Coins with QuestService wired;
--   * Match HUD M2 (2026-10-16): a match pay (addFromMatch) trains squeezes × an own squeeze's Grip (the pen's, pens3
--     phase 1), never doubled and without a Double Grip point, each squeeze one event (never clamped when the whole
--     pay is above maxGripPerEvent), with the level toasts; nothing unready, frozen, or for a squeezes count outside
--     1..the largest duel pay (MatchRewards.maxSqueezes()).

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
	local PenMath = t.requireShared("PenMath")
	local TableUtil = t.requireShared("Util/TableUtil")

	local REST = Config.Grip.Rested
	local UNIX_START = 1_800_000_000

	type World = {
		clock: any,
		unix: any,
		player: any,
		status: string,
		profile: any,
		frozen: boolean, -- the session takes no more changes (its final save took its snapshot): mutate refuses
		dirty: { string },
		saves: { string },
		notices: { { player: any, code: string, args: any } },
		levelAttr: number?,
		levelChanges: { { old: number, new: number, silent: boolean } },
		migratedFrom: number?,
		lobby: { any },
	}

	-- A pen item (pens3 phase 1), plain Lv 1 unless told.
	local function penItem(id: number, kind: string, form: number?, level: number?, coat: number?): any
		return { id = id, kind = kind, form = form or 0, level = level or 1, coat = coat or 0 }
	end

	local function newProfile(unixNow: number): any
		return {
			coins = 50,
			stats = { squeezes = 7, coinsEarned = 50 },
			quests = { day = 3, swapsUsed = 0, active = { { id = "q3_1", progress = 1, goal = 5, done = false } } },
			starter = { progress = { squeeze = 2 }, claimed = {} },
			grip = {
				total = 0,
				rested = { value = 0, at = unixNow },
			},
			-- Pens3 phase 1: a new player's pen, Kitty Bread in the 3 free spots.
			pen = { spots = 3, nextId = 2, items = { penItem(1, "kitty_bread") } },
		}
	end

	-- Grip of one own squeeze for this profile (pens3 phase 1: the floor of the pen's squeeze value).
	local function ownGrip(world: any): number
		return PenMath.squeezeGrip(world.profile.pen)
	end

	local function fresh(): World
		local world: World = {
			clock = FakeClock.new(1000),
			unix = FakeClock.new(UNIX_START),
			player = { UserId = 42, DisplayName = "Tester" },
			status = "ready",
			profile = newProfile(UNIX_START),
			frozen = false,
			dirty = {},
			saves = {},
			notices = {},
			levelAttr = nil,
			levelChanges = {},
			migratedFrom = nil,
			lobby = {},
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
		})
		GripService.playerAdded(world.player)
		return world
	end

	local function finish()
		GripService.reset()
		GripService.useDeps(nil)
		GripService.LevelChanged:disconnectAll()
	end

	-- Advances both clocks by `seconds` (the anomaly window and Double Grip).
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

	-- Slow training and the trainers are gone (build plan Phase 6) ----------------------------------------------------

	t.test("no slow training or trainers; a save without grip.afk or grip.trainer trains Grip", function()
		for _, name in
			{
				"tick",
				"debugTick",
				"debugSetAfkBank",
				"debugSetTickSeconds",
				"disableStation",
				"isStationDisabled",
				"upgradeTrainer",
			}
		do
			expect.equal((GripService :: any)[name], nil)
		end
		local world = fresh()
		expect.equal(world.profile.grip.afk, nil) -- a new save (ProfileSchema.defaults) has no bank
		expect.equal(world.profile.grip.trainer, nil) -- and no trainer
		local gain = GripService.addFromSqueeze(world.player, 1)
		expect.equal(gain.grip, ownGrip(world))
		expect.equal(GripService.addFromCapsule(world.player, 10), 10)
		expect.equal(world.profile.grip.total, gain.grip + 10)
		finish()
	end)

	t.test("an old save keeps its grip.afk and grip.trainer as they are (unknown fields nothing reads)", function()
		local world = fresh()
		world.profile.grip.afk = { value = 5, at = UNIX_START }
		world.profile.grip.trainer = 8
		wait(world, 3600)
		local gain = GripService.addFromSqueeze(world.player, 1)
		expect.truthy(gain.grip > 0)
		GripService.addFromCapsule(world.player, 10)
		expect.deepEqual(world.profile.grip.afk, { value = 5, at = UNIX_START })
		expect.equal(world.profile.grip.trainer, 8)
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
	t.test("without a Double Grip point a squeeze trains the base Grip", function()
		local world = fresh()
		local gain = GripService.addFromSqueeze(world.player, 1)
		expect.equal(gain.doubled, false)
		expect.equal(gain.grip, ownGrip(world))
		expect.equal(gain.grip, 10) -- a new player's pen: Kitty Bread, 10 a second
		expect.equal(gain.gripTotal, world.profile.grip.total)
		expect.near(world.profile.grip.rested.value, 0, 1e-6)
		finish()
	end)

	t.test(
		"an own squeeze trains the floor of the pen's squeeze value (a capsule counts for nothing), x mult doubled",
		function()
			local world = fresh()
			-- Kitty Bread Lv 2 (11.5) + Dragon (640) = 651.5 a squeeze: 651 Grip.
			world.profile.pen.items = { penItem(1, "kitty_bread", 0, 2), penItem(2, "dragon") }
			world.profile.capsules = { slots = 1, list = { { level = 100, squishyId = "dragon" } } }
			local plain = GripService.addFromSqueeze(world.player, 1)
			expect.equal(plain.grip, 651)
			world.profile.grip.rested = { value = 3, at = UNIX_START }
			local doubled = GripService.addFromSqueeze(world.player, 1)
			expect.equal(doubled.doubled, REST.enabled)
			expect.equal(doubled.grip, if REST.enabled then 651 * REST.mult else 651)
			-- Without a pen the squeeze trains the least squeeze value, 10.
			world.profile.pen = nil
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
		-- Not ready, or a session that takes no more changes: nothing.
		world.status = "offline"
		expect.equal(GripService.addFromCapsule(world.player, power), 0)
		world.status = "ready"
		world.frozen = true
		expect.equal(GripService.addFromCapsule(world.player, power), 0)
		finish()
	end)

	-- Match HUD M2 (2026-10-16): the Grip half of a Free for All / Team Deathmatch pay.
	t.test("a match pay trains squeezes × an own squeeze's Grip: never doubled, no Double Grip point used", function()
		local world = fresh()
		world.profile.grip.rested = { value = 5, at = UNIX_START }
		table.insert(world.profile.pen.items, penItem(2, "bird"))
		local before = TableUtil.deepCopy(world.profile)
		local perSqueeze = 170 -- Kitty Bread 10 + Bird 160
		expect.equal(GripService.addFromMatch(world.player, 600), 600 * perSqueeze)
		expect.equal(world.profile.grip.total, 600 * perSqueeze)
		expect.deepEqual(world.profile.grip.rested, before.grip.rested)
		expect.equal(world.profile.coins, before.coins)
		expect.deepEqual(world.profile.stats, before.stats)
		expect.truthy(table.find(world.dirty, "grip") ~= nil)
		expect.equal(GripService.levelOf(world.player), GripMath.levelFor(600 * perSqueeze))
		-- A level-up from a match pay toasts like any gain.
		local levelUps = 0
		for _, n in world.notices do
			if n.code == "grip.levelUp" then
				levelUps += 1
			end
		end
		expect.truthy(levelUps >= 1)
		finish()
	end)

	t.test("a big match pay is never clamped per event (each squeeze is one event)", function()
		local world = fresh()
		-- 12 Rainbow Galaxy Dragons at Lv 26: about 12M a squeeze (pens3 phase 1 makes none yet; later phases will).
		local items = {}
		for id = 1, 12 do
			table.insert(items, penItem(id, "dragon", 2, 26, 7))
		end
		world.profile.pen = { spots = 12, nextId = 13, items = items }
		local top = PenMath.squeezeGrip(world.profile.pen)
		expect.truthy(top < Config.Grip.maxGripPerEvent) -- one squeeze is one event under the cap
		expect.truthy(600 * top > Config.Grip.maxGripPerEvent) -- one event of the whole pay would be clamped
		expect.equal(GripService.addFromMatch(world.player, 600), 600 * top)
		finish()
	end)

	t.test(
		"a match pay gives nothing unready, frozen, or for a squeezes count outside 1..the largest duel pay",
		function()
			local world = fresh()
			-- One above the largest duel pay: the live one, which addFromMatch's guard reads (review fix, not 601).
			local above = t.requireServer("Logic/MatchRewards").maxSqueezes() + 1
			for _, bad in { 0, -5, 1.5, 0 / 0, math.huge, above } do
				expect.equal(GripService.addFromMatch(world.player, bad), 0)
			end
			expect.equal(world.profile.grip.total, 0)
			world.status = "offline"
			expect.equal(GripService.addFromMatch(world.player, 180), 0)
			world.status = "ready"
			world.frozen = true
			expect.equal(GripService.addFromMatch(world.player, 180), 0)
			expect.equal(world.profile.grip.total, 0)
			world.frozen = false
			expect.equal(GripService.addFromMatch(world.player, 1), ownGrip(world))
			finish()
		end
	)

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
		local before = TableUtil.deepCopy(world.profile.grip)
		world.frozen = true -- still "ready", but DataService.mutate refuses every change now
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
		fresh()
		local gone = Instance.new("Folder") -- like a Player after PlayerRemoving: Parent = nil
		GripService.addFromSqueeze(gone, 1)
		expect.equal(GripService.debugState().sessions, 2)
		GripService.step()
		expect.equal(GripService.debugState().sessions, 1)
		gone:Destroy()
		finish()
	end)

	t.test("an unknown tier trains nothing (the giant pads' tiers 2-4 too); canUseTier is gone (Phase 6)", function()
		local world = fresh()
		expect.equal(#Config.Grip.Pads, 1)
		expect.equal(GripService.addFromSqueeze(world.player, 2).grip, 0)
		expect.equal(GripService.addFromSqueeze(world.player, 4).grip, 0)
		expect.equal(world.profile.grip.total, 0)
		expect.equal((GripService :: any).canUseTier, nil)
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

	t.test("a level-up toasts the level (no pad toast since Phase 6) and asks for a soon save", function()
		local world = fresh()
		local level = 5 -- the old Jelly Pad level
		world.profile.grip.total = Config.Grip.LevelTotals[level] - 1
		GripService.refreshBaseline(world.player, false)
		expect.equal(#world.notices, 0)
		GripService.addFromSqueeze(world.player, 1)
		expect.equal(GripService.levelOf(world.player), level)
		local list = codes(world)
		expect.truthy(table.find(list, "grip.levelUp") ~= nil)
		expect.falsy(table.find(list, "grip.padUnlocked") ~= nil)
		expect.falsy(table.find(list, "grip.rankUp") ~= nil)
		expect.deepEqual(world.saves, { "soon" })
		local change = world.levelChanges[#world.levelChanges]
		expect.equal(change.new, level)
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

	-- Phase 6: capsule Grip is the idle Grip left (was: slow-training ticks on a pad).
	t.test("Part 7: a capsule-only profile reaching Lv 5 keeps starter progress and Coins with quests wired", function()
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
		world.profile.starter = { progress = { starter_squeeze = 2, starter_duel = 0 }, claimed = {} }
		local target = Config.Grip.LevelTotals[5]
		world.profile.grip.total = target - 1
		GripService.refreshBaseline(world.player, false)
		local before = TableUtil.deepCopy(world.profile)
		expect.equal(GripService.addFromCapsule(world.player, 10), 10)
		expect.equal(GripService.levelOf(world.player), 5)
		for _ = 1, 3 do -- more capsule squeezes at Lv 5
			wait(world, 4)
			GripService.addFromCapsule(world.player, 10)
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
