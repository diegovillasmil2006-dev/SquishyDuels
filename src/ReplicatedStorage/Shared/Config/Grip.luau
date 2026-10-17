--!strict
-- Config.Grip: Grip training (DESIGN §17, approved 2026-10-05). Shared, data only. Every value is [P].
-- Grip is a lobby-only stat: never a currency, never sold, never read by duel or matchmaking code (§17.2).
-- Pads are indexed by GripTier (WorldLayout gives each squeeze station its tier). Config.validate checks the rules
-- G1 (levels), G2 (pads), G5 (caps and timers) and G8 (world, with WorldLayout) from Part 3 on; G3 (squeeze ceiling)
-- and G6 (Strings names) from Part 5; G7 (Robux allowlist)
-- and G7b (coin bundles stay off while Grip is on and allowCoinBundles is false) from Part 7.
-- Big-number progression (spec 2026-10-12, Phase 1: numbers only): Lv 1-100 and 9 Qa of Grip, five ranks above Lv 50
-- and G3 as a squeeze count (its Capsule block went in pens3 phase 3). Since Phase 3 a pad no longer changes
-- what an own squeeze pays (the pen's squeeze value, PenMath). Phase 6 removed
-- slow training (the Afk block and G9); the pad test's padMargin / heightAbove moved to Config.Squeeze. Then it removed
-- the trainers (the Trainer block, its next-goal price rule, G4 and G6's wiring half), and the giant pads and their
-- Jelly gates (Pads rows 2-4, the Gate block, unlockWaypointSeconds, G10): only the Foam Mats row is left.
-- Texts live in Strings: pad names `grip.pad.<key>`, ranks `grip.rank.<key>`.
-- Math: shared GripMath (levels, ranks, minutes, next goal) and SqueezeLimit (the Double Grip timer).

export type Pad = {
	key: string, -- Strings grip.pad.<key>
	level: number, -- Grip Level that unlocks it (G2: 1, the Foam Mats)
	coinBonus: number, -- read by G2 only since Phase 6 (Foam Mats: 0; was added to a paid squeeze's Coins)
	gripPercent: number, -- read by G2 only since Phase 6 (Foam Mats: 100; was a squeeze's share of the trainer's Grip)
}

export type Limit = { enabled: boolean, perHour: number, burst: number }

local Grip = {
	enabled = true,
	maxGrip = 9_000_000_000_000_000, -- 9 Qa (spec 2026-10-12 §12; was 1B)
	maxLevel = 100, -- spec 2026-10-12 §10 (was 50)
	-- Total Grip needed for each level (index = level): the spec 2026-10-12 appendix exactly. G1: the totals rise
	-- strictly (that table makes Lv 3 and Lv 11 cost less than the level before, so G1 no longer forbids that).
	LevelTotals = {
		-- Lv 1-10
		0,
		1000,
		1700,
		3000,
		5100,
		8700,
		15_000,
		26_000,
		44_000,
		76_000,
		-- Lv 11-20
		100_000,
		130_000,
		170_000,
		220_000,
		290_000,
		380_000,
		500_000,
		650_000,
		850_000,
		1_100_000,
		-- Lv 21-30
		1_400_000,
		1_800_000,
		2_200_000,
		2_800_000,
		3_600_000,
		4_500_000,
		5_700_000,
		7_200_000,
		9_100_000,
		11_000_000,
		-- Lv 31-40
		15_000_000,
		19_000_000,
		25_000_000,
		32_000_000,
		41_000_000,
		52_000_000,
		67_000_000,
		87_000_000,
		110_000_000,
		140_000_000,
		-- Lv 41-50
		180_000_000,
		220_000_000,
		270_000_000,
		330_000_000,
		400_000_000,
		500_000_000,
		610_000_000,
		750_000_000,
		920_000_000,
		1_100_000_000,
		-- Lv 51-60
		1_400_000_000,
		1_800_000_000,
		2_300_000_000,
		3_000_000_000,
		3_800_000_000,
		4_900_000_000,
		6_200_000_000,
		8_000_000_000,
		10_000_000_000,
		13_000_000_000,
		-- Lv 61-70
		17_000_000_000,
		21_000_000_000,
		27_000_000_000,
		35_000_000_000,
		44_000_000_000,
		57_000_000_000,
		72_000_000_000,
		92_000_000_000,
		120_000_000_000,
		150_000_000_000,
		-- Lv 71-80
		190_000_000_000,
		230_000_000_000,
		280_000_000_000,
		340_000_000_000,
		420_000_000_000,
		510_000_000_000,
		630_000_000_000,
		770_000_000_000,
		950_000_000_000,
		1_200_000_000_000,
		-- Lv 81-90
		1_600_000_000_000,
		2_100_000_000_000,
		2_800_000_000_000,
		3_700_000_000_000,
		4_900_000_000_000,
		6_600_000_000_000,
		8_800_000_000_000,
		12_000_000_000_000,
		16_000_000_000_000,
		21_000_000_000_000,
		-- Lv 91-100
		28_000_000_000_000,
		38_000_000_000_000,
		50_000_000_000_000,
		67_000_000_000_000,
		90_000_000_000_000,
		120_000_000_000_000,
		160_000_000_000_000,
		210_000_000_000_000,
		290_000_000_000_000,
		380_000_000_000_000,
	},
	-- Rank names (always text plus colour): Strings grip.rank.<key>.
	Ranks = {
		{ level = 1, key = "soft" },
		{ level = 10, key = "firm" },
		{ level = 20, key = "strong" },
		{ level = 30, key = "iron" },
		{ level = 40, key = "titan" },
		{ level = 50, key = "master" },
		-- Spec 2026-10-12 §10: the ranks above Lv 50.
		{ level = 60, key = "legend" },
		{ level = 70, key = "mythic" },
		{ level = 80, key = "cosmic" },
		{ level = 90, key = "galaxy" },
		{ level = 100, key = "infinite" },
	},
	-- Index = GripTier: 1 = the Foam Mats (squeeze_01..06), the only tier since the giant pads went (Phase 6).
	-- Spec 2026-10-11 §5: squeezing pays anywhere in the lobby as tier 1 (no boost).
	Pads = {
		{ key = "foam", level = 1, coinBonus = 0, gripPercent = 100 },
	} :: { Pad },
	-- Double Grip (G-B): a timer like Economy.SqueezeLimit, filled only by time; new accounts start full.
	Rested = { enabled = true, perHour = 240, burst = 1200, mult = 2 },
	-- Hold-to-squeeze (client only, §17.3.2): a click squeezes at once; holding repeats at a relaxed rhythm of one full
	-- squeeze animation, repeatSeconds (validator: >= the release pop end of every rarity in Config.Anim.squeeze,
	-- 0.43 s). Batch 1 #2: it is also the paid-squeeze cap (Config.Squeeze.cycleSeconds), so clicking pays no faster
	-- than holding.
	-- Reading: the Grip pacing estimates of DESIGN §17.4 assumed one squeeze per 1.5 s (the old Squeeze.cycleSeconds).
	-- Grip per squeeze is unchanged, so squeezing now trains at most about 1.5 / repeatSeconds (3.3x) faster; the
	-- "holding rate" rules (G5 Double Grip refill, GripMath.restedMinutes) use repeatSeconds.
	Hold = { maxSeconds = 600, queuedSeconds = 60, repeatSeconds = 0.45, leadSeconds = 0.05, replyGraceSeconds = 0.5 },
	-- G3 (spec 2026-10-12 §12): a squeeze count, no longer a Coin number, because Coins per squeeze now grow. The most
	-- paid squeezes the server accepts in an hour: the hold rhythm, 3600 / 0.45 (Batch 1 #2; was 43,200 at the old
	-- 12-a-second cap, before that maxSqueezeCoinsPerHour, 216,000 Coins).
	maxSqueezesPerHour = 8_000,
	-- Spec 2026-10-12 §12: the server logs a warning (log only, like gripAlertPerHour) when one player's paid squeezes
	-- pass this in a rolling hour (was 50,000 squeeze Coins, then 30,000). Batch 1 #2: the paid cap's whole hour, so
	-- only riding the cap with no break for an hour (more than the client sends) passes it. Validator: a whole number
	-- in 1..maxSqueezesPerHour.
	squeezeAlertPerHour = 8_000,
	-- Pens3 phase 2 (ECONOMY_V3): at least 4 × the top squeeze value (Double Grip 2 × Squeaky Ring 2: 4.0e10 at the
	-- top SV 9.96e9, G5 computes it from Config.Economy.Pen). Was CP(100) × 2 = 1,841,051,178 (the capsules).
	maxGripPerEvent = 500_000_000_000,
	-- [P] Rolling-hour anomaly log (log only). The honest top hour at SV 9.9B is about 3.3e14 (8,000 squeezes × Ring 2,
	-- Double Grip's 1,440 doubled squeezes, 120 highway landings × 60 squeezes × Ring 2); the old 7.96e13 flagged it.
	gripAlertPerHour = 400_000_000_000_000,
	-- G-E / G7b (lobby spec 2026-10-11 §11; was allowBundlesWithTrainer, then allowBundlesWithCapsules until pens3
	-- phase 3): coin bundles stay off while Grip is on.
	allowCoinBundles = false,
	-- Lobby nameplate "Lv 23 · Strong Grip" (NameplateController, §17.7): shown within maxDistance studs, hidden when
	-- the viewer's or the target's SD_DuelPhase ~= "". Reading (DESIGN gives no numbers): it sits headOffsetStuds above
	-- the head and pops to popScale for popSeconds when the level changes (still under ReducedMotion).
	-- Part 8 polish (§17.11; Readings, DESIGN lists no details): it fades out over the last fadeStuds studs before
	-- maxDistance (transparency only, so also under ReducedMotion), refreshed every checkSeconds by one loop (never per
	-- frame), and the local player's own plate hides while the camera is within ownHideStuds of its Head (first
	-- person). Validator: 0 < fadeStuds < maxDistance, checkSeconds > 0, ownHideStuds >= 0.
	Nameplate = {
		-- Off since 2026-10-15 (jayyyyy: distracting above heads). Diego's HUD shows the Grip level on the player's own
		-- screen ("GRIP n", UI FINAL H:92-96) and nothing above heads, like Ride a Pet.
		enabled = false,
		maxDistance = 60,
		headOffsetStuds = 2,
		popScale = 1.2,
		popSeconds = 0.3,
		fadeStuds = 10,
		checkSeconds = 0.25,
		ownHideStuds = 1.5,
	},
	idleReminderSeconds = 900, -- idle card after 15 min of LocalPlayer.Idled
	welcomeBackMinGain = 300, -- Double Grip points gained since the last save that show the welcome-back toast
}

return Grip
