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
-- UI FINAL R4 (plan work/ui/PLAN.md R4; `H:n` = "Squishy Duels HUD.dc.html" line n, `N:n` = Diego's newer file): the
-- "+N" float and the disc wiggle are gone (gainText, gainRise, gainSpot, iconWiggle; a gain shows the coin flash);
-- a landing shows floor(amount / k) more per coin, the last one the rest (coinStep), its bright flash at most once per
-- bounceMinGapMs, the last coin's kept (flashPlan, PR7); the DUEL area reads DUEL / Join the queue, and while Searching
-- the search bar's Finding match, its clock and its queue line (ctaModel); the testers' mode picker (pickerShown); the
-- tracker's status (trackerStatus); the design's spots (origins: Hud_Left 24 / 18, the tiles 14 / 150, the right
-- column 22 / 16, the DUEL area at 30; phones the edge), the faceless 118 x 104 tiles with no gap, the bare Grip row
-- (gripRowWidth, gripGoalWidth, gripCardHeight), the 63 px coin pill (pillHeight, pillWidth), the DUEL button's 350
-- (ctaWidth) and the search / found bars' room (barWidth, barParts); the toast column top 200 (N:197) and the coach
-- card's own band line (coachLine 110). Review fixes: a claim's flight only raises the number, whichever of its
-- StateDelta and its reply comes first (flightShows); the GRIP float not on phones nor in first person
-- (gripFloatShown); phones scale only the idle DUEL button, the search bar keeps its second line on every screen
-- (ctaScales, PR1, PR2); MATCH FOUND under the duel HUD's top bar (foundSpot); Down from the searching bar's cancel X
-- to the queue pill's hint (focusLinks `hint`).

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
		-- UI FINAL R2: the Settings sticker hovers as the design's "icon" (H:157), the tiles as their kind's "nav".
		expect.equal(HudFormat.navAt("settings")[1].fx, "icon")
		for _, item in HudFormat.navAt("tile") do
			expect.equal(item.fx, nil)
		end
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
		-- UI FINAL R4 (G4.11): no "+N" text any more (a gain shows the coin flash).
		expect.equal((HudFormat :: any).gainText, nil)
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

	t.test("coin landings (G4.10, H:663-668): each coin shows floor(amount / k) more, the last one the rest", function()
		expect.equal(HudFormat.coinStep(100, 8, 1), 12)
		expect.equal(HudFormat.coinStep(100, 8, 7), 84)
		expect.equal(HudFormat.coinStep(100, 8, 8), 100)
		expect.equal(HudFormat.coinStep(5, 8, 3), 0) -- fewer Coins than coins: the number moves at the last one
		expect.equal(HudFormat.coinStep(5, 8, 8), 5)
		expect.equal(HudFormat.coinStep(100, 0, 1), 100)
		expect.equal(HudFormat.coinStep(0 / 0, 8, 1), 0)
		for i = 1, 7 do
			expect.truthy(HudFormat.coinStep(1234, 8, i) <= HudFormat.coinStep(1234, 8, i + 1))
		end
		-- The disc wiggle went with the "+N" (UI FINAL R4).
		expect.equal((HudFormat :: any).iconWiggle, nil)
	end)

	t.test("coin flash (PR7): at most one per bounceMinGapMs; the last coin's is kept for when the gap ends", function()
		local Config = t.requireShared("Config")
		local gap = Config.UI.motion.coinFlight.bounceMinGapMs / 1000
		expect.equal((HudFormat.flashPlan(10, nil, false)), "now")
		expect.equal((HudFormat.flashPlan(10 + gap, 10, false)), "now")
		expect.equal((HudFormat.flashPlan(10 + gap / 2, 10, false)), "skip")
		local kind, at = HudFormat.flashPlan(10 + gap / 2, 10, true)
		expect.equal(kind, "later")
		expect.near(at :: number, 10 + gap, 1e-9)
		expect.equal((HudFormat.flashPlan(10, 0 / 0, true)), "now")
		-- 3 Hz at most (§9.12).
		expect.truthy(gap >= 1 / 3 - 1e-6)
	end)

	t.test("a claim's flight (G4.10): the shown number only rises from the old one, whichever comes first", function()
		local function run(target: (i: number) -> number?): { number }
			local shown = {}
			for i = 1, 8 do
				table.insert(shown, HudFormat.flightShows(1000, target(i), 100, 8, i))
			end
			return shown
		end
		local function rising(list: { number }, from: number, to: number)
			local last = from
			for _, n in list do
				expect.truthy(n >= last and n <= to)
				last = n
			end
			expect.equal(list[#list], to)
		end
		-- The StateDelta first (the number held at 1,000: HudController's flightWaitMs), then the flight of 100.
		local deltaFirst = run(function()
			return 1100
		end)
		expect.deepEqual(deltaFirst, { 1012, 1024, 1036, 1048, 1060, 1072, 1084, 1100 })
		rising(deltaFirst, 1000, 1100)
		-- The reply first: the number stays at 1,000 until the delta, then steps on.
		local replyFirst = run(function(i: number): number?
			return if i <= 3 then 1000 else 1100
		end)
		expect.deepEqual(replyFirst, { 1000, 1000, 1000, 1048, 1060, 1072, 1084, 1100 })
		rising(replyFirst, 1000, 1100)
		-- A spend during the flight wins at once; no newest value known: the steps, then the whole amount.
		expect.equal(HudFormat.flightShows(1000, 900, 100, 8, 2), 900)
		expect.equal(HudFormat.flightShows(1000, nil, 100, 8, 2), 1024)
		expect.equal(HudFormat.flightShows(1000, nil, 100, 8, 8), 1100)
		local Config = t.requireShared("Config")
		local wait = Config.UI.motion.coinCounter.flightWaitMs
		expect.truthy(type(wait) == "number" and wait > 0 and wait < Config.UI.motion.coinFlight.ms)
	end)

	t.test("the GRIP float (H:92-96): with the HUD up and a level, not on phones, not in first person", function()
		expect.truthy(HudFormat.gripFloatShown(true, 5, false, false))
		expect.falsy(HudFormat.gripFloatShown(false, 5, false, false)) -- the HUD hidden (a duel)
		expect.falsy(HudFormat.gripFloatShown(true, nil, false, false)) -- no Grip state
		expect.falsy(HudFormat.gripFloatShown(true, 5, true, false)) -- phones: the compact card shows the level
		expect.falsy(HudFormat.gripFloatShown(true, 5, false, true)) -- practice in first person: over the targets
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

	t.test("the DUEL area: DUEL / Join the queue; Searching: Finding match, its clock and the queue line", function()
		expect.deepEqual(
			HudFormat.ctaModel(nil, 100),
			{ queued = false, title = Strings.hud.duelCta, subtext = Strings.hud.duelJoin, time = "" }
		)
		expect.equal(HudFormat.ctaModel({ state = "Idle" }, 100).queued, false)
		expect.equal(HudFormat.ctaModel({ state = "Matched", joinedAt = 10 }, 100).queued, false)
		-- UI FINAL R4 (H:139, H:142): the search bar's "Finding match", its m:ss and the position line (plan FD1).
		local queue = { state = "Searching", joinedAt = 1000, position = 2, searching = 3, arenasFree = 6 }
		local queued = HudFormat.ctaModel(queue, 1023.6)
		expect.deepEqual(queued, {
			queued = true,
			title = Strings.hud.findingMatch,
			subtext = Strings.format(Strings.queue.position, { n = 2 }),
			time = "0:23",
		})
		-- The same clock as the queue pill's title.
		local QueueFormat = t.requireClient("UI/QueueFormat")
		local pill = QueueFormat.pill(queue, 1023.6, nil, nil)
		expect.truthy(string.find(pill.title, queued.time, 1, true) ~= nil)
		-- No arena free for the head pair: the arena line (QueueFormat.searchLine, never the hint).
		local waiting = HudFormat.ctaModel(
			{ state = "Searching", joinedAt = 1000, position = 1, searching = 2, arenasFree = 0 },
			1001
		)
		expect.equal(waiting.subtext, Strings.queue.waitingArena)
		-- Before joinedAt and the counts arrive: no clock, no line.
		local bare = HudFormat.ctaModel({ state = "Searching" }, 50)
		expect.equal(bare.title, Strings.hud.findingMatch)
		expect.equal(bare.time, "")
		expect.equal(bare.subtext, "")
	end)

	t.test("the mode picker (UI FINAL R4, N:144-162): Config.Match testers, or everyone with the [P] switch", function()
		local match = t.requireShared("Config").Match
		for _, id in match.pickerTesters do
			expect.truthy(HudFormat.pickerShown(id))
		end
		expect.equal(HudFormat.pickerShown(1, { pickerTesters = { 8963996639 }, pickerForEveryone = false }), false)
		expect.equal(HudFormat.pickerShown(1, { pickerTesters = {}, pickerForEveryone = true }), true)
		expect.equal(HudFormat.pickerShown(nil, { pickerTesters = { 1 }, pickerForEveryone = false }), false)
		expect.equal(
			HudFormat.pickerShown(8963996639, { pickerTesters = { 8963996639 }, pickerForEveryone = false }),
			true
		)
	end)

	t.test("the quest tracker's status (H:995): Ready to claim! for a claimable quest, else its reward", function()
		expect.deepEqual(
			HudFormat.trackerStatus({ state = "claim", reward = 50 } :: any),
			{ text = Strings.hud.questReady, ready = true }
		)
		expect.deepEqual(HudFormat.trackerStatus({ state = "inProgress", reward = 1200 } :: any), {
			text = Strings.format(Strings.hud.trackerReward, { coins = Format.coins(1200) }),
			ready = false,
		})
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

	-- UI FINAL R1: the band sums the HUD lays out with come from the sticker shapes (no hand copies), and the text
	-- estimate is Fredoka One's for every kind.
	t.test("band sums from Config.UI.Sticker; one text metric for every kind (Fredoka One)", function()
		local sticker = Config.UI.Sticker
		expect.equal(COLUMN.panelBottom, sticker.border.normal + sticker.lip.card + 3)
		local Button = t.requireClient("UI/Components/Button")
		local tile = Button.style("tile")
		expect.equal(COLUMN.tileBands, tile.top + tile.bevel + tile.drop)
		local Theme = t.requireClient("UI/Theme")
		local panel = Theme.panel({}, nil, COLUMN.coachPadding)
		expect.equal((panel:FindFirstChildOfClass("UIPadding") :: UIPadding).PaddingBottom.Offset, COLUMN.panelBottom)
		panel:Destroy()
		expect.equal(HudFormat.TEXT_METRICS.bodyEm, HudFormat.TEXT_METRICS.titleEm)
		expect.equal(HudFormat.TEXT_METRICS.bodyEm, 0.6)
	end)

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
						-- UI FINAL R4: from the design's spots (origins; phones the edge).
						local compact = class == "compact"
						local origin = HudFormat.origins(compact)
						local innerGap, tilesGap = HudFormat.leftGaps(compact, layout.grip)
						local leftBottom = if layout.left == "beside"
							then origin.left.Y + math.max(layout.pillHeight, layout.gripHeight)
							else origin.left.Y + layout.pillHeight + innerGap + layout.gripHeight
						expect.truthy(layout.left == "stack" or layout.grip == "compact")
						expect.near(layout.leftBottom, leftBottom, 1e-6)
						-- The tiles a gap under Hud_Left; on regular layouts never above the design's nav top (H:98).
						local under = layout.leftBottom + tilesGap
						expect.near(layout.tilesTop, if compact then under else math.max(origin.nav.Y, under), 1e-6)
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
			expect.near(noGrip.leftBottom, HudFormat.origins(class == "compact").left.Y + noGrip.pillHeight, 1e-6)
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
		-- UI FINAL R4 (H:102, H:32): the badge sits inside the sticker (right 8, top 0); only its sdBadge pop (the
		-- loop's peak scale, about its centre) reaches past the tile's top, never past its right.
		local peak = 1
		for _, frame in Config.UI.motion.idle.badge.frames do
			peak = math.max(peak, frame.scale or 1)
		end
		expect.equal(COLUMN.badgeReach, math.ceil((peak - 1) * CountBadge.SIZE_PX / 2 - 1e-6))
		expect.truthy((peak - 1) * CountBadge.SIZE_PX / 2 <= Config.UI.Sticker.hud.nav.badgeRight)
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

	-- UI FINAL R4 (G4.11): the "+N" float is gone with its spot and rise (a gain shows the coin flash, H:562-578).
	t.test("no coins '+N' any more: gainRise and gainSpot are gone", function()
		expect.equal((HudFormat :: any).gainRise, nil)
		expect.equal((HudFormat :: any).gainSpot, nil)
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
				-- UI FINAL R4 (H:99-101): at least the nav sticker's 118 x 104 (phones: the 58 px tile), as wide as the
				-- widest label in the nav's D23 (phones: Chip).
				expect.truthy(w >= (if compact then COLUMN.tileSizeCompact else COLUMN.tileWidth))
				expect.truthy(h >= (if compact then COLUMN.tileSizeCompact else COLUMN.tileHeight))
				local kind = if compact then "Chip" else "D23"
				for _, label in HudFormat.worstCaseTexts().tiles do
					local needed = HudFormat.textWidth(label, HudFormat.kindPx(kind, ts), "title")
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
		-- UI FINAL R4: the design's nav column has no gap (H:98); phones keep 10 px between their two columns.
		expect.equal(COLUMN.tileGap, 0)
		local g = COLUMN.tileGapCompact
		expect.deepEqual({ HudFormat.tilesBox("grid", 5, 80, 80, 1000, g) }, { 2, 3, 2 * 80 + g, 3 * 80 + 2 * g })
		-- The picture less the label's pull plus one D23 line fits in the design's 104 at the default text size.
		local _, height = HudFormat.tileSize(false, 1)
		expect.equal(height, COLUMN.tileHeight)
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
		-- UI FINAL R4 (H:82-90): the bare row: the bar with its lip, the gap and "{have} / {need} Grip", then the goal
		-- line (UD4) wrapped at the row's width; it grows with the text and stays a touch target (Hud_GripButton).
		expect.truthy(HudFormat.gripCardHeight("regular", LARGEST, 1) > HudFormat.gripCardHeight("regular", 1, 1))
		local texts = HudFormat.worstCaseTexts()
		local small = HudFormat.kindPx("Small", 1)
		local line = math.ceil(small * HudFormat.TEXT_METRICS.lineHeight - 1e-6)
		local goal = HudFormat.textHeight(texts.gripGoal, small, HudFormat.gripGoalWidth(1))
		expect.equal(
			HudFormat.gripCardHeight("regular", 1, 1),
			COLUMN.gripBarHeight + COLUMN.gripBarGap + line + COLUMN.listGap + goal
		)
		expect.truthy(HudFormat.gripCardHeight("regular", 1, 1) >= Layout.touchBase(TOUCH.minTarget, 1))
		-- Its width: the padding, the 200 px bar column (or its text), the gap and the Double Grip chip (H:83-89).
		local bar = math.max(COLUMN.gripBarWidth, HudFormat.textWidth(texts.gripBar, small))
		local chip = COLUMN.boltPx + COLUMN.boostGap + HudFormat.textWidth(texts.gripChip, small)
		expect.equal(HudFormat.gripRowWidth(1), math.ceil(COLUMN.gripPadLeft + bar + COLUMN.gripRowGap + chip))
		expect.equal(HudFormat.gripGoalWidth(1), HudFormat.gripRowWidth(1) - COLUMN.gripPadLeft)
		expect.equal(COLUMN.gripBarHeight, Config.UI.Sticker.bars.grip.height + Config.UI.Sticker.lip.bar) -- H:84
	end)

	t.test("worst-case texts: every onboarding step in every input, the longest Grip lines, the tiles", function()
		local texts = HudFormat.worstCaseTexts()
		expect.equal(#texts.onboarding, #Config.Onboarding.Steps * 3)
		for _, entry in texts.onboarding do
			expect.truthy(type(entry.text) == "string" and entry.text ~= "")
		end
		-- §11.8: the skip link is "Skip tutorial" (it ends the whole tutorial), never the short "Skip".
		expect.equal(texts.skip, Strings.onboarding.skip)
		expect.equal(texts.gotIt, Strings.common.gotIt)
		expect.equal(texts.gripLevel, tostring(Config.Grip.maxLevel))
		expect.truthy(string.find(texts.gripCompact, tostring(Config.Grip.maxLevel), 1, true) ~= nil)
		expect.equal((texts :: any).gripBadge, nil) -- Phase 6: no Upgrade tab (the trainers are gone)
		expect.truthy(#texts.coins >= #Strings.common.loading)
		expect.equal(#texts.tiles, 5)
		expect.equal(texts.tiles[1], Strings.hud.nav.squishies)
		-- UI FINAL R4 (H:89, FD3): the bare row's chip at a full Double Grip.
		local GripMath = t.requireShared("GripMath")
		local minutes = GripMath.restedMinutes(Config.Grip.Rested.burst)
		expect.equal(texts.gripChip, Strings.format(Strings.hud.gripBoost, { minutes = minutes }))
		expect.equal(HudFormat.worstCaseTexts(), texts) -- computed once
	end)

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
		-- UI FINAL R4: the coach card's band keeps its old line (coachLine 110) now the toasts start at 200 (N:197).
		local line = COLUMN.coachLine - COLUMN.rowGap
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
				local scale = Layout.uiScale(screen.Y, screen.X) -- UI FINAL R2 (PR1): the live fit (1024×768: 0.85)
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

		-- Every screen, with the real left side (sized for its widest texts) at the design's spots (UI FINAL R4:
		-- origins), the tiles' badge reach and the top-right group: the DUEL button fits at its top (PR10) over none
		-- of them, on PCs at every text size centred unless the left column pushes it; there the search bar keeps its
		-- dots and its second line in the room its band leaves (barWidth, barParts).
		for _, screen in ALL do
			local class = classOf(screen)
			local compact = class == "compact"
			local origin = HudFormat.origins(compact)
			local scales: { number } = if compact then { 1 } else TEXT_SCALES
			for _, ts in scales do
				local plan = HudFormat.leftColumnPlan(screen, class, ts)
				local c = plan.canvas
				local ctaSize = Vector2.new(
					HudFormat.ctaWidth(compact, ts),
					if compact then COLUMN.ctaCompactHeight else COLUMN.ctaHeight
				)
				local column = {
					x = origin.left.X,
					y = origin.left.Y,
					w = plan.width,
					h = plan.leftBottom - origin.left.Y,
				}
				local tileBox = HudFormat.badgeReachRect({
					x = origin.nav.X,
					y = plan.tilesTop,
					w = plan.tilesWidth,
					h = plan.tilesHeight,
				})
				local rightWidth = if compact then COLUMN.settingsSize else COLUMN.trackerWidth
				local rightGroup = {
					x = c.X - origin.right.X - rightWidth,
					y = origin.right.Y,
					w = rightWidth,
					h = if compact then COLUMN.settingsSize else COLUMN.settingsHeight + COLUMN.rightGap + 100,
				}
				local blockers = { column, tileBox, rightGroup }
				local place = HudFormat.ctaPlacement({
					canvas = c,
					size = ctaSize,
					blockers = blockers,
					top = origin.ctaTop,
				})
				local label = `{screen.X}x{screen.Y} text {ts}: x {place.x}`
				if not place.fits then
					error("the Duel CTA has no room at the top: " .. label)
				end
				expect.equal(place.y, origin.ctaTop)
				local cta = { x = place.x, y = place.y, w = ctaSize.X, h = ctaSize.Y }
				for _, rect in blockers do
					if overlaps(cta, rect) then
						error("the Duel CTA covers a HUD group: " .. label)
					end
				end
				if not compact then
					local centred = (c.X - ctaSize.X) / 2
					local pushed = column.x + column.w + COLUMN.rowGap
					expect.truthy(math.abs(place.x - centred) < 1e-6 or math.abs(place.x - pushed) < 1e-6)
				end
				-- The search bar at its full size on phones too (never scaled, HudFormat.ctaScales): its room keeps
				-- its dots and second line on every screen (phones 441 at 667x375, 649 at 844x390).
				local low, high = HudFormat.freeSpan(c, origin.ctaTop, COLUMN.barHeight, blockers)
				local bar = HudFormat.barWidth(COLUMN.searchWidth, high - low)
				if not HudFormat.barParts(bar).line2 then
					error(`the search bar loses its second line at {label} ({bar} wide)`)
				end
			end
		end
	end)

	t.test(
		"the DUEL area's scales (PR1, PR2): phones draw only the idle button smaller; texts and taps keep",
		function()
			local regular, compact = HudFormat.ctaScales(false), HudFormat.ctaScales(true)
			expect.deepEqual(regular, { idle = 1, search = 1, picker = 1 })
			expect.deepEqual(compact, { idle = COLUMN.ctaCompactScale, search = 1, picker = 1 })
			-- At the smallest UI scale the search bar's 16 px texts, its 52 px cancel X and the picker's 52 px tabs
			-- stay over the floors (minTextSize 13, the 44 px touch floor); at the idle button's scale they would not.
			local least = UI.Scale.min
			for _, scales in { regular, compact } do
				expect.truthy(UI.TextSize.Small * scales.search * least >= UI.minTextSize)
				expect.truthy(TOUCH.minTarget * scales.search * least >= TOUCH.minTargetFloor)
				expect.truthy(TOUCH.minTarget * scales.picker * least >= TOUCH.minTargetFloor)
			end
			expect.falsy(TOUCH.minTarget * compact.idle * least >= TOUCH.minTargetFloor)
			expect.falsy(UI.TextSize.Small * compact.idle * least >= UI.minTextSize)
			-- N:145: the picker 14 under the button's face, so 7 past its 7 px lip (Layout.lipGap).
			expect.equal(COLUMN.pickerGap, Config.UI.Sticker.hud.picker.gap - Config.UI.Sticker.lip.cta)
		end
	)

	t.test(
		"MATCH FOUND's spot (G4.2): the DUEL area's last place, under the duel HUD's top bar once it shows",
		function()
			local canvas = Vector2.new(1440, 810)
			local rect = { x = 545, y = 30, w = 350, h = 103 }
			expect.equal(HudFormat.foundSpot(rect, canvas, false, nil), Vector2.new(720, 30))
			-- No rect (the area never showed): the canvas centre at the DUEL area's top (phones: their own top).
			expect.equal(
				HudFormat.foundSpot(nil, canvas, false, nil),
				Vector2.new(720, HudFormat.origins(false).ctaTop)
			)
			expect.equal(HudFormat.foundSpot(nil, canvas, true, nil), Vector2.new(720, HudFormat.origins(true).ctaTop))
			-- The duel HUD's top bar ends at 96: a row gap under it; a bar that ends above the spot changes nothing.
			expect.equal(HudFormat.foundSpot(rect, canvas, false, 96), Vector2.new(720, 96 + COLUMN.rowGap))
			expect.equal(HudFormat.foundSpot(rect, canvas, false, 10), Vector2.new(720, 30))
			expect.equal(HudFormat.foundSpot(rect, canvas, false, 0 / 0), Vector2.new(720, 30))
		end
	)

	t.test("the DUEL button's width (ctaWidth): the design's 350, wider only for its texts; phones scaled", function()
		local Button = t.requireClient("UI/Components/Button")
		expect.equal(COLUMN.ctaHeight, Button.frameHeight("cta")) -- UI FINAL R2 (P1): the 92 px face + the 7 px lip
		expect.equal(COLUMN.ctaWidth, 350) -- H:126
		expect.equal(COLUMN.ctaCompactHeight, math.ceil(COLUMN.ctaHeight * COLUMN.ctaCompactScale - 1e-6))
		local sticker = Config.UI.Sticker
		local frame = 2 * sticker.border.heavy + sticker.hud.cta.padLeft + sticker.hud.cta.padRight
		for _, ts in TEXT_SCALES do
			local regular = HudFormat.ctaWidth(false, ts)
			expect.truthy(regular >= COLUMN.ctaWidth)
			-- Its paddings (the emblem's 128, 24 on the right, the 5 px border each side) and the wider text fit.
			local title = HudFormat.textWidth(Strings.hud.duelCta, HudFormat.kindPx("Duel", ts), "title")
			local sub = HudFormat.textWidth(Strings.hud.duelJoin, HudFormat.kindPx("D17", ts), "title")
			expect.truthy(regular >= frame + math.max(title, sub))
			-- Phones: the same button drawn at the compact scale (its second line hidden).
			expect.truthy(HudFormat.ctaWidth(true, ts) <= math.ceil(regular * COLUMN.ctaCompactScale))
		end
		expect.equal(HudFormat.ctaWidth(false, 1), COLUMN.ctaWidth)
		expect.equal(HudFormat.ctaWidth(true, 1), math.ceil(COLUMN.ctaWidth * COLUMN.ctaCompactScale))
		expect.truthy(HudFormat.ctaWidth(false, LARGEST) > HudFormat.ctaWidth(false, 1))
	end)

	t.test(
		"the design's spots (UI FINAL R4, Sticker.hud): Hud_Left, the tiles, the right column, the DUEL area",
		function()
			local hud = Config.UI.Sticker.hud
			local regular = HudFormat.origins(false)
			expect.equal(regular.left, Vector2.new(hud.left.x, hud.left.y)) -- H:74: 24, 18
			expect.equal(regular.nav, Vector2.new(hud.nav.x, hud.nav.y)) -- H:98: 14, 150
			expect.equal(regular.right, Vector2.new(hud.right.edge, hud.right.top)) -- H:156: 22, 16
			expect.equal(regular.ctaTop, hud.cta.top) -- PR10: 30
			local compact = HudFormat.origins(true)
			expect.equal(compact.left, Vector2.new(COLUMN.edge, COLUMN.edge))
			expect.equal(compact.nav, Vector2.new(COLUMN.edge, COLUMN.edge))
			expect.equal(compact.ctaTop, math.ceil(hud.cta.top * COLUMN.ctaCompactScale - 1e-6))
			-- PR10: the emblem pokes 12 above the button (its top -24 and the 6 px bob, H:23, H:128): still in the HUD.
			local poke = hud.cta.top - hud.cta.designTop
			expect.truthy(regular.ctaTop - poke >= 0)
			expect.truthy(compact.ctaTop - poke * COLUMN.ctaCompactScale >= -1e-6)
			-- The toasts start at N:197's 200, under the idle DUEL button and the search bar (and under the testers'
			-- picker when it reaches lower: UIController.toastsBelow).
			expect.equal(COLUMN.toastTop, 200)
			expect.truthy(COLUMN.toastTop >= regular.ctaTop + math.max(COLUMN.ctaHeight, COLUMN.barHeight))
		end
	)

	t.test(
		"the coin pill (H:75, G4.23): the 58 px face and the 5 px lip; at least 220 wide, its number after 68",
		function()
			expect.equal(HudFormat.pillHeight(1), COLUMN.pillFace + COLUMN.pillLip) -- 63
			expect.truthy(HudFormat.pillHeight(1) >= TOUCH.minTarget)
			expect.truthy(HudFormat.pillHeight(LARGEST) >= HudFormat.pillHeight(1))
			expect.equal(HudFormat.pillWidth(1, "0"), COLUMN.pillMinWidth)
			local number = HudFormat.textWidth("999.99M", HudFormat.kindPx("Coin", 1), "title")
			local wide = 2 * COLUMN.pillBorder + COLUMN.pillPadLeft + number + COLUMN.pillPadRight
			expect.equal(HudFormat.pillWidth(1, "999.99M"), math.max(COLUMN.pillMinWidth, math.ceil(wide)))
			expect.truthy(HudFormat.pillWidth(1) >= HudFormat.pillWidth(1, "0"))
		end
	)

	t.test(
		"search / found bars: the design's width, narrower only to their room; under dropBelow lines drop",
		function()
			local search = Config.UI.Sticker.hud.search
			expect.equal(HudFormat.barWidth(COLUMN.searchWidth, 900), COLUMN.searchWidth)
			expect.equal(HudFormat.barWidth(COLUMN.searchWidth, 400), 400)
			expect.equal(HudFormat.barWidth(COLUMN.foundWidth, -5), 0)
			expect.equal(HudFormat.barWidth(COLUMN.searchWidth, 0 / 0), COLUMN.searchWidth)
			expect.deepEqual(HudFormat.barParts(COLUMN.searchWidth), { dots = true, line2 = true })
			expect.deepEqual(HudFormat.barParts(search.dropBelow), { dots = true, line2 = true })
			expect.deepEqual(HudFormat.barParts(search.dropBelow - 1), { dots = false, line2 = false })
			expect.equal(COLUMN.barHeight, search.face + Config.UI.Sticker.lip.search) -- 96 + 7 (H:136)
		end
	)

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
			-- UI FINAL R4 (N:144-162): the testers' mode picker under the DUEL button: Down from it to the first tab,
			-- left / right between the tabs, Up back, Down on to the coach card's button.
			local picker = HudFormat.focusLinks({
				left = { "coins" },
				tiles = {},
				right = { "settings" },
				cta = "cta",
				coach = "coach",
				modes = { "mode:tdm", "mode:ffa" },
			})
			expect.deepEqual(picker.cta, { left = "coins", right = "settings", down = "mode:tdm" })
			expect.deepEqual(picker["mode:tdm"], { up = "cta", right = "mode:ffa", down = "coach" })
			expect.deepEqual(picker["mode:ffa"], { up = "cta", left = "mode:tdm", down = "coach" })
			-- UI FINAL R4: while searching (the cancel X is the CTA) Down reaches the queue pill's first hint button
			-- (its buttons link Up to Cancel themselves: no link is written on the hint here), else the coach card.
			local hint = HudFormat.focusLinks({
				left = { "coins" },
				tiles = {},
				right = { "settings" },
				cta = "cta",
				coach = "coach",
				hint = "hint",
			})
			expect.deepEqual(hint.cta, { left = "coins", right = "settings", down = "hint" })
			expect.equal(hint.hint, nil)
			-- The Grip panel's chain (chainLinks) went with its pad cards (build plan Phase 6).
			expect.equal((HudFormat :: any).chainLinks, nil)
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
