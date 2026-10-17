--!strict
-- Config.Economy.Food: food and levels (pens3 phase 9, 2026-10-17). Shared, data only. A squishy goes from level L
-- to L + 1 by eating food; the food of each band of levels is sold once you reach its biome, so the highest level is
-- levelsPerBiome × the biomes reached (PenMath.levelCap). A child module, so Config/init does not grow: exposed
-- through Config/Economy and checked by Config/ValidateFood when PenService starts. Math: Shared/PenMath.
-- Numbers from work/pen2/ECONOMY_V2.md "B. Formulas" (V2:214-224; V3:169 keeps them): level L -> L + 1 is worth
-- base × growth^(L - 1) Coins; a food's piece costs the first step of its band (Butter Bun 6.4K = 400 × 1.36^9,
-- rounded as V2 rounds it), and the step `i` of a band takes pieces[i] of it (round(growth^(i - 1)); the 1-10 band
-- has 9 steps). The piece table wins over V2's rounded band totals: a whole band costs sum(pieces) × its price
-- (16.8K, 371.2K, 8.0M, 174M, 3.77B, 81.2B, 1.74T against V2's 17K, 365K, 7.9M, 171M, 3.7B, 80B, 1.7T).

local Food = {
	base = 400,
	growth = 1.36,
	levelsPerBiome = 10,
	pieces = { 1, 1, 2, 3, 3, 5, 6, 9, 12, 16 },
	-- In band order. A food feeds every step from level `from` up to `to` (from <= level < to); its step i (level =
	-- from + i - 1) takes pieces[i] pieces of `price` Coins each.
	foods = {
		{ id = "candy_drop", nameKey = "food.candyDrop.name", price = 400, from = 1, to = 10 },
		{ id = "butter_bun", nameKey = "food.butterBun.name", price = 6_400, from = 10, to = 20 },
		{ id = "boba_pearl_pop", nameKey = "food.bobaPearlPop.name", price = 138_000, from = 20, to = 30 },
		{ id = "frosty_scoop", nameKey = "food.frostyScoop.name", price = 3_000_000, from = 30, to = 40 },
		{ id = "lava_truffle", nameKey = "food.lavaTruffle.name", price = 65_000_000, from = 40, to = 50 },
		{ id = "prism_tart", nameKey = "food.prismTart.name", price = 1_400_000_000, from = 50, to = 60 },
		{ id = "halo_puff", nameKey = "food.haloPuff.name", price = 30_000_000_000, from = 60, to = 70 },
	} :: { { id: string, nameKey: string, price: number, from: number, to: number } },
	maxPieces = 10_000, -- [P] the most pieces of one food a save holds (sanitize clamps; BuyFood refuses past it)
	maxBuy = 100, -- [P] the most pieces one BuyFood buys
}

return Food
