--!strict
-- MatchFoundShow_Test: unit tests for StarterPlayerScripts.Client.UI.MatchFoundShow (round 2 of the match flow,
-- 2026-10-25; L = Diego's "Squishy Duels LOBBY HUD.dc.html"). Contract: the stage fits the whole 1440 x 810 design on any
-- screen (L:629); the row puts you on the left in DUEL, the Strawberry team left and Blueberry right in TEAM (VS after
-- the left half), you first in FREE FOR ALL (no VS); a team's tiles nearest the middle come in first, .05 s apart from
-- 1.2 s, Free for All's in order (L:1412-1414); the mode chip's gradient is the design's (L:763-765); the show builds,
-- plays its sounds on time and ends by itself once the arena is on.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local MatchFoundShow = t.requireClient("UI/MatchFoundShow")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local expect = t.expect
	local ROSTER = Config.UI.MatchFound.roster

	local function player(userId: number, team: number?): any
		return { userId = userId, name = "P" .. userId, squishy = "toast", level = 3, team = team }
	end

	t.test("the stage fits the whole design: 1 at 1440 x 810, the smaller side's share elsewhere", function()
		expect.near(MatchFoundShow.stageScale(Vector2.new(1440, 810)), 1, 1e-9)
		expect.near(MatchFoundShow.stageScale(Vector2.new(1920, 1080)), 1920 / 1440, 1e-9)
		expect.near(MatchFoundShow.stageScale(Vector2.new(844, 390)), 390 / 810, 1e-9) -- a phone: the height decides
		expect.near(MatchFoundShow.stageScale(Vector2.new(800, 1200)), 800 / 1440, 1e-9)
		expect.truthy(MatchFoundShow.stageScale(Vector2.new(0, 0)) > 0)
	end)

	t.test("DUEL: you on the left against the opponent, VS between", function()
		local order = MatchFoundShow.order({ mode = "1v1", players = { player(9), player(7) } }, 7)
		expect.equal(#order.entries, 2)
		expect.equal(order.entries[1].player.userId, 7)
		expect.equal(order.entries[1].team, 1)
		expect.equal(order.entries[1].from, "left")
		expect.equal(order.entries[2].player.userId, 9)
		expect.equal(order.entries[2].team, 2)
		expect.equal(order.vsAfter, 1)
		expect.equal(order.entries[1].delayMs, ROSTER.startMs)
		expect.equal(order.entries[2].delayMs, ROSTER.startMs)
	end)

	t.test("TEAM: Strawberry left, Blueberry right, the tiles nearest VS first", function()
		local players = {}
		for i = 1, 12 do
			table.insert(players, player(i, if i % 2 == 0 then 2 else 1))
		end
		local order = MatchFoundShow.order({ mode = "tdm", players = players }, 4)
		expect.equal(#order.entries, 12)
		expect.equal(order.vsAfter, 6)
		for i, entry in order.entries do
			expect.equal(entry.team, if i <= 6 then 1 else 2)
			expect.equal(entry.from, if i <= 6 then "left" else "right")
		end
		-- L:1414: left i waits (half - 1 - i) steps, right (i - half): both halves start at the middle.
		expect.equal(order.entries[6].delayMs, ROSTER.startMs)
		expect.equal(order.entries[1].delayMs, ROSTER.startMs + 5 * ROSTER.stepMs)
		expect.equal(order.entries[7].delayMs, ROSTER.startMs)
		expect.equal(order.entries[12].delayMs, ROSTER.startMs + 5 * ROSTER.stepMs)
	end)

	t.test("FREE FOR ALL: you first, every tile popping in order, no VS", function()
		local order = MatchFoundShow.order({ mode = "ffa", players = { player(1), player(2), player(3) } }, 3)
		expect.equal(order.vsAfter, nil)
		expect.equal(order.entries[1].player.userId, 3)
		expect.equal(order.entries[2].player.userId, 1)
		for i, entry in order.entries do
			expect.equal(entry.from, "pop")
			expect.equal(entry.slot, i)
			expect.equal(entry.delayMs, ROSTER.startMs + (i - 1) * ROSTER.stepMs)
		end
	end)

	t.test("the mode chip's gradient: DUEL pink, TEAM red to blue, FREE FOR ALL yellow", function()
		local ffa, ffaRotation = MatchFoundShow.chipGradient("ffa", 90, 24)
		expect.equal(ffa.Keypoints[1].Value, Palette.StickerYellowTop)
		expect.equal(ffa.Keypoints[#ffa.Keypoints].Value, Palette.StickerGoldMid)
		expect.equal(ffaRotation, 90)
		local tdm, tdmRotation = MatchFoundShow.chipGradient("tdm", 90, 24)
		expect.equal(#tdm.Keypoints, 4)
		expect.equal(tdm.Keypoints[1].Value, Palette.StickerTdmRedTop)
		expect.equal(tdm.Keypoints[4].Value, Palette.StickerTdmBlueEnd)
		expect.truthy(tdmRotation > 0 and tdmRotation < 10) -- 100deg on a flat chip: a slight lean
		local duel = MatchFoundShow.chipGradient("1v1", 90, 24)
		expect.equal(duel.Keypoints[1].Value, Palette.StickerPinkTop)
		expect.equal(duel.Keypoints[3].Value, Palette.StickerPinkEnd)
	end)

	t.test("the show builds every part and closes cleanly", function()
		local gui = Instance.new("ScreenGui")
		local done = 0
		local players = {}
		for i = 1, 12 do
			table.insert(players, player(i, if i <= 6 then 1 else 2))
		end
		local show = MatchFoundShow.play({
			layer = gui,
			view = { mode = "tdm", players = players },
			you = 2,
			play = function() end, -- the timeline runs on the Scheduler (Play), not in this Edit-mode test
			ready = function()
				return true
			end,
			onDone = function()
				done += 1
			end,
		})
		local root = show.root
		expect.equal(root.Parent, gui)
		expect.truthy(root:FindFirstChild("Dim") ~= nil)
		local stage = root:FindFirstChild("Stage") :: Frame
		expect.truthy(stage ~= nil)
		local block = stage:FindFirstChild("Block") :: Frame
		local letters = block:FindFirstChild("Letters", true) :: Frame
		local count = 0
		for _, cell in letters:GetChildren() do
			if cell:IsA("Frame") then
				count += 1
			end
		end
		expect.equal(count, #"MATCH FOUND!") -- one cell per character, the space too
		local row = stage:FindFirstChild("Players") :: Frame
		local tiles, vs = 0, 0
		for _, cell in row:GetChildren() do
			if cell:IsA("Frame") then
				if cell.Name == "Vs" then
					vs += 1
				else
					tiles += 1
				end
			end
		end
		expect.equal(tiles, 12)
		expect.equal(vs, 1)
		expect.equal(#root:GetDescendants() > 100, true)
		local you = row:FindFirstChild("You", true)
		expect.truthy(you ~= nil) -- your tile wears YOU
		show:close()
		show:close()
		expect.equal(root.Parent, nil)
		expect.equal(done, 1)
		gui:Destroy()
	end)
end
