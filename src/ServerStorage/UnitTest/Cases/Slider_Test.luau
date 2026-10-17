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

	-- UI FINAL R9 (G9.7, H:898, lib:191): the volume tick: the first change always, then only past a 5% move, at
	-- .8 + .9 x the share.
	t.test(
		"tickPitch: the first change ticks, then only past slideStepShare, at slideFrom + slideSpan x share",
		function()
			local pitch = t.requireShared("Config").Audio.uiPitch
			expect.equal(pitch.slideStepShare, 0.05)
			expect.near(Slider.tickPitch(nil, 0.5) :: number, 0.8 + 0.9 * 0.5, 1e-9)
			expect.equal(Slider.tickPitch(0.5, 0.54), nil)
			expect.equal(Slider.tickPitch(0.5, 0.5), nil)
			expect.near(Slider.tickPitch(0.5, 0.56) :: number, 0.8 + 0.9 * 0.56, 1e-9)
			expect.near(Slider.tickPitch(0.5, 0.44) :: number, 0.8 + 0.9 * 0.44, 1e-9)
			expect.near(Slider.tickPitch(nil, 0) :: number, 0.8, 1e-9)
			expect.near(Slider.tickPitch(0.5, 1) :: number, 1.7, 1e-9)
			expect.equal(Slider.tickPitch(nil, 0 / 0), nil)
		end
	)
end
