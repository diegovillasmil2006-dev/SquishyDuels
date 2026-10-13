--!strict
-- GripMath: pure Grip arithmetic (DESIGN §17.3-§17.5, §17.7). Shared: server GripService and SqueezeService (levels
-- and clamps, the pad level check), client GripController, SqueezeController, NameplateController
-- and WorldBinder (levels, ranks, pad labels, the next-goal line). No instances, no yields, no side effects.
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
--   pad(tier, cfg?)                           -> the Config.Grip.Pads entry, or nil
--   bestTier(level, cfg?)                     -> the highest pad tier the level opens (1..#Pads)
--   canUseTier(level, tier, cfg?)             -> boolean: tier is a pad and its level <= level (fail closed)
--   restedMinutes(restedValue, cfg?)          -> "Double Grip: about {minutes} min" (§17.3.4)
--   clampTotal(total, cfg?)                   -> the total as stored: floored, clamped to [0, maxGrip] (§17.9 #6)
--   addGrip(total, gain, cfg?)                -> clampTotal(total + gain)
--   clampEvent(gain, cfg?)                    -> (gain clamped to [0, maxGripPerEvent], wasClamped) (§17.3.1)
--   unlocks(oldLevel, newLevel, cfg?)         -> Unlocks: pads and the rank reached on a level change (toasts)
--   nextGoal(state, cfg?)                     -> Goal?: the one next-goal line of the Grip card (§17.7)
-- Since Phase 3 own squeezes pay CapsuleMath.squeezeGrip (and the squeeze value in Coins). Build plan Phase 6 removed
-- slow training (afkGrip, afkMinutes) and the trainers (trainer, squeezeGrip, upgradeReady, upgradeDecision and the
-- next goal's upgrade line with its Dragon rule, topShopSquishyId).
--
-- Readings:
--   * HUD bar "{have} / {need} Grip" (§17.7): Progress.have = the total Grip and Progress.need = the total of the next
--     level (both shown with Format.coins); the bar fill is into / span. At the max level the card shows grip.hudMax.
--   * restedMinutes counts whole points only (a squeeze needs a whole point): a pool holding
--     0.5 shows 0 min, not "about 1 min".
--   * nextGoal ("the next unlock line", §17.5): the unlock with the lowest level above the current one, a pad or a
--     rank; on a tie the pad comes first. With nothing left to unlock and the level at maxLevel the line is
--     grip.goalMax.

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Config = require(script.Parent.Config)

-- Types

export type Pad = { key: string, level: number, coinBonus: number, gripPercent: number }
export type Rank = { level: number, key: string }

-- Anything with Config's Grip, Squeeze and Economy sections.
export type GripConfig = { Grip: any, Squeeze: any, Economy: any }

-- The GripState field the next-goal rule reads (Types.GripState has it and more).
export type GoalState = { total: number }

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
	pads: { number }, -- tiers whose level lies in (oldLevel, newLevel], in tier order
	rank: Rank?, -- the highest rank whose level lies in (oldLevel, newLevel]
	rankIndex: number?,
}

export type GoalKind = "pad" | "rank" | "max"
-- One next-goal line. Format: Strings.format(Strings.resolve(textKey), { pad = <name>, rank = <name>, level = level })
-- where <name> = Strings.resolve(nameKey).
export type Goal = {
	kind: GoalKind,
	textKey: string, -- grip.goalPad | grip.goalRank | grip.goalMax
	nameKey: string?, -- grip.pad.<key> | grip.rank.<key>
	index: number?, -- the pad tier or rank index
	level: number?, -- the unlock level
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

-- True when n is an integer index into list.
local function isIndex(n: unknown, list: { any }): boolean
	return type(n) == "number" and n == n and math.floor(n) == n and n >= 1 and n <= #list
end

local function maxLevelOf(c: GripConfig): number
	return math.min(c.Grip.maxLevel, #c.Grip.LevelTotals)
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

-- Public: pads

function GripMath.pad(tier: number, cfg: GripConfig?): Pad?
	local pads = sections(cfg).Grip.Pads
	return if isIndex(tier, pads) then pads[tier] else nil
end

function GripMath.bestTier(level: number, cfg: GripConfig?): number
	local lv = whole(level)
	local best = 1
	for tier, pad in sections(cfg).Grip.Pads do
		if pad.level <= lv and tier > best then
			best = tier
		end
	end
	return best
end

-- §17.3.1 step 6a (server, before the bucket) and the client's locked-pad text. An unknown tier is never usable.
function GripMath.canUseTier(level: number, tier: number, cfg: GripConfig?): boolean
	local pad = GripMath.pad(tier, cfg)
	return pad ~= nil and pad.level <= whole(level)
end

-- Public: amounts

-- ceil(points × Grip.Hold.repeatSeconds / 60): minutes of holding Squeeze that Double Grip still covers (9 when full;
-- one point per squeeze, holding repeats every repeatSeconds).
-- Reading (every click pays, 2026-10-06): this used Squeeze.cycleSeconds while that was the 1.5 s squeeze timer (30
-- minutes when full, the DESIGN §17.3.4 / §17.4 pacing estimate); the cycle is now the 1/12 s anti-autoclicker cap,
-- so the holding rhythm is Hold.repeatSeconds. Clicking faster than holding uses Double Grip up sooner than this says.
-- Grip amounts are unchanged.
function GripMath.restedMinutes(restedValue: number, cfg: GripConfig?): number
	local c = sections(cfg)
	return math.max(0, math.ceil(whole(restedValue) * c.Grip.Hold.repeatSeconds / MINUTE - ROUNDING_SLACK))
end

-- Public: level changes and goals

function GripMath.unlocks(oldLevel: number, newLevel: number, cfg: GripConfig?): Unlocks
	local c = sections(cfg)
	local from, to = whole(oldLevel), whole(newLevel)
	local result: Unlocks = { pads = {} }
	for tier, pad in c.Grip.Pads do
		if pad.level > from and pad.level <= to then
			table.insert(result.pads, tier)
		end
	end
	for index, rank in c.Grip.Ranks do
		if rank.level > from and rank.level <= to then
			result.rank = rank
			result.rankIndex = index
		end
	end
	return result
end

-- The one next-goal line (§17.7 order): 1 the next unlock (pad or rank); 2 max level. nil only when nothing applies.
function GripMath.nextGoal(state: GoalState, cfg: GripConfig?): Goal?
	local c = sections(cfg)
	local grip = c.Grip
	local level = GripMath.levelFor(state.total, c)

	-- 1. The next unlock: the lowest level above the current one (pad, then rank on a tie).
	-- Candidates in tie order; the first with the lowest level wins.
	local candidates: { Goal } = {}
	for tier, pad in grip.Pads do
		if pad.level > level then
			table.insert(candidates, {
				kind = "pad",
				textKey = "grip.goalPad",
				nameKey = "grip.pad." .. pad.key,
				index = tier,
				level = pad.level,
			})
			break
		end
	end
	local rank, rankIndex = GripMath.nextRank(level, c)
	if rank ~= nil then
		table.insert(candidates, {
			kind = "rank",
			textKey = "grip.goalRank",
			nameKey = "grip.rank." .. rank.key,
			index = rankIndex,
			level = rank.level,
		})
	end
	local best: Goal? = nil
	for _, goal in candidates do
		if best == nil or (goal.level :: number) < (best.level :: number) then
			best = goal
		end
	end
	if best ~= nil then
		return best
	end

	-- 2. Max level.
	if level >= maxLevelOf(c) then
		return { kind = "max", textKey = "grip.goalMax" }
	end
	return nil
end

return table.freeze(GripMath)
