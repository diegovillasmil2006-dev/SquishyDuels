--!strict
-- BoxService_Test: unit tests for ServerScriptService.Server.Services.BoxService.
-- Server only (ServerStorage.UnitTest). Edit mode: the real EconomyService runs on a fake data port (READY profiles in a
-- table, mutate like DataService), the "now" save, the policy gate, the shutdown flags, the duel lock, both clocks and
-- the rng (a scripted NextInteger) are fakes; players are plain tables. Boxes and costs come from the test's Shared
-- copy; tables are compared by value.
-- Contract (DESIGN §6.4, §6.5, §3.4, §3.11, §12 #14 #17; pens3 phase 5):
--   * an open charges the box cost once (reason "box"), draws once with the server rng, grants the squishy (a pen
--     item; src "box" when the kind is new, a copy when it is owned: never Coins back), appends boxLog {req, box,
--     squishy, dup, cost, at, seen = false} (cap Config.Data.caps.boxLog), counts stats.boxesOpened, marks
--     unseenReveals, awaits the "now" save and answers {squishyId, isDuplicate, savePending = not saved};
--   * the same requestId replays the stored result: no charge, no draw, no save;
--   * refusals in the §6.4 order, each charged = false with no Coin change and no draw: net.invalid (bad id, unknown or
--     free-only box), data.notReady, box.paused (closing / restart), box.saving (savePending), inventory.lockedInDuel,
--     inventory.full (the Toy Box holds toyBoxMax unplaced squishies, checked before any Coins move),
--     economy.notEnoughCoins;
--   * restricted accounts (the policy gate is not "eligible": restricted, checking or unknown) are never refused and
--     never drawn at random: the open charges the same price and gives Boxes.fixedItem(box, boxOrder[box]), and
--     boxOrder[box] + 1 in the same steps (Soft: Mochi Fox at box 11, Strawberry Frog at 12); an eligible open never
--     moves the count;
--   * MinSecondsBetweenOpens (2 s) and one open in flight (net.rateLimited);
--   * AckReveal: an unseen entry becomes seen once (markDirty + "soon" save), nothing else changes;
--   * grantFree: the Treat Box with no cost and no policy check (random even for a restricted account: it is free),
--     idempotent by "daily:<day>", seen = false, no save; with a full Toy Box its squishy waits in profile.giftQueue;
--   * the shipped boxes pass the boot check (each paid box has its fixed order).

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
-- Soft Box draws (pens3 phase 5 cumulative weights: toast 1900, banana 3800, boba_bear 5700, pancake_pup 7600, butter
-- 8400, chocolate 9200, mochi_fox 9600, strawberry_frog 10000).
local R_TOAST = 1
local R_BANANA = 1901
local R_BUTTER = 7601
local COINS = 1_000_000 -- a few Snack Boxes (150,000 each)

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
	local MIN_SECONDS = Config.Economy.MinSecondsBetweenOpens
	local PEN = Config.Economy.Pen

	local function newProfile(coins: number): any
		return {
			coins = coins,
			owned = { kitty_bread = { at = 1, src = "starter" } },
			equipped = "kitty_bread",
			stats = { coinsEarned = 0, coinsSpent = 0, boxesOpened = 0 },
			boxLog = {},
			-- Pens3 phase 5: a pen (grants add items), the gift queue and the fixed-order counts.
			pen = { spots = 3, nextId = 2, items = { { id = 1, kind = "kitty_bread", form = 0, level = 1, coat = 0 } } },
			giftQueue = {},
			boxOrder = { snack = 0, sweet = 0 },
		}
	end

	-- Fills the Toy Box: spots + toyBoxMax items in all (PenMath.room 0).
	local function fillToyBox(profile: any)
		local pen = profile.pen
		while #pen.items < pen.spots + PEN.toyBoxMax do
			table.insert(pen.items, { id = pen.nextId, kind = "toast", form = 0, level = 1, coat = 0 })
			pen.nextId += 1
		end
		profile.owned.toast = { at = 1, src = "box" }
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
		local p, profile = readyPlayer(w, COINS)
		w.rolls = { R_BANANA }
		local result = BoxService.open(p, "snack", REQ_A)
		expect.deepEqual(result, {
			ok = true,
			data = { squishyId = "banana", isDuplicate = false, savePending = false },
		})
		expect.equal(profile.coins, COINS - SNACK_COST)
		expect.deepEqual(profile.owned.banana, { at = NOW, src = "box" })
		expect.equal(profile.pen.items[2].kind, "banana") -- it walks in the pen
		expect.deepEqual(profile.boxLog, {
			{
				req = REQ_A,
				box = "snack",
				squishy = "banana",
				dup = false,
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
		expect.deepEqual(profile.boxOrder, { snack = 0, sweet = 0 }) -- a random open never moves the fixed order
	end)

	t.test("the same requestId replays the stored result: no charge, no draw, no save", function()
		local w = setup()
		local p, profile = readyPlayer(w, COINS)
		w.rolls = { R_TOAST }
		local first = BoxService.open(p, "snack", REQ_A)
		w.clock.advance(MIN_SECONDS + 0.2)
		local again = BoxService.open(p, "snack", REQ_A)
		expect.deepEqual(again, first)
		expect.equal(profile.coins, COINS - SNACK_COST)
		expect.equal(#profile.boxLog, 1)
		expect.equal(profile.stats.boxesOpened, 1)
		expect.equal(w.draws, 1)
		expect.equal(w.saves, 1)
	end)

	t.test("a squishy owned already is a copy: one more pen item, dup = true, no Coins back", function()
		local w = setup()
		local p, profile = readyPlayer(w, COINS)
		profile.owned.toast = { at = 5, src = "shop" }
		w.rolls = { R_TOAST }
		local result = BoxService.open(p, "snack", REQ_A)
		expect.deepEqual(result.data, { squishyId = "toast", isDuplicate = true, savePending = false })
		expect.equal(profile.coins, COINS - SNACK_COST)
		expect.deepEqual(profile.owned.toast, { at = 5, src = "shop" })
		expect.equal(#profile.pen.items, 2)
		expect.equal(profile.pen.items[2].kind, "toast")
		expect.equal(profile.boxLog[1].dup, true)
		expect.equal(profile.boxLog[1].refund, nil)
	end)

	t.test("refusals in the §6.4 order, each charged = false with no Coin change and no draw", function()
		local w = setup()
		local p, profile = readyPlayer(w, COINS)
		refused(BoxService.open(p, "snack", "nope"), "net.invalid")
		refused(BoxService.open({ UserId = 2 }, "snack", REQ_A), "data.notReady")
		w.statuses[p] = "offline"
		refused(BoxService.open(p, "snack", REQ_A), "data.notReady")
		w.statuses[p] = "ready"
		refused(BoxService.open(p, "mystery", REQ_A), "net.invalid")
		refused(BoxService.open(p, "treat", REQ_A), "net.invalid") -- free-only: never opened with Coins
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
		-- Pens3 phase 5: a full Toy Box is refused before any Coins move (a restricted account too).
		fillToyBox(profile)
		refused(BoxService.open(p, "snack", REQ_A), "inventory.full")
		w.policy[p] = false
		refused(BoxService.open(p, "snack", REQ_A), "inventory.full")
		w.policy[p] = nil
		expect.equal(profile.coins, COINS)
		profile.pen.spots += 1 -- a spot bought: room for one
		profile.coins = SNACK_COST - 1
		refused(BoxService.open(p, "snack", REQ_A), "economy.notEnoughCoins")
		expect.equal(profile.coins, SNACK_COST - 1)
		expect.deepEqual(profile.boxLog, {})
		expect.equal(profile.stats.boxesOpened, 0)
		expect.deepEqual(profile.giftQueue, {}) -- a paid open never queues
		expect.deepEqual(profile.boxOrder, { snack = 0, sweet = 0 })
		expect.equal(w.draws, 0)
		expect.equal(w.saves, 0)
	end)

	t.test("restricted accounts open the fixed order: no draw, the same price, Fox at 11, Frog at 12", function()
		local w = setup()
		local p, profile = readyPlayer(w, 30 * SNACK_COST)
		w.policy[p] = false -- restricted, checking or unknown: anything but eligible
		profile.pen.spots = 12 -- room for every one
		local got: { string } = {}
		for n = 1, 12 do
			local req = string.format("%08x-0000-0000-0000-000000000000", n)
			local result = BoxService.open(p, "snack", req)
			expect.equal(result.ok, true)
			table.insert(got, result.data.squishyId)
			expect.equal(profile.boxOrder.snack, n) -- counted in the same steps as the grant
			w.clock.advance(MIN_SECONDS)
		end
		for index, id in got do
			expect.equal(id, Boxes.fixedItem("snack", index - 1))
		end
		expect.equal(got[11], "mochi_fox")
		expect.equal(got[12], "strawberry_frog")
		expect.equal(w.draws, 0) -- never random
		expect.equal(profile.coins, 18 * SNACK_COST) -- the same price as everyone
		expect.equal(profile.boxOrder.sweet, 0)
		-- A replay is the stored result and never moves the order.
		local replay = BoxService.open(p, "snack", string.format("%08x-0000-0000-0000-000000000000", 12))
		expect.equal(replay.data.squishyId, "strawberry_frog")
		expect.equal(profile.boxOrder.snack, 12)
		-- Once eligible, opens are random again and the count stays where it was.
		w.policy[p] = nil
		w.rolls = { R_BUTTER }
		expect.equal(BoxService.open(p, "snack", REQ_A).data.squishyId, "butter")
		expect.equal(profile.boxOrder.snack, 12)
		expect.equal(w.draws, 1)
	end)

	t.test("the Sweet Box's fixed order gives its Dragon at box 501 to a restricted account", function()
		local w = setup()
		local p, profile = readyPlayer(w, Config.Economy.maxCoins)
		w.policy[p] = false
		profile.boxOrder.sweet = 500 -- 500 opened before
		local result = BoxService.open(p, "sweet", REQ_A)
		expect.equal(result.data.squishyId, "dragon")
		expect.equal(profile.boxOrder.sweet, 501)
		expect.equal(w.draws, 0)
	end)

	t.test(
		"a failed now save answers savePending = true, keeps the change and blocks the next open (box.saving)",
		function()
			local w = setup()
			local p, profile = readyPlayer(w, COINS)
			w.saveResult = false
			w.rolls = { R_BUTTER }
			local result = BoxService.open(p, "snack", REQ_A)
			expect.deepEqual(result.data, { squishyId = "butter", isDuplicate = false, savePending = true })
			expect.equal(profile.owned.butter ~= nil, true)
			w.clock.advance(MIN_SECONDS + 1)
			refused(BoxService.open(p, "snack", REQ_B), "box.saving")
			-- a replay of the first request still answers its stored result, with the current savePending
			expect.deepEqual(BoxService.open(p, "snack", REQ_A).data, result.data)
			expect.equal(profile.coins, COINS - SNACK_COST)
		end
	)

	t.test("MinSecondsBetweenOpens and one open in flight answer net.rateLimited", function()
		local w = setup()
		local p, profile = readyPlayer(w, COINS)
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
		expect.equal(profile.coins, COINS - 2 * SNACK_COST)
		expect.equal(w.draws, 2)
	end)

	t.test("AckReveal marks an unseen entry seen once, with markDirty and a soon save", function()
		local w = setup()
		local p, profile = readyPlayer(w, COINS)
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
		expect.equal(profile.coins, COINS - SNACK_COST) -- no economic effect
	end)

	t.test("grantFree: the Treat Box with no cost and no policy check, idempotent by daily:<day>, no save", function()
		local w = setup()
		local p, profile = readyPlayer(w, 0)
		w.policy[p] = false -- the Treat Box is not a paid random item: random for everyone
		w.rolls = { 1 }
		local result = BoxService.grantFree(p, "treat", "daily:20000")
		expect.deepEqual(result, { squishyId = "toast", isDuplicate = false, savePending = false })
		expect.equal(profile.coins, 0)
		expect.deepEqual(profile.boxLog[1], {
			req = "daily:20000",
			box = "treat",
			squishy = "toast",
			dup = false,
			cost = 0,
			at = NOW,
			seen = false,
		})
		expect.equal(profile.stats.boxesOpened, 1)
		expect.deepEqual(BoxService.grantFree(p, "treat", "daily:20000"), result) -- replay: no second draw
		expect.equal(w.draws, 1)
		expect.equal(w.saves, 0) -- the daily claim saves "now" itself
		expect.deepEqual(profile.boxOrder, { snack = 0, sweet = 0 })
		expect.equal(BoxService.grantFree(p, "snack", "daily:20001"), nil) -- a paid box is never free
		expect.equal(BoxService.grantFree(p, "treat", "free please"), nil)
		w.statuses[p] = "offline"
		expect.equal(BoxService.grantFree(p, "treat", "daily:20002"), nil)
		expect.equal(#profile.boxLog, 1)
	end)

	t.test("grantFree with a full Toy Box: the squishy waits in the gift queue, the reveal still plays", function()
		local w = setup()
		local p, profile = readyPlayer(w, 0)
		fillToyBox(profile)
		local items = #profile.pen.items
		w.rolls = { Boxes.WeightTotal } -- the last Treat item: cupcake_axolotl
		local result = BoxService.grantFree(p, "treat", "daily:20000")
		expect.deepEqual(result, { squishyId = "cupcake_axolotl", isDuplicate = false, savePending = false })
		expect.deepEqual(profile.giftQueue, { "cupcake_axolotl" })
		expect.equal(profile.owned.cupcake_axolotl, nil) -- owned once it drops in
		expect.equal(#profile.pen.items, items)
		expect.equal(profile.boxLog[1].squishy, "cupcake_axolotl")
	end)

	t.test("boxLog keeps the newest Config.Data.caps.boxLog entries", function()
		local w = setup()
		local p, profile = readyPlayer(w, COINS)
		local cap = Config.Data.caps.boxLog
		for i = 1, cap do
			table.insert(profile.boxLog, {
				req = string.format("%08x-0000-0000-0000-000000000000", i),
				box = "snack",
				squishy = "toast",
				dup = false,
				refund = 0, -- an entry from before pens3 phase 5
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
			if box.paid then
				expect.truthy(Boxes.fixedItem(box.id, 0) ~= nil) -- restricted accounts can open every paid box
			end
		end
	end)
end
