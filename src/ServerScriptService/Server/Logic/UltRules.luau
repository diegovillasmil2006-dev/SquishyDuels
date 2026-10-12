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
--   UltRules.rainDrops(center, ability, releaseAt, targets)  -> { Drop } (design: fp.js:352-357, 371)
--   UltRules.practiceCenter(origin, dir, targets, maxLength) -> Vector3?: the practice target nearest the aim within
--                                                              the practice cone and maxLength (nil = none)

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
		local angle = math.rad(-fanDeg / 2 + fanDeg * index / (n - 1))
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

function UltRules.rainDrops(center: Vector3, ability: RainSpec, releaseAt: number, targets: { Vector3 }): { Drop }
	local count = math.max(0, math.floor(ability.drops or 0))
	local radii = ability.dropRadii or { 0 }
	local step = ability.dropAngleStep or 0
	local first = ability.firstShadowSeconds or 0
	local every = ability.dropStepSeconds or 0
	local warn = (ability.shadowSeconds or 0) + (ability.fallSeconds or 0)
	local positions: { Vector3 } = {}
	for k = 0, count - 1 do
		local angle = k * step
		local r = radii[(k % #radii) + 1]
		positions[k + 1] = center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
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

return table.freeze(UltRules)
