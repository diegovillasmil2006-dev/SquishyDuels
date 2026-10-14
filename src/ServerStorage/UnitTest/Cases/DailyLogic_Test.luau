--!strict
-- DailyLogic_Test: unit tests for ServerScriptService.Server.Logic.DailyLogic. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.9, §13.2 Part 7 L1): the day is floor(os.time() / 86400), so 23:59:59 UTC and 00:00:00 UTC are
-- different days and secondsUntilNext counts to midnight UTC; a second claim the same day is daily.alreadyClaimed;
-- claiming the day after continues the streak; a missed day only pauses it (review quick win 2026-10-14: the claim
-- after a gap pays the next day, never back to Day 1); a first-ever claim is Day 1, and after Day 7 the cycle restarts
-- at Day 1; rewards are 100/150/200/250/300/400/500 with the free Treat Box on Day 7 only.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local DAY = 86400
local TODAY = 20368 -- a UTC day index (2025-10-07)
local MIDNIGHT = TODAY * DAY -- 00:00:00 UTC of TODAY
local COINS = { 100, 150, 200, 250, 300, 400, 500 } -- §6.9

return function(t: Context)
	local DailyLogic = t.requireServer("Logic/DailyLogic")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local function state(lastClaimDay: number, streakDay: number): any
		return { lastClaimDay = lastClaimDay, streakDay = streakDay, totalClaims = 0 }
	end

	t.test("23:59:59 and 00:00:00 UTC fall on consecutive days", function()
		expect.equal(DailyLogic.dayIndex(MIDNIGHT - 1), TODAY - 1)
		expect.equal(DailyLogic.dayIndex(MIDNIGHT), TODAY)
		expect.equal(DailyLogic.dayIndex(MIDNIGHT + DAY - 1), TODAY)
		expect.equal(DailyLogic.dayIndex(MIDNIGHT + DAY), TODAY + 1)
	end)

	t.test("secondsUntilNext counts to the next 00:00 UTC", function()
		expect.equal(DailyLogic.secondsUntilNext(MIDNIGHT - 1), 1)
		expect.equal(DailyLogic.secondsUntilNext(MIDNIGHT), DAY)
		expect.equal(DailyLogic.secondsUntilNext(MIDNIGHT + 3600), DAY - 3600)
	end)

	t.test("a claim at 23:59:59 blocks the rest of that day; 00:00:00 opens the next claim", function()
		local claimedYesterday = state(DailyLogic.dayIndex(MIDNIGHT - 1), 3)
		local ok, reason = DailyLogic.canClaim(claimedYesterday, DailyLogic.dayIndex(MIDNIGHT - 1))
		expect.falsy(ok)
		expect.equal(reason, "daily.alreadyClaimed")
		local okNext, reasonNext = DailyLogic.canClaim(claimedYesterday, DailyLogic.dayIndex(MIDNIGHT))
		expect.truthy(okNext)
		expect.equal(reasonNext, nil)
		-- ... and it continues the streak.
		local streak = DailyLogic.nextStreak(claimedYesterday, DailyLogic.dayIndex(MIDNIGHT))
		expect.equal(streak, 4)
	end)

	t.test("the same day is daily.alreadyClaimed (also for a lastClaimDay in the future or not a number)", function()
		for _, last in { TODAY, TODAY + 3, 0 / 0, math.huge } do
			local ok, reason = DailyLogic.canClaim(state(last, 2), TODAY)
			expect.falsy(ok)
			expect.equal(reason, "daily.alreadyClaimed")
		end
		local fresh, why = DailyLogic.canClaim(state(-1, 0), TODAY)
		expect.truthy(fresh)
		expect.equal(why, nil)
	end)

	t.test("a missed day pauses the streak: the claim after a gap pays the next day, never Day 1", function()
		for _, last in { TODAY - 2, TODAY - 10, TODAY - 400 } do
			expect.equal(DailyLogic.nextStreak(state(last, 3), TODAY), 4)
		end
		-- After Day 7 a new cycle starts at Day 1, gap or not.
		expect.equal(DailyLogic.nextStreak(state(TODAY - 5, 7), TODAY), 1)
	end)

	t.test("a first-ever claim is Day 1", function()
		expect.equal(DailyLogic.nextStreak(state(-1, 0), TODAY), 1)
		expect.equal(DailyLogic.nextStreak(state(-1, 4), TODAY), 1)
	end)

	t.test("consecutive claims walk Day 1..7, then the cycle restarts at Day 1", function()
		local daily = state(-1, 0)
		local seen = {}
		for offset = 0, 8 do
			local today = TODAY + offset
			expect.truthy((DailyLogic.canClaim(daily, today)))
			local streak = DailyLogic.nextStreak(daily, today)
			table.insert(seen, streak)
			daily = state(today, streak)
		end
		expect.deepEqual(seen, { 1, 2, 3, 4, 5, 6, 7, 1, 2 })
	end)

	t.test("rewards follow §6.9 and only Day 7 gives the free Treat Box", function()
		for day, coins in COINS do
			expect.deepEqual(DailyLogic.reward(day), { coins = coins, freeBox = day == 7 })
		end
		expect.equal(Config.Economy.Daily.freeBoxDay, 7)
		expect.deepEqual(Config.Economy.Daily.coinsByDay, COINS)
		-- A streak day outside 1..7 (a hand edit) is clamped.
		expect.deepEqual(DailyLogic.reward(0), { coins = 100, freeBox = false })
		expect.deepEqual(DailyLogic.reward(9), { coins = 500, freeBox = true })
	end)

	t.test("a config copy can change the cycle and the free box day", function()
		local cfg = { coinsByDay = { 10, 20, 30 }, freeBoxDay = 3 }
		expect.deepEqual(DailyLogic.reward(3, cfg), { coins = 30, freeBox = true })
		expect.equal(DailyLogic.nextStreak(state(TODAY - 1, 3), TODAY, cfg), 1)
		-- A missed day pauses the streak in any cycle.
		expect.equal(DailyLogic.nextStreak(state(TODAY - 2, 1), TODAY, cfg), 2)
	end)
end
