--!strict
-- ProfileSize_Test: the §3.5 size budget, measured with HttpService:JSONEncode (the encoder Roblox uses for DataStore
-- values) on a MAXIMAL profile: every log at its cap (50 boxLog, 20 shopLog, 100 receipts, 30 duelLog), a full
-- same-pair record (Config.Data.caps.samePair opponents x samePairFullRewards times, §6.7), every catalog
-- squishy owned (14 since the 2026-10-09 overhaul), 3 quests, 4 weekly quests (2026-10-17), every starter task and
-- onboarding step, the v2 Grip block,
-- an old save's 4 capsules at the top level (unknown since pens3 phase 2), a full pen (pens3 phase 1: toyBoxMax +
-- placedMax = 71 items, each Rainbow Galaxy at the top level with an id near 2^53), and long worst-case values
-- (36-character GUIDs, 10-digit user and product ids, counters at 2^53, fractional timers). Pass: below
-- Config.Data.profileSizeLimitBytes (100 KB). The measured size is printed for docs/PROGRESS.md. Also checks that the
-- maximal profile is a valid profile (sanitize changes nothing) and that the lock metadata stays under 120 characters
-- (§3.7; the limit is 300). Server only (ServerStorage.UnitTest); JSONEncode works in Edit mode.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
	requireShared: (path: string) -> any,
}

local HttpService = game:GetService("HttpService")

local NOW = 1_800_000_000
local BIG_COUNTER = 2 ^ 53
local DATASTORE_LIMIT = 4_194_304 -- characters per key (Roblox)
local METADATA_TARGET = 120 -- §3.7

return function(t: Context)
	local expect = t.expect
	local ProfileSchema = t.requireServer("Logic/ProfileSchema")
	local SessionLock = t.requireServer("Logic/SessionLock")
	local TableUtil = t.requireShared("Util/TableUtil")
	local Config = t.requireShared("Config")
	local Catalog = t.requireShared("Catalog")

	-- A 36-character upper-case GUID like HttpService:GenerateGUID(false), deterministic per index.
	local function guid(i: number): string
		return string.format("%08X-%04X-4%03X-8%03X-%012X", 0xA0000000 + i, i % 0x10000, i % 0x1000, i % 0x1000, i)
	end

	local function maximalProfile(): any
		local p = ProfileSchema.defaults(NOW)
		local caps = Config.Data.caps
		p.createdAt = NOW - 86400 * 365
		p.lastSeenAt = NOW
		p.saveSeq = BIG_COUNTER
		p.coins = Config.Economy.maxCoins
		local ids = {}
		for _, def in Catalog.list() do
			table.insert(ids, def.id)
			p.owned[def.id] = { at = NOW, src = if def.id == Catalog.starterId() then "starter" else "shop" }
		end
		expect.equal(#ids, #Catalog.list())
		p.equipped = "dragon"
		for key in p.stats do
			p.stats[key] = BIG_COUNTER
		end
		p.squeezeLimit = { value = 123.45678901234567, at = NOW - 0.123456789 }
		p.quests = { day = 20833, swapsUsed = 1, active = {} }
		for i = 1, 3 do
			table.insert(p.quests.active, {
				id = `q20833_{i}`,
				def = "squeeze_with_squishy_xx", -- 23 characters (templates are <= 24)
				squishy = "chocolate",
				progress = BIG_COUNTER,
				goal = BIG_COUNTER,
				reward = 450,
				done = true,
				claimed = false,
			})
		end
		-- Weekly quests (2026-10-17): every weekly quest of a week.
		p.weekly = { week = BIG_COUNTER, active = {} }
		for i = 1, 4 do
			table.insert(p.weekly.active, {
				id = `w9007199254740992_{i}`, -- the week at 2^53
				def = "weekly_duel_finish_xxxxx", -- 24 characters (weekly ids are <= 24)
				progress = BIG_COUNTER,
				goal = BIG_COUNTER,
				reward = 2000,
				done = true,
				claimed = false,
			})
		end
		-- starter_jelly: build plan Phase 6 removed the task, but an old save keeps its entries.
		for _, starterId in { "starter_squeeze", "starter_practice", "starter_duel", "starter_jelly" } do
			p.starter.progress[starterId] = BIG_COUNTER
			p.starter.claimed[starterId] = true
		end
		p.daily = { lastClaimDay = 20833, streakDay = 7, totalClaims = BIG_COUNTER }
		p.settings = { music = 100, sfx = 100, cameraShake = false, showTips = false }
		for _, step in Config.Onboarding.Steps do
			p.onboarding.done[step.id] = true
		end
		p.onboarding.skipped = false
		for i = 1, caps.boxLog do
			table.insert(p.boxLog, {
				req = guid(i),
				box = "sweet",
				squishy = "chocolate",
				dup = true,
				refund = 1000,
				cost = 1500,
				at = NOW + i,
				seen = false,
			})
		end
		for i = 1, caps.shopLog do
			table.insert(p.shopLog, { req = guid(1000 + i), squishy = "chocolate", price = 25000, at = NOW + i })
		end
		for i = 1, caps.receipts do
			table.insert(p.receipts, { id = guid(2000 + i), product = 9_876_543_210, coins = 18000, at = NOW + i })
		end
		for i = 1, caps.duelLog do
			table.insert(
				p.duelLog,
				{ matchId = guid(3000 + i), opp = 9_999_999_999, result = "draw", at = NOW + i, full = false }
			)
		end
		p.grip = {
			total = Config.Grip.maxGrip,
			-- Phase 6: an old save keeps its best trainer (an unknown field now): the worst case has it.
			trainer = 8,
			rested = { value = 1199.987654321, at = NOW - 0.987654321 },
			-- Phase 6: slow training is gone, but an old save keeps its bank (an unknown field): the worst case has it.
			afk = { value = 119.987654321, at = NOW - 0.987654321 },
		}
		-- 10-digit opponent ids, each with the most times a list keeps (ascending, inside the window).
		local perOpponent = Config.Economy.DuelRewards.samePairFullRewards
		for i = 1, caps.samePair do
			local times = {}
			for j = perOpponent, 1, -1 do
				table.insert(times, NOW - j * 500 - i)
			end
			p.samePair[string.format("%d", 9_999_999_000 + i)] = times
		end
		-- Pens3 phase 2: an old save keeps its capsules (an unknown field now): the worst case has 4 slots at Lv 100.
		p.capsules = { slots = 4, list = {} }
		for _, id in { "dragon", "bird", "donut", "cloud_bunny" } do
			table.insert(p.capsules.list, { level = 100, squishyId = id })
		end
		-- Pens3 phase 1: the fullest pen (every Toy Box and placed spot), every squishy at its top, the longest ids.
		local pen = Config.Economy.Pen
		local count = pen.toyBoxMax + pen.placedMax
		p.pen = { spots = pen.maxSpots, nextId = BIG_COUNTER, items = {} }
		local defs = Catalog.list()
		for i = 1, count do
			table.insert(p.pen.items, {
				id = BIG_COUNTER - count - 1 + i,
				kind = defs[(i - 1) % #defs + 1].id,
				form = #pen.formMult - 1,
				level = pen.maxLevel,
				coat = #pen.coatMult - 1,
			})
		end
		return p
	end

	t.test("a maximal profile is valid as built (sanitize changes nothing)", function()
		local p = maximalProfile()
		local copy = TableUtil.deepCopy(p)
		local _, problems = ProfileSchema.sanitize(copy, { now = NOW })
		expect.deepEqual(problems, {})
		expect.deepEqual(copy, p)
	end)

	t.test("a maximal profile encodes with HttpService:JSONEncode below 100 KB", function()
		local p = maximalProfile()
		local json = HttpService:JSONEncode(p)
		local size = #json
		print(
			string.format(
				"[ProfileSize] maximal profile (schema %d): %d characters with HttpService:JSONEncode (%.2f%% of %d; budget %d)",
				ProfileSchema.CURRENT,
				size,
				size / DATASTORE_LIMIT * 100,
				DATASTORE_LIMIT,
				Config.Data.profileSizeLimitBytes
			)
		)
		expect.truthy(size > 0)
		expect.truthy(size < Config.Data.profileSizeLimitBytes)
		expect.truthy(Config.Data.profileSizeLimitBytes <= 100_000)
		-- the encoding round-trips (nothing the encoder cannot represent)
		local decoded = HttpService:JSONDecode(json)
		expect.equal(decoded.coins, p.coins)
		expect.equal(#decoded.receipts, Config.Data.caps.receipts)
		expect.equal(decoded.grip.total, p.grip.total)
		expect.deepEqual(decoded.capsules, p.capsules)
		expect.deepEqual(decoded.pen, p.pen) -- pens3 phase 1: 71 items, ids near 2^53, exact
		local opponents = 0
		for key, times in decoded.samePair do
			opponents += 1
			expect.deepEqual(times, p.samePair[key]) -- string keys survive JSON
		end
		expect.equal(opponents, Config.Data.caps.samePair)
	end)

	t.test("the session lock metadata stays under 120 characters (limit 300)", function()
		local owner = SessionLock.owner(guid(1), SessionLock.nonceFrom(guid(2)))
		local metadata = { lock = SessionLock.newLock(owner, NOW) }
		local size = #HttpService:JSONEncode(metadata)
		expect.truthy(size < METADATA_TARGET)
	end)
end
