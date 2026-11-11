--!strict
-- Seasons (shared, pure). Big job item 11 (2026-11-10): the seasonal events' rules; today one event, Christmas
-- (Config/Christmas: built, and off until the owner sets its end date in the experience config `event_christmas`).
-- The server puts that end on Workspace as the attribute Config/Christmas.attribute (Unix seconds; absent = off);
-- the server reads it with os.time(), a client with Workspace:GetServerTimeNow(). LihFolk vault "Limited-Time Offers -
-- Design and Ethics": the end shown is the real one, and a seasonal item is labelled seasonal (it comes back).
-- No instances, no yields, no side effects.
--
-- API:
--   Seasons.EVENT                         "christmas"
--   Seasons.ATTRIBUTE                     the Workspace attribute holding the event's end
--   Seasons.isOn(untilAt, now) -> boolean  the event is on: its end is a real time still ahead of `now`
--                                          (a seasonal squishy's price: Shared/Pricing.shopPrice(id, owned, on))
--   Seasons.defs(owned, on) -> {SquishyDef}  the squishies a player's own lists show: the year-round ones in catalog
--                                          order, then each seasonal one that is on sale (on) or already owned
--                                          (`owned`: the profile's owned map)
--   Seasons.left(untilAt, now) -> string?  "5d 03h" | "3h 12m" | "12:05" left while it is on (UpdateClock.time)
--   Seasons.pill(text, live, untilAt, now) -> string  the event pill's text: `text` (the hourly event's or the
--                                          update's line); while the season is on and no hourly event is live, the
--                                          season's line ("Christmas: 5d 03h left") takes the first PILL_SECONDS
--                                          of every UpdateClock.TURN_SECONDS (the same moments on every client)

local Catalog = require(script.Parent.Catalog)
local Christmas = require(script.Parent.Config.Christmas)
local UpdateClock = require(script.Parent.UpdateClock)

local Strings = require(script.Parent.Strings)

local Seasons = {}

Seasons.EVENT = Christmas.event
Seasons.ATTRIBUTE = Christmas.attribute
Seasons.PILL_SECONDS = 3

local function finite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Seasons.isOn(untilAt: unknown, now: unknown): boolean
	return finite(untilAt) and finite(now) and (now :: number) < (untilAt :: number)
end

function Seasons.defs(owned: unknown, on: unknown): { any }
	local list = Catalog.list()
	for _, def in Catalog.seasonal(Seasons.EVENT) do
		if on == true or (type(owned) == "table" and (owned :: any)[def.id] ~= nil) then
			table.insert(list, def)
		end
	end
	return list
end

function Seasons.left(untilAt: unknown, now: unknown): string?
	if not Seasons.isOn(untilAt, now) then
		return nil
	end
	return UpdateClock.time((untilAt :: number) - (now :: number))
end

function Seasons.pill(text: string, live: unknown, untilAt: unknown, now: unknown): string
	local left = if live == true then nil else Seasons.left(untilAt, now)
	if left == nil or (now :: number) % UpdateClock.TURN_SECONDS >= Seasons.PILL_SECONDS then
		return text
	end
	return Strings.format(Strings.season.christmas.pill, { time = left })
end

return table.freeze(Seasons)
