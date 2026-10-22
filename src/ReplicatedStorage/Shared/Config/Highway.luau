--!strict
-- Config.Economy.Highway: the highway's distances (pens3 phase 12, 2026-10-17). Shared, data only. Every distance is
-- in studs along the lane from the start line (the launch gate), the unit phase 13's landing math works in, so a
-- landing at d studs lands on the built lane exactly d studs from the gate (World/WorldLayout.highwayCFrame).
-- Numbers: PLAN phase 12 and PR3:36 ("biome starts STAY"; the Golden Gates at 8,500 "so they match the coin math",
-- moved from v6's 8,350, layout.json:1597), the v6 kit's biome table (kit.json:3136-3529). A child module, so
-- Config/init does not grow: exposed through Config/Economy and checked by Config/ValidateHighway (HighwayBuilder
-- runs it; phase 13's highway service runs it at init). The look of each biome is WorldLayout.Highway.biomes (the
-- same order).
-- Pens3 phase 13 (2026-10-18; work/pens3/PLAN.md "PHASE 13" with the owner's corrections, work/pens3/p13v2/NOTES.md):
-- the throw for distance. Shared/HighwayMath does the math, HighwayService the server's part. Sources: J =
-- work/econ4/final_hagb_grip110.json, G110 = work/econ4/out5_grip110.txt, SIM = work/econ4/sim5.js, V3 =
-- work/econ3/ECONOMY_V3.md, P3D = the lobby design v6's "Squishy Lobby 3D.html", K = its kit.json. [P] = provisional.
-- P13v4 (owner 2026-10-19: copy the TikTok duck throw on all 4 points; work/pens3/p13v4/SPEC.md, numbers from its
-- spec/curve.js): longer throws (power.base 900, a flight that is almost all air: carryShare 0.9 up to the gates,
-- arcs at most peakMax high, a short roll), the PERFECT timing bar (timing), one boost a throw (boost) and the rings'
-- pay (pay.ringShare). Every new number is [P].

local Highway = {
	-- Where biome n starts (Candy Meadow, Bakery Town, Boba Lagoon, Frozen Dessert Peaks, Lava Volcano, Rainbow Road,
	-- Divine Heaven); biome n ends where n + 1 starts, the last at gatesAt (300 / 500 / 700 / 1,000 / 1,500 / 2,000 /
	-- 2,500 long).
	starts = { 0, 300, 800, 1_500, 2_500, 4_000, 6_000 },
	gatesAt = 8_500, -- the Golden Gates: the highway's end, the farthest a landing goes (V4:76)

	-- Pens3 phase 13 ------------------------------------------------------------------------------------------------
	-- The throw power each biome starts at (J band: 1 / 14K / 330M / 16T / 1.2Qi / 62Sx / 1.6Oc) and the Golden Gates'
	-- (2.4e31). A throw of power P lands in biome n (walls[n] <= P < walls[n + 1], walls[8] = gatesPower) at
	-- starts[n] + length_n x ln(P / walls[n]) / ln(walls[n + 1] / walls[n]) studs (V4:76; SIM:89 distOf), at most
	-- gatesAt.
	walls = { 1, 14_000, 330_000_000, 16e12, 1.2e18, 6.2e22, 1.6e27 },
	gatesPower = 2.4e31,
	-- Throw power = base x perGripLevel^(Grip Lv - 1) (G110:42; the owner fixed x1.1 a level, 2026-10-17). Phase 14
	-- multiplies the gear in. P13v4 [P] base 2 -> 900: the smallest base where Grip Lv 1 lands "a few hundred" studs
	-- (213) and a PERFECT throw with its boost just enters Bakery Town (301), like the video's first throws passing a
	-- zone; every biome keeps its power wall, so the biomes are still reached by exponentially more power.
	-- Owner 2026-10-22: Grip grows slower, x1.1 -> x1.05 a level (Lv 100 lands 403 studs, was 632).
	power = { base = 900, perGripLevel = 1.05 },
	-- What every landing pays, in squeezes of the squeeze value: perStud x the landing's studs of Coins (p13v3, owner
	-- 2026-10-18: "it should give coins on base of how many meters far they go like hit a golf ball"; it replaces
	-- SIM:59's flat 70 x 1.15^(b - 1)) and grip of Grip (SIM:59 landGrip, SIM:241). Owner 2026-10-16 ("No daily limits
	-- on squeezes or throwing"): every landing pays in full, and the only pacing is one throw in flight per player.
	-- [P] perStud 0.5: each throw pays more the farther it flies; a second of throwing earns about 2x squeezing at Grip
	-- Lv 1 (21 studs, a 2.1 s flight), 14x at Lv 100, 96x at the Golden Gates (it dips from 6.7x to 4.1x at Lv 18,
	-- where the 1.6 s roll starts; work/pens3/p13v3/NOTES.md, econ/paytable.js). P13v4 (the longer throws; the owner
	-- accepted that they pay more): Lv 1 throws 213 studs, about 15x squeezing (10x with a 1.5 s pause between throws),
	-- 35x at Lv 100 (SPEC table 1). [P] ringShare: each ring the squishy flies through adds 10 % to that throw's Coins.
	pay = { perStud = 0.5, grip = 60, ringShare = 0.1 },
	-- The Food Bag (SIM:59 foodEvery / foodSV, :239; V3:185): every `seconds` of flight time of paid throws,
	-- `squeezes` x the squeeze value of food (pieces of the weakest placed squishy's band food).
	foodBag = { seconds = 150, squeezes = 50 },
	-- The biome gifts (SIM:205: 3 Boba Bears at Boba Lagoon, a Bird at Lava Volcano, 3 Cloud Bunnies at Divine Heaven),
	-- given once each, in the throw that first reaches the biome (a full Toy Box queues them, pens3 phase 5).
	gifts = {
		{ biome = 3, kind = "boba_bear", count = 3 },
		{ biome = 5, kind = "bird", count = 1 },
		{ biome = 7, kind = "cloud_bunny", count = 3 },
	} :: { { biome: number, kind: string, count: number } },
	-- The flight (P3D:575-597, the design's own throw; HighwayMath.flight). Release at the A3 "Release" marker (K:5295,
	-- 0.42 s), then the air: a carry of carryShare x the landing (P3D:554, at least carryMin and at most carryMax, and
	-- never past the landing) over airSeconds + airPerRoot x sqrt(the carry / airRoot) seconds, peaking at peakShare
	-- x the carry (P3D:575); then the roll: groundSeconds + groundScale x (the rest / groundRef)^groundPower seconds
	-- (P3D:575), eased 1 - (1 - v)^rollPower (P3D:590), hopping every hopEvery studs hopBase + hopScale x (1 - d / D)
	-- high (P3D:555). The server keeps a throw in flight for release + air + roll.
	-- P13v4 [P] (the video flies almost all the way, and the boost and the rings need air time; v6's 32 % carry left
	-- little): carryShare 0.32 -> 0.9, carryMax 1,100 -> 8,500, the arc at most peakMax high (the chase camera stays
	-- near the lane), groundSeconds 1.6 -> 0.5 and groundScale 15 -> 2 (a short roll). The release starts releaseUp
	-- above the thrower's root (the hand), and the squishy drifts from the release's x to the lane's centre over the
	-- first centreStuds studs (the rings are centred). HighwayMath.arc / newPlan / planAt.
	flight = {
		releaseSeconds = 0.42,
		carryShare = 0.9,
		carryMin = 70,
		carryMax = 8_500,
		airSeconds = 1.1,
		airPerRoot = 2.4,
		airRoot = 900,
		peakShare = 0.175,
		peakMax = 60,
		groundSeconds = 0.5,
		groundScale = 2,
		groundRef = 8_000,
		groundPower = 0.75,
		rollPower = 1.8,
		hopEvery = 75,
		hopBase = 0.8,
		hopScale = 3.5,
		releaseUp = 1.5,
		centreStuds = 60,
	},
	-- P13v4 [P] The PERFECT timing bar (HighwayMath.barAt / isPerfect): a triangle wave 0 -> 1 -> 0 every periodSeconds
	-- of the shared server clock; a press whose arrival, less half the player's ping (at most maxOneWaySeconds), finds
	-- the bar within perfectHalfWidth of the middle is PERFECT (the green middle 20 %: 160 ms a pass, a random press 1
	-- time in 5) and throws with perfectPower x the power (about +20 % distance early, +6 % late). Anything else is a
	-- normal throw: no penalty.
	timing = { periodSeconds = 1.6, perfectHalfWidth = 0.1, perfectPower = 4, maxOneWaySeconds = 0.25 },
	-- P13v4 [P] The boost (the video: "QUACK! x1", then "NO FUEL"): `fuel` boosts a throw. A THROW press during the own
	-- flight asks for one; it is refused before afterReleaseSeconds after the release (a double tap at the throw never
	-- wastes it) and after beforeCarrySeconds before the air ends. It multiplies the power by `power` (the size of a
	-- PERFECT), flies on from where the squishy is, at least minAheadStuds farther, speedUp x faster than the arc it
	-- leaves and never under minAirSeconds (HighwayMath.boost).
	boost = {
		fuel = 1,
		power = 4,
		afterReleaseSeconds = 0.2,
		beforeCarrySeconds = 0.15,
		minAheadStuds = 30,
		speedUp = 1.25,
		minAirSeconds = 0.5,
	},
	-- [P] The next throw may start this much before the server's landing (the client times its landing on the server
	-- clock it reads, a few ms off).
	inFlightGraceSeconds = 0.1,
	-- [P] The server's throw-area check: the character root inside WorldLayout.Highway.throwArea, this much bigger on
	-- every side (the server sees the root a little behind the client).
	areaMarginStuds = 1,
	-- [P] The auto-clicker check on the THROW presses (owner 2026-10-16: "punishes step by step", "bans players with
	-- very high clicks per second"; AutoClickService.checkThrow). The client sends every THROW press while it stands in
	-- the throw area (a press during a flight asks for its boost, p13v4), at most clientPressesPerSecond in any
	-- rolling second and none while a reply is a second late, so the server sees the real press rhythm (with the
	-- squeeze presses' cap, Config.Net.AutoClick.clientPressesPerSecond, under Config.Net.Global.rate: a kid mashing
	-- both is never limited). Rule B (Logic/AutoClickRules: blocks of blockIntervals gaps, the spread of their mean
	-- gaps at most maxBlockSpreadSeconds over windowIntervals gaps of one burst, a pause over burstGapSeconds starting
	-- it again), never on a window as fast as maxPerSecond (the client's own ceiling rhythm: past it a kid and a macro
	-- look alike), with the squeeze study's window (Config.Net.AutoClick: 400 gaps in blocks of 20, a 0.7 ms spread),
	-- but a throw press comes far slower than a squeeze, so a window may be as slow as maxMeanGapSeconds a press (an
	-- unattended macro clicking once a second is caught after 400 s). The flood rule: more than floodPresses presses
	-- inside one second, which our client never sends (at most twice its cap: a network stall's held presses and that
	-- second's own), only a changed client or a script does. The steps are AutoClick's (warn with a pause, kick, then
	-- bans; Config.Net.AutoClick.enforce).
	-- Verification fix: the cap is 12 (the most Net.Global.rate leaves beside the squeeze presses' 18), so a clicker at
	-- the usual auto-clicker default of 10 a second (100 ms) is slower than the ceiling's rhythm and rule B judges it
	-- (caught after 40 s); one at 11 a second or faster is held at the cap and looks like a fast kid (as squeezes past
	-- 17 a second). floodPresses keeps its margin over twice the cap (24).
	autoClick = {
		clientPressesPerSecond = 12,
		maxPerSecond = 11,
		windowIntervals = 400,
		blockIntervals = 20,
		maxMeanGapSeconds = 6,
		maxBlockSpreadSeconds = 0.0007,
		burstGapSeconds = 8,
		floodPresses = 30,
	},
}

return Highway
