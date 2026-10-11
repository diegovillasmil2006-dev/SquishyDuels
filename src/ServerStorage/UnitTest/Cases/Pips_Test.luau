--!strict
-- Pips_Test: the pure width of StarterPlayerScripts.Client.UI.Components.Pips (DESIGN §11.6 duel life pips).
-- Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract (foam fix 2, 2026-10-09):
--   * the dots keep a visible gap outside their 2 px InkUI outlines (they touched with 6 px between the dots);
--   * rowWidth is the row's resting width (every dot at full size), so a lost pip's pop never counts.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Pips = t.requireClient("UI/Components/Pips")
	local Theme = t.requireClient("UI/Theme")

	t.test("pips (foam fix 2): the dots keep a gap outside their outlines", function()
		local gap = Pips.rowWidth(2, 20) - 2 * 20
		-- Each dot's outline is drawn outside it, so the gap left between two outlines is the spacing less both.
		expect.truthy(gap - 2 * Theme.Stroke.bar >= 6 - 1e-6)
	end)

	t.test("pips (foam fix 2): rowWidth is the row's resting width", function()
		local gap = Pips.rowWidth(2, 20) - 2 * 20
		expect.near(Pips.rowWidth(3, 20), 3 * 20 + 2 * gap, 1e-6)
		expect.near(Pips.rowWidth(1, 20), 20, 1e-6)
		expect.equal(Pips.rowWidth(0, 20), 0)
		expect.equal(Pips.rowWidth(0 / 0, 20), 0)
		-- The default dot size when none is given.
		expect.near(Pips.rowWidth(1), Pips.rowWidth(1, nil), 1e-6)
		expect.truthy(Pips.rowWidth(1) > 0)
	end)
end
