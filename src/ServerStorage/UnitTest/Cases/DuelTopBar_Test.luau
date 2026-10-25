--!strict
-- DuelTopBar_Test: unit tests for StarterPlayerScripts.Client.UI.DuelTopBar. Server only (ServerStorage.UnitTest).
-- Contract (Duel HUD part 3, 2026-10-24; D = "Squishy Duels Duel HUD.dc.html"): the scores are the lives each one took
-- (a duel won at the lives, owner: "Keep 3 lives"); the timer turns pink at 10 s or less, only while live (D:416);
-- SQUISHED while the hit invulnerability runs; the bar builds both forms and draws the info it is given.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local DuelTopBar = t.requireClient("UI/DuelTopBar")
	local expect = t.expect

	t.test("scores: the lives each one took from the other, never below 0", function()
		local you, foe = DuelTopBar.scores(3, 3, 3)
		expect.equal(you, 0)
		expect.equal(foe, 0)
		you, foe = DuelTopBar.scores(2, 1, 3)
		expect.equal(you, 2)
		expect.equal(foe, 1)
		you, foe = DuelTopBar.scores(5, 4, 3)
		expect.equal(you, 0)
		expect.equal(foe, 0)
	end)

	t.test("timerLow: 10 s or less while Active or SuddenDeath only", function()
		expect.truthy(DuelTopBar.timerLow("Active", 110, 100))
		expect.falsy(DuelTopBar.timerLow("Active", 110.5, 100))
		expect.truthy(DuelTopBar.timerLow("SuddenDeath", 105, 100))
		expect.falsy(DuelTopBar.timerLow("Countdown", 101, 100))
	end)

	t.test("squished: while the hit invulnerability runs", function()
		expect.truthy(DuelTopBar.squished(101, 100))
		expect.falsy(DuelTopBar.squished(100, 100))
		expect.falsy(DuelTopBar.squished(nil, 100))
	end)

	t.test("the bar draws both forms: scores, timer, first-to label, names", function()
		local holder = Instance.new("Frame")
		local bar = DuelTopBar.new(holder)
		local function info(form: string): any
			return {
				form = form,
				scale = 0.5,
				you = { userId = -1, name = "Me", squishyId = "dragon", score = 2, squished = true },
				foe = { userId = -2, name = "Them", squishyId = "bird", score = 1, squished = false },
				timer = "0:09",
				timerLow = true,
				target = 3,
			}
		end
		bar:update(info("desk"))
		local canvas = bar.root:FindFirstChild("Canvas") :: Frame
		expect.equal((canvas:FindFirstChild("YouScore") :: any).Number.Text, "2")
		expect.equal((canvas:FindFirstChild("FoeScore") :: any).Number.Text, "1")
		expect.equal((canvas:FindFirstChild("Timer") :: any).Number.Text, "0:09")
		expect.equal((canvas:FindFirstChild("FirstTo") :: any).Text, "First to 3!")
		expect.equal(bar.root.Size, UDim2.fromOffset(468, 93))
		bar:update(info("phone"))
		canvas = bar.root:FindFirstChild("Canvas") :: Frame
		expect.equal((canvas:FindFirstChild("FirstTo") :: any).Text, "FIRST TO 3")
		expect.equal(bar.root.Size, UDim2.fromOffset(174, 26))
		bar:destroy()
		holder:Destroy()
	end)
end
