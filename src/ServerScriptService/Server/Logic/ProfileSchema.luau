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
-- still writes them. Pens3 phase 2 removed `capsules` the same way (an old save keeps it, unread; no refund).
-- Match HUD M2 (2026-10-16): `stats.winStreak` (the Free for All / Team Deathmatch win streak,
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
-- Pens (pens3 phase 1, 2026-10-17): `pen = {spots = 3, nextId = 2, items = {{id = 1, kind = <the starter>, form = 0,
-- level = 1, coat = 0}}}` joined schema 2 the same way. fixPen is an invariant repair, not a migration (it reads only
-- the profile itself), and it never drops a squishy someone owns: spots a whole number in [Pen.startSpots,
-- Pen.maxSpots]; nextId a whole number >= 1; items not a table -> {}, a table that is not a pure list keeps its list
-- part (logged; the owned rule below brings every owned kind back); each entry: not a table, or a kind not in the
-- Catalog, dropped (an owned entry stays owned, as `owned` keeps a removed id); form / level / coat whole numbers
-- clamped to [0, #formMult - 1] / [1, maxLevel] / [0, #coatMult - 1] (non-finite -> 0 / 1 / 0); an id that is not a
-- whole number in [1, 2^53], or one an earlier entry has, gets a fresh id (the item is kept); then nextId =
-- max(nextId, the largest id + 1); a pen item whose kind is not owned makes it owned ({at = now, src = "grant"});
-- every owned Catalog kind without an item gets one plain Lv 1 item (the kind ids in alphabetical order: an older
-- save gets one item per owned kind); more than Pen.toyBoxMax + Pen.placedMax entries are all kept and logged (only a
-- bug gets there: grants stop at the cap from phase 5). Pens3 phase 4: `pen.awayRate` (the pen's Coins a second at the
-- last save, stamped by DataService; what the next load pays the time away from) joined the same way: default 0
-- (reconcile gives an older pen 0, so its first load after phase 4 pays no away Coins); sanitize turns a non-finite,
-- negative or non-number rate into 0 (fails closed: no away Coins). Pens3 phase 5 (copies) joined the same way:
-- `giftQueue = {}` (free squishies waiting for room in the Toy Box, kind ids oldest first; none is owned yet): not a
-- table -> {}, only Catalog kinds kept in order (each drop logged), more than Pen.giftQueueMax all kept and logged
-- (only a bug gets there); `boxOrder = {snack = 0, sweet = 0}` (one count per paid box: the fixed-order opens of a
-- restricted account): each a whole number in [0, 2^53] (non-finite -> 0), other keys kept; `gifts = {frog = false}`
-- (the once-per-account gifts given): fails closed, a non-boolean flag or a gifts value that is not a table counts
-- every gift as given (never twice). Pens3 phase 6 (the pen screen) joined the same way: every pen item has `slot` (0 =
-- the Toy Box, 1..spots the pen) and `locked` (the default Kitty Bread: slot 1, unlocked). fixPen, after the ids and
-- the owned rule: a slot that is a whole number in [1, spots] no earlier item holds is kept; 0 is kept; any other
-- slot (past the open spots, repeated, not a whole number) becomes 0 (the Toy Box: never dropped), logged; then the
-- items with no slot (an older save, or an item the owned rule added) get one, once, in the order the pen used before
-- (PenMath.better: the higher rate, then the lower id), the free spots first, then the Toy Box, each logged (so an old
-- save's best `spots` squishies keep paying); a missing lock is false (not logged, like reconcile), a lock that is not
-- a boolean false (logged). Pens3 phases 7-8 (selling, the buy-back, fusion) joined the same way: `buyBack = {}`
-- (the sales that can still be bought back, oldest first: Types.BuyBackEntry {item, price, at, req}) and `bag = {0 x
-- #coatMult - 1}` (the coatings that came off fused or sold squishies, one count per coating, index = the coat).
-- fixSales fails closed: an entry that is not a sold squishy (a Catalog kind, form / level / coat in range, a whole
-- id), whole Coins in [0, maxCoins], a finite `at` no later than now + 300 and a string req is dropped and logged
-- (its Coins were paid; it is no longer owned, so nothing anyone owns is lost); more than Pen.buyBackMax keeps the
-- newest (logged); an expired entry is kept (PenMath.liveBuyBack leaves it out, the next sale prunes it). The bag: not
-- a table -> zeros; each count a whole number in [0, 2^53] (non-finite or missing -> 0), any other key dropped; logged.
-- Pens3 phase 9 (food and levels) joined the same way: `food = {[foodId] = 0 for every Config.Economy.Food food}`
-- (the pieces owned; reconcile gives an older profile none of each, and a food the Config gains later 0). fixFood
-- fails closed: not a table -> none of each; each count a whole number in [0, Food.maxPieces] (floored: never more
-- than was bought; clamped; non-finite or missing -> 0); a key that is not a Config food is dropped; every fix logged.
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
--        DuelRewards.capSamePair).
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
local Boxes = require(Shared.Boxes)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local PenMath = require(Shared.PenMath)
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
local PEN = Config.Economy.Pen
local FOOD = Config.Economy.Food -- pens3 phase 9
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
local PAID_BOX_IDS: { string } = {} -- pens3 phase 5: the boxOrder keys, in Boxes order
for _, box in Boxes.list() do
	if box.paid then
		table.insert(PAID_BOX_IDS, box.id)
	end
end
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

-- The pen (pens3 phase 1, see the header): fixed in place, every fix noted. Runs after `owned` is fixed.
local function fixPen(d: any, catalog: CatalogLike, now: number, problems: { string })
	local pen = ensureTable(d, "pen", function()
		return { spots = PEN.startSpots, nextId = 1, items = {}, awayRate = 0 }
	end, "pen", problems)
	fixInt(pen, "spots", PEN.startSpots, PEN.maxSpots, PEN.startSpots, "pen.spots", problems)
	fixInt(pen, "nextId", 1, MAX_COUNTER, 1, "pen.nextId", problems)
	local rate = pen.awayRate -- nil only before reconcile (it fills 0)
	if rate ~= nil and not (isFinite(rate) and (rate :: number) >= 0) then
		pen.awayRate = 0
		note(problems, "pen.awayRate", rate, 0)
	end
	local list = ensureTable(pen, "items", function()
		return {}
	end, "pen.items", problems)

	-- The entries: kept in order, fixed field by field; an id is checked once every entry is in.
	local items: { any } = {}
	local count, walked = 0, 0
	for _ in list do
		count += 1
	end
	for index, item in ipairs(list) do
		walked = index
		local path = `pen.items[{index}]`
		if type(item) ~= "table" then
			note(problems, path, item, "removed")
		elseif not catalog.isValidId(item.kind) then
			note(problems, path .. ".kind", item.kind, "removed")
		else
			fixInt(item, "form", 0, #PEN.formMult - 1, 0, path .. ".form", problems)
			fixInt(item, "level", 1, PEN.maxLevel, 1, path .. ".level", problems)
			fixInt(item, "coat", 0, #PEN.coatMult - 1, 0, path .. ".coat", problems)
			table.insert(items, item)
		end
	end
	if count ~= walked then
		note(problems, "pen.items (not a list)", count, walked)
	end

	-- Ids: unique whole numbers; a bad or repeated one gets a fresh id above every good one.
	local taken: { [number]: boolean } = {}
	local renumber: { any } = {}
	local largest = 0
	for _, item in items do
		local id = item.id
		if isFinite(id) and math.floor(id) == id and id >= 1 and id <= MAX_COUNTER and not taken[id] then
			taken[id] = true
			largest = math.max(largest, id)
		else
			table.insert(renumber, item)
		end
	end
	if pen.nextId <= largest then
		note(problems, "pen.nextId", pen.nextId, largest + 1)
		pen.nextId = largest + 1
	end
	for _, item in renumber do
		note(problems, `pen.items (id of {show(item.kind)})`, item.id, pen.nextId)
		item.id = pen.nextId
		pen.nextId += 1
	end

	-- Owned and the pen agree: a pen squishy is owned, an owned squishy is in the pen.
	local hasItem: { [string]: boolean } = {}
	for _, item in items do
		hasItem[item.kind] = true
		if d.owned[item.kind] == nil then
			d.owned[item.kind] = { at = now, src = "grant" }
			note(problems, `owned.{item.kind} (in the pen)`, nil, "grant")
		end
	end
	local missing: { string } = {}
	for kind in d.owned do
		if not hasItem[kind] and catalog.isValidId(kind) then
			table.insert(missing, kind)
		end
	end
	table.sort(missing)
	for _, kind in missing do
		table.insert(items, { id = pen.nextId, kind = kind, form = 0, level = 1, coat = 0 })
		note(problems, `pen.items (owned {kind})`, nil, pen.nextId)
		pen.nextId += 1
	end
	if #items > PEN.toyBoxMax + PEN.placedMax then
		note(problems, "pen.items (over toyBoxMax + placedMax, all kept)", #items, #items)
	end

	-- Pens3 phase 6: slots and locks (see the header). Every item ends in the Toy Box (0) or one open spot of its own.
	local held: { [number]: boolean } = {}
	local unplaced: { any } = {}
	for _, item in items do
		local slot = item.slot
		if slot == nil then
			table.insert(unplaced, item)
		elseif slot ~= 0 then
			local open = isFinite(slot) and math.floor(slot) == slot and slot >= 1 and slot <= pen.spots
			if open and not held[slot] then
				held[slot] = true
			else
				note(problems, `pen.items (slot of {show(item.kind)} {item.id})`, slot, 0)
				item.slot = 0
			end
		end
		if item.locked == nil then
			item.locked = false
		elseif type(item.locked) ~= "boolean" then
			note(problems, `pen.items (lock of {show(item.kind)} {item.id})`, item.locked, false)
			item.locked = false
		end
	end
	table.sort(unplaced, PenMath.better)
	local free = 1
	for _, item in unplaced do
		while held[free] do
			free += 1
		end
		item.slot = if free <= pen.spots then free else 0
		held[free] = true
		note(problems, `pen.items (slot of {show(item.kind)} {item.id})`, nil, item.slot)
	end
	pen.items = items
end

-- Pens3 phase 5 (see the header): the gift queue, the fixed box orders and the gifts given. Fixed in place, noted.
local function fixGifts(d: any, catalog: CatalogLike, fresh: any, problems: { string })
	local queue = ensureTable(d, "giftQueue", function()
		return {}
	end, "giftQueue", problems)
	local kept: { string } = {}
	local count = 0
	for _ in queue do
		count += 1
	end
	for index, id in ipairs(queue) do
		if catalog.isValidId(id) then
			table.insert(kept, id)
		else
			note(problems, `giftQueue[{index}]`, id, "removed")
		end
	end
	if #kept ~= count then
		d.giftQueue = kept
		note(problems, "giftQueue", count, #kept)
	end
	if #kept > PEN.giftQueueMax then
		note(problems, "giftQueue (over giftQueueMax, all kept)", #kept, #kept)
	end

	local order = ensureTable(d, "boxOrder", function()
		return {}
	end, "boxOrder", problems)
	for _, id in PAID_BOX_IDS do
		fixInt(order, id, 0, MAX_COUNTER, 0, `boxOrder.{id}`, problems)
	end

	local gifts = ensureTable(d, "gifts", function()
		local given = {}
		for key in fresh.gifts do
			given[key] = true -- fail closed: a broken record never gives a gift twice
		end
		return given
	end, "gifts", problems)
	fixFlagMap(gifts, true, "gifts", problems)
end

-- Pens3 phases 7-8 (see the header): the buy-back list and the bag. Fixed in place, every fix noted.
local function isSale(entry: any, catalog: CatalogLike, now: number): boolean
	local item = if type(entry) == "table" then entry.item else nil
	local function whole(v: unknown, lo: number, hi: number): boolean
		return isFinite(v) and math.floor(v :: number) == v and (v :: number) >= lo and (v :: number) <= hi
	end
	return type(item) == "table"
		and catalog.isValidId(item.kind)
		and whole(item.form, 0, #PEN.formMult - 1)
		and whole(item.level, 1, PEN.maxLevel)
		and whole(item.coat, 0, #PEN.coatMult - 1)
		and whole(item.id, 1, MAX_COUNTER)
		and whole(entry.price, 0, Config.Economy.maxCoins)
		and isFinite(entry.at)
		and entry.at <= now + FUTURE_SLACK_SECONDS
		and type(entry.req) == "string"
end

local function fixSales(d: any, catalog: CatalogLike, now: number, problems: { string })
	local list = ensureTable(d, "buyBack", function()
		return {}
	end, "buyBack", problems)
	local kept: { any } = {}
	local count = 0
	for _ in list do
		count += 1
	end
	for index, entry in ipairs(list) do
		if isSale(entry, catalog, now) then
			table.insert(kept, entry)
		else
			local item = if type(entry) == "table" and type(entry.item) == "table" then entry.item.kind else entry
			note(problems, `buyBack[{index}]`, item, "removed")
		end
	end
	local trimmed = #kept > PEN.buyBackMax
	if #kept ~= count then
		note(problems, "buyBack", count, #kept)
	end
	if trimmed then
		note(problems, "buyBack (over buyBackMax, newest kept)", #kept, PEN.buyBackMax)
		kept = table.move(kept, #kept - PEN.buyBackMax + 1, #kept, 1, {})
	end
	if trimmed or #kept ~= count then
		d.buyBack = kept
	end

	local size = #PEN.coatMult - 1
	local bag = ensureTable(d, "bag", function()
		return table.create(size, 0)
	end, "bag", problems)
	for key, value in table.clone(bag) :: { [any]: any } do
		if not (type(key) == "number" and key >= 1 and key <= size and math.floor(key) == key) then
			bag[key] = nil
			note(problems, `bag[{show(key)}]`, value, "removed")
		end
	end
	for index = 1, size do
		fixInt(bag, index :: any, 0, MAX_COUNTER, 0, `bag[{index}]`, problems)
	end
end

-- Pens3 phase 9 (see the header): none of each Config food.
local function noFood(): { [string]: number }
	local food: { [string]: number } = {}
	for _, def in FOOD.foods do
		food[def.id] = 0
	end
	return food
end

local function fixFood(d: any, problems: { string })
	local food = ensureTable(d, "food", noFood, "food", problems)
	local known = noFood()
	for key, value in table.clone(food) :: { [any]: any } do
		if known[key] == nil then
			food[key] = nil
			note(problems, `food[{show(key)}]`, value, "removed")
		end
	end
	for _, def in FOOD.foods do
		fixInt(food, def.id, 0, FOOD.maxPieces, 0, `food.{def.id}`, problems)
	end
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
		autoClick = { step = 0, at = 0 }, -- auto-clicker check (2026-10-16): no strike
		weekly = { week = -1, active = {} }, -- weekly quests (2026-10-17): none until the first check
		-- Pens3 phase 1: the starter walks in the free spots.
		pen = {
			spots = PEN.startSpots,
			nextId = 2,
			-- Pens3 phase 6: the starter in spot 1, unlocked.
			items = { { id = 1, kind = starter, form = 0, level = 1, coat = 0, slot = 1, locked = false } },
			awayRate = 0, -- pens3 phase 4: the pen's rate at the last save (DataService stamps it)
		},
		-- Pens3 phase 5: no gift waiting for room, no fixed-order box opened, the Frog gift still to come.
		giftQueue = {},
		boxOrder = {},
		gifts = { frog = false },
		buyBack = {}, -- pens3 phase 7: nothing to buy back
		bag = table.create(#PEN.coatMult - 1, 0), -- pens3 phase 8: no coating in the bag
		food = noFood(), -- pens3 phase 9: no food
	}
	for _, id in PAID_BOX_IDS do
		profile.boxOrder[id] = 0
	end
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

	-- The pen (pens3 phase 1, see the header).
	fixPen(d, catalog, now, problems)
	fixGifts(d, catalog, fresh, problems) -- pens3 phase 5
	fixSales(d, catalog, now, problems) -- pens3 phases 7-8
	fixFood(d, problems) -- pens3 phase 9

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
