--!strict
-- ValidateMatch_Test: unit tests for ReplicatedStorage.Shared.Config.ValidateMatch (the Config.Match part of
-- Config.validate, power-ups v1.1 2026-10-16). Server only (ServerStorage.UnitTest). Like Config_Test's broken-copy
-- cases, but without cloning Shared: the checker is built straight from the module with this file's own copies of
-- Config/init's check helpers and a deep copy of Config.Match, so a case breaks one value and reads the problems.
-- Contract: the live Config.Match has no problem; the power-up pickup reach (pickupRadiusStuds, pickupHeightStuds) must
-- be > 0; speed walkMultiplier, superJump jumpMultiplier and throwBoost speedMultiplier must be numbers >= 1; the super
-- jump plus the double jump must stay under Maps.boundsTop; rapidThrow cooldownMultiplier must be in [0, 1]. Match HUD
-- M2 (2026-10-16): Rewards must be a table with a boolean `enabled` (false in the live Config; rewardCoins is gone).

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

-- Config/init's check helpers, restated (they are private there).
local function isNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function show(value: unknown): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function add(problems: { string }, message: string)
	table.insert(problems, message)
end

local function expect(problems: { string }, ok: boolean, message: string)
	if not ok then
		add(problems, message)
	end
end

local HELPERS = {
	add = add,
	expect = expect,
	expectPositive = function(problems: { string }, path: string, value: unknown)
		expect(problems, isNumber(value) and (value :: number) > 0, `{path} must be a number > 0 (got {show(value)})`)
	end,
	expectNonNegative = function(problems: { string }, path: string, value: unknown)
		expect(problems, isNumber(value) and (value :: number) >= 0, `{path} must be a number >= 0 (got {show(value)})`)
	end,
	expectCount = function(problems: { string }, path: string, value: unknown, min: number)
		expect(
			problems,
			isNumber(value) and math.floor(value :: number) == value and (value :: number) >= min,
			`{path} must be a whole number >= {min} (got {show(value)})`
		)
	end,
	expectBetween = function(problems: { string }, path: string, value: unknown, min: number, max: number)
		expect(
			problems,
			isNumber(value) and (value :: number) >= min and (value :: number) <= max,
			`{path} must be a number in [{min}, {max}] (got {show(value)})`
		)
	end,
	expectBoolean = function(problems: { string }, path: string, value: unknown)
		expect(problems, type(value) == "boolean", `{path} must be a boolean (got {show(value)})`)
	end,
	expectText = function(problems: { string }, path: string, value: unknown)
		expect(problems, type(value) == "string" and value ~= "", `{path} must be a non-empty string`)
	end,
	expectCoins = function(problems: { string }, path: string, value: unknown)
		expect(
			problems,
			isNumber(value) and math.floor(value :: number) == value and (value :: number) >= 0,
			`{path} must be whole Coins >= 0 (got {show(value)})`
		)
	end,
	isNumber = isNumber,
	show = show,
	sortedKeys = function(tbl: any): { any }
		local keys = {}
		for key in tbl do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		return keys
	end,
}

local function containsText(list: { string }, text: string): boolean
	for _, entry in list do
		if string.find(entry, text, 1, true) ~= nil then
			return true
		end
	end
	return false
end

return function(t: Context)
	local expectT = t.expect
	local Config = t.requireShared("Config")
	local ValidateMatch = t.requireShared("Config/ValidateMatch")

	-- The problems of a Config.Match copy changed by `breakIt` (the palette check is skipped: no Art/Palette).
	local function problemsOf(breakIt: ((match: any) -> ())?): { string }
		local match = deepCopy(Config.Match)
		if breakIt then
			breakIt(match)
		end
		local problems: { string } = {}
		ValidateMatch(HELPERS, match, Config.Duel, function(): any
			return nil
		end)(problems)
		return problems
	end

	t.test("the live Config.Match has no problem", function()
		local problems = problemsOf(nil)
		if #problems > 0 then
			error(table.concat(problems, "\n"))
		end
	end)

	t.test("power-ups v1.1: the pickup reach must be > 0", function()
		local problems = problemsOf(function(match: any)
			match.PowerUps.pickupRadiusStuds = 0
			match.PowerUps.pickupHeightStuds = nil
		end)
		expectT.truthy(containsText(problems, "Config.Match.PowerUps.pickupRadiusStuds must be a number > 0"))
		expectT.truthy(containsText(problems, "Config.Match.PowerUps.pickupHeightStuds must be a number > 0"))
	end)

	t.test("power-ups v1.1: speed, super jump and throw boost multipliers must be numbers >= 1", function()
		local problems = problemsOf(function(match: any)
			match.PowerUps.kinds.speed.walkMultiplier = 0.5
			match.PowerUps.kinds.superJump.jumpMultiplier = nil
			match.PowerUps.kinds.throwBoost.speedMultiplier = "fast"
		end)
		expectT.truthy(containsText(problems, "kinds.speed.walkMultiplier must be a number >= 1"))
		expectT.truthy(containsText(problems, "kinds.superJump.jumpMultiplier must be a number >= 1"))
		expectT.truthy(containsText(problems, "kinds.throwBoost.speedMultiplier must be a number >= 1"))
		expectT.equal(#problemsOf(function(match: any)
			match.PowerUps.kinds.speed.walkMultiplier = 1
			match.PowerUps.kinds.throwBoost.speedMultiplier = 1
		end), 0) -- 1 (no boost) is allowed
	end)

	t.test("power-ups v1.1: the super jump with the double jump must stay under Maps.boundsTop", function()
		local problems = problemsOf(function(match: any)
			match.PowerUps.kinds.superJump.jumpMultiplier = 20 -- 7.2 × 20 + the double jump: far over 100
		end)
		expectT.truthy(containsText(problems, "must stay under Maps.boundsTop"))
		expectT.equal(#problemsOf(function(match: any)
			match.PowerUps.kinds.superJump.jumpMultiplier = 2
		end), 0)
	end)

	t.test("power-ups v1.1: the rapid throw's cooldown multiplier must be in [0, 1]", function()
		local over = problemsOf(function(match: any)
			match.PowerUps.kinds.rapidThrow.cooldownMultiplier = 1.5
		end)
		expectT.truthy(containsText(over, "kinds.rapidThrow.cooldownMultiplier must be a number in [0, 1]"))
		local under = problemsOf(function(match: any)
			match.PowerUps.kinds.rapidThrow.cooldownMultiplier = -0.1
		end)
		expectT.truthy(containsText(under, "kinds.rapidThrow.cooldownMultiplier"))
		expectT.equal(#problemsOf(function(match: any)
			match.PowerUps.kinds.rapidThrow.cooldownMultiplier = 0 -- no wait at all
		end), 0)
	end)

	t.test(
		"power-ups v1.1: a kind left out of the table skips its number check (the kinds check reports it)",
		function()
			local problems = problemsOf(function(match: any)
				match.PowerUps.kinds.superJump = nil
			end)
			expectT.truthy(containsText(problems, "Config.Match.PowerUps.kinds.superJump is missing"))
			expectT.falsy(containsText(problems, "jumpMultiplier"))
		end
	)

	t.test("match HUD M2: Rewards is a table with a boolean enabled, on in the live Config (owner)", function()
		expectT.equal(Config.Match.Rewards.enabled, true)
		expectT.equal(Config.Match.rewardCoins, nil) -- replaced by Rewards
		expectT.truthy(containsText(
			problemsOf(function(match: any)
				match.Rewards = nil
			end),
			"Config.Match.Rewards must be a table"
		))
		expectT.truthy(containsText(
			problemsOf(function(match: any)
				match.Rewards.enabled = "yes"
			end),
			"Config.Match.Rewards.enabled must be a boolean"
		))
		expectT.equal(#problemsOf(function(match: any)
			match.Rewards.enabled = true
		end), 0)
	end)
end
