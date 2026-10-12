--!strict
-- MonetizationService (server only). DESIGN §2.3, §2.6 (ORDER[1]), §2.8 (PromptCoinBundle, PromptGamePass), §3.4,
-- §3.10, §6.11, §12 #14 #18 #21, §17.9 (G7b). Robux stays OFF in v1: every productId is nil (M7) and nothing is ever
-- prompted, granted or shown for an id that was invented or not validated.
-- * init() runs FIRST in the bootstrap (SERVICE_ORDER[1]) and assigns MarketplaceService.ProcessReceipt before anything
--   that could yield; then it registers the PromptCoinBundle / PromptGamePass handlers (NetService.on works before
--   NetService.init: handlers are looked up on every call).
-- * processReceipt(info) is the classic ProcessReceipt (§3.10; BindReceiptHandler is not used), driven by the pure
--   ReceiptLogic.decide: bundle = Config.Monetization.byProductId[ProductId] (any configured id, even one that failed
--   boot validation); unknown -> Log:error + NotProcessedYet; buyer not in this server -> NotProcessedYet;
--   DataService.waitForProfileAsync, and a profile that is not READY -> NotProcessedYet; a PurchaseId already in
--   profile.receipts -> PurchaseGranted when it is saved, else (still pending) PurchaseGranted only after another
--   successful saveNowAsync; otherwise EconomyService.grantCoins(p, coins, "robux") and the receipts entry
--   (ReceiptLogic.entry, cap Config.Data.caps.receipts) with no yield between, DataService.addPendingReceipt, then
--   PurchaseGranted ONLY after a successful saveNowAsync (else NotProcessedYet: Roblox retries and the pending id is
--   saved again, never granted twice). CurrencySpent is never read (AdReward / CommerceProduct channels exist).
--   PromptProductPurchaseFinished never grants anything (it only closes the client's spinner, §3.10).
-- * Boot validation (spawned in start): every configured productId is checked with GetProductInfoAsync (pcall,
--   Config.Monetization.productInfoRetries retries, Reading: RETRY_WAIT_SECONDS apart): it must exist, have
--   Creator.CreatorTargetId == creatorGroupId and IsForSale. Ids that fail are never offered. With no id configured
--   (v1) it logs one info line.
-- * offeredBundles(): the keys of bundles with a validated productId and onSale, and {} whenever Config.Grip.enabled
--   and not Config.Grip.allowBundlesWithCapsules (G7b fail closed at runtime too, G-E). The owner's state field
--   StateDelta.monetization = {bundles = offeredBundles(), passes = {}} is set on join and after validation.
-- * PromptCoinBundle(bundleKey): an offered bundle, a READY profile and a server that is not closing -> the server's
--   MarketplaceService:PromptProductPurchase; anything else -> Notify("purchase.unavailable"). Never prompts an id
--   that is not offered. PromptGamePass(passKey): Reading: no pass has a validated id and a team-defined benefit in v1
--   (GamePasses = {}, CosmeticBenefits = {}), so it always answers Notify("purchase.unavailable") and ownsPass is
--   false; pass ownership checks and PromptGamePassPurchaseFinished arrive with the first real pass.
-- * Studio only (RunService:IsStudio() and Config.Debug.debugHooks, §12 #21): debugSimulateReceipt(p, purchaseId)
--   runs the SAME receipt core with a Studio-only fixture bundle (ProductId 0, FIXTURE_COINS Coins) that lives only
--   here and is never added to Config.Monetization (§3.10 "Studio receipt test"); debugState().
-- useDeps(overrides?) swaps the collaborators (tests: MarketplaceService, data, saves, grants, players, bundles).

-- Services

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Types = require(Shared.Types)
local Server = script.Parent.Parent
local ReceiptLogic = require(Server.Logic.ReceiptLogic)
local Services = script.Parent
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local NetService = require(Services.NetService)
local ShutdownService = require(Services.ShutdownService)
local StateService = require(Services.StateService)

-- Types

export type CoinBundle = ReceiptLogic.CoinBundle

export type Deps = {
	marketplace: any, -- MarketplaceService: ProcessReceipt, PromptProductPurchase, GetProductInfoAsync
	data: StateService.DataPort,
	waitForProfile: (player: any) -> any, -- DataService.waitForProfileAsync (yields): a READY profile or nil
	isReceiptPending: (player: any, purchaseId: string) -> boolean,
	addPendingReceipt: (player: any, purchaseId: string) -> (),
	saveNow: (player: any) -> boolean, -- DataService.saveNowAsync (yields)
	grantCoins: (player: any, amount: number, reason: string) -> (number, string?),
	playerByUserId: (userId: number) -> any?,
	players: () -> { any },
	setMonetization: (player: any, view: Types.MonetizationView) -> (),
	notify: (player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?) -> (),
	isClosing: () -> boolean,
	now: () -> number, -- os.time: the receipts `at`
	wait: (seconds: number) -> (), -- yields (task.wait): between product info retries
	debugAllowed: () -> boolean,
	bundles: { CoinBundle }, -- Config.Monetization.CoinBundles
	byProductId: { [number]: CoinBundle }, -- Config.Monetization.byProductId
	bundlesLockedByGrip: () -> boolean, -- G7b: Config.Grip.enabled and not allowBundlesWithCapsules
	log: Log.Logger, -- [SD][Monetization] (tests record it)
}

-- Constants

local MONETIZATION = Config.Monetization
local REMOTE_BUNDLE = "PromptCoinBundle"
local REMOTE_PASS = "PromptGamePass"
local REASON_ROBUX = "robux"
local CODE_UNAVAILABLE = "purchase.unavailable"
local STATUS_READY = "ready"
local RECEIPTS_CAP = Config.Data.caps.receipts
-- Reading: DESIGN gives no delay between GetProductInfoAsync retries.
local RETRY_WAIT_SECONDS = 2
-- The Studio-only receipt fixture (§3.10): ProductId 0 is never a real product, and this table is never in Config.
local FIXTURE_PRODUCT_ID = 0
local FIXTURE_COINS = 100
local FIXTURE_BUNDLE: CoinBundle = table.freeze({
	key = "studio_fixture",
	nameKey = "bundle.handful", -- never shown
	productId = FIXTURE_PRODUCT_ID,
	coins = FIXTURE_COINS,
	onSale = true,
})

-- Module table

local MonetizationService = {}

-- Private

local DEFAULT_LOG = Log.new("Monetization")
local deps: Deps? = nil
local validated: { [number]: boolean } = {} -- productId -> passed boot validation

local function defaultDeps(): Deps
	return {
		marketplace = MarketplaceService,
		data = StateService.dataPort(),
		waitForProfile = function(player: any): any
			return DataService.waitForProfileAsync(player)
		end,
		isReceiptPending = DataService.isReceiptPending,
		addPendingReceipt = DataService.addPendingReceipt,
		saveNow = function(player: any): boolean
			return DataService.saveNowAsync(player)
		end,
		grantCoins = EconomyService.grantCoins,
		playerByUserId = function(userId: number): any?
			return Players:GetPlayerByUserId(userId)
		end,
		players = function(): { any }
			return Players:GetPlayers()
		end,
		setMonetization = function(player: any, view: Types.MonetizationView)
			StateService.setSessionField(player, "monetization", view)
		end,
		notify = function(player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
			NetService.notify(player, code, args, kind)
		end,
		isClosing = ShutdownService.isClosing,
		now = os.time,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		debugAllowed = function(): boolean
			return RunService:IsStudio() and Config.Debug.debugHooks == true
		end,
		bundles = MONETIZATION.CoinBundles,
		byProductId = MONETIZATION.byProductId,
		bundlesLockedByGrip = function(): boolean
			return Config.Grip.enabled == true and Config.Grip.allowBundlesWithCapsules ~= true
		end,
		log = DEFAULT_LOG,
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

local function decisionOf(granted: boolean): Enum.ProductPurchaseDecision
	return if granted
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

local function userIdOf(player: any): string
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok then tostring(id) else "?"
end

-- The §3.10 core, shared by the real ProcessReceipt and the Studio fixture. `bundleFor(productId)` finds the bundle.
-- Returns the decision and the Coins this call added (0 unless it granted).
local function processCore(info: any, bundleFor: (productId: any) -> CoinBundle?): (boolean, number)
	local d = getDeps()
	local purchaseId = if type(info) == "table" then info.PurchaseId else nil
	if type(purchaseId) ~= "string" or purchaseId == "" then
		d.log:error("receipt without a PurchaseId")
		return false, 0
	end
	local productId = info.ProductId
	local bundle = bundleFor(productId)
	local player = if bundle ~= nil and type(info.PlayerId) == "number" then d.playerByUserId(info.PlayerId) else nil
	local profile = if player ~= nil then d.waitForProfile(player) else nil
	-- From here to the receipts append nothing yields (the status read, the decision and the grant are one step).
	local state: ReceiptLogic.DecideState = {
		bundle = bundle,
		playerPresent = player ~= nil,
		status = if player ~= nil then d.data.status(player) else nil,
	}
	local pending: { [string]: boolean }? = if player ~= nil
		then { [purchaseId] = d.isReceiptPending(player, purchaseId) }
		else nil
	local decision = ReceiptLogic.decide(state, profile, pending, info)
	local action = decision.action
	if action == "unknownProduct" then
		d.log:error("unknown product", tostring(productId), "purchase", purchaseId)
		return false, 0
	elseif action == "noPlayer" or action == "notReady" then
		return false, 0
	elseif action == "alreadyGranted" then
		return true, 0
	elseif action == "awaitSave" then
		return d.saveNow(player), 0
	end
	-- "grant": the Coins and the receipt in one non-yielding step, then the awaited save.
	local coinsBundle = bundle :: CoinBundle
	local added, failure = d.grantCoins(player, coinsBundle.coins, REASON_ROBUX)
	if failure ~= nil then
		d.log:error(`receipt {purchaseId}: Coins could not be granted to user {userIdOf(player)} ({failure})`)
		return false, 0
	end
	local entry = ReceiptLogic.entry(info, coinsBundle, d.now())
	local logged = d.data.mutate(player, function(live: any): any
		local list = live.receipts
		if type(list) ~= "table" then
			list = {}
			live.receipts = list
		end
		EconomyService.appendLog(list, entry, RECEIPTS_CAP)
		return nil
	end)
	if not logged then
		-- Cannot happen right after a grant in the same step; logged so it is never silent.
		d.log:error(`receipt {purchaseId}: the receipts entry for user {userIdOf(player)} could not be written`)
	end
	d.addPendingReceipt(player, purchaseId)
	local saved = d.saveNow(player)
	d.log:info(
		string.format(
			"receipt user=%s product=%s purchase=%s coins=%d saved=%s",
			userIdOf(player),
			tostring(productId),
			purchaseId,
			added,
			tostring(saved)
		)
	)
	return saved, added
end

local function bundleByKey(key: unknown): CoinBundle?
	if type(key) ~= "string" then
		return nil
	end
	for _, bundle in getDeps().bundles do
		if bundle.key == key then
			return bundle
		end
	end
	return nil
end

local function view(): Types.MonetizationView
	return { bundles = MonetizationService.offeredBundles(), passes = {} }
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- Replaces collaborators (fields not given keep their defaults; nil restores every default) and forgets validation
-- results (tests).
function MonetizationService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
	validated = {}
end

-- MarketplaceService.ProcessReceipt (§3.10). Never throws; an error answers NotProcessedYet (Roblox retries).
function MonetizationService.processReceipt(info: any): Enum.ProductPurchaseDecision
	local ok, granted = pcall(function(): boolean
		local byProductId = getDeps().byProductId
		local result = processCore(info, function(productId: any): CoinBundle?
			return if type(productId) == "number" then byProductId[productId] else nil
		end)
		return result
	end)
	if not ok then
		getDeps().log:error("ProcessReceipt failed:", granted)
		return decisionOf(false)
	end
	return decisionOf(granted)
end

-- The keys of the coin bundles offered right now (see the header; {} in v1).
function MonetizationService.offeredBundles(): { string }
	local d = getDeps()
	local keys: { string } = {}
	if d.bundlesLockedByGrip() then
		return keys -- G7b: coin bundles stay off while Grip is on (G-E)
	end
	for _, bundle in d.bundles do
		local productId = bundle.productId
		if productId ~= nil and bundle.onSale == true and validated[productId] == true then
			table.insert(keys, bundle.key)
		end
	end
	return keys
end

-- Game pass ownership (§3.10). No pass exists in v1 (see the header): always false.
function MonetizationService.ownsPass(_player: any, _key: string): boolean
	return false
end

-- PromptCoinBundle (§2.8, §6.11). Returns true when the purchase prompt was shown.
function MonetizationService.promptBundle(player: any, bundleKey: unknown): boolean
	local d = getDeps()
	local bundle = bundleByKey(bundleKey)
	local offered = bundle ~= nil and table.find(MonetizationService.offeredBundles(), bundle.key) ~= nil
	if bundle == nil or not offered or d.data.status(player) ~= STATUS_READY or d.isClosing() then
		d.notify(player, CODE_UNAVAILABLE, nil, "warn")
		return false
	end
	local productId = bundle.productId
	local ok, err = pcall(function(): any
		return d.marketplace:PromptProductPurchase(player, productId)
	end)
	if not ok then
		getDeps().log:warn(`PromptProductPurchase failed for user {userIdOf(player)}:`, err)
		d.notify(player, CODE_UNAVAILABLE, nil, "warn")
		return false
	end
	return true
end

-- PromptGamePass (§2.8): no pass is offered in v1 (see the header). Always purchase.unavailable.
function MonetizationService.promptPass(player: any, _passKey: unknown): boolean
	getDeps().notify(player, CODE_UNAVAILABLE, nil, "warn")
	return false
end

-- One boot validation of a product id (§3.10): exists, made by the group, for sale. Yields (GetProductInfoAsync).
function MonetizationService.validateProductAsync(productId: number): (boolean, string?)
	local d = getDeps()
	local attempts = 1 + math.max(0, MONETIZATION.productInfoRetries)
	local lastError = "no answer"
	for attempt = 1, attempts do
		local ok, info = pcall(function(): any
			return d.marketplace:GetProductInfoAsync(productId, Enum.InfoType.Product)
		end)
		if ok and type(info) == "table" then
			local creator = info.Creator
			local creatorId = if type(creator) == "table" then creator.CreatorTargetId else nil
			if creatorId ~= MONETIZATION.creatorGroupId then
				return false, `created by {tostring(creatorId)}, not group {MONETIZATION.creatorGroupId}`
			elseif info.IsForSale ~= true then
				return false, "not for sale"
			end
			return true, nil
		end
		lastError = if ok then "no product info" else tostring(info)
		if attempt < attempts then
			d.wait(RETRY_WAIT_SECONDS)
		end
	end
	return false, lastError
end

-- Validates every configured product id, then refreshes every player's monetization field. Yields.
function MonetizationService.validateAllAsync(): number
	local d = getDeps()
	local configured = 0
	for _, bundle in d.bundles do
		local productId = bundle.productId
		if productId ~= nil then
			configured += 1
			local ok, why = MonetizationService.validateProductAsync(productId)
			validated[productId] = ok
			if ok then
				getDeps().log:info(`coin bundle {bundle.key} ({productId}) validated`)
			else
				getDeps().log:warn(`coin bundle {bundle.key} ({productId}) is not offered: {tostring(why)}`)
			end
		end
	end
	if configured == 0 then
		getDeps().log:info("no coin bundle has a product id: Robux purchases are off until real products exist (M7)")
		return 0
	end
	for _, player in d.players() do
		d.setMonetization(player, view())
	end
	return configured
end

-- Studio only: runs the receipt core with the fixture bundle (ProductId 0). Returns {ok, decision, coinsAdded}.
function MonetizationService.debugSimulateReceipt(player: any, purchaseId: unknown): { [string]: any }
	local d = getDeps()
	if not d.debugAllowed() then
		return { ok = false, error = "Studio only" }
	end
	if type(purchaseId) ~= "string" or purchaseId == "" then
		return { ok = false, error = "needs a purchaseId string" }
	end
	local info = {
		PurchaseId = purchaseId,
		ProductId = FIXTURE_PRODUCT_ID,
		PlayerId = player.UserId,
		CurrencySpent = 0, -- never read: a receipt with 0 is granted like any other (§3.10)
	}
	local ok, granted, added = pcall(processCore, info, function(productId: any): CoinBundle?
		return if productId == FIXTURE_PRODUCT_ID then FIXTURE_BUNDLE else nil
	end)
	if not ok then
		return { ok = false, error = tostring(granted) }
	end
	return { ok = true, decision = decisionOf(granted).Name, coinsAdded = added, fixtureCoins = FIXTURE_COINS }
end

-- Studio debug view.
function MonetizationService.debugState(): { [string]: any }
	local ids: { number } = {}
	for productId, ok in validated do
		if ok then
			table.insert(ids, productId)
		end
	end
	return {
		offered = MonetizationService.offeredBundles(),
		validated = ids,
		lockedByGrip = getDeps().bundlesLockedByGrip(),
		fixtureCoins = FIXTURE_COINS,
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function MonetizationService.init()
	-- First, before anything that could yield (§2.6 rule 3): Roblox may deliver a pending receipt at any time.
	getDeps().marketplace.ProcessReceipt = MonetizationService.processReceipt
	NetService.on(REMOTE_BUNDLE, function(player: Player, bundleKey: any)
		MonetizationService.promptBundle(player, bundleKey)
	end)
	NetService.on(REMOTE_PASS, function(player: Player, passKey: any)
		MonetizationService.promptPass(player, passKey)
	end)
end

function MonetizationService.start()
	MonetizationService.validateAllAsync()
end

function MonetizationService.playerAdded(player: Player)
	getDeps().setMonetization(player, view())
end

return MonetizationService
