--!strict
-- Scheduler_Test: unit tests for StarterPlayerScripts.Client.Anim.Scheduler. Server only (ServerStorage.UnitTest).
-- Uses private schedulers (Scheduler.new(false)) driven by tick(), so no frame event is ever connected here.
-- Contract (DESIGN §9.1 #3-#4): two phases ("joint" = PreSimulation, "render" = PreRender), at most two connections,
-- made lazily; effects are objects with step(dt, now) -> alive (plain functions allowed); dt clamped to <= 1/20 s;
-- anything but `true` removes the effect; an effect that errors is removed while the others run; an effect added
-- during a step runs from the next frame; add() returns a handle a Cleanup can destroy.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Scheduler = t.requireClient("Anim/Scheduler")
	local Config = t.requireShared("Config")
	local Cleanup = t.requireShared("Util/Cleanup")
	local expect = t.expect
	local MAX_DT = Config.Anim.Scheduler.maxDt

	t.test("steps effects with a clamped dt and the frame time, and keeps them while they return true", function()
		local scheduler = Scheduler.new(false)
		local seen: { number } = {}
		local effect = {
			step = function(_: any, dt: number, now: number): boolean
				table.insert(seen, dt)
				table.insert(seen, now)
				return true
			end,
		}
		scheduler:add(effect, "render")
		scheduler:tick("render", 1, 42)
		scheduler:tick("render", -1, 43)
		expect.deepEqual(seen, { MAX_DT, 42, 0, 43 })
		expect.equal(scheduler:count("render"), 1)
		expect.equal(scheduler:connectionCount(), 0)
	end)

	t.test("returning anything but true removes the effect", function()
		local scheduler = Scheduler.new(false)
		local calls = 0
		scheduler:add(function(): boolean
			calls += 1
			return calls < 3
		end, "joint")
		for _ = 1, 5 do
			scheduler:tick("joint", 1 / 60, 0)
		end
		expect.equal(calls, 3)
		expect.equal(scheduler:count(), 0)
	end)

	t.test("phases are separate", function()
		local scheduler = Scheduler.new(false)
		local joint, render = 0, 0
		scheduler:add(function(): boolean
			joint += 1
			return true
		end, "joint")
		scheduler:add(function(): boolean
			render += 1
			return true
		end) -- default phase: render
		scheduler:tick("joint", 1 / 60, 0)
		expect.equal(joint, 1)
		expect.equal(render, 0)
		scheduler:tick("render", 1 / 60, 0)
		expect.equal(render, 1)
		expect.equal(scheduler:count("joint"), 1)
		expect.equal(scheduler:count("render"), 1)
	end)

	t.test("an effect that errors is removed and the others still run", function()
		local scheduler = Scheduler.new(false)
		local after = 0
		scheduler:add(function(): boolean
			error("boom (expected by Scheduler_Test)")
		end)
		scheduler:add(function(): boolean
			after += 1
			return true
		end)
		scheduler:tick("render", 1 / 60, 0)
		scheduler:tick("render", 1 / 60, 0)
		expect.equal(after, 2)
		expect.equal(scheduler:count(), 1)
	end)

	t.test("an effect added during a step first runs on the next frame", function()
		local scheduler = Scheduler.new(false)
		local order: { string } = {}
		scheduler:add(function(): boolean
			table.insert(order, "parent")
			if #order == 1 then
				scheduler:add(function(): boolean
					table.insert(order, "child")
					return false
				end)
			end
			return true
		end)
		scheduler:tick("render", 1 / 60, 0)
		expect.deepEqual(order, { "parent" })
		scheduler:tick("render", 1 / 60, 0)
		expect.deepEqual(order, { "parent", "parent", "child" })
	end)

	t.test("handles disconnect, also from a Cleanup and from inside a step", function()
		local scheduler = Scheduler.new(false)
		local calls = 0
		local handle = scheduler:add(function(): boolean
			calls += 1
			return true
		end)
		local cleanup = Cleanup.new()
		cleanup:add(handle)
		cleanup:clean()
		expect.falsy(handle.connected)
		scheduler:tick("render", 1 / 60, 0)
		expect.equal(calls, 0)

		local selfHandle: any = nil
		local selfCalls = 0
		selfHandle = scheduler:add(function(): boolean
			selfCalls += 1
			selfHandle:disconnect()
			return true
		end)
		scheduler:tick("render", 1 / 60, 0)
		scheduler:tick("render", 1 / 60, 0)
		expect.equal(selfCalls, 1)
		expect.equal(scheduler:count(), 0)
	end)

	t.test("reset drops every effect", function()
		local scheduler = Scheduler.new(false)
		local handle = scheduler:add(function(): boolean
			return true
		end, "joint")
		scheduler:reset()
		expect.equal(scheduler:count(), 0)
		handle:disconnect() -- still safe
	end)

	t.test("rejects effects without step and unknown phases", function()
		local scheduler = Scheduler.new(false)
		expect.throws(function()
			scheduler:add({} :: any)
		end, "step")
		expect.throws(function()
			scheduler:add(function(): boolean
				return true
			end, "physics" :: any)
		end, "unknown phase")
	end)
end
