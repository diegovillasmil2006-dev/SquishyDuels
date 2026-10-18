--!strict
-- ValidateAutoClick_Test: unit tests for ReplicatedStorage.Shared.Config.ValidateAutoClick (auto-clicker check,
-- 2026-10-16). Server only (ServerStorage.UnitTest). Each case builds the checker's input from deep copies of the live
-- Config sections it reads (Net, Squeeze, Grip), breaks one value and reads the problems.
-- Contract: the live Config.Net.AutoClick with the live Strings has no problem; each of these is one problem naming its
-- field: enabled / banExcludeAltAccounts not booleans; enforce not "log" / "warn" / "full" (review fix 2026-10-16);
-- clientPressesPerSecond not whole, at or under the paid-squeeze cap, with Squeeze.bucketCapacity on top above
-- Squeeze.floodPerSecond, or at or above the SqueezeRequest rate; maxPerSecond at or under the paid cap or
-- 1 / maxMeanGapSeconds (nothing left to judge), or at or above clientPressesPerSecond; blockIntervals under 2;
-- windowIntervals not a whole
-- multiple of it or under 10 blocks; maxMeanGapSeconds 0 or at or above Grip.Hold.repeatSeconds; maxBlockSpreadSeconds
-- 0 or above 10 ms; burstGapSeconds not above maxMeanGapSeconds; penaltySeconds / memorySeconds not positive;
-- banSeconds -1 (permanent), under an hour or not whole hours; a missing warning, kick, kickNoBan or ban text, and a
-- kick or ban text without {hours}. A missing AutoClick table is one problem. Batch B (2026-10-17): laterBanSeconds
-- not a list, not whole days, -1, or not longer than the ban before; a banLonger text missing or without {days}.
-- P13v3 (owner 2026-10-18): speed not a table, speed.perSecond not a whole number >= 1, speed.seconds under 2 (one
-- burst would count) or not whole; a missing speed warning text (reason.squeeze.superFast, reason.highway.superFast).
-- Verification fix: no speed.maxPerRequest (the requests report seconds in a row, not presses).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

return function(t: Context)
	local expect = t.expect
	local validate = t.requireShared("Config/ValidateAutoClick")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")

	local function input(): any
		return { Net = deepCopy(Config.Net), Squeeze = deepCopy(Config.Squeeze), Grip = deepCopy(Config.Grip) }
	end

	-- The problems after `change(config)`; checks exactly one problem names `field`.
	local function oneProblem(field: string, change: (config: any) -> ())
		local config = input()
		change(config)
		local problems = validate(config, Strings)
		local naming = 0
		for _, problem in problems do
			if string.find(problem, field, 1, true) then
				naming += 1
			end
		end
		if #problems ~= 1 or naming ~= 1 then
			error(`{field}: expected one problem naming it, got {#problems}: {table.concat(problems, " | ")}`)
		end
	end

	t.test("the live Config.Net.AutoClick and Strings have no problem", function()
		expect.deepEqual(validate(Config, Strings), {})
		expect.deepEqual(validate(input(), Strings), {})
	end)

	t.test("the switches must be booleans", function()
		oneProblem("enabled", function(c: any)
			c.Net.AutoClick.enabled = "yes"
		end)
		oneProblem("banExcludeAltAccounts", function(c: any)
			c.Net.AutoClick.banExcludeAltAccounts = 1
		end)
		-- Review fix (2026-10-16): how far a catch goes. (Mixed bad values: `:: { any }`, small1 merge 2026-10-16.)
		for _, bad in { "strict", "", 1, false } :: { any } do
			oneProblem("enforce", function(c: any)
				c.Net.AutoClick.enforce = bad
			end)
		end
		for _, good in { "log", "warn", "full" } do
			local config = input()
			config.Net.AutoClick.enforce = good
			expect.deepEqual(validate(config, Strings), {})
		end
	end)

	t.test("clientPressesPerSecond: whole, above the paid cap, under the flood guard and the remote's rate", function()
		oneProblem("clientPressesPerSecond", function(c: any)
			c.Net.AutoClick.clientPressesPerSecond = 17.5
		end)
		oneProblem("Squeeze.floodPerSecond", function(c: any)
			-- With the paid cap's own sends on top, one rolling second could pass the flood guard.
			c.Net.AutoClick.clientPressesPerSecond = c.Squeeze.floodPerSecond - c.Squeeze.bucketCapacity + 1
		end)
		oneProblem("SqueezeRequest.rate", function(c: any)
			c.Net.Remotes.SqueezeRequest.rate = c.Net.AutoClick.clientPressesPerSecond
		end)
		-- At the paid cap: both it and maxPerSecond (which must sit between them) are wrong.
		local config = input()
		config.Net.AutoClick.clientPressesPerSecond = 2
		expect.equal(#validate(config, Strings), 2)
	end)

	t.test("maxPerSecond: above the paid cap and 1 / maxMeanGapSeconds, under clientPressesPerSecond", function()
		oneProblem("maxPerSecond", function(c: any)
			c.Net.AutoClick.maxPerSecond = 1 / c.Squeeze.cycleSeconds -- exactly the hold rhythm
		end)
		oneProblem("maxPerSecond", function(c: any)
			-- review fix (2026-10-16): at or under 1 / maxMeanGapSeconds no window would be left to judge
			c.Net.AutoClick.maxPerSecond = 1 / c.Net.AutoClick.maxMeanGapSeconds
		end)
		oneProblem("maxPerSecond", function(c: any)
			c.Net.AutoClick.maxPerSecond = c.Net.AutoClick.clientPressesPerSecond -- the ceiling's rhythm would be judged
		end)
	end)

	t.test("windowIntervals and blockIntervals: whole blocks, at least 10 of them", function()
		oneProblem("windowIntervals", function(c: any)
			c.Net.AutoClick.windowIntervals = c.Net.AutoClick.blockIntervals * 20 + 1
		end)
		oneProblem("windowIntervals", function(c: any)
			c.Net.AutoClick.windowIntervals = c.Net.AutoClick.blockIntervals * 9
		end)
		local config = input()
		config.Net.AutoClick.blockIntervals = 1
		local problems = validate(config, Strings)
		expect.truthy(#problems >= 1)
		expect.truthy(string.find(table.concat(problems, " | "), "blockIntervals", 1, true) ~= nil)
	end)

	t.test("rule B's gaps: a hold is never judged; the spread is small; a pause is longer than a judged gap", function()
		oneProblem("maxMeanGapSeconds", function(c: any)
			c.Net.AutoClick.maxMeanGapSeconds = c.Grip.Hold.repeatSeconds
		end)
		oneProblem("maxMeanGapSeconds", function(c: any)
			c.Net.AutoClick.maxMeanGapSeconds = 0
			c.Net.AutoClick.burstGapSeconds = 1
		end)
		oneProblem("maxBlockSpreadSeconds", function(c: any)
			c.Net.AutoClick.maxBlockSpreadSeconds = 0
		end)
		oneProblem("maxBlockSpreadSeconds", function(c: any)
			c.Net.AutoClick.maxBlockSpreadSeconds = 0.011
		end)
		oneProblem("burstGapSeconds", function(c: any)
			c.Net.AutoClick.burstGapSeconds = c.Net.AutoClick.maxMeanGapSeconds
		end)
	end)

	t.test("the steps: positive penalty and memory; a ban of whole hours, never permanent", function()
		oneProblem("penaltySeconds", function(c: any)
			c.Net.AutoClick.penaltySeconds = 0
		end)
		oneProblem("memorySeconds", function(c: any)
			c.Net.AutoClick.memorySeconds = -1
		end)
		for _, bad in { -1, 0, 1800, 5000, 86400.5 } do
			oneProblem("banSeconds", function(c: any)
				c.Net.AutoClick.banSeconds = bad
			end)
		end
		-- Batch B (2026-10-17): the longer bans after the 1st (whole days, each longer than the one before).
		local bads: { any } = { "7 days", { -1 }, { 90000 }, { 86400 }, { 604800, 604800 }, { 2592000, 604800 } }
		for _, bad in bads do
			oneProblem("laterBanSeconds", function(c: any)
				c.Net.AutoClick.laterBanSeconds = bad
			end)
		end
		for _, good in { {}, { 172800 }, { 604800, 2592000, 7776000 } } do
			local config = input()
			config.Net.AutoClick.laterBanSeconds = good
			expect.deepEqual(validate(config, Strings), {})
		end
	end)

	t.test("the texts: the warning, the kick and the ban exist; the kick and ban name {hours}", function()
		local function withTexts(texts: { [string]: string? }): { string }
			local fake = {
				resolve = function(key: string): string?
					if texts[key] ~= nil then
						return texts[key]
					end
					return Strings.resolve(key)
				end,
			}
			return validate(input(), fake)
		end
		local missing = withTexts({ ["autoClick.kick"] = "" })
		expect.equal(#missing, 2) -- empty, and so no {hours}
		local noHours = withTexts({ ["autoClick.ban"] = "Banned for a day." })
		expect.equal(#noHours, 1)
		expect.truthy(string.find(noHours[1], "autoClick.ban", 1, true) ~= nil)
		local noWarning = withTexts({ ["reason.squeeze.autoClick"] = "" })
		expect.equal(#noWarning, 1)
		local noKickNoBan = withTexts({ ["autoClick.kickNoBan"] = "" }) -- review fix (2026-10-16)
		expect.equal(#noKickNoBan, 1)
		expect.truthy(string.find(noKickNoBan[1], "autoClick.kickNoBan", 1, true) ~= nil)
		local noDays = withTexts({ ["autoClick.banLonger"] = "Banned for {hours} hours." }) -- batch B (2026-10-17)
		expect.equal(#noDays, 1)
		expect.truthy(string.find(noDays[1], "autoClick.banLonger", 1, true) ~= nil)
		expect.equal(#withTexts({ ["autoClick.banLonger"] = "" }), 2) -- empty, and so no {days}
		expect.deepEqual(validate(input(), nil), {}) -- no Strings: the text checks are skipped
	end)

	t.test("p13v3: the speed rule: a whole limit, at least 2 seconds in a row", function()
		local function speed(perSecond: any, seconds: any): (c: any) -> ()
			return function(c: any)
				c.Net.AutoClick.speed = { perSecond = perSecond, seconds = seconds }
			end
		end
		for _, bad in { 20.5, 0, "20" } :: { any } do
			oneProblem("speed.perSecond", speed(bad, 3))
		end
		for _, bad in { 1, 2.5, 0 / 0 } :: { any } do
			oneProblem("speed.seconds", speed(20, bad))
		end
		oneProblem("speed", function(c: any)
			c.Net.AutoClick.speed = "fast"
		end)
		local config = input()
		config.Net.AutoClick.speed = { perSecond = 30, seconds = 2 }
		expect.deepEqual(validate(config, Strings), {})
	end)

	t.test("p13v3: the speed rule's warnings exist", function()
		for _, key in { "reason.squeeze.superFast", "reason.highway.superFast" } do
			local problems = validate(input(), {
				resolve = function(asked: string): string?
					return if asked == key then "" else Strings.resolve(asked)
				end,
			})
			expect.equal(#problems, 1)
			expect.truthy(string.find(problems[1], key, 1, true) ~= nil)
		end
	end)

	t.test("a missing AutoClick table is one problem", function()
		local config = input()
		config.Net.AutoClick = nil
		local problems = validate(config, Strings)
		expect.equal(#problems, 1)
		expect.truthy(string.find(problems[1], "missing", 1, true) ~= nil)
	end)
end
