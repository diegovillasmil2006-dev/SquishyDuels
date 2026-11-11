--!strict
-- GearFormat_Test: unit tests for StarterPlayer.StarterPlayerScripts.Client.UI.GearFormat (gear step 3, 2026-10-26: the
-- shop's GEAR tab; owner "Yes, build step 3 like that", "Use my themed names", "Tier number + stars"). Pure.
-- Contract:
--   * cards(gear, coins, busyLine?): one card a line (held, platform, arm, armor) for the NEXT step: its piece's name
--     ("Lolli Sling", then "Lolli Sling ★2" for a star), its tier, the stars bought in that tier and the tier's steps
--     (the tile's pips; armor: none), its line ("x2 throw power", tiers 6-7 "x1.4 throw power", armor "Go through
--     traps"), its price, the tier's zone colour token, the name of the tier's 3D model (big job item 9, 2026-11-10:
--     the tile pictures it) and the state: buy / needCoins (with the Coins missing) / busy (a buy of that line on its
--     way) / max (all bought: the last piece, no price);
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
				model = "held_1", -- big job item 9: the piece's own 3D model on the tile
				golden = false, -- big job item 10: not a Golden piece
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
				desc = "Go through traps",
				price = 9_000,
				state = "buy",
				missing = 0,
				color = BIOMES[1].nameColor,
				model = "armor_1",
				golden = false,
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
		-- big job item 9: each card pictures the model of the tier it sells (a star keeps its tier's model)
		expect.equal(c.held.model, "held_1")
		expect.equal(c.platform.model, "platform_2")
		expect.equal(c.arm.model, "arm_6")
		expect.equal(c.armor.model, "armor_4")
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

	-- Big job item 10 (2026-11-10): the Gear Box and Golden gear on the GEAR page.
	t.test("cards: waiting gear cards ride on the line's text; a Golden piece's picture is gold", function()
		local g = gear(2, 4, 0, 1)
		g.cards = { held = 2, platform = 0, arm = 3, armor = 0 }
		g.gold = { held = 1, platform = 1, arm = 0, armor = 0 }
		local c = byLine(GearFormat.cards(g, 1e15))
		expect.equal(c.held.desc, "x2 throw power · Cards 2/3")
		expect.equal(c.held.golden, true) -- the next step is a star of the same (Golden) piece
		expect.equal(c.platform.desc, "x2 throw power")
		expect.equal(c.platform.golden, false) -- the next step is tier 2's piece: plain
		expect.equal(c.arm.desc, "x2 throw power · Cards 3/3") -- waiting for the first arm piece
		expect.equal(c.armor.golden, false)
	end)

	t.test("boxCard: the Gear Box's price, who can get the card and each one's chance (or the fixed next one)", function()
		local GearMath = t.requireShared("GearMath")
		local none = gear(0, 0, 0, 0)
		local price = GearMath.boxPrice(none)
		local card = GearFormat.boxCard(none, price, nil, true)
		expect.equal(card.line, GearFormat.BOX)
		expect.equal(card.name, "Gear Box")
		expect.equal(card.price, price)
		expect.equal(card.state, "buy")
		expect.equal(card.desc, "3 cards make a piece GOLDEN! 1 random card (25% each gear)")
		expect.equal(card.model, nil) -- a picture, not a gear model
		expect.truthy(card.icon ~= nil)
		-- short of Coins; a buy on its way
		local short = GearFormat.boxCard(none, price - 5, nil, true)
		expect.equal(short.state, "needCoins")
		expect.equal(short.missing, 5)
		expect.equal(GearFormat.boxCard(none, price, GearFormat.BOX, true).state, "busy")
		-- an account that may not buy random items sees the one card it gets next
		expect.equal(GearFormat.boxCard(none, price, nil, false).desc, "3 cards make a piece GOLDEN! Next card: Lolli Sling")
		-- lines without room leave the pool: the chances are the pool's
		local some = gear(5, 1, 0, 0)
		some.cards = { held = 3, platform = 1, arm = 3, armor = 0 }
		some.gold = { held = 2 } -- held: Golden, with 3 more cards waiting for the next piece
		local two = GearFormat.boxCard(some, 1e15, nil, true)
		expect.equal(two.desc, "3 cards make a piece GOLDEN! 1 random card (50% each gear)")
		-- one line left with room: no dice at all, the card says which
		some.cards.armor = 3
		expect.equal(GearFormat.boxCard(some, 1e15, nil, true).desc, "3 cards make a piece GOLDEN! Next card: Gumdrop Catapult")
		-- no line has room: nothing to buy
		local full = gear(0, 0, 0, 0)
		full.cards = { held = 3, platform = 3, arm = 3, armor = 3 }
		local closed = GearFormat.boxCard(full, 1e15, nil, true)
		expect.equal(closed.state, "max")
		expect.equal(closed.price, nil)
		expect.equal(closed.maxText, "Cards full")
		expect.equal(closed.desc, "3 cards make a piece GOLDEN! Buy your next gear to use your cards!")
	end)

	t.test("boxToast: the card's piece and count, or the piece turned Golden", function()
		local g = gear(5, 0, 0, 0)
		g.cards = { held = 2 }
		expect.equal(GearFormat.boxToast(g, "held", false), "Gear card for Butter Bow! 2/3")
		expect.equal(GearFormat.boxToast(g, "held", true), "Your Butter Bow is GOLDEN!")
		expect.equal(GearFormat.boxToast(g, "armor", false), "Gear card for Gumdrop Guard! 0/3") -- no armor yet: its first piece
	end)

	t.test("trailTier: the held launcher's tier, 0 without one", function()
		expect.equal(GearFormat.trailTier(gear(0, 9, 9, 9)), 0)
		expect.equal(GearFormat.trailTier(gear(1, 0, 0, 0)), 1)
		expect.equal(GearFormat.trailTier(gear(5, 0, 0, 0)), 2)
		expect.equal(GearFormat.trailTier(gear(36, 0, 0, 0)), 7)
		expect.equal(GearFormat.trailTier(nil), 0)
	end)
end
