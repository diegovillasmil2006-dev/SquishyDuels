--!strict
-- HitMath_Test: unit tests for ServerScriptService.Server.Logic.HitMath. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §5.5, §5.7, §5.9, §12 #11): segSegDistance is Ericson §5.1.9; the standard capsule runs from
-- HRP + (0, -1.7, 0) to HRP + (0, +1.8, 0) with radius 1.3 (Config.Combat.Hitbox); a swept sphere hits when
-- dist(step, axis) <= sphereRadius + 1.3, a graze at exactly that distance included; the entry fraction equals
-- s - sqrt(R² - dist²)/|step| for a step perpendicular to the axis and is the exact first touch for any step; a step of
-- any length is tested whole, so a fast projectile never tunnels through; the Dragon Rush lane is a radius-4 sphere
-- swept between two points (a stadium), and jumping never leaves it; zone boxes grow by the margin on X and Z only.
-- Vector3 components are single precision, so geometric expectations use small tolerances.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local FLOAT_TOLERANCE = 1e-4 -- single-precision Vector3 math
local GRAZE = 1e-3 -- studs either side of an exact touch

return function(t: Context)
	local HitMath = t.requireServer("Logic/HitMath")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local HITBOX = Config.Combat.Hitbox
	local ROOT = Vector3.new(0, 3, 0) -- a player standing on a floor at Y 0 (capsule covers Y 0..6.1)
	local THROW_RADIUS = 1.0

	-- segSegDistance ------------------------------------------------------------------------------------------------

	t.test("segSegDistance: crossing perpendicular segments", function()
		local dist, s, u = HitMath.segSegDistance(
			Vector3.new(-1, 0, 0),
			Vector3.new(1, 0, 0),
			Vector3.new(0, 2, -1),
			Vector3.new(0, 2, 1)
		)
		expect.near(dist, 2, FLOAT_TOLERANCE)
		expect.near(s, 0.5, FLOAT_TOLERANCE)
		expect.near(u, 0.5, FLOAT_TOLERANCE)
	end)

	t.test("segSegDistance: parallel overlapping segments keep their gap", function()
		local dist = HitMath.segSegDistance(
			Vector3.new(0, 0, 0),
			Vector3.new(10, 0, 0),
			Vector3.new(2, 3, 0),
			Vector3.new(8, 3, 0)
		)
		expect.near(dist, 3, FLOAT_TOLERANCE)
	end)

	t.test("segSegDistance: closest points at the end points clamp to [0, 1]", function()
		local dist, s, u = HitMath.segSegDistance(
			Vector3.new(0, 0, 0),
			Vector3.new(1, 0, 0),
			Vector3.new(4, 0, 0),
			Vector3.new(4, 5, 0)
		)
		expect.near(dist, 3, FLOAT_TOLERANCE)
		expect.near(s, 1, FLOAT_TOLERANCE)
		expect.near(u, 0, FLOAT_TOLERANCE)
	end)

	t.test("segSegDistance: degenerate segments (points) are handled", function()
		local a = Vector3.new(1, 2, 3)
		expect.near((HitMath.segSegDistance(a, a, a, a)), 0, FLOAT_TOLERANCE)
		expect.near((HitMath.segSegDistance(a, a, Vector3.new(1, 0, 0), Vector3.new(1, 10, 0))), 3, FLOAT_TOLERANCE)
		expect.near((HitMath.segSegDistance(Vector3.new(1, 0, 0), Vector3.new(1, 10, 0), a, a)), 3, FLOAT_TOLERANCE)
	end)

	-- Capsule -----------------------------------------------------------------------------------------------------

	t.test("capsule: axis from HRP - 1.7 to HRP + 1.8, radius 1.3 (Config.Combat.Hitbox)", function()
		expect.equal(HITBOX.bottomOffset, -1.7)
		expect.equal(HITBOX.topOffset, 1.8)
		expect.equal(HITBOX.radius, 1.3)
		local capsule = HitMath.capsule(ROOT, HITBOX)
		expect.near(capsule.a.Y, 1.3, FLOAT_TOLERANCE)
		expect.near(capsule.b.Y, 4.8, FLOAT_TOLERANCE)
		expect.equal(capsule.radius, 1.3)
		-- Covers floor + 0 .. floor + 6.1, 2.6 studs wide.
		expect.near(capsule.a.Y - capsule.radius, 0, FLOAT_TOLERANCE)
		expect.near(capsule.b.Y + capsule.radius, 6.1, FLOAT_TOLERANCE)
	end)

	-- capsuleEntry ------------------------------------------------------------------------------------------------

	t.test("a perpendicular step through the axis enters at s - R/|step| (DESIGN §5.5 form)", function()
		local capsule = HitMath.capsule(ROOT, HITBOX)
		local reach = THROW_RADIUS + HITBOX.radius
		local entry = HitMath.capsuleEntry(Vector3.new(-10, 3.5, 0), Vector3.new(10, 3.5, 0), THROW_RADIUS, capsule)
		expect.near(entry, 0.5 - reach / 20, FLOAT_TOLERANCE)
	end)

	t.test("a perpendicular step passing beside the axis matches s - sqrt(R² - d²)/|step|", function()
		local capsule = HitMath.capsule(ROOT, HITBOX)
		local reach = THROW_RADIUS + HITBOX.radius
		local offset = 1.5
		local entry =
			HitMath.capsuleEntry(Vector3.new(-10, 3.5, offset), Vector3.new(10, 3.5, offset), THROW_RADIUS, capsule)
		expect.near(entry, 0.5 - math.sqrt(reach * reach - offset * offset) / 20, FLOAT_TOLERANCE)
	end)

	t.test("an oblique (falling) step enters exactly where the sphere first touches", function()
		local capsule = HitMath.capsule(ROOT, HITBOX)
		local reach = THROW_RADIUS + HITBOX.radius
		local p0, p1 = Vector3.new(-6, 9, 0.5), Vector3.new(6, -1, 0.5)
		local entry = HitMath.capsuleEntry(p0, p1, THROW_RADIUS, capsule)
		expect.truthy(entry ~= nil)
		local atEntry = HitMath.pointSegDistance(p0 + (p1 - p0) * entry, capsule.a, capsule.b)
		expect.near(atEntry, reach, FLOAT_TOLERANCE)
		local justBefore = HitMath.pointSegDistance(p0 + (p1 - p0) * (entry - 0.01), capsule.a, capsule.b)
		expect.truthy(justBefore > reach)
	end)

	t.test("edge graze: a path exactly at reach hits, just outside misses", function()
		-- Sphere 0.5 + capsule 1.5 = reach 2. Axis Y 1.25..4.75 and a path at Y 3 (its middle): every number on the
		-- way is exact in binary floating point, so the distance is exactly 2 in single or double precision.
		local capsule = HitMath.capsule(ROOT, { bottomOffset = -1.75, topOffset = 1.75, radius = 1.5 })
		local touching = HitMath.capsuleEntry(Vector3.new(2, 3, -10), Vector3.new(2, 3, 10), 0.5, capsule)
		expect.truthy(touching ~= nil)
		expect.near(touching, 0.5, 1e-3)
		expect.equal(
			HitMath.capsuleEntry(Vector3.new(2 + GRAZE, 3, -10), Vector3.new(2 + GRAZE, 3, 10), 0.5, capsule),
			nil
		)
	end)

	t.test("edge graze with the standard hitbox: just inside hits, just outside misses", function()
		local capsule = HitMath.capsule(ROOT, HITBOX)
		local reach = THROW_RADIUS + HITBOX.radius
		local inside = reach - GRAZE
		local outside = reach + GRAZE
		expect.truthy(
			HitMath.capsuleEntry(Vector3.new(inside, 3, -10), Vector3.new(inside, 3, 10), THROW_RADIUS, capsule) ~= nil
		)
		expect.equal(
			HitMath.capsuleEntry(Vector3.new(outside, 3, -10), Vector3.new(outside, 3, 10), THROW_RADIUS, capsule),
			nil
		)
	end)

	t.test("graze over the head (the capsule's top cap): just inside hits, just above misses", function()
		local capsule = HitMath.capsule(ROOT, HITBOX)
		local reach = THROW_RADIUS + HITBOX.radius
		local topY = capsule.b.Y
		local low, high = topY + reach - GRAZE, topY + reach + GRAZE
		expect.truthy(
			HitMath.capsuleEntry(Vector3.new(-10, low, 0), Vector3.new(10, low, 0), THROW_RADIUS, capsule) ~= nil
		)
		expect.equal(
			HitMath.capsuleEntry(Vector3.new(-10, high, 0), Vector3.new(10, high, 0), THROW_RADIUS, capsule),
			nil
		)
	end)

	t.test("tunnelling: one 200-stud step straight through the capsule still hits", function()
		local capsule = HitMath.capsule(ROOT, HITBOX)
		local reach = THROW_RADIUS + HITBOX.radius
		local p0, p1 = Vector3.new(-100, 3.5, 0), Vector3.new(100, 3.5, 0)
		-- Neither end point is anywhere near the capsule: a per-frame point test would miss it.
		expect.truthy(HitMath.pointSegDistance(p0, capsule.a, capsule.b) > 50)
		expect.truthy(HitMath.pointSegDistance(p1, capsule.a, capsule.b) > 50)
		local entry = HitMath.capsuleEntry(p0, p1, THROW_RADIUS, capsule)
		expect.near(entry, 0.5 - reach / 200, FLOAT_TOLERANCE)
	end)

	t.test("tunnelling at the fastest throw over a 6-sub-step hitch is still caught", function()
		-- 115 studs/s (top of the speed band) for 0.1 s in one sub-step: 11.5 studs per step.
		local capsule = HitMath.capsule(ROOT, HITBOX)
		local step = 115 * 0.1
		local p0 = Vector3.new(-step / 2, 3.5, 0.4)
		local p1 = Vector3.new(step / 2, 3.5, 0.4)
		expect.truthy(HitMath.capsuleEntry(p0, p1, 0.8, capsule) ~= nil)
	end)

	t.test("a sphere already touching at the step start enters at 0", function()
		local capsule = HitMath.capsule(ROOT, HITBOX)
		expect.equal(HitMath.capsuleEntry(Vector3.new(0.5, 3, 0), Vector3.new(20, 3, 0), THROW_RADIUS, capsule), 0)
	end)

	t.test("a zero-length step: touching -> 0, apart -> nil", function()
		local capsule = HitMath.capsule(ROOT, HITBOX)
		local near = Vector3.new(1, 3, 0)
		local far = Vector3.new(10, 3, 0)
		expect.equal(HitMath.capsuleEntry(near, near, THROW_RADIUS, capsule), 0)
		expect.equal(HitMath.capsuleEntry(far, far, THROW_RADIUS, capsule), nil)
	end)

	t.test("a step moving away from the capsule never hits", function()
		local capsule = HitMath.capsule(ROOT, HITBOX)
		expect.equal(HitMath.capsuleEntry(Vector3.new(5, 3, 0), Vector3.new(30, 3, 0), THROW_RADIUS, capsule), nil)
	end)

	t.test("a jump lifts the capsule clear of a chest-height throw", function()
		local jumpHeight = Config.Duel.Rules.Movement.JumpHeight
		local standing = HitMath.capsule(ROOT, HITBOX)
		local jumping = HitMath.capsule(ROOT + Vector3.new(0, jumpHeight, 0), HITBOX)
		local p0, p1 = Vector3.new(-10, 3.5, 0), Vector3.new(10, 3.5, 0)
		expect.truthy(HitMath.capsuleEntry(p0, p1, THROW_RADIUS, standing) ~= nil)
		expect.equal(HitMath.capsuleEntry(p0, p1, THROW_RADIUS, jumping), nil)
	end)

	-- laneHit (Dragon Rush) -----------------------------------------------------------------------------------------

	t.test("lane: touching the lane side hits, just beside it misses", function()
		local rush = Config.Abilities.dragon_rush
		local laneY = rush.laneHeightAboveFloor
		local origin, endpoint = Vector3.new(0, laneY, -40), Vector3.new(0, laneY, 40)
		local reach = rush.radius + HITBOX.radius
		local inside = HitMath.capsule(Vector3.new(reach - GRAZE, 3, 0), HITBOX)
		local outside = HitMath.capsule(Vector3.new(reach + GRAZE, 3, 0), HITBOX)
		expect.truthy((HitMath.laneHit(origin, endpoint, rush.radius, inside)))
		expect.falsy((HitMath.laneHit(origin, endpoint, rush.radius, outside)))
	end)

	t.test("lane: the round end caps count (stadium footprint)", function()
		local rush = Config.Abilities.dragon_rush
		local laneY = rush.laneHeightAboveFloor
		local origin, endpoint = Vector3.new(0, laneY, -40), Vector3.new(0, laneY, 40)
		local reach = rush.radius + HITBOX.radius
		expect.truthy(
			(
				HitMath.laneHit(
					origin,
					endpoint,
					rush.radius,
					HitMath.capsule(Vector3.new(0, 3, 40 + reach - GRAZE), HITBOX)
				)
			)
		)
		expect.falsy(
			(
				HitMath.laneHit(
					origin,
					endpoint,
					rush.radius,
					HitMath.capsule(Vector3.new(0, 3, 40 + reach + GRAZE), HITBOX)
				)
			)
		)
	end)

	t.test("lane: jumping never avoids the lane", function()
		local rush = Config.Abilities.dragon_rush
		local laneY = rush.laneHeightAboveFloor
		local jumpHeight = Config.Duel.Rules.Movement.JumpHeight
		local airborne = HitMath.capsule(ROOT + Vector3.new(0, jumpHeight, 0), HITBOX)
		expect.truthy((HitMath.laneHit(Vector3.new(0, laneY, -40), Vector3.new(0, laneY, 40), rush.radius, airborne)))
	end)

	-- inZone ---------------------------------------------------------------------------------------------------------

	t.test("inZone: inside, outside, and a margin that grows X and Z but not Y", function()
		local zone = { cframe = CFrame.new(0, 12.5, -30), size = Vector3.new(72, 55, 44) } -- arena HalfA
		expect.truthy(HitMath.inZone(Vector3.new(0, 3, -30), zone))
		expect.truthy(HitMath.inZone(Vector3.new(36, 3, -8), zone))
		expect.falsy(HitMath.inZone(Vector3.new(0, 3, -7), zone))
		expect.truthy(HitMath.inZone(Vector3.new(0, 3, -6.5), zone, 2))
		expect.falsy(HitMath.inZone(Vector3.new(0, 3, -5.5), zone, 2))
		expect.truthy(HitMath.inZone(Vector3.new(37.5, 3, -30), zone, 2))
		expect.falsy(HitMath.inZone(Vector3.new(0, 41, -30), zone, 2))
		expect.falsy(HitMath.inZone(Vector3.new(0, -16, -30), zone, 2))
	end)

	t.test("inZone: a rotated box is tested in its own space", function()
		local zone =
			{ cframe = CFrame.new(100, 0, 0) * CFrame.Angles(0, math.rad(90), 0), size = Vector3.new(10, 4, 2) }
		-- Rotated 90° about Y: the 10-stud side now runs along world Z.
		expect.truthy(HitMath.inZone(Vector3.new(100, 0, 4.5), zone))
		expect.falsy(HitMath.inZone(Vector3.new(104.5, 0, 0), zone))
	end)
end
