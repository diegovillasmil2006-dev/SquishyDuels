--!strict
-- GripController_Test: unit tests for StarterPlayerScripts.Client.Controllers.GripController (Part 5, the pure
-- helpers; Part 7, the trainer card). Server only (ServerStorage.UnitTest). Edit mode: init() / start() are not called (no LocalPlayer, no UI).
-- Contract (DESIGN §17.3.4, §17.3.6, §17.5, §17.7, §17.10):
--   * normalize(raw): the StateDelta `grip` field as the client uses it; nil when missing or malformed; the total is
--     floored and clamped to [0, maxGrip], the trainer to [1, #Trainer]; a timer needs a finite value and at;
--   * afkGain(old, new, explained): the Grip rise no SqueezeResult explains (the slow-training popup), never negative;
--   * gripChange: the first grip state and every full state (a profile recovered after OFFLINE) are a silent baseline
--     (no popup check, no waypoint; LevelChanged only for the first state or a moved level); an earned rise starts the
--     popup check and a level-up points the waypoint at the best pad it opened;
--   * shouldShowIdleCard(t): LocalPlayer.Idled's t >= Config.Grip.idleReminderSeconds (900);
--   * waypointTarget(tier): the Foam Mats' "squeeze" waypoint, "<key>Pad" for a giant pad, nil for an unknown tier;
--   * padPerks(pad): a pad card's perks line; the Foam Mats give no boost (grip.padPerksBase, spec 2026-10-11 §5:
--     the same Coins and Grip as anywhere), the giant pads grip.padPerks;
--   * restedChip / afkBankText: "Double Grip: about {minutes} min" (nil while empty) and "Slow training at full speed:
--     about {minutes} min left" (40 for a full bank), both refilled to the given server time with SqueezeLimit;
--   * cardModel: the HUD card texts (grip.hudLevel, the rank alone for the foam card's title, grip.hudBar /
--     grip.hudMax, the bar fraction = have / need, the same numbers grip.hudBar shows (foam fix, user decision
--     2026-10-09), the next goal in the §17.7 order with the §17.5 Dragon rule, the upgrade badge only while trainers can
--     be bought);
--   * goalId / shouldToastGoal: on the compact layout a new goal is toasted once per session, never the first one;
--   * trainerCardState (Part 7, §17.5): maxed (grip.trainerMax), Locked (grip.trainerNeedLevel), need Coins
--     (grip.trainerNeedCoins with the missing amount, never a Coin Store link or Robux), upgrading, paused (profile not
--     ready or a save pending), ready; the current / next trainer lines and the grip.trainerBuy label at the Config
--     price; the TrainerUpgrade remote exists, so the live card shows the trainer lines and the badge.
--   * Part 8 (§11.4): scrollDelta (the panel's column follows a gamepad selection, with a margin). (headerLayout went
--     with the panel's Close-only header row, foam fix.) The compact card's touch height and width are tested in
--     HudFormat_Test.
--   * Foam fix 2: cardModel's cardGoal (the regular card's short goal line, grip.hudGoal*); panelLayout (the panel and
--     the Close hanging above it are centred together, so Close stays on the screen).
--   * Foam fix 3: panelLayout gives the panel its whole height share back (fix 2 took Close's hang out of it, and on a
--     phone no pad card showed); it shrinks only to keep Close's top PANEL.edge inside the screen. introShown: the
--     panel's intro line hides on the compact layout, so the first pad card peeks in under "Squeeze pads".
-- Strings are compared by value through the test's own Strings copy (the controller requires the real one).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local GripController = t.requireClient("Controllers/GripController")
	local Config = t.requireShared("Config")
	local Remotes = t.requireShared("Remotes")
	local Format = t.requireShared("Util/Format")
	local GripMath = t.requireShared("GripMath")
	local Strings = t.requireShared("Strings")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local expect = t.expect
	local GRIP = Config.Grip

	local function s(key: string, args: { [string]: any }?): string
		local template = Strings.resolve(key)
		assert(template ~= nil, `missing Strings key {key}`)
		return Strings.format(template, args)
	end

	local function rankName(level: number): string
		return s("grip.rank." .. GripMath.rankFor(level).key)
	end

	local NOW = 1_800_000_000 -- a server time on the GetServerTimeNow() / os.time() scale

	local function view(total: number, trainer: number?, rested: number?, afk: number?): any
		return {
			total = total,
			trainer = trainer or 1,
			rested = if rested then { value = rested, at = NOW } else nil,
			afk = if afk then { value = afk, at = NOW } else nil,
		}
	end

	-- normalize -------------------------------------------------------------------------------------------------

	t.test("normalize rejects a missing or malformed grip field", function()
		expect.equal(GripController.normalize(nil), nil)
		expect.equal(GripController.normalize(12), nil)
		expect.equal(GripController.normalize({}), nil)
		expect.equal(GripController.normalize({ total = 0 / 0 }), nil)
		expect.equal(GripController.normalize({ total = math.huge }), nil)
		expect.equal(GripController.normalize({ total = "12" }), nil)
	end)

	t.test("normalize clamps the total and the trainer, and keeps only finite timers", function()
		local v = GripController.normalize({
			total = 1234.9,
			trainer = 3.7,
			rested = { value = 600, at = NOW },
			afk = { value = 0 / 0, at = NOW },
		})
		expect.deepEqual(v, { total = 1234, trainer = 3, rested = { value = 600, at = NOW } })
		expect.equal(GripController.normalize({ total = -5 }).total, 0)
		expect.equal(GripController.normalize({ total = GRIP.maxGrip * 10 }).total, GRIP.maxGrip)
		expect.equal(GripController.normalize({ total = 0 }).trainer, 1) -- missing trainer = the free Foam Ball
		expect.equal(GripController.normalize({ total = 0, trainer = 0 }).trainer, 1)
		expect.equal(GripController.normalize({ total = 0, trainer = 99 }).trainer, #GRIP.Trainer)
	end)

	-- Slow-training popup ----------------------------------------------------------------------------------------

	t.test("afkGain is the part of a rise no SqueezeResult explains, never negative", function()
		expect.equal(GripController.afkGain(100, 137, 100), 37) -- a tick alone
		expect.equal(GripController.afkGain(100, 130, 130), 0) -- a squeeze explains all of it
		expect.equal(GripController.afkGain(100, 160, 130), 30) -- a squeeze, then a tick
		expect.equal(GripController.afkGain(100, 90, 0), 0)
		expect.equal(GripController.afkGain(100, 120, 50), 20) -- an old explanation below the start counts as none
	end)

	-- Grip state changes (§17.7 "Load-time level jumps") -------------------------------------------------------------

	t.test("the session's first grip state is a silent baseline that still sets the level", function()
		local level = GripMath.levelFor(12000)
		expect.deepEqual(
			GripController.gripChange(false, true, nil, 12000, nil, level),
			{ baseline = true, fireLevel = true }
		)
		expect.deepEqual(
			GripController.gripChange(false, false, nil, 12000, nil, level),
			{ baseline = true, fireLevel = true }
		)
	end)

	t.test(
		"a full state after the baseline (a profile recovered after OFFLINE) is silent: no popup, no waypoint",
		function()
			-- OFFLINE defaults (total 0, Lv 1), then the real profile is swapped in with a total past several pad levels.
			local total = GRIP.LevelTotals[GRIP.Pads[#GRIP.Pads].level]
			local level = GripMath.levelFor(total)
			expect.truthy(level > 1)
			local change = GripController.gripChange(true, true, 0, total, 1, level)
			expect.deepEqual(change, { baseline = true, fireLevel = true }) -- gates and signs still follow the new level
			-- A full state that keeps the level changes nothing visible either.
			expect.deepEqual(
				GripController.gripChange(true, true, 100, 150, 1, 1),
				{ baseline = true, fireLevel = false }
			)
		end
	)

	t.test("an earned rise starts the slow-training check, and a level-up opens the best pad's waypoint", function()
		local rise = GripController.gripChange(true, false, 100, 150, 1, 1)
		expect.deepEqual(rise, { baseline = false, fireLevel = false, afkFrom = 100 })
		local padLevel = GRIP.Pads[2].level
		local before = GRIP.LevelTotals[padLevel] - 1
		local after = GRIP.LevelTotals[padLevel]
		local levelUp = GripController.gripChange(true, false, before, after, padLevel - 1, padLevel)
		expect.deepEqual(levelUp, { baseline = false, fireLevel = true, afkFrom = before, waypointTier = 2 })
		-- A drop (never earned) starts nothing.
		expect.deepEqual(
			GripController.gripChange(true, false, 150, 100, 1, 1),
			{ baseline = false, fireLevel = false }
		)
	end)

	t.test("the level label pops only for a level reached after the silent baseline (§18.5.1 A9)", function()
		local padLevel = GRIP.Pads[2].level
		local before = GRIP.LevelTotals[padLevel] - 1
		local after = GRIP.LevelTotals[padLevel]
		-- The session's first state and a full state (loaded, not earned) never pop, even when the level moved.
		expect.falsy(GripController.shouldPopLevel(GripController.gripChange(false, false, nil, after, nil, padLevel)))
		expect.falsy(GripController.shouldPopLevel(GripController.gripChange(true, true, before, after, 1, padLevel)))
		-- An earned level-up pops; an earned rise inside a level does not.
		expect.truthy(
			GripController.shouldPopLevel(GripController.gripChange(true, false, before, after, padLevel - 1, padLevel))
		)
		expect.falsy(GripController.shouldPopLevel(GripController.gripChange(true, false, 100, 150, 1, 1)))
	end)

	-- Idle card ------------------------------------------------------------------------------------------------------

	t.test("the idle card waits for Config.Grip.idleReminderSeconds of LocalPlayer.Idled", function()
		local threshold = GRIP.idleReminderSeconds
		expect.equal(threshold, 900)
		expect.falsy(GripController.shouldShowIdleCard(threshold - 1))
		expect.truthy(GripController.shouldShowIdleCard(threshold))
		expect.truthy(GripController.shouldShowIdleCard(threshold + 30))
		expect.falsy(GripController.shouldShowIdleCard(0 / 0))
		expect.falsy(GripController.shouldShowIdleCard(120)) -- Idled's first event (about 2 minutes)
	end)

	-- Waypoints ------------------------------------------------------------------------------------------------------

	t.test("pad waypoints come from WorldLayout (Foam Mats: the squeeze waypoint)", function()
		expect.equal(GripController.waypointTarget(1), WorldLayout.waypoint("squeeze"))
		for tier = 2, #GRIP.Pads do
			local key = GRIP.Pads[tier].key
			local target = GripController.waypointTarget(tier)
			expect.truthy(target ~= nil)
			expect.equal(target, WorldLayout.waypoint(key .. "Pad"))
		end
		expect.equal(GripController.waypointTarget(#GRIP.Pads + 1), nil)
		expect.equal(GripController.waypointTarget(0), nil)
	end)

	t.test(
		"pad perks: the Foam Mats card says it gives no boost (spec 2026-10-11 §5); the others show theirs",
		function()
			expect.equal(GripController.padPerks(GRIP.Pads[1]), s("grip.padPerksBase"))
			for tier = 2, #GRIP.Pads do
				local pad = GRIP.Pads[tier]
				expect.equal(
					GripController.padPerks(pad),
					s("grip.padPerks", { coins = pad.coinBonus, mult = pad.gripPercent / 100 })
				)
			end
		end
	)

	-- Timers ---------------------------------------------------------------------------------------------------------

	t.test("the Double Grip chip shows whole minutes and hides while empty", function()
		local full = GRIP.Rested.burst
		local fullMinutes = GripMath.restedMinutes(full)
		expect.equal(fullMinutes, 9) -- minutes of holding (Hold.repeatSeconds 0.45 s per squeeze; every click pays)
		expect.equal(GripController.restedChip(view(0, 1, full), NOW), s("grip.restedChip", { minutes = 9 }))
		expect.equal(GripController.restedChip(view(0, 1, 0), NOW), nil)
		expect.equal(GripController.restedChip(view(0), NOW), nil)
		-- It refills with time (4 points a minute): one minute after empty -> 4 points -> about 1 min.
		expect.equal(GripController.restedChip(view(0, 1, 0), NOW + 60), s("grip.restedChip", { minutes = 1 }))
		-- It never goes above the burst.
		expect.equal(GripController.restedChip(view(0, 1, full), NOW + 86400), s("grip.restedChip", { minutes = 9 }))
	end)

	t.test("the slow-training bank line reads 40 minutes when full and refills with time", function()
		local full = GRIP.Afk.burst
		expect.equal(GripController.afkBankText(view(0, 1, nil, full), NOW), s("grip.afkBank", { minutes = 40 }))
		expect.equal(GripController.afkBankText(view(0, 1, nil, 0), NOW), s("grip.afkBank", { minutes = 0 }))
		local refilled = GripMath.afkMinutes(GRIP.Afk.perHour / 60 * 10) -- 10 minutes of refill
		expect.equal(
			GripController.afkBankText(view(0, 1, nil, 0), NOW + 600),
			s("grip.afkBank", { minutes = refilled })
		)
		expect.equal(GripController.afkBankText(view(0), NOW), nil)
	end)

	-- HUD card -------------------------------------------------------------------------------------------------------

	t.test("a new player's card: Lv 1, the bar toward Lv 2 and the Jelly Pad as the next goal", function()
		local model = GripController.cardModel(view(0, 1, GRIP.Rested.burst, GRIP.Afk.burst), NOW, {}, 0, false)
		expect.equal(model.level, 1)
		expect.equal(model.levelText, s("grip.hudLevel", { level = 1, rank = rankName(1) }))
		expect.equal(model.levelCompact, s("grip.hudLevelCompact", { level = 1, rank = rankName(1) }))
		-- Foam restyle: the regular card's title is the rank alone (the level shows on its level tile).
		expect.equal(model.rankText, rankName(1))
		expect.equal(
			model.barText,
			s("grip.hudBar", { have = Format.coins(0), need = Format.coins(GRIP.LevelTotals[2]) })
		)
		expect.near(model.fraction, 0)
		expect.equal(model.chip, s("grip.restedChip", { minutes = 9 })) -- holding minutes (Hold.repeatSeconds 0.45 s)
		expect.equal(model.goalKey, "grip.goalPad")
		expect.equal(model.goal, s("grip.goalPad", { pad = s("grip.pad.jelly"), level = GRIP.Pads[2].level }))
		expect.falsy(model.badge)
	end)

	t.test("the bar fills with the numbers it shows: have / need (user decision 2026-10-09)", function()
		-- Lv 2 spans 1,000 .. 2,500: 1,750 reads "1,750 / 2,500" and fills 70% (not the 50% share of the level).
		local model = GripController.cardModel(view(1750), NOW, {}, 0, false)
		expect.equal(model.level, 2)
		expect.near(model.fraction, 1750 / 2500, 1e-9)
		expect.equal(model.barText, s("grip.hudBar", { have = "1,750", need = "2,500" }))
		-- The design's example: 42,000 / 66,000 is about two thirds full, whatever level that is.
		local example = GripController.cardModel(view(42000), NOW, {}, 0, false)
		local need = GripMath.progress(42000).need
		expect.near(example.fraction, 42000 / need, 1e-9)
		expect.equal(example.barText, s("grip.hudBar", { have = Format.coins(42000), need = Format.coins(need) }))
		-- Right at a level's start the bar is not empty (the old share of the level read 0 there).
		local start = GripController.cardModel(view(GRIP.LevelTotals[3]), NOW, {}, 0, false)
		expect.near(start.fraction, GRIP.LevelTotals[3] / GRIP.LevelTotals[4], 1e-9)
		expect.truthy(start.fraction > 0)
	end)

	t.test("the next unlock is the lowest level ahead (a rank before a farther pad)", function()
		-- Lv 5 (the Jelly Pad is open): Firm Grip at Lv 10 comes before the Marshmallow Pad at Lv 15.
		local model = GripController.cardModel(view(GRIP.LevelTotals[5]), NOW, {}, 0, false)
		expect.equal(model.level, 5)
		expect.equal(model.goalKey, "grip.goalRank")
		expect.equal(model.goal, s("grip.goalRank", { rank = s("grip.rank.firm"), level = 10 }))
	end)

	t.test("the max level shows grip.hudMax, a full bar and grip.goalMax", function()
		local model = GripController.cardModel(view(GRIP.LevelTotals[GRIP.maxLevel]), NOW, {}, 0, false)
		expect.equal(model.level, GRIP.maxLevel)
		expect.equal(model.levelText, s("grip.hudLevel", { level = GRIP.maxLevel, rank = rankName(GRIP.maxLevel) }))
		expect.equal(model.rankText, rankName(GRIP.maxLevel))
		expect.equal(model.barText, s("grip.hudMax"))
		expect.near(model.fraction, 1)
		expect.equal(model.goal, s("grip.goalMax"))
	end)

	t.test("no trainer line and no badge until the TrainerUpgrade remote exists (Part 7)", function()
		-- Lv 3 with 1,000 Coins could buy the Sponge Ball, but trainers are not available yet.
		local model = GripController.cardModel(view(GRIP.LevelTotals[3]), NOW, {}, 1000, false)
		expect.falsy(model.badge)
		expect.truthy(model.goalKey ~= "grip.goalUpgrade" and model.goalKey ~= "grip.goalTrainer")
	end)

	t.test("with trainers available: a cheap upgrade is the goal and shows the badge", function()
		local sponge = GRIP.Trainer[2]
		local model = GripController.cardModel(view(GRIP.LevelTotals[sponge.level]), NOW, {}, sponge.cost, true)
		expect.truthy(model.badge)
		expect.equal(model.goalKey, "grip.goalUpgrade")
		expect.equal(
			model.goal,
			s("grip.goalUpgrade", { trainer = s("grip.trainer." .. sponge.key), coins = Format.coins(sponge.cost) })
		)
		-- One Coin short: no badge, no upgrade line.
		local short = GripController.cardModel(view(GRIP.LevelTotals[sponge.level]), NOW, {}, sponge.cost - 1, true)
		expect.falsy(short.badge)
		expect.truthy(short.goalKey ~= "grip.goalUpgrade")
	end)

	t.test(
		"the §17.5 Dragon rule: an expensive upgrade is only the goal once the top shop squishy is owned",
		function()
			-- Trainer 4 owned; the next one (Jelly Gripper, 25,000 > 5,000) needs Lv 15.
			local nextTrainer = GRIP.Trainer[5]
			expect.truthy(nextTrainer.cost > GRIP.goalUpgradeMaxCostWhileCollecting)
			local state = view(GRIP.LevelTotals[nextTrainer.level], 4)
			local topId = GripMath.topShopSquishyId()
			expect.truthy(topId ~= nil)
			local collecting = GripController.cardModel(state, NOW, {}, nextTrainer.cost, true)
			expect.truthy(collecting.badge) -- the badge still shows
			expect.truthy(collecting.goalKey ~= "grip.goalUpgrade")
			local owned = { [topId :: string] = { at = 0 } }
			local done = GripController.cardModel(state, NOW, owned, nextTrainer.cost, true)
			expect.equal(done.goalKey, "grip.goalUpgrade")
		end
	)

	t.test("compact layout: each new goal is toasted once, never the session's first one", function()
		local model = GripController.cardModel(view(0), NOW, {}, 0, false)
		local id = GripController.goalId(model)
		expect.equal(id, "grip.goalPad|" .. model.goal)
		expect.equal(GripController.goalId({ goalKey = nil, goal = nil } :: any), nil)
		local seen: { [string]: boolean } = {}
		expect.falsy(GripController.shouldToastGoal(seen, id, true, true)) -- the baseline
		expect.truthy(GripController.shouldToastGoal(seen, id, true, false))
		expect.falsy(GripController.shouldToastGoal(seen, id, false, false)) -- regular shows it on the card
		expect.falsy(GripController.shouldToastGoal(seen, nil, true, false))
		seen[id :: string] = true
		expect.falsy(GripController.shouldToastGoal(seen, id, true, false)) -- already toasted this session
		-- A different goal (Lv 5: the next rank) is new.
		local later = GripController.cardModel(view(GRIP.LevelTotals[5]), NOW, {}, 0, false)
		expect.truthy(GripController.shouldToastGoal(seen, GripController.goalId(later), true, false))
	end)

	-- Foam fix 2 (2026-10-09): the regular card's goal line is a short form of the same goal ("Next: Sponge Ball at Lv
	-- 3"), so a new player's first card has no line holding only "Grip Lv 3"; the panel and the compact layout's toast
	-- keep the full text (goal / goalKey).
	t.test(
		"the HUD card's goal line is the short form of the goal; the panel and the toast keep the full text",
		function()
			local sponge = GRIP.Trainer[2]
			local fresh = GripController.cardModel(view(0), NOW, {}, 0, true)
			expect.equal(fresh.goalKey, "grip.goalTrainer")
			local spongeArgs = { trainer = s("grip.trainer.sponge"), level = sponge.level }
			expect.equal(fresh.goal, s("grip.goalTrainer", spongeArgs))
			expect.equal(fresh.cardGoal, s("grip.hudGoalTrainer", spongeArgs))
			local pad = GripController.cardModel(view(0), NOW, {}, 0, false)
			expect.equal(pad.cardGoal, s("grip.hudGoalPad", { pad = s("grip.pad.jelly"), level = GRIP.Pads[2].level }))
			local rank = GripController.cardModel(view(GRIP.LevelTotals[5]), NOW, {}, 0, false)
			expect.equal(rank.cardGoal, s("grip.hudGoalRank", { rank = s("grip.rank.firm"), level = 10 }))
			-- The max level keeps its own line (the upgrade goal hides behind the Upgrade tab, so it keeps its text too).
			local max = GripController.cardModel(view(GRIP.LevelTotals[GRIP.maxLevel]), NOW, {}, 0, false)
			expect.equal(max.cardGoal, max.goal)
			local upgrade = GripController.cardModel(view(GRIP.LevelTotals[sponge.level]), NOW, {}, sponge.cost, true)
			expect.equal(upgrade.cardGoal, upgrade.goal)
			-- Every short form of every pad, trainer and rank goal: no "Grip Lv" (the card is the Grip card) and at most 30
			-- characters (Reading: in Studio a 28-character goal line took 165 of the info column's 184 base px).
			local lines = {}
			for tier = 2, #GRIP.Pads do
				local row = GRIP.Pads[tier]
				table.insert(lines, s("grip.hudGoalPad", { pad = s("grip.pad." .. row.key), level = row.level }))
			end
			for index = 2, #GRIP.Trainer do
				local row = GRIP.Trainer[index]
				table.insert(
					lines,
					s("grip.hudGoalTrainer", { trainer = s("grip.trainer." .. row.key), level = row.level })
				)
			end
			for index = 2, #GRIP.Ranks do
				local row = GRIP.Ranks[index]
				table.insert(lines, s("grip.hudGoalRank", { rank = s("grip.rank." .. row.key), level = row.level }))
			end
			for _, line in lines do
				expect.falsy(string.find(line, "Grip Lv", 1, true))
				if (utf8.len(line) or #line) > 30 then
					error("the card's goal line is too long for one line: " .. line)
				end
			end
		end
	)

	t.test("goalArgs gives the name under every placeholder and formats the Coins", function()
		local args = GripController.goalArgs({
			kind = "upgrade",
			textKey = "grip.goalUpgrade",
			nameKey = "grip.trainer.sponge",
			index = 2,
			level = 3,
			coins = 1000,
		})
		expect.equal(args.trainer, s("grip.trainer.sponge"))
		expect.equal(args.pad, s("grip.trainer.sponge"))
		expect.equal(args.level, 3)
		expect.equal(args.coins, "1,000")
		local maxArgs = GripController.goalArgs({ kind = "max", textKey = "grip.goalMax" })
		expect.equal(maxArgs.trainer, nil)
		expect.equal(maxArgs.coins, nil)
	end)

	-- Trainer card (Part 7, §17.5 / §17.7) ------------------------------------------------------------------------

	local TRAINER = GRIP.Trainer

	local function trainerName(index: number): string
		return s("grip.trainer." .. TRAINER[index].key)
	end

	local function readyStatus(savePending: boolean?): any
		return { status = "ready", persisted = true, savePending = savePending == true }
	end

	t.test("the TrainerUpgrade remote exists (Part 7), so the live card shows trainer lines and the badge", function()
		expect.truthy(Remotes.SPEC.TrainerUpgrade ~= nil)
		local spec = Remotes.SPEC.TrainerUpgrade
		expect.equal(spec.dir, "c2s")
		expect.equal(spec.kind, "RemoteFunction")
		expect.equal(#spec.args, 2) -- (targetLevel, expectedPrice): never a Grip amount
		local sponge = TRAINER[2]
		local model = GripController.cardModel(view(GRIP.LevelTotals[sponge.level]), NOW, {}, sponge.cost, true)
		expect.truthy(model.badge)
		expect.equal(model.goalKey, "grip.goalUpgrade")
	end)

	t.test("trainerCardState: nil without a Grip state", function()
		expect.equal(GripController.trainerCardState(nil, 1000, 5), nil)
	end)

	t.test("trainerCardState: the current and next trainer lines and the Upgrade label at the Config price", function()
		local card = GripController.trainerCardState(view(GRIP.LevelTotals[3], 1), 5000, 3)
		expect.equal(card.kind, "ready")
		expect.equal(card.trainer, 1)
		expect.equal(card.target, 2)
		expect.equal(card.cost, TRAINER[2].cost)
		expect.equal(card.missing, 0)
		expect.equal(card.reason, nil)
		expect.equal(card.nowText, s("grip.trainerNow", { trainer = trainerName(1), grip = TRAINER[1].gripPerSqueeze }))
		expect.equal(
			card.nextText,
			s("grip.trainerNext", { trainer = trainerName(2), grip = TRAINER[2].gripPerSqueeze })
		)
		expect.equal(card.buyText, s("grip.trainerBuy", { coins = Format.coins(TRAINER[2].cost) }))
		expect.equal(card.buyText, "Upgrade: 1,000 Coins")
		expect.equal(card.maxText, nil)
	end)

	t.test("trainerCardState: Locked below the next trainer's Grip level (grip.trainerNeedLevel)", function()
		local nextLevel = TRAINER[2].level
		local card = GripController.trainerCardState(view(0, 1), 999999, nextLevel - 1)
		expect.equal(card.kind, "locked")
		expect.equal(card.reason, s("grip.trainerNeedLevel", { level = nextLevel }))
		-- The gate is the next trainer's, not the owned one's: trainer 4 owned, the Jelly Gripper needs Lv 15.
		local later = GripController.trainerCardState(view(0, 4), 999999, TRAINER[5].level - 1)
		expect.equal(later.kind, "locked")
		expect.equal(later.reason, s("grip.trainerNeedLevel", { level = TRAINER[5].level }))
		local open = GripController.trainerCardState(view(0, 4), 999999, TRAINER[5].level)
		expect.equal(open.kind, "ready")
	end)

	t.test("trainerCardState: need Coins shows the missing amount, never a Coin Store link or Robux", function()
		local cost = TRAINER[2].cost
		local card = GripController.trainerCardState(view(0, 1), cost - 600, TRAINER[2].level)
		expect.equal(card.kind, "needCoins")
		expect.equal(card.missing, 600)
		expect.equal(card.reason, s("grip.trainerNeedCoins", { coins = "600" }))
		local broke = GripController.trainerCardState(view(0, 1), 0 / 0, TRAINER[2].level)
		expect.equal(broke.missing, cost)
		-- §17.2 rule 4: no Robux upsell and no Coin Store link anywhere on the card.
		for _, c in { card, broke } do
			for _, value in { c.nowText, c.nextText, c.buyText, c.reason } do
				expect.falsy(string.find(string.lower(value :: string), "robux", 1, true))
				-- No link to the shop (the Coin Store lives there): the word "shop" never appears.
				expect.falsy(string.find(string.lower(value :: string), string.lower(s("hud.nav.shop")), 1, true))
			end
		end
	end)

	t.test("trainerCardState: maxed shows grip.trainerMax and no next trainer", function()
		local card = GripController.trainerCardState(view(GRIP.LevelTotals[GRIP.maxLevel], #TRAINER), 0, GRIP.maxLevel)
		expect.equal(card.kind, "max")
		expect.equal(card.trainer, #TRAINER)
		expect.equal(card.target, nil)
		expect.equal(card.cost, 0)
		expect.equal(card.nextText, nil)
		expect.equal(card.buyText, nil)
		expect.equal(card.maxText, s("grip.trainerMax"))
		expect.equal(
			card.nowText,
			s("grip.trainerNow", { trainer = trainerName(#TRAINER), grip = TRAINER[#TRAINER].gripPerSqueeze })
		)
	end)

	t.test("trainerCardState: upgrading while a TrainerUpgrade runs (it wins over every other state)", function()
		local ready = GripController.trainerCardState(view(0, 1), 5000, 3, { pending = true, status = readyStatus() })
		expect.equal(ready.kind, "upgrading")
		local locked = GripController.trainerCardState(view(0, 1), 0, 1, { pending = true })
		expect.equal(locked.kind, "upgrading")
		-- Maxed stays maxed (nothing can be running).
		expect.equal(GripController.trainerCardState(view(0, #TRAINER), 0, 1, { pending = true }).kind, "max")
	end)

	t.test("trainerCardState: paused while the profile is not ready or a save is pending (§3.11)", function()
		local level = TRAINER[2].level
		local saving = GripController.trainerCardState(view(0, 1), 5000, level, { status = readyStatus(true) })
		expect.equal(saving.kind, "blocked")
		expect.equal(saving.reason, Strings.reasonText("trainer.paused"))
		local loading = GripController.trainerCardState(view(0, 1), 5000, level, {
			status = { status = "loading", persisted = true, savePending = false },
		})
		expect.equal(loading.reason, Strings.common.loading)
		local offline = GripController.trainerCardState(view(0, 1), 5000, level, {
			status = { status = "offline", persisted = false, savePending = false },
		})
		expect.equal(offline.reason, Strings.reasonText("data.offline"))
		local readOnly = GripController.trainerCardState(view(0, 1), 5000, level, {
			status = { status = "readonly", persisted = false, savePending = false },
		})
		expect.equal(readOnly.reason, Strings.reasonText("data.readOnly"))
		-- Locked wins over paused (the level gate is the reason that lasts).
		local both = GripController.trainerCardState(view(0, 1), 5000, 1, { status = readyStatus(true) })
		expect.equal(both.kind, "locked")
		-- A ready profile with no pending save: ready.
		expect.equal(GripController.trainerCardState(view(0, 1), 5000, level, { status = readyStatus() }).kind, "ready")
	end)

	t.test("trainerCardState agrees with GripMath.upgradeDecision on the next trainer (the server's checks)", function()
		for owned = 1, #TRAINER - 1 do
			local nextDef = TRAINER[owned + 1]
			for _, level in { nextDef.level - 1, nextDef.level } do
				local decision = GripMath.upgradeDecision({ trainer = owned, level = level }, owned + 1, nextDef.cost)
				local card = GripController.trainerCardState(view(0, owned), nextDef.cost, level)
				if decision.kind == "buy" then
					expect.equal(card.kind, "ready")
				else
					expect.equal(decision.reason, "trainer.locked")
					expect.equal(card.kind, "locked")
				end
			end
		end
	end)

	-- Part 8 (§11.4, §17.7): the panel's gamepad scroll and header ---------------------------------------------------

	t.test("scrollDelta: a selected item scrolls into the window with a margin; 0 when it already shows", function()
		-- Window 100..300, margin 10: the item may sit in 110..290.
		expect.equal(GripController.scrollDelta(150, 200, 100, 300, 10), 0)
		expect.equal(GripController.scrollDelta(110, 290, 100, 300, 10), 0) -- exactly inside the margin
		expect.equal(GripController.scrollDelta(320, 372, 100, 300, 10), 82) -- below: scroll down by 372 - 290
		expect.equal(GripController.scrollDelta(40, 92, 100, 300, 10), -70) -- above: scroll up by 110 - 40
		expect.equal(GripController.scrollDelta(285, 337, 100, 300, 10), 47) -- partly below
		-- An item taller than the window aligns its top (never a back-and-forth).
		expect.equal(GripController.scrollDelta(400, 800, 100, 300, 10), 290)
		-- A margin larger than half the window falls back to the bare window.
		expect.equal(GripController.scrollDelta(150, 200, 100, 300, 500), 0)
		expect.equal(GripController.scrollDelta(320, 372, 100, 300, 500), 72)
		-- A negative margin counts as 0; non-finite input never jumps.
		expect.equal(GripController.scrollDelta(320, 372, 100, 300, -5), 72)
		expect.equal(GripController.scrollDelta(0 / 0, 372, 100, 300, 10), 0)
		expect.equal(GripController.scrollDelta(320, math.huge, 100, 300, 10), 0)
	end)

	-- Foam fix 2 (2026-10-09): the panel and what hangs above its top edge are centred together, like Quests and
	-- Settings, so Close stays on the screen (the layout audit saw it 1-4 px above the top on phones). Foam fix 3: the
	-- panel keeps its whole height share (fix 2 took Close's hang out of it and on a phone the pad cards went under
	-- the fold); it gives up height only to keep Close's top PANEL.edge inside the screen.
	t.test(
		"panelLayout: the panel keeps its height share, centred with the Close above it; Close stays inside the screen",
		function()
			local PANEL = GripController.PANEL
			local above = Config.UI.Touch.closeButton / 2
			expect.truthy(PANEL.edge >= 3) -- Close's raised content sits 3 base above its top
			-- SD_Modal's size (px) and UI scale: the phone emulator at 667×375 and 844×390 as measured (296 and 311 px
			-- under the 58 px top bar inset) and as estimated (317, 332), PCs.
			local cases = {
				{ screen = Vector2.new(667, 296), scale = 0.85 },
				{ screen = Vector2.new(844, 311), scale = 0.85 },
				{ screen = Vector2.new(667, 317), scale = 0.85 },
				{ screen = Vector2.new(844, 332), scale = 0.85 },
				{ screen = Vector2.new(1280, 662), scale = 0.85 },
				{ screen = Vector2.new(1920, 1022), scale = 1.25 },
			}
			for _, case in cases do
				local layout = GripController.panelLayout(case.screen, case.scale, above)
				local canvas = case.screen / case.scale
				local label = `{case.screen.X}x{case.screen.Y}: {layout.width} x {layout.height} down {layout.shift}`
				local top = canvas.Y / 2 + layout.shift - layout.height / 2
				local bottom = canvas.Y / 2 + layout.shift + layout.height / 2
				local closeTop = top - above
				-- The panel alone is the height share of the screen; with Close it is centred (within the 1 px a whole
				-- offset rounds).
				expect.near(layout.height, canvas.Y * PANEL.heightShare, 1e-3)
				expect.near(closeTop, canvas.Y - bottom, 1)
				-- Close's top stays PANEL.edge inside the screen (half a px for the rounded offset).
				if not (closeTop >= PANEL.edge - 0.5) then
					error("Close is too near the screen's top: " .. label)
				end
				expect.truthy(bottom <= canvas.Y)
				expect.equal(layout.shift, math.floor(layout.shift))
				expect.truthy(layout.width <= PANEL.maxWidth)
			end
			-- A taller header tab (a large text size) moves the panel down by half of it; nothing hanging changes nothing.
			local screen, scale = Vector2.new(844, 311), 0.85
			local tall = GripController.panelLayout(screen, scale, 30)
			expect.near(tall.height, screen.Y / scale * PANEL.heightShare, 1e-3)
			expect.equal(tall.shift, 15)
			local flat = GripController.panelLayout(screen, scale, 0)
			expect.near(flat.height, screen.Y / scale * PANEL.heightShare, 1e-3)
			expect.equal(flat.shift, 0)
			-- So much hangs above it that the share would push Close past the edge: the panel gives up just enough.
			local cramped = GripController.panelLayout(screen, scale, 45)
			local canvasY = screen.Y / scale
			expect.near(cramped.height, canvasY - 45 - 2 * PANEL.edge, 1e-3)
			local crampedTop = canvasY / 2 + cramped.shift - cramped.height / 2 - 45
			expect.truthy(crampedTop >= PANEL.edge - 0.5)
			-- No size yet (the panel is built before SD_Modal is drawn): the fallback, never an error.
			local boot = GripController.panelLayout(Vector2.zero, 1, above)
			expect.equal(boot.width, PANEL.maxWidth)
			expect.truthy(boot.height > 0)
		end
	)

	-- Foam fix 3: on a phone the intro line ("Every squeeze trains your Grip. …") hides, so the first pad card's top
	-- shows under "Squeeze pads" (with it, the column ended at the heading and nothing showed that it scrolls on).
	t.test("introShown: the Grip panel's intro line shows on regular screens, not on the compact layout", function()
		expect.equal(GripController.introShown("regular"), true)
		expect.equal(GripController.introShown("compact"), false)
	end)
end
