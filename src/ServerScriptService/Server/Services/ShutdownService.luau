--!strict
-- ShutdownService (server only). DESIGN §2.3, §3.12, §5.4 (edge-case rows ServerRestartScheduled and Closing).
-- * The ONLY game:BindToClose in the game. When the server closes:
--     1. the closing flag is set and the `Closing` signal fires (handlers start at once, in connection order, and run
--        until their first yield: DuelService voids live matches with duel.void, QueueService clears the queue and
--        stops accepting, BoxService/ShopService reject from then on);
--     2. every close task added with addCloseTask runs in parallel (Part 5: DataService.releaseAllAsync) and BindToClose
--        waits for them, at most Config.Data.closeDeadline seconds (Roblox allows 30).
--   isClosing() is the flag every service checks before starting new work.
-- * DataModel.ServerRestartScheduled (§3.12): records the restart time (server time), fires `RestartScheduled`
--   (QueueService pauses joins and clears the queue with queue.paused; DuelService cancels matches that cannot finish
--   before restart - Config.Duel.RestartMarginSeconds and lets the others continue, §5.4) and notifies every player,
--   including later joiners, with `server.restartSoon` {time}. canFinishBeforeRestart(seconds) answers the margin rule.
-- * This module never touches matches itself: services above it in the layer order listen to its signals (§2.6 rule 2).
-- * Studio only (Config.Debug.debugHooks): debugScheduleRestart(seconds) simulates a scheduled restart for tests.
-- init() never yields; the restart notice is sent through NetService (same layer, wired before this module).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local TimeUtil = require(Shared.Util.TimeUtil)
local NetService = require(script.Parent.NetService)

-- Types

export type CloseTask = { name: string, fn: () -> () }

-- Constants

local RESTART_NOTICE = "server.restartSoon"
local POLL_SECONDS = 0.05 -- how often the close wait checks for finished tasks

-- Module table

local ShutdownService = {}

-- Fired once, when BindToClose starts (after isClosing() turns true).
ShutdownService.Closing = Signal.new() :: Signal.Signal<>
-- Fired with (restartAt: server time, reason: string) when a restart is scheduled (once per new restart time).
ShutdownService.RestartScheduled = Signal.new() :: Signal.Signal<number, string>

-- Private

local log = Log.new("Shutdown")
local closing = false
local restartAt: number? = nil
local restartReason = ""
local closeTasks: { CloseTask } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function restartNoticeArgs(now: number): { [string]: string | number }?
	local at = restartAt
	if at == nil then
		return nil
	end
	local args: { [string]: string | number } = { time = TimeUtil.formatCountdown(math.max(0, at - now)) }
	return args
end

local function onClose()
	ShutdownService.beginClosing()
	local done, total = ShutdownService.runTasksAsync(closeTasks, Config.Data.closeDeadline)
	if done < total then
		log:warn(`{total - done} of {total} close tasks did not finish within {Config.Data.closeDeadline} s`)
	end
end

-- Public: pure helpers (unit-tested) -----------------------------------------------------------------------------------

-- Runs every task in its own thread and waits until all have finished or `deadlineSeconds` passed (measured with
-- os.clock). A task that errors is logged and counts as finished. Returns (finished, total). Yields.
function ShutdownService.runTasksAsync(tasks: { CloseTask }, deadlineSeconds: number): (number, number)
	local total = #tasks
	if total == 0 then
		return 0, 0
	end
	local finished = 0
	for _, closeTask in tasks do
		task.spawn(function()
			local ok, err = xpcall(function(): any
				closeTask.fn()
				return nil
			end, function(e: any): string
				return debug.traceback(tostring(e), 2)
			end)
			if not ok then
				log:error(`close task {closeTask.name} failed:`, err)
			end
			finished += 1
		end)
	end
	local deadline = os.clock() + math.max(0, deadlineSeconds)
	while finished < total and os.clock() < deadline do
		task.wait(POLL_SECONDS)
	end
	return finished, total
end

-- Seconds from `now` to `restartAtSeconds` (both server time), never below 0; a non-finite result is 0.
function ShutdownService.secondsUntil(restartAtSeconds: number, now: number): number
	local left = restartAtSeconds - now
	if left ~= left or left == math.huge then
		return 0
	end
	return math.max(0, left)
end

-- True when something that needs `seconds` more can end before the restart minus the margin (§3.12), or when no
-- restart is scheduled. `at` / `now` default to the scheduled restart and the server time.
function ShutdownService.canFinishBeforeRestart(seconds: number, at: number?, now: number?): boolean
	local restart = if at ~= nil then at else restartAt
	if restart == nil then
		return true
	end
	local t = if now ~= nil then now else serverNow()
	return t + seconds <= restart - Config.Duel.RestartMarginSeconds
end

-- Public: state --------------------------------------------------------------------------------------------------------

-- True once BindToClose started. Services refuse new work from then on.
function ShutdownService.isClosing(): boolean
	return closing
end

-- True while a restart is scheduled (QueueJoin -> queue.paused, box opens paused).
function ShutdownService.isRestartPending(): boolean
	return restartAt ~= nil
end

-- The scheduled restart in server time (workspace:GetServerTimeNow() seconds), or nil.
function ShutdownService.restartAt(): number?
	return restartAt
end

-- Adds a task that BindToClose runs (in parallel with the others) after `Closing` fired, and waits for, up to
-- Config.Data.closeDeadline seconds. Part 5: DataService.releaseAllAsync. Returns a function that removes it.
function ShutdownService.addCloseTask(name: string, fn: () -> ()): () -> ()
	assert(type(fn) == "function", "[SD][Shutdown] a close task must be a function")
	local entry: CloseTask = { name = name, fn = fn }
	table.insert(closeTasks, entry)
	return function()
		local index = table.find(closeTasks, entry)
		if index then
			table.remove(closeTasks, index)
		end
	end
end

-- Sets the closing flag and fires `Closing` (once). Called by BindToClose; never call it from gameplay code.
function ShutdownService.beginClosing()
	if closing then
		return
	end
	closing = true
	log:info("server closing")
	ShutdownService.Closing:fire()
end

-- Records a restart at `at` (server time) and tells everyone. A later or equal time than the one already scheduled
-- changes nothing.
function ShutdownService.scheduleRestart(at: number, reason: string?)
	if at ~= at or at == math.huge or at == -math.huge then
		at = serverNow()
	end
	local current = restartAt
	if current ~= nil and at >= current then
		return
	end
	restartAt = at
	restartReason = reason or "restart"
	log:info(
		string.format("restart scheduled in %.0f s (%s)", ShutdownService.secondsUntil(at, serverNow()), restartReason)
	)
	ShutdownService.RestartScheduled:fire(at, restartReason)
	NetService.notifyAll(RESTART_NOTICE, restartNoticeArgs(serverNow()), "warn")
end

-- Studio only (Config.Debug.debugHooks): pretends a restart was scheduled `seconds` from now. Returns false elsewhere.
function ShutdownService.debugScheduleRestart(seconds: number): boolean
	if not (RunService:IsStudio() and Config.Debug.debugHooks) then
		return false
	end
	ShutdownService.scheduleRestart(serverNow() + math.max(0, seconds), "studioTest")
	return true
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function ShutdownService.init()
	game:BindToClose(onClose)
	local ok, err = pcall(function(): any
		return game.ServerRestartScheduled:Connect(function(when: DateTime, reason: EnumItem?)
			local at = when.UnixTimestampMillis / 1000
			ShutdownService.scheduleRestart(at, if reason then reason.Name else nil)
		end)
	end)
	if not ok then
		log:warn("ServerRestartScheduled is not available; restart notices are off:", err)
	end
end

-- Players who join while a restart is pending get the notice too (reading: §3.12 names the notice, not its audience).
function ShutdownService.playerAdded(player: Player)
	if restartAt ~= nil then
		NetService.notify(player, RESTART_NOTICE, restartNoticeArgs(serverNow()), "warn")
	end
end

return ShutdownService
