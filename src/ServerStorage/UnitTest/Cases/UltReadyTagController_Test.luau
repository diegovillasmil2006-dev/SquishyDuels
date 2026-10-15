--!strict
-- UltReadyTagController_Test: unit tests for StarterPlayerScripts.Client.Controllers.UltReadyTagController (the pure
-- helpers). Server only (ServerStorage.UnitTest). Edit mode: init() / start() are not called (no LocalPlayer).
-- Contract (jayyyyy 2026-10-15, "show on top of the players that they have ult ready"):
--   * shownFor(view, localUserId): every duelist but the local player whose ultReady is true, only while the match is
--     on (not Result, Returning, Cancelled, Void); nothing without a view;
--   * scaleAt(t, reduced): the HUD READY badge's motion: the readyPop pop, then a pulse within 1 ± 0.08 every
--     ultReadyPulseSeconds; under ReducedMotion it holds at 1 once popped.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Tag = t.requireClient("Controllers/UltReadyTagController")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local MOTION = Config.UI.motion

	local function view(phase: string, youReady: boolean, opponentReady: boolean): any
		return {
			phase = phase,
			you = { userId = 1, ultReady = youReady },
			opponent = { userId = 2, ultReady = opponentReady },
		}
	end

	t.test("shownFor: the other duelist with a charged ultimate, never the local player", function()
		expect.deepEqual(Tag.shownFor(view("Active", true, true), 1), { 2 })
		expect.deepEqual(Tag.shownFor(view("Active", true, false), 1), {})
		expect.deepEqual(Tag.shownFor(view("SuddenDeath", false, true), 1), { 2 })
		expect.deepEqual(Tag.shownFor(view("Countdown", false, true), 1), { 2 })
	end)

	t.test("shownFor: a spectator-like client (not in the view) sees both charged duelists", function()
		expect.deepEqual(Tag.shownFor(view("Active", true, true), 99), { 1, 2 })
	end)

	t.test("shownFor: nothing without a view or once the match ends", function()
		expect.deepEqual(Tag.shownFor(nil, 1), {})
		for _, phase in { "Result", "Returning", "Cancelled", "Void" } do
			expect.deepEqual(Tag.shownFor(view(phase, true, true), 1), {})
		end
	end)

	t.test("scaleAt: pops from readyPop.from, then pulses within 1 ± 0.08", function()
		expect.near(Tag.scaleAt(0, false), MOTION.readyPop.from, 1e-6)
		local popEnd = MOTION.readyPop.ms / 1000
		for i = 0, 20 do
			local s = Tag.scaleAt(popEnd + i * MOTION.ultReadyPulseSeconds / 10, false)
			expect.truthy(s >= 1 - 0.08 - 1e-6 and s <= 1 + 0.08 + 1e-6)
		end
	end)

	t.test("scaleAt: ReducedMotion holds at 1 once popped", function()
		local popEnd = MOTION.readyPop.ms / 1000
		expect.near(Tag.scaleAt(popEnd + 0.37, true), 1, 1e-6)
		expect.near(Tag.scaleAt(popEnd + 5, true), 1, 1e-6)
	end)
end
