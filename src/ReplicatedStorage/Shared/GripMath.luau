--!strict
-- GripMath: pure Grip arithmetic (DESIGN §17.3-§17.5, §17.7). Shared: server GripService (levels and clamps), client
-- GripController, NameplateController, CapsuleController and UI/HudFormat (levels, ranks, the next-goal line).
-- No instances, no yields, no side effects.
-- Grip is a lobby-only stat: never a currency, never read by duel or matchmaking code (§17.2 rule 1).
--
-- Integers only: every Grip, level, tier, Coin and minute value returned is a whole number; inputs are floored, and a
-- non-finite or negative input counts as 0. Timers (Double Grip, the squeeze Coins limit) use
-- SqueezeLimit; this module only turns their values into minutes.
-- `cfg` (optional, always the last argument) is a table with Config's Grip, Squeeze and Economy sections (a test's
-- copy); nil = the live Config.
--
-- API:
--   levelFor(total, cfg?)                     -> level (1..maxLevel): the highest level whose LevelTotals <= total
--   progress(total, cfg?)                     -> Progress (level, the level's start and the next level's total)
--   rankFor(level, cfg?)                      -> (Rank, index): the rank of a level (Lv 1 "soft" .. Lv 50 "master")
--   nextRank(level, cfg?)                     -> (Rank?, index?): the first rank above that level
--   restedMinutes(restedValue, cfg?)          -> "Double Grip: about {minutes} min" (§17.3.4)
--   clampTotal(total, cfg?)                   -> the total as stored: floored, clamped to [0, maxGrip] (§17.9 #6)
--   addGrip(total, gain, cfg?)                -> clampTotal(total + gain)
--   clampEvent(gain, cfg?)                    -> (gain clamped to [0, maxGripPerEvent], wasClamped) (§17.3.1)
--   unlocks(oldLevel, newLevel, cfg?)         -> Unlocks: the rank reached on a level change (toasts)
--   nextGoal(state, cfg?)                     -> Goal?: the one next-goal line of the Grip card (§17.7; pens3 phase 1:
--                                                the next pen spot first when the state has a pen)
-- Since pens3 phase 1 own squeezes pay PenMath.squeezeGrip (and the squeeze value in Coins). Build plan Phase 6 removed
-- slow training (afkGrip, afkMinutes), the trainers (trainer, squeezeGrip, upgradeReady, upgradeDecision and the
-- next goal's upgrade line with its Dragon rule, topShopSquishyId) and the giant pads (pad, bestTier, canUseTier, the
-- pads of unlocks and the next goal's pad line).
--
-- Readings:
--   * HUD bar "{have} / {need} Grip" (§17.7): Progress.have = the total Grip and Progress.need = the total of the next
--     level (both shown with Format.coins); the bar fill is into / span. At the max level the card shows grip.hudMax.
--   * restedMinutes counts whole points only (a squeeze needs a whole point): a pool holding
--     0.5 shows 0 min, not "about 1 min".
--   * nextGoal ("the next unlock line", §17.5; pens3 phase 1, it replaced Batch 1 #7a's capsule buy): with the
--     player's pen and Coins in the state, the next pen spot first while the pen has fewer than maxSpots (penGoal:
--     its price, READY once the Coins cover it, else with progress); then the next rank above the current level; with
--     nothing left to unlock and the level at maxLevel the line is grip.goalMax. The pen step reads the live Config
--     through PenMath (cfg is for Grip levels and ranks only).

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Config = require(script.Parent.Config)
local PenMath = require(script.Parent.PenMath)

-- Types

export type Rank = { level: number, key: string }

-- Anything with Config's Grip, Squeeze and Economy sections.
export type GripConfig = { Grip: any, Squeeze: any, Economy: any }

-- The fields the next-goal rule reads: the Grip total; pens3 phase 1: the pen (Types.PenState) and the Coins when the
-- caller has them (the client's state fields; without a pen the goal is a rank or max, as before).
export type GoalState = { total: number, pen: any?, coins: number? }

export type Progress = {
	level: number,
	total: number, -- the clamped total
	levelStart: number, -- LevelTotals[level]
	nextTotal: number, -- LevelTotals[level + 1]; levelStart at the max level
	into: number, -- total - levelStart
	span: number, -- nextTotal - levelStart; 0 at the max level
	have: number, -- HUD "{have}": the total Grip
	need: number, -- HUD "{need}": the next level's total
	isMax: boolean,
}

export type Unlocks = {
	rank: Rank?, -- the highest rank whose level lies in (oldLevel, newLevel]
	rankIndex: number?,
}

export type GoalKind = "penReady" | "pen" | "rank" | "max"
-- One next-goal line (format: GripController.goalArgs).
export type Goal = {
	kind: GoalKind,
	textKey: string, -- grip.goalPenReady | goalPen | goalRank | goalMax
	nameKey: string?, -- grip.rank.<key>
	index: number?, -- the rank index
	level: number?, -- the rank's unlock level
	have: number?, -- a pen goal: the Coins now, capped at need
	need: number?, -- a pen goal: the next spot's price
}

-- Constants

local MINUTE = 60
local ROUNDING_SLACK = 1e-9 -- keeps ceil() from rounding an exact quotient up because of float noise

-- Module table

local GripMath = {}

-- Private

local function sections(cfg: GripConfig?): GripConfig
	return if cfg ~= nil then cfg else Config :: any
end

-- floor(n) for a finite n >= 0, else 0.
local function whole(n: unknown): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge or n < 0 then
		return 0
	end
	return math.floor(n)
end

local function maxLevelOf(c: GripConfig): number
	return math.min(c.Grip.maxLevel, #c.Grip.LevelTotals)
end

-- Pens3 phase 1: the next pen spot the next-goal line names (its price, READY once the Coins cover it), or nil at
-- maxSpots or for anything that is not a pen.
local function penGoal(pen: any, coins: unknown): Goal?
	local spots = if type(pen) == "table" then pen.spots else nil
	local need = if type(spots) == "number" then PenMath.spotPrice(spots + 1) else nil
	if need == nil then
		return nil
	end
	local have = whole(coins)
	local ready = have >= need
	return {
		kind = if ready then "penReady" else "pen",
		textKey = if ready then "grip.goalPenReady" else "grip.goalPen",
		have = math.min(have, need),
		need = need,
	}
end

-- Public: levels and ranks

function GripMath.clampTotal(total: number, cfg: GripConfig?): number
	return math.min(whole(total), whole(sections(cfg).Grip.maxGrip))
end

function GripMath.addGrip(total: number, gain: number, cfg: GripConfig?): number
	return GripMath.clampTotal(whole(total) + whole(gain), cfg)
end

function GripMath.clampEvent(gain: number, cfg: GripConfig?): (number, boolean)
	local cap = whole(sections(cfg).Grip.maxGripPerEvent)
	local n = whole(gain)
	if n > cap then
		return cap, true
	end
	return n, false
end

function GripMath.levelFor(total: number, cfg: GripConfig?): number
	local c = sections(cfg)
	local totals = c.Grip.LevelTotals
	local t = GripMath.clampTotal(total, c)
	local level = 1
	for index = 2, maxLevelOf(c) do
		if t >= totals[index] then
			level = index
		else
			break
		end
	end
	return level
end

function GripMath.progress(total: number, cfg: GripConfig?): Progress
	local c = sections(cfg)
	local totals = c.Grip.LevelTotals
	local t = GripMath.clampTotal(total, c)
	local level = GripMath.levelFor(t, c)
	local levelStart = totals[level]
	local isMax = level >= maxLevelOf(c)
	local nextTotal = if isMax then levelStart else totals[level + 1]
	return {
		level = level,
		total = t,
		levelStart = levelStart,
		nextTotal = nextTotal,
		into = t - levelStart,
		span = nextTotal - levelStart,
		have = t,
		need = nextTotal,
		isMax = isMax,
	}
end

function GripMath.rankFor(level: number, cfg: GripConfig?): (Rank, number)
	local ranks = sections(cfg).Grip.Ranks
	local lv = whole(level)
	local index = 1
	for i, rank in ranks do
		if lv >= rank.level then
			index = i
		end
	end
	return ranks[index], index
end

function GripMath.nextRank(level: number, cfg: GripConfig?): (Rank?, number?)
	local lv = whole(level)
	for i, rank in sections(cfg).Grip.Ranks do
		if rank.level > lv then
			return rank, i
		end
	end
	return nil, nil
end

-- Public: amounts

-- ceil(points × Grip.Hold.repeatSeconds / 60): minutes of holding Squeeze that Double Grip still covers (9 when full;
-- one point per squeeze, holding repeats every repeatSeconds).
-- Reading (2026-10-06): this used Squeeze.cycleSeconds while that was the 1.5 s squeeze timer (30
-- minutes when full, the DESIGN §17.3.4 / §17.4 pacing estimate); the holding rhythm is Hold.repeatSeconds, which is
-- also the paid-squeeze cap since Batch 1 #2, so no way of squeezing runs Double Grip out sooner than this says.
-- Grip amounts are unchanged.
function GripMath.restedMinutes(restedValue: number, cfg: GripConfig?): number
	local c = sections(cfg)
	return math.max(0, math.ceil(whole(restedValue) * c.Grip.Hold.repeatSeconds / MINUTE - ROUNDING_SLACK))
end

-- Public: level changes and goals

function GripMath.unlocks(oldLevel: number, newLevel: number, cfg: GripConfig?): Unlocks
	local c = sections(cfg)
	local from, to = whole(oldLevel), whole(newLevel)
	local result: Unlocks = {}
	for index, rank in c.Grip.Ranks do
		if rank.level > from and rank.level <= to then
			result.rank = rank
			result.rankIndex = index
		end
	end
	return result
end

-- The one next-goal line (§17.7 order; pens3 phase 1): 0 the next pen spot (when the state has a pen); 1 the next
-- rank; 2 max level. nil only when nothing applies.
function GripMath.nextGoal(state: GoalState, cfg: GripConfig?): Goal?
	local c = sections(cfg)
	local level = GripMath.levelFor(state.total, c)

	-- 0. The next pen spot (pens3 phase 1: the Next line teaches the pen).
	local goal = penGoal(state.pen, state.coins)
	if goal ~= nil then
		return goal
	end

	-- 1. The next rank above the current level.
	local rank, rankIndex = GripMath.nextRank(level, c)
	if rank ~= nil then
		return {
			kind = "rank",
			textKey = "grip.goalRank",
			nameKey = "grip.rank." .. rank.key,
			index = rankIndex,
			level = rank.level,
		}
	end

	-- 2. Max level.
	if level >= maxLevelOf(c) then
		return { kind = "max", textKey = "grip.goalMax" }
	end
	return nil
end

return table.freeze(GripMath)
