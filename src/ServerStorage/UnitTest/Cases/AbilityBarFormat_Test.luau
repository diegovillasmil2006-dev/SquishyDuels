--!strict
-- AbilityBarFormat_Test: unit tests for StarterPlayerScripts.Client.UI.AbilityBarFormat and the AbilityBarController
-- lifecycle. Server only (ServerStorage.UnitTest). Contract (Duel HUD part 2, 2026-10-24; D = "Squishy Duels Duel
-- HUD.dc.html"): the phone layout on touch or under 1000 px; the canvas UIScale; the countdown text (D:401); the sweep's
-- share and its two masks; the ultimate's time left from a whole-number meter; the phone arc's boxes (D:240).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Format = t.requireClient("UI/AbilityBarFormat")
	local expect = t.expect

	t.test("form: phone on touch or under 1000 px wide, else desk", function()
		expect.equal(Format.form(1920, false), "desk")
		expect.equal(Format.form(1000, false), "desk")
		expect.equal(Format.form(999, false), "phone")
		expect.equal(Format.form(1920, true), "phone")
	end)

	t.test("canvasScale: min(width / W, height / H) of the design canvas", function()
		expect.near(Format.canvasScale("desk", Vector2.new(1440, 810)), 1, 1e-9)
		expect.near(Format.canvasScale("desk", Vector2.new(2880, 1000)), 1000 / 810, 1e-9)
		expect.near(Format.canvasScale("phone", Vector2.new(667, 375)), 667 / 844, 1e-9)
		expect.equal(Format.canvasScale("desk", Vector2.new(0, 0)), 1)
	end)

	t.test("cooldownText: blank when ready, whole seconds up from 1 s, one decimal below", function()
		expect.equal(Format.cooldownText(0), "")
		expect.equal(Format.cooldownText(-1), "")
		expect.equal(Format.cooldownText(4.4), "5")
		expect.equal(Format.cooldownText(1), "1")
		expect.equal(Format.cooldownText(0.74), "0.7")
		expect.equal(Format.cooldownText(0.01), "0.1")
	end)

	t.test("sweepFraction: the share still covered, 0..1", function()
		expect.near(Format.sweepFraction(4.4, 5), 0.88, 1e-9)
		expect.equal(Format.sweepFraction(0, 5), 0)
		expect.equal(Format.sweepFraction(9, 5), 1)
		expect.equal(Format.sweepFraction(1, 0), 0)
	end)

	t.test("sweepRotations: full = both masks at their start; empty = both turned all the way", function()
		local r, l = Format.sweepRotations(1)
		expect.equal(r, 0)
		expect.equal(l, 180)
		r, l = Format.sweepRotations(0)
		expect.equal(r, 180)
		expect.equal(l, 360)
		r, l = Format.sweepRotations(0.75) -- the clear part is the first 90°
		expect.equal(r, 90)
		expect.equal(l, 180)
		r, l = Format.sweepRotations(0.25) -- the clear part is the first 270°
		expect.equal(r, 180)
		expect.equal(l, 270)
	end)

	t.test("ultLeft: from the whole-number meter, run on while live but never past the next point", function()
		local rate = 100 / 45
		expect.near(Format.ultLeft(0, 100, rate, 0, true), 45, 1e-9)
		expect.equal(Format.ultLeft(100, 100, rate, 0, true), 0)
		-- 0.2 s after a message the meter has grown 0.44 points
		expect.near(Format.ultLeft(50, 100, rate, 0.2, true), (50 - rate * 0.2) / rate, 1e-9)
		-- long after (no message): capped at the next whole point
		expect.near(Format.ultLeft(50, 100, rate, 10, true), 49 / rate, 1e-9)
		-- not live (Countdown): no growth
		expect.near(Format.ultLeft(50, 100, rate, 10, false), 50 / rate, 1e-9)
		expect.equal(Format.ultLeft(50, 100, 0, 1, true), math.huge)
		-- from the middle of a whole point: never more than half a point further
		expect.near(Format.ultLeft(50.5, 100, rate, 10, true, 0.5), 49 / rate, 1e-9)
		expect.near(Format.ultLeft(99.5, 100, rate, 10, true, 0.5), 0, 1e-9)
	end)

	t.test("the 8 s start: a fresh meter is 8 s from full", function()
		local Config = t.requireShared("Config")
		for _, ability in Config.Abilities do
			local left = Format.ultLeft(math.floor(ability.startCharge), ability.chargeMax, ability.chargePerSecond, 0, false)
			expect.truthy(left >= 8 - 1e-9 and left < 8 + 1 / ability.chargePerSecond)
		end
	end)

	t.test("phoneRect: the arc from the bottom-right corner, scaled; Catch is its left edge", function()
		local size = Vector2.new(844, 390)
		local catch = Format.phoneRect("catch", size)
		expect.near(catch.x, 844 - 150 - 62, 1e-9)
		expect.near(catch.y, 390 - 40 - 62, 1e-9)
		expect.near(catch.w, 62, 1e-9)
		local dash = Format.phoneRect("dash", size)
		expect.near(dash.x, 844 - 28 - 62, 1e-9)
		expect.near(Format.phoneArcLeft(size), catch.x, 1e-9)
		local small = Format.phoneRect("ult", Vector2.new(422, 195))
		expect.near(small.w, 36, 1e-9)
	end)

	t.test("ultIconKey: each ultimate's icon slot exists", function()
		local AssetTable = t.requireShared("AssetTable")
		for _, id in { "dragon_rush", "flock_volley", "rain_check", "bubble_pop", "sprinkle_roller" } do
			local key = Format.ultIconKey(id)
			expect.truthy(key ~= nil and AssetTable.image(key) ~= nil)
		end
		expect.equal(Format.ultIconKey(nil), nil)
	end)

	t.test("AbilityBarController: init / start / destroy run cleanly in Edit mode (no LocalPlayer)", function()
		local Bar = t.requireClient("Controllers/AbilityBarController")
		Bar.init()
		Bar.start()
		Bar.destroy()
	end)
end
