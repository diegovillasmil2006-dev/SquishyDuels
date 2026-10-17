--!strict
-- ProfileSchema_Test: defaults, the v1 -> v2 migration against a real v1 FIXTURE, reconcile and sanitize
-- (DESIGN §3.2, §3.3, §17.9 #6, §17.10, §17.12 Part 5). Server Logic/ProfileSchema, pure; `now` is injected.
-- Server only (ServerStorage.UnitTest). Tables are compared by value (deepEqual), never by identity.
-- Contract:
--   * a v1 fixture becomes v2: 10 Grip per old squeeze from the FROZEN constant, rested and afk start full and are
--     stamped with lastSeenAt, missing fields filled with defaults, everything else deep-equal, start version 1;
--   * v2 is a no-op (no second head start);
--   * bad Grip values (total, rested) are sanitized; slow training and the trainers are gone (build plan Phase 6): a
--     new save has no grip.afk or grip.trainer, and an old save's (or the frozen migration's) are kept as they are,
--     unknown fields nothing reads;
--   * v3 (newer than CURRENT) is not migrated: READONLY view;
--   * the §3.3 sanitize rules (coins, starter ownership, equipped, logs, settings, quests);
--   * samePair (§6.7) joined schema 2 without a new version: defaults {}, an older v2 profile gets it from reconcile,
--     and sanitize fails closed (bad keys / values dropped, non-finite times dropped, far-future times -> now,
--     sorted, both caps);
--   * capsules left schema 2 the same way (pens3 phase 2): not in defaults, never added by reconcile or fixed by
--     sanitize, and an old save's are kept unchanged (through JSON too), an unknown field nothing reads;
--   * Match HUD M2 (2026-10-16): stats.winStreak joined schema 2 the same way (CURRENT stays 2): defaults 0, an older
--     v2 profile gets 0 from reconcile (no sanitize problem), a saved streak is kept, and sanitize fixes a negative,
--     fractional, non-finite or wrong-type one like every counter;
--   * auto-clicker check (2026-10-16): autoClick (the last strike) joined schema 2 the same way: defaults {step = 0,
--     at = 0}, an older v2 profile gets it from reconcile (no problem), a saved strike is kept, and sanitize keeps step
--     a whole number in [0, AutoClickRules.MAX_STEP] (5 with the live ban ladder, batch B 2026-10-17) and at a whole
--     number in [0, now + 300] (non-finite -> 0, wrong type -> the default);
--   * weekly quests (2026-10-17): weekly joined schema 2 the same way: defaults {week = -1, active = {}}, an older v2
--     profile gets it from reconcile (no problem), a saved week survives a load and the JSON round trip, and sanitize
--     fixes the week (a whole number >= -1) and the entries like the daily quests' (claims fail closed);
--   * pens (pens3 phase 1): pen joined schema 2 the same way: defaults {spots = 3, nextId = 2, items = {Kitty Bread
--     id 1}}, an older profile gets one plain Lv 1 item per owned kind (logged), and sanitize fails closed without
--     ever dropping a squishy someone owns: spots a whole number in [3, 12]; a bad or repeated id gets a fresh one; an
--     unknown kind is dropped (its owned entry stays); form, level and coat clamped; an item not in `owned` makes it
--     owned; nextId above every id; a pen past toyBoxMax + placedMax kept whole and logged; JSON round trip unchanged;
--   * pens3 phase 4: pen.awayRate (the pen's rate at the last save) joined the same way: defaults 0, an older pen gets
--     0 from reconcile (no problem), a saved rate is kept, and sanitize turns a non-finite, negative or non-number
--     rate into 0 (logged; fails closed: no away Coins);
--   * pens3 phase 5: giftQueue {}, boxOrder {snack = 0, sweet = 0} and gifts {frog = false} joined the same way (an
--     older profile gets them from reconcile, no problem; saved values survive JSON); sanitize keeps only Catalog kinds
--     in the queue, in order (a long queue is all kept and logged), makes each paid box's count a whole number >= 0
--     (other keys kept), and fails closed on gifts (a broken flag or table counts every gift as given);
--   * pens3 phase 6: every pen item has `slot` (0 = the Toy Box, 1..spots the pen) and `locked`: the default Kitty
--     Bread sits in slot 1; an item with no slot (an older save) gets one once, from the best-N order the pen used
--     before (rate, then the lower id: the same squishies keep paying), the rest the Toy Box; a slot past the open
--     spots, a repeated slot or a broken one goes to the Toy Box (slot 0), never dropped; every fix logged; a missing
--     lock is false (like reconcile, not logged), a broken one false (logged);
--   * pens3 phases 7-8: buyBack {} and bag {0 x 7} joined the same way (an older profile gets them from reconcile, no
--     problem; saved values survive JSON); sanitize fails closed and logs: a buy-back entry that is not a sold squishy
--     (a Catalog kind, form / level / coat in range, a whole id), whole Coins, a finite time no later than now + 300
--     and a string requestId is dropped (it can't be bought back; its Coins were paid); more than buyBackMax keeps the
--     newest; the bag becomes one whole count >= 0 per coating (broken -> 0, missing -> 0, extra keys dropped).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
	requireShared: (path: string) -> any,
}

local NOW = 1_800_000_000
local DAY = 86400

-- A complete ProfileV1 exactly as Part 5's first release would have stored it (schemaVersion 1, no grip).
local FIXTURE_V1 = {
	schemaVersion = 1,
	createdAt = 1_790_000_000,
	lastSeenAt = 1_795_000_000,
	saveSeq = 42,
	coins = 12_345,
	owned = {
		kitty_bread = { at = 1_790_000_000, src = "starter" },
		toast = { at = 1_791_000_000, src = "shop" },
		banana = { at = 1_792_000_000, src = "box" },
	},
	equipped = "toast",
	stats = {
		coinsEarned = 20_000,
		coinsSpent = 7_655,
		squeezes = 1_234,
		duelsPlayed = 10,
		duelsWon = 6,
		duelsLost = 3,
		duelsDrawn = 1,
		eliminations = 14,
		boxesOpened = 3,
	},
	squeezeLimit = { value = 120, at = 1_795_000_000 },
	quests = {
		day = 20_775,
		swapsUsed = 1,
		active = {
			{
				id = "q20775_1",
				def = "squeeze_any",
				progress = 10,
				goal = 50,
				reward = 100,
				done = false,
				claimed = false,
			},
			{
				id = "q20775_2",
				def = "duel_play",
				progress = 2,
				goal = 2,
				reward = 150,
				done = true,
				claimed = true,
			},
			{
				id = "q20775_3",
				def = "squeeze_with",
				squishy = "banana",
				progress = 0,
				goal = 30,
				reward = 120,
				done = false,
				claimed = false,
			},
		},
	},
	starter = { progress = { starter_squeeze = 5 }, claimed = { starter_box = true } },
	daily = { lastClaimDay = 20_774, streakDay = 3, totalClaims = 9 },
	settings = { music = 25, sfx = 80, cameraShake = false, showTips = true },
	onboarding = { v = 1, done = { welcome = true, squeeze = true }, skipped = false },
	boxLog = {
		{
			req = "6C3A1E2B-9D4F-4A1B-8C2D-3E4F5A6B7C8D",
			box = "snack",
			squishy = "banana",
			dup = false,
			refund = 0,
			cost = 400,
			at = 1_792_000_000,
			seen = true,
		},
	},
	shopLog = { { req = "1A2B3C4D-5E6F-4A1B-8C2D-3E4F5A6B7C8D", squishy = "toast", price = 1200, at = 1_791_000_000 } },
	receipts = {},
	duelLog = { { matchId = "7D8E9F0A-1B2C-4D3E-8F4A-5B6C7D8E9F0A", opp = 222, result = "win", at = 1_794_000_000 } },
}

return function(t: Context)
	local expect = t.expect
	local ProfileSchema = t.requireServer("Logic/ProfileSchema")
	local TableUtil = t.requireShared("Util/TableUtil")
	local Config = t.requireShared("Config")

	local function load(raw: any, opts: any?): any
		local options = opts or {}
		options.now = options.now or NOW
		return ProfileSchema.load(raw, options)
	end

	-- A pen item (pens3 phase 1), plain Lv 1 unless told; pens3 phase 6: in `slot` (default 0, the Toy Box), unlocked
	-- unless told.
	local function penItem(
		id: number,
		kind: string,
		form: number?,
		level: number?,
		coat: number?,
		slot: number?,
		locked: boolean?
	): any
		local item = { id = id, kind = kind, form = form or 0, level = level or 1, coat = coat or 0 }
		item.slot = slot or 0
		item.locked = locked == true
		return item
	end

	-- Phase 6: a pen item as an older save has it (no slot, no lock).
	local function oldItem(id: number, kind: string, form: number?, level: number?, coat: number?): any
		return { id = id, kind = kind, form = form or 0, level = level or 1, coat = coat or 0 }
	end

	local function expectedV2(fixture: any): any
		local expected = TableUtil.deepCopy(fixture)
		expected.schemaVersion = 2
		local seen = fixture.lastSeenAt
		expected.grip = {
			total = fixture.stats.squeezes * 10,
			trainer = 1,
			rested = { value = 1200, at = seen },
			afk = { value = 120, at = seen },
		}
		expected.samePair = {} -- filled by reconcile (no migration step)
		expected.stats.winStreak = 0 -- Match HUD M2: the same
		expected.autoClick = { step = 0, at = 0 } -- auto-clicker check (2026-10-16): the same
		expected.weekly = { week = -1, active = {} } -- weekly quests (2026-10-17): the same
		expected.giftQueue = {} -- pens3 phase 5: the same
		expected.boxOrder = { snack = 0, sweet = 0 }
		expected.gifts = { frog = false }
		expected.buyBack = {} -- pens3 phases 7-8: the same
		expected.bag = { 0, 0, 0, 0, 0, 0, 0 }
		-- Pens3 phase 1: the default pen (Kitty Bread, id 1), then one item per other owned kind, in id order.
		expected.pen = { spots = 3, nextId = 2, items = { penItem(1, "kitty_bread", 0, 1, 0, 1) }, awayRate = 0 }
		for _, kind in { "banana", "toast" } do
			if fixture.owned[kind] ~= nil then
				-- Phase 6: a new item takes the next free spot (all three are Commons: id order).
				table.insert(expected.pen.items, penItem(expected.pen.nextId, kind, 0, 1, 0, expected.pen.nextId))
				expected.pen.nextId += 1
			end
		end
		return expected
	end

	-- The sanitize notes about the pen (an older save gets its pen items, logged).
	local function penProblems(problems: { string }): number
		local count = 0
		for _, problem in problems do
			if string.sub(problem, 1, 4) == "pen." or string.sub(problem, 1, 4) == "pen " then
				count += 1
			end
		end
		return count
	end

	t.test("CURRENT is 2 and the v1 -> v2 constants are frozen at 10 / 1200 / 120 / 1e9", function()
		expect.equal(ProfileSchema.CURRENT, 2)
		expect.deepEqual(
			ProfileSchema.V1_TO_V2,
			{ headStartPerSqueeze = 10, restedStart = 1200, afkStart = 120, maxGrip = 1_000_000_000 }
		)
	end)

	t.test("defaults(now) follow §3.2 + the v2 Grip block", function()
		local d = ProfileSchema.defaults(NOW)
		expect.equal(d.schemaVersion, 2)
		expect.equal(d.createdAt, NOW)
		expect.equal(d.lastSeenAt, NOW)
		expect.equal(d.saveSeq, 0)
		expect.equal(d.coins, 0)
		expect.deepEqual(d.owned, { kitty_bread = { at = NOW, src = "starter" } })
		expect.equal(d.equipped, "kitty_bread")
		expect.equal(d.stats.squeezes, 0)
		expect.equal(d.stats.boxesOpened, 0)
		expect.deepEqual(d.squeezeLimit, { value = Config.Economy.SqueezeLimit.burst, at = NOW })
		expect.deepEqual(d.quests, { day = -1, swapsUsed = 0, active = {} })
		expect.deepEqual(d.starter, { progress = {}, claimed = {} })
		expect.deepEqual(d.daily, { lastClaimDay = -1, streakDay = 0, totalClaims = 0 })
		expect.deepEqual(d.settings, { music = 40, sfx = 70, cameraShake = true, showTips = true })
		expect.deepEqual(d.onboarding, { v = 1, done = {}, skipped = false })
		for _, log in { d.boxLog, d.shopLog, d.receipts, d.duelLog } do
			expect.deepEqual(log, {})
		end
		-- Phase 6: no slow-training bank (grip.afk) and no trainer (grip.trainer) any more.
		expect.deepEqual(d.grip, { total = 0, rested = { value = Config.Grip.Rested.burst, at = NOW } })
		expect.deepEqual(d.samePair, {})
		expect.equal(d.capsules, nil) -- pens3 phase 2: the capsules are gone
		expect.deepEqual(d.autoClick, { step = 0, at = 0 }) -- auto-clicker check (2026-10-16): no strike
		-- Pens3 phase 1: Kitty Bread walks in the 3 free spots.
		expect.deepEqual(
			d.pen,
			{ spots = 3, nextId = 2, items = { penItem(1, "kitty_bread", 0, 1, 0, 1) }, awayRate = 0 }
		)
		-- Pens3 phase 5: no gift waiting, no fixed-order box opened, the Frog gift still to come.
		expect.deepEqual(d.giftQueue, {})
		expect.deepEqual(d.boxOrder, { snack = 0, sweet = 0 })
		expect.deepEqual(d.gifts, { frog = false })
		-- Pens3 phases 7-8: nothing to buy back, an empty bag (one count per coating, Wax .. Galaxy).
		expect.deepEqual(d.buyBack, {})
		expect.deepEqual(d.bag, { 0, 0, 0, 0, 0, 0, 0 })
		expect.equal(#d.bag, #Config.Economy.Pen.coatMult - 1)
		-- defaults are valid as they are: sanitize changes nothing
		local _, problems = ProfileSchema.sanitize(TableUtil.deepCopy(d), { now = NOW })
		expect.deepEqual(problems, {})
	end)

	t.test("a v1 fixture becomes v2: 10 Grip per old squeeze, timers from lastSeenAt, the rest deep-equal", function()
		local before = TableUtil.deepCopy(FIXTURE_V1)
		local result = load(FIXTURE_V1)
		expect.equal(result.status, "ok")
		expect.equal(result.fromVersion, 1)
		expect.equal(result.migrated, true)
		-- Pens3 phase 1: the only fixes are the pen items of its other owned kinds (Banana, Toast), logged; phase 6:
		-- and the slot each of them gets.
		expect.equal(#result.problems, 4)
		expect.equal(penProblems(result.problems), 4)
		expect.deepEqual(result.profile, expectedV2(FIXTURE_V1))
		expect.equal(result.profile.grip.total, 12_340)
		-- the stored value is never changed (migrations run on a deep copy)
		expect.deepEqual(FIXTURE_V1, before)
	end)

	t.test("migrate returns the start version and works on a copy", function()
		local migrated, from, err = ProfileSchema.migrate(FIXTURE_V1)
		expect.equal(err, nil)
		expect.equal(from, 1)
		expect.equal(migrated.schemaVersion, 2)
		expect.truthy(migrated ~= FIXTURE_V1)
		expect.equal(FIXTURE_V1.schemaVersion, 1)
		expect.equal((FIXTURE_V1 :: any).grip, nil)
	end)

	t.test("an older v1 shape gets the missing fields from defaults", function()
		local old = TableUtil.deepCopy(FIXTURE_V1) :: any
		old.settings = nil
		old.onboarding = nil
		old.stats.boxesOpened = nil
		old.schemaVersion = nil -- a missing version counts as 1 (reading)
		local result = load(old)
		expect.equal(result.fromVersion, 1)
		expect.equal(result.profile.schemaVersion, 2)
		expect.deepEqual(result.profile.settings, { music = 40, sfx = 70, cameraShake = true, showTips = true })
		expect.deepEqual(result.profile.onboarding, { v = 1, done = {}, skipped = false })
		expect.equal(result.profile.stats.boxesOpened, 0)
		expect.equal(result.profile.grip.total, 12_340)
	end)

	t.test("the head start reads only stats.squeezes, and survives bad values", function()
		local cases: { { any } } = {
			{ 0, 0 },
			{ 5_000, 50_000 }, -- §17.10 example: Lv 8
			{ 12.9, 120 }, -- floored first
			{ "7", 70 }, -- tonumber
			{ -3, 0 },
			{ 0 / 0, 0 },
			{ math.huge, 0 },
			{ 200_000_000, 1_000_000_000 }, -- clamped to MAX_GRIP
			{ "lots", 0 },
		}
		for _, case in cases do
			local fixture = TableUtil.deepCopy(FIXTURE_V1) :: any
			fixture.stats.squeezes = case[1]
			local migrated = ProfileSchema.migrate(fixture)
			if migrated.grip.total ~= case[2] then
				error(`squeezes {tostring(case[1])}: grip {migrated.grip.total}, expected {case[2]}`)
			end
		end
		local noStats = TableUtil.deepCopy(FIXTURE_V1) :: any
		noStats.stats = nil
		expect.equal((ProfileSchema.migrate(noStats)).grip.total, 0)
		local noSeen = TableUtil.deepCopy(FIXTURE_V1) :: any
		noSeen.lastSeenAt = nil
		local migrated = ProfileSchema.migrate(noSeen)
		expect.deepEqual(migrated.grip.rested, { value = 1200, at = 0 })
	end)

	t.test("v2 is a no-op: loading a migrated profile again changes nothing", function()
		local first = load(FIXTURE_V1).profile
		local again = load(first)
		expect.equal(again.status, "ok")
		expect.equal(again.fromVersion, 2)
		expect.equal(again.migrated, false)
		expect.deepEqual(again.problems, {})
		expect.deepEqual(again.profile, first)
		local v2 = TableUtil.deepCopy(first)
		v2.grip.total = 777
		expect.equal(load(v2).profile.grip.total, 777) -- no second head start
	end)

	t.test("bad Grip values are sanitized (total, rested); an old save's afk and trainer stay as they are", function()
		local function gripAfter(grip: any): (any, { string })
			local profile = load(FIXTURE_V1).profile
			profile.grip = grip
			local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
			return fixed.grip, problems
		end
		local function timer(value: any, at: any): any
			return { value = value, at = at }
		end
		local grip, problems = gripAfter({ total = 0 / 0, rested = timer(5000, 0 / 0) })
		expect.deepEqual(grip, { total = 0, rested = timer(1200, NOW) })
		local mentionsNonFinite = false
		for _, problem in problems do
			if string.find(problem, "non-finite", 1, true) then
				mentionsNonFinite = true
			end
		end
		expect.truthy(mentionsNonFinite) -- a non-finite total is logged

		-- Above the 9 Qa maxGrip (spec 2026-10-12 §12): clamped to it.
		grip = gripAfter({ total = 1.8e16, rested = timer(-5, NOW + 300) })
		expect.deepEqual(grip, { total = Config.Grip.maxGrip, rested = timer(0, NOW + 300) })

		grip = gripAfter({ total = 12.7, rested = timer(0 / 0, math.huge) })
		expect.deepEqual(grip, { total = 12, rested = timer(0, NOW) })

		grip = gripAfter({ total = -5, rested = "garbage" })
		expect.deepEqual(grip, { total = 0, rested = timer(0, NOW) })

		grip = gripAfter("garbage")
		expect.deepEqual(grip, { total = 0, rested = timer(1200, NOW) })

		grip, problems = gripAfter({ total = 50_000, rested = timer(600.5, NOW) })
		expect.deepEqual(grip, { total = 50_000, rested = timer(600.5, NOW) })
		expect.deepEqual(problems, {})

		-- Phase 6: slow training and the trainers are gone, so nothing reads or fixes an old save's bank or trainer,
		-- even broken ones.
		grip, problems = gripAfter({ total = 5, trainer = 99, rested = timer(1, NOW), afk = timer(-1, NOW + 301) })
		expect.deepEqual(grip.afk, timer(-1, NOW + 301))
		expect.equal(grip.trainer, 99)
		expect.deepEqual(problems, {})
	end)

	t.test("v3 is newer than CURRENT: not migrated, READONLY view", function()
		local v3 = TableUtil.deepCopy(FIXTURE_V1) :: any
		v3.schemaVersion = 3
		v3.grip = { total = 5, trainer = 2, rested = { value = 1, at = NOW }, afk = { value = 2, at = NOW } }
		v3.futureField = { x = 1 }
		expect.equal(ProfileSchema.isNewer(v3), true)
		expect.equal(ProfileSchema.isNewer(FIXTURE_V1), false)
		local migrated, version, err = ProfileSchema.migrate(v3)
		expect.equal(migrated, nil)
		expect.equal(version, 3)
		expect.equal(err, "newer")
		local result = load(v3)
		expect.equal(result.status, "newer")
		expect.equal(result.migrated, false)
		expect.equal(result.profile.schemaVersion, 3) -- shown as stored, never rewritten
		expect.deepEqual(result.profile.futureField, { x = 1 })
		expect.equal(result.profile.coins, 12_345)
		expect.equal(v3.schemaVersion, 3)
	end)

	t.test("a stored value that is not a table is corrupt", function()
		local migrated, version, err = ProfileSchema.migrate("hello")
		expect.equal(migrated, nil)
		expect.equal(version, 0)
		expect.equal(err, "corrupt")
		local result = load(42)
		expect.equal(result.status, "corrupt")
		expect.equal(result.profile.coins, 0)
		-- nil is a key that was never written: defaults
		local fresh = load(nil)
		expect.equal(fresh.status, "ok")
		expect.equal(fresh.fromVersion, 2)
		expect.deepEqual(fresh.profile, ProfileSchema.defaults(NOW))
	end)

	t.test("sanitize: coins integer in range; non-finite -> 0", function()
		local cases: { { any } } = {
			{ 0 / 0, 0 },
			{ math.huge, 0 },
			{ -5, 0 },
			{ 1.7, 1 },
			{ 2e16, Config.Economy.maxCoins }, -- above the 9 Qa cap (spec 2026-10-12 §12)
			{ "100", 0 },
			{ 500, 500 },
		}
		for _, case in cases do
			local profile = load(FIXTURE_V1).profile
			profile.coins = case[1]
			local fixed = ProfileSchema.sanitize(profile, { now = NOW })
			if fixed.coins ~= case[2] then
				error(`coins {tostring(case[1])} -> {tostring(fixed.coins)}, expected {case[2]}`)
			end
		end
	end)

	t.test("sanitize: the starter is always owned; equipped falls back; unknown ids are kept", function()
		local profile = load(FIXTURE_V1).profile
		profile.owned.kitty_bread = nil
		profile.owned.retired_squishy = { at = 1, src = "box" }
		profile.owned.toast = "garbage"
		profile.owned.banana.src = "hacked"
		profile.equipped = "retired_squishy" -- owned but not in the Catalog
		local fixed = ProfileSchema.sanitize(profile, { now = NOW })
		expect.deepEqual(fixed.owned.kitty_bread, { at = NOW, src = "starter" })
		expect.deepEqual(fixed.owned.retired_squishy, { at = 1, src = "box" })
		expect.deepEqual(fixed.owned.toast, { at = NOW, src = "grant" }) -- stays owned
		expect.equal(fixed.owned.banana.src, "grant")
		expect.equal(fixed.equipped, "kitty_bread")

		local notOwned = load(FIXTURE_V1).profile
		notOwned.equipped = "dragon" -- in the Catalog, not owned
		expect.equal(ProfileSchema.sanitize(notOwned, { now = NOW }).equipped, "kitty_bread")
	end)

	t.test("sanitize: logs trimmed to the caps (newest kept); settings clamped", function()
		local profile = load(FIXTURE_V1).profile
		local cap = Config.Data.caps.duelLog
		profile.duelLog = {}
		for i = 1, cap + 5 do
			table.insert(profile.duelLog, { matchId = `m{i}`, opp = i, result = "win", at = i })
		end
		profile.receipts = { "not a table" :: any, { id = "r1", product = 1, coins = 1, at = 1 } }
		profile.settings = { music = 150, sfx = -3, cameraShake = "yes", showTips = false }
		local fixed = ProfileSchema.sanitize(profile, { now = NOW })
		expect.equal(#fixed.duelLog, cap)
		expect.equal(fixed.duelLog[1].matchId, "m6")
		expect.equal(fixed.duelLog[cap].matchId, `m{cap + 5}`)
		expect.deepEqual(fixed.receipts, { { id = "r1", product = 1, coins = 1, at = 1 } })
		expect.deepEqual(fixed.settings, { music = 100, sfx = 0, cameraShake = true, showTips = false })
	end)

	t.test("sanitize: quests of removed templates are dropped; claims fail closed", function()
		local profile = load(FIXTURE_V1).profile
		profile.quests.active[1].claimed = "maybe"
		profile.starter.claimed.starter_squeeze = 1
		local fixed = ProfileSchema.sanitize(profile, {
			now = NOW,
			questExists = function(defId: string): boolean
				return defId ~= "duel_play"
			end,
		})
		expect.equal(#fixed.quests.active, 2)
		expect.equal(fixed.quests.active[1].id, "q20775_1")
		expect.equal(fixed.quests.active[1].claimed, true) -- never paid twice
		expect.equal(fixed.quests.active[2].id, "q20775_3")
		expect.equal(fixed.starter.claimed.starter_squeeze, true)
		-- without QuestDefs (Part 7) every quest is kept
		local keep = ProfileSchema.sanitize(load(FIXTURE_V1).profile, { now = NOW })
		expect.equal(#keep.quests.active, 3)
	end)

	t.test("sanitize: wrong types become defaults; unknown fields are kept", function()
		local profile = load(FIXTURE_V1).profile :: any
		profile.stats = "garbage"
		profile.daily = { lastClaimDay = 0 / 0, streakDay = -2, totalClaims = 3.5 }
		profile.squeezeLimit = { value = 9999, at = NOW + 10_000 }
		profile.someFutureThing = { keep = true }
		local fixed = ProfileSchema.sanitize(profile, { now = NOW })
		expect.equal(fixed.stats.squeezes, 0)
		expect.deepEqual(fixed.daily, { lastClaimDay = math.floor(NOW / DAY), streakDay = 0, totalClaims = 3 })
		expect.deepEqual(fixed.squeezeLimit, { value = Config.Economy.SqueezeLimit.burst, at = NOW })
		expect.deepEqual((fixed :: any).someFutureThing, { keep = true })
	end)

	-- The same-pair record (§6.7, §12 #15) ------------------------------------------------------------------------------

	t.test("samePair joins schema 2 without a new version: an older v2 profile gets {} from reconcile", function()
		local older = load(FIXTURE_V1).profile :: any
		older.samePair = nil -- a v2 profile saved before the field existed
		local result = load(older)
		expect.equal(result.status, "ok")
		expect.equal(result.fromVersion, 2)
		expect.equal(result.migrated, false)
		expect.deepEqual(result.problems, {})
		expect.deepEqual(result.profile.samePair, {})
		expect.equal(result.profile.schemaVersion, ProfileSchema.CURRENT)
		-- A record that is there is kept as it is.
		local kept = load(FIXTURE_V1).profile :: any
		kept.samePair = { ["222"] = { NOW - 100, NOW - 50 } }
		local again = load(kept)
		expect.deepEqual(again.problems, {})
		expect.deepEqual(again.profile.samePair, { ["222"] = { NOW - 100, NOW - 50 } })
	end)

	t.test("sanitize samePair: bad keys and values dropped, bad times dropped, far-future times -> now", function()
		local function fixedRecord(record: any): (any, { string })
			local profile = load(FIXTURE_V1).profile :: any
			profile.samePair = record
			local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
			return (fixed :: any).samePair, problems
		end
		local record, problems = fixedRecord("garbage")
		expect.deepEqual(record, {})
		expect.truthy(#problems > 0)

		record = fixedRecord({
			["222"] = { NOW - 30, 0 / 0, NOW - 60, math.huge, "x" :: any, -math.huge }, -- non-finite / non-number dropped
			["333"] = { NOW + 300, NOW + 301, NOW + 1e9 }, -- skew allowed; later -> now (still counts, then expires)
			["-1"] = { NOW - 1 }, -- a Studio player
			["abc"] = { NOW }, -- not a userId
			["1e3"] = { NOW }, -- not written the way samePairKey writes it
			["007"] = { NOW },
			["44.5"] = { NOW },
			["555"] = "garbage", -- not a list
			["666"] = { 0 / 0 }, -- nothing left
			["777"] = { b = NOW - 5, a = NOW - 9 }, -- not an array: rebuilt from its numbers
			[42] = { NOW }, -- not a string key
		})
		expect.deepEqual(record, {
			["222"] = { NOW - 60, NOW - 30 },
			["333"] = { NOW, NOW, NOW + 300 },
			["-1"] = { NOW - 1 },
			["777"] = { NOW - 9, NOW - 5 },
		})

		-- A valid record passes unchanged.
		record, problems = fixedRecord({ ["222"] = { NOW - 60, NOW - 30 }, ["9999999999"] = { NOW } })
		expect.deepEqual(record, { ["222"] = { NOW - 60, NOW - 30 }, ["9999999999"] = { NOW } })
		expect.deepEqual(problems, {})
	end)

	t.test("sanitize samePair: sorted, and both caps (times per opponent, opponents)", function()
		local perOpponent = Config.Economy.DuelRewards.samePairFullRewards
		local cap = Config.Data.caps.samePair
		local profile = load(FIXTURE_V1).profile :: any
		local many = {}
		for i = 1, perOpponent + 4 do -- newest first: out of order
			table.insert(many, NOW - i)
		end
		profile.samePair = { ["222"] = many }
		for i = 1, cap do
			profile.samePair[tostring(1000 + i)] = { NOW - 10_000 + i } -- 1001 is met least recently
		end
		local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
		local samePair = (fixed :: any).samePair
		local times = samePair["222"]
		expect.equal(#times, perOpponent)
		expect.equal(times[1], NOW - perOpponent)
		expect.equal(times[perOpponent], NOW - 1)
		local count = 0
		for _ in samePair do
			count += 1
		end
		expect.equal(count, cap)
		expect.equal(samePair["1001"], nil)
		expect.deepEqual(samePair["1002"], { NOW - 10_000 + 2 })
		expect.truthy(#problems > 0)
	end)

	-- The win streak (Match HUD M2, 2026-10-16) --------------------------------------------------------------------------

	t.test("winStreak joins schema 2 without a new version: defaults 0, an older v2 profile gets 0", function()
		expect.equal(ProfileSchema.CURRENT, 2)
		expect.equal(ProfileSchema.defaults(NOW).stats.winStreak, 0)
		local older = load(FIXTURE_V1).profile :: any
		older.stats.winStreak = nil -- a v2 profile saved before the stat existed
		local result = load(older)
		expect.equal(result.status, "ok")
		expect.equal(result.fromVersion, 2)
		expect.equal(result.migrated, false)
		expect.deepEqual(result.problems, {})
		expect.equal(result.profile.stats.winStreak, 0)
		expect.equal(result.profile.schemaVersion, ProfileSchema.CURRENT)
		-- A saved streak is kept as it is.
		local kept = load(FIXTURE_V1).profile :: any
		kept.stats.winStreak = 7
		local again = load(kept)
		expect.deepEqual(again.problems, {})
		expect.equal(again.profile.stats.winStreak, 7)
	end)

	t.test("sanitize winStreak: negative, fractional, non-finite or not a number -> a whole number >= 0", function()
		local cases: { { any } } =
			{ { -4, 0 }, { 3.9, 3 }, { 0 / 0, 0 }, { math.huge, 0 }, { "5", 0 }, { 2 ^ 60, 2 ^ 53 } }
		for _, case in cases do
			local profile = load(FIXTURE_V1).profile :: any
			profile.stats.winStreak = case[1]
			local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
			expect.equal(fixed.stats.winStreak, case[2])
			expect.equal(#problems, 1)
		end
	end)

	-- Pens3 phase 2: capsules left defaults and sanitize with no new version; an old save keeps them as they are.
	t.test("an old save's capsules stay as an unknown field: never added, never fixed, kept through JSON", function()
		local HttpService = game:GetService("HttpService")
		expect.equal(load(FIXTURE_V1).profile.capsules, nil)
		local profile = load(FIXTURE_V1).profile :: any
		-- More slots than there ever were and a broken entry: nothing reads them, so nothing fixes them.
		profile.capsules = { slots = 9, list = { { level = 100, squishyId = "toast" }, "garbage" :: any } :: { any } }
		local result = load(HttpService:JSONDecode(HttpService:JSONEncode(profile)))
		expect.equal(result.status, "ok")
		expect.deepEqual(result.problems, {})
		expect.deepEqual(result.profile.capsules, profile.capsules)
	end)

	-- The last auto-clicker strike (auto-clicker check, 2026-10-16) -------------------------------------------------------

	t.test(
		"autoClick joins schema 2 without a new version: an older v2 profile gets no strike, a saved one stays",
		function()
			expect.equal(ProfileSchema.CURRENT, 2)
			local older = load(FIXTURE_V1).profile :: any
			older.autoClick = nil -- a v2 profile saved before the field existed
			local result = load(older)
			expect.equal(result.status, "ok")
			expect.equal(result.fromVersion, 2)
			expect.equal(result.migrated, false)
			expect.deepEqual(result.problems, {})
			expect.deepEqual(result.profile.autoClick, { step = 0, at = 0 })
			local kept = load(FIXTURE_V1).profile :: any
			kept.autoClick = { step = 2, at = NOW - 600 }
			local again = load(kept)
			expect.deepEqual(again.problems, {})
			expect.deepEqual(again.profile.autoClick, { step = 2, at = NOW - 600 })
		end
	)

	t.test("sanitize autoClick: step whole in [0, MAX_STEP], at in [0, now + 300]; broken values forget", function()
		-- Batch B (2026-10-17): the ladder's last step (a 1st ban, then the longer ones) is the most a record keeps.
		local MAX_STEP = t.requireServer("Logic/AutoClickRules").MAX_STEP
		expect.equal(MAX_STEP, 5)
		local function fixedStrike(value: any): (any, { string })
			local profile = load(FIXTURE_V1).profile :: any
			profile.autoClick = value
			local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
			return (fixed :: any).autoClick, problems
		end
		local cases: { { any } } = {
			{ "garbage", { step = 0, at = 0 } },
			{ { step = 7, at = NOW }, { step = MAX_STEP, at = NOW } },
			{ { step = -1, at = NOW }, { step = 0, at = NOW } },
			{ { step = 1.5, at = NOW }, { step = 1, at = NOW } },
			{ { step = 0 / 0, at = 0 / 0 }, { step = 0, at = 0 } },
			{ { step = "2", at = NOW }, { step = 0, at = NOW } },
			{ { step = 2, at = NOW + 10_000 }, { step = 2, at = NOW + 300 } }, -- a far-future strike is clamped
			{ { step = 1, at = -5 }, { step = 1, at = 0 } },
		}
		for _, case in cases do
			local strike, problems = fixedStrike(case[1])
			expect.deepEqual(strike, case[2])
			expect.truthy(#problems > 0)
		end
		local strike, problems = fixedStrike({ step = 3, at = NOW - 1 })
		expect.deepEqual(strike, { step = 3, at = NOW - 1 })
		expect.deepEqual(problems, {})
		local longest, none = fixedStrike({ step = MAX_STEP, at = NOW - 1 }) -- a later, longer ban is kept
		expect.deepEqual(longest, { step = MAX_STEP, at = NOW - 1 })
		expect.deepEqual(none, {})
	end)

	-- Weekly quests (2026-10-17) --------------------------------------------------------------------------------------

	local function weeklyEntry(slot: number, def: string): any
		return {
			id = `w2856_{slot}`,
			def = def,
			progress = 3,
			goal = 10,
			reward = 2000,
			done = false,
			claimed = false,
		}
	end

	t.test("weekly joins schema 2 without a new version: an older v2 profile gets none, a saved week stays", function()
		expect.equal(ProfileSchema.CURRENT, 2)
		expect.deepEqual(ProfileSchema.defaults(NOW).weekly, { week = -1, active = {} })
		local older = load(FIXTURE_V1).profile :: any
		older.weekly = nil -- a v2 profile saved before the field existed
		local result = load(older)
		expect.equal(result.fromVersion, 2)
		expect.deepEqual(result.problems, {})
		expect.deepEqual(result.profile.weekly, { week = -1, active = {} })
		local kept = load(FIXTURE_V1).profile :: any
		kept.weekly = { week = 2856, active = { weeklyEntry(1, "weekly_squeeze"), weeklyEntry(2, "weekly_duel_win") } }
		local saved = TableUtil.deepCopy(kept.weekly)
		local again = load(kept, {
			questExists = function(_defId: string): boolean
				return true
			end,
		})
		expect.deepEqual(again.problems, {})
		expect.deepEqual(again.profile.weekly, saved)
		-- It survives the JSON a DataStore keeps unchanged.
		local HttpService = game:GetService("HttpService")
		local decoded = HttpService:JSONDecode(HttpService:JSONEncode(again.profile))
		expect.deepEqual(load(decoded).profile.weekly, saved)
	end)

	t.test("sanitize weekly: week a whole number >= -1, entries like the daily quests', claims fail closed", function()
		local function fixedWeekly(value: any, exists: ((string) -> boolean)?): (any, { string })
			local profile = load(FIXTURE_V1).profile :: any
			profile.weekly = value
			local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW, questExists = exists })
			return (fixed :: any).weekly, problems
		end
		local broken, problems = fixedWeekly("garbage")
		expect.deepEqual(broken, { week = -1, active = {} })
		expect.truthy(#problems > 0)
		local fractional = fixedWeekly({ week = 12.5, active = {} })
		expect.equal(fractional.week, 12)
		local tooLow = fixedWeekly({ week = -9, active = {} })
		expect.equal(tooLow.week, -1)
		local noList = fixedWeekly({ week = 3, active = "x" })
		expect.deepEqual(noList.active, {})
		local entry = weeklyEntry(1, "weekly_squeeze")
		entry.claimed = "yes" -- not a boolean: counts as claimed (never pay twice)
		entry.progress = -4
		local fixed = fixedWeekly({ week = 3, active = { entry, 7, weeklyEntry(2, "gone_quest") } }, function(defId)
			return defId ~= "gone_quest"
		end)
		expect.equal(#fixed.active, 1)
		expect.equal(fixed.active[1].claimed, true)
		expect.equal(fixed.active[1].progress, 0)
	end)

	-- The pen (pens3 phase 1) -----------------------------------------------------------------------------------------

	-- The pen and owned list sanitize makes of `pen` on a loaded fixture (owns kitty_bread, toast and banana).
	local function fixedPen(pen: any, owned: any?): (any, any, { string })
		local profile = load(FIXTURE_V1).profile :: any
		profile.pen = pen
		if owned ~= nil then
			profile.owned = owned
		end
		local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
		return (fixed :: any).pen, (fixed :: any).owned, problems
	end

	t.test("pen joins schema 2 without a new version: an older profile gets one plain item per owned kind", function()
		expect.equal(ProfileSchema.CURRENT, 2)
		local older = load(FIXTURE_V1).profile :: any
		older.pen = nil -- a v2 profile saved before the field existed
		older.owned.dragon = { at = 5, src = "box" }
		local result = load(older)
		expect.equal(result.fromVersion, 2)
		expect.equal(result.migrated, false)
		expect.deepEqual(result.profile.pen, {
			spots = 3,
			nextId = 5,
			items = {
				penItem(1, "kitty_bread", 0, 1, 0, 1), -- the default's slot 1
				penItem(2, "banana", 0, 1, 0, 3),
				penItem(3, "dragon", 0, 1, 0, 2), -- phase 6: the best of the added items takes the first free spot
				penItem(4, "toast"), -- the Toy Box: the 3 spots are full
			},
			awayRate = 0, -- pens3 phase 4: from reconcile
		})
		expect.equal(penProblems(result.problems), 6) -- every added item is logged, and its slot
		-- The next load changes nothing.
		local again = load(result.profile)
		expect.deepEqual(again.problems, {})
		expect.deepEqual(again.profile.pen, result.profile.pen)
	end)

	t.test("sanitize pen: spots clamped, not a table or not a list fixed, form / level / coat clamped", function()
		local maxLevel = Config.Economy.Pen.maxLevel
		local pen, _, problems = fixedPen("garbage")
		expect.equal(pen.spots, 3)
		expect.equal(#pen.items, 3) -- every owned kind gets its item back
		expect.truthy(#problems > 0)
		for _, case in { { 2, 3 }, { 13, 12 }, { 7.6, 7 }, { 0 / 0, 3 }, { "9", 3 } } :: { { any } } do
			local fixed = fixedPen({ spots = case[1], nextId = 4, items = load(FIXTURE_V1).profile.pen.items })
			expect.equal(fixed.spots, case[2])
		end
		local fixed = fixedPen({
			spots = 3,
			nextId = 4,
			items = {
				oldItem(1, "kitty_bread", 3, 0, 9), -- form above Rainbow, level 0, coat past Galaxy
				oldItem(2, "toast", -1, maxLevel + 5, -2),
				{ id = 3, kind = "banana", form = 0 / 0, level = "high", coat = math.huge },
			},
		})
		expect.deepEqual(fixed.items, { -- phase 6: the slots from the fixed rates (Toast Lv max, then Kitty Bread)
			penItem(1, "kitty_bread", 2, 1, 7, 2),
			penItem(2, "toast", 0, maxLevel, 0, 1),
			penItem(3, "banana", 0, 1, 0, 3),
		})
		local notList = fixedPen({ spots = 3, nextId = 4, items = "x" })
		expect.equal(#notList.items, 3) -- rebuilt from owned
	end)

	t.test("sanitize pen ids: a bad or repeated id gets a fresh one, never dropped; nextId above every id", function()
		local pen, _, problems = fixedPen({
			spots = 3,
			nextId = 2, -- stale: below the ids in use
			items = {
				penItem(7, "kitty_bread", 0, 1, 0, 1),
				penItem(7, "toast", 0, 1, 0, 2), -- a repeat: a fresh id
				penItem(0, "banana"), -- not an id: a fresh one
				penItem(2.5, "banana", 1, 1, 0, 3), -- a second Banana (a copy), fractional id
			},
		})
		expect.deepEqual(pen, {
			spots = 3,
			nextId = 11,
			items = {
				penItem(7, "kitty_bread", 0, 1, 0, 1),
				penItem(8, "toast", 0, 1, 0, 2),
				penItem(9, "banana"),
				penItem(10, "banana", 1, 1, 0, 3),
			},
		})
		expect.equal(penProblems(problems), 4) -- 3 ids and the stale nextId (a new id keeps its slot)
	end)

	t.test("sanitize pen invariants: owned and the pen agree, nothing anyone owns is lost", function()
		-- An unknown kind is dropped (its owned entry stays, like owned keeps a removed id); a pen squishy that is not
		-- owned becomes owned; an owned kind with no item gets one.
		local owned = {
			kitty_bread = { at = 1, src = "starter" },
			retired_squishy = { at = 2, src = "box" },
			toast = { at = 3, src = "shop" },
		}
		local pen, fixedOwned, problems = fixedPen({
			spots = 4,
			nextId = 3,
			items = {
				penItem(1, "kitty_bread", 0, 1, 0, 2),
				penItem(2, "retired_squishy", 0, 1, 0, 3),
				"garbage" :: any, -- not an item at all
				penItem(3, "dragon", 1, 9, 0, 1),
			},
		}, owned)
		expect.deepEqual(pen, {
			spots = 4,
			nextId = 5,
			items = {
				penItem(1, "kitty_bread", 0, 1, 0, 2),
				penItem(3, "dragon", 1, 9, 0, 1),
				penItem(4, "toast", 0, 1, 0, 3), -- phase 6: the retired squishy's spot is free again
			},
		})
		expect.deepEqual(fixedOwned.dragon, { at = NOW, src = "grant" })
		expect.deepEqual(fixedOwned.retired_squishy, { at = 2, src = "box" })
		expect.truthy(penProblems(problems) >= 3)
	end)

	t.test("sanitize pen: more items than toyBoxMax + placedMax are all kept, and logged", function()
		local cap = Config.Economy.Pen.toyBoxMax + Config.Economy.Pen.placedMax
		local items = {}
		for id = 1, cap + 3 do
			local slot = if id <= 12 then id else 0 -- phase 6: good slots, so only the cap is logged
			table.insert(items, penItem(id, if id % 2 == 0 then "toast" else "kitty_bread", 0, 1, 0, slot))
		end
		table.insert(items, penItem(cap + 4, "banana"))
		local pen, _, problems = fixedPen({ spots = 12, nextId = cap + 5, items = TableUtil.deepCopy(items) })
		expect.deepEqual(pen.items, items)
		expect.equal(penProblems(problems), 1)
	end)

	t.test("the pen survives a save and load (the HttpService JSON DataStores keep) unchanged", function()
		local HttpService = game:GetService("HttpService")
		local profile = load(FIXTURE_V1).profile :: any
		profile.pen = {
			spots = 12,
			nextId = 9,
			items = {
				penItem(1, "kitty_bread", 2, 70, 7, 1),
				penItem(4, "toast", 1, 12, 3, 12, true), -- phase 6: a slot and a lock survive
				penItem(8, "banana"),
			},
			awayRate = 1_234_567.25, -- pens3 phase 4: a rate with a fraction (a levelled pen)
		}
		local result = load(HttpService:JSONDecode(HttpService:JSONEncode(profile)))
		expect.equal(result.status, "ok")
		expect.deepEqual(result.problems, {})
		expect.deepEqual(result.profile.pen, profile.pen)
	end)

	-- Pens3 phase 6: where each squishy is (slot) and its lock.
	t.test(
		"pen slots join schema 2: an older save's items get slots once, from the best-N order; locks false",
		function()
			local PenMath = t.requireShared("PenMath")
			local items = {
				oldItem(1, "kitty_bread"),
				oldItem(2, "butter"),
				oldItem(3, "toast"),
				oldItem(4, "banana"),
				oldItem(5, "dragon"),
			}
			-- What the pen paid before phase 6: its best 3 (Dragon, Butter, then Kitty Bread: the lower id of the 10s).
			local paid = 640 + 40 + 10
			local pen, owned, problems = fixedPen({ spots = 3, nextId = 6, items = items, awayRate = 0 })
			expect.deepEqual(pen.items, {
				penItem(1, "kitty_bread", 0, 1, 0, 3),
				penItem(2, "butter", 0, 1, 0, 2),
				penItem(3, "toast"),
				penItem(4, "banana"),
				penItem(5, "dragon", 0, 1, 0, 1),
			})
			expect.equal(PenMath.rate(pen), paid) -- the same squishies keep paying
			expect.equal(penProblems(problems), 5) -- one note per derived slot; a missing lock is not a fix
			-- Once: the next sanitize finds nothing to fix.
			local profile = load(FIXTURE_V1).profile :: any
			profile.pen, profile.owned = pen, owned
			local _, again = ProfileSchema.sanitize(profile, { now = NOW })
			expect.deepEqual(again, {})
		end
	)

	t.test("sanitize pen slots: closed, repeated or broken -> the Toy Box, never dropped, logged; locks", function()
		local pen, _, problems = fixedPen({
			spots = 3,
			nextId = 9,
			items = {
				penItem(1, "kitty_bread", 0, 1, 0, 2), -- good: kept
				penItem(2, "toast", 0, 1, 0, 2), -- slot 2 again: the Toy Box
				penItem(3, "banana", 0, 1, 0, 7), -- a spot not bought: the Toy Box
				penItem(4, "toast", 0, 1, 0, 1.5), -- broken: the Toy Box
				penItem(5, "toast", 0, 1, 0, -1), -- broken: the Toy Box
				{ id = 6, kind = "toast", form = 0, level = 1, coat = 0, slot = "1", locked = false },
				oldItem(7, "banana"), -- no slot: the first free spot (1)
				{ id = 8, kind = "kitty_bread", form = 0, level = 1, coat = 0, slot = 0, locked = "yes" }, -- broken
			},
		})
		expect.deepEqual(pen.items, {
			penItem(1, "kitty_bread", 0, 1, 0, 2),
			penItem(2, "toast"),
			penItem(3, "banana"),
			penItem(4, "toast"),
			penItem(5, "toast"),
			penItem(6, "toast"),
			penItem(7, "banana", 0, 1, 0, 1),
			penItem(8, "kitty_bread"),
		})
		expect.equal(#pen.items, 8) -- nothing anyone owns is lost
		expect.equal(penProblems(problems), 7) -- 5 slots sent to the Toy Box, 1 derived, 1 lock
		-- A locked squishy stays locked, wherever it is.
		local locked = fixedPen({
			spots = 3,
			nextId = 3,
			items = { penItem(1, "kitty_bread", 0, 1, 0, 1, true), penItem(2, "toast", 0, 1, 0, 0, true) },
		})
		expect.equal(locked.items[1].locked, true)
		expect.equal(locked.items[2].locked, true)
	end)

	-- Pens3 phase 4: the pen's rate at the last save (DataService stamps it), what the next load pays away time from.
	t.test(
		"pen.awayRate joins schema 2: reconcile gives an older pen 0; a bad rate becomes 0, a good one stays",
		function()
			local older = load(FIXTURE_V1).profile :: any
			older.pen.awayRate = nil -- a pen saved before phase 4
			local result = load(older)
			expect.equal(result.profile.pen.awayRate, 0)
			expect.deepEqual(result.problems, {})
			for _, case in
				{ { 51.5, 51.5 }, { 0, 0 }, { -10, 0 }, { 0 / 0, 0 }, { math.huge, 0 }, { "50", 0 } } :: { { any } }
			do
				local pen, _, problems = fixedPen({
					spots = 3,
					nextId = 2,
					items = { penItem(1, "kitty_bread", 0, 1, 0, 1) },
					awayRate = case[1],
				})
				expect.equal(pen.awayRate, case[2])
				local logged = false
				for _, problem in problems do
					logged = logged or string.sub(problem, 1, 13) == "pen.awayRate:"
				end
				expect.equal(logged, case[1] ~= case[2]) -- every fix is logged, a good rate is not
			end
			local garbage = fixedPen("garbage")
			expect.equal(garbage.awayRate, 0)
		end
	)

	-- Pens3 phase 5 (copies): the gift queue, the fixed box orders, the gifts given ----------------------------------

	-- The sanitize notes whose path starts with `prefix`.
	local function notesAbout(problems: { string }, prefix: string): number
		local count = 0
		for _, problem in problems do
			if string.sub(problem, 1, #prefix) == prefix then
				count += 1
			end
		end
		return count
	end

	t.test(
		"giftQueue, boxOrder and gifts join schema 2 without a new version: an older profile gets them, no problem",
		function()
			expect.equal(ProfileSchema.CURRENT, 2)
			local older = load(FIXTURE_V1).profile :: any
			older.giftQueue, older.boxOrder, older.gifts = nil, nil, nil -- a v2 profile saved before phase 5
			local result = load(older)
			expect.equal(result.fromVersion, 2)
			expect.equal(result.migrated, false)
			expect.deepEqual(result.problems, {})
			expect.deepEqual(result.profile.giftQueue, {})
			expect.deepEqual(result.profile.boxOrder, { snack = 0, sweet = 0 })
			expect.deepEqual(result.profile.gifts, { frog = false })
			-- Saved values stay, through JSON too.
			local HttpService = game:GetService("HttpService")
			local kept = load(FIXTURE_V1).profile :: any
			kept.giftQueue = { "strawberry_frog", "bird" }
			kept.boxOrder = { snack = 11, sweet = 2_500 }
			kept.gifts = { frog = true }
			local again = load(HttpService:JSONDecode(HttpService:JSONEncode(kept)))
			expect.deepEqual(again.problems, {})
			expect.deepEqual(again.profile.giftQueue, { "strawberry_frog", "bird" })
			expect.deepEqual(again.profile.boxOrder, { snack = 11, sweet = 2_500 })
			expect.deepEqual(again.profile.gifts, { frog = true })
		end
	)

	t.test(
		"sanitize giftQueue: only Catalog kinds stay, in order; not a list fixed; a long queue kept, logged",
		function()
			local function fixedQueue(value: any): ({ string }, { string })
				local profile = load(FIXTURE_V1).profile :: any
				profile.giftQueue = value
				local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
				return fixed.giftQueue, problems
			end
			local queue, problems = fixedQueue({ "toast", "unicorn", 5 :: any, "bird" })
			expect.deepEqual(queue, { "toast", "bird" }) -- a kind gone or not a kind is dropped (none is owned yet)
			expect.equal(notesAbout(problems, "giftQueue"), 3) -- each drop, and the new length
			local garbage, garbageProblems = fixedQueue("frog")
			expect.deepEqual(garbage, {})
			expect.equal(notesAbout(garbageProblems, "giftQueue"), 1)
			local notAList: any = { "toast", "banana" }
			notAList.x = "bird" -- a key outside the list part (only a bug or a hand edit makes one)
			local mixed = fixedQueue(notAList)
			expect.deepEqual(mixed, { "toast", "banana" })
			-- More than giftQueueMax can only come from a bug: every one is kept (squishies someone was given).
			local long: { string } = {}
			for _ = 1, Config.Economy.Pen.giftQueueMax + 2 do
				table.insert(long, "toast")
			end
			local kept, longProblems = fixedQueue(long)
			expect.equal(#kept, Config.Economy.Pen.giftQueueMax + 2)
			expect.equal(notesAbout(longProblems, "giftQueue (over giftQueueMax, all kept)"), 1)
			-- A good queue is not touched.
			local good, goodProblems = fixedQueue({ "toast", "toast", "dragon" })
			expect.deepEqual(good, { "toast", "toast", "dragon" })
			expect.equal(notesAbout(goodProblems, "giftQueue"), 0)
		end
	)

	t.test("sanitize boxOrder: a whole number >= 0 per paid box (broken -> 0, logged); other keys kept", function()
		local profile = load(FIXTURE_V1).profile :: any
		profile.boxOrder = { snack = 7.9, sweet = -3, mystery = 4 }
		local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
		expect.deepEqual(fixed.boxOrder, { snack = 7, sweet = 0, mystery = 4 })
		expect.equal(notesAbout(problems, "boxOrder"), 2)
		profile.boxOrder = { snack = 0 / 0, sweet = "12" }
		fixed = ProfileSchema.sanitize(profile, { now = NOW })
		expect.deepEqual(fixed.boxOrder, { snack = 0, sweet = 0 })
		profile.boxOrder = "garbage"
		fixed = ProfileSchema.sanitize(profile, { now = NOW })
		expect.deepEqual(fixed.boxOrder, { snack = 0, sweet = 0 })
	end)

	t.test("sanitize gifts: fail closed, a broken flag or a broken table counts every gift as given", function()
		local profile = load(FIXTURE_V1).profile :: any
		profile.gifts = { frog = "yes", [3] = true }
		local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
		expect.deepEqual(fixed.gifts, { frog = true }) -- never given twice
		expect.equal(notesAbout(problems, "gifts"), 2)
		profile.gifts = "garbage"
		fixed = ProfileSchema.sanitize(profile, { now = NOW })
		expect.deepEqual(fixed.gifts, { frog = true })
		profile.gifts = { frog = false }
		local _, clean = ProfileSchema.sanitize(profile, { now = NOW })
		expect.equal(notesAbout(clean, "gifts"), 0)
	end)

	-- Pens3 phases 7-8 (selling, the buy-back, fusion): buyBack and bag ----------------------------------------------

	-- A buy-back entry: a sold Toast `age` seconds ago for 1,000 Coins.
	local function sold(id: number, age: number?): any
		return {
			item = penItem(id, "toast"),
			price = 1_000,
			at = NOW - (age or 0),
			req = "0123abcd-4567-89ab-cdef-0123456789ab",
		}
	end

	t.test("buyBack and bag join schema 2 without a new version: an older profile gets them, no problem", function()
		expect.equal(ProfileSchema.CURRENT, 2)
		local older = load(FIXTURE_V1).profile :: any
		older.buyBack, older.bag = nil, nil -- a v2 profile saved before phase 7
		local result = load(older)
		expect.equal(result.fromVersion, 2)
		expect.deepEqual(result.problems, {})
		expect.deepEqual(result.profile.buyBack, {})
		expect.deepEqual(result.profile.bag, { 0, 0, 0, 0, 0, 0, 0 })
		local HttpService = game:GetService("HttpService")
		local kept = load(FIXTURE_V1).profile :: any
		kept.buyBack = { sold(40, 30), sold(41) }
		kept.bag = { 2, 0, 0, 1, 0, 0, 5 }
		local again = load(HttpService:JSONDecode(HttpService:JSONEncode(kept)))
		expect.deepEqual(again.problems, {})
		expect.deepEqual(again.profile.buyBack, { sold(40, 30), sold(41) })
		expect.deepEqual(again.profile.bag, { 2, 0, 0, 1, 0, 0, 5 })
	end)

	t.test("sanitize buyBack: broken entries dropped (fail closed), logged; the newest buyBackMax kept", function()
		local function fixedList(value: any): ({ any }, { string })
			local profile = load(FIXTURE_V1).profile :: any
			profile.buyBack = value
			local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
			return fixed.buyBack, problems
		end
		local good = sold(10)
		local badKind = sold(11)
		badKind.item.kind = "unicorn"
		local badForm = sold(12)
		badForm.item.form = 3
		local badId = sold(13)
		badId.item.id = 1.5
		local badPrice = sold(14)
		badPrice.price = -1
		local badAt = sold(15)
		badAt.at = NOW + 301 -- later than now + 300: it would wait past its 10 minutes
		local badReq = sold(16)
		badReq.req = 5
		local nan = sold(17)
		nan.price = 0 / 0
		local list, problems = fixedList({ good, badKind, badForm, badId, badPrice, badAt, badReq, nan, "x" :: any })
		expect.deepEqual(list, { sold(10) })
		expect.equal(notesAbout(problems, "buyBack"), 9) -- each drop, and the new length
		local garbage, garbageProblems = fixedList("garbage")
		expect.deepEqual(garbage, {})
		expect.equal(notesAbout(garbageProblems, "buyBack"), 1)
		local long = {}
		for id = 1, Config.Economy.Pen.buyBackMax + 2 do
			table.insert(long, sold(id))
		end
		local trimmed, longProblems = fixedList(long)
		expect.equal(#trimmed, Config.Economy.Pen.buyBackMax)
		expect.equal(trimmed[1].item.id, 3) -- the oldest fall off first
		expect.equal(notesAbout(longProblems, "buyBack"), 1)
		local fine, fineProblems = fixedList({ sold(20, 900), sold(21) }) -- an expired one is not broken: kept
		expect.equal(#fine, 2)
		expect.equal(notesAbout(fineProblems, "buyBack"), 0)
	end)

	t.test("sanitize bag: one whole count >= 0 per coating; broken -> 0, missing -> 0, extra keys dropped", function()
		local function fixedBag(value: any): ({ number }, { string })
			local profile = load(FIXTURE_V1).profile :: any
			profile.bag = value
			local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
			return fixed.bag, problems
		end
		local raw: any = { 2.7, -1, 0 / 0, "3" :: any, 4, 0, 1, 9 }
		raw.x = 2 -- a key outside the list (only a bug or a hand edit makes one)
		local bag, problems = fixedBag(raw)
		expect.deepEqual(bag, { 2, 0, 0, 0, 4, 0, 1 })
		expect.equal(notesAbout(problems, "bag"), 6) -- four counts, the eighth entry and x
		local short, shortProblems = fixedBag({ 1, 2 })
		expect.deepEqual(short, { 1, 2, 0, 0, 0, 0, 0 })
		expect.equal(notesAbout(shortProblems, "bag"), 5)
		local garbage = fixedBag("garbage")
		expect.deepEqual(garbage, { 0, 0, 0, 0, 0, 0, 0 })
		local _, clean = fixedBag({ 0, 1, 0, 0, 0, 0, 3 })
		expect.equal(notesAbout(clean, "bag"), 0)
	end)
end
