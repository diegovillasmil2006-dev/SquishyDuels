--!strict
-- ProfileSchema_Test: defaults, the v1 -> v2 migration against a real v1 FIXTURE, reconcile and sanitize
-- (DESIGN §3.2, §3.3, §17.9 #6, §17.10, §17.12 Part 5). Server Logic/ProfileSchema, pure; `now` is injected.
-- Server only (ServerStorage.UnitTest). Tables are compared by value (deepEqual), never by identity.
-- Contract:
--   * a v1 fixture becomes v2: 10 Grip per old squeeze from the FROZEN constant, rested and afk start full and are
--     stamped with lastSeenAt, missing fields filled with defaults, everything else deep-equal, start version 1;
--   * v2 is a no-op (no second head start);
--   * bad Grip values (total, trainer, rested, afk) are sanitized;
--   * v3 (newer than CURRENT) is not migrated: READONLY view;
--   * the §3.3 sanitize rules (coins, starter ownership, equipped, logs, settings, quests);
--   * samePair (§6.7) joined schema 2 without a new version: defaults {}, an older v2 profile gets it from reconcile,
--     and sanitize fails closed (bad keys / values dropped, non-finite times dropped, far-future times -> now,
--     sorted, both caps).

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
		return expected
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
		expect.deepEqual(d.grip, {
			total = 0,
			trainer = 1,
			rested = { value = Config.Grip.Rested.burst, at = NOW },
			afk = { value = Config.Grip.Afk.burst, at = NOW },
		})
		expect.deepEqual(d.samePair, {})
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
		expect.deepEqual(result.problems, {})
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

	t.test("bad Grip values are sanitized (total, trainer, rested, afk)", function()
		local function gripAfter(grip: any): (any, { string })
			local profile = load(FIXTURE_V1).profile
			profile.grip = grip
			local fixed, problems = ProfileSchema.sanitize(profile, { now = NOW })
			return fixed.grip, problems
		end
		local function timer(value: any, at: any): any
			return { value = value, at = at }
		end
		local grip, problems = gripAfter({
			total = 0 / 0,
			trainer = 0,
			rested = timer(5000, 0 / 0),
			afk = timer(-1, NOW + 301),
		})
		expect.deepEqual(grip, { total = 0, trainer = 1, rested = timer(1200, NOW), afk = timer(0, NOW) })
		local mentionsNonFinite = false
		for _, problem in problems do
			if string.find(problem, "non-finite", 1, true) then
				mentionsNonFinite = true
			end
		end
		expect.truthy(mentionsNonFinite) -- a non-finite total is logged

		grip = gripAfter({ total = 1.5e9, trainer = 99, rested = timer(-5, NOW + 300), afk = timer(500, 1) })
		expect.deepEqual(grip, { total = 1e9, trainer = 8, rested = timer(0, NOW + 300), afk = timer(120, 1) })

		grip = gripAfter({
			total = 12.7,
			trainer = 2.6,
			rested = timer(0 / 0, math.huge),
			afk = timer(math.huge, -math.huge),
		})
		expect.deepEqual(grip, { total = 12, trainer = 2, rested = timer(0, NOW), afk = timer(0, NOW) })

		grip = gripAfter({ total = -5, trainer = "x", rested = "garbage", afk = timer(60, NOW - 10) })
		expect.deepEqual(grip, { total = 0, trainer = 1, rested = timer(0, NOW), afk = timer(60, NOW - 10) })

		grip = gripAfter("garbage")
		expect.deepEqual(grip, { total = 0, trainer = 1, rested = timer(1200, NOW), afk = timer(120, NOW) })

		grip, problems = gripAfter({ total = 50_000, trainer = 3, rested = timer(600.5, NOW), afk = timer(42, NOW) })
		expect.deepEqual(grip, { total = 50_000, trainer = 3, rested = timer(600.5, NOW), afk = timer(42, NOW) })
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
			{ 2e9, Config.Economy.maxCoins },
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
end
