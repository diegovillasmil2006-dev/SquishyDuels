--!strict
-- FlakePool_Test: unit tests for StarterPlayerScripts.Client.Anim.FlakePool, the wax flakes, the jolt and the re-wax
-- sparkle of the knead screen (spec phase2-squeeze §1.15, §1.16, §3.5). Server only (ServerStorage.UnitTest). The pure
-- parts with FakeRng, and the pool with plain Parts in a Folder (no engine-only API). Contract (design: fp.js:676-687,
-- fx.js:67, 94-107, 134-141):
--   * a crack throws flakes only from E >= 0.6, with chance 0.25 + 0.4·I (halved under ReducedMotion), one plus one
--     more with chance 0.3·E; colour = the part's lerped 30% to white; spawned 0.002 du out along the normal; velocity
--     normal·U(0.1, 0.28) + right·U(±0.08) + up·U(0.02, 0.12) + back·U(±0.04) du/s; size U(0.0016, 0.0032)·max(1,
--     0.8·kz) du; life U(0.5, 0.9) s; spin U(8, 18) rad/s (none under ReducedMotion); all in studs at studsPerDu;
--   * the scale over a life: a pop to 1.16 by 12%, 1, then a fade from 60% (no pop under ReducedMotion);
--   * one step: v += g·dt, v ×= e^(-1.4·dt), p += v·dt;
--   * the chip's box: the outline radii at 60° steps, 0.16 deep;
--   * the jolt: E > 1.4 raises it to 0.0005·E·(0.4 + 0.6·I) du (never lowers it), then ×= e^(-30·dt); none under
--     ReducedMotion;
--   * the sparkle: 10 stars at the centre ± 0.7 × half the width, White and cream in turn, speed 0.22·U(0.45, 1.2),
--     size 0.004·U(0.6, 1.4), life 0.45·U(0.7, 1.3), no gravity, drag 2.5;
--   * the pool: at most cap live flakes (a new one past it is dropped), parts reused, gone after their life; clear()
--     hides them all; destroy() removes the folder.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local FlakePool = t.requireClient("Anim/FlakePool")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local FakeRng = t.requireFake("FakeRng")
	local expect = t.expect
	local FLAKES = Config.Wax.flakes
	local SPARKLE = Config.Wax.sparkle

	local RIGHT, UP, BACK = Vector3.xAxis, Vector3.yAxis, Vector3.zAxis

	local function crack(E: number, I: number, overrides: { [string]: any }?): any
		local input: { [string]: any } = {
			E = E,
			intact = I,
			position = Vector3.new(1, 2, 3),
			normal = Vector3.new(0, 0, 1),
			color = Color3.new(1, 0.5, 0),
			right = RIGHT,
			up = UP,
			back = BACK,
			studsPerDu = 2,
			kz = 3,
			reduced = false,
		}
		if overrides then
			for key, value in overrides do
				input[key] = value
			end
		end
		return input
	end

	t.test("a crack's flakes: the gate, one or two, the colour, the spawn point (scripted rolls)", function()
		-- E below 0.6: none, and no roll is used.
		expect.equal(#FlakePool.crackSpecs(crack(0.59, 1), FakeRng.new({})), 0)
		-- I = 1: chance 0.65; a roll of 0.66 throws none.
		expect.equal(#FlakePool.crackSpecs(crack(1, 1), FakeRng.new({ 0.66 })), 0)
		-- A roll of 0.64 throws; the count roll 0.29 < 0.3·1 adds the second.
		local rolls = { 0.64, 0.29 }
		for _ = 1, 2 do
			for _, roll in { 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 } do
				table.insert(rolls, roll)
			end
		end
		local specs = FlakePool.crackSpecs(crack(1, 1), FakeRng.new(rolls))
		expect.equal(#specs, 2)
		local spec = specs[1]
		local white = Color3.new(1, 1, 1)
		local expectedColor = Color3.new(1, 0.5, 0):Lerp(white, FLAKES.whiten)
		expect.near(spec.color.G, expectedColor.G, 1e-6)
		expect.near(
			(spec.position - (Vector3.new(1, 2, 3) + Vector3.new(0, 0, 1) * FLAKES.offset * 2)).Magnitude,
			0,
			1e-6
		)
		-- Rolls of 0.5 sit mid-range: speed 0.19 along the normal, no sideways, up 0.07, no depth (du), × 2 studs/du.
		local speed = (FLAKES.speedMin + FLAKES.speedMax) / 2
		local up = (FLAKES.upMin + FLAKES.upMax) / 2
		local expectedVelocity = (Vector3.new(0, 0, 1) * speed + UP * up) * 2
		expect.near((spec.velocity - expectedVelocity).Magnitude, 0, 1e-6)
		local size = (FLAKES.sizeMin + FLAKES.sizeMax) / 2 * math.max(1, FLAKES.zoomShare * 3) * 2
		expect.near(spec.size, size, 1e-9)
		expect.near(spec.life, (FLAKES.lifeMin + FLAKES.lifeMax) / 2, 1e-9)
		expect.near(spec.spin, (FLAKES.spinMin + FLAKES.spinMax) / 2, 1e-9)
		expect.near((spec.gravity - UP * FLAKES.gravity * 2).Magnitude, 0, 1e-6)
		expect.equal(spec.drag, FLAKES.drag)
		-- The count roll 0.31 >= 0.3·1: one flake.
		local one = { 0.64, 0.31 }
		for _ = 1, 11 do
			table.insert(one, 0.5)
		end
		expect.equal(#FlakePool.crackSpecs(crack(1, 1), FakeRng.new(one)), 1)
	end)

	t.test("ReducedMotion halves the flake chance and drops the spin", function()
		local multiplier = Config.Vfx.reducedParticleMultiplier
		-- I = 1: chance 0.65 × multiplier; a roll just above it throws none.
		expect.equal(
			#FlakePool.crackSpecs(crack(1, 1, { reduced = true }), FakeRng.new({ 0.65 * multiplier + 0.01 })),
			0
		)
		local rolls = { 0.65 * multiplier - 0.01, 0.9 }
		for _ = 1, 11 do
			table.insert(rolls, 0.5)
		end
		local specs = FlakePool.crackSpecs(crack(1, 1, { reduced = true }), FakeRng.new(rolls))
		expect.equal(#specs, 1)
		expect.equal(specs[1].spin, 0)
		expect.truthy(specs[1].reduced)
	end)

	t.test("over many cracks the flake share follows 0.25 + 0.4·I and every value stays in range", function()
		local rng = FakeRng.new(42)
		local thrown, cracks = 0, 4000
		for _ = 1, cracks do
			local specs = FlakePool.crackSpecs(crack(0.8, 0.5), rng)
			if #specs > 0 then
				thrown += 1
			end
			for _, spec in specs do
				local along = spec.velocity:Dot(Vector3.new(0, 0, 1)) / 2
				expect.truthy(spec.life >= FLAKES.lifeMin and spec.life <= FLAKES.lifeMax)
				expect.truthy(spec.spin >= FLAKES.spinMin and spec.spin <= FLAKES.spinMax)
				expect.truthy(along >= FLAKES.speedMin - FLAKES.depth - 1e-6)
				expect.near(spec.axis.Magnitude, 1, 1e-6)
			end
		end
		expect.near(thrown / cracks, FLAKES.chanceBase + FLAKES.chanceIntact * 0.5, 0.03)
	end)

	t.test("the scale over a life: pop, hold, fade; no pop under ReducedMotion", function()
		expect.equal(FlakePool.scaleAt(0, false), 0)
		local popTop = FLAKES.popPeak * math.sin(FLAKES.popArc * math.pi)
		expect.near(FlakePool.scaleAt(FLAKES.popEnd - 1e-9, false), popTop, 1e-6)
		expect.near(popTop, 1.162, 0.001)
		expect.equal(FlakePool.scaleAt(0.3, false), 1)
		expect.equal(FlakePool.scaleAt(FLAKES.fadeStart, false), 1)
		expect.near(FlakePool.scaleAt(0.8, false), 1 - (0.2 / 0.4) ^ FLAKES.fadePower, 1e-9)
		expect.equal(FlakePool.scaleAt(1, false), 0)
		expect.equal(FlakePool.scaleAt(0, true), 1)
		expect.equal(FlakePool.scaleAt(0.05, true), 1)
		expect.near(FlakePool.scaleAt(0.8, true), FlakePool.scaleAt(0.8, false), 1e-12)
	end)

	t.test("one step: gravity, then drag, then the move", function()
		local p, v = FlakePool.stepParticle(Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(0, -2, 0), 1.4, 0.1)
		local expectedV = Vector3.new(1, -0.2, 0) * math.exp(-0.14)
		expect.near((v - expectedV).Magnitude, 0, 1e-6)
		expect.near((p - expectedV * 0.1).Magnitude, 0, 1e-6)
	end)

	t.test("the chip's box: the outline at 60° steps, 0.16 deep", function()
		local box = FlakePool.chipBox()
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for i, r in FLAKES.chip do
			local a = (i - 1) / #FLAKES.chip * 2 * math.pi
			minX, maxX = math.min(minX, math.cos(a) * r), math.max(maxX, math.cos(a) * r)
			minY, maxY = math.min(minY, math.sin(a) * r), math.max(maxY, math.sin(a) * r)
		end
		expect.near(box.X, maxX - minX, 1e-6)
		expect.near(box.Y, maxY - minY, 1e-6)
		expect.near(box.Z, FLAKES.chipDepth, 1e-6)
		expect.near(box.X, 1.62, 1e-6)
	end)

	t.test("the jolt: raised by E > 1.4 to 0.0005·E·(0.4 + 0.6·I), never lowered, decaying e^(-30·dt)", function()
		expect.equal(FlakePool.joltAfter(0, 1.4, 1, false), 0)
		expect.near(FlakePool.joltAfter(0, 2, 0.5, false), 0.0005 * 2 * (0.4 + 0.6 * 0.5), 1e-15)
		expect.equal(FlakePool.joltAfter(0.01, 2, 1, false), 0.01)
		expect.equal(FlakePool.joltAfter(0, 3, 1, true), 0)
		expect.near(FlakePool.joltDecay(0.001, 0.1), 0.001 * math.exp(-3), 1e-15)
	end)

	t.test("the sparkle: 10 stars in White and cream, the design's speeds, sizes and lives", function()
		local specs = FlakePool.sparkleSpecs(Vector3.new(0, 1, 0), 0.5, 2, FakeRng.new(7), false)
		expect.equal(#specs, SPARKLE.count)
		for index, spec in specs do
			expect.equal(spec.color, if index % 2 == 1 then Palette.White else Palette.WaxSparkle)
			local offset = spec.position - Vector3.new(0, 1, 0)
			expect.near(offset.Magnitude, SPARKLE.spread * 0.5, 1e-6)
			local speed = spec.velocity.Magnitude / 2
			expect.truthy(speed >= SPARKLE.speed * 0.45 - 1e-6 and speed <= SPARKLE.speed * 1.2 + 1e-6)
			-- Outward, along the offset.
			expect.truthy(spec.velocity:Dot(offset) > 0)
			expect.truthy(spec.size >= SPARKLE.sizeDu * 0.6 * 2 - 1e-9 and spec.size <= SPARKLE.sizeDu * 1.4 * 2 + 1e-9)
			expect.truthy(spec.life >= SPARKLE.life * 0.7 - 1e-9 and spec.life <= SPARKLE.life * 1.3 + 1e-9)
			expect.equal(spec.gravity, Vector3.zero)
			expect.equal(spec.drag, SPARKLE.drag)
			expect.equal(spec.box, SPARKLE.star)
		end
		-- ReducedMotion keeps half of them (Config.Vfx.reducedParticleMultiplier).
		local reduced = FlakePool.sparkleSpecs(Vector3.zero, 0.5, 2, FakeRng.new(7), true)
		expect.equal(#reduced, math.max(1, math.floor(SPARKLE.count * Config.Vfx.reducedParticleMultiplier)))
	end)

	t.test("the pool: capped, reused, gone after their life; clear and destroy", function()
		local folder = Instance.new("Folder")
		local pool = FlakePool.new(folder, 3)
		local function spec(life: number): any
			return {
				position = Vector3.zero,
				velocity = Vector3.new(0, 1, 0),
				gravity = Vector3.zero,
				drag = 0,
				size = 0.1,
				life = life,
				spin = 0,
				axis = Vector3.xAxis,
				angle = 0,
				color = Color3.new(1, 1, 1),
				box = Vector3.one,
				reduced = false,
			}
		end
		expect.truthy(pool:spawn(spec(1)))
		expect.truthy(pool:spawn(spec(1)))
		expect.truthy(pool:spawn(spec(0.5)))
		expect.falsy(pool:spawn(spec(1))) -- past the cap: dropped
		expect.equal(pool:count(), 3)
		local found = folder:FindFirstChild("SD_KneadFlakes")
		expect.truthy(found ~= nil)
		local root = found :: Instance
		expect.equal(#root:GetChildren(), 3)
		pool:step(0.6)
		expect.equal(pool:count(), 2) -- the 0.5 s one is gone
		expect.equal(#root:GetChildren(), 2)
		-- Its part is reused for the next one.
		expect.truthy(pool:spawn(spec(1)))
		expect.equal(pool:count(), 3)
		local moved = false
		for _, child in root:GetChildren() do
			moved = moved or (child :: BasePart).CFrame.Position.Y > 0
		end
		expect.truthy(moved)
		pool:clear()
		expect.equal(pool:count(), 0)
		expect.equal(#root:GetChildren(), 0)
		pool:destroy()
		expect.equal(folder:FindFirstChild("SD_KneadFlakes"), nil)
		folder:Destroy()
	end)
end
