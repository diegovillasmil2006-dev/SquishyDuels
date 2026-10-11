--!strict
-- Spring_Test: unit tests for ReplicatedStorage.Shared.Util.Spring. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §9.1 #4, §9.2): an underdamped spring x'' = -ω²(x - target) - 2ζω·x', integrated with
-- semi-implicit Euler in substeps of at most 1/120 s whenever dt > 1/60 s; numbers and Vector3s; used for wobble,
-- flinch and pop-in. A frame hitch must not make it blow up; dt <= 0 does nothing.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- Exact solution of the underdamped spring from rest at x0 (v0 = 0) toward `target`.
local function analytic(x0: number, target: number, omega: number, zeta: number, t: number): number
	local e0 = x0 - target
	local damped = omega * math.sqrt(1 - zeta * zeta)
	local decay = math.exp(-zeta * omega * t)
	return target + decay * (e0 * math.cos(damped * t) + (zeta * omega * e0 / damped) * math.sin(damped * t))
end

return function(t: Context)
	local Spring = t.requireShared("Util/Spring")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local SUBSTEP = Config.Anim.Scheduler.springSubstep

	t.test("one step is semi-implicit Euler: v += a·h first, then x += v·h", function()
		local s = Spring.new(0, 10, 0.5, 1)
		s:step(1 / 100) -- a = ω²·(1 - 0) - 2ζω·0 = 100
		expect.near(s.velocity, 1, 1e-12)
		expect.near(s.position, 0.01, 1e-12) -- explicit Euler would leave x at 0
	end)

	-- First-order integration at 60 fps tracks the exact curve loosely (measured max error ≈ 0.044 on a 0.4 swing);
	-- a wrong omega or zeta would be far off.
	t.test("tracks the exact underdamped curve (pop-in: omega 16, zeta 0.55)", function()
		local s = Spring.new(0.6, 16, 0.55, 1)
		local time = 0
		for _ = 1, 30 do -- 0.5 s at 60 fps
			s:step(1 / 60)
			time += 1 / 60
			expect.near(s.position, analytic(0.6, 1, 16, 0.55, time), 0.06)
		end
	end)

	t.test("an underdamped spring overshoots its target, then settles on it", function()
		local s = Spring.new(0, 24, 0.3, 1)
		local peak = 0
		for _ = 1, 180 do -- 3 s
			s:step(1 / 60)
			peak = math.max(peak, s.position)
		end
		expect.truthy(peak > 1.2)
		expect.near(s.position, 1, 1e-3)
		expect.truthy(s:isSettled(1e-3))
	end)

	t.test("a long frame is integrated in substeps of at most 1/120 s", function()
		local one = Spring.new(0, 20, 0.45, 1)
		local many = Spring.new(0, 20, 0.45, 1)
		one:step(1 / 20)
		for _ = 1, math.round((1 / 20) / SUBSTEP) do
			many:step(SUBSTEP)
		end
		expect.near(one.position, many.position, 1e-9)
		expect.near(one.velocity, many.velocity, 1e-9)
	end)

	t.test("a frame hitch does not make a stiff spring blow up", function()
		local s = Spring.new(0, 24, 0.3, 1)
		s:step(0.5)
		expect.truthy(s.position == s.position and math.abs(s.position) < 3)
		for _ = 1, 120 do
			s:step(1 / 60)
		end
		expect.near(s.position, 1, 1e-3)
	end)

	t.test("dt <= 0 or NaN changes nothing", function()
		local s = Spring.new(0, 16, 0.5, 1)
		s:step(0)
		s:step(-1)
		s:step(0 / 0)
		expect.equal(s.position, 0)
		expect.equal(s.velocity, 0)
	end)

	t.test("impulse adds velocity (jiggle kick) and the spring returns to rest", function()
		local s = Spring.new(1, 24, 0.3)
		s:impulse(0.06 * 24)
		expect.near(s.velocity, 0.06 * 24, 1e-12)
		s:step(1 / 60)
		expect.truthy(s.position > 1)
		for _ = 1, 120 do
			s:step(1 / 60)
		end
		expect.truthy(s:isSettled(1e-3))
	end)

	t.test("Vector3 springs follow the same law per axis", function()
		local v = Spring.new(Vector3.new(0.6, 0.6, 0.6), 16, 0.55, Vector3.one)
		local n = Spring.new(0.6, 16, 0.55, 1)
		for _ = 1, 20 do
			v:step(1 / 60)
			n:step(1 / 60)
		end
		expect.near(v.position.X, n.position, 1e-5)
		expect.near(v.position.Y, n.position, 1e-5)
		expect.near(v.position.Z, n.position, 1e-5)
	end)

	t.test("setTarget and reset", function()
		local s = Spring.new(0, 16, 0.55, 1)
		s:setTarget(2)
		for _ = 1, 120 do
			s:step(1 / 60)
		end
		expect.near(s.position, 2, 1e-3)
		s:reset(5)
		expect.equal(s.position, 5)
		expect.equal(s.velocity, 0)
		expect.equal(s.target, 2)
	end)

	t.test("rejects bad values", function()
		expect.throws(function()
			Spring.new("x", 16, 0.5)
		end)
		expect.throws(function()
			Spring.new(0, 0, 0.5)
		end)
		expect.throws(function()
			Spring.new(0, 16, -1)
		end)
		expect.throws(function()
			Spring.new(0, 16, 0.5, Vector3.one)
		end)
	end)
end
