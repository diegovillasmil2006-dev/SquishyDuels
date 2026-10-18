--!strict
-- HighwayMath: pure throw arithmetic (pens3 phase 13, 2026-10-18; work/pens3/PLAN.md "PHASE 13" with the owner's
-- corrections, work/pens3/p13v2/NOTES.md). Shared: the server decides every throw with it (HighwayService) and the
-- client draws the same flight (HighwayThrowController). Every number is Config.Economy.Highway's (Config/Highway: its
-- sources), the throw area WorldLayout.Highway.throwArea. No instances, no yields, no side effects.
--
-- API:
--   HighwayMath.power(level)          -> number: the throw power of a Grip level, base x perGripLevel^(level - 1)
--                                        (G110:42: Lv 1 2, Lv 100 25K); a level that is not a whole number >= 1
--                                        counts as Lv 1, a fraction is cut
--   HighwayMath.landing(power)        -> number: whole studs from the start line (cut), in [0, gatesAt]: biome n
--                                        (walls[n] <= P < walls[n + 1], walls[8] = gatesPower) at starts[n] +
--                                        length_n x ln(P / walls[n]) / ln(walls[n + 1] / walls[n]) (V4:76, SIM:89);
--                                        0 at walls[1] or less (and for anything that is not a number), gatesAt from
--                                        gatesPower
--   HighwayMath.biomeAt(studs)        -> 1..#starts: the biome a landing lies in (SIM:90; the Golden Gates are in the
--                                        last one); a broken distance is biome 1
--   HighwayMath.reached(studs)        -> 1..#starts + 1: what a landing reaches (#starts + 1 = the Golden Gates), the
--                                        saved profile.highway.biome
--   HighwayMath.landingCoins(sv, b)   -> number: PenMath.rewardCoins(pay.coins x pay.biomeGain^(b - 1), sv) (SIM:239);
--                                        a biome that is not 1..#starts pays biome 1's
--   HighwayMath.flight(studs)         -> Flight {from, carry, air, peak, roll, total, landing}: the design's throw
--                                        (P3D:554, :575), from the throw area's middle (from = its distance, behind
--                                        the start line): carry = carryShare x the landing in [carryMin, carryMax],
--                                        never past the landing; air = airSeconds + airPerRoot x sqrt((carry - from)
--                                        / airRoot) seconds; peak = peakShare x (carry - from) studs; roll =
--                                        groundSeconds + groundScale x (rest / groundRef)^groundPower seconds, 0 when
--                                        nothing is left to roll; total = releaseSeconds + air + roll (how long the
--                                        server keeps the throw in flight)
--   HighwayMath.at(plan, t, x0, y0)   -> Vector3 (x, y, d): the squishy t seconds after the release, lane-local x and
--                                        y and d studs from the start line (WorldLayout.highwayCFrame(x, y, d) is the
--                                        world frame): an arc from (x0, y0, from) to the carry over `air` (P3D:577-
--                                        579), then a roll to the landing over `roll` (P3D:590, eased) hopping every
--                                        hopEvery studs (P3D:555); on the lane (LANE_Y + 1) at the carry and the
--                                        landing; x stays x0, held inside the rails (±MAX_X)
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
local WorldLayout = require(Shared.World.WorldLayout)

-- Types

export type Flight = {
	from: number, -- the release's distance (studs from the start line; negative: on the deck behind it)
	carry: number, -- where the air ends and the roll starts (studs)
	air: number, -- seconds in the air
	peak: number, -- how high the arc rises (studs)
	roll: number, -- seconds rolling (0: it lands at the carry)
	total: number, -- the release delay + air + roll: the server's time in flight
	landing: number, -- where it stops (studs)
}

-- Constants

local H = Config.Economy.Highway
local F = H.flight
local AREA = WorldLayout.Highway.throwArea
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

function HighwayMath.landingCoins(sv: number, biome: any): number
	local b = if isFinite(biome) and biome >= 1 and biome <= biomes() then math.floor(biome) else 1
	return PenMath.rewardCoins(H.pay.coins * H.pay.biomeGain ^ (b - 1), sv)
end

function HighwayMath.flight(studs: number): Flight
	local landing = if isFinite(studs) then math.clamp(studs, 0, H.gatesAt) else 0
	local from = -AREA.position.Z
	local carry = math.min(math.clamp(F.carryShare * landing, F.carryMin, F.carryMax), landing)
	local reach = math.max(carry - from, 0)
	local air = F.airSeconds + F.airPerRoot * math.sqrt(reach / F.airRoot)
	local rest = landing - carry
	local roll = if rest > 0 then F.groundSeconds + F.groundScale * (rest / F.groundRef) ^ F.groundPower else 0
	return {
		from = from,
		carry = carry,
		air = air,
		peak = F.peakShare * reach,
		roll = roll,
		total = F.releaseSeconds + air + roll,
		landing = landing,
	}
end

function HighwayMath.at(plan: Flight, t: number, x0: number, y0: number): Vector3
	local x = math.clamp(x0, -MAX_X, MAX_X)
	local time = if isFinite(t) then math.max(t, 0) else 0
	if time < plan.air then
		local u = time / plan.air
		local d = plan.from + (plan.carry - plan.from) * u
		local y = y0 + (CLEAR - y0) * u + 4 * plan.peak * u * (1 - u)
		return Vector3.new(x, y, d)
	end
	local rest = plan.landing - plan.carry
	if plan.roll <= 0 or rest <= 0 then
		return Vector3.new(x, CLEAR, plan.landing)
	end
	local v = math.min((time - plan.air) / plan.roll, 1)
	local d = plan.carry + rest * (1 - (1 - v) ^ F.rollPower)
	local hops = math.max(1, math.floor(rest / F.hopEvery + 0.5))
	local length = rest / hops
	local index = math.min(math.floor((d - plan.carry) / length), hops - 1)
	local a = plan.carry + index * length
	local u = math.clamp((d - a) / length, 0, 1)
	local h = F.hopBase + F.hopScale * (1 - a / plan.landing)
	return Vector3.new(x, CLEAR + 4 * h * u * (1 - u), d)
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
