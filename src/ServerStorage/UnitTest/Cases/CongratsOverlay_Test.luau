--!strict
-- CongratsOverlay_Test: StarterPlayerScripts.Client.UI.CongratsOverlay, the design's congratulations overlay after a
-- squishy buy (UI FINAL R6, plan work/ui/PLAN.md R6 G6.8, G6.9; `H:n` = "Squishy Duels HUD.dc.html" line n). Server
-- only (ServerStorage.UnitTest), Edit mode.
-- Contract: the letters of "CONGRATULATIONS!" slam in .05 + .035 i s apart (H:1005); the row shrinks to fit a narrow
-- screen (never grows); the timings are the design's (H:537-547, H:878); show draws the background, the 16 letters,
-- the icon holder, "You got", the title, the description and AWESOME! (Shop_AwesomeButton); a close plays ui.pop once
-- and a second close does nothing.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local CongratsOverlay = t.requireClient("UI/CongratsOverlay")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local CG = Config.UI.Shop.congrats

	t.test("letters: one per character of CONGRATULATIONS!, .05 + .035 i s apart (H:1005)", function()
		expect.equal(Strings.shop.congratsTitle, "CONGRATULATIONS!")
		local letters = CongratsOverlay.letters(Strings.shop.congratsTitle)
		expect.equal(#letters, 16)
		expect.equal(letters[1].char, "C")
		expect.equal(letters[16].char, "!")
		for i, letter in letters do
			expect.near(letter.delayS, 0.05 + 0.035 * (i - 1))
		end
	end)

	t.test("fitScale: 1 while the row fits the screen less the margins, else smaller", function()
		expect.equal(CongratsOverlay.fitScale(900, 1440), 1)
		expect.near(CongratsOverlay.fitScale(900, 459), (459 - 2 * CG.margin) / 900)
		expect.equal(CongratsOverlay.fitScale(0, 459), 1)
		expect.equal(CongratsOverlay.fitScale(900, 0), 1)
	end)

	t.test("the design's timings (H:537-547, H:878)", function()
		expect.equal(CG.fadeMs, 300)
		expect.equal(CG.letters.slamMs, 600)
		expect.equal(CG.icon.revealDelayS, 0.55)
		expect.equal(CG.icon.floatDelayS, 1.2)
		expect.deepEqual(
			{ CG.youGot.delayS, CG.title.delayS, CG.desc.delayS, CG.button.delayS },
			{ 0.9, 1.0, 1.1, 1.25 }
		)
		expect.equal(CG.button.radius, 20)
		expect.equal(CG.closeMs, 220)
		expect.equal(CG.removeMs, 210)
		expect.truthy(CG.removeMs < CG.closeMs)
	end)

	t.test("show: every part of the overlay; a close plays ui.pop once", function()
		local layer = Instance.new("Frame")
		layer.Size = UDim2.fromOffset(1440, 810)
		local sounds: { string } = {}
		local overlay = CongratsOverlay.show({
			layer = layer,
			title = "Toast",
			description = "Common · x16 power",
			sound = function(key: string)
				table.insert(sounds, key)
			end,
		})
		local root = overlay.root
		expect.equal(root.Parent, layer)
		expect.truthy(root:FindFirstChild("Background") ~= nil)
		local column = root:FindFirstChild("Column") :: Frame
		local letters = column:FindFirstChild("Letters") :: Frame
		local count = 0
		for _, child in letters:GetChildren() do
			if child:IsA("Frame") then
				count += 1
			end
		end
		expect.equal(count, 16)
		-- Found by playing (2026-10-17): a wrapping letter a pixel wider than its slot drew nothing (CO G ATU ATIO !).
		for _, text in letters:GetDescendants() do
			if text:IsA("TextLabel") then
				expect.equal(text.TextWrapped, false)
			end
		end
		expect.truthy(column:FindFirstChild("Icon") ~= nil)
		expect.equal((column:FindFirstChild("YouGot") :: any).Pose.Text.Text, Strings.shop.youGot)
		expect.equal((column:FindFirstChild("Title") :: any).Pose.Text.Text, "Toast")
		expect.equal((column:FindFirstChild("Description") :: any).Pose.Text.Text, "Common · x16 power")
		expect.equal(overlay.button.root.Name, "Shop_AwesomeButton")
		expect.equal(overlay:isOpen(), true)
		overlay:close()
		overlay:close()
		expect.deepEqual(sounds, { "ui.pop" })
		expect.equal(overlay:isOpen(), false)
		overlay:destroy()
		layer:Destroy()
	end)
end
