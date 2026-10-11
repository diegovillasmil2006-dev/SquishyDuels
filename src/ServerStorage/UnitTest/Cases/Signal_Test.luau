--!strict
-- Signal_Test: unit tests for ReplicatedStorage.Shared.Util.Signal. Server only (ServerStorage.UnitTest).
-- Contract (module header, DESIGN §2.2): connect/once/fire/wait/disconnectAll/destroy. wait() returns the next
-- fire's arguments (nil holes kept); its wake-up belongs to that one wait: a thread resumed by something else is
-- never resumed later by the signal, and a waiter whose thread was cancelled does not stay connected after the
-- next connect/once/wait. disconnectAll()/destroy() drop pending waiters without resuming them.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

-- Connections held by a signal. Memory held by dead waiters is not observable through the public API, so the
-- leak cases read the private list.
local function connectionCount(signal: any): number
	return #signal._connections
end

return function(t: Context)
	local Signal = t.requireShared("Util/Signal")
	local expect = t.expect

	-- wait ----------------------------------------------------------------------------------------------------

	-- The waiter gets exactly the fired arguments, including a nil in the middle.
	t.test("wait returns the next fire's arguments, nil holes included", function()
		local signal = Signal.new()
		local got: any = nil
		task.spawn(function()
			got = table.pack(signal:wait())
		end)
		signal:fire(1, nil, 3)
		expect.truthy(got ~= nil)
		expect.equal(got.n, 3)
		expect.equal(got[1], 1)
		expect.equal(got[2], nil)
		expect.equal(got[3], 3)
	end)

	-- After the wait is over, its connection is gone: a second fire reaches nobody.
	t.test("a finished wait leaves no connection behind", function()
		local signal = Signal.new()
		task.spawn(function()
			signal:wait()
		end)
		signal:fire()
		expect.equal(connectionCount(signal), 0)
	end)

	-- A thread resumed by something else (e.g. a timeout) must not be woken later, at an unrelated yield.
	t.test("a waiter resumed from outside is never resumed by a later fire", function()
		local signal = Signal.new()
		local log: { string } = {}
		local thread = task.spawn(function()
			table.insert(log, tostring(signal:wait()))
			table.insert(log, tostring(coroutine.yield())) -- an unrelated yield
		end)
		task.spawn(thread, "outside")
		signal:fire("signal")
		expect.deepEqual(log, { "outside" })
		task.cancel(thread)
	end)

	-- Cancelled waiters (Cleanup cancels suspended threads) do not pile up on a signal that never fires.
	t.test("cancelled waiters are dropped on the next connect", function()
		local signal = Signal.new()
		for _ = 1, 100 do
			task.cancel(task.spawn(function()
				signal:wait()
			end))
		end
		local connection = signal:connect(function() end)
		expect.equal(connectionCount(signal), 1)
		connection:disconnect()
		expect.equal(connectionCount(signal), 0)
	end)

	-- A fire after the waiter was cancelled just drops the wake-up and still calls the other handlers.
	t.test("a fire after a waiter was cancelled still reaches the other handlers", function()
		local signal = Signal.new()
		task.cancel(task.spawn(function()
			signal:wait()
		end))
		local calls = 0
		signal:connect(function()
			calls += 1
		end)
		signal:fire()
		expect.equal(calls, 1)
	end)

	-- destroy -----------------------------------------------------------------------------------------------

	-- destroy() drops pending waiters without resuming them (the owner cancels its own waiting threads).
	t.test("destroy drops a pending waiter without resuming it", function()
		local signal = Signal.new()
		local resumed = false
		local thread = task.spawn(function()
			signal:wait()
			resumed = true
		end)
		signal:destroy()
		signal:fire()
		expect.falsy(resumed)
		expect.equal(coroutine.status(thread), "suspended")
		expect.equal(connectionCount(signal), 0)
		task.cancel(thread)
	end)

	-- connect / once / fire -------------------------------------------------------------------------------------

	-- once() runs a single time; connect() runs on every fire until disconnected.
	t.test("once runs once and connect runs until disconnected", function()
		local signal = Signal.new()
		local onceCalls, connectCalls = 0, 0
		signal:once(function()
			onceCalls += 1
		end)
		local connection = signal:connect(function()
			connectCalls += 1
		end)
		signal:fire()
		signal:fire()
		connection:disconnect()
		signal:fire()
		expect.equal(onceCalls, 1)
		expect.equal(connectCalls, 2)
	end)
end
