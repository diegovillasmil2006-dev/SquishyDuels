--!strict
-- Config.Economy: Coin amounts, limits and reward rules (DESIGN §6.1-§6.13). Shared, data only.
-- Every number is [P] (provisional, not playtested). Box contents and costs live in Boxes.luau, shop prices in
-- Catalog.luau, Robux coin bundles in Config.Monetization, quest templates and starter tasks in QuestDefs.luau.

local Economy = {
	startingCoins = 0,
	maxCoins = 1_000_000_000, -- Coins are integers clamped to [0, maxCoins]

	-- The closed list of reasons for EconomyService.grantCoins / trySpend (§6.1). "trainer" = Grip trainer upgrades
	-- (§17.5, Part 7; validator G6 checks it is listed). "debug" is Studio only.
	CoinReasons = {
		"squeeze",
		"duel_win",
		"duel_loss",
		"duel_draw",
		"quest",
		"starter",
		"daily",
		"refund",
		"robux",
		"box",
		"shop",
		"trainer",
		"debug",
	},

	-- Coins per paid squeeze by the equipped squishy's rarity; Catalog `squeezeCoins` may override (§6.2).
	-- Spec 2026-10-11 §5 (the user: "Less per squeeze, no limit"): every squeeze pays, so less each time (was 5 / 6 / 8
	-- / 10 under the hourly limit).
	CoinsByRarity = {
		Common = 1,
		Uncommon = 1,
		Epic = 2,
		Exclusive = 2,
	} :: { [string]: number },

	-- Squeeze earnings limit (§6.3): a rate limit, not a currency; never sold, never changed by passes or products.
	-- Each paid squeeze uses 1 point; points refill at perHour (even offline) up to burst. At 0 a squeeze pays
	-- emptyCoins (it still trains Grip, §17.3.1). New players start full (ProfileV1.squeezeLimit.value = burst).
	-- A paid squeeze pays Catalog.getSqueezeCoins + the pad's Config.Grip.Pads[tier].coinBonus (GripMath.squeezeCoins);
	-- validator G3 keeps that ceiling under Config.Grip.maxSqueezeCoinsPerHour for every limit setting.
	-- Math: shared SqueezeLimit (current / spend / full).
	-- Off since spec 2026-10-11 §5 (the user: "Less per squeeze, no limit"): every squeeze pays. The module and the
	-- profile field stay, dormant (SqueezeLimit also runs Double Grip and slow training).
	SqueezeLimit = {
		enabled = false,
		perHour = 600,
		burst = 300,
		emptyCoins = 0,
	},

	-- Duel rewards (§6.7), computed by Logic/DuelRewards and granted once on the transition into Result.
	DuelRewards = {
		win = 200,
		loss = 60,
		draw = 100,
		minOwnThrows = 3, -- server-accepted throws, for every outcome; a draw needs both players to reach it
		winMinActiveSeconds = 20, -- a bail before this is Cancelled (must be >= Duel.Rules.EarlyForfeitSeconds)
		lossMinActiveSeconds = 45,
		samePairFullRewards = 6, -- fully rewarded results per pair inside the rolling window (profile.samePair)
		samePairWindowSeconds = 3600,
		samePairMultiplier = 0.25, -- from the 7th result in the window, with duel.rewardsReduced
	},

	-- Daily rewards (§6.9). Server time only: dayIndex = floor(os.time() / 86400), reset at 00:00 UTC.
	Daily = {
		coinsByDay = { 100, 150, 200, 250, 300, 400, 500 }, -- streak days 1..7, then the cycle restarts at Day 1
		freeBoxDay = 7, -- also grants the free Treat Box, opened immediately
		freeBoxId = "treat", -- must be a free-only box in Boxes.luau
		GraceDays = 0, -- a missed day restarts the streak at Day 1 (name as in DESIGN §6.9)
	},

	-- Daily quests (§6.8). Templates and rewards are in QuestDefs.luau.
	Quests = {
		perDay = 3, -- slot 1 squeeze template, slot 2 duel template, slot 3 any template not already chosen
		freeSwapsPerDay = 1, -- no paid swaps, skips or rerolls, ever
		rolloverCheckSeconds = 30, -- how often online players are checked for quests.day ~= today
		equippedPickChance = 0.5, -- a template needing a squishy picks the equipped one with this chance (if owned)
		practiceTargetRepeatSeconds = 2, -- practice_hits: each target counts at most once per 2 s
	},

	-- Duplicate box results (§6.5). "exclude_owned" is the documented alternative and is not built.
	DuplicatePolicy = "refund" :: "refund" | "exclude_owned",
	DuplicateRefund = {
		Common = 100,
		Uncommon = 150,
		Epic = 300,
		Exclusive = 1000,
	} :: { [string]: number },
	AllowOpenWhenComplete = false, -- a box whose every item is owned cannot be opened (box.complete)
	MinSecondsBetweenOpens = 2, -- per player, plus one open in flight (keeps box writes inside the budget)

	-- Friendly tip after repeated losses (§6.13). Session memory only.
	LossTip = {
		lossStreak = 3, -- consecutive completed losses; draws leave the count unchanged, a win resets it
		minOwnThrows = 3, -- a loss counts only with >= 3 own accepted throws (forfeits and cancels never count)
		minSecondsBetween = 1200, -- 20 min
		maxPerSession = 2,
		textKey = "duel.lossTip",
	},
}

return Economy
