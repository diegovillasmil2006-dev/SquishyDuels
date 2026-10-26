--!strict
-- BoxReveal_Test: the pure parts of StarterPlayerScripts.Client.UI.BoxReveal's fancier reveal (2026-10-26; `L:n` =
-- Diego's "Squishy Duels LOBBY HUD.dc.html" line n). Contract: 18 rising stars (L:1454) left 3 + 5.4 i + 0..3 %,
-- 10..26 px, 3..6 s a rise, started 0..5 s into it, white / gold / white, drawn once a session and kept; a star p into
-- its rise (L:554 uxMote) lifts 900 p px, turns 220 p degrees, grows .6 -> 1.1, in by 15% and out from 85%.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local BoxReveal = t.requireClient("UI/BoxReveal")

	t.test("the stars: 18, spread across the width, 10..26 px, 3..6 s a rise, white / gold / white, kept", function()
		local list = BoxReveal.motes(Random.new(3))
		expect.equal(#list, 18)
		for i, mote in list do
			local from = 3 + (i - 1) * 5.4
			expect.truthy(mote.x >= from and mote.x <= from + 3)
			expect.truthy(mote.px >= 10 and mote.px <= 26)
			expect.truthy(mote.period >= 3 and mote.period <= 6)
			expect.truthy(mote.start >= 0 and mote.start <= 5)
			expect.equal(mote.color, ({ "White", "StickerCoinText", "White" })[(i - 1) % 3 + 1])
		end
		expect.equal(BoxReveal.motes(), BoxReveal.motes()) -- the same table: drawn once a session
	end)

	t.test("a star along its rise: up 900 px turning 220 degrees, .6 -> 1.1, in by 15% and out from 85%", function()
		local lift, turn, scale, alpha = BoxReveal.moteAt(0)
		expect.deepEqual({ lift, turn, scale, alpha }, { 0, 0, 0.6, 0 })
		lift, turn, scale, alpha = BoxReveal.moteAt(0.5)
		expect.near(lift, 450, 1e-9)
		expect.near(turn, 110, 1e-9)
		expect.near(scale, 0.85, 1e-9)
		expect.equal(alpha, 1)
		expect.near(select(4, BoxReveal.moteAt(0.075)), 0.5, 1e-9)
		expect.near(select(4, BoxReveal.moteAt(0.925)), 0.5, 1e-9)
		expect.near(select(4, BoxReveal.moteAt(1)), 0, 1e-9)
	end)
end
