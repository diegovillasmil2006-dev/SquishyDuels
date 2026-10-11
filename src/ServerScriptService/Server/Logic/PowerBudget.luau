--!strict
-- PowerBudget: the per-squishy throw power budget (DESIGN §5.8). Server only, pure (no instances, no yields).
-- Squishies differ only in how hard their throws are to dodge, so the budget has one dimension. Reference: distance
-- D = 40 studs, dodge speed V = 16 studs/s, Kitty Bread baseline (speed 95, radius 1.0, cooldown 1.00, windup 0.18);
-- 1 point = 0.4 studs of dodge slack at 40 studs = 5% throw rate. Arc (gravity) costs 0 points because
-- ProjectileMath.solveLaunchDir lands on the reticle; gravity is only checked against its band.
--
--   Ps = V·D·(1/base.speed − 1/speed)/studsPerPoint     Pr = (radius − base.radius)/studsPerPoint
--   Pw = V·(base.windup − windup)/studsPerPoint         Pc = (base.cooldown/cooldown − 1)/ratePerPoint
--   Σ = Ps + Pr + Pw + Pc
--   dodge slack(D) = (windup + D/speed − reaction)·V − (radius + Hitbox.radius)
-- Rules: every throw stat inside Config.Combat.Bands; no ability → |Σ| ≤ tolerance; with an ultimate →
-- |Σ + ultimateCost| ≤ tolerance (ultimateCost = Config.Abilities[ultimateId].budgetCost, 2.0 for Dragon Rush).
--
-- Every function takes an optional `cfg` (a table with Config's `Combat` and `Abilities` sections, e.g. a test's
-- copy of Config); nil = the live Config.
--
-- API:
--   PowerBudget.points(throw, cfg?)              -> Points { Ps, Pr, Pw, Pc, sum }
--   PowerBudget.ultimateCost(ultimateId?, cfg?)  -> number? (0 for nil, nil for an unknown ultimate)
--   PowerBudget.flightTime(speed, distance?, cfg?) -> s to cover `distance` (default D) horizontally
--   PowerBudget.dodgeSlack(throw, distance?, cfg?) -> studs of dodge slack at `distance` (default D)
--   PowerBudget.check(def, cfg?)                 -> (ok: boolean, problems: { string }); never errors

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

-- Types

type SquishyDef = Types.SquishyDef

-- The throw stats the points depend on (a SquishyDef `throw` table fits).
export type ThrowStats = { speed: number, radius: number, cooldown: number, windup: number }

export type Points = { Ps: number, Pr: number, Pw: number, Pc: number, sum: number }

export type BudgetConfig = { Combat: any, Abilities: any }

-- Constants

local THROW_STATS = { "speed", "gravity", "radius", "cooldown", "windup" }

-- Module table

local PowerBudget = {}

-- Private

local function config(cfg: BudgetConfig?): BudgetConfig
	return if cfg ~= nil then cfg else Config
end

local function isNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function show(value: unknown): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

-- Public

function PowerBudget.points(throw: ThrowStats, cfg: BudgetConfig?): Points
	local budget = config(cfg).Combat.PowerBudget
	local base = budget.baseline
	local v, d, studs = budget.dodgeSpeed, budget.referenceDistance, budget.studsPerPoint
	local ps = v * d * (1 / base.speed - 1 / throw.speed) / studs
	local pr = (throw.radius - base.radius) / studs
	local pw = v * (base.windup - throw.windup) / studs
	local pc = (base.cooldown / throw.cooldown - 1) / budget.ratePerPoint
	return { Ps = ps, Pr = pr, Pw = pw, Pc = pc, sum = ps + pr + pw + pc }
end

function PowerBudget.ultimateCost(ultimateId: string?, cfg: BudgetConfig?): number?
	if ultimateId == nil then
		return 0
	end
	local ability = config(cfg).Abilities[ultimateId]
	if type(ability) ~= "table" or not isNumber(ability.budgetCost) then
		return nil
	end
	return ability.budgetCost
end

function PowerBudget.flightTime(speed: number, distance: number?, cfg: BudgetConfig?): number
	local d = if distance ~= nil then distance else config(cfg).Combat.PowerBudget.referenceDistance
	return d / speed
end

function PowerBudget.dodgeSlack(throw: ThrowStats, distance: number?, cfg: BudgetConfig?): number
	local c = config(cfg)
	local budget = c.Combat.PowerBudget
	local d = if distance ~= nil then distance else budget.referenceDistance
	return (throw.windup + d / throw.speed - budget.reactionSeconds) * budget.dodgeSpeed
		- (throw.radius + c.Combat.Hitbox.radius)
end

-- Checks one catalog entry: throw stats present, finite and inside their bands, a known ultimate, and the budget
-- rule. Returns every problem found (developer-facing text), so a malformed def never raises.
function PowerBudget.check(def: SquishyDef, cfg: BudgetConfig?): (boolean, { string })
	local c = config(cfg)
	local problems: { string } = {}
	local entry = def :: any
	local id = if type(entry) == "table" and type(entry.id) == "string" then entry.id else "?"
	local path = `Catalog.{id}`

	local throw = if type(entry) == "table" then entry.throw else nil
	if type(throw) ~= "table" then
		table.insert(problems, `{path}.throw is missing`)
		return false, problems
	end

	local statsOk = true
	for _, stat in THROW_STATS do
		local value = throw[stat]
		local band = c.Combat.Bands[stat]
		if not isNumber(value) or (value :: number) <= 0 then
			statsOk = false
			table.insert(problems, `{path}.throw.{stat} must be a finite number > 0 (got {show(value)})`)
		elseif band ~= nil and ((value :: number) < band.min or (value :: number) > band.max) then
			table.insert(problems, `{path}.throw.{stat} {value} is outside its band {band.min}-{band.max}`)
		end
	end

	local cost = PowerBudget.ultimateCost(entry.ultimateId, c)
	if cost == nil then
		table.insert(problems, `{path}.ultimateId {show(entry.ultimateId)} has no budgetCost in Config.Abilities`)
	end

	if statsOk then
		local sum = PowerBudget.points(throw, c).sum
		local net = sum + (cost or 0)
		local tolerance = c.Combat.PowerBudget.tolerance
		if math.abs(net) > tolerance then
			local detail = string.format("Σ %.2f", sum)
			if entry.ultimateId ~= nil then
				detail = string.format("Σ %.2f + ultimate %.2f = %.2f", sum, cost or 0, net)
			end
			table.insert(problems, `{path} is over the power budget: |{detail}| > {tolerance}`)
		end
	end

	return #problems == 0, problems
end

return table.freeze(PowerBudget)
