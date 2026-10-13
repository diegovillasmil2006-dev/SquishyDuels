--!strict
-- GripMath_Test: unit tests for ReplicatedStorage.Shared.GripMath. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §17.3-§17.5, §17.7, §17.12 Part 5): integers only. levelFor gives the highest level whose
-- LevelTotals <= total (edges checked at every threshold, t - 1 and t); progress at the max level; ranks Soft (Lv 1)
-- .. Squish Master (Lv 50) .. Infinite (Lv 100, spec 2026-10-12 §10); pads open at Lv 5 / 15 / 30 and canUseTier
-- fails closed; squeezeGrip =
-- floor(gripPerSqueeze × gripPercent / 100), × 2 when doubled (the §17.3.1 table; Phase 3: squeezeCoins is gone, own
-- squeezes pay the squeeze value of CapsuleMath); afkGrip = floor(squeezeGrip × 125 / 100) (12, 37,
-- 100, 375); afkMinutes 40 for a full bank; restedMinutes 9 when full (holding repeats every Hold.repeatSeconds,
-- 0.45 s, since every click pays; it was 30 with the old 1.5 s cycle); nextGoal order (upgrade, next unlock, max),
-- both branches of the Dragon rule, and no trainer line while trainerAvailable = false. Part 7 (§17.12 L1):
-- upgradeDecision's every branch (buy, replay with charged = false, net.invalid, trainer.notNext, trainer.locked,
-- trainer.priceChanged) and its DESIGN check order.
-- Every table is compared by value (Config here is the runner's copy; GripMath reads the same copy).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- §17.3.1 "Grip per squeeze" (trainer rows × Foam Mats, Jelly, Marshmallow, Royal).
local GRIP_TABLE = {
	{ 10, 15, 20, 30 },
	{ 15, 22, 30, 45 },
	{ 20, 30, 40, 60 },
	{ 30, 45, 60, 90 },
	{ 40, 60, 80, 120 },
	{ 55, 82, 110, 165 },
	{ 75, 112, 150, 225 },
	{ 100, 150, 200, 300 },
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

	local function state(total: number, trainer: number): any
		return { total = total, trainer = trainer }
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
		expect.equal(GripMath.trainer(8) and GripMath.trainer(8).key, "diamond")
		expect.equal(GripMath.pad(9), nil)
	end)

	-- Amounts ---------------------------------------------------------------------------------------------------

	t.test("squeezeGrip matches the §17.3.1 table (floor rounding) and doubles with Double Grip", function()
		local wrong = {}
		for trainer, row in GRIP_TABLE do
			for tier, want in row do
				local got = GripMath.squeezeGrip(trainer, tier)
				local doubled = GripMath.squeezeGrip(trainer, tier, true)
				if got ~= want or doubled ~= want * GRIP.Rested.mult then
					table.insert(wrong, string.format("trainer %d tier %d: %d / %d", trainer, tier, got, doubled))
				end
			end
		end
		if #wrong > 0 then
			error(table.concat(wrong, "; "))
		end
		expect.equal(GripMath.squeezeGrip(2, 2), 22) -- 15 × 150% = 22.5, rounded down
		expect.equal(GripMath.squeezeGrip(0, 1), 0)
		expect.equal(GripMath.squeezeGrip(9, 1), 0)
		expect.equal(GripMath.squeezeGrip(1, 5), 0)
	end)

	t.test("afkGrip is one and a quarter squeezes' worth, rounded down (12, 37, 100, 375)", function()
		expect.equal(GripMath.afkGrip(1, 1), 12)
		expect.equal(GripMath.afkGrip(3, 2), 37)
		expect.equal(GripMath.afkGrip(5, 3), 100)
		expect.equal(GripMath.afkGrip(8, 4), 375)
		for trainer = 1, #GRIP.Trainer do
			for tier = 1, #GRIP.Pads do
				local want = math.floor(GripMath.squeezeGrip(trainer, tier) * GRIP.Afk.percentPerTick / 100)
				expect.equal(GripMath.afkGrip(trainer, tier), want)
			end
		end
	end)

	t.test("afkMinutes: 40 for a full bank, whole points only", function()
		expect.equal(GripMath.afkMinutes(GRIP.Afk.burst), 40)
		expect.equal(GripMath.afkMinutes(0), 0)
		expect.equal(GripMath.afkMinutes(0.9), 0)
		expect.equal(GripMath.afkMinutes(1), 1)
		expect.equal(GripMath.afkMinutes(3), 1)
		expect.equal(GripMath.afkMinutes(4), 2)
		expect.equal(GripMath.afkMinutes(119.5), 40)
		expect.equal(GripMath.afkMinutes(0 / 0), 0)
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

	-- Next goal (§17.5, §17.7) ---------------------------------------------------------------------------------

	t.test("the highest-priced shop squishy is Dragon", function()
		expect.equal(GripMath.topShopSquishyId(), "dragon")
	end)

	t.test("nextGoal: a new player is pointed at the first trainer gate (Lv 3) before the Jelly Pad (Lv 5)", function()
		local goal = GripMath.nextGoal(state(0, 1), {}, 0, true)
		expect.deepEqual(goal, {
			kind = "trainer",
			textKey = "grip.goalTrainer",
			nameKey = "grip.trainer.sponge",
			index = 2,
			level = 3,
		})
	end)

	t.test("nextGoal with trainerAvailable = false never shows a trainer line or badge", function()
		local goal = GripMath.nextGoal(state(0, 1), {}, 0, false)
		expect.equal(goal and goal.kind, "pad")
		expect.equal(goal and goal.nameKey, "grip.pad.jelly")
		expect.equal(goal and goal.level, 5)
		-- Lv 3 with the Coins for Sponge Ball: still no upgrade line without the remote.
		local rich = GripMath.nextGoal(state(TOTALS[3], 1), {}, 1000, false)
		expect.equal(rich and rich.kind, "pad")
		expect.falsy(GripMath.upgradeReady(state(TOTALS[3], 1), 1000, false))
	end)

	t.test("nextGoal: an affordable cheap upgrade comes first", function()
		local goal = GripMath.nextGoal(state(TOTALS[3], 1), {}, 1000, true)
		expect.deepEqual(goal, {
			kind = "upgrade",
			textKey = "grip.goalUpgrade",
			nameKey = "grip.trainer.sponge",
			index = 2,
			level = 3,
			coins = 1000,
		})
		expect.truthy(GripMath.upgradeReady(state(TOTALS[3], 1), 1000, true))
		-- One Coin short: not ready, the next unlock is the Jelly Pad.
		local short = GripMath.nextGoal(state(TOTALS[3], 1), {}, 999, true)
		expect.equal(short and short.kind, "pad")
		expect.falsy(GripMath.upgradeReady(state(TOTALS[3], 1), 999, true))
	end)

	t.test("nextGoal Dragon rule: a pricey upgrade waits until Dragon is owned (badge either way)", function()
		-- Lv 10 with Rubber Ball (trainer 3): Spring Gripper costs 12,000 (> 5,000) and is affordable.
		local s = state(TOTALS[10], 3)
		expect.truthy(GripMath.upgradeReady(s, 20000, true))
		local collecting = GripMath.nextGoal(s, { kitty_bread = {} }, 20000, true)
		expect.equal(collecting and collecting.kind, "pad")
		expect.equal(collecting and collecting.nameKey, "grip.pad.marshmallow")
		local done = GripMath.nextGoal(s, { kitty_bread = {}, dragon = {} }, 20000, true)
		expect.equal(done and done.kind, "upgrade")
		expect.equal(done and done.nameKey, "grip.trainer.spring")
		expect.equal(done and done.coins, 12000)
	end)

	t.test("nextGoal: on a tie the pad line comes before the trainer gate (Lv 12: Marshmallow Pad at Lv 15)", function()
		local goal = GripMath.nextGoal(state(TOTALS[12], 4), {}, 0, true)
		expect.equal(goal and goal.kind, "pad")
		expect.equal(goal and goal.nameKey, "grip.pad.marshmallow")
		expect.equal(goal and goal.level, 15)
	end)

	t.test("nextGoal: the rank line when it is the nearest unlock", function()
		-- Lv 31 with Gold Gripper (trainer 7): Diamond needs Lv 36, Titan Grip comes at Lv 40, no pad is left.
		local goal = GripMath.nextGoal(state(TOTALS[31], 7), {}, 0, true)
		expect.equal(goal and goal.kind, "trainer")
		expect.equal(goal and goal.level, 36)
		local noTrainer = GripMath.nextGoal(state(TOTALS[31], 7), {}, 0, false)
		expect.equal(noTrainer and noTrainer.kind, "rank")
		expect.equal(noTrainer and noTrainer.nameKey, "grip.rank.titan")
		expect.equal(noTrainer and noTrainer.level, 40)
	end)

	t.test("nextGoal at the max level: grip.goalMax, unless an upgrade is ready under the Dragon rule", function()
		local top = TOTALS[#TOTALS]
		expect.deepEqual(GripMath.nextGoal(state(top, 8), {}, 0, true), { kind = "max", textKey = "grip.goalMax" })
		local diamondReady = state(top, 7)
		local collecting = GripMath.nextGoal(diamondReady, {}, 150000, true)
		expect.equal(collecting and collecting.kind, "max")
		local withDragon = GripMath.nextGoal(diamondReady, { dragon = {} }, 150000, true)
		expect.equal(withDragon and withDragon.kind, "upgrade")
		expect.equal(withDragon and withDragon.nameKey, "grip.trainer.diamond")
	end)

	-- upgradeDecision (§17.5 steps 2 and 4-7, Part 7 L1: every branch, including a replay with charged = false) ----

	local TRAINER = GRIP.Trainer

	local function decide(trainer: number, level: number, target: number, price: number): any
		return GripMath.upgradeDecision({ trainer = trainer, level = level }, target, price)
	end

	t.test("upgradeDecision: the next trainer at its level and price is a charged buy", function()
		local sponge = TRAINER[2]
		expect.deepEqual(decide(1, sponge.level, 2, sponge.cost), { kind = "buy", cost = sponge.cost, charged = true })
		local diamond = TRAINER[8]
		expect.deepEqual(decide(7, MAX_LEVEL, 8, diamond.cost), { kind = "buy", cost = diamond.cost, charged = true })
	end)

	t.test("upgradeDecision: a trainer already owned is a replay with charged = false (step 4)", function()
		local sponge = TRAINER[2]
		expect.deepEqual(
			decide(2, sponge.level, 2, sponge.cost),
			{ kind = "replay", cost = sponge.cost, charged = false }
		)
		-- A replay answers before the later checks: the level and the price are not looked at.
		local replay = decide(5, 1, 3, 0)
		expect.equal(replay.kind, "replay")
		expect.equal(replay.charged, false)
		expect.equal(replay.reason, nil)
	end)

	t.test("upgradeDecision: TrainerUpgrade(8, 150000) at trainer 1 is trainer.notNext (step 5)", function()
		local result = decide(1, MAX_LEVEL, 8, TRAINER[8].cost)
		expect.deepEqual(
			result,
			{ kind = "reject", reason = "trainer.notNext", cost = TRAINER[8].cost, charged = false }
		)
	end)

	t.test("upgradeDecision: a level below the trainer's gate is trainer.locked (step 6)", function()
		local sponge = TRAINER[2]
		local result = decide(1, sponge.level - 1, 2, sponge.cost)
		expect.deepEqual(result, { kind = "reject", reason = "trainer.locked", cost = sponge.cost, charged = false })
		expect.equal(decide(1, sponge.level, 2, sponge.cost).kind, "buy")
	end)

	t.test("upgradeDecision: a price that differs from the config is trainer.priceChanged (step 7)", function()
		local sponge = TRAINER[2]
		for _, price in { 0, sponge.cost - 1, sponge.cost + 1 } do
			local result = decide(1, sponge.level, 2, price)
			expect.deepEqual(
				result,
				{ kind = "reject", reason = "trainer.priceChanged", cost = sponge.cost, charged = false }
			)
		end
	end)

	t.test("upgradeDecision: out-of-range or malformed arguments are net.invalid (step 2)", function()
		local maxAbs = Config.Net.maxAbsNumber
		local cases: { { any } } = {
			{ 1, 0 }, -- the free Foam Ball is never bought
			{ 0, 0 },
			{ #TRAINER + 1, 0 },
			{ 2.5, 1000 },
			{ 0 / 0, 1000 },
			{ math.huge, 1000 },
			{ "2", 1000 },
			{ 2, -1 },
			{ 2, 1000.5 },
			{ 2, maxAbs },
			{ 2, 0 / 0 },
			{ 2, "1000" },
		}
		for index, case in cases do
			local result = GripMath.upgradeDecision({ trainer = 1, level = MAX_LEVEL }, case[1], case[2])
			if result.kind ~= "reject" or result.reason ~= "net.invalid" or result.charged ~= false then
				error(`case {index} was not net.invalid ({result.kind}, {tostring(result.reason)})`)
			end
		end
		-- The bound is exclusive: maxAbsNumber - 1 is a well-formed (if wrong) price.
		expect.equal(decide(1, MAX_LEVEL, 2, maxAbs - 1).reason, "trainer.priceChanged")
	end)

	t.test("upgradeDecision: the checks run in DESIGN order (notNext before locked before priceChanged)", function()
		-- Trainer 1 asking for 3 at Lv 1 with a wrong price: step 5 answers first.
		expect.equal(decide(1, 1, 3, 1).reason, "trainer.notNext")
		-- The next trainer at Lv 1 with a wrong price: step 6 answers first.
		expect.equal(decide(1, 1, 2, 1).reason, "trainer.locked")
		-- A malformed trainer value counts as the free Foam Ball (1).
		expect.equal(decide(0 / 0, TRAINER[2].level, 2, TRAINER[2].cost).kind, "buy")
	end)
end
