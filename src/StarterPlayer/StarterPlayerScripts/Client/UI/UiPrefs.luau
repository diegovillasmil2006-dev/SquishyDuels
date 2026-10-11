--!strict
-- UiPrefs (client only). UI overhaul (2026-10-11): the player's in-game presentation preferences, one place every UI
-- module reads them from. SettingsController writes them from the saved settings (and at once while the player
-- edits): 
--   reduceMotion   true: no scale pops, bounces, travel or shake (Anim/Tweens.reducedMotion ORs it with Roblox's own
--                  GuiService.ReducedMotionEnabled)
--   fewerEffects   true: the UI celebrations (UI/UiFx) draw about half their pieces
-- set(key, value) fires Changed(key, value) only when a value changes. Pure state: no instances, no services.

-- Requires

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Shared.Util.Signal)

-- Types

export type Key = "reduceMotion" | "fewerEffects"

-- Module table

local UiPrefs = {}

UiPrefs.Changed = Signal.new() :: Signal.Signal<string, boolean>

local values: { [string]: boolean } = {
	reduceMotion = false,
	fewerEffects = false,
}

-- Public

function UiPrefs.get(key: Key): boolean
	return values[key] == true
end

function UiPrefs.set(key: Key, value: boolean)
	local on = value == true
	if values[key] == on then
		return
	end
	values[key] = on
	UiPrefs.Changed:fire(key, on)
end

return UiPrefs
