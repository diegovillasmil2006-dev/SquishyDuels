--!strict
-- DuelRules: the pure duel state machine (DESIGN §5.2 rules and victory, §5.4 phases and edge cases). Server only,
-- pure: no instances, no yields, time comes in as `now`. DuelService owns one MatchState per match, feeds it events,
-- stores the returned state before any yield, and performs the returned effects (attributes, DuelState, teleports,
-- requeues, rewards). `step` never modifies the state it is given, so an old state is a safe snapshot.
--
-- Phases (Types.DuelPhase): Preparing -> Positioning -> Countdown -> Active (-> SuddenDeath) -> Result -> Returning,
-- with Cancelled (a bail before Active or before EarlyForfeitSeconds of Active) and Void (shutdown, error, lease) as
-- the other ends. `ended` is set exactly once, on the single transition into Result, Cancelled or Void, together with
-- `outcome`; every event that would end the match again is a no-op (double end, late spam, §12 #22). `closed` is set
-- when DuelService reports the players returned (the slot can be released).
--
-- Victory and draw (§5.2): opponent at 0 lives -> win; opponent forfeits/leaves/dies/goes missing after
-- >= EarlyForfeitSeconds of Active -> win (reason "opponentLeft"); time-up with different lives -> more lives wins;
-- equal lives -> SuddenDeath (next hit wins; SuddenDeathSeconds = 0 -> draw); SuddenDeath timeout -> draw; a bail
-- before that -> Cancelled (innocent side requeued at the front, bailer gets BailRequeueCooldownSeconds); shutdown or
-- error -> Void. Two final hits in one server step: the earlier impact time wins, an exact tie is a draw.
--
-- Events ({ kind = ..., side = "A" | "B", ... }; anything unknown, or a bad side, is ignored):
--   tick                         timers (phase ends, respawn and missing waits)
--   streamed {side}              Preparing: RequestStreamAroundAsync finished for that side (both -> Positioning; round
--                                2 of the match flow: new(..., holdSeconds) adds the MATCH FOUND show's wait to the
--                                Preparing timeout, and DuelService sends `streamed` only once that wait is over)
--   positioned {side}            Positioning: that character is on its pad (both -> Countdown)
--   hits {hits = {{victim, at}}} hits of one server step (CombatService already applied canDamage); `hit {victim, at}`
--                                is the one-hit form. Applied in impact order; a hit inside invulnerability is ignored,
--                                unless it has force = true (feature 1: a caught throw's burst, Hit).
--   throwAccepted {side}         counts an accepted throw (rewards need >= 3)
--   forfeit {side}               Forfeit button or intercepted Reset, confirmed
--   leave {side}                 disconnect
--   died {side}, respawned {side}  character died or was removed / came back
--   missing {side}, found {side} no character or HRP missing > MissingRootSeconds (DuelService measures that)
--   oob {side}                   out of bounds (Logic/MovementRules)
--   restartScheduled {deadline}  ServerRestartScheduled: the time the match must be over by (restart - margin)
--   shutdown                     ShutdownService.Closing (BindToClose)
--   error, leaseExpired          an error in the match tick / the arena lease expired
--   returned                     DuelService finished returning the players (Returning, Cancelled or Void)
-- Effects ({ kind = ..., ... }): phase {phase, startedAt, endsAt}, ended {outcome}, lifeLost {side, lives,
--   invulnUntil, at, eliminated}, repivot {side, silent, count?, invulnUntil?}, requeue {side} (front of the queue),
--   requeueCooldown {side, seconds}, notify {side, key}, forceReturn {reason}, closed.
-- `endsAt = math.huge` means the phase has no timer (Returning, Cancelled, Void).
--
-- Readings (DESIGN leaves them open):
--   * Active time = time since Active began, SuddenDeath included; it is frozen in outcome.activeSeconds.
--   * Timed transitions happen at their deadline, not at the tick that notices them; a hit at or after the Active
--     deadline is applied after the time-up (in SuddenDeath it then wins, after Result it is ignored).
--   * A death during Preparing waits RespawnWaitSeconds (Config.Duel.Positioning) for a respawn, also into
--     Positioning; a death in Positioning or Countdown cancels at once. "Missing" before Active cancels after
--     PositioningTimeoutSeconds of absence; a player still missing when Active begins has bailed at that moment.
--     At the Positioning timeout an unpositioned side is the bailer; when both are unpositioned nobody is blamed or
--     requeued.
--   * Dying, going missing and repeated out-of-bounds count as a bail (like a forfeit). A forfeit after
--     EarlyForfeitSeconds is a loss, not a bail: both players get the normal requeue cooldown.
--   * The requeued innocent player gets no cooldown (the server requeues them). `notify duel.opponentLeftEarly` is
--     sent only for bails before Active.
--   * restartScheduled voids a running match whose worst-case end (Active + SuddenDeath + Result, or what is left
--     of them) is after the deadline; Result and Returning always continue.
--   * Out-of-bounds before Active is a silent re-pivot and never counts (ignored in Preparing and for a side not yet
--     positioned: that character is not on its pad yet); in Active it pivots to the own pad, gives
--     OutOfBoundsInvulnSeconds, costs LifePenalty lives and counts; the (MaxPerMatch + 1)th is a bail.
--
-- API:
--   DuelRules.new(matchId, entrants, now, duel?)  -> MatchState in Preparing; duel = Config.Duel shape (nil = live)
--   DuelRules.step(state, event, now)             -> (MatchState, { Effect })
--   DuelRules.participant(state, side)            -> Participant
--   DuelRules.isLive(state)                       -> boolean (Active or SuddenDeath, not ended)
--   DuelRules.canBeHit(state, side, at)           -> boolean (live and outside invulnerability)
--   DuelRules.cooldownMultiplier(state)           -> number (SuddenDeathCooldownMultiplier in SuddenDeath, else 1)
--   DuelRules.activeSeconds(state, now)           -> number
--   DuelRules.sideOf(state, userId)               -> Side?
--   DuelRules.other(side)                         -> Side

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

-- Types

export type Phase = Types.DuelPhase
-- Sides DuelRules hands out (Participant, Outcome, Effect) are Types.Side, "A" or "B".
export type Side = Types.Side
-- Sides DuelRules accepts (events, hits, function arguments) are plain strings, because the type checker widens an
-- "A" | "B" value to string as soon as it sits in a local or a loop variable. Every one is checked with isSide (or
-- turned into "A"/"B" by asSide) at run time.
export type SideName = string

-- A Config.Duel-shaped table: `Rules` and `Positioning` are read.
export type DuelConfig = { Rules: any, Positioning: any }

export type Entrant = {
	userId: number,
	isTestDummy: boolean?, -- the Studio test dummy (§13.4 T2): never rewarded
	rewardsEnabled: boolean?, -- profile status `ready` at Preparing (§5.4); nil = false
}

export type Participant = {
	userId: number,
	side: Side,
	isTestDummy: boolean,
	rewardsEnabled: boolean,
	lives: number,
	invulnUntil: number,
	streamed: boolean,
	positioned: boolean,
	present: boolean, -- false after leave
	deadSince: number?, -- died during Preparing, waiting for a respawn
	missingSince: number?, -- missing before Active
	outOfBounds: number,
	throws: number, -- accepted throws
	hits: number, -- hits landed on the opponent
}

export type OutcomeKind = "win" | "draw" | "cancelled" | "void"

export type Outcome = {
	kind: OutcomeKind,
	reason: string, -- eliminated, opponentLeft, timeUp, suddenDeath, suddenDeathTimeout, doubleKo, outOfBounds,
	-- forfeit, left, died, missing, restart, shutdown, error, lease
	winner: Side?,
	loser: Side?,
	bailer: Side?, -- Cancelled: the side that bailed (15 s requeue cooldown)
	requeue: Side?, -- Cancelled: the innocent side, requeued at the front
	endedFrom: Phase, -- the phase the match was in when it ended
	at: number,
	activeSeconds: number,
}

export type MatchState = {
	matchId: string,
	duel: DuelConfig,
	phase: Phase,
	phaseStartedAt: number,
	phaseEndsAt: number, -- math.huge = no timer
	activeStartedAt: number?,
	participants: { A: Participant, B: Participant },
	outcome: Outcome?,
	ended: boolean,
	closed: boolean,
}

-- force (feature 1, 2026-10-11): the life is lost even inside the victim's invulnerability (a caught throw bursting in
-- the catcher's hands, Config.Combat.Catch.burstIgnoresInvuln); the invulnerability then runs to the later end.
export type Hit = { victim: SideName, at: number, force: boolean? }

export type Event = {
	kind: string,
	side: SideName?,
	victim: SideName?,
	at: number?,
	hits: { Hit }?,
	deadline: number?,
}

export type Effect = {
	kind: string,
	side: Side?,
	phase: Phase?,
	startedAt: number?,
	endsAt: number?,
	outcome: Outcome?,
	lives: number?,
	invulnUntil: number?,
	at: number?,
	eliminated: boolean?,
	silent: boolean?,
	count: number?,
	seconds: number?,
	key: string?,
	reason: string?,
}

type Effects = { Effect }

-- Constants

local SIDES: { SideName } = { "A", "B" }
local PRE_ACTIVE: { [string]: boolean } = { Preparing = true, Positioning = true, Countdown = true }
local LIVE: { [string]: boolean } = { Active = true, SuddenDeath = true }
local AFTER_END: { [string]: boolean } = { Returning = true, Cancelled = true, Void = true }
local MAX_TRANSITIONS = 16 -- timer transitions handled in one step (a long hitch); far more than the phase count
local NOTIFY_OPPONENT_LEFT = "duel.opponentLeftEarly"

-- Module table

local DuelRules = {}

-- Private: helpers

local function config(duel: DuelConfig?): DuelConfig
	return if duel ~= nil then duel else Config.Duel
end

local function isSide(value: unknown): boolean
	return value == "A" or value == "B"
end

-- The typed side of a side name already known to be "A" or "B" (anything else counts as "B").
local function asSide(side: SideName): Side
	if side == "A" then
		return "A"
	end
	return "B"
end

local function otherSide(side: SideName): Side
	if side == "A" then
		return "B"
	end
	return "A"
end

local function participant(s: MatchState, side: SideName): Participant
	if side == "A" then
		return s.participants.A
	end
	return s.participants.B
end

local function emit(fx: Effects, effect: Effect)
	table.insert(fx, effect)
end

local function copyState(state: MatchState): MatchState
	local copy = table.clone(state)
	copy.participants = {
		A = table.clone(state.participants.A),
		B = table.clone(state.participants.B),
	}
	return copy
end

local function phaseSeconds(s: MatchState, phase: Phase): number
	local rules = s.duel.Rules
	if phase == "Preparing" then
		return rules.PreparingTimeoutSeconds
	elseif phase == "Positioning" then
		return rules.PositioningTimeoutSeconds
	elseif phase == "Countdown" then
		return rules.CountdownSeconds
	elseif phase == "Active" then
		return rules.MatchSeconds
	elseif phase == "SuddenDeath" then
		return rules.SuddenDeathSeconds
	elseif phase == "Result" then
		return rules.ResultSeconds
	end
	return math.huge
end

local function activeSecondsAt(s: MatchState, at: number): number
	local started = s.activeStartedAt
	if started == nil then
		return 0
	end
	return math.max(0, at - started)
end

local function enterPhase(s: MatchState, phase: Phase, at: number, fx: Effects)
	s.phase = phase
	s.phaseStartedAt = at
	s.phaseEndsAt = at + phaseSeconds(s, phase)
	if phase == "Active" then
		s.activeStartedAt = at
	end
	emit(fx, { kind = "phase", phase = phase, startedAt = at, endsAt = s.phaseEndsAt })
end

-- The single end of a match: sets `ended` and `outcome`, enters Result/Cancelled/Void and emits the requeue effects.
local function finish(s: MatchState, outcome: Outcome, fx: Effects)
	s.ended = true
	s.outcome = outcome
	if outcome.kind == "cancelled" then
		enterPhase(s, "Cancelled", outcome.at, fx)
	elseif outcome.kind == "void" then
		enterPhase(s, "Void", outcome.at, fx)
	else
		enterPhase(s, "Result", outcome.at, fx)
	end
	emit(fx, { kind = "ended", outcome = outcome })

	local rules = s.duel.Rules
	local requeue: Side? = outcome.requeue
	if requeue ~= nil then
		emit(fx, { kind = "requeue", side = requeue })
		if PRE_ACTIVE[outcome.endedFrom] then
			emit(fx, { kind = "notify", side = requeue, key = NOTIFY_OPPONENT_LEFT })
		end
	end
	for _, side in SIDES do
		if side == outcome.bailer then
			emit(fx, { kind = "requeueCooldown", side = asSide(side), seconds = rules.BailRequeueCooldownSeconds })
		elseif side ~= requeue then
			emit(fx, { kind = "requeueCooldown", side = asSide(side), seconds = rules.RequeueCooldownSeconds })
		end
	end
end

local function makeOutcome(s: MatchState, kind: OutcomeKind, reason: string, at: number): Outcome
	return {
		kind = kind,
		reason = reason,
		endedFrom = s.phase,
		at = at,
		activeSeconds = activeSecondsAt(s, at),
	}
end

local function win(s: MatchState, winner: SideName, reason: string, at: number, fx: Effects)
	local outcome = makeOutcome(s, "win", reason, at)
	outcome.winner = asSide(winner)
	outcome.loser = otherSide(winner)
	finish(s, outcome, fx)
end

local function draw(s: MatchState, reason: string, at: number, fx: Effects)
	finish(s, makeOutcome(s, "draw", reason, at), fx)
end

local function void(s: MatchState, reason: string, at: number, fx: Effects)
	finish(s, makeOutcome(s, "void", reason, at), fx)
end

-- Cancelled. With a bailer, the other side is requeued at the front if it is still in the game.
local function cancel(s: MatchState, reason: string, bailer: SideName?, at: number, fx: Effects)
	local outcome = makeOutcome(s, "cancelled", reason, at)
	if bailer ~= nil then
		outcome.bailer = asSide(bailer)
		local innocent: Side = otherSide(bailer)
		if participant(s, innocent).present then
			outcome.requeue = innocent
		end
	end
	finish(s, outcome, fx)
end

-- A bail by `side` (forfeit, leave, death, missing, repeated out-of-bounds), by phase (§5.4 edge cases).
local function bail(s: MatchState, side: SideName, reason: string, at: number, fx: Effects)
	if s.ended then
		return
	end
	if PRE_ACTIVE[s.phase] then
		cancel(s, reason, side, at, fx)
	elseif LIVE[s.phase] then
		if activeSecondsAt(s, at) >= s.duel.Rules.EarlyForfeitSeconds then
			win(s, otherSide(side), "opponentLeft", at, fx)
		else
			cancel(s, reason, side, at, fx)
		end
	end
end

-- Private: timers

-- Time-up of the Active phase at `at` (§5.2 rules 3 and 4).
local function timeUp(s: MatchState, at: number, fx: Effects)
	local a, b = s.participants.A.lives, s.participants.B.lives
	if a > b then
		win(s, "A", "timeUp", at, fx)
	elseif b > a then
		win(s, "B", "timeUp", at, fx)
	elseif s.duel.Rules.SuddenDeathSeconds > 0 then
		enterPhase(s, "SuddenDeath", at, fx)
	else
		draw(s, "timeUp", at, fx)
	end
end

-- The earliest pending deadline: (time, what, side).
local function nextDeadline(s: MatchState): (number, string, SideName?)
	local due: number = s.phaseEndsAt
	local what: string = "phase"
	local who: SideName? = nil
	if PRE_ACTIVE[s.phase] then
		local respawnWait = s.duel.Positioning.RespawnWaitSeconds
		local missingWait = s.duel.Rules.PositioningTimeoutSeconds
		for _, side in SIDES do
			local p = participant(s, side)
			local deadSince, missingSince = p.deadSince, p.missingSince
			if deadSince ~= nil and deadSince + respawnWait < due then
				due, what, who = deadSince + respawnWait, "died", side
			end
			if missingSince ~= nil and missingSince + missingWait < due then
				due, what, who = missingSince + missingWait, "missing", side
			end
		end
	end
	return due, what, who
end

local function fireDeadline(s: MatchState, what: string, side: SideName?, at: number, fx: Effects)
	if side ~= nil then
		bail(s, side, what, at, fx)
		return
	end
	local phase = s.phase
	if phase == "Preparing" then
		enterPhase(s, "Positioning", at, fx) -- stream timeout: continue
	elseif phase == "Positioning" then
		local a, b = s.participants.A.positioned, s.participants.B.positioned
		if a and not b then
			cancel(s, "missing", "B", at, fx)
		elseif b and not a then
			cancel(s, "missing", "A", at, fx)
		else
			cancel(s, "missing", nil, at, fx)
		end
	elseif phase == "Countdown" then
		enterPhase(s, "Active", at, fx)
		-- Still missing when Active begins: from now on that is a forfeit by the missing player (§5.4).
		for _, candidate in SIDES do
			if participant(s, candidate).missingSince ~= nil then
				bail(s, candidate, "missing", at, fx)
				return
			end
		end
	elseif phase == "Active" then
		timeUp(s, at, fx)
	elseif phase == "SuddenDeath" then
		draw(s, "suddenDeathTimeout", at, fx)
	elseif phase == "Result" then
		enterPhase(s, "Returning", at, fx)
	end
end

-- Runs every timed transition that is due at or before `t`, each at its own deadline.
local function advance(s: MatchState, t: number, fx: Effects)
	for _ = 1, MAX_TRANSITIONS do
		local due, what, side = nextDeadline(s)
		if due > t then
			return
		end
		fireDeadline(s, what, side, due, fx)
	end
end

-- Private: events

local function applyHitGroup(s: MatchState, group: { Hit }, at: number, fx: Effects)
	local rules = s.duel.Rules
	local suddenDeath = s.phase == "SuddenDeath"
	local struckA, struckB = false, false
	for _, hit in group do
		local victim = participant(s, hit.victim)
		if hit.force == true or at >= victim.invulnUntil then
			victim.lives = math.max(0, victim.lives - 1)
			victim.invulnUntil = math.max(victim.invulnUntil, at + rules.HitInvulnSeconds)
			participant(s, otherSide(hit.victim)).hits += 1
			if hit.victim == "A" then
				struckA = true
			else
				struckB = true
			end
			emit(fx, {
				kind = "lifeLost",
				side = asSide(hit.victim),
				lives = victim.lives,
				invulnUntil = victim.invulnUntil,
				at = at,
				eliminated = suddenDeath or victim.lives <= 0,
			})
		end
	end
	local aOut = struckA and (suddenDeath or s.participants.A.lives <= 0)
	local bOut = struckB and (suddenDeath or s.participants.B.lives <= 0)
	local reason = if suddenDeath then "suddenDeath" else "eliminated"
	if aOut and bOut then
		draw(s, "doubleKo", at, fx)
	elseif aOut then
		win(s, "B", reason, at, fx)
	elseif bOut then
		win(s, "A", reason, at, fx)
	end
end

local function onHits(s: MatchState, hits: { Hit }, now: number, fx: Effects)
	local valid: { Hit } = {}
	for _, hit in hits do
		if type(hit) == "table" and isSide(hit.victim) and type(hit.at) == "number" and hit.at == hit.at then
			local entry: Hit = { victim = hit.victim, at = math.min(hit.at, now), force = hit.force == true }
			table.insert(valid, entry)
		end
	end
	table.sort(valid, function(x: Hit, y: Hit): boolean
		return x.at < y.at
	end)
	local index = 1
	while index <= #valid do
		local at = valid[index].at
		local group: { Hit } = {}
		while index <= #valid and valid[index].at == at do
			table.insert(group, valid[index])
			index += 1
		end
		advance(s, at, fx)
		if s.ended or not LIVE[s.phase] then
			return
		end
		applyHitGroup(s, group, at, fx)
		if s.ended then
			return
		end
	end
end

local function onOutOfBounds(s: MatchState, side: SideName, now: number, fx: Effects)
	if PRE_ACTIVE[s.phase] then
		-- Only a character already on its pad is put back; before that it is still on its way (or in the lobby).
		if not s.ended and (s.phase == "Countdown" or participant(s, side).positioned) then
			emit(fx, { kind = "repivot", side = asSide(side), silent = true })
		end
		return
	end
	if not LIVE[s.phase] or s.ended then
		return
	end
	local rules = s.duel.Rules
	local oob = rules.OutOfBounds
	local p = participant(s, side)
	p.outOfBounds += 1
	p.invulnUntil = math.max(p.invulnUntil, now + rules.OutOfBoundsInvulnSeconds)
	emit(fx, {
		kind = "repivot",
		side = asSide(side),
		silent = false,
		count = p.outOfBounds,
		invulnUntil = p.invulnUntil,
	})
	if oob.LifePenalty > 0 then
		p.lives = math.max(0, p.lives - oob.LifePenalty)
		local eliminated = s.phase == "SuddenDeath" or p.lives <= 0
		emit(fx, {
			kind = "lifeLost",
			side = asSide(side),
			lives = p.lives,
			invulnUntil = p.invulnUntil,
			at = now,
			eliminated = eliminated,
		})
		if eliminated then
			win(s, otherSide(side), "outOfBounds", now, fx)
			return
		end
	end
	if p.outOfBounds > oob.MaxPerMatch then
		bail(s, side, "outOfBounds", now, fx)
	end
end

-- Worst-case time the running match is over (Result included), for restartScheduled.
local function worstCaseEnd(s: MatchState): number
	local rules = s.duel.Rules
	if s.phase == "Active" then
		return s.phaseEndsAt + rules.SuddenDeathSeconds + rules.ResultSeconds
	end
	return s.phaseEndsAt + rules.ResultSeconds
end

local function forceReturn(s: MatchState, reason: string, now: number, fx: Effects)
	if not s.ended then
		void(s, reason, now, fx)
		return
	end
	if s.closed then
		return
	end
	if s.phase == "Result" then
		enterPhase(s, "Returning", now, fx)
	end
	emit(fx, { kind = "forceReturn", reason = reason })
end

local function handle(s: MatchState, event: Event, now: number, fx: Effects)
	local kind = event.kind

	if kind == "tick" then
		return -- timers already ran
	elseif kind == "hits" or kind == "hit" then
		if s.ended then
			return
		end
		local hits: { Hit } = {}
		local list = event.hits
		local victim, at = event.victim, event.at
		if kind == "hits" and type(list) == "table" then
			hits = list
		elseif kind == "hit" and victim ~= nil and isSide(victim) and type(at) == "number" then
			local single: Hit = { victim = victim, at = at }
			hits = { single }
		end
		onHits(s, hits, now, fx)
		return
	elseif kind == "restartScheduled" then
		local deadline = event.deadline
		if s.ended or type(deadline) ~= "number" then
			return
		end
		if PRE_ACTIVE[s.phase] then
			cancel(s, "restart", nil, now, fx)
		elseif LIVE[s.phase] and worstCaseEnd(s) > deadline then
			void(s, "restart", now, fx)
		end
		return
	elseif kind == "shutdown" then
		if not s.ended then
			void(s, "shutdown", now, fx)
		end
		return
	elseif kind == "error" then
		forceReturn(s, "error", now, fx)
		return
	elseif kind == "leaseExpired" then
		forceReturn(s, "lease", now, fx)
		return
	elseif kind == "returned" then
		if AFTER_END[s.phase] and s.ended and not s.closed then
			s.closed = true
			emit(fx, { kind = "closed" })
		end
		return
	end

	-- Every remaining event is about one side.
	local side = event.side
	if side == nil or not isSide(side) then
		return
	end
	local p = participant(s, side)

	if kind == "streamed" then
		if s.phase == "Preparing" and not s.ended then
			p.streamed = true
			if s.participants.A.streamed and s.participants.B.streamed then
				enterPhase(s, "Positioning", now, fx)
			end
		end
	elseif kind == "positioned" then
		if s.phase == "Positioning" and not s.ended then
			p.positioned = true
			p.missingSince = nil
			if s.participants.A.positioned and s.participants.B.positioned then
				enterPhase(s, "Countdown", now, fx)
			end
		end
	elseif kind == "throwAccepted" then
		if LIVE[s.phase] and not s.ended then
			p.throws += 1
		end
	elseif kind == "forfeit" then
		bail(s, side, "forfeit", now, fx)
	elseif kind == "leave" then
		if not s.ended then
			p.present = false
		end
		bail(s, side, "left", now, fx)
	elseif kind == "died" then
		if s.phase == "Preparing" and not s.ended then
			if p.deadSince == nil then
				p.deadSince = now
			end
		else
			bail(s, side, "died", now, fx)
		end
	elseif kind == "respawned" then
		p.deadSince = nil
	elseif kind == "missing" then
		if PRE_ACTIVE[s.phase] and not s.ended then
			if p.missingSince == nil then
				p.missingSince = now
			end
		else
			bail(s, side, "missing", now, fx)
		end
	elseif kind == "found" then
		p.missingSince = nil
	elseif kind == "oob" then
		onOutOfBounds(s, side, now, fx)
	end
end

local function newParticipant(side: Side, entrant: Entrant?, lives: number): Participant
	assert(
		entrant ~= nil and type(entrant.userId) == "number",
		"[SD][DuelRules] new: entrant " .. side .. " needs a userId"
	)
	return {
		userId = entrant.userId,
		side = side,
		isTestDummy = entrant.isTestDummy == true,
		rewardsEnabled = entrant.rewardsEnabled == true,
		lives = lives,
		invulnUntil = -math.huge,
		streamed = false,
		positioned = false,
		present = true,
		deadSince = nil,
		missingSince = nil,
		outOfBounds = 0,
		throws = 0,
		hits = 0,
	}
end

-- Public

function DuelRules.other(side: SideName): Side
	return otherSide(side)
end

function DuelRules.participant(state: MatchState, side: SideName): Participant
	return participant(state, side)
end

-- A new match in Preparing. entrants = { A = Entrant, B = Entrant } (DuelService picks the sides at random).
-- holdSeconds: the MATCH FOUND show's wait (round 2 of the match flow), on top of the Preparing timeout.
function DuelRules.new(
	matchId: string,
	entrants: { A: Entrant?, B: Entrant? },
	now: number,
	duel: DuelConfig?,
	holdSeconds: number?
): MatchState
	local c = config(duel)
	local lives = c.Rules.Lives
	return {
		matchId = matchId,
		duel = c,
		phase = "Preparing",
		phaseStartedAt = now,
		phaseEndsAt = now + c.Rules.PreparingTimeoutSeconds + math.max(0, holdSeconds or 0),
		activeStartedAt = nil,
		participants = {
			A = newParticipant("A", entrants.A, lives),
			B = newParticipant("B", entrants.B, lives),
		},
		outcome = nil,
		ended = false,
		closed = false,
	}
end

-- One event at server time `now`. Due timers run first, then the event (hits run the timers up to each impact time,
-- then the rest up to `now`). Returns a new state and the effects to perform, in order; the given state is not
-- modified.
function DuelRules.step(state: MatchState, event: Event, now: number): (MatchState, { Effect })
	local s = copyState(state)
	local fx: Effects = {}
	if s.closed or type(event) ~= "table" or type(event.kind) ~= "string" then
		return s, fx
	end
	if event.kind == "hits" or event.kind == "hit" then
		-- Hits run the timers up to each impact time themselves; the timers due after the last impact follow.
		handle(s, event, now, fx)
		advance(s, now, fx)
	else
		advance(s, now, fx)
		handle(s, event, now, fx)
	end
	return s, fx
end

function DuelRules.isLive(state: MatchState): boolean
	return LIVE[state.phase] == true and not state.ended
end

-- CombatService's canDamage uses this for the victim's side (plus same match, opposite sides, inside Bounds).
function DuelRules.canBeHit(state: MatchState, side: SideName, at: number): boolean
	if not DuelRules.isLive(state) or not isSide(side) then
		return false
	end
	local p = participant(state, side)
	return p.present and at >= p.invulnUntil
end

function DuelRules.cooldownMultiplier(state: MatchState): number
	if state.phase == "SuddenDeath" and not state.ended then
		return state.duel.Rules.SuddenDeathCooldownMultiplier
	end
	return 1
end

function DuelRules.activeSeconds(state: MatchState, now: number): number
	local outcome = state.outcome
	if outcome ~= nil then
		return outcome.activeSeconds
	end
	return activeSecondsAt(state, now)
end

function DuelRules.sideOf(state: MatchState, userId: number): Side?
	for _, side in SIDES do
		if participant(state, side).userId == userId then
			return asSide(side)
		end
	end
	return nil
end

return table.freeze(DuelRules)
