--!strict
-- GearFormat_Test: unit tests for StarterPlayer.StarterPlayerScripts.Client.UI.GearFormat (gear step 3, 2026-10-26: the
-- shop's GEAR tab; owner "Yes, build step 3 like that", "Use my themed names", "Tier number + stars"). Pure.
-- Contract:
--   * cards(gear, coins, busyLine?): one card a line (held, platform, arm, armor) for the NEXT step: its piece's name
--     ("Lolli Sling", then "Lolli Sling ★2" for a star), its tier, the stars bought in that tier and the tier's steps
--     (the tile's pips; armor: none), its line ("x2 throw power", tiers 6-7 "x1.4 throw power", armor "Traps take
--     less"), its price, the tier's zone colour token and the state: buy / needCoins (with the Coins missing) / busy (a
--     buy of that line on its way) / max (all bought: the last piece, no price);
--   * powerText(gear): the gear's throw power multiplier ("x16");
--   * trailTier(gear): the held launcher's tier (0 = none): the throw's trail colour;
--   * every gear piece has its decided name (Decisions 2026-10-15 and 2026-10-26).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local NAMES = {
	held = { "Lolli Sling", "Butter Bow", "Boba Blaster", "Frosty Flick", "Magma Snap", "Prism Popper", "Halo Hurler" },
	platform = {
		"Gumdrop Catapult",
		"Toaster Tosser",
		"Pearl Pitcher",
		"Glacier Flinger",
		"Volcano Vaulter",
		"Starbeam Trebuchet",
		"Angel Ascender",
	},
	arm = { "Gummy Grip", "Biscuit Bracer", "Bubble Band", "Frost Fist", "Magma Mitt", "Rainbow Wrap", "Halo Gauntlet" },
	armor = { "Gumdrop Guard", "Crust Coat", "Pearl Plate", "Ice Shell", "Volcano Vest", "Prism Plate", "Angel Aegis" },
}

return function(t: Context)
	local expect = t.expect
	local GearFormat = t.requireClient("UI/GearFormat")
	local Strings = t.requireShared("Strings")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local BIOMES = WorldLayout.Highway.biomes

	local function gear(held: number, platform: number, arm: number, armor: number): any
		return { held = held, platform = platform, arm = arm, armor = armor }
	end

	local function byLine(cards: { any }): { [string]: any }
		local map = {}
		for _, card in cards do
			map[card.line] = card
		end
		return map
	end

	t.test("every gear piece has its decided name", function()
		expect.deepEqual(Strings.gear.names, NAMES)
	end)

	t.test(
		"cards: the next piece of each line in order, its price, its zone colour; buy when the Coins reach",
		function()
			local cards = GearFormat.cards(gear(0, 0, 0, 0), 20_000)
			expect.deepEqual(
				{ cards[1].line, cards[2].line, cards[3].line, cards[4].line },
				{ "held", "platform", "arm", "armor" }
			)
			local c = byLine(cards)
			expect.deepEqual(c.held, {
				line = "held",
				name = "Lolli Sling",
				tier = 1,
				stars = 0,
				steps = 4,
				desc = "x2 throw power",
				price = 18_000,
				state = "buy",
				missing = 0,
				color = BIOMES[1].nameColor,
			})
			expect.equal(c.platform.name, "Gumdrop Catapult")
			expect.equal(c.platform.price, 18_000)
			expect.equal(c.arm.name, "Gummy Grip")
			expect.equal(c.arm.price, 9_000)
			expect.deepEqual(c.armor, {
				line = "armor",
				name = "Gumdrop Guard",
				tier = 1,
				stars = 0,
				steps = 0, -- armor is one piece a tier: no pips
				desc = "Traps take less",
				price = 9_000,
				state = "buy",
				missing = 0,
				color = BIOMES[1].nameColor,
			})
		end
	)

	t.test("cards: a star step names its star; a full tier moves on; tiers 6-7 are x1.4 steps", function()
		local c = byLine(GearFormat.cards(gear(2, 4, 21, 3), 1e15))
		expect.equal(c.held.name, "Lolli Sling ★2")
		expect.equal(c.held.stars, 2)
		expect.equal(c.held.price, 87_000)
		expect.equal(c.platform.name, "Toaster Tosser") -- tier 1 done: the next is tier 2's base piece
		expect.equal(c.platform.tier, 2)
		expect.equal(c.platform.stars, 0)
		expect.equal(c.platform.color, BIOMES[2].nameColor)
		expect.equal(c.arm.name, "Rainbow Wrap ★1") -- 21 bought: tier 6's second (small) step
		expect.equal(c.arm.tier, 6)
		expect.equal(c.arm.stars, 1)
		expect.equal(c.arm.steps, 8)
		expect.equal(c.arm.desc, "x1.4 throw power")
		expect.equal(c.arm.price, 6e12 / 2)
		expect.equal(c.armor.name, "Ice Shell")
		expect.equal(c.armor.tier, 4)
	end)

	t.test("cards: short of Coins says how many are missing; a buy on its way is busy", function()
		local c = byLine(GearFormat.cards(gear(0, 0, 0, 0), 10_000))
		expect.equal(c.held.state, "needCoins")
		expect.equal(c.held.missing, 8_000)
		expect.equal(c.arm.state, "buy") -- 9,000 is within reach
		local busy = byLine(GearFormat.cards(gear(0, 0, 0, 0), 1e6, "arm"))
		expect.equal(busy.arm.state, "busy")
		expect.equal(busy.held.state, "buy")
		-- No Coins known yet (still loading) counts as none.
		expect.equal(byLine(GearFormat.cards(gear(0, 0, 0, 0), nil)).held.state, "needCoins")
	end)

	t.test("cards: all bought is MAX with the last piece and no price; a missing gear counts as none", function()
		local c = byLine(GearFormat.cards(gear(36, 0, 0, 7), 0))
		expect.equal(c.held.state, "max")
		expect.equal(c.held.price, nil)
		expect.equal(c.held.name, "Halo Hurler ★7")
		expect.equal(c.held.tier, 7)
		expect.equal(c.held.stars, 8)
		expect.equal(c.held.desc, Strings.gear.maxLine)
		expect.equal(c.armor.state, "max")
		expect.equal(c.armor.name, "Angel Aegis")
		expect.equal(byLine(GearFormat.cards(nil, 0)).held.name, "Lolli Sling")
	end)

	t.test("powerText: the gear's throw power multiplier", function()
		expect.equal(GearFormat.powerText(gear(0, 0, 0, 0)), "x1")
		expect.equal(GearFormat.powerText(gear(4, 0, 0, 7)), "x16")
		expect.equal(GearFormat.powerText(nil), "x1")
	end)

	t.test("trailTier: the held launcher's tier, 0 without one", function()
		expect.equal(GearFormat.trailTier(gear(0, 9, 9, 9)), 0)
		expect.equal(GearFormat.trailTier(gear(1, 0, 0, 0)), 1)
		expect.equal(GearFormat.trailTier(gear(5, 0, 0, 0)), 2)
		expect.equal(GearFormat.trailTier(gear(36, 0, 0, 0)), 7)
		expect.equal(GearFormat.trailTier(nil), 0)
	end)
end
