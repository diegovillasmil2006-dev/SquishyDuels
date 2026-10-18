--!strict
-- HighwayController_Test: StarterPlayerScripts.Client.Controllers.HighwayController (access2, owner 2026-10-18 "Both":
-- a quick button to the highway's launch deck, beside the bridge). Server only (ServerStorage.UnitTest). Edit mode: the
-- remote and the toast are fakes (useDeps).
-- Contract:
--   * goAsync() sends GoHighway() (no argument) once at a time: a press while one is in flight sends nothing more;
--   * an accepted trip shows nothing (the server moves the character); a refusal shows the server's reason as a toast,
--     its text alone (no Coins are ever involved, so never "No Coins were spent");
--   * the HUD's HIGHWAY tile opens the non-modal "highway" screen (HudFormat.NAV): init() registers it (refused in a
--     duel by UIController, lobbyOnly), destroy() takes it away, and the tile only shows while it is registered.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local HighwayController = t.requireClient("Controllers/HighwayController")
	local UIController = t.requireClient("Controllers/UIController")
	local HudFormat = t.requireClient("UI/HudFormat")
	local Strings = t.requireShared("Strings")

	type Calls = { sent: { { name: string, n: number } }, toasts: { { text: string, kind: string? } } }

	local function fake(reply: (calls: Calls) -> any): Calls
		local calls: Calls = { sent = {}, toasts = {} }
		HighwayController.useDeps({
			invoke = function(name: string, ...: any): any
				table.insert(calls.sent, { name = name, n = select("#", ...) })
				return reply(calls)
			end,
			toast = function(text: string, kind: string?)
				table.insert(calls.toasts, { text = text, kind = kind })
			end,
		})
		return calls
	end

	t.test("goAsync sends GoHighway() once at a time; an accepted trip shows nothing", function()
		local inner: boolean? = nil
		local calls = fake(function(): any
			inner = HighwayController.goAsync() -- a second press while the first is in flight
			return { ok = true, data = { charged = false, savePending = false } }
		end)
		expect.equal(HighwayController.goAsync(), true)
		expect.equal(inner, false)
		expect.equal(#calls.sent, 1)
		expect.equal(calls.sent[1].name, "GoHighway")
		expect.equal(calls.sent[1].n, 0)
		expect.equal(#calls.toasts, 0)
		-- Free again afterwards.
		expect.equal(HighwayController.goAsync(), true)
		expect.equal(#calls.sent, 2)
		HighwayController.useDeps(nil)
	end)

	t.test("a refusal shows the server's reason alone (no 'No Coins were spent')", function()
		local calls = fake(function(): any
			return { ok = false, reason = "highway.inQueue", charged = false }
		end)
		expect.equal(HighwayController.goAsync(), false)
		expect.equal(#calls.toasts, 1)
		expect.equal(calls.toasts[1].text, Strings.reasonText("highway.inQueue"))
		expect.equal(calls.toasts[1].kind, "warn")
		expect.equal(string.find(calls.toasts[1].text, Strings.common.noCoinsSpent, 1, true), nil)
		-- A reply without a reason (a timeout) still says something.
		local again = fake(function(): any
			return { ok = false }
		end)
		expect.equal(HighwayController.goAsync(), false)
		expect.equal(again.toasts[1].text, Strings.reasonText("error.generic"))
		HighwayController.useDeps(nil)
	end)

	t.test("init registers the HUD tile's non-modal 'highway' screen; destroy takes it away", function()
		expect.falsy(UIController.isRegistered("highway"))
		HighwayController.init()
		expect.truthy(UIController.isRegistered("highway"))
		-- The tile shows only while the screen is registered (HudController.refreshNav reads visibleNav's rule).
		local shown = HudFormat.visibleNav(UIController.isRegistered)
		local ids = {}
		for _, item in shown do
			ids[item.id] = true
		end
		expect.truthy(ids.highway)
		HighwayController.destroy()
		expect.falsy(UIController.isRegistered("highway"))
	end)
end
