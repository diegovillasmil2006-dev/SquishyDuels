--!strict
-- PerfFormat (client only, pure). LihFolk check 2026-10-31 (owner: "Ping + FPS only"): what PerfController shows.
--   MODES / nextMode(mode)     the Settings chip's order: "bad" (the default: only while the game runs badly),
--                              "always", "off"; the chip steps to the next one, after "off" back to "bad"
--   average(samples)           the mean of a list (0 for an empty one)
--   isBad(fps, pingMs)         FPS under Config.UI.Perf.badFps or ping from badPingMs up
--   shown(mode, fps, pingMs)   whether the number shows
--   text(fps, pingMs)          "60 FPS · 48 ms" (whole numbers)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)

-- Types

export type Mode = "bad" | "always" | "off"

-- Constants

local PERF = Config.UI.Perf
local MODES: { Mode } = { "bad", "always", "off" }

-- Module table

local PerfFormat = {}

PerfFormat.MODES = MODES

-- Public

function PerfFormat.nextMode(mode: Mode): Mode
	local index = table.find(MODES, mode) or 0
	return MODES[index % #MODES + 1]
end

function PerfFormat.average(samples: { number }): number
	if #samples == 0 then
		return 0
	end
	local sum = 0
	for _, value in samples do
		sum += value
	end
	return sum / #samples
end

function PerfFormat.isBad(fps: number, pingMs: number): boolean
	return fps < PERF.badFps or pingMs >= PERF.badPingMs
end

function PerfFormat.shown(mode: Mode, fps: number, pingMs: number): boolean
	return mode == "always" or (mode == "bad" and PerfFormat.isBad(fps, pingMs))
end

function PerfFormat.text(fps: number, pingMs: number): string
	return Strings.format(Strings.settings.perfReadout, { fps = math.round(fps), ping = math.round(pingMs) })
end

return PerfFormat
