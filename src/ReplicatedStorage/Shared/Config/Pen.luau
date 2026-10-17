--!strict
-- Config.Economy.Pen: the pen (pens3 phase 1, 2026-10-17): the walking squishies that earn Coins every second, the
-- spots you buy at the sign and what one squishy earns. Shared, data only. Numbers from work/econ4 (Grip x1.1 per
-- level, owner decision): the spot prices are final_hagb_grip110.json "penPrice" (out5_grip110.txt "SPOTS"), the
-- multipliers ECONOMY_V4's (out5_grip110.txt "COATINGS"). [P] where marked. A child module, so Config/init does not
-- grow (it is near Roblox's 200,000-character Source limit): exposed through Config/Economy and checked by
-- Config/ValidatePen when PenService starts. Math: Shared/PenMath.

local Pen = {
	startSpots = 3, -- open from the start
	maxSpots = 12,
	-- The Coins of spot n (startSpots + 1 .. maxSpots), strictly rising.
	spotPrices = {
		[4] = 1_500,
		[5] = 3_100,
		[6] = 4_650,
		[7] = 2_300_000,
		[8] = 2_100_000_000,
		[9] = 7_900_000_000,
		[10] = 63_000_000_000,
		[11] = 2_200_000_000_000,
		[12] = 5_600_000_000_000,
	} :: { [number]: number },

	-- One squishy earns coinsPerPower × its squishy power (Catalog.getPower) × formMult[form + 1] × coatMult[coat + 1]
	-- × levelGain^(level - 1) Coins a second.
	coinsPerPower = 10,
	levelGain = 1.15,
	formMult = { 1, 2, 4 }, -- form 0 plain, 1 Golden, 2 Rainbow
	coatMult = { 1, 1.5, 2, 3, 4, 6, 8, 12 }, -- coat 0 none, then Wax, Glitter, Jelly, Frost, Chrome, Neon, Galaxy
	minSqueezeValue = 10, -- an own squeeze, and every reward counted in squeezes, is worth at least this
	maxLevel = 70, -- 10 levels for each of the 7 biomes
	toyBoxMax = 50, -- unplaced squishies (D1:254-258: at the cap paid opens and shop buys stop, free ones wait)
	placedMax = 21, -- 12 pen spots + 8 shelf spots + the TOP spot (phase 11)

	tickSeconds = 1, -- the pen pays every second
	maxTickSeconds = 10, -- [P] a server hitch pays at most this much time at once
	buyCooldownSeconds = 1, -- the server refuses a spot buy this soon after the last one
	signHoldSeconds = 0.5, -- [P] the sign's prompt is a hold, so a kid walking past never buys by accident

	-- Pens3 phase 4 (owner decision): time away pays this share of the pen's Coins a second as saved at the last save
	-- (profile.pen.awayRate), for every second away, with no limit and no idle rule (PenMath.awayCoins).
	awayRate = 0.05,

	-- Pens3 phase 5 (copies). A free squishy (a gift, the day-7 Royal Box) that finds the Toy Box full waits in
	-- profile.giftQueue (kind ids, oldest first) and drops in as soon as there is room; at most this many wait. [P]
	giftQueueMax = 50,
	-- The first squishy of each kind of these rarities costs this in the shop while the kind is not owned (D1:202,
	-- "Welcome price: first one 3K"; it never runs out). ValidatePen keeps it at or below each one's shopPrice.
	welcomePrice = { Common = 3_000 } :: { [string]: number },
	-- The free gift of the first play (SIM:226): this squishy once per account (profile.gifts.frog), this many seconds
	-- into a session.
	frogGift = { kind = "strawberry_frog", seconds = 180 },
}

return Pen
