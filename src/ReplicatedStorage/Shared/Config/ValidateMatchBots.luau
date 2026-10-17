--!strict
-- Config/ValidateMatchBots: the checks of Config.Match.Bots (the FFA / TDM match bots, 2026-10-17). Apart from
-- Config/init (Roblox's 200,000-character Source limit): MatchBotService.init runs it (and Config/ValidateBots, whose
-- aim, reaction and name numbers the match bots share) and keeps the match bots off on any problem. Pure; shared.
-- validate(config) -> { string }: the problems as text (an empty list = valid). `config` = a table with Config's Match
-- section (Match.Bots) (Config itself or a test's copy). Checks:
--   * enabled is a boolean;
--   * thinkSeconds, rigRetrySeconds, targetSeconds, stuckSeconds, pathStepStuds, targetMaxStuds, strafeStuds and
--     roamStuds are positive numbers;
--   * moveMinSeconds / moveMaxSeconds and keepMinStuds / keepMaxStuds are two numbers with 0 <= min <= max;
--   * rangeFraction is in (0, 1]; coverChance, huntChance, padChance and dodgeChance are in [0, 1];
--   * moveMinStuds, arrivedStuds, edgeMarginStuds, climbStuds, stuckStuds, padSeekStuds, stormLookaheadSeconds,
--     stormMarginStuds and dodgeRangeStuds are numbers >= 0; huntJitterDegrees and dodgeAngleDegrees are in [0, 90];
--   * moveCandidates is a whole number >= 1; strafeStuds and roamStuds are at least moveMinStuds (else no goal fits).

local P = "Config.Match.Bots"
local POSITIVE = {
	"thinkSeconds",
	"rigRetrySeconds",
	"targetSeconds",
	"stuckSeconds",
	"pathStepStuds",
	"targetMaxStuds",
	"strafeStuds",
	"roamStuds",
}
local PAIRS = { { "moveMinSeconds", "moveMaxSeconds" }, { "keepMinStuds", "keepMaxStuds" } }
local CHANCES = { "coverChance", "huntChance", "padChance", "dodgeChance" }
local NON_NEGATIVE = {
	"moveMinStuds",
	"arrivedStuds",
	"edgeMarginStuds",
	"climbStuds",
	"stuckStuds",
	"padSeekStuds",
	"stormLookaheadSeconds",
	"stormMarginStuds",
	"dodgeRangeStuds",
}

local function isNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
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

	local match = if type(config) == "table" then config.Match else nil
	local c = if type(match) == "table" then match.Bots else nil
	if type(c) ~= "table" then
		table.insert(problems, `{P} is missing`)
		return problems
	end

	expect(type(c.enabled) == "boolean", `{P}.enabled must be a boolean (got {show(c.enabled)})`)
	for _, field in POSITIVE do
		local v = c[field]
		expect(isNumber(v) and v > 0, `{P}.{field} must be a positive number (got {show(v)})`)
	end
	for _, pair in PAIRS do
		local lo, hi = c[pair[1]], c[pair[2]]
		expect(
			isNumber(lo) and isNumber(hi) and lo >= 0 and lo <= hi,
			`{P}.{pair[1]} / {pair[2]} must be numbers with 0 <= min <= max (got {show(lo)} / {show(hi)})`
		)
	end
	expect(
		isNumber(c.rangeFraction) and c.rangeFraction > 0 and c.rangeFraction <= 1,
		`{P}.rangeFraction must be in (0, 1] (got {show(c.rangeFraction)})`
	)
	for _, field in CHANCES do
		local v = c[field]
		expect(isNumber(v) and v >= 0 and v <= 1, `{P}.{field} must be in [0, 1] (got {show(v)})`)
	end
	for _, field in NON_NEGATIVE do
		local v = c[field]
		expect(isNumber(v) and v >= 0, `{P}.{field} must be a number >= 0 (got {show(v)})`)
	end
	for _, field in { "huntJitterDegrees", "dodgeAngleDegrees" } do
		local v = c[field]
		expect(isNumber(v) and v >= 0 and v <= 90, `{P}.{field} must be in [0, 90] (got {show(v)})`)
	end
	expect(
		isNumber(c.moveCandidates) and c.moveCandidates >= 1 and math.floor(c.moveCandidates) == c.moveCandidates,
		`{P}.moveCandidates must be a whole number >= 1 (got {show(c.moveCandidates)})`
	)
	for _, field in { "strafeStuds", "roamStuds" } do
		expect(
			isNumber(c[field]) and isNumber(c.moveMinStuds) and c[field] >= c.moveMinStuds,
			`{P}.{field} must be at least moveMinStuds (got {show(c[field])})`
		)
	end
	return problems
end
