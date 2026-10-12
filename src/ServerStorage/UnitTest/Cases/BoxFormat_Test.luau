--!strict
-- BoxFormat_Test: StarterPlayerScripts.Client.UI.BoxFormat (what the Boxes screen, the reveal and the box counter show).
-- Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §6.4, §6.5, §6.10, §7.6, §7.7, §9.11, §18.1, §18.6):
--   * the odds rows equal Boxes (ids, order, weights, the exact "xx.xx%" texts), with the rarity text + pips, Owned and
--     the refund line from Pricing; every box's percent texts add up to exactly 100.00% and "Total: 100.00%";
--   * the rarity summary is rarity descending (Snack: Uncommon 20.00% · Common 80.00%; spec 2026-10-12 §8);
--   * the open area follows the §6.10 table: checking -> disabled "Checking…" + the checking note; unknown -> Try again
--     + the unknown note (disabled while the retry waits: 30 s from the later of the last press and the arrival of
--     "unknown", retryWait); restricted -> "Shop squishies directly" + the restricted note;
--     the Treat Box -> box.freeOnly, no Open; eligible -> "Open: {cost} Coins", needCoins / complete / saving / the duel
--     lock disabled with a reason; armed -> the confirm texts; an unknown policy fails closed (checking); no Robux text;
--   * the reveal timeline: 0 / 900 / 1150 / 1750 / 2350 ms; ReducedMotion: anticipation 300 ms, no wobble or hop, the
--     same phase lengths after it; the wobble stays inside [0.92, 1.06] and swings at most 3 times a second;
--   * the sounds: box.shake at 0 / 300 / 600, box.open at 900, reveal.<rarity> at 1150 (shifted under ReducedMotion);
--   * the odds board and the counter prompt (restricted and unknown -> "Shop Squishies" and the shop); the board groups
--     a rarity into one line ("Common 80.00% — 20.00% each: Toast, …") only when its items share one weight (spec
--     2026-10-09 §3.3), else one line per item;
--   * the unseen-reveal rule: malformed entries are dropped, skipped ids are left out, each id once.
--   * Part 8 (§11.2 audit): revealStageHeight keeps the class stage while the reveal panel fits, else shrinks it so the
--     panel stays inside REVEAL_PANEL.heightShare of the screen (never below stageMin) at 667×375, 893×673, 1280×720
--     and 1920×1080, at the default, Large and Largest text sizes.
--   * Foam UI restyle (2026-10-09): costText is a paid box's cost as a bare number (the card's coin says Coins), nil for
--     the free box; revealStageHeight's `title` is the whole header tab, and the panel with the half of the tab above
--     it stays inside heightShare of the screen.
--   * Foam fix batch (2026-10-09): REVEAL_PANEL.infoGap keeps the outlined rarity tag and result chip apart and
--     buttonGap the result buttons; the stage height still keeps the panel on screen with both.
--   * Foam fix round 2 (2026-10-09): the reveal keeps within the Boxes panel's share less shorterBy (at least 12 px on
--     a phone), so on 844×390 and 667×375 phones it ends inside the Boxes panel behind it (the stage at its minimum).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local BoxFormat = t.requireClient("UI/BoxFormat")
	local Boxes = t.requireShared("Boxes")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Format = t.requireShared("Util/Format")
	local Pricing = t.requireShared("Pricing")
	local Rarity = t.requireShared("Rarity")
	local Strings = t.requireShared("Strings")

	local REVEAL = Config.Anim.boxReveal

	local function rarityName(rarity: string): string
		return Strings.resolve(Rarity.get(rarity).nameKey)
	end

	-- "32.00" -> 3200 (hundredths), so sums are exact.
	local function hundredths(text: string): number
		local whole, cents = string.match(text, "^(%d+)%.(%d%d)$")
		assert(whole and cents, "not an xx.xx text: " .. text)
		return (tonumber(whole) :: number) * 100 + (tonumber(cents) :: number)
	end

	local function noRobux(view: any)
		for _, field in { "text", "reason", "note" } do
			local value = view[field]
			if type(value) == "string" then
				expect.falsy(string.find(value, "Robux", 1, true))
			end
		end
	end

	t.test("odds rows equal the Boxes config, with rarity, Owned and the refund line", function()
		for _, box in Boxes.list() do
			local owned = { [box.items[1].id] = { at = 0, src = "box" } }
			local rows = BoxFormat.oddsRows(box.id, owned)
			expect.equal(#rows, #box.items)
			for i, row in rows do
				local item = box.items[i]
				local def = Catalog.get(item.id)
				expect.equal(row.id, item.id)
				expect.equal(row.weight, item.weight)
				expect.equal(row.percent, Boxes.percentText(item.weight))
				expect.equal(row.percentText, Strings.format(Strings.common.percent, { value = row.percent }))
				expect.equal(row.name, Strings.resolve(def.nameKey))
				expect.equal(row.rarity, def.rarity)
				expect.equal(row.rarityText, rarityName(def.rarity))
				expect.equal(row.pips, Rarity.get(def.rarity).pips)
				expect.equal(row.refund, Pricing.duplicateRefund(box.id)) -- a share of the box price (spec 2026-10-12 §8)
				expect.equal(
					row.refundText,
					Strings.format(Strings.box.refundLine, { coins = Format.coins(row.refund) })
				)
				expect.equal(row.owned, i == 1)
				expect.equal(row.ownedText, if i == 1 then Strings.common.owned else nil)
				expect.equal(row.inspect, true) -- Inspect for owned and unowned rows (§6.10 #4)
			end
		end
		expect.deepEqual(BoxFormat.oddsRows("nope", {}), {})
	end)

	t.test("every box's percent texts total exactly 100.00%", function()
		for _, box in Boxes.list() do
			local sum = 0
			for _, row in BoxFormat.oddsRows(box.id, nil) do
				sum += hundredths(row.percent)
			end
			expect.equal(sum, 10000)
			expect.equal(BoxFormat.totalText(box.id), Strings.format(Strings.box.total, { percent = "100.00" }))
		end
	end)

	t.test("rarity summary: rarity descending, DESIGN's numbers", function()
		local function summary(parts: { { string } }): string
			local list = {}
			for _, part in parts do
				table.insert(
					list,
					Strings.format(Strings.box.rarityChance, { rarity = rarityName(part[1]), percent = part[2] })
				)
			end
			return Strings.format(Strings.box.chancesByRarity, { list = table.concat(list, Strings.box.listSeparator) })
		end
		-- Spec 2026-10-12 §8: Epics left the Snack Box; Dragon is 0.04% of the Sweet Box.
		expect.equal(BoxFormat.raritySummary("snack"), summary({ { "Uncommon", "20.00" }, { "Common", "80.00" } }))
		expect.equal(
			BoxFormat.raritySummary("sweet"),
			summary({ { "Exclusive", "0.04" }, { "Epic", "39.96" }, { "Uncommon", "60.00" } })
		)
	end)

	t.test("box name and price: Coins for the paid boxes, free-only for the Treat Box", function()
		expect.equal(BoxFormat.boxName("snack"), Strings.box.snack.name)
		expect.equal(BoxFormat.priceText("snack"), Strings.format(Strings.common.coinsAmount, { coins = "150.0K" }))
		expect.equal(BoxFormat.priceText("sweet"), Strings.format(Strings.common.coinsAmount, { coins = "450.00M" }))
		expect.equal(BoxFormat.priceText("treat"), Strings.box.freeOnly)
	end)

	t.test("costText: a paid box's cost as a bare number (beside the coin); none for the free box", function()
		expect.equal(BoxFormat.costText("snack"), "150.0K")
		expect.equal(BoxFormat.costText("sweet"), "450.00M")
		expect.equal(BoxFormat.costText("treat"), nil)
		expect.equal(BoxFormat.costText("nope"), nil)
		for _, box in Boxes.list() do
			if box.paid and box.cost then
				expect.equal(BoxFormat.costText(box.id), Format.coins(box.cost))
			end
		end
	end)

	t.test("open area: the §6.10 policy states", function()
		local base = { box = "snack", coins = 200_000, owned = {}, savePending = false, inLobby = true }
		local function with(changes: { [string]: any }): any
			local input = table.clone(base)
			for key, value in changes do
				input[key] = value
			end
			return BoxFormat.openView(input)
		end

		local checking = with({ policy = "checking" })
		expect.equal(checking.kind, "checking")
		expect.equal(checking.button, "confirm")
		expect.equal(checking.text, Strings.box.checkingButton)
		expect.equal(checking.enabled, false)
		expect.equal(checking.note, Strings.reasonText("box.checking"))

		local unknown = with({ policy = "unknown" })
		expect.equal(unknown.kind, "retry")
		expect.equal(unknown.button, "retry")
		expect.equal(unknown.text, Strings.common.tryAgain)
		expect.equal(unknown.enabled, true)
		expect.equal(unknown.note, Strings.box.unknownNote)
		local waiting = with({ policy = "unknown", retryWaitSeconds = 12.2 })
		expect.equal(waiting.enabled, false)
		expect.equal(waiting.reason, Strings.format(Strings.common.secondsShort, { seconds = 13 }))

		local restricted = with({ policy = "restricted" })
		expect.equal(restricted.kind, "shopDirect")
		expect.equal(restricted.button, "shop")
		expect.equal(restricted.text, Strings.box.shopDirect)
		expect.equal(restricted.enabled, true)
		expect.equal(restricted.note, Strings.box.restrictedNote)

		-- Fail closed: no policy yet, or an unexpected value, is "checking" (§6.10 server rule).
		expect.equal(with({ policy = nil }).kind, "checking")
		expect.equal(with({ policy = "yes" }).kind, "checking")

		local open = with({ policy = "eligible" })
		expect.equal(open.kind, "open")
		expect.equal(open.button, "confirm")
		expect.equal(open.text, Strings.format(Strings.box.openButton, { cost = "150.0K" }))
		expect.equal(open.enabled, true)
		expect.equal(open.price, 150_000)
		expect.equal(open.missing, 0)
		expect.equal(open.howToEarn, false)

		for _, view in { checking, unknown, waiting, restricted, open } do
			noRobux(view)
		end
	end)

	t.test("Try again waits 30 s from the later of the last press and the moment 'unknown' arrived", function()
		local span = Config.Monetization.Policy.manualRetryMinSeconds
		expect.equal(span, 30)
		expect.equal(BoxFormat.retryWait(100, nil, nil), 0)
		-- Review scenario: the join checks fail at t = 0, 2 and 6 s, "unknown" arrives at t = 6 s. The server drops a
		-- retry within 30 s of its last check, so the button must not be live at t = 10 s (it was, with no wait at all).
		expect.equal(BoxFormat.retryWait(10, nil, 6), 26)
		expect.equal(BoxFormat.retryWait(36, nil, 6), 0)
		-- After a press: the press, then the "unknown" of the failed retry, each restart the wait; the later one wins.
		expect.equal(BoxFormat.retryWait(45, 40, 6), 25)
		expect.equal(BoxFormat.retryWait(45, 40, 41), 26)
		expect.equal(BoxFormat.retryWait(71, 40, 41), 0)
		-- The span can be given; a non-number anchor is ignored.
		expect.equal(BoxFormat.retryWait(5, 0, nil, 10), 5)
		expect.equal(BoxFormat.retryWait(5, 0 / 0, nil, 10), 0)
	end)

	t.test("the reveal's result buttons ignore presses for resultInputGuardMs after they appear", function()
		local guard = Config.Anim.boxReveal.resultInputGuardMs
		expect.equal(guard, 350)
		-- The press that skipped lands at once: closed. A deliberate press later: open.
		expect.equal(BoxFormat.resultInputOpen(10, 10, guard), false)
		expect.equal(BoxFormat.resultInputOpen(10, 10.349, guard), false)
		expect.equal(BoxFormat.resultInputOpen(10, 10.35, guard), true)
		expect.equal(BoxFormat.resultInputOpen(10, 12, guard), true)
		-- No anchor (buttons never shown by a run) and bad values never lock the buttons for good.
		expect.equal(BoxFormat.resultInputOpen(nil, 10, guard), true)
		expect.equal(BoxFormat.resultInputOpen(0 / 0, 10, guard), true)
		expect.equal(BoxFormat.resultInputOpen(10, 10, 0 / 0), true)
		expect.equal(BoxFormat.resultInputOpen(10, 10, -5), true)
	end)

	t.test("open area: the Treat Box is free-only in every policy (no Open)", function()
		for _, policy in { "checking", "eligible", "restricted", "unknown" } do
			local view = BoxFormat.openView({ box = "treat", policy = policy, coins = 99999, owned = {} })
			expect.equal(view.kind, "freeOnly")
			expect.equal(view.button, nil)
			expect.equal(view.text, Strings.box.freeOnly)
			expect.equal(view.enabled, false)
		end
	end)

	t.test("open area: eligible blocks (Coins, complete, saving, duel, profile) and the armed confirm", function()
		local poor = BoxFormat.openView({ box = "snack", policy = "eligible", coins = 149_880, owned = {} })
		expect.equal(poor.kind, "needCoins")
		expect.equal(poor.enabled, false)
		expect.equal(poor.missing, 120)
		expect.equal(poor.reason, Strings.format(Strings.box.needCoins.many, { missing = "120" }))
		expect.equal(poor.reason, BoxFormat.needCoinsText(120))
		expect.equal(poor.howToEarn, true)
		expect.equal(BoxFormat.needCoinsText(1), Strings.format(Strings.box.needCoins.one, { missing = "1" }))
		expect.equal(BoxFormat.openView({ box = "snack", policy = "eligible", owned = {} }).kind, "needCoins")

		local all = {}
		for _, item in Boxes.get("snack").items do
			all[item.id] = { at = 0, src = "box" }
		end
		local complete = BoxFormat.openView({ box = "snack", policy = "eligible", coins = 200_000, owned = all })
		expect.equal(complete.kind, "complete")
		expect.equal(complete.enabled, false)
		expect.equal(complete.reason, Strings.reasonText("box.complete"))
		-- The policy comes first: a restricted player who owns everything still gets the shop alternative.
		expect.equal(
			BoxFormat.openView({ box = "snack", policy = "restricted", coins = 200_000, owned = all }).kind,
			"shopDirect"
		)

		local saving =
			BoxFormat.openView({ box = "snack", policy = "eligible", coins = 200_000, owned = {}, savePending = true })
		expect.equal(saving.kind, "saving")
		expect.equal(saving.enabled, false)
		expect.equal(saving.reason, Strings.reasonText("box.saving"))

		local duel =
			BoxFormat.openView({ box = "snack", policy = "eligible", coins = 200_000, owned = {}, inLobby = false })
		expect.equal(duel.enabled, false)
		expect.equal(duel.reason, Strings.common.lockedInDuel)

		local offline =
			BoxFormat.openView({ box = "snack", policy = "eligible", coins = 200_000, profileReady = false })
		expect.equal(offline.enabled, false)
		expect.equal(offline.reason, Strings.data.loadFailed)

		local armed =
			BoxFormat.openView({ box = "sweet", policy = "eligible", coins = 450_000_500, owned = {}, armed = true })
		expect.equal(armed.kind, "confirm")
		expect.equal(armed.enabled, true)
		expect.equal(armed.text, Strings.format(Strings.spend.confirm, { price = "450.00M" }))
		expect.equal(armed.note, Strings.format(Strings.spend.balanceAfter, { balance = "500" }))
		for _, view in { poor, complete, saving, duel, offline, armed } do
			noRobux(view)
		end
	end)

	t.test("reveal timeline: DESIGN's phases; ReducedMotion anticipation 300 ms, same lengths after", function()
		local normal = BoxFormat.revealTimes(false)
		expect.deepEqual(normal, {
			anticipationEnd = REVEAL.anticipationEndMs,
			popEnd = REVEAL.popEndMs,
			revealEnd = REVEAL.revealEndMs,
			highlightEnd = REVEAL.highlightEndMs,
		})
		expect.deepEqual(normal, { anticipationEnd = 900, popEnd = 1150, revealEnd = 1750, highlightEnd = 2350 })
		local reduced = BoxFormat.revealTimes(true)
		expect.equal(reduced.anticipationEnd, REVEAL.reducedMotionAnticipationMs)
		expect.equal(reduced.anticipationEnd, 300)
		expect.equal(reduced.popEnd - reduced.anticipationEnd, normal.popEnd - normal.anticipationEnd)
		expect.equal(reduced.revealEnd - reduced.popEnd, normal.revealEnd - normal.popEnd)
		expect.equal(reduced.highlightEnd - reduced.revealEnd, normal.highlightEnd - normal.revealEnd)

		local function phase(tMs: number, isReduced: boolean): string
			local name = BoxFormat.revealPhase(tMs, isReduced)
			return name
		end
		expect.equal(phase(0, false), "anticipation")
		expect.equal(phase(899, false), "anticipation")
		expect.equal(phase(900, false), "pop")
		expect.equal(phase(1150, false), "reveal")
		expect.equal(phase(1750, false), "highlight")
		expect.equal(phase(2349, false), "highlight")
		expect.equal(phase(2350, false), "result")
		expect.equal(phase(299, true), "anticipation")
		expect.equal(phase(300, true), "pop")
		expect.equal(phase(550, true), "reveal")
		expect.equal(phase(1750, true), "result")
		local _, half = BoxFormat.revealPhase(450, false)
		expect.near(half, 0.5, 1e-9)
		local _, done = BoxFormat.revealPhase(99999, false)
		expect.equal(done, 1)
		expect.equal(phase(-5, false), "anticipation")
		expect.equal(phase(0 / 0, false), "anticipation")
	end)

	t.test("wobble: inside [cMin, cMax], hops only on the stretch, <= 3 Hz, off under ReducedMotion", function()
		local lowest, highest = 1, 1
		local signs = {}
		for tMs = 0, REVEAL.anticipationEndMs, 5 do
			local c, hop = BoxFormat.wobble(tMs, false)
			expect.truthy(c >= REVEAL.wobbleCMin - 1e-9 and c <= REVEAL.wobbleCMax + 1e-9)
			expect.truthy(hop >= 0)
			if hop > 0 then
				expect.truthy(c > 1) -- a hop only while stretching
			end
			lowest, highest = math.min(lowest, c), math.max(highest, c)
			local sign = if c < 1 - 1e-9 then -1 elseif c > 1 + 1e-9 then 1 else 0
			if sign ~= 0 and signs[#signs] ~= sign then
				table.insert(signs, sign)
			end
			local rc, rhop = BoxFormat.wobble(tMs, true)
			expect.equal(rc, 1)
			expect.equal(rhop, 0)
		end
		expect.near(lowest, REVEAL.wobbleCMin, 1e-3) -- the last, strongest squash reaches 0.92
		expect.truthy(highest > 1)
		-- Squash, stretch, squash: 3 half-swings in 900 ms, each >= 1 / (2 · 3 Hz).
		expect.deepEqual(signs, { -1, 1, -1 })
		expect.truthy(REVEAL.anticipationEndMs / #signs >= 1000 / (2 * 3))
		local c0, h0 = BoxFormat.wobble(REVEAL.anticipationEndMs + 1, false)
		expect.equal(c0, 1)
		expect.equal(h0, 0)
	end)

	t.test("sounds: box.shake ×3, box.open at the pop, reveal.<rarity> at the reveal (§18.6)", function()
		local expectedKeys: { [string]: string } = {
			Common = "reveal.common",
			Uncommon = "reveal.uncommon",
			Epic = "reveal.epic",
			Exclusive = "reveal.exclusive",
		}
		for rarity, key in expectedKeys do
			expect.equal(BoxFormat.revealSoundKey(rarity), key)
			local cues = BoxFormat.soundCues(rarity, false)
			local list: { string } = {}
			for _, cue in cues do
				table.insert(list, string.format("%d %s", cue.atMs, cue.key))
			end
			expect.deepEqual(list, {
				"0 box.shake",
				"300 box.shake",
				"600 box.shake",
				"900 box.open",
				"1150 " .. key,
			})
			expect.equal(cues[4].variance, 0)
			expect.equal(cues[5].variance, 0)
			local reduced: { string } = {}
			for _, cue in BoxFormat.soundCues(rarity, true) do
				table.insert(reduced, string.format("%d %s", cue.atMs, cue.key))
			end
			expect.deepEqual(reduced, {
				"0 box.shake",
				"100 box.shake",
				"200 box.shake",
				"300 box.open",
				"550 " .. key,
			})
		end
		expect.equal(BoxFormat.revealSoundKey("Nope"), "reveal.common")
	end)

	t.test("result text: NEW! or the duplicate refund", function()
		expect.equal(BoxFormat.resultText(false, 0), Strings.box.revealNew)
		expect.equal(BoxFormat.resultText(true, 1000), Strings.format(Strings.box.revealDuplicate, { coins = "1,000" }))
	end)

	t.test("odds board: the stand's box rows, or the restricted / unknown note", function()
		local text = BoxFormat.boardText("eligible", "snack")
		local lines = string.split(text, "\n")
		local box = Boxes.get("snack")
		expect.equal(
			lines[1],
			Strings.format(Strings.box.boardHeader, { box = Strings.box.snack.name, cost = "150.0K" })
		)
		expect.deepEqual(table.move(lines, 2, #lines, 1, {}), BoxFormat.oddsLines(box.items))
		expect.equal(BoxFormat.boardText("checking", "snack"), text)
		expect.equal(BoxFormat.boardText(nil, "snack"), text)
		expect.equal(BoxFormat.boardText("restricted", "snack"), Strings.box.restrictedNote)
		expect.equal(BoxFormat.boardText("unknown", "snack"), Strings.box.unknownNote)
		expect.equal(BoxFormat.boardText("eligible", "nope"), "")
	end)

	-- Spec 2026-10-09 §3.3: with 14 squishies the 7×8-stud board would hold 13 lines, so a rarity whose items all share
	-- one weight takes one line that still names every item and its chance.
	t.test("odds board grouping: one line per rarity when its items share a weight", function()
		local function line(id: string, percent: string): string
			local def = Catalog.get(id)
			return Strings.format(
				Strings.box.boardLine,
				{ name = Strings.resolve(def.nameKey), rarity = rarityName(def.rarity), percent = percent }
			)
		end
		local function group(rarity: string, total: string, each: string, names: { string }): string
			return Strings.format(Strings.box.boardGroupLine, {
				rarity = rarityName(rarity),
				total = total,
				each = each,
				names = table.concat(names, Strings.box.boardNameSeparator),
			})
		end

		local snack = string.split(BoxFormat.boardText("eligible", "snack"), "\n")
		expect.equal(#snack, 3) -- the header, then Common and Uncommon in item order (spec 2026-10-12 §8)
		expect.equal(snack[2], "Common 80.00% — 20.00% each: Toast, Banana, Boba Bear, Pancake Pup")
		expect.equal(
			snack[3],
			group("Uncommon", "20.00", "5.00", { "Butter", "Chocolate", "Mochi Fox", "Strawberry Frog" })
		)

		-- Dragon, alone in its rarity, keeps its own line.
		expect.deepEqual(BoxFormat.oddsLines(Boxes.get("sweet").items), {
			group("Uncommon", "60.00", "15.00", { "Butter", "Chocolate", "Mochi Fox", "Strawberry Frog" }),
			group("Epic", "39.96", "9.99", { "Birdie", "Donut", "Cloud Bunny", "Cupcake Axolotl" }),
			line("dragon", "0.04"),
		})

		-- Different weights inside a rarity: one line per item; an unknown id keeps a line of its own.
		local mixed = {
			{ id = "toast", weight = 5000 },
			{ id = "banana", weight = 3000 },
			{ id = "butter", weight = 900 },
			{ id = "chocolate", weight = 900 },
			{ id = "nope", weight = 200 },
		}
		expect.deepEqual(BoxFormat.oddsLines(mixed), {
			line("toast", "50.00"),
			line("banana", "30.00"),
			group("Uncommon", "18.00", "9.00", { "Butter", "Chocolate" }),
			Strings.format(Strings.box.boardLine, { name = "nope", rarity = "", percent = "2.00" }),
		})
		expect.deepEqual(BoxFormat.oddsLines({}), {})
	end)

	t.test("counter prompt: Shop Squishies for restricted AND unknown (§7.6)", function()
		expect.equal(BoxFormat.promptKey("restricted"), "prompt.shopDirect")
		expect.equal(BoxFormat.promptKey("unknown"), "prompt.shopDirect")
		expect.equal(BoxFormat.promptKey("checking"), "prompt.seeBoxes")
		expect.equal(BoxFormat.promptKey("eligible"), "prompt.seeBoxes")
		expect.equal(BoxFormat.promptKey(nil), "prompt.seeBoxes")
		expect.truthy(Strings.resolve(BoxFormat.promptKey("unknown")))
		expect.truthy(Strings.resolve(BoxFormat.promptKey("eligible")))
		expect.equal(BoxFormat.standScreen("restricted"), "shop")
		expect.equal(BoxFormat.standScreen("unknown"), "shop")
		expect.equal(BoxFormat.standScreen("checking"), "boxes")
		expect.equal(BoxFormat.standScreen("eligible"), "boxes")
	end)

	t.test("unseen reveals: valid entries only, skipped ids left out, each id once", function()
		local guid = "0A1B2C3D-0000-4000-8000-00000000000F"
		local entry =
			{ req = guid, box = "snack", squishy = "toast", dup = true, refund = 100, cost = 400, at = 1, seen = false }
		local daily =
			{ req = "daily:20000", box = "treat", squishy = "bird", dup = false, refund = 0, cost = 0, at = 2 }
		expect.deepEqual(
			BoxFormat.revealFromEntry(entry),
			{ requestId = guid, boxId = "snack", squishyId = "toast", isDuplicate = true, refund = 100 }
		)
		expect.deepEqual(
			BoxFormat.revealFromEntry(daily),
			{ requestId = "daily:20000", boxId = "treat", squishyId = "bird", isDuplicate = false, refund = 0 }
		)
		local bads: { any } = {
			"x",
			{ req = "nope", box = "snack", squishy = "toast" },
			{ req = guid, box = "mystery", squishy = "toast" },
			{ req = guid, box = "snack", squishy = "unicorn" },
			{ req = 5, box = "snack", squishy = "toast" },
			{ req = "daily:x", box = "treat", squishy = "toast" },
		}
		for _, bad in bads do
			expect.equal(BoxFormat.revealFromEntry(bad), nil)
		end
		local played = { [guid] = true }
		local entries: { any } = { entry, daily, daily, { req = "bad" } }
		local list = BoxFormat.pendingReveals(entries, function(id: string): boolean
			return played[id] == true
		end)
		expect.equal(#list, 1)
		expect.equal(list[1].requestId, "daily:20000")
		expect.deepEqual(
			BoxFormat.pendingReveals(nil, function()
				return false
			end),
			{}
		)
	end)

	t.test("replies: only unanswered or never-sent requests reuse their requestId", function()
		for _, reason in { "error.generic", "error.connect", "net.rateLimited", "net.invalid" } do
			expect.truthy(BoxFormat.isIndeterminate(reason))
		end
		expect.truthy(BoxFormat.isIndeterminate(nil))
		for _, reason in { "economy.notEnoughCoins", "box.restricted", "box.complete", "box.saving", "box.paused" } do
			expect.falsy(BoxFormat.isIndeterminate(reason))
		end
	end)

	-- Part 8: the reveal panel's stage height (DESIGN §11.2 audit) ---------------------------------------------------
	-- At 667×375 (a phone, compact), 893×673 (Studio's window), 1280×720 and 1920×1080, at the default and the largest
	-- text size (text from a generous per-character estimate): the stage keeps its class height when the panel fits,
	-- shrinks so the whole panel stays inside REVEAL_PANEL.heightShare of the screen, never below stageMin, and a larger
	-- text never gives a taller stage.

	local Layout = t.requireClient("UI/Layout")
	local PANEL = BoxFormat.REVEAL_PANEL
	local TEXT = Config.UI.TextSize
	local EM, LINE = 0.6, 1.3
	local REVEAL_SCREENS = {
		{ label = "667x375", size = Vector2.new(667, 375) },
		{ label = "893x673", size = Vector2.new(893, 673) },
		{ label = "1280x720", size = Vector2.new(1280, 720) },
		{ label = "1920x1080", size = Vector2.new(1920, 1080) },
	}

	-- The reveal's other rows at a text scale (every result button shown, the saving note reserved).
	local function revealParts(textScale: number): any
		local inner = PANEL.width - 2 * PANEL.padding
		local items = {}
		for _, text in { Strings.common.equip, Strings.common.inspect, Strings.box.openAnother, Strings.common.close } do
			table.insert(
				items,
				{ w = #text * TEXT.Button * textScale * EM + 2 * 18 + 4, h = Config.UI.Touch.primaryButton }
			)
		end
		local savingWidth = #Strings.reasonText("box.saving") * TEXT.Small * textScale * EM
		return {
			-- Foam restyle: the title is a header tab (its H2 line, 2 × 4 px padding and the 2 / 5 / 3 foam bands) and the
			-- result line a Chip (Button kind, at least 26 px).
			title = TEXT.H2 * textScale * LINE + 18,
			name = TEXT.Title * textScale * LINE,
			rarity = TEXT.Small * textScale * LINE + 4,
			result = math.max(26, TEXT.Button * textScale * LINE),
			saving = math.ceil(savingWidth / inner) * TEXT.Small * textScale * LINE,
			buttons = Layout.wrapRow(items, inner, PANEL.buttonGap).height, -- fix batch: the buttons' own gap
		}
	end

	-- Foam fix batch (2026-10-09): the name, the outlined rarity tag and the outlined result chip never touch (their
	-- 2 px outlines are drawn outside their boxes), and the chunky result buttons keep a clear gap.
	t.test("REVEAL_PANEL: the result rows and buttons keep clear gaps", function()
		local Theme = t.requireClient("UI/Theme")
		expect.truthy(PANEL.infoGap >= 2 * Theme.Stroke.bar + 2)
		expect.truthy(PANEL.buttonGap > PANEL.gap)
		expect.truthy(PANEL.buttonGap >= 2 * Theme.Stroke.ink + 4)
	end)

	local function otherRows(p: any): number
		return p.title
			+ p.name
			+ p.rarity
			+ p.result
			+ 2 * PANEL.infoGap
			+ p.saving
			+ p.buttons
			+ 4 * PANEL.gap
			+ 2 * PANEL.padding
	end

	for _, screen in REVEAL_SCREENS do
		t.test(`revealStageHeight {screen.label}: the panel stays on screen at every text size`, function()
			local scale = Layout.uiScale(screen.size.Y)
			local class = Layout.layoutClass(screen.size.X, screen.size.Y)
			local baseHeight = screen.size.Y / scale
			local maxStage = if class == "compact" then PANEL.stageCompact else PANEL.stage
			local previous = math.huge
			for _, textScale in { 1, Config.UI.PreferredTextScale.Large, Config.UI.PreferredTextScale.Largest } do
				local parts = revealParts(textScale)
				local stage = BoxFormat.revealStageHeight(baseHeight, parts, class)
				expect.truthy(stage >= PANEL.stageMin and stage <= maxStage)
				expect.equal(stage, math.floor(stage)) -- whole base px
				if stage > PANEL.stageMin then
					-- The whole panel inside heightShare of the screen less shorterBy (so inside the screen and shorter
					-- than the Boxes panel behind it, fix round 2).
					expect.truthy(otherRows(parts) + stage <= baseHeight * PANEL.heightShare - PANEL.shorterBy + 1e-6)
				end
				expect.truthy(stage <= previous)
				previous = stage
				-- The panel is narrower than the screen.
				expect.truthy(PANEL.width <= screen.size.X / scale)
			end
			if class == "regular" then
				-- A regular screen at the default text keeps Part 7's stage.
				expect.equal(BoxFormat.revealStageHeight(baseHeight, revealParts(1), class), PANEL.stage)
			end
		end)
	end

	-- Foam fix round 2 (2026-10-09): on a phone the reveal was as tall as the Boxes panel behind it (the stage at its
	-- minimum), so the two outlines doubled up at the corners.
	t.test("REVEAL_PANEL: never taller than the Boxes panel, and on phones it ends inside it", function()
		local InventoryFormat = t.requireClient("UI/InventoryFormat")
		local boxesShare = InventoryFormat.PANEL.heightShare -- the Boxes panel's share (BoxController MAX_HEIGHT_SHARE)
		expect.truthy(PANEL.heightShare <= boxesShare)
		expect.truthy(PANEL.shorterBy * Layout.uiScale(375) >= 12) -- at least 12 px on a phone
		-- SD_Modal on the two phones (the safe area, as in the foam shots), Medium text. The shots measured the reveal's
		-- rows other than the stage at 202 base px (the panel was 322 with the 120 px stage); the stage here comes from
		-- the generous estimate above, which keeps the phone stage at its minimum.
		local MEASURED_ROWS = 202
		for _, actual in { Vector2.new(844, 312), Vector2.new(667, 297) } do
			local scale = Layout.uiScale(actual.Y)
			local baseHeight = actual.Y / scale
			local stage = BoxFormat.revealStageHeight(baseHeight, revealParts(1), "compact")
			expect.truthy(MEASURED_ROWS + stage <= baseHeight * boxesShare - PANEL.shorterBy + 1e-6)
			expect.truthy(stage * scale >= 70) -- still a stage you can see the squishy in and tap to skip
		end
	end)

	t.test("revealStageHeight: a bad screen height or bad parts give a safe stage", function()
		local parts = revealParts(1)
		expect.equal(BoxFormat.revealStageHeight(0 / 0, parts, "regular"), PANEL.stageMin)
		expect.equal(BoxFormat.revealStageHeight(-5, parts, "compact"), PANEL.stageMin)
		local bad = { title = 0 / 0, name = -1, rarity = math.huge, result = 0, saving = 0, buttons = 0 }
		local stage = BoxFormat.revealStageHeight(2000, bad, "regular")
		expect.equal(stage, PANEL.stage)
		expect.equal(BoxFormat.revealStageHeight(2000, parts, "compact"), PANEL.stageCompact)
	end)
end
