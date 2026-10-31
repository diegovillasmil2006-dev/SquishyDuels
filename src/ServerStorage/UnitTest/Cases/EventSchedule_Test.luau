--!strict
-- EventSchedule_Test: ReplicatedStorage.Shared.EventSchedule (the timed events' clock and candy rules). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (2026-10-31, owner: candy rain, "Yes, build it"):
--   * an event starts every 15 minutes on the UTC clock and runs 5; the pill counts down to it, then the time left;
--   * a candy pays 10 s of the grabber's pen Coins a second, at least 100;
--   * 30 candies per player fall evenly over the event; spots stay inside the ring;
--   * the nearest player within the grab radius gets a candy, nobody farther.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local EventSchedule = t.requireShared("EventSchedule")
	local EVENTS = t.requireShared("Config/Events")
	local CANDY = EVENTS.CandyRain
	local LOOP = EVENTS.loopSeconds -- 900
	local BASE = 1_000 * LOOP -- a loop start on the clock

	t.test("owner's timing: an event every 15 minutes, 5 minutes long", function()
		expect.equal(LOOP, 900)
		expect.equal(EVENTS.liveSeconds, 300)
		expect.equal(CANDY.penSeconds, 10)
		expect.equal(CANDY.perPlayer, 30)
	end)

	-- BASE is loop 1000 (even): candy rain; the next loop golden luck (they take turns).
	local GOLDEN = BASE + LOOP

	t.test("at: live for the first 5 minutes of a loop, then waiting for the next one", function()
		local live = EventSchedule.at(BASE + 10)
		expect.equal(live.live, true)
		expect.equal(live.startsAt, BASE)
		expect.equal(live.endsAt, BASE + 300)
		expect.equal(live.kind, "candyRain")
		expect.equal(EventSchedule.at(GOLDEN + 10).kind, "goldenLuck")
		expect.equal(EventSchedule.at(GOLDEN + LOOP + 10).kind, "candyRain")
		local waiting = EventSchedule.at(BASE + 300)
		expect.equal(waiting.live, false)
		expect.equal(waiting.startsAt, BASE + LOOP)
		expect.equal(waiting.index, live.index + 1)
	end)

	t.test("pillText: the countdown while waiting, the time left while live", function()
		expect.equal(EventSchedule.pillText(BASE + 300), "Golden luck in 10:00") -- the next one takes its turn
		expect.equal(EventSchedule.pillText(GOLDEN + 300), "Candy rain in 10:00")
		expect.equal(EventSchedule.pillText(GOLDEN + LOOP - 1), "Candy rain in 0:01")
		expect.equal(EventSchedule.pillText(BASE + 79), "CANDY RAIN! 3:41")
	end)

	t.test("candyCoins: 10 s of the pen, at least 100; a broken rate pays the least", function()
		expect.equal(EventSchedule.candyCoins(10), 100)
		expect.equal(EventSchedule.candyCoins(2_500), 25_000)
		expect.equal(EventSchedule.candyCoins(0), 100)
		expect.equal(EventSchedule.candyCoins(0 / 0), 100)
	end)

	t.test("candiesDue: 30 a player spread over the event, never negative", function()
		expect.equal(EventSchedule.candiesDue(2, 0, 0), 0)
		expect.equal(EventSchedule.candiesDue(2, 150, 0), 30) -- half the event, half of 60
		expect.equal(EventSchedule.candiesDue(2, 150, 28), 2)
		expect.equal(EventSchedule.candiesDue(2, 300, 0), 60)
		expect.equal(EventSchedule.candiesDue(2, 999, 60), 0) -- capped at the event's end
		expect.equal(EventSchedule.candiesDue(1, 150, 40), 0) -- a player left: no catch-up below zero
	end)

	t.test("ringPoint: every spot is inside the ring around the Monument", function()
		for _, uv in { { 0, 0 }, { 0.25, 0.999 }, { 0.5, 0.5 }, { 0.99, 0.01 } } do
			local x, z = EventSchedule.ringPoint(uv[1], uv[2])
			local r = Vector2.new(x - CANDY.centre.X, z - CANDY.centre.Z).Magnitude
			expect.truthy(r >= CANDY.innerRadius - 1e-6 and r <= CANDY.outerRadius + 1e-6)
		end
	end)

	t.test("boxForm: golden luck gives Rainbow 1 in 100, Golden 1 in 10; nothing outside it", function()
		expect.equal(EVENTS.GoldenLuck.rainbowChance, 0.01)
		expect.equal(EVENTS.GoldenLuck.goldenChance, 0.10)
		local function rolls(value: number): () -> number
			return function(): number
				return value
			end
		end
		expect.equal(EventSchedule.boxForm(GOLDEN + 10, rolls(0.005)), 2)
		expect.equal(EventSchedule.boxForm(GOLDEN + 10, rolls(0.05)), 1)
		expect.equal(EventSchedule.boxForm(GOLDEN + 10, rolls(0.109)), 1)
		expect.equal(EventSchedule.boxForm(GOLDEN + 10, rolls(0.12)), 0)
		-- Outside golden luck no roll is taken, so the box draws stay exactly as before.
		local rolled = false
		local function spy(): number
			rolled = true
			return 0
		end
		expect.equal(EventSchedule.boxForm(GOLDEN + 400, spy), 0) -- golden luck is over
		expect.equal(EventSchedule.boxForm(BASE + 10, spy), 0) -- candy rain: no golden chance
		expect.equal(rolled, false)
	end)

	t.test("goldenOddsText: the odds line only while golden luck is live", function()
		expect.equal(EventSchedule.goldenOddsText(GOLDEN + 10), "Golden luck: 10% Golden, 1% Rainbow")
		expect.equal(EventSchedule.goldenOddsText(BASE + 10), nil)
		expect.equal(EventSchedule.pillText(GOLDEN + 79), "GOLDEN LUCK! 3:41")
	end)

	t.test("grabber: the nearest root within the radius, nobody beyond it", function()
		local candy = Vector3.new(0, 1, 0)
		local roots = { a = Vector3.new(4, 3, 0), b = Vector3.new(2, 3, 0), c = Vector3.new(9, 3, 0) }
		expect.equal(EventSchedule.grabber(candy, roots, CANDY.grabRadius), "b")
		expect.equal(EventSchedule.grabber(candy, { c = roots.c }, CANDY.grabRadius), nil)
		expect.equal(EventSchedule.grabber(candy, {}, CANDY.grabRadius), nil)
	end)
end
