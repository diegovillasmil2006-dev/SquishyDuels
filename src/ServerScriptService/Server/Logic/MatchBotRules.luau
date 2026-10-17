--!strict
-- MatchBotRules: the decisions of the Free for All / Team Deathmatch match bots (owner 2026-10-17). Server only, pure:
-- no instances, no yields; the randomness comes in as a Random (tests seed it), the world as plain values and the
-- raycasts as callbacks. Numbers: Config.Match.Bots (Config/MatchBots, [P]); `cfg` = a table shaped like it (a test's
-- copy), nil = the live one. MatchBotService does everything else; the aim, the name and the dodge direction are the
-- practice bot's (Logic/BotRules).
--
-- API:
--   MatchBotRules.dealTeams(humans, bots, teamNames)      -> { team }: the team of each entrant, humans first: the
--                                                             humans Red, Blue, Red, ... (as MatchService always dealt
--                                                             them), then each bot to the team with fewer players (the
--                                                             first on a tie), so 12 entrants play 6 vs 6
--   MatchBotRules.pickTarget(from, enemies, reach, visible) -> the index of the nearest enemy position within `reach`
--                                                             (flat) that visible(index) says the bot can see, or nil;
--                                                             visible is asked nearest first, only until one is seen
--   MatchBotRules.safeCircle(storm, centre, startRadius, t, cfg?) -> Circle?: the TDM storm's safe circle as it will be
--                                                             stormLookaheadSeconds after Active second t (never larger
--                                                             than now); nil while the storm is not up by then
--   MatchBotRules.insideBounds(point, zone, margin)       -> true inside the zone's box shrunk by margin on X and Z
--   MatchBotRules.pickMove(rng, args, cfg?)               -> where to walk next, or nil (stay, try again soon):
--       1. outside the safe circle (stormMarginStuds inside its edge): back in, toward its centre (the first walkable
--          step of roamStuds, then shorter ones; else the centre itself);
--       2. with padChance: the nearest ready pad within padSeekStuds;
--       3. with a target: a spot within strafeStuds (at least moveMinStuds away) that keeps it keepMinStuds..keepMaxStuds
--          (never past its reach) from the target; with coverChance the first such spot covered(point) says the target
--          cannot see; else the nearest to that band;
--       4. without one, with huntChance: up to roamStuds toward the nearest enemy, at most huntJitterDegrees off the
--          straight line (stopping keepMinStuds short);
--       5. else a random spot moveMinStuds..roamStuds away.
--       Every goal is edgeMarginStuds inside the Bounds, inside the safe circle (when the storm is up) and
--       walkable(from, point) (the service's raycasts: a clear straight path with ground under it); moveCandidates
--       random tries per step.
--   MatchBotRules.threatened(at, origin, velocity, cfg?)  -> true when a throw from `origin` flying `velocity` heads at
--                                                             `at`: within dodgeAngleDegrees (flat), from at most
--                                                             dodgeRangeStuds away

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local StormMath = require(Shared.StormMath)
local Types = require(Shared.Types)

-- Types

type Zone = Types.ArenaZone

export type Circle = { centre: Vector3, radius: number }

export type MoveArgs = {
	from: Vector3, -- the bot's root
	bounds: Zone, -- the map's Bounds
	safe: Circle?, -- the storm's safe circle (safeCircle), nil = no storm now
	target: Vector3?, -- the enemy it fights (seen), nil = none
	reach: number, -- its throw reach: it never keeps farther than this from the target
	hunt: Vector3?, -- the nearest enemy, seen or not, nil = none
	pads: { Vector3 }, -- the ready power-up pads (their tops)
	walkable: (from: Vector3, to: Vector3) -> boolean,
	covered: ((point: Vector3) -> boolean)?, -- the target cannot see that point
}

-- Constants

local FLAT_EPSILON = 1e-6

-- Module table

local MatchBotRules = {}

-- Private

local function bots(cfg: any?): any
	return if cfg ~= nil then cfg else Config.Match.Bots
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

local function between(rng: Random, min: number, max: number): number
	return if max <= min then min else min + rng:NextNumber() * (max - min)
end

-- A point `distance` studs from `from` in the flat direction `angle` (radians), at from's height.
local function around(from: Vector3, angle: number, distance: number): Vector3
	return from + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function insideSafe(point: Vector3, safe: Circle?, margin: number): boolean
	return safe == nil or flatDistance(point, safe.centre) <= safe.radius - margin
end

-- Public

function MatchBotRules.dealTeams(humans: number, botCount: number, teamNames: { string }): { string }
	local out: { string } = {}
	local count = { 0, 0 }
	for i = 1, humans do
		local side = (i - 1) % 2 + 1
		out[i] = teamNames[side]
		count[side] += 1
	end
	for i = 1, botCount do
		local side = if count[2] < count[1] then 2 else 1
		out[humans + i] = teamNames[side]
		count[side] += 1
	end
	return out
end

function MatchBotRules.pickTarget(
	from: Vector3,
	enemies: { Vector3 },
	reach: number,
	visible: (index: number) -> boolean
): number?
	local order: { { index: number, distance: number } } = {}
	for index, position in enemies do
		local distance = flatDistance(from, position)
		if distance <= reach then
			table.insert(order, { index = index, distance = distance })
		end
	end
	table.sort(order, function(a, b)
		return a.distance < b.distance
	end)
	for _, entry in order do
		if visible(entry.index) then
			return entry.index
		end
	end
	return nil
end

function MatchBotRules.safeCircle(storm: any, centre: Vector3, startRadius: number, t: number, cfg: any?): Circle?
	local later = t + bots(cfg).stormLookaheadSeconds
	if not StormMath.shown(storm, later) then
		return nil
	end
	local radius = math.min(StormMath.radiusAt(storm, startRadius, t), StormMath.radiusAt(storm, startRadius, later))
	return { centre = centre, radius = radius }
end

function MatchBotRules.insideBounds(point: Vector3, zone: Zone, margin: number): boolean
	local p = zone.cframe:PointToObjectSpace(point)
	return math.abs(p.X) <= zone.size.X / 2 - margin and math.abs(p.Z) <= zone.size.Z / 2 - margin
end

function MatchBotRules.pickMove(rng: Random, args: MoveArgs, cfg: any?): Vector3?
	local c = bots(cfg)
	local from = args.from
	local safe = args.safe

	-- A goal it may walk to: inside the Bounds and the safe circle, far enough, on a walkable path (raycasts last).
	local function ok(point: Vector3, minStuds: number): boolean
		return MatchBotRules.insideBounds(point, args.bounds, c.edgeMarginStuds)
			and insideSafe(point, safe, c.stormMarginStuds)
			and flatDistance(point, from) >= minStuds
			and args.walkable(from, point)
	end

	-- 1. Out of the (coming) storm: back in first.
	if safe ~= nil and not insideSafe(from, safe, c.stormMarginStuds) then
		local centre = Vector3.new(safe.centre.X, from.Y, safe.centre.Z)
		local toCentre = flat(centre - from)
		local distance = toCentre.Magnitude
		if distance > FLAT_EPSILON then
			for k = 1, c.moveCandidates do
				local step = math.min(c.roamStuds * (1 - (k - 1) / c.moveCandidates), distance)
				local point = from + toCentre.Unit * step
				if MatchBotRules.insideBounds(point, args.bounds, c.edgeMarginStuds) and args.walkable(from, point) then
					return point
				end
			end
		end
		return centre
	end

	-- 2. A ready power-up pad nearby, sometimes.
	if #args.pads > 0 and rng:NextNumber() < c.padChance then
		local best: Vector3? = nil
		local bestDistance = c.padSeekStuds
		for _, pad in args.pads do
			local distance = flatDistance(pad, from)
			if distance <= bestDistance and ok(pad, 0) then
				best, bestDistance = pad, distance
			end
		end
		if best then
			return best
		end
	end

	-- 3. A target: strafe at a good distance, behind cover sometimes.
	local target = args.target
	if target ~= nil then
		local keepMax = math.min(c.keepMaxStuds, args.reach)
		local keepMin = math.min(c.keepMinStuds, keepMax)
		local wantCover = args.covered ~= nil and rng:NextNumber() < c.coverChance
		local best: Vector3? = nil
		local bestMiss = math.huge
		for _ = 1, c.moveCandidates do
			local point = around(from, rng:NextNumber() * 2 * math.pi, between(rng, c.moveMinStuds, c.strafeStuds))
			if ok(point, c.moveMinStuds) then
				local distance = flatDistance(point, target)
				local miss = if distance < keepMin then keepMin - distance else math.max(distance - keepMax, 0)
				if miss == 0 and (not wantCover or (args.covered :: (Vector3) -> boolean)(point)) then
					return point
				end
				if miss < bestMiss then
					best, bestMiss = point, miss
				end
			end
		end
		return best
	end

	-- 4. No target: hunt the nearest enemy, sometimes.
	local hunt = args.hunt
	if hunt ~= nil and rng:NextNumber() < c.huntChance then
		local line = flat(hunt - from)
		local reachable = math.min(c.roamStuds, line.Magnitude - c.keepMinStuds)
		if reachable >= c.moveMinStuds then
			local heading = math.atan2(line.Z, line.X)
			for _ = 1, c.moveCandidates do
				local angle = heading + (rng:NextNumber() * 2 - 1) * math.rad(c.huntJitterDegrees)
				local point = around(from, angle, between(rng, c.moveMinStuds, reachable))
				if ok(point, c.moveMinStuds) then
					return point
				end
			end
		end
	end

	-- 5. Roam.
	for _ = 1, c.moveCandidates do
		local point = around(from, rng:NextNumber() * 2 * math.pi, between(rng, c.moveMinStuds, c.roamStuds))
		if ok(point, c.moveMinStuds) then
			return point
		end
	end
	return nil
end

function MatchBotRules.threatened(at: Vector3, origin: Vector3, velocity: Vector3, cfg: any?): boolean
	local c = bots(cfg)
	local line = flat(at - origin)
	local flight = flat(velocity)
	local distance = line.Magnitude
	if distance > c.dodgeRangeStuds or distance < FLAT_EPSILON or flight.Magnitude < FLAT_EPSILON then
		return false
	end
	return line.Unit:Dot(flight.Unit) >= math.cos(math.rad(c.dodgeAngleDegrees))
end

return table.freeze(MatchBotRules)
