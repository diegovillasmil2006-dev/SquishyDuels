--!strict
-- GripController_Test: unit tests for StarterPlayerScripts.Client.Controllers.GripController (Part 5, the pure
-- helpers). Server only (ServerStorage.UnitTest). Edit mode: init() / start() are not called (no LocalPlayer, no UI).
-- Contract (DESIGN §17.3.4, §17.5, §17.7, §17.10):
--   * normalize(raw): the StateDelta `grip` field as the client uses it; nil when missing or malformed; the total is
--     floored and clamped to [0, maxGrip]; a timer needs a finite value and at;
--   * slow training is gone (build plan Phase 6): no popup helpers (afkGain, capsuleGrip) and no bank line
--     (afkBankText); so are the trainers (Phase 6): no trainer card (trainerCardState), no upgrade badge and no
--     trainer goal, and an old save's trainer is not part of the view;
--   * gripChange: the first grip state and every full state (a profile recovered after OFFLINE) are a silent baseline
--     (fireLevel only for the first state or a moved level); a level-up after it fires the level (and pops it);
--   * shouldShowIdleCard(t): LocalPlayer.Idled's t >= Config.Grip.idleReminderSeconds (900);
--   * the giant pads and Jelly gates are gone (build plan Phase 6): no waypointTarget, padPerks, pad cards, unlock
--     waypoint, pad goal or LevelChanged (WorldBinder's level source);
--   * restedChip: "Double Grip: about {minutes} min" (nil while empty), refilled to the given server time with
--     SqueezeLimit;
--   * cardModel: the HUD card texts (grip.hudLevel, the rank alone for the foam card's title, grip.hudBar /
--     grip.hudMax, the bar fraction = have / need, the same numbers grip.hudBar shows (foam fix, user decision
--     2026-10-09), the next goal in the §17.7 order (Batch 1: a capsule buy first when capsules are given; then the
--     next rank, then max);
--   * goalId / shouldToastGoal: on the compact layout a new goal is toasted once per session, never the first one;
--   * Part 8: the compact card's touch height and width are tested in HudFormat_Test. (headerLayout went with the
--     panel's Close-only header row, foam fix; scrollDelta went with the pad cards' Show me buttons, Phase 6.)
--   * Foam fix 2: cardModel's cardGoal (the regular card's short goal line, grip.hudGoal*); panelLayout (the panel and
--     the Close hanging above it are centred together, so Close stays on the screen).
--   * Foam fix 3: panelLayout gives the panel its whole height share back (fix 2 took Close's hang out of it, and on a
--     phone no pad card showed); it shrinks only to keep Close's top PANEL.edge inside the screen. introShown: the
--     panel's intro line hides on the compact layout.
--   * UI FINAL R4 (H:82-90, H:707): the bare row's chip, cardModel.boost "2x ~{minutes} min" (hud.gripBoost, FD3; nil
--     while Double Grip is empty, like the panel's chip); shouldSquash: the row squashes for Grip gained after the
--     silent baseline only.
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

	local function view(total: number, rested: number?): any
		return {
			total = total,
			rested = if rested then { value = rested, at = NOW } else nil,
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

	t.test("normalize clamps the total, keeps finite timers and drops an old save's trainer and afk", function()
		local v = GripController.normalize({
			total = 1234.9,
			trainer = 3.7,
			rested = { value = 600, at = NOW },
			afk = { value = 0 / 0, at = NOW },
		})
		expect.deepEqual(v, { total = 1234, rested = { value = 600, at = NOW } })
		expect.equal(GripController.normalize({ total = -5 }).total, 0)
		expect.equal(GripController.normalize({ total = GRIP.maxGrip * 10 }).total, GRIP.maxGrip)
		-- Phase 6: an old save's slow-training bank is not part of the view.
		expect.equal((GripController.normalize({ total = 0, afk = { value = 60, at = NOW } }) :: any).afk, nil)
	end)

	-- Slow training and the trainers are gone (build plan Phase 6) ----------------------------------------------------

	t.test("no slow-training popup or bank line any more", function()
		for _, name in { "afkGain", "capsuleGrip", "afkBankText" } do
			expect.equal((GripController :: any)[name], nil)
		end
	end)

	t.test("no trainer card, upgrade badge or trainer goal any more; the TrainerUpgrade remote is gone", function()
		expect.equal(Remotes.SPEC.TrainerUpgrade, nil)
		expect.equal((GripController :: any).trainerCardState, nil)
		for level = 1, GRIP.maxLevel do
			local model = GripController.cardModel(view(GRIP.LevelTotals[level]), NOW)
			expect.equal((model :: any).badge, nil)
			local key = model.goalKey
			if key ~= "grip.goalRank" and key ~= "grip.goalMax" then
				error(`Lv {level}: the goal is {tostring(key)}`)
			end
		end
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

	t.test("a full state after the baseline (a profile recovered after OFFLINE) is silent: no popup", function()
		-- OFFLINE defaults (total 0, Lv 1), then the real profile is swapped in with a total past several levels.
		local total = GRIP.LevelTotals[30]
		local level = GripMath.levelFor(total)
		expect.truthy(level > 1)
		local change = GripController.gripChange(true, true, 0, total, 1, level)
		expect.deepEqual(change, { baseline = true, fireLevel = true })
		-- A full state that keeps the level changes nothing visible either.
		expect.deepEqual(GripController.gripChange(true, true, 100, 150, 1, 1), { baseline = true, fireLevel = false })
	end)

	t.test("an earned rise changes nothing visible, and a level-up fires the level (no waypoint, Phase 6)", function()
		local rise = GripController.gripChange(true, false, 100, 150, 1, 1)
		expect.deepEqual(rise, { baseline = false, fireLevel = false })
		local before = GRIP.LevelTotals[5] - 1
		local after = GRIP.LevelTotals[5]
		local levelUp = GripController.gripChange(true, false, before, after, 4, 5)
		expect.deepEqual(levelUp, { baseline = false, fireLevel = true })
		-- A drop (never earned) starts nothing.
		expect.deepEqual(
			GripController.gripChange(true, false, 150, 100, 1, 1),
			{ baseline = false, fireLevel = false }
		)
	end)

	t.test("the level label pops only for a level reached after the silent baseline (§18.5.1 A9)", function()
		local padLevel = 5 -- any level above 1
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

	-- The giant pads and Jelly gates are gone (build plan Phase 6) ---------------------------------------------------

	t.test("no pad waypoints, pad perks or LevelChanged (WorldBinder's level source) any more", function()
		for _, name in { "waypointTarget", "padPerks", "LevelChanged" } do
			expect.equal((GripController :: any)[name], nil)
		end
	end)

	-- Timers ---------------------------------------------------------------------------------------------------------

	t.test("the Double Grip chip shows whole minutes and hides while empty", function()
		local full = GRIP.Rested.burst
		local fullMinutes = GripMath.restedMinutes(full)
		expect.equal(fullMinutes, 9) -- minutes of holding (Hold.repeatSeconds 0.45 s per squeeze)
		expect.equal(GripController.restedChip(view(0, full), NOW), s("grip.restedChip", { minutes = 9 }))
		expect.equal(GripController.restedChip(view(0, 0), NOW), nil)
		expect.equal(GripController.restedChip(view(0), NOW), nil)
		-- It refills with time (4 points a minute): one minute after empty -> 4 points -> about 1 min.
		expect.equal(GripController.restedChip(view(0, 0), NOW + 60), s("grip.restedChip", { minutes = 1 }))
		-- It never goes above the burst.
		expect.equal(GripController.restedChip(view(0, full), NOW + 86400), s("grip.restedChip", { minutes = 9 }))
	end)

	-- HUD card -------------------------------------------------------------------------------------------------------

	t.test("UI FINAL R4: the bare row's Double Grip chip reads 2x ~{minutes} min, gone while it is empty", function()
		local full = GripController.cardModel(view(0, GRIP.Rested.burst), NOW)
		expect.equal(full.boost, s("hud.gripBoost", { minutes = 9 }))
		expect.equal(GripController.cardModel(view(0, 0), NOW).boost, nil)
		expect.equal(GripController.cardModel(view(0), NOW).boost, nil)
		-- The same minutes as the panel's chip, refilled with time.
		local later = GripController.cardModel(view(0, 0), NOW + 60)
		expect.equal(later.boost, s("hud.gripBoost", { minutes = 1 }))
		expect.equal(later.chip, s("grip.restedChip", { minutes = 1 }))
	end)

	t.test("UI FINAL R4 (H:707): the row squashes for Grip gained after the silent baseline only", function()
		local first = GripController.gripChange(false, false, nil, 500, nil, 1)
		expect.falsy(GripController.shouldSquash(first, nil, 500))
		local full = GripController.gripChange(true, true, 100, 500, 1, 1)
		expect.falsy(GripController.shouldSquash(full, 100, 500))
		local rise = GripController.gripChange(true, false, 100, 150, 1, 1)
		expect.truthy(GripController.shouldSquash(rise, 100, 150))
		local drop = GripController.gripChange(true, false, 150, 100, 1, 1)
		expect.falsy(GripController.shouldSquash(drop, 150, 100))
		expect.falsy(GripController.shouldSquash(rise, 150, 150))
	end)

	t.test("a new player's card: Lv 1, the bar toward Lv 2 and Firm Grip as the next goal", function()
		local model = GripController.cardModel(view(0, GRIP.Rested.burst), NOW)
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
		expect.equal(model.goalKey, "grip.goalRank")
		expect.equal(model.goal, s("grip.goalRank", { rank = s("grip.rank.firm"), level = 10 }))
	end)

	t.test("the bar fills with the numbers it shows: have / need (user decision 2026-10-09)", function()
		-- Lv 2 spans 1,000 .. 1,700 (spec 2026-10-12 totals): 1,350 reads "1,350 / 1,700" and fills 79% (not the 50%
		-- share of the level).
		local model = GripController.cardModel(view(1350), NOW)
		expect.equal(model.level, 2)
		expect.near(model.fraction, 1350 / 1700, 1e-9)
		expect.equal(model.barText, s("grip.hudBar", { have = "1,350", need = "1,700" }))
		-- The design's example: 42,000 / 66,000 is about two thirds full, whatever level that is.
		local example = GripController.cardModel(view(42000), NOW)
		local need = GripMath.progress(42000).need
		expect.near(example.fraction, 42000 / need, 1e-9)
		expect.equal(example.barText, s("grip.hudBar", { have = Format.coins(42000), need = Format.coins(need) }))
		-- Right at a level's start the bar is not empty (the old share of the level read 0 there).
		local start = GripController.cardModel(view(GRIP.LevelTotals[3]), NOW)
		expect.near(start.fraction, GRIP.LevelTotals[3] / GRIP.LevelTotals[4], 1e-9)
		expect.truthy(start.fraction > 0)
	end)

	t.test("the next unlock is the next rank", function()
		-- Lv 12: Strong Grip at Lv 20.
		local model = GripController.cardModel(view(GRIP.LevelTotals[12]), NOW)
		expect.equal(model.level, 12)
		expect.equal(model.goalKey, "grip.goalRank")
		expect.equal(model.goal, s("grip.goalRank", { rank = s("grip.rank.strong"), level = 20 }))
	end)

	t.test("the max level shows grip.hudMax, a full bar and grip.goalMax", function()
		local model = GripController.cardModel(view(GRIP.LevelTotals[GRIP.maxLevel]), NOW)
		expect.equal(model.level, GRIP.maxLevel)
		expect.equal(model.levelText, s("grip.hudLevel", { level = GRIP.maxLevel, rank = rankName(GRIP.maxLevel) }))
		expect.equal(model.rankText, rankName(GRIP.maxLevel))
		expect.equal(model.barText, s("grip.hudMax"))
		expect.near(model.fraction, 1)
		expect.equal(model.goal, s("grip.goalMax"))
	end)

	t.test("compact layout: each new goal is toasted once, never the session's first one", function()
		local model = GripController.cardModel(view(0), NOW)
		local id = GripController.goalId(model)
		expect.equal(id, "grip.goalRank|" .. model.goal)
		expect.equal(GripController.goalId({ goalKey = nil, goal = nil } :: any), nil)
		local seen: { [string]: boolean } = {}
		expect.falsy(GripController.shouldToastGoal(seen, id, true, true)) -- the baseline
		expect.truthy(GripController.shouldToastGoal(seen, id, true, false))
		expect.falsy(GripController.shouldToastGoal(seen, id, false, false)) -- regular shows it on the card
		expect.falsy(GripController.shouldToastGoal(seen, nil, true, false))
		seen[id :: string] = true
		expect.falsy(GripController.shouldToastGoal(seen, id, true, false)) -- already toasted this session
		-- A different goal (Lv 12: the next rank after Firm Grip) is new.
		local later = GripController.cardModel(view(GRIP.LevelTotals[12]), NOW)
		expect.truthy(GripController.shouldToastGoal(seen, GripController.goalId(later), true, false))
	end)

	-- Foam fix 2 (2026-10-09): the regular card's goal line is a short form of the same goal ("Next: Firm Grip at Lv
	-- 10"), so it keeps to one line; the panel and the compact layout's toast keep the full text (goal / goalKey).
	t.test(
		"the HUD card's goal line is the short form of the goal; the panel and the toast keep the full text",
		function()
			local rank = GripController.cardModel(view(GRIP.LevelTotals[5]), NOW)
			expect.equal(rank.cardGoal, s("grip.hudGoalRank", { rank = s("grip.rank.firm"), level = 10 }))
			-- The max level keeps its own line.
			local max = GripController.cardModel(view(GRIP.LevelTotals[GRIP.maxLevel]), NOW)
			expect.equal(max.cardGoal, max.goal)
			-- Every short form of every rank goal: no "Grip Lv" (the card is the Grip card) and at most 30
			-- characters (Reading: in Studio a 28-character goal line took 165 of the info column's 184 base px).
			local lines = {}
			for index = 2, #GRIP.Ranks do
				local row = GRIP.Ranks[index]
				table.insert(lines, s("grip.hudGoalRank", { rank = s("grip.rank." .. row.key), level = row.level }))
			end
			-- Batch 1 #7a: the capsule lines at the widest Format.coins forms that keep to one line (99,999 / 999.9K /
			-- 99.99M / 999B / 2.90Qa; capsule prices end at 2.9Qa). A 100.00M .. 999.99M price makes 31-32 characters
			-- and may take a second line, which the card's height plan holds (HudFormat.worstCaseTexts gripGoal).
			for _, n in { 99_999, 999_999, 99_999_999, 999e9, 2.9e15 } do
				local coins = Format.coins(n)
				table.insert(lines, s("grip.hudGoalCapsule", { slot = 4, have = coins, need = coins }))
			end
			table.insert(lines, s("grip.goalCapsuleReady", { slot = 4 }))
			table.insert(lines, s("grip.goalUnlockReady", { slot = 4 }))
			for _, line in lines do
				expect.falsy(string.find(line, "Grip Lv", 1, true))
				if (utf8.len(line) or #line) > 30 then
					error("the card's goal line is too long for one line: " .. line)
				end
			end
		end
	)

	t.test("goalArgs gives the rank name and the level", function()
		local args = GripController.goalArgs({
			kind = "rank",
			textKey = "grip.goalRank",
			nameKey = "grip.rank.firm",
			index = 2,
			level = 10,
		})
		expect.equal(args.rank, s("grip.rank.firm"))
		expect.equal(args.level, 10)
		expect.equal(args.pad, nil) -- Phase 6: no pad goal any more
		expect.equal(args.trainer, nil) -- Phase 6: no trainer goal any more
		local maxArgs = GripController.goalArgs({ kind = "max", textKey = "grip.goalMax" })
		expect.equal(maxArgs.rank, nil)
		expect.equal(maxArgs.coins, nil)
		expect.equal(maxArgs.slot, nil)
		expect.equal(maxArgs.have, nil)
		-- Batch 1 #7a: a capsule goal's {slot}, {level} and its Coins as {have} / {need}.
		local capsuleArgs = GripController.goalArgs({
			kind = "capsule",
			textKey = "grip.goalCapsule",
			slot = 2,
			level = 5,
			have = 1234,
			need = 99_999,
		})
		expect.equal(capsuleArgs.slot, 2)
		expect.equal(capsuleArgs.level, 5)
		expect.equal(capsuleArgs.have, Format.coins(1234))
		expect.equal(capsuleArgs.need, Format.coins(99_999))
	end)

	t.test("Batch 1: the goal names the capsule buy first; its toast id ignores the Coins", function()
		local capsules = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } }
		local saving = GripController.cardModel(view(0), NOW, capsules, 120)
		local have, need = Format.coins(120), Format.coins(1_000)
		expect.equal(saving.goalKey, "grip.goalCapsule")
		expect.equal(saving.goal, s("grip.goalCapsule", { slot = 1, level = 2, have = have, need = need }))
		expect.equal(saving.cardGoal, s("grip.hudGoalCapsule", { slot = 1, have = have, need = need }))
		local more = GripController.cardModel(view(0), NOW, capsules, 480)
		expect.equal(GripController.goalId(more), GripController.goalId(saving))
		local ready = GripController.cardModel(view(0), NOW, capsules, 1_000)
		expect.equal(ready.goal, s("grip.goalCapsuleReady", { slot = 1 }))
		expect.equal(ready.cardGoal, ready.goal)
		expect.truthy(GripController.goalId(ready) ~= GripController.goalId(saving))
		expect.equal(GripController.cardModel(view(0), NOW, nil, 120).goalKey, "grip.goalRank") -- no capsules: as before
		-- An unlock only with a spare squishy in `owned` (Lv 5 -> 6 costs 3,200; Capsule 2 opens for 2,500).
		local five = { slots = 1, list = { { level = 5, squishyId = "kitty_bread" } } }
		expect.equal(GripController.cardModel(view(0), NOW, five, 2_600).goalKey, "grip.goalCapsule")
		local owned = { kitty_bread = { at = 1, src = "shop" }, toast = { at = 2, src = "shop" } }
		expect.equal(GripController.cardModel(view(0), NOW, five, 2_600, owned).goalKey, "grip.goalUnlockReady")
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

	-- Foam fix 3: on a phone the intro line ("Squeezing trains your Grip. …") hides (it pushed the pad cards, gone
	-- since Phase 6, under the fold).
	t.test("introShown: the Grip panel's intro line shows on regular screens, not on the compact layout", function()
		expect.equal(GripController.introShown("regular"), true)
		expect.equal(GripController.introShown("compact"), false)
	end)

	-- UI FINAL R9 (G9.13, UD8): the level-up show plays for a level that rose after the silent baseline (and then the
	-- server's grip.levelUp toast is dropped: NotifyController.present); never for a load or a level that did not rise.
	t.test("levelUpShow: only a level that rose after the baseline plays the show", function()
		local before = GRIP.LevelTotals[5] - 1
		local after = GRIP.LevelTotals[5]
		local earned = GripController.gripChange(true, false, before, after, 4, 5)
		expect.equal(GripController.levelUpShow(earned, 4, 5), true)
		local loaded = GripController.gripChange(false, false, nil, after, nil, 5)
		expect.equal(GripController.levelUpShow(loaded, nil, 5), false)
		local full = GripController.gripChange(true, true, before, after, 4, 5)
		expect.equal(GripController.levelUpShow(full, 4, 5), false)
		local same = GripController.gripChange(true, false, 100, 150, 1, 1)
		expect.equal(GripController.levelUpShow(same, 1, 1), false)
	end)
end
