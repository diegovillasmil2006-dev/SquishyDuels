--!strict
-- InventoryController (client only). DESIGN §11.6 (Squishies screen), §10.8 / §10.9 (compact info panel, owned and
-- unowned), §10.3 (Inspect entry point), §4.3 (rarity: text + pips + colour), §11.4 (focus, L1 / R1), §11.7 (I key),
-- §2.8 (EquipSquishy), §11.3 (states).
-- The "squishies" modal (lobby only; refused and closed from Matched through Returning by UIController; while open
-- UIController holds ControlsController.block("modal")). Opened by the HUD Squishies tile, the I key (the
-- "Squishies" action) and the collection kiosk's "Open Collection" prompt (reading: the kiosk is this screen's stand,
-- WorldBinder.registerStand("SD_CollectionKiosk"); the pedestals' Inspect prompts are Part 6's).
-- * Layout: header (title, "Collected {n}/8", Close), filter chips with counts ("Epic (2)", inventory.filterCount;
--   All, Common, Uncommon, Epic, Exclusive; L1 / R1 cycle them) and "Show not owned" (default on), then the grid
--   (Config.UI.Inventory: 55-60% of the width, columns = floor(gridWidth / (cardWidth + pad))) next to the detail
--   panel, on every device. Gamepad: the grid scrolls to keep the selected card in view (§11.4).
-- * Cards (Squishies_Card_<id>, built once and kept; filters only change Visible and LayoutOrder, as StaticIcon wants):
--   preview, name, rarity pips + label, a rarity-coloured frame (Art/RarityStyle card: stroke width, Epic gradient,
--   Exclusive shimmer at 45°/s, static under ReducedMotion, and the "Ultimate" badge), and the badges "Equipped", "NEW"
--   (StateController new squishies, until the card is first selected) or "Not owned" (greyed, with a lock).
--   Sort: equipped first, then rarity descending, then name (UI/InventoryFormat); the selection is kept while visible.
-- * Detail panel: preview, name, rarity row, ownership (with a lock when not owned), "x{n} power" (Phase 5), the five
--   throw stats as bars inside the §5.8 bands, trail, ultimate, elimination, the shop price when not owned (+ View in
--   Shop once a "shop" screen exists), Equip and Inspect.
-- * Equip (Squishies_EquipButton): EquipSquishy through NetController; loading while it runs; ok -> "Equipped!" toast
--   (NotifyController) and the button reads Equipped (the StateDelta follows); a failure shows its reason, or "Couldn't
--   equip. Try again." for an unknown one, and the button comes back. Disabled for unowned ("Not owned") and during a
--   duel. The server checks everything again (§12 #4).
-- * Inspect (Squishies_InspectButton) opens the Part 6 "inspect" screen with {squishyId, owned, source = "squishies"};
--   the button shows only once that screen is registered.
-- * States: loading (no Snapshot yet), filter-empty ("No {rarity} squishies yet." + Go to Boxes once a "boxes" screen
--   exists), data error (offline / read-only: data.loadFailed above the details).
-- * Sounds (§18.5.2 B3 / B5, §18.6): the filter chips get the Button press feel and its click / hover (Button.decorate);
--   the cards keep their own ui.click (they are not Buttons); Close, Inspect, View in Shop and Go to Boxes are silent
--   Buttons (ui.back / ui.open play); the equip-failure toast carries ui.error (one sound per action).
-- Part 8 (the two Squishies items of Part 6's Studio run, and the §11.2 audit; layout maths in UI/InventoryFormat):
-- * The detail column is the info list (ScrollingFrame "Detail") with Equip / Inspect / View in Shop pinned under it
--   ("DetailButtons", a sibling, like InspectPanel's InfoButtons), so they are on screen at every size (at Studio's
--   893×673 they sat below the fold). The buttons wrap into rows in the narrow column: InventoryFormat.detailLayout
--   places them from their measured widths (Button.widthFor) and gives the list what is left above them.
-- * The panel's sizes come from InventoryFormat.panelLayout (the ScreenGui's size): the header, the filter row and its
--   chips are touch-sized (Layout.touchBase: the chips were 44 base = 37 px at scale 0.85, under §11.2's minimum). On
--   phones (compact) the detail preview is DETAIL_ICON_COMPACT_PX so more of the info shows above the buttons.
-- * Cards: InventoryFormat.cardSize keeps the 112 × 168 card at the default text size and grows it only when the
--   player's text needs it; the rarity tag sits stacked (pips above the chip) when side by side does not fit ("◆◆◆◆
--   EXCLUSIVE" was wider than the card). The corner badges never overlap: InventoryFormat.cardTags moves the rarity
--   badge ("Ultimate") to a second row when it and "Not owned" / "Equipped" / "NEW" do not fit one row ("Not oUltimate");
--   each badge counts as the larger of its measured size and its drawn size (AbsoluteSize; laid out again when it
--   changes), so a font drawing wider than measured cannot bring the overlap back.
-- * "Show not owned" is as wide as its label needs on one line (Toggle.widthFor; at least TOGGLE_MIN_WIDTH_PX, at most
--   TOGGLE_MAX_SHARE of the row); the chips scroll sideways in the rest of the row.
-- * The gamepad focus on open: the selected card, else the active filter chip, else Close.
-- Foam UI restyle (spec 2026-10-09; look and layout only, every button does what it did):
-- * The title is a Strawberry header tab on the panel's top edge (Theme.headerTab; the panel's top padding follows it,
--   InventoryFormat.panelLayout's topPadding, and the panel sits a quarter of the tab lower so both are centred); the
--   header row keeps a "Collected 4/8" chip and Close.
-- * The filter chips are foam Buttons (Strawberry when active, Frosting otherwise; Button-kind labels).
-- * Cards are foam cards (Frosting face, bevel and ink drop) with a rarity rim (the rarity colour, at least
--   Theme.Stroke.thick; the Epic gradient and Exclusive shimmer stay on the rim); not owned = the disabled face, the
--   greyed preview and a Lilac "Not owned" chip with the lock; the selected card's face is a light Sky. Corner badges are
--   Chips: Equipped (Mint), NEW (Strawberry), Not owned (Lilac, lock), the rarity badge in the rarity colour. Names in
--   the Button display kind (the card is CARD_NAME_ROOM wider than §11.6's 112 for it).
-- * The detail column: the preview in a Biscuit inset well, the name, the rarity tag, an ownership chip, the coins line
--   in the display font, the five stats as foam progress bars (Sky) in an inset field, then trail, ultimate and
--   elimination in Ink2. Fewer words: the "per accepted squeeze…" and "compared with other squishies" sub-lines stay
--   on Inspect only.
-- Foam fix batch (2026-10-09; on an 844×390 phone the detail showed only a sliver of the preview, the buttons wrapped
-- and the cards were cut; layout maths in UI/InventoryFormat):
-- * Close hangs on the panel's top-right corner level with the header tab (as on Quests, Daily and Settings) and the
--   "Collected 4/8" chip on the top-left corner; the Close-only header row is gone, so the filter row starts the
--   content (InventoryFormat.hangingChrome, panelLayout).
-- * The grid is as wide as the columns that fit in its share (InventoryFormat.gridFit); the detail column takes the
--   rest (before, an empty strip of about 135 px sat between them), so on phones its buttons fit one row more often.
-- * The detail preview shrinks so the squishy's name under it stays in view above the pinned buttons (previewPx).
-- * The corner badges stay on one row (the second row sat on the portrait): "Not owned" becomes its lock pip when it
--   and "Ultimate" do not fit side by side; when even that does not fit (an owned Dragon that is Equipped or NEW), the
--   "Ultimate" badge is left out on that card (InventoryFormat.cardBadges; the detail still names the ultimate).
-- Foam fix round 2 (2026-10-09; on a phone the rarity tag under the name was cut in half above the buttons):
-- * The preview leaves room for the name and the rarity tag (RarityTag.tallest); when not even its smallest size fits,
--   the well hides (InventoryFormat.previewPx 0) so the tag is never cut.
-- * The detail buttons keep InventoryFormat.PANEL.buttonGap between them, from the column's left edge, like Shop's.
-- * On touch the detail list's scroll bar stays on screen while it is longer than its window (UI/Components/ScrollHint).
-- UI overhaul (2026-10-11, Candy UI): the cards are collectible cards (UI/CardFace: the rarity's gradient face, the
-- PlumInk outline, the rarity flourish on an inner rim, a glow behind 96 px art, a white frame when selected; locked =
-- the dark disabled face); inactive filter chips are the plum neutral; Close is the red X; the detail preview sits on a
-- glow in the rarity's colour and bobs gently while the screen is open (one StaticIcon, Scheduler; still under
-- ReducedMotion); Reload and Windup bars are Lavender (time: shorter is faster, said by inspect.statsHint under the
-- stats), the others Cyan.
-- Stable names: Squishies_CloseButton, Squishies_Filter<Name>Button, Squishies_ShowNotOwnedToggle,
-- Squishies_Card_<id>, Squishies_EquipButton, Squishies_InspectButton, Squishies_ViewInShopButton,
-- Squishies_GoToBoxesButton.

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local CapsuleMath = require(Shared.CapsuleMath)
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Rarity = require(Shared.Rarity)
local RarityStyle = require(Shared.Art.RarityStyle)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local CardFace = require(Client.UI.CardFace)
local Chip = require(Client.UI.Components.Chip)
local Create = require(Client.UI.Create)
local Focus = require(Client.UI.Focus)
local InventoryFormat = require(Client.UI.InventoryFormat)
local KeyText = require(Client.UI.KeyText)
local Layout = require(Client.UI.Layout)
local LockIcon = require(Client.UI.Components.LockIcon)
local ProgressBar = require(Client.UI.Components.ProgressBar)
local RarityTag = require(Client.UI.Components.RarityTag)
local Scheduler = require(Client.Anim.Scheduler)
local ScrollHint = require(Client.UI.Components.ScrollHint)
local StaticIcon = require(Client.UI.Components.StaticIcon)
local Theme = require(Client.UI.Theme)
local Toggle = require(Client.UI.Components.Toggle)
local Tweens = require(Client.Anim.Tweens)
local UiFx = require(Client.UI.UiFx)
local ControlsController = require(script.Parent.ControlsController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Constants

local SCREEN = "squishies"
local INSPECT_SCREEN = "inspect"
local SHOP_SCREEN = "shop"
local BOXES_SCREEN = "boxes"
local MODAL_GUI = "SD_Modal"
local ACTION = "Squishies"
local KIOSK_TAG = "SD_CollectionKiosk"
local EQUIPPED_TOAST = "inspect.equippedToast"
local INVENTORY = Config.UI.Inventory
local TOUCH = Config.UI.Touch
local ABILITIES = Config.Abilities
local PANEL = InventoryFormat.PANEL -- margin, height share (0.88: never more of the screen), padding, gaps, grid share
-- Foam restyle reading: the names are in the Button display kind, which needs about this much more room than §11.6's
-- 112 px card had for the Body font (InventoryFormat.cardSize still adds a second name line when the widest name needs
-- it; Studio check).
local CARD_NAME_ROOM = 12
local CARD_WIDTH = INVENTORY.cardWidth + CARD_NAME_ROOM
local CARD_HEIGHT = 180 -- reading: §11.6 gives the card width only (UI overhaul: 168 -> 180 for the larger art)
local CARD_ICON_PX = 96 -- UI overhaul: 84 -> 96, the art dominates the card
local CARD_PAD_X = 6 -- Part 8: the card's text keeps off its frame (foam restyle: off the thicker rim too)
local CARD_PAD_Y = 6
local CARD_GAP = 2
local CARD_PIP_PX = 8
local CARD_NAME_KIND: Theme.TextKind = "Button" -- foam restyle: larger type, the display font
local CARD_RADIUS = Theme.Radius.button
local CARD_BANDS = Theme.Foam.panel.bevel + Theme.Foam.panel.drop -- the foam card's bevel and drop (kept free)
local CELL_PAD = PANEL.cellPad
local DETAIL_ICON_PX = 132
local DETAIL_ICON_COMPACT_PX = 88 -- reading (Part 8): on phones more of the info shows above the pinned buttons
local DETAIL_ICON_MIN_PX = 48 -- fix batch: the smallest the preview gets so the name stays in view (previewPx)
local WELL_PAD_PX = 8 -- the inset well around the detail preview
local CLOSE_INSET = 16 -- Close and the Collected chip sit this far from the panel's sides (as on Quests and Settings)
local EMPTY_TOP_PX = 40 -- the filter-empty state: this far under the body's top ...
local EMPTY_SIDE_PX = 20 -- ... and this far inside the grid's sides
local LOCK_PIP_PX = 22 -- the compact "Not owned" badge: a round Lilac pip with the lock (DESIGN §11.6 "lock pip")
local STATS_PAD_PX = 10 -- the stats inset field's padding
local GRID_SHARE = PANEL.gridShare
local SCROLLBAR_PX = 6
-- The corner badges (Part 8: InventoryFormat.cardTags; foam restyle: Chips). Badge = the Chip's padding, lock, gap,
-- text; the rarity badge = padding, text. MEASURE_MARGIN_PX is added to each measured width; TAG_GAP leaves room for
-- both chips' outlines, so the two never touch.
local TAG_INSET = 4
local TAG_GAP = 6
local BADGE_PAD_X = 10 -- reading: Chip's side padding
local BADGE_LOCK_PX = 12
local BADGE_LIST_GAP = 4 -- reading: Chip's gap between the lock and the text
local BADGE_HEIGHT_PX = 22
local MEASURE_MARGIN_PX = 2
local CHIP_ROW_OUTSET = 4 -- the chips' scrolling row reaches this far past the filter row (their outlines show)
local TOGGLE_MIN_WIDTH_PX = 240 -- "Show not owned" at the default text size, as before
local TOGGLE_MAX_SHARE = 0.45 -- reading: the chips keep at least the rest of the filter row
local CARD_BASE: InventoryFormat.CardBase = {
	width = CARD_WIDTH,
	height = CARD_HEIGHT,
	iconPx = CARD_ICON_PX,
	padX = CARD_PAD_X,
	padY = CARD_PAD_Y,
	gap = CARD_GAP,
	bands = CARD_BANDS,
}
local STAT_BAR_PX = 10
local CONFIRM_SECONDS = 5 -- reading: how long "Equipped" shows before the StateDelta must have arrived
local SHIMMER_FULL_TURN = 360
local GENERIC = "error.generic"
local TAB_KIND: Theme.TextKind = "H2" -- the header tab's gap under it is PANEL.tabGap (InventoryFormat.hangingChrome)
-- UI overhaul: the card faces are UI/CardFace's (owned: the rarity's colours; not owned: the dark disabled face; the
-- selected card: a white frame).
local STAT_TIME: { [string]: boolean } = { reload = true, windup = true } -- shorter is faster (Lavender bars)
local PREVIEW_BOB_PX = 3 -- the detail preview's idle bob (base px) ...
local PREVIEW_BOB_SECONDS = 2.6 -- ... one cycle (well under 1 Hz)
local PREVIEW_WOBBLE_DEG = 2 -- ... and its gentle sway
local PREVIEW_GLOW_SHARE = 0.92 -- the glow disc behind the preview, as a share of its size
local PREVIEW_GLOW_TRANSPARENCY = 0.7

-- Module table

local InventoryController = {}

-- Private

type Card = {
	id: string,
	root: TextButton,
	face: CardFace.CardFace, -- UI overhaul: the collectible card's face, rim and art glow
	icon: StaticIcon.StaticIcon,
	stroke: UIStroke, -- the rarity rim (the foam outline in the rarity colour)
	gradient: UIGradient?,
	shimmer: boolean,
	badge: Chip.Chip, -- top-left: Equipped / NEW / Not owned (with the lock)
	badgeBox: InventoryFormat.TagBox?, -- its drawn box while it last showed (kept while the lock pip replaces it)
	lock: Frame,
	lockPip: Frame, -- top-left instead of the "Not owned" chip when it and "Ultimate" do not fit one row
	rarity: RarityTag.RarityTag,
	ultimate: Chip.Chip?, -- the rarity badge (style.card.badgeKey, "Ultimate"), top-right
	tagText: string?, -- the top-left badge's text as painted last (layoutTags), nil = hidden
	tagLocked: boolean, -- ... with the lock
}

type Detail = {
	icon: StaticIcon.StaticIcon,
	well: Frame, -- the inset well around the preview
	glow: Frame, -- UI overhaul: the rarity glow behind the preview
	name: TextLabel,
	rarity: RarityTag.RarityTag,
	ownership: Chip.Chip,
	lock: Frame,
	coins: TextLabel,
	stats: { [string]: { value: TextLabel, bar: ProgressBar.ProgressBar } },
	trail: TextLabel,
	ultimate: TextLabel,
	elimination: TextLabel,
	price: TextLabel,
	error: TextLabel,
	scroll: ScrollingFrame, -- "Detail": the info list
	rail: Frame, -- fix round 2: its scroll bar on touch (ScrollHint), over the list's right edge
	buttons: Frame, -- "DetailButtons": pinned under the list (Part 8)
	equip: Button.Button,
	equipText: string, -- what Equip shows now (its width is measured for the layout)
	equipReason: string?,
	inspect: Button.Button,
	viewInShop: Button.Button,
}

-- The frames the panel layout sizes (Part 8: InventoryFormat.panelLayout; foam restyle: the header tab; fix batch: no
-- header row, Close and the Collected chip hang on the top corners).
type Frames = {
	filterRow: Frame,
	filters: ScrollingFrame,
	tab: Frame,
	padding: UIPadding, -- the panel's (its top follows the tab and Close)
}

local log = Log.new("Inventory")
local cleanup: Cleanup.Cleanup? = nil
local openCleanup: Cleanup.Cleanup? = nil
local panel: Frame? = nil
local frames: Frames? = nil
local closeButton: Button.Button? = nil
local collectedChip: Chip.Chip? = nil
local chips: { [string]: Button.Button } = {}
local chipActive: { [string]: boolean } = {} -- each chip's painted state (Strawberry = its filter is on)
local showNotOwnedToggle: Toggle.Toggle? = nil
local grid: ScrollingFrame? = nil
local gridLayout: UIGridLayout? = nil
local emptyState: Frame? = nil
local emptyLabel: TextLabel? = nil
local goToBoxes: Button.Button? = nil
local loadingLabel: TextLabel? = nil
local body: Frame? = nil
local cards: { [string]: Card } = {}
local detail: Detail? = nil
local panelLayout: InventoryFormat.PanelLayout? = nil
local lastDetail: InventoryFormat.DetailLayout? = nil -- the detail column as laid out last (debugState)
local cardSize: InventoryFormat.CardSize = { width = CARD_WIDTH, height = CARD_HEIGHT, nameLines = 1, stacked = true }
local filter: InventoryFormat.Filter = "All"
local showNotOwned = true
local selected: string? = nil
local pendingEquip: string? = nil
local confirmedEquip: string? = nil
local confirmTimer: thread? = nil

local function currentEntries(): { InventoryFormat.Entry }
	return InventoryFormat.entries(
		Catalog.list(),
		StateController.owned(),
		StateController.equipped(),
		StateController.isNewOwned
	)
end

local function entryOf(list: { InventoryFormat.Entry }, id: string?): InventoryFormat.Entry?
	for _, entry in list do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

local function hasError(): boolean
	local status = StateController.dataStatus()
	return status ~= nil and (status.status == "offline" or status.status == "readonly")
end

local function setText(label: TextLabel?, text: string)
	if label then
		label.Text = text
	end
end

-- Layout (Part 8) -----------------------------------------------------------------------------------------------------

-- The detail column: Equip / Inspect / View in Shop pinned under the info list, wrapped from their measured widths
-- (InventoryFormat.detailLayout); the list scrolls in what is left; the preview is smaller on phones and shrinks so the
-- name under it stays in view (fix batch: InventoryFormat.previewPx).
local function layoutDetail()
	local d, l = detail, panelLayout
	if d == nil or l == nil then
		return
	end
	local shown: { Button.Button } = {}
	local widths: { number } = {}
	local function add(button: Button.Button, text: string, reason: string?)
		if button.root.Visible then
			table.insert(shown, button)
			table.insert(widths, Button.widthFor(text, reason))
		end
	end
	add(d.equip, d.equipText, d.equipReason)
	add(d.inspect, Strings.common.inspect)
	add(d.viewInShop, Strings.inspect.viewInShop)
	local buttonHeight = Layout.touchBase(TOUCH.primaryButton, l.scale)
	local placed = InventoryFormat.detailLayout(l.detailWidth, l.detailHeight, buttonHeight, PANEL.gap, widths)
	lastDetail = placed
	d.scroll.Size = UDim2.fromOffset(l.detailWidth, placed.scrollHeight)
	d.buttons.Position = UDim2.new(1, 0, 0, placed.buttonsTop)
	d.buttons.Size = UDim2.fromOffset(l.detailWidth, placed.buttonsHeight)
	for index, button in shown do
		local r = placed.buttons[index]
		if r then
			button.root.Position = UDim2.fromOffset(r.x + r.w / 2, r.y)
			button.root.Size = UDim2.fromOffset(0, buttonHeight)
		end
	end
	d.rail.Size = UDim2.fromOffset(SCROLLBAR_PX, placed.scrollHeight)
	-- Under the well: the list's gap, the name (Title), a gap and (fix round 2) the rarity tag stay in view; with no
	-- room for the smallest preview the well hides (previewPx 0) rather than cut the tag.
	local reserve = 2 * Theme.Padding.small + Theme.lineHeight("Title") + RarityTag.tallest()
	local iconPx = InventoryFormat.previewPx(
		placed.scrollHeight,
		reserve,
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

-- A badge's drawn size in the card's base px (its AbsoluteSize over the card's drawn scale), or nil before it is drawn.
local function drawnBox(card: Card, object: GuiObject): InventoryFormat.TagBox?
	local k = card.root.AbsoluteSize.X / math.max(cardSize.width, 1)
	local size = object.AbsoluteSize
	if k <= 0 or size.X <= 0 or size.Y <= 0 then
		return nil
	end
	return { w = size.X / k, h = size.Y / k }
end

-- The larger of a measured and a drawn box (the drawn one also covers what the measure cannot know).
local function largerBox(measured: InventoryFormat.TagBox, drawn: InventoryFormat.TagBox?): InventoryFormat.TagBox
	if drawn == nil then
		return measured
	end
	return { w = math.max(measured.w, drawn.w + MEASURE_MARGIN_PX), h = math.max(measured.h, drawn.h) }
end

-- The corner badges of one card on one row (fix batch: InventoryFormat.cardBadges; Part 8's second row sat on the
-- portrait): when the left badge (`badgeText`, with the lock when `locked`) and the rarity badge ("Ultimate") do not
-- fit side by side, "Not owned" shows as its lock pip; when even that does not fit, the rarity badge is left out. Each
-- badge counts as the larger of its measured size (Theme.textBounds) and its drawn size (AbsoluteSize, once drawn;
-- layoutTags runs again when a badge's drawn size changes), so a font that draws wider than measured never brings
-- back the overlap.
local function layoutTags(card: Card, badgeText: string?, locked: boolean)
	card.tagText, card.tagLocked = badgeText, locked
	card.lockPip.Visible = false
	local ultimate = card.ultimate
	if ultimate == nil then
		return
	end
	local left: InventoryFormat.TagBox? = nil
	if badgeText then
		-- Review fix: the chip's drawn box is remembered while it shows, so a relayout while the lock pip stands in for it
		-- (the chip hidden) still counts a font that draws wider than measured and never brings back the overlap.
		if card.badge.root.Visible then
			card.badgeBox = drawnBox(card, card.badge.root) or card.badgeBox
		end
		local bounds = Theme.textBounds(badgeText, "Chip")
		local lockWidth = if locked then BADGE_LOCK_PX + BADGE_LIST_GAP else 0
		left = largerBox({
			w = math.ceil(bounds.X) + lockWidth + 2 * BADGE_PAD_X + MEASURE_MARGIN_PX,
			h = math.max(math.ceil(bounds.Y), BADGE_HEIGHT_PX),
		}, card.badgeBox)
	end
	local bounds = Theme.textBounds(ultimate.label.Text, "Chip")
	local right = largerBox({
		w = math.ceil(bounds.X) + 2 * BADGE_PAD_X + MEASURE_MARGIN_PX,
		h = math.max(math.ceil(bounds.Y), BADGE_HEIGHT_PX),
	}, drawnBox(card, ultimate.root))
	local compact: InventoryFormat.TagBox? = if badgeText and locked
		then { w = LOCK_PIP_PX + MEASURE_MARGIN_PX, h = LOCK_PIP_PX }
		else nil
	local badges = InventoryFormat.cardBadges(cardSize.width, TAG_INSET, TAG_GAP, left, right, compact)
	card.badge.root.Visible = badgeText ~= nil and not badges.compact
	card.lockPip.Visible = badges.compact
	ultimate.root.Visible = badges.rightShown
	ultimate.root.Position = UDim2.new(1, -TAG_INSET, 0, TAG_INSET)
end

-- The card size for the player's text size (InventoryFormat.cardSize): names, words and every rarity tag measured.
local function measureCards(): InventoryFormat.CardSize
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
	return InventoryFormat.cardSize(CARD_BASE, metrics)
end

-- The grid's columns: the ones panelLayout fitted (InventoryFormat.gridFit; the grid is exactly that wide).
local function updateColumns()
	local layout, l = gridLayout, panelLayout
	if layout == nil or l == nil then
		return
	end
	layout.FillDirectionMaxCells = math.max(1, l.columns)
end

-- The cells follow the card size; the rarity tags stack when the card needs it. (The grid's width follows in
-- applyLayout: the columns depend on the card width.)
local function applyCardSize()
	cardSize = measureCards()
	local layout = gridLayout
	if layout then
		layout.CellSize = UDim2.fromOffset(cardSize.width, cardSize.height)
	end
	for _, card in cards do
		card.rarity:setStacked(cardSize.stacked)
	end
end

-- The header tab and Close at the player's text size (fix batch: InventoryFormat.hangingChrome): the tab stays centred
-- on the panel's top edge, Close hangs on the top-right corner and the Collected chip on the top-left corner, level with
-- it; the panel's top padding keeps the gap under their lower halves, and the panel moves down by half of what hangs
-- above it (both centred together). Returns the top padding.
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
	local collected = collectedChip
	if collected then
		collected.root.Position = UDim2.fromOffset(CLOSE_INSET - PANEL.padding, -chrome.top)
	end
	root.Position = UDim2.new(0.5, 0, 0.5, chrome.shift)
	return chrome.top
end

-- Every size of the panel from the ScreenGui's size (InventoryFormat.panelLayout), then the detail column.
local function applyLayout()
	local root, f = panel, frames
	if root == nil or f == nil then
		return
	end
	local top = fitChrome(root, f)
	local l = InventoryFormat.panelLayout(UIController.screenGui(MODAL_GUI).AbsoluteSize, top, cardSize.width)
	panelLayout = l
	root.Size = UDim2.new(0, l.panelWidth, PANEL.heightShare, 0)
	f.filterRow.Position = UDim2.fromOffset(0, 0)
	f.filterRow.Size = UDim2.new(1, 0, 0, l.rowHeight)
	for _, chip in chips do
		chip.root.Size = UDim2.fromOffset(0, l.rowHeight)
	end
	local toggleWidth = TOGGLE_MIN_WIDTH_PX
	local toggle = showNotOwnedToggle
	if toggle then
		local widest = math.max(TOGGLE_MIN_WIDTH_PX, math.floor(l.contentWidth * TOGGLE_MAX_SHARE))
		toggleWidth = math.clamp(Toggle.widthFor(Strings.inventory.showNotOwned), TOGGLE_MIN_WIDTH_PX, widest)
		toggle.root.Size = UDim2.fromOffset(toggleWidth, l.rowHeight)
	end
	f.filters.Size = UDim2.new(1, -(toggleWidth + PANEL.columnGap), 1, 2 * CHIP_ROW_OUTSET)
	local b = body
	if b then
		b.Position = UDim2.fromOffset(0, l.bodyTop)
		b.Size = UDim2.new(1, 0, 1, -l.bodyTop)
	end
	-- The grid is as wide as its columns (the detail column takes the rest); the empty state is centred over it.
	local g = grid
	if g then
		g.Size = UDim2.new(0, l.gridWidth, 1, 0)
	end
	local empty = emptyState
	if empty then
		empty.Position = UDim2.fromOffset(l.gridWidth / 2, EMPTY_TOP_PX)
		empty.Size = UDim2.fromOffset(math.max(0, l.gridWidth - 2 * EMPTY_SIDE_PX), 0)
	end
	local close = closeButton
	if close then
		close.root.Size = UDim2.fromOffset(l.closeHeight, l.closeHeight) -- UI overhaul: the square red X
	end
	layoutDetail()
	updateColumns()
end

-- Detail panel ------------------------------------------------------------------------------------------------------

local function refreshDetail(list: { InventoryFormat.Entry })
	local d = detail
	if d == nil then
		return
	end
	local entry = entryOf(list, selected)
	d.error.Visible = hasError()
	if entry == nil then
		return
	end
	local def = entry.def
	d.icon:setSquishy(entry.id)
	d.icon:setOwned(entry.owned)
	d.name.Text = entry.name
	d.rarity:setRarity(entry.rarity)
	local rarityStyle = RarityStyle.get(entry.rarity)
	d.glow.BackgroundColor3 = if rarityStyle then rarityStyle.ui.glow else Theme.Colors.ink2
	d.glow.BackgroundTransparency = if entry.owned then PREVIEW_GLOW_TRANSPARENCY else 0.9
	d.ownership:setText(KeyText.get(InventoryFormat.ownershipKey(entry)))
	d.ownership:setAccent(if entry.equipped then "mint" elseif entry.owned then "frosting" else "lilac")
	d.ownership.root.Visible = true
	d.lock.Visible = not entry.owned
	-- Phase 5 (progression spec 2026-10-12 §6): what the squishy multiplies in a capsule ("x16 power").
	d.coins.Text = Strings.format(Strings.capsule.power, { n = CapsuleMath.squishyPower(entry.id) })
	for _, bar in InventoryFormat.statBars(def) do
		local view = d.stats[bar.stat]
		if view then
			view.value.Text =
				Strings.format(Strings.inspect.statValue, { value = bar.value, unit = KeyText.get(bar.unitKey) })
			view.bar:set(bar.fraction, false)
		end
	end
	local trail = RarityStyle.trail(def.visuals.trail)
	d.trail.Text = if trail
		then Strings.format(Strings.trail.label, { name = KeyText.get(trail.nameKey) })
		else Strings.trail.none
	local ability = if def.ultimateId then ABILITIES[def.ultimateId] else nil
	d.ultimate.Visible = ability ~= nil
	if ability then
		d.ultimate.Text = Strings.format(Strings.inspect.ultimate, {
			name = KeyText.get(ability.nameKey),
			description = KeyText.get(ability.descriptionKey, { seconds = ability.telegraphSeconds }),
		})
	end
	d.elimination.Text = Strings.format(Strings.inspect.elimination, { name = Strings.elimination.standard })
	local price = def.shopPrice
	d.price.Visible = not entry.owned and price ~= nil
	if price then
		d.price.Text = Strings.format(Strings.inspect.shopPrice, { price = Format.coins(price) })
	end
	d.viewInShop.root.Visible = not entry.owned and price ~= nil and UIController.isRegistered(SHOP_SCREEN)
	d.inspect.root.Visible = UIController.isRegistered(INSPECT_SCREEN)

	local state = InventoryFormat.equipState(entry, {
		locked = StateController.isLobbyLocked(),
		pending = pendingEquip,
		confirmed = confirmedEquip,
	})
	local equip = d.equip
	local reason: string? = nil
	if state == "equip" then
		d.equipText = Strings.common.equip
		equip:setText(d.equipText)
		equip:setState("normal")
	elseif state == "equipped" then
		d.equipText = Strings.common.equipped
		equip:setText(d.equipText)
		equip:setState("disabled")
	elseif state == "notOwned" then
		d.equipText = Strings.common.notOwned
		equip:setText(d.equipText)
		equip:setState("disabled")
	elseif state == "locked" then
		d.equipText = Strings.common.equip
		reason = Strings.common.lockedInDuel
		equip:setText(d.equipText)
		equip:setState("disabled", reason)
	else
		equip:setState("loading") -- keeps its text and its place
	end
	d.equipReason = reason
	layoutDetail()
end

-- Grid ----------------------------------------------------------------------------------------------------------------

-- Fix batch: the Collected chip hangs above the panel's edge, so it shows only while Squishies is the top screen (a
-- screen opened over it, like Inspect, covers the panel but not what hangs above it) and once the profile is loaded.
local function refreshCollected()
	local collected = collectedChip
	if collected then
		local top = UIController.topModal()
		collected.root.Visible = StateController.isLoaded() and (top == nil or top == SCREEN)
	end
end

local function paintCard(card: Card, entry: InventoryFormat.Entry, isSelected: boolean)
	card.face:paint({ owned = entry.owned, selected = isSelected })
	card.icon:setOwned(entry.owned)
	-- The top-left chip: Equipped (Mint), NEW (Strawberry) or Not owned (Lilac, with the lock).
	local badgeText: string? = nil
	local accent: Theme.AccentName = "lilac"
	if entry.equipped then
		badgeText = Strings.common.equipped
		accent = "mint"
	elseif entry.isNew then
		badgeText = Strings.inventory.new
		accent = "strawberry"
	elseif not entry.owned then
		badgeText = Strings.common.notOwned
	end
	card.badge.root.Visible = badgeText ~= nil
	card.badge:setText(badgeText or "")
	card.badge:setAccent(accent)
	card.lock.Visible = not entry.owned
	layoutTags(card, badgeText, not entry.owned)
end

local function refreshGrid(list: { InventoryFormat.Entry })
	local shownList = InventoryFormat.visible(list, filter, showNotOwned)
	selected = InventoryFormat.keepSelection(selected, shownList)
	local visibleIds: { [string]: number } = {}
	for index, entry in shownList do
		visibleIds[entry.id] = index
	end
	for _, entry in list do
		local card = cards[entry.id]
		if card then
			local index = visibleIds[entry.id]
			card.root.Visible = index ~= nil
			card.root.LayoutOrder = index or 0
			paintCard(card, entry, entry.id == selected)
		end
	end
	local counts = InventoryFormat.chipCounts(list, showNotOwned)
	for name, chip in chips do
		chip:setText(InventoryFormat.chipText(name, counts[name] or 0))
		-- Repainted only when it changes (a repaint restarts the Button's press motion).
		local active = name == filter
		if chipActive[name] ~= active then
			chipActive[name] = active
			chip:setAccent(if active then "strawberry" else "plum")
		end
	end
	local owned, total = InventoryFormat.collected(list)
	local collected = collectedChip
	if collected then
		collected:setText(Strings.format(Strings.inventory.collected, { n = owned, total = total }))
	end
	refreshCollected()
	local empty = #shownList == 0
	if emptyState then
		emptyState.Visible = empty
	end
	if empty then
		setText(emptyLabel, InventoryFormat.emptyText(filter))
	end
	if goToBoxes then
		goToBoxes.root.Visible = empty and UIController.isRegistered(BOXES_SCREEN)
	end
end

local function refresh()
	if panel == nil then
		return
	end
	local loaded = StateController.isLoaded()
	if loadingLabel then
		loadingLabel.Visible = not loaded
	end
	if body then
		body.Visible = loaded
	end
	if not loaded then
		return
	end
	if showNotOwnedToggle then
		showNotOwnedToggle:setValue(showNotOwned)
	end
	local list = currentEntries()
	refreshGrid(list)
	refreshDetail(list)
end

local function selectCard(id: string)
	selected = id
	StateController.markOwnedSeen(id)
	SoundController.play("ui.click")
	refresh()
end

-- UI overhaul: the visible cards' contents in grid order (the entrance cascade).
local function cardContents(): { GuiObject }
	local shown: { Card } = {}
	for _, card in cards do
		if card.root.Visible then
			table.insert(shown, card)
		end
	end
	table.sort(shown, function(a: Card, b: Card): boolean
		return a.root.LayoutOrder < b.root.LayoutOrder
	end)
	local list: { GuiObject } = {}
	for _, card in shown do
		local content = card.root:FindFirstChild("Content")
		if content and content:IsA("GuiObject") then
			table.insert(list, content)
		end
	end
	return list
end

local function setFilter(newFilter: InventoryFormat.Filter)
	filter = newFilter
	refresh()
	-- UI overhaul: a filter change settles the grid's contents (no stagger, never the whole panel).
	local settle = Config.UI.motion.tabSettle
	UiFx.cascade(SCREEN, cardContents(), { from = settle.scaleFrom, ms = settle.ms, staggerMs = 0 })
end

local function equipSelected()
	local id = selected
	if id == nil or pendingEquip ~= nil then
		return
	end
	pendingEquip = id
	refresh()
	local result = NetController.equipSquishyAsync(id)
	pendingEquip = nil
	if result.ok then
		confirmedEquip = id
		if confirmTimer then
			task.cancel(confirmTimer)
		end
		confirmTimer = task.delay(CONFIRM_SECONDS, function()
			confirmTimer = nil
			confirmedEquip = nil
			refresh()
		end)
		NotifyController.show(EQUIPPED_TOAST, nil, "success")
		-- UI overhaul: a brief ring and sparkles in the rarity's glow on the preview, once the server said yes.
		local d = detail
		local def = Catalog.get(id)
		local style = if def then RarityStyle.get(def.rarity) else nil
		if d and d.well.Visible then
			UiFx.burst(d.well, "small", if style then style.ui.glow else nil)
			UiFx.punch(d.icon.root, 1.12)
		end
	else
		local reason = result.reason
		local known = type(reason) == "string" and reason ~= GENERIC and KeyText.has("reason." .. reason)
		-- One sound per action (§18.5.2 B5): the toast carries ui.error.
		UIController.toast(
			if known then Strings.reasonText(reason) else Strings.inspect.equipFailed,
			"warn",
			{ sound = "ui.error" }
		)
	end
	refresh()
end

-- Builders -----------------------------------------------------------------------------------------------------------

local function buildCard(c: Cleanup.Cleanup, parent: Instance, id: string)
	local def = Catalog.get(id)
	if def == nil then
		return
	end
	local style = RarityStyle.get(def.rarity)
	local root: TextButton = Create("TextButton", {
		Name = "Squishies_Card_" .. id,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	})
	c:add(root)
	-- UI overhaul: a collectible card (UI/CardFace: the rarity's face, the PlumInk outline, the rarity flourish on the
	-- rim, the glow behind the art); paintCard paints its state.
	local face = CardFace.new(root, def.rarity, {
		radius = CARD_RADIUS,
		artCenterY = CARD_PAD_Y + CARD_ICON_PX / 2,
		artPx = CARD_ICON_PX,
	})
	c:add(face)
	Focus.decorate(root, CARD_RADIUS)
	local stroke = face.rim
	local gradient: UIGradient? = face.gradient
	local shimmer = style ~= nil and style.card.gradient ~= nil and style.card.gradient.shimmerDegPerSecond ~= nil

	-- Content (laid out top to bottom) and an overlay for the corner badges (not laid out). UI overhaul: anchored at its
	-- centre, so the entrance cascade (UiFx.cascade) pops it from the middle.
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
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
		PaddingTop = UDim.new(0, CARD_PAD_Y),
		PaddingBottom = UDim.new(0, CARD_PAD_Y + CARD_BANDS), -- the foam bands stay free (InventoryFormat.cardSize)
		PaddingLeft = UDim.new(0, CARD_PAD_X),
		PaddingRight = UDim.new(0, CARD_PAD_X),
		Parent = content,
	})
	local icon = StaticIcon.new({
		name = "Preview",
		squishyId = id,
		sizePx = CARD_ICON_PX,
		layoutOrder = 1,
		parent = content,
	})
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

	local overlay: Frame = Create("Frame", {
		Name = "Overlay",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = 2,
		Parent = root,
	})
	-- The corner badges are Chips (paintCard picks the text and the accent; the lock sits before the text).
	local badge = Chip.new({ name = "Badge", text = "", heightPx = BADGE_HEIGHT_PX, parent = overlay })
	c:add(badge)
	badge.root.Position = UDim2.fromOffset(TAG_INSET, TAG_INSET)
	badge.root.Visible = false
	badge.root.ZIndex = 2
	local lock = LockIcon.new({ name = "Lock", sizePx = BADGE_LOCK_PX, layoutOrder = 0, parent = badge.root })
	c:add(lock)
	-- Fix batch: the compact "Not owned" badge, a round Lilac pip with the lock (layoutTags shows it instead of the chip
	-- when the chip and "Ultimate" do not fit one row; the greyed card and the detail still say "Not owned").
	local lockPip: Frame = Create("Frame", {
		Name = "LockPip",
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(TAG_INSET, TAG_INSET),
		Size = UDim2.fromOffset(LOCK_PIP_PX, LOCK_PIP_PX),
		Visible = false,
		ZIndex = 2,
		Parent = overlay,
	})
	Theme.foam(lockPip, { radius = Theme.Radius.pill, stroke = Theme.Stroke.bar, colors = Theme.accentColors("lilac") })
	local pipLock = LockIcon.new({ name = "Lock", sizePx = BADGE_LOCK_PX, parent = lockPip })
	pipLock.root.AnchorPoint = Vector2.new(0.5, 0.5)
	pipLock.root.Position = UDim2.fromScale(0.5, 0.5)
	c:add(pipLock)
	local ultimate: Chip.Chip? = nil
	if style and style.card.badgeKey then
		local rarityBadge = Chip.new({
			name = "UltimateBadge",
			text = KeyText.get(style.card.badgeKey),
			heightPx = BADGE_HEIGHT_PX,
			parent = overlay,
		})
		c:add(rarityBadge)
		rarityBadge:setColor(style.color, style.labelTextColor)
		rarityBadge.root.AnchorPoint = Vector2.new(1, 0)
		rarityBadge.root.Position = UDim2.new(1, -TAG_INSET, 0, TAG_INSET)
		rarityBadge.root.ZIndex = 2
		ultimate = rarityBadge
	end

	c:add(root.Activated:Connect(function()
		selectCard(id)
	end))
	root.Parent = parent
	local card: Card = {
		id = id,
		root = root,
		face = face,
		icon = icon,
		stroke = stroke,
		gradient = gradient,
		shimmer = shimmer,
		badge = badge,
		badgeBox = nil,
		lock = lock.root,
		lockPip = lockPip,
		rarity = rarityTag,
		ultimate = ultimate,
		tagText = nil,
		tagLocked = false,
	}
	cards[id] = card
	if ultimate then
		-- Part 8: the badges are laid out again from their drawn sizes (layoutTags) when those change.
		local function relayout()
			layoutTags(card, card.tagText, card.tagLocked)
		end
		c:add(badge.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))
		c:add(ultimate.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))
	end
end

-- The filter chips in a sideways-scrolling row (sized by applyLayout); returns that row. Each chip is a foam Button
-- (its press feel, click / hover sounds and focus ring): Strawberry while its filter is on, else Frosting (refreshGrid).
local function buildChips(c: Cleanup.Cleanup, parent: Instance): ScrollingFrame
	local chipHeight = Layout.touchBase(TOUCH.minTarget, UIController.scale())
	-- The scrolling row reaches CHIP_ROW_OUTSET past the filter row above and below (into the gaps), and keeps as much
	-- room at its ends, so the chips' foam outlines are never cut by its clipping.
	local row: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Filters",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, -CHIP_ROW_OUTSET),
		Size = UDim2.new(1, -(TOGGLE_MIN_WIDTH_PX + PANEL.columnGap), 1, 2 * CHIP_ROW_OUTSET),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		Parent = parent,
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, CHIP_ROW_OUTSET),
		PaddingRight = UDim.new(0, CHIP_ROW_OUTSET),
		Parent = row,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, row, Enum.HorizontalAlignment.Left)
	for index, name in InventoryFormat.FILTERS do
		local chip = Button.new({
			name = "Squishies_Filter" .. name .. "Button",
			text = InventoryFormat.chipText(name, 0),
			height = chipHeight, -- §11.2 touch size (was 44 base = 37 px at scale 0.85)
			layoutOrder = index,
			parent = row,
			onActivated = function()
				setFilter(name)
			end,
		})
		c:add(chip)
		chips[name] = chip
	end
	return row
end

local function detailLabel(parent: Instance, name: string, order: number, kind: Theme.TextKind?): TextLabel
	return Theme.label({
		Name = name,
		LayoutOrder = order,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}, kind or "Body")
end

local function buildDetail(c: Cleanup.Cleanup, parent: Instance)
	-- The info list (its height comes from layoutDetail: what is left above the pinned buttons).
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
		Parent = parent,
	})
	-- The left padding keeps the chips' outlines inside the list's clipping.
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
	Theme.corner(glowPx, glow)
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
	-- Equipped (Mint) / Owned (Frosting) / Not owned (Lilac, with the lock): refreshDetail.
	local ownership = Chip.new({ name = "Ownership", text = "", layoutOrder = 5, parent = scroll })
	ownership.root.Visible = false -- shown with its text (refreshDetail)
	c:add(ownership)
	local lock = LockIcon.new({ name = "Lock", sizePx = BADGE_LOCK_PX, layoutOrder = 0, parent = ownership.root })
	c:add(lock)
	local coins = detailLabel(scroll, "Coins", 6, "H2")

	-- The five stats as foam progress bars in an inset field (fewer words: no sub-lines here; Inspect has them).
	local statsField = Theme.inset({
		Name = "Stats",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 7,
		Parent = scroll,
	}, Theme.Radius.button, STATS_PAD_PX)
	Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.small,
		statsField,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local stats: { [string]: { value: TextLabel, bar: ProgressBar.ProgressBar } } = {}
	for index, bar in InventoryFormat.statBars(Catalog.list()[1]) do
		local row: Frame = Create("Frame", {
			Name = "Stat_" .. bar.stat,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = index,
			Parent = statsField,
		})
		Theme.list(Enum.FillDirection.Vertical, 3, row, Enum.HorizontalAlignment.Left)
		local header: Frame = Create("Frame", {
			Name = "Header",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			Parent = row,
		})
		Theme.label({
			Name = "Label",
			Text = KeyText.get(bar.labelKey),
			Size = UDim2.fromScale(0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = header,
		}, "Body", Enum.FontWeight.Bold)
		local value = Theme.label({
			Name = "Value",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = header,
		}, "Body")
		local statBar = ProgressBar.new({
			name = "Bar",
			accent = if STAT_TIME[bar.stat] then "lilac" else "sky",
			heightPx = STAT_BAR_PX,
			layoutOrder = 2,
			parent = row,
		})
		c:add(statBar)
		stats[bar.stat] = { value = value, bar = statBar }
	end
	-- UI overhaul: the time stats are "shorter is faster" (the bars show the value, not "better").
	Theme.label({
		Name = "StatsHint",
		Text = Strings.inspect.statsHint,
		LayoutOrder = 99,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = statsField,
	}, "Small", nil, Theme.Colors.ink2)
	local trail = detailLabel(scroll, "Trail", 20, "Small")
	local ultimate = detailLabel(scroll, "Ultimate", 21, "Small")
	local elimination = detailLabel(scroll, "Elimination", 22, "Small")
	for _, secondary in { trail, ultimate, elimination } do
		secondary.TextColor3 = Theme.Colors.ink2
	end
	local price = detailLabel(scroll, "Price", 23, "Body")
	price.FontFace = Theme.font("Body", Enum.FontWeight.Bold)

	-- Part 8: the buttons are pinned under the list (a sibling of it, not inside it), so they never scroll below the
	-- fold; layoutDetail places them (no UIListLayout: InventoryFormat.detailLayout decides the rows).
	local buttons: Frame = Create("Frame", {
		Name = "DetailButtons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.new(1 - GRID_SHARE, -PANEL.columnGap, 0, 0),
		Parent = parent,
	})
	local equip = Button.new({
		name = "Squishies_EquipButton",
		text = Strings.common.equip,
		kind = "primary",
		height = TOUCH.primaryButton,
		layoutOrder = 1,
		parent = buttons,
		onActivated = equipSelected,
	})
	c:add(equip)
	local inspect = Button.new({
		name = "Squishies_InspectButton",
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
	local viewInShop = Button.new({
		name = "Squishies_ViewInShopButton",
		text = Strings.inspect.viewInShop,
		height = TOUCH.primaryButton,
		layoutOrder = 3,
		parent = buttons,
		sound = false, -- opens a screen: ui.open plays instead
		onActivated = function()
			local id = selected
			if id then
				UIController.close(SCREEN, "viewInShop")
				UIController.open(SHOP_SCREEN, { squishyId = id })
			end
		end,
	})
	viewInShop.root.Visible = false
	c:add(viewInShop)
	for _, button in { equip, inspect, viewInShop } do
		button.root.AnchorPoint = Vector2.new(0.5, 0) -- centred in its measured slot (layoutDetail)
	end

	detail = {
		icon = icon,
		well = well,
		glow = glow,
		name = name,
		rarity = rarity,
		ownership = ownership,
		lock = lock.root,
		coins = coins,
		stats = stats,
		trail = trail,
		ultimate = ultimate,
		elimination = elimination,
		price = price,
		error = errorLabel,
		scroll = scroll,
		rail = scrollHint.root,
		buttons = buttons,
		equip = equip,
		equipText = Strings.common.equip,
		equipReason = nil,
		inspect = inspect,
		viewInShop = viewInShop,
	}
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local root = Theme.panel({
		Name = "Squishies",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, Config.UI.modalMaxWidth, PANEL.heightShare, 0),
		Parent = parent,
	}, Theme.Radius.panel, PANEL.padding)
	c:add(root)
	local rowHeight = Layout.touchBase(TOUCH.minTarget, UIController.scale())

	-- The title: a Strawberry header tab on the panel's top edge (the Squishies tile's colour; fitChrome follows it).
	local tab = Theme.headerTab(root, Strings.inventory.title, { textKind = TAB_KIND })

	-- Fix batch: no header row. The collected count hangs on the top-left corner and Close on the top-right corner,
	-- level with the tab (fitChrome places them; drawn over the panel's outline like the tab).
	local collected = Chip.new({ name = "Collected", text = "", parent = root })
	collected.root.AnchorPoint = Vector2.new(0, 0.5)
	collected.root.ZIndex = tab.ZIndex
	collected.root.Visible = false -- shown with its count once the profile is loaded (refreshGrid)
	c:add(collected)
	collectedChip = collected
	local close = Button.new({
		name = "Squishies_CloseButton",
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

	-- Filters: chips + "Show not owned" (the first row of the content).
	local filters: Frame = Create("Frame", {
		Name = "FilterRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, rowHeight),
		Parent = root,
	})
	local chipRow = buildChips(c, filters)
	local toggle = Toggle.new({
		name = "Squishies_ShowNotOwnedToggle",
		text = Strings.inventory.showNotOwned,
		value = showNotOwned,
		widthPx = TOGGLE_MIN_WIDTH_PX, -- applyLayout widens it when the player's text needs it
		parent = filters,
		onChanged = function(on: boolean)
			showNotOwned = on
			refresh()
		end,
	})
	toggle.root.AnchorPoint = Vector2.new(1, 0)
	toggle.root.Position = UDim2.fromScale(1, 0)
	c:add(toggle)
	showNotOwnedToggle = toggle
	frames = {
		filterRow = filters,
		filters = chipRow,
		tab = tab,
		padding = root:FindFirstChildOfClass("UIPadding") :: UIPadding,
	}

	-- Body: grid + detail (applyLayout sizes both columns).
	local top = rowHeight + PANEL.gap
	local content: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -top),
		Parent = root,
	})
	body = content
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
	-- InventoryFormat.PANEL.gridChrome (4 + the scrollbar + 4), which gridFit counts.
	Create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, SCROLLBAR_PX + 4),
		Parent = gridFrame,
	})
	cardSize = measureCards()
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

	local empty: Frame = Create("Frame", {
		Name = "Empty",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(GRID_SHARE / 2, 0, 0, EMPTY_TOP_PX), -- applyLayout centres it over the grid
		Size = UDim2.new(GRID_SHARE, -2 * EMPTY_SIDE_PX, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = content,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.medium, empty)
	emptyLabel = Theme.label({
		Name = "Text",
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = empty,
	}, "Body")
	local boxes = Button.new({
		name = "Squishies_GoToBoxesButton",
		text = Strings.inventory.goToBoxes,
		kind = "primary",
		height = TOUCH.primaryButton,
		layoutOrder = 2,
		parent = empty,
		sound = false, -- opens a screen: ui.open plays instead
		onActivated = function()
			UIController.close(SCREEN, "goToBoxes")
			UIController.open(BOXES_SCREEN)
		end,
	})
	c:add(boxes)
	goToBoxes = boxes
	emptyState = empty

	buildDetail(c, content)

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
			refresh() -- the corner badges are measured again
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

-- Shimmer of Exclusive card frames (§4.3: 45°/s; static under ReducedMotion), only while the screen is open.
local function startShimmer(c: Cleanup.Cleanup)
	local speeds: { [Card]: number } = {}
	for _, card in cards do
		local def = Catalog.get(card.id)
		local style = if def then RarityStyle.get(def.rarity) else nil
		local speed = if style and style.card.gradient then style.card.gradient.shimmerDegPerSecond else nil
		if card.shimmer and card.gradient and speed then
			speeds[card] = speed
		end
	end
	if next(speeds) == nil then
		return
	end
	c:add(Scheduler.add(function(dt: number): boolean
		if Tweens.reducedMotion() then
			return true
		end
		for card, speed in speeds do
			local gradient = card.gradient
			if gradient and card.root.Visible then
				gradient.Rotation = (gradient.Rotation + speed * dt) % SHIMMER_FULL_TURN
			end
		end
		return true
	end, "render"))
end

-- Gamepad: keeps the selected card inside the grid's visible part (§11.4 "scroll to the selected cell"; the engine
-- may already do it: play-check), only while the screen is open.
local function followSelection(c: Cleanup.Cleanup)
	c:add(GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local frame = grid
		local object = GuiService.SelectedObject
		if frame == nil or object == nil or object.Parent ~= frame then
			return
		end
		-- Absolute values are screen px; reading: CanvasPosition is in the frame's own (unscaled) px, so the
		-- differences are divided by the UIScale.
		local scale = math.max(UIController.scale(), 1e-3)
		local top = (object.AbsolutePosition.Y - frame.AbsolutePosition.Y) / scale
		local bottom = top + object.AbsoluteSize.Y / scale
		local view = frame.AbsoluteWindowSize.Y / scale
		local position = frame.CanvasPosition
		if top < 0 then
			frame.CanvasPosition = Vector2.new(position.X, math.max(0, position.Y + top))
		elseif bottom > view then
			frame.CanvasPosition = Vector2.new(position.X, position.Y + bottom - view)
		end
	end))
end

-- Public -------------------------------------------------------------------------------------------------------------

-- Opens the screen, optionally on one squishy (e.g. an onboarding hint). Returns UIController.open's result.
function InventoryController.open(squishyId: string?): boolean
	return UIController.open(SCREEN, if squishyId then { squishyId = squishyId } else nil)
end

-- Small table for Studio debug hooks.
function InventoryController.debugState(): { [string]: any }
	local visible = {}
	for id, card in cards do
		if card.root.Visible then
			table.insert(visible, id)
		end
	end
	table.sort(visible)
	local placed = lastDetail
	return {
		built = panel ~= nil,
		filter = filter,
		showNotOwned = showNotOwned,
		selected = selected,
		visible = visible,
		pending = pendingEquip,
		-- Part 8: the card size and the pinned detail buttons (base px); fix batch: the fitted grid
		card = { width = cardSize.width, height = cardSize.height, stacked = cardSize.stacked },
		grid = if panelLayout
			then { columns = panelLayout.columns, width = panelLayout.gridWidth, detailWidth = panelLayout.detailWidth }
			else nil,
		detailButtons = if placed
			then {
				rows = placed.rows,
				scrollHeight = placed.scrollHeight,
				buttonsTop = placed.buttonsTop,
				buttonsHeight = placed.buttonsHeight,
			}
			else nil,
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function InventoryController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(UIController.registerScreen(SCREEN, {
		build = build,
		onOpen = function(params: any?)
			if
				type(params) == "table"
				and type(params.squishyId) == "string"
				and Catalog.isValidId(params.squishyId)
			then
				selected = params.squishyId
				filter = "All"
			elseif selected == nil then
				selected = StateController.equipped()
			end
			local oc = Cleanup.new()
			if openCleanup then
				openCleanup:clean()
			end
			openCleanup = oc
			startShimmer(oc)
			startPreviewBob(oc)
			followSelection(oc)
			refresh()
			UiFx.cascade(SCREEN, cardContents()) -- UI overhaul: the cards pop in one after another (capped)
		end,
		onClose = function()
			if openCleanup then
				openCleanup:clean()
				openCleanup = nil
			end
		end,
		primary = function(): GuiObject?
			-- The selected card; else the active filter chip (an empty filter); else Close (Part 8: never nothing).
			local card = if selected then cards[selected] else nil
			if card and card.root.Visible then
				return card.root
			end
			local chip = chips[filter]
			if chip then
				return chip.root
			end
			return if closeButton then closeButton.root else nil
		end,
		onTab = function(direction: number)
			setFilter(InventoryFormat.nextFilter(filter, direction))
		end,
	}))
	c:add(ControlsController.bindAction(ACTION, function(inputState: Enum.UserInputState): boolean?
		if inputState ~= Enum.UserInputState.Begin then
			return nil
		end
		if UIController.isOpen(SCREEN) then
			return UIController.close(SCREEN, "key")
		end
		return UIController.open(SCREEN)
	end))
	c:add(WorldBinder.registerStand(KIOSK_TAG, function()
		UIController.open(SCREEN)
	end))
	for _, field in { "owned", "equipped", "dataStatus" } do
		c:add(StateController.changed(field):connect(function()
			if field == "equipped" then
				confirmedEquip = nil
			end
			refresh()
		end))
	end
	c:add(StateController.Loaded:connect(refresh))
	c:add(StateController.NewOwnedChanged:connect(refresh))
	c:add(StateController.LobbyLockChanged:connect(refresh))
	-- Fix batch: the hanging Collected chip hides while another screen is over Squishies (after the stack changes).
	c:add(UIController.ScreenOpened:connect(function()
		task.defer(refreshCollected)
	end))
	c:add(UIController.ScreenClosed:connect(function()
		task.defer(refreshCollected)
	end))
	c:add(function()
		if openCleanup then
			openCleanup:clean()
			openCleanup = nil
		end
		if confirmTimer then
			task.cancel(confirmTimer)
			confirmTimer = nil
		end
		table.clear(cards)
		table.clear(chips)
		table.clear(chipActive)
		panel, collectedChip, showNotOwnedToggle, grid, gridLayout = nil, nil, nil, nil, nil
		emptyState, emptyLabel, goToBoxes, loadingLabel, body, detail = nil, nil, nil, nil, nil, nil
		frames, closeButton, panelLayout, lastDetail = nil, nil, nil, nil
		pendingEquip, confirmedEquip = nil, nil
	end)
	log:debug("ready")
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function InventoryController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return InventoryController
