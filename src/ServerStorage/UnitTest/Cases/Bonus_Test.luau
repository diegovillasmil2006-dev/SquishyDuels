--!strict
-- Bonus_Test: Config.Bonus (required directly, so Config.validate does not see it) and the pure code rules of
-- ServerScriptService.Server.Logic.Codes (big job item 4, 2026-11-10: the group bonus and the redeem codes).
-- Contract:
--   * the group perk is modest (LihFolk vault: "a modest currency bonus"): a pen boost of at most a quarter, a gift no
--     bigger than the biggest code; membership checks a player asks for are spaced out;
--   * the code rules fit NetService's text limit; "group" and "code" are Coin reasons that double coins never doubles;
--   * every built-in code is a normal name that pays within the cap;
--   * typing is forgiven (capitals, spaces, dashes); anything that is not a text of the right length is no code;
--   * live codes: only clean entries count, a typo adds nothing, 0 closes a built-in code, live wins over built in;
--   * every text the feature shows exists.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local NET_TEXT_LIMIT = 64 -- NetService's MAX_STRING_LENGTH for a "string" argument

return function(t: Context)
	local expect = t.expect
	local Bonus = t.requireShared("Config/Bonus")
	local Config = t.requireShared("Config")
	local Events = t.requireShared("Config/Events")
	local Strings = t.requireShared("Strings")
	local Codes = t.requireServer("Logic/Codes")

	local GROUP, RULES = Bonus.Group, Bonus.Codes

	local function isWhole(n: any): boolean
		return type(n) == "number" and n == n and math.floor(n) == n
	end

	t.test("Config.Bonus: a modest group perk and code rules that fit the net limits", function()
		expect.truthy(isWhole(GROUP.id) and GROUP.id > 0)
		expect.truthy(GROUP.penBoost > 0 and GROUP.penBoost <= 0.25)
		expect.truthy(isWhole(GROUP.giftSqueezes) and GROUP.giftSqueezes >= 1 and GROUP.giftSqueezes <= RULES.maxSqueezes)
		expect.truthy(GROUP.recheckSeconds >= 5) -- each one is a web call to Roblox
		-- Item 5: the Roblox Plus perk is the same modest kind (never a fighting advantage: pen Coins only).
		local PLUS = Bonus.Plus
		expect.truthy(PLUS.penBoost > 0 and PLUS.penBoost <= 0.25)
		expect.truthy(isWhole(PLUS.giftSqueezes) and PLUS.giftSqueezes >= 1 and PLUS.giftSqueezes <= RULES.maxSqueezes)
		expect.truthy(isWhole(RULES.minLength) and RULES.minLength >= 1)
		expect.truthy(isWhole(RULES.maxLength) and RULES.maxLength >= RULES.minLength)
		expect.truthy(isWhole(RULES.maxTyped) and RULES.maxTyped >= RULES.maxLength and RULES.maxTyped <= NET_TEXT_LIMIT)
		expect.truthy(isWhole(RULES.maxSqueezes) and RULES.maxSqueezes >= 1)
		expect.truthy(isWhole(RULES.missLimit) and RULES.missLimit >= 2) -- one typo never locks
		expect.truthy(RULES.missWindowSeconds > 0 and RULES.lockSeconds > 0)
	end)

	t.test("'group', 'code' and 'plus' are Coin reasons, and double coins never doubles them", function()
		for _, reason in { "group", "code", "plus" } do
			expect.truthy(table.find(Config.Economy.CoinReasons, reason) ~= nil)
			expect.equal(table.find(Events.DoubleCoins.reasons, reason), nil)
		end
	end)

	t.test("every built-in code is a normal name that pays within the cap", function()
		local count = 0
		for code, squeezes in Codes.BUILT_IN do
			count += 1
			expect.equal(Codes.normalize(code), code)
			expect.truthy(isWhole(squeezes) and squeezes >= 1 and squeezes <= RULES.maxSqueezes)
			expect.equal(Codes.find(code, {}), squeezes)
		end
		expect.truthy(count >= 1)
	end)

	t.test("normalize forgives capitals, spaces and dashes, and refuses the rest", function()
		expect.equal(Codes.normalize("welcome"), "WELCOME")
		expect.equal(Codes.normalize("  Wel-Come 2026 "), "WELCOME2026")
		expect.equal(Codes.normalize(string.rep("a", RULES.minLength)), string.rep("A", RULES.minLength))
		expect.equal(Codes.normalize(string.rep("a", RULES.minLength - 1)), nil)
		expect.equal(Codes.normalize(string.rep("a", RULES.maxLength)), string.rep("A", RULES.maxLength))
		expect.equal(Codes.normalize(string.rep("a", RULES.maxLength + 1)), nil)
		expect.equal(Codes.normalize("   "), nil)
		expect.equal(Codes.normalize("!!!???"), nil)
		expect.equal(Codes.normalize(12345), nil)
		expect.equal(Codes.normalize(nil), nil)
		expect.equal(Codes.normalize({ "WELCOME" }), nil)
		-- What lies past maxTyped is cut before anything else: the B never counts.
		expect.equal(Codes.normalize("AAA" .. string.rep(" ", RULES.maxTyped) .. "B"), "AAA")
	end)

	t.test("readLive keeps only clean entries and names what it skipped", function()
		local live, skipped = Codes.readLive({
			party = 300,
			["XMAS 2026"] = 500,
			WELCOME = 0,
			BIG = RULES.maxSqueezes + 1,
			HALF = 1.5,
			NEG = -1,
			WORD = "100",
			NAN = 0 / 0,
			ab = 10,
			[5] = 100,
		})
		expect.deepEqual(live, { PARTY = 300, XMAS2026 = 500, WELCOME = 0 })
		table.sort(skipped)
		expect.deepEqual(skipped, { "5", "BIG", "HALF", "NAN", "NEG", "WORD", "ab" })
		-- No config, or one of the wrong type: no live codes.
		for _, junk in { 5, "PARTY=300", true, false } :: { any } do
			local none, names = Codes.readLive(junk)
			expect.deepEqual(none, {})
			expect.deepEqual(names, {})
		end
		expect.deepEqual(Codes.readLive(nil), {})
	end)

	t.test("find: live wins over built in, 0 closes a code, an unknown name is nothing", function()
		local code = next(Codes.BUILT_IN) :: string
		expect.equal(Codes.find(code, { [code] = 7 }), 7)
		expect.equal(Codes.find(code, { [code] = 0 }), nil)
		expect.equal(Codes.find("PARTY", { PARTY = 300 }), 300)
		expect.equal(Codes.find("PARTY", {}), nil)
		expect.equal(Codes.giftKey("PARTY"), "code:PARTY")
	end)

	t.test("every text of the group bonus and the codes exists", function()
		local keys = {
			"reason.code.invalid",
			"reason.code.used",
			"reason.code.wait",
			"reason.net.rateLimited", -- a group check asked for too soon
			"bonus.groupRow",
			"bonus.groupJoin",
			"bonus.groupJoined",
			"bonus.groupGift",
			"bonus.groupOn",
			"bonus.groupNotYet",
			"bonus.groupPending",
			"bonus.groupTip",
			"bonus.codeHint",
			"bonus.codeRedeem",
			"social.groupBoost",
			"bonus.plusGift", -- item 5
			"social.plusBoost",
			"social.boostTotal",
		}
		for _, key in keys do
			local text = Strings.resolve(key)
			if type(text) ~= "string" or text == "" then
				error("no text for " .. key)
			end
		end
		-- One answer for a wrong and a closed code: the text names neither.
		expect.equal(string.find(string.lower(Strings.reason.code.invalid), "expired", 1, true), nil)
	end)
end
