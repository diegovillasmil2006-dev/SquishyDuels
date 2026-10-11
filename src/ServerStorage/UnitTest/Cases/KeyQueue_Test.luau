--!strict
-- KeyQueue_Test: per-key serialized jobs, retries, backoff and error classes (DESIGN §3.6; server Logic/KeyQueue).
-- Server only (ServerStorage.UnitTest). Waits are injected (recorded, never slept); the only real yields are the
-- gates some jobs block on, opened by the test itself.
-- Contract:
--   * one FIFO per key (a job never starts before the previous one on its key ended); keys run in parallel;
--   * up to 5 attempts; delay min(16, 2^(n-1)) * (1 + random() * 0.5); throttle 301-306 doubles it;
--   * not retried: 101-107, 403, 509, 511-513 ("fatal") and the Studio access error; 401/402 stop ALL work;
--     retried: 404, 501-505, unknown;
--   * onStart runs once before the first attempt, onFinish once with the final outcome;
--   * dropPendingExceptLast folds not-yet-started droppable jobs into the key's last job (its result is theirs).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local KeyQueue = t.requireServer("Logic/KeyQueue")
	local Signal = t.requireShared("Util/Signal")

	local function newQueue(randomValue: number?, attempts: number?): (any, { number })
		local waits: { number } = {}
		local queue = KeyQueue.new({
			wait = function(seconds: number)
				table.insert(waits, seconds)
			end,
			random = function(): number
				return randomValue or 0
			end,
			attempts = attempts,
		})
		return queue, waits
	end

	-- A job whose fn throws each message of `failures` in turn, then returns `value`.
	local function flaky(failures: { string }, value: any): (any, () -> number)
		local calls = 0
		local job = {
			name = "flaky",
			fn = function(): any
				calls += 1
				local failure = failures[calls]
				if failure then
					error(failure, 0)
				end
				return value
			end,
		}
		return job, function(): number
			return calls
		end
	end

	t.test("classify follows the §3.6 error classes", function()
		local cases: { { string | number } } = {
			{ "301: throttled", "throttle" },
			{ "304: Request was throttled", "throttle" },
			{ "306: x", "throttle" },
			{ "101: Key name can't be empty", "fatal" },
			{ "105: Serialized value too large", "fatal" },
			{ "107: x", "fatal" },
			{ "403: Cannot store data in Studio", "fatal" },
			{ "509: x", "fatal" },
			{ "511: x", "fatal" },
			{ "513: x", "fatal" },
			{ "401: DataModel inaccessible when the game is shutting down", "shutdown" },
			{ "402: x", "shutdown" },
			{ "404: x", "retry" },
			{ "501: x", "retry" },
			{ "503: x", "retry" },
			{ "505: x", "retry" },
			{ "something odd happened", "retry" },
			{
				"502: API Services rejected request with error. Error code: 7 Reason: Studio access denied",
				"studioAccess",
			},
			{ "502: API Services rejected request. StudioAccessToApisNotAllowed", "studioAccess" },
			{ "ServerScriptService.Server.Services.DataService:120: 304: throttled", "throttle" },
		}
		for _, case in cases do
			local class = KeyQueue.classify(case[1] :: string)
			if class ~= case[2] then
				error(`classify({case[1]}) = {class}, expected {case[2]}`)
			end
		end
		local _, code = KeyQueue.classify("304: x")
		expect.equal(code, 304)
	end)

	t.test("a retried error is attempted again after 1 s, 2 s, ... (random 0)", function()
		local queue, waits = newQueue(0)
		local job, calls = flaky({ "503: busy", "503: busy" }, "done")
		local ok, value, class = queue:run("k", job)
		expect.equal(ok, true)
		expect.equal(value, "done")
		expect.equal(class, nil)
		expect.equal(calls(), 3)
		expect.deepEqual(waits, { 1, 2 })
	end)

	t.test("jitter scales the delay by (1 + random * 0.5)", function()
		local queue, waits = newQueue(1)
		local job = flaky({ "503: busy", "503: busy" }, true)
		queue:run("k", job)
		expect.near(waits[1], 1.5)
		expect.near(waits[2], 3)
	end)

	t.test("throttle 304 doubles the delay", function()
		local queue, waits = newQueue(0)
		local job, calls = flaky({ "304: throttled", "304: throttled" }, true)
		local ok = queue:run("k", job)
		expect.equal(ok, true)
		expect.equal(calls(), 3)
		expect.deepEqual(waits, { 2, 4 })
	end)

	t.test("non-retryable 105 fails at once (one attempt, no wait)", function()
		local queue, waits = newQueue(0)
		local job, calls = flaky({ "105: too big", "105: too big" }, true)
		local ok, value, class, message = queue:run("k", job)
		expect.equal(ok, false)
		expect.equal(value, nil)
		expect.equal(class, "fatal")
		expect.truthy(string.find(message, "105", 1, true))
		expect.equal(calls(), 1)
		expect.equal(#waits, 0)
	end)

	t.test("the Studio access error is not retried", function()
		local queue, waits = newQueue(0)
		local job, calls = flaky({ "502: API Services rejected request with error. Error code: 7" }, true)
		local ok, _, class = queue:run("k", job)
		expect.equal(ok, false)
		expect.equal(class, "studioAccess")
		expect.equal(calls(), 1)
		expect.equal(#waits, 0)
	end)

	t.test("5 attempts at most; the delay is capped at 16 s", function()
		local queue, waits = newQueue(0)
		local failures = table.create(10, "503: busy")
		local job, calls = flaky(failures, true)
		local ok, _, class = queue:run("k", job)
		expect.equal(ok, false)
		expect.equal(class, "retry")
		expect.equal(calls(), 5)
		expect.deepEqual(waits, { 1, 2, 4, 8 })

		local longQueue, longWaits = newQueue(0, 8)
		longQueue:run("k", (flaky(failures, true)))
		expect.deepEqual(longWaits, { 1, 2, 4, 8, 16, 16, 16 })
	end)

	t.test("onStart runs once before the attempts; onFinish once with the outcome", function()
		local queue = newQueue(0)
		local events = {}
		local job = flaky({ "503: busy" }, "v")
		job.onStart = function()
			table.insert(events, "start")
		end
		job.onFinish = function(ok: boolean, value: any)
			table.insert(events, `finish {tostring(ok)} {tostring(value)}`)
		end
		local ticket = queue:enqueue("k", job)
		expect.equal(ticket:isStarted(), true)
		expect.equal(ticket:isDone(), true)
		expect.deepEqual(events, { "start", "finish true v" })
	end)

	t.test("one FIFO per key: a job never starts before the previous one on its key ended", function()
		local queue = newQueue(0)
		local gate = Signal.new()
		local order = {}
		local first = queue:enqueue("k", {
			fn = function(): any
				table.insert(order, "A start")
				gate:wait()
				table.insert(order, "A end")
				return "a"
			end,
		})
		local second = queue:enqueue("k", {
			fn = function(): any
				table.insert(order, "B")
				return "b"
			end,
		})
		local other = queue:enqueue("other", {
			fn = function(): any
				table.insert(order, "C (other key)")
				return "c"
			end,
		})
		-- A blocks key "k"; key "other" ran meanwhile; B waits behind A.
		expect.deepEqual(order, { "A start", "C (other key)" })
		expect.equal(second:isStarted(), false)
		expect.equal(queue:pendingCount("k"), 1)
		expect.equal(other:isDone(), true)
		gate:fire()
		local ok, value = second:await()
		expect.equal(ok, true)
		expect.equal(value, "b")
		expect.deepEqual(order, { "A start", "C (other key)", "A end", "B" })
		expect.equal(select(2, first:await()), "a")
		expect.equal(queue:isBusy("k"), false)
	end)

	t.test("dropPendingExceptLast folds pending droppable jobs into the last one", function()
		local queue = newQueue(0)
		local gate = Signal.new()
		local ran = {}
		local function job(name: string, droppable: boolean, blocking: boolean?): any
			return {
				name = name,
				droppable = droppable,
				fn = function(): any
					if blocking then
						gate:wait()
					end
					table.insert(ran, name)
					return name .. " result"
				end,
			}
		end
		queue:enqueue("k", job("running", true, true))
		local b = queue:enqueue("k", job("b", true))
		local unlock = queue:enqueue("k", job("unlock", false))
		local c = queue:enqueue("k", job("c", true))
		local last = queue:enqueue("k", job("last", true))
		-- another key with a single pending job: nothing to drop there
		local single = queue:enqueue("j", job("single", true, true))
		expect.equal(queue:dropPendingExceptLast(), 2)
		expect.equal(queue:pendingCount("k"), 2) -- the non-droppable unlock + last
		expect.equal(b:isDropped(), true)
		expect.equal(c:isDropped(), true)
		expect.equal(unlock:isDropped(), false)
		expect.equal(last:isDropped(), false)
		gate:fire()
		-- the gate wakes "running" first (it waited first), whose runner then runs the rest of key "k"
		expect.deepEqual(ran, { "running", "unlock", "last", "single" })
		local okB, valueB = b:await()
		local okC, valueC = c:await()
		expect.equal(okB, true)
		expect.equal(valueB, "last result")
		expect.equal(okC, true)
		expect.equal(valueC, "last result")
		expect.equal(select(2, unlock:await()), "unlock result")
		expect.equal(select(2, last:await()), "last result")
		expect.equal(select(2, single:await()), "single result")
	end)

	t.test("nothing is dropped when the last pending job is not droppable", function()
		local queue = newQueue(0)
		local gate = Signal.new()
		queue:enqueue("k", {
			fn = function(): any
				gate:wait()
				return 1
			end,
		})
		queue:enqueue("k", {
			droppable = true,
			fn = function(): any
				return 2
			end,
		})
		queue:enqueue("k", {
			droppable = false,
			fn = function(): any
				return 3
			end,
		})
		expect.equal(queue:dropPendingExceptLast(), 0)
		expect.equal(queue:pendingCount("k"), 2)
		gate:fire()
	end)

	t.test("shutdown 401 stops all work: pending and later jobs fail with class shutdown", function()
		local queue, waits = newQueue(0)
		local gate = Signal.new()
		local blocked = queue:enqueue("a", {
			fn = function(): any
				gate:wait()
				error("401: DataModel inaccessible when the game is shutting down", 0)
			end,
		})
		local behind = queue:enqueue("a", {
			fn = function(): any
				return "never"
			end,
		})
		local finished: { string } = {}
		local onOther = queue:enqueue("b", {
			fn = function(): any
				gate:wait()
				return "never either"
			end,
			onFinish = function(ok: boolean, _value: any, class: string?)
				table.insert(finished, `{tostring(ok)} {tostring(class)}`)
			end,
		})
		gate:fire()
		local ok, _, class = blocked:await()
		expect.equal(ok, false)
		expect.equal(class, "shutdown")
		expect.equal(#waits, 0) -- never retried
		local okBehind, _, classBehind = behind:await()
		expect.equal(okBehind, false)
		expect.equal(classBehind, "shutdown")
		expect.equal(queue:isStopped(), true)
		-- the job that was already running on another key ends as it can (here it succeeds), nothing new starts
		local okOther = onOther:await()
		expect.equal(okOther, true)
		expect.deepEqual(finished, { "true nil" })
		local okLate, _, classLate = queue:run("c", {
			fn = function(): any
				return "late"
			end,
		})
		expect.equal(okLate, false)
		expect.equal(classLate, "shutdown")
	end)

	t.test("an error in onStart fails the job without calling fn", function()
		local queue = newQueue(0)
		local job, calls = flaky({}, true)
		job.onStart = function()
			error("snapshot failed")
		end
		local ok, _, class = queue:run("k", job)
		expect.equal(ok, false)
		expect.equal(class, "fatal")
		expect.equal(calls(), 0)
	end)
end
