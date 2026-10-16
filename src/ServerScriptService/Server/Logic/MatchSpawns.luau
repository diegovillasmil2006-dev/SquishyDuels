--!strict
-- MatchSpawns: where Free for All / Team Deathmatch players stand on Diego's maps (SPEC D12, FFA/TDM v1 2026-10-15).
-- Server only, pure: no instances, no yields; the pads, the players' positions, the randomness and the raycast come in
-- as arguments, so every rule is unit-tested. MatchMapService reads each map's spawn pads (boxes: cframe and size, a
-- TDM pad with its team) and builds the map's SpawnSet once; MatchService places and respawns players with it.
-- * Spots: Config.Match.Spawns.spotsPerPad[mode] points (6 per TDM pad, 2 per FFA pad) on a grid inside each pad box,
--   each at least edgeStuds from the pad's edges, on the pad's top face. A spot faces the map centre (flat). A spot is
--   the feet point: the service adds the character's stand height (placement).
-- * First placement: TDM: the own team's spots in order (round again past the last); FFA: the players spread over the
--   pads round robin (player 1 on pad 1, player 2 on pad 2, ..., then the second spot of each pad).
-- * Respawn: TDM: a random spot of the own team's pads with no other standing player within occupiedStuds
--   (horizontally), never the spot the player stood on last while another free one exists (any spot when all are
--   taken); FFA: the pad whose nearest standing enemy is farthest (ties: random), then a free spot on it. When the storm
--   is up and the chosen spot is in it (StormMath.inStorm), the spot moves onto the safe circle: from the centre toward
--   the own team's pads (TDM) / the chosen pad (FFA), at radius - Storm.respawnInsetStuds, on the floor, raised onto
--   any geometry by a downward raycast from raycastUpStuds above it (the caller's raycast, the map's raycastParams).
-- * A map with no pad for a team falls back to every spot; a map with no spot at all to its centre.
--
-- API (`cfg` = a Config.Match-shaped table; nil = the live Config.Match):
--   MatchSpawns.gridPoints(pad, count, edgeStuds) -> { Vector3 }      count points on the pad's top face
--   MatchSpawns.build(pads, centre, floorY, modeId, cfg?) -> SpawnSet
--   MatchSpawns.spotsFor(set, team?) -> { Spot }                      a team's spots (nil = every spot)
--   MatchSpawns.firstSpots(set, entrants) -> { [userId]: Spot }       entrants = { { userId, team? } } in order
--   MatchSpawns.respawnSpot(set, args, cfg?) -> Spot                  args: RespawnArgs
--   MatchSpawns.safeSpot(set, toward, storm, raycast?, cfg?) -> Spot  the point on the safe circle toward `toward`
--   MatchSpawns.placement(spot, standHeight) -> CFrame                the character's pivot on the spot

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local StormMath = require(Shared.StormMath)

-- Types

-- A spawn pad's box (Model:GetBoundingBox or a part's CFrame and Size); `team` names a Config.Match.teamNames team
-- (TDM pads), nil for an FFA pad.
export type Pad = { cframe: CFrame, size: Vector3, team: string? }

-- Where one player stands: the feet point, the flat facing and the pad index in its set (0 = a storm-circle spot).
export type Spot = { position: Vector3, facing: Vector3, pad: number }

export type SpawnSet = {
	pads: { Pad },
	spotsOf: { { Spot } }, -- spotsOf[i] = the spots of pads[i]
	centre: Vector3, -- the map centre at floor height
	floorY: number,
}

export type Entrant = { userId: number, team: string? }

-- The storm's safe circle (only when the storm is shown); `centre` at floor height.
export type StormCircle = { centre: Vector3, radius: number }

-- (origin, direction) -> the hit position, or nil: a Workspace:Raycast with the map's raycastParams.
export type Raycast = (origin: Vector3, direction: Vector3) -> Vector3?

export type RespawnArgs = {
	team: string?, -- TDM: the player's team; nil in FFA
	enemies: { Vector3 }, -- standing enemies' positions (FFA: every other standing player)
	occupied: { Vector3 }, -- every other standing player's position
	last: Spot?, -- the spot the player stood on last
	r: number, -- a random number in [0, 1) (Random:NextNumber())
	storm: StormCircle?,
	raycast: Raycast?,
}

-- Constants

local EPSILON = 1e-6
local DEFAULT_FACING = Vector3.new(0, 0, -1)
local RAY_BELOW_FLOOR_STUDS = 1 -- reading: the downward ray ends a little under the floor, so the floor itself is hit

-- Module table

local MatchSpawns = {}

-- Private --------------------------------------------------------------------------------------------------------------

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- The flat unit direction from `from` toward `to` (DEFAULT_FACING when they stand on the same spot).
local function facingToward(from: Vector3, to: Vector3): Vector3
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if flat.Magnitude <= EPSILON then
		return DEFAULT_FACING
	end
	return flat.Unit
end

-- 1-based index for a random r in [0, 1) over n items, and the r left over for a second pick.
local function pick(r: number, n: number): (number, number)
	local scaled = math.clamp(r, 0, 1 - EPSILON) * n
	local index = math.floor(scaled)
	return math.clamp(index + 1, 1, n), scaled - index
end

local function nearest(point: Vector3, list: { Vector3 }): number
	local best = math.huge
	for _, other in list do
		best = math.min(best, flatDistance(point, other))
	end
	return best
end

local function isFree(spot: Spot, occupied: { Vector3 }, radius: number): boolean
	return nearest(spot.position, occupied) > radius
end

local function sameSpot(a: Spot?, b: Spot?): boolean
	return a ~= nil and b ~= nil and flatDistance(a.position, b.position) <= EPSILON
end

-- The free spots of `list` (not the last one when another is free), else every spot.
local function freeSpots(list: { Spot }, occupied: { Vector3 }, last: Spot?, radius: number): { Spot }
	local free: { Spot } = {}
	for _, spot in list do
		if isFree(spot, occupied, radius) then
			table.insert(free, spot)
		end
	end
	if #free > 1 and last ~= nil then
		for index, spot in free do
			if sameSpot(spot, last) then
				table.remove(free, index)
				break
			end
		end
	end
	return if #free > 0 then free else list
end

local function average(list: { Spot }): Vector3
	local sum = Vector3.zero
	for _, spot in list do
		sum += spot.position
	end
	return if #list > 0 then sum / #list else Vector3.zero
end

local function centreSpot(set: SpawnSet): Spot
	return { position = set.centre, facing = DEFAULT_FACING, pad = 0 }
end

-- Public ---------------------------------------------------------------------------------------------------------------

function MatchSpawns.gridPoints(pad: Pad, count: number, edgeStuds: number): { Vector3 }
	local size = pad.size
	local width = math.max(0, size.X - 2 * edgeStuds)
	local depth = math.max(0, size.Z - 2 * edgeStuds)
	local columns: number
	if width <= EPSILON then
		columns = 1
	elseif depth <= EPSILON then
		columns = count
	else
		columns = math.clamp(math.floor(math.sqrt(count * width / depth) + 0.5), 1, count)
	end
	local rows = math.ceil(count / columns)
	local points: { Vector3 } = {}
	for i = 0, count - 1 do
		local column, row = i % columns, i // columns
		local x = if columns > 1 then -width / 2 + width * column / (columns - 1) else 0
		local z = if rows > 1 then -depth / 2 + depth * row / (rows - 1) else 0
		table.insert(points, pad.cframe:PointToWorldSpace(Vector3.new(x, size.Y / 2, z)))
	end
	return points
end

function MatchSpawns.build(pads: { Pad }, centre: Vector3, floorY: number, modeId: string, cfg: any?): SpawnSet
	local c = cfg or Config.Match
	local spawns = c.Spawns
	local count = spawns.spotsPerPad[modeId] or 1
	local floorCentre = Vector3.new(centre.X, floorY, centre.Z)
	local spotsOf: { { Spot } } = {}
	for index, pad in pads do
		local spots: { Spot } = {}
		for _, point in MatchSpawns.gridPoints(pad, count, spawns.edgeStuds) do
			table.insert(spots, { position = point, facing = facingToward(point, floorCentre), pad = index })
		end
		spotsOf[index] = spots
	end
	return { pads = pads, spotsOf = spotsOf, centre = floorCentre, floorY = floorY }
end

function MatchSpawns.spotsFor(set: SpawnSet, team: string?): { Spot }
	local all: { Spot } = {}
	local own: { Spot } = {}
	for index, pad in set.pads do
		local spots = set.spotsOf[index]
		if spots ~= nil then
			for _, spot in spots do
				table.insert(all, spot)
				if team ~= nil and pad.team == team then
					table.insert(own, spot)
				end
			end
		end
	end
	if #own > 0 then
		return own
	end
	return if #all > 0 then all else { centreSpot(set) }
end

function MatchSpawns.firstSpots(set: SpawnSet, entrants: { Entrant }): { [number]: Spot }
	local out: { [number]: Spot } = {}
	local nextOfTeam: { [string]: number } = {}
	local padsWithSpots: { number } = {}
	for index in set.pads do
		if #(set.spotsOf[index] or {}) > 0 then
			table.insert(padsWithSpots, index)
		end
	end
	local ffaCount = 0
	for _, entrant in entrants do
		local team = entrant.team
		if team ~= nil then
			local list = MatchSpawns.spotsFor(set, team)
			local taken = nextOfTeam[team] or 0
			out[entrant.userId] = list[taken % #list + 1]
			nextOfTeam[team] = taken + 1
		elseif #padsWithSpots == 0 then
			out[entrant.userId] = centreSpot(set)
		else
			local padIndex = padsWithSpots[ffaCount % #padsWithSpots + 1]
			local spots = set.spotsOf[padIndex]
			out[entrant.userId] = spots[(ffaCount // #padsWithSpots) % #spots + 1]
			ffaCount += 1
		end
	end
	return out
end

function MatchSpawns.safeSpot(set: SpawnSet, toward: Vector3, storm: StormCircle, raycast: Raycast?, cfg: any?): Spot
	local c = cfg or Config.Match
	local centre = storm.centre
	local direction = facingToward(centre, toward) -- a pad right at the centre: DEFAULT_FACING
	local distance = math.max(0, storm.radius - c.Storm.respawnInsetStuds)
	local ground = Vector3.new(centre.X, set.floorY, centre.Z) + direction * distance
	local y = set.floorY
	if raycast ~= nil then
		local up = c.Spawns.raycastUpStuds
		local hit = raycast(ground + Vector3.new(0, up, 0), Vector3.new(0, -(up + RAY_BELOW_FLOOR_STUDS), 0))
		if hit ~= nil then
			y = math.max(y, hit.Y)
		end
	end
	local position = Vector3.new(ground.X, y, ground.Z)
	return { position = position, facing = facingToward(position, centre), pad = 0 }
end

function MatchSpawns.respawnSpot(set: SpawnSet, args: RespawnArgs, cfg: any?): Spot
	local c = cfg or Config.Match
	local radius = c.Spawns.occupiedStuds
	local chosen: Spot
	local toward: Vector3
	if args.team ~= nil then
		local own = MatchSpawns.spotsFor(set, args.team)
		local free = freeSpots(own, args.occupied, args.last, radius)
		chosen = free[(pick(args.r, #free))]
		toward = average(own)
	else
		-- The pad whose nearest standing enemy is farthest; ties (no enemies at all included) are broken at random.
		local best: { number } = {}
		local bestScore = -math.huge
		for index, spots in set.spotsOf do
			if #spots > 0 then
				local score = nearest(average(spots), args.enemies)
				if score > bestScore + EPSILON then
					best, bestScore = { index }, score
				elseif score >= bestScore - EPSILON then
					table.insert(best, index)
				end
			end
		end
		if #best == 0 then
			return centreSpot(set)
		end
		local padPick, rest = pick(args.r, #best)
		local spots = set.spotsOf[best[padPick]]
		local free = freeSpots(spots, args.occupied, args.last, radius)
		chosen = free[(pick(rest, #free))]
		toward = average(spots)
	end
	local storm = args.storm
	if storm ~= nil and StormMath.inStorm(storm.centre, storm.radius, chosen.position) then
		return MatchSpawns.safeSpot(set, toward, storm, args.raycast, c)
	end
	return chosen
end

function MatchSpawns.placement(spot: Spot, standHeight: number): CFrame
	local at = spot.position + Vector3.new(0, standHeight, 0)
	return CFrame.lookAt(at, at + spot.facing)
end

return MatchSpawns
