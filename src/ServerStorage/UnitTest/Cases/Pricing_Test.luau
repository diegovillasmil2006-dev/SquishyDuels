--!strict
-- Pricing_Test: unit tests for ReplicatedStorage.Shared.Pricing. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.5, §6.6, §13.2 Part 7 L1; spec 2026-10-12 §8): ceiling(id) = floor(min over the paid boxes
-- containing id of cost × 10000 / weight) (Commons 750,000, Uncommons 3,000,000, Epics 4,504,504,504, Dragon
-- 1,125,000,000,000; nil for Kitty Bread, which is in no box and not sold); every Catalog shopPrice <= its ceiling;
-- duplicateRefund(boxId) gives back a quarter of the box price (Snack 37,500, Sweet 112,500,000; the free Treat Box the
-- Snack's 37,500), below every paid box's price (opening can never earn Coins), and 0 for an unknown box.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- Spec 2026-10-12 §8 ceilings: Common 150K × 10000 / 2000; Uncommon min(150K × 10000 / 500, 450M × 10000 / 1500);
-- Epic 450M × 10000 / 999 (Sweet only); Dragon 450M × 10000 / 4.
local CEILINGS: { [string]: number } = {
	toast = 750_000,
	banana = 750_000,
	boba_bear = 750_000,
	pancake_pup = 750_000,
	butter = 3_000_000,
	chocolate = 3_000_000,
	mochi_fox = 3_000_000,
	strawberry_frog = 3_000_000,
	bird = 4_504_504_504,
	donut = 4_504_504_504,
	cloud_bunny = 4_504_504_504,
	cupcake_axolotl = 4_504_504_504,
	dragon = 1_125_000_000_000,
}

return function(t: Context)
	local Pricing = t.requireShared("Pricing")
	local Boxes = t.requireShared("Boxes")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local expect = t.expect

	t.test("ceiling matches the spec 2026-10-12 table and is nil for a squishy in no paid box", function()
		for id, expected in CEILINGS do
			expect.equal(Pricing.ceiling(id), expected)
		end
		expect.equal(Pricing.ceiling(Catalog.starterId()), nil)
		expect.equal(Pricing.ceiling("nope"), nil)
	end)

	t.test("ceiling uses only paid boxes (the free Treat Box never lowers a price limit)", function()
		-- Toast is 14.00% in the Treat Box; a "cost" of 0 there would give a ceiling of 0 if it counted.
		for _, row in Boxes.containing("toast") do
			if not row.paid then
				expect.equal(Boxes.get(row.boxId).cost, nil)
			end
		end
		expect.equal(Pricing.ceiling("toast"), 750_000)
	end)

	t.test("every shop price is at or below its ceiling", function()
		for _, def in Catalog.list() do
			local price = def.shopPrice
			if price ~= nil then
				local limit = Pricing.ceiling(def.id)
				if limit == nil or price > limit then
					error(`{def.id}: shopPrice {price} is above the ceiling {tostring(limit)}`)
				end
			end
		end
	end)

	t.test("the whole collection through the shop costs 1,106,810,840,000 Coins (spec 2026-10-12 §6)", function()
		local total = 0
		for _, def in Catalog.list() do
			total += def.shopPrice or 0
		end
		expect.equal(total, 4 * 10_000 + 4 * 2_700_000 + 4 * 1_700_000_000 + 1_100_000_000_000)
	end)

	t.test("a paid box's double gives back a quarter of its price, always below the price", function()
		for _, box in Boxes.list() do
			if box.paid then
				local refund = Pricing.duplicateRefund(box.id)
				expect.equal(refund, box.cost // 4)
				if not (refund < box.cost) then
					error(`{box.id} ({box.cost}): the refund {refund} is not below the price`)
				end
			end
		end
	end)

	t.test("duplicateRefund: Snack 37,500, Sweet 112,500,000, the free Treat Box the Snack's; 0 otherwise", function()
		expect.equal(Config.Economy.DuplicatePolicy, "refund")
		expect.equal(Pricing.duplicateRefund("snack"), 37_500)
		expect.equal(Pricing.duplicateRefund("sweet"), 112_500_000)
		expect.equal(Pricing.duplicateRefund("treat"), 37_500)
		expect.equal(Pricing.duplicateRefund("nope"), 0)
		expect.equal(Pricing.duplicateRefund(nil :: any), 0)
	end)
end
