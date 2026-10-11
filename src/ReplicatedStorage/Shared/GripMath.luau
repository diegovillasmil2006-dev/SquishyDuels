--!strict
-- GripMath: pure Grip arithmetic (DESIGN §17.3-§17.5, §17.7). Shared: server GripService and SqueezeService (Grip per
-- squeeze, the pad level check, slow-training ticks), client GripController, SqueezeController, NameplateController
-- and WorldBinder (levels, ranks, pad labels, the next-goal line). No instances, no yields, no side effects.
-- Grip is a lobby-only stat: never a currency, never read by duel or matchmaking code (§17.2 rule 1).
--
-- Integers only: every Grip, level, tier, Coin and minute value returned is a whole number; inputs are floored, and a
-- non-finite or negative input counts as 0. Timers (Double Grip, the slow-training bank, the squeeze Coins limit) use
-- SqueezeLimit; this module only turns their values into minutes.
-- `cfg` (optional, always the last argument) is a table with Config's Grip, Squeeze and Economy sections (a test's
-- copy); nil = the live Config.
--
-- API:
--   levelFor(total, cfg?)                     -> level (1..maxLevel): the highest level whose LevelTotals <= total
--   progress(total, cfg?)                     -> Progress (level, the level's start and the next level's total)
--   rankFor(level, cfg?)                      -> (Rank, index): the rank of a level (Lv 1 "soft" .. Lv 50 "master")
--   nextRank(level, cfg?)                     -> (Rank?, index?): the first rank above that level
--   pad(tier, cfg?) / trainer(index, cfg?)    -> the Config.Grip.Pads / Trainer entry, or nil
--   bestTier(level, cfg?)                     -> the highest pad tier the level opens (1..#Pads)
--   canUseTier(level, tier, cfg?)             -> boolean: tier is a pad and its level <= level (fail closed)
--   squeezeGrip(trainer, tier, doubled?, cfg?) -> Grip of one accepted squeeze (§17.3.1)
--   squeezeCoins(baseCoins, tier, paid, cfg?) -> Coins of one accepted squeeze (§17.3.1)
--   afkGrip(trainer, tier, cfg?)              -> Grip of one paid slow-training tick (§17.3.6)
--   afkMinutes(bankValue, cfg?)               -> "Slow training at full speed: about {minutes} min left" (§17.7)
--   restedMinutes(restedValue, cfg?)          -> "Double Grip: about {minutes} min" (§17.3.4)
--   clampTotal(total, cfg?)                   -> the total as stored: floored, clamped to [0, maxGrip] (§17.9 #6)
--   addGrip(total, gain, cfg?)                -> clampTotal(total + gain)
--   clampEvent(gain, cfg?)                    -> (gain clamped to [0, maxGripPerEvent], wasClamped) (§17.3.1)
--   unlocks(oldLevel, newLevel, cfg?)         -> Unlocks: pads and the rank reached on a level change (toasts)
--   upgradeReady(state, coins, trainerAvailable, cfg?) -> boolean: the "Upgrade available" badge (§17.5)
--   nextGoal(state, owned, coins, trainerAvailable, cfg?) -> Goal?: the one next-goal line of the Grip card (§17.7)
--   topShopSquishyId()                        -> the Catalog squishy with the highest shopPrice (Dragon today)
--   upgradeDecision(state, targetLevel, expectedPrice, cfg?) -> UpgradeDecision: the pure TrainerUpgrade checks of
--     §17.5 (Part 7), steps 2 and 4-7 in DESIGN order (the first that applies wins):
--       2 targetLevel an integer in 2..#Trainer, expectedPrice an integer with 0 <= price < Net.maxAbsNumber, else
--         reject "net.invalid";
--       4 state.trainer >= targetLevel -> "replay" (ok, charged = false: the stored trainer is the idempotency key);
--       5 targetLevel ~= trainer + 1 -> reject "trainer.notNext";
--       6 state.level < Trainer[targetLevel].level -> reject "trainer.locked";
--       7 expectedPrice ~= cost -> reject "trainer.priceChanged" (the client's price is only compared);
--       else "buy" (charged = true: GripService spends `cost` with reason "trainer").
--     Steps 3 (profile ready) and 8-10 (paused, in a duel, Coins, the "now" save) stay in GripService.
--
-- Readings:
--   * HUD bar "{have} / {need} Grip" (§17.7): Progress.have = the total Grip and Progress.need = the total of the next
--     level (both shown with Format.coins); the bar fill is into / span. At the max level the card shows grip.hudMax.
--   * restedMinutes and afkMinutes count whole points only (a squeeze or a tick needs a whole point): a pool holding
--     0.5 shows 0 min, not "about 1 min".
--   * nextGoal, line 2 ("the next unlock line: pad, trainer gate or rank", §17.5): the unlock with the lowest level
--     above the current one; on a tie the pad comes first, then the trainer gate, then the rank. Trainer lines (the
--     upgrade line and the trainer gate) only appear while `trainerAvailable` is true (the TrainerUpgrade remote,
--     Part 7). With nothing left to unlock and the level at maxLevel the line is grip.goalMax.
--   * upgradeReady = the next trainer exists, the level reaches its gate and the Coins cover its cost (shown as the
--     badge whatever the Dragon rule says; the goal line also needs the Dragon rule).

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Catalog = require(script.Parent.Catalog)
local Config = require(script.Parent.Config)

-- Types

export type Pad = { key: string, level: number, coinBonus: number, gripPercent: number }
export type Trainer = { key: string, gripPerSqueeze: number, cost: number, level: number }
export type Rank = { level: number, key: string }

-- Anything with Config's Grip, Squeeze and Economy sections (and Net for upgradeDecision; the live Config.Net when
-- absent).
export type GripConfig = { Grip: any, Squeeze: any, Economy: any, Net: any? }

-- The TrainerUpgrade inputs the pure checks read: the best trainer owned (grip.trainer) and the Grip Level.
export type UpgradeState = { trainer: number, level: number }
export type UpgradeKind = "replay" | "buy" | "reject"
-- `cost` = Trainer[targetLevel].cost (0 when targetLevel is invalid); `charged` is true only for "buy".
export type UpgradeDecision = { kind: UpgradeKind, reason: string?, cost: number, charged: boolean }

-- The two GripState fields the next-goal rule reads (Types.GripState has these and more).
export type GoalState = { total: number, trainer: number }

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

export type GoalKind = "upgrade" | "pad" | "trainer" | "rank" | "max"
-- One next-goal line. Format: Strings.format(Strings.resolve(textKey), { trainer = <name>, pad = <name>, rank = <name>,
-- level = level, coins = Format.coins(coins) }) where <name> = Strings.resolve(nameKey).
export type Goal = {
	kind: GoalKind,
	textKey: string, -- grip.goalUpgrade | grip.goalPad | grip.goalTrainer | grip.goalRank | grip.goalMax
	nameKey: string?, -- grip.trainer.<key> | grip.pad.<key> | grip.rank.<key>
	index: number?, -- the trainer index, pad tier or rank index
	level: number?, -- the unlock level (pad, trainer gate, rank) or the trainer's level (upgrade)
	coins: number?, -- the upgrade price (upgrade only)
}

-- Constants

local MINUTE = 60
local PERCENT = 100
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

-- The index of the next trainer to buy (the owned trainer counts as at least 1, the free Foam Ball).
local function nextTrainerIndex(state: GoalState): number
	return math.max(1, whole(state.trainer)) + 1
end

-- An integer (finite, no fraction); unlike whole() it does not turn bad input into 0.
local function isWholeNumber(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and math.floor(n) == n
end

local function reject(reason: string, cost: number): UpgradeDecision
	return { kind = "reject", reason = reason, cost = cost, charged = false }
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

-- Public: pads and trainers

function GripMath.pad(tier: number, cfg: GripConfig?): Pad?
	local pads = sections(cfg).Grip.Pads
	return if isIndex(tier, pads) then pads[tier] else nil
end

function GripMath.trainer(index: number, cfg: GripConfig?): Trainer?
	local trainers = sections(cfg).Grip.Trainer
	return if isIndex(index, trainers) then trainers[index] else nil
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

-- floor(gripPerSqueeze × gripPercent / 100), × Rested.mult when doubled (and Double Grip is enabled). 0 for an
-- unknown trainer or tier.
function GripMath.squeezeGrip(trainer: number, tier: number, doubled: boolean?, cfg: GripConfig?): number
	local c = sections(cfg)
	local t = GripMath.trainer(trainer, c)
	local pad = GripMath.pad(tier, c)
	if t == nil or pad == nil then
		return 0
	end
	local base = math.floor(t.gripPerSqueeze * pad.gripPercent / PERCENT)
	local rested = c.Grip.Rested
	if doubled == true and rested.enabled then
		return math.floor(base * rested.mult)
	end
	return base
end

-- paid: baseCoins (Catalog.getSqueezeCoins of the server's equipped squishy) + the pad's coinBonus; not paid:
-- Economy.SqueezeLimit.emptyCoins. An unknown tier adds no bonus.
function GripMath.squeezeCoins(baseCoins: number, tier: number, paid: boolean, cfg: GripConfig?): number
	local c = sections(cfg)
	if not paid then
		return whole(c.Economy.SqueezeLimit.emptyCoins)
	end
	local pad = GripMath.pad(tier, c)
	return whole(baseCoins) + (if pad then pad.coinBonus else 0)
end

-- floor(squeezeGrip(trainer, tier) × percentPerTick / 100): never doubled.
function GripMath.afkGrip(trainer: number, tier: number, cfg: GripConfig?): number
	local c = sections(cfg)
	return math.floor(GripMath.squeezeGrip(trainer, tier, false, c) * c.Grip.Afk.percentPerTick / PERCENT)
end

-- ceil(points / (60 / tickSeconds - perHour / 60)): minutes of nonstop slow training the bank still pays every tick
-- (40 for a full bank). math.huge if the bank would never drain (validator G9 forbids that).
function GripMath.afkMinutes(bankValue: number, cfg: GripConfig?): number
	local afk = sections(cfg).Grip.Afk
	local drainPerMinute = MINUTE / afk.tickSeconds - afk.perHour / MINUTE
	if drainPerMinute <= 0 then
		return math.huge
	end
	return math.max(0, math.ceil(whole(bankValue) / drainPerMinute - ROUNDING_SLACK))
end

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

-- The Catalog squishy with the highest shopPrice (first in catalog order on a tie), or nil if nothing is sold.
function GripMath.topShopSquishyId(): string?
	local bestId: string? = nil
	local bestPrice = -math.huge
	for _, def in Catalog.list() do
		local price = def.shopPrice
		if type(price) == "number" and price > bestPrice then
			bestId = def.id
			bestPrice = price
		end
	end
	return bestId
end

-- The "Upgrade available" badge: the next trainer exists, its level gate is reached and the Coins cover it.
function GripMath.upgradeReady(state: GoalState, coins: number, trainerAvailable: boolean, cfg: GripConfig?): boolean
	if not trainerAvailable then
		return false
	end
	local c = sections(cfg)
	local nextTrainer = GripMath.trainer(nextTrainerIndex(state), c)
	if nextTrainer == nil then
		return false
	end
	return GripMath.levelFor(state.total, c) >= nextTrainer.level and whole(coins) >= nextTrainer.cost
end

-- The one next-goal line (§17.7 order): 1 "Upgrade ready" under the §17.5 rule (cost <= goalUpgradeMaxCostWhileCollecting,
-- or the player owns the highest-priced shop squishy); 2 the next unlock (pad, trainer gate or rank); 3 max level.
-- `owned` = profile.owned (squishyId -> entry). nil only when nothing applies.
function GripMath.nextGoal(
	state: GoalState,
	owned: { [string]: any },
	coins: number,
	trainerAvailable: boolean,
	cfg: GripConfig?
): Goal?
	local c = sections(cfg)
	local grip = c.Grip
	local level = GripMath.levelFor(state.total, c)
	local nextIndex = nextTrainerIndex(state)
	local nextTrainer = GripMath.trainer(nextIndex, c)

	-- 1. Upgrade ready.
	if nextTrainer ~= nil and GripMath.upgradeReady(state, coins, trainerAvailable, c) then
		local topId = GripMath.topShopSquishyId()
		local ownsTop = topId ~= nil and owned[topId] ~= nil
		if nextTrainer.cost <= grip.goalUpgradeMaxCostWhileCollecting or ownsTop then
			return {
				kind = "upgrade",
				textKey = "grip.goalUpgrade",
				nameKey = "grip.trainer." .. nextTrainer.key,
				index = nextIndex,
				level = nextTrainer.level,
				coins = nextTrainer.cost,
			}
		end
	end

	-- 2. The next unlock: the lowest level above the current one (pad, then trainer gate, then rank on a tie).
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
	if trainerAvailable and nextTrainer ~= nil and nextTrainer.level > level then
		table.insert(candidates, {
			kind = "trainer",
			textKey = "grip.goalTrainer",
			nameKey = "grip.trainer." .. nextTrainer.key,
			index = nextIndex,
			level = nextTrainer.level,
		})
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

	-- 3. Max level.
	if level >= maxLevelOf(c) then
		return { kind = "max", textKey = "grip.goalMax" }
	end
	return nil
end

-- Public: the trainer purchase (§17.5)

function GripMath.upgradeDecision(
	state: UpgradeState,
	targetLevel: number,
	expectedPrice: number,
	cfg: GripConfig?
): UpgradeDecision
	local c = sections(cfg)
	local trainers = c.Grip.Trainer
	local net = if c.Net ~= nil then c.Net else Config.Net
	-- Step 2: the argument shapes (NetService already checked whole, finite numbers; this is the range check).
	if not isWholeNumber(targetLevel) or targetLevel < 2 or targetLevel > #trainers then
		return reject("net.invalid", 0)
	end
	local target = trainers[targetLevel]
	local cost: number = target.cost
	if not isWholeNumber(expectedPrice) or expectedPrice < 0 or expectedPrice >= net.maxAbsNumber then
		return reject("net.invalid", cost)
	end
	local owned = math.max(1, whole(state.trainer))
	-- Step 4: already owned -> a replay, nothing is charged.
	if owned >= targetLevel then
		return { kind = "replay", cost = cost, charged = false }
	end
	-- Step 5: bought in order.
	if targetLevel ~= owned + 1 then
		return reject("trainer.notNext", cost)
	end
	-- Step 6: the Grip Level gate.
	if whole(state.level) < target.level then
		return reject("trainer.locked", cost)
	end
	-- Step 7: the client's price is only compared, never charged.
	if expectedPrice ~= cost then
		return reject("trainer.priceChanged", cost)
	end
	return { kind = "buy", cost = cost, charged = true }
end

return table.freeze(GripMath)
