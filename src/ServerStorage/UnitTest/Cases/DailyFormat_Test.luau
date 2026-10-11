--!strict
-- DailyFormat_Test: StarterPlayerScripts.Client.UI.DailyFormat (the Daily panel and the daily stand sign). Server only
-- (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §6.9, §7.7, §11.6):
--   * the day changes at 00:00 UTC of the server time: 23:59:59 still counts as the claimed day, 00:00:00 is a new one;
--   * the day after a claim continues the streak (Day 7 wraps to Day 1 without a reset); a missed day restarts it at
--     Day 1 with the one-sentence reset rule; a first claim is Day 1 without that sentence;
--   * 7 day cards with "Day n", the Coins of that day and the free Treat Box on day 7; today highlighted; the days of
--     the cycle already claimed carry "Claimed";
--   * once today is claimed: "Come back in {time}" until 00:00 UTC; the sign reads "Ready to claim!" or
--     "Next reward in {time}", nothing while the state is unknown;
--   * Part 8 layout (§11.2; base px at 667×375, 1280×720 and 1920×1080, Medium and the largest text): the day cards
--     grow with the text so every word of a card fits it, wrap onto a second line when the row is too narrow (one row
--     at Medium text everywhere), and the panel stays within 86% of the screen height with its body scrolling;
--   * foam UI (2026-10-09): today's card is Sky blue with the thick outline (claimed today too), the Treat Box day
--     Lilac, claimed days Biscuit, each with its word; the chrome counts the header tab and Close above the panel.

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
	local Format = t.requireShared("Util/Format")
	local Strings = t.requireShared("Strings")
	local DAILY = Config.Economy.Daily
	local DAYS = #DAILY.coinsByDay

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
		expect.equal(after.reset, false)
		expect.equal(DailyFormat.signText(claimed, LAST_SECOND), Strings.format(Strings.daily.wait, { time = "0:01" }))
		expect.equal(DailyFormat.signText(claimed, NEXT_DAY), Strings.daily.ready)
	end)

	t.test("streak: the next day continues, Day 7 wraps to Day 1 without a reset", function()
		expect.equal(DailyFormat.nextDay(daily(D - 1, 3), D), 4)
		expect.equal(DailyFormat.isReset(daily(D - 1, 3), D), false)
		expect.equal(DailyFormat.nextDay(daily(D - 1, DAYS), D), 1)
		expect.equal(DailyFormat.isReset(daily(D - 1, DAYS), D), false)
		-- A first claim ever (the profile defaults): Day 1, no reset sentence.
		local first = DailyFormat.model(daily(-1, 0), NOON)
		expect.equal(first.canClaim, true)
		expect.equal(first.nextDay, 1)
		expect.equal(first.reset, false)
		expect.equal(first.resetText, nil)
		expect.deepEqual(claimedDays(first), {})
		expect.deepEqual(todayDays(first), { 1 })
	end)

	t.test("reset: a missed day restarts at Day 1 with the one-sentence rule", function()
		local missed = daily(D - 2, 5)
		expect.equal(DailyFormat.isReset(missed, D), true)
		expect.equal(DailyFormat.nextDay(missed, D), 1)
		local model = DailyFormat.model(missed, NOON)
		expect.equal(model.canClaim, true)
		expect.equal(model.reset, true)
		expect.equal(model.resetText, Strings.daily.streakReset)
		expect.deepEqual(claimedDays(model), {})
		expect.deepEqual(todayDays(model), { 1 })
		expect.equal(model.coins, DAILY.coinsByDay[1])
		-- After the claim the saved state no longer shows the miss: the reply's streakReset keeps the sentence.
		local claimed = daily(D, 1)
		expect.equal(DailyFormat.model(claimed, NOON).reset, false)
		local kept = DailyFormat.model(claimed, NOON, true)
		expect.equal(kept.reset, true)
		expect.equal(kept.resetText, Strings.daily.streakReset)
	end)

	t.test("day cards: labels, Coins, the day 7 Treat Box, today highlighted, claimed days", function()
		local model = DailyFormat.model(daily(D - 1, 3), NOON)
		expect.equal(#model.cards, DAYS)
		for n, card in model.cards do
			expect.equal(card.day, n)
			expect.equal(card.label, Strings.format(Strings.daily.dayLabel, { n = n }))
			expect.equal(card.coins, DAILY.coinsByDay[n])
			expect.equal(
				card.coinsText,
				Strings.format(Strings.common.coinsAmount, { coins = Format.coins(DAILY.coinsByDay[n]) })
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
		expect.equal(seventh.coins, DAILY.coinsByDay[7])
		expect.deepEqual(todayDays(seventh), { 7 })
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

	t.test("card looks (foam UI): today Sky + thick, Treat Box Lilac, claimed Biscuit, with words", function()
		local function looks(model: any): { string }
			local list = {}
			for _, card in model.cards do
				local look = DailyFormat.cardLook(card)
				table.insert(list, look.face .. (if look.thick then "+" else ""))
			end
			return list
		end
		-- Days 1-3 claimed, day 4 today, day 7 the Treat Box still to come.
		local model = DailyFormat.model(daily(D - 1, 3), NOON)
		expect.deepEqual(looks(model), { "biscuit", "biscuit", "biscuit", "sky+", "frosting", "frosting", "lilac" })
		-- Claimed today: today's card keeps Sky blue and the thick outline.
		expect.deepEqual(
			looks(DailyFormat.model(daily(D, 3), NOON)),
			{ "biscuit", "biscuit", "sky+", "frosting", "frosting", "frosting", "lilac" }
		)
		-- Day 7 is today: today wins over the Treat Box face.
		expect.equal(looks(DailyFormat.model(daily(D - 1, 6), NOON))[7], "sky+")
		-- Unknown state: plain cards, the Treat Box day still Lilac.
		expect.deepEqual(
			looks(DailyFormat.model(nil, NOON)),
			{ "frosting", "frosting", "frosting", "frosting", "frosting", "frosting", "lilac" }
		)
		-- Never colour alone: every coloured look comes with its word on the card.
		for _, state in { daily(D - 1, 3), daily(D, 3), daily(D - 1, 6) } do
			for _, card in DailyFormat.model(state, NOON).cards do
				local face = DailyFormat.cardLook(card).face
				if face == "sky" then
					expect.equal(card.todayText, Strings.daily.today)
				elseif face == "biscuit" then
					expect.equal(card.claimedText, Strings.common.claimed)
				elseif face == "lilac" then
					expect.equal(card.treatText, Strings.daily.treatBox)
				end
			end
		end
	end)

	-- Part 8 layout ---------------------------------------------------------------------------------------------------

	local Layout = t.requireClient("UI/Layout")
	local UI = Config.UI
	local LARGEST = UI.PreferredTextScale.Largest
	local SCREENS = { Vector2.new(667, 375), Vector2.new(1280, 720), Vector2.new(1920, 1080) }
	-- DailyController's numbers: panel 680 (modal margin 24), padding 20, card 84 with 6 px between cards and 6 px of
	-- padding, the scroll bar's 6 px, the panel at most 86% of the screen.
	local PANEL_WIDTH, MARGIN, PADDING, CARD, GAP, CARD_PADDING, SCROLLBAR = 680, 24, 20, 84, 6, 6, 6
	local SHARE = 0.86
	-- The longest word any day card shows (they wrap between words, never inside one).
	local function longestWord(): number
		local longest = 0
		local model = DailyFormat.model(daily(D - 1, 3), NOON)
		local texts = { Strings.common.claimed, Strings.daily.today, Strings.daily.treatBox }
		for _, card in model.cards do
			table.insert(texts, card.label)
			table.insert(texts, card.coinsText)
		end
		for _, text in texts do
			for word in string.gmatch(text, "%S+") do
				longest = math.max(longest, utf8.len(word) or #word)
			end
		end
		return longest
	end

	t.test("layout (Part 8): cards grow with the text, every word fits, they wrap only when they must", function()
		local letters = longestWord()
		expect.truthy(letters >= 5)
		for _, actual in SCREENS do
			local scale = Layout.uiScale(actual.Y)
			local panel = math.min(PANEL_WIDTH, Layout.modalWidth(actual.X, scale, MARGIN))
			local row = panel - 2 * PADDING - SCROLLBAR
			for _, textScale in { 1, UI.PreferredTextScale.Large, LARGEST } do
				local card = DailyFormat.cardWidth(CARD, textScale)
				expect.truthy(card >= CARD)
				-- About 0.6 em a letter (Nunito Bold / ExtraBold and Fredoka One, generous) at the card's Small and
				-- Chip text size (both 16 base px).
				local wordWidth = letters * 0.6 * UI.TextSize.Small * textScale
				expect.truthy(wordWidth + 2 * CARD_PADDING <= card)
				local perRow = DailyFormat.cardsPerRow(row, card, GAP)
				expect.truthy(perRow >= 1)
				expect.truthy(perRow * card + (perRow - 1) * GAP <= row + 1e-6)
				if textScale == 1 then
					expect.truthy(perRow >= 7) -- one row of 7 at Medium text on every screen
				end
			end
		end
		expect.equal(DailyFormat.cardWidth(CARD, 1), 84)
		expect.equal(DailyFormat.cardWidth(CARD, LARGEST), 122)
		expect.equal(DailyFormat.cardWidth(CARD, 0.5), 84) -- never narrower than the base
		expect.equal(DailyFormat.cardWidth(CARD, 0 / 0), 84)
		-- The phone at the largest text: the cards wrap (5 + 2).
		local phoneScale = Layout.uiScale(375)
		local phoneRow = math.min(PANEL_WIDTH, Layout.modalWidth(667, phoneScale, MARGIN)) - 2 * PADDING - SCROLLBAR
		expect.equal(DailyFormat.cardsPerRow(phoneRow, 122, GAP), 5)
		expect.equal(DailyFormat.cardsPerRow(50, 122, GAP), 1)
	end)

	t.test(
		"layout (Part 8): the panel stays within 86% of the screen, the cards and the reset sentence scroll",
		function()
			for _, actual in SCREENS do
				local screen = actual / Layout.uiScale(actual.Y)
				for _, textScale in { 1, LARGEST } do
					local line = 1.25 * UI.TextSize.Small * textScale
					-- Foam UI: the header tab (an H2 line, 2 × 4 px padding and its 2 + 5 + 3 px bands) and Close hang
					-- half above the panel; the top padding leaves room for their lower halves (+ 6 px), the bottom
					-- padding is 20; one 12 px gap, then Claim (56) or, once claimed, the countdown (an H2 line).
					local tab = 1.25 * UI.TextSize.H2 * textScale + 18
					local above = math.max(tab, UI.Touch.closeButton) / 2
					local top = math.max(math.ceil(UI.Touch.closeButton / 2), math.ceil(tab / 2)) + 6
					local pinned = math.max(UI.Touch.primaryButton, 1.25 * UI.TextSize.H2 * textScale)
					local chrome = above + top + PADDING + 12 + pinned
					-- A day card (all as tall as the tallest): 6 px padding on top, 12 at the bottom (the foam bands),
					-- the label, the coin (22), Coins (2 lines), the Treat Box (3 lines), Today and the check (18)
					-- with Claimed, 2 px between them.
					local cardHeight = 6 + 12 + 8 * line + 22 + 18 + 6 * 2
					for _, rows in { 1, 2 } do
						-- The reset sentence (2 lines) in its inset field (12 px padding).
						local reset = 2 * 1.25 * UI.TextSize.Body * textScale + 24
						local content = rows * cardHeight + (rows - 1) * GAP + 12 + reset + 6
						local body = DailyFormat.bodyHeight(screen.Y, content, chrome, SHARE, UI.Touch.minTarget)
						expect.truthy(body + chrome <= screen.Y * SHARE + 1e-6)
						expect.truthy(body >= UI.Touch.minTarget)
						expect.truthy(body <= content + 1e-6)
					end
				end
			end
			-- Short content is shown whole; nothing is ever below the minimum.
			expect.equal(DailyFormat.bodyHeight(864, 180, 172, SHARE, 52), 180)
			expect.equal(DailyFormat.bodyHeight(441, 10, 172, SHARE, 52), 52)
			expect.equal(DailyFormat.bodyHeight(0 / 0, 0 / 0, 0 / 0, SHARE, 52), 52)
		end
	)
end
