--!strict
-- Config.Net: per-remote token buckets, global cap and abuse thresholds (DESIGN §2.7, §2.8, §12). Shared, data only.
-- `Remotes` is keyed by the exact client -> server remote names of Remotes.SPEC; Config.validate() checks that every
-- C->S remote has an entry here and that every entry here is a C->S remote. Rates are [P].
-- Grip has no remote of its own (§17.9 #1). TrainerUpgrade went with the trainers (build plan Phase 6), the capsule
-- remotes with CapsuleService (pens3 phase 2).
-- FFA/TDM v1 (2026-10-15): MatchJoin and MatchLeave (the client's /ffa, /tdm and /leave chat commands).
-- Power-ups v1.1 review fix (2026-10-16): DashRequest's rate covers the dash boost (one dash after the other).
-- Auto-clicker check (2026-10-16): AutoClick = the Config/AutoClick module (Config.Net.AutoClick; a child module, so
-- Config/init does not grow; Config/ValidateAutoClick checks it). The client now sends fresh squeeze presses over the
-- paid cap too (at most AutoClick.clientPressesPerSecond = 18 a second, none while replies are late).

export type RemoteRate = {
	rate: number, -- tokens refilled per second
	burst: number, -- bucket capacity
	oneInFlight: boolean?, -- RemoteFunction: a second call while one runs is rejected
}

local Net = {
	Remotes = {
		-- The client polls every Client.snapshotRetrySeconds (1.5 s) for up to 60 s while loading (§2.6), so the
		-- rate must cover the poll cadence (Config.validate: rate x snapshotRetrySeconds >= 1).
		RequestSnapshot = { rate = 1, burst = 3 },
		-- Part 5 (InventoryService). SetSettings and OnboardingStep (PreferencesService) are at the end of this table.
		EquipSquishy = { rate = 2, burst = 4 },
		-- Duel (Part 4). ThrowRequest is also the practice range's throw remote (§5.11).
		QueueJoin = { rate = 1, burst = 3 },
		QueueLeave = { rate = 1, burst = 3 },
		DuelForfeit = { rate = 0.2, burst = 2 },
		ReportIdle = { rate = 1 / 30, burst = 1 },
		ThrowRequest = { rate = 3, burst = 4 }, -- §5.6 #1: over the bucket = silent drop
		UltimateRequest = { rate = 0.5, burst = 2 },
		-- Spec phase 5: the dash's 2 s cooldown is DashRules' (the client sends at most one per cooldown); the bucket
		-- only stops floods. Power-ups v1.1 review fix (2026-10-16): the match dash boost has no cooldown, one dash
		-- after the other (at most one per pose clip, Config.Duel.Rules.Dash visualFrames / visualFps = 0.4 s: 2.5 a
		-- second), so the rate is above that: an honest boosted dasher never runs the bucket down to where network
		-- jitter could make the server drop (and count) a dash the client already made. Duels still get one per 2 s
		-- (DashRules). Rapid throw needs no change: its shortest cooldown (0.6 s) is 1.7 throws and ChargeStarts a
		-- second, under ThrowRequest's and ChargeStart's 3.
		DashRequest = { rate = 3, burst = 3 },
		-- 2026-10-15: the double jump (one per air time, DoubleJumpRules' serverIntervalSeconds); the bucket only stops
		-- floods.
		DoubleJumpRequest = { rate = 3, burst = 4 },
		-- Movement overhaul (2026-10-17): the lobby slide (LobbyMoveService; one per Config.LobbyMove.Slide cooldown,
		-- 0.9 s); the bucket only stops floods.
		SlideRequest = { rate = 2, burst = 3 },
		-- Feature 1 (2026-10-11): the client sends one ChargeStart before each throw (ThrowRequest's own bucket); the
		-- catch's cooldown is CombatService's (Config.Combat.Catch.cooldownSeconds), the bucket only stops floods.
		ChargeStart = { rate = 3, burst = 4 },
		CatchRequest = { rate = 2, burst = 3 },
		-- The flood guard (> 20/s dropped silently, = Config.Squeeze.floodPerSecond): an honest client sends at most
		-- AutoClick.clientPressesPerSecond (18) a second plus the paid cap's own (auto-clicker check 2026-10-16:
		-- presses over the paid cap are sent too, so the server sees the real rhythm; before, at most the paid-squeeze
		-- cap, 2 in 0.9 s), so it is never rate-limited, counted as a violation or muted; a macro above 20/s still is,
		-- once it has used up the burst. After a network stall the queued presses arrive at once: the client stops
		-- sending presses over the paid cap once a reply is late (about 1 s), so the queue stays far under burst 60
		-- (Config.validate: burst >= 5 s of the cap, Global.burst >= this burst). The paid-squeeze cap itself (2 at
		-- once, then 1 per 0.45 s, the hold rhythm) is a game-state check in SqueezeService (Config.Squeeze), not this
		-- bucket.
		SqueezeRequest = { rate = 20, burst = 60 },
		BoxOpen = { rate = 0.5, burst = 1, oneInFlight = true },
		AckReveal = { rate = 5, burst = 5 },
		ShopBuy = { rate = 1, burst = 1, oneInFlight = true },
		QuestClaim = { rate = 2, burst = 3 },
		QuestSwap = { rate = 0.5, burst = 1 },
		DailyClaim = { rate = 0.5, burst = 1 },
		-- Pens3 phase 1: the pen's spot buy: 1 a second and one at a time.
		PenBuySpot = { rate = 1, burst = 1, oneInFlight = true },
		-- Pens3 phase 6: the pen screen's place / put away / swap and lock: 2 a second (a burst of 3), one at a time.
		PenPlace = { rate = 2, burst = 3, oneInFlight = true },
		PenLock = { rate = 2, burst = 3, oneInFlight = true },
		-- Pens3 phases 7-8: the pen screen's sell, Sell All, buy-back and fuse: PenPlace's 2 a second (a burst of 3),
		-- one at a time.
		SellItems = { rate = 2, burst = 3, oneInFlight = true },
		SellAll = { rate = 2, burst = 3, oneInFlight = true },
		BuyBack = { rate = 2, burst = 3, oneInFlight = true },
		Fuse = { rate = 2, burst = 3, oneInFlight = true },
		PromptCoinBundle = { rate = 0.5, burst = 1 },
		PromptGamePass = { rate = 0.5, burst = 1 },
		-- Burst 2: the UI re-enables the button after exactly 30 s, so with network jitter an honest second press can
		-- arrive just under 30 s and would count as abuse. PolicyGateService still enforces the real rule
		-- (>= 30 s since the last attempt, <= 5 per session, §6.10).
		PolicyRetry = { rate = 1 / 30, burst = 2 },
		SetSettings = { rate = 0.5, burst = 2 },
		OnboardingStep = { rate = 2, burst = 5 },
		-- Batch 3 (FriendDuelService): no arguments; a press only sets the player's own wish for the offered rematch.
		RematchRequest = { rate = 0.5, burst = 2 },
		-- FFA/TDM v1 (2026-10-15, MatchService): the /ffa, /tdm and /leave chat commands; a person types them, so the
		-- bucket only stops floods.
		MatchJoin = { rate = 1, burst = 3 },
		MatchLeave = { rate = 1, burst = 3 },
	} :: { [string]: RemoteRate },

	-- Per-player cap over all C->S remotes together (§2.7 step 2). Burst 80 (was 40): it holds SqueezeRequest's
	-- burst of 60 (an honest clicker's backlog after a stall) plus room for the other remotes.
	Global = { rate = 30, burst = 80 },

	-- A violation is a rate-limit hit or an invalid payload. More than `violations` inside `windowSeconds` mutes
	-- that player's C->S remotes for `muteSeconds` and logs [SD][abuse].
	Abuse = {
		violations = 20,
		windowSeconds = 60,
		muteSeconds = 30,
	},
	kickOnAbuse = false, -- no automatic kicks in v1 (the auto-clicker check's steps are AutoClick's, below)

	-- Auto-clicker check (2026-10-16): Config/AutoClick (every value and why).
	AutoClick = require(script.Parent.AutoClick),

	maxAbsNumber = 1e6, -- finite numbers only: x == x and |x| < maxAbsNumber
	-- Server timestamps (ThrowRequest/UltimateRequest clientTime = workspace:GetServerTimeNow(), §5.6) are Unix
	-- seconds (~1.8e9 in 2026), so they get their own bound instead of maxAbsNumber. Implausible values are then
	-- handled by ThrowRules (§5.6 #7: outside [-0.05 s, 1 s] of now -> lag from ping only).
	maxAbsServerTime = 1e10,

	-- Server -> client broadcast rate caps.
	Broadcast = {
		queueStatusMaxHz = 2, -- count-only QueueStatus to all players (podium board)
		ultimateChargeMaxHz = 2,
	},

	-- Client boot (§2.6).
	Client = {
		connectTimeoutSeconds = 30, -- NetController.connectAsync(30), else error.connect
		snapshotRetrySeconds = 1.5, -- RequestSnapshot every 1.5 s while loading ...
		snapshotWaitSeconds = 60, -- ... for up to 60 s
	},
}

return Net
