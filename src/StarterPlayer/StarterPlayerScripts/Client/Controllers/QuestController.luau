--!strict
-- QuestController (client only). DESIGN §6.8 (quests and starter tasks), §11.6 (Quests screen), §11.3 (states), §11.4
-- (focus), §7.6 (the quest board stand), §18.5.2 B2 (coin flights). The server owns progress, claims and swaps
-- (QuestService); this module shows the `quests` state and sends QuestClaim / QuestSwap / EquipSquishy. Looks:
-- UI/QuestFormat (pure).
-- * The "quests" modal (registered in init, so the HUD's Quests button and the SD_QuestBoard prompt come alive, §7.6):
--   the Daily quests (one row per quest of the day, or "No quests right now. Check back in {time}."), the Starter
--   tasks (hidden once all are claimed) and Top Wins, with the time to the next quest day (refreshed every second while
--   open). A row (Quest_<questId>): the quest's picture, its line, "3 / 5" and the bar, the reward (Phase 5: its
--   squeezes × the `capsules` field's squeeze value), Quests_SwapButton on unfinished daily quests while the day's
--   free swap is left, the Quests_EquipButton shortcut when the quest's squishy is owned but not equipped, and CLAIM
--   (Quests_ClaimButton) / GO (Quests_GoButton) / the claimed check.
-- * Claim -> NetController.invokeAsync("QuestClaim", questId): on ok the reward flies from the button into the pill
--   (HudController.flyCoins, only for amounts >= coinFlight.minAmount) and "+{coins} Coins" is toasted (§6.8); a
--   replay answered quest.alreadyClaimed is an info toast; any other failure toasts its reason. Swap ->
--   QuestSwap(questId); Equip -> EquipSquishy(squishyId) with the Squishies screen's toasts. One request per row at a
--   time (its button shows the spinner). Locked state (§11.3): a profile that is not ready disables the buttons with
--   reason.data.notReady.
-- * Completion and rollover toasts (quest.complete, quest.autoCollected) are server Notify codes: NotifyController shows
--   them. UI FINAL R9 (G9.1-G9.3, H:161-162, H:739): quest.complete (its args.questId) is the design's quest pop in the
--   HUD tracker's slot (UI/QuestPop, through NotifyController.present: after the hold-back) with the quest's title
--   (QuestFormat.namer) and ui.toast 150 ms later; without a shown tracker (phones, no title) it stays the toast.
-- Times are server times (workspace:GetServerTimeNow()).
-- Batch 3 (friends, review #10; user decision Q3 B): "Top Wins This Week" (QuestFormat.topWins of the topWins state,
-- ShowOffService's weekly board, refreshed by the server about once a minute): the top entries, a note before the
-- first read, while the board cannot be read or for an empty week, and the player's own line.
-- UI FINAL R3 (the window frame, plan work/ui/PLAN.md R3; `H:n` = "Squishy Duels HUD.dc.html" line n): the panel is
-- the design's Quests window (Theme.window "quests", H:350-353: 900 x 620, shrunk to fit with its sticker and X,
-- Layout.windowFit) with its mint band (Theme.headerTab: "QUESTS", H:354; the sticker, H:378) and the 76 px close X in
-- the band (Theme.attachClose, H:379); fitBody lays the chrome out at the window's chrome scale (Theme.fitWindow) and
-- places the window as the design does (Layout.windowShift).
-- UI FINAL R8 (the design's Quests window, plan R8; Config.UI.Quests): the body (padding 18 26 24, gap 14, H:356-357):
-- the tab row (H:358, UD7: Daily / Starter / Top Wins, QuestFormat.tabs; mint when selected, the purple card
-- otherwise; the tab hover, the tab sound; the count badge of quests ready to claim with its sdBadge loop; L1 / R1 step
-- through them) and the reset pill pushed right (H:359, the Daily tab only: the starter tasks and the board do not
-- reset at midnight), then the rows (H:361-373, 12 apart, scrolling with the design bar): the purple row (border
-- #FFE36B when ready; the row hover x +4), the icon tile (QuestFormat.iconFor), the title (at most 2 lines) with
-- "x / y" pushed right, the quest bar (blue, gold once ready or claimed, the shine), the reward pill (the coin and the
-- amount), Swap (cyan) / Equip (green) as the design's chip (PR26), and CLAIM (green, pulsing 1.1 s) / GO (cyan) / the
-- stamped check in the 126 px slot; a claimed row at .6 (a CanvasGroup, T15). Top Wins (PR26): the same row with the
-- rank in the tile, the name as the title and the wins in the pill (the duel picture), the player's own line last.
-- The rows rise in on open and on a tab change (sdRise, i x 60 ms). Claim ok (H:742-746): the claim sound (ui.purchase,
-- RL8), the design's burst and ring at CLAIM and 10 coins (Config.UI.Fx.events.questClaim). GO (UD2, H:748-755): the
-- pop sound, the window closes, then after 240 ms QuestFormat.goRoute: squeeze -> the squeeze waypoint and the toast
-- (QuestFormat.goToast), duel -> QueueController.joinAsync(), practice -> the practice waypoint. Phones: the reward and
-- the chips go under the bar (the row grows by Config.UI.Quests.row.compactExtra).
-- Public: open(), debugState().

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local CountBadge = require(Client.UI.Components.CountBadge)
local Create = require(Client.UI.Create)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local Layout = require(Client.UI.Layout)
local MotionTrack = require(Client.UI.MotionTrack)
local NotifyFormat = require(Client.UI.NotifyFormat)
local ProgressBar = require(Client.UI.Components.ProgressBar)
local QuestFormat = require(Client.UI.QuestFormat)
local QuestPop = require(Client.UI.QuestPop)
local SquishyImage = require(Client.UI.Components.SquishyImage)
local Theme = require(Client.UI.Theme)
local UiFx = require(Client.UI.UiFx)
local UiIdle = require(Client.Anim.UiIdle)
local Waypoint = require(Client.UI.Waypoint)
local WellPill = require(Client.UI.Components.WellPill)
local ControlsController = require(script.Parent.ControlsController)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local QueueController = require(script.Parent.QueueController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

-- UI FINAL R8: a row (H:363-372), pooled: a quest, a Top Wins entry or the player's own line.
type RowKind = "quest" | "wins" | "you"
type RowView = {
	root: TextButton, -- the laid-out box (face + lip): Quest_<id>; the row hover's hit (no click of its own)
	rise: Frame,
	group: CanvasGroup, -- a claimed row at .6 (T15)
	foam: Theme.Foam,
	tile: Frame,
	rank: TextLabel,
	picture: Frame?,
	squishy: SquishyImage.SquishyImage?,
	pictureFor: string?,
	column: Frame,
	line1: Frame,
	title: TextLabel,
	progress: TextLabel,
	bar: ProgressBar.ProgressBar,
	content: Frame,
	under: Frame, -- phones: the reward and the chips under the bar
	reward: WellPill.WellPill,
	wins: WellPill.WellPill,
	swap: Button.Button,
	equip: Button.Button,
	slot: Frame,
	pulse: Frame,
	claim: Button.Button,
	go: Button.Button,
	check: Frame,
	kind: RowKind?,
	model: QuestFormat.Card?,
	stateWas: QuestFormat.CardState?,
	mix: number,
	compact: boolean,
}

type TabView = {
	root: TextButton,
	foam: Theme.Foam,
	label: TextLabel,
	badge: CountBadge.CountBadge,
	mix: number,
}

-- Constants

local SCREEN = "quests"
local STAND_TAG = "SD_QuestBoard"
local FIELD = "quests"
local TOP_WINS_FIELD = "topWins" -- Batch 3
local CLAIM_REMOTE = "QuestClaim"
local SWAP_REMOTE = "QuestSwap"
local MODAL_GUI = "SD_Modal"
local TOUCH = Config.UI.Touch
local WINDOW_KIND = "quests" -- UI FINAL R3: its Config.UI.Sticker.window kind (H:350-381)
local SCROLLBAR_PX = Theme.SCROLLBAR_PX -- UI FINAL R3: the design's 12 px bar (H:22)
local TICK_SECONDS = 1 -- the reset pill counts down once a second while the screen is open
local REASON_NOT_READY = "data.notReady"
local REASON_ALREADY_CLAIMED = "quest.alreadyClaimed"
local EQUIPPED_TOAST = "inspect.equippedToast"
local NOTICE_COMPLETE = "quest.complete" -- UI FINAL R9: the quest pop (args.questId)
local SOUND_CHIME = "ui.toast" -- UI FINAL R9 (H:739): the pop's chime
local CLAIMED: QuestFormat.CardState = "claimed"
local CLAIMABLE: QuestFormat.CardState = "claim"
-- UI FINAL R8 (Config.UI.Quests, H:350-381, H:742-755).
local QUESTS = Config.UI.Quests
local BODY, TAB, ROW, TEXT = QUESTS.body, QUESTS.tab, QUESTS.row, QUESTS.text
local STAMP = Config.UI.Daily.stamp -- H:41, H:372
local CARD_IN = Config.UI.motion.cardIn -- H:31: sdRise's frames
local CLAIM_FX = Config.UI.Fx.events.questClaim -- H:744-746
local STICKER = Config.UI.Sticker
local ROW_SURFACE = STICKER.surfaces.row -- H:363
local WINDOW_BORDER = STICKER.border.heavy
local WINDOW_LIP = STICKER.lip.window
local UI_PITCH = Config.Audio.uiPitch
local WHITE = Color3.new(1, 1, 1)
local TITLE_KIND: Theme.TextKind = STICKER.text[TEXT.titleRole].kind :: Theme.TextKind
local PROGRESS_KIND: Theme.TextKind = STICKER.text[TEXT.progressRole].kind :: Theme.TextKind
local TAB_KIND: Theme.TextKind = STICKER.text[TAB.textRole].kind :: Theme.TextKind
local RANK_KIND: Theme.TextKind = "H2" -- reading: the Top Wins rank in the tile (no design line)
-- reading: the room the list keeps on its right for the row hover (x +4) and the scroll bar, in the body's padding
local LIST_RIGHT_ROOM = 4 + SCROLLBAR_PX
local MEASURE_MARGIN_PX = 2 -- reading: TextService rounding
local SOUND_CLAIM = "ui.purchase" -- the design's claim (lib:146) by its nearest clip (RL8)
local SOUND_POP = "ui.pop" -- GO (H:957, G2.6); fallback ui.click
local SQUEEZE_WAYPOINT = "squeeze"
local PRACTICE_WAYPOINT = "practice"

-- Module table

local QuestController = {}

-- Private

local log = Log.new("Quests")
local cleanup: Cleanup.Cleanup? = nil
local root: Frame? = nil
local list: ScrollingFrame? = nil
local rows: { RowView } = {}
local tabs: { [string]: TabView } = {}
local resetPill: WellPill.WellPill? = nil
local note: WellPill.WellPill? = nil
local noteBox: Frame? = nil
local closeButton: Button.Button? = nil
local selectedTab: QuestFormat.TabId = "daily"
local compactRows = false
local pending: { [string]: boolean } = {} -- questId (claim / swap) or squishyId (equip) with a request in flight
local lastBoard: QuestFormat.Board? = nil
local waypoint: Waypoint.Handle? = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function currentBoard(): QuestFormat.Board
	return QuestFormat.board(StateController.get(FIELD), {
		owned = StateController.owned(),
		equipped = StateController.equipped(),
		now = serverNow(),
		capsules = StateController.get("capsules"), -- Phase 5: rewards = squeezes × the squeeze value
	})
end

local function centreOf(object: GuiObject): Vector2
	return object.AbsolutePosition + object.AbsoluteSize / 2
end

local function failureToast(result: NetController.Result)
	if result.reason == REASON_ALREADY_CLAIMED then
		UIController.toast(Strings.reasonText(REASON_ALREADY_CLAIMED), "info")
		return
	end
	UIController.toast(NotifyFormat.resultText(result :: any), "warn")
end

local function setButton(button: Button.Button, visible: boolean, busy: boolean, lock: string?)
	button.root.Visible = visible
	if not visible then
		return
	end
	if busy then
		button:setState("loading")
	elseif lock then
		button:setState("disabled", lock)
	else
		button:setState("normal")
	end
end

-- The panel's scale on screen: the UI scale times UIController's open pop (SD_OpenScale).
local function panelScale(panel: GuiObject): number
	local pop = panel:FindFirstChild("SD_OpenScale")
	local openScale = if pop and pop:IsA("UIScale") then pop.Scale else 1
	return UIController.scale() * openScale
end

-- A design face's colours (top -> bottom under its inset highlight) at hover filter `mix` (Button.hoverColor, H:637).
local function faceColors(top: Color3, bottom: Color3, highlightAlpha: number, mix: number): Theme.FoamColors
	local function lit(color: Color3): Color3
		return if mix > 0 then color:Lerp(Button.hoverColor(color), mix) else color
	end
	return {
		face = lit(top),
		faceEnd = lit(bottom),
		top = lit(top:Lerp(WHITE, highlightAlpha)),
		drop = Theme.Colors.inkUI,
	}
end

local function paintTab(id: string, tab: TabView)
	local on = id == selectedTab
	tab.foam:paint(
		faceColors(
			if on then Palette.StickerMintTop else Palette.StickerCardTop,
			if on then Palette.StickerMintEnd else Palette.StickerCardBottom,
			TAB.inset.alpha,
			tab.mix
		),
		"exact"
	)
end

local function paintRow(view: RowView)
	view.foam:paint(
		faceColors(Palette.StickerCardTop, Palette.StickerCardBottom, ROW_SURFACE.highlightAlpha, view.mix),
		"exact"
	)
end

-- The tile's picture (QuestFormat.iconFor, as the HUD tracker's): the squishy a quest names, else its category's;
-- `key` = an image key (the Top Wins rows' duel picture); nil = none.
local function setPicture(view: RowView, squishy: string?, key: string?)
	local want = squishy or key
	if want == view.pictureFor then
		return
	end
	view.pictureFor = want
	local old = view.squishy
	if old then
		old:destroy()
		view.squishy = nil
	end
	local picture = view.picture
	if picture then
		picture:Destroy()
		view.picture = nil
	end
	local size = QUESTS.icon.px
	if squishy then
		local made = SquishyImage.new(squishy, { size = size, owned = true })
		made.root.AnchorPoint = Vector2.new(0.5, 0.5)
		made.root.Position = UDim2.fromScale(0.5, 0.5)
		made.root.Parent = view.tile
		view.squishy = made
	elseif key then
		local holder = IconGlyph.image(key, { name = "Picture", sizePx = size, parent = view.tile })
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		view.picture = holder
	end
end

-- Measures the title in its column (at most TEXT.titleLines lines, "x / y" beside it) and the line's height.
local function fitTitle(view: RowView)
	local frame = root
	if frame == nil then
		return
	end
	local s = panelScale(frame)
	if not (s > 0) then
		return
	end
	local progressShown = view.progress.Visible
	local progressWidth = if progressShown
		then math.ceil(Theme.textWidth(view.progress.Text, PROGRESS_KIND)) + MEASURE_MARGIN_PX
		else 0
	view.progress.Size = UDim2.fromOffset(progressWidth, math.ceil(Theme.lineHeight(PROGRESS_KIND)))
	local columnWidth = view.column.AbsoluteSize.X / s
	local wrap = math.max(1, columnWidth - progressWidth - (if progressShown then TEXT.titleGap else 0))
	local lineHeight = Theme.lineHeight(TITLE_KIND)
	local height = math.min(Theme.textBounds(view.title.Text, TITLE_KIND, nil, wrap).Y, TEXT.titleLines * lineHeight)
	view.title.Size = UDim2.fromOffset(math.floor(wrap), math.ceil(height))
	local lineSize = UDim2.new(1, 0, 0, math.ceil(math.max(height, Theme.lineHeight(PROGRESS_KIND))))
	if view.line1.Size ~= lineSize then
		view.line1.Size = lineSize
	end
end

-- Phones (plan R8): the reward and the chips go under the bar; the row grows by ROW.compactExtra.
local function placeExtras(view: RowView, compact: boolean)
	if view.compact == compact then
		return
	end
	view.compact = compact
	local parent = if compact then view.under else view.content
	for _, part in { view.reward.root, view.wins.root, view.swap.root, view.equip.root } :: { GuiObject } do
		part.Parent = parent
	end
	view.under.Visible = compact
	view.root.Size = UDim2.new(1, -LIST_RIGHT_ROOM, 0, ROW.face + ROW.lip + (if compact then ROW.compactExtra else 0))
end

local function stamp(view: RowView, delayMs: number?)
	MotionTrack.play(view.check, STAMP.frames :: any, STAMP.ms, delayMs or 0, STAMP.curve)
end

local function applyCard(view: RowView, card: QuestFormat.Card, lock: string?)
	local previous = view.model
	view.kind = "quest"
	view.model = card
	view.root.Name = "Quest_" .. card.id
	view.root.Visible = true
	local icon = QuestFormat.iconFor(card)
	setPicture(view, icon.squishy, icon.image)
	view.rank.Visible = false
	view.title.Text = card.title
	view.progress.Text = card.progressText
	view.progress.Visible = true
	view.bar.root.Visible = true
	-- The bar eases when the same quest moves on; a row reused for another quest jumps to its value.
	view.bar:set(card.fraction, previous ~= nil and previous.id == card.id)
	view.bar:setAccent(if QuestFormat.barGold(card) then "yellow" else "blueBar") -- H:956
	local ready = card.state == CLAIMABLE
	local claimed = card.state == CLAIMED
	view.foam:setStroke(if ready then Palette.StickerCoinText else Palette.StickerInk, ROW.border) -- H:363
	view.group.GroupTransparency = if claimed then 1 - ROW.claimedAlpha else 0 -- T15
	view.reward.root.Visible = true
	view.reward:setText(Format.coins(card.reward))
	view.wins.root.Visible = false
	local busy = pending[card.id] == true
	setButton(view.claim, ready, busy, lock)
	view.pulse.Visible = ready
	setButton(view.go, card.state == "inProgress" and QuestFormat.goRoute(card) ~= nil, false, nil)
	setButton(view.swap, card.canSwap, busy, lock)
	local equipId = card.equipSquishy
	setButton(view.equip, equipId ~= nil, equipId ~= nil and pending[equipId] == true, lock)
	view.check.Visible = claimed
	if
		claimed
		and view.stateWas == CLAIMABLE
		and previous
		and previous.id == card.id
		and UIController.isOpen(SCREEN)
	then
		stamp(view)
	end
	view.stateWas = card.state
	fitTitle(view)
end

-- PR26: a Top Wins entry (the rank, the name, the wins) or the player's own line (`you`) in the quest row's look.
local function applyWins(view: RowView, entry: QuestFormat.WinsRow?, you: string?)
	view.kind = if entry then "wins" else "you"
	view.model = nil
	view.stateWas = nil
	view.root.Name = if entry then "TopWins_" .. entry.rank else "TopWins_You"
	view.root.Visible = true
	view.rank.Visible = entry ~= nil
	view.rank.Text = if entry then tostring(entry.rank) else ""
	setPicture(view, nil, if entry then nil else "img.nav.duel")
	view.title.Text = if entry then entry.name else you or ""
	view.progress.Visible = false
	view.bar.root.Visible = false
	view.foam:setStroke(Palette.StickerInk, ROW.border)
	view.group.GroupTransparency = 0
	view.reward.root.Visible = false
	view.wins.root.Visible = entry ~= nil
	if entry then
		view.wins:setText(Format.coins(entry.wins))
	end
	for _, button in { view.claim, view.go, view.swap, view.equip } do
		button.root.Visible = false
	end
	view.pulse.Visible = false
	view.check.Visible = false
	fitTitle(view)
end

-- Forward declaration: rows are made on demand by `refresh`.
local newRow: (index: number) -> RowView

local function rowAt(index: number): RowView
	return rows[index] or newRow(index)
end

local function refreshTimes(board: QuestFormat.Board)
	local pill = resetPill
	if pill then
		pill:setText(board.reset)
		pill.root.Visible = selectedTab == "daily"
	end
	local box, label = noteBox, note
	if selectedTab == "daily" and box and label then
		box.Visible = board.empty ~= nil
		label:setText(board.empty or "")
	end
end

local function refresh()
	if root == nil then
		return
	end
	local board = currentBoard()
	lastBoard = board
	local lock = if StateController.isProfileReady() then nil else Strings.reasonText(REASON_NOT_READY)
	-- The tabs (H:358): a tab that goes (Starter, all claimed) hands the view back to Daily.
	local shown: { [string]: QuestFormat.Tab } = {}
	for index, tab in QuestFormat.tabs(board) do
		shown[tab.id] = tab
		local view = tabs[tab.id]
		if view then
			view.root.LayoutOrder = index
			view.badge:setCount(tab.count)
		end
	end
	if shown[selectedTab] == nil then
		selectedTab = "daily"
	end
	for id, view in tabs do
		view.root.Visible = shown[id] ~= nil
		paintTab(id, view)
	end
	local used = 0
	local noteText: string? = nil
	if selectedTab == "topWins" then
		local model = QuestFormat.topWins(StateController.get(TOP_WINS_FIELD))
		for _, entry in model.rows do
			used += 1
			applyWins(rowAt(used), entry, nil)
		end
		if model.you then
			used += 1
			applyWins(rowAt(used), nil, model.you)
		end
		noteText = model.note
	else
		local cards: { QuestFormat.Card } = if selectedTab == "starter" then board.starter else board.daily
		for _, card in cards do
			used += 1
			applyCard(rowAt(used), card, lock)
		end
		noteText = if selectedTab == "daily" then board.empty else nil
	end
	for i = used + 1, #rows do
		rows[i].root.Visible = false
		rows[i].model = nil
		rows[i].kind = nil
	end
	local box, label = noteBox, note
	if box and label then
		box.Visible = noteText ~= nil
		label:setText(noteText or "")
	end
	refreshTimes(board)
end

-- The visible rows rise in, i x 60 ms apart (H:363), their claimed checks stamping in with them.
local function playRise()
	local index = 0
	for _, view in rows do
		if view.root.Visible then
			local delay = index * ROW.rise.stepMs
			MotionTrack.play(view.rise, CARD_IN.frames :: any, ROW.rise.ms, delay, ROW.rise.curve)
			if view.check.Visible then
				stamp(view, delay)
			end
			index += 1
		end
	end
end

local function selectTab(id: QuestFormat.TabId)
	if id == selectedTab then
		return
	end
	selectedTab = id
	refresh()
	local scroll = list
	if scroll then
		scroll.CanvasPosition = Vector2.zero
	end
	playRise()
end

local function claim(view: RowView)
	local card = view.model
	if card == nil or card.state ~= CLAIMABLE or pending[card.id] or not StateController.isProfileReady() then
		return
	end
	local id, reward = card.id, card.reward
	-- The flight starts where the button is now: the reply's StateDelta may hide it before the reply returns.
	local from = centreOf(view.claim.root)
	pending[id] = true
	refresh()
	local result = NetController.invokeAsync(CLAIM_REMOTE, id)
	pending[id] = nil
	if result.ok then
		SoundController.play(SOUND_CLAIM) -- H:743
		-- UI FINAL R8 (H:744): the design's burst and ring where CLAIM was (once per claim, after the server's yes).
		if from then
			UiFx.sparks(from, { n = CLAIM_FX.sparks.n, spread = CLAIM_FX.sparks.spread })
			for _, ring in CLAIM_FX.rings do
				UiFx.ring(from, UiFx.colors({ ring.color })[1], ring.size)
			end
		end
		if reward > 0 then
			HudController.flyCoins(from, reward, CLAIM_FX.coins)
			UIController.toast(
				Strings.format(Strings.common.coinsGain, { coins = Format.coins(reward) }),
				"success",
				{ sound = false } -- one sound per action: the claim's
			)
		end
	else
		failureToast(result)
	end
	refresh()
end

local function swap(view: RowView)
	local card = view.model
	if card == nil or not card.canSwap or pending[card.id] or not StateController.isProfileReady() then
		return
	end
	local id = card.id
	pending[id] = true
	refresh()
	local result = NetController.invokeAsync(SWAP_REMOTE, id)
	pending[id] = nil
	if not result.ok then
		failureToast(result)
	end
	refresh()
end

local function equip(view: RowView)
	local card = view.model
	local id = if card then card.equipSquishy else nil
	if id == nil or pending[id] or not StateController.isProfileReady() then
		return
	end
	pending[id] = true
	refresh()
	local result = NetController.equipSquishyAsync(id)
	pending[id] = nil
	if result.ok then
		NotifyController.show(EQUIPPED_TOAST, nil, "success")
	else
		failureToast(result)
	end
	refresh()
end

local function clearWaypoint()
	if waypoint then
		waypoint:destroy()
		waypoint = nil
	end
end

-- GO's waypoint (as BoxController's earn waypoint and the queue's practice one), gone after goWaypointSeconds.
local function showWaypoint(name: string)
	clearWaypoint()
	local target = WorldLayout.waypoint(name)
	if target == nil then
		return
	end
	local handle = Waypoint.show(target)
	waypoint = handle
	task.delay(QUESTS.goWaypointSeconds, function()
		if waypoint == handle then
			clearWaypoint()
		end
	end)
end

-- UD2 (H:748-755, H:957): the pop sound, the window closes (ui.back, H:684), then the route after 240 ms.
-- AFFECTED 2026-10-15: the duel route will join the picker's mode and the squeeze spots move into the pens.
local function go(view: RowView)
	local card = view.model
	local route = if card then QuestFormat.goRoute(card) else nil
	if route == nil then
		return
	end
	if not SoundController.play(SOUND_POP) then
		SoundController.play("ui.click")
	end
	UIController.close(SCREEN, "button")
	task.delay(QUESTS.goDelayMs / 1000, function()
		if route == "duel" then
			QueueController.joinAsync()
		elseif route == "squeeze" then
			showWaypoint(SQUEEZE_WAYPOINT)
			-- UI FINAL R9: the design's squeeze picture on the toast (H:750).
			UIController.toast(
				QuestFormat.goToast(ControlsController.preferredInput().Name),
				"info",
				{ icon = "img.icon.squeeze" }
			)
		else
			showWaypoint(PRACTICE_WAYPOINT)
		end
	end)
end

-- Builders -----------------------------------------------------------------------------------------------------------

-- A clear holder filling its parent, centred (a pose turns and scales about its middle).
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

-- A design chip (H:402, PR26: Swap cyan, Equip green), 52 px hit box.
local function chip(
	name: string,
	text: string,
	accent: Theme.AccentName?,
	order: number,
	parent: Instance,
	fn: () -> ()
)
	return Button.new({
		name = name,
		text = text,
		size = "chip",
		accent = accent,
		layoutOrder = order,
		parent = parent,
		onActivated = fn,
	})
end

newRow = function(index: number): RowView
	local c = cleanup :: Cleanup.Cleanup
	local scroll = list :: ScrollingFrame
	local rowRoot: TextButton = Create("TextButton", {
		Name = "Quest",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = false,
		Size = UDim2.new(1, -LIST_RIGHT_ROOM, 0, ROW.face + ROW.lip),
		LayoutOrder = index,
		Visible = false,
		Parent = scroll,
	})
	local visual = holder("SD_Visual", rowRoot)
	local rise = holder("SD_Rise", visual)
	local group: CanvasGroup = Create("CanvasGroup", {
		Name = "Fade",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = rise,
	})
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = group,
	})
	local bands = Layout.stickerBands(ROW.border, ROW_SURFACE.highlightPx, 0, ROW.lip)
	local foam = Theme.foam(face, {
		radius = ROW.radius,
		stroke = ROW.border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
	})
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -ROW.lip),
		Active = false,
		Parent = face,
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, ROW.border + ROW.padLeft),
		PaddingRight = UDim.new(0, ROW.border + ROW.padRight),
		PaddingTop = UDim.new(0, ROW.border),
		PaddingBottom = UDim.new(0, ROW.border),
		Parent = content,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		ROW.gap,
		content,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	-- H:364: the icon tile (70, border 4, radius 18, #EFE6FF) with the picture 58, or the rank (Top Wins).
	local iconSpec = QUESTS.icon
	local tile: Frame = Create("Frame", {
		Name = "Tile",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(iconSpec.tile, iconSpec.tile),
		LayoutOrder = 1,
		Parent = content,
	})
	Theme.foam(tile, {
		radius = iconSpec.radius,
		stroke = iconSpec.border,
		inner = true,
		colors = { face = Palette.StickerToyTile },
	})
	local rank = Theme.label({
		Name = "Rank",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromScale(1, 1),
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = tile,
	}, RANK_KIND)
	Theme.textOnLight(rank) -- the ink on the light tile
	-- H:365-367: the text column: the title with "x / y" pushed right, then the bar.
	local columnFrame: Frame = Create("Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = content,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = columnFrame })
	Theme.list(
		Enum.FillDirection.Vertical,
		TEXT.gap,
		columnFrame,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	local line1: Frame = Create("Frame", {
		Name = "Line1",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, math.ceil(Theme.lineHeight(TITLE_KIND))),
		LayoutOrder = 1,
		Parent = columnFrame,
	})
	local title = Theme.label({
		Name = "Title",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = line1,
	}, TITLE_KIND)
	Theme.stickerText(title, TEXT.titleRole)
	title.TextWrapped = true
	local progress = Theme.label({
		Name = "Progress",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = line1,
	}, PROGRESS_KIND)
	Theme.stickerText(progress, TEXT.progressRole)
	local bar = ProgressBar.new({ name = "Bar", variant = "quest", layoutOrder = 2, parent = columnFrame })
	c:add(bar)
	-- Phones: the reward and the chips under the bar (placeExtras).
	local under: Frame = Create("Frame", {
		Name = "Under",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, QUESTS.reward.height),
		LayoutOrder = 3,
		Visible = false,
		Parent = columnFrame,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		ROW.gap,
		under,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	-- H:369: the reward pill (the coin and the amount); the Top Wins pill shows the duel picture and the wins.
	local reward =
		WellPill.new({ name = "Reward", look = QUESTS.reward, icon = "img.coin", layoutOrder = 3, parent = content })
	c:add(reward)
	local wins =
		WellPill.new({ name = "Wins", look = QUESTS.reward, icon = "img.nav.duel", layoutOrder = 3, parent = content })
	wins.root.Visible = false
	c:add(wins)
	local view: RowView
	local swapButton = chip("Quests_SwapButton", Strings.quest.swap, "cyan", 4, content, function()
		swap(view)
	end)
	c:add(swapButton)
	local equipButton = chip("Quests_EquipButton", Strings.common.equip, nil, 5, content, function()
		equip(view)
	end)
	c:add(equipButton)
	-- H:370-372: the 126 px slot: CLAIM (pulsing) / GO / the claimed check.
	local buttonSpec = QUESTS.button
	local slot: Frame = Create("Frame", {
		Name = "Slot",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(buttonSpec.width, buttonSpec.face + buttonSpec.lip),
		LayoutOrder = 6,
		Parent = content,
	})
	local pulse = holder("SD_Pulse", slot)
	pulse.Visible = false
	local claimButton = Button.new({
		name = "Quests_ClaimButton",
		text = Strings.common.claim,
		kind = "primary",
		width = buttonSpec.width,
		height = buttonSpec.face,
		radius = buttonSpec.radius,
		textRole = buttonSpec.textRole,
		clickSound = false, -- the claim plays its own (H:743)
		parent = pulse,
		onActivated = function()
			claim(view)
		end,
	})
	claimButton.root.AnchorPoint = Vector2.new(0.5, 0.5)
	claimButton.root.Position = UDim2.fromScale(0.5, 0.5)
	c:add(claimButton)
	UiIdle.add(pulse, "pulse", { periodS = buttonSpec.pulseS })
	local goButton = Button.new({
		name = "Quests_GoButton",
		text = Strings.quest.go,
		kind = "secondary",
		width = buttonSpec.width,
		height = buttonSpec.face,
		radius = buttonSpec.radius,
		textRole = buttonSpec.textRole,
		clickSound = false, -- GO plays the pop (H:957)
		parent = slot,
		onActivated = function()
			go(view)
		end,
	})
	goButton.root.AnchorPoint = Vector2.new(0.5, 0.5)
	goButton.root.Position = UDim2.fromScale(0.5, 0.5)
	c:add(goButton)
	local check: Frame = Create("Frame", {
		Name = "Check",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(QUESTS.checkPx, QUESTS.checkPx),
		Rotation = STAMP.restRot,
		Visible = false,
		Parent = slot,
	})
	local checkImage = IconGlyph.image("img.icon.check", { name = "Icon", sizePx = QUESTS.checkPx, parent = check })
	checkImage.AnchorPoint = Vector2.new(0.5, 0.5)
	checkImage.Position = UDim2.fromScale(0.5, 0.5)
	view = {
		root = rowRoot,
		rise = rise,
		group = group,
		foam = foam,
		tile = tile,
		rank = rank,
		picture = nil,
		squishy = nil,
		pictureFor = nil,
		column = columnFrame,
		line1 = line1,
		title = title,
		progress = progress,
		bar = bar,
		content = content,
		under = under,
		reward = reward,
		wins = wins,
		swap = swapButton,
		equip = equipButton,
		slot = slot,
		pulse = pulse,
		claim = claimButton,
		go = goButton,
		check = check,
		kind = nil,
		model = nil,
		stateWas = nil,
		mix = 0,
		compact = false,
	}
	paintRow(view)
	-- H:361 data-fx row: the row hover (x +4) and its brightness on SD_Visual; a row has no click of its own.
	local feel: Button.DecorateOptions = {
		fx = "row",
		visual = visual,
		clickSound = false,
		pivotPx = ROW.lip / 2,
		onFilter = function(mix: number)
			view.mix = mix
			paintRow(view)
		end,
	}
	c:add(Button.decorate(rowRoot, feel))
	c:add(columnFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		fitTitle(view)
	end))
	placeExtras(view, compactRows)
	rows[index] = view
	return view
end

-- A tab (H:358): 46 + lip 4 in a 52 px hit box (PR1), padding 22, its width from its label.
local function newTab(parent: Instance, id: QuestFormat.TabId, text: string): TabView
	local c = cleanup :: Cleanup.Cleanup
	local width = math.ceil(Theme.textWidth(text, TAB_KIND)) + MEASURE_MARGIN_PX + 2 * (TAB.border + TAB.padX)
	local tabRoot: TextButton = Create("TextButton", {
		Name = "Quests_Tab" .. string.upper(string.sub(id, 1, 1)) .. string.sub(id, 2) .. "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, math.max(TAB.face + TAB.lip, TOUCH.minTarget)),
		Parent = parent,
	})
	local visual: Frame = Create("Frame", {
		Name = "SD_Visual",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, TAB.face + TAB.lip),
		Active = false,
		Parent = tabRoot,
	})
	local bands = Layout.stickerBands(TAB.border, TAB.inset.px, 0, TAB.lip)
	local foam = Theme.foam(visual, {
		radius = TAB.radius,
		stroke = TAB.border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
	})
	local label = Theme.label({
		Name = "Label",
		Text = text,
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, TAB.face / 2),
		Size = UDim2.new(1, 0, 0, math.ceil(Theme.lineHeight(TAB_KIND))),
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = visual,
	}, TAB_KIND)
	Theme.stickerText(label, TAB.textRole)
	local badge = CountBadge.new({ name = "Badge", small = true, parent = visual })
	badge.root.AnchorPoint = Vector2.new(1, 0)
	badge.root.Position = UDim2.new(1, -TAB.badgeRight, 0, TAB.badgeTop) -- H:358: right -10, top -12
	UiIdle.add(badge.root, "badge", { periodS = TAB.badgeS })
	c:add(badge)
	local view: TabView = { root = tabRoot, foam = foam, label = label, badge = badge, mix = 0 }
	local feel: Button.DecorateOptions = {
		fx = "tab",
		visual = visual,
		clickSound = false, -- the tab sound below (H:959)
		pivotPx = TAB.lip / 2,
		onFilter = function(mix: number)
			view.mix = mix
			paintTab(id, view)
		end,
	}
	c:add(Button.decorate(tabRoot, feel))
	c:add(tabRoot.Activated:Connect(function()
		SoundController.play("ui.click", { pitch = UI_PITCH.tab })
		selectTab(id)
	end))
	tabs[id] = view
	return view
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local fit = Layout.windowFit(gui.AbsoluteSize, WINDOW_KIND)
	local panel = Theme.window({
		Name = "Quests",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(fit.width, fit.height + WINDOW_LIP),
		Parent = parent,
	}, WINDOW_KIND, BODY.padTop)
	c:add(panel)
	-- UI FINAL R8 (H:357): the body's padding 18 26 24 inside the window's border (fitWindow sets the top).
	local pad = panel:FindFirstChildOfClass("UIPadding") :: UIPadding
	pad.PaddingLeft = UDim.new(0, WINDOW_BORDER + BODY.padX)
	pad.PaddingRight = UDim.new(0, WINDOW_BORDER + BODY.padX)
	pad.PaddingBottom = UDim.new(0, WINDOW_BORDER + BODY.padBottom + WINDOW_LIP)
	-- UI FINAL R3: the band (H:353-354) on the window's top (it sets the top padding).
	Theme.headerTab(panel, Strings.quest.panelTitle)
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = panel,
	})

	local close = Button.new({
		name = "Quests_CloseButton",
		text = Strings.common.close,
		kind = "close", -- UI overhaul: the chunky red X
		parent = panel,
		sound = false, -- a Close button plays ui.back through UIController.close (§18.6)
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	Theme.attachClose(panel, close.root) -- UI FINAL R3: the 76 px X in the band (H:379)
	close.root.Modal = true -- frees the cursor in shift lock / first person
	c:add(close)
	closeButton = close

	-- H:358-359: the tab row and the reset pill pushed right.
	local row: Frame = Create("Frame", {
		Name = "TabRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, math.max(TAB.face + TAB.lip, TOUCH.minTarget)),
		Parent = content,
	})
	local tabList: Frame = Create("Frame", {
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = row,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		BODY.tabGap,
		tabList,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Center
	)
	table.clear(tabs)
	newTab(tabList, "daily", Strings.quest.section.daily)
	newTab(tabList, "starter", Strings.quest.section.starter)
	newTab(tabList, "topWins", Strings.board.title)
	local reset = WellPill.new({ name = "Reset", look = QUESTS.reset, icon = "img.icon.clock", parent = row })
	reset.root.AnchorPoint = Vector2.new(1, 0.5)
	reset.root.Position = UDim2.new(1, 0, 0, TAB.face / 2)
	c:add(reset)
	resetPill = reset

	-- H:361: the rows, scrolling with the design bar (H:22) when there are more than the body holds (Top Wins).
	local scroll: ScrollingFrame = Theme.scrollbar(Create("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	}))
	list = scroll
	Theme.list(
		Enum.FillDirection.Vertical,
		Layout.lipGap(ROW.rowsGap, ROW.lip),
		scroll,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	-- PR23: the note (loading, the board's states, the empty day) as the design's well pill, centred.
	local box: Frame = Create("Frame", {
		Name = "NoteBox",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -LIST_RIGHT_ROOM, 0, Config.UI.Daily.timer.height),
		LayoutOrder = 1000,
		Visible = false,
		Parent = scroll,
	})
	local pill = WellPill.new({ name = "Note", look = Config.UI.Daily.timer, icon = "img.icon.clock", parent = box })
	pill.root.AnchorPoint = Vector2.new(0.5, 0)
	pill.root.Position = UDim2.fromScale(0.5, 0)
	c:add(pill)
	note, noteBox = pill, box
	table.clear(rows)

	-- The window at its fitted design size; the rows' look on phones.
	local function fitBody()
		local screen = gui.AbsoluteSize
		if not (panelScale(panel) > 0) or screen.X <= 0 or screen.Y <= 0 then
			return
		end
		local fitted = Layout.windowFit(screen, WINDOW_KIND)
		local chrome = Theme.fitWindow(panel, fitted.k)
		local size = UDim2.fromOffset(fitted.width, fitted.height + WINDOW_LIP)
		if panel.Size ~= size then
			panel.Size = size
		end
		local position = UDim2.new(0.5, 0, 0.5, fitted.shift)
		if panel.Position ~= position then
			panel.Position = position
		end
		local width = fitted.width - 2 * (WINDOW_BORDER + BODY.padX)
		local height = fitted.height - chrome.top - (WINDOW_BORDER + BODY.padBottom)
		local top = TAB.face + BODY.gap -- H:356: the tab row (46) and the gap
		scroll.Position = UDim2.fromOffset(0, top)
		scroll.Size = UDim2.fromOffset(width + LIST_RIGHT_ROOM, math.max(TOUCH.minTarget, height - top))
		local compact = fitted.class == "compact"
		if compact ~= compactRows then
			compactRows = compact
			for _, view in rows do
				placeExtras(view, compact)
			end
		end
		for _, view in rows do
			if view.root.Visible then
				fitTitle(view)
			end
		end
	end
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBody))
	c:add(UIController.LayoutChanged:connect(function()
		fitBody()
	end))
	root = panel
	refresh()
	fitBody()
	return panel
end

-- Public -------------------------------------------------------------------------------------------------------------

function QuestController.open(): boolean
	return UIController.open(SCREEN)
end

-- Small table for Studio debug hooks.
function QuestController.debugState(): { [string]: any }
	local board = lastBoard or currentBoard()
	local function summary(cards: { QuestFormat.Card }): { { [string]: any } }
		local out = {}
		for _, card in cards do
			table.insert(out, {
				id = card.id,
				state = card.state,
				progress = card.progressText,
				canSwap = card.canSwap,
				equip = card.equipSquishy,
			})
		end
		return out
	end
	local busy = {}
	for id in pending do
		table.insert(busy, id)
	end
	table.sort(busy)
	return {
		open = UIController.isOpen(SCREEN),
		built = root ~= nil,
		tab = selectedTab,
		daily = summary(board.daily),
		starter = if board.starterVisible then summary(board.starter) else {},
		swapsLeft = board.swapsLeft,
		pending = busy,
		standRegistered = WorldBinder.isStandRegistered(STAND_TAG),
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function QuestController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(UIController.registerScreen(SCREEN, {
		build = build,
		onOpen = function()
			refresh()
			playRise()
		end,
		primary = function(): GuiObject?
			for _, view in rows do
				if view.root.Visible and view.claim.root.Visible then
					return view.claim.root
				end
			end
			local tab = tabs[selectedTab]
			if tab then
				return tab.root
			end
			return if closeButton then closeButton.root else nil
		end,
		-- L1 / R1 step through the shown tabs.
		onTab = function(direction: number)
			local board = lastBoard or currentBoard()
			local shown = QuestFormat.tabs(board)
			for index, tab in shown do
				if tab.id == selectedTab then
					local nextTab = shown[(index - 1 + direction) % #shown + 1]
					SoundController.play("ui.click", { pitch = UI_PITCH.tab })
					selectTab(nextTab.id)
					return
				end
			end
		end,
	}))
	c:add(WorldBinder.registerStand(STAND_TAG, function()
		UIController.open(SCREEN)
	end))
	-- UI FINAL R9 (G9.2, G9.3): the quest pop in the tracker's slot; false keeps the toast.
	c:add(NotifyController.present(NOTICE_COMPLETE, function(_code: string, args: any): boolean
		local id = if type(args) == "table" then args.questId else nil
		local title = if type(id) == "string" then QuestFormat.namer(StateController.get(FIELD))(id) else nil
		local tracker = HudController.element("tracker")
		local gui = if tracker then tracker:FindFirstAncestorWhichIsA("ScreenGui") else nil
		if title == nil or tracker == nil or not tracker.Visible or gui == nil or not gui.Enabled then
			return false
		end
		QuestPop.show({
			anchor = tracker,
			title = title,
			onChime = function()
				SoundController.play(SOUND_CHIME)
			end,
		})
		return true
	end))
	c:add(QuestPop.stop)
	for _, field in { FIELD, "owned", "equipped", "dataStatus", "capsules", TOP_WINS_FIELD } do
		c:add(StateController.changed(field):connect(refresh))
	end
	c:add(StateController.LobbyLockChanged:connect(function(locked: boolean)
		if locked then
			clearWaypoint() -- a match started: GO's waypoint goes
		end
	end))
	c:add(clearWaypoint)
	c:add(function()
		table.clear(pending)
		table.clear(rows)
		table.clear(tabs)
		root, list, resetPill, note, noteBox, closeButton = nil, nil, nil, nil, nil, nil
		lastBoard = nil
		selectedTab = "daily"
		compactRows = false
	end)
end

function QuestController.start()
	local c = cleanup
	if c == nil then
		return
	end
	c:add(task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			if root and UIController.isOpen(SCREEN) then
				local ok, err = pcall(function(): any
					refreshTimes(currentBoard())
					return nil
				end)
				if not ok then
					log:error("quest reset tick failed:", err)
				end
			end
		end
	end))
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function QuestController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return QuestController
