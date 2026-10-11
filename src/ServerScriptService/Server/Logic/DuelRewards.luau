--!strict
-- DuelRewards: reward eligibility and amounts for one participant of an ended match (DESIGN §6.7, §12 #14, #15).
-- Server only, pure: no instances, no yields, no Coins change here. DuelService calls it once, on the single transition
-- into Result (DuelRules sets `ended` exactly once) and pays the result through EconomyService.grantDuelResult (Part 5).
--
-- Rules (Config.Economy.DuelRewards, all [P]):
--   amounts win 200, loss 60, draw 100; Cancelled and Void pay nothing and log nothing.
--   every outcome: the match reached Result from Active or SuddenDeath; the player made >= minOwnThrows (3)
--     server-accepted throws; a real player (never the Studio test dummy); profile ready (`rewardsEnabled`).
--   win (also by forfeit or leave): Active >= winMinActiveSeconds (20). loss: Active >= lossMinActiveSeconds (45).
--   draw: both players made >= minOwnThrows throws.
--   same pair: once the player's samePair record holds samePairFullRewards (6) fully rewarded results against this
--     opponent inside the rolling samePairWindowSeconds (3600), the amount is × samePairMultiplier (0.25), floored,
--     with duel.rewardsReduced.
--   exactly once: a matchId already in duelLog pays 0 (`alreadyGranted`) and adds no new entry.
-- Not eligible -> 0 Coins with `coinsBlockedReason` (duel.noRewardsOffline when the profile is not ready, duel.tooShort
-- for too little Active time or too few throws).
--
-- API:
--   DuelRewards.compute(match, participant, history, now, cfg?) -> Reward
--   DuelRewards.computeAll(match, histories, now, cfg?)         -> { A: Reward, B: Reward }
--   DuelRewards.samePairKey(userId)                             -> the record's key for an opponent
--   DuelRewards.samePairCount(samePair, opponentUserId, now, cfg?) -> fully rewarded results inside the window
--   DuelRewards.recordSamePair(samePair, opponentUserId, now, full, cfg?)  (in place; EconomyService.grantDuelResult)
--   DuelRewards.capSamePair(samePair, cfg?) -> times removed      (in place; also ProfileSchema.sanitize)
-- match = a DuelRules MatchState; participant = its Side ("A"/"B") or its Participant record; history = that player's
-- { duelLog = ProfileV1.duelLog, samePair = ProfileV1.samePair } (nil, {} or missing fields when no profile is ready);
-- now = os.time() (the duelLog clock, §2.11), also the new entry's `at`. cfg = a table with Config's Economy section and
-- optionally its Data section (caps.samePair) (a test's copy); nil = the live Config (also for a missing Data).
--
-- Readings: too few own throws reports duel.tooShort (DESIGN lists no separate code). Every win, loss or draw of a real
-- player with a ready profile returns a `logEntry` (eligible or not: it is the matchId idempotency key and the
-- duelsPlayed stat). The entry's `full` is true only for a fully rewarded result (eligible, multiplier 1).
-- A test dummy's reward is always 0 with no reason and no log entry.
-- Readings (same pair, §6.7, §12 #15): the count reads the persisted samePair record (Types.SamePairRecord), never
-- duelLog: duelLog keeps 30 entries, about 17 minutes of fast duels (~34 s a cycle), so seven accounts in rotation
-- never filled it with 6 results against one of them. EconomyService adds a time only for a fully rewarded result
-- (§6.7 "6 fully rewarded results"), so unpaid short matches and reduced results never cut a later reward. A time
-- exactly samePairWindowSeconds old is outside the window; a time after `now` (another server's clock) is inside.
-- Profiles from before the record start with an empty one (results before that release do not count).
-- A match that has not ended counts as void (0 Coins). stats is Types.DuelStats: accuracy = hits / throws as a
-- rounded percentage 0-100 (the DuelResult.stats unit).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local DuelRules = require(script.Parent.DuelRules)

-- Types

-- "A" or "B" (Types.Side). A participant may also be given as a plain side name (DuelRules.SideName, checked at
-- run time).
type Side = DuelRules.Side
type SideName = DuelRules.SideName
type DuelLogEntry = Types.DuelLogEntry
type MatchState = DuelRules.MatchState
type Participant = DuelRules.Participant
export type SamePairRecord = Types.SamePairRecord

export type RewardConfig = { Economy: any, Data: any? }

-- What compute reads from a player's profile (both read-only here).
export type RewardHistory = { duelLog: { DuelLogEntry }?, samePair: SamePairRecord? }

export type Reward = {
	userId: number,
	outcome: Types.DuelOutcome, -- this participant's view: win, loss, draw, cancelled, void
	coins: number, -- integer to grant (0 when not eligible)
	base: number, -- the amount before the same-pair multiplier (0 when not eligible)
	multiplier: number, -- 1, or samePairMultiplier
	eligible: boolean,
	coinsBlockedReason: string?, -- DuelResult.coinsBlockedReason
	reducedReason: string?, -- duel.rewardsReduced when the same-pair multiplier applied
	alreadyGranted: boolean, -- matchId already in duelLog: nothing to grant again
	logEntry: DuelLogEntry?, -- append to duelLog (EconomyService.grantDuelResult, Part 5)
	stats: Types.DuelStats, -- DuelResult.stats (accuracy 0-100, rounded)
}

-- Constants

local REASON_TOO_SHORT = "duel.tooShort"
local REASON_OFFLINE = "duel.noRewardsOffline"
local REASON_REDUCED = "duel.rewardsReduced"
local KEY_FORMAT = "%d"
local MAX_EXACT_INTEGER = 2 ^ 53

local RESULT_FROM: { [string]: boolean } = { Active = true, SuddenDeath = true }

-- Module table

local DuelRewards = {}

-- Private

local function config(cfg: RewardConfig?): RewardConfig
	return if cfg ~= nil then cfg else Config
end

local function samePairCaps(cfg: RewardConfig?): (number, number)
	local data = if cfg ~= nil and cfg.Data ~= nil then cfg.Data else Config.Data
	return config(cfg).Economy.DuelRewards.samePairFullRewards, data.caps.samePair
end

local function isTime(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function sideOf(participant: any): Side?
	local side = if type(participant) == "table" then participant.side else participant
	if side == "A" then
		return "A"
	elseif side == "B" then
		return "B"
	end
	return nil
end

-- Hits per throw as a rounded percentage 0-100 (Types.DuelStats.accuracy).
local function accuracyPercent(hits: number, throws: number): number
	if throws <= 0 then
		return 0
	end
	return math.floor(math.min(1, hits / throws) * 100 + 0.5)
end

local function hasMatch(duelLog: { DuelLogEntry }, matchId: string): boolean
	for _, entry in duelLog do
		if type(entry) == "table" and entry.matchId == matchId then
			return true
		end
	end
	return false
end

-- Public: the same-pair record (§6.7) ------------------------------------------------------------------------------

-- The record's key for an opponent: the userId as a whole-number string ("301", "-1" for a Studio player).
function DuelRewards.samePairKey(userId: number): string
	if userId == math.floor(userId) and math.abs(userId) < MAX_EXACT_INTEGER then
		return string.format(KEY_FORMAT, userId)
	end
	return tostring(userId)
end

-- Fully rewarded results against this opponent inside the rolling window (now - at < samePairWindowSeconds).
function DuelRewards.samePairCount(
	samePair: SamePairRecord?,
	opponentUserId: number,
	now: number,
	cfg: RewardConfig?
): number
	local times: any = if type(samePair) == "table" then samePair[DuelRewards.samePairKey(opponentUserId)] else nil
	if type(times) ~= "table" then
		return 0
	end
	local window = config(cfg).Economy.DuelRewards.samePairWindowSeconds
	local count = 0
	for _, at in times do
		if isTime(at) and now - at < window then
			count += 1
		end
	end
	return count
end

-- Enforces both caps in place: each opponent keeps only finite times, sorted ascending, at most samePairFullRewards of
-- them (the newest; more never change the count); empty opponents are dropped; above Config.Data.caps.samePair
-- opponents, the ones whose newest time is oldest go first (ties by key, so the result never depends on table order).
-- Returns how many times were removed.
function DuelRewards.capSamePair(samePair: SamePairRecord, cfg: RewardConfig?): number
	local perOpponent, maxOpponents = samePairCaps(cfg)
	local removed = 0
	local keys: { string } = {}
	for key, times in samePair do
		local kept: { number } = {}
		local count = 0
		if type(times) == "table" then
			for _, at in times do
				count += 1
				if isTime(at) then
					table.insert(kept, at)
				end
			end
		end
		table.sort(kept)
		local first = math.max(1, #kept - perOpponent + 1)
		local newest = table.move(kept, first, #kept, 1, {})
		removed += count - #newest
		if #newest == 0 then
			samePair[key] = nil
		else
			samePair[key] = newest
			table.insert(keys, key)
		end
	end
	if #keys > maxOpponents then
		table.sort(keys, function(a: string, b: string): boolean
			local lastA, lastB = samePair[a][#samePair[a]], samePair[b][#samePair[b]]
			if lastA ~= lastB then
				return lastA > lastB
			end
			return a < b
		end)
		for index = maxOpponents + 1, #keys do
			removed += #samePair[keys[index]]
			samePair[keys[index]] = nil
		end
	end
	return removed
end

-- Updates a player's record for one recorded duel result, in place (EconomyService.grantDuelResult, inside the same
-- profile step as the duelLog entry): times no longer inside the window are dropped for every opponent (and opponents
-- left with none); a fully rewarded result (`full`) adds `now` against this opponent; then capSamePair.
function DuelRewards.recordSamePair(
	samePair: SamePairRecord,
	opponentUserId: number,
	now: number,
	full: boolean,
	cfg: RewardConfig?
)
	local window = config(cfg).Economy.DuelRewards.samePairWindowSeconds
	for key, times in samePair do
		local kept: { number } = {}
		if type(times) == "table" then
			for _, at in times do
				if isTime(at) and now - at < window then
					table.insert(kept, at)
				end
			end
		end
		if #kept > 0 then
			samePair[key] = kept
		else
			samePair[key] = nil
		end
	end
	if full then
		local key = DuelRewards.samePairKey(opponentUserId)
		local times = samePair[key] or {}
		table.insert(times, now)
		samePair[key] = times
	end
	DuelRewards.capSamePair(samePair, cfg)
end

-- Public: rewards ----------------------------------------------------------------------------------------------------

function DuelRewards.compute(
	match: MatchState,
	participant: SideName | Participant,
	history: RewardHistory?,
	now: number,
	cfg: RewardConfig?
): Reward
	local rewards = config(cfg).Economy.DuelRewards
	local side = sideOf(participant)
	assert(side ~= nil, "[SD][DuelRewards] compute: participant must be a side or a participant record")
	assert(
		history == nil or (history :: any)[1] == nil,
		"[SD][DuelRewards] compute: history is { duelLog = ..., samePair = ... }, not a duelLog"
	)
	local me = DuelRules.participant(match, side)
	local opponent = DuelRules.participant(match, DuelRules.other(side))
	local log: { DuelLogEntry } = if history ~= nil and history.duelLog ~= nil then history.duelLog else {}
	local samePair = if history ~= nil then history.samePair else nil

	local throws, hits = me.throws, me.hits
	local reward: Reward = {
		userId = me.userId,
		outcome = "void",
		coins = 0,
		base = 0,
		multiplier = 1,
		eligible = false,
		coinsBlockedReason = nil,
		reducedReason = nil,
		alreadyGranted = false,
		logEntry = nil,
		stats = { throws = throws, hits = hits, accuracy = accuracyPercent(hits, throws) },
	}

	local outcome = match.outcome
	if not match.ended or outcome == nil or outcome.kind == "void" then
		return reward
	elseif outcome.kind == "cancelled" then
		reward.outcome = "cancelled"
		return reward
	end
	local result: Types.DuelLogResult = "loss"
	if outcome.kind == "draw" then
		result = "draw"
	elseif outcome.winner == side then
		result = "win"
	end
	reward.outcome = result

	if me.isTestDummy then
		return reward
	end
	if hasMatch(log, match.matchId) then
		reward.alreadyGranted = true
		return reward
	end
	if not me.rewardsEnabled then
		reward.coinsBlockedReason = REASON_OFFLINE
		return reward
	end
	local entry: DuelLogEntry =
		{ matchId = match.matchId, opp = opponent.userId, result = result, at = now, full = false }
	reward.logEntry = entry

	local minActive = if result == "win"
		then rewards.winMinActiveSeconds
		elseif result == "loss" then rewards.lossMinActiveSeconds
		else 0
	local longEnough = RESULT_FROM[outcome.endedFrom] == true and outcome.activeSeconds >= minActive
	local enoughThrows = throws >= rewards.minOwnThrows
		and (result ~= "draw" or opponent.throws >= rewards.minOwnThrows)
	if not (longEnough and enoughThrows) then
		reward.coinsBlockedReason = REASON_TOO_SHORT
		return reward
	end

	local base: number = rewards[result]
	local multiplier = 1
	if DuelRewards.samePairCount(samePair, opponent.userId, now, cfg) >= rewards.samePairFullRewards then
		multiplier = rewards.samePairMultiplier
		reward.reducedReason = REASON_REDUCED
	end
	reward.eligible = true
	reward.base = base
	reward.multiplier = multiplier
	reward.coins = math.floor(base * multiplier)
	entry.full = multiplier == 1
	return reward
end

-- Both participants at once. histories = { A = history?, B = history? } (each as in compute).
function DuelRewards.computeAll(
	match: MatchState,
	histories: { A: RewardHistory?, B: RewardHistory? }?,
	now: number,
	cfg: RewardConfig?
): { A: Reward, B: Reward }
	local historyA = if histories ~= nil then histories.A else nil
	local historyB = if histories ~= nil then histories.B else nil
	return {
		A = DuelRewards.compute(match, "A", historyA, now, cfg),
		B = DuelRewards.compute(match, "B", historyB, now, cfg),
	}
end

return table.freeze(DuelRewards)
