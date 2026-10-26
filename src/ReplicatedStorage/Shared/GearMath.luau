--!strict
-- GearMath: pure gear arithmetic (gear step 2, 2026-10-26). Shared: the server prices every buy and powers every throw
-- with it (HighwayService), the client shows the same numbers. Every number is Config.Economy.Gear's (Config/Gear: its
-- sources). No instances, no yields, no side effects.
--
-- API:
--   GearMath.LINES                       -> { "held", "platform", "arm", "armor" }: the saved profile.gear fields
--   GearMath.maxStep(line)               -> number?: the last step of a line (a power line: the tiers' steps added up,
--                                           36; armor: one a tier, 7); nil for anything that is not a line
--   GearMath.tierOf(step)                -> 0..7: the tier a power-line step is in (0 for none)
--   GearMath.price(line, step)           -> number?: the Coins of that step (launchers: launcherPrices; arm gear:
--                                           x armGearShare; armor: armorPrices); nil outside 1..maxStep or a broken
--                                           step
--   GearMath.multiplier(gear)            -> number: the throw power x of the three power lines' steps (a step of a
--                                           tier of n steps is x tierPower^(1/n)); armor adds none; a missing or
--                                           broken line counts as none, past the last step as the last
--   GearMath.trapChance(zone)            -> number: the chance a throw reaching that zone is trapped (zones clamped
--                                           to the list)
--   GearMath.trapKeep(zone, armor)       -> number: the share of the power a trap leaves, 2^-(zone + trapBase -
--                                           armor), at most 1
--   GearMath.buyDecision(gear, line, expectedPrice) -> ({step, price}?, code?): the next step of the line and its
--                                           price, or nil and net.invalid (not a line) / gear.max (all bought) /
--                                           gear.priceChanged (the price is compared, never charged)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local G = Config.Economy.Gear

local GearMath = {}

GearMath.LINES = table.freeze({ "held", "platform", "arm", "armor" })

local POWER_LINES = { "held", "platform", "arm" }
local IS_POWER_LINE: { [string]: boolean } = { held = true, platform = true, arm = true }
local CODE_INVALID = "net.invalid"
local CODE_MAX = "gear.max"
local CODE_PRICE = "gear.priceChanged"

local function isFinite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- The steps bought on a line of a saved gear table (broken -> 0, cut, at most the line's last).
local function stepsOf(gear: any, line: string): number
	local value = if type(gear) == "table" then gear[line] else nil
	if not isFinite(value) then
		return 0
	end
	return math.clamp(math.floor(value), 0, GearMath.maxStep(line) :: number)
end

function GearMath.maxStep(line: any): number?
	if line == "armor" then
		return #G.armorPrices
	end
	return if IS_POWER_LINE[line] then #G.launcherPrices else nil
end

function GearMath.tierOf(step: number): number
	local before = 0
	for tier, n in G.tierSteps do
		if step <= before + n then
			return if step >= 1 then tier else 0
		end
		before += n
	end
	return #G.tierSteps
end

function GearMath.price(line: any, step: any): number?
	local last = GearMath.maxStep(line)
	if last == nil or not isFinite(step) or math.floor(step) ~= step or step < 1 or step > last then
		return nil
	end
	if line == "armor" then
		return G.armorPrices[step]
	end
	local price = G.launcherPrices[step]
	return if line == "arm" then price * G.armGearShare else price
end

function GearMath.multiplier(gear: any): number
	local exponent = 0 -- in powers of tierPower
	for _, line in POWER_LINES do
		for step = 1, stepsOf(gear, line) do
			exponent += 1 / G.tierSteps[GearMath.tierOf(step)]
		end
	end
	return G.tierPower ^ exponent
end

function GearMath.trapChance(zone: number): number
	return G.trapChance[math.clamp(math.floor(zone), 1, #G.trapChance)]
end

function GearMath.trapKeep(zone: number, armor: number): number
	return 2 ^ -math.max(0, zone + G.trapBase - armor)
end

function GearMath.buyDecision(gear: any, line: any, expectedPrice: any): ({ step: number, price: number }?, string?)
	local last = GearMath.maxStep(line)
	if last == nil then
		return nil, CODE_INVALID
	end
	local step = stepsOf(gear, line) + 1
	if step > last then
		return nil, CODE_MAX
	end
	local price = GearMath.price(line, step) :: number
	if expectedPrice ~= price then
		return nil, CODE_PRICE
	end
	return { step = step, price = price }, nil
end

return GearMath
