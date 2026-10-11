--!strict
-- ViewportStage_Test: the pure maths of StarterPlayerScripts.Client.UI.ViewportStage (the shared Inspect / box reveal
-- stage). Server only (ServerStorage.UnitTest). Pure: ViewportStage.get() is never called (no ViewportFrame).
-- Contract (DESIGN §10.5):
--   * fitDistance: r = size.Magnitude/2 × squeezeWidening; hFov = 2·atan(tan(vFov/2)·aspect); fitDist =
--     r / sin(min(vFov, hFov)/2) × fitPadding, never closer than r + minClearance; a narrow frame (aspect < 1) moves the
--     camera back, a wide one does not move it closer than the vertical fit; bad inputs fall back (r = 1, aspect 1);
--   * orbitCFrame: the camera sits `dist` from the centre and looks at it; yaw 0 / pitch 0 is in front of the face
--     (the pivot's -Z), a positive yaw turns to the model's own left (-X), a positive pitch looks from above; it follows
--     the pivot's rotation; the camera stays upright;
--   * projectPoint: the centre of the view is (0.5, 0.5), a point at the edge of the horizontal FOV is at x = 1, a
--     point above is higher (smaller y), a point behind the camera is nil;
--   * lightDirection: Config.Inspect's key light turned with the camera (camera-locked), unit length.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local ViewportStage = t.requireClient("UI/ViewportStage")
	local Config = t.requireShared("Config")
	local FRAMING = Config.Inspect.Framing
	local LIGHTING = Config.Inspect.Lighting

	local function near3(a: Vector3, b: Vector3, tolerance: number?)
		local tol = tolerance or 1e-4
		expect.near(a.X, b.X, tol)
		expect.near(a.Y, b.Y, tol)
		expect.near(a.Z, b.Z, tol)
	end

	t.test("fitDistance: §10.5 formula with the squeeze widening, padding and clearance", function()
		local size = Vector3.new(1.4, 1.2, 1.2)
		local r = size.Magnitude / 2 * FRAMING.squeezeWidening
		local vFov = math.rad(FRAMING.vFovDeg)
		-- Square frame: hFov == vFov.
		local expected = r / math.sin(vFov / 2) * FRAMING.fitPadding
		local distance, radius = ViewportStage.fitDistance(size, FRAMING.vFovDeg, 1, FRAMING)
		expect.near(radius, r, 1e-9)
		expect.near(distance, expected, 1e-6)
		expect.truthy(distance - radius >= FRAMING.minClearance)
		-- Narrow (portrait) frame: the horizontal FOV is the smaller one and the camera moves back.
		local hFov = 2 * math.atan(math.tan(vFov / 2) * 0.5)
		local narrow = ViewportStage.fitDistance(size, FRAMING.vFovDeg, 0.5, FRAMING)
		expect.near(narrow, r / math.sin(hFov / 2) * FRAMING.fitPadding, 1e-6)
		expect.truthy(narrow > distance)
		-- Wide frame: min(vFov, hFov) = vFov, so the distance is the vertical fit.
		expect.near(ViewportStage.fitDistance(size, FRAMING.vFovDeg, 2.5, FRAMING), distance, 1e-6)
		-- The default config is Config.Inspect.Framing.
		expect.near(ViewportStage.fitDistance(size, FRAMING.vFovDeg, 1), distance, 1e-9)
	end)

	t.test("fitDistance: bad inputs fall back, the clearance always holds", function()
		local _, unitRadius = ViewportStage.fitDistance(Vector3.zero, FRAMING.vFovDeg, 1, FRAMING)
		expect.equal(unitRadius, 1)
		local good = ViewportStage.fitDistance(Vector3.new(2, 2, 2), FRAMING.vFovDeg, 1, FRAMING)
		expect.near(ViewportStage.fitDistance(Vector3.new(2, 2, 2), FRAMING.vFovDeg, 0 / 0, FRAMING), good, 1e-9)
		expect.near(ViewportStage.fitDistance(Vector3.new(2, 2, 2), FRAMING.vFovDeg, -3, FRAMING), good, 1e-9)
		local cfg = { squeezeWidening = 1, fitPadding = 0.01, minClearance = 5 }
		local close, r = ViewportStage.fitDistance(Vector3.new(2, 0, 0), 170, 1, cfg)
		expect.near(close, r + 5, 1e-9)
	end)

	t.test("orbitCFrame: yaw 0 / pitch 0 looks at the face from `dist` away", function()
		local center = Vector3.new(3, 1, -2)
		local cf = ViewportStage.orbitCFrame(center, CFrame.identity, 0, 0, 5)
		near3(cf.Position, center + Vector3.new(0, 0, -5))
		near3(cf.LookVector, Vector3.new(0, 0, 1))
		expect.near((cf.Position - center).Magnitude, 5, 1e-6)
		-- Upright: the camera's up has no sideways lean.
		expect.near(cf.RightVector.Y, 0, 1e-6)
		expect.truthy(cf.UpVector.Y > 0)
	end)

	t.test("orbitCFrame: positive yaw = the model's own left, positive pitch = from above", function()
		local center = Vector3.zero
		local left = ViewportStage.orbitCFrame(center, CFrame.identity, 90, 0, 4)
		near3(left.Position, Vector3.new(-4, 0, 0))
		local above = ViewportStage.orbitCFrame(center, CFrame.identity, 0, 30, 4)
		expect.truthy(above.Position.Y > 0)
		near3(above.Position, Vector3.new(0, 4 * math.sin(math.rad(30)), -4 * math.cos(math.rad(30))))
		near3(above.LookVector, (center - above.Position).Unit)
		-- Same direction as the static icons (StaticIcon.viewDirection), for every Catalog default view.
		local StaticIcon = t.requireClient("UI/Components/StaticIcon")
		for _, def in t.requireShared("Catalog").list() do
			local cf = ViewportStage.orbitCFrame(center, CFrame.identity, def.inspect.yaw, def.inspect.pitch, 1)
			near3(cf.Position, StaticIcon.viewDirection(def.inspect.yaw, def.inspect.pitch))
		end
	end)

	t.test("orbitCFrame: follows the pivot's rotation", function()
		local pivot = CFrame.Angles(0, math.rad(90), 0) -- the face now looks along -X
		local cf = ViewportStage.orbitCFrame(Vector3.zero, pivot, 0, 0, 2)
		near3(cf.Position, pivot.LookVector * 2)
		near3(cf.LookVector, -pivot.LookVector)
		-- A bad distance counts as 1; yaw wraps.
		local one = ViewportStage.orbitCFrame(Vector3.zero, CFrame.identity, 0, 0, 0 / 0)
		expect.near(one.Position.Magnitude, 1, 1e-6)
		near3(
			ViewportStage.orbitCFrame(Vector3.zero, CFrame.identity, 370, 0, 2).Position,
			ViewportStage.orbitCFrame(Vector3.zero, CFrame.identity, 10, 0, 2).Position
		)
	end)

	t.test("projectPoint: centre, horizontal edge, above, behind", function()
		local cam = CFrame.lookAt(Vector3.new(0, 0, 10), Vector3.zero)
		local vFov, aspect = 30, 2
		local centre = ViewportStage.projectPoint(cam, vFov, aspect, Vector3.zero)
		expect.near(centre.X, 0.5, 1e-6)
		expect.near(centre.Y, 0.5, 1e-6)
		local tanH = math.tan(math.rad(vFov) / 2) * aspect
		local edge =
			ViewportStage.projectPoint(cam, vFov, aspect, cam:PointToWorldSpace(Vector3.new(10 * tanH, 0, -10)))
		expect.near(edge.X, 1, 1e-6)
		expect.near(edge.Y, 0.5, 1e-6)
		local up = ViewportStage.projectPoint(cam, vFov, aspect, cam:PointToWorldSpace(Vector3.new(0, 1, -10)))
		expect.truthy(up.Y < 0.5)
		expect.equal(ViewportStage.projectPoint(cam, vFov, aspect, cam:PointToWorldSpace(Vector3.new(0, 0, 3))), nil)
	end)

	t.test("lightDirection: the key light is camera-locked and unit length", function()
		local a = CFrame.identity
		local b = CFrame.Angles(0, math.rad(120), 0)
		local la = ViewportStage.lightDirection(a)
		local lb = ViewportStage.lightDirection(b)
		near3(la, LIGHTING.lightDirection.Unit)
		near3(lb, (b:VectorToWorldSpace(LIGHTING.lightDirection.Unit)))
		expect.near(lb.Magnitude, 1, 1e-6)
		-- In camera space it is always the same direction.
		near3((b:VectorToObjectSpace(lb)), LIGHTING.lightDirection.Unit)
		near3(ViewportStage.lightDirection(a, Vector3.zero), LIGHTING.lightDirection.Unit)
	end)
end
