--!strict
-- AmbientMath_Test: unit tests for StarterPlayerScripts.Client.Anim.AmbientMath (pure). Server only
-- (ServerStorage.UnitTest). Edit mode: no instances, the clock is passed in.
-- Contract (DESIGN §18.5.1 A8, §18.11, Config.Vfx.Ambient):
--   * the spin angle is base + rate · t (mod 360), computed from t, never accumulated; lollipops turn 10°/s (odd
--     ones +, even ones -), the daily gift box 18°/s;
--   * the gift box bob stays in [0, giftBobStuds] (0.12): it never sinks into the pedestal;
--   * a breather's scale stays in [1 - A/2, 1 + A] on every axis (counter box A = 0.02, statue A = 0.012);
--   * ReducedMotion gives the exact rest pose (identity offset, scale 1);
--   * every instance has its own stable phase from its name;
--   * Part 8 (tools/mcp/ambient-check.lua relies on it): WorldLayout.TagCounts.SD_Ambient = 7 (4 lollipops "spin",
--     the daily gift box "spinBob", the counter gift box and the statue "breathe"), Lollipop1..4 at +10, -10, +10,
--     -10 °/s, culled beyond 120 studs.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local AmbientMath = t.requireClient("Anim/AmbientMath")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local A = Config.Vfx.Ambient
	local EPS = 1e-9

	-- Every sample time used below: start, fractions of periods, long sessions.
	local TIMES = { 0, 0.05, 0.4, 1, 1.6, 2.5, 3.2, 7.77, 36, 123.456, 3600.25, 86400.5 }

	t.test("DESIGN values: lollipops 10°/s, gift 18°/s with a 0.12 bob over 3.2 s, breathers 0.02 / 0.012", function()
		expect.equal(A.lollipopDegPerSecond, 10)
		expect.equal(A.giftSpinDegPerSecond, 18)
		expect.equal(A.giftBobStuds, 0.12)
		expect.equal(A.giftBobPeriod, 3.2)
		expect.equal(A.counterBreatheAmp, 0.02)
		expect.equal(A.counterBreathePeriod, 3.6)
		expect.equal(A.statueBreatheAmp, 0.012)
		expect.equal(A.statueBreathePeriod, 4.2)
		expect.equal(A.cullStuds, 120)
	end)

	t.test("the angle is base + rate · t (mod 360), never accumulated", function()
		for _, phase in { 0, 0.25, 0.9 } do
			for _, rate in { 10, -10, 18 } do
				for _, time in TIMES do
					local angle = AmbientMath.angleDeg(rate, time, phase)
					expect.truthy(angle >= 0 and angle < 360)
					local expected = (phase * 360 + rate * time) % 360
					expect.near(angle, expected, 1e-6)
				end
			end
		end
		-- The same t gives the same angle however many frames came before (no running sum).
		local stepped = 0
		for _ = 1, 600 do
			stepped = AmbientMath.angleDeg(10, 12.5, 0.3)
		end
		expect.equal(stepped, AmbientMath.angleDeg(10, 12.5, 0.3))
		-- 36 s is one full lollipop turn.
		expect.near(AmbientMath.angleDeg(A.lollipopDegPerSecond, 36, 0), 0, 1e-6)
	end)

	t.test("lollipops: odd ones turn +, even ones -; the daily gift box spins + and bobs", function()
		local one = AmbientMath.spec("spin", "Lollipop1")
		local two = AmbientMath.spec("spin", "Lollipop2")
		local three = AmbientMath.spec("spin", "Lollipop3")
		local four = AmbientMath.spec("spin", "Lollipop4")
		expect.equal(one.degPerSecond, A.lollipopDegPerSecond)
		expect.equal(two.degPerSecond, -A.lollipopDegPerSecond)
		expect.equal(three.degPerSecond, A.lollipopDegPerSecond)
		expect.equal(four.degPerSecond, -A.lollipopDegPerSecond)
		local gift = AmbientMath.spec("spinBob", "GiftBox")
		expect.equal(gift.degPerSecond, A.giftSpinDegPerSecond)
		expect.equal(gift.bobStuds, A.giftBobStuds)
		expect.truthy(AmbientMath.isMover(one) and AmbientMath.isMover(gift))
		expect.equal(AmbientMath.spec("wobble", "Lollipop1"), nil)
		expect.falsy(AmbientMath.isKind("wobble"))
		expect.truthy(AmbientMath.isKind("breathe"))
	end)

	t.test("the bob stays in [0, 0.12] and the offset never goes below the rest height", function()
		local gift = AmbientMath.spec("spinBob", "GiftBox")
		local top = 0
		for step = 0, 3200 do
			local time = step / 1000 * 1.0
			local b = AmbientMath.bob(gift.bobStuds, gift.bobPeriod, time, 0.37)
			expect.truthy(b >= -EPS and b <= A.giftBobStuds + EPS)
			top = math.max(top, b)
			local offset = AmbientMath.offset(gift, time, 0.37, false)
			expect.truthy(offset.Position.Y >= -EPS)
		end
		expect.near(top, A.giftBobStuds, 1e-3) -- the full bob is reached within one period
		expect.near(AmbientMath.bob(0.12, 3.2, 0, 0), 0, EPS)
		expect.near(AmbientMath.bob(0.12, 3.2, 1.6, 0), 0.12, EPS)
	end)

	t.test("a breather's scale stays in [1 - A/2, 1 + A]; the counter box and the statue differ", function()
		local counter = AmbientMath.spec("breathe", "GiftBox")
		local statue = AmbientMath.spec("breathe", "Statue")
		expect.equal(counter.breatheAmp, A.counterBreatheAmp)
		expect.equal(statue.breatheAmp, A.statueBreatheAmp)
		expect.equal(statue.breathePeriod, A.statueBreathePeriod)
		expect.falsy(AmbientMath.isMover(counter))
		for _, spec in { counter, statue } do
			local amp = spec.breatheAmp
			local highest, lowest = 0, 2
			for step = 0, 5000 do
				local time = step / 1000
				local s = AmbientMath.scale(spec, time, 0.61, false)
				for _, value in { s.X, s.Y, s.Z } do
					expect.truthy(value >= 1 - amp / 2 - EPS and value <= 1 + amp + EPS)
				end
				expect.near(s.X, s.Z, EPS)
				highest = math.max(highest, s.Y)
				lowest = math.min(lowest, s.X)
			end
			expect.near(highest, 1 + amp, 1e-4)
			expect.near(lowest, 1 - amp / 2, 1e-4)
			-- A breather never moves its pivot.
			expect.equal(AmbientMath.offset(spec, 1.3, 0.61, false), CFrame.identity)
		end
	end)

	t.test("ReducedMotion gives the exact rest pose", function()
		for _, spec in
			{
				AmbientMath.spec("spin", "Lollipop2"),
				AmbientMath.spec("spinBob", "GiftBox"),
				AmbientMath.spec("breathe", "Statue"),
			}
		do
			for _, time in TIMES do
				expect.equal(AmbientMath.offset(spec, time, 0.4, true), CFrame.identity)
				expect.equal(AmbientMath.scale(spec, time, 0.4, true), Vector3.one)
			end
		end
		-- Movers never scale.
		expect.equal(AmbientMath.scale(AmbientMath.spec("spin", "Lollipop1"), 2, 0, false), Vector3.one)
	end)

	t.test("culling: the bounding sphere is on screen with its projected radius, never behind the camera", function()
		local viewport = Vector2.new(1280, 720)
		local tanHalf = math.tan(math.rad(70) / 2)
		expect.truthy(AmbientMath.sphereOnScreen(640, 360, 40, 8, viewport, tanHalf))
		expect.truthy(AmbientMath.sphereOnScreen(-20, 360, 40, 8, viewport, tanHalf)) -- the edge still overlaps
		expect.falsy(AmbientMath.sphereOnScreen(-2000, 360, 40, 8, viewport, tanHalf))
		expect.falsy(AmbientMath.sphereOnScreen(640, 5000, 40, 8, viewport, tanHalf))
		expect.falsy(AmbientMath.sphereOnScreen(640, 360, -20, 8, viewport, tanHalf)) -- wholly behind
		expect.truthy(AmbientMath.sphereOnScreen(-5000, -5000, 2, 8, viewport, tanHalf)) -- the camera inside it
	end)

	-- What tools/mcp/ambient-check.lua expects in Play (Part 8).
	t.test("ambient check (Part 8): 7 SD_Ambient models (4 spin, 1 spinBob, 2 breathe), lollipops ±10°/s", function()
		local WorldLayout = t.requireShared("World/WorldLayout")
		local lollipops = #WorldLayout.Props.lollipops.positions
		expect.equal(lollipops, 4)
		expect.equal(WorldLayout.TagCounts.SD_Ambient, lollipops + 1 + 2)
		expect.equal(WorldLayout.Tags.Ambient, "SD_Ambient")
		expect.equal(WorldLayout.Attributes.AmbientKind, "SD_AmbientKind")
		for index = 1, lollipops do
			local spec = AmbientMath.spec("spin", "Lollipop" .. index)
			local sign = if index % 2 == 1 then 1 else -1
			expect.equal(spec.degPerSecond, sign * 10)
			-- Over the check's ~1.5 s sample the turn is 15°, so the yaw never wraps between two samples.
			expect.truthy(math.abs(spec.degPerSecond) * 1.5 < 180)
		end
		expect.equal(A.cullStuds, 120)
	end)

	t.test("each instance has its own stable phase from its name", function()
		local seen: { [number]: boolean } = {}
		for _, name in { "Lollipop1", "Lollipop2", "Lollipop3", "Lollipop4", "GiftBox", "Statue" } do
			local phase = AmbientMath.phaseOf(name)
			expect.truthy(phase >= 0 and phase < 1)
			expect.equal(AmbientMath.phaseOf(name), phase)
			expect.falsy(seen[phase])
			seen[phase] = true
		end
	end)
end
