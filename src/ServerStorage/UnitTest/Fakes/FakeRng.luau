--!strict
-- FakeRng: a stand-in for Roblox's Random in unit tests. Server only (ServerStorage.UnitTest; never required at
-- runtime). Two modes:
--   FakeRng.new({ 1, 10000, ... })  scripted: each NextInteger / NextNumber call returns the next value of the list, in
--                                   order (an exhausted list, or a value outside the call's range, raises an error so
--                                   a test can never pass by accident)
--   FakeRng.new(seed)               seeded: a deterministic counter-based generator (SplitMix-style, 32-bit, integer
--                                   math only), the same stream for the same seed on every machine and runner
-- NextInteger(min, max) returns an integer in [min, max]; NextNumber() a number in [0, 1); NextNumber(min, max) one in
-- [min, max). The result is typed as Random so it can be passed wherever game code takes one (BoxDraw.draw, a
-- QuestLogic rng factory: `QuestLogic.generate(ctx, FakeRng.new)`). `calls` counts the values handed out.

-- Types

type FakeState = {
	calls: number,
	NextInteger: (self: any, min: number, max: number) -> number,
	NextNumber: (self: any, min: number?, max: number?) -> number,
}

-- Constants

local TWO_16 = 65536
local TWO_32 = 4294967296
local GOLDEN = 0x9E3779B9 -- the 32-bit golden-ratio step
local MIX_1 = 0x85EBCA6B -- MurmurHash3 finalizer constants
local MIX_2 = 0xC2B2AE35

-- Module table

local FakeRng = {}

-- Private

-- (a × b) mod 2^32 for 32-bit unsigned a and b, exact in doubles (16-bit halves).
local function mul32(a: number, b: number): number
	local aHi, aLo = a // TWO_16, a % TWO_16
	local bHi, bLo = b // TWO_16, b % TWO_16
	local cross = (aHi * bLo + aLo * bHi) % TWO_16
	return (cross * TWO_16 + aLo * bLo) % TWO_32
end

-- MurmurHash3's 32-bit finalizer: spreads every input bit over the output.
local function fmix32(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, MIX_1)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, MIX_2)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

local function isFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Public

function FakeRng.new(source: number | { number }): Random
	local state: FakeState
	if type(source) == "table" then
		local values: { number } = table.clone(source)
		local nextIndex = 1
		local function take(): number
			local value = values[nextIndex]
			assert(value ~= nil, `FakeRng: the scripted sequence ran out after {nextIndex - 1} values`)
			nextIndex += 1
			return value
		end
		state = {
			calls = 0,
			NextInteger = function(self: any, min: number, max: number): number
				local value = take()
				self.calls += 1
				assert(
					math.floor(value) == value and value >= min and value <= max,
					`FakeRng: scripted NextInteger value {value} is not an integer in [{min}, {max}]`
				)
				return value
			end,
			NextNumber = function(self: any, min: number?, max: number?): number
				local value = take()
				self.calls += 1
				local lo, hi = min or 0, max or 1
				assert(value >= lo and value <= hi, `FakeRng: scripted NextNumber value {value} is not in [{lo}, {hi}]`)
				return value
			end,
		}
	else
		assert(isFinite(source), "FakeRng.new: the seed must be a finite number")
		local counter = math.floor(source :: number) % TWO_32
		local function nextUnit(): number
			counter = (counter + GOLDEN) % TWO_32
			return fmix32(counter) / TWO_32 -- [0, 1)
		end
		state = {
			calls = 0,
			NextInteger = function(self: any, min: number, max: number): number
				assert(max >= min, `FakeRng: NextInteger({min}, {max}) has an empty range`)
				self.calls += 1
				return min + math.floor(nextUnit() * (max - min + 1))
			end,
			NextNumber = function(self: any, min: number?, max: number?): number
				self.calls += 1
				local lo, hi = min or 0, max or 1
				return lo + nextUnit() * (hi - lo)
			end,
		}
	end
	return (state :: any) :: Random
end

-- How many values a FakeRng has handed out (both methods).
function FakeRng.calls(rng: Random): number
	return (rng :: any).calls
end

return FakeRng
