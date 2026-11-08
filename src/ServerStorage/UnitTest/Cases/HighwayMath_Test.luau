--!strict
-- HighwayMath_Test: unit tests for ReplicatedStorage.Shared.HighwayMath (pens3 phase 13: the throw for distance;
-- work/pens3/PLAN.md "PHASE 13" with the owner's corrections, work/pens3/p13v2/NOTES.md; p13v4: the TikTok throw,
-- work/pens3/p13v4/SPEC.md with its spec/curve.js). Server only (ServerStorage.UnitTest). Pure.
-- Contract (Config.Economy.Highway, restated from the sources: G110 = work/econ4/out5_grip110.txt, J =
-- final_hagb_grip110.json, SIM = sim5.js, P3D = the lobby design v6's "Squishy Lobby 3D.html"):
--   * power(Grip Lv) = 900 x 1.05^(Lv - 1) (owner 2026-10-22; p13v4 [P]: base 900, Lv 1 lands 213 studs); a broken level counts as Lv 1;
--   * landing(power): J's walls, s_n + len_n x ln(P / P_n) / ln(P_n+1 / P_n) (V4:76; SIM:89), whole studs (cut), 0 at
--     power 1 or less, the Golden Gates (8,500) from 2.4e31; curve.js: power 900 -> 213, 14,400 -> 301;
--   * biomeAt(studs) 1..7 (SIM:90: the Golden Gates are in Divine Heaven), reached(studs) 1..8 (8 = the Golden Gates);
--   * landingCoins(sv, studs, rings?) = floor(0.5 x studs x (1 + 0.1 x rings) x sv) (p13v3 by distance; p13v4 +10 % a
--     ring hit), never above maxCoins: one stud farther always pays more, a broken distance nothing;
--   * p13v4 the PERFECT bar: barAt(t) a 0 -> 1 -> 0 triangle every 1.6 s of server time, isPerfect within 0.1 of the
--     middle;
--   * p13v4 the flight plan: arc (carry 0.9 x the landing in [70, 8,500], never past it, raised to minCarry; air 1.1
--     + 2.4 sqrt(reach / 900); peak 0.175 x the reach, at most 60), rollSeconds (0.5 + 2 (rest / 8,000)^0.75), newPlan
--     from a lane-local root (the release 1.5 above it), planAt (the release point before the release, the arcs, the
--     roll, on the lane (y 2) at the carry and the landing, x easing to the centre over 60 studs), boost (x4 power,
--     only from 0.2 s after the release to 0.15 s before the air ends, continuous, faster), ringsHit, bullseye;
--   * the course (owner 2026-11-06): reach lands a touchdown on a spot within catchShare x its biome's length; a booster
--     adds an arc to 2 x the stop (2 a throw, faster, continuous), a trap stops it on it unless the armor reaches the
--     zone; a boost flies over what is ahead;
--   * the course's rooms (owner 2026-11-07, "yes" to fixing the repeating distances): no throw stops inside a spot's
--     room (clearStuds a booster, trapClearStuds a trap): a stop in the first half of one stops that far short of it
--     when that is clear, anything else flies past it by as much (and past the next room the same way); the touchdown
--     is never in a room nor before one the roll would run through; a trap stops it within trapSpread of its middle,
--     as far off as the touchdown was within the catch; no whole-stud distance comes back much more than its
--     neighbours;
--   * inArea(lane-local point, margin): inside WorldLayout.Highway.throwArea (the deck top, L:20 30 x 15), grown by
--     the margin; inThrowArea(world point, margin) the same from a world position;
--   * foodBag(pen, sv): the band food of the weakest placed squishy (the lowest level: its band decides the food),
--     max(1, floor(50 x sv / its piece price)) pieces; nil when nothing is placed or the weakest is past the last
--     band.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local HighwayMath = t.requireShared("HighwayMath")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local H = Config.Economy.Highway
	-- A standing character's root in the middle of the throw area, lane-local (curve.js: y 5.5, d -34.25).
	local ROOT = Vector3.new(0, 5.5, WorldLayout.Highway.throwArea.position.Z)
	local RELEASE = 1_000

	t.test("power: 900 x 1.05^(Grip Lv - 1) (owner 2026-10-22); a broken level is Lv 1", function()
		expect.equal(HighwayMath.power(1), 900)
		expect.near(HighwayMath.power(10), 900 * 1.05 ^ 9, 1e-6)
		expect.near(HighwayMath.power(100), 900 * 1.05 ^ 99, 1e-6)
		for _, bad in { 0, -5, 0 / 0, math.huge, "7" } :: { any } do
			expect.equal(HighwayMath.power(bad), 900)
		end
		expect.equal(HighwayMath.power(3.7), HighwayMath.power(3)) -- whole levels only
	end)

	t.test("landing: J's walls, whole studs (cut), 0 at power 1, the Golden Gates from 2.4e31", function()
		expect.equal(HighwayMath.landing(2), 21) -- 300 x ln 2 / ln 14,000 = 21.8 (G110 T0 G1: 22)
		expect.equal(HighwayMath.landing(900), 213) -- p13v4: Grip Lv 1 (curve.js)
		expect.equal(HighwayMath.landing(14_400), 301) -- Lv 1 PERFECT + boost: just into Bakery Town
		expect.equal(HighwayMath.landing(HighwayMath.power(100)), 403) -- x1.05 a level (632 at x1.1, curve.js table 1)
		expect.equal(HighwayMath.landing(1), 0)
		expect.equal(HighwayMath.landing(0.5), 0)
		for index, wall in H.walls do
			expect.equal(HighwayMath.landing(wall), H.starts[index]) -- each wall is its biome's start
		end
		expect.equal(HighwayMath.landing(H.gatesPower), H.gatesAt)
		expect.equal(HighwayMath.landing(1e40), H.gatesAt)
		expect.equal(HighwayMath.landing(H.gatesPower * 0.999), H.gatesAt - 1) -- just short of the gates
		for _, bad in { 0 / 0, -math.huge, "9" } :: { any } do
			expect.equal(HighwayMath.landing(bad), 0)
		end
		-- Rising with power everywhere.
		local last = -1
		for exponent = 0, 32, 0.25 do
			local studs = HighwayMath.landing(10 ^ exponent)
			expect.truthy(studs >= last)
			last = studs
		end
	end)

	t.test("biomeAt 1..7 and reached 1..8 (the Golden Gates are 8)", function()
		expect.equal(HighwayMath.biomeAt(0), 1)
		expect.equal(HighwayMath.biomeAt(299), 1)
		expect.equal(HighwayMath.biomeAt(300), 2)
		expect.equal(HighwayMath.biomeAt(6000), 7)
		expect.equal(HighwayMath.biomeAt(8500), 7)
		expect.equal(HighwayMath.reached(8499), 7)
		expect.equal(HighwayMath.reached(8500), 8)
		expect.equal(HighwayMath.reached(800), 3)
		expect.equal(HighwayMath.biomeAt(0 / 0), 1)
		expect.equal(HighwayMath.reached(-3), 1)
	end)

	-- P13v3 (owner 2026-10-18: "it should give coins on base of how many meters far they go like hit a golf ball").
	t.test("landingCoins: floor(0.5 x the studs x the squeeze value), farther always more, at most maxCoins", function()
		expect.equal(H.pay.perStud, 0.5)
		expect.equal(HighwayMath.landingCoins(10, 21), 105) -- the least squeeze value
		expect.equal(HighwayMath.landingCoins(10, 328), 1640)
		expect.equal(HighwayMath.landingCoins(40.5, 8500), math.floor(0.5 * 8500 * 40.5)) -- the Golden Gates
		expect.equal(HighwayMath.landingCoins(1e18, 8500), Config.Economy.maxCoins)
		expect.equal(HighwayMath.landingCoins(10, 0), 0)
		for _, bad in { 0 / 0, -5, math.huge, "21" } :: { any } do
			expect.equal(HighwayMath.landingCoins(10, bad), 0) -- a broken distance pays nothing
		end
		expect.equal(HighwayMath.landingCoins(10, 9000), HighwayMath.landingCoins(10, H.gatesAt)) -- held at the gates
		-- Strictly farther = more, at the least squeeze value (perStud x minSqueezeValue >= 1, ValidateHighway).
		local last = -1
		for studs = 0, H.gatesAt do
			local coins = HighwayMath.landingCoins(Config.Economy.Pen.minSqueezeValue, studs)
			if coins <= last then
				error(`{studs} studs pay {coins}, not more than {studs - 1} studs' {last}`)
			end
			last = coins
		end
	end)

	-- P13v4 -----------------------------------------------------------------------------------------------------------

	t.test(
		"p13v4 landingCoins: each ring hit adds 10 % (SPEC: (10, 213, 2) = 1,278); broken ring counts are 0",
		function()
			expect.equal(HighwayMath.landingCoins(10, 213, 2), 1278) -- floor(0.5 x 213 x 1.2 x 10)
			expect.equal(HighwayMath.landingCoins(10, 213, 0), 1065)
			expect.equal(HighwayMath.landingCoins(10, 213), 1065)
			expect.equal(HighwayMath.landingCoins(10, 213, 3), math.floor(0.5 * 213 * 1.3 * 10))
			expect.equal(HighwayMath.landingCoins(10, 213, 2.9), 1278) -- whole rings
			for _, bad in { -2, 0 / 0, math.huge, "2" } :: { any } do
				expect.equal(HighwayMath.landingCoins(10, 213, bad), 1065)
			end
			expect.equal(HighwayMath.landingCoins(10, 0 / 0, 3), 0)
		end
	)

	t.test(
		"p13v4 barAt: a 0 -> 1 -> 0 triangle every 1.6 s of server time; isPerfect within 0.1 of the middle",
		function()
			expect.near(HighwayMath.barAt(0), 0, 1e-9)
			expect.near(HighwayMath.barAt(0.4), 0.5, 1e-9)
			expect.near(HighwayMath.barAt(0.8), 1, 1e-9)
			expect.near(HighwayMath.barAt(1.2), 0.5, 1e-9)
			expect.near(HighwayMath.barAt(1.6), 0, 1e-9)
			expect.near(HighwayMath.barAt(-0.4), 0.5, 1e-9)
			expect.near(HighwayMath.barAt(1_800_000_000.4), 0.5, 1e-5) -- a real server clock
			for _, bad in { 0 / 0, math.huge, "1" } :: { any } do
				expect.equal(HighwayMath.barAt(bad), 0)
				expect.falsy(HighwayMath.isPerfect(bad))
			end
			expect.truthy(HighwayMath.isPerfect(0.4))
			expect.truthy(HighwayMath.isPerfect(1.2))
			expect.truthy(HighwayMath.isPerfect(0.4 + 0.079)) -- bar 0.599 (1.25 a second)
			expect.truthy(HighwayMath.isPerfect(0.4 - 0.079))
			expect.falsy(HighwayMath.isPerfect(0.4 + 0.081)) -- bar 0.601
			expect.falsy(HighwayMath.isPerfect(0.4 - 0.081))
			expect.falsy(HighwayMath.isPerfect(0))
			expect.falsy(HighwayMath.isPerfect(0.8))
			-- 1 time in 5.
			local hits = 0
			for i = 0, 15_999 do
				hits += if HighwayMath.isPerfect(i * 0.0001) then 1 else 0
			end
			expect.near(hits / 16_000, 0.2, 0.001)
		end
	)

	t.test("p13v4 arc: carry 0.9 x the landing in [70, 8,500], never past it; air; peak at most 60", function()
		local a = HighwayMath.arc(-34.25, 7, 213, RELEASE)
		expect.equal(a.startAt, RELEASE)
		expect.equal(a.from, -34.25)
		expect.equal(a.y0, 7)
		expect.near(a.carry, 0.9 * 213, 1e-9)
		expect.near(a.air, 1.1 + 2.4 * math.sqrt((0.9 * 213 + 34.25) / 900), 1e-9)
		expect.near(a.peak, 0.175 * (0.9 * 213 + 34.25), 1e-9)
		expect.near(a.air, 2.30, 0.01) -- curve.js table 1, Lv 1
		local far = HighwayMath.arc(-34.25, 7, 8500, RELEASE)
		expect.equal(far.carry, 7650)
		expect.equal(far.peak, 60)
		expect.equal(HighwayMath.arc(-34.25, 7, 50, RELEASE).carry, 50) -- carryMin 70, but never past the landing
		expect.equal(HighwayMath.arc(-34.25, 7, 75, RELEASE).carry, 70)
		expect.equal(HighwayMath.arc(100, 20, 120, RELEASE, 130).carry, 120) -- raised to minCarry, never past studs
		expect.equal(HighwayMath.arc(100, 20, 400, RELEASE, 380).carry, 380)
		expect.equal(HighwayMath.arc(100, 20, 400, RELEASE, 200).carry, 360) -- minCarry under the carry: unchanged
		expect.equal(HighwayMath.rollSeconds(100, 100), 0)
		expect.near(HighwayMath.rollSeconds(7650, 8500), 0.5 + 2 * (850 / 8000) ^ 0.75, 1e-9)
	end)

	t.test(
		"p13v4 newPlan: from a lane-local root, released 1.5 above it; landsAt = the release + air + roll",
		function()
			local plan = HighwayMath.newPlan(900, ROOT, RELEASE)
			expect.equal(plan.x0, 0)
			expect.equal(plan.studs, 213)
			expect.equal(#plan.arcs, 1)
			local a = plan.arcs[1]
			expect.near(a.from, -34.25, 1e-9)
			expect.near(a.y0, 7, 1e-9)
			expect.equal(a.startAt, RELEASE)
			expect.near(plan.roll, HighwayMath.rollSeconds(a.carry, 213), 1e-12)
			expect.near(plan.landsAt, RELEASE + a.air + plan.roll, 1e-9)
			expect.near(HighwayMath.airEnd(plan), RELEASE + a.air, 1e-9)
			expect.near(0.42 + a.air + plan.roll, 3.25, 0.01) -- curve.js table 1, Lv 1: a 3.25 s flight
			local side = HighwayMath.newPlan(900, ROOT + Vector3.new(8, 0, 0), RELEASE)
			expect.equal(side.x0, 8)
		end
	)

	t.test(
		"p13v4 planAt: the release point, the arc, on the lane at the carry and the stop; x to the centre",
		function()
			local plan = HighwayMath.newPlan(HighwayMath.power(100), ROOT + Vector3.new(8, 0, 0), RELEASE)
			local a = plan.arcs[1]
			local before, flying = HighwayMath.planAt(plan, RELEASE - 0.3)
			expect.falsy(flying)
			expect.truthy((before - Vector3.new(8, 7, -34.25)).Magnitude < 1e-3)
			local start, startFlying = HighwayMath.planAt(plan, RELEASE)
			expect.truthy(startFlying)
			expect.truthy((start - before).Magnitude < 1e-3)
			local top = HighwayMath.planAt(plan, RELEASE + a.air / 2)
			expect.truthy(top.Y > 7 + a.peak * 0.9) -- the arc's top
			expect.near(top.Z, (a.from + a.carry) / 2, 1e-3)
			expect.near(top.X, 0, 1e-9) -- past from + 60: on the lane's centre
			local carry, carryFlying = HighwayMath.planAt(plan, HighwayMath.airEnd(plan))
			expect.falsy(carryFlying) -- rolling
			expect.near(carry.Z, a.carry, 1e-3)
			expect.near(carry.Y, 2, 1e-3) -- the lane's top (1) + 1
			local stop = HighwayMath.planAt(plan, plan.landsAt)
			expect.near(stop.Z, plan.studs, 1e-3)
			expect.near(stop.Y, 2, 1e-3)
			expect.near(HighwayMath.planAt(plan, 1e12).Z, plan.studs, 1e-3) -- stays there
			-- x eases from the release's x to 0 over the first 60 studs.
			local mid = HighwayMath.planAt(plan, RELEASE + a.air * (30 / (a.carry - a.from)))
			expect.near(mid.Z, -34.25 + 30, 1e-3)
			expect.near(mid.X, 8 * 0.5, 1e-3)
			-- Always forward; held inside the rails.
			local last = -math.huge
			for step = 0, 200 do
				local p = HighwayMath.planAt(plan, RELEASE + (plan.landsAt - RELEASE) * step / 200)
				expect.truthy(p.Z >= last - 1e-3)
				last = p.Z
			end
			local wide = HighwayMath.newPlan(900, ROOT + Vector3.new(30, 0, 0), RELEASE)
			expect.near(HighwayMath.planAt(wide, RELEASE).X, 12, 1e-3)
			expect.near(HighwayMath.planAt(plan, 0 / 0).Z, -34.25, 1e-3) -- a broken time: the release point
		end
	)

	t.test("p13v4 boost: x4 power from where it is, only inside its window, continuous and faster", function()
		local perfect = HighwayMath.newPlan(900 * 4, ROOT, RELEASE) -- Lv 1 PERFECT
		expect.equal(perfect.studs, 257) -- curve.js
		local airEnd = HighwayMath.airEnd(perfect)
		expect.equal(HighwayMath.boost(perfect, 3600, RELEASE + 0.19), nil) -- a double tap at the throw
		expect.equal(HighwayMath.boost(perfect, 3600, RELEASE - 0.3), nil) -- before the release
		expect.equal(HighwayMath.boost(perfect, 3600, airEnd - 0.14), nil) -- too close to the carry
		expect.equal(HighwayMath.boost(perfect, 3600, airEnd + 0.5), nil) -- rolling
		expect.equal(HighwayMath.boost(perfect, 3600, 0 / 0), nil)
		expect.truthy(HighwayMath.boost(perfect, 3600, RELEASE + 0.2) ~= nil)
		local at = RELEASE + 1
		local boosted = HighwayMath.boost(perfect, 3600, at)
		assert(boosted ~= nil, "a boost 1 s after the release goes")
		expect.equal(boosted.studs, 301) -- curve.js: Bakery Town on the first throw
		expect.equal(#boosted.arcs, 2)
		expect.equal(boosted.arcs[1], perfect.arcs[1])
		local b = boosted.arcs[2]
		expect.equal(b.startAt, at)
		local here = HighwayMath.planAt(perfect, at)
		local there = HighwayMath.planAt(boosted, at)
		expect.truthy((here - there).Magnitude < 1e-6) -- continuous
		expect.near(b.from, here.Z, 1e-9)
		expect.near(b.y0, here.Y, 1e-9)
		local a = perfect.arcs[1]
		expect.truthy((b.carry - b.from) / b.air > (a.carry - a.from) / a.air) -- faster
		expect.near((b.carry - b.from) / b.air, 1.25 * (a.carry - a.from) / a.air, 1e-9)
		expect.near(boosted.landsAt, at + b.air + boosted.roll, 1e-9)
		expect.near(boosted.landsAt - RELEASE + 0.42, 3.36, 0.01) -- curve.js: a 3.36 s flight
		expect.truthy(perfect.arcs[2] == nil) -- the old plan untouched
		-- Never shorter than the plan it boosts; at least 30 studs ahead.
		local late = HighwayMath.boost(perfect, 3600, airEnd - 0.2)
		assert(late ~= nil, "a late boost goes")
		expect.truthy(late.studs >= perfect.studs)
		expect.truthy(late.arcs[2].carry >= late.arcs[2].from + 30 - 1e-9 or late.arcs[2].carry == late.studs)
		expect.truthy(late.arcs[2].air >= 0.5)
	end)

	-- The course (owner 2026-11-06): a Lv 1 throw (power 900) stops at 213 and first touches down at 191.7; catch 6.3
	-- studs in Candy Meadow (0.021 x 300), 10.5 in Bakery Town (0.021 x 500).
	local function spots(...: any): { any }
		local list = {}
		local args = { ... }
		for index = 1, #args, 2 do
			table.insert(list, { d = args[index], kind = args[index + 1] })
		end
		return list
	end

	t.test("course: no spot near: the same flight, and reach changes no plan in place", function()
		local plain = HighwayMath.newPlan(900, ROOT, RELEASE)
		local carry = plain.arcs[1].carry
		expect.near(carry, 191.7, 1e-6)
		for _, list in { {}, spots(170, "a"), spots(50, "a", 100, "trap") } do -- 170's room ends at 184, before the touchdown
			local r = HighwayMath.reach(plain, 0, list, 0)
			expect.equal(r.studs, 213)
			expect.equal(r.arcs[1].carry, carry)
			expect.near(r.landsAt, plain.landsAt, 1e-9)
			expect.deepEqual(r.bounces, {})
			expect.equal(r.trap, false)
			expect.equal(r.pushed, nil)
		end
		HighwayMath.reach(plain, 0, spots(190, "a"), 0)
		HighwayMath.reach(plain, 0, spots(205, "a"), 0)
		expect.equal(plain.arcs[1].carry, carry)
		expect.equal(#plain.arcs, 1)
	end)

	t.test("course: a booster near the touchdown: lands exactly on it, doubles the stop, faster, continuous", function()
		local plain = HighwayMath.newPlan(900, ROOT, RELEASE)
		local first = plain.arcs[1]
		local r = HighwayMath.reach(plain, 0, spots(190, "a"), 0)
		expect.deepEqual(r.bounces, { 190 })
		expect.equal(r.studs, 426)
		expect.equal(#r.arcs, 2)
		expect.equal(r.arcs[1].carry, 190)
		local second = r.arcs[2]
		expect.equal(second.from, 190)
		expect.near(second.startAt, first.startAt + first.air, 1e-9)
		expect.near(second.carry, 0.9 * 426, 1e-6)
		local speed = (first.carry - first.from) / first.air
		expect.near((second.carry - second.from) / second.air, 1.25 * speed, 1e-9)
		expect.near(r.landsAt, second.startAt + second.air + r.roll, 1e-9)
		local touch = first.startAt + first.air
		expect.truthy((HighwayMath.planAt(r, touch - 1e-6) - HighwayMath.planAt(r, touch + 1e-6)).Magnitude < 0.01)
		expect.near(HighwayMath.planAt(r, touch).Z, 190, 1e-3)
		-- Touched at the booster's own height, not down on the lane: Candy Meadow's "a".
		local height = 1 + H.course.touch.a[1]
		expect.equal(r.arcs[1].y1, height)
		expect.equal(second.y0, height)
		expect.equal(second.y1, nil)
		expect.near(HighwayMath.planAt(r, touch).Y, height, 1e-3)
		expect.equal(first.y1, nil) -- the plan it came from stays as it was
		-- The nearest spot wins; "b" is a booster too.
		expect.deepEqual(HighwayMath.reach(plain, 0, spots(187, "a", 193, "b"), 0).bounces, { 193 })
	end)

	t.test("course: one booster can lead into the next, up to maxBounces; never off the same spot twice", function()
		local plain = HighwayMath.newPlan(900, ROOT, RELEASE)
		-- 426 touches down at 383.4, 852 at 766.8.
		local list = spots(190, "a", 380, "b", 770, "a")
		local r = HighwayMath.reach(plain, 0, list, 0)
		expect.deepEqual(r.bounces, { 190, 380 })
		expect.equal(r.studs, 852)
		expect.equal(#r.arcs, 3)
		-- The third booster is over the limit: nothing happens, and the roll carries past it.
		expect.equal(r.arcs[3].carry, 784)
		expect.deepEqual(HighwayMath.reach(plain, 0, list, H.course.maxBounces - 1).bounces, { 190 })
		expect.deepEqual(HighwayMath.reach(plain, 0, list, H.course.maxBounces).bounces, {})
		expect.equal(HighwayMath.reach(plain, 0, list, H.course.maxBounces).studs, 213)
		-- A far bounce stops at the Golden Gates.
		local far = HighwayMath.newPlan(H.walls[7], ROOT, RELEASE) -- stops at 6,000, touches down at 5,400
		local gates = HighwayMath.reach(far, 0, spots(5400, "a"), 0)
		expect.equal(gates.studs, H.gatesAt)
		expect.near(gates.arcs[2].carry, 0.9 * H.gatesAt, 1e-6)
	end)

	t.test("course: a trap stops the throw on it, unless the armor reaches its zone", function()
		local plain = HighwayMath.newPlan(900, ROOT, RELEASE)
		local first = plain.arcs[1]
		local r = HighwayMath.reach(plain, 0, spots(190, "trap"), 0)
		expect.equal(r.trap, true)
		expect.equal(r.studs, 190)
		expect.equal(r.roll, 0)
		expect.equal(r.arcs[1].carry, 190)
		expect.near(r.landsAt, first.startAt + first.air, 1e-9)
		expect.near(HighwayMath.planAt(r, r.landsAt).Z, 190, 1e-3)
		-- 1 armor piece goes through zone 1's traps: the same flight, with the ARMOR! pop's spot.
		local through = HighwayMath.reach(plain, 1, spots(190, "trap"), 0)
		expect.equal(through.trap, false)
		expect.equal(through.pushed, 190)
		expect.equal(through.studs, 213)
		-- ... but not zone 2's: a bounce into a trap stops there.
		local list = spots(190, "a", 380, "trap")
		local stopped = HighwayMath.reach(plain, 1, list, 0)
		expect.deepEqual(stopped.bounces, { 190 })
		expect.equal(stopped.trap, true)
		expect.equal(stopped.studs, 380)
		expect.equal(HighwayMath.reach(plain, 2, list, 0).trap, false)
	end)

	t.test("course: rooms: never stops in one or rolls through one; short of it, or past it by as much", function()
		-- Lv 1 plain: touches down at 191.7 and would stop at 213; a booster's room is 14, a trap's too (the toy traps,
		-- 2026-11-07; it was 7).
		local plain = HighwayMath.newPlan(900, ROOT, RELEASE)
		local function stops(list: { any }): (number, number)
			local r = HighwayMath.reach(plain, 0, list, 0)
			expect.equal(r.trap, false)
			expect.deepEqual(r.bounces, {})
			expect.near(r.roll, HighwayMath.rollSeconds(r.arcs[1].carry, r.studs), 1e-9)
			return r.studs, r.arcs[1].carry
		end
		local function expectStop(list: { any }, studs: number, carry: number)
			local got, touch = stops(list)
			expect.equal(got, studs)
			expect.near(touch, carry, 1e-9)
		end
		-- A trap's room round the touchdown (7.3 off: just outside the catch) that ends at the stop: touches down at its
		-- edge, the same stop.
		expectStop(spots(199, "trap"), 213, 213)
		-- A touchdown inside a booster's room (6.7 off: just outside the catch): touches down past it instead.
		expectStop(spots(185, "a"), 213, 199)
		-- A stop in the first half of a room stops that far short of it (199, clear) ...
		expectStop(spots(220, "a"), 199, 191.7)
		-- ... in the second half flies past it by as much (213 + 14) ...
		expectStop(spots(205, "a"), 227, 219)
		-- ... and in the first half with the trap's room behind it, past it by its whole room (213 + 28).
		expectStop(spots(199, "trap", 220, "a"), 241, 234)
		-- Past one room into the next: past that one too, the same way (227 is in the first half of 230's: + 28).
		expectStop(spots(205, "a", 230, "trap"), 255, 244)
		-- A room that ends before the stop is clear; one that starts after it does not count.
		expectStop(spots(213 + H.course.clearStuds + 1, "a"), 213, 191.7)
		-- A PERFECT (touches down at 231.3, stops at 257): the touchdown goes past the last room before the stop.
		local perfect = HighwayMath.newPlan(3600, ROOT, RELEASE)
		local two = HighwayMath.reach(perfect, 0, spots(240, "a", 245, "a"), 0)
		expect.equal(two.studs, 271) -- 257 is in the second half of 245's room
		expect.equal(two.arcs[1].carry, 259)
		local one = HighwayMath.reach(perfect, 0, spots(240, "a"), 0)
		expect.equal(one.studs, 257)
		expect.equal(one.arcs[1].carry, 254)
	end)

	t.test("course: a trap stops it within trapSpread of its middle, as far off as the touchdown was in the catch", function()
		-- Lv 1 plain touches down at 191.7; the catch is 6.3 in Candy Meadow, the spread 2.5: 191.7 - 196 = -4.3 -> -1.7.
		local plain = HighwayMath.newPlan(900, ROOT, RELEASE)
		for _, case in { { 196, 194 }, { 187, 188 }, { 190, 190 } } do
			local r = HighwayMath.reach(plain, 0, spots(case[1], "trap"), 0)
			expect.equal(r.trap, true)
			expect.equal(r.studs, case[2])
			expect.equal(r.arcs[1].carry, case[2])
			expect.equal(r.roll, 0)
			expect.truthy(math.abs(r.studs - case[1]) <= H.course.trapSpread + 1)
		end
	end)

	t.test("course: from every stop on the lane, never in a room, never rolling through one, no distance coming back", function()
		local C = H.course
		local function roomOf(spot: any): number
			return if spot.kind == "trap" then C.trapClearStuds else C.clearStuds
		end
		local hits: { [number]: number } = {}
		local problem: string? = nil
		for natural = 100, H.gatesAt - 1 do
			local first = HighwayMath.arc(-ROOT.Z, ROOT.Y, natural, RELEASE)
			local core = {
				x0 = 0,
				arcs = { first },
				roll = HighwayMath.rollSeconds(first.carry, natural),
				studs = natural,
				landsAt = RELEASE + first.air,
			}
			for _, armor in { 0, #H.starts } do
				local r = HighwayMath.reach(core, armor, C.spots, 0)
				local touch = r.arcs[#r.arcs].carry
				if r.trap then
					local near = math.huge
					for _, spot in C.spots do
						if spot.kind == "trap" then
							near = math.min(near, math.abs(r.studs - spot.d))
						end
					end
					if near > C.trapSpread + 1 or touch ~= r.studs or r.roll ~= 0 then
						problem = problem or `{natural}: trapped at {r.studs}, {near} from a trap`
					end
				else
					if touch > r.studs then
						problem = problem or `{natural}: touches down at {touch}, past the stop {r.studs}`
					end
					for _, spot in C.spots do
						local room = roomOf(spot)
						local clear = r.studs >= H.gatesAt or math.abs(r.studs - spot.d) >= room
						local over = spot.d + room <= touch or spot.d - room >= r.studs
						if not (clear and over) then
							problem = problem or `{natural}: rolls {touch} -> {r.studs} against the {spot.kind} at {spot.d}`
						end
					end
					if armor == 0 and r.studs < H.gatesAt then
						hits[r.studs] = (hits[r.studs] or 0) + 1
					end
				end
			end
		end
		expect.equal(problem, nil)
		-- No whole-stud stop comes from more than 6 of the 8,400 whole-stud throws (it was 28 and more: every throw that
		-- would roll into a spot stopped exactly clearStuds past it).
		local most, at = 0, 0
		for studs, n in hits do
			if n > most then
				most, at = n, studs
			end
		end
		expect.equal(if most <= 6 then nil else `{most} throws stop at {at}`, nil)
	end)

	t.test("course: a boost flies over what is ahead, adds its own gain, and escapes a trap", function()
		local plain = HighwayMath.newPlan(900, ROOT, RELEASE)
		local gain = HighwayMath.landing(3600) - HighwayMath.landing(900)
		local bounced = HighwayMath.reach(plain, 0, spots(190, "a"), 0)
		local boosted = HighwayMath.boost(bounced, 900, RELEASE + 0.5)
		assert(boosted ~= nil, "a boost before the bounce goes")
		expect.equal(#boosted.arcs, 2)
		expect.truthy(boosted.arcs[2] ~= bounced.arcs[2])
		expect.near(boosted.arcs[2].startAt, RELEASE + 0.5, 1e-9)
		expect.equal(boosted.studs, 426 + gain)
		local trapped = HighwayMath.reach(plain, 0, spots(190, "trap"), 0)
		local away = HighwayMath.boost(trapped, 900, RELEASE + 0.5)
		assert(away ~= nil, "a boost before the trap goes")
		expect.equal(away.studs, 190 + gain)
		-- Never past the Golden Gates.
		local high = HighwayMath.reach(HighwayMath.newPlan(H.walls[7], ROOT, RELEASE), 0, spots(5400, "a"), 0)
		local capped = HighwayMath.boost(high, H.walls[7], RELEASE + 0.5)
		assert(capped ~= nil, "a boost before the bounce goes")
		expect.equal(capped.studs, H.gatesAt)
	end)

	t.test("course: Config's spots rise in every biome, hold both boosters and a trap, and keep off the pads", function()
		local kinds: { { [string]: boolean } } = {}
		for index, spot in H.course.spots do
			local before = H.course.spots[index - 1]
			expect.truthy(before == nil or spot.d > before.d)
			local biome = HighwayMath.biomeAt(spot.d)
			kinds[biome] = kinds[biome] or {}
			kinds[biome][spot.kind] = true
			local room = if spot.kind == "trap" then H.course.trapClearStuds else H.course.clearStuds
			for _, pad in WorldLayout.Highway.pads do
				expect.truthy(math.abs(spot.d - pad.d) >= WorldLayout.Highway.padRadius + room)
			end
		end
		for biome = 1, #H.starts do
			expect.deepEqual(kinds[biome], { a = true, b = true, trap = true })
		end
	end)

	t.test("course: a booster stands clear of every ring low enough to touch it (the tallest is 31 studs)", function()
		local tallest = 31
		for _, spot in H.course.spots do
			if spot.kind ~= "trap" then
				for _, ring in WorldLayout.Highway.rings do
					if ring.y - WorldLayout.Highway.ringRadius < tallest then
						expect.truthy(math.abs(spot.d - ring.d) >= WorldLayout.Highway.ringRadius + H.course.clearStuds)
					end
				end
			end
		end
	end)

	t.test("p13v4 ringsHit: Lv 1 plain none, PERFECT ring 1, PERFECT + a boost at +1 s rings 1-3", function()
		local plain = HighwayMath.newPlan(900, ROOT, RELEASE)
		local perfect = HighwayMath.newPlan(3600, ROOT, RELEASE)
		expect.deepEqual(HighwayMath.ringsHit(plain), {})
		expect.deepEqual(HighwayMath.ringsHit(perfect), { 1 })
		local boosted = HighwayMath.boost(perfect, 3600, RELEASE + 1)
		expect.deepEqual(HighwayMath.ringsHit(boosted), { 1, 2, 3 })
		-- Rolling never hits: a plan whose air ends before the first ring.
		local short = HighwayMath.newPlan(2, ROOT, RELEASE) -- 21 studs
		expect.deepEqual(HighwayMath.ringsHit(short), {})
	end)

	t.test("p13v4 bullseye: a stop within 15 studs of a pad (135, 255, ...)", function()
		expect.truthy(HighwayMath.bullseye(135))
		expect.truthy(HighwayMath.bullseye(120))
		expect.truthy(HighwayMath.bullseye(8140))
		expect.falsy(HighwayMath.bullseye(151))
		expect.falsy(HighwayMath.bullseye(213))
		expect.falsy(HighwayMath.bullseye(0 / 0))
	end)

	t.test("inArea: the deck top's 30 x 15 (L:20), grown by the margin; inThrowArea from a world point", function()
		local area = WorldLayout.Highway.throwArea
		local c = area.position
		expect.truthy(HighwayMath.inArea(c, 0))
		expect.truthy(HighwayMath.inArea(c + Vector3.new(14.9, 0, 7.4), 0))
		expect.falsy(HighwayMath.inArea(c + Vector3.new(15.5, 0, 0), 0))
		expect.truthy(HighwayMath.inArea(c + Vector3.new(15.5, 0, 0), 1))
		expect.falsy(HighwayMath.inArea(c + Vector3.new(0, 0, 9), 1))
		expect.falsy(HighwayMath.inArea(Vector3.new(0, 2, 10), 1)) -- the gap between the deck and the start line
		expect.falsy(HighwayMath.inArea(c + Vector3.new(0, area.size.Y, 0), 0)) -- far above
		local origin: CFrame = WorldLayout.Highway.origin
		expect.truthy(HighwayMath.inThrowArea((origin * CFrame.new(c)).Position, 0))
		expect.falsy(HighwayMath.inThrowArea(origin.Position, 0)) -- the start line
		expect.falsy(HighwayMath.inThrowArea(Vector3.zero, 1)) -- the island
	end)

	t.test("foodBag: 50 squeezes of the weakest placed squishy's band food, at least 1 piece", function()
		local function item(id: number, kind: string, level: number, slot: number): any
			return { id = id, kind = kind, form = 0, level = level, coat = 0, slot = slot, locked = false }
		end
		local function pen(items: { any }): any
			return { spots = 3, nextId = 9, items = items, awayRate = 0, shelfRows = 1, top = false }
		end
		local food, pieces = HighwayMath.foodBag(pen({ item(1, "kitty_bread", 1, 1) }), 10)
		expect.equal((food :: any).id, "candy_drop")
		expect.equal(pieces, 1) -- floor(500 / 400)
		food, pieces = HighwayMath.foodBag(pen({ item(1, "kitty_bread", 1, 1) }), 1000)
		expect.equal(pieces, 125)
		food, pieces = HighwayMath.foodBag(pen({ item(1, "kitty_bread", 15, 1), item(2, "toast", 12, 2) }), 2_000_000)
		expect.equal((food :: any).id, "butter_bun") -- the weakest is Lv 12 (band 10-20)
		expect.equal(pieces, math.floor(50 * 2_000_000 / 6_400))
		food, pieces = HighwayMath.foodBag(pen({ item(1, "kitty_bread", 3, 0) }), 10) -- only a Toy Box squishy
		expect.equal(food, nil)
		expect.equal(pieces, 0)
		food = HighwayMath.foodBag(pen({ item(1, "kitty_bread", 70, 1) }), 10) -- past the last band
		expect.equal(food, nil)
		expect.equal(HighwayMath.foodBag(nil, 10), nil)
	end)
end
