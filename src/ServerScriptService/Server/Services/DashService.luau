--!strict
-- DashService (server only). Spec phase 5 §3.3: the dash (design numbers in Config.Duel.Rules.Dash).
-- The dasher's own client moves its HumanoidRootPart (it owns its physics, like knockback) and predicts at once; the
-- server only decides whether the dash is legal and how far it may go:
-- * DashRequest(seq, dir, clientTime) (and the Studio test dummy, through requestDash) is checked by Logic/DashRules
--   with the server's own state: a registered duel (brought up to the request time first, port.sync) in Active or
--   SuddenDeath with the dasher in its own half + Config.Combat.Throw.zoneToleranceStuds, or the practice range
--   (PracticeService.isPracticing); alive with a server HRP; not rooted by an ultimate (telegraph or recovery), not in
--   a throw windup and not crushing a caught toy (feature 1, CombatService's handsBackAt); on the ground;
--   cooldownSeconds since the last accepted dash; a flat unit direction. The end point
--   is cut at cover (a Spherecast of bodyRadiusStuds from the server HRP against the place's Geometry without Barriers)
--   and kept bodyRadiusStuds inside the own half (practice: PracticeTargets.BOUNDS), so it never reaches the neutral
--   band (Shared/DashMath.clampToZone, the client's own prediction uses the same clamp).
-- * Accepted: DashStarted {userId, dir, from, to, startAt} to the match's players (practice: players within
--   Config.Combat.Projectile.practiceBroadcastStuds and the dasher), so the other clients play the pose and effects;
--   a duel dasher's movement guard gets the dash's own studs (+ guardSlackStuds) once, from guardLeadSeconds before the
--   request to seconds + guardTailSeconds after it (MovementRules.allowDash). No i-frames, nothing else changes.
-- * Refused: nothing is sent (the client's gate mirrors these rules, so an honest client is refused only at a race);
--   a payload failure counts toward NetService's abuse mute. A refused dash gets no guard allowance: whatever the
--   client moved stays under the normal movement guard.
-- * FFA/TDM v1 (2026-10-15, MatchService on Diego's DuelMaps; SPEC D16): for a port with `ffa = true` (an open map, no
--   halves) the place check and the end clamp use the map's Bounds, and the ground check measures from the ground under
--   the dasher (CombatService.groundUnder: a downward cast from the server HRP against the map's RaycastParams; no
--   hit: the map floor), so a dash works on the maps' raised platforms. Duel ports keep every line of the 1v1 path.
--   Review fix (2026-10-15): the cast is a Spherecast of the body's radius, not a thin ray, so a dasher whose HRP
--   centre is just past a platform edge (the Humanoid still stands on it, and the client's FloorMaterial gate passes)
--   is on the ground here too; the probe and its length live in CombatService, shared with AbilityService.
-- * Power-ups v1.1 (2026-10-16): on an ffa port whose optional port.dashCooldownFree(fighter) says so (MatchService:
--   the dash boost lives), the cooldown is skipped; every other check stays, and the accepted dash still records
--   lastDashAt, so the cooldown counts from the last boosted dash once the boost ends. Review fix (2026-10-16): one
--   dash after the other, not any number at once: a boosted dash waits until the last one's pose clip has played
--   (DashMath.eventSeconds(visualFrames), 0.4 s, with DashRules' cooldownToleranceSeconds), as the client's gate
--   already does (its dash lives at least that long). At most 2.5 dashes a second: under the DashRequest bucket.
-- Per player (userId) for the session: lastSeq and lastDashAt; playerRemoving forgets them.
-- Tests swap the clock, the sender, the violation reporter, the Spherecast and the ground probe with useDeps.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DashMath = require(Shared.DashMath)
local PracticeTargets = require(Shared.Practice.PracticeTargets)
local Types = require(Shared.Types)
local Logic = script.Parent.Parent.Logic
local DashRules = require(Logic.DashRules)
local MovementRules = require(Logic.MovementRules)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)
local NetService = require(script.Parent.NetService)
local PracticeService = require(script.Parent.PracticeService)

-- Types

type Zone = Types.ArenaZone

-- What this module needs from the outside world (useDeps).
export type Deps = {
	now: () -> number,
	send: (remote: string, recipients: { any }, ...any) -> (),
	reportViolation: (player: any, remote: string) -> (),
	-- The distance at which a sphere of `radius` moved from `origin` along `direction` meets Geometry (Spherecast).
	cast: (origin: Vector3, radius: number, direction: Vector3, params: RaycastParams) -> number?,
	-- FFA/TDM v1: the height of the first ground at most `distance` studs below `origin`, or nil
	-- (CombatService.groundProbe, a body-radius Spherecast).
	ground: CombatService.GroundProbe,
}

type DasherState = { lastSeq: number, lastDashAt: number }

-- Constants

local DASH = Config.Duel.Rules.Dash
-- Power-ups v1.1 review fix: the dash boost's spacing, the dash's pose clip (the client's CLIP_SECONDS).
local BOOST_SPACING_SECONDS = DashMath.eventSeconds(DASH.visualFrames)
local HALF_BY_SIDE: { [string]: string } = { A = "HalfA", B = "HalfB" }
local REMOTE_DASH = "DashRequest"
local REMOTE_STARTED = "DashStarted"
local REASON_CONTEXT = "dash.context"

-- Module table

local DashService = {}

-- Private

local states: { [number]: DasherState } = {} -- userId -> state

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
		cast = function(origin: Vector3, radius: number, direction: Vector3, params: RaycastParams): number?
			local hit = Workspace:Spherecast(origin, radius, direction, params)
			return if hit then hit.Distance else nil
		end,
		ground = function(origin: Vector3, distance: number, params: RaycastParams): number?
			return CombatService.groundProbe(origin, distance, params)
		end,
	}
end

local deps: Deps = defaultDeps()

local function stateOf(userId: number): DasherState
	local state = states[userId]
	if state == nil then
		state = { lastSeq = 0, lastDashAt = -math.huge }
		states[userId] = state
	end
	return state
end

-- The cover query for DashRules: a Spherecast of the body radius along the flat dir.
local function caster(params: RaycastParams?): ((origin: Vector3, dir: Vector3, distance: number) -> number?)?
	if params == nil then
		return nil
	end
	return function(origin: Vector3, dir: Vector3, distance: number): number?
		return deps.cast(origin, DASH.bodyRadiusStuds, dir * distance, params)
	end
end

-- Public

-- Validates and accepts one dash (spec phase 5 §3.3). `who` is the Player (DashRequest) or a registered fighter / its
-- userId (the Studio test dummy). Returns (accepted, reason?).
-- Practice bot (2026-10-16): an accepted dash also returns its end point `to` (the bot moves its own root there, as a
-- player's client does).
function DashService.requestDash(
	who: any,
	seq: unknown,
	dir: unknown,
	clientTime: unknown
): (boolean, string?, Vector3?)
	local now = deps.now()
	local fighter = CombatService.getFighter(who)
	local player: Player? = if fighter
		then fighter.player
		elseif typeof(who) == "Instance" and who:IsA("Player") then who
		else nil
	local userId = if fighter then fighter.userId elseif player then player.UserId else nil
	if userId == nil then
		return false, REASON_CONTEXT
	end
	local memory = stateOf(userId)

	local state: DashRules.DashState
	local port = if fighter then CombatService.portOf(fighter) else nil
	if fighter and port then
		local sync = port.sync
		if sync then
			sync(now) -- the match's timers first, so the phase below is the one at the request time
		end
		local root = fighter.getRoot()
		state = {
			lastSeq = memory.lastSeq,
			lastDashAt = memory.lastDashAt,
			mode = "duel",
			matchPhase = port.phase(),
			alive = fighter.isAlive(),
			rootPosition = if root then root.Position else nil,
			floorY = port.arena.floorY,
			rooted = now < fighter.rootedUntil,
			windup = now < fighter.windupUntil,
			crushing = now < fighter.handsBackAt, -- feature 1 (user decision 2026-10-11: no dash while crushing)
			zone = port.arena.zones[HALF_BY_SIDE[fighter.side] or ""],
			cast = caster(port.arena.raycastParams),
		}
		if port.ffa then
			-- FFA/TDM v1 (server_map D1, SPEC D16): no halves (the place check and the end clamp use Bounds) and the
			-- ground under the dasher, so a dash on a platform is not "airborne".
			state.zone = port.arena.zones.Bounds
			state.floorY = CombatService.groundUnder(port.arena, if root then root.Position else nil, deps.ground)
			-- Power-ups v1.1 (2026-10-16): the dash boost: no cooldown while it lives. Review fix: DashRules' cooldown
			-- check then waits BOOST_SPACING_SECONDS after the last dash instead of cooldownSeconds (one at a time).
			local cooldownFree = port.dashCooldownFree
			if cooldownFree and cooldownFree(fighter) then
				state.lastDashAt = memory.lastDashAt - DASH.cooldownSeconds + BOOST_SPACING_SECONDS
			end
		end
	elseif player and PracticeService.isPracticing(player) then
		local actor = CombatService.practiceActor(player)
		local root = CharacterService.getRoot(player)
		local bounds = PracticeTargets.BOUNDS
		state = {
			lastSeq = memory.lastSeq,
			lastDashAt = memory.lastDashAt,
			mode = "practice",
			matchPhase = nil,
			alive = CharacterService.isAlive(player),
			rootPosition = if root then root.Position else nil,
			floorY = PracticeService.floorY(),
			rooted = now < actor.rootedUntil,
			windup = now < actor.windupUntil,
			zone = { cframe = CFrame.new(bounds.position), size = bounds.size },
			cast = caster(PracticeService.raycastParams()),
		}
	else
		-- Neither a registered duel nor the practice range (NetService already dropped a replayed seq).
		return false, REASON_CONTEXT
	end

	local decision = DashRules.validate({ seq = seq, dir = dir, clientTime = clientTime }, state, nil, now)
	memory.lastSeq = decision.lastSeq
	if not decision.ok then
		if decision.violation and player then
			deps.reportViolation(player, REMOTE_DASH)
		end
		return false, decision.reason
	end

	memory.lastDashAt = now
	local from = decision.from :: Vector3
	local to = decision.to :: Vector3
	local distance = decision.distance :: number
	if fighter then
		MovementRules.allowDash(
			fighter.guard,
			now - DASH.guardLeadSeconds,
			now + DASH.seconds + DASH.guardTailSeconds,
			distance + DASH.guardSlackStuds
		)
	end
	local payload: Types.DashStartedPayload = {
		userId = userId,
		dir = decision.dir :: Vector3,
		from = from,
		to = to,
		startAt = now,
	}
	local recipients: { any } = {}
	if port then
		for _, participant in port.fighters do
			if participant.player then
				table.insert(recipients, participant.player)
			end
		end
	else
		recipients = PracticeService.audience(from, player)
	end
	deps.send(REMOTE_STARTED, recipients, payload)
	return true, nil, to
end

-- Swaps the clock, the sender, the violation reporter, the Spherecast and the ground probe (tests). Missing fields keep
-- the live default; nil restores every default.
function DashService.useDeps(newDeps: {
	now: (() -> number)?,
	send: ((remote: string, recipients: { any }, ...any) -> ())?,
	reportViolation: ((player: any, remote: string) -> ())?,
	cast: ((origin: Vector3, radius: number, direction: Vector3, params: RaycastParams) -> number?)?,
	ground: ((origin: Vector3, distance: number, params: RaycastParams) -> number?)?,
}?)
	local base = defaultDeps()
	if newDeps then
		base.now = newDeps.now or base.now
		base.send = newDeps.send or base.send
		base.reportViolation = newDeps.reportViolation or base.reportViolation
		base.cast = newDeps.cast or base.cast
		base.ground = newDeps.ground or base.ground
	end
	deps = base
end

-- Lifecycle

function DashService.init()
	NetService.on(REMOTE_DASH, function(player: Player, seq: any, dir: any, clientTime: any)
		DashService.requestDash(player, seq, dir, clientTime)
	end)
end

function DashService.playerRemoving(player: Player)
	states[player.UserId] = nil
end

return DashService
