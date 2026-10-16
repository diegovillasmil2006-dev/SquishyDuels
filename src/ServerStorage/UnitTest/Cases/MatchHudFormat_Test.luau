--!strict
-- MatchHudFormat_Test: StarterPlayerScripts.Client.UI.MatchHudFormat (Match HUD M4, 2026-10-16: the base rules of the
-- in-match screens; plan work/matchhud2/PLAN.md §4 M4 = v1 M3a, v1 §1.3). Server only (ServerStorage.UnitTest). Pure.
-- Contract:
--   * canvas(size, scale): the safe area in base px = size / scale; zero for a bad size or scale;
--   * fitScale(pieceBase, canvas, fitMin, useHeight?): clamp(canvas / pieceBase, fitMin, 1) on width (v1 §1.3b; the
--     6v6 bar ≈ 1170 base on an 844 px phone at the .85 floor ≈ .85), on height too when asked (the smaller), never
--     under fitMin, 1 when it fits or a size is bad;
--   * build(specs, enabled, preview): every piece in a Studio preview, only the switched-on ones in a real match (a
--     missing switch is off), in list order;
--   * sessionAction(session, matchId): a first view starts a session, another match or a real view over a preview
--     restarts it, no view stops a real one and leaves a preview alone, the same match keeps it.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Format = t.requireClient("UI/MatchHudFormat")

	local function spec(name: string): any
		return {
			name = name,
			new = function(): any
				return {}
			end,
		}
	end

	local function names(list: { any }): { string }
		local out = {}
		for _, item in list do
			table.insert(out, item.name)
		end
		return out
	end

	t.test("canvas: the safe area in base px; zero for a bad size or scale", function()
		local c = Format.canvas(Vector2.new(1440, 810), 1.25)
		expect.near(c.X, 1152, 1e-9)
		expect.near(c.Y, 648, 1e-9)
		expect.equal(Format.canvas(Vector2.new(844, 390), 0), Vector2.zero)
		expect.equal(Format.canvas(Vector2.new(0, 390), 0.85), Vector2.zero)
		expect.equal(Format.canvas(Vector2.new(844, 390), 0 / 0), Vector2.zero)
	end)

	t.test("fitScale: shrinks a piece wider than the safe area, never under fitMin, 1 when it fits", function()
		local phone = Format.canvas(Vector2.new(844, 390), 0.85) -- ≈ 993 x 459 base
		expect.near(Format.fitScale(Vector2.new(1170, 120), phone, 0.6), 844 / 0.85 / 1170, 1e-6) -- Vector2 is float32
		expect.equal(Format.fitScale(Vector2.new(2000, 100), phone, 0.6), 0.6)
		expect.equal(Format.fitScale(Vector2.new(400, 200), phone, 0.6), 1)
		expect.equal(Format.fitScale(Vector2.new(0, 200), phone, 0.6), 1) -- a bad size never shrinks
	end)

	t.test("fitScale: with useHeight the smaller of the width and height fits", function()
		local canvas = Vector2.new(1000, 400)
		expect.near(Format.fitScale(Vector2.new(800, 500), canvas, 0.6), 1, 1e-9)
		expect.near(Format.fitScale(Vector2.new(800, 500), canvas, 0.6, true), 0.8, 1e-9)
		expect.near(Format.fitScale(Vector2.new(800, 1000), canvas, 0.6, true), 0.6, 1e-9)
	end)

	t.test("build: a preview builds every piece, a real match only the switched-on ones, in list order", function()
		local specs = { spec("feed"), spec("card"), spec("finish") }
		expect.deepEqual(names(Format.build(specs, {}, true)), { "feed", "card", "finish" })
		expect.deepEqual(names(Format.build(specs, { feed = false, card = true }, false)), { "card" })
		expect.deepEqual(names(Format.build(specs, { finish = true, feed = true }, false)), { "feed", "finish" })
		expect.deepEqual(names(Format.build(specs, {}, false)), {})
	end)

	t.test("sessionAction: start, keep, restart and stop", function()
		local real = { matchId = "match:1", preview = false }
		local preview = { matchId = "match:preview-tdm", preview = true }
		expect.equal(Format.sessionAction(nil, "match:1"), "start")
		expect.equal(Format.sessionAction(nil, nil), "keep")
		expect.equal(Format.sessionAction(real, "match:1"), "keep")
		expect.equal(Format.sessionAction(real, "match:2"), "restart")
		expect.equal(Format.sessionAction(real, nil), "stop")
		expect.equal(Format.sessionAction(preview, nil), "keep") -- no real match: the preview stays
		expect.equal(Format.sessionAction(preview, "match:1"), "restart") -- a real match ends the preview
		expect.equal(Format.sessionAction(preview, "match:preview-tdm"), "restart") -- even with the same id
	end)
end
