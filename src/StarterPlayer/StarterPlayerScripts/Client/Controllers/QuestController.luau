--!strict
-- QuestController (client only). DESIGN §6.8 (quests and starter tasks), §11.6 (Quests screen), §11.3 (states), §11.4
-- (focus), §7.6 (the quest board stand), §18.5.2 B2 (coin flights). The server owns progress, claims and swaps
-- (QuestService); this module shows the `quests` state and sends QuestClaim / QuestSwap / EquipSquishy. Looks:
-- UI/QuestFormat (pure).
-- * The "quests" modal (registered in init, so the HUD's Quests button and the SD_QuestBoard prompt come alive, §7.6):
--   a Daily section (one card per quest of the day, or "No quests right now. Check back in {time}.") and a Starter
--   section (the starter tasks, hidden once all are claimed), then the footer "New quests in {h}h {m}m" (refreshed
--   every second while open). A card (Quest_<questId>): the quest line, a progress bar with "3/5", the reward
--   "+1,500 Coins" (Phase 5: its squeezes × the `capsules` field's squeeze value), its state (In progress; Claim = the primary Quests_ClaimButton; Claimed = a check drawn from shapes +
--   "Claimed"), Quests_SwapButton on unfinished daily quests while the day's free swap is left, and the
--   Quests_EquipButton shortcut when the quest's squishy is owned but not equipped.
-- * Claim -> NetController.invokeAsync("QuestClaim", questId): on ok the reward flies from the button into the pill
--   (HudController.flyCoins, only for amounts >= coinFlight.minAmount) and "+{coins} Coins" is toasted (§6.8); a
--   replay answered quest.alreadyClaimed is an info toast; any other failure toasts its reason. Swap ->
--   QuestSwap(questId); Equip -> EquipSquishy(squishyId) with the Squishies screen's toasts. One request per card at a
--   time (its button shows the spinner). Locked state (§11.3): a profile that is not ready disables the buttons with
--   reason.data.notReady.
-- * Completion and rollover toasts (quest.complete, quest.autoCollected) are server Notify codes: NotifyController shows
--   them.
-- Times are server times (workspace:GetServerTimeNow()).
-- Part 8 (layout pass, §11.2): the sections scroll in a body sized by QuestFormat.bodyHeight from the measured header,
-- footer, gaps and paddings (the panel within MAX_HEIGHT_SHARE of the screen at every text size), and the panel's
-- width follows the screen. Every button is a Button touch target; the gamepad primary is the first Claim, else Close.
-- Foam UI restyle (spec 2026-10-09; behaviour, names and timings unchanged): a foam panel with the title in a header
-- tab (the Quests tile's accent) and Close straddling the top-right corner (both hang half above the panel; the panel
-- is moved down by half of that so the whole stays centred and within MAX_HEIGHT_SHARE). Section headers carry their
-- tile icon (IconGlyph). A card is a foam card: the quest line, a ProgressBar (Mint) with "3/5" beside it, then the
-- reward as a Biscuit chip with the coin, the state (InkUI check + "Claimed", or "In progress" in Ink2) and the
-- buttons; a claimed card turns Biscuit. The footer sits in an inset pill with the clock icon.
-- Foam fix batch (2026-10-09): the tab reads quest.panelTitle "Quests" in title case like every other screen's tab
-- (quest.title "QUESTS" stays the world board's sign); the sections' list is top-aligned in its scrolling body (a
-- centred list taller than the body was centred on it: on a phone the first card's top was out of reach).
-- Foam fix round 2 (2026-10-09; Swap sat mid-row and the bars ended unevenly): a card's Actions row holds the reward
-- and the state on the left ("Info") and Claim / Swap / Equip at its right end ("Buttons", Theme.Padding.medium apart;
-- UIListLayout.HorizontalFlex SpaceBetween; they wrap under the left part when both do not fit); every count beside a
-- bar is as wide as the widest the board shows (digits measured as 8), so the bars end at one edge.
-- Batch 3 (friends, review #10; user decision Q3 B): a "Top Wins This Week" section under the quests (the Duel CTA's
-- swords icon): QuestFormat.topWins of the topWins state (ShowOffService's weekly board, refreshed by the server about
-- once a minute): the top 5 as "1. Ana · 12 wins", a note before the first read, while the board cannot be read or for
-- an empty week, and the player's own line (place and wins). Text only, from the existing label kinds; no new art. On
-- touch the body keeps its scroll bar on screen (UI/Components/ScrollHint, like Settings), so the section under the
-- quests can be found on a phone.
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
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local Chip = require(Client.UI.Components.Chip)
local CoinIcon = require(Client.UI.Components.CoinIcon)
local Create = require(Client.UI.Create)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local ProgressBar = require(Client.UI.Components.ProgressBar)
local ScrollHint = require(Client.UI.Components.ScrollHint) -- Batch 3
local Layout = require(Client.UI.Layout)
local NotifyFormat = require(Client.UI.NotifyFormat)
local QuestFormat = require(Client.UI.QuestFormat)
local QueueFormat = require(Client.UI.QueueFormat)
local Theme = require(Client.UI.Theme)
local UiFx = require(Client.UI.UiFx)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

type CardView = {
	frame: Frame,
	title: TextLabel,
	bar: ProgressBar.ProgressBar,
	progress: TextLabel,
	reward: Chip.Chip,
	stateRow: Frame,
	stateLabel: TextLabel,
	check: Frame,
	claim: Button.Button,
	swap: Button.Button,
	equip: Button.Button,
	model: QuestFormat.Card?,
}

type Section = {
	header: Frame,
	list: Frame,
	views: { CardView },
}

-- Batch 3: the Top Wins section's rows: the ranked lines (made on demand), the note and the player's own line.
type TopWinsRows = { section: Section, lines: { TextLabel }, note: TextLabel, you: TextLabel }

-- Constants

local SCREEN = "quests"
local STAND_TAG = "SD_QuestBoard"
local FIELD = "quests"
local TOP_WINS_FIELD = "topWins" -- Batch 3
local CLAIM_REMOTE = "QuestClaim"
local SWAP_REMOTE = "QuestSwap"
local MODAL_GUI = "SD_Modal"
local TOUCH = Config.UI.Touch
local PANEL_WIDTH = 600
local MARGIN_PX = 24
local SCROLLBAR_PX = 6
local MAX_HEIGHT_SHARE = 0.86 -- the panel never covers more than this share of the screen height (as Settings)
local CHECK_PX = 18
-- Foam UI (readings: DESIGN gives no numbers): the body's inner padding keeps the cards' 2.5 px outline inside its
-- clip; Close sits CLOSE_INSET from the panel's right edge; icons and the reward coin in base px.
local BODY_PAD_PX = 3
local CLOSE_INSET = 16
local SECTION_ICON_PX = 26
local FOOTER_ICON_PX = 20
local REWARD_COIN_PX = 18
local PROGRESS_GAP = 8 -- between the bar and its "3/5"
local PROGRESS_SLACK_PX = 2 -- added to the measured "3/5" (TextService rounding)
local CHECK_BAR_PX = 3
local TICK_SECONDS = 1 -- the footer counts down once a second while the screen is open
local REASON_NOT_READY = "data.notReady"
local REASON_ALREADY_CLAIMED = "quest.alreadyClaimed"
local EQUIPPED_TOAST = "inspect.equippedToast"
local CLAIMED: QuestFormat.CardState = "claimed"
local CLAIMABLE: QuestFormat.CardState = "claim"

-- Module table

local QuestController = {}

-- Private

local log = Log.new("Quests")
local cleanup: Cleanup.Cleanup? = nil
local root: Frame? = nil
local dailySection: Section? = nil
local starterSection: Section? = nil
local topWins: TopWinsRows? = nil -- Batch 3
local emptyLabel: TextLabel? = nil
local footerLabel: TextLabel? = nil
local closeButton: Button.Button? = nil
local pending: { [string]: boolean } = {} -- questId (claim / swap) or squishyId (equip) with a request in flight
local lastBoard: QuestFormat.Board? = nil

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

local function applyCard(view: CardView, card: QuestFormat.Card?, lock: string?, progressWidth: number)
	local previous = view.model
	view.model = card
	view.frame.Visible = card ~= nil
	if card == nil then
		return
	end
	view.frame.Name = "Quest_" .. card.id
	view.title.Text = card.title
	-- The bar eases when the same quest moves on; a card reused for another quest jumps to its value.
	local sameQuest = previous ~= nil and previous.id == card.id
	view.bar:set(card.fraction, sameQuest)
	view.progress.Text = card.progressText
	-- "3/5" beside the bar: the bar takes the rest of the row. Fix round 2: every card's count is as wide as the widest
	-- (progressWidthOf), so the bars end at one edge ("4/60", "0/1" and "0/12" ended them at three).
	view.bar.root.Size = UDim2.new(1, -(progressWidth + PROGRESS_GAP), 0, ProgressBar.HEIGHT_PX)
	view.progress.Size = UDim2.fromOffset(progressWidth, 0)
	view.reward:setText(card.rewardText)
	local claimed = card.state == CLAIMED
	view.stateRow.Visible = card.state ~= CLAIMABLE
	view.stateLabel.Text = card.stateText
	-- UI overhaul (Candy UI): light text on the dark cards; "Claimed" in Mint beside its check.
	Theme.textOnLight(view.stateLabel, if claimed then Theme.Accents.mint.face else Theme.Colors.ink2)
	view.check.Visible = claimed
	-- A claimed card is recessed (the dark recess; the foam bands follow the face); an open one is raised off the window.
	view.frame.BackgroundColor3 = if claimed then Theme.Colors.biscuit else Theme.Colors.panelAlt
	local busy = pending[card.id] == true
	setButton(view.claim, card.state == CLAIMABLE, busy, lock)
	setButton(view.swap, card.canSwap, busy, lock)
	local equipId = card.equipSquishy
	setButton(view.equip, equipId ~= nil, equipId ~= nil and pending[equipId] == true, lock)
end

local function refreshTimes(board: QuestFormat.Board)
	if footerLabel then
		footerLabel.Text = board.footer
	end
	local empty = emptyLabel
	if empty then
		empty.Visible = board.empty ~= nil
		empty.Text = board.empty or ""
	end
end

-- Forward declaration: cards are made on demand by `refresh` and their buttons call back into it.
local newCard: (section: Section, index: number) -> CardView

local function fillSection(section: Section, cards: { QuestFormat.Card }, lock: string?, progressWidth: number)
	for i, card in cards do
		local view = section.views[i] or newCard(section, i)
		applyCard(view, card, lock, progressWidth)
	end
	for i = #cards + 1, #section.views do
		applyCard(section.views[i], nil, lock, progressWidth)
	end
end

-- The width of the counts beside the bars (fix round 2): the widest count the board shows, every digit measured as a
-- wide one (QueueFormat.measureSample), so the bars of all cards end at one edge and a count that ticks never moves them
-- (Chip kind: measured without yielding).
local function progressWidthOf(board: QuestFormat.Board): number
	local widest = 0
	for _, cards in { board.daily, if board.starterVisible then board.starter else {} } do
		for _, card in cards do
			widest = math.max(widest, Theme.textWidth(QueueFormat.measureSample(card.progressText), "Chip"))
		end
	end
	return math.ceil(widest) + PROGRESS_SLACK_PX
end

-- Batch 3: the Top Wins section from the topWins state.
local function refreshTopWins()
	local rows = topWins
	if rows == nil then
		return
	end
	local model = QuestFormat.topWins(StateController.get(TOP_WINS_FIELD))
	for i, text in model.lines do
		local label = rows.lines[i]
			or Theme.label({
				Name = "Line" .. i,
				LayoutOrder = i,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = rows.section.list,
			}, "Body")
		rows.lines[i] = label
		label.Text = text
		label.Visible = true
	end
	for i = #model.lines + 1, #rows.lines do
		rows.lines[i].Visible = false
	end
	rows.note.Text = model.note or ""
	rows.note.Visible = model.note ~= nil
	rows.you.Text = model.you or ""
	rows.you.Visible = model.you ~= nil
end

local function refresh()
	if root == nil then
		return
	end
	local board = currentBoard()
	lastBoard = board
	local lock = if StateController.isProfileReady() then nil else Strings.reasonText(REASON_NOT_READY)
	local daily, starter = dailySection, starterSection
	local progressWidth = progressWidthOf(board)
	if daily then
		fillSection(daily, board.daily, lock, progressWidth)
	end
	if starter then
		starter.header.Visible = board.starterVisible
		starter.list.Visible = board.starterVisible
		fillSection(starter, if board.starterVisible then board.starter else {}, lock, progressWidth)
	end
	refreshTimes(board)
	refreshTopWins()
end

local function claim(view: CardView)
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
		-- UI overhaul: a compact Mint burst where the Claim was (once per claim, after the server's yes).
		if from then
			UiFx.burst(from, "small", Theme.Accents.quests.face)
		end
		if reward > 0 then
			HudController.flyCoins(from, reward)
			UIController.toast(Strings.format(Strings.common.coinsGain, { coins = Format.coins(reward) }), "success")
		end
	else
		failureToast(result)
	end
	refresh()
end

local function swap(view: CardView)
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

local function equip(view: CardView)
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

-- Builders -----------------------------------------------------------------------------------------------------------

-- A check mark drawn from two bars (§11.2: no image ids exist, so icons are shapes).
local function checkMark(parent: Instance, order: number): Frame
	local holder: Frame = Create("Frame", {
		Name = "Check",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CHECK_PX, CHECK_PX),
		LayoutOrder = order,
		Parent = parent,
	})
	Create("Frame", {
		Name = "Short",
		BackgroundColor3 = Theme.Accents.mint.face, -- UI overhaul: the success colour on the dark card
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.3, 0.62),
		Size = UDim2.fromOffset(CHECK_PX * 0.45, CHECK_BAR_PX),
		Rotation = 45,
		Parent = holder,
	})
	Create("Frame", {
		Name = "Long",
		BackgroundColor3 = Theme.Accents.mint.face,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.62, 0.48),
		Size = UDim2.fromOffset(CHECK_PX * 0.8, CHECK_BAR_PX),
		Rotation = -50,
		Parent = holder,
	})
	return holder
end

newCard = function(section: Section, index: number): CardView
	local c = cleanup :: Cleanup.Cleanup
	local frame = Theme.panel({
		Name = "Quest",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = index,
		Visible = false,
		Parent = section.list,
	}, Theme.Radius.button, Theme.Padding.medium)
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, frame, Enum.HorizontalAlignment.Left)
	local title = Theme.label({
		Name = "Title",
		Text = "",
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}, "Body", Enum.FontWeight.Bold)
	-- The bar and "3/5" beside it (applyCard sizes the bar to the rest of the row).
	local progressRow: Frame = Create("Frame", {
		Name = "ProgressRow",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = frame,
	})
	Theme.list(Enum.FillDirection.Horizontal, PROGRESS_GAP, progressRow, Enum.HorizontalAlignment.Left)
	local bar = ProgressBar.new({ name = "Bar", layoutOrder = 1, parent = progressRow })
	c:add(bar)
	local progress = Theme.label({
		Name = "Progress",
		Text = "",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 0),
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = progressRow,
	}, "Chip")

	local actions: Frame = Create("Frame", {
		Name = "Actions",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = frame,
	})
	-- Fix round 2: the reward and the state on the left, the buttons at the row's right end (SpaceBetween); the buttons
	-- wrap under them when both do not fit (Swap sat mid-row right after "In progress").
	local actionsList =
		Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, actions, Enum.HorizontalAlignment.Left)
	actionsList.Wraps = true
	actionsList.HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween
	local info: Frame = Create("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 1,
		Parent = actions,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, info, Enum.HorizontalAlignment.Left)
	local buttons: Frame = Create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		Parent = actions,
	})
	-- Theme.Padding.medium between the bevelled buttons (at 6 they read as one).
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.medium, buttons, Enum.HorizontalAlignment.Right)
	-- The reward: a recessed chip with the coin and the amount in Gold (UI overhaul; the coin colours stay for Coins).
	local reward = Chip.new({ name = "Reward", text = "", layoutOrder = 0, parent = info })
	reward:setColor(Theme.Colors.biscuit, Theme.Colors.gold)
	c:add(reward)
	local coin = CoinIcon.new({ name = "Coin", sizePx = REWARD_COIN_PX, layoutOrder = 1, parent = reward.root })
	c:add(coin)
	local stateRow: Frame = Create("Frame", {
		Name = "State",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, TOUCH.minTarget),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
		Parent = info,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, stateRow, Enum.HorizontalAlignment.Left)
	local check = checkMark(stateRow, 1)
	local stateLabel = Theme.label({
		Name = "Text",
		Text = "",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 2,
		Parent = stateRow,
	}, "Small", Enum.FontWeight.Bold)

	local view: CardView
	local claimButton = Button.new({
		name = "Quests_ClaimButton",
		text = Strings.common.claim,
		kind = "primary",
		accent = "gold", -- UI overhaul: claiming Coins is the Gold celebration (as Daily)
		height = TOUCH.minTarget,
		layoutOrder = 2,
		parent = buttons,
		onActivated = function()
			claim(view)
		end,
	})
	c:add(claimButton)
	local swapButton = Button.new({
		name = "Quests_SwapButton",
		text = Strings.quest.swap,
		textKind = "Chip",
		height = TOUCH.minTarget,
		layoutOrder = 3,
		parent = buttons,
		onActivated = function()
			swap(view)
		end,
	})
	c:add(swapButton)
	local equipButton = Button.new({
		name = "Quests_EquipButton",
		text = Strings.common.equip,
		textKind = "Chip",
		height = TOUCH.minTarget,
		layoutOrder = 4,
		parent = buttons,
		onActivated = function()
			equip(view)
		end,
	})
	c:add(equipButton)
	view = {
		frame = frame,
		title = title,
		bar = bar,
		progress = progress,
		reward = reward,
		stateRow = stateRow,
		stateLabel = stateLabel,
		check = check,
		claim = claimButton,
		swap = swapButton,
		equip = equipButton,
		model = nil,
	}
	section.views[index] = view
	return view
end

-- A section header: its tile icon (IconGlyph, InkUI on the panel) and the section's name.
local function newSection(parent: Instance, name: string, order: number, headerText: string, icon: string): Section
	local c = cleanup :: Cleanup.Cleanup
	local header: Frame = Create("Frame", {
		Name = name .. "Header",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, header, Enum.HorizontalAlignment.Left)
	c:add(IconGlyph.new({ name = "Icon", icon = icon, sizePx = SECTION_ICON_PX, tone = "light", parent = header }))
	Theme.label({
		Name = "Text",
		Text = headerText,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = header,
	}, "H2")
	local list: Frame = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order + 1,
		Parent = parent,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, list, Enum.HorizontalAlignment.Left)
	return { header = header, list = list, views = {} }
end

-- The panel's scale on screen: the UI scale times UIController's open pop (SD_OpenScale), so a measure taken while the
-- panel pops in still reads in base px.
local function panelScale(panel: GuiObject): number
	local pop = panel:FindFirstChild("SD_OpenScale")
	local openScale = if pop and pop:IsA("UIScale") then pop.Scale else 1
	return UIController.scale() * openScale
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local width = math.min(PANEL_WIDTH, Layout.modalWidth(gui.AbsoluteSize.X, UIController.scale(), MARGIN_PX))
	local panel = Theme.panel({
		Name = "Quests",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(if width > 0 then width else PANEL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, Theme.Radius.panel, Theme.Padding.large)
	c:add(panel)
	-- Foam UI: room at the top for Close's lower half, then the header tab (it raises the padding for its own half).
	local pad = panel:FindFirstChildOfClass("UIPadding") :: UIPadding
	pad.PaddingTop = UDim.new(0, math.ceil(TOUCH.closeButton / 2) + Theme.Padding.small)
	local tab = Theme.headerTab(panel, Strings.quest.panelTitle, { accent = "quests" })
	-- The header tab sits on the panel itself, so the rows go in a Content frame with the list.
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = panel,
	})
	local panelList =
		Theme.list(Enum.FillDirection.Vertical, Theme.Padding.medium, content, Enum.HorizontalAlignment.Center)

	local close = Button.new({
		name = "Quests_CloseButton",
		text = Strings.common.close,
		kind = "close", -- UI overhaul: the chunky red X
		height = TOUCH.closeButton,
		parent = panel,
		sound = false, -- a Close button plays ui.back through UIController.close (§18.6)
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	-- Straddles the panel's top edge at the right, like the tab in the middle.
	close.root.AnchorPoint = Vector2.new(1, 0.5)
	close.root.Position = UDim2.new(1, Theme.Padding.large - CLOSE_INSET, 0, -pad.PaddingTop.Offset)
	close.root.ZIndex = tab.ZIndex
	close.root.Modal = true -- frees the cursor in shift lock / first person
	c:add(close)
	closeButton = close

	-- The sections scroll when the screen is too short for them (phones in landscape).
	local body: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR_PX,
		ScrollBarImageColor3 = Theme.Colors.inkUI,
		LayoutOrder = 1,
		Parent = content,
	})
	-- Top-aligned (fix batch): a centred list taller than the window was centred on the window, so on a phone the first
	-- card's top sat above the canvas, out of reach, and the last card's bottom was cut.
	local list = Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.medium,
		body,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, BODY_PAD_PX), -- the cards' outlines stay inside the clip
		PaddingBottom = UDim.new(0, BODY_PAD_PX),
		PaddingLeft = UDim.new(0, BODY_PAD_PX),
		PaddingRight = UDim.new(0, SCROLLBAR_PX + 4),
		Parent = body,
	})
	-- Batch 3 (like Settings): on touch the body's scroll bar stays on screen while the sections are longer than it
	-- (UI/Components/ScrollHint), on the panel over the body's right edge (the body is the first row of Content);
	-- fitBody sizes it. Top Wins sits under the quests, below the fold on a phone.
	local scrollHint = ScrollHint.new({ scroll = body, parent = panel })
	scrollHint.root.AnchorPoint = Vector2.new(1, 0)
	scrollHint.root.Position = UDim2.fromScale(1, 0)
	c:add(scrollHint)
	-- Part 8: the body's height from QuestFormat.bodyHeight with the chrome measured (the tab and Close above the
	-- panel, the paddings, the footer and the gaps at the player's text size), and the panel's width follows the
	-- screen. Foam UI: the panel moves down by half of what hangs above it, so the whole stays centred.
	local function fitBody()
		local scale = UIController.scale()
		local screen = gui.AbsoluteSize
		local s = panelScale(panel)
		if not (scale > 0) or not (s > 0) or screen.X <= 0 or screen.Y <= 0 then
			return
		end
		local fitWidth = math.min(PANEL_WIDTH, Layout.modalWidth(screen.X, scale, MARGIN_PX))
		local panelSize = UDim2.fromOffset(if fitWidth > 0 then math.floor(fitWidth) else PANEL_WIDTH, 0)
		if panel.Size ~= panelSize then
			panel.Size = panelSize
		end
		local above = math.max(tab.AbsoluteSize.Y / s, TOUCH.closeButton) / 2
		local position = UDim2.new(0.5, 0, 0.5, math.floor(above / 2 + 0.5))
		if panel.Position ~= position then
			panel.Position = position
		end
		local current = body.AbsoluteSize.Y / s
		local chrome = panel.AbsoluteSize.Y / s - current + above
		local height = math.ceil(
			QuestFormat.bodyHeight(
				screen.Y / scale,
				list.AbsoluteContentSize.Y / s + 2 * BODY_PAD_PX,
				chrome,
				MAX_HEIGHT_SHARE,
				TOUCH.minTarget
			)
		)
		if math.abs(height - current) >= 1 then
			body.Size = UDim2.new(1, 0, 0, height)
		end
		local railSize = UDim2.fromOffset(SCROLLBAR_PX, body.Size.Y.Offset) -- Batch 3: the ScrollHint rail
		if scrollHint.root.Size ~= railSize then
			scrollHint.root.Size = railSize
		end
	end
	c:add(list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitBody))
	c:add(panelList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitBody))
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBody))
	c:add(UIController.LayoutChanged:connect(function()
		fitBody()
	end))

	dailySection = newSection(body, "Daily", 1, Strings.quest.section.daily, "daily")
	emptyLabel = Theme.label({
		Name = "Empty",
		Text = "",
		Visible = false,
		LayoutOrder = 3,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	}, "Body")
	starterSection = newSection(body, "Starter", 4, Strings.quest.section.starter, "quests")
	-- Batch 3 (review #10): Top Wins This Week, after the quests.
	local winsSection = newSection(body, "TopWins", 6, Strings.board.title, "duel")
	topWins = {
		section = winsSection,
		lines = {},
		note = Theme.label({
			Name = "Note",
			LayoutOrder = 98,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = winsSection.list,
		}, "Small"),
		you = Theme.label({
			Name = "You",
			LayoutOrder = 99,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = winsSection.list,
		}, "Body", Enum.FontWeight.Bold),
	}
	-- The footer: the clock and "New quests in {h}h {m}m" in an inset pill.
	local footer = Theme.inset({
		Name = "FooterPill",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
		Parent = content,
	}, Theme.Radius.pill, Theme.Padding.small)
	local footerPad = footer:FindFirstChildOfClass("UIPadding") :: UIPadding
	footerPad.PaddingLeft = UDim.new(0, Theme.Padding.medium)
	footerPad.PaddingRight = UDim.new(0, Theme.Padding.medium)
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, footer)
	c:add(IconGlyph.new({ name = "Clock", icon = "clock", sizePx = FOOTER_ICON_PX, tone = "light", parent = footer }))
	footerLabel = Theme.label({
		Name = "Footer",
		Text = "",
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = footer,
	}, "Small", Enum.FontWeight.Bold)
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
		local list = {}
		for _, card in cards do
			table.insert(list, {
				id = card.id,
				state = card.state,
				progress = card.progressText,
				canSwap = card.canSwap,
				equip = card.equipSquishy,
			})
		end
		return list
	end
	local busy = {}
	for id in pending do
		table.insert(busy, id)
	end
	table.sort(busy)
	return {
		open = UIController.isOpen(SCREEN),
		built = root ~= nil,
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
		end,
		primary = function(): GuiObject?
			for _, section in { dailySection, starterSection } do
				if section then
					for _, view in section.views do
						if view.frame.Visible and view.claim.root.Visible then
							return view.claim.root
						end
					end
				end
			end
			return if closeButton then closeButton.root else nil
		end,
	}))
	c:add(WorldBinder.registerStand(STAND_TAG, function()
		UIController.open(SCREEN)
	end))
	for _, field in { FIELD, "owned", "equipped", "dataStatus", "capsules", TOP_WINS_FIELD } do
		c:add(StateController.changed(field):connect(refresh))
	end
	c:add(function()
		table.clear(pending)
		root, dailySection, starterSection, emptyLabel, footerLabel, closeButton = nil, nil, nil, nil, nil, nil
		topWins = nil
		lastBoard = nil
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
					log:error("quest footer tick failed:", err)
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
