--!strict
-- PressSpeed_Test: unit tests for ReplicatedStorage.Shared.PressSpeed (p13v3 verification fix; owner 2026-10-18: "Yes,
-- above 20 a second"). Pure: every case passes its own press times (the client's os.clock seconds).
-- Contract (Config.Net.AutoClick.speed: perSecond 20, seconds 3):
--   * press(state, now) counts one real press in its whole second; `peak` = the most whole seconds in a row each with
--     more than perSecond presses (the current one counts once it is over the line): 21 a second reaches 3 at the 21st
--     press of the 3rd second, never before; exactly 20 a second never counts; a kid's 2 s burst (up to 40 a second,
--     however it falls across whole seconds) never reaches 3; a slower or an empty second starts the run again;
--   * sent(state) after a send that carried `peak`: the next report starts from the run so far (still alive while
--     the second right after a hot one is running), 0 once a slower second ended it.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

local SECOND = 2000 -- a whole os.clock second, so the cases can place presses inside seconds

return function(t: Context)
	local expect = t.expect
	local PressSpeed = t.requireShared("PressSpeed")

	-- `perSecond` presses inside each of `seconds` whole seconds from `from`; the state and the 1-based second in which
	-- the peak first reached 3 (nil: never), at its `press`-th press.
	local function run(perSecond: number, seconds: number, from: number?): (any, number?, number?)
		local state = PressSpeed.new()
		local start = from or SECOND
		local reached, at = nil, nil
		for s = 1, seconds do
			for i = 1, perSecond do
				PressSpeed.press(state, start + s - 1 + (i - 0.5) / perSecond)
				if reached == nil and state.peak >= 3 then
					reached, at = s, i
				end
			end
		end
		return state, reached, at
	end

	t.test(
		"more than 20 presses in each of 3 seconds in a row: the peak reaches 3 at the 21st press of the 3rd",
		function()
			local state, reached, at = run(21, 10)
			expect.equal(reached, 3)
			expect.equal(at, 21)
			expect.equal(state.peak, 10)
			-- Exactly 20 a second, for 10 minutes, never counts (strictly more than 20).
			expect.equal((run(20, 600)).peak, 0)
		end
	)

	t.test("a kid's 2 s burst never reaches 3, however it falls across whole seconds; 3 hot seconds do", function()
		expect.equal((run(400, 2)).peak, 2) -- inside 2 whole seconds
		expect.equal((run(35, 2, SECOND + 0.5)).peak, 1) -- half, whole, half: only the whole second is over 20
		expect.equal((run(400, 2, SECOND + 0.5)).peak, 3) -- 200 + 400 + 200: 3 seconds over the line
	end)

	t.test("a slower second, or an empty one, starts the run again", function()
		local state = PressSpeed.new()
		for index, presses in { 40, 40, 20, 40, 40, 0, 40, 40 } do
			for i = 1, presses do
				PressSpeed.press(state, SECOND + index - 1 + (i - 0.5) / presses)
			end
		end
		expect.equal(state.peak, 2)
		for i = 1, 21 do -- the run's last two seconds and one more in a row
			PressSpeed.press(state, SECOND + 8 + i / 22)
		end
		expect.equal(state.peak, 3)
	end)

	t.test("sent: the next report starts from the run so far, 0 once a slower second ended it", function()
		local state = run(30, 4) -- 4 seconds over the line
		expect.equal(state.peak, 4)
		PressSpeed.sent(state)
		expect.equal(state.peak, 4) -- the 4th second is still running and over the line
		PressSpeed.press(state, SECOND + 4.1) -- the 5th second: the run is alive until it ends below the line
		PressSpeed.sent(state)
		expect.equal(state.peak, 4)
		PressSpeed.press(state, SECOND + 5.5) -- the 5th second ended with 1 press: the run is over
		expect.equal(state.peak, 4) -- not reported yet
		PressSpeed.sent(state)
		expect.equal(state.peak, 0)
	end)
end
