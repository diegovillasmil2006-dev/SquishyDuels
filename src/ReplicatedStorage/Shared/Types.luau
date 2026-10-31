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
-- Match HUD M1 (2026-10-16, the data Diego's Match HUD reads: kill feed and final K.O. M:497-516, 567-572, respawn
-- seconds M:73, 88, 113, 641, streaks M:149, 349, 527, standings M:610-614, 688): MatchEventView (one K.O. of the
-- feed), MatchStandingView, every player's respawnAt / out / protectUntil / streak / bestStreak, outcome.finalKo and
-- outcome.standings, MatchStateView.events.
-- Match HUD M2 (2026-10-16, owner Q3 / Q4; the results pills M:361-363 and the WIN STREAK box M:186-189):
-- ProfileStats.winStreak (the saved win streak) and MatchRewardView / MatchOutcomeView.mine (what the match paid the
-- receiving player, in Coins and Grip, and their streak before and after).
-- Auto-clicker check (2026-10-16): AutoClickMemory, the profile's `autoClick` (the last auto-clicker strike), and the
-- squeeze.autoClick reason of SqueezeResultPayload.
-- Bubble Pop bounce (2026-10-16): UltimateBounce / UltimateEventPayload.bounce (the bubble's leg after its bounce).
-- Weekly quests (2026-10-17): WeeklyState, ProfileV1.weekly and QuestsView.weekly.
-- Pens (pens3 phase 1, 2026-10-17): PenItem, PenState, ProfileV1.pen, the `pen` state field, PenResult and the
-- PenBuySpot call. Phase 4 (coins while away): PenState.awayRate and AwayGift, the `awayGift` state field. Phase 5
-- (copies): ProfileV1.giftQueue / boxOrder / gifts, the `boxOrder` state field; BoxResult has no refund any more (an
-- old boxLog entry keeps its `refund`, unread). Phase 6 (the pen screen): PenItem.slot / locked and the PenPlace /
-- PenLock calls. Phases 7-8 (selling, the buy-back, fusion): BuyBackEntry, ProfileV1.buyBack / bag, the `buyBack`
-- state field, SellResult / FuseResult and the SellItems / SellAll / BuyBack / Fuse calls.
-- Phase 9 (food and levels): FoodCounts, ProfileV1.food, the `food` state field, FoodResult and the BuyFood / Feed /
-- FeedAll calls. Phase 11 (the shelf rows + the TOP spot): PenState.shelfRows / top and the PenBuyShelf call.
-- Phase 13 (the throw): HighwayState, ProfileV1.highway, the `highway` state field and the HighwayThrow call.
-- P13v4 (the TikTok throw): HighwayArc and HighwayPlan (HighwayThrow's data: the flight plan, boosts included) and
-- HighwayLanding (the new HighwayLanded remote: what the landing paid); HighwayResult is gone (the pay moved to the
-- landing).

-- == Catalog (§4.1) ==

export type Rarity = "Common" | "Uncommon" | "Epic" | "Exclusive"
export type TrailKind = "ribbon" | "twinRibbon" | "comet" | "ember"
-- The kill set (Art/KillStyle, kill banners 2026-10-16): "standard" for every Common and Uncommon squishy, one of its
-- own for each squishy above Uncommon. "epic_pending" (before 2026-10-16) still plays the standard set.
export type EliminationEffectId =
	"standard"
	| "epic_pending"
	| "feather_storm"
	| "sprinkle_blast"
	| "cloudburst"
	| "bubble_burst"
	| "dragon_blaze"

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
	-- Match HUD M2 (2026-10-16): Free for All / Team Deathmatch wins in a row (a team win or FFA 1st +1, paid or not;
	-- a loss, a draw or leaving a live match -> 0; 1v1 duels never touch it). Joined schema 2 without a new version.
	winStreak: number,
}

export type SqueezeLimitState = { value: number, at: number } -- §6.3 (a rate limit, not a currency)
-- Grip (§17.10): a lobby-only stat, never a currency. `rested` (Double Grip) is a timer with the SqueezeLimit shape,
-- filled only by time. `total` is an integer in [0, Config.Grip.maxGrip]. Build plan Phase 6: slow training and the
-- trainers are gone, so `afk` (its bank) and `trainer` (the best trainer owned) are no fields any more; an old save
-- keeps them as unknown fields.
export type GripTimerState = SqueezeLimitState
export type GripState = { total: number, rested: GripTimerState }
export type QuestsState = { day: number, swapsUsed: number, active: { QuestEntry } }
-- Weekly quests (2026-10-17): `week` = the week index (TimeUtil.utcWeek; -1 = none yet), `active` = its quests (ids
-- "w<week>_<slot>", no squishy).
export type WeeklyState = { week: number, active: { QuestEntry } }
export type StarterState = { progress: { [string]: number }, claimed: { [string]: boolean } }
export type DailyState = { lastClaimDay: number, streakDay: number, totalClaims: number }
export type Settings = { music: number, sfx: number, cameraShake: boolean, showTips: boolean } -- music/sfx ints 0–100
export type OnboardingState = { v: number, done: { [string]: boolean }, skipped: boolean }

export type BoxLogEntry = {
	req: string,
	box: string,
	squishy: string,
	dup: boolean, -- pens3 phase 5: the kind was owned before (a copy)
	form: number?, -- 2026-10-31 (golden luck): 1 Golden, 2 Rainbow; 0 or missing (older entries) = plain
	refund: number?, -- only in entries from before pens3 phase 5 (copies replaced the refund)
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
-- Auto-clicker check (2026-10-16): the last strike (server Services/AutoClickService): step 0 none, 1 warned, 2 kicked,
-- 3 banned; at = its os.time (0 = none). A rejoin within Config.Net.AutoClick.memorySeconds keeps the step.
export type AutoClickMemory = { step: number, at: number }
-- Pens3 phase 1: one squishy of the pen (Shared/PenMath): `id` a whole number unique in the pen (from PenState.nextId),
-- `kind` a Catalog squishy id, `form` 0 plain / 1 Golden / 2 Rainbow, `level` 1..Config.Economy.Pen.maxLevel, `coat`
-- 0 none .. 7 (Config.Economy.Pen.coatMult). Phase 1 makes only form 0, level 1, coat 0, one per owned kind. Phase 6:
-- `slot` 0 = the Toy Box, 1..spots the pen (phase 11: the shelf from 13, and the TOP spot; Neon Sugar part 5: 13..23 and
-- 24, one cubby a row; unique except 0),
-- `locked` = never sold, fused or moved by auto-place (the player can still move it).
export type PenItem = {
	id: number,
	kind: string,
	form: number,
	level: number,
	coat: number,
	slot: number,
	locked: boolean,
}
-- The player's pen: `spots` open (Pen.startSpots .. Pen.maxSpots; the items in slots 1..spots walk in it and pay),
-- `nextId` the id of the next new item, `items` every pen squishy the player has, `awayRate` (phase 4) its Coins a
-- second at the last save (DataService stamps it; the next load pays the time away from it). Phase 11: `shelfRows`
-- the open shelf rows (Pen.shelfStartRows .. Pen.shelfMaxRows; since schema 3 a row is one cubby; their squishies
-- stand in the shelf and pay too), `top`
-- true once the TOP spot is bought.
export type PenState = {
	spots: number,
	nextId: number,
	items: { PenItem },
	awayRate: number,
	shelfRows: number,
	top: boolean,
	income: IncomeState, -- INCOME step 1: the levels bought (Config/Income)
}
-- INCOME step 1: the levels bought of SQUISHY COINS and ALL EARNINGS (whole numbers in [0, the line's levels]).
export type IncomeState = { coins: number, all: number }
-- Phase 4: the Coins the pen paid for the time away on this session's load, and the seconds counted (session only).
export type AwayGift = { coins: number, seconds: number }
-- Phase 7: one sale that can be bought back for Config.Economy.Pen.buyBackSeconds: `item` the squishy as it was sold
-- (bare: its coating went to the bag), `price` the Coins the sale paid (what the buy-back charges, once), `at` its
-- os.time, `req` the sale's requestId (a retried SellItems / SellAll replays, it never sells twice).
export type BuyBackEntry = { item: PenItem, price: number, at: number, req: string }
-- Phase 9: the food pieces a player owns, by Config.Economy.Food food id (whole numbers in [0, Food.maxPieces]).
export type FoodCounts = { [string]: number }
-- Phase 13: the farthest landing (whole studs from the start line, 0..gatesAt) and the biome reached (1..#starts,
-- #starts + 1 = the Golden Gates; it only rises).
export type HighwayState = { best: number, biome: number }
-- Gear step 2: the steps bought of each gear line (GearMath.LINES; whole numbers in [0, GearMath.maxStep]).
export type GearState = { held: number, platform: number, arm: number, armor: number }

-- The one profile schema. The type name stays ProfileV1 across schema versions (§17.10): schemaVersion 2 added
-- `grip` (the first migration, v1 -> v2, in Logic/ProfileSchema); schemaVersion 3 made the shelf one cubby a row.
export type ProfileV1 = {
	schemaVersion: number, -- 3 (ProfileSchema.CURRENT)
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
	-- (pens3 phase 2: `capsules` left with no new version; an old save keeps it as an unknown field nothing reads)
	autoClick: AutoClickMemory, -- added within schemaVersion 2 the same way (2026-10-16); never sent to the client
	weekly: WeeklyState, -- weekly quests, added within schemaVersion 2 the same way (2026-10-17)
	pen: PenState, -- the pen (pens3 phase 1), added within schemaVersion 2 the same way
	-- Pens3 phase 5, added within schemaVersion 2 the same way: free squishies waiting for room in the Toy Box (kind
	-- ids, oldest first), the fixed-order opens per paid box (restricted accounts) and the once-per-account gifts
	-- given.
	giftQueue: { string },
	boxOrder: { [string]: number },
	gifts: { [string]: boolean },
	-- Pens3 phases 7-8, added within schemaVersion 2 the same way: the sales that can be bought back (at most
	-- Config.Economy.Pen.buyBackMax, oldest first) and the coatings in the bag (one count per coating, Wax .. Galaxy:
	-- index = PenItem.coat).
	buyBack: { BuyBackEntry },
	bag: { number },
	food: FoodCounts, -- pens3 phase 9, added within schemaVersion 2 the same way: the food pieces owned
	highway: HighwayState, -- pens3 phase 13, added within schemaVersion 2 the same way: the farthest throw, the biome
	gear: GearState, -- gear step 2, added the same way (no new schema version): the gear steps bought
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
-- reading: `quests` (daily + starter) = the profile's daily quest state plus the starter task state; `weekly` (2026-10-17)
-- = the profile's weekly quests (nil before the first week's are made).
export type QuestsView = {
	day: number,
	swapsUsed: number,
	active: { QuestEntry },
	starter: StarterState,
	weekly: WeeklyState?,
}

-- Every state field, all present: the reply to RequestSnapshot and the content of a full StateDelta.
-- `grip` (§17.10) is the profile's GripState as stored; the client derives the level, rank and Double Grip minutes
-- with the same pure GripMath. Never sent into a duel view: Grip never reaches duel code (§17.2 rule 1).
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
	topWins: TopWinsView, -- Batch 3
	pen: PenState, -- pens3 phase 1: the profile's pen as stored (the squeeze value of every client text, the sign)
	awayGift: AwayGift, -- pens3 phase 4: {coins = 0, seconds = 0} until the load pays one (the client shows it once)
	-- Pens3 phase 5: the profile's fixed-order opens per paid box (Boxes.fixedItem(boxId, n) is the next squishy a
	-- restricted account gets; the box card shows it before the open).
	boxOrder: { [string]: number },
	buyBack: { BuyBackEntry }, -- pens3 phase 7: the profile's buy-back list as stored (the pen screen's sold cards)
	food: FoodCounts, -- pens3 phase 9: the profile's food as stored (the pen screen's food row and FEED buttons)
	highway: HighwayState, -- pens3 phase 13: the profile's highway as stored (the level cap, the throw HUD)
	gear: GearState, -- gear step 2: the profile's gear as stored (the zone banner's power, the gear shop)
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
	topWins: TopWinsView?,
	pen: PenState?,
	awayGift: AwayGift?,
	boxOrder: { [string]: number }?,
	buyBack: { BuyBackEntry }?,
	food: FoodCounts?,
	highway: HighwayState?,
	gear: GearState?,
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
	| "topWins"
	| "pen"
	| "awayGift"
	| "boxOrder"
	| "buyBack"
	| "food"
	| "highway"
	| "gear"

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
-- Match HUD M1 (2026-10-16): respawnAt = server time they stand again (nil when standing or out); out = TDM, no team
-- life left; protectUntil = their spawn protection's end (server time, 0 = none); streak = K.O.s since they were last
-- knocked out; bestStreak = the longest streak of this match.
export type MatchParticipantView = {
	userId: number,
	displayName: string,
	squishyId: string,
	team: string?,
	kos: number,
	knockedOut: number,
	alive: boolean,
	ultReady: boolean,
	respawnAt: number?,
	out: boolean,
	protectUntil: number,
	streak: number,
	bestStreak: number,
	-- Round 1 of the match screens (2026-10-26): arrived = in the map (MatchRules; bots from the start), for the intro's
	-- cards; level = the Grip level the MATCH FOUND show gave them (1 when unknown).
	arrived: boolean,
	level: number,
}

-- One HUD event of a match (Match HUD M1, 2026-10-16): seq counts from 1 per match. kind "ko" now; later "revived",
-- "pickup", "shieldBlocked" (alerts, power-ups) once Diego designs them. at = server time.
export type MatchEventView = {
	seq: number,
	kind: string,
	at: number,
	victim: number?, -- ko
	by: number?, -- ko: the attacker; nil for a storm or out-of-bounds K.O.
	cause: string?, -- ko: "hit" | "storm" | "outOfBounds" (MatchRules ko effect; an ultimate's hit is "hit")
	final: boolean?, -- ko: this K.O. ended the match (outcome win by koTarget, wiped or overtime)
	streak: number?, -- ko: the attacker's streak after it (K.O.s since they were last knocked out); nil without one
}

-- One line of the final standings (Match HUD M1): present players only, their stats frozen when the outcome is made.
-- End screens round A (2026-10-26): grip = the Grip the match paid them (the scoreboard's column; nil when not paid).
export type MatchStandingView = { userId: number, kos: number, knockedOut: number, bestStreak: number, grip: number? }

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
-- Match HUD M1 (2026-10-16): finalKo = the K.O. that ended the match (a win by koTarget, wiped or overtime; nil
-- otherwise; only cause "hit" has a `by`); standings = MatchRules.standings order (most K.O.s, fewest times knocked
-- out, entrant order) of the players present at the end, the same list in every later view.
-- Match HUD M2 (2026-10-16): mine = what this match paid the receiving player (in their own view only); nil for a
-- cancelled / void match, while Config.Match.Rewards is off, and for anyone not paid.
export type MatchOutcomeView = {
	kind: string,
	reason: string,
	winnerUserId: number?,
	winnerTeam: string?,
	winners: { number },
	finalKo: MatchEventView?,
	standings: { MatchStandingView },
	mine: MatchRewardView?,
}

-- Match HUD M2 (owner 2026-10-16): what a match paid one player (Coins and Grip really added) and their win streak
-- before and after it (Diego's results pills, M:361-363).
export type MatchRewardView = { coins: number, grip: number, streakBefore: number, streakAfter: number }

-- The map: its floor height, the Bounds box the combat code reads, and its centre (the storm's centre).
export type MatchArenaView = { floorY: number, bounds: ArenaZone, centre: Vector3 }

-- The MatchQueue payload (round 1 of the match flow, 2026-10-25): the player's Free for All / Team Deathmatch queue
-- ticket as the waiting bar draws it. `mode` nil (an empty table) = no ticket any more. count = the players queued
-- (at most max); joinedAt = when this player joined (server time); full = the match starts now with count players
-- (bots included): the bar fills up, and {} follows at once (the ticket is gone).
export type MatchQueueView = {
	mode: MatchMode?,
	count: number?,
	max: number?,
	joinedAt: number?,
	full: boolean?,
}

-- The MatchFound payload (round 2 of the match flow, 2026-10-25): who plays the match or duel the queue just started,
-- for the lobby's MATCH FOUND show (Diego's LOBBY HUD L:722-735). team: 1 / 2 (Config.Match.teamNames) in Team
-- Deathmatch, nil otherwise; level: the Grip level (a bot's is drawn by Server/Logic/MatchFoundRoster).
export type MatchFoundMode = "1v1" | "tdm" | "ffa"
export type MatchFoundPlayer = { userId: number, name: string, squishy: string, level: number, team: number? }
export type MatchFoundView = { mode: MatchFoundMode, players: { MatchFoundPlayer } }

-- The MatchVoteState payload (round 3 of the match flow, 2026-10-25): the map vote of a Team Deathmatch / Free for All
-- match the queue just started (Diego's LOBBY HUD L:1024-1147). maps: the cards' maps (Workspace.DuelMaps model
-- names), in order; votes[i]: the userIds on card i in landing order (bots' too); opensAt / closesAt: the timer's start
-- and its 0 (server times). result, once decided: the winning card, how ("chosen" | "tie" | "random": nobody voted),
-- the tie's roulette (each card lit and when), and when the result shows (at), the winner moves (revealAt) and the
-- match starts (startsAt). An empty table: no vote any more.
export type MatchVoteResultView = {
	winner: number,
	kind: "chosen" | "tie" | "random",
	roulette: { { choice: number, at: number } },
	at: number,
	revealAt: number,
	startsAt: number,
}
export type MatchVoteView = {
	id: string?,
	mode: MatchMode?,
	maps: { string }?,
	opensAt: number?,
	closesAt: number?,
	votes: { { number } }?,
	result: MatchVoteResultView?,
}

-- The MatchState payload (one per player): sent on the first view, every phase change, K.O., respawn, team-score
-- change and outcome, plus the own view when `you.stormBar` moved (at most Config.Match.Storm.sampleHz a second).
-- A last view with phase "Returning", then the cleared attributes (SD_MatchId "") end it on the client.
-- Power-ups v1.1 (2026-10-16): also on every pickup (everyone: a pad's readyAt rose), a shield used up, and to the
-- player whose timed power-up just ended.
-- Match HUD M1 (2026-10-16): a view sent to everyone carries `events` (the HUD events since the previous such view,
-- by seq; empty when none); a view sent only to its owner (the storm bar, a power-up's end) has none.
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
	teamScore: { [string]: number }?, -- TDM: each team's K.O.s scored (2026-10-26)
	koTarget: number?, -- the mode's win target (TDM: the team score)
	arena: MatchArenaView,
	storm: { startRadius: number }?, -- TDM only (StormMath.startRadius of the map's footprint)
	outcome: MatchOutcomeView?,
	pads: { MatchPadView }, -- power-ups v1.1: every power-up pad of the map (empty when it has none)
	events: { MatchEventView }?, -- Match HUD M1: the HUD events since the previous view sent to everyone
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

-- Pens3 phase 5: a buy always charges (an owned squishy is bought again as a copy); every refusal is a ResultErr.
export type ShopResult = { squishyId: string, charged: boolean, savePending: boolean }
-- Pens3 phase 5: `isDuplicate` = the kind was owned before (the squishy is a copy); there is no refund.
-- form (2026-10-31, golden luck): 0 plain, 1 Golden, 2 Rainbow.
export type BoxResult = { squishyId: string, isDuplicate: boolean, form: number?, savePending: boolean }
-- reading: day 7 carries the free Treat Box result so the reveal can play at once (§6.9). Readings (Part 7):
-- `treatRequestId` is the free Treat Box's boxLog key "daily:<dayIndex>" (§3.4), the id AckReveal sends. A missed day
-- only pauses the streak (review quick win 2026-10-14), so there is no reset flag.
export type DailyClaimResult = {
	streakDay: number,
	coins: number,
	treat: BoxResult?,
	treatRequestId: string?,
}
-- PenBuySpot data (pens3 phase 1): `pen` = the caller's own pen after the buy; `charged` true (every refusal is a
-- ResultErr with charged = false); `savePending` = the awaited "now" save failed.
export type PenResult = { pen: PenState, charged: boolean, savePending: boolean }
-- Pens3 phase 7: SellItems / SellAll data: `coins` the Coins the sale paid (a replay: what it paid then), charged =
-- false (nothing is taken). BuyBack answers a PenResult with charged = true. Phase 8: Fuse data: `id` the result's
-- item id (the keeper's), charged = false (fusion is free).
export type SellResult = { pen: PenState, coins: number, charged: boolean, savePending: boolean }
export type FuseResult = { pen: PenState, id: number, charged: boolean, savePending: boolean }
-- Pens3 phase 9: BuyFood / Feed / FeedAll data: the caller's pen and food after the call, `levels` the levels
-- gained (BuyFood 0), charged (BuyFood true, also on a replay as first answered; Feed / FeedAll false).
export type FoodResult = { pen: PenState, food: FoodCounts, levels: number, charged: boolean, savePending: boolean }
-- P13v4 (HighwayService, Shared/HighwayMath; work/pens3/p13v4/SPEC.md 3.1, 5.2): one air arc of a throw. Server times
-- (workspace:GetServerTimeNow), distances in studs from the start line, heights lane-local (WorldLayout.highwayCFrame).
export type HighwayArc = {
	startAt: number, -- server time it starts (the release, or a boost)
	from: number, -- studs from the start line where it starts (negative on the deck)
	y0: number, -- lane-local height where it starts
	carry: number, -- studs where it meets the lane
	air: number, -- seconds from startAt to the carry
	peak: number, -- studs the arc rises over the straight line (at most flight.peakMax)
}
-- HighwayThrow's data: a new throw (boosted = false) or the same throw after a boost (boosted = true). The client draws
-- HighwayMath.planAt(plan, serverNow); the pay comes at the landing (HighwayLanded).
export type HighwayPlan = {
	id: number, -- this throw's number in the player's server session (HighwayLanded names it)
	perfect: boolean,
	x0: number, -- lane-local x of the release
	arcs: { HighwayArc }, -- 1 + the boosts so far, in order
	roll: number, -- seconds rolling after the last arc's carry
	studs: number, -- where it stops (whole studs, 0..gatesAt)
	biome: number, -- HighwayMath.biomeAt(studs)
	landsAt: number, -- server time it stops
	fuel: number, -- boosts left
	boosted: boolean,
	trap: boolean, -- gear step 2: a trap took some of this throw's power (a boost keeps it)
	charged: boolean, -- false
	savePending: boolean,
}
-- HighwayLanded's payload (the server's settle at the landing): what the landing paid (`coins` with the rings' share,
-- `grip`); the player's `best` after it and `newBest`; `reached` the biome (1..8) this throw reached first (nil if
-- none); `gifts` the biome gifts given (squishy ids); `food` the Food Bag it filled (nil if none); `rings` the
-- WorldLayout.Highway.rings indices it flew through; `bullseye` it stopped on a pad; `boosts` the boosts it used.
export type HighwayLanding = {
	id: number,
	studs: number,
	biome: number,
	coins: number,
	grip: number,
	best: number,
	newBest: boolean,
	reached: number?, -- the biome first reached by this throw (8 = the Golden Gates), else nil
	gifts: { string },
	food: { id: string, count: number }?,
	rings: { number }, -- WorldLayout.Highway.rings indices hit, ascending
	bullseye: boolean,
	perfect: boolean,
	boosts: number,
}

-- GearBuy data (gear step 2): the caller's gear after the buy; charged true (every refusal is a ResultErr with
-- charged = false); savePending = the awaited "now" save failed.
export type GearResult = { gear: GearState, charged: boolean, savePending: boolean }

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
export type SqueezeRequestCall = (fastSeconds: number) -> () -- spec 2026-10-11 §5: the server finds the pad itself
export type BoxOpenCall = (boxId: string, requestId: string) -> Result<BoxResult>
export type AckRevealCall = (requestId: string) -> ()
export type ShopBuyCall = (squishyId: string, expectedPrice: number, requestId: string) -> Result<ShopResult>
export type QuestClaimCall = (questId: string) -> Result<nil>
export type QuestSwapCall = (questId: string) -> Result<nil>
export type DailyClaimCall = () -> Result<DailyClaimResult>
-- Pens3 phase 1: buys the caller's own next pen spot; expectedPrice is compared, never charged.
export type PenBuySpotCall = (expectedPrice: number) -> Result<PenResult>
-- Pens3 phase 11: buys the caller's own next shelf row, then the TOP spot; expectedPrice is compared, never charged.
export type PenBuyShelfCall = (expectedPrice: number) -> Result<PenResult>
-- INCOME step 1: buys the next level of one of the caller's own INCOME lines ("coins" | "all"); expectedPrice is
-- compared, never charged.
export type PenBuyIncomeCall = (line: string, expectedPrice: number) -> Result<PenResult>
-- Gear step 2: buys the next step of one of the caller's gear lines (GearMath.LINES); expectedPrice is compared,
-- never charged.
export type GearBuyCall = (line: string, expectedPrice: number) -> Result<GearResult>
-- Pens3 phase 6: one of the caller's own squishies to a slot (0 = put away; an occupied spot swaps), and its lock.
export type PenPlaceCall = (itemId: number, slot: number) -> Result<PenResult>
export type PenLockCall = (itemId: number, locked: boolean) -> Result<PenResult>
-- Pens3 phases 7-8: sell the caller's own squishies (ids from its pen, at most Pen.sellMaxIds), Sell All, buy one back
-- within Pen.buyBackSeconds (its sold item id), fuse 3 of the same.
export type SellItemsCall = (ids: { number }, requestId: string) -> Result<SellResult>
export type SellAllCall = (requestId: string) -> Result<SellResult>
export type BuyBackCall = (itemId: number) -> Result<PenResult>
export type FuseCall = (a: number, b: number, c: number) -> Result<FuseResult>
-- Pens3 phase 9: buy pieces of a food (expectedPrice compared, never charged), feed one squishy one level, Feed All.
export type BuyFoodCall = (
	foodId: string,
	count: number,
	expectedPrice: number,
	requestId: string
) -> Result<FoodResult>
export type FeedCall = (itemId: number, requestId: string) -> Result<FoodResult>
export type FeedAllCall = () -> Result<FoodResult>
-- Pens3 phase 13: one throw (p13v4: a press during the own flight asks for its boost); clientTime =
-- workspace:GetServerTimeNow() at the press, checked and never trusted.
export type HighwayThrowCall = (clientTime: number, fastSeconds: number) -> Result<HighwayPlan> -- p13v3, p13v4
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
	-- a §2.10 code when ok = false (squeeze.tooFast, squeeze.noCharacter, data.notReady, ...; squeeze.autoClick once
	-- per auto-clicker strike, 2026-10-16)
	reason: string?,
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
-- Bubble Pop bounce (2026-10-16): the bubble's second leg. It starts at `origin` (the end of the first leg, `length`
-- studs from the event's origin, on the cover it bounces off) the moment the first leg ends, and flies `length` studs
-- along `dir` (flat unit) at the event's speed.
export type UltimateBounce = { origin: Vector3, dir: Vector3, length: number }
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
	bounce: UltimateBounce?, -- release: Bubble Pop's leg after it bounced off cover (nil = no bounce)
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
