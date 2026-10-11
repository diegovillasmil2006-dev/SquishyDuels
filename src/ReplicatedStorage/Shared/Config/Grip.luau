--!strict
-- Config.Grip: Grip training (DESIGN §17, approved 2026-10-05). Shared, data only. Every value is [P].
-- Grip is a lobby-only stat: never a currency, never sold, never read by duel or matchmaking code (§17.2).
-- Pads are indexed by GripTier (WorldLayout gives each squeeze station its tier). Config.validate checks the rules
-- G1 (levels), G2 (pads), G4 (trainer), G5 (caps and timers), G8 (world, with WorldLayout) and G10 (giant-pad
-- animation, with Config.Anim.giantPad) from Part 3 on; G3 (Coin ceiling), G6 (Strings names) and G9 (slow training)
-- from Part 5; G6's wiring half ("trainer" Coin reason, the TrainerUpgrade rate), G7 (Robux allowlist) and G7b (coin
-- bundles stay off while Grip is on and allowBundlesWithTrainer is false) from Part 7.
-- Texts live in Strings: pad names `grip.pad.<key>`, ranks `grip.rank.<key>`, trainers `grip.trainer.<key>`.
-- Math: shared GripMath (levels, ranks, pads, Grip and Coins per squeeze, slow-training ticks, minutes, next goal) and
-- SqueezeLimit (the Double Grip and slow-training timers).

export type Pad = {
	key: string, -- Strings grip.pad.<key>; giant pads also use it as WorldLayout.GiantPads key / PadKey
	level: number, -- Grip Level that unlocks it
	coinBonus: number, -- added to a paid squeeze's Coins
	gripPercent: number, -- Grip per squeeze, % of the trainer value
}

export type Trainer = {
	key: string, -- Strings grip.trainer.<key>
	gripPerSqueeze: number,
	cost: number, -- Coins
	level: number, -- Grip Level needed to buy it
}

export type Limit = { enabled: boolean, perHour: number, burst: number }

local Grip = {
	enabled = true,
	maxGrip = 1_000_000_000,
	maxLevel = 50,
	-- Total Grip needed for each level (index = level). G1: the cost of a level never drops from one to the next.
	LevelTotals = {
		0,
		1000,
		2500,
		5500,
		12000,
		19000,
		28000,
		42000,
		66000,
		100000,
		140000,
		185000,
		235000,
		290000,
		350000,
		480000,
		650000,
		880000,
		1180000,
		1550000,
		1950000,
		2370000,
		2810000,
		3270000,
		3770000,
		4330000,
		4970000,
		5730000,
		6730000,
		8000000,
		9600000,
		11600000,
		13900000,
		16500000,
		19300000,
		22300000,
		25400000,
		28600000,
		32000000,
		36000000,
		40500000,
		45500000,
		50800000,
		56400000,
		62400000,
		68900000,
		75900000,
		83400000,
		91400000,
		100000000,
	},
	-- Rank names (always text plus colour): Strings grip.rank.<key>.
	Ranks = {
		{ level = 1, key = "soft" },
		{ level = 10, key = "firm" },
		{ level = 20, key = "strong" },
		{ level = 30, key = "iron" },
		{ level = 40, key = "titan" },
		{ level = 50, key = "master" },
	},
	-- Index = GripTier: 1 = the Foam Mats (squeeze_01..06), 2-4 = the giant pads (squeeze_07..09).
	-- Spec 2026-10-11 §5: squeezing pays anywhere in the lobby as tier 1 (no boost); a pad gives the boost. Coin bonuses
	-- +0 / +1 / +2 / +3 (the user, 2026-10-11; were +0 / +1 / +3 / +5).
	Pads = {
		{ key = "foam", level = 1, coinBonus = 0, gripPercent = 100 },
		{ key = "jelly", level = 5, coinBonus = 1, gripPercent = 150 },
		{ key = "marshmallow", level = 15, coinBonus = 2, gripPercent = 200 },
		{ key = "royal", level = 30, coinBonus = 3, gripPercent = 300 },
	} :: { Pad },
	-- Trainer upgrades, bought in order with Coins (reason "trainer", Part 7); each needs a Grip Level.
	Trainer = {
		{ key = "foam", gripPerSqueeze = 10, cost = 0, level = 1 },
		{ key = "sponge", gripPerSqueeze = 15, cost = 1000, level = 3 },
		{ key = "rubber", gripPerSqueeze = 20, cost = 4000, level = 6 },
		{ key = "spring", gripPerSqueeze = 30, cost = 12000, level = 10 },
		{ key = "jelly", gripPerSqueeze = 40, cost = 25000, level = 15 },
		{ key = "steel", gripPerSqueeze = 55, cost = 50000, level = 20 },
		{ key = "gold", gripPerSqueeze = 75, cost = 90000, level = 28 },
		{ key = "diamond", gripPerSqueeze = 100, cost = 150000, level = 36 },
	} :: { Trainer },
	-- Double Grip (G-B): a timer like Economy.SqueezeLimit, filled only by time; new accounts start full.
	Rested = { enabled = true, perHour = 240, burst = 1200, mult = 2 },
	-- Slow training on a pad (§17.3.6): never Coins, never quest progress, never doubled.
	Afk = {
		enabled = true,
		tickSeconds = 10,
		percentPerTick = 125, -- of one squeeze's Grip, rounded down
		perHour = 180, -- the bank: 1 point per paid tick, refills 3 a minute ...
		burst = 120, -- ... up to 120 (new accounts start full)
		padMargin = 1, -- studs beyond a pad's footprint that still count as "on it"
		heightAbove = 6, -- root part height window above the pad top
		maxShareOfActive = 25, -- G9: at most this % of the holding rate
	},
	-- Hold-to-squeeze (client only, §17.3.2). Every click pays (2026-10-06): a click squeezes at once; holding repeats
	-- at a relaxed rhythm of one full squeeze animation, repeatSeconds (validator: >= the release pop end of every
	-- rarity in Config.Anim.squeeze, 0.43 s), so clicking can be faster than holding.
	-- Reading: the Grip pacing estimates of DESIGN §17.4 assumed one squeeze per 1.5 s (the old Squeeze.cycleSeconds).
	-- Grip per squeeze is unchanged, so holding now trains about 1.5 / repeatSeconds (3.3x) faster and fast clicking
	-- up to 12 × 1.5 = 18x; the "holding rate" rules (G5 Double Grip refill, G9 slow-training share,
	-- GripMath.restedMinutes) now use repeatSeconds in place of the old cycle.
	Hold = { maxSeconds = 600, queuedSeconds = 60, repeatSeconds = 0.45, leadSeconds = 0.05, replyGraceSeconds = 0.5 },
	-- G3 ceiling. The user's decision of 2026-10-11 ("Less per squeeze, no limit"; spec 2026-10-11 §5): with no hourly
	-- limit every squeeze at the anti-autoclicker cap pays, 43,200 × (2 squeeze Coins + 3 pad bonus) = 216,000 Coins an
	-- hour, the real ceiling. (Was 9,000 under the limit.)
	maxSqueezeCoinsPerHour = 216_000,
	-- Spec 2026-10-11 §5: the server logs a warning (log only, like gripAlertPerHour) when one player's squeeze Coins
	-- pass this in a rolling hour. Validator: a whole number in 1..maxSqueezeCoinsPerHour.
	squeezeCoinsAlertPerHour = 50_000,
	maxGripPerEvent = 600, -- Trainer[8] × 300% × Rested.mult; also covers a slow-training tick (375) (G5)
	-- (43200 + 12) × 600: rolling-hour anomaly log, at the most squeezes the server can accept in an hour (the
	-- anti-autoclicker cap, 12 per second, plus its burst) at the biggest Grip event, so honest fast clicking never
	-- trips it. (Was (2400 + 2) × 600 with the old 1.5 s cycle.)
	gripAlertPerHour = 25_927_200,
	goalUpgradeMaxCostWhileCollecting = 5000, -- next-goal rule (§17.5)
	allowBundlesWithTrainer = false, -- G-E / G7b; user decision: coin bundles stay off while Grip is on
	-- Lobby nameplate "Lv 23 · Strong Grip" (NameplateController, §17.7): shown within maxDistance studs, hidden when
	-- the viewer's or the target's SD_DuelPhase ~= "". Reading (DESIGN gives no numbers): it sits headOffsetStuds above
	-- the head and pops to popScale for popSeconds when the level changes (still under ReducedMotion).
	-- Part 8 polish (§17.11; Readings, DESIGN lists no details): it fades out over the last fadeStuds studs before
	-- maxDistance (transparency only, so also under ReducedMotion), refreshed every checkSeconds by one loop (never per
	-- frame), and the local player's own plate hides while the camera is within ownHideStuds of its Head (first
	-- person). Validator: 0 < fadeStuds < maxDistance, checkSeconds > 0, ownHideStuds >= 0.
	Nameplate = {
		enabled = true,
		maxDistance = 60,
		headOffsetStuds = 2,
		popScale = 1.2,
		popSeconds = 0.3,
		fadeStuds = 10,
		checkSeconds = 0.25,
		ownHideStuds = 1.5,
	},
	-- Jelly gates (built open; WorldBinder closes them locally while the viewer's level is too low, §17.6).
	Gate = { lockedTransparency = 0.45, openTransparency = 0.85, antiTrapPadding = 1, recheckSeconds = 0.5 },
	idleReminderSeconds = 900, -- idle card after 15 min of LocalPlayer.Idled
	unlockWaypointSeconds = 20,
	welcomeBackMinGain = 300, -- Double Grip points gained since the last save that show the welcome-back toast
}

return Grip
