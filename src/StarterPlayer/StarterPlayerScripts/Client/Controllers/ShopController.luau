--!strict
-- ShopController (client only). DESIGN §11.6 (Shop screen), §6.6 (direct shop: the guaranteed Coin path to Dragon),
-- §11.5 (two-step spend confirm), §6.10 (the restricted "Shop squishies directly" shortcut), §6.11 (Robux: coin bundles
-- off until real ids, no passes), §11.3 (states), §11.4 (focus, L1 / R1), §2.8 (ShopBuy, EquipSquishy,
-- PromptCoinBundle), §18.5.2 / §18.6 (sounds), §12 (the server decides everything).
-- The "shop" modal (lobby only; refused and closed from Matched through Returning by UIController). Opened by the HUD
-- Shop button, the HUD coin pill ({tab = "coins"}), the Squishies screen's "View in Shop" ({squishyId}), the Boxes
-- screen's restricted shortcut ({boxId}: only that box's items) and the shop counter's prompt
-- (WorldBinder.registerStand("SD_ShopCounter")). Params: {tab = "squishies" | "coins", squishyId?, boxId?}
-- (UI/ShopFormat.params).
-- * Header: title (hud.nav.shop), the player's Coins (coin icon + common.coinsAmount), Close. Tabs Squishies / Coins
--   (shop.tabSquishies / shop.tabCoins; L1 / R1 switch them). No passes tab or line (§6.11).
-- * Squishies tab: with a box filter, a chip row [All] [<box name>] (All clears the filter); the grid of cards
--   (Shop_Card_<id>: preview, name, rarity, status: price / Owned / need Coins / Loading… / not for sale; sorted by
--   rarity, price, name) next to the detail panel (preview, name, rarity, price, Owned or not-for-sale line, Buy,
--   Inspect, and after a purchase "You got {name}!" with "Equip now").
-- * Buy (Shop_BuyButton) is a UI/Components/ConfirmButton: first press "Confirm: {price} Coins" + "Balance after", a
--   second press within Config.UI.confirmSeconds sends NetController.invokeAsync("ShopBuy", id, price, requestId)
--   with the Catalog price (compared only) and a GUID per buy, reused when the same buy is pressed again after a call
--   that never reached the server's decision (ShopFormat.requestIdFor / buyOutcome). Disabled with the missing amount
--   when the Coins are short, and with a reason while the duel lock holds, the profile loads / is OFFLINE / READONLY or
--   a save is pending (ShopFormat.spendBlock). Success: the shop.success toast with the ui.purchase sound (one sound per
--   action, §18.5.2 B5), the card reads Owned, "Equip now" (EquipSquishy) in the detail panel; a pending save adds the
--   box.saving note. ok with charged = false -> Owned ("You already own this squishy. No Coins were spent."). Refusals
--   show Strings.reasonText (common.noCoinsSpent only when charged == false). Coins are never shown or granted
--   locally: the HUD counts down on the StateDelta (its spend squish, §18.5.2 B1).
-- * Inspect (Shop_InspectButton) opens the Part 6 "inspect" screen {squishyId, owned, source = "shop"}; it shows only
--   once that screen is registered. Unowned squishies can be inspected; they cannot be equipped (§6.6).
-- * Coins tab: only shop.coinsUnavailable while no bundle is offered (StateController monetization.bundles is empty:
--   always in v1, every productId is nil) - no buy buttons, no "coming soon". The bundle path exists but is unreachable
--   until the server offers bundles: rows with the amount from Config and the Robux price from GetProductInfoAsync on
--   the client ("…" / "Unavailable" / "{price} Robux"); Buy fires PromptCoinBundle(key); PromptProductPurchaseFinished
--   only stops the spinner. Coins and the "+{n} Coins" toast come only from StateDelta after ProcessReceipt.
-- Readings (DESIGN is silent):
-- * §11.6 "cards with Coin price, Inspect, Buy": the cards show the price and state; Inspect and Buy sit in the detail
--   panel of the selected card, the same grid + detail layout as the Squishies screen (a 150 px card has no room for
--   "Confirm: 25,000 Coins"). Opening with {squishyId} selects that card.
-- * The card frames use the rarity colour and stroke width (Art/RarityStyle); the gradients and shimmer stay on the
--   Squishies screen.
-- * A Robux prompt spinner also stops after PROMPT_TIMEOUT_SECONDS (a prompt the server refused never finishes).
-- Part 8 (DESIGN §11.2, §11.6; the same fold as the Squishies screen's; layout maths in UI/ShopFormat):
-- * Buy (Shop_BuyButton with its "Balance after" line) and Inspect are pinned under the scrolling detail
--   ("DetailButtons", a sibling of the "Detail" ScrollingFrame), wrapped in the narrow column by ShopFormat.detailLayout
--   from their measured widths; the line under Buy is always reserved, so arming moves nothing. When the widest text
--   Buy can show ("Confirm: 25,000 Coins" at a large text size on a phone) is wider than the column, Buy takes the
--   column's width and wraps its label (ShopFormat.buyBox, ConfirmButton:setWidth). Equip now stays in the success area
--   inside the list; the list scrolls to it when a purchase succeeds.
-- * The panel's sizes come from ShopFormat.panelLayout: the header and every chip (tabs, box filter) are touch-sized
--   (they were 44 base = 37 px at scale 0.85, under §11.2's minimum). On phones the detail preview is
--   DETAIL_ICON_COMPACT_PX.
-- * Cards: InventoryFormat.cardSize keeps 150 × 184 at the default text size and grows only when the player's text
--   needs it; the rarity tag stacks when side by side does not fit; the status line wraps under the coin.
-- * The gamepad focus on open: the selected card (Squishies tab) or the tab's chip, else Close.
-- Foam UI restyle (spec 2026-10-09; look and layout only, every button does what it did):
-- * The title is a header tab in the Shop tile's accent (Theme.headerTab, accent "shop"); the panel's top padding
--   follows it (ShopFormat.panelLayout's topPadding) and the panel sits a quarter of the tab lower so both are centred.
--   The header row shows the player's Coins as the coin and a bare number (fewer words) and Close.
-- * The tab and filter chips are foam Buttons (Strawberry when on, Frosting otherwise).
-- * Cards are foam cards with a rarity rim (as on the Squishies screen; the face is the light Sky when selected, a light
--   Mint when owned); names in the Button display kind; the status line is ShopFormat.cardLine: a buyable card shows
--   the coin and the bare price.
-- * The detail column: the preview in a Biscuit inset well, the price as the coin and a HudNumber, the Coins tab's note
--   in an inset field.
-- Foam fix batch (2026-10-09; on an 844×390 phone the cards' prices and "Owned" lines were cut in half and the detail
-- showed only the preview; layout maths in UI/ShopFormat and UI/InventoryFormat):
-- * Close hangs on the panel's top-right corner level with the header tab (as on Quests, Daily and Settings); the
--   Close-only header row is gone and the player's Coins sit at the tab row's right end (InventoryFormat.hangingChrome,
--   ShopFormat.panelLayout).
-- * The grid is as wide as the columns that fit in its share (InventoryFormat.gridFit); the detail column takes the
--   rest (before, an empty strip of about 180 px sat before the grid's scrollbar).
-- * The cards are as tall as the status lines they show now (a two-line "Need … more Coins" makes them taller; before,
--   every card kept room for one: about 55 px empty under the text on a PC).
-- * The detail preview shrinks so the squishy's name under it stays in view above Buy and Inspect (previewPx).
-- Foam fix round 2 (2026-10-09; Buy floated in a slot wider than itself, 65-97 px before Inspect; on a phone the rarity
-- tag was hidden under the buttons):
-- * Buy is drawn as wide as its box (the widest text it can show, so arming still moves nothing): Buy and Inspect sit
--   from the column's left edge, ShopFormat.PANEL.buttonGap apart, like the Squishies detail buttons.
-- * The preview leaves room for the name and the rarity tag (RarityTag.tallest); with no room for its smallest size the
--   well hides (InventoryFormat.previewPx 0).
-- * On touch the detail list's scroll bar stays on screen while it is longer than its window (UI/Components/ScrollHint).
-- UI overhaul (2026-10-11, Candy UI): the cards are collectible cards (UI/CardFace, every card in its rarity's colours:
-- they are products; a white frame when selected); the card's status line is Gold for a price and Mint for Owned;
-- inactive tab and filter chips are the plum neutral; Close is the red X; the detail preview is the hero of the column
-- (up to DETAIL_ICON_PX when the column has the room, on a glow in the rarity's colour, bobbing gently while the screen
-- is open) and the price is a Gold number.
-- Stable names: Shop_CloseButton, Shop_TabSquishiesButton, Shop_TabCoinsButton, Shop_FilterAllButton,
-- Shop_FilterBoxButton, Shop_Card_<id>, Shop_BuyButton, Shop_InspectButton, Shop_EquipNowButton,
-- Shop_Bundle_<key>Button.

-- Services

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local RarityStyle = require(Shared.Art.RarityStyle)
local Rarity = require(Shared.Rarity)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local CardFace = require(Client.UI.CardFace)
local CoinIcon = require(Client.UI.Components.CoinIcon)
local ConfirmButton = require(Client.UI.Components.ConfirmButton)
local Create = require(Client.UI.Create)
local Focus = require(Client.UI.Focus)
local InventoryFormat = require(Client.UI.InventoryFormat)
local KeyText = require(Client.UI.KeyText)
local Layout = require(Client.UI.Layout)
local RarityTag = require(Client.UI.Components.RarityTag)
local ScrollHint = require(Client.UI.Components.ScrollHint)
local ShopFormat = require(Client.UI.ShopFormat)
local StaticIcon = require(Client.UI.Components.StaticIcon)
local Theme = require(Client.UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

type Card = {
	id: string,
	root: TextButton,
	face: CardFace.CardFace, -- UI overhaul: the collectible card's face, rim and art glow
	icon: StaticIcon.StaticIcon,
	coin: Frame,
	status: TextLabel,
	statusLimit: UISizeConstraint, -- the status line wraps under the coin (Part 8: sized with the card)
	rarity: RarityTag.RarityTag,
}

-- A tab or filter chip: a foam Button (setAccent: Strawberry when on).
type Chip = Button.Button

type Detail = {
	icon: StaticIcon.StaticIcon,
	well: Frame, -- the inset well around the preview
	glow: Frame, -- UI overhaul: the rarity glow behind the preview
	coinsLine: TextLabel, -- UI overhaul: "Coins per squeeze: n"
	name: TextLabel,
	rarity: RarityTag.RarityTag,
	priceRow: Frame,
	price: TextLabel,
	status: TextLabel,
	error: TextLabel,
	scroll: ScrollingFrame, -- "Detail": the list
	rail: Frame, -- fix round 2: its scroll bar on touch (ScrollHint), over the list's right edge
	buttons: Frame, -- "DetailButtons": pinned under the list (Part 8)
	confirm: ConfirmButton.ConfirmButton,
	inspect: Button.Button,
	success: Frame,
	successLabel: TextLabel,
	equipNow: Button.Button,
}

-- The frames the panel layout sizes (Part 8: ShopFormat.panelLayout; foam restyle: the header tab; fix batch: no
-- header row, Close hangs on the top-right corner, the player's Coins at the tab row's right end).
type Frames = {
	tabs: Frame,
	wallet: Frame, -- the player's Coins: the coin and a bare number
	body: Frame,
	content: Frame,
	grid: ScrollingFrame,
	coins: ScrollingFrame,
	tab: Frame,
	padding: UIPadding, -- the panel's (its top follows the tab and Close)
}

type BundleRowRefs = { root: Frame, name: TextLabel, amount: TextLabel, price: TextLabel, buy: Button.Button }

-- Constants

local SCREEN = "shop"
local INSPECT_SCREEN = "inspect"
local MODAL_GUI = "SD_Modal"
local COUNTER_TAG = "SD_ShopCounter"
local REMOTE_BUY = "ShopBuy"
local REMOTE_BUNDLE = "PromptCoinBundle"
local SOUND_PURCHASE = "ui.purchase" -- §18.6: a server purchase result (Shop, trainer)
local EQUIPPED_TOAST = "inspect.equippedToast"
local GENERIC = "error.generic"
local SHOP = Config.UI.Shop
local TOUCH = Config.UI.Touch
local CARD_WIDTH = SHOP.cardWidth
local CARD_HEIGHT = 192 -- reading: §11.6 gives the card width only (UI overhaul: 184 -> 192, larger art)
local CARD_ICON_PX = 100 -- UI overhaul: 92 -> 100
local CARD_PAD = 6
local CARD_GAP = 2
local CARD_PIP_PX = 8
local CARD_NAME_KIND: Theme.TextKind = "Button" -- foam restyle: larger type, the display font
local CARD_STATUS_KIND: Theme.TextKind = "Chip" -- the price / status line in the display font
local CARD_RADIUS = Theme.Radius.button
local CARD_BANDS = Theme.Foam.panel.bevel + Theme.Foam.panel.drop -- the foam card's bevel and drop (kept free)
local DETAIL_ICON_PX = 300 -- UI overhaul: 132 -> 300, the hero fills the column's free height (previewPx caps it)
local DETAIL_ICON_COMPACT_PX = 88 -- reading (Part 8): on phones more of the detail shows above the pinned buttons
local DETAIL_ICON_MIN_PX = 48 -- fix batch: the smallest the preview gets so the name stays in view (previewPx)
local WELL_PAD_PX = 8 -- the inset well around the detail preview
local CLOSE_INSET = 16 -- Close sits this far from the panel's right edge (as on Quests and Settings)
local PANEL = ShopFormat.PANEL -- margin, height share (0.88: never more of the screen), padding, gaps, grid share
local CELL_PAD = PANEL.cellPad
local GRID_SHARE = PANEL.gridShare -- the Squishies screen's split
local SCROLLBAR_PX = 6
local COIN_PX = 18
local HEADER_COIN_PX = 30
local PRICE_COIN_PX = 28
local STATUS_GAP = 4 -- between the coin and the status text on a card
local MEASURE_MARGIN_PX = 2 -- Part 8: added to measured texts so laid-out parts never touch
local BUY_PAD_Y = 4 -- reading: the space above and below a wrapped Buy label
local PROMPT_TIMEOUT_SECONDS = 30 -- reading: the Robux spinner never outlives this
local TAB_KIND: Theme.TextKind = "H2" -- the header tab's gap under it is PANEL.tabGap (InventoryFormat.hangingChrome)
-- UI overhaul: the card faces are UI/CardFace's; the status line's colours (a price in Gold, "Owned" in Mint).
local STATUS_PRICE_COLOR = Theme.Colors.gold
local STATUS_OWNED_COLOR = Theme.Accents.mint.face
local PREVIEW_BOB_PX = 4 -- the detail preview's idle bob (base px) ...
local PREVIEW_BOB_SECONDS = 2.6 -- ... one cycle
local PREVIEW_WOBBLE_DEG = 2
local PREVIEW_GLOW_SHARE = 0.92
local PREVIEW_GLOW_TRANSPARENCY = 0.7

-- Module table

local ShopController = {}

-- Private

local log = Log.new("Shop")
local cleanup: Cleanup.Cleanup? = nil
local openCleanup: Cleanup.Cleanup? = nil
local panel: Frame? = nil
local frames: Frames? = nil
local closeButton: Button.Button? = nil
local panelLayout: ShopFormat.PanelLayout? = nil
local lastDetail: ShopFormat.DetailLayout? = nil -- the detail column as laid out last (debugState)
local cardSize: InventoryFormat.CardSize = { width = CARD_WIDTH, height = CARD_HEIGHT, nameLines = 1, stacked = false }
-- Fix batch: the status lines the cards show now (refreshGrid); the cards are as tall as these need. Nil = every line a
-- card can show (before the first refresh).
local cardLines: { string }? = nil
local successShown = false -- the success area was showing at the last refresh (scroll to it once when it appears)
local coinsLabel: TextLabel? = nil
local loadingLabel: TextLabel? = nil
local tabChips: { [string]: Chip } = {}
local filterRow: Frame? = nil
local filterAll: Chip? = nil
local filterBox: Chip? = nil
local squishiesBody: Frame? = nil
local coinsBody: GuiObject? = nil
local coinsNote: TextLabel? = nil
local coinsNoteField: Frame? = nil -- the inset field around the note
local bundleList: Frame? = nil
local bundleRows: { [string]: BundleRowRefs } = {}
local grid: ScrollingFrame? = nil
local gridLayout: UIGridLayout? = nil
local cards: { [string]: Card } = {}
local detail: Detail? = nil

local tab: ShopFormat.Tab = ShopFormat.TAB_SQUISHIES
local boxFilter: string? = nil
local selected: string? = nil
local buying: string? = nil -- the squishy a ShopBuy is running for
local pendingRequest: ShopFormat.Pending? = nil
local lastSuccess: string? = nil -- the squishy just bought (the "You got X!" line and Equip now)
local equipping = false
local prices: { [string]: ShopFormat.PriceState } = {}
local promptingKey: string? = nil
local promptToken = 0

local function newRequestId(): string
	return HttpService:GenerateGUID(false)
end

local function coinsNow(): number
	return StateController.coins() or 0
end

local function hasDataError(): boolean
	local status = StateController.dataStatus()
	return status ~= nil and (status.status == "offline" or status.status == "readonly")
end

local function currentEntries(): { ShopFormat.Entry }
	return ShopFormat.entries(
		Catalog.list(),
		StateController.owned(),
		coinsNow(),
		buying,
		ShopFormat.boxItemIds(boxFilter)
	)
end

local function entryOf(list: { ShopFormat.Entry }, id: string?): ShopFormat.Entry?
	for _, entry in list do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

-- Each chip's painted state, so a refresh repaints only the chips that change (a repaint restarts the press motion).
local chipActive: { [Chip]: boolean } = {}

local function paintChip(chip: Chip?, active: boolean)
	if chip == nil or chipActive[chip] == active then
		return
	end
	chipActive[chip] = active
	chip:setAccent(if active then "strawberry" else "plum")
end

-- Layout: the pinned detail buttons (Part 8) ------------------------------------------------------------------------

-- What the Buy can show for the selected squishy (its price, the player's Coins and the reason that blocks it): set
-- by refreshDetail, read by layoutDetail.
type BuyInfo = { price: number, balance: number, block: string? }
local lastBuy: BuyInfo? = nil

-- The Buy's widest width on one line over every text it can show (idle, armed "Confirm: ...", need Coins, blocked, and
-- the "Balance after" line), and its height with the label wrapped inside `columnWidth`.
local function measureBuy(info: BuyInfo, columnWidth: number): (number, number)
	local idle = ConfirmButton.view(ConfirmButton.initial(info.price, info.balance))
	local armedState = ConfirmButton.initial(info.price, math.max(info.balance, info.price))
	armedState.phase = "armed"
	local armed = ConfirmButton.view(armedState)
	local states: { { text: string, reason: string? } } = {
		{ text = Strings.shop.buy },
		{ text = armed.confirmText or Strings.shop.buy },
		{ text = Strings.shop.buy, reason = idle.needText },
		{ text = Strings.shop.buy, reason = info.block },
	}
	local inner = math.max(1, columnWidth - 2 * Button.PADDING_X)
	local natural, wrapped = 0, 0
	for _, state in states do
		natural = math.max(natural, Button.widthFor(state.text, state.reason))
		local height = Theme.textBounds(state.text, "Button", nil, inner).Y
		if state.reason then
			height += Theme.textBounds(state.reason, "Small", nil, inner).Y
		end
		wrapped = math.max(wrapped, height + 2 * BUY_PAD_Y)
	end
	local balanceText = armed.balanceText
	if balanceText then
		natural = math.max(natural, Theme.textWidth(balanceText, "Small", Enum.FontWeight.Bold) + MEASURE_MARGIN_PX)
	end
	return natural, wrapped
end

-- The detail column: Buy and Inspect pinned under the list (ShopFormat.detailLayout); the preview smaller on phones.
-- Only while the screen is open (it runs again from onOpen).
local function layoutDetail()
	local d, l = detail, panelLayout
	if d == nil or l == nil or not UIController.isOpen(SCREEN) then
		return
	end
	local buttonHeight = Layout.touchBase(TOUCH.primaryButton, l.scale)
	local balanceLine = Theme.lineHeight("Small", Enum.FontWeight.Bold)
	local info = lastBuy
	local buyBox: ShopFormat.BuyBox? = nil
	if d.confirm.root.Visible and info then
		local natural, wrapped = measureBuy(info, l.detailWidth)
		buyBox = ShopFormat.buyBox(natural, l.detailWidth, buttonHeight, wrapped)
	end
	local inspect: ShopFormat.Box? = if d.inspect.root.Visible
		then { w = Button.widthFor(Strings.common.inspect), h = buttonHeight }
		else nil
	local buy: ShopFormat.Box? = if buyBox then { w = buyBox.w, h = buyBox.h } else nil
	local placed = ShopFormat.detailLayout(l.detailWidth, l.detailHeight, PANEL.gap, buy, balanceLine, inspect)
	lastDetail = placed
	d.scroll.Size = UDim2.fromOffset(l.detailWidth, placed.scrollHeight)
	d.buttons.Position = UDim2.new(1, 0, 0, placed.buttonsTop)
	d.buttons.Size = UDim2.fromOffset(l.detailWidth, placed.buttonsHeight)
	local buyRect = placed.buy
	if buyBox and buyRect then
		-- Fix round 2: Buy is drawn as wide as its box (its widest text), so it no longer floats in a wider slot with a
		-- gap before Inspect; the row starts at the column's left edge like the Squishies one.
		d.confirm:setWidth(buyBox.w)
		d.confirm.button.root.Size = UDim2.fromOffset(buyBox.w, buyBox.h)
		d.confirm.root.Position = UDim2.fromOffset(buyRect.x + buyRect.w / 2, buyRect.y)
	end
	local inspectRect = placed.inspect
	if inspectRect then
		d.inspect.root.Position = UDim2.fromOffset(inspectRect.x + inspectRect.w / 2, inspectRect.y)
		d.inspect.root.Size = UDim2.fromOffset(0, buttonHeight)
	end
	d.rail.Size = UDim2.fromOffset(SCROLLBAR_PX, placed.scrollHeight)
	-- Fix batch: under the well, the list's gap and the name (Title) stay in view (InventoryFormat.previewPx). Fix round
	-- 2: and a gap and the rarity tag; with no room for the smallest preview the well hides rather than cut the tag.
	local iconPx = InventoryFormat.previewPx(
		placed.scrollHeight,
		2 * Theme.Padding.small + Theme.lineHeight("Title") + RarityTag.tallest(),
		WELL_PAD_PX,
		DETAIL_ICON_MIN_PX,
		if l.class == "compact" then DETAIL_ICON_COMPACT_PX else DETAIL_ICON_PX
	)
	d.well.Visible = iconPx > 0
	if iconPx > 0 then
		d.icon.root.Size = UDim2.fromOffset(iconPx, iconPx)
		d.well.Size = UDim2.new(1, 0, 0, iconPx + 2 * WELL_PAD_PX)
		local glowPx = math.floor(iconPx * PREVIEW_GLOW_SHARE)
		d.glow.Size = UDim2.fromOffset(glowPx, glowPx)
	end
end

-- Detail panel ------------------------------------------------------------------------------------------------------

local function refreshDetail(list: { ShopFormat.Entry })
	local d = detail
	if d == nil then
		return
	end
	d.error.Visible = hasDataError()
	local entry = entryOf(list, selected)
	if entry == nil then
		d.confirm.root.Visible = false
		d.success.Visible = false
		return
	end
	d.icon:setSquishy(entry.id)
	d.icon:setOwned(true)
	d.name.Text = entry.name
	d.rarity:setRarity(entry.rarity)
	local rarityStyle = RarityStyle.get(entry.rarity)
	d.glow.BackgroundColor3 = if rarityStyle then rarityStyle.ui.glow else Theme.Colors.ink2
	d.coinsLine.Text = Strings.format(Strings.inspect.coinsPerSqueeze, { n = Catalog.getSqueezeCoins(entry.id) })
	-- Fewer words (foam restyle): the coin and the bare price.
	local priceText = ShopFormat.priceNumber(entry.price)
	d.priceRow.Visible = priceText ~= nil and not entry.owned
	d.price.Text = priceText or ""
	local statusText = if entry.state == "owned"
		then Strings.common.owned
		elseif entry.state == "notSold" then ShopFormat.cardStatusText(entry)
		else nil
	d.status.Visible = statusText ~= nil
	d.status.Text = statusText or ""

	-- Just bought: the success line shows at once, even before the StateDelta marks it owned.
	local justBought = lastSuccess == entry.id
	local buyable = not justBought
		and (entry.state == "buy" or entry.state == "needCoins" or entry.state == "purchasing")
	local confirm = d.confirm
	confirm.root.Visible = buyable
	if buyable and entry.price then
		local block = ShopFormat.spendBlock(StateController.dataStatus(), StateController.isLobbyLocked())
		if block == nil and buying ~= nil and buying ~= entry.id then
			block = Strings.common.loading -- another buy is still running (one in flight)
		end
		confirm:setPrice(entry.price, coinsNow())
		confirm:setDisabled(block)
		confirm:setLoading(buying == entry.id)
		lastBuy = { price = entry.price, balance = coinsNow(), block = block }
	elseif not buyable then
		confirm:reset()
	end
	d.inspect.root.Visible = UIController.isRegistered(INSPECT_SCREEN)
	layoutDetail()

	-- Part 8: the success area (with Equip now) sits at the end of the list; show it once when it appears.
	if justBought and not successShown then
		local scroll = d.scroll
		task.defer(function()
			if scroll.Parent ~= nil then
				local scale = math.max(UIController.scale(), 1e-3)
				scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y / scale)
			end
		end)
	end
	successShown = justBought
	d.success.Visible = justBought
	if justBought then
		d.successLabel.Text = Strings.format(Strings.shop.success, { name = entry.name })
		local equipped = StateController.equipped() == entry.id
		d.equipNow.root.Visible = not equipped
		if equipping then
			d.equipNow:setState("loading")
		elseif StateController.isLobbyLocked() then
			d.equipNow:setState("disabled", Strings.common.lockedInDuel)
		else
			d.equipNow:setState("normal")
		end
	end
end

-- Grid ----------------------------------------------------------------------------------------------------------------

-- Fix batch: fits the cards' height to the status lines `list` shows (defined with the layout below).
local fitCardLines: (list: { ShopFormat.Entry }) -> ()

local function paintCard(card: Card, entry: ShopFormat.Entry, isSelected: boolean)
	card.face:paint({ owned = true, selected = isSelected })
	local text, coin = ShopFormat.cardLine(entry)
	card.status.Text = text
	card.coin.Visible = coin
	card.status.TextColor3 = if entry.owned
		then STATUS_OWNED_COLOR
		elseif coin then STATUS_PRICE_COLOR
		else Theme.Colors.text
end

local function refreshGrid(list: { ShopFormat.Entry })
	selected = ShopFormat.keepSelection(selected, list)
	fitCardLines(list)
	local order: { [string]: number } = {}
	for index, entry in list do
		order[entry.id] = index
	end
	for id, card in cards do
		local index = order[id]
		card.root.Visible = index ~= nil
		card.root.LayoutOrder = index or 0
		local entry = if index then list[index] else nil
		if entry then
			paintCard(card, entry, id == selected)
		end
	end
	local row = filterRow
	if row then
		row.Visible = boxFilter ~= nil
	end
	local box = if boxFilter then Boxes.get(boxFilter) else nil
	if filterBox and box then
		filterBox:setText(KeyText.get(box.nameKey))
	end
	paintChip(filterAll, boxFilter == nil)
	paintChip(filterBox, boxFilter ~= nil)
end

-- Coins tab -----------------------------------------------------------------------------------------------------------

local function fetchPrice(key: string, productId: number)
	if prices[key] ~= nil then
		return
	end
	prices[key] = { status = "loading" }
	task.spawn(function()
		local ok, info = pcall(function(): any
			return MarketplaceService:GetProductInfoAsync(productId, Enum.InfoType.Product)
		end)
		local price = if ok and type(info) == "table" then info.PriceInRobux else nil
		if type(price) == "number" then
			prices[key] = { status = "ok", price = price }
		else
			prices[key] = { status = "failed" }
			if not ok then
				log:warn(`product info for {key} failed:`, info)
			end
		end
		ShopController.refresh()
	end)
end

local function stopPrompt()
	promptToken += 1
	promptingKey = nil
end

local function promptBundle(key: string)
	if promptingKey ~= nil then
		return
	end
	if not NetController.fire(REMOTE_BUNDLE, key) then
		UIController.toast(Strings.reasonText("purchase.unavailable"), "warn")
		return
	end
	promptingKey = key
	promptToken += 1
	local token = promptToken
	task.delay(PROMPT_TIMEOUT_SECONDS, function()
		if promptToken == token then
			stopPrompt()
			ShopController.refresh()
		end
	end)
	ShopController.refresh()
end

local function bundleRow(parent: Instance, row: ShopFormat.BundleRow, order: number): BundleRowRefs
	local c = cleanup :: Cleanup.Cleanup
	local frame = Theme.panel({
		Name = "Bundle_" .. row.key,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, Theme.Radius.medium, Theme.Padding.medium)
	c:add(frame)
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.medium, frame, Enum.HorizontalAlignment.Left)
	local text: Frame = Create("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.6, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = frame,
	})
	Theme.list(Enum.FillDirection.Vertical, 2, text, Enum.HorizontalAlignment.Left)
	local name = Theme.label({ Name = "Name", LayoutOrder = 1, Parent = text }, "Body", Enum.FontWeight.Bold)
	local amount = Theme.label({ Name = "Amount", LayoutOrder = 2, Parent = text }, "Small")
	local price = Theme.label({ Name = "Price", LayoutOrder = 3, Parent = text }, "Small")
	local key = row.key
	local buy = Button.new({
		name = "Shop_Bundle_" .. key .. "Button",
		text = Strings.shop.buy,
		kind = "primary",
		height = TOUCH.primaryButton,
		layoutOrder = 2,
		parent = frame,
		onActivated = function()
			promptBundle(key)
		end,
	})
	c:add(buy)
	return { root = frame, name = name, amount = amount, price = price, buy = buy }
end

local function refreshCoins()
	local note, list = coinsNote, bundleList
	if note == nil or list == nil then
		return
	end
	local monetization = StateController.get("monetization")
	local offered = if type(monetization) == "table" and type(monetization.bundles) == "table"
		then monetization.bundles
		else nil
	local view =
		ShopFormat.coinsView(offered, Config.Monetization.CoinBundles, prices, ShopFormat.bundlesAllowed(Config.Grip))
	note.Visible = view.unavailable
	note.Text = view.text or ""
	local field = coinsNoteField
	if field then
		field.Visible = view.unavailable
	end
	local shown: { [string]: boolean } = {}
	for index, row in view.rows do
		shown[row.key] = true
		if tab == ShopFormat.TAB_COINS then
			fetchPrice(row.key, row.productId)
		end
		local refs = bundleRows[row.key]
		if refs == nil then
			refs = bundleRow(list, row, index)
			bundleRows[row.key] = refs
		end
		local r = refs :: BundleRowRefs
		r.root.Visible = true
		r.root.LayoutOrder = index
		r.name.Text = row.name
		r.amount.Text = row.coinsText
		r.price.Text = row.priceText
		if promptingKey == row.key then
			r.buy:setState("loading")
		elseif not row.priceReady or StateController.isLobbyLocked() then
			r.buy:setState("disabled", if StateController.isLobbyLocked() then Strings.common.lockedInDuel else nil)
		else
			r.buy:setState("normal")
		end
	end
	for key, refs in bundleRows do
		if not shown[key] then
			refs.root.Visible = false
		end
	end
end

-- Refresh ---------------------------------------------------------------------------------------------------------------

local function refresh()
	if panel == nil then
		return
	end
	local loaded = StateController.isLoaded()
	if loadingLabel then
		loadingLabel.Visible = not loaded
	end
	local coins = StateController.coins()
	if coinsLabel then
		coinsLabel.Text = Format.coins(coins or 0) -- beside the coin icon (fewer words, like the HUD's coin capsule)
		coinsLabel.Visible = coins ~= nil
	end
	for name, chip in tabChips do
		paintChip(chip, name == tab)
	end
	if squishiesBody then
		squishiesBody.Visible = loaded and tab == ShopFormat.TAB_SQUISHIES
	end
	if coinsBody then
		coinsBody.Visible = loaded and tab == ShopFormat.TAB_COINS
	end
	if not loaded then
		return
	end
	local list = currentEntries()
	refreshGrid(list)
	refreshDetail(list)
	refreshCoins()
end

-- An armed Buy never carries over to another squishy, tab or filter (the player confirms what they armed).
local function disarm()
	local d = detail
	if d and buying == nil then
		d.confirm:reset()
	end
end

local function selectCard(id: string)
	if selected ~= id then
		lastSuccess = nil
		disarm()
	end
	selected = id
	SoundController.play("ui.click")
	refresh()
end

local function setTab(newTab: ShopFormat.Tab)
	if table.find(ShopFormat.TABS, newTab) == nil then
		return
	end
	tab = newTab
	disarm()
	refresh()
	-- A card in the hidden tab may hold the gamepad selection: move it to the tab's chip.
	local chip = tabChips[newTab]
	if chip and Focus.isGamepad() then
		Focus.select(chip.root)
	end
end

-- The grid's columns: the ones panelLayout fitted (InventoryFormat.gridFit; the grid is exactly that wide).
local function updateColumns()
	local layout, l = gridLayout, panelLayout
	if layout == nil or l == nil then
		return
	end
	layout.FillDirectionMaxCells = math.max(1, l.columns)
end

-- Layout: the panel and the cards (Part 8) ----------------------------------------------------------------------------

-- Every text a card's status line can show (the price, need Coins, Owned, Loading, not for sale).
local function statusTexts(): { string }
	local texts = { Strings.common.owned, Strings.common.loading, Strings.reasonText("shop.notForSale") }
	for _, def in Catalog.list() do
		local price = def.shopPrice
		if price then
			table.insert(texts, ShopFormat.priceNumber(price) or "")
			table.insert(texts, ShopFormat.needText(price))
		end
	end
	return texts
end

-- The card size for the player's text size (InventoryFormat.cardSize with the status line under the rarity tag), and
-- the width the status text wraps in. Fix batch: the status line is as tall as the lines the cards show now need
-- (cardLines), else as tall as the tallest a card can show.
local function measureCards(): (InventoryFormat.CardSize, number)
	local nameWidth, wordWidth = 0, 0
	for _, def in Catalog.list() do
		local name = Strings.resolve(def.nameKey) or def.id
		nameWidth = math.max(nameWidth, Theme.textWidth(name, CARD_NAME_KIND))
		for word in string.gmatch(name, "%S+") do
			wordWidth = math.max(wordWidth, Theme.textWidth(word, CARD_NAME_KIND))
		end
	end
	local metrics: InventoryFormat.CardMetrics = {
		nameWidth = nameWidth + MEASURE_MARGIN_PX,
		wordWidth = wordWidth + MEASURE_MARGIN_PX,
		lineHeight = Theme.lineHeight(CARD_NAME_KIND),
		tagInlineWidth = 0,
		tagInlineHeight = 0,
		tagStackedWidth = 0,
		tagStackedHeight = 0,
	}
	for _, rarity in Rarity.ORDER do
		local m = RarityTag.measure(rarity, CARD_PIP_PX)
		metrics.tagInlineWidth = math.max(metrics.tagInlineWidth, m.inlineWidth + MEASURE_MARGIN_PX)
		metrics.tagInlineHeight = math.max(metrics.tagInlineHeight, m.inlineHeight)
		metrics.tagStackedWidth = math.max(metrics.tagStackedWidth, m.stackedWidth + MEASURE_MARGIN_PX)
		metrics.tagStackedHeight = math.max(metrics.tagStackedHeight, m.stackedHeight)
	end
	local base: InventoryFormat.CardBase = {
		width = CARD_WIDTH,
		height = CARD_HEIGHT,
		iconPx = CARD_ICON_PX,
		padX = CARD_PAD,
		padY = CARD_PAD,
		gap = CARD_GAP,
		bands = CARD_BANDS,
	}
	-- The status line wraps beside the coin inside the card's width, so the width comes first.
	local first = InventoryFormat.cardSize(base, metrics)
	local statusWidth = math.max(1, first.width - 2 * CARD_PAD - COIN_PX - STATUS_GAP)
	local statusHeight = COIN_PX
	for _, text in cardLines or statusTexts() do
		statusHeight = math.max(statusHeight, Theme.textBounds(text, CARD_STATUS_KIND, nil, statusWidth).Y)
	end
	base.extraHeight = statusHeight
	return InventoryFormat.cardSize(base, metrics), statusWidth
end

-- The cells follow the card size; the rarity tags stack and the status lines wrap when the card needs it. (The grid's
-- width follows in applyLayout: the columns depend on the card width.)
local function applyCardSize()
	local size, statusWidth = measureCards()
	cardSize = size
	local layout = gridLayout
	if layout then
		layout.CellSize = UDim2.fromOffset(size.width, size.height)
	end
	for _, card in cards do
		card.rarity:setStacked(size.stacked)
		card.statusLimit.MaxSize = Vector2.new(statusWidth, math.huge)
	end
end

fitCardLines = function(list: { ShopFormat.Entry })
	local lines: { string } = {}
	for _, entry in list do
		local text = ShopFormat.cardLine(entry)
		table.insert(lines, text)
	end
	local last = cardLines
	if last and #last == #lines then
		local same = true
		for index, text in lines do
			if last[index] ~= text then
				same = false
				break
			end
		end
		if same then
			return
		end
	end
	cardLines = lines
	-- Only the height can change (the width comes from the names and the rarity tags), so the columns stay.
	applyCardSize()
end

-- The header tab and Close at the player's text size (fix batch: InventoryFormat.hangingChrome): the tab stays centred
-- on the panel's top edge and Close hangs on the top-right corner, level with it; the panel's top padding keeps the gap
-- under their lower halves, and the panel moves down by half of what hangs above it (both centred together). Returns
-- the top padding.
local function fitChrome(root: Frame, f: Frames): number
	local tabPad = f.tab:FindFirstChildOfClass("UIPadding")
	local padY = if tabPad then tabPad.PaddingTop.Offset + tabPad.PaddingBottom.Offset else 0
	local tabHeight = math.ceil(Theme.lineHeight(TAB_KIND)) + padY
	local chrome = InventoryFormat.hangingChrome(tabHeight, Layout.touchBase(TOUCH.closeButton, UIController.scale()))
	f.padding.PaddingTop = UDim.new(0, chrome.top)
	f.tab.Position = UDim2.new(0.5, 0, 0, -chrome.top)
	local close = closeButton
	if close then
		close.root.Position = UDim2.new(1, PANEL.padding - CLOSE_INSET, 0, -chrome.top)
	end
	root.Position = UDim2.new(0.5, 0, 0.5, chrome.shift)
	return chrome.top
end

-- Every size of the panel from the ScreenGui's size (ShopFormat.panelLayout), then the detail column.
local function applyLayout()
	local root, f = panel, frames
	if root == nil or f == nil then
		return
	end
	local row = filterRow
	local filtered = row ~= nil and row.Visible
	local top = fitChrome(root, f)
	local l = ShopFormat.panelLayout(UIController.screenGui(MODAL_GUI).AbsoluteSize, filtered, top, cardSize.width)
	panelLayout = l
	root.Size = UDim2.new(0, l.panelWidth, PANEL.heightShare, 0)
	f.tabs.Position = UDim2.fromOffset(0, 0)
	f.tabs.Size = UDim2.new(1, 0, 0, l.chipHeight)
	f.wallet.Position = UDim2.new(1, 0, 0, l.chipHeight / 2) -- the tab row's right end
	f.grid.Size = UDim2.new(0, l.gridWidth, 1, 0) -- as wide as its columns; the detail column takes the rest
	local chipList: { Chip } = {}
	for _, chip in tabChips do
		table.insert(chipList, chip)
	end
	for _, chip in { filterAll, filterBox } :: { Chip? } do
		if chip then
			table.insert(chipList, chip)
		end
	end
	for _, chip in chipList do
		chip.root.Size = UDim2.fromOffset(0, l.chipHeight)
	end
	f.body.Position = UDim2.fromOffset(0, l.bodyTop)
	f.body.Size = UDim2.new(1, 0, 1, -l.bodyTop)
	f.coins.Position = UDim2.fromOffset(0, l.bodyTop)
	f.coins.Size = UDim2.new(1, 0, 1, -l.bodyTop)
	if row then
		row.Size = UDim2.new(1, 0, 0, l.chipHeight)
	end
	f.content.Position = UDim2.fromOffset(0, l.listTop)
	f.content.Size = UDim2.new(1, 0, 1, -l.listTop)
	local close = closeButton
	if close then
		close.root.Size = UDim2.fromOffset(l.closeHeight, l.closeHeight) -- UI overhaul: the square red X
	end
	layoutDetail()
	updateColumns()
end

-- Buying ----------------------------------------------------------------------------------------------------------------

local function buySelected()
	local id = selected
	local def = if id then Catalog.get(id) else nil
	local price = if def then def.shopPrice else nil
	if id == nil or price == nil or buying ~= nil then
		return
	end
	local requestId, pending = ShopFormat.requestIdFor(pendingRequest, id, price, newRequestId)
	pendingRequest = pending
	buying = id
	lastSuccess = nil
	refresh()
	local result = NetController.invokeAsync(REMOTE_BUY, id, price, requestId)
	buying = nil
	local outcome = ShopFormat.buyOutcome(result)
	if not outcome.retry then
		pendingRequest = nil
	end
	if outcome.kind == "success" then
		lastSuccess = id
		local name = if def then Strings.resolve(def.nameKey) or id else id
		-- One sound per action (§18.5.2 B5): the success toast carries ui.purchase (§18.6).
		UIController.toast(Strings.format(Strings.shop.success, { name = name }), "success", { sound = SOUND_PURCHASE })
		if outcome.savePending then
			UIController.toast(Strings.reasonText("box.saving"), "info", { sound = false })
		end
	elseif outcome.kind == "owned" then
		UIController.toast(outcome.text or Strings.common.owned, "info")
	else
		UIController.toast(outcome.text or Strings.error.generic, "warn", { sound = "ui.error" })
	end
	local d = detail
	if d then
		d.confirm:setLoading(false)
	end
	refresh()
end

local function equipNow()
	local id = lastSuccess
	if id == nil or equipping then
		return
	end
	equipping = true
	refresh()
	local result = NetController.equipSquishyAsync(id)
	equipping = false
	if result.ok then
		NotifyController.show(EQUIPPED_TOAST, nil, "success")
	else
		local reason = result.reason
		local known = type(reason) == "string" and reason ~= GENERIC and KeyText.has("reason." .. reason)
		UIController.toast(
			if known then Strings.reasonText(reason) else Strings.inspect.equipFailed,
			"warn",
			{ sound = "ui.error" }
		)
	end
	refresh()
end

-- Builders --------------------------------------------------------------------------------------------------------------

-- A tab or filter chip: a foam Button (the press feel, click / hover sounds and focus ring), Strawberry while it is on
-- (paintChip). §11.2 touch size (was 44 base = 37 px at scale 0.85); applyLayout keeps it in step with the scale.
local function chipButton(
	c: Cleanup.Cleanup,
	parent: Instance,
	name: string,
	text: string,
	order: number,
	onActivated: () -> ()
): Chip
	local chip = Button.new({
		name = name,
		text = text,
		height = Layout.touchBase(TOUCH.minTarget, UIController.scale()),
		layoutOrder = order,
		parent = parent,
		onActivated = onActivated,
	})
	c:add(chip)
	return chip
end

local function buildCard(c: Cleanup.Cleanup, parent: Instance, id: string)
	local def = Catalog.get(id)
	if def == nil then
		return
	end
	local style = RarityStyle.get(def.rarity)
	local root: TextButton = Create("TextButton", {
		Name = "Shop_Card_" .. id,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	})
	c:add(root)
	-- UI overhaul: a collectible card (UI/CardFace); paintCard paints its selection.
	local _ = style
	local face = CardFace.new(root, def.rarity, {
		radius = CARD_RADIUS,
		artCenterY = CARD_PAD + CARD_ICON_PX / 2,
		artPx = CARD_ICON_PX,
	})
	c:add(face)
	Focus.decorate(root, CARD_RADIUS)
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = root,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		CARD_GAP,
		content,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Top
	)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, CARD_PAD),
		PaddingBottom = UDim.new(0, CARD_PAD + CARD_BANDS), -- the foam bands stay free (InventoryFormat.cardSize)
		PaddingLeft = UDim.new(0, CARD_PAD),
		PaddingRight = UDim.new(0, CARD_PAD),
		Parent = content,
	})
	local icon =
		StaticIcon.new({ name = "Preview", squishyId = id, sizePx = CARD_ICON_PX, layoutOrder = 1, parent = content })
	c:add(icon)
	Theme.label({
		Name = "Name",
		Text = Strings.resolve(def.nameKey) or id,
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	}, CARD_NAME_KIND)
	local rarityTag = RarityTag.new({
		name = "Rarity",
		rarity = def.rarity,
		pipSizePx = CARD_PIP_PX,
		stacked = cardSize.stacked,
		layoutOrder = 3,
		parent = content,
	})
	c:add(rarityTag)
	local statusRow: Frame = Create("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Parent = content,
	})
	Theme.list(Enum.FillDirection.Horizontal, STATUS_GAP, statusRow, Enum.HorizontalAlignment.Center)
	local coin = CoinIcon.new({ name = "Coin", sizePx = COIN_PX, layoutOrder = 1, parent = statusRow })
	c:add(coin)
	local status = Theme.label({
		Name = "Text",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		Parent = statusRow,
	}, CARD_STATUS_KIND)
	local statusLimit: UISizeConstraint = Create("UISizeConstraint", {
		MaxSize = Vector2.new(CARD_WIDTH - 2 * CARD_PAD - COIN_PX - STATUS_GAP, math.huge),
		Parent = status,
	})
	c:add(root.Activated:Connect(function()
		selectCard(id)
	end))
	root.Parent = parent
	cards[id] = {
		id = id,
		root = root,
		face = face,
		icon = icon,
		coin = coin.root,
		status = status,
		statusLimit = statusLimit,
		rarity = rarityTag,
	}
end

local function detailLabel(parent: Instance, name: string, order: number, kind: Theme.TextKind): TextLabel
	return Theme.label({
		Name = name,
		LayoutOrder = order,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}, kind)
end

local function buildDetail(c: Cleanup.Cleanup, parent: Instance)
	-- The list (its height comes from layoutDetail: what is left above the pinned buttons).
	local scroll: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Detail",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1 - GRID_SHARE, -PANEL.columnGap, 1, 0),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR_PX,
		ScrollBarImageColor3 = Theme.Colors.inkUI,
		Selectable = false,
		Parent = parent,
	})
	-- The left padding keeps the rarity chip's outline inside the list's clipping.
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, 3),
		PaddingRight = UDim.new(0, SCROLLBAR_PX + 4),
		Parent = scroll,
	})
	-- Fix round 2: on touch the list's scroll bar stays on screen while it is longer than its window (layoutDetail sizes
	-- the rail with the list).
	local scrollHint = ScrollHint.new({ scroll = scroll, parent = parent })
	scrollHint.root.AnchorPoint = Vector2.new(1, 0)
	scrollHint.root.Position = UDim2.fromScale(1, 0)
	c:add(scrollHint)
	Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.small,
		scroll,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local errorLabel = detailLabel(scroll, "Error", 1, "Small")
	errorLabel.Text = Strings.data.loadFailed
	errorLabel.TextColor3 = Theme.Colors.danger
	errorLabel.Visible = false
	-- The preview in an inset well (its size follows the layout class, layoutDetail).
	local well = Theme.inset({
		Name = "PreviewWell",
		Size = UDim2.new(1, 0, 0, DETAIL_ICON_PX + 2 * WELL_PAD_PX),
		LayoutOrder = 2,
		Parent = scroll,
	}, Theme.Radius.tile, WELL_PAD_PX)
	-- UI overhaul: a soft glow in the rarity's colour behind the preview (refreshDetail colours it).
	local glowPx = math.floor(DETAIL_ICON_PX * PREVIEW_GLOW_SHARE)
	local glow: Frame = Create("Frame", {
		Name = "Glow",
		BackgroundColor3 = Theme.Colors.ink2,
		BackgroundTransparency = PREVIEW_GLOW_TRANSPARENCY,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(glowPx, glowPx),
		Active = false,
		ZIndex = 0,
		Parent = well,
	})
	Theme.corner(9999, glow)
	local icon = StaticIcon.new({
		name = "Preview",
		squishyId = Catalog.starterId(),
		sizePx = DETAIL_ICON_PX,
		parent = well,
	})
	icon.root.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.root.Position = UDim2.fromScale(0.5, 0.5)
	c:add(icon)
	local name = detailLabel(scroll, "Name", 3, "Title")
	local rarity = RarityTag.new({ name = "Rarity", rarity = "Common", layoutOrder = 4, parent = scroll })
	c:add(rarity)
	-- The price as the coin and a bare number (fewer words; refreshDetail).
	local priceRow: Frame = Create("Frame", {
		Name = "PriceRow",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 5,
		Parent = scroll,
	})
	Theme.list(Enum.FillDirection.Horizontal, 6, priceRow, Enum.HorizontalAlignment.Left)
	c:add(CoinIcon.new({ name = "Coin", sizePx = PRICE_COIN_PX, layoutOrder = 1, parent = priceRow }))
	local price = Theme.label({
		Name = "Price",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = priceRow,
	}, "HudNumber")
	price.TextColor3 = Theme.Colors.gold -- UI overhaul: the price in Gold, with the HudNumber outline
	local status = detailLabel(scroll, "Status", 6, "Body")
	status.Visible = false
	-- UI overhaul: what the squishy earns per squeeze (Catalog), a reason to buy it; refreshDetail fills it.
	local coinsLine = detailLabel(scroll, "CoinsPerSqueeze", 7, "Body")
	coinsLine.TextColor3 = Theme.Colors.ink2

	-- Part 8: Buy and Inspect are pinned under the list (a sibling of it, not inside it), so they never scroll below
	-- the fold; layoutDetail places them (no UIListLayout: ShopFormat.detailLayout decides the rows).
	local buttons: Frame = Create("Frame", {
		Name = "DetailButtons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(1 - GRID_SHARE, -PANEL.columnGap, 0, 0),
		Parent = parent,
	})
	local confirm = ConfirmButton.new({
		name = "Shop_BuyButton",
		accent = "shop", -- UI overhaul: the Lime purchase CTA
		text = Strings.shop.buy,
		price = 0,
		balance = 0,
		height = TOUCH.primaryButton,
		layoutOrder = 1,
		parent = buttons,
		onConfirm = buySelected,
	})
	c:add(confirm)
	local inspect = Button.new({
		name = "Shop_InspectButton",
		text = Strings.common.inspect,
		height = TOUCH.primaryButton,
		layoutOrder = 2,
		parent = buttons,
		sound = false, -- opens a screen: ui.open plays instead (§18.5.2 B3)
		onActivated = function()
			local id = selected
			if id then
				UIController.open(INSPECT_SCREEN, { squishyId = id, owned = StateController.owns(id), source = SCREEN })
			end
		end,
	})
	inspect.root.Visible = false
	c:add(inspect)
	confirm.root.AnchorPoint = Vector2.new(0.5, 0) -- centred in its measured slot (layoutDetail)
	inspect.root.AnchorPoint = Vector2.new(0.5, 0)

	local success: Frame = Create("Frame", {
		Name = "Success",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 8,
		Visible = false,
		Parent = scroll,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, success, Enum.HorizontalAlignment.Left)
	local successLabel = Theme.label({ Name = "Text", LayoutOrder = 1, Parent = success }, "H2")
	local equip = Button.new({
		name = "Shop_EquipNowButton",
		text = Strings.shop.equipNow,
		kind = "primary",
		height = TOUCH.primaryButton,
		layoutOrder = 2,
		parent = success,
		onActivated = equipNow,
	})
	c:add(equip)

	detail = {
		icon = icon,
		well = well,
		glow = glow,
		coinsLine = coinsLine,
		name = name,
		rarity = rarity,
		priceRow = priceRow,
		price = price,
		status = status,
		error = errorLabel,
		scroll = scroll,
		rail = scrollHint.root,
		buttons = buttons,
		confirm = confirm,
		inspect = inspect,
		success = success,
		successLabel = successLabel,
		equipNow = equip,
	}
end

local function buildCoinsBody(c: Cleanup.Cleanup, parent: Instance, top: number): ScrollingFrame
	local body: ScrollingFrame = Create("ScrollingFrame", {
		Name = "CoinsBody",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR_PX,
		ScrollBarImageColor3 = Theme.Colors.inkUI,
		Selectable = false,
		Visible = false,
		Parent = parent,
	})
	c:add(body)
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.medium, body, Enum.HorizontalAlignment.Center)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.Padding.large),
		PaddingRight = UDim.new(0, SCROLLBAR_PX + 4),
		Parent = body,
	})
	-- The note sits in an inset field (foam restyle); it shows and hides with the note (refreshCoins).
	local field = Theme.inset({
		Name = "UnavailableField",
		LayoutOrder = 1,
		Size = UDim2.fromScale(0.8, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	}, Theme.Radius.button, Theme.Padding.large)
	local note = Theme.label({
		Name = "Unavailable",
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = Strings.shop.coinsUnavailable,
		Parent = field,
	}, "Body")
	coinsNoteField = field
	local list: Frame = Create("Frame", {
		Name = "Bundles",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = body,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, list, Enum.HorizontalAlignment.Center)
	coinsBody = body
	coinsNote = note
	bundleList = list
	return body
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local root = Theme.panel({
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, Config.UI.modalMaxWidth, PANEL.heightShare, 0),
		Parent = parent,
	}, Theme.Radius.panel, PANEL.padding)
	c:add(root)
	local chipHeight = Layout.touchBase(TOUCH.minTarget, UIController.scale())

	-- The title: a header tab in the Shop tile's accent on the panel's top edge (fitChrome follows it).
	local tab = Theme.headerTab(root, Strings.hud.nav.shop, { textKind = TAB_KIND, accent = "shop" })

	-- Fix batch: no header row. Close hangs on the top-right corner, level with the tab (fitChrome places it; drawn over
	-- the panel's outline like the tab).
	local close = Button.new({
		name = "Shop_CloseButton",
		text = Strings.common.close,
		kind = "close", -- UI overhaul: the chunky red X
		height = TOUCH.closeButton,
		parent = root,
		sound = false, -- closing plays ui.back (UIController.close, reason "button")
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	close.root.AnchorPoint = Vector2.new(1, 0.5)
	close.root.ZIndex = tab.ZIndex
	close.root.Modal = true -- frees the cursor in shift lock / first person (§10.4 step 4)
	c:add(close)
	closeButton = close

	-- Tabs (L1 / R1): the first row of the content.
	local tabRow: Frame = Create("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, chipHeight),
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, tabRow, Enum.HorizontalAlignment.Left)
	local tabTexts = { squishies = Strings.shop.tabSquishies, coins = Strings.shop.tabCoins }
	local tabNames = { squishies = "Shop_TabSquishiesButton", coins = "Shop_TabCoinsButton" }
	for index, name in ShopFormat.TABS do
		tabChips[name] = chipButton(c, tabRow, tabNames[name], tabTexts[name], index, function()
			setTab(name)
		end)
	end
	-- The player's Coins (the coin and a bare number) at the tab row's right end (fix batch: the header row is gone).
	local wallet: Frame = Create("Frame", {
		Name = "Wallet",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0, chipHeight / 2),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = root,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		Theme.Padding.small,
		wallet,
		Enum.HorizontalAlignment.Right,
		Enum.VerticalAlignment.Center
	)
	c:add(CoinIcon.new({ name = "Coin", sizePx = HEADER_COIN_PX, layoutOrder = 1, parent = wallet }))
	coinsLabel = Theme.label({
		Name = "Coins",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = wallet,
	}, "HudNumber")

	local top = chipHeight + PANEL.gap

	-- Squishies tab: the box filter row, then the grid and the detail panel.
	local body: Frame = Create("Frame", {
		Name = "SquishiesBody",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		Parent = root,
	})
	squishiesBody = body
	local row: Frame = Create("Frame", {
		Name = "FilterRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, chipHeight),
		Visible = false,
		Parent = body,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, row, Enum.HorizontalAlignment.Left)
	filterRow = row
	filterAll = chipButton(c, row, "Shop_FilterAllButton", Strings.inventory.filterAll, 1, function()
		boxFilter = nil
		disarm()
		refresh()
	end)
	-- The box's own chip only shows the filter that is on (pressing it changes nothing, as before).
	filterBox = chipButton(c, row, "Shop_FilterBoxButton", "", 2, function() end)

	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = body,
	})
	-- The grid and detail start under the filter row while it shows (applyLayout: ShopFormat.panelLayout's listTop).
	c:add(row:GetPropertyChangedSignal("Visible"):Connect(function()
		applyLayout()
	end))

	local gridFrame: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(GRID_SHARE, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR_PX,
		ScrollBarImageColor3 = Theme.Colors.inkUI,
		Selectable = false,
		Parent = content,
	})
	-- Room on every side for the cards' rarity rims (the grid clips its children). The side room is
	-- ShopFormat.PANEL.gridChrome (4 + the scrollbar + 4), which gridFit counts.
	Create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, SCROLLBAR_PX + 4),
		Parent = gridFrame,
	})
	local statusWidth: number
	cardSize, statusWidth = measureCards()
	gridLayout = Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(cardSize.width, cardSize.height),
		CellPadding = UDim2.fromOffset(CELL_PAD, CELL_PAD),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		Parent = gridFrame,
	})
	grid = gridFrame
	for _, def in Catalog.list() do
		buildCard(c, gridFrame, def.id)
	end
	for _, card in cards do
		card.statusLimit.MaxSize = Vector2.new(statusWidth, math.huge)
	end
	buildDetail(c, content)

	-- Coins tab.
	local coins = buildCoinsBody(c, root, top)
	frames = {
		tabs = tabRow,
		wallet = wallet,
		body = body,
		content = content,
		grid = gridFrame,
		coins = coins,
		tab = tab,
		padding = root:FindFirstChildOfClass("UIPadding") :: UIPadding,
	}

	loadingLabel = Theme.label({
		Name = "Loading",
		Text = Strings.common.loading,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = root,
	}, "H2")

	panel = root
	-- Part 8: every size follows the ScreenGui, the layout class and the player's text size.
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout))
	c:add(UIController.LayoutChanged:connect(applyLayout))
	local okSignal, textSizeChanged = pcall(function(): RBXScriptSignal
		return GuiService:GetPropertyChangedSignal("PreferredTextSize")
	end)
	if okSignal then
		c:add(textSizeChanged:Connect(function()
			applyCardSize()
			applyLayout()
		end))
	end
	applyLayout()
	refresh()
	return root
end

-- UI overhaul: the detail preview's idle life while the screen is open: a gentle bob and sway of the one StaticIcon
-- (never every card), still under ReducedMotion.
local function startPreviewBob(c: Cleanup.Cleanup)
	local d = detail
	if d == nil then
		return
	end
	local root = d.icon.root
	local elapsed = 0
	c:add(Scheduler.add(function(dt: number): boolean
		if Tweens.reducedMotion() then
			root.Position = UDim2.fromScale(0.5, 0.5)
			root.Rotation = 0
			return true
		end
		elapsed = (elapsed + dt) % PREVIEW_BOB_SECONDS
		local phase = 2 * math.pi * elapsed / PREVIEW_BOB_SECONDS
		root.Position = UDim2.new(0.5, 0, 0.5, math.sin(phase) * PREVIEW_BOB_PX)
		root.Rotation = math.sin(phase * 0.5) * PREVIEW_WOBBLE_DEG
		return true
	end, "render"))
	c:add(function()
		root.Position = UDim2.fromScale(0.5, 0.5)
		root.Rotation = 0
	end)
end

-- Gamepad: keeps the selected card inside the grid's visible part (§11.4), only while the screen is open.
local function followSelection(c: Cleanup.Cleanup)
	c:add(GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local frame = grid
		local object = GuiService.SelectedObject
		if frame == nil or object == nil or object.Parent ~= frame then
			return
		end
		local scale = math.max(UIController.scale(), 1e-3)
		local topPx = (object.AbsolutePosition.Y - frame.AbsolutePosition.Y) / scale
		local bottom = topPx + object.AbsoluteSize.Y / scale
		local view = frame.AbsoluteWindowSize.Y / scale
		local position = frame.CanvasPosition
		if topPx < 0 then
			frame.CanvasPosition = Vector2.new(position.X, math.max(0, position.Y + topPx))
		elseif bottom > view then
			frame.CanvasPosition = Vector2.new(position.X, position.Y + bottom - view)
		end
	end))
end

-- Public ------------------------------------------------------------------------------------------------------------------

-- Re-reads the state and repaints the screen (only once it is built).
function ShopController.refresh()
	local ok, err = pcall(function(): any
		refresh()
		return nil
	end)
	if not ok then
		log:error("refresh failed:", err)
	end
end

-- Opens the shop: {tab = "squishies" | "coins", squishyId?, boxId?} (ShopFormat.params). Returns UIController.open's result.
function ShopController.open(params: { [string]: any }?): boolean
	return UIController.open(SCREEN, params)
end

-- Small table for Studio debug hooks.
function ShopController.debugState(): { [string]: any }
	local visible = {}
	for id, card in cards do
		if card.root.Visible then
			table.insert(visible, id)
		end
	end
	table.sort(visible)
	local d = detail
	return {
		built = panel ~= nil,
		open = UIController.isOpen(SCREEN),
		tab = tab,
		boxFilter = boxFilter,
		selected = selected,
		visible = visible,
		buying = buying,
		lastSuccess = lastSuccess,
		confirm = if d then d.confirm:getView().mode else nil,
		promptingKey = promptingKey,
		-- Part 8: the card size and the pinned detail buttons (base px); fix batch: the fitted grid
		card = { width = cardSize.width, height = cardSize.height, stacked = cardSize.stacked },
		grid = if panelLayout
			then { columns = panelLayout.columns, width = panelLayout.gridWidth, detailWidth = panelLayout.detailWidth }
			else nil,
		detailButtons = if lastDetail
			then {
				rows = lastDetail.rows,
				scrollHeight = lastDetail.scrollHeight,
				buttonsTop = lastDetail.buttonsTop,
				buttonsHeight = lastDetail.buttonsHeight,
			}
			else nil,
	}
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------------

function ShopController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(UIController.registerScreen(SCREEN, {
		build = build,
		onOpen = function(params: any?)
			local p = ShopFormat.params(params)
			tab = p.tab
			boxFilter = p.boxId
			local id = p.squishyId
			if id and Catalog.isValidId(id) then
				selected = id
			end
			lastSuccess = nil
			local oc = Cleanup.new()
			if openCleanup then
				openCleanup:clean()
			end
			openCleanup = oc
			followSelection(oc)
			startPreviewBob(oc)
			refresh()
		end,
		onClose = function()
			if openCleanup then
				openCleanup:clean()
				openCleanup = nil
			end
			local d = detail
			if d and buying == nil then
				d.confirm:reset()
			end
		end,
		primary = function(): GuiObject?
			-- The selected card (Squishies tab), else the tab's chip, else Close (Part 8: never nothing).
			local card = if selected then cards[selected] else nil
			if tab ~= ShopFormat.TAB_COINS and card and card.root.Visible then
				return card.root
			end
			local chip = tabChips[tab]
			if chip then
				return chip.root
			end
			return if closeButton then closeButton.root else nil
		end,
		onTab = function(direction: number)
			setTab(ShopFormat.nextTab(tab, direction))
		end,
	}))
	c:add(WorldBinder.registerStand(COUNTER_TAG, function()
		UIController.open(SCREEN)
	end))
	for _, field in { "coins", "owned", "equipped", "dataStatus", "monetization" } do
		c:add(StateController.changed(field):connect(function()
			ShopController.refresh()
		end))
	end
	c:add(StateController.Loaded:connect(ShopController.refresh))
	c:add(StateController.LobbyLockChanged:connect(ShopController.refresh))
	c:add(
		MarketplaceService.PromptProductPurchaseFinished:Connect(
			function(userId: number, productId: number, _isPurchased: boolean)
				local player = Players.LocalPlayer
				local key = promptingKey
				if player == nil or userId ~= player.UserId or key == nil then
					return
				end
				for _, bundle in Config.Monetization.CoinBundles do
					if bundle.key == key and bundle.productId == productId then
						-- Only the spinner closes: Coins arrive with the StateDelta after ProcessReceipt (§6.11).
						stopPrompt()
						ShopController.refresh()
						return
					end
				end
			end
		)
	)
	c:add(function()
		if openCleanup then
			openCleanup:clean()
			openCleanup = nil
		end
		stopPrompt()
		table.clear(cards)
		table.clear(tabChips)
		table.clear(chipActive)
		table.clear(bundleRows)
		table.clear(prices)
		panel, coinsLabel, loadingLabel, filterRow, filterAll, filterBox = nil, nil, nil, nil, nil, nil
		frames, closeButton, panelLayout, lastDetail, lastBuy = nil, nil, nil, nil, nil
		successShown = false
		squishiesBody, coinsBody, coinsNote, bundleList, grid, gridLayout, detail = nil, nil, nil, nil, nil, nil, nil
		coinsNoteField, cardLines = nil, nil
		tab, boxFilter, selected, buying, pendingRequest, lastSuccess =
			ShopFormat.TAB_SQUISHIES, nil, nil, nil, nil, nil
		equipping = false
	end)
	log:debug("ready")
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function ShopController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return ShopController
