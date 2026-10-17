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
--   * capsules (spec 2026-10-12 §6-§7) joined schema 2 the same way: one free Kitty Bread capsule at Lv 1, sanitize
--     fails closed (slots and levels clamped, one entry per slot, a squishy owned and in one capsule only), and they
--     survive a JSON save and load unchanged;
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
--     owned; nextId above every id; a pen past toyBoxMax + placedMax kept whole and logged; JSON round trip unchanged.

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

	-- A pen item (pens3 phase 1), plain Lv 1 unless told.
	local function penItem(id: number, kind: string, form: number?, level: number?, coat: number?): any
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
		expected.capsules = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } } -- the same
		expected.stats.winStreak = 0 -- Match HUD M2: the same
		expected.autoClick = { step = 0, at = 0 } -- auto-clicker check (2026-10-16): the same
		expected.weekly = { week = -1, active = {} } -- weekly quests (2026-10-17): the same
		-- Pens3 phase 1: the default pen (Kitty Bread, id 1), then one item per other owned kind, in id order.
		expected.pen = { spots = 3, nextId = 2, items = { penItem(1, "kitty_bread") } }
		for _, kind in { "banana", "toast" } do
			if fixture.owned[kind] ~= nil then
				table.insert(expected.pen.items, penItem(expected.pen.nextId, kind))
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
		expect.deepEqual(d.capsules, { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } })
		expect.deepEqual(d.autoClick, { step = 0, at = 0 }) -- auto-clicker check (2026-10-16): no strike
		-- Pens3 phase 1: Kitty Bread walks in the 3 free spots.
		expect.deepEqual(d.pen, { spots = 3, nextId = 2, items = { penItem(1, "kitty_bread") } })
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
		-- Pens3 phase 1: the only fixes are the pen items of its other owned kinds (Banana, Toast), logged.
		expect.equal(#result.problems, 2)
		expect.equal(penProblems(result.problems), 2)
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

	-- Capsules (progression spec 2026-10-12 §6-§7) ---------------------------------------------------------------------

	local STARTER_CAPSULES = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } }

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

	t.test("capsules join schema 2 without a new version: an older v2 profile gets the free capsule", function()
		local older = load(FIXTURE_V1).profile :: any
		older.capsules = nil -- a v2 profile saved before the field existed
		local result = load(older)
		expect.equal(result.fromVersion, 2)
		expect.equal(result.migrated, false)
		expect.deepEqual(result.problems, {})
		expect.deepEqual(result.profile.capsules, STARTER_CAPSULES)
		expect.equal(result.profile.schemaVersion, ProfileSchema.CURRENT)
	end)

	t.test("sanitize capsules: slots and levels clamped, one entry per slot, a squishy in one capsule only", function()
		local function fixedCapsules(capsules: any): (any, { string })
			local profile = load(FIXTURE_V1).profile :: any -- owns kitty_bread, toast and banana
			profile.capsules = capsules
			local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
			return (fixed :: any).capsules, problems
		end
		local maxLevel = Config.Grip.Capsule.maxLevel
		local capsules, problems = fixedCapsules("garbage")
		expect.deepEqual(capsules, STARTER_CAPSULES)
		expect.truthy(#problems > 0)

		capsules = fixedCapsules({
			slots = 9, -- more than the 4 slots
			list = {
				{ level = 0, squishyId = "toast" }, -- below Lv 1
				{ level = 5.7, squishyId = "toast" }, -- floored; toast is already in capsule 1
				{ level = maxLevel + 1, squishyId = "dragon" }, -- capped; dragon is not owned
				"garbage" :: any, -- not a capsule: an empty Lv 1 one
				{ level = 3 }, -- beyond the slots: dropped
			} :: { any },
		})
		expect.deepEqual(capsules, {
			slots = #Config.Grip.Capsule.slotPrices,
			list = { { level = 1, squishyId = "toast" }, { level = 5 }, { level = maxLevel }, { level = 1 } } :: { any },
		})

		-- Not a number, not in the Catalog, a missing capsule.
		capsules = fixedCapsules({ slots = 0 / 0, list = { { level = 0 / 0, squishyId = "retired_squishy" } } })
		expect.deepEqual(capsules, { slots = 1, list = { { level = 1 } } })
		capsules = fixedCapsules({ slots = 2.9, list = { { level = 7, squishyId = "banana" } } })
		expect.deepEqual(
			capsules,
			{ slots = 2, list = { { level = 7, squishyId = "banana" }, { level = 1 } } :: { any } }
		)

		-- A valid set passes unchanged.
		local valid = {
			slots = 3,
			list = {
				{ level = maxLevel, squishyId = "kitty_bread" },
				{ level = 42 },
				{ level = 11, squishyId = "banana" },
			} :: { any },
		}
		capsules, problems = fixedCapsules(TableUtil.deepCopy(valid))
		expect.deepEqual(capsules, valid)
		expect.deepEqual(problems, {})
	end)

	t.test("capsules survive a save and load (the HttpService JSON DataStores keep) unchanged", function()
		local HttpService = game:GetService("HttpService")
		local profile = load(FIXTURE_V1).profile :: any
		profile.capsules = {
			slots = 3,
			list = { { level = 100, squishyId = "toast" }, { level = 1 }, { level = 57, squishyId = "banana" } } :: { any },
		}
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
				penItem(1, "kitty_bread"),
				penItem(2, "banana"),
				penItem(3, "dragon"),
				penItem(4, "toast"),
			},
		})
		expect.equal(penProblems(result.problems), 3) -- every added item is logged
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
				penItem(1, "kitty_bread", 3, 0, 9), -- form above Rainbow, level 0, coat past Galaxy
				penItem(2, "toast", -1, maxLevel + 5, -2),
				{ id = 3, kind = "banana", form = 0 / 0, level = "high", coat = math.huge },
			},
		})
		expect.deepEqual(fixed.items, {
			penItem(1, "kitty_bread", 2, 1, 7),
			penItem(2, "toast", 0, maxLevel, 0),
			penItem(3, "banana", 0, 1, 0),
		})
		local notList = fixedPen({ spots = 3, nextId = 4, items = "x" })
		expect.equal(#notList.items, 3) -- rebuilt from owned
	end)

	t.test("sanitize pen ids: a bad or repeated id gets a fresh one, never dropped; nextId above every id", function()
		local pen, _, problems = fixedPen({
			spots = 3,
			nextId = 2, -- stale: below the ids in use
			items = {
				penItem(7, "kitty_bread"),
				penItem(7, "toast"), -- a repeat: a fresh id
				penItem(0, "banana"), -- not an id: a fresh one
				penItem(2.5, "banana", 1), -- a second Banana (a copy), fractional id
			},
		})
		expect.deepEqual(pen, {
			spots = 3,
			nextId = 11,
			items = {
				penItem(7, "kitty_bread"),
				penItem(8, "toast"),
				penItem(9, "banana"),
				penItem(10, "banana", 1),
			},
		})
		expect.equal(penProblems(problems), 4) -- 3 ids and the stale nextId
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
				penItem(1, "kitty_bread"),
				penItem(2, "retired_squishy"),
				"garbage" :: any, -- not an item at all
				penItem(3, "dragon", 1, 9),
			},
		}, owned)
		expect.deepEqual(pen, {
			spots = 4,
			nextId = 5,
			items = { penItem(1, "kitty_bread"), penItem(3, "dragon", 1, 9), penItem(4, "toast") },
		})
		expect.deepEqual(fixedOwned.dragon, { at = NOW, src = "grant" })
		expect.deepEqual(fixedOwned.retired_squishy, { at = 2, src = "box" })
		expect.truthy(penProblems(problems) >= 3)
	end)

	t.test("sanitize pen: more items than toyBoxMax + placedMax are all kept, and logged", function()
		local cap = Config.Economy.Pen.toyBoxMax + Config.Economy.Pen.placedMax
		local items = {}
		for id = 1, cap + 3 do
			table.insert(items, penItem(id, if id % 2 == 0 then "toast" else "kitty_bread"))
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
				penItem(1, "kitty_bread", 2, 70, 7),
				penItem(4, "toast", 1, 12, 3),
				penItem(8, "banana"),
			},
		}
		local result = load(HttpService:JSONDecode(HttpService:JSONEncode(profile)))
		expect.equal(result.status, "ok")
		expect.deepEqual(result.problems, {})
		expect.deepEqual(result.profile.pen, profile.pen)
	end)
end
