--!strict
-- ValidateMatchBots_Test: unit tests for ReplicatedStorage.Shared.Config.ValidateMatchBots (the FFA / TDM match bots,
-- 2026-10-17). Server only (ServerStorage.UnitTest). Pure: broken copies of Config.Match.Bots.
-- Contract (Config/ValidateMatchBots header): the shipped Config is valid; a missing section is one problem; each
-- broken value is reported by name.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local validate = t.requireShared("Config/ValidateMatchBots")

	-- A Config-shaped copy with Match.Bots changed.
	local function broken(changes: { [string]: any }): any
		local bots = table.clone(Config.Match.Bots)
		for key, value in changes do
			bots[key] = value
		end
		return { Match = { Bots = bots } }
	end

	local function mentions(problems: { string }, text: string): boolean
		for _, problem in problems do
			if string.find(problem, text, 1, true) then
				return true
			end
		end
		return false
	end

	t.test("the shipped Config is valid", function()
		expect.deepEqual(validate(Config), {})
	end)

	t.test("a missing section is one problem", function()
		local problems = validate({ Match = {} })
		expect.equal(#problems, 1)
		expect.truthy(mentions(problems, "Config.Match.Bots is missing"))
		expect.equal(#validate(nil), 1)
	end)

	t.test("each broken value is reported by name", function()
		local cases: { { changes: { [string]: any }, field: string } } = {
			{ changes = { enabled = "yes" }, field = "enabled" },
			{ changes = { thinkSeconds = 0 }, field = "thinkSeconds" },
			{ changes = { rigRetrySeconds = -1 }, field = "rigRetrySeconds" },
			{ changes = { targetSeconds = 0 / 0 }, field = "targetSeconds" },
			{ changes = { stuckSeconds = math.huge }, field = "stuckSeconds" },
			{ changes = { pathStepStuds = 0 }, field = "pathStepStuds" },
			{ changes = { targetMaxStuds = "far" }, field = "targetMaxStuds" },
			{ changes = { moveMinSeconds = 3, moveMaxSeconds = 2 }, field = "moveMinSeconds" },
			{ changes = { keepMinStuds = -1 }, field = "keepMinStuds" },
			{ changes = { keepMaxStuds = 5 }, field = "keepMinStuds" },
			{ changes = { rangeFraction = 0 }, field = "rangeFraction" },
			{ changes = { rangeFraction = 1.2 }, field = "rangeFraction" },
			{ changes = { coverChance = 1.5 }, field = "coverChance" },
			{ changes = { huntChance = -0.1 }, field = "huntChance" },
			{ changes = { padChance = "often" }, field = "padChance" },
			{ changes = { dodgeChance = 2 }, field = "dodgeChance" },
			{ changes = { climbStuds = -1 }, field = "climbStuds" },
			{ changes = { padSeekStuds = -5 }, field = "padSeekStuds" },
			{ changes = { stormMarginStuds = 0 / 0 }, field = "stormMarginStuds" },
			{ changes = { dodgeAngleDegrees = 120 }, field = "dodgeAngleDegrees" },
			{ changes = { huntJitterDegrees = -1 }, field = "huntJitterDegrees" },
			{ changes = { arrivedStuds = "near" }, field = "arrivedStuds" },
			{ changes = { moveCandidates = 0 }, field = "moveCandidates" },
			{ changes = { moveCandidates = 2.5 }, field = "moveCandidates" },
			{ changes = { strafeStuds = 2 }, field = "strafeStuds must be at least" },
			{ changes = { roamStuds = 3 }, field = "roamStuds must be at least" },
		}
		for _, case in cases do
			local problems = validate(broken(case.changes))
			if not mentions(problems, case.field) then
				error(`no problem names {case.field}: {table.concat(problems, " | ")}`)
			end
		end
	end)
end
