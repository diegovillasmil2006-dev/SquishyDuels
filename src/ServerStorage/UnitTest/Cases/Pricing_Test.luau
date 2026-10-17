--!strict
-- Pricing_Test: unit tests for ReplicatedStorage.Shared.Pricing. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.5, §6.6, §13.2 Part 7 L1; pens3 phase 5, ECONOMY_V3:159-163): ceiling(id) = floor(min over the
-- paid boxes containing id of cost × 10000 / weight) (Commons 789,473, Butter and Chocolate 1,875,000, Mochi Fox and
-- Strawberry Frog 3,750,000, Epics 1,800,720,288, Dragon 1,125,000,000,000; nil for Kitty Bread, which is in no box and
-- not sold); every Catalog shopPrice <= its ceiling; shopPrice(id, owned) is the Welcome price (3,000) for a Common
-- while it is not in `owned`, else the Catalog price (a missing `owned` pays the full price: fail closed), and the
-- Welcome price is under every ceiling too; copies replaced the duplicate refund (DuplicatePolicy "copy").

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- Pens3 phase 5: Common 150K × 10000 / 1900; Butter / Chocolate 150K × 10000 / 800; Mochi Fox / Strawberry Frog 150K ×
-- 10000 / 400; Epic 450M × 10000 / 2499; Dragon 450M × 10000 / 4 (Sweet only).
local CEILINGS: { [string]: number } = {
	toast = 789_473,
	banana = 789_473,
	boba_bear = 789_473,
	pancake_pup = 789_473,
	butter = 1_875_000,
	chocolate = 1_875_000,
	mochi_fox = 3_750_000,
	strawberry_frog = 3_750_000,
	bird = 1_800_720_288,
	donut = 1_800_720_288,
	cloud_bunny = 1_800_720_288,
	cupcake_axolotl = 1_800_720_288,
	dragon = 1_125_000_000_000,
}

return function(t: Context)
	local Pricing = t.requireShared("Pricing")
	local Boxes = t.requireShared("Boxes")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local expect = t.expect

	t.test("ceiling matches the V3 table and is nil for a squishy in no paid box", function()
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
		expect.equal(Pricing.ceiling("toast"), 789_473)
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

	t.test("the whole collection through the shop costs 1,107,214,406,000 Coins at full price (V3:163)", function()
		local total = 0
		for _, def in Catalog.list() do
			total += def.shopPrice or 0
		end
		expect.equal(total, 4 * 789_000 + 2 * 1_875_000 + 2 * 3_750_000 + 4 * 1_800_000_000 + 1_100_000_000_000)
	end)

	t.test("copies replaced the duplicate refund (pens3 phase 5)", function()
		expect.equal(Config.Economy.DuplicatePolicy, "copy")
		expect.equal((Pricing :: any).duplicateRefund, nil)
	end)

	t.test("shopPrice: the Welcome price for a Common not owned yet, then the Catalog price", function()
		local welcome = Config.Economy.Pen.welcomePrice.Common
		expect.equal(welcome, 3_000) -- D1:202 "Welcome price: first one 3K"
		local owned: { [string]: any } = { kitty_bread = { at = 1, src = "starter" } }
		for _, def in Catalog.byRarity("Common") do
			if def.shopPrice ~= nil then
				expect.equal(Pricing.shopPrice(def.id, owned), welcome)
			end
		end
		owned.toast = { at = 2, src = "box" } -- owned once, from anywhere: the full price from now on
		expect.equal(Pricing.shopPrice("toast", owned), 789_000)
		expect.equal(Pricing.shopPrice("banana", owned), welcome)
		-- Every other rarity always pays the Catalog price.
		for _, id in { "butter", "mochi_fox", "bird", "dragon" } do
			expect.equal(Pricing.shopPrice(id, owned), Catalog.get(id).shopPrice)
		end
		-- Not sold, unknown, or no `owned` table to read (fail closed: never cheaper than it should be).
		expect.equal(Pricing.shopPrice(Catalog.starterId(), owned), nil)
		expect.equal(Pricing.shopPrice("nope", owned), nil)
		expect.equal(Pricing.shopPrice("toast", nil), 789_000)
		expect.equal(Pricing.shopPrice("toast", "owned" :: any), 789_000)
	end)

	t.test("the Welcome price is under the ceiling of every Common it applies to", function()
		for rarity, price in Config.Economy.Pen.welcomePrice do
			for _, def in Catalog.byRarity(rarity) do
				local limit = Pricing.ceiling(def.id)
				if def.shopPrice ~= nil and (limit == nil or price > limit or price > def.shopPrice) then
					error(`{def.id}: Welcome price {price} is above its price or its ceiling {tostring(limit)}`)
				end
			end
		end
	end)
end
