--!strict
-- Boxes_Test: unit tests for ReplicatedStorage.Shared.Boxes. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.4, §6.10, §13.2 Part 7 L1; spec 2026-10-09 §3.3): the box data exactly (snack 400 / sweet 1500
-- paid, treat free-only with no cost; ordered items, each new squishy right after its same-rarity siblings, Dragon
-- last; nameKey box.<id>.name; Kitty Bread in no box); every box's weights sum to WeightTotal (10,000); each rarity
-- keeps its §6.4 total, split equally across its items; the "xx.xx" texts come from integer math and add up to
-- "100.00"; byRarity is rarity descending with the §6.4 summaries (Snack: Epic 6.00 · Uncommon 30.00 · Common 64.00);
-- isComplete is true only when every item is owned; containing lists every box a squishy is in; paidById holds only
-- the paid boxes; everything is frozen. Tables are compared by value.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- Spec 2026-10-09 §3.3 (the §6.4 rarity totals split equally), as {id, weight} pairs in table order.
local EXPECTED_ITEMS: { [string]: { { any } } } = {
	snack = {
		{ "toast", 1600 },
		{ "banana", 1600 },
		{ "boba_bear", 1600 },
		{ "pancake_pup", 1600 },
		{ "butter", 750 },
		{ "chocolate", 750 },
		{ "mochi_fox", 750 },
		{ "strawberry_frog", 750 },
		{ "bird", 150 },
		{ "donut", 150 },
		{ "cloud_bunny", 150 },
		{ "cupcake_axolotl", 150 },
	},
	sweet = {
		{ "butter", 1450 },
		{ "chocolate", 1450 },
		{ "mochi_fox", 1450 },
		{ "strawberry_frog", 1450 },
		{ "bird", 950 },
		{ "donut", 950 },
		{ "cloud_bunny", 950 },
		{ "cupcake_axolotl", 950 },
		{ "dragon", 400 },
	},
	treat = {
		{ "toast", 1400 },
		{ "banana", 1400 },
		{ "boba_bear", 1400 },
		{ "pancake_pup", 1400 },
		{ "butter", 850 },
		{ "chocolate", 850 },
		{ "mochi_fox", 850 },
		{ "strawberry_frog", 850 },
		{ "bird", 250 },
		{ "donut", 250 },
		{ "cloud_bunny", 250 },
		{ "cupcake_axolotl", 250 },
	},
}

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

	t.test("the three boxes hold the §6.4 data exactly", function()
		local ids = {}
		for _, box in Boxes.list() do
			table.insert(ids, box.id)
		end
		expect.deepEqual(ids, { "snack", "sweet", "treat" })
		expect.equal(Boxes.WeightTotal, 10000)

		local snack, sweet, treat = Boxes.get("snack"), Boxes.get("sweet"), Boxes.get("treat")
		expect.equal(snack.cost, 400)
		expect.equal(snack.paid, true)
		expect.equal(sweet.cost, 1500)
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

	-- Spec 2026-10-09 §3.3: each rarity's total is split equally across that rarity's items.
	t.test("every item of a rarity has the same weight in a box; Dragon stays last", function()
		for _, box in Boxes.list() do
			local weightOf: { [string]: number } = {}
			for _, entry in box.items do
				local rarity = Catalog.get(entry.id).rarity
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
		expect.deepEqual(Boxes.odds("snack")[1], { id = "toast", weight = 1600, percent = 16, text = "16.00" })
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
		expect.deepEqual(summary("snack"), { { "Epic", "6.00" }, { "Uncommon", "30.00" }, { "Common", "64.00" } })
		expect.deepEqual(summary("sweet"), { { "Exclusive", "4.00" }, { "Epic", "38.00" }, { "Uncommon", "58.00" } })
		expect.deepEqual(summary("treat"), { { "Epic", "10.00" }, { "Uncommon", "34.00" }, { "Common", "56.00" } })
		for _, box in Boxes.list() do
			local sum = 0
			for _, row in Boxes.byRarity(box.id) do
				sum += row.weight
			end
			expect.equal(sum, Boxes.WeightTotal)
		end
		expect.deepEqual(Boxes.byRarity("nope"), {})
	end)

	t.test("isComplete is true only when every item of the box is owned", function()
		local owned: { [string]: any } = { kitty_bread = {} }
		expect.falsy(Boxes.isComplete("snack", owned))
		for _, entry in Boxes.get("snack").items do
			owned[entry.id] = { at = 0, src = "box" }
		end
		expect.truthy(Boxes.isComplete("snack", owned))
		-- Owning the Snack Box items does not complete the Sweet Box (Dragon is missing).
		expect.falsy(Boxes.isComplete("sweet", owned))
		owned.dragon = { at = 0, src = "shop" }
		expect.truthy(Boxes.isComplete("sweet", owned))
		owned.bird = nil
		expect.falsy(Boxes.isComplete("snack", owned))
		expect.falsy(Boxes.isComplete("nope", owned))
	end)

	t.test("containing lists every box a squishy is in, with its chance and whether the box is paid", function()
		expect.deepEqual(Boxes.containing("dragon"), {
			{ boxId = "sweet", weight = 400, percent = 4, text = "4.00", paid = true },
		})
		local butter = Boxes.containing("butter")
		local seen: { { any } } = {}
		for _, row in butter do
			table.insert(seen, { row.boxId, row.text, row.paid })
		end
		local expected: { { any } } =
			{ { "snack", "7.50", true }, { "sweet", "14.50", true }, { "treat", "8.50", false } }
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
		expect.deepEqual(paid, { "snack", "sweet" })
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
		expect.equal(#Boxes.list(), 3)
	end)
end
