--!strict
-- CatchRules (server only, pure: no instances, no yields): feature 1 (2026-10-11) - the catch press, the catch test and
-- the charge start's press time (Config.Combat.Catch / Charge; design: the combat-effects page "Squishy Combat FP
-- v2.html", html:342-345, 614). Used by CombatService.
--
-- A CatchRequest(clientTime), cheapest check first; the first failure refuses with a reason code (nothing is sent back:
-- the client's gate mirrors these rules):
--   1. Rate bucket (Config.Net.Remotes.CatchRequest): NetService drops silently, before this module.
--   2. Payload: clientTime a server timestamp (Util/Validate.serverTime) ...................... net.invalid (violation)
--   3. Context: a registered duel in Active or SuddenDeath; alive with a server HRP .................... catch.context
--   4. Busy: not crushing (the hands are back handsBackSeconds after a catch), not rooted by an ultimate, not in a throw
--      windup (design: html:343 refuses a catch while crushing or throwing) ........................... catch.busy
--   5. Cooldown: press >= the last accepted press + cooldownSeconds - cooldownToleranceSeconds ...... catch.cooldown
-- The press time is the server's: now - lag, the same lag compensation as a ThrowRequest's clientTime (§5.6 #7,
-- ThrowRules.lagCompensation). Accepted: the window [press, press + windowSeconds] (design: html:532), the next press
-- from press + cooldownSeconds (design: html:344).
--
-- The catch test (design: html:614, "d < 2.7 && pr.vel.dot(toMe) > 0"): a projectile is caught at the first point of a
-- swept segment p0 -> p1 that lies within radiusStuds of the catcher's centre (the HRP + centreAboveRootStuds) while
-- the segment still moves toward it, inside the part of the segment the window covers (fMin..fMax). Analytic, like
-- Logic/HitMath: the segment is the server's own sub-step of the projectile's path (Shared/ProjectileMath).
--
-- API:
--   CatchRules.validate(input, state, cfg?, now) -> Decision   (state is never modified)
--   CatchRules.pressTime(now, clientTime, ping, cfg?) -> number?   a press stamped clientTime, in server time (nil: not
--       a server timestamp); also the charge start's (ChargeStart)
--   CatchRules.centre(rootPosition, cfg?) -> Vector3
--   CatchRules.windowShare(opensAt, closesAt, t0, t1) -> (fMin, fMax)?   the part of a sub-step [t0, t1] (server
--       times) the window covers, as fractions of it; nil when they do not meet
--   CatchRules.catchFraction(p0, p1, centre, radius, fMin?, fMax?) -> number?
-- `cfg` is a table with Config's Combat and Duel sections (a test's copy); nil = the live Config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Validate = require(ReplicatedStorage.Shared.Util.Validate)
local ThrowRules = require(script.Parent.ThrowRules)

-- Types

-- The raw remote argument, exactly as received.
export type CatchInput = { clientTime: unknown }

-- What the server knows about the catcher when the request arrives (CombatService fills it fresh for each request).
export type CatchState = {
	inDuel: boolean, -- a registered duel fighter
	matchPhase: string?, -- Types.DuelPhase
	alive: boolean,
	hasRoot: boolean,
	busyUntil: number, -- server time the hands are back from the last catch (-math.huge before one)
	rooted: boolean, -- an ultimate's telegraph or recovery
	windup: boolean, -- a throw windup
	lastPressAt: number, -- the last accepted press, server time (-math.huge before one)
	ping: number, -- Player:GetNetworkPing(), seconds (round trip)
}

export type Decision = {
	ok: boolean,
	reason: string?,
	violation: boolean, -- a payload failure: an abuse violation for NetService
	-- Accepted only (server times):
	pressAt: number?,
	opensAt: number?,
	closesAt: number?,
}

export type CatchConfig = { Combat: any, Duel: any }

-- Constants

local REASON_INVALID = "net.invalid"
local REASON_CONTEXT = "catch.context"
local REASON_BUSY = "catch.busy"
local REASON_COOLDOWN = "catch.cooldown"
local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }
local EPSILON = 1e-12

-- Module table

local CatchRules = {}

-- Private

local function config(cfg: CatchConfig?): CatchConfig
	return if cfg ~= nil then cfg else Config
end

local function refuse(reason: string, violation: boolean): Decision
	return { ok = false, reason = reason, violation = violation }
end

-- Public

function CatchRules.pressTime(now: number, clientTime: unknown, ping: number, cfg: CatchConfig?): number?
	local stamped = Validate.serverTime(clientTime)
	if stamped == nil then
		return nil
	end
	return now - ThrowRules.lagCompensation(now, stamped, ping, config(cfg) :: any)
end

function CatchRules.centre(rootPosition: Vector3, cfg: CatchConfig?): Vector3
	return rootPosition + Vector3.new(0, config(cfg).Combat.Catch.centreAboveRootStuds, 0)
end

function CatchRules.validate(input: CatchInput, state: CatchState, cfg: CatchConfig?, now: number): Decision
	local c = config(cfg)
	local catch = c.Combat.Catch

	-- 2. Payload.
	local pressAt = CatchRules.pressTime(now, input.clientTime, state.ping, c)
	if pressAt == nil then
		return refuse(REASON_INVALID, true)
	end

	-- 3. Context.
	if not state.inDuel or not LIVE_PHASES[state.matchPhase or ""] then
		return refuse(REASON_CONTEXT, false)
	end
	if not state.alive or not state.hasRoot then
		return refuse(REASON_CONTEXT, false)
	end

	-- 4. Busy (design: html:343).
	if now < state.busyUntil or state.rooted or state.windup then
		return refuse(REASON_BUSY, false)
	end

	-- 5. Cooldown (design: html:344).
	if pressAt < state.lastPressAt + catch.cooldownSeconds - catch.cooldownToleranceSeconds then
		return refuse(REASON_COOLDOWN, false)
	end

	return {
		ok = true,
		violation = false,
		pressAt = pressAt,
		opensAt = pressAt,
		closesAt = pressAt + catch.windowSeconds, -- design: html:532
	}
end

function CatchRules.windowShare(opensAt: number, closesAt: number, t0: number, t1: number): (number?, number?)
	if not (t1 > t0) or closesAt < t0 or opensAt > t1 then
		return nil, nil
	end
	local span = t1 - t0
	return math.clamp((opensAt - t0) / span, 0, 1), math.clamp((closesAt - t0) / span, 0, 1)
end

function CatchRules.catchFraction(
	p0: Vector3,
	p1: Vector3,
	centre: Vector3,
	radius: number,
	fMin: number?,
	fMax: number?
): number?
	local lo, hi = math.max(fMin or 0, 0), math.min(fMax or 1, 1)
	if lo > hi or not (radius > 0) then
		return nil
	end
	local d = p1 - p0
	local m = p0 - centre
	local a = d:Dot(d)
	local r2 = radius * radius
	if a < EPSILON then
		-- A segment of no length: caught only when inside, and it is not moving away (nothing to test): no catch.
		return nil
	end
	-- Inside the sphere for f in [e0, e1] (|m + f·d|² <= r²), moving toward the centre while f < approach (the closest
	-- point of the line: (centre - p(f))·d > 0).
	local b = m:Dot(d)
	local cc = m:Dot(m) - r2
	local disc = b * b - a * cc
	if disc < 0 then
		return nil
	end
	local root = math.sqrt(disc)
	local e0, e1 = (-b - root) / a, (-b + root) / a
	local approach = -b / a
	local from = math.max(lo, e0)
	local to = math.min(hi, e1, approach)
	if from > to or from >= approach then
		return nil
	end
	return from
end

return table.freeze(CatchRules)
