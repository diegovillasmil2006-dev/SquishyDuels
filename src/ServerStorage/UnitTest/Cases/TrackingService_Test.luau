--!strict
-- TrackingService_Test: unit tests for ServerScriptService.Server.Services.TrackingService (player tracking for
-- Roblox's analytics) with a fake AnalyticsService. Server only (ServerStorage.UnitTest). Edit mode: init() is never
-- called (the signal handlers are called directly); players are plain tables.
-- Contract:
--   * a READY profile with the tutorial neither finished nor skipped sends funnel step 1 "Joined"; each tutorial step
--     sends its number (Config.Onboarding order + 1) once, forward-only; all steps done sends "Finished";
--   * finished or skipped tutorials and not-READY profiles send nothing;
--   * a skip sends "TutorialSkipped" with the lowest open step and ends the funnel;
--   * "NewPlayer10Min" 10 minutes after "Joined", only while the player is still in the game;
--   * Coins are summed per reason and direction and sent on flush (Source / Sink, last balance, "debug" never sent);
--   * "ModePlayed" once per real player of a finished duel or match (never cancelled / void, bots, test dummies);
--   * a failing analytics call never breaks the game; leaving sends the summed Coins and forgets the player, and a
--     late payment is sent one step later.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local TrackingService = t.requireServer("Services/TrackingService")
	local Config = t.requireShared("Config")

	local STEPS = Config.Onboarding.Steps
	local FIELD_1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name
	local SOURCE = Enum.AnalyticsEconomyFlowType.Source
	local SINK = Enum.AnalyticsEconomyFlowType.Sink

	-- Fresh fakes: every analytics call lands in `calls` as { method, ... }; delayed functions wait in `delayed`.
	local function setup(options: { [string]: any }?): (any, { any }, { any })
		local opts = options or {}
		local calls: { any } = {}
		local delayed: { any } = {}
		local fake: any = {}
		for _, method in { "LogOnboardingFunnelStepEvent", "LogCustomEvent", "LogEconomyEvent" } do
			fake[method] = function(_self: any, ...: any)
				if opts.fail then
					error("analytics down")
				end
				table.insert(calls, { method, ... })
			end
		end
		TrackingService.useDeps({
			analytics = fake,
			playerByUserId = function(userId: number): any
				return (opts.players or {})[userId]
			end,
			inGame = function(player: any): boolean
				return player.inGame ~= false
			end,
			delay = function(seconds: number, fn: () -> ())
				table.insert(delayed, { seconds = seconds, fn = fn })
			end,
		})
		return fake, calls, delayed
	end

	local function profile(done: { [string]: boolean }?, skipped: boolean?): any
		return { onboarding = { done = done or {}, skipped = skipped == true } }
	end

	local function allDone(): { [string]: boolean }
		local done = {}
		for _, step in STEPS do
			done[step.id] = true
		end
		return done
	end

	local function funnel(calls: { any }): { any }
		local list = {}
		for _, call in calls do
			if call[1] == "LogOnboardingFunnelStepEvent" then
				table.insert(list, { call[3], call[4] })
			end
		end
		return list
	end

	t.test("a new player sends Joined, each step once in its number, then Finished", function()
		local _, calls = setup()
		local p = { name = "new" }
		expect.equal(#STEPS, 6)
		TrackingService.onLoaded(p, profile(), "ready")
		TrackingService.onStepDone(p, STEPS[2].id)
		TrackingService.onStepDone(p, STEPS[1].id) -- older than the last sent step: not sent (Roblox back-fills it)
		TrackingService.onStepDone(p, STEPS[2].id) -- repeat: not sent
		for index = 3, #STEPS do
			TrackingService.onStepDone(p, STEPS[index].id)
		end
		expect.deepEqual(funnel(calls), {
			{ 1, "Joined" },
			{ 3, STEPS[2].id },
			{ 4, STEPS[3].id },
			{ 5, STEPS[4].id },
			{ 6, STEPS[5].id },
			{ 7, STEPS[6].id },
			{ 8, "Finished" },
		})
		expect.equal(calls[1][2], p)
		TrackingService.useDeps(nil)
	end)

	t.test("finished or skipped tutorials and profiles that are not ready send nothing", function()
		local _, calls = setup()
		local finished, skipped, offline = {}, {}, {}
		TrackingService.onLoaded(finished, profile(allDone()), "ready")
		TrackingService.onLoaded(skipped, profile(nil, true), "ready")
		TrackingService.onLoaded(offline, profile(), "offline")
		TrackingService.onLoaded({}, nil, "ready")
		for _, p in { finished, skipped, offline } do
			TrackingService.onStepDone(p, STEPS[1].id)
		end
		expect.equal(#calls, 0)
		TrackingService.useDeps(nil)
	end)

	t.test("a player half way through keeps the steps done before; only new ones are sent", function()
		local _, calls = setup()
		local p = {}
		TrackingService.onLoaded(p, profile({ [STEPS[1].id] = true, [STEPS[2].id] = true }), "ready")
		TrackingService.onStepDone(p, STEPS[3].id)
		expect.deepEqual(funnel(calls), { { 1, "Joined" }, { 4, STEPS[3].id } })
		TrackingService.useDeps(nil)
	end)

	t.test("a skip sends TutorialSkipped with the lowest open step and ends the funnel", function()
		local _, calls = setup()
		local p = {}
		TrackingService.onLoaded(p, profile(), "ready")
		TrackingService.onStepDone(p, STEPS[1].id)
		TrackingService.onStepDone(p, Config.Onboarding.skipStepId)
		TrackingService.onStepDone(p, STEPS[3].id)
		expect.equal(#calls, 3)
		expect.deepEqual(calls[3], { "LogCustomEvent", p, "TutorialSkipped", 1, { [FIELD_1] = STEPS[2].id } })
		TrackingService.useDeps(nil)
	end)

	t.test("NewPlayer10Min only for a new player still in the game after 10 minutes", function()
		local _, calls, delayed = setup()
		local stays, leaves = {}, {}
		TrackingService.onLoaded(stays, profile(), "ready")
		TrackingService.onLoaded(leaves, profile(), "ready")
		TrackingService.onLoaded({}, profile(allDone()), "ready")
		expect.equal(#delayed, 2)
		expect.equal(delayed[1].seconds, 600)
		leaves.inGame = false
		for _, item in delayed do
			item.fn()
		end
		expect.deepEqual(calls[#calls], { "LogCustomEvent", stays, "NewPlayer10Min", 1 })
		expect.equal(#calls, 3)
		TrackingService.useDeps(nil)
	end)

	t.test("Coins are summed per reason and direction and sent on flush with the last balance", function()
		local _, calls = setup()
		local p = {}
		TrackingService.onCoinsChanged(p, 105, 5, "squeeze")
		TrackingService.onCoinsChanged(p, 110, 5, "squeeze")
		TrackingService.onCoinsChanged(p, 60, -50, "box")
		TrackingService.onCoinsChanged(p, 100, 40, "pen")
		TrackingService.onCoinsChanged(p, 70, -30, "pen")
		TrackingService.onCoinsChanged(p, 170, 100, "robux")
		TrackingService.onCoinsChanged(p, 190, 20, "daily")
		TrackingService.onCoinsChanged(p, 9999, 9809, "debug")
		TrackingService.onCoinsChanged(p, 190, 0, "shop")
		expect.equal(#calls, 0)
		TrackingService.flush(p)
		local sent: { [string]: any } = {}
		for _, call in calls do
			expect.equal(call[1], "LogEconomyEvent")
			expect.equal(call[2], p)
			expect.equal(call[4], "Coins")
			expect.equal(call[6], 190)
			sent[call[8] .. "|" .. tostring(call[3])] = { call[5], call[7] }
		end
		expect.deepEqual(sent, {
			["squeeze|" .. tostring(SOURCE)] = { 10, "Gameplay" },
			["box|" .. tostring(SINK)] = { 50, "Shop" },
			["pen|" .. tostring(SOURCE)] = { 40, "Gameplay" },
			["pen|" .. tostring(SINK)] = { 30, "Shop" },
			["robux|" .. tostring(SOURCE)] = { 100, "IAP" },
			["daily|" .. tostring(SOURCE)] = { 20, "TimedReward" },
		})
		TrackingService.flush(p)
		TrackingService.flushAll()
		expect.equal(#calls, 6)
		TrackingService.useDeps(nil)
	end)

	t.test("ModePlayed once per real player of a finished duel or match", function()
		local p1, p2 = { name = "a" }, { name = "b" }
		local _, calls = setup({ players = { [1] = p1, [2] = p2 } })
		TrackingService.onDuelEnded({
			outcome = "win",
			participants = {
				{ player = p1, isTestDummy = false },
				{ player = nil, isTestDummy = false }, -- the practice bot
				{ player = p2, isTestDummy = true },
			},
		})
		TrackingService.onDuelEnded({ outcome = "cancelled", participants = { { player = p1, isTestDummy = false } } })
		TrackingService.onMatchEnded({
			outcome = "draw",
			modeId = "tdm",
			participants = { { userId = 2 }, { userId = -7 } },
		})
		TrackingService.onMatchEnded({ outcome = "void", modeId = "ffa", participants = { { userId = 1 } } })
		expect.deepEqual(calls, {
			{ "LogCustomEvent", p1, "ModePlayed", 1, { [FIELD_1] = "duel" } },
			{ "LogCustomEvent", p2, "ModePlayed", 1, { [FIELD_1] = "tdm" } },
		})
		TrackingService.useDeps(nil)
	end)

	t.test("a failing analytics call never breaks the game", function()
		setup({ fail = true, players = { [1] = {} } })
		local p = {}
		TrackingService.onLoaded(p, profile(), "ready")
		TrackingService.onStepDone(p, STEPS[1].id)
		TrackingService.onCoinsChanged(p, 10, 10, "squeeze")
		TrackingService.flush(p)
		TrackingService.onMatchEnded({ outcome = "win", modeId = "ffa", participants = { { userId = 1 } } })
		expect.truthy(true)
		TrackingService.useDeps(nil)
	end)

	t.test("leaving sends the summed Coins and forgets the player; a late payment goes one step later", function()
		local _, calls, delayed = setup()
		local p = {}
		TrackingService.onLoaded(p, profile(), "ready")
		TrackingService.onCoinsChanged(p, 10, 10, "squeeze")
		TrackingService.playerRemoving(p :: any)
		expect.equal(calls[#calls][1], "LogEconomyEvent")
		local before = #calls
		TrackingService.onCoinsChanged(p, 30, 20, "duel_win") -- DuelService pays the leaver after this hook
		delayed[#delayed].fn()
		expect.equal(#calls, before + 1)
		expect.equal(calls[#calls][8], "duel_win")
		TrackingService.onStepDone(p, STEPS[1].id)
		TrackingService.flushAll()
		expect.equal(#calls, before + 1)
		TrackingService.useDeps(nil)
	end)
end
