--!strict
-- HighwayMath: pure throw arithmetic (pens3 phase 13, 2026-10-18; work/pens3/PLAN.md "PHASE 13" with the owner's
-- corrections, work/pens3/p13v2/NOTES.md). Shared: the server decides every throw with it (HighwayService) and the
-- client draws the same flight (HighwayThrowController). Every number is Config.Economy.Highway's (Config/Highway: its
-- sources), the throw area, the rings and the pads WorldLayout.Highway's. No instances, no yields, no side effects.
-- P13v4 (owner 2026-10-19: the TikTok throw; work/pens3/p13v4/SPEC.md 2, 3, 5.5, numbers from its spec/curve.js): a
-- throw is a flight plan (Core: a list of air arcs and a final roll, on the shared server clock) the server makes at
-- the press and changes at a boost; the PERFECT bar, the boost, the rings and the BULLSEYE pads. `flight`, `at` and the
-- Flight type are gone.
--
-- API:
--   HighwayMath.power(level, gear?)   -> number: the throw power of a Grip level, base x perGripLevel^(level - 1)
--                                        (p13v4: Lv 1 900); a level that is not a whole number >= 1 counts as Lv 1,
--                                        a fraction is cut; gear step 2: x GearMath.multiplier(gear) (none = x1)
--   HighwayMath.landing(power)        -> number: whole studs from the start line (cut), in [0, gatesAt]: biome n
--                                        (walls[n] <= P < walls[n + 1], walls[8] = gatesPower) at starts[n] +
--                                        length_n x ln(P / walls[n]) / ln(walls[n + 1] / walls[n]) (V4:76, SIM:89);
--                                        0 at walls[1] or less (and for anything that is not a number), gatesAt from
--                                        gatesPower
--   HighwayMath.biomeAt(studs)        -> 1..#starts: the biome a landing lies in (SIM:90; the Golden Gates are in the
--                                        last one); a broken distance is biome 1
--   HighwayMath.reached(studs)        -> 1..#starts + 1: what a landing reaches (#starts + 1 = the Golden Gates), the
--                                        saved profile.highway.biome
--   HighwayMath.landingCoins(sv, studs, rings?) -> number: PenMath.rewardCoins(pay.perStud x studs x (1 +
--                                        pay.ringShare x r), sv) (p13v3: Coins by distance; p13v4: + a share a ring
--                                        hit); studs held in [0, gatesAt], a broken distance pays 0; r = the whole
--                                        rings when a finite number > 0, else 0
--   HighwayMath.barAt(t)              -> 0..1: the PERFECT bar at server time t, a triangle 0 -> 1 -> 0 every
--                                        timing.periodSeconds; 0 for a broken time
--   HighwayMath.isPerfect(t)          -> boolean: |barAt(t) - 0.5| <= timing.perfectHalfWidth
--   HighwayMath.arc(from, y0, studs, startAt, minCarry?) -> Types.HighwayArc: an air arc from `from` (y0 high) of a
--                                        throw stopping at `studs`: carry = carryShare x studs in [carryMin,
--                                        carryMax], raised to minCarry, never past studs; air = airSeconds +
--                                        airPerRoot x sqrt(reach / airRoot) (reach = carry - from, at least 0); peak =
--                                        min(peakShare x reach, peakMax)
--   HighwayMath.rollSeconds(carry, studs) -> number: groundSeconds + groundScale x (rest / groundRef)^groundPower,
--                                        0 when nothing is left to roll
--   HighwayMath.newPlan(power, root, releaseAt) -> Core: a new throw from the lane-local root (from = -root.Z, y0 =
--                                        root.Y + releaseUp, x0 = root.X), one arc to landing(power) from releaseAt,
--                                        its roll, landsAt = releaseAt + air + roll
--   HighwayMath.airEnd(core)          -> number: the server time the air ends (the last arc's startAt + air)
--   HighwayMath.planAt(core, t)       -> (Vector3 (x, y, d), boolean): the squishy at server time t and whether it is
--                                        in the air (t in [the release, airEnd)): the release point before the
--                                        release; arc i (in force from its startAt to the next one's) at u = its
--                                        share of the air, d = from + (carry - from) u, y = y0 + (y1 - y0) u + 4
--                                        peak u (1 - u), y1 = CLEAR unless the arc ends on a booster; then the roll
--                                        (P3D:590's ease, P3D:555's hops) to studs, then
--                                        (x, CLEAR, studs); x = clamp(x0, ±MAX_X) eased to 0 over the first
--                                        centreStuds studs (the rings are centred)
--   HighwayMath.boost(core, power, t) -> Core?: the plan after a boost at server time t (fuel is the service's
--                                        check): nil before the release + afterReleaseSeconds, after airEnd -
--                                        beforeCarrySeconds, or with no room ahead; else a new arc from planAt(core,
--                                        t) to core.studs + what boost.power adds to landing(power), at most gatesAt,
--                                        carrying at least minAheadStuds farther, flying speedUp x faster than the arc
--                                        in force (never under minAirSeconds), after the arcs up to the one in force
--                                        (what was still ahead is flown over: run reach again); the roll and landsAt
--                                        again
--   HighwayMath.reach(core, armor, spots, bounced) -> Reached: the course (owner 2026-11-06, Config's course): what
--                                        the plan's last arc reaches. Its touchdown within catchShare x a spot's biome
--                                        length, of the nearest spot ahead of the arc's start, lands exactly on it (the
--                                        arc's carry moves there). A booster, under maxBounces (`bounced` so far on this
--                                        throw + this call's), is touched at its course.touch height (the arc's y1), and
--                                        adds an arc from there to bounceDistance x where the throw
--                                        would stop (at most gatesAt, at least boost.minAheadStuds ahead), flying
--                                        boost.speedUp x faster than the arc before (never under minAirSeconds), and
--                                        looks again from that arc's touchdown: bounces = the spots bounced off. A trap
--                                        stops it on it (trap = true, no roll), as far off its middle as the touchdown
--                                        was in the catch, scaled to trapSpread, unless armor >= the spot's biome: then
--                                        it goes through (pushed = that spot). A booster over the limit does nothing.
--                                        The rooms (owner 2026-11-07): no stop lies inside a spot's room (clearStuds a
--                                        booster, trapClearStuds a trap): a stop in the first half of one stops that
--                                        far short of it when that is clear (and minAheadStuds past the arc's start),
--                                        anything else flies past it by as much, past the next room the same way; the
--                                        touchdown moves past every room before the stop (never in one: a roll never
--                                        runs through a spot). Plans are never changed in place; with no spot near, the
--                                        same flight
--   HighwayMath.ringsHit(core)        -> { number }: the WorldLayout.Highway.rings indices (ascending) the plan flies
--                                        through: the arc in force at the ring's d is within ringRadius of its
--                                        centre (rolling never hits)
--   HighwayMath.bullseye(studs)       -> boolean: the stop within padRadius of a WorldLayout.Highway.pads pad
--   HighwayMath.inArea(point, margin) -> boolean: a lane-local point (WorldLayout.Highway.origin's frame) inside the
--                                        throw area grown by `margin` studs on every side
--   HighwayMath.inThrowArea(position, margin) -> boolean: the same for a world position
--   HighwayMath.foodBag(pen, sv)      -> (FoodDef?, pieces): the Food Bag (SIM:239, V3:185): the band food of the
--                                        weakest placed squishy (the lowest level: PenMath.placed, PenMath.feedCost),
--                                        max(1, floor(foodBag.squeezes x sv / its piece price)) pieces; (nil, 0) when
--                                        nothing is placed or that squishy is past the last band

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GearMath = require(Shared.GearMath)
local PenMath = require(Shared.PenMath)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

-- Types

-- The flight part of Types.HighwayPlan (what the math reads and makes).
export type Core = { x0: number, arcs: { Types.HighwayArc }, roll: number, studs: number, landsAt: number }
-- The course (2026-11-06): one trap or booster on the lane, and a plan after HighwayMath.reach.
export type Spot = { d: number, kind: string }
export type Reached = {
	x0: number,
	arcs: { Types.HighwayArc },
	roll: number,
	studs: number,
	landsAt: number,
	bounces: { number },
	trap: boolean,
	pushed: number?,
}

-- Constants

local H = Config.Economy.Highway
local F = H.flight
local T = H.timing
local B = H.boost
local C = H.course
local TRAP = "trap"
local LAYOUT = WorldLayout.Highway
local AREA = LAYOUT.throwArea
local LANE_Y = 1 -- the lane's top (HighwayBuilder's lane tiles, y 0..1; P3D:136 LANE_Y)
local MAX_X = 12 -- inside the rails (x ±14, a 0.6 tube; the lane top is 26 wide)
local CLEAR = LANE_Y + 1 -- a squishy's centre on the lane (P3D:578 LANE_Y + 1)

-- Module table

local HighwayMath = {}

-- Private

local function isFinite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function biomes(): number
	return #H.starts
end

-- The far end of biome n: the next start, the last one at the Golden Gates.
local function endOf(n: number): number
	return H.starts[n + 1] or H.gatesAt
end

-- The power where biome n + 1 starts (the last one's: the Golden Gates').
local function wallAfter(n: number): number
	return H.walls[n + 1] or H.gatesPower
end

-- The index of the arc in force at server time t (the last one started by then; 1 before the release).
local function arcAt(core: Core, t: number): number
	local index = 1
	while core.arcs[index + 1] ~= nil and t >= core.arcs[index + 1].startAt do
		index += 1
	end
	return index
end

-- The height of arc `a` over distance d (inside its from..carry).
local function heightOn(a: Types.HighwayArc, d: number): number
	local u = (d - a.from) / (a.carry - a.from)
	return a.y0 + ((a.y1 or CLEAR) - a.y0) * u + 4 * a.peak * u * (1 - u)
end

-- Public

function HighwayMath.power(level: any, gear: any?): number
	local lv = if isFinite(level) and level >= 1 then math.floor(level) else 1
	return H.power.base * H.power.perGripLevel ^ (lv - 1) * GearMath.multiplier(gear)
end

function HighwayMath.landing(power: any): number
	if not isFinite(power) and power ~= math.huge then
		return 0
	end
	if power <= H.walls[1] then
		return 0
	end
	if power >= H.gatesPower then
		return H.gatesAt
	end
	local n = 1
	while n < biomes() and power >= H.walls[n + 1] do
		n += 1
	end
	local low, high = H.walls[n], wallAfter(n)
	local start = H.starts[n]
	local studs = start + (endOf(n) - start) * math.log(power / low) / math.log(high / low)
	return math.clamp(math.floor(studs), 0, H.gatesAt)
end

function HighwayMath.biomeAt(studs: any): number
	local n = 1
	if isFinite(studs) then
		for index, start in H.starts do
			if studs >= start then
				n = index
			end
		end
	end
	return n
end

function HighwayMath.reached(studs: any): number
	if isFinite(studs) and studs >= H.gatesAt then
		return biomes() + 1
	end
	return HighwayMath.biomeAt(studs)
end

function HighwayMath.landingCoins(sv: number, studs: any, rings: any?): number
	local d = if isFinite(studs) then math.clamp(studs, 0, H.gatesAt) else 0
	local r = if isFinite(rings) and rings > 0 then math.floor(rings :: number) else 0
	return PenMath.rewardCoins(H.pay.perStud * d * (1 + H.pay.ringShare * r), sv)
end

function HighwayMath.barAt(t: any): number
	if not isFinite(t) then
		return 0
	end
	local phase = (t / T.periodSeconds) % 1
	return 1 - math.abs(2 * phase - 1)
end

function HighwayMath.isPerfect(t: any): boolean
	return isFinite(t) and math.abs(HighwayMath.barAt(t) - 0.5) <= T.perfectHalfWidth
end

function HighwayMath.arc(from: number, y0: number, studs: number, startAt: number, minCarry: number?): Types.HighwayArc
	local carry = math.min(math.clamp(F.carryShare * studs, F.carryMin, F.carryMax), studs)
	if minCarry ~= nil then
		carry = math.min(math.max(carry, minCarry), studs)
	end
	local reach = math.max(carry - from, 0)
	return {
		startAt = startAt,
		from = from,
		y0 = y0,
		carry = carry,
		air = F.airSeconds + F.airPerRoot * math.sqrt(reach / F.airRoot),
		peak = math.min(F.peakShare * reach, F.peakMax),
	}
end

function HighwayMath.rollSeconds(carry: number, studs: number): number
	local rest = studs - carry
	return if rest > 0 then F.groundSeconds + F.groundScale * (rest / F.groundRef) ^ F.groundPower else 0
end

function HighwayMath.newPlan(power: number, root: Vector3, releaseAt: number): Core
	local studs = HighwayMath.landing(power)
	local first = HighwayMath.arc(-root.Z, root.Y + F.releaseUp, studs, releaseAt)
	local roll = HighwayMath.rollSeconds(first.carry, studs)
	return { x0 = root.X, arcs = { first }, roll = roll, studs = studs, landsAt = releaseAt + first.air + roll }
end

function HighwayMath.airEnd(core: Core): number
	local last = core.arcs[#core.arcs]
	return last.startAt + last.air
end

function HighwayMath.planAt(core: Core, t: number): (Vector3, boolean)
	local first = core.arcs[1]
	local function at(y: number, d: number): Vector3
		local x = math.clamp(core.x0, -MAX_X, MAX_X) * math.clamp(1 - (d - first.from) / F.centreStuds, 0, 1)
		return Vector3.new(x, y, d)
	end
	if not isFinite(t) or t < first.startAt then
		return at(first.y0, first.from), false
	end
	local index = arcAt(core, t)
	local a = core.arcs[index]
	if index < #core.arcs or t < a.startAt + a.air then
		local u = math.clamp((t - a.startAt) / a.air, 0, 1)
		local d = a.from + (a.carry - a.from) * u
		return at(a.y0 + ((a.y1 or CLEAR) - a.y0) * u + 4 * a.peak * u * (1 - u), d), true
	end
	local rest = core.studs - a.carry
	if core.roll <= 0 or rest <= 0 then
		return at(CLEAR, core.studs), false
	end
	local v = math.min((t - a.startAt - a.air) / core.roll, 1)
	local d = a.carry + rest * (1 - (1 - v) ^ F.rollPower)
	local hops = math.max(1, math.floor(rest / F.hopEvery + 0.5))
	local length = rest / hops
	local hop = math.min(math.floor((d - a.carry) / length), hops - 1)
	local start = a.carry + hop * length
	local u = math.clamp((d - start) / length, 0, 1)
	local h = F.hopBase + F.hopScale * (1 - start / core.studs)
	return at(CLEAR + 4 * h * u * (1 - u), d), false
end

function HighwayMath.boost(core: Core, power: number, t: number): Core?
	if not isFinite(t) then
		return nil
	end
	if t < core.arcs[1].startAt + B.afterReleaseSeconds or t > HighwayMath.airEnd(core) - B.beforeCarrySeconds then
		return nil
	end
	local here = HighwayMath.planAt(core, t)
	-- The boost's own gain on top of where the plan stops now (a bounce or a trap moved that from landing(power)).
	local studs = math.min(core.studs + HighwayMath.landing(power * B.power) - HighwayMath.landing(power), H.gatesAt)
	local new = HighwayMath.arc(here.Z, here.Y, studs, t, here.Z + B.minAheadStuds)
	local index = arcAt(core, t)
	local current = core.arcs[index]
	local speed = (current.carry - current.from) / current.air
	if new.carry <= here.Z or not (speed > 0) then
		return nil
	end
	new.air = math.max((new.carry - new.from) / (speed * B.speedUp), B.minAirSeconds)
	local arcs = table.move(core.arcs, 1, index, 1, {}) -- the course: what was still ahead is flown over
	table.insert(arcs, new)
	local roll = HighwayMath.rollSeconds(new.carry, studs)
	return { x0 = core.x0, arcs = arcs, roll = roll, studs = studs, landsAt = t + new.air + roll }
end

-- The course: a spot's catch, catchShare x its biome's length.
local function catchOf(d: number): number
	local biome = HighwayMath.biomeAt(d)
	return C.catchShare * (endOf(biome) - H.starts[biome])
end

-- The course: the nearest spot ahead of `from` whose catch holds a touchdown at `carry`.
local function spotAt(spots: { Spot }, carry: number, from: number): Spot?
	local found: Spot? = nil
	local nearest = math.huge
	for _, spot in spots do
		local off = math.abs(spot.d - carry)
		if spot.d > from and off < nearest and off <= catchOf(spot.d) then
			found, nearest = spot, off
		end
	end
	return found
end

-- The course: the room a spot keeps clear along the lane (its model's half-length and a little more).
local function roomOf(spot: Spot): number
	return if spot.kind == TRAP then C.trapClearStuds else C.clearStuds
end

-- The spot whose room holds lane distance d (its edges are clear), with that room.
local function roomAt(spots: { Spot }, d: number): (Spot?, number)
	for _, spot in spots do
		local room = roomOf(spot)
		if math.abs(d - spot.d) < room then
			return spot, room
		end
	end
	return nil, 0
end

-- Where a throw that would stop at `studs` stops (see the API): short of a room it would stop in the first half of,
-- by the room, when that is clear and at least `low`; else past it by as much, and past the next room the same way.
-- Throws near a spot keep their spread instead of all stopping at one distance.
local function freeStop(spots: { Spot }, studs: number, low: number): number
	local spot, room = roomAt(spots, studs)
	if spot ~= nil and studs < spot.d and studs - room >= low and roomAt(spots, studs - room) == nil then
		return studs - room
	end
	for _ = 1, #spots do -- every step leaves a room forwards, so this ends
		if spot == nil then
			break
		end
		studs += if studs < spot.d then 2 * room else room
		spot, room = roomAt(spots, studs)
	end
	return math.min(studs, H.gatesAt)
end

-- The course (see the API).
function HighwayMath.reach(core: Core, armor: number, spots: { Spot }, bounced: number): Reached
	local arcs = table.clone(core.arcs)
	local studs = core.studs
	local bounces: { number } = {}
	local pushed: number? = nil
	local last = arcs[#arcs]
	local spot = spotAt(spots, last.carry, last.from)
	while spot ~= nil do
		local isTrap = spot.kind == TRAP
		if isTrap and armor >= HighwayMath.biomeAt(spot.d) then
			pushed = spot.d
			break
		end
		if not isTrap and bounced + #bounces >= C.maxBounces then
			break
		end
		local aimed = table.clone(last)
		aimed.carry = spot.d
		arcs[#arcs] = aimed
		local touch = aimed.startAt + aimed.air
		if isTrap then
			aimed.carry = math.floor(spot.d + (last.carry - spot.d) / catchOf(spot.d) * C.trapSpread)
			return {
				x0 = core.x0,
				arcs = arcs,
				roll = 0,
				studs = aimed.carry,
				landsAt = touch,
				bounces = bounces,
				trap = true,
				pushed = pushed,
			}
		end
		local height = LANE_Y + C.touch[spot.kind][HighwayMath.biomeAt(spot.d)]
		aimed.y1 = height
		local ahead = spot.d + B.minAheadStuds
		studs = math.min(math.max(math.floor(studs * C.bounceDistance), ahead), H.gatesAt)
		local new = HighwayMath.arc(spot.d, height, studs, touch, ahead)
		local speed = (last.carry - last.from) / last.air
		new.air = math.max((new.carry - new.from) / (speed * B.speedUp), B.minAirSeconds)
		table.insert(arcs, new)
		table.insert(bounces, spot.d)
		last = new
		spot = spotAt(spots, last.carry, last.from)
	end
	-- Where it stops, out of every room, and where it touches down: past every room before the stop (it flies over).
	studs = freeStop(spots, studs, last.from + B.minAheadStuds)
	local carry = math.min(last.carry, studs)
	for _, ahead in spots do
		local edge = ahead.d + roomOf(ahead)
		if edge > carry and edge <= studs then
			carry = edge
		end
	end
	if carry ~= last.carry then
		last = table.clone(last)
		last.carry = carry
		arcs[#arcs] = last
	end
	local roll = HighwayMath.rollSeconds(last.carry, studs)
	return {
		x0 = core.x0,
		arcs = arcs,
		roll = roll,
		studs = studs,
		landsAt = last.startAt + last.air + roll,
		bounces = bounces,
		trap = false,
		pushed = pushed,
	}
end

function HighwayMath.ringsHit(core: Core): { number }
	local hit: { number } = {}
	for index, ring in LAYOUT.rings do
		for i, a in core.arcs do
			local after = core.arcs[i + 1]
			local stop = if after then after.from else a.carry
			if ring.d >= a.from and ring.d < stop then
				if math.abs(heightOn(a, ring.d) - ring.y) <= LAYOUT.ringRadius then
					table.insert(hit, index)
				end
				break
			end
		end
	end
	return hit
end

function HighwayMath.bullseye(studs: any): boolean
	if not isFinite(studs) then
		return false
	end
	for _, pad in LAYOUT.pads do
		if math.abs(studs - pad.d) <= LAYOUT.padRadius then
			return true
		end
	end
	return false
end

function HighwayMath.inArea(point: Vector3, margin: number): boolean
	local half = AREA.size / 2 + Vector3.one * math.max(margin, 0)
	local offset = point - AREA.position
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

function HighwayMath.inThrowArea(position: Vector3, margin: number): boolean
	return HighwayMath.inArea(WorldLayout.Highway.origin:PointToObjectSpace(position), margin)
end

function HighwayMath.foodBag(pen: any, sv: number): (PenMath.FoodDef?, number)
	local weakest: number? = nil
	for _, item in PenMath.placed(pen) do
		if weakest == nil or item.level < weakest then
			weakest = item.level
		end
	end
	local food = if weakest ~= nil then PenMath.feedCost(weakest) else nil
	if food == nil then
		return nil, 0
	end
	return food, math.max(1, math.floor(H.foodBag.squeezes * sv / food.price))
end

return table.freeze(HighwayMath)
