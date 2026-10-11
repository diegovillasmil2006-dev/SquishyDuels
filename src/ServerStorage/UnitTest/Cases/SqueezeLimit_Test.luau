--!strict
-- SqueezeLimit_Test: unit tests for ReplicatedStorage.Shared.SqueezeLimit. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.3, §17.3.4, §17.3.6): a `{ value, at }` pool of points refills continuously at perHour (online
-- and offline) up to burst; current() = min(burst, value + max(0, now - at) × perHour / 3600); spend() pays when a
-- whole point is there and always returns the state to store (the refill up to now); full() = burst at now. One model
-- for the squeeze Coins limit (600/h, burst 300), Double Grip (240/h, burst 1200) and the slow-training bank (180/h,
-- burst 120): nonstop ticks every 10 s from a full bank pay every tick for about 40 minutes (239 ticks), then 1 in 2,
-- at most 300 in any hour. Odd input fails closed (non-finite or negative value = 0); a clock that went backwards
-- credits nothing twice.
-- Time comes only from fixed numbers, never from the wall clock.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

local T0 = 1_790_000_000 -- os.time()-like seconds
local TEST_LIMIT = { perHour = 600, burst = 300 } -- §6.3 numbers, fixed here so retuning Config never breaks the math
local TEST_BANK = { perHour = 180, burst = 120 } -- §17.3.6 numbers
local TICK_SECONDS = 10

return function(t: Context)
	local SqueezeLimit = t.requireShared("SqueezeLimit")
	local Config = t.requireShared("Config")
	local expect = t.expect

	-- Spends `count` times at time `now`; returns (paid count, last state).
	local function spendTimes(state: any, now: number, count: number, cfg: any): (number, any)
		local paid = 0
		for _ = 1, count do
			local ok
			ok, state = SqueezeLimit.spend(state, now, cfg)
			if ok then
				paid += 1
			end
		end
		return paid, state
	end

	-- Burst and refill ------------------------------------------------------------------------------------------

	t.test("a full pool pays exactly burst points at once", function()
		local paid = spendTimes(SqueezeLimit.full(T0, TEST_LIMIT), T0, TEST_LIMIT.burst + 5, TEST_LIMIT)
		expect.equal(paid, TEST_LIMIT.burst)
	end)

	t.test("full() is burst points at now", function()
		expect.deepEqual(SqueezeLimit.full(T0, TEST_LIMIT), { value = TEST_LIMIT.burst, at = T0 })
	end)

	t.test("an empty pool refills one point every 3600 / perHour seconds (6 s at 600/h)", function()
		local empty = { value = 0, at = T0 }
		expect.near(SqueezeLimit.current(empty, T0 + 6, TEST_LIMIT), 1)
		local early = SqueezeLimit.spend(empty, T0 + 5.9, TEST_LIMIT)
		expect.falsy(early)
		local onTime = SqueezeLimit.spend(empty, T0 + 6, TEST_LIMIT)
		expect.truthy(onTime)
	end)

	t.test("the refill never goes above burst, even after a day away", function()
		expect.equal(SqueezeLimit.current({ value = 10, at = T0 }, T0 + 86400, TEST_LIMIT), TEST_LIMIT.burst)
	end)

	t.test("an empty pool pays nothing while time stands still", function()
		local paid = spendTimes({ value = 0, at = T0 }, T0, 10, TEST_LIMIT)
		expect.equal(paid, 0)
	end)

	-- Returned state ---------------------------------------------------------------------------------------------

	t.test("a paid spend stores value - 1 at now", function()
		local paid, state = SqueezeLimit.spend({ value = 5, at = T0 }, T0 + 12, TEST_LIMIT)
		expect.truthy(paid)
		expect.near(state.value, 6) -- 5 + 12 s × 600/3600 = 7, minus 1
		expect.equal(state.at, T0 + 12)
	end)

	t.test("an unpaid spend still stores the refill up to now", function()
		local paid, state = SqueezeLimit.spend({ value = 0.5, at = T0 }, T0 + 1, TEST_LIMIT)
		expect.falsy(paid)
		expect.near(state.value, 0.5 + 1 / 6)
		expect.equal(state.at, T0 + 1)
	end)

	t.test("spend never changes the state it was given", function()
		local before = table.freeze({ value = 3, at = T0 })
		local paid, after = SqueezeLimit.spend(before, T0 + 60, TEST_LIMIT)
		expect.truthy(paid)
		expect.deepEqual(before, { value = 3, at = T0 })
		expect.truthy(after ~= before)
	end)

	-- Odd input ----------------------------------------------------------------------------------------------------

	t.test("a clock that went backwards refills nothing and keeps the later time", function()
		expect.equal(SqueezeLimit.current({ value = 0, at = T0 }, T0 - 100, TEST_LIMIT), 0)
		local paid, state = SqueezeLimit.spend({ value = 2, at = T0 }, T0 - 50, TEST_LIMIT)
		expect.truthy(paid)
		expect.deepEqual(state, { value = 1, at = T0 })
		-- Moving forward again credits only the time after T0.
		expect.near(SqueezeLimit.current(state, T0 + 6, TEST_LIMIT), 2)
	end)

	t.test("a non-finite or negative value counts as empty, a non-finite time as now", function()
		local nan = 0 / 0
		expect.equal(SqueezeLimit.current({ value = nan, at = T0 }, T0, TEST_LIMIT), 0)
		expect.equal(SqueezeLimit.current({ value = math.huge, at = T0 }, T0, TEST_LIMIT), 0)
		expect.equal(SqueezeLimit.current({ value = -5, at = T0 }, T0, TEST_LIMIT), 0)
		expect.falsy((SqueezeLimit.spend({ value = nan, at = T0 }, T0, TEST_LIMIT)))
		expect.equal(SqueezeLimit.current({ value = 5, at = nan }, T0, TEST_LIMIT), 5)
		local _, state = SqueezeLimit.spend({ value = 5, at = nan }, T0, TEST_LIMIT)
		expect.equal(state.at, T0)
	end)

	-- The three pools of Config -------------------------------------------------------------------------------

	t.test("Config: Coins limit 1 per 6 s, Double Grip 4 a minute, slow-training bank 3 a minute", function()
		local function perMinute(cfg: any): number
			return SqueezeLimit.current({ value = 0, at = T0 }, T0 + 60, cfg)
		end
		expect.near(perMinute(Config.Economy.SqueezeLimit), Config.Economy.SqueezeLimit.perHour / 60)
		expect.near(perMinute(Config.Grip.Rested), Config.Grip.Rested.perHour / 60)
		expect.near(perMinute(Config.Grip.Afk), Config.Grip.Afk.perHour / 60)
		-- DESIGN's numbers today: 600/h, 240/h, 180/h.
		expect.near(perMinute({ perHour = 600, burst = 300 }), 10)
		expect.near(perMinute({ perHour = 240, burst = 1200 }), 4)
		expect.near(perMinute({ perHour = 180, burst = 120 }), 3)
	end)

	t.test("Double Grip takes 5 h to fill from empty", function()
		local rested = { perHour = 240, burst = 1200 }
		expect.near(SqueezeLimit.current({ value = 0, at = T0 }, T0 + 5 * 3600, rested), 1200)
		expect.truthy(SqueezeLimit.current({ value = 0, at = T0 }, T0 + 5 * 3600 - 60, rested) < 1200)
	end)

	-- §17.3.6: nonstop resting from a full bank ----------------------------------------------------------------

	-- DESIGN: "nonstop resting is paid on every tick for the first 40 minutes (the bank drains by 3 a minute), then on
	-- 1 tick in 2 ... At most 300 ticks are paid in any hour." Reading of "the first 40 minutes", exact for this model:
	-- the first tick lands on a full bank (120), each tick adds 0.5 and spends 1, so ticks 1..239 pay
	-- (120 + 0.5 × 238 = 239 points) and tick 240 (39 min 50 s after the first) is the first unpaid one; after that
	-- exactly every other tick pays (180 an hour, the refill rate). The first hour pays 299, every rolling hour <= 300.
	t.test("nonstop ticks from a full bank: every tick for ~40 min, then 1 in 2, at most 300 in any hour", function()
		local state: any = SqueezeLimit.full(T0, TEST_BANK)
		local ticksPerHour = 3600 / TICK_SECONDS
		local paid: { boolean } = {}
		for k = 1, 3 * ticksPerHour do
			local ok
			ok, state = SqueezeLimit.spend(state, T0 + (k - 1) * TICK_SECONDS, TEST_BANK)
			paid[k] = ok
		end
		local firstUnpaid = table.find(paid, false)
		expect.equal(firstUnpaid, 240)
		for k = 241, #paid do
			if paid[k] ~= (k % 2 == 1) then
				error(
					string.format(
						"tick %d: paid = %s, want every other tick after the bank drained",
						k,
						tostring(paid[k])
					)
				)
			end
		end
		local function paidIn(from: number, to: number): number
			local count = 0
			for k = from, to do
				if paid[k] then
					count += 1
				end
			end
			return count
		end
		expect.equal(paidIn(1, ticksPerHour), 299)
		expect.equal(paidIn(2 * ticksPerHour + 1, 3 * ticksPerHour), TEST_BANK.perHour) -- steady state: 180 an hour
		for from = 1, #paid - ticksPerHour + 1 do
			local count = paidIn(from, from + ticksPerHour - 1)
			if count > 300 then
				error(string.format("%d ticks paid in the hour starting at tick %d", count, from))
			end
		end
	end)
end
