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
--   GearMath.steps(gear, line)           -> number: the steps bought on a line of a saved gear table (gear step 3: the
--                                           shop's cards); broken -> 0, cut, at most the line's last
--   GearMath.price(line, step)           -> number?: the Coins of that step (launchers: launcherPrices; arm gear:
--                                           x armGearShare; armor: armorPrices); nil outside 1..maxStep or a broken
--                                           step
--   GearMath.multiplier(gear)            -> number: the throw power x of the three power lines' steps (a step of a
--                                           tier of n steps is x tierPower^(1/n)); armor adds none; a missing or
--                                           broken line counts as none, past the last step as the last
--   GearMath.buyDecision(gear, line, expectedPrice) -> ({step, price}?, code?): the next step of the line and its
--                                           price, or nil and net.invalid (not a line) / gear.max (all bought) /
--                                           gear.priceChanged (the price is compared, never charged)
-- Big job item 10 (2026-11-10; Config/Gear: the Gear Box and Golden gear). A saved gear table may also hold
-- `cards = {line = 0..goldCards}` (the gear cards waiting on each line) and `gold = {line = tier}` (the tier of that
-- line whose piece is Golden; 0 or missing = none):
--   GearMath.tier(gear, line)            -> 0..7: the tier owned on a line (a power line: the tier of its last step;
--                                           armor: a step a tier; not a line: 0)
--   GearMath.cards(gear, line)           -> 0..goldCards: the gear cards waiting on a line
--   GearMath.isGold(gear, line)          -> boolean: the line's current piece is Golden
--   GearMath.armor(gear)                 -> number: the zones whose traps the armor goes through: its pieces, and one
--                                           more when the piece is Golden
--   GearMath.goldAfter(gear, line, added) -> (cards, goldTier, turned): the line after `added` cards land on it (0:
--                                           after a buy on it): goldCards waiting and a piece that is not Golden ->
--                                           that piece's tier Golden, no cards left, turned = true; else the cards
--                                           (never over goldCards) and the Golden tier as they are
--   GearMath.boxPrice(gear)              -> number: the Gear Box's Coins: boxShare x the dearest step bought last
--                                           (nothing bought: x the first launcher step), whole, at least 1
--   GearMath.boxPool(gear)               -> {line}: the lines a Gear Box can give a card for, in LINES order: fewer
--                                           than goldCards waiting, and not a Golden last-tier piece (no later piece
--                                           could use them); empty = no line has room
--   GearMath.boxDecision(gear, expectedPrice) -> ({price, pool}?, code?): the box's price and pool, or nil and
--                                           gear.boxFull (no line has room) / gear.priceChanged
-- multiplier(gear) is also x goldPower for every power line whose piece is Golden.

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
local CODE_BOX_FULL = "gear.boxFull"
local ARMOR = "armor"

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
	if line == ARMOR then
		return #G.armorPrices
	end
	return if IS_POWER_LINE[line] then #G.launcherPrices else nil
end

GearMath.steps = stepsOf

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

-- Item 10: a whole number of a gear sub-table (cards, gold) for a line, in [0, hi]; broken or missing -> 0.
local function sub(gear: any, field: string, line: string, hi: number): number
	local t = if type(gear) == "table" then gear[field] else nil
	local value = if type(t) == "table" then t[line] else nil
	if not isFinite(value) then
		return 0
	end
	return math.clamp(math.floor(value), 0, hi)
end

function GearMath.tier(gear: any, line: any): number
	if GearMath.maxStep(line) == nil then
		return 0
	end
	local steps = stepsOf(gear, line)
	return if line == ARMOR then steps else GearMath.tierOf(steps)
end

function GearMath.cards(gear: any, line: string): number
	return sub(gear, "cards", line, G.goldCards)
end

function GearMath.isGold(gear: any, line: any): boolean
	local tier = GearMath.tier(gear, line)
	return tier > 0 and sub(gear, "gold", line, #G.tierSteps) == tier
end

function GearMath.armor(gear: any): number
	return stepsOf(gear, ARMOR) + (if GearMath.isGold(gear, ARMOR) then 1 else 0)
end

function GearMath.multiplier(gear: any): number
	local exponent = 0 -- in powers of tierPower
	local gold = 1
	for _, line in POWER_LINES do
		for step = 1, stepsOf(gear, line) do
			exponent += 1 / G.tierSteps[GearMath.tierOf(step)]
		end
		if GearMath.isGold(gear, line) then
			gold *= G.goldPower
		end
	end
	return G.tierPower ^ exponent * gold
end

function GearMath.goldAfter(gear: any, line: string, added: number): (number, number, boolean)
	local cards = math.min(GearMath.cards(gear, line) + added, G.goldCards)
	local tier = GearMath.tier(gear, line)
	local gold = sub(gear, "gold", line, #G.tierSteps)
	if cards >= G.goldCards and tier > 0 and gold ~= tier then
		return 0, tier, true
	end
	return cards, gold, false
end

function GearMath.boxPrice(gear: any): number
	local dearest = GearMath.price(POWER_LINES[1], 1) :: number
	for _, line in GearMath.LINES do
		local steps = stepsOf(gear, line)
		if steps > 0 then
			dearest = math.max(dearest, GearMath.price(line, steps) :: number)
		end
	end
	return math.max(1, math.floor(dearest * G.boxShare))
end

function GearMath.boxPool(gear: any): { string }
	local pool: { string } = {}
	for _, line in GearMath.LINES do
		local lastGold = GearMath.isGold(gear, line) and GearMath.tier(gear, line) >= #G.tierSteps
		if GearMath.cards(gear, line) < G.goldCards and not lastGold then
			table.insert(pool, line)
		end
	end
	return pool
end

function GearMath.boxDecision(gear: any, expectedPrice: any): ({ price: number, pool: { string } }?, string?)
	local pool = GearMath.boxPool(gear)
	if #pool == 0 then
		return nil, CODE_BOX_FULL
	end
	local price = GearMath.boxPrice(gear)
	if expectedPrice ~= price then
		return nil, CODE_PRICE
	end
	return { price = price, pool = pool }, nil
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
