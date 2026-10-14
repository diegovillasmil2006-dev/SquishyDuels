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
--   nextGoal(state, cfg?)                     -> Goal?: the one next-goal line of the Grip card (§17.7; Batch 1: a
--                                                capsule buy first when the state has capsules)
-- Since Phase 3 own squeezes pay CapsuleMath.squeezeGrip (and the squeeze value in Coins). Build plan Phase 6 removed
-- slow training (afkGrip, afkMinutes), the trainers (trainer, squeezeGrip, upgradeReady, upgradeDecision and the
-- next goal's upgrade line with its Dragon rule, topShopSquishyId) and the giant pads (pad, bestTier, canUseTier, the
-- pads of unlocks and the next goal's pad line).
--
-- Readings:
--   * HUD bar "{have} / {need} Grip" (§17.7): Progress.have = the total Grip and Progress.need = the total of the next
--     level (both shown with Format.coins); the bar fill is into / span. At the max level the card shows grip.hudMax.
--   * restedMinutes counts whole points only (a squeeze needs a whole point): a pool holding
--     0.5 shows 0 min, not "about 1 min".
--   * nextGoal ("the next unlock line", §17.5; Batch 1 #7a): with the player's capsules and Coins in the state, the
--     capsule buy first (capsuleGoal: an affordable upgrade is READY, else the cheaper of the cheapest upgrade and
--     the next slot's unlock, with progress; the unlock only while a spare squishy waits for the new capsule, so the
--     line never names a capsule that would open empty); then the next rank above the current level; with nothing
--     left to unlock and the level at maxLevel the line is grip.goalMax. The capsule step reads the live Config
--     through CapsuleMath (cfg is for Grip levels and ranks only).

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local CapsuleMath = require(script.Parent.CapsuleMath)
local Config = require(script.Parent.Config)

-- Types

export type Rank = { level: number, key: string }

-- Anything with Config's Grip, Squeeze and Economy sections.
export type GripConfig = { Grip: any, Squeeze: any, Economy: any }

-- The fields the next-goal rule reads: the Grip total; Batch 1 #7a: the capsules ({slots, list}), Coins and owned
-- squishies (id -> entry) when the caller has them (the client's state fields; without capsules the goal is a rank or
-- max, as before).
export type GoalState = { total: number, capsules: any?, coins: number?, owned: any? }

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

export type GoalKind = "capsuleReady" | "unlockReady" | "capsule" | "unlock" | "rank" | "max"
-- One next-goal line (format: GripController.goalArgs).
export type Goal = {
	kind: GoalKind,
	textKey: string, -- grip.goalCapsuleReady | goalUnlockReady | goalCapsule | goalUnlock | goalRank | goalMax
	nameKey: string?, -- grip.rank.<key>
	index: number?, -- the rank index
	level: number?, -- the rank's unlock level, or an upgrade goal's next capsule level
	slot: number?, -- a capsule goal's capsule (1..4)
	have: number?, -- a capsule goal: the Coins now, capped at need
	need: number?, -- a capsule goal: its price
}

-- Constants

local MINUTE = 60
local ROUNDING_SLACK = 1e-9 -- keeps ceil() from rounding an exact quotient up because of float noise
-- Batch 1 #7a: the Strings key of each capsule goal kind.
local CAPSULE_GOAL_KEYS: { [string]: string } = {
	capsuleReady = "grip.goalCapsuleReady",
	unlockReady = "grip.goalUnlockReady",
	capsule = "grip.goalCapsule",
	unlock = "grip.goalUnlock",
}

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

-- Batch 1 #7c's spare rule (CapsuleService.bestSpare): true when an owned squishy with power sits in no capsule.
local function hasSpare(capsules: any, owned: unknown): boolean
	if type(owned) ~= "table" then
		return false
	end
	local placed: { [string]: boolean } = {}
	for _, capsule in capsules.list do
		if type(capsule) == "table" and type(capsule.squishyId) == "string" then
			placed[capsule.squishyId] = true
		end
	end
	for id in owned :: any do
		if not placed[id] and CapsuleMath.squishyPower(id) > 0 then
			return true
		end
	end
	return false
end

-- Batch 1 #7a: the capsule buy the next-goal line names, or nil when none can be bought. The cheapest upgrade
-- (CapsuleMath.upgradeCost) when the Coins cover it ("capsuleReady") or it costs no more than the next slot's unlock
-- ("capsule", with progress); else that unlock ("unlockReady" / "unlock"), counted only while a spare squishy (owned,
-- in no capsule) would fill the new capsule: an empty one earns nothing. Ties go to the lower slot.
local function capsuleGoal(capsules: any, coins: unknown, gripLevel: number, owned: unknown): Goal?
	local have = whole(coins)
	local spare = hasSpare(capsules, owned)
	local upSlot: number? = nil
	local upCost = math.huge
	local unlockSlot: number? = nil
	local unlockCost = math.huge
	for slot = 1, #Config.Grip.Capsule.slotPrices do
		local cost = CapsuleMath.upgradeCost(capsules, slot, gripLevel)
		if cost ~= nil and cost < upCost then
			upSlot, upCost = slot, cost
		end
		local price = CapsuleMath.slotPrice(slot) :: number
		if spare and CapsuleMath.unlockDecision(capsules, slot, price).kind == "buy" then
			unlockSlot, unlockCost = slot, price
		end
	end
	local upgrade = upSlot ~= nil and (have >= upCost or upCost <= unlockCost)
	local slot = if upgrade then upSlot else unlockSlot
	if slot == nil then
		return nil
	end
	local need = if upgrade then upCost else unlockCost
	local ready = have >= need
	local kind: GoalKind = if upgrade
		then (if ready then "capsuleReady" else "capsule")
		else (if ready then "unlockReady" else "unlock")
	return {
		kind = kind,
		textKey = CAPSULE_GOAL_KEYS[kind],
		slot = slot,
		level = if upgrade then capsules.list[slot].level + 1 else nil,
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

-- The one next-goal line (§17.7 order; Batch 1 #7a): 0 a capsule buy (when the state has capsules); 1 the next rank;
-- 2 max level. nil only when nothing applies.
function GripMath.nextGoal(state: GoalState, cfg: GripConfig?): Goal?
	local c = sections(cfg)
	local level = GripMath.levelFor(state.total, c)

	-- 0. A capsule buy (Batch 1: the Next line teaches capsules).
	local capsules = state.capsules
	if type(capsules) == "table" and type(capsules.list) == "table" then
		local goal = capsuleGoal(capsules, state.coins, level, state.owned)
		if goal ~= nil then
			return goal
		end
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
