--!strict
-- NotifyFormat_Test: StarterPlayerScripts.Client.UI.NotifyFormat (what NotifyController shows). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §2.8, §2.10, §3.12, §3.13, §11.3, §17.2, §17.7):
--   * a Notify code shows its Strings text (reason.<code> or the plain key), placeholders filled from string and
--     number args only; a code without a text (or not shaped like a code) shows nothing;
--   * queue.* and duel.* codes are worded exactly like QueueController words them (one toast, never two texts);
--   * server.restartSoon gets its {time}; grip.* codes are held back during a match, at most 3, newest kept, merged;
--   * "No Coins were spent." only when the server's Result says charged = false;
--   * unknown kinds become info;
--   * foam UI (spec 2026-10-09): each toast kind has its accent stripe (Danger only for errors); the toast column
--     starts 110 base px down, or under the lobby's coach card when that reaches lower, never past the middle;
--   * integration (2026-10-09): only what hangs into the centred column from above moves it (the coach card, the
--     phone's top-band queue pill, the duel top bar), never the PC queue pill lower down or the top-left column;
--   * overlays fix (2026-10-09): quest.* codes are held back like grip.* ("Quest complete!" covered the duel result
--     card); the toast column never covers the HUD groups beside it: it stays centred when they leave room, moves
--     aside (the phone's tile row), narrows down to its minimum, else goes under them (never past the middle), and
--     starts under anything above it that the moved column meets;
--   * lobby HUD (spec 2026-10-11): what hangs in from above chains: a rect counts when it starts at or above the
--     running top (the Duel CTA at the top middle, then the coach card or the queue pill right under it).
--   * UI FINAL R4: the column's default top is the design's 200 (N:197) on its 810 px canvas while the lobby HUD shows,
--     keeping that share on a shorter canvas (a phone's 441: about 109), else the game's own 110 (duels, matches).
--   * Phone HUD B (2026-10-17): on a phone's lobby the column sits at the right edge under Daily and Settings,
--     narrowed clear of the DUEL area; with no room beside it (the 1v1 search bar) it is the centred column.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local NotifyFormat = t.requireClient("UI/NotifyFormat")
	local QueueFormat = t.requireClient("UI/QueueFormat")
	local Strings = t.requireShared("Strings")

	t.test("codes: reason texts and plain keys, args filled; unknown codes show nothing", function()
		expect.equal(NotifyFormat.textFor("data.openedElsewhere", nil), Strings.reason.data.openedElsewhere)
		expect.equal(NotifyFormat.textFor("data.loaded", nil), Strings.data.loaded)
		expect.equal(
			NotifyFormat.textFor("server.restartSoon", { time = "2:00" }),
			Strings.format(Strings.server.restartSoon, { time = "2:00" })
		)
		expect.equal(
			NotifyFormat.textFor("grip.levelUp", { level = 13 }),
			Strings.format(Strings.grip.levelUp, { level = 13 })
		)
		expect.equal(NotifyFormat.textFor("ult.noRoom", nil), Strings.reason.ult.noRoom)
		expect.equal(NotifyFormat.textFor("nope.missing", nil), nil)
		expect.equal(NotifyFormat.textFor("plainword", nil), nil)
		expect.equal(NotifyFormat.textFor(42, nil), nil)
		expect.equal(NotifyFormat.textFor(string.rep("a", 70) .. ".b", nil), nil)
		expect.equal(NotifyFormat.isKnown("grip.headStart"), true)
		expect.equal(NotifyFormat.isKnown("grip.nope"), false)
	end)

	t.test("args: only string and number values fill placeholders", function()
		local text = NotifyFormat.textFor("grip.rankUp", { name = "Ana", rank = { "table" } :: any })
		expect.equal(text, Strings.format(Strings.grip.rankUp, { name = "Ana" }))
		expect.truthy(string.find(text :: string, "{rank}", 1, true))
	end)

	t.test("queue and duel codes use QueueController's wording", function()
		for _, code in { "queue.timedOut", "queue.removedIdle", "queue.paused", "duel.noRewardsOffline" } do
			expect.equal(NotifyFormat.textFor(code, nil), QueueFormat.messageText(code))
		end
		-- queue.timedOut gets its {minutes} from Config, never a raw placeholder.
		expect.equal(string.find(NotifyFormat.textFor("queue.timedOut", nil) :: string, "{", 1, true), nil)
	end)

	t.test("kinds: the four kinds, anything else info", function()
		expect.equal(NotifyFormat.kindOf("success"), "success")
		expect.equal(NotifyFormat.kindOf("warn"), "warn")
		expect.equal(NotifyFormat.kindOf("error"), "error")
		expect.equal(NotifyFormat.kindOf("info"), "info")
		expect.equal(NotifyFormat.kindOf("loud"), "info")
		expect.equal(NotifyFormat.kindOf(nil), "info")
	end)

	t.test("hold-back: grip and quest codes only; at most max, newest kept, no repeats; merged one per line", function()
		expect.equal(NotifyFormat.isHeldBack("grip.levelUp"), true)
		expect.equal(NotifyFormat.isHeldBack("queue.timedOut"), false)
		expect.equal(NotifyFormat.isHeldBack("gripper.x"), false)
		-- Overlays fix: "Quest complete!" (and the auto-collected notice) wait for the end of the match too.
		expect.equal(NotifyFormat.isHeldBack("quest.complete"), true)
		expect.equal(NotifyFormat.isHeldBack("quest.autoCollected"), true)
		expect.equal(NotifyFormat.isHeldBack("questline.x"), false)
		expect.equal(NotifyFormat.isHeldBack("duel.noRewardsOffline"), false)
		expect.equal(NotifyFormat.isHeldBack(nil), false)
		local held = {}
		held = NotifyFormat.pushHeld(held, "a", 3)
		held = NotifyFormat.pushHeld(held, "b", 3)
		held = NotifyFormat.pushHeld(held, "a", 3)
		expect.deepEqual(held, { "b", "a" })
		held = NotifyFormat.pushHeld(held, "c", 3)
		held = NotifyFormat.pushHeld(held, "d", 3)
		expect.deepEqual(held, { "a", "c", "d" })
		expect.equal(NotifyFormat.merge(held), "a\nc\nd")
		expect.equal(NotifyFormat.merge({}), nil)
	end)

	t.test("results: the reason text; No Coins were spent only when charged = false", function()
		local plain = NotifyFormat.resultText({ ok = false, reason = "economy.notEnoughCoins" })
		expect.equal(plain, Strings.reason.economy.notEnoughCoins)
		local charged = NotifyFormat.resultText({ ok = false, reason = "economy.notEnoughCoins", charged = true })
		expect.equal(charged, Strings.reason.economy.notEnoughCoins)
		local refunded = NotifyFormat.resultText({ ok = false, reason = "box.paused", charged = false })
		expect.equal(refunded, Strings.reason.box.paused .. " " .. Strings.common.noCoinsSpent)
		expect.equal(NotifyFormat.resultText({ ok = false }), Strings.error.generic)
	end)

	t.test("areas", function()
		expect.equal(NotifyFormat.areaOf("queue.timedOut"), "queue.")
		expect.equal(NotifyFormat.areaOf("plain"), nil)
		expect.equal(NotifyFormat.areaOf(5), nil)
	end)

	-- UI FINAL R9 (H:660, H:846, H:676, H:779): the design's toast faces; a reserved gameplay colour never marks one.
	t.test(
		"toast faces (R9): purple info, mint success, red warn and error, pink teleport, unknown kinds as info",
		function()
			expect.equal(NotifyFormat.toastAccent("info"), "purple")
			expect.equal(NotifyFormat.toastAccent("success"), "mint")
			expect.equal(NotifyFormat.toastAccent("warn"), "red")
			expect.equal(NotifyFormat.toastAccent("error"), "red")
			expect.equal(NotifyFormat.toastAccent("loud"), "purple")
			expect.equal(NotifyFormat.toastAccent(nil), "purple")
			expect.equal(NotifyFormat.toastAccent("info", "teleport"), "pink")
			expect.equal(NotifyFormat.toastAccent("error", "unknown"), "red")
			local Palette = t.requireShared("Art/Palette")
			local hex: { [string]: { string } } = {
				purple = { "#A385FF", "#7A57F2" }, -- H:660
				mint = { "#6FE8BC", "#20A574" }, -- H:846
				red = { "#FF8A9A", "#E83A5A" }, -- H:676
				pink = { "#FF9CC2", "#F2468A" }, -- H:779
			}
			for face, want in hex do
				local top, bottom = NotifyFormat.toastColors(face :: any)
				expect.equal(Palette[top], Color3.fromHex(want[1]))
				expect.equal(Palette[bottom], Color3.fromHex(want[2]))
				for _, reserved in Palette.RESERVED do
					expect.truthy(top ~= reserved and bottom ~= reserved)
				end
			end
			expect.equal(NotifyFormat.toastIcon("success"), "img.icon.check")
			expect.equal(NotifyFormat.toastIcon("info"), nil)
		end
	)

	-- UI FINAL R9 (H:174-175): the pill 52 + lip 5, border 4, padding 0 20 0 8, the picture 40, gap 10; at most 3, 8 apart.
	t.test("toast pill (R9): its width from the text, with and without a picture; at most 3", function()
		local Config = t.requireShared("Config")
		local look = Config.UI.Sticker.toast
		expect.deepEqual(
			{ look.face, look.lip, look.border, look.padLeft, look.padRight, look.gap, look.icon, look.columnGap },
			{ 52, 5, 4, 8, 20, 10, 40, 8 }
		)
		expect.equal(NotifyFormat.toastWidth(100, true), 4 + 8 + 40 + 10 + 100 + 20 + 4)
		expect.equal(NotifyFormat.toastWidth(100, false), 4 + 20 + 100 + 20 + 4)
		expect.equal(NotifyFormat.toastWidth(0 / 0, false), 48)
		expect.equal(Config.UI.motion.toast.maxStacked, 3) -- H:660
	end)

	-- UI FINAL R9 (G9.1-G9.3, H:162, H:67, H:739): the quest pop: 60 + lip 5, border 4, padding 0 18 0 8, the check 42,
	-- gap 10; sdQPop over 2.8 s; the chime 150 ms later; its width from the wider line.
	t.test("quest pop (R9): its numbers and its measured width", function()
		local Config = t.requireShared("Config")
		local look = Config.UI.Sticker.qpop
		expect.deepEqual(
			{ look.face, look.lip, look.border, look.padLeft, look.padRight, look.gap, look.check, look.textGap },
			{ 60, 5, 4, 8, 18, 10, 42, 3 }
		)
		expect.equal(look.chimeDelayMs, 150)
		local motion = Config.UI.motion.qpop
		expect.equal(motion.lifeMs, 2800)
		expect.equal(#motion.frames, 5)
		expect.equal(motion.frames[2].at, 0.12)
		local QuestPop = t.requireClient("UI/QuestPop")
		expect.equal(QuestPop.width(80, 120), 4 + 8 + 42 + 10 + 120 + 18 + 4)
		expect.equal(QuestPop.width(150, 120), 4 + 8 + 42 + 10 + 150 + 18 + 4)
		expect.equal(Strings.quest.completeTag, "QUEST COMPLETE")
	end)

	t.test("toast column top: 110 base, under the coach card when it reaches lower, never past the middle", function()
		-- Nothing to keep clear: the default top.
		expect.equal(NotifyFormat.toastTop(441, nil, 110, 8), 110)
		-- A coach card ending higher than the default: the default top stays.
		expect.equal(NotifyFormat.toastTop(441, 90, 110, 8), 110)
		-- A coach card ending at 140: 8 under it.
		expect.equal(NotifyFormat.toastTop(441, 140, 110, 8), 148)
		-- A very tall card on a phone canvas (441 base): capped at the middle.
		expect.equal(NotifyFormat.toastTop(441, 400, 110, 8), 220.5)
		-- A canvas shorter than twice the default: never above the default either.
		expect.equal(NotifyFormat.toastTop(200, 300, 110, 8), 110)
		-- Bad numbers count as nothing to keep clear.
		expect.equal(NotifyFormat.toastTop(441, 0 / 0, 110, 8), 110)
		expect.equal(NotifyFormat.toastTop(441, 140, 110, 0 / 0), 140)
		expect.equal(NotifyFormat.toastTop(0 / 0, 140, 110, 8), 110)
	end)

	t.test(
		"toast column default top (UI FINAL R4): the lobby HUD's 200 of 810, its share when shorter; else 110",
		function()
			local Config = t.requireShared("Config")
			local lobby = Config.UI.Sticker.hud.toastTop
			local design = Config.UI.Scale.referenceHeight
			expect.equal(lobby, 200) -- N:197
			expect.equal(NotifyFormat.defaultTop(810, lobby, 110, design), 200)
			expect.equal(NotifyFormat.defaultTop(1000, lobby, 110, design), 200) -- never lower than the design's top
			expect.near(NotifyFormat.defaultTop(441, lobby, 110, design), 200 * 441 / design, 1e-9) -- a phone: ~109
			-- Duels and matches (the lobby HUD hidden): the game's own top under the duel HUD's top row.
			expect.equal(NotifyFormat.defaultTop(810, nil, 110, design), 110)
			expect.equal(NotifyFormat.defaultTop(810, 0 / 0, 110, design), 110)
			expect.equal(NotifyFormat.defaultTop(0 / 0, lobby, 110, design), 200)
		end
	)

	t.test("toast clearance (integration): only what hangs into the centred column from above counts", function()
		-- A phone canvas (785 base wide): the 420-wide column spans x 182.5 .. 602.5.
		local W, COLUMN, TOP = 785, 420, 110
		-- Nothing registered or shown: nothing to keep clear.
		expect.equal(NotifyFormat.toastClearance({}, W, COLUMN, TOP), nil)
		-- The coach card at the top centre, ending at 140: its bottom.
		local coach = { x = 200, y = 12, w = 380, h = 128 }
		expect.equal(NotifyFormat.toastClearance({ coach }, W, COLUMN, TOP), 140)
		-- The duel top bar (two cards and the timer, 135 tall at 8 down) and the coach card: the lower one wins.
		local topBar = { x = 150, y = 8, w = 480, h = 135 }
		expect.equal(NotifyFormat.toastClearance({ coach, topBar }, W, COLUMN, TOP), 143)
		-- The PC queue pill above the Duel CTA starts far below the toasts' top: it never moves them.
		local pillAboveCta = { x = 1000, y = 520, w = 400, h = 150 }
		expect.equal(NotifyFormat.toastClearance({ pillAboveCta }, 1422, COLUMN, TOP), nil)
		-- The phone's queue pill in the top band (centred between the HUD groups): it counts.
		local pillTop = { x = 300, y = 12, w = 320, h = 170 }
		expect.equal(NotifyFormat.toastClearance({ pillTop, pillAboveCta }, W, COLUMN, TOP), 182)
		-- Something beside the column (the top-left coin capsule and Grip card) does not count.
		local left = { x = 12, y = 12, w = 160, h = 200 }
		expect.equal(NotifyFormat.toastClearance({ left }, W, COLUMN, TOP), nil)
		-- Rects without a size or with bad numbers count as nothing, as do bad canvas numbers.
		expect.equal(NotifyFormat.toastClearance({ { x = 300, y = 12, w = 0, h = 50 } }, W, COLUMN, TOP), nil)
		expect.equal(NotifyFormat.toastClearance({ { x = 0 / 0, y = 12, w = 300, h = 50 } }, W, COLUMN, TOP), nil)
		expect.equal(NotifyFormat.toastClearance({ coach }, 0 / 0, COLUMN, TOP), nil)
		-- Fed to toastTop: 8 under the coach card, capped at the middle of a 441-tall phone canvas.
		expect.equal(NotifyFormat.toastTop(441, NotifyFormat.toastClearance({ coach }, W, COLUMN, TOP), TOP, 8), 148)
	end)

	t.test(
		"toast clearance (lobby HUD 2026-10-11): under the Duel CTA, then the coach card or the pill under it",
		function()
			-- A PC canvas (1536 base wide): the 420-wide column spans x 558 .. 978; the CTA at the top middle ends at 104.
			local W, COLUMN, TOP, GAP = 1536, 420, 110, 8
			local cta = { x = 648, y = 12, w = 240, h = 92 }
			expect.equal(NotifyFormat.toastClearance({ cta }, W, COLUMN, TOP, GAP), 104)
			-- The coach card starts right under it (104 + 8 = 112, below the default top): it counts too (`<=`).
			local coach = { x = 512, y = 112, w = 512, h = 80 }
			expect.equal(NotifyFormat.toastClearance({ coach, cta }, W, COLUMN, TOP, GAP), 192)
			-- The queue pill under the CTA instead (the coach card waits while queued).
			local pill = { x = 508, y = 112, w = 520, h = 76 }
			expect.equal(NotifyFormat.toastClearance({ pill, cta }, W, COLUMN, TOP, GAP), 188)
			-- Without the CTA above it, a rect starting under the default top still never counts.
			expect.equal(NotifyFormat.toastClearance({ coach }, W, COLUMN, TOP, GAP), nil)
			-- A rect lower than the running top (a gap wider than `gap`) breaks the chain.
			local nearly = { x = 512, y = 113, w = 512, h = 80 }
			-- One pixel of play (a button's real box can sit a pixel off its layout rect): still counts.
			expect.equal(NotifyFormat.toastClearance({ nearly, cta }, W, COLUMN, TOP, GAP), 193)
			local lower = { x = 512, y = 114, w = 512, h = 80 }
			expect.equal(NotifyFormat.toastClearance({ lower, cta }, W, COLUMN, TOP, GAP), 104)
			-- The toast column: 8 under the coach card, centred.
			local placed = NotifyFormat.toastColumn({
				canvas = Vector2.new(W, 864),
				width = COLUMN,
				minWidth = 280,
				height = 44,
				defaultTop = TOP,
				gap = GAP,
				edge = 12,
				above = { cta, coach },
				beside = {},
			})
			expect.deepEqual(placed, { x = 558, y = 200, width = COLUMN })
		end
	)

	-- Overlays fix: the toast column beside the HUD groups (base px; an 844×390 phone is about 993 wide at 0.85).
	local function column(overrides: { [string]: any }): any
		local input: { [string]: any } = {
			canvas = Vector2.new(993, 441),
			width = 420,
			minWidth = 280,
			height = 44,
			defaultTop = 110,
			gap = 8,
			edge = 12,
			above = {},
			beside = {},
		}
		for key, value in overrides do
			input[key] = value
		end
		return NotifyFormat.toastColumn(input :: any)
	end
	local function overlaps(x: number, y: number, w: number, h: number, rect: any): boolean
		return x < rect.x + rect.w and rect.x < x + w and y < rect.y + rect.h and rect.y < y + h
	end

	t.test(
		"toast column (overlays fix): centred with nothing beside it; moved aside of the phone's tile row",
		function()
			-- Nothing registered: centred at the default top, full width.
			expect.deepEqual(column({}), { x = 286.5, y = 110, width = 420 })
			-- The tile row on a phone (x 12..452) at the column's height: the column starts 8 right of it.
			local tiles = { x = 12, y = 126, w = 440, h = 64 }
			local beside = column({ beside = { tiles } })
			expect.deepEqual(beside, { x = 460, y = 110, width = 420 })
			expect.falsy(overlaps(beside.x, beside.y, beside.width, 44, tiles))
			-- Two toasts (a taller band) also meet the Duel CTA at the right edge: narrowed to the room between them.
			local cta = { x = 841, y = 166, w = 138, h = 64 }
			local narrow = column({ beside = { tiles, cta }, height = 100 })
			expect.deepEqual(narrow, { x = 460, y = 110, width = 373 })
			expect.falsy(overlaps(narrow.x, narrow.y, narrow.width, 100, cta))
			-- The same CTA lower than the band: the full width again.
			expect.deepEqual(column({ beside = { tiles, cta }, height = 44 }), { x = 460, y = 110, width = 420 })
			-- A PC (1536 wide): the left column, the tile column, the right column and the CTA leave it centred.
			local pc = column({
				canvas = Vector2.new(1536, 864),
				beside = {
					{ x = 12, y = 12, w = 270, h = 190 },
					{ x = 12, y = 210, w = 80, h = 400 },
					{ x = 1284, y = 12, w = 240, h = 300 },
					{ x = 1284, y = 740, w = 240, h = 92 },
				},
			})
			expect.deepEqual(pc, { x = 558, y = 110, width = 420 })
		end
	)

	t.test(
		"toast column (overlays fix): under the groups with no room beside them; under what hangs in above",
		function()
			-- Room narrower than the minimum: under the lowest group the band meets, full width, centred.
			local tiles = { x = 12, y = 126, w = 440, h = 64 }
			local wall = { x = 600, y = 100, w = 381, h = 80 }
			expect.deepEqual(column({ beside = { tiles, wall } }), { x = 286.5, y = 198, width = 420 })
			-- Never past the middle of the canvas (a 300-tall canvas: 150).
			local left = { x = 12, y = 50, w = 600, h = 240 }
			local right = { x = 620, y = 50, w = 361, h = 240 }
			local capped = column({ canvas = Vector2.new(993, 300), beside = { left, right } })
			expect.deepEqual(capped, { x = 286.5, y = 150, width = 420 })
			-- The coach card above (bottom 140): 8 under it, then beside the tiles.
			local coach = { x = 288, y = 12, w = 512, h = 128 }
			expect.deepEqual(column({ above = { coach }, beside = { tiles } }), { x = 460, y = 148, width = 420 })
			-- Something above that only the moved column meets (top right, ending at 160): it starts under that too.
			local high = { x = 720, y = 12, w = 180, h = 148 }
			expect.deepEqual(column({ above = { high } }), { x = 286.5, y = 110, width = 420 })
			expect.deepEqual(column({ above = { high }, beside = { tiles } }), { x = 460, y = 168, width = 420 })
		end
	)

	t.test("toast column (overlays fix): hidden rects count as nothing; a canvas narrower than the column", function()
		local hidden = {
			{ x = 0 / 0, y = 126, w = 440, h = 64 },
			{ x = 12, y = 126, w = 0, h = 64 },
			{ x = 12, y = 126, w = 440, h = 0 },
		}
		expect.deepEqual(column({ beside = hidden, above = hidden }), { x = 286.5, y = 110, width = 420 })
		-- 400 base wide: the column takes the room inside the edges.
		expect.deepEqual(column({ canvas = Vector2.new(400, 441) }), { x = 12, y = 110, width = 376 })
		-- Bad numbers never break it.
		local bad = column({ height = 0 / 0, gap = 0 / 0, minWidth = 0 / 0 })
		expect.deepEqual(bad, { x = 286.5, y = 110, width = 420 })
	end)

	-- Phone HUD B (2026-10-17): the phone lobby's column at the right (sideColumn), base px of an 844×390 phone (993 ×
	-- 391 at 0.85) with the B layout's groups: the left column, the 2 x 2 tiles, the DUEL area (button and mode chip)
	-- and Daily beside Settings.
	local function side(overrides: { [string]: any }): (any, any)
		local input: { [string]: any } = {
			canvas = Vector2.new(993, 391),
			width = 300,
			minWidth = 240,
			height = 57,
			defaultTop = 96,
			gap = 8,
			edge = 12,
			above = { { x = 383, y = 20, w = 227, h = 136 } }, -- the DUEL area
			beside = {
				{ x = 12, y = 12, w = 242, h = 106 }, -- Hud_Left
				{ x = 12, y = 116, w = 221, h = 131 }, -- the tiles' reach
				{ x = 845, y = 12, w = 136, h = 64 }, -- Daily and Settings
			},
		}
		for key, value in overrides do
			input[key] = value
		end
		return NotifyFormat.sideColumn(input :: any), input
	end

	t.test("side column (Phone HUD B): at the right edge under Daily and Settings, clear of the DUEL area", function()
		-- The 844x390 phone: the edge in from the right, at the lobby top (Daily and Settings end above it).
		local placed = side({})
		expect.deepEqual(placed, { x = 681, y = 96, width = 300 })
		-- Nothing registered: the same spot.
		expect.deepEqual((side({ above = {}, beside = {} })), { x = 681, y = 96, width = 300 })
		-- The 667x375 phone (785 x 373; the column 36% of it): the DUEL area at the middle reaches into it, so it is
		-- narrowed from the left to a gap right of that, at the same top.
		local small = side({
			canvas = Vector2.new(785, 373),
			width = 785 * 0.36,
			defaultTop = 92,
			above = { { x = 279, y = 20, w = 227, h = 136 } },
			beside = { { x = 12, y = 12, w = 242, h = 106 }, { x = 637, y = 12, w = 136, h = 64 } },
		})
		expect.deepEqual(small, { x = 514, y = 92, width = 259 })
		-- A taller top-right group (a large text size) hangs into it: it starts a gap under it.
		local tall = side({ beside = { { x = 845, y = 12, w = 136, h = 100 } } })
		expect.deepEqual(tall, { x = 681, y = 120, width = 300 })
	end)

	t.test("side column (Phone HUD B): with no room beside the search bar it is the centred column", function()
		-- The 1v1 search bar (560 wide, never scaled) across the top: less room at the right than minWidth.
		local search, input = side({ above = { { x = 216.5, y = 20, w = 560, h = 103 } } })
		expect.deepEqual(search, NotifyFormat.toastColumn(input :: any))
		expect.truthy(search.x < 681)
		-- Bad numbers never break it.
		local bad = side({ height = 0 / 0, gap = 0 / 0, minWidth = 0 / 0, defaultTop = 0 / 0 })
		expect.truthy(bad.x == bad.x and bad.y == bad.y and bad.width == bad.width)
	end)
end
