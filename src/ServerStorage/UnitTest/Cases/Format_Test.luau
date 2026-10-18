--!strict
-- Format_Test: unit tests for ReplicatedStorage.Shared.Util.Format.coins. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §2.2, §9.13, §11.6; spec 2026-10-12 §12): grouped below 100,000, one-decimal K below 1,000,000,
-- two-decimal M below 1B, then 3 significant digits with B, T and Qa ("1.23B", "12.3B", "123B", "45.6T", "2.85Qa")
-- and the whole Qa, grouped, from 1,000Qa; decimals are cut, never rounded up; negatives keep their sign and a
-- non-finite value reads "0".
-- Pens3 phase 13 (the throw): power(x), a float (G110's style: "4.7", "12", "1.4K", "25K", "330M", "1.6Oc", "24No"):
-- under 10 one decimal (a whole number without it), under 1,000 whole, then K M B T Qa Qi Sx Sp Oc No Dc Ud with one
-- decimal under 10 of the unit and whole above, the whole Ud grouped past 1,000Ud; cut, never rounded up (a float a
-- hair under its unit's whole number still shows it); 0 or below and non-finite read "0". distance(studs): whole studs,
-- cut and grouped ("8,500"); below 0 and non-finite read "0".

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local Format = t.requireShared("Util/Format")
	local Config = t.requireShared("Config")
	local expect = t.expect

	-- Fails at the first { amount, text } pair that Format.coins does not show exactly.
	local function expectTexts(cases: { { any } })
		for _, case in cases do
			local got = Format.coins(case[1])
			if got ~= case[2] then
				error(string.format("Format.coins(%s) = %q, want %q", tostring(case[1]), got, case[2]), 2)
			end
		end
	end

	t.test("below 1B: grouped, then one-decimal K, then two-decimal M", function()
		expectTexts({
			{ 0, "0" },
			{ 999, "999" },
			{ 12_345, "12,345" },
			{ 99_999, "99,999" },
			{ 100_000, "100.0K" },
			{ 123_456, "123.4K" },
			{ 1_000_000, "1.00M" },
			{ 1_234_567, "1.23M" },
		})
	end)

	t.test("B, T and Qa show 3 significant digits (the spec's examples)", function()
		expectTexts({
			{ 1_000_000_000, "1.00B" },
			{ 1_234_567_890, "1.23B" },
			{ 12_345_678_901, "12.3B" },
			{ 123_456_789_012, "123B" },
			{ 1_000_000_000_000, "1.00T" },
			{ 45_678_901_234_567, "45.6T" },
			{ 1_000_000_000_000_000, "1.00Qa" },
			{ 2_859_369_232_492_232, "2.85Qa" },
		})
	end)

	t.test("decimals are cut, never rounded up to the next digit or unit", function()
		expectTexts({
			{ 999_999, "999.9K" },
			{ 999_999_999, "999.99M" },
			{ 1_999_999_999, "1.99B" },
			{ 9_999_999_999, "9.99B" },
			{ 99_999_999_999, "99.9B" },
			{ 999_999_999_999, "999B" },
			{ 999_999_999_999_999, "999T" },
			{ 8_999_999_999_999_999, "8.99Qa" },
		})
	end)

	t.test("the Coin cap reads 9.00Qa; from 1,000Qa the whole Qa is grouped", function()
		expect.equal(Format.coins(Config.Economy.maxCoins), "9.00Qa")
		expectTexts({ { 1e18, "1,000Qa" }, { 1.234e18, "1,234Qa" } })
	end)

	-- Pens3 phase 13 -----------------------------------------------------------------------------------------------

	t.test("power: G110's style, cut, from 2 up to Ud", function()
		local cases: { { any } } = {
			{ 2, "2" },
			{ 2 * 1.1 ^ 9, "4.7" }, -- Grip Lv 10
			{ 9.99, "9.9" },
			{ 2 * 1.1 ^ 19, "12" }, -- Lv 20
			{ 999.9, "999" },
			{ 1000, "1.0K" },
			{ 1384.6, "1.3K" },
			{ 2 * 1.1 ^ 99, "25K" }, -- Lv 100
			{ 14_000, "14K" },
			{ 330e6, "330M" },
			{ 16e12, "16T" },
			{ 1.2e18, "1.2Qi" },
			{ 62e21, "62Sx" },
			{ 1.6e27, "1.6Oc" },
			{ 2.4e31, "24No" },
			{ 5e33, "5.0Dc" },
			{ 7.5e36, "7.5Ud" },
			{ 1.234e39, "1,234Ud" },
			{ 0, "0" },
			{ -3, "0" },
			{ 0 / 0, "0" },
			{ math.huge, "0" },
		}
		for _, case in cases do
			local got = Format.power(case[1])
			if got ~= case[2] then
				error(string.format("Format.power(%s) = %q, want %q", tostring(case[1]), got, case[2]))
			end
		end
	end)

	t.test("distance: whole studs, cut and grouped", function()
		expect.equal(Format.distance(8500), "8,500")
		expect.equal(Format.distance(21.8), "21")
		expect.equal(Format.distance(0), "0")
		expect.equal(Format.distance(123_456), "123,456")
		expect.equal(Format.distance(-5), "0")
		expect.equal(Format.distance(0 / 0), "0")
	end)

	t.test("fractions drop, negatives keep their sign, non-finite values read 0", function()
		expectTexts({
			{ 1_234_567_890.9, "1.23B" },
			{ -1_234_567_890, "-1.23B" },
			{ -12_345, "-12,345" },
			{ -0.5, "0" },
			{ 0 / 0, "0" },
			{ math.huge, "0" },
			{ -math.huge, "0" },
		})
	end)
end
