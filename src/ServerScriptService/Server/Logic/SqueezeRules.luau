--!strict
-- SqueezeRules: the pure squeeze model of DESIGN §6.3 (with step 6a of §17.3.1). Server only, pure: no instances, no
-- yields, no Coins, Grip or profile change here. SqueezeService keeps one State per player (newState on join), calls
-- decide() for every SqueezeRequest, stores the returned state and limit, then acts on the decision:
--   "dropped"  -> nothing at all (no reply; §6.3 step 1 drops floods silently); log once when `logFlood`.
--   "rejected" -> reply SqueezeResult{ok = false, reason, nextAt, ...}; no token used, nothing earned.
--   "accepted" -> grant `coins` (EconomyService.grantCoins(p, coins, "squeeze") when > 0), store `limit`, Grip
--                 (GripService.addFromSqueeze, §17.3.1 step 8a, whether or not it paid), stats.squeezes and quests,
--                 SD_SqueezeAt, reply SqueezeResult{ok = true, coins, ..., nextAt}.
--
-- decide() runs the §6.3 order on plain inputs (squeeze anywhere, spec 2026-10-11 §5: the lobby has no station gate):
--   1 flood guard: more than Squeeze.floodPerSecond (20) requests inside any 1 s are dropped; more than
--     floodLogDrops (40) drops inside floodLogWindowSeconds (10 s) set `logFlood` once
--   2 profile ready (not OFFLINE / READONLY / loading)       else data.notReady
--   3 a living character with a root part                                           else squeeze.noCharacter
--   4 not in a match (SD_DuelPhase == ""; squeezing while Searching is allowed)     else squeeze.inDuel
--   5 the Coins come from the server record (the caller passes the squeeze value of the player's capsules,
--     CapsuleMath.squeezeValue; Phase 3: the held squishy no longer changes it)
--   6 the tier (tierFor): the pad the server-side root stands on (padUnder; SqueezeService drops a pad its
--     stale-lobby check disabled) when Config.Grip.Pads has its tier; off a pad, BASE_TIER (1: the Foam Mats row,
--     base Coins and Grip). Since the giant pads went (build plan Phase 6) every station is tier 1, so every squeeze
--     pays tier 1; the tier still goes to Grip's fail-closed check
--   7 the anti-autoclicker cap, a token bucket: capacity Squeeze.bucketCapacity (12), 1 token per cycleSeconds
--     (1/12 s), on os.clock(): 12 at once and 12 per second on average, so over any t seconds at most 12 + 12 × t
--     squeezes are accepted (right after a rest a macro can get up to 20 in one second, the flood guard's limit, then
--     12 a second)                                                                   else squeeze.tooFast
--   8 earnings limit (SqueezeLimit with Economy.SqueezeLimit, on os.time()): paid when a point is there (always
--     when the limit is disabled, as shipped since spec 2026-10-11 §5: the limit state is then left alone);
--     coins = baseCoins when paid, else Economy.SqueezeLimit.emptyCoins (Phase 3: a pad adds no Coin bonus)
-- Every click pays (user decision, 2026-10-06): there is no squeeze timer; a human clicking never meets step 7 (the
-- client stays under the cap), so every press is accepted and pays (through the earnings limit). Only a macro gets
-- squeeze.tooFast (no Coins, no Grip; the client shows nothing for it), and above 20/s the flood guard drops it.
-- Reading (why a bucket, not a strict "12 in any second" window): the client keeps its own 12-in-any-second limit on
-- its clock, and network jitter bunches those presses on arrival; the bucket's spare tokens absorb that, where a strict
-- server window would answer honest presses with squeeze.tooFast. The price is one extra burst of at most 12 after a
-- rest, which the long-run 12 a second keeps small (the hourly earnings limit is off since spec 2026-10-11 §5).
-- `nextAt` (every reply) is a server time: serverNow + max(0, 1 - tokens) × cycleSeconds (§17.10).
--
-- API:
--   SqueezeRules.newState(now, cfg?)                 -> State (a full bucket, an empty flood window)
--   SqueezeRules.flood(flood, now, cfg?)             -> (allowed, Flood, logNow)
--   SqueezeRules.accept(bucket, now, cfg?)           -> (accepted, Bucket)  the §6.3 token bucket check
--   SqueezeRules.tokens(bucket, now, cfg?)           -> tokens now (fractional, <= bucketCapacity)
--   SqueezeRules.secondsUntilNext(bucket, now, cfg?) -> max(0, 1 - tokens) × cycleSeconds
--   SqueezeRules.padUnder(rootPosition, cfg?)        -> WorldLayout.Station? the pad the root stands on
--                                                       (WorldLayout.stationUnder with Squeeze padMargin / heightAbove)
--   SqueezeRules.tierFor(station, cfg?)              -> the tier a squeeze pays (step 6)
--   SqueezeRules.earn(limit, osNow, baseCoins, cfg?) -> (paid, coins, newLimit)
--   SqueezeRules.decide(input, cfg?)                 -> Decision
-- `now` = os.clock() seconds (bucket, flood guard); `osNow` = os.time() (the saved limit); `serverNow` =
-- workspace:GetServerTimeNow() (nextAt). cfg = a table with Config's Squeeze, Economy and Grip sections (a test's
-- copy); nil = the live Config.
--
-- Readings: a missing or dead character is squeeze.noCharacter (spec 2026-10-11 §5: the only refusal left of the old
-- station checks; its text is under Strings reason.squeeze); the pad test is "standing on it" (Config.Squeeze's
-- margins; slow training, which shared it, is gone since build plan Phase 6); a squeeze from
-- a player in a match is squeeze.inDuel (new reading code, its text is under Strings reason.squeeze); the flood guard
-- counts only requests it let through (like a token bucket, so a spammer still gets 20 per second through to the
-- bucket); the flood log re-arms once the drops inside the log window are back to floodLogDrops or fewer; a request
-- exactly 1 s old (within FLOOD_EDGE_SECONDS, float noise) is out of the window, so a steady 20/s is never dropped.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)
local SqueezeLimit = require(ReplicatedStorage.Shared.SqueezeLimit)
local Types = require(ReplicatedStorage.Shared.Types)
local WorldLayout = require(ReplicatedStorage.Shared.World.WorldLayout)

-- Types

export type Bucket = { tokens: number, at: number } -- os.clock() seconds
export type Flood = {
	recent: { number }, -- times of the requests let through inside the last second (at most floodPerSecond)
	drops: { number }, -- times of the recent drops (at most floodLogDrops + 1)
	logged: boolean, -- the flood was logged and the log has not re-armed yet
}
export type State = { bucket: Bucket, flood: Flood }

-- Anything with Config's Squeeze, Economy and Grip sections.
export type SqueezeConfig = { Squeeze: any, Economy: any, Grip: any }

export type StationInfo = {
	tier: number, -- WorldLayout.Station.tier (GripTier), never from the client
}

export type Input = {
	now: number, -- os.clock()
	osNow: number, -- os.time()
	serverNow: number, -- workspace:GetServerTimeNow()
	state: State, -- this player's State
	profileReady: boolean, -- DataService status "ready"
	station: StationInfo?, -- the pad under the server-side root (padUnder); nil: off every pad or a disabled one
	rootPosition: Vector3?, -- nil: no living character with a HumanoidRootPart
	inMatch: boolean, -- SD_DuelPhase ~= ""
	baseCoins: number, -- the squeeze value (CapsuleMath.squeezeValue of the profile's capsules)
	limit: Types.SqueezeLimitState, -- profile.squeezeLimit
}

export type Outcome = "dropped" | "rejected" | "accepted"

export type Decision = {
	outcome: Outcome,
	reason: string?, -- "rejected": a §2.10 reason code
	logFlood: boolean, -- log the flood now (once)
	state: State, -- store this as the player's State (every outcome)
	tier: number, -- the tier this squeeze pays (tierFor: Grip)
	paid: boolean, -- "accepted" and the earnings limit had a point
	coins: number, -- Coins to grant with reason "squeeze" ("accepted" only; may be 0)
	limit: Types.SqueezeLimitState, -- the new profile.squeezeLimit (unchanged unless accepted)
	nextAt: number, -- server time of the next token (SqueezeResult.nextAt)
}

-- Constants

local REASON_NOT_READY = "data.notReady"
local REASON_NO_CHARACTER = "squeeze.noCharacter"
local REASON_IN_DUEL = "squeeze.inDuel"
local REASON_TOO_FAST = "squeeze.tooFast"
-- Off a pad a squeeze pays the Foam Mats row: validator G2 keeps Pads[1] at level 1, coinBonus 0, gripPercent 100
-- (spec 2026-10-11 §5: base Coins and base Grip, no pad bonus).
local BASE_TIER = 1
local FLOOD_WINDOW_SECONDS = 1 -- "> floodPerSecond requests/s"
local FLOOD_EDGE_SECONDS = 1e-6 -- float slack at the window's edge (see Readings)
local TOKEN_SLACK = 1e-6 -- a bucket this close to a whole token has one (accept)

-- Module table

local SqueezeRules = {}

-- Private

local function sections(cfg: SqueezeConfig?): SqueezeConfig
	return if cfg ~= nil then cfg else Config :: any
end

-- The entries of `times` newer than `after`, keeping at most the last `keep`.
local function recentTimes(times: { number }, after: number, keep: number): { number }
	local kept: { number } = {}
	for _, t in times do
		if t > after then
			table.insert(kept, t)
		end
	end
	while #kept > keep do
		table.remove(kept, 1)
	end
	return kept
end

-- Public: state

function SqueezeRules.newState(now: number, cfg: SqueezeConfig?): State
	local squeeze = sections(cfg).Squeeze
	return {
		bucket = { tokens = squeeze.bucketCapacity, at = now },
		flood = { recent = {}, drops = {}, logged = false },
	}
end

-- Public: step 1, the flood guard

function SqueezeRules.flood(flood: Flood, now: number, cfg: SqueezeConfig?): (boolean, Flood, boolean)
	local squeeze = sections(cfg).Squeeze
	local limit = squeeze.floodPerSecond
	local recent = recentTimes(flood.recent, now - FLOOD_WINDOW_SECONDS + FLOOD_EDGE_SECONDS, limit)
	local drops = recentTimes(flood.drops, now - squeeze.floodLogWindowSeconds, squeeze.floodLogDrops + 1)
	local logged = flood.logged and #drops > squeeze.floodLogDrops
	if #recent < limit then
		table.insert(recent, now)
		return true, { recent = recent, drops = drops, logged = logged }, false
	end
	table.insert(drops, now)
	drops = recentTimes(drops, now - squeeze.floodLogWindowSeconds, squeeze.floodLogDrops + 1)
	local logNow = not logged and #drops > squeeze.floodLogDrops
	return false, { recent = recent, drops = drops, logged = logged or logNow }, logNow
end

-- Public: step 7, the token bucket

function SqueezeRules.tokens(bucket: Bucket, now: number, cfg: SqueezeConfig?): number
	local squeeze = sections(cfg).Squeeze
	local refill = math.max(0, now - bucket.at) / squeeze.cycleSeconds
	return math.min(squeeze.bucketCapacity, math.max(0, bucket.tokens) + refill)
end

-- Uses one token if there is one. Returns (accepted, newBucket); store the new bucket either way. A clock that went
-- backwards refills nothing and keeps the later time. A token short by float noise only (TOKEN_SLACK: with the 1/12 s
-- cycle, os.clock differences are not exact multiples of it) still counts as a token.
function SqueezeRules.accept(bucket: Bucket, now: number, cfg: SqueezeConfig?): (boolean, Bucket)
	local tokens = SqueezeRules.tokens(bucket, now, cfg)
	local at = math.max(bucket.at, now)
	if tokens >= 1 - TOKEN_SLACK then
		return true, { tokens = math.max(0, tokens - 1), at = at }
	end
	return false, { tokens = tokens, at = at }
end

function SqueezeRules.secondsUntilNext(bucket: Bucket, now: number, cfg: SqueezeConfig?): number
	local c = sections(cfg)
	return math.max(0, 1 - SqueezeRules.tokens(bucket, now, c)) * c.Squeeze.cycleSeconds
end

-- Public: step 6, the pad and the tier (spec 2026-10-11 §5)

-- The station a root part at `rootPosition` (server-measured) stands on: WorldLayout.stationUnder with
-- Config.Squeeze's padMargin and heightAbove (the client's mat pulse uses the same test). nil off every pad.
function SqueezeRules.padUnder(rootPosition: Vector3, cfg: SqueezeConfig?): WorldLayout.Station?
	local squeeze = sections(cfg).Squeeze
	return WorldLayout.stationUnder(rootPosition, squeeze.padMargin, squeeze.heightAbove)
end

-- The tier a squeeze pays: the pad's when Config.Grip.Pads has its tier, else BASE_TIER (off a pad or an unknown
-- tier).
function SqueezeRules.tierFor(station: StationInfo?, cfg: SqueezeConfig?): number
	if station ~= nil and sections(cfg).Grip.Pads[station.tier] ~= nil then
		return station.tier
	end
	return BASE_TIER
end

-- Public: step 8, the earnings limit

-- Returns (paid, coins, newLimit). A disabled limit pays every squeeze and leaves the state as it is.
function SqueezeRules.earn(
	limit: Types.SqueezeLimitState,
	osNow: number,
	baseCoins: number,
	cfg: SqueezeConfig?
): (boolean, number, Types.SqueezeLimitState)
	local limitCfg = sections(cfg).Economy.SqueezeLimit
	local paid, newLimit = true, limit
	if limitCfg.enabled then
		paid, newLimit = SqueezeLimit.spend(limit, osNow, limitCfg)
	end
	return paid, if paid then baseCoins else limitCfg.emptyCoins, newLimit
end

-- Public: the whole §6.3 order

function SqueezeRules.decide(input: Input, cfg: SqueezeConfig?): Decision
	local c = sections(cfg)
	local state = input.state
	local tier = SqueezeRules.tierFor(input.station, c)

	-- 1. Flood guard (silent drop).
	local allowed, flood, logNow = SqueezeRules.flood(state.flood, input.now, c)
	local bucket = state.bucket
	local function finish(outcome: Outcome, reason: string?, newBucket: Bucket): Decision
		return {
			outcome = outcome,
			reason = reason,
			logFlood = logNow,
			state = { bucket = newBucket, flood = flood },
			tier = tier,
			paid = false,
			coins = 0,
			limit = input.limit,
			nextAt = input.serverNow + SqueezeRules.secondsUntilNext(newBucket, input.now, c),
		}
	end
	if not allowed then
		return finish("dropped", nil, bucket)
	end

	-- 2-4. Game-state checks; none of them uses a token. Step 6 (the tier) refuses nothing.
	if not input.profileReady then
		return finish("rejected", REASON_NOT_READY, bucket)
	end
	if input.rootPosition == nil then
		return finish("rejected", REASON_NO_CHARACTER, bucket)
	end
	if input.inMatch then
		return finish("rejected", REASON_IN_DUEL, bucket)
	end

	-- 7. Token bucket.
	local accepted, newBucket = SqueezeRules.accept(bucket, input.now, c)
	if not accepted then
		return finish("rejected", REASON_TOO_FAST, newBucket)
	end

	-- 8. Earnings limit and Coins.
	local decision = finish("accepted", nil, newBucket)
	local paid, coins, newLimit = SqueezeRules.earn(input.limit, input.osNow, input.baseCoins, c)
	decision.paid = paid
	decision.coins = coins
	decision.limit = newLimit
	return decision
end

return table.freeze(SqueezeRules)
