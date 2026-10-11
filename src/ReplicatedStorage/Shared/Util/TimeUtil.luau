--!strict
-- TimeUtil (shared). UTC day index and countdown helpers. Pure: every function takes the time it needs.
-- Day index (DESIGN §6.9): math.floor(os.time() / 86400), so a new day starts at 00:00 UTC.
-- Countdown text is digits and colons only ("2:05:09", "4:07"); worded templates such as
-- "New quests in {h}h {m}m" live in Strings and take their numbers from splitDuration.

-- Constants

local SECONDS_PER_DAY = 86400
local SECONDS_PER_HOUR = 3600
local SECONDS_PER_MINUTE = 60

-- Module table

local TimeUtil = {}

-- Public

-- UTC day index for Unix time t (seconds).
function TimeUtil.utcDay(t: number): number
	return math.floor(t / SECONDS_PER_DAY)
end

-- Seconds from t until the next 00:00 UTC, in (0, 86400].
function TimeUtil.secondsUntilNextUtcDay(t: number): number
	return (TimeUtil.utcDay(t) + 1) * SECONDS_PER_DAY - t
end

-- Whole hours, minutes and seconds in a duration (fractions dropped). Negative or non-finite -> 0, 0, 0.
function TimeUtil.splitDuration(seconds: number): (number, number, number)
	local total = 0
	if seconds == seconds and seconds > 0 and seconds < math.huge then
		total = math.floor(seconds)
	end
	return total // SECONDS_PER_HOUR, (total % SECONDS_PER_HOUR) // SECONDS_PER_MINUTE, total % SECONDS_PER_MINUTE
end

-- Remaining time as "h:mm:ss" (one hour or more) or "m:ss". Rounds up to whole seconds, so it shows
-- "0:01" until the time is really over, then "0:00".
function TimeUtil.formatCountdown(seconds: number): string
	local hours, minutes, secs = TimeUtil.splitDuration(math.ceil(seconds))
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, secs)
	end
	return string.format("%d:%02d", minutes, secs)
end

return TimeUtil
