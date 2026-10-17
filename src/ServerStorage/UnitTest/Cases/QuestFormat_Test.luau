--!strict
-- QuestFormat_Test: StarterPlayerScripts.Client.UI.QuestFormat (the quest board and the result panel's quest names).
-- Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §6.8, §11.6):
--   * a daily card: the QuestDefs text (goal and squishy name filled in), "3/5" progress with its bar, "+1,500 Coins",
--     and its state In progress / Claim / Claimed; Phase 5 (progression spec 2026-10-12 §9): a quest's or starter
--     task's reward is its squeezes × the player's squeeze value (CapsuleMath.squeezeValue of ctx.capsules; a new
--     player's 10 without them), the Coins the server pays at claim time (card.reward is those Coins);
--   * Swap on unfinished daily quests while a free swap is left (none once used, none on a finished quest);
--   * the Equip shortcut when the quest's squishy is owned but not equipped (and the quest is unfinished);
--   * a Starter section with every QuestDefs starter task (progress from profile.starter), hidden once all are claimed;
--   * the reset line "Resets in {clock}" to 00:00 UTC (UI FINAL R8, lib:306: "{h}h {MM}m", "m:ss" in the last
--     hour); the empty sentence when the day has no quest;
--   * namer(quests) names daily quests from the state and starter tasks from QuestDefs, nil otherwise;
--   * Part 8 (§11.2): the Quests panel's scrolling body keeps the whole panel within 86% of the screen height at
--     667×375, 1280×720 and 1920×1080, Medium and the largest text, never under one touch target; short boards show
--     whole. Foam UI (2026-10-09): the chrome counts the header tab and Close hanging above the panel.
--   * Batch 3 (review #10): "Top Wins This Week" (the topWins state): "Checking the board…" until the first read,
--     "The board is taking a break…" while no read works, the ranked lines "1. Ana · 12 wins" ("1 win"), "No wins yet
--     this week. Be the first!" alone for an empty week, and the player's own line: their place and wins, their
--     week's wins outside the read, or how to get on the board.
--   * UI FINAL R4 (moved from R8): iconFor(card): a quest that names a squishy shows it, else its category's picture
--     (squeeze, duel, practice); the cards carry their QuestDefs id (defId) and named squishy.
--   * UI FINAL R8 (the design's Quests window): "x / y" (H:956), the tabs with their ready counts (Starter while a
--     task is unclaimed, Top Wins last), the bar's gold once ready or claimed, GO's route by category, the squeeze
--     toast's key by input, and the Top Wins rows.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local QuestFormat = t.requireClient("UI/QuestFormat")
	local CapsuleMath = t.requireShared("CapsuleMath")
	local Config = t.requireShared("Config")
	local Format = t.requireShared("Util/Format")
	local QuestDefs = t.requireShared("QuestDefs")
	local Strings = t.requireShared("Strings")
	local SWAPS = Config.Economy.Quests.freeSwapsPerDay

	local D = 20000
	local START = D * 86400
	local NOW = START + 5 * 3600 + 7 * 60 -- 05:07:00 UTC: 18 h 53 min to the next day
	local TOAST = "Toast"

	local function entry(slot: number, def: string, goal: number, progress: number, extra: { [string]: any }?): any
		local e: { [string]: any } = {
			id = string.format("q%d_%d", D, slot),
			def = def,
			progress = progress,
			goal = goal,
			reward = 150,
			done = progress >= goal,
			claimed = false,
		}
		if extra then
			for key, value in extra do
				e[key] = value
			end
		end
		return e
	end

	local function quests(active: { any }, swapsUsed: number?, starter: any?): any
		return {
			day = D,
			swapsUsed = swapsUsed or 0,
			active = active,
			starter = starter or { progress = {}, claimed = {} },
		}
	end

	local ctx = { owned = { kitty_bread = {}, toast = {} }, equipped = "kitty_bread", now = NOW }
	-- A new player's squeeze value (no capsules in the context): Kitty Bread in a Lv 1 capsule, 10 Coins.
	local VALUE = CapsuleMath.squeezeValue(nil)

	t.test("daily card: title, progress, reward and the three states", function()
		local open = QuestFormat.dailyCard(entry(1, "squeeze_any", 100, 37), ctx, SWAPS)
		expect.equal(open.title, QuestDefs.text("squeeze_any", 100))
		expect.equal(open.progressText, Strings.format(Strings.quest.progress, { progress = 37, goal = 100 }))
		expect.equal(open.progressText, "37 / 100") -- UI FINAL R8 (H:956)
		expect.near(open.fraction, 0.37, 1e-9)
		expect.equal(open.reward, 150 * VALUE)
		expect.equal(open.rewardText, Strings.format(Strings.common.coinsGain, { coins = "1,500" }))
		expect.equal(open.state, "inProgress")
		expect.equal(open.stateText, Strings.quest.inProgress)
		local ready = QuestFormat.dailyCard(entry(1, "squeeze_any", 100, 100), ctx, SWAPS)
		expect.equal(ready.state, "claim")
		expect.equal(ready.stateText, Strings.common.claim)
		local claimed = QuestFormat.dailyCard(entry(1, "squeeze_any", 100, 100, { claimed = true }), ctx, SWAPS)
		expect.equal(claimed.state, "claimed")
		expect.equal(claimed.stateText, Strings.common.claimed)
		-- Progress is shown clamped to the goal; a squishy quest names its squishy.
		local over = QuestFormat.dailyCard(entry(2, "squeeze_with", 60, 75, { squishy = "toast" }), ctx, SWAPS)
		expect.equal(over.progress, 60)
		expect.equal(over.title, QuestDefs.text("squeeze_with", 60, TOAST))
		expect.equal(over.fraction, 1)
		-- An unknown template is left out.
		expect.equal(QuestFormat.dailyCard(entry(3, "no_such_quest", 5, 0), ctx, SWAPS), nil)
	end)

	t.test("quest pictures (UI FINAL R4, iconFor): the named squishy, else the category's picture", function()
		local with = QuestFormat.dailyCard(entry(2, "squeeze_with", 60, 10, { squishy = "toast" }), ctx, SWAPS)
		expect.equal(with.defId, "squeeze_with")
		expect.equal(with.squishy, "toast")
		expect.deepEqual(QuestFormat.iconFor(with), { squishy = "toast" })
		local pictures = { squeeze = "img.icon.squeeze", duel = "img.nav.duel", practice = "img.icon.match" }
		local plain = QuestFormat.dailyCard(entry(1, "squeeze_any", 100, 37), ctx, SWAPS)
		expect.equal(plain.squishy, nil)
		expect.deepEqual(QuestFormat.iconFor(plain), { image = pictures.squeeze })
		expect.deepEqual(
			QuestFormat.iconFor(QuestFormat.dailyCard(entry(3, "duel_win", 3, 0), ctx, SWAPS)),
			{ image = pictures.duel }
		)
		expect.deepEqual(
			QuestFormat.iconFor(QuestFormat.dailyCard(entry(4, "practice_hits", 20, 0), ctx, SWAPS)),
			{ image = pictures.practice }
		)
		-- A squishy quest without its squishy falls back to its category's picture.
		local unnamed = QuestFormat.dailyCard(entry(5, "duel_win_with", 3, 0), ctx, SWAPS)
		expect.deepEqual(QuestFormat.iconFor(unnamed), { image = pictures.duel })
		-- Starter tasks carry their QuestDefs id too.
		for _, starter in QuestFormat.starterCards(nil) do
			local def = QuestDefs.get(starter.id)
			expect.equal(starter.defId, starter.id)
			expect.deepEqual(QuestFormat.iconFor(starter), { image = pictures[def.category] })
		end
		-- An unknown quest has no picture.
		expect.deepEqual(QuestFormat.iconFor({ defId = "no_such_quest" } :: any), {})
	end)

	t.test("swap: unfinished daily quests while a free swap is left", function()
		local board = QuestFormat.board(
			quests({ entry(1, "squeeze_any", 100, 10), entry(2, "duel_win", 1, 1), entry(3, "practice_hits", 20, 0) }),
			ctx
		)
		expect.equal(board.swapsLeft, SWAPS)
		expect.equal(board.daily[1].canSwap, SWAPS > 0)
		expect.equal(board.daily[2].canSwap, false) -- finished
		expect.equal(board.daily[3].canSwap, SWAPS > 0)
		local used = QuestFormat.board(quests({ entry(1, "squeeze_any", 100, 10) }, SWAPS), ctx)
		expect.equal(used.swapsLeft, 0)
		expect.equal(used.daily[1].canSwap, false)
		expect.equal(QuestFormat.swapsLeft({ swapsUsed = 99 }), 0)
		expect.equal(QuestFormat.swapsLeft(nil), SWAPS)
		-- Starter tasks never swap.
		for _, c in used.starter do
			expect.equal(c.canSwap, false)
		end
	end)

	t.test("equip shortcut: owned but not equipped, and unfinished", function()
		local withToast = entry(2, "hits_with", 8, 2, { squishy = "toast" })
		expect.equal(QuestFormat.dailyCard(withToast, ctx, SWAPS).equipSquishy, "toast")
		local equippedCtx = { owned = ctx.owned, equipped = "toast", now = NOW }
		expect.equal(QuestFormat.dailyCard(withToast, equippedCtx, SWAPS).equipSquishy, nil)
		local notOwned = entry(2, "hits_with", 8, 2, { squishy = "dragon" })
		expect.equal(QuestFormat.dailyCard(notOwned, ctx, SWAPS).equipSquishy, nil)
		local finished = entry(2, "hits_with", 8, 8, { squishy = "toast" })
		expect.equal(QuestFormat.dailyCard(finished, ctx, SWAPS).equipSquishy, nil)
		expect.equal(QuestFormat.dailyCard(entry(1, "squeeze_any", 100, 0), ctx, SWAPS).equipSquishy, nil)
	end)

	t.test("starter section: every starter task, its progress, hidden once all are claimed", function()
		local defs = QuestDefs.starter()
		local progress = { [defs[1].id] = 7 }
		local cards = QuestFormat.starterCards({ progress = progress, claimed = {} })
		expect.equal(#cards, #defs)
		for i, def in defs do
			local variant = def.variants[1]
			expect.equal(cards[i].id, def.id)
			expect.equal(cards[i].kind, "starter")
			expect.equal(cards[i].title, QuestDefs.text(def.id, variant.goal))
			expect.equal(cards[i].reward, variant.reward * VALUE)
		end
		expect.equal(cards[1].progress, math.min(7, defs[1].variants[1].goal))
		expect.equal(cards[2].progress, 0)
		-- Done at the goal; claimed.
		local doneMap = { [defs[1].id] = defs[1].variants[1].goal }
		local done = QuestFormat.starterCards({ progress = doneMap, claimed = { [defs[2].id] = true } })
		expect.equal(done[1].state, "claim")
		expect.equal(done[2].state, "claimed")
		expect.equal(done[3].state, "inProgress")
		local someLeft = QuestFormat.board(quests({}, 0, { progress = {}, claimed = { [defs[1].id] = true } }), ctx)
		expect.equal(someLeft.starterVisible, true)
		local allClaimed = {}
		for _, def in defs do
			allClaimed[def.id] = true
		end
		local finished = QuestFormat.board(quests({}, 0, { progress = {}, claimed = allClaimed }), ctx)
		expect.equal(finished.starterVisible, false)
		-- A wrong-shaped starter state reads as nothing done.
		expect.equal(QuestFormat.starterCards("x")[1].state, "inProgress")
		-- The HUD badge's starter count: done and not claimed only.
		local state = quests({}, 0, { progress = doneMap, claimed = { [defs[2].id] = true } })
		expect.equal(QuestFormat.starterClaimable(state), 1)
		expect.equal(QuestFormat.starterClaimable(quests({}, 0, { progress = doneMap, claimed = allClaimed })), 0)
		expect.equal(QuestFormat.starterClaimable(nil), 0)
	end)

	t.test(
		"rewards are the squeezes × the squeeze value of the capsules in the context (spec 2026-10-12 §9)",
		function()
			-- Dragon (power 64) in a Lv 21 capsule: 64 × CP(21) Coins a squeeze.
			local capsules = { slots = 1, list = { { level = 21, squishyId = "dragon" } } }
			local value = CapsuleMath.squeezeValue(capsules)
			expect.equal(value, 64 * (CapsuleMath.power(21) :: number))
			local rich = { owned = ctx.owned, equipped = ctx.equipped, now = NOW, capsules = capsules }
			local defs = QuestDefs.starter()
			local board = QuestFormat.board(quests({ entry(1, "squeeze_any", 100, 37) }), rich)
			expect.equal(board.daily[1].reward, 150 * value)
			expect.equal(
				board.daily[1].rewardText,
				Strings.format(Strings.common.coinsGain, { coins = Format.coins(150 * value) })
			)
			for i, def in defs do
				expect.equal(board.starter[i].reward, CapsuleMath.rewardCoins(def.variants[1].reward, value))
			end
		end
	)

	t.test("reset line and empty state count down to 00:00 UTC", function()
		expect.equal(QuestFormat.resetText(NOW), Strings.format(Strings.quest.footer, { clock = "18h 53m" }))
		expect.equal(QuestFormat.resetText(NOW), "Resets in 18h 53m")
		expect.equal(QuestFormat.resetText(START + 86399), "Resets in 0:01")
		-- lib:306: hours and two-digit minutes, else m:ss in the last hour; never below 0.
		expect.equal(QuestFormat.clock(3600), "1h 00m")
		expect.equal(QuestFormat.clock(3599), "59:59")
		expect.equal(QuestFormat.clock(25920), "7h 12m")
		expect.equal(QuestFormat.clock(65.9), "1:05")
		expect.equal(QuestFormat.clock(-5), "0:00")
		expect.equal(QuestFormat.clock(0 / 0), "0:00")
		local empty = QuestFormat.board(quests({}), ctx)
		expect.equal(#empty.daily, 0)
		expect.equal(empty.empty, Strings.format(Strings.quest.empty, { time = "18:53:00" }))
		expect.equal(empty.reset, QuestFormat.resetText(NOW))
		local full = QuestFormat.board(quests({ entry(1, "squeeze_any", 100, 0) }), ctx)
		expect.equal(full.empty, nil)
		-- No state at all: empty, starter tasks still listed.
		local none = QuestFormat.board(nil, ctx)
		expect.equal(#none.daily, 0)
		expect.truthy(none.empty ~= nil)
		expect.equal(#none.starter, #QuestDefs.starter())
	end)

	t.test("namer: daily quests from the state, starter tasks from QuestDefs", function()
		local state =
			quests({ entry(1, "squeeze_any", 100, 0), entry(2, "duel_win_with", 2, 0, { squishy = "toast" }) })
		local name = QuestFormat.namer(state)
		expect.equal(name(string.format("q%d_1", D)), QuestDefs.text("squeeze_any", 100))
		expect.equal(name(string.format("q%d_2", D)), QuestDefs.text("duel_win_with", 2, TOAST))
		local starter = QuestDefs.starter()[3]
		expect.equal(name(starter.id), QuestDefs.text(starter.id, starter.variants[1].goal))
		expect.equal(name(string.format("q%d_9", D)), nil)
		expect.equal(name("starter_nope"), nil)
		expect.equal(name("squeeze_any"), nil) -- a template id is not a questId
		local bare = QuestFormat.namer(nil)
		expect.equal(bare(starter.id), QuestDefs.text(starter.id, starter.variants[1].goal))
		expect.equal(bare(string.format("q%d_1", D)), nil)
	end)

	t.test(
		"layout (Part 8): the panel stays within 86% of the screen; the sections scroll; short boards show whole",
		function()
			local Layout = t.requireClient("UI/Layout")
			local UI = Config.UI
			local SHARE = 0.86 -- QuestController.MAX_HEIGHT_SHARE
			for _, actual in { Vector2.new(667, 375), Vector2.new(1280, 720), Vector2.new(1920, 1080) } do
				local screen = actual / Layout.uiScale(actual.Y)
				for _, textScale in { 1, UI.PreferredTextScale.Largest } do
					-- Foam UI: the header tab (an H2 line, 2 × 4 px padding and its 2 + 5 + 3 px bands) and Close hang
					-- half above the panel; the top padding leaves room for their lower halves (+ 6 px), the bottom
					-- padding is 20; the footer pill (a Small line in 6 px paddings) sits under one 12 px gap.
					local tab = 1.25 * UI.TextSize.H2 * textScale + 18
					local above = math.max(tab, UI.Touch.closeButton) / 2
					local top = math.max(math.ceil(UI.Touch.closeButton / 2), math.ceil(tab / 2)) + 6
					local chrome = above + top + 20 + 12 + 1.25 * UI.TextSize.Small * textScale + 12
					-- A card: 12 px padding around (the bottom one holds the foam bands), the title (2 lines), the bar
					-- row ("3/5" in the Chip kind), the action row (two rows of buttons at the largest text), 6 px
					-- between rows; 3 daily + 4 starter cards.
					local actionRows = if textScale > 1 then 2 * 52 + 6 else 52
					local card = 24
						+ 2 * 1.25 * UI.TextSize.Body * textScale
						+ 12
						+ 1.25 * UI.TextSize.Chip * textScale
						+ actionRows
					local content = 7 * card + 2 * 1.25 * UI.TextSize.H2 * textScale + 9 * 6
					local body = QuestFormat.bodyHeight(screen.Y, content, chrome, SHARE, UI.Touch.minTarget)
					expect.truthy(body + chrome <= screen.Y * SHARE + 1e-6)
					expect.truthy(body >= UI.Touch.minTarget)
					expect.truthy(body < content) -- a full board scrolls on every screen
					local one = QuestFormat.bodyHeight(screen.Y, card, chrome, SHARE, UI.Touch.minTarget)
					if card + chrome <= screen.Y * SHARE then
						expect.equal(one, card)
					end
				end
			end
			expect.equal(QuestFormat.bodyHeight(441, 10, 200, SHARE, 52), 52)
			expect.equal(QuestFormat.bodyHeight(0 / 0, 0 / 0, 0 / 0, SHARE, 52), 52)
		end
	)

	t.test("Top Wins This Week: loading, the ranked lines, an empty week and the player's own line", function()
		local board = Strings.board
		expect.deepEqual(QuestFormat.topWins(nil), { lines = {}, rows = {}, note = board.loading })
		expect.deepEqual(
			QuestFormat.topWins({ loaded = false, top = {}, wins = 0 }),
			{ lines = {}, rows = {}, note = board.loading }
		)
		expect.deepEqual(
			QuestFormat.topWins({ loaded = true, top = {}, wins = 0 }),
			{ lines = {}, rows = {}, note = "No wins yet this week. Be the first!" } -- the note alone
		)
		expect.deepEqual(
			QuestFormat.topWins({ loaded = true, unavailable = true, top = {}, wins = 0 }),
			{ lines = {}, rows = {}, note = "The board is taking a break. Check back soon!" }
		)
		expect.deepEqual(
			QuestFormat.topWins({ loaded = true, top = { { name = "Cy", wins = 1 } }, wins = 0 }),
			{ lines = { "1. Cy · 1 win" }, rows = { { rank = 1, name = "Cy", wins = 1 } }, you = board.youNone }
		)
		local top: { any } = { { name = "Ana", wins = 1234 }, { name = "Bo", wins = 12 }, { name = 5, wins = "x" } }
		local view = {
			loaded = true,
			top = top,
			place = 1,
			wins = 1234,
		}
		expect.deepEqual(QuestFormat.topWins(view), {
			lines = { "1. Ana · 1,234 wins", "2. Bo · 12 wins" }, -- a broken entry is left out
			rows = { { rank = 1, name = "Ana", wins = 1234 }, { rank = 2, name = "Bo", wins = 12 } }, -- R8 (PR26)
			you = "You: #1 · 1,234 wins",
		})
		expect.equal(
			QuestFormat.topWins({ loaded = true, top = view.top, place = 2, wins = 1 }).you,
			"You: #2 · 1 win"
		)
		expect.equal(QuestFormat.topWins({ loaded = true, top = view.top, wins = 3 }).you, "You: 3 wins this week")
	end)

	-- UI FINAL R8 (the design's Quests window, plan work/ui/PLAN.md R8; `H:n` = "Squishy Duels HUD.dc.html" line n).

	t.test(
		"tabs (H:358, UD7): Daily, Starter while a task is unclaimed, Top Wins, each with its ready count",
		function()
			local function ids(list: { any }): { string }
				local out = {}
				for _, tab in list do
					table.insert(out, tab.id .. ":" .. tab.count)
				end
				return out
			end
			local state = quests({
				entry(1, "squeeze_any", 100, 100),
				entry(2, "duel_win", 1, 1),
				entry(3, "practice_hits", 20, 0),
			})
			local tabs = QuestFormat.tabs(QuestFormat.board(state, ctx))
			expect.deepEqual(ids(tabs), { "daily:2", "starter:0", "topWins:0" })
			expect.equal(tabs[1].label, Strings.quest.section.daily)
			expect.equal(tabs[2].label, Strings.quest.section.starter)
			expect.equal(tabs[3].label, Strings.board.title)
			-- A claimed daily quest is not counted; a done starter task is.
			local defs = QuestDefs.starter()
			local progress = { [defs[1].id] = defs[1].variants[1].goal }
			local mixed = quests(
				{ entry(1, "squeeze_any", 100, 100, { claimed = true }) },
				0,
				{ progress = progress, claimed = {} }
			)
			expect.deepEqual(
				ids(QuestFormat.tabs(QuestFormat.board(mixed, ctx))),
				{ "daily:0", "starter:1", "topWins:0" }
			)
			-- Every starter task claimed: no Starter tab.
			local allClaimed = {}
			for _, def in defs do
				allClaimed[def.id] = true
			end
			local done = quests({}, 0, { progress = {}, claimed = allClaimed })
			expect.deepEqual(ids(QuestFormat.tabs(QuestFormat.board(done, ctx))), { "daily:0", "topWins:0" })
		end
	)

	t.test("the bar's gold (H:956), GO's route (UD2) and the squeeze toast's key", function()
		local open = QuestFormat.dailyCard(entry(1, "squeeze_any", 100, 37), ctx, SWAPS)
		local ready = QuestFormat.dailyCard(entry(1, "squeeze_any", 100, 100), ctx, SWAPS)
		local claimed = QuestFormat.dailyCard(entry(1, "squeeze_any", 100, 100, { claimed = true }), ctx, SWAPS)
		expect.equal(QuestFormat.barGold(open), false)
		expect.equal(QuestFormat.barGold(ready), true)
		expect.equal(QuestFormat.barGold(claimed), true)
		expect.equal(QuestFormat.goRoute(open), "squeeze")
		expect.equal(QuestFormat.goRoute(QuestFormat.dailyCard(entry(2, "duel_win", 3, 0), ctx, SWAPS)), "duel")
		expect.equal(
			QuestFormat.goRoute(QuestFormat.dailyCard(entry(3, "practice_hits", 20, 0), ctx, SWAPS)),
			"practice"
		)
		for _, starter in QuestFormat.starterCards(nil) do
			expect.equal(QuestFormat.goRoute(starter), QuestDefs.get(starter.id).category)
		end
		expect.equal(QuestFormat.goRoute({ defId = "no_such_quest" } :: any), nil)
		local keys = Strings.duel.key
		expect.equal(
			QuestFormat.goToast("KeyboardAndMouse"),
			Strings.format(Strings.quest.goSqueeze, { key = keys.squeezeMouse })
		)
		expect.equal(
			QuestFormat.goToast("Gamepad"),
			Strings.format(Strings.quest.goSqueeze, { key = keys.squeezeGamepad })
		)
		expect.equal(QuestFormat.goToast("Touch"), Strings.quest.goSqueezeTouch)
		expect.equal(Strings.quest.goSqueeze, "Squeeze your squishy! Press {key}")
	end)
end
