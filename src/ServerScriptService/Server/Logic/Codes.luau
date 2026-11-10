--!strict
-- Codes (server only, pure). Big job item 4 (2026-11-10): the redeem codes' list and rules (Config.Bonus.Codes;
-- LihFolk vault "Codes Redemption System End to End": the list never leaves the server, typing is forgiven, rewards
-- are sized as if every player redeems every code). Services/CodeService redeems them.
-- A code pays Coins counted in squeezes (squeezes x the player's squeeze value at that moment, like the daily reward).
--   BUILT_IN            the codes that ship with the game: { CODE = squeezes }.
--   normalize(typed)    what a player typed as a code name: cut to maxTyped, capitals, letters and digits only; nil
--                       when it is not a text or not minLength..maxLength long after that.
--   readLive(value)     the live codes (the experience config `codes`, a JSON object { "CODE": squeezes }, edited in
--                       Creator Hub > Configs with no publish) as a clean table, plus the names it skipped. A name is
--                       normalized like typed text; the value must be a whole number in [0, maxSqueezes]; anything
--                       else is skipped (a typo adds nothing). 0 closes a built-in code of that name.
--   find(code, live)    the squeezes a normalized code pays now, or nil (not a code, or closed). Live wins over built in.
--   giftKey(code)       the code's flag in profile.gifts ("code:<CODE>": used once per account).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RULES = require(ReplicatedStorage.Shared.Config.Bonus).Codes

local KEY_PREFIX = "code:"

local Codes = {}

Codes.BUILT_IN = table.freeze({
	WELCOME = 250,
	DIJAY = 500,
}) :: { [string]: number }

function Codes.normalize(typed: unknown): string?
	if type(typed) ~= "string" then
		return nil
	end
	local code = string.gsub(string.upper(string.sub(typed, 1, RULES.maxTyped)), "[^A-Z0-9]", "")
	if #code < RULES.minLength or #code > RULES.maxLength then
		return nil
	end
	return code
end

function Codes.readLive(value: unknown): ({ [string]: number }, { string })
	local live: { [string]: number } = {}
	local skipped: { string } = {}
	if type(value) ~= "table" then
		return live, skipped
	end
	for name, squeezes in value :: { [any]: any } do
		local code = Codes.normalize(name)
		local whole = type(squeezes) == "number" and squeezes == squeezes and math.floor(squeezes) == squeezes
		if code ~= nil and whole and squeezes >= 0 and squeezes <= RULES.maxSqueezes then
			live[code] = squeezes
		else
			table.insert(skipped, tostring(name))
		end
	end
	return live, skipped
end

function Codes.find(code: string, live: { [string]: number }): number?
	local squeezes = live[code]
	if squeezes == nil then
		squeezes = Codes.BUILT_IN[code]
	end
	if squeezes == nil or squeezes <= 0 then
		return nil
	end
	return squeezes
end

function Codes.giftKey(code: string): string
	return KEY_PREFIX .. code
end

return Codes
