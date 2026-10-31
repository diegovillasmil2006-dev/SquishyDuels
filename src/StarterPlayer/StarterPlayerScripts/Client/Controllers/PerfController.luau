--!strict
-- PerfController (client only). LihFolk check 2026-10-31 (owner: "Ping + FPS only", "Yes, start step 1"): a small
-- "60 FPS · 48 ms" number in the bottom-left corner (SD_Overlay, over the windows), one sample a second averaged over
-- the last Config.UI.Perf.samples (UI/PerfFormat). FPS = frames drawn in the second; ping = Player:GetNetworkPing().
-- Settings' "Ping & FPS" chip picks the mode (PerfFormat.MODES): When bad (the default: only while FPS or ping is
-- bad, the number in red), Always, Off. A session setting like First-person duels: never saved.
-- shortcut: the mode goes back to When bad every visit; save it with the settings if players ask for it.
-- Stand-in look (the HUD's small text) until Diego draws one (his to-do).
-- Stable name: Perf_Readout.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local Client = script.Parent.Parent
local PerfFormat = require(Client.UI.PerfFormat)
local Theme = require(Client.UI.Theme)
local UIController = require(script.Parent.UIController)

-- Constants

local PERF = Config.UI.Perf
local GUI = "SD_Overlay"
local TEXT_KIND: Theme.TextKind = "Small"
local WIDEST = PerfFormat.text(999, 9999) -- sizes the label (AutomaticSize misreads under the UIScale)

-- Module table

local PerfController = {}

-- Private

local cleanup: Cleanup.Cleanup? = nil
local label: TextLabel? = nil
local mode: PerfFormat.Mode = PerfFormat.MODES[1]
local fpsSamples: { number } = {}
local pingSamples: { number } = {}

local function push(list: { number }, value: number)
	table.insert(list, value)
	if #list > PERF.samples then
		table.remove(list, 1)
	end
end

local function refresh()
	local readout = label
	if not readout then
		return
	end
	local fps, ping = PerfFormat.average(fpsSamples), PerfFormat.average(pingSamples)
	readout.Visible = #fpsSamples > 0 and PerfFormat.shown(mode, fps, ping)
	readout.Text = PerfFormat.text(fps, ping)
	readout.TextColor3 = if PerfFormat.isBad(fps, ping) then Palette.CandyRed else Palette.WarmWhite
end

-- Public

function PerfController.mode(): PerfFormat.Mode
	return mode
end

function PerfController.setMode(value: PerfFormat.Mode)
	mode = value
	refresh()
end

-- Lifecycle

function PerfController.init()
	local c = Cleanup.new()
	cleanup = c
	local bounds = Theme.textBounds(WIDEST, TEXT_KIND)
	label = c:add(Theme.label({
		Name = "Perf_Readout",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, PERF.marginPx, 1, -PERF.marginPx),
		Size = UDim2.fromOffset(math.ceil(bounds.X) + 2, math.ceil(bounds.Y)),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = UIController.screenGui(GUI),
	}, TEXT_KIND))
	local player = Players.LocalPlayer
	local frames, since = 0, os.clock()
	c:add(RunService.RenderStepped:Connect(function()
		frames += 1
		local now = os.clock()
		if now - since < PERF.sampleSeconds then
			return
		end
		push(fpsSamples, frames / (now - since))
		push(pingSamples, player:GetNetworkPing() * 1000)
		frames, since = 0, now
		refresh()
	end))
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function PerfController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
	label = nil
	table.clear(fpsSamples)
	table.clear(pingSamples)
end

return PerfController
