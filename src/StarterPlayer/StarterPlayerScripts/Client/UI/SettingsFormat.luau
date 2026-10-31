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
-- UI FINAL R9 (plan work/ui/PLAN.md R9: G9.9, PR27, PR28; `H:n` = "Squishy Duels HUD.dc.html" line n):
--   ROWS                     the window's rows in order: the design's Sound effects, Screen shake and Reduced motion
--                            switches (H:979) and its Volume row (H:440, the SFX volume), then the game's Music volume
--                            (the Volume row's look) and its extras in the design's row look (Show tips, First-person
--                            duels, Ping & FPS, Replay tutorial): each { id, kind ("switch" / "volume" / "action" /
--                            "cycle"), text (a
--                            Strings key), icon (an AssetTable image key, or nil), key (the saved setting it drives) }
--   soundOn(sfx)             the Sound effects switch's state: the SFX volume is above 0 (no save key of its own)
--   sfxFor(on, last?)        the SFX volume the switch sets: 0 when off; on, the last volume above 0 this visit, else
--                            the default (Config.Data.DefaultSettings.sfx)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

-- Types

export type Edits = { [string]: any }

-- UI FINAL R9: one Settings row (ROWS).
export type RowKind = "switch" | "volume" | "action" | "cycle" -- cycle: a chip that steps through modes
export type Row = { id: string, kind: RowKind, text: string, icon: string?, key: string? }

-- Constants

local DATA = Config.Data
local KEYS: { string } = { "music", "sfx", "cameraShake", "showTips" }
local VOLUME_KEYS: { [string]: boolean } = { music = true, sfx = true }
-- UI FINAL R9 (H:979, H:440; PR27, PR28): the rows in order; their stable names are SettingsController's.
local ROWS: { Row } = {
	{ id = "sound", kind = "switch", text = "settings.sfx", icon = "img.icon.sound", key = "sfx" }, -- H:979
	{ id = "cameraShake", kind = "switch", text = "settings.cameraShake", icon = "img.icon.bolt", key = "cameraShake" },
	{ id = "reducedMotion", kind = "switch", text = "settings.reducedMotion", icon = "img.icon.clock" }, -- UiPrefs
	{ id = "sfx", kind = "volume", text = "settings.volume", icon = "img.icon.sound", key = "sfx" }, -- H:440-447
	{ id = "music", kind = "volume", text = "settings.music", icon = "img.icon.sound", key = "music" }, -- PR27
	{ id = "showTips", kind = "switch", text = "settings.showTips", icon = "img.icon.star", key = "showTips" }, -- PR28
	{ id = "firstPerson", kind = "switch", text = "settings.firstPerson", icon = "img.nav.duel" }, -- PR28 (session)
	{ id = "perf", kind = "cycle", text = "settings.perf" }, -- 2026-10-31 (session): PerfController's mode
	{ id = "replayTutorial", kind = "action", text = "settings.replayTutorial" }, -- PR28: the chip, no picture
}

-- Module table

local SettingsFormat = {}

SettingsFormat.KEYS = KEYS
SettingsFormat.ROWS = ROWS

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

-- UI FINAL R9 (PR27): the Sound effects switch is on while the SFX volume is above 0.
function SettingsFormat.soundOn(sfx: unknown): boolean
	return type(sfx) == "number" and sfx == sfx and sfx > DATA.settingsMin
end

-- UI FINAL R9 (PR27): the SFX volume the Sound effects switch sets: 0 off; on, `last` (the last volume above 0 this
-- visit) or the default.
function SettingsFormat.sfxFor(on: boolean, last: number?): number
	if not on then
		return DATA.settingsMin
	end
	if last ~= nil and SettingsFormat.soundOn(last) then
		return SettingsFormat.volume(last)
	end
	return DATA.DefaultSettings.sfx
end

return SettingsFormat
