--!strict
-- MatchService (server only). SPEC (FFA/TDM v1, 2026-10-15): playable Free for All (12) and Team Deathmatch (6 vs 6)
-- inside this lobby server, on Diego's maps (MatchMapService). Logic/MatchRules is the state machine (pure); this
-- module owns one MatchRules state per match, feeds it events, stores the new state BEFORE doing anything else (and
-- before any yield), then performs the returned effects. It is the N-player sibling of DuelService (1v1), which it
-- never changes: it calls the same public CombatService / AbilityService / CharacterService functions and copies
-- DuelService's private patterns (stand height, freeze / match / restored movement, the teleport retry, the return).
-- * Queues (SPEC D6): the client's chat commands /ffa and /tdm fire MatchJoin(mode), /leave fires MatchLeave. One
--   in-server queue per mode. A join is refused with a match.refused.* toast while the server is closing or a restart
--   is pending, when already queued, in a duel or a match (SD_MatchId / SD_DuelPhase set), in the duel queue
--   (QueueService.state ~= "Idle"), practicing, or when this server has no map of the mode. Joining the duel queue
--   afterwards drops the ticket (QueueService.Joined). Once minPlayers are queued the gather timer
--   (Config.Match.gatherSeconds) runs; at 0, or at once at maxPlayers or when everyone in the server is queued, the
--   match starts with the queued players (first come, up to maxPlayers) on a random free map of the mode; with no free
--   map the queue keeps waiting (one match.waitingMap toast). TDM: the players are shuffled (server Random), then
--   dealt Red, Blue, Red, ... Toasts: joined (n/max), left, startingIn, waitingPlayers, the end (below).
--   Round 1 of the match flow (2026-10-25): each ticket's waiting bar (MatchQueue). Round 2: a match from the queue
--   sends its players MatchFound (Logic/MatchFoundRoster), the lobby's MATCH FOUND show.
--   Round 3 (2026-10-25, owner: Diego's map vote for Team and Free for All, LOBBY HUD L:1024-1147; on while
--   Config.Match.Vote.enabled): the queue's match is first a Pending: its players (SD_MatchId = its id: every lobby
--   lock holds, no queue takes them; SD_DuelPhase stays "": no duel controls) and bots (held out of sight) are dealt
--   their teams now, and it holds up to Vote.maxChoices free maps of the mode (acquired, so no other match takes them).
--   MatchVoteState (Types.MatchVoteView) goes to its players at the start, on every vote and with the result. The vote
--   opens introSeconds after MATCH FOUND and closes `seconds` later; MatchVote(card) is taken from a player of an open
--   vote, a whole card number, at most once per minIntervalSeconds (MatchService.vote); bots vote at Logic/MatchVote's
--   times; endDelaySeconds after the close the result (Logic/MatchVote: the most voted, else a roulette over the tied)
--   is sent with its times, and at its startsAt the match starts on the winner (the other maps go back). A player who
--   leaves (/leave, the game) takes their vote with them ({} to them); nobody real left, the server closing or a
--   restart ahead cancels it (maps and bots back). A single free map is chosen at once.
-- * A match: matchId "match:<GUID>"; each player's squishy is the equipped one (validated, else the starter); the
--   fighter is CombatService's with isAlive = the character is alive AND MatchRules says the player is standing, side
--   "A" in FFA, Red "A" / Blue "B" in TDM. The MatchPort (buildPort: ffa = true, teams in TDM, the map's Bounds only,
--   phase() = the D1 DuelPhase name, cooldownMultiplier 1, canBeHit = MatchRules.canBeHit with the attacker) is
--   registered with CombatService and AbilityService. The attributes SD_MatchId, SD_DuelPhase (D1 name), SD_MatchPhase
--   (the MatchRules phase), SD_MatchMode ("ffa" / "tdm") and SD_Team (TDM) hold from the start to the return, so every
--   lobby lock that reads SD_MatchId / SD_DuelPhase holds (equip, boxes, shop, capsules, squeeze, practice, duel queue,
--   friend pads); the return sets SD_MatchId / SD_DuelPhase to "" and removes the other three.
-- * Phases (D1): Waiting -> "Positioning" (each character is teleported to its first MatchSpawns spot, retried until it
--   works, and frozen; each teleport is MatchRules `arrived`), Countdown -> "Countdown" (still frozen: the movement
--   guard holds them on the spot; players who never arrived go back to the lobby), Active and Overtime -> "Active"
--   (never "SuddenDeath": that would change the client's throw cooldown; Active gives Config.Duel.Rules.Movement and
--   nextThrowAt = the Active start), Result -> "Result", Closed -> "Returning".
-- * Hits (one batch per server step, CombatService) go through MatchRules: one hit = K.O., spawn protection, no team
--   hits; each K.O. is an applied hit {lives = TDM team lives / FFA 0, eliminated = true}. A K.O.'d character stays
--   where it fell, frozen (WalkSpeed / JumpHeight 0, AutoRotate off) and unhittable (D3); at `respawn` it is pivoted
--   to a MatchSpawns respawn spot (TDM: a free spot on its team's pads; FFA: the pad farthest from enemies; inside the
--   storm's safe circle once the storm is up) and gets the match movement back. No LoadCharacter. A TDM player "out"
--   of team lives stays frozen (match.outNoLives) until the return.
-- * Out of bounds (D4, the movement guard): a re-pivot to the player's spot (silent before Active), else to a respawn
--   spot; with Config.Match.outOfBoundsIsKo (jayyyyy 2026-10-15: falling off "counts as a knockout") it is then a
--   MatchRules `oob` K.O. with the match.outOfBoundsKo toast (TDM: costs a team life); off, just the
--   match.outOfBounds toast.
-- * Death anyway (D5; the client turns Reset off): a character of a match player found alive outside the map (a new
--   character in the lobby after a death, or any stray) is re-placed at a respawn spot (its first spot before Active)
--   with the movement of its state; no K.O. and no life.
-- * Storm (TDM, D11): Config.Match.Storm.sampleHz times a second every standing player's root is tested with
--   StormMath.inStorm around (centre, floorY) at the radius of the Active time (MatchRules `storm`; a full bar is a
--   storm K.O.).
-- * The client (C4): the MatchState remote, one Types.MatchStateView per player, on the first view, every phase change,
--   K.O., respawn, out, team-lives change and outcome, plus the player's own view when its storm bar moved (at most
--   sampleHz). Then a final view with phase "Returning", then the attributes clear.
-- * The end (MatchRules `ended`, once): the outcome in the view, a toast to every participant (match.youWin /
--   match.winner {name} / match.teamWins {team} / match.draw / match.cancelled / match.void) and MatchEnded. The pay
--   is Match HUD M2's (below; off while Config.Match.Rewards.enabled is false): no DuelResult, no quests, weekly wins
--   or badges. `closed` (after
--   Result, or at once for a void): everyone still in the map goes to the least-recently-used lobby return point
--   (WorldLayout.ReturnPoints, spread by Config.Match.returnSpreadStuds), movement is restored, the attributes clear,
--   the port is unregistered and detached, the map is released and the match is forgotten.
-- * /leave in a match (or leaving the game): MatchRules `leave` (the others get a view without the leaver); the player
--   goes back to the lobby at once (the others play on). A teleport still streaming when they leave (the first one or a
--   D5 re-placement) brings them back to the lobby once it lands, never frozen in the map. A leaver, or a player who
--   never arrived, is detached from AbilityService (detachFighter) and released by CombatService (releaseFighter): no
--   longer a target, recipient or caster of the match, so lobby practice works again. ShutdownService.Closing voids
--   every match and clears the queues; RestartScheduled (onRestartScheduled) clears the queues and voids a match that
--   can't end before the restart (its longest remaining time, overtime and Result included).
-- * Review fixes (2026-10-15): the guard's out-of-bounds for a character outside the map (a new one in the lobby) is the
--   streamed D5 re-placement (no toast); the storm samples only live characters standing in the map; no re-placement
--   during Result; the Heartbeat tick steps MatchRules only when a timer is due; a match that fails to register is
--   cleaned up at once; a later joiner of a mode waiting for a free map gets match.waitingMap; a void after an error
--   says match.voidError.
-- * Power-ups v1.1 (2026-10-16, jayyyyy's pads; SPEC powerups P1-P3, P6): each match has its own pads (the map's
--   powerUps, all ready at the start, Logic/PowerUpRules). While the match is live (Active / Overtime), at
--   Config.Match.Storm.sampleHz in both modes, a standing, present player whose root is within
--   PowerUps.pickupRadiusStuds of a ready pad's centre (horizontally) and pickupHeightStuds of standing height on its
--   top takes it (the nearest one when several stand there; one pickup per player per sample): the pad refills
--   padRefillSeconds later, PowerUpRules.roll picks the kind with the server's Random, MatchRules `pickup` does the
--   rest, and the player gets the match.powerUp.<kind> toast. Effects: speed and super jump change the standing
--   movement (Config.Duel.Rules.Movement × kinds.speed.walkMultiplier / kinds.superJump.jumpMultiplier) at once and
--   again when they end, never while an ultimate roots the player (AbilityService gives port.movement back at the
--   root's end) and never on a frozen body; the port answers CombatService and DashService for the buffed fighter
--   (cooldownMultiplier(fighter) = the rapid throw's, throwSpeedMultiplier = the throw boost's, dashCooldownFree = the
--   dash boost, movement = the buffed walk speed and jump height); ultCharge goes to AbilityService.addChargeFraction;
--   a shield-blocked hit is an applied outcome with `blocked` (CombatService ends the throw at the shield, no K.O.);
--   teamLife (TDM) and its revive are MatchRules' (the revived player respawns like any respawn). The views carry
--   you.buffs (the live timed power-ups) and pads ({name, readyAt}), re-sent on every pickup, used-up shield and, to
--   that player, when a timed power-up ends. The pads are idle before Active and after the end.
--   Review fixes (2026-10-16): the rapid throw's "no wait" is the shortest cooldown
--   (Config.Duel.Rules.CooldownClamp.Min), not none; a pad is taken only once the match is up to the sample's time (a
--   hit that K.O.s the taker, or the time-up, lands first, so MatchRules always accepts the pickup); a speed / super
--   jump that ends in Result goes back too.
-- * Match HUD M1 (2026-10-16, the data of Diego's Match HUD: the kill feed and the final K.O. M:497-516, 567-572, the
--   respawn seconds M:73, 88, 113, 641, the streaks M:149, 349, 527, the standings M:610-614, 688): every MatchRules
--   `ko` becomes a HUD event {seq (1, 2, ... per match), kind "ko", at, victim, by (nil for a storm / out-of-bounds
--   K.O.), cause, final, streak (the attacker's after it), livesLeft (TDM: the victim's team lives after it, 0 when
--   out)}; the attacker's streak +1 (bestStreak = its best), the victim's streak 0. The events go out in the next view
--   sent to everyone (`events`, then forgotten); a view sent to one player (the storm bar, a power-up's end) has none.
--   Effects are performed in batches (one MatchRules step: stepMatch's loop, or the port's flush); each batch has its
--   own number (stepId), and perform gets the batch and the effect's index (the K.O.'s team lives). A win by koTarget,
--   wiped or overtime marks the last K.O. of its own batch `final` and keeps it as outcome.finalKo (a wipe by a leave,
--   a time-up or a draw has none). The players list carries respawnAt, out, protectUntil, streak and bestStreak; the
--   outcome carries the standings (MatchRules.standings order, present players only: a leaver is never on the
--   podium), built once at the end so every later view repeats the same list.
-- * Match HUD M2 (2026-10-16, owner Q3 / Q4; the results pills M:361-363, the WIN STREAK box M:186-189, the podium
--   chip M:353): while Config.Match.Rewards.enabled ([P] false until M9), the single end pays every present, real
--   player of a win or a draw like a 1v1 duel (Logic/MatchRewards: the duel's squeezes, throws and Active time, no
--   hourly cap) through deps.rewards: EconomyService.grantMatchResult (Coins with reason "match" and the win streak,
--   one profile step) and, when the profile took it and the pay is not 0, GripService.addFromMatch (the same squeezes
--   as Grip). A win (a team win, FFA 1st; paid or not) is +1 win streak, a loss or a draw 0; leaving a live match
--   (Countdown, Active, Overtime: /leave or the game) is 0 through the same step, nothing paid; cancelled / void pay
--   and touch nothing. What a player was paid ({coins, grip, streakBefore, streakAfter}) is outcome.mine in their own
--   view only (nil when not paid). The Player attribute SD_WinStreak (server-written, like SD_GripLevel) holds the
--   saved streak: set when a profile loads (init's DataService Loaded hook, refreshWinStreak) and after every grant.
--   Exactly once: the single end pays each player once, and grantMatchResult itself takes a matchId once per player
--   (a repeat is alreadyGranted: no Grip, no mine). Review fixes (2026-10-16): the pay rules come from
--   deps.rewards.config (tests) or the live Config; a leave that MatchRules no longer took (the leave's own step ended
--   the match first) is no leave: that player was present at the end, is paid like everyone present and keeps the
--   streak their result gives.
-- * Match bots (2026-10-17, owner: bots fill a match up to 12; MatchBotService, attached as deps.bots by attachBots):
--   while deps.bots.ready(), one queued player is enough to start a match (the gather as above; at once when everyone in
--   the server is queued), and startFromQueue fills the empty slots up to maxPlayers with deps.bots.take (no yield;
--   the ones startMatch did not take go back through release). A bot ref is a Player-shaped table (kind "bot", isBot,
--   squishyId: its squishy) with a character in the Workspace: it plays through the same port, rules, spawns and
--   movement as a player (MatchRules: arrived from the start; isBot), gets no MatchState and no toast, is never paid
--   (MatchRewards) and has no win streak. TDM: the players are shuffled and dealt Red, Blue, ... as before, then each
--   bot joins the smaller team (MatchBotRules.dealTeams: 6 vs 6). A match with bots pays its real players like any match
--   (owner: bots never block pay; Config.Match.Rewards.enabled still decides, off until M9). Once no real player is
--   left in it (left, never arrived) a bot match is void (MatchRules `empty`) and goes back as any void. A player who queues while a bot match
--   runs gets the next match: a running match takes nobody new (MatchRules' entrants are fixed at the start).
--   botView(ref) is what a bot's pilot may read of its match (the map, live, the storm time, the ready pads).
-- Every collaborator is reached through `deps` (useDeps in tests; init() builds the real ones), so the service is
-- unit-tested with fakes, without Players, remotes, Studio or a Heartbeat (tests call tick(now)).

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
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local StormMath = require(Shared.StormMath)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)
local Logic = script.Parent.Parent.Logic
local MatchBotRules = require(Logic.MatchBotRules)
local MatchFoundRoster = require(Logic.MatchFoundRoster)
local MatchRewards = require(Logic.MatchRewards)
local MatchRules = require(Logic.MatchRules)
local MatchSpawns = require(Logic.MatchSpawns)
local MatchVote = require(Logic.MatchVote)
local PowerUpRules = require(Logic.PowerUpRules)
local Services = script.Parent
local AbilityService = require(Services.AbilityService)
local CharacterService = require(Services.CharacterService)
local CombatService = require(Services.CombatService)
local EconomyService = require(Services.EconomyService)
local GripService = require(Services.GripService)
local InventoryService = require(Services.InventoryService)
local MatchMapService = require(Services.MatchMapService)
local NetService = require(Services.NetService)
local PracticeService = require(Services.PracticeService)
local QueueService = require(Services.QueueService)
local ShutdownService = require(Services.ShutdownService)
local StateService = require(Services.StateService)

-- Types

type MatchState = MatchRules.MatchState
type Effect = MatchRules.Effect
type Event = MatchRules.Event
type Fighter = CombatService.Fighter
type MatchPort = CombatService.MatchPort
type MapRecord = MatchMapService.MapRecord
type Spot = MatchSpawns.Spot

export type CombatDeps = {
	newFighter: (spec: any) -> any,
	registerMatch: (port: any) -> (),
	unregisterMatch: (matchId: string) -> (),
	pivotFighter: (fighter: any, cf: CFrame) -> boolean,
	noteTeleport: (fighter: any) -> (),
	syncTo: (now: number) -> (),
	releaseFighter: (fighter: any) -> boolean, -- one leaver out of a running ffa port (area A)
}

export type AbilityDeps = {
	attachMatch: (port: any) -> (),
	detachMatch: (matchId: string) -> (),
	detachFighter: (userId: number) -> (), -- one leaver's caster forgotten (area A; before releaseFighter)
	isReady: (userId: number) -> boolean,
	-- Power-ups v1.1: the ult charge power-up (AbilityService.addChargeFraction); optional (nil: nothing happens).
	addCharge: ((userId: number, fraction: number) -> boolean)?,
}

export type MapDeps = {
	acquire: (modeId: string, matchId: string) -> any?,
	release: (record: any) -> (),
	hasMode: (modeId: string) -> boolean,
}

-- Match HUD M2: the match pay (EconomyService / GripService). Optional: nil = nothing is paid.
export type RewardDeps = {
	grant: (ref: any, matchId: string, pay: MatchRewards.Pay) -> EconomyService.MatchGrant, -- grantMatchResult
	addGrip: (ref: any, squeezes: number) -> number, -- GripService.addFromMatch
	winStreak: (ref: any) -> number, -- EconomyService.winStreak: the saved streak
	-- The pay rules (a Config-shaped table with Economy.DuelRewards; tests pass their copy); nil = the live Config.
	config: MatchRewards.RewardConfig?,
}

-- Match bots (MatchBotService). Optional: nil = no bots.
export type BotDeps = {
	ready: () -> boolean, -- take() can give bots now
	-- Up to `count` bot refs now (no yield; fewer, or none, when it can't). startMatch must follow in the same frame.
	take: (modeId: string, count: number) -> { any },
	release: (ref: any) -> (), -- a taken bot that is in no match: destroyed
}

export type Deps = {
	now: () -> number, -- server time
	clock: () -> number, -- os.clock (timeouts, the return-point LRU)
	wait: (seconds: number) -> (),
	defer: (fn: (...any) -> ...any, ...any) -> (),
	spawn: (fn: (...any) -> ...any, ...any) -> (),
	rng: Random,
	isPlayer: (ref: any) -> boolean, -- a real Player still in the game
	playerCount: () -> number,
	getRoot: (ref: any) -> any?, -- the HumanoidRootPart
	humanoid: (ref: any) -> any?,
	isAlive: (ref: any) -> boolean,
	teleportAsync: (ref: any, cf: CFrame) -> (boolean, string?),
	equipped: (ref: any) -> string?,
	queueState: (ref: any) -> string, -- QueueService.state
	isPracticing: (ref: any) -> boolean,
	closing: () -> boolean,
	restartPending: () -> boolean,
	canFinishBeforeRestart: (seconds: number) -> boolean,
	fire: (name: string, ref: any, payload: any) -> (),
	notify: (ref: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?) -> (),
	combat: CombatDeps,
	ability: AbilityDeps,
	maps: MapDeps,
	rewards: RewardDeps?, -- Match HUD M2 (nil: no pay, as in the older tests' fakes)
	bots: BotDeps?, -- match bots (attachBots; nil: none)
	heartbeat: boolean, -- tick matches every Heartbeat (false in tests: they call tick)
	matchConfig: any?, -- a Config.Match-shaped table (tests pass their copy); nil = the live Config.Match
	gripLevel: ((ref: any) -> number)?, -- round 2 of the match flow: GripService.levelOf (nil: MATCH FOUND makes them up)
}

type SavedMovement = { walkSpeed: number, jumpHeight: number, jumpPower: number, autoRotate: boolean }

type Participant = {
	ref: any, -- the Player
	userId: number,
	displayName: string,
	squishyId: string,
	team: string?, -- TDM: Config.Match.teamNames[1] / [2]
	side: Types.Side,
	fighter: Fighter,
	spot: Spot?, -- where the player stands now (first spot, then each respawn / re-pivot)
	moved: boolean, -- teleported into the map: must be returned
	positioning: boolean, -- the first teleport is in flight
	placing: boolean, -- a re-placement teleport is in flight
	dropped: boolean, -- never arrived: back in the lobby since the Countdown
	gone: boolean, -- left the match (/leave or the game)
	savedMovement: SavedMovement?,
	throws: number,
	sentStormBar: number, -- the storm bar of the last view this player got
	buffsCheckedAt: number, -- power-ups v1.1: buffs ending at or before this were already handled (expireBuffs)
	streak: number, -- Match HUD M1: K.O.s since this player was last knocked out
	bestStreak: number, -- Match HUD M1: the longest streak of this match
}

-- Power-ups v1.1: one pad of a match (the map's PowerUpPad, with its PowerUpRules state).
type MatchPad = { name: string, position: Vector3, top: number, pad: PowerUpRules.Pad }

-- Match HUD M1: a HUD event (its wire view) kept until the next view sent to everyone; `step` = the batch (stepId) of
-- the effect it came from.
type HudEvent = { view: Types.MatchEventView, step: number }

type Match = {
	matchId: string,
	modeId: string,
	mode: any, -- Config.Match.Modes[modeId]
	map: MapRecord,
	state: MatchState,
	port: MatchPort,
	list: { Participant },
	byUserId: { [number]: Participant },
	pending: { Effect }, -- effects of applyHits, performed by flush
	stateDirty: boolean, -- MatchState must be re-sent to everyone
	returning: boolean,
	closed: boolean,
	endedFired: boolean,
	nextStormAt: number,
	createdAt: number,
	-- Power-ups v1.1:
	pads: { MatchPad },
	nextPadAt: number, -- the next pickup sample
	nextBuffAt: number, -- the earliest end of a live timed power-up (math.huge = none)
	now: number, -- the server time of the latest step (the views' "live" buffs)
	-- Match HUD M1:
	events: { HudEvent }, -- since the last view sent to everyone
	eventSeq: number, -- the last HUD event's seq
	stepId: number, -- the batch of effects being performed (bumped once per perform loop)
	finalKo: HudEvent?, -- the K.O. that ended the match (koTarget, wiped, overtime)
	standings: { Types.MatchStandingView }?, -- built once, with the outcome
	rewards: { [number]: Types.MatchRewardView }, -- Match HUD M2: userId -> what the end paid them (outcome.mine)
	bots: number, -- match bots: how many bots it started with
}

-- Round 3 of the match flow: a queue match waiting through the MATCH FOUND show and the map vote (see the header).
type Pending = {
	id: string, -- the matchId it starts with
	modeId: string,
	refs: { any }, -- the players, then the bots (startMatch's order)
	teams: { [any]: string }, -- TDM: ref -> team
	bots: { any },
	maps: { MapRecord }, -- the cards, in Vote.mapOrder
	votes: MatchVote.Order,
	opensAt: number,
	closesAt: number,
	botAt: { number | false }, -- bots[i] votes then (server time); false = never, or done
	lastVoteAt: { [number]: number },
	result: Types.MatchVoteResultView?,
}

type Ticket = { player: any, userId: number, joinedAt: number }
type Gather = { endsAt: number, waitingMapSent: boolean }

-- What getMatch returns (read-only).
export type MatchInfo = {
	matchId: string,
	modeId: string,
	phase: Types.DuelPhase, -- the D1 name
	matchPhase: string, -- the MatchRules phase
	team: string?,
}

-- What botView returns (read-only): what a match bot's pilot may know of its match now.
export type BotView = {
	map: MapRecord,
	live: boolean, -- Active or Overtime, not ended
	stormSeconds: number?, -- a storm mode: the Active seconds the storm reads (nil: no storm in this mode)
	pads: { Vector3 }, -- the ready power-up pads: their centres at the height a player stands on (the pad's top)
}

-- The MatchEnded payload.
export type MatchSummary = {
	matchId: string,
	modeId: string,
	mapCode: string,
	outcome: string, -- MatchRules outcome kind
	reason: string,
	winnerUserId: number?,
	winnerTeam: string?,
	winners: { number },
	activeSeconds: number,
	participants: { { userId: number, team: string?, kos: number, knockedOut: number, left: boolean } },
}

-- Constants

local RULES = Config.Duel.Rules
local MOVEMENT = RULES.Movement
local POSITIONING = Config.Duel.Positioning
local REMOTE_STATE = "MatchState"
local REMOTE_QUEUE = "MatchQueue"
local REMOTE_FOUND = "MatchFound"
local REMOTE_VOTE_STATE = "MatchVoteState"
local REMOTE_VOTE = "MatchVote"
local REMOTE_JOIN = "MatchJoin"
local REMOTE_LEAVE = "MatchLeave"
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_PHASE = "SD_DuelPhase"
local ATTR_MATCH_PHASE = "SD_MatchPhase"
local ATTR_MODE = "SD_MatchMode"
local ATTR_TEAM = "SD_Team"
local ATTR_WIN_STREAK = "SD_WinStreak" -- Match HUD M2: the saved win streak, on every player (lobby too)
local MATCH_ID_PREFIX = "match:"
-- D1: MatchRules phase -> the DuelPhase name on the wire and in SD_DuelPhase (Overtime is NOT SuddenDeath).
local WIRE_PHASE: { [string]: Types.DuelPhase } = {
	Waiting = "Positioning",
	Countdown = "Countdown",
	Active = "Active",
	Overtime = "Active",
	Result = "Result",
	Closed = "Returning",
}
local SIDES: { Types.Side } = { "A", "B" } -- teamNames[1] (Red) = "A", teamNames[2] (Blue) = "B"
local POLL_SECONDS = 0.1
local QUEUE_TICK_SECONDS = 0.5
local RETURN_PADDING_SECONDS = 1 -- reading (as DuelService): extra time a return may take beyond the stream timeout
local REPLACE_TIMEOUT_SECONDS = 10 -- reading: a re-placement gives up after this long (the next check tries again)
-- Reading (as DuelService's ARENA_RADIUS_STUDS): a character is "in the map" within the footprint's half diagonal
-- plus this apron (horizontally). The maps are 500 studs apart, so this never reaches the next map or the lobby.
local MAP_APRON_STUDS = 40
local RETURN_RING = 6 -- players around one return point per ring

-- The Notify codes (Strings match.*).
local CODE = table.freeze({
	joined = "match.joined",
	left = "match.left",
	leftForDuel = "match.leftForDuel",
	startingIn = "match.startingIn",
	waitingPlayers = "match.waitingPlayers",
	waitingMap = "match.waitingMap",
	youLeft = "match.youLeft",
	notQueued = "match.notQueued",
	notArrived = "match.notArrived",
	outOfBounds = "match.outOfBounds",
	outOfBoundsKo = "match.outOfBoundsKo",
	outNoLives = "match.outNoLives",
	youWin = "match.youWin",
	winner = "match.winner",
	teamWins = "match.teamWins",
	draw = "match.draw",
	cancelled = "match.cancelled",
	void = "match.void",
	voidError = "match.voidError",
	closing = "match.refused.closing",
	alreadyQueued = "match.refused.alreadyQueued",
	inMatch = "match.refused.inMatch",
	duelQueue = "match.refused.duelQueue",
	practice = "match.refused.practice",
	noMaps = "match.refused.noMaps",
	powerUp = "match.powerUp.", -- power-ups v1.1: + the Config.Match.PowerUps kind (the pickup toast)
	paid = "match.paid", -- qb1 (owner 2026-10-16): the pay toast, a stand-in until M9's results bar
})

-- Module table

local MatchService = {}

-- (summary: MatchSummary) exactly once per match, on its single end. Nothing listens in v1 (no rewards or quests).
MatchService.MatchEnded = Signal.new() :: Signal.Signal<MatchSummary>

-- Private

local log = Log.new("Match")
local deps: Deps? = nil
local matches: { [string]: Match } = {}
local matchOfUser: { [number]: Match } = {}
local queues: { [string]: { Ticket } } = {}
local gathers: { [string]: Gather } = {}
local pendings: { [string]: Pending } = {} -- round 3 of the match flow: id -> its map vote
local pendingOfUser: { [number]: Pending } = {} -- its players and bots
-- Round 3's helpers live in one table: this chunk is near Luau's 200-local limit. Filled in "Private: the map vote".
local Pend = {}
local returnPointUsedAt: { [number]: number } = {} -- ReturnPoints index -> clock() of its last use
local heartbeat: RBXScriptConnection? = nil
local defaultDeps: () -> Deps

local function getDeps(): Deps
	local d = deps
	if d ~= nil then
		return d
	end
	local made = defaultDeps()
	deps = made
	return made
end

-- Config.Match (the test's copy when given). Never read at module load: a cached old Config would lack the new fields.
local function cfg(): any
	local d = deps
	return if d ~= nil and d.matchConfig ~= nil then d.matchConfig else Config.Match
end

local function try(fn: (...any) -> ...any, ...: any): (boolean, any)
	local ok, err = pcall(fn :: any, ...)
	return ok, err
end

local function userIdOf(ref: any): number?
	if type(ref) == "number" then
		return ref
	elseif typeof(ref) == "Instance" then
		return if ref:IsA("Player") then ref.UserId else nil
	elseif type(ref) == "table" then
		local id = ref.userId or ref.UserId
		return if type(id) == "number" then id else nil
	end
	return nil
end

-- Match bots: a bot ref (MatchBotService's, a BotService bot), as DuelService tells the practice bot.
local function isBotRef(ref: any): boolean
	return type(ref) == "table" and ref.isBot == true and ref.kind == "bot"
end

local function attributeOf(ref: any, name: string): any
	if typeof(ref) == "Instance" then
		return ref:GetAttribute(name)
	elseif type(ref) == "table" and type(ref.GetAttribute) == "function" then
		local ok, value = pcall(ref.GetAttribute, ref, name)
		return if ok then value else nil
	end
	return nil
end

local function setAttribute(ref: any, name: string, value: any)
	if typeof(ref) == "Instance" then
		ref:SetAttribute(name, value)
	elseif type(ref) == "table" and type(ref.SetAttribute) == "function" then
		pcall(ref.SetAttribute, ref, name, value)
	end
end

local function textOf(key: string, fallback: string): string
	return Strings.resolve(key) or fallback
end

local function modeName(modeId: string): string
	return textOf(`match.mode.{modeId}`, modeId)
end

local function teamName(team: string): string
	return textOf(`match.team.{string.lower(team)}`, team)
end

local function notify(ref: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
	if isBotRef(ref) then
		return -- match bots: no client
	end
	local ok, err = try(getDeps().notify, ref, code, args, kind)
	if not ok then
		log:warn(`notify {code} failed:`, err)
	end
end

local function matchList(): { Match }
	local list: { Match } = {}
	for _, match in matches do
		table.insert(list, match)
	end
	return list
end

local function inAnyMatch(ref: any): boolean
	local userId = userIdOf(ref)
	if userId ~= nil and (matchOfUser[userId] ~= nil or pendingOfUser[userId] ~= nil) then
		return true
	end
	local matchId, phase = attributeOf(ref, ATTR_MATCH_ID), attributeOf(ref, ATTR_PHASE)
	return (type(matchId) == "string" and matchId ~= "") or (type(phase) == "string" and phase ~= "")
end

local function record(match: Match, p: Participant): MatchRules.Participant?
	return MatchRules.participant(match.state, p.userId)
end

-- Present and standing in MatchRules.
local function standing(match: Match, p: Participant): boolean
	local r = record(match, p)
	return r ~= nil and r.present and r.alive
end

local function active(p: Participant): boolean
	return not p.gone and not p.dropped
end

local function wirePhaseOf(match: Match): Types.DuelPhase
	if match.returning or match.closed then
		return "Returning"
	end
	return WIRE_PHASE[match.state.phase] or "Returning"
end

-- Private: movement (DuelService's pattern) ------------------------------------------------------------------------------

-- §5.4: R15 HipHeight + HRP.Size.Y/2 + R15ExtraHeight; R6 (or unknown) R6Height.
local function standHeight(p: Participant): number
	local d = getDeps()
	local humanoid = d.humanoid(p.ref)
	local root = d.getRoot(p.ref)
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 and root and typeof(root.Size) == "Vector3" then
		return humanoid.HipHeight + root.Size.Y / 2 + POSITIONING.R15ExtraHeight
	end
	return POSITIONING.R6Height
end

local function spotCFrame(p: Participant, spot: Spot): CFrame
	return MatchSpawns.placement(spot, standHeight(p))
end

local function saveMovement(p: Participant, humanoid: any)
	if p.savedMovement ~= nil then
		return
	end
	-- A 0 here is a hold, not the lobby value (as DuelService): the lobby default is saved instead.
	local walk, jump, power = humanoid.WalkSpeed, humanoid.JumpHeight, humanoid.JumpPower
	p.savedMovement = {
		walkSpeed = if walk > 0 then walk else MOVEMENT.WalkSpeed,
		jumpHeight = if jump > 0 then jump else MOVEMENT.JumpHeight,
		jumpPower = if power > 0 then power else StarterPlayer.CharacterJumpPower,
		autoRotate = humanoid.AutoRotate ~= false,
	}
end

-- Waiting / Countdown: frozen; a K.O. (D3) also stops turning.
local function freezeMovement(p: Participant, knockedOut: boolean)
	local humanoid = getDeps().humanoid(p.ref)
	if humanoid == nil then
		return
	end
	saveMovement(p, humanoid)
	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	end
	if knockedOut then
		humanoid.AutoRotate = false
	end
end

-- Power-ups v1.1: the Config.Match.PowerUps kind's number `field` while p's power-up of that kind lives at `now`, else
-- `default` (also when the Config has no such number).
local function buffNumber(
	match: Match,
	p: Participant,
	power: string,
	field: string,
	now: number,
	default: number
): number
	if not MatchRules.hasBuff(match.state, p.userId, power, now) then
		return default
	end
	local kind = cfg().PowerUps.kinds[power]
	local value = if kind then kind[field] else nil
	return if type(value) == "number" and value == value then value else default
end

-- Power-ups v1.1: the walk speed and jump height a standing `p` has at `now`: Config.Duel.Rules.Movement × the live
-- speed / super jump power-ups.
local function buffedMovement(match: Match, p: Participant, now: number): (number, number)
	return MOVEMENT.WalkSpeed * buffNumber(match, p, "speed", "walkMultiplier", now, 1),
		MOVEMENT.JumpHeight * buffNumber(match, p, "superJump", "jumpMultiplier", now, 1)
end

-- Power-ups v1.1: the throw cooldown multiplier of p's fighter at `now` (CombatService hands it to ThrowRules): 1, or
-- the live rapid throw's kinds.rapidThrow.cooldownMultiplier. Review fix (2026-10-16, SPEC P3): "no wait" is the
-- shortest cooldown, Config.Duel.Rules.CooldownClamp.Min (0.6 s), not none. ThrowRules clamps the catalog cooldown
-- first and multiplies after, so the multiplier is kept at or above Min / that clamped cooldown. That is at most
-- 1 / Min throws a second, under Config.Net's ThrowRequest and ChargeStart buckets (an honest client never hits them).
local function throwCooldownMultiplier(match: Match, p: Participant, fighter: Fighter, now: number): number
	local multiplier = buffNumber(match, p, "rapidThrow", "cooldownMultiplier", now, 1)
	if multiplier >= 1 then
		return multiplier
	end
	local stats = (fighter :: any).throw -- CombatService's fighter always has it (a test's fake may not)
	if type(stats) ~= "table" then
		local def = Catalog.get(p.squishyId) or Catalog.get(Catalog.starterId())
		stats = if def then def.throw else nil
	end
	local clamp = RULES.CooldownClamp
	local cooldown = if stats and type(stats.cooldown) == "number" then stats.cooldown else clamp.Min
	return math.max(multiplier, clamp.Min / math.clamp(cooldown, clamp.Min, clamp.Max))
end

-- Active (and a respawn): Config.Duel.Rules.Movement, turning on again. Power-ups v1.1: with the live speed / super
-- jump power-ups (buffedMovement at the latest step's time).
local function matchMovement(match: Match, p: Participant)
	local humanoid = getDeps().humanoid(p.ref)
	if humanoid == nil then
		return
	end
	saveMovement(p, humanoid)
	local walk, jump = buffedMovement(match, p, match.now)
	humanoid.WalkSpeed = walk
	humanoid.JumpHeight = jump
	local saved = p.savedMovement
	if humanoid.UseJumpPower and saved then
		humanoid.JumpPower = saved.jumpPower
	end
	humanoid.AutoRotate = if saved then saved.autoRotate else true
end

local function restoreMovement(p: Participant)
	local humanoid = getDeps().humanoid(p.ref)
	local saved = p.savedMovement
	if humanoid == nil or saved == nil then
		return
	end
	humanoid.WalkSpeed = saved.walkSpeed
	humanoid.JumpHeight = saved.jumpHeight
	humanoid.JumpPower = saved.jumpPower
	humanoid.AutoRotate = saved.autoRotate
	p.savedMovement = nil
end

-- The movement a (re-)placed character gets for the match's state.
local function movementForState(match: Match, p: Participant)
	local phase = match.state.phase
	if phase == "Waiting" or phase == "Countdown" then
		freezeMovement(p, false)
	elseif standing(match, p) then
		matchMovement(match, p)
	else
		freezeMovement(p, true)
	end
end

-- Power-ups v1.1: a pickup or a power-up's end changes a standing player's movement at once. Not while everyone is held
-- (Waiting, Countdown) or the return runs, the player is knocked out (frozen) or an ultimate roots them (WalkSpeed 0 on
-- the server: AbilityService gives port.movement back at the root's end). Review fix (2026-10-16): Result is not held
-- (players still walk there), so a speed / super jump that ends in Result goes back too.
local function refreshMovement(match: Match, p: Participant, now: number)
	local phase = match.state.phase
	if
		not active(p)
		or match.returning
		or match.closed
		or phase == "Waiting"
		or phase == "Countdown"
		or not standing(match, p)
	then
		return
	end
	local rootedUntil = (p.fighter :: any).rootedUntil
	if type(rootedUntil) == "number" and now < rootedUntil then
		return
	end
	matchMovement(match, p)
end

-- Private: attributes and views ----------------------------------------------------------------------------------------

local function setMatchAttributes(match: Match, p: Participant)
	setAttribute(p.ref, ATTR_MATCH_ID, match.matchId)
	setAttribute(p.ref, ATTR_PHASE, wirePhaseOf(match))
	setAttribute(p.ref, ATTR_MATCH_PHASE, match.state.phase)
	setAttribute(p.ref, ATTR_MODE, match.modeId)
	setAttribute(p.ref, ATTR_TEAM, p.team)
end

-- SD_MatchId / SD_DuelPhase go back to "" (as DuelService: the readers compare with ""); the others are removed.
local function clearAttributes(p: Participant)
	setAttribute(p.ref, ATTR_PHASE, "")
	setAttribute(p.ref, ATTR_MATCH_ID, "")
	setAttribute(p.ref, ATTR_MATCH_PHASE, nil)
	setAttribute(p.ref, ATTR_MODE, nil)
	setAttribute(p.ref, ATTR_TEAM, nil)
end

local function setPhaseAttributes(match: Match)
	for _, p in match.list do
		if active(p) then
			setAttribute(p.ref, ATTR_PHASE, wirePhaseOf(match))
			setAttribute(p.ref, ATTR_MATCH_PHASE, match.state.phase)
		end
	end
end

local function finiteOrZero(value: number?): number
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return value
end

-- Everyone still in the match (a player who left or never arrived is not listed: no enemy, no leader). Match HUD M1:
-- with their respawn time, out, spawn protection and streaks (every tile's respawn seconds and streak, M:73, 149).
local function playersView(match: Match): { Types.MatchParticipantView }
	local d = getDeps()
	local list: { Types.MatchParticipantView } = {}
	for _, p in match.list do
		local r = record(match, p)
		if r and active(p) then
			local ok, ready = try(d.ability.isReady, p.userId)
			table.insert(list, {
				userId = p.userId,
				displayName = p.displayName,
				squishyId = p.squishyId,
				team = p.team,
				kos = r.kos,
				knockedOut = r.knockedOut,
				alive = r.present and r.alive,
				ultReady = ok and ready == true,
				respawnAt = r.respawnAt,
				out = r.out,
				protectUntil = finiteOrZero(r.protectUntil), -- 0 = none
				streak = p.streak,
				bestStreak = p.bestStreak,
			})
		end
	end
	return list
end

-- Match HUD M1: the standings at the end (MatchRules.standings order), present players only (a leaver, or a player
-- who never arrived, is not on the podium), each with their final stats. "Present" is MatchRules' own, as for the
-- outcome's winner (review 2026-10-16): a /leave in the very step that ended the match is one MatchRules ignored, so
-- that player finished the match and stays listed (else the winner could be missing from the standings).
local function standingsView(match: Match): { Types.MatchStandingView }
	local list: { Types.MatchStandingView } = {}
	for _, r in MatchRules.standings(match.state) do
		local p = match.byUserId[r.userId]
		if r.present and p ~= nil then
			table.insert(list, { userId = r.userId, kos = r.kos, knockedOut = r.knockedOut, bestStreak = p.bestStreak })
		end
	end
	return list
end

-- Power-ups v1.1: the player's live timed power-ups (kind -> server time it ends) at the latest step's time.
local function buffsView(match: Match, r: MatchRules.Participant?): { [string]: number }
	local out: { [string]: number } = {}
	if r then
		for power, untilAt in r.buffs do
			if type(untilAt) == "number" and untilAt > match.now then
				out[power] = untilAt
			end
		end
	end
	return out
end

-- Power-ups v1.1: every pad of the match, {name, readyAt} (server time; 0 = ready).
local function padsView(match: Match): { Types.MatchPadView }
	local list: { Types.MatchPadView } = {}
	for _, entry in match.pads do
		table.insert(list, { name = entry.name, readyAt = finiteOrZero(entry.pad.readyAt) })
	end
	return list
end

-- Match HUD M1: `events` = the HUD events of a view sent to everyone (nil for a view sent to one player). Match HUD M2:
-- the outcome's `mine` is the receiver's own pay.
local function viewFor(
	match: Match,
	p: Participant,
	players: { Types.MatchParticipantView },
	events: { Types.MatchEventView }?
): Types.MatchStateView
	local state = match.state
	local map = match.map
	local r = record(match, p)
	local outcome = state.outcome
	local view: Types.MatchStateView = {
		matchId = match.matchId,
		mode = match.modeId :: any,
		mapCode = map.code,
		mapName = map.name,
		phase = wirePhaseOf(match),
		matchPhase = if match.returning or match.closed then "Closed" else state.phase,
		phaseEndsAt = finiteOrZero(state.phaseEndsAt), -- 0 = no timer
		activeStartedAt = state.activeStartedAt,
		you = {
			userId = p.userId,
			team = p.team,
			alive = r ~= nil and r.present and r.alive,
			respawnAt = if r then r.respawnAt else nil,
			protectUntil = finiteOrZero(if r then r.protectUntil else nil), -- 0 = none
			stormBar = if r then r.stormBar else 0,
			out = r ~= nil and r.out,
			buffs = buffsView(match, r), -- power-ups v1.1
		},
		players = players,
		teamLives = if match.mode.teams then table.clone(state.teamLives) else nil,
		koTarget = if match.mode.teams then nil else match.mode.koTarget,
		arena = { floorY = map.floorY, bounds = map.bounds, centre = map.centre },
		storm = if match.mode.storm then { startRadius = map.startRadius } else nil,
		outcome = if outcome
			then {
				kind = outcome.kind,
				reason = outcome.reason,
				winnerUserId = outcome.winnerUserId,
				winnerTeam = outcome.winnerTeam,
				winners = table.clone(outcome.winners),
				-- Match HUD M1: the final K.O. (M:567-572) and the standings (M:610-614, 688), frozen at the end.
				finalKo = if match.finalKo then table.clone(match.finalKo.view) else nil,
				standings = match.standings or {},
				-- Match HUD M2: what the end paid this receiver (the results pills, M:361-363); nil when not paid.
				mine = if match.rewards[p.userId] then table.clone(match.rewards[p.userId]) else nil,
			}
			else nil,
		pads = padsView(match), -- power-ups v1.1
		events = events, -- Match HUD M1
	}
	return view
end

-- Sends MatchState to every active participant (or only to those in `only`); the players list is built once. Match
-- HUD M1: a send to everyone carries the HUD events since the previous one (then they are forgotten); a send to
-- `only` carries none (they wait for the next send to everyone).
local function sendState(match: Match, only: { Participant }?)
	local d = getDeps()
	local players = playersView(match)
	local events: { Types.MatchEventView }? = nil
	if only == nil then
		local list: { Types.MatchEventView } = {}
		for _, event in match.events do
			table.insert(list, table.clone(event.view))
		end
		events = list
		match.events = {}
	end
	for _, p in only or match.list do
		if active(p) and not isBotRef(p.ref) then -- match bots: no client
			local r = record(match, p)
			p.sentStormBar = if r then r.stormBar else 0
			local ok, err = try(d.fire, REMOTE_STATE, p.ref, viewFor(match, p, players, events))
			if not ok then
				log:warn(`MatchState to user {p.userId} failed:`, err)
			end
		end
	end
end

local function syncFighters(match: Match)
	for _, p in match.list do
		local r = record(match, p)
		if r then
			p.fighter.invulnUntil = r.protectUntil -- a mirror (CombatService never decides with it)
		end
	end
end

-- Private: places ------------------------------------------------------------------------------------------------------

local function stormCentre(match: Match): Vector3
	return Vector3.new(match.map.centre.X, match.map.floorY, match.map.centre.Z)
end

local function inMap(match: Match, position: Vector3): boolean
	local centre = match.map.centre
	local dx, dz = position.X - centre.X, position.Z - centre.Z
	local reach = match.map.startRadius + MAP_APRON_STUDS
	return dx * dx + dz * dz <= reach * reach
end

-- A respawn spot for `p` now (MatchSpawns: the own team's free spot / the pad far from enemies / the safe circle).
local function respawnSpotFor(match: Match, p: Participant): Spot
	local d = getDeps()
	local c = cfg()
	local enemies: { Vector3 } = {}
	local occupied: { Vector3 } = {}
	for _, other in match.list do
		if other ~= p and standing(match, other) then
			local root = d.getRoot(other.ref)
			if root then
				table.insert(occupied, root.Position)
				if not (match.mode.teams and other.team == p.team) then
					table.insert(enemies, root.Position)
				end
			end
		end
	end
	local storm: MatchSpawns.StormCircle? = nil
	if match.mode.storm then
		local t = MatchRules.activeSeconds(match.state, d.now())
		if StormMath.shown(c.Storm, t) then
			storm = { centre = stormCentre(match), radius = StormMath.radiusAt(c.Storm, match.map.startRadius, t) }
		end
	end
	return MatchSpawns.respawnSpot(match.map.spawns, {
		team = p.team,
		enemies = enemies,
		occupied = occupied,
		last = p.spot,
		r = d.rng:NextNumber(),
		storm = storm,
		raycast = match.map.raycast,
	}, c)
end

-- Moves the fighter to `spot` now (no yield). False without a character.
local function pivotTo(match: Match, p: Participant, spot: Spot): boolean
	p.spot = spot
	local ok, moved = try(getDeps().combat.pivotFighter, p.fighter, spotCFrame(p, spot))
	return ok and moved == true
end

local stepMatch: (match: Match, event: Event, now: number?) -> ()
local returnOne: (match: Match, p: Participant, slotOf: { [number]: number }?) -> ()

-- D5: re-places a character found outside the map (a new one after a death) at a respawn spot, retried until it works.
local function replaceParticipant(match: Match, p: Participant)
	if p.placing or p.positioning then
		return
	end
	p.placing = true
	local d = getDeps()
	d.spawn(function()
		local ok, err = try(function()
			local deadline = d.clock() + REPLACE_TIMEOUT_SECONDS
			while not match.closed and not match.returning and active(p) and d.clock() < deadline do
				if d.isAlive(p.ref) and d.getRoot(p.ref) ~= nil then
					local phase = match.state.phase
					local before = phase == "Waiting" or phase == "Countdown"
					local spot = if before and p.spot then p.spot else respawnSpotFor(match, p)
					local moved = d.teleportAsync(p.ref, spotCFrame(p, spot))
					if moved then
						p.spot = spot
						p.moved = true
						d.combat.noteTeleport(p.fighter)
						-- The teleport yields while it streams: the player may have left (or the match closed) since.
						if active(p) and not match.closed then
							movementForState(match, p)
						end
						return
					end
				end
				d.wait(POLL_SECONDS)
			end
		end)
		p.placing = false
		if not ok then
			log:error(`re-placing user {p.userId} failed:`, err)
		end
		if p.moved and (not active(p) or match.closed) then
			d.spawn(returnOne, match, p, nil) -- it landed after /leave (or the return): back to the lobby
		end
	end)
end

-- Waiting: the first teleport to the player's spot, retried until it works (DuelService's positionParticipant).
local function positionParticipant(match: Match, p: Participant)
	p.positioning = true
	local d = getDeps()
	local ok, err = try(function()
		while not match.closed and active(p) and match.state.phase == "Waiting" and d.now() < match.state.phaseEndsAt do
			local spot = p.spot
			if spot and d.isAlive(p.ref) and d.getRoot(p.ref) ~= nil then
				local moved = d.teleportAsync(p.ref, spotCFrame(p, spot))
				if moved then
					p.moved = true
					d.combat.noteTeleport(p.fighter)
					-- The teleport yields while it streams: the player may have left (/leave), been dropped by the
					-- Countdown or the match closed since. Only a player still in the match is frozen and arrives.
					if active(p) and not match.closed then
						freezeMovement(p, false)
						if match.state.phase == "Waiting" then
							stepMatch(match, { kind = "arrived", userId = p.userId })
						end
					end
					return
				end
			end
			d.wait(POLL_SECONDS)
		end
	end)
	p.positioning = false
	if not ok then
		log:error(`positioning user {p.userId} failed:`, err)
	end
	if p.moved and (not active(p) or match.closed) then
		-- The teleport landed after the player left or was dropped (or after the return): back to the lobby.
		d.spawn(returnOne, match, p, nil)
	end
end

-- Every first teleport, deferred. Match bots first: their teleport never streams, so they stand on their spots before
-- the last player arrives (that arrival starts the Countdown, which ends the positioning).
local function positionAll(match: Match)
	local d = getDeps()
	for _, p in match.list do
		p.positioning = true -- set now: a return that starts before the deferred thread runs must wait for it
	end
	for pass = 1, 2 do
		for _, p in match.list do
			if isBotRef(p.ref) == (pass == 1) then
				d.defer(positionParticipant, match, p)
			end
		end
	end
end

-- Private: lifecycle -----------------------------------------------------------------------------------------------------

local perform: (match: Match, effect: Effect, effects: { Effect }, index: number) -> ()

-- One MatchRules event: the new state is stored first, then its effects run (none of them yields). The projectiles
-- are swept up to the same time first (CombatService.syncTo), as in DuelService.stepMatch. Match HUD M1: the effects
-- are one batch (a new stepId; a flush that syncTo runs first is a batch of its own).
stepMatch = function(match: Match, event: Event, now: number?)
	if match.closed then
		return
	end
	local d = getDeps()
	local t = if now ~= nil then now else d.now()
	d.combat.syncTo(t)
	if match.closed then
		return
	end
	local state, effects = MatchRules.step(match.state, event, t)
	match.state = state
	match.now = math.max(match.now, t) -- power-ups v1.1: the time the views' live buffs are read at
	syncFighters(match)
	match.stepId += 1
	for index, effect in effects do
		perform(match, effect, effects, index)
	end
	if match.stateDirty and not match.closed then
		match.stateDirty = false
		sendState(match)
	end
end

local function stopHeartbeatIfIdle()
	if next(matches) == nil and heartbeat ~= nil then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

-- The terminal cleanup: unregister from combat and abilities, release the map, clear the attributes, forget the match.
local function closeMatch(match: Match)
	if match.closed then
		return
	end
	match.closed = true
	local d = getDeps()
	local matchId = match.matchId
	try(d.combat.unregisterMatch, matchId)
	try(d.ability.detachMatch, matchId)
	try(d.maps.release, match.map)
	for _, p in match.list do
		if matchOfUser[p.userId] == match then
			matchOfUser[p.userId] = nil
		end
		if active(p) then
			clearAttributes(p)
		end
	end
	matches[matchId] = nil
	stopHeartbeatIfIdle()
	log:info(`match {matchId} closed`)
end

local function safeClose(match: Match)
	local ok, err = try(closeMatch, match)
	if not ok then
		log:error(`closing match {match.matchId} failed:`, err)
	end
end

-- The least-recently-used lobby return point for this character, `slot` places it around the point (0 = on it).
local function returnCFrame(p: Participant, slotOf: { [number]: number }?): CFrame?
	local d = getDeps()
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
	returnPointUsedAt[bestIndex] = d.clock()
	local slot = 0
	if slotOf then
		slot = slotOf[bestIndex] or 0
		slotOf[bestIndex] = slot + 1
	end
	local point = points[bestIndex]
	local position = point.position
	if slot > 0 then
		local ring = (slot - 1) // RETURN_RING + 1
		local angle = ((slot - 1) % RETURN_RING) * 2 * math.pi / RETURN_RING
		position += Vector3.new(math.cos(angle), 0, math.sin(angle)) * cfg().returnSpreadStuds * ring
	end
	return CFrame.lookAt(position, position + point.facing) + Vector3.new(0, standHeight(p), 0)
end

returnOne = function(match: Match, p: Participant, slotOf: { [number]: number }?)
	local d = getDeps()
	if p.moved and d.isPlayer(p.ref) then
		local root = d.getRoot(p.ref)
		if root and inMap(match, root.Position) then
			local cf = returnCFrame(p, slotOf)
			if cf then
				local moved, reason = d.teleportAsync(p.ref, cf)
				if not moved then
					log:warn(`could not return user {p.userId} to the lobby ({tostring(reason)}); they respawn there`)
				end
			end
		end
	end
	p.moved = false
	restoreMovement(p)
	clearAttributes(p)
end

local function anyInFlight(match: Match): boolean
	for _, p in match.list do
		if p.positioning or p.placing then
			return true
		end
	end
	return false
end

-- Closed: everyone still in the map back to the lobby, then the cleanup.
local function returnPlayers(match: Match)
	local d = getDeps()
	local limit = POSITIONING.StreamAroundTimeoutSeconds + RETURN_PADDING_SECONDS
	local deadline = d.clock() + limit
	while anyInFlight(match) and d.clock() < deadline do
		d.wait(POLL_SECONDS) -- a teleport still in flight must not be left behind in the map
	end
	d.wait(POSITIONING.ReturnFadeSeconds) -- the client's fade, as a duel's return
	local pending = 0
	local slotOf: { [number]: number } = {}
	for _, p in match.list do
		if active(p) then
			pending += 1
			d.spawn(function()
				local ok, err = try(returnOne, match, p, slotOf)
				if not ok then
					log:error(`returning user {p.userId} failed:`, err)
				end
				pending -= 1
			end)
		end
	end
	deadline = d.clock() + limit
	while pending > 0 and d.clock() < deadline do
		d.wait(POLL_SECONDS)
	end
	safeClose(match)
end

local function startReturn(match: Match)
	if match.returning or match.closed then
		return
	end
	match.returning = true
	match.stateDirty = true -- the final view, phase "Returning"
	setPhaseAttributes(match)
	-- Deferred: the effects of the step that closed the match run first (as DuelService.startReturn).
	getDeps().defer(returnPlayers, match)
end

-- A player out of a running match (left, or never arrived): no longer an ultimate caster nor a fighter of the port (no
-- target, recipient or guard), so the lobby and practice treat them as a lobby player again. AbilityService first,
-- as area A asks.
local function releaseParticipant(p: Participant)
	local d = getDeps()
	local okDetach, errDetach = try(d.ability.detachFighter, p.userId)
	if not okDetach then
		log:warn(`detaching user {p.userId} failed:`, errDetach)
	end
	local okRelease, errRelease = try(d.combat.releaseFighter, p.fighter)
	if not okRelease then
		log:warn(`releasing user {p.userId} failed:`, errRelease)
	end
end

-- A player who never arrived (the Countdown started without them): back to the lobby, the lobby unlocked.
local function dropParticipant(match: Match, p: Participant)
	if p.dropped or p.gone then
		return
	end
	p.dropped = true
	if matchOfUser[p.userId] == match then
		matchOfUser[p.userId] = nil
	end
	releaseParticipant(p)
	if p.moved then
		getDeps().spawn(returnOne, match, p, nil)
	else
		restoreMovement(p)
		clearAttributes(p)
	end
	notify(p.ref, CODE.notArrived, nil, "warn")
end

local function onPhase(match: Match, phase: string, startedAt: number)
	match.stateDirty = true
	setPhaseAttributes(match)
	if phase == "Countdown" then
		for _, p in match.list do
			local r = record(match, p)
			if r and not r.present then
				dropParticipant(match, p)
			elseif active(p) then
				freezeMovement(p, false)
			end
		end
	elseif phase == "Active" then
		for _, p in match.list do
			p.fighter.nextThrowAt = startedAt -- as a duel: nextThrowAt = the Active start
			if active(p) and standing(match, p) then
				matchMovement(match, p)
			end
		end
	elseif phase == "Closed" then
		startReturn(match)
	end
end

local function onKo(match: Match, effect: Effect)
	match.stateDirty = true
	local p = match.byUserId[effect.victim]
	if p and active(p) then
		freezeMovement(p, true) -- D3: where it fell, frozen, not turning
	end
end

local function onRespawn(match: Match, effect: Effect)
	match.stateDirty = true
	local p = match.byUserId[effect.userId]
	if p == nil or not active(p) then
		return
	end
	if not pivotTo(match, p, respawnSpotFor(match, p)) then
		replaceParticipant(match, p) -- no character right now: the re-placement places it once it is back
	end
	matchMovement(match, p)
end

local function onOut(match: Match, effect: Effect)
	match.stateDirty = true
	local p = match.byUserId[effect.userId]
	if p and active(p) then
		notify(p.ref, CODE.outNoLives, nil, "warn")
	end
end

-- Power-ups v1.1: a pad was taken (MatchRules accepted the pickup): the picker's toast; everyone's view (the pad).
local function onPickup(match: Match, effect: Effect)
	match.stateDirty = true
	local p = match.byUserId[effect.userId]
	if p and active(p) and type(effect.power) == "string" then
		notify(p.ref, CODE.powerUp .. effect.power, nil, "success")
	end
end

-- Power-ups v1.1: a timed power-up until effect.untilAt: its end is watched (expireBuffs) and a speed / super jump
-- changes the movement now.
local function onBuff(match: Match, effect: Effect)
	match.stateDirty = true
	local untilAt = effect.untilAt
	if type(untilAt) == "number" and untilAt < match.nextBuffAt then
		match.nextBuffAt = untilAt
	end
	local p = match.byUserId[effect.userId]
	if p and (effect.power == "speed" or effect.power == "superJump") then
		refreshMovement(match, p, match.now)
	end
end

-- Power-ups v1.1: the ult charge power-up: `fraction` of the full meter (AbilityService sends UltimateCharge).
local function onUltCharge(match: Match, effect: Effect)
	match.stateDirty = true -- ultReady in the players list may change
	local addCharge = getDeps().ability.addCharge
	if addCharge == nil or type(effect.fraction) ~= "number" then
		return
	end
	local ok, err = try(addCharge, effect.userId, effect.fraction)
	if not ok then
		log:warn(`ult charge for user {effect.userId} failed:`, err)
	end
end

-- D4: the movement guard's out-of-bounds.
local function onOutOfBounds(match: Match, p: Participant)
	if match.closed or match.returning or not active(p) or p.placing or p.positioning then
		return -- a teleport into the map is already on its way
	end
	local root = getDeps().getRoot(p.ref)
	if root and not inMap(match, root.Position) then
		-- Not near this map at all (a new character in the lobby after a death): D5's streamed re-placement, no toast
		-- (an instant pivot into a map the client has not streamed in could drop it through the floor).
		replaceParticipant(match, p)
		return
	end
	if MatchRules.isLive(match.state) then
		-- Out of the void first (a K.O.'d body is frozen where it is), then, with Config.Match.outOfBoundsIsKo
		-- (jayyyyy 2026-10-15: falling off "counts as a knockout"), MatchRules' `oob`: a K.O. with no attacker that
		-- respawns like any K.O. (TDM: costs a team life). Off: just the re-pivot.
		pivotTo(match, p, respawnSpotFor(match, p))
		if cfg().outOfBoundsIsKo then
			notify(p.ref, CODE.outOfBoundsKo, nil, "warn")
			stepMatch(match, { kind = "oob", userId = p.userId })
		else
			notify(p.ref, CODE.outOfBounds, nil, "warn")
		end
	elseif p.spot then
		pivotTo(match, p, p.spot) -- silent before Active (and in Result)
	end
end

local function summaryOf(match: Match, outcome: any): MatchSummary
	local participants = {}
	for _, p in match.list do
		local r = record(match, p)
		table.insert(participants, {
			userId = p.userId,
			team = p.team,
			kos = if r then r.kos else 0,
			knockedOut = if r then r.knockedOut else 0,
			left = p.gone,
		})
	end
	return {
		matchId = match.matchId,
		modeId = match.modeId,
		mapCode = match.map.code,
		outcome = outcome.kind,
		reason = outcome.reason,
		winnerUserId = outcome.winnerUserId,
		winnerTeam = outcome.winnerTeam,
		winners = table.clone(outcome.winners or {}),
		activeSeconds = outcome.activeSeconds or 0,
		participants = participants,
	}
end

-- The TDM team lives right after the K.O. at effects[index] (the next teamLives / out of the victim's team). Match
-- HUD M1: moved above perform, which reads it too (the K.O. event's livesLeft).
local function livesAfter(match: Match, effects: { Effect }, index: number, victim: Participant?): number
	if not match.mode.teams or victim == nil or victim.team == nil then
		return 0
	end
	for i = index + 1, #effects do
		local e = effects[i]
		if e.kind == "teamLives" and e.team == victim.team then
			return e.lives
		elseif e.kind == "out" and e.userId == victim.userId then
			return 0
		elseif e.kind == "ko" then
			break
		end
	end
	return match.state.teamLives[victim.team] or 0
end

-- Match HUD M1: the MatchRules `ko` at effects[index] of the batch being performed becomes a HUD event (the kill feed,
-- M:516: killer, victim, final, score): the attacker's streak +1 (bestStreak its best, M:149, 349, 527), the victim's
-- streak 0 whatever the cause.
local function recordKo(match: Match, effect: Effect, effects: { Effect }, index: number)
	local victim = match.byUserId[effect.victim]
	local by = if effect.by ~= nil then match.byUserId[effect.by] else nil
	if victim then
		victim.streak = 0
	end
	local streak: number? = nil
	if by then
		by.streak += 1
		by.bestStreak = math.max(by.bestStreak, by.streak)
		streak = by.streak
	end
	match.eventSeq += 1
	table.insert(match.events, {
		view = {
			seq = match.eventSeq,
			kind = "ko",
			at = effect.at,
			victim = effect.victim,
			by = effect.by,
			cause = effect.cause,
			final = false,
			streak = streak,
			livesLeft = if match.mode.teams then livesAfter(match, effects, index, victim) else nil,
		},
		step = match.stepId,
	})
end

-- Match HUD M1: a win by koTarget, wiped or overtime was decided by the last K.O. of this batch (M:567-572): it is
-- marked final and kept as outcome.finalKo. Nothing for a wipe by a leave (no K.O. in the batch), a time-up or a draw.
local function markFinalKo(match: Match, outcome: any)
	local reason = outcome.reason
	if outcome.kind ~= "win" or not (reason == "koTarget" or reason == "wiped" or reason == "overtime") then
		return
	end
	for i = #match.events, 1, -1 do
		local event = match.events[i]
		if event.step ~= match.stepId then
			return -- an earlier batch
		elseif event.view.kind == "ko" then
			event.view.final = true
			match.finalKo = event
			return
		end
	end
end

-- Match HUD M2: the pay's collaborators while Config.Match.Rewards is on ([P] off until M9), else nil. Match bots (owner
-- 2026-10-17): bots never block pay; the switch decides for every match.
local function payDeps(_match: Match): RewardDeps?
	local switch = cfg().Rewards
	local on = type(switch) == "table" and switch.enabled == true
	return if on then getDeps().rewards else nil
end

-- Match HUD M2: one profile step of p's result (EconomyService.grantMatchResult: the Coins and the win streak), then
-- SD_WinStreak. nil when the grant failed.
local function grantResult(
	rewards: RewardDeps,
	match: Match,
	p: Participant,
	pay: MatchRewards.Pay
): EconomyService.MatchGrant?
	local ok, grant = try(rewards.grant, p.ref, match.matchId, pay)
	if not ok or type(grant) ~= "table" then
		log:warn(`the match pay of user {p.userId} failed:`, grant)
		return nil
	end
	if grant.recorded then
		setAttribute(p.ref, ATTR_WIN_STREAK, grant.streakAfter)
	end
	return grant
end

-- Match HUD M2 (owner Q3 / Q4): the single end pays every present, real player of a win or a draw like a 1v1 duel
-- (MatchRewards): the Coins and the win streak in one step, then the same squeezes as Grip. A paid player keeps
-- {coins, grip, streakBefore, streakAfter} for their own view (outcome.mine, M:361-363). Called once (onEnded).
-- Review fix (2026-10-16): "present" is MatchRules' (as the outcome and the standings): a player whose /leave came in
-- the very step that ended the match (MatchRules took the end first and ignored the leave) finished it and is paid
-- like everyone present. A grant the profile did not take (not ready, or alreadyGranted) pays no Grip and no mine.
local function payParticipants(match: Match, outcome: any)
	local rewards = payDeps(match)
	if rewards == nil then
		return
	end
	for _, p in match.list do
		local r = record(match, p)
		local pay = if r
			then MatchRewards.forPlayer(outcome, {
				userId = p.userId,
				team = p.team,
				present = r.present,
				isBot = r.isBot,
				throws = p.throws,
			}, rewards.config)
			else nil
		local grant = if pay then grantResult(rewards, match, p, pay) else nil
		if pay and pay.eligible and grant and grant.recorded then
			local grip = 0
			if pay.squeezes > 0 then
				local ok, gained = try(rewards.addGrip, p.ref, pay.squeezes)
				grip = if ok and type(gained) == "number" then gained else 0
			end
			match.rewards[p.userId] = {
				coins = grant.coins,
				grip = grip,
				streakBefore = grant.streakBefore,
				streakAfter = grant.streakAfter,
			}
		end
	end
end

-- Match HUD M2: leaving now costs the win streak (owner Q4 "leaving early"): Countdown, Active or Overtime.
local function streakAtStake(match: Match): boolean
	local state = match.state
	return not state.ended and (state.phase == "Countdown" or MatchRules.isLive(state))
end

-- Match HUD M2: a player who left a live match: the win streak -> 0 through the same profile step, nothing paid.
-- Review fix (2026-10-16): only when MatchRules took the leave (`left`). When the leave's own step ended the match
-- first (a time-up due within the frame, or a K.O. its projectile sweep brought in), MatchRules ignored the leave: the
-- player was present at the end, payParticipants paid their result, and their streak follows it.
local function resetLeaverStreak(match: Match, p: Participant)
	local r = record(match, p)
	local rewards = payDeps(match)
	if rewards and r and r.left then
		grantResult(rewards, match, p, MatchRewards.left())
	end
end

-- The single end (MatchRules `ended`): the toasts and MatchEnded. Exactly once. Match HUD M1: the final K.O. and the
-- standings, kept for every later view. Match HUD M2: the pay (payParticipants, before the view that shows it).
local function onEnded(match: Match, outcome: any)
	if match.endedFired then
		return
	end
	match.endedFired = true
	match.stateDirty = true
	markFinalKo(match, outcome)
	match.standings = standingsView(match)
	payParticipants(match, outcome)
	local winner = if outcome.winnerUserId then match.byUserId[outcome.winnerUserId] else nil
	for _, p in match.list do
		if active(p) then
			if outcome.kind == "win" and winner == p then
				notify(p.ref, CODE.youWin, nil, "success")
			elseif outcome.kind == "win" and winner then
				notify(p.ref, CODE.winner, { name = winner.displayName }, "info")
			elseif outcome.kind == "win" and outcome.winnerTeam then
				local kind: Types.NotifyKind = if p.team == outcome.winnerTeam then "success" else "info"
				notify(p.ref, CODE.teamWins, { team = teamName(outcome.winnerTeam) }, kind)
			elseif outcome.kind == "draw" then
				notify(p.ref, CODE.draw, nil, "info")
			elseif outcome.kind == "cancelled" then
				notify(p.ref, CODE.cancelled, nil, "warn")
			elseif outcome.reason == "error" then
				notify(p.ref, CODE.voidError, nil, "warn") -- a void after a failure: the server is not shutting down
			else
				notify(p.ref, CODE.void, nil, "warn")
			end
			-- qb1 (owner 2026-10-16 "Same as a duel, no limit"): what the end paid, until M9's results bar shows it.
			local paid = match.rewards[p.userId]
			if paid and (paid.coins > 0 or paid.grip > 0) then
				local args: Types.NotifyArgs = { coins = Format.coins(paid.coins), grip = Format.coins(paid.grip) }
				notify(p.ref, CODE.paid, args, "success")
			end
		end
	end
	-- No quests, weekly wins or badges for a match yet (the pay is payParticipants', above).
	local summary = summaryOf(match, outcome)
	log:info(
		string.format(
			"match %s (%s on %s) ended outcome=%s reason=%s active=%.1fs winner=%s team=%s",
			match.matchId,
			match.modeId,
			match.map.code,
			tostring(outcome.kind),
			tostring(outcome.reason),
			summary.activeSeconds,
			tostring(outcome.winnerUserId or "-"),
			tostring(outcome.winnerTeam or "-")
		)
	)
	MatchService.MatchEnded:fire(summary)
end

-- Match HUD M1: `effects` = the batch being performed and `index` = this effect's place in it (the K.O.'s team lives).
perform = function(match: Match, effect: Effect, effects: { Effect }, index: number)
	local kind = effect.kind
	if kind == "phase" then
		onPhase(match, effect.phase, effect.startedAt or getDeps().now())
	elseif kind == "ended" then
		if effect.outcome then
			onEnded(match, effect.outcome)
		end
	elseif kind == "ko" then
		recordKo(match, effect, effects, index)
		onKo(match, effect)
	elseif kind == "respawn" then
		onRespawn(match, effect)
	elseif kind == "out" then
		onOut(match, effect)
	elseif kind == "closed" then
		startReturn(match)
	elseif kind == "pickup" then
		onPickup(match, effect)
	elseif kind == "buff" then
		onBuff(match, effect)
	elseif kind == "ultCharge" then
		onUltCharge(match, effect)
	else
		-- teamLives, and power-ups v1.1's revived (its respawn effect places the player) and shieldBlocked (the shield is
		-- used up): the views carry them.
		match.stateDirty = true
	end
end

local function participantOfFighter(match: Match, fighter: Fighter): Participant?
	local p = match.byUserId[fighter.userId]
	return if p and p.fighter == fighter then p else nil
end

local function buildPort(match: Match): MatchPort
	local map = match.map
	local fighters: { Fighter } = {}
	for _, p in match.list do
		table.insert(fighters, p.fighter)
	end
	local port: MatchPort = {
		matchId = match.matchId,
		ffa = true,
		teams = match.mode.teams == true,
		arena = {
			slot = 0,
			floorY = map.floorY,
			killY = map.floorY + RULES.OutOfBounds.KillYOffset,
			zones = { Bounds = map.bounds },
			geometry = map.model,
			raycastParams = map.raycastParams,
			overlapParams = map.overlapParams,
		},
		fighters = fighters,
		phase = function(): string
			return wirePhaseOf(match)
		end,
		-- D1: 1. Power-ups v1.1: CombatService hands the thrower; its live rapid throw gives the shortest cooldown
		-- (throwCooldownMultiplier).
		cooldownMultiplier = function(fighter: Fighter?): number
			local p = if fighter then participantOfFighter(match, fighter) else nil
			return if p and fighter then throwCooldownMultiplier(match, p, fighter, getDeps().now()) else 1
		end,
		-- Power-ups v1.1: the throw boost (× the launch speed), the dash boost and the buffed standing movement.
		throwSpeedMultiplier = function(fighter: Fighter): number
			local p = participantOfFighter(match, fighter)
			return if p then buffNumber(match, p, "throwBoost", "speedMultiplier", getDeps().now(), 1) else 1
		end,
		dashCooldownFree = function(fighter: Fighter): boolean
			local p = participantOfFighter(match, fighter)
			return p ~= nil and MatchRules.hasBuff(match.state, p.userId, "dashBoost", getDeps().now())
		end,
		movement = function(fighter: Fighter): (number, number)
			local p = participantOfFighter(match, fighter)
			if p == nil or not active(p) or match.returning or match.closed then
				-- (AbilityService's detach un-roots a caster who is leaving or already back in the lobby: no boost there)
				return MOVEMENT.WalkSpeed, MOVEMENT.JumpHeight
			end
			return buffedMovement(match, p, getDeps().now())
		end,
		placement = function(fighter: Fighter): CFrame?
			local p = participantOfFighter(match, fighter)
			local spot = if p then p.spot else nil
			if p == nil or spot == nil then
				return nil
			end
			return spotCFrame(p, spot)
		end,
		canBeHit = function(victim: Fighter, at: number, attacker: Fighter?): boolean
			local byId = if attacker then attacker.userId else nil
			return not match.closed and MatchRules.canBeHit(match.state, victim.userId, at, byId)
		end,
		applyHits = function(hits: { CombatService.HitRequest }, now: number): { [number]: CombatService.HitOutcome }
			local outcomes: { [number]: CombatService.HitOutcome } = {}
			if match.closed then
				return outcomes
			end
			local list = {}
			for index, hit in hits do
				list[index] = { victim = hit.victim.userId, by = hit.attacker.userId, at = hit.at }
			end
			-- `now` = the time the projectiles were swept to: the timers never run past what was simulated.
			local state, effects = MatchRules.step(match.state, { kind = "hits", hits = list }, now)
			match.state = state
			match.now = math.max(match.now, now)
			syncFighters(match)
			local used: { [number]: boolean } = {}
			-- The first unused hit of `victimId` by `byId` at `at` (MatchRules clamps impact times to `now`).
			local function claim(victimId: number, byId: number, at: number): number?
				for index, hit in hits do
					if
						not used[index]
						and hit.victim.userId == victimId
						and hit.attacker.userId == byId
						and math.min(hit.at, now) == at
					then
						used[index] = true
						return index
					end
				end
				return nil
			end
			for i, effect in effects do
				if effect.kind == "ko" and effect.by ~= nil then
					local index = claim(effect.victim, effect.by, effect.at)
					if index then
						outcomes[index] = {
							lives = livesAfter(match, effects, i, match.byUserId[effect.victim]),
							invulnUntil = effect.at,
							eliminated = true,
						}
					end
				elseif effect.kind == "shieldBlocked" then
					-- Power-ups v1.1: the shield took it. An applied, blocked outcome, so CombatService ends the throw at
					-- the shield (no K.O.) instead of letting it fly on into the unshielded player a step later.
					local index = claim(effect.userId, effect.by, effect.at)
					if index then
						local victim = match.byUserId[effect.userId]
						local team = if victim then victim.team else nil
						outcomes[index] = {
							lives = if match.mode.teams and team then match.state.teamLives[team] or 0 else 0,
							invulnUntil = effect.at,
							eliminated = false,
							blocked = true,
						}
					end
				end
				table.insert(match.pending, effect)
			end
			return outcomes
		end,
		flush = function()
			local effects = match.pending
			match.pending = {}
			match.stepId += 1 -- Match HUD M1: a batch of its own
			for index, effect in effects do
				perform(match, effect, effects, index)
			end
			if match.stateDirty and not match.closed then
				match.stateDirty = false
				sendState(match)
			end
		end,
		throwAccepted = function(fighter: Fighter)
			local p = participantOfFighter(match, fighter)
			if p then
				p.throws += 1
			end
		end,
		outOfBounds = function(fighter: Fighter)
			local p = participantOfFighter(match, fighter)
			if p then
				onOutOfBounds(match, p)
			end
		end,
		sync = function(now: number)
			stepMatch(match, { kind = "tick" }, now)
		end,
	}
	return port
end

-- The squishy a player (or bot) plays: the equipped one when valid, else the starter.
local function squishyOf(ref: any): string
	local id = if isBotRef(ref) then ref.squishyId else getDeps().equipped(ref) -- match bots: their own random squishy
	return if Catalog.isValidId(id) then id :: string else Catalog.starterId()
end

local function displayNameOf(ref: any, userId: number): string
	return if type(ref.DisplayName) == "string" then ref.DisplayName else tostring(userId)
end

local function newParticipant(match: Match, ref: any, team: string?, now: number): Participant
	local d = getDeps()
	local userId = userIdOf(ref) :: number
	local squishyId = squishyOf(ref)
	local side: Types.Side = "A"
	if team ~= nil and team == cfg().teamNames[2] then
		side = SIDES[2]
	end
	local p: Participant
	local fighter = d.combat.newFighter({
		userId = userId,
		player = if typeof(ref) == "Instance" then ref else nil,
		isTestDummy = false,
		side = side,
		squishyId = squishyId,
		getRoot = function(): BasePart?
			return d.getRoot(ref)
		end,
		isAlive = function(): boolean
			-- D3: a K.O.'d (or left) player can't throw, dash, jump or cast, is never hit and is left alone by the guard.
			return d.isAlive(ref) and p ~= nil and active(p) and standing(match, p)
		end,
		now = now,
	})
	p = {
		ref = ref,
		userId = userId,
		displayName = displayNameOf(ref, userId),
		squishyId = squishyId,
		team = team,
		side = side,
		fighter = fighter,
		spot = nil,
		moved = false,
		positioning = false,
		placing = false,
		dropped = false,
		gone = false,
		savedMovement = nil,
		throws = 0,
		sentStormBar = 0,
		buffsCheckedAt = -math.huge,
		streak = 0, -- Match HUD M1
		bestStreak = 0,
	}
	return p
end

-- Power-ups v1.1: the match's own pads (every one ready), from the map record's power-up pads (none in an older record).
local function padsOf(map: MapRecord): { MatchPad }
	local list: { MatchPad } = {}
	for _, pad in map.powerUps or {} do
		table.insert(list, { name = pad.name, position = pad.position, top = pad.top, pad = PowerUpRules.newPad() })
	end
	return list
end

-- D5 backstop: a character of a moved, active player alive outside the map is re-placed. Not once the match has ended
-- (Result): the return is seconds away, and it leaves a character already in the lobby there.
local function checkPresence(match: Match)
	if match.returning or match.closed or match.state.ended then
		return
	end
	local d = getDeps()
	for _, p in match.list do
		if p.moved and active(p) and not p.placing and not p.positioning then
			local root = d.getRoot(p.ref)
			if root and d.isAlive(p.ref) and not inMap(match, root.Position) then
				log:info(`user {p.userId} is outside the map of {match.matchId}; placing them back`)
				replaceParticipant(match, p)
			end
		end
	end
end

-- D11 (TDM): who stands in the storm, sampleHz times a second; then each player's own storm bar if it moved. Only a
-- live character standing in this map counts: a corpse (the Humanoid died: Reset, a fall) or a new character still in
-- the lobby, or one being teleported in, is not "in the storm", so its bar drains (D5: a death costs no K.O.).
local function sampleStorm(match: Match, now: number)
	if not match.mode.storm or match.returning or not MatchRules.isLive(match.state) or now < match.nextStormAt then
		return
	end
	local d = getDeps()
	local storm = cfg().Storm
	match.nextStormAt = now + 1 / storm.sampleHz
	local t = MatchRules.activeSeconds(match.state, now)
	if not StormMath.shown(storm, t) then
		return
	end
	local radius = StormMath.radiusAt(storm, match.map.startRadius, t)
	local centre = stormCentre(match)
	local inStorm: { [number]: boolean } = {}
	for _, p in match.list do
		if active(p) and standing(match, p) and not p.placing and not p.positioning and d.isAlive(p.ref) then
			local root = d.getRoot(p.ref)
			local position = if root then root.Position else nil
			if position and inMap(match, position) and StormMath.inStorm(centre, radius, position) then
				inStorm[p.userId] = true
			end
		end
	end
	stepMatch(match, { kind = "storm", inStorm = inStorm }, now)
	if match.closed then
		return
	end
	local changed: { Participant } = {}
	for _, p in match.list do
		local r = record(match, p)
		if active(p) and r and r.stormBar ~= p.sentStormBar and not isBotRef(p.ref) then
			table.insert(changed, p)
		end
	end
	if #changed > 0 then
		sendState(match, changed)
	end
end

-- Power-ups v1.1: who takes `entry` now: the nearest eligible player in reach (see samplePads), or nil.
local function padTaker(
	match: Match,
	entry: MatchPad,
	took: { [Participant]: boolean },
	radius: number,
	height: number
): Participant?
	local d = getDeps()
	local best: Participant? = nil
	local bestDistance = math.huge
	for _, p in match.list do
		if
			not took[p]
			and active(p)
			and standing(match, p)
			and not p.placing
			and not p.positioning
			and d.isAlive(p.ref)
		then
			local root = d.getRoot(p.ref)
			local position = if root then root.Position else nil
			if position then
				local dx, dz = position.X - entry.position.X, position.Z - entry.position.Z
				local flat = math.sqrt(dx * dx + dz * dz)
				local rise = math.abs(position.Y - (entry.top + standHeight(p)))
				if flat <= radius and rise <= height and flat < bestDistance then
					best, bestDistance = p, flat
				end
			end
		end
	end
	return best
end

-- Power-ups v1.1 (P1): who takes a pad, Config.Match.Storm.sampleHz times a second while the match is live (both
-- modes). A ready pad goes to the nearest standing, present player (a live character in the map, no teleport in
-- flight) within PowerUps.pickupRadiusStuds of its centre and pickupHeightStuds of standing height on its top; one
-- pickup per player per sample. PowerUpRules.take refills it padRefillSeconds later, PowerUpRules.roll picks the kind
-- with the server's Random and MatchRules `pickup` does the rest (perform: the toast, the buff, the ult charge).
-- Review fix (2026-10-16): before the first pad is taken the match is brought up to `now` (a tick step: the projectiles
-- swept to now, the timers run), then the taker is chosen again. A hit that K.O.s the taker, or the time-up, lands
-- first, so MatchRules always accepts the pickup and a pad is never used up with nobody getting it.
local function samplePads(match: Match, now: number)
	if #match.pads == 0 or match.returning or not MatchRules.isLive(match.state) or now < match.nextPadAt then
		return
	end
	local d = getDeps()
	local c = cfg()
	local pu = c.PowerUps
	match.nextPadAt = now + 1 / c.Storm.sampleHz
	local radius, height = pu.pickupRadiusStuds, pu.pickupHeightStuds
	if type(radius) ~= "number" or type(height) ~= "number" then
		return -- an older Config without the pickup reach: the pads stay idle
	end
	local took: { [Participant]: boolean } = {}
	local synced = false
	for _, entry in match.pads do
		if PowerUpRules.isReady(entry.pad, now) then
			local best = padTaker(match, entry, took, radius, height)
			if best and not synced then
				synced = true
				stepMatch(match, { kind = "tick" }, now)
				if match.closed or match.returning or not MatchRules.isLive(match.state) then
					return
				end
				best = padTaker(match, entry, took, radius, height)
			end
			if best then
				local taken, pad = PowerUpRules.take(entry.pad, now, c)
				if taken then
					entry.pad = pad
					took[best] = true
					match.stateDirty = true -- everyone sees the pad go (its readyAt)
					local power = PowerUpRules.roll(match.modeId, d.rng:NextNumber(), c)
					stepMatch(match, { kind = "pickup", userId = best.userId, power = power }, now)
					if match.closed or not MatchRules.isLive(match.state) then
						return
					end
				end
			end
		end
	end
end

-- Power-ups v1.1: when a timed power-up ends (MatchRules keeps only its end time; no effect fires) the player's
-- movement goes back (speed, super jump) and their own view drops it. Runs when the earliest end is due.
local function expireBuffs(match: Match, now: number)
	if now < match.nextBuffAt or match.closed then
		return
	end
	local nextAt = math.huge
	local changed: { Participant } = {}
	for _, p in match.list do
		local r = record(match, p)
		if r and active(p) then
			local ended = false
			for _, untilAt in r.buffs do
				if type(untilAt) == "number" then
					if untilAt <= now then
						ended = ended or untilAt > p.buffsCheckedAt
					elseif untilAt < nextAt then
						nextAt = untilAt
					end
				end
			end
			p.buffsCheckedAt = now
			if ended then
				table.insert(changed, p)
				refreshMovement(match, p, now)
			end
		end
	end
	match.nextBuffAt = nextAt
	if #changed > 0 then
		sendState(match, changed)
	end
end

-- When MatchRules next has a timer due: the phase end or the earliest respawn (MatchRules' advance() runs nothing
-- else; arrivals, hits, the storm and leaves are events of their own).
local function nextDueAt(state: MatchState): number
	local due = state.phaseEndsAt
	for _, r in state.participants do
		local at = r.respawnAt
		if r.present and at ~= nil and at < due then
			due = at
		end
	end
	return due
end

-- Match bots: a real player is still in the match (not left, not dropped).
local function hasRealPlayer(match: Match): boolean
	for _, p in match.list do
		if active(p) and not isBotRef(p.ref) then
			return true
		end
	end
	return false
end

local function tickMatch(match: Match, now: number)
	if match.closed then
		return
	end
	match.now = math.max(match.now, now)
	if match.bots > 0 and not match.state.ended and not hasRealPlayer(match) then
		stepMatch(match, { kind = "empty" }, now) -- match bots: nobody real is left to play with them
		return
	end
	checkPresence(match)
	sampleStorm(match, now)
	if not match.closed then
		samplePads(match, now) -- power-ups v1.1
	end
	if not match.closed then
		expireBuffs(match, now) -- power-ups v1.1
	end
	if not match.closed and now >= nextDueAt(match.state) then
		-- Only when a timer is due: no projectile sweep (syncTo) or state copy every Heartbeat for nothing. port.sync
		-- and the hits still bring the match up to date whenever combat asks.
		stepMatch(match, { kind = "tick" }, now)
	end
end

local function tickMatches(now: number)
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
	if heartbeat == nil and getDeps().heartbeat then
		heartbeat = RunService.Heartbeat:Connect(function()
			local now = getDeps().now()
			Pend.tick(now) -- round 3 of the match flow: the map votes
			tickMatches(now)
		end)
	end
end

-- The longest a match may still take from `now` (overtime and Result included), for RestartScheduled.
local function maxRemaining(match: Match, now: number): number
	local c = cfg()
	local state = match.state
	local left = math.max(0, finiteOrZero(state.phaseEndsAt) - now)
	local phase = state.phase
	if phase == "Waiting" then
		return left + c.countdownSeconds + match.mode.matchSeconds + c.overtimeMaxSeconds + c.resultSeconds
	elseif phase == "Countdown" then
		return left + match.mode.matchSeconds + c.overtimeMaxSeconds + c.resultSeconds
	elseif phase == "Active" then
		return left + c.overtimeMaxSeconds + c.resultSeconds
	elseif phase == "Overtime" then
		return left + c.resultSeconds
	end
	return left
end

local function participantOf(ref: any): (Match?, Participant?)
	local userId = userIdOf(ref)
	local match = if userId then matchOfUser[userId] else nil
	if match == nil or match.closed or userId == nil then
		return nil, nil
	end
	local p = match.byUserId[userId]
	if p == nil or not active(p) then
		return nil, nil
	end
	return match, p
end

-- Private: queues --------------------------------------------------------------------------------------------------------

local function ticketOf(ref: any): (string?, number?)
	for modeId, queue in queues do
		for index, ticket in queue do
			if ticket.player == ref then
				return modeId, index
			end
		end
	end
	return nil, nil
end

local function queueOf(modeId: string): { Ticket }
	local queue = queues[modeId]
	if queue == nil then
		queue = {}
		queues[modeId] = queue
	end
	return queue
end

local function newMatchId(): string
	return MATCH_ID_PREFIX .. HttpService:GenerateGUID(false)
end

local function notifyQueue(modeId: string, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
	for _, ticket in queueOf(modeId) do
		notify(ticket.player, code, args, kind)
	end
end

-- Round 1 of the match flow (2026-10-25, Diego's waiting bar): a player's MatchQueue view ({} = no ticket).
local function sendQueue(ref: any, view: Types.MatchQueueView)
	local d = getDeps()
	if not d.isPlayer(ref) then
		return
	end
	local ok, err = try(d.fire, REMOTE_QUEUE, ref, view)
	if not ok then
		log:warn(`MatchQueue to user {userIdOf(ref)} failed:`, err)
	end
end

-- Round 2 of the match flow (2026-10-25): the lobby's MATCH FOUND show (MatchFound, Logic/MatchFoundRoster) for every
-- player of a match (round 3: a map vote) the queue just started: each one's name, squishy, Grip level and team (1 / 2
-- in Team Deathmatch). `refs`: the players, then the bots; `teams`: ref -> team.
local function sendFound(modeId: string, refs: { any }, teams: { [any]: string })
	local d = getDeps()
	local entries: { MatchFoundRoster.Entry } = {}
	for _, ref in refs do
		local userId = userIdOf(ref) :: number
		local level: number? = nil
		if d.gripLevel and not isBotRef(ref) then
			local ok, value = try(d.gripLevel, ref)
			level = if ok and type(value) == "number" then value else nil
		end
		local team = teams[ref]
		table.insert(entries, {
			userId = userId,
			name = displayNameOf(ref, userId),
			squishy = squishyOf(ref),
			level = level,
			team = if team then table.find(cfg().teamNames, team) else nil,
		})
	end
	local view = MatchFoundRoster.build(modeId :: any, entries, d.rng)
	for _, ref in refs do
		if d.isPlayer(ref) then
			local ok, err = try(d.fire, REMOTE_FOUND, ref, view)
			if not ok then
				log:warn(`MatchFound to user {userIdOf(ref)} failed:`, err)
			end
		end
	end
end

-- Every ticket of `modeId` gets the queue as it is now (the count is at most the mode's maxPlayers).
local function syncQueue(modeId: string)
	local max = cfg().Modes[modeId].maxPlayers
	local queue = queueOf(modeId)
	local count = math.min(#queue, max)
	for _, ticket in queue do
		sendQueue(ticket.player, { mode = modeId :: any, count = count, max = max, joinedAt = ticket.joinedAt })
	end
end

-- Removes the player's ticket (with `code` when given). True when there was one. The player's waiting bar clears and
-- the rest of the queue gets the new count, unless `entered` (the ticket became a match: startFromQueue sent its
-- full view and {} and syncs the rest once).
local function dropTicket(ref: any, code: string?, entered: boolean?): boolean
	local modeId, index = ticketOf(ref)
	if modeId == nil or index == nil then
		return false
	end
	table.remove(queueOf(modeId), index)
	if code ~= nil then
		notify(ref, code, { mode = modeName(modeId) }, "info")
	end
	if not entered then
		sendQueue(ref, {})
		syncQueue(modeId)
	end
	return true
end

local function clearQueues(code: string?)
	for modeId, queue in queues do
		for _, ticket in queue do
			if code ~= nil then
				notify(ticket.player, code, { mode = modeName(modeId) }, "warn")
			end
			sendQueue(ticket.player, {})
		end
		queues[modeId] = {}
		gathers[modeId] = nil
	end
end

-- Why `ref` may not join a match queue now (nil = it may).
local function refusalOf(ref: any, modeId: string): string?
	local d = getDeps()
	if d.closing() or d.restartPending() then
		return CODE.closing
	elseif ticketOf(ref) ~= nil then
		return CODE.alreadyQueued
	elseif inAnyMatch(ref) then
		return CODE.inMatch
	elseif d.queueState(ref) ~= "Idle" then
		return CODE.duelQueue
	elseif d.isPracticing(ref) then
		return CODE.practice
	elseif not d.maps.hasMode(modeId) then
		return CODE.noMaps
	end
	return nil
end

-- Tickets whose player can't start any more (left the game, now in a duel or the duel queue) go silently.
local function pruneQueue(modeId: string)
	local d = getDeps()
	local queue = queueOf(modeId)
	local pruned = false
	for index = #queue, 1, -1 do
		local ref = queue[index].player
		if not d.isPlayer(ref) or inAnyMatch(ref) or d.queueState(ref) ~= "Idle" then
			table.remove(queue, index)
			sendQueue(ref, {}) -- sendQueue skips a player who left the game
			pruned = true
		end
	end
	if pruned then
		syncQueue(modeId)
	end
end

-- Match bots: whether deps.bots can give bots now.
local function botsReady(): boolean
	local bots = getDeps().bots
	if bots == nil then
		return false
	end
	local ok, ready = try(bots.ready)
	return ok and ready == true
end

-- Match bots: up to `count` bots from deps.bots now (none without it).
local function takeBots(modeId: string, count: number): { any }
	local bots = getDeps().bots
	if bots == nil or count <= 0 or not botsReady() then
		return {}
	end
	local ok, list = try(bots.take, modeId, count)
	if not ok or type(list) ~= "table" then
		log:warn(`taking match bots failed:`, list)
		return {}
	end
	return list
end

-- Match bots: the taken bots that are in no match go back.
local function releaseBots(list: { any })
	local bots = getDeps().bots
	for _, bot in list do
		if bots and not inAnyMatch(bot) then
			try(bots.release, bot)
		end
	end
end

local function startFromQueue(modeId: string, now: number, gather: Gather)
	local d = getDeps()
	local mode = cfg().Modes[modeId]
	local queue = queueOf(modeId)
	local refs: { any } = {}
	for index = 1, math.min(#queue, mode.maxPlayers) do
		table.insert(refs, queue[index].player)
	end
	local matchId = newMatchId()
	-- Round 3 of the match flow: the map vote's cards, up to Vote.maxChoices free maps (one without the vote).
	local vote = cfg().Vote
	local maps: { MapRecord } = {}
	for _ = 1, if vote.enabled then vote.maxChoices else 1 do
		local map = d.maps.acquire(modeId, matchId)
		if map == nil then
			break
		end
		table.insert(maps, map)
	end
	if #maps == 0 then
		if not gather.waitingMapSent then
			gather.waitingMapSent = true
			notifyQueue(modeId, CODE.waitingMap, { mode = modeName(modeId) }, "info")
		end
		return
	end
	-- Match bots: the empty slots, up to maxPlayers (taken now, no yield; startMatch / Pend.start follows at once).
	local bots = takeBots(modeId, mode.maxPlayers - #refs)
	table.move(bots, 1, #bots, #refs + 1, refs)
	local started, why
	if vote.enabled then
		started, why = Pend.start(modeId, matchId, refs, maps, now)
	else
		started, why = MatchService.startMatch(refs, modeId, maps[1], matchId)
	end
	releaseBots(bots) -- the ones it did not take
	if started == nil then
		for _, map in maps do
			try(d.maps.release, map)
		end
		log:warn(`could not start {modeId} from the queue: {tostring(why)}`)
		gather.endsAt = now + cfg().gatherSeconds -- try again after another gather, not every tick
		return
	end
	for _, ref in refs do
		if inAnyMatch(ref) then
			-- In the match now (a ticket startMatch skipped stays queued): the bar fills up (the full view), then the
			-- ticket is gone ({}, so the bar never comes back after the match).
			local _, index = ticketOf(ref)
			local ticket = if index then queue[index] else nil
			if ticket then
				sendQueue(ref, {
					mode = modeId :: any,
					count = #refs,
					max = mode.maxPlayers,
					joinedAt = ticket.joinedAt,
					full = true,
				})
				sendQueue(ref, {})
			end
			dropTicket(ref, nil, true)
		end
	end
	gathers[modeId] = nil
	syncQueue(modeId) -- whoever did not fit keeps waiting
	local pending = pendings[started]
	local match = matches[started]
	if pending then
		sendFound(modeId, pending.refs, pending.teams)
		Pend.send(pending) -- round 3: the vote's first view
	elseif match then
		local list, teams = {}, {}
		for _, p in match.list do
			table.insert(list, p.ref)
			teams[p.ref] = p.team
		end
		sendFound(modeId, list, teams)
	end
end

local function tickQueue(modeId: string, now: number)
	local d = getDeps()
	local c = cfg()
	local mode = c.Modes[modeId]
	if mode == nil then
		return
	end
	pruneQueue(modeId)
	local queue = queueOf(modeId)
	local gather = gathers[modeId]
	-- Match bots: while they can fill it, one queued player is enough.
	if #queue < (if botsReady() then 1 else c.minPlayers) then
		if gather ~= nil then
			gathers[modeId] = nil
			notifyQueue(modeId, CODE.waitingPlayers, { mode = modeName(modeId) }, "info")
		end
		return
	end
	local full = #queue >= mode.maxPlayers or #queue >= d.playerCount()
	if gather == nil then
		gather = { endsAt = now + c.gatherSeconds, waitingMapSent = false }
		gathers[modeId] = gather
		if not full then
			notifyQueue(modeId, CODE.startingIn, { mode = modeName(modeId), seconds = c.gatherSeconds }, "info")
		end
	end
	if full or now >= gather.endsAt then
		startFromQueue(modeId, now, gather)
	end
end

local function tickQueues(now: number)
	for modeId in cfg().Modes do
		local ok, err = try(tickQueue, modeId, now)
		if not ok then
			log:error(`queue {modeId} tick failed:`, err)
		end
	end
end

local function shuffle(list: { any }, rng: Random)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

-- Private: the map vote (round 3 of the match flow, see the header) -----------------------------------------------------

-- Who of `refs` may play a new match of `mode`: real players and match bots, once each, in no match, up to maxPlayers
-- (the bots kept apart, after the players).
function Pend.entrants(refs: { any }, mode: any): ({ any }, { any })
	local d = getDeps()
	local list: { any } = {}
	local bots: { any } = {}
	local seen: { [number]: boolean } = {}
	for _, ref in refs do
		local userId = userIdOf(ref)
		if
			userId ~= nil
			and not seen[userId]
			and (d.isPlayer(ref) or isBotRef(ref))
			and not inAnyMatch(ref)
			and #list + #bots < mode.maxPlayers
		then
			seen[userId] = true
			table.insert(if isBotRef(ref) then bots else list, ref)
		end
	end
	return list, bots
end

-- TDM: the players shuffled, then Red, Blue, Red, ... (friends together: later), then each bot to the smaller team
-- (MatchBotRules.dealTeams). Returns the players then the bots, and ref -> team (empty outside TDM).
function Pend.deal(list: { any }, bots: { any }, mode: any): ({ any }, { [any]: string })
	local teams: { [any]: string } = {}
	if mode.teams then
		shuffle(list, getDeps().rng)
	end
	local humans = #list
	table.move(bots, 1, #bots, humans + 1, list)
	if mode.teams then
		for index, team in MatchBotRules.dealTeams(humans, #bots, cfg().teamNames) do
			teams[list[index]] = team
		end
	end
	return list, teams
end

-- The players still in `pending` (its bots get nothing).
function Pend.humans(pending: Pending): { any }
	local out: { any } = {}
	for _, ref in pending.refs do
		if not isBotRef(ref) and pendingOfUser[userIdOf(ref) :: number] == pending then
			table.insert(out, ref)
		end
	end
	return out
end

function Pend.sendTo(ref: any, view: Types.MatchVoteView)
	local d = getDeps()
	if not d.isPlayer(ref) then
		return
	end
	local ok, err = try(d.fire, REMOTE_VOTE_STATE, ref, view)
	if not ok then
		log:warn(`MatchVoteState to user {userIdOf(ref)} failed:`, err)
	end
end

-- Everyone still in `pending` gets its view.
function Pend.send(pending: Pending)
	local maps: { string } = {}
	local votes: { { number } } = {}
	for index, map in pending.maps do
		maps[index] = map.name
		votes[index] = table.clone(pending.votes[index])
	end
	local view: Types.MatchVoteView = {
		id = pending.id,
		mode = pending.modeId :: any,
		maps = maps,
		opensAt = pending.opensAt,
		closesAt = pending.closesAt,
		votes = votes,
		result = pending.result,
	}
	for _, ref in Pend.humans(pending) do
		Pend.sendTo(ref, view)
	end
end

-- The queue's players and bots (`refs`, on `maps`, acquired under `id`) become a vote: the teams dealt, the cards in
-- Vote.mapOrder, the bots' vote times drawn, the players held (SD_MatchId = id). Returns (id, nil) or (nil, why).
function Pend.start(modeId: string, id: string, refs: { any }, maps: { MapRecord }, now: number): (string?, string?)
	local d = getDeps()
	local c = cfg()
	local mode = c.Modes[modeId]
	if d.closing() then
		return nil, "closing"
	end
	local list, bots = Pend.entrants(refs, mode)
	if #list + #bots < c.minPlayers or #list == 0 then
		return nil, "notEnoughPlayers" -- (bots alone never play)
	end
	local players = #list
	local ordered, teams = Pend.deal(list, bots, mode)
	local vote = c.Vote
	local order = vote.mapOrder
	table.sort(maps, function(a: MapRecord, b: MapRecord): boolean
		local ra, rb = table.find(order, a.name) or math.huge, table.find(order, b.name) or math.huge
		if ra ~= rb then
			return ra < rb
		end
		return a.name < b.name
	end)
	local opensAt = now + vote.introSeconds
	local pending: Pending = {
		id = id,
		modeId = modeId,
		refs = ordered,
		teams = teams,
		bots = bots,
		maps = maps,
		votes = {},
		opensAt = opensAt,
		closesAt = opensAt + vote.seconds,
		botAt = {},
		lastVoteAt = {},
		result = nil,
	}
	for index in maps do
		pending.votes[index] = {}
	end
	for index, at in MatchVote.botTimes(#bots, vote.seconds * 1000, d.rng, vote) do
		pending.botAt[index] = if at == false then false else opensAt + at / 1000
	end
	if #maps < 2 then
		Pend.decide(pending, opensAt) -- a single free map: chosen as the cards open
	end
	pendings[id] = pending
	for index, ref in ordered do
		pendingOfUser[userIdOf(ref) :: number] = pending
		if index <= players then
			setAttribute(ref, ATTR_MATCH_ID, id)
		end
	end
	ensureHeartbeat()
	log:info(`vote {id} started: {modeId} on {#maps} maps with {#ordered} players`)
	return id, nil
end

-- The result now (Logic/MatchVote), its times on the server clock.
function Pend.decide(pending: Pending, now: number)
	local vote = cfg().Vote
	local r = MatchVote.result(pending.votes, #pending.maps, getDeps().rng, vote)
	local roulette: { { choice: number, at: number } } = {}
	for _, step in r.roulette do
		table.insert(roulette, { choice = step.choice, at = now + step.atMs / 1000 })
	end
	local revealAt = now + r.revealMs / 1000
	pending.result = {
		winner = r.winner,
		kind = r.kind,
		roulette = roulette,
		at = now,
		revealAt = revealAt,
		startsAt = revealAt + vote.startAfterRevealSeconds,
	}
end

-- Ends `pending` (its players and bots are in no vote any more, SD_MatchId ""). Returns its players.
function Pend.forget(pending: Pending): { any }
	local humans = Pend.humans(pending)
	pendings[pending.id] = nil
	for _, ref in pending.refs do
		local userId = userIdOf(ref) :: number
		if pendingOfUser[userId] == pending then
			pendingOfUser[userId] = nil
		end
	end
	for _, ref in humans do
		setAttribute(ref, ATTR_MATCH_ID, "")
	end
	return humans
end

-- Called off: the maps and the bots go back; its players get {} (and the `code` toast).
function Pend.cancel(pending: Pending, code: string?)
	local d = getDeps()
	for _, ref in Pend.forget(pending) do
		Pend.sendTo(ref, {})
		if code ~= nil then
			notify(ref, code, nil, "warn")
		end
	end
	for _, map in pending.maps do
		try(d.maps.release, map)
	end
	releaseBots(pending.bots)
end

function Pend.cancelAll(code: string?)
	for _, pending in table.clone(pendings) do
		Pend.cancel(pending, code)
	end
end

-- The result's startsAt: the match starts on the winner with the teams MATCH FOUND showed; the other maps and the bots
-- it did not take go back. Its players get {} after the match's first view.
function Pend.begin(pending: Pending)
	local d = getDeps()
	local result = pending.result :: Types.MatchVoteResultView
	local humans = Pend.forget(pending)
	local winner = pending.maps[result.winner]
	for _, map in pending.maps do
		if map ~= winner then
			try(d.maps.release, map)
		end
	end
	local started, why = MatchService.startMatch(pending.refs, pending.modeId, winner, pending.id, pending.teams)
	releaseBots(pending.bots)
	if started == nil then
		try(d.maps.release, winner)
		log:warn(`vote {pending.id}: could not start {pending.modeId}: {tostring(why)}`)
	end
	for _, ref in humans do
		Pend.sendTo(ref, {})
		if started == nil then
			notify(ref, if why == "closing" then CODE.closing else CODE.voidError, nil, "warn")
		end
	end
end

-- `ref` is out of `pending` (/leave, `inGame`; or gone from the game): its vote goes with it and the others see that;
-- nobody real left calls the vote off.
function Pend.leave(pending: Pending, ref: any, inGame: boolean)
	local userId = userIdOf(ref) :: number
	pendingOfUser[userId] = nil
	local at = table.find(pending.refs, ref)
	if at then
		table.remove(pending.refs, at)
	end
	pending.teams[ref] = nil
	if pending.result == nil then
		for _, list in pending.votes do
			local index = table.find(list, userId)
			if index then
				table.remove(list, index)
			end
		end
	end
	if inGame then
		setAttribute(ref, ATTR_MATCH_ID, "")
		Pend.sendTo(ref, {})
	end
	if #Pend.humans(pending) == 0 then
		Pend.cancel(pending)
	elseif pending.result == nil then
		Pend.send(pending)
	end
end

-- One step of `pending` at `now`: the bots' due votes, the result endDelaySeconds after the close, the start.
function Pend.tickOne(pending: Pending, now: number)
	local d = getDeps()
	local vote = cfg().Vote
	local result = pending.result
	if result then
		if now >= result.startsAt then
			Pend.begin(pending)
		end
		return
	end
	local changed = false
	for index, at in pending.botAt do
		if at ~= false and now >= at then
			pending.botAt[index] = false
			local choice = MatchVote.botPick(pending.votes, #pending.maps, d.rng, vote)
			changed = MatchVote.cast(pending.votes, userIdOf(pending.bots[index]) :: number, choice) or changed
		end
	end
	if now >= pending.closesAt + vote.endDelaySeconds then
		Pend.decide(pending, now)
		changed = true
	end
	if changed then
		Pend.send(pending)
	end
end

function Pend.tick(now: number)
	for _, pending in table.clone(pendings) do
		if pendings[pending.id] == pending then
			local ok, err = try(Pend.tickOne, pending, now)
			if not ok then
				log:error(`vote {pending.id} tick failed; calling it off:`, err)
				try(Pend.cancel, pending, CODE.voidError)
			end
		end
	end
end

-- Public: queues ---------------------------------------------------------------------------------------------------------

-- MatchJoin (D6): queues the player for `mode` ("ffa" | "tdm"). Returns (true, nil) or (false, the toast code).
function MatchService.join(player: any, mode: unknown): (boolean, string?)
	local d = getDeps()
	local c = cfg()
	local modeId = if type(mode) == "string" then string.lower(mode) else nil
	local modeCfg = if modeId then c.Modes[modeId] else nil
	if modeId == nil or modeCfg == nil or not d.isPlayer(player) then
		return false, nil -- an unknown mode is never sent by an honest client: no toast
	end
	local why = refusalOf(player, modeId)
	if why ~= nil then
		notify(player, why, { mode = modeName(modeId) }, "warn")
		return false, why
	end
	local now = d.now()
	local queue = queueOf(modeId)
	table.insert(queue, { player = player, userId = userIdOf(player) :: number, joinedAt = now })
	notify(player, CODE.joined, { mode = modeName(modeId), count = #queue, max = modeCfg.maxPlayers }, "info")
	syncQueue(modeId)
	local hadGather = gathers[modeId] ~= nil
	tickQueue(modeId, now) -- may start the gather (toasting the whole queue) or the match itself
	local gather = gathers[modeId]
	if hadGather and gather ~= nil and ticketOf(player) == modeId then
		if gather.waitingMapSent then
			-- D6 "no free map: keep waiting": the gather is over and the queue waits for a map (not "in 0 seconds").
			notify(player, CODE.waitingMap, { mode = modeName(modeId) }, "info")
		else
			local seconds = math.max(0, math.ceil(gather.endsAt - now))
			notify(player, CODE.startingIn, { mode = modeName(modeId), seconds = seconds }, "info")
		end
	end
	return true, nil
end

-- MatchLeave (D6): drops the queue ticket, or leaves the running match (back to the lobby at once). True when
-- something happened; else the match.notQueued toast. Match HUD M2: leaving a live match resets the win streak.
function MatchService.leave(player: any): boolean
	if dropTicket(player, CODE.left) then
		tickQueues(getDeps().now())
		return true
	end
	local userId = userIdOf(player)
	local pending = if userId then pendingOfUser[userId] else nil
	if pending then
		Pend.leave(pending, player, true) -- round 3 of the match flow: out of the map vote, back to the lobby's HUD
		notify(player, CODE.youLeft, nil, "info")
		return true
	end
	local match, p = participantOf(player)
	if match and p then
		if not match.returning then -- the return is already bringing them back
			local atStake = streakAtStake(match)
			p.gone = true
			if matchOfUser[p.userId] == match then
				matchOfUser[p.userId] = nil
			end
			match.stateDirty = true -- the others' views drop the leaver even when the leave changes nothing else
			stepMatch(match, { kind = "leave", userId = p.userId })
			if atStake then
				resetLeaverStreak(match, p)
			end
			releaseParticipant(p)
			-- At once (attributes cleared, movement back); a teleport still streaming returns them again once it lands.
			getDeps().spawn(returnOne, match, p, nil)
			notify(player, CODE.youLeft, nil, "info")
		end
		return true
	end
	notify(player, CODE.notQueued, nil, "info")
	return false
end

-- MatchVote (round 3 of the match flow): the player's vote for card `choice` of their match's map vote. Taken only from
-- a player of a vote with no result yet, open (from Vote.earlySeconds before opensAt until closesAt), for a whole card
-- number, at most once per Vote.minIntervalSeconds. True when the vote moved (everyone in it gets the new view).
function MatchService.vote(player: any, choice: unknown): boolean
	local d = getDeps()
	local userId = userIdOf(player)
	local pending = if userId then pendingOfUser[userId] else nil
	if userId == nil or pending == nil or pending.result ~= nil or not d.isPlayer(player) then
		return false
	end
	if type(choice) ~= "number" or choice % 1 ~= 0 or choice < 1 or choice > #pending.maps then
		return false -- (NaN and ±inf fail `% 1 ~= 0`)
	end
	local vote = cfg().Vote
	local now = d.now()
	local last = pending.lastVoteAt[userId]
	if now < pending.opensAt - vote.earlySeconds or now >= pending.closesAt then
		return false
	elseif last ~= nil and now - last < vote.minIntervalSeconds then
		return false
	end
	pending.lastVoteAt[userId] = now
	if not MatchVote.cast(pending.votes, userId, choice) then
		return false
	end
	Pend.send(pending)
	return true
end

-- The mode the player is queued for, or nil.
function MatchService.queued(player: any): string?
	local modeId = ticketOf(player)
	return modeId
end

function MatchService.queueCount(modeId: string): number
	return #queueOf(modeId)
end

-- Public: matches --------------------------------------------------------------------------------------------------------

-- Starts a match of `modeId` with these players (the queue's, or a Studio call) and match bots (at least one real
-- player). `map` is the one the caller acquired (else one is acquired here). Returns (matchId, nil) or (nil, why).
-- Round 3 of the match flow: `teams` (ref -> team) are the ones a map vote dealt at its start (MATCH FOUND showed
-- them; `refs` then hold the players, then the bots); without them the teams are dealt here.
function MatchService.startMatch(
	refs: { any },
	modeId: string,
	map: any?,
	matchId: string?,
	teams: { [any]: string }?
): (string?, string?)
	local d = getDeps()
	local c = cfg()
	local mode = c.Modes[modeId]
	if mode == nil then
		return nil, "unknownMode"
	end
	if d.closing() then
		return nil, "closing"
	end
	local list, bots = Pend.entrants(refs, mode) -- match bots: kept apart, after the players
	if #list + #bots < c.minPlayers or #list == 0 then
		return nil, "notEnoughPlayers" -- (bots alone never play)
	end
	local id = matchId or newMatchId()
	local useMap: MapRecord? = map or d.maps.acquire(modeId, id)
	if useMap == nil then
		return nil, "noMap"
	end
	local teamOf: { [any]: string }
	if teams then
		teamOf = teams
		table.move(bots, 1, #bots, #list + 1, list)
	else
		list, teamOf = Pend.deal(list, bots, mode)
	end
	local now = d.now()
	local match: Match = {
		matchId = id,
		modeId = modeId,
		mode = mode,
		map = useMap,
		state = nil :: any,
		port = nil :: any,
		list = {},
		byUserId = {},
		pending = {},
		stateDirty = false,
		returning = false,
		closed = false,
		endedFired = false,
		nextStormAt = -math.huge,
		createdAt = now,
		pads = padsOf(useMap), -- power-ups v1.1: per match, all ready
		nextPadAt = -math.huge,
		nextBuffAt = math.huge,
		now = now,
		events = {}, -- Match HUD M1
		eventSeq = 0,
		stepId = 0,
		finalKo = nil,
		standings = nil,
		rewards = {}, -- Match HUD M2
		bots = #bots,
	}
	local spawns = useMap.spawns
	local built, why = try(function()
		local entrants: { MatchRules.Entrant } = {}
		for _, ref in list do
			local p = newParticipant(match, ref, teamOf[ref], now)
			table.insert(match.list, p)
			match.byUserId[p.userId] = p
			table.insert(entrants, { userId = p.userId, team = p.team, isBot = isBotRef(ref) })
		end
		match.state = MatchRules.new(id, modeId, entrants, now, c)
		local first = MatchSpawns.firstSpots(spawns, entrants :: any) -- (MatchSpawns reads userId and team only)
		for _, p in match.list do
			p.spot = first[p.userId]
		end
		match.port = buildPort(match)
		matches[id] = match
		for _, p in match.list do
			matchOfUser[p.userId] = match
		end
		d.combat.registerMatch(match.port)
		d.ability.attachMatch(match.port)
		for _, p in match.list do
			setMatchAttributes(match, p)
		end
	end)
	if not built then
		-- Nobody may stay "in" a match that never ran: unregister, detach, release the map, forget the players and
		-- clear their attributes (the queue tries again after another gather).
		log:error(`match {id} ({modeId} on {useMap.code}) could not start:`, why)
		if matches[id] == match then
			safeClose(match)
		elseif map == nil then
			try(d.maps.release, useMap)
		end
		return nil, "error"
	end
	sendState(match)
	ensureHeartbeat()
	log:info(`match {id} started: {modeId} on {useMap.code} with {#match.list} players`)
	positionAll(match)
	return id, nil
end

-- The match of a Player (or a userId), or nil.
function MatchService.getMatch(who: any): MatchInfo?
	local match, p = participantOf(who)
	if match == nil or p == nil then
		return nil
	end
	return {
		matchId = match.matchId,
		modeId = match.modeId,
		phase = wirePhaseOf(match),
		matchPhase = match.state.phase,
		team = p.team,
	}
end

-- Match bots: what the pilot of a bot (or any participant) may read of its match now, or nil outside a match.
function MatchService.botView(who: any): BotView?
	local match, p = participantOf(who)
	if match == nil or p == nil then
		return nil
	end
	local now = getDeps().now()
	local pads: { Vector3 } = {}
	for _, entry in match.pads do
		if PowerUpRules.isReady(entry.pad, now) then
			table.insert(pads, Vector3.new(entry.position.X, entry.top, entry.position.Z))
		end
	end
	return {
		map = match.map,
		live = MatchRules.isLive(match.state),
		stormSeconds = if match.mode.storm then MatchRules.activeSeconds(match.state, now) else nil,
		pads = pads,
	}
end

-- Match bots: MatchBotService's init hands its bots over (nil: no bots). Tests pass them in their deps instead.
function MatchService.attachBots(bots: BotDeps?)
	getDeps().bots = bots
end

-- Matches in progress (Result and the return included).
function MatchService.matchCount(): number
	local count = 0
	for _ in matches do
		count += 1
	end
	return count
end

-- D1: the DuelPhase name of a MatchRules phase (pure; unit-tested).
function MatchService.wirePhase(matchPhase: string): Types.DuelPhase
	return WIRE_PHASE[matchPhase] or "Returning"
end

-- Ends every match now: "shutdown" (BindToClose, a restart) voids them; any other reason voids them as an error.
function MatchService.voidAll(reason: string?)
	Pend.cancelAll(nil) -- round 3 of the match flow: the map votes too (no match yet)
	local kind = if reason == "shutdown" then "shutdown" else "error"
	for _, match in matchList() do
		local ok, err = try(stepMatch, match, { kind = kind })
		if not ok then
			log:error(`voiding match {match.matchId} failed:`, err)
			safeClose(match)
		end
	end
end

-- QueueService.Joined (init connects it): joining the duel queue (or a friend duel) gives up the match ticket.
function MatchService.onDuelQueueJoined(player: any)
	dropTicket(player, CODE.leftForDuel)
end

-- ShutdownService.RestartScheduled (init connects it): the queues are cleared (match.refused.closing) and every match
-- that can't end before the restart (maxRemaining: its longest remaining time, overtime and Result included) is voided.
function MatchService.onRestartScheduled()
	clearQueues(CODE.closing)
	Pend.cancelAll(CODE.closing) -- round 3 of the match flow: a map vote's match would start too late
	local d = getDeps()
	local now = d.now()
	for _, match in matchList() do
		if not match.state.ended and not d.canFinishBeforeRestart(maxRemaining(match, now)) then
			local ok, err = try(stepMatch, match, { kind = "shutdown" }, now)
			if not ok then
				log:error(`restart handling failed for match {match.matchId}:`, err)
			end
		end
	end
end

-- One step of everything at server time `now` (default the clock): the queues, then every match. The live server
-- runs the matches every Heartbeat and the queues from start(); tests call this.
function MatchService.tick(now: number?)
	local t = if now ~= nil then now else getDeps().now()
	tickQueues(t)
	Pend.tick(t) -- round 3 of the match flow: the map votes
	tickMatches(t)
end

-- Uses these collaborators and forgets every queue and match (init() passes the real ones; tests pass fakes; nil
-- restores the real ones).
function MatchService.useDeps(newDeps: Deps?)
	if heartbeat ~= nil then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	deps = newDeps
	matches = {}
	matchOfUser = {}
	queues = {}
	gathers = {}
	pendings = {}
	pendingOfUser = {}
	returnPointUsedAt = {}
end

-- Studio debug view.
function MatchService.debugState(): { [string]: any }
	local list = {}
	for matchId, match in matches do
		local players = {}
		for _, p in match.list do
			local r = record(match, p)
			table.insert(players, {
				userId = p.userId,
				team = p.team,
				kos = if r then r.kos else 0,
				alive = r ~= nil and r.alive,
				gone = p.gone,
				dropped = p.dropped,
			})
		end
		table.insert(list, {
			matchId = matchId,
			modeId = match.modeId,
			map = match.map.code,
			phase = match.state.phase,
			teamLives = table.clone(match.state.teamLives),
			players = players,
		})
	end
	local queued = {}
	for modeId, queue in queues do
		queued[modeId] = #queue
	end
	return { matches = list, queued = queued }
end

defaultDeps = function(): Deps
	return {
		now = function(): number
			return Workspace:GetServerTimeNow()
		end,
		clock = os.clock,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		defer = function(fn: (...any) -> ...any, ...: any)
			task.defer(fn, ...)
		end,
		spawn = function(fn: (...any) -> ...any, ...: any)
			task.spawn(fn, ...)
		end,
		rng = Random.new(),
		isPlayer = function(ref: any): boolean
			return typeof(ref) == "Instance" and ref:IsA("Player") and ref.Parent == Players
		end,
		playerCount = function(): number
			return #Players:GetPlayers()
		end,
		getRoot = function(ref: any): any?
			return CharacterService.getRoot(ref)
		end,
		humanoid = function(ref: any): any?
			return CharacterService.getHumanoid(ref)
		end,
		isAlive = function(ref: any): boolean
			return CharacterService.isAlive(ref)
		end,
		teleportAsync = function(ref: any, cf: CFrame): (boolean, string?)
			return CharacterService.teleportAsync(ref, cf)
		end,
		equipped = function(ref: any): string?
			return InventoryService.getEquipped(ref)
		end,
		queueState = function(ref: any): string
			return QueueService.state(ref)
		end,
		isPracticing = function(ref: any): boolean
			return PracticeService.isPracticing(ref)
		end,
		closing = ShutdownService.isClosing,
		restartPending = ShutdownService.isRestartPending,
		canFinishBeforeRestart = function(seconds: number): boolean
			return ShutdownService.canFinishBeforeRestart(seconds)
		end,
		fire = function(name: string, ref: any, payload: any)
			NetService.fire(name, ref, payload)
		end,
		notify = function(ref: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
			NetService.notify(ref, code, args, kind)
		end,
		combat = {
			newFighter = CombatService.newFighter,
			registerMatch = CombatService.registerMatch,
			unregisterMatch = CombatService.unregisterMatch,
			pivotFighter = CombatService.pivotFighter,
			noteTeleport = CombatService.noteTeleport,
			syncTo = CombatService.syncTo,
			releaseFighter = CombatService.releaseFighter,
		},
		ability = {
			attachMatch = AbilityService.attachMatch,
			detachMatch = AbilityService.detachMatch,
			detachFighter = AbilityService.detachFighter,
			isReady = AbilityService.isReady,
			addCharge = AbilityService.addChargeFraction, -- power-ups v1.1
		},
		maps = {
			acquire = function(modeId: string, matchId: string): any?
				return MatchMapService.acquire(modeId, matchId)
			end,
			release = MatchMapService.release,
			hasMode = MatchMapService.hasMode,
		},
		rewards = { -- Match HUD M2
			grant = EconomyService.grantMatchResult,
			addGrip = GripService.addFromMatch,
			winStreak = EconomyService.winStreak,
		},
		heartbeat = true,
		matchConfig = nil,
		gripLevel = GripService.levelOf, -- round 2 of the match flow: MATCH FOUND shows each player's Grip level
	}
end

-- Lifecycle

function MatchService.init()
	MatchService.useDeps(defaultDeps())
	NetService.on(REMOTE_JOIN, function(player: Player, mode: any)
		MatchService.join(player, mode)
	end)
	NetService.on(REMOTE_LEAVE, function(player: Player)
		MatchService.leave(player)
	end)
	NetService.on(REMOTE_VOTE, function(player: Player, choice: any)
		MatchService.vote(player, choice)
	end)
	QueueService.Joined:connect(function(player: any)
		MatchService.onDuelQueueJoined(player)
	end)
	ShutdownService.Closing:connect(function()
		clearQueues(nil)
		MatchService.voidAll("shutdown")
	end)
	ShutdownService.RestartScheduled:connect(function(_restartAt: number, _reason: string)
		MatchService.onRestartScheduled()
	end)
	-- Match HUD M2: SD_WinStreak from every loaded profile (as GripService's SD_GripLevel baseline).
	StateService.dataPort().onLoaded(function(player: any)
		MatchService.refreshWinStreak(player)
	end)
end

function MatchService.start()
	while true do
		task.wait(QUEUE_TICK_SECONDS)
		local ok, err = try(tickQueues, getDeps().now())
		if not ok then
			log:error("queue tick failed:", err)
		end
	end
end

-- Leaving the game: the ticket goes, a running match gets MatchRules `leave` (no return: the character is gone).
-- Match HUD M2: leaving a live match resets the win streak (this hook runs before DataService's: the profile still
-- takes the change).
function MatchService.playerRemoving(player: Player)
	dropTicket(player, nil)
	local pending = pendingOfUser[player.UserId]
	if pending then
		Pend.leave(pending, player, false) -- round 3 of the match flow: their vote goes with them
	end
	local match, p = participantOf(player)
	if match and p then
		local atStake = streakAtStake(match)
		p.gone = true
		if matchOfUser[p.userId] == match then
			matchOfUser[p.userId] = nil
		end
		match.stateDirty = true -- the others' views drop the leaver
		stepMatch(match, { kind = "leave", userId = p.userId })
		if atStake then
			resetLeaverStreak(match, p)
		end
		releaseParticipant(p) -- a rejoin gets a fresh lobby fighter, not this one (its closures hold the old Player)
	end
end

-- Match HUD M2: SD_WinStreak = the player's saved win streak (init calls it whenever a profile loads). Nothing without
-- the pay's collaborators.
function MatchService.refreshWinStreak(player: any)
	local rewards = getDeps().rewards
	if rewards == nil then
		return
	end
	local ok, streak = try(rewards.winStreak, player)
	setAttribute(player, ATTR_WIN_STREAK, if ok and type(streak) == "number" then streak else 0)
end

-- Not called by the bootstrap; used by leak checks.
function MatchService.destroy()
	Pend.cancelAll(nil)
	for _, match in matchList() do
		safeClose(match)
	end
	MatchService.useDeps(nil)
	MatchService.MatchEnded:disconnectAll()
end

return MatchService
