--!strict
-- ScreenHold_Test: StarterPlayerScripts.Client.UI.ScreenHold (p13v4, SPEC 4.4: the creator's note "hide everything for
-- the whole launch"). Server only (ServerStorage.UnitTest); plain ScreenGuis in a Folder stand in for the PlayerGui.
-- Contract:
--   * step() turns off every enabled direct ScreenGui child whose name starts with "SD_" and is not kept, and remembers
--     it; kept ones, other names (Roblox's own TouchGui, chat) and other classes are never touched;
--   * one its owner switched back on during the hold is turned off again at the next step;
--   * release() turns back on exactly the remembered guis that are still off; a gui that was already off before the
--     hold stays off; release twice is a no-op, and a step after release does nothing.
--   * the launch's other hold, UIController.holdToasts(on) (SPEC 4.4, "hold toasts until it lands"): while on, a toast
--     is queued (nothing is built: in Edit mode building one fails); off plays the queue in order through
--     UIController.toast, once; an empty text is never queued.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local ScreenHold = t.requireClient("UI/ScreenHold")
	local UIController = t.requireClient("Controllers/UIController")

	local function world(): (Folder, { [string]: ScreenGui })
		local container = Instance.new("Folder")
		local guis: { [string]: ScreenGui } = {}
		for _, name in { "SD_Hud", "SD_Touch", "SD_Overlay", "SD_Highway", "SD_Viewmodel", "TouchGui", "SD_Off" } do
			local gui = Instance.new("ScreenGui")
			gui.Name = name
			gui.Enabled = name ~= "SD_Off"
			gui.Parent = container
			guis[name] = gui
		end
		local frame = Instance.new("Frame")
		frame.Name = "SD_Frame" -- not a ScreenGui
		frame.Parent = container
		return container, guis
	end

	t.test("step hides the SD_ guis not kept; kept, non-SD_ and other classes stay", function()
		local container, guis = world()
		local hold = ScreenHold.new(container, { SD_Highway = true, SD_Viewmodel = true })
		hold:step()
		expect.equal(guis.SD_Hud.Enabled, false)
		expect.equal(guis.SD_Touch.Enabled, false)
		expect.equal(guis.SD_Overlay.Enabled, false)
		expect.equal(guis.SD_Highway.Enabled, true)
		expect.equal(guis.SD_Viewmodel.Enabled, true)
		expect.equal(guis.TouchGui.Enabled, true)
		expect.equal((container:FindFirstChild("SD_Frame") :: Frame).Visible, true)
		container:Destroy()
	end)

	t.test("a gui its owner switches back on mid-hold is hidden again at the next step", function()
		local container, guis = world()
		local hold = ScreenHold.new(container, {})
		hold:step()
		guis.SD_Hud.Enabled = true
		hold:step()
		expect.equal(guis.SD_Hud.Enabled, false)
		container:Destroy()
	end)

	t.test("release brings back exactly the remembered guis; twice is a no-op; no step after it", function()
		local container, guis = world()
		local hold = ScreenHold.new(container, { SD_Highway = true })
		hold:step()
		hold:release()
		expect.equal(guis.SD_Hud.Enabled, true)
		expect.equal(guis.SD_Touch.Enabled, true)
		expect.equal(guis.SD_Overlay.Enabled, true)
		expect.equal(guis.SD_Off.Enabled, false) -- off before the hold: not ours
		guis.SD_Hud.Enabled = false -- its owner turns it off after the hold
		hold:release()
		expect.equal(guis.SD_Hud.Enabled, false)
		hold:step()
		expect.equal(guis.SD_Touch.Enabled, true)
		container:Destroy()
	end)

	t.test("UIController.holdToasts: toasts wait while held, then play in order through toast, once", function()
		local real = UIController.toast
		UIController.holdToasts(true)
		real("first", "info") -- held: queued, nothing built
		real("", "info") -- an empty text is never queued
		real("second", "warn", { sound = false })
		local played = {}
		UIController.toast = function(text: string, kind: string?, opts: any?)
			table.insert(played, { text, kind or "none", if opts then tostring(opts.sound) else "none" })
		end
		local ok, err = pcall(UIController.holdToasts, false)
		UIController.toast = real
		expect.truthy(ok, tostring(err))
		expect.deepEqual(played, { { "first", "info", "none" }, { "second", "warn", "false" } })
		UIController.toast = function(text: string)
			table.insert(played, { text })
		end
		UIController.holdToasts(false) -- nothing left to play
		UIController.toast = real
		expect.equal(#played, 2)
	end)
end
