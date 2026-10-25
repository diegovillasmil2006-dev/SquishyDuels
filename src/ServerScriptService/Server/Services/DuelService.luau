--!strict
-- DuelService (server only). DESIGN §5.2, §5.4, §6.7, §9.14, §12 #6, #12, #14, #15, #21, #22.
-- The match lifecycle. Logic/DuelRules is the state machine (pure); this module owns one DuelRules state per match,
-- feeds it events, stores the new state BEFORE doing anything else (and before any yield), then performs the returned
-- effects. Phases: Preparing -> Positioning -> Countdown -> Active (-> SuddenDeath) -> Result -> Returning, with
-- Cancelled and Void as the other ends (§5.4). Every terminal path ends in closeMatch (in pcall).
-- * startMatch(a, b, slot?): a and b are Players, or one may be the Studio test dummy (TestHarness: a Player-shaped
--   table with isTestDummy = true, accepted only in Studio with Config.Debug.testHarness, never rewarded). The slot is
--   the one QueueService acquired (else this module acquires one). Preparing snapshots each participant: the squishy
--   is the equipped one (validated against the Catalog, fallback the starter; never changed by the client afterwards),
--   rewardsEnabled = the profile is ready (hooks.profileReady = EconomyService.canEarn), random sides A/B.
--   SD_MatchId / SD_DuelPhase are set, DuelState goes to both, and the pads are streamed to each player
--   (RequestStreamAroundAsync in pcall, Config.Duel.Positioning.StreamAroundTimeoutSeconds).
-- * Positioning waits for each character, teleports it to its pad with CharacterService.teleportAsync at
--   ArenaService.placementCFrame (lookAt on the pad's facing, never pad.CFrame, plus the §5.4 height) and sets
--   WalkSpeed / JumpHeight 0. Countdown keeps them frozen. Active restores Config.Duel.Rules.Movement, resets
--   nextThrowAt to the Active start, and the per-match tick runs every Heartbeat (in pcall: an error voids the match).
-- * Combat: CombatService validates throws and simulates projectiles against a MatchPort built here (phase, sides,
--   arena slot, DuelRules.canBeHit). Hits come back as one batch per server step and go through DuelRules (lives,
--   invulnerability, final hit, exact-tie draw). Nothing ever changes Humanoid.Health. Out-of-bounds from the movement
--   guard is a DuelRules `oob` event (silent re-pivot before Active; then pad + invulnerability + count, the 7th a bail).
-- * Edge cases (§5.4 table): DuelForfeit and the intercepted Reset (the client confirms, then fires DuelForfeit) ->
--   `forfeit`; leaving -> `leave`; CharacterService.Died -> `died` (a respawn -> `respawned`); a HumanoidRootPart
--   missing longer than MissingRootSeconds -> `missing` (`found` when it is back); ArenaService.LeaseExpired ->
--   `leaseExpired`; ShutdownService.Closing -> `shutdown` (Void, duel.void); RestartScheduled -> `restartScheduled`.
--   DuelRules decides Cancelled (bail before Active or before EarlyForfeitSeconds of Active) or a win for the other
--   side; late requests in Result/Returning are no-ops.
-- * The single end (DuelRules `ended`, exactly once per match): each real participant gets DuelResult {matchId,
--   outcome, reasonKey, coins, coinsBlockedReason?, stats {throws, hits, accuracy 0-100}, questProgress = {}}. For a
--   Result the reward of each real participant is computed by Logic/DuelRewards and paid through
--   EconomyService.grantDuelResult (settleReward, §3.11, §6.7): the duelLog entry, the duel stats and the Coins in one
--   step, exactly once per matchId (EconomyService checks duelLog; this module fires the end once), then a "soon"
--   save. DuelResult.coins is what was really paid, with the blocked reason when it is 0 (duel.rewardsReduced rides
--   along when a same-pair reward was reduced). init wires the profile hooks (profileReady, duelLog, samePair) to
--   EconomyService; a module that was never wired (a unit-test clone) has no profile system, so no progress failed to
--   load and duel.noRewardsOffline stays out of the DuelResult (shownBlockedReason, §0.3 #9). One `reward` line per
--   real participant of a Result is logged.
--   MatchEnded fires exactly once per matchId with the outcome, every participant's view, reward and coinsGranted,
--   bailers and the players to requeue at the front (QueueService reads it).
-- * Result hooks (Part 7): DuelResult.questProgress and DuelResult.tip come from the hooks the layers above register
--   with setResultHooks({questProgress, tip}) from their init (this module never requires them: upward wiring only,
--   §2.6). For each real participant (a Player, never the test dummy), after its ParticipantSummary is built and
--   before its DuelResult goes out, each hook is called once as hook(player, summary, info) with info = {matchId,
--   outcome = the DuelRules outcome kind, reason, activeSeconds}, inside pcall: an error is logged and leaves {} / nil,
--   so it never breaks the result (resultExtras). Reading (DESIGN §2.6 has QuestService and TipService listen to
--   MatchEnded, but DuelResult carries their answers and goes out before MatchEnded): the duel counts for quests and
--   the tip is decided here, once per participant, and not on MatchEnded, so nothing counts twice.
-- * Returning (and Cancelled / Void): after the client's fade (ReturnFadeSeconds), every real player still in the game
--   who was moved into the arena is teleported to the least-recently-used lobby return point (WorldLayout.ReturnPoints,
--   the SD_ReturnPoint data), movement is restored and SD_MatchId / SD_DuelPhase are cleared; then the slot is
--   released (only if it still holds this match) and the match is forgotten.
-- Lobby stats never enter a match (duel isolation, §17.9 #8).
-- * Practice bot (2026-10-16, BotService through QueueService.startWithBot): one participant may be a bot (a
--   Player-shaped table with kind "bot" and isBot = true, on live servers too). It rides the test dummy's server
--   paths (no Player: no DuelResult, no reward, no save, no quest; its own displayName and squishyId) except that
--   DuelState shows it as a player (isTestDummy false, its name). The human's reward is computed and paid as in any
--   duel. A match needs at least one real Player.
-- * MATCH FOUND (round 2 of the match flow, 2026-10-25): startMatch's holdSeconds (a queue duel) sends each real player
--   MatchFound (Logic/MatchFoundRoster: both names, squishies and Grip levels) and holds the `streamed` events until
--   then, so the lobby's show plays before the teleport.

-- Services

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)
local Logic = script.Parent.Parent.Logic
local DuelRewards = require(Logic.DuelRewards)
local DuelRules = require(Logic.DuelRules)
local MatchFoundRoster = require(Logic.MatchFoundRoster)
local AbilityService = require(script.Parent.AbilityService)
local ArenaService = require(script.Parent.ArenaService)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)
local EconomyService = require(script.Parent.EconomyService)
local GripService = require(script.Parent.GripService)
local InventoryService = require(script.Parent.InventoryService)
local NetService = require(script.Parent.NetService)
local ShutdownService = require(script.Parent.ShutdownService)

-- Types

-- "A" or "B", held as DuelRules' SideName (a string: the checker widens the singleton union in locals); payloads get
-- Types.Side through publicSide.
type Side = DuelRules.SideName
type Phase = Types.DuelPhase
-- A Util/Cleanup as stored in records (its generic add<T>() trips the exact record comparison of the type checker).
type Trove = {
	add: (self: any, item: any) -> any,
	clean: (self: any) -> (),
}
type Slot = ArenaService.Slot
type Fighter = CombatService.Fighter
type MatchPort = CombatService.MatchPort
type MatchState = DuelRules.MatchState
type Effect = DuelRules.Effect
type Event = DuelRules.Event
type Outcome = DuelRules.Outcome
type Reward = DuelRewards.Reward

type SavedMovement = { walkSpeed: number, jumpHeight: number, jumpPower: number }

type Participant = {
	ref: any, -- the Player, or the Studio test dummy table
	player: Player?, -- nil for the test dummy
	userId: number,
	isTestDummy: boolean,
	displayName: string,
	squishyId: string,
	side: Side,
	fighter: Fighter,
	moved: boolean, -- teleported into the arena: must be returned
	positioning: boolean, -- a pad teleport is in flight
	missingSince: number?,
	missingSent: boolean,
	savedMovement: SavedMovement?,
}

type Sides = { A: Participant, B: Participant }

type Match = {
	matchId: string,
	state: MatchState,
	slot: Slot,
	port: MatchPort,
	sides: Sides,
	list: { Participant },
	arenaView: Types.DuelArenaView,
	cleanup: Trove, -- the match's connections (a Util/Cleanup)
	pending: { Effect }, -- effects of applyHits, performed by flush
	stateDirty: boolean, -- DuelState must be re-sent
	returning: boolean,
	closed: boolean,
	endedFired: boolean,
	createdAt: number,
	holdUntil: number?, -- round 2 of the match flow: the MATCH FOUND show plays until then (no teleport before)
}

-- What getMatch / startMatch return (read-only).
export type MatchView = {
	matchId: string,
	phase: Phase,
	side: Types.Side,
	opponentUserId: number,
	slot: number,
}

export type ParticipantSummary = {
	userId: number,
	player: Player?,
	isTestDummy: boolean,
	side: Types.Side,
	squishyId: string,
	opponentUserId: number,
	outcome: Types.DuelOutcome, -- this participant's view
	reasonKey: string,
	throws: number,
	hits: number,
	livesLeft: number,
	rewardsEnabled: boolean,
	reward: Reward?, -- Result only, real players only: what Logic/DuelRewards computed
	coinsGranted: number, -- what EconomyService really paid (0 when nothing was paid)
	bailed: boolean,
	requeueFront: boolean,
}

-- The MatchEnded payload. `outcome` is the DuelRules outcome kind ("win", "draw", "cancelled", "void").
export type MatchSummary = {
	matchId: string,
	outcome: string,
	reason: string,
	endedFrom: Phase,
	activeSeconds: number,
	result: Outcome,
	participants: { ParticipantSummary },
	bailers: { number }, -- userIds: BailRequeueCooldownSeconds (QueueService)
	requeueUserIds: { number }, -- userIds requeued at the front (QueueService)
	noRequeue: boolean,
}

-- init replaces these with EconomyService's (setHooks): whether a profile is ready, its duelLog (the matchId check)
-- and its same-pair record (§6.7).
export type Hooks = {
	profileReady: (player: Player) -> boolean,
	duelLog: (player: Player) -> { Types.DuelLogEntry },
	samePair: (player: Player) -> Types.SamePairRecord,
}

-- What a result hook gets next to the player and its ParticipantSummary. `outcome` is the DuelRules outcome kind
-- ("win", "draw", "cancelled", "void"); the participant's own view is summary.outcome.
export type ResultInfo = { matchId: string, outcome: string, reason: string, activeSeconds: number }

-- The DuelResult hooks (setResultHooks): questProgress -> DuelResult.questProgress, tip -> DuelResult.tip.
export type ResultHooks = {
	questProgress: (player: Player, summary: ParticipantSummary, info: ResultInfo) -> { Types.QuestProgressLine },
	tip: (player: Player, summary: ParticipantSummary, info: ResultInfo) -> string?,
}

-- The part of EconomyService settleReward uses (tests pass a fake).
export type RewardPayer = {
	grantDuelResult: (
		player: any,
		matchId: string,
		outcome: string,
		result: EconomyService.DuelResultInput
	) -> EconomyService.DuelGrant,
}

-- What one participant is paid and shown (DuelResult.coins / coinsBlockedReason).
export type Settlement = { coins: number, coinsBlockedReason: string? }

-- Constants

local RULES = Config.Duel.Rules
local POSITIONING = Config.Duel.Positioning
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_PHASE = "SD_DuelPhase"
local PRE_ACTIVE: { [string]: boolean } = { Preparing = true, Positioning = true, Countdown = true }
local RETURN_PHASES: { [string]: boolean } = { Returning = true, Cancelled = true, Void = true }
local POLL_SECONDS = 0.1
local RETURN_PADDING_SECONDS = 1 -- reading: extra time a return may take beyond the stream timeout
-- Reading (§5.4 "return anyone in the arena"): a character is in the arena when its root is within this many studs
-- (horizontally) of the slot's Origin. Slots are >= 200 studs apart and the lobby is >= 250 studs away, so a player
-- who died and respawned in the lobby is never pulled to the return point. 120 covers the Bounds (76 x 108) and the
-- decor apron around them.
local ARENA_RADIUS_STUDS = 120
local NOTIFY_OUT_OF_BOUNDS = "duel.outOfBounds"
local KEY_VOID = "duel.void"
local KEY_CANCELLED = "duel.cancelled"
local KEY_OPPONENT_LEFT_EARLY = "duel.opponentLeftEarly"
local RESULT_KEY_PREFIX = "duel.result."
local REASON_NO_REWARDS_OFFLINE = "duel.noRewardsOffline"

-- Module table

local DuelService = {}

-- (summary: MatchSummary) exactly once per match, on its single end (Result, Cancelled or Void).
DuelService.MatchEnded = Signal.new() :: Signal.Signal<MatchSummary>

-- Private

local log = Log.new("Duel")
local matches: { [string]: Match } = {}
local matchOfUser: { [number]: Match } = {}
local returnPointUsedAt: { [number]: number } = {} -- ReturnPoints index -> os.clock() of its last use
local heartbeat: RBXScriptConnection? = nil
local rng = Random.new()

local hooks: Hooks = {
	-- Until init wires EconomyService's (a unit-test clone never is) no profile is ever ready and duel rewards stay
	-- at 0 (duel.noRewardsOffline in the log only: see profilesWired).
	profileReady = function(_player: Player): boolean
		return false
	end,
	duelLog = function(_player: Player): { Types.DuelLogEntry }
		return {}
	end,
	samePair = function(_player: Player): Types.SamePairRecord
		return {}
	end,
}
-- The DuelResult hooks (setResultHooks). Until a layer above registers one, DuelResult carries no quest lines and no tip.
local resultHooks: ResultHooks = {
	questProgress = function(
		_player: Player,
		_summary: ParticipantSummary,
		_info: ResultInfo
	): { Types.QuestProgressLine }
		return {}
	end,
	tip = function(_player: Player, _summary: ParticipantSummary, _info: ResultInfo): string?
		return nil
	end,
}
-- True once setHooks supplied profileReady (init always does). Until then no profile system is wired at all, so a
-- DuelResult never says "Your progress didn't load" (duel.noRewardsOffline would be untrue, §0.3 #9): the
-- reward line is left out and the reward the rules would give is only logged.
local profilesWired = false

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function otherSide(side: Side): Side
	return if side == "A" then "B" else "A"
end

-- A side as payloads type it.
local function publicSide(side: Side): Types.Side
	if side == "B" then
		return "B"
	end
	return "A"
end

-- The matches as a list (iterating a copy lets a handler close a match while the loop runs).
local function matchList(): { Match }
	local list: { Match } = {}
	for _, match in matches do
		table.insert(list, match)
	end
	return list
end

-- The participant on `side`.
local function onSide(match: Match, side: Side): Participant
	return if side == "A" then match.sides.A else match.sides.B
end

-- pcall for a function that returns nothing; the error (or nil) comes back as the second value.
local function try(fn: (...any) -> ...any, ...: any): (boolean, any)
	local ok, err = pcall(fn :: any, ...)
	return ok, err
end

local function isRealPlayer(ref: any): boolean
	return typeof(ref) == "Instance" and ref:IsA("Player") and ref.Parent == Players
end

local function isTestDummy(ref: any): boolean
	return type(ref) == "table" and ref.isTestDummy == true and ref.kind == "testDummy"
end

-- The practice bot (BotService), accepted on live servers (see the header).
local function isBot(ref: any): boolean
	return type(ref) == "table" and ref.isBot == true and ref.kind == "bot"
end

-- The Studio test dummy is accepted only in Studio with the harness flag on (§12 #21).
local function dummyAllowed(): boolean
	return RunService:IsStudio() and Config.Debug.testHarness == true
end

local function userIdOf(ref: any): number?
	if typeof(ref) == "Instance" then
		return if ref:IsA("Player") then ref.UserId else nil
	elseif type(ref) == "number" then
		return ref
	elseif type(ref) == "table" then
		local id = ref.userId or ref.UserId
		return if type(id) == "number" then id else nil
	end
	return nil
end

local function isPresent(p: Participant): boolean
	local ref = p.ref
	if p.player then
		return p.player.Parent == Players
	end
	return type(ref) == "table" and ref.Parent ~= nil
end

local function setAttribute(p: Participant, name: string, value: any)
	local ref = p.ref
	if p.player then
		p.player:SetAttribute(name, value)
	elseif type(ref) == "table" and type(ref.SetAttribute) == "function" then
		pcall(ref.SetAttribute, ref, name, value)
	end
end

local function characterOf(p: Participant): Model?
	local character = p.ref.Character
	if typeof(character) == "Instance" and character:IsA("Model") then
		return character
	end
	return nil
end

local function humanoidOf(p: Participant): Humanoid?
	local character = characterOf(p)
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

-- §5.4: R15 HipHeight + HRP.Size.Y/2 + R15ExtraHeight; R6 (or unknown) R6Height.
local function standHeight(character: Model?): number
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 and root and root:IsA("BasePart") then
		return humanoid.HipHeight + root.Size.Y / 2 + POSITIONING.R15ExtraHeight
	end
	return POSITIONING.R6Height
end

local function placementFor(match: Match, p: Participant): CFrame?
	return ArenaService.placementCFrame(match.slot, p.side, standHeight(characterOf(p)))
end

-- Movement (§5.4): frozen from Positioning through Countdown, Rules.Movement from Active, the saved values after.
local function freezeMovement(p: Participant)
	local humanoid = humanoidOf(p)
	if humanoid == nil then
		return
	end
	if p.savedMovement == nil then
		-- A 0 here is a hold, not the lobby value (e.g. a practice Dragon Rush root): the lobby default is saved
		-- instead, so the return never strands the player without movement.
		local walk, jump, power = humanoid.WalkSpeed, humanoid.JumpHeight, humanoid.JumpPower
		p.savedMovement = {
			walkSpeed = if walk > 0 then walk else RULES.Movement.WalkSpeed,
			jumpHeight = if jump > 0 then jump else RULES.Movement.JumpHeight,
			jumpPower = if power > 0 then power else StarterPlayer.CharacterJumpPower,
		}
	end
	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	end
end

local function duelMovement(p: Participant)
	local humanoid = humanoidOf(p)
	if humanoid == nil then
		return
	end
	humanoid.WalkSpeed = RULES.Movement.WalkSpeed
	humanoid.JumpHeight = RULES.Movement.JumpHeight
	local saved = p.savedMovement
	if humanoid.UseJumpPower and saved then
		humanoid.JumpPower = saved.jumpPower
	end
end

local function restoreMovement(p: Participant)
	local humanoid = humanoidOf(p)
	local saved = p.savedMovement
	if humanoid == nil or saved == nil then
		return
	end
	humanoid.WalkSpeed = saved.walkSpeed
	humanoid.JumpHeight = saved.jumpHeight
	humanoid.JumpPower = saved.jumpPower
	p.savedMovement = nil
end

local function accuracy(hits: number, throws: number): number
	if throws <= 0 then
		return 0
	end
	return math.floor(math.min(1, hits / throws) * 100 + 0.5)
end

local function viewOutcome(outcome: Outcome, side: Side): Types.DuelOutcome
	local view: Types.DuelOutcome = "void"
	if outcome.kind == "win" then
		view = if outcome.winner == side then "win" else "loss"
	elseif outcome.kind == "draw" then
		view = "draw"
	elseif outcome.kind == "cancelled" then
		view = "cancelled"
	end
	return view
end

-- The DuelResult line under the title (Strings duel.*), for this participant's view of the outcome.
local function reasonKeyFor(state: MatchState, outcome: Outcome, side: Side, view: Types.DuelOutcome): string
	if view == "void" then
		return KEY_VOID
	elseif view == "cancelled" then
		if outcome.requeue == side and PRE_ACTIVE[outcome.endedFrom] then
			return KEY_OPPONENT_LEFT_EARLY
		end
		return KEY_CANCELLED
	end
	local won = view == "win"
	local reason = outcome.reason
	if reason == "opponentLeft" then
		-- A bail after EarlyForfeitSeconds; repeated out-of-bounds gets its own line.
		local loser = outcome.loser
		local tooManyOob = loser ~= nil
			and DuelRules.participant(state, loser).outOfBounds > state.duel.Rules.OutOfBounds.MaxPerMatch
		if tooManyOob then
			return if won then "duel.opponentOutOfBounds" else "duel.youOutOfBounds"
		end
		return if won then "duel.opponentLeft" else "duel.youLeft"
	elseif reason == "eliminated" then
		return if won then "duel.opponentOut" else "duel.youOut"
	elseif reason == "timeUp" and view ~= "draw" then
		return if won then "duel.timeUpWin" else "duel.timeUpLoss"
	elseif reason == "suddenDeath" then
		return if won then "duel.suddenDeathWin" else "duel.suddenDeathLoss"
	elseif reason == "suddenDeathTimeout" then
		return "duel.suddenDeathDraw"
	elseif reason == "doubleKo" then
		return "duel.tieHit"
	elseif reason == "outOfBounds" then
		return if won then "duel.opponentOutOfBounds" else "duel.youOutOfBounds"
	end
	return RESULT_KEY_PREFIX .. view
end

local function participantView(match: Match, p: Participant): Types.DuelParticipantView
	return {
		userId = p.userId,
		displayName = p.displayName,
		squishyId = p.squishyId,
		side = publicSide(p.side),
		lives = DuelRules.participant(match.state, p.side).lives,
		ultReady = AbilityService.isReady(p.userId),
		isTestDummy = p.isTestDummy and not isBot(p.ref), -- the practice bot shows its own name
	}
end

-- Round 2 of the match flow: the lobby's MATCH FOUND show (MatchFound) for each real player of a queue duel.
local function sendFound(match: Match)
	local entries: { MatchFoundRoster.Entry } = {}
	for _, p in match.list do
		local player = p.player
		table.insert(entries, {
			userId = p.userId,
			name = p.displayName,
			squishy = p.squishyId,
			level = if player and not p.isTestDummy then GripService.levelOf(player) else nil,
		})
	end
	local view = MatchFoundRoster.build("1v1", entries, rng)
	for _, p in match.list do
		local player = p.player
		if player and not p.isTestDummy then
			local ok, err = pcall(NetService.fire, "MatchFound", player, view)
			if not ok then
				log:warn(`MatchFound to user {p.userId} failed:`, err)
			end
		end
	end
end

local function sendDuelState(match: Match)
	local state = match.state
	local endsAt = if state.phaseEndsAt == math.huge then 0 else state.phaseEndsAt -- 0 = no timer
	for _, p in match.list do
		local player = p.player
		if player then
			local view: Types.DuelStateView = {
				matchId = match.matchId,
				phase = state.phase,
				phaseEndsAt = endsAt,
				you = participantView(match, p),
				opponent = participantView(match, onSide(match, otherSide(p.side))),
				arena = match.arenaView,
				rules = RULES,
			}
			NetService.fire("DuelState", player, view)
		end
	end
end

local function syncFighters(match: Match)
	for _, p in match.list do
		p.fighter.invulnUntil = DuelRules.participant(match.state, p.side).invulnUntil
	end
end

-- Private: lifecycle -------------------------------------------------------------------------------------------------

local perform: (match: Match, effect: Effect) -> ()

-- One DuelRules event: the new state is stored first, then its effects run (none of them yields). The projectiles are
-- swept up to the same time first (CombatService.syncTo), so a hit whose impact comes before a phase deadline is
-- applied before that deadline fires here (DuelRules: timed transitions happen at their deadline).
local function stepMatch(match: Match, event: Event, now: number?)
	if match.closed then
		return
	end
	local t = if now ~= nil then now else serverNow()
	CombatService.syncTo(t)
	if match.closed then
		return
	end
	local state, effects = DuelRules.step(match.state, event, t)
	match.state = state
	syncFighters(match)
	for _, effect in effects do
		perform(match, effect)
	end
	if match.stateDirty and not match.closed then
		match.stateDirty = false
		sendDuelState(match)
	end
end

local function stopHeartbeatIfIdle()
	if next(matches) == nil and heartbeat ~= nil then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

-- The terminal cleanup (§5.4): unregister from combat and abilities, release the slot if it still holds this match,
-- clear the attributes and forget the match.
local function closeMatch(match: Match)
	if match.closed then
		return
	end
	match.closed = true
	local matchId = match.matchId
	try(CombatService.unregisterMatch, matchId)
	try(AbilityService.detachMatch, matchId)
	local slot = match.slot
	if slot.inUse and slot.matchId == matchId then
		ArenaService.release(slot)
	end
	for _, p in match.list do
		if matchOfUser[p.userId] == match then
			matchOfUser[p.userId] = nil
		end
		setAttribute(p, ATTR_PHASE, "")
		setAttribute(p, ATTR_MATCH_ID, "")
	end
	matches[matchId] = nil
	match.cleanup:clean()
	stopHeartbeatIfIdle()
	log:info(`match {matchId} closed`)
end

local function safeClose(match: Match)
	local ok, err = try(closeMatch, match)
	if not ok then
		log:error(`closing match {match.matchId} failed:`, err)
	end
end

-- The least-recently-used lobby return point, as a placement CFrame for this character.
local function returnCFrame(p: Participant): CFrame?
	local points = WorldLayout.ReturnPoints
	local bestIndex: number? = nil
	for index in points do
		if bestIndex == nil or (returnPointUsedAt[index] or 0) < (returnPointUsedAt[bestIndex] or 0) then
			bestIndex = index
		end
	end
	if bestIndex == nil then
		return nil
	end
	returnPointUsedAt[bestIndex] = os.clock()
	local point = points[bestIndex]
	local position = point.position
	return CFrame.lookAt(position, position + point.facing) + Vector3.new(0, standHeight(characterOf(p)), 0)
end

-- True when the participant's character stands in (or around) this match's arena.
local function inArena(match: Match, p: Participant): boolean
	local root = CharacterService.getRoot(p.ref)
	if root == nil then
		return false
	end
	local offset = root.Position - match.slot.origin.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= ARENA_RADIUS_STUDS
end

local function returnOne(match: Match, p: Participant)
	if p.moved and p.player and isPresent(p) and inArena(match, p) then
		local cf = returnCFrame(p)
		if cf then
			local moved, reason = CharacterService.teleportAsync(p.player, cf)
			if not moved then
				log:warn(`could not return user {p.userId} to the lobby ({tostring(reason)}); they respawn there`)
			end
		end
	end
	restoreMovement(p)
	setAttribute(p, ATTR_PHASE, "")
	setAttribute(p, ATTR_MATCH_ID, "")
end

local function anyPositioning(match: Match): boolean
	for _, p in match.list do
		if p.positioning then
			return true
		end
	end
	return false
end

-- Returning / Cancelled / Void: bring everyone who was moved back to the lobby, then report `returned`.
local function returnPlayers(match: Match)
	local limit = POSITIONING.StreamAroundTimeoutSeconds + RETURN_PADDING_SECONDS
	local deadline = os.clock() + limit
	while anyPositioning(match) and os.clock() < deadline do
		task.wait(POLL_SECONDS) -- a pad teleport still in flight must not be left behind in the arena
	end
	-- The client fades out first (§9.14). Reading: also before a Cancelled / Void return, so every return looks alike.
	task.wait(POSITIONING.ReturnFadeSeconds)
	local pending = #match.list
	for _, p in match.list do
		task.spawn(function()
			local ok, err = try(returnOne, match, p)
			if not ok then
				log:error(`returning user {p.userId} failed:`, err)
			end
			pending -= 1
		end)
	end
	deadline = os.clock() + limit
	while pending > 0 and os.clock() < deadline do
		task.wait(POLL_SECONDS)
	end
	local ok, err = try(stepMatch, match, { kind = "returned" })
	if not ok then
		log:error(`match {match.matchId} could not report its return:`, err)
	end
	if not match.closed then
		safeClose(match) -- DuelRules already closed it, or this is the fallback
	end
end

local function startReturn(match: Match)
	if match.returning or match.closed then
		return
	end
	match.returning = true
	-- Deferred: the effects of the step that ended the match (DuelResult, MatchEnded) run first, and the return never
	-- re-enters stepMatch while that step's effects are still being performed.
	task.defer(returnPlayers, match)
end

local function positionParticipant(match: Match, p: Participant)
	p.positioning = true
	local ok, err = pcall(function(): any
		while not match.closed and match.state.phase == "Positioning" and serverNow() < match.state.phaseEndsAt do
			if CharacterService.isAlive(p.ref) and CharacterService.getRoot(p.ref) ~= nil then
				local cf = placementFor(match, p)
				if cf == nil then
					return nil
				end
				local moved = CharacterService.teleportAsync(p.ref, cf)
				if moved then
					p.moved = true
					CombatService.noteTeleport(p.fighter)
					freezeMovement(p)
					if match.state.phase == "Positioning" then
						stepMatch(match, { kind = "positioned", side = p.side })
					end
					return nil
				end
			end
			task.wait(POLL_SECONDS)
		end
		return nil
	end)
	p.positioning = false
	if not ok then
		log:error(`positioning user {p.userId} failed:`, err)
	end
end

local function streamParticipant(match: Match, p: Participant)
	local player = p.player
	local pad = ArenaService.padCFrame(match.slot, p.side)
	if player and pad then
		local ok, err = pcall(function(): any
			player:RequestStreamAroundAsync(pad.Position, POSITIONING.StreamAroundTimeoutSeconds)
			return nil
		end)
		if not ok then
			log:warn(`stream request for user {p.userId} failed; continuing:`, err)
		end
	end
	-- Round 2 of the match flow: the lobby's MATCH FOUND show plays before the teleport (DuelRules' Preparing timeout
	-- already includes the wait).
	local holdUntil = match.holdUntil
	if holdUntil and holdUntil > serverNow() then
		task.wait(holdUntil - serverNow())
	end
	if not match.closed and match.state.phase == "Preparing" then
		stepMatch(match, { kind = "streamed", side = p.side })
	end
end

local function onPhase(match: Match, phase: Phase, startedAt: number)
	match.stateDirty = true
	for _, p in match.list do
		setAttribute(p, ATTR_PHASE, phase)
	end
	if phase == "Positioning" then
		for _, p in match.list do
			p.positioning = true -- set now: a return that starts before the deferred thread runs must wait for it
			task.defer(positionParticipant, match, p) -- never re-enters stepMatch from inside this step
		end
	elseif phase == "Active" then
		for _, p in match.list do
			p.fighter.nextThrowAt = startedAt -- §5.4: nextThrowAt = now at Active start
			duelMovement(p)
		end
	elseif RETURN_PHASES[phase] then
		startReturn(match)
	end
end

local function rewardText(reward: Reward): string
	return string.format(
		"coins=%d base=%d x%.2f eligible=%s blocked=%s reduced=%s",
		reward.coins,
		reward.base,
		reward.multiplier,
		tostring(reward.eligible),
		reward.coinsBlockedReason or "-",
		reward.reducedReason or "-"
	)
end

-- What the same rules would give if this participant's profile were ready (logged next to the real reward while no
-- profile can be ready, so the reward rules are visible in Part 4).
local function rewardIfReady(state: MatchState, side: Side, history: DuelRewards.RewardHistory, now: number): Reward
	local copy = table.clone(state)
	copy.participants = { A = table.clone(state.participants.A), B = table.clone(state.participants.B) }
	DuelRules.participant(copy, side).rewardsEnabled = true
	return DuelRewards.compute(copy, publicSide(side), history, now)
end

-- The single end of the match (DuelRules `ended`): rewards (paid once through EconomyService), DuelResult,
-- MatchEnded. Exactly once.
local function onEnded(match: Match, outcome: Outcome)
	if match.endedFired then
		return
	end
	match.endedFired = true -- the exactly-once guard (DuelRules also ends a match only once)
	local state = match.state
	local payRewards = outcome.kind == "win" or outcome.kind == "draw"
	local nowUnix = os.time() -- the duelLog clock (§2.11)
	local info: ResultInfo = {
		matchId = match.matchId,
		outcome = outcome.kind,
		reason = outcome.reason,
		activeSeconds = outcome.activeSeconds,
	}

	local summaries: { ParticipantSummary } = {}
	for _, p in match.list do
		local side = p.side
		local record = DuelRules.participant(state, side)
		local view: Types.DuelOutcome = viewOutcome(outcome, side)
		local reasonKey = reasonKeyFor(state, outcome, side, view)
		local reward: Reward? = nil
		local settled: Settlement = { coins = 0, coinsBlockedReason = nil }
		local player = p.player
		if payRewards and player and not p.isTestDummy then
			local history: DuelRewards.RewardHistory =
				{ duelLog = hooks.duelLog(player), samePair = hooks.samePair(player) }
			local computed = DuelRewards.compute(state, publicSide(side), history, nowUnix)
			reward = computed
			local ok, result = pcall(
				DuelService.settleReward,
				player,
				match.matchId,
				view,
				computed,
				DuelService.eliminationsFor(outcome, view)
			)
			if ok then
				settled = result
			else
				log:error(`paying the reward of user {p.userId} in match {match.matchId} failed:`, result)
			end
			local preview = if record.rewardsEnabled
				then ""
				else " ifProfileReady[" .. rewardText(rewardIfReady(state, side, history, nowUnix)) .. "]"
			local computedText = rewardText(computed)
			log:info(
				`reward match={match.matchId} user={p.userId} outcome={view} granted={settled.coins} {computedText}{preview}`
			)
		end
		local summary: ParticipantSummary = {
			userId = p.userId,
			player = player,
			isTestDummy = p.isTestDummy,
			side = publicSide(side),
			squishyId = p.squishyId,
			opponentUserId = onSide(match, otherSide(side)).userId,
			outcome = view,
			reasonKey = reasonKey,
			throws = record.throws,
			hits = record.hits,
			livesLeft = record.lives,
			rewardsEnabled = record.rewardsEnabled,
			reward = reward,
			coinsGranted = settled.coins,
			bailed = outcome.bailer == side,
			requeueFront = outcome.requeue == side,
		}
		table.insert(summaries, summary)
		if player then
			local questProgress, tip = DuelService.resultExtras(summary, info)
			local payload: Types.DuelResultPayload = {
				matchId = match.matchId,
				outcome = view,
				reasonKey = reasonKey,
				coins = settled.coins,
				coinsBlockedReason = settled.coinsBlockedReason,
				stats = { throws = record.throws, hits = record.hits, accuracy = accuracy(record.hits, record.throws) },
				questProgress = questProgress,
				tip = tip,
			}
			NetService.fire("DuelResult", player, payload)
		end
	end

	if outcome.kind == "win" and outcome.winner then
		CombatService.recordWin(onSide(match, outcome.winner).squishyId)
	end
	local a, b = state.participants.A, state.participants.B
	log:info(
		string.format(
			"match %s ended outcome=%s reason=%s from=%s active=%.1fs winner=%s A[user=%d lives=%d throws=%d hits=%d] B[user=%d lives=%d throws=%d hits=%d]",
			match.matchId,
			outcome.kind,
			outcome.reason,
			outcome.endedFrom,
			outcome.activeSeconds,
			if outcome.winner then tostring(onSide(match, outcome.winner).userId) else "-",
			a.userId,
			a.lives,
			a.throws,
			a.hits,
			b.userId,
			b.lives,
			b.throws,
			b.hits
		)
	)

	local bailers: { number } = {}
	if outcome.bailer then
		table.insert(bailers, onSide(match, outcome.bailer).userId)
	end
	local requeue: { number } = {}
	if outcome.requeue then
		table.insert(requeue, onSide(match, outcome.requeue).userId)
	end
	DuelService.MatchEnded:fire({
		matchId = match.matchId,
		outcome = outcome.kind,
		reason = outcome.reason,
		endedFrom = outcome.endedFrom,
		activeSeconds = outcome.activeSeconds,
		result = outcome,
		participants = summaries,
		bailers = bailers,
		requeueUserIds = requeue,
		noRequeue = #requeue == 0,
	})
end

local function onRepivot(match: Match, effect: Effect)
	local side = effect.side
	local p = if side then onSide(match, side) else nil
	if p == nil then
		return
	end
	local cf = placementFor(match, p)
	if cf then
		CombatService.pivotFighter(p.fighter, cf)
	end
	if not effect.silent and p.player then
		NetService.notify(p.player, NOTIFY_OUT_OF_BOUNDS, nil, "warn")
	end
end

perform = function(match: Match, effect: Effect)
	local kind = effect.kind
	if kind == "phase" then
		onPhase(match, effect.phase :: Phase, effect.startedAt or serverNow())
	elseif kind == "ended" then
		local outcome = effect.outcome
		if outcome then
			onEnded(match, outcome)
		end
	elseif kind == "lifeLost" then
		match.stateDirty = true
	elseif kind == "repivot" then
		onRepivot(match, effect)
	elseif kind == "notify" then
		local side = effect.side
		local p = if side then onSide(match, side) else nil
		if p and p.player and effect.key then
			NetService.notify(p.player, effect.key, nil, "info")
		end
	elseif kind == "forceReturn" then
		startReturn(match)
	elseif kind == "closed" then
		safeClose(match)
	end
	-- `requeue` / `requeueCooldown` reach QueueService through MatchEnded (requeueUserIds, bailers).
end

local function checkPresence(match: Match, now: number)
	if match.state.ended then
		return
	end
	for _, p in match.list do
		if CharacterService.getRoot(p.ref) == nil then
			local since = p.missingSince or now
			p.missingSince = since
			if not p.missingSent and now - since > POSITIONING.MissingRootSeconds then
				p.missingSent = true
				stepMatch(match, { kind = "missing", side = p.side }, now)
			end
		else
			p.missingSince = nil
			if p.missingSent then
				p.missingSent = false
				stepMatch(match, { kind = "found", side = p.side }, now)
			end
		end
	end
end

local function tickMatch(match: Match, now: number)
	if match.closed then
		return
	end
	checkPresence(match, now)
	stepMatch(match, { kind = "tick" }, now) -- DuelRules runs every timer that is due
end

local function tickAll()
	local now = serverNow()
	for _, match in matchList() do
		local ok, err = try(tickMatch, match, now)
		if not ok then
			log:error(`match {match.matchId} tick failed; voiding it:`, err)
			local okError, errError = try(stepMatch, match, { kind = "error" }, now)
			if not okError then
				log:error(`match {match.matchId} could not be voided; forcing cleanup:`, errError)
				safeClose(match)
			end
		end
	end
end

local function ensureHeartbeat()
	if heartbeat == nil then
		heartbeat = RunService.Heartbeat:Connect(tickAll)
	end
end

local function participantOf(ref: any): (Match?, Participant?)
	local userId = userIdOf(ref)
	if userId == nil then
		return nil, nil
	end
	local match = matchOfUser[userId]
	if match == nil or match.closed then
		return nil, nil
	end
	for _, p in match.list do
		if p.userId == userId then
			return match, p
		end
	end
	return nil, nil
end

local function snapshotSquishy(ref: any): string
	local id: any = nil
	if isTestDummy(ref) or isBot(ref) then
		id = ref.squishyId
	elseif typeof(ref) == "Instance" and ref:IsA("Player") then
		id = InventoryService.getEquipped(ref)
	end
	return if Catalog.isValidId(id) then id else Catalog.starterId()
end

local function buildPort(match: Match, fighters: { Fighter }, slot: Slot): MatchPort
	local port: MatchPort = {
		matchId = match.matchId,
		arena = {
			slot = slot.index,
			floorY = slot.floorY,
			killY = slot.killY,
			zones = slot.zones,
			geometry = slot.geometry,
			raycastParams = slot.raycastParams,
			overlapParams = slot.overlapParams,
		},
		fighters = fighters,
		phase = function(): string
			return match.state.phase
		end,
		cooldownMultiplier = function(): number
			return DuelRules.cooldownMultiplier(match.state)
		end,
		placement = function(fighter: Fighter): CFrame?
			return placementFor(match, onSide(match, fighter.side))
		end,
		canBeHit = function(victim: Fighter, at: number): boolean
			return not match.closed and DuelRules.canBeHit(match.state, victim.side, at)
		end,
		applyHits = function(hits: { CombatService.HitRequest }, now: number): { [number]: CombatService.HitOutcome }
			local outcomes: { [number]: CombatService.HitOutcome } = {}
			if match.closed then
				return outcomes
			end
			local list: { DuelRules.Hit } = {}
			for index, hit in hits do
				-- Feature 1: a caught throw's burst may cost the life inside invulnerability (hit.force).
				list[index] = { victim = hit.victim.side, at = hit.at, force = hit.force == true }
			end
			-- `now` = the time the projectiles were swept to: the timers never run past what was simulated.
			local state, effects = DuelRules.step(match.state, { kind = "hits", hits = list }, now)
			match.state = state
			syncFighters(match)
			local used: { [number]: boolean } = {}
			for _, effect in effects do
				if effect.kind == "lifeLost" then
					for index, hit in hits do
						if not used[index] and hit.victim.side == effect.side and hit.at == effect.at then
							used[index] = true
							outcomes[index] = {
								lives = effect.lives or 0,
								invulnUntil = effect.invulnUntil or hit.at,
								eliminated = effect.eliminated == true,
							}
							break
						end
					end
				end
				table.insert(match.pending, effect)
			end
			return outcomes
		end,
		flush = function()
			local effects = match.pending
			match.pending = {}
			for _, effect in effects do
				perform(match, effect)
			end
			if match.stateDirty and not match.closed then
				match.stateDirty = false
				sendDuelState(match)
			end
		end,
		throwAccepted = function(fighter: Fighter)
			stepMatch(match, { kind = "throwAccepted", side = fighter.side })
		end,
		outOfBounds = function(fighter: Fighter)
			stepMatch(match, { kind = "oob", side = fighter.side })
		end,
		sync = function(now: number)
			stepMatch(match, { kind = "tick" }, now)
		end,
	}
	return port
end

local function newParticipant(ref: any, side: Side, now: number): Participant
	local dummy = isTestDummy(ref) or isBot(ref) -- the practice bot rides the dummy's server paths (see the header)
	local player: Player? = if dummy then nil else ref
	local userId = userIdOf(ref) :: number
	local displayName = if dummy
		then (if type(ref.displayName) == "string" then ref.displayName else Strings.duel.testDummy)
		else (ref :: Player).DisplayName
	local squishyId = snapshotSquishy(ref)
	local fighter = CombatService.newFighter({
		userId = userId,
		player = player,
		isTestDummy = dummy,
		side = publicSide(side),
		squishyId = squishyId,
		getRoot = function(): BasePart?
			return CharacterService.getRoot(ref)
		end,
		isAlive = function(): boolean
			return CharacterService.isAlive(ref)
		end,
		now = now,
	})
	return {
		ref = ref,
		player = player,
		userId = userId,
		isTestDummy = dummy,
		displayName = displayName,
		squishyId = squishyId,
		side = side,
		fighter = fighter,
		moved = false,
		positioning = false,
		missingSince = nil,
		missingSent = false,
		savedMovement = nil,
	}
end

-- Public: matches ------------------------------------------------------------------------------------------------------

-- Starts a match between a and b (Players; one may be the Studio test dummy in Studio). `slot` is the arena slot the
-- caller acquired (QueueService); without one a slot is acquired here. Returns (view, nil) or (nil, why) with an
-- internal reason (QueueService logs it and releases its slot).
-- Practice bot (2026-10-16): one of them may be a bot (BotService), on any server; never two non-players.
-- Round 2 of the match flow (2026-10-25): `holdSeconds` (QueueService: Config.Duel.Rules.FoundHoldSeconds for a duel it
-- paired or the practice bot filled) keeps the match in Preparing that long and sends each real player MatchFound, so
-- the lobby's MATCH FOUND show plays before the teleport; nil (the duel pads, Rematch, Studio) starts as before.
function DuelService.startMatch(a: any, b: any, slot: Slot?, holdSeconds: number?): (MatchView?, string?)
	if ShutdownService.isClosing() then
		return nil, "closing"
	end
	if a == nil or b == nil then
		return nil, "notAPlayer"
	end
	for _, ref in { a, b } do
		local dummy = isTestDummy(ref)
		if dummy and not dummyAllowed() then
			return nil, "dummyNotAllowed"
		end
		if not dummy and not isBot(ref) and not isRealPlayer(ref) then
			return nil, "notAPlayer"
		end
		local userId = userIdOf(ref)
		if userId == nil or matchOfUser[userId] ~= nil then
			return nil, "alreadyInMatch"
		end
	end
	if not isRealPlayer(a) and not isRealPlayer(b) then
		return nil, "noRealPlayer"
	end
	if userIdOf(a) == userIdOf(b) then
		return nil, "samePlayer"
	end

	local matchId = HttpService:GenerateGUID(false)
	local useSlot = slot or ArenaService.acquire(matchId)
	if useSlot == nil then
		return nil, "noArena"
	end
	ArenaService.setMatch(useSlot, matchId)

	local now = serverNow()
	local sideOfA: Side = if rng:NextInteger(0, 1) == 0 then "A" else "B"
	local pa = newParticipant(a, sideOfA, now)
	local pb = newParticipant(b, otherSide(sideOfA), now)
	local sides: Sides = if sideOfA == "A" then { A = pa, B = pb } else { A = pb, B = pa }
	local function entrant(p: Participant): DuelRules.Entrant
		local player = p.player
		return {
			userId = p.userId,
			isTestDummy = p.isTestDummy,
			rewardsEnabled = player ~= nil and not p.isTestDummy and hooks.profileReady(player),
		}
	end

	local hold = if holdSeconds and holdSeconds > 0 then holdSeconds else nil
	local match: Match = {
		matchId = matchId,
		state = DuelRules.new(matchId, { A = entrant(sides.A), B = entrant(sides.B) }, now, nil, hold),
		slot = useSlot,
		port = nil :: any,
		sides = sides,
		list = { sides.A, sides.B },
		arenaView = ArenaService.view(useSlot),
		cleanup = Cleanup.new() :: any,
		pending = {},
		stateDirty = false,
		returning = false,
		closed = false,
		endedFired = false,
		createdAt = now,
		holdUntil = if hold then now + hold else nil,
	}
	match.port = buildPort(match, { sides.A.fighter, sides.B.fighter }, useSlot)
	matches[matchId] = match
	for _, p in match.list do
		matchOfUser[p.userId] = match
	end
	CombatService.registerMatch(match.port)
	AbilityService.attachMatch(match.port)

	-- A respawn after a death (DuelRules waits for it in Preparing; later a death has already ended the match).
	for _, p in match.list do
		local added = p.ref.CharacterAdded
		if typeof(added) == "RBXScriptSignal" or type(added) == "table" then
			match.cleanup:add(added:Connect(function()
				if not match.closed then
					stepMatch(match, { kind = "respawned", side = p.side })
				end
			end))
		end
		setAttribute(p, ATTR_MATCH_ID, matchId)
		setAttribute(p, ATTR_PHASE, match.state.phase)
	end
	sendDuelState(match)
	if hold then
		sendFound(match)
	end
	ensureHeartbeat()
	log:info(
		string.format(
			"match %s started in slot %d (%s): A user %d (%s) vs B user %d (%s)",
			matchId,
			useSlot.index,
			useSlot.arenaId,
			sides.A.userId,
			sides.A.squishyId,
			sides.B.userId,
			sides.B.squishyId
		)
	)
	for _, p in match.list do
		task.spawn(streamParticipant, match, p)
	end
	return DuelService.getMatch(a), nil
end

-- The match of a Player (or the test dummy / a userId), or nil.
function DuelService.getMatch(who: any): MatchView?
	local match, p = participantOf(who)
	if match == nil or p == nil then
		return nil
	end
	return {
		matchId = match.matchId,
		phase = match.state.phase,
		side = publicSide(p.side),
		opponentUserId = onSide(match, otherSide(p.side)).userId,
		slot = match.slot.index,
	}
end

-- One participant's view of an ended DuelRules state: (DuelResult.outcome, DuelResult.reasonKey). A state that has
-- not ended reads as void. Pure (no match needed); unit-tested.
function DuelService.resultFor(state: MatchState, side: string): (Types.DuelOutcome, string)
	local outcome = state.outcome
	if not state.ended or outcome == nil then
		return "void", KEY_VOID
	end
	local view: Types.DuelOutcome = viewOutcome(outcome, side)
	return view, reasonKeyFor(state, outcome, side, view)
end

-- The DuelResult.coinsBlockedReason a participant is shown: the reward's own reason, except duel.noRewardsOffline
-- while no profile system exists (init wires profileReady through setHooks only when one does): no progress failed to
-- load then, so that text would be untrue (§0.3 #9) and the reward line is left out instead. Pure; unit-tested.
function DuelService.shownBlockedReason(reward: Reward?, profilesReady: boolean): string?
	local reason = if reward then reward.coinsBlockedReason else nil
	if reason == REASON_NO_REWARDS_OFFLINE and not profilesReady then
		return nil
	end
	return reason
end

-- Opponents a participant eliminated in this match, for the profile's eliminations stat (reading: the winner of an
-- elimination or a sudden-death hit, and both players of a simultaneous final hit). Pure; unit-tested.
function DuelService.eliminationsFor(outcome: Outcome, view: string): number
	local reason = outcome.reason
	if reason == "doubleKo" or (view == "win" and (reason == "eliminated" or reason == "suddenDeath")) then
		return 1
	end
	return 0
end

-- Pays one real participant's DuelRewards result (§3.11, §6.7) through EconomyService.grantDuelResult (or `payer`,
-- in tests) and returns what DuelResult shows: the Coins really added and, when that is 0, the reason (filtered by
-- shownBlockedReason). A reward without a duelLog entry (profile not ready, already in duelLog) pays nothing and asks
-- EconomyService nothing. A matchId EconomyService already recorded pays 0 again with no reason (exactly once).
-- Reading: a same-pair reduction rides in coinsBlockedReason next to its Coins (duel.rewardsReduced, §2.10, §6.7).
function DuelService.settleReward(
	player: any,
	matchId: string,
	view: string,
	reward: Reward,
	eliminations: number?,
	payer: RewardPayer?
): Settlement
	local shown = DuelService.shownBlockedReason(reward, profilesWired)
	local entry = reward.logEntry
	if entry == nil then
		return { coins = 0, coinsBlockedReason = if reward.alreadyGranted then nil else shown }
	end
	local economy: RewardPayer = payer or EconomyService
	local grant = economy.grantDuelResult(player, matchId, view, {
		coins = reward.coins,
		logEntry = entry,
		eliminations = eliminations or 0,
	})
	if grant.alreadyGranted then
		return { coins = 0, coinsBlockedReason = nil }
	end
	if grant.blockedReason ~= nil then
		-- The profile stopped being ready between Preparing and Result (e.g. its session lock was lost).
		return {
			coins = 0,
			coinsBlockedReason = DuelService.shownBlockedReason(
				{ coinsBlockedReason = grant.blockedReason } :: any,
				profilesWired
			),
		}
	end
	if grant.coins > 0 then
		return { coins = grant.coins, coinsBlockedReason = reward.reducedReason }
	end
	return { coins = 0, coinsBlockedReason = shown }
end

-- DuelResult.questProgress and DuelResult.tip for one participant (see the header). Only a real participant (a
-- Player, not the test dummy) asks the hooks, each once and inside pcall: an error is logged and leaves {} / nil, an
-- answer of the wrong type is dropped, so a hook can never break the result. onEnded calls it once per participant;
-- exposed for unit tests.
function DuelService.resultExtras(summary: ParticipantSummary, info: ResultInfo): ({ Types.QuestProgressLine }, string?)
	local player = summary.player
	if player == nil or summary.isTestDummy then
		return {}, nil
	end
	local questProgress: { Types.QuestProgressLine } = {}
	local okLines, lines = pcall(resultHooks.questProgress, player, summary, info)
	if not okLines then
		log:error(`questProgress hook failed for user {summary.userId} in match {info.matchId}:`, lines)
	elseif type(lines) == "table" then
		questProgress = lines
	end
	local tip: string? = nil
	local okTip, answer = pcall(resultHooks.tip, player, summary, info)
	if not okTip then
		log:error(`tip hook failed for user {summary.userId} in match {info.matchId}:`, answer)
	elseif type(answer) == "string" then
		tip = answer
	end
	return questProgress, tip
end

-- Registers the DuelResult hooks (questProgress, tip) of the layers above (QuestService, TipService, from their init).
-- Missing fields keep the current hook, like setHooks.
function DuelService.setResultHooks(newHooks: {
	questProgress: ((Player, ParticipantSummary, ResultInfo) -> { Types.QuestProgressLine })?,
	tip: ((Player, ParticipantSummary, ResultInfo) -> string?)?,
})
	if newHooks.questProgress then
		resultHooks.questProgress = newHooks.questProgress
	end
	if newHooks.tip then
		resultHooks.tip = newHooks.tip
	end
end

-- Matches in progress (Result and Returning included). Studio counts use it.
function DuelService.matchCount(): number
	local count = 0
	for _ in matches do
		count += 1
	end
	return count
end

-- A forfeit (DuelForfeit, the confirmed Reset, the test dummy) or, with reason "leave", a departure. DuelRules decides
-- (§5.4): Cancelled before Active or before EarlyForfeitSeconds of Active, else a loss; ignored after the end.
-- Returns true when the player was in a match.
function DuelService.forfeit(who: any, reason: string?): boolean
	local match, p = participantOf(who)
	if match == nil or p == nil then
		return false
	end
	local kind = if reason == "leave" or reason == "left" then "leave" else "forfeit"
	stepMatch(match, { kind = kind, side = p.side })
	return true
end

-- Ends every match now: "shutdown" voids them with duel.void (BindToClose); any other reason voids them as an error.
function DuelService.voidAll(reason: string?)
	local kind = if reason == "shutdown" then "shutdown" else "error"
	for _, match in matchList() do
		local ok, err = try(stepMatch, match, { kind = kind })
		if not ok then
			log:error(`voiding match {match.matchId} failed:`, err)
			safeClose(match)
		end
	end
end

-- True once the profile hooks are wired (setHooks with profileReady): rewards can then be paid.
function DuelService.rewardsWired(): boolean
	return profilesWired
end

-- Replaces the profile hooks (profileReady, duelLog, samePair); init passes EconomyService's when a profile system
-- exists. Missing fields keep the current hook.
function DuelService.setHooks(newHooks: {
	profileReady: ((Player) -> boolean)?,
	duelLog: ((Player) -> { Types.DuelLogEntry })?,
	samePair: ((Player) -> Types.SamePairRecord)?,
})
	if newHooks.profileReady then
		hooks.profileReady = newHooks.profileReady
		profilesWired = true
	end
	if newHooks.duelLog then
		hooks.duelLog = newHooks.duelLog
	end
	if newHooks.samePair then
		hooks.samePair = newHooks.samePair
	end
end

-- Studio debug view.
function DuelService.debugState(): { [string]: any }
	local list = {}
	for matchId, match in matches do
		local a, b = match.state.participants.A, match.state.participants.B
		table.insert(list, {
			matchId = matchId,
			phase = match.state.phase,
			slot = match.slot.index,
			ended = match.state.ended,
			outcome = if match.state.outcome then match.state.outcome.kind else nil,
			A = { userId = a.userId, lives = a.lives, throws = a.throws, hits = a.hits },
			B = { userId = b.userId, lives = b.lives, throws = b.throws, hits = b.hits },
		})
	end
	return { matches = list }
end

-- Lifecycle

function DuelService.init()
	-- Rewards are paid through EconomyService from here on (§6.7, see profilesWired).
	DuelService.setHooks({
		profileReady = EconomyService.canEarn,
		duelLog = EconomyService.duelLog,
		samePair = EconomyService.samePair,
	})
	NetService.on("DuelForfeit", function(player: Player)
		DuelService.forfeit(player, "forfeit")
	end)
	CharacterService.Died:connect(function(player: Player, _character: Model)
		local match, p = participantOf(player)
		if match and p then
			stepMatch(match, { kind = "died", side = p.side })
		end
	end)
	ArenaService.LeaseExpired:connect(function(slot: Slot, matchId: string?)
		local match = if matchId then matches[matchId] else nil
		if match and not match.closed then
			-- Void (or a forced return); closeMatch releases the slot once the players are back in the lobby.
			stepMatch(match, { kind = "leaseExpired" })
		else
			ArenaService.release(slot) -- no match of ours holds it: free it now
		end
	end)
	ShutdownService.Closing:connect(function()
		DuelService.voidAll("shutdown")
	end)
	ShutdownService.RestartScheduled:connect(function(restartAt: number, _reason: string)
		local deadline = restartAt - Config.Duel.RestartMarginSeconds
		for _, match in matchList() do
			local ok, err = try(stepMatch, match, { kind = "restartScheduled", deadline = deadline })
			if not ok then
				log:error(`restart handling failed for match {match.matchId}:`, err)
			end
		end
	end)
end

-- A player (or, from TestHarness.leave, the test dummy) leaves: the `leave` event (§5.4 "Leave / disconnect").
function DuelService.playerRemoving(player: any)
	local match, p = participantOf(player)
	if match and p then
		stepMatch(match, { kind = "leave", side = p.side })
	end
end

-- Not called by the bootstrap; used by leak checks.
function DuelService.destroy()
	for _, match in matchList() do
		safeClose(match)
	end
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	DuelService.MatchEnded:disconnectAll()
end

return DuelService
