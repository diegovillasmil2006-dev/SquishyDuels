--!strict
-- Signal (shared: server and client). A pure-Luau event; no BindableEvent, so arguments are passed by
-- reference (tables are not copied) and behaviour does not depend on Workspace.SignalBehavior.
--
-- Dispatch: fire() calls every handler through task.spawn, in connection order. Each handler starts
-- immediately (fire is synchronous up to each handler's first yield), runs in its own thread, and an
-- error or yield in one handler never stops the others or the caller.
-- Safety: fire() works on a snapshot. A handler disconnected during a fire (by itself or another handler)
-- is not called afterwards; a handler connected during a fire is first called on the next fire.
-- wait(): the wake-up is tied to that one wait. If the waiting thread is resumed by something else first, the
-- wake-up is dropped (it never resumes the thread at a later, unrelated yield). A waiter whose thread died before a
-- fire (e.g. task.cancel by a Cleanup) is dropped on the next connect, once or wait, so it does not pile up on a
-- signal that rarely fires. disconnectAll()/destroy() also drop pending waiters: their threads are never resumed
-- (and are released for garbage collection), so whoever destroys a signal that a thread waits on should also
-- cancel that thread.

-- Types

export type Connection = {
	connected: boolean,
	disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	fire: (self: Signal<T...>, T...) -> (),
	wait: (self: Signal<T...>) -> T...,
	disconnectAll: (self: Signal<T...>) -> (),
	destroy: (self: Signal<T...>) -> (),
}

type SignalData = {
	_connections: { ConnectionData },
}

type ConnectionData = {
	connected: boolean,
	_signal: SignalData,
	_handler: (...any) -> (),
	_once: boolean,
	_waiter: thread?, -- set for the connection behind a wait()
}

-- Module tables

local ConnectionClass = {}
ConnectionClass.__index = ConnectionClass

local SignalClass = {}
SignalClass.__index = SignalClass

local Signal = {}

-- Private

local function disconnectConnection(connection: ConnectionData)
	if not connection.connected then
		return
	end
	connection.connected = false
	local list = connection._signal._connections
	local index = table.find(list, connection)
	if index then
		table.remove(list, index)
	end
end

-- Removes wait() connections whose waiting thread has died (cancelled or errored) before any fire.
local function pruneDeadWaiters(signal: SignalData)
	local list = signal._connections
	for index = #list, 1, -1 do
		local waiter = list[index]._waiter
		if waiter ~= nil and coroutine.status(waiter) == "dead" then
			list[index].connected = false
			table.remove(list, index)
		end
	end
end

local function addConnection(signal: SignalData, handler: (...any) -> (), once: boolean, waiter: thread?): Connection
	assert(type(handler) == "function", "[SD][Signal] handler must be a function")
	pruneDeadWaiters(signal)
	local connection: ConnectionData = {
		connected = true,
		_signal = signal,
		_handler = handler,
		_once = once,
		_waiter = waiter,
	}
	table.insert(signal._connections, connection)
	return setmetatable(connection, ConnectionClass) :: any
end

-- Connection methods

function ConnectionClass.disconnect(self: ConnectionData)
	disconnectConnection(self)
end

-- Signal methods

function SignalClass.connect(self: SignalData, handler: (...any) -> ()): Connection
	return addConnection(self, handler, false)
end

-- Like connect, but disconnects itself before its first call.
function SignalClass.once(self: SignalData, handler: (...any) -> ()): Connection
	return addConnection(self, handler, true)
end

function SignalClass.fire(self: SignalData, ...: any)
	local list = self._connections
	if #list == 0 then
		return
	end
	for _, connection in table.clone(list) do
		if connection.connected then
			if connection._once then
				disconnectConnection(connection)
			end
			task.spawn(connection._handler, ...)
		end
	end
end

-- Yields the calling thread until the next fire and returns its arguments (see the header for cancelled waiters,
-- outside resumes and destroy()).
function SignalClass.wait(self: SignalData): ...any
	local thread = coroutine.running()
	local waiting = true
	local connection = addConnection(self, function(...: any)
		if waiting and coroutine.status(thread) == "suspended" then
			waiting = false
			task.spawn(thread, ...)
		end
	end, true, thread)
	local results = table.pack(coroutine.yield())
	-- Resumed by the fire or by anything else: either way this wait is over and its wake-up must not fire later.
	waiting = false
	connection:disconnect()
	return table.unpack(results, 1, results.n)
end

function SignalClass.disconnectAll(self: SignalData)
	for _, connection in self._connections do
		connection.connected = false
	end
	table.clear(self._connections)
end

-- Alias so a Signal can be handed to a Cleanup.
SignalClass.destroy = SignalClass.disconnectAll

-- Public

function Signal.new<T...>(): Signal<T...>
	local signal: SignalData = {
		_connections = {},
	}
	return setmetatable(signal, SignalClass) :: any
end

return Signal
