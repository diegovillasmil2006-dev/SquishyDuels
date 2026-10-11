--!strict
-- ConfirmButton_Test: the pure two-step confirm of StarterPlayerScripts.Client.UI.Components.ConfirmButton. Server only
-- (ServerStorage.UnitTest). Pure: ConfirmButton.new is never called (no instances, no LocalPlayer).
-- Contract (DESIGN §11.5, one pattern for boxes, the shop and the Grip trainer):
--   * the first press arms the button: "Confirm: {price} Coins" with "Balance after: {balance}" under it;
--   * a second press inside Config.UI.confirmSeconds confirms (once), otherwise a tick reverts it to idle;
--   * not enough Coins -> disabled with the missing amount (common.needCoins), and a press is denied;
--   * readings: a second press within the double-click guard is ignored; a price change while armed disarms it; a
--     balance change keeps it armed while it still covers the price; loading ignores presses; a caller's disabled
--     reason wins over the missing amount; the input state is never changed (step returns a copy).
-- Texts are compared by value through the test's own Strings copy.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local ConfirmButton = t.requireClient("UI/Components/ConfirmButton")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")

	local WINDOW = Config.UI.confirmSeconds
	local CFG = { confirmSeconds = WINDOW, guardSeconds = 0.3 }
	local T0 = 100

	local function press(state: any, now: number): (any, string?)
		return ConfirmButton.step(state, { kind = "press" }, now, CFG)
	end

	local function needText(missing: string, n: number): string
		local pair = Strings.common.needCoins
		return Strings.format(if n == 1 then pair.one else pair.many, { missing = missing })
	end

	t.test("confirmSeconds is the §11.5 window (3 s)", function()
		expect.equal(WINDOW, 3)
		expect.equal(ConfirmButton.GUARD_SECONDS < WINDOW, true)
	end)

	t.test("initial: idle, whole Coins, nothing missing when the balance covers the price", function()
		local s = ConfirmButton.initial(1200, 3000.9)
		expect.deepEqual(s, { phase = "idle", price = 1200, balance = 3000 })
		local view = ConfirmButton.view(s)
		expect.equal(view.mode, "idle")
		expect.equal(view.buttonState, "normal")
		expect.equal(view.missing, 0)
		expect.equal(view.confirmText, nil)
		expect.equal(view.balanceText, nil)
		-- Bad numbers count as 0 (never negative, never NaN).
		expect.deepEqual(ConfirmButton.initial(0 / 0, -5), { phase = "idle", price = 0, balance = 0 })
	end)

	t.test("the first press arms: Confirm text and the balance after", function()
		local s, action = press(ConfirmButton.initial(1200, 3000), T0)
		expect.equal(action, "arm")
		expect.equal(s.phase, "armed")
		expect.equal(s.armedAt, T0)
		local view = ConfirmButton.view(s)
		expect.equal(view.mode, "armed")
		expect.equal(view.buttonState, "normal")
		expect.equal(view.balanceAfter, 1800)
		expect.equal(view.confirmText, Strings.format(Strings.spend.confirm, { price = "1,200" }))
		expect.equal(view.balanceText, Strings.format(Strings.spend.balanceAfter, { balance = "1,800" }))
		expect.equal(view.confirmText, "Confirm: 1,200 Coins")
		expect.equal(view.balanceText, "Balance after: 1,800")
	end)

	t.test("a second press inside the window confirms once and returns to idle", function()
		local armed = press(ConfirmButton.initial(400, 400), T0)
		local s, action = press(armed, T0 + 1)
		expect.equal(action, "confirm")
		expect.equal(s.phase, "idle")
		expect.equal(s.armedAt, nil)
		-- The balance after an exact spend is 0.
		expect.equal(ConfirmButton.view(armed).balanceAfter, 0)
		-- The next press arms again: one confirm per two presses.
		local _, again = press(s, T0 + 1.5)
		expect.equal(again, "arm")
		-- Just inside the window still confirms.
		local _, late = press(armed, T0 + WINDOW - 0.01)
		expect.equal(late, "confirm")
	end)

	t.test("it reverts after confirmSeconds without a second press", function()
		local armed = press(ConfirmButton.initial(1200, 3000), T0)
		local early, none = ConfirmButton.step(armed, { kind = "tick" }, T0 + WINDOW - 0.1, CFG)
		expect.equal(none, nil)
		expect.equal(early.phase, "armed")
		local s, action = ConfirmButton.step(armed, { kind = "tick" }, T0 + WINDOW, CFG)
		expect.equal(action, "revert")
		expect.equal(s.phase, "idle")
		expect.equal(ConfirmButton.view(s).confirmText, nil)
		-- A press after the window (before the tick ran) arms again instead of confirming.
		local again, pressAction = press(armed, T0 + WINDOW + 0.5)
		expect.equal(pressAction, "arm")
		expect.equal(again.armedAt, T0 + WINDOW + 0.5)
	end)

	t.test("a double click never confirms (the guard)", function()
		local armed = press(ConfirmButton.initial(1200, 3000), T0)
		local s, action = press(armed, T0 + 0.1)
		expect.equal(action, "ignored")
		expect.equal(s.phase, "armed")
		expect.equal(s.armedAt, T0)
		local _, after = press(s, T0 + 0.31)
		expect.equal(after, "confirm")
		-- Without a guard the second press confirms at once.
		local _, unguarded = ConfirmButton.step(armed, { kind = "press" }, T0 + 0.1, { confirmSeconds = WINDOW })
		expect.equal(unguarded, "confirm")
	end)

	t.test("not enough Coins: disabled with the missing amount, and a press is denied", function()
		local s = ConfirmButton.initial(25000, 1300)
		local view = ConfirmButton.view(s)
		expect.equal(view.mode, "needCoins")
		expect.equal(view.buttonState, "disabled")
		expect.equal(view.missing, 23700)
		expect.equal(view.reason, needText("23,700", 23700))
		expect.equal(view.reason, "Need 23,700 more Coins")
		local after, action = press(s, T0)
		expect.equal(action, "denied")
		expect.equal(after.phase, "idle")
		-- One Coin short uses the singular text.
		local one = ConfirmButton.view(ConfirmButton.initial(400, 399))
		expect.equal(one.missing, 1)
		expect.equal(one.reason, needText("1", 1))
		-- Enough Coins: nothing missing, no reason.
		local enough = ConfirmButton.view(ConfirmButton.initial(400, 400))
		expect.equal(enough.missing, 0)
		expect.equal(enough.reason, nil)
		expect.equal(enough.needText, nil)
	end)

	t.test("a balance drop while armed disarms; a balance change that still covers keeps it armed", function()
		local armed = press(ConfirmButton.initial(1200, 3000), T0)
		local richer, none = ConfirmButton.step(armed, { kind = "price", price = 1200, balance = 3500 }, T0 + 1, CFG)
		expect.equal(none, nil)
		expect.equal(richer.phase, "armed")
		expect.equal(ConfirmButton.view(richer).balanceText, "Balance after: 2,300")
		local poorer, action = ConfirmButton.step(armed, { kind = "price", price = 1200, balance = 1000 }, T0 + 1, CFG)
		expect.equal(action, "revert")
		expect.equal(poorer.phase, "idle")
		expect.equal(ConfirmButton.view(poorer).mode, "needCoins")
		expect.equal(ConfirmButton.view(poorer).missing, 200)
	end)

	t.test("a price change while armed disarms it (the player confirms the price they read)", function()
		local armed = press(ConfirmButton.initial(1000, 5000), T0)
		local s, action = ConfirmButton.step(armed, { kind = "price", price = 4000, balance = 5000 }, T0 + 1, CFG)
		expect.equal(action, "revert")
		expect.equal(s.phase, "idle")
		expect.equal(s.price, 4000)
		-- A price change while idle just updates it.
		local idle, idleAction =
			ConfirmButton.step(ConfirmButton.initial(1000, 5000), { kind = "price", price = 4000, balance = 5000 }, T0)
		expect.equal(idleAction, nil)
		expect.equal(idle.price, 4000)
	end)

	t.test("a caller's disabled reason wins over the missing amount and disarms", function()
		local armed = press(ConfirmButton.initial(1200, 3000), T0)
		local s, action = ConfirmButton.step(armed, { kind = "disable", reason = "Saving…" }, T0 + 1, CFG)
		expect.equal(action, "revert")
		local view = ConfirmButton.view(s)
		expect.equal(view.mode, "blocked")
		expect.equal(view.buttonState, "disabled")
		expect.equal(view.reason, "Saving…")
		local _, pressAction = press(s, T0 + 1.5)
		expect.equal(pressAction, "denied")
		-- Short of Coins too: the caller's reason is shown.
		local short =
			ConfirmButton.step(ConfirmButton.initial(5000, 0), { kind = "disable", reason = "Locked" }, T0, CFG)
		expect.equal(ConfirmButton.view(short).reason, "Locked")
		expect.equal(ConfirmButton.view(short).missing, 5000)
		-- Disabled with no reason line, then enabled again.
		local plain = ConfirmButton.step(ConfirmButton.initial(10, 100), { kind = "disable" }, T0, CFG)
		expect.equal(plain.blocked, "")
		expect.equal(ConfirmButton.view(plain).reason, nil)
		expect.equal(ConfirmButton.view(plain).buttonState, "disabled")
		local enabled = ConfirmButton.step(plain, { kind = "enable" }, T0, CFG)
		expect.equal(enabled.blocked, nil)
		expect.equal(ConfirmButton.view(enabled).mode, "idle")
	end)

	t.test("loading ignores presses and shows the spinner state until it is turned off", function()
		local armed = press(ConfirmButton.initial(1200, 3000), T0)
		local loading = ConfirmButton.step(armed, { kind = "loading", on = true }, T0 + 1, CFG)
		expect.equal(loading.phase, "loading")
		expect.equal(loading.armedAt, nil)
		expect.equal(ConfirmButton.view(loading).buttonState, "loading")
		local same, action = press(loading, T0 + 1.2)
		expect.equal(action, "ignored")
		expect.equal(same.phase, "loading")
		-- Loading wins over a disabled reason and over missing Coins.
		local short = ConfirmButton.step(ConfirmButton.initial(5000, 0), { kind = "loading", on = true }, T0, CFG)
		expect.equal(ConfirmButton.view(short).mode, "loading")
		local off = ConfirmButton.step(loading, { kind = "loading", on = false }, T0 + 2, CFG)
		expect.equal(off.phase, "idle")
		-- Turning loading off on an idle button changes nothing.
		local idle = ConfirmButton.step(ConfirmButton.initial(1, 1), { kind = "loading", on = false }, T0, CFG)
		expect.equal(idle.phase, "idle")
	end)

	t.test("reset clears an arm and loading but keeps the price, balance and disabled reason", function()
		local armed = press(ConfirmButton.initial(1200, 3000), T0)
		local s, action = ConfirmButton.step(armed, { kind = "reset" }, T0 + 1, CFG)
		expect.equal(action, "revert")
		expect.deepEqual(s, { phase = "idle", price = 1200, balance = 3000 })
		local blocked = ConfirmButton.step(ConfirmButton.initial(1, 1), { kind = "disable", reason = "x" }, T0, CFG)
		local loading = ConfirmButton.step(blocked, { kind = "loading", on = true }, T0, CFG)
		local cleared, none = ConfirmButton.step(loading, { kind = "reset" }, T0, CFG)
		expect.equal(none, nil)
		expect.equal(cleared.phase, "idle")
		expect.equal(cleared.blocked, "x")
	end)

	t.test("step never changes the state it was given", function()
		local s = ConfirmButton.initial(1200, 3000)
		local armed = press(s, T0)
		expect.deepEqual(s, { phase = "idle", price = 1200, balance = 3000 })
		ConfirmButton.step(armed, { kind = "press" }, T0 + 1, CFG)
		ConfirmButton.step(armed, { kind = "price", price = 1, balance = 0 }, T0 + 1, CFG)
		expect.deepEqual(armed, { phase = "armed", price = 1200, balance = 3000, armedAt = T0 })
	end)

	t.test("a tick on an idle button does nothing", function()
		local s, action = ConfirmButton.step(ConfirmButton.initial(1, 1), { kind = "tick" }, T0 + 99, CFG)
		expect.equal(action, nil)
		expect.equal(s.phase, "idle")
	end)
end
