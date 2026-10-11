--!strict
-- Scheduler (client only). The animation runtime's only per-frame connections (DESIGN §9.1 #3): RunService.PreSimulation
-- drives the "joint" phase (joint layers) and RunService.PreRender drives the "render" phase (deformation, held-model
-- motion, VFX, UI number tweens). Effects never connect frame events themselves (camera shake is the one documented
-- exception, §9.12).
--
-- Effect contract: an object with `step(self, dt, now) -> alive` (or a plain function `(dt, now) -> alive`).
--   * dt is clamped to [0, Config.Anim.Scheduler.maxDt] (1/20 s); now = os.clock() for that frame (networked effects
--     read workspace:GetServerTimeNow() themselves, §9.1 #4).
--   * Returning anything other than `true` removes the effect. An effect that errors is removed and logged; the
--     others still run.
--   * Effects run in the order they were added. One added during a step first runs on the next frame of its phase.
--   * add() returns a handle with disconnect()/destroy(), so it can go straight into a Cleanup.
--
-- The default scheduler (Scheduler.add/count/reset) connects lazily on the first add of each phase, so requiring
-- this module has no side effects and there are never more than two connections. Scheduler.new(false) makes a
-- private, unconnected scheduler driven by :tick() (unit tests, previews).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)

-- Types

export type Phase = "joint" | "render"

export type Effect = {
	step: (self: any, dt: number, now: number) -> boolean,
}

export type Handle = {
	connected: boolean,
	disconnect: (self: Handle) -> (),
	destroy: (self: Handle) -> (),
}

type Entry = {
	effect: any,
	removed: boolean,
}

type PhaseState = {
	entries: { Entry },
	pending: { Entry },
	stepping: boolean,
	connection: RBXScriptConnection?,
}

export type Scheduler = {
	add: (self: Scheduler, effect: Effect | (dt: number, now: number) -> boolean, phase: Phase?) -> Handle,
	tick: (self: Scheduler, phase: Phase, dt: number, now: number?) -> (),
	count: (self: Scheduler, phase: Phase?) -> number,
	connectionCount: (self: Scheduler) -> number,
	reset: (self: Scheduler) -> (),
}

-- Constants

local MAX_DT = Config.Anim.Scheduler.maxDt
local PHASES: { Phase } = { "joint", "render" }

-- Module tables

local SchedulerClass = {}
SchedulerClass.__index = SchedulerClass

local HandleClass = {}
HandleClass.__index = HandleClass

local Scheduler = {}

-- Private

local log = Log.new("Scheduler")
local defaultScheduler: Scheduler? = nil

local function newPhase(): PhaseState
	return { entries = {}, pending = {}, stepping = false, connection = nil }
end

local function signalFor(phase: Phase): RBXScriptSignal<number>
	return if phase == "joint" then RunService.PreSimulation else RunService.PreRender
end

local function clampDt(dt: number): number
	if not (dt > 0) then -- also NaN
		return 0
	end
	return math.min(dt, MAX_DT)
end

local function runPhase(state: PhaseState, dt: number, now: number)
	state.stepping = true
	local entries = state.entries
	local kept = 0
	for index = 1, #entries do
		local entry = entries[index]
		if entry == nil then
			break -- reset() ran inside a step
		end
		if not entry.removed then
			local effect = entry.effect
			local ok, alive = pcall(effect.step, effect, dt, now)
			if not ok then
				log:error("an effect failed and was removed:", alive)
				entry.removed = true
			elseif alive ~= true then
				entry.removed = true
			end
		end
		if not entry.removed then
			kept += 1
			entries[kept] = entry
		end
	end
	for index = #entries, kept + 1, -1 do
		entries[index] = nil
	end
	state.stepping = false
	if #state.pending > 0 then
		for _, entry in state.pending do
			if not entry.removed then
				table.insert(entries, entry)
			end
		end
		table.clear(state.pending)
	end
end

local function removeEntry(state: PhaseState, entry: Entry)
	entry.removed = true
	if state.stepping then
		return -- compacted at the end of the running step
	end
	local index = table.find(state.entries, entry)
	if index then
		table.remove(state.entries, index)
		return
	end
	index = table.find(state.pending, entry)
	if index then
		table.remove(state.pending, index)
	end
end

-- Handle methods

function HandleClass.disconnect(self: any)
	if not self.connected then
		return
	end
	self.connected = false
	removeEntry(self._state, self._entry)
end

HandleClass.destroy = HandleClass.disconnect

-- Scheduler methods

function SchedulerClass.add(self: any, effect: any, phase: Phase?): Handle
	local which: Phase = phase or "render"
	local state: PhaseState? = self._phases[which]
	assert(state, `[SD][Scheduler] unknown phase {tostring(phase)}`)
	local target = effect
	if type(effect) == "function" then
		target = {
			step = function(_: any, dt: number, now: number): boolean
				return effect(dt, now)
			end,
		}
	end
	assert(
		type(target) == "table" and type(target.step) == "function",
		"[SD][Scheduler] an effect needs a step(self, dt, now) method"
	)
	local entry: Entry = { effect = target, removed = false }
	if state.stepping then
		table.insert(state.pending, entry)
	else
		table.insert(state.entries, entry)
	end
	if self._autoConnect and state.connection == nil then
		state.connection = signalFor(which):Connect(function(dt: number)
			runPhase(state, clampDt(dt), os.clock())
		end)
	end
	local handle = { connected = true, _state = state, _entry = entry }
	return setmetatable(handle, HandleClass) :: any
end

-- Runs one frame of `phase` by hand (dt clamped as for the connections; now defaults to os.clock()).
function SchedulerClass.tick(self: any, phase: Phase, dt: number, now: number?)
	local state: PhaseState? = self._phases[phase]
	assert(state, `[SD][Scheduler] unknown phase {tostring(phase)}`)
	assert(not state.stepping, "[SD][Scheduler] tick() called from inside a step")
	runPhase(state, clampDt(dt), if now == nil then os.clock() else now)
end

-- Live effects in one phase, or in both when phase is nil.
function SchedulerClass.count(self: any, phase: Phase?): number
	local total = 0
	for _, name in PHASES do
		if phase == nil or phase == name then
			local state: PhaseState = self._phases[name]
			for _, list in { state.entries, state.pending } do
				for _, entry in list do
					if not entry.removed then
						total += 1
					end
				end
			end
		end
	end
	return total
end

-- Number of frame connections this scheduler holds (0-2).
function SchedulerClass.connectionCount(self: any): number
	local total = 0
	for _, name in PHASES do
		if self._phases[name].connection ~= nil then
			total += 1
		end
	end
	return total
end

-- Disconnects both phases and drops every effect (their handles become no-ops).
function SchedulerClass.reset(self: any)
	for _, name in PHASES do
		local state: PhaseState = self._phases[name]
		if state.connection then
			state.connection:Disconnect()
			state.connection = nil
		end
		for _, list in { state.entries, state.pending } do
			for _, entry in list do
				entry.removed = true
			end
			table.clear(list)
		end
	end
end

-- Public

-- A new scheduler. autoConnect = true connects PreSimulation/PreRender lazily on the first add of each phase;
-- false never connects (drive it with :tick()).
function Scheduler.new(autoConnect: boolean): Scheduler
	local self = {
		_autoConnect = autoConnect,
		_phases = { joint = newPhase(), render = newPhase() },
	}
	return setmetatable(self, SchedulerClass) :: any
end

-- The client's shared scheduler (created on first use, auto-connecting).
function Scheduler.default(): Scheduler
	if defaultScheduler == nil then
		defaultScheduler = Scheduler.new(true)
	end
	return defaultScheduler :: Scheduler
end

-- Shortcuts to the default scheduler.
function Scheduler.add(effect: Effect | (dt: number, now: number) -> boolean, phase: Phase?): Handle
	return Scheduler.default():add(effect, phase)
end

function Scheduler.count(phase: Phase?): number
	return Scheduler.default():count(phase)
end

function Scheduler.reset()
	if defaultScheduler then
		defaultScheduler:reset()
	end
end

return Scheduler
