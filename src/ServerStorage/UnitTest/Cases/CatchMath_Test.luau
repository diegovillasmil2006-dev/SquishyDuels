--!strict
-- CatchMath_Test: unit tests for ReplicatedStorage.Shared.CatchMath and Config.Economy.Catch (rework Option A, owner
-- 2026-11-12: "Yes, build it"; the rules on the vault page "Plan - Rework from top games 2026-11", step 1). Server only
-- (ServerStorage.UnitTest). Pure.
-- Contract:
--   * every highway zone's wild squishies come from one box: zones 1-2 the Soft Box (snack), 3 Sweet, 4 Frosty, 5 Lava,
--     6 Prism, 7 and the Golden Gates (8) Halo; a landing catches from min(the landing's zone, the zone reached);
--   * a throw's chance: share x its Coins / the box price, at least minChance and at most maxChance, and never so much
--     that a catch's sell value is worth more than the throw's own Coins (step 3's money check);
--   * the bad-luck guarantee: a sure catch after pity / chance throws without one;
--   * the catch is a weighted pick from the box's own weights (the odds board's table);
--   * "x/y here": the kinds of a box the player owns, of all its kinds;
--   * every catch sound (Config.Economy.Catch.sounds) has a sound to play (2 first picks were silent slots).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local CatchMath = t.requireShared("CatchMath")
	local Boxes = t.requireShared("Boxes")
	local PenMath = t.requireShared("PenMath")
	local Config = t.requireShared("Config")
	local C = Config.Economy.Catch

	t.test("zones: 1-2 Soft, 3 Sweet, 4 Frosty, 5 Lava, 6 Prism, 7 and the Golden Gates Halo; nothing else", function()
		local want = { "snack", "snack", "sweet", "frosty", "lava", "prism", "halo", "halo" }
		for zone, box in want do
			expect.equal(CatchMath.boxFor(zone), box)
		end
		for _, bad in { 0, 9, -1, 1.5, "1", nil } :: { any } do
			expect.equal(CatchMath.boxFor(bad), nil)
		end
	end)

	t.test("a landing catches in its own zone, but never past the zone reached (a bounce is no shortcut)", function()
		expect.equal(CatchMath.zoneOf(213, 1), 1)
		expect.equal(CatchMath.zoneOf(450, 3), 2) -- Bakery Town
		expect.equal(CatchMath.zoneOf(900, 2), 2) -- a bounce into Boba Lagoon while only Bakery Town is reached
		expect.equal(CatchMath.zoneOf(900, 5), 3)
		expect.equal(CatchMath.zoneOf(8500, 8), 7) -- the Golden Gates lie in Divine Heaven
		expect.equal(CatchMath.zoneOf(213, "x" :: any), 1) -- a broken reach counts as zone 1
	end)

	t.test("sell value: the box's own weights times each squishy's plain sell price", function()
		for _, id in { "snack", "sweet", "frosty", "lava", "prism", "halo" } do
			local box = Boxes.get(id)
			local sum = 0
			for _, item in box.items do
				sum += PenMath.sellPrice({ kind = item.id, form = 0, coat = 0, level = 1, mut = 0 }) * item.weight
			end
			expect.near(CatchMath.sellValue(id), sum / Boxes.WeightTotal, 1e-6 * sum)
			expect.truthy(CatchMath.sellValue(id) > 0)
		end
		expect.equal(CatchMath.sellValue("nope"), 0)
	end)

	t.test("chance: a quarter of the throw's Coins in box value, between 1 in 20 and 1 in 4", function()
		-- a pen earning 1,000 a second, Bakery Town (350 studs): 175K a throw, the Soft Box 150K -> more than 1 in 4
		expect.near(CatchMath.chance(175_000, "snack"), C.maxChance, 1e-9)
		-- a pen earning 100K a second just in Boba Lagoon (1,000 studs): 50M a throw, the Sweet Box 450M -> 1 in 36 -> 1 in 20
		expect.near(CatchMath.chance(50_000_000, "sweet"), C.minChance, 1e-9)
		-- in between: exactly share x Coins / price
		local coins = 0.1 * Boxes.get("snack").cost / C.share
		expect.near(CatchMath.chance(coins, "snack"), 0.1, 1e-9)
		expect.equal(C.minChance, 1 / 20)
		expect.equal(C.maxChance, 1 / 4)
	end)

	t.test("chance: a catch is never worth more to sell than the throw's own Coins (the first minutes)", function()
		-- a new player: Grip Lv 1 throws 213 studs with a pen of 10 a second -> 1,065 Coins
		local fresh = CatchMath.chance(1_065, "snack")
		expect.truthy(fresh > 0 and fresh < C.minChance)
		expect.near(fresh, 1_065 / CatchMath.sellValue("snack"), 1e-9)
		-- across many throws and every box: the expected sell value of a throw's catch stays under its Coins
		for _, id in { "snack", "sweet", "frosty", "lava", "prism", "halo" } do
			local coins = 100
			while coins < 1e18 do
				local chance = CatchMath.chance(coins, id)
				expect.truthy(chance >= 0 and chance <= C.maxChance)
				expect.truthy(chance * CatchMath.sellValue(id) <= coins * (1 + 1e-9))
				coins *= 7
			end
		end
		expect.equal(CatchMath.chance(0, "snack"), 0)
		expect.equal(CatchMath.chance(-5, "snack"), 0)
		expect.equal(CatchMath.chance(1_000, "nope"), 0)
	end)

	t.test("bad luck: a sure catch after pity / chance throws without one", function()
		expect.equal(CatchMath.need(1 / 20), 40)
		expect.equal(CatchMath.need(1 / 4), 8)
		expect.equal(CatchMath.need(0.03), math.ceil(C.pity / 0.03))
		expect.truthy(CatchMath.need(0) > 1e8) -- no Coins: no forced catch
		-- decide: the roll under the chance, or the miss count reaching the need
		expect.equal(CatchMath.decide(0, 1 / 4, 0.2), true)
		expect.equal(CatchMath.decide(0, 1 / 4, 0.3), false)
		expect.equal(CatchMath.decide(6, 1 / 4, 0.99), false)
		expect.equal(CatchMath.decide(7, 1 / 4, 0.99), true) -- the 8th throw since the last catch
		expect.equal(CatchMath.decide(0, 0, 0), false)
	end)

	t.test("the pick: the box's own weights, in its order", function()
		for _, id in { "snack", "frosty", "halo" } do
			local box = Boxes.get(id)
			local counts: { [string]: number } = {}
			for k = 0, Boxes.WeightTotal - 1 do
				local kind = CatchMath.pick(id, (k + 0.5) / Boxes.WeightTotal)
				counts[kind] = (counts[kind] or 0) + 1
			end
			for _, item in box.items do
				expect.equal(counts[item.id], item.weight)
			end
			expect.equal(CatchMath.pick(id, 0), box.items[1].id)
			expect.equal(CatchMath.pick(id, 0.999999), box.items[#box.items].id)
		end
		expect.equal(CatchMath.pick("nope", 0.5), nil)
	end)

	t.test("x/y here: the kinds of the zone's box the player owns", function()
		local box = Boxes.get("snack")
		local owned = { [box.items[1].id] = 3, [box.items[2].id] = 1, dragon = 1 }
		local have, total = CatchMath.have(owned, "snack")
		expect.equal(have, 2)
		expect.equal(total, #box.items)
		local none, all = CatchMath.have(nil, "frosty")
		expect.equal(none, 0)
		expect.equal(all, #Boxes.get("frosty").items)
	end)

	t.test("every catch sound is one the game can play (no silent slot)", function()
		local AssetTable = t.requireShared("AssetTable")
		for name, key in C.sounds do
			local playable = type(key) == "string" and AssetTable.sound(key) ~= nil
			expect.equal(if playable then "ok" else `sounds.{name} = {tostring(key)} has no sound`, "ok")
		end
	end)

	t.test("the shipped numbers pass the check; broken ones are named", function()
		expect.deepEqual(CatchMath.validate(C), {})
		local broken = table.clone(C)
		broken.zoneBoxes = { "snack", "nope" }
		broken.minChance = 0.5
		broken.share = -1
		local problems = CatchMath.validate(broken)
		expect.truthy(#problems >= 3)
	end)
end
