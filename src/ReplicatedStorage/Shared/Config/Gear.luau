--!strict
-- Config.Economy.Gear: the gear (gear step 2, 2026-10-26; owner 2026-10-24 "Build the gear next", 2026-10-26 "Yes, use
-- these prices" + "Use the fixed prices", "Traps + armor now"). Shared, data only. A child module, so Config/init does
-- not grow: exposed through Config/Economy and checked by Config/ValidateGear when HighwayService starts. Math:
-- Shared/GearMath. Only the highway throw uses it (owner 2026-10-16: gear = highway perks; duels are untouched).
-- Four lines, each bought one step at a time with Coins (HighwayService.buyGear): the held launcher and the platform
-- launcher (the owner's names: Strings), arm gear, and armor. The first three are power lines: each step multiplies
-- the throw power, tiers 1-5 by x2 a step (a base piece + 3 stars = x16 a tier, Hit a Golf Ball), tiers 6-7 in 8
-- smaller steps of x sqrt 2 ("shorter late waits"). Armor is one piece a tier and adds no power: it makes traps take
-- less. Numbers: gear step 1's model (today's Grip, traps and armor, INCOME curve C; Decisions 2026-10-26): Boba Lagoon
-- at 14 min, Divine Heaven at 25 h, the Golden Gates at 79 h of a 2 h a day player. Every price is [P].

local Gear = {
	-- The steps of each tier of a power line (7 tiers, one a highway zone).
	tierSteps = { 4, 4, 4, 4, 4, 8, 8 },
	tierPower = 16, -- a whole tier multiplies its line's throw power by this
	-- The Coins of each step of a launcher line (held = platform), strictly rising.
	launcherPrices = {
		-- Tier 1 (Lolli Sling / Gumdrop Catapult) .. tier 5 (Magma Snap / Volcano Vaulter): x2.2 a step.
		18_000,
		40_000,
		87_000,
		190_000,
		13_000_000,
		29_000_000,
		63_000_000,
		140_000_000,
		220_000_000,
		480_000_000,
		1_100_000_000,
		2_300_000_000,
		15_000_000_000,
		33_000_000_000,
		73_000_000_000,
		160_000_000_000,
		400_000_000_000,
		880_000_000_000,
		1_900_000_000_000,
		4_300_000_000_000,
		-- Tier 6 (Prism Popper / Starbeam Trebuchet) and tier 7 (Halo Hurler / Angel Ascender): 8 smaller steps.
		4_700_000_000_000,
		6_000_000_000_000,
		7_700_000_000_000,
		9_900_000_000_000,
		13_000_000_000_000,
		16_000_000_000_000,
		21_000_000_000_000,
		26_000_000_000_000,
		47_000_000_000_000,
		63_000_000_000_000,
		84_000_000_000_000,
		110_000_000_000_000,
		150_000_000_000_000,
		200_000_000_000_000,
		270_000_000_000_000,
		350_000_000_000_000,
	},
	armGearShare = 0.5, -- an arm gear step costs this x the launcher step (whole Coins: the launcher prices are even)
	-- The Coins of each armor piece (one a tier), strictly rising.
	armorPrices = {
		9_000,
		6_500_000,
		110_000_000,
		7_500_000_000,
		200_000_000_000,
		3_400_000_000_000,
		35_000_000_000_000,
	},
	-- Traps (owner 2026-10-17: "Harsh" without armor): the chance a throw is trapped, by the zone it would reach, and
	-- what a trap takes: a trap in zone n halves the throw power (n + trapBase - armor pieces) times (at least 0).
	trapChance = { 0.08, 0.11, 0.14, 0.18, 0.22, 0.26, 0.30 },
	trapBase = 1,
}

return Gear
