--!strict
-- Killcam_Test: unit tests for StarterPlayerScripts.Client.UI.Match.Killcam (killcam step 1, 2026-10-26; K = Diego's
-- uploads/match-stage.html). Contract: Diego's speed ramp (full, x0.22 round the squish, full again), the look turning
-- onto the victim by the throw, the FOV beats and the punch, a whole killcam ending before the 9 s cut, the tape's
-- samples round a time, the window round the final squish (none without the killer, the victim, an attacker or enough
-- tape; the killer's last throw), the arm's points and its throw punch, and the tape keeping its last seconds and
-- stopping at an end with no killcam.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-3

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local Killcam = t.requireClient("UI/Match/Killcam")
	local KC = Config.UI.Match.finish.killcam

	local function body(): any
		return { root = CFrame.identity, head = CFrame.identity, joints = {}, held = nil }
	end

	-- Samples every 1/30 s from `from` to `to`, killer 1 and victim 2 on every one; the killer's toy 7 from `throwAt`.
	local function frames(from: number, to: number, throwAt: number?): { any }
		local out = {}
		local n = math.floor((to - from) * 30 + 0.5)
		for i = 0, n do
			local at = from + i / 30
			local flying = {}
			if throwAt and at >= throwAt then
				table.insert(flying, { id = 7, squishyId = "x", scale = 1, at = CFrame.identity, thrower = 1 })
			end
			table.insert(out, { t = at, bodies = { [1] = body(), [2] = body() }, flying = flying })
		end
		return out
	end

	t.test("the speed: full, easing down to x0.22 round the squish, then full again (K:444-449)", function()
		expect.equal(Killcam.speed(-2), 1)
		expect.equal(Killcam.speed(-0.55), 1)
		expect.near(Killcam.speed(-0.3), 0.5156, EPS)
		expect.near(Killcam.speed(-0.12), 0.22, EPS)
		expect.equal(Killcam.speed(0), 0.22)
		expect.near(Killcam.speed(0.45), 0.22, EPS)
		expect.near(Killcam.speed(0.675), 0.61, EPS)
		expect.near(Killcam.speed(0.9), 1, EPS)
		expect.equal(Killcam.speed(3), 1)
		expect.equal(Killcam.smooth(-1), 0)
		expect.equal(Killcam.smooth(0.5), 0.5)
		expect.equal(Killcam.smooth(2), 1)
	end)

	t.test("the look turns onto the victim by the throw; the FOV beats and the punch (K:483, 489)", function()
		expect.near(Killcam.lookWeight(10, 10, 12), 0.35, EPS)
		expect.near(Killcam.lookWeight(11, 10, 12), 0.675, EPS)
		expect.near(Killcam.lookWeight(12, 10, 12), 1, EPS)
		expect.near(Killcam.lookWeight(13, 10, 12), 1, EPS)
		expect.equal(Killcam.fov(-1, 0), 72)
		expect.equal(Killcam.fov(0, 0), 54)
		expect.equal(Killcam.fov(0, 1), 64)
		expect.equal(Killcam.fov(0.6, 0), 66)
	end)

	t.test("a whole killcam ends before the 9 s cut", function()
		local length = Killcam.length()
		expect.truthy(length > 6.5 and length < 7.6)
		expect.truthy(KC.at + length < KC.cap)
		expect.truthy(Config.Match.killcamSeconds >= KC.cap)
	end)

	t.test("bracket: the samples round a time and how far between", function()
		local f = { { t = 0 }, { t = 1 }, { t = 2 } } :: any
		local a, b, u = Killcam.bracket(f, 0.5)
		expect.deepEqual({ a, b }, { 1, 2 })
		expect.near(u, 0.5, EPS)
		a, b, u = Killcam.bracket(f, 1.75)
		expect.deepEqual({ a, b }, { 2, 3 })
		expect.near(u, 0.75, EPS)
		a, b, u = Killcam.bracket(f, -1)
		expect.deepEqual({ a, b, u }, { 1, 1, 0 })
		a, b, u = Killcam.bracket(f, 5)
		expect.deepEqual({ a, b, u }, { 3, 3, 0 })
		a, b, u = Killcam.bracket({}, 1)
		expect.deepEqual({ a, b, u }, { 0, 0, 0 })
	end)

	t.test("window: before -> after the squish, the killer's last throw; none without a killcam", function()
		local tape = frames(0, 5, 2)
		local w = Killcam.window(tape, { at = 4, by = 1, victim = 2 })
		expect.truthy(w ~= nil)
		local win = w :: any
		expect.near(win.t0, 4 - 190 / 60, EPS)
		expect.near(win.t1, 4 + 54 / 60, EPS)
		expect.equal(win.hit, 4)
		expect.near(win.throwAt, 2, EPS)
		expect.equal(#win.throws, 1)
		-- the tape ends at the squish: the window too; no throw on the tape: 0.5 s before the squish
		local short = Killcam.window(frames(0, 4), { at = 4, by = 1, victim = 2 }) :: any
		expect.near(short.t1, 4, EPS)
		expect.near(short.throwAt, 3.5, EPS)
		expect.equal(#short.throws, 0)
		-- a throw that started before the window: from the window's start
		local early = Killcam.window(frames(0, 5, 0.2), { at = 4, by = 1, victim = 2 }) :: any
		expect.near(early.throwAt, early.t0, EPS)
		expect.equal(#early.throws, 0)
		-- none: no attacker (the storm), too little tape, the victim not on it, nothing at all
		expect.equal(Killcam.window(tape, { at = 4, victim = 2 }), nil)
		expect.equal(Killcam.window(tape, { at = 0.1, by = 1, victim = 2 }), nil)
		expect.equal(Killcam.window(tape, { at = 4, by = 1, victim = 3 }), nil)
		expect.equal(Killcam.window({}, { at = 4, by = 1, victim = 2 }), nil)
		expect.equal(Killcam.window(tape, nil), nil)
	end)

	t.test("the arm: Diego's fist, sleeve and toy, bobbing and punching forward (K:434-448, 491-498)", function()
		local A = KC.arm
		local hand, shoulder, toy = Killcam.armPoints(0, 1, 0, 0)
		local yaw = A.yaw
		expect.near(hand.X, A.at.X - 0.6 * math.sin(yaw), EPS)
		expect.near(hand.Y, A.at.Y + A.bob.y, EPS) -- |cos 0| x the bob
		expect.near(hand.Z, A.at.Z - 0.6 * math.cos(yaw), EPS)
		expect.near(shoulder.Z, A.at.Z + 2.7 * math.cos(yaw), EPS)
		expect.near(toy.Y, A.at.Y + A.bob.y + 0.7, EPS)
		local pushed = Killcam.armPoints(0, 1, A.throw.push, A.throw.lift)
		expect.truthy(pushed.Z < hand.Z - 1) -- forward
		expect.truthy(pushed.Y > hand.Y) -- lifted, and turned down a little
	end)

	t.test("the tape keeps its last seconds at its rate and stops at an end with no killcam", function()
		local tape = Killcam.tape({
			saveCamera = function() end,
			restoreCamera = function() end,
			setHeldHidden = function() end,
			setAway = function() end,
			held = function(): any
				return nil
			end,
			flying = function(): any
				return {}
			end,
		})
		local view = { players = {} }
		tape:record(view, 10)
		tape:record(view, 10.01) -- under 1/30 s: no sample
		tape:record(view, 10.05)
		expect.equal(#tape.frames, 2)
		tape:record(view, 10 + KC.tape.keep + 1)
		expect.equal(#tape.frames, 1)
		-- a squish the killcam can show keeps it recording until `after` past it
		local won = { players = {}, outcome = { finalKo = { at = 16, by = 1, victim = 2 } } }
		tape:record(won, 16.5)
		expect.equal(#tape.frames, 2)
		tape:record(won, 16 + KC.after + 1)
		tape:record(won, 16.6)
		expect.equal(#tape.frames, 2)
		-- no final squish (a time-up, the storm): it stops at once
		local other = Killcam.tape({
			saveCamera = function() end,
			restoreCamera = function() end,
			setHeldHidden = function() end,
			setAway = function() end,
			held = function(): any
				return nil
			end,
			flying = function(): any
				return {}
			end,
		})
		other:record({ players = {}, outcome = { finalKo = { at = 5, victim = 2 } } }, 5.1)
		other:record({ players = {} }, 6)
		expect.equal(#other.frames, 0)
	end)
end
