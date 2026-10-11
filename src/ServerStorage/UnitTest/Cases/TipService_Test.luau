--!strict
-- TipService_Test: unit tests for ServerScriptService.Server.Services.TipService (the pure step() and the DuelService
-- tip hook with injected fakes). Server only (ServerStorage.UnitTest). Edit mode: init() is never called (the hook is
-- called directly); players are plain tables.
-- Contract (DESIGN §6.13, §2.8 DuelResult.tip):
--   * 3 consecutive completed losses (>= 3 own throws) give "duel.lossTip" once and reset the count;
--   * a win resets the count; a draw leaves it; cancelled and void never count; a forfeit / bail loss
--     ("opponentLeft") and a loss with too few own throws never count;
--   * at most 2 tips per session, at least 20 minutes apart; settings.showTips off never shows one (the count keeps,
--     so the tip can show after a later loss once tips are on again);
--   * the hook keeps one session state per player (debugState) and forgets it on leave, also when the leaver's match
--     ends (and asks the hook) after the leave hook ran (the deferred second clear).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local TipService = t.requireServer("Services/TipService")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")

	local CFG = Config.Economy.LossTip
	local KEY = CFG.textKey

	local function fresh(): any
		return { lossStreak = 0, shown = 0, lastTipAt = nil }
	end

	local function loss(throws: number?, showTips: boolean?): any
		return {
			outcome = "loss",
			reason = "eliminated",
			throws = throws or CFG.minOwnThrows,
			showTips = if showTips == nil then true else showTips,
		}
	end

	local function result(outcome: string, reason: string?): any
		return { outcome = outcome, reason = reason or "timeUp", throws = 10, showTips = true }
	end

	-- Feeds results in order at time `now`; returns (state, tips shown as a list of keys / false).
	local function feed(state: any, results: { any }, now: number): (any, { any })
		local tips: { any } = {}
		local s = state
		for _, r in results do
			local tip
			s, tip = TipService.step(s, r, now)
			table.insert(tips, tip or false)
		end
		return s, tips
	end

	t.test("three completed losses show the tip once and reset the count", function()
		expect.equal(KEY, "duel.lossTip")
		expect.equal(CFG.lossStreak, 3)
		local s, tips = feed(fresh(), { loss(), loss(), loss() }, 100)
		expect.deepEqual(tips, { false, false, KEY })
		expect.equal(s.lossStreak, 0)
		expect.equal(s.shown, 1)
		expect.equal(s.lastTipAt, 100)
	end)

	t.test("step never changes the state it is given", function()
		local before = fresh()
		local after = TipService.step(before, loss(), 5)
		expect.equal(before.lossStreak, 0)
		expect.equal(after.lossStreak, 1)
	end)

	t.test("a win resets the count; a draw leaves it; cancelled and void never count", function()
		local s = feed(fresh(), { loss(), loss(), result("win") }, 0)
		expect.equal(s.lossStreak, 0)
		local s2, tips = feed(fresh(), {
			loss(),
			result("draw", "suddenDeathTimeout"),
			result("cancelled", "forfeit"),
			result("void", "shutdown"),
			loss(),
		}, 0)
		expect.equal(s2.lossStreak, 2)
		expect.deepEqual(tips, { false, false, false, false, false })
		local _, last = TipService.step(s2, loss(), 0)
		expect.equal(last, KEY)
	end)

	t.test("a forfeit / bail loss and a loss with too few own throws never count", function()
		local bail = { outcome = "loss", reason = "opponentLeft", throws = 12, showTips = true }
		local s, tips = feed(fresh(), { loss(), loss(), bail, loss(CFG.minOwnThrows - 1), loss(0) }, 0)
		expect.equal(s.lossStreak, 2)
		expect.deepEqual(tips, { false, false, false, false, false })
		-- An out-of-bounds elimination is a completed loss (not a bail).
		local oob = { outcome = "loss", reason = "outOfBounds", throws = CFG.minOwnThrows, showTips = true }
		local _, tip = TipService.step(s, oob, 0)
		expect.equal(tip, KEY)
	end)

	t.test("at most maxPerSession tips, at least minSecondsBetween apart", function()
		expect.equal(CFG.maxPerSession, 2)
		expect.equal(CFG.minSecondsBetween, 1200)
		local s, first = feed(fresh(), { loss(), loss(), loss() }, 1000)
		expect.equal(first[3], KEY)
		-- 3 more losses 10 minutes later: too soon; the count keeps growing.
		local s2, early = feed(s, { loss(), loss(), loss() }, 1000 + 600)
		expect.deepEqual(early, { false, false, false })
		expect.equal(s2.lossStreak, 3)
		-- Exactly 20 minutes after the first tip: the next counted loss shows it.
		local s3, onTime = TipService.step(s2, loss(), 1000 + CFG.minSecondsBetween)
		expect.equal(onTime, KEY)
		expect.equal(s3.shown, 2)
		-- A third tip never shows this session.
		local _, never = feed(s3, { loss(), loss(), loss(), loss(), loss() }, 1000 + 10 * CFG.minSecondsBetween)
		expect.deepEqual(never, { false, false, false, false, false })
	end)

	t.test("settings.showTips off never shows the tip; the count keeps for later", function()
		local s, tips = feed(fresh(), { loss(nil, false), loss(nil, false), loss(nil, false), loss(nil, false) }, 0)
		expect.deepEqual(tips, { false, false, false, false })
		expect.equal(s.lossStreak, 4)
		expect.equal(s.shown, 0)
		local _, tip = TipService.step(s, loss(nil, true), 0)
		expect.equal(tip, KEY)
	end)

	t.test("the DuelService hook keeps a session state per player and forgets it on leave", function()
		local clock = FakeClock.new(50)
		local showTips = true
		TipService.useDeps({
			clock = clock.now,
			showTips = function(_player: any): boolean
				return showTips
			end,
		})
		local alice, bob = { UserId = 1 }, { UserId = 2 }
		local function summary(userId: number, outcome: string, throws: number): any
			return { userId = userId, outcome = outcome, throws = throws, isTestDummy = false }
		end
		local info = { matchId = "m1", outcome = "win", reason = "eliminated", activeSeconds = 70 }
		expect.equal(TipService.onResult(alice, summary(1, "loss", 5), info), nil)
		expect.equal(TipService.onResult(bob, summary(2, "win", 5), info), nil)
		expect.equal(TipService.onResult(alice, summary(1, "loss", 5), info), nil)
		expect.equal(TipService.debugState(alice).lossStreak, 2)
		expect.equal(TipService.debugState(bob).lossStreak, 0)
		expect.equal(TipService.onResult(alice, summary(1, "loss", 5), info), KEY)
		expect.equal(TipService.debugState(alice).shown, 1)
		expect.equal(TipService.debugState(alice).lastTipAt, 50)
		TipService.playerRemoving(alice :: any)
		expect.deepEqual(TipService.debugState(alice), { lossStreak = 0, shown = 0 })
		TipService.useDeps(nil)
	end)

	t.test("a result for a leaver that arrives after its leave hook is forgotten one step later", function()
		-- The bootstrap runs playerRemoving in reverse layer order: TipService's hook runs first, then
		-- DuelService.playerRemoving ends the leaver's match at once and asks the tip hook for the leaver too.
		local deferred: { () -> () } = {}
		TipService.useDeps({
			clock = FakeClock.new(10).now,
			showTips = function(_player: any): boolean
				return true
			end,
			defer = function(fn: () -> ())
				table.insert(deferred, fn)
			end,
		})
		local carol = { UserId = 3 }
		local info = { matchId = "m2", outcome = "win", reason = "eliminated", activeSeconds = 60 }
		local completedLoss = { userId = 3, outcome = "loss", throws = CFG.minOwnThrows, isTestDummy = false }
		TipService.onResult(carol, completedLoss, info)
		TipService.playerRemoving(carol :: any)
		expect.deepEqual(TipService.debugState(carol), { lossStreak = 0, shown = 0 })
		-- The match ends during DuelService's leave hook: the late answer stores an entry again ...
		TipService.onResult(carol, completedLoss, info)
		expect.equal(TipService.debugState(carol).lossStreak, 1)
		-- ... which the deferred clear removes (no entry kept for a Player who left).
		expect.equal(#deferred, 1)
		for _, fn in deferred do
			fn()
		end
		expect.deepEqual(TipService.debugState(carol), { lossStreak = 0, shown = 0 })
		TipService.useDeps(nil)
	end)
end
