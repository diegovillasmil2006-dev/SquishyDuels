--!strict
-- ShopFormat_Test: the pure display logic of StarterPlayerScripts.Client.UI.ShopFormat (the Shop screen). Server only
-- (ServerStorage.UnitTest). Pure: no instances, no LocalPlayer, no MarketplaceService.
-- Contract (DESIGN §11.6 Shop, §6.6, §6.10 restricted shortcut, §6.11 Robux off, §11.3, §11.5, §2.10, §3.11):
--   * params: {tab = "coins"} opens the Coins tab; a squishyId or a boxId opens the Squishies tab; junk is dropped;
--   * card states: Owned, Buy with the price, need Coins with the missing amount, purchasing, not sold;
--   * sort: rarity, then price, then name; the box filter keeps only Boxes.get(boxId).items;
--   * Buy is disabled during the duel lock, while the profile loads / is OFFLINE / READONLY, and while a save is pending;
--   * a ShopBuy Result: success (charged), owned (charged = false: "No Coins were spent."), failed (the reason, plus
--     "No Coins were spent." only when charged == false); a call that never reached the server keeps its request id;
--   * the Coins tab: only shop.coinsUnavailable while no bundle is offered (always in v1, and while Grip forbids
--     bundles); offered bundles show their amount and "…" / "Unavailable" / "{price} Robux".
--   * Part 8 layout (DESIGN §11.2, §11.6) at 667×375, 893×673, 1280×720 and 1920×1080, with and without the box filter,
--     at the default and the largest text size (widths from a generous per-character estimate): panelLayout fits the
--     screen with touch-sized chips; buyBox keeps the natural width when it fits, else the column's width with the
--     wrapped height; detailLayout pins Buy (with its reserved "Balance after" line) and Inspect under the list inside
--     the column, never overlapping; PANEL and SUB_GAP equal the Squishies panel, Theme and ConfirmButton.
--   * Foam UI restyle (2026-10-09): priceNumber is the bare price ("7,500") and cardLine the card's line with the
--     coin for a buyable card (the bare price) and need Coins, words without it otherwise; panelLayout(..., topPadding)
--     shrinks the content box by the header tab's room and still fits the screen; a bad padding means PANEL.padding.
--   * Foam fix batch (2026-10-09): no header row (Close hangs on the corner): the tab row starts the content; with the
--     card width the grid takes the columns that fit in gridShare (InventoryFormat.gridFit) and the detail column the
--     rest; on an 844×390 phone Buy (its widest text) and Inspect share one row.
--   * Foam fix round 2 (2026-10-09): PANEL.buttonGap (Theme.Padding.medium, as on Squishies) between Buy and Inspect,
--     the row from the column's left edge (Buy is drawn as wide as its box, so it no longer floats in it).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local ShopFormat = t.requireClient("UI/ShopFormat")
	local Boxes = t.requireShared("Boxes")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")

	local function ids(list: { any }): { string }
		local out = {}
		for _, entry in list do
			table.insert(out, entry.id)
		end
		return out
	end

	local function coinsText(n: string): string
		return Strings.format(Strings.common.coinsAmount, { coins = n })
	end

	-- Params and tabs ---------------------------------------------------------------------------------------------

	t.test("params: the coin pill opens Coins; a squishy or a box opens Squishies; junk is dropped", function()
		expect.deepEqual(ShopFormat.params(nil), { tab = "squishies" })
		expect.deepEqual(ShopFormat.params({ tab = "coins" }), { tab = "coins" })
		expect.deepEqual(ShopFormat.params({ squishyId = "dragon" }), { tab = "squishies", squishyId = "dragon" })
		expect.deepEqual(ShopFormat.params({ boxId = "snack" }), { tab = "squishies", boxId = "snack" })
		expect.deepEqual(ShopFormat.params({ tab = "coins", squishyId = "toast" }), {
			tab = "squishies",
			squishyId = "toast",
		})
		expect.deepEqual(ShopFormat.params({ boxId = "nope", tab = "passes", squishyId = 5 }), { tab = "squishies" })
		expect.deepEqual(ShopFormat.params("coins"), { tab = "squishies" })
	end)

	t.test("nextTab: L1 / R1 cycle Squishies and Coins (no passes tab)", function()
		expect.deepEqual(ShopFormat.TABS, { "squishies", "coins" })
		expect.equal(ShopFormat.nextTab("squishies", 1), "coins")
		expect.equal(ShopFormat.nextTab("coins", 1), "squishies")
		expect.equal(ShopFormat.nextTab("squishies", -1), "coins")
		expect.equal(ShopFormat.nextTab("coins", -1), "squishies")
		expect.equal(ShopFormat.nextTab("junk", 1), "coins")
	end)

	-- Card states -------------------------------------------------------------------------------------------------

	t.test("cardState: owned, not sold, purchasing, need Coins (with the missing amount) and buy", function()
		local function card(price: number?, owned: boolean, coins: number, buying: boolean): any
			local state, missing = ShopFormat.cardState(price, owned, coins, buying)
			return { state = state, missing = missing }
		end
		expect.deepEqual(card(1200, true, 0, false), { state = "owned", missing = 0 })
		expect.deepEqual(card(nil, true, 0, false), { state = "owned", missing = 0 }) -- the free starter
		expect.deepEqual(card(nil, false, 99999, false), { state = "notSold", missing = 0 })
		expect.deepEqual(card(1200, false, 5000, true), { state = "purchasing", missing = 0 })
		expect.deepEqual(card(25000, false, 1300, false), { state = "needCoins", missing = 23700 })
		expect.deepEqual(card(1200, false, 1200, false), { state = "buy", missing = 0 })
		expect.deepEqual(card(1200, false, 0 / 0, false), { state = "needCoins", missing = 1200 })
	end)

	t.test("cardStatusText: Owned, the price, the missing Coins, Loading… and not for sale", function()
		local function entry(state: string, price: number?, missing: number): any
			return { state = state, price = price, missing = missing }
		end
		expect.equal(ShopFormat.cardStatusText(entry("owned", 1200, 0)), Strings.common.owned)
		expect.equal(ShopFormat.cardStatusText(entry("buy", 25000, 0)), coinsText("25,000"))
		expect.equal(ShopFormat.cardStatusText(entry("buy", 25000, 0)), "25,000 Coins")
		expect.equal(
			ShopFormat.cardStatusText(entry("needCoins", 25000, 23700)),
			Strings.format(Strings.common.needCoins.many, { missing = "23,700" })
		)
		expect.equal(
			ShopFormat.cardStatusText(entry("needCoins", 1200, 1)),
			Strings.format(Strings.common.needCoins.one, { missing = "1" })
		)
		expect.equal(ShopFormat.cardStatusText(entry("purchasing", 1200, 0)), Strings.common.loading)
		expect.equal(ShopFormat.cardStatusText(entry("notSold", nil, 0)), Strings.reason.shop.notForSale)
		expect.equal(ShopFormat.priceText(nil), nil)
	end)

	t.test("entries: every Catalog squishy, sorted by rarity, then price, then name", function()
		local owned = { kitty_bread = { at = 0 } }
		local list = ShopFormat.entries(Catalog.list(), owned, 3_000_000, nil, nil)
		expect.equal(#list, #Catalog.list())
		-- Commons first (Kitty Bread is not sold, so after the priced Commons), Dragon last.
		expect.deepEqual(ids(list), {
			"banana",
			"boba_bear",
			"pancake_pup",
			"toast",
			"kitty_bread",
			"butter",
			"chocolate",
			"mochi_fox",
			"strawberry_frog",
			"bird",
			"cloud_bunny",
			"cupcake_axolotl",
			"donut",
			"dragon",
		})
		local byId: { [string]: any } = {}
		for _, e in list do
			byId[e.id] = e
		end
		expect.equal(byId.kitty_bread.state, "owned")
		expect.equal(byId.toast.state, "buy")
		-- Spec 2026-10-12 §6 prices: Toast 10K, Butter 2.7M, Birdie 1.7B, Dragon 1.1T.
		expect.equal(byId.toast.price, 10_000)
		expect.equal(byId.butter.state, "buy")
		expect.equal(byId.bird.state, "needCoins")
		expect.equal(byId.bird.missing, 1_697_000_000)
		expect.equal(byId.dragon.missing, 1_099_997_000_000)
		-- A buy in flight marks only that card.
		local buying = ShopFormat.entries(Catalog.list(), owned, 3_000_000, "toast", nil)
		for _, e in buying do
			if e.id == "toast" then
				expect.equal(e.state, "purchasing")
			elseif e.id == "banana" then
				expect.equal(e.state, "buy")
			end
		end
	end)

	t.test("the box filter keeps only that box's items (the restricted shortcut, §6.10)", function()
		local snack = ShopFormat.boxItemIds("snack")
		expect.truthy(snack ~= nil)
		local expected: { [string]: boolean } = {}
		for _, item in Boxes.get("snack").items do
			expected[item.id] = true
		end
		expect.deepEqual(snack, expected)
		expect.equal(ShopFormat.boxItemIds("nope"), nil)
		expect.equal(ShopFormat.boxItemIds(nil), nil)
		local list = ShopFormat.entries(Catalog.list(), {}, 0, nil, snack)
		expect.equal(#list, #Boxes.get("snack").items)
		for _, e in list do
			expect.truthy(expected[e.id])
		end
		-- The Sweet Box has Dragon; the Snack Box doesn't.
		local sweet = ShopFormat.entries(Catalog.list(), {}, 0, nil, ShopFormat.boxItemIds("sweet"))
		expect.equal(sweet[#sweet].id, "dragon")
	end)

	t.test("keepSelection keeps a listed selection, else picks the first entry", function()
		local list = ShopFormat.entries(Catalog.list(), {}, 0, nil, ShopFormat.boxItemIds("snack"))
		expect.equal(ShopFormat.keepSelection("butter", list), "butter") -- in the Snack Box (spec 2026-10-12 §8)
		expect.equal(ShopFormat.keepSelection("dragon", list), list[1].id)
		expect.equal(ShopFormat.keepSelection(nil, list), list[1].id)
		expect.equal(ShopFormat.keepSelection("toast", {}), nil)
	end)

	-- Spend blocks -------------------------------------------------------------------------------------------------

	t.test("spendBlock: duel lock, loading, offline / read-only and a pending save disable Buy", function()
		local function status(name: string, savePending: boolean?): any
			return { status = name, persisted = true, savePending = savePending == true }
		end
		expect.equal(ShopFormat.spendBlock(status("ready"), false), nil)
		expect.equal(ShopFormat.spendBlock(nil, false), nil)
		expect.equal(ShopFormat.spendBlock(status("ready"), true), Strings.common.lockedInDuel)
		expect.equal(ShopFormat.spendBlock(status("loading"), false), Strings.common.loading)
		expect.equal(ShopFormat.spendBlock(status("offline"), false), Strings.reason.data.offline)
		expect.equal(ShopFormat.spendBlock(status("readonly"), false), Strings.reason.data.readOnly)
		expect.equal(ShopFormat.spendBlock(status("ready", true), false), Strings.reason.box.saving)
	end)

	-- Buy results --------------------------------------------------------------------------------------------------

	t.test("buyOutcome: success, owned (charged = false) and the save-pending flag", function()
		local ok = ShopFormat.buyOutcome({
			ok = true,
			v = 1,
			data = { squishyId = "dragon", charged = true, savePending = false },
		})
		expect.deepEqual(ok, { kind = "success", squishyId = "dragon", savePending = false, retry = false })
		local pending = ShopFormat.buyOutcome({
			ok = true,
			v = 1,
			data = { squishyId = "dragon", charged = true, savePending = true },
		})
		expect.equal(pending.savePending, true)
		local owned = ShopFormat.buyOutcome({
			ok = true,
			v = 1,
			data = { squishyId = "toast", charged = false, savePending = false },
		})
		expect.equal(owned.kind, "owned")
		expect.equal(owned.squishyId, "toast")
		expect.equal(owned.text, Strings.reason.shop.owned .. " " .. Strings.common.noCoinsSpent)
	end)

	t.test("buyOutcome: a server refusal says no Coins were spent; a lost call keeps its request id", function()
		local refused = ShopFormat.buyOutcome({ ok = false, v = 1, reason = "economy.notEnoughCoins", charged = false })
		expect.equal(refused.kind, "failed")
		expect.equal(refused.retry, false)
		expect.equal(refused.text, Strings.reason.economy.notEnoughCoins .. " " .. Strings.common.noCoinsSpent)
		local saving = ShopFormat.buyOutcome({ ok = false, v = 1, reason = "box.saving", charged = false })
		expect.equal(saving.text, Strings.reason.box.saving .. " " .. Strings.common.noCoinsSpent)
		-- A local refusal or a timeout has no `charged`: no "No Coins were spent", and the id is kept for a retry.
		local lost = ShopFormat.buyOutcome({ ok = false, v = 0, reason = "error.generic" })
		expect.equal(lost.kind, "failed")
		expect.equal(lost.retry, true)
		expect.equal(lost.text, Strings.error.generic)
	end)

	t.test("requestIdFor: a retry of the same buy reuses the id; another squishy or price gets a new one", function()
		local n = 0
		local function newId(): string
			n += 1
			return "id" .. n
		end
		local id1, pending = ShopFormat.requestIdFor(nil, "dragon", 25000, newId)
		expect.equal(id1, "id1")
		expect.deepEqual(pending, { squishyId = "dragon", price = 25000, requestId = "id1" })
		local again = ShopFormat.requestIdFor(pending, "dragon", 25000, newId)
		expect.equal(again, "id1")
		local other = ShopFormat.requestIdFor(pending, "toast", 1200, newId)
		expect.equal(other, "id2")
		local repriced = ShopFormat.requestIdFor(pending, "dragon", 24000, newId)
		expect.equal(repriced, "id3")
	end)

	-- Coins tab ------------------------------------------------------------------------------------------------------

	t.test("Coins tab in v1: only shop.coinsUnavailable (every productId is nil)", function()
		local bundles = Config.Monetization.CoinBundles
		for _, bundle in bundles do
			expect.equal(bundle.productId, nil)
		end
		local allowed = ShopFormat.bundlesAllowed(Config.Grip)
		local view = ShopFormat.coinsView({}, bundles, {}, allowed)
		expect.deepEqual(view, { unavailable = true, text = Strings.shop.coinsUnavailable, rows = {} })
		-- Even if a server offered every key, bundles without a productId are never listed.
		local keys = {}
		for _, bundle in bundles do
			table.insert(keys, bundle.key)
		end
		expect.equal(ShopFormat.coinsView(keys, bundles, {}, true).unavailable, true)
		expect.equal(ShopFormat.coinsView(nil, bundles, {}, true).unavailable, true)
	end)

	t.test("bundles stay off while Grip is on with allowBundlesWithCapsules false (G-E)", function()
		expect.equal(ShopFormat.bundlesAllowed({ enabled = true, allowBundlesWithCapsules = false }), false)
		expect.equal(ShopFormat.bundlesAllowed({ enabled = true, allowBundlesWithCapsules = true }), true)
		expect.equal(ShopFormat.bundlesAllowed({ enabled = false, allowBundlesWithCapsules = false }), true)
		expect.equal(ShopFormat.bundlesAllowed(Config.Grip), false) -- the shipped config
		local fixture =
			{ { key = "coins_test", nameKey = "bundle.handful", productId = 1, coins = 1000, onSale = true } }
		expect.equal(ShopFormat.coinsView({ "coins_test" }, fixture, {}, false).unavailable, true)
	end)

	t.test("offered bundles (a test fixture): amount from config and the Robux price states", function()
		local fixture: { any } = {
			{ key = "coins_a", nameKey = "bundle.handful", productId = 1, coins = 1000, onSale = true },
			{ key = "coins_b", nameKey = "bundle.jar", productId = 2, coins = 2750, onSale = true },
			{ key = "coins_c", nameKey = "bundle.tin", productId = 3, coins = 6500, onSale = false },
			{ key = "coins_d", nameKey = "bundle.barrel", productId = nil, coins = 18000, onSale = true },
		}
		local prices = {
			coins_a = { status = "ok", price = 99 },
			coins_b = { status = "failed" },
		}
		local view = ShopFormat.coinsView({ "coins_a", "coins_b", "coins_c", "coins_d" }, fixture, prices, true)
		expect.equal(view.unavailable, false)
		expect.equal(view.text, nil)
		expect.equal(#view.rows, 2) -- not on sale and no productId are left out
		expect.equal(view.rows[1].key, "coins_a")
		expect.equal(view.rows[1].name, Strings.bundle.handful)
		expect.equal(view.rows[1].coinsText, coinsText("1,000"))
		expect.equal(view.rows[1].priceText, Strings.format(Strings.shop.robuxPrice, { price = "99" }))
		expect.equal(view.rows[1].priceReady, true)
		expect.equal(view.rows[2].priceText, Strings.shop.robuxUnavailable)
		expect.equal(view.rows[2].priceReady, false)
		-- Not offered by the server: not listed.
		expect.equal(#ShopFormat.coinsView({ "coins_b" }, fixture, prices, true).rows, 1)
	end)

	t.test("robuxText: loading, unavailable and the price", function()
		expect.equal(ShopFormat.robuxText(nil), Strings.shop.robuxLoading)
		expect.equal(ShopFormat.robuxText({ status = "loading" }), Strings.shop.robuxLoading)
		expect.equal(ShopFormat.robuxText({ status = "failed" }), Strings.shop.robuxUnavailable)
		expect.equal(ShopFormat.robuxText({ status = "ok" }), Strings.shop.robuxUnavailable)
		expect.equal(ShopFormat.robuxText({ status = "ok", price = 0 / 0 }), Strings.shop.robuxUnavailable)
		expect.equal(ShopFormat.robuxText({ status = "ok", price = 1250 }), "1,250 Robux")
	end)
	-- Part 8 layout ---------------------------------------------------------------------------------------------------

	local InventoryFormat = t.requireClient("UI/InventoryFormat")
	local Theme = t.requireClient("UI/Theme")
	local ConfirmButton = t.requireClient("UI/Components/ConfirmButton")
	local TOUCH = Config.UI.Touch
	local EPS = 1e-6
	local EM = 0.6 -- per character: wider than Builder Sans Bold really is (a pessimistic estimate)
	local BUTTON_PADDING = 2 * 18 + 4
	local SCREENS = {
		{ label = "667x375", size = Vector2.new(667, 375) },
		{ label = "893x673", size = Vector2.new(893, 673) },
		{ label = "1280x720", size = Vector2.new(1280, 720) },
		{ label = "1920x1080", size = Vector2.new(1920, 1080) },
	}

	local function overlap(a: any, b: any): boolean
		return a.x < b.x + b.w - EPS and b.x < a.x + a.w - EPS and a.y < b.y + b.h - EPS and b.y < a.y + a.h - EPS
	end

	t.test("PANEL and SUB_GAP: the Squishies panel's, Theme's and ConfirmButton's numbers", function()
		expect.deepEqual(ShopFormat.PANEL, InventoryFormat.PANEL)
		expect.equal(ShopFormat.PANEL.padding, Theme.Padding.medium)
		expect.equal(ShopFormat.PANEL.gap, Theme.Padding.small)
		expect.equal(ShopFormat.SUB_GAP, ConfirmButton.SUB_GAP)
	end)

	t.test("buyBox: the natural width when it fits, else the column's width and the wrapped height", function()
		expect.deepEqual(ShopFormat.buyBox(120, 300, 56, 90), { w = 120, h = 56, wraps = false })
		expect.deepEqual(ShopFormat.buyBox(300, 300, 56, 90), { w = 300, h = 56, wraps = false })
		expect.deepEqual(ShopFormat.buyBox(340, 300, 56, 90), { w = 300, h = 90, wraps = true })
		expect.deepEqual(ShopFormat.buyBox(340, 300, 56, 40.2), { w = 300, h = 56, wraps = true })
	end)

	for _, screen in SCREENS do
		for _, filtered in { false, true } do
			for _, textScale in { 1, Config.UI.PreferredTextScale.Largest } do
				local name = `{screen.label} filter {filtered} text x{textScale}`
				t.test(`panelLayout + detailLayout {name}: Buy and Inspect pinned inside the column`, function()
					local l = ShopFormat.panelLayout(screen.size, filtered)
					expect.truthy(l.panelWidth * l.scale <= screen.size.X + EPS)
					expect.truthy(l.panelHeight * l.scale <= screen.size.Y + EPS)
					expect.truthy(l.chipHeight * l.scale >= TOUCH.minTargetFloor - EPS)
					expect.truthy(l.closeHeight * l.scale >= TOUCH.minTargetFloor - EPS)
					expect.near(l.bodyTop, l.chipHeight + ShopFormat.PANEL.gap) -- fix batch: the tab row starts it
					expect.near(l.bodyTop + l.bodyHeight, l.contentHeight)
					expect.equal(l.listTop, if filtered then l.chipHeight + ShopFormat.PANEL.gap else 0)
					expect.near(l.detailHeight, l.bodyHeight - l.listTop)
					local buttonPx = Config.UI.TextSize.Button * textScale
					local smallPx = Config.UI.TextSize.Small * textScale
					local confirmText = Strings.format(Strings.spend.confirm, { price = "25,000" })
					local natural = #confirmText * buttonPx * EM + BUTTON_PADDING
					local inner = l.detailWidth - 36
					local lines = math.ceil(#confirmText * buttonPx * EM / inner)
					local buyBox = ShopFormat.buyBox(natural, l.detailWidth, 56, lines * buttonPx * 1.3 + 8)
					expect.truthy(buyBox.w <= l.detailWidth + EPS)
					local inspect = { w = #Strings.common.inspect * buttonPx * EM + BUTTON_PADDING, h = 56 }
					local balance = smallPx * 1.3
					local gap = ShopFormat.PANEL.gap
					for _, case in { { buy = true, inspect = true }, { buy = true }, { inspect = true } } :: { any } do
						local buy = if case.buy then { w = buyBox.w, h = buyBox.h } else nil
						local d = ShopFormat.detailLayout(
							l.detailWidth,
							l.detailHeight,
							gap,
							buy,
							balance,
							if case.inspect then inspect else nil
						)
						expect.near(d.buttonsTop + d.buttonsHeight, l.detailHeight)
						expect.truthy(d.scrollHeight >= 0)
						expect.truthy(d.scrollHeight + gap <= d.buttonsTop + EPS)
						expect.truthy(l.bodyTop + l.listTop + d.buttonsTop + d.buttonsHeight <= l.contentHeight + EPS)
						local rects = {}
						if case.buy then
							local r = d.buy :: any
							expect.truthy(r ~= nil)
							-- The holder: the button and its reserved "Balance after" line under it.
							expect.near(r.h, buyBox.h + ShopFormat.SUB_GAP + balance)
							table.insert(rects, r)
						else
							expect.equal(d.buy, nil)
						end
						if case.inspect then
							table.insert(rects, d.inspect :: any)
						else
							expect.equal(d.inspect, nil)
						end
						for i, r in rects do
							expect.truthy(r.x >= -EPS and r.x + r.w <= l.detailWidth + EPS)
							expect.truthy(r.y + r.h <= d.buttonsHeight + EPS)
							for j = i + 1, #rects do
								expect.falsy(overlap(r, rects[j]))
							end
						end
						if not filtered and textScale == 1 then
							expect.truthy(d.scrollHeight > 0) -- something of the detail always shows
						end
					end
				end)
			end
		end
	end

	-- Foam UI restyle (2026-10-09) ------------------------------------------------------------------------------------

	t.test("priceNumber / cardLine: the coin and a bare price; every other state in words", function()
		local function entry(state: string, price: number?, missing: number): any
			return { state = state, price = price, missing = missing }
		end
		expect.equal(ShopFormat.priceNumber(25000), "25,000")
		expect.equal(ShopFormat.priceNumber(1200.9), "1,200")
		expect.equal(ShopFormat.priceNumber(nil), nil)
		local function line(e: any): { text: string, coin: boolean }
			local text, coin = ShopFormat.cardLine(e)
			return { text = text, coin = coin }
		end
		expect.deepEqual(line(entry("buy", 7500, 0)), { text = "7,500", coin = true })
		expect.deepEqual(line(entry("needCoins", 25000, 23700)), {
			text = Strings.format(Strings.common.needCoins.many, { missing = "23,700" }),
			coin = true,
		})
		expect.deepEqual(line(entry("owned", 1200, 0)), { text = Strings.common.owned, coin = false })
		expect.deepEqual(line(entry("purchasing", 1200, 0)), { text = Strings.common.loading, coin = false })
		expect.deepEqual(line(entry("notSold", nil, 0)), { text = Strings.reason.shop.notForSale, coin = false })
	end)

	-- Foam fix batch (2026-10-09) -------------------------------------------------------------------------------------

	local CARD_WIDTH = Config.UI.Shop.cardWidth
	for _, screen in SCREENS do
		t.test(
			`panelLayout {screen.label} with the card width: the grid fits its columns, the detail takes the rest`,
			function()
				for _, filtered in { false, true } do
					local plain = ShopFormat.panelLayout(screen.size, filtered, 32)
					local l = ShopFormat.panelLayout(screen.size, filtered, 32, CARD_WIDTH)
					local panel = ShopFormat.PANEL
					local fit = InventoryFormat.gridFit(
						plain.contentWidth * panel.gridShare,
						CARD_WIDTH,
						panel.cellPad,
						panel.gridChrome
					)
					expect.equal(l.columns, fit.columns)
					expect.near(l.gridWidth, fit.width)
					expect.near(l.gridWidth + panel.columnGap + l.detailWidth, l.contentWidth)
					expect.truthy(l.detailWidth >= plain.detailWidth - EPS)
					expect.equal(l.bodyTop, plain.bodyTop)
					expect.equal(l.detailHeight, plain.detailHeight)
				end
				expect.equal(ShopFormat.panelLayout(screen.size, false, 32).columns, 0) -- no card width: the plain split
			end
		)
	end

	t.test("844x390 phone: Buy at its widest and Inspect share one row in the detail column", function()
		-- SD_Modal on an 844×390 phone (the safe area, as measured in the foam shots); 32 = the hanging Close's room.
		local l = ShopFormat.panelLayout(Vector2.new(844, 311), false, 32, CARD_WIDTH)
		local buttonPx = Config.UI.TextSize.Button
		-- Fix round 2: with PANEL.buttonGap (12) the generous 0.6 em guess no longer fits one row; the foam shots measured
		-- Buy's box for "Confirm: 1,200 Coins" at 200 base on this phone (about 0.4 em a character), so 0.5 em still
		-- leaves a wide margin.
		local em = 0.5
		local confirmText = Strings.format(Strings.spend.confirm, { price = "25,000" })
		local natural = #confirmText * buttonPx * em + BUTTON_PADDING
		local buyBox = ShopFormat.buyBox(natural, l.detailWidth, 56, buttonPx * 1.3 + 8)
		expect.equal(buyBox.wraps, false)
		local inspect = { w = #Strings.common.inspect * buttonPx * em + BUTTON_PADDING, h = 56 }
		local d = ShopFormat.detailLayout(
			l.detailWidth,
			l.detailHeight,
			ShopFormat.PANEL.gap,
			{ w = buyBox.w, h = buyBox.h },
			Config.UI.TextSize.Small * 1.3,
			inspect
		)
		expect.equal(d.rows, 1)
		expect.truthy(d.scrollHeight > 0)
	end)

	-- Foam fix round 2 (2026-10-09): Buy is drawn as wide as its box (ShopController), so the row reads like the Squishies
	-- one: from the column's left edge, PANEL.buttonGap between the buttons, the list PANEL.gap above them.
	t.test("detailLayout: Buy at the column's left edge, Inspect PANEL.buttonGap after it, as on Squishies", function()
		expect.equal(ShopFormat.PANEL.buttonGap, Theme.Padding.medium)
		local d = ShopFormat.detailLayout(500, 300, ShopFormat.PANEL.gap, { w = 200, h = 56 }, 21, { w = 110, h = 56 })
		expect.equal(d.rows, 1)
		local buy, inspect = d.buy :: any, d.inspect :: any
		expect.equal(buy.x, 0)
		expect.equal(inspect.x, 200 + ShopFormat.PANEL.buttonGap)
		expect.equal(inspect.y, buy.y) -- one row, tops level
		expect.equal(d.scrollHeight, 300 - (56 + ShopFormat.SUB_GAP + 21) - ShopFormat.PANEL.gap)
	end)

	-- The header tab's room at the top of the panel (an H2 tab: about 29 base px at the default text, 35 at Largest).
	for _, screen in SCREENS do
		t.test(`panelLayout {screen.label} with a header tab: the content box shrinks, the rest still fits`, function()
			for _, filtered in { false, true } do
				local plain = ShopFormat.panelLayout(screen.size, filtered)
				expect.equal(plain.topPadding, ShopFormat.PANEL.padding)
				for _, top in { 29, 35 } do
					local l = ShopFormat.panelLayout(screen.size, filtered, top)
					expect.equal(l.topPadding, top)
					expect.near(l.contentHeight, plain.contentHeight - (top - ShopFormat.PANEL.padding))
					expect.near(l.bodyTop + l.bodyHeight, l.contentHeight)
					expect.near(l.detailHeight, l.bodyHeight - l.listTop)
					expect.truthy(l.detailHeight > 0)
					-- The panel and the tab's outer half (top - its 6 px gap) fit the screen together.
					expect.truthy((l.panelHeight + (top - 6)) * l.scale <= screen.size.Y + EPS)
				end
				-- A bad padding means the panel padding.
				expect.deepEqual(ShopFormat.panelLayout(screen.size, filtered, 0 / 0), plain)
				expect.deepEqual(ShopFormat.panelLayout(screen.size, filtered, -3), plain)
			end
		end)
	end
end
