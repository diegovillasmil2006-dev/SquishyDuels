--!strict
-- InspectPanel (client only). DESIGN §10.8 (info panel), §10.9 (owned and unowned), §10.4 step 4 (the Close button's
-- Modal frees the cursor), §10.11 (leak rule), §11.1-§11.4 (construction, layout, states, focus), §18.6 (sounds).
-- The Inspect modal's UI component. A component never requires a controller: InspectController passes callbacks,
-- attaches the shared ViewportStage into `stageHolder` and drives the panel.
--   local panel = InspectPanel.new(parent, { onClose = fn, onSqueeze = fn, onResetView = fn, onEquip = fn,
--                                            onViewInShop = fn })
--   panel:show(view)        an InspectFormat.View (all text comes from it: Catalog, Config and Boxes, nothing here)
--   panel:setEquip(state)   equip / equipped / notOwned / locked (with common.lockedInDuel) / loading
--   panel:setLayout(class)  "compact" | "regular" (UIController.layoutClass, on LayoutChanged)
--   panel.stageHolder       Frame "Inspect_Stage" (Active): the stage fills it; gestures start on it
--   panel:primary()         the Squeeze button (the default gamepad focus, §10.4 step 6)
--   panel:layout()          the PanelLayout applied last (tests, debug)
--   InspectPanel.layoutFor(screenPx, class, textScale?, rows?, topPadding?) / InspectPanel.howToGetSlots()   pure,
--                           unit-tested
--   InspectPanel.buttonRows(stageWidth, infoWidth, stageWidths, infoWidths)   pure: how many rows each button row needs
-- The layout class also follows the ScreenGui's size by itself (Layout.layoutClass, UIController's rule).
-- Content (foam UI restyle, spec 2026-10-09: header-tab title, inset fields, fewer words, larger type): the squishy's
-- name in a Strawberry header tab straddling the panel's top edge (Theme.headerTab); a header row with the RarityTag
-- (text + pips + colour, never colour alone) and one ownership chip ("Equipped" in Mint, "Owned" in Frosting, or a
-- lock with "PREVIEW · NOT OWNED" in Lilac) on the left and Close on the right, its key on a Keycap (Backspace on a
-- keyboard, B on a gamepad, none on touch: the old "Close: Backspace / B" sentence); then two columns: the stage with
-- the caption (Ink2) and [Squeeze] [Reset View] under it, and the info list (a ScrollingFrame in a Biscuit inset field,
-- wrapped AutomaticSize.Y text: coins line in the display font and its sub-text, five stat rows with foam progress
-- bars (Sky) and their caption, trail with a 2D gradient swatch, ultimate, elimination, "How to get") with [Equip]
-- [View in Shop] under it.
-- Layout: the pure, unit-tested InspectPanel.layoutFor(screenPx, class, textScale?, rows?, topPadding?) gives every
-- rect in base px (under the ScreenGui UIScale) inside the panel's padding; the panel re-applies it when the
-- ScreenGui's size, the layout class or the shown view changes (textScale = the player's PreferredTextSize multiplier,
-- so the caption grows with the text; topPadding = the room the header tab takes at the top).
-- Readings:
-- * §10.8 names the title 28 px; Theme's Title kind is 30, so the name (now the header tab's title) takes Title × 28/30
--   (with the player's PreferredTextSize; re-applied on every show and layout pass). The panel's top padding keeps
--   TAB_GAP under the tab's lower half at the current text size, and the panel sits a quarter of the tab lower than the
--   centre, so the panel and the half of the tab above it are centred together.
-- * The trail swatch is a white Frame whose UIGradient takes view.trail.colors (a ColorSequence) as is.
-- * Regular: the stage column is 55% of the width; compact (phones, 667×375): 50%, the info list scrolls, and each
--   column's buttons sit on one shared bottom row. Equip and View in Shop are pinned under the info list (not inside
--   it), so they stay on screen while the list scrolls.
-- * Kinds: Squeeze, Reset View and View in Shop are secondary, Equip is the primary (one primary per panel). Squeeze,
--   Reset View and Equip keep ui.click (Button default); Close and View in Shop are silent (ui.back / ui.open play).
-- * The info list is selectable (Focus ring) so a gamepad can scroll it.
-- * Fewer words (foam restyle): the ownership badge and the "PREVIEW · NOT OWNED" badge are one chip (it says the same
--   twice before); the close hint sentence is the Close button's keycap.
-- * Part 8 (re-checked at the largest text size): a button row wraps onto a second row when its buttons do not fit the
--   column side by side (on a phone at the Larger / Largest text size "Not owned" + "View in Shop" were wider than the
--   info column). apply() measures the shown buttons (Button.widthFor), buttonRows() counts the rows, and layoutFor(...,
--   rows) gives that row its height from the bottom up (the list or the stage shrinks above it); both rows keep the
--   same bottom edge. The row lists wrap (UIListLayout.Wraps); the measured widths are generous, so the reserved rows
--   are never fewer than the engine's.
-- * Foam fix batch (2026-10-09): Close hangs on the panel's top-right corner level with the name tab, as on every
--   other screen (InventoryFormat.hangingChrome), so the header row holds only the rarity tag and the ownership chip
--   and is as tall as they are (layoutFor's header: the Chip line, the chip padding and the tag's outline room); the
--   stage and the info list get the rest (on a phone the Reload stat was below the fold).
-- * Foam fix round 2 (2026-10-09): the body starts HEADER_GAP (Theme.Padding.medium) under the badges (their outline and
--   drop used up the 6 px, so on a phone the chips sat on the preview's rim), and both button rows keep BUTTON_GAP
--   (Theme.Padding.medium) between their buttons and their wrapped rows (at 6 the bevelled buttons read as one). On
--   touch the info list's scroll bar always shows while it is longer than its field (UI/Components/ScrollHint: the
--   engine draws it only while the list moves, so "How to get" below the fold gave no sign it was there).
-- Leak rule (§10.11): every instance is built once in new(). show(), setEquip() and setLayout() only set properties:
-- one RarityTag per rarity (toggled), 5 fixed stat rows, and a fixed pool of "How to get" lines (one per Boxes.list()
-- box + one shop line) toggled Visible. destroy() removes everything (one Cleanup).
-- Stable names: Inspect, Inspect_Stage, Inspect_CloseButton, Inspect_SqueezeButton, Inspect_ResetViewButton,
-- Inspect_EquipButton, Inspect_ViewInShopButton.
-- Knead (spec phase2-squeeze §1.19, §3.6-§3.7): panel:setKnead(view?) shows, while Inspect kneads, Thumb crunch
-- (Inspect_CrunchButton) before Squeeze and Re-wax (Inspect_RewaxButton) after it (the design's bar order, fp.js:555-
-- 560), the Squeeze and Coat rows at the top of the info list (rich text, UI/KneadFormat) and the knead help as the
-- caption; nil hides them again. Squeeze and Thumb crunch report their pointer down and up (callbacks.onKneadHold:
-- "palms" / "crunch", the design's hold buttons fp.js:609-615); Re-wax calls callbacks.onRewax. Both callbacks are
-- optional. User 2026-10-12 (the wax switch, Config.Wax.enabled): the thumb button takes the view's label (Thumb press
-- with the wax off), Re-wax shows only while view.rewax and the Coat row only with a view.coat.

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Rarity = require(Shared.Rarity)
local Strings = require(Shared.Strings)

local UI = script.Parent
local Button = require(UI.Components.Button)
local Chip = require(UI.Components.Chip)
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local InspectFormat = require(UI.InspectFormat)
local InventoryFormat = require(UI.InventoryFormat)
local Layout = require(UI.Layout)
local LockIcon = require(UI.Components.LockIcon)
local ProgressBar = require(UI.Components.ProgressBar)
local RarityTag = require(UI.Components.RarityTag)
local ScrollHint = require(UI.Components.ScrollHint)
local Theme = require(UI.Theme)

-- Types

export type Callbacks = {
	onClose: () -> (),
	onSqueeze: () -> (),
	onResetView: () -> (),
	onEquip: () -> (),
	onViewInShop: () -> (),
	-- Spec phase2-squeeze §3.6 (optional): a knead hold button down / up ("palms" = Squeeze, "crunch" = Thumb crunch)
	onKneadHold: ((action: string, down: boolean) -> ())?,
	onRewax: (() -> ())?,
}

-- What the panel shows while Inspect kneads (setKnead): the Squeeze and Coat rows (rich text; no Coat row without
-- coat), the caption's help, the thumb hold button's label and whether Re-wax shows (KneadController.View).
export type KneadView = { squeeze: string, coat: string?, help: string, thumb: string, rewax: boolean }

-- A rectangle in base px, relative to the panel's content box (inside its padding).
export type Rect = { x: number, y: number, w: number, h: number }

-- How many rows each button row takes (layoutFor; default 1 each).
export type ButtonRows = { stage: number?, info: number? }

export type PanelLayout = {
	class: Layout.LayoutClass,
	scale: number, -- the ScreenGui UIScale for this screen (Layout.uiScale)
	panelWidth: number, -- base px, capped at Config.UI.modalMaxWidth
	panelHeight: number, -- base px
	padding: number, -- the panel's inner padding on the sides and the bottom (base px)
	topPadding: number, -- the panel's top padding: the header tab's room (at least `padding`)
	contentWidth: number,
	contentHeight: number,
	stageWidthShare: number, -- the stage column's share of the content width
	buttonHeight: number, -- base px, >= Config.UI.Touch.minTarget and never below minTargetFloor on screen
	closeHeight: number, -- Close, hanging on the panel's top-right corner (fix batch)
	stageRows: number, -- rows of the [Squeeze] [Reset View] row
	infoRows: number, -- rows of the [Equip] [View in Shop] row
	header: Rect, -- the badges (the rarity tag and the ownership chip)
	stage: Rect,
	caption: Rect,
	stageButtons: Rect,
	info: Rect, -- the inset field around the info list
	infoButtons: Rect,
}

export type Panel = {
	root: Frame,
	stageHolder: Frame,
	info: ScrollingFrame,
	squeezeButton: Button.Button,
	resetButton: Button.Button,
	equipButton: Button.Button,
	viewInShopButton: Button.Button,
	closeButton: Button.Button,
	crunchButton: Button.Button, -- spec phase2-squeeze §3.6: shown while kneading
	rewaxButton: Button.Button,
	show: (self: Panel, view: InspectFormat.View) -> (),
	setKnead: (self: Panel, knead: KneadView?) -> (),
	setEquip: (self: Panel, state: InspectFormat.EquipState) -> (),
	setLayout: (self: Panel, class: Layout.LayoutClass) -> (),
	layout: (self: Panel) -> PanelLayout,
	primary: (self: Panel) -> GuiObject,
	destroy: (self: Panel) -> (),
}

type StatRow = { root: Frame, label: TextLabel, value: TextLabel, bar: ProgressBar.ProgressBar }

-- Constants

local UI_CONFIG = Config.UI
local TOUCH = UI_CONFIG.Touch
local MARGIN_PX = 24 -- like the Squishies and Shop panels
local MAX_HEIGHT_SHARE = 0.88 -- the panel never covers more than this share of the screen height
local PANEL_PADDING = Theme.Padding.medium
local GAP = Theme.Padding.small
local COLUMN_GAP = Theme.Padding.medium
local HEADER_GAP = Theme.Padding.medium -- fix round 2: under the badge row
local BUTTON_GAP = Theme.Padding.medium -- fix round 2: between the buttons of a row and between its wrapped rows
local STAGE_SHARE_REGULAR = 0.55 -- reading (task: "about 55%")
local STAGE_SHARE_COMPACT = 0.5 -- reading (task: "about 50%")
local CAPTION_LINES = 2 -- the caption's reserved height under the stage, in Small lines
local LINE_HEIGHT = 1.25
local NAME_TEXT_PX = 28 -- §10.8
local FALLBACK_SCREEN = Vector2.new(1280, 720) -- reading: before the ScreenGui has a size
local STAT_ROWS = 5 -- §10.8: Speed, Size, Reload, Windup, Arc
local STAT_BAR_PX = 12
local SWATCH_WIDTH = 44
local SWATCH_HEIGHT = 16
local LOCK_PX = 14
local SCROLLBAR_PX = 6
local INFO_INSET_PX = 10 -- the inset field's inner padding around the list
local SHOP_LINES = 1
local TAB_KIND: Theme.TextKind = "Title" -- the gap under it: InventoryFormat.PANEL.tabGap (hangingChrome)
-- Fix batch: the header row is as tall as its badges: the Chip line (LINE_HEIGHT of the Chip size), BADGE_PAD_PX (the
-- chip's padding and the rarity tag's outline room above and below), never below Chip.HEIGHT_PX. Close hangs on the
-- top-right corner CLOSE_INSET from the panel's right edge (as on Quests and Settings).
local BADGE_PAD_PX = 8
local CLOSE_INSET = 16

-- Module table

local InspectPanel = {}

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function rect(x: number, y: number, w: number, h: number): Rect
	return { x = x, y = y, w = math.max(0, w), h = math.max(0, h) }
end

local function place(object: GuiObject, r: Rect)
	object.Position = UDim2.fromOffset(r.x, r.y)
	object.Size = UDim2.fromOffset(r.w, r.h)
end

local function textOf(key: string): string
	return Strings.resolve(key) or key
end

local function fractionOf(value: unknown): number
	if not finite(value) then
		return 0
	end
	return math.clamp(value :: number, 0, 1)
end

-- The Close button's key for the active input (§10.6: Escape is the Roblox menu's, so Backspace / B), nil on touch.
local function closeKey(): string?
	local ok, input = pcall(function(): Enum.PreferredInput
		return UserInputService.PreferredInput
	end)
	if not ok or input == Enum.PreferredInput.Touch then
		return nil
	elseif input == Enum.PreferredInput.Gamepad then
		return Strings.controls.key.backGamepad
	end
	return Strings.controls.key.backKeyboard
end

-- Public: pure layout (unit-tested) ------------------------------------------------------------------------------------

-- The number of "How to get" lines the panel holds: one per box (Boxes.list()) plus one shop line.
function InspectPanel.howToGetSlots(): number
	return #Boxes.list() + SHOP_LINES
end

-- How many rows the stage buttons and the info buttons take in columns `stageWidth` / `infoWidth` wide (base px), from
-- the shown buttons' widths (Layout.wrapRow, the row gap BUTTON_GAP); at least 1 each.
function InspectPanel.buttonRows(
	stageWidth: number,
	infoWidth: number,
	stageWidths: { number },
	infoWidths: { number }
): ButtonRows
	local function rowsOf(width: number, widths: { number }): number
		local items: { Layout.WrapItem } = {}
		for _, w in widths do
			table.insert(items, { w = w, h = 1 })
		end
		return math.max(1, Layout.wrapRow(items, width, BUTTON_GAP).rows)
	end
	return { stage = rowsOf(stageWidth, stageWidths), info = rowsOf(infoWidth, infoWidths) }
end

-- Every rect of the panel for a ScreenGui of `sizePx` actual px in layout class `class`. `textScale` is the player's
-- PreferredTextSize multiplier (default 1); it sizes the caption's reserved space. `rows` (Part 8, default 1 each,
-- buttonRows) gives a wrapped button row its height, from the bottom up. `topPadding` (foam restyle) is the panel's top
-- padding, which its header tab raises (default the panel padding); the content box loses the difference.
function InspectPanel.layoutFor(
	sizePx: Vector2,
	class: Layout.LayoutClass,
	textScale: number?,
	rows: ButtonRows?,
	topPadding: number?
): PanelLayout
	local screenX = if finite(sizePx.X) and sizePx.X > 0 then sizePx.X else FALLBACK_SCREEN.X
	local screenY = if finite(sizePx.Y) and sizePx.Y > 0 then sizePx.Y else FALLBACK_SCREEN.Y
	local scale = Layout.uiScale(screenY)
	local width = math.floor(Layout.modalWidth(screenX, scale, MARGIN_PX))
	if width <= 0 then
		width = UI_CONFIG.modalMaxWidth
	end
	local height = math.floor(screenY / scale * MAX_HEIGHT_SHARE)
	local top = if topPadding ~= nil
			and finite(topPadding)
			and topPadding > PANEL_PADDING
		then topPadding
		else PANEL_PADDING
	local contentWidth = math.max(0, width - 2 * PANEL_PADDING)
	local contentHeight = math.max(0, height - top - PANEL_PADDING)

	local compact = class == "compact"
	local share = if compact then STAGE_SHARE_COMPACT else STAGE_SHARE_REGULAR
	local closeHeight = Layout.touchBase(TOUCH.closeButton, scale)
	local buttonHeight = Layout.touchBase(if compact then TOUCH.minTarget else TOUCH.primaryButton, scale)
	local textMultiplier = if textScale ~= nil and finite(textScale) and textScale > 0 then textScale else 1
	local smallPx = math.floor(UI_CONFIG.TextSize.Small * textMultiplier + 0.5)
	local captionHeight = math.ceil(CAPTION_LINES * smallPx * LINE_HEIGHT)
	-- Fix batch: Close hangs on the corner, so the header row is only as tall as its badges.
	local chipPx = math.floor(UI_CONFIG.TextSize.Chip * textMultiplier + 0.5)
	local headerHeight = math.max(Chip.HEIGHT_PX, math.ceil(chipPx * LINE_HEIGHT) + BADGE_PAD_PX)

	local bodyTop = headerHeight + HEADER_GAP
	local bodyHeight = math.max(0, contentHeight - bodyTop)
	local stageWidth = math.floor(math.max(0, contentWidth - COLUMN_GAP) * share)
	local infoX = stageWidth + COLUMN_GAP
	local infoWidth = math.max(0, contentWidth - infoX)
	local function rowCount(n: number?): number
		return if n ~= nil and finite(n) and n >= 1 then math.floor(n) else 1
	end
	local stageRows = rowCount(rows and rows.stage)
	local infoRows = rowCount(rows and rows.info)
	local stageButtonsHeight = stageRows * buttonHeight + (stageRows - 1) * BUTTON_GAP
	local infoButtonsHeight = infoRows * buttonHeight + (infoRows - 1) * BUTTON_GAP
	local stageButtonsTop = bodyTop + math.max(0, bodyHeight - stageButtonsHeight)
	local infoButtonsTop = bodyTop + math.max(0, bodyHeight - infoButtonsHeight)
	local stageHeight = math.max(0, bodyHeight - stageButtonsHeight - GAP - captionHeight - GAP)

	return {
		class = if compact then "compact" else "regular",
		scale = scale,
		panelWidth = width,
		panelHeight = height,
		padding = PANEL_PADDING,
		topPadding = top,
		contentWidth = contentWidth,
		contentHeight = contentHeight,
		stageWidthShare = share,
		buttonHeight = buttonHeight,
		closeHeight = closeHeight,
		stageRows = stageRows,
		infoRows = infoRows,
		header = rect(0, 0, contentWidth, headerHeight),
		stage = rect(0, bodyTop, stageWidth, stageHeight),
		caption = rect(0, bodyTop + stageHeight + GAP, stageWidth, captionHeight),
		stageButtons = rect(0, stageButtonsTop, stageWidth, stageButtonsHeight),
		info = rect(infoX, bodyTop, infoWidth, bodyHeight - infoButtonsHeight - GAP),
		infoButtons = rect(infoX, infoButtonsTop, infoWidth, infoButtonsHeight),
	}
end

-- Public: the component ------------------------------------------------------------------------------------------------

function InspectPanel.new(parent: Instance, callbacks: Callbacks): Panel
	local cleanup = Cleanup.new()

	local root = Theme.panel({
		Name = "Inspect",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(UI_CONFIG.modalMaxWidth, 0),
	}, Theme.Radius.panel, PANEL_PADDING)
	cleanup:add(root)
	Focus.prepareGroup(root)
	local rootPad = root:FindFirstChildOfClass("UIPadding") :: UIPadding

	-- The name: a header tab on the panel's top edge -----------------------------------------------------------------
	local tab, nameLabel = Theme.headerTab(root, "", { textKind = TAB_KIND, name = "NameTab" })

	-- Header row: rarity and ownership (fix batch: Close hangs on the panel's top-right corner, below) --------------------
	local header: Frame = Create("Frame", { Name = "Header", BackgroundTransparency = 1, Parent = root })
	local badges: Frame = Create("Frame", {
		Name = "Badges",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = header,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.medium, badges, Enum.HorizontalAlignment.Left)
	local rarityTags: { [string]: RarityTag.RarityTag } = {}
	for _, rarity in Rarity.ORDER do
		local tag = RarityTag.new({ name = "Rarity_" .. rarity, rarity = rarity, layoutOrder = 1, parent = badges })
		tag.root.Visible = false
		cleanup:add(tag)
		rarityTags[rarity] = tag
	end
	local ownership = Chip.new({ name = "Ownership", text = "", layoutOrder = 2, parent = badges })
	cleanup:add(ownership)
	local lock = LockIcon.new({ name = "Lock", sizePx = LOCK_PX, layoutOrder = 0, parent = ownership.root })
	cleanup:add(lock)
	-- Close (with its key) hangs on the panel's top-right corner, level with the name tab (fitTab places it; drawn over
	-- the panel's outline like the tab).
	local close = Button.new({
		name = "Inspect_CloseButton",
		text = Strings.common.close,
		kind = "primary", -- UI overhaul: the close red, with its key hint (a pill, not the X)
		accent = "red",
		height = TOUCH.closeButton,
		keycap = "", -- the key for the active input (closeKey), hidden on touch
		parent = root,
		sound = false, -- closing plays ui.back (UIController.close)
		onActivated = function()
			callbacks.onClose()
		end,
	})
	close.root.AnchorPoint = Vector2.new(1, 0.5)
	close.root.ZIndex = tab.ZIndex
	close.root.Modal = true -- frees the cursor in shift lock / first person (§10.4 step 4)
	cleanup:add(close)
	local function applyCloseKey()
		close:setKeycap(closeKey())
	end
	applyCloseKey()
	cleanup:add(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(applyCloseKey))

	-- Stage column: the holder, the caption, [Squeeze] [Reset View] ---------------------------------------------------
	local stageHolder: Frame = Create("Frame", {
		Name = "Inspect_Stage",
		BackgroundTransparency = 1,
		Active = true,
		Parent = root,
	})
	local caption = Theme.label({
		Name = "Caption",
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = root,
	}, "Small", nil, Theme.Colors.ink2)
	local stageButtons: Frame = Create("Frame", { Name = "StageButtons", BackgroundTransparency = 1, Parent = root })
	local stageList =
		Theme.list(Enum.FillDirection.Horizontal, BUTTON_GAP, stageButtons, Enum.HorizontalAlignment.Center)
	stageList.Wraps = true -- Part 8: a second row at a large text size (the height comes from layoutFor's rows)
	local squeeze = Button.new({
		name = "Inspect_SqueezeButton",
		text = Strings.controls.squeeze,
		height = TOUCH.primaryButton,
		layoutOrder = 1,
		parent = stageButtons,
		onActivated = function()
			callbacks.onSqueeze()
		end,
	})
	cleanup:add(squeeze)
	local reset = Button.new({
		name = "Inspect_ResetViewButton",
		text = Strings.inspect.resetView,
		height = TOUCH.primaryButton,
		layoutOrder = 3, -- spec phase2-squeeze §1.19: after Re-wax (the design's bar order)
		parent = stageButtons,
		onActivated = function()
			callbacks.onResetView()
		end,
	})
	cleanup:add(reset)
	-- Spec phase2-squeeze §3.6: the knead's Thumb crunch (held) before Squeeze and Re-wax after it, shown by setKnead.
	local crunch = Button.new({
		name = "Inspect_CrunchButton",
		text = Strings.knead.thumbCrunch,
		height = TOUCH.primaryButton,
		layoutOrder = 0,
		parent = stageButtons,
		onActivated = function() end, -- a hold: its pointer down and up (below)
	})
	crunch.root.Visible = false
	cleanup:add(crunch)
	local rewax = Button.new({
		name = "Inspect_RewaxButton",
		text = Strings.knead.rewax,
		height = TOUCH.primaryButton,
		layoutOrder = 2,
		parent = stageButtons,
		onActivated = function()
			if callbacks.onRewax then
				callbacks.onRewax()
			end
		end,
	})
	rewax.root.Visible = false
	cleanup:add(rewax)
	-- The hold buttons (fp.js:609-615): a mouse or touch press on Squeeze ("palms") or Thumb crunch ("crunch") reports
	-- down, and its release, wherever it lifts, reports up.
	local held: { [string]: InputObject } = {}
	local function report(action: string, down: boolean)
		local onHold = callbacks.onKneadHold
		if onHold then
			onHold(action, down)
		end
	end
	local function holdOn(action: string, target: TextButton)
		cleanup:add(target.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch) and not held[action] then
				held[action] = input
				report(action, true)
			end
		end))
	end
	holdOn("palms", squeeze.root)
	holdOn("crunch", crunch.root)
	cleanup:add(UserInputService.InputEnded:Connect(function(input: InputObject)
		for action, pressed in held do
			local mouse = pressed.UserInputType == Enum.UserInputType.MouseButton1
			if pressed == input or (mouse and input.UserInputType == Enum.UserInputType.MouseButton1) then
				held[action] = nil
				report(action, false)
			end
		end
	end))

	-- Info column: the scrolling list in an inset field, then [Equip] [View in Shop] ----------------------------------
	local infoField = Theme.inset({ Name = "InfoField", Parent = root }, Theme.Radius.button, INFO_INSET_PX)
	local info: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Info",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR_PX,
		ScrollBarImageColor3 = Theme.Colors.inkUI,
		Parent = infoField,
	})
	Focus.decorate(info)
	Create("UIPadding", { PaddingRight = UDim.new(0, SCROLLBAR_PX + 4), Parent = info })
	-- Fix round 2: on touch the list's scroll bar stays on screen while the list is longer than the field.
	local scrollHint = ScrollHint.new({ scroll = info, parent = infoField })
	scrollHint.root.AnchorPoint = Vector2.new(1, 0)
	scrollHint.root.Position = UDim2.fromScale(1, 0)
	scrollHint.root.Size = UDim2.new(0, SCROLLBAR_PX, 1, 0)
	cleanup:add(scrollHint)
	Theme.list(Enum.FillDirection.Vertical, GAP, info, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function infoLabel(name: string, kind: Theme.TextKind, weight: Enum.FontWeight?, color: Color3?): TextLabel
		return Theme.label({
			Name = name,
			LayoutOrder = nextOrder(),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = info,
		}, kind, weight, color)
	end

	-- Spec phase2-squeeze §1.19: the knead's Squeeze and Coat rows (rich text, the label in bold), shown by setKnead.
	local kneadRows: { TextLabel } = {}
	for _, name in { "KneadSqueeze", "KneadCoat" } do
		local row = infoLabel(name, "Body")
		row.RichText = true
		row.Visible = false
		table.insert(kneadRows, row)
	end
	local coins = infoLabel("Coins", "H2")
	local coinsSub = infoLabel("CoinsSub", "Small", nil, Theme.Colors.ink2)
	local statsCaption = infoLabel("StatsCaption", "Small", nil, Theme.Colors.ink2)
	local statRows: { StatRow } = {}
	for i = 1, STAT_ROWS do
		local row: Frame = Create("Frame", {
			Name = "Stat_" .. i,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = nextOrder(),
			Parent = info,
		})
		Theme.list(Enum.FillDirection.Vertical, 3, row, Enum.HorizontalAlignment.Left)
		local top: Frame = Create("Frame", {
			Name = "Header",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = row,
		})
		local label = Theme.label({
			Name = "Label",
			Size = UDim2.fromScale(0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = top,
		}, "Body", Enum.FontWeight.Bold)
		local value = Theme.label({
			Name = "Value",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = top,
		}, "Body")
		local bar =
			ProgressBar.new({ name = "Bar", accent = "sky", heightPx = STAT_BAR_PX, layoutOrder = 2, parent = row })
		cleanup:add(bar)
		table.insert(statRows, { root = row, label = label, value = value, bar = bar })
	end

	local trailRow: Frame = Create("Frame", {
		Name = "Trail",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = nextOrder(),
		Parent = info,
	})
	Theme.list(Enum.FillDirection.Horizontal, GAP, trailRow, Enum.HorizontalAlignment.Left)
	local swatch: Frame = Create("Frame", {
		Name = "Swatch",
		BackgroundColor3 = Theme.Colors.white, -- the UIGradient multiplies this colour
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(SWATCH_WIDTH, SWATCH_HEIGHT),
		LayoutOrder = 1,
		Visible = false,
		Parent = trailRow,
	})
	Theme.corner(Theme.Radius.small, swatch)
	Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.bar, swatch)
	local gradient: UIGradient = Create("UIGradient", { Name = "Gradient", Parent = swatch })
	local trailLabel = Theme.label({
		Name = "Text",
		Size = UDim2.new(1, -(SWATCH_WIDTH + GAP), 0, 0),
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = trailRow,
	}, "Body")

	local ultimate = infoLabel("Ultimate", "Body")
	local elimination = infoLabel("Elimination", "Body")
	local howHeading = infoLabel("HowToGet", "H2")
	local howLines: { TextLabel } = {}
	for i = 1, InspectPanel.howToGetSlots() do
		local line = infoLabel("HowToGet_" .. i, "Body")
		line.Visible = false
		table.insert(howLines, line)
	end

	local infoButtons: Frame = Create("Frame", { Name = "InfoButtons", BackgroundTransparency = 1, Parent = root })
	local infoList = Theme.list(Enum.FillDirection.Horizontal, BUTTON_GAP, infoButtons, Enum.HorizontalAlignment.Left)
	infoList.Wraps = true -- Part 8: a second row at a large text size (the height comes from layoutFor's rows)
	local equip = Button.new({
		name = "Inspect_EquipButton",
		text = Strings.common.equip,
		kind = "primary",
		height = TOUCH.primaryButton,
		layoutOrder = 1,
		parent = infoButtons,
		onActivated = function()
			callbacks.onEquip()
		end,
	})
	cleanup:add(equip)
	local viewInShop = Button.new({
		name = "Inspect_ViewInShopButton",
		text = Strings.inspect.viewInShop,
		height = TOUCH.primaryButton,
		layoutOrder = 2,
		parent = infoButtons,
		sound = false, -- opens a screen: ui.open plays instead
		onActivated = function()
			callbacks.onViewInShop()
		end,
	})
	viewInShop.root.Visible = false
	cleanup:add(viewInShop)

	-- Layout -------------------------------------------------------------------------------------------------------------
	local sizeSource: GuiBase2d? = if parent:IsA("GuiBase2d")
		then parent
		else parent:FindFirstAncestorWhichIsA("GuiBase2d")
	-- The ScreenGui's actual size; the fallback while it has none yet (unparented, Edit mode).
	local function screenSize(): Vector2
		local size = if sizeSource then sizeSource.AbsoluteSize else Vector2.zero
		return if size.X > 0 and size.Y > 0 then size else FALLBACK_SCREEN
	end
	local class: Layout.LayoutClass = Layout.layoutClass(screenSize().X, screenSize().Y)
	local current: PanelLayout = InspectPanel.layoutFor(screenSize(), class)

	local function applyNameSize()
		local size = Theme.textSize("Title") * NAME_TEXT_PX / UI_CONFIG.TextSize.Title
		nameLabel.TextSize = math.max(UI_CONFIG.minTextSize, math.floor(size + 0.5))
	end

	-- The header tab and Close at the player's text size (fix batch: InventoryFormat.hangingChrome): the tab stays centred
	-- on the panel's top edge and Close hangs on the top-right corner, level with it; the panel's top padding keeps the
	-- gap under their lower halves, and the panel moves down by half of what hangs above it (both centred together).
	-- Returns the top padding.
	local function fitTab(): number
		local tabPad = tab:FindFirstChildOfClass("UIPadding")
		local padY = if tabPad then tabPad.PaddingTop.Offset + tabPad.PaddingBottom.Offset else 0
		local tabHeight = math.ceil(Theme.lineHeight(TAB_KIND)) + padY
		local closeHeight = Layout.touchBase(TOUCH.closeButton, Layout.uiScale(screenSize().Y))
		local chrome = InventoryFormat.hangingChrome(tabHeight, closeHeight, PANEL_PADDING)
		rootPad.PaddingTop = UDim.new(0, chrome.top)
		tab.Position = UDim2.new(0.5, 0, 0, -chrome.top)
		close.root.Position = UDim2.new(1, PANEL_PADDING - CLOSE_INSET, 0, -chrome.top)
		root.Position = UDim2.new(0.5, 0, 0.5, chrome.shift)
		return chrome.top
	end

	-- What Equip shows now (setEquip), measured for the row count.
	local equipText = Strings.common.equip
	local equipReason: string? = nil
	-- Spec phase2-squeeze §3.7: the knead view while Inspect kneads (setKnead), and the caption show() last gave.
	local kneadView: KneadView? = nil
	local viewCaption = ""
	local thumbText = Strings.knead.thumbCrunch -- the thumb button's label (setKnead; user 2026-10-12)

	-- The rows each button row needs at this size and text size (Part 8): the shown buttons measured.
	local function measuredRows(l: PanelLayout): ButtonRows
		local stageWidths = { Button.widthFor(Strings.controls.squeeze), Button.widthFor(Strings.inspect.resetView) }
		if crunch.root.Visible then -- spec phase2-squeeze §3.6: the knead's buttons (Re-wax with the wax on)
			table.insert(stageWidths, Button.widthFor(thumbText))
		end
		if rewax.root.Visible then
			table.insert(stageWidths, Button.widthFor(Strings.knead.rewax))
		end
		local infoWidths = { Button.widthFor(equipText, equipReason) }
		if viewInShop.root.Visible then
			table.insert(infoWidths, Button.widthFor(Strings.inspect.viewInShop))
		end
		return InspectPanel.buttonRows(l.stage.w, l.info.w, stageWidths, infoWidths)
	end

	local function apply()
		local textScale = Theme.textSize("Body") / UI_CONFIG.TextSize.Body
		local top = fitTab()
		local first = InspectPanel.layoutFor(screenSize(), class, textScale, nil, top)
		local l = InspectPanel.layoutFor(screenSize(), class, textScale, measuredRows(first), top)
		current = l
		applyNameSize()
		root.Size = UDim2.fromOffset(l.panelWidth, l.panelHeight)
		place(header, l.header)
		place(stageHolder, l.stage)
		place(caption, l.caption)
		place(stageButtons, l.stageButtons)
		place(infoField, l.info)
		place(infoButtons, l.infoButtons)
		close.root.Size = UDim2.fromOffset(0, l.closeHeight)
		for _, button in { squeeze, reset, equip, viewInShop, crunch, rewax } do
			button.root.Size = UDim2.fromOffset(0, l.buttonHeight)
		end
	end
	apply()
	if sizeSource then
		-- The class follows the size too (the same rule as UIController's LayoutChanged, which also calls setLayout).
		cleanup:add(sizeSource:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local size = screenSize()
			class = Layout.layoutClass(size.X, size.Y)
			apply()
		end))
	end
	local okSignal, textSizeChanged = pcall(function(): RBXScriptSignal
		return GuiService:GetPropertyChangedSignal("PreferredTextSize")
	end)
	if okSignal then
		-- Deferred: UIController re-applies the text sizes on the same signal; the tab is measured after it.
		cleanup:add(textSizeChanged:Connect(function()
			task.defer(apply)
		end))
	end

	root.Parent = parent

	local self = {} :: Panel
	self.root = root
	self.stageHolder = stageHolder
	self.info = info
	self.squeezeButton = squeeze
	self.resetButton = reset
	self.equipButton = equip
	self.viewInShopButton = viewInShop
	self.closeButton = close
	self.crunchButton = crunch
	self.rewaxButton = rewax

	function self.show(_: Panel, view: InspectFormat.View)
		nameLabel.Text = view.name
		for rarity, tag in rarityTags do
			tag.root.Visible = rarity == view.rarity
		end
		-- One ownership chip: the lock and "Preview · Not owned" (Lilac) when not owned, else Equipped (Mint) / Owned.
		local preview = view.previewBadge
		if not view.owned then
			ownership:setText(if preview and preview ~= "" then preview else textOf(view.badgeKey))
			ownership:setAccent("lilac")
		else
			ownership:setText(textOf(view.badgeKey))
			ownership:setAccent(if view.equipped then "mint" else "frosting")
		end
		lock.root.Visible = not view.owned

		viewCaption = view.caption
		caption.Text = if kneadView then kneadView.help else view.caption
		coins.Text = view.coinsText
		coinsSub.Text = view.coinsSub
		statsCaption.Text = view.statsCaption
		for i, row in statRows do
			local stat = view.stats[i]
			row.root.Visible = stat ~= nil
			if stat then
				row.label.Text = stat.label
				row.value.Text = stat.valueText
				row.bar:set(fractionOf(stat.fraction), false)
			end
		end
		trailLabel.Text = view.trail.text
		local colors = view.trail.colors
		local hasSwatch = typeof(colors) == "ColorSequence"
		swatch.Visible = hasSwatch
		if colors and hasSwatch then
			gradient.Color = colors
		end
		local ultimateText = view.ultimate
		ultimate.Visible = ultimateText ~= nil and ultimateText ~= ""
		ultimate.Text = ultimateText or ""
		elimination.Text = view.elimination
		local lines = view.howToGet
		howHeading.Visible = #lines > 0
		howHeading.Text = view.howToGetTitle
		for i, label in howLines do
			local line = lines[i]
			label.Visible = line ~= nil
			label.Text = if line then line.text else ""
		end
		viewInShop.root.Visible = view.canViewInShop
		info.CanvasPosition = Vector2.zero
		apply() -- picks up a PreferredTextSize change (name size, tab, caption space)
	end

	function self.setEquip(_: Panel, state: InspectFormat.EquipState)
		local reason: string? = nil
		if state == "equip" then
			equipText = Strings.common.equip
			equip:setText(equipText)
			equip:setState("normal")
		elseif state == "equipped" then
			equipText = Strings.common.equipped
			equip:setText(equipText)
			equip:setState("disabled")
		elseif state == "notOwned" then
			equipText = Strings.common.notOwned
			equip:setText(equipText)
			equip:setState("disabled")
		elseif state == "locked" then
			equipText = Strings.common.equip
			reason = Strings.common.lockedInDuel
			equip:setText(equipText)
			equip:setState("disabled", reason)
		else
			equip:setState("loading") -- keeps its text
		end
		if reason ~= equipReason or state ~= "loading" then
			equipReason = reason
			apply() -- the info row may need another row now (Part 8)
		end
	end

	-- Spec phase2-squeeze §1.19, §3.7: the knead's buttons, rows and help while Inspect kneads; nil hides them. User
	-- 2026-10-12 (the wax switch): the thumb button's label from the view, Re-wax only while view.rewax, the Coat row
	-- only with a view.coat.
	function self.setKnead(_: Panel, view: KneadView?)
		kneadView = view
		local on = view ~= nil
		if view then
			thumbText = view.thumb
			crunch:setText(thumbText)
		end
		crunch.root.Visible = on
		rewax.root.Visible = view ~= nil and view.rewax
		local coat = if view then view.coat else nil
		kneadRows[1].Text = if view then view.squeeze else ""
		kneadRows[2].Text = coat or ""
		kneadRows[1].Visible = on
		kneadRows[2].Visible = coat ~= nil
		caption.Text = if view then view.help else viewCaption
		apply() -- the stage's button row may need another row now (Part 8)
	end

	function self.setLayout(_: Panel, newClass: Layout.LayoutClass)
		class = if newClass == "compact" then "compact" else "regular"
		apply()
	end

	function self.layout(_: Panel): PanelLayout
		return current
	end

	function self.primary(_: Panel): GuiObject
		return squeeze.root
	end

	function self.destroy(_: Panel)
		cleanup:clean()
	end

	return self
end

return InspectPanel
