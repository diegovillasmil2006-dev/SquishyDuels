--!strict
-- CapsuleService_Test: unit tests for ServerScriptService.Server.Services.CapsuleService with injected fakes (a fake
-- data port over plain profiles, recorders for Coins, Grip, attributes, spends and saves; players are plain tables).
-- Server only (ServerStorage.UnitTest). Edit mode: init() and start() are never called; ticks run through step(dt).
-- Contract (lobby bases spec 2026-10-11 §5-§6; big-number progression spec 2026-10-12 §3-§7, §10; plan Phase 3):
--   * the tick: a capsule that holds a squishy squeezes every CapsuleMath.seconds(level); each squeeze pays
--     capsuleCoins Coins (one "capsule" grant per player and tick) and CP Grip (one event per squeeze, never doubled)
--     and counts in SD_Squeezes<slot>; progress carries over between ticks; an empty capsule pays and keeps nothing;
--     only a READY profile of a player in the server is paid, and time out of it never pays;
--   * home taps: a paid own squeeze inside the caller's own plot pushes every capsule with a squishy 0.15 of a squeeze;
--     outside it, in another player's plot or without a plot, nothing;
--   * the remotes (CapsuleUpgrade / CapsuleUnlock / CapsuleSet) only change the caller's own capsules and no argument
--     names a base, plot or player; bad input is net.invalid; a wrong price capsule.priceChanged; then the order, the
--     Grip gate, the top level, an unopened slot, an unowned squishy; a duel inventory.lockedInDuel; paused while a
--     save is pending, the server closes or restarts; too few Coins economy.notEnoughCoins; every refusal charges
--     nothing; 1 call a second and one at a time (spam is rate-limited);
--   * a buy charges once with "capsule", writes the level or the slot, awaits one "now" save and replies the capsules;
--     an unlock retry is a replay; an upgrade retry carries the old price and is refused; CapsuleSet moves a squishy
--     out of the capsule that held it and asks for a "soon" save;
--   * Phase 4: every capsule change (a bought level or slot, a squishy set) redraws the caller's own base
--     (BaseService.refresh through deps.showCapsules); a refusal, a replay or a squishy already there does not;
--   * Batch 1: an open empty capsule takes the best spare squishy (owned, in no capsule, highest power, ties in Catalog
--     order) on a new grant (autoFill, ready only) and on an unlock; a placed squishy never moves; a fill redraws and
--     saves soon.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local CapsuleService = t.requireServer("Services/CapsuleService")
	local NetService = t.requireServer("Services/NetService")
	local CapsuleMath = t.requireShared("CapsuleMath")
	local Config = t.requireShared("Config")
	local Remotes = t.requireShared("Remotes")
	local TableUtil = t.requireShared("Util/TableUtil")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local FakeClock = t.requireFake("FakeClock")

	type World = {
		a: any,
		b: any,
		profiles: { [any]: any },
		status: { [any]: string },
		plots: { [any]: number },
		phase: { [any]: string },
		gripLevel: number,
		savePending: boolean,
		closing: boolean,
		restart: boolean,
		saveOk: boolean,
		spendFails: string?, -- a trySpend failure to force ("savePending")
		grants: { { player: any, amount: number, reason: string } },
		grip: { { player: any, amount: number } },
		attrs: { [string]: number }, -- "<UserId>:<name>" -> value
		spends: { { player: any, amount: number, reason: string } },
		nowSaves: number,
		saves: { string },
		shown: { any }, -- players whose base was redrawn (showCapsules)
	}

	local function newProfile(): any
		return {
			coins = 0,
			owned = {
				kitty_bread = { at = 1, src = "starter" },
				toast = { at = 2, src = "shop" },
				butter = { at = 3, src = "box" },
			},
			capsules = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } },
		}
	end

	local function fresh(): World
		local w: World = {
			a = { UserId = 1 },
			b = { UserId = 2 },
			profiles = {},
			status = {},
			plots = {},
			phase = {},
			gripLevel = 1,
			savePending = false,
			closing = false,
			restart = false,
			saveOk = true,
			spendFails = nil,
			grants = {},
			grip = {},
			attrs = {},
			spends = {},
			nowSaves = 0,
			saves = {},
			shown = {},
		}
		CapsuleService.reset()
		CapsuleService.useDeps({
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
			gripLevelOf = function(_player: any): number
				return w.gripLevel
			end,
			plotOf = function(player: any): number?
				return w.plots[player]
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
				w.profiles[player].coins += amount
				table.insert(w.grants, { player = player, amount = amount, reason = reason })
				return amount
			end,
			addGrip = function(player: any, amount: number): number
				table.insert(w.grip, { player = player, amount = amount })
				return amount
			end,
			saveNow = function(_player: any): boolean
				w.nowSaves += 1
				return w.saveOk
			end,
			requestSave = function(_player: any, reason: string)
				table.insert(w.saves, reason)
			end,
			setAttribute = function(player: any, name: string, value: number)
				w.attrs[`{player.UserId}:{name}`] = value
			end,
			showCapsules = function(player: any)
				table.insert(w.shown, player)
			end,
		})
		for index, player in { w.a, w.b } do
			w.profiles[player] = newProfile()
			w.status[player] = "ready"
			w.plots[player] = index
			CapsuleService.playerAdded(player)
		end
		return w
	end

	local function finish()
		CapsuleService.reset()
		CapsuleService.useDeps(nil)
	end

	-- A standing root position (3 studs up) at a plot point.
	local function inPlot(plot: number, x: number?, z: number?): Vector3
		return (WorldLayout.plotFrame(plot) :: CFrame) * Vector3.new(x or 0, 3, z or 0)
	end

	local function gripOf(w: World, player: any): { number }
		local list = {}
		for _, event in w.grip do
			if event.player == player then
				table.insert(list, event.amount)
			end
		end
		return list
	end

	local function expectRefused(reply: any, reason: string)
		expect.equal(reply.ok, false)
		expect.equal(reply.reason, reason)
		expect.equal(reply.charged, false)
	end

	-- The tick --------------------------------------------------------------------------------------------------------

	t.test("pay per squeeze matches CapsuleMath: Coins = power × CP ('capsule'), Grip = CP, never doubled", function()
		local w = fresh()
		local cp91 = CapsuleMath.power(91) :: number
		local list: { any } = {
			{ level = 1, squishyId = "kitty_bread" }, -- Foam: every 4.0 s, 10 Coins, 10 Grip
			{ level = 11, squishyId = "butter" }, -- Jelly: every 3.5 s, 4 × 68 Coins, 68 Grip
			{ level = 30 }, -- empty: nothing
			{ level = 91, squishyId = "toast" }, -- Royal: every 1.3 s, 1 × CP(91) Coins and Grip
		}
		w.profiles[w.a].capsules = { slots = 4, list = list }
		CapsuleService.step(14)
		-- 14 s: 3 squeezes (14 / 4), 4 squeezes (14 / 3.5), none, 10 squeezes (14 / 1.3), paid in one grant.
		local coins = 3 * 10 + 4 * 4 * 68 + 10 * cp91
		local aGrants = {}
		for _, grant in w.grants do
			if grant.player == w.a then
				table.insert(aGrants, grant)
			end
		end
		expect.deepEqual(aGrants, { { player = w.a, amount = coins, reason = "capsule" } })
		local events = gripOf(w, w.a)
		expect.equal(#events, 17) -- one Grip event per squeeze
		local total = 0
		for _, amount in events do
			total += amount
		end
		expect.equal(total, 3 * 10 + 4 * 68 + 10 * cp91) -- CP each: Double Grip never touches a capsule
		expect.equal(w.attrs["1:SD_Squeezes1"], 3)
		expect.equal(w.attrs["1:SD_Squeezes2"], 4)
		expect.equal(w.attrs["1:SD_Squeezes3"], nil)
		expect.equal(w.attrs["1:SD_Squeezes4"], 10)
		-- B's own Lv 1 Kitty Bread squeezed 3 times in the same 14 s.
		expect.equal(w.profiles[w.b].coins, 30)
		finish()
	end)

	t.test("progress carries over between ticks; an empty capsule keeps none", function()
		local w = fresh()
		for _ = 1, 3 do
			CapsuleService.step(1)
		end
		expect.equal(#w.grants, 0) -- 3 of the 4 s
		CapsuleService.step(1)
		expect.equal(w.profiles[w.a].coins, 10)
		expect.equal(w.attrs["1:SD_Squeezes1"], 1)
		-- 3 s while empty count for nothing: the squishy back in starts from 0.
		local capsule = w.profiles[w.a].capsules.list[1]
		capsule.squishyId = nil
		CapsuleService.step(3)
		capsule.squishyId = "kitty_bread"
		CapsuleService.step(1)
		expect.equal(w.profiles[w.a].coins, 10)
		CapsuleService.step(3)
		expect.equal(w.profiles[w.a].coins, 20)
		finish()
	end)

	t.test("only a ready profile of a player in the server is paid; time away never pays", function()
		local w = fresh()
		w.status[w.a] = "offline"
		CapsuleService.step(8)
		expect.equal(w.profiles[w.a].coins, 0)
		expect.equal(#gripOf(w, w.a), 0)
		w.status[w.a] = "ready"
		CapsuleService.step(1) -- the 8 s while not ready did not count
		expect.equal(w.profiles[w.a].coins, 0)
		CapsuleService.playerRemoving(w.a) -- left: no offline pay
		CapsuleService.step(40)
		expect.equal(w.profiles[w.a].coins, 0)
		expect.equal(w.profiles[w.b].coins, 2 * 10 + 10 * 10) -- B: 2 squeezes in the first 8 s, 10 in the 41 s after
		finish()
	end)

	-- Home taps -------------------------------------------------------------------------------------------------------

	t.test("taps inside your own base push every capsule 0.15 of a squeeze; outside it they do not", function()
		local w = fresh()
		expect.equal(Config.Grip.Capsule.tapPush, 0.15)
		local list: { any } = { { level = 1, squishyId = "kitty_bread" }, { level = 1 } } -- the empty one: no squeeze
		w.profiles[w.a].capsules = { slots = 2, list = list }
		for _ = 1, 6 do
			expect.truthy(CapsuleService.push(w.a, inPlot(1)))
		end
		CapsuleService.step(0)
		expect.equal(w.profiles[w.a].coins, 0) -- 6 × 0.15 = 0.9
		expect.truthy(CapsuleService.push(w.a, inPlot(1, 20, 25))) -- near a corner: still home
		CapsuleService.step(0)
		expect.equal(w.profiles[w.a].coins, 10) -- 7 × 0.15 = 1.05: one squeeze
		expect.equal(w.attrs["1:SD_Squeezes2"], nil)
		-- Outside: the hub, just past the gate, the neighbour's base; and a player with no plot.
		for _, outside in { Vector3.new(0, 3, 0), inPlot(1, 0, 27), inPlot(2), inPlot(10) } do
			expect.falsy(CapsuleService.push(w.a, outside))
		end
		w.plots[w.a] = nil
		expect.falsy(CapsuleService.push(w.a, inPlot(1)))
		CapsuleService.step(0)
		expect.equal(w.profiles[w.a].coins, 10)
		-- B standing in A's base pushes nothing of anyone's (taps count only in your own base).
		expect.falsy(CapsuleService.push(w.b, inPlot(1)))
		finish()
	end)

	-- The remotes -----------------------------------------------------------------------------------------------------

	t.test("no remote names a base, plot or player; they change only the caller's own capsules", function()
		local w = fresh()
		local names: { [string]: { string } } = {}
		for _, remote in { "CapsuleUpgrade", "CapsuleUnlock", "CapsuleSet" } do
			local spec = Remotes.SPEC[remote]
			expect.equal(spec.kind, "RemoteFunction")
			expect.equal(spec.dir, "c2s")
			names[remote] = {}
			for _, arg in spec.args do
				table.insert(names[remote], arg.name)
			end
		end
		expect.deepEqual(names, {
			CapsuleUpgrade = { "slot", "expectedPrice" },
			CapsuleUnlock = { "slot", "expectedPrice" },
			CapsuleSet = { "slot", "squishyId" },
		})
		-- A visitor (A, standing anywhere) can only ever reach A's own capsules: B's never change.
		w.profiles[w.a].coins = 1_000_000
		local before = TableUtil.deepCopy(w.profiles[w.b])
		expect.equal(CapsuleService.upgrade(w.a, 1, CapsuleMath.price(1)).ok, true)
		expect.equal(CapsuleService.unlock(w.a, 2, 2_500).ok, true)
		expect.equal(CapsuleService.set(w.a, 2, "toast").ok, true)
		expect.deepEqual(w.profiles[w.b], before)
		expect.equal(w.profiles[w.a].capsules.list[1].level, 2)
		finish()
	end)

	t.test("bad input is net.invalid and charges nothing", function()
		local w = fresh()
		w.profiles[w.a].coins = 1_000_000
		local price = CapsuleMath.price(1)
		local bad: { { any } } = { { 0, price }, { 5, price }, { 1.5, price }, { 1, -1 }, { 1, 0 / 0 }, { 1, "1000" } }
		for _, args in bad do
			expectRefused(CapsuleService.upgrade(w.a, args[1], args[2]), "net.invalid")
			expectRefused(CapsuleService.unlock(w.a, args[1], args[2]), "net.invalid")
		end
		local badSets: { { any } } = { { 0, "toast" }, { 5, "toast" }, { 1, "unicorn" }, { 1, 7 }, { "1", "toast" } }
		for _, args in badSets do
			expectRefused(CapsuleService.set(w.a, args[1], args[2]), "net.invalid")
		end
		expect.equal(#w.spends, 0)
		expect.equal(w.profiles[w.a].coins, 1_000_000)
		-- The argument range comes before the ready check (like TrainerUpgrade did).
		w.status[w.a] = "offline"
		expectRefused(CapsuleService.upgrade(w.a, 0, price), "net.invalid")
		expectRefused(CapsuleService.upgrade(w.a, 1, price), "data.notReady")
		expectRefused(CapsuleService.unlock(w.a, 2, 2_500), "data.notReady")
		expectRefused(CapsuleService.set(w.a, 1, "toast"), "data.notReady")
		finish()
	end)

	t.test("a buy charges once ('capsule'), saves now and replies the capsules; a wrong price is refused", function()
		local w = fresh()
		w.profiles[w.a].coins = 5_000
		expectRefused(CapsuleService.upgrade(w.a, 1, 999), "capsule.priceChanged")
		local reply = CapsuleService.upgrade(w.a, 1, 1_000)
		expect.equal(reply.ok, true)
		expect.deepEqual(reply.data, {
			capsules = { slots = 1, list = { { level = 2, squishyId = "kitty_bread" } } },
			charged = true,
			savePending = false,
		})
		expect.deepEqual(w.spends, { { player = w.a, amount = 1_000, reason = "capsule" } })
		expect.equal(w.profiles[w.a].coins, 4_000)
		expect.equal(w.nowSaves, 1)
		-- A retry carries the old price: Lv 2 -> 3 costs 1,300, so it is refused and nothing is charged twice.
		expectRefused(CapsuleService.upgrade(w.a, 1, 1_000), "capsule.priceChanged")
		expect.equal(#w.spends, 1)
		-- A failed now save keeps the purchase and says so.
		w.saveOk = false
		local unsaved = CapsuleService.upgrade(w.a, 1, CapsuleMath.price(2))
		expect.equal(unsaved.data.savePending, true)
		expect.equal(w.profiles[w.a].capsules.list[1].level, 3)
		finish()
	end)

	t.test(
		"unlock in order at the slot price; an open slot is a replay; a new capsule takes the best spare squishy",
		function()
			local w = fresh()
			w.profiles[w.a].coins = 100_000
			expectRefused(CapsuleService.unlock(w.a, 3, 80_000), "capsule.notNext")
			expectRefused(CapsuleService.unlock(w.a, 2, 2_000), "capsule.priceChanged")
			local reply = CapsuleService.unlock(w.a, 2, 2_500)
			expect.equal(reply.ok, true)
			expect.equal(reply.data.charged, true)
			local opened: { any } = { { level = 1, squishyId = "kitty_bread" }, { level = 1, squishyId = "butter" } }
			expect.deepEqual(w.profiles[w.a].capsules, { slots = 2, list = opened })
			expect.equal(w.profiles[w.a].coins, 97_500)
			local replay = CapsuleService.unlock(w.a, 2, 2_500)
			expect.equal(replay.ok, true)
			expect.equal(replay.data.charged, false)
			expect.equal(CapsuleService.unlock(w.a, 1, 0).data.charged, false)
			expect.equal(#w.spends, 1)
			expect.equal(w.nowSaves, 1) -- a replay saves nothing
			finish()
		end
	)

	t.test(
		"Batch 1: an unlock with no spare stays empty; ties go to Catalog order; a replay changes nothing",
		function()
			local w = fresh()
			local a = w.profiles[w.a]
			a.coins = 100_000
			a.owned = { kitty_bread = { at = 1, src = "starter" } } -- only the squishy already in capsule 1
			expect.equal(CapsuleService.unlock(w.a, 2, 2_500).ok, true)
			expect.deepEqual(a.capsules.list[2], { level = 1 })
			finish()
			-- Two Commons spare (Toast before Banana in the Catalog): the first one goes in.
			local v = fresh()
			local b = v.profiles[v.a]
			b.coins = 100_000
			b.owned.butter = nil
			b.owned.banana = { at = 4, src = "shop" }
			expect.equal(CapsuleService.unlock(v.a, 2, 2_500).ok, true)
			expect.equal(b.capsules.list[2].squishyId, "toast")
			local before = TableUtil.deepCopy(b.capsules)
			expect.equal(CapsuleService.unlock(v.a, 2, 2_500).data.charged, false) -- a replay
			expect.deepEqual(b.capsules, before)
			finish()
		end
	)

	t.test(
		"Batch 1: a new squishy fills every open empty capsule with the best spare; a placed squishy never moves",
		function()
			local w = fresh()
			local a = w.profiles[w.a]
			local list: { any } = { { level = 4, squishyId = "kitty_bread" }, { level = 2 }, { level = 1 } }
			a.capsules = { slots = 3, list = list }
			a.owned.nope = { at = 9, src = "box" } -- not in the Catalog: never placed
			local bBefore = TableUtil.deepCopy(w.profiles[w.b].capsules)
			expect.equal(CapsuleService.autoFill(w.a), true)
			local filled: { any } = {
				{ level = 4, squishyId = "kitty_bread" },
				{ level = 2, squishyId = "butter" },
				{ level = 1, squishyId = "toast" },
			}
			expect.deepEqual(a.capsules.list, filled)
			expect.deepEqual(w.shown, { w.a })
			expect.deepEqual(w.saves, { "soon" })
			-- Nothing left empty: a newer squishy waits (the player swaps it in).
			a.owned.banana = { at = 10, src = "shop" }
			expect.equal(CapsuleService.autoFill(w.a), false)
			expect.deepEqual(a.capsules.list, filled)
			expect.deepEqual(w.shown, { w.a })
			expect.deepEqual(w.saves, { "soon" })
			expect.deepEqual(w.profiles[w.b].capsules, bBefore)
			finish()
		end
	)

	t.test("Batch 1: auto-fill needs a ready profile and never fills a locked slot", function()
		local w = fresh()
		local a = w.profiles[w.a]
		local list: { any } = { { level = 1, squishyId = "kitty_bread" }, { level = 1 } }
		a.capsules = { slots = 2, list = list }
		w.status[w.a] = "offline"
		expect.equal(CapsuleService.autoFill(w.a), false)
		expect.equal(a.capsules.list[2].squishyId, nil)
		w.status[w.a] = "ready"
		a.capsules = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } }
		expect.equal(CapsuleService.autoFill(w.a), false)
		expect.equal(#a.capsules.list, 1)
		expect.deepEqual(w.shown, {})
		expect.deepEqual(w.saves, {})
		finish()
	end)

	t.test("the next level's Grip gate, the top level and an unopened slot are refused", function()
		local w = fresh()
		w.profiles[w.a].coins = 10_000_000
		local capsules = w.profiles[w.a].capsules
		capsules.list[1].level = 10
		local evolve = CapsuleMath.price(10) :: number -- Lv 10 -> 11: Jelly, Grip Lv 10
		w.gripLevel = 9
		expectRefused(CapsuleService.upgrade(w.a, 1, evolve), "capsule.gripLocked")
		w.gripLevel = 10
		expect.equal(CapsuleService.upgrade(w.a, 1, evolve).ok, true)
		expect.equal(capsules.list[1].level, 11)
		capsules.list[1].level = 100
		expectRefused(CapsuleService.upgrade(w.a, 1, 0), "capsule.maxLevel")
		expectRefused(CapsuleService.upgrade(w.a, 2, CapsuleMath.price(1)), "capsule.locked")
		expectRefused(CapsuleService.set(w.a, 2, "toast"), "capsule.locked")
		expect.equal(#w.spends, 1)
		finish()
	end)

	t.test("in a duel, paused or short of Coins: refused with nothing charged", function()
		local w = fresh()
		local price = CapsuleMath.price(1) :: number
		w.profiles[w.a].coins = price
		for _, phase in { "Preparing", "Active", "Returning" } do
			w.phase[w.a] = phase
			expectRefused(CapsuleService.upgrade(w.a, 1, price), "inventory.lockedInDuel")
			expectRefused(CapsuleService.unlock(w.a, 2, 2_500), "inventory.lockedInDuel")
			expectRefused(CapsuleService.set(w.a, 1, "toast"), "inventory.lockedInDuel")
		end
		w.phase[w.a] = ""
		w.savePending = true
		expectRefused(CapsuleService.upgrade(w.a, 1, price), "capsule.paused")
		w.savePending = false
		w.closing = true
		expectRefused(CapsuleService.upgrade(w.a, 1, price), "capsule.paused")
		w.closing = false
		w.restart = true
		expectRefused(CapsuleService.unlock(w.a, 2, 2_500), "capsule.paused")
		w.restart = false
		w.spendFails = "savePending"
		expectRefused(CapsuleService.upgrade(w.a, 1, price), "capsule.paused")
		w.spendFails = nil
		expectRefused(CapsuleService.unlock(w.a, 2, 2_500), "economy.notEnoughCoins")
		expect.equal(#w.spends, 0)
		expect.equal(w.profiles[w.a].coins, price)
		expect.equal(w.profiles[w.a].capsules.list[1].level, 1)
		finish()
	end)

	t.test(
		"CapsuleSet: an owned squishy goes in, moving out of the capsule that held it; unowned is refused",
		function()
			local w = fresh()
			local capsules = w.profiles[w.a].capsules
			capsules.slots = 2
			capsules.list[2] = { level = 4 }
			local reply = CapsuleService.set(w.a, 2, "toast")
			expect.equal(reply.ok, true)
			expect.equal(reply.data.charged, false)
			expect.equal(capsules.list[2].squishyId, "toast")
			-- One capsule per squishy: Toast moves to capsule 1 and leaves capsule 2 empty.
			expect.equal(CapsuleService.set(w.a, 1, "toast").ok, true)
			local moved: { any } = { { level = 1, squishyId = "toast" }, { level = 4 } }
			expect.deepEqual(capsules.list, moved)
			expect.deepEqual(w.saves, { "soon", "soon" })
			-- Already there: ok, nothing changes and nothing is saved.
			expect.equal(CapsuleService.set(w.a, 1, "toast").ok, true)
			expect.equal(#w.saves, 2)
			expectRefused(CapsuleService.set(w.a, 1, "dragon"), "inventory.notOwned")
			expect.equal(capsules.list[1].squishyId, "toast")
			expect.equal(#w.spends, 0)
			finish()
		end
	)

	t.test("a bought level or slot and a squishy set redraw the caller's base; refusals and replays do not", function()
		local w = fresh()
		w.profiles[w.a].coins = 10_000
		expectRefused(CapsuleService.upgrade(w.a, 1, 999), "capsule.priceChanged")
		expect.equal(#w.shown, 0)
		expect.equal(CapsuleService.upgrade(w.a, 1, CapsuleMath.price(1)).ok, true)
		expect.deepEqual(w.shown, { w.a })
		expect.equal(CapsuleService.unlock(w.a, 2, 2_500).ok, true)
		expect.equal(#w.shown, 2)
		expect.equal(CapsuleService.unlock(w.a, 2, 2_500).data.charged, false) -- a replay: nothing changed
		expect.equal(#w.shown, 2)
		expect.equal(CapsuleService.set(w.a, 2, "toast").ok, true)
		expect.equal(#w.shown, 3)
		expect.equal(CapsuleService.set(w.a, 2, "toast").ok, true) -- already there: nothing changes
		expectRefused(CapsuleService.set(w.a, 1, "dragon"), "inventory.notOwned")
		expect.equal(#w.shown, 3)
		for _, player in w.shown do
			expect.equal(player, w.a) -- only the caller's own base
		end
		finish()
	end)

	t.test("spam: 1 call a second and one at a time for each capsule remote", function()
		for _, remote in { "CapsuleUpgrade", "CapsuleUnlock", "CapsuleSet" } do
			expect.deepEqual(Config.Net.Remotes[remote], { rate = 1, burst = 1, oneInFlight = true })
		end
		local clock = FakeClock.new(100)
		local guard = NetService.newGuard({ clock = clock.now })
		local player = { UserId = 9 }
		expect.equal(guard:check(player, "CapsuleUpgrade", 2, 1, 1_100_000_000_000), "ok") -- prices reach trillions
		expect.equal(guard:check(player, "CapsuleUpgrade", 2, 1, 1_000), "rateLimited")
		clock.advance(1)
		expect.equal(guard:check(player, "CapsuleUpgrade", 2, 1, 1_000), "ok")
		expect.equal(guard:check(player, "CapsuleSet", 2, 1, "Dragon!"), "invalid") -- not a squishy id
		expect.equal(guard:check(player, "CapsuleUnlock", 3, 2, 2_500, "extra"), "badArgCount")
	end)
end
