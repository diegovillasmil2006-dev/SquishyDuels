--!strict
-- UltFx_Test: unit tests for StarterPlayerScripts.Client.Anim.UltFx, the pure helpers of the four Epic ultimates' world
-- visuals (spec phase 5 §1.5-§1.8). Server only (ServerStorage.UnitTest). Edit mode: no instances.
-- Contract (design numbers in Config.Vfx.Ultimates and Config.Abilities):
--   * a drawn bird follows the server's straight path plus the design's glide arc (0.3 m peak) and wobble, and a drawn
--     bubble the design's 0.9 m sine arc: on the path at both ends (fp.js:241); Bubble Pop bounce (2026-10-16): a
--     bounced bubble follows its first leg up to the bounce, then the bounce leg, with one arc over the whole flight;
--   * the roller grows 0.5 -> 2.3 with the design's backOut over 0.3 s (fp.js:242, 342);
--   * the lane marker is a flat 6 × 60 plate on the floor along the lane (fp.js:340-341);
--   * a drop falls from 13 studs over the zone's centre to its point along k² in 0.3 s (fp.js:356, 371);
--   * every pulse stays at or under 3 Hz: the drop shadow's 30 rad/s is held to 3 Hz (user decision 2026-10-11);
--   * batch B (owner 2026-10-17): a bounced bubble reaches its bounce at bounce.at studs (bouncePassed; never without
--     a bounce), and its bounce look is the Strawberry Frog's bounce pass (fp.js:239): 6 hearts in #EE4A5C / #6CC56A
--     at 1.4 m/s, 0.04 m, 0.5 s; a white ring to 0.5 m in 0.3 s at 0.6; its sound and heart picture exist.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local UltFx = t.requireClient("Anim/UltFx")
	local Config = t.requireShared("Config")
	local FX = Config.Vfx.Ultimates
	local A = Config.Abilities

	local function near(a: Vector3, b: Vector3, tolerance: number?)
		expect.near((a - b).Magnitude, 0, tolerance or 1e-4)
	end

	t.test("a drawn bird is on the server path at both ends, its glide arc 0.3 m above it halfway", function()
		local origin, dir = Vector3.new(0, 4.8, -38), Vector3.new(0, 0, 1)
		local speed, duration = A.flock_volley.speed, 1.2
		near(UltFx.glidePoint(origin, dir, speed, 0, duration), origin)
		local endT = duration
		local wobbleEnd = math.sin(FX.glideWobbleRate) * FX.glideWobbleStuds
		near(
			UltFx.glidePoint(origin, dir, speed, endT, duration),
			origin + dir * speed * endT + Vector3.yAxis * wobbleEnd
		)
		local mid = UltFx.glidePoint(origin, dir, speed, duration / 2, duration)
		local arc = FX.glideArcStuds + math.sin(FX.glideWobbleRate / 2) * FX.glideWobbleStuds
		expect.near(mid.Y - origin.Y, arc, 1e-4)
		expect.near(mid.Z - origin.Z, speed * duration / 2, 1e-4)
	end)

	t.test("a drawn bubble rises on the design's 0.9 m sine arc and lands back on its path", function()
		local origin, dir = Vector3.new(0, 4.8, -38), Vector3.new(1, 0, 0)
		local speed, duration = A.bubble_pop.speed, A.bubble_pop.popSeconds
		near(UltFx.arcPoint(origin, dir, speed, 0, duration, FX.bubbleArcStuds), origin)
		local mid = UltFx.arcPoint(origin, dir, speed, duration / 2, duration, FX.bubbleArcStuds)
		expect.near(mid.Y - origin.Y, 0.9 / 0.28, 1e-4)
		near(UltFx.arcPoint(origin, dir, speed, duration, duration, FX.bubbleArcStuds), origin + dir * speed * duration)
	end)

	t.test("a bounced bubble turns onto its bounce leg there; one 0.9 m arc spans the whole flight", function()
		local origin, dir = Vector3.new(0, 4.8, -38), Vector3.new(0, 0, 1)
		local speed, duration = A.bubble_pop.speed, A.bubble_pop.popSeconds
		local bounceAt = 30 -- studs: the first leg ends on cover at Z -8
		local bounce = { at = bounceAt, origin = origin + dir * bounceAt, dir = Vector3.new(1, 0, 0) }
		local arc = FX.bubbleArcStuds
		local function lift(t: number): Vector3
			return Vector3.new(0, math.sin(math.pi * t / duration) * arc, 0)
		end
		-- Before the bounce: the first leg, as without one.
		local before = 0.5
		near(
			UltFx.arcPoint(origin, dir, speed, before, duration, arc, bounce),
			origin + dir * speed * before + lift(before)
		)
		-- At the bounce itself: on the cover.
		local at = bounceAt / speed
		near(UltFx.arcPoint(origin, dir, speed, at, duration, arc, bounce), bounce.origin + lift(at))
		-- After it: along the bounce leg; the flight's end is back on the path (arc 0).
		local after = 1.0
		near(
			UltFx.arcPoint(origin, dir, speed, after, duration, arc, bounce),
			bounce.origin + bounce.dir * (speed * after - bounceAt) + lift(after)
		)
		near(
			UltFx.arcPoint(origin, dir, speed, duration, duration, arc, bounce),
			bounce.origin + bounce.dir * (speed * duration - bounceAt)
		)
		-- The arc's top is halfway through the whole flight, not at the bounce.
		local mid = UltFx.arcPoint(origin, dir, speed, duration / 2, duration, arc, bounce)
		expect.near(mid.Y - origin.Y, 0.9 / 0.28, 1e-4)
	end)

	t.test("the roller grows 0.5 -> 2.3 with the design's backOut over 0.3 s, overshooting on the way", function()
		expect.near(UltFx.rollerScale(0), FX.rollerScaleFrom, 1e-9)
		expect.near(UltFx.rollerScale(FX.rollerGrowSeconds), FX.rollerScaleTo, 1e-9)
		expect.near(UltFx.rollerScale(5), FX.rollerScaleTo, 1e-9)
		local peak = 0
		for i = 1, 30 do
			peak = math.max(peak, UltFx.rollerScale(FX.rollerGrowSeconds * i / 30))
		end
		expect.truthy(peak > FX.rollerScaleTo) -- backOut overshoots before it settles
	end)

	t.test("the lane marker: a flat plate 2R × length on the floor, centred on the lane", function()
		local R = A.sprinkle_roller
		local cframe, size =
			UltFx.lanePlate(Vector3.new(0, R.laneHeightAboveFloor, -34), Vector3.new(0, 0, 1), 60, R.radius, 0)
		near(size, Vector3.new(2 * R.radius, size.Y, 60))
		expect.truthy(size.Y < 0.2)
		near(cframe.Position, Vector3.new(0, FX.laneLift, -4))
		near(cframe.LookVector, Vector3.new(0, 0, 1))
	end)

	t.test("a drop falls along k² from 13 studs over the centre to its point in 0.3 s", function()
		local top = Vector3.new(0, 13, 30)
		local to = Vector3.new(2, 0, 31)
		near(UltFx.dropPoint(top, to, 0, 0.3), top)
		near(UltFx.dropPoint(top, to, 0.15, 0.3), top:Lerp(to, 0.25))
		near(UltFx.dropPoint(top, to, 0.4, 0.3), to)
	end)

	t.test("pulses: the zone at the design's 2.5 Hz, the drop shadow held to 3 Hz; none faster than 3 Hz", function()
		expect.near(FX.zonePulseHz, 16 / (2 * math.pi), 1e-9)
		expect.truthy(FX.zonePulseHz <= 3)
		expect.truthy(FX.shadowPulseHz <= 3)
		expect.truthy(30 / (2 * math.pi) > 3) -- the design's own shadow pulse would break the rule
		expect.near(UltFx.pulse(0, 2), 0.5, 1e-9)
		expect.near(UltFx.pulse(0.125, 2), 1, 1e-9)
		expect.near(UltFx.pulse(0.375, 2), 0, 1e-9)
		expect.truthy(FX.rollerSpinDegPerSecond <= 720)
	end)

	-- Batch B (owner 2026-10-17: "the Frog's bounce look from the design") -------------------------------------------

	t.test("the bubble's bounce look: when it plays, and the Frog's bounce pass numbers (fp.js:239)", function()
		local speed = A.bubble_pop.speed
		local bounce = { at = 20, origin = Vector3.new(0, 4.8, -18), dir = Vector3.new(1, 0, 0) }
		expect.falsy(UltFx.bouncePassed(speed, 0, bounce))
		expect.falsy(UltFx.bouncePassed(speed, 19.9 / speed, bounce))
		expect.truthy(UltFx.bouncePassed(speed, (20 + 1e-6) / speed, bounce)) -- a hair past it (float slack)
		expect.truthy(UltFx.bouncePassed(speed, 1, bounce))
		expect.falsy(UltFx.bouncePassed(speed, 1, nil)) -- no bounce leg: no bounce look
		expect.equal(FX.bounceHearts, 6)
		expect.near(FX.bounceHeartSpeed, 1.4 / 0.28, 1e-9)
		expect.near(FX.bounceHeartSize, 0.04 / 0.28, 1e-9)
		expect.equal(FX.bounceHeartLifetime, 0.5)
		expect.near(FX.bounceRingToStuds, 2 * 0.5 / 0.28, 1e-9)
		expect.equal(FX.bounceRingSeconds, 0.3)
		expect.near(FX.bounceTransparencyFrom, 0.4, 1e-9)
		local Palette = t.requireShared("Art/Palette")
		expect.equal(Palette.UltBounceHeartRed, Color3.fromHex("#EE4A5C"))
		expect.equal(Palette.UltBounceHeartGreen, Color3.fromHex("#6CC56A"))
		local AssetTable = t.requireShared("AssetTable")
		expect.truthy(AssetTable.image("img.kill.heart") ~= nil)
		local soundKnown = false
		for _, slot in AssetTable.all() do
			soundKnown = soundKnown or (slot.kind == "sound" and slot.key == "sfx.pop")
		end
		expect.truthy(soundKnown)
	end)
end
