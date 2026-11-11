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
--   * ValidateGear: the shipped table passes; broken tables are named;
--   * big job item 10 (2026-11-10, the Gear Box and Golden gear): a gear table may hold `cards` and `gold`; goldCards
--     cards turn a line's current piece Golden (x goldPower throw power, never as much as a step; armor: one more
--     zone's traps), cards without a piece to turn wait (at most goldCards a line) and turn the next piece bought; the
--     box costs boxShare x the dearest step bought last and gives a card only to a line with room, so no card is
--     ever wasted.

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
			g.tierSteps[1] = 0
		end) > 0)
		expect.truthy(broken(function(g)
			g.tierPower = 1 -- gear that adds nothing
		end) > 0)
		expect.truthy(broken(function(g)
			g.launcherPrices[36] = Config.Economy.maxCoins + 1
		end) > 0)
		-- Big job item 10: the Gear Box and Golden gear.
		expect.truthy(broken(function(g)
			g.goldPower = 1.5 -- over a tier 6-7 step (x1.41): the next plain piece would be weaker than the Golden one
		end) > 0)
		expect.truthy(broken(function(g)
			g.goldPower = 1 -- a Golden piece that adds nothing
		end) > 0)
		expect.truthy(broken(function(g)
			g.goldCards = 0
		end) > 0)
		expect.truthy(broken(function(g)
			g.boxShare = 0 -- a free box
		end) > 0)
	end)

	-- Big job item 10 (2026-11-10): the Gear Box and Golden gear -------------------------------------------------
	-- A saved gear table may hold `cards` (0..goldCards waiting on each line) and `gold` (the tier of each line whose
	-- piece is Golden). goldCards cards turn the line's current piece Golden: its throw power x goldPower (armor: one
	-- more zone's traps); the next tier's piece is plain again, and still stronger than the Golden one before it.
	local G = Config.Economy.Gear

	t.test("tier, cards and Golden of a line; broken or missing counts as none", function()
		local gear = { held = 5, platform = 4, arm = 0, armor = 3, cards = { held = 2, arm = 9, armor = "x" }, gold = { held = 2, platform = 2, armor = 3 } }
		expect.equal(GearMath.tier(gear, "held"), 2)
		expect.equal(GearMath.tier(gear, "platform"), 1) -- the last star of tier 1
		expect.equal(GearMath.tier(gear, "arm"), 0)
		expect.equal(GearMath.tier(gear, "armor"), 3) -- armor: a step a tier
		expect.equal(GearMath.tier(gear, "hat"), 0)
		expect.equal(GearMath.cards(gear, "held"), 2)
		expect.equal(GearMath.cards(gear, "platform"), 0)
		expect.equal(GearMath.cards(gear, "arm"), G.goldCards) -- never over what a Golden takes
		expect.equal(GearMath.cards(gear, "armor"), 0)
		expect.equal(GearMath.isGold(gear, "held"), true)
		expect.equal(GearMath.isGold(gear, "platform"), false) -- Golden was another tier's piece
		expect.equal(GearMath.isGold(gear, "arm"), false) -- no piece
		expect.equal(GearMath.isGold(gear, "armor"), true)
		expect.equal(GearMath.isGold(nil, "held"), false)
		expect.equal(GearMath.cards({ held = 1 }, "held"), 0) -- a gear saved before the Gear Box
	end)

	t.test("a Golden power piece multiplies the throw power; a new plain piece is still an upgrade", function()
		for _, line in { "held", "platform", "arm" } do
			for tier = 1, #G.tierSteps do
				local last = 0 -- the last step of this tier
				for i = 1, tier do
					last += G.tierSteps[i]
				end
				local plain = { [line] = last }
				local golden = { [line] = last, gold = { [line] = tier } }
				expect.near(GearMath.multiplier(golden), GearMath.multiplier(plain) * G.goldPower, GearMath.multiplier(plain) * 1e-9)
				if last < GearMath.maxStep(line) then
					local nextPiece = { [line] = last + 1, gold = { [line] = tier } } -- bought: the Golden mark is the old tier's
					expect.truthy(GearMath.multiplier(nextPiece) > GearMath.multiplier(golden))
				end
			end
		end
		-- all three power lines Golden
		local all = { held = 4, platform = 4, arm = 4, gold = { held = 1, platform = 1, arm = 1, armor = 1 } }
		expect.near(GearMath.multiplier(all), 16 ^ 3 * G.goldPower ^ 3, 1e-6)
	end)

	t.test("goldAfter: the cards add up; the last one turns a piece that is not Golden yet; else they wait", function()
		local need = G.goldCards
		local gear = { held = 1, platform = 0, arm = 0, armor = 0, cards = { held = need - 2 } }
		expect.deepEqual({ GearMath.goldAfter(gear, "held", 1) }, { need - 1, 0, false })
		gear.cards.held = need - 1
		expect.deepEqual({ GearMath.goldAfter(gear, "held", 1) }, { 0, 1, true }) -- spent: tier 1 is Golden
		-- no piece on the line: the cards wait, never more than a Golden takes
		expect.deepEqual({ GearMath.goldAfter(gear, "platform", need + 4) }, { need, 0, false })
		-- already Golden: the cards wait for the next piece
		local golden = { held = 2, cards = { held = need }, gold = { held = 1 } }
		expect.deepEqual({ GearMath.goldAfter(golden, "held", 0) }, { need, 1, false })
		golden.held = 5 -- the next tier's piece is bought: the waiting cards turn it Golden at once
		expect.deepEqual({ GearMath.goldAfter(golden, "held", 0) }, { 0, 2, true })
	end)

	t.test("the Gear Box: its price follows the dearest step bought; its pool is every line with room", function()
		expect.equal(GearMath.boxPrice(nil), math.floor(LAUNCHER[1] * G.boxShare))
		expect.equal(GearMath.boxPrice({ held = 3, platform = 9, arm = 2, armor = 2 }), math.floor(LAUNCHER[9] * G.boxShare))
		expect.equal(GearMath.boxPrice({ held = 0, platform = 0, arm = 0, armor = 4 }), math.floor(G.armorPrices[4] * G.boxShare))
		expect.deepEqual(GearMath.boxPool(nil), { "held", "platform", "arm", "armor" })
		local gear = { held = 36, platform = 1, arm = 0, armor = 7, cards = { platform = G.goldCards, armor = 1 }, gold = { held = 7 } }
		-- held: a Golden last-tier piece needs no more cards; platform: full; arm and armor have room
		expect.deepEqual(GearMath.boxPool(gear), { "arm", "armor" })
		local price = GearMath.boxPrice(gear)
		local decision = GearMath.boxDecision(gear, price)
		expect.deepEqual(decision, { price = price, pool = { "arm", "armor" } })
		local changed, why = GearMath.boxDecision(gear, price + 1)
		expect.equal(changed, nil)
		expect.equal(why, "gear.priceChanged")
		local full = { cards = { held = G.goldCards, platform = G.goldCards, arm = G.goldCards, armor = G.goldCards } }
		local none, whyFull = GearMath.boxDecision(full, GearMath.boxPrice(full))
		expect.equal(none, nil)
		expect.equal(whyFull, "gear.boxFull")
	end)

	t.test("twelve boxes at most make every line Golden: a card is never wasted", function()
		local rng = Random.new(7)
		for _ = 1, 200 do
			local gear: any = { held = 1, platform = 1, arm = 1, armor = 1, cards = {}, gold = {} }
			local opens = 0
			while #GearMath.boxPool(gear) > 0 do
				local pool = GearMath.boxPool(gear)
				local line = pool[rng:NextInteger(1, #pool)]
				local cards, gold = GearMath.goldAfter(gear, line, 1)
				gear.cards[line], gear.gold[line] = cards, gold
				opens += 1
				expect.truthy(opens <= 100)
			end
			-- every line Golden (4 x goldCards) and then goldCards more waiting on each for the next piece
			expect.equal(opens, 2 * 4 * G.goldCards)
			for _, line in GearMath.LINES do
				expect.equal(GearMath.isGold(gear, line), true)
			end
		end
	end)
end
