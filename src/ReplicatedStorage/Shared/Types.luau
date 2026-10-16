--!strict
-- Shared type definitions (shared: server and client). Types only: this module has no runtime values.
-- Sources: DESIGN §2.2 (list), §2.7 (Result), §2.8 (remote payloads), §3.2 (ProfileV1), §4.1 (SquishyDef),
-- §5.4 (phases and queue states), §17.10 (Grip: schemaVersion 2, the StateDelta grip field, SqueezeResult fields),
-- §6.9 (Part 7: DailyClaimResult).
-- Where DESIGN names a payload field but not its exact type, the reading is marked "reading:".
-- FFA/TDM v1 (2026-10-15): MatchMode, MatchParticipantView, MatchStateView (the MatchState remote) and the MatchJoin /
-- MatchLeave calls.
-- Power-ups v1.1 (2026-10-16): MatchYouView.buffs (the live timed power-ups), MatchPadView / MatchStateView.pads (the
-- map's power-up pads and when each is ready) and ThrowImpactPayload.blocked (a shield took the hit).

-- == Catalog (§4.1) ==

export type Rarity = "Common" | "Uncommon" | "Epic" | "Exclusive"
export type TrailKind = "ribbon" | "twinRibbon" | "comet" | "ember"
export type EliminationEffectId = "standard" | "epic_pending"

export type SquishyDef = {
	id: string,
	nameKey: string,
	rarity: Rarity,
	blueprintId: string,
	icon: string?, -- uploaded image id later; nil = static viewport preview (v1)
	power: number?, -- optional squishy power; default Economy.SquishyPower[rarity] (spec 2026-10-12 §6)
	shopPrice: number?, -- nil = not sold (the starter)
	robuxOnly: boolean?,
	equivalentId: string?, -- future Robux-exclusive squishies (§6.12)
	throw: { speed: number, gravity: number, radius: number, cooldown: number, windup: number }, -- studs/s, studs/s², studs, s, s
	ultimateId: string?, -- "dragon_rush" for dragon only
	eliminationEffectId: EliminationEffectId,
	visuals: { trail: TrailKind?, flightSpin: "wobble" | "roll", accent: string },
	anim: { squeezeAxis: "X" | "Y" | "Z", foamRecoveryT: number, squeezeFx: string? },
	hold: { grip: Vector3, heldYaw: number }, -- grip offset from RightGripAttachment; heldYaw degrees
	inspect: { yaw: number, pitch: number }, -- default 3/4 view
}

-- == Profile (§3.2; defaults, migration and sanitizing live in server Logic/ProfileSchema) ==

export type OwnedSource = "starter" | "box" | "shop" | "grant"
export type OwnedEntry = { at: number, src: OwnedSource }

export type QuestEntry = {
	id: string,
	def: string,
	squishy: string?,
	progress: number,
	goal: number,
	reward: number,
	done: boolean,
	claimed: boolean,
}

export type ProfileStats = {
	coinsEarned: number,
	coinsSpent: number,
	squeezes: number,
	duelsPlayed: number,
	duelsWon: number,
	duelsLost: number,
	duelsDrawn: number,
	eliminations: number,
	boxesOpened: number,
}

export type SqueezeLimitState = { value: number, at: number } -- §6.3 (a rate limit, not a currency)
-- Grip (§17.10): a lobby-only stat, never a currency. `rested` (Double Grip) is a timer with the SqueezeLimit shape,
-- filled only by time. `total` is an integer in [0, Config.Grip.maxGrip]. Build plan Phase 6: slow training and the
-- trainers are gone, so `afk` (its bank) and `trainer` (the best trainer owned) are no fields any more; an old save
-- keeps them as unknown fields.
export type GripTimerState = SqueezeLimitState
export type GripState = { total: number, rested: GripTimerState }
export type QuestsState = { day: number, swapsUsed: number, active: { QuestEntry } }
export type StarterState = { progress: { [string]: number }, claimed: { [string]: boolean } }
export type DailyState = { lastClaimDay: number, streakDay: number, totalClaims: number }
export type Settings = { music: number, sfx: number, cameraShake: boolean, showTips: boolean } -- music/sfx ints 0–100
export type OnboardingState = { v: number, done: { [string]: boolean }, skipped: boolean }

export type BoxLogEntry = {
	req: string,
	box: string,
	squishy: string,
	dup: boolean,
	refund: number,
	cost: number,
	at: number,
	seen: boolean,
}
export type ShopLogEntry = { req: string, squishy: string, price: number, at: number }
export type ReceiptEntry = { id: string, product: number, coins: number, at: number }
export type DuelLogResult = "win" | "loss" | "draw"
-- Reading: `full` (optional, not in §3.2's entry) is true only for a fully rewarded result (eligible and not reduced);
-- EconomyService adds a same-pair time (SamePairRecord) only for such a result (§6.7 "fully rewarded results"), an
-- entry without it that pays Coins counting as full (fail closed). The same-pair count never reads duelLog.
export type DuelLogEntry = { matchId: string, opp: number, result: DuelLogResult, at: number, full: boolean? }
-- The same-pair guard's record (§6.7, §12 #15; Logic/DuelRewards): key = the opponent's userId as a string (DataStore
-- JSON keys are strings), value = ascending os.time() times of this player's FULLY rewarded results against that
-- opponent inside the rolling window. Reading: kept apart from duelLog (cap 30, about 17 minutes of fast duels) and
-- trimmed by time, so the rolling hour is always whole; at most samePairFullRewards times per opponent and
-- Config.Data.caps.samePair opponents.
export type SamePairRecord = { [string]: { number } }
-- The player's capsules (lobby bases spec 2026-10-11 §6, progression spec 2026-10-12 §6-§7): `slots` unlocked, a
-- whole number 1..#Config.Grip.Capsule.slotPrices; `list[i]` = the capsule in slot i, one per unlocked slot: its level
-- (1..Capsule.maxLevel) and the squishy in it (nil = empty; a squishy sits in one capsule at a time).
export type CapsuleState = { level: number, squishyId: string? }
export type CapsulesState = { slots: number, list: { CapsuleState } }

-- The one profile schema. The type name stays ProfileV1 across schema versions (§17.10): schemaVersion 2 added
-- `grip` (the first migration, v1 -> v2, in Logic/ProfileSchema).
export type ProfileV1 = {
	schemaVersion: number, -- 2 (ProfileSchema.CURRENT)
	createdAt: number, -- unix seconds (os.time)
	lastSeenAt: number,
	saveSeq: number, -- monotonic, +1 per write snapshot
	coins: number, -- integer, 0..Config.Economy.maxCoins
	owned: { [string]: OwnedEntry }, -- squishyId -> entry
	equipped: string,
	stats: ProfileStats,
	squeezeLimit: SqueezeLimitState,
	quests: QuestsState,
	starter: StarterState,
	daily: DailyState,
	settings: Settings,
	onboarding: OnboardingState,
	boxLog: { BoxLogEntry }, -- cap 50
	shopLog: { ShopLogEntry }, -- cap 20
	receipts: { ReceiptEntry }, -- cap 100
	duelLog: { DuelLogEntry }, -- cap 30
	grip: GripState, -- schemaVersion 2 (§17.10)
	samePair: SamePairRecord, -- added within schemaVersion 2 (reconcile fills it; no migration)
	capsules: CapsulesState, -- added within schemaVersion 2 (reconcile fills it; no old saves to fix, spec 2026-10-12 §14)
}

-- The same type under its version name, for code that wants to say which schema it means.
export type ProfileV2 = ProfileV1

-- A profile as stored at schemaVersion 1 (before the Grip migration): every ProfileV1 field except `grip`. The input
-- of ProfileSchema MIGRATIONS[1] and of its v1 fixture test (§17.12).
export type ProfileV1Unmigrated = {
	schemaVersion: number, -- 1
	createdAt: number,
	lastSeenAt: number,
	saveSeq: number,
	coins: number,
	owned: { [string]: OwnedEntry },
	equipped: string,
	stats: ProfileStats,
	squeezeLimit: SqueezeLimitState,
	quests: QuestsState,
	starter: StarterState,
	daily: DailyState,
	settings: Settings,
	onboarding: OnboardingState,
	boxLog: { BoxLogEntry },
	shopLog: { ShopLogEntry },
	receipts: { ReceiptEntry },
	duelLog: { DuelLogEntry },
}

-- == Result (§2.7) ==

-- `v` is the player's state version. `charged = false` on a failure is what allows the client to add
-- "No Coins were spent" (§2.10).
export type ResultOk<T> = { ok: true, v: number, data: T }
export type ResultErr = { ok: false, v: number, reason: string, charged: boolean? }
export type Result<T> = ResultOk<T> | ResultErr

-- == State channel: Snapshot and StateDelta (§2.8) ==

export type PolicyState = "checking" | "eligible" | "restricted" | "unknown"
export type DataStatusName = "loading" | "ready" | "offline" | "readonly"
-- Reading: `banner` (optional, not in §2.8's list) is the Strings key of the honest status banner the server chose
-- (StateService.bannerFor: data.studioMemory, data.offlineRetrying, data.loadFailed, data.newerVersion, data.rejoin;
-- nil = none, §3.1, §3.13, §11.3). A client may also derive the banner from status and persisted.
export type DataStatus = { status: DataStatusName, persisted: boolean, savePending: boolean, banner: string? }
export type MonetizationView = { bundles: { string }, passes: { string } } -- offered keys; passes empty in v1
export type PracticeStats = { throws: number, hits: number, accuracy: number } -- session only, never saved
-- Batch 3 (review #10): "Top Wins This Week" (ShowOffService; session only). `loaded` turns true with the first board
-- read; `top` = the leaders (at most Config.Social.Board.size) with their display names; `place` = the player's own
-- place when within the read (Board.readSize); `wins` = the player's counted wins this week; `unavailable` = no read
-- has worked yet (no API access, an outage), so there is no board to show.
export type TopWinsLine = { name: string, wins: number }
export type TopWinsView = { loaded: boolean, top: { TopWinsLine }, place: number?, wins: number, unavailable: boolean? }
-- reading: `quests` (daily + starter) = the profile's daily quest state plus the starter task state.
export type QuestsView = { day: number, swapsUsed: number, active: { QuestEntry }, starter: StarterState }

-- Every state field, all present: the reply to RequestSnapshot and the content of a full StateDelta.
-- `grip` (§17.10) is the profile's GripState as stored; the client derives the level, rank and Double Grip minutes
-- with the same pure GripMath. Never sent into a duel view: Grip never reaches duel code (§17.2 rule 1).
-- `capsules` (build plan Phase 5) is the profile's CapsulesState as stored, for the owner's capsule card, the squeeze
-- value of the reward texts and the owner's capsule pops (other players' capsules are read from their base's models).
export type Snapshot = {
	coins: number,
	owned: { [string]: OwnedEntry },
	equipped: string,
	stats: ProfileStats,
	squeezeLimit: SqueezeLimitState,
	quests: QuestsView,
	daily: DailyState,
	settings: Settings,
	onboarding: OnboardingState,
	policy: PolicyState,
	dataStatus: DataStatus,
	monetization: MonetizationView,
	unseenReveals: { BoxLogEntry }, -- boxLog entries with seen = false
	practice: PracticeStats,
	grip: GripState,
	capsules: CapsulesState,
	topWins: TopWinsView, -- Batch 3
}

-- A partial StateDelta: only the changed fields are present.
export type StateDeltaFields = {
	coins: number?,
	owned: { [string]: OwnedEntry }?,
	equipped: string?,
	stats: ProfileStats?,
	squeezeLimit: SqueezeLimitState?,
	quests: QuestsView?,
	daily: DailyState?,
	settings: Settings?,
	onboarding: OnboardingState?,
	policy: PolicyState?,
	dataStatus: DataStatus?,
	monetization: MonetizationView?,
	unseenReveals: { BoxLogEntry }?,
	practice: PracticeStats?,
	grip: GripState?,
	capsules: CapsulesState?,
	topWins: TopWinsView?,
}

-- The StateDelta field names (Snapshot keys), for code that walks them.
export type StateField =
	"coins"
	| "owned"
	| "equipped"
	| "stats"
	| "squeezeLimit"
	| "quests"
	| "daily"
	| "settings"
	| "onboarding"
	| "policy"
	| "dataStatus"
	| "monetization"
	| "unseenReveals"
	| "practice"
	| "grip"
	| "capsules"
	| "topWins"

export type SnapshotLoading = { status: "loading" }

-- == Duel and queue views (§2.8, §5.4) ==

export type QueueState = "Idle" | "Searching" | "Matched"
export type DuelPhase =
	"Preparing"
	| "Positioning"
	| "Countdown"
	| "Active"
	| "SuddenDeath"
	| "Result"
	| "Returning"
	| "Cancelled"
	| "Void"
export type Side = "A" | "B"

export type DuelParticipantView = {
	userId: number,
	displayName: string,
	squishyId: string,
	side: Side,
	lives: number,
	ultReady: boolean,
	isTestDummy: boolean,
}

-- reading: zones and pads are keyed by the arena child names (`HalfA`, `Neutral`, `HalfB`, `Bounds`;
-- `PadA`, `PadB`); a zone is sent as the box the server reads (CFrame and Size, §5.3).
export type ArenaZone = { cframe: CFrame, size: Vector3 }
export type DuelArenaView = {
	slot: number,
	arenaId: string?, -- World/Arenas id of the match's arena (phase 4: a server fact, picked at random per match)
	floorY: number,
	zones: { [string]: ArenaZone },
	pads: { [string]: CFrame },
}

-- The DuelState payload (the match state channel): a full view, sent to each participant on every phase change.
-- Lives also change through ThrowImpact.livesLeft between two DuelState messages.
export type DuelStateView = {
	matchId: string,
	phase: DuelPhase,
	phaseEndsAt: number, -- server time
	you: DuelParticipantView,
	opponent: DuelParticipantView,
	arena: DuelArenaView,
	rules: { [string]: any }, -- reading: this match's copy of Config.Duel.Rules
}

-- == Free for All / Team Deathmatch views (FFA/TDM v1, 2026-10-15; MatchService -> the MatchState remote) ==

export type MatchMode = "ffa" | "tdm"

-- One match player as everyone sees them. `team` is Config.Match.teamNames[1] / [2] in TDM, nil in FFA; `kos` = the
-- K.O.s they scored, `knockedOut` = the times they were knocked out; `alive` = standing in the map right now.
export type MatchParticipantView = {
	userId: number,
	displayName: string,
	squishyId: string,
	team: string?,
	kos: number,
	knockedOut: number,
	alive: boolean,
	ultReady: boolean,
}

-- The receiving player's own state. Server times; respawnAt = while knocked out (nil when standing or out);
-- protectUntil = the spawn protection's end (0 = none); stormBar 0..1 (TDM); out = TDM, no team life left.
-- Power-ups v1.1 (2026-10-16): buffs = the player's live timed power-ups, Config.Match.PowerUps kind -> the server
-- time it ends (an ended or used-up one is left out; a K.O. clears them all).
export type MatchYouView = {
	userId: number,
	team: string?,
	alive: boolean,
	respawnAt: number?,
	protectUntil: number,
	stormBar: number,
	out: boolean,
	buffs: { [string]: number },
}

-- Power-ups v1.1 (2026-10-16): one power-up pad of the map: its instance name under the map's model (the client finds
-- it for Diego's MapAnimations_<code>.Collect(padModel, seconds)) and the server time it is ready again (0 = ready).
-- A pickup raises readyAt to the pickup time + Config.Match.PowerUps.padRefillSeconds.
export type MatchPadView = { name: string, readyAt: number }

-- MatchRules' outcome: kind "win" | "draw" | "cancelled" | "void"; reason koTarget, wiped, timeUp, overtime,
-- overtimeTimeout, lastPlayer, notEnoughPlayers, shutdown, error or empty; winners = every winning userId.
export type MatchOutcomeView = {
	kind: string,
	reason: string,
	winnerUserId: number?,
	winnerTeam: string?,
	winners: { number },
}

-- The map: its floor height, the Bounds box the combat code reads, and its centre (the storm's centre).
export type MatchArenaView = { floorY: number, bounds: ArenaZone, centre: Vector3 }

-- The MatchState payload (one per player): sent on the first view, every phase change, K.O., respawn, team-lives
-- change and outcome, plus the own view when `you.stormBar` moved (at most Config.Match.Storm.sampleHz a second).
-- A last view with phase "Returning", then the cleared attributes (SD_MatchId "") end it on the client.
-- Power-ups v1.1 (2026-10-16): also on every pickup (everyone: a pad's readyAt rose), a shield used up, and to the
-- player whose timed power-up just ended.
export type MatchStateView = {
	matchId: string,
	mode: MatchMode,
	mapCode: string, -- the map's MapCode (Diego's MapLighting / MapAnimations_<code>)
	mapName: string,
	phase: DuelPhase, -- the DuelPhase name (Waiting -> Positioning, Overtime -> Active, Closed -> Returning)
	matchPhase: string, -- the real MatchRules phase: Waiting, Countdown, Active, Overtime, Result, Closed
	phaseEndsAt: number, -- server time (workspace:GetServerTimeNow()); 0 = no timer
	activeStartedAt: number?, -- server time Active began (the storm and the match timer)
	you: MatchYouView,
	players: { MatchParticipantView },
	teamLives: { [string]: number }?, -- TDM
	koTarget: number?, -- FFA
	arena: MatchArenaView,
	storm: { startRadius: number }?, -- TDM only (StormMath.startRadius of the map's footprint)
	outcome: MatchOutcomeView?,
	pads: { MatchPadView }, -- power-ups v1.1: every power-up pad of the map (empty when it has none)
}

-- One queue entry (§5.4), as QueueService keeps it and Logic/Matchmaker reads it. `priority` is
-- Config.Duel.Matchmaking.NormalPriority or RequeuePriority (requeued after the opponent bailed). `rating` is nil in
-- v1 (getRating returns nil: pure FIFO; it never reads lobby stats). `player` is nil in pure tests.
export type QueueTicket = {
	userId: number,
	player: Player?,
	joinedAt: number, -- server time
	priority: number,
	rating: number?,
	lastOpponentUserId: number?,
}

-- Throws, hits and accuracy (0-100, rounded) of one match or one practice session.
export type DuelStats = { throws: number, hits: number, accuracy: number }

-- == Remote payloads: client → server (§2.8) ==
-- Argument lists as the client sends them. The server receives `unknown` and narrows through Validate.

export type SettingsPatch = { music: number?, sfx: number?, cameraShake: boolean?, showTips: boolean? }
-- reading (Part 7): "skip" = Config.Onboarding.skipStepId, the "Skip tutorial" link (sets onboarding.skipped).
export type ClientOnboardingStep = "welcome" | "inspect" | "skip"

-- reading: `charged` is false when the squishy was already owned (no charge, `shop.owned`).
export type ShopResult = { squishyId: string, charged: boolean, savePending: boolean }
export type BoxResult = { squishyId: string, isDuplicate: boolean, refund: number, savePending: boolean }
-- reading: day 7 carries the free Treat Box result so the reveal can play at once (§6.9). Readings (Part 7):
-- `treatRequestId` is the free Treat Box's boxLog key "daily:<dayIndex>" (§3.4), the id AckReveal sends. A missed day
-- only pauses the streak (review quick win 2026-10-14), so there is no reset flag.
export type DailyClaimResult = {
	streakDay: number,
	coins: number,
	treat: BoxResult?,
	treatRequestId: string?,
}
-- CapsuleUpgrade / CapsuleUnlock / CapsuleSet data (lobby spec 2026-10-11 §6, Phase 3): `capsules` = the caller's own
-- capsules after the call; `charged` is false when no Coins were taken (an unlock replay, any CapsuleSet);
-- `savePending` = the awaited "now" save failed (CapsuleSet: a failed save is pending).
export type CapsuleResult = { capsules: CapsulesState, charged: boolean, savePending: boolean }

-- QueueJoin data: the player's place in the queue (1 = next). A join from an OFFLINE/READONLY profile still
-- succeeds and the server also sends Notify("duel.noRewardsOffline", nil, "warn") (§2.8).
export type QueueJoinResult = { position: number }

-- ThrowRequest / UltimateRequest arguments after the server's type checks (§5.6 #2), as Logic/ThrowRules reads them.
export type ThrowInput = { seq: number, aimDir: Vector3, originHint: Vector3, clientTime: number }
export type UltimateInput = { seq: number, aimDir: Vector3, clientTime: number }

export type RequestSnapshotCall = () -> Result<Snapshot | SnapshotLoading>
export type EquipSquishyCall = (squishyId: string) -> Result<nil>
export type QueueJoinCall = () -> Result<QueueJoinResult>
export type QueueLeaveCall = () -> ()
export type DuelForfeitCall = () -> ()
export type ReportIdleCall = () -> ()
export type ThrowRequestCall = (seq: number, aimDir: Vector3, originHint: Vector3, clientTime: number) -> ()
export type UltimateRequestCall = (seq: number, aimDir: Vector3, clientTime: number) -> ()
export type SqueezeRequestCall = () -> () -- spec 2026-10-11 §5: the server finds the pad itself
export type BoxOpenCall = (boxId: string, requestId: string) -> Result<BoxResult>
export type AckRevealCall = (requestId: string) -> ()
export type ShopBuyCall = (squishyId: string, expectedPrice: number, requestId: string) -> Result<ShopResult>
export type QuestClaimCall = (questId: string) -> Result<nil>
export type QuestSwapCall = (questId: string) -> Result<nil>
export type DailyClaimCall = () -> Result<DailyClaimResult>
-- slot = 1..#Config.Grip.Capsule.slotPrices of the caller's own capsules; expectedPrice is compared, never charged.
export type CapsuleUpgradeCall = (slot: number, expectedPrice: number) -> Result<CapsuleResult>
export type CapsuleUnlockCall = (slot: number, expectedPrice: number) -> Result<CapsuleResult>
export type CapsuleSetCall = (slot: number, squishyId: string) -> Result<CapsuleResult>
export type PromptCoinBundleCall = (bundleKey: string) -> ()
export type PromptGamePassCall = (passKey: string) -> ()
export type PolicyRetryCall = () -> ()
export type SetSettingsCall = (settings: SettingsPatch) -> ()
export type OnboardingStepCall = (stepId: ClientOnboardingStep) -> ()
-- FFA/TDM v1 (2026-10-15): the /ffa, /tdm and /leave chat commands.
export type MatchJoinCall = (mode: MatchMode) -> ()
export type MatchLeaveCall = () -> ()

-- == Remote payloads: server → client (§2.8) ==

export type NotifyKind = "info" | "success" | "warn" | "error"
export type NotifyArgs = { [string]: string | number }

-- Tuple events, typed as the client's OnClientEvent handler.
export type StateDeltaHandler = (v: number, fields: StateDeltaFields, full: boolean?) -> ()
export type NotifyHandler = (code: string, args: NotifyArgs?, kind: NotifyKind) -> ()
export type ThrowRejectedHandler = (seq: number, reason: string, nextThrowAt: number) -> ()

-- The reply to every SqueezeRequest the server did not drop (§6.3, §17.10). A flood-guard drop has no reply.
export type SqueezeResultPayload = {
	ok: boolean, -- accepted (it may still pay 0 Coins when the earnings limit is empty)
	coins: number, -- Coins this squeeze paid (the "+N" popup only when > 0)
	total: number, -- the Coins balance after it
	limit: number, -- reading: whole points left in the squeeze Coins limit (floor of SqueezeLimit.current)
	reason: string?, -- a §2.10 code when ok = false (squeeze.tooFast, squeeze.noCharacter, data.notReady, ...)
	-- Server time (workspace:GetServerTimeNow() scale) of the next token of the paid-squeeze cap:
	-- GetServerTimeNow() + max(0, 1 - tokens) × Config.Squeeze.cycleSeconds, converted by SqueezeService from its
	-- os.clock() bucket (§17.10). Only a hold repeat looks at it (SqueezeController.sendDue).
	nextAt: number,
	grip: number, -- Grip this squeeze trained (0 when rejected); already doubled when `doubled`
	gripTotal: number, -- grip.total after it
	doubled: boolean, -- Double Grip covered it (popup "+{n} Grip (x{mult})")
}

-- Notify codes of the Grip feature (§17.10): toasts, held back by the client from Matched to Returning (§17.7).
-- grip.rankUp goes only to players whose SD_DuelPhase == "". (grip.trainerBought went with the trainers and
-- grip.padUnlocked with the giant pads, Phase 6.)
-- Reading: the intro toast `grip.intro` ("the first Grip ever", §17.7 Toasts) is not in the §17.10 Notify list; it is
-- listed here because GripService sends it once, when grip.total first rises above 0 (one sender only: the client
-- shows what arrives, so it is never raised a second time locally).
export type GripNotifyCode =
	"grip.levelUp"
	| "grip.rankUp"
	| "grip.welcome"
	| "grip.welcomeBack"
	| "grip.headStart"
	| "grip.intro"

-- Owner update. reading: `position` and `joinedAt` are absent while Idle.
export type QueueStatusPayload = {
	state: QueueState,
	position: number?,
	searching: number,
	duelsInProgress: number,
	arenasFree: number,
	joinedAt: number?,
	messageKey: string?,
}
-- Count-only broadcast to everyone for the queue board (≤ 2 Hz).
export type QueueCountsPayload = { searching: number, duelsInProgress: number, arenasFree: number }

export type ThrowKind = "throw" | "practice"
-- reading: `projId` is a per-server counter (a number).
export type ThrowStartedPayload = {
	seq: number,
	nextThrowAt: number,
	projId: number,
	matchId: string?,
	throwerId: number,
	squishyId: string,
	kind: ThrowKind,
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	radius: number,
	releaseAt: number,
	-- Feature 1 (2026-10-11): the server's charge c (0..1) of this throw, which drew its speed; clients scale the trail
	-- and the release by it. Reading: nil (an older server) = 0.
	power: number?,
}

export type ImpactKind = "player" | "geometry" | "expired" | "target" | "fizzle"

-- Feature 1 (2026-10-11): a catch and its burst (CombatService, Config.Combat.Catch), to the two duelists. Server
-- times. A caught throw sends no ThrowImpact: this event ends it on the clients.
export type CatchPhase = "caught" | "burst"
export type CatchEventPayload = {
	phase: CatchPhase,
	matchId: string,
	catcherId: number,
	throwerId: number,
	projId: number, -- the caught throw
	squishyId: string, -- the caught toy (the thrower's)
	position: Vector3, -- caught: where the throw was caught; burst: the catcher's hands (the server's estimate)
	at: number, -- the catch / the burst
	burstAt: number, -- when the caught toy bursts
	-- burst only: the thrower's lives after it, its invulnerability and whether it ended the match. livesLeft nil = no
	-- life was lost (the match had ended meanwhile).
	livesLeft: number?,
	invulnUntil: number?,
	eliminated: boolean?,
}
export type ThrowImpactPayload = {
	projId: number,
	kind: ImpactKind,
	position: Vector3,
	normal: Vector3?,
	victimId: number?,
	livesLeft: number?,
	invulnUntil: number?,
	knockbackDir: Vector3?,
	eliminated: boolean?,
	effectId: EliminationEffectId?,
	-- reading (not in §2.8's field list): kind "target" names the practice target that was hit (its TargetId), so
	-- the client squishes the right one (§5.11) without guessing from the position.
	targetId: string?,
	-- Power-ups v1.1 (2026-10-16, Free for All / Team Deathmatch only): true = the victim's shield took this hit (kind
	-- "player", eliminated false: no K.O., the shield is used up; the throw ends there). nil = a normal hit.
	blocked: boolean?,
}

export type UltimatePhase = "telegraph" | "release" | "cancel"
-- Spec phase 5: one Flock Volley bird (its own projectile) and one Rain Check drop (an area hit), in a release.
export type UltimateShot = { projId: number, origin: Vector3, dir: Vector3, length: number, releaseAt: number }
export type UltimateDrop = { projId: number, position: Vector3, shadowAt: number, landAt: number }
export type UltimateEventPayload = {
	phase: UltimatePhase,
	casterId: number,
	-- Config.Abilities key (spec phase 5). Reading: nil = "dragon_rush", the only ultimate before it existed.
	ultimateId: string?,
	projId: number?, -- release: the lane, the roller or the bubble
	origin: Vector3,
	dir: Vector3,
	length: number,
	radius: number,
	telegraphEndsAt: number,
	speed: number,
	shots: { UltimateShot }?, -- release: Flock Volley's birds
	center: Vector3?, -- release: Rain Check's zone centre, on the floor
	drops: { UltimateDrop }?, -- release: Rain Check's drops
}

-- Spec phase 5: an accepted dash, to the participants (practice: nearby players) so their clients play its pose and
-- effects; the dasher's own client already moved (it predicts). Server times.
export type DashStartedPayload = {
	userId: number,
	dir: Vector3, -- flat unit
	from: Vector3, -- the server HRP at the request
	to: Vector3, -- the server's end point (cover, the own half and the range bounds cut it)
	startAt: number,
}

-- 2026-10-15: an accepted double jump, to the match's players so their clients play its flip and effects; the
-- jumper's own client already moved. Server times.
export type DoubleJumpedPayload = {
	userId: number,
	key: string, -- "F" | "B" | "L" | "R": the flip (DoubleJumpController.poseAt)
	at: Vector3, -- the server HRP at the request
	startAt: number,
}

export type UltimateChargePayload = { ownerId: number, charge: number }

export type DuelOutcome = "win" | "loss" | "draw" | "cancelled" | "void"
-- reading: one line per quest the match advanced.
export type QuestProgressLine = { questId: string, progress: number, goal: number, done: boolean }
export type DuelResultPayload = {
	matchId: string,
	outcome: DuelOutcome,
	-- A full Strings key for this participant's line under the title, e.g. "duel.opponentLeft" (§5.2 rule 2),
	-- "duel.youOut", "duel.timeUpWin", "duel.cancelled", "duel.opponentLeftEarly", "duel.void".
	reasonKey: string,
	coins: number, -- the Coins EconomyService really paid (0 with coinsBlockedReason when nothing was paid)
	-- A §2.10 reason code: why 0 Coins ("duel.tooShort", "duel.noRewardsOffline", ...), or, next to Coins that were
	-- paid, "duel.rewardsReduced" (the same-pair reduction, §6.7; the result panel shows it under the reward line).
	coinsBlockedReason: string?,
	stats: DuelStats,
	questProgress: { QuestProgressLine },
	tip: string?, -- "duel.lossTip" when the tip is due
}

return {}
