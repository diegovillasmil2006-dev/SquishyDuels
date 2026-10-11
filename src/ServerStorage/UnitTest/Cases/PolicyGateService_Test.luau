--!strict
-- PolicyGateService_Test: unit tests for ServerScriptService.Server.Services.PolicyGateService.
-- Server only (ServerStorage.UnitTest). Edit mode: PolicyService is a scripted fake (no real GetPolicyInfoForPlayerAsync),
-- waits are recorded and move a fake clock (never slept), spawn runs at once (or is held to test a running check),
-- players are plain tables, the state channel is a recorder. Config values are read from the test's Shared copy.
-- Contract (DESIGN §6.10, §2.8 PolicyRetry, §12 #17 #20 #21):
--   * join -> "checking" at once, one check: a boolean ArePaidRandomItemsRestricted -> eligible / restricted; errors
--     and anything else are failed attempts; Config attempts (3) waiting waitSeconds between failed attempts; then
--     "unknown"; the check stops once the player left; one check per player;
--   * fail closed: canBuyPaidRandom is true ONLY for eligible (checking, unknown, restricted and unknown players: false);
--   * the state goes only to the owner's state channel (setState), on every change;
--   * PolicyRetry: only in unknown, >= manualRetryMinSeconds since the last attempt, <= manualRetryMaxPerSession,
--     never while a check runs; it shows "checking" while it runs;
--   * debugSetState: Studio-gated, valid states only, discards a running check.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local PolicyGateService = t.requireServer("Services/PolicyGateService")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")
	local POLICY = Config.Monetization.Policy

	-- answers: a list of what each fetch returns, in order ("error" throws; a table is returned as it is).
	local function setup(answers: { any }, opts: { [string]: any }?): any
		local o: { [string]: any } = opts or {}
		local w: any = {
			clock = FakeClock.new(1000),
			answers = answers,
			fetches = 0,
			waits = {},
			sent = {},
			present = {},
			held = {},
			allowed = if o.allowed == nil then true else o.allowed,
		}
		PolicyGateService.useDeps({
			fetch = function(_player: any): any
				w.fetches += 1
				local answer = w.answers[w.fetches]
				if answer == "error" or answer == nil then
					error("HTTP 500 (fake)")
				end
				return answer
			end,
			wait = function(seconds: number)
				table.insert(w.waits, seconds)
				w.clock.advance(seconds)
				if w.onWait then
					w.onWait()
				end
			end,
			clock = w.clock.now,
			isPresent = function(player: any): boolean
				return w.present[player] == true
			end,
			setState = function(player: any, state: string)
				table.insert(w.sent, { player = player, state = state })
			end,
			spawn = function(fn: () -> ())
				if w.hold then
					table.insert(w.held, fn)
				else
					fn()
				end
			end,
			debugAllowed = function(): boolean
				return w.allowed
			end,
		})
		return w
	end

	local function join(w: any, userId: number?): any
		local player = { UserId = userId or 1 }
		w.present[player] = true
		PolicyGateService.playerAdded(player)
		return player
	end

	local function statesSent(w: any, player: any): { string }
		local list = {}
		for _, entry in w.sent do
			if entry.player == player then
				table.insert(list, entry.state)
			end
		end
		return list
	end

	t.test("join: checking at once, then eligible when ArePaidRandomItemsRestricted is false", function()
		local w = setup({ { ArePaidRandomItemsRestricted = false } })
		local p = join(w)
		expect.deepEqual(statesSent(w, p), { "checking", "eligible" })
		expect.equal(PolicyGateService.state(p), "eligible")
		expect.equal(PolicyGateService.canBuyPaidRandom(p), true)
		expect.equal(w.fetches, 1)
		expect.deepEqual(w.waits, {})
	end)

	t.test("join: restricted when ArePaidRandomItemsRestricted is true (no paid random items)", function()
		local w = setup({ { ArePaidRandomItemsRestricted = true } })
		local p = join(w)
		expect.deepEqual(statesSent(w, p), { "checking", "restricted" })
		expect.equal(PolicyGateService.canBuyPaidRandom(p), false)
	end)

	t.test("fail closed: only eligible may buy paid random items", function()
		local w = setup({})
		expect.equal(PolicyGateService.state({ UserId = 9 }), "checking") -- never joined
		expect.equal(PolicyGateService.canBuyPaidRandom({ UserId = 9 }), false)
		w.hold = true
		local p = join(w)
		expect.equal(PolicyGateService.state(p), "checking")
		expect.equal(PolicyGateService.canBuyPaidRandom(p), false)
		for _, state in { "restricted", "unknown", "checking" } do
			PolicyGateService.debugSetState(p, state)
			expect.equal(PolicyGateService.canBuyPaidRandom(p), false)
		end
		PolicyGateService.debugSetState(p, "eligible")
		expect.equal(PolicyGateService.canBuyPaidRandom(p), true)
	end)

	t.test(
		"errors and non-boolean answers are failed attempts: Config attempts with the waits between, then unknown",
		function()
			local w = setup({ "error", { ArePaidRandomItemsRestricted = "no" }, {} })
			local p = join(w)
			expect.equal(w.fetches, POLICY.attempts)
			local expectedWaits = {}
			for n = 1, POLICY.attempts - 1 do
				table.insert(expectedWaits, POLICY.waitSeconds[n])
			end
			expect.deepEqual(w.waits, expectedWaits) -- nothing is waited after the last attempt
			expect.deepEqual(statesSent(w, p), { "checking", "unknown" })
			expect.equal(PolicyGateService.canBuyPaidRandom(p), false)
		end
	)

	t.test("a later attempt that answers decides the state", function()
		local w = setup({ "error", { ArePaidRandomItemsRestricted = false } })
		local p = join(w)
		expect.equal(w.fetches, 2)
		expect.deepEqual(w.waits, { POLICY.waitSeconds[1] })
		expect.deepEqual(statesSent(w, p), { "checking", "eligible" })
	end)

	t.test("the check stops when the player leaves; one check per player", function()
		local w = setup({ "error", { ArePaidRandomItemsRestricted = false } })
		local player = { UserId = 1 }
		w.onWait = function()
			w.present[player] = nil
			PolicyGateService.playerRemoving(player)
		end
		w.present[player] = true
		PolicyGateService.playerAdded(player)
		expect.equal(w.fetches, 1)
		expect.deepEqual(statesSent(w, player), { "checking" }) -- nothing sent after the leave
		-- a second playerAdded for the same player never starts a second check
		local w2 = setup({ { ArePaidRandomItemsRestricted = false } })
		w2.hold = true
		local p2 = join(w2)
		PolicyGateService.playerAdded(p2)
		expect.equal(#w2.held, 1)
	end)

	t.test("PolicyRetry: only in unknown, spaced by manualRetryMinSeconds, capped per session", function()
		local w = setup({ "error", "error", "error" })
		local p = join(w)
		expect.equal(PolicyGateService.state(p), "unknown")
		local ok, why = PolicyGateService.retry(p)
		expect.equal(ok, false)
		expect.equal(why, "tooSoon")
		w.clock.advance(POLICY.manualRetryMinSeconds - 0.5)
		expect.equal(select(2, PolicyGateService.retry(p)), "tooSoon")
		w.clock.advance(0.5)
		local before = w.fetches
		ok = PolicyGateService.retry(p)
		expect.equal(ok, true)
		expect.equal(w.fetches, before + 1) -- one attempt per retry
		local sent = statesSent(w, p)
		expect.deepEqual({ sent[#sent - 1], sent[#sent] }, { "checking", "unknown" })
		for _ = 2, POLICY.manualRetryMaxPerSession do
			w.clock.advance(POLICY.manualRetryMinSeconds)
			expect.equal(PolicyGateService.retry(p), true)
		end
		w.clock.advance(POLICY.manualRetryMinSeconds)
		expect.equal(select(2, PolicyGateService.retry(p)), "limit")
		expect.equal(w.fetches, POLICY.attempts + POLICY.manualRetryMaxPerSession)
	end)

	t.test("PolicyRetry: refused outside unknown and while a check runs; a successful retry decides", function()
		local w = setup({ { ArePaidRandomItemsRestricted = true } })
		local p = join(w)
		expect.equal(select(2, PolicyGateService.retry(p)), "state") -- restricted
		expect.equal(select(2, PolicyGateService.retry({ UserId = 5 })), "state") -- no entry
		local w2 = setup({ "error", "error", "error", { ArePaidRandomItemsRestricted = false } })
		local q = join(w2)
		w2.clock.advance(POLICY.manualRetryMinSeconds)
		w2.hold = true
		expect.equal(PolicyGateService.retry(q), true)
		expect.equal(PolicyGateService.state(q), "checking")
		w2.clock.advance(POLICY.manualRetryMinSeconds)
		expect.equal(select(2, PolicyGateService.retry(q)), "state") -- checking now
		w2.held[1]()
		expect.equal(PolicyGateService.state(q), "eligible")
	end)

	t.test("debugSetState: Studio only, valid states only, and a running check is discarded", function()
		local w = setup({ { ArePaidRandomItemsRestricted = false } }, { allowed = false })
		w.hold = true
		local p = join(w)
		local ok, err = PolicyGateService.debugSetState(p, "restricted")
		expect.equal(ok, false)
		expect.equal(err, "Studio only")
		w.allowed = true
		expect.equal((PolicyGateService.debugSetState(p, "banana")), false)
		expect.equal((PolicyGateService.debugSetState({ UserId = 7 }, "eligible")), false)
		expect.equal((PolicyGateService.debugSetState(p, "restricted")), true)
		expect.equal(PolicyGateService.state(p), "restricted")
		w.held[1]() -- the join check finishes with "eligible" but was discarded
		expect.equal(PolicyGateService.state(p), "restricted")
		expect.deepEqual(statesSent(w, p), { "checking", "restricted" })
	end)
end
