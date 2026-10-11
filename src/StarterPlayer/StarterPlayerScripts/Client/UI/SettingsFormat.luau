--!strict
-- SettingsFormat (client only, pure). DESIGN §11.6 (Settings), §2.8 (SetSettings: a table with <= 4 keys from {music,
-- sfx, cameraShake, showTips}; music / sfx integers 0-100), §3.2 (defaults). What SettingsController computes:
--   KEYS                     the saved settings keys, in screen order
--   merge(server, edits)     the settings the player sees: the server's (defaults filled in) with local edits on top
--   patch(server, desired)   the SetSettings table: only the keys whose value differs from the server's (every key
--                            when the server sent none); empty = nothing to save
--   isEmpty(patch)
--   same(a, b)               equal on every key
--   volume(n)                a slider value as a saved integer 0-100
--   volumeText(n)            "40%" (common.percent)
--   bodyHeight(screenH, contentH, chromeH, maxShare, minH)   foam UI (2026-10-09): the scrolling rows' height (base
--                            px): the content's, capped so the whole panel (body + chrome: the header tab and Close
--                            above it, paddings, gaps) stays within maxShare of the screen height; never under minH
--                            (before, a fixed 60 px guess for the chrome)
--   captionShown(class, hasSound)   foam fix round 2: a slider's no-sound note shows while nothing is approved, never
--                            on the compact layout (phones: the switches field shows its top under the volumes)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

-- Types

export type Edits = { [string]: any }

-- Constants

local DATA = Config.Data
local KEYS: { string } = { "music", "sfx", "cameraShake", "showTips" }
local VOLUME_KEYS: { [string]: boolean } = { music = true, sfx = true }

-- Module table

local SettingsFormat = {}

SettingsFormat.KEYS = KEYS

-- Public

function SettingsFormat.volume(n: number): number
	if not (n == n) then
		return DATA.settingsMin
	end
	return math.clamp(math.floor(n + 0.5), DATA.settingsMin, DATA.settingsMax)
end

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

local function valid(key: string, value: any): boolean
	if VOLUME_KEYS[key] then
		return type(value) == "number" and value == value
	end
	return type(value) == "boolean"
end

function SettingsFormat.merge(server: Types.Settings?, edits: Edits): Types.Settings
	local defaults = DATA.DefaultSettings
	local base: { [string]: any } = {}
	for _, key in KEYS do
		local fromServer = if server then (server :: any)[key] else nil
		base[key] = if valid(key, fromServer) then fromServer else (defaults :: any)[key]
		local edited = edits[key]
		if valid(key, edited) then
			base[key] = edited
		end
		if VOLUME_KEYS[key] then
			base[key] = SettingsFormat.volume(base[key])
		end
	end
	return base :: any
end

function SettingsFormat.patch(server: Types.Settings?, desired: Types.Settings): Types.SettingsPatch
	local result: { [string]: any } = {}
	for _, key in KEYS do
		local wanted = (desired :: any)[key]
		local current = if server then (server :: any)[key] else nil
		if valid(key, wanted) and wanted ~= current then
			result[key] = if VOLUME_KEYS[key] then SettingsFormat.volume(wanted) else wanted
		end
	end
	return result :: any
end

function SettingsFormat.isEmpty(patch: Types.SettingsPatch): boolean
	return next(patch :: any) == nil
end

function SettingsFormat.same(a: Types.Settings?, b: Types.Settings?): boolean
	if a == nil or b == nil then
		return a == b
	end
	for _, key in KEYS do
		if (a :: any)[key] ~= (b :: any)[key] then
			return false
		end
	end
	return true
end

function SettingsFormat.volumeText(n: number): string
	return Strings.format(Strings.common.percent, { value = SettingsFormat.volume(n) })
end

-- The Settings panel's scrolling body: its content's height, capped so the panel (body + `chromeHeight`) stays within
-- `maxShare` of a screen `screenHeight` tall; never under `minHeight`. Bad numbers count as 0.
function SettingsFormat.bodyHeight(
	screenHeight: number,
	contentHeight: number,
	chromeHeight: number,
	maxShare: number,
	minHeight: number
): number
	local room = (if finite(screenHeight) then screenHeight else 0) * maxShare
		- (if finite(chromeHeight) then chromeHeight else 0)
	local content = if finite(contentHeight) then math.max(0, contentHeight) else 0
	return math.max(minHeight, math.min(content, room))
end

-- Whether a slider's "No music yet" / "No sound effects yet" note shows: only while none of its sounds is approved
-- (`hasSound` false), and never on the compact layout (fix round 2: on a phone the two notes pushed the switches field
-- just under the fold, so nothing showed that the list goes on).
function SettingsFormat.captionShown(class: string, hasSound: boolean): boolean
	return not hasSound and class ~= "compact"
end

return SettingsFormat
