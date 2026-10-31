--!strict
-- BoxFormat_Test: StarterPlayerScripts.Client.UI.BoxFormat (what the Boxes screen, the reveal and the box counter show).
-- Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract (DESIGN §6.4, §6.5, §6.10, §7.6, §7.7, §9.11, §18.1, §18.6):
--   * the odds rows equal Boxes (ids, order, weights, the exact "xx.xx%" texts), with the rarity text + pips and Owned
--     (pens3 phase 5: no refund line, a squishy you own again is a copy); every box's percent texts add up to exactly
--     100.00% and "Total: 100.00%";
--   * the rarity summary is rarity descending (Snack: Uncommon 24.00% · Common 76.00%; ECONOMY_V3 odds);
--   * the open area follows the §6.10 table: checking -> disabled "Checking…" + the checking note; unknown -> Try again
--     + the unknown note (disabled while the retry waits: 30 s from the later of the last press and the arrival of
--     "unknown", retryWait); restricted (pens3 phase 5) -> OPEN like eligible, with "Next in this box: {name}" (the
--     fixed order's next squishy from boxOrder) and the restricted note, and no Open while that next squishy is not
--     known (checking);
--     the Treat Box -> box.freeOnly, no Open; eligible -> "Open: {cost} Coins", needCoins / Toy Box full / saving / the
--     duel lock disabled with a reason; armed -> the confirm texts; an unknown policy fails closed (checking); no
--     Robux text;
--   * UI FINAL R7 (plan work/ui/PLAN.md R7): the reveal timeline (the drop lands at 750 ms, a tap every 1.1 s or the
--     player's advances one tap, the third bursts about 4.05 s in, only once the reply is in, the result idle 1.5 s
--     later; skip lands with every move done), the design's curves and springs, the sounds per moment, the flash
--     under Config.Vfx.Flash (PR16), the §9.15 frame ledger with the burst and the rain (PR18), the orbit (T14), the
--     duplicate line (PR21; no Coins since pens3 phase 5), the window's card row (PR20), card layout, odds rows, toy
--     tiles and subtitle;
--   * the odds board and the counter prompt (unknown -> "Shop Squishies" and the shop; restricted -> the boxes since
--     pens3 phase 5); the board groups a rarity into one line ("Common 76.00% — 19.00% each: Toast, …") only when its
--     items share one weight (spec 2026-10-09 §3.3), else one line per item;
--   * the unseen-reveal rule: malformed entries are dropped, skipped ids are left out, each id once.

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

	t.test("odds rows equal the Boxes config, with rarity and Owned (no refund line: copies)", function()
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
				-- Pens3 phase 5: a squishy you own again is a copy for the pen, never Coins back.
				expect.equal(row.refund, nil)
				expect.equal(row.refundText, nil)
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
		-- ECONOMY_V3:159-161 (pens3 phase 5): Soft 4 x 19% Commons; Sweet 4 Epics and Dragon at 0.04%.
		expect.equal(BoxFormat.raritySummary("snack"), summary({ { "Uncommon", "24.00" }, { "Common", "76.00" } }))
		expect.equal(BoxFormat.raritySummary("sweet"), summary({ { "Exclusive", "0.04" }, { "Epic", "99.96" } }))
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
		local base = {
			box = "snack",
			coins = 200_000,
			owned = {},
			savePending = false,
			inLobby = true,
			boxOrder = { snack = 0, sweet = 0 },
		}
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

		-- Pens3 phase 5 (D1:235): a restricted account opens the paid boxes in a fixed order, never random, and sees
		-- the next squishy before it opens (Boxes.fixedItem of its boxOrder count).
		local restricted = with({ policy = "restricted" })
		expect.equal(restricted.kind, "open")
		expect.equal(restricted.button, "confirm")
		expect.equal(restricted.text, Strings.format(Strings.box.openButton, { cost = "150.0K" }))
		expect.equal(restricted.enabled, true)
		expect.equal(restricted.note, Strings.box.restrictedNote)
		expect.equal(restricted.nextText, Strings.format(Strings.box.nextItem, { name = "Toast" }))
		expect.equal(Boxes.fixedItem("snack", 0), "toast")
		local eleventh = with({ policy = "restricted", boxOrder = { snack = 10, sweet = 0 } })
		expect.equal(eleventh.nextText, Strings.format(Strings.box.nextItem, { name = "Mochi Fox" }))
		local sweet = with({ policy = "restricted", box = "sweet", coins = 450_000_000, boxOrder = { sweet = 500 } })
		expect.equal(sweet.kind, "open")
		expect.equal(sweet.nextText, Strings.format(Strings.box.nextItem, { name = "Dragon" })) -- box 501 (V4:252)
		local again = with({ policy = "restricted", box = "sweet", coins = 450_000_000, boxOrder = { sweet = 3000 } })
		expect.equal(again.nextText, sweet.nextText) -- the order repeats every fixedCycle (2,500)
		-- Its blocks are the eligible ones (short of Coins here), and the next squishy still shows.
		local short = with({ policy = "restricted", coins = 10 })
		expect.equal(short.kind, "needCoins")
		expect.equal(short.nextText, restricted.nextText)
		-- No boxOrder yet (or a broken count): the next squishy is not known, so no Open (never a blind open).
		-- (false = no boxOrder field at all)
		for _, order in { false, "x", {}, { snack = -1 }, { snack = 1.5 }, { snack = "3" } } :: { any } do
			local input: any = { box = "snack", policy = "restricted", coins = 200_000 }
			if order ~= false then
				input.boxOrder = order
			end
			local blind = BoxFormat.openView(input)
			expect.equal(blind.kind, "checking")
			expect.equal(blind.enabled, false)
			expect.equal(blind.nextText, nil)
		end
		-- Eligible accounts draw at random: no next squishy is shown.
		expect.equal(with({ policy = "eligible" }).nextText, nil)

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

	t.test("open area: eligible blocks (Coins, Toy Box full, saving, duel, profile) and the armed confirm", function()
		local poor = BoxFormat.openView({ box = "snack", policy = "eligible", coins = 149_880, owned = {} })
		expect.equal(poor.kind, "needCoins")
		expect.equal(poor.enabled, false)
		expect.equal(poor.missing, 120)
		expect.equal(poor.reason, Strings.format(Strings.box.needCoins.many, { missing = "120" }))
		expect.equal(poor.reason, BoxFormat.needCoinsText(120))
		expect.equal(poor.howToEarn, true)
		expect.equal(BoxFormat.needCoinsText(1), Strings.format(Strings.box.needCoins.one, { missing = "1" }))
		expect.equal(BoxFormat.openView({ box = "snack", policy = "eligible", owned = {} }).kind, "needCoins")

		-- Pens3 phase 5: owning every squishy of a box no longer blocks it (a copy comes); a full Toy Box does
		-- (PenMath.room 0: 3 spots + toyBoxMax unplaced), before any Coins move. No pen state yet: the server decides.
		local all = {}
		for _, item in Boxes.get("snack").items do
			all[item.id] = { at = 0, src = "box" }
		end
		expect.equal(
			BoxFormat.openView({ box = "snack", policy = "eligible", coins = 200_000, owned = all }).kind,
			"open"
		)
		local items = {}
		for i = 1, 3 + Config.Economy.Pen.toyBoxMax do
			table.insert(items, { id = i, kind = "toast" })
		end
		local fullPen = { spots = 3, nextId = #items + 1, items = items }
		local full =
			BoxFormat.openView({ box = "snack", policy = "eligible", coins = 200_000, owned = {}, pen = fullPen })
		expect.equal(full.kind, "full")
		expect.equal(full.enabled, false)
		expect.equal(full.reason, Strings.reasonText("inventory.full"))
		local roomy = { spots = 4, nextId = fullPen.nextId, items = items } -- a pen spot bought: room for one more
		expect.equal(
			BoxFormat.openView({ box = "snack", policy = "eligible", coins = 200_000, pen = roomy }).kind,
			"open"
		)
		-- Restricted accounts have the same block (their next squishy still shows).
		local fullRestricted = BoxFormat.openView({
			box = "snack",
			policy = "restricted",
			coins = 200_000,
			pen = fullPen,
			boxOrder = { snack = 0 },
		})
		expect.equal(fullRestricted.kind, "full")
		expect.equal(fullRestricted.nextText, Strings.format(Strings.box.nextItem, { name = "Toast" }))

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
		for _, view in { poor, full, saving, duel, offline, armed } do
			noRobux(view)
		end
	end)

	-- UI FINAL R7: the reveal's timeline (stage:254-332, G7.20) ----------------------------------------------------------

	-- Steps `state` by `dt` until `untilS` seconds passed; returns every event in order with its time.
	local function play(state: any, untilS: number, dt: number, replied: boolean, tapsAt: { number }?): { any }
		local out = {}
		local time = 0
		local pending: { number } = table.clone(tapsAt or {})
		while time < untilS - 1e-9 do
			time += dt
			local tapped = false
			if pending[1] and time >= pending[1] - 1e-9 then
				table.remove(pending, 1)
				tapped = true
			end
			for _, event in BoxFormat.revealAdvance(state, dt, tapped, replied) do
				table.insert(out, { kind = event.kind, tap = event.tap, at = time })
			end
		end
		return out
	end

	t.test(
		"reveal: the drop lands at 750 ms, a tap every 1.1 s, the third bursts at about 4.05 s, ready 1.5 s later",
		function()
			local state = BoxFormat.revealStart()
			local events = play(state, 6, 1 / 120, true)
			local kinds = {}
			for _, e in events do
				table.insert(kinds, e.kind)
			end
			expect.deepEqual(kinds, { "land", "tap", "tap", "tap", "burst", "ready" })
			expect.near(events[1].at, REVEAL.dropMs / 1000, 1 / 120 + 1e-6)
			for j = 0, 2 do
				expect.equal(events[2 + j].tap, j)
				-- each tap restarts the 1.1 s count on its frame (as stage:256, 313): at most a frame late per tap
				expect.near(events[2 + j].at, REVEAL.dropMs / 1000 + (j + 1) * REVEAL.autoTapS, (j + 2) / 120 + 1e-6)
			end
			expect.near(events[5].at, 4.05, 4 / 120 + 1e-6) -- the plan's "about 4.05 s after the drop starts"
			expect.near(events[6].at - events[5].at, REVEAL.resultAtS, 2 / 120)
			expect.equal(state.phase, "inspect")
		end
	)

	t.test("reveal: a player's tap advances one tap (never a skip); taps during the drop do nothing", function()
		local state = BoxFormat.revealStart()
		local events = play(state, 1.2, 1 / 60, true, { 0.2, 0.9, 1.0 })
		local taps = 0
		for _, e in events do
			if e.kind == "tap" then
				taps += 1
			end
			expect.falsy(e.kind == "burst")
		end
		expect.equal(taps, 2) -- the 0.2 s tap fell in the drop
		expect.equal(state.taps, 2)
		expect.equal(state.phase, "idle")
	end)

	t.test("reveal: the burst waits for the BoxOpen reply (the box is held after its third tap)", function()
		local state = BoxFormat.revealStart()
		local events = play(state, 8, 1 / 60, false)
		local kinds = {}
		for _, e in events do
			table.insert(kinds, e.kind)
		end
		expect.deepEqual(kinds, { "land", "tap", "tap", "tap" })
		expect.equal(state.held, true)
		expect.equal(state.phase, "idle")
		local late = BoxFormat.revealAdvance(state, 1 / 60, true, true)
		expect.equal(#late, 1)
		expect.equal(late[1].kind, "burst")
		expect.equal(state.taps, REVEAL.taps)
	end)

	t.test("reveal: skip lands in the result idle with every move done", function()
		local state = BoxFormat.revealStart()
		play(state, 1, 1 / 60, true)
		BoxFormat.revealSkip(state)
		expect.equal(state.phase, "inspect")
		expect.equal(state.taps, REVEAL.taps)
		local mul, _, hidden = BoxFormat.boxExit(state.t)
		expect.equal(hidden, true)
		expect.equal(mul, 0)
		local scale, y, yaw, alpha = BoxFormat.toyPose(state.t)
		expect.near(scale, 1, 1e-9)
		expect.near(y, REVEAL.toy.y + REVEAL.toy.rise, 1e-9)
		expect.near(yaw, 0, 1e-9)
		expect.near(alpha, 1, 1e-9)
	end)

	t.test("reveal curves: the design's bounce, elastic, drop, exit, entrance, beam and wave", function()
		expect.equal(BoxFormat.bounceOut(0), 0)
		expect.near(BoxFormat.bounceOut(1), 1, 1e-9)
		expect.near(BoxFormat.bounceOut(0.5), 0.765625, 1e-9) -- stage:286 at x = .5
		expect.equal(BoxFormat.elastic(0), 0)
		expect.equal(BoxFormat.elastic(1), 1)
		expect.truthy(BoxFormat.elastic(0.2) > 1) -- it overshoots
		local height, yaw, blobScale, blobAlpha = BoxFormat.dropPose(0)
		expect.near(height, REVEAL.dropHeight, 1e-9)
		expect.near(yaw, REVEAL.restYaw + math.pi * REVEAL.dropTurns, 1e-9)
		expect.near(blobScale, REVEAL.floor.from, 1e-9)
		expect.equal(blobAlpha, 0)
		height, yaw = BoxFormat.dropPose(REVEAL.dropMs / 1000)
		expect.near(height, 0, 1e-9)
		expect.near(yaw, REVEAL.restYaw, 1e-9)
		expect.equal(BoxFormat.boxExit(0.1), 1)
		local mid, spinning = BoxFormat.boxExit(0.2)
		expect.truthy(spinning and mid > 0 and mid < 1.25)
		expect.falsy(BoxFormat.exitPoofs(0.3))
		expect.truthy(BoxFormat.exitPoofs(0.36))
		local s0, _, spin0, a0 = BoxFormat.toyPose(0.36)
		expect.near(s0, 0.001, 1e-9)
		expect.near(spin0, math.pi * REVEAL.toy.spins, 1e-9)
		expect.equal(a0, 0)
		local _, _, _, aHalf = BoxFormat.toyPose(0.56)
		expect.near(aHalf, 0.5, 1e-6)
		local sx, sy, alpha = BoxFormat.beamPose(0)
		expect.near(sx, 0.2, 1e-9)
		expect.near(sy, 0.01, 1e-9)
		expect.near(alpha, REVEAL.beam.alpha, 1e-9)
		local _, _, gone = BoxFormat.beamPose(0.7 + 1e-6)
		expect.near(gone, 0, 1e-6)
		local waveScale, waveAlpha = BoxFormat.wavePose(0)
		expect.near(waveScale, REVEAL.wave.from, 1e-9)
		expect.near(waveAlpha, REVEAL.wave.alpha, 1e-9)
		local _, waveGone = BoxFormat.wavePose(1)
		expect.equal(waveGone, 0)
		expect.near(BoxFormat.lidTarget("idle", 2, "soft"), REVEAL.lid.rest + 2 * REVEAL.lid.perTap, 1e-9)
		expect.equal(BoxFormat.lidTarget("open", 3, "royal"), REVEAL.lid.openRoyal)
		expect.equal(BoxFormat.lidTarget("inspect", 3, "sweet"), REVEAL.lid.open)
	end)

	t.test("reveal springs settle on their target (stage:294-295)", function()
		local x, v = 1, -9
		for _ = 1, 240 do
			x, v = BoxFormat.spring(x, v, 1, REVEAL.squash.k, REVEAL.squash.c, 1 / 60)
		end
		expect.near(x, 1, 1e-3)
		expect.near(v, 0, 1e-2)
	end)

	t.test(
		"sounds per moment (the fancier reveal): a rattle per tap, the rise, the unbox of the rarity, letters, stamp",
		function()
			local land = BoxFormat.soundCue("land")
			expect.equal(land.key, "ui.click")
			expect.equal(land.pitch, REVEAL.landPitch)
			for j = 0, 2 do
				local tap = BoxFormat.soundCue("tap", nil, j)
				expect.equal(tap.key, "box.ux.rattle" .. j + 1)
				expect.deepEqual(tap.fallbacks, { "box.shake", "ui.click" }) -- the older slot, then a look-alike
			end
			expect.equal(BoxFormat.soundCue("tap", nil, 9).key, "box.ux.rattle3")
			expect.equal(BoxFormat.soundCue("rise").key, "box.ux.rise")
			for rarity, key in BoxFormat.REVEAL_SOUNDS do
				for _, event in { "burst", "reveal" } :: { any } do
					local cue = BoxFormat.soundCue(event, rarity)
					expect.equal(cue.key, "box.ux.unbox" .. rarity)
					expect.equal((cue.fallbacks :: { string })[1], key) -- then reveal.<rarity>
					expect.equal(cue.delayMs, nil) -- one sound at the burst now (L:1183)
					expect.equal(cue.variance, 0)
				end
			end
			expect.equal(BoxFormat.soundCue("burst", "Nope").key, "box.ux.unboxCommon")
			-- lib:195: notes 0, 2, 4, 7, 9, 12 on the low file, 14, 16, 19 on the high one an octave up.
			expect.equal(BoxFormat.soundCue("letter", nil, 0).key, "box.ux.letterLow")
			expect.near(BoxFormat.soundCue("letter", nil, 5).pitch :: number, 2, 1e-9)
			local high = BoxFormat.soundCue("letter", nil, 8)
			expect.equal(high.key, "box.ux.letterHigh")
			expect.near(high.pitch :: number, 2 ^ (7 / 12), 1e-9)
			expect.equal(BoxFormat.soundCue("letter", nil, 9).key, "box.ux.letterLow") -- the notes go round
			expect.equal(BoxFormat.soundCue("stamp").key, "box.ux.stamp")
			expect.equal(BoxFormat.soundCue("close").key, "ui.pop")
			expect.equal(BoxFormat.revealSoundKey("Nope"), "reveal.common")
		end
	)

	t.test("the fancier reveal's letter notes: one per letter from 300 ms, 45 ms a character, spaces silent", function()
		expect.deepEqual(BoxFormat.letterNotes("Ab C"), {
			{ atMs = 300, index = 0 },
			{ atMs = 345, index = 1 },
			{ atMs = 435, index = 2 },
		})
		expect.deepEqual(BoxFormat.letterNotes(""), {})
	end)

	t.test("PR16: the flash peaks at most at the flash cap, not before minPeakMs, and is gone by 700 ms", function()
		local Tweens = t.requireClient("Anim/Tweens")
		local cap = Config.Vfx.Flash
		for _, ease in
			{
				function(u: number): number
					return u
				end,
				Tweens.curve("easeOut"),
			}
		do
			local peak, peakAt = 0, 0
			for ms = 0, 800, 2 do
				local a = BoxFormat.flashAlpha(ms, ease)
				if a > peak + 1e-9 then
					peak, peakAt = a, ms
				end
			end
			expect.truthy(peak <= cap.maxOverlayOpacity + 1e-9)
			expect.truthy(peak > cap.maxOverlayOpacity * 0.9)
			expect.truthy(peakAt >= cap.minPeakMs - 2 - 1e-6) -- the 2 ms sampling step
			expect.equal(BoxFormat.flashAlpha(700, ease), 0)
			expect.equal(BoxFormat.flashAlpha(0, ease), 0)
		end
	end)

	t.test(
		"PR18: the frame ledger never grants more than the budget; the burst and the rain take what is left",
		function()
			local total = Config.Vfx.Effects.boxRevealUiFrames
			local ledger = {}
			expect.equal(BoxFormat.budgetTake(ledger, 0, 16, 1.2, total), 16) -- the third tap's sparks
			expect.equal(BoxFormat.budgetFree(ledger, 0.5, total), total - 16)
			expect.equal(BoxFormat.budgetTake(ledger, 0.5, 30, 1, total), total - 16)
			expect.equal(BoxFormat.budgetFree(ledger, 0.6, total), 0)
			expect.equal(BoxFormat.budgetTake(ledger, 0.6, 5, 1, total), 0)
			expect.equal(BoxFormat.budgetFree(ledger, 1.3, total), 16) -- the first entry ran out
			expect.equal(BoxFormat.budgetFree(ledger, 2, total), total)
			-- rays (1) + rings (2) + at most 21 pieces = 24; the fancier reveal (2026-10-26): + its rarity ring (1) and
			-- its 21 always-moving frames (set aside)
			local burst = Config.UI.Fx.events.boxBurst
			expect.equal(1 + 2 + burst.maxPieces + 1 + Config.UI.Boxes.reveal.ux.frames, total)
			expect.equal(BoxFormat.burstPieces("Exclusive", total), burst.maxPieces)
			expect.equal(BoxFormat.burstPieces("Common", 5), 5)
			expect.equal(BoxFormat.burstPieces("Common", 0), 0)
			-- the rain: Epic and Exclusive only, within the free frames
			expect.equal(BoxFormat.rainPieces("Common", total), 0)
			expect.equal(BoxFormat.rainPieces("Uncommon", total), 0)
			expect.equal(BoxFormat.rainPieces("Epic", 10), 10)
			expect.equal(BoxFormat.rainPieces("Exclusive", 0), 0)
		end
	)

	t.test(
		"T14: the orbit starts at the design's camera, the drag turns it, the zoom stays in 4-11, the turntable 13.2°/s",
		function()
			local orbit = BoxFormat.orbitStart()
			local eye = BoxFormat.orbitEye(orbit)
			expect.near((eye - REVEAL.camera.eye).Magnitude, 0, 1e-6)
			local zoomed = BoxFormat.orbitStep(orbit, 1 / 60, { zoom = 100 })
			expect.near(zoomed.radius, REVEAL.orbit.minDist, 1e-9)
			zoomed = BoxFormat.orbitStep(orbit, 1 / 60, { zoom = -100 })
			expect.near(zoomed.radius, REVEAL.orbit.maxDist, 1e-9)
			local turned = orbit
			for _ = 1, 120 do
				turned =
					BoxFormat.orbitStep(turned, 1 / 60, { dragX = if turned == orbit then 100 else 0, height = 800 })
			end
			expect.near(turned.theta, orbit.theta - 2 * math.pi * 100 / 800, 1e-3)
			local spinning = table.clone(orbit)
			spinning.auto = true
			for _ = 1, 600 do -- 10 s: the damping's ramp is long over
				spinning = BoxFormat.orbitStep(spinning, 1 / 60, nil)
			end
			local before = spinning.theta
			for _ = 1, 60 do
				spinning = BoxFormat.orbitStep(spinning, 1 / 60, nil)
			end
			expect.near(math.deg(before - spinning.theta), REVEAL.orbit.autoRotateDegS, 0.05)
		end
	)

	t.test(
		"result text: NEW!, or the duplicate line (PR21; a copy for the pen, no Coins since pens3 phase 5)",
		function()
			expect.equal(BoxFormat.resultText(false), Strings.box.revealNew)
			expect.equal(BoxFormat.resultText(true), Strings.box.revealDuplicate)
			expect.falsy(string.find(BoxFormat.resultText(true), "Coins", 1, true))
		end
	)
	t.test("odds sign: the box's chance by rarity on Diego's 3 plaques, commonest first (owner: the real odds)", function()
		-- ECONOMY_V3: the Soft Box's 4 Commons 19% each, its Uncommons 8 + 8 + 4 + 4.
		expect.deepEqual(BoxFormat.signLines("snack"), { "COMMON  76%", "UNCOMMON  24%", "" })
		-- A non-whole percent keeps its two decimals.
		expect.deepEqual(BoxFormat.signLines("sweet"), { "EPIC  99.96%", "EXCLUSIVE  0.04%", "" })
		expect.deepEqual(BoxFormat.signLines("treat"), { "COMMON  56%", "UNCOMMON  30%", "EPIC  14%" })
		expect.deepEqual(BoxFormat.signLines("nope"), { "", "", "" })
	end)

	t.test("counter prompt: Shop Squishies for unknown (§7.6); restricted opens the boxes (pens3 phase 5)", function()
		expect.equal(BoxFormat.promptKey("restricted"), "prompt.seeBoxes") -- the fixed order opens there
		expect.equal(BoxFormat.promptKey("unknown"), "prompt.shopDirect")
		expect.equal(BoxFormat.promptKey("checking"), "prompt.seeBoxes")
		expect.equal(BoxFormat.promptKey("eligible"), "prompt.seeBoxes")
		expect.equal(BoxFormat.promptKey(nil), "prompt.seeBoxes")
		expect.truthy(Strings.resolve(BoxFormat.promptKey("unknown")))
		expect.truthy(Strings.resolve(BoxFormat.promptKey("eligible")))
		expect.equal(BoxFormat.standScreen("restricted"), "boxes")
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
		-- An entry from before pens3 phase 5 still carries `refund`: it is not read (copies).
		expect.deepEqual(
			BoxFormat.revealFromEntry(entry),
			{ requestId = guid, boxId = "snack", squishyId = "toast", isDuplicate = true, form = 0 }
		)
		expect.deepEqual(
			BoxFormat.revealFromEntry(daily),
			{ requestId = "daily:20000", boxId = "treat", squishyId = "bird", isDuplicate = false, form = 0 }
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
		for _, reason in { "economy.notEnoughCoins", "inventory.full", "box.saving", "box.paused" } do
			expect.falsy(BoxFormat.isIndeterminate(reason))
		end
	end)

	-- UI FINAL R7: the Boxes window (H:262-278, PR20) --------------------------------------------------------------------

	local CARDS = Config.UI.Boxes

	t.test("cardColumns: the selected card 2fr + gap, the others 1fr; sideways scroll under minFr", function()
		local body = CARDS.body
		-- the design's 1060 window: 1060 - 2 x 5 border - 2 x 24 padding = 1002 inside
		local wide = BoxFormat.cardColumns(1002, 3, 2, body.gap, body.minFr)
		expect.near(wide.fr, (1002 - 3 * body.gap) / 4, 1e-9)
		expect.near(wide.widths[2], 2 * wide.fr + body.gap, 1e-9)
		expect.near(wide.widths[1], wide.fr, 1e-9)
		expect.near(wide.widths[1] + wide.widths[2] + wide.widths[3] + 2 * body.gap, 1002, 1e-6)
		expect.equal(wide.scroll, false)
		local narrow = BoxFormat.cardColumns(600, 3, 1, body.gap, body.minFr)
		expect.equal(narrow.fr, body.minFr)
		expect.equal(narrow.scroll, true)
		expect.truthy(narrow.total > 600)
		local bad = BoxFormat.cardColumns(0 / 0, 0, 1, -5, 100)
		expect.equal(#bad.widths, 1)
		-- Owner 2026-10-17: a tap on the open box hides its list (selected 0): the three cards share the row.
		local closed = BoxFormat.cardColumns(1002, 3, 0, body.gap, body.minFr)
		expect.near(closed.widths[1], (1002 - 2 * body.gap) / 3, 1e-9)
		expect.near(closed.widths[1] + closed.widths[2] + closed.widths[3] + 2 * body.gap, 1002, 1e-6)
		expect.near(closed.total, 1002, 1e-6)
		expect.equal(closed.scroll, false)
	end)

	t.test("cardLayout: the plate 178 with room, else smaller; the tiles go first, then the plate", function()
		local parts = { name = 32, odds = 4 * 22 + 3 * 6, tiles = 42, open = 67 }
		local roomy = BoxFormat.cardLayout(560, parts)
		expect.equal(roomy.plate, CARDS.card.plate)
		expect.equal(roomy.tiles, true)
		local frame = 2 * (CARDS.card.pad + CARDS.card.border) + CARDS.card.lip
		local fixed = frame + parts.name + parts.odds + parts.open + 4 * CARDS.card.gap + parts.tiles
		local tight = BoxFormat.cardLayout(fixed + 100, parts)
		expect.equal(tight.plate, 100)
		expect.equal(tight.tiles, true)
		local noTiles = BoxFormat.cardLayout(fixed + CARDS.card.plateMin - 10, parts)
		expect.equal(noTiles.tiles, false)
		expect.truthy(noTiles.plate >= CARDS.card.plateMin)
		local phone = BoxFormat.cardLayout(200, parts)
		expect.equal(phone.plate, 0)
		expect.equal(phone.tiles, false)
	end)

	t.test("cardOdds: one row per rarity, lowest first, the exact percent and the bar's max(6, p) share", function()
		for _, box in Boxes.list() do
			local rows = BoxFormat.cardOdds(box.id)
			local byRarity = Boxes.byRarity(box.id)
			expect.equal(#rows, #byRarity)
			local total = 0
			for i, row in rows do
				local source = byRarity[#byRarity - i + 1]
				expect.equal(row.rarity, source.rarity)
				expect.equal(row.text, source.text .. "%")
				expect.near(row.share, math.max(CARDS.odds.minPct, source.percent) / 100, 1e-9)
				total += hundredths(source.text)
				if i > 1 then
					expect.truthy(Rarity.index(row.rarity) > Rarity.index(rows[i - 1].rarity))
				end
			end
			expect.equal(total, 10000)
		end
	end)

	t.test("toyTiles: rarest first (item order inside a rarity), at most max, owned or a silhouette", function()
		-- Pens3 phase 5: the Sweet Box holds 5 squishies (fewer than max: every one); the Treat Box's 12 stop at max.
		expect.equal(#BoxFormat.toyTiles("treat", nil, 6), 6)
		local tiles = BoxFormat.toyTiles("sweet", { dragon = true }, 6)
		expect.equal(#tiles, 5)
		expect.equal(tiles[1].id, "dragon")
		expect.equal(tiles[1].owned, true)
		expect.equal(tiles[2].owned, false)
		for i = 2, #tiles do
			local a = Rarity.index(Catalog.get(tiles[i - 1].id).rarity)
			local b = Rarity.index(Catalog.get(tiles[i].id).rarity)
			expect.truthy(a >= b)
		end
		expect.equal(#BoxFormat.toyTiles("snack", nil, 2), 2)
		expect.equal(#BoxFormat.toyTiles("nope", nil, 6), 0)
		expect.equal(BoxFormat.tilesThatFit(42), 1)
		expect.equal(BoxFormat.tilesThatFit(42 * 4 + 4 * 3), 4)
		expect.equal(BoxFormat.tilesThatFit(9999), CARDS.toys.max)
		expect.equal(BoxFormat.tilesThatFit(10), 0)
	end)

	t.test("subtitle: shown while a box can still give a new squishy (H:260, FD5)", function()
		expect.equal(BoxFormat.subtitleShown({}), true)
		local all = {}
		for _, box in Boxes.list() do
			for _, item in box.items do
				all[item.id] = true
			end
		end
		expect.equal(BoxFormat.subtitleShown(all), false)
	end)
end
