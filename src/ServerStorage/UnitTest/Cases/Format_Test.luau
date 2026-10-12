--!strict
-- Format_Test: unit tests for ReplicatedStorage.Shared.Util.Format.coins. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §2.2, §9.13, §11.6; spec 2026-10-12 §12): grouped below 100,000, one-decimal K below 1,000,000,
-- two-decimal M below 1B, then 3 significant digits with B, T and Qa ("1.23B", "12.3B", "123B", "45.6T", "2.85Qa")
-- and the whole Qa, grouped, from 1,000Qa; decimals are cut, never rounded up; negatives keep their sign and a
-- non-finite value reads "0".

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
