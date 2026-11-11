--!strict
-- UpdateClock (shared, pure). Big job item 8 (2026-11-10; the owner's "Next update in..." countdown; where it shows
-- was open, so Claude's call: the event pill under DUEL takes turns with it, no new HUD piece). LihFolk vault "Update
-- Cadence and Hype Cycles": a countdown must be true: the real date, the server's clock, never restarted, and nothing
-- at all while no date is set.
-- The date is the experience config `next_update` (Creator Hub > Configs: a text like 2026-12-05T18:00:00Z, UTC, or a
-- number of Unix seconds); the server puts it on Workspace as the attribute SD_NextUpdateAt (Unix seconds; absent =
-- no date), clients read it with Workspace:GetServerTimeNow(). No instances, no yields, no side effects.
--
-- API:
--   UpdateClock.parse(value)            -> Unix seconds, or nil for anything that is not a date
--   UpdateClock.time(left)              -> "2d 05h" | "5h 12m" | "12:05" for the seconds left
--   UpdateClock.text(at, now)           -> "Update in 2d 05h"; "NEW UPDATE!" for LIVE_SECONDS from the date; nil
--                                          without a date or after that
--   UpdateClock.pill(event, live, at, now) -> the event pill's text: the event's own line; while there is an update
--                                          text and no event is live, the update's line takes the last UPDATE_SECONDS
--                                          of every TURN_SECONDS (the same moments on every client)

local Strings = require(script.Parent.Strings)

local DAY, HOUR, MINUTE = 86400, 3600, 60

local UpdateClock = {}

UpdateClock.CONFIG = "next_update"
UpdateClock.ATTRIBUTE = "SD_NextUpdateAt"
UpdateClock.LIVE_SECONDS = HOUR -- how long "NEW UPDATE!" shows once the date has come
UpdateClock.TURN_SECONDS = 10
UpdateClock.UPDATE_SECONDS = 4

local function finite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function UpdateClock.parse(value: unknown): number?
	if finite(value) then
		return if (value :: number) > 0 then math.floor(value :: number) else nil
	end
	if type(value) ~= "string" then
		return nil
	end
	local text = string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")
	text = string.gsub(text, "^(%d%d%d%d%-%d%d%-%d%d) ", "%1T") -- "2026-12-05 18:00" is taken too
	if string.match(text, "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d$") then
		text ..= ":00"
	end
	if string.match(text, "T") and not string.match(text, "[Zz]$") and not string.match(text, "[%+%-]%d%d:?%d%d$") then
		text ..= "Z" -- no zone written: UTC
	end
	local ok, date = pcall(DateTime.fromIsoDate, text)
	if not ok or typeof(date) ~= "DateTime" then
		return nil
	end
	return date.UnixTimestamp
end

function UpdateClock.time(left: number): string
	local seconds = if finite(left) then math.max(0, math.floor(left)) else 0
	local days = seconds // DAY
	local hours = (seconds % DAY) // HOUR
	local minutes = (seconds % HOUR) // MINUTE
	if days > 0 then
		return string.format("%dd %02dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%d:%02d", minutes, seconds % MINUTE)
end

function UpdateClock.text(at: unknown, now: number): string?
	if not finite(at) or not finite(now) then
		return nil
	end
	local left = (at :: number) - now
	if left > 0 then
		return Strings.format(Strings.savings.update, { time = UpdateClock.time(left) })
	elseif left > -UpdateClock.LIVE_SECONDS then
		return Strings.savings.updateLive
	end
	return nil
end

function UpdateClock.pill(event: string, live: boolean, at: unknown, now: number): string
	local update = if live then nil else UpdateClock.text(at, now)
	if update == nil or not finite(now) then
		return event
	end
	local turn = now % UpdateClock.TURN_SECONDS
	return if turn >= UpdateClock.TURN_SECONDS - UpdateClock.UPDATE_SECONDS then update else event
end

return table.freeze(UpdateClock)
