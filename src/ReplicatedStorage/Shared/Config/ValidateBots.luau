--!strict
-- Config/ValidateBots: the checks of Config.Duel.Bots (the 1v1 practice bot, 2026-10-16). Apart from Config/init
-- (Roblox's 200,000-character Source limit): BotService.init runs it and keeps the bots off on any problem. Pure; shared.
-- validate(config, strings?) -> { string }: the problems as text (an empty list = valid). `config` = a table with
-- Config's Duel section (Duel.Bots, Duel.Matchmaking) (Config itself or a test's copy); `strings` = the Strings module
-- (its bot word lists); nil skips the name checks. Checks:
--   * enabled and useUltimate are booleans;
--   * every min / max pair is two numbers with 0 <= min <= max; fillDelayMaxSeconds is below
--     Config.Duel.Matchmaking.NoOpponentHintSeconds (the bot comes before the "no opponent" hint);
--   * checkSeconds and thinkSeconds are positive; checkSeconds is at most fillDelayMinSeconds;
--   * the chances and leadFraction are in [0, 1]; the stud distances and aimErrorPerStud are >= 0, aimErrorMaxStuds
--     >= aimErrorBaseStuds; moveCandidates a whole number >= 1; nameDigitsMin / Max whole numbers, 0 <= min <= max;
--   * Strings.bot.nameStarts / nameEnds are non-empty lists of letter-only words, and the longest name (longest start
--     + longest end + "_" + nameDigitsMax) fits a username's 20 characters.

local P = "Config.Duel.Bots"
local MAX_NAME = 20 -- a Roblox username's limit (the shortest, one letter each + one digit, is already 3)
local PAIRS = {
	{ "fillDelayMinSeconds", "fillDelayMaxSeconds" },
	{ "throwReactionMinSeconds", "throwReactionMaxSeconds" },
	{ "moveMinSeconds", "moveMaxSeconds" },
	{ "dodgeReactionMinSeconds", "dodgeReactionMaxSeconds" },
	{ "ultReactionMinSeconds", "ultReactionMaxSeconds" },
}
local CHANCES = { "nameUnderscoreChance", "leadFraction", "coverChance", "dodgeChance" }
local NON_NEGATIVE = { "aimErrorBaseStuds", "aimErrorPerStud", "aimErrorMaxStuds", "moveMinStuds", "edgeMarginStuds" }

local function isNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isWhole(v: unknown): boolean
	return isNumber(v) and math.floor(v :: number) == v
end

local function show(v: unknown): string
	return if type(v) == "string" then string.format("%q", v) else tostring(v)
end

-- The length of the longest word of a word list, or nil when it is not a non-empty list of letter-only words.
local function longestWord(list: any): number?
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local longest = 0
	for _, word in list do
		if type(word) ~= "string" or string.match(word, "^%a+$") == nil then
			return nil
		end
		longest = math.max(longest, #word)
	end
	return longest
end

return function(config: any, strings: any?): { string }
	local problems: { string } = {}
	local function expect(ok: boolean, message: string)
		if not ok then
			table.insert(problems, message)
		end
	end

	local duel = if type(config) == "table" then config.Duel else nil
	local c = if type(duel) == "table" then duel.Bots else nil
	if type(c) ~= "table" then
		table.insert(problems, `{P} is missing`)
		return problems
	end

	for _, field in { "enabled", "useUltimate" } do
		expect(type(c[field]) == "boolean", `{P}.{field} must be a boolean (got {show(c[field])})`)
	end
	for _, pair in PAIRS do
		local lo, hi = c[pair[1]], c[pair[2]]
		expect(
			isNumber(lo) and isNumber(hi) and lo >= 0 and lo <= hi,
			`{P}.{pair[1]} / {pair[2]} must be numbers with 0 <= min <= max (got {show(lo)} / {show(hi)})`
		)
	end
	local matchmaking = if type(duel.Matchmaking) == "table" then duel.Matchmaking else nil
	local hint = if matchmaking then matchmaking.NoOpponentHintSeconds else nil
	expect(
		isNumber(c.fillDelayMaxSeconds) and isNumber(hint) and c.fillDelayMaxSeconds < hint,
		`{P}.fillDelayMaxSeconds must be below Config.Duel.Matchmaking.NoOpponentHintSeconds ({show(hint)}; got {show(
			c.fillDelayMaxSeconds
		)})`
	)
	for _, field in { "checkSeconds", "thinkSeconds" } do
		expect(isNumber(c[field]) and c[field] > 0, `{P}.{field} must be a positive number (got {show(c[field])})`)
	end
	expect(
		isNumber(c.checkSeconds) and isNumber(c.fillDelayMinSeconds) and c.checkSeconds <= c.fillDelayMinSeconds,
		`{P}.checkSeconds must be at most fillDelayMinSeconds (got {show(c.checkSeconds)})`
	)
	for _, field in CHANCES do
		local v = c[field]
		expect(isNumber(v) and v >= 0 and v <= 1, `{P}.{field} must be in [0, 1] (got {show(v)})`)
	end
	for _, field in NON_NEGATIVE do
		local v = c[field]
		expect(isNumber(v) and v >= 0, `{P}.{field} must be a number >= 0 (got {show(v)})`)
	end
	expect(
		isNumber(c.aimErrorMaxStuds) and isNumber(c.aimErrorBaseStuds) and c.aimErrorMaxStuds >= c.aimErrorBaseStuds,
		`{P}.aimErrorMaxStuds must be at least aimErrorBaseStuds (got {show(c.aimErrorMaxStuds)})`
	)
	expect(
		isWhole(c.moveCandidates) and c.moveCandidates >= 1,
		`{P}.moveCandidates must be a whole number >= 1 (got {show(c.moveCandidates)})`
	)
	local digitsMin, digitsMax = c.nameDigitsMin, c.nameDigitsMax
	expect(
		isWhole(digitsMin) and isWhole(digitsMax) and digitsMin >= 0 and digitsMin <= digitsMax,
		`{P}.nameDigitsMin / nameDigitsMax must be whole numbers with 0 <= min <= max (got {show(digitsMin)} / {show(
			digitsMax
		)})`
	)

	if strings ~= nil then
		local words = if type(strings.bot) == "table" then strings.bot else {}
		local startLong = longestWord(words.nameStarts)
		local endLong = longestWord(words.nameEnds)
		expect(startLong ~= nil, `{P}: Strings.bot.nameStarts must be a non-empty list of letter-only words`)
		expect(endLong ~= nil, `{P}: Strings.bot.nameEnds must be a non-empty list of letter-only words`)
		if startLong and endLong and isWhole(digitsMax) then
			local longest = startLong + endLong + 1 + #tostring(digitsMax)
			expect(
				longest <= MAX_NAME,
				`{P}: the longest bot name ({longest} characters) must fit {MAX_NAME} (shorter words or fewer digits)`
			)
		end
	end
	return problems
end
