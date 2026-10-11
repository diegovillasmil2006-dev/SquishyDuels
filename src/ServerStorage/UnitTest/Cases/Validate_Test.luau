--!strict
-- Validate_Test: unit tests for ReplicatedStorage.Shared.Util.Validate. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §2.7, §2.8): squishyId/boxId/bundleKey/passKey `^[a-z_]+$` and <= 24 chars; requestId is a
-- GenerateGUID(false) GUID (36 chars, hex groups 8-4-4-4-12); AckReveal also accepts `^daily:%d+$`;
-- questId `^q%d+_%d$` or `^starter_[a-z]+$`, <= 24 chars; stationId `^squeeze_%d%d$`; numbers are finite
-- (`x == x` and |x| < 1e6); server timestamps (`clientTime` = GetServerTimeNow(), §5.6) are finite with their own,
-- larger bound; SetSettings takes <= 4 known keys, integer volumes clamped 0-100, booleans.
-- Every helper returns the (typed) value when the input is valid and nil otherwise.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local GUID_UPPER = "0F8FAD5B-D9CB-469F-A165-70867728950E"
local GUID_LOWER = "0f8fad5b-d9cb-469f-a165-70867728950e"

local function show(value: unknown): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

return function(t: Context)
	local Validate = t.requireShared("Util/Validate")
	local expect = t.expect

	-- Fails unless Validate[fnName] returns each value unchanged. (nil cannot sit in a list: see the last case.)
	local function expectAccepted(fnName: string, values: { any })
		for _, value in values do
			local result = Validate[fnName](value)
			if result ~= value then
				error(string.format("Validate.%s(%s) should accept it, got %s", fnName, show(value), show(result)), 2)
			end
		end
	end

	-- Fails unless Validate[fnName] returns nil for each value.
	local function expectRejected(fnName: string, values: { any })
		for _, value in values do
			local result = Validate[fnName](value)
			if result ~= nil then
				error(string.format("Validate.%s(%s) should reject it, got %s", fnName, show(value), show(result)), 2)
			end
		end
	end

	-- Simple ids ----------------------------------------------------------------------------------------------

	-- Every catalog squishy id is a valid squishyId.
	t.test("squishyId accepts the lower-case snake_case catalog ids", function()
		expectAccepted(
			"squishyId",
			{ "kitty_bread", "toast", "banana", "butter", "chocolate", "bird", "donut", "dragon" }
		)
	end)

	-- The length limit is inclusive: 24 characters pass, 25 fail.
	t.test("squishyId accepts 24 characters and rejects 25", function()
		expectAccepted("squishyId", { string.rep("a", 24) })
		expectRejected("squishyId", { string.rep("a", 25) })
	end)

	-- Anything outside [a-z_] is rejected, including a trailing newline and the empty string.
	t.test("squishyId rejects upper case, digits, spaces, hyphens, newlines and empty strings", function()
		expectRejected("squishyId", { "Kitty_bread", "toast1", "kitty bread", "kitty-bread", "dragon\n", "" })
	end)

	-- Non-string input is rejected without throwing.
	t.test("squishyId rejects non-string values", function()
		expectRejected("squishyId", { 5, true, {}, Vector3.new(1, 2, 3) })
	end)

	-- boxId, bundleKey and passKey use the same rule as squishyId.
	t.test("boxId, bundleKey and passKey follow the same id rule", function()
		for _, fnName in { "boxId", "bundleKey", "passKey" } do
			expectAccepted(fnName, { "treat", "coins_small", string.rep("z", 24) })
			expectRejected(fnName, { "Treat", "box1", "coins-small", string.rep("z", 25), "", 7 })
		end
	end)

	-- requestId ---------------------------------------------------------------------------------------------

	-- GenerateGUID(false) output is upper-case hex; %x also matches lower case.
	t.test("requestId accepts a GUID without braces, in upper or lower case", function()
		expectAccepted("requestId", { GUID_UPPER, GUID_LOWER })
	end)

	-- GenerateGUID(true) adds braces (38 characters), which is not the requested format.
	t.test("requestId rejects the braced GUID format", function()
		expectRejected("requestId", { "{" .. GUID_UPPER .. "}" })
	end)

	-- 36 characters with the wrong group lengths must not pass.
	t.test("requestId rejects 36-character strings whose groups are not 8-4-4-4-12", function()
		expectRejected("requestId", {
			"0F8FAD5BD-9CB-469F-A165-70867728950E", -- 9-3-4-4-12
			"0F8FAD5B-D9CB-469FA-165-70867728950E", -- 8-4-5-3-12
			"0F8FAD5BD9CB469FA16570867728950E1234", -- no dashes
		})
	end)

	-- Non-hex characters, wrong total lengths and non-strings are rejected.
	t.test("requestId rejects non-hex characters, wrong lengths and non-strings", function()
		expectRejected("requestId", {
			"0F8FAD5G-D9CB-469F-A165-70867728950E", -- G is not hex
			string.sub(GUID_UPPER, 1, 35),
			GUID_UPPER .. "0",
			"",
			123,
		})
	end)

	-- The daily reveal key is only valid for AckReveal, not as a requestId.
	t.test("requestId rejects the daily reveal key", function()
		expectRejected("requestId", { "daily:20367" })
	end)

	-- AckReveal ---------------------------------------------------------------------------------------------

	-- AckReveal takes either a box request GUID or "daily:<dayIndex>".
	t.test("ackRevealId accepts a GUID and a daily key", function()
		expectAccepted("ackRevealId", { GUID_UPPER, "daily:20367", "daily:0" })
	end)

	-- The daily form needs the exact prefix and at least one digit, nothing else.
	t.test("ackRevealId rejects malformed daily keys", function()
		expectRejected(
			"ackRevealId",
			{ "daily:", "daily:-1", "daily:1a", "Daily:1", "weekly:1", " daily:1", "daily:1 " }
		)
	end)

	-- questId -----------------------------------------------------------------------------------------------

	-- Daily quests are q<day>_<slot digit>; starter tasks are starter_<letters>.
	t.test("questId accepts daily quest ids and starter task ids", function()
		expectAccepted("questId", { "q20367_1", "q0_0", "starter_squeeze", "starter_box" })
	end)

	-- The slot is a single digit and the starter name is lower-case letters only.
	t.test("questId rejects two-digit slots, missing parts and wrong case", function()
		expectRejected("questId", {
			"q20367_12",
			"q_1",
			"q20367_",
			"Q1_1",
			"q1-1",
			"starter_",
			"starter_Box",
			"starter_box1",
			"starter__x",
		})
	end)

	-- Both forms are limited to 24 characters (inclusive).
	t.test("questId accepts 24 characters and rejects 25", function()
		expectAccepted("questId", { "starter_" .. string.rep("a", 16), "q" .. string.rep("1", 21) .. "_1" })
		expectRejected("questId", { "starter_" .. string.rep("a", 17), "q" .. string.rep("1", 22) .. "_1" })
	end)

	-- stationId ---------------------------------------------------------------------------------------------

	-- Station ids are squeeze_ followed by exactly two digits.
	t.test("stationId accepts squeeze_ plus two digits", function()
		expectAccepted("stationId", { "squeeze_01", "squeeze_06", "squeeze_99" })
	end)

	-- One digit, three digits, letters, wrong case, padding and non-strings are rejected.
	t.test("stationId rejects every other form", function()
		expectRejected("stationId", { "squeeze_1", "squeeze_001", "squeeze_ab", "Squeeze_01", "squeeze_01 ", "" })
	end)

	-- Numbers -----------------------------------------------------------------------------------------------

	-- Finite values strictly inside +-1e6 pass unchanged.
	t.test("number accepts finite values below 1e6 in magnitude", function()
		expectAccepted("number", { 0, -3.5, 999999, -999999 })
	end)

	-- NaN fails x == x; infinities and |x| >= 1e6 fail the bound; strings are not numbers.
	t.test("number rejects NaN, infinities, |x| >= 1e6 and non-numbers", function()
		expectRejected("number", { 0 / 0, math.huge, -math.huge, 1e6, -1e6, "5" })
	end)

	-- clientTime is workspace:GetServerTimeNow(): Unix seconds (~1.79e9 in Oct 2026), far above the 1e6 number bound.
	t.test("serverTime accepts real GetServerTimeNow() timestamps that number rejects", function()
		local timestamps = { 1791000000.25, 1791000000, 2e9, 0 }
		expectAccepted("serverTime", timestamps)
		expectRejected("number", { 1791000000.25 })
	end)

	-- Timestamps must still be finite numbers.
	t.test("serverTime rejects NaN, infinities, absurd magnitudes and non-numbers", function()
		expectRejected("serverTime", { 0 / 0, math.huge, -math.huge, 1e300, -1e300, "1791000000", true })
	end)

	-- The remote contract must declare clientTime as a timestamp, or handlers would check it with `number` (1e6).
	t.test("Remotes.SPEC declares every clientTime argument as serverTime", function()
		local Remotes = t.requireShared("Remotes")
		for _, remoteName in { "ThrowRequest", "UltimateRequest" } do
			local declared: unknown = nil
			for _, spec in Remotes.SPEC[remoteName].args do
				if spec.name == "clientTime" then
					declared = spec.type
				end
			end
			if declared ~= "serverTime" then
				error(string.format("%s.clientTime is declared as %s, not serverTime", remoteName, show(declared)))
			end
		end
	end)

	-- A vector is finite only when all three components are.
	t.test("vector3 rejects a Vector3 with a non-finite component", function()
		expectAccepted("vector3", { Vector3.new(1, 2, 3) })
		expectRejected("vector3", { Vector3.new(0 / 0, 0, 0), Vector3.new(0, math.huge, 0), Vector3.new(0, 0, 2e6) })
	end)

	-- SetSettings payload -----------------------------------------------------------------------------------

	-- Volumes are clamped to 0-100 and booleans are kept as sent.
	t.test("settings clamps volumes to 0-100 and keeps the booleans", function()
		local patch = Validate.settings({ music = 150, sfx = -5, cameraShake = false, showTips = true })
		expect.deepEqual(patch, { music = 100, sfx = 0, cameraShake = false, showTips = true })
	end)

	-- Only the four known keys with the right value types are accepted; anything else rejects the payload.
	t.test("settings rejects unknown keys, wrong value types and non-tables", function()
		expectRejected("settings", {
			{ volume = 50 },
			{ music = "50" },
			{ music = 50.5 },
			{ sfx = 0 / 0 },
			{ cameraShake = 1 },
			{ showTips = "yes" },
			"music=50",
		})
	end)

	-- First-person spec 2026-10-10 §3.8: the "First-person duels" switch is session only; a patch carrying it is refused
	-- whole, so the client must never send it (SettingsFormat.KEYS leaves it out).
	t.test("settings refuses a patch carrying the session-only firstPerson switch", function()
		expectRejected("settings", { { firstPerson = true }, { cameraShake = false, firstPerson = false } })
	end)

	-- Missing arguments ------------------------------------------------------------------------------------

	-- A missing argument (nil) never passes any helper and never throws.
	t.test("every helper rejects nil", function()
		for _, fnName in
			{
				"squishyId",
				"boxId",
				"bundleKey",
				"passKey",
				"requestId",
				"ackRevealId",
				"questId",
				"stationId",
				"number",
				"serverTime",
				"vector3",
				"settings",
			}
		do
			local result = Validate[fnName](nil)
			if result ~= nil then
				error(string.format("Validate.%s(nil) should reject it, got %s", fnName, show(result)))
			end
		end
	end)
end
