--!strict
-- UltRules: the pure geometry of the four Epic ultimates (spec phase 5 §1.5-§1.8, §3.2; numbers in Config.Abilities).
-- Server only, pure (no instances, no yields). AbilityService builds each ultimate from it and CombatService tests hits
-- with it; every number comes from the server (Config, the match snapshot, the server HRP), never from a client.
--
-- A player's "feet" are the lowest point of its standard capsule (§5.5): HRP + bottomOffset - radius, on the floor
-- when standing (HRP 3.0 above it). The design tests its dummies from their floor point (fp.js:353, 361, 372), so the
-- feet stand in for it: a jump lifts them.
--
-- API:
--   UltRules.volleyDirs(dir, count, fanDeg)                  -> { Vector3 } flat unit directions, evenly over fanDeg
--                                                              around dir (design: ults.js:3 "3 in a 24° fan")
--   UltRules.feetPoint(rootPosition, hitbox?)                -> Vector3
--   UltRules.feetAbove(rootPosition, floorY, height, hitbox?) -> boolean: feet higher than `height` above the floor
--   UltRules.feetWithin(rootPosition, point, radius, hitbox?) -> boolean: |feet - point| <= radius (3D)
--   UltRules.flatEntry(p0, p1, radius, rootPosition, hitbox?) -> number?: the first fraction of the step p0 -> p1 at
--                                                              which a disc of `radius` (horizontal only) touches the
--                                                              capsule, or nil (the roller's lane test)
--   UltRules.rainCenter(target, fallback, zone, floorY)      -> Vector3: the target's (else fallback's) floor point,
--                                                              clamped into the zone box on X and Z
--   UltRules.rainDrops(center, ability, releaseAt, targets, toward?) -> { Drop } (design: fp.js:352-357, 371).
--                                                              Geyser Line (Frosty Box, 2026-11-10; design: lab50.js:295-307):
--                                                              with dropSpacing and `toward` (the flat unit from the
--                                                              caster to the centre) the drops stand in a line ending at
--                                                              the centre, dropSpacing apart, the nearest one first
--   UltRules.ringTouches(center, r0, r1, width, rootPosition, hitbox?) -> boolean: Layer Cake Shockwave (2026-11-10;
--                                                              design: lab50.js:309-325): a ring wall of half-thickness
--                                                              `width` about `center`, grown from radius r0 to r1 in
--                                                              this step, met the capsule (horizontal distances only)
--   UltRules.ringReachTime(startAt, speed, width, d, hitbox?) -> number: when a ring started at startAt (radius 0,
--                                                              `speed` studs/s) first touches a capsule d studs away
--   UltRules.practiceCenter(origin, dir, targets, maxLength) -> Vector3?: the practice target nearest the aim within
--                                                              the practice cone and maxLength (nil = none)
--   UltRules.bowDir(dir, bow, length)                        -> Vector3: Halo Toss (2026-11-10): the flat direction to
--                                                              the far end of a path `length` long whose end lies `bow`
--                                                              studs to the side of the aim (the design's side)
--   UltRules.circleInSlice(center, half, degrees, point, reach) -> boolean / UltRules.inSlice(center, half, degrees,
--                                                              rootPosition, hitbox?): Bread Stamp (2026-11-10)
--   UltRules.bounceDir(dir, normal, maxNormalY)              -> Vector3?: Bubble Pop bounce (2026-10-16): the flat
--                                                              direction after bouncing off a surface with `normal`,
--                                                              mirrored on its horizontal part (the bubble flies at one
--                                                              height); nil for a direction that does not go into the
--                                                              surface, and (review fix) for a surface that is not
--                                                              close to upright: |unit normal.Y| >= maxNormalY (a
--                                                              floor, a ceiling, a ramp, the top of a round prop)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local HitMath = require(script.Parent.HitMath)

-- Types

type Zone = Types.ArenaZone
type Hitbox = HitMath.HitboxConfig

-- One Rain Check drop: where it lands (on the floor), when its shadow shows and when it lands (server times).
export type Drop = { position: Vector3, shadowAt: number, landAt: number }

-- The Config.Abilities fields rainDrops reads.
export type RainSpec = {
	drops: number?,
	firstShadowSeconds: number?,
	dropStepSeconds: number?,
	shadowSeconds: number?,
	fallSeconds: number?,
	dropRadii: { number }?,
	dropAngleStep: number?,
	targetRadius: number?,
	dropSpacing: number?, -- Geyser Line: the drops stand in a line this far apart (with rainDrops' `toward`)
	ringAroundCaster: boolean?, -- Campfire Ring: the ring starts at `toward`'s angle and goes clockwise by dropAngleStep
}

-- Constants

local EPSILON = 1e-6
local FLAT_AXIS_HALF = 1 -- flatEntry's vertical stand-in axis: any length works, the step lies at its middle

-- Module table

local UltRules = {}

-- Private

local function hitboxOf(hitbox: Hitbox?): Hitbox
	return if hitbox ~= nil then hitbox else Config.Combat.Hitbox
end

local function flat(v: Vector3): Vector3?
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < EPSILON then
		return nil
	end
	return f.Unit
end

-- Public

function UltRules.volleyDirs(dir: Vector3, count: number, fanDeg: number): { Vector3 }
	local aim = flat(dir) or Vector3.new(0, 0, -1)
	local n = math.max(1, math.floor(count))
	if n == 1 then
		return { aim }
	end
	local dirs: { Vector3 } = {}
	for index = 0, n - 1 do
		-- A full circle (Puff Burst, 2026-11-10): the first on the aim, the others evenly round.
		local angle = if fanDeg >= 360 then math.rad(360 * index / n) else math.rad(-fanDeg / 2 + fanDeg * index / (n - 1))
		table.insert(dirs, CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(aim))
	end
	return dirs
end

function UltRules.feetPoint(rootPosition: Vector3, hitbox: Hitbox?): Vector3
	local box = hitboxOf(hitbox)
	return rootPosition + Vector3.new(0, box.bottomOffset - box.radius, 0)
end

function UltRules.feetAbove(rootPosition: Vector3, floorY: number, height: number, hitbox: Hitbox?): boolean
	return UltRules.feetPoint(rootPosition, hitbox).Y - floorY > height
end

function UltRules.feetWithin(rootPosition: Vector3, point: Vector3, radius: number, hitbox: Hitbox?): boolean
	return (UltRules.feetPoint(rootPosition, hitbox) - point).Magnitude <= radius
end

function UltRules.flatEntry(p0: Vector3, p1: Vector3, radius: number, rootPosition: Vector3, hitbox: Hitbox?): number?
	local box = hitboxOf(hitbox)
	-- Everything on one horizontal plane: the step at y = 0 and a vertical axis through the HRP centred on it, so the
	-- closest distance is the horizontal one whatever the heights.
	local a = Vector3.new(p0.X, 0, p0.Z)
	local b = Vector3.new(p1.X, 0, p1.Z)
	local capsule: HitMath.Capsule = {
		a = Vector3.new(rootPosition.X, -FLAT_AXIS_HALF, rootPosition.Z),
		b = Vector3.new(rootPosition.X, FLAT_AXIS_HALF, rootPosition.Z),
		radius = box.radius,
	}
	return HitMath.capsuleEntry(a, b, radius, capsule)
end

function UltRules.rainCenter(target: Vector3?, fallback: Vector3, zone: Zone?, floorY: number): Vector3
	local spot = target or fallback
	local point = Vector3.new(spot.X, floorY, spot.Z)
	if zone == nil then
		return point
	end
	local localPoint = zone.cframe:PointToObjectSpace(point)
	local half = zone.size / 2
	local clamped =
		Vector3.new(math.clamp(localPoint.X, -half.X, half.X), localPoint.Y, math.clamp(localPoint.Z, -half.Z, half.Z))
	local world = zone.cframe:PointToWorldSpace(clamped)
	return Vector3.new(world.X, floorY, world.Z)
end

function UltRules.rainDrops(
	center: Vector3,
	ability: RainSpec,
	releaseAt: number,
	targets: { Vector3 },
	toward: Vector3?
): { Drop }
	local count = math.max(0, math.floor(ability.drops or 0))
	local radii = ability.dropRadii or { 0 }
	local step = ability.dropAngleStep or 0
	local first = ability.firstShadowSeconds or 0
	local every = ability.dropStepSeconds or 0
	local warn = (ability.shadowSeconds or 0) + (ability.fallSeconds or 0)
	local positions: { Vector3 } = {}
	local spacing = ability.dropSpacing
	local line = if spacing ~= nil and toward ~= nil then flat(toward) else nil
	local ringDir = if ability.ringAroundCaster and toward ~= nil then flat(toward) else nil
	local angle0 = if ringDir ~= nil then math.atan2(ringDir.Z, ringDir.X) else 0
	for k = 0, count - 1 do
		if line ~= nil then
			positions[k + 1] = center + line * ((k - (count - 1)) * (spacing :: number))
		else
			local angle = if ringDir ~= nil then angle0 - k * step else k * step
			local r = radii[(k % #radii) + 1]
			positions[k + 1] = center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
		end
	end
	-- A target close to the centre gets a drop at its own spot, from the last drop back (design: fp.js:353).
	local reach = ability.targetRadius or 0
	for index, spot in targets do
		local onFloor = Vector3.new(spot.X, center.Y, spot.Z)
		local slot = count - (index - 1)
		if slot >= 1 and (onFloor - center).Magnitude < reach then
			positions[slot] = onFloor
		end
	end
	local drops: { Drop } = {}
	for k = 0, count - 1 do
		local shadowAt = releaseAt + first + every * k
		drops[k + 1] = { position = positions[k + 1], shadowAt = shadowAt, landAt = shadowAt + warn }
	end
	return drops
end

function UltRules.ringTouches(
	center: Vector3,
	r0: number,
	r1: number,
	width: number,
	rootPosition: Vector3,
	hitbox: Hitbox?
): boolean
	local box = hitboxOf(hitbox)
	local d = Vector3.new(rootPosition.X - center.X, 0, rootPosition.Z - center.Z).Magnitude
	return d + box.radius >= r0 - width and d - box.radius <= r1 + width
end

-- Fondue Flood (Lava Box, 2026-11-10): whether a body (its flat circle) reaches into the fan of halfAngle (radians) around
-- the flat `dir` from `center`; a body over the centre is in.
function UltRules.inFan(center: Vector3, dir: Vector3, halfAngle: number, rootPosition: Vector3, hitbox: Hitbox?): boolean
	local box = hitboxOf(hitbox)
	local away = Vector3.new(rootPosition.X - center.X, 0, rootPosition.Z - center.Z)
	local d = away.Magnitude
	if d <= box.radius then
		return true
	end
	local f = flat(dir)
	if f == nil then
		return false
	end
	local angle = math.acos(math.clamp(away.Unit:Dot(f), -1, 1))
	return angle <= halfAngle + math.asin(math.min(1, box.radius / d))
end

-- Prism Pen (Prism Box, 2026-11-10): the corners of the flat equilateral triangle of corner distance `radius` around
-- `center`, the first at `degrees` (atan2 of z, x) and the others 120° on.
function UltRules.triangleCorners(center: Vector3, radius: number, degrees: number): { Vector3 }
	local corners: { Vector3 } = {}
	for index = 0, 2 do
		local angle = math.rad(degrees + 120 * index)
		corners[index + 1] = Vector3.new(center.X + math.cos(angle) * radius, center.Y, center.Z + math.sin(angle) * radius)
	end
	return corners
end

-- Whether a flat circle of radius `reach` around `point` touches that triangle (inside it, or within reach of an edge).
function UltRules.circleInTriangle(center: Vector3, radius: number, degrees: number, point: Vector3, reach: number): boolean
	local corners = UltRules.triangleCorners(center, radius, degrees)
	local px, pz = point.X, point.Z
	local inside = true
	local nearest = math.huge
	for index = 1, 3 do
		local a, b = corners[index], corners[index % 3 + 1]
		local ex, ez = b.X - a.X, b.Z - a.Z
		local cross = ex * (pz - a.Z) - ez * (px - a.X)
		local sideOfCentre = ex * (center.Z - a.Z) - ez * (center.X - a.X)
		if cross * sideOfCentre < 0 then
			inside = false
		end
		local len2 = ex * ex + ez * ez
		local t = if len2 > EPSILON then math.clamp(((px - a.X) * ex + (pz - a.Z) * ez) / len2, 0, 1) else 0
		local dx, dz = px - (a.X + ex * t), pz - (a.Z + ez * t)
		nearest = math.min(nearest, math.sqrt(dx * dx + dz * dz))
	end
	return inside or nearest <= reach
end

-- A body (its flat circle at its feet) in that triangle.
function UltRules.inTriangle(center: Vector3, radius: number, degrees: number, rootPosition: Vector3, hitbox: Hitbox?): boolean
	return UltRules.circleInTriangle(center, radius, degrees, rootPosition, hitboxOf(hitbox).radius)
end

-- Halo Toss (Halo Box, 2026-11-10; design: lab50.js:393, P(u) = o + dir·sin(πu)·L + side·0.6·sin²(πu)): the flat direction
-- from the start to the far end of a path `length` long whose end lies `bow` studs to the side, the design's side
-- (-dir.Z, 0, dir.X). The design's curve stays within a quarter of `bow` of this straight line.
function UltRules.bowDir(dir: Vector3, bow: number, length: number): Vector3
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < EPSILON then
		return Vector3.new(0, 0, -1)
	end
	flat = flat.Unit
	local far = flat * length + Vector3.new(-flat.Z, 0, flat.X) * bow
	return if far.Magnitude < EPSILON then flat else far.Unit
end

-- Bread Stamp (Halo Box, 2026-11-10; design: lab50.js:409-410): a bread slice of half-size `half` around `center`, its
-- crown toward `degrees` (atan2 of z, x): straight sides from -half to SLICE_SHOULDER·half along that way, then a round
-- crown (a half-ellipse) up to half + SLICE_CROWN_STUDS. Whether a flat circle of radius `reach` around `point` touches
-- it (the shape grown by reach: its straight part as a box, its crown as a bigger half-ellipse).
local SLICE_SHOULDER = 0.55 -- lab50.js:409 (lineTo(h, h·0.55))
local SLICE_CROWN_STUDS = 0.1 / 0.28 -- lab50.js:409 (the top at h + 0.1 m)
function UltRules.circleInSlice(center: Vector3, half: number, degrees: number, point: Vector3, reach: number): boolean
	local angle = math.rad(degrees)
	local ux, uz = math.cos(angle), math.sin(angle)
	local dx, dz = point.X - center.X, point.Z - center.Z
	local along = dx * ux + dz * uz
	local across = dz * ux - dx * uz
	local shoulder = SLICE_SHOULDER * half
	if along <= shoulder then
		return math.abs(across) <= half + reach and along >= -half - reach
	end
	local a = half + reach
	local b = half - shoulder + SLICE_CROWN_STUDS + reach
	local x, z = across / a, (along - shoulder) / b
	return x * x + z * z <= 1
end

-- A body (its flat circle at its feet) in that slice.
function UltRules.inSlice(center: Vector3, half: number, degrees: number, rootPosition: Vector3, hitbox: Hitbox?): boolean
	return UltRules.circleInSlice(center, half, degrees, rootPosition, hitboxOf(hitbox).radius)
end

function UltRules.ringReachTime(startAt: number, speed: number, width: number, d: number, hitbox: Hitbox?): number
	local box = hitboxOf(hitbox)
	return startAt + math.max(0, d - box.radius - width) / math.max(speed, EPSILON)
end

function UltRules.practiceCenter(origin: Vector3, dir: Vector3, targets: { Vector3 }, maxLength: number): Vector3?
	local aim = flat(dir)
	if aim == nil then
		return nil
	end
	local minDot = math.cos(math.rad(Config.Combat.Throw.practiceConeDeg))
	local best: Vector3? = nil
	local bestDot = -math.huge
	for _, spot in targets do
		local offset = Vector3.new(spot.X - origin.X, 0, spot.Z - origin.Z)
		local distance = offset.Magnitude
		if distance > EPSILON and distance <= maxLength then
			local dot = offset.Unit:Dot(aim)
			if dot >= minDot and dot > bestDot then
				best, bestDot = spot, dot
			end
		end
	end
	return best
end

function UltRules.bounceDir(dir: Vector3, normal: Vector3, maxNormalY: number): Vector3?
	local d, n = flat(dir), flat(normal)
	if d == nil or n == nil or math.abs(normal.Unit.Y) >= maxNormalY then
		return nil
	end
	local into = d:Dot(n)
	if into > -EPSILON then
		return nil
	end
	return flat(d - n * (2 * into))
end

return table.freeze(UltRules)
