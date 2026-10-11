--!strict
-- KeyQueue (server only). Per-key serialized jobs with retries, backoff and DataStore error classes (DESIGN §3.6).
-- Logic layer: no services and no instances; time, waiting and randomness are injected, so tests run it with a fake
-- clock and no real waits.
--
-- * One FIFO and one runner thread per key: jobs on the same key run one at a time, in order; different keys run in
--   parallel. enqueue(key, job) returns a Ticket at once; run(key, job) enqueues and waits (yields) for the result.
-- * A job is { fn, onStart?, onFinish?, droppable?, name? }. When the job reaches the front of its key:
--   onStart() runs once (DataService takes its save snapshot there, §3.9), then fn() is attempted up to
--   `attempts` times (5 [P]); fn is the DataStore request and may throw. Between attempts the runner waits
--   min(cap, 2^(n-1)) * (1 + random() * jitter) seconds; a throttle code (301-306) doubles that delay.
--   onFinish(ok, value, class, message) runs once with the final outcome, then every waiter is resumed.
-- * Error classes (classify): "throttle" (301-306, retried, doubled delay), "fatal" (101-107, 403, 509, 511-513: not
--   retried), "studioAccess" (the "Studio access" error, seen as 502 ... Error code: 7 / StudioAccessToApisNotAllowed:
--   not retried), "shutdown" (401, 402: stops ALL work: the failing job, every pending job and every later enqueue
--   fail with class "shutdown"), "retry" (404, 501-505, anything else).
-- * dropPendingExceptLast() (BindToClose, §3.12): on every key, the jobs that have not started yet are collapsed into
--   the last one, which is safe because every DataService write is a full snapshot taken when the job starts. Only
--   droppable jobs are dropped, and only when the last pending job is droppable too; a dropped job never runs (no
--   onStart, no onFinish; Ticket:isDropped() is true) and its waiters receive the result of the job it was folded into.
-- Reading: an error message's code is its leading "<digits>:" (DataStore errors look like "304: ..."), also after one
--   "<chunk>:<line>:" location prefix; a message without a code is class "retry".

-- Types

export type ErrorClass = "throttle" | "fatal" | "studioAccess" | "shutdown" | "retry"

export type Job = {
	fn: () -> any,
	onStart: (() -> ())?,
	onFinish: ((ok: boolean, value: any, class: ErrorClass?, message: string?) -> ())?,
	droppable: boolean?,
	name: string?,
}

export type ErrorCodes = { throttle: { number }, notRetried: { number }, shutdown: { number } }

export type Deps = {
	wait: (seconds: number) -> (), -- yields (task.wait in production)
	random: (() -> number)?, -- [0, 1); default math.random
	spawn: ((fn: () -> ()) -> ())?, -- starts a runner thread; default task.spawn
	attempts: number?, -- default 5
	cap: number?, -- default 16 s
	jitter: number?, -- default 0.5
	codes: ErrorCodes?, -- default: the classes of DESIGN §3.6
	onRetry: ((name: string, attempt: number, class: ErrorClass, message: string, delay: number) -> ())?,
}

type TicketData = {
	job: Job,
	key: string,
	started: boolean,
	done: boolean,
	dropped: boolean,
	ok: boolean,
	value: any,
	class: ErrorClass?,
	message: string?,
	followers: { TicketData },
	waiters: { thread },
}

type QueueData = {
	_deps: Deps,
	_pending: { [string]: { TicketData } },
	_running: { [string]: boolean },
	_stopped: boolean,
}

-- Constants

local DEFAULT_ATTEMPTS = 5
local DEFAULT_CAP = 16
local DEFAULT_JITTER = 0.5
local THROTTLE_FACTOR = 2
local STUDIO_ACCESS_CODE = 502 -- "Studio access" is seen as 502 ... Error code: 7 (§3.1)
local DEFAULT_CODES: ErrorCodes = {
	throttle = { 301, 302, 303, 304, 305, 306 },
	notRetried = { 101, 102, 103, 104, 105, 106, 107, 403, 509, 511, 512, 513 },
	shutdown = { 401, 402 },
}

-- Module tables

local TicketClass = {}
TicketClass.__index = TicketClass

local QueueClass = {}
QueueClass.__index = QueueClass

export type Ticket = typeof(setmetatable({} :: TicketData, TicketClass))
export type KeyQueue = typeof(setmetatable({} :: QueueData, QueueClass))

local KeyQueue = {}

-- Private

local function errorCode(message: string): number?
	local code = string.match(message, "^%s*(%d+)%s*:")
	if code == nil then
		code = string.match(message, "^[^:\n]*:%d+:%s*(%d+)%s*:")
	end
	return if code then tonumber(code) else nil
end

local function isStudioAccess(message: string, code: number?): boolean
	local lower = string.lower(message)
	if string.find(lower, "studioaccess", 1, true) or string.find(lower, "studio access", 1, true) then
		return true
	end
	return code == STUDIO_ACCESS_CODE and string.find(lower, "error code: 7", 1, true) ~= nil
end

local function resolve(ticket: TicketData, ok: boolean, value: any, class: ErrorClass?, message: string?)
	if ticket.done then
		return
	end
	ticket.done = true
	ticket.ok = ok
	ticket.value = value
	ticket.class = class
	ticket.message = message
	local waiters = ticket.waiters
	ticket.waiters = {}
	for _, thread in waiters do
		if coroutine.status(thread) == "suspended" then
			task.spawn(thread)
		end
	end
	for _, follower in ticket.followers do
		resolve(follower, ok, value, class, message)
	end
end

local function newTicket(key: string, job: Job): Ticket
	local data: TicketData = {
		job = job,
		key = key,
		started = false,
		done = false,
		dropped = false,
		ok = false,
		value = nil,
		class = nil,
		message = nil,
		followers = {},
		waiters = {},
	}
	return setmetatable(data, TicketClass)
end

local function callHook(fn: (...any) -> (), ...: any): (boolean, string?)
	local ok, err = pcall(fn :: any, ...)
	if ok then
		return true, nil
	end
	return false, tostring(err)
end

-- Ticket methods

-- True once the job reached the front of its key (onStart ran or is running).
function TicketClass.isStarted(self: Ticket): boolean
	return self.started
end

function TicketClass.isDone(self: Ticket): boolean
	return self.done
end

-- True once dropPendingExceptLast folded this job into a later one: it never runs (and never gets onStart / onFinish).
function TicketClass.isDropped(self: Ticket): boolean
	return self.dropped
end

-- Waits (yields) until the job finished, then returns (ok, value, class, message). Returns at once when done.
function TicketClass.await(self: Ticket): (boolean, any, ErrorClass?, string?)
	while not self.done do
		local thread = coroutine.running()
		table.insert(self.waiters, thread)
		coroutine.yield()
		local index = table.find(self.waiters, thread)
		if index then
			table.remove(self.waiters, index)
		end
	end
	return self.ok, self.value, self.class, self.message
end

-- Queue methods

function QueueClass.classify(self: KeyQueue, message: string): (ErrorClass, number?)
	return KeyQueue.classify(message, self._deps.codes)
end

-- Delay before the attempt after failed attempt `attempt` (1-based).
function QueueClass.delayFor(self: KeyQueue, attempt: number, throttled: boolean): number
	local deps = self._deps
	local cap = deps.cap or DEFAULT_CAP
	local jitter = deps.jitter or DEFAULT_JITTER
	local roll = if deps.random then deps.random() else math.random()
	local delay = math.min(cap, 2 ^ (attempt - 1)) * (1 + roll * jitter)
	return if throttled then delay * THROTTLE_FACTOR else delay
end

local function failPending(self: KeyQueue)
	for key, list in self._pending do
		self._pending[key] = {}
		for _, ticket in list do
			ticket.started = true
			if ticket.job.onFinish then
				callHook(ticket.job.onFinish :: any, false, nil, "shutdown", "queue stopped")
			end
			resolve(ticket, false, nil, "shutdown", "queue stopped")
		end
	end
end

local function attemptAll(self: KeyQueue, job: Job): (boolean, any, ErrorClass?, string?)
	local attempts = math.max(1, self._deps.attempts or DEFAULT_ATTEMPTS)
	local lastClass: ErrorClass = "retry"
	local lastMessage = ""
	for attempt = 1, attempts do
		if self._stopped then
			return false, nil, "shutdown", "queue stopped"
		end
		local ok, value = pcall(job.fn)
		if ok then
			return true, value, nil, nil
		end
		lastMessage = tostring(value)
		lastClass = (self:classify(lastMessage))
		if lastClass == "shutdown" then
			self._stopped = true
			failPending(self)
			return false, nil, lastClass, lastMessage
		elseif lastClass == "fatal" or lastClass == "studioAccess" then
			return false, nil, lastClass, lastMessage
		elseif attempt < attempts then
			local delay = self:delayFor(attempt, lastClass == "throttle")
			local onRetry = self._deps.onRetry
			if onRetry then
				callHook(onRetry :: any, job.name or "job", attempt, lastClass, lastMessage, delay)
			end
			self._deps.wait(delay)
		end
	end
	return false, nil, lastClass, lastMessage
end

local function runKey(self: KeyQueue, key: string)
	while true do
		local list = self._pending[key]
		if list == nil or #list == 0 then
			self._pending[key] = nil
			self._running[key] = nil
			return
		end
		local ticket = table.remove(list, 1) :: TicketData
		ticket.started = true
		local job = ticket.job
		local ok: boolean, value: any, class: ErrorClass?, message: string? = false, nil, nil, nil
		if self._stopped then
			ok, value, class, message = false, nil, "shutdown", "queue stopped"
		else
			local startOk, startErr = true, nil
			if job.onStart then
				startOk, startErr = callHook(job.onStart :: any)
			end
			if startOk then
				ok, value, class, message = attemptAll(self, job)
			else
				ok, value, class, message = false, nil, "fatal", "onStart failed: " .. tostring(startErr)
			end
		end
		if job.onFinish then
			callHook(job.onFinish :: any, ok, value, class, message)
		end
		resolve(ticket, ok, value, class, message)
	end
end

-- Adds `job` behind the other jobs of `key` and returns its ticket (never yields; the runner may start at once).
function QueueClass.enqueue(self: KeyQueue, key: string, job: Job): Ticket
	assert(type(job) == "table" and type(job.fn) == "function", "[SD][KeyQueue] a job needs fn")
	local ticket = newTicket(key, job)
	if self._stopped then
		ticket.started = true
		if job.onFinish then
			callHook(job.onFinish :: any, false, nil, "shutdown", "queue stopped")
		end
		resolve(ticket :: any, false, nil, "shutdown", "queue stopped")
		return ticket
	end
	local list = self._pending[key]
	if list == nil then
		list = {}
		self._pending[key] = list
	end
	table.insert(list, ticket :: any)
	if not self._running[key] then
		self._running[key] = true
		local spawn = self._deps.spawn or task.spawn :: any
		spawn(function()
			runKey(self, key)
		end)
	end
	return ticket
end

-- Enqueues `job` and waits for it: returns (ok, value, class, message).
function QueueClass.run(self: KeyQueue, key: string, job: Job): (boolean, any, ErrorClass?, string?)
	return self:enqueue(key, job):await()
end

-- Collapses every key's not-yet-started droppable jobs into that key's last pending job (see the header). Returns
-- how many jobs were dropped.
function QueueClass.dropPendingExceptLast(self: KeyQueue): number
	local dropped = 0
	for key, list in self._pending do
		local count = #list
		if count < 2 then
			continue
		end
		local last = list[count]
		if not last.job.droppable then
			continue
		end
		local kept: { TicketData } = {}
		for index = 1, count - 1 do
			local ticket = list[index]
			if ticket.job.droppable then
				ticket.dropped = true
				table.insert(last.followers, ticket)
				dropped += 1
			else
				table.insert(kept, ticket)
			end
		end
		table.insert(kept, last)
		self._pending[key] = kept
	end
	return dropped
end

-- Jobs of `key` (or of every key) that have not started yet.
function QueueClass.pendingCount(self: KeyQueue, key: string?): number
	if key ~= nil then
		local list = self._pending[key]
		return if list then #list else 0
	end
	local total = 0
	for _, list in self._pending do
		total += #list
	end
	return total
end

-- True while a runner works on `key`.
function QueueClass.isBusy(self: KeyQueue, key: string): boolean
	return self._running[key] == true
end

-- True after a shutdown-class error (401/402): every job fails from then on.
function QueueClass.isStopped(self: KeyQueue): boolean
	return self._stopped
end

-- Public

-- The class of a DataStore error message, and its numeric code when it has one. `codes` defaults to §3.6.
function KeyQueue.classify(message: string, codes: ErrorCodes?): (ErrorClass, number?)
	local text = tostring(message)
	local code = errorCode(text)
	if isStudioAccess(text, code) then
		return "studioAccess", code
	end
	if code == nil then
		return "retry", nil
	end
	local classes = codes or DEFAULT_CODES
	if table.find(classes.shutdown, code) then
		return "shutdown", code
	elseif table.find(classes.throttle, code) then
		return "throttle", code
	elseif table.find(classes.notRetried, code) then
		return "fatal", code
	end
	return "retry", code
end

function KeyQueue.new(deps: Deps): KeyQueue
	assert(type(deps) == "table" and type(deps.wait) == "function", "[SD][KeyQueue] deps.wait is required")
	local data: QueueData = {
		_deps = deps,
		_pending = {},
		_running = {},
		_stopped = false,
	}
	return setmetatable(data, QueueClass)
end

return KeyQueue
