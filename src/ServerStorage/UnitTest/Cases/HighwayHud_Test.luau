--!strict
-- HighwayHud_Test: StarterPlayerScripts.Client.UI.HighwayHud (p13v4, SPEC 4.5: the video's throw screen, a stand-in in
-- the sticker look). Server only (ServerStorage.UnitTest); a plain ScreenGui stands in for SD_Highway and a private
-- Scheduler drives the motion.
-- Contract:
--   * zoneText(n): "Zone {n} • {biome name}"; ringsText(hit, total): "RINGS {hit}/{total}";
--   * boostText(fuel, input): the action by input (touch "Tap", mouse "Click", gamepad "Press R2") and the fuel line
--     "SQUISH! x{fuel}", or "NO FUEL" at 0;
--   * barZone(): the PERFECT part of the timing bar, centred, 2 x perfectHalfWidth wide (0..1 of the bar);
--   * the timing bar shows only when asked, its marker at the value; the flight lines show the distance, the zone and
--     the rings while a view is given and hide with nil;
--   * a pop is 1-3 lines; a new pop replaces the old one; it is gone after in + hold + out.
--   * popShift(canvas, height, floor): how far a pop moves down so its top stays under the flight lines (a phone's
--     short canvas puts centreY on them); 0 when it already clears them.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local HighwayHud = t.requireClient("UI/HighwayHud")
	local Scheduler = t.requireClient("Anim/Scheduler")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local S = Strings.highway.screen
	local P = Config.UI.Highway.pop

	local function made(): (any, ScreenGui, any)
		local gui = Instance.new("ScreenGui")
		local scheduler = Scheduler.new(false)
		local hud = HighwayHud.new({
			gui = gui,
			onBoost = function() end,
			scheduler = scheduler,
			scale = function(): number
				return 1
			end,
			compact = function(): boolean
				return false
			end,
			reduced = function(): boolean
				return false
			end,
		})
		return hud, gui, scheduler
	end

	local function pops(gui: ScreenGui): { Instance }
		local found = {}
		for _, d in gui:GetDescendants() do
			if d.Name == "HighwayPop" then
				table.insert(found, d)
			end
		end
		return found
	end

	t.test("zoneText and ringsText", function()
		expect.equal(HighwayHud.zoneText(1), "Zone 1 • " .. Strings.highway.biome.candyMeadow)
		expect.equal(HighwayHud.zoneText(3), "Zone 3 • " .. Strings.highway.biome.bobaLagoon)
		expect.equal(HighwayHud.ringsText(2, 3), "RINGS 2/3")
		expect.equal(S.rings, "RINGS {hit}/{total}")
	end)

	t.test("boostText: the action by input, the fuel or NO FUEL", function()
		local a, f = HighwayHud.boostText(1, Enum.PreferredInput.Touch)
		expect.deepEqual({ a, f }, { S.boost.touch, "SQUISH! x1" })
		a, f = HighwayHud.boostText(1, Enum.PreferredInput.KeyboardAndMouse)
		expect.deepEqual({ a, f }, { S.boost.mouse, "SQUISH! x1" })
		a, f = HighwayHud.boostText(0, Enum.PreferredInput.Gamepad)
		expect.deepEqual({ a, f }, { S.boost.gamepad, S.noFuel })
	end)

	t.test("barZone: the PERFECT part is centred and 2 x perfectHalfWidth wide", function()
		local left, width = HighwayHud.barZone()
		local half = Config.Economy.Highway.timing.perfectHalfWidth
		expect.near(width, 2 * half, 1e-9)
		expect.near(left, 0.5 - half, 1e-9)
		expect.near(left + width / 2, 0.5, 1e-9)
	end)

	t.test("the bar shows when asked with its marker at the value; the flight lines follow the view", function()
		local hud, gui = made()
		local bar = gui:FindFirstChild("HighwayBar", true) :: Frame
		local flight = gui:FindFirstChild("HighwayFlight", true) :: Frame
		expect.equal(bar.Visible, false)
		expect.equal(flight.Visible, false)
		hud:setBar(true, 0.25)
		expect.equal(bar.Visible, true)
		expect.near((bar:FindFirstChild("Marker", true) :: Frame).Position.X.Scale, 0.25, 1e-9)
		hud:setBar(false)
		expect.equal(bar.Visible, false)
		hud:setFlight({ studs = 213, biome = 1, ringsHit = 1, ringsTotal = 3 })
		expect.equal(flight.Visible, true)
		expect.equal((flight:FindFirstChild("Distance", true) :: TextLabel).Text, "213 studs")
		expect.equal((flight:FindFirstChild("Zone", true) :: TextLabel).Text, HighwayHud.zoneText(1))
		expect.equal((flight:FindFirstChild("Rings", true) :: TextLabel).Text, "RINGS 1/3")
		hud:setFlight(nil)
		expect.equal(flight.Visible, false)
		hud:destroy()
		expect.equal(#gui:GetChildren(), 0)
	end)

	t.test("a new pop replaces the old one; a pop is gone after in + hold + out", function()
		local hud, gui, scheduler = made()
		hud:pop({ { text = "PERFECT!", big = true, color = P.colors.perfect } })
		expect.equal(#pops(gui), 1)
		hud:pop({
			{ text = "BULLSEYE!", big = true, color = P.colors.bullseye },
			{ text = "2/3 RINGS", big = false, color = P.colors.rings },
			{ text = "NEW BEST!", big = false, color = P.colors.newBest },
		})
		local shown = pops(gui)
		expect.equal(#shown, 1)
		expect.equal(#shown[1]:GetChildren() >= 3, true)
		local total = (P.inMs + P.holdMs + P.outMs) / 1000
		for _ = 1, math.ceil(total / 0.05) + 2 do
			scheduler:tick("render", 0.05)
		end
		expect.equal(#pops(gui), 0)
		hud:destroy()
	end)

	t.test("popShift: a pop on a phone's short canvas moves under the flight lines; on a PC it stays", function()
		-- A phone at 0.85 UI scale (about 434 base px high): a 2-line pop 118 high, the lines down to 130 + the gap.
		local floor = 130 + P.lineGapPx
		local shift = HighwayHud.popShift(434, 118, floor)
		expect.near(P.centreY * 434 - 118 / 2 + shift, floor, 1e-6)
		expect.equal(HighwayHud.popShift(1080, 138, 184), 0) -- a PC: already well below
	end)
end
