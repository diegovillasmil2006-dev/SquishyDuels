--!strict
-- AutoClickService_Test: unit tests for ServerScriptService.Server.Services.AutoClickService (auto-clicker check,
-- 2026-10-16) with injected fakes: a fake os.time, a fake profile, recorded kicks, bans and saves; the "player" is a
-- plain table. Server only (ServerStorage.UnitTest). Edit mode: nothing real is ever kicked or banned.
-- Contract (owner 2026-10-16, "step by step"):
--   * a hold, and people clicking, are let through (nil);
--   * the 1st catch: that request gets squeeze.autoClick (the warning), then squeeze.tooFast (silent) for
--     penaltySeconds, nothing judged meanwhile; saved as profile.autoClick = {step = 1, at} with a "soon" save; no
--     kick, no ban;
--   * caught again in the same visit (after the penalty, with new proof) = kicked with Strings autoClick.kick (naming
--     the hours), saved as step 2;
--   * a rejoin within memorySeconds keeps the step: kicked before -> the next catch is a ban: Players:BanAsync with
--     UserIds, Duration = banSeconds, DisplayReason = Strings autoClick.ban, a PrivateReason with the numbers,
--     ApplyToUniverse true, ExcludeAltAccounts = banExcludeAltAccounts, ApplyDeviceBlock false; still in the server
--     after it = kicked with the ban text; warned before -> the next catch is a kick;
--   * BanningEnabled off, or BanAsync failing: no ban, the kick instead; a test account (UserId <= 0): the kick;
--   * Studio: nobody is kicked or banned (log only); the warning and the penalty still apply;
--   * a strike older than memorySeconds is forgotten (back to a warning); enabled = false lets everything through;
--   * an invalid config turns the check off at init (and stops the boot in Studio, like Config.validate);
--   * playerRemoving forgets the visit (the saved strike still counts);
--   * review fixes (2026-10-16, job autoclick): the cases above run with enforce = "full"; "log" only logs (every
--     request let through, no penalty, nothing saved, nobody kicked); "warn" makes every catch the first step (never a
--     kick or a ban); the kick text names the ban only when one can follow (autoClick.kickNoBan with bans off or a
--     test account). The machine is a steady 10 a second (the old 19 a second is the client ceiling's rhythm, never
--     judged since the fix);
--   * batch B (owner 2026-10-17): the live config enforces the steps ("full"); a ban is never forgotten, so the next
--     catch after it (even a year later) is a longer ban: 7 days, then 30 days, then 30 days again, each with
--     Strings autoClick.banLonger (naming the days) and the step in the PrivateReason; never in Studio; bans off: the
--     kick with kickNoBan.
--   * pens3 phase 13 (owner 2026-10-16: "step by step", "bans players with very high clicks per second"): the THROW
--     presses (checkThrow) go through the same ladder: people mashing, a kid held at the client's cap and a person
--     throwing once per landing are let through; a steady macro at one press a second or at 10 a second (rule B on the
--     throw window) and a flood (more than floodPresses a second) are caught: highway.autoClick once, then
--     highway.tooFast for the penalty, saved as the next step; one ladder and one pause for squeezes and throws (a
--     squeeze catch's pause refuses throws, the next catch of either is the kick); the ban's PrivateReason names the
--     throw rule.
--   * p13v3 (owner 2026-10-18: "Yes, above 20 a second"): check / checkThrow take the request's report (the seconds in
--     a row the client counted with more than 20 presses each, Shared/PressSpeed); more than 20 a second for 3 s in a
--     row is caught on the same ladder (squeeze.superFast / highway.superFast once, then the pause; a ban's
--     PrivateReason names the presses a second); exactly 20 a second, a kid's 2 s burst at 25 a second, squeezes and
--     throws at about 16 a second each at once, a request without a report, and the check switched off are let
--     through; a catch of either kind starts the other's count again (its next catch needs 3 more seconds).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local UNIX_START = 1_800_000_000
local CLOCK_START = 500.5

return function(t: Context)
	local expect = t.expect
	local AutoClickService = t.requireServer("Services/AutoClickService")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")
	local Strings = t.requireShared("Strings")

	local AUTO = Config.Net.AutoClick
	local HOURS = AUTO.banSeconds // 3600

	-- A copy of the live rules at `enforce` (default "full": the owner's steps).
	local function rulesAt(enforce: string?): any
		local copy = table.clone(AUTO)
		copy.enforce = enforce or "full"
		return copy
	end

	type World = {
		clock: any, -- os.clock (request arrival times)
		unix: any, -- os.time
		player: any,
		profile: any,
		ready: boolean, -- mutate works
		studio: boolean,
		banning: boolean,
		banOk: boolean,
		inGame: boolean,
		rules: any,
		kicks: { string },
		bans: { { [string]: any } },
		saves: { string },
	}

	local function fresh(overrides: { [string]: any }?): World
		local world: World = {
			clock = FakeClock.new(CLOCK_START),
			unix = FakeClock.new(UNIX_START),
			player = { UserId = 4242 },
			profile = { autoClick = { step = 0, at = 0 } },
			ready = true,
			studio = false,
			banning = true,
			banOk = true,
			inGame = true,
			rules = rulesAt(),
			kicks = {},
			bans = {},
			saves = {},
		}
		if overrides then
			for key, value in overrides do
				(world :: any)[key] = value
			end
		end
		AutoClickService.reset()
		AutoClickService.useDeps({
			unixNow = world.unix.now,
			isStudio = function(): boolean
				return world.studio
			end,
			profileOf = function(): any
				return world.profile
			end,
			mutate = function(_player: any, fn: (profile: any) -> any): (boolean, any)
				if not world.ready then
					return false, "data.notReady"
				end
				return true, fn(world.profile)
			end,
			requestSave = function(_player: any, reason: string)
				table.insert(world.saves, reason)
			end,
			banningEnabled = function(): boolean
				return world.banning
			end,
			ban = function(config: { [string]: any }): (boolean, string?)
				table.insert(world.bans, config)
				return world.banOk, if world.banOk then nil else "HTTP 429 (Too Many Requests)"
			end,
			kick = function(_player: any, message: string): (boolean, string?)
				table.insert(world.kicks, message)
				return true, nil
			end,
			inGame = function(): boolean
				return world.inGame
			end,
			later = function(fn: () -> ())
				fn() -- at once in tests (task.defer live)
			end,
			rules = function(): any
				return world.rules
			end,
		})
		return world
	end

	local function finish()
		AutoClickService.reset()
		AutoClickService.useDeps(nil)
	end

	local function advance(world: World, seconds: number)
		world.clock.advance(seconds)
		world.unix.advance(seconds)
	end

	-- `count` requests `gap` seconds apart; returns every answer (nil = let through) in order, as a list of strings
	-- ("ok" for nil).
	local function press(world: World, count: number, gap: number): { string }
		local answers = table.create(count)
		for i = 1, count do
			answers[i] = AutoClickService.check(world.player, world.clock.now()) or "ok"
			advance(world, gap)
		end
		return answers
	end

	local function countOf(answers: { string }, answer: string): number
		local n = 0
		for _, a in answers do
			if a == answer then
				n += 1
			end
		end
		return n
	end

	-- A machine at a steady 10 a second for `seconds` (rule B catches it at its first window, after 40 s); returns the
	-- answers.
	local function machine(world: World, seconds: number): { string }
		return press(world, math.floor(seconds * 10), 0.1)
	end

	-- A person tapping about 8 a second (gaps 95-155 ms in a fixed, uneven pattern).
	local function person(world: World, count: number): { string }
		local pattern = { 0.12, 0.095, 0.155, 0.11, 0.13, 0.1, 0.145, 0.125, 0.105, 0.14, 0.115 }
		local answers = {}
		for i = 1, count do
			table.insert(answers, AutoClickService.check(world.player, world.clock.now()) or "ok")
			advance(world, pattern[(i - 1) % #pattern + 1] + 0.003 * math.sin(i))
		end
		return answers
	end

	t.test("a hold and a person clicking are always let through", function()
		local world = fresh()
		local held = press(world, math.floor(600 / 0.45), Config.Grip.Hold.repeatSeconds) -- 10 minutes
		expect.equal(countOf(held, "ok"), #held)
		local clicked = person(world, 4000) -- about 8 minutes at 8 a second
		expect.equal(countOf(clicked, "ok"), #clicked)
		expect.deepEqual(world.profile.autoClick, { step = 0, at = 0 })
		expect.equal(#world.kicks + #world.bans + #world.saves, 0)
		finish()
	end)

	t.test("the 1st catch: one warning, a silent penalty, saved as step 1; no kick, no ban", function()
		local world = fresh()
		local answers = machine(world, 45)
		local first = table.find(answers, "squeeze.autoClick") :: number
		expect.truthy(first ~= nil)
		expect.equal(countOf(answers, "squeeze.autoClick"), 1)
		for i = first + 1, #answers do
			expect.equal(answers[i], "squeeze.tooFast") -- the 5 s after the catch are inside the 30 s penalty
		end
		expect.equal(world.profile.autoClick.step, 1)
		expect.near(world.profile.autoClick.at, UNIX_START + (first - 1) * 0.1, 1e-3) -- the fake clock adds up 0.1 s
		expect.deepEqual(world.saves, { "soon" })
		expect.equal(#world.kicks, 0)
		expect.equal(#world.bans, 0)
		finish()
	end)

	t.test("the penalty ends after penaltySeconds; switched off, a person is let through again", function()
		local world = fresh()
		machine(world, 45)
		advance(world, AUTO.penaltySeconds) -- the penalty is over
		local clicked = person(world, 1500)
		expect.equal(countOf(clicked, "ok"), #clicked)
		expect.equal(#world.kicks, 0)
		finish()
	end)

	t.test("caught again in the same visit: kicked with the kick text, saved as step 2", function()
		local world = fresh()
		machine(world, 45)
		advance(world, AUTO.penaltySeconds)
		local again = machine(world, 45)
		expect.equal(countOf(again, "squeeze.autoClick"), 1)
		expect.deepEqual(world.kicks, { Strings.format(Strings.autoClick.kick, { hours = HOURS }) })
		expect.truthy(string.find(world.kicks[1], tostring(HOURS), 1, true) ~= nil)
		expect.equal(world.profile.autoClick.step, 2)
		expect.equal(#world.bans, 0)
		finish()
	end)

	t.test("kicked, rejoined within a day: the next catch is a 1-day ban, then a kick with the ban text", function()
		local world = fresh({ profile = { autoClick = { step = 2, at = UNIX_START - 3600 } } })
		machine(world, 45)
		expect.equal(#world.bans, 1)
		local ban = world.bans[1]
		expect.deepEqual(ban.UserIds, { 4242 })
		expect.equal(ban.Duration, AUTO.banSeconds)
		expect.equal(ban.Duration, 86400)
		expect.equal(ban.ApplyToUniverse, true)
		expect.equal(ban.ExcludeAltAccounts, AUTO.banExcludeAltAccounts)
		expect.equal(ban.ApplyDeviceBlock, false)
		local display = Strings.format(Strings.autoClick.ban, { hours = HOURS })
		expect.equal(ban.DisplayReason, display)
		expect.truthy(#ban.DisplayReason <= 400)
		expect.truthy(#ban.PrivateReason <= 1000)
		expect.truthy(string.find(ban.PrivateReason, "strike 3", 1, true) ~= nil)
		expect.truthy(string.find(ban.PrivateReason, "machine-regular", 1, true) ~= nil) -- the rule and its numbers
		expect.deepEqual(world.kicks, { display }) -- still in the server after the ban
		expect.equal(world.profile.autoClick.step, 3)
		finish()
	end)

	t.test("warned, rejoined within a day: the next catch is a kick, not a second warning", function()
		local world = fresh({ profile = { autoClick = { step = 1, at = UNIX_START - 60 } } })
		machine(world, 45)
		expect.equal(#world.kicks, 1)
		expect.equal(#world.bans, 0)
		expect.equal(world.profile.autoClick.step, 2)
		finish()
	end)

	t.test("a strike older than memorySeconds is forgotten: back to a warning", function()
		local world = fresh({ profile = { autoClick = { step = 2, at = UNIX_START - AUTO.memorySeconds } } })
		machine(world, 45)
		expect.equal(world.profile.autoClick.step, 1)
		expect.equal(#world.kicks + #world.bans, 0)
		finish()
	end)

	t.test("BanningEnabled off: no ban, the kick instead; BanAsync failing: the kick too", function()
		local remembered = { autoClick = { step = 2, at = UNIX_START - 60 } }
		local world = fresh({ profile = table.clone(remembered), banning = false })
		machine(world, 45)
		expect.equal(#world.bans, 0)
		expect.deepEqual(world.kicks, { Strings.autoClick.kickNoBan }) -- no ban can follow: the text promises none
		finish()
		local failing = fresh({ profile = table.clone(remembered), banOk = false })
		machine(failing, 45)
		expect.equal(#failing.bans, 1) -- tried
		expect.deepEqual(failing.kicks, { Strings.format(Strings.autoClick.kick, { hours = HOURS }) })
		finish()
	end)

	t.test(
		"a banned player who already left is not kicked again; a test account (UserId <= 0) is only kicked",
		function()
			local gone = fresh({ profile = { autoClick = { step = 2, at = UNIX_START - 60 } }, inGame = false })
			machine(gone, 45)
			expect.equal(#gone.bans, 1)
			expect.equal(#gone.kicks, 0)
			finish()
			local test =
				fresh({ profile = { autoClick = { step = 2, at = UNIX_START - 60 } }, player = { UserId = -1 } })
			machine(test, 45)
			expect.equal(#test.bans, 0)
			expect.deepEqual(test.kicks, { Strings.autoClick.kickNoBan })
			finish()
		end
	)

	t.test("Studio: nobody is kicked or banned; the warning and the penalty still apply", function()
		local world = fresh({ studio = true, profile = { autoClick = { step = 2, at = UNIX_START - 60 } } })
		local answers = machine(world, 45)
		expect.equal(countOf(answers, "squeeze.autoClick"), 1)
		expect.truthy(countOf(answers, "squeeze.tooFast") > 0)
		expect.equal(#world.bans, 0)
		expect.equal(#world.kicks, 0)
		expect.equal(world.profile.autoClick.step, 3) -- the strike itself still counts (Studio's store is a test one)
		finish()
	end)

	t.test("a profile that is not ready: the strike still counts in the visit, nothing is saved", function()
		local world = fresh({ ready = false })
		machine(world, 45)
		advance(world, AUTO.penaltySeconds)
		machine(world, 45)
		expect.equal(#world.kicks, 1) -- the visit's own step 1 -> 2
		expect.deepEqual(world.profile.autoClick, { step = 0, at = 0 })
		expect.deepEqual(world.saves, {})
		finish()
	end)

	t.test("enabled = false lets everything through", function()
		local rules = rulesAt()
		rules.enabled = false
		local world = fresh({ rules = rules })
		local answers = machine(world, 60)
		expect.equal(countOf(answers, "ok"), #answers)
		expect.equal(#world.saves, 0)
		finish()
	end)

	t.test("an invalid config turns the check off at init (the boot stops in Studio)", function()
		local rules = rulesAt()
		rules.maxPerSecond = 1 -- under the paid-squeeze cap: invalid
		local world = fresh({ rules = rules })
		if Config.Debug.failOnInvalidConfig then
			expect.throws(function()
				AutoClickService.init()
			end, "Config invalid")
		else
			AutoClickService.init()
		end
		local answers = machine(world, 60)
		expect.equal(countOf(answers, "ok"), #answers) -- never punishes on a broken config
		finish()
		-- The live config passes init.
		fresh()
		AutoClickService.init()
		finish()
	end)

	t.test("playerRemoving forgets the visit; the saved strike still counts at the next catch", function()
		local world = fresh()
		machine(world, 45) -- step 1, saved
		AutoClickService.playerRemoving(world.player)
		local answers = machine(world, 45) -- a new visit: no penalty carried over
		expect.equal(countOf(answers, "squeeze.autoClick"), 1)
		expect.equal(#world.kicks, 1) -- warned within a day -> kicked
		finish()
	end)

	-- Review fixes (2026-10-16, job autoclick) ------------------------------------------------------------------------

	t.test(
		"enforce = log: a catch is only logged; every request goes on, no penalty, nothing saved, nobody kicked",
		function()
			local world =
				fresh({ rules = rulesAt("log"), profile = { autoClick = { step = 2, at = UNIX_START - 60 } } })
			local answers = machine(world, 45)
			expect.equal(countOf(answers, "ok"), #answers) -- the catch at 40 s too: no warning, no penalty
			advance(world, 1)
			local again = machine(world, 45) -- a second catch in the same visit
			expect.equal(countOf(again, "ok"), #again)
			expect.deepEqual(world.profile.autoClick, { step = 2, at = UNIX_START - 60 }) -- the saved strike is untouched
			expect.equal(#world.saves + #world.kicks + #world.bans, 0)
			finish()
		end
	)

	t.test("enforce = warn: every catch is the first step, never a kick or a ban; saved as step 1", function()
		local world = fresh({ rules = rulesAt("warn"), profile = { autoClick = { step = 2, at = UNIX_START - 60 } } })
		local answers = machine(world, 45)
		expect.equal(countOf(answers, "squeeze.autoClick"), 1)
		expect.truthy(countOf(answers, "squeeze.tooFast") > 0) -- the penalty
		advance(world, AUTO.penaltySeconds)
		local again = machine(world, 45)
		expect.equal(countOf(again, "squeeze.autoClick"), 1) -- warned again, not kicked
		expect.equal(#world.kicks + #world.bans, 0)
		expect.equal(world.profile.autoClick.step, 1)
		finish()
	end)

	-- Batch B (owner 2026-10-17) ---------------------------------------------------------------------------------------

	t.test("the live config enforces the steps: warn, kick, ban (enforce = full)", function()
		expect.equal(AUTO.enforce, "full")
	end)

	t.test("after a ban ends, the next catch is a longer ban: 7 days, then 30 days, then 30 days again", function()
		local YEAR = 365 * 86400
		local expected = { { 3, 604800, 4 }, { 4, 2592000, 5 }, { 5, 2592000, 5 } } -- saved step, ban, new step
		for _, case in expected do
			local saved, seconds, step = case[1], case[2], case[3]
			local world = fresh({ profile = { autoClick = { step = saved, at = UNIX_START - YEAR } } })
			local answers = machine(world, 45)
			expect.equal(countOf(answers, "squeeze.autoClick"), 1)
			expect.equal(#world.bans, 1)
			local ban = world.bans[1]
			expect.equal(ban.Duration, seconds)
			expect.equal(ban.ApplyToUniverse, true)
			expect.equal(ban.ApplyDeviceBlock, false)
			local display = Strings.format(Strings.autoClick.banLonger, { days = seconds // 86400 })
			expect.equal(ban.DisplayReason, display)
			expect.truthy(string.find(display, tostring(seconds // 86400), 1, true) ~= nil)
			expect.truthy(#ban.DisplayReason <= 400)
			expect.truthy(string.find(ban.PrivateReason, `strike {step}`, 1, true) ~= nil)
			expect.deepEqual(world.kicks, { display }) -- still in the server after the ban
			expect.equal(world.profile.autoClick.step, step)
			finish()
		end
		-- A 1-day ban that ended a day ago, then the same in Studio (never banned) and with bans off (the kick).
		local ended = fresh({ profile = { autoClick = { step = 3, at = UNIX_START - AUTO.memorySeconds - 60 } } })
		machine(ended, 45)
		expect.equal(ended.bans[1].Duration, 604800)
		finish()
		local studio = fresh({ studio = true, profile = { autoClick = { step = 3, at = UNIX_START - YEAR } } })
		machine(studio, 45)
		expect.equal(#studio.bans + #studio.kicks, 0)
		expect.equal(studio.profile.autoClick.step, 4)
		finish()
		local off = fresh({ banning = false, profile = { autoClick = { step = 4, at = UNIX_START - YEAR } } })
		machine(off, 45)
		expect.equal(#off.bans, 0)
		expect.deepEqual(off.kicks, { Strings.autoClick.kickNoBan })
		finish()
	end)

	-- Pens3 phase 13: the THROW presses ---------------------------------------------------------------------------

	local THROW = Config.Economy.Highway.autoClick

	-- `count` throw presses `gap` seconds apart (each a list of gaps used in turn); the answers ("ok" for nil).
	local function throwPress(world: World, count: number, gaps: { number }): { string }
		local answers = table.create(count)
		for i = 1, count do
			answers[i] = AutoClickService.checkThrow(world.player, world.clock.now()) or "ok"
			advance(world, gaps[(i - 1) % #gaps + 1])
		end
		return answers
	end

	t.test(
		"pens3 phase 13: throw presses: people mashing, the client's cap and one per landing are let through",
		function()
			local world = fresh()
			local mash = { 0.12, 0.095, 0.155, 0.11, 0.13, 0.1, 0.145, 0.125, 0.105, 0.14, 0.115 }
			local mashed = throwPress(world, 3000, mash) -- about 6 minutes at 8 a second
			expect.equal(countOf(mashed, "ok"), #mashed)
			-- A faster kid, held at the client's cap.
			local held = throwPress(world, 3000, { 1 / THROW.clientPressesPerSecond })
			expect.equal(countOf(held, "ok"), #held)
			local landings = throwPress(world, 600, { 2.6, 3.1, 2.4, 3.7, 2.9, 2.5, 4.2, 2.7 }) -- 30 minutes of throws
			expect.equal(countOf(landings, "ok"), #landings)
			expect.deepEqual(world.profile.autoClick, { step = 0, at = 0 })
			expect.equal(#world.kicks + #world.bans + #world.saves, 0)
			finish()
		end
	)

	t.test("pens3 phase 13: a steady throw macro (1 a second) is caught: one warning, a pause, step 1", function()
		local world = fresh()
		local answers = throwPress(world, THROW.windowIntervals + 20, { 1 })
		local first = table.find(answers, "highway.autoClick") :: number
		expect.equal(first, THROW.windowIntervals + 1) -- its first full window
		expect.equal(countOf(answers, "highway.autoClick"), 1)
		for i = first + 1, #answers do
			expect.equal(answers[i], "highway.tooFast") -- 19 s of the 30 s pause
		end
		expect.equal(world.profile.autoClick.step, 1)
		expect.deepEqual(world.saves, { "soon" })
		expect.equal(#world.kicks + #world.bans, 0)
		finish()
	end)

	-- Verification fix: the usual auto-clicker default (100 ms) is slower than the client's cap, so rule B judges it.
	t.test(
		"pens3 phase 13: a steady throw clicker at 10 a second (the usual auto-clicker default) is caught",
		function()
			local world = fresh()
			local answers = throwPress(world, THROW.windowIntervals + 5, { 0.1 })
			expect.equal(table.find(answers, "highway.autoClick"), THROW.windowIntervals + 1) -- its first full window
			expect.equal(world.profile.autoClick.step, 1)
			finish()
		end
	)

	t.test("pens3 phase 13: a flood (more than floodPresses in a second) is caught at once", function()
		local world = fresh({ profile = { autoClick = { step = 2, at = UNIX_START - 60 } } }) -- kicked a minute ago
		local answers = throwPress(world, THROW.floodPresses + 5, { 0.01 })
		expect.equal(answers[THROW.floodPresses + 1], "highway.autoClick")
		expect.equal(countOf(answers, "ok"), THROW.floodPresses)
		expect.equal(#world.bans, 1) -- the 3rd step: the 1-day ban
		expect.truthy(string.find(world.bans[1].PrivateReason, "flood", 1, true) ~= nil)
		expect.equal(world.profile.autoClick.step, 3)
		finish()
	end)

	t.test("pens3 phase 13: one ladder and one pause for squeezes and throws", function()
		local world = fresh()
		machine(world, 45) -- a squeeze catch: step 1 and its pause
		expect.equal(world.profile.autoClick.step, 1)
		expect.equal(AutoClickService.checkThrow(world.player, world.clock.now()), "highway.tooFast")
		advance(world, AUTO.penaltySeconds)
		throwPress(world, THROW.windowIntervals + 1, { 1 }) -- then a throw macro: the 2nd step, a kick
		expect.equal(world.profile.autoClick.step, 2)
		expect.deepEqual(world.kicks, { Strings.format(Strings.autoClick.kick, { hours = HOURS }) })
		expect.equal(AutoClickService.check(world.player, world.clock.now()), "squeeze.tooFast") -- the throw's pause
		finish()
	end)

	t.test("pens3 phase 13: enabled = false lets every throw press through", function()
		local rules = rulesAt()
		rules.enabled = false
		local world = fresh({ rules = rules })
		local answers = throwPress(world, THROW.floodPresses * 2, { 0.01 })
		expect.equal(countOf(answers, "ok"), #answers)
		finish()
	end)

	t.test("the same-visit kick names the ban only when one can follow (bans off: kickNoBan)", function()
		local world = fresh({ banning = false })
		machine(world, 45)
		advance(world, AUTO.penaltySeconds)
		machine(world, 45)
		expect.deepEqual(world.kicks, { Strings.autoClick.kickNoBan })
		expect.equal(string.find(Strings.autoClick.kickNoBan, "hours", 1, true), nil)
		finish()
	end)

	-- P13v3 (owner 2026-10-18: "Yes, above 20 a second"): the speed rule on the clients' reports ---------------------

	local PressSpeed = t.requireShared("PressSpeed")

	-- `seconds` of a client pressing `perSecond` times a second (evenly, on the test's clock) and sending every
	-- (perSecond // sends)-th press with its PressSpeed report (kind "squeeze": check, "throw": checkThrow); the
	-- answers ("ok" for nil).
	local function counted(world: World, kind: string, seconds: number, sends: number, perSecond: number): { string }
		local client = PressSpeed.new()
		local every = perSecond // sends
		local answers = {}
		for i = 1, math.floor(seconds * perSecond) do
			local now = world.clock.now()
			PressSpeed.press(client, now)
			if i % every == 0 then
				local answer = if kind == "squeeze"
					then AutoClickService.check(world.player, now, client.peak)
					else AutoClickService.checkThrow(world.player, now, client.peak)
				PressSpeed.sent(client)
				table.insert(answers, answer or "ok")
			end
			advance(world, 1 / perSecond)
		end
		return answers
	end

	t.test("p13v3: squeezes above 20 a second for 3 s: squeeze.superFast once, the pause, step 1", function()
		local world = fresh()
		-- A 36-a-second auto-clicker through the client's 18 sends a second.
		local answers = counted(world, "squeeze", 10, AUTO.clientPressesPerSecond, 36)
		local first = table.find(answers, "squeeze.superFast") :: number
		expect.truthy(first ~= nil)
		expect.truthy(first <= 4 * AUTO.clientPressesPerSecond) -- inside the first 4 s (the clock starts mid-second)
		expect.equal(countOf(answers, "squeeze.superFast"), 1)
		expect.equal(countOf(answers, "ok"), first - 1)
		for i = first + 1, #answers do
			expect.equal(answers[i], "squeeze.tooFast") -- the rest of the 10 s is inside the 30 s pause
		end
		expect.equal(world.profile.autoClick.step, 1)
		expect.deepEqual(world.saves, { "soon" })
		expect.equal(#world.kicks + #world.bans, 0)
		finish()
	end)

	t.test("p13v3: throw presses above 20 a second for 3 s: highway.superFast; the ban names the speed", function()
		local world = fresh({ profile = { autoClick = { step = 2, at = UNIX_START - 60 } } }) -- kicked a minute ago
		local answers = counted(world, "throw", 10, THROW.clientPressesPerSecond, 36)
		local first = table.find(answers, "highway.superFast") :: number
		expect.truthy(first ~= nil and first <= 4 * THROW.clientPressesPerSecond)
		expect.equal(answers[first + 1], "highway.tooFast")
		expect.equal(world.profile.autoClick.step, 3)
		expect.equal(#world.bans, 1) -- the 3rd step: the 1-day ban
		expect.truthy(string.find(world.bans[1].PrivateReason, "presses a second", 1, true) ~= nil)
		finish()
	end)

	t.test("p13v3: at most 20 a second, a 2 s burst, or squeezes and throws at once are let through", function()
		local world = fresh()
		local exact = counted(world, "squeeze", 120, 20, 20) -- exactly 20 a second for 2 minutes
		expect.equal(countOf(exact, "ok"), #exact)
		advance(world, 5)
		local burst = counted(world, "throw", 2, 25, 25) -- a kid's 25 a second (F + E + a click), for 2 s
		expect.equal(countOf(burst, "ok"), #burst)
		advance(world, 5)
		-- A kid mashing F (squeezes) and clicking on the deck (throws), about 16 a second each for 2 minutes: 32 a
		-- second in all, but each client counts its own presses.
		local squeezes, throws = PressSpeed.new(), PressSpeed.new()
		local pattern = { 0.12, 0.095, 0.155, 0.11, 0.13, 0.1, 0.145, 0.125, 0.105, 0.14, 0.115 }
		for i = 1, 1000 do
			local now = world.clock.now()
			PressSpeed.press(squeezes, now)
			PressSpeed.press(squeezes, now + 0.05)
			PressSpeed.press(throws, now + 0.01)
			PressSpeed.press(throws, now + 0.06)
			expect.equal(AutoClickService.check(world.player, now, squeezes.peak), nil)
			expect.equal(AutoClickService.checkThrow(world.player, now + 0.01, throws.peak), nil)
			advance(world, pattern[(i - 1) % #pattern + 1] + 0.003 * math.sin(i))
		end
		advance(world, 5)
		-- A request without a report (an older caller) or a broken one counts as none.
		for _, broken in { 0 / 0, "9", -5 } :: { any } do
			expect.equal(AutoClickService.check(world.player, world.clock.now(), broken), nil)
		end
		expect.deepEqual(world.profile.autoClick, { step = 0, at = 0 })
		expect.equal(#world.kicks + #world.bans + #world.saves, 0)
		finish()
	end)

	t.test("p13v3: a catch of either kind starts the other's speed count again (3 more seconds in a row)", function()
		for _, first in { "squeeze", "throw" } do
			local world = fresh()
			local function report(kind: string, n: number): string?
				local now = world.clock.now()
				return if kind == "squeeze"
					then AutoClickService.check(world.player, now, n)
					else AutoClickService.checkThrow(world.player, now, n)
			end
			local other = if first == "squeeze" then "throw" else "squeeze"
			local refusal = if other == "squeeze" then "squeeze.superFast" else "highway.superFast"
			expect.equal(report(other, 2), nil) -- 2 seconds over the line so far
			expect.truthy(report(first, 3) ~= nil) -- a catch of the other kind: the warning and the pause
			advance(world, AUTO.penaltySeconds + 1)
			expect.equal(report(other, 3), nil) -- not 3 new seconds yet
			expect.equal(report(other, 4), nil)
			expect.equal(report(other, 5), refusal) -- the next step: the kick
			expect.equal(#world.kicks, 1)
			finish()
		end
	end)

	t.test("p13v3: the speed rule is off with the check (enabled = false)", function()
		local rules = rulesAt()
		rules.enabled = false
		local world = fresh({ rules = rules })
		local answers = counted(world, "squeeze", 10, AUTO.clientPressesPerSecond, 36)
		expect.equal(countOf(answers, "ok"), #answers)
		finish()
	end)
end
