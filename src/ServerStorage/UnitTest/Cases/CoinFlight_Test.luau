--!strict
-- CoinFlight_Test: StarterPlayerScripts.Client.UI.CoinFlight (the "+N" coin flight into the pill). Server only
-- (ServerStorage.UnitTest). Pure parts only: no instances, no Scheduler.
-- Contract (DESIGN §18.5.2 B2, §18.11):
--   * coinCount: clamp(round(amount / 40), 3, 8): 50 -> 3, 200 -> 5, 400 -> 8, 10,000 -> 8;
--   * path(0) is the source and path(1) the pill, and the arc rises above both ends;
--   * landings are 45 ms apart, the first after the 520 ms flight; the count-up lasts (k - 1) · 45 + 400 ms;
--   * a coin flies Quad In and grows 0.7 -> 1 over its first 120 ms.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local CoinFlight = t.requireClient("UI/CoinFlight")
	local Config = t.requireShared("Config")
	local FLIGHT = Config.UI.motion.coinFlight

	t.test("coin count: amount / 40 rounded, between 3 and 8", function()
		expect.equal(CoinFlight.coinCount(50), 3)
		expect.equal(CoinFlight.coinCount(200), 5)
		expect.equal(CoinFlight.coinCount(400), 8)
		expect.equal(CoinFlight.coinCount(10000), 8)
		expect.equal(CoinFlight.coinCount(220), 6) -- 5.5 rounds up
		expect.equal(CoinFlight.coinCount(0 / 0), FLIGHT.minCoins)
		expect.equal(CoinFlight.coinCount(-10), FLIGHT.minCoins)
	end)

	t.test("path: starts at the source, ends at the pill, and rises above both", function()
		local cases = {
			{ Vector2.new(640, 420), Vector2.new(60, 40) }, -- the result panel up to the pill (top-left)
			{ Vector2.new(100, 100), Vector2.new(500, 300) },
			{ Vector2.new(300, 200), Vector2.new(300, 200) },
		}
		for _, case in cases do
			local from, to = case[1], case[2]
			local first = CoinFlight.path(0, from, to)
			local last = CoinFlight.path(1, from, to)
			expect.near(first.X, from.X, 1e-6)
			expect.near(first.Y, from.Y, 1e-6)
			expect.near(last.X, to.X, 1e-6)
			expect.near(last.Y, to.Y, 1e-6)
			local highest = math.huge
			for i = 0, 100 do
				highest = math.min(highest, CoinFlight.path(i / 100, from, to).Y)
			end
			expect.truthy(highest < math.min(from.Y, to.Y)) -- screen Y grows downward: "above" is smaller
		end
		-- Out-of-range progress is clamped.
		local from, to = Vector2.new(10, 20), Vector2.new(30, 40)
		expect.near(CoinFlight.path(-1, from, to).X, from.X, 1e-6)
		expect.near(CoinFlight.path(2, from, to).Y, to.Y, 1e-6)
	end)

	t.test("landings are 45 ms apart and the count-up ends with the last coin", function()
		for k = FLIGHT.minCoins, FLIGHT.maxCoins do
			local times = CoinFlight.landingTimes(k)
			expect.equal(#times, k)
			expect.near(times[1], FLIGHT.ms / 1000, 1e-9)
			for i = 2, k do
				expect.near(times[i] - times[i - 1], FLIGHT.staggerMs / 1000, 1e-9)
			end
			expect.equal(CoinFlight.countMs(k), (k - 1) * FLIGHT.staggerMs + FLIGHT.countTailMs)
		end
		expect.equal(FLIGHT.staggerMs, 45)
		expect.equal(CoinFlight.countMs(3), 2 * 45 + 400)
		expect.equal(CoinFlight.countMs(8), 7 * 45 + 400)
	end)

	t.test("a coin flies Quad In and grows 0.7 -> 1 over its first 120 ms", function()
		local duration = FLIGHT.ms / 1000
		expect.equal(CoinFlight.progress(0), 0)
		expect.equal(CoinFlight.progress(-1), 0)
		expect.equal(CoinFlight.progress(duration), 1)
		expect.near(CoinFlight.progress(duration / 2), 0.25, 1e-6) -- Quad In: (1/2)^2
		expect.near(CoinFlight.scaleAt(0), FLIGHT.startScale, 1e-9)
		expect.equal(CoinFlight.scaleAt(FLIGHT.scaleInMs / 1000), 1)
		expect.equal(CoinFlight.scaleAt(duration), 1)
		local mid = CoinFlight.scaleAt(FLIGHT.scaleInMs / 2000)
		expect.truthy(mid > FLIGHT.startScale and mid < 1)
	end)
end
