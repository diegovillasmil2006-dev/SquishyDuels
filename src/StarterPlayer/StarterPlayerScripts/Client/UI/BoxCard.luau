--!strict
-- BoxCard (client only). UI FINAL R7 (plan work/ui/PLAN.md R7 G7.15-G7.19, PR20, PR22, P11; `H:n` = "Squishy Duels
-- HUD.dc.html" line n, `lib:n` = uploads/hud-lib.js line n; numbers in Config.UI.Boxes): one of the Boxes window's
-- design cards (H:264-278), drawn into a cell BoxController places:
--   local card = BoxCard.new({ boxId = "snack", index = 1, parent = row, onOpen = fn, onRetry = fn, scale = fn })
--   card:layout(width, height, column, plate, tiles)   card:paint(view, owned)   card:rise()   card:destroy()
-- The card: the purple face (StickerCardTop -> StickerCardBottom, H:264: border 4 inside, radius 24, the inset 3 at
-- .12, the 6 px lip), column gap 12, padding 14, rising in with sdRise (.5 s, card i after i x 90 ms). Its column:
--   * the plate (H:265-267): 178 high (BoxFormat.cardLayout shrinks or hides it on a short body), border 4, radius 18,
--     the inset 5 at .4, the box's plate gradient (lib:44-46), the rays (img.fx.rays 520 px at (50%, 55%), .28, one turn
--     in 18 s), the box art 176 (img.nav.boxes / img.box.sweet / img.box.treat; the tinted gift while it has no id)
--     floating (sdFloat 2.8 s, card i after i x .5 s) with its drop shadow (0 8 0 at .3);
--   * the name (H:269: the boxName role);
--   * one odds row per rarity (H:271, BoxFormat.cardOdds): the pill (96 wide, 22 border-box, padding 2 8 0, border 3,
--     the rarity's colour, capitals: the rarityPill role), the bar (12 border-box, border 3 StickerInkDeep, trough
--     StickerTrough, the fill in the rarity's colour with its 2 px top highlight at .4, max(6, p)% wide: no transition)
--     and the exact percent (the oddsPct role, right; its column at least 40, wider when "80.00%" needs it: §6.10 shows
--     every chance exactly);
--   * the toy tiles at the bottom (H:273-274): 42, border 3, radius 12, StickerToyTile, the toy 40 (a silhouette when not
--     owned), rarest first, as many as fit (BoxFormat.tilesThatFit; hidden on a short body);
--   * OPEN (H:276-278): the green 62 + lip 5, "OPEN" (the boxOpen role) and the price pill (36 high, padding 0 10 0 4, gap
--     4, border 3, full radius, ink at .45, the coin 28, the price in the boxPrice role: white, or StickerPriceShort when
--     the Coins do not cover it: P11's off state, its press ui.error + the shake, then the caller's deny); a free-only box
--     shows box.freeOnly instead (FD5); "unknown" shows Try again; every other state OPEN disabled with its reason.
--   * Pens3 phase 5 (D1:235), a restricted account (the fixed order, never random): OPEN as above and, in the toy
--     tiles' row, the next squishy it gives (view.nextText, box.nextItem "Next in this box: Toast"; a stand-in in the
--     card's free-only line role until Diego draws it, measured with Theme.textBoundsAt at spec.scale()).
--   * `side`: the room right of the column (the selected card's stats well, PR20; BoxController fills it).
-- No hover on the card (only on its buttons). Stable names: Boxes_Box_<id> (the cell), Boxes_OpenButton,
-- Boxes_RetryButton, NextItem (the stand-in label).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Art.Palette)
local Rarity = require(Shared.Rarity)
local RarityStyle = require(Shared.Art.RarityStyle)
local Strings = require(Shared.Strings)

local UI = script.Parent
local Client = UI.Parent
local BoxFormat = require(UI.BoxFormat)
local Button = require(UI.Components.Button)
local CoinIcon = require(UI.Components.CoinIcon)
local Create = require(UI.Create)
local IconGlyph = require(UI.Components.IconGlyph)
local Layout = require(UI.Layout)
local SquishyImage = require(UI.Components.SquishyImage)
local StaticIcon = require(UI.Components.StaticIcon)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type Spec = {
	boxId: string,
	index: number, -- 1-based: the rise's and the float's delays
	parent: Instance,
	onOpen: () -> (), -- OPEN pressed (live or off)
	onRetry: () -> (),
	scale: (() -> number)?, -- the UI scale the card is drawn at (its UIScale; Theme.textBoundsAt), default 1
}

export type BoxCard = {
	boxId: string,
	root: Frame,
	column: Frame,
	side: Frame,
	open: Button.Button,
	retry: Button.Button,
	layout: (self: BoxCard, width: number, height: number, column: number, plate: number, tiles: boolean) -> (),
	paint: (self: BoxCard, view: BoxFormat.OpenView, owned: { [string]: any }?) -> (),
	rise: (self: BoxCard) -> (),
	parts: (self: BoxCard) -> BoxFormat.CardParts,
	destroy: (self: BoxCard) -> (),
}

-- Constants

local B = Config.UI.Boxes
local CARD = B.card
local ODDS = B.odds
local OPEN = B.open
local TOYS = B.toys
local LIP = Config.UI.Sticker.lip.button
local WHITE = Color3.new(1, 1, 1)
local ART_KEYS = { snack = "img.nav.boxes", sweet = "img.box.sweet", treat = "img.box.treat" } :: { [string]: string }
local PLATES = {
	snack = { Palette.StickerBoxSnackTop, Palette.StickerBoxSnackEnd },
	sweet = { Palette.StickerBoxSweetTop, Palette.StickerBoxSweetEnd },
	treat = { Palette.StickerFeaturedTop, Palette.StickerBoxTreatEnd },
} :: { [string]: { Color3 } }
local TINTS = { sweet = Palette.BoxTintSweet, treat = Palette.BoxTintTreat } :: { [string]: Color3 }
local GIFT_BOX = "gift_box"

-- Module table

local BoxCard = {}

-- Private

-- A design surface (the ShopController helper's shape): `top` -> `bottom`, the ink border inside, the inset
-- highlight, the lip under the face.
local function sticker(
	frame: GuiObject,
	top: Color3,
	bottom: Color3,
	border: number,
	radius: number,
	lip: number,
	inset: { px: number, alpha: number }?
)
	local bands = Layout.stickerBands(border, if inset then inset.px else 0, 0, lip)
	Theme.foam(frame, {
		radius = radius,
		stroke = border,
		inner = true,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = {
			face = top,
			faceEnd = bottom,
			top = if inset then top:Lerp(WHITE, inset.alpha) else top,
			drop = Theme.Colors.inkUI,
		},
	})
end

local function rarityBase(rarity: string): Color3
	local style = RarityStyle.get(rarity)
	return if style then style.ui.base or style.color else Theme.Colors.inkUI
end

local function measured(text: string, role: string): Vector2
	local kind = (Theme.Sticker.text[role] :: any).kind
	local bounds = Theme.textBounds(text, kind)
	return Vector2.new(math.ceil(bounds.X) + 6, math.ceil(bounds.Y) + 2)
end

local function roleLabel(
	parent: Instance,
	name: string,
	text: string,
	role: string,
	align: Enum.TextXAlignment
): TextLabel
	local size = measured(text, role)
	local label = Theme.label({
		Name = name,
		Text = text,
		Size = UDim2.fromOffset(size.X, size.Y),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		TextXAlignment = align,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = parent,
	}, (Theme.Sticker.text[role] :: any).kind)
	Theme.stickerText(label, role)
	return label
end

-- Public: pure

-- The box art's picture key (H:267, H:458: also the confirm dialog's medallion, PR13).
function BoxCard.artKey(boxId: string): string
	return ART_KEYS[boxId] or ART_KEYS.snack
end

-- The odds rows' percent column (base px): the design's 40, or the widest exact percent of the box when wider.
function BoxCard.pctWidth(boxId: string): number
	local widest = ODDS.pct
	for _, row in BoxFormat.cardOdds(boxId) do
		widest = math.max(widest, measured(row.text, B.oddsPctRole).X)
	end
	return widest
end

-- One odds row's height (base px): the pill's 22, or its 16 px label's line with its padding and borders (PR2).
function BoxCard.rowHeight(): number
	local pill = B.oddsPill
	local line = Theme.lineHeight((Theme.Sticker.text[pill.role] :: any).kind)
	return math.max(ODDS.pillHeight, math.ceil(line) + pill.padTop + 2 * pill.border)
end

-- Public: component

function BoxCard.new(spec: Spec): BoxCard
	local c = Cleanup.new()
	local boxId = spec.boxId
	local self = {} :: BoxCard
	self.boxId = boxId

	local root: Frame = Create("Frame", {
		Name = "Boxes_Box_" .. boxId,
		BackgroundTransparency = 1,
		Parent = spec.parent,
	})
	c:add(root)
	-- sdRise moves and scales the card about its centre (H:31): the pose holder fills the cell.
	local pose: Frame = Create("Frame", {
		Name = "Pose",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = pose,
	})
	sticker(face, Palette.StickerCardTop, Palette.StickerCardBottom, CARD.border, CARD.radius, CARD.lip, CARD.inset)
	local inner = CARD.border + CARD.pad
	local column: Frame = Create("Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(inner, inner),
		ZIndex = 2,
		Parent = pose,
	})
	local side: Frame = Create("Frame", {
		Name = "Side",
		BackgroundTransparency = 1,
		ZIndex = 2,
		Visible = false,
		Parent = pose,
	})

	-- H:265-267: the plate
	local plate: Frame = Create("Frame", {
		Name = "Plate",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, CARD.plate),
		Parent = column,
	})
	local stops = PLATES[boxId] or PLATES.snack
	sticker(plate, stops[1], stops[2], CARD.plateBorder, CARD.plateRadius, 0, CARD.plateHighlight)
	local clip: Frame = Create("Frame", {
		Name = "Clip",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(CARD.plateBorder, CARD.plateBorder),
		Size = UDim2.new(1, -2 * CARD.plateBorder, 1, -2 * CARD.plateBorder),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = plate,
	})
	Theme.corner(CARD.plateRadius - CARD.plateBorder, clip)
	local rays = CARD.rays
	Theme.rays(clip, "img.fx.rays", rays.px, rays.alpha, rays.spinS, rays.centreY)
	local art: Frame = Create("Frame", {
		Name = "SD_Float",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD.art.px, CARD.art.px),
		ZIndex = 3,
		Parent = clip,
	})
	local artScale: UIScale = Create("UIScale", { Parent = art })
	local key = ART_KEYS[boxId] or ART_KEYS.snack
	if AssetTable.image(key) then
		local picture = IconGlyph.image(key, {
			name = "Art",
			sizePx = CARD.art.px,
			shadow = { px = CARD.art.shadow.px, alpha = CARD.art.shadow.alpha },
			parent = art,
		})
		picture.ZIndex = 3
	else
		-- the tinted gift while the picture has no id
		local gift = StaticIcon.new({ name = "Art", squishyId = GIFT_BOX, sizePx = CARD.art.px, parent = art })
		gift.root.ImageColor3 = TINTS[boxId] or WHITE
		c:add(gift)
	end
	local float =
		UiIdle.add(art, "float", { periodS = CARD.art.floatS, delayS = (spec.index - 1) * CARD.art.delayStepS })
	if float then
		c:add(function()
			float:remove()
		end)
	end

	-- H:269: the name
	local name = roleLabel(column, "Name", BoxFormat.boxName(boxId), CARD.nameRole, Enum.TextXAlignment.Left)

	-- H:270-272: the odds rows
	local oddsFrame: Frame = Create("Frame", { Name = "Odds", BackgroundTransparency = 1, Parent = column })
	local rowHeight = BoxCard.rowHeight()
	local pctWidth = BoxCard.pctWidth(boxId)
	local odds = BoxFormat.cardOdds(boxId)
	local pillSpec = B.oddsPill
	for index, data in odds do
		local row: Frame = Create("Frame", {
			Name = "Odds_" .. data.rarity,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, (index - 1) * (rowHeight + ODDS.rowGap)),
			Size = UDim2.new(1, 0, 0, rowHeight),
			Parent = oddsFrame,
		})
		local fill = rarityBase(data.rarity)
		local pill: Frame = Create("Frame", {
			Name = "Pill",
			BorderSizePixel = 0,
			Size = UDim2.new(0, ODDS.pill, 1, 0),
			Parent = row,
		})
		Theme.foam(pill, { radius = 999, stroke = pillSpec.border, inner = true, colors = { face = fill } })
		local info = Rarity.get(data.rarity)
		local pillLabel = Theme.label({
			Name = "Label",
			Text = string.upper(if info then Strings.resolve(info.labelKey) or data.rarity else data.rarity),
			Position = UDim2.fromOffset(0, pillSpec.padTop),
			Size = UDim2.new(1, 0, 1, -pillSpec.padTop),
			AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 2,
			Parent = pill,
		}, (Theme.Sticker.text[pillSpec.role] :: any).kind)
		Theme.stickerText(pillLabel, pillSpec.role)
		local bar: Frame = Create("Frame", {
			Name = "Bar",
			BackgroundColor3 = Palette.StickerTrough,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, ODDS.pill + ODDS.gap, 0.5, 0),
			Size = UDim2.new(1, -(ODDS.pill + 2 * ODDS.gap + pctWidth), 0, ODDS.bar),
			ClipsDescendants = true,
			Parent = row,
		})
		Theme.corner(999, bar)
		local barStroke = Theme.stroke(Palette.StickerInkDeep, B.oddsBar.border, bar)
		pcall(function()
			(barStroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
		end)
		local border = B.oddsBar.border
		local barFill: Frame = Create("Frame", {
			Name = "Fill",
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(border, border),
			Size = UDim2.new(data.share, -2 * border * data.share, 1, -2 * border),
			Parent = bar,
		})
		local hl = B.oddsBar.fillHighlight
		Theme.foam(
			barFill,
			{ radius = 999, stroke = 0, top = hl.px, colors = { face = fill, top = fill:Lerp(WHITE, hl.alpha) } }
		)
		local pct = roleLabel(row, "Pct", data.text, B.oddsPctRole, Enum.TextXAlignment.Right)
		pct.AnchorPoint = Vector2.new(1, 0.5)
		pct.Position = UDim2.fromScale(1, 0.5)
		pct.Size = UDim2.fromOffset(pctWidth, pct.Size.Y.Offset)
	end
	local oddsHeight = #odds * rowHeight + math.max(0, #odds - 1) * ODDS.rowGap

	-- H:273-274: the toy tiles (rebuilt by paint when the owned set or the count changes)
	local tilesFrame: Frame = Create("Frame", { Name = "Toys", BackgroundTransparency = 1, Parent = column })
	local tileImages: { SquishyImage.SquishyImage } = {}
	local tileCount = 0
	local tileKey = ""

	-- H:276-278: OPEN, Try again, the shop button (PR22) and the free-only line, in one slot at the bottom
	local slot: Frame = Create("Frame", { Name = "Open", BackgroundTransparency = 1, Parent = column })
	local width = 200
	local open = Button.new({
		name = "Boxes_OpenButton",
		text = Strings.box.open,
		kind = "primary",
		width = width,
		height = OPEN.face,
		textRole = OPEN.labelRole,
		keycap = "", -- reserves the row: then the price pill
		clickSound = false, -- H:276 data-snd none (the dialog opens silently, RL8)
		parent = slot,
		onActivated = spec.onOpen,
	})
	c:add(open)
	local priceText = BoxFormat.costText(boxId) or ""
	local priceSize = measured(priceText, OPEN.priceRole)
	local pricePill: Frame = Create("Frame", {
		Name = "Price",
		BackgroundColor3 = Theme.Colors.inkUI,
		BackgroundTransparency = 1 - OPEN.priceAlpha,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(
			2 * OPEN.priceBorder + OPEN.pricePadLeft + OPEN.coin + OPEN.priceGap + priceSize.X + OPEN.pricePadRight,
			OPEN.priceH
		),
		LayoutOrder = 60,
	})
	Theme.corner(999, pricePill)
	local pillStroke = Theme.stroke(Theme.Colors.inkUI, OPEN.priceBorder, pricePill)
	pcall(function()
		(pillStroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	local coin = CoinIcon.new({ name = "Coin", sizePx = OPEN.coin, parent = pricePill })
	c:add(coin)
	coin.root.AnchorPoint = Vector2.new(0, 0.5)
	coin.root.Position = UDim2.new(0, OPEN.priceBorder + OPEN.pricePadLeft, 0.5, 0)
	local price = roleLabel(pricePill, "Price", priceText, OPEN.priceRole, Enum.TextXAlignment.Left)
	price.AnchorPoint = Vector2.new(0, 0.5)
	price.Position = UDim2.new(0, OPEN.priceBorder + OPEN.pricePadLeft + OPEN.coin + OPEN.priceGap, 0.5, 0)
	local line = open.visual:FindFirstChild("Line", true)
	if line then
		local list = line:FindFirstChildOfClass("UIListLayout")
		if list then
			list.Padding = UDim.new(0, OPEN.gap) -- H:276: gap 10
		end
		pricePill.Parent = line
	else
		pricePill.Parent = open.visual
	end
	pricePill.Visible = priceText ~= ""
	local retry = Button.new({
		name = "Boxes_RetryButton",
		text = Strings.common.tryAgain,
		kind = "primary",
		width = width,
		height = OPEN.face,
		parent = slot,
		onActivated = spec.onRetry,
	})
	c:add(retry)
	retry.root.Visible = false
	local freeSize = Theme.textBounds(Strings.box.freeOnly, (Theme.Sticker.text[OPEN.freeRole] :: any).kind, nil, width)
	local free = Theme.label({
		Name = "FreeOnly",
		Text = Strings.box.freeOnly,
		Size = UDim2.new(1, 0, 0, math.ceil(freeSize.Y) + 2),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = slot,
	}, (Theme.Sticker.text[OPEN.freeRole] :: any).kind)
	Theme.stickerText(free, OPEN.freeRole)
	-- Pens3 phase 5 (see the header): the fixed order's next squishy, a stand-in in the free-only line's role, in the
	-- toy tiles' row (placeNext); no text = hidden.
	local freeKind: Theme.TextKind = (Theme.Sticker.text[OPEN.freeRole] :: any).kind
	local nextLabel = Theme.label({
		Name = "NextItem",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Visible = false,
		Parent = column,
	}, freeKind)
	Theme.stickerText(nextLabel, OPEN.freeRole)

	local shown: { column: number, height: number, plate: number, tiles: boolean } =
		{ column = 0, height = 0, plate = CARD.plate, tiles = true }
	local lastOwned: { [string]: any }? = nil

	-- The next squishy's line in the toy tiles' row, above OPEN (it grows up when it needs more than the row), sized
	-- at the drawn size: text under a UIScale lays out wider than Theme.textBounds says, and a wrapped label too
	-- small draws nothing.
	local function placeNext()
		local text = nextLabel.Text
		local on = text ~= ""
		nextLabel.Visible = on
		tilesFrame.Visible = shown.tiles and not on
		if on then
			local scale = if spec.scale then spec.scale() else 1
			local height = math.max(TOYS.tile, Theme.textBoundsAt(text, freeKind, shown.column, scale).Y + 2)
			local bottom = shown.height - OPEN.face - LIP - CARD.gap
			nextLabel.Position = UDim2.fromOffset(0, bottom - height)
			nextLabel.Size = UDim2.fromOffset(shown.column, height)
		end
	end

	local function buildTiles()
		local count = if shown.tiles then BoxFormat.tilesThatFit(shown.column) else 0
		local tiles = BoxFormat.toyTiles(boxId, lastOwned, count)
		local keyNow = ""
		for _, tile in tiles do
			keyNow ..= tile.id .. (if tile.owned then "+" else "-")
		end
		if keyNow == tileKey and count == tileCount then
			return
		end
		tileKey, tileCount = keyNow, count
		for _, image in tileImages do
			image:destroy()
		end
		table.clear(tileImages)
		for _, child in tilesFrame:GetChildren() do
			child:Destroy()
		end
		for index, tile in tiles do
			local frame: Frame = Create("Frame", {
				Name = "Toy_" .. tile.id,
				BackgroundColor3 = Palette.StickerToyTile,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset((index - 1) * (TOYS.tile + TOYS.gap), 0),
				Size = UDim2.fromOffset(TOYS.tile, TOYS.tile),
				Parent = tilesFrame,
			})
			Theme.corner(TOYS.radius, frame)
			local stroke = Theme.stroke(Theme.Colors.inkUI, TOYS.border, frame)
			pcall(function()
				(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
			end)
			local image = SquishyImage.new(tile.id, { size = TOYS.px, owned = tile.owned, parent = frame :: Instance })
			image.root.AnchorPoint = Vector2.new(0.5, 0.5)
			image.root.Position = UDim2.fromScale(0.5, 0.5)
			table.insert(tileImages, image)
		end
	end

	function self.layout(
		_: BoxCard,
		cellWidth: number,
		cellHeight: number,
		columnWidth: number,
		plateHeight: number,
		tiles: boolean
	)
		root.Size = UDim2.fromOffset(cellWidth, cellHeight)
		local innerHeight = cellHeight - 2 * inner - CARD.lip
		column.Size = UDim2.fromOffset(columnWidth, innerHeight)
		side.Position = UDim2.fromOffset(inner + columnWidth + CARD.gap, inner)
		side.Size = UDim2.fromOffset(math.max(0, cellWidth - 2 * inner - columnWidth - CARD.gap), innerHeight)
		shown.column, shown.height, shown.plate, shown.tiles = columnWidth, innerHeight, plateHeight, tiles
		-- top to bottom: the plate, the name, the odds; the tiles and OPEN at the bottom (H:273: margin-top auto)
		local y = 0
		plate.Visible = plateHeight > 0
		if plateHeight > 0 then
			plate.Size = UDim2.new(1, 0, 0, plateHeight)
			artScale.Scale = math.min(1, (plateHeight - 2 * CARD.plateBorder) / CARD.art.px)
			y += plateHeight + CARD.gap
		end
		name.Position = UDim2.fromOffset(0, y)
		name.Size = UDim2.fromOffset(columnWidth, name.Size.Y.Offset)
		y += name.Size.Y.Offset + CARD.gap
		oddsFrame.Position = UDim2.fromOffset(0, y)
		oddsFrame.Size = UDim2.fromOffset(columnWidth, oddsHeight)
		local openHeight = OPEN.face + LIP
		slot.Position = UDim2.fromOffset(0, innerHeight - openHeight)
		slot.Size = UDim2.fromOffset(columnWidth, openHeight)
		for _, button in { open, retry } do
			button:setWidth(columnWidth)
		end
		tilesFrame.Visible = tiles
		tilesFrame.Position = UDim2.fromOffset(0, innerHeight - openHeight - CARD.gap - TOYS.tile)
		tilesFrame.Size = UDim2.fromOffset(columnWidth, TOYS.tile)
		buildTiles()
		placeNext()
	end

	function self.parts(_: BoxCard): BoxFormat.CardParts
		return {
			name = name.Size.Y.Offset,
			odds = oddsHeight,
			tiles = TOYS.tile,
			open = OPEN.face + LIP,
		}
	end

	function self.paint(_: BoxCard, view: BoxFormat.OpenView, owned: { [string]: any }?)
		lastOwned = owned
		local kind = view.kind
		local freeOnly = kind == "freeOnly"
		open.root.Visible = view.button == "confirm"
		retry.root.Visible = view.button == "retry"
		free.Visible = freeOnly
		if view.button == "confirm" then
			local short = kind == "needCoins"
			local live = view.enabled or short
			open:setState(if live then "normal" else "disabled", if live then nil else view.reason or view.text)
			open:setOff(short)
			price.TextColor3 = if short then Palette.StickerPriceShort else WHITE
			price.Text = Format.coins(view.price)
		elseif view.button == "retry" then
			retry:setState(if view.enabled then "normal" else "disabled", view.reason)
		end
		buildTiles()
		nextLabel.Text = view.nextText or ""
		placeNext()
	end

	-- H:264: sdRise, card i after i x 90 ms (on every open).
	function self.rise(_: BoxCard)
		local rise = CARD.rise
		local track = Tweens.keyframes(pose, rise.frames :: any, {
			ms = rise.ms,
			delayMs = (spec.index - 1) * rise.stepMs,
			curve = rise.curve,
		})
		c:add(Scheduler.add(function(dt: number): boolean
			return track:step(dt, 0)
		end, "render"))
	end

	function self.destroy(_: BoxCard)
		for _, image in tileImages do
			image:destroy()
		end
		table.clear(tileImages)
		c:clean()
	end

	self.root = root
	self.column = column
	self.side = side
	self.open = open
	self.retry = retry
	return self
end

return BoxCard
