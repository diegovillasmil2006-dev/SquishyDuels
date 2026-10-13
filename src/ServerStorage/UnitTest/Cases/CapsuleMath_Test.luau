--!strict
-- CapsuleMath_Test: unit tests for ReplicatedStorage.Shared.CapsuleMath. Server only (ServerStorage.UnitTest).
-- Contract (spec 2026-10-12 §3-§9, §15): 10 tiers × 10 levels; CP is 10 at Lv1 and rises every level (920,525,589 at
-- Lv100) and matches each tier's first and last value of §4, with the tier's interval and Grip gate; the prices match
-- every §5 row, the base price rises every level and an evolve (10 -> 11 ... 90 -> 91) costs exactly 2× the rounded
-- base; one capsule Lv1 -> 100 costs about 11.5Qa and the biggest price fits the 9 Qa Coin cap; slots cost 0 / 2,500 /
-- 80,000 / 1,500,000; squishy power is 1 / 4 / 16 / 64; the squeeze value is the best capsule's (10 for a new player);
-- rewardCoins = squeezes × value, stopping at 9 Qa; anything that is not a level or a slot gives nil.
-- Phase 3: capsuleCoins = squishy power × CP; an own squeeze's Grip is the CP of the highest capsule level; two prices
-- in a row always differ (so a retried upgrade is refused, never charged twice); the CapsuleUpgrade / CapsuleUnlock
-- checks in GripMath.upgradeDecision's order.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- Spec §5: the price from L to L + 1.
local SPEC_PRICES: { [number]: number } = {
	[1] = 1_000,
	[2] = 1_300,
	[5] = 3_200,
	[9] = 10_000,
	[10] = 28_000,
	[11] = 19_000,
	[20] = 520_000,
	[30] = 9_800_000,
	[40] = 182_000_000,
	[50] = 3_400_000_000,
	[60] = 64_000_000_000,
	[70] = 1_180_000_000_000,
	[80] = 22_000_000_000_000,
	[90] = 420_000_000_000_000,
	[95] = 890_000_000_000_000,
	[99] = 2_900_000_000_000_000,
}

-- Spec §4, one row per tier: CP at its first and last level (a Common's Coins per squeeze; the spec shows them
-- rounded, e.g. 1.39K and 921M), the seconds between squeezes and the Grip Level it needs.
local SPEC_TIERS = {
	{ first = 10, last = 30, seconds = 4.0, grip = 0 },
	{ first = 68, last = 204, seconds = 3.5, grip = 10 },
	{ first = 461, last = 1_385, seconds = 3.1, grip = 20 },
	{ first = 3_129, last = 9_400, seconds = 2.7, grip = 30 },
	{ first = 21_245, last = 63_821, seconds = 2.4, grip = 40 },
	{ first = 144_235, last = 433_289, seconds = 2.1, grip = 50 },
	{ first = 979_234, last = 2_941_661, seconds = 1.9, grip = 60 },
	{ first = 6_648_153, last = 19_971_331, seconds = 1.6, grip = 70 },
	{ first = 45_135_208, last = 135_588_056, seconds = 1.4, grip = 80 },
	{ first = 306_429_007, last = 920_525_589, seconds = 1.3, grip = 90 },
}

return function(t: Context)
	local CapsuleMath = t.requireShared("CapsuleMath")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local MAX_COINS = Config.Economy.maxCoins

	t.test("CP is 10 at Lv1 and rises every level, up to 920,525,589 at Lv100", function()
		expect.equal(CapsuleMath.power(1), 10)
		for level = 2, 100 do
			if not (CapsuleMath.power(level) > CapsuleMath.power(level - 1)) then
				error(`CP does not rise from Lv {level - 1} to Lv {level}`)
			end
		end
		expect.equal(CapsuleMath.power(100), 920_525_589)
	end)

	t.test("10 tiers of 10 levels: CP, interval and Grip gate match spec §4", function()
		for tier, row in SPEC_TIERS do
			local first, last = tier * 10 - 9, tier * 10
			expect.equal(CapsuleMath.power(first), row.first)
			expect.equal(CapsuleMath.power(last), row.last)
			for level = first, last do
				expect.equal(CapsuleMath.tier(level), tier)
				expect.equal(CapsuleMath.seconds(level), row.seconds)
				expect.equal(CapsuleMath.gripLevelFor(level), row.grip)
			end
		end
	end)

	t.test("the prices match every spec §5 row; nothing to buy at Lv100", function()
		for level, price in SPEC_PRICES do
			expect.equal(CapsuleMath.price(level), price)
		end
		expect.equal(CapsuleMath.price(100), nil)
	end)

	t.test("the base price rises every level and an evolve costs exactly 2x the rounded base", function()
		local function base(level: number): number
			local price = CapsuleMath.price(level)
			return if level % 10 == 0 then price / 2 else price
		end
		for level = 1, 99 do
			-- 1,000 × 1.34^(L - 1) rounded to 2 significant digits, worked out a second way (printf's rounding).
			local rounded = tonumber(string.format("%.1e", 1000 * 1.34 ^ (level - 1)))
			expect.equal(base(level), rounded)
			if level > 1 and not (base(level) > base(level - 1)) then
				error(`the base price does not rise from Lv {level - 1} to Lv {level}`)
			end
		end
	end)

	t.test("one capsule from Lv1 to Lv100 costs about 11.5Qa; its biggest price fits the Coin cap", function()
		local total, biggest = 0, 0
		for level = 1, 99 do
			local price = CapsuleMath.price(level)
			total += price
			biggest = math.max(biggest, price)
		end
		expect.near(total / 1e15, 11.5, 0.05) -- spec §5: 11.5Qa for one capsule, 46.1Qa for all 4
		expect.equal(biggest, CapsuleMath.price(99))
		expect.truthy(biggest <= MAX_COINS)
	end)

	t.test("slot 1 is free, then 2,500 / 80,000 / 1,500,000 in order", function()
		expect.equal(CapsuleMath.slotPrice(1), 0)
		expect.equal(CapsuleMath.slotPrice(2), 2_500)
		expect.equal(CapsuleMath.slotPrice(3), 80_000)
		expect.equal(CapsuleMath.slotPrice(4), 1_500_000)
		local bads: { any } = { 0, 5, 1.5, -1, 0 / 0, "2" }
		for _, bad in bads do
			expect.equal(CapsuleMath.slotPrice(bad), nil)
		end
	end)

	t.test("anything that is not a level 1-100 has no tier, interval, power, price or gate", function()
		local bads: { any } = { 0, 101, 1.5, -10, 0 / 0, math.huge, "5" }
		for _, level in bads do
			expect.equal(CapsuleMath.tier(level), nil)
			expect.equal(CapsuleMath.seconds(level), nil)
			expect.equal(CapsuleMath.power(level), nil)
			expect.equal(CapsuleMath.price(level), nil)
			expect.equal(CapsuleMath.gripLevelFor(level), nil)
		end
	end)

	t.test("squishy power is 1 / 4 / 16 / 64 by rarity, 0 for an unknown id", function()
		expect.equal(CapsuleMath.squishyPower("toast"), 1)
		expect.equal(CapsuleMath.squishyPower("butter"), 4)
		expect.equal(CapsuleMath.squishyPower("bird"), 16)
		expect.equal(CapsuleMath.squishyPower("dragon"), 64)
		expect.equal(CapsuleMath.squishyPower("unicorn"), 0)
	end)

	-- Phase 3: squeezeValue reads a profile's capsules ({slots, list}), so callers pass profile.capsules as it is.
	t.test("the squeeze value is the best capsule's; a new player's squeeze is 10", function()
		expect.equal(CapsuleMath.squeezeValue(nil), 10)
		expect.equal(CapsuleMath.squeezeValue({}), 10)
		expect.equal(CapsuleMath.squeezeValue({ slots = 1, list = {} }), 10)
		expect.equal(CapsuleMath.squeezeValue({ slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } }), 10)
		-- Lv21 Toast: 461 × 1; Lv5 Dragon: 16 × 64 = 1,024 (a weaker capsule with a rarer squishy can win).
		local two = { { level = 21, squishyId = "toast" }, { level = 5, squishyId = "dragon" } }
		expect.equal(CapsuleMath.squeezeValue({ slots = 2, list = two }), 1_024)
		table.insert(two, { level = 100, squishyId = "bird" })
		expect.equal(CapsuleMath.squeezeValue({ slots = 3, list = two }), 920_525_589 * 16)
		-- Entries without a level or a known squishy count for nothing.
		local junk: { any } = {
			{ level = 0, squishyId = "dragon" },
			{ level = 101, squishyId = "dragon" },
			{ level = 5.5, squishyId = "dragon" },
			{ level = 50 },
			{ level = 50, squishyId = "unicorn" },
			"dragon",
		}
		expect.equal(CapsuleMath.squeezeValue({ slots = 4, list = junk }), 10)
		-- The list itself is not a capsules state: it counts as none (callers pass profile.capsules).
		expect.equal(CapsuleMath.squeezeValue({ { level = 5, squishyId = "dragon" } } :: any), 10)
	end)

	t.test("capsuleCoins = squishy power × CP; 0 for an unknown squishy or level", function()
		expect.equal(CapsuleMath.capsuleCoins("kitty_bread", 1), 10)
		expect.equal(CapsuleMath.capsuleCoins("butter", 11), 4 * 68)
		expect.equal(CapsuleMath.capsuleCoins("dragon", 100), 64 * 920_525_589) -- spec §4: 58.9B at Royal Lv100
		expect.equal(CapsuleMath.capsuleCoins("unicorn", 5), 0)
		expect.equal(CapsuleMath.capsuleCoins(nil, 5), 0)
		expect.equal(CapsuleMath.capsuleCoins("toast", 0), 0)
		expect.equal(CapsuleMath.capsuleCoins("toast", 101), 0)
	end)

	t.test("an own squeeze's Grip is the CP of the highest capsule level (an empty capsule counts too)", function()
		expect.equal(CapsuleMath.squeezeGrip(nil), 10)
		expect.equal(CapsuleMath.squeezeGrip({ slots = 1, list = {} }), 10)
		local list: { any } =
			{ { level = 4, squishyId = "dragon" }, { level = 23 }, { level = 11, squishyId = "toast" } }
		expect.equal(CapsuleMath.squeezeGrip({ slots = 3, list = list }), CapsuleMath.power(23))
		local junk: { any } = { { level = 0 }, { level = 101 }, { level = 7.5 }, "x" }
		expect.equal(CapsuleMath.squeezeGrip({ slots = 4, list = junk }), 10)
	end)

	t.test("two prices in a row always differ, so a retried upgrade can never match the next price", function()
		for level = 2, 99 do
			if CapsuleMath.price(level) == CapsuleMath.price(level - 1) then
				error(`Lv {level - 1} and Lv {level} cost the same`)
			end
		end
	end)

	-- One capsules state: `levels` per unlocked slot (squishies do not matter to the checks).
	local function state(levels: { number }): any
		local list = {}
		for i, level in levels do
			list[i] = { level = level }
		end
		return { slots = #levels, list = list }
	end

	t.test("upgradeDecision: buy at the next level's price; refusals in GripMath.upgradeDecision's order", function()
		local price3 = CapsuleMath.price(3)
		expect.deepEqual(CapsuleMath.upgradeDecision(state({ 3 }), 1, price3, 1), { kind = "buy", cost = price3 })
		-- 2: the argument range comes first, whatever the state.
		local bad: { { any } } = { { 0, price3 }, { 5, price3 }, { 1.5, price3 }, { 1, -1 }, { 1, 2.5 }, { 1, 0 / 0 } }
		for _, args in bad do
			expect.equal(CapsuleMath.upgradeDecision(state({ 100 }), args[1], args[2], 1).reason, "net.invalid")
		end
		-- A slot that is not unlocked; a capsule at the top level.
		expect.equal(CapsuleMath.upgradeDecision(state({ 3 }), 2, price3, 1).reason, "capsule.locked")
		expect.equal(CapsuleMath.upgradeDecision(state({ 3, 100 }), 2, 0, 100).reason, "capsule.maxLevel")
		-- 6: Lv 10 -> 11 is Jelly (Grip Lv 10); 7: the price is only compared.
		local evolve = CapsuleMath.price(10)
		local locked = CapsuleMath.upgradeDecision(state({ 10 }), 1, evolve, 9)
		expect.deepEqual(locked, { kind = "reject", reason = "capsule.gripLocked", cost = evolve })
		expect.equal(CapsuleMath.upgradeDecision(state({ 10 }), 1, evolve, 10).kind, "buy")
		expect.equal(CapsuleMath.upgradeDecision(state({ 10 }), 1, evolve - 1, 10).reason, "capsule.priceChanged")
		-- The gate is checked before the price.
		expect.equal(CapsuleMath.upgradeDecision(state({ 10 }), 1, 1, 9).reason, "capsule.gripLocked")
		-- Without a capsules state (a profile that is not ready) nothing can be bought.
		expect.equal(CapsuleMath.upgradeDecision(nil, 1, CapsuleMath.price(1), 1).reason, "capsule.locked")
	end)

	t.test(
		"unlockDecision: the next slot at its price; an unlocked one is a replay; out of order is refused",
		function()
			expect.deepEqual(CapsuleMath.unlockDecision(state({ 1 }), 2, 2_500), { kind = "buy", cost = 2_500 })
			expect.deepEqual(CapsuleMath.unlockDecision(state({ 1, 1 }), 2, 2_500), { kind = "replay", cost = 2_500 })
			expect.equal(CapsuleMath.unlockDecision(state({ 1, 1 }), 1, 0).kind, "replay")
			expect.equal(CapsuleMath.unlockDecision(state({ 1 }), 3, 80_000).reason, "capsule.notNext")
			expect.equal(CapsuleMath.unlockDecision(state({ 1 }), 2, 2_499).reason, "capsule.priceChanged")
			local bad: { { any } } = { { 0, 0 }, { 5, 0 }, { 2.5, 2_500 }, { 2, -1 }, { 2, 1.5 }, { "2", 2_500 } }
			for _, args in bad do
				expect.equal(CapsuleMath.unlockDecision(state({ 1 }), args[1], args[2]).reason, "net.invalid")
			end
		end
	)

	t.test("rewardCoins = squeezes × value, rounded down and stopping at 9 Qa", function()
		expect.equal(CapsuleMath.rewardCoins(100, 10), 1_000) -- spec §9: Daily day 1 for a new player
		expect.equal(CapsuleMath.rewardCoins(600, 1_024), 614_400)
		expect.equal(CapsuleMath.rewardCoins(1.5, 3), 4)
		expect.equal(CapsuleMath.rewardCoins(1e9, 920_525_589 * 64), MAX_COINS)
		for _, bad in { -1, 0 / 0, math.huge } do
			expect.equal(CapsuleMath.rewardCoins(bad, 10), 0)
			expect.equal(CapsuleMath.rewardCoins(10, bad), 0)
		end
	end)
end
