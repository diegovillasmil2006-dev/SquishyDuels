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
-- UI FINAL R3 (the window frame, plan work/ui/PLAN.md R3; `H:n` = "Squishy Duels HUD.dc.html" line n): the panel is
-- the design's Squishies window (Theme.window "squishies", H:180-182: 1060 x 650, shrunk to fit with its sticker and X,
-- InventoryFormat.panelLayout / Layout.windowFit, the face's top 310 above the middle) with its band (Theme.headerTab:
-- "SQUISHIES", the Collected chip at its right end as the design's header pill, H:185; the sticker, H:251) and the 76
-- px close X in the band (Theme.attachClose, H:252); Theme.fitWindow lays the chrome out at the window's chrome scale.
-- The texts on the pink body (the empty state, the loading line) take the window's text colour (H:196).
-- UI FINAL R5 (Diego's Squishies window, plan work/ui/PLAN.md R5 with its Decided list; numbers in
-- Config.UI.Inventory, layout maths in UI/InventoryFormat): the window's inside is the design's (H:185-248):
-- * The header pill at the band's right end (H:185-188): "Collected", the yellow 110 px bar (600 ms, the bars curve)
--   and "{n} / {total}" in the coin yellow, on the ink at .55.
-- * The body (H:191): the 600 px left column (the tab row, then the grid) and the detail column; padding 18 22 22.
-- * The rarity tabs (H:193-194, H:927-929): title case "All", "Common", ... with each rarity's catalogue count (no
--   brackets); on: the All pink or the rarity's light -> base, off: the purple; hover "tab" (y -2, 1.05), the tab click
--   (ui.click at the tab pitch). Five tabs and "Show locked" need more than the 600 px at 16 px text (PR2): the tabs
--   scroll sideways (InventoryFormat.tabRowFits, G5.3). "Show locked" (H:195-197): the two-line label left of the small
--   switch, no On / Off, hover "tab", the switch's rising / falling click.
-- * The cards (H:203-212; UI/CardFace): one purple face for every rarity, the plate (the rarity's radial, H:204) with
--   the squishy (UI/Components/SquishyImage: the silhouette and the 40 px lock when not owned), the name, the footer
--   (the rarity pill, RarityTag "card", and its dots when they fit, [PR25]), the hanging "Equipped" ribbon and NEW
--   (only when new and not equipped); selected: the white border, the ring and the glow in the rarity's colour.
--   Hover "card" (y -5, 1.035, the brightness filter) and the press squash on an inner holder (Button.decorate), the
--   card click (ui.click at the card pitch). They rise in (sdRise .42 s, i x 28 ms, no cap: Config.UI.motion.cardIn)
--   on open; after a filter change only the newly shown slots rise (G5.10). NEW and the HUD badge clear when the
--   window closes (StateController.markAllOwnedSeen, G5.9), not on a pick.
-- * The detail (H:217-248): the stage (UI/StageLook: the radial, rays, floor, stars; the squishy 190 floating, its pick
--   pop on every pick, H:937; tap it = Inspect, focusable, G5.15), the name row (the name, RarityTag "detail", the mint
--   EQUIPPED pill), the chips (power "x{n} power" [FD4], the throw style, "Ultimate: {name}"), the stats well (blue /
--   purple bars, Config.Combat bands) and ONE button: EQUIP (green), EQUIPPED (the disabled lilac with the check) or
--   FIND IN BOXES (cyan, the boxes picture; "View in Shop" with the shop picture for a restricted account, [PR22]).
--   The stage shrinks so the rest fits above the button (InventoryFormat.detailLayout); on phones the list scrolls.
-- * Equip: the design's burst (Config.UI.Fx.events.equip) and the 1.2 squash at the stage's squishy (G5.16), and the
--   toast "Equipped {name}!" (inventory.equippedToast, G5.17).
-- * States ([PR23], UI/Components/StatePill): loading = the pill with the spinner, filter-empty = the pill with its
--   text over the grid; the data error stays the line at the top of the detail.
-- * Kill banners (Diego, 2026-10-16): the squishy's kill set line is kept but hidden (the design has no place for it;
--   NOTES question).
-- Stable names: Squishies_CloseButton, Squishies_Filter<Name>Button, Squishies_ShowNotOwnedToggle,
-- Squishies_Card_<id>, Squishies_EquipButton, Squishies_EquippedButton, Squishies_InspectButton (the stage),
-- Squishies_GoToBoxesButton (FIND IN BOXES; View in Shop when restricted).

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local RarityStyle = require(Shared.Art.RarityStyle)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local BoxFormat = require(Client.UI.BoxFormat)
local Button = require(Client.UI.Components.Button)
local CardFace = require(Client.UI.CardFace)
local Chip = require(Client.UI.Components.Chip)
local CoinIcon = require(Client.UI.Components.CoinIcon)
local Create = require(Client.UI.Create)
local Focus = require(Client.UI.Focus)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local InventoryFormat = require(Client.UI.InventoryFormat)
local KeyText = require(Client.UI.KeyText)
local Layout = require(Client.UI.Layout)
local ProgressBar = require(Client.UI.Components.ProgressBar)
local RarityTag = require(Client.UI.Components.RarityTag)
local Scheduler = require(Client.Anim.Scheduler)
local ScrollHint = require(Client.UI.Components.ScrollHint)
local SquishyImage = require(Client.UI.Components.SquishyImage)
local StageLook = require(Client.UI.StageLook)
local StatePill = require(Client.UI.Components.StatePill)
local Theme = require(Client.UI.Theme)
local Toggle = require(Client.UI.Components.Toggle)
local Tweens = require(Client.Anim.Tweens)
local UiFx = require(Client.UI.UiFx)
local UiIdle = require(Client.Anim.UiIdle)
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
local EQUIPPED_TOAST = "inventory.equippedToast" -- UI FINAL R5: "Equipped {name}!" (H:846)
local TOUCH = Config.UI.Touch
local ABILITIES = Config.Abilities
local STICKER = Config.UI.Sticker
local UI_PITCH = Config.Audio.uiPitch
local INVENTORY = Config.UI.Inventory
local BODY = INVENTORY.body
local GRID = INVENTORY.grid
local CARD = INVENTORY.card
local PLATE = INVENTORY.plate
local TAB = INVENTORY.tab
local PILL = INVENTORY.pill
local STAGE = INVENTORY.stage
local STATS = INVENTORY.stats
local DETAIL = INVENTORY.detail
local CARD_IN = Config.UI.motion.cardIn -- H:31, H:203: sdRise
local PRESS = Config.UI.motion.buttonPress
local EQUIP_FX = Config.UI.Fx.events.equip -- H:845
local EQUIP_SQUASH = 1.2 -- H:845: FX.squash(.., 1.2)
local WINDOW_KIND = "squishies" -- UI FINAL R3: its Config.UI.Sticker.window kind (H:180-254)
local WINDOW_BORDER = STICKER.border.heavy
local BUTTON_HEIGHT = INVENTORY.button.face + STICKER.lip.button -- H:245: the 60 px face and its 5 px lip
local CONFIRM_SECONDS = 5 -- reading: how long "Equipped" shows before the StateDelta must have arrived
local GENERIC = "error.generic"
local STAT_TIME: { [string]: boolean } = { reload = true, windup = true } -- the purple bars (lib:39)
local TEXT_KIND: Theme.TextKind = "Small" -- PR2: the design's 11-15 px texts are 16
local NAME_LINE_HEIGHT = 1.1 -- H:208
local MEASURE_MARGIN_PX = 2
local TAB_ROW_OUTSET = 4 -- the tab scroller reaches this far past the row, so a lifted tab is never cut
local WHITE = Color3.new(1, 1, 1)

-- Module table

local InventoryController = {}

-- Private

type Card = {
	id: string,
	rarity: string,
	root: TextButton,
	rise: Frame, -- the inner holder the rise plays on (in SD_Visual, which the hover poses)
	face: CardFace.CardFace,
	image: SquishyImage.SquishyImage,
	lock: Frame,
	lockReady: boolean, -- the lock picture has an id
	tag: RarityTag.RarityTag,
	ribbon: Frame,
	newTag: Frame,
}

type Tab = {
	root: TextButton,
	foam: Theme.Foam,
	label: TextLabel,
	count: TextLabel,
	on: boolean?, -- as painted last
}

type Detail = {
	error: TextLabel,
	list: ScrollingFrame,
	listLayout: UIListLayout,
	rail: Frame,
	stage: TextButton,
	look: StageLook.StageLook,
	pick: Frame, -- the pick pop's holder
	fit: UIScale, -- the squishy's size for the stage's face
	image: SquishyImage.SquishyImage,
	name: TextLabel,
	rarity: RarityTag.RarityTag,
	equippedPill: Frame,
	power: Chip.Chip,
	throw: Chip.Chip,
	ultimate: Chip.Chip,
	stats: { [string]: { value: TextLabel, bar: ProgressBar.ProgressBar } },
	elimination: TextLabel,
	buttons: Frame,
	equip: Button.Button,
	equipped: Button.Button,
	find: Button.Button,
}

type Frames = {
	left: Frame,
	tabRow: Frame,
	tabs: ScrollingFrame,
	toggle: Toggle.Toggle,
	detailColumn: Frame,
	padding: UIPadding,
}

-- A running track (playTrack): its effect, its poser and its fade group.
type Track = { handle: Scheduler.Handle, poser: Tweens.Poser, fade: Tweens.FadeGroup }

local log = Log.new("Inventory")
local cleanup: Cleanup.Cleanup? = nil
local openCleanup: Cleanup.Cleanup? = nil
local panel: Frame? = nil
local frames: Frames? = nil
local closeButton: Button.Button? = nil
local collectedPill: Frame? = nil
local collectedBar: ProgressBar.ProgressBar? = nil
local collectedCount: TextLabel? = nil
local tabs: { [string]: Tab } = {}
local grid: ScrollingFrame? = nil
local gridLayout: UIGridLayout? = nil
local emptyPill: StatePill.StatePill? = nil
local loadingPill: StatePill.StatePill? = nil
local body: Frame? = nil
local cards: { [string]: Card } = {}
local detail: Detail? = nil
local panelLayout: InventoryFormat.PanelLayout? = nil
local lastDetail: InventoryFormat.DetailLayout? = nil -- the detail column as laid out last (debugState)
local cardFrame: InventoryFormat.CardFrame = { face = CARD.face, nameLines = 1, inner = 0 }
local tracks: { [GuiObject]: Track } = {}
local filter: InventoryFormat.Filter = "All"
local showNotOwned = true
local selected: string? = nil
local shownCount = 0 -- the grid's slots shown last (InventoryFormat.riseSlots)
local riseFrom: number? = nil -- set: the next refresh rises the slots past this many
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

local function nameOf(id: string): string
	local def = Catalog.get(id)
	return if def then Strings.resolve(def.nameKey) or id else id
end

-- Motion (UI FINAL R5) ---------------------------------------------------------------------------------------------

-- Stops `holder`'s track and puts it at rest (its pose and every transparency it faded).
local function stopTrack(holder: GuiObject)
	local track = tracks[holder]
	if track then
		tracks[holder] = nil
		track.handle:disconnect()
		track.poser:rest()
		track.fade:restore()
	end
end

-- Plays a design @keyframes track on `holder` (its poses through Tweens.poser, its alpha over the whole holder and what
-- is in it through Tweens.fadeGroup), after `delayMs`, each segment eased `curve` or the whole run `wholeRun`; nothing
-- under ReducedMotion. A new track on the holder first puts the last one at rest.
local function playTrack(
	holder: GuiObject,
	frames: { any }, -- Config's MotionPose tracks (Anim/Tweens.Pose)
	ms: number,
	delayMs: number,
	curve: string?,
	wholeRun: string?
)
	stopTrack(holder)
	if Tweens.reducedMotion() or ms <= 0 then
		return
	end
	local poser = Tweens.poser(holder)
	local fade = Tweens.fadeGroup(holder)
	local function apply(u: number)
		local pose = Tweens.poseAt(frames :: { Tweens.Pose }, u, curve, wholeRun)
		fade:setAlpha(pose.alpha or 1)
		pose.alpha = nil
		poser:set(pose)
	end
	apply(0)
	local elapsed = 0
	local handle = Scheduler.add(function(dt: number): boolean
		elapsed += dt
		local u = (elapsed * 1000 - delayMs) / ms
		if u < 0 then
			return true -- the first frame holds through the delay (CSS fill: both)
		end
		if u >= 1 then
			stopTrack(holder)
			return false
		end
		apply(u)
		return true
	end, "render")
	tracks[holder] = { handle = handle, poser = poser, fade = fade }
end

-- The press squash of `amount` (PR4: Config.UI.motion.buttonPress's frames) on the stage's squishy (G5.16).
local function squashImage(image: SquishyImage.SquishyImage, amount: number, c: Cleanup.Cleanup)
	if Tweens.reducedMotion() then
		return
	end
	local elapsed = 0
	local duration = PRESS.ms / 1000
	c:add(Scheduler.add(function(dt: number): boolean
		elapsed += dt
		local u = math.min(elapsed / duration, 1)
		local sx, sy = Button.squashAt(u, amount)
		image:squash(if u >= 1 then 1 else sx, if u >= 1 then 1 else sy)
		return u < 1
	end, "render"))
end

-- Layout ---------------------------------------------------------------------------------------------------------------

-- The detail column (InventoryFormat.detailLayout): the stage shrinks so the rest of the list (measured from the
-- list's content less the stage) fits above the pinned button; the list scrolls when even the smallest stage does not
-- leave room (phones).
local function layoutDetail()
	local d, l, f = detail, panelLayout, frames
	if d == nil or l == nil or f == nil then
		return
	end
	local current = (lastDetail and lastDetail.stageFace or STAGE.face) + STAGE.lip
	local listBase = if lastDetail then lastDetail.listHeight else 0
	local drawn = d.list.AbsoluteSize.Y
	local k = if listBase > 0 and drawn > 0 then drawn / listBase else 0
	local rest = if k > 0 then math.max(0, d.listLayout.AbsoluteContentSize.Y / k - current) else 0
	local placed = InventoryFormat.detailLayout(l.detailHeight, BUTTON_HEIGHT, rest)
	local before = lastDetail
	lastDetail = placed
	d.list.Size = UDim2.new(1, 0, 0, placed.listHeight)
	d.rail.Size = UDim2.fromOffset(Theme.SCROLLBAR_PX, placed.listHeight)
	d.buttons.Position = UDim2.fromOffset(0, placed.buttonsTop)
	for _, button in { d.equip, d.equipped, d.find } do
		button:setWidth(l.detailWidth)
		button.root.Size = UDim2.fromOffset(l.detailWidth, BUTTON_HEIGHT)
	end
	if before == nil or before.stageFace ~= placed.stageFace then
		d.stage.Size = UDim2.new(1, 0, 0, placed.stageFace + STAGE.lip)
		d.look:setFace(placed.stageFace)
		d.fit.Scale = InventoryFormat.stageSquishyPx(placed.stageFace) / STAGE.squishyPx
	end
end

-- The cards for the card width panelLayout gave (InventoryFormat.cardFrame): the face's height (a 2-line name grows
-- every card alike), the grid's cells, and each card's pips beside its pill when they fit ([PR25]).
local function applyCardSize()
	local l = panelLayout
	if l == nil then
		return
	end
	local nameWidth, footer = 0, 0
	for _, def in Catalog.list() do
		nameWidth = math.max(nameWidth, Theme.textWidth(nameOf(def.id), TEXT_KIND) + MEASURE_MARGIN_PX)
		footer = math.max(footer, RarityTag.measurePill(def.rarity, "card").pillHeight)
	end
	local lineHeight = math.ceil(Theme.lineHeight(TEXT_KIND) * NAME_LINE_HEIGHT)
	cardFrame = InventoryFormat.cardFrame(l.cardWidth, nameWidth, lineHeight, footer)
	local layout = gridLayout
	if layout then
		layout.CellSize = UDim2.fromOffset(l.cardWidth, cardFrame.face + CARD.lip)
		layout.CellPadding = UDim2.fromOffset(GRID.gap, Layout.lipGap(GRID.gap, CARD.lip))
		layout.FillDirectionMaxCells = math.max(1, l.columns)
	end
	for _, card in cards do
		card.tag:setRarity(card.rarity) -- the pill's height at the player's text size
		local m = RarityTag.measurePill(card.rarity, "card")
		card.tag:setPipsShown(InventoryFormat.footerFits(cardFrame.inner, m.pipsWidth, m.pillWidth + MEASURE_MARGIN_PX))
	end
end

-- A tab's width at the player's text size: its border and padding, the name, the gap and the count.
local function tabWidth(name: string, count: string): number
	local label = Theme.textWidth(InventoryFormat.filterName(name), TEXT_KIND)
	local number = Theme.textWidth(count, TEXT_KIND)
	return math.ceil(label + number) + TAB.gap + 2 * (TAB.border + TAB.padX) + MEASURE_MARGIN_PX
end

-- The tab row: each tab as wide as it needs; the row scrolls sideways only when the tabs do not fit beside "Show
-- locked" (G5.3).
local function layoutTabs()
	local l, f = panelLayout, frames
	if l == nil or f == nil then
		return
	end
	local widths: { number } = {}
	for _, name in InventoryFormat.FILTERS do
		local tab = tabs[name]
		if tab then
			local width = tabWidth(name, tab.count.Text)
			tab.root.Size = UDim2.fromOffset(width, l.rowHeight)
			table.insert(widths, width)
		end
	end
	local toggleWidth = Toggle.widthFor(Strings.inventory.showLockedLines, "small", true)
	f.toggle.root.Size = UDim2.fromOffset(toggleWidth, l.rowHeight)
	local room = l.gridWidth - toggleWidth - TAB.rowGap
	f.tabs.Size = UDim2.new(0, room + 2 * TAB_ROW_OUTSET, 1, 2 * TAB_ROW_OUTSET)
	f.tabs.ScrollingEnabled = not InventoryFormat.tabRowFits(widths, TAB.rowGap, room)
end

-- UI FINAL R3: the window's band, sticker and X at the window's chrome scale (Theme.fitWindow; Layout.windowFit), and
-- the face's top 310 px above the middle (H:181, kept on the screen with what hangs off it). Returns the top padding.
local function fitChrome(root: Frame, fit: Layout.WindowFit): number
	local chrome = Theme.fitWindow(root, fit.k)
	root.Position = UDim2.new(0.5, 0, 0.5, fit.shift)
	return chrome.top
end

-- Every size of the window from the ScreenGui's size (InventoryFormat.panelLayout), then the tabs, cards and detail.
local function applyLayout()
	local root, f = panel, frames
	if root == nil or f == nil then
		return
	end
	local screen = UIController.screenGui(MODAL_GUI).AbsoluteSize
	local top = fitChrome(root, Layout.windowFit(screen, WINDOW_KIND))
	local l = InventoryFormat.panelLayout(screen, top)
	panelLayout = l
	root.Size = UDim2.fromOffset(l.panelWidth, l.panelHeight + STICKER.lip.window) -- the face and its lip
	f.left.Size = UDim2.fromOffset(l.gridWidth, l.contentHeight)
	f.tabRow.Size = UDim2.new(1, 0, 0, l.rowHeight)
	f.detailColumn.Position = UDim2.fromOffset(l.gridWidth + BODY.gap, 0)
	f.detailColumn.Size = UDim2.fromOffset(l.detailWidth, l.contentHeight)
	local g = grid
	if g then
		-- H:200: the scroller's padding and the matching negative margin, so the hanging tags are not cut.
		g.Position = UDim2.fromOffset(-GRID.padLeft, l.bodyTop - GRID.padTop)
		g.Size = UDim2.fromOffset(l.gridWidth + GRID.padLeft + GRID.padRight, l.bodyHeight + GRID.padTop)
	end
	local empty = emptyPill
	if empty then
		empty.root.Position = UDim2.fromOffset(l.gridWidth / 2, l.bodyTop + l.bodyHeight / 2)
	end
	layoutTabs()
	applyCardSize()
	layoutDetail()
end

-- Detail panel ------------------------------------------------------------------------------------------------------

-- FIND IN BOXES, or (PR22) View in Shop for an account that may not buy random items (BoxFormat.standScreen).
local function findScreen(): string
	return BoxFormat.standScreen(StateController.get("policy"))
end

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
	d.image:setCatalogId(entry.id)
	d.image:setOwned(entry.owned)
	d.look:setRarity(entry.rarity)
	d.name.Text = entry.name
	d.rarity:setRarity(entry.rarity)
	d.equippedPill.Visible = entry.equipped
	-- Phase 5 (progression spec 2026-10-12 §6): what the squishy multiplies in the pen ("x16 power").
	d.power:setText(Strings.format(Strings.squishy.power, { n = Catalog.getPower(entry.id) }))
	local throw = InventoryFormat.throwText(entry.id)
	d.throw.root.Visible = throw ~= ""
	d.throw:setText(throw)
	for _, bar in InventoryFormat.statBars(def) do
		local view = d.stats[bar.stat]
		if view then
			view.value.Text =
				Strings.format(Strings.inspect.statValue, { value = bar.value, unit = KeyText.get(bar.unitKey) })
			view.bar:set(bar.fraction, true) -- H:240: 600 ms on the bars curve
		end
	end
	local ability = if def.ultimateId then ABILITIES[def.ultimateId] else nil
	d.ultimate.root.Visible = ability ~= nil
	if ability then
		d.ultimate:setText(Strings.format(Strings.inventory.ultimateChip, { name = KeyText.get(ability.nameKey) }))
	end
	-- Kill banners (2026-10-16): the squishy's own kill set name (Strings elimination.<id>), Standard otherwise.
	local eliminationName = Strings.resolve("elimination." .. def.eliminationEffectId) or Strings.elimination.standard
	d.elimination.Text = Strings.format(Strings.inspect.elimination, { name = eliminationName })
	-- G5.15: the stage is the Inspect button once that screen exists.
	local canInspect = UIController.isRegistered(INSPECT_SCREEN)
	d.stage.Active = canInspect
	d.stage.Selectable = canInspect

	local state = InventoryFormat.equipState(entry, {
		locked = StateController.isLobbyLocked(),
		pending = pendingEquip,
		confirmed = confirmedEquip,
	})
	d.find.root.Visible = state == "notOwned"
	d.equipped.root.Visible = state == "equipped"
	d.equip.root.Visible = state ~= "notOwned" and state ~= "equipped"
	if state == "notOwned" then
		local shop = findScreen() == SHOP_SCREEN
		d.find:setText(if shop then Strings.inspect.viewInShop else Strings.inventory.goToBoxes)
		d.find:setIcon(if shop then "shop" else "boxes")
	elseif state == "equip" then
		d.equip:setState("normal")
	elseif state == "locked" then
		d.equip:setState("disabled", Strings.common.lockedInDuel)
	elseif state == "loading" then
		d.equip:setState("loading") -- keeps its text and its place
	end
end

-- Grid ----------------------------------------------------------------------------------------------------------------

-- Fix batch: the Collected pill shows only while Squishies is the top screen and once the profile is loaded.
local function refreshCollected()
	local collected = collectedPill
	if collected then
		local top = UIController.topModal()
		collected.Visible = StateController.isLoaded() and (top == nil or top == SCREEN)
	end
end

local function paintCard(card: Card, entry: InventoryFormat.Entry, isSelected: boolean)
	card.face:paint({ owned = entry.owned, selected = isSelected })
	card.image:setOwned(entry.owned)
	card.lock.Visible = card.lockReady and not entry.owned
	card.ribbon.Visible = entry.equipped
	card.newTag.Visible = InventoryFormat.showNewTag(entry.isNew, entry.equipped)
end

-- A tab's look: on (the All pink, or the rarity's light -> base, the 3 px highlight at .5, white text) or off (the
-- purple, 2 px at .12, the soft lilac text) (H:928-929).
local function paintTab(name: string, tab: Tab, on: boolean)
	if tab.on == on then
		return -- repainted only when it changes
	end
	tab.on = on
	local top, bottom = Palette.StickerCardTop, Palette.StickerCardBottom
	if on then
		local style = RarityStyle.get(name)
		top = if name == "All" then Palette.StickerTabAllTop elseif style then style.ui.light or style.color else top
		bottom = if name == "All"
			then Palette.StickerHeaderPinkEnd
			elseif style then style.ui.base or style.color
			else bottom
	end
	local highlightPx = if on then TAB.onHighlightPx else TAB.offHighlightPx
	local alpha = if on then TAB.onHighlightAlpha else TAB.offHighlightAlpha
	local bands = Layout.stickerBands(TAB.border, highlightPx, 0, TAB.lip)
	tab.foam:setBands(bands.top, bands.bevel, bands.drop)
	tab.foam:paint({ face = top, faceEnd = bottom, top = top:Lerp(WHITE, alpha), drop = Theme.Colors.inkUI })
	local color = if on then Palette.White else Palette.StickerTabOff
	tab.label.TextColor3 = color
	tab.count.TextColor3 = color
end

local function refreshGrid(list: { InventoryFormat.Entry })
	local shownList = InventoryFormat.visible(list, filter, showNotOwned)
	selected = InventoryFormat.keepSelection(selected, shownList)
	local visibleIds: { [string]: number } = {}
	for index, entry in shownList do
		visibleIds[entry.id] = index
	end
	local bySlot: { [number]: Card } = {}
	for _, entry in list do
		local card = cards[entry.id]
		if card then
			local index = visibleIds[entry.id]
			card.root.Visible = index ~= nil
			card.root.LayoutOrder = index or 0
			if index then
				bySlot[index] = card
			end
			paintCard(card, entry, entry.id == selected)
		end
	end
	-- G5.10: on open every slot rises; after a filter change only the slots past the ones shown before.
	local from = riseFrom
	riseFrom = nil
	if from then
		for _, slot in InventoryFormat.riseSlots(from, #shownList) do
			local card = bySlot[slot]
			if card then
				playTrack(card.rise, CARD_IN.frames, CARD_IN.ms, (slot - 1) * CARD_IN.staggerMs, CARD_IN.curve)
			end
		end
	end
	shownCount = #shownList
	local counts = InventoryFormat.tabCounts(list)
	for name, tab in tabs do
		tab.count.Text = tostring(counts[name] or 0)
		paintTab(name, tab, name == filter)
	end
	local owned, total = InventoryFormat.collected(list)
	local count = collectedCount
	if count then
		count.Text = Strings.format(Strings.inventory.collectedCount, { n = owned, total = total })
	end
	local bar = collectedBar
	if bar then
		bar:set(if total > 0 then owned / total else 0, true) -- H:187: 600 ms on the bars curve
	end
	refreshCollected()
	local empty = emptyPill
	if empty then
		empty.root.Visible = #shownList == 0
		if #shownList == 0 then
			empty:setText(InventoryFormat.emptyText(filter))
		end
	end
end

local function refresh()
	if panel == nil then
		return
	end
	local loaded = StateController.isLoaded()
	if loadingPill then
		loadingPill.root.Visible = not loaded
	end
	if body then
		body.Visible = loaded
	end
	if not loaded then
		return
	end
	local f = frames
	if f then
		f.toggle:setValue(showNotOwned)
	end
	local list = currentEntries()
	refreshGrid(list)
	refreshDetail(list)
	layoutTabs() -- the counts may have changed a tab's width
end

local function selectCard(id: string)
	local changed = selected ~= id
	selected = id
	SoundController.play("ui.click", { pitch = UI_PITCH.card }) -- the design's card sound (H:318)
	refresh()
	local d = detail
	if d and changed then
		-- H:937: the stage's squishy pops in on every pick.
		playTrack(d.pick, STAGE.pickFrames, STAGE.pickMs, 0, nil, STAGE.pickCurve)
	end
end

local function setFilter(newFilter: InventoryFormat.Filter)
	if newFilter ~= filter then
		SoundController.play("ui.click", { pitch = UI_PITCH.tab }) -- the design's tab sound (H:929)
	end
	filter = newFilter
	riseFrom = shownCount -- G5.10: only the newly shown slots rise
	refresh()
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
		-- UI FINAL R9 (H:846): the mint toast with the squishy's picture.
		NotifyController.show(EQUIPPED_TOAST, { name = nameOf(id) }, "success", { squishy = id })
		-- G5.16 (H:845): the design's burst and the 1.2 squash at the stage's squishy, once the server said yes.
		local d, c = detail, openCleanup
		if d and c then
			UiFx.sparks(d.image.root, EQUIP_FX.sparks :: any)
			squashImage(d.image, PRESS.amount * EQUIP_SQUASH, c)
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

-- FIND IN BOXES: the Boxes window replaces this one (H:1016); a restricted account goes to the squishy in the Shop.
local function findSelected()
	local id = selected
	if id == nil then
		return
	end
	if findScreen() == SHOP_SCREEN then
		UIController.close(SCREEN, "viewInShop")
		UIController.open(SHOP_SCREEN, { squishyId = id })
	else
		UIController.close(SCREEN, "goToBoxes")
		UIController.open(BOXES_SCREEN)
	end
end

-- Builders -----------------------------------------------------------------------------------------------------------

-- A hanging card tag (H:210-211): a pill of `spec`'s height (grown by the measured extra of its 16 px text), its 3 px
-- border inside and its ink lip, in `colors`, with its text in `role`.
local function hangingTag(
	parent: Instance,
	name: string,
	text: string,
	spec: { [string]: number },
	colors: Theme.FoamColors,
	role: string
): Frame
	local height = math.max(spec.height, math.ceil(Theme.lineHeight(TEXT_KIND)) + (spec.padTop or 0) + 2 * spec.border)
	local tag: Frame = Create("Frame", {
		Name = name,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height + spec.lip),
		Visible = false,
		Active = false,
		ZIndex = 3,
		Parent = parent,
	})
	local bands = Layout.stickerBands(spec.border, 0, 0, spec.lip)
	Theme.foam(tag, {
		radius = Theme.Radius.pill,
		stroke = spec.border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
		colors = colors,
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, spec.padX + spec.border),
		PaddingRight = UDim.new(0, spec.padX + spec.border),
		PaddingTop = UDim.new(0, (spec.padTop or 0) + spec.border),
		PaddingBottom = UDim.new(0, spec.border + spec.lip),
		Parent = tag,
	})
	local label = Theme.label({
		Name = "Text",
		Text = text,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Parent = tag,
	}, TEXT_KIND)
	Theme.stickerText(label, role)
	return tag
end

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
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	c:add(root)
	Focus.decorate(root, CARD.radius)
	local function holder(name: string, parentFrame: Instance): Frame
		return Create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Active = false,
			Parent = parentFrame,
		})
	end
	-- SD_Visual takes the hover and press (Button.decorate), SD_Rise the entrance; the hit box never moves.
	local visual = holder("SD_Visual", root)
	local rise = holder("SD_Rise", visual)
	local face = CardFace.new(rise, def.rarity)
	c:add(face)
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -CARD.lip),
		Active = false,
		ZIndex = 1,
		Parent = rise,
	})
	Create("UIPadding", {
		PaddingTop = UDim.new(0, CARD.border + CARD.padTop),
		PaddingBottom = UDim.new(0, CARD.border + CARD.padBottom),
		PaddingLeft = UDim.new(0, CARD.border + CARD.padSide),
		PaddingRight = UDim.new(0, CARD.border + CARD.padSide),
		Parent = content,
	})
	local column: Frame = Create("Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = content,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		CARD.gap,
		column,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Top
	)
	-- The plate (H:204, H:936): the rarity's radial, its insets, the squishy over it (H:205) and the lock (H:206).
	local plate: Frame = Create("Frame", {
		Name = "Plate",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(PLATE.px, PLATE.px),
		LayoutOrder = 1,
		Parent = column,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = plate })
	local ui = if style then style.ui else nil
	Theme.radial(plate, "img.fx.radial.plate" .. def.rarity, {
		inner = if ui then ui.light or ui.faceTop else Theme.Colors.panelAlt,
		outer = if ui then ui.base or ui.faceBottom else Theme.Colors.panel,
		centre = Vector2.new(0.5, PLATE.centreY),
	})
	StageLook.shade(
		plate,
		UDim.new(0.5, 0),
		PLATE.border,
		PLATE.px,
		PLATE.topPx,
		PLATE.topAlpha,
		PLATE.bottomPx,
		PLATE.bottomAlpha
	)
	local rim = Theme.stroke(Theme.Colors.inkUI, PLATE.border, plate)
	pcall(function()
		(rim :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	local imageOptions: SquishyImage.Options = {
		name = "Preview",
		size = PLATE.thumbPx,
		shadow = { px = PLATE.shadowPx, alpha = PLATE.shadowAlpha },
		parent = plate,
	}
	local image = SquishyImage.new(id, imageOptions)
	image.root.AnchorPoint = Vector2.new(0.5, 0.5)
	image.root.Position = UDim2.fromScale(0.5, 0.5)
	image.root.ZIndex = 2
	c:add(image)
	local lock = IconGlyph.image("img.icon.lock", { name = "Lock", sizePx = PLATE.lockPx, parent = plate })
	local lockReady = lock.Visible
	lock.AnchorPoint = Vector2.new(0.5, 0.5)
	lock.Position = UDim2.fromScale(0.5, 0.5)
	lock.ZIndex = 3
	for _, child in lock:GetChildren() do
		if child:IsA("GuiObject") then
			child.ZIndex = 3
		end
	end
	local name = Theme.label({
		Name = "Name",
		Text = nameOf(id),
		LayoutOrder = 2,
		LineHeight = NAME_LINE_HEIGHT,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = column,
	}, TEXT_KIND)
	Theme.stickerText(name, "cardName")
	-- The footer (H:209: margin-top auto): the rarity pill and its dots at the content's bottom.
	local tag = RarityTag.new({ name = "Rarity", rarity = def.rarity, variant = "card", parent = content })
	tag.root.AnchorPoint = Vector2.new(0.5, 1)
	tag.root.Position = UDim2.fromScale(0.5, 1)
	c:add(tag)
	local ribbon = hangingTag(
		rise,
		"Equipped",
		Strings.common.equipped,
		INVENTORY.ribbon,
		Theme.accentColors("mint"),
		"cardRibbon"
	)
	ribbon.Position = UDim2.fromOffset(INVENTORY.ribbon.x, INVENTORY.ribbon.y)
	ribbon.Rotation = INVENTORY.ribbon.rot
	local newTag = hangingTag(rise, "New", Strings.inventory.new, INVENTORY.newTag, {
		face = Palette.StickerRedTop,
		faceEnd = Palette.StickerRedEnd,
		drop = Theme.Colors.inkUI,
	}, "cardNew")
	newTag.AnchorPoint = Vector2.new(1, 0)
	newTag.Position = UDim2.new(1, -INVENTORY.newTag.x, 0, INVENTORY.newTag.y)
	UiIdle.add(newTag, "badge", { periodS = INVENTORY.newTag.badgeS }) -- H:211: sdBadge 2 s
	-- G5.5 (H:634-644): the card hover and press on SD_Visual, the brightness on the face; the click is the card's.
	local feel: Button.DecorateOptions = {
		fx = "card",
		visual = visual,
		clickSound = false,
		pivotPx = CARD.lip / 2,
		onFilter = function(mix: number)
			face:setHover(mix)
		end,
	}
	c:add(Button.decorate(root, feel))
	c:add(root.Activated:Connect(function()
		selectCard(id)
	end))
	root.Parent = parent
	cards[id] = {
		id = id,
		rarity = def.rarity,
		root = root,
		rise = rise,
		face = face,
		image = image,
		lock = lock,
		lockReady = lockReady,
		tag = tag,
		ribbon = ribbon,
		newTag = newTag,
	}
end

-- The rarity tabs in a sideways-scrolling row (H:193-194; sized by layoutTabs); returns that row.
local function buildTabs(c: Cleanup.Cleanup, parent: Instance, rowHeight: number): ScrollingFrame
	local row: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-TAB_ROW_OUTSET, -TAB_ROW_OUTSET),
		Size = UDim2.new(1, 0, 1, 2 * TAB_ROW_OUTSET),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		Parent = parent,
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, TAB_ROW_OUTSET),
		PaddingRight = UDim.new(0, TAB_ROW_OUTSET),
		Parent = row,
	})
	Theme.list(Enum.FillDirection.Horizontal, TAB.rowGap, row, Enum.HorizontalAlignment.Left)
	for index, name in InventoryFormat.FILTERS do
		local root: TextButton = Create("TextButton", {
			Name = "Squishies_Filter" .. name .. "Button",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, rowHeight),
			LayoutOrder = index,
			Parent = row,
		})
		Focus.decorate(root, TAB.radius)
		-- The face + lip, centred in the touch-sized hit box (PR1).
		local visual: Frame = Create("Frame", {
			Name = "SD_Visual",
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, TAB.face + TAB.lip),
			Active = false,
			Parent = root,
		})
		local bands = Layout.stickerBands(TAB.border, TAB.offHighlightPx, 0, TAB.lip)
		local foam = Theme.foam(visual, {
			radius = TAB.radius,
			stroke = TAB.border,
			inner = true,
			top = bands.top,
			drop = bands.drop,
			colors = { face = Palette.StickerCardTop, faceEnd = Palette.StickerCardBottom },
		})
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, TAB.border + TAB.padX),
			PaddingRight = UDim.new(0, TAB.border + TAB.padX),
			PaddingBottom = UDim.new(0, TAB.lip),
			Parent = visual,
		})
		Theme.list(Enum.FillDirection.Horizontal, TAB.gap, visual)
		local function text(textName: string, order: number): TextLabel
			local label = Theme.label({
				Name = textName,
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				TextWrapped = false,
				LayoutOrder = order,
				Parent = visual,
			}, TEXT_KIND)
			Theme.stickerText(label, "tabLabel")
			return label
		end
		local label = text("Label", 1)
		label.Text = InventoryFormat.filterName(name)
		local count = text("Count", 2)
		count.TextTransparency = 1 - TAB.countAlpha -- H:194: opacity .85
		local feel: Button.DecorateOptions = { fx = "tab", visual = visual, clickSound = false, pivotPx = TAB.lip / 2 }
		c:add(Button.decorate(root, feel))
		c:add(root.Activated:Connect(function()
			setFilter(name)
		end))
		tabs[name] = { root = root, foam = foam, label = label, count = count, on = nil }
	end
	return row
end

-- A detail chip (H:232-234; UI/Components/Chip: 30 high, border 3, radius 10, padding 12) with an optional 20 px
-- picture before its text.
local function detailChip(c: Cleanup.Cleanup, parent: Instance, name: string, order: number): Chip.Chip
	local chip = Chip.new({ name = name, text = "", layoutOrder = order, parent = parent })
	c:add(chip)
	return chip
end

local function buildDetail(c: Cleanup.Cleanup, parent: Instance)
	-- The list above the one pinned button (its height from layoutDetail).
	local list: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Detail",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		Selectable = false,
		Parent = parent,
	})
	Theme.scrollbar(list) -- G5.18 (H:22)
	local scrollHint = ScrollHint.new({ scroll = list, parent = parent })
	scrollHint.root.AnchorPoint = Vector2.new(1, 0)
	scrollHint.root.Position = UDim2.fromScale(1, 0)
	c:add(scrollHint)
	local listLayout = Theme.list(
		Enum.FillDirection.Vertical,
		DETAIL.gap,
		list,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local errorLabel = Theme.label({
		Name = "Error",
		Text = Strings.data.loadFailed,
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = list,
	}, "Small")
	Theme.textOnWindow(errorLabel) -- UI FINAL R3: on the pink body (H:196; Danger is 1.8:1 on it)

	-- The stage (H:218-224): tap it = Inspect (G5.15; no look of its own beyond the focus ring).
	local stage: TextButton = Create("TextButton", {
		Name = "Squishies_InspectButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, STAGE.face + STAGE.lip),
		LayoutOrder = 2,
		Parent = list,
	})
	Focus.decorate(stage, STAGE.radius)
	local look = StageLook.new(stage, { floor = true })
	c:add(look)
	local px = STAGE.squishyPx
	local pick: Frame = Create("Frame", {
		Name = "Pick",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(px, px),
		Active = false,
		Parent = look.slot,
	})
	local float: Frame = Create("Frame", {
		Name = "Float",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = pick,
	})
	UiIdle.add(float, "float", { periodS = STAGE.floatS }) -- H:223: sdFloat 3.2 s
	-- The squishy at the stage's size (a UIScale: the 3D fallback's ViewportFrame keeps its px size).
	local fit: Frame = Create("Frame", {
		Name = "Fit",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = float,
	})
	local fitScale: UIScale = Create("UIScale", { Name = "SD_Fit", Parent = fit })
	local imageOptions: SquishyImage.Options = {
		name = "Preview",
		size = px,
		shadow = { px = STAGE.shadowPx, alpha = STAGE.shadowAlpha },
		parent = fit,
	}
	local image = SquishyImage.new(Catalog.starterId(), imageOptions)
	image.root.AnchorPoint = Vector2.new(0.5, 0.5)
	image.root.Position = UDim2.fromScale(0.5, 0.5)
	c:add(image)
	c:add(stage.Activated:Connect(function()
		local id = selected
		if id and UIController.isRegistered(INSPECT_SCREEN) then
			UIController.open(INSPECT_SCREEN, { squishyId = id, owned = StateController.owns(id), source = SCREEN })
		end
	end))

	-- The name row (H:226-230): the name, the rarity pill and EQUIPPED (wrapping).
	local nameRow: Frame = Create("Frame", {
		Name = "NameRow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = list,
	})
	local nameList = Theme.list(Enum.FillDirection.Horizontal, DETAIL.nameGap, nameRow, Enum.HorizontalAlignment.Left)
	nameList.Wraps = true
	local name = Theme.label({
		Name = "Name",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = nameRow,
	}, "Name")
	Theme.stickerText(name, "detailName")
	local rarity = RarityTag.new({
		name = "Rarity",
		rarity = "Common",
		variant = "detail",
		layoutOrder = 2,
		parent = nameRow,
	})
	c:add(rarity)
	local pillSpec = STICKER.pills.detail
	local pillHeight =
		math.max(pillSpec.height, math.ceil(Theme.lineHeight(TEXT_KIND)) + pillSpec.padTop + 2 * pillSpec.border)
	local equippedPill = hangingTag(nameRow, "EquippedPill", string.upper(Strings.common.equipped), {
		height = pillHeight,
		padTop = pillSpec.padTop,
		padX = pillSpec.padX,
		border = pillSpec.border,
		lip = 0,
	}, Theme.accentColors("mint"), "rarityPill")
	equippedPill.LayoutOrder = 3
	equippedPill.ZIndex = 1

	-- The chips (H:231-234): power, the throw style, the Ultimate.
	local chipRow: Frame = Create("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Parent = list,
	})
	local chipList = Theme.list(Enum.FillDirection.Horizontal, DETAIL.chipGap, chipRow, Enum.HorizontalAlignment.Left)
	chipList.Wraps = true
	local power = detailChip(c, chipRow, "Power", 1)
	c:add(CoinIcon.new({ name = "Coin", sizePx = DETAIL.iconPx, layoutOrder = 1, parent = power.root }))
	local throw = detailChip(c, chipRow, "Throw", 2)
	throw:setColor(Palette.StickerThrowChip, Palette.StickerTextChip) -- H:233
	local ultimate = detailChip(c, chipRow, "Ultimate", 3)
	ultimate:setAccent("ult")
	Theme.textOnLight(ultimate.label, Palette.StickerUltText) -- H:234
	IconGlyph.image("img.icon.bolt", { name = "Bolt", sizePx = DETAIL.iconPx, layoutOrder = 1, parent = ultimate.root })

	-- The stats well (H:236-243): rows 72 | 1fr | 92, the blue and purple bars (lib:37-41).
	local well = Theme.inset({
		Name = "Stats",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 5,
		Parent = list,
	}, STATS.radius, STATS.border + STATS.padY)
	local wellPad = well:FindFirstChildOfClass("UIPadding")
	if wellPad then
		wellPad.PaddingLeft = UDim.new(0, STATS.border + STATS.padX)
		wellPad.PaddingRight = UDim.new(0, STATS.border + STATS.padX)
	end
	Theme.list(
		Enum.FillDirection.Vertical,
		STATS.rowGap,
		well,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local rowHeight = math.max(STICKER.bars.stat.height, math.ceil(Theme.lineHeight(TEXT_KIND)))
	local stats: { [string]: { value: TextLabel, bar: ProgressBar.ProgressBar } } = {}
	for index, bar in InventoryFormat.statBars(Catalog.list()[1]) do
		local row: Frame = Create("Frame", {
			Name = "Stat_" .. bar.stat,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, rowHeight),
			LayoutOrder = index,
			Parent = well,
		})
		Theme.label({
			Name = "Label",
			Text = KeyText.get(bar.labelKey),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(STATS.label, 0),
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		}, TEXT_KIND, nil, Theme.Colors.textFaint) -- H:239: #F3EDFF
		local value = Theme.label({
			Name = "Value",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(STATS.value, 0),
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		}, TEXT_KIND)
		local statBar = ProgressBar.new({
			name = "Bar",
			variant = "stat",
			accent = if STAT_TIME[bar.stat] then "lilac" else "blueBar",
			parent = row,
		})
		statBar.root.AnchorPoint = Vector2.new(0, 0.5)
		statBar.root.Position = UDim2.new(0, STATS.label + STATS.gap, 0.5, 0)
		statBar.root.Size = UDim2.new(1, -(STATS.label + STATS.value + 2 * STATS.gap), 0, STICKER.bars.stat.height)
		c:add(statBar)
		stats[bar.stat] = { value = value, bar = statBar }
	end
	-- Kept for Diego's kill-set line (refreshDetail); the design's detail has no line for it (NOTES question).
	local elimination = Theme.label({
		Name = "Elimination",
		LayoutOrder = 6,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = list,
	}, "Small")
	Theme.textOnWindow(elimination)

	-- The one button (H:245-247), pinned under the list (layoutDetail places it).
	local buttons: Frame = Create("Frame", {
		Name = "DetailButtons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
		Parent = parent,
	})
	local equip = Button.new({
		name = "Squishies_EquipButton",
		text = Strings.common.equip,
		kind = "primary",
		height = INVENTORY.button.face,
		textKind = "Large", -- H:245: 28 px, stroke 6
		parent = buttons,
		onActivated = equipSelected,
	})
	c:add(equip)
	local equipped = Button.new({
		name = "Squishies_EquippedButton",
		text = Strings.common.equipped,
		kind = "primary",
		height = INVENTORY.button.face,
		textKind = "HudNumber", -- H:246: 26 px, stroke 6
		icon = "check",
		iconSize = INVENTORY.button.checkPx,
		parent = buttons,
		onActivated = function() end,
	})
	equipped:setState("disabled") -- H:246: the lilac EQUIPPED, a press says no
	equipped.root.Visible = false
	c:add(equipped)
	local find = Button.new({
		name = "Squishies_GoToBoxesButton",
		text = Strings.inventory.goToBoxes,
		kind = "secondary",
		height = INVENTORY.button.face,
		textKind = "HudNumber", -- H:247: 26 px, stroke 6
		icon = "boxes",
		iconSize = INVENTORY.button.iconPx,
		parent = buttons,
		sound = false, -- opens a screen: ui.open plays instead
		onActivated = findSelected,
	})
	find.root.Visible = false
	c:add(find)
	c:add(listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(layoutDetail))
	c:add(list:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutDetail))

	detail = {
		error = errorLabel,
		list = list,
		listLayout = listLayout,
		rail = scrollHint.root,
		stage = stage,
		look = look,
		pick = pick,
		fit = fitScale,
		image = image,
		name = name,
		rarity = rarity,
		equippedPill = equippedPill,
		power = power,
		throw = throw,
		ultimate = ultimate,
		stats = stats,
		elimination = elimination,
		buttons = buttons,
		equip = equip,
		equipped = equipped,
		find = find,
	}
end

-- The header pill (H:185-188): "Collected", the bar and the count, the band's extra.
local function buildCollected(c: Cleanup.Cleanup, parent: Instance): Frame
	local pill: Frame = Create("Frame", {
		Name = "Collected",
		BackgroundColor3 = Theme.Colors.inkUI,
		BackgroundTransparency = 1 - PILL.alpha,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, PILL.height),
		Visible = false, -- shown with its count once the profile is loaded (refreshCollected)
		Parent = parent,
	})
	Theme.corner(PILL.height, pill)
	local stroke = Theme.stroke(Theme.Colors.inkUI, PILL.border, pill)
	pcall(function()
		(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, PILL.border + PILL.padX),
		PaddingRight = UDim.new(0, PILL.border + PILL.padX),
		Parent = pill,
	})
	Theme.list(Enum.FillDirection.Horizontal, PILL.gap, pill)
	Theme.label({
		Name = "Label",
		Text = Strings.inventory.collectedLabel,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = pill,
	}, TEXT_KIND, nil, Palette.StickerCollected) -- H:186: #FFE3EF
	local bar = ProgressBar.new({
		name = "Bar",
		variant = "collected",
		widthPx = PILL.barWidth,
		layoutOrder = 2,
		parent = pill,
	})
	c:add(bar)
	local count = Theme.label({
		Name = "Count",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 3,
		Parent = pill,
	}, "Button")
	Theme.stickerText(count, "collectedCount") -- H:188
	collectedBar, collectedCount = bar, count
	return pill
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local root = Theme.window({
		Name = "Squishies",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(STICKER.window.kinds.squishies.width, STICKER.window.kinds.squishies.height),
		Parent = parent,
	}, WINDOW_KIND, BODY.padTop)
	c:add(root)
	-- H:191: the body's padding inside the window's border (fitWindow sets the top: the band, then padTop).
	local padding = root:FindFirstChildOfClass("UIPadding") :: UIPadding
	padding.PaddingLeft = UDim.new(0, WINDOW_BORDER + BODY.padSide)
	padding.PaddingRight = UDim.new(0, WINDOW_BORDER + BODY.padSide)
	padding.PaddingBottom = UDim.new(0, WINDOW_BORDER + BODY.padBottom + STICKER.lip.window)
	local rowHeight = Layout.touchBase(TOUCH.minTarget, UIController.scale())

	-- UI FINAL R3: the band (H:183-189): the title, and the header pill at its right end (H:185).
	local collected = buildCollected(c, root)
	collectedPill = collected
	Theme.headerTab(root, Strings.inventory.title, { extra = collected :: GuiObject })
	-- The 76 px X in the band at the window's top-right corner (H:252).
	local close = Button.new({
		name = "Squishies_CloseButton",
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

	local content: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	body = content
	-- The left column (H:192): the tab row, then the grid.
	local left: Frame = Create("Frame", {
		Name = "Left",
		BackgroundTransparency = 1,
		Parent = content,
	})
	local tabRow: Frame = Create("Frame", {
		Name = "TabRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, rowHeight),
		Parent = left,
	})
	local tabScroller = buildTabs(c, tabRow, rowHeight)
	local lockedText = Strings.inventory.showLockedLines
	local toggle = Toggle.new({
		name = "Squishies_ShowNotOwnedToggle",
		text = lockedText,
		value = showNotOwned,
		stateText = false,
		labelBeside = "left",
		gapPx = TAB.toggleGap,
		widthPx = Toggle.widthFor(lockedText, "small", true),
		parent = tabRow,
		onChanged = function(on: boolean)
			-- H:1011: the switch's rising / falling click.
			SoundController.play("ui.click", { pitch = if on then UI_PITCH.toggleOn else UI_PITCH.toggleOff })
			showNotOwned = on
			riseFrom = shownCount -- a re-filter: only the newly shown slots rise
			refresh()
		end,
	})
	toggle.root.AnchorPoint = Vector2.new(1, 0)
	toggle.root.Position = UDim2.fromScale(1, 0)
	local toggleFeel: Button.DecorateOptions = { fx = "tab", visual = toggle.visual, clickSound = false }
	c:add(Button.decorate(toggle.root, toggleFeel))
	c:add(toggle)

	local gridFrame: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.Always, -- the cards keep one width (InventoryFormat.panelLayout)
		Selectable = false,
		Parent = left,
	})
	Theme.scrollbar(gridFrame) -- G5.18 (H:22)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, GRID.padTop),
		PaddingRight = UDim.new(0, GRID.padRight),
		PaddingBottom = UDim.new(0, GRID.padBottom),
		PaddingLeft = UDim.new(0, GRID.padLeft),
		Parent = gridFrame,
	})
	gridLayout = Create("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD.face, CARD.face + CARD.lip),
		CellPadding = UDim2.fromOffset(GRID.gap, Layout.lipGap(GRID.gap, CARD.lip)),
		SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = GRID.columns,
		Parent = gridFrame,
	})
	grid = gridFrame
	for _, def in Catalog.list() do
		buildCard(c, gridFrame, def.id)
	end
	local empty = StatePill.new({ name = "Empty", text = "", parent = left })
	empty.root.AnchorPoint = Vector2.new(0.5, 0.5)
	empty.root.Visible = false
	c:add(empty)
	emptyPill = empty

	local detailColumn: Frame = Create("Frame", {
		Name = "DetailColumn",
		BackgroundTransparency = 1,
		Parent = content,
	})
	buildDetail(c, detailColumn)
	frames = {
		left = left,
		tabRow = tabRow,
		tabs = tabScroller,
		toggle = toggle,
		detailColumn = detailColumn,
		padding = padding,
	}

	local loading = StatePill.new({ name = "Loading", text = Strings.common.loading, spinner = true, parent = root })
	loading.root.AnchorPoint = Vector2.new(0.5, 0.5)
	loading.root.Position = UDim2.fromScale(0.5, 0.5)
	loading.root.Visible = false
	c:add(loading)
	loadingPill = loading

	panel = root
	-- Part 8: every size follows the ScreenGui, the layout class and the player's text size.
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout))
	c:add(UIController.LayoutChanged:connect(applyLayout))
	local okSignal, textSizeChanged = pcall(function(): RBXScriptSignal
		return GuiService:GetPropertyChangedSignal("PreferredTextSize")
	end)
	if okSignal then
		c:add(textSizeChanged:Connect(function()
			applyLayout()
			refresh()
		end))
	end
	applyLayout()
	refresh()
	return root
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

-- Every card's rise at rest (the window closed mid-entrance).
local function stopRises()
	for holder in tracks do
		stopTrack(holder)
	end
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
	local l, placed = panelLayout, lastDetail
	return {
		built = panel ~= nil,
		filter = filter,
		showNotOwned = showNotOwned,
		selected = selected,
		visible = visible,
		pending = pendingEquip,
		-- UI FINAL R5: the card frame, the fitted grid and the detail column (base px)
		card = { width = if l then l.cardWidth else 0, face = cardFrame.face, nameLines = cardFrame.nameLines },
		grid = if l then { columns = l.columns, width = l.gridWidth, detailWidth = l.detailWidth } else nil,
		detail = if placed
			then { listHeight = placed.listHeight, stageFace = placed.stageFace, scrolls = placed.scrolls }
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
			followSelection(oc)
			riseFrom = 0 -- UI FINAL R5: every card rises in (sdRise, i x 28 ms, H:934)
			refresh()
		end,
		onClose = function()
			if openCleanup then
				openCleanup:clean()
				openCleanup = nil
			end
			stopRises()
			StateController.markAllOwnedSeen() -- G5.9 (H:681, H:689): NEW and the HUD badge clear on close
		end,
		primary = function(): GuiObject?
			-- The selected card; else the active tab (an empty filter); else Close (Part 8: never nothing).
			local card = if selected then cards[selected] else nil
			if card and card.root.Visible then
				return card.root
			end
			local tab = tabs[filter]
			if tab then
				return tab.root
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
	for _, field in { "owned", "equipped", "dataStatus", "policy" } do
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
	-- Fix batch: the Collected pill hides while another screen is over Squishies (after the stack changes).
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
		stopRises()
		table.clear(cards)
		table.clear(tabs)
		panel, collectedPill, collectedBar, collectedCount, grid, gridLayout = nil, nil, nil, nil, nil, nil
		emptyPill, loadingPill, body, detail = nil, nil, nil, nil
		frames, closeButton, panelLayout, lastDetail = nil, nil, nil, nil
		pendingEquip, confirmedEquip, riseFrom = nil, nil, nil
		shownCount = 0
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
