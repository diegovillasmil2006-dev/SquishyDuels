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
--   match.winner {name} / match.teamWins {team} / match.draw / match.cancelled / match.void) and MatchEnded. v1 pays
--   nothing (Config.Match.rewardCoins = 0): no Coins, no DuelResult, no quests, weekly wins or badges. `closed` (after
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
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local StormMath = require(Shared.StormMath)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)
local Logic = script.Parent.Parent.Logic
local MatchRules = require(Logic.MatchRules)
local MatchSpawns = require(Logic.MatchSpawns)
local Services = script.Parent
local AbilityService = require(Services.AbilityService)
local CharacterService = require(Services.CharacterService)
local CombatService = require(Services.CombatService)
local InventoryService = require(Services.InventoryService)
local MatchMapService = require(Services.MatchMapService)
local NetService = require(Services.NetService)
local PracticeService = require(Services.PracticeService)
local QueueService = require(Services.QueueService)
local ShutdownService = require(Services.ShutdownService)

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
}

export type MapDeps = {
	acquire: (modeId: string, matchId: string) -> any?,
	release: (record: any) -> (),
	hasMode: (modeId: string) -> boolean,
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
	heartbeat: boolean, -- tick matches every Heartbeat (false in tests: they call tick)
	matchConfig: any?, -- a Config.Match-shaped table (tests pass their copy); nil = the live Config.Match
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
}

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
local REMOTE_JOIN = "MatchJoin"
local REMOTE_LEAVE = "MatchLeave"
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_PHASE = "SD_DuelPhase"
local ATTR_MATCH_PHASE = "SD_MatchPhase"
local ATTR_MODE = "SD_MatchMode"
local ATTR_TEAM = "SD_Team"
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
	if userId ~= nil and matchOfUser[userId] ~= nil then
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

-- Active (and a respawn): Config.Duel.Rules.Movement, turning on again.
local function matchMovement(p: Participant)
	local humanoid = getDeps().humanoid(p.ref)
	if humanoid == nil then
		return
	end
	saveMovement(p, humanoid)
	humanoid.WalkSpeed = MOVEMENT.WalkSpeed
	humanoid.JumpHeight = MOVEMENT.JumpHeight
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
		matchMovement(p)
	else
		freezeMovement(p, true)
	end
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

-- Everyone still in the match (a player who left or never arrived is not listed: no enemy, no leader).
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
			})
		end
	end
	return list
end

local function viewFor(match: Match, p: Participant, players: { Types.MatchParticipantView }): Types.MatchStateView
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
			}
			else nil,
	}
	return view
end

-- Sends MatchState to every active participant (or only to those in `only`); the players list is built once.
local function sendState(match: Match, only: { Participant }?)
	local d = getDeps()
	local players = playersView(match)
	for _, p in only or match.list do
		if active(p) then
			local r = record(match, p)
			p.sentStormBar = if r then r.stormBar else 0
			local ok, err = try(d.fire, REMOTE_STATE, p.ref, viewFor(match, p, players))
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

-- Private: lifecycle -----------------------------------------------------------------------------------------------------

local perform: (match: Match, effect: Effect) -> ()

-- One MatchRules event: the new state is stored first, then its effects run (none of them yields). The projectiles
-- are swept up to the same time first (CombatService.syncTo), as in DuelService.stepMatch.
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
	syncFighters(match)
	for _, effect in effects do
		perform(match, effect)
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
				matchMovement(p)
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
	matchMovement(p)
end

local function onOut(match: Match, effect: Effect)
	match.stateDirty = true
	local p = match.byUserId[effect.userId]
	if p and active(p) then
		notify(p.ref, CODE.outNoLives, nil, "warn")
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

-- The single end (MatchRules `ended`): the toasts and MatchEnded. Exactly once. No rewards in v1.
local function onEnded(match: Match, outcome: any)
	if match.endedFired then
		return
	end
	match.endedFired = true
	match.stateDirty = true
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
		end
	end
	-- v1: Config.Match.rewardCoins is 0 and nothing is paid (no EconomyService reason, quests or weekly wins yet).
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

perform = function(match: Match, effect: Effect)
	local kind = effect.kind
	if kind == "phase" then
		onPhase(match, effect.phase, effect.startedAt or getDeps().now())
	elseif kind == "ended" then
		if effect.outcome then
			onEnded(match, effect.outcome)
		end
	elseif kind == "ko" then
		onKo(match, effect)
	elseif kind == "respawn" then
		onRespawn(match, effect)
	elseif kind == "out" then
		onOut(match, effect)
	elseif kind == "closed" then
		startReturn(match)
	else
		-- teamLives, and the power-up effects MatchRules supports (pads stay idle in v1): the views carry them.
		match.stateDirty = true
	end
end

-- The TDM team lives right after the K.O. at effects[index] (the next teamLives / out of the victim's team).
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
		cooldownMultiplier = function(): number
			return 1 -- D1 (rapidThrow will pass the fighter later)
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
			syncFighters(match)
			local used: { [number]: boolean } = {}
			for i, effect in effects do
				if effect.kind == "ko" and effect.by ~= nil then
					for index, hit in hits do
						if
							not used[index]
							and hit.victim.userId == effect.victim
							and hit.attacker.userId == effect.by
							and math.min(hit.at, now) == effect.at
						then
							used[index] = true
							outcomes[index] = {
								lives = livesAfter(match, effects, i, match.byUserId[effect.victim]),
								invulnUntil = effect.at,
								eliminated = true,
							}
							break
						end
					end
				end
				-- A shieldBlocked hit (no power-ups in v1) is refused here: its projectile flies on.
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

local function newParticipant(match: Match, ref: any, team: string?, now: number): Participant
	local d = getDeps()
	local userId = userIdOf(ref) :: number
	local id = d.equipped(ref)
	local squishyId = if Catalog.isValidId(id) then id :: string else Catalog.starterId()
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
		displayName = if type(ref.DisplayName) == "string" then ref.DisplayName else tostring(userId),
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
	}
	return p
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
		if active(p) and r and r.stormBar ~= p.sentStormBar then
			table.insert(changed, p)
		end
	end
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

local function tickMatch(match: Match, now: number)
	if match.closed then
		return
	end
	checkPresence(match)
	sampleStorm(match, now)
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
			tickMatches(getDeps().now())
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

-- Removes the player's ticket (with `code` when given). True when there was one.
local function dropTicket(ref: any, code: string?): boolean
	local modeId, index = ticketOf(ref)
	if modeId == nil or index == nil then
		return false
	end
	table.remove(queueOf(modeId), index)
	if code ~= nil then
		notify(ref, code, { mode = modeName(modeId) }, "info")
	end
	return true
end

local function clearQueues(code: string?)
	for modeId, queue in queues do
		for _, ticket in queue do
			if code ~= nil then
				notify(ticket.player, code, { mode = modeName(modeId) }, "warn")
			end
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
	for index = #queue, 1, -1 do
		local ref = queue[index].player
		if not d.isPlayer(ref) or inAnyMatch(ref) or d.queueState(ref) ~= "Idle" then
			table.remove(queue, index)
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
	local map = d.maps.acquire(modeId, matchId)
	if map == nil then
		if not gather.waitingMapSent then
			gather.waitingMapSent = true
			notifyQueue(modeId, CODE.waitingMap, { mode = modeName(modeId) }, "info")
		end
		return
	end
	local started, why = MatchService.startMatch(refs, modeId, map, matchId)
	if started == nil then
		try(d.maps.release, map)
		log:warn(`could not start {modeId} from the queue: {tostring(why)}`)
		gather.endsAt = now + cfg().gatherSeconds -- try again after another gather, not every tick
		return
	end
	for _, ref in refs do
		if inAnyMatch(ref) then
			dropTicket(ref, nil) -- in the match now (a ticket startMatch skipped stays queued)
		end
	end
	gathers[modeId] = nil
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
	if #queue < c.minPlayers then
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
-- something happened; else the match.notQueued toast.
function MatchService.leave(player: any): boolean
	if dropTicket(player, CODE.left) then
		tickQueues(getDeps().now())
		return true
	end
	local match, p = participantOf(player)
	if match and p then
		if not match.returning then -- the return is already bringing them back
			p.gone = true
			if matchOfUser[p.userId] == match then
				matchOfUser[p.userId] = nil
			end
			match.stateDirty = true -- the others' views drop the leaver even when the leave changes nothing else
			stepMatch(match, { kind = "leave", userId = p.userId })
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

-- The mode the player is queued for, or nil.
function MatchService.queued(player: any): string?
	local modeId = ticketOf(player)
	return modeId
end

function MatchService.queueCount(modeId: string): number
	return #queueOf(modeId)
end

-- Public: matches --------------------------------------------------------------------------------------------------------

-- Starts a match of `modeId` with these players (the queue's, or a Studio call). `map` is the one the caller acquired
-- (else one is acquired here). Returns (matchId, nil) or (nil, why).
function MatchService.startMatch(refs: { any }, modeId: string, map: any?, matchId: string?): (string?, string?)
	local d = getDeps()
	local c = cfg()
	local mode = c.Modes[modeId]
	if mode == nil then
		return nil, "unknownMode"
	end
	if d.closing() then
		return nil, "closing"
	end
	local list: { any } = {}
	local seen: { [number]: boolean } = {}
	for _, ref in refs do
		local userId = userIdOf(ref)
		if
			userId ~= nil
			and not seen[userId]
			and d.isPlayer(ref)
			and not inAnyMatch(ref)
			and #list < mode.maxPlayers
		then
			seen[userId] = true
			table.insert(list, ref)
		end
	end
	if #list < c.minPlayers then
		return nil, "notEnoughPlayers"
	end
	local id = matchId or newMatchId()
	local useMap: MapRecord? = map or d.maps.acquire(modeId, id)
	if useMap == nil then
		return nil, "noMap"
	end

	-- TDM: shuffled, then Red, Blue, Red, ... (friends together: later).
	local teams: { [any]: string } = {}
	if mode.teams then
		shuffle(list, d.rng)
		for index, ref in list do
			teams[ref] = c.teamNames[(index - 1) % 2 + 1]
		end
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
	}
	local spawns = useMap.spawns
	local built, why = try(function()
		local entrants: { MatchSpawns.Entrant } = {}
		for _, ref in list do
			local p = newParticipant(match, ref, teams[ref], now)
			table.insert(match.list, p)
			match.byUserId[p.userId] = p
			table.insert(entrants, { userId = p.userId, team = p.team })
		end
		match.state = MatchRules.new(id, modeId, entrants, now, c)
		local first = MatchSpawns.firstSpots(spawns, entrants)
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
	for _, p in match.list do
		p.positioning = true -- set now: a return that starts before the deferred thread runs must wait for it
		d.defer(positionParticipant, match, p)
	end
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
		},
		maps = {
			acquire = function(modeId: string, matchId: string): any?
				return MatchMapService.acquire(modeId, matchId)
			end,
			release = MatchMapService.release,
			hasMode = MatchMapService.hasMode,
		},
		heartbeat = true,
		matchConfig = nil,
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
function MatchService.playerRemoving(player: Player)
	dropTicket(player, nil)
	local match, p = participantOf(player)
	if match and p then
		p.gone = true
		if matchOfUser[p.userId] == match then
			matchOfUser[p.userId] = nil
		end
		match.stateDirty = true -- the others' views drop the leaver
		stepMatch(match, { kind = "leave", userId = p.userId })
		releaseParticipant(p) -- a rejoin gets a fresh lobby fighter, not this one (its closures hold the old Player)
	end
end

-- Not called by the bootstrap; used by leak checks.
function MatchService.destroy()
	for _, match in matchList() do
		safeClose(match)
	end
	MatchService.useDeps(nil)
	MatchService.MatchEnded:disconnectAll()
end

return MatchService
