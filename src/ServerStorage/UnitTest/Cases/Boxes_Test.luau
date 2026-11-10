--!strict
-- Boxes_Test: unit tests for ReplicatedStorage.Shared.Boxes. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.4, §6.10, §13.2 Part 7 L1; spec 2026-10-09 §3.3; spec 2026-10-12 §8): the box data exactly
-- (snack 150,000 / sweet 450,000,000 paid, treat free-only with no cost; ordered items, each new squishy right after its
-- same-rarity siblings, Dragon last; nameKey box.<id>.name; Kitty Bread in no box); every box's weights sum to
-- WeightTotal (10,000); each rarity's total is split equally across its items, except Mochi Fox and Strawberry Frog
-- (pens3 phase 5: Rare-to-be, their own weight until their rarity moves in phase 22); the "xx.xx" texts come from
-- integer math and add up to "100.00"; byRarity is rarity descending (Snack: Uncommon 24.00 · Common 76.00);
-- containing lists every box a squishy is in; paidById holds only the paid boxes; everything is frozen. Pens3 phase 5:
-- the V3 odds (Soft 1,900 / 800 / 400; Sweet the 4 Epics 2,499 and Dragon 4; Royal 1,400 / 900 / 600 / 350), and the
-- fixed orders of restricted accounts (smooth weighted round-robin, V4:248-252), each item as often as its weight says
-- (rounded, a tie to the earlier item), repeating; isComplete is gone (copies). Series 01 (2026-11-10): Soft a cycle
-- of 150 with the first Rares at boxes 16-18, Sweet 2,500 with Cosmo at box 417 and the Dragon at 834. Tables are
-- compared by value.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- Pens3 phase 5 (ECONOMY_V3:159-161; Snack = Soft, Treat = Royal), as {id, weight} pairs in table order. Series 01
-- (2026-11-10): Berry Jelly, Peachy, Grapey, Bao Buddy and Pando join the Soft Box (one weight a rarity: 1,266 / 532 /
-- 202), Cosmo the Sweet Box before the Dragon (4 each, the Epics 2,498); the Royal Box is unchanged.
local EXPECTED_ITEMS: { [string]: { { any } } } = {
	snack = {
		{ "toast", 1266 },
		{ "banana", 1266 },
		{ "boba_bear", 1266 },
		{ "pancake_pup", 1266 },
		{ "berry_jelly", 1266 },
		{ "peachy", 1266 },
		{ "butter", 532 },
		{ "chocolate", 532 },
		{ "grapey", 532 },
		{ "mochi_fox", 202 },
		{ "strawberry_frog", 202 },
		{ "bao_buddy", 202 },
		{ "pando", 202 },
	},
	sweet = {
		{ "bird", 2498 },
		{ "donut", 2498 },
		{ "cloud_bunny", 2498 },
		{ "cupcake_axolotl", 2498 },
		{ "cosmo", 4 },
		{ "dragon", 4 },
	},
	-- Plan "50 squishies" step 4 (Frosty Box, 2026-11-10): 30 / 30 / 13 / 13 / 10 / 3.9 / 0.1 %.
	frosty = {
		{ "cone_cub", 3000 },
		{ "slushy_seal", 3000 },
		{ "ice_pop_beaver", 1300 },
		{ "mint_chip_mouse", 1300 },
		{ "sundae_manatee", 1000 },
		{ "gelato_narwhal", 390 },
		{ "parfait_wyvern", 10 },
	},
	-- Plan "50 squishies" step 5 (Lava Box, 2026-11-10): the same weights.
	lava = {
		{ "cocoa_quokka", 3000 },
		{ "cinder_bun", 3000 },
		{ "smore_skunk", 1300 },
		{ "cayenne_kiwi", 1300 },
		{ "pizza_pangolin", 1000 },
		{ "lava_cake_hippo", 390 },
		{ "mallow_behemoth", 10 },
	},
	-- Plan "50 squishies" step 6 (Prism Box, 2026-11-10): the same weights.
	prism = {
		{ "taffy_tadpole", 3000 },
		{ "jellybean_piglet", 3000 },
		{ "cotton_candy_alpaca", 1300 },
		{ "lollipop_lemur", 1300 },
		{ "gumball_goat", 1000 },
		{ "gummy_pufferfish", 390 },
		{ "candyglass_qilin", 10 },
	},
	treat = {
		{ "toast", 1400 },
		{ "banana", 1400 },
		{ "boba_bear", 1400 },
		{ "pancake_pup", 1400 },
		{ "butter", 900 },
		{ "chocolate", 900 },
		{ "mochi_fox", 600 },
		{ "strawberry_frog", 600 },
		{ "bird", 350 },
		{ "donut", 350 },
		{ "cloud_bunny", 350 },
		{ "cupcake_axolotl", 350 },
	},
}

-- Pens3 phase 5: their rarity moves to Rare in phase 22; until then they weigh less than the other Uncommons.
local RARE_TO_BE: { [string]: boolean } = { mochi_fox = true, strawberry_frog = true }

-- "xx.xx%" with exactly two decimals.
local PERCENT_PATTERN = "^%d+%.%d%d$"

return function(t: Context)
	local Boxes = t.requireShared("Boxes")
	local Catalog = t.requireShared("Catalog")
	local expect = t.expect

	-- Hundredths from an "xx.xx" text, by integer parsing (no float sums).
	local function hundredths(text: string): number
		local whole, frac = string.match(text, "^(%d+)%.(%d%d)$")
		assert(whole ~= nil and frac ~= nil, "not an xx.xx text: " .. text)
		return (tonumber(whole) :: number) * 100 + (tonumber(frac) :: number)
	end

	t.test("the four boxes hold the §6.4 data exactly (the Frosty Box, 2026-11-10)", function()
		local ids = {}
		for _, box in Boxes.list() do
			table.insert(ids, box.id)
		end
		expect.deepEqual(ids, { "snack", "sweet", "frosty", "lava", "prism", "treat" })
		local prism = Boxes.get("prism")
		expect.equal(prism.cost, 8_000_000_000_000)
		expect.equal(prism.paid, true)
		expect.equal(prism.zone, 6)
		expect.equal(prism.fixedCycle, 1000)
		local lava = Boxes.get("lava")
		expect.equal(lava.cost, 600_000_000_000)
		expect.equal(lava.paid, true)
		expect.equal(lava.zone, 5)
		expect.equal(lava.fixedCycle, 1000)
		local frosty = Boxes.get("frosty")
		expect.equal(frosty.cost, 20_000_000_000)
		expect.equal(frosty.paid, true)
		expect.equal(frosty.zone, 4)
		expect.equal(frosty.fixedCycle, 1000)
		expect.equal(Boxes.WeightTotal, 10000)

		local snack, sweet, treat = Boxes.get("snack"), Boxes.get("sweet"), Boxes.get("treat")
		expect.equal(snack.cost, 150_000)
		expect.equal(snack.paid, true)
		expect.equal(sweet.cost, 450_000_000)
		expect.equal(sweet.paid, true)
		expect.equal(treat.cost, nil)
		expect.equal(treat.paid, false)
		expect.equal(treat.freeOnly, true)
		for id, expected in EXPECTED_ITEMS do
			local box = Boxes.get(id)
			expect.equal(box.nameKey, `box.{id}.name`)
			local actual = {}
			for _, entry in box.items do
				table.insert(actual, { entry.id, entry.weight })
			end
			expect.deepEqual(actual, expected)
		end
	end)

	t.test("every box's weights are positive integers that sum to exactly 10000", function()
		for _, box in Boxes.list() do
			local total = 0
			for _, entry in box.items do
				expect.truthy(entry.weight >= 1 and math.floor(entry.weight) == entry.weight)
				total += entry.weight
			end
			expect.equal(total, Boxes.WeightTotal)
		end
	end)

	-- Spec 2026-10-09 §3.3: each rarity's total is split equally across that rarity's items (pens3 phase 5: Mochi Fox
	-- and Strawberry Frog are their own group until they become Rare in phase 22).
	t.test("every item of a rarity has the same weight in a box; Dragon stays last", function()
		for _, box in Boxes.list() do
			local weightOf: { [string]: number } = {}
			for _, entry in box.items do
				local rarity = if RARE_TO_BE[entry.id] then "Rare-to-be" else Catalog.get(entry.id).rarity
				local first = weightOf[rarity]
				if first == nil then
					weightOf[rarity] = entry.weight
				elseif first ~= entry.weight then
					error(`{box.id}: {entry.id} weighs {entry.weight}, other {rarity}s weigh {first}`)
				end
			end
		end
		local sweet = Boxes.get("sweet").items
		expect.equal(sweet[#sweet].id, "dragon")
	end)

	t.test("every item is a Catalog squishy and Kitty Bread is in no box", function()
		for _, box in Boxes.list() do
			for _, entry in box.items do
				expect.truthy(Catalog.isValidId(entry.id))
				expect.truthy(entry.id ~= Catalog.starterId())
			end
		end
		expect.deepEqual(Boxes.containing(Catalog.starterId()), {})
	end)

	t.test("percentText is weight / 100 with two exact decimals", function()
		expect.equal(Boxes.percentText(3200), "32.00")
		expect.equal(Boxes.percentText(300), "3.00")
		expect.equal(Boxes.percentText(1500), "15.00")
		expect.equal(Boxes.percentText(10000), "100.00")
		expect.equal(Boxes.percentText(1), "0.01")
		expect.equal(Boxes.percentText(2666), "26.66")
		expect.equal(Boxes.percentText(0), "0.00")
		expect.equal(Boxes.percentText(-5), "0.00")
		expect.equal(Boxes.percentText(0 / 0), "0.00")
	end)

	t.test('the odds rows are "xx.xx" texts in item order and total exactly 100.00', function()
		for _, box in Boxes.list() do
			local rows = Boxes.odds(box.id)
			expect.equal(#rows, #box.items)
			local sum = 0
			for index, row in rows do
				expect.equal(row.id, box.items[index].id)
				expect.equal(row.weight, box.items[index].weight)
				expect.truthy(string.match(row.text, PERCENT_PATTERN) ~= nil)
				expect.near(row.percent, row.weight / 100)
				sum += hundredths(row.text)
			end
			expect.equal(sum, 10000)
			expect.equal(Boxes.totalText(box.id), "100.00")
		end
		expect.deepEqual(Boxes.odds("snack")[1], { id = "toast", weight = 1266, percent = 12.66, text = "12.66" })
		expect.deepEqual(Boxes.odds("nope"), {})
		expect.equal(Boxes.totalText("nope"), nil)
	end)

	t.test("byRarity is rarity descending with the §6.4 summaries", function()
		local function summary(boxId: string): { { any } }
			local out = {}
			for _, row in Boxes.byRarity(boxId) do
				table.insert(out, { row.rarity, row.text })
			end
			return out
		end
		-- 2026-11-01: Mochi Fox and Strawberry Frog are Rare (Royal 6% each). Series 01 (2026-11-10): the Soft Box's 4
		-- Rares 2.02% each, Cosmo and the Dragon 0.04% each.
		expect.deepEqual(summary("snack"), { { "Rare", "8.08" }, { "Uncommon", "15.96" }, { "Common", "75.96" } })
		expect.deepEqual(summary("sweet"), { { "Exclusive", "0.08" }, { "Epic", "99.92" } })
		expect.deepEqual(
			summary("treat"),
			{ { "Epic", "14.00" }, { "Rare", "12.00" }, { "Uncommon", "18.00" }, { "Common", "56.00" } }
		)
		for _, box in Boxes.list() do
			local sum = 0
			for _, row in Boxes.byRarity(box.id) do
				sum += row.weight
			end
			expect.equal(sum, Boxes.WeightTotal)
		end
		expect.deepEqual(Boxes.byRarity("nope"), {})
	end)

	t.test("isComplete is gone: with copies every box always gives something (pens3 phase 5)", function()
		expect.equal((Boxes :: any).isComplete, nil)
	end)

	-- Pens3 phase 5 (restricted accounts, D1:235, V4:248-252): the fixed orders.
	-- Series 01 (2026-11-10): a cycle of 150 (each Common 19 times, each Uncommon 8, each Rare 3).
	t.test(
		"the Soft Box's fixed order: a cycle of 150, the first Rares at boxes 16-18, repeating",
		function()
			local snack = Boxes.get("snack")
			expect.equal(snack.fixedCycle, 150)
			local order: { string } = {}
			for n = 0, 149 do
				table.insert(order, Boxes.fixedItem("snack", n))
			end
			expect.equal(
				table.concat(order, " ", 1, 24),
				table.concat({
					"toast banana boba_bear pancake_pup berry_jelly peachy butter chocolate grapey", -- boxes 1-9
					"toast banana boba_bear pancake_pup berry_jelly peachy", -- 10-15
					"mochi_fox strawberry_frog bao_buddy", -- 16-18
					"toast banana boba_bear pancake_pup berry_jelly peachy", -- 19-24
				}, " ")
			)
			local counts: { [string]: number } = {}
			for _, id in order do
				counts[id] = (counts[id] or 0) + 1
			end
			expect.equal(counts.toast, 19)
			expect.equal(counts.grapey, 8)
			expect.equal(counts.pando, 3)
			for n = 0, 149 do
				expect.equal(Boxes.fixedItem("snack", n + 150), order[n + 1]) -- the cycle repeats
				expect.equal(Boxes.fixedItem("snack", n + 150 * 4000), order[n + 1])
			end
		end
	)

	t.test("the Sweet Box's fixed order: 2,500 long, Cosmo once at box 417, the Dragon at 834, each Epic 624-625", function()
		local sweet = Boxes.get("sweet")
		expect.equal(sweet.fixedCycle, 2500)
		local counts: { [string]: number } = {}
		local dragonAt: { number } = {}
		local cosmoAt: { number } = {}
		for n = 0, sweet.fixedCycle - 1 do
			local id = Boxes.fixedItem("sweet", n) :: string
			counts[id] = (counts[id] or 0) + 1
			if id == "dragon" then
				table.insert(dragonAt, n + 1)
			elseif id == "cosmo" then
				table.insert(cosmoAt, n + 1)
			end
		end
		expect.deepEqual(cosmoAt, { 417 })
		expect.deepEqual(dragonAt, { 834 })
		expect.deepEqual(
			counts,
			{ bird = 625, donut = 625, cloud_bunny = 624, cupcake_axolotl = 624, cosmo = 1, dragon = 1 }
		)
		expect.equal(Boxes.fixedItem("sweet", 2500 + 833), "dragon")
	end)

	t.test("every paid box's fixed order has each item as often as its weight says (rounded)", function()
		for _, box in Boxes.list() do
			if not box.paid then
				expect.equal(box.fixedCycle, nil)
				expect.equal(Boxes.fixedItem(box.id, 0), nil) -- a free box is never in a fixed order
				continue
			end
			local cycle = box.fixedCycle :: number
			local counts: { [string]: number } = {}
			for n = 0, cycle - 1 do
				local id = Boxes.fixedItem(box.id, n) :: string
				counts[id] = (counts[id] or 0) + 1
			end
			for _, entry in box.items do
				local fair = entry.weight * cycle / Boxes.WeightTotal
				local got = counts[entry.id] or 0
				if math.abs(got - fair) >= 1 then
					error(`{box.id}: {entry.id} {got} times in {cycle}, its weight says {fair}`)
				end
			end
		end
	end)

	t.test("fixedItem: nil for an unknown box, a free box or a count that is not a whole number >= 0", function()
		for _, bad in { -1, 1.5, 0 / 0, math.huge, "3", true } :: { any } do
			expect.equal(Boxes.fixedItem("snack", bad), nil)
		end
		expect.equal(Boxes.fixedItem("snack", nil), nil)
		expect.equal(Boxes.fixedItem("nope", 0), nil)
		expect.equal(Boxes.fixedItem("treat", 0), nil)
		expect.equal(Boxes.fixedItem(nil, 0), nil)
	end)

	t.test("containing lists every box a squishy is in, with its chance and whether the box is paid", function()
		expect.deepEqual(Boxes.containing("dragon"), {
			{ boxId = "sweet", weight = 4, percent = 0.04, text = "0.04", paid = true },
		})
		local butter = Boxes.containing("butter")
		local seen: { { any } } = {}
		for _, row in butter do
			table.insert(seen, { row.boxId, row.text, row.paid })
		end
		local expected: { { any } } = { { "snack", "5.32", true }, { "treat", "9.00", false } }
		expect.deepEqual(seen, expected)
		expect.deepEqual(Boxes.containing("nope"), {})
	end)

	t.test("paidById holds the paid boxes only; get rejects unknown ids", function()
		local paid = {}
		for id, box in Boxes.paidById do
			expect.equal(box.paid, true)
			expect.equal(Boxes.get(id), box)
			table.insert(paid, id)
		end
		table.sort(paid)
		expect.deepEqual(paid, { "frosty", "lava", "prism", "snack", "sweet" })
		expect.equal(Boxes.paidById.treat, nil)
		expect.equal(Boxes.get("nope"), nil)
		expect.equal(Boxes.get(nil), nil)
		expect.equal(Boxes.get(5), nil)
	end)

	t.test("the box data is frozen and list() returns a fresh array", function()
		expect.truthy(table.isfrozen(Boxes.List))
		expect.truthy(table.isfrozen(Boxes.paidById))
		for _, box in Boxes.list() do
			expect.truthy(table.isfrozen(box))
			expect.truthy(table.isfrozen(box.items))
			expect.truthy(table.isfrozen(box.items[1]))
		end
		local list = Boxes.list()
		table.remove(list)
		expect.equal(#Boxes.list(), 6)
	end)

	-- Plan "50 squishies": a zone box opens from its zone on (profile.highway.biome), every other box always.
	t.test("isOpenFor: the Frosty Box from biome 4; the others always; unknown boxes never", function()
		expect.falsy(Boxes.isOpenFor("frosty", 1))
		expect.falsy(Boxes.isOpenFor("frosty", 3))
		expect.truthy(Boxes.isOpenFor("frosty", 4))
		expect.truthy(Boxes.isOpenFor("frosty", 8)) -- the Golden Gates
		expect.falsy(Boxes.isOpenFor("frosty", nil)) -- not known: biome 1
		expect.falsy(Boxes.isOpenFor("frosty", 0 / 0))
		expect.falsy(Boxes.isOpenFor("lava", 4)) -- the Lava Box from Lava Volcano (biome 5)
		expect.truthy(Boxes.isOpenFor("lava", 5))
		expect.falsy(Boxes.isOpenFor("prism", 5)) -- the Prism Box from Rainbow Road (biome 6)
		expect.truthy(Boxes.isOpenFor("prism", 6))
		expect.truthy(Boxes.isOpenFor("snack", nil))
		expect.truthy(Boxes.isOpenFor("sweet", 1))
		expect.falsy(Boxes.isOpenFor("nope", 9))
	end)
end
