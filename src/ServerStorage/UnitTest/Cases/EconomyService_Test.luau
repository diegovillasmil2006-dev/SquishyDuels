--!strict
-- EconomyService_Test: unit tests for ServerScriptService.Server.Services.EconomyService.
-- Server only (ServerStorage.UnitTest). Edit mode: DataService is a fake data port (or a real DataService core on a
-- memory store / FakeDataStore, through StateService.portFrom), StateService is a recorder, the clock is fixed;
-- players are plain tables. Config values are read from the test's Shared copy (compared by value).
-- Contract (DESIGN §3.4, §3.9, §3.11, §6.1, §6.2, §6.5, §6.7, §12 #6, #14):
--   * Coins are whole numbers in [0, maxCoins], never negative; only the closed reason list; "debug" only when allowed;
--   * every change goes through DataService.mutate on a READY profile: loading, OFFLINE, READONLY and a session that
--     takes no more changes (the final leave snapshot) earn and spend nothing; spends also need no pending failed
--     save; every change marks coins + stats and fires CoinsChanged(player, coins, delta, reason); coinsEarned /
--     coinsSpent count real changes;
--   * grantSquishy adds {at, src}; a box duplicate is refunded a quarter of that box's price (spec 2026-10-12 §8),
--     any other duplicate changes nothing; Coins stop at 9 Qa, exact to the Coin;
--   * grantDuelResult records the duelLog entry (capped, oldest dropped), the duel stats and the Coins exactly once per
--     matchId, then asks for a "soon" save; an unready profile records nothing (duel.noRewardsOffline);
--   * the same-pair record (§6.7, §12 #15): a time only for a fully rewarded result (reduced and zero-Coin ones add
--     none), never twice for one matchId, per player; expired times and opponents dropped on every result; at most
--     samePairFullRewards times per opponent and Config.Data.caps.samePair opponents (the least recent go);
--   * end to end through a real DataService core: Coins, a squishy and a duel result survive a release and a reload
--     (memory store and FakeDataStore), and the same matchId never pays twice.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type World = {
	profiles: { [any]: any },
	statuses: { [any]: string },
	pending: { [any]: boolean },
	frozen: { [any]: boolean },
	dirty: { { player: any, field: string } },
	saves: { { player: any, reason: string } },
	mutations: number,
	debug: boolean,
	clock: number, -- deps.now()
}

local NOW = 1_790_000_000
local MATCH_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

return function(t: Context)
	local expect = t.expect
	local EconomyService = t.requireServer("Services/EconomyService")
	local StateService = t.requireServer("Services/StateService")
	local Config = t.requireShared("Config")
	local ECONOMY = Config.Economy

	local function newProfile(coins: number): any
		return {
			coins = coins,
			owned = { kitty_bread = { at = 1, src = "starter" } },
			equipped = "kitty_bread",
			stats = {
				coinsEarned = 0,
				coinsSpent = 0,
				squeezes = 0,
				duelsPlayed = 0,
				duelsWon = 0,
				duelsLost = 0,
				duelsDrawn = 0,
				eliminations = 0,
				boxesOpened = 0,
			},
			duelLog = {},
		}
	end

	local function recorderDeps(w: World, port: any): any
		return {
			data = port,
			markDirty = function(player: any, field: string)
				table.insert(w.dirty, { player = player, field = field })
			end,
			now = function(): number
				return w.clock
			end,
			debugAllowed = function(): boolean
				return w.debug
			end,
		}
	end

	local function newWorld(): World
		return {
			profiles = {},
			statuses = {},
			pending = {},
			frozen = {},
			dirty = {},
			saves = {},
			mutations = 0,
			debug = false,
			clock = NOW,
		}
	end

	local function setup(): World
		local w = newWorld()
		EconomyService.useDeps(recorderDeps(w, {
			getProfile = function(player: any): any?
				return w.profiles[player]
			end,
			status = function(player: any): string
				return w.statuses[player] or "loading"
			end,
			persisted = function(_player: any): boolean
				return true
			end,
			savePending = function(player: any): boolean
				return w.pending[player] == true
			end,
			statusReason = function(_player: any): string?
				return nil
			end,
			-- Like DataService.mutate: READY sessions only, and none once the final leave snapshot is taken.
			mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
				if w.statuses[player] ~= "ready" or w.frozen[player] then
					return false, "data.notReady"
				end
				w.mutations += 1
				return true, fn(w.profiles[player])
			end,
			requestSave = function(player: any, reason: string)
				table.insert(w.saves, { player = player, reason = reason })
			end,
			onLoaded = function(_handler: any) end,
			onStatusChanged = function(_handler: any) end,
		}))
		return w
	end

	local function readyPlayer(w: World, coins: number): (any, any)
		local player = { UserId = 1 }
		local profile = newProfile(coins)
		w.profiles[player] = profile
		w.statuses[player] = "ready"
		return player, profile
	end

	local function dirtyFields(w: World): { string }
		local list = {}
		for _, entry in w.dirty do
			if not table.find(list, entry.field) then
				table.insert(list, entry.field)
			end
		end
		table.sort(list)
		return list
	end

	-- Like DuelRewards: `full` marks a fully rewarded result (here: any result that pays Coins).
	local function duelResult(result: string, coins: number, opp: number?, matchId: string?): any
		return {
			coins = coins,
			logEntry = { matchId = matchId or MATCH_ID, opp = opp or 99, result = result, at = NOW, full = coins > 0 },
			eliminations = if result == "win" then 1 else 0,
		}
	end

	-- Coins -----------------------------------------------------------------------------------------------------------

	t.test(
		"grantCoins adds whole Coins through mutate, counts coinsEarned, marks coins + stats, fires CoinsChanged",
		function()
			local w = setup()
			local player, profile = readyPlayer(w, 10)
			local seen: { any } = {}
			local connection = EconomyService.CoinsChanged:connect(
				function(p: any, coins: number, delta: number, reason: string)
					table.insert(seen, { p = p, coins = coins, delta = delta, reason = reason })
				end
			)
			local added, why = EconomyService.grantCoins(player, 25, "squeeze")
			connection:disconnect()
			expect.equal(added, 25)
			expect.equal(why, nil)
			expect.equal(w.mutations, 1)
			expect.equal(profile.coins, 35)
			expect.equal(profile.stats.coinsEarned, 25)
			expect.deepEqual(dirtyFields(w), { "coins", "stats" })
			expect.equal(#seen, 1)
			expect.deepEqual(seen[1], { p = player, coins = 35, delta = 25, reason = "squeeze" })
			expect.equal(EconomyService.coins(player), 35)
			expect.equal(#w.saves, 0) -- the caller decides the save of a plain grant (§3.4)
		end
	)

	t.test("grantCoins refuses bad amounts and reasons outside the closed list", function()
		local w = setup()
		local player, profile = readyPlayer(w, 10)
		for _, bad in { -1, 1.5, 0 / 0, math.huge, ECONOMY.maxCoins + 1 } do
			local added, why = EconomyService.grantCoins(player, bad, "squeeze")
			expect.equal(added, 0)
			expect.equal(why, "invalid")
		end
		local added, why = EconomyService.grantCoins(player, 5, "lottery")
		expect.equal(added, 0)
		expect.equal(why, "reason")
		local debugAdded, debugWhy = EconomyService.grantCoins(player, 5, "debug")
		expect.equal(debugAdded, 0)
		expect.equal(debugWhy, "reason") -- "debug" only while allowed (Studio)
		expect.equal(profile.coins, 10)
		expect.equal(#w.dirty, 0)
		expect.equal(w.mutations, 0)
		w.debug = true
		expect.equal(EconomyService.grantCoins(player, 5, "debug"), 5)
		expect.equal(profile.stats.coinsEarned, 0) -- debug never inflates the stats
		for _, reason in ECONOMY.CoinReasons do
			expect.truthy(EconomyService.isReason(reason))
		end
	end)

	t.test("a grant is clamped at maxCoins (9 Qa) and returns what was really added", function()
		expect.equal(ECONOMY.maxCoins, 9_000_000_000_000_000) -- spec 2026-10-12 §12
		local w = setup()
		local player, profile = readyPlayer(w, ECONOMY.maxCoins - 10)
		expect.equal(EconomyService.grantCoins(player, 100, "duel_win"), 10)
		expect.equal(profile.coins, ECONOMY.maxCoins)
		expect.equal(EconomyService.grantCoins(player, 100, "duel_win"), 0)
		expect.equal(profile.coins, ECONOMY.maxCoins)
		-- Whole Coins stay exact up to the cap: 8 Qa + 2.9 Qa adds exactly 1 Qa.
		profile.coins = 8_000_000_000_000_000
		expect.equal(EconomyService.grantCoins(player, 2_900_000_000_000_000, "duel_win"), 1_000_000_000_000_000)
		expect.equal(profile.coins, ECONOMY.maxCoins)
	end)

	t.test("grants need a ready profile (loading, OFFLINE and READONLY earn nothing)", function()
		local w = setup()
		local player, profile = readyPlayer(w, 10)
		for _, status in { "loading", "offline", "readonly" } do
			w.statuses[player] = status
			local added, why = EconomyService.grantCoins(player, 5, "squeeze")
			expect.equal(added, 0)
			expect.equal(why, "notReady")
			expect.falsy(EconomyService.canEarn(player))
		end
		expect.equal(profile.coins, 10)
		w.statuses[player] = "ready"
		expect.truthy(EconomyService.canEarn(player))
	end)

	t.test("a session that takes no more changes (the final leave snapshot) earns and spends nothing", function()
		local w = setup()
		local player, profile = readyPlayer(w, 500)
		w.frozen[player] = true
		local seen = 0
		local connection = EconomyService.CoinsChanged:connect(function()
			seen += 1
		end)
		local added, why = EconomyService.grantCoins(player, 5, "squeeze")
		expect.equal(added, 0)
		expect.equal(why, "notReady")
		local ok, spendWhy = EconomyService.trySpend(player, 100, "box")
		expect.equal(ok, false)
		expect.equal(spendWhy, "notReady")
		expect.equal(EconomyService.grantSquishy(player, "toast", "shop").refused, "notReady")
		local grant = EconomyService.grantDuelResult(player, MATCH_ID, "win", duelResult("win", 200))
		connection:disconnect()
		expect.equal(grant.blockedReason, "duel.noRewardsOffline")
		expect.equal(profile.coins, 500)
		expect.equal(profile.owned.toast, nil)
		expect.equal(#profile.duelLog, 0)
		expect.equal(seen, 0)
		expect.equal(#w.dirty, 0)
		expect.equal(#w.saves, 0)
	end)

	t.test("trySpend takes Coins only when there are enough, never below 0", function()
		local w = setup()
		local player, profile = readyPlayer(w, 400)
		local seen: { number } = {}
		local connection = EconomyService.CoinsChanged:connect(function(_p: any, _coins: number, delta: number)
			table.insert(seen, delta)
		end)
		expect.equal(EconomyService.trySpend(player, 400, "box"), true)
		expect.equal(profile.coins, 0)
		expect.equal(profile.stats.coinsSpent, 400)
		local ok, why = EconomyService.trySpend(player, 1, "box")
		connection:disconnect()
		expect.equal(ok, false)
		expect.equal(why, "notEnoughCoins")
		expect.equal(profile.coins, 0)
		expect.equal(profile.stats.coinsSpent, 400)
		expect.deepEqual(seen, { -400 })
		expect.equal(EconomyService.CODES.notEnoughCoins, "economy.notEnoughCoins")
	end)

	t.test("trySpend is blocked while a failed save is pending and for unready profiles", function()
		local w = setup()
		local player, profile = readyPlayer(w, 1000)
		w.pending[player] = true
		local ok, why = EconomyService.trySpend(player, 400, "box")
		expect.equal(ok, false)
		expect.equal(why, "savePending")
		w.pending[player] = false
		w.statuses[player] = "offline"
		ok, why = EconomyService.trySpend(player, 400, "box")
		expect.equal(ok, false)
		expect.equal(why, "notReady")
		expect.equal(profile.coins, 1000)
		w.statuses[player] = "ready"
		for _, bad in { 0, -5, 2.5 } do
			ok, why = EconomyService.trySpend(player, bad, "box")
			expect.equal(ok, false)
			expect.equal(why, "invalid")
		end
		expect.equal(select(2, EconomyService.trySpend(player, 5, "lottery")), "reason")
		expect.equal(profile.coins, 1000)
	end)

	t.test("clampCoins keeps any value a whole number in [0, maxCoins]", function()
		expect.equal(EconomyService.clampCoins(12.9), 12)
		expect.equal(EconomyService.clampCoins(-4), 0)
		expect.equal(EconomyService.clampCoins(0 / 0), 0)
		expect.equal(EconomyService.clampCoins(math.huge), ECONOMY.maxCoins)
		expect.equal(EconomyService.clampCoins("12"), 0)
	end)

	-- Squishies -------------------------------------------------------------------------------------------------------

	t.test("grantSquishy adds an owned entry {at, src} and fires SquishyGranted", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		local granted: { any } = {}
		local connection = EconomyService.SquishyGranted:connect(function(p: any, id: string, source: string)
			table.insert(granted, { p = p, id = id, source = source })
		end)
		local result = EconomyService.grantSquishy(player, "toast", "shop")
		connection:disconnect()
		expect.deepEqual(result, { added = true, refund = 0 })
		expect.deepEqual(profile.owned.toast, { at = NOW, src = "shop" })
		expect.deepEqual(granted, { { p = player, id = "toast", source = "shop" } })
		expect.deepEqual(dirtyFields(w), { "owned" })
	end)

	t.test("a box duplicate is refunded a quarter of the box price; any other duplicate changes nothing", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		profile.owned.toast = { at = 5, src = "box" }
		profile.owned.dragon = { at = 6, src = "shop" }
		-- Spec 2026-10-12 §8: 25% of the box price; the free Treat Box counts the Snack Box's.
		local toastRefund = 37_500
		expect.equal(EconomyService.duplicateRefund("snack"), toastRefund)
		expect.equal(EconomyService.duplicateRefund("sweet"), 112_500_000)
		expect.equal(EconomyService.duplicateRefund("treat"), toastRefund)
		expect.equal(EconomyService.duplicateRefund("nope"), 0)
		local reasons: { string } = {}
		local connection = EconomyService.CoinsChanged:connect(function(_p: any, _c: number, _d: number, reason: string)
			table.insert(reasons, reason)
		end)
		local dup = EconomyService.grantSquishy(player, "toast", "box", "snack")
		expect.deepEqual(dup, { added = false, refund = toastRefund })
		expect.equal(profile.coins, toastRefund)
		expect.deepEqual(profile.owned.toast, { at = 5, src = "box" })
		local shopDup = EconomyService.grantSquishy(player, "dragon", "shop")
		connection:disconnect()
		expect.deepEqual(shopDup, { added = false, refund = 0 })
		expect.equal(profile.coins, toastRefund)
		expect.deepEqual(reasons, { "refund" })
		expect.deepEqual(dirtyFields(w), { "coins", "stats" })
	end)

	t.test("grantSquishy refuses unknown ids, unknown sources and unready profiles", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		expect.equal(EconomyService.grantSquishy(player, "unicorn", "shop").refused, "invalid")
		expect.equal(EconomyService.grantSquishy(player, "toast", "robux").refused, "invalid")
		w.statuses[player] = "readonly"
		expect.equal(EconomyService.grantSquishy(player, "toast", "shop").refused, "notReady")
		expect.equal(profile.owned.toast, nil)
	end)

	-- Duel results ----------------------------------------------------------------------------------------------------

	t.test("grantDuelResult records the result, counts the stats, pays duel_win and asks for a soon save", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		local reasons: { string } = {}
		local connection = EconomyService.CoinsChanged:connect(function(_p: any, _c: number, _d: number, reason: string)
			table.insert(reasons, reason)
		end)
		local grant = EconomyService.grantDuelResult(player, MATCH_ID, "win", duelResult("win", 200, 42))
		connection:disconnect()
		expect.deepEqual(grant, { coins = 200, recorded = true, alreadyGranted = false })
		expect.equal(w.mutations, 1) -- the whole result in one step
		expect.equal(profile.coins, 200)
		expect.deepEqual(profile.duelLog, { { matchId = MATCH_ID, opp = 42, result = "win", at = NOW, full = true } })
		expect.equal(profile.stats.duelsPlayed, 1)
		expect.equal(profile.stats.duelsWon, 1)
		expect.equal(profile.stats.eliminations, 1)
		expect.equal(profile.stats.coinsEarned, 200)
		expect.deepEqual(reasons, { "duel_win" })
		expect.deepEqual(w.saves, { { player = player, reason = "soon" } })
		expect.deepEqual(EconomyService.duelLog(player), profile.duelLog)
		-- A fully rewarded result adds its time to the same-pair record (§6.7), keyed by the opponent's userId.
		expect.deepEqual(profile.samePair, { ["42"] = { NOW } })
		expect.deepEqual(EconomyService.samePair(player), profile.samePair)
		expect.deepEqual(dirtyFields(w), { "coins", "stats" })
	end)

	t.test("exactly once: the same matchId pays nothing again and adds no entry", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		EconomyService.grantDuelResult(player, MATCH_ID, "loss", duelResult("loss", 60))
		w.clock = NOW + 5
		local again = EconomyService.grantDuelResult(player, MATCH_ID, "loss", duelResult("loss", 60))
		expect.deepEqual(again, { coins = 0, recorded = false, alreadyGranted = true })
		expect.equal(profile.coins, 60)
		expect.equal(#profile.duelLog, 1)
		expect.deepEqual(profile.samePair, { ["99"] = { NOW } }) -- the replay adds no second same-pair time
		expect.equal(profile.stats.duelsPlayed, 1)
		expect.equal(profile.stats.duelsLost, 1)
		expect.equal(#w.saves, 1)
	end)

	t.test("an ineligible result (0 Coins) still counts as played; a draw counts as drawn", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		local grant = EconomyService.grantDuelResult(player, MATCH_ID, "draw", duelResult("draw", 0))
		expect.deepEqual(grant, { coins = 0, recorded = true, alreadyGranted = false })
		expect.equal(profile.coins, 0)
		expect.equal(profile.stats.duelsPlayed, 1)
		expect.equal(profile.stats.duelsDrawn, 1)
		expect.equal(profile.stats.eliminations, 0)
		expect.equal(#profile.duelLog, 1)
		expect.equal(profile.duelLog[1].full, false) -- not fully rewarded: never counts for the same-pair rule (§6.7)
		expect.deepEqual(profile.samePair, {})
		expect.deepEqual(w.saves, { { player = player, reason = "soon" } })
	end)

	t.test("an unready profile records nothing and reports duel.noRewardsOffline", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		w.statuses[player] = "offline"
		local grant = EconomyService.grantDuelResult(player, MATCH_ID, "win", duelResult("win", 200))
		expect.deepEqual(grant, {
			coins = 0,
			recorded = false,
			alreadyGranted = false,
			blockedReason = "duel.noRewardsOffline",
		})
		expect.equal(#profile.duelLog, 0)
		expect.equal(profile.samePair, nil)
		expect.equal(profile.coins, 0)
		expect.equal(#w.saves, 0)
	end)

	t.test("cancelled, void, a mismatched entry or a missing entry record nothing", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		for _, outcome in { "cancelled", "void" } do
			local grant = EconomyService.grantDuelResult(player, MATCH_ID, outcome, duelResult("win", 200))
			expect.equal(grant.recorded, false)
		end
		local wrongMatch = duelResult("win", 200)
		wrongMatch.logEntry.matchId = "other"
		expect.equal(EconomyService.grantDuelResult(player, MATCH_ID, "win", wrongMatch).recorded, false)
		local wrongOutcome = duelResult("loss", 60)
		expect.equal(EconomyService.grantDuelResult(player, MATCH_ID, "win", wrongOutcome).recorded, false)
		expect.equal(EconomyService.grantDuelResult(player, MATCH_ID, "win", { coins = 200 }).recorded, false)
		expect.equal(EconomyService.grantDuelResult(player, "", "win", duelResult("win", 200, 9, "")).recorded, false)
		expect.equal(#profile.duelLog, 0)
		expect.equal(profile.samePair, nil)
		expect.equal(profile.coins, 0)
		expect.equal(#w.saves, 0)
	end)

	t.test("a reward above the largest duel reward is recorded without Coins", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		local grant = EconomyService.grantDuelResult(player, MATCH_ID, "win", duelResult("win", 1_000_000))
		expect.equal(grant.recorded, true)
		expect.equal(grant.coins, 0)
		expect.equal(profile.coins, 0)
		expect.equal(profile.duelLog[1].full, false) -- paid nothing, so not a fully rewarded result
		expect.deepEqual(profile.samePair, {})
	end)

	-- The same-pair record (§6.7, §12 #15) ------------------------------------------------------------------------------

	t.test("samePair: only fully rewarded results add a time; reduced and zero-Coin results do not", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		local reduced = duelResult("win", 50, 42, "reduced-1")
		reduced.logEntry.full = false -- DuelRewards: a reduced result is not fully rewarded
		expect.equal(EconomyService.grantDuelResult(player, "reduced-1", "win", reduced).coins, 50)
		local short = EconomyService.grantDuelResult(player, "short-1", "loss", duelResult("loss", 0, 42, "short-1"))
		expect.equal(short.recorded, true)
		expect.deepEqual(profile.samePair, {})
		expect.equal(#profile.duelLog, 2)
		w.clock = NOW + 30
		EconomyService.grantDuelResult(player, "full-1", "win", duelResult("win", 200, 42, "full-1"))
		expect.deepEqual(profile.samePair, { ["42"] = { NOW + 30 } })
		-- Reading: an entry without `full` that pays Coins counts as fully rewarded (fail closed).
		local unmarked = duelResult("draw", 100, 42, "unmarked-1")
		unmarked.logEntry.full = nil
		w.clock = NOW + 60
		EconomyService.grantDuelResult(player, "unmarked-1", "draw", unmarked)
		expect.deepEqual(profile.samePair, { ["42"] = { NOW + 30, NOW + 60 } })
	end)

	t.test("samePair: each player's record is their own", function()
		local w = setup()
		local alice, aliceProfile = readyPlayer(w, 0)
		local bob = { UserId = 2 }
		local bobProfile = newProfile(0)
		w.profiles[bob] = bobProfile
		w.statuses[bob] = "ready"
		-- One match: Alice (1) beats Bob (2) in full; Bob's loss pays nothing (too short for a loss).
		EconomyService.grantDuelResult(alice, MATCH_ID, "win", duelResult("win", 200, 2))
		EconomyService.grantDuelResult(bob, MATCH_ID, "loss", duelResult("loss", 0, 1))
		expect.deepEqual(aliceProfile.samePair, { ["2"] = { NOW } })
		expect.deepEqual(bobProfile.samePair, {})
		expect.deepEqual(EconomyService.samePair(bob), {})
		expect.deepEqual(EconomyService.samePair({ UserId = 3 }), {}) -- no profile
	end)

	t.test("samePair: trimmed by time on every result, whatever duelLog still holds", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		local window = ECONOMY.DuelRewards.samePairWindowSeconds
		profile.samePair = {
			["42"] = { NOW - window, NOW - 10 }, -- the first is exactly a window old: dropped
			["7"] = { NOW - window - 1 }, -- nothing left: the opponent goes
		}
		-- A zero-Coin result against someone else still trims the whole record.
		EconomyService.grantDuelResult(player, "m-1", "loss", duelResult("loss", 0, 5, "m-1"))
		expect.deepEqual(profile.samePair, { ["42"] = { NOW - 10 } })
		-- More full results than the limit against one opponent: only the newest samePairFullRewards stay.
		local limit = ECONOMY.DuelRewards.samePairFullRewards
		for i = 1, limit + 2 do
			w.clock = NOW + i
			EconomyService.grantDuelResult(player, "f-" .. i, "win", duelResult("win", 200, 42, "f-" .. i))
		end
		local times = profile.samePair["42"]
		expect.equal(#times, limit)
		expect.equal(times[1], NOW + 3)
		expect.equal(times[limit], NOW + limit + 2)
		-- duelLog is capped by count, the record by time: they are independent.
		expect.equal(#profile.duelLog, limit + 3)
	end)

	t.test("samePair: above Config.Data.caps.samePair opponents the least recent ones go", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		local cap = Config.Data.caps.samePair
		profile.samePair = {}
		for i = 1, cap do
			profile.samePair[tostring(1000 + i)] = { NOW - cap + i } -- 1001 is the least recent
		end
		EconomyService.grantDuelResult(player, MATCH_ID, "win", duelResult("win", 200, 42))
		local count = 0
		for _ in profile.samePair do
			count += 1
		end
		expect.equal(count, cap)
		expect.equal(profile.samePair["1001"], nil)
		expect.deepEqual(profile.samePair["1002"], { NOW - cap + 2 })
		expect.deepEqual(profile.samePair["42"], { NOW })
	end)

	t.test("samePair: a profile without the field (an older one) gets it on its first result", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		profile.samePair = "garbage"
		EconomyService.grantDuelResult(player, MATCH_ID, "win", duelResult("win", 200, 42))
		expect.deepEqual(profile.samePair, { ["42"] = { NOW } })
	end)

	t.test("duelLog keeps the newest Config.Data.caps.duelLog entries", function()
		local w = setup()
		local player, profile = readyPlayer(w, 0)
		local cap = Config.Data.caps.duelLog
		for i = 1, cap do
			table.insert(profile.duelLog, { matchId = "old-" .. i, opp = 5, result = "win", at = NOW - 10_000 + i })
		end
		EconomyService.grantDuelResult(player, MATCH_ID, "win", duelResult("win", 200))
		expect.equal(#profile.duelLog, cap)
		expect.equal(profile.duelLog[1].matchId, "old-2")
		expect.equal(profile.duelLog[cap].matchId, MATCH_ID)
	end)

	t.test("findLog / appendLog: the shared helpers for keyed, capped logs", function()
		local list: { any } = {}
		for i = 1, 3 do
			EconomyService.appendLog(list, { req = "r" .. i }, 2)
		end
		expect.deepEqual(list, { { req = "r2" }, { req = "r3" } })
		expect.deepEqual(EconomyService.findLog(list, "req", "r3"), { req = "r3" })
		expect.equal(EconomyService.findLog(list, "req", "r1"), nil)
		expect.equal(EconomyService.findLog(nil, "req", "r1"), nil)
	end)

	t.test("debugSetCoins works only while the debug reason is allowed", function()
		local w = setup()
		local player, profile = readyPlayer(w, 10)
		expect.falsy(EconomyService.debugSetCoins(player, 500))
		expect.equal(profile.coins, 10)
		w.debug = true
		expect.truthy(EconomyService.debugSetCoins(player, 500))
		expect.equal(profile.coins, 500)
		expect.equal(profile.stats.coinsEarned, 0)
		expect.falsy(EconomyService.debugSetCoins(player, -1))
		w.statuses[player] = "offline"
		expect.falsy(EconomyService.debugSetCoins(player, 7))
		expect.equal(profile.coins, 500)
	end)

	t.test("canSpend reads the data port", function()
		local w = setup()
		local player = readyPlayer(w, 10)
		expect.equal(EconomyService.canSpend(player), true)
		w.pending[player] = true
		local ok, why = EconomyService.canSpend(player)
		expect.equal(ok, false)
		expect.equal(why, "savePending")
	end)

	-- End to end through a real DataService core ----------------------------------------------------------------------

	-- A DataService core on `store` with a fixed clock and no real waits (spawn / defer run at once).
	local function newCore(store: any, nonce: string): any
		local DataService = t.requireServer("Services/DataService")
		return DataService.newCore({
			now = function(): number
				return NOW
			end,
			wait = function(_seconds: number) end,
			random = function(): number
				return 0
			end,
			storeFor = function(_userId: number): any
				return store
			end,
			jobId = "economy-test",
			newNonce = function(): string
				return nonce
			end,
			notify = function() end,
			spawn = function(fn: () -> ())
				fn()
			end,
			defer = function(fn: () -> ())
				fn()
			end,
		})
	end

	local function persistenceRoundTrip(store: any, persisted: boolean)
		local w = newWorld()
		local player = { UserId = 4242 }
		local first = newCore(store, "1111aaaa")
		expect.equal(first.loadAsync(player), "ready")
		expect.equal(first.isPersisted(player), persisted)
		EconomyService.useDeps(recorderDeps(w, StateService.portFrom(first)))
		expect.equal(EconomyService.grantCoins(player, 25, "squeeze"), 25)
		expect.deepEqual(EconomyService.grantSquishy(player, "toast", "shop"), { added = true, refund = 0 })
		local grant = EconomyService.grantDuelResult(player, MATCH_ID, "win", duelResult("win", 200, 77))
		expect.equal(grant.coins, 200)
		expect.equal(EconomyService.trySpend(player, 20, "box"), true)
		expect.truthy(first.releaseAsync(player))
		-- After the release the old session takes no changes.
		expect.equal(select(2, EconomyService.grantCoins(player, 5, "squeeze")), "notReady")

		-- Another server loads the same key.
		local second = newCore(store, "2222bbbb")
		expect.equal(second.loadAsync(player), "ready")
		EconomyService.useDeps(recorderDeps(w, StateService.portFrom(second)))
		local profile = second.getProfile(player)
		expect.equal(profile.coins, 205)
		expect.deepEqual(profile.owned.toast, { at = NOW, src = "shop" })
		expect.equal(#profile.duelLog, 1)
		expect.equal(profile.duelLog[1].matchId, MATCH_ID)
		expect.deepEqual(profile.samePair, { ["77"] = { NOW } }) -- the same-pair record survives too (§6.7)
		expect.equal(profile.stats.duelsWon, 1)
		expect.equal(profile.stats.coinsEarned, 225)
		expect.equal(profile.stats.coinsSpent, 20)
		-- The same match never pays twice, even on another server.
		local again = EconomyService.grantDuelResult(player, MATCH_ID, "win", duelResult("win", 200, 77))
		expect.equal(again.alreadyGranted, true)
		expect.equal(profile.coins, 205)
		expect.deepEqual(profile.samePair, { ["77"] = { NOW } })
		second.releaseAsync(player)
		EconomyService.useDeps(nil)
	end

	t.test("memory mode end to end: Coins, a squishy and a duel result survive a release and a reload", function()
		local InMemoryAdapter = t.requireServer("Data/InMemoryAdapter")
		persistenceRoundTrip(InMemoryAdapter.new("Memory"), false)
	end)

	t.test("datastore path end to end (FakeDataStore): the same, through UpdateAsync only", function()
		local FakeDataStore = t.requireFake("FakeDataStore")
		local store = FakeDataStore.new("PlayerData_v1_STUDIO")
		persistenceRoundTrip(store, true)
		expect.equal(store.forbiddenCalls, 0)
		expect.truthy(store.writes >= 2) -- the first load's lock and the release, at least
	end)
end
