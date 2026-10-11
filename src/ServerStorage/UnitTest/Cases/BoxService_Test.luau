--!strict
-- BoxService_Test: unit tests for ServerScriptService.Server.Services.BoxService.
-- Server only (ServerStorage.UnitTest). Edit mode: the real EconomyService runs on a fake data port (READY profiles in a
-- table, mutate like DataService), the "now" save, the policy gate, the shutdown flags, the duel lock, both clocks and
-- the rng (a scripted NextInteger) are fakes; players are plain tables. Boxes, costs and refunds come from the test's
-- Shared copy; tables are compared by value.
-- Contract (DESIGN §6.4, §6.5, §3.4, §3.11, §12 #14 #17):
--   * an open charges the box cost once (reason "box"), draws once with the server rng, grants the squishy (src "box")
--     or refunds a duplicate by rarity (reason "refund"), appends boxLog {req, box, squishy, dup, refund, cost, at,
--     seen = false} (cap Config.Data.caps.boxLog), counts stats.boxesOpened, marks unseenReveals, awaits the "now"
--     save and answers {squishyId, isDuplicate, refund, savePending = not saved};
--   * the same requestId replays the stored result: no charge, no draw, no save;
--   * refusals in the §6.4 order, each charged = false with no Coin change and no draw: net.invalid (bad id, unknown or
--     free-only box), data.notReady, box.restricted (policy not eligible), box.paused (closing / restart), box.saving
--     (savePending), inventory.lockedInDuel, box.complete, economy.notEnoughCoins;
--   * MinSecondsBetweenOpens (2 s) and one open in flight (net.rateLimited);
--   * AckReveal: an unseen entry becomes seen once (markDirty + "soon" save), nothing else changes;
--   * grantFree: the Treat Box with no cost and no policy check, idempotent by "daily:<day>", seen = false, no save;
--   * the shipped boxes pass the boot check.

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
-- Snack Box draws (spec 2026-10-09 §3.3 cumulative weights: toast 1600, banana 3200, boba_bear 4800, pancake_pup
-- 6400, butter 7150, chocolate 7900, mochi_fox 8650, strawberry_frog 9400, bird 9550, donut 9700, cloud_bunny 9850,
-- cupcake_axolotl 10000).
local R_TOAST = 1
local R_BANANA = 1601
local R_BUTTER = 6401

return function(t: Context)
	local expect = t.expect
	local BoxService = t.requireServer("Services/BoxService")
	local EconomyService = t.requireServer("Services/EconomyService")
	local Boxes = t.requireShared("Boxes")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")

	local SNACK = Boxes.get("snack")
	local SNACK_COST = SNACK.cost
	local COMMON_REFUND = Config.Economy.DuplicateRefund.Common
	local MIN_SECONDS = Config.Economy.MinSecondsBetweenOpens

	local function newProfile(coins: number): any
		return {
			coins = coins,
			owned = { kitty_bread = { at = 1, src = "starter" } },
			equipped = "kitty_bread",
			stats = { coinsEarned = 0, coinsSpent = 0, boxesOpened = 0 },
			boxLog = {},
		}
	end

	local function setup(): any
		local w: any = {
			profiles = {},
			statuses = {},
			pending = {},
			policy = {},
			locked = {},
			closing = false,
			restart = false,
			saves = 0,
			saveResult = true,
			soonSaves = 0,
			dirty = {},
			draws = 0,
			rolls = {},
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
			requestSave = function(_player: any, reason: string)
				if reason == "soon" then
					w.soonSaves += 1
				end
			end,
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
		local rng = {
			NextInteger = function(_self: any, low: number, high: number): number
				w.draws += 1
				local r = table.remove(w.rolls, 1) or low
				assert(r >= low and r <= high, "scripted roll outside the range")
				return r
			end,
		}
		BoxService.useDeps({
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
			canBuyPaidRandom = function(player: any): boolean
				return w.policy[player] ~= false
			end,
			isClosing = function(): boolean
				return w.closing
			end,
			isRestartPending = function(): boolean
				return w.restart
			end,
			isLocked = function(player: any): boolean
				return w.locked[player] == true
			end,
			markDirty = function(_player: any, field: string)
				w.dirty[field] = (w.dirty[field] or 0) + 1
			end,
			now = function(): number
				return NOW
			end,
			clock = w.clock.now,
			rng = rng,
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

	t.test("an open charges the cost once, draws once, grants, logs, counts and awaits the now save", function()
		local w = setup()
		local p, profile = readyPlayer(w, 1000)
		w.rolls = { R_BANANA }
		local result = BoxService.open(p, "snack", REQ_A)
		expect.deepEqual(result, {
			ok = true,
			data = { squishyId = "banana", isDuplicate = false, refund = 0, savePending = false },
		})
		expect.equal(profile.coins, 1000 - SNACK_COST)
		expect.deepEqual(profile.owned.banana, { at = NOW, src = "box" })
		expect.deepEqual(profile.boxLog, {
			{
				req = REQ_A,
				box = "snack",
				squishy = "banana",
				dup = false,
				refund = 0,
				cost = SNACK_COST,
				at = NOW,
				seen = false,
			},
		})
		expect.equal(profile.stats.boxesOpened, 1)
		expect.equal(profile.stats.coinsSpent, SNACK_COST)
		expect.equal(w.draws, 1)
		expect.equal(w.saves, 1)
		expect.equal(w.dirty.unseenReveals, 1)
	end)

	t.test("the same requestId replays the stored result: no charge, no draw, no save", function()
		local w = setup()
		local p, profile = readyPlayer(w, 1000)
		w.rolls = { R_TOAST }
		local first = BoxService.open(p, "snack", REQ_A)
		w.clock.advance(MIN_SECONDS + 0.2)
		local again = BoxService.open(p, "snack", REQ_A)
		expect.deepEqual(again, first)
		expect.equal(profile.coins, 1000 - SNACK_COST)
		expect.equal(#profile.boxLog, 1)
		expect.equal(profile.stats.boxesOpened, 1)
		expect.equal(w.draws, 1)
		expect.equal(w.saves, 1)
	end)

	t.test(
		"a duplicate is refunded by rarity (reason refund) and logged dup = true; the cost is still charged",
		function()
			local w = setup()
			local p, profile = readyPlayer(w, 1000)
			profile.owned.toast = { at = 5, src = "shop" }
			w.rolls = { R_TOAST }
			local result = BoxService.open(p, "snack", REQ_A)
			expect.deepEqual(
				result.data,
				{ squishyId = "toast", isDuplicate = true, refund = COMMON_REFUND, savePending = false }
			)
			expect.equal(profile.coins, 1000 - SNACK_COST + COMMON_REFUND)
			expect.deepEqual(profile.owned.toast, { at = 5, src = "shop" })
			expect.equal(profile.boxLog[1].dup, true)
			expect.equal(profile.boxLog[1].refund, COMMON_REFUND)
			expect.equal(true, COMMON_REFUND < SNACK_COST) -- opening can never earn Coins (§6.5)
		end
	)

	t.test("refusals in the §6.4 order, each charged = false with no Coin change and no draw", function()
		local w = setup()
		local p, profile = readyPlayer(w, 1000)
		refused(BoxService.open(p, "snack", "nope"), "net.invalid")
		refused(BoxService.open({ UserId = 2 }, "snack", REQ_A), "data.notReady")
		w.statuses[p] = "offline"
		refused(BoxService.open(p, "snack", REQ_A), "data.notReady")
		w.statuses[p] = "ready"
		refused(BoxService.open(p, "mystery", REQ_A), "net.invalid")
		refused(BoxService.open(p, "treat", REQ_A), "net.invalid") -- free-only: never opened with Coins
		w.policy[p] = false
		refused(BoxService.open(p, "snack", REQ_A), "box.restricted")
		w.policy[p] = nil
		w.closing = true
		refused(BoxService.open(p, "snack", REQ_A), "box.paused")
		w.closing = false
		w.restart = true
		refused(BoxService.open(p, "snack", REQ_A), "box.paused")
		w.restart = false
		w.pending[p] = true
		refused(BoxService.open(p, "snack", REQ_A), "box.saving")
		w.pending[p] = nil
		w.locked[p] = true
		refused(BoxService.open(p, "snack", REQ_A), "inventory.lockedInDuel")
		w.locked[p] = nil
		profile.coins = SNACK_COST - 1
		refused(BoxService.open(p, "snack", REQ_A), "economy.notEnoughCoins")
		for _, item in SNACK.items do
			profile.owned[item.id] = { at = 1, src = "grant" }
		end
		profile.coins = 1000
		refused(BoxService.open(p, "snack", REQ_A), "box.complete")
		expect.equal(profile.coins, 1000)
		expect.deepEqual(profile.boxLog, {})
		expect.equal(profile.stats.boxesOpened, 0)
		expect.equal(w.draws, 0)
		expect.equal(w.saves, 0)
	end)

	t.test(
		"a failed now save answers savePending = true, keeps the change and blocks the next open (box.saving)",
		function()
			local w = setup()
			local p, profile = readyPlayer(w, 1000)
			w.saveResult = false
			w.rolls = { R_BUTTER }
			local result = BoxService.open(p, "snack", REQ_A)
			expect.deepEqual(result.data, { squishyId = "butter", isDuplicate = false, refund = 0, savePending = true })
			expect.equal(profile.owned.butter ~= nil, true)
			w.clock.advance(MIN_SECONDS + 1)
			refused(BoxService.open(p, "snack", REQ_B), "box.saving")
			-- a replay of the first request still answers its stored result, with the current savePending
			expect.deepEqual(BoxService.open(p, "snack", REQ_A).data, result.data)
			expect.equal(profile.coins, 1000 - SNACK_COST)
		end
	)

	t.test("MinSecondsBetweenOpens and one open in flight answer net.rateLimited", function()
		local w = setup()
		local p, profile = readyPlayer(w, 5000)
		local inner: any = nil
		w.onSave = function(player: any)
			if inner == nil then
				inner = BoxService.open(player, "snack", REQ_C)
			end
		end
		w.rolls = { R_TOAST, R_BANANA }
		expect.equal(BoxService.open(p, "snack", REQ_A).ok, true)
		refused(inner, "net.rateLimited")
		w.clock.advance(MIN_SECONDS - 0.1)
		refused(BoxService.open(p, "snack", REQ_B), "net.rateLimited")
		w.clock.advance(0.1)
		expect.equal(BoxService.open(p, "snack", REQ_B).ok, true)
		expect.equal(profile.coins, 5000 - 2 * SNACK_COST)
		expect.equal(w.draws, 2)
	end)

	t.test("AckReveal marks an unseen entry seen once, with markDirty and a soon save", function()
		local w = setup()
		local p, profile = readyPlayer(w, 1000)
		w.rolls = { R_TOAST }
		BoxService.open(p, "snack", REQ_A)
		local dirtyBefore = w.dirty.unseenReveals
		expect.equal(BoxService.ackReveal(p, REQ_A), true)
		expect.equal(profile.boxLog[1].seen, true)
		expect.equal(w.dirty.unseenReveals, dirtyBefore + 1)
		expect.equal(w.soonSaves, 1)
		expect.equal(BoxService.ackReveal(p, REQ_A), false) -- already seen
		expect.equal(BoxService.ackReveal(p, REQ_B), false) -- unknown
		expect.equal(BoxService.ackReveal(p, "daily:x"), false) -- invalid id
		expect.equal(w.soonSaves, 1)
		expect.equal(profile.coins, 1000 - SNACK_COST) -- no economic effect
	end)

	t.test("grantFree: the Treat Box with no cost and no policy check, idempotent by daily:<day>, no save", function()
		local w = setup()
		local p, profile = readyPlayer(w, 0)
		w.policy[p] = false -- the Treat Box is not a paid random item
		w.rolls = { 1 }
		local result = BoxService.grantFree(p, "treat", "daily:20000")
		expect.deepEqual(result, { squishyId = "toast", isDuplicate = false, refund = 0, savePending = false })
		expect.equal(profile.coins, 0)
		expect.deepEqual(profile.boxLog[1], {
			req = "daily:20000",
			box = "treat",
			squishy = "toast",
			dup = false,
			refund = 0,
			cost = 0,
			at = NOW,
			seen = false,
		})
		expect.equal(profile.stats.boxesOpened, 1)
		expect.deepEqual(BoxService.grantFree(p, "treat", "daily:20000"), result) -- replay: no second draw
		expect.equal(w.draws, 1)
		expect.equal(w.saves, 0) -- the daily claim saves "now" itself
		expect.equal(BoxService.grantFree(p, "snack", "daily:20001"), nil) -- a paid box is never free
		expect.equal(BoxService.grantFree(p, "treat", "free please"), nil)
		w.statuses[p] = "offline"
		expect.equal(BoxService.grantFree(p, "treat", "daily:20002"), nil)
		expect.equal(#profile.boxLog, 1)
	end)

	t.test("boxLog keeps the newest Config.Data.caps.boxLog entries", function()
		local w = setup()
		local p, profile = readyPlayer(w, 1000)
		local cap = Config.Data.caps.boxLog
		for i = 1, cap do
			table.insert(profile.boxLog, {
				req = string.format("%08x-0000-0000-0000-000000000000", i),
				box = "snack",
				squishy = "toast",
				dup = false,
				refund = 0,
				cost = SNACK_COST,
				at = i,
				seen = true,
			})
		end
		w.rolls = { R_TOAST }
		BoxService.open(p, "snack", REQ_A)
		expect.equal(#profile.boxLog, cap)
		expect.equal(profile.boxLog[cap].req, REQ_A)
		expect.equal(profile.boxLog[1].at, 2)
	end)

	t.test("the shipped boxes pass the boot check; every drawn id is in the Catalog", function()
		setup()
		expect.deepEqual(BoxService.checkBoxes(), {})
		for _, box in Boxes.list() do
			for _, item in box.items do
				expect.equal(Catalog.isValidId(item.id), true)
			end
		end
	end)
end
