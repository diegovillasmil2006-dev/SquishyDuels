--!strict
-- MatchRules: the pure state machine of a Free for All (12) or Team Deathmatch (6 vs 6) match on Diego's duel maps
-- (jayyyyy's rules 2026-10-15, Config.Match). Server only, pure: no instances, no yields, time comes in as `now`. The
-- match service owns one MatchState per match, feeds it events, stores the returned state before any yield and
-- performs the returned effects (placing and protecting players, power-up effects, HUD state, rewards). `step` never
-- modifies the state it is given, so an old state is a safe snapshot. It is the 12-player sibling of DuelRules (1v1).
--
-- Phases: Waiting (players arrive; every entrant in, but not before introMinSeconds, or waitSeconds) -> Countdown
-- (countdownSeconds) -> Active
-- (matchSeconds) (-> Overtime) -> Result (resultSeconds) -> Closed. A match with fewer than minPlayers present at the
-- countdown (or, in TDM, a team with nobody present) is cancelled. Every end goes through Result, except Void
-- (shutdown or error), which closes at once. `ended` is set exactly once, together with `outcome`.
--
-- Rules (Config.Match):
--   * One hit = knocked out (K.O.). A hit counts only while the match is live, on a present, standing victim outside
--     spawn protection, and never between teammates (TDM) or on oneself. A live shield power-up blocks the hit and is
--     used up. A K.O. clears the victim's power-ups and storm bar and gives the attacker +1 K.O.
--   * FFA: the victim respawns respawnSeconds later. The first to koTarget K.O.s wins at once.
--   * TDM (owner 2026-10-26, Diego's match page): the victim respawns respawnSeconds later and the other team scores 1
--     (any cause: a storm or out-of-bounds K.O. scores for the other team too); the first team to koTarget wins at
--     once. A team with nobody left in it (everyone left) is wiped: the other team wins (both: a draw).
--   * Respawn: standing again with spawnProtectSeconds of protection (hits ignored) and an empty storm bar.
--   * Time-up: FFA: the single leader (most K.O.s among present players) wins; TDM: the team with the higher score
--     wins. A tie goes to Overtime: in FFA the first moment one player alone leads wins; in TDM the team that scores the
--     next K.O. wins. Overtime ends after overtimeMaxSeconds as a draw.
--   * Leaving: the player is gone for the rest of the match (no respawn). FFA with one player left: that player wins;
--     with none: void. TDM: a team with nobody left in it is wiped.
--   * Out of bounds (jayyyyy 2026-10-15: falling off or leaving the map "counts as a knockout"): the service sends `oob`
--     when Config.Match.outOfBoundsIsKo is on; it is a K.O. with no attacker, like a storm K.O. (TDM: the other team
--     scores; FFA: nobody scores).
--   * Storm (TDM only, Config.Match.Storm, StormMath): the service samples who stands in the storm; each standing,
--     present player's bar moves by the time since their last sample; a full bar is a storm K.O. (no attacker).
--   * Power-ups (the pickup event; PowerUpRules picks the kind and owns the pads): timed kinds become a buff until
--     now + seconds; ultCharge is an effect for the ability service.
--   * Readings (not given by the user): power-ups end on a K.O.; spawn protection only stops hits (the storm bar still
--     fills, so the service must respawn players inside the safe circle once the storm is up); the attacker of a K.O.
--     need not be standing (a throw in flight still counts); time-up counts only present players.
--
-- Events ({ kind = ..., ... }; anything unknown or malformed is ignored):
--   tick                                timers (phase ends, respawns)
--   arrived {userId}                    Waiting: that player's character is in the map
--   hits {hits = {{victim, by, at}}}    hits of one server step (the combat service already checked range and aim);
--                                       applied in impact order, timers due before each impact first
--   storm {inStorm = {[userId] = true}} TDM: who stands in the storm right now (sampled a few times a second)
--   pickup {userId, power}              a power-up pad was taken (PowerUpRules.roll chose `power`)
--   leave {userId}                      disconnect or left the match
--   oob {userId}                        that standing player fell off / left the map (a K.O., cause "outOfBounds")
--   shutdown, error                     void the match
--   empty                               void the match: no real player is left in it, only bots (2026-10-17)
-- Effects ({ kind = ..., ... }):
--   phase {phase, startedAt, endsAt}    `endsAt = math.huge` means no timer (Closed)
--   ko {victim, by?, cause, at}         cause "hit", "storm" or "outOfBounds"
--   respawn {userId, at, protectUntil}  place the player at a spawn and protect them
--   teamScore {team, score}             TDM: that team's score after a K.O.
--   shieldBlocked {userId, by, at}
--   pickup {userId, power, at}; buff {userId, power, untilAt}; ultCharge {userId, fraction}
--   ended {outcome}; closed
--
-- API:
--   MatchRules.new(matchId, modeId, entrants, now, match?) -> MatchState in Waiting (match = Config.Match shape)
--   MatchRules.step(state, event, now)                     -> (MatchState, { Effect })
--   MatchRules.isLive(state)                               -> boolean (Active or Overtime, not ended)
--   MatchRules.canBeHit(state, victimId, at, byId?)        -> boolean
--   MatchRules.hasBuff(state, userId, power, now)          -> boolean
--   MatchRules.participant(state, userId)                  -> Participant?
--   MatchRules.standings(state)                            -> { Participant } (most K.O.s first, then fewest
--                                                             times knocked out, then entrant order)
--   MatchRules.activeSeconds(state, now)                   -> number (0 before Active; frozen at the end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local StormMath = require(Shared.StormMath)

-- Types

export type Phase = "Waiting" | "Countdown" | "Active" | "Overtime" | "Result" | "Closed"

export type Entrant = {
	userId: number,
	team: string?, -- TDM: one of Config.Match.teamNames
	isBot: boolean?, -- bots count as arrived from the start
}

export type Participant = {
	userId: number,
	index: number, -- entrant order (tie-break)
	team: string?,
	isBot: boolean,
	arrived: boolean,
	left: boolean, -- left the match (never comes back)
	present: boolean, -- arrived and not left
	alive: boolean, -- standing in the map
	respawnAt: number?, -- knocked out, coming back at this time
	out: boolean, -- never set since TDM lost its team lives (2026-10-26); kept for the views' `out`
	protectUntil: number,
	kos: number,
	knockedOut: number,
	stormBar: number,
	stormAt: number?, -- time of the last storm sample
	buffs: { [string]: number? }, -- power -> until
}

export type OutcomeKind = "win" | "draw" | "cancelled" | "void"

export type Outcome = {
	kind: OutcomeKind,
	reason: string, -- koTarget, wiped, timeUp, overtime, overtimeTimeout, lastPlayer, notEnoughPlayers, shutdown,
	-- error, empty
	winnerUserId: number?, -- FFA win
	winnerTeam: string?, -- TDM win
	winners: { number }, -- every winning userId (a draw: the tied leaders in FFA, nobody in TDM)
	activeSeconds: number,
}

export type MatchState = {
	matchId: string,
	modeId: string,
	mode: any, -- Config.Match.Modes[modeId]
	match: any, -- Config.Match shape
	phase: Phase,
	phaseStartedAt: number,
	phaseEndsAt: number,
	activeStartedAt: number?,
	order: { number },
	participants: { [number]: Participant },
	teamScore: { [string]: number }, -- TDM: each team's K.O.s scored
	ended: boolean,
	outcome: Outcome?,
	closed: boolean,
}

export type Event = { [string]: any }
export type Effect = { [string]: any }
type Effects = { Effect }

-- Constants

local LIVE: { [string]: boolean } = { Active = true, Overtime = true }
local MAX_TIMER_STEPS = 32 -- advance() loop guard (a few phase changes and up to 12 respawns per call)

-- Module table

local MatchRules = {}

-- Private: state ------------------------------------------------------------------------------------------------------

local function copyState(state: MatchState): MatchState
	local copy = table.clone(state)
	local participants: { [number]: Participant } = {}
	for userId, p in state.participants do
		local pc = table.clone(p)
		pc.buffs = table.clone(p.buffs)
		participants[userId] = pc
	end
	copy.participants = participants
	copy.teamScore = table.clone(state.teamScore)
	return copy
end

local function eachParticipant(s: MatchState): { Participant }
	local out: { Participant } = {}
	for _, userId in s.order do
		table.insert(out, s.participants[userId])
	end
	return out
end

local function setPhase(s: MatchState, phase: Phase, at: number, seconds: number, fx: Effects)
	s.phase = phase
	s.phaseStartedAt = at
	s.phaseEndsAt = at + seconds
	table.insert(fx, { kind = "phase", phase = phase, startedAt = at, endsAt = s.phaseEndsAt })
end

local function activeSecondsAt(s: MatchState, at: number): number
	if s.activeStartedAt == nil then
		return 0
	end
	return math.max(0, at - s.activeStartedAt)
end

local function endMatch(s: MatchState, at: number, fx: Effects, outcome: { [string]: any })
	if s.ended then
		return
	end
	s.ended = true
	outcome.winners = outcome.winners or {}
	outcome.activeSeconds = activeSecondsAt(s, at)
	s.outcome = outcome :: any
	table.insert(fx, { kind = "ended", outcome = outcome })
	if outcome.kind == "void" then
		s.closed = true
		setPhase(s, "Closed", at, math.huge, fx)
		table.insert(fx, { kind = "closed" })
	else
		setPhase(s, "Result", at, s.match.resultSeconds, fx)
	end
end

local function teamMembers(s: MatchState, team: string): { Participant }
	local out: { Participant } = {}
	for _, p in eachParticipant(s) do
		if p.team == team then
			table.insert(out, p)
		end
	end
	return out
end

local function teamWins(s: MatchState, team: string, reason: string, at: number, fx: Effects)
	local winners: { number } = {}
	for _, p in teamMembers(s, team) do
		table.insert(winners, p.userId)
	end
	endMatch(s, at, fx, { kind = "win", reason = reason, winnerTeam = team, winners = winners })
end

local function playerWins(s: MatchState, p: Participant, reason: string, at: number, fx: Effects)
	endMatch(s, at, fx, { kind = "win", reason = reason, winnerUserId = p.userId, winners = { p.userId } })
end

local function otherTeam(s: MatchState, team: string): string
	local names = s.match.teamNames
	return if names[1] == team then names[2] else names[1]
end

-- Present players with the most K.O.s.
local function leaders(s: MatchState): { Participant }
	local best, out = -1, {} :: { Participant }
	for _, p in eachParticipant(s) do
		if p.present then
			if p.kos > best then
				best, out = p.kos, { p }
			elseif p.kos == best then
				table.insert(out, p)
			end
		end
	end
	return out
end

-- A team is wiped when none of its members is standing or waiting to respawn (gone players count as down).
local function wiped(s: MatchState, team: string): boolean
	for _, p in teamMembers(s, team) do
		if p.present and (p.alive or p.respawnAt ~= nil) then
			return false
		end
	end
	return true
end

local function presentCount(s: MatchState): number
	local n = 0
	for _, p in eachParticipant(s) do
		if p.present then
			n += 1
		end
	end
	return n
end

-- Private: rules ------------------------------------------------------------------------------------------------------

local function respawn(s: MatchState, p: Participant, at: number, fx: Effects)
	p.alive = true
	p.respawnAt = nil
	p.out = false
	p.protectUntil = at + s.match.spawnProtectSeconds
	p.stormBar = 0
	p.stormAt = nil
	table.insert(fx, { kind = "respawn", userId = p.userId, at = at, protectUntil = p.protectUntil })
end

-- After any change that can end a live TDM match: wiped teams.
local function checkWipe(s: MatchState, at: number, fx: Effects)
	if s.ended or not s.mode.teams then
		return
	end
	local names = s.match.teamNames
	local aDown, bDown = wiped(s, names[1]), wiped(s, names[2])
	if aDown and bDown then
		endMatch(s, at, fx, { kind = "draw", reason = "wiped" })
	elseif aDown then
		teamWins(s, names[2], "wiped", at, fx)
	elseif bDown then
		teamWins(s, names[1], "wiped", at, fx)
	end
end

-- After a player leaves a live FFA match.
local function checkFfaPlayers(s: MatchState, at: number, fx: Effects)
	if s.ended or s.mode.teams then
		return
	end
	local count = presentCount(s)
	if count == 0 then
		endMatch(s, at, fx, { kind = "void", reason = "empty" })
	elseif count == 1 then
		for _, p in eachParticipant(s) do
			if p.present then
				playerWins(s, p, "lastPlayer", at, fx)
			end
		end
	end
end

local function knockOut(s: MatchState, victim: Participant, by: Participant?, cause: string, at: number, fx: Effects)
	victim.alive = false
	victim.knockedOut += 1
	victim.buffs = {}
	victim.stormBar = 0
	victim.stormAt = nil
	if by then
		by.kos += 1
	end
	table.insert(
		fx,
		{ kind = "ko", victim = victim.userId, by = if by then by.userId else nil, cause = cause, at = at }
	)
	if s.mode.teams then
		-- 2026-10-26: the other team scores (a storm or out-of-bounds K.O. too); the victim always respawns.
		local scorer = if by then by.team :: string else otherTeam(s, victim.team :: string)
		s.teamScore[scorer] += 1
		victim.respawnAt = at + s.match.respawnSeconds
		table.insert(fx, { kind = "teamScore", team = scorer, score = s.teamScore[scorer] })
		if s.phase == "Overtime" then
			teamWins(s, scorer, "overtime", at, fx) -- the next K.O. decides it
		elseif s.teamScore[scorer] >= s.mode.koTarget then
			teamWins(s, scorer, "koTarget", at, fx)
		end
	else
		victim.respawnAt = at + s.match.respawnSeconds
		if by and by.kos >= s.mode.koTarget then
			playerWins(s, by, "koTarget", at, fx)
		elseif s.phase == "Overtime" then
			local top = leaders(s)
			if #top == 1 then
				playerWins(s, top[1], "overtime", at, fx)
			end
		end
	end
end

-- At least minPlayers present and, in TDM, someone present on each team.
local function enoughPlayers(s: MatchState): boolean
	if presentCount(s) < s.match.minPlayers then
		return false
	end
	if s.mode.teams then
		for _, team in s.match.teamNames do
			local any = false
			for _, p in teamMembers(s, team) do
				any = any or p.present
			end
			if not any then
				return false
			end
		end
	end
	return true
end

local function startCountdown(s: MatchState, at: number, fx: Effects)
	for _, p in eachParticipant(s) do
		p.present = p.arrived and not p.left
		p.alive = p.present
	end
	if not enoughPlayers(s) then
		endMatch(s, at, fx, { kind = "cancelled", reason = "notEnoughPlayers" })
		return
	end
	setPhase(s, "Countdown", at, s.match.countdownSeconds, fx)
end

local function timeUp(s: MatchState, at: number, fx: Effects)
	if s.mode.teams then
		local names = s.match.teamNames
		local a, b = s.teamScore[names[1]], s.teamScore[names[2]]
		if a ~= b then
			teamWins(s, if a > b then names[1] else names[2], "timeUp", at, fx)
			return
		end
	else
		local top = leaders(s)
		if #top == 1 then
			playerWins(s, top[1], "timeUp", at, fx)
			return
		end
	end
	setPhase(s, "Overtime", at, s.match.overtimeMaxSeconds, fx)
end

local function overtimeOver(s: MatchState, at: number, fx: Effects)
	local winners: { number } = {}
	if not s.mode.teams then
		for _, p in leaders(s) do
			table.insert(winners, p.userId)
		end
	end
	endMatch(s, at, fx, { kind = "draw", reason = "overtimeTimeout", winners = winners })
end

-- The earliest respawn due at or before `limit`, if any.
local function nextRespawn(s: MatchState, limit: number): Participant?
	local best: Participant? = nil
	for _, p in eachParticipant(s) do
		local due = p.respawnAt
		if p.present and due ~= nil and due <= limit and (best == nil or due < (best.respawnAt :: number)) then
			best = p
		end
	end
	return best
end

-- Runs every timer due at or before `now`, in time order.
local function advance(s: MatchState, now: number, fx: Effects)
	for _ = 1, MAX_TIMER_STEPS do
		if s.closed then
			return
		end
		local phase = s.phase
		if phase == "Waiting" then
			local all = true
			for _, p in eachParticipant(s) do
				all = all and (p.arrived or p.left)
			end
			if all and now >= s.phaseStartedAt + s.match.introMinSeconds then -- the intro's cards play first
				startCountdown(s, math.min(now, s.phaseEndsAt), fx)
			elseif now >= s.phaseEndsAt then
				startCountdown(s, s.phaseEndsAt, fx)
			else
				return
			end
		elseif phase == "Countdown" then
			if now < s.phaseEndsAt then
				return
			end
			s.activeStartedAt = s.phaseEndsAt
			setPhase(s, "Active", s.phaseEndsAt, s.mode.matchSeconds, fx)
		elseif LIVE[phase] then
			local due = nextRespawn(s, math.min(now, s.phaseEndsAt))
			if due then
				respawn(s, due, due.respawnAt :: number, fx)
			elseif now >= s.phaseEndsAt then
				if phase == "Active" then
					timeUp(s, s.phaseEndsAt, fx)
				else
					overtimeOver(s, s.phaseEndsAt, fx)
				end
			else
				return
			end
		elseif phase == "Result" then
			if now < s.phaseEndsAt then
				return
			end
			s.closed = true
			setPhase(s, "Closed", s.phaseEndsAt, math.huge, fx)
			table.insert(fx, { kind = "closed" })
		else
			return
		end
	end
end

-- Private: events -----------------------------------------------------------------------------------------------------

local function isUserId(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function applyHit(s: MatchState, hit: any, fx: Effects)
	local at = hit.at
	local victim = s.participants[hit.victim]
	local by = s.participants[hit.by]
	if victim == nil or by == nil or victim == by or not MatchRules.canBeHit(s, victim.userId, at, by.userId) then
		return
	end
	local shieldUntil = victim.buffs.shield
	if shieldUntil ~= nil and at < shieldUntil then
		victim.buffs.shield = nil
		table.insert(fx, { kind = "shieldBlocked", userId = victim.userId, by = by.userId, at = at })
		return
	end
	knockOut(s, victim, by, "hit", at, fx)
end

local function handleHits(s: MatchState, event: Event, now: number, fx: Effects)
	if type(event.hits) ~= "table" then
		return
	end
	local hits = {}
	for _, hit in event.hits do
		if
			type(hit) == "table"
			and isUserId(hit.victim)
			and isUserId(hit.by)
			and type(hit.at) == "number"
			and hit.at == hit.at
		then
			table.insert(hits, { victim = hit.victim, by = hit.by, at = math.min(hit.at, now) })
		end
	end
	table.sort(hits, function(a, b)
		return a.at < b.at
	end)
	for _, hit in hits do
		advance(s, hit.at, fx)
		if s.ended then
			return
		end
		applyHit(s, hit, fx)
	end
end

local function handleStorm(s: MatchState, event: Event, now: number, fx: Effects)
	if not s.mode.storm or not MatchRules.isLive(s) or type(event.inStorm) ~= "table" then
		return
	end
	local storm = s.match.Storm
	if not StormMath.shown(storm, activeSecondsAt(s, now)) then
		return
	end
	for _, p in eachParticipant(s) do
		if s.ended then
			return
		end
		if p.present and p.alive then
			local dt = if p.stormAt then now - p.stormAt else 0
			p.stormAt = now
			p.stormBar = StormMath.stepBar(storm, p.stormBar, event.inStorm[p.userId] == true, dt)
			if p.stormBar >= 1 then
				knockOut(s, p, nil, "storm", now, fx)
			end
		end
	end
end

local function handlePickup(s: MatchState, event: Event, now: number, fx: Effects)
	local p = s.participants[event.userId]
	local power = event.power
	local kind = if type(power) == "string" then s.match.PowerUps.kinds[power] else nil
	if p == nil or kind == nil or not MatchRules.isLive(s) or not (p.present and p.alive) then
		return
	end
	if kind.teamsOnly and not s.mode.teams then
		return
	end
	table.insert(fx, { kind = "pickup", userId = p.userId, power = power, at = now })
	if kind.seconds then
		p.buffs[power] = now + kind.seconds
		table.insert(fx, { kind = "buff", userId = p.userId, power = power, untilAt = p.buffs[power] })
	elseif kind.ultFraction then
		table.insert(fx, { kind = "ultCharge", userId = p.userId, fraction = kind.ultFraction })
	end
end

local function handleLeave(s: MatchState, event: Event, now: number, fx: Effects)
	local p = s.participants[event.userId]
	if p == nil or p.left then
		return
	end
	p.left = true
	p.present = false
	p.alive = false
	p.respawnAt = nil
	p.out = false
	if s.phase == "Waiting" then
		return -- advance() stops waiting for them
	end
	if s.phase == "Countdown" then
		if not enoughPlayers(s) then
			endMatch(s, now, fx, { kind = "cancelled", reason = "notEnoughPlayers" })
		end
		return
	end
	if MatchRules.isLive(s) then
		checkWipe(s, now, fx)
		checkFfaPlayers(s, now, fx)
	end
end

local function handle(s: MatchState, event: Event, now: number, fx: Effects)
	local kind = event.kind
	if kind == "shutdown" or kind == "error" or kind == "empty" then
		endMatch(s, now, fx, { kind = "void", reason = kind })
		return
	end
	if s.ended then
		return
	end
	if kind == "arrived" then
		local p = s.participants[event.userId]
		if p and s.phase == "Waiting" and not p.arrived and not p.left then
			p.arrived = true
			p.present = true
		end
	elseif kind == "hits" then
		handleHits(s, event, now, fx)
	elseif kind == "storm" then
		handleStorm(s, event, now, fx)
	elseif kind == "pickup" then
		handlePickup(s, event, now, fx)
	elseif kind == "leave" then
		handleLeave(s, event, now, fx)
	elseif kind == "oob" then
		local p = s.participants[event.userId]
		if p and MatchRules.isLive(s) and p.present and p.alive then
			knockOut(s, p, nil, "outOfBounds", now, fx)
		end
	end
end

-- Public ---------------------------------------------------------------------------------------------------------------

function MatchRules.new(matchId: string, modeId: string, entrants: { Entrant }, now: number, match: any?): MatchState
	local cfg = match or Config.Match
	local mode = cfg.Modes[modeId]
	assert(mode, `MatchRules.new: unknown mode {modeId}`)
	assert(#entrants >= 1 and #entrants <= mode.maxPlayers, `MatchRules.new: {#entrants} entrants for {modeId}`)
	local participants: { [number]: Participant } = {}
	local order: { number } = {}
	for index, entrant in entrants do
		local userId = entrant.userId
		assert(participants[userId] == nil, `MatchRules.new: entrant {userId} twice`)
		if mode.teams then
			assert(
				entrant.team == cfg.teamNames[1] or entrant.team == cfg.teamNames[2],
				`MatchRules.new: entrant {userId} has no team`
			)
		end
		local isBot = entrant.isBot == true
		participants[userId] = {
			userId = userId,
			index = index,
			team = if mode.teams then entrant.team else nil,
			isBot = isBot,
			arrived = isBot,
			left = false,
			present = isBot,
			alive = false,
			respawnAt = nil,
			out = false,
			protectUntil = -math.huge,
			kos = 0,
			knockedOut = 0,
			stormBar = 0,
			stormAt = nil,
			buffs = {},
		}
		table.insert(order, userId)
	end
	local teamScore: { [string]: number } = {}
	if mode.teams then
		for _, team in cfg.teamNames do
			teamScore[team] = 0
		end
	end
	return {
		matchId = matchId,
		modeId = modeId,
		mode = mode,
		match = cfg,
		phase = "Waiting",
		phaseStartedAt = now,
		phaseEndsAt = now + cfg.waitSeconds,
		activeStartedAt = nil,
		order = order,
		participants = participants,
		teamScore = teamScore,
		ended = false,
		outcome = nil,
		closed = false,
	}
end

function MatchRules.step(state: MatchState, event: Event, now: number): (MatchState, { Effect })
	local s = copyState(state)
	local fx: Effects = {}
	if s.closed or type(event) ~= "table" or type(event.kind) ~= "string" then
		return s, fx
	end
	if event.kind ~= "hits" then
		advance(s, now, fx)
	end
	handle(s, event, now, fx)
	advance(s, now, fx)
	return s, fx
end

function MatchRules.isLive(state: MatchState): boolean
	return LIVE[state.phase] == true and not state.ended
end

function MatchRules.canBeHit(state: MatchState, victimId: number, at: number, byId: number?): boolean
	if not MatchRules.isLive(state) then
		return false
	end
	local victim = state.participants[victimId]
	if victim == nil or not (victim.present and victim.alive) or at < victim.protectUntil then
		return false
	end
	if byId ~= nil then
		local by = state.participants[byId]
		if by == nil or by == victim or (state.mode.teams and by.team == victim.team) then
			return false
		end
	end
	return true
end

function MatchRules.hasBuff(state: MatchState, userId: number, power: string, now: number): boolean
	local p = state.participants[userId]
	local untilAt = if p then p.buffs[power] else nil
	return untilAt ~= nil and now < untilAt
end

function MatchRules.participant(state: MatchState, userId: number): Participant?
	return state.participants[userId]
end

function MatchRules.standings(state: MatchState): { Participant }
	local list = eachParticipant(state)
	table.sort(list, function(a, b)
		if a.kos ~= b.kos then
			return a.kos > b.kos
		end
		if a.knockedOut ~= b.knockedOut then
			return a.knockedOut < b.knockedOut
		end
		return a.index < b.index
	end)
	return list
end

function MatchRules.activeSeconds(state: MatchState, now: number): number
	local outcome = state.outcome
	if outcome ~= nil then
		return outcome.activeSeconds
	end
	return activeSecondsAt(state, now)
end

return MatchRules
