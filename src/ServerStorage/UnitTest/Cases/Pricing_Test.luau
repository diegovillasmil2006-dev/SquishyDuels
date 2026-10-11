--!strict
-- Pricing_Test: unit tests for ReplicatedStorage.Shared.Pricing. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.5, §6.6, §13.2 Part 7 L1; spec 2026-10-09 §3.3): ceiling(id) = floor(min over the paid boxes
-- containing id of cost × 10000 / weight) (with 14 squishies: Commons 2,500, Uncommons 5,333, Epics 15,789, Dragon
-- 37,500; nil for Kitty Bread, which is in no box and not sold); every Catalog shopPrice <= its ceiling; every
-- duplicate refund is below the price of every paid box that contains that rarity (opening can never earn Coins);
-- duplicateRefund follows Config.Economy.DuplicateRefund under the "refund" policy and is 0 for a non-rarity.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- Spec 2026-10-09 §3.3 ceilings: Common 400 × 10000 / 1600; Uncommon min(400 × 10000 / 750, 1500 × 10000 / 1450);
-- Epic min(400 × 10000 / 150, 1500 × 10000 / 950); Dragon 1500 × 10000 / 400.
local CEILINGS: { [string]: number } = {
	toast = 2500,
	banana = 2500,
	boba_bear = 2500,
	pancake_pup = 2500,
	butter = 5333,
	chocolate = 5333,
	mochi_fox = 5333,
	strawberry_frog = 5333,
	bird = 15789,
	donut = 15789,
	cloud_bunny = 15789,
	cupcake_axolotl = 15789,
	dragon = 37500,
}

return function(t: Context)
	local Pricing = t.requireShared("Pricing")
	local Boxes = t.requireShared("Boxes")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local expect = t.expect

	t.test("ceiling matches the spec 2026-10-09 table and is nil for a squishy in no paid box", function()
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
		expect.equal(Pricing.ceiling("toast"), 2500)
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

	t.test("the whole collection through the shop costs 69,800 Coins (spec 2026-10-09 §3.3)", function()
		local total = 0
		for _, def in Catalog.list() do
			total += def.shopPrice or 0
		end
		expect.equal(total, 69800)
	end)

	t.test("every duplicate refund is below every paid box price containing that rarity", function()
		for _, box in Boxes.list() do
			if box.paid then
				for _, entry in box.items do
					local def = Catalog.get(entry.id)
					local refund = Pricing.duplicateRefund(def.rarity)
					if not (refund < box.cost) then
						error(`{box.id} ({box.cost}) contains {entry.id}, whose refund {refund} is not below it`)
					end
				end
			end
		end
	end)

	t.test("duplicateRefund follows Config.Economy.DuplicateRefund under the refund policy", function()
		expect.equal(Config.Economy.DuplicatePolicy, "refund")
		expect.equal(Pricing.duplicateRefund("Common"), 100)
		expect.equal(Pricing.duplicateRefund("Uncommon"), 150)
		expect.equal(Pricing.duplicateRefund("Epic"), 300)
		expect.equal(Pricing.duplicateRefund("Exclusive"), 1000)
		for rarity, coins in Config.Economy.DuplicateRefund do
			expect.equal(Pricing.duplicateRefund(rarity), coins)
		end
		expect.equal(Pricing.duplicateRefund("Mythic"), 0)
		expect.equal(Pricing.duplicateRefund(nil :: any), 0)
	end)
end
