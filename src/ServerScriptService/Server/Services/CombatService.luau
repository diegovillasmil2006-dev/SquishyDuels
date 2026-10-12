--!strict
-- CombatService (server only). DESIGN §5.1, §5.5-§5.7, §5.11, §12 #2-#13, #23.
-- The server decides every throw and every hit; clients only render (§5.1).
-- * ThrowRequest (and the Studio test dummy, through requestThrow) is validated by Logic/ThrowRules with the
--   server's own state: the match snapshot of the thrown squishy (never the client's), the server HumanoidRootPart, the
--   arena slot's zones and its projectile RaycastParams / OverlapParams (Default group, Geometry minus Barriers, §5.3).
--   Practice throws use the same rules inside the lobby's SD_PracticeZone (PracticeService) with the equipped squishy.
--   A rejection answers ThrowRejected(seq, reason, nextThrowAt) to the thrower; an acceptance sends ThrowStarted to
--   both participants (practice: players within Config.Combat.Projectile.practiceBroadcastStuds) with
--   releaseAt = the server projectile's spawn time (it is the projectile's own releaseAt, §13.2 Part 4).
-- * Projectiles are analytic (Shared/ProjectileMath, no server Parts, no Touched). One Heartbeat connection runs while
--   any projectile exists; each projectile is swept over sub-steps of its local time (ProjectileMath.subSteps): a
--   Spherecast against the slot's RaycastParams and the capsule test of Logic/HitMath against the opponent's current
--   server HRP (no rewind, §5.7 lag policy). The earliest of the two in a sub-step is the projectile's candidate.
--   Candidates of one Heartbeat are applied in impact-time order; duel hits go to the match owner (DuelService) in one
--   batch, so Logic/DuelRules applies lives, invulnerability, the final hit and the exact-tie draw (§5.2 rule 7). A hit
--   the rules refuse (the victim is invulnerable, the match just ended) is not an impact: that projectile flies on.
-- * Limits (§12 #10): MaxActiveProjectilesPerPlayer live per thrower (ThrowRules check 9), ProjectileMaxLifetime,
--   expiry outside the arena Bounds (practice: PracticeTargets.BOUNDS), spawn-overlap fizzle at release. A projectile
--   whose match left Active/SuddenDeath before its release is discarded (sent as `expired` at its origin so clients
--   drop the model).
-- * Target set (§12 #12): canDamage = different sides of the same match, the match is live and the victim outside
--   invulnerability (DuelRules.canBeHit through the port), the victim's HRP inside that arena's Bounds. The thrower's
--   own capsule is never tested. Practice projectiles test only practice targets. Nothing here touches Humanoid.Health.
-- * Dragon Rush lanes (AbilityService.launchLane): the same simulation with gravity 0 and the lane radius from O to E
--   (E already stops at cover and Bounds), hitting each victim (or practice target) at most once. A lane tests the
--   victim's capsule at standing height (axis floor + 1.3 .. floor + 4.8, §5.9 "even at the top of a jump"): only
--   the HRP's X and Z count, so jumping never avoids the lane and the floor stadium the clients draw is the hit area.
-- * The Epic ultimates (spec phase 5; AbilityService.launchUlt / launchArea), kind "ult" ("practiceUlt" in the range;
--   never "throw", so they give no charge): the same gravity-0 simulation from O over a length that already stops at
--   cover and Bounds. A Flock Volley bird tests the real capsule and ends at its first hit. The Sprinkle Roller
--   (`clearHeight`) tests horizontally only (its lane's half-width + the capsule radius, Logic/UltRules.flatEntry) and
--   misses a player whose feet are higher than clearHeight above the floor; it flies on like a lane. A Bubble Pop
--   (`splashRadius`) pops at its first contact, at cover or at the end of its flight, and a pop is an area hit. An area
--   hit (a Rain Check drop, a pop) happens once at its server time: the first victim (or practice target) whose feet
--   (the capsule's lowest point) are within its radius of its floor point and passes canDamage is hit; a drop that
--   hits nobody sends nothing, a pop that hits nobody sends its end impact (expired / geometry) at the pop point.
-- * Order against the match timers (§5.2 rule 7, DuelRules "timed transitions happen at their deadline"): the match
--   owner calls syncTo(now) before it advances its timers to `now`, so every projectile is swept up to that time
--   first and a hit whose impact comes just before a phase deadline is applied before the deadline fires. A throw or
--   ultimate request first brings its match up to the request time (port.sync), so the phase, nextThrowAt and the
--   cooldown multiplier it is validated against are current.
-- * Movement guard at Config.Combat.MovementGuard.checkHz (Logic/MovementRules, §5.7): pivots back on over-speed,
--   neutral zone, opponent half or inside Geometry; out-of-bounds goes to the match owner (count, re-pivot, forfeit).
--   While a fighter must stand still (the Countdown freeze on its pad, the Dragon Rush root of telegraph + recovery)
--   the server enforces it too, not only through WalkSpeed / JumpHeight 0: a drift beyond holdToleranceStuds (plus the
--   stopping distance a root allows at the player's ping) is pivoted back.
-- * Feature 1 (2026-10-11; Config.Combat.Charge / Catch; design: the combat-effects page "Squishy Combat FP v2.html"):
--   - The charge throw: ChargeStart(clientTime) stores the press time, lag-compensated as a throw's (§5.6 #7,
--     Logic/CatchRules.pressTime), on the fighter (practice: the practice actor); the next ThrowRequest consumes it
--     (accepted or not) and Logic/ThrowRules measures the charge from it, never before the throw was ready, the hands
--     were back or a root ended (chargeFloorAt). ThrowStarted carries that charge as `power`.
--   - The catch: CatchRequest(clientTime) is checked by Logic/CatchRules (a live duel, alive, not crushing, rooted or
--     in a windup, the cooldown from the last press) and opens a window [press, press + windowSeconds] on the fighter;
--     it also drops a charge (design: html:344). A throw's sweep tests the opponent's open window before its hit test
--     (CatchRules.catchFraction on the same sub-steps, at the catcher's HRP + centreAboveRootStuds; ultimates, lanes
--     and practice throws are never caught). A catch ends the throw without an impact (it is no longer a live throw)
--     and keeps its record as a crush: CatchEvent "caught" to both duelists, the window closes, the catcher's hands are
--     busy until handsBackSeconds after the catch (no throw, catch, dash or ultimate: ThrowRules 7b, CatchRules,
--     DashService, AbilityService). At burstAt (= the catch + crushSeconds) the burst goes to the match owner with the
--     step's hits, as a hit on the thrower by the catcher (kind "catch", force = Catch.burstIgnoresInvuln, so the
--     thrower loses 1 life even inside its invulnerability; user decision 2026-10-11), then CatchEvent "burst" with
--     the outcome; a match that ended meanwhile loses no life (the burst is still sent, without lives). Hit (and
--     Eliminated) fire for it as for any hit. unregisterMatch drops a crush with its match.
-- * CombatLog counters (§12 #23): rejections per reason and throws / hits / wins per squishy; userIds only in logs.
--   A payload failure that only ThrowRules can see (the seq window, §5.6 #2) is reported to NetService as a violation.
-- Signals (upward communication, §2.6): Hit(info), Eliminated(info), ThrowAccepted(info).
-- The match owner talks to this module only through a MatchPort (registerMatch): plain callbacks, no requires upward.
-- Tests (Edit mode) swap the clock and the sender with useDeps({now, send, autoStep = false}) and drive the
-- simulation with step(now); the live server uses Workspace:GetServerTimeNow(), NetService and one Heartbeat.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local ProjectileMath = require(Shared.ProjectileMath)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local Logic = script.Parent.Parent.Logic
local CatchRules = require(Logic.CatchRules)
local HitMath = require(Logic.HitMath)
local MovementRules = require(Logic.MovementRules)
local ThrowRules = require(Logic.ThrowRules)
local UltRules = require(Logic.UltRules)
local CharacterService = require(script.Parent.CharacterService)
local InventoryService = require(script.Parent.InventoryService)
local NetService = require(script.Parent.NetService)
local PracticeService = require(script.Parent.PracticeService)

-- Types

export type Side = Types.Side
export type Zone = Types.ArenaZone
export type ThrowStats = ThrowRules.ThrowStats
-- "catch" (feature 1) is the kind of a caught throw's burst hit (HitRequest, HitInfo); no projectile has it.
export type ProjectileKind = "throw" | "practice" | "lane" | "practiceLane" | "ult" | "practiceUlt" | "catch"

-- One duelist. DuelService creates it with newFighter(); the throw state fields belong to this module.
export type Fighter = {
	userId: number,
	player: Player?, -- nil for the Studio test dummy
	isTestDummy: boolean,
	side: Side,
	squishyId: string, -- match snapshot (§5.4 Preparing), never from the client
	throw: ThrowStats,
	getRoot: () -> BasePart?, -- the current server HumanoidRootPart
	isAlive: () -> boolean,
	nextThrowAt: number, -- server time; DuelService resets it to `now` at Active start
	activeProjectiles: number,
	invulnUntil: number, -- mirrors DuelRules (hits and out-of-bounds)
	rootedUntil: number, -- Dragon Rush telegraph and recovery (AbilityService)
	windupUntil: number, -- releaseAt of the newest accepted throw
	throwsAccepted: number,
	hits: number,
	guard: MovementRules.Guard, -- movement guard memory (§5.7)
	-- Feature 1 (server times): the charge start (ChargeStart; nil = none), the catch window, the last accepted catch
	-- press and when the hands are back from a catch (-math.huge = none).
	chargeStartAt: number?,
	catchOpensAt: number,
	catchClosesAt: number,
	lastCatchPressAt: number,
	handsBackAt: number,
}

-- The arena of one match, from the ArenaService slot.
export type ArenaInfo = {
	slot: number,
	floorY: number,
	killY: number,
	zones: { [string]: Zone }, -- HalfA, Neutral, HalfB, Bounds
	geometry: Instance?,
	raycastParams: RaycastParams,
	overlapParams: OverlapParams,
}

export type HitRequest = {
	attacker: Fighter,
	victim: Fighter,
	at: number, -- impact time (server time)
	kind: ProjectileKind,
	projId: number,
	position: Vector3,
	force: boolean?, -- feature 1: a caught throw's burst costs the life inside invulnerability (DuelRules Hit.force)
}

export type HitOutcome = {
	lives: number,
	invulnUntil: number,
	eliminated: boolean,
}

-- How CombatService talks to the owner of a match (DuelService). Every call is synchronous and must not yield.
export type MatchPort = {
	matchId: string,
	arena: ArenaInfo,
	fighters: { Fighter }, -- the two duelists
	phase: () -> string, -- Types.DuelPhase
	cooldownMultiplier: () -> number, -- DuelRules.cooldownMultiplier
	placement: (fighter: Fighter) -> CFrame?, -- where the fighter stands on its own pad (§5.4 height included)
	canBeHit: (victim: Fighter, at: number) -> boolean, -- DuelRules.canBeHit
	-- One step's hits on this match, in impact order, found while sweeping up to server time `now`. Returns the
	-- applied ones by index (missing = refused).
	applyHits: (hits: { HitRequest }, now: number) -> { [number]: HitOutcome },
	flush: () -> (), -- after the step's impacts were sent: perform the effects of applyHits
	throwAccepted: (fighter: Fighter) -> (),
	outOfBounds: (fighter: Fighter) -> (),
	-- Optional: brings the match's timers up to server time `now` (DuelService: a `tick`). Called before a throw or an
	-- ultimate is validated against phase(), nextThrowAt and cooldownMultiplier().
	sync: ((now: number) -> ())?,
}

export type HitInfo = {
	matchId: string,
	attacker: Fighter,
	victim: Fighter,
	kind: ProjectileKind,
	projId: number,
	at: number,
	position: Vector3,
	livesLeft: number,
	eliminated: boolean,
}

export type ThrowInfo = {
	userId: number,
	player: Player?,
	matchId: string?,
	kind: Types.ThrowKind,
	squishyId: string,
	projId: number,
	releaseAt: number,
}

-- A Dragon Rush lane (AbilityService): a straight sphere sweep from origin over `length` studs.
export type LaneSpec = {
	caster: Fighter?, -- duel caster (nil in practice)
	player: Player?, -- the casting player (practice: required)
	squishyId: string,
	origin: Vector3,
	direction: Vector3, -- unit, horizontal
	length: number,
	radius: number,
	speed: number,
	releaseAt: number,
	stoppedByGeometry: boolean, -- E is on cover: the end impact is `geometry`, else `expired`
}

-- An Epic ultimate's projectile (AbilityService, spec phase 5): a Flock Volley bird, the Sprinkle Roller or a Bubble
-- Pop bubble, a straight sweep like a lane over a length that already stops at cover and Bounds.
export type UltSpec = {
	caster: Fighter?, -- duel caster (nil in practice)
	player: Player?, -- the casting player (practice: required)
	squishyId: string,
	origin: Vector3,
	direction: Vector3, -- unit, horizontal
	length: number,
	radius: number,
	speed: number,
	releaseAt: number,
	stoppedByGeometry: boolean,
	floorY: number, -- the arena (or practice lane) floor, for the feet tests
	flyOn: boolean?, -- true: flies on through the victim it hits (the roller); else ends at its first hit
	clearHeight: number?, -- the roller: horizontal hits only, none while the feet are higher than this above floorY
	splashRadius: number?, -- the bubble: it pops at its first contact or end; feet this close to the pop are hit
}

-- One area hit at one server time (a Rain Check drop).
export type AreaSpec = {
	caster: Fighter?,
	player: Player?,
	squishyId: string,
	position: Vector3, -- on the floor
	radius: number, -- a victim whose feet are this close to `position` is hit
	at: number, -- server time
	floorY: number,
}

-- What the guard and AbilityService read about a practising player.
type PracticeActor = {
	nextThrowAt: number,
	activeProjectiles: number,
	rootedUntil: number,
	windupUntil: number,
	chargeStartAt: number?, -- feature 1: the practice charge start (ChargeStart; nil = none)
}

-- Feature 1: a caught throw's record while the catcher crushes it (its projectile stays in the list until the burst).
type Crush = {
	port: MatchPort,
	catcher: Fighter,
	thrower: Fighter,
	at: number, -- the catch (server time)
	burstAt: number,
	position: Vector3, -- where it was caught
}

type Projectile = {
	projId: number,
	kind: ProjectileKind,
	ownerId: number,
	owner: any, -- Fighter (duel kinds) or PracticeActor
	player: Player?, -- the thrower (nil for the dummy)
	port: MatchPort?,
	squishyId: string,
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	radius: number,
	releaseAt: number,
	lastT: number, -- local time already swept
	maxT: number,
	fizzle: boolean,
	released: boolean,
	done: boolean,
	countsAsLive: boolean, -- throws count toward MaxActiveProjectilesPerPlayer; lanes do not
	hitOnce: { [any]: boolean }, -- lanes: victims / targets already hit
	endKind: Types.ImpactKind,
	-- Spec phase 5 (the Epic ultimates; nil / false for throws and lanes unless said):
	flyOn: boolean, -- a hit does not end it (lanes, the roller)
	floorY: number?, -- the floor its feet tests read
	clearHeight: number?, -- the roller's horizontal test and jump rule
	splashRadius: number?, -- a bubble: its pop becomes an area hit
	area: Area?, -- an area hit waiting for (or at) its time
	areaHits: number, -- victims / targets its area already hit
	charge: number?, -- feature 1: a throw's charge (ThrowStarted.power)
	crush: Crush?, -- feature 1: caught; it bursts at crush.burstAt (no more sweeping)
}

-- One area hit: at server time `at`, feet within `radius` of `center` (projected to the floor) are hit.
type Area = {
	center: Vector3, -- the drop point, or the pop point (its impacts are sent here)
	at: number,
	radius: number,
	endKind: Types.ImpactKind?, -- sent at the center when nobody is hit (nil: silent, a Rain Check drop)
	normal: Vector3?,
}

-- What this module needs from the outside world (useDeps). `send` fires a server -> client remote to a list of
-- recipients (non-players are skipped by NetService).
export type Deps = {
	now: () -> number,
	send: (remote: string, recipients: { any }, ...any) -> (),
	reportViolation: (player: any, remote: string) -> (),
	autoStep: boolean, -- false: no Heartbeat; the caller runs step(now)
}

-- A copy of one live projectile (projectileInfo).
export type ProjectileInfo = {
	projId: number,
	kind: ProjectileKind,
	ownerId: number,
	matchId: string?,
	squishyId: string,
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	radius: number,
	releaseAt: number,
	maxT: number,
	fizzle: boolean,
}

-- Feature 1: "caught" (an opponent's open catch window took the throw) and "burst" (a crush's burst, a hit on the
-- thrower by the catcher) are no ThrowImpact kinds.
type CandidateKind = Types.ImpactKind | "caught" | "burst"

type Candidate = {
	proj: Projectile,
	kind: CandidateKind,
	time: number,
	a: number, -- local time the projectile goes back to when the candidate is refused
	position: Vector3,
	normal: Vector3?,
	direction: Vector3, -- travel direction at impact (knockback)
	victim: Fighter?,
	targetId: string?,
	outcome: HitOutcome?,
	catcher: Fighter?, -- feature 1: "caught" and "burst"
}

-- Constants

local RULES = Config.Duel.Rules
local GUARD = Config.Combat.MovementGuard
local THROW_CFG = Config.Combat.Throw
local HITBOX = Config.Combat.Hitbox
-- §5.9: a lane tests the capsule of a player standing on the floor (axis floor + radius .. floor + radius + height),
-- whatever the HRP's height: the HRP height above the floor that puts the capsule's bottom cap on the floor.
local LANE_ROOT_HEIGHT = HITBOX.radius - HITBOX.bottomOffset
local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }
-- The guard runs while the arena is in play: Countdown (out of bounds = silent re-pivot), Active and SuddenDeath.
local GUARDED_PHASES: { [string]: boolean } = { Countdown = true, Active = true, SuddenDeath = true }
local HALF_BY_SIDE: { [string]: string } = { A = "HalfA", B = "HalfB" }
local MIN_STEP = 1e-6 -- studs: a shorter sub-step skips the Spherecast
local COUNTER_LOG_SECONDS = 300 -- reading: CombatLog counters are logged at most this often, when they changed
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_DUEL_PHASE = "SD_DuelPhase"
local REASON_CONTEXT = "throw.context"
local REMOTE_THROW = "ThrowRequest"
-- Feature 1 (2026-10-11).
local CATCH = Config.Combat.Catch
local REMOTE_CHARGE = "ChargeStart"
local REMOTE_CATCH = "CatchRequest"
local REMOTE_CATCH_EVENT = "CatchEvent"
local REASON_INVALID = "net.invalid"

-- Module table

local CombatService = {}

-- (info: HitInfo) after every applied duel hit, in impact order.
CombatService.Hit = Signal.new() :: Signal.Signal<HitInfo>
-- (info: HitInfo) when that hit eliminated the victim (0 lives, or the sudden-death hit).
CombatService.Eliminated = Signal.new() :: Signal.Signal<HitInfo>
-- (info: ThrowInfo) after every accepted throw (duel or practice).
CombatService.ThrowAccepted = Signal.new() :: Signal.Signal<ThrowInfo>

-- Private

local log = Log.new("Combat")

local ports: { [string]: MatchPort } = {} -- matchId -> port
local fighters: { [number]: Fighter } = {} -- userId -> fighter (registered matches only)
local portOf: { [Fighter]: MatchPort } = {}
local practiceActors: { [Player]: PracticeActor } = {}
local lastSeqs: { [number]: number } = {} -- userId -> last ThrowRequest seq (whole session)
local projectiles: { Projectile } = {}
local heartbeat: RBXScriptConnection? = nil
local nextProjId = 0
local stepping = false -- a step is running (syncTo from inside it is a no-op)
local lastStepAt = -math.huge -- the latest server time the projectiles were swept to

type Counters = {
	accepted: number,
	practiceAccepted: number,
	rejected: { [string]: number },
	originClamped: number,
	fizzles: number,
	impacts: { [string]: number },
	bySquishy: { [string]: { throws: number, hits: number, wins: number } },
	guardPivots: number,
	outOfBounds: number,
	catchWindows: number, -- feature 1: accepted catch presses
	catches: number,
	bursts: number,
}

local function newCounters(): Counters
	return {
		accepted = 0,
		practiceAccepted = 0,
		rejected = {},
		originClamped = 0,
		fizzles = 0,
		impacts = {},
		bySquishy = {},
		guardPivots = 0,
		outOfBounds = 0,
		catchWindows = 0,
		catches = 0,
		bursts = 0,
	}
end

local counters: Counters = newCounters()
local countersDirty = false

local function defaultDeps(): Deps
	return {
		now = function(): number
			return Workspace:GetServerTimeNow()
		end,
		send = function(remote: string, recipients: { any }, ...: any)
			NetService.fireMany(remote, recipients, ...)
		end,
		reportViolation = function(player: any, remote: string)
			if typeof(player) == "Instance" and player:IsA("Player") then
				NetService.reportViolation(player, remote)
			end
		end,
		autoStep = true,
	}
end

local deps: Deps = defaultDeps()

local function serverNow(): number
	return deps.now()
end

-- pcall for a function that returns nothing; the error (or nil) comes back as the second value.
local function try(fn: (...any) -> ...any, ...: any): (boolean, any)
	local ok, err = pcall(fn :: any, ...)
	return ok, err
end

local function squishyCounter(id: string): { throws: number, hits: number, wins: number }
	local entry = counters.bySquishy[id]
	if entry == nil then
		entry = { throws = 0, hits = 0, wins = 0 }
		counters.bySquishy[id] = entry
	end
	return entry
end

local function bump(map: { [string]: number }, key: string)
	map[key] = (map[key] or 0) + 1
	countersDirty = true
end

local function pingOf(player: Player?): number
	if player == nil then
		return 0
	end
	local ok, ping = pcall(function(): number
		return player:GetNetworkPing()
	end)
	return if ok and type(ping) == "number" then ping else 0
end

local function flatUnit(v: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-6 then
		return Vector3.zero
	end
	return flat.Unit
end

local function opponentOf(port: MatchPort, fighter: Fighter): Fighter?
	for _, other in port.fighters do
		if other ~= fighter then
			return other
		end
	end
	return nil
end

-- Real players of a match (the test dummy is never a recipient; NetService skips it too).
local function audienceOf(port: MatchPort): { Player }
	local list: { Player } = {}
	for _, fighter in port.fighters do
		local player = fighter.player
		if player then
			table.insert(list, player)
		end
	end
	return list
end

local function sendTo(proj: Projectile, remote: string, payload: { [string]: any }, at: Vector3)
	local port = proj.port
	if port then
		deps.send(remote, audienceOf(port), payload)
	else
		deps.send(remote, PracticeService.audience(at, proj.player), payload)
	end
end

local function practiceActorOf(player: Player, now: number?): PracticeActor
	local actor = practiceActors[player]
	if actor == nil then
		-- §5.2 "nextThrowAt is always finite": a new actor may throw from now (ThrowRejected echoes this value).
		local t = if now ~= nil then now else serverNow()
		actor = { nextThrowAt = t, activeProjectiles = 0, rootedUntil = -math.huge, windupUntil = -math.huge }
		practiceActors[player] = actor
	end
	return actor
end

-- The throw stats of the squishy a practising player has equipped (server state, never the client).
local function equippedThrow(player: Player): (string, ThrowStats)
	local id = InventoryService.getEquipped(player)
	local def = Catalog.get(id) or Catalog.get(Catalog.starterId())
	assert(def ~= nil, "[SD][Combat] the starter squishy is missing from the Catalog")
	return def.id, def.throw
end

-- Resolves a requestThrow / launch caller: a Player, a registered fighter, or a fighter's userId (the test dummy).
local function resolve(who: any): (Fighter?, Player?)
	if typeof(who) == "Instance" and who:IsA("Player") then
		return fighters[who.UserId], who
	end
	if type(who) == "number" then
		local fighter = fighters[who]
		return fighter, if fighter then fighter.player else nil
	end
	if type(who) == "table" and type(who.userId) == "number" then
		local fighter = fighters[who.userId]
		return fighter, if fighter then fighter.player else nil
	end
	return nil, nil
end

local function inMatchByAttribute(player: Player): (boolean, string?)
	local matchId = player:GetAttribute(ATTR_MATCH_ID)
	if type(matchId) == "string" and matchId ~= "" then
		local phase = player:GetAttribute(ATTR_DUEL_PHASE)
		return true, if type(phase) == "string" and phase ~= "" then phase else "Preparing"
	end
	return false, nil
end

-- Private: projectiles ----------------------------------------------------------------------------------------------

local step: (now: number) -> ()

local function ensureHeartbeat()
	if heartbeat == nil and deps.autoStep then
		heartbeat = RunService.Heartbeat:Connect(function()
			step(serverNow())
		end)
	end
end

local function addProjectile(proj: Projectile)
	table.insert(projectiles, proj)
	ensureHeartbeat()
end

local function finish(proj: Projectile)
	if proj.done then
		return
	end
	proj.done = true
	if proj.countsAsLive then
		local owner = proj.owner
		owner.activeProjectiles = math.max(0, owner.activeProjectiles - 1)
	end
end

local function geometryParams(proj: Projectile): RaycastParams?
	if proj.kind == "throw" then
		local port = proj.port
		return if port then port.arena.raycastParams else nil
	elseif proj.kind == "practice" then
		return PracticeService.raycastParams()
	end
	return nil -- lanes: E already stops at cover
end

local function insideBounds(proj: Projectile, position: Vector3): boolean
	local port = proj.port
	if port then
		local bounds = port.arena.zones.Bounds
		return bounds == nil or HitMath.inZone(position, bounds, 0)
	end
	return PracticeService.inBounds(position)
end

-- canDamage (§5.5): attacker and victim on different sides of the same live match, victim outside invulnerability
-- and with its HRP inside that arena's Bounds.
local function canDamage(
	port: MatchPort,
	attacker: Fighter,
	victim: Fighter,
	rootPosition: Vector3,
	at: number
): boolean
	if attacker == victim or attacker.side == victim.side then
		return false
	end
	if not port.canBeHit(victim, at) then
		return false
	end
	local bounds = port.arena.zones.Bounds
	return bounds == nil or HitMath.inZone(rootPosition, bounds, 0)
end

local function makeCandidate(
	proj: Projectile,
	kind: CandidateKind,
	s: ProjectileMath.SubStep,
	fraction: number,
	position: Vector3?
): Candidate
	local t = s.a + math.clamp(fraction, 0, 1) * (s.b - s.a)
	return {
		proj = proj,
		kind = kind,
		time = ProjectileMath.impactTime(proj.releaseAt, s.a, s.b, fraction),
		a = s.a,
		position = position or ProjectileMath.positionAt(proj.origin, proj.velocity, proj.gravity, t),
		normal = nil,
		direction = flatUnit(ProjectileMath.velocityAt(proj.velocity, proj.gravity, t)),
		victim = nil,
		targetId = nil,
		outcome = nil,
	}
end

-- The earliest impact inside one sub-step, or nil.
local function sweep(proj: Projectile, s: ProjectileMath.SubStep): Candidate?
	local best: Candidate? = nil
	local bestFraction = math.huge
	local delta = s.p1 - s.p0
	local length = delta.Magnitude

	-- 1. Geometry (Spherecast vs the slot's Geometry without Barriers, Default group).
	local params = geometryParams(proj)
	if params and length > MIN_STEP then
		local result = Workspace:Spherecast(s.p0, proj.radius, delta, params)
		if result then
			local fraction = math.clamp(result.Distance / length, 0, 1)
			local candidate = makeCandidate(proj, "geometry", s, fraction, result.Position)
			candidate.normal = result.Normal
			best, bestFraction = candidate, fraction
		end
	end
	-- Practice: the lane floor (the throw box stands on the lobby floor, not on a range part).
	if proj.kind == "practice" then
		local floorTop = PracticeService.floorY() + proj.radius
		if s.p1.Y <= floorTop then
			local fraction = if s.p0.Y <= floorTop then 0 else (s.p0.Y - floorTop) / (s.p0.Y - s.p1.Y)
			if fraction < bestFraction then
				local candidate = makeCandidate(proj, "geometry", s, fraction, nil)
				candidate.normal = Vector3.yAxis
				best, bestFraction = candidate, fraction
			end
		end
	end

	-- 1b. Feature 1: the opponent's open catch window, before the hit test (design: html:614-615). Only a normal duel
	-- throw is caught (never an ultimate, a lane or a practice throw); a tie with a capsule entry is the catch.
	local port = proj.port
	if port and proj.kind == "throw" then
		local catcher = opponentOf(port, proj.owner :: Fighter)
		local catcherRoot = if catcher then catcher.getRoot() else nil
		if catcher and catcherRoot and catcher.isAlive() and LIVE_PHASES[port.phase()] then
			local fMin, fMax = CatchRules.windowShare(
				catcher.catchOpensAt,
				catcher.catchClosesAt,
				proj.releaseAt + s.a,
				proj.releaseAt + s.b
			)
			if fMin ~= nil and fMax ~= nil then
				local centre = CatchRules.centre(catcherRoot.Position)
				local fraction = CatchRules.catchFraction(s.p0, s.p1, centre, CATCH.radiusStuds, fMin, fMax)
				if fraction and fraction < bestFraction then
					local candidate = makeCandidate(proj, "caught", s, fraction, nil)
					candidate.catcher = catcher
					best, bestFraction = candidate, fraction
				end
			end
		end
	end

	-- 2. Capsules.
	if port then
		local attacker = proj.owner :: Fighter
		local victim = opponentOf(port, attacker)
		local root = if victim then victim.getRoot() else nil
		if victim and root and not proj.hitOnce[victim] then
			local capsuleRoot = root.Position
			local fraction: number?
			local clearHeight = proj.clearHeight
			if clearHeight ~= nil then
				-- The Sprinkle Roller (spec phase 5): horizontal only, jumped once the feet clear clearHeight.
				if not UltRules.feetAbove(capsuleRoot, proj.floorY or port.arena.floorY, clearHeight) then
					fraction = UltRules.flatEntry(s.p0, s.p1, proj.radius, capsuleRoot)
				end
			else
				if proj.kind == "lane" then
					-- §5.9: axis floor + 1.3 .. floor + 4.8 even at the top of a jump (only X and Z of the HRP count).
					capsuleRoot = Vector3.new(capsuleRoot.X, port.arena.floorY + LANE_ROOT_HEIGHT, capsuleRoot.Z)
				end
				fraction = HitMath.capsuleEntry(s.p0, s.p1, proj.radius, HitMath.capsule(capsuleRoot))
			end
			if fraction and fraction < bestFraction then
				local at = ProjectileMath.impactTime(proj.releaseAt, s.a, s.b, fraction)
				if canDamage(port, attacker, victim, root.Position, at) then
					local candidate = makeCandidate(proj, "player", s, fraction, nil)
					candidate.victim = victim
					best, bestFraction = candidate, fraction
				end
			end
		end
	elseif proj.kind == "practice" or proj.kind == "practiceLane" or proj.kind == "practiceUlt" then
		local at = proj.releaseAt + s.b
		for _, target in PracticeService.targets() do
			if not proj.hitOnce[target.id] and not PracticeService.isTargetDown(target.id, at) then
				local bottom, top, radius = PracticeService.capsuleAt(target, at)
				local fraction: number?
				local clearHeight = proj.clearHeight
				if clearHeight ~= nil then
					-- The roller against a target: horizontal only (a target's feet are on its lane floor).
					local feetY = bottom.Y - radius
					if feetY - (proj.floorY or feetY) <= clearHeight then
						local box = { bottomOffset = 0, topOffset = 0, radius = radius }
						fraction = UltRules.flatEntry(s.p0, s.p1, proj.radius, bottom, box)
					end
				else
					fraction = HitMath.capsuleEntry(s.p0, s.p1, proj.radius, { a = bottom, b = top, radius = radius })
				end
				if fraction and fraction < bestFraction then
					local candidate = makeCandidate(proj, "target", s, fraction, nil)
					candidate.targetId = target.id
					best, bestFraction = candidate, fraction
				end
			end
		end
	end
	return best
end

-- An area hit at its time (spec phase 5): the first victim (or practice target) not hit yet whose feet are within its
-- radius of its floor point and that may be damaged then; nil when nobody is (left).
local function areaVictim(proj: Projectile, area: Area): Candidate?
	local floorPoint = Vector3.new(area.center.X, proj.floorY or area.center.Y, area.center.Z)
	local candidate: Candidate = {
		proj = proj,
		kind = "player",
		time = area.at,
		a = proj.lastT,
		position = area.center,
		normal = nil,
		direction = flatUnit(proj.velocity),
		victim = nil,
		targetId = nil,
		outcome = nil,
	}
	local port = proj.port
	if port then
		local attacker = proj.owner :: Fighter
		local victim = opponentOf(port, attacker)
		local root = if victim then victim.getRoot() else nil
		if
			victim
			and root
			and not proj.hitOnce[victim]
			and UltRules.feetWithin(root.Position, floorPoint, area.radius)
			and canDamage(port, attacker, victim, root.Position, area.at)
		then
			candidate.victim = victim
			local away = flatUnit(root.Position - area.center)
			if away ~= Vector3.zero then
				candidate.direction = away -- knockback away from the drop or the pop
			end
			return candidate
		end
		return nil
	end
	if proj.kind == "practiceUlt" then
		for _, target in PracticeService.targets() do
			if not proj.hitOnce[target.id] and not PracticeService.isTargetDown(target.id, area.at) then
				local bottom, _, radius = PracticeService.capsuleAt(target, area.at)
				if (bottom - Vector3.new(0, radius, 0) - floorPoint).Magnitude <= area.radius then
					candidate.kind = "target"
					candidate.targetId = target.id
					return candidate
				end
			end
		end
	end
	return nil
end

-- An area projectile's step: nothing before its time; then a victim, its end impact (a pop that hit nobody) or, when
-- nobody (else) is in reach, a silent finish.
local function areaStep(proj: Projectile, now: number): Candidate?
	local area = proj.area :: Area
	if now < area.at then
		return nil
	end
	local candidate = areaVictim(proj, area)
	if candidate then
		return candidate
	end
	local endKind = area.endKind
	if endKind == nil or proj.areaHits > 0 then
		finish(proj)
		return nil
	end
	return {
		proj = proj,
		kind = endKind :: Types.ImpactKind,
		time = area.at,
		a = proj.lastT,
		position = area.center,
		normal = area.normal,
		direction = flatUnit(proj.velocity),
	}
end

-- A Bubble Pop bubble pops where `at` says (its first contact, or the end of its flight): from now on it is an area hit.
local function pop(proj: Projectile, at: Candidate, now: number): Candidate?
	proj.area = {
		center = at.position,
		at = at.time,
		radius = proj.splashRadius or 0,
		-- (a bubble is an ultimate: never caught, so its first contact is an ImpactKind)
		endKind = if at.kind == "player" or at.kind == "target"
			then "expired"
			else (at.kind :: any) :: Types.ImpactKind,
		normal = at.normal,
	}
	return areaStep(proj, now)
end

-- Feature 1: a caught throw waits for its burst; at burstAt the burst is this step's candidate, a hit on the thrower by
-- the catcher that goes to the match owner with the step's hits (impact order, as any hit).
local function crushStep(proj: Projectile, crush: Crush, now: number): Candidate?
	if now < crush.burstAt then
		return nil
	end
	local root = crush.catcher.getRoot()
	return {
		proj = proj,
		kind = "burst",
		time = crush.burstAt,
		a = proj.lastT,
		position = if root then CatchRules.centre(root.Position) else crush.position,
		normal = nil,
		direction = Vector3.zero,
		victim = crush.thrower,
		targetId = nil,
		outcome = nil,
		catcher = crush.catcher,
	}
end

local function simulate(proj: Projectile, now: number): Candidate?
	if proj.done then
		return nil
	end
	local crush = proj.crush
	if crush ~= nil then
		return crushStep(proj, crush, now)
	end
	if proj.area ~= nil then
		return areaStep(proj, now)
	end
	if now < proj.releaseAt then
		return nil
	end
	if not proj.released then
		proj.released = true
		local port = proj.port
		local direction = flatUnit(proj.velocity)
		if port ~= nil and not LIVE_PHASES[port.phase()] then
			-- The match ended before the release: the throw is discarded (§5.6).
			return {
				proj = proj,
				kind = "expired",
				time = proj.releaseAt,
				a = 0,
				position = proj.origin,
				direction = direction,
			}
		end
		if proj.fizzle then
			return {
				proj = proj,
				kind = "fizzle",
				time = proj.releaseAt,
				a = 0,
				position = proj.origin,
				direction = direction,
			}
		end
	end

	local tNow = math.min(now - proj.releaseAt, proj.maxT)
	for _, s in ProjectileMath.subSteps(proj.origin, proj.velocity, proj.gravity, proj.lastT, tNow) do
		local candidate = sweep(proj, s)
		if candidate then
			if proj.splashRadius ~= nil then
				return pop(proj, candidate, now) -- a bubble pops at its first contact
			end
			return candidate -- lastT stays at this sub-step's start until the candidate is applied
		end
		proj.lastT = s.b
	end

	local position = ProjectileMath.positionAt(proj.origin, proj.velocity, proj.gravity, proj.lastT)
	if proj.lastT >= proj.maxT or not insideBounds(proj, position) then
		local ended: Candidate = {
			proj = proj,
			kind = proj.endKind,
			time = proj.releaseAt + proj.lastT,
			a = proj.lastT,
			position = position,
			direction = flatUnit(ProjectileMath.velocityAt(proj.velocity, proj.gravity, proj.lastT)),
		}
		if proj.splashRadius ~= nil then
			return pop(proj, ended, now) -- a bubble pops at cover or when its time is up
		end
		return ended
	end
	return nil
end

local function impactPayload(candidate: Candidate): { [string]: any }
	return {
		projId = candidate.proj.projId,
		kind = candidate.kind,
		position = candidate.position,
		normal = candidate.normal,
	}
end

-- A refused candidate: the projectile goes back to the sub-step start and is swept again next Heartbeat.
local function rewind(candidate: Candidate)
	candidate.proj.lastT = candidate.a
end

local function applyPlayerHit(candidate: Candidate)
	local proj = candidate.proj
	local outcome = candidate.outcome
	local victim = candidate.victim
	local port = proj.port
	if outcome == nil or victim == nil or port == nil then
		rewind(candidate)
		return
	end
	local attacker = proj.owner :: Fighter
	victim.invulnUntil = outcome.invulnUntil
	MovementRules.grace(victim.guard, candidate.time + GUARD.hitGraceSeconds) -- knockback is not over-speed
	attacker.hits += 1
	proj.hitOnce[victim] = true
	squishyCounter(attacker.squishyId).hits += 1
	bump(counters.impacts, "player")

	local payload = impactPayload(candidate)
	payload.victimId = victim.userId
	payload.livesLeft = outcome.lives
	payload.invulnUntil = outcome.invulnUntil
	payload.knockbackDir = candidate.direction
	payload.eliminated = outcome.eliminated
	if outcome.eliminated then
		local def = Catalog.get(attacker.squishyId)
		payload.effectId = if def then def.eliminationEffectId else "standard"
	end
	sendTo(proj, "ThrowImpact", payload, candidate.position)

	if proj.area ~= nil then
		proj.areaHits += 1 -- an area hit: the next step looks for anyone else in reach, then finishes
	end
	if proj.flyOn or proj.area ~= nil then
		rewind(candidate) -- a lane (or the roller) flies on to its end; this victim is never hit twice
	else
		finish(proj)
	end
	local info: HitInfo = {
		matchId = port.matchId,
		attacker = attacker,
		victim = victim,
		kind = proj.kind,
		projId = proj.projId,
		at = candidate.time,
		position = candidate.position,
		livesLeft = outcome.lives,
		eliminated = outcome.eliminated,
	}
	CombatService.Hit:fire(info)
	if outcome.eliminated then
		CombatService.Eliminated:fire(info)
	end
end

local function applyTargetHit(candidate: Candidate)
	local proj = candidate.proj
	local player = proj.player
	local targetId = candidate.targetId
	-- An ultimate's rehearsal hit (a lane or an Epic ultimate): the target reacts but it is not a throw (§5.11).
	local fromLane = proj.kind == "practiceLane" or proj.kind == "practiceUlt"
	if
		player == nil
		or targetId == nil
		or not PracticeService.registerHit(player, targetId, candidate.time, fromLane)
	then
		rewind(candidate)
		return
	end
	proj.hitOnce[targetId] = true
	bump(counters.impacts, "target")
	local payload = impactPayload(candidate)
	payload.targetId = targetId
	sendTo(proj, "ThrowImpact", payload, candidate.position)
	if proj.area ~= nil then
		proj.areaHits += 1
	end
	if proj.flyOn or proj.area ~= nil then
		rewind(candidate)
	else
		finish(proj)
	end
end

-- Feature 1: an opponent's open window took the throw. The window is used up (one catch each), so a second throw found
-- in the same step is refused here and flies on from its sub-step. The throw ends (no ThrowImpact, no longer a live
-- throw); its record stays as the crush until the burst (crushStep). CatchEvent "caught" goes to both duelists.
local function applyCatch(candidate: Candidate)
	local proj = candidate.proj
	local catcher = candidate.catcher
	local port = proj.port
	local at = candidate.time
	if catcher == nil or port == nil or at < catcher.catchOpensAt or at > catcher.catchClosesAt then
		rewind(candidate)
		return
	end
	local thrower = proj.owner :: Fighter
	catcher.catchOpensAt, catcher.catchClosesAt = -math.huge, -math.huge
	catcher.handsBackAt = math.max(catcher.handsBackAt, at + CATCH.handsBackSeconds)
	catcher.chargeStartAt = nil
	if proj.countsAsLive then
		proj.countsAsLive = false
		thrower.activeProjectiles = math.max(0, thrower.activeProjectiles - 1)
	end
	local burstAt = at + CATCH.crushSeconds
	proj.crush = {
		port = port,
		catcher = catcher,
		thrower = thrower,
		at = at,
		burstAt = burstAt,
		position = candidate.position,
	}
	counters.catches += 1
	bump(counters.impacts, "caught")
	local payload: Types.CatchEventPayload = {
		phase = "caught",
		matchId = port.matchId,
		catcherId = catcher.userId,
		throwerId = thrower.userId,
		projId = proj.projId,
		squishyId = proj.squishyId,
		position = candidate.position,
		at = at,
		burstAt = burstAt,
	}
	deps.send(REMOTE_CATCH_EVENT, audienceOf(port), payload)
end

-- Feature 1: the crush ends. With the match owner's outcome the thrower lost a life (Hit and Eliminated fire as for any
-- hit, kind "catch"); without one (the match had ended meanwhile) no life is lost. CatchEvent "burst" goes out either way.
local function applyBurst(candidate: Candidate)
	local proj = candidate.proj
	local crush = proj.crush
	finish(proj)
	if crush == nil then
		return
	end
	local port = crush.port
	local outcome = candidate.outcome
	counters.bursts += 1
	countersDirty = true
	local payload: Types.CatchEventPayload = {
		phase = "burst",
		matchId = port.matchId,
		catcherId = crush.catcher.userId,
		throwerId = crush.thrower.userId,
		projId = proj.projId,
		squishyId = proj.squishyId,
		position = candidate.position,
		at = crush.burstAt,
		burstAt = crush.burstAt,
		livesLeft = if outcome then outcome.lives else nil,
		invulnUntil = if outcome then outcome.invulnUntil else nil,
		eliminated = if outcome then outcome.eliminated else nil,
	}
	if outcome then
		crush.thrower.invulnUntil = outcome.invulnUntil
		crush.catcher.hits += 1
		bump(counters.impacts, "burst")
	end
	deps.send(REMOTE_CATCH_EVENT, audienceOf(port), payload)
	if outcome then
		local info: HitInfo = {
			matchId = port.matchId,
			attacker = crush.catcher,
			victim = crush.thrower,
			kind = "catch",
			projId = proj.projId,
			at = crush.burstAt,
			position = candidate.position,
			livesLeft = outcome.lives,
			eliminated = outcome.eliminated,
		}
		CombatService.Hit:fire(info)
		if outcome.eliminated then
			CombatService.Eliminated:fire(info)
		end
	end
end

local function applyCandidate(candidate: Candidate)
	local kind = candidate.kind
	if kind == "player" then
		applyPlayerHit(candidate)
	elseif kind == "target" then
		applyTargetHit(candidate)
	elseif kind == "caught" then
		applyCatch(candidate)
	elseif kind == "burst" then
		applyBurst(candidate)
	else
		if kind == "fizzle" then
			counters.fizzles += 1
		end
		bump(counters.impacts, kind)
		sendTo(candidate.proj, "ThrowImpact", impactPayload(candidate), candidate.position)
		finish(candidate.proj)
	end
end

-- Sends one match's player hits (found sweeping up to `now`) to its owner as one batch and stores the outcomes on the
-- candidates.
local function resolveHits(port: MatchPort, list: { Candidate }, now: number)
	local requests: { HitRequest } = {}
	for index, candidate in list do
		-- Feature 1: a crush's burst is the catcher's hit on the thrower (kind "catch", Catch.burstIgnoresInvuln).
		local burst = candidate.kind == "burst"
		requests[index] = {
			attacker = if burst then candidate.catcher :: Fighter else candidate.proj.owner,
			victim = candidate.victim :: Fighter,
			at = candidate.time,
			kind = if burst then "catch" else candidate.proj.kind,
			projId = candidate.proj.projId,
			position = candidate.position,
			force = if burst then CATCH.burstIgnoresInvuln == true else nil,
		}
	end
	local ok, outcomes = pcall(port.applyHits, requests, now)
	if not ok then
		log:error(`applyHits failed for match {port.matchId}:`, outcomes)
		return
	end
	for index, candidate in list do
		candidate.outcome = (outcomes :: { [number]: HitOutcome })[index]
	end
end

local function runStep(now: number)
	local candidates: { Candidate } = {}
	for _, proj in projectiles do
		local ok, result = pcall(simulate, proj, now)
		if not ok then
			log:error(`projectile {proj.projId} failed and was dropped:`, result)
			finish(proj)
		elseif result then
			table.insert(candidates, result)
		end
	end
	table.sort(candidates, function(x: Candidate, y: Candidate): boolean
		if x.time ~= y.time then
			return x.time < y.time
		end
		return x.proj.projId < y.proj.projId -- a stable order for equal times
	end)

	-- Duel hits go to their match in one batch per Heartbeat (DuelRules: impact order, simultaneous final hits); a
	-- crush's burst is one of them (feature 1).
	local hitsByPort: { [MatchPort]: { Candidate } } = {}
	for _, candidate in candidates do
		local port = candidate.proj.port
		if (candidate.kind == "player" or candidate.kind == "burst") and port then
			local list = hitsByPort[port]
			if list == nil then
				list = {}
				hitsByPort[port] = list
			end
			table.insert(list, candidate)
		end
	end
	for port, list in hitsByPort do
		resolveHits(port, list, now)
	end
	for _, candidate in candidates do
		local ok, err = try(applyCandidate, candidate)
		if not ok then
			log:error(`impact of projectile {candidate.proj.projId} failed:`, err)
			finish(candidate.proj)
		end
	end
	for port in hitsByPort do
		local ok, err = try(port.flush)
		if not ok then
			log:error(`flush failed for match {port.matchId}:`, err)
		end
	end

	-- Drop finished projectiles; stop the Heartbeat when none is left.
	local kept: { Projectile } = {}
	for _, proj in projectiles do
		if not proj.done then
			table.insert(kept, proj)
		end
	end
	projectiles = kept
	if #projectiles == 0 and heartbeat ~= nil then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

-- One simulation step. Never nested: a step that something inside a step asks for (a match owner's syncTo from an
-- effect) is skipped, the running one already covers that time.
step = function(now: number)
	if stepping then
		return
	end
	stepping = true
	lastStepAt = math.max(lastStepAt, now)
	local ok, err = pcall(runStep, now)
	stepping = false
	if not ok then
		log:error("simulation step failed:", err)
	end
end

-- Private: throws ---------------------------------------------------------------------------------------------------

local function newProjId(): number
	nextProjId += 1
	return nextProjId
end

local function duelState(fighter: Fighter, port: MatchPort, now: number): ThrowRules.ThrowState
	local root = fighter.getRoot()
	local arena = port.arena
	return {
		lastSeq = lastSeqs[fighter.userId] or 0,
		nextThrowAt = fighter.nextThrowAt,
		activeProjectiles = fighter.activeProjectiles,
		matchPhase = port.phase(),
		alive = fighter.isAlive(),
		rootCFrame = if root then root.CFrame else nil,
		rooted = now < fighter.rootedUntil,
		ownHalf = arena.zones[HALF_BY_SIDE[fighter.side]],
		ping = pingOf(fighter.player),
		throw = fighter.throw,
		cooldownMultiplier = port.cooldownMultiplier(),
		isClear = function(from: Vector3, to: Vector3): boolean
			return Workspace:Raycast(from, to - from, arena.raycastParams) == nil
		end,
		overlaps = function(origin: Vector3, radius: number): boolean
			return #Workspace:GetPartBoundsInRadius(origin, radius, arena.overlapParams) > 0
		end,
		-- Feature 1: the charge record, the hands (an open catch window or a crush) and the charge's floor.
		chargeStartAt = fighter.chargeStartAt,
		handsBusyUntil = math.max(fighter.catchClosesAt, fighter.handsBackAt),
		chargeFloorAt = math.max(fighter.handsBackAt, fighter.rootedUntil),
	}
end

local function practiceState(
	player: Player,
	actor: PracticeActor,
	throw: ThrowStats,
	now: number
): ThrowRules.ThrowState
	local root = CharacterService.getRoot(player)
	local inMatch, phase = inMatchByAttribute(player)
	local params = PracticeService.raycastParams()
	local overlap = PracticeService.overlapParams()
	return {
		lastSeq = lastSeqs[player.UserId] or 0,
		nextThrowAt = actor.nextThrowAt,
		activeProjectiles = actor.activeProjectiles,
		-- In a match that this module does not know (yet): ThrowRules rejects it as a non-live phase.
		matchPhase = if inMatch then phase else nil,
		alive = CharacterService.isAlive(player),
		rootCFrame = if root then root.CFrame else nil,
		rooted = now < actor.rootedUntil,
		practiceZone = PracticeService.zone(),
		practiceForward = PracticeService.forward(),
		ping = pingOf(player),
		throw = throw,
		cooldownMultiplier = 1,
		isClear = if params
			then function(from: Vector3, to: Vector3): boolean
				return Workspace:Raycast(from, to - from, params) == nil
			end
			else nil,
		overlaps = if overlap
			then function(origin: Vector3, radius: number): boolean
				return #Workspace:GetPartBoundsInRadius(origin, radius, overlap) > 0
			end
			else nil,
		chargeStartAt = actor.chargeStartAt, -- feature 1 (no catch in practice)
		chargeFloorAt = actor.rootedUntil,
	}
end

-- Public: matches ---------------------------------------------------------------------------------------------------

-- A fighter for a match. `spec` gives the identity and the server's view of the character; the throw state starts
-- empty. nextThrowAt starts at `spec.now` (default the clock), always finite (§5.2): no throw happens before Active
-- anyway (ThrowRules' phase check), and the match owner resets it to the Active start.
function CombatService.newFighter(spec: {
	userId: number,
	player: Player?,
	isTestDummy: boolean?,
	side: Side,
	squishyId: string,
	getRoot: () -> BasePart?,
	isAlive: () -> boolean,
	now: number?,
}): Fighter
	local def = Catalog.get(spec.squishyId) or Catalog.get(Catalog.starterId())
	assert(def ~= nil, "[SD][Combat] the starter squishy is missing from the Catalog")
	return {
		userId = spec.userId,
		player = spec.player,
		isTestDummy = spec.isTestDummy == true,
		side = spec.side,
		squishyId = def.id,
		throw = def.throw,
		getRoot = spec.getRoot,
		isAlive = spec.isAlive,
		nextThrowAt = if spec.now ~= nil then spec.now else serverNow(),
		activeProjectiles = 0,
		invulnUntil = -math.huge,
		rootedUntil = -math.huge,
		windupUntil = -math.huge,
		throwsAccepted = 0,
		hits = 0,
		guard = MovementRules.new(),
		chargeStartAt = nil,
		catchOpensAt = -math.huge,
		catchClosesAt = -math.huge,
		lastCatchPressAt = -math.huge,
		handsBackAt = -math.huge,
	}
end

-- Starts simulating and validating for this match. Its fighters become throw targets of each other only.
function CombatService.registerMatch(port: MatchPort)
	ports[port.matchId] = port
	for _, fighter in port.fighters do
		fighters[fighter.userId] = fighter
		portOf[fighter] = port
	end
end

-- Forgets the match: its remaining projectiles are dropped without impacts (the players are leaving the arena).
function CombatService.unregisterMatch(matchId: string)
	local port = ports[matchId]
	if port == nil then
		return
	end
	ports[matchId] = nil
	for _, fighter in port.fighters do
		if fighters[fighter.userId] == fighter then
			fighters[fighter.userId] = nil
		end
		portOf[fighter] = nil
	end
	for _, proj in projectiles do
		if proj.port == port then
			finish(proj)
		end
	end
end

-- The registered fighter of a Player or userId (nil outside a match).
function CombatService.getFighter(who: any): Fighter?
	local fighter = resolve(who)
	return fighter
end

-- The port of a registered fighter's match.
function CombatService.portOf(fighter: Fighter): MatchPort?
	return portOf[fighter]
end

-- The practice throw state of a player (AbilityService reads rootedUntil / windupUntil / nextThrowAt).
function CombatService.practiceActor(player: Player): PracticeActor
	return practiceActorOf(player)
end

-- Public: throws ----------------------------------------------------------------------------------------------------

-- Validates and, when accepted, launches one throw (§5.6). `who` is the Player (the ThrowRequest handler) or a
-- registered fighter / its userId (the Studio test dummy, §13.4 T2). Returns (accepted, reason?).
function CombatService.requestThrow(
	who: any,
	seq: unknown,
	aimDir: unknown,
	originHint: unknown,
	clientTime: unknown
): (boolean, string?)
	local now = serverNow()
	local fighter, player = resolve(who)
	local port = if fighter then portOf[fighter] else nil
	local input: ThrowRules.ThrowInput =
		{ seq = seq, aimDir = aimDir, originHint = originHint, clientTime = clientTime }

	local state: ThrowRules.ThrowState
	local thrower: any
	local userId: number
	local squishyId: string
	if fighter and port then
		-- The match's timers first (a press in the Countdown's last instant meets Active, one after the Active
		-- deadline meets Result or SuddenDeath), so the phase, nextThrowAt and the multiplier below are current.
		local sync = port.sync
		if sync then
			sync(now)
		end
		state = duelState(fighter, port, now)
		thrower = fighter
		userId = fighter.userId
		squishyId = fighter.squishyId
	elseif player then
		local actor = practiceActorOf(player, now)
		local id, throw = equippedThrow(player)
		state = practiceState(player, actor, throw, now)
		thrower = actor
		userId = player.UserId
		squishyId = id
	else
		bump(counters.rejected, REASON_CONTEXT)
		return false, REASON_CONTEXT
	end

	local decision = ThrowRules.validate(input, state, nil, now)
	lastSeqs[userId] = decision.lastSeq
	thrower.chargeStartAt = nil -- feature 1: a ThrowRequest uses up the charge record, accepted or not
	if not decision.ok then
		local reason = decision.reason or REASON_CONTEXT
		bump(counters.rejected, reason)
		if decision.violation and player then
			deps.reportViolation(player, REMOTE_THROW) -- §12 #1: a payload failure counts toward the abuse mute
		end
		if decision.seq ~= nil and player then
			deps.send("ThrowRejected", { player }, decision.seq, reason, decision.nextThrowAt)
		end
		return false, reason
	end

	local releaseAt = decision.releaseAt :: number
	local origin = decision.origin :: Vector3
	local velocity = decision.velocity :: Vector3
	local gravity = decision.gravity :: number
	local radius = decision.radius :: number
	thrower.nextThrowAt = decision.nextThrowAt
	thrower.activeProjectiles += 1
	thrower.windupUntil = releaseAt
	if decision.originClamped then
		counters.originClamped += 1
	end

	local kind: ProjectileKind = if decision.mode == "duel" then "throw" else "practice"
	local proj: Projectile = {
		projId = newProjId(),
		kind = kind,
		ownerId = userId,
		owner = thrower,
		player = player,
		port = if kind == "throw" then port else nil,
		squishyId = squishyId,
		origin = origin,
		velocity = velocity,
		gravity = gravity,
		radius = radius,
		releaseAt = releaseAt,
		lastT = 0,
		maxT = RULES.ProjectileMaxLifetime,
		fizzle = decision.fizzle == true,
		released = false,
		done = false,
		countsAsLive = true,
		hitOnce = {},
		endKind = "expired",
		flyOn = false,
		areaHits = 0,
		charge = decision.charge,
	}

	if kind == "throw" and fighter and port then
		fighter.throwsAccepted += 1
		counters.accepted += 1
		port.throwAccepted(fighter)
	elseif player then
		counters.practiceAccepted += 1
		PracticeService.registerThrow(player)
	end
	squishyCounter(squishyId).throws += 1
	countersDirty = true

	local payload: Types.ThrowStartedPayload = {
		seq = decision.seq :: number,
		nextThrowAt = decision.nextThrowAt,
		projId = proj.projId,
		matchId = if port and kind == "throw" then port.matchId else nil,
		throwerId = userId,
		squishyId = squishyId,
		kind = if kind == "throw" then "throw" else "practice",
		origin = origin,
		velocity = velocity,
		gravity = gravity,
		radius = radius,
		releaseAt = releaseAt, -- the server projectile's own spawn time
		power = decision.charge or 0, -- feature 1: the server's charge (the trail and the release)
	}
	sendTo(proj, "ThrowStarted", payload :: any, origin)
	addProjectile(proj)
	CombatService.ThrowAccepted:fire({
		userId = userId,
		player = player,
		matchId = payload.matchId,
		kind = payload.kind,
		squishyId = squishyId,
		projId = proj.projId,
		releaseAt = releaseAt,
	})
	return true, nil
end

-- Feature 1: records a charge start (ChargeStart) for `who` (a Player, or a registered fighter / its userId): the press
-- time in server time (lag-compensated as a throw's press, CatchRules.pressTime) on the duel fighter, else on the
-- practising player's actor; the next ThrowRequest measures its charge from it. Returns (recorded, reason?).
function CombatService.requestChargeStart(who: any, clientTime: unknown): (boolean, string?)
	local now = serverNow()
	local fighter, player = resolve(who)
	local holder: any = nil
	if fighter and portOf[fighter] then
		holder = fighter
	elseif player then
		holder = practiceActorOf(player, now)
	else
		return false, REASON_CONTEXT
	end
	local pressAt = CatchRules.pressTime(now, clientTime, pingOf(player))
	if pressAt == nil then
		if player then
			deps.reportViolation(player, REMOTE_CHARGE)
		end
		return false, REASON_INVALID
	end
	holder.chargeStartAt = pressAt
	return true, nil
end

-- Feature 1: one catch press (CatchRequest) by `who` (a Player, or a registered fighter / its userId), checked by
-- Logic/CatchRules against the server's state; accepted, it opens the window and drops a charge (design: html:344).
-- Returns (accepted, reason?).
function CombatService.requestCatch(who: any, clientTime: unknown): (boolean, string?)
	local now = serverNow()
	local fighter, player = resolve(who)
	local port = if fighter then portOf[fighter] else nil
	if port then
		local sync = port.sync
		if sync then
			sync(now) -- the match's timers first, so the phase below is the one at the request time
		end
	end
	local root = if fighter then fighter.getRoot() else nil
	local state: CatchRules.CatchState = {
		inDuel = fighter ~= nil and port ~= nil,
		matchPhase = if port then port.phase() else nil,
		alive = fighter ~= nil and fighter.isAlive(),
		hasRoot = root ~= nil,
		busyUntil = if fighter then fighter.handsBackAt else -math.huge,
		rooted = fighter ~= nil and now < fighter.rootedUntil,
		windup = fighter ~= nil and now < fighter.windupUntil,
		lastPressAt = if fighter then fighter.lastCatchPressAt else -math.huge,
		ping = pingOf(player),
	}
	local decision = CatchRules.validate({ clientTime = clientTime }, state, nil, now)
	if not decision.ok or fighter == nil then
		local reason = decision.reason or "catch.context"
		bump(counters.rejected, reason)
		if decision.violation and player then
			deps.reportViolation(player, REMOTE_CATCH)
		end
		return false, reason
	end
	fighter.lastCatchPressAt = decision.pressAt :: number
	fighter.catchOpensAt = decision.opensAt :: number
	fighter.catchClosesAt = decision.closesAt :: number
	fighter.chargeStartAt = nil
	counters.catchWindows += 1
	countersDirty = true
	return true, nil
end

-- Launches a Dragon Rush lane (AbilityService, §5.9): a straight sweep at `speed` from origin over `length` studs,
-- starting at releaseAt. Duel lanes test the caster's opponent with the normal canDamage; practice lanes test only
-- practice targets. Returns the projId (sent in UltimateEvent release).
function CombatService.launchLane(spec: LaneSpec): number
	local caster = spec.caster
	local port = if caster then portOf[caster] else nil
	local kind: ProjectileKind = if caster and port then "lane" else "practiceLane"
	local speed = math.max(spec.speed, 1e-3)
	local proj: Projectile = {
		projId = newProjId(),
		kind = kind,
		ownerId = if caster then caster.userId elseif spec.player then spec.player.UserId else 0,
		owner = caster or (if spec.player then practiceActorOf(spec.player) else nil),
		player = spec.player,
		port = port,
		squishyId = spec.squishyId,
		origin = spec.origin,
		velocity = spec.direction * speed,
		gravity = 0,
		radius = spec.radius,
		releaseAt = spec.releaseAt,
		lastT = 0,
		maxT = math.max(spec.length, 0) / speed,
		fizzle = false,
		released = false,
		done = false,
		countsAsLive = false,
		hitOnce = {},
		endKind = if spec.stoppedByGeometry then "geometry" else "expired",
		flyOn = true,
		areaHits = 0,
	}
	addProjectile(proj)
	return proj.projId
end

-- The owner, kind and match of an Epic ultimate's projectile (duel caster, or the practising player).
local function ultOwner(caster: Fighter?, player: Player?): (any, ProjectileKind, MatchPort?, number)
	local port = if caster then portOf[caster] else nil
	local kind: ProjectileKind = if caster and port then "ult" else "practiceUlt"
	local owner = caster or (if player then practiceActorOf(player) else nil)
	local ownerId = if caster then caster.userId elseif player then player.UserId else 0
	return owner, kind, port, ownerId
end

-- Launches an Epic ultimate's projectile (AbilityService, spec phase 5): a Flock Volley bird, the Sprinkle Roller or a
-- Bubble Pop bubble; a straight gravity-0 sweep from origin over `length` studs starting at releaseAt (see the header).
-- Duel ones test the caster's opponent with the normal canDamage, practice ones only practice targets. Returns the projId.
function CombatService.launchUlt(spec: UltSpec): number
	local owner: any, kind: ProjectileKind, port: MatchPort?, ownerId: number = ultOwner(spec.caster, spec.player)
	local speed = math.max(spec.speed, 1e-3)
	local proj: Projectile = {
		projId = newProjId(),
		kind = kind,
		ownerId = ownerId,
		owner = owner,
		player = spec.player,
		port = port,
		squishyId = spec.squishyId,
		origin = spec.origin,
		velocity = spec.direction * speed,
		gravity = 0,
		radius = spec.radius,
		releaseAt = spec.releaseAt,
		lastT = 0,
		maxT = math.max(spec.length, 0) / speed,
		fizzle = false,
		released = false,
		done = false,
		countsAsLive = false,
		hitOnce = {},
		endKind = if spec.stoppedByGeometry then "geometry" else "expired",
		flyOn = spec.flyOn == true,
		floorY = spec.floorY,
		clearHeight = spec.clearHeight,
		splashRadius = spec.splashRadius,
		areaHits = 0,
	}
	addProjectile(proj)
	return proj.projId
end

-- Schedules one area hit (a Rain Check drop, spec phase 5) at server time spec.at: the caster's opponent (or the
-- practice targets) whose feet are within spec.radius of spec.position is hit; a miss sends nothing. Returns the projId.
function CombatService.launchArea(spec: AreaSpec): number
	local owner: any, kind: ProjectileKind, port: MatchPort?, ownerId: number = ultOwner(spec.caster, spec.player)
	local proj: Projectile = {
		projId = newProjId(),
		kind = kind,
		ownerId = ownerId,
		owner = owner,
		player = spec.player,
		port = port,
		squishyId = spec.squishyId,
		origin = spec.position,
		velocity = Vector3.zero,
		gravity = 0,
		radius = spec.radius,
		releaseAt = spec.at,
		lastT = 0,
		maxT = 0,
		fizzle = false,
		released = true,
		done = false,
		countsAsLive = false,
		hitOnce = {},
		endKind = "expired",
		flyOn = false,
		floorY = spec.floorY,
		area = { center = spec.position, at = spec.at, radius = spec.radius, endKind = nil, normal = nil },
		areaHits = 0,
	}
	addProjectile(proj)
	return proj.projId
end

-- Live projectiles (all kinds) for Studio counts.
function CombatService.projectileCount(): number
	local count = 0
	for _, proj in projectiles do
		if not proj.done then
			count += 1
		end
	end
	return count
end

-- A copy of a live projectile (tests and Studio checks: its releaseAt is the one ThrowStarted carried), or nil.
function CombatService.projectileInfo(projId: number): ProjectileInfo?
	for _, proj in projectiles do
		if proj.projId == projId and not proj.done then
			local port = proj.port
			return {
				projId = proj.projId,
				kind = proj.kind,
				ownerId = proj.ownerId,
				matchId = if port then port.matchId else nil,
				squishyId = proj.squishyId,
				origin = proj.origin,
				velocity = proj.velocity,
				gravity = proj.gravity,
				radius = proj.radius,
				releaseAt = proj.releaseAt,
				maxT = proj.maxT,
				fizzle = proj.fizzle,
			}
		end
	end
	return nil
end

-- Runs one simulation step at server time `now` (default the clock). The Heartbeat calls it; tests call it directly
-- after useDeps({autoStep = false}).
function CombatService.step(now: number?)
	step(if now ~= nil then now else serverNow())
end

-- Sweeps every projectile up to server time `now` unless that is already done (a later or equal step ran), a step
-- is running (re-entry from a step's own effects) or nothing flies. The match owner calls it before it advances its
-- timers to `now` (DuelService.stepMatch), so no phase deadline ever fires before the hits that came before it.
function CombatService.syncTo(now: number)
	if stepping or not (now > lastStepAt) or #projectiles == 0 then
		return
	end
	step(now)
end

-- The latest server time the projectiles were swept to (-math.huge before the first step). Tests and Studio checks.
function CombatService.lastStepTime(): number
	return lastStepAt
end

-- Swaps the clock, the sender, the violation reporter and the Heartbeat switch (tests). Missing fields keep the live
-- default; nil restores every default.
function CombatService.useDeps(newDeps: {
	now: (() -> number)?,
	send: ((remote: string, recipients: { any }, ...any) -> ())?,
	reportViolation: ((player: any, remote: string) -> ())?,
	autoStep: boolean?,
}?)
	local base = defaultDeps()
	if newDeps then
		base.now = newDeps.now or base.now
		base.send = newDeps.send or base.send
		base.reportViolation = newDeps.reportViolation or base.reportViolation
		if newDeps.autoStep ~= nil then
			base.autoStep = newDeps.autoStep
		end
	end
	deps = base
	lastStepAt = -math.huge -- a new clock: the old step times mean nothing on it
	if not deps.autoStep and heartbeat ~= nil then
		heartbeat:Disconnect()
		heartbeat = nil
	elseif deps.autoStep and #projectiles > 0 then
		ensureHeartbeat()
	end
end

-- Public: movement ----------------------------------------------------------------------------------------------------

-- Moves a fighter's character so its HumanoidRootPart is at `cf` (velocity cleared) and starts the guard's teleport
-- grace, so the move itself never counts as over-speed. False without a character.
function CombatService.pivotFighter(fighter: Fighter, cf: CFrame): boolean
	local root = fighter.getRoot()
	local model = if root then root.Parent else nil
	if model == nil or not model:IsA("Model") then
		return false
	end
	model:PivotTo(cf)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	CombatService.noteTeleport(fighter)
	return true
end

-- Starts the guard's teleport grace after a server move done elsewhere (DuelService's pad teleports).
function CombatService.noteTeleport(fighter: Fighter)
	MovementRules.grace(fighter.guard, serverNow() + GUARD.teleportGraceSeconds)
end

-- One movement-guard sample of one fighter (§5.7): pivot back, or hand an out-of-bounds to the match owner.
local function guardFighter(port: MatchPort, fighter: Fighter, now: number)
	if fighter.player == nil or not fighter.isAlive() then
		return -- the Studio test dummy is never guarded
	end
	local root = fighter.getRoot()
	local zones = port.arena.zones
	local own = zones[HALF_BY_SIDE[fighter.side]]
	if root == nil or own == nil then
		return
	end
	local opponentHalf = zones[HALF_BY_SIDE[if fighter.side == "A" then "B" else "A"]]
	local insideGeometry = #Workspace:GetPartBoundsInBox(
			root.CFrame,
			GUARD.geometryProbeSize,
			port.arena.overlapParams
		) > 0
	-- Held in place: the Countdown freeze on the own pad, or a Dragon Rush root (telegraph + recovery) where the
	-- player stands, with the stopping distance a root that starts mid-run takes to reach this server.
	local countdown = port.phase() == "Countdown"
	local rooted = now < fighter.rootedUntil
	local holdAt: Vector3? = nil
	if countdown then
		local pad = port.placement(fighter)
		holdAt = if pad then pad.Position else nil
	end
	local holdSlack = if rooted and not countdown
		then RULES.Movement.WalkSpeed * math.min(pingOf(fighter.player), THROW_CFG.originPingCapSeconds)
		else 0
	local verdict = MovementRules.evaluate(fighter.guard, {
		position = root.Position,
		insideGeometry = insideGeometry,
		held = countdown or rooted,
		holdAt = holdAt,
		holdSlack = holdSlack,
	}, { own = own, neutral = zones.Neutral, opponent = opponentHalf, floorY = port.arena.floorY }, now)
	if verdict.action == "pivotBack" then
		counters.guardPivots += 1
		countersDirty = true
		local target = verdict.target
		local cf = if target then CFrame.new(target) * root.CFrame.Rotation else port.placement(fighter)
		if cf then
			CombatService.pivotFighter(fighter, cf)
		end
	elseif verdict.action == "outOfBounds" then
		counters.outOfBounds += 1
		countersDirty = true
		port.outOfBounds(fighter)
	end
end

-- One guard pass over every registered match (run at Config.Combat.MovementGuard.checkHz by start()).
function CombatService.guardStep(now: number?)
	local t = if now ~= nil then now else serverNow()
	for _, port in table.clone(ports) do
		if GUARDED_PHASES[port.phase()] then
			for _, fighter in port.fighters do
				local ok, err = try(guardFighter, port, fighter, t)
				if not ok then
					log:error(`movement guard failed for user {fighter.userId}:`, err)
				end
			end
		end
	end
end

-- Public: CombatLog ---------------------------------------------------------------------------------------------------

-- A win for this squishy (DuelService, at Result).
function CombatService.recordWin(squishyId: string)
	squishyCounter(squishyId).wins += 1
	countersDirty = true
end

-- A copy of the CombatLog counters (§12 #23).
function CombatService.counters(): { [string]: any }
	local bySquishy: { [string]: any } = {}
	for id, entry in counters.bySquishy do
		bySquishy[id] = table.clone(entry)
	end
	return {
		accepted = counters.accepted,
		practiceAccepted = counters.practiceAccepted,
		rejected = table.clone(counters.rejected),
		originClamped = counters.originClamped,
		fizzles = counters.fizzles,
		impacts = table.clone(counters.impacts),
		bySquishy = bySquishy,
		guardPivots = counters.guardPivots,
		outOfBounds = counters.outOfBounds,
		catchWindows = counters.catchWindows,
		catches = counters.catches,
		bursts = counters.bursts,
		projectiles = CombatService.projectileCount(),
		matches = (function(): number
			local n = 0
			for _ in ports do
				n += 1
			end
			return n
		end)(),
	}
end

local function logCounters()
	if not countersDirty then
		return
	end
	countersDirty = false
	local parts: { string } = {
		string.format(
			"accepted=%d practice=%d originClamped=%d fizzles=%d guardPivots=%d oob=%d catchWindows=%d catches=%d bursts=%d",
			counters.accepted,
			counters.practiceAccepted,
			counters.originClamped,
			counters.fizzles,
			counters.guardPivots,
			counters.outOfBounds,
			counters.catchWindows,
			counters.catches,
			counters.bursts
		),
	}
	for reason, count in counters.rejected do
		table.insert(parts, `rejected[{reason}]={count}`)
	end
	for id, entry in counters.bySquishy do
		table.insert(parts, `{id}: throws={entry.throws} hits={entry.hits} wins={entry.wins}`)
	end
	log:info("CombatLog", table.concat(parts, "; "))
end

-- Lifecycle

function CombatService.init()
	NetService.on("ThrowRequest", function(player: Player, seq: any, aimDir: any, originHint: any, clientTime: any)
		CombatService.requestThrow(player, seq, aimDir, originHint, clientTime)
	end)
	-- Feature 1 (2026-10-11): the charge start and the catch press.
	NetService.on(REMOTE_CHARGE, function(player: Player, clientTime: any)
		CombatService.requestChargeStart(player, clientTime)
	end)
	NetService.on(REMOTE_CATCH, function(player: Player, clientTime: any)
		CombatService.requestCatch(player, clientTime)
	end)
end

function CombatService.start()
	task.spawn(function()
		while true do
			task.wait(COUNTER_LOG_SECONDS)
			local ok, err = try(logCounters)
			if not ok then
				log:error("CombatLog failed:", err)
			end
		end
	end)
	local interval = 1 / GUARD.checkHz
	while true do
		task.wait(interval)
		CombatService.guardStep()
	end
end

function CombatService.playerRemoving(player: Player)
	practiceActors[player] = nil
	lastSeqs[player.UserId] = nil
end

-- Not called by the bootstrap; used by leak checks.
function CombatService.destroy()
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	table.clear(projectiles)
	table.clear(ports)
	table.clear(fighters)
	table.clear(portOf)
	table.clear(practiceActors)
	table.clear(lastSeqs)
	stepping = false
	lastStepAt = -math.huge
	counters = newCounters()
	countersDirty = false
	CombatService.Hit:disconnectAll()
	CombatService.Eliminated:disconnectAll()
	CombatService.ThrowAccepted:disconnectAll()
end

return CombatService
