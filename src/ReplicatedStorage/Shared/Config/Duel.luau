--!strict
-- Config.Duel: match rules, phase timings, matchmaking and arena slots (DESIGN §5.2-§5.4). Shared, data only.
-- All [P]. Throw validation, hitbox and lag are in Config.Combat; Dragon Rush is in Config.Abilities.

local Duel = {
	-- DuelRules / CombatService (§5.2).
	Rules = {
		Lives = 3, -- hits a player can take before losing; every hit costs exactly 1 life
		MatchSeconds = 120, -- Active phase length
		SuddenDeathSeconds = 30, -- only if lives are tied at time-up (0 = straight to draw)
		SuddenDeathCooldownMultiplier = 0.8,
		PreparingTimeoutSeconds = 3,
		PositioningTimeoutSeconds = 5,
		CountdownSeconds = 3, -- frozen, no throws
		ResultSeconds = 4, -- result shown in the arena before return
		HitInvulnSeconds = 1.5, -- victim can't be hit (projectiles pass through) but can throw
		OutOfBoundsInvulnSeconds = 1.0,
		CooldownClamp = { Min = 0.6, Max = 2.0 }, -- hard clamp on any catalog cooldown, seconds
		CooldownToleranceSeconds = 0.05, -- jitter allowance: releaseAt >= nextThrowAt - tolerance
		InputBufferSeconds = 0.15, -- a press this close to the cooldown end is buffered on the client
		-- Feature 1 (2026-10-11, the user-approved plan; was HoldToRepeat): holding Throw charges the throw
		-- (Config.Combat.Charge) and letting go throws it (design: html:393-394). A press during the cooldown starts the
		-- charge when the throw is ready; one let go before that still throws, uncharged, when it was at most
		-- InputBufferSeconds early. false: every press throws at once, uncharged.
		HoldToCharge = true,
		MaxActiveProjectilesPerPlayer = 4, -- extra requests rejected (throw.tooMany)
		ProjectileMaxLifetime = 3.0, -- seconds
		EarlyForfeitSeconds = 20, -- a bail before this much Active time cancels the duel
		RequeueCooldownSeconds = 3, -- after any match
		BailRequeueCooldownSeconds = 15, -- after bailing
		OutOfBounds = {
			CheckHz = 5,
			KillYOffset = -15, -- KillY = arena floor + KillYOffset
			LifePenalty = 0,
			MaxPerMatch = 6, -- the 7th out-of-bounds is a forfeit
			-- Out of bounds = HRP outside its own half grown by this many studs (X and Z), or below KillY (§5.4).
			-- Reading: the same 2 studs as the throw position check (Config.Combat.Throw.zoneToleranceStuds).
			HalfToleranceStuds = 2,
		},
		Movement = { WalkSpeed = 16, JumpHeight = 7.2 }, -- uniform for everyone (= StarterPlayer, V)
		-- Feedback only, applied once by the victim's client. Dragon Rush multiplies it by
		-- Config.Abilities.dragon_rush.knockbackMultiplier (the single source of that ×1.5).
		Knockback = { Horizontal = 22, Vertical = 8 }, -- studs/s
		-- The dash (spec phase 5 §1.2, §3.3; the design's numbers are all "provisional", design: main.js:310). The
		-- dasher's client moves its own HumanoidRootPart (like knockback) along e(x) = 1 - (1 - x)³; the server checks
		-- the request (Logic/DashRules), clamps the end point with Shared/DashMath and gives the movement guard a
		-- bounded allowance for that dash only (MovementRules.allowDash). No i-frames.
		Dash = {
			distanceStuds = 14, -- design: main.js:310, fp.js:525 (D = s(14))
			seconds = 0.22, -- design: main.js:310, fp.js:537 (T2 = 0.22)
			-- The pose clip (design: avatar.js:79-99, 155): keys at frames 0, 2, 4, 7, 12 at 30 fps (0.40 s); the
			-- push-off puff and sound at frame 2, the plant at frame 7; full weight until frame 9, then w² with
			-- w = (12 - f) / 3 (design: avatar.js:160-161).
			visualFrames = 12, -- design: main.js:357, avatar.js:84
			visualFps = 30, -- design: avatar.js:155
			pushoffFrame = 2, -- design: avatar.js:81
			plantFrame = 7, -- design: avatar.js:83
			fadeFromFrame = 9, -- design: avatar.js:160 (end - 3)
			ribbonSeconds = 0.26, -- the ribbons and speed lines run while t < 0.26 s (design: fp.js:539-540)
			cooldownSeconds = 2.0, -- user decision 2026-10-11 (NOT IN DESIGN: main.js:311 "unassigned (server)")
			-- build choice 2026-10-11 (NOT IN DESIGN): the server checks the cooldown with this much jitter allowance,
			-- like a throw's CooldownToleranceSeconds, so an honest client's dash is never refused at the edge.
			cooldownToleranceSeconds = 0.15,
			-- build choice 2026-10-11 (NOT IN DESIGN; the design ignores a dash in the air, fp.js:524): grounded = the HRP
			-- at most this far above its standing height (the capsule's floor + 3.0).
			groundToleranceStuds = 1.5,
			-- build choice 2026-10-11 (NOT IN DESIGN): the end point stays this far (the hitbox radius) inside the own
			-- half (duel) or the practice range bounds, so a dash never crosses into the neutral band; and a Spherecast
			-- of this radius from the HRP stops it at cover and walls.
			bodyRadiusStuds = 1.3,
			-- build choice 2026-10-11 (NOT IN DESIGN): the movement guard allows the dash's own studs (plus this slack)
			-- once, between the request (minus guardLeadSeconds: the client starts before its request arrives) and
			-- seconds + guardTailSeconds after it (the replication delay of the last part of the move).
			guardSlackStuds = 2,
			guardLeadSeconds = 0.25,
			guardTailSeconds = 0.5,
			-- Bug fix 2026-10-15 (2-player test: a player was flung spinning and flying): the dash's mover pushes with
			-- at most this acceleration (studs/s², times the character's mass) instead of an unlimited force, and the
			-- move ends as soon as the body lags blockedLagStuds behind its eased path (it ran into something), so a
			-- dash can never keep shoving the body into cover. 12,000 still reaches the 191 studs/s peak in a frame.
			maxAccelStuds = 12000,
			blockedLagStuds = 2,
		},
	},

	-- QueueService / Matchmaker (§5.4). Order: priority descending, then joinedAt.
	-- Rating hook: none in v1, pure FIFO; never reads lobby stats (§5.4).
	Matchmaking = {
		PairIntervalSeconds = 0.5, -- pairing also runs on ticket add and slot release
		NoOpponentHintSeconds = 20,
		QueueMaxSeconds = 300, -- then the ticket is removed (queue.timedOut)
		AvoidImmediateRematch = true, -- skip the head's last opponent if another partner exists
		NormalPriority = 0, -- reading: a fresh ticket
		RequeuePriority = 1, -- requeued at the front after the opponent bailed (§5.4)
		-- canPair when both ratings exist: |a - b| <= base + growthPerSecond × waited. Unused in v1 (getRating
		-- returns nil, so canPair is always true); reading: zero window until a hidden duel-only rating exists (§16).
		RatingWindow = { base = 0, growthPerSecond = 0 },
	},

	-- Preparing / Positioning (§5.4).
	Positioning = {
		StreamAroundTimeoutSeconds = 3, -- RequestStreamAroundAsync(pad, 3), in pcall
		R15ExtraHeight = 0.1, -- R15 pivot height above the pad: HipHeight + HRP.Size.Y/2 + 0.1
		R6Height = 3.1,
		RespawnWaitSeconds = 5, -- character died before Positioning: wait this long, else Cancelled
		MissingRootSeconds = 1, -- HRP missing longer than this = opponent missing
		-- Returning (§9.14): the client fades to #2B2440 over this long; the server waits it out before the PivotTo
		-- to the return point, then the client fades back over the same time. Reading: DESIGN gives 250 ms per fade.
		ReturnFadeSeconds = 0.25,
		-- When Countdown starts, the client turns the camera to sit behind the positioned character, looking along its
		-- facing (toward the opponent): the default camera keeps the lobby heading through a teleport, which can leave
		-- it in front of the player looking back (Part 4 test play). Reading: DESIGN gives no numbers.
		CameraBehindStuds = 12,
		CameraHeightStuds = 4,
	},

	-- Arena slot pool (ArenaService, §5.3). Slot origins: X ∈ {320, 520} × Z ∈ {-300, -100, 100, 300}, first
	-- MaxSlots used. Y = 0 (floor top level of the lobby, §7.5; DESIGN gives no Y).
	Arena = {
		MaxSlots = 6,
		PrewarmSlots = 1,
		SlotOrigins = {
			Vector3.new(320, 0, -300),
			Vector3.new(320, 0, -100),
			Vector3.new(320, 0, 100),
			Vector3.new(320, 0, 300),
			Vector3.new(520, 0, -300),
			Vector3.new(520, 0, -100),
			Vector3.new(520, 0, 100),
			Vector3.new(520, 0, 300),
		},
		LeaseGraceSeconds = 60,
		JanitorIntervalSeconds = 5, -- voids matches whose lease expired
		-- Reading (§5.4 "Lease expired: Void, slot released"): the voided match returns its players and then releases
		-- the slot itself; only a slot still held this long after its lease expired is released by the janitor.
		LeaseDrainSeconds = 30,
	},

	-- DataModel.ServerRestartScheduled (§3.12): matches that can finish before restart - margin continue.
	RestartMarginSeconds = 30,
}

return Duel
