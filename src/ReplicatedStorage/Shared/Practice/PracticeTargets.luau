--!strict
-- PracticeTargets: the practice range's targets and the moving target's path (DESIGN §5.11, §7.6). Shared, pure:
-- no instances, no clock. Server hits (PracticeService) and client animation (PracticeController) both call
-- positionAt(target, workspace:GetServerTimeNow()), so they agree with no per-frame replication.
-- * Data comes from World/WorldLayout.PracticeRange, the table the lobby generator builds the range from. A target's
--   `position` is its floor point: where the generated model's pivot sits (on the lane floor top) and, for the
--   moving target, the centre of its rail.
-- * The moving target slides along Z: offset = railLength/2 · sin(2π · (serverTime mod period) / period); peak speed
--   railLength/2 · 2π/period (12 studs, 9.42 s: ≈ 4 studs/s). Static targets (moving false, railLength 0 or period 0)
--   never move.
-- * Hitbox = the standard player capsule (Config.Combat.Hitbox, §5.5) on a virtual root ROOT_HEIGHT above the floor
--   point, so it spans floor+0 .. floor+6.1 like a standing R15 player.
-- * Practice context for ThrowRules (§5.6 #3, #5, #6): inThrowBox (the SD_PracticeZone box) and inCone (flat aim
--   within Config.Combat.Throw.practiceConeDeg of the range forward, WorldLayout's throwDirection: +X, the island's
--   range runs east, lobby bases spec §3 and D3).

local Config = require(script.Parent.Parent.Config)
local WorldLayout = require(script.Parent.Parent.World.WorldLayout)

export type TargetDef = {
	id: string, -- TargetId ("target_01".."target_04")
	distance: number, -- studs from the firing line
	position: Vector3, -- floor point (rail centre for the moving target)
	moving: boolean,
	railLength: number, -- along Z, centred on `position`
	period: number, -- seconds
}

-- An axis-aligned box: centre and full size.
export type Box = { position: Vector3, size: Vector3 }

local RANGE = WorldLayout.PracticeRange
local ATTRIBUTES = WorldLayout.Attributes
local HITBOX = Config.Combat.Hitbox
local TWO_PI = 2 * math.pi
local MIN_FLAT_AIM = 1e-6

-- The capsule's lowest point (root + bottomOffset - radius) sits on the floor point.
local ROOT_HEIGHT = HITBOX.radius - HITBOX.bottomOffset

-- Reading (not in DESIGN): practice projectiles expire when they leave this box, as duel projectiles do outside the
-- arena Bounds (§5.7). Phase 3: the box is WorldLayout.PracticeRange.bounds (the design range from its throw box to
-- the hub's east edge, the arena zones' height).
local BOUNDS: Box = table.freeze({
	position = RANGE.bounds.position,
	size = RANGE.bounds.size,
})

local PracticeTargets = {}

PracticeTargets.ROOT_HEIGHT = ROOT_HEIGHT
PracticeTargets.FLOOR_Y = RANGE.laneFloorTopY -- the lane floor top (projectile shadow discs, §9.7)
PracticeTargets.FORWARD = RANGE.throwDirection -- range forward: throws go toward +X (D3)
PracticeTargets.THROW_BOX = table.freeze({ position = RANGE.throwBox.position, size = RANGE.throwBox.size }) :: Box
PracticeTargets.BOUNDS = BOUNDS

-- Private ------------------------------------------------------------------------------------------------------------

local function isFinite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function inBox(box: Box, point: Vector3): boolean
	local offset = point - box.position
	local half = box.size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

local function isMoving(target: TargetDef): boolean
	return target.moving and target.railLength > 0 and target.period > 0
end

-- Phase angle (radians) of a moving target at a server time. fmod is exact, so large server times stay precise.
local function phaseAt(target: TargetDef, serverTime: number): number
	return TWO_PI * math.fmod(serverTime, target.period) / target.period
end

-- The definitions, built once from WorldLayout (floor points lifted to the lane floor top).
local defs: { TargetDef } = {}
local byId: { [string]: TargetDef } = {}
for _, target in RANGE.targets do
	local def: TargetDef = table.freeze({
		id = target.id,
		distance = target.distance,
		position = Vector3.new(target.position.X, RANGE.laneFloorTopY, target.position.Z),
		moving = target.moving,
		railLength = target.railLength,
		period = target.period,
	})
	table.insert(defs, def)
	byId[def.id] = def
end
table.freeze(defs)
table.freeze(byId)

-- Public: definitions ------------------------------------------------------------------------------------------------

-- Every target, in WorldLayout order (lane by lane, nearest first). Frozen.
function PracticeTargets.list(): { TargetDef }
	return defs
end

-- The target with this TargetId, or nil.
function PracticeTargets.get(id: string): TargetDef?
	return byId[id]
end

-- A definition from a tagged SD_PracticeTarget instance: its attributes (TargetId, Distance, Moving, RailLength,
-- Period; §2.9) and its floor point (the model's pivot position as built). Nil when an attribute is missing or wrong.
function PracticeTargets.fromAttributes(attributes: { [string]: any }, floorPoint: Vector3): TargetDef?
	local id = attributes[ATTRIBUTES.TargetId]
	local distance = attributes[ATTRIBUTES.Distance]
	local moving = attributes[ATTRIBUTES.Moving]
	local railLength = attributes[ATTRIBUTES.RailLength]
	local period = attributes[ATTRIBUTES.Period]
	if
		type(id) ~= "string"
		or id == ""
		or not isFinite(distance)
		or type(moving) ~= "boolean"
		or not isFinite(railLength)
		or railLength < 0
		or not isFinite(period)
		or period < 0
		or typeof(floorPoint) ~= "Vector3"
	then
		return nil
	end
	return table.freeze({
		id = id,
		distance = distance,
		position = floorPoint,
		moving = moving,
		railLength = railLength,
		period = period,
	})
end

-- Public: motion -----------------------------------------------------------------------------------------------------

-- Floor point of the target at a server time.
function PracticeTargets.positionAt(target: TargetDef, serverTime: number): Vector3
	if not isMoving(target) or not isFinite(serverTime) then
		return target.position
	end
	local offset = target.railLength / 2 * math.sin(phaseAt(target, serverTime))
	return target.position + Vector3.new(0, 0, offset)
end

-- Velocity of the target at a server time (studs/s, along Z).
function PracticeTargets.velocityAt(target: TargetDef, serverTime: number): Vector3
	if not isMoving(target) or not isFinite(serverTime) then
		return Vector3.zero
	end
	local speed = target.railLength / 2 * TWO_PI / target.period * math.cos(phaseAt(target, serverTime))
	return Vector3.new(0, 0, speed)
end

-- Fastest speed of the target (studs/s); 0 for a static one.
function PracticeTargets.peakSpeed(target: TargetDef): number
	if not isMoving(target) then
		return 0
	end
	return target.railLength / 2 * TWO_PI / target.period
end

-- The virtual root of the target's hitbox (the equivalent of a player's HumanoidRootPart position).
function PracticeTargets.rootAt(target: TargetDef, serverTime: number): Vector3
	return PracticeTargets.positionAt(target, serverTime) + Vector3.new(0, ROOT_HEIGHT, 0)
end

-- The target's hitbox at a server time: the capsule axis (bottom, top) and radius, exactly as for a player (§5.5).
function PracticeTargets.capsuleAt(target: TargetDef, serverTime: number): (Vector3, Vector3, number)
	local root = PracticeTargets.rootAt(target, serverTime)
	return root + Vector3.new(0, HITBOX.bottomOffset, 0), root + Vector3.new(0, HITBOX.topOffset, 0), HITBOX.radius
end

-- Public: practice context -------------------------------------------------------------------------------------------

-- True when a position (the server HRP) is inside the throw box, the SD_PracticeZone (§5.11, §7.6).
function PracticeTargets.inThrowBox(position: Vector3): boolean
	return inBox(PracticeTargets.THROW_BOX, position)
end

-- True when the flat part of an aim direction is within coneDeg (default Config.Combat.Throw.practiceConeDeg) of
-- the range forward: dot(flat aim, forward) >= cos(cone) (§5.6 #6). A vertical aim has no flat part: false.
function PracticeTargets.inCone(aimDir: Vector3, coneDeg: number?): boolean
	local cone = if coneDeg == nil then Config.Combat.Throw.practiceConeDeg else coneDeg
	local flat = Vector3.new(aimDir.X, 0, aimDir.Z)
	if flat.Magnitude < MIN_FLAT_AIM then
		return false
	end
	return flat.Unit:Dot(PracticeTargets.FORWARD) >= math.cos(math.rad(cone))
end

-- True while a practice projectile is still inside the range (BOUNDS).
function PracticeTargets.inBounds(position: Vector3): boolean
	return inBox(BOUNDS, position)
end

return table.freeze(PracticeTargets)
