--!strict
-- RateLimiter_Test: unit tests for ReplicatedStorage.Shared.Util.RateLimiter. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §2.2, §2.7, §2.8): a token bucket per key with an injectable clock. A new key starts with
-- `burst` tokens; tokens refill at `ratePerSecond` (may be fractional, e.g. 1/30) and never exceed `burst`;
-- a request that finds no token is rejected and does not reset the refill; keys never share tokens; a cost n
-- outside (0, burst] raises; a clock that jumps backwards removes no tokens and never credits the same time twice.
-- API (module header): RateLimiter.new(ratePerSecond, burst, clock?), limiter:take(key, n?) -> boolean,
-- limiter:reset(key). Time comes only from FakeClock, never from the wall clock.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local START_TIME = 1000

return function(t: Context)
	local RateLimiter = t.requireShared("Util/RateLimiter")
	local FakeClock = t.requireFake("FakeClock")
	local expect = t.expect

	-- A fresh limiter and clock per case keeps cases independent.
	local function makeLimiter(ratePerSecond: number, burst: number): (any, any)
		local clock = FakeClock.new(START_TIME)
		return RateLimiter.new(ratePerSecond, burst, clock.now), clock
	end

	-- Calls take(key) `attempts` times without moving the clock; returns how many were accepted.
	local function countAccepted(limiter: any, key: any, attempts: number): number
		local accepted = 0
		for _ = 1, attempts do
			if limiter:take(key) then
				accepted += 1
			end
		end
		return accepted
	end

	-- Burst ---------------------------------------------------------------------------------------------------

	-- A new key may spend its whole burst at once and nothing more.
	t.test("a new key allows exactly burst requests at once", function()
		local limiter = makeLimiter(1, 3)
		expect.equal(countAccepted(limiter, "player", 10), 3)
	end)

	-- With no time passing, an empty bucket stays empty.
	t.test("an empty bucket rejects every request while time stands still", function()
		local limiter = makeLimiter(1, 2)
		countAccepted(limiter, "player", 2)
		expect.equal(countAccepted(limiter, "player", 5), 0)
	end)

	-- Refill --------------------------------------------------------------------------------------------------

	-- At 2 tokens/s one token is back after 0.5 s, and only one.
	t.test("an empty bucket gets one token back after 1/rate seconds", function()
		local limiter, clock = makeLimiter(2, 3)
		countAccepted(limiter, "player", 3)
		clock.advance(0.5)
		expect.equal(countAccepted(limiter, "player", 5), 1)
	end)

	-- Half a token is not enough, but the half is kept: a rejected request does not reset the refill.
	t.test("partial refills accumulate across a rejected request", function()
		local limiter, clock = makeLimiter(2, 3)
		countAccepted(limiter, "player", 3)
		clock.advance(0.25)
		expect.falsy(limiter:take("player"))
		clock.advance(0.25)
		expect.truthy(limiter:take("player"))
	end)

	-- A long idle refills the bucket only up to burst.
	t.test("refill never exceeds burst after a long idle", function()
		local limiter, clock = makeLimiter(2, 3)
		countAccepted(limiter, "player", 3)
		clock.advance(1000)
		expect.equal(countAccepted(limiter, "player", 10), 3)
	end)

	-- Fractional rates (ReportIdle, PolicyRetry: 1 per 30 s) work: not before 30 s, yes after.
	t.test("a fractional rate of 1/30 refills one token in about 30 seconds", function()
		local limiter, clock = makeLimiter(1 / 30, 1)
		expect.truthy(limiter:take("player"))
		clock.advance(29)
		expect.falsy(limiter:take("player"))
		clock.advance(2)
		expect.truthy(limiter:take("player"))
	end)

	-- Keys --------------------------------------------------------------------------------------------------

	-- Draining one key leaves another key's bucket full.
	t.test("string keys are isolated from each other", function()
		local limiter = makeLimiter(1, 2)
		countAccepted(limiter, "alice", 5)
		expect.equal(countAccepted(limiter, "bob", 5), 2)
	end)

	-- Table keys (e.g. one per player object) are told apart by identity, not by contents.
	t.test("table keys with equal contents are still separate keys", function()
		local limiter = makeLimiter(1, 2)
		local first, second = { id = 1 }, { id = 1 }
		countAccepted(limiter, first, 5)
		expect.equal(countAccepted(limiter, second, 5), 2)
	end)

	-- Refill time for one key does not leak tokens to another key that is already drained.
	t.test("each key refills on its own schedule", function()
		local limiter, clock = makeLimiter(1, 1)
		expect.truthy(limiter:take("alice"))
		clock.advance(0.5)
		expect.truthy(limiter:take("bob"))
		clock.advance(0.5)
		expect.truthy(limiter:take("alice")) -- alice: 1 s since her last take
		expect.falsy(limiter:take("bob")) -- bob: only 0.5 s since his
	end)

	-- reset ---------------------------------------------------------------------------------------------------

	-- After reset (e.g. on PlayerRemoving) the key starts again from a full bucket.
	t.test("reset makes a drained key start full again", function()
		local limiter = makeLimiter(1, 3)
		countAccepted(limiter, "player", 3)
		limiter:reset("player")
		expect.equal(countAccepted(limiter, "player", 10), 3)
	end)

	-- Resetting one key leaves the others untouched.
	t.test("reset of one key does not refill another key", function()
		local limiter = makeLimiter(1, 2)
		countAccepted(limiter, "alice", 2)
		countAccepted(limiter, "bob", 2)
		limiter:reset("alice")
		expect.equal(countAccepted(limiter, "bob", 5), 0)
	end)

	-- Multi-token takes -------------------------------------------------------------------------------------

	-- take(key, n) spends n tokens; when fewer than n are available it takes nothing.
	t.test("take with n spends n tokens and takes nothing when fewer remain", function()
		local limiter = makeLimiter(1, 3)
		expect.truthy(limiter:take("player", 2))
		expect.falsy(limiter:take("player", 2))
		expect.truthy(limiter:take("player", 1)) -- the failed take(2) left the last token in place
		expect.falsy(limiter:take("player", 1))
	end)

	-- A cost that is not in (0, burst] is a programming error: a negative cost would add tokens, NaN would poison
	-- the bucket, and a cost above burst could never succeed.
	t.test("take rejects a cost that is not a number in (0, burst]", function()
		local limiter = makeLimiter(1, 2)
		for _, cost in { -1, 0, 0 / 0, 3, math.huge } do
			expect.throws(function()
				limiter:take("player", cost)
			end, "n must be")
		end
	end)

	-- An invalid cost changes nothing: a drained bucket stays drained.
	t.test("a rejected cost leaves the bucket unchanged", function()
		local limiter = makeLimiter(1, 1)
		expect.truthy(limiter:take("player"))
		pcall(function()
			limiter:take("player", -1)
		end)
		pcall(function()
			limiter:take("player", 0 / 0)
		end)
		expect.falsy(limiter:take("player"))
	end)

	-- Clock jumps --------------------------------------------------------------------------------------------

	-- Going back and then forward to the same time credits nothing new: no grant above the configured rate.
	t.test("a clock that jumps back and forward again never credits the same time twice", function()
		local limiter, clock = makeLimiter(1, 1)
		expect.truthy(limiter:take("player")) -- START_TIME: bucket empty
		clock.set(START_TIME - 50)
		expect.falsy(limiter:take("player"))
		clock.set(START_TIME)
		expect.falsy(limiter:take("player")) -- no time passed beyond START_TIME
		clock.advance(1)
		expect.truthy(limiter:take("player")) -- one real second later: one token
	end)

	-- A backward jump never removes tokens that were already there.
	t.test("a clock that jumps backwards keeps the tokens a key has", function()
		local limiter, clock = makeLimiter(1, 3)
		expect.truthy(limiter:take("player"))
		clock.set(START_TIME - 100)
		expect.equal(countAccepted(limiter, "player", 5), 2)
	end)

	-- Construction ------------------------------------------------------------------------------------------

	-- A zero or negative rate, or a burst below 1, is a programming error.
	t.test("new rejects a non-positive rate and a burst below 1", function()
		local clock = FakeClock.new(START_TIME)
		expect.throws(function()
			RateLimiter.new(0, 1, clock.now)
		end)
		expect.throws(function()
			RateLimiter.new(-1, 1, clock.now)
		end)
		expect.throws(function()
			RateLimiter.new(1, 0, clock.now)
		end)
	end)
end
