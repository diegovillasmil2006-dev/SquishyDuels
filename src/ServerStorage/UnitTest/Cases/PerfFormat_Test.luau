--!strict
-- PerfFormat_Test: StarterPlayerScripts.Client.UI.PerfFormat (the small ping + FPS number). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (LihFolk check 2026-10-31, owner: "Ping + FPS only"):
--   * the Settings chip goes When bad -> Always -> Off -> When bad, starting on When bad;
--   * "bad" = FPS under Config.UI.Perf.badFps or ping from badPingMs up; When bad shows the number only then;
--   * the number reads "60 FPS · 48 ms" in whole numbers.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local PerfFormat = t.requireClient("UI/PerfFormat")
	local PERF = t.requireShared("Config").UI.Perf

	t.test("the chip starts on When bad and cycles Always, Off, When bad", function()
		expect.equal(PerfFormat.MODES[1], "bad")
		expect.equal(PerfFormat.nextMode("bad"), "always")
		expect.equal(PerfFormat.nextMode("always"), "off")
		expect.equal(PerfFormat.nextMode("off"), "bad")
	end)

	t.test("average: the mean, 0 when there are no samples yet", function()
		expect.equal(PerfFormat.average({}), 0)
		expect.equal(PerfFormat.average({ 50, 60, 70 }), 60)
	end)

	t.test("bad at low FPS or high ping, on the limits too", function()
		expect.equal(PerfFormat.isBad(60, 40), false)
		expect.equal(PerfFormat.isBad(PERF.badFps, PERF.badPingMs - 1), false)
		expect.equal(PerfFormat.isBad(PERF.badFps - 1, 40), true)
		expect.equal(PerfFormat.isBad(60, PERF.badPingMs), true)
	end)

	t.test("When bad shows only while bad, Always always, Off never", function()
		local badFps = PERF.badFps - 5
		expect.equal(PerfFormat.shown("bad", 60, 40), false)
		expect.equal(PerfFormat.shown("bad", badFps, 40), true)
		expect.equal(PerfFormat.shown("always", 60, 40), true)
		expect.equal(PerfFormat.shown("off", badFps, 900), false)
	end)

	t.test("the number reads FPS then ping in whole numbers", function()
		expect.equal(PerfFormat.text(59.6, 48.2), "60 FPS · 48 ms")
	end)
end
