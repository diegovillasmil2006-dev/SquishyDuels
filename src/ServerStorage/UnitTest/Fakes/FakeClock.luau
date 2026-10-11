--!strict
-- FakeClock: a manual clock for unit tests. Server only (ServerStorage.UnitTest; never required at runtime).
-- Time moves only when a test calls advance() or set(), so results never depend on the wall clock.
-- `clock.now` is a plain function (no colon), so it can be injected wherever a `() -> number` clock is expected:
--   local clock = FakeClock.new(100)
--   local limiter = RateLimiter.new(..., clock.now)
--   clock.advance(0.5)

export type FakeClock = {
	now: () -> number,
	advance: (dt: number) -> number,
	set: (t: number) -> (),
}

local FakeClock = {}

local function isFiniteNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Creates a clock that starts at `start` (default 0).
function FakeClock.new(start: number?): FakeClock
	local current = if start == nil then 0 else start
	assert(isFiniteNumber(current), "FakeClock.new: start must be a finite number")

	local clock = {} :: FakeClock

	-- Returns the current fake time in seconds.
	function clock.now(): number
		return current
	end

	-- Moves time forward by dt seconds (dt >= 0) and returns the new time.
	function clock.advance(dt: number): number
		assert(isFiniteNumber(dt) and dt >= 0, "FakeClock.advance: dt must be a finite number >= 0")
		current += dt
		return current
	end

	-- Jumps to time t (may go backwards, to test code that must tolerate clock jumps).
	function clock.set(t: number)
		assert(isFiniteNumber(t), "FakeClock.set: t must be a finite number")
		current = t
	end

	return clock
end

return FakeClock
