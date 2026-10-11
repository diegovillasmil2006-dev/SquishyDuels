--!strict
-- SplatMath_Test: unit tests for StarterPlayerScripts.Client.Anim.SplatMath (pure: colour, droplets, timeline).
-- Contract (DESIGN §18.4.1, §18.9 validator 11, Config.Vfx.Splat):
--   * color(): accent:Lerp(White, 0.25); a hue within 15° of red with saturation > 0.45 whitens by 0.6, so no catalog
--     accent and no red input (#FF0000, #E0466A, #FF5A4E) ever comes out red with saturation > 0.45;
--   * droplets: 4, sizes 0.16-0.30 d, distances 0.55-0.85 d, the same for the same seed;
--   * sample: scale 0 at t = 0, peak <= 1.12, 1.0 at 160 ms, transparency 0.1 while holding, 1 and done at 2.5 s;
--     the drip only on a wall (|n.Y| < 0.35); ReducedMotion: full size at once, no drip, the fade stays;
--   * a curved surface (a gumdrop) gets the main blob only, d <= 1.6, no droplets or drip;
--   * eviction takes the oldest first, other players' practice splats before anything else;
--   * a practice lane-floor hit (the projectile centre at FLOOR_Y + r) is dropped to the floor;
--   * SplatController.prepare (the trigger rules, §18.4.1): only "geometry" with a normal; an unknown throw is r 1.0
--     and White; culled beyond 120 studs, other players' practice splats beyond 60 (and marked low).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local TOLERANCE = 1e-6

return function(t: Context)
	local SplatMath = t.requireClient("Anim/SplatMath")
	local Config = t.requireShared("Config")
	local Catalog = t.requireShared("Catalog")
	local expect = t.expect
	local splat = Config.Vfx.Splat

	-- Red as §18.4.1 defines it: a hue within redHueDeg of red with saturation above redMinSaturation.
	local function looksRed(color: Color3): boolean
		local h, s = color:ToHSV()
		local deg = h * 360
		return math.min(deg, 360 - deg) <= splat.redHueDeg and s > splat.redMinSaturation
	end

	t.test("no catalog accent and no red input ever comes out red", function()
		local inputs: { Color3 } = {}
		for _, def in Catalog.list() do
			table.insert(inputs, Color3.fromHex(def.visuals.accent))
		end
		expect.truthy(#inputs >= 8)
		for _, hex in { "#FF0000", "#E0466A", "#FF5A4E" } do
			table.insert(inputs, Color3.fromHex(hex))
		end
		for _, input in inputs do
			expect.falsy(looksRed(SplatMath.color(input)))
		end
		-- The guard is what saves pure red: plain whitening would leave it red.
		expect.truthy(looksRed(Color3.fromHex("#FF0000"):Lerp(Color3.new(1, 1, 1), splat.whiten)))
	end)

	t.test("a non-red accent is whitened by 0.25 (Chocolate becomes milk chocolate)", function()
		local chocolate = Color3.fromHex("#7A4632")
		local got = SplatMath.color(chocolate)
		local want = chocolate:Lerp(Color3.new(1, 1, 1), splat.whiten)
		expect.near(got.R, want.R, TOLERANCE)
		expect.near(got.G, want.G, TOLERANCE)
		expect.near(got.B, want.B, TOLERANCE)
		local red = SplatMath.color(Color3.fromHex("#FF0000"))
		local _, s = red:ToHSV()
		expect.truthy(s <= 1 - splat.redGuardWhiten + TOLERANCE)
	end)

	t.test("droplets: 4, inside the size and distance ranges, the same for the same seed", function()
		local d = 2.2
		local a = SplatMath.droplets(Random.new(7), d)
		local b = SplatMath.droplets(Random.new(7), d)
		expect.equal(#a, splat.droplets)
		expect.equal(#a, 4)
		for index, droplet in a do
			expect.truthy(droplet.size >= splat.dropletSizeMin * d - TOLERANCE)
			expect.truthy(droplet.size <= splat.dropletSizeMax * d + TOLERANCE)
			expect.truthy(droplet.dist >= splat.dropletDistMin * d - TOLERANCE)
			expect.truthy(droplet.dist <= splat.dropletDistMax * d + TOLERANCE)
			expect.equal(droplet.size, b[index].size)
			expect.equal(droplet.dist, b[index].dist)
			expect.equal(droplet.angle, b[index].angle)
		end
	end)

	t.test("the timeline: 0 at the start, peak <= 1.12, 1.0 at 160 ms, held at 0.1, gone at 2.5 s", function()
		local start = SplatMath.sample(0, false)
		expect.near(start.main, 0, TOLERANCE)
		expect.near(start.droplet, 0, TOLERANCE)
		local peak = 0
		for ms = 0, 400, 5 do
			local s = SplatMath.sample(ms / 1000, false)
			peak = math.max(peak, s.main)
		end
		expect.truthy(peak <= splat.overshoot + TOLERANCE)
		expect.truthy(peak > 1.05) -- it does overshoot
		expect.near(SplatMath.sample((splat.growMs + splat.settleMs) / 1000, false).main, 1, 1e-4)
		for _, at in { 0.2, 0.8, splat.holdSeconds } do
			local s = SplatMath.sample(at, false)
			expect.near(s.transparency, splat.transparency, TOLERANCE)
			expect.near(s.main, 1, TOLERANCE)
			expect.near(s.droplet, 1, TOLERANCE)
			expect.falsy(s.done)
		end
		local finish = SplatMath.sample(splat.holdSeconds + splat.fadeSeconds, false)
		expect.near(finish.transparency, 1, TOLERANCE)
		expect.near(finish.main, splat.fadeScaleTo, TOLERANCE)
		expect.truthy(finish.done)
		expect.near(splat.holdSeconds + splat.fadeSeconds, 2.5, TOLERANCE)
	end)

	t.test("droplets pop in from 40 ms over 80 ms", function()
		expect.near(SplatMath.sample(splat.dropletDelayMs / 1000 - 0.001, false).droplet, 0, TOLERANCE)
		local grown = SplatMath.sample((splat.dropletDelayMs + splat.dropletGrowMs) / 1000, false)
		expect.near(grown.droplet, 1, TOLERANCE)
	end)

	t.test("the drip runs only on a wall", function()
		expect.truthy(SplatMath.isWall(Vector3.new(1, 0, 0)))
		expect.truthy(SplatMath.isWall(Vector3.new(1, 0.3, 0).Unit))
		expect.falsy(SplatMath.isWall(Vector3.yAxis))
		expect.falsy(SplatMath.isWall(Vector3.new(1, 0.5, 0).Unit))
		local wall = SplatMath.sample(1.0, true)
		local floor = SplatMath.sample(1.0, false)
		expect.truthy(wall.drip > 0)
		expect.truthy(wall.dripStretch > 1)
		expect.equal(floor.drip, 0)
		expect.equal(floor.dripStretch, 1)
		-- Not before dripFromSeconds; all the way by holdSeconds.
		expect.equal(SplatMath.sample(splat.dripFromSeconds - 0.01, true).drip, 0)
		local full = SplatMath.sample(splat.holdSeconds, true)
		expect.near(full.drip, 1, TOLERANCE)
		expect.near(full.dripStretch, splat.dripStretch, TOLERANCE)
		-- The spec agrees.
		expect.truthy(SplatMath.spec(1, false, Vector3.xAxis).drip)
		expect.falsy(SplatMath.spec(1, false, Vector3.yAxis).drip)
	end)

	t.test("ReducedMotion: full size at once, no droplet pop or drip, the slow fade stays", function()
		local s = SplatMath.sample(0, true, true)
		expect.equal(s.main, 1)
		expect.equal(s.droplet, 1)
		expect.equal(SplatMath.sample(1.0, true, true).drip, 0)
		local fading = SplatMath.sample(splat.holdSeconds + splat.fadeSeconds / 2, true, true)
		expect.truthy(fading.transparency > splat.transparency)
		expect.truthy(SplatMath.sample(splat.holdSeconds + splat.fadeSeconds, true, true).done)
	end)

	t.test("size: d = 2.2 × the throw radius; a curved surface gets the main blob only, d <= 1.6", function()
		local flat = SplatMath.spec(1.2, false, Vector3.xAxis)
		expect.near(flat.d, splat.diameterPerRadius * 1.2, TOLERANCE)
		expect.truthy(flat.droplets)
		for _, normal in { Vector3.xAxis, Vector3.yAxis } do
			local curved = SplatMath.spec(1.4, true, normal)
			expect.truthy(curved.d <= splat.curvedMaxDiameter + TOLERANCE)
			expect.falsy(curved.droplets)
			expect.falsy(curved.drip)
		end
	end)

	t.test("eviction takes the oldest first, other players' practice splats before anything", function()
		expect.equal(SplatMath.pickEvict({}), nil)
		expect.equal(SplatMath.pickEvict({ { bornAt = 5 }, { bornAt = 2 }, { bornAt = 9 } }), 2)
		local mixed = { { bornAt = 1 }, { bornAt = 7, low = true }, { bornAt = 3, low = true } }
		expect.equal(SplatMath.pickEvict(mixed), 3)
		local value, gone = SplatMath.evicted(0.1, splat.evictFadeSeconds / 2)
		expect.near(value, 0.55, TOLERANCE)
		expect.falsy(gone)
		local _, over = SplatMath.evicted(0.1, splat.evictFadeSeconds)
		expect.truthy(over)
	end)

	t.test("newer splats sit higher off the surface, in a repeating stack", function()
		expect.near(SplatMath.lift(0), splat.lift, TOLERANCE)
		expect.truthy(SplatMath.lift(5) > SplatMath.lift(4))
		expect.near(SplatMath.lift(splat.layers), SplatMath.lift(0), TOLERANCE)
	end)

	t.test("a practice floor hit is dropped from the projectile centre to the lane floor", function()
		local floorY = 0.4
		local centre = Vector3.new(-30, floorY + 1.1, -40)
		local onFloor = SplatMath.surfacePoint(centre, Vector3.yAxis, 1.1, true, floorY)
		expect.near(onFloor.Y, floorY, TOLERANCE)
		expect.near(onFloor.X, -30, TOLERANCE)
		-- A duel hit, or a practice hit on a wall, stays where the server put it.
		expect.equal(SplatMath.surfacePoint(centre, Vector3.yAxis, 1.1, false, floorY), centre)
		local wall = Vector3.new(-30, 3, -40)
		expect.equal(SplatMath.surfacePoint(wall, Vector3.xAxis, 1.1, true, floorY), wall)
	end)

	t.test("splats come only from geometry hits with a normal, near enough to the camera", function()
		local SplatController = t.requireClient("Controllers/SplatController")
		local at = Vector3.new(0, 4, 0)
		local throw = { radius = 1.2, squishyId = "", practice = false, own = true }
		-- Only "geometry" with a normal (not bodies, targets, misses, or a Dragon Rush lane end without one).
		for _, kind in { "player", "target", "expired", "fizzle" } do
			expect.equal(SplatController.prepare(kind, at, Vector3.xAxis, throw, nil), nil)
		end
		expect.equal(SplatController.prepare("geometry", at, nil, throw, nil), nil)
		local placed = SplatController.prepare("geometry", at, Vector3.new(2, 0, 0), throw, nil)
		expect.truthy(placed ~= nil)
		local p = placed :: any
		expect.near(p.normal.Magnitude, 1, TOLERANCE)
		expect.equal(p.radius, 1.2)
		expect.falsy(p.low)
		-- An unknown throw: r = 1.0 and White.
		local unknown = SplatController.prepare("geometry", at, Vector3.yAxis, nil, nil) :: any
		expect.equal(unknown.radius, 1)
		expect.equal(unknown.accent, Color3.new(1, 1, 1))
		-- Camera culls: 120 studs for duels and own practice, 60 for other players' practice splats.
		local far = at + Vector3.new(splat.cullStuds + 1, 0, 0)
		expect.equal(SplatController.prepare("geometry", at, Vector3.xAxis, throw, far), nil)
		local mid = at + Vector3.new(splat.othersCullStuds + 1, 0, 0)
		expect.truthy(SplatController.prepare("geometry", at, Vector3.xAxis, throw, mid) ~= nil)
		local others = { radius = 1, squishyId = "", practice = true, own = false }
		expect.equal(SplatController.prepare("geometry", at, Vector3.xAxis, others, mid), nil)
		local near = SplatController.prepare("geometry", at, Vector3.xAxis, others, at) :: any
		expect.truthy(near.low)
	end)
end
