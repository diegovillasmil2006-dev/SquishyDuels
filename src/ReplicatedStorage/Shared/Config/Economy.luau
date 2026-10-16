--!strict
-- Config.Economy: Coin amounts, limits and reward rules (DESIGN §6.1-§6.13). Shared, data only.
-- Every number is [P] (provisional, not playtested). Box contents and costs live in Boxes.luau, shop prices in
-- Catalog.luau, Robux coin bundles in Config.Monetization, quest templates and starter tasks in QuestDefs.luau.
-- Big-number progression (spec 2026-10-12, Phase 1: numbers only): Coins up to 9 Qa, squishy power by rarity (the
-- squeeze value, shared CapsuleMath), duel rewards counted in squeezes, refunds as a share of the box price and the
-- "capsule" Coin reason. Since Phase 3 every reward counted in squeezes pays CapsuleMath.rewardCoins(squeezes, the
-- player's squeeze value) Coins at the moment it is granted, and an own squeeze pays the squeeze value.
-- Match HUD M2 (2026-10-16): the "match" Coin reason (a Free for All / Team Deathmatch result, EconomyService.
-- grantMatchResult). Its amounts and rules are DuelRewards' below (owner: a match pays like a 1v1 duel, no hourly cap).

local Economy = {
	startingCoins = 0,
	-- Coins are integers clamped to [0, maxCoins]. 9 Qa (spec 2026-10-12 §12; was 1B): Luau numbers hold every whole
	-- number up to about 9.007 Qa exactly.
	maxCoins = 9_000_000_000_000_000,

	-- The closed list of reasons for EconomyService.grantCoins / trySpend (§6.1). "capsule" = capsule upgrades, slots
	-- and squeezes (spec 2026-10-12, lobby spec 2026-10-11 §6; CapsuleService). "debug" is Studio only. "trainer" went
	-- with the trainers (build plan Phase 6). "match" = a Free for All / Team Deathmatch result (Match HUD M2).
	CoinReasons = {
		"squeeze",
		"duel_win",
		"duel_loss",
		"duel_draw",
		"match",
		"quest",
		"starter",
		"daily",
		"refund",
		"robux",
		"box",
		"shop",
		"capsule",
		"debug",
	},

	-- Squishy power by rarity (spec 2026-10-12 §3, §6): a capsule squeeze pays squishy power × capsule power Coins
	-- (CapsuleMath), and an own squeeze pays the best capsule's (the squeeze value; it replaced CoinsByRarity in
	-- Phase 3). A Catalog def's `power` may override it for one squishy.
	SquishyPower = {
		Common = 1,
		Uncommon = 4,
		Epic = 16,
		Exclusive = 64,
	} :: { [string]: number },

	-- Squeeze earnings limit (§6.3): a rate limit, not a currency; never sold, never changed by passes or products.
	-- Each paid squeeze uses 1 point; points refill at perHour (even offline) up to burst. At 0 a squeeze pays
	-- emptyCoins (it still trains Grip, §17.3.1). New players start full (ProfileV1.squeezeLimit.value = burst).
	-- A paid squeeze pays the squeeze value (CapsuleMath.squeezeValue, Phase 3; pads add nothing since then);
	-- validator G3 keeps the paid squeezes an hour under Config.Grip.maxSqueezesPerHour for every limit setting.
	-- Math: shared SqueezeLimit (current / spend / full).
	-- Off since spec 2026-10-11 §5 (the user: "Less per squeeze, no limit"): every squeeze pays. The module and the
	-- profile field stay, dormant (SqueezeLimit also runs Double Grip).
	SqueezeLimit = {
		enabled = false,
		perHour = 600,
		burst = 300,
		emptyCoins = 0,
	},

	-- Duel rewards (§6.7), computed by Logic/DuelRewards and granted once on the transition into Result.
	-- Spec 2026-10-12 §9: counted in squeezes, 3× the old 200 / 60 / 100; EconomyService.grantDuelResult turns them
	-- into Coins with the player's squeeze value when it pays.
	-- Match HUD M2 (2026-10-16, owner): a Free for All / Team Deathmatch result pays the same win / loss / draw
	-- squeezes as Coins AND as Grip, with the same minOwnThrows and min Active seconds, but no same-pair or hourly cap
	-- (Server/Logic/MatchRewards reads this table; Config.Match.Rewards.enabled switches it on).
	DuelRewards = {
		win = 600,
		loss = 180,
		draw = 300,
		minOwnThrows = 3, -- server-accepted throws, for every outcome; a draw needs both players to reach it
		winMinActiveSeconds = 20, -- a bail before this is Cancelled (must be >= Duel.Rules.EarlyForfeitSeconds)
		lossMinActiveSeconds = 45,
		samePairFullRewards = 6, -- fully rewarded results per pair inside the rolling window (profile.samePair)
		samePairWindowSeconds = 3600,
		samePairMultiplier = 0.25, -- from the 7th result in the window, with duel.rewardsReduced
	},

	-- Daily rewards (§6.9). Server time only: dayIndex = floor(os.time() / 86400), reset at 00:00 UTC.
	Daily = {
		-- Streak days 1..7, then the cycle restarts at Day 1. Spec 2026-10-12 §9: counted in squeezes (the same
		-- numbers), paid as squeezes × the squeeze value when claimed. Review quick win 2026-10-14 (NOT IN DESIGN: §6.9
		-- had GraceDays = 0, a reset): a missed day only pauses the streak; the next claim pays the next day.
		coinsByDay = { 100, 150, 200, 250, 300, 400, 500 },
		freeBoxDay = 7, -- also grants the free Treat Box, opened immediately
		freeBoxId = "treat", -- must be a free-only box in Boxes.luau
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
	-- Spec 2026-10-12 §8: a double gives back `percent` % of the box price, rounded down (Snack 37,500, Sweet
	-- 112,500,000); a free box (no price: the day-7 Treat Box) gives back that share of the `freeBoxPriceOf` box's price.
	-- Replaces the refunds by rarity (100 / 150 / 300 / 1,000). Pricing.duplicateRefund(boxId) reads it.
	DuplicateRefund = {
		percent = 25,
		freeBoxPriceOf = "snack",
	},
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
