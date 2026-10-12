--!strict
-- NetService_Test: unit tests for ServerScriptService.Server.Services.NetService (pure parts only).
-- Server only (ServerStorage.UnitTest). Edit mode: init() is never called (it creates remotes in a running server), no
-- remote is fired; the per-player guard runs with plain table keys and a FakeClock.
-- Contract (DESIGN §2.7, §2.8, §12 #1-#2):
--   * every Remotes.ArgType a client -> server remote uses narrows only valid values: finite numbers (x == x,
--     |x| < 1e6), serverTime (|x| < 1e10), whole integers, finite Vector3s, ids by their §2.7 patterns and lengths,
--     tables up to the key cap; NaN, inf, 1 KB strings, wrong types and unknown types fail;
--   * validateArgs checks the argument count (too many = badArgCount) and every argument of a real remote;
--   * ShopBuy's expectedPrice is a whole Coin amount up to Config.Economy.maxCoins (Dragon costs 1.1T, spec 2026-10-12
--     §6), never NaN, inf, negative, fractional or above the cap;
--   * OnboardingStep takes the client-recorded steps plus the Skip tutorial id (Part 7); TrainerUpgrade (Part 7) takes
--     two whole numbers and rejects NaN, inf, 1e9, strings, fractions and extra arguments; SqueezeRequest takes no
--     argument (spec 2026-10-11 §5: the server finds the pad itself), so a station id or anything else is badArgCount;
--   * the guard runs mute -> per-remote bucket -> global cap (30/s, burst 80) -> arg count -> types -> seq replay;
--     a rate-limit hit, a wrong count or an invalid argument is a violation; more than 20 violations in 60 s mute the
--     key for 30 s; muted calls are dropped without counting; a stale seq is dropped but is no violation;
--     reset() forgets a key;
--   * ok() / err() build the Result shapes NetService completes with `v`.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local GUID = "0123abcd-4567-89ab-cdef-0123456789ab"

return function(t: Context)
	local expect = t.expect
	local NetService = t.requireServer("Services/NetService")
	local Config = t.requireShared("Config")
	local Remotes = t.requireShared("Remotes")
	local FakeClock = t.requireFake("FakeClock")

	local NAN = 0 / 0
	local INF = math.huge
	local KB_STRING = string.rep("a", 1024)

	local function valid(argType: string, value: any): boolean
		local ok = NetService.validateArg(argType, value)
		return ok
	end

	-- A guard with a fake clock and optional overrides; returns (guard, clock, mutes).
	local function makeGuard(overrides: { [string]: any }?): (any, any, { any })
		local clock = FakeClock.new(500)
		local mutes = {}
		local deps: { [string]: any } = {
			clock = clock.now,
			onMute = function(key: any, name: string, untilTime: number)
				table.insert(mutes, { key = key, name = name, untilTime = untilTime })
			end,
		}
		if overrides then
			for k, v in overrides do
				deps[k] = v
			end
		end
		return NetService.newGuard(deps), clock, mutes
	end

	t.test("numbers: finite only, |x| < 1e6; integers must be whole", function()
		expect.truthy(valid("number", 12.5))
		expect.truthy(valid("number", -999999))
		expect.falsy(valid("number", NAN))
		expect.falsy(valid("number", INF))
		expect.falsy(valid("number", -INF))
		expect.falsy(valid("number", 1e6))
		expect.falsy(valid("number", "5"))
		expect.truthy(valid("integer", 7))
		expect.falsy(valid("integer", 7.5))
		expect.falsy(valid("integer", NAN))
		expect.falsy(valid("integer", true))
	end)

	t.test("serverTime accepts GetServerTimeNow-sized values and rejects NaN/inf/1e10", function()
		expect.truthy(valid("serverTime", 1.8e9))
		expect.falsy(valid("serverTime", 1e10))
		expect.falsy(valid("serverTime", NAN))
		expect.falsy(valid("serverTime", INF))
		expect.falsy(valid("serverTime", "1800000000"))
	end)

	t.test("Vector3: every component finite", function()
		expect.truthy(valid("Vector3", Vector3.new(1, 2, 3)))
		expect.falsy(valid("Vector3", Vector3.new(NAN, 0, 0)))
		expect.falsy(valid("Vector3", Vector3.new(0, INF, 0)))
		expect.falsy(valid("Vector3", Vector3.new(0, 0, 2e6)))
		expect.falsy(valid("Vector3", { X = 1, Y = 2, Z = 3 }))
		expect.falsy(valid("Vector3", CFrame.new()))
	end)

	t.test("ids follow the §2.7 patterns and lengths", function()
		expect.truthy(valid("squishyId", "kitty_bread"))
		expect.falsy(valid("squishyId", "Kitty"))
		expect.falsy(valid("squishyId", KB_STRING))
		expect.falsy(valid("squishyId", 5))
		expect.truthy(valid("boxId", "snack"))
		expect.truthy(valid("bundleKey", "coins_jar"))
		expect.truthy(valid("passKey", "vip"))
		expect.truthy(valid("requestId", GUID))
		expect.falsy(valid("requestId", "not-a-guid"))
		expect.falsy(valid("requestId", KB_STRING))
		expect.truthy(valid("revealRequestId", GUID))
		expect.truthy(valid("revealRequestId", "daily:20000"))
		expect.falsy(valid("revealRequestId", "daily:x"))
		expect.truthy(valid("questId", "q20000_1"))
		expect.truthy(valid("questId", "starter_jelly"))
		expect.falsy(valid("questId", "q1"))
	end)

	t.test("SqueezeRequest takes no argument: a station id (any argument) is badArgCount", function()
		expect.equal(#Remotes.SPEC.SqueezeRequest.args, 0)
		local ok, args = NetService.validateArgs("SqueezeRequest")
		expect.truthy(ok)
		expect.equal(#args, 0)
		local extras: { any } = { "squeeze_09", "squeeze_99", KB_STRING, Vector3.zero, NAN }
		for _, extra in extras do
			local okExtra, why = NetService.validateArgs("SqueezeRequest", extra)
			expect.falsy(okExtra)
			expect.equal(why, "badArgCount")
		end
	end)

	t.test("stepId accepts only the client-recorded onboarding steps", function()
		for _, step in Config.Onboarding.Steps do
			expect.equal(valid("stepId", step.id), step.recordedBy == "client")
		end
		expect.falsy(valid("stepId", "duel_win"))
		expect.falsy(valid("stepId", KB_STRING))
	end)

	t.test("stepId also accepts the Skip tutorial id (Config.Onboarding.skipStepId), nothing else new", function()
		local skipId = Config.Onboarding.skipStepId
		expect.equal(type(skipId), "string")
		expect.truthy(valid("stepId", skipId))
		expect.falsy(valid("stepId", string.upper(skipId)))
		expect.falsy(valid("stepId", "skipped"))
		local ok, args = NetService.validateArgs("OnboardingStep", skipId)
		expect.truthy(ok)
		expect.equal(args[1], skipId)
		local okMany, whyMany = NetService.validateArgs("OnboardingStep", skipId, "extra")
		expect.falsy(okMany)
		expect.equal(whyMany, "badArgCount")
	end)

	t.test("TrainerUpgrade: two whole numbers; NaN, inf, 1e9, strings, fractions, extra args fail", function()
		local ok, args = NetService.validateArgs("TrainerUpgrade", 2, 1000)
		expect.truthy(ok)
		expect.equal(args[1], 2)
		expect.equal(args[2], 1000)
		local bad: { { any } } = {
			{ NAN, 1000 },
			{ 2, NAN },
			{ INF, 1000 },
			{ 2, -INF },
			{ 2, 1e9 },
			{ 1e9, 1000 },
			{ "2", 1000 },
			{ 2, "1000" },
			{ 2.5, 1000 },
			{ 2, 1000.5 },
			{ 2 }, -- missing expectedPrice
			{ {}, 1000 },
		}
		for i, case in bad do
			local okBad, why = NetService.validateArgs("TrainerUpgrade", table.unpack(case))
			if okBad or why ~= "invalid" then
				error(`bad TrainerUpgrade case {i} was not rejected as invalid ({tostring(why)})`)
			end
		end
		local okMany, whyMany = NetService.validateArgs("TrainerUpgrade", 2, 1000, "extra")
		expect.falsy(okMany)
		expect.equal(whyMany, "badArgCount")
		local entry = Config.Net.Remotes.TrainerUpgrade
		expect.truthy(entry ~= nil and entry.oneInFlight == true)
	end)

	t.test("ShopBuy: a whole Coin price up to maxCoins passes; NaN, inf, negative, fractions and more fail", function()
		local dragon = 1_100_000_000_000 -- above the 1e6 "integer" bound (spec 2026-10-12 §6)
		local ok, args = NetService.validateArgs("ShopBuy", "dragon", dragon, GUID)
		expect.truthy(ok)
		expect.equal(args[2], dragon)
		expect.truthy(valid("coins", Config.Economy.maxCoins))
		expect.truthy(valid("coins", 0))
		local bads: { any } = { 0 / 0, math.huge, -1, 2.5, Config.Economy.maxCoins + 2, "10000" }
		for _, bad in bads do
			if valid("coins", bad) then
				error(`coins accepted {tostring(bad)}`)
			end
		end
	end)

	t.test("booleans, strings and tables; unknown types fail closed", function()
		expect.truthy(valid("boolean", false))
		expect.falsy(valid("boolean", 0))
		expect.truthy(valid("string", "abc"))
		expect.falsy(valid("string", KB_STRING))
		expect.truthy(valid("table", { music = 10 }))
		expect.falsy(valid("table", "x"))
		local big = {}
		for i = 1, 100 do
			big[i] = i
		end
		expect.falsy(valid("table", big))
		expect.falsy(valid("reasonCode", "net.invalid")) -- server -> client only
		expect.falsy(valid("noSuchType", 1))
	end)

	t.test("every client -> server arg type in Remotes.SPEC has a check", function()
		local sample: { [string]: any } = {
			integer = 1,
			number = 1,
			serverTime = 1.8e9,
			coins = 1_100_000_000_000,
			boolean = true,
			string = "a",
			table = {},
			Vector3 = Vector3.one,
			squishyId = "toast",
			boxId = "snack",
			bundleKey = "coins_jar",
			passKey = "vip",
			requestId = GUID,
			revealRequestId = GUID,
			questId = "q1_1",
		}
		for _, step in Config.Onboarding.Steps do
			if step.recordedBy == "client" then
				sample.stepId = step.id
			end
		end
		for name, spec in Remotes.SPEC do
			if spec.dir == "c2s" then
				for _, arg in spec.args do
					local value = sample[arg.type]
					if value == nil then
						error(`no sample for {name}.{arg.name} ({arg.type})`)
					end
					if not valid(arg.type, value) then
						error(`{name}.{arg.name} ({arg.type}) rejects a valid value`)
					end
				end
			end
		end
	end)

	t.test("validateArgs: ThrowRequest shape, NaN/inf vectors, wrong types, too many args", function()
		local ok, args = NetService.validateArgs("ThrowRequest", 3, Vector3.new(0, 0, -1), Vector3.new(1, 2, 3), 1.8e9)
		expect.truthy(ok)
		expect.equal(args[1], 3)
		expect.equal(args[4], 1.8e9)
		local bad: { { any } } = {
			{ 3, Vector3.new(NAN, 0, 0), Vector3.one, 1.8e9 },
			{ 3, Vector3.new(0, 0, -1), Vector3.new(INF, 0, 0), 1.8e9 },
			{ "3", Vector3.new(0, 0, -1), Vector3.one, 1.8e9 },
			{ 3.5, Vector3.new(0, 0, -1), Vector3.one, 1.8e9 },
			{ 3, Vector3.new(0, 0, -1), Vector3.one, NAN },
			{ 3, KB_STRING, Vector3.one, 1.8e9 },
			{ 3, Vector3.new(0, 0, -1), Vector3.one }, -- missing clientTime
		}
		for i, case in bad do
			local okBad, why = NetService.validateArgs("ThrowRequest", table.unpack(case))
			if okBad or why ~= "invalid" then
				error(`bad case {i} was not rejected as invalid ({tostring(why)})`)
			end
		end
		local okMany, whyMany =
			NetService.validateArgs("ThrowRequest", 3, Vector3.new(0, 0, -1), Vector3.one, 1.8e9, "extra")
		expect.falsy(okMany)
		expect.equal(whyMany, "badArgCount")
		local okNone, whyNone = NetService.validateArgs("QueueLeave", 1)
		expect.falsy(okNone)
		expect.equal(whyNone, "badArgCount")
		local okS2c, whyS2c = NetService.validateArgs("DuelState", {})
		expect.falsy(okS2c)
		expect.equal(whyS2c, "unknownRemote")
	end)

	t.test("guard: per-remote bucket drops extra calls and counts each as a violation", function()
		local guard, clock = makeGuard()
		local key = { name = "p1" }
		local burst = Config.Net.Remotes.QueueLeave.burst
		for _ = 1, burst do
			expect.equal(guard:check(key, "QueueLeave", 0), "ok")
		end
		expect.equal(guard:check(key, "QueueLeave", 0), "rateLimited")
		expect.equal(guard:violationsOf(key), 1)
		clock.advance(1 / Config.Net.Remotes.QueueLeave.rate)
		expect.equal(guard:check(key, "QueueLeave", 0), "ok")
		-- Another key has its own bucket.
		expect.equal(guard:check({ name = "p2" }, "QueueLeave", 0), "ok")
	end)

	t.test("guard: the global cap limits all remotes of one key together", function()
		local guard = makeGuard({
			rates = { QueueLeave = { rate = 1000, burst = 1000 }, ReportIdle = { rate = 1000, burst = 1000 } },
			global = { rate = 1, burst = 5 },
			abuse = { violations = 1000, windowSeconds = 60, muteSeconds = 30 },
		})
		local key = {}
		local accepted = 0
		for i = 1, 10 do
			local name = if i % 2 == 0 then "QueueLeave" else "ReportIdle"
			if guard:check(key, name, 0) == "ok" then
				accepted += 1
			end
		end
		expect.equal(accepted, 5)
	end)

	t.test("guard: wrong argument count and invalid payloads are violations; args come back narrowed", function()
		local guard = makeGuard()
		local key = {}
		local verdict = guard:check(key, "QueueLeave", 3, 1, 2, 3)
		expect.equal(verdict, "badArgCount")
		verdict = guard:check(key, "EquipSquishy", 1, KB_STRING)
		expect.equal(verdict, "invalid")
		local okVerdict, args = guard:check(key, "EquipSquishy", 1, "toast")
		expect.equal(okVerdict, "ok")
		expect.equal(args[1], "toast")
		expect.equal(guard:violationsOf(key), 2)
		local stats = guard:stats()
		expect.equal(stats.badArgCount, 1)
		expect.equal(stats.invalid, 1)
	end)

	t.test("guard: more than 20 violations in 60 s mute for 30 s; muted calls are not counted", function()
		local guard, clock, mutes = makeGuard()
		local key = {}
		local threshold = Config.Net.Abuse.violations
		for _ = 1, threshold do
			guard:check(key, "EquipSquishy", 1, NAN)
		end
		expect.falsy(guard:isMuted(key))
		guard:check(key, "EquipSquishy", 1, NAN) -- violation threshold + 1
		expect.truthy(guard:isMuted(key))
		expect.equal(#mutes, 1)
		expect.equal(mutes[1].name, "EquipSquishy")
		expect.near(mutes[1].untilTime, clock.now() + Config.Net.Abuse.muteSeconds)
		-- While muted even a valid call is dropped, and it is not a violation.
		local before = guard:violationsOf(key)
		expect.equal(guard:check(key, "EquipSquishy", 1, "toast"), "muted")
		expect.equal(guard:violationsOf(key), before)
		clock.advance(Config.Net.Abuse.muteSeconds + 0.01)
		expect.falsy(guard:isMuted(key))
		expect.equal(guard:check(key, "EquipSquishy", 1, "toast"), "ok")
	end)

	t.test("guard: violations older than the window do not add up to a mute", function()
		local guard, clock = makeGuard()
		local key = {}
		local threshold = Config.Net.Abuse.violations
		for _ = 1, threshold do
			guard:check(key, "EquipSquishy", 1, NAN)
		end
		clock.advance(Config.Net.Abuse.windowSeconds + 1)
		for _ = 1, threshold do
			guard:check(key, "EquipSquishy", 1, NAN)
		end
		expect.falsy(guard:isMuted(key))
	end)

	t.test("guard: 100x spam of one remote mutes and accepts at most the burst", function()
		local guard = makeGuard()
		local key = {}
		local accepted = 0
		for i = 1, 100 do
			if guard:check(key, "ThrowRequest", 4, i, Vector3.new(0, 0, -1), Vector3.one, 1.8e9) == "ok" then
				accepted += 1
			end
		end
		expect.equal(accepted, Config.Net.Remotes.ThrowRequest.burst)
		expect.truthy(guard:isMuted(key))
	end)

	-- Every click pays (2026-10-06): normal fast clicking is never rate-limited, counted or muted; a macro still is.
	t.test("guard: SqueezeRequest at 20 per second for a minute is never limited or muted; 30 per second is", function()
		local guard, clock, mutes = makeGuard()
		local key = { name = "clicker" }
		local rate = Config.Net.Remotes.SqueezeRequest.rate
		expect.equal(rate, 20)
		for i = 1, 60 * rate do
			local verdict = guard:check(key, "SqueezeRequest", 0)
			if verdict ~= "ok" then
				error(`request {i} at {rate}/s: {verdict}`)
			end
			clock.advance(1 / rate)
		end
		expect.equal(guard:violationsOf(key), 0)
		expect.falsy(guard:isMuted(key))
		expect.equal(#mutes, 0)
		-- A burst of the cap's 12 at once (a jittery network can bunch presses) is fine too.
		for _ = 1, Config.Squeeze.bucketCapacity do
			expect.equal(guard:check(key, "SqueezeRequest", 0), "ok")
		end
		-- A 30/s macro: once the burst (60) is used up (6 s at 10 over the rate a second), 10 rate-limit hits a
		-- second, muted a little over 2 s later.
		local macro = { name = "macro" }
		for _ = 1, 30 * 12 do
			guard:check(macro, "SqueezeRequest", 0)
			clock.advance(1 / 30)
		end
		expect.truthy(guard:isMuted(macro))
	end)

	-- Review fix (every click pays): a network stall queues an honest clicker's presses (the client sends at most 12 a
	-- second) and delivers them in one go. Up to 5 s of them (60) are no violation at all, the clicking goes on
	-- without one, and even a 6.5 s backlog (78) stays under the mute.
	t.test("guard: a 5 s backlog of 12/s clicking arriving at once is no violation and never mutes", function()
		local guard, clock, mutes = makeGuard()
		local key = { name = "laggy clicker" }
		local backlog = 5 * 12
		expect.truthy(Config.Net.Remotes.SqueezeRequest.burst >= backlog)
		expect.truthy(Config.Net.Global.burst >= backlog)
		for i = 1, backlog do
			local verdict = guard:check(key, "SqueezeRequest", 0)
			if verdict ~= "ok" then
				error(`queued request {i}: {verdict}`)
			end
		end
		-- The clicking goes on at 12 a second for a minute: still nothing.
		for i = 1, 60 * 12 do
			clock.advance(1 / 12)
			local verdict = guard:check(key, "SqueezeRequest", 0)
			if verdict ~= "ok" then
				error(`request {i} after the backlog: {verdict}`)
			end
		end
		expect.equal(guard:violationsOf(key), 0)
		expect.falsy(guard:isMuted(key))
		expect.equal(#mutes, 0)
		-- A longer stall (6.5 s, 78 at once) costs some violations but stays under the mute.
		local longer = { name = "laggier clicker" }
		for _ = 1, 78 do
			guard:check(longer, "SqueezeRequest", 0)
		end
		expect.truthy(guard:violationsOf(longer) <= Config.Net.Abuse.violations)
		expect.falsy(guard:isMuted(longer))
	end)

	t.test("guard: seq must rise per key and remote; a replay is dropped without a violation", function()
		local guard, clock = makeGuard()
		local key = {}
		local function throw(seq: any): string
			clock.advance(1)
			return (guard:check(key, "ThrowRequest", 4, seq, Vector3.new(0, 0, -1), Vector3.one, 1.8e9))
		end
		expect.equal(throw(1), "ok")
		expect.equal(throw(2), "ok")
		expect.equal(throw(2), "staleSeq")
		expect.equal(throw(1), "staleSeq")
		expect.equal(throw(5), "ok") -- gaps are fine (local drops on the client)
		expect.equal(guard:violationsOf(key), 0)
		expect.equal(guard:stats().staleSeq, 2)
		-- UltimateRequest has its own counter.
		clock.advance(1)
		expect.equal(guard:check(key, "UltimateRequest", 3, 1, Vector3.new(0, 0, -1), 1.8e9), "ok")
		-- reset() forgets the key (a player who left and came back starts over).
		guard:reset(key)
		expect.equal(throw(1), "ok")
	end)

	t.test("guard: report() counts a violation found by a service", function()
		local guard = makeGuard()
		local key = {}
		guard:report(key, "ThrowRequest")
		expect.equal(guard:violationsOf(key), 1)
		expect.equal(guard:stats().invalid, 1)
	end)

	t.test("ok() and err() build Result shapes", function()
		local ok = NetService.ok({ position = 2 })
		expect.equal(ok.ok, true)
		expect.equal(ok.data.position, 2)
		local err = NetService.err("queue.cooldown")
		expect.equal(err.ok, false)
		expect.equal(err.reason, "queue.cooldown")
		local refunded = NetService.err("shop.priceChanged", false)
		expect.equal(refunded.charged, false)
		expect.equal(NetService.Reasons.rateLimited, "net.rateLimited")
		expect.equal(NetService.Reasons.invalid, "net.invalid")
	end)
end
