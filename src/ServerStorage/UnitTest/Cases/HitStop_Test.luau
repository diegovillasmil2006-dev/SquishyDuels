--!strict
-- HitStop_Test: unit tests for StarterPlayerScripts.Client.Anim.HitStop (clock math only; a private stopper on a
-- FakeClock, so the client's shared one is never touched).
-- Contract (DESIGN §18.4.4, Config.Vfx.HitStop):
--   * elapsed(start, now) = now - start minus every hold that overlaps [start, now];
--   * holds merge and never stack; at most maxPerWindow (0.12 s) of hold per windowSeconds (0.5 s);
--   * deduplicated by key (projId): every asker with that key gets the first answer;
--   * nothing holds under ReducedMotion;
--   * after(fn) runs fn once, in order, when the hold ends (runDue); clear() drops the pending ones;
--   * only the local victim of a "player" impact or the local thrower gets a hold (hit 0.06, elimination 0.10,
--     practice target 0.04 for the thrower); never for geometry, expired or fizzle, never for spectators.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local TOLERANCE = 1e-9

return function(t: Context)
	local HitStop = t.requireClient("Anim/HitStop")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")
	local expect = t.expect
	local cfg = Config.Vfx.HitStop

	local function newStopper(start: number?): (any, any)
		local clock = FakeClock.new(start or 100)
		return HitStop.new(clock.now), clock
	end

	t.test("the hit-stop values are DESIGN's and fit the window", function()
		expect.equal(cfg.playerHit, 0.06)
		expect.equal(cfg.elimination, 0.10)
		expect.equal(cfg.practiceTarget, 0.04)
		expect.equal(cfg.maxPerWindow, 0.12)
		expect.equal(cfg.windowSeconds, 0.5)
		for _, seconds in { cfg.playerHit, cfg.elimination, cfg.practiceTarget } do
			expect.truthy(seconds <= cfg.maxPerWindow)
		end
		expect.truthy(cfg.maxPerWindow <= cfg.windowSeconds)
	end)

	t.test("elapsed with no holds is now - start", function()
		local stopper = newStopper()
		expect.near(stopper:elapsed(100, 100.25), 0.25, TOLERANCE)
		expect.near(stopper:elapsed(100, 99), 0, TOLERANCE) -- never below 0
	end)

	t.test("one 0.06 hold after the start subtracts 0.06", function()
		local stopper = newStopper()
		local start = stopper:trigger(1, 0.06, 100.1)
		expect.equal(start, 100.1)
		expect.near(stopper:elapsed(100, 100.5), 0.5 - 0.06, 1e-9)
		-- Inside the hold the clock stands still.
		expect.near(stopper:elapsed(100.1, 100.13), 0, 1e-9)
		expect.near(stopper:elapsed(100.1, 100.16), 0, 1e-9)
		expect.near(stopper:elapsed(100.1, 100.2), 0.04, 1e-9)
		-- A start after the hold is not affected.
		expect.near(stopper:elapsed(100.3, 100.4), 0.1, 1e-9)
	end)

	t.test("overlapping holds merge and never stack", function()
		local stopper = newStopper()
		stopper:trigger(1, 0.06, 100)
		stopper:trigger(2, 0.06, 100.03) -- inside the first: the hold now ends at 100.09, not 100.12
		expect.near(stopper:holdEndsAt(), 100.09, 1e-9)
		expect.near(stopper:elapsed(100, 100.2), 0.2 - 0.09, 1e-9)
		-- A shorter one inside the running hold changes nothing.
		stopper:trigger(3, 0.02, 100.04)
		expect.near(stopper:holdEndsAt(), 100.09, 1e-9)
	end)

	t.test("at most 0.12 s of hold in any 0.5 s window", function()
		local stopper = newStopper()
		expect.equal(stopper:trigger(1, 0.10, 100), 100)
		local second = stopper:trigger(2, 0.10, 100.2) -- only 0.02 of room is left
		expect.equal(second, 100.2)
		expect.near(stopper:holdEndsAt(), 100.22, 1e-9)
		-- The window is full: no hold at all.
		expect.equal(stopper:trigger(3, 0.06, 100.3), nil)
		-- Once the first hold leaves the window there is room again.
		expect.equal(stopper:trigger(4, 0.06, 100.61), 100.61)
		-- A single hold never exceeds the cap.
		local fresh = newStopper()
		fresh:trigger(nil, 5, 100)
		expect.near(fresh:holdEndsAt(), 100 + cfg.maxPerWindow, 1e-9)
	end)

	t.test("deduplicated by projId: the second asker gets the first answer", function()
		local stopper = newStopper()
		local first = stopper:trigger(42, 0.06, 100)
		local second = stopper:trigger(42, 0.06, 100.001)
		expect.equal(first, 100)
		expect.equal(second, 100)
		expect.near(stopper:holdEndsAt(), 100.06, 1e-9)
		-- A refused key stays refused for both askers.
		local full = newStopper()
		full:trigger(1, 0.12, 100)
		expect.equal(full:trigger(7, 0.06, 100.2), nil)
		expect.equal(full:trigger(7, 0.06, 100.21), nil)
	end)

	t.test("nothing holds under ReducedMotion (or for a bad length)", function()
		local stopper = newStopper()
		expect.equal(stopper:trigger(1, 0.06, 100, true), nil)
		expect.equal(stopper:trigger(2, 0, 100), nil)
		expect.equal(stopper:trigger(3, -1, 100), nil)
		expect.falsy(stopper:holding(100))
		expect.near(stopper:elapsed(100, 100.5), 0.5, TOLERANCE)
	end)

	t.test("after runs once, in order, when the hold ends; with no hold it runs at once", function()
		local stopper, clock = newStopper()
		local order: { string } = {}
		stopper:after(function()
			table.insert(order, "free")
		end)
		expect.deepEqual(order, { "free" })
		stopper:trigger(1, 0.06, clock.now())
		stopper:after(function()
			table.insert(order, "a")
		end)
		stopper:after(function()
			table.insert(order, "b")
		end)
		expect.equal(stopper:pending(), 2)
		expect.equal(stopper:runDue(100.03), 0) -- still holding
		expect.deepEqual(order, { "free" })
		expect.equal(stopper:runDue(100.07), 2)
		expect.deepEqual(order, { "free", "a", "b" })
		expect.equal(stopper:runDue(100.2), 0) -- never twice
		expect.deepEqual(order, { "free", "a", "b" })
	end)

	t.test("one failing follow-up never stops the others", function()
		local stopper = newStopper()
		stopper:trigger(1, 0.06, 100)
		local ran = 0
		stopper:after(function()
			error("boom")
		end, 100)
		stopper:after(function()
			ran += 1
		end, 100)
		local errors = 0
		stopper:runDue(100.1, function()
			errors += 1
		end)
		expect.equal(ran, 1)
		expect.equal(errors, 1)
	end)

	t.test("clear drops pending calls (they never run) and every hold", function()
		local stopper = newStopper()
		stopper:trigger(1, 0.06, 100)
		local ran = false
		stopper:after(function()
			ran = true
		end, 100)
		stopper:clear()
		expect.equal(stopper:pending(), 0)
		stopper:runDue(101)
		expect.falsy(ran)
		expect.falsy(stopper:holding(100.01))
		-- The key is forgotten too.
		expect.equal(stopper:trigger(1, 0.06, 100.5), 100.5)
	end)

	t.test("only the two people involved get a hold, never on walls or floors", function()
		expect.equal(HitStop.secondsFor("player", false, true, false), cfg.playerHit)
		expect.equal(HitStop.secondsFor("player", false, false, true), cfg.playerHit)
		expect.equal(HitStop.secondsFor("player", true, true, false), cfg.elimination)
		expect.equal(HitStop.secondsFor("player", true, false, true), cfg.elimination)
		expect.equal(HitStop.secondsFor("player", false, false, false), nil) -- a spectator
		expect.equal(HitStop.secondsFor("target", false, false, true), cfg.practiceTarget)
		expect.equal(HitStop.secondsFor("target", false, false, false), nil)
		for _, kind in { "geometry", "expired", "fizzle" } do
			expect.equal(HitStop.secondsFor(kind, false, true, true), nil)
		end
	end)
end
