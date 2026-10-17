--!strict
-- ConfirmDialog_Test: StarterPlayerScripts.Client.UI.Components.ConfirmDialog, the design's confirm dialog for a coin
-- spend (UI FINAL R6, plan work/ui/PLAN.md R6 PR13; `H:n` = "Squishy Duels HUD.dc.html" line n). Server only
-- (ServerStorage.UnitTest), Edit mode.
-- Contract:
--   * step: BUY spends once, only after the 0.3 s guard (presses inside it are ignored); CANCEL / the scrim / the
--     back handler cancel while open, never while busy; the answer closes it; a closed dialog ignores everything;
--   * balanceText is spend.balanceAfter with the Coins left, never below 0 (§11.5);
--   * fit keeps the card and the medallion inside the margin (k <= 1) and the design's top (the middle - 200) when it
--     fits; flexWidths splits the row 1 : 1.4 around the 12 px gap (H:461-463);
--   * open draws the scrim, the card, the medallion, the title, the description, CANCEL and BUY ("BUY", the coin, the
--     price); the scrim's tap cancels with reason "scrim" and removes it; primary() is BUY.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local ConfirmDialog = t.requireClient("UI/Components/ConfirmDialog")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local C = Config.UI.confirm
	local T0 = 50

	t.test("the design's numbers (H:455-469) and the guard", function()
		expect.equal(C.scrimAlpha, 0.4)
		expect.equal(C.fadeMs, 200)
		expect.equal(C.card.width, 480)
		expect.equal(C.card.shiftY, -200)
		expect.equal(C.card.radius, 30)
		expect.equal(C.card.lip, 10)
		expect.equal(C.medallion.px, 130)
		expect.equal(C.medallion.top, -70)
		expect.equal(C.buttons.face, 62)
		expect.equal(C.buttons.cancelFlex, 1)
		expect.equal(C.buttons.buyFlex, 1.4)
		expect.equal(C.guardMs, 300)
		expect.equal(C.layer.displayOrder, 25)
		for _, spec in Config.UI.ScreenGuis do
			expect.truthy(spec.displayOrder ~= C.layer.displayOrder)
		end
		expect.truthy(C.layer.displayOrder > Config.UI.ScreenGuis.SD_Modal.displayOrder)
	end)

	t.test("step: BUY spends once after the guard; CANCEL only while open; the answer closes it", function()
		local s = ConfirmDialog.initial(T0)
		expect.equal(s.phase, "open")
		local early, a1 = ConfirmDialog.step(s, "buy", T0 + 0.1)
		expect.equal(a1, "ignored") -- a double tap that opened it never spends
		expect.equal(early.phase, "open")
		local busy, a2 = ConfirmDialog.step(s, "buy", T0 + 0.3)
		expect.equal(a2, "buy")
		expect.equal(busy.phase, "busy")
		local again, a3 = ConfirmDialog.step(busy, "buy", T0 + 1)
		expect.equal(a3, "ignored") -- spends once
		expect.equal(again.phase, "busy")
		local stay, a4 = ConfirmDialog.step(busy, "cancel", T0 + 1)
		expect.equal(a4, "ignored") -- nothing cancels while the server answers
		expect.equal(stay.phase, "busy")
		local done, a5 = ConfirmDialog.step(busy, "done", T0 + 2)
		expect.equal(a5, "close")
		expect.equal(done.phase, "closed")
		local cancelled, a6 = ConfirmDialog.step(s, "cancel", T0 + 0.05)
		expect.equal(a6, "cancel") -- CANCEL, the scrim and Backspace / ButtonB work at once
		expect.equal(cancelled.phase, "closed")
		for _, event in { "buy", "cancel", "done" } do
			local _, action = ConfirmDialog.step(cancelled, event :: any, T0 + 5)
			expect.equal(action, "ignored")
		end
		expect.equal(s.phase, "open") -- the input is never changed
	end)

	t.test("balanceText: 'Balance after: {n}' with the Coins left, never below 0", function()
		local function text(n: string): string
			return Strings.format(Strings.spend.balanceAfter, { balance = n })
		end
		expect.equal(ConfirmDialog.balanceText(25000, 10000), text("15,000"))
		expect.equal(ConfirmDialog.balanceText(10000, 10000), text("0"))
		expect.equal(ConfirmDialog.balanceText(500, 10000), text("0"))
		expect.equal(ConfirmDialog.balanceText(0 / 0, 10), text("0"))
	end)

	t.test("fit: the design's top on a desktop; shrunk and kept on screen on a phone", function()
		local cardHeight = 300
		local k, top = ConfirmDialog.fit(Vector2.new(1440, 810), cardHeight)
		expect.equal(k, 1)
		expect.equal(top, 810 / 2 + C.card.shiftY) -- H:457: 200 above the middle
		for _, canvas in { Vector2.new(993, 366), Vector2.new(459, 929), Vector2.new(785, 441) } do
			local kk, tt = ConfirmDialog.fit(canvas, cardHeight)
			expect.truthy(kk <= 1)
			expect.truthy(C.card.width * kk <= canvas.X - 2 * C.margin + 1e-6)
			expect.truthy(tt + C.medallion.top * kk >= C.margin - 0.5) -- the medallion stays on screen
			expect.truthy(tt + cardHeight * kk <= canvas.Y - C.margin + 0.5)
		end
	end)

	t.test("flexWidths: CANCEL 1 and BUY 1.4 around the 12 px gap (H:461-463)", function()
		local cancel, buy = ConfirmDialog.flexWidths(424)
		expect.near(cancel + buy + C.buttons.gap, 424)
		expect.near(buy / cancel, 1.4)
	end)

	t.test("open: the scrim, the card, the medallion, the texts and both buttons; the scrim cancels", function()
		local layer = Instance.new("Frame")
		layer.Size = UDim2.fromOffset(1440, 810)
		local reasons: { string } = {}
		local bought = 0
		local dialog = ConfirmDialog.open({
			layer = layer,
			title = "Toast",
			description = ConfirmDialog.balanceText(25000, 10000),
			price = 10000,
			onBuy = function()
				bought += 1
			end,
			onCancel = function(reason: string)
				table.insert(reasons, reason)
			end,
		})
		local root = dialog.root
		expect.equal(root.Parent, layer)
		expect.truthy(root:FindFirstChild("Scrim") ~= nil)
		local card = root:FindFirstChild("Card", true) :: any
		expect.truthy(card ~= nil)
		expect.equal(card.SelectionGroup, true) -- the gamepad stays inside the card
		expect.truthy(card:FindFirstChild("Medallion") ~= nil)
		expect.equal((card:FindFirstChild("Title", true) :: TextLabel).Text, "Toast")
		expect.equal(
			(card:FindFirstChild("Description", true) :: TextLabel).Text,
			Strings.format(Strings.spend.balanceAfter, { balance = "15,000" })
		)
		expect.equal(dialog.buy.root.Name, "Confirm_BuyButton")
		expect.equal(dialog.cancelButton.root.Name, "Confirm_CancelButton")
		expect.equal(dialog:primary(), dialog.buy.root)
		local word = dialog.buy.visual:FindFirstChild("Word", true) :: TextLabel
		expect.equal(word.Text, "BUY") -- H:464: "BUY", the coin and the price
		expect.truthy(dialog.buy.visual:FindFirstChild("Coin", true) ~= nil)
		expect.equal(dialog:isOpen(), true)
		dialog:cancel("scrim")
		expect.deepEqual(reasons, { "scrim" })
		expect.equal(dialog:isOpen(), false)
		expect.equal(root.Parent, nil)
		dialog:cancel("cancel") -- closed: ignored
		expect.deepEqual(reasons, { "scrim" })
		expect.equal(bought, 0)
		layer:Destroy()
	end)
end
