--!strict
-- DataStoreAdapter (server only). The one place that opens a real DataStore (DESIGN §3.1, §3.6, §12 #19).
-- Wraps a GlobalDataStore in the small Store interface DataService uses (InMemoryAdapter and the tests' FakeDataStore
-- implement the same interface):
--   store.updateAsync(key, transform) -> (newValue, keyInfo)   UpdateAsync only: never GetAsync / SetAsync (§3.6)
--   store.budget("read" | "write")    -> number                StandardRead / StandardWrite request budget
--   store.name, store.persisted (true), store.kind ("datastore")
-- The transform gets (value, info) where info = { metadata = {...}, userIds = {...} } (a plain-table copy of the
-- DataStoreKeyInfo), or nil for a key that was never written. It returns (newValue, userIds, metadata), or nil to
-- cancel the write. Transforms are pure (no yields, grants or remotes) and always return {userId} and the metadata
-- table, because omitting them clears them (§3.6).
-- Guard (§3.1): in Studio, open() refuses any store whose name does not end in "_STUDIO", so Studio can never touch
-- real players' data. DataService also checks the name at boot (assertSafeName).

-- Services

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- Types

export type KeyInfo = { metadata: { [string]: any }, userIds: { number } }
export type Transform = (value: any, info: KeyInfo?) -> (any, { number }?, { [string]: any }?)
export type BudgetKind = "read" | "write"

-- The interface every adapter implements (dot-call functions; no `self`).
export type Store = {
	name: string,
	kind: string, -- "datastore" | "memory" | "fake"
	persisted: boolean, -- false = memory only (the Studio banner, §3.1)
	updateAsync: (key: string, transform: Transform) -> (any, KeyInfo?),
	budget: (kind: BudgetKind) -> number,
}

export type OpenOptions = {
	isStudio: boolean?, -- default RunService:IsStudio()
	service: DataStoreService?, -- default game:GetService("DataStoreService")
}

-- Constants

local STUDIO_SUFFIX = "_STUDIO"

-- Module table

local DataStoreAdapter = {}

-- Public

-- True when `name` may be opened from this context: anything live, only "*_STUDIO" in Studio.
function DataStoreAdapter.isSafeName(name: string, isStudio: boolean): boolean
	if type(name) ~= "string" or name == "" then
		return false
	end
	return not isStudio or string.sub(name, -#STUDIO_SUFFIX) == STUDIO_SUFFIX
end

-- Errors (the §3.1 boot assert) when `name` is not safe for this context.
function DataStoreAdapter.assertSafeName(name: string, isStudio: boolean)
	assert(
		DataStoreAdapter.isSafeName(name, isStudio),
		`[SD][Data] Studio may only open stores whose name ends in {STUDIO_SUFFIX} (got {tostring(name)})`
	)
end

-- Copies a DataStoreKeyInfo into the plain KeyInfo table (nil stays nil).
function DataStoreAdapter.readKeyInfo(keyInfo: DataStoreKeyInfo?): KeyInfo?
	if keyInfo == nil then
		return nil
	end
	local metadata = keyInfo:GetMetadata()
	local userIds = keyInfo:GetUserIds()
	return {
		metadata = if type(metadata) == "table" then table.clone(metadata) :: any else {},
		userIds = if type(userIds) == "table" then table.clone(userIds) else {},
	}
end

-- Opens the real DataStore `name` (no scope). Errors in Studio for a name without "_STUDIO", and when
-- GetDataStore itself fails (for example without API access); DataService calls this inside pcall.
function DataStoreAdapter.open(name: string, options: OpenOptions?): Store
	local opts: OpenOptions = options or {}
	local isStudio = if opts.isStudio ~= nil then opts.isStudio else RunService:IsStudio()
	DataStoreAdapter.assertSafeName(name, isStudio)
	local service: DataStoreService = opts.service or DataStoreService
	local dataStore = service:GetDataStore(name)

	local store: Store = {
		name = name,
		kind = "datastore",
		persisted = true,
		updateAsync = function(key: string, transform: Transform): (any, KeyInfo?)
			local newValue, keyInfo = dataStore:UpdateAsync(key, function(value: any, keyInfo: DataStoreKeyInfo)
				return transform(value, DataStoreAdapter.readKeyInfo(keyInfo))
			end)
			return newValue, DataStoreAdapter.readKeyInfo(keyInfo)
		end,
		budget = function(kind: BudgetKind): number
			local requestType = if kind == "write"
				then Enum.DataStoreRequestType.StandardWrite
				else Enum.DataStoreRequestType.StandardRead
			return service:GetRequestBudgetForRequestType(requestType)
		end,
	}
	return store
end

return DataStoreAdapter
