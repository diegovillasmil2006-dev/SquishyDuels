--!strict
-- ValidateBots_Test: unit tests for ReplicatedStorage.Shared.Config.ValidateBots (the 1v1 practice bot, 2026-10-16).
-- Server only (ServerStorage.UnitTest). Pure: broken copies of Config.Duel.Bots and of the Strings word lists.
-- Contract (Config/ValidateBots header): the shipped Config and Strings are valid; each broken value is reported by
-- name; a missing section is one problem; names that would not fit 20 characters, or words that are not letters only,
-- are reported; nil strings skips the name checks.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local validate = t.requireShared("Config/ValidateBots")

	-- A Config-shaped copy with Duel.Bots changed.
	local function broken(changes: { [string]: any }): any
		local bots = table.clone(Config.Duel.Bots)
		for key, value in changes do
			bots[key] = value
		end
		return { Duel = { Bots = bots, Matchmaking = Config.Duel.Matchmaking } }
	end

	local function mentions(problems: { string }, text: string): boolean
		for _, problem in problems do
			if string.find(problem, text, 1, true) then
				return true
			end
		end
		return false
	end

	t.test("the shipped Config and Strings are valid", function()
		expect.deepEqual(validate(Config, Strings), {})
		expect.deepEqual(validate(Config, nil), {})
	end)

	t.test("a missing section is one problem", function()
		local problems = validate({ Duel = {} }, Strings)
		expect.equal(#problems, 1)
		expect.truthy(mentions(problems, "Config.Duel.Bots is missing"))
		expect.equal(#validate(nil, nil), 1)
	end)

	t.test("each broken value is reported by name", function()
		local cases: { { changes: { [string]: any }, field: string } } = {
			{ changes = { enabled = "yes" }, field = "enabled" },
			{ changes = { useUltimate = 1 }, field = "useUltimate" },
			{ changes = { fillDelayMinSeconds = 11 }, field = "fillDelayMinSeconds" },
			{ changes = { fillDelayMaxSeconds = 25 }, field = "NoOpponentHintSeconds" },
			{ changes = { throwReactionMinSeconds = -0.1 }, field = "throwReactionMinSeconds" },
			{ changes = { moveMaxSeconds = 0.1 }, field = "moveMinSeconds" },
			{ changes = { dodgeReactionMaxSeconds = 0 / 0 }, field = "dodgeReactionMinSeconds" },
			{ changes = { ultReactionMinSeconds = 3 }, field = "ultReactionMinSeconds" },
			{ changes = { checkSeconds = 0 }, field = "checkSeconds" },
			{ changes = { checkSeconds = 9 }, field = "checkSeconds must be at most" },
			{ changes = { thinkSeconds = -1 }, field = "thinkSeconds" },
			{ changes = { coverChance = 1.5 }, field = "coverChance" },
			{ changes = { dodgeChance = -0.2 }, field = "dodgeChance" },
			{ changes = { leadFraction = 2 }, field = "leadFraction" },
			{ changes = { nameUnderscoreChance = "half" }, field = "nameUnderscoreChance" },
			{ changes = { aimErrorPerStud = -1 }, field = "aimErrorPerStud" },
			{ changes = { aimErrorMaxStuds = 1 }, field = "aimErrorMaxStuds must be at least" },
			{ changes = { moveCandidates = 0 }, field = "moveCandidates" },
			{ changes = { moveCandidates = 2.5 }, field = "moveCandidates" },
			{ changes = { edgeMarginStuds = math.huge }, field = "edgeMarginStuds" },
			{ changes = { nameDigitsMin = 50, nameDigitsMax = 5 }, field = "nameDigitsMin" },
			{ changes = { nameDigitsMax = 1.5 }, field = "nameDigitsMin" },
		}
		for _, case in cases do
			local problems = validate(broken(case.changes), Strings)
			if not mentions(problems, case.field) then
				error(`no problem names {case.field}: {table.concat(problems, " | ")}`)
			end
		end
	end)

	t.test("bot names that would not fit, and words that are not letters, are reported", function()
		local long = validate(broken({ nameDigitsMax = 999999999 }), Strings)
		expect.truthy(mentions(long, "longest bot name"))
		local words = { bot = { nameStarts = { "Squish", "Bad Word" }, nameEnds = { "Fan" } } }
		expect.truthy(mentions(validate(Config, words), "nameStarts"))
		local digits = { bot = { nameStarts = { "Squish" }, nameEnds = { "Fan2" } } }
		expect.truthy(mentions(validate(Config, digits), "nameEnds"))
		local empty = { bot = { nameStarts = {}, nameEnds = { "Fan" } } }
		expect.truthy(mentions(validate(Config, empty), "nameStarts"))
		expect.truthy(mentions(validate(Config, {}), "nameStarts"))
	end)
end
