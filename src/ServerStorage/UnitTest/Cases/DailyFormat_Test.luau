--!strict
-- DailyFormat_Test: StarterPlayerScripts.Client.UI.DailyFormat (the Daily panel and the daily stand sign). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §6.9, §7.7, §11.6):
--   * the day changes at 00:00 UTC of the server time: 23:59:59 still counts as the claimed day, 00:00:00 is a new one;
--   * the day after a claim continues the streak (Day 7 wraps to Day 1); a missed day only pauses it (review quick win
--     2026-10-14): the next claim pays the next day and the panel greets the player with daily.welcomeBack; a first
--     claim is Day 1 without that line;
--   * 7 day cards with "Day n", the Coins of that day and the free Treat Box on day 7; today highlighted; the days of
--     the cycle already claimed carry "Claimed"; Phase 5 (progression spec 2026-10-12 §9): a day's Coins are its
--     squeezes (Config.Economy.Daily.coinsByDay) × the player's squeeze value (pens3 phase 1: PenMath.squeezeValue of
--     the pen passed in; a new player's 10 without it), as the server pays at claim time;
--   * once today is claimed: "Come back in {time}" until 00:00 UTC; the sign reads "Ready to claim!" or
--     "Next reward in {time}", nothing while the state is unknown;
--   * UI FINAL R8 (the design's Daily window, plan work/ui/PLAN.md R8): the card looks (claimed lilac, today's
--     claimable day yellow with the white border, else purple), Tomorrow / locked / the value / the foot, the streak
--     and timer pills, the stamp's rest and the day 7 flow, and the grid (the design's 4 columns and 2 rows on its
--     body, never under the natural faces; 3 columns and day 7 under them on phones); bodyHeight stays
--     (CapsuleController's).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local DailyFormat = t.requireClient("UI/DailyFormat")
	local Config = t.requireShared("Config")
	local PenMath = t.requireShared("PenMath")
	local Format = t.requireShared("Util/Format")
	local Strings = t.requireShared("Strings")
	local DAILY = Config.Economy.Daily
	local DAYS = #DAILY.coinsByDay
	-- A new player's squeeze value (no pen passed in): 10 Coins (Config.Economy.Pen.minSqueezeValue).
	local VALUE = PenMath.squeezeValue(nil)

	local D = 20000 -- a UTC day index
	local START = D * 86400 -- 00:00:00 UTC of day D
	local LAST_SECOND = START + 86399 -- 23:59:59 UTC of day D
	local NEXT_DAY = START + 86400 -- 00:00:00 UTC of day D + 1
	local NOON = START + 43200

	local function daily(lastClaimDay: number, streakDay: number): any
		return { lastClaimDay = lastClaimDay, streakDay = streakDay, totalClaims = math.max(0, streakDay) }
	end

	local function claimedDays(model: any): { number }
		local list = {}
		for _, card in model.cards do
			if card.claimed then
				table.insert(list, card.day)
			end
		end
		return list
	end

	local function todayDays(model: any): { number }
		local list = {}
		for _, card in model.cards do
			if card.today then
				table.insert(list, card.day)
			end
		end
		return list
	end

	t.test("UTC rollover: 23:59:59 is still the claimed day, 00:00:00 is a new day", function()
		local claimed = daily(D, 3)
		expect.equal(DailyFormat.today(LAST_SECOND), D)
		expect.equal(DailyFormat.today(NEXT_DAY), D + 1)
		expect.equal(DailyFormat.canClaim(claimed, DailyFormat.today(LAST_SECOND)), false)
		expect.equal(DailyFormat.canClaim(claimed, DailyFormat.today(NEXT_DAY)), true)
		expect.equal(DailyFormat.model(claimed, LAST_SECOND).canClaim, false)
		local after = DailyFormat.model(claimed, NEXT_DAY)
		expect.equal(after.canClaim, true)
		expect.equal(after.nextDay, 4)
		expect.equal(after.welcomeBack, false)
		expect.equal(DailyFormat.signText(claimed, LAST_SECOND), Strings.format(Strings.daily.wait, { time = "0:01" }))
		expect.equal(DailyFormat.signText(claimed, NEXT_DAY), Strings.daily.ready)
	end)

	t.test("streak: the next day continues, Day 7 wraps to Day 1", function()
		expect.equal(DailyFormat.nextDay(daily(D - 1, 3), D), 4)
		expect.equal(DailyFormat.welcomeBack(daily(D - 1, 3), D), false)
		expect.equal(DailyFormat.nextDay(daily(D - 1, DAYS), D), 1)
		expect.equal(DailyFormat.welcomeBack(daily(D - 1, DAYS), D), false)
		-- A first claim ever (the profile defaults): Day 1, no welcome back line.
		local first = DailyFormat.model(daily(-1, 0), NOON)
		expect.equal(first.canClaim, true)
		expect.equal(first.nextDay, 1)
		expect.equal(first.welcomeBack, false)
		expect.equal(first.welcomeText, nil)
		expect.deepEqual(claimedDays(first), {})
		expect.deepEqual(todayDays(first), { 1 })
	end)

	t.test("welcome back: a missed day pauses the streak; the panel names the day that is waiting", function()
		local missed = daily(D - 2, 5)
		expect.equal(DailyFormat.welcomeBack(missed, D), true)
		expect.equal(DailyFormat.nextDay(missed, D), 6)
		local model = DailyFormat.model(missed, NOON)
		expect.equal(model.canClaim, true)
		expect.equal(model.welcomeBack, true)
		expect.equal(model.welcomeText, Strings.format(Strings.daily.welcomeBack, { n = 6 }))
		expect.deepEqual(claimedDays(model), { 1, 2, 3, 4, 5 })
		expect.deepEqual(todayDays(model), { 6 })
		expect.equal(model.coins, DAILY.coinsByDay[6] * VALUE)
		-- A long break pauses too; after Day 7 a new cycle starts at Day 1.
		expect.equal(DailyFormat.nextDay(daily(D - 40, 2), D), 3)
		expect.equal(DailyFormat.nextDay(daily(D - 3, DAYS), D), 1)
		-- Once today is claimed nothing is waiting any more: no line.
		local claimed = DailyFormat.model(daily(D, 6), NOON)
		expect.equal(claimed.welcomeBack, false)
		expect.equal(claimed.welcomeText, nil)
	end)

	t.test("day cards: labels, Coins, the day 7 Treat Box, today highlighted, claimed days", function()
		local model = DailyFormat.model(daily(D - 1, 3), NOON)
		expect.equal(#model.cards, DAYS)
		for n, card in model.cards do
			expect.equal(card.day, n)
			expect.equal(card.label, Strings.format(Strings.daily.dayLabel, { n = n }))
			expect.equal(card.coins, DAILY.coinsByDay[n] * VALUE)
			expect.equal(
				card.coinsText,
				Strings.format(Strings.common.coinsAmount, { coins = Format.coins(DAILY.coinsByDay[n] * VALUE) })
			)
			expect.equal(card.treat, n == DAILY.freeBoxDay)
			if n == DAILY.freeBoxDay then
				expect.equal(card.treatText, Strings.daily.treatBox)
			else
				expect.equal(card.treatText, nil)
			end
		end
		expect.equal(model.cards[7].treat, true)
		expect.equal(model.cards[7].treatText, Strings.daily.treatBox)
		expect.deepEqual(claimedDays(model), { 1, 2, 3 })
		expect.deepEqual(todayDays(model), { 4 })
		expect.equal(model.cards[3].claimedText, Strings.common.claimed)
		expect.equal(model.cards[4].claimedText, nil)
		expect.equal(model.cards[4].todayText, Strings.daily.today)
		expect.equal(model.cards[3].todayText, nil)
		-- Day 7 itself: the Treat Box day is the one offered.
		local seventh = DailyFormat.model(daily(D - 1, 6), NOON)
		expect.equal(seventh.nextDay, 7)
		expect.equal(seventh.treat, true)
		expect.equal(seventh.coins, DAILY.coinsByDay[7] * VALUE)
		expect.deepEqual(todayDays(seventh), { 7 })
	end)

	t.test("a day's Coins are its squeezes × the squeeze value of the player's pen (pens3 phase 1)", function()
		-- Kitty Bread (10/s) and Butter (40/s) walk in the pen: 50 Coins a squeeze.
		local items: { any } = {
			{ id = 1, kind = "kitty_bread", form = 0, level = 1, coat = 0 },
			{ id = 2, kind = "butter", form = 0, level = 1, coat = 0 },
		}
		local pen = { spots = 3, nextId = 3, items = items }
		local value = PenMath.squeezeValue(pen)
		expect.equal(value, 50)
		local model = DailyFormat.model(daily(D - 1, 3), NOON, pen)
		for n, card in model.cards do
			expect.equal(card.coins, DAILY.coinsByDay[n] * value)
			expect.equal(
				card.coinsText,
				Strings.format(Strings.common.coinsAmount, { coins = Format.coins(DAILY.coinsByDay[n] * value) })
			)
		end
		expect.equal(model.coins, DAILY.coinsByDay[4] * value) -- day 4 is next
		-- The same rule as the server's reward (PenMath.rewardCoins: floored, never past the Coins cap).
		expect.equal(model.cards[1].coins, PenMath.rewardCoins(DAILY.coinsByDay[1], value))
	end)

	t.test("claimed today: Come back in {time} until 00:00 UTC; the sign counts down", function()
		local claimed = daily(D, 3)
		local model = DailyFormat.model(claimed, NOON)
		expect.equal(model.canClaim, false)
		expect.equal(model.nextDay, 3)
		expect.deepEqual(claimedDays(model), { 1, 2, 3 })
		expect.deepEqual(todayDays(model), { 3 })
		expect.equal(model.secondsLeft, 43200)
		expect.equal(model.countdownText, Strings.format(Strings.daily.comeBack, { time = "12:00:00" }))
		expect.equal(DailyFormat.countdownText(NOON), "12:00:00")
		expect.equal(DailyFormat.countdownText(LAST_SECOND), "0:01")
		expect.equal(DailyFormat.signText(claimed, NOON), Strings.format(Strings.daily.wait, { time = "12:00:00" }))
		-- A claimable day has no countdown line.
		expect.equal(DailyFormat.model(daily(D - 1, 3), NOON).countdownText, nil)
	end)

	t.test("unknown state: nothing offered, the sign stays as it is", function()
		local bads: { any } = { false, "daily", { lastClaimDay = "x", streakDay = 1 }, { lastClaimDay = 0 / 0 } }
		table.insert(bads, { lastClaimDay = 0 / 0, streakDay = 1 })
		local missing = DailyFormat.model(nil, NOON)
		expect.equal(missing.known, false)
		expect.equal(missing.canClaim, false)
		expect.equal(DailyFormat.signText(nil, NOON), nil)
		for _, bad in bads do
			local model = DailyFormat.model(bad, NOON)
			expect.equal(model.known, false)
			expect.equal(model.canClaim, false)
			expect.deepEqual(claimedDays(model), {})
			expect.deepEqual(todayDays(model), {})
			expect.equal(DailyFormat.signText(bad, NOON), nil)
		end
		expect.equal(DailyFormat.signText(daily(D, 1), 0 / 0), nil)
	end)

	-- UI FINAL R8 (the design's Daily window, plan work/ui/PLAN.md R8; `H:n` = "Squishy Duels HUD.dc.html" line n) -----

	local Palette = t.requireShared("Art/Palette")
	local UI = Config.UI.Daily

	t.test(
		"card looks (R8, H:965-966): claimed lilac, today's claimable day yellow with the white border, else purple",
		function()
			local function looks(model: any): { string }
				local list = {}
				for _, card in model.cards do
					local look = DailyFormat.cardLook(card)
					table.insert(list, look.top .. "/" .. look.border)
				end
				return list
			end
			local CLAIMED, TODAY, PLAIN =
				"StickerDayClaimedTop/StickerInk", "StickerCreamYellow/White", "StickerCardTop/StickerInk"
			-- Days 1-3 claimed, day 4 today.
			expect.deepEqual(
				looks(DailyFormat.model(daily(D - 1, 3), NOON)),
				{ CLAIMED, CLAIMED, CLAIMED, TODAY, PLAIN, PLAIN, PLAIN }
			)
			-- Claimed today: today's card takes the claimed look (the design's i < streak), nothing is yellow.
			expect.deepEqual(
				looks(DailyFormat.model(daily(D, 3), NOON)),
				{ CLAIMED, CLAIMED, CLAIMED, PLAIN, PLAIN, PLAIN, PLAIN }
			)
			-- Unknown state: every card plain.
			expect.deepEqual(looks(DailyFormat.model(nil, NOON)), { PLAIN, PLAIN, PLAIN, PLAIN, PLAIN, PLAIN, PLAIN })
			-- The two stops (today #FFF3A6 -> #FFC23A, H:965), the names (H:966) and the claimed icon at .5 (H:398).
			local open = DailyFormat.model(daily(D - 1, 3), NOON)
			local today, claimed, plain =
				DailyFormat.cardLook(open.cards[4]),
				DailyFormat.cardLook(open.cards[1]),
				DailyFormat.cardLook(open.cards[5])
			expect.deepEqual(today, {
				top = "StickerCreamYellow",
				bottom = "StickerGoldMid",
				border = "White",
				name = "StickerFoundText",
				iconAlpha = 1,
			})
			expect.equal(claimed.bottom, "StickerDayClaimedEnd")
			expect.equal(claimed.name, "StickerDayClaimedText")
			expect.equal(claimed.iconAlpha, UI.card.claimedIconAlpha)
			expect.equal(plain.name, "White")
			for _, look in { today, claimed, plain } do
				for _, key in { look.top, look.bottom, look.border, look.name } do
					expect.truthy(typeof((Palette :: any)[key]) == "Color3")
				end
			end
			expect.equal(Palette.StickerCreamYellow:ToHex():upper(), "FFF3A6")
			expect.equal(Palette.StickerGoldMid:ToHex():upper(), "FFC23A")
			expect.equal(Palette.StickerDayClaimedTop:ToHex():upper(), "D8CCF5")
		end
	)

	t.test("next, locked, the value and the foot (R8, H:399-403, H:964)", function()
		local function daysWith(model: any, field: string): { number }
			local list = {}
			for _, card in model.cards do
				if card[field] then
					table.insert(list, card.day)
				end
			end
			return list
		end
		local function feet(model: any): { string }
			local list = {}
			for _, card in model.cards do
				table.insert(list, card.foot)
			end
			return list
		end
		local F = {
			claimed = Strings.common.claimed,
			claim = Strings.daily.footClaim,
			tomorrow = Strings.daily.tomorrow,
			locked = Strings.daily.footLocked,
		}
		-- Day 4 claimable: no Tomorrow, the days after it locked.
		local open = DailyFormat.model(daily(D - 1, 3), NOON)
		expect.deepEqual(daysWith(open, "next"), {})
		expect.deepEqual(daysWith(open, "locked"), { 5, 6, 7 })
		expect.deepEqual(feet(open), { F.claimed, F.claimed, F.claimed, F.claim, F.locked, F.locked, F.locked })
		expect.equal(open.cards[1].valueText, Format.coins(PenMath.rewardCoins(DAILY.coinsByDay[1], VALUE)))
		expect.equal(open.cards[DAYS].valueText, Strings.daily.treatBox)
		-- Day 3 claimed today: day 4 is Tomorrow, the days after it locked.
		local claimed = DailyFormat.model(daily(D, 3), NOON)
		expect.deepEqual(daysWith(claimed, "next"), { 4 })
		expect.deepEqual(daysWith(claimed, "locked"), { 5, 6, 7 })
		expect.deepEqual(feet(claimed), { F.claimed, F.claimed, F.claimed, F.tomorrow, F.locked, F.locked, F.locked })
		-- Day 7 claimed today: the cycle is done, nothing is next or locked.
		local full = DailyFormat.model(daily(D, DAYS), NOON)
		expect.deepEqual(daysWith(full, "next"), {})
		expect.deepEqual(daysWith(full, "locked"), {})
		-- Day 7 claimable: its foot is Claim!.
		expect.equal(DailyFormat.model(daily(D - 1, 6), NOON).cards[DAYS].foot, F.claim)
		-- Unknown: no lock, no Tomorrow.
		local unknown = DailyFormat.model(nil, NOON)
		expect.deepEqual(daysWith(unknown, "locked"), {})
		expect.deepEqual(daysWith(unknown, "next"), {})
		expect.equal(Strings.daily.claimTag, "CLAIM!")
		expect.deepEqual(F, { claimed = "Claimed", claim = "Claim!", tomorrow = "Tomorrow", locked = "Locked" }) -- H:964
	end)

	t.test("the streak and timer pills (R8, H:390-391, H:1029, FD6)", function()
		local open = DailyFormat.model(daily(D - 1, 3), NOON)
		expect.equal(open.streakText, Strings.format(Strings.daily.dayLabel, { n = 4 }))
		expect.equal(open.timerText, Strings.daily.readyNow)
		expect.equal(Strings.daily.readyNow, "Your reward is ready!")
		local claimed = DailyFormat.model(daily(D, 3), NOON)
		expect.equal(claimed.streakText, Strings.format(Strings.daily.dayLabel, { n = 3 }))
		expect.equal(claimed.timerText, Strings.format(Strings.daily.wait, { time = "12:00:00" }))
		expect.equal(DailyFormat.model(nil, NOON).timerText, nil)
		expect.equal(DailyFormat.model(nil, NOON).streakText, Strings.format(Strings.daily.dayLabel, { n = 1 }))
	end)

	t.test(
		"the stamp (H:41) is drawn at its rest -10°, the frames relative to it; the day 7 box flow (H:858)",
		function()
			local stamp = UI.stamp
			expect.equal(stamp.restRot, -10)
			local first, mid, last = stamp.frames[1], stamp.frames[2], stamp.frames[#stamp.frames]
			expect.near(first.rot + stamp.restRot, -25, 1e-9)
			expect.near(mid.rot + stamp.restRot, -8, 1e-9)
			expect.near(last.rot + stamp.restRot, -10, 1e-9) -- the reduced-motion rest is the authored one
			expect.equal(first.scale, 3)
			expect.equal(first.alpha, 0)
			expect.near(mid.at, 0.6, 1e-9)
			expect.equal(stamp.ms, 500)
			expect.equal(UI.boxFlow.closeAfterMs, 750)
			expect.equal(UI.boxFlow.revealAfterMs, 280)
			expect.equal(UI.claimSoundDelayMs, 120)
		end
	)

	-- The design's body inside the 980 x 620 window (H:382-393): 980 - 2 x (5 + 26) wide; 620 less the top padding
	-- (border 5 + band 98 + 18) and the bottom (26 + 5), less the top row (40) and its gap (16).
	local WIDTH = 980 - 2 * (5 + UI.body.padX)
	local ROOM = 620 - (5 + 98 + UI.body.padTop) - (UI.body.padBottom + 5) - UI.streak.height - UI.body.gap
	local TEXT = Config.UI.TextSize

	t.test("grid (R8, H:393): 1fr 1fr 1fr 1.25fr, two rows of 199 on the design body, day 7 over both", function()
		expect.equal(WIDTH, 918)
		expect.equal(ROOM, 412)
		local cardFace = DailyFormat.cardFace(TEXT.Body, TEXT.H2)
		local day7Face = DailyFormat.day7Face(TEXT.HudNumber, TEXT.Large, 20)
		expect.truthy(cardFace <= 199) -- the design's card fits its row at Medium text
		local layout = DailyFormat.gridLayout(WIDTH, ROOM, false, cardFace, day7Face)
		local lip, lip7 = UI.card.lip, UI.day7.lip
		expect.equal(#layout.cards, DAYS - 1)
		expect.deepEqual(layout.cards[1], { x = 0, y = 0, w = 206, h = 199 + lip })
		expect.deepEqual(layout.cards[3], { x = 440, y = 0, w = 206, h = 199 + lip })
		expect.deepEqual(layout.cards[4], { x = 0, y = 213, w = 206, h = 199 + lip })
		expect.deepEqual(layout.day7, { x = 660, y = 0, w = 258, h = 2 * 199 + 14 + lip7 })
		expect.equal(layout.height, ROOM + math.max(lip, lip7)) -- no scroll: the lips hang into the padding
		-- A room too small: the faces keep their natural height (the grid scrolls).
		local short = DailyFormat.gridLayout(WIDTH, 200, false, cardFace, day7Face)
		expect.equal(short.cards[1].h, cardFace + lip)
		expect.truthy(short.height > 200)
		expect.equal(DailyFormat.gridLayout(0 / 0, 0 / 0, false, cardFace, day7Face).cards[1].h, cardFace + lip)
	end)

	t.test("grid on phones (plan R8): three columns, day 7 under them at its natural height", function()
		local cardFace = DailyFormat.cardFace(TEXT.Body, TEXT.H2)
		local day7Face = DailyFormat.day7Face(TEXT.HudNumber, TEXT.Large, 20)
		local width = 639
		local layout = DailyFormat.gridLayout(width, 150, true, cardFace, day7Face)
		local unit = math.floor((width - 2 * 14) / 3)
		local lip = UI.card.lip
		expect.deepEqual(layout.cards[1], { x = 0, y = 0, w = unit, h = cardFace + lip })
		expect.deepEqual(layout.cards[3], { x = 2 * (unit + 14), y = 0, w = unit, h = cardFace + lip })
		expect.deepEqual(layout.cards[6], { x = 2 * (unit + 14), y = cardFace + 14, w = unit, h = cardFace + lip })
		expect.deepEqual(layout.day7, { x = 0, y = 2 * (cardFace + 14), w = width, h = day7Face + UI.day7.lip })
		expect.equal(layout.height, 2 * (cardFace + 14) + day7Face + UI.day7.lip)
		-- The natural faces (H:395-416): the border, the padding, the lines, the icon / art and the gaps.
		expect.equal(cardFace, 2 * 4 + 10 + 10 + 18 + 84 + 22 + 34 + 3 * 4)
		expect.equal(day7Face, 2 * 4 + 14 + 14 + 26 + 26 + 170 + 28 + 20 + 4 * 6)
	end)

	-- Part 8 (kept for CapsuleController, its one caller now): a scrolling panel part within maxShare of the screen.
	t.test("bodyHeight: the content's height, capped to the screen share, never under the minimum", function()
		local SHARE = 0.86
		expect.equal(DailyFormat.bodyHeight(864, 180, 172, SHARE, 52), 180)
		expect.equal(DailyFormat.bodyHeight(441, 10, 172, SHARE, 52), 52)
		expect.equal(DailyFormat.bodyHeight(0 / 0, 0 / 0, 0 / 0, SHARE, 52), 52)
		expect.near(DailyFormat.bodyHeight(500, 1000, 100, SHARE, 52), 500 * SHARE - 100, 1e-9)
	end)
end
