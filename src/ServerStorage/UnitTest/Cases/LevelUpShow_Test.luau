--!strict
-- LevelUpShow_Test: StarterPlayerScripts.Client.UI.LevelUpShow, the new short level-up (2026-10-25; `L:n` = Diego's
-- "Squishy Duels LOBBY HUD.dc.html" line n). Server only (ServerStorage.UnitTest).
-- Contract:
--   * the hold (L:931): 1.3 s, 1.9 s with an unlock line; the cues: the tone at 60 ms, the main hit at 440 (L:940-945),
--     the arrival 400 ms after the hold (L:950), in that order;
--   * the flight (L:948-949): from the badge (0, 0, 1) through its lift (15% of the way, 20 px higher, 1.08) to the
--     target, shrunk to .18 and faded;
--   * a waiting level-up merged with the next: the lowest start, the newest level and unlock;
--   * the layer at (50%, 34%), above the windows (z 25), gone 460 ms after the flight starts (L:955);
--   * the show builds its parts (badge, opening with both numbers, chip, ring, 8 rays, ribbon, the unlock line only
--     with an unlock) and stops cleanly once (onDone).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local LevelUpShow = t.requireClient("UI/LevelUpShow")
	local Config = t.requireShared("Config")
	local LOOK = Config.UI.Sticker.levelUp

	t.test("the hold, then the cues: the tone at 60 ms, the main hit at 440, the arrival after the hold", function()
		expect.equal(LevelUpShow.holdMs(false), 1300)
		expect.equal(LevelUpShow.holdMs(true), 1900)
		for _, unlock in { false, true } do
			local cues = LevelUpShow.cues(unlock)
			local got = {}
			for _, entry in cues do
				table.insert(got, { entry.cue, entry.ms })
			end
			expect.deepEqual(got, {
				{ "tone", 60 },
				{ "main", 440 },
				{ "arrive", LevelUpShow.holdMs(unlock) + 400 },
			})
		end
	end)

	t.test("the flight lifts first, then reaches the target small and faded (L:948-949)", function()
		local frames = LevelUpShow.flightFrames(200, -300)
		expect.equal(#frames, 3)
		expect.deepEqual(frames[1], { at = 0, alpha = 1, x = 0, y = 0, scale = 1 })
		expect.near(frames[2].x, 30, 1e-9)
		expect.near(frames[2].y, -45 - 20, 1e-9)
		expect.near(frames[2].scale, 1.08, 1e-9)
		expect.equal(frames[2].at, 0.25)
		expect.deepEqual(frames[3], { at = 1, alpha = 0, x = 200, y = -300, scale = 0.18 })
	end)

	t.test("a waiting level-up merges with the next: the lowest start, the newest level and unlock", function()
		expect.deepEqual(LevelUpShow.merge(nil, 4, 5, nil), { prev = 4, level = 5 })
		local waiting = LevelUpShow.merge(nil, 4, 5, "Firm Grip")
		expect.deepEqual(LevelUpShow.merge(waiting, 5, 6, nil), { prev = 4, level = 6, unlock = "Firm Grip" })
		expect.deepEqual(LevelUpShow.merge(waiting, 5, 7, "Mega Grip"), { prev = 4, level = 7, unlock = "Mega Grip" })
	end)

	t.test("the layer and the timing: (50%, 34%), z 25, gone 460 ms after the flight starts", function()
		expect.equal(LOOK.centreX, 0.5)
		expect.equal(LOOK.centreY, 0.34)
		expect.equal(LOOK.layer.displayOrder, 24) -- above the windows (SD_Modal), under the toasts
		expect.equal(LOOK.layer.insets, Enum.ScreenInsets.None)
		expect.equal(LOOK.endAfterMs, 460)
		expect.equal(LOOK.rays.n, 8)
	end)

	t.test("the show builds its parts and stops cleanly once", function()
		for _, unlock in { "", "Firm Grip" } do
			local gui = Instance.new("ScreenGui")
			local done = 0
			LevelUpShow.play({
				layer = gui,
				prev = 4,
				level = 5,
				unlock = if unlock ~= "" then unlock else nil,
				uiScale = function(): number
					return 1
				end,
				onDone = function()
					done += 1
				end,
			})
			expect.truthy(LevelUpShow.isPlaying())
			local root = gui:FindFirstChild("SD_LevelUpShow") :: Frame
			expect.truthy(root ~= nil)
			local opening = root:FindFirstChild("Opening", true) :: CanvasGroup
			expect.truthy(opening ~= nil and opening:IsA("CanvasGroup"))
			expect.equal(((opening:FindFirstChild("Old") :: Frame):FindFirstChild("Text") :: TextLabel).Text, "4")
			expect.equal(((opening:FindFirstChild("New") :: Frame):FindFirstChild("Text") :: TextLabel).Text, "5")
			expect.truthy(root:FindFirstChild("Chip", true) ~= nil)
			expect.truthy(root:FindFirstChild("Ring", true) ~= nil)
			expect.truthy(root:FindFirstChild("Ray8", true) ~= nil)
			expect.truthy(root:FindFirstChild("Ribbon", true) ~= nil)
			expect.equal(root:FindFirstChild("Unlock", true) ~= nil, unlock ~= "")
			LevelUpShow.stop()
			LevelUpShow.stop()
			expect.falsy(LevelUpShow.isPlaying())
			expect.equal(root.Parent, nil)
			expect.equal(done, 1) -- (task.spawn runs it at once)
			gui:Destroy()
		end
	end)
end
