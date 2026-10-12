--!strict
-- Specks_Test: unit tests for StarterPlayerScripts.Client.Anim.Specks (final polish 2026-10-11: the Inspect showcases'
-- small particles drawn as parts in the first-person overlay; design: sd/fx.js FX.emit / burst / update, fx.js:92-143).
-- Server only (ServerStorage.UnitTest). Pure: no instances; a seeded Random.
-- Contract:
--   * a burst: round(count × multiplier) specks at the point (+ offsetY up), each flying along a random direction (with
--     a normal: folded into its half and biased toward it by 0.6) at speed × [0.45, 1.2], size × [0.6, 1.4], life ×
--     [0.7, 1.3], colours in turn (fx.js:97-106); gravity and drag as given (the design's -6 and 1.6 when not given);
--   * an emit: the size and life exactly, the velocity inside velMin..velMax (fx.js:92-96, fp.js:182, 191);
--   * a step: v.y += g·dt, v ×= exp(-drag·dt), p += v·dt; a speck dies when its age reaches its life (fx.js:131-135);
--   * the size envelope: 1.25·sin(t/0.12·0.62π) up to t = 0.12, 1 to 0.6, then 1 - ((t - 0.6)/0.4)^1.6 (fx.js:139);
--   * spark and glowdrop are the design's unlit pools (fx.js:79): glow.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-9

return function(t: Context)
	local Specks = t.requireClient("Anim/Specks")
	local expect = t.expect
	local WHITE = Color3.new(1, 1, 1)
	local ACCENT = Color3.fromRGB(217, 142, 71)

	local function burst(overrides: { [string]: any }?): any
		local spec: { [string]: any } = {
			kind = "burst",
			count = 5,
			shape = "puff",
			speed = 0.35,
			size = 0.006,
			life = 0.6,
			gravity = -0.6,
			drag = 3,
		}
		local extra: { [string]: any } = overrides or {}
		for key, value in extra do
			spec[key] = value
		end
		return spec
	end

	t.test("a burst: n specks at the point with the design's ranges (fx.js:97-106)", function()
		local at = Vector3.new(0, -0.13, -0.5)
		local list = Specks.spawn(burst(), at, Random.new(7), 1, { ACCENT, WHITE })
		expect.equal(#list, 5)
		for i, speck in list do
			expect.truthy((speck.p - at).Magnitude < EPS)
			local speed = speck.v.Magnitude
			expect.truthy(speed >= 0.35 * 0.45 - EPS and speed <= 0.35 * 1.2 + EPS)
			expect.truthy(speck.size >= 0.006 * 0.6 - EPS and speck.size <= 0.006 * 1.4 + EPS)
			expect.truthy(speck.life >= 0.6 * 0.7 - EPS and speck.life <= 0.6 * 1.3 + EPS)
			expect.equal(speck.age, 0)
			expect.equal(speck.g, -0.6)
			expect.equal(speck.drag, 3)
			expect.equal(speck.colour, if i % 2 == 1 then ACCENT else WHITE) -- colours in turn
			expect.equal(speck.shape, "puff")
			expect.falsy(speck.glow)
		end
	end)

	t.test("a burst with a normal flies into that half; offsetY lifts the point; defaults -6 and 1.6", function()
		local spec = burst({ count = 40, normal = Vector3.yAxis, offsetY = 0.05 })
		spec.gravity, spec.drag = nil, nil -- not given: the design's defaults
		local list = Specks.spawn(spec, Vector3.zero, Random.new(3), 1, { WHITE })
		for _, speck in list do
			expect.truthy(speck.v.Y > 0)
			expect.truthy((speck.p - Vector3.new(0, 0.05, 0)).Magnitude < EPS)
			expect.equal(speck.g, -6) -- fx.js:95 (o.gravity ?? -6)
			expect.equal(speck.drag, 1.6) -- fx.js:95 (o.drag ?? 1.6)
		end
	end)

	t.test("the count is round(count × multiplier): ReducedMotion halves the specks", function()
		expect.equal(#Specks.spawn(burst({ count = 5 }), Vector3.zero, Random.new(1), 0.5, { WHITE }), 3)
		expect.equal(#Specks.spawn(burst({ count = 8 }), Vector3.zero, Random.new(1), 0.5, { WHITE }), 4)
		expect.equal(#Specks.spawn(burst({ count = 3 }), Vector3.zero, Random.new(1), 1, { WHITE }), 3)
		expect.equal(#Specks.spawn(burst({ count = 1 }), Vector3.zero, Random.new(1), 0.4, { WHITE }), 0)
	end)

	t.test("an emit: exact size and life, the velocity inside its box, its own colours (fp.js:182)", function()
		local spec = {
			kind = "emit",
			count = 14,
			shape = "glowdrop",
			colours = { Color3.fromRGB(255, 154, 77), Color3.fromRGB(255, 210, 94), Color3.fromRGB(255, 111, 125) },
			velMin = Vector3.new(-0.12, 0.15, 0.05),
			velMax = Vector3.new(0.12, 0.4, 0.3),
			size = 0.007,
			life = 0.5,
			gravity = 0.3,
			drag = 2,
			offsetY = 0.07,
		}
		local list = Specks.spawn(spec :: any, Vector3.zero, Random.new(11), 1, { WHITE })
		expect.equal(#list, 14)
		for i, speck in list do
			expect.equal(speck.size, 0.007)
			expect.equal(speck.life, 0.5)
			expect.truthy(speck.v.X >= -0.12 and speck.v.X <= 0.12)
			expect.truthy(speck.v.Y >= 0.15 and speck.v.Y <= 0.4)
			expect.truthy(speck.v.Z >= 0.05 and speck.v.Z <= 0.3)
			expect.equal(speck.colour, spec.colours[(i - 1) % 3 + 1])
			expect.truthy(speck.glow) -- glowdrop: the design's unlit pool (fx.js:79)
		end
	end)

	t.test("a step: gravity, drag, then the move (fx.js:135); death at the life", function()
		local speck = Specks.spawn(burst({ count = 1 }), Vector3.zero, Random.new(5), 1, { WHITE })[1]
		local v0, p0, life = speck.v, speck.p, speck.life
		local dt = 0.02
		expect.truthy(Specks.step(speck, dt))
		local v1 = Vector3.new(v0.X, v0.Y + -0.6 * dt, v0.Z) * math.exp(-3 * dt)
		expect.truthy((speck.v - v1).Magnitude < EPS)
		expect.truthy((speck.p - (p0 + v1 * dt)).Magnitude < EPS)
		expect.near(speck.age, dt)
		expect.falsy(Specks.step(speck, life)) -- its age reached its life
	end)

	t.test("the size envelope (fx.js:139)", function()
		expect.near(Specks.envelope(0), 0)
		expect.near(Specks.envelope(0.06), 1.25 * math.sin(0.5 * math.pi * 0.62))
		expect.near(Specks.envelope(0.12), 1, 0.02)
		expect.near(Specks.envelope(0.3), 1)
		expect.near(Specks.envelope(0.6), 1)
		expect.near(Specks.envelope(0.8), 1 - 0.5 ^ 1.6)
		expect.near(Specks.envelope(1), 0)
		local speck = Specks.spawn(burst({ count = 1 }), Vector3.zero, Random.new(2), 1, { WHITE })[1]
		Specks.step(speck, speck.life * 0.3)
		expect.near(Specks.radius(speck), speck.size) -- the design's sphere of radius 1 × size × the envelope
	end)

	t.test("spark and glowdrop are the unlit pools; the rest are lit", function()
		for shape, glow in { spark = true, glowdrop = true, puff = false, cube = false, petal = false, heart = false } do
			local speck =
				Specks.spawn(burst({ count = 1, shape = shape }), Vector3.zero, Random.new(9), 1, { WHITE })[1]
			expect.equal(speck.glow, glow)
		end
	end)
end
