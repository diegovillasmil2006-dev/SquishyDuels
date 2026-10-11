--!strict
-- Cleanup (shared: server and client). Trove pattern: everything a feature opens goes in, clean() closes
-- it all. Accepted items: RBXScriptConnection (Disconnect), Instance (Destroy), function (called),
-- thread (task.cancel), or a table with a Destroy, destroy, Disconnect or disconnect method (in that
-- order; this covers Signals, Signal connections, UI components and other Cleanups).
-- Unsupported items are rejected by add(), not at clean() time.
-- clean() runs items newest first (LIFO), is idempotent, and is safe to call again from inside an item.
-- Items added while cleaning are cleaned in the same pass. A failing item is logged and the rest still run.
-- A cleaned Cleanup can be reused: adding to it opens it again.
-- Threads: only suspended threads are cancelled; the thread running clean() itself is skipped.
-- Leak tests: in Studio, Cleanup.liveCount() is the number of open Cleanups (created or reused and not
-- yet cleaned), while Config.Debug.cleanupLiveCount is on. Outside Studio that flag is off and it is always 0.

-- Requires

local Config = require(script.Parent.Parent.Config)
local Log = require(script.Parent.Log)

-- Types

type CleanupData = {
	_items: { any },
	_open: boolean,
	_cleaning: boolean,
}

-- Constants

local COUNT_LIVE = Config.Debug.cleanupLiveCount -- false outside Studio
local TABLE_METHODS = { "Destroy", "destroy", "Disconnect", "disconnect" }

-- Module table

local Cleanup = {}
Cleanup.__index = Cleanup

export type Cleanup = typeof(setmetatable({} :: CleanupData, Cleanup))

-- Private

local log = Log.new("Cleanup")
local liveCount = 0

local function markOpen(self: Cleanup)
	if not self._open then
		self._open = true
		if COUNT_LIVE then
			liveCount += 1
		end
	end
end

local function markClosed(self: Cleanup)
	if self._open then
		self._open = false
		if COUNT_LIVE then
			liveCount -= 1
		end
	end
end

local function tableMethod(item: { [any]: any }): string?
	for _, name in TABLE_METHODS do
		if type(item[name]) == "function" then
			return name
		end
	end
	return nil
end

local function isSupported(item: any): boolean
	local kind = typeof(item)
	if kind == "function" or kind == "thread" or kind == "RBXScriptConnection" or kind == "Instance" then
		return true
	end
	return kind == "table" and tableMethod(item) ~= nil
end

local function cleanItem(item: any)
	local kind = typeof(item)
	if kind == "function" then
		item()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "thread" then
		if coroutine.status(item) == "suspended" then
			task.cancel(item)
		end
	elseif kind == "table" then
		local name = tableMethod(item)
		if name then
			item[name](item)
		end
	end
end

local function reportFailure(err: any)
	log:error("an item failed to clean up:", debug.traceback(tostring(err), 2))
end

-- Public

function Cleanup.new(): Cleanup
	local self: CleanupData = {
		_items = {},
		_open = false,
		_cleaning = false,
	}
	local cleanup = setmetatable(self, Cleanup)
	markOpen(cleanup)
	return cleanup
end

-- Adds an item and returns it, so `local part = cleanup:add(Instance.new("Part"))` works.
function Cleanup.add<T>(self: Cleanup, item: T): T
	if not isSupported(item) then
		error(`[SD][Cleanup] cannot clean a value of type {typeof(item)}`, 2)
	end
	markOpen(self)
	table.insert(self._items, item)
	return item
end

function Cleanup.clean(self: Cleanup)
	if self._cleaning then
		return
	end
	self._cleaning = true
	local items = self._items
	while #items > 0 do
		xpcall(cleanItem, reportFailure, table.remove(items))
	end
	self._cleaning = false
	markClosed(self)
end

-- Alias so a Cleanup can be added to another Cleanup (or used where :destroy() is expected).
function Cleanup.destroy(self: Cleanup)
	self:clean()
end

-- Studio only (Config.Debug.cleanupLiveCount): open Cleanups on this side (server or this client). 0 outside Studio.
function Cleanup.liveCount(): number
	return liveCount
end

return Cleanup
