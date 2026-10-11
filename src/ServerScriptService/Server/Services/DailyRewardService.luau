--!strict
-- DailyRewardService (server only). DESIGN §6.9, §2.8 (DailyClaim), §3.4 (daily row), §3.9 / §3.11 ("now" save,
-- blocked while savePending), §6.4 (the free Treat Box), §12 #6, #14.
-- One claim per UTC day (server time only: Logic/DailyLogic.dayIndex(os.time()); the client clock is never used).
-- claim(p), the DailyClaim RF, in this order:
--   1. the profile is READY, else data.notReady;
--   2. no failed save pending, else box.saving (Reading: §3.11 blocks daily claims while savePending and §2.10 has no
--      daily code for it; "Saving your collection…" is the sentence the box and shop use too);
--   3. DailyLogic.canClaim(daily, today), else daily.alreadyClaimed (the client shows "Claimed! Come back in {time}"
--      with its own countdown to 00:00 UTC);
--   4. DailyLogic.nextStreak -> the streak day and whether a missed day restarted it (Notify daily.streakReset, and
--      streakReset = true in the reply);
--   5. in one step with nothing yielding: the daily record {lastClaimDay = today, streakDay, totalClaims + 1} through
--      DataService.mutate, EconomyService.grantCoins(coinsByDay[streak], "daily") and, on the free box day,
--      BoxService.grantFree(p, Economy.Daily.freeBoxId, "daily:<today>") (the Treat Box: no cost, no policy check,
--      appends boxLog seen = false; its key makes it impossible to repeat, §3.4);
--   6. markDirty("daily"), then ONE awaited DataService.saveNowAsync (it carries the Coins and the Treat Box too);
--   7. reply ok Types.DailyClaimResult {streakDay, coins, treat, streakReset, treatRequestId}; `treat` is the Treat
--      Box result with savePending = the save failed (the reveal plays at once; AckReveal uses treatRequestId).
-- Idempotent by daily.lastClaimDay: a second claim the same day is refused (daily.alreadyClaimed) before anything
-- changes. Reading: DailyClaim has no oneInFlight; a second call while the first awaits its save already sees today's
-- lastClaimDay (step 5 runs before the yield), so it is refused the same way.
-- status(p) is the server's view of the same rules (Studio checks; the client derives its own from StateDelta.daily).
-- Studio only (RunService:IsStudio() and Config.Debug.debugHooks): debugSetState(p, {lastClaimDay?, streakDay?}).
-- Collaborators are injectable (useDeps) so unit tests run with a fake data port, clock and box service.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Types = require(Shared.Types)
local DailyLogic = require(script.Parent.Parent.Logic.DailyLogic)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local NetService = require(script.Parent.NetService)
local StateService = require(script.Parent.StateService)

-- Types

export type Deps = {
	data: StateService.DataPort,
	markDirty: (player: any, field: string) -> (),
	notify: (player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?) -> (),
	grantCoins: (player: any, amount: number, reason: string) -> (number, string?),
	-- BoxService.grantFree: non-yielding, idempotent by requestId; nil when nothing was granted.
	grantFree: (player: any, boxId: string, requestId: string) -> Types.BoxResult?,
	saveNow: (player: any) -> boolean, -- DataService.saveNowAsync (yields)
	unixNow: () -> number, -- os.time
	debugAllowed: () -> boolean,
}

export type Status = {
	ready: boolean, -- the profile is READY
	today: number,
	lastClaimDay: number,
	streakDay: number,
	totalClaims: number,
	canClaim: boolean,
	nextStreakDay: number, -- the day the next claim pays (today's day while claimed today)
	willReset: boolean, -- the next claim restarts the streak at Day 1
	coins: number, -- the Coins of nextStreakDay
	freeBox: boolean, -- nextStreakDay is the free Treat Box day
	secondsUntilNext: number, -- until the next 00:00 UTC
}

-- Constants

local REMOTE_CLAIM = "DailyClaim"
local FIELD = "daily"
local STATUS_READY = "ready"
local COIN_REASON = "daily"
local TREAT_KEY_PREFIX = "daily:"
local CODE_NOT_READY = "data.notReady"
local CODE_SAVING = "box.saving"
local CODE_ALREADY = "daily.alreadyClaimed"
local NOTICE_RESET = "daily.streakReset"

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve these paths statically.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local DailyRewardService = {}

-- Private

local log = Log.new("Daily")

-- BoxService (same top layer, booted before this one) is looked up on first use, so a missing or broken module can
-- never stop the daily Coins; the Treat Box is then logged as not granted.
local boxServiceModule: any = nil
local boxServiceResolved = false
local function boxService(): any
	if not boxServiceResolved then
		boxServiceResolved = true
		local module = script.Parent:FindFirstChild("BoxService")
		if module ~= nil and module:IsA("ModuleScript") then
			local ok, result = pcall(dynamicRequire, module)
			if ok then
				boxServiceModule = result
			else
				log:error("BoxService failed to load:", result)
			end
		end
	end
	return boxServiceModule
end

local function defaultDeps(): Deps
	return {
		data = StateService.dataPort(),
		markDirty = function(player: any, field: string)
			StateService.markDirty(player, field)
		end,
		notify = function(player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
			NetService.notify(player, code, args, kind)
		end,
		grantCoins = function(player: any, amount: number, reason: string): (number, string?)
			return EconomyService.grantCoins(player, amount, reason)
		end,
		grantFree = function(player: any, boxId: string, requestId: string): Types.BoxResult?
			local boxes = boxService()
			if type(boxes) ~= "table" or type(boxes.grantFree) ~= "function" then
				log:error("BoxService.grantFree is missing: the free Treat Box was not granted")
				return nil
			end
			return boxes.grantFree(player, boxId, requestId)
		end,
		saveNow = function(player: any): boolean
			return DataService.saveNowAsync(player)
		end,
		unixNow = os.time,
		debugAllowed = function(): boolean
			return RunService:IsStudio() and Config.Debug.debugHooks == true
		end,
	}
end

local deps: Deps = defaultDeps()

local function isWhole(n: unknown): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and math.floor(n) == n
end

-- The profile's daily record as plain numbers (fail closed: a missing or malformed field reads as "claimed today",
-- like DailyLogic.canClaim, so nothing can be claimed from it).
local function dailyOf(profile: any, today: number): Types.DailyState
	local daily = if type(profile) == "table" then profile.daily else nil
	if type(daily) ~= "table" then
		return { lastClaimDay = today, streakDay = 1, totalClaims = 0 }
	end
	return {
		lastClaimDay = if type(daily.lastClaimDay) == "number" then daily.lastClaimDay else today,
		streakDay = if type(daily.streakDay) == "number" then daily.streakDay else 0,
		totalClaims = if isWhole(daily.totalClaims) then daily.totalClaims else 0,
	}
end

-- Public: API ----------------------------------------------------------------------------------------------------------

-- The daily rules as they stand for this player now (a copy; nothing changes).
function DailyRewardService.status(player: any): Status
	local now = deps.unixNow()
	local today = DailyLogic.dayIndex(now)
	local ready = deps.data.status(player) == STATUS_READY
	local daily = dailyOf(deps.data.getProfile(player), today)
	local canClaim = ready and (DailyLogic.canClaim(daily, today))
	local streak, reset = DailyLogic.nextStreak(daily, today)
	local reward = DailyLogic.reward(streak)
	return {
		ready = ready,
		today = today,
		lastClaimDay = daily.lastClaimDay,
		streakDay = daily.streakDay,
		totalClaims = daily.totalClaims,
		canClaim = canClaim,
		nextStreakDay = streak,
		willReset = reset,
		coins = reward.coins,
		freeBox = reward.freeBox,
		secondsUntilNext = DailyLogic.secondsUntilNext(now),
	}
end

-- The DailyClaim RF (see the header). Returns NetService.ok(Types.DailyClaimResult) or NetService.err(reason).
function DailyRewardService.claim(player: any): any
	local data = deps.data
	-- 1. ready
	if data.status(player) ~= STATUS_READY then
		return NetService.err(CODE_NOT_READY)
	end
	-- 2. no failed save pending
	if data.savePending(player) then
		return NetService.err(CODE_SAVING)
	end
	-- 3. once per UTC day
	local today = DailyLogic.dayIndex(deps.unixNow())
	local before = dailyOf(data.getProfile(player), today)
	local allowed = DailyLogic.canClaim(before, today)
	if not allowed then
		return NetService.err(CODE_ALREADY)
	end
	-- 4. the streak day this claim pays
	local streak, reset = DailyLogic.nextStreak(before, today)
	local reward = DailyLogic.reward(streak)
	-- 5. the daily record, the Coins and the Treat Box, with nothing yielding in between
	local ok, recorded = data.mutate(player, function(profile: any): boolean
		local current = dailyOf(profile, today)
		if not DailyLogic.canClaim(current, today) then
			return false -- claimed in the meantime (impossible without a yield; kept as a guard)
		end
		local daily = profile.daily
		if type(daily) ~= "table" then
			daily = {}
			profile.daily = daily
		end
		daily.lastClaimDay = today
		daily.streakDay = streak
		daily.totalClaims = current.totalClaims + 1
		return true
	end)
	if not ok then
		return NetService.err(CODE_NOT_READY) -- the session stopped taking changes (its final save started)
	elseif recorded ~= true then
		return NetService.err(CODE_ALREADY)
	end
	local coins = 0
	if reward.coins > 0 then
		local added, failure = deps.grantCoins(player, reward.coins, COIN_REASON)
		coins = added
		if failure ~= nil then
			log:error(`user {player.UserId}: daily Coins for day {today} not granted ({failure})`)
		end
	end
	local treat: Types.BoxResult? = nil
	local treatRequestId: string? = nil
	if reward.freeBox then
		treatRequestId = TREAT_KEY_PREFIX .. tostring(today)
		local okBox, box = pcall(deps.grantFree, player, Config.Economy.Daily.freeBoxId, treatRequestId :: string)
		if okBox and type(box) == "table" then
			treat = table.clone(box)
		else
			log:error(`user {player.UserId}: the free Treat Box of day {today} was not granted:`, box)
			treatRequestId = nil
		end
	end
	deps.markDirty(player, FIELD)
	if reset then
		deps.notify(player, NOTICE_RESET, nil, "info")
	end
	log:info(`user {player.UserId} claimed daily day {today}: streak {streak}, {coins} Coins, treat {treat ~= nil}`)
	-- 6. one awaited "now" save carries the record, the Coins and the Treat Box (§3.4).
	local saved = deps.saveNow(player)
	if treat ~= nil then
		treat.savePending = not saved
	end
	-- 7. the reply
	local claimResult: Types.DailyClaimResult = {
		streakDay = streak,
		coins = coins,
		treat = treat,
		streakReset = reset,
		treatRequestId = treatRequestId,
	}
	return NetService.ok(claimResult)
end

-- Public: Studio debug -------------------------------------------------------------------------------------------------

-- Studio only: sets the daily record ({lastClaimDay?, streakDay?}, whole numbers; streakDay 0..#coinsByDay) of a ready
-- profile, e.g. lastClaimDay = today - 1 and streakDay = 6 so the next claim is day 7 with the Treat Box.
function DailyRewardService.debugSetState(player: any, values: unknown): (boolean, string?)
	if not deps.debugAllowed() then
		return false, "Studio only"
	end
	if type(values) ~= "table" then
		return false, "values must be a table {lastClaimDay?, streakDay?}"
	end
	local v = values :: { [string]: any }
	local last, streak = v.lastClaimDay, v.streakDay
	local cycle = #Config.Economy.Daily.coinsByDay
	if last ~= nil and not isWhole(last) then
		return false, "lastClaimDay must be a whole number"
	end
	if streak ~= nil and (not isWhole(streak) or streak < 0 or streak > cycle) then
		return false, `streakDay must be a whole number from 0 to {cycle}`
	end
	local ok = deps.data.mutate(player, function(profile: any): boolean
		local daily = profile.daily
		if type(daily) ~= "table" then
			daily = { lastClaimDay = -1, streakDay = 0, totalClaims = 0 }
			profile.daily = daily
		end
		if last ~= nil then
			daily.lastClaimDay = last
		end
		if streak ~= nil then
			daily.streakDay = streak
		end
		return true
	end)
	if not ok then
		return false, "profile not ready"
	end
	deps.markDirty(player, FIELD)
	return true, nil
end

-- Public: tests --------------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function DailyRewardService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function DailyRewardService.init()
	NetService.onInvoke(REMOTE_CLAIM, function(player: Player): any
		return DailyRewardService.claim(player)
	end)
end

return DailyRewardService
