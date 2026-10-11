--!strict
-- RunUnitTest: discovers, filters, times and runs the unit test cases in the sibling `Cases` folder.
-- Server only (ServerStorage.UnitTest; never required at runtime). Built-in rbx-unit-test harness.
--
-- A case module is a ModuleScript named `<Module>_Test` anywhere under `Cases`. It returns `function(t)`:
--   t.test(name, fn)       runs one case in isolation (Arrange, Act, Assert)
--   t.expect.*             equal, deepEqual, near, throws, truthy, falsy
--   t.requireShared(path)  requires a module of the Shared folder under test, e.g. "Util/RateLimiter"
--   t.requireClient(path)  requires a module of the Client folder under test, e.g. "Anim/SquishDeformer"
--   t.requireServer(path)  requires a module of the Server folder under test, e.g. "Logic/PowerBudget"
--   t.requireFake(name)    requires a fake from the sibling `Fakes` folder, e.g. "FakeClock"
--   t.Shared, t.Client, t.Server   the folders under test (nil if none was found)
-- Client and server modules require Shared through ReplicatedStorage.Shared (the copy in the place, not deps.Shared),
-- so sync before testing them (tools/mcp/run-tests.mjs points those requires at its Shared clone instead, because the
-- plugin VM's require cache can hold an older copy of the place's modules). Tests run in Edit mode: no Players.LocalPlayer and no Play-only APIs.
--
-- Call: RunUnitTest(filter?, timeout?, deps?) -> Summary
--   filter   plain substring of the case module name (nil = every case module)
--   timeout  seconds per case (default 5); it only bounds cases that yield
--   deps     { Shared = <folder>, Client = <folder>, Server = <folder> }, each optional; defaults
--            ReplicatedStorage.Shared, StarterPlayer.StarterPlayerScripts.Client, ServerScriptService.Server.
--            Pass clones (see below) so the require cache never serves stale code.
-- Prints one [PASS] / [FAIL] / [TIMEOUT] line per case and a [SUMMARY] line, and returns the summary table.
-- The run passes only when summary.failed == 0 (`failed` includes timeouts; `timedOut` counts them separately).
--
-- Play (server):  return require(game.ServerStorage.UnitTest.RunUnitTest)(nil, 5)
-- Edit (pure modules, no Play needed): run fresh clones, so the require cache never serves stale code:
--   local SS, RS = game:GetService("ServerStorage"), game:GetService("ReplicatedStorage")
--   local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client:Clone()
--   local server = game:GetService("ServerScriptService").Server:Clone()
--   local tests, shared = SS.UnitTest:Clone(), RS.Shared:Clone()
--   local deps = { Shared = shared, Client = client, Server = server }
--   local ok, summary = pcall(function() return require(tests.RunUnitTest)(nil, 5, deps) end)
--   tests:Destroy(); shared:Destroy(); client:Destroy(); server:Destroy()
--   return ok and summary or ("TESTS DID NOT RUN: " .. tostring(summary))
-- Cases and fakes are found relative to this script, so a clone runs its own copies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

export type Expect = {
	equal: (actual: unknown, expected: unknown) -> (),
	deepEqual: (actual: unknown, expected: unknown) -> (),
	near: (actual: unknown, expected: number, tolerance: number?) -> (),
	throws: (fn: () -> ...any, contains: string?) -> string,
	truthy: (value: unknown) -> (),
	falsy: (value: unknown) -> (),
}

export type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: Expect,
	Shared: Instance?,
	Client: Instance?,
	Server: Instance?,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

export type Failure = {
	case: string,
	test: string,
	status: string,
	message: string,
}

export type Summary = {
	run: number,
	passed: number,
	failed: number,
	timedOut: number,
	durationSec: number,
	failures: { Failure },
}

export type Deps = {
	Shared: Instance?,
	Client: Instance?,
	Server: Instance?,
}

local DEFAULT_TIMEOUT = 5
local DEFAULT_TOLERANCE = 1e-6
local CASE_SUFFIX = "_Test"

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve these paths statically.
local dynamicRequire = require :: (ModuleScript) -> any

local function fmt(v: unknown): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

-- Matchers -------------------------------------------------------------------------------------------------

local expect = {} :: Expect

function expect.equal(actual: unknown, expected: unknown)
	if actual ~= expected then
		error(string.format("expected %s, got %s", fmt(expected), fmt(actual)), 2)
	end
end

-- Returns a description of the first difference between two values, or nil when they are deeply equal.
local function firstDifference(actual: any, expected: any, path: string, seen: { [any]: any }): string?
	if actual == expected then
		return nil
	end
	local where = if path == "" then "(root)" else path
	if type(actual) ~= "table" or type(expected) ~= "table" then
		return string.format("at %s: expected %s, got %s", where, fmt(expected), fmt(actual))
	end
	if seen[actual] == expected then
		return nil -- already being compared (cycle)
	end
	seen[actual] = expected
	for key, value in actual do
		local diff = firstDifference(value, expected[key], path .. "[" .. fmt(key) .. "]", seen)
		if diff then
			return diff
		end
	end
	for key, value in expected do
		if actual[key] == nil then
			return string.format("at %s[%s]: expected %s, got nil", path, fmt(key), fmt(value))
		end
	end
	return nil
end

function expect.deepEqual(actual: unknown, expected: unknown)
	local diff = firstDifference(actual, expected, "", {})
	if diff then
		error("not deeply equal " .. diff, 2)
	end
end

-- Use for floating point results. NaN never passes.
function expect.near(actual: unknown, expected: number, tolerance: number?)
	local tol = if tolerance == nil then DEFAULT_TOLERANCE else tolerance
	if type(actual) ~= "number" or not (math.abs(actual - expected) <= tol) then
		error(string.format("expected %s within %s of %s", fmt(actual), fmt(tol), fmt(expected)), 2)
	end
end

-- Asserts that fn raises; optionally that the message contains `contains` (plain text). Returns the message.
function expect.throws(fn: () -> ...any, contains: string?): string
	local ok, err = pcall(fn)
	if ok then
		error("expected the function to throw, but it returned normally", 2)
	end
	local message = tostring(err)
	if contains ~= nil and string.find(message, contains, 1, true) == nil then
		error(string.format("expected an error containing %s, got %s", fmt(contains), fmt(message)), 2)
	end
	return message
end

function expect.truthy(value: unknown)
	if not value then
		error(string.format("expected truthy, got %s", fmt(value)), 2)
	end
end

function expect.falsy(value: unknown)
	if value then
		error(string.format("expected falsy, got %s", fmt(value)), 2)
	end
end

table.freeze(expect)

-- Runner ---------------------------------------------------------------------------------------------------

-- Runs one case in its own thread with a yield-based timeout. A case that never yields (a tight infinite
-- loop) cannot be preempted; the timeout only bounds cases that yield while waiting.
local function runOne(fn: () -> (), timeout: number): (string, number, string?)
	local done, ok, err = false, false, nil :: unknown
	local started = os.clock()
	local thread = task.spawn(function()
		ok, err = pcall(fn)
		done = true
	end)
	local waited = 0
	while not done and waited < timeout do
		waited += task.wait()
	end
	local elapsed = if waited > 0 then waited else os.clock() - started
	if not done then
		task.cancel(thread)
		return "timeout", elapsed, string.format("exceeded %.1fs", timeout)
	elseif ok then
		return "pass", elapsed, nil
	end
	return "fail", elapsed, tostring(err)
end

-- Walks `path` ("Util/RateLimiter") below `root` and returns the ModuleScript; errors with a clear message.
local function findModule(root: Instance?, rootLabel: string, path: string): ModuleScript
	if root == nil then
		error(
			string.format("%s folder not found (cannot load %s; pass deps.%s or sync it)", rootLabel, path, rootLabel),
			3
		)
	end
	local node: Instance = root
	for part in string.gmatch(path, "[^/]+") do
		local child = node:FindFirstChild(part)
		if child == nil then
			error(string.format("module not found: %s/%s", rootLabel, path), 3)
		end
		node = child
	end
	if not node:IsA("ModuleScript") then
		error(string.format("not a ModuleScript: %s/%s", rootLabel, path), 3)
	end
	return node
end

local function findCaseModules(casesFolder: Instance?, filter: string?): { ModuleScript }
	local found: { ModuleScript } = {}
	if casesFolder == nil then
		return found
	end
	for _, descendant in casesFolder:GetDescendants() do
		if
			descendant:IsA("ModuleScript")
			and string.sub(descendant.Name, -#CASE_SUFFIX) == CASE_SUFFIX
			and (filter == nil or string.find(descendant.Name, filter, 1, true) ~= nil)
		then
			table.insert(found, descendant)
		end
	end
	table.sort(found, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return found
end

local function runUnitTest(filter: string?, timeout: number?, deps: Deps?): Summary
	local limit = if timeout == nil then DEFAULT_TIMEOUT else timeout
	local sessionStart = os.clock()
	local summary: Summary = { run = 0, passed = 0, failed = 0, timedOut = 0, durationSec = 0, failures = {} }

	local root = script.Parent
	local casesFolder = if root then root:FindFirstChild("Cases") else nil
	local fakesFolder = if root then root:FindFirstChild("Fakes") else nil
	local shared: Instance? = if deps and deps.Shared then deps.Shared else ReplicatedStorage:FindFirstChild("Shared")
	local playerScripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	local client: Instance? = if deps and deps.Client
		then deps.Client
		elseif playerScripts then playerScripts:FindFirstChild("Client")
		else nil
	local server: Instance? = if deps and deps.Server then deps.Server else ServerScriptService:FindFirstChild("Server")

	local function fail(caseName: string, testName: string, status: string, message: string)
		summary.failed += 1
		if status == "timeout" then
			summary.timedOut += 1
		end
		table.insert(summary.failures, { case = caseName, test = testName, status = status, message = message })
	end

	if casesFolder == nil then
		warn("[UnitTest] no Cases folder next to RunUnitTest")
	end
	if shared == nil then
		warn("[UnitTest] no Shared folder (pass deps.Shared, or sync ReplicatedStorage.Shared)")
	end

	for _, module in findCaseModules(casesFolder, filter) do
		local caseName = module.Name
		local okRequire, caseFn = pcall(dynamicRequire, module)
		if not okRequire or type(caseFn) ~= "function" then
			summary.run += 1
			local message = if okRequire then "case module did not return a function" else tostring(caseFn)
			fail(caseName, "(load)", "fail", message)
			warn(string.format("[FAIL] %s | %s", caseName, message))
			continue
		end

		local t: Context = {
			expect = expect,
			Shared = shared,
			Client = client,
			Server = server,
			test = function(name: string, fn: () -> ())
				summary.run += 1
				if type(name) ~= "string" or type(fn) ~= "function" then
					fail(caseName, tostring(name), "fail", "t.test needs (name: string, fn: function)")
					warn(
						string.format("[FAIL] %s > %s | t.test needs (name: string, fn: function)", caseName, fmt(name))
					)
					return
				end
				local status, elapsed, message = runOne(fn, limit)
				if status == "pass" then
					summary.passed += 1
					print(string.format("[PASS] %s > %s (%.3fs)", caseName, name, elapsed))
				else
					local text = message or ""
					fail(caseName, name, status, text)
					warn(
						string.format("[%s] %s > %s (%.3fs) | %s", string.upper(status), caseName, name, elapsed, text)
					)
				end
			end,
			requireShared = function(path: string): any
				return dynamicRequire(findModule(shared, "Shared", path))
			end,
			requireClient = function(path: string): any
				return dynamicRequire(findModule(client, "Client", path))
			end,
			requireServer = function(path: string): any
				return dynamicRequire(findModule(server, "Server", path))
			end,
			requireFake = function(name: string): any
				return dynamicRequire(findModule(fakesFolder, "Fakes", name))
			end,
		}

		local okBuild, buildErr = pcall(caseFn, t)
		if not okBuild then
			summary.run += 1
			fail(caseName, "(build)", "fail", tostring(buildErr))
			warn(string.format("[FAIL] %s | error while building cases: %s", caseName, tostring(buildErr)))
		end
	end

	summary.durationSec = os.clock() - sessionStart
	print(
		string.format(
			"[SUMMARY] %d run, %d passed, %d failed, %.3fs",
			summary.run,
			summary.passed,
			summary.failed,
			summary.durationSec
		)
	)
	return summary
end

return runUnitTest
