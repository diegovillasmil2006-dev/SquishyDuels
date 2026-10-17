--!strict
-- Config/ValidateWeeklyQuests: the checks of the weekly quests (owner 2026-10-17): Config.Economy.WeeklyQuests
-- (Config/WeeklyQuests) and QuestDefs.weekly(). Apart from Config/init (Roblox's 200,000-character Source limit):
-- QuestService.init runs it and keeps the weekly quests off on any problem. Pure; shared.
-- validate(config, questDefs, strings?) -> { string }: the problems as text (an empty list = valid). `config` = a table
-- with Config's Economy section (Config itself or a test's copy); `questDefs` = the QuestDefs module (its weekly() and
-- list()); `strings` = the Strings module (its resolve); nil skips the text checks. Checks:
--   * enabled is a boolean; weekOffsetSeconds a whole number in [0, 604800) (one week);
--   * at least one weekly quest; each: an id matching ^weekly_[a-z_]+$ with at most 24 characters, listed once and not
--     the id of a daily template or starter task (list(); QuestDefs.get would return only one of them); kind "weekly";
--     a category GO and the picture know (squeeze, duel, practice); a progress rule that needs no squishy (squeeze,
--     duelFinish, duelWin, practiceHit); needsSquishy false; exactly one variant with a whole goal and reward >= 1;
--   * the textPair's .one and .many texts exist (one problem per quest).

local P = "Config.Economy.WeeklyQuests"
local Q = "QuestDefs.weekly"
local SECONDS_PER_WEEK = 7 * 86400
local ID_PATTERN = "^weekly_[a-z_]+$"
local ID_MAX_LENGTH = 24
local CATEGORIES = { squeeze = true, duel = true, practice = true }
local COUNTS = { squeeze = true, duelFinish = true, duelWin = true, practiceHit = true }

local function isWhole(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and math.floor(v) == v
end

local function show(v: unknown): string
	return if type(v) == "string" then string.format("%q", v) else tostring(v)
end

return function(config: any, questDefs: any, strings: any?): { string }
	local problems: { string } = {}
	local function expect(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end

	local economy = if type(config) == "table" then config.Economy else nil
	local c = if type(economy) == "table" then economy.WeeklyQuests else nil
	if type(c) ~= "table" then
		table.insert(problems, `{P} is missing`)
		return problems
	end
	expect(type(c.enabled) == "boolean", `{P}.enabled must be a boolean (got {show(c.enabled)})`)
	local offset = c.weekOffsetSeconds
	expect(
		isWhole(offset) and offset >= 0 and offset < SECONDS_PER_WEEK,
		`{P}.weekOffsetSeconds must be a whole number in [0, {SECONDS_PER_WEEK}) (got {show(offset)})`
	)

	if type(questDefs) ~= "table" or type(questDefs.weekly) ~= "function" or type(questDefs.list) ~= "function" then
		table.insert(problems, `{Q}() is missing`)
		return problems
	end
	local list = questDefs.weekly()
	if type(list) ~= "table" or #list == 0 then
		table.insert(problems, `{Q}() lists no weekly quest`)
		return problems
	end
	local seen: { [string]: boolean } = {}
	local others = questDefs.list()
	for _, other in if type(others) == "table" then others else {} do
		if type(other) == "table" and type(other.id) == "string" then
			seen[other.id] = true -- a daily template or starter task
		end
	end
	for index, def in list do
		if type(def) ~= "table" or type(def.id) ~= "string" then
			table.insert(problems, `{Q}()[{index}] has no string id`)
			continue
		end
		local path = `QuestDefs.{def.id}`
		if seen[def.id] then
			table.insert(problems, `{path} is listed twice (weekly, daily and starter ids are one namespace)`)
			continue
		end
		seen[def.id] = true
		expect(
			#def.id <= ID_MAX_LENGTH and string.match(def.id, ID_PATTERN) ~= nil,
			`{path} must match {ID_PATTERN} with at most {ID_MAX_LENGTH} characters`
		)
		expect(def.kind == "weekly", `{path}.kind must be "weekly" (got {show(def.kind)})`)
		expect(
			type(def.category) == "string" and CATEGORIES[def.category] == true,
			`{path}.category must be squeeze, duel or practice (got {show(def.category)})`
		)
		expect(
			type(def.counts) == "string" and COUNTS[def.counts] == true,
			`{path}.counts must be squeeze, duelFinish, duelWin or practiceHit (got {show(def.counts)})`
		)
		expect(def.needsSquishy == false, `{path}.needsSquishy must be false (a weekly quest names no squishy)`)
		local variants = def.variants
		if type(variants) ~= "table" or #variants ~= 1 or type(variants[1]) ~= "table" then
			table.insert(problems, `{path}.variants must hold exactly one goal/reward pair`)
		else
			local variant = variants[1]
			expect(isWhole(variant.goal) and variant.goal >= 1, `{path} goal must be a whole number >= 1`)
			expect(isWhole(variant.reward) and variant.reward >= 1, `{path} reward must be a whole number >= 1`)
		end
		if strings ~= nil and type(strings.resolve) == "function" then
			local missing: { string } = {}
			for _, form in { "one", "many" } do
				local key = `{tostring(def.textPair)}.{form}`
				local ok, text = pcall(strings.resolve, key)
				if not (ok and type(text) == "string" and text ~= "") then
					table.insert(missing, key)
				end
			end
			expect(#missing == 0, `{path}.textPair needs the Strings texts {table.concat(missing, ", ")}`)
		end
	end
	return problems
end
