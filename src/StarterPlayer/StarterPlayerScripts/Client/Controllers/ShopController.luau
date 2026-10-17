--!strict
-- ShopController (client only). DESIGN §11.6 (Shop screen), §6.6 (direct shop: the guaranteed Coin path to Dragon),
-- §11.5 (two-step spend confirm), §6.10 (the "Shop squishies directly" shortcut), §6.11 (Robux: coin bundles
-- off until real ids, no passes), §11.3 (states), §11.4 (focus, L1 / R1), §2.8 (ShopBuy, PromptCoinBundle),
-- §18.5.2 / §18.6 (sounds), §12 (the server decides everything).
-- The "shop" modal (lobby only; refused and closed from Matched through Returning by UIController). Opened by the HUD
-- Shop button, the HUD coin pill ({tab = "coins"}), the Squishies screen's "View in Shop" ({squishyId}), the box
-- counter while the box check is unknown ({boxId}: only that box's items) and the shop counter's prompt
-- (WorldBinder.registerStand("SD_ShopCounter")). Params: {tab = "squishies" | "coins", squishyId?, boxId?}
-- (UI/ShopFormat.params).
-- UI FINAL R6 (the Shop window = Diego's design, plan work/ui/PLAN.md R6; `H:n` = "Squishy Duels HUD.dc.html" line n;
-- Config.UI.Shop, Config.UI.confirm; the layout maths in UI/ShopFormat):
-- * The window (R3): the gold "SHOP" band (Q9, H:291-292) with the sticker and the 76 px X; no coins readout (the HUD
--   pill shows them, G6.1). The body (H:294): 330 | 1fr, gap 20, padding 20 / 24 / 24.
-- * The featured card (H:295-312) is the selected squishy: the gold -> orange -> purple card with the rays, the two
--   stars and the gem twinkling, the art 230 floating (tap it = Inspect, G6.7), the name (featuredName), the line
--   "{Rarity} · x{n} power" (FD4; AFFECTED 2026-10-15: the capsule power; pens3 phase 5: and under it the Welcome
--   price line, shop.welcomePrice, while it applies: a stand-in, calm, no timer), and BUY (green, the coin 36 and the
--   price, pulsing; pens3 phase 5: also for a squishy you own, a copy) or the lilac OWNED bar (the free starter). The
--   LIMITED row, the Inspect button, "You got X!" and Equip now are not built (UD5, G6.7: EQUIP stays one tap away in
--   Squishies).
-- * BUY (PR13): the first press opens the design's confirm dialog (UI/Components/ConfirmDialog: the squishy in the
--   medallion, its name, "Balance after: {n}", CANCEL / BUY with the coin and the price), whose BUY sends
--   NetController.invokeAsync("ShopBuy", id, price, requestId) with the Catalog price (compared only) and a GUID per buy,
--   reused when the same buy is pressed again after a call that never reached the server's decision
--   (ShopFormat.requestIdFor / buyOutcome). Short of Coins, BUY is the "off" BUY (P11: its price #FFB3BE, a press plays
--   ui.error and the shake) and nothing opens (H:799, H:1020); the duel lock, a loading / OFFLINE / READONLY profile, a
--   pending save, a full Toy Box (pens3 phase 5) or another buy in flight disable it with the reason
--   (ShopFormat.spendBlock). The price is the entry's (Pricing.shopPrice: the Welcome price first, pens3 phase 5).
-- * A real buy (H:867-871): the design's purchase burst and green ring at the dialog's BUY, the purchase sound (its
--   fanfare's nearest, RL8), then the congrats overlay (UI/CongratsOverlay, in the dialog's layer above SD_Modal), its
--   rain after 300 ms and the jolt (Config.UI.Fx.events.purchase); AWESOME! or a tap closes it. A pending save adds
--   the box.saving note; refusals (pens3 phase 5: inventory.full too) show Strings.reasonText (common.noCoinsSpent
--   only when charged == false). Coins are never shown or granted locally: the HUD counts down on the StateDelta.
-- * The right column (H:314): the box filter row ([All] [<box name>]) while a box filter is on, then the list:
--   "SQUISHIES" (the sectionHead role, H:315) over the cards (Shop_Card_<id>: preview, name, rarity, the coin and the
--   price / Owned / need Coins / Loading… / not for sale; sorted by rarity, price, name) and, only while a coin bundle
--   is offered (G6.6; never in v1: every productId is nil), "COINS" over the pack cards (H:330-340: cream, the coin
--   92 bobbing, the amount, the green price bar with the Robux price: "…" / "Unavailable" / "{price} Robux";
--   Shop_Bundle_<key>Button fires PromptCoinBundle(key); PromptProductPurchaseFinished only stops the spinner). The
--   shop.coinsUnavailable note is not drawn. Theme.scrollbar on the list (G5.18).
-- * Desktops have no tab chips: L1 / R1 jump between the drawn sections (ShopFormat.nextTab). A phone (the compact
--   class) shows the list, or after a card's tap the featured card across the body (the separate detail state) with
--   a Back chip in the band (Shop_BackButton); its tab chips show over the list while COINS is drawn.
-- * The gamepad focus on open: the selected card (the list), BUY (the phone's featured card), else Close.
-- Readings (DESIGN is silent):
-- * The card frames use the rarity colour and stroke width (Art/RarityStyle; UI/CardFace); R5 redraws the cards.
-- * A Robux prompt spinner also stops after PROMPT_TIMEOUT_SECONDS (a prompt the server refused never finishes).
-- * The cards are as tall as the status lines they show now (InventoryFormat.cardSize; the name and the rarity tag
--   fit at the player's text size; the status line wraps under the coin).
-- Stable names: Shop_CloseButton, Shop_BackButton, Shop_TabSquishiesButton, Shop_TabCoinsButton,
-- Shop_FilterAllButton, Shop_FilterBoxButton, Shop_Card_<id>, Shop_BuyButton, Shop_InspectButton,
-- Shop_Bundle_<key>Button; the dialog's Confirm_BuyButton / Confirm_CancelButton; the overlay's Shop_AwesomeButton.

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
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local RarityStyle = require(Shared.Art.RarityStyle)
local Rarity = require(Shared.Rarity)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local CardFace = require(Client.UI.CardFace)
local CoinIcon = require(Client.UI.Components.CoinIcon)
local ConfirmDialog = require(Client.UI.Components.ConfirmDialog)
local CongratsOverlay = require(Client.UI.CongratsOverlay)
local Create = require(Client.UI.Create)
local Focus = require(Client.UI.Focus)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local InventoryFormat = require(Client.UI.InventoryFormat)
local KeyText = require(Client.UI.KeyText)
local Layout = require(Client.UI.Layout)
local RarityTag = require(Client.UI.Components.RarityTag)
local ShopFormat = require(Client.UI.ShopFormat)
local SquishyImage = require(Client.UI.Components.SquishyImage)
local StaticIcon = require(Client.UI.Components.StaticIcon)
local Theme = require(Client.UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)
local UiFx = require(Client.UI.UiFx)
local NetController = require(script.Parent.NetController)
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

-- UI FINAL R6: the featured card (H:295-312). `well` (the art area) and `icon` (the art) keep the old detail
-- preview's names: the purchase burst reads them.
type Detail = {
	root: Frame, -- "Featured"
	well: Frame, -- the art area (inside the border, above the text block), with the twinkles
	fit: UIScale, -- the art at artPx / 230
	art: Frame, -- the art's float holder (sdFloat)
	icon: SquishyImage.SquishyImage,
	inspect: TextButton, -- tap the art = Inspect (G6.7)
	text: Frame, -- the text block
	name: TextLabel,
	line: TextLabel,
	pulse: Frame, -- BUY's sdPulse holder
	buy: Button.Button,
	buyLabel: TextLabel?,
	buyCoin: Frame?,
	owned: Frame,
	error: TextLabel,
}

-- The frames the window layout sizes (ShopFormat.panelLayout).
type Frames = {
	tabs: Frame, -- the phone's tab chips
	body: Frame,
	column: Frame, -- the right column
	list: ScrollingFrame,
	cards: Frame,
	coinsHead: TextLabel,
	packs: Frame,
	tab: Frame,
	padding: UIPadding,
}

type BundleRowRefs = { root: Frame, amount: TextLabel, buy: Button.Button }

-- Constants

local SCREEN = "shop"
local INSPECT_SCREEN = "inspect"
local MODAL_GUI = "SD_Modal"
local COUNTER_TAG = "SD_ShopCounter"
local REMOTE_BUY = "ShopBuy"
local REMOTE_BUNDLE = "PromptCoinBundle"
local SOUND_PURCHASE = "ui.purchase" -- §18.6: a server purchase result (Shop, capsules); the fanfare's nearest (RL8)
local SOUND_BACK = "ui.back" -- H:886: the confirm dialog's CANCEL / scrim
local SHOP = Config.UI.Shop
local FEATURED = SHOP.featured
local PACKS = SHOP.packs
local CONFIRM = Config.UI.confirm
local PURCHASE = Config.UI.Fx.events.purchase -- H:867-871
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
local PANEL = ShopFormat.PANEL -- the body's padding and gaps, the card grid's gap and the list's chrome
local CELL_PAD = PANEL.cellPad
local LIST_PAD = 4 -- the list's padding round the cards' rims (PANEL.gridChrome counts it with the scroll bar)
local COIN_PX = 18
local STATUS_GAP = 4 -- between the coin and the status text on a card
local MEASURE_MARGIN_PX = 2 -- Part 8: added to measured texts so laid-out parts never touch
local PROMPT_TIMEOUT_SECONDS = 30 -- reading: the Robux spinner never outlives this
local WINDOW_KIND = "shop" -- UI FINAL R3: its Config.UI.Sticker.window kind (H:288-349)
local BUTTON_LIP = Config.UI.Sticker.lip.button -- H:310: 0 5px 0 #1E1428
local WHITE = Color3.new(1, 1, 1)
-- UI overhaul: the card faces are UI/CardFace's; the status line's colours (a price in Gold, "Owned" in Mint).
local STATUS_PRICE_COLOR = Theme.Colors.gold
local STATUS_OWNED_COLOR = Theme.Accents.mint.face

-- Module table

local ShopController = {}

-- Private

local log = Log.new("Shop")
local cleanup: Cleanup.Cleanup? = nil
local openCleanup: Cleanup.Cleanup? = nil
local panel: Frame? = nil
local frames: Frames? = nil
local closeButton: Button.Button? = nil
local backButton: Chip? = nil
local panelLayout: ShopFormat.PanelLayout? = nil
local lastDetail: ShopFormat.FeaturedLayout? = nil -- the featured card as laid out last (debugState)
local lastView: ShopFormat.FeaturedView? = nil -- what its button shows (refreshDetail)
local shownView: string? = nil -- the button state painted last (a repaint restarts its motion)
local cardSize: InventoryFormat.CardSize = { width = CARD_WIDTH, height = CARD_HEIGHT, nameLines = 1, stacked = false }
-- Fix batch: the status lines the cards show now (refreshGrid); the cards are as tall as these need. Nil = every line a
-- card can show (before the first refresh).
local cardLines: { string }? = nil
local loadingLabel: TextLabel? = nil
local tabChips: { [string]: Chip } = {}
local filterRow: Frame? = nil
local filterAll: Chip? = nil
local filterBox: Chip? = nil
local bundleRows: { [string]: BundleRowRefs } = {}
local gridLayout: UIGridLayout? = nil
local packLayout: UIGridLayout? = nil
local cards: { [string]: Card } = {}
local detail: Detail? = nil
local confirmDialog: ConfirmDialog.ConfirmDialog? = nil
local popConfirmBack: (() -> ())? = nil
local congrats: CongratsOverlay.CongratsOverlay? = nil
local popCongratsBack: (() -> ())? = nil

local tab: ShopFormat.Tab = ShopFormat.TAB_SQUISHIES
local boxFilter: string? = nil
local selected: string? = nil
local detailOpen = false -- a phone shows the featured card instead of the list
local coinsShown = false -- the COINS section is drawn (a bundle is offered)
local buying: string? = nil -- the squishy a ShopBuy is running for
local pendingRequest: ShopFormat.Pending? = nil
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

-- The confirm dialog's and the congrats overlay's layer: its own full-screen ScreenGui above SD_Modal.
local function promptLayer(): ScreenGui
	return UIController.screenGui(CONFIRM.layerName, CONFIRM.layer)
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

-- Layout: the featured card (H:295-312) -----------------------------------------------------------------------------

-- The art area, the art's size and the text block from the card's height and the measured name and line
-- (ShopFormat.featuredLayout). Only while the screen is open (it runs again from onOpen).
local function layoutDetail()
	local d, l = detail, panelLayout
	if d == nil or l == nil or not UIController.isOpen(SCREEN) then
		return
	end
	local border = FEATURED.border
	local textWidth = math.max(1, l.featuredWidth - 2 * border - 2 * FEATURED.text.padX)
	local nameHeight = Theme.textBounds(d.name.Text, "Found", nil, textWidth).Y
	local lineHeight = Theme.textBoundsAt(d.line.Text, "Small", textWidth, UIController.scale()).Y
	local placed = ShopFormat.featuredLayout(l.featuredHeight, nameHeight, lineHeight)
	lastDetail = placed
	d.well.Size = UDim2.new(1, 0, 0, placed.artArea)
	d.well.Visible = placed.artPx > 0
	d.fit.Scale = placed.artPx / FEATURED.art.px
	d.text.Position = UDim2.fromOffset(border, placed.textTop)
	d.text.Size = UDim2.new(1, -2 * border, 0, placed.textHeight)
	d.name.Size = UDim2.new(1, 0, 0, math.ceil(nameHeight))
	d.line.Size = UDim2.new(1, 0, 0, math.ceil(lineHeight))
	d.buy:setWidth(textWidth)
	d.buy.root.Size = UDim2.fromOffset(textWidth, FEATURED.buy.face + BUTTON_LIP)
end

-- Featured card -------------------------------------------------------------------------------------------------------

local function refreshDetail(list: { ShopFormat.Entry })
	local d = detail
	if d == nil then
		return
	end
	d.error.Visible = hasDataError()
	local entry = entryOf(list, selected)
	d.text.Visible = entry ~= nil
	if entry == nil then
		return
	end
	if d.icon:catalogId() ~= entry.id then
		d.icon:setCatalogId(entry.id)
	end
	d.name.Text = entry.name
	local line = ShopFormat.featuredLine(entry.rarity, Catalog.getPower(entry.id))
	d.line.Text = if entry.welcomeText then line .. "\n" .. entry.welcomeText else line
	local block =
		ShopFormat.spendBlock(StateController.dataStatus(), StateController.isLobbyLocked(), StateController.get("pen"))
	if block == nil and buying ~= nil and buying ~= entry.id then
		block = Strings.common.loading -- another buy is still running (one in flight)
	end
	local view = ShopFormat.featuredView(entry, block, buying)
	lastView = view
	local owned = view.mode == "owned"
	d.owned.Visible = owned
	d.pulse.Visible = not owned
	if not owned then
		d.buy:setText(view.priceText or Strings.shop.buy)
		local coin = d.buyCoin
		if coin then
			coin.Visible = view.priceText ~= nil
		end
		local key = `{view.mode}|{view.reason or ""}`
		if key ~= shownView then
			shownView = key
			if view.mode == "loading" then
				d.buy:setState("loading")
			elseif view.mode == "blocked" or view.mode == "notSold" then
				d.buy:setState("disabled", view.reason)
			else
				d.buy:setState("normal")
			end
			d.buy:setOff(view.mode == "short")
		end
		local label = d.buyLabel
		if label then
			-- P11: an "off" BUY's price in StickerPriceShort (H:946); the role's white otherwise.
			label.TextColor3 = if view.mode == "short" then Palette.StickerPriceShort else WHITE
		end
	end
	d.inspect.Visible = UIController.isRegistered(INSPECT_SCREEN)
	layoutDetail()
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

-- Coins (the pack cards, H:330-340) -----------------------------------------------------------------------------------

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

-- A design surface as a foam face (`top` -> `bottom`, the ink border inside the box, the inset highlight, the lip).
local function sticker(
	frame: GuiObject,
	colors: { top: Color3, bottom: Color3, mid: Color3?, midAt: number? },
	border: number,
	radius: number,
	lip: number,
	inset: { px: number, alpha: number }
)
	local bands = Layout.stickerBands(border, inset.px, 0, lip)
	local faceColors: any = {
		face = colors.top,
		mid = colors.mid,
		midAt = colors.midAt,
		faceEnd = colors.bottom,
		top = colors.top:Lerp(WHITE, inset.alpha),
		drop = Theme.Colors.inkUI,
	}
	Theme.foam(frame, {
		radius = radius,
		stroke = border,
		inner = true,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = faceColors,
	})
end

-- H:330-340: a coin pack card (cream, the coin bobbing, the amount, the green price bar = its buy button).
local function bundleRow(parent: Instance, row: ShopFormat.BundleRow, order: number): BundleRowRefs
	local c = cleanup :: Cleanup.Cleanup
	local frame: Frame = Create("Frame", {
		Name = "Bundle_" .. row.key,
		BorderSizePixel = 0,
		LayoutOrder = order,
	})
	c:add(frame)
	sticker(
		frame,
		{ top = Palette.StickerPackTop, bottom = Palette.StickerPackEnd },
		PACKS.border,
		PACKS.radius,
		PACKS.lip,
		PACKS.inset
	)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, PACKS.padTop),
		PaddingLeft = UDim.new(0, PACKS.padX),
		PaddingRight = UDim.new(0, PACKS.padX),
		PaddingBottom = UDim.new(0, PACKS.padBottom + PACKS.lip),
		Parent = frame,
	})
	Theme.list(Enum.FillDirection.Vertical, PACKS.innerGap, frame, Enum.HorizontalAlignment.Center)
	local art: Frame = Create("Frame", {
		Name = "Art",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, PACKS.iconPx),
		LayoutOrder = 1,
		Parent = frame,
	})
	local bob: Frame = Create("Frame", {
		Name = "SD_Bob",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PACKS.iconPx, PACKS.iconPx),
		Parent = art,
	})
	c:add(CoinIcon.new({ name = "Coin", sizePx = PACKS.iconPx, parent = bob }))
	local handle = UiIdle.add(bob, "bob", { periodS = PACKS.bobS })
	if handle then
		c:add(function()
			handle:remove()
		end)
	end
	local amount = Theme.label({
		Name = "Amount",
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = frame,
	}, "Big")
	Theme.stickerText(amount, PACKS.amountRole)
	local key = row.key
	local buy = Button.new({
		name = "Shop_Bundle_" .. key .. "Button",
		text = row.priceText,
		kind = "primary",
		accent = "greenChip", -- H:339: #A6F796 -> #38C150
		height = PACKS.priceBar,
		border = PACKS.priceBorder,
		radius = PACKS.priceRadius,
		lip = PACKS.priceLip,
		stops = 2,
		highlight = { px = PACKS.priceInset.px, a = PACKS.priceInset.alpha },
		textRole = PACKS.priceRole,
		layoutOrder = 3,
		parent = frame,
		onActivated = function()
			promptBundle(key)
		end,
	})
	c:add(buy)
	frame.Parent = parent
	return { root = frame, amount = amount, buy = buy }
end

-- The COINS section (G6.6): drawn only while a bundle is offered; true when it shows.
local function refreshCoins(): boolean
	local list, f = frames and frames.packs, frames
	if list == nil or f == nil then
		return false
	end
	local monetization = StateController.get("monetization")
	local offered = if type(monetization) == "table" and type(monetization.bundles) == "table"
		then monetization.bundles
		else nil
	local view =
		ShopFormat.coinsView(offered, Config.Monetization.CoinBundles, prices, ShopFormat.bundlesAllowed(Config.Grip))
	local shownNow = not view.unavailable
	f.coinsHead.Visible = shownNow
	list.Visible = shownNow
	local shown: { [string]: boolean } = {}
	for index, row in view.rows do
		shown[row.key] = true
		fetchPrice(row.key, row.productId)
		local refs = bundleRows[row.key]
		if refs == nil then
			refs = bundleRow(list, row, index)
			bundleRows[row.key] = refs
		end
		local r = refs :: BundleRowRefs
		r.root.Visible = true
		r.root.LayoutOrder = index
		r.amount.Text = row.coinsText
		r.buy:setText(row.priceText)
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
	return shownNow
end

-- Refresh ---------------------------------------------------------------------------------------------------------------

local applyLayout: () -> ()

local function refresh()
	if panel == nil then
		return
	end
	local loaded = StateController.isLoaded()
	if loadingLabel then
		loadingLabel.Visible = not loaded
	end
	for name, chip in tabChips do
		paintChip(chip, name == tab)
	end
	local f = frames
	if f then
		f.body.Visible = loaded
	end
	if not loaded then
		return
	end
	local list = currentEntries()
	refreshGrid(list)
	refreshDetail(list)
	local coins = refreshCoins()
	if coins ~= coinsShown then
		coinsShown = coins
		local chip = tabChips[ShopFormat.TAB_COINS]
		if chip then
			chip.root.Visible = coins
		end
		applyLayout() -- the phone's tab chips show with the sections
	end
end

-- The sections drawn (COINS only while a bundle is offered, G6.6).
local function sections(): { ShopFormat.Tab }
	return ShopFormat.sections(coinsShown)
end

-- Scrolls the list to `section`'s head (the jump of the tab chips and L1 / R1).
local function scrollTo(section: ShopFormat.Tab)
	local f = frames
	if f == nil then
		return
	end
	if section ~= ShopFormat.TAB_COINS or not coinsShown then
		f.list.CanvasPosition = Vector2.zero
		return
	end
	local scale = math.max(UIController.scale(), 1e-3)
	local offset = (f.coinsHead.AbsolutePosition.Y - f.list.AbsolutePosition.Y) / scale
	f.list.CanvasPosition = Vector2.new(0, math.max(0, f.list.CanvasPosition.Y + offset - LIST_PAD))
end

-- A phone's featured card (the separate detail state) on or off.
local function setDetailOpen(open: boolean)
	if detailOpen == open then
		return
	end
	detailOpen = open
	applyLayout()
	refresh()
	if Focus.isGamepad() then
		local d = detail
		local card = if selected then cards[selected] else nil
		Focus.select(if open and d then d.buy.root elseif card then card.root else nil)
	end
end

local function selectCard(id: string)
	selected = id
	SoundController.play("ui.click")
	refresh()
	if UIController.layoutClass() == "compact" then
		setDetailOpen(true)
	end
end

local function setTab(newTab: ShopFormat.Tab)
	if table.find(sections(), newTab) == nil then
		newTab = ShopFormat.TAB_SQUISHIES
	end
	tab = newTab
	setDetailOpen(false)
	refresh()
	scrollTo(newTab)
	local chip = tabChips[newTab]
	if chip and chip.root.Visible and Focus.isGamepad() then
		Focus.select(chip.root)
	end
end

-- The card grid's columns: the ones panelLayout fitted (InventoryFormat.gridFit in the list).
local function updateColumns()
	local layout, l = gridLayout, panelLayout
	if layout == nil or l == nil then
		return
	end
	layout.FillDirectionMaxCells = math.max(1, l.columns)
end

-- Layout: the window and the cards (Part 8) ---------------------------------------------------------------------------

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
-- columns follow in applyLayout: they depend on the card width.)
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

-- UI FINAL R3: the window's band, sticker and X at the window's chrome scale (Theme.fitWindow; Layout.windowFit), and
-- the face's top 310 px above the middle (H:289, kept on the screen with what hangs off it). Returns the top padding.
local function fitChrome(root: Frame, fit: Layout.WindowFit): number
	local chrome = Theme.fitWindow(root, fit.k)
	root.Position = UDim2.new(0.5, 0, 0.5, fit.shift)
	return chrome.top
end

-- The pack cards' cells: PACKS.columns across the list (H:330: repeat(4, 1fr), gap 12), as tall as their parts.
local function packCell(listWidth: number): Vector2
	local inner = math.max(1, listWidth - PANEL.gridChrome)
	local width = math.max(1, math.floor((inner - (PACKS.columns - 1) * PACKS.gap) / PACKS.columns))
	local height = PACKS.padTop
		+ PACKS.iconPx
		+ PACKS.innerGap
		+ Theme.lineHeight("Big")
		+ PACKS.innerGap
		+ math.max(PACKS.priceBar + PACKS.priceLip, TOUCH.minTarget)
		+ PACKS.padBottom
		+ PACKS.lip
	return Vector2.new(width, math.ceil(height))
end

-- Every size of the window from the ScreenGui's size (ShopFormat.panelLayout), then the featured card.
applyLayout = function()
	local root, f = panel, frames
	if root == nil or f == nil then
		return
	end
	local row = filterRow
	local filtered = row ~= nil and row.Visible
	local screen = UIController.screenGui(MODAL_GUI).AbsoluteSize
	local top = fitChrome(root, Layout.windowFit(screen, WINDOW_KIND))
	local l = ShopFormat.panelLayout(screen, filtered, top, cardSize.width, detailOpen, #sections() > 1)
	panelLayout = l
	root.Size = UDim2.fromOffset(l.panelWidth, l.panelHeight + Config.UI.Sticker.lip.window) -- the face and its lip
	f.tabs.Visible = l.tabsShown
	f.tabs.Position = UDim2.fromOffset(l.inset, 0)
	f.tabs.Size = UDim2.fromOffset(l.bodyWidth, l.chipHeight)
	local chipList: { Chip } = {}
	for _, chip in tabChips do
		table.insert(chipList, chip)
	end
	for _, chip in { filterAll, filterBox, backButton } :: { Chip? } do
		if chip then
			table.insert(chipList, chip)
		end
	end
	for _, chip in chipList do
		chip.root.Size = UDim2.fromOffset(0, l.chipHeight)
	end
	local back = backButton
	if back then
		back.root.Visible = l.class == "compact" and detailOpen
	end
	f.body.Position = UDim2.fromOffset(l.inset, l.bodyTop)
	f.body.Size = UDim2.fromOffset(l.bodyWidth, l.bodyHeight)
	local d = detail
	if d then
		d.root.Visible = l.featuredShown
		d.root.Size = UDim2.fromOffset(l.featuredWidth, l.featuredHeight)
		d.root.Position = UDim2.fromOffset(l.featuredWidth / 2, l.featuredHeight / 2)
	end
	f.column.Visible = l.listShown
	f.column.Position = UDim2.fromOffset(l.listLeft, 0)
	f.column.Size = UDim2.fromOffset(l.listWidth, l.bodyHeight)
	if row then
		row.Size = UDim2.new(1, 0, 0, l.chipHeight)
	end
	f.list.Position = UDim2.fromOffset(0, l.listTop)
	f.list.Size = UDim2.new(1, 0, 0, l.listHeight)
	local packs = packLayout
	if packs then
		local cell = packCell(l.listWidth)
		packs.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	end
	layoutDetail()
	updateColumns()
end

-- Buying ----------------------------------------------------------------------------------------------------------------

local function closeConfirm()
	local pop = popConfirmBack
	popConfirmBack = nil
	if pop then
		pop()
	end
	local dialog = confirmDialog
	confirmDialog = nil
	if dialog then
		dialog:close()
	end
end

local function closeCongrats()
	local pop = popCongratsBack
	popCongratsBack = nil
	if pop then
		pop()
	end
	congrats = nil
end

-- H:867-871: the purchase burst and ring at the dialog's BUY (`at`), then the congrats overlay with its rain and jolt.
local function celebrate(id: string, name: string, at: GuiObject?)
	if at then
		UiFx.sparks(at, { n = PURCHASE.sparks.n, spread = PURCHASE.sparks.spread })
		for _, ring in PURCHASE.rings do
			UiFx.ring(at, UiFx.colors({ ring.color })[1], ring.size)
		end
	end
	closeConfirm()
	local old = congrats
	if old then
		old:destroy()
		closeCongrats()
	end
	local def = Catalog.get(id)
	local overlay = CongratsOverlay.show({
		layer = promptLayer(),
		catalogId = id,
		title = name,
		description = if def then ShopFormat.featuredLine(def.rarity, Catalog.getPower(id)) else "",
		scale = UIController.scale(),
		trackScale = UIController.trackScale,
		sound = function(key: string)
			SoundController.play(key)
		end,
		onClose = closeCongrats,
	})
	congrats = overlay
	popCongratsBack = UIController.pushBack(function()
		overlay:close(true) -- UIController.back plays ui.back for it
	end)
	task.delay(PURCHASE.rainDelayMs / 1000, function()
		overlay:rain(PURCHASE.rain)
	end)
	local column = overlay.root:FindFirstChild("Column")
	if column and column:IsA("GuiObject") then
		UiFx.jolt(column, PURCHASE.jolt)
	end
end

-- The confirm dialog's BUY (PR13 step two): one ShopBuy for `id` at its Catalog `price`.
local function buySelected(id: string, price: number)
	local def = Catalog.get(id)
	if buying ~= nil then
		return
	end
	local requestId, pending = ShopFormat.requestIdFor(pendingRequest, id, price, newRequestId)
	pendingRequest = pending
	buying = id
	refresh()
	local result = NetController.invokeAsync(REMOTE_BUY, id, price, requestId)
	buying = nil
	local outcome = ShopFormat.buyOutcome(result)
	if not outcome.retry then
		pendingRequest = nil
	end
	local dialog = confirmDialog
	local at: GuiObject? = if dialog then dialog.buy.root else nil
	if outcome.kind == "success" then
		local name = if def then Strings.resolve(def.nameKey) or id else id
		-- One sound per action (§18.5.2 B5): ui.purchase (§18.6; H:868 / H:871, RL8), then the congrats overlay.
		SoundController.play(SOUND_PURCHASE)
		celebrate(id, name, at)
		-- UI overhaul: the new squishy gets a burst in its rarity's glow on the preview (after the server's yes only).
		local d = detail
		local style = if def then RarityStyle.get(def.rarity) else nil
		if d and d.well.Visible then
			UiFx.burst(d.well, "medium", if style then style.ui.glow else nil)
			UiFx.punch(d.icon.root, 1.15)
		end
		if outcome.savePending then
			UIController.toast(Strings.reasonText("box.saving"), "info", { sound = false })
		end
	else
		closeConfirm()
		UIController.toast(outcome.text or Strings.error.generic, "warn", { sound = "ui.error" })
	end
	refresh()
end

-- The featured BUY (PR13 step one): opens the confirm dialog for the selected squishy.
local function openConfirm()
	local id = selected
	local def = if id then Catalog.get(id) else nil
	local entry = entryOf(currentEntries(), id)
	local price = if entry then entry.price else nil -- pens3 phase 5: Pricing.shopPrice (the Welcome price first)
	if id == nil or def == nil or price == nil or buying ~= nil or confirmDialog ~= nil then
		return
	end
	local squishyId: string, cost: number = id, price
	local dialog = ConfirmDialog.open({
		layer = promptLayer(),
		title = Strings.resolve(def.nameKey) or squishyId,
		description = ConfirmDialog.balanceText(coinsNow(), cost),
		price = cost,
		catalogId = squishyId,
		scale = UIController.scale(),
		trackScale = UIController.trackScale,
		onBuy = function()
			buySelected(squishyId, cost)
		end,
		onCancel = function(reason: string)
			confirmDialog = nil
			local pop = popConfirmBack
			popConfirmBack = nil
			if pop then
				pop()
			end
			if reason ~= "back" then
				SoundController.play(SOUND_BACK) -- UIController.back plays it for Backspace / ButtonB
			end
		end,
	})
	confirmDialog = dialog
	popConfirmBack = UIController.pushBack(function()
		dialog:cancel("back")
	end)
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
	local root: TextButton = Create("TextButton", {
		Name = "Shop_Card_" .. id,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	})
	c:add(root)
	-- UI overhaul: a collectible card (UI/CardFace); paintCard paints its selection.
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

-- H:295-312: the featured card (the selected squishy; layoutDetail sizes its parts, refreshDetail fills them).
local function buildDetail(c: Cleanup.Cleanup, parent: Instance)
	local border = FEATURED.border
	local root: Frame = Create("Frame", {
		Name = "Featured",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), -- sdRise scales about the centre
		Size = UDim2.fromOffset(SHOP.body.featuredWidth, 0),
		Parent = parent,
	})
	sticker(root, {
		top = Palette.StickerFeaturedTop,
		mid = Palette.StickerFeaturedMid,
		midAt = FEATURED.midAt,
		bottom = Palette.StickerFeaturedEnd,
	}, border, FEATURED.radius, FEATURED.lip, FEATURED.inset)
	-- Inside the border, above the lip: the rays (H:296) and the art area clip there (overflow hidden, H:295).
	local clip: Frame = Create("Frame", {
		Name = "Clip",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(border, border),
		Size = UDim2.new(1, -2 * border, 1, -(2 * border + FEATURED.lip)),
		ClipsDescendants = true,
		Parent = root,
	})
	local rays = FEATURED.rays
	Theme.rays(clip, "img.fx.rays", rays.px, rays.alpha, rays.spinS, rays.centreY)
	-- H:301-306: the art area with its twinkles and the art.
	local well: Frame = Create("Frame", {
		Name = "Art",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		ZIndex = 2,
		Parent = clip,
	})
	for index, spot in FEATURED.twinkles do
		local star = IconGlyph.image(spot.key, { name = "Twinkle" .. index, sizePx = spot.px, parent = well })
		star.AnchorPoint = Vector2.new(if spot.right then 1 else 0, if spot.bottom then 1 else 0)
		star.Position = UDim2.new(
			if spot.right then 1 else 0,
			if spot.right then -spot.right else spot.left or 0,
			if spot.bottom then 1 else 0,
			if spot.bottom then -spot.bottom else spot.top or 0
		)
		local image = star:FindFirstChild("Image")
		if image and image:IsA("GuiObject") then
			image.AnchorPoint = Vector2.new(0.5, 0.5) -- sdTwinkle turns and scales about the centre
			image.Position = UDim2.fromScale(0.5, 0.5)
			UiIdle.add(image, "twinkle", { periodS = spot.periodS, delayS = spot.delayS })
		end
	end
	local holder: Frame = Create("Frame", {
		Name = "Fit",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(FEATURED.art.px, FEATURED.art.px),
		Parent = well,
	})
	local fit: UIScale = Create("UIScale", { Parent = holder })
	local art: Frame = Create("Frame", {
		Name = "SD_Float",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	local icon = SquishyImage.new(Catalog.starterId(), {
		name = "Preview",
		size = FEATURED.art.px,
		shadow = FEATURED.art.shadow,
		parent = art :: Instance,
	})
	icon.root.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.root.Position = UDim2.fromScale(0.5, 0.5)
	c:add(icon)
	-- G6.7 (R5 G5.15): a tap on the art opens Inspect (no visible button; focusable for the gamepad, PR24).
	local inspect: TextButton = Create("TextButton", {
		Name = "Shop_InspectButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 3,
		Parent = well,
	})
	Focus.decorate(inspect, FEATURED.radius)
	c:add(Button.decorate(inspect, { sound = false })) -- opens a screen: ui.open plays instead (§18.5.2 B3)
	c:add(inspect.Activated:Connect(function()
		local id = selected
		if id then
			UIController.open(INSPECT_SCREEN, { squishyId = id, owned = StateController.owns(id), source = SCREEN })
		end
	end))

	-- H:307-312: the text block (padding 0 16 16, gap 6): the name, the line, BUY / OWNED.
	local text: Frame = Create("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = root,
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, FEATURED.text.padX),
		PaddingRight = UDim.new(0, FEATURED.text.padX),
		PaddingBottom = UDim.new(0, FEATURED.text.padBottom),
		Parent = text,
	})
	Theme.list(Enum.FillDirection.Vertical, FEATURED.text.gap, text, Enum.HorizontalAlignment.Left)
	local name = Theme.label({
		Name = "Name",
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = text,
	}, "Found")
	Theme.stickerText(name, FEATURED.nameRole) -- H:308
	local line = Theme.label({
		Name = "Line",
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = text,
	}, "Small")
	Theme.stickerText(line, FEATURED.lineRole) -- H:309
	local errorLabel = Theme.label({
		Name = "Error",
		Text = Strings.data.loadFailed,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		LayoutOrder = 0,
		Parent = text,
	}, "Small")
	local action: Frame = Create("Frame", {
		Name = "Action",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, FEATURED.buy.marginTop + FEATURED.buy.face),
		LayoutOrder = 3,
		Parent = text,
	})
	-- H:310: BUY (green 62 + lip 5, the coin 36 and the price, 28 px stroke 6, gap 10), pulsing on its holder.
	local pulse: Frame = Create("Frame", {
		Name = "SD_Pulse",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), -- sdPulse scales about the centre (the CSS transform origin)
		Position = UDim2.new(0.5, 0, 0, FEATURED.buy.marginTop + (FEATURED.buy.face + BUTTON_LIP) / 2),
		Size = UDim2.new(1, 0, 0, FEATURED.buy.face + BUTTON_LIP),
		Parent = action,
	})
	local buy = Button.new({
		name = "Shop_BuyButton",
		text = Strings.shop.buy,
		kind = "primary",
		width = SHOP.body.featuredWidth - 2 * border - 2 * FEATURED.text.padX,
		height = FEATURED.buy.face,
		textRole = FEATURED.buy.textRole,
		keycap = "", -- reserves the row: the coin, then the price (H:310)
		clickSound = false, -- H:310 data-snd none: the dialog opens without a sound (RL8)
		parent = pulse,
		onActivated = function()
			local view = lastView
			if view and view.mode == "buy" then
				openConfirm()
			end
			-- "short" (off) or disabled: Button played ui.error and the shake (P11); nothing opens (H:799, H:1020).
		end,
	})
	c:add(buy)
	local buyLine = buy.visual:FindFirstChild("Line", true)
	local buyCoin: Frame? = nil
	if buyLine then
		local list = buyLine:FindFirstChildOfClass("UIListLayout")
		if list then
			list.Padding = UDim.new(0, FEATURED.buy.gap) -- H:310: gap 10
		end
		local coin = CoinIcon.new({ name = "Coin", sizePx = FEATURED.buy.coinPx, layoutOrder = 2, parent = buyLine })
		c:add(coin)
		buyCoin = coin.root
	end
	local label = buy.visual:FindFirstChild("Label", true)
	-- H:311: OWNED, the lilac bar (no lip, no inset), the check raised 5 and "OWNED", gap 10.
	local owned: Frame = Create("Frame", {
		Name = "Owned",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, FEATURED.buy.marginTop),
		Size = UDim2.new(1, 0, 0, FEATURED.owned.face),
		Visible = false,
		Parent = action,
	})
	Theme.foam(owned, {
		radius = FEATURED.owned.radius,
		stroke = FEATURED.owned.border,
		inner = true,
		colors = { face = Palette.StickerDisabledTop, faceEnd = Palette.StickerDisabledEnd },
	})
	local ownedRow: Frame = Create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = owned,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		FEATURED.owned.gap,
		ownedRow,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local checkSlot: Frame = Create("Frame", {
		Name = "Check",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(FEATURED.owned.checkPx, FEATURED.owned.checkPx),
		LayoutOrder = 1,
		Parent = ownedRow,
	})
	local check = IconGlyph.new({ name = "Icon", icon = "check", sizePx = FEATURED.owned.checkPx, parent = checkSlot })
	check.root.Position = UDim2.fromOffset(0, -FEATURED.owned.checkRaise) -- H:311: margin-top -5
	c:add(check)
	local ownedLabel = Theme.label({
		Name = "Label",
		Text = Strings.shop.owned,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = ownedRow,
	}, "HudNumber")
	Theme.stickerText(ownedLabel, FEATURED.owned.textRole)

	detail = {
		root = root,
		well = well,
		fit = fit,
		art = art,
		icon = icon,
		inspect = inspect,
		text = text,
		name = name,
		line = line,
		pulse = pulse,
		buy = buy,
		buyLabel = if label and label:IsA("TextLabel") then label else nil,
		buyCoin = buyCoin,
		owned = owned,
		error = errorLabel,
	}
end

-- A section head (H:315, H:329: 22 px #FFE36B, stroke 5).
local function sectionHead(parent: Instance, name: string, text: string, order: number): TextLabel
	local head = Theme.label({
		Name = name,
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Parent = parent,
	}, "H2")
	Theme.stickerText(head, SHOP.sections.headRole)
	return head
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local root = Theme.window({
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, Config.UI.modalMaxWidth, PANEL.heightShare, 0),
		Parent = parent,
	}, WINDOW_KIND, PANEL.padding)
	c:add(root)
	local chipHeight = Layout.touchBase(TOUCH.minTarget, UIController.scale())

	-- A phone's way back from the featured card to the list: a chip at the band's right end (shown in that state).
	local back = Button.new({
		name = "Shop_BackButton",
		text = Strings.shop.back,
		height = chipHeight,
		parent = root,
		onActivated = function()
			setDetailOpen(false)
		end,
	})
	back.root.Visible = false
	c:add(back)
	backButton = back
	-- UI FINAL R3: the gold band (H:291-292, Q9; fitChrome lays it out) and the 76 px X in it (H:347).
	local tab = Theme.headerTab(root, Strings.hud.nav.shop, { extra = back.root :: GuiObject })
	local close = Button.new({
		name = "Shop_CloseButton",
		text = Strings.common.close,
		kind = "close", -- UI overhaul: the chunky red X
		parent = root,
		sound = false, -- closing plays ui.back (UIController.close, reason "button")
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	Theme.attachClose(root, close.root)
	close.root.Modal = true -- frees the cursor in shift lock / first person (§10.4 step 4)
	c:add(close)
	closeButton = close

	-- The phone's tab chips (shown over the list while COINS is drawn; desktops jump with L1 / R1).
	local tabRow: Frame = Create("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, chipHeight),
		Visible = false,
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
	tabChips[ShopFormat.TAB_COINS].root.Visible = false

	-- H:294: the body: the featured card, then the right column.
	local body: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Parent = root,
	})
	buildDetail(c, body)
	local column: Frame = Create("Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		Parent = body,
	})
	local row: Frame = Create("Frame", {
		Name = "FilterRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, chipHeight),
		Visible = false,
		Parent = column,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, row, Enum.HorizontalAlignment.Left)
	filterRow = row
	filterAll = chipButton(c, row, "Shop_FilterAllButton", Strings.inventory.filterAll, 1, function()
		boxFilter = nil
		refresh()
	end)
	-- The box's own chip only shows the filter that is on (pressing it changes nothing, as before).
	filterBox = chipButton(c, row, "Shop_FilterBoxButton", "", 2, function() end)
	-- The list starts under the filter row while it shows (applyLayout: ShopFormat.panelLayout's listTop).
	c:add(row:GetPropertyChangedSignal("Visible"):Connect(function()
		applyLayout()
	end))

	-- H:314: the list of sections (gap 12): SQUISHIES over the cards, COINS over the pack cards.
	local list: ScrollingFrame = Create("ScrollingFrame", {
		Name = "List",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
		Parent = column,
	})
	Theme.scrollbar(list) -- G5.18 (H:22)
	-- Room on every side for the cards' rarity rims (the list clips its children): PANEL.gridChrome counts it.
	Create("UIPadding", {
		PaddingTop = UDim.new(0, LIST_PAD),
		PaddingBottom = UDim.new(0, LIST_PAD),
		PaddingLeft = UDim.new(0, LIST_PAD),
		PaddingRight = UDim.new(0, Theme.SCROLLBAR_PX + LIST_PAD),
		Parent = list,
	})
	Theme.list(Enum.FillDirection.Vertical, SHOP.sections.gap, list, Enum.HorizontalAlignment.Left)
	sectionHead(list, "SquishiesHead", Strings.shop.sectionSquishies, 1)
	local cardsFrame: Frame = Create("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = list,
	})
	local statusWidth: number
	cardSize, statusWidth = measureCards()
	gridLayout = Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(cardSize.width, cardSize.height),
		CellPadding = UDim2.fromOffset(CELL_PAD, CELL_PAD),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		Parent = cardsFrame,
	})
	for _, def in Catalog.list() do
		buildCard(c, cardsFrame, def.id)
	end
	for _, card in cards do
		card.statusLimit.MaxSize = Vector2.new(statusWidth, math.huge)
	end
	local coinsHead = sectionHead(list, "CoinsHead", Strings.shop.sectionCoins, 3)
	coinsHead.Visible = false
	local packs: Frame = Create("Frame", {
		Name = "Packs",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Visible = false,
		Parent = list,
	})
	packLayout = Create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(PACKS.gap, PACKS.gap),
		FillDirectionMaxCells = PACKS.columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		Parent = packs,
	})
	frames = {
		tabs = tabRow,
		body = body,
		column = column,
		list = list,
		cards = cardsFrame,
		coinsHead = coinsHead,
		packs = packs,
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
	Theme.textOnWindow(loadingLabel :: TextLabel) -- UI FINAL R3: on the pink body (H:196)

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

-- UI FINAL R6: the featured card's idle life while the screen is open (H:295, H:305, H:310): its rise on open, the
-- art's sdFloat 3 s and BUY's sdPulse 1.6 s (Anim/UiIdle; at rest under ReducedMotion).
local function startPreviewBob(c: Cleanup.Cleanup)
	local d = detail
	if d == nil then
		return
	end
	local rise = FEATURED.rise
	c:add(Scheduler.add(Tweens.keyframes(d.root, rise.frames :: any, { ms = rise.ms, curve = rise.curve }), "render"))
	local float = UiIdle.add(d.art, "float", { periodS = FEATURED.art.floatS })
	local pulse = UiIdle.add(d.pulse, "pulse", { periodS = FEATURED.buy.pulseS })
	c:add(function()
		if float then
			float:remove()
		end
		if pulse then
			pulse:remove()
		end
	end)
end

-- Gamepad: keeps the selected card inside the list's visible part (§11.4), only while the screen is open.
local function followSelection(c: Cleanup.Cleanup)
	c:add(GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local f = frames
		local object = GuiService.SelectedObject
		if f == nil or object == nil or object.Parent ~= f.cards then
			return
		end
		local frame = f.list
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
	local view = lastView
	return {
		built = panel ~= nil,
		open = UIController.isOpen(SCREEN),
		tab = tab,
		sections = sections(),
		boxFilter = boxFilter,
		selected = selected,
		detailOpen = detailOpen,
		visible = visible,
		buying = buying,
		featured = if view then view.mode else nil,
		confirmOpen = confirmDialog ~= nil,
		congratsOpen = congrats ~= nil,
		promptingKey = promptingKey,
		-- Part 8: the card size; UI FINAL R6: the body and the featured card (base px)
		card = { width = cardSize.width, height = cardSize.height, stacked = cardSize.stacked },
		body = if panelLayout
			then {
				columns = panelLayout.columns,
				featuredWidth = panelLayout.featuredWidth,
				featuredHeight = panelLayout.featuredHeight,
				listWidth = panelLayout.listWidth,
				listHeight = panelLayout.listHeight,
			}
			else nil,
		featuredLayout = if lastDetail
			then { artArea = lastDetail.artArea, artPx = lastDetail.artPx, textTop = lastDetail.textTop }
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
			boxFilter = p.boxId
			local id = p.squishyId
			if id and Catalog.isValidId(id) then
				selected = id
			end
			-- A phone opened on a squishy ("View in Shop") shows its featured card; else the list.
			detailOpen = id ~= nil and UIController.layoutClass() == "compact"
			local oc = Cleanup.new()
			if openCleanup then
				openCleanup:clean()
			end
			openCleanup = oc
			followSelection(oc)
			startPreviewBob(oc)
			refresh()
			applyLayout()
			-- The coin pill ({tab = "coins"}) opens at COINS while it is drawn, else at the top (R4 G4.16).
			tab = if table.find(sections(), p.tab) then p.tab else ShopFormat.TAB_SQUISHIES
			refresh()
			task.defer(scrollTo, tab)
		end,
		onClose = function()
			if openCleanup then
				openCleanup:clean()
				openCleanup = nil
			end
			if buying == nil then
				closeConfirm() -- never left open over another screen (a busy one closes with its answer)
			end
		end,
		primary = function(): GuiObject?
			-- The phone's featured card: BUY; else the selected card, the tab's chip, Close (never nothing).
			local d = detail
			if d and detailOpen and d.root.Visible then
				return d.buy.root
			end
			local card = if selected then cards[selected] else nil
			if card and card.root.Visible then
				return card.root
			end
			local chip = tabChips[tab]
			if chip and chip.root.Visible then
				return chip.root
			end
			return if closeButton then closeButton.root else nil
		end,
		onTab = function(direction: number)
			setTab(ShopFormat.nextTab(tab, direction, sections()))
		end,
	}))
	c:add(WorldBinder.registerStand(COUNTER_TAG, function()
		UIController.open(SCREEN)
	end))
	for _, field in { "coins", "owned", "equipped", "dataStatus", "monetization", "pen" } do
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
		closeConfirm()
		local overlay = congrats
		if overlay then
			overlay:destroy()
		end
		closeCongrats()
		table.clear(cards)
		table.clear(tabChips)
		table.clear(chipActive)
		table.clear(bundleRows)
		table.clear(prices)
		panel, loadingLabel, filterRow, filterAll, filterBox = nil, nil, nil, nil, nil
		frames, closeButton, backButton, panelLayout, lastDetail, lastView = nil, nil, nil, nil, nil, nil
		gridLayout, packLayout, detail, cardLines, shownView = nil, nil, nil, nil, nil
		tab, boxFilter, selected, buying, pendingRequest = ShopFormat.TAB_SQUISHIES, nil, nil, nil, nil
		detailOpen, coinsShown = false, false
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
