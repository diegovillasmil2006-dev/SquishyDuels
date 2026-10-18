--!strict
-- Config.Economy.Highway: the highway's distances (pens3 phase 12, 2026-10-17). Shared, data only. Every distance is
-- in studs along the lane from the start line (the launch gate), the unit phase 13's landing math works in, so a
-- landing at d studs lands on the built lane exactly d studs from the gate (World/WorldLayout.highwayCFrame).
-- Numbers: PLAN phase 12 and PR3:36 ("biome starts STAY"; the Golden Gates at 8,500 "so they match the coin math",
-- moved from v6's 8,350, layout.json:1597), the v6 kit's biome table (kit.json:3136-3529). A child module, so
-- Config/init does not grow: exposed through Config/Economy and checked by Config/ValidateHighway (HighwayBuilder
-- runs it; phase 13's highway service runs it at init). The look of each biome is WorldLayout.Highway.biomes (the
-- same order).

local Highway = {
	-- Where biome n starts (Candy Meadow, Bakery Town, Boba Lagoon, Frozen Dessert Peaks, Lava Volcano, Rainbow Road,
	-- Divine Heaven); biome n ends where n + 1 starts, the last at gatesAt (300 / 500 / 700 / 1,000 / 1,500 / 2,000 /
	-- 2,500 long).
	starts = { 0, 300, 800, 1_500, 2_500, 4_000, 6_000 },
	gatesAt = 8_500, -- the Golden Gates: the highway's end, the farthest a landing goes (V4:76)
}

return Highway
