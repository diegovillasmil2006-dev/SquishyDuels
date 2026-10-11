--!strict
-- HudFormat_Test: StarterPlayerScripts.Client.UI.HudFormat (the lobby HUD's words, numbers and layout). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §11.6, §11.3, §3.1, §3.13, §9.13, §11.4; foam UI restyle, spec 2026-10-09 "Lobby HUD"):
--   * the HUD's buttons are Squishies, Boxes, Shop, Quests, Daily (the tile column, each with its accent and icon), Duel
--     (the CTA at the top middle) and Settings (the top-right gear) with stable names; only those whose screen exists
--     show;
--   * the data line: a pending save first ("Saving your collection…"), then the server's banner key, else derived from
--     the status (offline, read-only); Studio memory mode is never shown (log only) and a ready, saved session shows
--     none;
--   * the coin capsule reads "Loading…" before the first value and Format.coins after; only an increase floats "+N";
--   * badges count done-but-unclaimed quests and an unclaimed daily reward; 0 shows no badge;
--   * key hints are text: "Inspect (V)" / "Inspect (Y)" / "Inspect" on touch, and a keycap's key the same way;
--   * the quest tracker shows the unclaimed quest closest to done, Starter tasks first, nothing when all are claimed;
--   * the Duel CTA reads DUEL / Join the queue, and IN QUEUE with the queue's clock while Searching;
--   * feel pass (§18.5.2 B1-B2): while the HUD is hidden every Coins change is held; when it shows again the held gain
--     lands as a flight from the result panel's reward label (>= 50 Coins, not under ReducedMotion) or a count-up; the
--     coin disc wiggles 0 -> -12° -> 0.
-- Layout (at 667×375, 812×375, 844×390, 1024×768, 1280×720 and 1920×1080, every PreferredTextSize up to Largest ×1.45):
-- the text estimate; the left side (the coin capsule, the Grip card and the tiles) fits on PCs at every text size, the
-- Grip card never hides while it has a state, else the shortest layout; the compact Grip card's row <= 40 base inside a
-- touch-sized tap target; the gamepad links walk the tile column and reach the CTA; DPadUp.
-- Lobby HUD (spec 2026-10-11): the Duel CTA sits at the top middle on every layout, moved only as far as the left and
-- right groups need; the coach card sits right under it (wider when its text needs it); phones follow the PC layout: the
-- compact Grip card under the coin capsule (beside it only when that keeps the top-middle CTA clear) and the tiles in
-- two columns, which may reach into the thumbstick zone (the user's choice); the gamepad links put the CTA between the
-- left column and Settings, Down to the queue pill's Cancel or the coach card's button. No dock.
-- Foam fix (2026-10-09): the thumbstick zone is a share of the whole screen (the top bar inset the HUD leaves out
-- counts); the compact Grip card is as wide as its line. Foam fix 2: the tiles start a count badge's reach plus air
-- under Hud_Left (not on the regular card);
-- the coins "+N" rises only as far as the HUD's top (gainRise); the toast column keeps air beside a badge hanging past
-- the tile row (badgeReachRect). Foam fix 3: the "+N" reads "+12,450" (gainText); on phones it sits on the capsule's
-- top edge over its number, clear of the Grip card beside it and inside the HUD (gainSpot); PCs keep fix 2's spot.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local HudFormat = t.requireClient("UI/HudFormat")
	local Strings = t.requireShared("Strings")
	local Format = t.requireShared("Util/Format")

	t.test("nav: DESIGN order, stable names, places, accents and icons; only registered screens", function()
		local ids = {}
		for _, item in HudFormat.NAV do
			table.insert(ids, item.id)
			expect.truthy(Strings.resolve(item.textKey))
			expect.truthy(string.match(item.button, "^Hud_%u%a+Button$"))
			expect.truthy(type(item.accent) == "string" and type(item.icon) == "string")
		end
		expect.deepEqual(ids, { "squishies", "boxes", "shop", "quests", "daily", "duel", "settings" })
		local tiles = {}
		for _, item in HudFormat.navAt("tile") do
			table.insert(tiles, item.id)
		end
		expect.deepEqual(tiles, { "squishies", "boxes", "shop", "quests", "daily" })
		expect.equal(HudFormat.navAt("cta")[1].button, "Hud_DuelButton")
		expect.equal(HudFormat.navAt("cta")[1].screen, "queue")
		expect.equal(HudFormat.navAt("settings")[1].button, "Hud_SettingsButton")
		-- Spec "Left column": Squishies Strawberry, Boxes Lilac, Shop the new accent, Quests the quest mint, Daily Sky.
		local accents = {}
		for _, item in HudFormat.navAt("tile") do
			accents[item.id] = item.accent
		end
		expect.deepEqual(
			accents,
			{ squishies = "strawberry", boxes = "lilac", shop = "shop", quests = "quests", daily = "sky" }
		)
		local shown = HudFormat.visibleNav(function(screen: string): boolean
			return screen == "squishies" or screen == "settings" or screen == "queue"
		end)
		local shownIds = {}
		for _, item in shown do
			table.insert(shownIds, item.id)
		end
		expect.deepEqual(shownIds, { "squishies", "duel", "settings" })
		expect.deepEqual(
			HudFormat.visibleNav(function()
				return false
			end),
			{}
		)
	end)

	t.test("banner: pending save first, then the server's key, else derived; Studio memory mode never shows", function()
		expect.equal(HudFormat.banner(nil), nil)
		expect.equal(HudFormat.banner({ status = "ready", persisted = true, savePending = false }), nil)
		local saving = HudFormat.banner({ status = "ready", persisted = true, savePending = true })
		expect.deepEqual(saving, { text = Strings.reason.box.saving, kind = "info" })
		-- Spec: the Studio memory-mode text is not shown to players (log only).
		local memory = { status = "ready", persisted = false, savePending = false }
		expect.equal(HudFormat.banner(memory), nil)
		expect.truthy(HudFormat.isStudioMemory(memory))
		local memoryKey = { status = "ready", persisted = false, savePending = false, banner = "data.studioMemory" }
		expect.equal(HudFormat.banner(memoryKey), nil)
		expect.truthy(HudFormat.isStudioMemory(memoryKey))
		expect.falsy(HudFormat.isStudioMemory({ status = "ready", persisted = true, savePending = false }))
		expect.falsy(HudFormat.isStudioMemory(nil))
		local offline = HudFormat.banner({ status = "offline", persisted = true, savePending = false })
		expect.deepEqual(offline, { text = Strings.data.offlineRetrying, kind = "warn" })
		local readonly = HudFormat.banner({ status = "readonly", persisted = true, savePending = false })
		expect.deepEqual(readonly, { text = Strings.data.loadFailed, kind = "warn" })
		expect.equal(HudFormat.banner({ status = "loading", persisted = true, savePending = false }), nil)
	end)

	t.test("banner: the server's choice wins over the derived line, unless it names no text", function()
		local newer = HudFormat.banner({
			status = "readonly",
			persisted = true,
			savePending = false,
			banner = "data.newerVersion",
		})
		expect.deepEqual(newer, { text = Strings.data.newerVersion, kind = "warn" })
		local exhausted =
			HudFormat.banner({ status = "offline", persisted = true, savePending = false, banner = "data.loadFailed" })
		expect.deepEqual(exhausted, { text = Strings.data.loadFailed, kind = "warn" })
		local unknown =
			HudFormat.banner({ status = "offline", persisted = true, savePending = false, banner = "data.noSuchKey" })
		expect.deepEqual(unknown, { text = Strings.data.offlineRetrying, kind = "warn" })
		-- A pending save is shown even when the server also chose a banner.
		local both =
			HudFormat.banner({ status = "ready", persisted = false, savePending = true, banner = "data.studioMemory" })
		expect.equal(both.text, Strings.reason.box.saving)
		-- The Studio key on an offline status still gives the offline line.
		local offlineStudio = HudFormat.banner({
			status = "offline",
			persisted = false,
			savePending = false,
			banner = "data.studioMemory",
		})
		expect.deepEqual(offlineStudio, { text = Strings.data.offlineRetrying, kind = "warn" })
	end)

	t.test("coins: Loading… before the first value, Format.coins after; only increases float", function()
		expect.equal(HudFormat.coinsText(nil), Strings.common.loading)
		expect.equal(HudFormat.coinsText(12345), Format.coins(12345))
		expect.equal(HudFormat.coinsText(0), Format.coins(0))
		expect.equal(HudFormat.coinGain(nil, 50), nil)
		expect.equal(HudFormat.coinGain(50, 55), 5)
		expect.equal(HudFormat.coinGain(55, 40), nil)
		expect.equal(HudFormat.coinGain(40, 40), nil)
		-- Foam fix 3: the "+N" groups its thousands like the capsule.
		expect.equal(HudFormat.gainText(5), "+5")
		expect.equal(HudFormat.gainText(12450), "+12,450")
		expect.equal(HudFormat.gainText(1234567), "+" .. Format.coins(1234567))
	end)

	t.test("badges: claimable quests, an unclaimed daily reward, capped numbers", function()
		local quests = {
			active = {
				{ done = true, claimed = false },
				{ done = true, claimed = true },
				{ done = false, claimed = false },
				{ done = true, claimed = false },
			},
		}
		expect.equal(HudFormat.questBadge(quests), 2)
		expect.equal(HudFormat.questBadge(nil), 0)
		expect.equal(HudFormat.questBadge({ active = "nope" }), 0)
		expect.equal(HudFormat.dailyBadge({ lastClaimDay = 99 }, 100), 1)
		expect.equal(HudFormat.dailyBadge({ lastClaimDay = 100 }, 100), 0)
		expect.equal(HudFormat.dailyBadge({ lastClaimDay = -1 }, 100), 1)
		expect.equal(HudFormat.dailyBadge(nil, 100), 0)
		expect.equal(HudFormat.badgeText(0), nil)
		expect.equal(HudFormat.badgeText(3), "3")
		expect.equal(HudFormat.badgeText(250), tostring(HudFormat.BADGE_MAX))
		expect.equal(HudFormat.badgeText(0 / 0), nil)
	end)

	t.test("coins: the gain is held while the HUD is hidden and lands when it shows again", function()
		local Config = t.requireShared("Config")
		local minFlight = Config.UI.motion.coinFlight.minAmount
		expect.deepEqual(HudFormat.coinAction(100, 100, 130, true, false), { kind = "gain", to = 130, gain = 30 })
		expect.deepEqual(HudFormat.coinAction(100, 100, 40, true, false), { kind = "spend", to = 40 })
		expect.deepEqual(HudFormat.coinAction(100, 100, 100, true, false), { kind = "none", to = 100 })
		expect.deepEqual(HudFormat.coinAction(nil, nil, 70, true, false), { kind = "set", to = 70 })
		expect.deepEqual(HudFormat.coinAction(100, 100, nil, true, false), { kind = "set", to = nil })
		expect.deepEqual(HudFormat.coinAction(100, 100, 900, false, true), { kind = "set", to = 900 })
		local displayed = 100
		local previous = 100
		for _, value in { 160, 220, 210 } do
			local action = HudFormat.coinAction(displayed, previous, value, false, false)
			expect.equal(action.kind, "hold")
			expect.equal(action.to, value)
			previous = value
		end
		expect.equal(displayed, 100)
		expect.deepEqual(
			HudFormat.releaseHeld(displayed, previous, true, false),
			{ kind = "flight", to = 210, gain = 110 }
		)
		expect.deepEqual(
			HudFormat.releaseHeld(displayed, previous, false, false),
			{ kind = "gain", to = 210, gain = 110 }
		)
		expect.deepEqual(
			HudFormat.releaseHeld(displayed, previous, true, true),
			{ kind = "gain", to = 210, gain = 110 }
		)
		expect.equal(HudFormat.releaseHeld(100, 100 + minFlight - 1, true, false).kind, "gain")
		expect.equal(HudFormat.releaseHeld(100, 100 + minFlight, true, false).kind, "flight")
		expect.deepEqual(HudFormat.releaseHeld(100, 100, true, false), { kind = "none", to = 100 })
		expect.deepEqual(HudFormat.releaseHeld(100, 60, true, false), { kind = "spend", to = 60 })
		expect.deepEqual(HudFormat.releaseHeld(nil, 60, true, false), { kind = "none" })
	end)

	t.test("coins: the disc wiggles 0 -> -12° -> 0 over 200 ms", function()
		local Config = t.requireShared("Config")
		local deg = Config.UI.motion.coinCounter.iconWiggleDeg
		local start, startDone = HudFormat.iconWiggle(0)
		expect.equal(start, 0)
		expect.falsy(startDone)
		local mid = HudFormat.iconWiggle(0.1)
		expect.near(mid, -deg, 1e-6)
		local final, done = HudFormat.iconWiggle(0.2)
		expect.equal(final, 0)
		expect.truthy(done)
		for i = 1, 19 do
			local r = HudFormat.iconWiggle(i / 100)
			expect.truthy(r <= 0 and r >= -deg)
		end
	end)

	t.test("key hints: the action with its key as text, plain on touch; the keycap's key", function()
		local keys = Strings.controls.key
		expect.equal(
			HudFormat.keyHint("common.inspect", "keyboard"),
			Strings.format(Strings.controls.keyHint, { action = Strings.common.inspect, key = keys.inspectKeyboard })
		)
		expect.equal(
			HudFormat.keyHint("common.inspect", "gamepad"),
			Strings.format(Strings.controls.keyHint, { action = Strings.common.inspect, key = keys.inspectGamepad })
		)
		expect.equal(HudFormat.keyHint("common.inspect", "touch"), Strings.common.inspect)
		expect.equal(HudFormat.keyHint("hud.nav.squishies", "gamepad"), Strings.hud.nav.squishies)
		expect.equal(HudFormat.keyHint("common.close", "keyboard"), Strings.common.close)
		-- An Inspect keycap: V on a keyboard, Y on a gamepad, hidden on touch.
		expect.equal(HudFormat.keyFor("common.inspect", "keyboard"), "controls.key.inspectKeyboard")
		expect.equal(HudFormat.keyFor("common.inspect", "gamepad"), "controls.key.inspectGamepad")
		expect.equal(HudFormat.keyFor("common.inspect", "touch"), nil)
		expect.equal(HudFormat.keyFor("common.close", "keyboard"), nil)
	end)

	t.test(
		"quest tracker: the unclaimed quest closest to done, Starter tasks first, none when all are claimed",
		function()
			local function card(id: string, state: string, fraction: number): any
				return { id = id, state = state, fraction = fraction }
			end
			local function board(starter: { any }, daily: { any }): any
				return { starter = starter, daily = daily }
			end
			-- Starter first, even when a daily quest is further along.
			local picked = HudFormat.trackedQuest(
				board({ card("starter_a", "inProgress", 0.2) }, { card("q1", "inProgress", 0.9) })
			)
			expect.equal(picked.id, "starter_a")
			-- The closest to done among the unclaimed; a quest ready to claim counts as done; claimed ones never show.
			picked = HudFormat.trackedQuest(board({
				card("starter_a", "inProgress", 0.4),
				card("starter_b", "claimed", 1),
				card("starter_c", "inProgress", 0.6),
			}, {}))
			expect.equal(picked.id, "starter_c")
			picked = HudFormat.trackedQuest(
				board({ card("starter_a", "inProgress", 0.4), card("starter_d", "claim", 1) }, {})
			)
			expect.equal(picked.id, "starter_d")
			-- Every Starter task claimed: the day's quests; equals keep the board order.
			picked = HudFormat.trackedQuest(board({ card("starter_a", "claimed", 1) }, {
				card("q1", "inProgress", 0.5),
				card("q2", "inProgress", 0.5),
				card("q3", "claimed", 1),
			}))
			expect.equal(picked.id, "q1")
			expect.equal(HudFormat.trackedQuest(board({ card("s", "claimed", 1) }, { card("q", "claimed", 1) })), nil)
			expect.equal(HudFormat.trackedQuest(board({}, {})), nil)
			-- With the real board of a new player: the first Starter task.
			local QuestFormat = t.requireClient("UI/QuestFormat")
			local real = QuestFormat.board(nil, { owned = {}, equipped = "kitty_bread", now = 0 })
			local first = HudFormat.trackedQuest(real)
			expect.truthy(first ~= nil and first.kind == "starter")
		end
	)

	t.test("the Duel CTA: DUEL / Join the queue; IN QUEUE with the queue's clock while Searching", function()
		expect.deepEqual(
			HudFormat.ctaModel(nil, 100),
			{ queued = false, title = Strings.hud.duelCta, subtext = Strings.hud.duelJoin }
		)
		expect.equal(HudFormat.ctaModel({ state = "Idle" }, 100).queued, false)
		expect.equal(HudFormat.ctaModel({ state = "Matched", joinedAt = 10 }, 100).queued, false)
		local queued = HudFormat.ctaModel({ state = "Searching", joinedAt = 1000 }, 1023.6)
		expect.deepEqual(queued, {
			queued = true,
			title = Strings.hud.duelQueued,
			subtext = Strings.format(Strings.hud.duelSearchingTime, { time = "0:23" }),
		})
		-- The same clock as the queue pill's title.
		local QueueFormat = t.requireClient("UI/QueueFormat")
		local pill = QueueFormat.pill(
			{ state = "Searching", joinedAt = 1000, position = 1, searching = 1, arenasFree = 6 },
			1023.6,
			nil,
			nil
		)
		expect.truthy(string.find(pill.title, "0:23", 1, true) ~= nil)
		expect.truthy(string.find(queued.subtext, "0:23", 1, true) ~= nil)
		expect.equal(HudFormat.ctaModel({ state = "Searching" }, 50).subtext, Strings.hud.duelSearching)
	end)

	-- Layout ---------------------------------------------------------------------------------------------------------

	local Config = t.requireShared("Config")
	local Layout = t.requireClient("UI/Layout")
	local UI = Config.UI
	local TOUCH = UI.Touch
	local COLUMN = HudFormat.COLUMN
	local PHONES = { Vector2.new(667, 375), Vector2.new(812, 375), Vector2.new(844, 390) }
	local PCS = { Vector2.new(1024, 768), Vector2.new(1280, 720), Vector2.new(1920, 1080) }
	local ALL = table.clone(PHONES)
	for _, screen in PCS do
		table.insert(ALL, screen)
	end
	local TEXT_SCALES = { 1, 1.15, 1.3, 1.45 } -- Medium, Large, Larger, Largest (UI.PreferredTextScale)
	local LARGEST = UI.PreferredTextScale.Largest

	local function classOf(screen: Vector2): string
		return Layout.layoutClass(screen.X, screen.Y)
	end
	local function overlaps(a: any, b: any): boolean
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end

	t.test("text estimate: greedy word wrap, long words break, empty text has no lines", function()
		local em = HudFormat.TEXT_METRICS.bodyEm
		-- A line exactly 10 characters wide at 10 px.
		local line = 10 * 10 * em
		expect.equal(HudFormat.textLines("", 10, line), 0)
		expect.equal(HudFormat.textLines("aaaa bbbb", 10, line), 1) -- 9 characters
		expect.equal(HudFormat.textLines("aaaa bbbbbb", 10, line), 2) -- 11: the second word wraps
		expect.equal(HudFormat.textLines("aaaaaaaaaaaaaaaaaaaaaaaaa", 10, line), 3) -- 25 characters break across 3 lines
		expect.equal(HudFormat.textLines("aa\nbb", 10, line), 2) -- a line break
		local lineHeight = HudFormat.TEXT_METRICS.lineHeight
		expect.equal(HudFormat.textHeight("aaaa bbbbbb", 10, line), math.ceil(2 * 10 * lineHeight))
		expect.near(HudFormat.textWidth("abc", 10), 3 * 10 * em, 1e-9)
		expect.near(HudFormat.textWidth("abc", 10, "title"), 3 * 10 * HudFormat.TEXT_METRICS.titleEm, 1e-9)
		-- "·" is one character, not two bytes.
		expect.equal(HudFormat.textWidth("Lv 1 · Soft", 10), HudFormat.textWidth("Lv 1 x Soft", 10))
		expect.equal(HudFormat.kindPx("Small", LARGEST), math.floor(UI.TextSize.Small * LARGEST + 0.5))
		expect.equal(HudFormat.kindPx("Small", 0 / 0), UI.TextSize.Small)
	end)

	t.test("left side: on PCs it fits at every text size; a PC at the default size keeps the design", function()
		for _, screen in PCS do
			for _, ts in TEXT_SCALES do
				local plan = HudFormat.leftColumnPlan(screen, classOf(screen), ts)
				local label = `{screen.X}x{screen.Y} text {ts}: {plan.grip} / {plan.tiles} bottom {plan.bottom}`
				if not plan.fits then
					error("the left side does not fit: " .. label)
				end
				expect.falsy(plan.narrow)
				expect.near(plan.limit, plan.canvas.Y - COLUMN.edge, 1e-3)
				expect.truthy(plan.bottom <= plan.canvas.Y - COLUMN.edge + 1e-6)
				expect.truthy(plan.grip ~= "hidden")
			end
			-- Spec "regular layout — match redesign-check.jpg": the regular Grip card and one tile column.
			local default = HudFormat.leftColumnPlan(screen, classOf(screen), 1)
			if screen.Y >= 720 then
				expect.equal(default.grip, "regular")
				expect.equal(default.tiles, "column")
				expect.equal(default.columns, 1)
				expect.equal(default.rows, 5)
			end
		end
	end)

	t.test(
		"left side (lobby HUD 2026-10-11): phones keep the compact Grip card and two tile columns, like PCs",
		function()
			for _, screen in PHONES do
				for _, ts in TEXT_SCALES do
					local plan = HudFormat.leftColumnPlan(screen, "compact", ts)
					expect.truthy(plan.narrow)
					expect.equal(plan.grip, "compact")
					-- The line is still the top of the lower-left thumbstick zone (§11.2, §17.7 L5); the two tile columns may
					-- reach past it (the user's choice: the joystick still starts in the lower-left corner below them).
					expect.near(plan.limit, plan.canvas.Y * UI.Grip.leftColumnMaxFraction, 1e-3)
					expect.near(plan.limit, plan.canvas.Y * (1 - TOUCH.thumbstickZoneHeight), 1e-3)
					expect.equal(plan.tiles, "grid")
					expect.equal(plan.columns, 2)
					expect.equal(plan.rows, 3)
					-- On these phones the coin capsule and the Grip card side by side would reach the top-middle CTA: stacked.
					expect.equal(plan.left, "stack")
					-- Never wider than the screen.
					expect.truthy(COLUMN.edge + plan.tilesWidth <= plan.canvas.X - COLUMN.edge + 1e-6)
					-- The tiles are touch targets (>= 44 px on screen).
					expect.truthy(plan.tileHeight * plan.scale >= TOUCH.minTargetFloor)
					expect.truthy(plan.tileWidth * plan.scale >= TOUCH.minTargetFloor)
				end
			end
			-- A short, wide compact window (1280×480): side by side keeps the CTA clear, so the capsule and the card share a
			-- row (and the left side then ends above the line).
			local wide = HudFormat.leftColumnPlan(Vector2.new(1280, 480), "compact", 1)
			expect.equal(wide.left, "beside")
			expect.equal(wide.tiles, "grid")
			expect.truthy(wide.fits)
			local ctaLeft = (wide.canvas.X - HudFormat.ctaWidth(true, 1)) / 2
			expect.truthy(COLUMN.edge + wide.width + COLUMN.rowGap <= ctaLeft + 1e-6)
		end
	)

	t.test("left side: touch on a regular screen keeps the thumbstick zone clear too", function()
		for _, screen in PCS do
			for _, ts in TEXT_SCALES do
				local plan = HudFormat.leftColumnPlan(screen, classOf(screen), ts, { touch = true })
				expect.truthy(plan.narrow)
				expect.near(plan.limit, plan.canvas.Y * UI.Grip.leftColumnMaxFraction, 1e-3)
				if ts == 1 then
					if not plan.fits then
						error(`{screen.X}x{screen.Y}: the left side reaches the thumbstick zone ({plan.bottom})`)
					end
				end
				if plan.fits then
					expect.truthy(plan.bottom <= plan.limit + 1e-6)
				end
			end
		end
	end)

	t.test("left side: the first layout that fits, else the shortest; the Grip card never hides for it", function()
		for _, screen in ALL do
			for _, ts in TEXT_SCALES do
				for _, touch in { false, true } do
					local class = classOf(screen)
					local parts = { touch = touch }
					local layouts = HudFormat.columnLayouts(screen, class, ts, parts)
					-- Phones: side by side only when it keeps the top-middle CTA clear (not on these phones).
					expect.truthy(#layouts >= (if class == "compact" then 1 else 2))
					for _, layout in layouts do
						expect.truthy(layout.grip == "regular" or layout.grip == "compact")
						expect.truthy(layout.gripHeight > 0)
						-- The parts add up: the edge, the capsule and the card (stacked, or side by side: the taller of
						-- the two), the gap, the tiles (phones: tight gaps). Only the compact card goes beside.
						local innerGap, tilesGap = HudFormat.leftGaps(class == "compact", layout.grip)
						local leftBottom = if layout.left == "beside"
							then COLUMN.edge + math.max(layout.pillHeight, layout.gripHeight)
							else COLUMN.edge + layout.pillHeight + innerGap + layout.gripHeight
						expect.truthy(layout.left == "stack" or layout.grip == "compact")
						expect.near(layout.leftBottom, leftBottom, 1e-6)
						expect.near(layout.tilesTop, layout.leftBottom + tilesGap, 1e-6)
						expect.near(layout.bottom, layout.tilesTop + layout.tilesHeight, 1e-6)
						expect.truthy(layout.tilesTop > layout.leftBottom)
					end
					if class == "compact" then
						expect.equal(layouts[1].grip, "compact")
						expect.equal(layouts[1].tiles, "grid")
						expect.equal(layouts[1].left, "stack")
					else
						expect.equal(layouts[1].grip, "regular")
						expect.equal(layouts[1].tiles, "column")
						expect.equal(layouts[1].left, "stack")
					end
					local plan = HudFormat.leftColumnPlan(screen, class, ts, parts)
					local firstFit = nil
					local shortest = layouts[1]
					for _, layout in layouts do
						if firstFit == nil and layout.fits then
							firstFit = layout
						end
						if layout.bottom < shortest.bottom then
							shortest = layout
						end
					end
					local expected = firstFit or shortest
					if not HudFormat.samePlan(plan, expected) or plan.bottom ~= expected.bottom then
						error(
							`{screen.X}x{screen.Y} text {ts}: the plan ({plan.grip}, {plan.tiles}) is not the first fit `
								.. `/ the shortest ({expected.grip}, {expected.tiles})`
						)
					end
					expect.equal(plan.fits, firstFit ~= nil)
				end
			end
		end
	end)

	t.test("left side: without the Grip card it takes no room; fewer tiles; the plan is stable", function()
		for _, screen in ALL do
			local class = classOf(screen)
			local noGrip = HudFormat.leftColumnPlan(screen, class, 1, { grip = false })
			expect.equal(noGrip.grip, "hidden")
			expect.equal(noGrip.gripHeight, 0)
			expect.near(noGrip.leftBottom, COLUMN.edge + noGrip.pillHeight, 1e-6)
			local both = HudFormat.leftColumnPlan(screen, class, 1)
			expect.truthy(noGrip.bottom <= both.bottom)
			-- Two tiles registered: a shorter left side.
			local two = HudFormat.leftColumnPlan(screen, class, 1, { tiles = 2 })
			expect.truthy(two.tilesHeight <= both.tilesHeight)
			local none = HudFormat.leftColumnPlan(screen, class, 1, { tiles = 0 })
			expect.equal(none.tilesHeight, 0)
			expect.near(none.bottom, none.leftBottom, 1e-6)
		end
		local a = HudFormat.leftColumnPlan(Vector2.new(667, 375), "compact", 1.3)
		local b = HudFormat.leftColumnPlan(Vector2.new(667, 375), "compact", 1.3)
		expect.truthy(HudFormat.samePlan(a, b))
		expect.falsy(HudFormat.samePlan(a, HudFormat.leftColumnPlan(Vector2.new(1920, 1080), "regular", 1)))
		expect.truthy(HudFormat.samePlan(nil, nil))
		expect.falsy(HudFormat.samePlan(a, nil))
		-- No size yet (the HUD at boot): the fallback screen, never an error.
		local boot = HudFormat.leftColumnPlan(Vector2.zero, "regular", nil)
		expect.truthy(boot.fits)
		-- Foam fix: how Hud_Left holds its items is part of the layout (both at the 0.85 phone scale).
		local stacked = HudFormat.leftColumnPlan(Vector2.new(844, 312), "compact", 1, { screenHeight = 370 })
		local beside = HudFormat.leftColumnPlan(Vector2.new(1280, 480), "compact", 1)
		expect.equal(stacked.left, "stack")
		expect.equal(beside.left, "beside")
		expect.equal(stacked.scale, beside.scale)
		expect.falsy(HudFormat.samePlan(stacked, beside))
	end)

	t.test("thumbstick zone: a share of the whole screen, its bottom at the HUD's bottom (foam fix)", function()
		local canvas = Vector2.new(993, 367)
		local scale = 0.85
		-- Without the screen's height it is the HUD's own share (as before).
		local own = HudFormat.thumbstickZone(canvas, nil, scale)
		expect.near(own.h, canvas.Y * TOUCH.thumbstickZoneHeight, 1e-6)
		expect.near(own.y + own.h, canvas.Y, 1e-6)
		expect.near(own.w, canvas.X * TOUCH.thumbstickZoneWidth, 1e-6)
		expect.equal(own.x, 0)
		-- The whole screen is taller by the top bar inset the HUD leaves out: the zone grows by its share of it.
		local screen = canvas.Y * scale + 58
		local whole = HudFormat.thumbstickZone(canvas, screen, scale)
		expect.near(whole.h, TOUCH.thumbstickZoneHeight * screen / scale, 1e-6)
		expect.near(whole.y + whole.h, canvas.Y, 1e-6)
		expect.truthy(whole.y < own.y)
		-- Never smaller than the HUD's own share; bad numbers fall back to it.
		expect.near(HudFormat.thumbstickZone(canvas, 10, scale).h, own.h, 1e-6)
		expect.near(HudFormat.thumbstickZone(canvas, 0 / 0, scale).h, own.h, 1e-6)
	end)

	t.test(
		"phones (lobby HUD 2026-10-11): stacked like the PC, two tile columns, the top middle left to the Duel CTA",
		function()
			-- SD_Hud's size and the whole screen's height (px): Studio's phone emulator (a 58 px top bar inset) and a phone.
			local cases = {
				{ hud = Vector2.new(844, 312), screen = 370 },
				{ hud = Vector2.new(844, 332), screen = 390 },
				{ hud = Vector2.new(667, 297), screen = 355 },
				{ hud = Vector2.new(667, 317), screen = 375 },
			}
			for _, case in cases do
				local plan = HudFormat.leftColumnPlan(case.hud, "compact", 1, {
					touch = true,
					screenHeight = case.screen,
				})
				local zone = HudFormat.thumbstickZone(plan.canvas, case.screen, plan.scale)
				local label = `{case.hud.X}x{case.hud.Y} (screen {case.screen}): {plan.left} / {plan.tiles}`
				expect.near(plan.limit, math.min(plan.canvas.Y * UI.Grip.leftColumnMaxFraction, zone.y), 1e-6)
				expect.equal(plan.grip, "compact")
				expect.equal(plan.left, "stack")
				expect.equal(plan.tiles, "grid")
				expect.equal(plan.columns, 2)
				local innerGap = HudFormat.leftGaps(true, "compact")
				expect.near(plan.leftBottom, COLUMN.edge + plan.pillHeight + innerGap + plan.gripHeight, 1e-6)
				-- The Duel CTA (its widest, queued) fits at the top between the left side and the Settings tile.
				local ctaSize = Vector2.new(HudFormat.ctaWidth(true, 1), COLUMN.ctaCompactHeight)
				local left = { x = COLUMN.edge, y = COLUMN.edge, w = plan.width, h = plan.leftBottom - COLUMN.edge }
				local tiles = HudFormat.badgeReachRect({
					x = COLUMN.edge,
					y = plan.tilesTop,
					w = plan.tilesWidth,
					h = plan.tilesHeight,
				})
				local settings = {
					x = plan.canvas.X - COLUMN.edge - COLUMN.settingsSize,
					y = COLUMN.edge,
					w = COLUMN.settingsSize,
					h = COLUMN.settingsSize,
				}
				local place = HudFormat.ctaPlacement({
					canvas = plan.canvas,
					size = ctaSize,
					blockers = { left, tiles, settings },
				})
				if not place.fits then
					error("the Duel CTA has no room at the top: " .. label)
				end
				local cta = { x = place.x, y = place.y, w = ctaSize.X, h = ctaSize.Y }
				for _, rect in { left, tiles, settings } do
					expect.falsy(overlaps(cta, rect))
				end
				-- The tiles stay touch targets (>= 44 px on screen) with their labels on one line.
				expect.truthy(plan.tileHeight * plan.scale >= TOUCH.minTargetFloor)
				expect.truthy(plan.tileWidth * plan.scale >= TOUCH.minTargetFloor)
			end
		end
	)

	-- Foam fix 2 (2026-10-09): a tile's count badge hangs past the tile's top-right corner; on phones the tight 6 px gap
	-- put the Squishies "3" on the coin capsule's outline.
	t.test("the tiles keep a count badge's reach plus air under Hud_Left (foam fix 2)", function()
		local CountBadge = t.requireClient("UI/Components/CountBadge")
		local Theme = t.requireClient("UI/Theme")
		-- The badge: CountBadge.SIZE_PX tall, centred Button's BADGE_INSET (5) inside the tile's corner, a bar outline.
		expect.truthy(COLUMN.badgeReach >= CountBadge.SIZE_PX / 2 - 5 + Theme.Stroke.bar)
		for _, compact in { true, false } do
			for _, grip in { "compact", "hidden" } do
				local _, toTiles = HudFormat.leftGaps(compact, grip)
				if not (toTiles >= COLUMN.badgeReach + 3) then
					error(`compact {compact}, grip {grip}: the tiles start {toTiles} under Hud_Left`)
				end
			end
		end
		-- The capsule and the compact card keep their tight gap; the regular card keeps the gap of its Upgrade tab.
		expect.equal((HudFormat.leftGaps(true, "compact")), COLUMN.gap)
		local _, regular = HudFormat.leftGaps(false, "regular")
		expect.equal(regular, COLUMN.tilesGap)
	end)

	-- Foam fix 2: the coins "+N" starts beside the capsule's middle and rises only as far as the HUD's top (it floated
	-- up from the capsule's top into Roblox's top bar).
	t.test("the coins '+N' rises at most floatPx and never past the HUD's top", function()
		local float = Config.UI.motion.coinCounter.floatPx
		local pill = HudFormat.pillHeight(1, 0.85)
		local label = HudFormat.kindPx("HudNumber", 1) * HudFormat.TEXT_METRICS.lineHeight
		local rise = HudFormat.gainRise(pill, label)
		expect.truthy(rise > 0 and rise <= float)
		-- Its top at the end of the rise: the capsule's middle less half the label less the rise.
		expect.truthy(COLUMN.edge + pill / 2 - label / 2 - rise >= -1e-6)
		expect.equal(HudFormat.gainRise(pill, 200), 0) -- already reaching the top: no rise
		expect.equal(HudFormat.gainRise(1000, 10), float)
		expect.equal(HudFormat.gainRise(0 / 0, 10), 0)
	end)

	-- Foam fix 3: on phones the Grip card sits right of the capsule ("beside"), so the "+N" printed over it. There it sits
	-- on the capsule's top edge over the number's right end, in the small display kind, inside the HUD (Roblox's top bar
	-- is right above it); a stacked column (PCs) keeps fix 2's spot beside the capsule's middle.
	t.test("the coins '+N' sits beside a stacked capsule, and on a phone's capsule clear of the Grip card", function()
		local float = Config.UI.motion.coinCounter.floatPx
		local metrics = HudFormat.TEXT_METRICS
		for _, textScale in { 1, 1.45 } do
			local pill = HudFormat.pillHeight(textScale, 1.25)
			local spot = HudFormat.gainSpot(false, pill, textScale)
			expect.equal(spot.kind, "HudNumber")
			expect.equal(spot.anchorX, 0)
			expect.truthy(spot.x > 0) -- its left edge right of the capsule
			expect.equal(spot.yScale, 0.5)
			expect.equal(spot.y, 0)
			local label = HudFormat.kindPx("HudNumber", textScale) * metrics.lineHeight
			expect.near(spot.rise, HudFormat.gainRise(pill, label), 1e-6)
		end
		for _, textScale in { 1, 1.15, 1.3, 1.45 } do
			local pill = HudFormat.pillHeight(textScale, 0.85)
			local spot = HudFormat.gainSpot(true, pill, textScale)
			local label = HudFormat.kindPx(spot.kind, textScale) * metrics.lineHeight
			local where = `text scale {textScale}`
			-- Its right edge at the number's right end, inside the capsule (the Grip card starts right of it).
			expect.equal(spot.anchorX, 1)
			expect.truthy(spot.x <= -COLUMN.capsulePadRight)
			-- On the capsule's top edge, or just under it, and never above the HUD's top while it rises.
			expect.equal(spot.yScale, 0)
			expect.truthy(spot.y >= 0)
			expect.truthy(spot.rise >= 0 and spot.rise <= float)
			if not (COLUMN.edge + spot.y - label / 2 - spot.rise >= -1e-6) then
				error("the '+N' reaches above the HUD's top at " .. where)
			end
			-- At least the 13 px minimum at the phone scale.
			expect.truthy(HudFormat.kindPx(spot.kind, textScale) * 0.85 >= Config.UI.minTextSize)
		end
		local pill = HudFormat.pillHeight(1, 0.85)
		local spot = HudFormat.gainSpot(true, pill, 1)
		expect.equal(spot.kind, "Chip")
		expect.equal(spot.y, 0) -- centred on the edge at the standard text size
		-- A gain is never more than the total the capsule shows, so its "+N" ends inside the capsule's left end.
		for _, n in { 5, 480, 12450, 999999 } do
			local gain = HudFormat.textWidth(HudFormat.gainText(n), HudFormat.kindPx(spot.kind, 1), "title")
			local total = HudFormat.textWidth(HudFormat.coinsText(n), HudFormat.kindPx("HudNumber", 1), "title")
			expect.truthy(gain <= total + COLUMN.capsuleTextGap)
		end
		local bad = HudFormat.gainSpot(true, 0 / 0, 0 / 0)
		expect.truthy(bad.rise >= 0 and bad.rise <= float)
	end)

	-- Foam fix 2: the toast column keeps beside the tile row's box plus a badge's reach (badgeReachRect, the box
	-- HudController registers for it); beside the bare row, the Daily "1" hanging past the last tile touched a toast.
	t.test("the toast column keeps air beside a count badge hanging past the tile row (badgeReachRect)", function()
		local NotifyFormat = t.requireClient("UI/NotifyFormat")
		local tiles = { x = 12, y = 78, w = 439, h = 58 } -- the phone's tile row at 844×390 (base px)
		local reach = HudFormat.badgeReachRect(tiles)
		expect.deepEqual(reach, {
			x = tiles.x,
			y = tiles.y - COLUMN.badgeReach,
			w = tiles.w + COLUMN.badgeReach,
			h = tiles.h + COLUMN.badgeReach,
		})
		local column = NotifyFormat.toastColumn({
			canvas = Vector2.new(993, 367),
			width = 420,
			minWidth = 280,
			height = 50,
			defaultTop = 110,
			gap = 8,
			edge = 12,
			above = {},
			beside = { reach },
		})
		-- The badge's outline ends badgeReach right of the row; the column starts at least badgeAir right of it.
		expect.truthy(column.x >= tiles.x + tiles.w + COLUMN.badgeReach + COLUMN.badgeAir)
	end)

	t.test("the compact Grip card is as wide as its line, between its minimum and the regular card", function()
		local short = HudFormat.gripCompactWidth("Lv 1 · Soft Grip", 1)
		local long = HudFormat.gripCompactWidth(HudFormat.worstCaseTexts().gripCompact, 1)
		expect.truthy(short >= COLUMN.gripCompactMinWidth and short <= COLUMN.cardWidth)
		expect.truthy(long >= short)
		expect.truthy(long <= COLUMN.cardWidth)
		-- The line and the card's padding fit (the estimate is on the roomy side).
		local line = HudFormat.textWidth("Lv 1 · Soft Grip", HudFormat.kindPx("Small", 1))
		expect.truthy(short >= line + 2 * (COLUMN.cardPadding + 4))
		expect.equal(HudFormat.gripCompactWidth("", 1), COLUMN.gripCompactMinWidth)
		expect.equal(HudFormat.gripCompactWidth(string.rep("W", 80), LARGEST), COLUMN.cardWidth)
	end)

	t.test("tiles: one shared size, at least the tile size, as wide as the widest label needs", function()
		for _, ts in TEXT_SCALES do
			for _, compact in { false, true } do
				local w, h = HudFormat.tileSize(compact, ts)
				local base = if compact then COLUMN.tileSizeCompact else COLUMN.tileSize
				expect.truthy(w >= base and h >= base)
				for _, label in HudFormat.worstCaseTexts().tiles do
					local needed = HudFormat.textWidth(label, HudFormat.kindPx("Chip", ts), "title")
					expect.truthy(w >= needed + 2 * COLUMN.tilePadding)
				end
			end
		end
		-- Arrangements: a column, two columns, a row that wraps at the width.
		local function box(mode: string, maxWidth: number): { number }
			return { HudFormat.tilesBox(mode, 5, 80, 80, maxWidth) }
		end
		local gap = COLUMN.tileGap
		expect.deepEqual(box("column", 1000), { 1, 5, 80, 5 * 80 + 4 * gap })
		expect.deepEqual(box("grid", 1000), { 2, 3, 2 * 80 + gap, 3 * 80 + 2 * gap })
		expect.deepEqual(box("row", 1000), { 5, 1, 5 * 80 + 4 * gap, 80 })
		expect.deepEqual(box("row", 3 * 80 + 2 * gap), { 3, 2, 3 * 80 + 2 * gap, 2 * 80 + gap })
		expect.deepEqual({ HudFormat.tilesBox("row", 0, 80, 80, 1000) }, { 0, 0, 0, 0 })
	end)

	t.test("the compact Grip card: one row <= 40 base, one tap target >= the touch minimum (>= 44 px)", function()
		for _, height in { 375, 720, 1080 } do
			local scale = Layout.uiScale(height)
			for _, ts in TEXT_SCALES do
				local row = HudFormat.gripCompactRowHeight(ts)
				expect.truthy(row <= UI.Grip.compactRowMaxHeight)
				local card = HudFormat.gripCardHeight("compact", ts, scale)
				expect.truthy(card >= Layout.touchBase(TOUCH.minTarget, scale))
				expect.truthy(card * scale >= TOUCH.minTargetFloor)
				expect.truthy(card >= row)
			end
		end
		expect.equal(HudFormat.gripCardHeight("hidden", 1, 1), 0)
		-- The regular card grows with the text and is never shorter than its level tile.
		expect.truthy(HudFormat.gripCardHeight("regular", LARGEST, 1) > HudFormat.gripCardHeight("regular", 1, 1))
		expect.truthy(
			HudFormat.gripCardHeight("regular", 1, 1)
				>= HudFormat.levelTileHeight(1) + COLUMN.cardPadTop + COLUMN.cardPadBottom
		)
	end)

	t.test(
		"worst-case texts: every onboarding step in every input and policy, the longest Grip lines, the tiles",
		function()
			local texts = HudFormat.worstCaseTexts()
			expect.equal(#texts.onboarding, #Config.Onboarding.Steps * 3 * 2)
			for _, entry in texts.onboarding do
				expect.truthy(type(entry.text) == "string" and entry.text ~= "")
			end
			-- §11.8: the skip link is "Skip tutorial" (it ends the whole tutorial), never the short "Skip".
			expect.equal(texts.skip, Strings.onboarding.skip)
			expect.equal(texts.gotIt, Strings.common.gotIt)
			expect.equal(texts.gripLevel, tostring(Config.Grip.maxLevel))
			expect.truthy(string.find(texts.gripCompact, tostring(Config.Grip.maxLevel), 1, true) ~= nil)
			expect.equal(texts.gripBadge, Strings.grip.upgradeBadge)
			expect.truthy(#texts.coins >= #Strings.common.loading)
			expect.equal(#texts.tiles, 5)
			expect.equal(texts.tiles[1], Strings.hud.nav.squishies)
			expect.equal(HudFormat.worstCaseTexts(), texts) -- computed once
		end
	)

	t.test("coach card (UI overhaul): a bottom-middle prompt, clear of the groups and the touch zones", function()
		local canvas = Vector2.new(1422, 800)
		local left = { x = 12, y = 12, w = 270, h = 200 }
		local right = { x = 1154, y = 12, w = 256, h = 160 }
		local bottom = canvas.Y - COLUMN.edge - COLUMN.coachBottomGap
		local function at(height: number): (number) -> number
			return function(_: number): number
				return height
			end
		end
		-- Nothing near the bottom: the preferred width, centred, its bottom edge at the gap.
		local open = HudFormat.coachBottomPlacement({ canvas = canvas, blockers = { left, right }, heightAt = at(70) })
		expect.truthy(open.fits)
		expect.equal(open.width, COLUMN.coachWidth)
		expect.near(open.y + open.height, bottom, 1e-6)
		expect.near(open.x + open.width / 2, canvas.X / 2, 1e-6)
		-- A phone: the thumbstick zone (lower left) and the jump button (lower right) narrow the band; never over them.
		local phone = Vector2.new(993, 459)
		local zone = { x = 0, y = 252, w = 397, h = 207 }
		local jump = { x = 850, y = 330, w = 130, h = 120 }
		local squeezed = HudFormat.coachBottomPlacement({
			canvas = phone,
			blockers = { zone, jump },
			heightAt = function(width: number): number
				return if width >= 440 then 60 else 84
			end,
		})
		expect.truthy(squeezed.fits)
		local box = { x = squeezed.x, y = squeezed.y, w = squeezed.width, h = squeezed.height }
		expect.falsy(overlaps(box, zone))
		expect.falsy(overlaps(box, jump))
		expect.truthy(squeezed.width >= COLUMN.coachMinWidth)
		-- No room at all: centred anyway, fits = false.
		local crowded = HudFormat.coachBottomPlacement({
			canvas = Vector2.new(700, 400),
			blockers = { { x = 0, y = 200, w = 380, h = 200 }, { x = 400, y = 200, w = 300, h = 200 } },
			heightAt = at(70),
		})
		expect.falsy(crowded.fits)
		expect.near(crowded.x + crowded.width / 2, 350, 1e-6)
	end)

	t.test("coach card: top centre between the HUD groups, above the toasts; wider when the text needs it", function()
		local canvas = Vector2.new(1422, 800)
		local left = { x = 12, y = 12, w = 270, h = 200 }
		local right = { x = 1154, y = 12, w = 256, h = 160 }
		local line = COLUMN.toastTop - COLUMN.rowGap
		-- A short text: the preferred width, centred.
		local short = HudFormat.coachPlacement({
			canvas = canvas,
			blockers = { left, right },
			heightAt = function(_: number): number
				return 70
			end,
		})
		expect.truthy(short.fits)
		expect.equal(short.y, COLUMN.edge)
		expect.equal(short.width, COLUMN.coachWidth)
		expect.near(short.x + short.width / 2, canvas.X / 2, 1e-6)
		expect.truthy(short.y + short.height <= line)
		-- Too tall at the preferred width: as wide as the room between the groups.
		local tall = HudFormat.coachPlacement({
			canvas = canvas,
			blockers = { left, right },
			heightAt = function(width: number): number
				return if width > 600 then 80 else 120
			end,
		})
		expect.truthy(tall.fits)
		expect.near(tall.x, left.x + left.w + COLUMN.rowGap, 1e-6)
		expect.near(tall.x + tall.width, right.x - COLUMN.rowGap, 1e-6)
		-- Never over a group, even when nothing ends above the line (fits = false).
		local never = HudFormat.coachPlacement({
			canvas = canvas,
			blockers = { left, right },
			heightAt = function(_: number): number
				return 200
			end,
		})
		expect.falsy(never.fits)
		expect.falsy(overlaps({ x = never.x, y = never.y, w = never.width, h = never.height }, left))
		expect.falsy(overlaps({ x = never.x, y = never.y, w = never.width, h = never.height }, right))
		-- A group below the band (the tiles) does not narrow it.
		local tiles = { x = 12, y = 240, w = 900, h = 84 }
		local free = HudFormat.coachPlacement({
			canvas = canvas,
			blockers = { left, right, tiles },
			heightAt = function(_: number): number
				return 70
			end,
		})
		expect.equal(free.width, COLUMN.coachWidth)
		-- No room between the groups: the screen's centre, fits = false.
		local crowded = HudFormat.coachPlacement({
			canvas = Vector2.new(700, 400),
			blockers = { { x = 12, y = 12, w = 330, h = 100 }, { x = 400, y = 12, w = 288, h = 100 } },
			heightAt = function(_: number): number
				return 70
			end,
		})
		expect.falsy(crowded.fits)
		-- Lobby HUD (spec 2026-10-11): right under the Duel CTA (`top`); the band keeps its height under it.
		local top = COLUMN.edge + COLUMN.ctaHeight + COLUMN.rowGap
		local under = HudFormat.coachPlacement({
			canvas = canvas,
			top = top,
			blockers = { left, right },
			heightAt = function(_: number): number
				return 70
			end,
		})
		expect.truthy(under.fits)
		expect.equal(under.y, top)
		expect.equal(under.width, COLUMN.coachWidth)
		expect.near(under.x + under.width / 2, canvas.X / 2, 1e-6)
		local wide = HudFormat.coachPlacement({
			canvas = canvas,
			top = top,
			blockers = { left, right },
			heightAt = function(width: number): number
				return if width > 600 then line - COLUMN.edge else line - COLUMN.edge + 1
			end,
		})
		expect.truthy(wide.fits)
		expect.near(wide.x, left.x + left.w + COLUMN.rowGap, 1e-6)
		expect.near(wide.x + wide.width, right.x - COLUMN.rowGap, 1e-6)
	end)

	t.test(
		"coach card: with the real texts it keeps its band under the CTA on 16:9 PCs at the default text size",
		function()
			local texts = HudFormat.worstCaseTexts()
			for _, screen in PCS do
				-- 1024×768 is narrow enough that the longest step may be taller than the band (checked: never over a group).
				local mustFit = screen.X / screen.Y > 1.5
				local scale = Layout.uiScale(screen.Y)
				local canvas = Vector2.new(screen.X / scale, screen.Y / scale)
				local plan = HudFormat.leftColumnPlan(screen, classOf(screen), 1)
				local left = { x = COLUMN.edge, y = COLUMN.edge, w = plan.width, h = plan.leftBottom - COLUMN.edge }
				local right = {
					x = canvas.X - COLUMN.edge - COLUMN.trackerWidth,
					y = COLUMN.edge,
					w = COLUMN.trackerWidth,
					h = 160,
				}
				for _, entry in texts.onboarding do
					local button = if entry.gotIt then texts.gotIt else texts.skip
					local place = HudFormat.coachPlacement({
						canvas = canvas,
						top = COLUMN.edge + COLUMN.ctaHeight + COLUMN.rowGap,
						blockers = { left, right },
						heightAt = function(width: number): number
							return HudFormat.coachHeight(width, 1, scale, entry.text, button, false)
						end,
					})
					if mustFit and not place.fits then
						error(`{screen.X}x{screen.Y}: the coach card is taller than its band with "{entry.text}"`)
					end
					local rect = { x = place.x, y = place.y, w = place.width, h = place.height }
					expect.falsy(overlaps(rect, left))
					expect.falsy(overlaps(rect, right))
					-- Its button is a touch target.
					expect.truthy(place.height >= Layout.touchBase(TOUCH.minTarget, scale))
				end
			end
			-- A button wider than the card leaves no room for the text: never chosen.
			expect.equal(HudFormat.coachHeight(100, 1, 1, "Hello there", texts.skip, false), math.huge)
		end
	)

	t.test("the Duel CTA (lobby HUD 2026-10-11): at the top middle, moved only as far as the groups need", function()
		local canvas = Vector2.new(1422, 800)
		local size = Vector2.new(COLUMN.ctaWidth, COLUMN.ctaHeight)
		local left = { x = 12, y = 12, w = 270, h = 200 }
		local right = { x = 1154, y = 12, w = 256, h = 160 }
		-- Room between the groups: centred, COLUMN.edge from the top.
		local centred = HudFormat.ctaPlacement({ canvas = canvas, size = size, blockers = { left, right } })
		expect.truthy(centred.fits)
		expect.equal(centred.y, COLUMN.edge)
		expect.near(centred.x + size.X / 2, canvas.X / 2, 1e-6)
		-- A left group reaching past the centred spot: moved right just enough, a row gap from it.
		local wideLeft = { x = 12, y = 12, w = 620, h = 64 }
		local moved = HudFormat.ctaPlacement({ canvas = canvas, size = size, blockers = { wideLeft, right } })
		expect.truthy(moved.fits)
		expect.near(moved.x, wideLeft.x + wideLeft.w + COLUMN.rowGap, 1e-6)
		-- A group lower down (the tiles under the column) never moves it.
		local tiles = { x = 12, y = 240, w = 900, h = 84 }
		local below = HudFormat.ctaPlacement({ canvas = canvas, size = size, blockers = { left, right, tiles } })
		expect.near(below.x, centred.x, 1e-6)
		-- No room between the groups: the screen's centre, fits = false.
		local crowded = HudFormat.ctaPlacement({
			canvas = Vector2.new(700, 400),
			size = size,
			blockers = { { x = 12, y = 12, w = 330, h = 100 }, { x = 400, y = 12, w = 288, h = 100 } },
		})
		expect.falsy(crowded.fits)
		expect.near(crowded.x, (700 - size.X) / 2, 1e-6)

		-- Every screen, with the real left side (sized for its widest texts), the tiles' badge reach and the top-right
		-- group: the widest (queued) CTA fits at the top over none of them; on PCs at every text size, centred.
		for _, screen in ALL do
			local class = classOf(screen)
			local compact = class == "compact"
			local scales: { number } = if compact then { 1 } else TEXT_SCALES
			for _, ts in scales do
				local plan = HudFormat.leftColumnPlan(screen, class, ts)
				local c = plan.canvas
				local ctaSize = Vector2.new(
					HudFormat.ctaWidth(compact, ts),
					if compact then COLUMN.ctaCompactHeight else COLUMN.ctaHeight
				)
				local column = { x = COLUMN.edge, y = COLUMN.edge, w = plan.width, h = plan.leftBottom - COLUMN.edge }
				local tileBox = HudFormat.badgeReachRect({
					x = COLUMN.edge,
					y = plan.tilesTop,
					w = plan.tilesWidth,
					h = plan.tilesHeight,
				})
				local rightWidth = if compact then COLUMN.settingsSize else COLUMN.trackerWidth
				local rightGroup = {
					x = c.X - COLUMN.edge - rightWidth,
					y = COLUMN.edge,
					w = rightWidth,
					h = if compact then COLUMN.settingsSize else COLUMN.settingsSize + COLUMN.rowGap + 100,
				}
				local place = HudFormat.ctaPlacement({
					canvas = c,
					size = ctaSize,
					blockers = { column, tileBox, rightGroup },
				})
				local label = `{screen.X}x{screen.Y} text {ts}: x {place.x}`
				if not place.fits then
					error("the Duel CTA has no room at the top: " .. label)
				end
				local cta = { x = place.x, y = place.y, w = ctaSize.X, h = ctaSize.Y }
				for _, rect in { column, tileBox, rightGroup } do
					if overlaps(cta, rect) then
						error("the Duel CTA covers a HUD group: " .. label)
					end
				end
				if not compact then
					expect.near(place.x + ctaSize.X / 2, c.X / 2, 1e-6)
				end
			end
		end
	end)

	t.test("the Duel CTA's widest width (ctaWidth): its queued texts, at least the design's width on PCs", function()
		local Button = t.requireClient("UI/Components/Button")
		expect.equal(COLUMN.ctaPadding, Button.style("cta").paddingX)
		local clock = Strings.format(Strings.hud.duelSearchingTime, { time = "88:88" })
		for _, ts in TEXT_SCALES do
			expect.truthy(HudFormat.ctaWidth(false, ts) >= COLUMN.ctaWidth)
			-- The queued clock line, the icon, the gap and the paddings fit.
			local line = HudFormat.textWidth(clock, HudFormat.kindPx("Chip", ts), "title")
			local least = COLUMN.ctaCompactIconPx + COLUMN.ctaLineGap + line + 2 * COLUMN.ctaPadding
			expect.truthy(HudFormat.ctaWidth(true, ts) >= least)
		end
		expect.truthy(HudFormat.ctaWidth(true, LARGEST) > HudFormat.ctaWidth(true, 1))
	end)

	t.test(
		"gamepad links: Down walks the tile column; the Duel CTA sits between the left column and Settings",
		function()
			expect.deepEqual(
				HudFormat.focusLinks({
					left = { "coins", "grip" },
					tiles = { "t1", "t2", "t3" },
					tileColumns = 1,
					right = { "settings", "tracker" },
					coach = "coach",
					cta = "cta",
				}),
				{
					coins = { down = "grip", right = "cta" },
					grip = { up = "coins", down = "t1", right = "cta" },
					t1 = { up = "grip", down = "t2", right = "cta" },
					t2 = { up = "t1", down = "t3", right = "cta" },
					t3 = { up = "t2", right = "cta" },
					cta = { left = "grip", right = "settings", down = "coach" },
					coach = { up = "cta", left = "grip", right = "settings" },
					settings = { down = "tracker", left = "cta" },
					tracker = { up = "settings" },
				}
			)
			-- Queued (the coach card waits): the CTA Down to the queue pill's Cancel, which links Up back to it.
			expect.deepEqual(
				HudFormat.focusLinks({
					left = { "coins", "grip" },
					tiles = { "t1", "t2" },
					right = { "settings" },
					queue = "queue",
					cta = "cta",
				}),
				{
					coins = { down = "grip", right = "cta" },
					grip = { up = "coins", down = "t1", right = "cta" },
					t1 = { up = "grip", down = "t2", right = "cta" },
					t2 = { up = "t1", right = "cta" },
					cta = { left = "grip", right = "settings", down = "queue" },
					queue = { up = "cta" },
					settings = { left = "cta" },
				}
			)
			-- No CTA (no "queue" screen): the top items reach the coach card's button, then Settings.
			expect.deepEqual(
				HudFormat.focusLinks({ left = { "coins" }, tiles = { "t1" }, right = { "settings" }, coach = "coach" }),
				{
					coins = { down = "t1", right = "coach" },
					t1 = { up = "coins" },
					coach = { left = "coins", right = "settings" },
					settings = { left = "coach" },
				}
			)
			-- Tiles in a row: left / right along the row, up to the Grip card, the row's end right to the CTA.
			local row = HudFormat.focusLinks({
				left = { "coins", "grip" },
				tiles = { "t1", "t2", "t3" },
				tileColumns = 3,
				right = {},
				cta = "cta",
			})
			expect.deepEqual(row.t1, { up = "grip", right = "t2" })
			expect.deepEqual(row.t2, { up = "grip", left = "t1", right = "t3" })
			expect.deepEqual(row.t3, { up = "grip", left = "t2", right = "cta" })
			expect.deepEqual(row.cta, { left = "grip" })
			-- Two columns (phones too): up / down by column, the second column and the last tile right to the CTA.
			local grid = HudFormat.focusLinks({
				left = { "grip" },
				tiles = { "t1", "t2", "t3", "t4", "t5" },
				tileColumns = 2,
				right = {},
				cta = "cta",
			})
			expect.deepEqual(grid.t1, { up = "grip", down = "t3", right = "t2" })
			expect.deepEqual(grid.t2, { up = "grip", down = "t4", left = "t1", right = "cta" })
			expect.deepEqual(grid.t4, { up = "t2", left = "t3", right = "cta" })
			expect.deepEqual(grid.t5, { up = "t3", right = "cta" })
			-- The Grip panel's chain (chainLinks): top to bottom only.
			expect.deepEqual(HudFormat.chainLinks({ "close", "showMe1", "showMe2" }), {
				close = { down = "showMe1" },
				showMe1 = { up = "close", down = "showMe2" },
				showMe2 = { up = "showMe1" },
			})
			expect.deepEqual(HudFormat.chainLinks({}), {})
		end
	)

	t.test(
		"DPadUp reaches the Grip card while it shows, else the first tile; nothing while the HUD hides (§17.12 L5)",
		function()
			expect.equal(HudFormat.dpadUpTarget(true, true, true), "entry")
			expect.equal(HudFormat.dpadUpTarget(true, true, false), "entry")
			expect.equal(HudFormat.dpadUpTarget(true, false, true), "row")
			expect.equal(HudFormat.dpadUpTarget(true, false, false), nil)
			expect.equal(HudFormat.dpadUpTarget(false, true, true), nil)
		end
	)
end
