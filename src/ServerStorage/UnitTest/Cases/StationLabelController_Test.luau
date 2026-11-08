--!strict
-- StationLabelController_Test: unit tests for StarterPlayerScripts.Client.Controllers.StationLabelController (owner
-- 2026-11-08: the floating names over the hub's stations). Server only (ServerStorage.UnitTest). Edit mode: start() is
-- never called; build() runs on a fake hub and a host part that is never parented to the place.
-- Contract (Config.UI.StationLabels):
--   * every station's textKey resolves to a name in Strings;
--   * one BillboardGui per station the hub has, in Config order (a missing one is skipped), each on its own
--     Attachment over the station's centre, liftStuds + half the label's height over its top;
--   * Size = sizeStuds (scale) + minPx (offset), not AlwaysOnTop, LightInfluence 0, MaxDistance maxStuds;
--   * white display text (Palette.StationLabelText) with a dark UIStroke (StationLabelStroke, strokePx).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local StationLabels = t.requireClient("Controllers/StationLabelController")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local Strings = t.requireShared("Strings")
	local L = Config.UI.StationLabels

	-- A hub holding a one-part Model per name, each part `size` big at `at`.
	local function fakeHub(names: { string }, at: Vector3, size: Vector3): Folder
		local hub = Instance.new("Folder")
		for _, name in names do
			local model = Instance.new("Model")
			model.Name = name
			local part = Instance.new("Part")
			part.Size = size
			part.CFrame = CFrame.new(at)
			part.Parent = model
			model.Parent = hub
		end
		return hub
	end

	local function allNames(): { string }
		local names = {}
		for _, station in L.stations do
			table.insert(names, station.model)
		end
		return names
	end

	t.test("every station's text key has a name in Strings", function()
		for _, station in L.stations do
			local text = Strings.resolve(station.textKey)
			expect.truthy(type(text) == "string" and #text > 0)
		end
	end)

	t.test("one label per station, in Config order, with its name", function()
		local hub = fakeHub(allNames(), Vector3.zero, Vector3.one)
		local host = Instance.new("Part")
		local guis = StationLabels.build(hub, host)
		expect.equal(#guis, #L.stations)
		for i, gui in guis do
			local label = gui:FindFirstChildOfClass("TextLabel")
			expect.truthy(label)
			expect.equal((label :: TextLabel).Text, Strings.resolve(L.stations[i].textKey))
		end
		hub:Destroy()
		host:Destroy()
	end)

	t.test("a station the hub lacks is skipped", function()
		local hub = fakeHub({ L.stations[1].model }, Vector3.zero, Vector3.one)
		local host = Instance.new("Part")
		expect.equal(#StationLabels.build(hub, host), 1)
		hub:Destroy()
		host:Destroy()
	end)

	t.test("the label floats over the station's centre, liftStuds over its top", function()
		local hub = fakeHub({ L.stations[1].model }, Vector3.new(10, 5, -3), Vector3.new(4, 6, 4))
		local host = Instance.new("Part") -- at the origin, so the Attachment's Position is its world point
		local gui = StationLabels.build(hub, host)[1]
		local anchor = gui.Parent :: Attachment
		expect.truthy(anchor:IsA("Attachment"))
		expect.near(anchor.Position.X, 10)
		expect.near(anchor.Position.Z, -3)
		expect.near(anchor.Position.Y, 5 + 3 + L.liftStuds + L.sizeStuds.Y / 2)
		hub:Destroy()
		host:Destroy()
	end)

	t.test("size, distance and look", function()
		local hub = fakeHub({ L.stations[1].model }, Vector3.zero, Vector3.one)
		local host = Instance.new("Part")
		local gui = StationLabels.build(hub, host)[1]
		expect.equal(gui.Size, UDim2.new(L.sizeStuds.X, L.minPx.X, L.sizeStuds.Y, L.minPx.Y))
		expect.falsy(gui.AlwaysOnTop)
		expect.equal(gui.LightInfluence, 0)
		expect.equal(gui.MaxDistance, L.maxStuds)
		local label = gui:FindFirstChildOfClass("TextLabel")
		expect.truthy(label)
		if label then
			expect.truthy(label.TextScaled)
			expect.equal(label.TextColor3, Palette.StationLabelText)
			local stroke = label:FindFirstChildOfClass("UIStroke")
			expect.truthy(stroke)
			if stroke then
				expect.equal(stroke.Color, Palette.StationLabelStroke)
				expect.equal(stroke.Thickness, L.strokePx)
			end
		end
		hub:Destroy()
		host:Destroy()
	end)
end
