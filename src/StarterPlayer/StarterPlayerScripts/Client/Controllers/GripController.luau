--!strict
-- GripController (client only). DESIGN §17.7 (UI), §17.2 rule 1 (no Grip in duels), §17.3.4 (Double Grip),
-- §17.5 (next-goal rule), §11.4, §11.6. Build plan Phase 6: slow training is gone (no
-- popup, help line or bank line), and so are the trainers (no trainer card, Upgrade tab or badge, trainer goal or
-- TrainerUpgrade call) and the giant pads and Jelly gates (no pad cards, Show me or unlock waypoint, pad goal, or
-- level source for WorldBinder's gates and pod signs).
-- Grip is a lobby-only stat: nothing here sends anything to the server (there is no Grip remote, §17.2 rule 5).
--
-- * State: StateController's `grip` field {total, rested {value, at}} (§17.10). Level, rank, the bar and the
--   Double Grip minutes come from the same pure GripMath and
--   SqueezeLimit the server uses; timers are read against Workspace:GetServerTimeNow() (unix seconds, the scale of the
--   server's os.time(): reading). The first grip state of the session is a silent baseline (§17.7 "Load-time level
--   jumps"): no toast. So is every later full state, e.g. a profile recovered
--   after an OFFLINE start replacing the defaults (§3.13; StateController.isApplyingFull, gripChange).
-- * HUD Grip card (SD_Hud, top-left under the coin capsule): one tap target `Hud_GripButton` that opens the Grip
--   panel; a foam card (foam UI restyle, spec 2026-10-09 "Grip card", redesign-check.jpg).
--   regular: a Mint level tile (grip.levelTag "GRIP" over the level) beside the rank (grip.rank.*), the ProgressBar,
--   grip.hudBar ({have}/{need} from GripMath.progress, Format.coins; grip.hudMax at the top), the Double Grip line with a
--   clock (grip.restedChip, only while it has minutes) and the next-goal line (GripMath.nextGoal). Its lines are
--   left-aligned like the design (foam fix; Theme.label's default is centred). The card's height follows its lines.
--   The bar (foam fix, user decision 2026-10-09) fills with the same numbers its words show: have / need, the total
--   over the next level's total (42,000 / 66,000 is about two thirds full); every Grip bar with have / need (the card,
--   the compact row, the panel) uses it. Before, it was the share of the current level (DESIGN §17.7).
--   compact (phones): one row of at most Config.UI.Grip.compactRowMaxHeight base px, grip.hudLevelCompact plus a
--   compactBarHeight bar, as wide as its line needs (HudFormat.gripCompactWidth: on phones it sits beside the coin
--   capsule); the chip and the goal live in the panel, and a new goal is shown once as a toast.
--   The card sits in HudController's top-left column (HudController.leftColumn(), a UIListLayout) at
--   HudController.LEFT_ORDER.grip, centred in a fixed-size slot (Hud_GripSlot, foam fix: its press feel's scale never
--   moves the tiles under it): under the coin capsule, or beside it on phones (the column plan's `left`); the tiles
--   follow under the column. HudController
--   .setFocusEntry(card) makes it the first DPadUp target, whose Down walks the tiles (§17.7 "Gamepad"). Reading:
--   HudController is the HUD's slot provider (a lower layer than this module, which boots after it); without its column
--   the card makes its own at the same spot.
-- * Grip panel (modal "grip", one scrolling column, §11.4 focus; foam restyle: a foam panel with the grip.panelTitle
--   header tab and Close straddling its top edge at the right, like Quests, Daily and Settings; foam fix: no header row
--   that held only Close, so the column starts at the top): the level and the bar (have / need, like the card), the
--   chip and the goal in a
--   Biscuit inset, the help lines
--   (grip.restedHelp, grip.limitNote: where squeezing pays now that the hourly limit is off)
--   in a second inset and the footer grip.duelNote.
--   No Coin Store link and no Robux upsell anywhere (§17.2 rule 4).
-- * Toasts: the server's `grip.*` Notify codes (levelUp, rankUp, intro, welcome, welcomeBack, headStart;
--   GripService decides them; reading: §17.10's code list has no grip.intro, but GripService sends it on the first Grip
--   ever, so the client shows no intro of its own) are shown by NotifyController, which also holds them back
--   from Matched through Returning (at most 3, merged into one, §17.7). This module's only own toast, the compact
--   layout's new goal, goes through NotifyController.show, so it gets the same hold-back.
-- * Idle card (modal "gripIdle"): Players.LocalPlayer.Idled with t >= Config.Grip.idleReminderSeconds (900) opens
--   grip.idleTitle / grip.idleBody / [grip.idleButton] in the lobby. It is a modal, so ControlsController.block stops
--   any hold-to-squeeze; [Keep going] only closes it (it never restarts a hold, and nothing simulates input).
-- * No Grip UI in duels: the card hides and both modals close while the lobby is locked
--   (StateController.isLobbyLocked) or SD_DuelPhase / SD_MatchId is set.
-- * Feel pass (DESIGN §18.5.1 A9, lobby only): a level change after the silent baseline (shouldPopLevel) pops the
--   card's level label (both layouts) LEVEL_POP.from -> 1, Back Out over LEVEL_POP.ms, through a UIScale (Tweens.scale:
--   no scale under ReducedMotion). Its sound, ui.gripUnlock, plays with the server's grip.levelUp toast
--   (NotifyController through Config.Audio.toastSounds), not here.
-- * Part 8 (§17.7 compact layout, §17.12 Part 8 L5, §11.2, §11.4):
--   - The card tells HudController whether it wants to show (setColumnItem "grip": a grip state, not held back by a
--     duel) and takes its layout from HudController.columnPlan().grip (HudFormat.leftColumnPlan): "regular" or
--     "compact" (phones; also a regular screen at a large text size when the column would not end above 55%). It never
--     hides for the tutorial card (§17.7: the card is the way into the Grip panel and DPadUp's target); "hidden" only
--     means the card is not in the column (no Grip state, or a duel holds it back).
--   - Compact (Reading, §17.7 vs §11.2): the visible row ("Lv 12 · Firm Grip" + the 4 px bar) stays <=
--     Config.UI.Grip.compactRowMaxHeight base px; the whole card, still the ONE tap target Hud_GripButton, is
--     HudFormat.gripCardHeight("compact") tall: at least Layout.touchBase(Config.UI.Touch.minTarget, scale) (>= 44 px
--     at scale 0.85). The goal toast follows the card: any card but the regular one toasts a new goal.
--   - Gamepad (§11.4, §17.7): the panel opens with its primary (Close) selected; the idle card's primary is its Keep
--     going button.
--   - The title sits in the header tab and Close straddles the panel's top edge (the panel's top padding holds their
--     lower halves), so the column starts at the panel's padding and the two never meet.
-- * Batch 1 #7a: the next goal also reads the capsules, Coins and owned squishies (StateController "capsules" /
--   coins() / owned(), refreshed on their changes), so it names the capsule buy first ("Upgrade Capsule 1 · READY!",
--   "Capsule 1: 120/1,000 Coins" on the regular card; an unlock only with a spare squishy); a capsule goal's toast id
--   is its key and capsule, never its Coins.
-- * Foam fix 2 (2026-10-09; look only): the panel and what hangs above it (half the taller of Close and the tab) take
--   PANEL_HEIGHT_SHARE together and are centred together (panelLayout, pure; as Quests and Settings), so Close stays on
--   a phone's screen. The Level block's list is centred. The regular card's goal line reads the short form of the
--   goal (cardModel's cardGoal, grip.hudGoal*: "Next: Firm Grip at Lv 10"), so a new player's card keeps it to one
--   line; the panel and the compact layout's toast keep the full text.
-- * Foam fix 3 (2026-10-10; look only): fix 2 took Close's hang out of the panel's height, so on a phone the column
--   ended at "Squeeze pads" with no pad card under it. The panel keeps the whole PANEL_HEIGHT_SHARE again, centred with
--   Close, and is shorter only to keep Close's top PANEL_EDGE inside the screen (panelLayout); on the compact layout
--   the intro line hides (introShown; see there); on touch the column has the scroll rail
--   (UI/Components/ScrollHint, "ScrollRail" on the panel), like Settings.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local GripMath = require(Shared.GripMath)
local Log = require(Shared.Util.Log)
local SqueezeLimit = require(Shared.SqueezeLimit)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Tweens = require(Client.Anim.Tweens)
local Button = require(Client.UI.Components.Button)
local Create = require(Client.UI.Create)
local Focus = require(Client.UI.Focus)
local HudFormat = require(Client.UI.HudFormat)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local Layout = require(Client.UI.Layout)
local ProgressBar = require(Client.UI.Components.ProgressBar)
local ScrollHint = require(Client.UI.Components.ScrollHint)
local Theme = require(Client.UI.Theme)
local UiFx = require(Client.UI.UiFx)
local HudController = require(script.Parent.HudController)
local NotifyController = require(script.Parent.NotifyController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

export type Timer = { value: number, at: number }
-- The client's view of the `grip` state field (§17.10), normalized.
export type GripView = { total: number, rested: Timer? }

-- What one new grip state does (gripChange): a silent baseline and whether the level moved (fireLevel; the level pop
-- reads it).
export type GripChange = { baseline: boolean, fireLevel: boolean }

-- Texts and numbers of the HUD card for one state.
export type CardModel = {
	level: number,
	levelText: string, -- grip.hudLevel
	levelCompact: string, -- grip.hudLevelCompact
	rankText: string, -- grip.rank.* (the regular card's title; the level shows on its level tile)
	barText: string, -- grip.hudBar or grip.hudMax
	fraction: number, -- 0..1: have / need, the numbers barText shows (1 at the top)
	chip: string?, -- grip.restedChip, nil while Double Grip is empty or off
	goal: string?, -- the next-goal line (the panel; the compact layout's toast)
	cardGoal: string?, -- the regular card's goal line (foam fix 2: the short grip.hudGoal* form of the same goal)
	goalKey: string?, -- its Strings key (GripMath.Goal.textKey)
	goalArgs: { [string]: any }?, -- its format arguments
}

-- The Grip panel's base size and how far below the screen's centre it sits (panelLayout, foam fix 2).
export type PanelLayout = { width: number, height: number, shift: number }

type Card = {
	slot: Frame, -- the fixed-size holder in HudController's column (the press scale never moves the list)
	root: TextButton,
	body: Frame, -- holds the one visible layout (the root has no padding)
	regular: Frame,
	compact: Frame,
	levelLabel: TextLabel, -- the level number on the level tile
	rankLabel: TextLabel,
	bar: ProgressBar.ProgressBar,
	barLabel: TextLabel,
	chipRow: Frame,
	chipLabel: TextLabel,
	goalLabel: TextLabel,
	compactLabel: TextLabel,
	compactBar: ProgressBar.ProgressBar,
	levelScales: { UIScale }, -- the level pop (§18.5.1 A9): on the level tile's number and the compact level label
	levelTweens: { Tween },
	barSet: boolean, -- the bars got their first value (later values ease)
}

type PanelRefs = {
	root: Frame,
	tab: Frame, -- the header tab (its height counts in what hangs above the panel, placePanel)
	title: TextLabel,
	scroll: ScrollingFrame,
	intro: TextLabel, -- foam fix 3: hidden on the compact layout (introShown)
	levelLabel: TextLabel,
	bar: ProgressBar.ProgressBar,
	barLabel: TextLabel,
	chipLabel: TextLabel,
	goalLabel: TextLabel,
	close: Button.Button,
}

-- Constants

local GRIP = Config.Grip
local UI_GRIP = Config.UI.Grip
local RESTED = GRIP.Rested
local SCREEN_PANEL = "grip"
local SCREEN_IDLE = "gripIdle"
local IDLE_BUTTON = "GripIdle_KeepGoingButton"
local HUD_GUI = "SD_Hud"
local MODAL_GUI = "SD_Modal"
local FALLBACK_COLUMN = "Hud_Left" -- HudController's column name, used only when HudController has none
local ATTR_DUEL_PHASE = "SD_DuelPhase"
local ATTR_MATCH_ID = "SD_MatchId"
-- reading (DESIGN gives the content, not the sizes): the HUD column and card in base px under the SD_Hud UIScale
-- (shared with HudFormat's column plan, which sizes the left side from the same numbers).
local COLUMN = HudFormat.COLUMN
local COLUMN_INSET = COLUMN.edge
local CARD_WIDTH = COLUMN.cardWidth
local CARD_ORDER = HudController.LEFT_ORDER.grip
local COMPACT_ROW_GAP = 2 -- between the compact row's label and its bar (HudFormat.gripCompactRowHeight)
local CARD_BANDS = Theme.Foam.panel -- the card's foam: bevel 5 + drop 4 under its content
local LEVEL_TILE_RADIUS = 14
local BAR_EPSILON = 1e-4 -- the bar eases only when its share really changed (the card refreshes every few seconds)
-- Foam fix (like Quests, Daily and Settings): Close straddles the panel's top edge this far from its right edge.
local CLOSE_INSET = 16
local PANEL_BAR_HEIGHT = 14
local PANEL_MAX_WIDTH = 560
local PANEL_MARGIN = 24
-- The panel takes this share of the screen's height (as Quests); foam fix 3: what hangs above it (Close, the header
-- tab) is centred with it, and it gives up height only to keep Close's top PANEL_EDGE inside the screen.
local PANEL_HEIGHT_SHARE = 0.86
local PANEL_EDGE = Theme.Padding.small
local PANEL_FALLBACK_HEIGHT = 480 -- before SD_Modal has a size
local IDLE_CARD_WIDTH = 440
local TIMER_REFRESH_SECONDS = 5 -- the minute texts change slowly (Double Grip refills 4 points a minute)
-- §18.5.1 A9: the level label pops 1.25 -> 1 (Back Out, 300 ms). Reading: §18.8 gives no Config key for it.
local LEVEL_POP = {
	from = 1.25,
	ms = 300,
	style = Enum.EasingStyle.Back,
	direction = Enum.EasingDirection.Out,
}
-- Foam fix 2: the regular card's short form of a goal's text (its info column is 184 base wide: the old trainer goal,
-- "Next: {trainer} unlocks at Grip Lv {level}", left "Grip Lv 3" alone on a line). Other goals keep their text.
local CARD_GOAL_KEYS: { [string]: string } = {
	["grip.goalRank"] = "grip.hudGoalRank",
	-- Batch 1 #7a: a capsule buy's progress, short; the READY lines are short already.
	["grip.goalCapsule"] = "grip.hudGoalCapsule",
	["grip.goalUnlock"] = "grip.hudGoalCapsule",
}

-- Module table

local GripController = {}

-- Foam fix 2: the Grip panel's height share and widest width; fix 3: Close's least room under the screen's top (tests
-- read them).
GripController.PANEL = table.freeze({ heightShare = PANEL_HEIGHT_SHARE, maxWidth = PANEL_MAX_WIDTH, edge = PANEL_EDGE })

-- Private

local log = Log.new("Grip")
local cleanup: Cleanup.Cleanup? = nil
local warnedKeys: { [string]: boolean } = {}
local view: GripView? = nil
local level: number? = nil
local baselineTotal: number? = nil
local lastGoalKey: string? = nil
local goalBaselineSet = false -- the session's first goal was seen (it is never toasted)
local toastedGoals: { [string]: boolean } = {} -- goals already seen this session (each new goal is toasted once)
local card: Card? = nil
local panelRefs: PanelRefs? = nil
local focusEntrySet = false -- the card is HudController's DPadUp focus entry (only while it is shown)
local cardPresent = false -- the card wants to show (HudController.setColumnItem "grip")

local function text(key: string, args: { [string]: any }?): string
	local template = Strings.resolve(key)
	if template == nil then
		if not warnedKeys[key] then
			warnedKeys[key] = true
			log:warn(`no Strings text for {key}`)
		end
		return ""
	end
	return Strings.format(template, args)
end

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function inMatch(): boolean
	local player = Players.LocalPlayer
	if player == nil then
		return false
	end
	local phase = player:GetAttribute(ATTR_DUEL_PHASE)
	local matchId = player:GetAttribute(ATTR_MATCH_ID)
	return (type(phase) == "string" and phase ~= "") or (type(matchId) == "string" and matchId ~= "")
end

-- From Matched through Returning nothing about Grip is shown (§17.2 rule 1).
local function suppressed(): boolean
	return StateController.isLobbyLocked() or inMatch()
end

-- Card --------------------------------------------------------------------------------------------------------------

-- HudController's top-left column, else (no HudController column) one of our own at the same spot, owned by `c`.
local function leftColumn(c: Cleanup.Cleanup): Frame
	local shared = HudController.leftColumn()
	if shared then
		return shared
	end
	local hud = UIController.screenGui(HUD_GUI)
	local existing = hud:FindFirstChild(FALLBACK_COLUMN)
	if existing and existing:IsA("Frame") then
		return existing
	end
	local column: Frame = c:add(Create("Frame", {
		Name = FALLBACK_COLUMN,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(COLUMN_INSET, COLUMN_INSET),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = hud,
	}))
	Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.small,
		column,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	return column
end

-- Sizes the card from its layout (defined after buildCard, which connects it).
local applyCardLayout: () -> ()

-- The card's foam look on a TextButton (Candy UI: the dark window face, the PlumInk outline and the inner rim, bevel
-- and ink drop, panel radius).
local function cardFoam(object: GuiObject)
	object.BackgroundColor3 = Theme.Colors.panel
	Theme.foam(object, {
		radius = Theme.Radius.panel,
		mode = "tint",
		bevel = CARD_BANDS.bevel,
		drop = CARD_BANDS.drop,
		colors = Theme.panelColors(),
	})
	Theme.rim(object)
end

local function caption(props: { [string]: any }): TextLabel
	return Theme.label(props, "Small", nil, Theme.Colors.ink2)
end

-- The regular layout (spec "Grip card", redesign-check.jpg): a Mint level tile ("GRIP" over the level) beside the rank,
-- the bar, "{have} / {need} Grip", the Double Grip line with a clock and the next goal (§17.7).
local function buildRegular(c: Cleanup.Cleanup, body: Frame): (Frame, { [string]: any })
	local regular: Frame = Create("Frame", {
		Name = "Regular",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		COLUMN.cardGap,
		regular,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local bands = Theme.Foam.button
	local tile: Frame = Create("Frame", {
		Name = "LevelTile",
		LayoutOrder = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(COLUMN.levelTileWidth, COLUMN.levelTileHeight),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = regular,
	})
	Theme.foam(tile, {
		radius = LEVEL_TILE_RADIUS,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.accentColors("mint", true),
	})
	Create("UIPadding", {
		PaddingTop = UDim.new(0, bands.top + 2),
		PaddingBottom = UDim.new(0, bands.bevel + bands.drop),
		Parent = tile,
	})
	Theme.list(Enum.FillDirection.Vertical, 0, tile)
	local tag = Theme.label({
		Name = "Tag",
		Text = text("grip.levelTag"),
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = tile,
	}, "Chip")
	Theme.textOnColor(tag) -- InkUI (the Chip kind is under the 18 px outline size)
	local levelLabel = Theme.label({
		Name = "Level",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = tile,
	}, "H2")
	Theme.textOnColor(levelLabel) -- white with the InkUI outline

	local info: Frame = Create("Frame", {
		Name = "Info",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(HudFormat.gripInfoWidth(), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = regular,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		COLUMN.listGap,
		info,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	-- Foam fix: every line left-aligned like the design (Theme.label centres by default).
	local rankLabel = Theme.label({
		Name = "Rank",
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = info,
	}, "Button")
	local gripBar = ProgressBar.new({
		name = "Bar",
		accent = "mint",
		heightPx = COLUMN.barHeight,
		layoutOrder = 2,
		parent = info,
	})
	c:add(gripBar)
	local barLabel = caption({
		Name = "BarText",
		LayoutOrder = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = info,
	})
	local chipRow: Frame = Create("Frame", {
		Name = "Chip",
		LayoutOrder = 4,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = info,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		COLUMN.listGap,
		chipRow,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local clock = IconGlyph.new({
		name = "Icon",
		icon = "clock",
		sizePx = COLUMN.chipIconPx,
		tone = "light", -- Candy UI: on the dark card
		layoutOrder = 1,
		parent = chipRow,
	})
	c:add(clock)
	local chipLabel = caption({
		Name = "Text",
		LayoutOrder = 2,
		Size = UDim2.new(1, -(COLUMN.chipIconPx + COLUMN.listGap), 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = chipRow,
	})
	local goalLabel = caption({
		Name = "Goal",
		LayoutOrder = 5,
		Visible = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = info,
	})
	return regular,
		{
			levelLabel = levelLabel,
			rankLabel = rankLabel,
			bar = gripBar,
			barLabel = barLabel,
			chipRow = chipRow,
			chipLabel = chipLabel,
			goalLabel = goalLabel,
		}
end

local function buildCard(c: Cleanup.Cleanup)
	-- Foam fix: the card sits centred in a fixed-size slot in the column (applyCardLayout sizes both), so the list only
	-- sees the slot and the press feel's scale (hover 1.04) never moves the tiles under it.
	local slot: Frame = Create("Frame", {
		Name = "Hud_GripSlot",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CARD_WIDTH, COLUMN.levelTileHeight),
		LayoutOrder = CARD_ORDER,
		Visible = false,
	})
	local root: TextButton = Create("TextButton", {
		Name = "Hud_GripButton",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_WIDTH, COLUMN.levelTileHeight),
		Visible = false,
		Parent = slot,
	})
	cardFoam(root)
	Focus.decorate(root, Theme.Radius.panel)
	-- The Button press feel; silent: it opens the Grip panel (ui.open plays).
	c:add(Button.decorate(root, { sound = false }))
	-- Part 8: one layout at a time (the other is invisible, so the list skips it). The root's height follows the body
	-- (applyCardLayout): no AutomaticSize.
	local body: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(COLUMN.cardPadLeft, COLUMN.cardPadTop),
		Size = UDim2.new(1, -(COLUMN.cardPadLeft + COLUMN.cardPadRight), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Vertical, 0, body, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)
	local regular, parts = buildRegular(c, body)

	-- The compact row (§17.7): one line and a 4 px bar, at most compactRowMaxHeight base px (HudFormat
	-- .gripCompactRowHeight at every text size); the card around it is the touch-sized tap target (applyCardLayout).
	local compact: Frame = Create("Frame", {
		Name = "Compact",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = body,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		COMPACT_ROW_GAP,
		compact,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	local compactLabel = Theme.label({
		Name = "Level",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = compact,
	}, "Small", Enum.FontWeight.Bold)
	local compactBar = ProgressBar.new({
		name = "Bar",
		accent = "mint",
		heightPx = UI_GRIP.compactBarHeight,
		layoutOrder = 2,
		parent = compact,
	})
	c:add(compactBar)
	local levelScales: { UIScale } = {}
	for _, label in { parts.levelLabel :: TextLabel, compactLabel } do
		table.insert(levelScales, Create("UIScale", { Name = "LevelPop", Scale = 1, Parent = label }))
	end

	c:add(root.Activated:Connect(function()
		if not suppressed() then
			UIController.open(SCREEN_PANEL)
		end
	end))
	slot.Parent = leftColumn(c)
	c:add(slot)
	c:add(function()
		if focusEntrySet then
			focusEntrySet = false
			HudController.setFocusEntry(nil)
		end
	end)
	card = {
		slot = slot,
		root = root,
		body = body,
		regular = regular,
		compact = compact,
		levelLabel = parts.levelLabel,
		rankLabel = parts.rankLabel,
		bar = parts.bar,
		barLabel = parts.barLabel,
		chipRow = parts.chipRow,
		chipLabel = parts.chipLabel,
		goalLabel = parts.goalLabel,
		compactLabel = compactLabel,
		compactBar = compactBar,
		levelScales = levelScales,
		levelTweens = {},
		barSet = false,
	}
	-- The root follows the body's height (the layout changes it, and wrapping lines at a new text size).
	c:add(body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyCardLayout()
	end))
	c:add(function()
		local k = card
		card = nil
		if k then
			for _, tween in k.levelTweens do
				tween:Cancel()
			end
		end
	end)
end

-- §18.5.1 A9: the level label pops (a new pop restarts it; none under ReducedMotion, Tweens.scale). UI overhaul: a
-- level up is a stronger moment: a large Mint burst with its expanding rings on the level badge (UI/UiFx; above the HUD,
-- never over the play area's centre).
local function popLevel()
	local k = card
	if k == nil then
		return
	end
	local badge = k.levelScales[1]
	local target = if badge then badge.Parent else nil
	if target and target:IsA("GuiObject") and target.Visible then
		UiFx.burst(target, "large", Theme.Accents.mint.face)
	end
	for _, tween in k.levelTweens do
		tween:Cancel()
	end
	table.clear(k.levelTweens)
	for _, scale in k.levelScales do
		local tween = Tweens.scale(scale, LEVEL_POP.from, 1, LEVEL_POP)
		if tween then
			table.insert(k.levelTweens, tween)
		end
	end
end

local function setLabel(label: TextLabel, value: string?)
	local shown = value ~= nil and value ~= ""
	label.Visible = shown
	if shown and label.Text ~= value then
		label.Text = value :: string
	end
end

local function currentModel(): CardModel?
	local v = view
	if v == nil then
		return nil
	end
	local capsules = StateController.get("capsules")
	return GripController.cardModel(v, serverNow(), capsules, StateController.coins(), StateController.owned())
end

-- The card's own press-feel scale (Button.decorate's UIScale "Scale" on the root; 1 without it), so its measured sizes
-- are read unscaled (foam fix: a hovered card measured its body 4% taller and grew itself on top of the scale).
local function feelScale(root: GuiObject): number
	local scale = root:FindFirstChild("Scale")
	return if scale and scale:IsA("UIScale") and scale.Scale > 0 then scale.Scale else 1
end

-- Part 8: the card's layout from HudController's column plan (regular / compact / hidden), whether it is up, and its
-- size: compact = the touch-sized tap target (HudFormat.gripCardHeight) as wide as its line (gripCompactWidth);
-- regular = the body plus the paddings. Its slot in the column takes the same, unscaled size.
applyCardLayout = function()
	local k = card
	if k == nil then
		return
	end
	local plan = HudController.columnPlan()
	local mode = plan.grip
	local visible = cardPresent and mode ~= "hidden"
	k.root.Visible = visible
	k.slot.Visible = visible
	-- §17.7 "Gamepad": while shown, the card is DPadUp's target and the column's second item (HudController links it);
	-- while hidden, DPadUp goes to the first tile.
	if visible ~= focusEntrySet then
		focusEntrySet = visible
		HudController.setFocusEntry(if visible then k.root else nil)
	end
	local compactLayout = mode == "compact"
	k.regular.Visible = not compactLayout
	k.compact.Visible = compactLayout
	local scale = UIController.scale() * feelScale(k.root)
	local width, height = CARD_WIDTH, 0
	if compactLayout then
		height = HudFormat.gripCardHeight("compact", HudController.textScale(), plan.scale)
		width = HudFormat.gripCompactWidth(k.compactLabel.Text, HudController.textScale())
		local body = (height - CARD_BANDS.bevel - CARD_BANDS.drop) / 2
		k.body.AnchorPoint = Vector2.new(0, 0.5)
		k.body.Position = UDim2.fromOffset(COLUMN.cardPadding + 4, body)
		k.body.Size = UDim2.new(1, -2 * (COLUMN.cardPadding + 4), 0, 0)
	else
		k.body.AnchorPoint = Vector2.new(0, 0)
		k.body.Position = UDim2.fromOffset(COLUMN.cardPadLeft, COLUMN.cardPadTop)
		k.body.Size = UDim2.new(1, -(COLUMN.cardPadLeft + COLUMN.cardPadRight), 0, 0)
		local bodyHeight = if scale > 0 then k.body.AbsoluteSize.Y / scale else 0
		height =
			math.ceil(COLUMN.cardPadTop + math.max(bodyHeight, HudFormat.levelTileHeight(1)) + COLUMN.cardPadBottom)
	end
	local size = UDim2.fromOffset(width, height)
	if k.root.Size ~= size then
		k.root.Size = size
	end
	if k.slot.Size ~= size then
		k.slot.Size = size
	end
end

local function refreshCard()
	local k = card
	if k == nil then
		return
	end
	local model = currentModel()
	cardPresent = model ~= nil and not suppressed()
	HudController.setColumnItem("grip", cardPresent)
	if model == nil then
		applyCardLayout()
		return
	end
	local compactLayout = HudController.columnPlan().grip ~= "regular"
	setLabel(k.levelLabel, tostring(model.level))
	setLabel(k.rankLabel, model.rankText)
	setLabel(k.barLabel, model.barText)
	k.chipRow.Visible = model.chip ~= nil
	setLabel(k.chipLabel, model.chip)
	-- Foam fix 2: the goal line reads the short form (cardGoal), so it keeps to one line.
	setLabel(k.goalLabel, model.cardGoal)
	setLabel(k.compactLabel, model.levelCompact)
	-- The first value is set at once; later changes ease (the bar variant's fillMs, Config.UI.Sticker.bars; at once
	-- under ReducedMotion).
	if not k.barSet or math.abs(k.bar:get() - model.fraction) > BAR_EPSILON then
		k.bar:set(model.fraction, k.barSet)
		k.compactBar:set(model.fraction, k.barSet)
	end
	k.barSet = true
	applyCardLayout()

	-- compact: a new goal also appears once as a toast (§17.7). The first goal of the session is the baseline, and so is
	-- a goal that changed while a full state was applied (a replaced profile: loaded, not reached).
	local goalId = GripController.goalId(model)
	if not goalBaselineSet or goalId ~= lastGoalKey then
		local first = not goalBaselineSet or StateController.isApplyingFull()
		goalBaselineSet = true
		lastGoalKey = goalId
		local key = model.goalKey
		if GripController.shouldToastGoal(toastedGoals, goalId, compactLayout, first) and key ~= nil then
			NotifyController.show(key, model.goalArgs, "info")
		end
		if goalId ~= nil then
			toastedGoals[goalId] = true
		end
	end
end

-- Panel -------------------------------------------------------------------------------------------------------------

-- Foam fix 2: sizes and places the panel (panelLayout) with what hangs above its top edge: half the taller of Close and
-- the header tab (measured without the open pop's scale, SD_OpenScale; Close until the tab has a size).
local function placePanel(root: GuiObject, tab: GuiObject?)
	local scale = UIController.scale()
	local pop = root:FindFirstChild("SD_OpenScale")
	local s = scale * (if pop and pop:IsA("UIScale") and pop.Scale > 0 then pop.Scale else 1)
	local tabHeight = if tab and s > 0 then tab.AbsoluteSize.Y / s else 0
	local above = math.max(Config.UI.Touch.closeButton, tabHeight) / 2
	local layout = GripController.panelLayout(UIController.screenGui(MODAL_GUI).AbsoluteSize, scale, above)
	local size = UDim2.fromOffset(layout.width, layout.height)
	if root.Size ~= size then
		root.Size = size
	end
	local position = UDim2.new(0.5, 0, 0.5, layout.shift)
	if root.Position ~= position then
		root.Position = position
	end
end

-- The Grip panel (foam restyle): a foam panel with the "Grip Training" header tab, Close straddling its top edge at the
-- right and one scrolling column: the intro, the level in a Biscuit inset (the bar, the Double Grip line, the goal),
-- the help lines in a second inset, then the duel note.
local function buildPanel(parent: Instance): GuiObject
	local root = Theme.panel({
		Name = "GripPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = parent,
	}, Theme.Radius.panel, Theme.Padding.large)
	-- Foam fix (like Quests, Daily and Settings): room at the top for Close's lower half, then the header tab (it raises
	-- the padding for its own half). No header row: the column starts right under them (on a phone the old Close-only
	-- row took about a fifth of the panel).
	local panelPad = root:FindFirstChildOfClass("UIPadding") :: UIPadding
	panelPad.PaddingTop = UDim.new(0, math.ceil(Config.UI.Touch.closeButton / 2) + Theme.Padding.small)
	-- The header tab straddles the panel's top edge (the panel holds no list itself, Theme.headerTab).
	local tab, title = Theme.headerTab(root, text("grip.panelTitle"))
	placePanel(root, tab)
	local close = Button.new({
		name = "Grip_CloseButton",
		text = text("common.close"),
		kind = "close", -- UI overhaul: the chunky red X
		height = Config.UI.Touch.closeButton,
		parent = root,
		onActivated = function()
			UIController.close(SCREEN_PANEL, "close")
		end,
	})
	-- Straddles the panel's top edge at the right, like the tab in the middle.
	close.root.AnchorPoint = Vector2.new(1, 0.5)
	close.root.Position = UDim2.new(1, Theme.Padding.large - CLOSE_INSET, 0, -panelPad.PaddingTop.Offset)
	close.root.ZIndex = tab.ZIndex

	local scroll: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Column",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.ink2,
		Parent = root,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.medium,
		scroll,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	-- Room for the scroll bar and for the cards' outlines and drops.
	Create("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 12),
		PaddingBottom = UDim.new(0, 8),
		Parent = scroll,
	})
	-- Foam fix 3 (like Settings): on touch the column's scroll bar stays on screen while it is longer than its window
	-- (UI/Components/ScrollHint), over the column's right edge; the column fills the panel's content box, so the rail
	-- does too.
	local scrollHint = ScrollHint.new({ scroll = scroll, parent = root })
	scrollHint.root.AnchorPoint = Vector2.new(1, 0)
	scrollHint.root.Position = UDim2.fromScale(1, 0)
	scrollHint.root.Size = UDim2.new(0, scroll.ScrollBarThickness, 1, 0)

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function insetBlock(name: string): Frame
		local block = Theme.inset({
			Name = name,
			LayoutOrder = nextOrder(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = scroll,
		}, Theme.Radius.button, Theme.Padding.medium)
		-- Foam fix 2: centred like its lines' text.
		Theme.list(Enum.FillDirection.Vertical, 6, block, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
		return block
	end

	local intro = Theme.label(
		{ Name = "Intro", LayoutOrder = nextOrder(), Text = text("grip.panelIntro"), Parent = scroll },
		"Body"
	)
	local header = insetBlock("Level")
	local levelLabel = Theme.label({ Name = "Level", LayoutOrder = 1, Parent = header }, "H2")
	local panelBar = ProgressBar.new({
		name = "Bar",
		accent = "mint",
		heightPx = PANEL_BAR_HEIGHT,
		layoutOrder = 2,
		parent = header,
	})
	local barLabel = caption({ Name = "BarText", LayoutOrder = 3, Parent = header })
	local chipLabel = caption({ Name = "Chip", LayoutOrder = 4, Parent = header })
	local goalLabel = Theme.label({ Name = "Goal", LayoutOrder = 5, Parent = header }, "Small", Enum.FontWeight.Bold)

	local help = insetBlock("Help")
	caption({
		Name = "RestedHelp",
		LayoutOrder = 1,
		Text = text("grip.restedHelp", { mult = RESTED.mult }),
		Parent = help,
	})
	caption({ Name = "LimitNote", LayoutOrder = 2, Text = text("grip.limitNote"), Parent = help })
	caption({ Name = "DuelNote", LayoutOrder = nextOrder(), Text = text("grip.duelNote"), Parent = scroll })

	panelRefs = {
		root = root,
		tab = tab,
		title = title,
		scroll = scroll,
		intro = intro,
		levelLabel = levelLabel,
		bar = panelBar,
		barLabel = barLabel,
		chipLabel = chipLabel,
		goalLabel = goalLabel,
		close = close,
	}
	return root
end

local function refreshPanel()
	local refs = panelRefs
	if refs == nil or not UIController.isOpen(SCREEN_PANEL) then
		return
	end
	placePanel(refs.root, refs.tab)
	refs.intro.Visible = GripController.introShown(UIController.layoutClass())
	local model = currentModel()
	if model == nil then
		return
	end
	setLabel(refs.levelLabel, model.levelText)
	refs.bar:set(model.fraction, false)
	setLabel(refs.barLabel, model.barText)
	setLabel(refs.chipLabel, model.chip)
	setLabel(refs.goalLabel, model.goal)
end

-- The idle card (foam restyle): a foam panel with the "Still there?" header tab, the sentence and [Keep going].
local function buildIdleCard(parent: Instance): GuiObject
	local root = Theme.panel({
		Name = "GripIdleCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(IDLE_CARD_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, Theme.Radius.panel, Theme.Padding.large)
	-- The header tab is placed by hand, so the list lives in a child frame (Theme.headerTab).
	Theme.headerTab(root, text("grip.idleTitle"), { name = "Title" })
	local body: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.medium, body)
	Theme.label({
		Name = "Body",
		LayoutOrder = 1,
		Text = text("grip.idleBody"),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = body,
	}, "Body")
	Button.new({
		name = IDLE_BUTTON,
		text = text("grip.idleButton"),
		kind = "primary",
		height = Config.UI.Touch.primaryButton,
		layoutOrder = 2,
		parent = body,
		onActivated = function()
			-- Only closes the card: it never restarts a hold-to-squeeze (§17.7).
			UIController.close(SCREEN_IDLE, "keepGoing")
		end,
	})
	return root
end

-- State -------------------------------------------------------------------------------------------------------------

local function onGrip(raw: any)
	local newView = GripController.normalize(raw)
	local old = view
	view = newView
	if newView == nil then
		refreshCard()
		return
	end
	local oldLevel = level
	local newLevel = GripMath.levelFor(newView.total)
	level = newLevel
	local change = GripController.gripChange(
		baselineTotal ~= nil,
		StateController.isApplyingFull(),
		if old then old.total else nil,
		newView.total,
		oldLevel,
		newLevel
	)
	if change.baseline then
		-- §17.7: the first state of the session, and a full state that replaced the profile (one recovered after an
		-- OFFLINE start, §3.13), are a silent baseline: that Grip was loaded, not earned.
		baselineTotal = newView.total
	end
	refreshCard()
	refreshPanel()
	if GripController.shouldPopLevel(change) and not suppressed() then
		popLevel()
	end
end

local function onLobbyLock()
	if suppressed() then
		UIController.close(SCREEN_IDLE, "matched")
		UIController.close(SCREEN_PANEL, "matched")
	end
	refreshCard()
end

-- Public: pure helpers (unit-tested) --------------------------------------------------------------------------------

-- The `grip` state field as the client uses it, or nil when it is missing or malformed. The total is clamped like
-- the server stores it (GripMath.clampTotal); a timer needs a finite value and at.
function GripController.normalize(raw: unknown): GripView?
	if type(raw) ~= "table" then
		return nil
	end
	local g = raw :: any
	if not finite(g.total) then
		return nil
	end
	local function timer(t: any): Timer?
		if type(t) == "table" and finite(t.value) and finite(t.at) then
			return { value = t.value, at = t.at }
		end
		return nil
	end
	return {
		total = GripMath.clampTotal(g.total),
		rested = timer(g.rested),
	}
end

-- What one new grip state does (§17.7, §17.10). `hadBaseline` = a grip state was already seen this session;
-- `fullApply` = it came in a full Snapshot / StateDelta (StateController.isApplyingFull). The session's first state and
-- every full state are a silent baseline ("Load-time level jumps"): the Grip was loaded, not earned (e.g. a profile
-- recovered after an OFFLINE start, §3.13); fireLevel is still true for the first state and for a level that moved.
-- shortcut: the two totals are unused since slow training went (Phase 6); drop them with the callers' arguments the
-- next time gripChange changes.
function GripController.gripChange(
	hadBaseline: boolean,
	fullApply: boolean,
	_oldTotal: number?,
	_newTotal: number,
	oldLevel: number?,
	newLevel: number
): GripChange
	local levelMoved = newLevel ~= oldLevel
	if not hadBaseline or fullApply then
		return { baseline = true, fireLevel = not hadBaseline or levelMoved }
	end
	return { baseline = false, fireLevel = levelMoved }
end

-- Whether a grip state pops the card's level label (§18.5.1 A9): only a level that moved after the silent baseline
-- (never the session's first state or a full state that replaced the profile: that level was loaded, not earned).
function GripController.shouldPopLevel(change: GripChange): boolean
	return change.fireLevel and not change.baseline
end

-- A goal's identity for the "new goal" toast: its Strings key plus its text; a capsule goal's key plus its capsule
-- (Batch 1: its Coins move with every squeeze, so its text would be a new goal again and again). nil while there is no
-- goal.
function GripController.goalId(model: CardModel): string?
	local key = model.goalKey
	if key == nil then
		return nil
	end
	local slot = if model.goalArgs then model.goalArgs.slot else nil
	return key .. "|" .. (if slot ~= nil then tostring(slot) else model.goal or "")
end

-- Whether a goal that just became the current one is toasted (§17.7 compact layout: "a new goal also appears once
-- as a toast"): only on the compact layout (regular shows the goal on the card), never for the session's first goal
-- (the baseline) and never twice for the same goal, so Coins moving around a price never repeat it.
function GripController.shouldToastGoal(
	toasted: { [string]: boolean },
	goalId: string?,
	compact: boolean,
	first: boolean
): boolean
	return compact and not first and goalId ~= nil and toasted[goalId] ~= true
end

-- Foam fix 2: the Grip panel's base size and how far below the centre it sits, for SD_Modal at `screenPx` px and the UI
-- `scale`. What hangs above its top edge (`above`: half the taller of Close and the header tab) is centred with it: the
-- panel moves down by half of it (a whole offset), like Quests and Settings (centred alone, Close ended 1-4 px above a
-- phone's screen). Foam fix 3: the panel keeps the whole PANEL_HEIGHT_SHARE (fix 2 took the hang out of it, and on a
-- phone the pad cards went under the fold); it is shorter only when that would bring Close's top within PANEL_EDGE of
-- the screen's top. The width is the modal width up to PANEL_MAX_WIDTH. No size yet: PANEL_MAX_WIDTH ×
-- PANEL_FALLBACK_HEIGHT.
function GripController.panelLayout(screenPx: Vector2, scale: number, above: number): PanelLayout
	local valid = finite(screenPx.X) and finite(screenPx.Y) and finite(scale)
	if not valid or screenPx.X <= 0 or screenPx.Y <= 0 or scale <= 0 then
		return { width = PANEL_MAX_WIDTH, height = PANEL_FALLBACK_HEIGHT, shift = 0 }
	end
	local hang = if finite(above) then math.max(0, above) else 0
	local canvas = screenPx.Y / scale
	return {
		width = math.min(PANEL_MAX_WIDTH, Layout.modalWidth(screenPx.X, scale, PANEL_MARGIN)),
		height = math.max(0, math.min(canvas * PANEL_HEIGHT_SHARE, canvas - hang - 2 * PANEL_EDGE)),
		shift = math.floor(hang / 2 + 0.5),
	}
end

-- Foam fix 3: whether the Grip panel's intro line shows. Not on the compact layout: on a phone it pushed the first pad
-- card under the fold. The pad cards are gone since build plan Phase 6; the phone layout is kept as it was until the
-- user decides whether the intro comes back there.
function GripController.introShown(class: string): boolean
	return class ~= "compact"
end

-- True when LocalPlayer.Idled's `t` reaches the idle card's threshold (§17.7).
function GripController.shouldShowIdleCard(idleSeconds: number): boolean
	return finite(idleSeconds) and idleSeconds >= GRIP.idleReminderSeconds
end

-- The format arguments of a GripMath.nextGoal result: its name (nameKey) as {rank}, {level}; a capsule goal's {slot}
-- and its Coins as {have} / {need} (Format.coins).
function GripController.goalArgs(goal: GripMath.Goal): { [string]: any }
	local args: { [string]: any } = { level = goal.level, slot = goal.slot }
	local nameKey = goal.nameKey
	if nameKey then
		args.rank = text(nameKey)
	end
	local need = goal.need
	if need ~= nil then
		args.have = Format.coins(goal.have or 0)
		args.need = Format.coins(need)
	end
	return args
end

-- "Double Grip: about {minutes} min" for a Grip state at server time `now`, or nil while it is empty or off.
function GripController.restedChip(v: GripView, now: number): string?
	local rested = v.rested
	if not RESTED.enabled or rested == nil then
		return nil
	end
	local minutes = GripMath.restedMinutes(SqueezeLimit.current(rested, now, RESTED))
	return if minutes > 0 then text("grip.restedChip", { minutes = minutes }) else nil
end

-- The HUD card's texts for a Grip state at server time `now` (§17.7): level and rank (together, and the rank alone for
-- the regular card's title beside its level tile), the bar ({have}/{need} from GripMath.progress; grip.hudMax at the
-- top; foam fix, user decision 2026-10-09: the fill is have / need too, the same numbers the words show, so 42,000 /
-- 66,000 reads about two thirds full; full at the top), the Double Grip chip and the next goal (Batch 1: a capsule
-- buy first when `capsules` is given, an unlock only with a spare in `owned`; foam fix 2: and its short form for the
-- regular card, CARD_GOAL_KEYS).
function GripController.cardModel(v: GripView, now: number, capsules: any?, coins: number?, owned: any?): CardModel
	local progress = GripMath.progress(v.total)
	local lv = progress.level
	local rank = GripMath.rankFor(lv)
	local rankText = text("grip.rank." .. rank.key)
	local fraction = if progress.isMax or progress.need <= 0 then 1 else progress.have / progress.need
	local goal = GripMath.nextGoal({ total = v.total, capsules = capsules, coins = coins, owned = owned })
	local goalArgs = if goal then GripController.goalArgs(goal) else nil
	return {
		level = lv,
		levelText = text("grip.hudLevel", { level = lv, rank = rankText }),
		levelCompact = text("grip.hudLevelCompact", { level = lv, rank = rankText }),
		rankText = rankText,
		barText = if progress.isMax
			then text("grip.hudMax")
			else text("grip.hudBar", { have = Format.coins(progress.have), need = Format.coins(progress.need) }),
		fraction = math.clamp(fraction, 0, 1),
		chip = GripController.restedChip(v, now),
		goal = if goal then text(goal.textKey, goalArgs) else nil,
		cardGoal = if goal then text(CARD_GOAL_KEYS[goal.textKey] or goal.textKey, goalArgs) else nil,
		goalKey = if goal then goal.textKey else nil,
		goalArgs = goalArgs,
	}
end

-- Public -----------------------------------------------------------------------------------------------------------

-- The local Grip level (nil until the first grip state arrives).
function GripController.level(): number?
	return level
end

-- Small table for Studio debug hooks.
function GripController.debugState(): { [string]: any }
	local v = view
	local model = currentModel()
	local k = card
	return {
		ok = true,
		total = if v then v.total else nil,
		level = level,
		rank = if level then GripMath.rankFor(level).key else nil,
		baselineTotal = baselineTotal,
		cardShown = k ~= nil and k.root.Visible,
		cardMode = HudController.columnPlan().grip, -- Part 8: regular / compact / hidden (HudFormat.leftColumnPlan)
		cardHeight = if k then k.root.AbsoluteSize.Y else nil, -- px on screen (>= 44 on the compact card)
		chip = if model then model.chip else nil,
		goal = if model then model.goal else nil,
		suppressed = suppressed(),
		panelOpen = UIController.isOpen(SCREEN_PANEL),
		idleOpen = UIController.isOpen(SCREEN_IDLE),
	}
end

-- Studio (DebugHooks): opens the idle card as if LocalPlayer.Idled had reached the threshold.
function GripController.debugIdle(): boolean
	if suppressed() or not GRIP.enabled then
		return false
	end
	return UIController.open(SCREEN_IDLE)
end

-- Lifecycle --------------------------------------------------------------------------------------------------------

function GripController.init()
	if not GRIP.enabled then
		return
	end
	local c = Cleanup.new()
	cleanup = c
	c:add(UIController.registerScreen(SCREEN_PANEL, {
		build = buildPanel,
		onOpen = function()
			refreshPanel()
		end,
		primary = function(): GuiObject?
			local refs = panelRefs
			return if refs then refs.close.root else nil
		end,
	}))
	c:add(UIController.registerScreen(SCREEN_IDLE, {
		build = buildIdleCard,
		primary = function(): GuiObject?
			local found = UIController.screenGui(MODAL_GUI):FindFirstChild(IDLE_BUTTON, true)
			return if found and found:IsA("GuiObject") then found else nil
		end,
	}))
	c:add(StateController.changed("grip"):connect(onGrip))
	-- Batch 1 #7a: the next goal follows the capsules, the Coins and the owned squishies (a spare allows an unlock).
	for _, field in { "capsules", "coins", "owned" } do
		c:add(StateController.changed(field):connect(function()
			refreshCard()
			refreshPanel()
		end))
	end
	c:add(StateController.LobbyLockChanged:connect(onLobbyLock))
	c:add(UIController.LayoutChanged:connect(function()
		refreshCard()
		refreshPanel()
	end))
	-- Part 8: the card's layout follows HudController's left column plan.
	c:add(HudController.ColumnPlanChanged:connect(function()
		applyCardLayout()
	end))
	c:add(function()
		view, level, baselineTotal = nil, nil, nil
		lastGoalKey, goalBaselineSet = nil, false
		panelRefs = nil
		if cardPresent then
			cardPresent = false
			HudController.setColumnItem("grip", false)
		end
		table.clear(toastedGoals)
	end)
	local existing = StateController.get("grip")
	if existing ~= nil then
		onGrip(existing)
	end
end

function GripController.start()
	local c = cleanup
	if c == nil then
		return
	end
	buildCard(c)
	refreshCard()
	local player = Players.LocalPlayer
	if player then
		c:add(player.Idled:Connect(function(idleSeconds: number)
			if GripController.shouldShowIdleCard(idleSeconds) and not suppressed() then
				UIController.open(SCREEN_IDLE)
			end
		end))
		c:add(player:GetAttributeChangedSignal(ATTR_DUEL_PHASE):Connect(onLobbyLock))
		c:add(player:GetAttributeChangedSignal(ATTR_MATCH_ID):Connect(onLobbyLock))
	end
	c:add(task.spawn(function()
		while true do
			task.wait(TIMER_REFRESH_SECONDS)
			local ok, err = pcall(function(): any
				refreshCard()
				refreshPanel()
				return nil
			end)
			if not ok then
				log:error("Grip card refresh failed:", err)
			end
		end
	end))
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function GripController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return GripController
