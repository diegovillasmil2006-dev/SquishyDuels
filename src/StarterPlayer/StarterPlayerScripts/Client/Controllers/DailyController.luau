--!strict
-- DailyController (client only). DESIGN §6.9 (daily rewards), §11.6 (Daily screen), §7.6 / §7.7 (the daily stand and
-- its sign), §11.3 (states), §11.4 (focus), §18.5.2 B2 (coin flights). The server decides every claim
-- (DailyRewardService); this module only shows the state and sends DailyClaim. Looks: UI/DailyFormat (pure).
-- * The "daily" modal (registered in init, so the HUD's Daily button and the SD_DailyStand prompt come alive, §7.6):
--   7 day cards (Day n, its Coins (Phase 5: its squeezes × the `capsules` field's squeeze value, refreshed when the
--   capsules change), "Treat Box" on day 7; today highlighted with "Today"; claimed days with a
--   check drawn from shapes plus "Claimed"), the welcome back line after a missed day (daily.welcomeBack), the Claim
--   button (Daily_ClaimButton), then "Come back in {time}" once today is claimed (refreshed every second while open).
--   Locked states (§11.3): a profile that is not ready -> disabled with reason.data.notReady; a pending save -> disabled
--   with reason.box.saving (§3.11: daily claims are blocked while a save is pending; reading, planner note 3).
-- * Claim -> NetController.invokeAsync("DailyClaim") (one at a time; the button shows its spinner). On ok: the Coins fly
--   from the button into the pill (HudController.flyCoins, only for amounts >= coinFlight.minAmount) and
--   common.coinsGain is toasted; the welcome back line is gone once today is claimed (nothing is waiting any more). A
--   failure toasts its reason ({time} filled with the countdown, e.g. daily.alreadyClaimed "Claimed! Come back in
--   {time}."). The day-7 Treat Box reveal is NOT opened here: BoxController plays it from StateDelta.unseenReveals
--   (planner note 6).
-- * "Daily reward ready" (daily.popup): one toast per session, the first time a full state arrives (or at start) with
--   a ready profile whose reward is claimable (§6.9 "appears once on join"); back after a missed day it reads
--   daily.welcomeBack ("Welcome back! Day 4 is waiting.") instead. Reading: not during a duel (it waits for the next
--   full state then).
-- * The daily stand (§7.6, §7.7): WorldBinder.registerStand("SD_DailyStand") opens the screen. The sign's live line
--   (the TextLabel named "Status" in the stand's station model, built empty) shows daily.ready / daily.wait {time},
--   rewritten every second while the stand is streamed in; it is emptied while the state is unknown (a profile that
--   did not load). The gift box's slow spin belongs to the feel pass (AmbientController spinBob), not to this module.
-- Times are server times (workspace:GetServerTimeNow(), §6.9: the client clock is never used).
-- Part 8 (layout pass, §11.2; the maths is pure in UI/DailyFormat and unit-tested at 667×375, 1280×720, 1920×1080 and
-- the largest text): the day cards and the welcome back line scroll in a body (DailyFormat.bodyHeight, the panel within
-- MAX_HEIGHT_SHARE of the screen) with Daily_ClaimButton and the countdown pinned under it; the cards grow with the
-- player's text size (DailyFormat.cardWidth: 84 -> 122 base px at the largest) and wrap onto a second line when
-- they do not fit; the panel's width follows the screen. Before, at 667×375 with the largest text, "Claimed" did not
-- fit its 84 px card and the panel with the reset sentence ran off the screen.
-- Foam UI restyle (spec 2026-10-09; behaviour, names and timings unchanged): a foam panel with the title in a header
-- tab (the Daily tile's Sky blue) and Close straddling the top-right corner (the panel moves down by half of what hangs
-- above it, as in Quests). The day cards are foam cards of one height (the tallest card's content): "Day n" in the
-- display font, the coin, the Coins; their face and outline come from DailyFormat.cardLook (today Sky blue with the
-- thick outline, the Treat Box day Lilac, claimed days Biscuit), always with their words. The welcome back line sits in
-- an inset field; the countdown carries the clock icon.
-- Foam fix batch (2026-10-09): the tab reads daily.panelTitle "Daily Reward" in title case like every other screen's
-- tab (daily.title "DAILY REWARD" stays the world sign's); the body's list is top-aligned (a centred list taller than
-- its scrolling body was centred on it, its top out of reach).
-- Foam fix round 2 (2026-10-09): day 7 reads daily.treatBox "Treat Box" (was "Free Treat Box", which wrapped onto a
-- third line on the 84 px card; every card takes the tallest card's height, so days 2-6 had about 40 px of empty room).
-- UI overhaul (2026-10-11, Candy UI): a collectible reward track. DailyFormat.cardLook's faces map to the candy
-- surfaces (CARD_FACES: a future day the raised plum, today Cyan with a white frame, a claimed day the recess with a
-- Mint check, the Treat Box day 7 Gold with a gift beside its coin, the payoff); the texts follow their face
-- (CARD_ACCENTS: outlined white on Cyan, PlumInk on Gold, light on the dark faces). The track is wider (PANEL_WIDTH,
-- CARD_WIDTH) and still wraps onto a second row when it does not fit (DailyFormat.cardsPerRow). Claim is a Gold CTA;
-- Close is the red X.
-- Public: open(), debugState().

-- Services

local CollectionService = game:GetService("CollectionService")
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
local CoinIcon = require(Client.UI.Components.CoinIcon)
local Create = require(Client.UI.Create)
local DailyFormat = require(Client.UI.DailyFormat)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local Layout = require(Client.UI.Layout)
local NotifyFormat = require(Client.UI.NotifyFormat)
local Theme = require(Client.UI.Theme)
local UiFx = require(Client.UI.UiFx)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

type CardView = {
	frame: Frame,
	stroke: UIStroke,
	list: UIListLayout,
	padding: UIPadding,
	today: TextLabel,
	coins: TextLabel, -- Phase 5: the day's Coins follow the squeeze value
	claimedRow: Frame,
	texts: { TextLabel }, -- UI overhaul: every text on the card (painted for its face)
	gift: Frame?, -- the Treat Box day's gift icon
}

-- Constants

local SCREEN = "daily"
local STAND_TAG = "SD_DailyStand"
local STATUS_LABEL = "Status" -- the sign's live line (WorldLayout.Signs dailySign, built empty)
local REMOTE = "DailyClaim"
local FIELD = "daily"
local MODAL_GUI = "SD_Modal"
local TOUCH = Config.UI.Touch
local PANEL_WIDTH = 760 -- UI overhaul: 680 -> 760, the wider cards still fit one row on a PC
local MARGIN_PX = 24
local CARD_WIDTH = 92 -- UI overhaul: 84 -> 92
local CARD_TEXT_KIND = "Small" -- the cards' text (their width grows with it)
local CHECK_PX = 18
local CHECK_BAR_PX = 3
local SCROLLBAR_PX = 6
local BODY_PAD_PX = 3 -- around the cards in the scrolling body: room for today's thick outline
-- Foam UI (readings: DESIGN gives no numbers): Close sits CLOSE_INSET from the panel's right edge; the day card's coin
-- and the countdown's clock in base px.
local CLOSE_INSET = 16
local CARD_COIN_PX = 22
local CLOCK_ICON_PX = 24
-- DailyFormat.cardLook's face names -> the candy surfaces (UI overhaul): a future day raised off the window, today
-- Cyan, the Treat Box day Gold ("lilac" names that day's face in DailyFormat), a claimed day recessed.
local CARD_FACES: { [string]: Color3 } = {
	frosting = Theme.Colors.panelAlt,
	sky = Theme.Accents.sky.face,
	lilac = Theme.Accents.gold.face,
	biscuit = Theme.Colors.biscuit,
}
-- The accent whose text rule a face's texts follow (nil: a dark face, light text).
local CARD_ACCENTS: { [string]: Theme.AccentName } = { sky = "sky", lilac = "gold" }
local TODAY_FRAME_PX = 4 -- today's white frame
local GIFT_ICON_PX = 26
local CLAIM_WIDTH = 240 -- the Claim CTA's width (base px)
local MAX_HEIGHT_SHARE = 0.86 -- the panel never covers more than this share of the screen height (as Quests)
local TICK_SECONDS = 1 -- the countdown and the sign line change once a second
local REASON_NOT_READY = "data.notReady"
local REASON_SAVING = "box.saving" -- §3.11 "Saving your collection…" (reading: DESIGN has no daily code for it)
local REASON_ALREADY_CLAIMED = "daily.alreadyClaimed"
local SUCCESS_KIND: UIController.ToastKind = "success"
local WARN_KIND: UIController.ToastKind = "warn"
local INFO_KIND: UIController.ToastKind = "info"

-- Module table

local DailyController = {}

-- Private

local log = Log.new("Daily")
local cleanup: Cleanup.Cleanup? = nil
local root: Frame? = nil
local body: ScrollingFrame? = nil
local bodyLayout: UIListLayout? = nil
local headerTab: Frame? = nil
local cards: { CardView } = {}
local resetLabel: TextLabel? = nil
local resetBox: Frame? = nil -- the inset field around the welcome back line (foam UI)
local countdownLabel: TextLabel? = nil
local countdownRow: Frame? = nil -- the clock and the countdown (foam UI)
local claimButton: Button.Button? = nil
local closeButton: Button.Button? = nil
local claiming = false
local popupShown = false
local started = false
local lastSignText: string? = nil

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function dailyState(): any
	return StateController.get(FIELD)
end

local function savePending(): boolean
	local status = StateController.dataStatus()
	return status ~= nil and status.savePending == true
end

local function currentModel(): DailyFormat.Model
	return DailyFormat.model(dailyState(), serverNow(), StateController.get("capsules"))
end

-- Why the Claim button is disabled now, or nil.
local function lockReason(): string?
	if not StateController.isProfileReady() then
		return Strings.reasonText(REASON_NOT_READY)
	elseif savePending() then
		return Strings.reasonText(REASON_SAVING)
	end
	return nil
end

local function refresh()
	local frame = root
	if frame == nil then
		return
	end
	local model = currentModel()
	for i, view in cards do
		local card = model.cards[i]
		if card then
			view.coins.Text = card.coinsText
			view.today.Visible = card.today and card.todayText ~= nil
			view.today.Text = card.todayText or ""
			view.claimedRow.Visible = card.claimed
			-- Foam UI: the face (the foam bands follow it) and the outline from DailyFormat.cardLook; UI overhaul: today's
			-- frame is white and the texts follow the face.
			local look = DailyFormat.cardLook(card)
			view.stroke.Color = if look.thick then Theme.Colors.white else Theme.Colors.inkUI
			view.stroke.Thickness = if look.thick then TODAY_FRAME_PX else Theme.Stroke.ink
			view.frame.BackgroundColor3 = CARD_FACES[look.face] or Theme.Colors.panelAlt
			local accent = CARD_ACCENTS[look.face]
			for _, text in view.texts do
				if accent then
					Theme.textOnAccent(text, accent)
				else
					Theme.textOnLight(text, Theme.Colors.text)
				end
			end
			local gift = view.gift
			if gift then
				gift.Visible = card.treat
			end
		end
	end
	local reset = resetLabel
	if reset then
		reset.Visible = model.welcomeBack
		reset.Text = model.welcomeText or ""
	end
	if resetBox then
		resetBox.Visible = model.welcomeBack
	end
	local countdown = countdownLabel
	if countdown then
		countdown.Visible = model.countdownText ~= nil
		countdown.Text = model.countdownText or ""
	end
	if countdownRow then
		countdownRow.Visible = model.countdownText ~= nil
	end
	local button = claimButton
	if button then
		button.root.Visible = model.known and model.canClaim or not model.known
		if claiming then
			button:setState("loading")
		else
			local reason = if model.known then lockReason() else Strings.reasonText(REASON_NOT_READY)
			button:setState(if reason then "disabled" else "normal", reason)
		end
	end
end

-- The panel's scale on screen: the UI scale times UIController's open pop (SD_OpenScale), so a measure taken while the
-- panel pops in still reads in base px.
local function panelScale(panel: GuiObject): number
	local pop = panel:FindFirstChild("SD_OpenScale")
	local openScale = if pop and pop:IsA("UIScale") then pop.Scale else 1
	return UIController.scale() * openScale
end

-- Part 8: the panel's width (follows the screen), the cards' width (follows the text size) and the body's height
-- (DailyFormat.bodyHeight: the panel stays within MAX_HEIGHT_SHARE of the screen; the rest scrolls). Foam UI: every
-- card is as tall as the tallest card's content (one even row of foam cards), and the panel moves down by half of what
-- hangs above it (the header tab, Close), which counts in the chrome.
local function fitBody()
	local frame, scroll, list, tab = root, body, bodyLayout, headerTab
	if frame == nil or scroll == nil or list == nil or tab == nil then
		return
	end
	local gui = UIController.screenGui(MODAL_GUI)
	local scale = UIController.scale()
	local s = panelScale(frame)
	local screen = gui.AbsoluteSize
	if not (scale > 0) or not (s > 0) or screen.X <= 0 or screen.Y <= 0 then
		return
	end
	local width = math.min(PANEL_WIDTH, Layout.modalWidth(screen.X, scale, MARGIN_PX))
	local size = UDim2.fromOffset(if width > 0 then math.floor(width) else PANEL_WIDTH, 0)
	if frame.Size ~= size then
		frame.Size = size
	end
	local textScale = Theme.textSize(CARD_TEXT_KIND) / Config.UI.TextSize[CARD_TEXT_KIND]
	local cardWidth = DailyFormat.cardWidth(CARD_WIDTH, textScale)
	local tallest = 0
	for _, view in cards do
		local pad = view.padding
		local natural = view.list.AbsoluteContentSize.Y / s + pad.PaddingTop.Offset + pad.PaddingBottom.Offset
		tallest = math.max(tallest, math.ceil(natural))
	end
	local cardSize = UDim2.fromOffset(cardWidth, tallest)
	for _, view in cards do
		if view.frame.Size ~= cardSize then
			view.frame.Size = cardSize
		end
	end
	local above = math.max(tab.AbsoluteSize.Y / s, TOUCH.closeButton) / 2
	local position = UDim2.new(0.5, 0, 0.5, math.floor(above / 2 + 0.5))
	if frame.Position ~= position then
		frame.Position = position
	end
	local current = scroll.AbsoluteSize.Y / s
	local chrome = frame.AbsoluteSize.Y / s - current + above
	local height = math.ceil(
		DailyFormat.bodyHeight(
			screen.Y / scale,
			list.AbsoluteContentSize.Y / s + 2 * BODY_PAD_PX,
			chrome,
			MAX_HEIGHT_SHARE,
			TOUCH.minTarget
		)
	)
	if math.abs(height - current) >= 1 then
		scroll.Size = UDim2.new(1, 0, 0, height)
	end
end

-- The failed Result's text with {time} filled in (daily.alreadyClaimed "Come back in {time}").
local function failureText(result: NetController.Result): string
	return Strings.format(NotifyFormat.resultText(result :: any), { time = DailyFormat.countdownText(serverNow()) })
end

local function claim()
	if claiming or lockReason() ~= nil then
		refresh()
		return
	end
	local button = claimButton
	-- The flight starts where the button is now: the reply's StateDelta may hide it before the reply returns.
	local from: Vector2? = if button then button.root.AbsolutePosition + button.root.AbsoluteSize / 2 else nil
	-- UI overhaul: today's card (its view, for the burst) and whether it is the Treat Box day (the larger payoff).
	local todayView: CardView? = nil
	local treatDay = false
	for i, card in currentModel().cards do
		if card.today then
			todayView = cards[i]
			treatDay = card.treat
		end
	end
	claiming = true
	refresh()
	local result = NetController.invokeAsync(REMOTE)
	claiming = false
	if result.ok then
		-- UI overhaul: the reward burst on today's card (Gold; large for the Treat Box day), after the server's yes.
		local target: GuiObject? = if todayView then todayView.frame else nil
		if target then
			UiFx.burst(target, if treatDay then "large" else "medium", Theme.Colors.gold)
			UiFx.punch(target, 1.12)
		elseif from then
			UiFx.burst(from, "medium", Theme.Colors.gold)
		end
		local data = if type(result.data) == "table" then result.data else {}
		local coins = if type(data.coins) == "number" then math.floor(data.coins) else 0
		if coins > 0 then
			if from then
				HudController.flyCoins(from, coins)
			end
			UIController.toast(Strings.format(Strings.common.coinsGain, { coins = Format.coins(coins) }), SUCCESS_KIND)
		end
	else
		-- "Claimed! Come back in {time}." is information (another device or a late tap), not an error.
		UIController.toast(
			failureText(result),
			if result.reason == REASON_ALREADY_CLAIMED then INFO_KIND else WARN_KIND
		)
	end
	refresh()
end

-- One toast per session: the first full state (or the start) with a ready, claimable reward (§6.9).
local function maybePopup()
	if popupShown or not started or not StateController.isProfileReady() or StateController.isLobbyLocked() then
		return
	end
	local model = currentModel()
	if model.canClaim then
		popupShown = true
		UIController.toast(model.welcomeText or Strings.daily.popup, INFO_KIND)
	end
end

-- The sign's live line of every streamed-in daily stand (§7.7).
local function statusLabelOf(stand: Instance): TextLabel?
	local model = stand:FindFirstAncestorOfClass("Model") or stand.Parent
	if model == nil then
		return nil
	end
	local label = model:FindFirstChild(STATUS_LABEL, true)
	return if label and label:IsA("TextLabel") then label else nil
end

local function updateSigns()
	local text = DailyFormat.signText(if StateController.isProfileReady() then dailyState() else nil, serverNow()) or ""
	lastSignText = text
	for _, stand in CollectionService:GetTagged(STAND_TAG) do
		local label = statusLabelOf(stand)
		if label and label.Text ~= text then
			label.Text = text
		end
	end
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
		BackgroundColor3 = Theme.Accents.mint.face, -- UI overhaul: the success colour on the recessed card
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

-- A day card: a foam card (fitBody gives every card the tallest content's height; refresh paints its look).
local function buildCard(parent: Instance, card: DailyFormat.DayCard): CardView
	local c = cleanup :: Cleanup.Cleanup
	local frame = Theme.panel({
		Name = "Day" .. card.day,
		Size = UDim2.fromOffset(CARD_WIDTH, 0),
		LayoutOrder = card.day,
		Parent = parent,
	}, Theme.Radius.button, Theme.Padding.small)
	local list =
		Theme.list(Enum.FillDirection.Vertical, 2, frame, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	local dayLabel = Theme.label({
		Name = "Label",
		Text = card.label,
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, "Chip")
	c:add(CoinIcon.new({ name = "Coin", sizePx = CARD_COIN_PX, layoutOrder = 2, parent = frame }))
	local coinsLabel = Theme.label({
		Name = "Coins",
		Text = card.coinsText,
		LayoutOrder = 3,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, "Small")
	-- UI overhaul: the Treat Box day shows its gift beside the coin (the payoff).
	local gift: Frame? = nil
	if card.treat then
		local glyph = IconGlyph.new({ name = "Gift", icon = "boxes", sizePx = GIFT_ICON_PX, layoutOrder = 4, parent = frame })
		c:add(glyph)
		gift = glyph.root
	end
	local treatLabel = Theme.label({
		Name = "Treat",
		Text = card.treatText or "",
		Visible = card.treat,
		LayoutOrder = 5,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, "Small", Enum.FontWeight.Bold)
	local today = Theme.label({
		Name = "Today",
		Text = "",
		Visible = false,
		LayoutOrder = 6,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, "Chip")
	local claimedRow: Frame = Create("Frame", {
		Name = "Claimed",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 7,
		Parent = frame,
	})
	Theme.list(Enum.FillDirection.Vertical, 0, claimedRow, Enum.HorizontalAlignment.Center)
	checkMark(claimedRow, 1)
	local claimedLabel = Theme.label({
		Name = "Text",
		Text = Strings.common.claimed,
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = claimedRow,
	}, "Small", Enum.FontWeight.Bold)
	return {
		frame = frame,
		stroke = stroke,
		list = list,
		padding = frame:FindFirstChildOfClass("UIPadding") :: UIPadding,
		today = today,
		coins = coinsLabel,
		claimedRow = claimedRow,
		texts = { dayLabel, coinsLabel, treatLabel, today, claimedLabel },
		gift = gift,
	}
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local width = math.min(PANEL_WIDTH, Layout.modalWidth(gui.AbsoluteSize.X, UIController.scale(), MARGIN_PX))
	local panel = Theme.panel({
		Name = "Daily",
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
	local tab = Theme.headerTab(panel, Strings.daily.panelTitle, { accent = "sky" })
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
		name = "Daily_CloseButton",
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

	-- Part 8: the day cards and the welcome back line scroll when the screen is too short (fitBody); Claim and the
	-- countdown stay under them.
	local scroll: ScrollingFrame = Create("ScrollingFrame", {
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
	-- Top-aligned (fix batch): a centred list taller than the window is centred on the window, its top out of reach.
	local scrollList = Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.medium,
		scroll,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Top
	)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, BODY_PAD_PX), -- room for the cards' outlines (today's thick one); the row is centred
		PaddingBottom = UDim.new(0, BODY_PAD_PX),
		PaddingRight = UDim.new(0, SCROLLBAR_PX),
		Parent = scroll,
	})
	local row: Frame = Create("Frame", {
		Name = "Days",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = scroll,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, row).Wraps = true
	table.clear(cards)
	for _, card in DailyFormat.model(nil, serverNow()).cards do
		table.insert(cards, buildCard(row, card))
	end

	-- The welcome back line (after a missed day) in an inset field.
	local box = Theme.inset({
		Name = "ResetBox",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 2,
		Parent = scroll,
	}, Theme.Radius.button, Theme.Padding.medium)
	resetBox = box
	resetLabel = Theme.label({
		Name = "ResetNote",
		Text = "",
		Visible = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = box,
	}, "Body")
	local button = Button.new({
		name = "Daily_ClaimButton",
		text = Strings.common.claim,
		kind = "primary",
		accent = "gold", -- UI overhaul: claiming Coins is the Gold celebration
		width = CLAIM_WIDTH, -- UI overhaul: a wide hero CTA (with its shine)
		height = TOUCH.primaryButton,
		layoutOrder = 4,
		parent = content,
		onActivated = claim,
	})
	c:add(button)
	claimButton = button
	-- "Come back in {time}" with the clock.
	local countdown: Frame = Create("Frame", {
		Name = "CountdownRow",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		LayoutOrder = 5,
		Parent = content,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, countdown)
	c:add(IconGlyph.new({ name = "Clock", icon = "clock", sizePx = CLOCK_ICON_PX, tone = "light", parent = countdown }))
	countdownRow = countdown
	countdownLabel = Theme.label({
		Name = "Countdown",
		Text = "",
		Visible = false,
		LayoutOrder = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = countdown,
	}, "H2")
	root = panel
	headerTab = tab
	body, bodyLayout = scroll, scrollList
	for _, view in cards do
		-- Every card's content height feeds the even row (fitBody).
		c:add(view.list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitBody))
	end
	c:add(scrollList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitBody))
	c:add(panelList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitBody))
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitBody))
	c:add(UIController.LayoutChanged:connect(function()
		fitBody()
	end))
	refresh()
	fitBody()
	return panel
end

-- Public -------------------------------------------------------------------------------------------------------------

function DailyController.open(): boolean
	return UIController.open(SCREEN)
end

-- Small table for Studio debug hooks.
function DailyController.debugState(): { [string]: any }
	local now = serverNow()
	local model = DailyFormat.model(dailyState(), now)
	return {
		open = UIController.isOpen(SCREEN),
		built = root ~= nil,
		today = DailyFormat.today(now),
		canClaim = model.canClaim,
		nextDay = model.nextDay,
		welcomeBack = model.welcomeBack,
		claiming = claiming,
		popupShown = popupShown,
		sign = lastSignText,
		standRegistered = WorldBinder.isStandRegistered(STAND_TAG),
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function DailyController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(UIController.registerScreen(SCREEN, {
		build = build,
		onOpen = function()
			refresh()
		end,
		primary = function(): GuiObject?
			local button = claimButton
			if button and button.root.Visible then
				return button.root
			end
			return if closeButton then closeButton.root else nil
		end,
	}))
	c:add(WorldBinder.registerStand(STAND_TAG, function()
		UIController.open(SCREEN)
	end))
	local function onState()
		refresh()
		updateSigns()
		if StateController.isApplyingFull() then
			maybePopup()
		end
	end
	c:add(StateController.changed(FIELD):connect(onState))
	c:add(StateController.changed("dataStatus"):connect(onState))
	c:add(StateController.changed("capsules"):connect(refresh)) -- Phase 5: the squeeze value sets the Coins
	c:add(function()
		table.clear(cards)
		root, resetLabel, countdownLabel, claimButton, closeButton = nil, nil, nil, nil, nil
		resetBox, countdownRow = nil, nil
		body, bodyLayout, headerTab = nil, nil, nil
		claiming, started = false, false
	end)
end

function DailyController.start()
	local c = cleanup
	if c == nil then
		return
	end
	started = true
	maybePopup()
	c:add(task.spawn(function()
		while true do
			local ok, err = pcall(function(): any
				updateSigns()
				if UIController.isOpen(SCREEN) then
					refresh()
				end
				return nil
			end)
			if not ok then
				log:error("daily tick failed:", err)
			end
			task.wait(TICK_SECONDS)
		end
	end))
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function DailyController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return DailyController
