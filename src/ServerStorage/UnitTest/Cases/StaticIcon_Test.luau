--!strict
-- StaticIcon_Test: the framing maths of StarterPlayerScripts.Client.UI.Components.StaticIcon. Server only
-- (ServerStorage.UnitTest). Pure: StaticIcon.new is never called (no ViewportFrame).
-- Contract (DESIGN §11.1 StaticIcon, §10.5 framing):
--   * the camera direction is in front of the face (-Z) at yaw 0 / pitch 0, turned by the Catalog inspect yaw about
--     +Y and raised by its pitch; it is always a unit vector;
--   * the fit distance frames a sphere of radius r in the vertical FOV with Config.Inspect fitPadding, never closer
--     than r + minClearance; a bad radius counts as 1;
--   * UI FINAL R5: a squishy not owned is the black silhouette at .42 (ownedLook).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local StaticIcon = t.requireClient("UI/Components/StaticIcon")
	local Config = t.requireShared("Config")
	local Catalog = t.requireShared("Catalog")
	local FRAMING = Config.Inspect.Framing

	t.test("viewDirection: in front of the face, turned and raised, unit length", function()
		local front = StaticIcon.viewDirection(0, 0)
		expect.near(front.X, 0, 1e-9)
		expect.near(front.Y, 0, 1e-9)
		expect.near(front.Z, -1, 1e-9)
		local above = StaticIcon.viewDirection(0, 90)
		expect.near(above.Y, 1, 1e-9)
		local side = StaticIcon.viewDirection(90, 0)
		expect.near(side.X, -1, 1e-9)
		expect.near(side.Z, 0, 1e-9)
		for _, def in Catalog.list() do
			local dir = StaticIcon.viewDirection(def.inspect.yaw, def.inspect.pitch)
			expect.near(dir.Magnitude, 1, 1e-6)
			expect.truthy(dir.Y > 0) -- every default view looks from slightly above
			expect.truthy(dir.Z < 0) -- and from the face's side
		end
	end)

	t.test("fitDistance: frames the sphere with padding, keeps the clearance", function()
		local r = 2
		local half = math.rad(FRAMING.vFovDeg) / 2
		local expected = math.max(r / math.sin(half) * FRAMING.fitPadding, r + FRAMING.minClearance)
		expect.near(StaticIcon.fitDistance(r, FRAMING.vFovDeg), expected, 1e-9)
		expect.truthy(StaticIcon.fitDistance(r, FRAMING.vFovDeg) - r >= FRAMING.minClearance)
		expect.near(StaticIcon.fitDistance(0 / 0, FRAMING.vFovDeg), StaticIcon.fitDistance(1, FRAMING.vFovDeg), 1e-9)
		expect.near(StaticIcon.fitDistance(-4, FRAMING.vFovDeg), StaticIcon.fitDistance(1, FRAMING.vFovDeg), 1e-9)
		-- A wide view never brings the camera inside the clearance.
		expect.truthy(StaticIcon.fitDistance(1, 179) >= 1 + FRAMING.minClearance)
	end)

	-- UI FINAL R5 (H:922): not owned = the design's silhouette, brightness(0) opacity(.42).
	t.test("ownedLook: as it is when owned, the black .42 silhouette when not", function()
		local tint, transparency = StaticIcon.ownedLook(true)
		expect.equal(tint, Color3.new(1, 1, 1))
		expect.equal(transparency, 0)
		tint, transparency = StaticIcon.ownedLook(false)
		expect.equal(tint, Color3.new(0, 0, 0))
		expect.near(transparency, 0.58, 1e-9)
	end)
end
