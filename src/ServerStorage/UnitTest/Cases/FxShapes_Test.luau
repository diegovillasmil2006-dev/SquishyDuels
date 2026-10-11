--!strict
-- FxShapes_Test: unit tests for StarterPlayerScripts.Client.Anim.FxShapes. Edit mode: the ring runs on a private
-- FxPool under an unparented Folder (nothing enters the place), a manual Scheduler and a FakeClock.
-- Contract (DESIGN §18.4 FxShapes, §18.3.6):
--   * ring(position, normal, diameter, seconds, color, transparencyFrom?): a flat ellipsoid grown 0 -> diameter
--     (Quad Out) while its Transparency goes transparencyFrom (default Hit.ringTransparencyFrom) -> 1;
--   * it lies on the surface: its thin (Y) axis along the normal, just off the hit point;
--   * the part goes back to the pool when the ring ends, and on stop() (once);
--   * the parts are cosmetic (no collide / query / touch).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local TOLERANCE = 1e-4

return function(t: Context)
	local FxShapes = t.requireClient("Anim/FxShapes")
	local FxPool = t.requireClient("Anim/FxPool")
	local Scheduler = t.requireClient("Anim/Scheduler")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")
	local expect = t.expect
	local hit = Config.Vfx.Hit

	-- A private pool (its SD_ClientFx folder under an unparented root), a manual scheduler and a FakeClock; `done()`
	-- destroys everything the test made.
	local function rig(): { deps: any, clock: any, pool: any, root: Folder, done: () -> () }
		local root = Instance.new("Folder")
		local pool = FxPool.new(root)
		local scheduler = Scheduler.new(false)
		local clock = FakeClock.new(10)
		local function done()
			scheduler:reset()
			pool:destroy()
			root:Destroy()
		end
		return {
			deps = { pool = pool, scheduler = scheduler, clock = clock.now },
			clock = clock,
			pool = pool,
			root = root,
			done = done,
		}
	end

	t.test("the ring grows 0 -> diameter (Quad Out) while it fades to 1", function()
		local d0, a0 = FxShapes.ringSample(0, 3, 0.45)
		expect.truthy(d0 <= 0.05 + 1e-9)
		expect.near(a0, 0.45, 1e-9)
		local dHalf, aHalf = FxShapes.ringSample(0.5, 3, 0.45)
		expect.near(dHalf, 3 * 0.75, 1e-9) -- Quad Out at 0.5 = 0.75
		expect.near(aHalf, 0.45 + 0.55 * 0.5, 1e-9)
		local d1, a1 = FxShapes.ringSample(1, 3, 0.45)
		expect.near(d1, 3, 1e-9)
		expect.near(a1, 1, 1e-9)
		-- Monotonic, and clamped outside 0..1.
		local previous = 0
		for i = 0, 20 do
			local d = FxShapes.ringSample(i / 20, 2.5)
			expect.truthy(d >= previous - 1e-9)
			previous = d
		end
		expect.near(FxShapes.ringSample(2, 2.5), 2.5, 1e-9)
		-- The default fade starts at the impact ring's value.
		local _, default = FxShapes.ringSample(0, 2)
		expect.near(default, hit.ringTransparencyFrom, 1e-9)
	end)

	t.test("the ring lies on the surface: thin axis along the normal, just off the point", function()
		for _, normal in { Vector3.yAxis, Vector3.xAxis, Vector3.new(0, 0, -1), Vector3.new(1, 1, 0) } do
			local frame = FxShapes.ringFrame(Vector3.new(4, 5, 6), normal)
			local n = normal.Unit
			expect.near(frame.UpVector:Dot(n), 1, TOLERANCE)
			local off = (frame.Position - Vector3.new(4, 5, 6)):Dot(n)
			expect.truthy(off > 0 and off < 0.2)
		end
		-- A zero normal falls back to up.
		expect.near(FxShapes.ringFrame(Vector3.zero, Vector3.zero).UpVector.Y, 1, TOLERANCE)
	end)

	t.test("a ring steps on its scheduler, then its part goes back to the pool", function()
		local r = rig()
		local ring = FxShapes.ringWith(r.deps, Vector3.new(0, 1, 0), Vector3.yAxis, 2.5, 0.3, Color3.new(1, 1, 1), 0.45)
		expect.equal(r.pool:activeCount("part"), 1)
		expect.equal(r.deps.scheduler:count("render"), 1)
		expect.truthy(FxShapes.count() >= 1)
		r.clock.advance(0.15)
		r.deps.scheduler:tick("render", 0.15)
		expect.falsy(ring.done)
		r.clock.advance(0.2)
		r.deps.scheduler:tick("render", 0.2)
		expect.truthy(ring.done)
		expect.equal(r.pool:activeCount("part"), 0)
		expect.equal(r.deps.scheduler:count("render"), 0)
		ring:stop() -- a second stop is a no-op
		expect.equal(r.pool:activeCount("part"), 0)
		r.done()
	end)

	t.test("the ring part is cosmetic, sized by the curve, and back in the pool on stop()", function()
		local r = rig()
		local ring = FxShapes.ringWith(r.deps, Vector3.zero, Vector3.yAxis, 4, 1, Color3.new(1, 1, 1))
		r.clock.advance(0.5)
		r.deps.scheduler:tick("render", 0.5)
		local part: BasePart? = nil
		for _, descendant in r.root:GetDescendants() do
			if descendant.Name == "Ring" and descendant:IsA("BasePart") then
				part = descendant
			end
		end
		expect.truthy(part ~= nil)
		local p = part :: BasePart
		expect.falsy(p.CanCollide)
		expect.falsy(p.CanQuery)
		expect.falsy(p.CanTouch)
		expect.near(p.Size.X, 4 * 0.75, 1e-3)
		expect.near(p.Size.Z, 4 * 0.75, 1e-3)
		expect.truthy(p:FindFirstChildOfClass("SpecialMesh") ~= nil)
		ring:stop()
		expect.truthy(ring.done)
		expect.equal(r.pool:activeCount("part"), 0)
		-- The pool cleared the mesh the ring gave its part, and hides the idle part.
		expect.equal(p:FindFirstChildOfClass("SpecialMesh"), nil)
		expect.equal(p.Transparency, 1)
		r.done()
	end)
end
