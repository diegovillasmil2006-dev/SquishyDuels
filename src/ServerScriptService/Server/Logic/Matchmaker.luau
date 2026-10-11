--!strict
-- Matchmaker: the single-server 1v1 queue rules (DESIGN §5.4 Queue, §2.8 QueueJoin, §12 #15, #21). Server only, pure:
-- no instances, no yields, time comes in as `now`. QueueService keeps the tickets and calls these functions.
--
--   Order: priority descending (RequeuePriority = requeued at the front after the opponent bailed), then joinedAt,
--   then userId (deterministic ties).
--   Pairing (on ticket add, slot release and every PairIntervalSeconds): take the head, pair it with the first later
--   ticket that canPair; skip the head's last opponent while another partner exists (AvoidImmediateRematch); repeat for
--   the next unpaired head. At most `capacity` pairs (the arena slots ArenaService can still give out).
--   Rating hook: getRating returns nil (pure FIFO). canPair is true when either rating is nil, otherwise
--   |a - b| <= base + growthPerSecond × waited. Lobby stats are never an input: newEntry copies only userId and the
--   test-dummy flag from its source.
--   The Studio test dummy is never in the real queue: joinCheck rejects it and pair/position skip it.
--
-- API:
--   Matchmaker.getRating(source)                               -> number? (always nil in v1)
--   Matchmaker.newEntry(source, joinedAt, priority?, lastOpponentUserId?, cfg?) -> Entry
--   Matchmaker.order(entries)                                  -> { Entry } (a new sorted array, dummies left out)
--   Matchmaker.canPair(a, b, now, cfg?)                        -> boolean
--   Matchmaker.pair(entries, now, capacity?, cfg?)             -> { Pair } (capacity nil = no limit)
--   Matchmaker.position(entries, userId)                       -> number? (1 = next to be paired)
--   Matchmaker.isTimedOut(entry, now, cfg?)                    -> boolean (QueueMaxSeconds -> queue.timedOut)
--   Matchmaker.cooldownUntil(endedAt, bailed, cfg?)            -> number (3 s after any match, 15 s after a bail)
--   Matchmaker.joinCheck(info, now)                            -> (boolean, reason?)
-- `cfg` is a table with Config's Duel section (a test's copy of Config); nil = the live Config.
--
-- Readings: `waited` (rating window) is the longer wait of the two tickets. A rematch is skipped when either ticket
-- names the other as its last opponent. joinCheck order follows §2.8: closing or paused (queue.paused), no arena
-- template (queue.unavailable), the test dummy (queue.unavailable), already queued or in a match
-- (queue.alreadyQueued), no live character (queue.unavailable), requeue cooldown (queue.cooldown). An equipped
-- squishy that is not owned is not a rejection (the starter is used, §2.8).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

export type Entry = {
	userId: number,
	joinedAt: number,
	priority: number,
	rating: number?,
	lastOpponentUserId: number?,
	isTestDummy: boolean?,
}

export type Pair = { a: Entry, b: Entry }

-- What QueueService knows when a player presses Join.
export type JoinInfo = {
	closing: boolean?, -- ShutdownService closing
	paused: boolean?, -- ServerRestartScheduled
	arenaAvailable: boolean, -- the arena template exists
	isTestDummy: boolean?,
	queued: boolean,
	inMatch: boolean,
	alive: boolean, -- has a live character
	cooldownUntil: number?, -- from cooldownUntil(); nil = no cooldown
}

export type MatchmakerConfig = { Duel: any }

-- Constants

local REASON_PAUSED = "queue.paused"
local REASON_UNAVAILABLE = "queue.unavailable"
local REASON_ALREADY = "queue.alreadyQueued"
local REASON_COOLDOWN = "queue.cooldown"

-- Module table

local Matchmaker = {}

-- Private

local function config(cfg: MatchmakerConfig?): MatchmakerConfig
	return if cfg ~= nil then cfg else Config
end

local function before(a: Entry, b: Entry): boolean
	if a.priority ~= b.priority then
		return a.priority > b.priority
	end
	if a.joinedAt ~= b.joinedAt then
		return a.joinedAt < b.joinedAt
	end
	return a.userId < b.userId
end

local function isRematch(a: Entry, b: Entry): boolean
	return a.lastOpponentUserId == b.userId or b.lastOpponentUserId == a.userId
end

-- Public

-- The rating hook (§5.4): nil = pure FIFO. Any future rating is a separate, hidden, duel-only value; it never reads
-- lobby stats.
function Matchmaker.getRating(_source: unknown): number?
	return nil
end

-- A queue ticket. `source` is the player (or a fake in tests): only its userId and test-dummy flag are read.
function Matchmaker.newEntry(
	source: { userId: number, isTestDummy: boolean? },
	joinedAt: number,
	priority: number?,
	lastOpponentUserId: number?,
	cfg: MatchmakerConfig?
): Entry
	return {
		userId = source.userId,
		joinedAt = joinedAt,
		priority = if priority ~= nil then priority else config(cfg).Duel.Matchmaking.NormalPriority,
		rating = Matchmaker.getRating(source),
		lastOpponentUserId = lastOpponentUserId,
		isTestDummy = if source.isTestDummy == true then true else nil,
	}
end

-- The queue in pairing order, without test dummies and without a second ticket for the same userId.
function Matchmaker.order(entries: { Entry }): { Entry }
	local sorted: { Entry } = {}
	for _, entry in entries do
		if entry.isTestDummy ~= true then
			table.insert(sorted, entry)
		end
	end
	table.sort(sorted, before)
	local seen: { [number]: boolean } = {}
	local unique: { Entry } = {}
	for _, entry in sorted do
		if not seen[entry.userId] then
			seen[entry.userId] = true
			table.insert(unique, entry)
		end
	end
	return unique
end

function Matchmaker.canPair(a: Entry, b: Entry, now: number, cfg: MatchmakerConfig?): boolean
	if a.userId == b.userId or a.isTestDummy == true or b.isTestDummy == true then
		return false
	end
	local ra, rb = a.rating, b.rating
	if ra == nil or rb == nil then
		return true
	end
	local window = config(cfg).Duel.Matchmaking.RatingWindow
	if window == nil then
		return true
	end
	local waited = math.max(0, now - math.min(a.joinedAt, b.joinedAt))
	return math.abs(ra - rb) <= window.base + window.growthPerSecond * waited
end

function Matchmaker.pair(entries: { Entry }, now: number, capacity: number?, cfg: MatchmakerConfig?): { Pair }
	local limit = if capacity ~= nil then capacity else math.huge
	local avoidRematch = config(cfg).Duel.Matchmaking.AvoidImmediateRematch == true
	local ordered = Matchmaker.order(entries)
	local used: { [number]: boolean } = {}
	local found: { Pair } = {}
	for i, head in ordered do
		if #found >= limit then
			break
		end
		if used[i] then
			continue
		end
		local first: number?, fallback: number? = nil, nil
		for j = i + 1, #ordered do
			if not used[j] and Matchmaker.canPair(head, ordered[j], now, cfg) then
				if avoidRematch and isRematch(head, ordered[j]) then
					fallback = fallback or j
				else
					first = j
					break
				end
			end
		end
		local pick = first or fallback
		if pick ~= nil then
			used[i], used[pick] = true, true
			table.insert(found, { a = head, b = ordered[pick] })
		end
	end
	return found
end

function Matchmaker.position(entries: { Entry }, userId: number): number?
	for index, entry in Matchmaker.order(entries) do
		if entry.userId == userId then
			return index
		end
	end
	return nil
end

function Matchmaker.isTimedOut(entry: Entry, now: number, cfg: MatchmakerConfig?): boolean
	return now - entry.joinedAt >= config(cfg).Duel.Matchmaking.QueueMaxSeconds
end

function Matchmaker.cooldownUntil(endedAt: number, bailed: boolean, cfg: MatchmakerConfig?): number
	local rules = config(cfg).Duel.Rules
	return endedAt + (if bailed then rules.BailRequeueCooldownSeconds else rules.RequeueCooldownSeconds)
end

-- QueueJoin game-state checks (§2.8), in order. Returns (true, nil) or (false, reason code).
function Matchmaker.joinCheck(info: JoinInfo, now: number): (boolean, string?)
	if info.closing == true or info.paused == true then
		return false, REASON_PAUSED
	end
	if not info.arenaAvailable or info.isTestDummy == true then
		return false, REASON_UNAVAILABLE
	end
	if info.queued or info.inMatch then
		return false, REASON_ALREADY
	end
	if not info.alive then
		return false, REASON_UNAVAILABLE
	end
	if info.cooldownUntil ~= nil and now < info.cooldownUntil then
		return false, REASON_COOLDOWN
	end
	return true, nil
end

return table.freeze(Matchmaker)
