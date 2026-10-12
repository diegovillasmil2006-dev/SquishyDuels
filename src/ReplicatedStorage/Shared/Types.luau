--!strict
-- Shared type definitions (shared: server and client). Types only: this module has no runtime values.
-- Sources: DESIGN §2.2 (list), §2.7 (Result), §2.8 (remote payloads), §3.2 (ProfileV1), §4.1 (SquishyDef),
-- §5.4 (phases and queue states), §17.10 (Grip: schemaVersion 2, the StateDelta grip field, SqueezeResult fields),
-- §6.9 / §17.5 (Part 7: DailyClaimResult, TrainerUpgradeResult).
-- Where DESIGN names a payload field but not its exact type, the reading is marked "reading:".

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
	squeezeCoins: number?, -- optional override; default Economy.CoinsByRarity[rarity] (replaced in Phase 3)
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
-- Grip (§17.10): a lobby-only stat, never a currency. `rested` (Double Grip) and `afk` (the slow-training bank) are
-- timers with the SqueezeLimit shape, filled only by time. `total` is an integer in [0, Config.Grip.maxGrip];
-- `trainer` an integer in [1, #Config.Grip.Trainer] (the best trainer owned, bought in Part 7).
export type GripTimerState = SqueezeLimitState
export type GripState = { total: number, trainer: number, rested: GripTimerState, afk: GripTimerState }
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
-- reading: `quests` (daily + starter) = the profile's daily quest state plus the starter task state.
export type QuestsView = { day: number, swapsUsed: number, active: { QuestEntry }, starter: StarterState }

-- Every state field, all present: the reply to RequestSnapshot and the content of a full StateDelta.
-- `grip` (§17.10) is the profile's GripState as stored; the client derives the level, rank, Double Grip minutes and
-- slow-training minutes with the same pure GripMath, and shows the slow-training popup when grip.total rises with no
-- SqueezeResult in between. Never sent into a duel view: Grip never reaches duel code (§17.2 rule 1).
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
-- `streakReset` is true when a missed day restarted the streak at Day 1 (the panel shows daily.streakReset; never on a
-- first claim); `treatRequestId` is the free Treat Box's boxLog key "daily:<dayIndex>" (§3.4), the id AckReveal sends.
export type DailyClaimResult = {
	streakDay: number,
	coins: number,
	treat: BoxResult?,
	streakReset: boolean?,
	treatRequestId: string?,
}
-- TrainerUpgrade data (§17.5, §17.10): `trainer` = the best trainer owned after the call; `charged` is false for a
-- replay (that trainer was already owned: no Coins taken); `savePending` = the awaited "now" save failed.
export type TrainerUpgradeResult = { trainer: number, charged: boolean, savePending: boolean }

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
-- targetLevel = the trainer index to buy (2..#Config.Grip.Trainer); expectedPrice is compared, never charged.
export type TrainerUpgradeCall = (targetLevel: number, expectedPrice: number) -> Result<TrainerUpgradeResult>
export type PromptCoinBundleCall = (bundleKey: string) -> ()
export type PromptGamePassCall = (passKey: string) -> ()
export type PolicyRetryCall = () -> ()
export type SetSettingsCall = (settings: SettingsPatch) -> ()
export type OnboardingStepCall = (stepId: ClientOnboardingStep) -> ()

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
	-- Server time (workspace:GetServerTimeNow() scale) of the next token of the anti-autoclicker cap:
	-- GetServerTimeNow() + max(0, 1 - tokens) × Config.Squeeze.cycleSeconds, converted by SqueezeService from its
	-- os.clock() bucket (§17.10). Every click pays: only a hold repeat looks at it (SqueezeController.sendDue).
	nextAt: number,
	grip: number, -- Grip this squeeze trained (0 when rejected); already doubled when `doubled`
	gripTotal: number, -- grip.total after it
	doubled: boolean, -- Double Grip covered it (popup "+{n} Grip (x{mult})")
}

-- Notify codes of the Grip feature (§17.10): toasts, held back by the client from Matched to Returning (§17.7).
-- grip.rankUp goes only to players whose SD_DuelPhase == "". grip.trainerBought comes with the trainer (Part 7).
-- Reading: the intro toast `grip.intro` ("the first Grip ever", §17.7 Toasts) is not in the §17.10 Notify list; it is
-- listed here because GripService sends it once, when grip.total first rises above 0 (one sender only: the client
-- shows what arrives, so it is never raised a second time locally).
export type GripNotifyCode =
	"grip.levelUp"
	| "grip.padUnlocked"
	| "grip.rankUp"
	| "grip.welcome"
	| "grip.welcomeBack"
	| "grip.headStart"
	| "grip.trainerBought"
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
