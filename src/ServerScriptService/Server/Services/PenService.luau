--!strict
-- PenService (server only). Pens3 phase 1 (work/pens3/PLAN.md, 2026-10-17): the pen of every player in the server pays
-- its Coins every second, and the one pen remote buys only the caller's own next spot (no remote takes a base, plot
-- or player id). Built from CapsuleService's patterns (its tick, pay, spend and buy; useDeps / reset; sessions).
-- * Config.Economy.Pen (Config/Pen) is checked by Config/ValidatePen in init: any problem stops with an error (the pen
--   is the Coin source of the game; the shipped table is pinned by ValidatePen_Test).
-- * The tick (start: every Pen.tickSeconds, step(dt) with the time that really passed): for each player in the server
--   with a READY profile, PenMath.payStep(carry, PenMath.rate(pen), dt) (at most Pen.maxTickSeconds of time at once)
--   and ONE EconomyService.grantCoins(p, coins, "pen") per player and tick, each player in its own pcall. The pen pays
--   no Grip. The carry (a part of a Coin) lives in this session only: it starts at 0 on join, time while not ready or
--   out of the server never pays here (the time away pays once on the next load, below).
-- * PenBuySpot(expectedPrice) (RF; Config.Net: 1 a second, one in flight), refusals in the CapsuleUnlock order: (1)
--   expectedPrice not whole Coins -> net.invalid; (2) no READY profile -> data.notReady; (3) PenMath.buyDecision ->
--   pen.max / pen.priceChanged (the price is compared, never charged); (4) a pending failed save, the server closing,
--   a restart pending, or less than Pen.buyCooldownSeconds since this player's last buy -> pen.paused; (5)
--   SD_DuelPhase ~= "" -> inventory.lockedInDuel; (6) EconomyService.trySpend(p, price, "pen") (else
--   economy.notEnoughCoins; "savePending" -> pen.paused). Then spots + 1 through DataService.mutate, nothing yielding
--   in between, the base redrawn and the `pen` field sent (BaseService.refresh + StateService.markDirty, deps.showPen),
--   a log line, and the awaited "now" save before the reply ok({pen, charged = true, savePending}). Every refusal
--   carries charged = false and writes nothing.
-- * EconomyService.SquishyGranted (a new squishy: its pen item was added in that grant's own step) redraws the base
--   and sends the `pen` field (showPen).
-- * Pens3 phase 4, coins while away: on DataService.Loaded, EconomyService.grantAway pays 5% of the pen's rate at the
--   last save for every second since it (PenMath.awayCoins; no limit, no idle rule) and stamps lastSeenAt in the same
--   step, so a second Loaded of the same profile pays nothing. A gift that paid goes to the owner's client as the
--   session field awayGift {coins, seconds} (StateService), which shows it once. This handler runs after
--   GripService's (it connects in an earlier init), whose welcome toasts read the loaded lastSeenAt.
-- * Pens3 phase 5 (copies, D1:254-258): a bought spot makes room in the Toy Box, so the buy drops queued gifts in
--   (EconomyService.dropGifts) before the reply's pen is copied; a load drops them in too. The free Frog gift
--   (Pen.frogGift, SIM:226): the tick asks EconomyService.grantGift(p, "frog", kind) once a session, frogGift.seconds
--   after the player joined, while the profile is READY; grantGift keeps it once per account (profile.gifts.frog).
--   Reading: "minute 3 of the first play" is minute 3 of the first session that lasts that long (play time is not
--   saved).
-- * Pens3 phase 6 (the pen screen; every squishy has a `slot`, 0 = the Toy Box, and a `locked` flag):
--   - PenPlace(itemId, slot) (RF; Config.Net: 2 a second, burst 3, one in flight) moves one of the caller's own
--     squishies (no remote takes a base, plot or player id), refusals in the PenBuySpot order: (1) itemId or slot not
--     a whole number -> net.invalid; (2) data.notReady; (3) PenMath.placeDecision -> net.invalid / inventory.notOwned
--     (no such item in the caller's pen) / pen.spotClosed (a spot not bought) / inventory.full (put away into a full
--     Toy Box); the same place -> ok, nothing written; (4) a pending failed save, closing or a restart pending ->
--     pen.changePaused; (5) SD_DuelPhase ~= "" -> inventory.lockedInDuel. Then one mutate (the item to its slot; an
--     occupied spot's squishy to the mover's old one: a swap; slot 0 = put away), the base redrawn and the pen sent
--     (showPen), a log line, a "soon" save and the reply ok({pen, charged = false, savePending}). Reading: a "soon"
--     save, not the plan's awaited "now": no Coins move, a crash loses only the placement, and an awaited write per
--     swap would wait on the DataStore's 6 s rule for one key on every quick second swap (CapsuleSet's choice too).
--   - PenLock(itemId, locked) (RF, same limits): (1) itemId whole and locked a boolean, else net.invalid; (2)
--     data.notReady; (3) inventory.notOwned; already so -> ok, nothing written; (4) pen.changePaused; (5)
--     inventory.lockedInDuel; then one mutate, the pen field sent (sendPen: nothing on the plot shows a lock), the
--     awaited "now" save (a lock guards against selling from phase 7, so it is written before the reply) and the
--     reply ok({pen, charged = false, savePending}). A lock never stops the player moving the squishy.
--   - A bought spot takes the best unlocked Toy Box squishy (PenMath.bestToyBox) in the buy's own mutate, as a new
--     capsule took the best spare squishy (CapsuleService); a placed squishy never moves on its own.
--   Every refusal carries charged = false and writes nothing.
-- * Pens3 phase 7 (selling, D1:217-225, V3:164; the 10-minute buy-back), every remote the PenPlace shape (RF;
--   Config.Net: 2 a second, burst 3, one in flight; no remote takes a base, plot or player id):
--   - SellItems(ids, requestId) / SellAll(requestId): (1) the ids (Validate.itemIds) or the requestId bad ->
--     net.invalid; (2) data.notReady; (3) a buyBack entry with this requestId: the sale was made (a retry) -> ok with
--     what it paid, nothing changes (never sells twice); (4) the ids (SellAll: PenMath.sellAllIds, none ->
--     pen.nothingToSell) through PenMath.sellDecision -> net.invalid / inventory.notOwned / pen.sellStarter /
--     pen.locked / pen.lastCopy; (5) pen.changePaused; (6) inventory.lockedInDuel. Then ONE mutate: the squishies leave
--     the pen, each becomes a buyBack entry {item (bare: its coating goes to profile.bag, V2:382; slot 0, unlocked),
--     price (its sellPrice), at (os.time), req}, and the list keeps only live entries (PenMath.liveBuyBack: the expired
--     go, the oldest past buyBackMax fall off). Then ONE grantCoins(p, the total, "sell"); if maxCoins clamped it, the
--     entries of this sale shrink (newest first) to what was really paid, so a buy-back never charges more than the
--     sale paid. Then the base and the pen (showPen), the buyBack field (sendBuyBack), a log line, the awaited "now"
--     save and the reply ok({pen, coins, charged = false, savePending}). Reading: Sell All sells from the Toy Box only
--     (the pen's walking squishies earn; a player sells one of them by picking it).
--   - BuyBack(itemId): (1) not whole -> net.invalid; (2) data.notReady; (3) PenMath.buyBackDecision ->
--     pen.buyBackGone (no live entry of that sold id: bought back already, expired, never sold) / inventory.full; (4)
--     a pending failed save, closing or a restart -> pen.paused; (5) inventory.lockedInDuel; (6) trySpend(p, the
--     entry's price, "sell") (economy.notEnoughCoins; a price of 0 spends nothing). Then ONE mutate: the entry leaves
--     buyBack and its squishy comes back bare with a fresh id (pen.nextId) in the first free spot, else the Toy Box,
--     unlocked; showPen, sendBuyBack, the awaited save, ok({pen, charged = price > 0, savePending}). The entry goes in
--     the same step as the spend, so a retry finds nothing: never charged twice.
-- * Pens3 phase 8 (fusion, D1:227-232, V2:232): Fuse(a, b, c): (1) not 3 whole numbers -> net.invalid; (2)
--   data.notReady; (3) PenMath.fuseDecision -> net.invalid / inventory.notOwned / pen.locked / pen.fuseMismatch /
--   pen.fuseTop; (4) pen.changePaused; (5) inventory.lockedInDuel. Then ONE mutate: the keeper (the highest level)
--   takes the next form at its level with no coating, in its own slot; the other two leave; every input's coating goes
--   to profile.bag; no luck, no Coins. showPen (the look changes), the awaited save, ok({pen, id, charged = false,
--   savePending}).
-- Every profile write goes through DataService.mutate (the data port).--   savePending}).
-- * Pens3 phase 9 (food and levels, V2:214-224; Config.Economy.Food, checked by Config/ValidateFood in init), every
--   remote the PenPlace shape (RF; Config.Net: 2 a second, burst 3, one in flight; no remote takes a base, plot or
--   player id); the level cap is PenMath.levelCap() (10 until phase 13's biomes):
--   - BuyFood(foodId, count, expectedPrice, requestId): (1) foodId not a string, count not whole, expectedPrice not
--     whole Coins or the requestId not a GUID -> net.invalid; (2) data.notReady; (3) this session's last bought
--     requestId: it was bought (a retry whose answer never arrived) -> ok, charged = true as first answered, nothing
--     changes (never buys twice); (4) PenMath.buyFoodDecision -> net.invalid (not a food, count not in [1, maxBuy]) /
--     food.notYet (its biome is not reached) / food.full (past maxPieces) / pen.priceChanged (the price is compared,
--     never charged); (5)-(6) spend(price, "food"): pen.paused / inventory.lockedInDuel / economy.notEnoughCoins. Then
--     ONE mutate (the pieces added; a write that fails gives the spend back), the food field sent (sendFood), a log
--     line, the awaited "now" save, ok({pen, food, levels = 0, charged = true, savePending}).
--   - Feed(itemId, requestId): (1) net.invalid; (2) data.notReady; (3) this session's last fed requestId -> ok, nothing
--     changes (never feeds twice); (4) PenMath.feedDecision -> net.invalid / inventory.notOwned (the caller's pen or
--     Toy Box only) / pen.maxLevel / food.notEnough; (5) pen.changePaused; (6) inventory.lockedInDuel. Then ONE mutate
--     (level + 1, its step's pieces gone), showPen (the coin label and the card show the level: the pen's rate, the
--     awayRate DataService stamps and the squeeze value all follow PenMath.itemRate's levelGain), sendFood, a "soon"
--     save and ok({pen, food, levels = 1, charged = false, savePending}).
--   - FeedAll(): (1) none (no arguments); (2) data.notReady; (3) PenMath.feedAllPlan: the placed squishies only (the
--     Toy Box never: an owner decision), the weakest first, a level at a time, until the food runs out; nothing to feed
--     -> pen.nothingToFeed (so a retry, which finds nothing left, never feeds twice); (4) pen.changePaused; (5)
--     inventory.lockedInDuel. Then ONE mutate (every level, every food used), showPen, sendFood, a "soon" save and
--     ok({pen, food, levels = the levels gained, charged = false, savePending}).
--   Reading: Feed / FeedAll save "soon", like PenPlace: no Coins move (food and levels are in the same profile, so a
--   crash loses both together), and an awaited write per tap would wait on the DataStore's 6 s rule for one key while
--   a kid taps FEED again and again. A buy moves Coins: awaited. Every refusal carries charged = false, writes nothing.
-- * Pens3 phase 11 (the shelf rows + the TOP spot, V3:144-151): PenBuyShelf(expectedPrice) (RF; Config.Net: 1 a
--   second, one in flight), PenBuySpot's shape and refusal order: (1) expectedPrice not whole Coins -> net.invalid; (2)
--   data.notReady; (3) PenMath.shelfDecision -> net.invalid (no shelfRows: never after sanitize) / pen.shelfMax /
--   pen.priceChanged (compared, never charged); (4) pen.paused (a pending failed save, closing, a restart, or less than
--   Pen.buyCooldownSeconds since this player's last pen or shelf buy); (5) inventory.lockedInDuel; (6) the "pen" spend
--   (economy.notEnoughCoins). Then ONE mutate: shelfRows = the next row (or top = true), and each spot it opens takes
--   the best unlocked Toy Box squishy (PenMath.bestToyBox into PenMath.freeSlot, as a pen spot does); queued gifts
--   dropped in, the base redrawn and the pen sent (showPen), a log line, the awaited "now" save and ok({pen, charged =
--   true, savePending}). Every refusal carries charged = false and writes nothing. The shelf's and the TOP spot's
--   squishies are paid by the tick with the pen's (PenMath.rate counts every placed squishy).
-- Every profile write goes through DataService.mutate (the data port). Dependencies are injectable (useDeps) so unit
-- tests run with fake profiles and players (plain tables); init() never yields; playerAdded / playerRemoving never
-- yield.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local PenMath = require(Shared.PenMath)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)
local ValidateFood = require(Shared.Config.ValidateFood) -- pens3 phase 9
local ValidatePen = require(Shared.Config.ValidatePen)
local Validate = require(Shared.Util.Validate)

local Services = script.Parent
local BaseService = require(Services.BaseService)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local NetService = require(Services.NetService)
local ShutdownService = require(Services.ShutdownService)
local StateService = require(Services.StateService)

-- Types

export type Deps = {
	statusOf: (player: any) -> string, -- DataService status: "loading" | "ready" | "offline" | "readonly"
	profileOf: (player: any) -> any, -- the profile table in memory (or nil); read only
	mutate: (player: any, fn: (profile: any) -> any) -> (boolean, any), -- DataService.mutate (READY sessions only)
	savePending: (player: any) -> boolean,
	isClosing: () -> boolean,
	isRestartPending: () -> boolean,
	duelPhaseOf: (player: any) -> string, -- SD_DuelPhase ("" outside a match)
	trySpend: (player: any, amount: number, reason: string) -> (boolean, string?),
	grantCoins: (player: any, amount: number, reason: string) -> number, -- the Coins really added
	saveNow: (player: any) -> boolean, -- DataService.saveNowAsync (yields)
	clock: () -> number, -- os.clock: the buy cooldown
	-- BaseService.refresh and StateService.markDirty(p, "pen"): the player's base and client show their pen again
	showPen: (player: any) -> (),
	grantAway: (player: any) -> (number, number), -- EconomyService.grantAway: (Coins added, seconds counted)
	setAwayGift: (player: any, gift: Types.AwayGift) -> (), -- StateService.setSessionField(p, "awayGift", gift)
	dropGifts: (player: any) -> number, -- pens3 phase 5: EconomyService.dropGifts (how many dropped in)
	grantGift: (player: any, key: string, kind: string) -> boolean, -- pens3 phase 5: EconomyService.grantGift
	requestSave: (player: any, reason: string) -> (), -- pens3 phase 6: DataService.requestSave (never yields)
	sendPen: (player: any) -> (), -- pens3 phase 6: StateService.markDirty(p, "pen") alone (a lock: nothing to redraw)
	now: () -> number, -- pens3 phase 7: os.time (a buy-back entry's `at`)
	sendBuyBack: (player: any) -> (), -- StateService.markDirty(p, "buyBack")
	sendFood: (player: any) -> (), -- pens3 phase 9: StateService.markDirty(p, "food")
}

-- What the remote answers: NetService.ok(Types.PenResult) or NetService.err(reason, false).
export type Reply = { ok: boolean, data: Types.PenResult?, reason: string?, charged: boolean? }

type Session = {
	carry: number, -- the part of a Coin the tick owes (PenMath.payStep)
	boughtAt: number, -- deps.clock() of the last spot bought (the cooldown)
	joinedAt: number, -- pens3 phase 5: deps.clock() at playerAdded (the Frog gift's time)
	frogAsked: boolean, -- pens3 phase 5: the Frog gift was asked for this session
	foodReq: string?, -- pens3 phase 9: the requestId of the last BuyFood that charged (a retry replays)
	feedReq: string?, -- the requestId of the last Feed that levelled (a retry replays)
}

-- Constants

local PEN = Config.Economy.Pen
local FROG_KEY = "frog" -- profile.gifts.frog
local COIN_REASON = "pen"
local REMOTE_BUY = "PenBuySpot"
local REMOTE_BUY_SHELF = "PenBuyShelf" -- pens3 phase 11
local REMOTE_PLACE = "PenPlace" -- pens3 phase 6
local REMOTE_LOCK = "PenLock"
local SAVE_SOON = "soon"
local FIELD_PEN = "pen"
local FIELD_AWAY_GIFT = "awayGift"
local STATUS_READY = "ready"
local ATTR_PHASE = "SD_DuelPhase"
local CODE_INVALID = "net.invalid"
local CODE_NOT_READY = "data.notReady"
local CODE_PAUSED = "pen.paused"
local CODE_IN_DUEL = "inventory.lockedInDuel"
local CODE_NOT_ENOUGH = "economy.notEnoughCoins"
local CODE_CHANGE_PAUSED = "pen.changePaused" -- pens3 phase 6
local CODE_NOT_OWNED = "inventory.notOwned"
local CODE_NOTHING = "pen.nothingToSell" -- pens3 phase 7
local REASON_SELL = "sell"
local REASON_REFUND = "refund"
local REMOTE_SELL = "SellItems"
local REMOTE_SELL_ALL = "SellAll"
local REMOTE_BUY_BACK = "BuyBack"
local REMOTE_FUSE = "Fuse" -- pens3 phase 8
local FIELD_BUY_BACK = "buyBack"
local REMOTE_BUY_FOOD = "BuyFood" -- pens3 phase 9
local REMOTE_FEED = "Feed"
local REMOTE_FEED_ALL = "FeedAll"
local FIELD_FOOD = "food"
local REASON_FOOD = "food"
local CODE_NOTHING_TO_FEED = "pen.nothingToFeed"

-- Module table

local PenService = {}

-- Private

local log = Log.new("Pen")
local sessions: { [any]: Session } = {}
local loopThread: thread? = nil

local function userIdOf(player: any): number
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok and type(id) == "number" then id else 0
end

local function duelPhaseAttribute(player: any): string
	if typeof(player) ~= "Instance" then
		return ""
	end
	local phase = (player :: Instance):GetAttribute(ATTR_PHASE)
	return if type(phase) == "string" then phase else ""
end

local function defaultDeps(): Deps
	return {
		statusOf = function(player: any): string
			return StateService.dataPort().status(player)
		end,
		profileOf = function(player: any): any
			return StateService.dataPort().getProfile(player)
		end,
		mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
			return StateService.dataPort().mutate(player, fn)
		end,
		savePending = function(player: any): boolean
			return StateService.dataPort().savePending(player)
		end,
		isClosing = function(): boolean
			return ShutdownService.isClosing()
		end,
		isRestartPending = function(): boolean
			return ShutdownService.isRestartPending()
		end,
		duelPhaseOf = duelPhaseAttribute,
		trySpend = function(player: any, amount: number, reason: string): (boolean, string?)
			return EconomyService.trySpend(player, amount, reason)
		end,
		grantCoins = function(player: any, amount: number, reason: string): number
			local added = EconomyService.grantCoins(player, amount, reason)
			return added
		end,
		saveNow = function(player: any): boolean
			return DataService.saveNowAsync(player)
		end,
		clock = os.clock,
		showPen = function(player: any)
			BaseService.refresh(player)
			StateService.markDirty(player, FIELD_PEN)
		end,
		grantAway = function(player: any): (number, number)
			return EconomyService.grantAway(player)
		end,
		setAwayGift = function(player: any, gift: Types.AwayGift)
			StateService.setSessionField(player, FIELD_AWAY_GIFT, gift)
		end,
		dropGifts = function(player: any): number
			return EconomyService.dropGifts(player)
		end,
		grantGift = function(player: any, key: string, kind: string): boolean
			return EconomyService.grantGift(player, key, kind)
		end,
		requestSave = function(player: any, reason: string)
			DataService.requestSave(player, reason :: any)
		end,
		sendPen = function(player: any)
			StateService.markDirty(player, FIELD_PEN)
		end,
		now = os.time,
		sendBuyBack = function(player: any)
			StateService.markDirty(player, FIELD_BUY_BACK)
		end,
		sendFood = function(player: any)
			StateService.markDirty(player, FIELD_FOOD)
		end,
	}
end

local deps: Deps = defaultDeps()

-- The pen of a READY profile (the only state that pays or changes), or nil.
local function readyPen(player: any): Types.PenState?
	if deps.statusOf(player) ~= STATUS_READY then
		return nil
	end
	local profile = deps.profileOf(player)
	local pen = if type(profile) == "table" then profile.pen else nil
	return if type(pen) == "table" then pen else nil
end

-- One tick of one player's pen (see the header).
local function pay(player: any, session: Session, dt: number)
	local pen = readyPen(player)
	if pen == nil then
		return
	end
	local coins, carry = PenMath.payStep(session.carry, PenMath.rate(pen), dt)
	session.carry = carry
	if coins > 0 then
		deps.grantCoins(player, coins, COIN_REASON)
	end
	-- Pens3 phase 5: the Frog gift, once a session (see the header).
	if not session.frogAsked and deps.clock() - session.joinedAt >= PEN.frogGift.seconds then
		session.frogAsked = true
		if deps.grantGift(player, FROG_KEY, PEN.frogGift.kind) then
			log:info(`user {userIdOf(player)} got the {PEN.frogGift.kind} gift`)
		end
	end
end

-- (4)-(6) of a buy: paused, in a duel, then the spend. Returns a refusal code, or nil once the Coins are taken. Pens3
-- phase 7: a buy-back spends with its own reason and no spot cooldown; a price of 0 spends nothing.
local function spend(player: any, price: number, reason: string, cooldown: boolean): string?
	local session = sessions[player]
	local cooling = cooldown and session ~= nil and deps.clock() - session.boughtAt < PEN.buyCooldownSeconds
	if cooling or deps.savePending(player) or deps.isClosing() or deps.isRestartPending() then
		return CODE_PAUSED
	end
	if deps.duelPhaseOf(player) ~= "" then
		return CODE_IN_DUEL
	end
	if price <= 0 then
		return nil
	end
	local spent, why = deps.trySpend(player, price, reason)
	if spent then
		return nil
	end
	return if why == "savePending"
		then CODE_PAUSED
		elseif why == "notReady" then CODE_NOT_READY
		elseif why == "notEnoughCoins" then CODE_NOT_ENOUGH
		else CODE_INVALID
end

-- Pens3 phase 6: (4)-(5) of a place or a lock (see the header). A refusal code, or nil.
local function changeRefused(player: any): string?
	if deps.savePending(player) or deps.isClosing() or deps.isRestartPending() then
		return CODE_CHANGE_PAUSED
	end
	if deps.duelPhaseOf(player) ~= "" then
		return CODE_IN_DUEL
	end
	return nil
end

-- Pens3 phase 6: the reply data of a place or a lock (no Coins move).
local function penResult(player: any, savePending: boolean): Types.PenResult
	return { pen = TableUtil.deepCopy(deps.profileOf(player).pen), charged = false, savePending = savePending }
end

-- Public: the tick ------------------------------------------------------------------------------------------------

-- Pays every session's pen for `dt` seconds (the loop calls it every tick).
function PenService.step(dt: number)
	for player, session in sessions do
		local ok, err = pcall(function(): any
			pay(player, session, dt)
			return nil
		end)
		if not ok then
			log:error(`pen tick failed for user {userIdOf(player)}:`, err)
		end
	end
end

-- Public: the remote (see the header for the order of the checks) ----------------------------------------------------

function PenService.buy(player: any, expectedPrice: any): Reply
	if Validate.coins(expectedPrice) == nil then
		return NetService.err(CODE_INVALID, false)
	end
	local pen = readyPen(player)
	if pen == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local decision, refused = PenMath.buyDecision(pen, expectedPrice)
	if decision == nil then
		return NetService.err(refused or CODE_INVALID, false)
	end
	local spot, price = decision.spot, decision.price
	local spendRefused = spend(player, price, COIN_REASON, true)
	if spendRefused ~= nil then
		return NetService.err(spendRefused, false)
	end
	local written = deps.mutate(player, function(profile: any): boolean
		profile.pen.spots = math.max(profile.pen.spots, spot)
		local best = PenMath.bestToyBox(profile.pen) -- pens3 phase 6: the new spot takes the best Toy Box squishy
		if best ~= nil then
			best.slot = PenMath.freeSlot(profile.pen)
		end
		return true
	end)
	if not written then
		-- Cannot happen without a yield after the spend (the session was ready a moment ago); logged loudly.
		log:error(`user {userIdOf(player)}: pen spot {spot} was paid ({price} Coins) but could not be written`)
		return NetService.err(CODE_NOT_READY, false)
	end
	local session = sessions[player]
	if session ~= nil then
		session.boughtAt = deps.clock()
	end
	log:info(`user {userIdOf(player)} bought pen spot {spot} for {price} Coins`)
	deps.dropGifts(player) -- pens3 phase 5: the new spot makes room for a waiting gift
	deps.showPen(player)
	local data: Types.PenResult = {
		pen = TableUtil.deepCopy(deps.profileOf(player).pen), -- copied before the save yields
		charged = true,
		savePending = false,
	}
	data.savePending = not deps.saveNow(player)
	return NetService.ok(data)
end

-- Pens3 phase 11: the next shelf row, then the TOP spot (see the header for the order of the checks).
function PenService.buyShelf(player: any, expectedPrice: any): Reply
	if Validate.coins(expectedPrice) == nil then
		return NetService.err(CODE_INVALID, false)
	end
	local pen = readyPen(player)
	if pen == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local decision, refused = PenMath.shelfDecision(pen, expectedPrice)
	if decision == nil then
		return NetService.err(refused or CODE_INVALID, false)
	end
	local price = decision.price
	local spendRefused = spend(player, price, COIN_REASON, true)
	if spendRefused ~= nil then
		return NetService.err(spendRefused, false)
	end
	local written = deps.mutate(player, function(profile: any): boolean
		if decision.top then
			profile.pen.top = true
		else
			profile.pen.shelfRows = math.max(profile.pen.shelfRows, decision.row :: number)
		end
		for _ in decision.slots do -- each new spot takes the best unlocked Toy Box squishy
			local best = PenMath.bestToyBox(profile.pen)
			local slot = PenMath.freeSlot(profile.pen)
			if best ~= nil and slot ~= 0 then
				best.slot = slot
			end
		end
		return true
	end)
	if not written then
		-- Cannot happen without a yield after the spend (the session was ready a moment ago); logged loudly.
		log:error(`user {userIdOf(player)}: a shelf buy was paid ({price} Coins) but could not be written`)
		return NetService.err(CODE_NOT_READY, false)
	end
	local session = sessions[player]
	if session ~= nil then
		session.boughtAt = deps.clock()
	end
	local what = if decision.top then "the TOP spot" else `shelf row {decision.row}`
	log:info(`user {userIdOf(player)} bought {what} for {price} Coins`)
	deps.dropGifts(player) -- the new spots make room for a waiting gift
	deps.showPen(player)
	local data: Types.PenResult = {
		pen = TableUtil.deepCopy(deps.profileOf(player).pen), -- copied before the save yields
		charged = true,
		savePending = false,
	}
	data.savePending = not deps.saveNow(player)
	return NetService.ok(data)
end

-- Public: the pen screen (pens3 phase 6; see the header for the order of the checks) ---------------------------------

function PenService.place(player: any, itemId: any, slot: any): Reply
	if Validate.integer(itemId) == nil or Validate.integer(slot) == nil then
		return NetService.err(CODE_INVALID, false)
	end
	local pen = readyPen(player)
	if pen == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local move, refused = PenMath.placeDecision(pen, itemId, slot)
	if move == nil then
		return NetService.err(refused or CODE_INVALID, false)
	end
	if move.from == move.to then
		return NetService.ok(penResult(player, deps.savePending(player))) -- already there: nothing changes
	end
	local paused = changeRefused(player)
	if paused ~= nil then
		return NetService.err(paused, false)
	end
	local written = deps.mutate(player, function(profile: any): boolean
		for _, item in profile.pen.items do
			if item.id == move.id then
				item.slot = move.to
			elseif move.swapId ~= nil and item.id == move.swapId then
				item.slot = move.from -- a swap: the other squishy takes the mover's old place
			end
		end
		return true
	end)
	if not written then
		return NetService.err(CODE_NOT_READY, false)
	end
	log:info(`user {userIdOf(player)} moved pen item {move.id} from slot {move.from} to {move.to}`)
	deps.showPen(player)
	deps.requestSave(player, SAVE_SOON)
	return NetService.ok(penResult(player, deps.savePending(player)))
end

function PenService.lock(player: any, itemId: any, locked: any): Reply
	if Validate.integer(itemId) == nil or type(locked) ~= "boolean" then
		return NetService.err(CODE_INVALID, false)
	end
	local pen = readyPen(player)
	if pen == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local item = PenMath.find(pen, itemId)
	if item == nil then
		return NetService.err(CODE_NOT_OWNED, false)
	end
	if (item.locked == true) == locked then
		return NetService.ok(penResult(player, deps.savePending(player))) -- already so: nothing changes
	end
	local paused = changeRefused(player)
	if paused ~= nil then
		return NetService.err(paused, false)
	end
	local written = deps.mutate(player, function(profile: any): boolean
		local live = PenMath.find(profile.pen, itemId)
		if live ~= nil then
			live.locked = locked
		end
		return live ~= nil
	end)
	if not written then
		return NetService.err(CODE_NOT_READY, false)
	end
	log:info(`user {userIdOf(player)} {if locked then "locked" else "unlocked"} pen item {itemId}`)
	deps.sendPen(player)
	local data = penResult(player, false) -- copied before the save yields
	data.savePending = not deps.saveNow(player)
	return NetService.ok(data)
end

-- Public: selling, the buy-back and fusion (pens3 phases 7-8; see the header for the order of the checks) ------------

-- The Coins a sale with this requestId paid (it was made: a retry), or nil.
local function replayOf(profile: any, request: string): number?
	local list = if type(profile) == "table" then profile.buyBack else nil
	local paid: number? = nil
	if type(list) == "table" then
		for _, entry in list do
			if type(entry) == "table" and entry.req == request then
				paid = (paid or 0) + (tonumber(entry.price) or 0)
			end
		end
	end
	return paid
end

-- A sale of `ids` (nil = Sell All).
local function sell(player: any, ids: any, requestId: any): Reply
	local request = Validate.requestId(requestId)
	if request == nil or (ids ~= nil and Validate.itemIds(ids) == nil) then
		return NetService.err(CODE_INVALID, false)
	end
	local pen = readyPen(player)
	if pen == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local replay = replayOf(deps.profileOf(player), request)
	if replay ~= nil then
		local again: Types.SellResult = {
			pen = TableUtil.deepCopy(pen),
			coins = replay,
			charged = false,
			savePending = deps.savePending(player),
		}
		return NetService.ok(again)
	end
	local list = ids or PenMath.sellAllIds(pen)
	if #list == 0 then
		return NetService.err(CODE_NOTHING, false)
	end
	local sale, refused = PenMath.sellDecision(pen, list)
	if sale == nil then
		return NetService.err(refused or CODE_INVALID, false)
	end
	local paused = changeRefused(player)
	if paused ~= nil then
		return NetService.err(paused, false)
	end
	local now = deps.now()
	local written = deps.mutate(player, function(profile: any): boolean
		local sold: { [number]: boolean } = {}
		for _, item in sale.items do
			sold[item.id] = true
		end
		local kept: { Types.PenItem } = {}
		for _, item in profile.pen.items do
			if not sold[item.id] then
				table.insert(kept, item)
			end
		end
		profile.pen.items = kept
		local entries = PenMath.liveBuyBack(profile.buyBack, now)
		for _, item in sale.items do
			local bare = TableUtil.deepCopy(item)
			if bare.coat > 0 then
				profile.bag[bare.coat] += 1 -- V2:382: the coating goes to the bag, the squishy is sold bare
				bare.coat = 0
			end
			bare.slot, bare.locked = 0, false
			table.insert(entries, { item = bare, price = PenMath.sellPrice(item), at = now, req = request })
		end
		while #entries > PEN.buyBackMax do
			table.remove(entries, 1) -- the oldest falls off first
		end
		profile.buyBack = entries
		return true
	end)
	if not written then
		return NetService.err(CODE_NOT_READY, false)
	end
	local paid = deps.grantCoins(player, sale.coins, REASON_SELL)
	if paid < sale.coins then
		-- maxCoins clamped the grant: this sale's entries hold what it really paid (the newest give way first).
		deps.mutate(player, function(profile: any): boolean
			local short = sale.coins - paid
			for index = #profile.buyBack, 1, -1 do
				local entry = profile.buyBack[index]
				if entry.req == request and short > 0 then
					local cut = math.min(short, entry.price)
					entry.price -= cut
					short -= cut
				end
			end
			return true
		end)
	end
	log:info(`user {userIdOf(player)} sold {#sale.items} squishies for {paid} Coins`)
	deps.showPen(player)
	deps.sendBuyBack(player)
	local data: Types.SellResult = {
		pen = TableUtil.deepCopy(deps.profileOf(player).pen), -- copied before the save yields
		coins = paid,
		charged = false,
		savePending = false,
	}
	data.savePending = not deps.saveNow(player)
	return NetService.ok(data)
end

function PenService.sellItems(player: any, ids: any, requestId: any): Reply
	if ids == nil then
		return NetService.err(CODE_INVALID, false) -- nil means Sell All inside sell(), never from a client
	end
	return sell(player, ids, requestId)
end

function PenService.sellAll(player: any, requestId: any): Reply
	return sell(player, nil, requestId)
end

function PenService.buyBack(player: any, itemId: any): Reply
	if Validate.integer(itemId) == nil then
		return NetService.err(CODE_INVALID, false)
	end
	local pen = readyPen(player)
	if pen == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local found, refused = PenMath.buyBackDecision(deps.profileOf(player).buyBack, pen, itemId, deps.now())
	if found == nil then
		return NetService.err(refused or CODE_INVALID, false)
	end
	local price = found.entry.price
	local spendRefused = spend(player, price, REASON_SELL, false)
	if spendRefused ~= nil then
		return NetService.err(spendRefused, false)
	end
	local ran, back = deps.mutate(player, function(profile: any): boolean
		if profile.buyBack[found.index] ~= found.entry then
			return false
		end
		table.remove(profile.buyBack, found.index)
		local item = TableUtil.deepCopy(found.entry.item)
		item.id = profile.pen.nextId
		profile.pen.nextId += 1
		item.slot = PenMath.freeSlot(profile.pen)
		item.locked = false
		table.insert(profile.pen.items, item)
		return true
	end)
	if not (ran and back) then
		-- Cannot happen without a yield after the spend; never keep Coins for nothing: the spend is given back.
		log:error(`user {userIdOf(player)}: buy-back of item {itemId} was paid ({price} Coins) but not written`)
		if price > 0 then
			deps.grantCoins(player, price, REASON_REFUND)
		end
		return NetService.err(CODE_NOT_READY, false)
	end
	log:info(`user {userIdOf(player)} bought back pen item {itemId} for {price} Coins`)
	deps.showPen(player)
	deps.sendBuyBack(player)
	local data: Types.PenResult = {
		pen = TableUtil.deepCopy(deps.profileOf(player).pen),
		charged = price > 0,
		savePending = false,
	}
	data.savePending = not deps.saveNow(player)
	return NetService.ok(data)
end

function PenService.fuse(player: any, a: any, b: any, c: any): Reply
	if Validate.integer(a) == nil or Validate.integer(b) == nil or Validate.integer(c) == nil then
		return NetService.err(CODE_INVALID, false)
	end
	local pen = readyPen(player)
	if pen == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local fusion, refused = PenMath.fuseDecision(pen, { a, b, c })
	if fusion == nil then
		return NetService.err(refused or CODE_INVALID, false)
	end
	local paused = changeRefused(player)
	if paused ~= nil then
		return NetService.err(paused, false)
	end
	local keeperId = fusion.keeper.id
	local written = deps.mutate(player, function(profile: any): boolean
		local gone: { [number]: boolean } = {}
		for _, item in fusion.others do
			gone[item.id] = true
		end
		local kept: { Types.PenItem } = {}
		for _, item in profile.pen.items do
			if item.id == keeperId then
				item.form, item.level, item.coat = fusion.form, fusion.level, 0 -- it comes out bare, in its slot
			end
			if not gone[item.id] then
				table.insert(kept, item)
			end
		end
		profile.pen.items = kept
		for _, coat in fusion.coats do
			profile.bag[coat] += 1
		end
		return true
	end)
	if not written then
		return NetService.err(CODE_NOT_READY, false)
	end
	log:info(`user {userIdOf(player)} fused pen items {a}, {b}, {c} into form {fusion.form} (item {keeperId})`)
	deps.showPen(player)
	local data: Types.FuseResult = {
		pen = TableUtil.deepCopy(deps.profileOf(player).pen),
		id = keeperId,
		charged = false,
		savePending = false,
	}
	data.savePending = not deps.saveNow(player)
	return NetService.ok(data)
end

-- Public: food and levels (pens3 phase 9; see the header for the order of the checks) --------------------------------

-- The reply data of a food call: the caller's pen and food, copied (before any save yields).
local function foodResult(player: any, levels: number, charged: boolean, savePending: boolean): Types.FoodResult
	local profile = deps.profileOf(player)
	return {
		pen = TableUtil.deepCopy(profile.pen),
		food = TableUtil.deepCopy(profile.food),
		levels = levels,
		charged = charged,
		savePending = savePending,
	}
end

function PenService.buyFood(player: any, foodId: any, count: any, expectedPrice: any, requestId: any): Reply
	local request = Validate.requestId(requestId)
	local whole = Validate.integer(count) ~= nil and Validate.coins(expectedPrice) ~= nil
	if type(foodId) ~= "string" or not whole or request == nil then
		return NetService.err(CODE_INVALID, false)
	end
	if readyPen(player) == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local session = sessions[player]
	if session ~= nil and session.foodReq == request then
		return NetService.ok(foodResult(player, 0, true, deps.savePending(player))) -- a retry: it was bought
	end
	local food = deps.profileOf(player).food
	local buy, refused = PenMath.buyFoodDecision(food, foodId, count, expectedPrice, PenMath.levelCap())
	if buy == nil then
		return NetService.err(refused or CODE_INVALID, false)
	end
	local spendRefused = spend(player, buy.price, REASON_FOOD, false)
	if spendRefused ~= nil then
		return NetService.err(spendRefused, false)
	end
	local id = buy.food.id
	local written = deps.mutate(player, function(profile: any): boolean
		profile.food[id] = PenMath.foodCount(profile.food, id) + buy.count
		return true
	end)
	if not written then
		-- Cannot happen without a yield after the spend; never keep Coins for nothing: the spend is given back.
		log:error(`user {userIdOf(player)}: {buy.count} {id} were paid ({buy.price} Coins) but not written`)
		deps.grantCoins(player, buy.price, REASON_REFUND)
		return NetService.err(CODE_NOT_READY, false)
	end
	if session ~= nil then
		session.foodReq = request
	end
	log:info(`user {userIdOf(player)} bought {buy.count} {id} for {buy.price} Coins`)
	deps.sendFood(player)
	local data = foodResult(player, 0, true, false)
	data.savePending = not deps.saveNow(player)
	return NetService.ok(data)
end

function PenService.feed(player: any, itemId: any, requestId: any): Reply
	local request = Validate.requestId(requestId)
	if Validate.integer(itemId) == nil or request == nil then
		return NetService.err(CODE_INVALID, false)
	end
	local pen = readyPen(player)
	if pen == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local session = sessions[player]
	if session ~= nil and session.feedReq == request then
		return NetService.ok(foodResult(player, 0, false, deps.savePending(player))) -- a retry: it was fed
	end
	local step, refused = PenMath.feedDecision(pen, deps.profileOf(player).food, itemId, PenMath.levelCap())
	if step == nil then
		return NetService.err(refused or CODE_INVALID, false)
	end
	local paused = changeRefused(player)
	if paused ~= nil then
		return NetService.err(paused, false)
	end
	local written = deps.mutate(player, function(profile: any): boolean
		local live = PenMath.find(profile.pen, itemId)
		if live == nil then
			return false
		end
		live.level += 1
		profile.food[step.food.id] -= step.pieces
		return true
	end)
	if not written then
		return NetService.err(CODE_NOT_READY, false)
	end
	if session ~= nil then
		session.feedReq = request
	end
	log:info(`user {userIdOf(player)} fed pen item {itemId} {step.pieces} {step.food.id} (Lv {step.item.level})`)
	deps.showPen(player) -- its coin label and card show the new level
	deps.sendFood(player)
	deps.requestSave(player, SAVE_SOON)
	return NetService.ok(foodResult(player, 1, false, deps.savePending(player)))
end

function PenService.feedAll(player: any): Reply
	local pen = readyPen(player)
	if pen == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local plan = PenMath.feedAllPlan(pen, deps.profileOf(player).food, PenMath.levelCap())
	if plan.steps == 0 then
		return NetService.err(CODE_NOTHING_TO_FEED, false)
	end
	local paused = changeRefused(player)
	if paused ~= nil then
		return NetService.err(paused, false)
	end
	local written = deps.mutate(player, function(profile: any): boolean
		for _, item in profile.pen.items do
			item.level = plan.levels[item.id] or item.level
		end
		for id, pieces in plan.used do
			profile.food[id] -= pieces
		end
		return true
	end)
	if not written then
		return NetService.err(CODE_NOT_READY, false)
	end
	log:info(`user {userIdOf(player)} fed the pen: {plan.steps} levels`)
	deps.showPen(player)
	deps.sendFood(player)
	deps.requestSave(player, SAVE_SOON)
	return NetService.ok(foodResult(player, plan.steps, false, deps.savePending(player)))
end

-- Public: coins while away (see the header) ---------------------------------------------------------------------------

-- DataService.Loaded: the Coins for the time away, and the gift for the client when they paid.
function PenService.loaded(player: any)
	local coins, seconds = deps.grantAway(player)
	if coins > 0 then
		deps.setAwayGift(player, { coins = coins, seconds = seconds })
		log:info(`user {userIdOf(player)} got {coins} Coins for {seconds} s away`)
	end
	deps.dropGifts(player) -- pens3 phase 5: gifts that waited for room
end

-- Public: tests -----------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function PenService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Forgets every session (tests; not called by the bootstrap).
function PenService.reset()
	table.clear(sessions)
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function PenService.init()
	local problems = ValidatePen(Config)
	if #problems > 0 then
		error(`[SD][Pen] Config.Economy.Pen is invalid: {table.concat(problems, "; ")}`)
	end
	local foodProblems = ValidateFood(Config) -- pens3 phase 9
	if #foodProblems > 0 then
		error(`[SD][Pen] Config.Economy.Food is invalid: {table.concat(foodProblems, "; ")}`)
	end
	NetService.onInvoke(REMOTE_BUY, function(player: Player, expectedPrice: any): any
		return PenService.buy(player, expectedPrice)
	end)
	NetService.onInvoke(REMOTE_BUY_SHELF, function(player: Player, expectedPrice: any): any
		return PenService.buyShelf(player, expectedPrice)
	end)
	NetService.onInvoke(REMOTE_PLACE, function(player: Player, itemId: any, slot: any): any
		return PenService.place(player, itemId, slot)
	end)
	NetService.onInvoke(REMOTE_LOCK, function(player: Player, itemId: any, locked: any): any
		return PenService.lock(player, itemId, locked)
	end)
	NetService.onInvoke(REMOTE_SELL, function(player: Player, ids: any, requestId: any): any
		return PenService.sellItems(player, ids, requestId)
	end)
	NetService.onInvoke(REMOTE_SELL_ALL, function(player: Player, requestId: any): any
		return PenService.sellAll(player, requestId)
	end)
	NetService.onInvoke(REMOTE_BUY_BACK, function(player: Player, itemId: any): any
		return PenService.buyBack(player, itemId)
	end)
	NetService.onInvoke(REMOTE_FUSE, function(player: Player, a: any, b: any, c: any): any
		return PenService.fuse(player, a, b, c)
	end)
	NetService.onInvoke(
		REMOTE_BUY_FOOD,
		function(player: Player, foodId: any, count: any, expectedPrice: any, requestId: any): any
			return PenService.buyFood(player, foodId, count, expectedPrice, requestId)
		end
	)
	NetService.onInvoke(REMOTE_FEED, function(player: Player, itemId: any, requestId: any): any
		return PenService.feed(player, itemId, requestId)
	end)
	NetService.onInvoke(REMOTE_FEED_ALL, function(player: Player): any
		return PenService.feedAll(player)
	end)
	-- A new squishy (a box, the shop, a Studio grant): its pen item came in the same grant step; show it.
	EconomyService.SquishyGranted:connect(function(player: Player)
		deps.showPen(player)
	end)
	StateService.dataPort().onLoaded(function(player: any)
		PenService.loaded(player)
	end)
end

function PenService.start()
	if loopThread ~= nil then
		return
	end
	loopThread = task.spawn(function()
		while true do
			PenService.step(task.wait(PEN.tickSeconds))
		end
	end)
end

function PenService.playerAdded(player: Player)
	if sessions[player] == nil then
		sessions[player] = { carry = 0, boughtAt = -math.huge, joinedAt = deps.clock(), frogAsked = false }
	end
end

function PenService.playerRemoving(player: Player)
	sessions[player] = nil
end

return PenService
