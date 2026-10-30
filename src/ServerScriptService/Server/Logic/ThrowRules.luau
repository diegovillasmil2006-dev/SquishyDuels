--!strict
-- ThrowRules: validation of one ThrowRequest (DESIGN §5.6; §12 #2, #5, #7, #8, #9, #10). Server only, pure (no
-- instances, no yields; the two world queries come in as adapter functions). Used by CombatService for duels and by
-- the practice range (same remote, same validator, §5.11).
--
-- Checks, cheapest first; the first failure rejects with a reason code (§2.10):
--   1. Rate bucket (Config.Net.Remotes.ThrowRequest, burst 4, 3/s): NetService drops silently, before this module.
--   2. Types: seq an integer with lastSeq < seq < lastSeq + seqWindow; aimDir, originHint finite Vector3s;
--      clientTime a server timestamp (Util/Validate.serverTime) .................................. net.invalid
--   3. Context: in a match in Active/SuddenDeath, or (not in a match) HRP inside the practice zone .. throw.context
--   4. Alive and server HRP present ............................................................ throw.context
--      not rooted by Dragon Rush (telegraph or recovery) ........................................ throw.rooted
--   5. Position: duel HRP inside own half + zoneToleranceStuds (X, Z); practice inside the zone .. throw.context
--   6. Direction: |aimDir| in [0.95, 1.05], pitch in [-35°, +65°]; practice: flat aim within 75° of the range's
--      forward ......................................................................................... throw.direction
--   7. Latency: lat = clamp(now - clientTime, 0, min(ping/2 + 0.03, 0.12)); abnormal clientTime (more than 0.05 s
--      ahead or 1 s behind) -> lat = min(ping/2, 0.12). releaseAt = now - lat + windup (always in the future).
--  7b. Hands (feature 1, 2026-10-11): the press (now - lat) is not before handsBusyUntil (a catch window or a crush,
--      Config.Combat.Catch; design: html:323 throws only from the hold) ........................................ throw.busy
--   8. Cooldown: releaseAt >= nextThrowAt - CooldownToleranceSeconds ......................... throw.cooldown
--   9. Live projectiles < MaxActiveProjectilesPerPlayer ............................................. throw.tooMany
--  10. Origin: originHint within 4 + 22·min(ping, 0.25) studs of serverHRP.CFrame * ReleaseOffset (a farther one is
--      pulled back to that distance, toward the hint: a lag spike only nudges a walker's throw), in line of sight from
--      the HRP (adapter) and inside the same zone as check 5; else the server origin. originClamped = not the hint.
--  11. Spawn overlap (adapter, GetPartBoundsInRadius vs Geometry without Barriers): accepted with fizzle = true; the
--      throw still uses its cooldown.
--  12. Accept: nextThrowAt = releaseAt + clamp(cooldown, CooldownClamp) × cooldownMultiplier (SuddenDeath 0.8).
--      Feature 1 (2026-10-11): the charge c = Shared/ThrowCharge.measure(chargeStartAt, press, ready): from the
--      server's own record of the charge start (ChargeStart, lag-compensated like this press) or from the moment the
--      throw was ready (nextThrowAt - windup, and not before chargeFloorAt), whichever is later, clamped 0..1 (no
--      record = 0); velocity = direction × speed × (1 + speedGain·c) (Config.Combat.Charge; design: html:330). The
--      client never sends a charge or a speed.
--      Power-ups v1.1 (2026-10-16): × state.speedMultiplier too (the Free for All / Team Deathmatch throw boost,
--      Config.Match.PowerUps.kinds.throwBoost; nil = 1, duels and practice never set it). The clamp comes first and the
--      multiplier after, so the rapid throw's multiplier (MatchService, review fix 2026-10-16) is Min / the clamped
--      cooldown there: its cooldown is exactly CooldownClamp.Min, the shortest one (a multiplier of 0 would be none).
-- Rejections echo the seq (when it was valid) and the unchanged nextThrowAt for ThrowRejected(seq, reason, nextThrowAt).
-- The thrown squishy's stats always come from the server (the match snapshot), never from the client (§12 #3).
--
-- API:
--   ThrowRules.validate(input, state, cfg?, now)                -> Decision (state is never modified)
--   ThrowRules.apply(state, decision)                           writes lastSeq (and nextThrowAt on accept) back
--   ThrowRules.lagCompensation(now, clientTime, ping, cfg?)     -> seconds (check 7)
--   ThrowRules.isExpired(releaseAt, now, position, bounds?, cfg?) -> boolean (§12 #10: lifetime or outside Bounds)
-- `cfg` is a table with Config's Combat and Duel sections (a test's copy of Config); nil = the live Config.
--
-- Readings (DESIGN names no code for them): a wrong zone (check 5) rejects with throw.context, the "blocked" reticle
-- state of §5.10; rooted (check 4) uses throw.rooted, the extra Strings reason code the client reticle also shows
-- (it is not in the §2.10 list). A payload failure (check 2) is flagged `violation` for NetService's abuse count;
-- when seq itself is invalid there is no seq to echo, so no ThrowRejected is sent. lastSeq advances as soon as seq
-- passes check 2, even if a later check rejects, so a request can never be replayed. A zone check for the origin
-- hint uses the same zone and margin as check 5. Pitch limits allow PITCH_EPSILON_DEG for float error (the client's
-- solveLaunchDir clamps to exactly the limit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ThrowCharge = require(ReplicatedStorage.Shared.ThrowCharge)
local Types = require(ReplicatedStorage.Shared.Types)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local HitMath = require(script.Parent.HitMath)

-- Types

type Zone = Types.ArenaZone

export type Mode = "duel" | "practice"

-- Server-side throw stats (a Catalog `throw` table from the match snapshot or the equipped squishy).
export type ThrowStats = { speed: number, gravity: number, radius: number, cooldown: number, windup: number }

-- The raw remote arguments, exactly as received (unknown until check 2 narrows them).
export type ThrowInput = { seq: unknown, aimDir: unknown, originHint: unknown, clientTime: unknown }

-- What the server knows about the thrower when the request arrives. CombatService keeps lastSeq, nextThrowAt and
-- activeProjectiles per player; the rest is read fresh for each request.
export type ThrowState = {
	lastSeq: number, -- 0 before the first throw of the session
	nextThrowAt: number, -- server time; reset to `now` at Active start
	activeProjectiles: number, -- live projectiles of this player (including ones still in windup)
	matchPhase: string?, -- the thrower's match phase (Types.DuelPhase); nil when not in a match
	alive: boolean,
	rootCFrame: CFrame?, -- server HumanoidRootPart CFrame; nil = missing
	rooted: boolean?, -- Dragon Rush telegraph or recovery
	ownHalf: Zone?, -- duel: Zones/HalfA or Zones/HalfB of the match's arena slot
	practiceZone: Zone?, -- the SD_PracticeZone box (lobby)
	practiceForward: Vector3?, -- the range's forward (WorldLayout.PracticeRange.throwDirection, +X); nil fails closed
	ping: number, -- Player:GetNetworkPing(), seconds (round trip); non-finite or negative counts as 0
	throw: ThrowStats,
	cooldownMultiplier: number?, -- DuelRules.cooldownMultiplier (SuddenDeath 0.8); nil = 1
	isClear: ((from: Vector3, to: Vector3) -> boolean)?, -- raycast vs the slot's Geometry (no Barriers); nil = clear
	overlaps: ((origin: Vector3, radius: number) -> boolean)?, -- GetPartBoundsInRadius vs Geometry; nil = no overlap
	-- Feature 1 (2026-10-11): the server's record of this thrower's charge start (server time; nil = none), the server
	-- time its hands are free again (a catch window or a crush; nil = free) and the earliest time a charge may count
	-- from besides the cooldown (the hands back, a root's end; nil = none).
	chargeStartAt: number?,
	handsBusyUntil: number?,
	chargeFloorAt: number?,
	-- Power-ups v1.1 (2026-10-16): × the launch speed (the throw boost of a Free for All / Team Deathmatch fighter);
	-- nil = 1.
	speedMultiplier: number?,
}

export type Decision = {
	ok: boolean,
	reason: string?, -- rejection code (§2.10)
	violation: boolean, -- payload failure (check 2): an abuse violation for NetService
	seq: number?, -- the validated seq; nil when seq itself was invalid
	lastSeq: number, -- the new ThrowState.lastSeq
	nextThrowAt: number, -- accepted: the new value; rejected: unchanged (ThrowRejected payload)
	mode: Mode?,
	-- Accepted only:
	releaseAt: number?,
	direction: Vector3?, -- unit aim direction
	origin: Vector3?,
	velocity: Vector3?, -- direction × speed
	gravity: number?,
	radius: number?,
	lag: number?,
	originClamped: boolean?, -- the hint was not used (§12 #23 counter)
	fizzle: boolean?, -- spawn overlap: ThrowImpact kind = fizzle at releaseAt
	charge: number?, -- feature 1: the server's charge c (0..1) that drew the speed
}

export type ThrowConfig = { Combat: any, Duel: any }

-- Constants

local REASON_INVALID = "net.invalid"
local REASON_CONTEXT = "throw.context"
local REASON_ROOTED = "throw.rooted"
local REASON_DIRECTION = "throw.direction"
local REASON_COOLDOWN = "throw.cooldown"
local REASON_TOO_MANY = "throw.tooMany"
local REASON_BUSY = "throw.busy" -- feature 1

local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }

local PITCH_EPSILON_DEG = 1e-3
local CONE_EPSILON = 1e-9
local FLAT_EPSILON = 1e-6

-- Module table

local ThrowRules = {}

-- Private

local function config(cfg: ThrowConfig?): ThrowConfig
	return if cfg ~= nil then cfg else Config
end

local function finitePing(ping: unknown): number
	if type(ping) ~= "number" or ping ~= ping or ping < 0 or ping == math.huge then
		return 0
	end
	return ping
end

local function reject(state: ThrowState, reason: string, seq: number?, violation: boolean, mode: Mode?): Decision
	return {
		ok = false,
		reason = reason,
		violation = violation,
		seq = seq,
		lastSeq = if seq ~= nil then math.max(state.lastSeq, seq) else state.lastSeq,
		nextThrowAt = state.nextThrowAt,
		mode = mode,
	}
end

-- The zone the HRP (check 5) and the origin hint (check 10) must be in, with its horizontal margin.
local function modeZone(state: ThrowState, mode: Mode, c: ThrowConfig): (Zone?, number)
	if mode == "duel" then
		return state.ownHalf, c.Combat.Throw.zoneToleranceStuds
	end
	return state.practiceZone, 0
end

local function directionOk(direction: Vector3, mode: Mode, state: ThrowState, c: ThrowConfig): boolean
	local throwCfg = c.Combat.Throw
	local pitch = math.deg(math.asin(math.clamp(direction.Y, -1, 1)))
	if pitch < throwCfg.pitchMinDeg - PITCH_EPSILON_DEG or pitch > throwCfg.pitchMaxDeg + PITCH_EPSILON_DEG then
		return false
	end
	if mode ~= "practice" then
		return true
	end
	local forward = state.practiceForward
	if forward == nil then
		return false
	end
	local flatAim = Vector3.new(direction.X, 0, direction.Z)
	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	if flatAim.Magnitude < FLAT_EPSILON or flatForward.Magnitude < FLAT_EPSILON then
		return false
	end
	return flatAim.Unit:Dot(flatForward.Unit) >= math.cos(math.rad(throwCfg.practiceConeDeg)) - CONE_EPSILON
end

-- Check 10: the hint when it is close (a farther one pulled back to the allowance), visible and in the right zone; else
-- the server origin.
local function chooseOrigin(
	hint: Vector3,
	root: CFrame,
	zone: Zone?,
	margin: number,
	state: ThrowState,
	c: ThrowConfig
): (Vector3, boolean)
	local throwCfg = c.Combat.Throw
	local serverOrigin = root * c.Combat.ReleaseOffset
	local ping = finitePing(state.ping)
	local allowed = throwCfg.originBaseStuds
		+ throwCfg.originPerPingStuds * math.min(ping, throwCfg.originPingCapSeconds)
	local offset = hint - serverOrigin
	local pulled = offset.Magnitude > allowed
	local origin = if pulled then serverOrigin + offset.Unit * allowed else hint
	if zone == nil or not HitMath.inZone(origin, zone, margin) then
		return serverOrigin, true
	end
	local isClear = state.isClear
	if isClear ~= nil and not isClear(root.Position, origin) then
		return serverOrigin, true
	end
	return origin, pulled
end

-- Public

-- Check 7 (§5.6, §12 #9): seconds of lag compensation for a press stamped clientTime, given the round-trip ping.
function ThrowRules.lagCompensation(now: number, clientTime: number, ping: number, cfg: ThrowConfig?): number
	local lagCfg = config(cfg).Combat.Lag
	local halfPing = finitePing(ping) / 2
	local delta = now - clientTime
	if delta ~= delta or delta < -lagCfg.clientTimeEarlySeconds or delta > lagCfg.clientTimeLateSeconds then
		return math.min(halfPing, lagCfg.maxCompensationSeconds)
	end
	local cap = math.min(halfPing + lagCfg.halfPingExtraSeconds, lagCfg.maxCompensationSeconds)
	return math.clamp(delta, 0, cap)
end

function ThrowRules.validate(input: ThrowInput, state: ThrowState, cfg: ThrowConfig?, now: number): Decision
	local c = config(cfg)
	local throwCfg = c.Combat.Throw
	local rules = c.Duel.Rules

	-- 2. Types and replay.
	local seq = Validate.integer(input.seq)
	if seq == nil or seq <= state.lastSeq or seq >= state.lastSeq + throwCfg.seqWindow then
		return reject(state, REASON_INVALID, nil, true, nil)
	end
	local aim = Validate.vector3(input.aimDir)
	local hint = Validate.vector3(input.originHint)
	local clientTime = Validate.serverTime(input.clientTime)
	if aim == nil or hint == nil or clientTime == nil then
		return reject(state, REASON_INVALID, seq, true, nil)
	end

	-- 3. Context.
	local root = state.rootCFrame
	local mode: Mode
	if state.matchPhase ~= nil then
		if not LIVE_PHASES[state.matchPhase] then
			return reject(state, REASON_CONTEXT, seq, false, nil)
		end
		mode = "duel"
	elseif root ~= nil and state.practiceZone ~= nil and HitMath.inZone(root.Position, state.practiceZone, 0) then
		mode = "practice"
	else
		return reject(state, REASON_CONTEXT, seq, false, nil)
	end

	-- 4. Alive, HRP, not rooted.
	if not state.alive or root == nil then
		return reject(state, REASON_CONTEXT, seq, false, mode)
	end
	if state.rooted == true then
		return reject(state, REASON_ROOTED, seq, false, mode)
	end

	-- 5. Position.
	local zone, margin = modeZone(state, mode, c)
	if zone == nil or not HitMath.inZone(root.Position, zone, margin) then
		return reject(state, REASON_CONTEXT, seq, false, mode)
	end

	-- 6. Direction.
	local magnitude = aim.Magnitude
	if magnitude < throwCfg.aimMagnitudeMin or magnitude > throwCfg.aimMagnitudeMax then
		return reject(state, REASON_DIRECTION, seq, false, mode)
	end
	local direction = aim / magnitude
	if not directionOk(direction, mode, state, c) then
		return reject(state, REASON_DIRECTION, seq, false, mode)
	end

	-- 7. Latency.
	local throw = state.throw
	local lag = ThrowRules.lagCompensation(now, clientTime, state.ping, c)
	local releaseAt = now - lag + throw.windup

	-- 7b. Hands (feature 1): not open for a catch, not crushing a caught toy.
	local busyUntil = state.handsBusyUntil
	if busyUntil ~= nil and now - lag < busyUntil then
		return reject(state, REASON_BUSY, seq, false, mode)
	end

	-- 8. Cooldown.
	if releaseAt < state.nextThrowAt - rules.CooldownToleranceSeconds then
		return reject(state, REASON_COOLDOWN, seq, false, mode)
	end

	-- 9. Live projectiles.
	if state.activeProjectiles >= rules.MaxActiveProjectilesPerPlayer then
		return reject(state, REASON_TOO_MANY, seq, false, mode)
	end

	-- 10. Origin.
	local origin, originClamped = chooseOrigin(hint, root, zone, margin, state, c)

	-- 11. Spawn overlap.
	local overlaps = state.overlaps
	local fizzle = overlaps ~= nil and overlaps(origin, throw.radius)

	-- 12. Accept. Feature 1: the charge, measured from the server's own record (see the header).
	local clamp = rules.CooldownClamp
	local multiplier = if state.cooldownMultiplier ~= nil then state.cooldownMultiplier else 1
	local cooldown = math.clamp(throw.cooldown, clamp.Min, clamp.Max) * multiplier
	local chargeCfg = c.Combat.Charge or Config.Combat.Charge -- a test's older Config copy may have none
	local readyPressAt = math.max(state.nextThrowAt - throw.windup, state.chargeFloorAt or -math.huge)
	local charge = ThrowCharge.measure(state.chargeStartAt, now - lag, readyPressAt, chargeCfg.seconds)
	local boost = if state.speedMultiplier ~= nil then state.speedMultiplier else 1 -- power-ups v1.1 (throw boost)
	return {
		ok = true,
		violation = false,
		seq = seq,
		lastSeq = seq,
		nextThrowAt = releaseAt + cooldown,
		mode = mode,
		releaseAt = releaseAt,
		direction = direction,
		origin = origin,
		velocity = direction * (throw.speed * ThrowCharge.speedFactor(charge, chargeCfg.speedGain) * boost),
		gravity = throw.gravity,
		radius = throw.radius,
		lag = lag,
		originClamped = originClamped,
		fizzle = fizzle,
		charge = charge,
	}
end

-- Writes a decision back into the thrower's state: lastSeq always, nextThrowAt only when accepted. CombatService
-- counts the new live projectile itself.
function ThrowRules.apply(state: ThrowState, decision: Decision)
	state.lastSeq = decision.lastSeq
	if decision.ok then
		state.nextThrowAt = decision.nextThrowAt
	end
end

-- §12 #10: a projectile expires ProjectileMaxLifetime after release, or when its position leaves the arena Bounds.
function ThrowRules.isExpired(
	releaseAt: number,
	now: number,
	position: Vector3,
	bounds: Zone?,
	cfg: ThrowConfig?
): boolean
	if now - releaseAt >= config(cfg).Duel.Rules.ProjectileMaxLifetime then
		return true
	end
	return bounds ~= nil and not HitMath.inZone(position, bounds, 0)
end

return table.freeze(ThrowRules)
