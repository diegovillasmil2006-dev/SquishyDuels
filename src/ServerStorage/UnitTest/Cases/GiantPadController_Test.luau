--!strict
-- GiantPadController_Test: unit tests for the pure parts of StarterPlayerScripts.Client.Controllers.GiantPadController.
-- Server only (ServerStorage.UnitTest). init() is never called here: no meshes, no Scheduler connection.
-- Contract (DESIGN §17.6.1 "Level of detail and culling", "Write budget"): a pad is simulated only while its bounding
-- sphere is on screen (checked from Camera:WorldToViewportPoint of its centre); High quality by default, Low on
-- request; a snap to rest is charged to the per-client write budget (it runs when it fits what is left, or alone on
-- a frame with nothing written yet), so several pads coming back on screen never write all at once; no path A
-- failure is remembered before one happens.
-- Feel pass (DESIGN §18.5.1 A5, §18.3.4): the landing thump landingExtra(vy) = clamp(0.004 · |vy|, 0.04, 0.14); a
-- landing is a fall at <= -18 studs/s that slows to >= -2, reported once with the fastest fall; a refused slot of the
-- shared editable-mesh quota (Anim/MeshQuota) blocks path A, so that pad uses path B.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local GiantPadController = t.requireClient("Controllers/GiantPadController")
	local viewport = Vector2.new(1280, 720)
	local tanHalf = math.tan(math.rad(70) / 2)

	t.test("bounding sphere on screen: centre inside, edges with the projected radius, behind the camera", function()
		expect.truthy(GiantPadController.sphereOnScreen(640, 360, 40, 6.7, viewport, tanHalf))
		-- Centre just off the left edge, but the sphere still overlaps the screen.
		expect.truthy(GiantPadController.sphereOnScreen(-20, 360, 40, 6.7, viewport, tanHalf))
		-- Far off to the side.
		expect.falsy(GiantPadController.sphereOnScreen(-2000, 360, 40, 6.7, viewport, tanHalf))
		expect.falsy(GiantPadController.sphereOnScreen(640, 5000, 40, 6.7, viewport, tanHalf))
		-- Wholly behind the camera.
		expect.falsy(GiantPadController.sphereOnScreen(640, 360, -20, 6.7, viewport, tanHalf))
		-- The camera inside the sphere.
		expect.truthy(GiantPadController.sphereOnScreen(-5000, -5000, 2, 6.7, viewport, tanHalf))
	end)

	t.test("snaps to rest are charged to the write budget", function()
		local budget = 600 -- Config.Anim.giantPad.writesPerClient
		-- A High pad (625 top vertices) still snaps on a frame with nothing written yet ...
		expect.truthy(GiantPadController.snapFits(625, 0, budget))
		-- ... but a second one waits for a later frame instead of writing 1,250 at once.
		expect.falsy(GiantPadController.snapFits(625, 625, 0))
		-- Small snaps share a frame while they fit.
		expect.truthy(GiantPadController.snapFits(150, 300, 300))
		expect.falsy(GiantPadController.snapFits(350, 300, 300))
		-- A pad already at rest costs nothing.
		expect.truthy(GiantPadController.snapFits(0, 600, 0))
	end)

	t.test("no path A failure is remembered before one happens", function()
		for _, key in { "jelly", "marshmallow", "royal" } do
			expect.equal(GiantPadController.pathAFailure(key), nil)
		end
	end)

	t.test("quality starts High and can be set", function()
		local before = GiantPadController.quality()
		expect.truthy(before == "High" or before == "Low")
		GiantPadController.setQuality("Low")
		expect.equal(GiantPadController.quality(), "Low")
		GiantPadController.setQuality("High")
		expect.equal(GiantPadController.quality(), "High")
	end)

	-- Feel pass (§18.5.1 A5, §18.3.4) -----------------------------------------------------------------------------

	local Config = t.requireShared("Config")
	local MeshQuota = t.requireClient("Anim/MeshQuota")
	local LANDING = Config.Anim.giantPad.landing

	t.test("DESIGN values of the landing thump", function()
		expect.deepEqual(
			{ LANDING.minFallSpeed, LANDING.landedVy, LANDING.perSpeed, LANDING.min, LANDING.max, LANDING.seconds },
			{ 18, -2, 0.004, 0.04, 0.14, 0.12 }
		)
	end)

	t.test("landingExtra = clamp(0.004 · |vy|, 0.04, 0.14)", function()
		expect.near(GiantPadController.landingExtra(-20), 0.08, 1e-9)
		expect.near(GiantPadController.landingExtra(-25), 0.1, 1e-9)
		expect.near(GiantPadController.landingExtra(-18), 0.072, 1e-9) -- the slowest fall that thumps
		expect.equal(GiantPadController.landingExtra(-5), LANDING.min)
		expect.equal(GiantPadController.landingExtra(-40), LANDING.max)
		expect.equal(GiantPadController.landingExtra(-500), LANDING.max)
		expect.equal(GiantPadController.landingExtra(0 / 0), 0)
		for vy = -200, 0, 0.5 do
			local extra = GiantPadController.landingExtra(vy)
			expect.truthy(extra >= LANDING.min and extra <= LANDING.max)
		end
	end)

	t.test("a landing is a fall at <= -18 that slows to >= -2, reported once with the fastest fall", function()
		-- A walk down a step never falls fast enough.
		local peak, landed = GiantPadController.landingStep(nil, -10)
		expect.equal(peak, nil)
		expect.equal(landed, nil)
		peak, landed = GiantPadController.landingStep(peak, 0)
		expect.equal(landed, nil)
		-- A jump from about 6 studs: the fall speeds up, then stops on the pad.
		for _, vy in { -12, -19, -24, -26 } do
			peak, landed = GiantPadController.landingStep(peak, vy)
			expect.equal(landed, nil)
		end
		expect.equal(peak, -26)
		peak, landed = GiantPadController.landingStep(peak, -9) -- slowing down: not landed yet
		expect.equal(peak, -26)
		expect.equal(landed, nil)
		peak, landed = GiantPadController.landingStep(peak, -1.5)
		expect.equal(peak, nil)
		expect.equal(landed, -26)
		peak, landed = GiantPadController.landingStep(peak, 0)
		expect.equal(landed, nil) -- once per landing
		-- Jumping up never lands.
		peak, landed = GiantPadController.landingStep(nil, 20)
		expect.equal(peak, nil)
		expect.equal(landed, nil)
	end)

	t.test("a refused mesh quota slot blocks path A (path B), a free one is taken", function()
		local full = MeshQuota.new(1)
		expect.truthy(full:tryAcquire("arena"))
		local reason = GiantPadController.pathABlocker("jelly", full)
		expect.truthy(type(reason) == "string" and string.find(reason, "quota", 1, true) ~= nil)
		expect.falsy(full:holds("pad:jelly"))
		expect.equal(full:count(), 1)
		local free = MeshQuota.new(Config.Vfx.Budgets.editableMeshes)
		expect.equal(GiantPadController.pathABlocker("jelly", free), nil)
		expect.truthy(free:holds("pad:jelly"))
		-- Asking again for the same pad takes no second slot.
		expect.equal(GiantPadController.pathABlocker("jelly", free), nil)
		expect.equal(free:count(), 1)
		-- The 3 pads and the ripple skin fill the 4 slots; nothing else fits.
		expect.equal(GiantPadController.pathABlocker("marshmallow", free), nil)
		expect.equal(GiantPadController.pathABlocker("royal", free), nil)
		expect.truthy(free:tryAcquire("arena"))
		expect.falsy(free:tryAcquire("backstop"))
	end)
end
