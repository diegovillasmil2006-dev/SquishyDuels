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
--   HighwayMath.power(level)          -> number: the throw power of a Grip level, base x perGripLevel^(level - 1)
--                                        (p13v4: Lv 1 900); a level that is not a whole number >= 1 counts as Lv 1,
--                                        a fraction is cut
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
--                                        share of the air, d = from + (carry - from) u, y = y0 + (CLEAR - y0) u + 4
--                                        peak u (1 - u); then the roll (P3D:590's ease, P3D:555's hops) to studs, then
--                                        (x, CLEAR, studs); x = clamp(x0, ±MAX_X) eased to 0 over the first
--                                        centreStuds studs (the rings are centred)
--   HighwayMath.boost(core, power, t) -> Core?: the plan after a boost at server time t (fuel is the service's
--                                        check): nil before the release + afterReleaseSeconds, after airEnd -
--                                        beforeCarrySeconds, or with no room ahead; else a new arc from planAt(core,
--                                        t) to max(landing(power x boost.power), core.studs), carrying at least
--                                        minAheadStuds farther, flying speedUp x faster than the arc in force (never
--                                        under minAirSeconds); the roll and landsAt again
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
local PenMath = require(Shared.PenMath)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

-- Types

-- The flight part of Types.HighwayPlan (what the math reads and makes).
export type Core = { x0: number, arcs: { Types.HighwayArc }, roll: number, studs: number, landsAt: number }

-- Constants

local H = Config.Economy.Highway
local F = H.flight
local T = H.timing
local B = H.boost
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
	return a.y0 + (CLEAR - a.y0) * u + 4 * a.peak * u * (1 - u)
end

-- Public

function HighwayMath.power(level: any): number
	local lv = if isFinite(level) and level >= 1 then math.floor(level) else 1
	return H.power.base * H.power.perGripLevel ^ (lv - 1)
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
		return at(a.y0 + (CLEAR - a.y0) * u + 4 * a.peak * u * (1 - u), d), true
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
	local studs = math.max(HighwayMath.landing(power * B.power), core.studs)
	local new = HighwayMath.arc(here.Z, here.Y, studs, t, here.Z + B.minAheadStuds)
	local current = core.arcs[arcAt(core, t)]
	local speed = (current.carry - current.from) / current.air
	if new.carry <= here.Z or not (speed > 0) then
		return nil
	end
	new.air = math.max((new.carry - new.from) / (speed * B.speedUp), B.minAirSeconds)
	local arcs = table.clone(core.arcs)
	table.insert(arcs, new)
	local roll = HighwayMath.rollSeconds(new.carry, studs)
	return { x0 = core.x0, arcs = arcs, roll = roll, studs = studs, landsAt = t + new.air + roll }
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
