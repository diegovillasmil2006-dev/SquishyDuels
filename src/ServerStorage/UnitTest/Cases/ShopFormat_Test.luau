--!strict
-- ShopFormat_Test: the pure display logic of StarterPlayerScripts.Client.UI.ShopFormat (the Shop screen). Server only
-- (ServerStorage.UnitTest). Pure: no instances, no LocalPlayer, no MarketplaceService.
-- Contract (DESIGN §11.6 Shop, §6.6, §6.10 restricted shortcut, §6.11 Robux off, §11.3, §11.5, §2.10, §3.11):
--   * params: {tab = "coins"} opens the Coins tab; a squishyId or a boxId opens the Squishies tab; junk is dropped;
--   * card states: Owned (the free starter only), Buy with the price, need Coins with the missing amount, purchasing,
--     not sold; pens3 phase 5: the price is Pricing.shopPrice (the Welcome price for a Common not owned yet, with the
--     shop.welcomePrice line; the Catalog price after), and an owned squishy is bought again as a copy;
--   * sort: rarity, then price, then name; the box filter keeps only Boxes.get(boxId).items;
--   * Buy is disabled during the duel lock, while the profile loads / is OFFLINE / READONLY, while a save is pending
--     and while the Toy Box is full (pens3 phase 5, PenMath.room 0);
--   * a ShopBuy Result: success (charged), failed (the reason, plus "No Coins were spent." only when charged == false);
--     a call that never reached the server keeps its request id;
--   * the Coins tab: only shop.coinsUnavailable while no bundle is offered (always in v1, and while Grip forbids
--     bundles); offered bundles show their amount and "…" / "Unavailable" / "{price} Robux".
--   * Foam UI restyle (2026-10-09): priceNumber is the bare price ("7,500") beside the coin.
--   * Shop fix (2026-10-22): the cards are the design's GAME PASSES cards (H:339-349): 2 columns, 104 high unless the
--     text needs more, the chip and the text column share the card (chipWidth, rowMinWidth, rowTextWidth, rowHeight).
--   * UI FINAL R6 (the Shop window, H:289-342): panelLayout is the design's body (330 | 652, 498 high on a desktop,
--     2 columns of cards) and fits every screen with touch-sized chips; a phone shows the list or the featured card
--     (the separate detail state) and the tab chips only over the list; featuredLayout keeps the name, line and BUY
--     and gives the art 230 or what is left (hidden under minPx); featuredLine / featuredView; COINS only with a
--     bundle, and L1 / R1 jump between the drawn sections.

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
		-- Pens3 phase 5: an owned squishy that is sold can be bought again (a copy for the pen).
		expect.deepEqual(card(1200, true, 0, false), { state = "needCoins", missing = 1200 })
		expect.deepEqual(card(1200, true, 5000, false), { state = "buy", missing = 0 })
		expect.deepEqual(card(nil, true, 0, false), { state = "owned", missing = 0 }) -- the free starter
		expect.deepEqual(card(nil, false, 99999, false), { state = "notSold", missing = 0 })
		expect.deepEqual(card(1200, false, 5000, true), { state = "purchasing", missing = 0 })
		expect.deepEqual(card(25000, false, 1300, false), { state = "needCoins", missing = 23700 })
		expect.deepEqual(card(1200, false, 1200, false), { state = "buy", missing = 0 })
		expect.deepEqual(card(1200, false, 0 / 0, false), { state = "needCoins", missing = 1200 })
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
		-- ECONOMY_V3:163 (pens3 phase 5): a Common not owned yet has the Welcome price (D1:202), Butter 1.875M,
		-- Birdie 1.8B, Dragon 1.1T.
		expect.equal(byId.toast.price, Config.Economy.Pen.welcomePrice.Common)
		expect.equal(byId.toast.price, 3_000)
		expect.equal(byId.toast.welcomeText, Strings.format(Strings.shop.welcomePrice, { coins = "3,000" }))
		expect.equal(byId.butter.price, 1_875_000)
		expect.equal(byId.butter.welcomeText, nil)
		expect.equal(byId.butter.state, "buy")
		expect.equal(byId.bird.state, "needCoins")
		expect.equal(byId.bird.missing, 1_797_000_000)
		expect.equal(byId.dragon.missing, 1_099_997_000_000)
		expect.equal(byId.kitty_bread.welcomeText, nil)
		-- Once owned, a Common costs its Catalog price and can be bought again as a copy (no Welcome line).
		local again = ShopFormat.entries(Catalog.list(), { kitty_bread = { at = 0 }, toast = { at = 1 } }, 3_000_000)
		for _, e in again do
			if e.id == "toast" then
				expect.equal(e.owned, true)
				expect.equal(e.price, Catalog.get("toast").shopPrice)
				expect.equal(e.price, 789_000)
				expect.equal(e.state, "buy")
				expect.equal(e.welcomeText, nil)
			elseif e.id == "banana" then
				expect.equal(e.price, 3_000) -- each Common has its own Welcome price
			end
		end
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
		-- Pens3 phase 5: a full Toy Box (3 spots + toyBoxMax squishies: PenMath.room 0) blocks Buy before any Coins
		-- move; no pen state yet = not known (the server decides).
		local items = {}
		for i = 1, 3 + Config.Economy.Pen.toyBoxMax do
			table.insert(items, { id = i, kind = "toast" })
		end
		local full = { spots = 3, nextId = #items + 1, items = items }
		expect.equal(ShopFormat.spendBlock(status("ready"), false, full), Strings.reasonText("inventory.full"))
		expect.equal(ShopFormat.spendBlock(status("ready"), false, nil), nil)
		expect.equal(
			ShopFormat.spendBlock(status("ready"), false, { spots = 4, nextId = #items + 1, items = items }),
			nil
		)
		expect.equal(ShopFormat.spendBlock(status("ready"), true, full), Strings.common.lockedInDuel)
	end)

	-- Buy results --------------------------------------------------------------------------------------------------

	t.test("buyOutcome: success (an owned squishy is bought again as a copy) and the save-pending flag", function()
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
		-- Pens3 phase 5: no "already owned" answer any more (reason.shop.owned is gone).
		expect.equal((Strings.reason.shop :: any).owned, nil)
		local full = ShopFormat.buyOutcome({ ok = false, v = 1, reason = "inventory.full", charged = false })
		expect.equal(full.kind, "failed")
		expect.equal(full.text, Strings.reasonText("inventory.full") .. " " .. Strings.common.noCoinsSpent)
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

	t.test("bundles stay off while Grip is on with allowCoinBundles false (G-E)", function()
		expect.equal(ShopFormat.bundlesAllowed({ enabled = true, allowCoinBundles = false }), false)
		expect.equal(ShopFormat.bundlesAllowed({ enabled = true, allowCoinBundles = true }), true)
		expect.equal(ShopFormat.bundlesAllowed({ enabled = false, allowCoinBundles = false }), true)
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
	-- UI FINAL R6 layout (the Shop window, plan work/ui/PLAN.md R6; `H:n` = "Squishy Duels HUD.dc.html" line n) -----

	local InventoryFormat = t.requireClient("UI/InventoryFormat")
	local Theme = t.requireClient("UI/Theme")
	local TOUCH = Config.UI.Touch
	local SHOP = Config.UI.Shop
	local EPS = 1e-6
	local CARD_WIDTH = 300 -- shop fix: a card's narrowest width (rowMinWidth), two in the design's 652 px column
	-- SD_Modal's safe areas (actual px): desktops under Roblox's top bar, a laptop, phones landscape and portrait.
	local SCREENS = {
		{ label = "1280x662", size = Vector2.new(1280, 662) },
		{ label = "1920x1022", size = Vector2.new(1920, 1022) },
		{ label = "1024x710", size = Vector2.new(1024, 710) },
		{ label = "844x311", size = Vector2.new(844, 311) },
		{ label = "667x375", size = Vector2.new(667, 375) },
		{ label = "390x790", size = Vector2.new(390, 790) },
	}
	-- The band's room on a desktop window (R3: the 5 px border, the 98 px band, the body's 20).
	local DESIGN_TOP = 5 + 98 + 20

	t.test("PANEL: the body's padding and gap (H:294), the card grid's gap (H:330), the list's chrome", function()
		expect.equal(ShopFormat.PANEL.padding, 20)
		expect.equal(ShopFormat.PANEL.columnGap, 20)
		expect.equal(ShopFormat.PANEL.cellPad, 12)
		expect.equal(ShopFormat.PANEL.gridChrome, 4 + Theme.SCROLLBAR_PX + 4)
		expect.equal(ShopFormat.PANEL.gap, Theme.Padding.small)
		expect.deepEqual(SHOP.body, { featuredWidth = 330, gap = 20, padTop = 20, padSide = 24, padBottom = 24 })
	end)

	t.test("panelLayout on a desktop: the design's body (H:294), 330 | 652, 498 high, 2 columns of cards", function()
		local l = ShopFormat.panelLayout(Vector2.new(1280, 662), false, DESIGN_TOP, CARD_WIDTH)
		expect.equal(l.class, "regular")
		expect.equal(l.panelWidth, 1060)
		expect.equal(l.panelHeight, 650)
		expect.equal(l.inset, 9) -- 24 inside the 5 px border, over the window's 20
		expect.equal(l.bodyWidth, 1060 - 2 * 5 - 2 * 24)
		expect.equal(l.bodyHeight, 650 - 2 * 5 - 98 - 20 - 24)
		expect.equal(l.bodyTop, 0)
		expect.equal(l.tabsShown, false) -- desktops have no tab chips (L1 / R1 jump between the sections)
		expect.equal(l.featuredShown, true)
		expect.equal(l.listShown, true)
		expect.equal(l.featuredWidth, 330)
		expect.equal(l.featuredHeight, l.bodyHeight + SHOP.featured.lip)
		expect.equal(l.listLeft, 350)
		expect.equal(l.listWidth, 652)
		expect.equal(l.columns, 2) -- H:339: repeat(2, 1fr)
		expect.equal(l.cellWidth, (652 - ShopFormat.PANEL.gridChrome - 12) // 2) -- 1fr less the scroll bar
		expect.equal(ShopFormat.panelLayout(Vector2.new(1280, 662), false, DESIGN_TOP, 100).columns, 2) -- at most 2
		local one = ShopFormat.panelLayout(Vector2.new(1280, 662), false, DESIGN_TOP, 400)
		expect.equal(one.columns, 1) -- a long name word: one column across the list
		expect.equal(one.cellWidth, 652 - ShopFormat.PANEL.gridChrome)
		expect.truthy(l.gridWidth <= l.listWidth + EPS)
		expect.equal(l.listTop, 0)
		expect.equal(l.listHeight, l.bodyHeight)
		local filtered = ShopFormat.panelLayout(Vector2.new(1280, 662), true, DESIGN_TOP, CARD_WIDTH)
		expect.equal(filtered.listTop, filtered.chipHeight + ShopFormat.PANEL.gap)
		expect.equal(filtered.listHeight, filtered.bodyHeight - filtered.listTop)
		expect.equal(filtered.featuredHeight, l.featuredHeight) -- the filter row sits over the list only
	end)

	for _, screen in SCREENS do
		t.test(`panelLayout {screen.label}: the body fits the window, the chips are touch-sized`, function()
			for _, filtered in { false, true } do
				for _, detailOpen in { false, true } do
					for _, tabs in { false, true } do
						local l =
							ShopFormat.panelLayout(screen.size, filtered, DESIGN_TOP, CARD_WIDTH, detailOpen, tabs)
						expect.truthy(l.panelWidth * l.scale <= screen.size.X + EPS)
						expect.truthy(l.panelHeight * l.scale <= screen.size.Y + EPS)
						expect.truthy(l.chipHeight * l.scale >= TOUCH.minTargetFloor - EPS)
						expect.truthy(l.closeHeight * l.scale >= TOUCH.minTargetFloor - EPS)
						expect.near(l.bodyWidth + 2 * l.inset, l.contentWidth)
						expect.truthy(l.bodyTop + l.bodyHeight <= l.contentHeight + EPS)
						expect.truthy(l.featuredShown or l.listShown)
						if l.class == "compact" then
							-- A phone: one of the two at a time, across the body; the tab chips over the list only.
							expect.equal(l.featuredShown, detailOpen)
							expect.equal(l.listShown, not detailOpen)
							expect.equal(l.featuredWidth, l.bodyWidth)
							expect.equal(l.listLeft, 0)
							expect.equal(l.listWidth, l.bodyWidth)
							expect.equal(l.tabsShown, tabs and not detailOpen)
						else
							expect.equal(l.featuredShown and l.listShown, true)
							expect.equal(l.tabsShown, false)
							expect.near(l.featuredWidth + ShopFormat.PANEL.columnGap + l.listWidth, l.bodyWidth)
						end
						expect.equal(l.bodyTop, if l.tabsShown then l.chipHeight + ShopFormat.PANEL.gap else 0)
						local fit = InventoryFormat.gridFit(
							l.listWidth,
							CARD_WIDTH,
							ShopFormat.PANEL.cellPad,
							ShopFormat.PANEL.gridChrome
						)
						expect.equal(l.columns, math.min(fit.columns, SHOP.rows.columns))
						expect.equal(
							l.cellWidth,
							(l.listWidth - ShopFormat.PANEL.gridChrome - (l.columns - 1) * ShopFormat.PANEL.cellPad)
								// l.columns
						)
						expect.near(l.gridWidth, fit.width)
						expect.equal(l.listTop, if filtered then l.chipHeight + ShopFormat.PANEL.gap else 0)
					end
				end
			end
			-- No card width: no columns (the plain list width); a bad padding means the body's 20.
			expect.equal(ShopFormat.panelLayout(screen.size, false, DESIGN_TOP).columns, 0)
			expect.deepEqual(
				ShopFormat.panelLayout(screen.size, false, 0 / 0),
				ShopFormat.panelLayout(screen.size, false)
			)
			expect.equal(ShopFormat.panelLayout(screen.size, false, -3).topPadding, ShopFormat.PANEL.padding)
		end)
	end

	t.test(
		"featuredLayout: the text block at the bottom (H:307), the art 230 over it, hidden when it has no room",
		function()
			local f = SHOP.featured
			local text = 44 + f.text.gap + 20 + f.text.gap + f.buy.marginTop + f.buy.face + f.text.padBottom
			local tall = ShopFormat.featuredLayout(498 + f.lip, 44, 20)
			expect.equal(tall.textHeight, text)
			expect.equal(tall.artArea, 498 - 2 * f.border - text)
			expect.equal(tall.artPx, f.art.px) -- H:305: 230 when the area allows
			expect.equal(tall.textTop, f.border + tall.artArea)
			local mid = ShopFormat.featuredLayout(2 * f.border + text + 120 + f.lip, 44, 20)
			expect.equal(mid.artPx, 120) -- as big as the area
			local short = ShopFormat.featuredLayout(2 * f.border + text + f.art.minPx - 1 + f.lip, 44, 20)
			expect.equal(short.artPx, 0) -- under minPx: hidden, the name, line and BUY stay
			expect.equal(ShopFormat.featuredLayout(10, 44, 20).artArea, 0)
			expect.equal(ShopFormat.featuredLayout(0 / 0, 44, 20).artPx, 0)
		end
	)

	t.test("featuredLine: '{Rarity} · x{power} power' (H:309, FD4)", function()
		expect.equal(ShopFormat.featuredLine("Common", 16), "Common · x16 power")
		expect.equal(ShopFormat.featuredLine("Epic", 400), `{Strings.rarity.epic.name} · x400 power`)
		expect.equal(ShopFormat.featuredLine("Mystery", 2), "Mystery · x2 power") -- unknown: the raw name
	end)

	t.test("featuredView: OWNED, not sold, the spinner, disabled with a reason, the off BUY and BUY", function()
		local function entry(fields: { [string]: any }): any
			local e = { id = "toast", price = 10000, owned = false, missing = 0, state = "buy" }
			for key, value in fields do
				e[key] = value
			end
			return e
		end
		-- Pens3 phase 5: OWNED only for the free starter (owned, not sold); an owned squishy that is sold shows BUY
		-- (a copy).
		local starter: any = entry({ owned = true })
		starter.price = nil
		expect.deepEqual(ShopFormat.featuredView(starter, "x", "toast"), {
			mode = "owned",
			priceText = nil,
			reason = nil,
		})
		expect.deepEqual(ShopFormat.featuredView(entry({ owned = true }), nil, nil), {
			mode = "buy",
			priceText = "10,000",
			reason = nil,
		})
		local free: any = entry({})
		free.price = nil
		expect.deepEqual(ShopFormat.featuredView(free, nil, nil), {
			mode = "notSold",
			priceText = nil,
			reason = Strings.reason.shop.notForSale,
		})
		expect.equal(ShopFormat.featuredView(entry({}), Strings.common.lockedInDuel, "toast").mode, "loading")
		expect.deepEqual(ShopFormat.featuredView(entry({}), Strings.common.lockedInDuel, nil), {
			mode = "blocked",
			priceText = "10,000",
			reason = Strings.common.lockedInDuel,
		})
		expect.deepEqual(ShopFormat.featuredView(entry({ missing = 500 }), nil, nil), {
			mode = "short",
			priceText = "10,000",
			reason = nil,
		})
		expect.deepEqual(ShopFormat.featuredView(entry({}), nil, "banana"), {
			mode = "buy",
			priceText = "10,000",
			reason = nil,
		})
		expect.equal(ShopFormat.featuredView(nil, nil, nil).mode, "notSold")
	end)

	t.test("sections / nextTab: COINS only with a bundle (G6.6); L1 / R1 jump between the drawn sections", function()
		expect.deepEqual(ShopFormat.sections(false), { "squishies" })
		expect.deepEqual(ShopFormat.sections(true), { "squishies", "coins" })
		local one = ShopFormat.sections(false)
		expect.equal(ShopFormat.nextTab("squishies", 1, one), "squishies")
		expect.equal(ShopFormat.nextTab("squishies", -1, one), "squishies")
		expect.equal(ShopFormat.nextTab("coins", 1, one), "squishies") -- a hidden section starts from the first
		local two = ShopFormat.sections(true)
		expect.equal(ShopFormat.nextTab("squishies", 1, two), "coins")
		expect.equal(ShopFormat.nextTab("coins", 1, two), "squishies")
		expect.equal(ShopFormat.nextTab("squishies", -1, two), "coins")
		expect.equal(ShopFormat.nextTab("squishies", 1, {}), "squishies")
	end)

	-- Foam UI restyle (2026-10-09) ------------------------------------------------------------------------------------

	t.test("priceNumber: a bare price beside the coin", function()
		expect.equal(ShopFormat.priceNumber(25000), "25,000")
		expect.equal(ShopFormat.priceNumber(1200.9), "1,200")
		expect.equal(ShopFormat.priceNumber(nil), nil)
	end)

	-- Shop fix (2026-10-22): the squishy cards as the design's GAME PASSES cards (H:341-349) ---------------------

	t.test("rows: the design's card numbers (H:339-348)", function()
		local rows = Config.UI.Shop.rows
		expect.equal(rows.columns, 2)
		expect.equal(rows.height, 104)
		expect.deepEqual(
			{ rows.border, rows.padTop, rows.padRight, rows.padBottom, rows.padLeft, rows.gap, rows.textGap },
			{ 4, 10, 12, 10, 10, 12, 4 }
		)
		expect.equal(rows.tile.px, 76)
		expect.equal(rows.art.px, 84)
		local chip = rows.chip
		expect.deepEqual({ chip.height, chip.padLeft, chip.padRight, chip.coinPx }, { 38, 6, 10, 22 })
		expect.equal(rows.checkPx, 44)
	end)

	t.test("chipWidth / rowMinWidth / rowTextWidth: the tile, the text column and the chip share the card", function()
		-- H:347: border 3 + padding 6 + the coin 22 + gap 5 + the price + padding 10 + border 3.
		expect.equal(ShopFormat.chipWidth(50), 3 + 6 + 22 + 5 + 50 + 10 + 3)
		expect.equal(ShopFormat.chipWidth(-4), ShopFormat.chipWidth(0))
		-- H:341: border 4 + padding 10, the tile 76, gap 12, the text, gap 12, the chip, padding 12 + border 4.
		local fixed = 4 + 10 + 76 + 12 + 12 + 12 + 4
		expect.equal(ShopFormat.rowMinWidth(80, 100), fixed + 100 + 80)
		expect.equal(ShopFormat.rowTextWidth(fixed + 100 + 80, 100), 80)
		expect.equal(ShopFormat.rowTextWidth(310, 99), 310 - fixed - 99)
		expect.equal(ShopFormat.rowTextWidth(10, 99), 1) -- never under 1
	end)

	t.test("rowHeight: 104 (H:341) unless the name and the line need more", function()
		expect.equal(ShopFormat.rowHeight(26, 40), 104)
		expect.equal(ShopFormat.rowHeight(0, 0), 104)
		-- Two name lines (2 x 27) + gap 4 + two lines (2 x 20) = 98 inside the border and padding (8 + 20).
		expect.equal(ShopFormat.rowHeight(54, 40), 8 + 20 + 54 + 4 + 40)
		expect.equal(ShopFormat.rowHeight(54.2, 40), 8 + 20 + 99) -- rounded up
	end)

	-- UI FINAL R3 (plan R3): the panel is the Shop window, the design's 1060 x 650 face on a desktop (H:289), its top
	-- 310 above the middle (the frame with its 10 px lip 20 below it), its chrome at full size.
	t.test("UI FINAL R3: panelLayout is the Shop window (H:289): its design size and chrome on desktops", function()
		for _, size in { Vector2.new(1280, 662), Vector2.new(1920, 1022) } do
			for _, filtered in { false, true } do
				local l = ShopFormat.panelLayout(size, filtered)
				expect.equal(l.panelWidth, 1060)
				expect.equal(l.panelHeight, 650)
				expect.equal(l.chromeScale, 1)
				expect.equal(l.shift, 20)
				expect.equal(l.above, 62)
			end
		end
	end)

	-- The shop = Diego's design (2026-10-22): the window keeps the design's size and shrinks evenly to the screen.
	t.test("windowFit: the design's 1060 x 650, whole on a big screen, evenly smaller on a phone", function()
		local design = Config.UI.Sticker.window.kinds.shop
		local big = ShopFormat.windowFit(Vector2.new(2560, 1440))
		expect.equal(big.width, design.width)
		expect.equal(big.height, design.height)
		expect.equal(big.k, 1)
		expect.equal(big.shift, design.height / 2 + design.marginTop)
		local phone = ShopFormat.windowFit(Vector2.new(844, 390))
		expect.equal(phone.width, design.width) -- never re-laid out: the same window, scaled
		expect.truthy(phone.k > 0 and phone.k < 1)
		expect.equal(phone.shift, (design.height / 2 + design.marginTop) * phone.k)
	end)
end
