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
--     unlocked Toy Box squishy in the buy's own step (a placed squishy never moves).

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
	}

	local function newProfile(): any
		return {
			coins = 0,
			owned = { kitty_bread = { at = 1, src = "starter" } },
			pen = {
				spots = 3,
				nextId = 2,
				items = { { id = 1, kind = "kitty_bread", form = 0, level = 1, coat = 0, slot = 1, locked = false } },
			},
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

	t.test("a bought spot takes the best unlocked Toy Box squishy in the buy's step; placed ones never move", function()
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
		expect.deepEqual(slotsOf(a), { 1, 2, 3, 0, 4, 0 })
		finish()
	end)
end
