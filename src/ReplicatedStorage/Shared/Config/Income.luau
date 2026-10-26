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

return Income
