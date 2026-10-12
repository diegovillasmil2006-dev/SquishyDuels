--!strict
-- DashRules: validation of one DashRequest (spec phase 5 §3.3; design numbers in Config.Duel.Rules.Dash). Server only,
-- pure (no instances, no yields; the Spherecast toward cover comes in as an adapter). Used by DashService for duels and
-- the practice range.
--
-- Checks, cheapest first; the first failure refuses with a reason code:
--   1. Rate bucket (Config.Net.Remotes.DashRequest): NetService drops silently, before this module.
--   2. Payload: seq an integer above lastSeq; dir a finite Vector3; clientTime a server timestamp .......... net.invalid
--      (a payload violation for NetService's abuse count). lastSeq advances as soon as seq passes, so a refused request
--      can never be replayed.
--   3. Context: a duel in Active or SuddenDeath, or the practice range; alive with a server HRP ......... dash.context
--   4. Not rooted (an ultimate's wind-up or recovery), not in a throw windup and, feature 1 (2026-10-11, user decision:
--      no dash while crushing), not crushing a caught toy ........................................... dash.busy
--   5. On the ground: HRP height above the floor <= standing height (Hitbox: radius - bottomOffset = 3.0) +
--      groundToleranceStuds (the design ignores a dash in the air, fp.js:524) .......................... dash.airborne
--   6. Cooldown: now >= lastDashAt + cooldownSeconds - cooldownToleranceSeconds ............................ dash.cooldown
--   7. Direction: a unit vector (±0.05) along the ground (|Y| <= 0.05), flattened ........................ dash.direction
--   8. Place (duel): the HRP inside the own half + Config.Combat.Throw.zoneToleranceStuds, like a throw .... dash.context
--   9. The end point: distanceStuds along dir from the server HRP, cut where the adapter finds cover and kept
--      bodyRadiusStuds inside `zone` (the own half, or the practice range bounds; Shared/DashMath.clampToZone), so a dash
--      never crosses into the neutral band. A dash blocked at once still counts (its cooldown is spent).
-- Nothing the client sends decides where the dash ends; the client's own prediction uses the same DashMath clamp.
--
-- API:
--   DashRules.validate(input, state, cfg?, now) -> Decision (state is never modified)
-- `cfg` is a table with Config's Combat and Duel sections (a test's copy of Config); nil = the live Config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local DashMath = require(Shared.DashMath)
local Types = require(Shared.Types)
local Validate = require(Shared.Util.Validate)
local HitMath = require(script.Parent.HitMath)

-- Types

type Zone = Types.ArenaZone

export type Mode = "duel" | "practice"

-- The raw remote arguments, exactly as received.
export type DashInput = { seq: unknown, dir: unknown, clientTime: unknown }

-- What the server knows about the dasher when the request arrives (DashService fills it fresh for each request).
export type DashState = {
	lastSeq: number, -- 0 before the first dash of the session
	lastDashAt: number, -- server time of the last accepted dash (-math.huge before one)
	mode: Mode?, -- nil = neither a registered duel nor the practice range
	matchPhase: string?, -- duel: Types.DuelPhase
	alive: boolean,
	rootPosition: Vector3?, -- the server HumanoidRootPart's position; nil = missing
	floorY: number, -- the arena slot's floor, or the practice lane floor
	rooted: boolean, -- an ultimate's telegraph or recovery (rootedUntil)
	windup: boolean, -- a throw windup (windupUntil)
	crushing: boolean?, -- feature 1: crushing a caught toy until the hands are back (nil = no)
	zone: Zone?, -- duel: the own half (the place check and the end clamp); practice: the range bounds (end clamp)
	-- The distance from `origin` along the flat unit `dir` (at most `distance`) at which the dasher's body meets cover,
	-- or nil when the way is clear (DashService: a Spherecast against the slot's Geometry).
	cast: ((origin: Vector3, dir: Vector3, distance: number) -> number?)?,
}

export type Decision = {
	ok: boolean,
	reason: string?,
	violation: boolean, -- a payload failure: an abuse violation for NetService
	seq: number?,
	lastSeq: number, -- the new DashState.lastSeq
	-- Accepted only:
	dir: Vector3?, -- flat unit
	from: Vector3?, -- the server HRP position
	to: Vector3?, -- the end point (same height)
	distance: number?, -- studs from `from` to `to` (0 .. distanceStuds)
}

export type DashConfig = { Combat: any, Duel: any }

-- Constants

local REASON_INVALID = "net.invalid"
local REASON_CONTEXT = "dash.context"
local REASON_BUSY = "dash.busy"
local REASON_AIRBORNE = "dash.airborne"
local REASON_COOLDOWN = "dash.cooldown"
local REASON_DIRECTION = "dash.direction"
local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }

-- Module table

local DashRules = {}

-- Private

local function config(cfg: DashConfig?): DashConfig
	return if cfg ~= nil then cfg else Config
end

local function refuse(state: DashState, reason: string, seq: number?, violation: boolean): Decision
	return {
		ok = false,
		reason = reason,
		violation = violation,
		seq = seq,
		lastSeq = if seq ~= nil then math.max(state.lastSeq, seq) else state.lastSeq,
	}
end

-- Public

function DashRules.validate(input: DashInput, state: DashState, cfg: DashConfig?, now: number): Decision
	local c = config(cfg)
	local dash = c.Duel.Rules.Dash
	local hitbox = c.Combat.Hitbox

	-- 2. Payload and replay.
	local seq = Validate.integer(input.seq)
	if seq == nil or seq <= state.lastSeq then
		return refuse(state, REASON_INVALID, nil, true)
	end
	local dir = Validate.vector3(input.dir)
	if dir == nil or Validate.serverTime(input.clientTime) == nil then
		return refuse(state, REASON_INVALID, seq, true)
	end

	-- 3. Context.
	local mode = state.mode
	if mode == nil or (mode == "duel" and not LIVE_PHASES[state.matchPhase or ""]) then
		return refuse(state, REASON_CONTEXT, seq, false)
	end
	local root = state.rootPosition
	if not state.alive or root == nil then
		return refuse(state, REASON_CONTEXT, seq, false)
	end

	-- 4. Busy.
	if state.rooted or state.windup or state.crushing == true then
		return refuse(state, REASON_BUSY, seq, false)
	end

	-- 5. Ground.
	local standing = hitbox.radius - hitbox.bottomOffset
	if root.Y - state.floorY > standing + dash.groundToleranceStuds then
		return refuse(state, REASON_AIRBORNE, seq, false)
	end

	-- 6. Cooldown.
	if now < state.lastDashAt + dash.cooldownSeconds - dash.cooldownToleranceSeconds then
		return refuse(state, REASON_COOLDOWN, seq, false)
	end

	-- 7. Direction.
	if not DashMath.isFlatUnit(dir) then
		return refuse(state, REASON_DIRECTION, seq, false)
	end
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit

	-- 8. Place.
	local zone = state.zone
	if zone == nil then
		return refuse(state, REASON_CONTEXT, seq, false)
	end
	if mode == "duel" and not HitMath.inZone(root, zone, c.Combat.Throw.zoneToleranceStuds) then
		return refuse(state, REASON_CONTEXT, seq, false)
	end

	-- 9. The end point.
	local distance = dash.distanceStuds
	local cast = state.cast
	if cast ~= nil then
		local blocked = cast(root, flat, distance)
		if blocked ~= nil then
			distance = math.clamp(blocked, 0, distance)
		end
	end
	distance = math.min(distance, DashMath.clampToZone(root, flat, distance, zone, dash.bodyRadiusStuds))
	return {
		ok = true,
		violation = false,
		seq = seq,
		lastSeq = seq,
		dir = flat,
		from = root,
		to = root + flat * distance,
		distance = distance,
	}
end

return table.freeze(DashRules)
