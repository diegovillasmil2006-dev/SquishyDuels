--!strict
-- Config/ValidateIncome: the checks of Config.Economy.Income (INCOME step 1, 2026-10-26). Apart from Config/init (Roblox's
-- 200,000-character Source limit): PenService runs it at init and stops on any problem. Pure; shared.
-- validate(config) -> { string }: the problems as text (an empty list = valid). `config` = a table with Config's
-- Economy section (Config itself or a test's copy). For each line, coins and all: boost a finite number above 1;
-- prices a non-empty list of whole Coins in [1, maxCoins], strictly rising.

local I = "Config.Economy.Income"
local LINES = { "coins", "all" }

local function isWhole(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and math.floor(v) == v
end

return function(config: any): { string }
	local problems: { string } = {}
	local economy = if type(config) == "table" then config.Economy else nil
	local income = if type(economy) == "table" then economy.Income else nil
	if type(income) ~= "table" then
		table.insert(problems, `{I} is missing`)
		return problems
	end
	local maxCoins = if type(economy.maxCoins) == "number" then economy.maxCoins else math.huge
	for _, name in LINES do
		local line = income[name]
		if type(line) ~= "table" then
			table.insert(problems, `{I}.{name} is missing`)
			continue
		end
		local boost = line.boost
		if not (type(boost) == "number" and boost == boost and boost > 1 and boost < math.huge) then
			table.insert(problems, `{I}.{name}.boost must be a number above 1 (got {tostring(boost)})`)
		end
		if type(line.prices) ~= "table" or #line.prices == 0 then
			table.insert(problems, `{I}.{name}.prices must be a non-empty list`)
			continue
		end
		local last = 0
		for level, price in line.prices do
			if not (isWhole(price) and price >= 1 and price <= maxCoins) then
				table.insert(problems, `{I}.{name}.prices[{level}] must be whole Coins in [1, maxCoins]`)
			elseif price <= last then
				table.insert(problems, `{I}.{name}.prices[{level}] must be above the price before it`)
			else
				last = price
			end
		end
	end
	return problems
end
