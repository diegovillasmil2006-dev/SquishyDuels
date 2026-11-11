--!strict
-- Config.Economy.Income: the INCOME upgrade (INCOME step 1, 2026-10-26; owner 2026-10-24 "2 upgrades, buy both",
-- "C: price x3, +7%"; Decisions, Economy). Shared, data only. A child module, so Config/init does not grow: exposed
-- through Config/Economy and checked by Config/ValidateIncome when PenService starts. Math: Shared/PenMath.
-- Two lines, each bought one level at a time with Coins (PenService.buyIncome), saved in profile.pen.income:
-- * coins (SQUISHY COINS): x boost a level on what the squishies earn (the pen, the shelf, the TOP spot, the coins
--   while away): PenMath.rate.
-- * all (ALL EARNINGS): x boost a level on that too and on the squeeze value: squeezes, duels and matches, the highway,
--   Grip and every reward counted in squeezes (PenMath.squeezeValue).
-- Curve C (the study, income-gear-curves-handover.md): price of level k = start x step^(k - 1) rounded to 2 significant
-- digits (COINS 500K x3.2, ALL 2.5M x3), 20 levels. The gear prices (Config/Gear) were tuned with these on. [P].

local Income = {
	coins = {
		boost = 1.07,
		prices = {
			500_000,
			1_600_000,
			5_100_000,
			16_000_000,
			52_000_000,
			170_000_000,
			540_000_000,
			1_700_000_000,
			5_500_000_000,
			18_000_000_000,
			56_000_000_000,
			180_000_000_000,
			580_000_000_000,
			1_800_000_000_000,
			5_900_000_000_000,
			19_000_000_000_000,
			60_000_000_000_000,
			190_000_000_000_000,
			620_000_000_000_000,
			2_000_000_000_000_000,
		},
	},
	all = {
		boost = 1.05,
		prices = {
			2_500_000,
			7_500_000,
			23_000_000,
			68_000_000,
			200_000_000,
			610_000_000,
			1_800_000_000,
			5_500_000_000,
			16_000_000_000,
			49_000_000_000,
			150_000_000_000,
			440_000_000_000,
			1_300_000_000_000,
			4_000_000_000_000,
			12_000_000_000_000,
			36_000_000_000_000,
			110_000_000_000_000,
			320_000_000_000_000,
			970_000_000_000_000,
			2_900_000_000_000_000,
		},
	},
}

-- Big job item 10 (2026-11-10): the 4 TOYS (the owner 2026-10-15: "Toys: Bouncy Ball, Squeaky Ring, Rubber Duck,
-- Spinning Top"; 2026-10-18: "Toys come in BOTH kinds: some boost a squishy (coins), some boost you (throws, Grip,
-- duel pay)"). The old plan's paper is lost (it only survives as "Squeaky Ring 2" in Config/Grip), so the rest is
-- Claude's call (vault page "Big job 2026-11" > My calls): each toy is one more line of this table (`toy = true`),
-- bought and saved exactly like the two above (PenBuyIncome, profile.pen.income; a line a save does not have reads
-- 0), one for each kind of earning:
-- * duck (RUBBER DUCK): what the squishies earn (PenMath.rate), on top of SQUISHY COINS;
-- * ball (BOUNCY BALL): the Coins of a highway landing (HighwayService);
-- * ring (SQUEAKY RING): Grip from squeezes, matches and the highway (PenMath.squeezeGrip);
-- * top (SPINNING TOP): the Coins of a duel or a match (EconomyService's duel grant).
-- 10 levels of x 2^(1/10) each, so a full toy is x2 (the old "Ring 2"), on one price list: 2M x9 a level. Dearer per
-- percent than the lines above on purpose: a toy is a luxury sink, and no toy moves the tuned gear and zone times
-- by more than its x2 at the very end (LihFolk vault: derive prices from one income model; cap each boost bucket).
local TOY_BOOST = 2 ^ (1 / 10)
local TOY_PRICES = {
	2_000_000,
	18_000_000,
	160_000_000,
	1_500_000_000,
	13_000_000_000,
	120_000_000_000,
	1_100_000_000_000,
	9_600_000_000_000,
	86_000_000_000_000,
	770_000_000_000_000,
}
for _, toy in { "duck", "ball", "ring", "top" } do
	-- `full`: the boost with every level bought (PenMath.incomeMult counts a toy from it, so it is exactly x2)
	(Income :: any)[toy] = { boost = TOY_BOOST, full = 2, prices = table.clone(TOY_PRICES), toy = true }
end

return Income
