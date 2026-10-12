--!strict
-- Config.Net: per-remote token buckets, global cap and abuse thresholds (DESIGN §2.7, §2.8, §12). Shared, data only.
-- `Remotes` is keyed by the exact client -> server remote names of Remotes.SPEC; Config.validate() checks that every
-- C->S remote has an entry here and that every entry here is a C->S remote. Rates are [P].
-- Grip has no remote of its own (§17.9 #1): the only Grip-related call is TrainerUpgrade (Part 7, §17.5), which buys
-- a trainer with Coins (rate 1, burst 1, one in flight; validator G6 checks the entry).

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
		-- only stops floods.
		DashRequest = { rate = 1, burst = 3 },
		-- Feature 1 (2026-10-11): the client sends one ChargeStart before each throw (ThrowRequest's own bucket); the
		-- catch's 0.75 s cooldown is CombatService's (Config.Combat.Catch), the bucket only stops floods.
		ChargeStart = { rate = 3, burst = 4 },
		CatchRequest = { rate = 2, burst = 3 },
		-- The flood guard (> 20/s dropped silently, = Config.Squeeze.floodPerSecond): every click pays, so normal
		-- fast clicking (the client sends at most 12 per second) is never rate-limited, counted as a violation or
		-- muted; a macro above 20/s still is, once it has used up the burst. Burst 60 = 5 s of the 12-per-second
		-- cap: after a network stall an honest clicker's queued presses arrive at once, and up to 5 s of them are
		-- never violations (a mute needs over 6.7 s of them; Config.validate: burst >= 5 s of the cap, Global.burst >=
		-- this burst). The paid-squeeze cap (capacity 12, 12 per second) is a game-state check in SqueezeService
		-- (Config.Squeeze), not this bucket.
		SqueezeRequest = { rate = 20, burst = 60 },
		BoxOpen = { rate = 0.5, burst = 1, oneInFlight = true },
		AckReveal = { rate = 5, burst = 5 },
		ShopBuy = { rate = 1, burst = 1, oneInFlight = true },
		QuestClaim = { rate = 2, burst = 3 },
		QuestSwap = { rate = 0.5, burst = 1 },
		DailyClaim = { rate = 0.5, burst = 1 },
		-- Grip trainer upgrade (§17.5, Part 7): the stored trainer is the idempotency key, so a retry is a replay.
		TrainerUpgrade = { rate = 1, burst = 1, oneInFlight = true },
		PromptCoinBundle = { rate = 0.5, burst = 1 },
		PromptGamePass = { rate = 0.5, burst = 1 },
		-- Burst 2: the UI re-enables the button after exactly 30 s, so with network jitter an honest second press can
		-- arrive just under 30 s and would count as abuse. PolicyGateService still enforces the real rule
		-- (>= 30 s since the last attempt, <= 5 per session, §6.10).
		PolicyRetry = { rate = 1 / 30, burst = 2 },
		SetSettings = { rate = 0.5, burst = 2 },
		OnboardingStep = { rate = 2, burst = 5 },
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
	kickOnAbuse = false, -- no automatic kicks in v1

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
