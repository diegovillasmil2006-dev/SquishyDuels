--!strict
-- RateLimiter (shared; mainly server remote guards, DESIGN §2.7). Token bucket per key.
-- Each key starts full (`burst` tokens) and refills at `ratePerSecond`, never above `burst`.
-- The clock is injectable for tests (default os.clock, a monotonic measurement clock). If an injected clock jumps
-- backwards, no tokens are removed and the time already credited is never credited again: refilling resumes once
-- the clock passes the latest time the key has seen.
-- Keys are held strongly: callers must reset(key) when a key goes away (e.g. on PlayerRemoving).
-- Weak keys are deliberately not used: an Instance key's Lua reference can be collected while the
-- Instance still exists, which would silently refill that bucket.

-- Types

type Bucket = {
	tokens: number,
	at: number,
}

type RateLimiterData = {
	_rate: number,
	_burst: number,
	_clock: () -> number,
	_buckets: { [any]: Bucket },
}

-- Module table

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable({} :: RateLimiterData, RateLimiter))

-- Public

-- ratePerSecond > 0 (may be fractional, e.g. 1/30); burst >= 1.
function RateLimiter.new(ratePerSecond: number, burst: number, clock: (() -> number)?): RateLimiter
	assert(ratePerSecond > 0 and ratePerSecond < math.huge, "[SD][RateLimiter] ratePerSecond must be > 0")
	assert(burst >= 1 and burst < math.huge, "[SD][RateLimiter] burst must be >= 1")
	local self: RateLimiterData = {
		_rate = ratePerSecond,
		_burst = burst,
		_clock = clock or os.clock,
		_buckets = {},
	}
	return setmetatable(self, RateLimiter)
end

-- Takes n tokens (default 1) for key. Returns false, and takes nothing, if fewer than n are available.
-- n must be a number with 0 < n <= burst (a larger cost could never succeed); anything else is a programming error.
function RateLimiter.take(self: RateLimiter, key: any, n: number?): boolean
	local cost = if n == nil then 1 else n
	assert(
		type(cost) == "number" and cost > 0 and cost <= self._burst,
		"[SD][RateLimiter] n must be a number with 0 < n <= burst"
	)
	local now = self._clock()
	local bucket = self._buckets[key]
	if bucket == nil then
		bucket = { tokens = self._burst, at = now }
		self._buckets[key] = bucket
	elseif now > bucket.at then
		-- Only time past the latest time seen is credited, so a clock that jumps back and forth never refills twice.
		bucket.tokens = math.min(self._burst, bucket.tokens + (now - bucket.at) * self._rate)
		bucket.at = now
	end
	if bucket.tokens < cost then
		return false
	end
	bucket.tokens -= cost
	return true
end

-- Forgets key; its next take() starts from a full bucket.
function RateLimiter.reset(self: RateLimiter, key: any)
	self._buckets[key] = nil
end

return RateLimiter
