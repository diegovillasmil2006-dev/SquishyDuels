--!strict
-- Pricing_Test: unit tests for ReplicatedStorage.Shared.Pricing. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.5, §6.6, §13.2 Part 7 L1; pens3 phase 5, ECONOMY_V3:159-163): ceiling(id) = floor(min over the
-- paid boxes containing id of cost × 10000 / weight) (Series 01: Commons 1,184,834, Uncommons 2,819,548, Rares
-- 7,425,742, Epics 1,801,441,152, Dragon and Cosmo 1,125,000,000,000; nil for Kitty Bread, which is in no box and
-- not sold); every Catalog shopPrice <= its ceiling; shopPrice(id, owned) is the Welcome price (1,000) for a Common
-- while it is not in `owned`, else the Catalog price (a missing `owned` pays the full price: fail closed), and the
-- Welcome price is under every ceiling too; copies replaced the duplicate refund (DuplicatePolicy "copy").

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- Series 01 (2026-11-10; were pens3 phase 5's 150K × 10000 / 1900, / 800, / 400 and 450M × 10000 / 2499): Common 150K ×
-- 10000 / 1266; Uncommon 150K × 10000 / 532; Rare 150K × 10000 / 202; Epic 450M × 10000 / 2498; Dragon and Cosmo
-- 450M × 10000 / 4 (Sweet only). Every ceiling went up, so every old price still fits.
local CEILINGS: { [string]: number } = {
	toast = 1_184_834,
	banana = 1_184_834,
	boba_bear = 1_184_834,
	pancake_pup = 1_184_834,
	berry_jelly = 1_184_834,
	peachy = 1_184_834,
	butter = 2_819_548,
	chocolate = 2_819_548,
	grapey = 2_819_548,
	mochi_fox = 7_425_742,
	strawberry_frog = 7_425_742,
	bao_buddy = 7_425_742,
	pando = 7_425_742,
	bird = 1_801_441_152,
	donut = 1_801_441_152,
	cloud_bunny = 1_801_441_152,
	cupcake_axolotl = 1_801_441_152,
	cosmo = 1_125_000_000_000,
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
		expect.equal(Pricing.ceiling("toast"), 1_184_834)
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

	-- 2026-11-01: Butter and Chocolate cost half (937.5K: Uncommon power 4 -> 2). Series 01 (2026-11-10): 2 Commons, an
	-- Uncommon, 2 Rares and Cosmo at their siblings' prices.
	-- Frosty Box (2026-11-10): its 7 at the Frosty ceilings (Commons 66B, Uncommons half theirs 76.9B, Rare 200B, Epic
	-- 512B, Parfait Wyvern 20T). Lava Box (2026-11-10): Commons 2T, Uncommons 2.3T, Rare 6T, Epic 15.3T, Mallow Behemoth 600T.
	-- Prism Box (2026-11-10): Commons 26.6T, Uncommons 30.7T, Rare 80T, Epic 205T, Candyglass Qilin 8,000T.
	t.test("the whole collection through the shop costs 9,052,705,022,546,500 Coins at full price (V3:163)", function()
		local total = 0
		for _, def in Catalog.list() do
			total += def.shopPrice or 0
		end
		local frosty = 2 * 66_000_000_000 + 2 * 76_900_000_000 + 200_000_000_000 + 512_000_000_000 + 20_000_000_000_000
		local lava = 2 * 2_000_000_000_000
			+ 2 * 2_300_000_000_000
			+ 6_000_000_000_000
			+ 15_300_000_000_000
			+ 600_000_000_000_000
		local prism = 2 * 26_600_000_000_000
			+ 2 * 30_700_000_000_000
			+ 80_000_000_000_000
			+ 205_000_000_000_000
			+ 8_000_000_000_000_000
		expect.equal(
			total,
			6 * 789_000 + 3 * 937_500 + 4 * 3_750_000 + 4 * 1_800_000_000 + 2 * 1_100_000_000_000 + frosty + lava + prism
		)
	end)

	t.test("copies replaced the duplicate refund (pens3 phase 5)", function()
		expect.equal(Config.Economy.DuplicatePolicy, "copy")
		expect.equal((Pricing :: any).duplicateRefund, nil)
	end)

	t.test("shopPrice: the Welcome price for a Common not owned yet, then the Catalog price", function()
		local welcome = Config.Economy.Pen.welcomePrice.Common
		expect.equal(welcome, 1_000) -- D1:202 said 3K; owner 2026-10-31: "Cheaper first + tip order"
		local owned: { [string]: any } = { kitty_bread = { at = 1, src = "starter" } }
		for _, def in Catalog.byRarity("Common") do
			if def.shopPrice ~= nil and def.boxMult == nil then -- the Soft Box's Commons (plan "50 squishies")
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

	-- Plan "50 squishies" (Frosty Box, 2026-11-10): the Welcome price is for the Soft Box's Commons only; a zone box's
	-- Common costs its full price from the first one.
	t.test("a zone box's Common has no Welcome price", function()
		local owned: { [string]: any } = {}
		for _, id in { "cone_cub", "slushy_seal" } do
			expect.equal(Pricing.shopPrice(id, owned), Catalog.get(id).shopPrice)
		end
		expect.equal(Pricing.shopPrice("toast", owned), Config.Economy.Pen.welcomePrice.Common)
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
