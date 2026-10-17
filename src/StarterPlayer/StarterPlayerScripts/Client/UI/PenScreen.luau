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
--   local s = PenScreen.new({ parent = gui, scale = UIController.scale, onCard = ..., onAction = ..., onClose = ... })
--   s:fit(screenPx);   s:render(view, busy);   s:primary();   s:destroy()

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)

local UI = script.Parent
local Button = require(UI.Components.Button)
local CardFace = require(UI.CardFace)
local Create = require(UI.Create)
local Layout = require(UI.Layout)
local LockIcon = require(UI.Components.LockIcon)
local PenFormat = require(UI.PenFormat)
local SquishyImage = require(UI.Components.SquishyImage)
local StatePill = require(UI.Components.StatePill)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	parent: Instance,
	scale: () -> number, -- the ScreenGui's UIScale (UIController.scale)
	onCard: (slot: number?, itemId: number?) -> (),
	onAction: (id: string) -> (),
	onClose: () -> (),
}

export type PenScreen = {
	root: Frame,
	fit: (self: PenScreen, screenPx: Vector2) -> (),
	render: (self: PenScreen, view: PenFormat.View, busy: boolean) -> (),
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
	local toyHeading = newLabel("Pen_ToyHeading", HEADING_KIND, scroll, 3)
	local toyGrid = grid("Pen_ToyBox", 4, scroll)
	local actionRow: Frame = Create("Frame", {
		Name = "Pen_Actions",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, S.buttonHeight + STICKER.lip.button),
		Parent = body,
	})
	Theme.list(Enum.FillDirection.Horizontal, S.gap, actionRow, Enum.HorizontalAlignment.Center)

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
		scroll.Position = UDim2.fromOffset(0, top)
		scroll.Size = UDim2.new(1, 0, 1, -(top + actionRow.Size.Y.Offset + S.gap))
	end

	local function scale(): number
		local value = spec.scale()
		return if value > 0 then value else 1
	end

	local function cardWidth(): number
		return S.cardSize.X - 2 * S.cardPad
	end

	local function newCard(key: string, item: any?, slot: number?): Card
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
			spec.onCard(slot, if item then item.id else nil)
		end))
		return { root = button, face = face, lock = lock, lines = lines, cleanup = c }
	end

	-- One card by key: reused when it exists, else made; painted and placed.
	local function show(key: string, item: any?, slot: number?, order: number, parent: Frame, selected: boolean)
		local card = cards[key]
		if card == nil then
			card = newCard(key, item, slot)
			cards[key] = card
		end
		local k, width = scale(), cardWidth()
		if item then
			local text = PenFormat.cardText(item)
			line(card.lines[1], text.name, TEXT_KIND, k, width)
			line(card.lines[2], text.rate, TEXT_KIND, k, width)
			line(card.lines[3], text.level, TEXT_KIND, k, width)
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
		selectedKey, firstKey = nil, nil
		local wanted: { [string]: boolean } = {}
		for _, spot in view.spots do
			local item = spot.item
			local key = `spot{spot.slot}_{if item then `{item.id}_{item.kind}` else "empty"}`
			wanted[key] = true
			show(key, item, spot.slot, spot.slot, penGrid, item ~= nil and item == view.selected)
		end
		for index, item in view.toys do
			local key = `toy{item.id}_{item.kind}`
			wanted[key] = true
			show(key, item, nil, index, toyGrid, item == view.selected)
		end
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
		local ids = table.concat(idList, ",")
		if ids ~= buttonIds then
			for _, old in buttons do
				old:destroy()
			end
			table.clear(buttons)
			buttonIds = ids
			for index, action in view.actions do
				local id = action.id
				table.insert(
					buttons,
					Button.new({
						name = "Pen_" .. id .. "Button",
						text = action.text,
						kind = action.kind,
						height = S.buttonHeight,
						layoutOrder = index,
						parent = actionRow,
						onActivated = function()
							spec.onAction(id)
						end,
					})
				)
			end
		end
		for index, action in view.actions do
			local button = buttons[index]
			button:setText(action.text)
			if busy then
				button:setState("loading")
			elseif action.reason ~= nil then
				button:setState("disabled", action.reason)
			else
				button:setState("normal")
			end
		end
		if focused ~= nil and focused.Parent == nil then
			GuiService.SelectedObject = self:primary() -- the focused card was rebuilt (it moved)
		end
		layout() -- the hint line may have come or gone
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
