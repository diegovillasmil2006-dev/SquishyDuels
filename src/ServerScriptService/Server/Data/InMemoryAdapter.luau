--!strict
-- InMemoryAdapter (server only). A server-memory Store with the DataStoreAdapter interface (DESIGN §3.1): used in
-- Studio with Config.Data.studioMode = "memory" (the default; banner "Studio test: progress is not saved."), for any
-- userId <= 0 (multi-client test players), and as the fallback when Studio has no API access. Sessions behave exactly
-- like real ones (status "ready"); only `persisted = false` differs. Data lives as long as this server.
-- Values, user ids and metadata are deep-copied in and out (like a real store's serialization), so a caller can never
-- change stored data by keeping a reference. A transform returning nil cancels the write, as UpdateAsync does.
-- Never yields; the budget is unlimited.
-- Studio tests (DESIGN §13.2 Part 7 "forced save failure (memory adapter)"): failNext(key, count, message?) makes the
-- next `count` updateAsync calls on `key` throw `message` (default a non-retried "105: ..." DataStore code) before the
-- transform runs, so nothing is read or written; count 0 clears it. DataService.debugFailSaves is its only caller.

-- Requires

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TableUtil = require(ReplicatedStorage.Shared.Util.TableUtil)
local DataStoreAdapter = require(script.Parent.DataStoreAdapter)

-- Types

type Store = DataStoreAdapter.Store
type KeyInfo = DataStoreAdapter.KeyInfo
type Transform = DataStoreAdapter.Transform

type Entry = { value: any, userIds: { number }, metadata: { [string]: any } }

export type MemoryStore = Store & {
	peek: (key: string) -> (any, KeyInfo?), -- deep copies of what is stored (Studio debug, tests)
	clear: () -> (),
	-- The next `count` updateAsync calls on `key` throw `message` (Studio forced save failures); count 0 clears.
	failNext: (key: string, count: number, message: string?) -> (),
}

type Failure = { count: number, message: string }

-- Constants

-- 105 is a DataStore code that is never retried (KeyQueue, DESIGN §3.6), so a forced failure fails at once.
local DEFAULT_FAIL_MESSAGE = "105: InMemoryAdapter forced failure"

-- Module table

local InMemoryAdapter = {}

-- Public

function InMemoryAdapter.new(name: string?): MemoryStore
	local entries: { [string]: Entry } = {}
	local failures: { [string]: Failure } = {}

	local function infoOf(entry: Entry?): KeyInfo?
		if entry == nil then
			return nil
		end
		return { metadata = TableUtil.deepCopy(entry.metadata), userIds = table.clone(entry.userIds) }
	end

	local store = {
		name = name or "memory",
		kind = "memory",
		persisted = false,
		updateAsync = function(key: string, transform: Transform): (any, KeyInfo?)
			local failure = failures[key]
			if failure ~= nil then
				failure.count -= 1
				if failure.count <= 0 then
					failures[key] = nil
				end
				error(failure.message, 0)
			end
			local entry = entries[key]
			local current = if entry then TableUtil.deepCopy(entry.value) else nil
			local newValue, userIds, metadata = transform(current, infoOf(entry))
			if newValue == nil then
				return nil, infoOf(entry)
			end
			local stored: Entry = {
				value = TableUtil.deepCopy(newValue),
				userIds = if type(userIds) == "table" then table.clone(userIds) else {},
				metadata = if type(metadata) == "table" then TableUtil.deepCopy(metadata) else {},
			}
			entries[key] = stored
			return TableUtil.deepCopy(stored.value), infoOf(stored)
		end,
		budget = function(_kind: DataStoreAdapter.BudgetKind): number
			return math.huge
		end,
		peek = function(key: string): (any, KeyInfo?)
			local entry = entries[key]
			return if entry then TableUtil.deepCopy(entry.value) else nil, infoOf(entry)
		end,
		clear = function()
			table.clear(entries)
			table.clear(failures)
		end,
		failNext = function(key: string, count: number, message: string?)
			local n = if type(count) == "number" and count == count then math.floor(count) else 0
			if n <= 0 then
				failures[key] = nil
				return
			end
			failures[key] = { count = n, message = if type(message) == "string" then message else DEFAULT_FAIL_MESSAGE }
		end,
	}
	return store :: MemoryStore
end

return InMemoryAdapter
