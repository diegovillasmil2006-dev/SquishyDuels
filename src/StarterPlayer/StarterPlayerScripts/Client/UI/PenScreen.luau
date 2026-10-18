--!strict
-- PenScreen (client only). Pens3 phase 6 (work/pens3/PLAN.md "PHASE 6"): the STAND-IN pen screen, built only from
-- Diego's existing parts until he draws the real one (PLACEHOLDERS in work/pens3/p6/NOTES.md): the UI FINAL R3 window
-- frame (Theme.window of the "squishies" kind, its band with the title and the close X), his squishy card face
-- (UI/CardFace) with the squishy's picture (Components/SquishyImage), Components/StatePill for the count line,
-- Components/LockIcon on a locked card and Components/Button for the actions. Numbers in Config.UI.Pen.screen.
-- It draws a PenFormat.View and reports taps; it decides nothing (PenController sends PenPlace / PenLock).
-- * Body (top to bottom): the count line (or the hint while picking a spot), a line under it (selectHint / toyEmpty),
--   then a scrolling list: "In your pen" and a card per open spot (its squishy, or Empty), "Toy Box" and a card per
--   Toy Box squishy (best first); the actions in a row pinned at the bottom (the thumb's reach on a phone).
-- * A card shows the squishy, its name, "+N/s" and "Lv N" (one line each, never wrapped: measured with
--   Theme.textBoundsAt at the screen's UIScale, cut with an ellipsis when longer than the card), a lock when locked,
--   and the selected one the card face's selected ring. Cards are kept by key (spot + squishy, or Toy Box squishy) and
--   reused, so a move rebuilds only the cards that changed.
-- * Gamepad: every card is a selectable button; primary() is the selected card, else the first card, else the X; a
--   render that removes the focused card moves the focus to primary().
-- * Pens3 phases 7-8 (sell, buy-back, fuse; stand-ins from the same parts, PLACEHOLDERS in work/pens3/p78/NOTES.md):
--   a third heading and grid, "Sold (you can buy them back)", with a card per live buy-back entry (its name, its price
--   in Coins and its minutes, plain text: no countdown; a tap calls onSold); the fuse inputs of a fuse confirm wear
--   the selected ring (view.marked); an action with `hold` reports its press and release (onHold, the controller
--   times it) instead of activating, and setHold(fraction?) shows the hold on Diego's progress bar
--   (Components/ProgressBar, holdBarPx tall) over the action row (nil hides it). statusRoot is the count line, where
--   the controller's celebrations start.
-- * Pens3 phase 9 (food and levels; stand-ins from the same parts, PLACEHOLDERS in work/pens3/p9/NOTES.md): a
--   "Buy food" heading and grid between the pen spots and the Toy Box, one card face per food on sale (its picture
--   when AssetTable img.food.<id> has an id, else none; its name, "{price} each", "You have N"; a tap calls onFood),
--   and the food row (view.foodLine, one line) pinned over the action row (and over the hold bar when it shows).
-- * Pens3 phase 11 (the shelf rows + the TOP spot; stand-ins from the same parts, PLACEHOLDERS in
--   work/pens3/p11/NOTES.md): an "On your shelf" heading and grid under the pen's spots (a card per open shelf spot)
--   and a "TOP spot" heading and grid with its one card once it is bought; their cards are the pen spots' (a tap
--   passes the slot: picking moves there). Wb (owner 2026-10-17): the shelf's BUY button is one more action in the row
--   (PenFormat's buyShelf, with nothing selected; the SHELF SPOTS sign stays), its reason on the reason row like
--   every disabled action's.
--   local s = PenScreen.new({ parent = gui, scale = UIController.scale, onCard = ..., onSold = ..., onAction = ...,
--       onHold = ..., onFood = ..., onClose = ... })
--   s:fit(screenPx);   s:render(view, busy);   s:setHold(fraction?);   s:primary();   s:destroy()

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable) -- pens3 phase 9: the food pictures
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Strings = require(Shared.Strings)

local UI = script.Parent
local Button = require(UI.Components.Button)
local CardFace = require(UI.CardFace)
local Create = require(UI.Create)
local Layout = require(UI.Layout)
local LockIcon = require(UI.Components.LockIcon)
local PenFormat = require(UI.PenFormat)
local ProgressBar = require(UI.Components.ProgressBar)
local SquishyImage = require(UI.Components.SquishyImage)
local StatePill = require(UI.Components.StatePill)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	parent: Instance,
	scale: () -> number, -- the ScreenGui's UIScale (UIController.scale)
	onCard: (slot: number?, itemId: number?) -> (),
	onSold: (itemId: number) -> (), -- pens3 phase 7: a sold card (its sold item id)
	onAction: (id: string) -> (),
	onHold: (id: string, down: boolean) -> (), -- pens3 phase 7: a hold action's press (true) and release (false)
	onFood: (foodId: string) -> (), -- pens3 phase 9: a BUY FOOD card
	onClose: () -> (),
}

export type PenScreen = {
	root: Frame,
	fit: (self: PenScreen, screenPx: Vector2) -> (),
	render: (self: PenScreen, view: PenFormat.View, busy: boolean) -> (),
	setHold: (self: PenScreen, fraction: number?) -> (),
	statusRoot: GuiObject,
	primary: (self: PenScreen) -> GuiObject?,
	destroy: (self: PenScreen) -> (),
}

type Card = {
	root: TextButton,
	face: CardFace.CardFace,
	lock: GuiObject?,
	lines: { TextLabel },
	cleanup: any, -- Cleanup.Cleanup
}

-- Constants

local S = Config.UI.Pen.screen
local STICKER = Config.UI.Sticker
local KIND = S.windowKind -- placeholder: Diego's Squishies window frame
local TEXT_KIND: Theme.TextKind = "Small"
local HEADING_KIND: Theme.TextKind = "Button"
local MARGIN_PX = 2
local SCREEN_TEXT = Strings.pen.screen
local HOLD_INPUTS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}
local HOLD_KEYS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.ButtonA] = true, [Enum.KeyCode.Return] = true }
local FOOD_PICTURE = "img.food." -- pens3 phase 9: + the food id (AssetTable)

-- Module table

local PenScreen = {}

-- Private

-- A one-line label sized to its text as drawn at `scale`, at most `maxWidth` base px wide (cut with an ellipsis).
local function line(label: TextLabel, text: string, kind: Theme.TextKind, scale: number, maxWidth: number)
	local bounds = Theme.textBoundsAt(text, kind, nil, scale)
	label.Text = text
	label.Size = UDim2.fromOffset(math.min(bounds.X + MARGIN_PX, maxWidth), bounds.Y + MARGIN_PX)
end

-- A label wrapped inside `width` base px, as tall as its lines drawn at `scale` (Theme.textBoundsAt: textBounds is a
-- few % short under a UIScale, and a wrapped label too small for its text draws nothing).
local function wrapped(label: TextLabel, text: string, kind: Theme.TextKind, scale: number, width: number)
	local bounds = Theme.textBoundsAt(text, kind, width, scale)
	label.Text = text
	label.Size = UDim2.fromOffset(width, bounds.Y + MARGIN_PX)
end

local function newLabel(name: string, kind: Theme.TextKind, parent: Instance, order: number?): TextLabel
	local label = Theme.label({
		Name = name,
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		LayoutOrder = order or 0,
		Parent = parent,
	}, kind)
	Theme.textOnWindow(label)
	return label
end

local function grid(name: string, order: number, parent: Instance): Frame
	local frame: Frame = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(S.cardSize.X, S.cardSize.Y),
		CellPadding = UDim2.fromOffset(S.cardGap, S.cardGap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	return frame
end

-- Public

function PenScreen.new(spec: Spec): PenScreen
	local cleanup = Cleanup.new()
	local root = Theme.window({
		Name = "Pen",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(STICKER.window.kinds[KIND].width, STICKER.window.kinds[KIND].height),
		Parent = spec.parent,
	}, KIND, S.bodyPad)
	cleanup:add(root)
	local padding = root:FindFirstChildOfClass("UIPadding") :: UIPadding
	padding.PaddingLeft = UDim.new(0, STICKER.border.heavy + S.bodyPad)
	padding.PaddingRight = UDim.new(0, STICKER.border.heavy + S.bodyPad)
	padding.PaddingBottom = UDim.new(0, STICKER.border.heavy + S.bodyPad + STICKER.lip.window)
	Theme.headerTab(root, SCREEN_TEXT.title)
	local close = Button.new({
		name = "Pen_CloseButton",
		text = Strings.common.close,
		kind = "close",
		parent = root,
		sound = false, -- closing plays ui.back (UIController.close, reason "button")
		onActivated = spec.onClose,
	})
	Theme.attachClose(root, close.root)
	close.root.Modal = true -- frees the cursor in shift lock / first person
	cleanup:add(close)

	local body: Frame = Create("Frame", { Name = "Body", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	body.Parent = root
	local status = StatePill.new({ name = "Pen_Status", text = "", parent = body })
	cleanup:add(status)
	local hint = newLabel("Pen_Hint", TEXT_KIND, body)
	hint.TextWrapped = true
	hint.TextTruncate = Enum.TextTruncate.None
	hint.Position = UDim2.fromOffset(0, STICKER.statePill.height + S.gap)
	local scroll: ScrollingFrame = Theme.scrollbar(Create("ScrollingFrame", {
		Name = "Pen_Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = body,
	}))
	Theme.list(Enum.FillDirection.Vertical, S.gap, scroll, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	Create(
		"UIPadding",
		{ PaddingTop = UDim.new(0, S.cardLift), PaddingRight = UDim.new(0, Theme.SCROLLBAR_PX), Parent = scroll }
	)
	local penHeading = newLabel("Pen_PenHeading", HEADING_KIND, scroll, 1)
	local penGrid = grid("Pen_Spots", 2, scroll)
	local shelfHeading = newLabel("Pen_ShelfHeading", HEADING_KIND, scroll, 3) -- pens3 phase 11
	local shelfGrid = grid("Pen_Shelf", 4, scroll)
	local topHeading = newLabel("Pen_TopHeading", HEADING_KIND, scroll, 5)
	local topGrid = grid("Pen_Top", 6, scroll)
	local foodHeading = newLabel("Pen_FoodHeading", HEADING_KIND, scroll, 7) -- pens3 phase 9
	local foodGrid = grid("Pen_Food", 8, scroll)
	local toyHeading = newLabel("Pen_ToyHeading", HEADING_KIND, scroll, 9)
	local toyGrid = grid("Pen_ToyBox", 10, scroll)
	local soldHeading = newLabel("Pen_SoldHeading", HEADING_KIND, scroll, 11) -- pens3 phase 7
	local soldGrid = grid("Pen_Sold", 12, scroll)
	local actionRow: Frame = Create("Frame", {
		Name = "Pen_Actions",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, S.buttonHeight + STICKER.lip.button),
		Parent = body,
	})
	Theme.list(Enum.FillDirection.Horizontal, S.gap, actionRow, Enum.HorizontalAlignment.Center)
	-- Pens3 phase 7: the hold's bar over the action row (hidden unless a hold action shows).
	local holdBar = ProgressBar.new({ name = "Pen_Hold", heightPx = S.holdBarPx, parent = body })
	cleanup:add(holdBar)
	holdBar.root.AnchorPoint = Vector2.new(0, 1)
	holdBar.root.Visible = false
	local holdShown = false
	-- Pens3 phase 9: the food row over the action row (and the hold bar).
	local foodRow = newLabel("Pen_FoodRow", TEXT_KIND, body)
	foodRow.AnchorPoint = Vector2.new(0, 1)
	-- Why the disabled actions can't run, wrapped over the action row: on the buttons it widened the row past the
	-- window (play look 2026-10-17, "Nothing to sell. Sell All keeps ...").
	local reasonRow = newLabel("Pen_ReasonRow", TEXT_KIND, body)
	reasonRow.AnchorPoint = Vector2.new(0, 1)
	reasonRow.TextWrapped = true
	reasonRow.TextTruncate = Enum.TextTruncate.None
	reasonRow.Visible = false

	local cards: { [string]: Card } = {}
	local buttons: { Button.Button } = {}
	local buttonIds = "" -- the action ids the buttons were built for
	local selectedKey: string? = nil
	local firstKey: string? = nil
	local screenPx: Vector2? = nil -- the last fit()

	-- The window for the screen size (UI FINAL R3: the design's size shrunk to fit, Layout.windowFit) and the body:
	-- the cards between the hint line and the action row.
	local function layout()
		local px = screenPx
		if px == nil then
			return
		end
		local fit = Layout.windowFit(px, KIND)
		root.Size = UDim2.fromOffset(fit.width, fit.height)
		Theme.fitWindow(root, fit.k)
		root.Position = UDim2.new(0.5, 0, 0.5, fit.shift)
		local top = STICKER.statePill.height + S.gap + (if hint.Visible then hint.Size.Y.Offset + S.gap else 0)
		local bottom = actionRow.Size.Y.Offset + S.gap + (if holdShown then S.holdBarPx + S.gap else 0)
		if reasonRow.Visible then
			reasonRow.Position = UDim2.new(0, 0, 1, -bottom)
			bottom += reasonRow.Size.Y.Offset + S.gap
		end
		foodRow.Position = UDim2.new(0, 0, 1, -bottom) -- pens3 phase 9
		bottom += foodRow.Size.Y.Offset + S.gap
		scroll.Position = UDim2.fromOffset(0, top)
		scroll.Size = UDim2.new(1, 0, 1, -(top + bottom))
		holdBar.root.Position = UDim2.new(0, 0, 1, -(actionRow.Size.Y.Offset + S.gap))
	end

	local function scale(): number
		local value = spec.scale()
		return if value > 0 then value else 1
	end

	local function cardWidth(): number
		return S.cardSize.X - 2 * S.cardPad
	end

	local function newCard(key: string, item: any?, slot: number?, sold: boolean?): Card
		local c = Cleanup.new()
		local button: TextButton = Create("TextButton", {
			Name = "Pen_Card_" .. key,
			Text = "",
			AutoButtonColor = false,
			Selectable = true,
		})
		c:add(button)
		local def = if item then Catalog.get(item.kind) else nil
		local face = CardFace.new(button, if def then def.rarity else "Common")
		c:add(face)
		local lines: { TextLabel } = {}
		local lock: GuiObject? = nil
		local holder: Frame = Create("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -STICKER.lip.card),
			ZIndex = 1,
			Parent = button,
		})
		Theme.list(
			Enum.FillDirection.Vertical,
			0,
			holder,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		)
		if item then
			local art: SquishyImage.Options = { size = S.artPx, layoutOrder = 1, parent = holder }
			c:add(SquishyImage.new(item.kind, art))
			for index = 1, 3 do
				local label = newLabel("Line" .. index, TEXT_KIND, holder, index + 1)
				label.TextXAlignment = Enum.TextXAlignment.Center
				table.insert(lines, label)
			end
			local made = LockIcon.new({ name = "Lock", sizePx = S.lockPx, parent = button })
			made.root.AnchorPoint = Vector2.new(1, 0)
			made.root.Position = UDim2.new(1, -S.cardPad, 0, S.cardPad)
			made.root.ZIndex = 2
			c:add(made)
			lock = made.root
		else
			local label = newLabel("Line1", TEXT_KIND, holder, 1)
			label.TextXAlignment = Enum.TextXAlignment.Center
			table.insert(lines, label)
		end
		c:add(Button.decorate(button, { fx = "card" }))
		c:add(button.Activated:Connect(function()
			if sold and item then
				spec.onSold(item.id) -- pens3 phase 7: a sold card
			else
				spec.onCard(slot, if item then item.id else nil)
			end
		end))
		return { root = button, face = face, lock = lock, lines = lines, cleanup = c }
	end

	-- Pens3 phase 9: a BUY FOOD card (the card face, the food picture when it has an id, three lines).
	local function newFoodCard(key: string, food: PenFormat.FoodCard): Card
		local c = Cleanup.new()
		local button: TextButton = Create("TextButton", {
			Name = "Pen_Card_" .. key,
			Text = "",
			AutoButtonColor = false,
			Selectable = true,
		})
		c:add(button)
		local face = CardFace.new(button, "Common") -- placeholder: Diego draws the food cards
		c:add(face)
		local holder: Frame = Create("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -STICKER.lip.card),
			ZIndex = 1,
			Parent = button,
		})
		Theme.list(
			Enum.FillDirection.Vertical,
			0,
			holder,
			Enum.HorizontalAlignment.Center,
			Enum.VerticalAlignment.Center
		)
		local picture = AssetTable.image(FOOD_PICTURE .. food.id)
		if picture then
			Create("ImageLabel", {
				Name = "Picture",
				BackgroundTransparency = 1,
				Image = picture,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(S.artPx, S.artPx),
				LayoutOrder = 1,
				Parent = holder,
			})
		end
		local lines: { TextLabel } = {}
		for index = 1, 3 do
			local label = newLabel("Line" .. index, TEXT_KIND, holder, index + 1)
			label.TextXAlignment = Enum.TextXAlignment.Center
			table.insert(lines, label)
		end
		c:add(Button.decorate(button, { fx = "card" }))
		c:add(button.Activated:Connect(function()
			spec.onFood(food.id)
		end))
		return { root = button, face = face, lines = lines, cleanup = c }
	end

	-- One card by key: reused when it exists, else made; painted and placed. A sold card (pens3 phase 7) shows its
	-- price and minutes instead of its rate and level.
	local function show(
		key: string,
		item: any?,
		slot: number?,
		order: number,
		parent: Frame,
		selected: boolean,
		sold: PenFormat.SoldCard?
	)
		local card = cards[key]
		if card == nil then
			card = newCard(key, item, slot, sold ~= nil)
			cards[key] = card
		end
		local k, width = scale(), cardWidth()
		if item then
			local text = PenFormat.cardText(item)
			local price = if sold
				then Strings.format(Strings.common.coinsAmount, { coins = Format.coins(sold.price) })
				else nil
			line(card.lines[1], text.name, TEXT_KIND, k, width)
			line(card.lines[2], price or text.rate, TEXT_KIND, k, width)
			line(card.lines[3], if sold then sold.time else text.level, TEXT_KIND, k, width)
			if card.lock then
				card.lock.Visible = item.locked == true
			end
		else
			line(card.lines[1], SCREEN_TEXT.empty, TEXT_KIND, k, width)
		end
		card.face:paint({ owned = item ~= nil, selected = selected })
		card.root.LayoutOrder = order
		card.root.Parent = parent
		if selected then
			selectedKey = key
		end
		firstKey = firstKey or key
	end

	local self = {} :: PenScreen
	self.root = root
	self.statusRoot = status.root

	function self.fit(_: PenScreen, px: Vector2)
		screenPx = px
		layout()
	end

	function self.render(_: PenScreen, view: PenFormat.View, busy: boolean)
		local focused = GuiService.SelectedObject
		local k = scale()
		status:setText(view.status)
		local width = math.max(0, root.Size.X.Offset - 2 * (STICKER.border.heavy + S.bodyPad))
		wrapped(hint, view.hint or "", TEXT_KIND, k, width)
		hint.Visible = view.hint ~= nil
		line(penHeading, SCREEN_TEXT.penHeading, HEADING_KIND, k, width)
		line(toyHeading, SCREEN_TEXT.toyHeading, HEADING_KIND, k, width)
		line(soldHeading, view.soldHeading or "", HEADING_KIND, k, width)
		soldHeading.Visible = view.soldHeading ~= nil
		soldGrid.Visible = view.soldHeading ~= nil
		selectedKey, firstKey = nil, nil
		local wanted: { [string]: boolean } = {}
		-- A card per spot (pens3 phase 11: the pen's, the shelf's and the TOP spot's grids).
		local function spotCards(spots: { PenFormat.Spot }, parent: Frame)
			for _, spot in spots do
				local item = spot.item
				local key = `spot{spot.slot}_{if item then `{item.id}_{item.kind}` else "empty"}`
				wanted[key] = true
				local ringed = item ~= nil and (item == view.selected or view.marked[item.id] == true)
				show(key, item, spot.slot, spot.slot, parent, ringed)
			end
		end
		spotCards(view.spots, penGrid)
		line(shelfHeading, view.shelfHeading or "", HEADING_KIND, k, width)
		shelfHeading.Visible = view.shelfHeading ~= nil
		shelfGrid.Visible = view.shelfHeading ~= nil
		spotCards(view.shelf, shelfGrid)
		line(topHeading, view.topHeading or "", HEADING_KIND, k, width)
		topHeading.Visible = view.topHeading ~= nil
		topGrid.Visible = view.topHeading ~= nil
		spotCards(if view.top then { view.top } else {}, topGrid)
		for index, item in view.toys do
			local key = `toy{item.id}_{item.kind}`
			wanted[key] = true
			show(key, item, nil, index, toyGrid, item == view.selected or view.marked[item.id] == true)
		end
		for index, card in view.sold do
			local key = `sold{card.id}_{card.item.kind}`
			wanted[key] = true
			show(key, card.item, nil, index, soldGrid, card == view.soldSelected, card)
		end
		-- Pens3 phase 9: the BUY FOOD cards.
		line(foodHeading, view.foodHeading or "", HEADING_KIND, k, width)
		foodHeading.Visible = view.foodHeading ~= nil
		foodGrid.Visible = view.foodHeading ~= nil
		for index, food in view.foods do
			local key = `food_{food.id}`
			wanted[key] = true
			local card = cards[key]
			if card == nil then
				card = newFoodCard(key, food)
				cards[key] = card
			end
			local cardText = cardWidth()
			line(card.lines[1], food.name, TEXT_KIND, k, cardText)
			line(card.lines[2], food.each, TEXT_KIND, k, cardText)
			line(card.lines[3], food.have, TEXT_KIND, k, cardText)
			local picked = view.foodSelected ~= nil and view.foodSelected.id == food.id
			card.face:paint({ owned = true, selected = picked })
			card.root.LayoutOrder = index
			card.root.Parent = foodGrid
			if picked then
				selectedKey = key
			end
		end
		line(foodRow, view.foodLine, TEXT_KIND, k, width)
		for key, card in cards do
			if not wanted[key] then
				card.cleanup:clean()
				cards[key] = nil
			end
		end
		-- The actions: rebuilt only when their ids change; their state follows `busy` and each action's reason.
		local idList = {}
		for _, action in view.actions do
			table.insert(idList, action.id)
		end
		local ids = table.concat(idList, ",") .. (if view.actions[1] and view.actions[1].hold then "+hold" else "")
		if ids ~= buttonIds then
			for _, old in buttons do
				old:destroy()
			end
			table.clear(buttons)
			buttonIds = ids
			for index, action in view.actions do
				local id = action.id
				local hold = action.hold == true
				local made = Button.new({
					name = "Pen_" .. id .. "Button",
					text = action.text,
					kind = action.kind,
					height = S.buttonHeight,
					layoutOrder = index,
					parent = actionRow,
					onActivated = function()
						if not hold then
							spec.onAction(id)
						end
					end,
				})
				table.insert(buttons, made)
				if hold then
					-- Pens3 phase 7: a hold reports its press and release; the controller times it.
					local root = made.root
					local mouseHeld = false -- a mouse that leaves the button lets go (a touch ends with InputEnded)
					local function held(input: InputObject): boolean
						return HOLD_INPUTS[input.UserInputType] == true or HOLD_KEYS[input.KeyCode] == true
					end
					root.InputBegan:Connect(function(input: InputObject)
						if held(input) then
							mouseHeld = input.UserInputType == Enum.UserInputType.MouseButton1
							spec.onHold(id, true)
						end
					end)
					root.InputEnded:Connect(function(input: InputObject)
						if held(input) then
							mouseHeld = false
							spec.onHold(id, false)
						end
					end)
					root.MouseLeave:Connect(function()
						if mouseHeld then
							mouseHeld = false
							spec.onHold(id, false)
						end
					end)
				end
			end
		end
		local wasShown = holdShown
		holdShown = view.actions[1] ~= nil and view.actions[1].hold == true
		if not holdShown then
			holdBar.root.Visible = false
		end
		if holdShown ~= wasShown then
			holdBar:set(0)
		end
		local reasons: { string } = {}
		for index, action in view.actions do
			local button = buttons[index]
			button:setText(action.text)
			if busy then
				button:setState("loading")
			elseif action.reason ~= nil then
				button:setState("disabled")
				if not table.find(reasons, action.reason) then
					table.insert(reasons, action.reason)
				end
			else
				button:setState("normal")
			end
		end
		wrapped(reasonRow, table.concat(reasons, " "), TEXT_KIND, k, width)
		reasonRow.Visible = #reasons > 0
		if focused ~= nil and focused.Parent == nil then
			GuiService.SelectedObject = self:primary() -- the focused card was rebuilt (it moved)
		end
		layout() -- the hint line may have come or gone
	end

	-- Pens3 phase 7: the hold's progress (0..1) on the bar; nil hides it.
	function self.setHold(_: PenScreen, fraction: number?)
		holdBar.root.Visible = holdShown and fraction ~= nil
		holdBar:set(fraction or 0)
	end

	function self.primary(_: PenScreen): GuiObject?
		local key = selectedKey or firstKey
		local card = if key then cards[key] else nil
		return if card then card.root else close.root
	end

	function self.destroy(_: PenScreen)
		for _, old in buttons do
			old:destroy()
		end
		table.clear(buttons)
		for _, card in cards do
			card.cleanup:clean()
		end
		table.clear(cards)
		cleanup:clean()
	end

	return self
end

return PenScreen
