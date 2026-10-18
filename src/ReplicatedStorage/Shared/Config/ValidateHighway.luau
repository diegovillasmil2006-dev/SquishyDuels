--!strict
-- Config/ValidateHighway: the checks of Config.Economy.Highway (the highway's distances, pens3 phase 12, 2026-10-17).
-- Apart from Config/init (Roblox's 200,000-character Source limit): SDTools HighwayBuilder runs it and refuses to build
-- on any problem; phase 13's highway service runs it at init. Pure; shared.
-- validate(config, catalog?) -> { string }: the problems as text (an empty list = valid). `config` = a table with
-- Config's Economy section (Config itself or a test's copy); `catalog` = the Catalog (its isValidId; nil skips the gift
-- kind check). Checks:
--   * starts is a non-empty list of whole numbers, starts[1] = 0 (the first biome starts at the gate), strictly rising
--     (no biome is empty);
--   * gatesAt is a whole number above the last start (the last biome is not empty).
-- Pens3 phase 13 (the throw; Config/Highway's header):
--   * walls a list of one finite power a biome, walls[1] > 0, strictly rising; gatesPower finite and above the last;
--   * power.base > 0 and power.perGripLevel >= 1 (finite); pay.perStud > 0 (p13v3: Coins by distance) and, with
--     config.Economy.Pen, pay.perStud x Pen.minSqueezeValue >= 1 (one stud farther always pays at least one Coin
--     more), pay.grip a whole number >= 1 (GripService.addFromHighway takes whole squeezes); foodBag.seconds and
--     foodBag.squeezes > 0;
--   * gifts a list of {biome a whole number in 1..#starts, kind a non-empty string (a Catalog id when a catalog is
--     given), count a whole number >= 1};
--   * every flight number finite and > 0, carryMax >= carryMin; inFlightGraceSeconds in [0, releaseSeconds);
--     areaMarginStuds finite and >= 0;
--   * autoClick: clientPressesPerSecond a whole number >= 1; maxPerSecond under it (a stream at the client's ceiling
--     is never judged) with 1 / maxPerSecond under maxMeanGapSeconds (something is left to judge); blockIntervals a
--     whole number >= 2, windowIntervals a whole multiple of it with at least MIN_BLOCKS blocks; maxMeanGapSeconds >
--     0, maxBlockSpreadSeconds in (0, MAX_SPREAD], burstGapSeconds above maxMeanGapSeconds; floodPresses a whole
--     number above 2 x clientPressesPerSecond (more than an honest client ever sends in a second); with config.Net:
--     Net.Remotes.HighwayThrow's rate above clientPressesPerSecond and its burst at least that (an honest client is
--     never limited), and the squeeze presses' cap (Net.AutoClick.clientPressesPerSecond) plus this one at most
--     Net.Global.rate (squeezing and throwing at once never trips the global cap).

local H = "Config.Economy.Highway"
local MIN_BLOCKS = 10 -- = Config/ValidateAutoClick's: the spread of fewer block means is too noisy to trust
local MAX_SPREAD = 0.01 -- seconds: anything above would call people machines (Config/ValidateAutoClick)
local FLIGHT_KEYS = {
	"releaseSeconds",
	"carryShare",
	"carryMin",
	"carryMax",
	"airSeconds",
	"airPerRoot",
	"airRoot",
	"peakShare",
	"groundSeconds",
	"groundScale",
	"groundRef",
	"groundPower",
	"rollPower",
	"hopEvery",
	"hopBase",
	"hopScale",
}

local function isNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isWhole(v: unknown): boolean
	return isNumber(v) and math.floor(v :: number) == v
end

local function show(v: unknown): string
	return if type(v) == "string" then string.format("%q", v) else tostring(v)
end

return function(config: any, catalog: any?): { string }
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

	-- Pens3 phase 13: the throw.
	local biomes = if type(starts) == "table" then #starts else 0
	local walls = c.walls
	local top = -math.huge
	if type(walls) ~= "table" or #walls ~= biomes then
		table.insert(problems, `{H}.walls must list one power a biome ({biomes}, got {show(walls)})`)
	else
		for index, wall in walls do
			local floor = if index == 1 then 0 else top
			local below = if index == 1 then "0" else `walls[{index - 1}]`
			expect(
				isNumber(wall) and wall > floor,
				`{H}.walls[{index}] must be a finite power above {below} (got {show(wall)})`
			)
			top = if isNumber(wall) then math.max(top, wall) else top
		end
	end
	expect(
		isNumber(c.gatesPower) and c.gatesPower > top,
		`{H}.gatesPower must be a finite power above the last wall (got {show(c.gatesPower)})`
	)

	local function section(name: string): { [string]: any }
		local value = c[name]
		if type(value) ~= "table" then
			table.insert(problems, `{H}.{name} must be a table (got {show(value)})`)
			return {}
		end
		return value
	end
	local power, pay, bag = section("power"), section("pay"), section("foodBag")
	expect(isNumber(power.base) and power.base > 0, `{H}.power.base must be above 0 (got {show(power.base)})`)
	expect(
		isNumber(power.perGripLevel) and power.perGripLevel >= 1,
		`{H}.power.perGripLevel must be at least 1 (got {show(power.perGripLevel)})`
	)
	expect(isNumber(pay.perStud) and pay.perStud > 0, `{H}.pay.perStud must be above 0 (got {show(pay.perStud)})`)
	local pen = if type(economy.Pen) == "table" then economy.Pen else nil
	if pen ~= nil and isNumber(pay.perStud) and pay.perStud > 0 then
		expect(
			isNumber(pen.minSqueezeValue) and pay.perStud * pen.minSqueezeValue >= 1,
			`{H}.pay.perStud x Config.Economy.Pen.minSqueezeValue must be at least 1, so one stud farther always pays `
				.. `more (got {show(pay.perStud)} x {show(pen.minSqueezeValue)})`
		)
	end
	expect(isWhole(pay.grip) and pay.grip >= 1, `{H}.pay.grip must be a whole number >= 1 (got {show(pay.grip)})`)
	expect(isNumber(bag.seconds) and bag.seconds > 0, `{H}.foodBag.seconds must be above 0 (got {show(bag.seconds)})`)
	expect(
		isNumber(bag.squeezes) and bag.squeezes > 0,
		`{H}.foodBag.squeezes must be above 0 (got {show(bag.squeezes)})`
	)

	local gifts = c.gifts
	if type(gifts) ~= "table" then
		table.insert(problems, `{H}.gifts must be a list (got {show(gifts)})`)
	else
		for index, gift in gifts do
			local g = if type(gift) == "table" then gift else {}
			local at = `{H}.gifts[{index}]`
			expect(
				isWhole(g.biome) and g.biome >= 1 and g.biome <= biomes,
				`{at}.biome must be a biome 1..{biomes} (got {show(g.biome)})`
			)
			local known = type(g.kind) == "string"
				and g.kind ~= ""
				and (catalog == nil or (catalog :: any).isValidId(g.kind) == true)
			expect(known, `{at}.kind must be a squishy id (got {show(g.kind)})`)
			expect(isWhole(g.count) and g.count >= 1, `{at}.count must be a whole number >= 1 (got {show(g.count)})`)
		end
	end

	local flight = section("flight")
	for _, key in FLIGHT_KEYS do
		expect(isNumber(flight[key]) and flight[key] > 0, `{H}.flight.{key} must be above 0 (got {show(flight[key])})`)
	end
	if isNumber(flight.carryMin) and isNumber(flight.carryMax) then
		expect(
			flight.carryMax >= flight.carryMin,
			`{H}.flight.carryMax must be at least carryMin (got {show(flight.carryMax)})`
		)
	end
	local grace = c.inFlightGraceSeconds
	expect(
		isNumber(grace) and grace >= 0 and (not isNumber(flight.releaseSeconds) or grace < flight.releaseSeconds),
		`{H}.inFlightGraceSeconds must be in [0, flight.releaseSeconds) (got {show(grace)})`
	)
	expect(
		isNumber(c.areaMarginStuds) and c.areaMarginStuds >= 0,
		`{H}.areaMarginStuds must be at least 0 (got {show(c.areaMarginStuds)})`
	)

	local a = section("autoClick")
	local cap = a.clientPressesPerSecond
	local capOk = isWhole(cap) and cap >= 1
	expect(capOk, `{H}.autoClick.clientPressesPerSecond must be a whole number >= 1 (got {show(cap)})`)
	expect(
		isNumber(a.maxPerSecond)
			and a.maxPerSecond > 0
			and (not capOk or a.maxPerSecond < cap)
			and (not isNumber(a.maxMeanGapSeconds) or 1 / a.maxPerSecond < a.maxMeanGapSeconds),
		`{H}.autoClick.maxPerSecond must be under clientPressesPerSecond, its gap under maxMeanGapSeconds (got {show(
			a.maxPerSecond
		)})`
	)
	local block = a.blockIntervals
	expect(
		isWhole(block) and block >= 2,
		`{H}.autoClick.blockIntervals must be a whole number >= 2 (got {show(block)})`
	)
	expect(
		isWhole(a.windowIntervals)
			and isWhole(block)
			and block >= 2
			and a.windowIntervals % block == 0
			and a.windowIntervals // block >= MIN_BLOCKS,
		`{H}.autoClick.windowIntervals must be a whole multiple of blockIntervals with at least {MIN_BLOCKS} blocks `
			.. `(got {show(a.windowIntervals)})`
	)
	expect(
		isNumber(a.maxMeanGapSeconds) and a.maxMeanGapSeconds > 0,
		`{H}.autoClick.maxMeanGapSeconds must be above 0 (got {show(a.maxMeanGapSeconds)})`
	)
	expect(
		isNumber(a.maxBlockSpreadSeconds) and a.maxBlockSpreadSeconds > 0 and a.maxBlockSpreadSeconds <= MAX_SPREAD,
		`{H}.autoClick.maxBlockSpreadSeconds must be in (0, {MAX_SPREAD}] (got {show(a.maxBlockSpreadSeconds)})`
	)
	expect(
		isNumber(a.burstGapSeconds) and (not isNumber(a.maxMeanGapSeconds) or a.burstGapSeconds > a.maxMeanGapSeconds),
		`{H}.autoClick.burstGapSeconds must be above maxMeanGapSeconds (got {show(a.burstGapSeconds)})`
	)
	local honest = if capOk then 2 * cap else 0
	expect(
		isWhole(a.floodPresses) and a.floodPresses >= 1 and a.floodPresses > honest,
		`{H}.autoClick.floodPresses must be a whole number above {honest} (twice the client's presses a second; `
			.. `got {show(a.floodPresses)})`
	)
	local net = if type(config.Net) == "table" then config.Net else nil
	if net ~= nil and capOk then
		local remote = if type(net.Remotes) == "table" then net.Remotes.HighwayThrow else nil
		local entry = if type(remote) == "table" then remote else {}
		expect(
			isNumber(entry.rate) and entry.rate > cap and isNumber(entry.burst) and entry.burst >= cap,
			`Config.Net.Remotes.HighwayThrow must refill faster than {H}.autoClick.clientPressesPerSecond ({cap}) `
				.. `and hold at least that many (got rate {show(entry.rate)}, burst {show(entry.burst)})`
		)
		local squeeze = if type(net.AutoClick) == "table" then net.AutoClick.clientPressesPerSecond else nil
		local global = if type(net.Global) == "table" then net.Global.rate else nil
		expect(
			isNumber(squeeze) and isNumber(global) and squeeze + cap <= global,
			`Config.Net.Global.rate ({show(global)}) must hold the squeeze and throw presses together `
				.. `({show(squeeze)} + {cap})`
		)
	end
	return problems
end
