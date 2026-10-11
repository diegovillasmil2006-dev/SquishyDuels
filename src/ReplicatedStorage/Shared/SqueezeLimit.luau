--!strict
-- SqueezeLimit: pure math for a pool of points that refills with time (DESIGN §6.3, §17.3.4, §17.3.6). Shared
-- (server SqueezeService, GripService, ProfileSchema; client limit bar, Grip card and panel). No instances, no yields,
-- no side effects; time is injected (`now` = os.time() seconds for the profile timers).
--
-- One model, three uses, each a `{ value, at }` state in the profile:
--   * the squeeze Coins limit   profile.squeezeLimit  Config.Economy.SqueezeLimit  (600/h, burst 300)
--   * Double Grip               profile.grip.rested   Config.Grip.Rested           (240/h, burst 1200)
--   * the slow-training bank    profile.grip.afk      Config.Grip.Afk              (180/h, burst 120)
-- Points refill continuously at perHour (online and offline) up to burst; each use takes 1 point. New accounts start
-- full (`full`). These are timers, never currencies: nothing sells, grants or refills them (§6.3, §17.2 rule 2).
-- `enabled` is read by the callers, never here: a disabled Coins limit means every squeeze pays, while a disabled
-- Double Grip means no squeeze is doubled, so the two need different handling.
--
-- API:
--   SqueezeLimit.current(s, now, cfg) -> number          points now (may be fractional), in [0, burst]
--   SqueezeLimit.spend(s, now, cfg)   -> (paid, State)   paid when a whole point was there; the new state to store
--   SqueezeLimit.full(now, cfg)       -> State           a full pool (new accounts, migration defaults)
-- `cfg` is any table with `perHour` and `burst` (the three Config blocks above).
--
-- Readings (DESIGN gives the formulas of §6.3; these only make them safe on odd input):
--   * A non-finite or negative `value` counts as 0 and a non-finite `at` as `now` (fail closed; ProfileSchema also
--     sanitizes on load).
--   * A clock that went backwards (`now < at`) refills nothing, and `spend` keeps the later `at`, so the same seconds
--     are never credited twice (DESIGN writes `at = now`; equal whenever time moves forward).

-- Types

export type State = { value: number, at: number }
export type Limit = { perHour: number, burst: number }

-- Constants

local SECONDS_PER_HOUR = 3600

-- Module table

local SqueezeLimit = {}

-- Private

local function isFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- Public

-- Points available at `now`: min(burst, value + max(0, now - at) × perHour / 3600).
function SqueezeLimit.current(s: State, now: number, cfg: Limit): number
	local value = if isFinite(s.value) then math.max(0, s.value) else 0
	local at = if isFinite(s.at) then s.at else now
	local refilled = value + math.max(0, now - at) * cfg.perHour / SECONDS_PER_HOUR
	return math.max(0, math.min(cfg.burst, refilled))
end

-- Uses one point if a whole point is there. Returns (paid, newState); store the new state either way (it carries the
-- refill up to `now`).
function SqueezeLimit.spend(s: State, now: number, cfg: Limit): (boolean, State)
	local v = SqueezeLimit.current(s, now, cfg)
	local at = if isFinite(s.at) then math.max(s.at, now) else now
	if v >= 1 then
		return true, { value = v - 1, at = at }
	end
	return false, { value = v, at = at }
end

-- A full pool at `now`.
function SqueezeLimit.full(now: number, cfg: Limit): State
	return { value = cfg.burst, at = now }
end

return table.freeze(SqueezeLimit)
