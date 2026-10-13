--!strict
-- GripMath_Test: unit tests for ReplicatedStorage.Shared.GripMath. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §17.3-§17.5, §17.7, §17.12 Part 5): integers only. levelFor gives the highest level whose
-- LevelTotals <= total (edges checked at every threshold, t - 1 and t); progress at the max level; ranks Soft (Lv 1)
-- .. Squish Master (Lv 50) .. Infinite (Lv 100, spec 2026-10-12 §10); pads open at Lv 5 / 15 / 30 and canUseTier
-- fails closed; afkGrip and afkMinutes are gone with slow training (build plan Phase 6), and the trainer helpers
-- (trainer, squeezeGrip, upgradeReady, upgradeDecision, topShopSquishyId) with the trainers (Phase 6; own squeezes pay
-- CapsuleMath's squeeze value and Grip since Phase 3); restedMinutes 9 when full (holding repeats every
-- Hold.repeatSeconds, 0.45 s, since every click pays; it was 30 with the old 1.5 s cycle); nextGoal: the next pad or
-- rank (the pad first on a tie), then max.
-- Every table is compared by value (Config here is the runner's copy; GripMath reads the same copy).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- §17.3.3 ranks: a level and its expected rank key.
local RANK_CASES: { { level: number, key: string } } = {
	{ level = 1, key = "soft" },
	{ level = 9, key = "soft" },
	{ level = 10, key = "firm" },
	{ level = 19, key = "firm" },
	{ level = 20, key = "strong" },
	{ level = 29, key = "strong" },
	{ level = 30, key = "iron" },
	{ level = 39, key = "iron" },
	{ level = 40, key = "titan" },
	{ level = 49, key = "titan" },
	{ level = 50, key = "master" },
	-- Spec 2026-10-12 §10: the ranks above Lv 50.
	{ level = 59, key = "master" },
	{ level = 60, key = "legend" },
	{ level = 70, key = "mythic" },
	{ level = 80, key = "cosmic" },
	{ level = 90, key = "galaxy" },
	{ level = 99, key = "galaxy" },
	{ level = 100, key = "infinite" },
}

-- §17.4 pads: (level, best tier).
local TIER_CASES = { { 1, 1 }, { 4, 1 }, { 5, 2 }, { 14, 2 }, { 15, 3 }, { 29, 3 }, { 30, 4 }, { 50, 4 } }

return function(t: Context)
	local GripMath = t.requireShared("GripMath")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local GRIP = Config.Grip
	local TOTALS = GRIP.LevelTotals
	local MAX_LEVEL = GRIP.maxLevel

	local function state(total: number): any
		return { total = total }
	end

	-- Levels --------------------------------------------------------------------------------------------------

	t.test("levelFor: every threshold t gives that level and t - 1 the level below", function()
		local wrong = {}
		for level = 2, #TOTALS do
			local threshold = TOTALS[level]
			if GripMath.levelFor(threshold) ~= level then
				table.insert(
					wrong,
					string.format("levelFor(%d) = %d, want %d", threshold, GripMath.levelFor(threshold), level)
				)
			end
			if GripMath.levelFor(threshold - 1) ~= level - 1 then
				table.insert(
					wrong,
					string.format(
						"levelFor(%d) = %d, want %d",
						threshold - 1,
						GripMath.levelFor(threshold - 1),
						level - 1
					)
				)
			end
		end
		if #wrong > 0 then
			error(table.concat(wrong, "; "))
		end
	end)

	t.test("levelFor: 0, negative and non-finite totals are Lv 1; above maxGrip is the max level", function()
		expect.equal(GripMath.levelFor(0), 1)
		expect.equal(GripMath.levelFor(-500), 1)
		expect.equal(GripMath.levelFor(0 / 0), 1)
		expect.equal(GripMath.levelFor(math.huge), 1)
		expect.equal(GripMath.levelFor(GRIP.maxGrip * 2), MAX_LEVEL)
		expect.equal(GripMath.levelFor(999.9), 1) -- floored: 999 < 1,000
	end)

	t.test("progress inside a level gives the level start, the next total and the bar parts", function()
		local p = GripMath.progress(1500) -- Lv 2 spans 1,000 .. 1,700 (spec 2026-10-12 totals)
		expect.deepEqual(p, {
			level = 2,
			total = 1500,
			levelStart = 1000,
			nextTotal = 1700,
			into = 500,
			span = 700,
			have = 1500,
			need = 1700,
			isMax = false,
		})
	end)

	t.test("progress at the maximum level", function()
		local top = TOTALS[#TOTALS]
		local p = GripMath.progress(top + 12345)
		expect.equal(p.level, MAX_LEVEL)
		expect.truthy(p.isMax)
		expect.equal(p.levelStart, top)
		expect.equal(p.nextTotal, top)
		expect.equal(p.span, 0)
		expect.equal(p.into, 12345)
		expect.equal(p.have, top + 12345)
	end)

	t.test("clampTotal, addGrip and clampEvent stay whole and inside the caps", function()
		expect.equal(GripMath.clampTotal(12.7), 12)
		expect.equal(GripMath.clampTotal(-3), 0)
		expect.equal(GripMath.clampTotal(0 / 0), 0)
		expect.equal(GripMath.clampTotal(GRIP.maxGrip + 5), GRIP.maxGrip)
		expect.equal(GripMath.addGrip(GRIP.maxGrip - 10, 600), GRIP.maxGrip)
		expect.equal(GripMath.addGrip(100, 30), 130)
		local clamped, was = GripMath.clampEvent(GRIP.maxGripPerEvent + 1)
		expect.equal(clamped, GRIP.maxGripPerEvent)
		expect.truthy(was)
		local fine, wasFine = GripMath.clampEvent(375)
		expect.equal(fine, 375)
		expect.falsy(wasFine)
	end)

	-- Ranks and pads --------------------------------------------------------------------------------------------

	t.test("rankFor gives Soft Grip at Lv 1 up to Squish Master at Lv 50 and Infinite at Lv 100", function()
		for _, case in RANK_CASES do
			local rank = GripMath.rankFor(case.level)
			if rank.key ~= case.key then
				error(string.format("rankFor(%d) = %s, want %s", case.level, tostring(rank.key), case.key))
			end
		end
		local nextRank = GripMath.nextRank(1)
		expect.equal(nextRank and nextRank.key, "firm")
		local afterMaster = GripMath.nextRank(50)
		expect.equal(afterMaster and afterMaster.key, "legend")
		expect.equal(GripMath.nextRank(100), nil)
	end)

	t.test("bestTier opens the Jelly Pad at Lv 5, the Marshmallow Pad at 15 and the Royal Cushion at 30", function()
		for _, case in TIER_CASES do
			if GripMath.bestTier(case[1]) ~= case[2] then
				error(string.format("bestTier(%d) = %d, want %d", case[1], GripMath.bestTier(case[1]), case[2]))
			end
		end
	end)

	t.test("canUseTier checks the pad's level and fails closed on an unknown tier", function()
		expect.truthy(GripMath.canUseTier(1, 1))
		expect.falsy(GripMath.canUseTier(4, 2))
		expect.truthy(GripMath.canUseTier(5, 2))
		expect.falsy(GripMath.canUseTier(29, 4))
		expect.truthy(GripMath.canUseTier(30, 4))
		expect.truthy(GripMath.canUseTier(50, 3)) -- a lower pad stays open
		expect.falsy(GripMath.canUseTier(50, 5))
		expect.falsy(GripMath.canUseTier(50, 0))
		expect.falsy(GripMath.canUseTier(50, 1.5))
		expect.equal(GripMath.pad(2) and GripMath.pad(2).key, "jelly")
		expect.equal(GripMath.pad(9), nil)
	end)

	-- Amounts ---------------------------------------------------------------------------------------------------

	t.test("slow training is gone (build plan Phase 6): no afkGrip or afkMinutes", function()
		expect.equal((GripMath :: any).afkGrip, nil)
		expect.equal((GripMath :: any).afkMinutes, nil)
	end)

	t.test("the trainers are gone (build plan Phase 6): no trainer, squeezeGrip or upgrade helpers", function()
		for _, name in { "trainer", "squeezeGrip", "upgradeReady", "upgradeDecision", "topShopSquishyId" } do
			expect.equal((GripMath :: any)[name], nil)
		end
	end)

	t.test("restedMinutes: 9 when full, ceil of points × Hold.repeatSeconds (0.45 s), whole points only", function()
		expect.equal(GRIP.Hold.repeatSeconds, 0.45)
		expect.equal(GripMath.restedMinutes(GRIP.Rested.burst), 9)
		expect.equal(GripMath.restedMinutes(0), 0)
		expect.equal(GripMath.restedMinutes(0.5), 0)
		expect.equal(GripMath.restedMinutes(1), 1)
		expect.equal(GripMath.restedMinutes(133), 1) -- 59.85 s of holding
		expect.equal(GripMath.restedMinutes(134), 2) -- 60.3 s
	end)

	t.test("unlocks lists the pads and the rank reached between two levels", function()
		expect.deepEqual(GripMath.unlocks(4, 5), { pads = { 2 } })
		local firm = GripMath.unlocks(9, 10)
		expect.deepEqual(firm.pads, {})
		expect.equal(firm.rank and firm.rank.key, "firm")
		local all = GripMath.unlocks(1, 50)
		expect.deepEqual(all.pads, { 2, 3, 4 })
		expect.equal(all.rank and all.rank.key, "master")
		expect.deepEqual(GripMath.unlocks(5, 5), { pads = {} })
	end)

	-- Next goal (§17.7; build plan Phase 6: no trainers, so the next pad or rank, then max) ------------------------

	t.test("nextGoal: a new player is pointed at the Jelly Pad (Lv 5)", function()
		expect.deepEqual(GripMath.nextGoal(state(0)), {
			kind = "pad",
			textKey = "grip.goalPad",
			nameKey = "grip.pad.jelly",
			index = 2,
			level = 5,
		})
	end)

	t.test("nextGoal: the rank line when it is the nearest unlock", function()
		-- Lv 5: Firm Grip at Lv 10 comes before the Marshmallow Pad at Lv 15.
		expect.deepEqual(GripMath.nextGoal(state(TOTALS[5])), {
			kind = "rank",
			textKey = "grip.goalRank",
			nameKey = "grip.rank.firm",
			index = 2,
			level = 10,
		})
		-- Lv 31: no pad is left, Titan Grip comes at Lv 40.
		local late = GripMath.nextGoal(state(TOTALS[31]))
		expect.equal(late and late.nameKey, "grip.rank.titan")
		expect.equal(late and late.level, 40)
	end)

	t.test("nextGoal: on a tie the pad line comes before the rank (Lv 20: both at Lv 30)", function()
		local goal = GripMath.nextGoal(state(TOTALS[20]))
		expect.equal(goal and goal.kind, "pad")
		expect.equal(goal and goal.nameKey, "grip.pad.royal")
		expect.equal(goal and goal.level, 30)
	end)

	t.test("nextGoal at the max level: grip.goalMax", function()
		expect.deepEqual(GripMath.nextGoal(state(TOTALS[#TOTALS])), { kind = "max", textKey = "grip.goalMax" })
	end)

	t.test("nextGoal is a pad, a rank or max at every level, never a trainer or a price (Phase 6)", function()
		for level = 1, MAX_LEVEL do
			local goal: any = GripMath.nextGoal(state(TOTALS[level]))
			local kind = if goal then goal.kind else "none"
			if (kind ~= "pad" and kind ~= "rank" and kind ~= "max") or (goal and goal.coins) ~= nil then
				error(`Lv {level}: {kind}`)
			end
		end
	end)
end
