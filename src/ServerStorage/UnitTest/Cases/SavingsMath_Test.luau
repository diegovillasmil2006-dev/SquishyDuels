--!strict
-- SavingsMath_Test: unit tests for ReplicatedStorage.Shared.SavingsMath and Shared.UpdateClock (big job item 8,
-- 2026-11-10: the savings bar and the "Next update in..." countdown). Server only (ServerStorage.UnitTest). Pure.
-- Contract:
--   * the savings goal is the cheapest next buy that lasts: the next pen spot or the next step of a gear line; equal
--     prices: the pen first; the bar is Coins / price, never over 1; nothing left to buy = no goal;
--   * the update date is a number of Unix seconds or a date text (UTC when no zone is written); anything else is no
--     date; the countdown reads days and hours, then hours and minutes, then minutes and seconds; "NEW UPDATE!" shows
--     for an hour from the date, then nothing; no date = no text at all (never a made-up countdown);
--   * the event pill keeps the event's line while an event is live or no date is set; else the update's line takes
--     the last UPDATE_SECONDS of every TURN_SECONDS.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local SavingsMath = t.requireShared("SavingsMath")
	local UpdateClock = t.requireShared("UpdateClock")
	local GearMath = t.requireShared("GearMath")
	local PenMath = t.requireShared("PenMath")
	local Strings = t.requireShared("Strings")

	-- The fewest and the most pen spots a pen can have (the first and the last spot with a price).
	local firstSpot: number?, lastSpot: number? = nil, nil
	for spot = 1, 100 do
		if PenMath.spotPrice(spot) ~= nil then
			firstSpot = firstSpot or spot
			lastSpot = spot
		end
	end
	local startPen = { spots = (firstSpot :: number) - 1 }
	local fullPen = { spots = lastSpot :: number }
	local fullGear: { [string]: number } = {}
	for _, line in GearMath.LINES do
		fullGear[line] = GearMath.maxStep(line)
	end

	t.test("the savings goal: the cheapest next buy, the bar is Coins / price", function()
		local penPrice = PenMath.spotPrice(firstSpot)
		local goal = SavingsMath.goal(penPrice / 4, startPen, nil)
		expect.equal(goal.kind, "pen")
		expect.equal(goal.step, firstSpot)
		expect.equal(goal.price, penPrice)
		expect.near(goal.share, 0.25, 1e-9)
		expect.equal(goal.ready, false)
		local rich = SavingsMath.goal(penPrice * 3, startPen, nil)
		expect.equal(rich.ready, true)
		expect.equal(rich.share, 1)
		expect.equal(rich.have, penPrice) -- never over the price
		-- gear only: the cheapest first step of the four lines
		local cheapest, cheapestLine = math.huge, nil
		for _, line in GearMath.LINES do
			local price = GearMath.price(line, 1)
			if price < cheapest then
				cheapest, cheapestLine = price, line
			end
		end
		local gearGoal = SavingsMath.goal(0, nil, {})
		expect.equal(gearGoal.kind, cheapestLine)
		expect.equal(gearGoal.step, 1)
		expect.equal(gearGoal.price, cheapest)
		expect.equal(gearGoal.share, 0)
		-- both: the cheaper of the two; with a full pen only gear is left
		local both = SavingsMath.goal(0, startPen, {})
		expect.equal(both.price, math.min(penPrice, cheapest))
		if penPrice <= cheapest then
			expect.equal(both.kind, "pen") -- equal prices: the pen first
		end
		expect.equal(SavingsMath.goal(0, fullPen, {}).kind, cheapestLine)
		-- a bought step moves the line's goal on to its next step
		local oneStep = SavingsMath.goal(0, fullPen, { [cheapestLine :: string] = 1 })
		expect.truthy(oneStep.kind ~= cheapestLine or oneStep.step == 2)
	end)

	t.test("the savings goal: nothing left to buy, or nothing known, is no goal; odd Coins count as 0", function()
		expect.equal(SavingsMath.goal(1e9, fullPen, fullGear), nil)
		expect.equal(SavingsMath.goal(100, nil, nil), nil)
		expect.equal(SavingsMath.goal(100, "pen" :: any, 7 :: any), nil)
		expect.equal(SavingsMath.goal(0 / 0, startPen, nil).share, 0)
		expect.equal(SavingsMath.goal(-50, startPen, nil).share, 0)
		expect.equal(SavingsMath.goal("lots" :: any, startPen, nil).have, 0)
	end)

	t.test("the update date: Unix seconds or a date text (UTC), anything else is no date", function()
		expect.equal(UpdateClock.parse(1800000000), 1800000000)
		expect.equal(UpdateClock.parse(1800000000.9), 1800000000)
		local want = DateTime.fromUniversalTime(2026, 12, 5, 18, 0, 0).UnixTimestamp
		expect.equal(UpdateClock.parse("2026-12-05T18:00:00Z"), want)
		expect.equal(UpdateClock.parse("2026-12-05T18:00:00"), want) -- no zone written: UTC
		expect.equal(UpdateClock.parse("2026-12-05 18:00"), want)
		expect.equal(UpdateClock.parse("  2026-12-05T18:00Z "), want)
		for _, junk in { "", "soon", "next friday", "2026-13-45T99:00:00Z" } do
			expect.equal(UpdateClock.parse(junk), nil)
		end
		for _, junk in { 0, -5, 0 / 0, math.huge } do
			expect.equal(UpdateClock.parse(junk), nil)
		end
		expect.equal(UpdateClock.parse(nil), nil)
		expect.equal(UpdateClock.parse(true), nil)
		expect.equal(UpdateClock.parse({}), nil)
	end)

	t.test("the countdown's words: days, then hours, then minutes; NEW UPDATE! for an hour; nothing without a date", function()
		expect.equal(UpdateClock.time(2 * 86400 + 5 * 3600 + 59), "2d 05h")
		expect.equal(UpdateClock.time(5 * 3600 + 12 * 60 + 3), "5h 12m")
		expect.equal(UpdateClock.time(12 * 60 + 5), "12:05")
		expect.equal(UpdateClock.time(9), "0:09")
		expect.equal(UpdateClock.time(-3), "0:00")
		local at = 1800000000
		expect.equal(UpdateClock.text(at, at - 90000), Strings.format(Strings.savings.update, { time = "1d 01h" }))
		expect.equal(UpdateClock.text(at, at - 1), Strings.format(Strings.savings.update, { time = "0:01" }))
		expect.equal(UpdateClock.text(at, at), Strings.savings.updateLive)
		expect.equal(UpdateClock.text(at, at + UpdateClock.LIVE_SECONDS - 1), Strings.savings.updateLive)
		expect.equal(UpdateClock.text(at, at + UpdateClock.LIVE_SECONDS), nil)
		expect.equal(UpdateClock.text(nil, at), nil)
		expect.equal(UpdateClock.text("tomorrow" :: any, at), nil)
		expect.equal(UpdateClock.text(0 / 0, at), nil)
	end)

	t.test("the event pill: the event's line alone when live or with no date; else the update takes its turn", function()
		local at = 1800000000
		local turn, share = UpdateClock.TURN_SECONDS, UpdateClock.UPDATE_SECONDS
		local base = (at - 86400) - (at - 86400) % turn -- the start of a turn, a day before the update
		local update = UpdateClock.text(at, base)
		expect.truthy(update ~= nil)
		expect.equal(UpdateClock.pill("Candy rain in 1:08", false, nil, base), "Candy rain in 1:08")
		for second = 0, turn - 1 do
			expect.equal(UpdateClock.pill("CANDY RAIN! 3:41", true, at, base + second), "CANDY RAIN! 3:41")
			local shown = UpdateClock.pill("Candy rain in 1:08", false, at, base + second)
			if second < turn - share then
				expect.equal(shown, "Candy rain in 1:08")
			else
				expect.equal(shown, UpdateClock.text(at, base + second))
			end
		end
		-- long after the update: the event's line alone again
		expect.equal(UpdateClock.pill("Candy rain in 1:08", false, at, at + 86400 + turn - 1), "Candy rain in 1:08")
		expect.truthy(share > 0 and share < turn)
	end)
end
