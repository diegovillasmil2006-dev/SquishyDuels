--!strict
-- PhoneHud_Test: StarterPlayerScripts.Client.UI.PhoneHud (Phone HUD B, the owner's pick 2026-10-17). Server only
-- (ServerStorage.UnitTest). The state the HUD drives, with no chip built (no instances):
--   * the popped mode picker opens only on a phone (the compact class) while the DUEL area is idle;
--   * it closes when either ends (the 1v1 search, a PC-sized window), on close() and on a new mode;
--   * without the chip (a player with no picker) nothing shows.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local PhoneHud = t.requireClient("UI/PhoneHud")

	t.test("the popped picker: only on a phone while idle; closed when that ends, by close() and a new mode", function()
		PhoneHud.sync(true, false) -- a PC: the picker shows under DUEL, nothing to pop
		PhoneHud.toggle()
		expect.falsy(PhoneHud.isOpen())
		PhoneHud.sync(true, true) -- a phone, idle
		PhoneHud.toggle()
		expect.truthy(PhoneHud.isOpen())
		PhoneHud.toggle() -- the chip again
		expect.falsy(PhoneHud.isOpen())
		PhoneHud.toggle()
		PhoneHud.sync(false, true) -- the 1v1 search starts
		expect.falsy(PhoneHud.isOpen())
		PhoneHud.sync(true, true) -- and ends: still closed
		expect.falsy(PhoneHud.isOpen())
		PhoneHud.toggle()
		PhoneHud.sync(true, false) -- the window grows past the phone sizes
		expect.falsy(PhoneHud.isOpen())
		PhoneHud.sync(true, true)
		PhoneHud.toggle()
		PhoneHud.close() -- a tap outside, a window opening
		expect.falsy(PhoneHud.isOpen())
		PhoneHud.toggle()
		PhoneHud.setMode("ffa") -- a pick
		expect.falsy(PhoneHud.isOpen())
		expect.equal(PhoneHud.debugState().mode, "ffa")
		-- Without the chip nothing shows.
		expect.equal(PhoneHud.chipSize(), Vector2.zero)
		expect.equal(PhoneHud.chipButton(), nil)
		expect.falsy(PhoneHud.debugState().chip)
		PhoneHud.sync(false, false)
	end)
end
