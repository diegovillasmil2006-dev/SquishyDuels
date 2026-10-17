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
--   UI FINAL R4 (plan work/ui/PLAN.md R4 "Grip row", G4.14; `H:n` = "Squishy Duels HUD.dc.html" line n): the regular
--   layout is the design's bare row (H:82-90): no card face; padding-left 6; the bar column (200 wide, H:83): the Grip
--   bar (Components/ProgressBar "grip": 14 px border-box, white .7 trough, its fill and 22 px shine, H:84-85) over its
--   3 px ink lip, and "{have} / {need} Grip" (the Sticker role gripText, H:87); beside it, 14 px up, the Double Grip
--   chip (H:89: the bolt pulsing 1 s and "2x ~{minutes} min", hud.gripBoost, plan FD3); under the row the goal line
--   (UD4, kept: AFFECTED 2026-10-15, it names capsule buys). The level shows on HudController's GRIP float
--   (setGripLevel, H:92-96; its number pops with the compact label's, §18.5.1 A9); the rank stays in the panel.
--   Hud_GripButton is the row's invisible tap target (no hover look: H:82 has no data-fx; at least the touch minimum
--   tall, the row centred in it, PR1); on each Grip gain after the baseline the row squashes (H:707: FX.squash(grip,
--   .3), the press squash's sy series on its UIScale, PR4).
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
-- * UI FINAL R3 (the window frame, plan work/ui/PLAN.md R3; `H:n` = "Squishy Duels HUD.dc.html" line n): the panel and
--   the idle card are Theme.windows (kind "grip": the grip bar's mint band, H:85, no sticker, a reading: the design
--   has no Grip window) with their band (Theme.headerTab) and, on the panel, the 76 px close X in the band
--   (Theme.attachClose, H:252); placePanel lays the chrome out at the window's chrome scale (Theme.fitWindow,
--   Layout.windowFit) and what hangs above is the X's 22 px. The column scrolls with the design's scroll bar
--   (Theme.scrollbar, H:22); the texts on the pink body (the intro, the duel note, the idle card's sentence) take the
--   window's text colour (H:196).
-- * UI FINAL R9 (plan work/ui/PLAN.md R9; `H:n` as above):
--   - The level-up show (G9.10-G9.13, UD8; UI/LevelUpShow): a level that rose after the silent baseline
--     (levelUpShow) plays the design's full show in its own layer (Config.UI.Sticker.levelUp.layer) with the equipped
--     squishy and, for a rank reached (GripMath.unlocks, FD8), its unlock line; the card's level pop stays. It waits
--     (LevelUpShow.merge) from Matched through Returning and while a box reveal is open, and plays when that ends; one
--     at a time; a level-up during the show plays it again with the new numbers (H:730). Its sounds (G9.12, RL8:
--     the nearest clips): the slam box.open; the tone ui.levelTone (pack 2); the main hit ui.gripUnlock, ui.purchase
--     and box.open. The server's grip.levelUp toast and its ui.gripUnlock are dropped while a show plays, waits or
--     just played (NotifyController.present); with no show it is still the toast. AFFECTED 2026-10-15: capsule tiers
--     are removed, so only a rank fills the unlock line (the new systems' unlocks later).
--   - The idle card (the screens the design lacks): the confirm card's look (H:457-458, Config.UI.confirm): the
--     purple card 480 wide (border 5, radius 30, the 10 px lip, inset 4 at .12, padding 64 28 26, gap 12), the
--     130 px medallion at -70 (the radial img.fx.radial.medallion, its fallback while it has no id; the 6 px lip,
--     border 5) holding the squeeze picture bobbing 2.4 s, the title in confirmTitle, the sentence in confirmDesc and
--     [Keep going] the green 62 px button.

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
local Palette = require(Shared.Art.Palette)
local SqueezeLimit = require(Shared.SqueezeLimit)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)
local Button = require(Client.UI.Components.Button)
local Create = require(Client.UI.Create)
local Focus = require(Client.UI.Focus)
local HudFormat = require(Client.UI.HudFormat)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local Layout = require(Client.UI.Layout)
local LevelUpShow = require(Client.UI.LevelUpShow)
local ProgressBar = require(Client.UI.Components.ProgressBar)
local ScrollHint = require(Client.UI.Components.ScrollHint)
local Theme = require(Client.UI.Theme)
local UiFx = require(Client.UI.UiFx)
local HudController = require(script.Parent.HudController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
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
	rankText: string, -- grip.rank.* (UI FINAL R4: the panel; the regular row shows no rank)
	barText: string, -- grip.hudBar or grip.hudMax
	fraction: number, -- 0..1: have / need, the numbers barText shows (1 at the top)
	chip: string?, -- grip.restedChip, nil while Double Grip is empty or off
	boost: string?, -- UI FINAL R4: the bare row's chip, hud.gripBoost "2x ~{minutes} min" (H:89), nil the same
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
	face: Frame, -- UI FINAL R4: the compact card's foam (the regular row is bare, H:82)
	regular: Frame,
	compact: Frame,
	bar: ProgressBar.ProgressBar,
	barLabel: TextLabel,
	chipRow: Frame,
	chipLabel: TextLabel,
	goalLabel: TextLabel,
	compactLabel: TextLabel,
	compactBar: ProgressBar.ProgressBar,
	levelScales: { UIScale }, -- the level pop (§18.5.1 A9): on the compact level label (UI FINAL R4: the regular row
	-- shows no level; HudController's GRIP float does)
	levelTweens: { Tween },
	barSet: boolean, -- the bars got their first value (later values ease)
	squash: UIScale, -- UI FINAL R4: the row's squash on a Grip gain (H:707)
	squashHandle: Scheduler.Handle?,
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
-- UI FINAL R4 (H:82-90): the bare row's numbers (Config.UI.Sticker.hud.grip) and the Grip bar with its 3 px lip (H:84).
local HUD_GRIP = Config.UI.Sticker.hud.grip
local BAR_PX = Config.UI.Sticker.bars.grip.height
local BAR_LIP_PX = Config.UI.Sticker.lip.bar
local PRESS = Config.UI.motion.buttonPress
local BAR_EPSILON = 1e-4 -- the bar eases only when its share really changed (the card refreshes every few seconds)
local WINDOW_KIND = "grip" -- UI FINAL R3: the panel's and the idle card's Config.UI.Sticker.window kind (a reading)
local PANEL_BAR_HEIGHT = 14
local PANEL_MAX_WIDTH = 560
local PANEL_MARGIN = 24
-- The panel takes this share of the screen's height (as Quests); foam fix 3: what hangs above it (Close, the header
-- tab) is centred with it, and it gives up height only to keep Close's top PANEL_EDGE inside the screen.
local PANEL_HEIGHT_SHARE = 0.86
local PANEL_EDGE = Theme.Padding.small
local PANEL_FALLBACK_HEIGHT = 480 -- before SD_Modal has a size
-- UI FINAL R9: the idle card in the confirm card's look (H:457-458) and the level-up show (H:506-535, H:719-722).
local CONFIRM = Config.UI.confirm
local IDLE_PICTURE = "img.icon.squeeze"
local MEDALLION_KEY = "img.fx.radial.medallion"
local LEVEL_UP_LAYER = Config.UI.Sticker.levelUp.layer
local LEVEL_UP_NOTICE = "grip.levelUp"
local REVEAL_SCREEN = "boxReveal" -- BoxController's reveal: the show waits for it (G9.13)
local OVERLAY_GUI = "SD_Overlay" -- its size is the safe area (CoreUISafeInsets)
local SHOW_RECENT_SECONDS = 5 -- reading: a grip.levelUp notice this soon after a show is the show's own
local SHOW_NOTICE_WAIT_SECONDS = 1 -- reading: a notice before its state waits this long for its show
local LEVEL_UP_SOUNDS: { [string]: { string } } = { -- G9.12 (RL8: the nearest clips)
	slam = { "box.open" }, -- H:719
	tone = { "ui.levelTone" }, -- H:720 (pack 2)
	main = { "ui.gripUnlock", "ui.purchase", "box.open" }, -- H:722
}
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
-- UI FINAL R9: the level-up show waiting for its turn, the one playing and when the last one started (os.clock()).
local pendingShow: LevelUpShow.Pending? = nil
local shownShow: LevelUpShow.Pending? = nil
local lastShowAt = -math.huge

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

-- Double Grip's whole minutes at server time `now` (0 while it is empty or off).
local function restedMinutes(v: GripView, now: number): number
	local rested = v.rested
	if not RESTED.enabled or rested == nil then
		return 0
	end
	return GripMath.restedMinutes(SqueezeLimit.current(rested, now, RESTED))
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

-- UI FINAL R4 (H:82-90, G4.14): the regular layout is the design's bare Grip row, 6 in from the left (H:82; its goal
-- line too): the bar column (200 wide, 3 apart, H:83): the Grip bar over its 3 px ink lip (H:84), then "{have} /
-- {need} Grip" (gripText, H:87); 10 to its right (centred) the Double Grip chip, raised by its 14 px bottom padding
-- (H:89 margin-top -14 in a centred row: 7 up either way): the bolt pulsing 1 s, 2 apart from "2x ~{minutes} min"
-- (boost). Under the row the goal line (UD4, kept; in the row's text look, a reading), wrapped at the row's width
-- (HudFormat.gripGoalWidth; applyCardLayout follows the text size).
local function buildRegular(c: Cleanup.Cleanup, body: Frame): (Frame, { [string]: any })
	local regular: Frame = Create("Frame", {
		Name = "Regular",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = body,
	})
	Create("UIPadding", { PaddingLeft = UDim.new(0, COLUMN.gripPadLeft), Parent = regular })
	Theme.list(
		Enum.FillDirection.Vertical,
		COLUMN.listGap,
		regular,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local row: Frame = Create("Frame", {
		Name = "Row",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = regular,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		COLUMN.gripRowGap,
		row,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	-- A text longer than the bar widens the column (its 200 is the least; HudFormat.gripRowWidth).
	local column: Frame = Create("Frame", {
		Name = "BarColumn",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMN.gripBarWidth, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = row,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		COLUMN.gripBarGap,
		column,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local barHolder: Frame = Create("Frame", {
		Name = "BarHolder",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMN.gripBarWidth, COLUMN.gripBarHeight),
		Parent = column,
	})
	-- H:84 box-shadow 0 3px 0 #1E1428: the bar's shape in the ink, 3 px lower, behind it.
	local lip: Frame = Create("Frame", {
		Name = "Lip",
		BackgroundColor3 = Theme.Colors.inkUI,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, BAR_LIP_PX),
		Size = UDim2.new(1, 0, 0, BAR_PX),
		ZIndex = 0,
		Parent = barHolder,
	})
	Theme.corner(BAR_PX, lip)
	local gripBar = ProgressBar.new({
		name = "Bar",
		variant = "grip",
		widthPx = COLUMN.gripBarWidth,
		parent = barHolder,
	})
	c:add(gripBar)
	local barLabel = Theme.label({
		Name = "BarText",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = column,
	}, "Small")
	Theme.stickerText(barLabel, "gripText") -- H:87
	barLabel.TextWrapped = false
	local chipRow: Frame = Create("Frame", {
		Name = "Chip",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		Parent = row,
	})
	Create("UIPadding", { PaddingBottom = UDim.new(0, HUD_GRIP.boostRaise), Parent = chipRow })
	Theme.list(
		Enum.FillDirection.Horizontal,
		COLUMN.boostGap,
		chipRow,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	-- The bolt's pulse plays on its picture inside a cell no layout places (UiIdle's inner holder).
	local boltCell: Frame = Create("Frame", {
		Name = "BoltCell",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(COLUMN.boltPx, COLUMN.boltPx),
		Parent = chipRow,
	})
	local bolt = IconGlyph.image("img.icon.bolt", { name = "Bolt", sizePx = COLUMN.boltPx, parent = boltCell })
	-- Centre-anchored: the pulse's UIScale scales about the AnchorPoint, so it breathes about its centre (CSS 50%).
	bolt.AnchorPoint = Vector2.new(0.5, 0.5)
	bolt.Position = UDim2.fromScale(0.5, 0.5)
	local pulse = UiIdle.add(bolt, "pulse", { periodS = HUD_GRIP.boltPulseS }) -- H:89 sdPulse 1s
	if pulse then
		c:add(function()
			pulse:remove()
		end)
	end
	local chipLabel = Theme.label({
		Name = "Text",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = chipRow,
	}, "Small")
	Theme.stickerText(chipLabel, "boost") -- H:89
	chipLabel.TextWrapped = false
	local goalLabel = Theme.label({
		Name = "Goal",
		LayoutOrder = 2,
		Visible = false,
		Size = UDim2.fromOffset(HudFormat.gripGoalWidth(), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = regular,
	}, "Small")
	Theme.stickerText(goalLabel, "gripText")
	goalLabel.TextWrapped = true
	return regular,
		{
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
	local startSize = UDim2.fromOffset(HudFormat.gripRowWidth(), HudFormat.gripCardHeight("regular", nil, 1))
	local slot: Frame = Create("Frame", {
		Name = "Hud_GripSlot",
		BackgroundTransparency = 1,
		Size = startSize,
		LayoutOrder = CARD_ORDER,
		Visible = false,
	})
	-- UI FINAL R4: the regular row's invisible tap target (H:82: no face and no press look, no data-fx); the compact
	-- card keeps its foam on Face. Its UIScale "Scale" is the row's squash on a Grip gain (squashRow).
	local root: TextButton = Create("TextButton", {
		Name = "Hud_GripButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = startSize,
		Visible = false,
		Parent = slot,
	})
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Visible = false,
		Parent = root,
	})
	cardFoam(face)
	local squash: UIScale = Create("UIScale", { Name = "Scale", Scale = 1, Parent = root })
	Focus.decorate(root, Theme.Radius.panel)
	-- Part 8: one layout at a time (the other is invisible, so the list skips it). The root's size follows the body
	-- (applyCardLayout): no AutomaticSize.
	local body: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
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
	-- UI FINAL R4: the compact label and HudController's GRIP float (the regular row's level) pop (§18.5.1 A9; the
	-- burst stays on the compact label, the first: the float sits over the play area's top).
	local levelScales: { UIScale } = { Create("UIScale", { Name = "LevelPop", Scale = 1, Parent = compactLabel }) }
	local floatLevel = HudController.gripLevelLabel()
	if floatLevel then
		local floatPop: UIScale = Create("UIScale", { Name = "LevelPop", Scale = 1, Parent = floatLevel })
		c:add(floatPop) -- the label is HudController's: the scale goes with this card
		table.insert(levelScales, floatPop)
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
		face = face,
		regular = regular,
		compact = compact,
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
		squash = squash,
		squashHandle = nil,
	}
	-- The root follows the body's size (the layout changes it, and the lines at a new text size).
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
			local handle = k.squashHandle
			k.squashHandle = nil
			if handle then
				handle:disconnect()
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

-- UI FINAL R4 (H:707: FX.squash(grip, .3) on each Grip gain; PR4): the press squash's series for the row's amount
-- (buttonPress.amount x hud.grip.squash), drawn as Button.decoratedScale on the root's UIScale (a new one restarts
-- it); none under ReducedMotion or while the card is hidden.
local function squashRow()
	local k = card
	if k == nil or not k.root.Visible or Tweens.reducedMotion() then
		return
	end
	local running = k.squashHandle
	if running then
		running:disconnect()
	end
	local scale = k.squash
	local amount = PRESS.amount * HUD_GRIP.squash
	local duration = PRESS.ms / 1000
	local elapsed = 0
	k.squashHandle = Scheduler.add(function(dt: number): boolean
		elapsed += dt
		local u = math.min(elapsed / duration, 1)
		scale.Scale = if u >= 1 then 1 else Button.decoratedScale(Button.squashAt(u, amount))
		if u >= 1 then
			k.squashHandle = nil
			return false
		end
		return true
	end, "render")
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

-- The card's own scale (its UIScale "Scale" on the root, UI FINAL R4: the row's squash; 1 without it), so its measured
-- sizes are read unscaled (foam fix: a hovered card measured its body 4% taller and grew itself on top of the scale).
local function feelScale(root: GuiObject): number
	local scale = root:FindFirstChild("Scale")
	return if scale and scale:IsA("UIScale") and scale.Scale > 0 then scale.Scale else 1
end

-- Part 8: the card's layout from HudController's column plan (regular / compact / hidden), whether it is up, and its
-- size: compact = the touch-sized tap target (HudFormat.gripCardHeight) as wide as its line (gripCompactWidth);
-- regular (UI FINAL R4) = the bare row's measured size (before it has one: HudFormat.gripRowWidth / gripCardHeight).
-- Its slot in the column takes the same, unscaled size.
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
	k.face.Visible = compactLayout
	local scale = UIController.scale() * feelScale(k.root)
	local textScale = HudController.textScale()
	local width, height = CARD_WIDTH, 0
	local hitHeight = 0 -- UI FINAL R4: the root (the tap target) can be taller than the slot
	if compactLayout then
		height = HudFormat.gripCardHeight("compact", textScale, plan.scale)
		width = HudFormat.gripCompactWidth(k.compactLabel.Text, textScale)
		local body = (height - CARD_BANDS.bevel - CARD_BANDS.drop) / 2
		k.body.AnchorPoint = Vector2.new(0, 0.5)
		k.body.Position = UDim2.fromOffset(COLUMN.cardPadding + 4, body)
		k.body.AutomaticSize = Enum.AutomaticSize.Y
		k.body.Size = UDim2.new(1, -2 * (COLUMN.cardPadding + 4), 0, 0)
	else
		-- The row centred in its tap target, which is at least the touch minimum tall (PR1: the max-level row with no
		-- goal line is about 40); the slot keeps the row's own size, so the column does not move.
		k.body.AnchorPoint = Vector2.new(0, 0.5)
		k.body.Position = UDim2.fromScale(0, 0.5)
		k.body.AutomaticSize = Enum.AutomaticSize.XY
		k.body.Size = UDim2.fromOffset(0, 0)
		local goalSize = UDim2.fromOffset(HudFormat.gripGoalWidth(textScale), 0)
		if k.goalLabel.Size ~= goalSize then
			k.goalLabel.Size = goalSize
		end
		local measured = if scale > 0 then k.body.AbsoluteSize / scale else Vector2.zero
		width = math.ceil(if measured.X > 0 then measured.X else HudFormat.gripRowWidth(textScale))
		height =
			math.ceil(if measured.Y > 0 then measured.Y else HudFormat.gripCardHeight("regular", textScale, plan.scale))
		hitHeight = math.max(height, Config.UI.Touch.minTarget)
	end
	local size = UDim2.fromOffset(width, height)
	local hit = UDim2.fromOffset(width, math.max(height, hitHeight))
	if k.root.Size ~= hit then
		k.root.Size = hit
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
	-- UI FINAL R4 (H:92-96): the level shows on HudController's GRIP float while the card is up.
	HudController.setGripLevel(if cardPresent and model then model.level else nil)
	if model == nil then
		applyCardLayout()
		return
	end
	local compactLayout = HudController.columnPlan().grip ~= "regular"
	setLabel(k.barLabel, model.barText)
	k.chipRow.Visible = model.boost ~= nil
	setLabel(k.chipLabel, model.boost)
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

-- Foam fix 2: sizes and places the panel (panelLayout) with what hangs above its top edge. UI FINAL R3: the band at
-- the window's chrome scale (Theme.fitWindow); what hangs above is the close X (H:252).
local function placePanel(root: GuiObject)
	local scale = UIController.scale()
	local screen = UIController.screenGui(MODAL_GUI).AbsoluteSize
	local above = Theme.fitWindow(root, Layout.windowFit(screen, WINDOW_KIND).k).above
	local layout = GripController.panelLayout(screen, scale, above)
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
	local root = Theme.window({
		Name = "GripPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Parent = parent,
	}, WINDOW_KIND, Theme.Padding.large)
	-- UI FINAL R3: the band on the window's top (it sets the top padding; the panel holds no list itself) and the
	-- 76 px X in it (H:252). No header row: the column starts right under the band.
	local tab, title = Theme.headerTab(root, text("grip.panelTitle"))
	local close = Button.new({
		name = "Grip_CloseButton",
		text = text("common.close"),
		kind = "close", -- UI overhaul: the chunky red X
		parent = root,
		onActivated = function()
			UIController.close(SCREEN_PANEL, "close")
		end,
	})
	Theme.attachClose(root, close.root)
	placePanel(root)

	local scroll: ScrollingFrame = Theme.scrollbar(Create("ScrollingFrame", {
		Name = "Column",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = root,
	}))
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
		PaddingRight = UDim.new(0, Theme.SCROLLBAR_PX + 6),
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
	Theme.textOnWindow(intro) -- UI FINAL R3: on the pink body (H:196)
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
	local duelNote =
		caption({ Name = "DuelNote", LayoutOrder = nextOrder(), Text = text("grip.duelNote"), Parent = scroll })
	Theme.textOnWindow(duelNote) -- UI FINAL R3: on the pink body (H:196)

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
	placePanel(refs.root)
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

-- The idle card (UI FINAL R9: the confirm card's look, H:457-458; see the header): the title, the sentence and
-- [Keep going] under the medallion with the squeeze picture. Its height from its measured parts.
local function buildIdleCard(parent: Instance): GuiObject
	local card, medal = CONFIRM.card, CONFIRM.medallion
	local innerWidth = card.width - 2 * card.padX
	local titleText, bodyText = text("grip.idleTitle"), text("grip.idleBody")
	local titleHeight = math.ceil(Theme.textBounds(titleText, "Name", nil, innerWidth).Y)
	local bodyHeight = math.ceil(Theme.textBounds(bodyText, "Small", nil, innerWidth).Y)
	local buttonHeight = CONFIRM.buttons.face + Config.UI.Sticker.lip.button
	local height = card.padTop
		+ titleHeight
		+ card.gap
		+ bodyHeight
		+ card.gap
		+ CONFIRM.buttons.marginTop
		+ buttonHeight
		+ card.padBottom
		+ card.lip
	local root: Frame = Create("Frame", {
		Name = "GripIdleCard",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(card.width, height),
		Active = true,
		Parent = parent,
	})
	local top, bottom = Palette.StickerPillTop, Palette.StickerPillBottom -- H:457: #9775FF -> #6C47F5
	local bands = Layout.stickerBands(card.border, card.inset.px, 0, card.lip)
	Theme.foam(root, {
		radius = card.radius,
		stroke = card.border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
		colors = {
			face = top,
			faceEnd = bottom,
			top = top:Lerp(Color3.new(1, 1, 1), card.inset.alpha),
			drop = Theme.Colors.inkUI,
		},
	})
	local body: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	Create("UIPadding", {
		PaddingTop = UDim.new(0, card.padTop),
		PaddingLeft = UDim.new(0, card.padX),
		PaddingRight = UDim.new(0, card.padX),
		PaddingBottom = UDim.new(0, card.padBottom + card.lip),
		Parent = body,
	})
	Theme.list(Enum.FillDirection.Vertical, card.gap, body, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	local title = Theme.label({
		Name = "Title",
		Text = titleText,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, titleHeight),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		Parent = body,
	}, "Name")
	Theme.stickerText(title, "confirmTitle") -- H:459
	local sentence = Theme.label({
		Name = "Body",
		Text = bodyText,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, bodyHeight),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = body,
	}, "Small")
	Theme.stickerText(sentence, "confirmDesc") -- H:460
	local row: Frame = Create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, CONFIRM.buttons.marginTop + buttonHeight),
		LayoutOrder = 3,
		Parent = body,
	})
	local keepGoing = Button.new({
		name = IDLE_BUTTON,
		text = text("grip.idleButton"),
		kind = "primary", -- H:463: the green
		width = innerWidth,
		height = CONFIRM.buttons.face,
		textRole = "button", -- H:462: 24 px, stroke 5
		parent = row,
		onActivated = function()
			-- Only closes the card: it never restarts a hold-to-squeeze (§17.7).
			UIController.close(SCREEN_IDLE, "keepGoing")
		end,
	})
	keepGoing.root.Position = UDim2.fromOffset(0, CONFIRM.buttons.marginTop)
	-- H:458: the medallion over the card's top edge: its lip, the radial face, the ring, the picture bobbing.
	local holder: Frame = Create("Frame", {
		Name = "Medallion",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, medal.top + medal.px / 2),
		Size = UDim2.fromOffset(medal.px, medal.px),
		ZIndex = 3,
		Parent = root,
	})
	local lip: Frame = Create("Frame", {
		Name = "Lip",
		BackgroundColor3 = Theme.Colors.inkUI,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, medal.lip),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = holder,
	})
	Theme.corner(medal.px, lip)
	local face: Frame = Create("Frame", {
		Name = "Face",
		BackgroundColor3 = Palette.StickerGoldMid,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = holder,
	})
	Theme.corner(medal.px, face)
	Theme.radial(face, MEDALLION_KEY, {
		inner = Palette.StickerMedallionTop,
		outer = Palette.StickerGoldMid,
		centre = Vector2.new(0.5, medal.centreY),
	})
	local ring: Frame = Create("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = holder,
	})
	Theme.corner(medal.px, ring)
	local ringStroke = Theme.stroke(Theme.Colors.inkUI, medal.border, ring)
	pcall(function()
		(ringStroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner -- H:458 border-box
	end)
	local bob: Frame = Create("Frame", {
		Name = "SD_Bob",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(medal.icon, medal.icon),
		ZIndex = 3,
		Parent = holder,
	})
	IconGlyph.image(IDLE_PICTURE, { name = "Picture", sizePx = medal.icon, parent = bob })
	UiIdle.add(bob, "bob", { periodS = medal.bobS })
	return root
end

-- Level-up show (UI FINAL R9) ------------------------------------------------------------------------------------------

-- G9.13: the show may play now: the lobby (not Matched through Returning) and no box reveal open.
local function canShow(): boolean
	return not suppressed() and not UIController.isOpen(REVEAL_SCREEN)
end

local function playShow(show: LevelUpShow.Pending)
	shownShow = show
	lastShowAt = os.clock()
	local overlay = UIController.screenGui(OVERLAY_GUI)
	local played: LevelUpShow.Pending = show
	LevelUpShow.play({
		layer = UIController.screenGui(LEVEL_UP_LAYER.name, {
			displayOrder = LEVEL_UP_LAYER.displayOrder,
			insets = LEVEL_UP_LAYER.insets,
		}),
		prev = show.prev,
		level = show.level,
		unlock = show.unlock,
		squishyId = StateController.equipped(),
		uiScale = UIController.scale,
		safe = function(): Vector2
			return overlay.AbsoluteSize
		end,
		onCue = function(cue: LevelUpShow.Cue)
			local keys = LEVEL_UP_SOUNDS[cue]
			if keys then
				for _, key in keys do
					SoundController.play(key)
				end
			end
		end,
		onDone = function()
			if shownShow == played then
				shownShow = nil
			end
			task.defer(function()
				local waiting = pendingShow
				if waiting and canShow() and not LevelUpShow.isPlaying() then
					pendingShow = nil
					playShow(waiting)
				end
			end)
		end,
	})
end

-- A waiting show plays once nothing holds it (the lock ended, the reveal closed).
local function playPendingShow()
	local waiting = pendingShow
	if waiting and canShow() and not LevelUpShow.isPlaying() then
		pendingShow = nil
		playShow(waiting)
	end
end

-- G9.13: a level-up from `prev` to `newLevel`: plays now, again with the new numbers over a playing show (H:730), or
-- waits.
local function queueShow(prev: number, newLevel: number)
	local reached = GripMath.unlocks(prev, newLevel).rank
	local unlock = if reached then text("grip.rank." .. reached.key) else nil
	if canShow() then
		local playingNow = if LevelUpShow.isPlaying() then shownShow else nil
		playShow(LevelUpShow.merge(playingNow, prev, newLevel, if unlock ~= "" then unlock else nil))
	else
		pendingShow = LevelUpShow.merge(pendingShow, prev, newLevel, if unlock ~= "" then unlock else nil)
	end
end

-- Whether a show plays, waits or just played (the grip.levelUp toast is its own then).
local function showActive(): boolean
	return LevelUpShow.isPlaying() or pendingShow ~= nil or os.clock() - lastShowAt < SHOW_RECENT_SECONDS
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
	if GripController.levelUpShow(change, oldLevel, newLevel) then
		queueShow(oldLevel :: number, newLevel)
	end
	if GripController.shouldSquash(change, if old then old.total else nil, newView.total) and not suppressed() then
		squashRow()
	end
end

local function onLobbyLock()
	if suppressed() then
		UIController.close(SCREEN_IDLE, "matched")
		UIController.close(SCREEN_PANEL, "matched")
	end
	refreshCard()
	playPendingShow() -- UI FINAL R9: a level-up that waited for the match to end
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

-- UI FINAL R9 (G9.13): whether a grip state plays the level-up show: the level rose after the silent baseline.
function GripController.levelUpShow(change: GripChange, oldLevel: number?, newLevel: number): boolean
	return GripController.shouldPopLevel(change) and oldLevel ~= nil and newLevel > oldLevel
end

-- UI FINAL R4 (H:707): whether a grip state squashes the row: Grip gained after the silent baseline.
function GripController.shouldSquash(change: GripChange, oldTotal: number?, newTotal: number): boolean
	return not change.baseline and oldTotal ~= nil and newTotal > oldTotal
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
	local minutes = restedMinutes(v, now)
	return if minutes > 0 then text("grip.restedChip", { minutes = minutes }) else nil
end

-- The HUD card's texts for a Grip state at server time `now` (§17.7): level and rank (together, and the rank alone for
-- the regular card's title beside its level tile), the bar ({have}/{need} from GripMath.progress; grip.hudMax at the
-- top; foam fix, user decision 2026-10-09: the fill is have / need too, the same numbers the words show, so 42,000 /
-- 66,000 reads about two thirds full; full at the top), the Double Grip chip and the next goal (Batch 1: a capsule
-- buy first when `capsules` is given, an unlock only with a spare in `owned`; foam fix 2: and its short form for the
-- regular card, CARD_GOAL_KEYS; UI FINAL R4: the bare row's chip, boost).
function GripController.cardModel(v: GripView, now: number, capsules: any?, coins: number?, owned: any?): CardModel
	local progress = GripMath.progress(v.total)
	local lv = progress.level
	local rank = GripMath.rankFor(lv)
	local rankText = text("grip.rank." .. rank.key)
	local fraction = if progress.isMax or progress.need <= 0 then 1 else progress.have / progress.need
	local goal = GripMath.nextGoal({ total = v.total, capsules = capsules, coins = coins, owned = owned })
	local goalArgs = if goal then GripController.goalArgs(goal) else nil
	local minutes = restedMinutes(v, now)
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
		boost = if minutes > 0 then text("hud.gripBoost", { minutes = minutes }) else nil, -- UI FINAL R4 (H:89)
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
		boost = if model then model.boost else nil, -- UI FINAL R4: the bare row's chip
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
	-- UI FINAL R9 (G9.13): a level-up that waited for a box reveal plays once it closes.
	c:add(UIController.ScreenClosed:connect(function(name: string)
		if name == REVEAL_SCREEN then
			task.defer(playPendingShow)
		end
	end))
	-- UI FINAL R9: the server's grip.levelUp toast goes while its show plays, waits or just played; a notice that
	-- comes before its grip state waits SHOW_NOTICE_WAIT_SECONDS for the show, else it is still the toast.
	c:add(NotifyController.present(LEVEL_UP_NOTICE, function(_code: string, args: any, kind: any): boolean
		if showActive() then
			return true
		end
		local toastText = text(LEVEL_UP_NOTICE, if type(args) == "table" then args else nil)
		task.delay(SHOW_NOTICE_WAIT_SECONDS, function()
			if not showActive() and toastText ~= "" then
				UIController.toast(toastText, kind, { sound = Config.Audio.toastSounds[LEVEL_UP_NOTICE] })
			end
		end)
		return true
	end))
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
		pendingShow, shownShow = nil, nil
		LevelUpShow.stop()
		if cardPresent then
			cardPresent = false
			HudController.setColumnItem("grip", false)
			HudController.setGripLevel(nil)
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
