--!strict
-- StormMath_Test: unit tests for ReplicatedStorage.Shared.StormMath (the Team Deathmatch storm, Config.Match.Storm).
-- Contract: the start radius is half the map's X/Z diagonal; the circle holds until each step's shrinkAt, then shrinks
-- linearly to radiusFraction x start over shrinkSeconds; nextShrink counts down to the next step; "in the storm" means
-- horizontally farther from the centre than the radius; the bar fills over barFillSeconds in the storm, drains over
-- barDrainSeconds outside and stays in 0..1. Config's storm reaches its last circle before TDM's time-up.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local StormMath = t.requireShared("StormMath")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local STORM = Config.Match.Storm

	-- A storm with round numbers, independent of Config's tuning.
	local FAKE = {
		stormStartSeconds = 100,
		warnSeconds = 30,
		steps = {
			{ shrinkAt = 100, shrinkSeconds = 20, radiusFraction = 0.5 },
			{ shrinkAt = 200, shrinkSeconds = 40, radiusFraction = 0.25 },
		},
		barFillSeconds = 3,
		barDrainSeconds = 9,
	}

	t.test("startRadius: half the X/Z diagonal of the footprint (height ignored)", function()
		expect.near(StormMath.startRadius(Vector3.new(160, 50, 240)), math.sqrt(160 ^ 2 + 240 ^ 2) / 2, 1e-6)
		expect.near(StormMath.startRadius(Vector3.new(200, 0, 200)), 100 * math.sqrt(2), 1e-6)
	end)

	t.test("radiusAt: holds, then shrinks linearly step by step, then stays at the last circle", function()
		local R = 100
		expect.equal(StormMath.radiusAt(FAKE, R, 0), R)
		expect.equal(StormMath.radiusAt(FAKE, R, 100), R)
		expect.near(StormMath.radiusAt(FAKE, R, 110), 75, 1e-6)
		expect.near(StormMath.radiusAt(FAKE, R, 120), 50, 1e-6)
		expect.near(StormMath.radiusAt(FAKE, R, 199), 50, 1e-6)
		expect.near(StormMath.radiusAt(FAKE, R, 220), 37.5, 1e-6)
		expect.near(StormMath.radiusAt(FAKE, R, 240), 25, 1e-6)
		expect.near(StormMath.radiusAt(FAKE, R, 10000), 25, 1e-6)
	end)

	t.test("shown and nextShrink", function()
		expect.falsy(StormMath.shown(FAKE, 99.9))
		expect.truthy(StormMath.shown(FAKE, 100))
		local seconds, index = StormMath.nextShrink(FAKE, 70)
		expect.equal(seconds, 30)
		expect.equal(index, 1)
		seconds, index = StormMath.nextShrink(FAKE, 150)
		expect.equal(seconds, 50)
		expect.equal(index, 2)
		seconds, index = StormMath.nextShrink(FAKE, 200)
		expect.equal(seconds, nil)
		expect.equal(index, nil)
	end)

	t.test("inStorm: horizontal distance beyond the radius; the edge itself is safe", function()
		local centre = Vector3.new(10, 0, -10)
		expect.falsy(StormMath.inStorm(centre, 10, Vector3.new(16, 300, -2))) -- distance exactly 10
		expect.truthy(StormMath.inStorm(centre, 10, Vector3.new(18, 0, -2)))
		expect.falsy(StormMath.inStorm(centre, 10, centre))
	end)

	t.test("stepBar: fills over barFillSeconds in the storm, drains over barDrainSeconds outside, stays in 0..1", function()
		expect.near(StormMath.stepBar(FAKE, 0, true, 1.5), 0.5, 1e-9)
		expect.near(StormMath.stepBar(FAKE, 0.5, false, 4.5), 0, 1e-9)
		expect.equal(StormMath.stepBar(FAKE, 0.9, true, 5), 1)
		expect.equal(StormMath.stepBar(FAKE, 0.1, false, 5), 0)
		expect.equal(StormMath.stepBar(FAKE, 0.4, true, 0), 0.4)
		expect.equal(StormMath.stepBar(FAKE, 0.4, true, -1), 0.4)
	end)

	t.test("Config: the storm starts at stormStartSeconds and reaches its last circle before TDM's time-up", function()
		local first = STORM.steps[1]
		local last = STORM.steps[#STORM.steps]
		expect.equal(first.shrinkAt, STORM.stormStartSeconds)
		expect.truthy(last.shrinkAt + last.shrinkSeconds <= Config.Match.Modes.tdm.matchSeconds)
		expect.truthy(Config.Match.Modes.tdm.storm)
		expect.falsy(Config.Match.Modes.ffa.storm)
	end)
end
