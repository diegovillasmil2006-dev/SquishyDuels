--!strict
-- CoinFlight_Test: StarterPlayerScripts.Client.UI.CoinFlight (the "+N" coin flight into the pill). Server only
-- (ServerStorage.UnitTest). Pure parts only: no instances, no Scheduler.
-- Contract (DESIGN §18.5.2 B2, §18.11; UI FINAL R2: the design's fly, hud-lib.js lib:269-286, plan §2.1):
--   * coinCount(count?) (G2.8): the design's 8 a gain (H:663) by default, a claim's 10 (H:746, H:856), a paid
--     squeeze's 1 (H:706), whole and within 1..10;
--   * a coin leaves within 15 px of the source, swings through a point up to 130 px to either side and 50-190 px above
--     the source (at 32% of its run eased by cubic-bezier(.25,.7,.35,1), the biggest, 1.15; these px x the flight's UI
--     scale) and lands on the pill at 0.55, its second leg eased by its own cubic-bezier(.55,0,.85,.55) (lib:281-283);
--   * each coin flies 720 ms + up to 220 ms, the coins 60 ms apart; the count-up (from the first landing) lasts
--     (k - 1) · 60 + 400 ms, so it never ends before the last coin lands.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local CoinFlight = t.requireClient("UI/CoinFlight")
	local Tweens = t.requireClient("Anim/Tweens")
	local Config = t.requireShared("Config")
	local FLIGHT = Config.UI.motion.coinFlight

	t.test("coin count (G2.8): the design's 8 a gain, a claim's 10, a paid squeeze's 1, within 1..10", function()
		expect.equal(FLIGHT.count, 8) -- H:663
		expect.equal(FLIGHT.maxCoins, 10)
		expect.equal(CoinFlight.coinCount(nil), 8)
		expect.equal(CoinFlight.coinCount(Config.UI.Fx.events.questClaim.coins), 10) -- H:746
		expect.equal(CoinFlight.coinCount(Config.UI.Fx.events.dailyClaim.coins), 10) -- H:856
		expect.equal(CoinFlight.coinCount(1), 1) -- a paid squeeze, H:706
		expect.equal(CoinFlight.coinCount(40), 10) -- capped at maxCoins
		expect.equal(CoinFlight.coinCount(2.7), 2)
		expect.equal(CoinFlight.coinCount(0), 1)
		expect.equal(CoinFlight.coinCount(0 / 0), 8) -- not a number: the default
	end)

	t.test("the swing point: up to 130 px to either side, 50-190 px above the source (lib:278)", function()
		local rng = Random.new(5)
		local from = Vector2.new(400, 300)
		local left, right = false, false
		for _ = 1, 500 do
			local mid = CoinFlight.midPoint(from, rng)
			local dx, up = mid.X - from.X, from.Y - mid.Y
			expect.truthy(math.abs(dx) <= FLIGHT.arcXPx + 1e-6)
			expect.truthy(up >= FLIGHT.arcUpMinPx - 1e-6 and up <= FLIGHT.arcUpMaxPx + 1e-6)
			left = left or dx < 0
			right = right or dx > 0
		end
		expect.truthy(left and right)
		local start = CoinFlight.startPoint(from, rng)
		expect.truthy(math.abs(start.X - from.X) <= FLIGHT.startJitterPx + 1e-6)
		expect.truthy(math.abs(start.Y - from.Y) <= FLIGHT.startJitterPx + 1e-6)
		-- Both scale with the flight's UI scale like its coins (the design's k, lib:277-278): a phone's 0.85.
		local far = 0
		for _ = 1, 500 do
			local mid = CoinFlight.midPoint(from, rng, 0.85)
			local dx, up = mid.X - from.X, from.Y - mid.Y
			expect.truthy(math.abs(dx) <= FLIGHT.arcXPx * 0.85 + 1e-6)
			expect.truthy(up >= FLIGHT.arcUpMinPx * 0.85 - 1e-6 and up <= FLIGHT.arcUpMaxPx * 0.85 + 1e-6)
			far = math.max(far, up)
			local jittered = CoinFlight.startPoint(from, rng, 0.85)
			expect.truthy(math.abs(jittered.X - from.X) <= FLIGHT.startJitterPx * 0.85 + 1e-6)
		end
		expect.truthy(far > FLIGHT.arcUpMaxPx * 0.85 * 0.9) -- the whole range is used
	end)

	t.test(
		"path: from the source through the swing point onto the pill; biggest at the swing, 0.55 on the pill",
		function()
			local from, mid, to = Vector2.new(640, 420), Vector2.new(560, 300), Vector2.new(60, 40)
			local first, last = CoinFlight.path(0, from, mid, to), CoinFlight.path(1, from, mid, to)
			expect.near(first.X, from.X, 1e-6)
			expect.near(first.Y, from.Y, 1e-6)
			expect.near(last.X, to.X, 1e-6)
			expect.near(last.Y, to.Y, 1e-6)
			-- The swing point is reached where the eased time crosses midAt.
			local u = CoinFlight.uAtEased(FLIGHT.midAt)
			local swing = CoinFlight.path(u, from, mid, to)
			expect.near(swing.X, mid.X, 1e-3)
			expect.near(swing.Y, mid.Y, 1e-3)
			expect.near(CoinFlight.scaleAt(0), 0, 1e-9)
			expect.near(CoinFlight.scaleAt(u), FLIGHT.midScale, 1e-3)
			expect.near(CoinFlight.scaleAt(1), FLIGHT.endScale, 1e-9)
			expect.equal(FLIGHT.endScale, 0.55)
			expect.near(CoinFlight.spinAt(0, 30), 0, 1e-9)
			expect.near(CoinFlight.spinAt(u, 30), 30, 1e-3)
			expect.near(CoinFlight.spinAt(1, 30), 0, 1e-9)
			-- The second leg follows its own curve (lib:281): halfway through that leg's eased time.
			local legU = CoinFlight.uAtEased(FLIGHT.midAt + (1 - FLIGHT.midAt) * 0.5)
			local onLeg = CoinFlight.path(legU, from, mid, to)
			local want = mid:Lerp(to, Tweens.curve("flyLeg")(0.5))
			expect.near(onLeg.X, want.X, 1e-2)
			expect.near(onLeg.Y, want.Y, 1e-2)
			-- Out of range is clamped.
			expect.near(CoinFlight.path(-1, from, mid, to).X, from.X, 1e-6)
			expect.near(CoinFlight.path(2, from, mid, to).Y, to.Y, 1e-6)
		end
	)

	t.test("lives and landings: 720 ms + up to 220, 60 ms apart; the count-up outlasts the last coin", function()
		expect.equal(FLIGHT.ms, 720)
		expect.equal(FLIGHT.jitterMs, 220)
		expect.equal(FLIGHT.staggerMs, 60)
		local rng = Random.new(9)
		for _ = 1, 200 do
			local life = CoinFlight.lifeMs(rng)
			expect.truthy(life >= FLIGHT.ms and life <= FLIGHT.ms + FLIGHT.jitterMs)
		end
		for k = 1, FLIGHT.maxCoins do
			local times = CoinFlight.landingTimes(k)
			expect.equal(#times, k)
			expect.near(times[1], FLIGHT.ms / 1000, 1e-9)
			for i = 2, k do
				expect.near(times[i] - times[i - 1], FLIGHT.staggerMs / 1000, 1e-9)
			end
			expect.equal(CoinFlight.countMs(k), (k - 1) * FLIGHT.staggerMs + FLIGHT.countTailMs)
			-- From the earliest first landing to the latest last one: the count-up is still running.
			expect.truthy(CoinFlight.countMs(k) >= (k - 1) * FLIGHT.staggerMs + FLIGHT.jitterMs)
		end
		expect.equal(CoinFlight.progress(-1, 0.72), 0)
		expect.near(CoinFlight.progress(0.36, 0.72), 0.5, 1e-9)
		expect.equal(CoinFlight.progress(1, 0.72), 1)
	end)
end
