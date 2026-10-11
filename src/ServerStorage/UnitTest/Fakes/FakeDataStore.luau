--!strict
-- FakeDataStore: an in-memory DataStore for unit tests (DESIGN §2.5, §13.2 Part 5). Server only
-- (ServerStorage.UnitTest; never required at runtime). It implements the Store interface of
-- src/server/Data/DataStoreAdapter (updateAsync(key, transform), budget(kind), name, kind, persisted) with real
-- UpdateAsync semantics, and injects every failure DataService_Test needs:
--   * failNext(n, code, message?)   the next n calls throw "<code>: <message>" before the transform runs
--                                   (throttle 304, non-retryable 105, shutdown 401, retried 503, ...)
--   * failAlways(code, message?)    every call throws until recover()
--   * ghostNext(n, code?, message?) the next n calls COMMIT the write and then throw ("write succeeded but reported
--                                   failure"; default code 503)
--   * repeatTransformNext(n, between?) the transform runs twice in the next n calls (a concurrent write made
--                                   UpdateAsync call it again); only the second result counts; between(key), when
--                                   given, runs between the two runs (that concurrent write, e.g. setMetadata)
--   * pause() / resume()            calls block (a real yield) until resume(), to test work queued behind a request
--   * onCall(hook)                  hook(callNumber, key) runs at the start of every call (e.g. another server
--                                   writes the key between two requests)
--   * setBudget(n)                  what budget("read" / "write") returns (default math.huge)
-- Semantics: the transform gets deep copies (value, {metadata, userIds}) or (nil, nil) for a key never written; it
-- must not yield (the fake errors if it does, like Roblox); returning nil cancels the write; a write stores deep
-- copies of (value, userIds or {}, metadata or {}): omitting userIds or metadata clears them, as on Roblox.
-- Inspection: calls, writes, writesFor(key), getRaw(key) -> (value, metadata, userIds), history (one entry per call:
-- {key, outcome = "write" | "cancel" | "fail" | "ghost"}), lastUserIds, lastMetadata. GetAsync / SetAsync /
-- RemoveAsync / IncrementAsync exist only to fail loudly and count `forbiddenCalls` (UpdateAsync only, §3.6).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)

export type KeyInfo = { metadata: { [string]: any }, userIds: { number } }
export type Transform = (value: any, info: KeyInfo?) -> (any, { number }?, { [string]: any }?)
export type CallRecord = { key: string, outcome: string }

export type FakeDataStore = {
	name: string,
	kind: string,
	persisted: boolean,
	updateAsync: (key: string, transform: Transform) -> (any, KeyInfo?),
	budget: (kind: string) -> number,
	-- failure injection
	failNext: (count: number, code: number, message: string?) -> (),
	failAlways: (code: number, message: string?) -> (),
	ghostNext: (count: number, code: number?, message: string?) -> (),
	repeatTransformNext: (count: number, between: ((key: string) -> ())?) -> (),
	recover: () -> (),
	pause: () -> (),
	resume: () -> (),
	isPaused: () -> boolean,
	blockedCount: () -> number,
	onCall: (hook: ((callNumber: number, key: string) -> ())?) -> (),
	setBudget: (n: number) -> (),
	-- data
	setRaw: (key: string, value: any, metadata: { [string]: any }?, userIds: { number }?) -> (),
	getRaw: (key: string) -> (any, { [string]: any }?, { number }?),
	setMetadata: (key: string, metadata: { [string]: any }) -> (),
	-- inspection
	calls: number,
	writes: number,
	forbiddenCalls: number,
	writesFor: (key: string) -> number,
	history: { CallRecord },
	lastUserIds: { number }?,
	lastMetadata: { [string]: any }?,
	-- forbidden APIs
	GetAsync: (key: any) -> never,
	SetAsync: (key: any) -> never,
	RemoveAsync: (key: any) -> never,
	IncrementAsync: (key: any) -> never,
}

type Entry = { value: any, metadata: { [string]: any }, userIds: { number } }
type Failure = { code: number, message: string }

local DEFAULT_GHOST_CODE = 503

local FakeDataStore = {}

function FakeDataStore.new(name: string?): FakeDataStore
	local entries: { [string]: Entry } = {}
	local writesByKey: { [string]: number } = {}
	local failQueue: { Failure } = {}
	local ghostQueue: { Failure } = {}
	local alwaysFail: Failure? = nil
	local repeatLeft = 0
	local repeatBetween: ((key: string) -> ())? = nil
	local paused = false
	local blocked: { thread } = {}
	local callHook: ((number, string) -> ())? = nil
	local budget = math.huge

	local fake = {} :: FakeDataStore
	fake.name = name or "FakeStore"
	fake.kind = "fake"
	fake.persisted = true
	fake.calls = 0
	fake.writes = 0
	fake.forbiddenCalls = 0
	fake.history = {}
	fake.lastUserIds = nil
	fake.lastMetadata = nil

	local function record(key: string, outcome: string)
		table.insert(fake.history, { key = key, outcome = outcome })
	end

	local function infoOf(entry: Entry?): KeyInfo?
		if entry == nil then
			return nil
		end
		return { metadata = TableUtil.deepCopy(entry.metadata), userIds = table.clone(entry.userIds) }
	end

	-- Runs the transform like Roblox: it must finish without yielding.
	local function runTransform(transform: Transform, entry: Entry?): (any, { number }?, { [string]: any }?)
		local value = if entry then TableUtil.deepCopy(entry.value) else nil
		local co = coroutine.create(transform)
		local results: any = table.pack(coroutine.resume(co, value, infoOf(entry)))
		if not results[1] then
			error(results[2], 0)
		end
		if coroutine.status(co) ~= "dead" then
			error("FakeDataStore: the transform yielded (transforms must be pure, DESIGN §3.6)", 0)
		end
		return results[2], results[3], results[4]
	end

	local function forbidden(apiName: string): never
		fake.forbiddenCalls += 1
		error(`FakeDataStore: {apiName} is forbidden (UpdateAsync only, DESIGN §3.6)`, 2)
	end

	function fake.updateAsync(key: string, transform: Transform): (any, KeyInfo?)
		assert(type(key) == "string", "FakeDataStore: key must be a string")
		assert(type(transform) == "function", "FakeDataStore: transform must be a function")
		while paused do
			table.insert(blocked, coroutine.running())
			coroutine.yield()
		end
		fake.calls += 1
		local hook = callHook
		if hook then
			hook(fake.calls, key)
		end
		local failure: Failure? = alwaysFail
		if failure == nil and #failQueue > 0 then
			failure = table.remove(failQueue, 1)
		end
		if failure then
			record(key, "fail")
			error(`{failure.code}: {failure.message}`, 0)
		end

		local newValue, userIds, metadata = runTransform(transform, entries[key])
		if repeatLeft > 0 then
			repeatLeft -= 1
			local between = repeatBetween
			if repeatLeft == 0 then
				repeatBetween = nil
			end
			if between then
				between(key)
			end
			newValue, userIds, metadata = runTransform(transform, entries[key])
		end
		if newValue == nil then
			record(key, "cancel")
			return nil, infoOf(entries[key])
		end
		local stored: Entry = {
			value = TableUtil.deepCopy(newValue),
			metadata = if type(metadata) == "table" then TableUtil.deepCopy(metadata) else {},
			userIds = if type(userIds) == "table" then table.clone(userIds) else {},
		}
		entries[key] = stored
		fake.writes += 1
		writesByKey[key] = (writesByKey[key] or 0) + 1
		fake.lastUserIds = table.clone(stored.userIds)
		fake.lastMetadata = TableUtil.deepCopy(stored.metadata)

		if #ghostQueue > 0 then
			local ghost = table.remove(ghostQueue, 1) :: Failure
			record(key, "ghost")
			error(`{ghost.code}: {ghost.message}`, 0)
		end
		record(key, "write")
		return TableUtil.deepCopy(stored.value), infoOf(stored)
	end

	function fake.budget(_kind: string): number
		return budget
	end

	function fake.failNext(count: number, code: number, message: string?)
		for _ = 1, count do
			table.insert(failQueue, { code = code, message = message or "injected failure" })
		end
	end

	function fake.failAlways(code: number, message: string?)
		alwaysFail = { code = code, message = message or "injected failure" }
	end

	function fake.ghostNext(count: number, code: number?, message: string?)
		for _ = 1, count do
			table.insert(ghostQueue, {
				code = code or DEFAULT_GHOST_CODE,
				message = message or "write succeeded but reported failure",
			})
		end
	end

	function fake.repeatTransformNext(count: number, between: ((key: string) -> ())?)
		repeatLeft += count
		repeatBetween = between
	end

	function fake.recover()
		alwaysFail = nil
		table.clear(failQueue)
		table.clear(ghostQueue)
	end

	function fake.pause()
		paused = true
	end

	function fake.resume()
		paused = false
		local threads = blocked
		blocked = {}
		for _, thread in threads do
			if coroutine.status(thread) == "suspended" then
				task.spawn(thread)
			end
		end
	end

	function fake.isPaused(): boolean
		return paused
	end

	-- How many calls are waiting in pause().
	function fake.blockedCount(): number
		return #blocked
	end

	function fake.onCall(hook: ((number, string) -> ())?)
		callHook = hook
	end

	function fake.setBudget(n: number)
		budget = n
	end

	function fake.setRaw(key: string, value: any, metadata: { [string]: any }?, userIds: { number }?)
		entries[key] = {
			value = TableUtil.deepCopy(value),
			metadata = if metadata then TableUtil.deepCopy(metadata) else {},
			userIds = if userIds then table.clone(userIds) else {},
		}
	end

	function fake.getRaw(key: string): (any, { [string]: any }?, { number }?)
		local entry = entries[key]
		if entry == nil then
			return nil, nil, nil
		end
		return TableUtil.deepCopy(entry.value), TableUtil.deepCopy(entry.metadata), table.clone(entry.userIds)
	end

	-- Replaces only the metadata of a stored key (another server took the lock over, for example).
	function fake.setMetadata(key: string, metadata: { [string]: any })
		local entry = entries[key]
		assert(entry ~= nil, "FakeDataStore.setMetadata: no such key " .. key)
		entry.metadata = TableUtil.deepCopy(metadata)
	end

	function fake.writesFor(key: string): number
		return writesByKey[key] or 0
	end

	fake.GetAsync = function(_key: any): never
		return forbidden("GetAsync")
	end
	fake.SetAsync = function(_key: any): never
		return forbidden("SetAsync")
	end
	fake.RemoveAsync = function(_key: any): never
		return forbidden("RemoveAsync")
	end
	fake.IncrementAsync = function(_key: any): never
		return forbidden("IncrementAsync")
	end

	return fake
end

return FakeDataStore
