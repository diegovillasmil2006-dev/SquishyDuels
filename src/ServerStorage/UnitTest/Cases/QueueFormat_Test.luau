--!strict
-- QueueFormat_Test: StarterPlayerScripts.Client.UI.QueueFormat (the queue pill, board and messages). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §5.4, §7.7, §11.6):
--   * the pill shows only while Searching: "Looking for an opponent… m:ss" from joinedAt, then the position;
--   * after NoOpponentHintSeconds as the only searching ticket: "No one else is in the queue right now." with the
--     Keep waiting / Practice buttons; Keep waiting hides it for another NoOpponentHintSeconds;
--   * "All arenas are in use. You're next." from the server's messageKey, or with no arena free for the head pair;
--   * the board's live lines use the counts; the podium prompt shows its alt key ("Leave Queue") while Searching;
--   * join errors show their reason text, unknown ones "Couldn't join the queue. Try again."; queue.timedOut gets
--     its {minutes} from Config; never "Opponent found" with an invented name;
--   * the pill's place (Part 8; foam restyle, spec 2026-10-09; lobby HUD, spec 2026-10-11): right under the Duel CTA
--     at the top middle, else right above the CTA, else the top band between the HUD groups, else left of the CTA; it
--     never covers a HUD group at 667×375, 1280×720 and 1920×1080 (Medium and the largest text); with no free spot it
--     takes the top centre and says so (fits = false);
--   * overlays fix (2026-10-09): the pill hugs its contents (clock, texts, Cancel; the hint row when wider), capped at
--     today's widths; its width is measured with every digit as an 8 so the ticking clock never changes it; a pill
--     narrower than 320 still gets its free spot at its own width;
--   * UI FINAL R4: searchLine (the DUEL search bar's second line: the arena or position line, never the hint);
--     matchedText is MATCH FOUND's second line, "Opponent: {name}", empty before the name is known.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local QueueFormat = t.requireClient("UI/QueueFormat")
	local Strings = t.requireShared("Strings")
	local Config = t.requireShared("Config")
	local HINT = Config.Duel.Matchmaking.NoOpponentHintSeconds

	local function view(overrides: { [string]: any }?): any
		local v: { [string]: any } = {
			state = "Searching",
			position = 1,
			joinedAt = 1000,
			messageKey = nil,
			searching = 1,
			arenasFree = 6,
		}
		local changes: { [string]: any } = overrides or {}
		for key, value in changes do
			v[key] = value
		end
		return v
	end

	t.test("the pill is hidden unless Searching", function()
		expect.equal(QueueFormat.pill(view({ state = "Idle" }), 1000, nil, nil).visible, false)
		expect.equal(QueueFormat.pill(view({ state = "Matched" }), 1000, nil, nil).visible, false)
		local pill = QueueFormat.pill(view(), 1023.6, nil, nil)
		expect.equal(pill.visible, true)
		expect.equal(pill.showCancel, true)
		expect.equal(pill.title, Strings.format(Strings.queue.searchingTime, { time = "0:23" }))
		expect.equal(pill.detail, Strings.format(Strings.queue.position, { n = 1 }))
		local bare = { state = "Searching", searching = 1, arenasFree = 6 } -- no joinedAt, no position
		local noTime = QueueFormat.pill(bare, 1000, nil, nil)
		expect.equal(noTime.title, Strings.queue.searching)
		expect.equal(noTime.detail, nil)
	end)

	t.test("the no-opponent hint after NoOpponentHintSeconds alone; Keep waiting snoozes it", function()
		local alone = QueueFormat.nextAloneSince(nil, view(), 1000)
		expect.equal(alone, 1000)
		expect.equal(QueueFormat.nextAloneSince(alone, view(), 1010), 1000) -- the clock keeps its start
		expect.equal(QueueFormat.nextAloneSince(alone, view({ searching = 2 }), 1010), nil)
		expect.equal(QueueFormat.nextAloneSince(alone, view({ state = "Idle" }), 1010), nil)

		local before = QueueFormat.pill(view(), 1000 + HINT - 0.5, alone, nil)
		expect.equal(before.showHint, false)
		local after = QueueFormat.pill(view(), 1000 + HINT, alone, nil)
		expect.equal(after.showHint, true)
		expect.equal(after.detail, Strings.queue.noOpponent)
		expect.equal(after.showCancel, true)

		local dismissedAt = 1000 + HINT + 1
		expect.equal(QueueFormat.pill(view(), dismissedAt + HINT - 1, alone, dismissedAt).showHint, false)
		expect.equal(QueueFormat.pill(view(), dismissedAt + HINT, alone, dismissedAt).showHint, true)
	end)

	t.test("the server's queue.noOpponent message shows the hint at once; Keep waiting still snoozes it", function()
		local told = view({ messageKey = "queue.noOpponent", searching = 1 })
		local now = 1005 -- well before the client's own 20 s clock
		local pill = QueueFormat.pill(told, now, nil, nil)
		expect.equal(pill.showHint, true)
		expect.equal(pill.detail, Strings.queue.noOpponent)
		expect.equal(QueueFormat.pill(told, now + 1, nil, now).showHint, false)
		expect.equal(QueueFormat.pill(told, now + HINT, nil, now).showHint, true)
	end)

	t.test("all arenas in use: from the server message, or for the head pair with no arena free", function()
		local fromServer = QueueFormat.pill(view({ messageKey = "queue.waitingArena", position = 5 }), 1000, nil, nil)
		expect.equal(fromServer.detail, Strings.queue.waitingArena)
		local headPair = QueueFormat.pill(view({ arenasFree = 0, searching = 2, position = 2 }), 1000, nil, nil)
		expect.equal(headPair.detail, Strings.queue.waitingArena)
		local third = QueueFormat.pill(view({ arenasFree = 0, searching = 3, position = 3 }), 1000, nil, nil)
		expect.equal(third.detail, Strings.format(Strings.queue.position, { n = 3 }))
		local aloneNoArena = QueueFormat.pill(view({ arenasFree = 0, searching = 1 }), 1000, nil, nil)
		expect.equal(aloneNoArena.detail, Strings.format(Strings.queue.position, { n = 1 }))
	end)

	t.test("board lines, prompt key and messages", function()
		local counts = { searching = 4, duelsInProgress = 2, arenasFree = 4 }
		expect.equal(
			QueueFormat.boardText("queue.boardWaiting", counts, 6),
			Strings.format(Strings.queue.boardWaiting, { count = 4 })
		)
		expect.equal(
			QueueFormat.boardText("queue.boardActive", counts, 6),
			Strings.format(Strings.queue.boardActive, { count = 2, max = 6 })
		)
		expect.equal(QueueFormat.boardText("queue.boardTitle", counts, 6), nil)
		expect.equal(QueueFormat.boardText(nil, counts, 6), nil)

		expect.equal(QueueFormat.promptAttribute("Searching"), "SD_AltTextKey")
		expect.equal(QueueFormat.promptAttribute("Idle"), "SD_TextKey")
		expect.equal(QueueFormat.promptAttribute("Matched"), "SD_TextKey")

		local minutes = Config.Duel.Matchmaking.QueueMaxSeconds / 60
		local timedOut = QueueFormat.messageText("queue.timedOut")
		expect.equal(timedOut, Strings.format(Strings.reason.queue.timedOut, { minutes = minutes }))
		expect.equal(string.find(timedOut, "{", 1, true), nil)
		expect.equal(QueueFormat.messageText("queue.left"), Strings.queue.left)
	end)

	t.test("join errors: the reason text, or the generic queue failure", function()
		expect.equal(QueueFormat.joinErrorText(nil), Strings.queue.joinFailed)
		expect.equal(QueueFormat.joinErrorText("error.generic"), Strings.queue.joinFailed)
		expect.equal(QueueFormat.joinErrorText("not.a.code"), Strings.queue.joinFailed)
		expect.equal(QueueFormat.joinErrorText("queue.cooldown"), Strings.reason.queue.cooldown)
		expect.equal(QueueFormat.joinErrorText("queue.unavailable"), Strings.reason.queue.unavailable)
	end)

	t.test("toasts for new queue messages, never for the arena wait the pill shows", function()
		local searching = view()
		local left = view({ state = "Idle", messageKey = "queue.left" })
		expect.equal(QueueFormat.toastKey(searching, left), "queue.left")
		expect.equal(QueueFormat.toastKey(left, left), nil) -- the same message again
		expect.equal(QueueFormat.toastKey(searching, view({ messageKey = "queue.waitingArena" })), nil)
		expect.equal(QueueFormat.toastKey(searching, view({ messageKey = "queue.noOpponent" })), nil)
		expect.equal(QueueFormat.toastKey(searching, view()), nil)
		local again = view({ state = "Searching", messageKey = "queue.left" })
		expect.equal(QueueFormat.toastKey(left, again), "queue.left") -- state changed with the key
	end)

	-- The pill's place (QueueFormat.pillPlacement; Part 8, foam restyle) ------------------------------------------------

	local Layout = t.requireClient("UI/Layout")
	local HudFormat = t.requireClient("UI/HudFormat")
	local COLUMN = HudFormat.COLUMN
	local LARGEST = Config.UI.PreferredTextScale.Largest
	local SCREENS = { Vector2.new(667, 375), Vector2.new(1280, 720), Vector2.new(1920, 1080) }
	local function canvas(actual: Vector2): Vector2
		return actual / Layout.uiScale(actual.Y)
	end
	local function overlaps(a: any, b: any): boolean
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end
	local function rectOf(place: any, height: number): any
		return { x = place.x - place.width / 2, y = place.y, w = place.width, h = height }
	end
	-- The foam HUD on a canvas (base px; lobby HUD spec 2026-10-11): the left column (the coin capsule over the Grip
	-- card), the tiles (a column on PCs, two columns under the column on phones), the top-right group (Settings, the
	-- tracker) and the Duel CTA at the top middle (medium-sized and queued on phones).
	local function hud(screen: Vector2, compact: boolean, textScale: number): any
		local left = { x = 12, y = 12, w = if compact then 213 else 270, h = if compact then 110 else 280 * textScale }
		local tiles = if compact
			then { x = 12, y = left.y + left.h + 14, w = 216, h = 194 * textScale }
			else { x = 12, y = left.y + left.h + 22, w = 103, h = 460 }
		local right = if compact
			then { x = screen.X - 12 - 64, y = 12, w = 64, h = 64 }
			else { x = screen.X - 12 - 256, y = 12, w = 256, h = 170 }
		local ctaSize = if compact then Vector2.new(242, 66) else Vector2.new(254, 92)
		local cta = { x = (screen.X - ctaSize.X) / 2, y = 12, w = ctaSize.X, h = ctaSize.Y }
		return { left = left, tiles = tiles, right = right, cta = cta }
	end

	t.test(
		"pill placement: right under the Duel CTA at the top middle, never over a HUD group, at every size",
		function()
			for _, actual in SCREENS do
				local screen = canvas(actual)
				local compact = Layout.layoutClass(actual.X, actual.Y) == "compact"
				for _, textScale in { 1, LARGEST } do
					local frames = hud(screen, compact, textScale)
					local blockers = { frames.left, frames.tiles, frames.right }
					local height = (if compact then 96 else 76) * textScale
					local place = QueueFormat.pillPlacement({
						screen = screen,
						cta = frames.cta,
						blockers = blockers,
						height = height,
					})
					local label = `{actual.X}x{actual.Y} text {textScale}: {place.spot} at {place.x}, {place.y}`
					if not place.fits then
						error("no free spot for the pill: " .. label)
					end
					expect.equal(place.spot, "belowCta")
					expect.truthy(place.width >= 320 and place.width <= 460)
					local rect = rectOf(place, height)
					expect.truthy(rect.x >= 12 - 1e-6 and rect.x + rect.w <= screen.X - 12 + 1e-6)
					for _, frame in { frames.left, frames.tiles, frames.right, frames.cta } do
						if overlaps(rect, frame) then
							error("the pill covers a HUD group: " .. label)
						end
					end
					-- A row gap under the CTA; on PCs centred on it (on phones moved right of the tiles).
					expect.near(rect.y, frames.cta.y + frames.cta.h + COLUMN.rowGap, 1e-6)
					if not compact then
						expect.near(place.x, frames.cta.x + frames.cta.w / 2, 1e-6)
					end
				end
			end
		end
	)

	t.test("pill placement: under the CTA first; then above it, the top band, beside it, the fallback", function()
		local screen = canvas(SCREENS[2])
		local frames = hud(screen, false, 1)
		-- The room under the CTA taken (the coach card, should it still show): never over it, the next free spot.
		local coach = { x = screen.X / 2 - 256, y = frames.cta.y + frames.cta.h + COLUMN.rowGap, w = 512, h = 80 }
		local taken = QueueFormat.pillPlacement({
			screen = screen,
			cta = frames.cta,
			blockers = { frames.left, frames.right, coach },
			height = 80,
		})
		expect.truthy(taken.spot ~= "belowCta")
		expect.falsy(overlaps(rectOf(taken, 80), coach))
		-- A CTA lower down with no room under it (the old bottom-right corner): right above it, right-aligned.
		local lowCta = { x = screen.X - 12 - 240, y = screen.Y - 12 - 92, w = 240, h = 92 }
		local above = QueueFormat.pillPlacement({
			screen = screen,
			cta = lowCta,
			blockers = { frames.left, frames.right },
			height = 80,
		})
		expect.equal(above.spot, "aboveCta")
		expect.near(above.x + above.width / 2, lowCta.x + lowCta.w, 1e-6)
		expect.near(above.y + 80, lowCta.y - COLUMN.rowGap, 1e-6)
		-- Under and above the CTA taken: the top band, centred between the groups it meets.
		local highCta = { x = lowCta.x, y = 40, w = 240, h = 92 }
		local under = { x = 300, y = 140, w = 900, h = 400 }
		local top = QueueFormat.pillPlacement({
			screen = screen,
			cta = highCta,
			blockers = { frames.left, frames.right, under },
			height = 80,
		})
		expect.equal(top.spot, "top")
		expect.equal(top.y, 12)
		expect.near(top.x, screen.X / 2, 1e-6)
		expect.equal(top.width, 460)
		-- Under, above and the top band taken: left of the CTA, bottom-aligned with it.
		local band = { x = screen.X / 2 - 256, y = 12, w = 512, h = 80 }
		local wall = { x = screen.X - 12 - 460, y = 300, w = 460, h = 350 }
		local beside = QueueFormat.pillPlacement({
			screen = screen,
			cta = lowCta,
			blockers = { frames.left, frames.right, band, wall },
			height = 80,
		})
		expect.equal(beside.spot, "besideCta")
		expect.near(beside.x + beside.width / 2, lowCta.x - COLUMN.rowGap, 1e-6)
		expect.near(beside.y + 80, lowCta.y + lowCta.h, 1e-6)
		-- Nothing free (a phone at the largest text): the top centre, fits = false.
		local phone = canvas(SCREENS[1])
		local crowded = QueueFormat.pillPlacement({
			screen = phone,
			cta = { x = phone.X - 182, y = 100, w = 170, h = 64 },
			blockers = { { x = 12, y = 12, w = phone.X - 24, h = phone.Y - 24 } },
			height = 200,
		})
		expect.equal(crowded.fits, false)
		expect.equal(crowded.y, 12)
		-- Nothing to clear: the top centre of the screen, at its preferred width.
		local free = QueueFormat.pillPlacement({ screen = phone })
		expect.equal(free.spot, "top")
		expect.near(free.x, phone.X / 2, 1e-6)
		expect.equal(free.width, 460)
		-- Hidden frames (empty or not finite rects) count as nothing.
		local empty = QueueFormat.pillPlacement({
			screen = phone,
			blockers = { { x = 0, y = 0, w = 0, h = 0 }, { x = 0 / 0, y = 0, w = 10, h = 10 } },
		})
		expect.near(empty.x, phone.X / 2, 1e-6)
	end)

	t.test(
		"pill width (overlays fix): hugs the clock, the texts and Cancel; the hint row when wider; capped",
		function()
			local parts = { padding = 12, icon = 24, gap = 8, text = 200, cancel = 92 }
			-- 2 × 12 + 24 + 2 × 8 + 200 (+ 4 slack) + 92.
			expect.equal(QueueFormat.pillWidth(parts, 520), 360)
			-- Never wider than today's width (the title wraps beside Cancel at the largest text).
			expect.equal(QueueFormat.pillWidth({ padding = 12, icon = 24, gap = 8, text = 600, cancel = 92 }, 460), 460)
			-- Keep waiting and Practice wider than the top row: the hint row decides.
			local hint = { padding = 12, icon = 24, gap = 8, text = 100, cancel = 92, hint = 300 }
			expect.equal(QueueFormat.pillWidth(hint, 520), 324)
			-- Whole px, rounded up.
			expect.equal(
				QueueFormat.pillWidth({ padding = 12, icon = 24, gap = 8, text = 200.3, cancel = 92 }, 520),
				361
			)
			-- Bad numbers count as 0; a bad cap is the phone width.
			local bad = { padding = 12, icon = 24, gap = 8, text = 0 / 0, cancel = 92 }
			expect.equal(QueueFormat.pillWidth(bad, 520), 160)
			expect.equal(
				QueueFormat.pillWidth({ padding = 12, icon = 24, gap = 8, text = 900, cancel = 92 }, 0 / 0),
				460
			)
		end
	)

	t.test("pill width samples: every digit is an 8, so the ticking clock never changes the measure", function()
		expect.equal(QueueFormat.measureSample("0:23"), "8:88")
		expect.equal(QueueFormat.measureSample("You're #12 in the queue"), "You're #88 in the queue")
		expect.equal(QueueFormat.measureSample("No digits"), "No digits")
		local a = QueueFormat.pill(view({ joinedAt = 1000 }), 1023, nil, nil)
		local b = QueueFormat.pill(view({ joinedAt = 1000 }), 1059, nil, nil)
		expect.truthy(a.title ~= b.title)
		expect.equal(QueueFormat.measureSample(a.title), QueueFormat.measureSample(b.title))
	end)

	t.test(
		"pill placement (overlays fix): a pill narrower than 320 still gets its free spot at its own width",
		function()
			for _, actual in SCREENS do
				local screen = canvas(actual)
				local compact = Layout.layoutClass(actual.X, actual.Y) == "compact"
				local frames = hud(screen, compact, 1)
				local blockers = { frames.left, frames.tiles, frames.right }
				local place = QueueFormat.pillPlacement({
					screen = screen,
					cta = frames.cta,
					blockers = blockers,
					width = 300,
					height = 76,
				})
				local label = `{actual.X}x{actual.Y}: {place.spot}`
				if not place.fits then
					error("no free spot for a 300-wide pill: " .. label)
				end
				expect.equal(place.width, 300)
				for _, frame in { frames.left, frames.tiles, frames.right, frames.cta } do
					if overlaps(rectOf(place, 76), frame) then
						error("the pill covers a HUD group: " .. label)
					end
				end
			end
		end
	)

	t.test("matched text (UI FINAL R4, H:151): 'Opponent: {name}' under MATCH FOUND, empty before the name", function()
		expect.equal(
			QueueFormat.matchedText("Builderman"),
			Strings.format(Strings.hud.matchOpponent, { name = "Builderman" })
		)
		expect.equal(QueueFormat.matchedText(nil), "")
		expect.equal(QueueFormat.matchedText(""), "")
	end)

	t.test(
		"search line (UI FINAL R4, H:142): the arena or position line, never the hint; nil when not Searching",
		function()
			expect.equal(QueueFormat.searchLine(view()), Strings.format(Strings.queue.position, { n = 1 }))
			expect.equal(
				QueueFormat.searchLine(view({ messageKey = "queue.waitingArena" })),
				Strings.queue.waitingArena
			)
			expect.equal(
				QueueFormat.searchLine(view({ arenasFree = 0, searching = 2, position = 1 })),
				Strings.queue.waitingArena
			)
			-- The no-opponent hint is the pill's own line, not the bar's.
			expect.equal(
				QueueFormat.searchLine(view({ messageKey = "queue.noOpponent" })),
				Strings.format(Strings.queue.position, { n = 1 })
			)
			-- No position yet: no line.
			expect.equal(QueueFormat.searchLine({ state = "Searching", searching = 1, arenasFree = 6 }), nil)
			expect.equal(QueueFormat.searchLine(view({ state = "Idle" })), nil)
			-- The pill's detail is the same line while no hint is due.
			local pill = QueueFormat.pill(view({ position = 3, searching = 4 }), 1001, nil, nil)
			expect.equal(pill.detail, QueueFormat.searchLine(view({ position = 3, searching = 4 })))
		end
	)
end
