--!strict
-- PracticeScoreBox_Test: unit tests for StarterPlayerScripts.Client.UI.PracticeScoreBox's pure parts (Diego's practice
-- score box and hit pop, FULL FINAL lobby). Server only (ServerStorage.UnitTest). Edit mode: no UI is built.
-- Contract (reference-preview "Hub Props.html" :385-390, :448): the box shows the score, the seconds left rounded up
-- (30 before the first hit), the bar's share, "COMBO xN" (at most x5) only while the last hit is within the combo
-- window, the best; the pop reads the callout over "+points (xN)", or that line alone, big for a bullseye.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Box = t.requireClient("UI/PracticeScoreBox")
	local expect = t.expect

	t.test("the box before a round: 0, the whole 30 s, no combo", function()
		local v = Box.view({}, 1000, 0)
		expect.equal(v.score, "0")
		expect.equal(v.time, "30")
		expect.equal(v.timeFraction, 1)
		expect.equal(v.combo, "")
		expect.equal(v.best, "BEST 0")
	end)

	t.test("the box in a round: time rounded up, the bar's share, a running combo capped at x5", function()
		local v = Box.view({ PracticeScore = 350, PracticeRoundEnds = 1012.2, PracticeCombo = 7, PracticeLastHit = 999.5 }, 1000, 420)
		expect.equal(v.score, "350")
		expect.equal(v.time, "13")
		expect.near(v.timeFraction, 12.2 / 30, 1e-9)
		expect.equal(v.combo, "COMBO x5")
		expect.equal(v.best, "BEST 420")
		-- the combo window (1.6 s) has passed: no combo line
		expect.equal(Box.view({ PracticeCombo = 3, PracticeLastHit = 998 }, 1000, 0).combo, "")
		-- a single hit is no combo
		expect.equal(Box.view({ PracticeCombo = 1, PracticeLastHit = 999.9 }, 1000, 0).combo, "")
		-- the round ran out: 0
		expect.equal(Box.view({ PracticeRoundEnds = 990 }, 1000, 0).time, "0")
	end)

	t.test("the pop: callout over the points, the combo in brackets, big for a bullseye", function()
		local top, bottom, big = Box.popText(100, "BULLSEYE!", 1)
		expect.equal(top, "BULLSEYE!")
		expect.equal(bottom, "+100")
		expect.equal(big, true)
		top, bottom, big = Box.popText(150, "GREAT", 3)
		expect.equal(top, "GREAT")
		expect.equal(bottom, "+150 (x3)")
		expect.equal(big, false)
		top, bottom, big = Box.popText(15, "", 1)
		expect.equal(top, "+15")
		expect.equal(bottom, nil)
		expect.equal(big, false)
		top, bottom, big = Box.popText(400, "BULLSEYE!", 4)
		expect.equal(big, true)
	end)
end
