--!strict
-- ProfileSchema (server only, pure). The one profile schema: defaults, migrations, reconcile and sanitize
-- (DESIGN §3.2, §3.3, §17.9 #6, §17.10). No yields, no instances, no services: time comes in as `now` (unix seconds,
-- os.time), and nothing here reads or writes a DataStore.
--
-- Versions: 1 = ProfileV1 as first shipped (§3.2); 2 = + `grip = {total, trainer, rested, afk}` (§17.10). The type
-- keeps the name ProfileV1 (Types). CURRENT = 2.
-- Reading: a field whose default needs nothing from the stored data is added WITHOUT a new version: reconcile fills it
-- (§3.3 step 2), and a server without it keeps it as an unknown field, so no rolling-deploy READONLY (§17.10). A
-- version (and a frozen MIGRATIONS step) is only for a transform of stored data, like v1 -> v2's head start. That is
-- how `samePair = {}` (the same-pair record, §6.7) joined schema 2, and `capsules` (progression spec 2026-10-12 §14:
-- nobody but the two owners has played yet, so there are no old saves to fix). The same way back: build plan Phase 6
-- removed slow training and the trainers, so `grip.afk` (the bank) and `grip.trainer` left defaults and sanitize with
-- no new version (and no refund); an old save keeps them as unknown fields nothing reads, and the frozen v1 -> v2 step
-- still writes them. Match HUD M2 (2026-10-16): `stats.winStreak` (the Free for All / Team Deathmatch win streak,
-- default 0, a counter like the other stats) joined schema 2 the same way: no new version, so a server without it keeps
-- it as an unknown stat (a version would make a player who saved on a new server READONLY on an old one during a
-- rolling update); reconcile fills it, sanitize clamps it with the other counters. Auto-clicker check (2026-10-16):
-- `autoClick = {step = 0, at = 0}` (the last auto-clicker strike: step 1 warned, 2 kicked, 3 and up banned (each later
-- ban longer, batch B 2026-10-17), and its os.time; AutoClickService reads it so a rejoin within
-- Config.Net.AutoClick.memorySeconds keeps a warning or a kick, and a ban is never forgotten) joined schema 2 the
-- same way; sanitize: step a whole number in [0, AutoClickRules.MAX_STEP], at a whole number in [0, now + 300], and
-- a non-finite one 0 (forgotten: a broken record never punishes anyone). Weekly quests (2026-10-17):
-- `weekly = {week = -1, active = {}}` (the week index and its quests, QuestService) joined schema 2 the same way;
-- sanitize: week a whole number in [-1, 2^53] (else -1: the next check makes this week's), the entries like the
-- daily quests' (claims fail closed; a quest whose definition is gone dropped when opts.questExists is given).
--
-- Load pipeline (§3.3), all on a deep copy; the result is written on the next save:
--   1. migrate(d)   -> (copy, fromVersion) or (nil, version, "newer") when the stored schemaVersion is above CURRENT
--                      (the session becomes READONLY), or (nil, 0, "corrupt") when the stored value is not a table.
--                      Applies MIGRATIONS[n] until CURRENT. MIGRATIONS[1] (v1 -> v2) is frozen: it never reads Config,
--                      so later re-tunes can't change what it produces (10 Grip per old squeeze, Double Grip and the
--                      slow-training bank start full, stamped at lastSeenAt).
--   2. reconcile(d, now) -> fills missing fields from defaults(now), deep; unknown fields are kept.
--   3. sanitize(d, opts) -> (d, problems): fixes values in place and lists every fix (DataService logs them):
--        coins integer clamped to [0, Economy.maxCoins] (non-finite -> 0); the starter always owned; owned ids missing
--        from the Catalog are kept (and ignored by their readers); equipped not owned or not in the Catalog -> the
--        starter; quests whose template no longer exists dropped (only when opts.questExists is given: QuestDefs lands
--        in Part 7); logs trimmed to Config.Data.caps (newest kept); settings clamped; Grip (§17.9 #6): total floored
--        and clamped to [0, Grip.maxGrip] (non-finite -> 0), rested.value in
--        [0, Rested.burst], a non-finite `at` or one later than now + 300 -> now;
--        samePair (§6.7, fails closed): not a table -> {}; a key that is not a whole-number userId string
--        (DuelRewards.samePairKey) or a value that is not a table is dropped; in a list only finite numbers stay (a
--        non-array table is rebuilt from them); a time later than now + 300 becomes now (reading: clamped, not
--        dropped, so it still counts for at most one window instead of never expiring); an empty list is dropped;
--        then sorted ascending with both caps (samePairFullRewards times per opponent, Data.caps.samePair opponents;
--        DuelRewards.capSamePair); capsules (spec 2026-10-12 §6-§7, fails closed): slots a whole number in
--        [1, #Capsule.slotPrices], one {level, squishyId} per unlocked slot (a missing one -> an empty Lv 1 capsule,
--        extra entries dropped), level a whole number in [1, Capsule.maxLevel], a squishy that is not owned, not in
--        the Catalog or already in an earlier capsule (one capsule each) taken out (the capsule stays, empty).
-- load(raw, opts) runs the whole pipeline and also returns the start version (DataService keeps it as migratedFrom,
-- GripService shows grip.headStart once, §17.10).
--
-- Readings (sanitize; wrong TYPES can only come from a bug or a hand edit, reconcile never replaces a present value):
--   * a field of the wrong type is replaced by its default; a malformed owned entry stays owned as {at = now,
--     src = "grant"}; a non-finite rate-limit value (squeezeLimit, grip.rested) becomes 0, which time
--     refills (fail closed);
--   * idempotency flags fail closed: a quest's or starter task's `claimed` that is not a boolean counts as claimed;
--     a non-finite daily.lastClaimDay becomes today (no second claim today);
--   * counters (stats, quest numbers, daily) are integers clamped to [0, 2^53]; the squeeze limit value is clamped to
--     [0, Economy.SqueezeLimit.burst] with the same `at` rule as Grip's timers;
--   * a stored schemaVersion that is missing, non-finite or below 1 counts as 1; a fractional one is floored.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)
local AutoClickRules = require(script.Parent.AutoClickRules)
local DuelRewards = require(script.Parent.DuelRewards)

-- Types

export type GripTimer = Types.GripTimerState
export type GripState = Types.GripState
-- The live profile: ProfileV1 (Types; the name stays across schema versions) with the v2 Grip block.
export type Profile = Types.ProfileV1
export type MigrateError = "newer" | "corrupt"
export type LoadStatus = "ok" | "newer" | "corrupt"

-- The parts of Catalog that sanitize reads (tests may pass their own).
export type CatalogLike = {
	isValidId: (v: unknown) -> boolean,
	starterId: () -> string,
}

export type SanitizeOptions = {
	now: number?, -- unix seconds; default os.time()
	catalog: CatalogLike?, -- default Shared.Catalog
	questExists: ((defId: string) -> boolean)?, -- nil = keep every quest (QuestDefs lands in Part 7)
}

export type LoadResult = {
	profile: Profile,
	fromVersion: number, -- the stored version before migration (CURRENT for a fresh profile)
	status: LoadStatus, -- "ok"; "newer" = READONLY view of a newer profile; "corrupt" = defaults shown, never saved
	migrated: boolean, -- fromVersion < CURRENT
	problems: { string }, -- every sanitize fix
}

-- Constants

local CURRENT = 2
local FUTURE_SLACK_SECONDS = Config.Data.timestampSkewSeconds -- §17.9 #6: a timer stamped after now + 300 -> now
local CAPSULE = Config.Grip.Capsule
local MAX_COUNTER = 2 ^ 53
local SECONDS_PER_DAY = 86400
local DAILY_PATH = "daily."
local OWNED_SOURCES = { starter = true, box = true, shop = true, grant = true }
local STAT_KEYS = {
	"coinsEarned",
	"coinsSpent",
	"squeezes",
	"duelsPlayed",
	"duelsWon",
	"duelsLost",
	"duelsDrawn",
	"eliminations",
	"boxesOpened",
	"winStreak", -- Match HUD M2 (2026-10-16): no new version (see the header)
}
local LOG_KEYS = { "boxLog", "shopLog", "receipts", "duelLog" }
local VOLUME_KEYS = { "music", "sfx" }
local SWITCH_KEYS = { "cameraShake", "showTips" }

-- Frozen for v1 -> v2 (§17.10). Never read Config here, so later re-tunes can't change what this migration produces.
local HEAD_START_PER_SQUEEZE = 10
local RESTED_START = 1200
local AFK_START = 120
local MAX_GRIP = 1_000_000_000

-- MIGRATIONS[n] turns version n into n + 1. Pure; runs on a deep copy; ships with a fixture test (§3.3).
local MIGRATIONS: { [number]: (d: any) -> any } = {}

MIGRATIONS[1] = function(d: any): any -- v1 -> v2 (§17.10)
	local sq = (type(d.stats) == "table" and tonumber(d.stats.squeezes)) or 0
	if sq ~= sq or sq == math.huge or sq < 0 then
		sq = 0
	end
	local seen = tonumber(d.lastSeenAt) or 0
	d.grip = {
		total = math.clamp(math.floor(sq) * HEAD_START_PER_SQUEEZE, 0, MAX_GRIP),
		trainer = 1,
		rested = { value = RESTED_START, at = seen },
		afk = { value = AFK_START, at = seen },
	}
	d.schemaVersion = 2
	return d
end

-- Module table

local ProfileSchema = {}

ProfileSchema.CURRENT = CURRENT
-- The frozen v1 -> v2 constants, for tests and logs.
ProfileSchema.V1_TO_V2 = table.freeze({
	headStartPerSqueeze = HEAD_START_PER_SQUEEZE,
	restedStart = RESTED_START,
	afkStart = AFK_START,
	maxGrip = MAX_GRIP,
})

-- Private

local function isFinite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function show(v: unknown): string
	if type(v) == "string" then
		return string.format("%q", string.sub(v, 1, 40))
	end
	return tostring(v)
end

local function note(problems: { string }, path: string, from: unknown, to: unknown)
	table.insert(problems, `{path}: {show(from)} -> {show(to)}`)
end

-- t[field] becomes a table; a value of another type is replaced by `fallback()` and noted.
local function ensureTable(t: any, field: string, fallback: () -> any, path: string, problems: { string }): any
	local value = t[field]
	if type(value) ~= "table" then
		local fresh = fallback()
		t[field] = fresh
		note(problems, path, if value == nil then nil else type(value), "default")
		return fresh
	end
	return value
end

-- t[field] becomes an integer in [lo, hi] (floored, clamped); a non-finite value becomes `fallback`.
local function fixInt(
	t: any,
	field: string,
	lo: number,
	hi: number,
	fallback: number,
	path: string,
	problems: { string }
)
	local value = t[field]
	if not isFinite(value) then
		t[field] = fallback
		note(problems, path, value, fallback)
		return
	end
	local fixed = math.clamp(math.floor(value :: number), lo, hi)
	if fixed ~= value then
		t[field] = fixed
		note(problems, path, value, fixed)
	end
end

-- t[field] becomes a boolean; any other value becomes `fallback`.
local function fixBoolean(t: any, field: string, fallback: boolean, path: string, problems: { string })
	local value = t[field]
	if type(value) ~= "boolean" then
		t[field] = fallback
		note(problems, path, value, fallback)
	end
end

-- A rate-limit timer {value, at}: value clamped to [0, maxValue] (non-finite -> 0), `at` non-finite or later than
-- now + 300 -> now.
local function fixTimer(t: any, field: string, maxValue: number, now: number, path: string, problems: { string })
	local timer = ensureTable(t, field, function()
		return { value = 0, at = now }
	end, path, problems)
	local value = timer.value
	if not isFinite(value) then
		timer.value = 0
		note(problems, path .. ".value", value, 0)
	elseif value < 0 or value > maxValue then
		local fixed = math.clamp(value, 0, maxValue)
		timer.value = fixed
		note(problems, path .. ".value", value, fixed)
	end
	local at = timer.at
	if not isFinite(at) or (at :: number) > now + FUTURE_SLACK_SECONDS then
		timer.at = now
		note(problems, path .. ".at", at, now)
	end
end

-- A string-keyed map of booleans; non-string keys are dropped; non-boolean values become `fallback`.
local function fixFlagMap(map: any, fallback: boolean, path: string, problems: { string })
	for key, value in table.clone(map) do
		if type(key) ~= "string" then
			map[key] = nil
			note(problems, path, key, "removed")
		elseif type(value) ~= "boolean" then
			map[key] = fallback
			note(problems, `{path}.{key}`, value, fallback)
		end
	end
end

-- Rebuilds t[field] as an array of the table entries, keeping only the newest `cap` (the tail).
local function fixLog(t: any, field: string, cap: number, path: string, problems: { string })
	local list = ensureTable(t, field, function()
		return {}
	end, path, problems)
	local entries = {}
	for _, entry in ipairs(list) do
		if type(entry) == "table" then
			table.insert(entries, entry)
		end
	end
	local count = 0
	for _ in list do
		count += 1
	end
	if count ~= #entries or #entries > cap then
		local first = math.max(1, #entries - cap + 1)
		local trimmed = table.move(entries, first, #entries, 1, {})
		t[field] = trimmed
		note(problems, path, count, #trimmed)
	end
end

local function fixQuestEntry(q: any, path: string, problems: { string })
	fixInt(q, "progress", 0, MAX_COUNTER, 0, path .. ".progress", problems)
	fixInt(q, "goal", 0, MAX_COUNTER, 0, path .. ".goal", problems)
	fixInt(q, "reward", 0, MAX_COUNTER, 0, path .. ".reward", problems)
	fixBoolean(q, "done", false, path .. ".done", problems)
	fixBoolean(q, "claimed", true, path .. ".claimed", problems) -- fail closed: never pay twice
	if q.squishy ~= nil and type(q.squishy) ~= "string" then
		note(problems, path .. ".squishy", q.squishy, nil)
		q.squishy = nil
	end
end

-- `container.active` (the daily quests, or the weekly ones): not a table -> {}; an entry without a string id and def,
-- or (with questExists) whose definition is gone, is dropped; the others are fixed by fixQuestEntry.
local function fixQuestList(container: any, path: string, questExists: ((string) -> boolean)?, problems: { string })
	local active = ensureTable(container, "active", function()
		return {}
	end, path .. ".active", problems)
	local kept = {}
	for index, q in ipairs(active) do
		local entryPath = `{path}.active[{index}]`
		if type(q) ~= "table" or type(q.id) ~= "string" or type(q.def) ~= "string" then
			note(problems, entryPath, if type(q) == "table" then q.id else q, "removed")
		elseif questExists ~= nil and not questExists(q.def) then
			note(problems, entryPath, q.def, "template gone")
		else
			fixQuestEntry(q, entryPath, problems)
			table.insert(kept, q)
		end
	end
	if #kept ~= #active then
		container.active = kept
	end
end

-- True for a key DuelRewards.samePairKey makes: a whole-number userId written exactly that way ("301", "-1").
local function isSamePairKey(key: unknown): boolean
	if type(key) ~= "string" then
		return false
	end
	local id = tonumber(key)
	return id ~= nil and isFinite(id) and math.floor(id) == id and DuelRewards.samePairKey(id) == key
end

-- The same-pair record (see the header): fixed in place, every fix noted.
local function fixSamePair(d: any, now: number, problems: { string })
	local samePair = ensureTable(d, "samePair", function()
		return {}
	end, "samePair", problems)
	for key, times in table.clone(samePair) :: { [any]: any } do
		if not isSamePairKey(key) then
			samePair[key] = nil
			note(problems, "samePair", key, "removed")
		elseif type(times) ~= "table" then
			samePair[key] = nil
			note(problems, `samePair.{key}`, times, "removed")
		else
			local kept: { number } = {}
			local count = 0
			local changed = false
			for _, at in times do
				count += 1
				if not isFinite(at) then
					changed = true
				elseif at > now + FUTURE_SLACK_SECONDS then
					table.insert(kept, now)
					changed = true
				else
					if #kept > 0 and at < kept[#kept] then
						changed = true -- out of order
					end
					table.insert(kept, at)
				end
			end
			if #kept == 0 then
				samePair[key] = nil
				note(problems, `samePair.{key}`, count, "removed")
			elseif changed or count ~= #times then
				table.sort(kept)
				samePair[key] = kept
				note(problems, `samePair.{key}`, count, #kept)
			end
		end
	end
	local removed = DuelRewards.capSamePair(samePair)
	if removed > 0 then
		note(problems, "samePair (caps)", removed, "removed")
	end
end

-- The capsules (see the header): fixed in place, every fix noted. Runs after `owned` is fixed.
local function fixCapsules(d: any, catalog: CatalogLike, problems: { string })
	local capsules = ensureTable(d, "capsules", function()
		return { slots = 1, list = { { level = 1, squishyId = catalog.starterId() } } }
	end, "capsules", problems)
	fixInt(capsules, "slots", 1, #CAPSULE.slotPrices, 1, "capsules.slots", problems)
	local list = ensureTable(capsules, "list", function()
		return {}
	end, "capsules.list", problems)
	local kept: { any } = {}
	local inUse: { [string]: boolean } = {}
	for index = 1, capsules.slots do
		local path = `capsules.list[{index}]`
		local capsule = list[index]
		if type(capsule) ~= "table" then
			note(problems, path, capsule, "empty Lv 1")
			capsule = { level = 1 }
		end
		fixInt(capsule, "level", 1, CAPSULE.maxLevel, 1, path .. ".level", problems)
		local id = capsule.squishyId
		if id ~= nil then
			if type(id) ~= "string" or d.owned[id] == nil or not catalog.isValidId(id) or inUse[id] then
				note(problems, path .. ".squishyId", id, nil)
				capsule.squishyId = nil
			else
				inUse[id] = true
			end
		end
		kept[index] = capsule
	end
	local count = 0
	for _ in list do
		count += 1
	end
	local present = 0
	for index = 1, capsules.slots do
		if list[index] ~= nil then
			present += 1
		end
	end
	if count ~= present then
		note(problems, "capsules.list", count, #kept)
	end
	capsules.list = kept
end

local function versionOf(d: any): number
	local v = tonumber(d.schemaVersion)
	if v == nil or v ~= v or v < 1 then
		return 1
	end
	return math.floor(v)
end

-- Public

-- True when `value` is a stored profile from a newer schema than this server knows (READONLY, §3.3).
function ProfileSchema.isNewer(value: unknown): boolean
	return type(value) == "table" and (tonumber((value :: any).schemaVersion) or 0) > CURRENT
end

-- A brand-new profile at `now` (unix seconds), schema CURRENT (§3.2, §17.10).
function ProfileSchema.defaults(now: number): Profile
	local starter = Catalog.starterId()
	local stats = {}
	for _, key in STAT_KEYS do
		stats[key] = 0
	end
	local profile: any = {
		schemaVersion = CURRENT,
		createdAt = now,
		lastSeenAt = now,
		saveSeq = 0,
		coins = Config.Economy.startingCoins,
		owned = { [starter] = { at = now, src = "starter" } },
		equipped = starter,
		stats = stats,
		squeezeLimit = { value = Config.Economy.SqueezeLimit.burst, at = now },
		quests = { day = -1, swapsUsed = 0, active = {} },
		starter = { progress = {}, claimed = {} },
		daily = { lastClaimDay = -1, streakDay = 0, totalClaims = 0 },
		settings = TableUtil.deepCopy(Config.Data.DefaultSettings),
		onboarding = { v = Config.Onboarding.version, done = {}, skipped = false },
		boxLog = {},
		shopLog = {},
		receipts = {},
		duelLog = {},
		grip = {
			total = 0,
			rested = { value = Config.Grip.Rested.burst, at = now },
		},
		samePair = {},
		-- Spec 2026-10-12 §7: one capsule free, Kitty Bread at Lv 1.
		capsules = { slots = 1, list = { { level = 1, squishyId = starter } } },
		autoClick = { step = 0, at = 0 }, -- auto-clicker check (2026-10-16): no strike
		weekly = { week = -1, active = {} }, -- weekly quests (2026-10-17): none until the first check
	}
	return profile
end

-- Step 1: returns (a migrated deep copy, the start version), or (nil, version, "newer") / (nil, 0, "corrupt").
-- `d` itself is never changed.
function ProfileSchema.migrate(d: unknown): (any, number, MigrateError?)
	if type(d) ~= "table" then
		return nil, 0, "corrupt"
	end
	if ProfileSchema.isNewer(d) then
		return nil, tonumber((d :: any).schemaVersion) or 0, "newer"
	end
	local from = versionOf(d)
	local copy = TableUtil.deepCopy(d) :: any
	local version = from
	while version < CURRENT do
		local step = MIGRATIONS[version]
		assert(step ~= nil, `[SD][ProfileSchema] no migration from version {version}`)
		copy = step(copy)
		version += 1
	end
	copy.schemaVersion = CURRENT
	return copy, from, nil
end

-- Step 2: fills missing fields of `d` from defaults(now), deep (in place; returns d). Unknown fields are kept.
function ProfileSchema.reconcile(d: any, now: number): any
	return TableUtil.reconcile(d, ProfileSchema.defaults(now) :: any)
end

-- Step 3: fixes `d` in place (see the header) and returns (d, problems).
function ProfileSchema.sanitize(d: any, opts: SanitizeOptions?): (Profile, { string })
	local options: SanitizeOptions = opts or {}
	local now = if options.now ~= nil then options.now else os.time()
	local catalog: CatalogLike = options.catalog or Catalog
	local questExists = options.questExists
	local problems: { string } = {}
	local fresh = ProfileSchema.defaults(now) :: any

	if type(d.schemaVersion) ~= "number" then
		note(problems, "schemaVersion", d.schemaVersion, CURRENT)
		d.schemaVersion = CURRENT
	end
	fixInt(d, "createdAt", -MAX_COUNTER, MAX_COUNTER, now, "createdAt", problems)
	fixInt(d, "lastSeenAt", -MAX_COUNTER, MAX_COUNTER, now, "lastSeenAt", problems)
	fixInt(d, "saveSeq", 0, MAX_COUNTER, 0, "saveSeq", problems)
	fixInt(d, "coins", 0, Config.Economy.maxCoins, 0, "coins", problems)

	-- Ownership: never lose an item; the starter is always owned.
	local starter = catalog.starterId()
	local owned = ensureTable(d, "owned", function()
		return {}
	end, "owned", problems)
	for id, entry in table.clone(owned) :: { [any]: any } do
		if type(id) ~= "string" then
			owned[id] = nil
			note(problems, "owned", id, "removed")
		elseif type(entry) ~= "table" then
			owned[id] = { at = now, src = "grant" }
			note(problems, `owned.{id}`, entry, "grant")
		else
			if not isFinite(entry.at) then
				note(problems, `owned.{id}.at`, entry.at, now)
				entry.at = now
			end
			if type(entry.src) ~= "string" or not OWNED_SOURCES[entry.src] then
				note(problems, `owned.{id}.src`, entry.src, "grant")
				entry.src = "grant"
			end
		end
	end
	if owned[starter] == nil then
		owned[starter] = { at = now, src = "starter" }
		note(problems, `owned.{starter}`, nil, "starter")
	end
	local equipped = d.equipped
	if type(equipped) ~= "string" or owned[equipped] == nil or not catalog.isValidId(equipped) then
		d.equipped = starter
		note(problems, "equipped", equipped, starter)
	end

	local stats = ensureTable(d, "stats", function()
		return TableUtil.deepCopy(fresh.stats)
	end, "stats", problems)
	for _, key in STAT_KEYS do
		fixInt(stats, key, 0, MAX_COUNTER, 0, `stats.{key}`, problems)
	end

	fixTimer(d, "squeezeLimit", Config.Economy.SqueezeLimit.burst, now, "squeezeLimit", problems)

	-- Quests (templates arrive with QuestDefs in Part 7).
	local quests = ensureTable(d, "quests", function()
		return TableUtil.deepCopy(fresh.quests)
	end, "quests", problems)
	fixInt(quests, "day", -1, MAX_COUNTER, -1, "quests.day", problems)
	fixInt(quests, "swapsUsed", 0, MAX_COUNTER, 0, "quests.swapsUsed", problems)
	fixQuestList(quests, "quests", questExists, problems)

	-- Weekly quests (2026-10-17, see the header).
	local weekly = ensureTable(d, "weekly", function()
		return TableUtil.deepCopy(fresh.weekly)
	end, "weekly", problems)
	fixInt(weekly, "week", -1, MAX_COUNTER, -1, "weekly.week", problems)
	fixQuestList(weekly, "weekly", questExists, problems)

	local starterTasks = ensureTable(d, "starter", function()
		return TableUtil.deepCopy(fresh.starter)
	end, "starter", problems)
	local progress = ensureTable(starterTasks, "progress", function()
		return {}
	end, "starter.progress", problems)
	for key in table.clone(progress) do
		if type(key) ~= "string" then
			progress[key] = nil
			note(problems, "starter.progress", key, "removed")
		else
			fixInt(progress, key, 0, MAX_COUNTER, 0, `starter.progress.{key}`, problems)
		end
	end
	local claimed = ensureTable(starterTasks, "claimed", function()
		return {}
	end, "starter.claimed", problems)
	fixFlagMap(claimed, true, "starter.claimed", problems) -- fail closed: never pay twice

	local daily = ensureTable(d, "daily", function()
		return TableUtil.deepCopy(fresh.daily)
	end, "daily", problems)
	-- (the log paths are built as DAILY_PATH .. key so tools/check-reasons.ps1 does not read them as reason codes)
	local today = math.floor(now / SECONDS_PER_DAY)
	fixInt(daily, "lastClaimDay", -1, MAX_COUNTER, today, DAILY_PATH .. "lastClaimDay", problems)
	fixInt(daily, "streakDay", 0, MAX_COUNTER, 0, DAILY_PATH .. "streakDay", problems)
	fixInt(daily, "totalClaims", 0, MAX_COUNTER, 0, DAILY_PATH .. "totalClaims", problems)

	local settings = ensureTable(d, "settings", function()
		return TableUtil.deepCopy(fresh.settings)
	end, "settings", problems)
	for _, key in VOLUME_KEYS do
		local fallback = (Config.Data.DefaultSettings :: any)[key]
		fixInt(settings, key, Config.Data.settingsMin, Config.Data.settingsMax, fallback, `settings.{key}`, problems)
	end
	for _, key in SWITCH_KEYS do
		fixBoolean(settings, key, (Config.Data.DefaultSettings :: any)[key], `settings.{key}`, problems)
	end

	local onboarding = ensureTable(d, "onboarding", function()
		return TableUtil.deepCopy(fresh.onboarding)
	end, "onboarding", problems)
	fixInt(onboarding, "v", 1, MAX_COUNTER, Config.Onboarding.version, "onboarding.v", problems)
	local done = ensureTable(onboarding, "done", function()
		return {}
	end, "onboarding.done", problems)
	fixFlagMap(done, true, "onboarding.done", problems)
	fixBoolean(onboarding, "skipped", false, "onboarding.skipped", problems)

	for _, key in LOG_KEYS do
		fixLog(d, key, (Config.Data.caps :: any)[key], key, problems)
	end

	-- Grip (§17.9 #6).
	local grip = ensureTable(d, "grip", function()
		return TableUtil.deepCopy(fresh.grip)
	end, "grip", problems)
	local total = grip.total
	if not isFinite(total) then
		grip.total = 0
		note(problems, "grip.total (non-finite)", total, 0)
	else
		local fixed = math.clamp(math.floor(total), 0, Config.Grip.maxGrip)
		if fixed ~= total then
			grip.total = fixed
			note(problems, "grip.total", total, fixed)
		end
	end
	fixTimer(grip, "rested", Config.Grip.Rested.burst, now, "grip.rested", problems)

	-- Same-pair record (§6.7, §12 #15).
	fixSamePair(d, now, problems)

	-- Capsules (spec 2026-10-12 §6-§7).
	fixCapsules(d, catalog, problems)

	-- Auto-clicker check (2026-10-16): the last strike (see the header).
	local autoClick = ensureTable(d, "autoClick", function()
		return { step = 0, at = 0 }
	end, "autoClick", problems)
	fixInt(autoClick, "step", 0, AutoClickRules.MAX_STEP, 0, "autoClick.step", problems)
	fixInt(autoClick, "at", 0, now + FUTURE_SLACK_SECONDS, 0, "autoClick.at", problems)

	return d, problems
end

-- The whole pipeline for a stored value (nil = a key never written: defaults). Never changes `raw`.
function ProfileSchema.load(raw: unknown, opts: SanitizeOptions?): LoadResult
	local options: SanitizeOptions = opts or {}
	local now = if options.now ~= nil then options.now else os.time()
	local sanitizeOptions: SanitizeOptions = { now = now, catalog = options.catalog, questExists = options.questExists }
	if raw == nil then
		return {
			profile = ProfileSchema.defaults(now),
			fromVersion = CURRENT,
			status = "ok",
			migrated = false,
			problems = {},
		}
	end
	local migrated, from, err = ProfileSchema.migrate(raw)
	if err == "newer" then
		-- READONLY: the real data is shown as far as this server understands it, and never saved.
		local view = TableUtil.deepCopy(raw) :: any
		ProfileSchema.reconcile(view, now)
		local profile, problems = ProfileSchema.sanitize(view, sanitizeOptions)
		return { profile = profile, fromVersion = from, status = "newer", migrated = false, problems = problems }
	elseif err == "corrupt" then
		return {
			profile = ProfileSchema.defaults(now),
			fromVersion = 0,
			status = "corrupt",
			migrated = false,
			problems = { `stored value is a {typeof(raw)}, not a table` },
		}
	end
	ProfileSchema.reconcile(migrated, now)
	local profile, problems = ProfileSchema.sanitize(migrated, sanitizeOptions)
	return { profile = profile, fromVersion = from, status = "ok", migrated = from < CURRENT, problems = problems }
end

return ProfileSchema
