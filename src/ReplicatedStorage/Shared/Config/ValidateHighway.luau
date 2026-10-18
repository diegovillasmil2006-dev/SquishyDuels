--!strict
-- Config/ValidateHighway: the checks of Config.Economy.Highway (the highway's distances, pens3 phase 12, 2026-10-17).
-- Apart from Config/init (Roblox's 200,000-character Source limit): SDTools HighwayBuilder runs it and refuses to build
-- on any problem; phase 13's highway service runs it at init. Pure; shared.
-- validate(config) -> { string }: the problems as text (an empty list = valid). `config` = a table with Config's
-- Economy section (Config itself or a test's copy). Checks:
--   * starts is a non-empty list of whole numbers, starts[1] = 0 (the first biome starts at the gate), strictly rising
--     (no biome is empty);
--   * gatesAt is a whole number above the last start (the last biome is not empty).

local H = "Config.Economy.Highway"

local function isWhole(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and math.floor(v) == v
end

local function show(v: unknown): string
	return if type(v) == "string" then string.format("%q", v) else tostring(v)
end

return function(config: any): { string }
	local problems: { string } = {}
	local function expect(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end

	local economy = if type(config) == "table" then config.Economy else nil
	local c = if type(economy) == "table" then economy.Highway else nil
	if type(c) ~= "table" then
		table.insert(problems, `{H} is missing`)
		return problems
	end

	local starts = c.starts
	local last = -math.huge
	if type(starts) ~= "table" or #starts == 0 then
		table.insert(problems, `{H}.starts must be a non-empty list (got {show(starts)})`)
	else
		for index, start in starts do
			if not isWhole(start) then
				table.insert(problems, `{H}.starts[{index}] must be a whole number (got {show(start)})`)
				continue
			end
			if index == 1 then
				expect(start == 0, `{H}.starts[1] must be 0, the start line (got {show(start)})`)
			else
				expect(start > last, `{H}.starts[{index}] must be above starts[{index - 1}] (got {show(start)})`)
			end
			last = math.max(last, start)
		end
	end
	expect(
		isWhole(c.gatesAt) and c.gatesAt > last,
		`{H}.gatesAt must be a whole number above the last start (got {show(c.gatesAt)})`
	)
	return problems
end
