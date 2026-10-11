--!strict
-- ShopService_Test: unit tests for ServerScriptService.Server.Services.ShopService.
-- Server only (ServerStorage.UnitTest). Edit mode: the real EconomyService runs on a fake data port (READY profiles in a
-- table, mutate like DataService), the "now" save, the shutdown flags, the duel lock and both clocks are fakes; players
-- are plain tables. Prices come from the test's Catalog copy; tables are compared by value.
-- Contract (DESIGN §6.6, §3.4, §3.11, §12 #3 #4 #6 #7 #14):
--   * a buy charges shopPrice once (reason "shop"), adds the squishy (src "shop"), appends shopLog {req, squishy,
--     price, at} (cap Config.Data.caps.shopLog), awaits the "now" save and answers {squishyId, charged = true,
--     savePending = not saved};
--   * the same requestId replays the stored result with no charge; an owned squishy answers ok {charged = false};
--   * refusals in the §6.6 order, each with charged = false and no Coin change: net.invalid, shop.notForSale,
--     shop.priceChanged (the client price is only compared), data.notReady, box.saving (savePending), purchase.unavailable
--     (closing / restart), inventory.lockedInDuel, economy.notEnoughCoins;
--   * one buy in flight per player and one charged buy per second (net.rateLimited);
--   * every Catalog price is valid at boot (nothing disabled).

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

return function(t: Context)
	local expect = t.expect
	local ShopService = t.requireServer("Services/ShopService")
	local EconomyService = t.requireServer("Services/EconomyService")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")

	local TOAST = Catalog.get("toast").shopPrice
	local BANANA = Catalog.get("banana").shopPrice

	local function newProfile(coins: number): any
		return {
			coins = coins,
			owned = { kitty_bread = { at = 1, src = "starter" } },
			equipped = "kitty_bread",
			stats = { coinsEarned = 0, coinsSpent = 0, boxesOpened = 0 },
			shopLog = {},
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

	t.test("a buy charges the shop price once, adds the squishy, logs it and awaits the now save", function()
		local w = setup()
		local p, profile = readyPlayer(w, 5000)
		local result = ShopService.buy(p, "toast", TOAST, REQ_A)
		expect.deepEqual(result, { ok = true, data = { squishyId = "toast", charged = true, savePending = false } })
		expect.equal(profile.coins, 5000 - TOAST)
		expect.deepEqual(profile.owned.toast, { at = NOW, src = "shop" })
		expect.deepEqual(profile.shopLog, { { req = REQ_A, squishy = "toast", price = TOAST, at = NOW } })
		expect.equal(profile.stats.coinsSpent, TOAST)
		expect.equal(w.saves, 1)
	end)

	t.test(
		"the same requestId replays the stored result with no second charge; owned answers charged = false",
		function()
			local w = setup()
			local p, profile = readyPlayer(w, 5000)
			ShopService.buy(p, "toast", TOAST, REQ_A)
			w.clock.advance(5)
			local replay = ShopService.buy(p, "toast", TOAST, REQ_A)
			expect.deepEqual(replay, { ok = true, data = { squishyId = "toast", charged = true, savePending = false } })
			local owned = ShopService.buy(p, "toast", TOAST, REQ_B)
			expect.deepEqual(owned, { ok = true, data = { squishyId = "toast", charged = false, savePending = false } })
			expect.equal(profile.coins, 5000 - TOAST)
			expect.equal(#profile.shopLog, 1)
			expect.equal(w.saves, 1)
		end
	)

	t.test("refusals in order, each with charged = false and no Coin change", function()
		local w = setup()
		local p, profile = readyPlayer(w, 5000)
		refused(ShopService.buy(p, "unicorn", 100, REQ_A), "net.invalid")
		refused(ShopService.buy(p, "toast", TOAST, "not-a-guid"), "net.invalid")
		refused(ShopService.buy(p, "kitty_bread", 0, REQ_A), "shop.notForSale")
		refused(ShopService.buy(p, "toast", TOAST - 1, REQ_A), "shop.priceChanged")
		refused(ShopService.buy(p, "toast", TOAST + 0.5, REQ_A), "shop.priceChanged")
		refused(ShopService.buy(p, "toast", tostring(TOAST), REQ_A), "shop.priceChanged")
		refused(ShopService.buy({ UserId = 2 }, "toast", TOAST, REQ_A), "data.notReady") -- no profile yet
		w.statuses[p] = "offline"
		refused(ShopService.buy(p, "toast", TOAST, REQ_A), "data.notReady")
		w.statuses[p] = "ready"
		w.pending[p] = true
		refused(ShopService.buy(p, "toast", TOAST, REQ_A), "box.saving")
		w.pending[p] = nil
		w.closing = true
		refused(ShopService.buy(p, "toast", TOAST, REQ_A), "purchase.unavailable")
		w.closing = false
		w.restart = true
		refused(ShopService.buy(p, "toast", TOAST, REQ_A), "purchase.unavailable")
		w.restart = false
		w.locked[p] = true
		refused(ShopService.buy(p, "toast", TOAST, REQ_A), "inventory.lockedInDuel")
		w.locked[p] = nil
		profile.coins = TOAST - 1
		refused(ShopService.buy(p, "toast", TOAST, REQ_A), "economy.notEnoughCoins")
		expect.equal(profile.coins, TOAST - 1)
		expect.equal(profile.owned.toast, nil)
		expect.deepEqual(profile.shopLog, {})
		expect.equal(w.saves, 0)
	end)

	t.test(
		"a failed now save answers savePending = true, and the next buy waits for a good save (box.saving)",
		function()
			local w = setup()
			local p, profile = readyPlayer(w, 5000)
			w.saveResult = false
			local result = ShopService.buy(p, "toast", TOAST, REQ_A)
			expect.deepEqual(result, { ok = true, data = { squishyId = "toast", charged = true, savePending = true } })
			expect.equal(profile.owned.toast ~= nil, true) -- the change stays in memory (§3.11)
			w.clock.advance(5)
			refused(ShopService.buy(p, "banana", BANANA, REQ_B), "box.saving")
			expect.equal(profile.coins, 5000 - TOAST)
		end
	)

	t.test("one buy in flight per player, and one charged buy per second", function()
		local w = setup()
		local p, profile = readyPlayer(w, 10000)
		local inner: any = nil
		w.onSave = function(player: any)
			if inner == nil then
				inner = ShopService.buy(player, "banana", BANANA, REQ_B) -- arrives while the first awaits its save
			end
		end
		ShopService.buy(p, "toast", TOAST, REQ_A)
		refused(inner, "net.rateLimited")
		w.clock.advance(0.5)
		refused(ShopService.buy(p, "banana", BANANA, REQ_C), "net.rateLimited")
		w.clock.advance(0.5)
		local ok = ShopService.buy(p, "banana", BANANA, REQ_C)
		expect.equal(ok.ok, true)
		expect.equal(profile.coins, 10000 - TOAST - BANANA)
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
		profile.coins = 5000
		ShopService.buy(p, "toast", TOAST, REQ_A)
		expect.equal(#profile.shopLog, cap)
		expect.equal(profile.shopLog[cap].req, REQ_A)
		expect.equal(profile.shopLog[1].at, 2)
	end)

	t.test("every Catalog shop price is valid at boot (nothing is disabled); priceOf reads the Catalog", function()
		setup()
		expect.deepEqual(ShopService.checkPrices(), {})
		expect.equal(ShopService.priceOf("dragon"), Catalog.get("dragon").shopPrice)
		expect.equal(ShopService.priceOf("kitty_bread"), nil)
		expect.equal(ShopService.priceOf("unicorn"), nil)
	end)
end
