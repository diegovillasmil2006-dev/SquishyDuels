--!strict
-- Config/ValidateGear: the checks of Config.Economy.Gear (gear step 2, 2026-10-26). Apart from Config/init (Roblox's
-- 200,000-character Source limit): HighwayService runs it at init and stops on any problem. Pure; shared.
-- validate(config) -> { string }: the problems as text (an empty list = valid). `config` = a table with Config's
-- Economy section (Config itself or a test's copy). Checks:
--   * tierSteps a non-empty list of whole numbers >= 1; tierPower finite and > 1;
--   * launcherPrices one whole Coin price a step (as many as tierSteps add up to), each in [1, maxCoins], strictly
--     rising; armGearShare in (0, 1] with every launcher price x it whole;
--   * armorPrices one whole price a tier, in [1, maxCoins], strictly rising;
--   * trapChance one chance a tier in [0, 1); trapBase a whole number >= 0.

local G = "Config.Economy.Gear"

local function isNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isWhole(v: unknown): boolean
	return isNumber(v) and math.floor(v :: number) == v
end

return function(config: any): { string }
	local problems: { string } = {}
	local function expect(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end

	local economy = if type(config) == "table" then config.Economy else nil
	local g = if type(economy) == "table" then economy.Gear else nil
	if type(g) ~= "table" then
		table.insert(problems, `{G} is missing`)
		return problems
	end
	local maxCoins = if isNumber(economy.maxCoins) then economy.maxCoins else math.huge

	local steps = 0
	if type(g.tierSteps) ~= "table" or #g.tierSteps == 0 then
		table.insert(problems, `{G}.tierSteps must be a non-empty list`)
	else
		for tier, n in g.tierSteps do
			expect(isWhole(n) and n >= 1, `{G}.tierSteps[{tier}] must be a whole number >= 1 (got {tostring(n)})`)
			steps += if isNumber(n) then n else 0
		end
	end
	expect(isNumber(g.tierPower) and g.tierPower > 1, `{G}.tierPower must be a number above 1`)

	-- A list of whole prices in [1, maxCoins], strictly rising, `count` long.
	local function prices(list: any, name: string, count: number)
		if type(list) ~= "table" then
			table.insert(problems, `{G}.{name} must be a list`)
			return
		end
		expect(#list == count, `{G}.{name} must have {count} prices (got {#list})`)
		local last = 0
		for index, price in list do
			if not (isWhole(price) and price >= 1 and price <= maxCoins) then
				table.insert(
					problems,
					`{G}.{name}[{index}] must be whole Coins in [1, maxCoins] (got {tostring(price)})`
				)
				continue
			end
			expect(price > last, `{G}.{name}[{index}] must be above the price before it (got {price})`)
			last = price
		end
	end
	prices(g.launcherPrices, "launcherPrices", steps)
	prices(g.armorPrices, "armorPrices", if type(g.tierSteps) == "table" then #g.tierSteps else 0)

	local share = g.armGearShare
	if not (isNumber(share) and share > 0 and share <= 1) then
		table.insert(problems, `{G}.armGearShare must be in (0, 1]`)
	elseif type(g.launcherPrices) == "table" then
		for index, price in g.launcherPrices do
			expect(
				not isNumber(price) or isWhole(price * share),
				`{G}.launcherPrices[{index}] x armGearShare must be whole Coins (got {tostring(price)})`
			)
		end
	end

	if type(g.trapChance) ~= "table" or type(g.tierSteps) ~= "table" or #g.trapChance ~= #g.tierSteps then
		table.insert(problems, `{G}.trapChance must have one chance a tier`)
	else
		for zone, chance in g.trapChance do
			expect(isNumber(chance) and chance >= 0 and chance < 1, `{G}.trapChance[{zone}] must be in [0, 1)`)
		end
	end
	expect(isWhole(g.trapBase) and g.trapBase >= 0, `{G}.trapBase must be a whole number >= 0`)
	return problems
end
