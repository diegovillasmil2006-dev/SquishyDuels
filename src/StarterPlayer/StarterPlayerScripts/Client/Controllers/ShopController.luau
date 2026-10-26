--!strict
-- ShopController (client only). The Shop window = Diego's design exactly (owner 2026-10-22: "exact diego layout"; the
-- owner's standing rule: what is uploaded is built exactly as it is). `H:n` = "Squishy Duels HUD.dc.html" line n
-- (Squishy Duels TDMFFAhud copy: the shop is H:311-372, its data hud-lib.js:50-61 = `lib:n`); numbers in
-- Config.UI.Shop, texts in Strings.shop, pictures in AssetTable (img.pass.*, img.pack.*, img.icon.robux).
-- * The window (H:312-316): 1060 x 650 at the design's own px, the gold dotted band with "SHOP", the basket sticker
--   and the red X (Theme.window kind "shop"). On a smaller screen the whole window shrinks evenly (the design's phone
--   render), never re-laid out: one UIScale (ShopFormat.windowFit).
-- * The body (H:317): 330 | 1fr, gap 20, padding 20 24 24.
-- * The featured card (H:318-336): the Dragon Bundle on the gold -> orange -> purple card with the rays, the LIMITED
--   badge (and the "Ends in" pill only while Config.UI.Shop.featured.bundle.endsAt is a real end time: no fake
--   countdown for kids), the stars and the gem twinkling, the Dragon floating, DRAGON BUNDLE, the line
--   "Exclusive Dragon + (coin) 2,500" and the green Robux BUY (or the lilac OWNED bar once the Dragon is owned).
-- * The right column (H:337-366): GAME PASSES over Diego's 4 pass cards (2 columns: the coloured tile with the picture
--   bobbing, the name over the line, the green Robux price chip), then COINS over his 4 coin pack cards (the +10% /
--   +20% / +30% and BEST badges, the picture bobbing, the amount, the green Robux price bar). Cards rise in on open.
-- * Buying with Robux (§6.11): a coin pack sells only once the server offers its bundle with a productId and its price
--   is known (PromptCoinBundle); passes and the bundle have no products yet. Until then every price reads
--   Strings.shop.soon and its button is off. Never a price or product made up here.
-- * Squishies for Coins moved out of the shop (owner 2026-10-22: "Keep it, outside the shop"): UI/SquishyBuy, used by
--   the Squishies screen.
-- * Gear step 3 (2026-10-26; owner "Yes, build step 3 like that"; [P] a stand-in until Diego draws it): two tabs SHOP |
--   GEAR in the gold band (his picker well, UI/Components/SegmentedTabs; Config/GearShop). GEAR swaps the right column
--   for the GEAR page: GEAR over 4 gear cards (his pass cards, a little taller, the text stacked over the chip:
--   UI/GearFormat's next step of each line, the tile in the tier's zone colour with the tier number and the stars
--   bought), then the gear's throw power. A tap buys (GearBuy with the shown price, one at a time: the chip reads …
--   meanwhile); short of Coins the chip greys, the line says how many are missing and a tap shakes the coin pill
--   (HudController.denyCoins); all bought = the lilac MAX chip. open({tab = "gear"}) opens on GEAR.
-- * INCOME step 2 (2026-10-26; owner "An INCOME tab in the shop"; [P] a stand-in until Diego draws it): a third tab
--   INCOME: INCOME over 2 gear cards (UI/IncomeFormat: SQUISHY COINS and ALL EARNINGS, the tile the level it buys, the
--   line the boost now -> after); a tap sends PenBuyIncome the same way. open({tab = "income"}) opens on INCOME (the
--   HUD's 6th sticker); an open without a tab shows SHOP.
-- Stable names: Shop_CloseButton, Shop_BuyButton (the featured BUY), Shop_Pass_<key>, Shop_Pack_<key>,
-- Shop_Bundle_<key>Button (a pack's price bar), Shop_Tabs (Tab_shop / Tab_gear / Tab_income), Shop_Gear_<line>
-- (Shop_Gear_coins / Shop_Gear_all on INCOME).

-- Services

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local GearShop = require(Shared.Config.GearShop) -- gear step 3
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local CoinIcon = require(Client.UI.Components.CoinIcon)
local Create = require(Client.UI.Create)
local GearFormat = require(Client.UI.GearFormat)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local IncomeFormat = require(Client.UI.IncomeFormat) -- INCOME step 2
local Layout = require(Client.UI.Layout)
local MotionTrack = require(Client.UI.MotionTrack)
local SegmentedTabs = require(Client.UI.Components.SegmentedTabs)
local ShopFormat = require(Client.UI.ShopFormat)
local SquishyImage = require(Client.UI.Components.SquishyImage)
local Theme = require(Client.UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

type PassCard = { key: string, root: TextButton, rise: Frame, chip: Frame, price: TextLabel }
type PackCard = { key: string, root: Frame, rise: Frame, buy: Button.Button, ready: boolean }
-- Gear step 3: a gear card; its tile is rebuilt when the shown tier changes, its stars when their count does.
type GearCard = {
	line: string,
	remote: string, -- INCOME step 2: GearBuy, or PenBuyIncome on the INCOME tab
	root: TextButton,
	rise: Frame,
	content: Frame,
	width: number,
	tile: Frame?,
	tier: number,
	dots: { Frame },
	steps: number,
	text: Frame,
	name: TextLabel,
	desc: TextLabel,
	buyChip: Frame,
	buyText: TextLabel,
	maxChip: Frame,
	maxText: TextLabel,
	view: GearFormat.Card?,
}
type Featured = {
	root: Frame,
	pulse: Frame,
	buy: Button.Button,
	owned: Frame,
	art: Frame,
	timer: Frame,
	timerText: TextLabel,
}

-- Constants

local SCREEN = "shop"
local MODAL_GUI = "SD_Modal"
local COUNTER_TAG = "SD_ShopCounter"
local REMOTE_BUNDLE = "PromptCoinBundle"
local SHOP = Config.UI.Shop
local BODY = SHOP.body
local FEATURED = SHOP.featured
local BUNDLE = FEATURED.bundle
local PASSES = SHOP.rows -- H:341-349: the pass card's numbers
local PASS_LIST = SHOP.passes -- lib:50-55: Diego's 4 passes
local PACKS = SHOP.packs
local BADGE = SHOP.badge
local CARD_IN = Config.UI.motion.cardIn -- H:31 sdRise
local CARD_LIP = 5 -- H:341, H:355: 0 5px 0 #1E1428
local WINDOW_KIND = "shop"
local WINDOW_BORDER = Config.UI.Sticker.border.heavy -- H:313: 5
local WINDOW_PAD = BODY.padTop -- the window's own padding (Theme.window); the body adds the rest (H:317)
local BUTTON_LIP = Config.UI.Sticker.lip.button
local PROMPT_TIMEOUT_SECONDS = 30 -- reading: the Robux spinner never outlives this
local WHITE = Color3.new(1, 1, 1)
local REMOTE_GEAR = "GearBuy" -- gear step 3
local REMOTE_INCOME = "PenBuyIncome" -- INCOME step 2
local PAGE_SHOP, PAGE_GEAR, PAGE_INCOME = "shop", "gear", "income"
local SOUND_PURCHASE = "ui.purchase" -- §18.6: a server purchase result
local GEAR_CARD = GearShop.card
local GEAR_TILE = GearShop.tile

-- A text role's kind (Theme.Sticker.text; any: the roles table is untyped).
local function roleKind(role: string): any
	return (Theme.Sticker.text :: any)[role].kind
end
local PASS_NAME_KIND: Theme.TextKind = roleKind(PASSES.nameRole)
local PASS_DESC_KIND: Theme.TextKind = roleKind(PASSES.descRole)
local CHIP_KIND: Theme.TextKind = roleKind(PASSES.chip.textRole)
local HEAD_KIND: Theme.TextKind = roleKind(SHOP.sections.headRole)

-- Module table

local ShopController = {}

-- Private

local log = Log.new("Shop")
local cleanup: Cleanup.Cleanup? = nil
local openCleanup: Cleanup.Cleanup? = nil
local panel: Frame? = nil
local fitScale: UIScale? = nil
local closeButton: Button.Button? = nil
local featured: Featured? = nil
local passCards: { PassCard } = {}
local packCards: { [string]: PackCard } = {}
local prices: { [string]: ShopFormat.PriceState } = {}
local promptingKey: string? = nil
local promptToken = 0
local lastFit: ShopFormat.WindowFit? = nil
-- Gear step 3: the tabs, the two pages, the gear cards, the power line, the page shown and the line being bought.
local tabs: SegmentedTabs.SegmentedTabs? = nil
local shopPage: Frame? = nil
local gearPage: Frame? = nil
local gearCards: { GearCard } = {}
local gearPower: TextLabel? = nil
local page = PAGE_SHOP
local gearBusy: string? = nil
-- INCOME step 2: the INCOME page and its 2 cards (gearBusy holds their line while one is bought: no line is shared).
local incomePage: Frame? = nil
local incomeCards: { GearCard } = {}

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

local function holder(name: string, parent: Instance): Frame
	return Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = parent,
	})
end

local function idle(c: Cleanup.Cleanup, frame: GuiObject, kind: UiIdle.Kind, periodS: number, delayS: number?)
	local handle = UiIdle.add(frame, kind, { periodS = periodS, delayS = delayS })
	if handle then
		c:add(function()
			handle:remove()
		end)
	end
end

-- A design picture (AssetTable key) at `px`, centred in `parent`; hidden until its id is filled (IconGlyph.image).
local function picture(parent: Instance, key: string, px: number, name: string): Frame
	local frame = IconGlyph.image(key, { name = name, sizePx = px, parent = parent })
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	return frame
end

-- A label sized to its measured text (never AutomaticSize inside the window's UIScale); a one-line label keeps
-- FIT_MARGIN_PX more for its sticker stroke.
local FIT_MARGIN_PX = 8
local function fitLabel(label: TextLabel, kind: Theme.TextKind, wrapWidth: number?)
	local size = Theme.textBounds(label.Text, kind, nil, wrapWidth)
	label.Size = UDim2.fromOffset(math.ceil(if wrapWidth then wrapWidth else size.X + FIT_MARGIN_PX), math.ceil(size.Y))
end

-- A price without a Robux product yet (Strings.shop.soon): the button keeps the design's green, a tap says so.
local function comingSoon()
	UIController.toast(Strings.shop.comingSoon, "info")
end

-- H:321 / H:356-357: a pill badge (border 3, round, the role's white text) at the given colours.
local function badge(
	parent: Instance,
	name: string,
	text: string,
	top: Color3,
	bottom: Color3,
	size: { height: number, padX: number }
): Frame
	local kind = roleKind(BADGE.textRole)
	local width = math.ceil(Theme.textBounds(text, kind).X) + 2 * size.padX + 2 * BADGE.border
	local frame: Frame = Create("Frame", {
		Name = name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, size.height),
		Parent = parent,
	})
	Theme.foam(frame, {
		radius = size.height / 2,
		stroke = BADGE.border,
		inner = true,
		colors = { face = top, faceEnd = bottom, drop = Theme.Colors.inkUI },
	})
	local label = Theme.label({
		Name = "Text",
		Text = text,
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 2,
		Parent = frame,
	}, kind)
	Theme.stickerText(label, BADGE.textRole)
	return frame
end

-- The green Robux chip / bar (H:347, H:362): the Robux picture and the price, or Strings.shop.soon.
local function robuxRow(c: Cleanup.Cleanup, parent: Instance, iconPx: number, gap: number, role: string): TextLabel
	local row: Frame = Create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = parent,
	})
	Theme.list(Enum.FillDirection.Horizontal, gap, row, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local icon = IconGlyph.image("img.icon.robux", { name = "Robux", sizePx = iconPx, layoutOrder = 1, parent = row })
	c:add(icon)
	local text = Theme.label({
		Name = "Text",
		Text = Strings.shop.soon,
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = row,
	}, roleKind(role))
	Theme.stickerText(text, role)
	return text
end

-- Prices and prompts ----------------------------------------------------------------------------------------------

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

-- A section head (H:338, H:352: 22 px #FFE36B, stroke 5).
local function sectionHead(parent: Instance, name: string, text: string, order: number): TextLabel
	local head = Theme.label({
		Name = name,
		Text = text,
		Size = UDim2.new(1, 0, 0, math.ceil(Theme.lineHeight(HEAD_KIND))),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Parent = parent,
	}, HEAD_KIND)
	Theme.stickerText(head, SHOP.sections.headRole)
	return head
end

-- Gear step 3: the GEAR page --------------------------------------------------------------------------------------

-- A gear card's chip (the pass chip's look, H:347): the coin (or the check) and its text; setChip sizes it to the text.
local function gearChip(
	c: Cleanup.Cleanup,
	parent: Instance,
	name: string,
	top: Color3,
	bottom: Color3,
	check: boolean
): (Frame, TextLabel)
	local spec = PASSES.chip
	local chip: Frame = Create("Frame", {
		Name = name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, spec.height + spec.lip),
		Visible = false,
		Parent = parent,
	})
	sticker(chip, { top = top, bottom = bottom }, spec.border, spec.radius, spec.lip, spec.inset)
	local row: Frame = Create("Frame", {
		Name = "FaceRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -spec.lip),
		ZIndex = 2,
		Parent = chip,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		spec.gap,
		row,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	if check then
		c:add(IconGlyph.new({ name = "Check", icon = "check", sizePx = spec.coinPx, layoutOrder = 1, parent = row }))
	else
		c:add(CoinIcon.new({ name = "Coin", sizePx = spec.coinPx, layoutOrder = 1, parent = row }))
	end
	local text = Theme.label({
		Name = "Text",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = row,
	}, CHIP_KIND)
	Theme.stickerText(text, spec.textRole)
	return chip, text
end

local function setChip(chip: Frame, label: TextLabel, text: string)
	local spec = PASSES.chip
	label.Text = text
	fitLabel(label, CHIP_KIND)
	chip.Size = UDim2.fromOffset(
		2 * spec.border + spec.padLeft + spec.coinPx + spec.gap + label.Size.X.Offset + spec.padRight,
		spec.height + spec.lip
	)
end

-- The tile in the tier's zone colour (H:342's look): the tier number over a dot a step of the tier (none for armor).
local function gearTile(card: GearCard, view: GearFormat.Card)
	local old = card.tile
	if old then
		old:Destroy()
	end
	table.clear(card.dots)
	local spec = PASSES.tile
	local found = (Palette :: any)[view.color]
	local color: Color3 = if typeof(found) == "Color3" then found else WHITE
	local tile: Frame = Create("Frame", {
		Name = "Tile",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, PASSES.border + PASSES.padLeft, 0.5, 0),
		Size = UDim2.fromOffset(spec.px, spec.px),
		Parent = card.content,
	})
	sticker(
		tile,
		{ top = color, bottom = color:Lerp(Theme.Colors.inkUI, GEAR_TILE.endShade) },
		spec.border,
		spec.radius,
		0,
		spec.inset
	)
	local number = Theme.label({
		Name = "Tier",
		Text = tostring(view.tier),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, if view.steps > 0 then 0.42 else 0.5),
		Size = UDim2.fromScale(1, 0.6),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 2,
		Parent = tile,
	}, roleKind(GEAR_TILE.numberRole))
	Theme.stickerText(number, GEAR_TILE.numberRole)
	if view.steps > 0 then
		local px = if view.steps > 4 then GEAR_TILE.pipPxSmall else GEAR_TILE.pipPx
		local row: Frame = Create("Frame", {
			Name = "Stars",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -GEAR_TILE.pipBottom),
			Size = UDim2.fromOffset(view.steps * px + (view.steps - 1) * GEAR_TILE.pipGap, px),
			ZIndex = 2,
			Parent = tile,
		})
		Theme.list(
			Enum.FillDirection.Horizontal,
			GEAR_TILE.pipGap,
			row,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		)
		for i = 1, view.steps do
			local dot: Frame = Create("Frame", {
				Name = "Star" .. i,
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(px, px),
				LayoutOrder = i,
				Parent = row,
			})
			Theme.corner(px, dot)
			Theme.stroke(Theme.Colors.inkUI, 1, dot)
			table.insert(card.dots, dot)
		end
	end
	card.tile, card.tier, card.steps = tile, view.tier, view.steps
end

-- One card from its view: the tile, the stars, the name over the line over the chip (BUY with the price, pink when
-- short with the Coins missing on the line, … while buying; the lilac MAX once all is bought).
local function paintGearCard(card: GearCard, view: GearFormat.Card)
	card.view = view
	if card.tile == nil or card.tier ~= view.tier or card.steps ~= view.steps then
		gearTile(card, view)
	end
	for i, dot in card.dots do
		dot.BackgroundTransparency = if i <= view.stars then 0 else 0.7
	end
	local max = view.state == "max"
	local short = view.state == "needCoins"
	card.maxChip.Visible = max
	card.buyChip.Visible = not max
	if max then
		setChip(card.maxChip, card.maxText, Strings.gear.max)
	else
		local price = if view.state == "busy" then Strings.shop.robuxLoading else Format.coins(view.price :: number)
		setChip(card.buyChip, card.buyText, price)
		card.buyText.TextColor3 = if short then Palette.StickerPriceShort else WHITE
	end
	local chip = if max then card.maxChip else card.buyChip
	local textLeft = PASSES.border + PASSES.padLeft + PASSES.tile.px + PASSES.gap
	local textW = math.max(1, card.width - textLeft - PASSES.border - PASSES.padRight)
	card.name.Text = view.name
	fitLabel(card.name, PASS_NAME_KIND, textW)
	card.desc.Text = if short
		then Strings.format(Strings.gear.need, { coins = Format.coins(view.missing) })
		else view.desc
	fitLabel(card.desc, PASS_DESC_KIND, textW)
	local y = 0
	card.name.Position = UDim2.fromOffset(0, y)
	y += card.name.Size.Y.Offset + PASSES.textGap
	card.desc.Position = UDim2.fromOffset(0, y)
	y += card.desc.Size.Y.Offset + GEAR_CARD.chipGap
	chip.Position = UDim2.fromOffset(0, y)
	card.text.Size = UDim2.fromOffset(textW, y + chip.Size.Y.Offset)
end

local function paintGear()
	local gear = StateController.get("gear")
	local coins = StateController.get("coins")
	local views = GearFormat.cards(gear, if type(coins) == "number" then coins else nil, gearBusy)
	for index, card in gearCards do
		local view = views[index]
		if view then
			paintGearCard(card, view)
		end
	end
	local power = gearPower
	if power then
		power.Text = Strings.format(Strings.gear.power, { x = GearFormat.powerText(gear) })
	end
	-- INCOME step 2: the INCOME cards from the pen's levels.
	local incomeViews =
		IncomeFormat.cards(StateController.get("pen"), if type(coins) == "number" then coins else nil, gearBusy)
	for index, card in incomeCards do
		local view = incomeViews[index]
		if view then
			paintGearCard(card, view)
		end
	end
end

-- A tap on a gear card (see the header): buy the shown step, or say why not.
local function buyGear(card: GearCard)
	local view = card.view
	if view == nil or view.state == "max" or gearBusy ~= nil then
		return
	end
	if view.state == "needCoins" then
		SoundController.play("ui.error")
		HudController.denyCoins()
		return
	end
	if StateController.isLobbyLocked() then
		UIController.toast(Strings.common.lockedInDuel, "warn")
		return
	end
	gearBusy = card.line
	ShopController.refresh()
	task.spawn(function()
		local result = NetController.invokeAsync(card.remote, card.line, view.price)
		gearBusy = nil
		if result.ok then
			SoundController.play(SOUND_PURCHASE)
			local bought = if card.remote == REMOTE_INCOME
				then Strings.format(Strings.income.bought, { name = view.name, level = view.tier })
				else Strings.format(Strings.gear.bought, { name = view.name })
			UIController.toast(bought, "success")
			MotionTrack.play(card.rise, CARD_IN.frames :: any, PASSES.rise.ms, 0, CARD_IN.curve)
		else
			UIController.toast(Strings.reasonText(result.reason), "warn")
		end
		ShopController.refresh()
	end)
end

-- A gear card (the pass card's face, H:341, GEAR_CARD.height tall): the tile left, the text stack (name, line, chip).
-- INCOME step 2: `remote` buys it, `list` keeps it (gearCards or incomeCards).
local function buildGearCard(
	c: Cleanup.Cleanup,
	parent: Instance,
	line: string,
	order: number,
	width: number,
	remote: string,
	list: { GearCard }
)
	local root: TextButton = Create("TextButton", {
		Name = "Shop_Gear_" .. line,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = order,
	})
	c:add(root)
	local visual = holder("SD_Visual", root)
	local rise = holder("SD_Rise", visual)
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = rise,
	})
	sticker(
		face,
		{ top = Palette.StickerCardTop, bottom = Palette.StickerCardBottom },
		PASSES.border,
		PASSES.radius,
		CARD_LIP,
		PASSES.inset
	)
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -CARD_LIP),
		ZIndex = 2,
		Parent = rise,
	})
	local text: Frame = Create("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, PASSES.border + PASSES.padLeft + PASSES.tile.px + PASSES.gap, 0.5, 0),
		Parent = content,
	})
	local name = Theme.label({
		Name = "Name",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = text,
	}, PASS_NAME_KIND)
	Theme.stickerText(name, PASSES.nameRole)
	local desc = Theme.label({
		Name = "Line",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = text,
	}, PASS_DESC_KIND)
	Theme.stickerText(desc, PASSES.descRole)
	local buyChip, buyText = gearChip(c, text, "Price", Palette.StickerGreenTop, Palette.StickerGreen2End, false)
	local maxChip, maxText = gearChip(c, text, "Max", Palette.StickerDisabledTop, Palette.StickerDisabledEnd, true)
	local card: GearCard = {
		line = line,
		remote = remote,
		root = root,
		rise = rise,
		content = content,
		width = width,
		tile = nil,
		tier = 0,
		dots = {},
		steps = -1,
		text = text,
		name = name,
		desc = desc,
		buyChip = buyChip,
		buyText = buyText,
		maxChip = maxChip,
		maxText = maxText,
		view = nil,
	}
	local feel: Button.DecorateOptions = { fx = "card", visual = visual, pivotPx = CARD_LIP / 2 }
	c:add(Button.decorate(root, feel))
	c:add(root.Activated:Connect(function()
		buyGear(card)
	end))
	root.Parent = parent
	table.insert(list, card)
end

-- A page of gear cards in the right column's place (H:337's column: the head, the cards 2 a row). INCOME step 2: the
-- GEAR and INCOME pages.
local function buildCardPage(
	c: Cleanup.Cleanup,
	body: Instance,
	left: number,
	width: number,
	height: number,
	id: string,
	head: string,
	lines: { string },
	remote: string,
	list: { GearCard }
): Frame
	local pageFrame: Frame = Create("Frame", {
		Name = if id == PAGE_GEAR then "GearPage" else "IncomePage",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(left, 0),
		Size = UDim2.fromOffset(width, height),
		Visible = false,
		Parent = body,
	})
	Theme.list(Enum.FillDirection.Vertical, SHOP.sections.gap, pageFrame, Enum.HorizontalAlignment.Left)
	sectionHead(pageFrame, if id == PAGE_GEAR then "GearHead" else "IncomeHead", head, 1)
	local cellW = math.floor((width - SHOP.sections.cellGap) / PASSES.columns)
	local rows = math.ceil(#lines / PASSES.columns)
	local gridH = rows * (GEAR_CARD.height + CARD_LIP) + (rows - 1) * Layout.lipGap(SHOP.sections.cellGap, CARD_LIP)
	local grid: Frame = Create("Frame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, gridH),
		LayoutOrder = 2,
		Parent = pageFrame,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(cellW, GEAR_CARD.height + CARD_LIP),
		CellPadding = UDim2.fromOffset(SHOP.sections.cellGap, Layout.lipGap(SHOP.sections.cellGap, CARD_LIP)),
		FillDirectionMaxCells = PASSES.columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for index, line in lines do
		buildGearCard(c, grid, line, index, cellW, remote, list)
	end
	return pageFrame
end

-- The GEAR page: its 2 x 2 cards, then the power line.
local function buildGearPage(c: Cleanup.Cleanup, body: Instance, left: number, width: number, height: number): Frame
	local lines = { "held", "platform", "arm", "armor" }
	local pageFrame =
		buildCardPage(c, body, left, width, height, PAGE_GEAR, Strings.gear.section, lines, REMOTE_GEAR, gearCards)
	local powerKind = roleKind(GearShop.powerRole)
	local power = Theme.label({
		Name = "Power",
		Text = "",
		Size = UDim2.new(1, 0, 0, math.ceil(Theme.lineHeight(powerKind))),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		LayoutOrder = 3,
		Parent = pageFrame,
	}, powerKind)
	Theme.stickerText(power, GearShop.powerRole)
	gearPower = power
	return pageFrame
end

-- Shows a page and paints the picked tab (the cards rise in on GEAR and INCOME, like the shop's on open).
local function setPage(id: string)
	page = if id == PAGE_GEAR or id == PAGE_INCOME then id else PAGE_SHOP
	if shopPage then
		shopPage.Visible = page == PAGE_SHOP
	end
	if gearPage then
		gearPage.Visible = page == PAGE_GEAR
	end
	if incomePage then
		incomePage.Visible = page == PAGE_INCOME
	end
	local picker = tabs
	if picker and picker:selected() ~= page then
		picker:select(page)
	end
	if page ~= PAGE_SHOP then
		for index, card in if page == PAGE_GEAR then gearCards else incomeCards do
			MotionTrack.play(
				card.rise,
				CARD_IN.frames :: any,
				PASSES.rise.ms,
				(index - 1) * PASSES.rise.staggerMs,
				CARD_IN.curve
			)
		end
	end
end

-- The tabs (Diego's picker well; INCOME step 2: SHOP | GEAR | INCOME), names only (setShort: no chips), sized for the
-- band's extra slot.
local function buildTabs(c: Cleanup.Cleanup): SegmentedTabs.SegmentedTabs
	local function stops(pair: { top: string, bottom: string }): { SegmentedTabs.Stop }
		return {
			{ at = 0, color = (Palette :: any)[pair.top] },
			{ at = 1, color = (Palette :: any)[pair.bottom] },
		}
	end
	local spec = GearShop.tabs
	local picker = SegmentedTabs.new({
		name = "Shop_Tabs",
		tabs = {
			{
				id = PAGE_SHOP,
				label = Strings.gear.tabShop,
				chip = "",
				short = Strings.gear.tabShop,
				stops = stops(spec.shop),
				rotation = spec.rotation,
			},
			{
				id = PAGE_GEAR,
				label = Strings.gear.tabGear,
				chip = "",
				short = Strings.gear.tabGear,
				stops = stops(spec.gear),
				rotation = spec.rotation,
			},
			{
				id = PAGE_INCOME,
				label = Strings.income.tab,
				chip = "",
				short = Strings.income.tab,
				stops = stops(spec.income),
				rotation = spec.rotation,
			},
		},
		selected = page,
		onSelect = function(id: string)
			SoundController.play("ui.click") -- Diego's tab() (hud-lib.js:138) by its nearest clip
			setPage(id)
		end,
	})
	picker:setShort(true)
	local size = picker:size(true)
	picker.root.AutomaticSize = Enum.AutomaticSize.None
	picker.root.Size = UDim2.fromOffset(size.X, size.Y)
	c:add(function()
		picker:destroy()
	end)
	return picker
end

-- Refresh -----------------------------------------------------------------------------------------------------------

local function refresh()
	if panel == nil then
		return
	end
	-- The featured card: OWNED once the Dragon is owned (H:334), else BUY: off until the bundle has a product.
	local f = featured
	if f then
		local owned = StateController.owns(BUNDLE.squishyId)
		f.owned.Visible = owned
		f.pulse.Visible = not owned
		f.buy:setState(if StateController.isLobbyLocked() then "disabled" else "normal")
		local endsAt = BUNDLE.endsAt
		f.timer.Visible = type(endsAt) == "number"
		if type(endsAt) == "number" then
			local left = math.max(0, endsAt - workspace:GetServerTimeNow())
			f.timerText.Text = Strings.format(Strings.shop.endsIn, { time = Format.clock(left) })
		end
	end
	-- The coin packs (§6.11): a pack sells while the server offers its bundle with a productId and a known price.
	local monetization = StateController.get("monetization")
	local offered = if type(monetization) == "table" and type(monetization.bundles) == "table"
		then monetization.bundles
		else nil
	local view =
		ShopFormat.coinsView(offered, Config.Monetization.CoinBundles, prices, ShopFormat.bundlesAllowed(Config.Grip))
	local rows: { [string]: ShopFormat.BundleRow } = {}
	for _, row in view.rows do
		rows[row.key] = row
		fetchPrice(row.key, row.productId)
	end
	for key, card in packCards do
		local row = rows[key]
		local price = if row then prices[key] else nil
		local ready = row ~= nil and price ~= nil and price.status == "ok"
		card.buy:setText(if ready and price and price.price then Format.coins(price.price) else Strings.shop.soon)
		card.ready = ready
		if promptingKey == key then
			card.buy:setState("loading")
		elseif StateController.isLobbyLocked() then
			card.buy:setState("disabled", if StateController.isLobbyLocked() then Strings.common.lockedInDuel else nil)
		else
			card.buy:setState("normal")
		end
	end
	paintGear() -- gear step 3
end

-- Layout ------------------------------------------------------------------------------------------------------------

-- The whole window at the design's size, shrunk evenly to the screen (ShopFormat.windowFit).
local function applyLayout()
	local root, scale = panel, fitScale
	if root == nil or scale == nil then
		return
	end
	local screen = UIController.screenGui(MODAL_GUI).AbsoluteSize
	local fit = ShopFormat.windowFit(screen)
	lastFit = fit
	Theme.fitWindow(root, 1)
	scale.Scale = fit.k
	root.Size = UDim2.fromOffset(fit.width, fit.height + Config.UI.Sticker.lip.window)
	root.Position = UDim2.new(0.5, 0, 0.5, fit.shift)
end

-- H:341, H:355, H:1240-1242: the cards rise in on open (passes from .08 s, packs from .3 s, i x .06 s).
local function riseCards()
	for index, card in passCards do
		MotionTrack.play(
			card.rise,
			CARD_IN.frames :: any,
			PASSES.rise.ms,
			PASSES.rise.delayMs + (index - 1) * PASSES.rise.staggerMs,
			CARD_IN.curve
		)
	end
	for index, item in PACKS.list do
		local card = packCards[item.key]
		if card then
			MotionTrack.play(
				card.rise,
				CARD_IN.frames :: any,
				PASSES.rise.ms,
				PACKS.riseDelayMs + (index - 1) * PASSES.rise.staggerMs,
				CARD_IN.curve
			)
		end
	end
end

-- Builders ----------------------------------------------------------------------------------------------------------

-- H:318-336: the featured card (the Dragon Bundle).
local function buildFeatured(c: Cleanup.Cleanup, parent: Instance, width: number, height: number)
	local border = FEATURED.border
	local root: Frame = Create("Frame", {
		Name = "Featured",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), -- sdRise scales about the centre
		Position = UDim2.fromOffset(width / 2, height / 2),
		Size = UDim2.fromOffset(width, height),
		Parent = parent,
	})
	sticker(root, {
		top = Palette.StickerFeaturedTop,
		mid = Palette.StickerFeaturedMid,
		midAt = FEATURED.midAt,
		bottom = Palette.StickerFeaturedEnd,
	}, border, FEATURED.radius, FEATURED.lip, FEATURED.inset)
	local clip: Frame = Create("Frame", {
		Name = "Clip",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(border, border),
		Size = UDim2.new(1, -2 * border, 1, -(2 * border + FEATURED.lip)),
		ClipsDescendants = true,
		Parent = root,
	})
	local rays = FEATURED.rays
	Theme.rays(clip, "img.fx.rays", rays.px, rays.alpha, rays.spinS, rays.centreY) -- H:319
	local innerW = width - 2 * border
	local faceH = height - FEATURED.lip - 2 * border

	-- H:320-323: the badge row (padding 14 14 0, gap 8): LIMITED, and the timer pill at the right.
	local row = BUNDLE.row
	local limited =
		badge(clip, "Limited", Strings.shop.limited, Palette.StickerRedTop, Palette.StickerRedEnd, BADGE.limited)
	limited.Position = UDim2.fromOffset(row.pad, row.pad)
	limited.ZIndex = 3
	idle(c, limited, "badge", BADGE.badgeS)
	local timer: Frame = Create("Frame", {
		Name = "Timer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -row.pad, 0, row.pad),
		Size = UDim2.fromOffset(row.timerWidth, BADGE.limited.height),
		BackgroundColor3 = Palette.StickerInk,
		BackgroundTransparency = 1 - row.timerAlpha,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		Parent = clip,
	})
	Theme.corner(BADGE.limited.height / 2, timer)
	Theme.stroke(Palette.StickerInk, BADGE.border, timer)
	local timerRow: Frame = Create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = timer,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		6,
		timerRow,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	c:add(IconGlyph.image("img.icon.clock", { name = "Clock", sizePx = 24, layoutOrder = 1, parent = timerRow }))
	local timerText = Theme.label({
		Name = "Text",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = timerRow,
	}, "Small")

	-- H:330-335: the text block (padding 0 16 16, gap 6): the name, the line, BUY / OWNED.
	local text = FEATURED.text
	local textW = innerW - 2 * text.padX
	local nameKind = roleKind(FEATURED.nameRole)
	local nameH = math.ceil(Theme.textBounds(Strings.shop.bundleName, nameKind, nil, textW).Y)
	local lineH = math.max(FEATURED.lineCoinPx, math.ceil(Theme.lineHeight(roleKind(FEATURED.lineRole))))
	local actionH = FEATURED.buy.marginTop + FEATURED.buy.face + BUTTON_LIP
	local blockH = nameH + text.gap + lineH + text.gap + actionH + text.padBottom
	local block: Frame = Create("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(text.padX, faceH - blockH),
		Size = UDim2.fromOffset(textW, blockH),
		ZIndex = 3,
		Parent = clip,
	})
	Theme.list(Enum.FillDirection.Vertical, text.gap, block, Enum.HorizontalAlignment.Left)
	local name = Theme.label({
		Name = "Name",
		Text = Strings.shop.bundleName,
		Size = UDim2.fromOffset(textW, nameH),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = block,
	}, nameKind)
	Theme.stickerText(name, FEATURED.nameRole)
	local line: Frame = Create("Frame", {
		Name = "Line",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(textW, lineH),
		LayoutOrder = 2,
		Parent = block,
	})
	Theme.list(Enum.FillDirection.Horizontal, 6, line, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)
	local lineKind = roleKind(FEATURED.lineRole)
	for index, part in { Strings.shop.bundleLine, "", Format.coins(BUNDLE.coins) } do
		if index == 2 then
			c:add(CoinIcon.new({ name = "Coin", sizePx = FEATURED.lineCoinPx, layoutOrder = 2, parent = line }))
		else
			local label = Theme.label({
				Name = "Part" .. index,
				Text = part,
				AutomaticSize = Enum.AutomaticSize.None,
				TextWrapped = false,
				LayoutOrder = index,
				Parent = line,
			}, lineKind)
			Theme.stickerText(label, FEATURED.lineRole)
			fitLabel(label, lineKind)
		end
	end
	local action: Frame = Create("Frame", {
		Name = "Action",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(textW, actionH),
		LayoutOrder = 3,
		Parent = block,
	})
	local pulse: Frame = Create("Frame", {
		Name = "SD_Pulse",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, FEATURED.buy.marginTop + (FEATURED.buy.face + BUTTON_LIP) / 2),
		Size = UDim2.new(1, 0, 0, FEATURED.buy.face + BUTTON_LIP),
		Parent = action,
	})
	local buy = Button.new({
		name = "Shop_BuyButton",
		text = Strings.shop.soon,
		kind = "primary",
		width = textW,
		height = FEATURED.buy.face,
		textRole = FEATURED.buy.textRole,
		keycap = "", -- reserves the row: the Robux picture, then the price (H:333)
		clickSound = false,
		parent = pulse,
		onActivated = comingSoon, -- no product yet (§6.11)
	})
	c:add(buy)
	local buyLine = buy.visual:FindFirstChild("Line", true)
	if buyLine then
		local list = buyLine:FindFirstChildOfClass("UIListLayout")
		if list then
			list.Padding = UDim.new(0, FEATURED.buy.gap)
		end
		c:add(IconGlyph.image("img.icon.robux", {
			name = "Robux",
			sizePx = FEATURED.buy.coinPx,
			layoutOrder = 2,
			parent = buyLine,
		}))
	end
	-- H:334: OWNED, the lilac bar with the check raised 5.
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
		Size = UDim2.fromScale(1, 1),
		Parent = owned,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		FEATURED.owned.gap,
		ownedRow,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local check = IconGlyph.new({
		name = "Check",
		icon = "check",
		sizePx = FEATURED.owned.checkPx,
		layoutOrder = 1,
		parent = ownedRow,
	})
	c:add(check)
	local ownedLabel = Theme.label({
		Name = "Label",
		Text = Strings.shop.owned,
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = ownedRow,
	}, roleKind(FEATURED.owned.textRole))
	Theme.stickerText(ownedLabel, FEATURED.owned.textRole)
	fitLabel(ownedLabel, roleKind(FEATURED.owned.textRole))

	-- H:324-329: the art area between the badge row and the text: the twinkles and the Dragon floating (230).
	local artTop = row.pad + BADGE.limited.height
	local well: Frame = Create("Frame", {
		Name = "Art",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, artTop),
		Size = UDim2.fromOffset(innerW, math.max(0, faceH - blockH - artTop)),
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
			image.AnchorPoint = Vector2.new(0.5, 0.5)
			image.Position = UDim2.fromScale(0.5, 0.5)
			idle(c, image, "twinkle", spot.periodS, spot.delayS)
		end
	end
	local artPx = math.min(FEATURED.art.px, math.floor(math.max(0, faceH - blockH - artTop)))
	local art: Frame = Create("Frame", {
		Name = "SD_Float",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(artPx, artPx),
		Parent = well,
	})
	local dragonOptions: SquishyImage.Options = {
		name = "Dragon",
		size = artPx,
		shadow = { px = FEATURED.art.shadow.px, alpha = FEATURED.art.shadow.alpha },
		parent = art :: Instance,
	}
	local dragon = SquishyImage.new(BUNDLE.squishyId, dragonOptions)
	dragon.root.AnchorPoint = Vector2.new(0.5, 0.5)
	dragon.root.Position = UDim2.fromScale(0.5, 0.5)
	c:add(dragon)

	featured = {
		root = root,
		pulse = pulse,
		buy = buy,
		owned = owned,
		art = art,
		timer = timer,
		timerText = timerText,
	}
end

-- H:341-349: a pass card (the purple card, the coloured tile with the picture bobbing, the name over the line, the
-- green Robux chip). Its BUY waits for a pass product (§6.11).
local function buildPass(c: Cleanup.Cleanup, parent: Instance, pass: { [string]: any }, order: number, width: number)
	local texts = (Strings.shop.passes :: any)[pass.key]
	local root: TextButton = Create("TextButton", {
		Name = "Shop_Pass_" .. pass.key,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = order,
	})
	c:add(root)
	local visual = holder("SD_Visual", root)
	local rise = holder("SD_Rise", visual)
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = rise,
	})
	sticker(
		face,
		{ top = Palette.StickerCardTop, bottom = Palette.StickerCardBottom },
		PASSES.border,
		PASSES.radius,
		CARD_LIP,
		PASSES.inset
	)
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -CARD_LIP),
		ZIndex = 2,
		Parent = rise,
	})
	local left = PASSES.border + PASSES.padLeft
	local tile: Frame = Create("Frame", {
		Name = "Tile",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, left, 0.5, 0),
		Size = UDim2.fromOffset(PASSES.tile.px, PASSES.tile.px),
		Parent = content,
	})
	sticker(tile, {
		top = (Palette :: any)[pass.top],
		bottom = (Palette :: any)[pass.bottom],
	}, PASSES.tile.border, PASSES.tile.radius, 0, PASSES.tile.inset)
	local bob = holder("SD_Bob", tile)
	bob.Size = UDim2.fromOffset(PASSES.art.px, PASSES.art.px)
	bob.ZIndex = 2
	picture(bob, pass.image, PASSES.art.px, "Picture")
	idle(c, bob, "bob", PASSES.art.bobS)
	-- H:347: the chip (measured to its text): border 3, padding 0 10 0 6, the Robux 22 and the price, gap 5.
	local chipSpec = PASSES.chip
	local chipW = chipSpec.border * 2
		+ chipSpec.padLeft
		+ chipSpec.coinPx
		+ chipSpec.gap
		+ math.ceil(Theme.textBounds(Strings.shop.soon, CHIP_KIND).X)
		+ chipSpec.padRight
		+ 2
	local right = PASSES.border + PASSES.padRight
	local chip: Frame = Create("Frame", {
		Name = "Price",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -right, 0.5, 0),
		Size = UDim2.fromOffset(chipW, chipSpec.height + chipSpec.lip),
		Parent = content,
	})
	sticker(
		chip,
		{ top = Palette.StickerGreenTop, bottom = Palette.StickerGreen2End },
		chipSpec.border,
		chipSpec.radius,
		chipSpec.lip,
		chipSpec.inset
	)
	local chipFace: Frame = Create("Frame", {
		Name = "FaceRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -chipSpec.lip),
		ZIndex = 2,
		Parent = chip,
	})
	local price = robuxRow(c, chipFace, chipSpec.coinPx, chipSpec.gap, chipSpec.textRole)
	fitLabel(price, CHIP_KIND)
	-- H:343-345: the name over the line, gap 4, between the tile and the chip (flex 1).
	local textLeft = left + PASSES.tile.px + PASSES.gap
	local textW = math.max(1, width - textLeft - PASSES.gap - chipW - right)
	local text: Frame = Create("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, textLeft, 0.5, 0),
		Parent = content,
	})
	Theme.list(Enum.FillDirection.Vertical, PASSES.textGap, text, Enum.HorizontalAlignment.Left)
	local name = Theme.label({
		Name = "Name",
		Text = texts.name,
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = text,
	}, PASS_NAME_KIND)
	Theme.stickerText(name, PASSES.nameRole)
	fitLabel(name, PASS_NAME_KIND, textW)
	local desc = Theme.label({
		Name = "Line",
		Text = texts.desc,
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = text,
	}, PASS_DESC_KIND)
	Theme.stickerText(desc, PASSES.descRole)
	fitLabel(desc, PASS_DESC_KIND, textW)
	text.Size = UDim2.fromOffset(textW, name.Size.Y.Offset + PASSES.textGap + desc.Size.Y.Offset)
	local feel: Button.DecorateOptions = { fx = "card", visual = visual, pivotPx = CARD_LIP / 2 }
	c:add(Button.decorate(root, feel))
	c:add(root.Activated:Connect(comingSoon)) -- no pass product yet (§6.11)
	root.Parent = parent
	table.insert(passCards, { key = pass.key, root = root, rise = rise, chip = chip, price = price })
end

-- H:355-363: a coin pack card (cream, the badges, the picture bobbing, the amount, the green Robux price bar).
local function buildPack(c: Cleanup.Cleanup, parent: Instance, pack: { [string]: any }, order: number, width: number)
	local root: Frame = Create("Frame", {
		Name = "Shop_Pack_" .. pack.key,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	})
	c:add(root)
	local rise = holder("SD_Rise", root)
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = rise,
	})
	sticker(
		face,
		{ top = Palette.StickerPackTop, bottom = Palette.StickerPackEnd },
		PACKS.border,
		PACKS.radius,
		PACKS.lip,
		PACKS.inset
	)
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -PACKS.lip),
		ZIndex = 2,
		Parent = rise,
	})
	Create("UIPadding", {
		PaddingTop = UDim.new(0, PACKS.border + PACKS.padTop),
		PaddingLeft = UDim.new(0, PACKS.border + PACKS.padX),
		PaddingRight = UDim.new(0, PACKS.border + PACKS.padX),
		PaddingBottom = UDim.new(0, PACKS.border + PACKS.padBottom),
		Parent = content,
	})
	-- H:361-362 from the bottom up: the price bar, the amount; the picture fills the rest (flex 1, min 70).
	local buy = Button.new({
		name = "Shop_Bundle_" .. pack.key .. "Button",
		text = Strings.shop.soon,
		kind = "primary",
		accent = "greenChip", -- H:362: #A6F796 -> #38C150
		height = PACKS.priceBar,
		border = PACKS.priceBorder,
		radius = PACKS.priceRadius,
		lip = PACKS.priceLip,
		stops = 2,
		highlight = { px = PACKS.priceInset.px, a = PACKS.priceInset.alpha },
		textRole = PACKS.priceRole,
		keycap = "",
		width = width - 2 * (PACKS.border + PACKS.padX),
		parent = content,
		onActivated = function()
			local card = packCards[pack.key]
			if card and card.ready then
				promptBundle(pack.key)
			else
				comingSoon()
			end
		end,
	})
	c:add(buy)
	buy.root.AnchorPoint = Vector2.new(0, 1)
	buy.root.Position = UDim2.fromScale(0, 1)
	local buyLine = buy.visual:FindFirstChild("Line", true)
	if buyLine then
		local list = buyLine:FindFirstChildOfClass("UIListLayout")
		if list then
			list.Padding = UDim.new(0, PACKS.priceGap)
		end
		c:add(IconGlyph.image("img.icon.robux", {
			name = "Robux",
			sizePx = PACKS.robuxPx,
			layoutOrder = 2,
			parent = buyLine,
		}))
	end
	local amountKind = roleKind(PACKS.amountRole)
	local amountH = math.ceil(Theme.lineHeight(amountKind))
	local amount = Theme.label({
		Name = "Amount",
		Text = Format.coins(pack.amount),
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(PACKS.priceBar + PACKS.priceLip + PACKS.innerGap)),
		Size = UDim2.new(1, 0, 0, amountH),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Parent = content,
	}, amountKind)
	Theme.stickerText(amount, PACKS.amountRole)
	local art: Frame = Create("Frame", {
		Name = "Art",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -(PACKS.priceBar + PACKS.priceLip + 2 * PACKS.innerGap + amountH)),
		Parent = content,
	})
	local bob = holder("SD_Bob", art)
	bob.Size = UDim2.fromOffset(PACKS.iconPx, PACKS.iconPx)
	picture(bob, pack.image, PACKS.iconPx, "Picture")
	idle(c, bob, "bob", PACKS.bobS)
	-- H:356-357: the +n% badge (right -8, top -12, 8°) and BEST (left -8, top -12, -8°).
	if pack.bonus then
		local b = badge(rise, "Bonus", pack.bonus, Palette.StickerRedTop, Palette.StickerRedEnd, BADGE.pack)
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.new(1, -BADGE.pack.offsetX, 0, -BADGE.pack.offsetY)
		b.Rotation = BADGE.pack.rot
		b.ZIndex = 4
	end
	if pack.best then
		local b =
			badge(rise, "Best", Strings.shop.best, Palette.StickerPurpleBarTop, Palette.StickerPurpleBarEnd, BADGE.pack)
		b.Position = UDim2.fromOffset(BADGE.pack.offsetX, -BADGE.pack.offsetY)
		b.Rotation = -BADGE.pack.rot
		b.ZIndex = 4
	end
	root.Parent = parent
	packCards[pack.key] = { key = pack.key, root = root, rise = rise, buy = buy, ready = false }
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local design = Config.UI.Sticker.window.kinds.shop
	local root = Theme.window({
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(design.width, design.height + Config.UI.Sticker.lip.window),
		Parent = parent,
	}, WINDOW_KIND, WINDOW_PAD)
	c:add(root)
	fitScale = Create("UIScale", { Name = "SD_Fit", Parent = root })
	local picker = buildTabs(c) -- gear step 3: SHOP | GEAR at the band's right end
	tabs = picker
	Theme.headerTab(root, Strings.shop.title, { extra = picker.root :: GuiObject })
	local close = Button.new({
		name = "Shop_CloseButton",
		text = Strings.common.close,
		kind = "close",
		parent = root,
		sound = false, -- closing plays ui.back (UIController.close, reason "button")
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	Theme.attachClose(root, close.root)
	close.root.Modal = true
	c:add(close)
	closeButton = close
	local chrome = Theme.fitWindow(root, 1)

	-- H:317: the body inside the window's content box (the design's padding 20 24 24 inside the 5 px border).
	local inset = BODY.padSide - WINDOW_PAD + WINDOW_BORDER
	local bottomInset = BODY.padBottom - WINDOW_PAD + WINDOW_BORDER
	local bodyW = design.width - 2 * WINDOW_PAD - 2 * inset
	local bodyH = design.height - chrome.top - WINDOW_PAD - bottomInset
	local body: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(inset, 0),
		Size = UDim2.fromOffset(bodyW, bodyH),
		Parent = root,
	})
	buildFeatured(c, body, BODY.featuredWidth, bodyH + FEATURED.lip)

	-- H:337-366: the right column (gap 12): GAME PASSES, the pass grid, COINS, the pack grid (flex 1).
	local columnLeft = BODY.featuredWidth + BODY.gap
	local columnW = bodyW - columnLeft
	local column: Frame = Create("Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(columnLeft, 0),
		Size = UDim2.fromOffset(columnW, bodyH),
		Parent = body,
	})
	Theme.list(Enum.FillDirection.Vertical, SHOP.sections.gap, column, Enum.HorizontalAlignment.Left)
	local headH = math.ceil(Theme.lineHeight(HEAD_KIND))
	sectionHead(column, "PassesHead", Strings.shop.sectionPasses, 1)
	local passW = math.floor((columnW - SHOP.sections.cellGap) / PASSES.columns)
	local passRows = math.ceil(#PASS_LIST / PASSES.columns)
	local passesH = passRows * (PASSES.height + CARD_LIP)
		+ (passRows - 1) * Layout.lipGap(SHOP.sections.cellGap, CARD_LIP)
	local passes: Frame = Create("Frame", {
		Name = "Passes",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(columnW, passesH),
		LayoutOrder = 2,
		Parent = column,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(passW, PASSES.height + CARD_LIP),
		CellPadding = UDim2.fromOffset(SHOP.sections.cellGap, Layout.lipGap(SHOP.sections.cellGap, CARD_LIP)),
		FillDirectionMaxCells = PASSES.columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = passes,
	})
	for index, pass in PASS_LIST do
		buildPass(c, passes, pass, index, passW)
	end
	sectionHead(column, "CoinsHead", Strings.shop.sectionCoins, 3)
	local packsH = math.max(0, bodyH - 2 * headH - passesH - 3 * SHOP.sections.gap)
	local packW = math.floor((columnW - (PACKS.columns - 1) * PACKS.gap) / PACKS.columns)
	local packs: Frame = Create("Frame", {
		Name = "Packs",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(columnW, packsH),
		LayoutOrder = 4,
		Parent = column,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(packW, packsH),
		CellPadding = UDim2.fromOffset(PACKS.gap, 0),
		FillDirectionMaxCells = PACKS.columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = packs,
	})
	for index, pack in PACKS.list do
		buildPack(c, packs, pack, index, packW)
	end
	shopPage = column -- gear step 3: the SHOP tab's page; GEAR's sits in the same place
	gearPage = buildGearPage(c, body, columnLeft, columnW, bodyH)
	incomePage = buildCardPage( -- INCOME step 2
		c,
		body,
		columnLeft,
		columnW,
		bodyH,
		PAGE_INCOME,
		Strings.income.section,
		{ "coins", "all" },
		REMOTE_INCOME,
		incomeCards
	)
	setPage(page)

	panel = root
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout))
	c:add(UIController.LayoutChanged:connect(applyLayout))
	applyLayout()
	refresh()
	return root
end

-- H:318, H:328, H:333: the featured card's rise on open, the Dragon's sdFloat 3 s and BUY's sdPulse 1.6 s.
local function startIdle(c: Cleanup.Cleanup)
	local f = featured
	if f == nil then
		return
	end
	local rise = FEATURED.rise
	c:add(Scheduler.add(Tweens.keyframes(f.root, rise.frames :: any, { ms = rise.ms, curve = rise.curve }), "render"))
	idle(c, f.art, "float", FEATURED.art.floatS)
	idle(c, f.pulse, "pulse", FEATURED.buy.pulseS)
end

-- Public --------------------------------------------------------------------------------------------------------------

function ShopController.refresh()
	local ok, err = pcall(function(): any
		refresh()
		return nil
	end)
	if not ok then
		log:error("refresh failed:", err)
	end
end

-- Opens the shop ({tab = "gear"} on the GEAR tab, gear step 3; {tab = "income"} on INCOME, INCOME step 2; else SHOP).
-- Returns UIController.open's result.
function ShopController.open(params: { [string]: any }?): boolean
	return UIController.open(SCREEN, params)
end

-- Small table for Studio debug hooks.
function ShopController.debugState(): { [string]: any }
	local passes, packs = {}, {}
	for _, card in passCards do
		table.insert(passes, card.key)
	end
	for _, pack in PACKS.list do
		local card = packCards[pack.key]
		if card then
			table.insert(packs, { key = pack.key, state = card.buy:getState() })
		end
	end
	local fit = lastFit
	return {
		built = panel ~= nil,
		open = UIController.isOpen(SCREEN),
		passes = passes,
		packs = packs,
		promptingKey = promptingKey,
		featured = if featured then (if featured.owned.Visible then "owned" else "soon") else nil,
		page = page, -- gear step 3
		gear = (function(): { any }
			local list = {}
			for _, cards in { gearCards, incomeCards } do -- INCOME step 2: then coins, all
				for _, card in cards do
					local view = card.view
					if view then
						table.insert(list, { line = card.line, name = view.name, state = view.state })
					end
				end
			end
			return list
		end)(),
		fit = if fit then { k = fit.k, width = fit.width, height = fit.height } else nil,
	}
end

-- Lifecycle -----------------------------------------------------------------------------------------------------

function ShopController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(UIController.registerScreen(SCREEN, {
		build = build,
		onOpen = function(params: any?)
			local oc = Cleanup.new()
			if openCleanup then
				openCleanup:clean()
			end
			openCleanup = oc
			startIdle(oc)
			applyLayout()
			refresh()
			riseCards()
			-- gear step 3 / INCOME step 2: the tab asked for, else SHOP (the HUD's Shop and INCOME stickers).
			setPage(if type(params) == "table" and type(params.tab) == "string" then params.tab else PAGE_SHOP)
		end,
		onClose = function()
			if openCleanup then
				openCleanup:clean()
				openCleanup = nil
			end
		end,
		primary = function(): GuiObject?
			return if closeButton then closeButton.root else nil
		end,
	}))
	c:add(WorldBinder.registerStand(COUNTER_TAG, function()
		UIController.open(SCREEN)
	end))
	for _, field in { "owned", "dataStatus", "monetization", "gear", "coins", "pen" } do
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
		table.clear(passCards)
		table.clear(packCards)
		table.clear(prices)
		panel, fitScale, closeButton, featured, lastFit = nil, nil, nil, nil, nil
		table.clear(gearCards) -- gear step 3
		tabs, shopPage, gearPage, gearPower, gearBusy, page = nil, nil, nil, nil, nil, PAGE_SHOP
		table.clear(incomeCards) -- INCOME step 2
		incomePage = nil
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
