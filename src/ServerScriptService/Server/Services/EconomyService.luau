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
--   no pending failed save (§3.11: boxes, shop, daily and trainer are blocked while savePending; each caller turns
--   "savePending" into its own code: box.saving, trainer.paused, ...).
-- * Idempotency (§3.4): there is no generic ledger; each action keeps its own log. The duel ledger lives here:
--   grantDuelResult(p, matchId, outcome, result) appends {matchId, opp, result, at, full} to profile.duelLog (cap
--   Config.Data.caps.duelLog, oldest dropped), updates the same-pair record profile.samePair (§6.7, §12 #15:
--   DuelRewards.recordSamePair drops times older than the rolling window and adds now only for a fully rewarded
--   result), counts the duel stats and pays the Coins, all in one step, and a matchId already in duelLog is a no-op
--   (exactly once together with DuelService's single end, §12 #14; a replay never adds a second same-pair time). It
--   asks for a "soon" save. findLog / appendLog are the same helpers for the other logs (boxLog, shopLog, receipts,
--   Part 7).
-- * Squishies: grantSquishy(p, id, source, boxId?) adds an owned entry {at, src}; a duplicate from a box is refunded
--   a share of that box's price when DuplicatePolicy is "refund" (§6.5; spec 2026-10-12 §8: duplicateRefund(boxId) =
--   Pricing.duplicateRefund); a duplicate from any other source changes nothing.
-- * Reading: stats.coinsEarned / coinsSpent count every real grant and spend except the Studio-only "debug" reason,
--   so Studio tests never inflate them. Reading: stats.eliminations counts opponents eliminated in recorded results
--   (DuelService passes 0 or 1).
-- * The caller decides the save of a Coin grant or spend (§3.4: squeeze rides the autosave, boxes and the shop save
--   "now"); grantDuelResult asks for "soon" itself.
-- Failures come back as a short kind ("invalid", "reason", "notReady", "savePending", "notEnoughCoins"); CODES maps
-- the kinds that have a §2.10 code. Collaborators are reached through `deps` (useDeps in tests).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Pricing = require(Shared.Pricing)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local DuelRewards = require(script.Parent.Parent.Logic.DuelRewards)
local StateService = require(script.Parent.StateService)

-- Types

export type Failure = "invalid" | "reason" | "notReady" | "savePending" | "notEnoughCoins"

export type Deps = {
	data: StateService.DataPort,
	markDirty: (player: any, field: string) -> (),
	now: () -> number, -- os.time(): owned `at`, the same-pair record's times
	debugAllowed: () -> boolean, -- the Studio-only "debug" reason
}

-- What grantSquishy did. `refused` is set when nothing could change (no profile, unknown id, ...).
export type SquishyGrant = { added: boolean, refund: number, refused: Failure? }

-- The duel result as DuelService passes it (computed by Logic/DuelRewards, §6.7).
export type DuelResultInput = {
	coins: number, -- the reward (0 when not eligible)
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

-- Constants

local ECONOMY = Config.Economy
local MAX_COINS = ECONOMY.maxCoins
local DUEL_LOG_CAP = Config.Data.caps.duelLog
local MAX_DUEL_COINS = math.max(ECONOMY.DuelRewards.win, ECONOMY.DuelRewards.loss, ECONOMY.DuelRewards.draw)
local STATUS_READY = "ready"
local REASON_DEBUG = "debug"
local REASON_REFUND = "refund"
local SOURCE_BOX = "box"
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
-- (player, squishyId, source) when a squishy is added to a collection (not for duplicates).
EconomyService.SquishyGranted = Signal.new() :: Signal.Signal<Player, string, string>

-- §2.10 codes for the failure kinds that have one ("savePending" is the caller's: box.saving, trainer.paused, ...).
EconomyService.CODES = table.freeze({
	notReady = "data.notReady",
	notEnoughCoins = "economy.notEnoughCoins",
	invalid = "net.invalid",
})

-- Private

local log = Log.new("Economy")
local deps: Deps? = nil

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

-- The Coins a duplicate from this box is worth under the duplicate policy (§6.5; spec 2026-10-12 §8): a share of the
-- box's price (Pricing.duplicateRefund) when DuplicatePolicy is "refund"; 0 for an unknown box or the (unbuilt)
-- "exclude_owned" policy.
function EconomyService.duplicateRefund(boxId: unknown): number
	return Pricing.duplicateRefund(boxId)
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

-- Uses these collaborators (nil = the real ones; tests).
function EconomyService.useDeps(newDeps: Deps?)
	deps = newDeps
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

-- Adds a squishy to the collection (§6.5). Already owned: a box duplicate is refunded duplicateRefund(boxId) (reason
-- "refund"; `boxId` = the box it came from), any other source changes nothing. Returns {added, refund, refused?}.
-- Never yields.
function EconomyService.grantSquishy(player: any, id: string, source: string, boxId: string?): SquishyGrant
	if not Catalog.isValidId(id) or not OWNED_SOURCES[source] then
		log:warn(`grantSquishy: invalid id {tostring(id)} or source {tostring(source)}`)
		return { added = false, refund = 0, refused = "invalid" }
	end
	local added, refund, after = false, 0, 0
	local ok = edit(player, function(profile: any)
		local owned = profile.owned
		if type(owned) ~= "table" then
			owned = {}
			profile.owned = owned
		end
		if owned[id] ~= nil then
			local worth = if source == SOURCE_BOX then EconomyService.duplicateRefund(boxId) else 0
			if worth > 0 then
				refund = addCoinsTo(profile, worth, REASON_REFUND)
				after = profile.coins
			end
			return
		end
		local entry: Types.OwnedEntry = { at = getDeps().now(), src = source :: Types.OwnedSource }
		owned[id] = entry
		added = true
	end)
	if not ok then
		return { added = false, refund = 0, refused = "notReady" }
	end
	if added then
		getDeps().markDirty(player, "owned")
		EconomyService.SquishyGranted:fire(player, id, source)
	elseif refund > 0 then
		coinsChanged(player, after, refund, REASON_REFUND)
	end
	return { added = added, refund = refund, refused = nil }
end

-- Records one finished duel for a real player and pays its reward, exactly once per matchId (§3.4, §3.11, §6.7):
-- duelLog entry (capped), the same-pair record (a time only for a fully rewarded result), duelsPlayed /
-- duelsWon|Lost|Drawn / eliminations, Coins with reason duel_<outcome>, then a "soon" save. `outcome` is this player's
-- view (win / loss / draw). Never yields.
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
	local coins = result.coins
	if not isWhole(coins) or coins > MAX_DUEL_COINS then
		log:warn(`grantDuelResult: invalid reward {tostring(coins)} for match {matchId}; recorded without Coins`)
		coins = 0
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
			full = if coins > 0 then entry.full else false,
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
		if coins > 0 then
			grant.coins = addCoinsTo(profile, coins, reason)
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
