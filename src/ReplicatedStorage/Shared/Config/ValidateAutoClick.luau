--!strict
-- Config/ValidateAutoClick: the checks of Config.Net.AutoClick (auto-clicker check, 2026-10-16). Apart from
-- Config/init (Roblox's 200,000-character Source limit): AutoClickService.init runs it and turns the check off on any
-- problem, so a bad value never warns, kicks or bans anyone. Pure; shared.
-- validate(config, strings?) -> { string }: the problems as text (an empty list = valid). `config` = a table with
-- Config's Net (Net.AutoClick, Net.Remotes.SqueezeRequest), Squeeze and Grip sections (Config itself or a test's copy);
-- `strings` = the Strings module (its resolve); nil skips the text checks. Checks:
--   * enabled and banExcludeAltAccounts are booleans; enforce is "log", "warn" or "full" (review fix 2026-10-16);
--   * clientPressesPerSecond a whole number above the paid-squeeze cap (1 / Squeeze.cycleSeconds); with the paid cap's
--     own sends (Squeeze.bucketCapacity) on top at most Squeeze.floodPerSecond, and below
--     Net.Remotes.SqueezeRequest.rate (the client is never dropped or counted as abuse);
--   * maxPerSecond (review fix 2026-10-16: the fastest rate the rule judges; faster is the client ceiling's rhythm)
--     above the paid-squeeze cap and 1 / maxMeanGapSeconds (something is left to judge) and below
--     clientPressesPerSecond (a stream the client holds at its ceiling is never judged);
--   * blockIntervals a whole number >= 2; windowIntervals a whole multiple of it with at least MIN_BLOCKS blocks (the
--     spread of fewer block means is too noisy to trust);
--   * maxMeanGapSeconds in (0, Grip.Hold.repeatSeconds) (a held squeeze is never judged); maxBlockSpreadSeconds in
--     (0, MAX_SPREAD]; burstGapSeconds above maxMeanGapSeconds;
--   * penaltySeconds and memorySeconds > 0; banSeconds a whole number of hours, at least one (never -1: no permanent
--     ban; the texts name the hours);
--   * laterBanSeconds (batch B, owner 2026-10-17: the longer bans after the 1st) a list of whole numbers of days, each
--     longer than the one before (the first longer than banSeconds), never -1;
--   * the texts exist: reason.squeeze.autoClick (the warning), autoClick.kick and autoClick.ban (both name {hours}),
--     autoClick.kickNoBan (the kick when no ban can follow; review fix 2026-10-16), autoClick.banLonger (names {days}).

local MIN_BLOCKS = 10
local MAX_SPREAD = 0.01 -- seconds: anything above would call people machines
local SECONDS_PER_HOUR = 3600
local SECONDS_PER_DAY = 86400
local P = "Config.Net.AutoClick"
local ENFORCE = { log = true, warn = true, full = true }
local TEXTS: { { key: string, names: string? } } = {
	{ key = "reason.squeeze.autoClick" },
	{ key = "autoClick.kick", names = "{hours}" },
	{ key = "autoClick.kickNoBan" },
	{ key = "autoClick.ban", names = "{hours}" },
	{ key = "autoClick.banLonger", names = "{days}" },
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

return function(config: any, strings: any?): { string }
	local problems: { string } = {}
	local function expect(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end

	local net = if type(config) == "table" then config.Net else nil
	local c = if type(net) == "table" then net.AutoClick else nil
	if type(c) ~= "table" then
		table.insert(problems, `{P} is missing`)
		return problems
	end
	local squeeze = config.Squeeze
	local hold = if type(config.Grip) == "table" then config.Grip.Hold else nil
	local remote = if type(net.Remotes) == "table" then net.Remotes.SqueezeRequest else nil
	local paidPerSecond = if type(squeeze) == "table"
			and isNumber(squeeze.cycleSeconds)
			and squeeze.cycleSeconds > 0
		then 1 / squeeze.cycleSeconds
		else nil
	expect(paidPerSecond ~= nil, `{P}: Config.Squeeze.cycleSeconds must be a positive number to check against`)
	local paid = paidPerSecond or math.huge

	expect(type(c.enabled) == "boolean", `{P}.enabled must be a boolean (got {show(c.enabled)})`)
	expect(
		type(c.banExcludeAltAccounts) == "boolean",
		`{P}.banExcludeAltAccounts must be a boolean (got {show(c.banExcludeAltAccounts)})`
	)
	expect(
		type(c.enforce) == "string" and ENFORCE[c.enforce] == true,
		`{P}.enforce must be "log", "warn" or "full" (got {show(c.enforce)})`
	)

	local presses = c.clientPressesPerSecond
	local flood = if type(squeeze) == "table" then squeeze.floodPerSecond else nil
	local capacity = if type(squeeze) == "table" then squeeze.bucketCapacity else nil
	local remoteRate = if type(remote) == "table" then remote.rate else nil
	expect(
		isWhole(presses) and presses > paid,
		`{P}.clientPressesPerSecond must be a whole number above the paid-squeeze cap ({show(paidPerSecond)}/s; got {show(
			presses
		)})`
	)
	expect(
		isNumber(presses) and isNumber(flood) and isNumber(capacity) and presses + capacity <= flood,
		`{P}.clientPressesPerSecond ({show(presses)}) + Config.Squeeze.bucketCapacity ({show(capacity)}) must be at `
			.. `most Config.Squeeze.floodPerSecond ({show(flood)})`
	)
	expect(
		isNumber(presses) and isNumber(remoteRate) and presses < remoteRate,
		`{P}.clientPressesPerSecond ({show(presses)}) must be below Config.Net.Remotes.SqueezeRequest.rate ({show(
			remoteRate
		)})`
	)

	local maxPerSecond = c.maxPerSecond
	local slowest = if isNumber(c.maxMeanGapSeconds) and c.maxMeanGapSeconds > 0 then 1 / c.maxMeanGapSeconds else 0
	expect(
		isNumber(maxPerSecond)
			and maxPerSecond > paid
			and maxPerSecond > slowest
			and isNumber(presses)
			and maxPerSecond < presses,
		`{P}.maxPerSecond must be above the paid-squeeze cap and 1 / maxMeanGapSeconds and below `
			.. `clientPressesPerSecond (got {show(maxPerSecond)})`
	)

	local block, gaps = c.blockIntervals, c.windowIntervals
	expect(isWhole(block) and block >= 2, `{P}.blockIntervals must be a whole number >= 2 (got {show(block)})`)
	expect(
		isWhole(gaps) and isWhole(block) and block >= 2 and gaps % block == 0 and gaps // block >= MIN_BLOCKS,
		`{P}.windowIntervals must be a whole multiple of blockIntervals with at least {MIN_BLOCKS} blocks (got {show(
			gaps
		)})`
	)

	local meanGap = c.maxMeanGapSeconds
	local repeatSeconds = if type(hold) == "table" then hold.repeatSeconds else nil
	expect(
		isNumber(meanGap) and meanGap > 0 and isNumber(repeatSeconds) and meanGap < repeatSeconds,
		`{P}.maxMeanGapSeconds must be in (0, Config.Grip.Hold.repeatSeconds = {show(repeatSeconds)}) so a held `
			.. `squeeze is never judged (got {show(meanGap)})`
	)
	local spread = c.maxBlockSpreadSeconds
	expect(
		isNumber(spread) and spread > 0 and spread <= MAX_SPREAD,
		`{P}.maxBlockSpreadSeconds must be in (0, {MAX_SPREAD}] (got {show(spread)})`
	)
	expect(
		isNumber(c.burstGapSeconds) and isNumber(meanGap) and c.burstGapSeconds > meanGap,
		`{P}.burstGapSeconds must be above maxMeanGapSeconds (got {show(c.burstGapSeconds)})`
	)

	for _, field in { "penaltySeconds", "memorySeconds" } do
		local value = c[field]
		expect(isNumber(value) and value > 0, `{P}.{field} must be a positive number (got {show(value)})`)
	end
	local ban = c.banSeconds
	expect(
		isWhole(ban) and ban >= SECONDS_PER_HOUR and ban % SECONDS_PER_HOUR == 0,
		`{P}.banSeconds must be a whole number of hours, at least 3600 (got {show(ban)}; never -1)`
	)
	local later = c.laterBanSeconds
	local laterOk = type(later) == "table"
	local previous = if isNumber(ban) then ban else 0
	if laterOk then
		for _, seconds in later do
			if not (isWhole(seconds) and seconds % SECONDS_PER_DAY == 0 and seconds > previous) then
				laterOk = false
				break
			end
			previous = seconds
		end
	end
	expect(
		laterOk,
		`{P}.laterBanSeconds must be a list of whole days, each longer than the ban before (got {show(later)})`
	)

	if strings ~= nil and type(strings.resolve) == "function" then
		for _, entry in TEXTS do
			local text = strings.resolve(entry.key)
			expect(type(text) == "string" and text ~= "", `{P}: Strings has no text for {entry.key}`)
			local names = entry.names
			if names and type(text) == "string" then
				expect(string.find(text, names, 1, true) ~= nil, `{P}: Strings {entry.key} must name {names}`)
			end
		end
	end
	return problems
end
