--!strict
-- GripMath_Test: unit tests for ReplicatedStorage.Shared.GripMath. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §17.3-§17.5, §17.7, §17.12 Part 5): integers only. levelFor gives the highest level whose
-- LevelTotals <= total (edges checked at every threshold, t - 1 and t); progress at the max level; ranks Soft (Lv 1)
-- .. Squish Master (Lv 50) .. Infinite (Lv 100, spec 2026-10-12 §10); pad, bestTier and canUseTier are gone with the
-- giant pads (build plan Phase 6); afkGrip and afkMinutes are gone with slow training (Phase 6), and the trainer helpers
-- (trainer, squeezeGrip, upgradeReady, upgradeDecision, topShopSquishyId) with the trainers (Phase 6; own squeezes pay
-- CapsuleMath's squeeze value and Grip since Phase 3); restedMinutes 9 when full (holding repeats every
-- Hold.repeatSeconds, 0.45 s, the hold rhythm; it was 30 with the old 1.5 s cycle); nextGoal: with capsules and
-- Coins, the capsule buy first (Batch 1; an unlock only while a spare squishy waits), then the next rank, then max
-- (never a pad since Phase 6).
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

	local function caps(list: { any }): any
		return { slots = #list, list = list }
	end

	-- Owned squishies: kitty_bread (in Capsule 1 in these tests) and toast, a spare for a new capsule.
	local WITH_SPARE = { kitty_bread = { at = 1, src = "shop" }, toast = { at = 2, src = "shop" } }

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

	-- Ranks -----------------------------------------------------------------------------------------------------

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

	t.test("the giant pads are gone (build plan Phase 6): no pad, bestTier or canUseTier", function()
		for _, name in { "pad", "bestTier", "canUseTier" } do
			expect.equal((GripMath :: any)[name], nil)
		end
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

	t.test("unlocks gives the rank reached between two levels (no pads since Phase 6)", function()
		expect.deepEqual(GripMath.unlocks(4, 5), {})
		local firm = GripMath.unlocks(9, 10)
		expect.equal(firm.rank and firm.rank.key, "firm")
		expect.equal((firm :: any).pads, nil)
		local all = GripMath.unlocks(1, 50)
		expect.equal(all.rank and all.rank.key, "master")
		expect.deepEqual(GripMath.unlocks(5, 5), {})
	end)

	-- Next goal (§17.7; build plan Phase 6: no trainers or pads, so the next rank, then max) -----------------------

	t.test("nextGoal: a new player is pointed at the next rank, Firm Grip (Lv 10)", function()
		expect.deepEqual(GripMath.nextGoal(state(0)), {
			kind = "rank",
			textKey = "grip.goalRank",
			nameKey = "grip.rank.firm",
			index = 2,
			level = 10,
		})
		-- Lv 31: Titan Grip comes at Lv 40.
		local late = GripMath.nextGoal(state(TOTALS[31]))
		expect.equal(late and late.nameKey, "grip.rank.titan")
		expect.equal(late and late.level, 40)
	end)

	t.test("nextGoal at the max level: grip.goalMax", function()
		expect.deepEqual(GripMath.nextGoal(state(TOTALS[#TOTALS])), { kind = "max", textKey = "grip.goalMax" })
	end)

	t.test("nextGoal is a rank or max at every level without capsules in the state (Phase 6)", function()
		for level = 1, MAX_LEVEL do
			local goal: any = GripMath.nextGoal(state(TOTALS[level]))
			local kind = if goal then goal.kind else "none"
			if (kind ~= "rank" and kind ~= "max") or (goal and goal.coins) ~= nil then
				error(`Lv {level}: {kind}`)
			end
		end
	end)

	-- Batch 1 #7a: the Next line names the capsule buy first.
	t.test("an affordable capsule upgrade is READY, even when an unlock is cheaper", function()
		local one = caps({ { level = 1, squishyId = "kitty_bread" } })
		expect.deepEqual(GripMath.nextGoal({ total = 0, coins = 1_000, capsules = one }), {
			kind = "capsuleReady",
			textKey = "grip.goalCapsuleReady",
			slot = 1,
			level = 2,
			have = 1_000,
			need = 1_000,
		})
		-- Lv 5 -> 6 costs 3,200, more than Capsule 2's 2,500 unlock: the affordable upgrade still wins.
		local five = GripMath.nextGoal({
			total = 0,
			coins = 3_300,
			capsules = caps({ { level = 5, squishyId = "kitty_bread" } }),
			owned = WITH_SPARE,
		})
		expect.equal(five and five.kind, "capsuleReady")
		expect.equal(five and five.slot, 1)
		expect.equal(five and five.level, 6)
		expect.equal(five and five.need, 3_200)
	end)

	t.test("else the cheapest capsule buy with progress (ties: the lower slot)", function()
		local one = caps({ { level = 1, squishyId = "kitty_bread" } })
		expect.deepEqual(GripMath.nextGoal({ total = 0, coins = 120, capsules = one }), {
			kind = "capsule",
			textKey = "grip.goalCapsule",
			slot = 1,
			level = 2,
			have = 120,
			need = 1_000,
		})
		local five = caps({ { level = 5, squishyId = "kitty_bread" } })
		expect.deepEqual(GripMath.nextGoal({ total = 0, coins = 100, capsules = five, owned = WITH_SPARE }), {
			kind = "unlock",
			textKey = "grip.goalUnlock",
			slot = 2,
			have = 100,
			need = 2_500,
		})
		expect.deepEqual(GripMath.nextGoal({ total = 0, coins = 2_600, capsules = five, owned = WITH_SPARE }), {
			kind = "unlockReady",
			textKey = "grip.goalUnlockReady",
			slot = 2,
			have = 2_500,
			need = 2_500,
		})
		-- An empty capsule has no upgrade to name.
		local withEmpty = caps({ { level = 1, squishyId = "kitty_bread" }, { level = 1 } })
		local first = GripMath.nextGoal({ total = 0, coins = 0, capsules = withEmpty })
		expect.equal(first and first.slot, 1)
		expect.equal(first and first.need, 1_000)
		local two = caps({ { level = 2, squishyId = "kitty_bread" }, { level = 2, squishyId = "toast" } })
		local tie = GripMath.nextGoal({ total = 0, coins = 0, capsules = two })
		expect.equal(tie and tie.slot, 1)
		expect.equal(tie and tie.need, 1_300)
	end)

	t.test("the unlock waits for a spare squishy: a new capsule would open empty and earn nothing", function()
		local five = caps({ { level = 5, squishyId = "kitty_bread" } })
		local function goalWith(owned: any): any
			return GripMath.nextGoal({ total = 0, coins = 2_600, capsules = five, owned = owned })
		end
		local upgrade =
			{ kind = "capsule", textKey = "grip.goalCapsule", slot = 1, level = 6, have = 2_600, need = 3_200 }
		expect.deepEqual(goalWith(nil), upgrade)
		-- Only the squishy already in Capsule 1, or an id outside the Catalog (an old save): no spare.
		expect.deepEqual(goalWith({ kitty_bread = { at = 1, src = "shop" } }), upgrade)
		expect.deepEqual(goalWith({ kitty_bread = { at = 1, src = "shop" }, nope = { at = 2, src = "box" } }), upgrade)
		local spare = goalWith(WITH_SPARE)
		expect.equal(spare and spare.kind, "unlockReady")
		expect.equal(spare and spare.slot, 2)
	end)

	t.test("no capsule buy falls back to the rank", function()
		local gated = caps({
			{ level = 10, squishyId = "kitty_bread" },
			{ level = 10, squishyId = "toast" },
			{ level = 10, squishyId = "banana" },
			{ level = 10, squishyId = "butter" },
		})
		local blocked = GripMath.nextGoal({ total = 0, coins = 1e9, capsules = gated })
		expect.equal(blocked and blocked.kind, "rank")
		local noCapsules = GripMath.nextGoal({ total = 0, coins = 1e9 })
		expect.equal(noCapsules and noCapsules.kind, "rank")
		local wrong = GripMath.nextGoal({ total = 0, coins = 1e9, capsules = "x" })
		expect.equal(wrong and wrong.kind, "rank")
	end)
end
