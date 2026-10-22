--!strict
-- MatchHudFormat_Test: StarterPlayerScripts.Client.UI.MatchHudFormat (Match HUD M4, 2026-10-16: the base rules of the
-- in-match screens; plan work/matchhud2/PLAN.md §4 M4 = v1 M3a, v1 §1.3). Server only (ServerStorage.UnitTest). Pure.
-- Contract:
--   * canvas(size, scale): the safe area in base px = size / scale; zero for a bad size or scale;
--   * fitScale(pieceBase, canvas, fitMin, useHeight?): clamp(canvas / pieceBase, fitMin, 1) on width (v1 §1.3b; the
--     6v6 bar ≈ 1170 base on an 844 px phone at the .85 floor ≈ .85), on height too when asked (the smaller), never
--     under fitMin, 1 when it fits or a size is bad;
--   * build(specs, enabled, preview): every piece in a Studio preview, only the switched-on ones in a real match (a
--     missing switch is off), in list order;
--   * sessionAction(session, matchId): a first view starts a session, another match or a real view over a preview
--     restarts it, no view stops a real one and leaves a preview alone, the same match keeps it.
-- Match HUD M6 / M7 (2026-10-17; M = "Squishy Duels Match HUD.dc.html"):
--   * feedLine: the tag order FINAL KILL > FIRST BLOOD > TRIPLE! > DOUBLE! > "{n} STREAK" (M:523-527); FIRST BLOOD on
--     the first K.O. with an attacker (a fall before it makes a cause line and keeps it), never after a late start
--     (the first moment seen is not seq 1); the 4 s window (3.99 s doubles, 4.01 s does not); mine = by / victim;
--   * feedPose: in for 0.5 s, held, out at 4.6 s for 0.4 s, gone at 5.0 s; an early leave starts the out at once;
--   * playerLook (TDM by team, FFA's six in turn), deadColor (CSS grayscale + brightness);
--   * the card: cardShows (you, not final, live; with or without an attacker), every Catalog squishy has its own
--     title, causeCard's storm / fall / other words; the bar: respawnShows, respawnLeft (whole seconds, at least 1),
--     respawnShare (the server-time fill, clamped);
--   * touchAreas: the thumbstick zone and the buttons in base px (no Catch); cardPlace / barPlace at 1440 x 810,
--     1024 x 768, a 844 x 390 phone with touch (the card above the thumbstick zone, the bar beside it, nothing on the
--     zone) and without (compact), and a narrow screen (the bar above the card);
--   * trackPose (reduced motion: only the fade), clipText (an ellipsis to fit).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireClient: (path: string) -> any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Format = t.requireClient("UI/MatchHudFormat")
	local Config = t.requireShared("Config")
	local Catalog = t.requireShared("Catalog")
	local Palette = t.requireShared("Art/Palette")
	local EPS = 1e-6
	local CARD = Vector2.new(486, 309)
	local BAR = Vector2.new(380, 80)

	local function spec(name: string): any
		return {
			name = name,
			new = function(): any
				return {}
			end,
		}
	end

	local function names(list: { any }): { string }
		local out = {}
		for _, item in list do
			table.insert(out, item.name)
		end
		return out
	end

	t.test("canvas: the safe area in base px; zero for a bad size or scale", function()
		local c = Format.canvas(Vector2.new(1440, 810), 1.25)
		expect.near(c.X, 1152, 1e-9)
		expect.near(c.Y, 648, 1e-9)
		expect.equal(Format.canvas(Vector2.new(844, 390), 0), Vector2.zero)
		expect.equal(Format.canvas(Vector2.new(0, 390), 0.85), Vector2.zero)
		expect.equal(Format.canvas(Vector2.new(844, 390), 0 / 0), Vector2.zero)
	end)

	t.test("fitScale: shrinks a piece wider than the safe area, never under fitMin, 1 when it fits", function()
		local phone = Format.canvas(Vector2.new(844, 390), 0.85) -- ≈ 993 x 459 base
		expect.near(Format.fitScale(Vector2.new(1170, 120), phone, 0.6), 844 / 0.85 / 1170, 1e-6) -- Vector2 is float32
		expect.equal(Format.fitScale(Vector2.new(2000, 100), phone, 0.6), 0.6)
		expect.equal(Format.fitScale(Vector2.new(400, 200), phone, 0.6), 1)
		expect.equal(Format.fitScale(Vector2.new(0, 200), phone, 0.6), 1) -- a bad size never shrinks
	end)

	t.test("fitScale: with useHeight the smaller of the width and height fits", function()
		local canvas = Vector2.new(1000, 400)
		expect.near(Format.fitScale(Vector2.new(800, 500), canvas, 0.6), 1, 1e-9)
		expect.near(Format.fitScale(Vector2.new(800, 500), canvas, 0.6, true), 0.8, 1e-9)
		expect.near(Format.fitScale(Vector2.new(800, 1000), canvas, 0.6, true), 0.6, 1e-9)
	end)

	t.test("build: a preview builds every piece, a real match only the switched-on ones, in list order", function()
		local specs = { spec("feed"), spec("card"), spec("finish") }
		expect.deepEqual(names(Format.build(specs, {}, true)), { "feed", "card", "finish" })
		expect.deepEqual(names(Format.build(specs, { feed = false, card = true }, false)), { "card" })
		expect.deepEqual(names(Format.build(specs, { finish = true, feed = true }, false)), { "feed", "finish" })
		expect.deepEqual(names(Format.build(specs, {}, false)), {})
	end)

	t.test("sessionAction: start, keep, restart and stop", function()
		local real = { matchId = "match:1", preview = false }
		local preview = { matchId = "match:preview-tdm", preview = true }
		expect.equal(Format.sessionAction(nil, "match:1"), "start")
		expect.equal(Format.sessionAction(nil, nil), "keep")
		expect.equal(Format.sessionAction(real, "match:1"), "keep")
		expect.equal(Format.sessionAction(real, "match:2"), "restart")
		expect.equal(Format.sessionAction(real, nil), "stop")
		expect.equal(Format.sessionAction(preview, nil), "keep") -- no real match: the preview stays
		expect.equal(Format.sessionAction(preview, "match:1"), "restart") -- a real match ends the preview
		expect.equal(Format.sessionAction(preview, "match:preview-tdm"), "restart") -- even with the same id
	end)

	-- Match HUD M6 / M7 ------------------------------------------------------------------------------------------

	local FEED = Config.UI.Match.feed
	local A, B, C, D, YOU = 11, 12, 13, 14, 7

	local function ko(seq: number, by: number?, victim: number, at: number, extra: { [string]: any }?): any
		local moment: { [string]: any } =
			{ seq = seq, kind = "ko", at = at, victim = victim, by = by, cause = if by then "hit" else "storm" }
		for k, v in (extra or {}) :: { [string]: any } do
			moment[k] = v
		end
		return moment
	end

	local function line(memory: any, moment: any): any
		return Format.feedLine(memory, moment, YOU, FEED.multiWindowS, FEED.streakMin)
	end

	t.test("feedLine: a fall first keeps FIRST BLOOD; then DOUBLE!, TRIPLE!, STREAK and FINAL KILL in order", function()
		local memory = Format.newFeedMemory()
		local fall = line(memory, ko(1, nil, C, 5, { cause = "outOfBounds" }))
		expect.equal(fall.by, nil)
		expect.equal(fall.cause, "outOfBounds")
		expect.equal(fall.tag, nil)
		expect.equal(line(memory, ko(2, A, B, 10, { streak = 1 })).tag, "firstBlood")
		expect.equal(line(memory, ko(3, A, C, 13.99, { streak = 2 })).tag, "double") -- 3.99 s later
		expect.equal(line(memory, ko(4, A, D, 17.98, { streak = 3 })).tag, "triple") -- 3.99 s later again
		local late = line(memory, ko(5, A, B, 22, { streak = 4 })) -- 4.02 s later: the run starts over
		expect.equal(late.tag, "streak")
		expect.equal(Format.tagText(late), "4 STREAK")
		expect.equal(line(memory, ko(6, B, A, 22.5, { streak = 1 })).tag, nil)
		expect.equal(line(memory, ko(7, B, C, 30, { streak = 2, final = true })).tag, "final")
	end)

	t.test("feedLine: the 4 s window edge: 3.99 s doubles, 4.01 s starts over", function()
		local memory = Format.newFeedMemory()
		line(memory, ko(1, A, B, 100, { streak = 1 }))
		expect.equal(line(memory, ko(2, A, C, 103.99, { streak = 1 })).tag, "double")
		expect.equal(line(memory, ko(3, A, D, 108, { streak = 1 })).tag, nil) -- 4.01 s after the last
	end)

	t.test("feedLine: a first K.O. that is final shows FINAL KILL and uses FIRST BLOOD up", function()
		local memory = Format.newFeedMemory()
		expect.equal(line(memory, ko(1, A, B, 10, { final = true })).tag, "final")
		expect.equal(line(memory, ko(2, C, D, 50)).tag, nil)
	end)

	t.test("feedLine: no FIRST BLOOD after a late start; mine; not a K.O. makes no line", function()
		local memory = Format.newFeedMemory()
		expect.equal(line(memory, ko(5, A, B, 10)).tag, nil) -- the first moment seen is seq 5
		expect.equal(line(memory, ko(6, YOU, B, 30)).mine, "by")
		expect.equal(line(memory, ko(7, A, YOU, 60)).mine, "victim")
		expect.equal(line(memory, ko(8, A, B, 90)).mine, nil)
		expect.equal(line(memory, { seq = 9, kind = "revived", victim = A }), nil)
		expect.equal(line(memory, "nope"), nil)
		expect.equal(Format.tagText({ victim = B, cause = "hit", tag = "final" }), "FINAL KILL")
		expect.equal(Format.tagText({ victim = B, cause = "hit" }), nil)
	end)

	t.test("feedPose: in 0.5 s, held, out at 4.6 s for 0.4 s, gone at 5.0 s; an early leave starts at once", function()
		local phase, u = Format.feedPose(0.25, nil, FEED)
		expect.equal(phase, "in")
		expect.near(u, 0.5, EPS)
		expect.equal((Format.feedPose(2, nil, FEED)), "hold")
		phase, u = Format.feedPose(4.8, nil, FEED)
		expect.equal(phase, "out")
		expect.near(u, 0.5, EPS)
		expect.equal((Format.feedPose(5.01, nil, FEED)), "gone")
		phase, u = Format.feedPose(1.2, 1, FEED) -- left early at 1.0 s
		expect.equal(phase, "out")
		expect.near(u, 0.5, EPS)
	end)

	t.test("playerLook: TDM by team, FFA's six colours in turn; deadColor greys and darkens", function()
		local red = Config.Match.teamNames[1]
		local blue = Config.Match.teamNames[2]
		expect.equal(Format.playerLook("tdm", red, 3).text, Palette.MatchTeamRedText)
		expect.equal(Format.playerLook("tdm", blue, 3).mid, Palette.StickerTdmBlue)
		expect.equal(Format.playerLook("tdm", nil, 1).text, Palette.StickerTextSoft)
		expect.equal(Format.playerLook("ffa", nil, 1), Format.playerLook("ffa", nil, 7))
		expect.equal(Format.playerLook("ffa", nil, 2).text, Palette.MatchFfaCyan)
		expect.equal(Format.playerLook("ffa", nil, nil).text, Palette.StickerTextSoft)
		local grey = Format.deadColor(Color3.new(1, 1, 1), 0.85, 0.85)
		expect.near(grey.R, 0.85, 1e-4)
		local red2 = Format.deadColor(Color3.new(1, 0, 0), 1, 1)
		expect.near(red2.R, 0.2126, 1e-4)
		expect.near(red2.G, 0.2126, 1e-4)
	end)

	t.test("cardShows: you squished and the match goes on, with or without an attacker", function()
		local view = { you = { userId = YOU }, matchPhase = "Active" }
		expect.equal(Format.cardShows({ kind = "ko", victim = YOU, by = A, final = false }, view), true)
		expect.equal(Format.cardShows({ kind = "ko", victim = YOU, final = false, cause = "storm" }, view), true)
		expect.equal(Format.cardShows({ kind = "ko", victim = YOU, by = A, final = true }, view), false)
		expect.equal(Format.cardShows({ kind = "ko", victim = A, by = YOU, final = false }, view), false)
		expect.equal(
			Format.cardShows({ kind = "ko", victim = YOU, by = A }, { you = view.you, matchPhase = "Result" }),
			false
		)
		expect.equal(
			Format.cardShows({ kind = "ko", victim = YOU, by = A }, { you = view.you, matchPhase = "Overtime" }),
			true
		)
	end)

	t.test(
		"the card's words: a title for every squishy (Birdie is bird), the fallback, the storm / fall words",
		function()
			local fallback = Format.squishyTitle("not_a_squishy")
			expect.equal(fallback, "Squishy Slinger")
			for _, def in Catalog.list() do
				expect.truthy(Format.squishyTitle(def.id) ~= fallback)
			end
			expect.equal(Format.squishyTitle("bird"), "Fluff Flyer")
			expect.equal(Format.causeCard("storm").pill, "THE STORM")
			expect.equal(Format.causeCard("outOfBounds").pill, "A FALL")
			expect.equal(Format.causeCard("hit"), Format.causeCard("other"))
			expect.equal(Format.causeCard(nil), Format.causeCard("other"))
		end
	)

	t.test(
		"the RESPAWNING bar: shown while coming back; whole seconds (at least 1); the fill from server time",
		function()
			local function view(you: { [string]: any }, phase: string?): any
				return { you = you, matchPhase = phase or "Active" }
			end
			expect.equal(Format.respawnShows(view({ alive = false, out = false, respawnAt = 5 })), true)
			expect.equal(Format.respawnShows(view({ alive = false, out = false, respawnAt = 5 }, "Overtime")), true)
			expect.equal(Format.respawnShows(view({ alive = false, out = false, respawnAt = 5 }, "Result")), false)
			expect.equal(Format.respawnShows(view({ alive = false, out = true, respawnAt = nil })), false)
			expect.equal(Format.respawnShows(view({ alive = true, out = false })), false)
			expect.equal(Format.respawnLeft(102.4, 100), 3)
			expect.equal(Format.respawnLeft(102.4, 102.4), 1)
			expect.equal(Format.respawnLeft(102.4, 104), 1)
			expect.near(Format.respawnShare(102.4, 100, 3), 0.2, EPS)
			expect.equal(Format.respawnShare(102.4, 102.4, 3), 1)
			expect.equal(Format.respawnShare(102.4, 98, 3), 0) -- clamped
			expect.equal(Format.respawnShare(102.4, 100, 0), 1) -- a bad total
		end
	)

	-- An 844 x 390 phone at the .85 UI scale floor, with touch: the zone and five buttons (px, ControlsController's
	-- touchLayout at that size; qb1: Catch too, catching works in a match).
	local PHONE_PX = Vector2.new(844, 390)
	local LAYOUT = {
		throw = { x = 645, y = 282, w = 88, h = 88 },
		ultimate = { x = 551, y = 188, w = 68, h = 68 },
		dash = { x = 561, y = 300, w = 68, h = 68 },
		jump = { x = 744, y = 290, w = 90, h = 90 },
		catch = { x = 697, y = 208, w = 68, h = 68 },
	}
	local CARD_CFG = {
		left = 22,
		bottom = 22,
		top = 8,
		gap = 16,
		fitMin = 0.6,
		compact = true,
		compactShare = 0.62,
	}
	local BAR_CFG = { bottom = 30, gap = 16, top = 8, scales = { 1, 0.9, 0.8, 0.7, 0.6 }, fitMin = 0.6 }

	local function rectOf(place: any, size: Vector2): any
		return { x = place.x, y = place.y, w = size.X * place.scale, h = size.Y * place.scale }
	end

	local function apart(a: any, b: any, gap: number): boolean
		return a.x + a.w + gap <= b.x + EPS
			or b.x + b.w + gap <= a.x + EPS
			or a.y + a.h + gap <= b.y + EPS
			or b.y + b.h + gap <= a.y + EPS
	end

	t.test("touchAreas: the thumbstick zone and Throw / Ultimate / Dash / jump / Catch in base px", function()
		local areas = Format.touchAreas(PHONE_PX, 0.85, LAYOUT, Config.UI.Touch)
		expect.equal(#areas, 6)
		expect.near(areas[6].x, 697 / 0.85, 1e-3) -- qb1: the Catch button
		local zone = areas[1]
		expect.equal(zone.kind, "zone")
		expect.near(zone.x, 0, EPS)
		expect.near(zone.y, 390 * (1 - Config.UI.Touch.thumbstickZoneHeight) / 0.85, 1e-3)
		expect.near(zone.w, 844 * Config.UI.Touch.thumbstickZoneWidth / 0.85, 1e-3)
		expect.near(areas[2].x, 645 / 0.85, 1e-3)
		expect.equal(areas[2].kind, "button")
		expect.equal(#Format.touchAreas(PHONE_PX, 0.85, nil, Config.UI.Touch), 1)
	end)

	t.test("phone with touch: the card above the thumbstick zone, shrunk; the bar beside it, off the zone", function()
		local canvas = Format.canvas(PHONE_PX, 0.85)
		local areas = Format.touchAreas(PHONE_PX, 0.85, LAYOUT, Config.UI.Touch)
		local zone = areas[1]
		local card = Format.cardPlace(canvas, areas, CARD, CARD_CFG)
		expect.equal(card.kind, "aboveTouch")
		expect.near(card.scale, (zone.y - 16 - 8) / CARD.Y, 1e-4)
		expect.truthy(card.scale >= 0.6 and card.scale < 1)
		local cardRect = rectOf(card, CARD)
		expect.truthy(apart(cardRect, zone, 16))
		local bar = Format.barPlace(canvas, { zone }, cardRect, BAR, BAR_CFG)
		expect.equal(bar.kind, "beside")
		expect.equal(bar.scale, 1)
		local barRect = rectOf(bar, BAR)
		expect.truthy(apart(barRect, zone, 16))
		expect.truthy(apart(barRect, cardRect, 16))
		expect.truthy(barRect.x + barRect.w <= canvas.X + EPS)
	end)

	t.test("desktop 1440 x 810: the card bottom left and the bar bottom centre, as M draws them", function()
		local canvas = Vector2.new(1440, 810)
		local cfg = table.clone(CARD_CFG)
		cfg.compact = false
		local card = Format.cardPlace(canvas, {}, CARD, cfg)
		expect.equal(card.kind, "corner")
		expect.equal(card.scale, 1)
		expect.near(card.y, 810 - 22 - CARD.Y, EPS)
		local bar = Format.barPlace(canvas, {}, rectOf(card, CARD), BAR, BAR_CFG)
		expect.equal(bar.kind, "centre")
		expect.near(bar.x, (1440 - 380) / 2, EPS)
		expect.near(bar.y, 810 - 30 - BAR.Y, EPS)
	end)

	t.test("1024 x 768 and a 844 x 390 window without touch: the bar moves beside the card (v1 §1.3h)", function()
		for _, case in { { px = Vector2.new(1024, 768), compact = false }, { px = PHONE_PX, compact = true } } do
			local canvas = Format.canvas(case.px, 0.85)
			local cfg = table.clone(CARD_CFG)
			cfg.compact = case.compact
			local card = Format.cardPlace(canvas, {}, CARD, cfg)
			expect.equal(card.kind, "corner")
			if case.compact then
				expect.truthy(card.scale <= 0.62 * canvas.Y / CARD.Y + EPS)
			end
			local cardRect = rectOf(card, CARD)
			local bar = Format.barPlace(canvas, {}, cardRect, BAR, BAR_CFG)
			expect.equal(bar.kind, "beside")
			expect.truthy(apart(rectOf(bar, BAR), cardRect, 16))
		end
	end)

	t.test("a narrow screen: no room beside the card, so the bar sits above it", function()
		local canvas = Vector2.new(600, 810)
		local cfg = table.clone(CARD_CFG)
		cfg.compact = false
		local card = Format.cardPlace(canvas, {}, CARD, cfg)
		local cardRect = rectOf(card, CARD)
		local bar = Format.barPlace(canvas, {}, cardRect, BAR, BAR_CFG)
		expect.equal(bar.kind, "above")
		expect.truthy(apart(rectOf(bar, BAR), cardRect, 16))
	end)

	t.test("trackPose: the design track, or under reduced motion only its fade (at most the fade time)", function()
		local show = Config.UI.Match.card.show
		local done = Format.trackPose(show.frames, show.ms / 1000, show.ms, nil, show.wholeRun, false, 120)
		expect.near(done.x, 0, EPS)
		expect.near(done.scale, 1, EPS)
		expect.near(done.alpha, 1, EPS)
		local start = Format.trackPose(show.frames, 0, show.ms, nil, show.wholeRun, true, 120)
		expect.equal(start.x, nil)
		expect.near(start.alpha, 0, EPS)
		expect.near(Format.trackPose(show.frames, 0.06, show.ms, nil, show.wholeRun, true, 120).alpha, 0.5, EPS)
		expect.near(Format.trackPose(show.frames, 0.2, show.ms, nil, show.wholeRun, true, 120).alpha, 1, EPS)
	end)

	t.test("clipText: cut with an ellipsis to fit the room", function()
		local function measure(text: string): number
			return (utf8.len(text) or #text) * 10
		end
		expect.equal(Format.clipText("Bob", 60, measure), "Bob")
		expect.equal(Format.clipText("SquishQueen", 60, measure), "Squis…")
		expect.equal(Format.clipText("SquishQueen", 5, measure), "…")
	end)
end
