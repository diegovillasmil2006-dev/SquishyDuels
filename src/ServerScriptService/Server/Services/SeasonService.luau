--!strict
-- SeasonService (server only). Big job item 11 (2026-11-10): the Christmas event's switch. The event is built and OFF.
-- The owner turns it on with the experience config `event_christmas` (Creator Hub > Configs; no publish needed): the
-- event's END date, a text like 2027-01-06T00:00:00Z (UTC) or Unix seconds. This service reads it through
-- SwitchService (which owns the configs snapshot), parses it (Shared/UpdateClock.parse) and puts it on Workspace as
-- the attribute Config/Christmas.attribute (Unix seconds), which the server and every client read (Shared/Seasons).
-- No config, or a value that is not a date: the attribute is removed and the event is off. A date in the past is off
-- too (Seasons.isOn compares it with the clock).
--   SeasonService.isOn() -> boolean   the event is on now (the server's clock)

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Christmas = require(ReplicatedStorage.Shared.Config.Christmas)
local Seasons = require(ReplicatedStorage.Shared.Seasons)
local UpdateClock = require(ReplicatedStorage.Shared.UpdateClock)
local SwitchService = require(script.Parent.SwitchService)

local SeasonService = {}

local function apply()
	Workspace:SetAttribute(Christmas.attribute, UpdateClock.parse(SwitchService.value(Christmas.config)))
end

function SeasonService.isOn(): boolean
	return Seasons.isOn(Workspace:GetAttribute(Christmas.attribute), os.time())
end

function SeasonService.init()
	SwitchService.onChanged(apply)
end

-- The configs may be loaded already (the listener then never heard that load).
function SeasonService.start()
	apply()
end

return SeasonService
