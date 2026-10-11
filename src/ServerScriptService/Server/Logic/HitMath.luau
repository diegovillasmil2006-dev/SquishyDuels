--!strict
-- HitMath: segment math for the server's hit tests (DESIGN §5.5, §5.7, §5.9). Server only, pure (no instances, no
-- yields, no state). Every hit is decided on the server: a projectile is a sphere swept along one simulation sub-step
-- (a segment), a player is the one standard capsule built from the server HumanoidRootPart (§5.5). No Touched, no
-- client hit reports (§12 #11).
--
--   Capsule: axis from HRP + (0, bottomOffset, 0) to HRP + (0, topOffset, 0) along world up (tilt ignored), radius
--   Config.Combat.Hitbox.radius (1.3). Same capsule for R15, R6 and the practice targets.
--   Hit: dist(stepSegment, capsuleAxis) <= sphereRadius + capsule.radius (a graze at exactly that distance hits).
--   Because the whole step segment is tested, a fast projectile can never tunnel through a capsule between frames.
--
-- API:
--   HitMath.segSegDistance(p1, q1, p2, q2)             -> (dist, s, t)  closest points p1+(q1-p1)s and p2+(q2-p2)t
--   HitMath.pointSegDistance(p, a, b)                   -> (dist, t)     closest point a+(b-a)t
--   HitMath.capsule(rootPosition, hitbox?)              -> Capsule       hitbox nil = Config.Combat.Hitbox
--   HitMath.capsuleEntry(p0, p1, sphereRadius, capsule) -> number?       first touching fraction of the step p0->p1
--   HitMath.laneHit(origin, endpoint, radius, capsule)  -> (boolean, dist) a sphere swept origin->endpoint (a lane)
--   HitMath.inZone(point, zone, horizontalMargin?)      -> boolean       zone box {cframe, size}; margin grows X and Z
--
-- Reading (DESIGN §5.5 gives sEntry = max(0, s - sqrt(R² - dist²)/|step|)): that closed form is exact only when the
-- step is perpendicular to the capsule axis. capsuleEntry returns the exact first touch for any step direction: the
-- distance from the moving sphere centre to the axis segment is convex along the step, so it only falls until `s`,
-- and a bisection on [0, s] finds where it first reaches R. It equals the DESIGN form for a perpendicular step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

-- Types

export type Capsule = { a: Vector3, b: Vector3, radius: number }
export type Zone = Types.ArenaZone
export type HitboxConfig = { bottomOffset: number, topOffset: number, radius: number }

-- Constants

local EPSILON = 1e-9 -- squared lengths below this count as a point (Ericson §5.1.9)
local ENTRY_ITERATIONS = 40 -- bisection steps: the entry fraction is exact to s / 2^40

-- Module table

local HitMath = {}

-- Public

-- Closest distance between segments p1q1 and p2q2 (Ericson, Real-Time Collision Detection §5.1.9; DESIGN §5.5).
-- Returns (dist, s, t): the closest points are p1 + (q1 - p1)·s and p2 + (q2 - p2)·t, with s, t in [0, 1].
function HitMath.segSegDistance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3): (number, number, number)
	local d1, d2, r = q1 - p1, q2 - p2, p1 - p2
	local a, e, f = d1:Dot(d1), d2:Dot(d2), d2:Dot(r)
	local s, t = 0, 0
	if a > EPSILON or e > EPSILON then
		if a <= EPSILON then
			t = math.clamp(f / e, 0, 1)
		else
			local c = d1:Dot(r)
			if e <= EPSILON then
				s = math.clamp(-c / a, 0, 1)
			else
				local b = d1:Dot(d2)
				local denom = a * e - b * b
				s = if denom > EPSILON then math.clamp((b * f - c * e) / denom, 0, 1) else 0
				t = (b * s + f) / e
				if t < 0 then
					t, s = 0, math.clamp(-c / a, 0, 1)
				elseif t > 1 then
					t, s = 1, math.clamp((b - c) / a, 0, 1)
				end
			end
		end
	end
	return ((p1 + d1 * s) - (p2 + d2 * t)).Magnitude, s, t
end

-- Distance from point p to segment ab, and the fraction t of the closest point a + (b - a)·t.
function HitMath.pointSegDistance(p: Vector3, a: Vector3, b: Vector3): (number, number)
	local ab = b - a
	local lengthSq = ab:Dot(ab)
	local t = if lengthSq > EPSILON then math.clamp((p - a):Dot(ab) / lengthSq, 0, 1) else 0
	return (p - (a + ab * t)).Magnitude, t
end

-- The standard capsule of a player (or practice target) whose HumanoidRootPart is at rootPosition.
function HitMath.capsule(rootPosition: Vector3, hitbox: HitboxConfig?): Capsule
	local box: HitboxConfig = if hitbox ~= nil then hitbox else Config.Combat.Hitbox
	return {
		a = rootPosition + Vector3.new(0, box.bottomOffset, 0),
		b = rootPosition + Vector3.new(0, box.topOffset, 0),
		radius = box.radius,
	}
end

-- A sphere of sphereRadius moving from p0 to p1 during one sub-step: the fraction of the step (0..1) at which it
-- first touches the capsule, or nil if it never does. 0 when it already touches at p0 (and for a zero-length step that
-- touches). Never misses a touch inside the step, however long the step is.
function HitMath.capsuleEntry(p0: Vector3, p1: Vector3, sphereRadius: number, capsule: Capsule): number?
	local reach = sphereRadius + capsule.radius
	if HitMath.pointSegDistance(p0, capsule.a, capsule.b) <= reach then
		return 0
	end
	local dist, s = HitMath.segSegDistance(p0, p1, capsule.a, capsule.b)
	if dist > reach then
		return nil
	end
	-- Invariant: the centre at fraction `low` is out of reach, at `high` it touches. The distance is convex along the
	-- step and smallest at s, so it only decreases on [0, s] and the first touch lies in between.
	local step = p1 - p0
	local low, high = 0, s
	for _ = 1, ENTRY_ITERATIONS do
		local mid = (low + high) / 2
		if HitMath.pointSegDistance(p0 + step * mid, capsule.a, capsule.b) <= reach then
			high = mid
		else
			low = mid
		end
	end
	return high
end

-- Dragon Rush lane (§5.9): a sphere of `radius` swept from origin to endpoint at a fixed height. True when the
-- capsule touches the lane volume ("if your body touches the lane, you're hit"); also returns the axis distance.
function HitMath.laneHit(origin: Vector3, endpoint: Vector3, radius: number, capsule: Capsule): (boolean, number)
	local dist = HitMath.segSegDistance(origin, endpoint, capsule.a, capsule.b)
	return dist <= radius + capsule.radius, dist
end

-- True when point lies inside the zone box (the arena Zones parts, read as CFrame and Size, §5.3). The box is grown by
-- horizontalMargin studs on X and Z (the "own half + 2 studs" checks, §5.4, §5.6 #5); Y is never grown.
function HitMath.inZone(point: Vector3, zone: Zone, horizontalMargin: number?): boolean
	local margin = if horizontalMargin ~= nil then horizontalMargin else 0
	local localPoint = zone.cframe:PointToObjectSpace(point)
	local half = zone.size / 2
	return math.abs(localPoint.X) <= half.X + margin
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z + margin
end

return table.freeze(HitMath)
