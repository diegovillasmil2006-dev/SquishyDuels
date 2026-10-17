--!strict
-- BotRules: the 1v1 practice bot's decisions (owner 2026-10-16). Server only, pure: no instances, no yields; the
-- randomness comes in as a Random (tests seed it) and the world as plain values. Numbers: Config.Duel.Bots (Config/Bots,
-- [P]); `cfg` = a table shaped like it (a test's copy), nil = the live one. BotService does everything else.
--
-- API:
--   BotRules.between(rng, min, max)                    -> a number in [min, max]
--   BotRules.name(rng, starts, ends, cfg?)             -> <start><end>[_]<number>: letters, digits and at most one
--                                                         underscore (never first or last), like a Roblox username
--   BotRules.fillDelay(rng, cfg?)                      -> seconds in [fillDelayMinSeconds, fillDelayMaxSeconds]
--   BotRules.watch(watch, waiterUserId, now, rng, cfg?) -> (watch, due): the lone-waiter timer. A new waiter (or a
--                                                         different one) starts a fresh timer with its own fillDelay;
--                                                         nobody alone clears it; due once the waiter waited that long
--   BotRules.aimOffset(rng, distance, cfg?)            -> a flat random miss of at most min(aimErrorBaseStuds +
--                                                         aimErrorPerStud × distance, aimErrorMaxStuds) studs
--   BotRules.aimPoint(rng, target, velocity, flightSeconds, distance, cfg?)
--                                                      -> target + aimOffset + the lead: leadFraction × the flat
--                                                         velocity × flightSeconds
--   BotRules.pointInZone(rng, zone, margin, y)         -> a random point of the zone's box shrunk by `margin` on X and Z
--                                                         (its own axes), at height y
--   BotRules.pickMove(rng, zone, from, cfg?, covered?) -> where to walk next: a point of the zone at least moveMinStuds
--                                                         (flat) from `from` (when one is found in moveCandidates tries);
--                                                         with coverChance, the first of them `covered(point)` says the
--                                                         player cannot see
--   BotRules.dodgeDir(rng, from, threat)               -> a flat unit direction across the line from `from` to `threat`
--                                                         (left or right at random)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

-- Types

type Zone = Types.ArenaZone

-- The lone-waiter timer (watch).
export type Watch = { userId: number, since: number, delay: number }

-- Constants

local FLAT_EPSILON = 1e-6

-- Module table

local BotRules = {}

-- Private

local function bots(cfg: any?): any
	return if cfg ~= nil then cfg else Config.Duel.Bots
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Public

function BotRules.between(rng: Random, min: number, max: number): number
	if max <= min then
		return min
	end
	return min + rng:NextNumber() * (max - min)
end

function BotRules.name(rng: Random, starts: { string }, ends: { string }, cfg: any?): string
	local c = bots(cfg)
	local first = starts[rng:NextInteger(1, #starts)]
	local second = ends[rng:NextInteger(1, #ends)]
	local separator = if rng:NextNumber() < c.nameUnderscoreChance then "_" else ""
	return first .. second .. separator .. tostring(rng:NextInteger(c.nameDigitsMin, c.nameDigitsMax))
end

function BotRules.fillDelay(rng: Random, cfg: any?): number
	local c = bots(cfg)
	return BotRules.between(rng, c.fillDelayMinSeconds, c.fillDelayMaxSeconds)
end

function BotRules.watch(watch: Watch?, waiterUserId: number?, now: number, rng: Random, cfg: any?): (Watch?, boolean)
	if waiterUserId == nil then
		return nil, false
	end
	if watch == nil or watch.userId ~= waiterUserId then
		return { userId = waiterUserId, since = now, delay = BotRules.fillDelay(rng, cfg) }, false
	end
	return watch, now - watch.since >= watch.delay
end

function BotRules.aimOffset(rng: Random, distance: number, cfg: any?): Vector3
	local c = bots(cfg)
	local spread = math.min(c.aimErrorBaseStuds + c.aimErrorPerStud * math.max(distance, 0), c.aimErrorMaxStuds)
	if spread <= 0 then
		return Vector3.zero
	end
	local angle = rng:NextNumber() * 2 * math.pi
	local radius = spread * rng:NextNumber() -- uniform radius: most throws land near, some far (a person's miss)
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

function BotRules.aimPoint(
	rng: Random,
	target: Vector3,
	velocity: Vector3,
	flightSeconds: number,
	distance: number,
	cfg: any?
): Vector3
	local c = bots(cfg)
	local lead = Vector3.new(velocity.X, 0, velocity.Z) * (math.max(flightSeconds, 0) * c.leadFraction)
	return target + lead + BotRules.aimOffset(rng, distance, cfg)
end

function BotRules.pointInZone(rng: Random, zone: Zone, margin: number, y: number): Vector3
	local half = zone.size / 2
	local x = (rng:NextNumber() * 2 - 1) * math.max(half.X - margin, 0)
	local z = (rng:NextNumber() * 2 - 1) * math.max(half.Z - margin, 0)
	local world = zone.cframe:PointToWorldSpace(Vector3.new(x, 0, z))
	return Vector3.new(world.X, y, world.Z)
end

function BotRules.pickMove(
	rng: Random,
	zone: Zone,
	from: Vector3,
	cfg: any?,
	covered: ((point: Vector3) -> boolean)?
): Vector3
	local c = bots(cfg)
	local wantCover = covered ~= nil and rng:NextNumber() < c.coverChance
	local first: Vector3? = nil
	for _ = 1, c.moveCandidates do
		local point = BotRules.pointInZone(rng, zone, c.edgeMarginStuds, from.Y)
		if flatDistance(point, from) >= c.moveMinStuds then
			if not wantCover or (covered :: (Vector3) -> boolean)(point) then
				return point
			end
			first = first or point
		end
	end
	return first or BotRules.pointInZone(rng, zone, c.edgeMarginStuds, from.Y)
end

function BotRules.dodgeDir(rng: Random, from: Vector3, threat: Vector3): Vector3
	local line = Vector3.new(threat.X - from.X, 0, threat.Z - from.Z)
	if line.Magnitude < FLAT_EPSILON then
		line = Vector3.new(0, 0, 1)
	end
	local across = Vector3.new(-line.Z, 0, line.X).Unit
	return if rng:NextNumber() < 0.5 then across else -across
end

return table.freeze(BotRules)
