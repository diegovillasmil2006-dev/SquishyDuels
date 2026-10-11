--!strict
-- Slider_Test: the value maths of StarterPlayerScripts.Client.UI.Components.Slider. Server only (ServerStorage.UnitTest).
-- Pure: Slider.new is never called (no instances).
-- Contract (DESIGN §11.6 Settings: "Sliders support drag, tap and DPad left/right in steps of 5"):
--   * a tap or drag at a fraction of the track gives a whole number inside the range;
--   * the knob sits at the value's fraction of the range;
--   * DPad steps snap to the step grid first (42 -> 45 / 40) and never leave the range.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Slider = t.requireClient("UI/Components/Slider")
	local Config = t.requireShared("Config")
	local STEP = Config.UI.Settings.sliderStep

	t.test("valueAt: whole numbers inside the range", function()
		expect.equal(Slider.valueAt(0, 0, 100), 0)
		expect.equal(Slider.valueAt(1, 0, 100), 100)
		expect.equal(Slider.valueAt(0.404, 0, 100), 40)
		expect.equal(Slider.valueAt(0.406, 0, 100), 41)
		expect.equal(Slider.valueAt(-3, 0, 100), 0)
		expect.equal(Slider.valueAt(7, 0, 100), 100)
		expect.equal(Slider.valueAt(0 / 0, 0, 100), 0)
	end)

	t.test("fractionOf: the knob position", function()
		expect.near(Slider.fractionOf(40, 0, 100), 0.4, 1e-9)
		expect.equal(Slider.fractionOf(-10, 0, 100), 0)
		expect.equal(Slider.fractionOf(150, 0, 100), 1)
		expect.equal(Slider.fractionOf(5, 10, 10), 0)
		expect.equal(Slider.fractionOf(0 / 0, 0, 100), 0)
	end)

	t.test("stepped: snaps to the step grid, stays inside the range", function()
		expect.equal(Slider.stepped(40, 1, STEP, 0, 100), 40 + STEP)
		expect.equal(Slider.stepped(40, -1, STEP, 0, 100), 40 - STEP)
		expect.equal(Slider.stepped(42, 1, 5, 0, 100), 45)
		expect.equal(Slider.stepped(42, -1, 5, 0, 100), 40)
		expect.equal(Slider.stepped(100, 1, 5, 0, 100), 100)
		expect.equal(Slider.stepped(0, -1, 5, 0, 100), 0)
		expect.equal(Slider.stepped(98, 1, 5, 0, 100), 100)
		expect.equal(Slider.stepped(50, 1, 0, 0, 100), 51) -- a bad step counts as 1
		expect.equal(Slider.stepped(0 / 0, 1, 5, 0, 100), 5)
	end)
end
