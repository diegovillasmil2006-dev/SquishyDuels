--!strict
-- ShopFormat (client only, pure). DESIGN §11.6 (Shop screen), §6.6 (direct shop), §6.10 (the restricted "Shop squishies
-- directly" shortcut), §6.11 (Robux: coin bundles off until real ids; no passes), §11.3 (states), §11.5 (spend
-- confirm), §2.10 / §11.3 ("No Coins were spent" only when charged = false), §3.11 (spends blocked while savePending).
-- What ShopController shows, as plain data (no instances, no services beyond the shared modules):
--   TABS / params(raw) / nextTab(tab, dir)  "squishies" | "coins"; open params {tab?, squishyId?, boxId?} cleaned up
--   cardState(price, owned, coins, buying)  owned (the free starter) / notSold / purchasing / needCoins / buy, and the
--                                           missing Coins
--   entries(defs, owned, coins, buying, onlyIds?)  one entry per Catalog squishy (only the box's items when a box
--                                           filter is on), sorted: rarity, then price, then name (before); pens3
--                                           phase 5: the price is Pricing.shopPrice(id, owned) (the Welcome price of a
--                                           Common not owned yet, with its shop.welcomePrice line `welcomeText`; no
--                                           timer, it never runs out), and an owned squishy is bought again as a copy
--   boxItemIds(boxId)                       the set of squishy ids in a box (Boxes.get(boxId).items), nil if unknown
--   keepSelection(selected, entries)        the selection while it is still listed, else the first entry
--   spendBlock(dataStatus, locked, pen?)    the reason text that disables Buy (duel lock, data not ready, save pending,
--                                           pens3 phase 5: the Toy Box full)
--   buyOutcome(result)                      what one ShopBuy Result means for the screen (success / failed)
--   requestIdFor(pending, id, price, newId) the request id of a buy press: a retry of the same buy after an answer
--                                           that never reached the server reuses it (§3.4 idempotency)
--   bundlesAllowed(gripCfg) / robuxText(p) / coinsView(offered, bundles, prices, allowed)  the Coins tab
-- Foam UI restyle (spec 2026-10-09: fewer words):
--   priceNumber(price)                      the price as a bare number ("1,200") beside the coin icon
-- Shop fix (2026-10-22: the squishies as the design's GAME PASSES cards, H:339-349; Config.UI.Shop.rows):
--   chipWidth(textWidth) / rowMinWidth(wordWidth, chipWidth) / rowTextWidth(cellWidth, chipWidth) /
--   rowHeight(nameHeight, descHeight)       a card's price chip, its narrowest width (the longest name word beside
--                                           the tile and the chip), its text column and its height (104, taller only
--                                           when the name and the line need it)
-- UI FINAL R6 (the Shop window = Diego's design, plan work/ui/PLAN.md R6; `H:n` = "Squishy Duels HUD.dc.html" line
-- n; Config.UI.Shop), all base px:
--   PANEL / panelLayout(screen, filtered, top?, cardWidth?, detailOpen?, tabs?)   the Shop window (H:289, R3) and
--                                           its body (H:294: 330 | 1fr, gap 20, padding 20 / 24 / 24 inside the 5 px
--                                           border): the featured card on the left, the right column (the box filter
--                                           row, then the scrolling list of sections) with the card grid's columns
--                                           (InventoryFormat.gridFit, at most rows.columns) and their cellWidth
--                                           (the shop fix: the columns fill the list, H:339 1fr). Desktops have no
--                                           tab chips (L1 / R1 jump between the sections, nextTab); a phone (the
--                                           compact class) shows one of the two at a time (the plan's separate
--                                           detail state: `detailOpen`), with the tab chips over the list while there
--                                           are sections to switch
--   sections(coinsShown) / nextTab(tab, dir, sections?)   the sections drawn (COINS only while a bundle is offered,
--                                           G6.6) and the L1 / R1 jump between them
--   featuredLayout(height, nameHeight, lineHeight)   the featured card (H:295-312): the art area over the text block
--                                           and the art's size (230, smaller when the area is, hidden under minPx)
--   featuredLine(rarity, power) / featuredView(entry, block, buying)   the line under the name (H:309, FD4) and what
--                                           the featured card's button shows: BUY with the price, the "off" BUY
--                                           when the Coins are short (P11), BUY disabled with a reason, the
--                                           spinner while buying, or OWNED (H:311; the free starter only)
-- Readings (DESIGN is silent):
-- * Sort: rarity ascending (Common first), then shop price ascending (not sold last), then name: the cheapest way in
--   first. The Squishies screen sorts rarity descending; the shop is a price list.
-- * Card priority: owned (not sold) > not sold > purchasing > need Coins > buy (a not-sold squishy you own reads
--   "Owned"; pens3 phase 5: a sold one you own is bought again as a copy).
-- * Buy is disabled while the duel lock holds (common.lockedInDuel), while the profile loads (common.loading), is
--   OFFLINE / READONLY (reason.data.offline / readOnly: §11.3 "purchases disabled"), or a save is pending
--   (reason.box.saving, §3.11; the server refuses the same with box.saving), or (pens3 phase 5) the Toy Box is full
--   (reason.inventory.full, PenMath.room 0; no pen state yet = not known, the server decides).
-- * A ShopBuy Result with ok = false and no `charged` never reached the server's decision (a local refusal, a
--   timeout or a lost reply), so the next press of the same buy at the same price reuses its request id: if the first
--   one did go through, the server replays its stored result instead of charging twice. Every server refusal carries
--   charged = false and gets a fresh id next time.
-- * The Coins tab lists only bundles the server offers (StateDelta.monetization.bundles) that have a productId in
--   Config and are on sale; it shows only shop.coinsUnavailable while none are left, and also whenever Grip is on with
--   allowCoinBundles false (G-E / G7b, fail closed on the client too; lobby spec 2026-10-11 §11, was
--   allowBundlesWithTrainer, then allowBundlesWithCapsules). No passes tab or line, ever, in v1.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local PenMath = require(Shared.PenMath)
local Pricing = require(Shared.Pricing)
local Rarity = require(Shared.Rarity)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local InventoryFormat = require(script.Parent.InventoryFormat)
local Layout = require(script.Parent.Layout)
local NotifyFormat = require(script.Parent.NotifyFormat)

-- Types

export type Tab = string -- "squishies" | "coins" (a plain string: checked against TABS)

export type Params = { tab: Tab, squishyId: string?, boxId: string? }

export type CardState = "owned" | "buy" | "needCoins" | "purchasing" | "notSold"

export type Entry = {
	id: string,
	def: Types.SquishyDef,
	name: string,
	rarity: Types.Rarity,
	price: number?, -- Pricing.shopPrice(id, owned) (pens3 phase 5: the Welcome price first); nil = not sold
	owned: boolean,
	state: CardState,
	missing: number, -- Coins still missing (needCoins only; else 0)
	welcomeText: string?, -- pens3 phase 5: shop.welcomePrice while the Welcome price applies (D1:202)
}

export type OutcomeKind = "success" | "failed"

export type Outcome = {
	kind: OutcomeKind,
	squishyId: string?, -- from the server's data (success)
	savePending: boolean, -- success, but the awaited save failed (box.saving)
	text: string?, -- the toast text of a failed outcome
	retry: boolean, -- failed without reaching the server's decision: keep the request id for the next press
}

export type Pending = { squishyId: string, price: number, requestId: string }

export type PriceState = { status: string, price: number? } -- status "loading" | "ok" | "failed"

export type BundleConfig = { key: string, nameKey: string, productId: number?, coins: number, onSale: boolean }

export type BundleRow = {
	key: string,
	name: string,
	coinsText: string,
	productId: number,
	priceText: string,
	priceReady: boolean, -- the Robux price is known (Buy enabled)
}

export type CoinsView = { unavailable: boolean, text: string?, rows: { BundleRow } }

-- The Shop window in base px (panelLayout). UI FINAL R6: every body position is inside the window's content box
-- (its UIPadding: the band's room on top, PANEL.padding on the sides and the bottom).
export type PanelLayout = {
	scale: number,
	class: string, -- "compact" | "regular"
	panelWidth: number,
	panelHeight: number,
	topPadding: number, -- the window's top padding (its band, Theme.fitWindow)
	contentWidth: number,
	contentHeight: number,
	closeHeight: number, -- the close X's hit box (touch-sized)
	chipHeight: number, -- the tab chips, the box filter chips and the phone's Back chip
	inset: number, -- the body's extra room on the sides and at the bottom (H:294: 24 inside the 5 px border)
	bodyWidth: number,
	tabsShown: boolean, -- the phone's tab chips over the list
	bodyTop: number, -- the featured card and the right column, under the tab chips
	bodyHeight: number,
	featuredShown: boolean,
	featuredWidth: number,
	featuredHeight: number, -- its face and lip (the lip hangs into the bottom padding, H:295 box-shadow)
	listShown: boolean,
	listLeft: number, -- the right column
	listWidth: number,
	listTop: number, -- the list under the box filter row (0 without a filter), inside the right column
	listHeight: number,
	gridWidth: number, -- the card grid inside the list: as wide as its columns (InventoryFormat.gridFit)
	columns: number, -- 0 when panelLayout was given no card width
	cellWidth: number, -- shop fix: a card's width (the columns fill the list less its chrome); 0 without columns
	-- UI FINAL R3: the Shop window's chrome scale, centre offset and what hangs above it (Layout.windowFit).
	chromeScale: number,
	shift: number,
	above: number,
}

-- UI FINAL R6: the featured card's parts (featuredLayout), base px from the card's top.
export type FeaturedLayout = { artArea: number, artPx: number, textTop: number, textHeight: number }

-- UI FINAL R6: what the featured card's button shows (featuredView): "buy" (BUY, the coin and the price), "short"
-- (the same, "off": the Coins do not cover it, P11), "blocked" (disabled with `reason`), "loading" (the spinner),
-- "owned" (the lilac OWNED bar, H:311), "notSold" (disabled with the not-for-sale reason).
export type FeaturedMode = "buy" | "short" | "blocked" | "loading" | "owned" | "notSold"
export type FeaturedView = { mode: FeaturedMode, priceText: string?, reason: string? }

-- Constants

local TAB_SQUISHIES = "squishies"
local TAB_COINS = "coins"
local TABS: { Tab } = { TAB_SQUISHIES, TAB_COINS }
local UNKNOWN_RANK = math.huge
local TOUCH = Config.UI.Touch
local SHOP = Config.UI.Shop
local BODY = SHOP.body
local ROWS = SHOP.rows
local WINDOW_BORDER = Config.UI.Sticker.border.heavy -- H:290: the window's 5 px border, drawn inside its box
-- The window (base px). Readings: the Squishies screen's margin and height share (unused by a fitted window, kept for
-- Layout.modalPanel). UI FINAL R6: padding = the body's top padding (H:294: 20; the band sits above it, R3), gap = the
-- chip rows' gap (Theme.Padding.small), columnGap = the 330 | 1fr gap (H:294), cellPad = the card grid's gap (H:330),
-- gridChrome = the list's padding 4 + Theme.scrollbar's 12 + 4.
local PANEL = {
	margin = 24,
	heightShare = 0.88,
	padding = BODY.padTop,
	gap = 6,
	columnGap = BODY.gap,
	tabGap = 6,
	cellPad = SHOP.sections.cellGap,
	gridChrome = 4 + Config.UI.Sticker.window.scrollbarPx + 4,
}

-- Module table

local ShopFormat = {}

ShopFormat.TABS = TABS
ShopFormat.TAB_SQUISHIES = TAB_SQUISHIES
ShopFormat.TAB_COINS = TAB_COINS
ShopFormat.PANEL = PANEL

-- Private

local function wholeCoins(value: unknown): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function nameOf(def: Types.SquishyDef): string
	return Strings.resolve(def.nameKey) or def.id
end

local function rarityRank(rarity: unknown): number
	return Rarity.index(rarity) or UNKNOWN_RANK
end

-- Public: tabs and params ------------------------------------------------------------------------------------------

-- The open params with defaults: {tab = "coins"} opens the Coins tab (the HUD coin pill); a squishyId (Squishies
-- screen "View in Shop") or a boxId (the box counter's "Shop Squishies" while the box check is unknown; pens3 phase 5:
-- restricted accounts open the boxes in a fixed order instead) opens the Squishies tab. Unknown or
-- malformed values are dropped.
function ShopFormat.params(raw: unknown): Params
	local result: Params = { tab = TAB_SQUISHIES }
	if type(raw) ~= "table" then
		return result
	end
	local p = raw :: { [string]: any }
	if type(p.squishyId) == "string" and p.squishyId ~= "" then
		result.squishyId = p.squishyId
	end
	if type(p.boxId) == "string" and Boxes.get(p.boxId) ~= nil then
		result.boxId = p.boxId
	end
	if p.tab == TAB_COINS and result.squishyId == nil and result.boxId == nil then
		result.tab = TAB_COINS
	end
	return result
end

-- L1 / R1 (§11.4): the tab `direction` steps away, wrapping around. UI FINAL R6: among `sections` (the ones drawn,
-- default TABS), so with COINS hidden it stays on SQUISHIES; a tab that is not drawn starts from the first.
function ShopFormat.nextTab(tab: Tab, direction: number, sections: { Tab }?): Tab
	local list = sections or TABS
	if #list == 0 then
		return TAB_SQUISHIES
	end
	local index = table.find(list, tab) or 1
	local step = if direction < 0 then -1 else 1
	return list[(index - 1 + step) % #list + 1]
end

-- UI FINAL R6 (G6.6, H:314-342): the sections the right column draws, in order: SQUISHIES, then COINS only while a
-- coin bundle is offered (its heading and note are not drawn otherwise).
function ShopFormat.sections(coinsShown: boolean): { Tab }
	return if coinsShown then { TAB_SQUISHIES, TAB_COINS } else { TAB_SQUISHIES }
end

-- Public: cards ------------------------------------------------------------------------------------------------------

-- A card's state and the Coins still missing (0 unless needCoins). `buying` = a ShopBuy for this squishy is running.
-- Pens3 phase 5: owning a squishy that is sold does not stop a buy (a copy); "owned" is the not-sold starter's.
function ShopFormat.cardState(price: number?, owned: boolean, coins: number, buying: boolean): (CardState, number)
	if price == nil then
		return (if owned then "owned" else "notSold"), 0
	end
	if buying then
		return "purchasing", 0
	end
	local missing = math.max(0, wholeCoins(price) - wholeCoins(coins))
	if missing > 0 then
		return "needCoins", missing
	end
	return "buy", 0
end

-- The shop's order: rarity ascending, then price ascending (not sold last), then name, then id.
function ShopFormat.before(a: Entry, b: Entry): boolean
	local ra, rb = rarityRank(a.rarity), rarityRank(b.rarity)
	if ra ~= rb then
		return ra < rb
	end
	local pa = a.price or math.huge
	local pb = b.price or math.huge
	if pa ~= pb then
		return pa < pb
	end
	if a.name ~= b.name then
		return a.name < b.name
	end
	return a.id < b.id
end

-- One entry per squishy in `defs` (Catalog.list()), only those in `onlyIds` when given (a box filter), sorted.
-- `owned` = the owned map; `buying` = the id a ShopBuy is running for.
function ShopFormat.entries(
	defs: { Types.SquishyDef },
	owned: { [string]: any },
	coins: number,
	buying: string?,
	onlyIds: { [string]: boolean }?
): { Entry }
	local list: { Entry } = {}
	for _, def in defs do
		if onlyIds == nil or onlyIds[def.id] == true then
			local isOwned = owned[def.id] ~= nil
			local price = Pricing.shopPrice(def.id, owned)
			local state, missing = ShopFormat.cardState(price, isOwned, coins, buying == def.id)
			local cardState: CardState = state :: CardState -- (cast: a multi-value return widens its literals)
			local welcome = price ~= nil and def.shopPrice ~= nil and price < def.shopPrice
			table.insert(list, {
				id = def.id,
				def = def,
				name = nameOf(def),
				rarity = def.rarity,
				price = price,
				owned = isOwned,
				state = cardState,
				missing = missing,
				welcomeText = if welcome
					then Strings.format(Strings.shop.welcomePrice, { coins = Format.coins(price :: number) })
					else nil,
			})
		end
	end
	table.sort(list, ShopFormat.before)
	return list
end

-- The ids of a box's items (Boxes.get(boxId).items), or nil for an unknown box.
function ShopFormat.boxItemIds(boxId: string?): { [string]: boolean }?
	local box = if boxId then Boxes.get(boxId) else nil
	if box == nil then
		return nil
	end
	local ids: { [string]: boolean } = {}
	for _, item in box.items do
		ids[item.id] = true
	end
	return ids
end

-- The selection while it is still listed, else the first entry (nil for an empty list).
function ShopFormat.keepSelection(selected: string?, list: { Entry }): string?
	for _, entry in list do
		if entry.id == selected then
			return selected
		end
	end
	local first = list[1]
	return if first then first.id else nil
end

-- The price as a bare number ("1,200", Format.coins), shown beside the coin icon; nil for a squishy that is not sold.
function ShopFormat.priceNumber(price: number?): string?
	if price == nil then
		return nil
	end
	return Format.coins(wholeCoins(price))
end

-- Shop fix: the squishy cards as the design's GAME PASSES cards (H:341-349; Config.UI.Shop.rows), base px ----------

-- The price chip's width around a price `textWidth` wide (H:347: padding 0 10 0 6, border 3, the coin 22, gap 5).
function ShopFormat.chipWidth(textWidth: number): number
	local chip = ROWS.chip
	return 2 * chip.border + chip.padLeft + chip.padRight + chip.coinPx + chip.gap + math.max(0, textWidth)
end

-- What a card's row takes besides its text column and chip: the border, the padding, the tile and the two gaps.
local function rowFixed(): number
	return 2 * ROWS.border + ROWS.padLeft + ROWS.padRight + ROWS.tile.px + 2 * ROWS.gap
end

-- The narrowest card that keeps `wordWidth` (the longest name word, never split) beside the tile and a chip
-- `chipWidth` wide: the grid's columns come from it (panelLayout).
function ShopFormat.rowMinWidth(wordWidth: number, chipWidth: number): number
	return rowFixed() + math.max(0, chipWidth) + math.max(0, wordWidth)
end

-- The text column of a card `cellWidth` wide beside a chip `chipWidth` wide (H:343: flex 1).
function ShopFormat.rowTextWidth(cellWidth: number, chipWidth: number): number
	return math.max(1, cellWidth - rowFixed() - math.max(0, chipWidth))
end

-- A card's face height (H:341: 104, the lip under it): taller only when the name and the line (H:343: gap 4) need
-- more than the tile's padded height.
function ShopFormat.rowHeight(nameHeight: number, descHeight: number): number
	local text = math.max(0, nameHeight) + ROWS.textGap + math.max(0, descHeight)
	local inner = math.max(ROWS.tile.px, text)
	return math.max(ROWS.height, math.ceil(2 * ROWS.border + ROWS.padTop + ROWS.padBottom + inner))
end

-- The reason text that disables Buy, or nil when buying is allowed (the server checks everything again).
-- `status` = StateController.dataStatus(); `locked` = the duel lock (Matched through Returning); `pen` = the pen state
-- (pens3 phase 5: PenMath.room 0 = the Toy Box is full; nil = not known).
function ShopFormat.spendBlock(status: Types.DataStatus?, locked: boolean, pen: any?): string?
	if locked then
		return Strings.common.lockedInDuel
	end
	local name = if status then status.status else nil
	if name == "loading" then
		return Strings.common.loading
	elseif name == "offline" then
		return Strings.reasonText("data.offline")
	elseif name == "readonly" then
		return Strings.reasonText("data.readOnly")
	elseif status and status.savePending == true then
		return Strings.reasonText("box.saving")
	elseif pen ~= nil and PenMath.room(pen) == 0 then
		return Strings.reasonText("inventory.full")
	end
	return nil
end

-- Public: buying ------------------------------------------------------------------------------------------------------

-- What one ShopBuy Result (NetController.invokeAsync) means: success (charged; the congrats overlay; pens3 phase 5: an
-- owned squishy bought again is a copy, the server has no "already owned" answer any more) or failed (the reason; "No
-- Coins were spent." only when the server said charged = false; `retry` when the call never reached the server's
-- decision).
function ShopFormat.buyOutcome(result: { [string]: any }): Outcome
	if result.ok == true then
		local data = if type(result.data) == "table" then result.data else {}
		local squishyId = if type(data.squishyId) == "string" then data.squishyId else nil
		return {
			kind = "success",
			squishyId = squishyId,
			savePending = data.savePending == true,
			text = nil,
			retry = false,
		}
	end
	return {
		kind = "failed",
		squishyId = nil,
		savePending = false,
		text = NotifyFormat.resultText(result),
		retry = result.charged == nil,
	}
end

-- The request id for a buy press of `squishyId` at `price`: the pending one when it is the same buy (a retry), else
-- newId(). Returns the id and the pending record to keep while the call runs.
function ShopFormat.requestIdFor(
	pending: Pending?,
	squishyId: string,
	price: number,
	newId: () -> string
): (string, Pending)
	if pending and pending.squishyId == squishyId and pending.price == price then
		return pending.requestId, pending
	end
	local id = newId()
	return id, { squishyId = squishyId, price = price, requestId = id }
end

-- Public: Coins tab ----------------------------------------------------------------------------------------------------

-- False while Grip is on and coin bundles must stay off (allowCoinBundles false; G-E, G7b): the Coins tab shows only
-- shop.coinsUnavailable whatever the server offers. `gripCfg` = Config.Grip.
function ShopFormat.bundlesAllowed(gripCfg: { enabled: boolean, allowCoinBundles: boolean }?): boolean
	if gripCfg == nil then
		return true
	end
	return not (gripCfg.enabled == true and gripCfg.allowCoinBundles ~= true)
end

-- A bundle's Robux price text: "…" while loading (or unknown), "Unavailable" on failure, else "{price} Robux".
function ShopFormat.robuxText(state: PriceState?): string
	if state == nil or state.status == "loading" then
		return Strings.shop.robuxLoading
	end
	local price = state.price
	if state.status ~= "ok" or type(price) ~= "number" or price ~= price or price < 0 then
		return Strings.shop.robuxUnavailable
	end
	return Strings.format(Strings.shop.robuxPrice, { price = Format.coins(price) })
end

-- The Coins tab: the offered bundles (server keys) that have a productId and are on sale, in Config order, with their
-- amount and Robux price text; or only shop.coinsUnavailable when none is left or bundles are not allowed.
function ShopFormat.coinsView(
	offered: { string }?,
	bundles: { BundleConfig },
	prices: { [string]: PriceState },
	allowed: boolean
): CoinsView
	local rows: { BundleRow } = {}
	if allowed and type(offered) == "table" then
		for _, bundle in bundles do
			local productId = bundle.productId
			if productId ~= nil and bundle.onSale and table.find(offered, bundle.key) ~= nil then
				local price = prices[bundle.key]
				table.insert(rows, {
					key = bundle.key,
					name = Strings.resolve(bundle.nameKey) or bundle.key,
					coinsText = Strings.format(Strings.common.coinsAmount, { coins = Format.coins(bundle.coins) }),
					productId = productId,
					priceText = ShopFormat.robuxText(price),
					priceReady = price ~= nil and price.status == "ok",
				})
			end
		end
	end
	if #rows == 0 then
		return { unavailable = true, text = Strings.shop.coinsUnavailable, rows = {} }
	end
	return { unavailable = false, text = nil, rows = rows }
end

-- UI FINAL R6 layout (the Shop window, H:289-342) ------------------------------------------------------------------

-- The Shop window for a ScreenGui of `screenPx` actual px (R3: the design's 1060 x 650, shrunk to fit,
-- Layout.windowFit) and its body (H:294): inside the window's content box (its top padding `topPadding` = the band's
-- room, Theme.fitWindow; default PANEL.padding) the body takes `inset` more on the sides and at the bottom (the
-- design's 24 inside the 5 px border, over the window's 20), then the featured card (330, the body's height and its
-- lip) and, `columnGap` to its right, the right column: the box filter row while `filtered`, then the list. With
-- `cardWidth` (shop fix: a card's narrowest width, rowMinWidth) the card grid takes the columns that fit in the list
-- (InventoryFormat.gridFit), at most rows.columns, each `cellWidth` wide (they fill the list). On a phone (the compact
-- class) the body shows one of the two: the list, or with `detailOpen` the featured card across the whole body (the
-- plan's separate detail state); the tab chips sit over the list while `tabs` (more than one section) is true.
function ShopFormat.panelLayout(
	screenPx: Vector2,
	filtered: boolean,
	topPadding: number?,
	cardWidth: number?,
	detailOpen: boolean?,
	tabs: boolean?
): PanelLayout
	local p = Layout.modalPanel(screenPx, PANEL.margin, PANEL.heightShare, PANEL.padding, "shop")
	local top = topPadding
	if top == nil or top ~= top or top == math.huge or top <= PANEL.padding then
		top = PANEL.padding
	end
	local contentHeight = math.max(0, p.contentHeight - ((top :: number) - PANEL.padding))
	local closeHeight = Layout.touchBase(TOUCH.closeButton, p.scale)
	local chipHeight = Layout.touchBase(TOUCH.minTarget, p.scale)
	local compact = p.class == "compact"
	local inset = BODY.padSide - BODY.padTop + WINDOW_BORDER
	local bottomInset = BODY.padBottom - BODY.padTop + WINDOW_BORDER
	local bodyWidth = math.max(0, p.contentWidth - 2 * inset)
	local featuredShown = not compact or detailOpen == true
	local listShown = not compact or detailOpen ~= true
	local tabsShown = compact and listShown and tabs == true
	local bodyTop = if tabsShown then chipHeight + PANEL.gap else 0
	local bodyHeight = math.max(0, contentHeight - bottomInset - bodyTop)
	local featuredWidth = if compact then bodyWidth else math.min(BODY.featuredWidth, bodyWidth)
	local listLeft = if compact then 0 else featuredWidth + PANEL.columnGap
	local listWidth = math.max(0, bodyWidth - listLeft)
	local listTop = if filtered then chipHeight + PANEL.gap else 0
	local gridWidth = listWidth
	local columns, cellWidth = 0, 0
	if cardWidth ~= nil and cardWidth == cardWidth and cardWidth > 0 and cardWidth < math.huge then
		local fit = InventoryFormat.gridFit(listWidth, cardWidth, PANEL.cellPad, PANEL.gridChrome)
		gridWidth, columns = fit.width, math.min(fit.columns, ROWS.columns)
		local inner = listWidth - PANEL.gridChrome - (columns - 1) * PANEL.cellPad
		cellWidth = math.max(0, math.floor(inner / columns))
	end
	return {
		scale = p.scale,
		class = p.class,
		panelWidth = p.panelWidth,
		panelHeight = p.panelHeight,
		topPadding = top :: number,
		contentWidth = p.contentWidth,
		contentHeight = contentHeight,
		closeHeight = closeHeight,
		chipHeight = chipHeight,
		inset = inset,
		bodyWidth = bodyWidth,
		tabsShown = tabsShown,
		bodyTop = bodyTop,
		bodyHeight = bodyHeight,
		featuredShown = featuredShown,
		featuredWidth = featuredWidth,
		featuredHeight = bodyHeight + SHOP.featured.lip,
		listShown = listShown,
		listLeft = listLeft,
		listWidth = listWidth,
		listTop = listTop,
		listHeight = math.max(0, bodyHeight - listTop),
		gridWidth = gridWidth,
		columns = columns,
		cellWidth = cellWidth,
		chromeScale = p.chromeScale or 1,
		shift = p.shift or 0,
		above = p.above or 0,
	}
end

-- The featured card (H:295-312) `height` base px tall (its face and lip): the text block at the bottom (H:307:
-- padding 0 16 16, gap 6: the name `nameHeight` (it may wrap), the line `lineHeight`, then BUY / OWNED's face with
-- its margin-top; the button's lip hangs into the bottom padding as the design's box-shadow does) and the art area
-- above it, inside the 4 px border (the LIMITED row is not built, UD5). The art is 230 (H:305), as big as the area
-- allows, and hidden under minPx (the name, the line and BUY stay).
function ShopFormat.featuredLayout(height: number, nameHeight: number, lineHeight: number): FeaturedLayout
	local f = SHOP.featured
	local face = math.max(0, (if height == height then height else 0) - f.lip)
	local text = math.max(0, nameHeight)
		+ f.text.gap
		+ math.max(0, lineHeight)
		+ f.text.gap
		+ f.buy.marginTop
		+ f.buy.face
		+ f.text.padBottom
	local artArea = math.max(0, face - 2 * f.border - text)
	local artPx = math.min(f.art.px, math.floor(artArea))
	if artPx < f.art.minPx then
		artPx = 0
	end
	return { artArea = artArea, artPx = artPx, textTop = f.border + artArea, textHeight = text }
end

-- The featured line (H:309; FD4: the design lists the bundle, the game the squishy): "{Rarity} · x{power} power".
-- AFFECTED 2026-10-15: the power is the pen multiplier (Catalog.getPower); the line is wired to the new income later.
function ShopFormat.featuredLine(rarity: string, power: number): string
	local names = (Strings :: any).rarity[string.lower(rarity)]
	local name = if type(names) == "table" and type(names.name) == "string" then names.name else rarity
	return Strings.format(Strings.shop.featuredLine, { rarity = name, power = power })
end

-- What the featured card's button shows for `entry` (nil: nothing selected), with `block` the spendBlock reason (or
-- another buy in flight) and `buying` the id a ShopBuy runs for. Priority: owned (not sold) > not sold > buying >
-- blocked > short > buy. Pens3 phase 5 (copies): owning a squishy that is sold no longer stops another buy; OWNED is
-- the not-sold starter's.
function ShopFormat.featuredView(entry: Entry?, block: string?, buying: string?): FeaturedView
	if entry == nil then
		return { mode = "notSold", priceText = nil, reason = nil }
	end
	local priceText = ShopFormat.priceNumber(entry.price)
	if entry.owned and entry.price == nil then
		return { mode = "owned", priceText = nil, reason = nil }
	elseif entry.price == nil then
		return { mode = "notSold", priceText = nil, reason = Strings.reasonText("shop.notForSale") }
	elseif buying == entry.id then
		return { mode = "loading", priceText = priceText, reason = nil }
	elseif block ~= nil then
		return { mode = "blocked", priceText = priceText, reason = block }
	elseif entry.missing > 0 then
		return { mode = "short", priceText = priceText, reason = nil }
	end
	return { mode = "buy", priceText = priceText, reason = nil }
end

return ShopFormat
