--!strict
-- ValidateHighway_Test: unit tests for ReplicatedStorage.Shared.Config.ValidateHighway (the highway's distances, pens3
-- phase 12). Server only (ServerStorage.UnitTest). Pure: broken copies of Config.Economy.Highway.
-- Contract (Config/ValidateHighway header; work/pens3/PLAN.md "PHASE 12"; PR3:36): the shipped Config is valid and
-- holds the 7 biome starts 0 / 300 / 800 / 1,500 / 2,500 / 4,000 / 6,000 with the Golden Gates at 8,500 (so the
-- biomes are 300 / 500 / 700 / 1,000 / 1,500 / 2,000 / 2,500 long); a missing section is one problem; each broken
-- value is reported by name.
-- Pens3 phase 13 (the throw; PLAN "PHASE 13" with the owner's corrections, work/pens3/p13v2/NOTES.md): the shipped
-- walls are J's band (work/econ4/final_hagb_grip110.json: 1 / 14K / 330M / 16T / 1.2Qi / 62Sx / 1.6Oc, the Golden
-- Gates at 2.4e31), the power 2 x 1.1^(Grip Lv - 1) (G110:42, x1.1 fixed by the owner), the pay (p13v3, owner
-- 2026-10-18: Coins by distance) 0.5 squeezes of Coins a stud and 60 of Grip a landing (SIM:59), with one stud
-- farther always paying at least one Coin more (perStud x Pen.minSqueezeValue >= 1, checked when the copy has the Pen
-- section), the Food Bag 50 squeezes every 150 s (SIM:59), the gifts 3 Boba Bears
-- at Boba Lagoon, a Bird at Lava Volcano and 3 Cloud Bunnies at Divine Heaven (SIM:205), the flight P3D's
-- (P3D:554, :575, :590; the Release marker K:5295, 0.42 s); a gift kind the catalog does not know, and every broken new
-- value, are reported by name.
-- P13v4 (owner 2026-10-19: the TikTok throw; work/pens3/p13v4/SPEC.md 5.3, all [P]): power.base 900, the flight almost
-- all air (carryShare 0.9 up to 8,500, peakMax 60, a short roll, releaseUp 1.5, centreStuds 60), the PERFECT bar
-- (timing), the boost (boost) and pay.ringShare 0.1; each broken new value is reported by name, 0 allowed where it
-- means none.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local validate = t.requireShared("Config/ValidateHighway")

	-- A Config-shaped copy with Economy.Highway changed.
	local function broken(changes: { [string]: any }): any
		local highway = table.clone(Config.Economy.Highway)
		for key, value in changes do
			highway[key] = value
		end
		return { Economy = { Highway = highway } }
	end

	local function mentions(problems: { string }, text: string): boolean
		for _, problem in problems do
			if string.find(problem, text, 1, true) then
				return true
			end
		end
		return false
	end

	t.test("the shipped Config is valid: 7 biomes from 0 to 6,000, the Golden Gates at 8,500 (PR3:36)", function()
		expect.deepEqual(validate(Config), {})
		local highway = Config.Economy.Highway
		expect.deepEqual(highway.starts, { 0, 300, 800, 1500, 2500, 4000, 6000 })
		expect.equal(highway.gatesAt, 8500)
		local lengths: { number } = {}
		for index, start in highway.starts do
			table.insert(lengths, (highway.starts[index + 1] or highway.gatesAt) - start)
		end
		expect.deepEqual(lengths, { 300, 500, 700, 1000, 1500, 2000, 2500 }) -- PLAN phase 13 (V4:76)
	end)

	t.test("a missing section is one problem", function()
		local problems = validate({ Economy = {} })
		expect.equal(#problems, 1)
		expect.truthy(mentions(problems, "Config.Economy.Highway is missing"))
		expect.equal(#validate(nil), 1)
	end)

	t.test("each broken value is reported by name", function()
		local cases: { { changes: { [string]: any }, field: string } } = {
			{ changes = { starts = {} }, field = "starts" },
			{ changes = { starts = "0" }, field = "starts" },
			{ changes = { starts = { 50, 300 } }, field = "starts[1]" }, -- the first biome starts at the gate
			{ changes = { starts = { 0, 300, 300 } }, field = "starts[3]" }, -- an empty biome
			{ changes = { starts = { 0, 800, 300 } }, field = "starts[3]" }, -- not rising
			{ changes = { starts = { 0, 300.5 } }, field = "starts[2]" },
			{ changes = { starts = { 0, 0 / 0 } }, field = "starts[2]" },
			{ changes = { gatesAt = 6000 }, field = "gatesAt" }, -- the last biome would be empty
			{ changes = { gatesAt = 8500.5 }, field = "gatesAt" },
			{ changes = { gatesAt = "8500" }, field = "gatesAt" },
			{ changes = { gatesAt = math.huge }, field = "gatesAt" },
		}
		for _, case in cases do
			local problems = validate(broken(case.changes))
			if not mentions(problems, case.field) then
				error(`expected a problem naming {case.field}, got: {table.concat(problems, "; ")}`)
			end
		end
	end)

	-- Pens3 phase 13 -----------------------------------------------------------------------------------------------

	t.test("pens3 phase 13: the shipped throw numbers are J's, G110's, SIM's and P3D's", function()
		local h = Config.Economy.Highway
		expect.deepEqual(h.walls, { 1, 14_000, 330_000_000, 16e12, 1.2e18, 6.2e22, 1.6e27 })
		expect.equal(h.gatesPower, 2.4e31)
		expect.deepEqual(h.power, { base = 900, perGripLevel = 1.1 }) -- p13v4 [P]: Lv 1 lands 213 studs
		-- p13v3: Coins by distance (owner 2026-10-18); p13v4 [P]: +10 % a ring hit
		expect.deepEqual(h.pay, { perStud = 0.5, grip = 60, ringShare = 0.1 })
		expect.deepEqual(h.foodBag, { seconds = 150, squeezes = 50 })
		expect.deepEqual(h.gifts, {
			{ biome = 3, kind = "boba_bear", count = 3 },
			{ biome = 5, kind = "bird", count = 1 },
			{ biome = 7, kind = "cloud_bunny", count = 3 },
		})
		local f = h.flight
		expect.equal(f.releaseSeconds, 0.42)
		-- p13v4 [P]: the video flies almost all the way (carry 0.9, to the gates, arcs at most 60 high, a short roll)
		expect.deepEqual({ f.carryShare, f.carryMin, f.carryMax, f.peakMax }, { 0.9, 70, 8500, 60 })
		expect.deepEqual({ f.airSeconds, f.airPerRoot, f.airRoot, f.peakShare }, { 1.1, 2.4, 900, 0.175 })
		expect.deepEqual({ f.groundSeconds, f.groundScale, f.groundRef, f.groundPower }, { 0.5, 2, 8000, 0.75 })
		expect.deepEqual({ f.rollPower, f.hopEvery, f.hopBase, f.hopScale }, { 1.8, 75, 0.8, 3.5 })
		expect.deepEqual({ f.releaseUp, f.centreStuds }, { 1.5, 60 })
		-- p13v4 [P]: the PERFECT bar and the boost.
		expect.deepEqual(
			h.timing,
			{ periodSeconds = 1.6, perfectHalfWidth = 0.1, perfectPower = 4, maxOneWaySeconds = 0.25 }
		)
		expect.deepEqual(h.boost, {
			fuel = 1,
			power = 4,
			afterReleaseSeconds = 0.2,
			beforeCarrySeconds = 0.15,
			minAheadStuds = 30,
			speedUp = 1.25,
			minAirSeconds = 0.5,
		})
		-- [P] The throw presses' own cap and ceiling (Config/Highway's autoClick).
		expect.equal(h.autoClick.clientPressesPerSecond, 12)
		expect.equal(h.autoClick.maxPerSecond, 11) -- 10 a second (the usual auto-clicker default) is slower: judged
		expect.equal(h.autoClick.floodPresses, 30)
		local Catalog = t.requireShared("Catalog")
		expect.deepEqual(validate(Config, Catalog), {})
	end)

	t.test("pens3 phase 13: each broken throw value is reported by name", function()
		local cases: { { changes: { [string]: any }, field: string } } = {
			{ changes = { walls = { 1, 14_000 } }, field = "walls" }, -- one a biome
			{ changes = { walls = { 0, 2, 3, 4, 5, 6, 7 } }, field = "walls[1]" },
			{ changes = { walls = { 1, 2, 3, 3, 5, 6, 7 } }, field = "walls[4]" }, -- not rising
			{ changes = { walls = { 1, 2, 3, 4, 5, 6, math.huge } }, field = "walls[7]" },
			{ changes = { gatesPower = 1e20 }, field = "gatesPower" }, -- under the last wall
			{ changes = { power = { base = 0, perGripLevel = 1.1 } }, field = "power.base" },
			{ changes = { power = { base = 2, perGripLevel = 0.9 } }, field = "power.perGripLevel" },
			{ changes = { pay = { perStud = -1, grip = 60 } }, field = "pay.perStud" },
			{ changes = { pay = { perStud = 0 / 0, grip = 60 } }, field = "pay.perStud" },
			{ changes = { pay = { perStud = 0.5, grip = 6.5 } }, field = "pay.grip" },
			{ changes = { foodBag = { seconds = 0, squeezes = 50 } }, field = "foodBag.seconds" },
			{ changes = { foodBag = { seconds = 150, squeezes = 0 / 0 } }, field = "foodBag.squeezes" },
			{ changes = { gifts = { { biome = 9, kind = "bird", count = 1 } } }, field = "gifts[1].biome" },
			{ changes = { gifts = { { biome = 3, kind = "", count = 1 } } }, field = "gifts[1].kind" },
			{ changes = { gifts = { { biome = 3, kind = "bird", count = 0 } } }, field = "gifts[1].count" },
			{ changes = { gifts = "bird" }, field = "gifts" },
			{ changes = { inFlightGraceSeconds = 1 }, field = "inFlightGraceSeconds" }, -- not under the release
			{ changes = { areaMarginStuds = -1 }, field = "areaMarginStuds" },
		}
		for _, case in cases do
			local problems = validate(broken(case.changes))
			if not mentions(problems, case.field) then
				error(`expected a problem naming {case.field}, got: {table.concat(problems, "; ")}`)
			end
		end
		-- The flight and the throw auto-click numbers, one key at a time.
		local function brokenIn(section: string, key: string, value: any): any
			local copy = table.clone(Config.Economy.Highway[section])
			copy[key] = value
			return broken({ [section] = copy })
		end
		for _, key in { "releaseSeconds", "carryShare", "carryMin", "airSeconds", "airRoot", "groundRef" } do
			expect.truthy(mentions(validate(brokenIn("flight", key, 0)), `flight.{key}`))
		end
		expect.truthy(mentions(validate(brokenIn("flight", "carryMax", 10)), "flight.carryMax")) -- under carryMin
		expect.truthy(mentions(validate(brokenIn("autoClick", "blockIntervals", 1)), "autoClick.blockIntervals"))
		expect.truthy(mentions(validate(brokenIn("autoClick", "windowIntervals", 30)), "autoClick.windowIntervals"))
		expect.truthy(mentions(validate(brokenIn("autoClick", "maxMeanGapSeconds", 0)), "autoClick.maxMeanGapSeconds"))
		expect.truthy(
			mentions(validate(brokenIn("autoClick", "maxBlockSpreadSeconds", 0.5)), "autoClick.maxBlockSpreadSeconds")
		)
		expect.truthy(mentions(validate(brokenIn("autoClick", "burstGapSeconds", 1)), "autoClick.burstGapSeconds"))
		expect.truthy(mentions(validate(brokenIn("autoClick", "floodPresses", 0)), "autoClick.floodPresses"))
		-- The flood line sits above anything an honest client can send in a second (2 x its cap: a stall's held
		-- presses and that second's own).
		local cap = Config.Economy.Highway.autoClick.clientPressesPerSecond
		expect.truthy(mentions(validate(brokenIn("autoClick", "floodPresses", 2 * cap)), "autoClick.floodPresses"))
		-- The ceiling rule: a stream at the client's cap is never judged.
		expect.truthy(mentions(validate(brokenIn("autoClick", "maxPerSecond", cap)), "autoClick.maxPerSecond"))
		expect.truthy(
			mentions(validate(brokenIn("autoClick", "clientPressesPerSecond", 2.5)), "autoClick.clientPressesPerSecond")
		)
		-- With Config.Net: HighwayThrow's bucket holds the client's cap, and squeezing and throwing at full speed stay
		-- under the global cap (an honest kid is never limited or muted).
		local function withNet(net: any): any
			local copy = broken({})
			copy.Net = net
			return copy
		end
		local live = Config.Net
		local function net(rate: number, burst: number, globalRate: number): any
			return {
				AutoClick = live.AutoClick,
				Remotes = { HighwayThrow = { rate = rate, burst = burst } },
				Global = { rate = globalRate, burst = live.Global.burst },
			}
		end
		local remote = live.Remotes.HighwayThrow
		expect.deepEqual(validate(withNet(net(remote.rate, remote.burst, live.Global.rate))), {})
		expect.truthy(mentions(validate(withNet(net(cap, remote.burst, live.Global.rate))), "HighwayThrow"))
		expect.truthy(mentions(validate(withNet(net(remote.rate, cap - 1, live.Global.rate))), "HighwayThrow"))
		expect.truthy(mentions(validate(withNet(net(remote.rate, remote.burst, cap))), "Global.rate"))
		-- A gift kind the catalog does not know (only checked with a catalog).
		local unknown = broken({ gifts = { { biome = 3, kind = "pizza", count = 1 } } })
		expect.deepEqual(validate(unknown), {})
		expect.truthy(mentions(
			validate(unknown, {
				isValidId = function(id: string)
					return id ~= "pizza"
				end,
			}),
			"gifts[1].kind"
		))
	end)

	t.test("p13v3: one stud farther pays at least one Coin more (perStud x Pen.minSqueezeValue >= 1)", function()
		local function withPen(perStud: number, least: number): any
			local copy = broken({ pay = { perStud = perStud, grip = 60, ringShare = 0.1 } })
			copy.Economy.Pen = { minSqueezeValue = least }
			return copy
		end
		expect.deepEqual(validate(withPen(0.5, 10)), {})
		expect.deepEqual(validate(withPen(0.1, 10)), {})
		expect.truthy(mentions(validate(withPen(0.05, 10)), "pay.perStud"))
		expect.truthy(mentions(validate(withPen(0.5, 1)), "pay.perStud"))
		-- no Pen section: not checked
		expect.deepEqual(validate(broken({ pay = { perStud = 0.05, grip = 60, ringShare = 0.1 } })), {})
	end)

	-- P13v4 (owner 2026-10-19: the TikTok throw): the flight's new keys, the PERFECT bar, the boost, the ring pay.
	t.test("p13v4: each broken flight, timing, boost and ring-pay value is reported by name", function()
		local function brokenIn(section: string, key: string, value: any): any
			local copy = table.clone(Config.Economy.Highway[section])
			copy[key] = value
			return broken({ [section] = copy })
		end
		local cases: { { section: string, key: string, value: any } } = {
			{ section = "flight", key = "peakMax", value = 0 },
			{ section = "flight", key = "releaseUp", value = -1 },
			{ section = "flight", key = "releaseUp", value = 0 / 0 },
			{ section = "flight", key = "centreStuds", value = 0 },
			{ section = "timing", key = "periodSeconds", value = 0 },
			{ section = "timing", key = "perfectHalfWidth", value = 0 },
			{ section = "timing", key = "perfectHalfWidth", value = 0.5 },
			{ section = "timing", key = "perfectPower", value = 0.5 },
			{ section = "timing", key = "maxOneWaySeconds", value = -0.1 },
			{ section = "boost", key = "fuel", value = 1.5 },
			{ section = "boost", key = "fuel", value = -1 },
			{ section = "boost", key = "power", value = 0.9 },
			{ section = "boost", key = "afterReleaseSeconds", value = -1 },
			{ section = "boost", key = "beforeCarrySeconds", value = math.huge },
			{ section = "boost", key = "minAheadStuds", value = -1 },
			{ section = "boost", key = "speedUp", value = 0 },
			{ section = "boost", key = "minAirSeconds", value = 0 },
			{ section = "pay", key = "ringShare", value = -0.1 },
			{ section = "pay", key = "ringShare", value = "0.1" },
		}
		for _, case in cases do
			local problems = validate(brokenIn(case.section, case.key, case.value))
			local field = `{case.section}.{case.key}`
			if not mentions(problems, field) then
				error(
					`expected a problem naming {field} for {tostring(case.value)}, got: {table.concat(problems, "; ")}`
				)
			end
		end
		-- 0 is allowed where it means "none": no lift at the release, no fuel, no wait or margin, no ring pay.
		for _, case in
			{
				{ section = "flight", key = "releaseUp" },
				{ section = "timing", key = "maxOneWaySeconds" },
				{ section = "boost", key = "fuel" },
				{ section = "boost", key = "afterReleaseSeconds" },
				{ section = "boost", key = "beforeCarrySeconds" },
				{ section = "boost", key = "minAheadStuds" },
				{ section = "pay", key = "ringShare" },
			}
		do
			expect.deepEqual(validate(brokenIn(case.section, case.key, 0)), {})
		end
		-- A missing section is named too.
		expect.truthy(mentions(validate(broken({ timing = false })), "timing"))
		local noBoost = broken({})
		noBoost.Economy.Highway.boost = nil
		expect.truthy(mentions(validate(noBoost), "boost"))
	end)
end
