--!strict
-- BoxService (server only). DESIGN §2.3, §2.8 (BoxOpen, AckReveal), §3.4, §3.11, §6.4, §6.5, §6.10, §9.11, §12 #14 #17.
-- Server-side box opens: the server draws, charges, grants and saves; the client only plays the result (§9.11).
-- open(p, boxId, requestId) follows the §6.4 code block (one request per player at a time):
--   1. profile READY, else data.notReady;
--   2. boxLog.req == requestId -> the stored BoxResult (a replay: no charge, no new draw);
--   3. Boxes.paidById[boxId] (a paid box that passed the boot check), else net.invalid (unknown, free-only, disabled);
--   4. PolicyGateService.canBuyPaidRandom (eligible ONLY), else box.restricted (fail closed, §6.10);
--   5. ShutdownService.isClosing() or isRestartPending() -> box.paused;
--   6. a failed save pending -> box.saving (§3.11; EconomyService.trySpend's "savePending" maps to it too);
--   7. matched or in a match (InventoryService.isLocked) -> inventory.lockedInDuel;
--   8. every item owned (Boxes.isComplete) while Config.Economy.AllowOpenWhenComplete is false -> box.complete;
--   9. Config.Economy.MinSecondsBetweenOpens (2 s) since this player's last open -> net.rateLimited (Reading: only
--      opens that charged start the window: the rule keeps box writes inside the DataStore budget, §3.11, and a
--      refusal writes nothing);
--  10. EconomyService.trySpend(p, cost, "box") (economy.notEnoughCoins), BoxDraw.draw(box, rng) with the one server
--      Random.new() (never sent to clients), EconomyService.grantSquishy(p, id, "box") (a duplicate is refunded by
--      rarity there, reason "refund", §6.5), then one DataService.mutate appending the boxLog entry {req, box, squishy,
--      dup, refund, cost, at, seen = false} (cap Config.Data.caps.boxLog) and stats.boxesOpened + 1, and
--      markDirty("unseenReveals"). Nothing yields between the spend and the log append (one in-memory change).
--  11. DataService.saveNowAsync (awaited; the reveal's anticipation covers it) -> ok {squishyId, isDuplicate, refund,
--      savePending = not saved}. A failed save keeps the change in memory and blocks spends until a save succeeds.
-- Every refusal carries charged = false (nothing was taken). Reading: the BoxOpen remote is also one-in-flight in
-- NetService; open() refuses a second concurrent call itself (net.rateLimited) so direct callers are serialized too.
-- AckReveal(requestId) -> ackReveal(p, id): the boxLog entry with seen = false becomes seen = true (no economic
--   effect), markDirty("unseenReveals") and a "soon" save (Reading: DESIGN says only "no economic effect"; without a
--   save the reveal would replay after a crash). Accepts a GUID or "daily:<n>".
-- grantFree(p, boxId, openId) -> BoxResult?: the free Treat Box (day 7 of Daily Rewards, §6.9): a box that is not
--   paid, no cost, no policy check, idempotent by boxLog.req = openId ("daily:<dayIndex>"), the same draw, grant and
--   boxLog entry (cost 0, seen = false) and stats.boxesOpened + 1; it does NOT save (DailyRewardService saves "now"
--   with the claim). nil when the profile is not ready or the box is not a valid free box. Reading: a free box whose
--   items are all owned still opens (a duplicate refund; every outcome gives something).
-- Fail closed at boot (§2.6 "invalid box entries are disabled"): a box whose weights are not valid (BoxDraw.isValid),
--   that names an id missing from the Catalog, or (paid) whose cost is not a positive whole number or not above every
--   duplicate refund of its items (§6.5: opening can never earn Coins) is logged and never opened.
-- useDeps(overrides?) swaps the collaborators (tests: data port, save, economy, policy, flags, clocks, rng).
-- init() registers the BoxOpen and AckReveal handlers and never yields.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Pricing = require(Shared.Pricing)
local Types = require(Shared.Types)
local Validate = require(Shared.Util.Validate)
local Server = script.Parent.Parent
local BoxDraw = require(Server.Logic.BoxDraw)
local Services = script.Parent
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local InventoryService = require(Services.InventoryService)
local NetService = require(Services.NetService)
local PolicyGateService = require(Services.PolicyGateService)
local ShutdownService = require(Services.ShutdownService)
local StateService = require(Services.StateService)

-- Types

export type BoxResult = Types.BoxResult
type BoxDef = Boxes.BoxDef

export type Economy = {
	trySpend: (player: any, amount: number, reason: string) -> (boolean, string?),
	grantSquishy: (player: any, id: string, source: string) -> { added: boolean, refund: number, refused: string? },
	grantCoins: (player: any, amount: number, reason: string) -> (number, string?),
}

export type Deps = {
	data: StateService.DataPort,
	saveNow: (player: any) -> boolean, -- DataService.saveNowAsync (yields)
	economy: Economy,
	canBuyPaidRandom: (player: any) -> boolean, -- PolicyGateService: eligible only
	isClosing: () -> boolean,
	isRestartPending: () -> boolean,
	isLocked: (player: any) -> boolean, -- InventoryService.isLocked: matched or in a match
	markDirty: (player: any, field: string) -> (),
	now: () -> number, -- os.time: the boxLog `at`
	clock: () -> number, -- os.clock: MinSecondsBetweenOpens
	rng: Random, -- the one server Random (never sent to clients)
}

-- Constants

local REMOTE_OPEN = "BoxOpen"
local REMOTE_ACK = "AckReveal"
local REASON_BOX = "box"
local REASON_REFUND = "refund"
local SOURCE_BOX = "box"
local STATUS_READY = "ready"
local SAVE_SOON = "soon"
local FIELD_UNSEEN = "unseenReveals"
local FIELD_STATS = "stats"
local BOX_LOG_CAP = Config.Data.caps.boxLog
local MIN_SECONDS_BETWEEN = Config.Economy.MinSecondsBetweenOpens
local ALLOW_OPEN_WHEN_COMPLETE = Config.Economy.AllowOpenWhenComplete

local CODE_INVALID = "net.invalid"
local CODE_RATE_LIMITED = "net.rateLimited"
local CODE_NOT_READY = "data.notReady"
local CODE_RESTRICTED = "box.restricted"
local CODE_PAUSED = "box.paused"
local CODE_SAVING = "box.saving"
local CODE_COMPLETE = "box.complete"
local CODE_LOCKED = "inventory.lockedInDuel"
local CODE_NOT_ENOUGH = "economy.notEnoughCoins"
local CODE_GENERIC = "error.generic"

-- Module table

local BoxService = {}

-- Private

local log = Log.new("Box")
local deps: Deps? = nil
local serverRng: Random? = nil
local busy: { [any]: boolean } = {}
local lastOpenAt: { [any]: number } = {}
local disabled: { [string]: string } = {} -- boxId -> why it is never opened (boot check)

-- The one server Random (§3.11, §6.4), created on first use.
local function getServerRng(): Random
	local existing = serverRng
	if existing ~= nil then
		return existing
	end
	local created = Random.new()
	serverRng = created
	return created
end

local function defaultDeps(): Deps
	return {
		data = StateService.dataPort(),
		saveNow = function(player: any): boolean
			return DataService.saveNowAsync(player)
		end,
		economy = EconomyService :: any,
		canBuyPaidRandom = PolicyGateService.canBuyPaidRandom,
		isClosing = ShutdownService.isClosing,
		isRestartPending = ShutdownService.isRestartPending,
		isLocked = InventoryService.isLocked,
		markDirty = function(player: any, field: string)
			StateService.markDirty(player, field)
		end,
		now = os.time,
		clock = os.clock,
		rng = getServerRng(),
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

-- A refusal before anything was charged (§2.10: "No Coins were spent" only when charged = false).
local function refuse(reason: string): any
	return NetService.err(reason, false)
end

local function userIdOf(player: any): string
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok then tostring(id) else "?"
end

local function resultFrom(entry: any, savePending: boolean): BoxResult
	return {
		squishyId = if type(entry.squishy) == "string" then entry.squishy else "",
		isDuplicate = entry.dup == true,
		refund = if type(entry.refund) == "number" then entry.refund else 0,
		savePending = savePending,
	}
end

-- Draws, grants and logs one box result for a player whose profile is ready. Never yields. Returns the boxLog entry,
-- or nil when the draw or the grant failed (nothing was granted; the caller gives back what it took).
local function drawAndGrant(player: any, box: BoxDef, req: string, cost: number): Types.BoxLogEntry?
	local d = getDeps()
	local drawn, id = pcall(BoxDraw.draw, box, d.rng)
	if not drawn or not Catalog.isValidId(id) then
		log:error(`box {box.id}: the draw failed ({tostring(id)})`)
		return nil
	end
	local grant = d.economy.grantSquishy(player, id, SOURCE_BOX)
	if grant.refused ~= nil then
		log:error(`box {box.id}: {id} could not be granted to user {userIdOf(player)} ({grant.refused})`)
		return nil
	end
	local entry: Types.BoxLogEntry = {
		req = req,
		box = box.id,
		squishy = id,
		dup = not grant.added,
		refund = grant.refund,
		cost = cost,
		at = d.now(),
		seen = false,
	}
	local logged = d.data.mutate(player, function(profile: any): any
		local list = profile.boxLog
		if type(list) ~= "table" then
			list = {}
			profile.boxLog = list
		end
		EconomyService.appendLog(list, entry, BOX_LOG_CAP)
		local stats = profile.stats
		if type(stats) ~= "table" then
			stats = {}
			profile.stats = stats
		end
		local opened = stats.boxesOpened
		stats.boxesOpened = (if type(opened) == "number" and opened == opened then opened else 0) + 1
		return nil
	end)
	if not logged then
		-- Cannot happen in the same step as a successful grant (mutate accepted it a moment ago).
		log:error(`box {box.id}: the boxLog entry for user {userIdOf(player)} could not be written`)
	end
	d.markDirty(player, FIELD_UNSEEN)
	d.markDirty(player, FIELD_STATS)
	return entry
end

local function openLocked(player: any, boxId: unknown, requestId: unknown): any
	local d = getDeps()
	local request = Validate.requestId(requestId)
	if request == nil then
		return refuse(CODE_INVALID)
	end
	-- 1-2: profile and replay
	local data = d.data
	local profile = data.getProfile(player)
	if type(profile) ~= "table" or data.status(player) ~= STATUS_READY then
		return refuse(CODE_NOT_READY)
	end
	local prior = EconomyService.findLog(profile.boxLog, "req", request)
	if prior ~= nil then
		return NetService.ok(resultFrom(prior, data.savePending(player)))
	end
	-- 3-9: the box and the gates (§6.4 order)
	local box: BoxDef? = if type(boxId) == "string" then Boxes.paidById[boxId] else nil
	if box == nil or disabled[box.id] ~= nil then
		return refuse(CODE_INVALID)
	end
	if not d.canBuyPaidRandom(player) then
		return refuse(CODE_RESTRICTED)
	end
	if d.isClosing() or d.isRestartPending() then
		return refuse(CODE_PAUSED)
	end
	if data.savePending(player) then
		return refuse(CODE_SAVING)
	end
	if d.isLocked(player) then
		return refuse(CODE_LOCKED)
	end
	if not ALLOW_OPEN_WHEN_COMPLETE and Boxes.isComplete(box.id, profile.owned) then
		return refuse(CODE_COMPLETE)
	end
	local last = lastOpenAt[player]
	if last ~= nil and d.clock() - last < MIN_SECONDS_BETWEEN then
		return refuse(CODE_RATE_LIMITED)
	end
	-- 10: from the spend to the log append nothing yields (§3.11)
	local cost = box.cost :: number
	local spent, failure = d.economy.trySpend(player, cost, REASON_BOX)
	if not spent then
		if failure == "notEnoughCoins" then
			return refuse(CODE_NOT_ENOUGH)
		elseif failure == "savePending" then
			return refuse(CODE_SAVING)
		elseif failure == "notReady" then
			return refuse(CODE_NOT_READY)
		end
		return refuse(CODE_GENERIC)
	end
	lastOpenAt[player] = d.clock()
	local entry = drawAndGrant(player, box, request, cost)
	if entry == nil then
		d.economy.grantCoins(player, cost, REASON_REFUND) -- never keep Coins for nothing
		return refuse(CODE_GENERIC)
	end
	-- 11: the "now" save, awaited
	local saved = d.saveNow(player)
	log:info(
		string.format(
			"open user=%s box=%s squishy=%s dup=%s refund=%d saved=%s",
			userIdOf(player),
			box.id,
			entry.squishy,
			tostring(entry.dup),
			entry.refund,
			tostring(saved)
		)
	)
	return NetService.ok(resultFrom(entry, not saved))
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Replaces collaborators (fields not given keep their defaults; nil restores every default) and forgets the per-player
-- state (tests).
function BoxService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
	busy = {}
	lastOpenAt = {}
end

-- BoxOpen (§6.4). Returns NetService.ok(BoxResult) or NetService.err(code, false). Yields only for the "now" save.
function BoxService.open(player: any, boxId: unknown, requestId: unknown): any
	if busy[player] then
		return refuse(CODE_RATE_LIMITED)
	end
	busy[player] = true
	local ok, result = pcall(openLocked, player, boxId, requestId)
	busy[player] = nil
	if not ok then
		log:error("open failed:", result)
		return NetService.err(CODE_GENERIC) -- whether anything was charged is unknown here: no `charged`
	end
	return result
end

-- AckReveal (§2.8, §6.4): marks the boxLog entry `requestId` seen. Returns true when an unseen entry became seen.
function BoxService.ackReveal(player: any, requestId: unknown): boolean
	local req = Validate.ackRevealId(requestId)
	if req == nil then
		return false
	end
	local d = getDeps()
	local changed = false
	local ok = d.data.mutate(player, function(profile: any): any
		local entry = EconomyService.findLog(profile.boxLog, "req", req)
		if entry ~= nil and entry.seen == false then
			entry.seen = true
			changed = true
		end
		return nil
	end)
	if not ok or not changed then
		return false
	end
	d.markDirty(player, FIELD_UNSEEN)
	d.data.requestSave(player, SAVE_SOON)
	return true
end

-- The free Treat Box (§6.9): see the header. Returns the BoxResult (the stored one for a replay) or nil.
function BoxService.grantFree(player: any, boxId: string, openId: string): BoxResult?
	local box = Boxes.get(boxId)
	if box == nil or box.paid or disabled[box.id] ~= nil then
		log:warn(`grantFree: {tostring(boxId)} is not a free box that can be granted`)
		return nil
	end
	local req = Validate.ackRevealId(openId)
	if req == nil then
		log:warn(`grantFree: invalid open id {tostring(openId)}`)
		return nil
	end
	local d = getDeps()
	local data = d.data
	local profile = data.getProfile(player)
	if type(profile) ~= "table" or data.status(player) ~= STATUS_READY then
		return nil
	end
	local prior = EconomyService.findLog(profile.boxLog, "req", req)
	if prior ~= nil then
		return resultFrom(prior, data.savePending(player))
	end
	local entry = drawAndGrant(player, box, req, 0)
	if entry == nil then
		return nil
	end
	log:info(`free user={userIdOf(player)} box={box.id} open={req} squishy={entry.squishy} dup={tostring(entry.dup)}`)
	return resultFrom(entry, data.savePending(player))
end

-- Checks every box definition (fail closed, see the header). Returns the disabled box ids and why (tests, boot).
function BoxService.checkBoxes(): { [string]: string }
	local found: { [string]: string } = {}
	for _, box in Boxes.list() do
		if not BoxDraw.isValid(box) then
			found[box.id] = `weights do not sum to {Boxes.WeightTotal}`
			continue
		end
		for _, item in box.items do
			if not Catalog.isValidId(item.id) then
				found[box.id] = `{item.id} is not in the Catalog`
				break
			end
		end
		if found[box.id] == nil and box.paid then
			local cost = box.cost
			if
				type(cost) ~= "number"
				or cost ~= cost
				or cost <= 0
				or cost > Config.Economy.maxCoins
				or math.floor(cost) ~= cost
			then
				found[box.id] = "cost is not a positive whole number"
			else
				for _, item in box.items do
					local def = Catalog.get(item.id)
					if def ~= nil and Pricing.duplicateRefund(def.rarity) >= cost then
						found[box.id] = `the duplicate refund of {item.id} is not below the cost {cost}`
						break
					end
				end
			end
		end
	end
	return found
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function BoxService.init()
	disabled = BoxService.checkBoxes()
	for id, why in disabled do
		log:warn(`box {id} is disabled: {why}`)
	end
	NetService.onInvoke(REMOTE_OPEN, function(player: Player, boxId: any, requestId: any): any
		return BoxService.open(player, boxId, requestId)
	end)
	NetService.on(REMOTE_ACK, function(player: Player, requestId: any)
		BoxService.ackReveal(player, requestId)
	end)
end

function BoxService.playerRemoving(player: Player)
	busy[player] = nil
	lastOpenAt[player] = nil
end

return BoxService
