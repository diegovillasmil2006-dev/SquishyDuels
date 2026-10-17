--!strict
-- LevelUpShow_Test: the pure parts of StarterPlayerScripts.Client.UI.LevelUpShow (UI FINAL R9, plan work/ui/PLAN.md R9
-- "Level-up: the full show"; `H:n` = "Squishy Duels HUD.dc.html" line n). Server only (ServerStorage.UnitTest). Pure:
-- LevelUpShow.play is never called (no instances).
-- Contract:
--   * the cues: the slam at 460 ms, the tone at 560, the main hit at 1000 (H:719-728), in that order;
--   * the number's gradient window (H:519: background-size 220%, position 0 -> 100%) at p = 0 / .5 / 1;
--   * the fit (G9.15, PR1): the design's 500 x 560 box 32 inside the safe area at most, never above 1: on a 390 x 844
--     and an 844 x 390 phone at the 0.85 floor, and 1 on a desktop;
--   * the bubbles (H:510, H:1000): 16, left 4 + 6 i + 0..4 %, 18..56 px, 2.4..4.0 s, 1..2.8 s, randomised once and kept;
--   * the ribbon letters (H:999): one per character with sdLvLetIn 1.3 + .035 i and sdLvWave 1.9 + .07 i;
--   * a waiting level-up merged with the next (G9.13): the lowest start, the newest level and unlock;
--   * ReducedMotion's squishy pose (PR9): sdLvSq's last frame, (0, -200) x .55;
--   * the show's numbers: 4.2 s, centred at 44%, its layer above the windows and under the toasts, full screen; the
--     flash under the overlay cap (PR17).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local LevelUpShow = t.requireClient("UI/LevelUpShow")
	local Tweens = t.requireClient("Anim/Tweens")
	local Config = t.requireShared("Config")
	local LOOK = Config.UI.Sticker.levelUp
	local EPSILON = 1e-9

	t.test("cues: the slam at 460 ms, the tone at 560, the main hit at 1000 (H:719-728)", function()
		local cues = LevelUpShow.cues()
		expect.equal(#cues, 3)
		local got = {}
		for _, entry in cues do
			table.insert(got, `{entry.cue}@{entry.ms}`)
		end
		expect.deepEqual(got, { "slam@460", "tone@560", "main@1000" })
	end)

	t.test("gradWindow: the 220% gradient's window slides from its top to its bottom (H:519)", function()
		local share = 1 / 2.2
		local offset, got = LevelUpShow.gradWindow(0)
		expect.near(offset, 0, EPSILON)
		expect.near(got, share, EPSILON)
		expect.near((LevelUpShow.gradWindow(0.5)), (1 - share) * 0.5, EPSILON)
		expect.near((LevelUpShow.gradWindow(1)), 1 - share, EPSILON) -- about .545
		expect.near((LevelUpShow.gradWindow(2)), 1 - share, EPSILON) -- clamped
		expect.near((LevelUpShow.gradWindow(0 / 0)), 0, EPSILON)
	end)

	t.test(
		"fitScale: the 500 x 560 box 32 inside the safe area, at most 1 (phones in both turns, a desktop)",
		function()
			expect.near(LevelUpShow.fitScale(390, 844, 0.85), (390 - 32) / (500 * 0.85), 1e-6)
			expect.near(LevelUpShow.fitScale(844, 390, 0.85), (390 - 32) / (560 * 0.85), 1e-6)
			expect.equal(LevelUpShow.fitScale(1920, 1080, 1.25), 1)
			-- The fitted content stays inside the safe area less its margin.
			for _, safe in { Vector2.new(390, 844), Vector2.new(844, 390) } do
				local k = 0.85 * LevelUpShow.fitScale(safe.X, safe.Y, 0.85)
				expect.truthy(500 * k <= safe.X - 32 + 1e-6)
				expect.truthy(560 * k <= safe.Y - 32 + 1e-6)
			end
			expect.equal(LevelUpShow.fitScale(0 / 0, 390, 0.85), 1)
		end
	)

	t.test("bubbles: 16 in the design's ranges, randomised once per session and kept (H:510, H:1000)", function()
		local list = LevelUpShow.bubbles(Random.new(7))
		expect.equal(#list, 16)
		for i, b in list do
			local base = 4 + 6 * (i - 1)
			expect.truthy(b.x >= base and b.x <= base + 4)
			expect.truthy(b.size >= 18 and b.size <= 56)
			expect.truthy(b.period >= 2.4 and b.period <= 4.0 + EPSILON)
			expect.truthy(b.delay >= 1 and b.delay <= 2.8 + EPSILON)
		end
		expect.equal(LevelUpShow.bubbles(), LevelUpShow.bubbles()) -- the same table: kept
	end)

	t.test("letters: GRIP LEVEL UP! one by one, sdLvLetIn 1.3 + .035 i, sdLvWave 1.9 + .07 i (H:999)", function()
		local letters = LevelUpShow.letters(t.requireShared("Strings").grip.levelUpRibbon)
		expect.equal(#letters, 14)
		expect.equal(letters[1].char, "G")
		expect.equal(letters[5].char, " ")
		expect.near(letters[1].delay, 1.3, EPSILON)
		expect.near(letters[14].delay, 1.3 + 0.035 * 13, EPSILON)
		expect.near(letters[1].wave, 1.9, EPSILON)
		expect.near(letters[14].wave, 1.9 + 0.07 * 13, EPSILON)
	end)

	t.test("merge: a waiting level-up keeps the lowest start, the newest level and unlock (G9.13)", function()
		expect.deepEqual(LevelUpShow.merge(nil, 4, 5, nil), { prev = 4, level = 5 })
		local waiting = LevelUpShow.merge(nil, 4, 5, "Firm Grip")
		expect.deepEqual(LevelUpShow.merge(waiting, 5, 6, nil), { prev = 4, level = 6, unlock = "Firm Grip" })
		expect.deepEqual(LevelUpShow.merge(waiting, 5, 7, "Mega Grip"), { prev = 4, level = 7, unlock = "Mega Grip" })
	end)

	t.test("ReducedMotion: the squishy rests at sdLvSq's last frame, (0, -200) x .55 (PR9, H:50)", function()
		local pose = Tweens.poseAt(LOOK.squishy.frames, 1, LOOK.squishy.curve)
		expect.near(pose.y, -200, EPSILON)
		expect.near(pose.sx, 0.55, EPSILON)
		expect.near(pose.sy, 0.55, EPSILON)
		expect.near(pose.rot, -360, EPSILON)
		expect.near(pose.alpha, 1, EPSILON)
		-- Before its 5% it is not seen (it drops in from 560 px up).
		expect.near(Tweens.poseAt(LOOK.squishy.frames, 0.02, LOOK.squishy.curve).alpha, 0, EPSILON)
	end)

	t.test("the show's numbers: 4.2 s, at 44%, its own full-screen layer over the windows, the flash capped", function()
		expect.equal(LOOK.lifeMs, 4200) -- H:730
		expect.equal(LOOK.centreY, 0.44) -- H:509
		local guis = Config.UI.ScreenGuis
		expect.truthy(LOOK.layer.displayOrder > guis.SD_Modal.displayOrder)
		expect.truthy(LOOK.layer.displayOrder < guis.SD_Overlay.displayOrder) -- the toasts and the FX stay above
		expect.truthy(LOOK.layer.displayOrder ~= Config.UI.confirm.layer.displayOrder)
		expect.equal(LOOK.layer.insets, Enum.ScreenInsets.None)
		expect.truthy(Config.Vfx.Flash.maxOverlayOpacity <= 0.3 + EPSILON) -- PR17: the disc at most .3
		expect.equal(Config.UI.Fx.events.levelUp.toneMs, 560)
		-- The exit holds until 88% (3.70 s), then fades out and grows to 1.3 (H:65).
		local exit = LOOK.exit.frames
		expect.near(Tweens.poseAt(exit, 0.88, LOOK.exit.curve).alpha, 1, EPSILON)
		local last = Tweens.poseAt(exit, 1, LOOK.exit.curve)
		expect.near(last.alpha, 0, EPSILON)
		expect.near(last.scale, 1.3, EPSILON)
	end)
end
