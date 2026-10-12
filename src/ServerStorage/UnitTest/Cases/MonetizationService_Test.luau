--!strict
-- MonetizationService_Test: unit tests for ServerScriptService.Server.Services.MonetizationService.
-- Server only (ServerStorage.UnitTest). Edit mode: MarketplaceService is a fake table (no real prompts, product info or
-- receipts), the real EconomyService runs on a fake data port, DataService's receipt and save functions are fakes,
-- players are plain tables found by userId. Bundles are test fixtures passed through useDeps (Config.Monetization keeps
-- every productId nil and is never changed). Tables are compared by value.
-- Contract (DESIGN §3.10, §6.11, §12 #14 #18 #21, §17.9 G7b):
--   * ProcessReceipt: unknown product / buyer not here / profile not READY -> NotProcessedYet with nothing granted;
--     a new PurchaseId -> Coins (reason "robux") + a receipts entry + a pending id, PurchaseGranted only after a
--     successful "now" save (a failed save -> NotProcessedYet, and the retry saves again without a second grant);
--     a recorded and saved PurchaseId -> PurchaseGranted with nothing new; CurrencySpent 0 is granted like any other;
--     receipts capped at Config.Data.caps.receipts; granted once per PurchaseId;
--   * offeredBundles: {} while every productId is nil, {} while Grip locks bundles (G7b), else validated onSale keys;
--   * PromptCoinBundle / PromptGamePass never prompt anything that is not offered (purchase.unavailable);
--   * boot validation: creator group, IsForSale, retries;
--   * debugSimulateReceipt: Studio only, the fixture bundle (ProductId 0) through the same core, granted once;
--   * init assigns ProcessReceipt.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local NOW = 1_790_000_000
local GROUP = 706867720
local PRODUCT = 111
local OTHER_PRODUCT = 222

return function(t: Context)
	local expect = t.expect
	local MonetizationService = t.requireServer("Services/MonetizationService")
	local EconomyService = t.requireServer("Services/EconomyService")
	local Config = t.requireShared("Config")

	local GRANTED = Enum.ProductPurchaseDecision.PurchaseGranted
	local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet

	local function bundle(key: string, productId: number?, coins: number, onSale: boolean?): any
		return { key = key, nameKey = "bundle.handful", productId = productId, coins = coins, onSale = onSale ~= false }
	end

	local function setup(opts: { [string]: any }?): any
		local o: { [string]: any } = opts or {}
		local bundles = o.bundles
			or { bundle("coins_handful", PRODUCT, 1000), bundle("coins_jar", OTHER_PRODUCT, 2750) }
		local byProductId = {}
		for _, b in bundles do
			if b.productId ~= nil then
				byProductId[b.productId] = b
			end
		end
		local w: any = {
			profiles = {},
			statuses = {},
			byUserId = {},
			pending = {},
			saves = 0,
			saveResult = true,
			grants = {},
			notices = {},
			prompts = {},
			views = {},
			waits = {},
			closing = false,
			locked = if o.locked == nil then false else o.locked,
			allowed = if o.allowed == nil then true else o.allowed,
			productInfo = o.productInfo or {},
			infoCalls = 0,
			logs = {},
		}
		local function record(level: string): (...any) -> ()
			return function(_self: any, ...: any)
				local parts = { level }
				for i = 1, select("#", ...) do
					table.insert(parts, tostring((select(i, ...))))
				end
				table.insert(w.logs, table.concat(parts, " "))
			end
		end
		local logger = { debug = function() end, info = record("info"), warn = record("warn"), error = record("error") }
		local port = {
			getProfile = function(player: any): any?
				return w.profiles[player]
			end,
			status = function(player: any): string
				return w.statuses[player] or "loading"
			end,
			persisted = function(_player: any): boolean
				return false
			end,
			savePending = function(_player: any): boolean
				return false
			end,
			statusReason = function(_player: any): string?
				return nil
			end,
			mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
				if w.statuses[player] ~= "ready" then
					return false, "data.notReady"
				end
				return true, fn(w.profiles[player])
			end,
			requestSave = function() end,
			onLoaded = function() end,
			onStatusChanged = function() end,
		}
		EconomyService.useDeps({
			data = port,
			markDirty = function() end,
			now = function(): number
				return NOW
			end,
			debugAllowed = function(): boolean
				return false
			end,
		})
		w.marketplace = {
			PromptProductPurchase = function(_self: any, player: any, productId: number)
				table.insert(w.prompts, { player = player, productId = productId })
			end,
			GetProductInfoAsync = function(_self: any, productId: number, _infoType: any): any
				w.infoCalls += 1
				local answers = w.productInfo[productId]
				local answer = if answers then table.remove(answers, 1) else nil
				if answer == nil or answer == "error" then
					error("HTTP 500 (fake)")
				end
				return answer
			end,
		}
		MonetizationService.useDeps({
			marketplace = w.marketplace,
			data = port,
			waitForProfile = function(player: any): any
				return if w.statuses[player] == "ready" then w.profiles[player] else nil
			end,
			isReceiptPending = function(player: any, id: string): boolean
				return w.pending[player] ~= nil and w.pending[player][id] == true
			end,
			addPendingReceipt = function(player: any, id: string)
				w.pending[player] = w.pending[player] or {}
				w.pending[player][id] = true
			end,
			saveNow = function(player: any): boolean
				w.saves += 1
				if w.saveResult then
					w.pending[player] = nil -- a successful save clears every pending id
				end
				return w.saveResult
			end,
			grantCoins = function(player: any, amount: number, reason: string): (number, string?)
				table.insert(w.grants, { amount = amount, reason = reason })
				return EconomyService.grantCoins(player, amount, reason)
			end,
			playerByUserId = function(userId: number): any?
				return w.byUserId[userId]
			end,
			players = function(): { any }
				local list = {}
				for _, player in w.byUserId do
					table.insert(list, player)
				end
				return list
			end,
			setMonetization = function(player: any, view: any)
				table.insert(w.views, { player = player, view = view })
			end,
			notify = function(player: any, code: string, _args: any, kind: any)
				table.insert(w.notices, { player = player, code = code, kind = kind })
			end,
			isClosing = function(): boolean
				return w.closing
			end,
			now = function(): number
				return NOW
			end,
			wait = function(seconds: number)
				table.insert(w.waits, seconds)
			end,
			debugAllowed = function(): boolean
				return w.allowed
			end,
			bundles = bundles,
			byProductId = byProductId,
			bundlesLockedByGrip = function(): boolean
				return w.locked
			end,
			log = logger,
		})
		return w
	end

	local function logged(w: any, text: string): boolean
		for _, line in w.logs do
			if string.find(line, text, 1, true) then
				return true
			end
		end
		return false
	end

	local function readyPlayer(w: any, coins: number, userId: number?): (any, any)
		local id = userId or 7
		local player = { UserId = id }
		local profile = { coins = coins, stats = { coinsEarned = 0, coinsSpent = 0 }, receipts = {} }
		w.profiles[player] = profile
		w.statuses[player] = "ready"
		w.byUserId[id] = player
		return player, profile
	end

	local function receipt(purchaseId: string, productId: number?, userId: number?, spent: number?): any
		return {
			PurchaseId = purchaseId,
			ProductId = productId or PRODUCT,
			PlayerId = userId or 7,
			CurrencySpent = if spent == nil then 75 else spent,
		}
	end

	local function offeredFor(w: any, ids: { number })
		for _, id in ids do
			w.productInfo[id] = { { Creator = { CreatorTargetId = GROUP }, IsForSale = true } }
		end
		MonetizationService.validateAllAsync()
	end

	t.test("unknown product, absent buyer and a profile that is not ready: NotProcessedYet, nothing granted", function()
		local w = setup()
		local p, profile = readyPlayer(w, 0)
		expect.equal(MonetizationService.processReceipt(receipt("P1", 999)), NOT_YET)
		expect.equal(logged(w, "error unknown product 999"), true)
		expect.equal(MonetizationService.processReceipt(receipt("P2", PRODUCT, 404)), NOT_YET)
		w.statuses[p] = "offline"
		expect.equal(MonetizationService.processReceipt(receipt("P3")), NOT_YET)
		expect.equal(MonetizationService.processReceipt({}), NOT_YET)
		expect.equal(profile.coins, 0)
		expect.deepEqual(profile.receipts, {})
		expect.deepEqual(w.grants, {})
		expect.equal(w.saves, 0)
	end)

	t.test("a new PurchaseId grants Coins (robux) and a receipt, then PurchaseGranted after the now save", function()
		local w = setup()
		local p, profile = readyPlayer(w, 50)
		expect.equal(MonetizationService.processReceipt(receipt("P1")), GRANTED)
		expect.equal(profile.coins, 1050)
		expect.deepEqual(w.grants, { { amount = 1000, reason = "robux" } })
		expect.deepEqual(profile.receipts, { { id = "P1", product = PRODUCT, coins = 1000, at = NOW } })
		expect.equal(w.saves, 1)
		expect.equal(w.pending[p], nil)
		-- Roblox calls again with the same PurchaseId (recorded and saved): granted, nothing new
		expect.equal(MonetizationService.processReceipt(receipt("P1")), GRANTED)
		expect.equal(profile.coins, 1050)
		expect.equal(#profile.receipts, 1)
		expect.equal(w.saves, 1)
	end)

	t.test("a failed save answers NotProcessedYet; the retry saves again and never grants twice", function()
		local w = setup()
		local p, profile = readyPlayer(w, 0)
		w.saveResult = false
		expect.equal(MonetizationService.processReceipt(receipt("P1")), NOT_YET)
		expect.equal(profile.coins, 1000) -- the change stays in memory (this server holds the lock)
		expect.equal(w.pending[p].P1, true)
		expect.equal(MonetizationService.processReceipt(receipt("P1")), NOT_YET) -- still pending, save fails again
		w.saveResult = true
		expect.equal(MonetizationService.processReceipt(receipt("P1")), GRANTED)
		expect.equal(profile.coins, 1000)
		expect.equal(#profile.receipts, 1)
		expect.equal(#w.grants, 1)
		expect.equal(w.saves, 3)
	end)

	t.test(
		"CurrencySpent 0 (AdReward, CommerceProduct) is granted like any other; receipts keep the newest 100",
		function()
			local w = setup()
			local _, profile = readyPlayer(w, 0)
			local cap = Config.Data.caps.receipts
			for i = 1, cap do
				table.insert(profile.receipts, { id = "old" .. i, product = PRODUCT, coins = 1, at = i })
			end
			expect.equal(MonetizationService.processReceipt(receipt("P0", OTHER_PRODUCT, 7, 0)), GRANTED)
			expect.equal(profile.coins, 2750)
			expect.equal(#profile.receipts, cap)
			expect.deepEqual(profile.receipts[cap], { id = "P0", product = OTHER_PRODUCT, coins = 2750, at = NOW })
			expect.equal(profile.receipts[1].id, "old2")
		end
	)

	t.test("offeredBundles: none while every productId is nil, none while Grip locks bundles (G7b)", function()
		local w = setup({ bundles = { bundle("coins_handful", nil, 1000), bundle("coins_jar", nil, 2750) } })
		local p = readyPlayer(w, 0)
		expect.equal(MonetizationService.validateAllAsync(), 0)
		expect.deepEqual(MonetizationService.offeredBundles(), {})
		MonetizationService.playerAdded(p)
		expect.deepEqual(w.views[#w.views].view, { bundles = {}, passes = {} })
		-- validated ids are still not offered while Grip is on and allowBundlesWithCapsules is false
		local locked = setup({ locked = true })
		offeredFor(locked, { PRODUCT, OTHER_PRODUCT })
		expect.deepEqual(MonetizationService.offeredBundles(), {})
		-- only validated, onSale ids when nothing locks them
		local open = setup({
			bundles = { bundle("coins_handful", PRODUCT, 1000), bundle("coins_jar", OTHER_PRODUCT, 2750, false) },
		})
		open.productInfo[PRODUCT] = { { Creator = { CreatorTargetId = GROUP }, IsForSale = true } }
		open.productInfo[OTHER_PRODUCT] = { { Creator = { CreatorTargetId = GROUP }, IsForSale = true } }
		local q = readyPlayer(open, 0)
		expect.equal(MonetizationService.validateAllAsync(), 2)
		expect.deepEqual(MonetizationService.offeredBundles(), { "coins_handful" })
		expect.deepEqual(open.views[#open.views], { player = q, view = { bundles = { "coins_handful" }, passes = {} } })
		-- the real config ships nothing to offer (every productId nil, G7b)
		for _, b in Config.Monetization.CoinBundles do
			expect.equal(b.productId, nil)
		end
	end)

	t.test(
		"PromptCoinBundle never prompts a bundle that is not offered; PromptGamePass is always unavailable",
		function()
			local w = setup({ locked = true })
			local p = readyPlayer(w, 0)
			offeredFor(w, { PRODUCT })
			expect.equal(MonetizationService.promptBundle(p, "coins_handful"), false)
			expect.equal(MonetizationService.promptBundle(p, "no_such_bundle"), false)
			expect.equal(MonetizationService.promptPass(p, "vip"), false)
			expect.deepEqual(w.prompts, {})
			expect.equal(#w.notices, 3)
			for _, notice in w.notices do
				expect.equal(notice.code, "purchase.unavailable")
			end
			expect.equal(MonetizationService.ownsPass(p, "vip"), false)
			-- an offered bundle prompts the server-side purchase for a ready profile only, never while closing
			local open = setup()
			local q = readyPlayer(open, 0)
			offeredFor(open, { PRODUCT })
			open.closing = true
			expect.equal(MonetizationService.promptBundle(q, "coins_handful"), false)
			open.closing = false
			open.statuses[q] = "offline"
			expect.equal(MonetizationService.promptBundle(q, "coins_handful"), false)
			open.statuses[q] = "ready"
			expect.equal(MonetizationService.promptBundle(q, "coins_handful"), true)
			expect.deepEqual(open.prompts, { { player = q, productId = PRODUCT } })
		end
	)

	t.test(
		"boot validation: the creator group and IsForSale must match; failures are retried, then not offered",
		function()
			local w = setup()
			readyPlayer(w, 0)
			w.productInfo[PRODUCT] = { "error" :: any, { Creator = { CreatorTargetId = GROUP }, IsForSale = true } }
			w.productInfo[OTHER_PRODUCT] = { { Creator = { CreatorTargetId = 12345 }, IsForSale = true } }
			expect.equal(MonetizationService.validateProductAsync(PRODUCT), true)
			expect.equal(#w.waits, 1)
			expect.equal((MonetizationService.validateProductAsync(OTHER_PRODUCT)), false)
			w.productInfo[OTHER_PRODUCT] = { { Creator = { CreatorTargetId = GROUP }, IsForSale = false } }
			expect.equal((MonetizationService.validateProductAsync(OTHER_PRODUCT)), false)
			local before = w.infoCalls
			w.productInfo[OTHER_PRODUCT] = {}
			expect.equal((MonetizationService.validateProductAsync(OTHER_PRODUCT)), false)
			expect.equal(w.infoCalls - before, 1 + Config.Monetization.productInfoRetries)
		end
	)

	t.test("debugSimulateReceipt: Studio only, the fixture bundle through the same core, granted once", function()
		local w = setup({ allowed = false })
		local p, profile = readyPlayer(w, 0)
		expect.equal(MonetizationService.debugSimulateReceipt(p, "SIM-1").ok, false)
		w.allowed = true
		local first = MonetizationService.debugSimulateReceipt(p, "SIM-1")
		expect.equal(first.ok, true)
		expect.equal(first.decision, "PurchaseGranted")
		expect.equal(type(first.coinsAdded), "number")
		expect.equal(first.coinsAdded > 0, true)
		local second = MonetizationService.debugSimulateReceipt(p, "SIM-1")
		expect.equal(second.decision, "PurchaseGranted")
		expect.equal(second.coinsAdded, 0)
		expect.equal(profile.coins, first.coinsAdded)
		expect.equal(#profile.receipts, 1)
		expect.equal(profile.receipts[1].product, 0)
		-- the fixture is never a real product: a real receipt for ProductId 0 is unknown
		expect.equal(MonetizationService.processReceipt(receipt("P9", 0)), NOT_YET)
		expect.equal(Config.Monetization.byProductId[0], nil)
	end)

	t.test("init assigns MarketplaceService.ProcessReceipt", function()
		local w = setup()
		MonetizationService.init()
		expect.equal(w.marketplace.ProcessReceipt, MonetizationService.processReceipt)
	end)
end
