--!strict
-- DailyLogic (server only, pure): daily reward days, claim eligibility, streak and rewards (DESIGN §6.9). No instances,
-- no yields; time comes in as `now` (os.time(), unix seconds) or a day index. The client never decides any of this
-- (its UI/DailyFormat only repeats the display math).
--
-- API:
--   DailyLogic.dayIndex(now)                  -> math.floor(now / 86400): the UTC day (a new day at 00:00 UTC)
--   DailyLogic.canClaim(daily, today)         -> (true) or (false, "daily.alreadyClaimed") when lastClaimDay >= today.
--                                                Profile ready and no save pending stay DailyRewardService's checks.
--   DailyLogic.nextStreak(daily, today, cfg?) -> streakDay: the streak day this claim pays:
--                                                streakDay % #coinsByDay + 1 after any earlier claim (after day 7 back
--                                                to Day 1). A missed day only pauses the streak (review quick win
--                                                2026-10-14): the claim after a gap pays the next day, never back to
--                                                Day 1.
--   DailyLogic.reward(streakDay, cfg?)        -> {coins, freeBox}: coinsByDay[streakDay]; freeBox on freeBoxDay (7)
--   DailyLogic.secondsUntilNext(now)          -> seconds until the next 00:00 UTC, in (0, 86400]
-- `cfg` is a table shaped like Config.Economy.Daily (a test's copy); nil = the live Config.
--
-- Readings:
--   * A first-ever claim (lastClaimDay < 0) is Day 1.
--   * nextStreak for a day that is not claimable (lastClaimDay >= today) returns the stored day (clamped).
--   * A streak day outside 1..#coinsByDay (only from a hand edit) is clamped into it; a non-number lastClaimDay is
--     treated as "already claimed today" by canClaim (fail closed; ProfileSchema.sanitize fixes it on load).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local TimeUtil = require(Shared.Util.TimeUtil)
local Types = require(Shared.Types)

-- Types

export type DailyState = Types.DailyState
export type DailyConfig = { coinsByDay: { number }, freeBoxDay: number }
export type Reward = { coins: number, freeBox: boolean }

-- Constants

local ALREADY_CLAIMED = "daily.alreadyClaimed"

-- Module table

local DailyLogic = {}

-- Private

local function daily(cfg: DailyConfig?): DailyConfig
	return if cfg ~= nil then cfg else Config.Economy.Daily
end

local function isFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- A whole number clamped to [lo, hi]; anything that is not a finite number counts as lo.
local function clampWhole(n: unknown, lo: number, hi: number): number
	if not isFinite(n) then
		return lo
	end
	return math.clamp(math.floor(n :: number), lo, hi)
end

-- Public

function DailyLogic.dayIndex(now: number): number
	return TimeUtil.utcDay(now)
end

function DailyLogic.canClaim(state: DailyState, today: number): (boolean, string?)
	local last = state.lastClaimDay
	if not isFinite(last) or last >= today then
		return false, ALREADY_CLAIMED
	end
	return true, nil
end

function DailyLogic.nextStreak(state: DailyState, today: number, cfg: DailyConfig?): number
	local c = daily(cfg)
	local cycle = math.max(1, #c.coinsByDay)
	local last = state.lastClaimDay
	if not isFinite(last) or last >= today then
		return clampWhole(state.streakDay, 1, cycle)
	end
	if last < 0 then
		return 1 -- a first-ever claim
	end
	return clampWhole(state.streakDay, 0, cycle) % cycle + 1 -- also after a missed day: the streak only paused
end

function DailyLogic.reward(streakDay: number, cfg: DailyConfig?): Reward
	local c = daily(cfg)
	local day = clampWhole(streakDay, 1, math.max(1, #c.coinsByDay))
	return { coins = c.coinsByDay[day] or 0, freeBox = day == c.freeBoxDay }
end

function DailyLogic.secondsUntilNext(now: number): number
	return TimeUtil.secondsUntilNextUtcDay(now)
end

return table.freeze(DailyLogic)
