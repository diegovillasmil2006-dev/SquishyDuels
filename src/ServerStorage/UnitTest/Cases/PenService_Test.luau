--!strict
-- PenService_Test: unit tests for ServerScriptService.Server.Services.PenService with injected fakes (a fake data
-- port over plain profiles, recorders for Coins, spends, saves and redraws; players are plain tables; a fake clock).
-- Server only (ServerStorage.UnitTest). Edit mode: init() and start() are never called; ticks run through step(dt).
-- Contract (work/pens3/PLAN.md phase 1):
--   * the tick: each READY player in the server is paid PenMath.payStep of the pen's rate for the real dt (whole
--     Coins, the rest carried), in ONE grantCoins(p, coins, "pen") per player and tick; no Grip; a player who is not
--     ready is paid nothing; one player's error does not stop the others; a player who left is never paid;
--   * PenBuySpot(expectedPrice) buys only the caller's own next spot: bad input net.invalid, then data.notReady, then
--     pen.max / pen.priceChanged, then pen.paused (a pending failed save, closing, a restart, or within
--     buyCooldownSeconds of the last buy), then inventory.lockedInDuel, then the spend (economy.notEnoughCoins;
--     a "savePending" spend -> pen.paused); every refusal has charged = false and writes nothing;
--   * a buy: one spend with reason "pen", spots + 1 through mutate, the base redrawn and the "pen" field sent once
--     (showPen), the awaited "now" save, the reply {pen, charged = true, savePending}; 1 call a second, one at a time;
--   * pens3 phase 4: a loaded profile gets its Coins for the time away from EconomyService.grantAway (once per load),
--     and a gift that paid goes to the client as the awayGift session field {coins, seconds}; a gift of 0 sends none;
--   * pens3 phase 5: a bought spot makes room, so the buy drops queued gifts in (EconomyService.dropGifts) before the
--     reply's pen is copied, and a load drops them in too; the Frog gift (Pen.frogGift) is asked for once a session,
--     frogGift.seconds after the player joined and only while the profile is READY (EconomyService.grantGift keeps it
--     once per account);
--   * pens3 phase 6 (the pen screen): PenPlace(itemId, slot) moves only the caller's own squishy: bad input
--     net.invalid, then data.notReady, then the decision (inventory.notOwned, pen.spotClosed, inventory.full), then
--     pen.changePaused (a pending failed save, closing, a restart), then inventory.lockedInDuel; an empty spot takes
--     it, an occupied one swaps, slot 0 puts it away; the same place answers ok and writes nothing; a move is one
--     mutate, the base redrawn and the pen sent (showPen), a "soon" save (no Coins move: reading, see PenService's
--     header) and the reply {pen, charged = false, savePending}; PenLock(itemId, locked) the same checks, the lock in
--     one mutate, the pen field sent (no redraw: nothing on the plot shows a lock) and the awaited "now" save; every
--     refusal has charged = false and writes nothing; 2 a second (burst 3), one at a time; a bought spot takes the best
--     unlocked Toy Box squishy in the buy's own step (a placed squishy never moves);
--   * pens3 phases 7-8 (selling, the 10-minute buy-back, fusion): SellItems(ids, requestId) and SellAll(requestId) sell
--     only the caller's own squishies: bad input net.invalid, then data.notReady, then a replay (a requestId already in
--     buyBack answers what that sale paid and changes nothing), then the decision (inventory.notOwned,
--     pen.sellStarter, pen.locked, pen.lastCopy; Sell All with nothing to sell pen.nothingToSell), then
--     pen.changePaused, then inventory.lockedInDuel; a sale is one mutate (the squishies out, one bare buy-back entry
--     each {item, price, at, req}, a coating to the bag, the oldest past buyBackMax and the expired ones dropped),
--     then ONE grantCoins(p, the exact total, "sell") (a sale clamped at maxCoins records what it really paid), the
--     base and pen shown, the buy-back field sent, an awaited save, the reply {pen, coins, charged = false,
--     savePending}; Sell All sells the Toy Box's plain Lv 1 unlocked squishies, keeping one of a kind;
--     BuyBack(itemId) within buyBackSeconds: net.invalid, data.notReady, pen.buyBackGone (never twice, expired),
--     inventory.full, then pen.paused / inventory.lockedInDuel / economy.notEnoughCoins before ONE trySpend of exactly
--     the price paid ("sell"); the squishy comes back bare with a fresh id in the first free spot, else the Toy Box;
--     Fuse(a, b, c): net.invalid, data.notReady, inventory.notOwned, pen.locked, pen.fuseMismatch, pen.fuseTop,
--     pen.changePaused, inventory.lockedInDuel; the highest-level input becomes the next form in its own slot (its
--     level), the other two go, every coating goes to the bag, no Coins move, an awaited save, the reply {pen, id,
--     charged = false, savePending}; every refusal has charged = false and writes nothing.
--   * pens3 phase 11 (the shelf rows + the TOP spot): PenBuyShelf(expectedPrice) (PenBuySpot's shape: only the expected
--     price, 1 a second, one at a time) buys the caller's own next shelf row, then the TOP spot: bad input net.invalid,
--     then data.notReady, then pen.shelfMax / pen.priceChanged, then pen.paused (a pending failed save, closing, a
--     restart, or within buyCooldownSeconds of the last buy: the pen sign's cooldown too), then
--     inventory.lockedInDuel, then the spend (economy.notEnoughCoins; a "savePending" spend -> pen.paused); a buy is
--     one "pen" spend, the row (or top = true) through mutate with each new spot taking the best unlocked Toy Box
--     squishy, queued gifts dropped in, the base and pen shown, the awaited save and the reply {pen, charged = true,
--     savePending}; every refusal has charged = false and writes nothing; the shelf's squishies are paid by the tick
--     like the pen's.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local PenService = t.requireServer("Services/PenService")
	local NetService = t.requireServer("Services/NetService")
	local Config = t.requireShared("Config")
	local Remotes = t.requireShared("Remotes")
	local PenMath = t.requireShared("PenMath") -- pens3 phase 9: the level cap
	local TableUtil = t.requireShared("Util/TableUtil")
	local FakeClock = t.requireFake("FakeClock")
	local PEN = Config.Economy.Pen

	type World = {
		a: any,
		b: any,
		profiles: { [any]: any },
		status: { [any]: string },
		phase: { [any]: string },
		clock: number,
		savePending: boolean,
		closing: boolean,
		restart: boolean,
		saveOk: boolean,
		spendFails: string?,
		grantFails: { [any]: boolean }, -- grantCoins errors for these players
		grants: { { player: any, amount: number, reason: string } },
		spends: { { player: any, amount: number, reason: string } },
		nowSaves: number,
		shown: { any },
		writes: number,
		away: { [any]: { number } }, -- grantAway's answer per player: {coins, seconds}
		awayCalls: { any },
		gifts: { { player: any, gift: any } },
		drops: { any }, -- pens3 phase 5: dropGifts calls
		dropAdds: { [any]: any }, -- an item dropGifts puts in that player's pen
		frogAsks: { { player: any, key: string, kind: string } }, -- grantGift calls
		soonSaves: { any }, -- pens3 phase 6: requestSave(p, "soon") calls
		sent: { any }, -- pens3 phase 6: sendPen calls (the pen field alone)
		now: number, -- pens3 phase 7: os.time (the buy-back's `at`)
		backSent: { any }, -- sendBuyBack calls
		foodSent: { any }, -- pens3 phase 9: sendFood calls
	}

	-- Pens3 phase 9: none of each Config food.
	local function noFood(): any
		local food = {}
		for _, def in Config.Economy.Food.foods do
			food[def.id] = 0
		end
		return food
	end

	local function newProfile(): any
		return {
			coins = 0,
			owned = { kitty_bread = { at = 1, src = "starter" } },
			pen = {
				spots = 3,
				nextId = 2,
				items = { { id = 1, kind = "kitty_bread", form = 0, level = 1, coat = 0, slot = 1, locked = false } },
			},
			buyBack = {}, -- pens3 phase 7
			bag = { 0, 0, 0, 0, 0, 0, 0 }, -- pens3 phase 8
			food = noFood(), -- pens3 phase 9
		}
	end

	local function fresh(): World
		local w: World = {
			a = { UserId = 1 },
			b = { UserId = 2 },
			profiles = {},
			status = {},
			phase = {},
			clock = 100,
			savePending = false,
			closing = false,
			restart = false,
			saveOk = true,
			spendFails = nil,
			grantFails = {},
			grants = {},
			spends = {},
			nowSaves = 0,
			shown = {},
			writes = 0,
			away = {},
			awayCalls = {},
			gifts = {},
			drops = {},
			dropAdds = {},
			frogAsks = {},
			soonSaves = {},
			sent = {},
			now = 1_800_000_000,
			backSent = {},
			foodSent = {},
		}
		PenService.reset()
		PenService.useDeps({
			statusOf = function(player: any): string
				return w.status[player] or "loading"
			end,
			profileOf = function(player: any): any
				return w.profiles[player]
			end,
			-- Like DataService.mutate: READY sessions only.
			mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
				if w.status[player] ~= "ready" then
					return false, "data.notReady"
				end
				w.writes += 1
				return true, fn(w.profiles[player])
			end,
			savePending = function(_player: any): boolean
				return w.savePending
			end,
			isClosing = function(): boolean
				return w.closing
			end,
			isRestartPending = function(): boolean
				return w.restart
			end,
			duelPhaseOf = function(player: any): string
				return w.phase[player] or ""
			end,
			-- Like EconomyService.trySpend over the same fake profile.
			trySpend = function(player: any, amount: number, reason: string): (boolean, string?)
				local profile = w.profiles[player]
				if w.spendFails ~= nil then
					return false, w.spendFails
				elseif w.status[player] ~= "ready" then
					return false, "notReady"
				elseif profile.coins < amount then
					return false, "notEnoughCoins"
				end
				profile.coins -= amount
				table.insert(w.spends, { player = player, amount = amount, reason = reason })
				return true, nil
			end,
			grantCoins = function(player: any, amount: number, reason: string): number
				if w.grantFails[player] then
					error("grant exploded")
				end
				w.profiles[player].coins += amount
				table.insert(w.grants, { player = player, amount = amount, reason = reason })
				return amount
			end,
			saveNow = function(_player: any): boolean
				w.nowSaves += 1
				return w.saveOk
			end,
			clock = function(): number
				return w.clock
			end,
			showPen = function(player: any)
				table.insert(w.shown, player)
			end,
			grantAway = function(player: any): (number, number)
				table.insert(w.awayCalls, player)
				local answer = w.away[player] or { 0, 0 }
				return answer[1], answer[2]
			end,
			setAwayGift = function(player: any, gift: any)
				table.insert(w.gifts, { player = player, gift = gift })
			end,
			dropGifts = function(player: any): number
				table.insert(w.drops, player)
				local item = w.dropAdds[player]
				if item ~= nil then
					table.insert(w.profiles[player].pen.items, item)
					return 1
				end
				return 0
			end,
			grantGift = function(player: any, key: string, kind: string): boolean
				table.insert(w.frogAsks, { player = player, key = key, kind = kind })
				return true
			end,
			requestSave = function(player: any, reason: string)
				expect.equal(reason, "soon")
				table.insert(w.soonSaves, player)
			end,
			sendPen = function(player: any)
				table.insert(w.sent, player)
			end,
			now = function(): number
				return w.now
			end,
			sendBuyBack = function(player: any)
				table.insert(w.backSent, player)
			end,
			sendFood = function(player: any)
				table.insert(w.foodSent, player)
			end,
		})
		for _, player in { w.a, w.b } do
			w.profiles[player] = newProfile()
			w.status[player] = "ready"
			PenService.playerAdded(player)
		end
		return w
	end

	local function finish()
		PenService.reset()
		PenService.useDeps(nil)
	end

	local function grantsOf(w: World, player: any): { any }
		local list = {}
		for _, grant in w.grants do
			if grant.player == player then
				table.insert(list, grant)
			end
		end
		return list
	end

	local function expectRefused(reply: any, reason: string)
		expect.equal(reply.ok, false)
		expect.equal(reply.reason, reason)
		expect.equal(reply.charged, false)
	end

	-- The tick ------------------------------------------------------------------------------------------------------

	t.test(
		"the tick pays the pen's rate in whole Coins with the rest carried, one 'pen' grant a tick, no Grip",
		function()
			local w = fresh()
			local a = w.profiles[w.a]
			a.pen.items[1].level = 2 -- 11.5 a second
			PenService.step(1)
			expect.deepEqual(grantsOf(w, w.a), { { player = w.a, amount = 11, reason = "pen" } })
			PenService.step(1)
			expect.deepEqual(grantsOf(w, w.a)[2], { player = w.a, amount = 12, reason = "pen" })
			expect.equal(a.coins, 23)
			-- B's Kitty Bread at Lv 1: 10 a second, one grant each tick.
			expect.deepEqual(grantsOf(w, w.b), {
				{ player = w.b, amount = 10, reason = "pen" },
				{ player = w.b, amount = 10, reason = "pen" },
			})
			-- Two placed squishies are still one grant a tick.
			a.owned.butter = { at = 2, src = "box" }
			table.insert(
				a.pen.items,
				{ id = 2, kind = "butter", form = 0, level = 1, coat = 0, slot = 2, locked = false }
			)
			local before = #grantsOf(w, w.a)
			PenService.step(1)
			local after = grantsOf(w, w.a)
			expect.equal(#after, before + 1)
			expect.equal(after[#after].amount, 51) -- 11.5 + 40, and the carried 0 from before: 51.5 -> 51
			-- A server hitch pays at most maxTickSeconds of time.
			PenService.step(60)
			expect.equal(grantsOf(w, w.b)[4].amount, 10 * PEN.maxTickSeconds)
			finish()
		end
	)

	t.test("a player who is not ready is paid nothing; one player's error does not stop the others", function()
		local w = fresh()
		w.status[w.a] = "offline"
		PenService.step(5)
		expect.equal(#grantsOf(w, w.a), 0)
		expect.equal(w.profiles[w.b].coins, 50)
		w.status[w.a] = "ready"
		w.grantFails[w.b] = true
		PenService.step(1)
		expect.equal(w.profiles[w.a].coins, 10) -- the 5 s while not ready never count
		w.grantFails[w.b] = nil
		PenService.playerRemoving(w.a) -- left: never paid again
		PenService.step(1)
		expect.equal(w.profiles[w.a].coins, 10)
		expect.equal(w.profiles[w.b].coins, 60)
		finish()
	end)

	-- The buy -------------------------------------------------------------------------------------------------------

	t.test(
		"PenBuySpot takes only the expected price: it names no base, plot or player; 1 a second, one at a time",
		function()
			local spec = Remotes.SPEC.PenBuySpot
			expect.equal(spec.kind, "RemoteFunction")
			expect.equal(spec.dir, "c2s")
			expect.deepEqual(spec.args, { { name = "expectedPrice", type = "coins" } })
			expect.deepEqual(Config.Net.Remotes.PenBuySpot, { rate = 1, burst = 1, oneInFlight = true })
			local clock = FakeClock.new(100)
			local guard = NetService.newGuard({ clock = clock.now })
			local player = { UserId = 9 }
			expect.equal(guard:check(player, "PenBuySpot", 1, 5_600_000_000_000), "ok") -- prices reach trillions
			expect.equal(guard:check(player, "PenBuySpot", 1, 3_100), "rateLimited")
			clock.advance(1)
			expect.equal(guard:check(player, "PenBuySpot", 1, -1), "invalid")
			clock.advance(1)
			expect.equal(guard:check(player, "PenBuySpot", 2, 1_500, "extra"), "badArgCount")
		end
	)

	t.test("a buy: one 'pen' spend, spots 3 -> 4, the base and the pen field once, an awaited save", function()
		local w = fresh()
		local a = w.profiles[w.a]
		a.coins = 2_000
		local bBefore = TableUtil.deepCopy(w.profiles[w.b])
		local reply = PenService.buy(w.a, 1_500)
		expect.equal(reply.ok, true)
		expect.deepEqual(reply.data, { pen = TableUtil.deepCopy(a.pen), charged = true, savePending = false })
		expect.equal(a.pen.spots, 4)
		expect.equal(a.coins, 500)
		expect.deepEqual(w.spends, { { player = w.a, amount = 1_500, reason = "pen" } })
		expect.equal(w.nowSaves, 1)
		expect.deepEqual(w.shown, { w.a })
		expect.deepEqual(w.profiles[w.b], bBefore) -- only the caller's own pen
		-- A failed now save keeps the buy and says so.
		a.coins = 10_000
		w.clock += PEN.buyCooldownSeconds
		w.saveOk = false
		local unsaved = PenService.buy(w.a, 3_100)
		expect.equal(unsaved.data.savePending, true)
		expect.equal(unsaved.data.charged, true)
		expect.equal(a.pen.spots, 5)
		finish()
	end)

	t.test(
		"refusals: bad input, not ready, max, a wrong price, paused, in a duel, short of Coins: nothing charged",
		function()
			local w = fresh()
			local a = w.profiles[w.a]
			a.coins = 1_500
			local writes = w.writes
			for _, bad in { -1, 1.5, 0 / 0, "1500", true } :: { any } do
				expectRefused(PenService.buy(w.a, bad), "net.invalid")
			end
			w.status[w.a] = "offline"
			expectRefused(PenService.buy(w.a, 1_500), "data.notReady")
			w.status[w.a] = "ready"
			expectRefused(PenService.buy(w.a, 1_499), "pen.priceChanged")
			w.savePending = true
			expectRefused(PenService.buy(w.a, 1_500), "pen.paused")
			w.savePending = false
			w.closing = true
			expectRefused(PenService.buy(w.a, 1_500), "pen.paused")
			w.closing = false
			w.restart = true
			expectRefused(PenService.buy(w.a, 1_500), "pen.paused")
			w.restart = false
			for _, phase in { "Preparing", "Active", "Returning" } do
				w.phase[w.a] = phase
				expectRefused(PenService.buy(w.a, 1_500), "inventory.lockedInDuel")
			end
			w.phase[w.a] = ""
			w.spendFails = "savePending"
			expectRefused(PenService.buy(w.a, 1_500), "pen.paused")
			w.spendFails = nil
			a.coins = 1_499
			expectRefused(PenService.buy(w.a, 1_500), "economy.notEnoughCoins")
			a.pen.spots = 12
			a.coins = 10 ^ 13
			expectRefused(PenService.buy(w.a, 5_600_000_000_000), "pen.max")
			expect.equal(#w.spends, 0)
			expect.equal(w.writes, writes)
			expect.equal(w.nowSaves, 0)
			expect.deepEqual(w.shown, {})
			finish()
		end
	)

	t.test("a second buy within buyCooldownSeconds is pen.paused; after it, the next spot sells", function()
		local w = fresh()
		local a = w.profiles[w.a]
		a.coins = 10_000
		expect.equal(PenService.buy(w.a, 1_500).ok, true)
		w.clock += PEN.buyCooldownSeconds / 2
		expectRefused(PenService.buy(w.a, 3_100), "pen.paused")
		expect.equal(#w.spends, 1)
		w.clock += PEN.buyCooldownSeconds / 2
		expect.equal(PenService.buy(w.a, 3_100).ok, true)
		expect.equal(a.pen.spots, 5)
		-- A retry with the old price is a wrong price: never charged twice.
		w.clock += PEN.buyCooldownSeconds
		expectRefused(PenService.buy(w.a, 3_100), "pen.priceChanged")
		expect.equal(#w.spends, 2)
		finish()
	end)

	-- Coins while away (pens3 phase 4) --------------------------------------------------------------------------------

	t.test("a load pays the time away (one grantAway) and a gift that paid is sent as awayGift", function()
		local w = fresh()
		w.away[w.a] = { 1_800, 3600 }
		PenService.loaded(w.a)
		expect.deepEqual(w.awayCalls, { w.a })
		expect.deepEqual(w.gifts, { { player = w.a, gift = { coins = 1_800, seconds = 3600 } } })
		-- Nothing paid (just saved, a pen that earned nothing, a session that is not ready): no gift.
		w.away[w.b] = { 0, 12 }
		PenService.loaded(w.b)
		expect.deepEqual(w.awayCalls, { w.a, w.b })
		expect.equal(#w.gifts, 1)
		expect.equal(#w.grants, 0) -- the pen's tick is not involved
		finish()
	end)

	-- Copies, the Toy Box and gifts (pens3 phase 5) -------------------------------------------------------------------

	t.test("a bought spot drops queued gifts in before the reply's pen is copied; a load drops them in too", function()
		local w = fresh()
		local a = w.profiles[w.a]
		a.coins = 2_000
		local gift = { id = 9, kind = "strawberry_frog", form = 0, level = 1, coat = 0 }
		w.dropAdds[w.a] = gift
		local reply = PenService.buy(w.a, 1_500)
		expect.equal(reply.ok, true)
		expect.deepEqual(w.drops, { w.a })
		expect.deepEqual(reply.data.pen.items[2], gift) -- the client sees the gift that dropped in
		-- A refused buy drops nothing.
		expectRefused(PenService.buy(w.a, 1), "pen.priceChanged")
		expect.equal(#w.drops, 1)
		-- A load drops queued gifts in (the room may have grown since the last session).
		PenService.loaded(w.b)
		expect.deepEqual(w.drops, { w.a, w.b })
		finish()
	end)

	t.test("the Frog gift is asked for once a session, frogGift.seconds after joining, only while READY", function()
		local w = fresh()
		expect.deepEqual(PEN.frogGift, { kind = "strawberry_frog", seconds = 180 })
		PenService.step(1)
		expect.deepEqual(w.frogAsks, {}) -- too early
		w.clock += PEN.frogGift.seconds - 1
		PenService.step(1)
		expect.deepEqual(w.frogAsks, {})
		w.clock += 1
		w.status[w.b] = "offline" -- not ready: waits
		PenService.step(1)
		expect.deepEqual(w.frogAsks, { { player = w.a, key = "frog", kind = "strawberry_frog" } })
		w.status[w.b] = "ready"
		PenService.step(1)
		PenService.step(1)
		expect.deepEqual(w.frogAsks, {
			{ player = w.a, key = "frog", kind = "strawberry_frog" },
			{ player = w.b, key = "frog", kind = "strawberry_frog" },
		})
		-- A new session asks again (grantGift itself keeps it once per account).
		PenService.playerRemoving(w.a)
		PenService.playerAdded(w.a)
		w.clock += PEN.frogGift.seconds
		PenService.step(1)
		expect.equal(#w.frogAsks, 3)
		finish()
	end)
	-- The pen screen (pens3 phase 6) --------------------------------------------------------------------------------

	-- A pen item for these cases.
	local function penItem(id: number, kind: string, slot: number, locked: boolean?): any
		return { id = id, kind = kind, form = 0, level = 1, coat = 0, slot = slot, locked = locked == true }
	end

	-- A's pen: Kitty Bread (1) in spot 1, Butter (2) in spot 2, Toast (3) in the Toy Box; spot 3 empty.
	local function screenWorld(): (World, any)
		local w = fresh()
		local a = w.profiles[w.a]
		a.owned.butter = { at = 2, src = "box" }
		a.owned.toast = { at = 3, src = "shop" }
		a.pen = {
			spots = 3,
			nextId = 4,
			items = { penItem(1, "kitty_bread", 1), penItem(2, "butter", 2), penItem(3, "toast", 0) },
		}
		return w, a
	end

	local function slotsOf(profile: any): { number }
		local list = {}
		for _, item in profile.pen.items do
			table.insert(list, item.slot)
		end
		return list
	end

	t.test(
		"PenPlace and PenLock take only an item id and a slot / a lock: no base, plot or player; 2 a second",
		function()
			expect.deepEqual(
				Remotes.SPEC.PenPlace.args,
				{ { name = "itemId", type = "integer" }, { name = "slot", type = "integer" } }
			)
			expect.deepEqual(
				Remotes.SPEC.PenLock.args,
				{ { name = "itemId", type = "integer" }, { name = "locked", type = "boolean" } }
			)
			for _, name in { "PenPlace", "PenLock" } do
				expect.equal(Remotes.SPEC[name].kind, "RemoteFunction")
				expect.equal(Remotes.SPEC[name].dir, "c2s")
				expect.deepEqual(Config.Net.Remotes[name], { rate = 2, burst = 3, oneInFlight = true })
			end
			local clock = FakeClock.new(100)
			local guard = NetService.newGuard({ clock = clock.now })
			local player = { UserId = 9 }
			expect.equal(guard:check(player, "PenPlace", 2, 4, 0), "ok")
			expect.equal(guard:check(player, "PenPlace", 2, 4, 1.5), "invalid")
			expect.equal(guard:check(player, "PenPlace", 3, 4, 1, 7), "badArgCount")
			expect.equal(guard:check(player, "PenLock", 2, 4, true), "ok")
			expect.equal(guard:check(player, "PenLock", 2, 4, "yes"), "invalid")
		end
	)

	t.test("place: a Toy Box squishy into an empty spot, one step, the base and pen shown, a soon save", function()
		local w, a = screenWorld()
		local bBefore = TableUtil.deepCopy(w.profiles[w.b])
		local reply = PenService.place(w.a, 3, 3)
		expect.equal(reply.ok, true)
		expect.deepEqual(slotsOf(a), { 1, 2, 3 })
		expect.deepEqual(reply.data, { pen = TableUtil.deepCopy(a.pen), charged = false, savePending = false })
		expect.equal(w.writes, 1)
		expect.deepEqual(w.shown, { w.a })
		expect.deepEqual(w.soonSaves, { w.a })
		expect.equal(w.nowSaves, 0) -- no Coins move: a soon save
		expect.deepEqual(w.profiles[w.b], bBefore) -- only the caller's own pen
		finish()
	end)

	t.test("place: an occupied spot swaps; slot 0 puts away; the same place writes nothing", function()
		local w, a = screenWorld()
		-- The Toy Box's Toast onto Kitty Bread's spot 1: Kitty Bread goes to the Toy Box.
		expect.equal(PenService.place(w.a, 3, 1).ok, true)
		expect.deepEqual(slotsOf(a), { 0, 2, 1 })
		-- Two pen squishies swap.
		expect.equal(PenService.place(w.a, 3, 2).ok, true)
		expect.deepEqual(slotsOf(a), { 0, 1, 2 })
		-- Put away.
		expect.equal(PenService.place(w.a, 2, 0).ok, true)
		expect.deepEqual(slotsOf(a), { 0, 0, 2 })
		local writes = w.writes
		local same = PenService.place(w.a, 3, 2)
		expect.equal(same.ok, true)
		expect.equal(same.data.charged, false)
		expect.equal(w.writes, writes)
		expect.equal(#w.shown, 3)
		expect.equal(#w.soonSaves, 3)
		finish()
	end)

	t.test(
		"place refusals: bad input, not ready, not owned, a closed spot, a full Toy Box, paused, in a duel",
		function()
			local w, a = screenWorld()
			local bad: { { any } } = { { 1.5, 1 }, { 1, -1 }, { "1", 1 }, { 1, 0 / 0 }, { 1, PEN.placedMax + 1 } }
			for _, case in bad do
				expectRefused(PenService.place(w.a, case[1], case[2]), "net.invalid")
			end
			w.status[w.a] = "offline"
			expectRefused(PenService.place(w.a, 3, 3), "data.notReady")
			w.status[w.a] = "ready"
			expectRefused(PenService.place(w.a, 99, 3), "inventory.notOwned")
			expectRefused(PenService.place(w.b, 3, 3), "inventory.notOwned") -- B has no item 3: never A's
			expectRefused(PenService.place(w.a, 3, 4), "pen.spotClosed")
			w.savePending = true
			expectRefused(PenService.place(w.a, 3, 3), "pen.changePaused")
			w.savePending = false
			w.closing = true
			expectRefused(PenService.place(w.a, 3, 3), "pen.changePaused")
			w.closing = false
			w.restart = true
			expectRefused(PenService.place(w.a, 3, 3), "pen.changePaused")
			w.restart = false
			w.phase[w.a] = "Active"
			expectRefused(PenService.place(w.a, 3, 3), "inventory.lockedInDuel")
			w.phase[w.a] = ""
			-- A full Toy Box takes no squishy from the pen (a swap from it still works).
			for id = 4, 3 + Config.Economy.Pen.toyBoxMax - 1 do
				table.insert(a.pen.items, penItem(id, "toast", 0))
			end
			expectRefused(PenService.place(w.a, 1, 0), "inventory.full")
			expect.equal(w.writes, 0)
			expect.deepEqual(w.shown, {})
			expect.deepEqual(w.soonSaves, {})
			expect.equal(PenService.place(w.a, 3, 1).ok, true) -- the swap
			expect.equal(a.pen.items[1].slot, 0)
			finish()
		end
	)

	t.test("lock: one step, the pen field sent (no redraw), an awaited save; the same lock writes nothing", function()
		local w, a = screenWorld()
		local reply = PenService.lock(w.a, 2, true)
		expect.equal(reply.ok, true)
		expect.equal(a.pen.items[2].locked, true)
		expect.deepEqual(reply.data, { pen = TableUtil.deepCopy(a.pen), charged = false, savePending = false })
		expect.equal(w.writes, 1)
		expect.deepEqual(w.sent, { w.a })
		expect.deepEqual(w.shown, {})
		expect.equal(w.nowSaves, 1)
		-- Locked again: nothing changes.
		expect.equal(PenService.lock(w.a, 2, true).ok, true)
		expect.equal(w.writes, 1)
		-- A failed save keeps the lock and says so.
		w.saveOk = false
		local unsaved = PenService.lock(w.a, 2, false)
		expect.equal(a.pen.items[2].locked, false)
		expect.equal(unsaved.data.savePending, true)
		-- A locked squishy still moves (a lock only keeps it from being sold or fused).
		a.pen.items[1].locked = true
		expect.equal(PenService.place(w.a, 1, 0).ok, true)
		finish()
	end)

	t.test("lock refusals: bad input, not ready, not owned, paused, in a duel: nothing written", function()
		local w = screenWorld()
		for _, case in { { 1.5, true }, { 1, "yes" }, { 1, nil }, { "1", false } } :: { { any } } do
			expectRefused(PenService.lock(w.a, case[1], case[2]), "net.invalid")
		end
		w.status[w.a] = "offline"
		expectRefused(PenService.lock(w.a, 1, true), "data.notReady")
		w.status[w.a] = "ready"
		expectRefused(PenService.lock(w.a, 99, true), "inventory.notOwned")
		w.savePending = true
		expectRefused(PenService.lock(w.a, 1, true), "pen.changePaused")
		w.savePending = false
		w.phase[w.a] = "Preparing"
		expectRefused(PenService.lock(w.a, 1, true), "inventory.lockedInDuel")
		expect.equal(w.writes, 0)
		expect.equal(w.nowSaves, 0)
		expect.deepEqual(w.sent, {})
		finish()
	end)

	t.test("a bought spot takes the best unlocked Toy Box squishy in the buy's step, then all sort", function()
		local w = fresh()
		local a = w.profiles[w.a]
		a.coins = 2_000
		a.pen.items = {
			penItem(1, "kitty_bread", 1),
			penItem(2, "toast", 2),
			penItem(3, "butter", 3),
			penItem(4, "dragon", 0, true), -- locked: auto-place never moves it
			penItem(5, "bird", 0),
			penItem(6, "banana", 0),
		}
		local writes = w.writes
		expect.equal(PenService.buy(w.a, 1_500).ok, true)
		expect.equal(w.writes, writes + 1) -- the spot and its squishy in one step
		-- The Bird comes out of the Toy Box, then (qb1) the placed ones sort best first: Bird, Butter, Kitty, Toast.
		expect.deepEqual(slotsOf(a), { 3, 4, 2, 0, 1, 0 })
		finish()
	end)

	-- Selling, the buy-back and fusion (pens3 phases 7-8) ------------------------------------------------------------

	local REQ = "0123abcd-4567-89ab-cdef-0123456789ab"
	local REQ2 = "0123abcd-4567-89ab-cdef-0123456789ac"

	-- A's pen for the sell cases: Kitty Bread (1) in spot 1, Toast (2) in spot 2, Toasts (3, 4) and Butter (5) in the
	-- Toy Box; spot 3 empty.
	local function sellWorld(): (World, any)
		local w = fresh()
		local a = w.profiles[w.a]
		a.owned.toast = { at = 2, src = "shop" }
		a.owned.butter = { at = 3, src = "box" }
		a.pen = {
			spots = 3,
			nextId = 6,
			items = {
				penItem(1, "kitty_bread", 1),
				penItem(2, "toast", 2),
				penItem(3, "toast", 0),
				penItem(4, "toast", 0),
				penItem(5, "butter", 0),
			},
		}
		return w, a
	end

	local function idsOf(profile: any): { number }
		local list = {}
		for _, item in profile.pen.items do
			table.insert(list, item.id)
		end
		return list
	end

	t.test(
		"SellItems, SellAll, BuyBack and Fuse take only ids and a requestId: no base, plot or player; 2 a second",
		function()
			expect.deepEqual(
				Remotes.SPEC.SellItems.args,
				{ { name = "ids", type = "itemIds" }, { name = "requestId", type = "requestId" } }
			)
			expect.deepEqual(Remotes.SPEC.SellAll.args, { { name = "requestId", type = "requestId" } })
			expect.deepEqual(Remotes.SPEC.BuyBack.args, { { name = "itemId", type = "integer" } })
			expect.deepEqual(Remotes.SPEC.Fuse.args, {
				{ name = "a", type = "integer" },
				{ name = "b", type = "integer" },
				{ name = "c", type = "integer" },
			})
			for _, name in { "SellItems", "SellAll", "BuyBack", "Fuse" } do
				expect.equal(Remotes.SPEC[name].kind, "RemoteFunction")
				expect.equal(Remotes.SPEC[name].dir, "c2s")
				expect.deepEqual(Config.Net.Remotes[name], { rate = 2, burst = 3, oneInFlight = true })
			end
			local clock = FakeClock.new(100)
			local guard = NetService.newGuard({ clock = clock.now })
			local player = { UserId = 9 }
			local twenty = {}
			for id = 1, 20 do
				twenty[id] = id
			end
			expect.equal(guard:check(player, "SellItems", 2, twenty, REQ), "ok") -- more ids than the generic table cap
			expect.equal(guard:check(player, "SellItems", 2, { 1.5 }, REQ), "invalid")
			expect.equal(guard:check(player, "SellAll", 1, "not-a-guid"), "invalid")
			clock.advance(2)
			expect.equal(guard:check(player, "Fuse", 3, 4, 5, 6), "ok")
			expect.equal(guard:check(player, "Fuse", 4, 4, 5, 6, 7), "badArgCount")
			expect.equal(guard:check(player, "BuyBack", 1, 4), "ok")
		end
	)

	t.test("a sale: the squishy out, one exact 'sell' grant, a bare buy-back entry, shown, an awaited save", function()
		local w, a = sellWorld()
		local bBefore = TableUtil.deepCopy(w.profiles[w.b])
		local reply = PenService.sellItems(w.a, { 3 }, REQ)
		expect.equal(reply.ok, true)
		expect.deepEqual(idsOf(a), { 1, 2, 4, 5 })
		expect.deepEqual(w.grants, { { player = w.a, amount = 1_000, reason = "sell" } })
		expect.equal(a.coins, 1_000)
		expect.deepEqual(a.buyBack, { { item = penItem(3, "toast", 0), price = 1_000, at = w.now, req = REQ } })
		expect.deepEqual(
			reply.data,
			{ pen = TableUtil.deepCopy(a.pen), coins = 1_000, charged = false, savePending = false }
		)
		expect.equal(w.writes, 1)
		expect.deepEqual(w.shown, { w.a })
		expect.deepEqual(w.backSent, { w.a })
		expect.equal(w.nowSaves, 1)
		expect.deepEqual(w.spends, {})
		expect.deepEqual(w.profiles[w.b], bBefore) -- only the caller's own pen
		finish()
	end)

	t.test(
		"a retried sale (same requestId) replays what it paid and changes nothing; the ids are gone after",
		function()
			local w, a = sellWorld()
			expect.equal(PenService.sellItems(w.a, { 3, 4 }, REQ).data.coins, 2_000)
			local writes, saves = w.writes, w.nowSaves
			local again = PenService.sellItems(w.a, { 3, 4 }, REQ)
			expect.equal(again.ok, true)
			expect.equal(again.data.coins, 2_000) -- what it paid then, never twice
			expect.equal(#w.grants, 1)
			expect.equal(a.coins, 2_000)
			expect.equal(w.writes, writes)
			expect.equal(w.nowSaves, saves)
			expectRefused(PenService.sellItems(w.a, { 3 }, REQ2), "inventory.notOwned") -- a new request: it is sold
			finish()
		end
	)

	t.test(
		"sale refusals, in order: invalid, not ready, not owned, Kitty Bread, locked, last copy, paused, duel",
		function()
			local w, a = sellWorld()
			for _, case in
				{ { { 3 }, "nope" }, { { 1.5 }, REQ }, { {}, REQ }, { "3", REQ }, { { 3, 3 }, REQ } } :: { { any } }
			do
				expectRefused(PenService.sellItems(w.a, case[1], case[2]), "net.invalid")
			end
			w.status[w.a] = "offline"
			expectRefused(PenService.sellItems(w.a, { 3 }, REQ), "data.notReady")
			w.status[w.a] = "ready"
			expectRefused(PenService.sellItems(w.a, { 99 }, REQ), "inventory.notOwned")
			expectRefused(PenService.sellItems(w.b, { 3 }, REQ), "inventory.notOwned") -- never another player's squishy
			expectRefused(PenService.sellItems(w.a, { 1 }, REQ), "pen.sellStarter")
			a.pen.items[3].locked = true
			expectRefused(PenService.sellItems(w.a, { 3 }, REQ), "pen.locked")
			a.pen.items[3].locked = false
			expectRefused(PenService.sellItems(w.a, { 5 }, REQ), "pen.lastCopy") -- the only Butter
			expectRefused(PenService.sellItems(w.a, { 2, 3, 4 }, REQ), "pen.lastCopy") -- every Toast
			w.savePending = true
			expectRefused(PenService.sellItems(w.a, { 3 }, REQ), "pen.changePaused")
			w.savePending = false
			w.restart = true
			expectRefused(PenService.sellAll(w.a, REQ), "pen.changePaused")
			w.restart = false
			w.phase[w.a] = "Active"
			expectRefused(PenService.sellItems(w.a, { 3 }, REQ), "inventory.lockedInDuel")
			w.phase[w.a] = ""
			expect.equal(w.writes, 0)
			expect.deepEqual(w.grants, {})
			expect.equal(w.nowSaves, 0)
			expect.deepEqual(w.shown, {})
			expect.deepEqual(a.buyBack, {})
			finish()
		end
	)

	t.test("sale coins: Golden x3, Rainbow x9, by rarity; a coating goes to the bag and the entry is bare", function()
		local w, a = sellWorld()
		a.pen.items[3].form = 1 -- a Golden Toast
		a.pen.items[4].form = 2 -- a Rainbow Toast
		a.pen.items[4].coat = 7 -- Galaxy
		a.pen.items[4].level = 12 -- food is not refunded
		expect.equal(PenService.sellItems(w.a, { 3, 4 }, REQ).data.coins, 3_000 + 9_000)
		expect.deepEqual(w.grants, { { player = w.a, amount = 12_000, reason = "sell" } }) -- one grant, the exact total
		expect.deepEqual(a.bag, { 0, 0, 0, 0, 0, 0, 1 })
		expect.equal(a.buyBack[2].item.coat, 0)
		expect.equal(a.buyBack[2].item.level, 12)
		expect.equal(a.buyBack[2].price, 9_000)
		finish()
	end)

	t.test(
		"Sell All: the Toy Box's plain Lv 1 unlocked squishies, one of a kind kept; one grant; nothing -> refused",
		function()
			local w, a = sellWorld()
			table.insert(a.pen.items, penItem(6, "butter", 0)) -- a second Butter: one of the two stays
			local levelled = penItem(7, "banana", 0)
			levelled.level = 3 -- skipped
			table.insert(a.pen.items, levelled)
			a.owned.banana = { at = 4, src = "box" }
			local reply = PenService.sellAll(w.a, REQ)
			expect.equal(reply.ok, true)
			-- Kitty Bread, the placed Toast, the best Butter, the levelled Banana.
			expect.deepEqual(idsOf(a), { 1, 2, 5, 7 })
			expect.equal(reply.data.coins, 1_000 + 1_000 + 150_000)
			expect.deepEqual(w.grants, { { player = w.a, amount = 152_000, reason = "sell" } })
			expect.equal(#a.buyBack, 3)
			for _, entry in a.buyBack do
				expect.equal(entry.req, REQ)
			end
			expect.equal(PenService.sellAll(w.a, REQ).data.coins, 152_000) -- a retry replays
			expectRefused(PenService.sellAll(w.a, REQ2), "pen.nothingToSell")
			expect.equal(#w.grants, 1)
			finish()
		end
	)

	t.test("buy-back: exactly what the sale paid, once; it comes back bare with a fresh id in a free spot", function()
		local w, a = sellWorld()
		PenService.sellItems(w.a, { 2 }, REQ) -- the placed Toast: spot 2 is free now
		a.coins = 5_000
		w.now += Config.Economy.Pen.buyBackSeconds - 1 -- still within the 10 minutes
		local saves, shown = w.nowSaves, #w.shown
		local reply = PenService.buyBack(w.a, 2)
		expect.equal(reply.ok, true)
		expect.deepEqual(w.spends, { { player = w.a, amount = 1_000, reason = "sell" } })
		expect.equal(a.coins, 4_000)
		expect.deepEqual(a.buyBack, {})
		local back = a.pen.items[#a.pen.items]
		expect.deepEqual(back, penItem(6, "toast", 2)) -- a fresh id, the first free spot, unlocked
		expect.equal(a.pen.nextId, 7)
		expect.deepEqual(reply.data, { pen = TableUtil.deepCopy(a.pen), charged = true, savePending = false })
		expect.equal(w.nowSaves, saves + 1)
		expect.equal(#w.shown, shown + 1)
		expect.equal(w.backSent[#w.backSent], w.a)
		expectRefused(PenService.buyBack(w.a, 2), "pen.buyBackGone") -- never twice
		expect.equal(#w.spends, 1)
		finish()
	end)

	t.test(
		"buy-back refusals: invalid, not ready, expired, a full Toy Box, paused, in a duel, not enough Coins",
		function()
			local w, a = sellWorld()
			PenService.sellItems(w.a, { 3 }, REQ)
			a.coins = 0
			expectRefused(PenService.buyBack(w.a, 1.5), "net.invalid")
			w.status[w.a] = "offline"
			expectRefused(PenService.buyBack(w.a, 3), "data.notReady")
			w.status[w.a] = "ready"
			expectRefused(PenService.buyBack(w.b, 3), "pen.buyBackGone") -- only the caller's own sales
			expectRefused(PenService.buyBack(w.a, 3), "economy.notEnoughCoins")
			a.coins = 1_000
			w.savePending = true
			expectRefused(PenService.buyBack(w.a, 3), "pen.paused")
			w.savePending = false
			w.phase[w.a] = "Preparing"
			expectRefused(PenService.buyBack(w.a, 3), "inventory.lockedInDuel")
			w.phase[w.a] = ""
			local items = a.pen.items
			for id = 10, 9 + PEN.toyBoxMax do
				table.insert(a.pen.items, penItem(id, "toast", 0))
			end
			expectRefused(PenService.buyBack(w.a, 3), "inventory.full")
			a.pen.items = table.move(items, 1, 4, 1, {})
			w.now += PEN.buyBackSeconds -- the 10 minutes are over
			expectRefused(PenService.buyBack(w.a, 3), "pen.buyBackGone")
			expect.deepEqual(w.spends, {})
			expect.equal(a.coins, 1_000)
			finish()
		end
	)

	t.test("the buy-back list: the oldest falls off past buyBackMax, expired sales go with the next one", function()
		local w, a = sellWorld()
		a.buyBack = {}
		for i = 1, PEN.buyBackMax do
			table.insert(a.buyBack, { item = penItem(100 + i, "toast", 0), price = 1_000, at = w.now, req = "old" })
		end
		PenService.sellItems(w.a, { 3 }, REQ)
		expect.equal(#a.buyBack, PEN.buyBackMax)
		expect.equal(a.buyBack[1].item.id, 102) -- the oldest one fell off
		expect.equal(a.buyBack[PEN.buyBackMax].item.id, 3)
		w.now += PEN.buyBackSeconds
		PenService.sellItems(w.a, { 4 }, REQ2)
		expect.equal(#a.buyBack, 1) -- the expired ones are gone
		expect.equal(a.buyBack[1].item.id, 4)
		finish()
	end)

	t.test("a sale clamped at maxCoins: the buy-back entry holds what the sale really paid", function()
		local w, a = sellWorld()
		PenService.useDeps({
			statusOf = function(): string
				return "ready"
			end,
			profileOf = function(player: any): any
				return w.profiles[player]
			end,
			mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
				return true, fn(w.profiles[player])
			end,
			grantCoins = function(_player: any, amount: number, _reason: string): number
				return amount - 400 -- 400 short of the total: the wallet is full
			end,
			saveNow = function(): boolean
				return true
			end,
			now = function(): number
				return w.now
			end,
			showPen = function() end,
			sendBuyBack = function() end,
			savePending = function(): boolean
				return false
			end,
			isClosing = function(): boolean
				return false
			end,
			isRestartPending = function(): boolean
				return false
			end,
			duelPhaseOf = function(): string
				return ""
			end,
		})
		local reply = PenService.sellItems(w.a, { 3, 4 }, REQ)
		expect.equal(reply.data.coins, 1_600)
		expect.equal(a.buyBack[1].price + a.buyBack[2].price, 1_600)
		expect.deepEqual({ a.buyBack[1].price, a.buyBack[2].price }, { 1_000, 600 })
		finish()
	end)

	-- Fusion (pens3 phase 8) --------------------------------------------------------------------------------------

	-- A's pen for the fuse cases: Kitty Bread (1) in spot 1; Toasts 2 (Lv 2, Jelly, Toy Box), 3 (Lv 7, spot 2) and 4
	-- (Lv 1, Wax, Toy Box); a Golden Butter (5) in the Toy Box.
	local function fuseWorld(): (World, any)
		local w, a = sellWorld()
		local function lv(item: any, level: number, coat: number?, form: number?): any
			item.level, item.coat, item.form = level, coat or 0, form or 0
			return item
		end
		a.pen.items = {
			penItem(1, "kitty_bread", 1),
			lv(penItem(2, "toast", 0), 2, 3),
			lv(penItem(3, "toast", 2), 7),
			lv(penItem(4, "toast", 0), 1, 1),
			lv(penItem(5, "butter", 0), 1, 0, 1),
		}
		return w, a
	end

	t.test(
		"fuse: the highest-level input becomes a Golden one in its spot at its level, coatings to the bag, free",
		function()
			local w, a = fuseWorld()
			local bBefore = TableUtil.deepCopy(w.profiles[w.b])
			local reply = PenService.fuse(w.a, 2, 3, 4)
			expect.equal(reply.ok, true)
			expect.deepEqual(idsOf(a), { 1, 3, 5 })
			local golden = a.pen.items[2]
			expect.equal(golden.form, 1)
			expect.equal(golden.level, 7)
			expect.equal(golden.coat, 0) -- it comes out bare
			expect.equal(golden.slot, 1) -- qb1: now the best placed squishy, it sorts to the first spot
			expect.deepEqual(a.bag, { 1, 0, 1, 0, 0, 0, 0 }) -- the Wax and the Jelly
			expect.deepEqual(
				reply.data,
				{ pen = TableUtil.deepCopy(a.pen), id = 3, charged = false, savePending = false }
			)
			expect.deepEqual(w.grants, {})
			expect.deepEqual(w.spends, {})
			expect.equal(w.writes, 1)
			expect.deepEqual(w.shown, { w.a })
			expect.equal(w.nowSaves, 1)
			expect.deepEqual(w.profiles[w.b], bBefore)
			-- Three Goldens make a Rainbow; Rainbow is the top.
			a.pen.items =
				{ penItem(1, "kitty_bread", 1), penItem(6, "toast", 0), penItem(7, "toast", 0), penItem(8, "toast", 3) }
			for i = 2, 4 do
				a.pen.items[i].form = 1
			end
			expect.equal(PenService.fuse(w.a, 6, 7, 8).data.id, 8) -- a level tie: the placed one
			expect.equal(a.pen.items[2].form, 2)
			finish()
		end
	)

	t.test(
		"fuse refusals: invalid, not ready, not owned, locked, mismatch, Rainbow, paused, duel: nothing written",
		function()
			local w, a = fuseWorld()
			for _, case in { { 2, 3, 3 }, { 2, 3, 1.5 }, { 2, 3, "4" } } :: { { any } } do
				expectRefused(PenService.fuse(w.a, case[1], case[2], case[3]), "net.invalid")
			end
			w.status[w.a] = "offline"
			expectRefused(PenService.fuse(w.a, 2, 3, 4), "data.notReady")
			w.status[w.a] = "ready"
			expectRefused(PenService.fuse(w.a, 2, 3, 99), "inventory.notOwned")
			expectRefused(PenService.fuse(w.b, 2, 3, 4), "inventory.notOwned") -- never another player's squishies
			a.pen.items[2].locked = true
			expectRefused(PenService.fuse(w.a, 2, 3, 4), "pen.locked")
			a.pen.items[2].locked = false
			expectRefused(PenService.fuse(w.a, 2, 3, 5), "pen.fuseMismatch")
			w.closing = true
			expectRefused(PenService.fuse(w.a, 2, 3, 4), "pen.changePaused")
			w.closing = false
			w.phase[w.a] = "Active"
			expectRefused(PenService.fuse(w.a, 2, 3, 4), "inventory.lockedInDuel")
			w.phase[w.a] = ""
			for i = 2, 4 do
				a.pen.items[i].form = 2
			end
			expectRefused(PenService.fuse(w.a, 2, 3, 4), "pen.fuseTop")
			expect.equal(w.writes, 0)
			expect.equal(w.nowSaves, 0)
			expect.deepEqual(a.bag, { 0, 0, 0, 0, 0, 0, 0 })
			finish()
		end
	)

	-- Pens3 phase 9 (food and levels) ---------------------------------------------------------------------------------

	-- A's pen: Kitty Bread (1) in spot 1 at Lv 1, Butter (2) in spot 2 at Lv 3, Toast (3) in the Toy Box at Lv 1;
	-- 10,000 Coins.
	local function foodWorld(): (World, any)
		local w, a = screenWorld()
		a.pen.items[2].level = 3
		a.coins = 10_000
		return w, a
	end

	local function levelsOf(profile: any): { number }
		local list = {}
		for _, item in profile.pen.items do
			table.insert(list, item.level)
		end
		return list
	end

	local function foodReply(profile: any, levels: number, charged: boolean): any
		return {
			pen = TableUtil.deepCopy(profile.pen),
			food = TableUtil.deepCopy(profile.food),
			levels = levels,
			charged = charged,
			savePending = false,
		}
	end

	t.test("BuyFood, Feed and FeedAll take a food id, a count, a price, an item id, a requestId; 2 a second", function()
		expect.deepEqual(Remotes.SPEC.BuyFood.args, {
			{ name = "foodId", type = "string" },
			{ name = "count", type = "integer" },
			{ name = "expectedPrice", type = "coins" },
			{ name = "requestId", type = "requestId" },
		})
		expect.deepEqual(
			Remotes.SPEC.Feed.args,
			{ { name = "itemId", type = "integer" }, { name = "requestId", type = "requestId" } }
		)
		expect.deepEqual(Remotes.SPEC.FeedAll.args, {})
		for _, name in { "BuyFood", "Feed", "FeedAll" } do
			expect.equal(Remotes.SPEC[name].kind, "RemoteFunction")
			expect.equal(Remotes.SPEC[name].dir, "c2s")
			expect.deepEqual(Config.Net.Remotes[name], { rate = 2, burst = 3, oneInFlight = true })
		end
		local clock = FakeClock.new(100)
		local guard = NetService.newGuard({ clock = clock.now })
		local player = { UserId = 9 }
		expect.equal(guard:check(player, "BuyFood", 4, "candy_drop", 2, 800, REQ), "ok")
		expect.equal(guard:check(player, "BuyFood", 4, "candy_drop", 2, -1, REQ), "invalid")
		expect.equal(guard:check(player, "Feed", 2, 3, REQ), "ok")
		expect.equal(guard:check(player, "Feed", 2, 3, "not-a-guid"), "invalid")
		expect.equal(guard:check(player, "FeedAll", 0), "ok")
		expect.equal(guard:check(player, "FeedAll", 1, 5), "badArgCount")
	end)

	t.test(
		"buy food: the server's price, one 'food' spend, the pieces added, the food sent, an awaited save",
		function()
			local w, a = foodWorld()
			local bBefore = TableUtil.deepCopy(w.profiles[w.b])
			local reply = PenService.buyFood(w.a, "candy_drop", 10, 4_000, REQ)
			expect.equal(reply.ok, true)
			expect.equal(a.food.candy_drop, 10)
			expect.equal(a.coins, 6_000)
			expect.deepEqual(w.spends, { { player = w.a, amount = 4_000, reason = "food" } })
			expect.deepEqual(reply.data, foodReply(a, 0, true))
			expect.equal(w.writes, 1)
			expect.deepEqual(w.foodSent, { w.a })
			expect.deepEqual(w.shown, {}) -- nothing on the plot changes
			expect.equal(w.nowSaves, 1)
			expect.deepEqual(w.grants, {})
			expect.deepEqual(w.profiles[w.b], bBefore) -- only the caller's own food
			-- A retry of the same request (its answer never arrived) replays: never charged twice.
			local again = PenService.buyFood(w.a, "candy_drop", 10, 4_000, REQ)
			expect.equal(again.ok, true)
			expect.equal(again.data.charged, true) -- as first answered
			expect.equal(a.food.candy_drop, 10)
			expect.equal(a.coins, 6_000)
			expect.equal(#w.spends, 1)
			expect.equal(w.writes, 1)
			-- A new request buys again.
			expect.equal(PenService.buyFood(w.a, "candy_drop", 1, 400, REQ2).ok, true)
			expect.equal(a.food.candy_drop, 11)
			finish()
		end
	)

	t.test(
		"buy food refusals, in order: invalid, not ready, unknown, not sold yet, full, price, paused, duel, coins",
		function()
			local w, a = foodWorld()
			for _, case in
				{
					{ "candy_drop", 1, 400, "not-a-guid" },
					{ 5, 1, 400, REQ },
					{ "candy_drop", 1.5, 600, REQ },
					{ "candy_drop", 1, -1, REQ },
					{ "pizza", 1, 400, REQ },
					{ "candy_drop", 0, 0, REQ },
					{ "candy_drop", Config.Economy.Food.maxBuy + 1, 400 * (Config.Economy.Food.maxBuy + 1), REQ },
				} :: { { any } }
			do
				expectRefused(PenService.buyFood(w.a, case[1], case[2], case[3], case[4]), "net.invalid")
			end
			w.status[w.a] = "offline"
			expectRefused(PenService.buyFood(w.a, "candy_drop", 1, 400, REQ), "data.notReady")
			w.status[w.a] = "ready"
			expectRefused(PenService.buyFood(w.a, "butter_bun", 1, 6_400, REQ), "food.notYet") -- biome 1
			a.food.candy_drop = Config.Economy.Food.maxPieces
			expectRefused(PenService.buyFood(w.a, "candy_drop", 1, 400, REQ), "food.full")
			a.food.candy_drop = 0
			expectRefused(PenService.buyFood(w.a, "candy_drop", 2, 400, REQ), "pen.priceChanged")
			w.savePending = true
			expectRefused(PenService.buyFood(w.a, "candy_drop", 1, 400, REQ), "pen.paused")
			w.savePending = false
			w.phase[w.a] = "Active"
			expectRefused(PenService.buyFood(w.a, "candy_drop", 1, 400, REQ), "inventory.lockedInDuel")
			w.phase[w.a] = ""
			a.coins = 399
			expectRefused(PenService.buyFood(w.a, "candy_drop", 1, 400, REQ), "economy.notEnoughCoins")
			expect.equal(w.writes, 0)
			expect.equal(w.nowSaves, 0)
			expect.deepEqual(w.spends, {})
			expect.equal(a.food.candy_drop, 0)
			-- A refused request is not remembered: the same id buys once it can.
			a.coins = 400
			expect.equal(PenService.buyFood(w.a, "candy_drop", 1, 400, REQ).ok, true)
			finish()
		end
	)

	t.test("feed: one level for its step's pieces, shown and sent, a soon save; a retry never feeds twice", function()
		local w, a = foodWorld()
		a.food.candy_drop = 5
		local reply = PenService.feed(w.a, 2, REQ) -- the Butter, Lv 3 -> 4: 2 Candy Drop
		expect.equal(reply.ok, true)
		expect.deepEqual(levelsOf(a), { 1, 4, 1 })
		expect.deepEqual(slotsOf(a), { 2, 1, 0 }) -- qb1: a feed re-sorts: the Butter, the best, takes the first spot
		expect.equal(a.food.candy_drop, 3)
		expect.deepEqual(reply.data, foodReply(a, 1, false))
		expect.equal(w.writes, 1)
		expect.deepEqual(w.shown, { w.a }) -- its coin label and card change
		expect.deepEqual(w.foodSent, { w.a })
		expect.deepEqual(w.soonSaves, { w.a })
		expect.equal(w.nowSaves, 0) -- no Coins move: a soon save, like a placement
		expect.deepEqual(w.spends, {})
		local again = PenService.feed(w.a, 2, REQ) -- its answer never arrived: the same request
		expect.equal(again.ok, true)
		expect.deepEqual(levelsOf(a), { 1, 4, 1 })
		expect.equal(a.food.candy_drop, 3)
		expect.equal(w.writes, 1)
		-- The Toy Box can be fed one at a time.
		expect.equal(PenService.feed(w.a, 3, REQ2).ok, true)
		expect.deepEqual(levelsOf(a), { 1, 4, 2 })
		expect.equal(a.food.candy_drop, 2)
		finish()
	end)

	t.test(
		"feed refusals, in order: invalid, not ready, not owned, top level, not enough food, paused, duel",
		function()
			local w, a = foodWorld()
			a.food.candy_drop = 1
			for _, case in { { 1.5, REQ }, { "2", REQ }, { 2, "not-a-guid" } } :: { { any } } do
				expectRefused(PenService.feed(w.a, case[1], case[2]), "net.invalid")
			end
			w.status[w.a] = "offline"
			expectRefused(PenService.feed(w.a, 2, REQ), "data.notReady")
			w.status[w.a] = "ready"
			expectRefused(PenService.feed(w.a, 99, REQ), "inventory.notOwned")
			expectRefused(PenService.feed(w.b, 2, REQ), "inventory.notOwned") -- never another player's squishy
			expectRefused(PenService.feed(w.a, 2, REQ), "food.notEnough") -- Lv 3 -> 4 takes 2
			a.pen.items[2].level = PenMath.levelCap()
			expectRefused(PenService.feed(w.a, 2, REQ), "pen.maxLevel")
			w.closing = true
			expectRefused(PenService.feed(w.a, 1, REQ), "pen.changePaused")
			w.closing = false
			w.phase[w.a] = "Active"
			expectRefused(PenService.feed(w.a, 1, REQ), "inventory.lockedInDuel")
			w.phase[w.a] = ""
			expect.equal(w.writes, 0)
			expect.deepEqual(w.soonSaves, {})
			expect.equal(a.food.candy_drop, 1)
			finish()
		end
	)

	-- Pens3 phase 13: the level cap is 10 a biome the highway reached (profile.highway.biome).
	t.test("pens3 phase 13: Feed, Feed All and BuyFood follow the biome the highway reached", function()
		local w, a = foodWorld()
		a.pen.items[2].level = 10 -- the Butter at Candy Meadow's top
		a.food.butter_bun = 5
		a.highway = { best = 0, biome = 1 }
		expectRefused(PenService.feed(w.a, 2, REQ), "pen.maxLevel")
		expectRefused(PenService.buyFood(w.a, "butter_bun", 1, 6_400, REQ2), "food.notYet")
		a.highway = { best = 320, biome = 2 } -- Bakery Town: Lv 20, Butter Bun on sale
		expect.equal(PenService.feed(w.a, 2, REQ).ok, true)
		expect.deepEqual(levelsOf(a), { 1, 11, 1 })
		expect.equal(PenService.buyFood(w.a, "butter_bun", 1, 6_400, REQ2).ok, true)
		expect.equal(a.food.butter_bun, 5) -- 5 - 1 fed + 1 bought
		a.food.candy_drop = 50
		expect.equal(PenService.feedAll(w.a).ok, true)
		for _, level in levelsOf(a) do
			expect.truthy(level <= 20)
		end
		finish()
	end)

	t.test(
		"feed all: the pen's squishies only, the weakest first, until the food runs out; a retry finds nothing",
		function()
			local w, a = foodWorld()
			a.food.candy_drop = 3
			-- Kitty Bread Lv 1 -> 2 (1), then Kitty Bread 2 -> 3 (1, still the weakest: the Butter is Lv 3); 1 left,
			-- and Kitty Bread's Lv 3 -> 4 takes 2 (as does the Butter's): it stops. The Toy Box Toast is never fed.
			local reply = PenService.feedAll(w.a)
			expect.equal(reply.ok, true)
			expect.deepEqual(levelsOf(a), { 3, 3, 1 })
			expect.equal(a.food.candy_drop, 1)
			expect.deepEqual(reply.data, foodReply(a, 2, false))
			expect.equal(w.writes, 1)
			expect.deepEqual(w.shown, { w.a })
			expect.deepEqual(w.foodSent, { w.a })
			expect.deepEqual(w.soonSaves, { w.a })
			expect.deepEqual(w.spends, {})
			expectRefused(PenService.feedAll(w.a), "pen.nothingToFeed") -- a retry: nothing left it can feed
			w.status[w.a] = "offline"
			expectRefused(PenService.feedAll(w.a), "data.notReady")
			w.status[w.a] = "ready"
			a.food.candy_drop = 50
			w.restart = true
			expectRefused(PenService.feedAll(w.a), "pen.changePaused")
			w.restart = false
			w.phase[w.a] = "Active"
			expectRefused(PenService.feedAll(w.a), "inventory.lockedInDuel")
			w.phase[w.a] = ""
			expect.equal(w.writes, 1)
			-- Plenty (Lv 3 -> 10 takes 40 each): both placed squishies to the cap, never past it.
			a.food.candy_drop = 100
			expect.equal(PenService.feedAll(w.a).ok, true)
			expect.deepEqual(levelsOf(a), { PenMath.levelCap(), PenMath.levelCap(), 1 })
			expect.equal(a.food.candy_drop, 20)
			finish()
		end
	)
	-- The shelf rows and the TOP spot (pens3 phase 11; Neon Sugar part 5: one cubby a row, 2 from the start) ---------

	-- A's pen with the shelf's start rows (a sanitized save always has shelfRows and top).
	local function withShelf(w: World, rows: number, top: boolean): any
		local a = w.profiles[w.a]
		a.pen.shelfRows, a.pen.top = rows, top
		return a
	end

	t.test(
		"PenBuyShelf takes only the expected price: it names no base, plot or player; 1 a second, one at a time",
		function()
			local spec = Remotes.SPEC.PenBuyShelf
			expect.equal(spec.kind, "RemoteFunction")
			expect.equal(spec.dir, "c2s")
			expect.deepEqual(spec.args, { { name = "expectedPrice", type = "coins" } })
			expect.deepEqual(Config.Net.Remotes.PenBuyShelf, { rate = 1, burst = 1, oneInFlight = true })
			local clock = FakeClock.new(100)
			local guard = NetService.newGuard({ clock = clock.now })
			local player = { UserId = 9 }
			expect.equal(guard:check(player, "PenBuyShelf", 1, 1_000_000_000_000_000), "ok")
			expect.equal(guard:check(player, "PenBuyShelf", 1, 300_000_000), "rateLimited")
		end
	)

	t.test("a shelf buy: cubby 3 for 300M, it takes the best Toy Box squishy, an awaited save", function()
		local w = fresh()
		local a = withShelf(w, 2, false)
		a.coins = 400_000_000
		local toast = { id = 2, kind = "toast", form = 0, level = 1, coat = 0, slot = 0, locked = false }
		local bird = { id = 3, kind = "bird", form = 0, level = 1, coat = 0, slot = 0, locked = false }
		local dragon = { id = 4, kind = "dragon", form = 0, level = 1, coat = 0, slot = 0, locked = true } -- locked
		local banana = { id = 5, kind = "banana", form = 0, level = 1, coat = 0, slot = 13, locked = false }
		local butter = { id = 6, kind = "butter", form = 0, level = 1, coat = 0, slot = 14, locked = false }
		for _, it in { toast, bird, dragon, banana, butter } do
			table.insert(a.pen.items, it)
		end
		a.pen.items[1].slot, a.pen.spots = 1, 3
		table.insert(a.pen.items, { id = 7, kind = "toast", form = 0, level = 1, coat = 0, slot = 2, locked = false })
		table.insert(a.pen.items, { id = 8, kind = "toast", form = 0, level = 1, coat = 0, slot = 3, locked = false })
		local reply = PenService.buyShelf(w.a, 300_000_000)
		expect.equal(reply.ok, true)
		expect.deepEqual(reply.data, { pen = TableUtil.deepCopy(a.pen), charged = true, savePending = false })
		expect.equal(a.pen.shelfRows, 3)
		expect.equal(a.pen.top, false)
		-- The new spot takes the best unlocked Toy Box squishy (Bird), then (qb1) the shelf holds the best: Bird 13,
		-- Butter 14, then the 10-a-second ones by id (Kitty Bread 15), the rest in the pen.
		expect.equal(bird.slot, 13)
		expect.equal(butter.slot, 14)
		expect.equal(a.pen.items[1].slot, 15)
		expect.equal(banana.slot, 1)
		expect.equal(toast.slot, 0) -- one new spot: the next Toast waits in the Toy Box
		expect.equal(dragon.slot, 0) -- locked: auto-place never moves it
		expect.equal(a.coins, 100_000_000)
		expect.deepEqual(w.spends, { { player = w.a, amount = 300_000_000, reason = "pen" } })
		expect.equal(w.nowSaves, 1)
		expect.deepEqual(w.shown, { w.a })
		expect.deepEqual(w.drops, { w.a }) -- the new spot makes room for a waiting gift
		finish()
	end)

	t.test("cubbies 3 .. 11, then the TOP spot, then max; a retry of an old price is never charged twice", function()
		local w = fresh()
		local a = withShelf(w, 2, false)
		a.coins = 2 * 10 ^ 15
		local order = {}
		for row = 3, PEN.shelfMaxRows do
			table.insert(order, PEN.shelfRowPrices[row])
		end
		table.insert(order, PEN.topPrice)
		expect.equal(#order, 10)
		local spent = 0
		for index, price in order do
			local reply = PenService.buyShelf(w.a, price)
			expect.equal(reply.ok, true)
			spent += price
			w.clock += PEN.buyCooldownSeconds
			if index < #order then
				expect.equal(a.pen.shelfRows, index + 2)
				expect.equal(a.pen.top, false)
			end
			-- The retry: a wrong price now (after the TOP spot: nothing left to buy).
			expectRefused(
				PenService.buyShelf(w.a, price),
				if index < #order then "pen.priceChanged" else "pen.shelfMax"
			)
			w.clock += PEN.buyCooldownSeconds
		end
		expect.equal(a.pen.shelfRows, 11)
		expect.equal(a.pen.top, true)
		expectRefused(PenService.buyShelf(w.a, 1_000_000_000_000_000), "pen.shelfMax")
		expect.equal(#w.spends, 10)
		expect.equal(a.coins, 2 * 10 ^ 15 - spent)
		finish()
	end)

	t.test(
		"shelf refusals: bad input, not ready, a wrong price, paused, cooling, in a duel, short of Coins: none charged",
		function()
			local w = fresh()
			local a = withShelf(w, 2, false)
			a.coins = 300_000_000
			local writes = w.writes
			for _, bad in { -1, 1.5, 0 / 0, "300000000", true } :: { any } do
				expectRefused(PenService.buyShelf(w.a, bad), "net.invalid")
			end
			w.status[w.a] = "offline"
			expectRefused(PenService.buyShelf(w.a, 300_000_000), "data.notReady")
			w.status[w.a] = "ready"
			expectRefused(PenService.buyShelf(w.a, 299_999_999), "pen.priceChanged")
			for _, flag in { "savePending", "closing", "restart" } do
				(w :: any)[flag] = true
				expectRefused(PenService.buyShelf(w.a, 300_000_000), "pen.paused");
				(w :: any)[flag] = false
			end
			w.phase[w.a] = "Active"
			expectRefused(PenService.buyShelf(w.a, 300_000_000), "inventory.lockedInDuel")
			w.phase[w.a] = ""
			w.spendFails = "savePending"
			expectRefused(PenService.buyShelf(w.a, 300_000_000), "pen.paused")
			w.spendFails = nil
			a.coins = 299_999_999
			expectRefused(PenService.buyShelf(w.a, 300_000_000), "economy.notEnoughCoins")
			-- A pen spot bought a moment ago cools the shelf sign too (one buy a second).
			a.coins = 10 ^ 13
			expect.equal(PenService.buy(w.a, 1_500).ok, true)
			expectRefused(PenService.buyShelf(w.a, 300_000_000), "pen.paused")
			-- A pen without shelfRows (never after sanitize) is not a shelf: net.invalid.
			a.pen.shelfRows = nil
			w.clock += PEN.buyCooldownSeconds
			expectRefused(PenService.buyShelf(w.a, 300_000_000), "net.invalid")
			expect.equal(#w.spends, 1) -- only the pen spot
			expect.equal(w.writes, writes + 1)
			finish()
		end
	)

	t.test("the tick pays the shelf's and the TOP spot's squishies like the pen's", function()
		local w = fresh()
		local a = withShelf(w, 2, true)
		table.insert(a.pen.items, { id = 2, kind = "butter", form = 0, level = 1, coat = 0, slot = 13, locked = false })
		table.insert(a.pen.items, { id = 3, kind = "dragon", form = 0, level = 1, coat = 0, slot = 24, locked = false })
		PenService.step(1)
		expect.deepEqual(grantsOf(w, w.a), { { player = w.a, amount = 10 + 40 + 640, reason = "pen" } })
		finish()
	end)

	-- INCOME step 1 (2026-10-26): PenBuyIncome ------------------------------------------------------------------------

	t.test("PenBuyIncome takes a line and a Coin price, one in flight; its max text exists", function()
		local spec = Remotes.SPEC.PenBuyIncome
		expect.equal(spec.kind, "RemoteFunction")
		expect.equal(spec.dir, "c2s")
		expect.deepEqual(spec.args, { { name = "line", type = "string" }, { name = "expectedPrice", type = "coins" } })
		expect.equal(Config.Net.Remotes.PenBuyIncome.oneInFlight, true)
		expect.truthy(type(t.requireShared("Strings").reason.pen.incomeMax) == "string")
	end)

	t.test("an INCOME buy: a 'pen' spend, the level up, shown, saved; no cooldown between levels", function()
		local w = fresh()
		local a = w.profiles[w.a]
		a.coins = 10_000_000
		local reply = PenService.buyIncome(w.a, "coins", 500_000)
		expect.equal(reply.ok, true)
		expect.deepEqual(a.pen.income, { coins = 1, all = 0 })
		expect.deepEqual(reply.data, { pen = TableUtil.deepCopy(a.pen), charged = true, savePending = false })
		expect.deepEqual(w.spends, { { player = w.a, amount = 500_000, reason = "pen" } })
		expect.equal(w.nowSaves, 1)
		expect.deepEqual(w.shown, { w.a })
		-- At once: the next level and an ALL EARNINGS level (many small buys: no spot cooldown).
		expect.equal(PenService.buyIncome(w.a, "coins", 1_600_000).ok, true)
		expect.equal(PenService.buyIncome(w.a, "all", 2_500_000).ok, true)
		expect.deepEqual(a.pen.income, { coins = 2, all = 1 })
		expect.equal(a.coins, 10_000_000 - 500_000 - 1_600_000 - 2_500_000)
		-- The tick pays the boosted rate: Kitty Bread 10 x 1.07^2 x 1.05 = 12.02.
		local before = #grantsOf(w, w.a)
		PenService.step(1)
		expect.equal(grantsOf(w, w.a)[before + 1].amount, 12)
		-- Another player's income is never touched.
		expect.equal(w.profiles[w.b].pen.income, nil)
		w.saveOk = false
		a.coins += 10_000_000
		expect.equal(PenService.buyIncome(w.a, "all", 7_500_000).data.savePending, true)
		finish()
	end)

	t.test("INCOME refusals: bad input, not ready, price, max, paused, duel, short: none charged", function()
		local w = fresh()
		local a = w.profiles[w.a]
		a.coins = 500_000
		local writes = w.writes
		local bads: { any } =
			{ { "gear", 500_000 }, { 7, 500_000 }, { "coins", -1 }, { "coins", 1.5 }, { "coins", "1" } }
		for _, bad in bads do
			expectRefused(PenService.buyIncome(w.a, bad[1], bad[2]), "net.invalid")
		end
		expectRefused(PenService.buyIncome(w.a, nil, 500_000), "net.invalid")
		w.status[w.a] = "offline"
		expectRefused(PenService.buyIncome(w.a, "coins", 500_000), "data.notReady")
		w.status[w.a] = "ready"
		expectRefused(PenService.buyIncome(w.a, "coins", 499_999), "pen.priceChanged")
		a.pen.income = { coins = 20, all = 0 }
		expectRefused(PenService.buyIncome(w.a, "coins", 1), "pen.incomeMax")
		a.pen.income = { coins = 0, all = 0 }
		for _, flag in { "savePending", "closing", "restart" } do
			(w :: any)[flag] = true
			expectRefused(PenService.buyIncome(w.a, "coins", 500_000), "pen.paused");
			(w :: any)[flag] = false
		end
		w.phase[w.a] = "Active"
		expectRefused(PenService.buyIncome(w.a, "coins", 500_000), "inventory.lockedInDuel")
		w.phase[w.a] = ""
		a.coins = 499_999
		expectRefused(PenService.buyIncome(w.a, "coins", 500_000), "economy.notEnoughCoins")
		expect.deepEqual(w.spends, {})
		expect.equal(w.writes, writes)
		expect.deepEqual(a.pen.income, { coins = 0, all = 0 })
		finish()
	end)
end
