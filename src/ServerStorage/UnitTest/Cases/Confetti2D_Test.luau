--!strict
-- Confetti2D_Test: StarterPlayerScripts.Client.UI.Confetti2D (the result panel's 2D confetti). Server only
-- (ServerStorage.UnitTest). Pure parts only: no instances, no Scheduler.
-- Contract (DESIGN §18.5.2 B7, §18.1 #4, §18.11):
--   * never red: the win and draw colours, and anything spawned, are never Danger and never a red hue (within 15° of
--     red with saturation > 0.45);
--   * done by its lifetime: a piece is alive while its age is under `lifetime`, then done; it fades over the last
--     fadeSeconds;
--   * stays inside the panel: launched up from the title, every piece's centre stays at least half its diagonal
--     inside the layer on every frame, even at the slowest frame rate.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Confetti2D = t.requireClient("UI/Confetti2D")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local CONFETTI = Config.Anim.duel.confetti
	local reach = math.sqrt(CONFETTI.w * CONFETTI.w + CONFETTI.h * CONFETTI.h) / 2

	t.test("never red: the win and draw colours, and every spawned piece", function()
		expect.equal(#Confetti2D.WIN_COLORS, 4)
		expect.equal(#Confetti2D.DRAW_COLORS, 2)
		for _, list in { Confetti2D.WIN_COLORS, Confetti2D.DRAW_COLORS } do
			for _, color in list do
				expect.falsy(Confetti2D.isRed(color))
				expect.truthy(color ~= Palette.Danger)
			end
		end
		expect.truthy(Confetti2D.isRed(Color3.fromRGB(255, 0, 0)))
		expect.truthy(Confetti2D.isRed(Palette.Danger))
		-- Red inputs are skipped; a list of only red ones falls back to a safe colour.
		local pieces = Confetti2D.spawn(
			Random.new(7),
			12,
			Vector2.new(50, 20),
			{ Palette.Danger, Color3.fromRGB(255, 0, 0), Palette.Mint }
		)
		expect.equal(#pieces, 12)
		for _, piece in pieces do
			expect.falsy(Confetti2D.isRed(piece.color))
			expect.truthy(piece.color ~= Palette.Danger)
		end
		for _, piece in Confetti2D.spawn(Random.new(8), 3, Vector2.zero, { Palette.Danger }) do
			expect.falsy(Confetti2D.isRed(piece.color))
		end
	end)

	t.test("launch: upward from the origin within the DESIGN speeds", function()
		local origin = Vector2.new(230, 30)
		for _, piece in Confetti2D.spawn(Random.new(11), CONFETTI.pieces, origin, Confetti2D.WIN_COLORS) do
			expect.equal(piece.x, origin.X)
			expect.equal(piece.y, origin.Y)
			expect.truthy(math.abs(piece.vx) <= CONFETTI.vxPx)
			expect.truthy(-piece.vy >= CONFETTI.vyMinPx and -piece.vy <= CONFETTI.vyMaxPx)
			expect.truthy(math.abs(piece.spin) <= CONFETTI.spinDeg)
			expect.equal(piece.age, 0)
		end
	end)

	t.test("done by its lifetime, fading over the last fadeSeconds", function()
		local size = Vector2.new(460, 320)
		local piece = Confetti2D.spawn(Random.new(3), 1, Vector2.new(230, 40), Confetti2D.WIN_COLORS)[1]
		local dt = 1 / 60
		local frames = 0
		while Confetti2D.step(piece, dt, size) do
			frames += 1
			expect.truthy(piece.age < CONFETTI.lifetime)
			expect.truthy(frames < 1000)
		end
		expect.truthy(piece.age >= CONFETTI.lifetime)
		expect.truthy(math.abs(frames - CONFETTI.lifetime * 60) <= 2)
		expect.equal(Confetti2D.transparencyAt(0), 0)
		expect.equal(Confetti2D.transparencyAt(CONFETTI.lifetime - CONFETTI.fadeSeconds), 0)
		expect.near(Confetti2D.transparencyAt(CONFETTI.lifetime - CONFETTI.fadeSeconds / 2), 0.5, 1e-6)
		expect.equal(Confetti2D.transparencyAt(CONFETTI.lifetime), 1)
	end)

	t.test("stays inside the panel on every frame", function()
		for _, case in
			{
				{ size = Vector2.new(460, 320), origin = Vector2.new(230, 30), dt = 1 / 60 },
				{ size = Vector2.new(460, 180), origin = Vector2.new(20, 20), dt = 1 / 20 },
				{ size = Vector2.new(300, 600), origin = Vector2.new(150, 300), dt = 1 / 144 },
			}
		do
			for seed = 1, 5 do
				local pieces = Confetti2D.spawn(Random.new(seed), CONFETTI.pieces, case.origin, Confetti2D.WIN_COLORS)
				for _ = 1, math.ceil(CONFETTI.lifetime / case.dt) + 2 do
					for _, piece in pieces do
						Confetti2D.step(piece, case.dt, case.size)
						expect.truthy(piece.x >= reach - 1e-9 and piece.x <= case.size.X - reach + 1e-9)
						expect.truthy(piece.y >= reach - 1e-9 and piece.y <= case.size.Y - reach + 1e-9)
					end
				end
			end
		end
		-- A layer smaller than a piece keeps it in the middle.
		local tiny = Confetti2D.spawn(Random.new(1), 1, Vector2.new(5, 5), Confetti2D.DRAW_COLORS)[1]
		Confetti2D.step(tiny, 1 / 60, Vector2.new(6, 6))
		expect.equal(tiny.x, 3)
		expect.equal(tiny.y, 3)
	end)
end
