--!strict
-- UpdateClockService (server only). Big job item 8 (2026-11-10): the "Next update in..." countdown's date. The owner
-- sets the experience config `next_update` (Creator Hub > Configs: a text like 2026-12-05T18:00:00Z, UTC, or Unix
-- seconds; no publish needed); this service reads it through SwitchService (which owns the configs snapshot), parses
-- it (Shared/UpdateClock.parse) and puts it on Workspace as the attribute SD_NextUpdateAt (Unix seconds), which every
-- client reads (Controllers/EventController: the event pill). No config, or a value that is not a date: the attribute
-- is removed and no countdown shows. A date in the past shows "NEW UPDATE!" for an hour, then nothing.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpdateClock = require(ReplicatedStorage.Shared.UpdateClock)
local SwitchService = require(script.Parent.SwitchService)

local UpdateClockService = {}

local function apply()
	Workspace:SetAttribute(UpdateClock.ATTRIBUTE, UpdateClock.parse(SwitchService.value(UpdateClock.CONFIG)))
end

function UpdateClockService.init()
	SwitchService.onChanged(apply)
end

-- The configs may be loaded already (the listener then never heard that load).
function UpdateClockService.start()
	apply()
end

return UpdateClockService
