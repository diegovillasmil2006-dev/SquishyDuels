--!strict
-- EconomyService (server only). DESIGN §2.3, §3.4, §3.11, §6.1, §6.2, §6.5, §6.7, §12 #3, #6, #14.
-- The only place where Coins and ownership change. Every change runs inside DataService.mutate (through the data
-- port): one non-yielding step on the live profile of a READY session (DataService keeps it; saves snapshot it later,
-- §3.9). After the change has landed, the state channel is told (StateService.markDirty) and CoinsChanged /
-- SquishyGranted fire for the layers above (quests, onboarding, ...).
-- * Coins are integers in [0, Config.Economy.maxCoins] and never go negative. Amounts are whole numbers from 0 to
--   maxCoins (server values only, never client input, §12 #3). Reasons are the closed list
--   Config.Economy.CoinReasons (§6.1); "debug" only while Config.Debug.debugCoinReason (Studio). A grant that would
--   pass maxCoins is clamped (the returned amount is what was really added).
-- * Profile status (§3.13, §12 #6): grants need a READY profile (OFFLINE / READONLY / loading sessions earn nothing,
--   they are never saved; neither is a change after the final leave snapshot, which mutate refuses); spends also need
--   no pending failed save (§3.11: boxes, shop, daily and capsules are blocked while savePending; each caller turns
--   "savePending" into its own code: box.saving, capsule.paused, ...).
-- * Idempotency (§3.4): there is no generic ledger; each action keeps its own log. The duel ledger lives here:
--   grantDuelResult(p, matchId, outcome, result) appends {matchId, opp, result, at, full} to profile.duelLog (cap
--   Config.Data.caps.duelLog, oldest dropped), updates the same-pair record profile.samePair (§6.7, §12 #15:
--   DuelRewards.recordSamePair drops times older than the rolling window and adds now only for a fully rewarded
--   result), counts the duel stats and pays the Coins, all in one step (the reward is counted in squeezes, spec
--   2026-10-12 §9: it pays PenMath.rewardCoins(squeezes, the profile's squeeze value: PenMath.squeezeValue of its pen
--   since pens3 phase 1) in that same step, so the squeeze value is the one of the moment it is granted), and a
--   matchId already in duelLog is a no-op
--   (exactly once together with DuelService's single end, §12 #14; a replay never adds a second same-pair time). It
--   asks for a "soon" save. findLog / appendLog are the same helpers for the other logs (boxLog, shopLog, receipts,
--   Part 7).
-- * Squishies (pens3 phase 5: DuplicatePolicy "copy", D1:254-258): grantSquishy(p, id, source, mayWait?) adds a pen
--   item {id = pen.nextId, kind, form = 0, level = 1, coat = 0} (and nextId + 1), and an owned entry {at, src} when the
--   kind is new, in one step; a kind owned again is a copy (never Coins). SquishyGranted fires for every item added
--   (PenService shows it). The Toy Box full (PenMath.room 0): refused with "full" and nothing changes, unless mayWait
--   (a free reward): then the kind joins profile.giftQueue (oldest first, at most Pen.giftQueueMax; not owned until it
--   drops in). Nothing is ever sold automatically. dropGifts(p) drops queued kinds in, oldest first, while there is
--   room (PenService: after a spot buy and on load). grantGift(p, key, id) gives `id` once per account: profile.gifts
--   [key] is set in the same step as the grant (or the queue), so it is never given twice. Pens3 phase 6: the new
--   item takes the first free pen spot (PenMath.freeSlot), else the Toy Box (slot 0), unlocked; a placed squishy never
--   moves.
-- * Reading: stats.coinsEarned / coinsSpent count every real grant and spend except the Studio-only "debug" reason,
--   so Studio tests never inflate them. Reading: stats.eliminations counts opponents eliminated in recorded results
--   (DuelService passes 0 or 1).
-- * The caller decides the save of a Coin grant or spend (§3.4: squeeze rides the autosave, boxes and the shop save
--   "now"); grantDuelResult asks for "soon" itself.
-- * Match HUD M2 (2026-10-16, owner Q3 / Q4): grantMatchResult(p, matchId, pay) records one Free for All / Team
--   Deathmatch result (Logic/MatchRewards' Pay) in one step: stats.winStreak becomes MatchRewards.nextStreak (a win
--   +1, anything else 0) and pay.squeezes are paid as Coins with reason "match" (squeezes × the Coins of one
--   squeeze, MatchRewards.squeezeWorth, of that moment); a "soon" save when something changed. Exactly once per
--   player per matchId (plan v2 §4 M2; review fix 2026-10-16): a matchId already granted to that player is a no-op
--   (alreadyGranted). The record is in memory (the newest MATCHES_REMEMBERED matches), not in the profile: a match
--   never leaves the server that runs it, and the owner chose no hourly cap, so no saved record is needed.
--   winStreak(p) reads the saved streak. 1v1 duels (grantDuelResult) never touch the streak.
-- * Pens3 phase 4: grantAway(p) pays the Coins for the time away, PenMath.awayCoins(pen.awayRate (the pen's rate at
--   the last save, DataService), lastSeenAt, createdAt, now), with reason "away", and stamps lastSeenAt = now in the
--   SAME step: the time away counted is the time stamped as paid, so a second call pays 0, and a crash before the next
--   save loses the grant and the stamp together (the next load pays that time once). A "soon" save when it paid.
-- Failures come back as a short kind ("invalid", "reason", "notReady", "savePending", "notEnoughCoins", "full"); CODES
-- maps the kinds that have a §2.10 code. Collaborators are reached through `deps` (useDeps in tests).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local PenMath = require(Shared.PenMath)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local DuelRewards = require(script.Parent.Parent.Logic.DuelRewards)
local MatchRewards = require(script.Parent.Parent.Logic.MatchRewards)
local StateService = require(script.Parent.StateService)

-- Types

export type Failure = "invalid" | "reason" | "notReady" | "savePending" | "notEnoughCoins" | "full"

export type Deps = {
	data: StateService.DataPort,
	markDirty: (player: any, field: string) -> (),
	now: () -> number, -- os.time(): owned `at`, the same-pair record's times
	debugAllowed: () -> boolean, -- the Studio-only "debug" reason
}

-- What grantSquishy did (pens3 phase 5): `added` = a pen item was added; `copy` = the kind was owned before; `queued` =
-- the Toy Box was full and it waits in profile.giftQueue; `refused` is set when nothing changed (no profile, unknown
-- id, the Toy Box full, ...).
export type SquishyGrant = { added: boolean, copy: boolean, queued: boolean, refused: Failure? }

-- The duel result as DuelService passes it (computed by Logic/DuelRewards, §6.7).
export type DuelResultInput = {
	coins: number, -- the reward counted in squeezes (0 when not eligible); paid as squeezes × the squeeze value
	logEntry: Types.DuelLogEntry?, -- nil = nothing to record (no ready profile, test dummy, cancelled, already granted)
	eliminations: number?, -- opponents this player eliminated in the match (0 or 1)
}

-- What grantDuelResult did.
export type DuelGrant = {
	coins: number, -- Coins really added
	recorded: boolean, -- the duelLog entry was appended (the result counts)
	alreadyGranted: boolean, -- the matchId was in duelLog: nothing happened
	blockedReason: string?, -- duel.noRewardsOffline when the profile is not ready
}

-- Match HUD M2: what grantMatchResult did.
export type MatchGrant = {
	coins: number, -- Coins really added
	recorded: boolean, -- the profile step ran (the streak is set)
	alreadyGranted: boolean, -- this matchId was already granted to this player (on this server): nothing happened
	streakBefore: number,
	streakAfter: number,
	blockedReason: string?, -- duel.noRewardsOffline when the profile is not ready
}

-- Constants

local ECONOMY = Config.Economy
local MAX_COINS = ECONOMY.maxCoins
local DUEL_LOG_CAP = Config.Data.caps.duelLog
-- The guard counts squeezes, so a legit reward passes at any squeeze value (its Coins stop at maxCoins).
local MAX_DUEL_SQUEEZES = math.max(ECONOMY.DuelRewards.win, ECONOMY.DuelRewards.loss, ECONOMY.DuelRewards.draw)
local MAX_MATCH_SQUEEZES = MatchRewards.maxSqueezes() -- Match HUD M2: a match pays a duel's amounts
local REASON_MATCH = "match"
local REASON_AWAY = "away" -- pens3 phase 4
-- Match HUD M2 review fix (reading): matches whose grants are remembered for the exactly-once check. A server runs a
-- few matches at once and a repeat can only come while its match is ending, so 64 is far more than ever needed.
local MATCHES_REMEMBERED = 64
local STATUS_READY = "ready"
local REASON_DEBUG = "debug"
local SOURCE_GRANT = "grant" -- pens3 phase 5: a gift, or a queued squishy that drops in
local SAVE_SOON = "soon"
local CODE_NO_REWARDS_OFFLINE = "duel.noRewardsOffline"
local OWNED_SOURCES: { [string]: boolean } = { starter = true, box = true, shop = true, grant = true }
local DUEL_RESULTS: { [string]: string } = { win = "duel_win", loss = "duel_loss", draw = "duel_draw" }
local DUEL_STAT: { [string]: string } = { win = "duelsWon", loss = "duelsLost", draw = "duelsDrawn" }

local REASONS: { [string]: boolean } = {}
for _, reason in ECONOMY.CoinReasons do
	REASONS[reason] = true
end

-- Module table

local EconomyService = {}

-- (player, coins, delta, reason) after every change of a player's Coins.
EconomyService.CoinsChanged = Signal.new() :: Signal.Signal<Player, number, number, string>
-- (player, squishyId, source) when a squishy joins the pen (pens3 phase 5: a copy too; not for a queued gift until it
-- drops in, then with source "grant").
EconomyService.SquishyGranted = Signal.new() :: Signal.Signal<Player, string, string>

-- §2.10 codes for the failure kinds that have one ("savePending" is the caller's: box.saving, capsule.paused, ...).
EconomyService.CODES = table.freeze({
	notReady = "data.notReady",
	notEnoughCoins = "economy.notEnoughCoins",
	invalid = "net.invalid",
	full = "inventory.full", -- pens3 phase 5: the Toy Box is full
})

-- Private

local log = Log.new("Economy")
local deps: Deps? = nil
-- Match HUD M2 review fix: matchId -> the players (UserId) grantMatchResult recorded for it on this server, and the
-- matchIds oldest first (only the newest MATCHES_REMEMBERED are kept).
local matchGrants: { [string]: { [any]: boolean } } = {}
local matchGrantOrder: { string } = {}

local function defaultDeps(): Deps
	return {
		data = StateService.dataPort(),
		markDirty = function(player: any, field: string)
			StateService.markDirty(player, field)
		end,
		now = os.time,
		debugAllowed = function(): boolean
			return Config.Debug.debugCoinReason == true
		end,
	}
end

local function getDeps(): Deps
	local current = deps
	if current then
		return current
	end
	local created = defaultDeps()
	deps = created
	return created
end

local function isWhole(n: unknown): boolean
	return type(n) == "number" and n == n and n >= 0 and n <= MAX_COINS and math.floor(n) == n
end

local function reasonAllowed(reason: unknown): boolean
	return EconomyService.isReason(reason) and (reason ~= REASON_DEBUG or getDeps().debugAllowed())
end

local function isReady(player: any): boolean
	return getDeps().data.status(player) == STATUS_READY
end

-- Runs fn(profile) through DataService.mutate on a READY session. Returns false when nothing could change (not
-- ready, the final leave snapshot already taken, or fn failed).
local function edit(player: any, fn: (profile: any) -> ()): boolean
	if not isReady(player) then
		return false
	end
	local ok, why = getDeps().data.mutate(player, function(profile: any): any
		fn(profile)
		return nil
	end)
	if not ok then
		log:debug(`profile change refused: {tostring(why)}`)
	end
	return ok
end

local function statsOf(profile: any): { [string]: number }
	local stats = profile.stats
	if type(stats) ~= "table" then
		stats = {}
		profile.stats = stats
	end
	return stats
end

local function addStat(profile: any, name: string, amount: number)
	local stats = statsOf(profile)
	local current = stats[name]
	stats[name] = (if type(current) == "number" and current == current then current else 0) + amount
end

local function coinsOf(profile: any): number
	return EconomyService.clampCoins(profile.coins)
end

-- Adds Coins to a profile inside an edit (no checks on the reason). Returns what was really added.
local function addCoinsTo(profile: any, amount: number, reason: string): number
	local before = coinsOf(profile)
	local after = math.min(MAX_COINS, before + amount)
	profile.coins = after
	local added = after - before
	if added > 0 and reason ~= REASON_DEBUG then
		addStat(profile, "coinsEarned", added)
	end
	return added
end

-- After a Coins change landed: the state fields and CoinsChanged.
local function coinsChanged(player: any, coins: number, delta: number, reason: string)
	local d = getDeps()
	d.markDirty(player, "coins")
	d.markDirty(player, "stats")
	EconomyService.CoinsChanged:fire(player, coins, delta, reason)
end

-- Match HUD M2 review fix: a player's key in matchGrants (the UserId; the ref itself for a test player without one).
local function grantKeyOf(player: any): any
	local id = if type(player) == "table" or (typeof(player) == "Instance" and player:IsA("Player"))
		then player.UserId
		else nil
	return if type(id) == "number" then id else player
end

-- Match HUD M2 review fix: remembers that `matchId` was granted to `key`; the oldest match is forgotten past the cap.
local function rememberMatchGrant(matchId: string, key: any)
	local granted = matchGrants[matchId]
	if granted == nil then
		granted = {}
		matchGrants[matchId] = granted
		table.insert(matchGrantOrder, matchId)
		while #matchGrantOrder > MATCHES_REMEMBERED do
			matchGrants[table.remove(matchGrantOrder, 1) :: string] = nil
		end
	end
	(granted :: { [any]: boolean })[key] = true
end

-- Pens3 phase 5: adds one squishy to a profile inside an edit (see the header). Never yields.
local function addSquishyTo(profile: any, id: string, source: string, mayWait: boolean, form: number?): SquishyGrant
	local owned = profile.owned
	if type(owned) ~= "table" then
		owned = {}
		profile.owned = owned
	end
	local copy = owned[id] ~= nil
	local pen = profile.pen
	if PenMath.room(pen) <= 0 then
		local queue = profile.giftQueue
		if mayWait and type(queue) == "table" and #queue < ECONOMY.Pen.giftQueueMax then
			table.insert(queue, id)
			return { added = false, copy = copy, queued = true, refused = nil }
		end
		return { added = false, copy = copy, queued = false, refused = "full" }
	end
	if not copy then
		owned[id] = { at = getDeps().now(), src = source :: Types.OwnedSource }
	end
	local slot = PenMath.freeSlot(pen) -- pens3 phase 6: the first free spot, else the Toy Box (0)
	-- shortcut: a queued squishy (a full Toy Box, above) keeps only its kind, so a Golden free box reward waiting
	-- there lands plain; store {kind, form} in giftQueue if that ever matters (paid boxes refuse a full Toy Box).
	local item = { id = pen.nextId, kind = id, form = form or 0, level = 1, coat = 0, slot = slot, locked = false }
	table.insert(pen.items, item)
	pen.nextId += 1
	PenMath.arrange(pen) -- qb1 (owner 2026-10-18): the best squishies go to the TOP spot and the shelf
	return { added = true, copy = copy, queued = false, refused = nil }
end

-- After grants landed: the new kinds' owned field and one SquishyGranted per pen item added.
local function squishiesAdded(player: any, ids: { string }, newKind: boolean, source: string)
	if newKind then
		getDeps().markDirty(player, "owned")
	end
	for _, id in ids do
		EconomyService.SquishyGranted:fire(player, id, source)
	end
end

-- Public: pure helpers (unit-tested) -----------------------------------------------------------------------------------

-- Any value as a Coin balance: an integer in [0, maxCoins] (non-finite or missing -> 0, fractions floored).
function EconomyService.clampCoins(value: unknown): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, MAX_COINS)
end

-- True for a reason in Config.Economy.CoinReasons (§6.1).
function EconomyService.isReason(reason: unknown): boolean
	return type(reason) == "string" and REASONS[reason] == true
end

-- A reward counted in squeezes (duels, daily, quests, starter tasks; spec 2026-10-12 §9) as the Coins it pays now:
-- PenMath.rewardCoins(squeezes, the squeeze value of the profile's pen; a new player's 10 without one; pens3 phase 1).
function EconomyService.rewardCoins(profile: unknown, squeezes: number): number
	local pen = if type(profile) == "table" then (profile :: any).pen else nil
	return PenMath.rewardCoins(squeezes, PenMath.squeezeValue(pen))
end

-- The first entry of a log whose `keyField` equals `key` (duelLog.matchId, boxLog.req, shopLog.req, receipts.id).
function EconomyService.findLog(list: unknown, keyField: string, key: unknown): any?
	if type(list) ~= "table" then
		return nil
	end
	for _, entry in list :: { any } do
		if type(entry) == "table" and entry[keyField] == key then
			return entry
		end
	end
	return nil
end

-- Appends an entry to a capped log, dropping the oldest entries above `cap` (Config.Data.caps).
function EconomyService.appendLog(list: { any }, entry: any, cap: number)
	table.insert(list, entry)
	while #list > cap do
		table.remove(list, 1)
	end
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Uses these collaborators (nil = the real ones; tests). Match HUD M2: also forgets the match grants (each test starts
-- with none).
function EconomyService.useDeps(newDeps: Deps?)
	deps = newDeps
	matchGrants = {}
	matchGrantOrder = {}
end

-- True when the player's profile is ready (grants allowed; DuelService's profileReady hook).
function EconomyService.canEarn(player: any): boolean
	return isReady(player)
end

-- (true) when the player may spend now; else (false, "notReady" | "savePending").
function EconomyService.canSpend(player: any): (boolean, Failure?)
	if not isReady(player) then
		return false, "notReady"
	end
	if getDeps().data.savePending(player) then
		return false, "savePending"
	end
	return true, nil
end

-- The player's Coins (0 without a profile).
function EconomyService.coins(player: any): number
	local profile = getDeps().data.getProfile(player)
	return if type(profile) == "table" then coinsOf(profile) else 0
end

-- The player's duelLog ({} without a profile). Read-only for callers (DuelService's matchId check, §6.7).
function EconomyService.duelLog(player: any): { Types.DuelLogEntry }
	local profile = getDeps().data.getProfile(player)
	local list = if type(profile) == "table" then profile.duelLog else nil
	return if type(list) == "table" then list else {}
end

-- The player's same-pair record ({} without a profile). Read-only for callers (DuelService's same-pair count, §6.7).
function EconomyService.samePair(player: any): Types.SamePairRecord
	local profile = getDeps().data.getProfile(player)
	local record = if type(profile) == "table" then profile.samePair else nil
	return if type(record) == "table" then record else {}
end

-- Match HUD M2: the player's saved Free for All / Team Deathmatch win streak (0 without a profile; MatchService's
-- SD_WinStreak attribute).
function EconomyService.winStreak(player: any): number
	local profile = getDeps().data.getProfile(player)
	local stats = if type(profile) == "table" then profile.stats else nil
	return MatchRewards.streakOf(if type(stats) == "table" then stats.winStreak else nil)
end

-- Adds `amount` Coins for `reason`. Returns (added, failure?): added is what was really added (clamped at maxCoins;
-- 0 on any failure). Never yields.
function EconomyService.grantCoins(player: any, amount: number, reason: string): (number, Failure?)
	if not isWhole(amount) then
		log:warn(`grantCoins: invalid amount {tostring(amount)} ({tostring(reason)})`)
		return 0, "invalid"
	end
	if not reasonAllowed(reason) then
		log:warn(`grantCoins: reason {tostring(reason)} is not allowed`)
		return 0, "reason"
	end
	if not isReady(player) then
		return 0, "notReady"
	end
	if amount == 0 then
		return 0, nil
	end
	local added, after = 0, 0
	local ok = edit(player, function(profile: any)
		added = addCoinsTo(profile, amount, reason)
		after = profile.coins
	end)
	if not ok then
		return 0, "notReady"
	end
	if added > 0 then
		coinsChanged(player, after, added, reason)
	end
	return added, nil
end

-- Takes `amount` Coins for `reason` if the player has them. Returns (true) or (false, failure). Never yields, never
-- goes below 0, refused while a failed save is pending (§3.11).
function EconomyService.trySpend(player: any, amount: number, reason: string): (boolean, Failure?)
	if not isWhole(amount) or amount <= 0 then
		log:warn(`trySpend: invalid amount {tostring(amount)} ({tostring(reason)})`)
		return false, "invalid"
	end
	if not reasonAllowed(reason) then
		log:warn(`trySpend: reason {tostring(reason)} is not allowed`)
		return false, "reason"
	end
	local allowed, why = EconomyService.canSpend(player)
	if not allowed then
		return false, why :: Failure?
	end
	local short, after = false, 0
	local ok = edit(player, function(profile: any)
		local before = coinsOf(profile)
		if before < amount then
			short = true
			return
		end
		profile.coins = before - amount
		after = profile.coins
		if reason ~= REASON_DEBUG then
			addStat(profile, "coinsSpent", amount)
		end
	end)
	if not ok then
		return false, "notReady"
	elseif short then
		return false, "notEnoughCoins"
	end
	coinsChanged(player, after, -amount, reason)
	return true, nil
end

-- Adds a squishy to the pen (§6.5, pens3 phase 5: a copy when owned; see the header). `mayWait` (a free reward): a
-- full Toy Box queues it instead of refusing. `form` (2026-10-31, golden luck): 0 plain (the default), 1 Golden,
-- 2 Rainbow. Returns {added, copy, queued, refused?}. Never yields.
function EconomyService.grantSquishy(
	player: any,
	id: string,
	source: string,
	mayWait: boolean?,
	form: number?
): SquishyGrant
	local validForm = form == nil or form == 0 or form == 1 or form == 2
	if not Catalog.isValidId(id) or not OWNED_SOURCES[source] or not validForm then
		log:warn(`grantSquishy: invalid id {tostring(id)}, source {tostring(source)} or form {tostring(form)}`)
		return { added = false, copy = false, queued = false, refused = "invalid" }
	end
	local grant: SquishyGrant = { added = false, copy = false, queued = false, refused = "notReady" }
	local ok = edit(player, function(profile: any)
		grant = addSquishyTo(profile, id, source, mayWait == true, form)
	end)
	if not ok then
		return { added = false, copy = false, queued = false, refused = "notReady" }
	end
	if grant.refused == "full" then
		log:info(`grantSquishy: user {tostring(grantKeyOf(player))}'s Toy Box is full; {id} ({source}) not granted`)
	end
	squishiesAdded(player, if grant.added then { id } else {}, grant.added and not grant.copy, source)
	return grant
end

-- Pens3 phase 5: drops queued gifts into the pen, oldest first, while there is room (one step; see the header).
-- Returns how many dropped. Never yields.
function EconomyService.dropGifts(player: any): number
	local dropped: { string } = {}
	local newKind = false
	edit(player, function(profile: any)
		local queue = profile.giftQueue
		while type(queue) == "table" and #queue > 0 and PenMath.room(profile.pen) > 0 do
			local id = table.remove(queue, 1) :: string -- a Catalog kind (sanitize keeps only those)
			local grant = addSquishyTo(profile, id, SOURCE_GRANT, false)
			newKind = newKind or not grant.copy
			table.insert(dropped, id)
		end
	end)
	squishiesAdded(player, dropped, newKind, SOURCE_GRANT)
	return #dropped
end

-- Pens3 phase 5: gives `id` once per account (profile.gifts[key] set in the same step; queued when the Toy Box is
-- full). Returns true when it was given now. Never yields.
function EconomyService.grantGift(player: any, key: string, id: string): boolean
	if not Catalog.isValidId(id) then
		log:warn(`grantGift: {tostring(id)} is not a squishy`)
		return false
	end
	local grant: SquishyGrant? = nil
	edit(player, function(profile: any)
		local gifts = profile.gifts
		if type(gifts) ~= "table" or gifts[key] ~= false then
			return -- given already (or no record to stamp: fail closed)
		end
		grant = addSquishyTo(profile, id, SOURCE_GRANT, true)
		if (grant :: SquishyGrant).refused == nil then
			gifts[key] = true
		end
	end)
	local given = grant :: SquishyGrant?
	if given == nil or given.refused ~= nil then
		return false
	end
	squishiesAdded(player, if given.added then { id } else {}, given.added and not given.copy, SOURCE_GRANT)
	return true
end

-- Records one finished duel for a real player and pays its reward, exactly once per matchId (§3.4, §3.11, §6.7):
-- duelLog entry (capped), the same-pair record (a time only for a fully rewarded result), duelsPlayed /
-- duelsWon|Lost|Drawn / eliminations, Coins with reason duel_<outcome> (result.coins squeezes × the squeeze value),
-- then a "soon" save. `outcome` is this player's view (win / loss / draw). Never yields.
function EconomyService.grantDuelResult(
	player: any,
	matchId: string,
	outcome: string,
	result: DuelResultInput
): DuelGrant
	local grant: DuelGrant = { coins = 0, recorded = false, alreadyGranted = false, blockedReason = nil }
	local reason = DUEL_RESULTS[outcome]
	local entry = result.logEntry
	if reason == nil or type(matchId) ~= "string" or matchId == "" then
		return grant -- cancelled / void: nothing to record
	end
	if entry ~= nil and (entry.matchId ~= matchId or entry.result ~= outcome) then
		log:warn(`grantDuelResult: log entry does not match match {matchId} / {outcome}; nothing recorded`)
		return grant
	end
	local squeezes = result.coins
	if not isWhole(squeezes) or squeezes > MAX_DUEL_SQUEEZES then
		log:warn(`grantDuelResult: invalid reward {tostring(squeezes)} for match {matchId}; recorded without Coins`)
		squeezes = 0
	end
	local after = 0
	local ok = edit(player, function(profile: any)
		local duelLog = profile.duelLog
		if type(duelLog) ~= "table" then
			duelLog = {}
			profile.duelLog = duelLog
		end
		if EconomyService.findLog(duelLog, "matchId", matchId) ~= nil then
			grant.alreadyGranted = true
			return
		end
		if entry == nil then
			return -- nothing to record (DuelRewards gave no entry)
		end
		-- `full` (DuelRewards: a fully rewarded result) feeds the same-pair record (§6.7); a result paying 0 never is.
		local logged: Types.DuelLogEntry = {
			matchId = matchId,
			opp = entry.opp,
			result = entry.result,
			at = entry.at,
			full = if squeezes > 0 then entry.full else false,
		}
		EconomyService.appendLog(duelLog, logged, DUEL_LOG_CAP)
		-- Reading: an entry without `full` that pays Coins counts as fully rewarded (fail closed).
		local samePair = profile.samePair
		if type(samePair) ~= "table" then
			samePair = {}
			profile.samePair = samePair
		end
		DuelRewards.recordSamePair(samePair, entry.opp, getDeps().now(), logged.full ~= false)
		grant.recorded = true
		addStat(profile, "duelsPlayed", 1)
		addStat(profile, DUEL_STAT[outcome], 1)
		local eliminations = result.eliminations
		if type(eliminations) == "number" and eliminations > 0 and math.floor(eliminations) == eliminations then
			addStat(profile, "eliminations", eliminations)
		end
		if squeezes > 0 then
			grant.coins = addCoinsTo(profile, EconomyService.rewardCoins(profile, squeezes), reason)
			after = profile.coins
		end
	end)
	if not ok then
		grant.blockedReason = CODE_NO_REWARDS_OFFLINE
		return grant
	end
	if grant.recorded then
		getDeps().markDirty(player, "stats")
		if grant.coins > 0 then
			coinsChanged(player, after, grant.coins, reason)
		end
		getDeps().data.requestSave(player, SAVE_SOON)
	end
	return grant
end

-- Match HUD M2 (2026-10-16): records one Free for All / Team Deathmatch result for a real player (see the header): in
-- one step stats.winStreak = MatchRewards.nextStreak(the saved streak, pay) and pay.squeezes (a whole number up to the
-- largest duel reward, else 0 with a warning) paid as Coins with reason "match", then a "soon" save when something
-- changed. Exactly once per player and matchId: a repeat changes nothing and returns alreadyGranted (its streakBefore
-- = streakAfter = the saved streak). Never yields.
function EconomyService.grantMatchResult(player: any, matchId: string, pay: MatchRewards.Pay): MatchGrant
	local grant: MatchGrant = {
		coins = 0,
		recorded = false,
		alreadyGranted = false,
		streakBefore = 0,
		streakAfter = 0,
		blockedReason = nil,
	}
	if type(pay) ~= "table" or type(matchId) ~= "string" or matchId == "" then
		log:warn(`grantMatchResult: no pay or no match id ({tostring(matchId)}); nothing recorded`)
		return grant
	end
	local key = grantKeyOf(player)
	local granted = matchGrants[matchId]
	if granted ~= nil and granted[key] then
		grant.alreadyGranted = true
		grant.streakBefore = EconomyService.winStreak(player)
		grant.streakAfter = grant.streakBefore
		return grant
	end
	local squeezes = pay.squeezes
	if not isWhole(squeezes) or squeezes > MAX_MATCH_SQUEEZES then
		log:warn(`grantMatchResult: invalid pay {tostring(squeezes)} for match {matchId}; the streak only`)
		squeezes = 0
	end
	local after = 0
	local ok = edit(player, function(profile: any)
		local stats = statsOf(profile)
		grant.streakBefore = MatchRewards.streakOf(stats.winStreak)
		grant.streakAfter = MatchRewards.nextStreak(grant.streakBefore, pay)
		stats.winStreak = grant.streakAfter
		if squeezes > 0 then
			local coinsPerSqueeze = MatchRewards.squeezeWorth(profile)
			grant.coins = addCoinsTo(profile, PenMath.rewardCoins(squeezes, coinsPerSqueeze), REASON_MATCH)
			after = profile.coins
		end
	end)
	if not ok then
		grant.blockedReason = CODE_NO_REWARDS_OFFLINE
		return grant
	end
	grant.recorded = true
	rememberMatchGrant(matchId, key)
	local streakChanged = grant.streakAfter ~= grant.streakBefore
	if streakChanged then
		getDeps().markDirty(player, "stats")
	end
	if grant.coins > 0 then
		coinsChanged(player, after, grant.coins, REASON_MATCH)
	end
	if streakChanged or grant.coins > 0 then
		getDeps().data.requestSave(player, SAVE_SOON)
	end
	return grant
end

-- Pens3 phase 4: the Coins for the time away and the lastSeenAt stamp, in one step (see the header). Returns (Coins
-- really added, the seconds counted); (0, 0) when nothing could change. Never yields.
function EconomyService.grantAway(player: any): (number, number)
	local now = getDeps().now()
	local added, seconds, after = 0, 0, 0
	local ok = edit(player, function(profile: any)
		local pen = profile.pen
		local due
		due, seconds = PenMath.awayCoins(
			if type(pen) == "table" then pen.awayRate else 0,
			profile.lastSeenAt,
			profile.createdAt,
			now
		)
		added = addCoinsTo(profile, due, REASON_AWAY)
		profile.lastSeenAt = now
		after = profile.coins
	end)
	if not ok then
		return 0, 0
	end
	if added > 0 then
		coinsChanged(player, after, added, REASON_AWAY)
		getDeps().data.requestSave(player, SAVE_SOON)
	end
	return added, seconds
end

-- Studio only (Config.Debug.debugCoinReason): sets the player's Coins (DebugHooks setCoins). Returns false elsewhere
-- or without a ready profile.
function EconomyService.debugSetCoins(player: any, coins: number): boolean
	if not getDeps().debugAllowed() or not isWhole(coins) then
		return false
	end
	local before = 0
	local ok = edit(player, function(profile: any)
		before = coinsOf(profile)
		profile.coins = coins
	end)
	if ok and coins ~= before then
		coinsChanged(player, coins, coins - before, REASON_DEBUG)
	end
	return ok
end

-- Not called by the bootstrap; used by leak checks.
function EconomyService.destroy()
	EconomyService.CoinsChanged:disconnectAll()
	EconomyService.SquishyGranted:disconnectAll()
end

return EconomyService
