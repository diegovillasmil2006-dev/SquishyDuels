--!strict
-- AutoClickRules (server only, pure). Auto-clicker check (owner 2026-10-16): the rule that tells a machine from a
-- person on the squeeze requests, and the step-by-step ladder. Every number is in Config.Net.AutoClick (with why).
-- No instances, no yields, no profile writes: AutoClickService keeps one State per player, calls observe() with the
-- arrival time (os.clock) of every SqueezeRequest and acts on a Verdict.
-- Review fix (2026-10-16, job autoclick): the "too fast" rule (rule A) is gone. Speed alone is no proof: a kid
-- mashing F + E + a click sends 17-25 presses a second, and past the client's ceiling (clientPressesPerSecond) every
-- stream has the ceiling's own rhythm, so a window as fast as maxPerSecond is never judged either.
-- P13v3 (owner 2026-10-18: "Yes, above 20 a second"): a speed rule again (speed below), on the real presses the
-- clients count on their own clock (Shared/PressSpeed) and report, not on the arrival rhythm; only seconds in a row
-- above the owner's line count.
--   newState(cfg?) -> State
--   observe(state, now, cfg?) -> Verdict?  records one request (changes `state` in place); a Verdict when the rule
--     catches the stream:
--       "regular" a window of windowIntervals gaps of one burst (a gap over burstGapSeconds starts a new window)
--                 whose mean gap is <= maxMeanGapSeconds and above 1 / maxPerSecond, and whose block means
--                 (blockIntervals gaps each) have a standard deviation <= maxBlockSpreadSeconds. A full window always
--                 starts the next one at its last request (tumbling windows: one verdict per window).
--   reset(state, cfg?)  forgets everything (after a catch: the next catch needs new proof).
--   newSpeedState() -> SpeedState; speed(state, fastSeconds, cfg?) -> Verdict?  p13v3 (owner 2026-10-18: "Yes, above
--     20 a second", squeezes and throws; Config.Net.AutoClick.speed): one request's report, the whole seconds in a row
--     the client counted with more than speed.perSecond presses each (Shared/PressSpeed; anything not a number, or
--     below 0, is 0); "speed" at speed.seconds or more, then the next catch needs speed.seconds more (a lower report:
--     that run ended, the next one needs speed.seconds again). Verification fix: the server's arrival second made a
--     person at 16-18 a second look faster after a lag spike; the client's own clock never does.
--   resetSpeed(state)  every count starts again (a catch of any rule): the next speed catch needs speed.seconds more.
--   flood(times, now, limit) -> Verdict?  pens3 phase 13 (the THROW presses, AutoClickService.checkThrow): records one
--     arrival in `times` (changed in place: only the last second's are kept); "flood" when more than `limit` arrived
--     inside one second (a rate our client never sends: only a changed client or a script), then the count starts
--     again. Rule B on the throw presses is observe() with Config.Economy.Highway.autoClick's window numbers.
--   memoryStep(memory, unixNow, cfg?) -> the step the profile remembers (profile.autoClick = {step, at}) while its
--     `at` is younger than memorySeconds, else 0; a ban (step >= BAN_STEP) is never forgotten (owner 2026-10-17);
--     anything malformed -> 0 (never punish on a broken record).
--   nextStep(sessionStep, memory, unixNow, cfg?) -> 1 .. lastStep: one past the higher of this visit's step and the
--     remembered one, at most the ladder's last step (BAN_STEP + #laterBanSeconds; that ban repeats).
--   actionFor(step) -> "warn" (1) | "kick" (2) | "ban" (3 and up).
--   banSeconds(step, cfg?) -> a ban step's length: banSeconds for the 1st ban (step 3), then laterBanSeconds in turn,
--     the last one again after that (owner 2026-10-17: after a ban ends the next catch is a longer ban).
-- `now` = os.clock() seconds; `unixNow` = os.time(). cfg = a table shaped like Config.Net.AutoClick (a test's copy);
-- nil = the live one.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

export type Enforce = "log" | "warn" | "full"

export type Rules = {
	enabled: boolean,
	enforce: Enforce,
	clientPressesPerSecond: number,
	maxPerSecond: number,
	windowIntervals: number,
	blockIntervals: number,
	maxMeanGapSeconds: number,
	maxBlockSpreadSeconds: number,
	burstGapSeconds: number,
	penaltySeconds: number,
	memorySeconds: number,
	banSeconds: number,
	laterBanSeconds: { number },
	banExcludeAltAccounts: boolean,
	speed: { perSecond: number, seconds: number }, -- p13v3
}

export type State = {
	window: { number }, -- arrival times of the window being filled (at most windowIntervals + 1)
}

-- P13v3: the speed rule's reports (one a player and a kind of press: squeezes, throws).
export type SpeedState = {
	last: number, -- the latest report (seconds in a row over the line, the client's count)
	used: number, -- the report the last catch used (the next catch needs speed.seconds more)
}

export type Rule = "regular" | "flood" | "speed"
export type Action = "warn" | "kick" | "ban"

export type Verdict = {
	rule: Rule,
	value: number, -- the block spread (seconds); "flood": the arrivals inside the second; "speed": the seconds in a row
	limit: number, -- the Config value it was compared with
	count: number, -- gaps judged
	seconds: number, -- how long they took
	meanGap: number, -- the window's mean gap (seconds)
}

-- Constants

local BAN_STEP = 3 -- the 1st ban; each later catch is one more (longer) ban step
local ACTIONS: { Action } = { "warn", "kick", "ban" }

-- Module table

local AutoClickRules = {}

-- Private

local function rules(cfg: Rules?): Rules
	return if cfg ~= nil then cfg else (Config :: any).Net.AutoClick
end

-- The longer bans after the 1st one (none when the config has no list: ValidateAutoClick reports that).
local function later(c: Rules): { number }
	local list = (c :: any).laterBanSeconds
	return if type(list) == "table" then list else {}
end

-- The ladder's last step: its last ban repeats from there.
local function lastStep(c: Rules): number
	return BAN_STEP + #later(c)
end

AutoClickRules.BAN_STEP = BAN_STEP
AutoClickRules.MAX_STEP = lastStep(rules(nil)) -- the live ladder's last step (ProfileSchema clamps a saved strike to it)

local function isFinite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- The rule on a full window (windowIntervals + 1 arrival times). nil = not a machine (or not judged: too slow, or as
-- fast as the client ceiling's own rhythm).
local function judge(window: { number }, c: Rules): Verdict?
	local gaps = c.windowIntervals
	local span = window[gaps + 1] - window[1]
	local meanGap = span / gaps
	if meanGap > c.maxMeanGapSeconds or meanGap <= 1 / c.maxPerSecond then
		return nil
	end
	local size = c.blockIntervals
	local blocks = gaps // size
	local means: { number } = table.create(blocks)
	local sum = 0
	for b = 0, blocks - 1 do
		local m = (window[(b + 1) * size + 1] - window[b * size + 1]) / size
		means[b + 1] = m
		sum += m
	end
	local average = sum / blocks
	local squares = 0
	for _, m in means do
		squares += (m - average) * (m - average)
	end
	local spread = math.sqrt(squares / (blocks - 1))
	if spread > c.maxBlockSpreadSeconds then
		return nil
	end
	return {
		rule = "regular",
		value = spread,
		limit = c.maxBlockSpreadSeconds,
		count = gaps,
		seconds = span,
		meanGap = meanGap,
	}
end

-- Public -------------------------------------------------------------------------------------------------------------

function AutoClickRules.newState(_cfg: Rules?): State
	return { window = {} }
end

function AutoClickRules.reset(state: State, _cfg: Rules?)
	table.clear(state.window)
end

function AutoClickRules.observe(state: State, now: number, cfg: Rules?): Verdict?
	local c = rules(cfg)
	-- Tumbling windows of one burst.
	local window = state.window
	local previous = window[#window]
	if previous ~= nil and now - previous > c.burstGapSeconds then
		table.clear(window)
	end
	table.insert(window, now)
	if #window <= c.windowIntervals then
		return nil
	end
	local verdict = judge(window, c)
	table.clear(window)
	table.insert(window, now)
	return verdict
end

function AutoClickRules.flood(times: { number }, now: number, limit: number): Verdict?
	local kept = 0
	for _, at in times do
		if now - at < 1 then
			kept += 1
			times[kept] = at
		end
	end
	for index = #times, kept + 1, -1 do
		times[index] = nil
	end
	table.insert(times, now)
	if #times <= limit then
		return nil
	end
	local count = #times
	table.clear(times)
	return { rule = "flood", value = count, limit = limit, count = count, seconds = 1, meanGap = 1 / count }
end

function AutoClickRules.newSpeedState(): SpeedState
	return { last = 0, used = 0 }
end

function AutoClickRules.resetSpeed(state: SpeedState)
	state.used = state.last
end

function AutoClickRules.speed(state: SpeedState, fastSeconds: unknown, cfg: Rules?): Verdict?
	local s = rules(cfg).speed
	local n = if isFinite(fastSeconds) then math.max(math.floor(fastSeconds :: number), 0) else 0
	if n < state.last then
		state.used = 0 -- that run ended: a new one needs speed.seconds again
	end
	state.last = n
	if n < state.used + s.seconds then
		return nil
	end
	state.used = n
	return { rule = "speed", value = n, limit = s.perSecond, count = n, seconds = n, meanGap = 0 }
end

function AutoClickRules.memoryStep(memory: unknown, unixNow: number, cfg: Rules?): number
	if type(memory) ~= "table" then
		return 0
	end
	local step, at = (memory :: any).step, (memory :: any).at
	if not isFinite(step) or not isFinite(at) or step < 1 or math.floor(step) ~= step then
		return 0
	end
	local c = rules(cfg)
	if step < BAN_STEP and unixNow - at >= c.memorySeconds then
		return 0 -- a warning or a kick is forgotten after memorySeconds; a ban never is (owner 2026-10-17)
	end
	return math.min(step, lastStep(c))
end

function AutoClickRules.nextStep(sessionStep: number, memory: unknown, unixNow: number, cfg: Rules?): number
	local before = math.max(sessionStep, AutoClickRules.memoryStep(memory, unixNow, cfg))
	return math.min(before + 1, lastStep(rules(cfg)))
end

function AutoClickRules.actionFor(step: number): Action
	return ACTIONS[math.clamp(step, 1, BAN_STEP)]
end

function AutoClickRules.banSeconds(step: number, cfg: Rules?): number
	local c = rules(cfg)
	local list = later(c)
	local index = math.min(step - BAN_STEP, #list)
	return if index >= 1 then list[index] else c.banSeconds
end

return table.freeze(AutoClickRules)
