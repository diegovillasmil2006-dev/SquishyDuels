--!strict
-- Config.Economy.Pen: the pen (pens3 phase 1, 2026-10-17): the walking squishies that earn Coins every second, the
-- spots you buy at the sign and what one squishy earns. Shared, data only. Numbers from work/econ4 (Grip x1.1 per
-- level, owner decision): the spot prices are final_hagb_grip110.json "penPrice" (out5_grip110.txt "SPOTS"), the
-- multipliers ECONOMY_V4's (out5_grip110.txt "COATINGS"). [P] where marked. A child module, so Config/init does not
-- grow (it is near Roblox's 200,000-character Source limit): exposed through Config/Economy and checked by
-- Config/ValidatePen when PenService starts. Math: Shared/PenMath. Pens3 phases 7-8: selling, the buy-back (below).
-- Pens3 phase 11: the shelf rows and the TOP spot (below).

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

	-- Pens3 phase 7 (selling, D1:217-225, V3:164): a squishy sells for sellPrice[its rarity] × sellFormMult[form + 1]
	-- Coins (Golden ×3, Rainbow ×9: they are 3 and 9 copies; food and coatings are not refunded). V3's Rare 300K comes
	-- with the Rare tier (phase 22). ValidatePen keeps each price below what that rarity can be bought for.
	sellPrice = { Common = 1_000, Uncommon = 150_000, Epic = 90_000_000, Exclusive = 225_000_000_000 } :: {
		[string]: number,
	},
	sellFormMult = { 1, 3, 9 },
	sellMaxIds = 50, -- one SellItems call sells at most this many squishies
	-- Hold-to-confirm (D1:222): selling a squishy of this form or above, this level or above, or this rarity or above.
	sellHold = { form = 1, level = 10, rarity = "Epic" },
	-- The buy-back: a sale can be bought back for this long, for exactly what it paid, once; at most buyBackMax wait
	-- (toyBoxMax + placedMax, so a whole Sell All can be undone), the oldest falling off first.
	buyBackSeconds = 600,
	buyBackMax = 71,

	-- Pens3 phase 11 (the show-off shelf, V3:144-151; prices final_hagb_grip110.json "shelfRowPrice" / "topPrice",
	-- the plan's 31M / 250B / 11T / 140T exactly): rows of shelfRowSpots spots, shelfStartRows open from the start,
	-- the next one bought at shelfRowPrices[row] up to shelfMaxRows, then the one TOP spot at topPrice (the last buy).
	-- They earn like the pen's squishies. Slots (PenMath): the pen 1..maxSpots, the shelf maxSpots + 1 .. (row r:
	-- maxSpots + shelfRowSpots × (r - 1) + 1 ..), the TOP spot placedMax (ValidatePen keeps placedMax = maxSpots +
	-- shelfMaxRows × shelfRowSpots + 1).
	shelfStartRows = 1,
	shelfMaxRows = 4,
	shelfRowSpots = 2,
	shelfRowPrices = {
		[2] = 31_000_000,
		[3] = 250_000_000_000,
		[4] = 11_000_000_000_000,
	} :: { [number]: number },
	topPrice = 140_000_000_000_000,
}

return Pen
