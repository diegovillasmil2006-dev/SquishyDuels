--!strict
-- ShopService (server only). DESIGN §2.3, §2.8 (ShopBuy), §3.4, §3.11, §6.6, §12 #3, #4, #6, #7, #14.
-- Direct Coin purchases: every squishy with a Catalog shopPrice can be bought by every player (the guaranteed Coin
-- path to Dragon). The client sends only (squishyId, expectedPrice, requestId); the price is the server's:
-- Pricing.shopPrice(id, profile.owned) (pens3 phase 5: the Welcome price for the first of a Common, D1:202, else the
-- Catalog shopPrice). An owned squishy is bought again as a copy (pens3 phase 5, copies).
-- buy(p, squishyId, expectedPrice, requestId), in the §6.6 order:
--   1. a Catalog id (and a GUID requestId), else net.invalid;
--   2. shopPrice nil (the free starter) or a price disabled at boot -> shop.notForSale;
--   3. expectedPrice not a whole Coin amount (Validate.coins: up to maxCoins, since prices reach 1.1T) ->
--      shop.priceChanged;
--   4. no profile in memory yet -> data.notReady;
--   5. shopLog.req == requestId -> the stored result (replay: no charge, charged = true as first answered);
--   6. expectedPrice ~= Pricing.shopPrice(id, owned) -> shop.priceChanged (it is only compared, never charged; checked
--      after the replay because the price moves once the squishy is owned); then (pens3 phase 5, was "already owned
--      -> ok {charged = false}") the Toy Box full (PenMath.room 0, D1:254-258) -> inventory.full;
--   7. profile not READY -> data.notReady;
--   8. a failed save pending -> box.saving (Reading: §3.11 blocks shop buys while savePending and §2.10 has no shop
--      code for it; "Saving your collection…" is the right sentence);
--   9. the server closing or a restart pending -> purchase.unavailable (Reading: §6.6 "not closing", no shop code);
--  10. matched or in a match -> inventory.lockedInDuel;
--  11. EconomyService.trySpend(p, price, "shop") (economy.notEnoughCoins; its "savePending" -> box.saving), then
--      EconomyService.grantSquishy(p, id, "shop") and the shopLog entry {req, squishy, price, at} (cap
--      Config.Data.caps.shopLog), with nothing yielding between the spend and the log append; then
--      DataService.saveNowAsync (awaited) and ok {squishyId, charged = true, savePending = not saved}.
-- Every refusal carries charged = false (nothing is ever charged before step 11 succeeds).
-- One buy in flight per player (a second call meanwhile -> net.rateLimited) and at most one charged buy per
-- 1 / Config.Net.Remotes.ShopBuy.rate seconds (§12 #7 "shop (1/s, one in flight)"; Reading: the spacing reuses the
-- remote's own rate instead of a second tunable). NetService enforces the same bucket on the remote.
-- Fail closed at boot (§2.6 "invalid shop entries are disabled"): a shopPrice that is not a positive whole number
-- within maxCoins, or above Pricing.ceiling(id) (the expected box spend, §6.6), is logged and not sold.
-- 2026-10-31 shop restock (Config.Events.ShopRestock; owner "Shared, first come", "Premium"): buyRestock(p, slot,
-- expectedPrice, requestId) buys offer `slot` of the live restock (EventSchedule.restockOffers of restockAt(serverNow),
-- the same offers in every server). Order: net.invalid (slot, requestId), data.notReady (no profile), the shopLog
-- replay, shop.restockOver (no restock live), net.invalid (no such slot), shop.notForSale (disabled at boot),
-- shop.priceChanged, inventory.full, shop.restockBought (this player has perPlayer of it), shop.soldOut (this server's
-- stock is gone), then steps 7-11 of a buy with the offer's form (Golden 1, Rainbow 2, a rare deal 0). The stock is
-- this server's, in memory, first come: it drops in the same no-yield step as the spend and is published as the
-- Workspace attribute SD_RestockStock (EventSchedule.stockText; a new restock starts full, so an older text means full).
-- useDeps(overrides?) swaps the collaborators (tests). init() registers the ShopBuy and ShopRestockBuy handlers and
-- never yields.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local EventSchedule = require(Shared.EventSchedule)
local Log = require(Shared.Util.Log)
local PenMath = require(Shared.PenMath)
local Pricing = require(Shared.Pricing)
local Types = require(Shared.Types)
local Validate = require(Shared.Util.Validate)
local Services = script.Parent
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local InventoryService = require(Services.InventoryService)
local NetService = require(Services.NetService)
local ShutdownService = require(Services.ShutdownService)
local StateService = require(Services.StateService)

-- Types

export type ShopResult = Types.ShopResult

export type Economy = {
	trySpend: (player: any, amount: number, reason: string) -> (boolean, string?),
	grantSquishy: (
		player: any,
		id: string,
		source: string,
		mayWait: boolean?,
		form: number?
	) -> { added: boolean, refused: string? },
	grantCoins: (player: any, amount: number, reason: string) -> (number, string?),
}

export type Deps = {
	data: StateService.DataPort,
	saveNow: (player: any) -> boolean, -- DataService.saveNowAsync (yields)
	economy: Economy,
	isClosing: () -> boolean,
	isRestartPending: () -> boolean,
	isLocked: (player: any) -> boolean, -- InventoryService.isLocked: matched or in a match
	now: () -> number, -- os.time: the shopLog `at`
	clock: () -> number, -- os.clock: the per-player spacing
	serverNow: () -> number, -- Workspace:GetServerTimeNow: which restock is live
	publishStock: (text: string) -> (), -- the SD_RestockStock attribute
}

-- Constants

local REMOTE_BUY = "ShopBuy"
local REMOTE_RESTOCK = "ShopRestockBuy"
local ATTR_STOCK = "SD_RestockStock"
local PER_PLAYER = require(Shared.Config.Events).ShopRestock.perPlayer
local REASON_SHOP = "shop"
local REASON_REFUND = "refund"
local SOURCE_SHOP = "shop"
local STATUS_READY = "ready"
local SHOP_LOG_CAP = Config.Data.caps.shopLog
local MIN_SECONDS_BETWEEN = 1 / Config.Net.Remotes.ShopBuy.rate

local CODE_INVALID = "net.invalid"
local CODE_RATE_LIMITED = "net.rateLimited"
local CODE_NOT_FOR_SALE = "shop.notForSale"
local CODE_PRICE_CHANGED = "shop.priceChanged"
local CODE_NOT_READY = "data.notReady"
local CODE_SAVING = "box.saving"
local CODE_UNAVAILABLE = "purchase.unavailable"
local CODE_LOCKED = "inventory.lockedInDuel"
local CODE_FULL = "inventory.full" -- pens3 phase 5: the Toy Box is full
local CODE_NOT_ENOUGH = "economy.notEnoughCoins"
local CODE_GENERIC = "error.generic"
local CODE_SOLD_OUT = "shop.soldOut"
local CODE_RESTOCK_BOUGHT = "shop.restockBought"
local CODE_RESTOCK_OVER = "shop.restockOver"

-- Module table

local ShopService = {}

-- Private

local log = Log.new("Shop")
local deps: Deps? = nil
local busy: { [any]: boolean } = {}
local lastChargeAt: { [any]: number } = {}
local disabled: { [string]: string } = {} -- squishyId -> why it is not sold (boot check)
-- The restock this server's stock is for: what is left of each offer and how many each buyer (UserId) took.
type Restock = { index: number, left: { number }, buyers: { { [any]: number } } }
local restock: Restock? = nil

local function defaultDeps(): Deps
	return {
		data = StateService.dataPort(),
		saveNow = function(player: any): boolean
			return DataService.saveNowAsync(player)
		end,
		economy = EconomyService :: any,
		isClosing = ShutdownService.isClosing,
		isRestartPending = ShutdownService.isRestartPending,
		isLocked = InventoryService.isLocked,
		now = os.time,
		clock = os.clock,
		serverNow = function(): number
			return Workspace:GetServerTimeNow()
		end,
		publishStock = function(text: string)
			Workspace:SetAttribute(ATTR_STOCK, text)
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

local function refuse(reason: string): any
	return NetService.err(reason, false)
end

local function isWholePrice(price: unknown): boolean
	return type(price) == "number"
		and price == price
		and price > 0
		and price <= Config.Economy.maxCoins
		and math.floor(price) == price
end

-- The Pricing ceiling of `id` (nil when no paid box contains it: no extra check).
local function ceilingOf(id: string): number?
	local value = Pricing.ceiling(id)
	if type(value) == "number" and value == value and value < math.huge then
		return value
	end
	return nil
end

local function resultFrom(squishyId: string, charged: boolean, savePending: boolean): ShopResult
	return { squishyId = squishyId, charged = charged, savePending = savePending }
end

local function appendShopLog(player: any, entry: Types.ShopLogEntry): boolean
	local ok = getDeps().data.mutate(player, function(profile: any): any
		local list = profile.shopLog
		if type(list) ~= "table" then
			list = {}
			profile.shopLog = list
		end
		EconomyService.appendLog(list, entry, SHOP_LOG_CAP)
		return nil
	end)
	return ok
end

local charge: (player: any, request: string, id: string, price: number, form: number, onGranted: (() -> ())?) -> any

local function buyLocked(player: any, squishyId: unknown, expectedPrice: unknown, requestId: unknown): any
	local d = getDeps()
	-- 1-3: the request itself
	local def = Catalog.get(squishyId)
	local request = Validate.requestId(requestId)
	if def == nil or request == nil then
		return refuse(CODE_INVALID)
	end
	local id = def.id
	if def.shopPrice == nil or disabled[id] ~= nil then
		return refuse(CODE_NOT_FOR_SALE)
	end
	if Validate.coins(expectedPrice) == nil then
		return refuse(CODE_PRICE_CHANGED)
	end
	-- 4-6: replay, this player's price and the room (the stored state is the idempotency key, §3.4)
	local data = d.data
	local profile = data.getProfile(player)
	if type(profile) ~= "table" then
		return refuse(CODE_NOT_READY)
	end
	local prior = EconomyService.findLog(profile.shopLog, "req", request)
	if prior ~= nil then
		local stored = if type(prior.squishy) == "string" then prior.squishy else id
		return NetService.ok(resultFrom(stored, true, data.savePending(player)))
	end
	local price = Pricing.shopPrice(id, profile.owned) :: number -- sold (step 2), so never nil
	if expectedPrice ~= price then
		return refuse(CODE_PRICE_CHANGED)
	end
	if PenMath.room(profile.pen) <= 0 then
		return refuse(CODE_FULL)
	end
	return charge(player, request, id, price, 0, nil)
end

-- The restock this server sells now (a new one starts with its full stock).
local function restockFor(index: number, offers: { EventSchedule.Offer }): Restock
	local current = restock
	if current and current.index == index then
		return current
	end
	local fresh: Restock = { index = index, left = {}, buyers = {} }
	for slot, offer in offers do
		fresh.left[slot] = offer.stock
		fresh.buyers[slot] = {}
	end
	restock = fresh
	return fresh
end

local function buyRestockLocked(player: any, slot: unknown, expectedPrice: unknown, requestId: unknown): any
	local d = getDeps()
	local request = Validate.requestId(requestId)
	if type(slot) ~= "number" or slot ~= math.floor(slot) or request == nil then
		return refuse(CODE_INVALID)
	end
	local data = d.data
	local profile = data.getProfile(player)
	if type(profile) ~= "table" then
		return refuse(CODE_NOT_READY)
	end
	local prior = EconomyService.findLog(profile.shopLog, "req", request)
	if prior ~= nil then
		return NetService.ok(resultFrom(tostring(prior.squishy), true, data.savePending(player)))
	end
	local index = EventSchedule.restockAt(d.serverNow())
	if index == nil then
		return refuse(CODE_RESTOCK_OVER)
	end
	local offers = EventSchedule.restockOffers(index)
	local offer = offers[slot :: number]
	if offer == nil then
		return refuse(CODE_INVALID)
	end
	if disabled[offer.squishy] ~= nil then
		return refuse(CODE_NOT_FOR_SALE)
	end
	if expectedPrice ~= offer.price then
		return refuse(CODE_PRICE_CHANGED)
	end
	if PenMath.room(profile.pen) <= 0 then
		return refuse(CODE_FULL)
	end
	local stock = restockFor(index, offers)
	local key = player.UserId
	local buyers = stock.buyers[slot :: number]
	if (buyers[key] or 0) >= PER_PLAYER then
		return refuse(CODE_RESTOCK_BOUGHT)
	end
	if stock.left[slot :: number] <= 0 then
		return refuse(CODE_SOLD_OUT)
	end
	return charge(player, request, offer.squishy, offer.price, offer.form, function()
		stock.left[slot :: number] -= 1
		buyers[key] = (buyers[key] or 0) + 1
		d.publishStock(EventSchedule.stockText(index, stock.left))
	end)
end

-- Steps 7-11 of a buy (see the header) for a sold `id` at `price` in `form`; `onGranted` runs right after the grant,
-- in the same no-yield step as the spend (the restock's stock).
function charge(player: any, request: string, id: string, price: number, form: number, onGranted: (() -> ())?): any
	local d = getDeps()
	local data = d.data
	-- 7-10: context gates
	if data.status(player) ~= STATUS_READY then
		return refuse(CODE_NOT_READY)
	end
	if data.savePending(player) then
		return refuse(CODE_SAVING)
	end
	if d.isClosing() or d.isRestartPending() then
		return refuse(CODE_UNAVAILABLE)
	end
	if d.isLocked(player) then
		return refuse(CODE_LOCKED)
	end
	local last = lastChargeAt[player]
	if last ~= nil and d.clock() - last < MIN_SECONDS_BETWEEN then
		return refuse(CODE_RATE_LIMITED)
	end
	-- 11: from the spend to the log append nothing yields (one in-memory change, §3.11)
	local spent, failure = d.economy.trySpend(player, price, REASON_SHOP)
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
	lastChargeAt[player] = d.clock()
	local grant = d.economy.grantSquishy(player, id, SOURCE_SHOP, false, form)
	if grant.refused ~= nil or not grant.added then
		-- Cannot happen after a successful spend in the same step (the id is valid and the room was checked); never
		-- keep Coins for nothing: the spend is given back.
		log:error(`buy {id}: the squishy could not be granted ({tostring(grant.refused)}); refunding {price}`)
		d.economy.grantCoins(player, price, REASON_REFUND)
		return refuse(CODE_GENERIC)
	end
	if onGranted then
		onGranted()
	end
	appendShopLog(player, { req = request, squishy = id, price = price, at = d.now() })
	local saved = d.saveNow(player)
	return NetService.ok(resultFrom(id, true, not saved))
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Replaces collaborators (fields not given keep their defaults; nil restores every default) and forgets the per-player
-- state (tests).
function ShopService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
	busy = {}
	lastChargeAt = {}
	restock = nil
end

-- The shop price of a squishy that is on sale, or nil (not sold, or disabled at boot).
function ShopService.priceOf(squishyId: unknown): number?
	local def = Catalog.get(squishyId)
	if def == nil or def.shopPrice == nil or disabled[def.id] ~= nil then
		return nil
	end
	return def.shopPrice
end

-- ShopBuy (§6.6). Returns NetService.ok(ShopResult) or NetService.err(code, false). Yields only for the "now" save.
function ShopService.buy(player: any, squishyId: unknown, expectedPrice: unknown, requestId: unknown): any
	if busy[player] then
		return refuse(CODE_RATE_LIMITED)
	end
	busy[player] = true
	local ok, result = pcall(buyLocked, player, squishyId, expectedPrice, requestId)
	busy[player] = nil
	if not ok then
		log:error("buy failed:", result)
		return NetService.err(CODE_GENERIC) -- whether anything was charged is unknown here: no `charged`
	end
	return result
end

-- ShopRestockBuy (see the header): ShopBuy's answers and its one-in-flight and one-a-second rules.
function ShopService.buyRestock(player: any, slot: unknown, expectedPrice: unknown, requestId: unknown): any
	if busy[player] then
		return refuse(CODE_RATE_LIMITED)
	end
	busy[player] = true
	local ok, result = pcall(buyRestockLocked, player, slot, expectedPrice, requestId)
	busy[player] = nil
	if not ok then
		log:error("restock buy failed:", result)
		return NetService.err(CODE_GENERIC) -- whether anything was charged is unknown here: no `charged`
	end
	return result
end

-- Checks every Catalog shop price (fail closed, see the header). Returns the disabled ids and why (tests, boot).
function ShopService.checkPrices(): { [string]: string }
	local found: { [string]: string } = {}
	for _, def in Catalog.list() do
		local price = def.shopPrice
		if price ~= nil then
			if not isWholePrice(price) then
				found[def.id] = "price is not a positive whole number within maxCoins"
			else
				local ceiling = ceilingOf(def.id)
				if ceiling ~= nil and price > ceiling then
					found[def.id] = `price {price} is above the box ceiling {ceiling}`
				end
			end
		end
	end
	return found
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function ShopService.init()
	disabled = ShopService.checkPrices()
	for id, why in disabled do
		log:warn(`{id} is not sold: {why}`)
	end
	NetService.onInvoke(REMOTE_BUY, function(player: Player, squishyId: any, expectedPrice: any, requestId: any): any
		return ShopService.buy(player, squishyId, expectedPrice, requestId)
	end)
	NetService.onInvoke(REMOTE_RESTOCK, function(player: Player, slot: any, expectedPrice: any, requestId: any): any
		return ShopService.buyRestock(player, slot, expectedPrice, requestId)
	end)
end

function ShopService.playerRemoving(player: Player)
	busy[player] = nil
	lastChargeAt[player] = nil
end

return ShopService
