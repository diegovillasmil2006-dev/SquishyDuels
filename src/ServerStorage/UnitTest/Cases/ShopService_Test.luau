--!strict
-- ShopService_Test: unit tests for ServerScriptService.Server.Services.ShopService.
-- Server only (ServerStorage.UnitTest). Edit mode: the real EconomyService runs on a fake data port (READY profiles in a
-- table, mutate like DataService), the "now" save, the shutdown flags, the duel lock and both clocks are fakes; players
-- are plain tables. Prices come from the test's Catalog copy; tables are compared by value.
-- Contract (DESIGN §6.6, §3.4, §3.11, §12 #3 #4 #6 #7 #14; pens3 phase 5):
--   * a buy charges Pricing.shopPrice(id, owned) once (reason "shop"): the Welcome price (1,000) for the first of a
--     Common, the Catalog price after that; it adds the squishy (a pen item; src "shop" when the kind is new, a copy
--     when it is owned), appends shopLog {req, squishy, price, at} (cap Config.Data.caps.shopLog), awaits the "now"
--     save and answers {squishyId, charged = true, savePending = not saved};
--   * the same requestId replays the stored result with no charge (whatever the price is now);
--   * refusals in the §6.6 order, each with charged = false and no Coin change: net.invalid, shop.notForSale,
--     shop.priceChanged (the client price is only compared; a Common's full price before the first one is a wrong
--     price too), data.notReady, inventory.full (the Toy Box is full, before any Coins move), box.saving
--     (savePending), purchase.unavailable (closing / restart), inventory.lockedInDuel, economy.notEnoughCoins;
--   * one buy in flight per player and one charged buy per second (net.rateLimited);
--   * every Catalog price is valid at boot (nothing disabled); Dragon's 1.1T price is bought with its exact
--     expectedPrice, above the 1e6 bound of plain integer arguments.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local NOW = 1_790_000_000
local REQ_A = "aaaaaaaa-0000-0000-0000-000000000001"
local REQ_B = "bbbbbbbb-0000-0000-0000-000000000002"
local REQ_C = "cccccccc-0000-0000-0000-000000000003"
local COINS = 1_000_000 -- a few Welcome prices and one full Common price

return function(t: Context)
	local expect = t.expect
	local ShopService = t.requireServer("Services/ShopService")
	local EconomyService = t.requireServer("Services/EconomyService")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")

	local WELCOME = Config.Economy.Pen.welcomePrice.Common -- the first of each Common (D1:202)
	local TOAST = Catalog.get("toast").shopPrice -- every Toast after the first
	local PEN = Config.Economy.Pen

	local function newProfile(coins: number): any
		return {
			coins = coins,
			owned = { kitty_bread = { at = 1, src = "starter" } },
			equipped = "kitty_bread",
			stats = { coinsEarned = 0, coinsSpent = 0, boxesOpened = 0 },
			shopLog = {},
			-- Pens3 phase 5: a pen (a buy adds an item) and the gift queue.
			pen = { spots = 3, nextId = 2, items = { { id = 1, kind = "kitty_bread", form = 0, level = 1, coat = 0 } } },
			giftQueue = {},
		}
	end

	local function setup(): any
		local w: any = {
			profiles = {},
			statuses = {},
			pending = {},
			saves = 0,
			saveResult = true,
			closing = false,
			restart = false,
			locked = {},
			clock = FakeClock.new(100),
			onSave = nil,
		}
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
			savePending = function(player: any): boolean
				return w.pending[player] == true
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
		ShopService.useDeps({
			data = port,
			saveNow = function(player: any): boolean
				w.saves += 1
				if w.onSave then
					w.onSave(player)
				end
				if not w.saveResult then
					w.pending[player] = true
				end
				return w.saveResult
			end,
			economy = EconomyService,
			isClosing = function(): boolean
				return w.closing
			end,
			isRestartPending = function(): boolean
				return w.restart
			end,
			isLocked = function(player: any): boolean
				return w.locked[player] == true
			end,
			now = function(): number
				return NOW
			end,
			clock = w.clock.now,
		})
		return w
	end

	local function readyPlayer(w: any, coins: number, userId: number?): (any, any)
		local player = { UserId = userId or 1 }
		local profile = newProfile(coins)
		w.profiles[player] = profile
		w.statuses[player] = "ready"
		return player, profile
	end

	local function refused(result: any, reason: string)
		expect.deepEqual(result, { ok = false, reason = reason, charged = false })
	end

	t.test("the first of a Common costs the Welcome price; it is added, logged and the now save is awaited", function()
		local w = setup()
		local p, profile = readyPlayer(w, COINS)
		expect.equal(WELCOME, 1_000) -- owner 2026-10-31: 3K -> 1K
		local result = ShopService.buy(p, "toast", WELCOME, REQ_A)
		expect.deepEqual(result, { ok = true, data = { squishyId = "toast", charged = true, savePending = false } })
		expect.equal(profile.coins, COINS - WELCOME)
		expect.deepEqual(profile.owned.toast, { at = NOW, src = "shop" })
		expect.equal(profile.pen.items[2].kind, "toast") -- it walks in the pen
		expect.deepEqual(profile.shopLog, { { req = REQ_A, squishy = "toast", price = WELCOME, at = NOW } })
		expect.equal(profile.stats.coinsSpent, WELCOME)
		expect.equal(w.saves, 1)
	end)

	t.test("once owned, a Common costs its full price and buys a copy; a replay is never charged twice", function()
		local w = setup()
		local p, profile = readyPlayer(w, COINS)
		ShopService.buy(p, "toast", WELCOME, REQ_A)
		w.clock.advance(5)
		local replay = ShopService.buy(p, "toast", WELCOME, REQ_A)
		expect.deepEqual(replay, { ok = true, data = { squishyId = "toast", charged = true, savePending = false } })
		expect.equal(profile.coins, COINS - WELCOME)
		refused(ShopService.buy(p, "toast", WELCOME, REQ_B), "shop.priceChanged") -- the Welcome price is used up
		expect.equal(TOAST, 789_000)
		local copy = ShopService.buy(p, "toast", TOAST, REQ_B)
		expect.deepEqual(copy, { ok = true, data = { squishyId = "toast", charged = true, savePending = false } })
		expect.equal(profile.coins, COINS - WELCOME - TOAST)
		expect.deepEqual(profile.owned.toast, { at = NOW, src = "shop" })
		expect.equal(#profile.pen.items, 3) -- Kitty Bread and two Toasts
		expect.equal(#profile.shopLog, 2)
		expect.equal(w.saves, 2)
	end)

	t.test("refusals in order, each with charged = false and no Coin change", function()
		local w = setup()
		local p, profile = readyPlayer(w, COINS)
		refused(ShopService.buy(p, "unicorn", 100, REQ_A), "net.invalid")
		refused(ShopService.buy(p, "toast", WELCOME, "not-a-guid"), "net.invalid")
		refused(ShopService.buy(p, "kitty_bread", 0, REQ_A), "shop.notForSale")
		refused(ShopService.buy(p, "toast", WELCOME - 1, REQ_A), "shop.priceChanged")
		refused(ShopService.buy(p, "toast", WELCOME + 0.5, REQ_A), "shop.priceChanged")
		refused(ShopService.buy(p, "toast", tostring(WELCOME), REQ_A), "shop.priceChanged")
		refused(ShopService.buy(p, "toast", TOAST, REQ_A), "shop.priceChanged") -- not owned: the Welcome price is due
		refused(ShopService.buy({ UserId = 2 }, "toast", WELCOME, REQ_A), "data.notReady") -- no profile yet
		w.statuses[p] = "offline"
		refused(ShopService.buy(p, "toast", WELCOME, REQ_A), "data.notReady")
		w.statuses[p] = "ready"
		-- Pens3 phase 5: a full Toy Box, before any Coins move.
		local items = profile.pen.items
		for i = #items + 1, profile.pen.spots + PEN.toyBoxMax do
			table.insert(items, { id = i, kind = "banana", form = 0, level = 1, coat = 0 })
		end
		profile.pen.nextId = #items + 1
		profile.owned.banana = { at = 1, src = "box" }
		refused(ShopService.buy(p, "toast", WELCOME, REQ_A), "inventory.full")
		table.remove(items) -- room for one again
		w.pending[p] = true
		refused(ShopService.buy(p, "toast", WELCOME, REQ_A), "box.saving")
		w.pending[p] = nil
		w.closing = true
		refused(ShopService.buy(p, "toast", WELCOME, REQ_A), "purchase.unavailable")
		w.closing = false
		w.restart = true
		refused(ShopService.buy(p, "toast", WELCOME, REQ_A), "purchase.unavailable")
		w.restart = false
		w.locked[p] = true
		refused(ShopService.buy(p, "toast", WELCOME, REQ_A), "inventory.lockedInDuel")
		w.locked[p] = nil
		profile.coins = WELCOME - 1
		refused(ShopService.buy(p, "toast", WELCOME, REQ_A), "economy.notEnoughCoins")
		expect.equal(profile.coins, WELCOME - 1)
		expect.equal(profile.owned.toast, nil)
		expect.deepEqual(profile.shopLog, {})
		expect.deepEqual(profile.giftQueue, {}) -- a buy never waits in the queue
		expect.equal(w.saves, 0)
	end)

	t.test(
		"a failed now save answers savePending = true, and the next buy waits for a good save (box.saving)",
		function()
			local w = setup()
			local p, profile = readyPlayer(w, COINS)
			w.saveResult = false
			local result = ShopService.buy(p, "toast", WELCOME, REQ_A)
			expect.deepEqual(result, { ok = true, data = { squishyId = "toast", charged = true, savePending = true } })
			expect.equal(profile.owned.toast ~= nil, true) -- the change stays in memory (§3.11)
			w.clock.advance(5)
			refused(ShopService.buy(p, "banana", WELCOME, REQ_B), "box.saving")
			expect.equal(profile.coins, COINS - WELCOME)
		end
	)

	t.test("one buy in flight per player, and one charged buy per second", function()
		local w = setup()
		local p, profile = readyPlayer(w, COINS)
		local inner: any = nil
		w.onSave = function(player: any)
			if inner == nil then
				inner = ShopService.buy(player, "banana", WELCOME, REQ_B) -- arrives while the first awaits its save
			end
		end
		ShopService.buy(p, "toast", WELCOME, REQ_A)
		refused(inner, "net.rateLimited")
		w.clock.advance(0.5)
		refused(ShopService.buy(p, "banana", WELCOME, REQ_C), "net.rateLimited")
		w.clock.advance(0.5)
		local ok = ShopService.buy(p, "banana", WELCOME, REQ_C)
		expect.equal(ok.ok, true)
		expect.equal(profile.coins, COINS - 2 * WELCOME)
	end)

	t.test("shopLog keeps the newest Config.Data.caps.shopLog entries", function()
		local w = setup()
		local p, profile = readyPlayer(w, 0)
		local cap = Config.Data.caps.shopLog
		for i = 1, cap do
			table.insert(
				profile.shopLog,
				{ req = string.format("%08x-0000-0000-0000-000000000000", i), squishy = "x", price = 1, at = i }
			)
		end
		profile.coins = COINS
		ShopService.buy(p, "toast", WELCOME, REQ_A)
		expect.equal(#profile.shopLog, cap)
		expect.equal(profile.shopLog[cap].req, REQ_A)
		expect.equal(profile.shopLog[1].at, 2)
	end)

	t.test("Dragon's 1.1T price is bought with its exact expectedPrice (a Coin amount, not a 1e6 integer)", function()
		local w = setup()
		local dragon = Catalog.get("dragon").shopPrice
		expect.equal(dragon, 1_100_000_000_000)
		local p, profile = readyPlayer(w, dragon)
		local result = ShopService.buy(p, "dragon", dragon, REQ_A)
		expect.deepEqual(result, { ok = true, data = { squishyId = "dragon", charged = true, savePending = false } })
		expect.equal(profile.coins, 0)
	end)

	t.test("every Catalog shop price is valid at boot (nothing is disabled); priceOf reads the Catalog", function()
		setup()
		expect.deepEqual(ShopService.checkPrices(), {})
		expect.equal(ShopService.priceOf("dragon"), Catalog.get("dragon").shopPrice)
		expect.equal(ShopService.priceOf("kitty_bread"), nil)
		expect.equal(ShopService.priceOf("unicorn"), nil)
	end)
end
