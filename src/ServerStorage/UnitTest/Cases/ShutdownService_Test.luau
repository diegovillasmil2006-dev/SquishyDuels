--!strict
-- ShutdownService_Test: unit tests for ServerScriptService.Server.Services.ShutdownService (pure helpers only).
-- Server only (ServerStorage.UnitTest). Edit mode: init() is never called (it binds BindToClose), the closing flag and
-- the restart time of the module are never touched; only the helpers that take their inputs as arguments are run.
-- Contract (DESIGN §3.12, §5.4):
--   * runTasksAsync runs every close task in parallel and returns (finished, total) as soon as all finished, or at the
--     deadline with the slow ones still counted as unfinished;
--   * canFinishBeforeRestart(seconds, at, now): true without a restart; otherwise true only when now + seconds ends
--     at least Config.Duel.RestartMarginSeconds before the restart;
--   * secondsUntil never goes below 0 and turns non-finite input into 0.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local ShutdownService = t.requireServer("Services/ShutdownService")
	local Config = t.requireShared("Config")

	t.test("runTasksAsync: every task runs; returns as soon as all are done", function()
		local ran = {}
		local tasks = {
			{
				name = "fast",
				fn = function()
					table.insert(ran, "fast")
				end,
			},
			{
				name = "yielding",
				fn = function()
					task.wait(0.05)
					table.insert(ran, "yielding")
				end,
			},
		}
		local started = os.clock()
		local finished, total = ShutdownService.runTasksAsync(tasks, 2)
		expect.equal(total, 2)
		expect.equal(finished, 2)
		expect.equal(#ran, 2)
		expect.truthy(os.clock() - started < 1)
	end)

	t.test("runTasksAsync: stops waiting at the deadline", function()
		local tasks = {
			{
				name = "slow",
				fn = function()
					task.wait(1)
				end,
			},
		}
		local started = os.clock()
		local finished, total = ShutdownService.runTasksAsync(tasks, 0.1)
		expect.equal(total, 1)
		expect.equal(finished, 0)
		expect.truthy(os.clock() - started < 0.9)
	end)

	t.test("runTasksAsync: no tasks returns at once", function()
		local finished, total = ShutdownService.runTasksAsync({}, 5)
		expect.equal(finished, 0)
		expect.equal(total, 0)
	end)

	t.test("canFinishBeforeRestart keeps the restart margin", function()
		local margin = Config.Duel.RestartMarginSeconds
		local now = 1000
		local restart = now + 100
		expect.truthy(ShutdownService.canFinishBeforeRestart(100 - margin, restart, now))
		expect.falsy(ShutdownService.canFinishBeforeRestart(100 - margin + 1, restart, now))
		expect.falsy(ShutdownService.canFinishBeforeRestart(0, now + margin - 1, now))
	end)

	t.test("secondsUntil clamps at 0 and rejects non-finite values", function()
		expect.equal(ShutdownService.secondsUntil(110, 100), 10)
		expect.equal(ShutdownService.secondsUntil(90, 100), 0)
		expect.equal(ShutdownService.secondsUntil(0 / 0, 100), 0)
		expect.equal(ShutdownService.secondsUntil(math.huge, 100), 0)
	end)

	t.test("signals and state queries exist", function()
		expect.equal(type(ShutdownService.Closing.connect), "function")
		expect.equal(type(ShutdownService.RestartScheduled.connect), "function")
		expect.equal(type(ShutdownService.isClosing()), "boolean")
		expect.equal(type(ShutdownService.isRestartPending()), "boolean")
	end)
end
