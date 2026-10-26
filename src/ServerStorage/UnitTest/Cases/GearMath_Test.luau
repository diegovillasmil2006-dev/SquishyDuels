--!strict
-- GearMath_Test: unit tests for ReplicatedStorage.Shared.GearMath and Config/ValidateGear (gear step 2, 2026-10-26:
-- the launchers, arm gear and armor; owner "Yes, use these prices" + "Use the fixed prices"). Server only
-- (ServerStorage.UnitTest). Pure.
-- Contract (Config.Economy.Gear):
--   * four lines bought one step at a time: held and platform launchers and arm gear (36 steps: tiers 1-5 of 4 steps,
--     tiers 6-7 of 8 smaller ones) and armor (7 pieces, one a tier);
--   * price(line, step): the owner's table (held = platform; arm gear half; armor its own list), nil outside 1..max;
--     every line's prices strictly rise;
--   * multiplier(gear): each power-line step x2 (tiers 6-7 x sqrt 2), a whole line x2^28; armor adds no power; a
--     missing or broken gear is x1;
--   * traps: chance by zone 8% .. 30%; a trap in zone n leaves 2^-(n + 1 - armor) of the power (never more than all);
--   * buyDecision(gear, line, expectedPrice): the next step and its price, or net.invalid / gear.max /
--     gear.priceChanged (the price is compared, never charged);
--   * HighwayMath.power(level, gear) = power(level) x multiplier(gear);
--   * ValidateGear: the shipped table passes; broken tables are named.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

local K, M, B, T = 1e3, 1e6, 1e9, 1e12
local LAUNCHER = {
	18 * K,
	40 * K,
	87 * K,
	190 * K,
	13 * M,
	29 * M,
	63 * M,
	140 * M,
	220 * M,
	480 * M,
	1.1 * B,
	2.3 * B,
	15 * B,
	33 * B,
	73 * B,
	160 * B,
	400 * B,
	880 * B,
	1.9 * T,
	4.3 * T,
	4.7 * T,
	6 * T,
	7.7 * T,
	9.9 * T,
	13 * T,
	16 * T,
	21 * T,
	26 * T,
	47 * T,
	63 * T,
	84 * T,
	110 * T,
	150 * T,
	200 * T,
	270 * T,
	350 * T,
}
local ARMOR = { 9 * K, 6.5 * M, 110 * M, 7.5 * B, 200 * B, 3.4 * T, 35 * T }

return function(t: Context)
	local expect = t.expect
	local GearMath = t.requireShared("GearMath")
	local HighwayMath = t.requireShared("HighwayMath")
	local Config = t.requireShared("Config")
	local ValidateGear = t.requireShared("Config/ValidateGear")

	local function gear(held: number, platform: number, arm: number, armor: number): any
		return { held = held, platform = platform, arm = arm, armor = armor }
	end

	t.test("four lines: launchers and arm gear 36 steps, armor 7 pieces", function()
		expect.deepEqual(GearMath.LINES, { "held", "platform", "arm", "armor" })
		expect.equal(GearMath.maxStep("held"), 36)
		expect.equal(GearMath.maxStep("platform"), 36)
		expect.equal(GearMath.maxStep("arm"), 36)
		expect.equal(GearMath.maxStep("armor"), 7)
		for _, bad in { "sword", "", 1, nil } :: { any } do
			expect.equal(GearMath.maxStep(bad), nil)
		end
		expect.equal(GearMath.tierOf(1), 1)
		expect.equal(GearMath.tierOf(4), 1)
		expect.equal(GearMath.tierOf(5), 2)
		expect.equal(GearMath.tierOf(20), 5)
		expect.equal(GearMath.tierOf(21), 6)
		expect.equal(GearMath.tierOf(28), 6)
		expect.equal(GearMath.tierOf(29), 7)
		expect.equal(GearMath.tierOf(36), 7)
	end)

	t.test("prices: the owner's table (held = platform, arm gear half, armor its own); nil outside", function()
		for step, price in LAUNCHER do
			expect.equal(GearMath.price("held", step), price)
			expect.equal(GearMath.price("platform", step), price)
			expect.equal(GearMath.price("arm", step), price / 2)
		end
		for step, price in ARMOR do
			expect.equal(GearMath.price("armor", step), price)
		end
		for _, bad in { 0, 37, 1.5, -1, 0 / 0, "1" } :: { any } do
			expect.equal(GearMath.price("held", bad), nil)
		end
		expect.equal(GearMath.price("armor", 8), nil)
		expect.equal(GearMath.price("sword", 1), nil)
		for _, line in GearMath.LINES do
			local last = 0
			for step = 1, GearMath.maxStep(line) do
				local price = GearMath.price(line, step)
				expect.truthy(price > last) -- every next piece costs more than the last
				expect.equal(price, math.floor(price)) -- whole Coins
				last = price
			end
		end
	end)

	t.test("multiplier: x2 a step (tiers 6-7 x sqrt 2), a whole line x2^28, armor none, broken x1", function()
		expect.equal(GearMath.multiplier(gear(0, 0, 0, 0)), 1)
		expect.equal(GearMath.multiplier(gear(1, 0, 0, 0)), 2)
		expect.equal(GearMath.multiplier(gear(4, 0, 0, 0)), 16) -- a whole tier x16
		expect.equal(GearMath.multiplier(gear(4, 4, 4, 0)), 16 ^ 3)
		expect.equal(GearMath.multiplier(gear(0, 0, 0, 7)), 1) -- armor adds no power
		expect.near(GearMath.multiplier(gear(21, 0, 0, 0)), 2 ^ 20.5, 1e-6) -- the first small step: x sqrt 2
		expect.equal(GearMath.multiplier(gear(36, 0, 0, 0)), 2 ^ 28)
		expect.equal(GearMath.multiplier(gear(36, 36, 36, 7)), 2 ^ 84)
		for _, bad in { nil, "x", 5, { held = 0 / 0 }, { held = -3 }, { held = 99 } } :: { any } do
			local m = GearMath.multiplier(bad)
			expect.truthy(m >= 1 and m <= 2 ^ 28) -- broken counts as none, too many as the whole line
		end
		expect.equal(GearMath.multiplier({ held = 2.9 }), 4) -- whole steps only
	end)

	t.test("traps: 8% .. 30% by zone; a trap leaves 2^-(zone + 1 - armor), never more than all", function()
		expect.deepEqual(
			{ GearMath.trapChance(1), GearMath.trapChance(4), GearMath.trapChance(7) },
			{ 0.08, 0.18, 0.30 }
		)
		expect.equal(GearMath.trapChance(99), 0.30) -- past the last zone: the last zone's
		expect.equal(GearMath.trapChance(0), 0.08)
		expect.equal(GearMath.trapKeep(1, 0), 1 / 4) -- harsh without armor (owner 2026-10-17)
		expect.equal(GearMath.trapKeep(7, 0), 1 / 256)
		expect.equal(GearMath.trapKeep(7, 7), 1 / 2)
		expect.equal(GearMath.trapKeep(1, 1), 1 / 2)
		expect.equal(GearMath.trapKeep(1, 2), 1) -- enough armor: the trap takes nothing
		expect.equal(GearMath.trapKeep(1, 7), 1)
	end)

	t.test("buyDecision: the next step and its price, or net.invalid / gear.max / gear.priceChanged", function()
		local none = gear(0, 0, 0, 0)
		expect.deepEqual(GearMath.buyDecision(none, "held", 18_000), { step = 1, price = 18_000 })
		expect.deepEqual(GearMath.buyDecision(none, "arm", 9_000), { step = 1, price = 9_000 })
		expect.deepEqual(GearMath.buyDecision(gear(4, 0, 0, 0), "held", 13_000_000), { step = 5, price = 13_000_000 })
		expect.deepEqual(GearMath.buyDecision(gear(0, 0, 0, 6), "armor", 35 * T), { step = 7, price = 35 * T })
		local function refused(g: any, line: any, price: any, code: string)
			local decision, why = GearMath.buyDecision(g, line, price)
			expect.equal(decision, nil)
			expect.equal(why, code)
		end
		refused(none, "sword", 18_000, "net.invalid")
		refused(none, 3, 18_000, "net.invalid")
		refused(none, "held", 17_999, "gear.priceChanged")
		refused(gear(36, 0, 0, 0), "held", 1, "gear.max")
		refused(gear(0, 0, 0, 7), "armor", 1, "gear.max")
		-- A missing or broken gear counts as none bought.
		expect.deepEqual(GearMath.buyDecision(nil, "platform", 18_000), { step = 1, price = 18_000 })
	end)

	t.test("HighwayMath.power(level, gear) = power(level) x multiplier(gear)", function()
		expect.equal(HighwayMath.power(1, nil), 900)
		expect.equal(HighwayMath.power(1, gear(4, 0, 0, 0)), 900 * 16)
		expect.near(HighwayMath.power(10, gear(4, 4, 4, 3)), HighwayMath.power(10) * 16 ^ 3, 1e-3)
	end)

	t.test("ValidateGear: the shipped table passes; broken ones are named", function()
		expect.deepEqual(ValidateGear(Config), {})
		local function broken(change: (g: any) -> ()): number
			local g = table.clone(Config.Economy.Gear)
			g.tierSteps = table.clone(g.tierSteps)
			g.launcherPrices = table.clone(g.launcherPrices)
			g.armorPrices = table.clone(g.armorPrices)
			g.trapChance = table.clone(g.trapChance)
			change(g)
			local economy = table.clone(Config.Economy)
			economy.Gear = g
			return #ValidateGear({ Economy = economy })
		end
		expect.truthy(broken(function(g)
			g.launcherPrices[22] = g.launcherPrices[20] -- falls back
		end) > 0)
		expect.truthy(broken(function(g)
			table.remove(g.launcherPrices) -- one step short of the tiers
		end) > 0)
		expect.truthy(broken(function(g)
			g.armorPrices[3] = 1.5 -- not whole Coins
		end) > 0)
		expect.truthy(broken(function(g)
			g.launcherPrices[1] = 18_001 -- arm gear's half is not whole
		end) > 0)
		expect.truthy(broken(function(g)
			g.trapChance[2] = 1 -- every throw trapped
		end) > 0)
		expect.truthy(broken(function(g)
			g.tierSteps[1] = 0
		end) > 0)
		expect.truthy(broken(function(g)
			g.tierPower = 1 -- gear that adds nothing
		end) > 0)
		expect.truthy(broken(function(g)
			g.launcherPrices[36] = Config.Economy.maxCoins + 1
		end) > 0)
	end)
end
