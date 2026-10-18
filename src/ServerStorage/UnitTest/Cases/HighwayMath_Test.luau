--!strict
-- HighwayMath_Test: unit tests for ReplicatedStorage.Shared.HighwayMath (pens3 phase 13: the throw for distance;
-- work/pens3/PLAN.md "PHASE 13" with the owner's corrections, work/pens3/p13v2/NOTES.md). Server only
-- (ServerStorage.UnitTest). Pure.
-- Contract (Config.Economy.Highway, restated from the sources: G110 = work/econ4/out5_grip110.txt, J =
-- final_hagb_grip110.json, SIM = sim5.js, P3D = the lobby design v6's "Squishy Lobby 3D.html"):
--   * power(Grip Lv) = 2 x 1.1^(Lv - 1) (G110:42: Lv 1 2, Lv 10 4.7, Lv 100 25K); a broken level counts as Lv 1;
--   * landing(power): J's walls, s_n + len_n x ln(P / P_n) / ln(P_n+1 / P_n) (V4:76; SIM:89), whole studs (cut), 0 at
--     power 1 or less, the Golden Gates (8,500) from 2.4e31; G110's typical throws: Lv 1 (power 2) 21.8, Lv 100 (25K)
--     328.9;
--   * biomeAt(studs) 1..7 (SIM:90: the Golden Gates are in Divine Heaven), reached(studs) 1..8 (8 = the Golden Gates);
--   * landingCoins(sv, studs) = floor(0.5 x studs x sv) (p13v3, owner 2026-10-18: Coins by distance, like Hit a Golf
--     Ball), never above maxCoins: one stud farther always pays more, a broken distance nothing;
--   * flight(studs): P3D's throw from the throw area's middle (P3D:554, :575): the release (0.42 s), the carry
--     (0.32 x the landing in [70, 1,100], never past it), the air 1.1 + 2.4 sqrt(carry from the release / 900) s,
--     the roll 1.6 + 15 (rest / 8,000)^0.75 s (none when nothing is left to roll);
--   * at(plan, t, x0, y0): the squishy's lane-local (x, y, d) t seconds after the release: from the release point to
--     the carry over the air time (an arc), then rolling to the landing (P3D:590's ease), on the lane (y 2) at the
--     carry and the landing; x stays the release's x (inside the rails);
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

	t.test("power: 2 x 1.1^(Grip Lv - 1) (G110:42); a broken level is Lv 1", function()
		expect.equal(HighwayMath.power(1), 2)
		expect.near(HighwayMath.power(10), 4.7159, 1e-3)
		expect.near(HighwayMath.power(100), 25_055.66, 0.01) -- G110: "Lv100 25K"
		for _, bad in { 0, -5, 0 / 0, math.huge, "7" } :: { any } do
			expect.equal(HighwayMath.power(bad), 2)
		end
		expect.equal(HighwayMath.power(3.7), HighwayMath.power(3)) -- whole levels only
	end)

	t.test("landing: J's walls, whole studs (cut), 0 at power 1, the Golden Gates from 2.4e31", function()
		expect.equal(HighwayMath.landing(2), 21) -- 300 x ln 2 / ln 14,000 = 21.8 (G110 T0 G1: 22)
		-- 300 + 500 x ln(25,056 / 14,000) / ln(330M / 14,000) = 328.9
		expect.equal(HighwayMath.landing(HighwayMath.power(100)), 328)
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
		expect.equal(HighwayMath.landingCoins(10, 21), 105) -- Grip Lv 1's throw at the least squeeze value
		expect.equal(HighwayMath.landingCoins(10, 328), 1640) -- Grip Lv 100's
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

	t.test("flight: P3D's carry, air and roll from the throw area's middle (P3D:554, :575)", function()
		local d0 = -WorldLayout.Highway.throwArea.position.Z -- the release's distance: behind the start line
		local short = HighwayMath.flight(21)
		expect.equal(short.carry, 21) -- 0.32 x 21 is under 70, and never past the landing
		expect.equal(short.from, d0)
		expect.near(short.air, 1.1 + 2.4 * math.sqrt((21 - d0) / 900), 1e-9)
		expect.near(short.peak, 0.175 * (21 - d0), 1e-9)
		expect.equal(short.roll, 0)
		expect.near(short.total, 0.42 + short.air, 1e-9)
		local mid = HighwayMath.flight(1000)
		expect.equal(mid.carry, 320)
		expect.near(mid.roll, 1.6 + 15 * (680 / 8000) ^ 0.75, 1e-9)
		local far = HighwayMath.flight(8500)
		expect.equal(far.carry, 1100)
		expect.near(
			far.total,
			0.42 + (1.1 + 2.4 * math.sqrt((1100 - d0) / 900)) + (1.6 + 15 * (7400 / 8000) ^ 0.75),
			1e-9
		)
		expect.truthy(far.total < 21) -- the longest throw is about 20 s
		local zero = HighwayMath.flight(0)
		expect.equal(zero.carry, 0)
		expect.truthy(zero.total > 0.42)
	end)

	t.test("at: an arc from the release to the carry, then a roll to the landing; on the lane at both", function()
		local plan = HighwayMath.flight(1000)
		local x0, y0 = 4, 6
		local start = HighwayMath.at(plan, 0, x0, y0)
		expect.near(start.X, x0, 1e-9)
		expect.near(start.Y, y0, 1e-9)
		expect.near(start.Z, plan.from, 1e-9)
		local top = HighwayMath.at(plan, plan.air / 2, x0, y0)
		expect.truthy(top.Y > y0 + plan.peak * 0.9) -- the arc's top
		local carry = HighwayMath.at(plan, plan.air, x0, y0)
		expect.near(carry.Z, plan.carry, 1e-6)
		expect.near(carry.Y, 2, 1e-6) -- the lane's top (1) + 1
		local landed = HighwayMath.at(plan, plan.air + plan.roll, x0, y0)
		expect.near(landed.Z, 1000, 1e-6)
		expect.near(landed.Y, 2, 1e-6)
		expect.near(HighwayMath.at(plan, 1e9, x0, y0).Z, 1000, 1e-6) -- stays there
		-- Always forward, and the x stays inside the rails (±14).
		local last = -math.huge
		for step = 0, 100 do
			local p = HighwayMath.at(plan, (plan.air + plan.roll) * step / 100, x0, y0)
			expect.truthy(p.Z >= last - 1e-9)
			last = p.Z
		end
		expect.near(HighwayMath.at(plan, 1, 30, y0).X, 12, 1e-9)
		expect.near(HighwayMath.at(plan, 1, -30, y0).X, -12, 1e-9)
		-- A short throw has no roll: it lands at the carry.
		local short = HighwayMath.flight(21)
		expect.near(HighwayMath.at(short, short.air, 0, y0).Z, 21, 1e-6)
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
