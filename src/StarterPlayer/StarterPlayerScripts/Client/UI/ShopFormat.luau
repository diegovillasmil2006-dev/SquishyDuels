--!strict
-- ShopFormat (client only, pure). DESIGN §11.6 (Shop screen), §6.6 (direct shop), §6.10 (the restricted "Shop squishies
-- directly" shortcut), §6.11 (Robux: coin bundles off until real ids; no passes), §11.3 (states), §11.5 (spend
-- confirm), §2.10 / §11.3 ("No Coins were spent" only when charged = false), §3.11 (spends blocked while savePending).
-- What ShopController shows, as plain data (no instances, no services beyond the shared modules):
--   TABS / params(raw) / nextTab(tab, dir)  "squishies" | "coins"; open params {tab?, squishyId?, boxId?} cleaned up
--   cardState(price, owned, coins, buying)  owned / notSold / purchasing / needCoins / buy, and the missing Coins
--   entries(defs, owned, coins, buying, onlyIds?)  one entry per Catalog squishy (only the box's items when a box
--                                           filter is on), sorted: rarity, then price, then name (before)
--   boxItemIds(boxId)                       the set of squishy ids in a box (Boxes.get(boxId).items), nil if unknown
--   keepSelection(selected, entries)        the selection while it is still listed, else the first entry
--   priceText(price) / cardStatusText(e)    "1,200 Coins"; the card's status line for each state
--   spendBlock(dataStatus, locked)          the reason text that disables Buy (duel lock, data not ready, save pending)
--   buyOutcome(result)                      what one ShopBuy Result means for the screen (success / owned / failed)
--   requestIdFor(pending, id, price, newId) the request id of a buy press: a retry of the same buy after an answer
--                                           that never reached the server reuses it (§3.4 idempotency)
--   bundlesAllowed(gripCfg) / robuxText(p) / coinsView(offered, bundles, prices, allowed)  the Coins tab
-- Part 8 layout (DESIGN §11.2, §11.6; the same fold as the Squishies screen's), all base px:
--   PANEL / panelLayout(screenPx, filtered)  the panel, header, tab and filter rows (touch-sized chips), the body and
--                                           the detail column for a ScreenGui of screenPx actual px
--   buyBox(naturalWidth, columnWidth, buttonHeight, wrappedHeight)   the Buy button's box: its natural width (the
--                                           widest text it can show) when that fits the column, else the column's
--                                           width with the label wrapped, as tall as that text needs
--   detailLayout(w, h, gap, buy?, balanceLine, inspect?)   Buy (with its "Balance after" line under it) and Inspect
--                                           pinned under the scrolling detail, wrapped in a narrow column
-- Foam UI restyle (spec 2026-10-09: fewer words):
--   priceNumber(price) / cardLine(entry)    the price as a bare number ("1,200") beside the coin icon, and a card's
--                                           status line with whether the coin shows: the price for a buyable card,
--                                           the missing Coins (with the coin) or cardStatusText's words otherwise
--   panelLayout(screenPx, filtered, topPadding?)   the panel's real top padding (its header tab's room), like
--                                           InventoryFormat.panelLayout
-- Foam fix batch (2026-10-09; on a phone the cards' prices and the detail were cut off):
--   panelLayout(screenPx, filtered, topPadding?, cardWidth?)   Close hangs on the panel's top-right corner
--                                           (InventoryFormat.hangingChrome), so the tab row starts the content (no
--                                           header row; the player's Coins sit at the tab row's right end); with the
--                                           card width the grid takes only the columns that fit in gridShare
--                                           (InventoryFormat.gridFit) and the detail column the rest
-- Foam fix round 2 (2026-10-09): detailLayout keeps PANEL.buttonGap (12, as on Squishies) between Buy and Inspect.
-- Readings (DESIGN is silent):
-- * Sort: rarity ascending (Common first), then shop price ascending (not sold last), then name: the cheapest way in
--   first. The Squishies screen sorts rarity descending; the shop is a price list.
-- * Card priority: owned > not sold > purchasing > need Coins > buy (a not-sold squishy you own reads "Owned").
-- * Buy is disabled while the duel lock holds (common.lockedInDuel), while the profile loads (common.loading), is
--   OFFLINE / READONLY (reason.data.offline / readOnly: §11.3 "purchases disabled"), or a save is pending
--   (reason.box.saving, §3.11; the server refuses the same with box.saving).
-- * A ShopBuy Result with ok = false and no `charged` never reached the server's decision (a local refusal, a
--   timeout or a lost reply), so the next press of the same buy at the same price reuses its request id: if the first
--   one did go through, the server replays its stored result instead of charging twice. Every server refusal carries
--   charged = false and gets a fresh id next time.
-- * The Coins tab lists only bundles the server offers (StateDelta.monetization.bundles) that have a productId in
--   Config and are on sale; it shows only shop.coinsUnavailable while none are left, and also whenever Grip is on with
--   allowBundlesWithCapsules false (G-E / G7b, fail closed on the client too; lobby spec 2026-10-11 §11, was
--   allowBundlesWithTrainer). No passes tab or line, ever, in v1.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
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
	price: number?, -- Catalog shopPrice; nil = not sold
	owned: boolean,
	state: CardState,
	missing: number, -- Coins still missing (needCoins only; else 0)
}

export type OutcomeKind = "success" | "owned" | "failed"

export type Outcome = {
	kind: OutcomeKind,
	squishyId: string?, -- from the server's data (success / owned)
	savePending: boolean, -- success, but the awaited save failed (box.saving)
	text: string?, -- the toast text of an owned / failed outcome
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

-- The Shop panel in base px (panelLayout).
export type PanelLayout = {
	scale: number,
	class: string, -- "compact" | "regular"
	panelWidth: number,
	panelHeight: number,
	topPadding: number, -- the panel's top padding (raised by its header tab and the hanging Close)
	contentWidth: number,
	contentHeight: number,
	closeHeight: number, -- the Close button hanging on the top-right corner (fix batch: no header row)
	chipHeight: number, -- the tab chips and the box filter chips
	bodyTop: number, -- the Squishies / Coins body under the tabs
	bodyHeight: number,
	listTop: number, -- the grid and detail under the box filter row (0 without a filter)
	gridWidth: number,
	columns: number, -- the grid's columns (InventoryFormat.gridFit); 0 when panelLayout was given no card width
	detailWidth: number,
	detailHeight: number,
}

export type Box = { w: number, h: number }

export type BuyBox = { w: number, h: number, wraps: boolean }

-- The detail column (detailLayout): the list scrolls above, Buy and Inspect are pinned under it.
export type DetailLayout = {
	rows: number,
	scrollHeight: number,
	buttonsTop: number,
	buttonsHeight: number,
	buy: Layout.Rect?, -- the Buy holder (button + "Balance after" line), relative to the button area
	inspect: Layout.Rect?,
}

-- Constants

local TAB_SQUISHIES = "squishies"
local TAB_COINS = "coins"
local TABS: { Tab } = { TAB_SQUISHIES, TAB_COINS }
local UNKNOWN_RANK = math.huge
local GRID_SHARE = (Config.UI.Inventory.gridWidthMin + Config.UI.Inventory.gridWidthMax) / 2
local TOUCH = Config.UI.Touch
-- The panel (base px). Readings: the Squishies screen's margin, height share, padding, gaps, split, tab gap and grid
-- cells (ShopFormat_Test keeps them equal to Theme's tokens and InventoryFormat.PANEL). SUB_GAP is ConfirmButton's gap
-- above "Balance after".
local PANEL = {
	margin = 24,
	heightShare = 0.88,
	padding = 12,
	gap = 6,
	columnGap = 12,
	gridShare = GRID_SHARE,
	tabGap = 6,
	cellPad = 8,
	gridChrome = 14,
	buttonGap = 12, -- fix round 2: between Buy and Inspect (and their rows), as between the Squishies detail buttons
}
local SUB_GAP = 2

-- Module table

local ShopFormat = {}

ShopFormat.TABS = TABS
ShopFormat.TAB_SQUISHIES = TAB_SQUISHIES
ShopFormat.TAB_COINS = TAB_COINS
ShopFormat.PANEL = PANEL
ShopFormat.SUB_GAP = SUB_GAP

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
-- screen "View in Shop") or a boxId (the restricted "Shop squishies directly") opens the Squishies tab. Unknown or
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

-- L1 / R1 (§11.4): the tab `direction` steps away, wrapping around.
function ShopFormat.nextTab(tab: Tab, direction: number): Tab
	local index = table.find(TABS, tab) or 1
	local step = if direction < 0 then -1 else 1
	return TABS[(index - 1 + step) % #TABS + 1]
end

-- Public: cards ------------------------------------------------------------------------------------------------------

-- A card's state and the Coins still missing (0 unless needCoins). `buying` = a ShopBuy for this squishy is running.
function ShopFormat.cardState(price: number?, owned: boolean, coins: number, buying: boolean): (CardState, number)
	if owned then
		return "owned", 0
	end
	if price == nil then
		return "notSold", 0
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
			local price = def.shopPrice
			local state, missing = ShopFormat.cardState(price, isOwned, coins, buying == def.id)
			local cardState: CardState = state :: CardState -- (cast: a multi-value return widens its literals)
			table.insert(list, {
				id = def.id,
				def = def,
				name = nameOf(def),
				rarity = def.rarity,
				price = price,
				owned = isOwned,
				state = cardState,
				missing = missing,
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

-- "1,200 Coins", or nil for a squishy that is not sold.
function ShopFormat.priceText(price: number?): string?
	if price == nil then
		return nil
	end
	return Strings.format(Strings.common.coinsAmount, { coins = Format.coins(price) })
end

-- "Need {missing} more Coins" (common.needCoins, singular for 1).
function ShopFormat.needText(missing: number): string
	local pair = Strings.common.needCoins
	return Strings.format(Strings.plural(missing, pair.one, pair.many), { missing = Format.coins(missing) })
end

-- The price as a bare number ("1,200", Format.coins), shown beside the coin icon; nil for a squishy that is not sold.
function ShopFormat.priceNumber(price: number?): string?
	if price == nil then
		return nil
	end
	return Format.coins(wholeCoins(price))
end

-- A card's status line and whether the coin icon shows beside it (foam restyle, fewer words): a buyable card shows
-- its price as a bare number with the coin, need Coins its missing amount with the coin, every other state
-- cardStatusText's words without it.
function ShopFormat.cardLine(entry: Entry): (string, boolean)
	if entry.state == "buy" then
		return ShopFormat.priceNumber(entry.price) or "", true
	end
	return ShopFormat.cardStatusText(entry), entry.state == "needCoins"
end

-- The card's status line: Owned, the price, the missing Coins, Loading… while buying, or the not-for-sale text.
function ShopFormat.cardStatusText(entry: Entry): string
	local state = entry.state
	if state == "owned" then
		return Strings.common.owned
	elseif state == "notSold" then
		return Strings.reasonText("shop.notForSale")
	elseif state == "purchasing" then
		return Strings.common.loading
	elseif state == "needCoins" then
		return ShopFormat.needText(entry.missing)
	end
	return ShopFormat.priceText(entry.price) or ""
end

-- The reason text that disables Buy, or nil when buying is allowed (the server checks everything again).
-- `status` = StateController.dataStatus(); `locked` = the duel lock (Matched through Returning).
function ShopFormat.spendBlock(status: Types.DataStatus?, locked: boolean): string?
	if locked then
		return Strings.common.lockedInDuel
	end
	if status == nil then
		return nil
	end
	local name = status.status
	if name == "loading" then
		return Strings.common.loading
	elseif name == "offline" then
		return Strings.reasonText("data.offline")
	elseif name == "readonly" then
		return Strings.reasonText("data.readOnly")
	elseif status.savePending == true then
		return Strings.reasonText("box.saving")
	end
	return nil
end

-- Public: buying ------------------------------------------------------------------------------------------------------

-- What one ShopBuy Result (NetController.invokeAsync) means: success (charged; "You got X!" and Equip now), owned (ok
-- with charged = false: nothing was spent, the card reads Owned) or failed (the reason; "No Coins were spent." only
-- when the server said charged = false; `retry` when the call never reached the server's decision).
function ShopFormat.buyOutcome(result: { [string]: any }): Outcome
	if result.ok == true then
		local data = if type(result.data) == "table" then result.data else {}
		local squishyId = if type(data.squishyId) == "string" then data.squishyId else nil
		if data.charged == false then
			return {
				kind = "owned",
				squishyId = squishyId,
				savePending = false,
				text = NotifyFormat.resultText({ reason = "shop.owned", charged = false }),
				retry = false,
			}
		end
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

-- False while Grip is on and coin bundles must stay off with the capsules (G-E, G7b): the Coins tab then shows only
-- shop.coinsUnavailable whatever the server offers. `gripCfg` = Config.Grip.
function ShopFormat.bundlesAllowed(gripCfg: { enabled: boolean, allowBundlesWithCapsules: boolean }?): boolean
	if gripCfg == nil then
		return true
	end
	return not (gripCfg.enabled == true and gripCfg.allowBundlesWithCapsules ~= true)
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

-- Part 8 layout ---------------------------------------------------------------------------------------------------------

-- The Shop panel for a ScreenGui of `screenPx` actual px: Close (hanging on the top-right corner, fix batch: no header
-- row) and the chips touch-sized; the tab row starts the content and the body sits under it; with a box filter
-- (`filtered`) the grid and detail start under the filter row. With `cardWidth` the grid takes only the columns that
-- fit in gridShare of the content width (InventoryFormat.gridFit) and the detail column the rest; without it the plain
-- gridShare split. `topPadding` is the panel's real top padding (InventoryFormat.hangingChrome's top; default
-- PANEL.padding); the bottom keeps PANEL.padding.
function ShopFormat.panelLayout(
	screenPx: Vector2,
	filtered: boolean,
	topPadding: number?,
	cardWidth: number?
): PanelLayout
	local p = Layout.modalPanel(screenPx, PANEL.margin, PANEL.heightShare, PANEL.padding)
	local top = topPadding
	if top == nil or top ~= top or top == math.huge or top <= PANEL.padding then
		top = PANEL.padding
	end
	local contentHeight = math.max(0, p.contentHeight - ((top :: number) - PANEL.padding))
	local closeHeight = Layout.touchBase(TOUCH.closeButton, p.scale)
	local chipHeight = Layout.touchBase(TOUCH.minTarget, p.scale)
	local bodyTop = chipHeight + PANEL.gap
	local bodyHeight = math.max(0, contentHeight - bodyTop)
	local listTop = if filtered then chipHeight + PANEL.gap else 0
	local gridWidth = p.contentWidth * PANEL.gridShare
	local columns = 0
	if cardWidth ~= nil and cardWidth == cardWidth and cardWidth > 0 and cardWidth < math.huge then
		local fit = InventoryFormat.gridFit(gridWidth, cardWidth, PANEL.cellPad, PANEL.gridChrome)
		gridWidth, columns = fit.width, fit.columns
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
		bodyTop = bodyTop,
		bodyHeight = bodyHeight,
		listTop = listTop,
		gridWidth = gridWidth,
		columns = columns,
		detailWidth = math.max(0, p.contentWidth - gridWidth - PANEL.columnGap),
		detailHeight = math.max(0, bodyHeight - listTop),
	}
end

-- The Buy button's box: `naturalWidth` (its widest text on one line, Button.widthFor) when that fits the column, else
-- the column's width with the label wrapped and the button as tall as `wrappedHeight` (that text wrapped, plus its
-- padding) needs, never below `buttonHeight`.
function ShopFormat.buyBox(
	naturalWidth: number,
	columnWidth: number,
	buttonHeight: number,
	wrappedHeight: number
): BuyBox
	if naturalWidth <= columnWidth then
		return { w = naturalWidth, h = buttonHeight, wraps = false }
	end
	return { w = math.max(0, columnWidth), h = math.max(buttonHeight, math.ceil(wrappedHeight)), wraps = true }
end

-- The detail column of `detailWidth` × `detailHeight`: Buy (`buy`, with its `balanceLine` px "Balance after" line and
-- SUB_GAP under it, always reserved so arming never moves anything) then Inspect (`inspect`), wrapped and pinned at the
-- bottom, PANEL.buttonGap apart (fix round 2); the list scrolls in what is left above them, `gap` above the buttons. A
-- nil box is a hidden button.
function ShopFormat.detailLayout(
	detailWidth: number,
	detailHeight: number,
	gap: number,
	buy: Box?,
	balanceLine: number,
	inspect: Box?
): DetailLayout
	local items: { Layout.WrapItem } = {}
	local buyIndex: number? = nil
	local inspectIndex: number? = nil
	if buy then
		table.insert(items, { w = buy.w, h = buy.h + SUB_GAP + math.max(0, balanceLine) })
		buyIndex = #items
	end
	if inspect then
		table.insert(items, { w = inspect.w, h = inspect.h })
		inspectIndex = #items
	end
	local pinned = Layout.pinnedButtons(detailWidth, detailHeight, gap, items, PANEL.buttonGap)
	return {
		rows = pinned.rows,
		scrollHeight = pinned.scrollHeight,
		buttonsTop = pinned.buttonsTop,
		buttonsHeight = pinned.buttonsHeight,
		buy = if buyIndex then pinned.buttons[buyIndex] else nil,
		inspect = if inspectIndex then pinned.buttons[inspectIndex] else nil,
	}
end

return ShopFormat
