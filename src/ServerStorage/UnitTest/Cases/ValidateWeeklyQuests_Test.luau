--!strict
-- ValidateWeeklyQuests_Test: unit tests for ReplicatedStorage.Shared.Config.ValidateWeeklyQuests and the TimeUtil week
-- helpers (weekly quests, 2026-10-17). Server only (ServerStorage.UnitTest). Each case builds the checker's input from
-- deep copies of the live Config.Economy and QuestDefs.weekly(), breaks one value and reads the problems.
-- Contract: the live config, weekly quests and Strings have no problem; each of these is one problem naming its field:
-- enabled not a boolean; weekOffsetSeconds negative, fractional or a week or more; a weekly quest with a bad id, a
-- second copy of an id or a daily template's id, kind not "weekly", an unknown category, a rule that needs a squishy,
-- needsSquishy true, two variants, a goal or reward under 1 or fractional, or a missing text (both forms). No
-- weekly quest at all, or no WeeklyQuests table, is one problem. TimeUtil.utcWeek / secondsUntilNextUtcWeek: weeks
-- start on Monday 00:00 UTC with the live offset, and the reset is in (0, 604800].

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
	local validate = t.requireShared("Config/ValidateWeeklyQuests")
	local Config = t.requireShared("Config")
	local QuestDefs = t.requireShared("QuestDefs")
	local Strings = t.requireShared("Strings")
	local TimeUtil = t.requireShared("Util/TimeUtil")

	-- A fake QuestDefs: copies of the weekly quests, and the live daily templates and starter tasks.
	local function fakeDefs(list: { any }): any
		return {
			weekly = function(): { any }
				return list
			end,
			list = QuestDefs.list,
		}
	end

	-- The problems after `change(config, list)`; checks exactly one problem names `field`.
	local function oneProblem(field: string, change: (config: any, list: { any }) -> ())
		local config = { Economy = deepCopy(Config.Economy) }
		local list = deepCopy(QuestDefs.weekly())
		change(config, list)
		local problems = validate(config, fakeDefs(list), Strings)
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

	t.test("the live Config.Economy.WeeklyQuests, QuestDefs.weekly() and Strings have no problem", function()
		expect.deepEqual(validate(Config, QuestDefs, Strings), {})
		expect.equal(Config.Economy.WeeklyQuests.weekOffsetSeconds, Config.Social.Board.weekOffsetSeconds)
		expect.equal(#QuestDefs.weekly(), 4)
		expect.equal(#QuestDefs.list(), #QuestDefs.daily() + #QuestDefs.starter()) -- weekly stays out of list()
	end)

	t.test("the switch and the week's start", function()
		oneProblem("enabled", function(c: any)
			c.Economy.WeeklyQuests.enabled = "yes"
		end)
		for _, bad in { -1, 0.5, 7 * 86400, 0 / 0 } do
			oneProblem("weekOffsetSeconds", function(c: any)
				c.Economy.WeeklyQuests.weekOffsetSeconds = bad
			end)
		end
		local missing = validate({ Economy = {} }, QuestDefs, Strings)
		expect.equal(#missing, 1)
	end)

	t.test("each weekly quest's id, kind, category, rule, variant and text", function()
		oneProblem("must match", function(_c: any, list: { any })
			list[1].id = "Weekly-Squeeze"
		end)
		oneProblem("listed twice", function(_c: any, list: { any })
			list[2] = deepCopy(list[1])
		end)
		oneProblem("listed twice", function(_c: any, list: { any })
			list[1].id = QuestDefs.daily()[1].id -- a daily template's id: QuestDefs.get finds only one of them
		end)
		oneProblem(".kind", function(_c: any, list: { any })
			list[1].kind = "daily"
		end)
		oneProblem(".category", function(_c: any, list: { any })
			list[1].category = "boxes"
		end)
		oneProblem(".counts", function(_c: any, list: { any })
			list[1].counts = "squeezeWith"
		end)
		oneProblem(".needsSquishy", function(_c: any, list: { any })
			list[1].needsSquishy = true
		end)
		oneProblem(".variants", function(_c: any, list: { any })
			table.insert(list[1].variants, { goal = 5, reward = 5 })
		end)
		oneProblem("goal", function(_c: any, list: { any })
			list[1].variants[1].goal = 0
		end)
		oneProblem("reward", function(_c: any, list: { any })
			list[1].variants[1].reward = 2.5
		end)
		oneProblem(".textPair", function(_c: any, list: { any })
			list[1].textPair = "quest.template.nope"
		end)
	end)

	t.test("no weekly quest at all is one problem", function()
		local problems = validate(Config, fakeDefs({}), Strings)
		expect.equal(#problems, 1)
	end)

	t.test("TimeUtil weeks start on Monday 00:00 UTC; the reset is in (0, 604800]", function()
		local offset = Config.Economy.WeeklyQuests.weekOffsetSeconds
		local monday = 20003 * 86400 -- day 20003 is a Monday ((20003 - 4) % 7 == 0)
		expect.equal(TimeUtil.utcWeek(monday, offset), TimeUtil.utcWeek(monday - 1, offset) + 1)
		expect.equal(TimeUtil.utcWeek(monday + 7 * 86400 - 1, offset), TimeUtil.utcWeek(monday, offset))
		expect.equal(TimeUtil.secondsUntilNextUtcWeek(monday, offset), 7 * 86400)
		expect.equal(TimeUtil.secondsUntilNextUtcWeek(monday - 1, offset), 1)
		expect.equal(TimeUtil.secondsUntilNextUtcWeek(monday - 0.25, offset), 0.25)
		-- 1970-01-01 (a Thursday) is in week -1; Monday 1970-01-05 starts week 0.
		expect.equal(TimeUtil.utcWeek(0, offset), -1)
		expect.equal(TimeUtil.utcWeek(4 * 86400, offset), 0)
	end)
end
