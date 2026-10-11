--!strict
-- QueueController (client only). DESIGN §5.4, §7.6, §7.7, §11.6 (queue pill), §2.8 (QueueJoin / QueueLeave /
-- ReportIdle / QueueStatus).
-- * Entry points (both send QueueJoin): the duel gate podium prompt and UIController.open("queue") (the HUD "Duel"
--   button and the result panel's "Queue again"; a non-modal screen, refused from Matched through Returning).
-- * Podium prompt (SD_QueuePodium): registered with WorldBinder.registerStand, so the prompt (built disabled) is
--   enabled only while this UI exists (§7.6). It toggles: Idle -> QueueJoin, Searching -> QueueLeave; its ActionText
--   follows the state from the prompt's own baked keys (SD_TextKey "Join 1v1 Queue" / SD_AltTextKey "Leave Queue"),
--   re-checked once a second so a prompt that streams in later gets the live text too. Walking off the pad never
--   cancels (§7.6).
-- * Queue pill (SD_Hud, under the Duel CTA; UI/QueueFormat): "Looking for an opponent… 0:23" + the position or arena
--   line + Cancel (52 px); after 20 s alone (or when QueueStatus says queue.noOpponent) the "No one else is in the queue
--   right now." hint with Keep waiting / Practice (a waypoint to the range; the player stays queued, no teleport) /
--   Cancel. Hidden while Idle and during a match.
-- * Matched: "Opponent found: {name}" for Config.UI.Queue.matchedBannerSeconds (UIController closes the modals); the
--   name comes from the first DuelState (a Studio test dummy is labelled as one, never shown as a player).
-- * Errors and messages: a failed QueueJoin shows its reason ("Couldn't join the queue. Try again." for unknown
--   errors); QueueStatus.messageKey and `queue.*` / `duel.*` Notify codes become toasts (UIController de-duplicates a
--   message reported twice).
-- * Idle: while Searching, LocalPlayer.Idled -> ReportIdle (the server removes the ticket; it still enforces
--   QueueMaxSeconds itself).
-- * Podium board (SD_QueueBoard): its live lines (SD_LiveKey queue.boardWaiting / queue.boardActive) show the counts
--   of the <= 2 Hz QueueStatus broadcast (searching, duels in progress of Config.Duel.Arena.MaxSlots).
-- Never fakes an opponent and never presents a bot as a player (§11.6).
-- Layout (Part 8 layout pass, §11.2, §11.4; rebuilt for the foam HUD, spec 2026-10-09):
-- * Look: a foam card (QueuePill): a clock icon, the title and the detail line beside Cancel (primary), and under them
--   Keep waiting / Practice (secondary) while the no-opponent hint shows; they wrap inside the pill at the largest text.
--   All are Button touch targets (>= Config.UI.Touch.minTarget).
-- * Place: QueueFormat.pillPlacement from HudController.layoutRects() (the Duel CTA, the HUD groups, the coach card
--   and, on touch / phones, the touch areas; base px) and the pill's measured height: right under the Duel CTA at the
--   top middle on every layout (lobby HUD, spec 2026-10-11; the CTA shows the queued state, the pill the details and
--   Cancel; the coach card waits while queued), else its later spots. Re-laid out when SD_Hud, the UI scale, the HUD's
--   layout (HudController.LayoutChanged), the coach card or the pill's own size changes, and on every pill tick while
--   it shows.
-- * Gamepad: Cancel is HudController's "queue" focus target (setFocusTarget), so the Duel CTA reaches it with Down (and
--   Cancel the CTA with Up); the pill's buttons link left / right in order.
-- Overlays fix (2026-10-09):
-- * The pill hugs its contents (QueueFormat.pillWidth: the clock, the wider of the title and the detail line measured
--   from QueueFormat.measureSample, Cancel; the hint's buttons when wider), capped at PILL_WIDE on PCs and PILL_WIDTH
--   on phones (before: always those widths, with about 170 base px of empty pill before Cancel).
-- * The matched banner sits under the duel HUD's top bar once it shows (UIController.banner `below`, followed) and
--   leaves when the countdown starts, so it never covers the bar's lives or the countdown disc.

-- Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local Create = require(Client.UI.Create)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local QueueFormat = require(Client.UI.QueueFormat)
local Theme = require(Client.UI.Theme)
local Waypoint = require(Client.UI.Waypoint)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Constants

local SCREEN_NAME = "queue"
local PODIUM_TAG = "SD_QueuePodium"
local BOARD_TAG = "SD_QueueBoard"
local ATTR_LIVE_KEY = "SD_LiveKey"
local HUD_GUI = "SD_Hud"
local PRACTICE_WAYPOINT = "practice"
local MAX_SLOTS = Config.Duel.Arena.MaxSlots
local MATCHED_SECONDS = Config.UI.Queue.matchedBannerSeconds
local TOUCH = Config.UI.Touch
local PILL_TOP = 12 -- until the first layout pass (QueueFormat.pillPlacement places it)
local PILL_WIDTH = 460 -- phones (QueueFormat's own width)
local PILL_WIDE = 520 -- PCs: the title fits one line beside Cancel
local PILL_PADDING = 12
local PILL_GAP = 8
local ICON_PX = 24
local TICK_SECONDS = 0.25 -- the pill's clock shows whole seconds
local PROMPT_REFRESH_TICKS = 4 -- the podium prompt text is re-checked once a second
local NOTIFY_AREAS = { "queue.", "duel." }
local COACH_FRAME = "Hud_OnboardingCard" -- OnboardingController's coach card (the pill keeps clear of it)
local FOCUS_KEY = "queue" -- HudController.setFocusTarget
-- The duel HUD's top bar (DuelController's stable name) the matched banner sits under, and the duel phases it shows
-- in (from the countdown on, the countdown disc and the top bar take over).
local DUEL_GUI = "SD_DuelHud"
local DUEL_TOP_BAR = "TopBar"
local MATCHED_PHASES: { [string]: boolean } = { Preparing = true, Positioning = true }

-- Module table

local QueueController = {}

-- Private

local log = Log.new("Queue")
local cleanup: Cleanup.Cleanup? = nil
local pill: Frame? = nil
local textsFrame: Frame? = nil
local hintRow: Frame? = nil
local titleLabel: TextLabel? = nil
local detailLabel: TextLabel? = nil
local keepButton: Button.Button? = nil
local practiceButton: Button.Button? = nil
local cancelButton: Button.Button? = nil
local lastPlacement: QueueFormat.PillPlacement? = nil
local aloneSince: number? = nil
local hintDismissedAt: number? = nil
local joining = false
local waypoint: Waypoint.Handle? = nil
local matchedBanner: any = nil
local matchedBannerFor: string? = nil
-- The pill's texts as last measured (overlays fix): the key of their samples and text size, and the wider one's width.
local measuredKey: string? = nil
local measuredText = 0

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function clearWaypoint()
	if waypoint then
		waypoint:destroy()
		waypoint = nil
	end
end

-- Layout (Part 8) ----------------------------------------------------------------------------------------------------

local function setIfChanged(object: any, property: string, value: any)
	if object[property] ~= value then
		object[property] = value
	end
end

-- Gamepad links while the pill shows: the pill's buttons left / right in order; Cancel is HudController's "queue"
-- focus target (the HUD's right column reaches it), cleared while the pill hides.
local function linkGamepad(shown: boolean)
	local cancel = cancelButton
	if cancel == nil then
		return
	end
	HudController.setFocusTarget(FOCUS_KEY, if shown then cancel.root else nil)
	if not shown then
		return
	end
	local order: { GuiObject } = {}
	for _, button in { keepButton, practiceButton, cancelButton } do
		if button and button.root.Visible then
			table.insert(order, button.root)
		end
	end
	for index, object in order do
		setIfChanged(object, "NextSelectionLeft", order[index - 1])
		setIfChanged(object, "NextSelectionRight", order[index + 1])
	end
end

-- Overlays fix: the width (base px) of the wider of the pill's title and detail line, each on one line, measured from
-- QueueFormat.measureSample at the player's text size; measured again only when a sample or the text size changes.
-- (Theme.textWidth may yield the first time it meets a text.)
local function measureTexts(title: string, detail: string?)
	local titleSample = QueueFormat.measureSample(title)
	local detailSample = if detail then QueueFormat.measureSample(detail) else ""
	local key = `{Theme.textSize("Body")}\n{titleSample}\n{detailSample}`
	if key == measuredKey then
		return
	end
	local width = Theme.textWidth(titleSample, "Body", Enum.FontWeight.Bold)
	if detail then
		width = math.max(width, Theme.textWidth(detailSample, "Small"))
	end
	measuredKey, measuredText = key, width
end

-- A button's width in base px without its press feel (Button's UIScale "Scale": hover 1.04, press 0.92). Review fix:
-- read with the feel, hovering or pressing Cancel resized the pill and moved its clock and texts on the next tick.
local function restingWidth(button: Button.Button, scale: number): number
	local feel = button.root:FindFirstChild("Scale")
	local k = if feel and feel:IsA("UIScale") and feel.Scale > 0 then feel.Scale else 1
	return button.root.AbsoluteSize.X / scale / k
end

-- The pill's width (QueueFormat.pillWidth): hugging its texts, Cancel and, while they show, the hint's buttons; at most
-- `cap`. Until the texts are measured, `cap`.
local function hugWidth(scale: number, cap: number): number
	local cancel = cancelButton
	if measuredKey == nil or cancel == nil then
		return cap
	end
	local hint = 0
	local keep, practice = keepButton, practiceButton
	if keep and practice and keep.root.Visible then
		hint = restingWidth(keep, scale) + restingWidth(practice, scale) + Theme.Padding.small
	end
	return QueueFormat.pillWidth({
		padding = PILL_PADDING,
		icon = ICON_PX,
		gap = PILL_GAP,
		text = measuredText,
		cancel = restingWidth(cancel, scale),
		hint = hint,
	}, cap)
end

-- Places the pill clear of the HUD (QueueFormat.pillPlacement from HudController.layoutRects()) at the width hugging
-- its contents, sizes its text column beside Cancel, and links it for the gamepad.
local function layoutPill()
	local frame = pill
	if frame == nil then
		return
	end
	if not frame.Visible then
		linkGamepad(false)
		return
	end
	local scale = UIController.scale()
	if not (scale > 0) then
		return
	end
	local rects = HudController.layoutRects()
	if rects.canvas.X <= 0 or rects.canvas.Y <= 0 then
		return
	end
	local blockers: { QueueFormat.Rect } = {}
	for _, rect in { rects.left, rects.tiles, rects.right, rects.coach } do
		if rect then
			table.insert(blockers, rect)
		end
	end
	for _, rect in rects.reserved do
		table.insert(blockers, rect)
	end
	local measured = frame.AbsoluteSize.Y / scale
	local compact = UIController.layoutClass() == "compact"
	local place = QueueFormat.pillPlacement({
		screen = rects.canvas,
		cta = rects.cta,
		blockers = blockers,
		width = hugWidth(scale, if compact then PILL_WIDTH else PILL_WIDE),
		height = if measured > 0 then measured else nil,
	})
	lastPlacement = place
	setIfChanged(frame, "Position", UDim2.fromOffset(math.floor(place.x + 0.5), math.floor(place.y + 0.5)))
	setIfChanged(frame, "Size", UDim2.fromOffset(math.floor(place.width), 0))
	-- The text column gets what the clock and Cancel leave.
	local texts, cancel = textsFrame, cancelButton
	if texts and cancel then
		local cancelWidth = restingWidth(cancel, scale)
		local width = math.max(60, math.floor(place.width - 2 * PILL_PADDING - ICON_PX - cancelWidth - 2 * PILL_GAP))
		setIfChanged(texts, "Size", UDim2.fromOffset(width, 0))
	end
	linkGamepad(true)
end

local function refreshPill()
	local frame = pill
	if frame == nil then
		return
	end
	local view = StateController.queue()
	local now = serverNow()
	aloneSince = QueueFormat.nextAloneSince(aloneSince, view, now)
	local model = QueueFormat.pill(view, now, aloneSince, hintDismissedAt)
	local visible = model.visible and not StateController.isLobbyLocked()
	frame.Visible = visible
	local title, detail = titleLabel, detailLabel
	if visible and title and detail then
		measureTexts(model.title, model.detail)
		setIfChanged(title, "Text", model.title)
		setIfChanged(detail, "Text", model.detail or "")
		setIfChanged(detail, "Visible", model.detail ~= nil)
		for _, button in { keepButton, practiceButton } do
			if button then
				setIfChanged(button.root, "Visible", model.showHint)
			end
		end
		local hint = hintRow
		if hint then
			setIfChanged(hint, "Visible", model.showHint)
		end
	end
	layoutPill()
end

local function refreshPrompts()
	local attribute = QueueFormat.promptAttribute(StateController.queue().state)
	local baseAttribute = QueueFormat.promptAttribute("Idle")
	for _, podium in CollectionService:GetTagged(PODIUM_TAG) do
		local prompts: { Instance } = podium:GetDescendants()
		table.insert(prompts, podium)
		for _, candidate in prompts do
			if candidate:IsA("ProximityPrompt") then
				local key = candidate:GetAttribute(attribute) or candidate:GetAttribute(baseAttribute)
				local text = if type(key) == "string" then Strings.resolve(key) else nil
				if text and candidate.ActionText ~= text then
					candidate.ActionText = text
				end
			end
		end
	end
end

local function refreshBoard()
	local counts = StateController.queueCounts()
	for _, board in CollectionService:GetTagged(BOARD_TAG) do
		for _, descendant in board:GetDescendants() do
			if descendant:IsA("TextLabel") then
				local text = QueueFormat.boardText(descendant:GetAttribute(ATTR_LIVE_KEY), counts, MAX_SLOTS)
				if text and descendant.Text ~= text then
					descendant.Text = text
				end
			end
		end
	end
end

local function showMatched()
	local duel = StateController.duel()
	local name: string? = nil
	if duel then
		name = if duel.opponent.isTestDummy then Strings.duel.testDummy else duel.opponent.displayName
	end
	local text = QueueFormat.matchedText(name)
	local key = if duel then duel.matchId else "pending"
	if matchedBanner and matchedBannerFor == key then
		matchedBanner:setText(text)
		return
	end
	if matchedBanner and matchedBannerFor == "pending" and matchedBanner:isShown() then
		matchedBanner:setText(text)
		matchedBannerFor = key
		return
	end
	matchedBannerFor = key
	-- Overlays fix: under the duel HUD's top bar once that shows (UIController follows it); 20% down until then.
	local bar = UIController.screenGui(DUEL_GUI):FindFirstChild(DUEL_TOP_BAR)
	matchedBanner = UIController.banner(text, {
		seconds = MATCHED_SECONDS,
		color = Theme.Colors.mint,
		below = if bar and bar:IsA("GuiObject") then bar else nil,
	})
end

-- Overlays fix: the matched banner leaves once the countdown starts (the countdown disc sits under the top bar, which
-- already names the opponent).
local function dismissMatchedAfter(view: StateController.DuelView)
	if matchedBanner and not MATCHED_PHASES[view.phase] then
		matchedBanner:dismiss()
	end
end

-- The pill (foam restyle): a foam card; its top row is a clock, the title over the detail line, and Cancel; the
-- no-opponent hint's Keep waiting / Practice wrap in a row under it.
local function buildPill(c: Cleanup.Cleanup)
	local frame = Theme.panel({
		Name = "QueuePill",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, PILL_TOP),
		Size = UDim2.fromOffset(PILL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = UIController.screenGui(HUD_GUI),
	}, Theme.Radius.panel, PILL_PADDING)
	c:add(frame)
	-- Integration: the toasts start under the pill (under the Duel CTA; NotifyFormat chains them, spec 2026-10-11).
	UIController.toastsBelow("queue", frame)
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, frame, Enum.HorizontalAlignment.Left)
	local top: Frame = Create("Frame", {
		Name = "Top",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = frame,
	})
	Theme.list(Enum.FillDirection.Horizontal, PILL_GAP, top, Enum.HorizontalAlignment.Left)
	local clock = IconGlyph.new({ name = "Icon", icon = "clock", sizePx = ICON_PX, tone = "dark", layoutOrder = 1 })
	clock.root.Parent = top
	c:add(clock)
	local texts: Frame = Create("Frame", {
		Name = "Texts",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(PILL_WIDTH - 200, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = top,
	})
	Theme.list(Enum.FillDirection.Vertical, 2, texts, Enum.HorizontalAlignment.Left)
	textsFrame = texts
	titleLabel = Theme.label({
		Name = "Title",
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = texts,
	}, "Body", Enum.FontWeight.Bold)
	detailLabel = Theme.label({
		Name = "Detail",
		LayoutOrder = 2,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = texts,
	}, "Small", nil, Theme.Colors.ink2)

	-- The no-opponent hint (Part 8: a wrapping row, hidden until it is due).
	local row: Frame = Create("Frame", {
		Name = "Buttons",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = frame,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, row, Enum.HorizontalAlignment.Left).Wraps = true
	hintRow = row

	local keep = Button.new({
		name = "Queue_KeepWaitingButton",
		text = Strings.queue.keepWaiting,
		height = TOUCH.minTarget,
		layoutOrder = 1,
		parent = row,
		onActivated = function()
			hintDismissedAt = serverNow()
			refreshPill()
		end,
	})
	keep.root.Visible = false
	c:add(keep)
	keepButton = keep
	local practice = Button.new({
		name = "Queue_PracticeButton",
		text = Strings.queue.practice,
		height = TOUCH.minTarget,
		layoutOrder = 2,
		parent = row,
		onActivated = function()
			hintDismissedAt = serverNow()
			clearWaypoint()
			local target = WorldLayout.waypoint(PRACTICE_WAYPOINT)
			if target then
				waypoint = Waypoint.show(target)
			end
			refreshPill()
		end,
	})
	practice.root.Visible = false
	c:add(practice)
	practiceButton = practice
	local cancel = Button.new({
		name = "Queue_CancelButton",
		text = Strings.common.cancel,
		kind = "primary",
		height = TOUCH.closeButton,
		layoutOrder = 3,
		parent = top,
		onActivated = function()
			QueueController.leave()
		end,
	})
	c:add(cancel)
	cancelButton = cancel
	pill = frame
	-- The pill's height and Cancel's width (the text column) decide its place.
	c:add(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPill))
	c:add(cancel.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutPill))
	c:add(function()
		linkGamepad(false)
		pill, titleLabel, detailLabel, textsFrame, hintRow = nil, nil, nil, nil, nil
		keepButton, practiceButton, cancelButton, lastPlacement = nil, nil, nil, nil
		measuredKey, measuredText = nil, 0
	end)
end

local function onQueueChanged(new: StateController.QueueView, old: StateController.QueueView)
	if new.state ~= old.state then
		joining = false
		if new.state == "Searching" and old.state ~= "Searching" then
			hintDismissedAt = nil
			aloneSince = nil
		end
		if new.state ~= "Searching" then
			clearWaypoint()
		end
		if new.state == "Matched" then
			showMatched()
		end
		refreshPrompts()
	end
	local key = QueueFormat.toastKey(old, new)
	if key then
		UIController.toast(QueueFormat.messageText(key), "info")
	end
	refreshPill()
end

-- Public -----------------------------------------------------------------------------------------------------------

-- Sends QueueJoin (from the podium, the HUD "Duel" button or "Queue again"). Yields for the reply. Returns true when
-- the server accepted it.
function QueueController.joinAsync(): boolean
	if joining or StateController.queue().state ~= "Idle" or StateController.isLobbyLocked() then
		return false
	end
	joining = true
	local result = NetController.queueJoinAsync()
	joining = false
	if not result.ok then
		UIController.toast(QueueFormat.joinErrorText(result.reason), "warn")
		return false
	end
	refreshPill()
	return true
end

-- Sends QueueLeave while Searching (Cancel; the podium's "Leave Queue"). Ignored once Matched (§5.4). The pill
-- hides when the server's Idle status arrives (a repeated press is dropped by NetController's rate guard).
function QueueController.leave(): boolean
	if StateController.queue().state ~= "Searching" then
		return false
	end
	return NetController.queueLeave()
end

-- Small table for Studio checks (Part 8): the pill, its last placement (QueueFormat.pillPlacement, base px) and the
-- row buttons linked down to Cancel.
function QueueController.debugState(): { [string]: any }
	local frame = pill
	local place = lastPlacement
	return {
		state = StateController.queue().state,
		pillVisible = frame ~= nil and frame.Visible,
		placement = if place
			then { x = place.x, y = place.y, width = place.width, spot = place.spot, fits = place.fits }
			else nil,
		hint = keepButton ~= nil and keepButton.root.Visible,
	}
end

-- Lifecycle --------------------------------------------------------------------------------------------------------

function QueueController.init()
	local c = Cleanup.new()
	cleanup = c
	buildPill(c)

	c:add(UIController.registerScreen(SCREEN_NAME, {
		modal = false,
		onOpen = function()
			QueueController.joinAsync()
		end,
	}))
	c:add(StateController.QueueChanged:connect(onQueueChanged))
	c:add(StateController.QueueCountsChanged:connect(function()
		refreshBoard()
		refreshPill()
	end))
	c:add(StateController.LobbyLockChanged:connect(function()
		refreshPill()
	end))
	c:add(StateController.DuelChanged:connect(function(new: StateController.DuelView?, old: StateController.DuelView?)
		if new and (old == nil or old.matchId ~= new.matchId) then
			showMatched()
		end
		if new then
			dismissMatchedAfter(new)
		end
	end))
	c:add(NetController.onNotify(function(code: string, args: any, kind: any)
		if type(code) ~= "string" then
			return
		end
		for _, area in NOTIFY_AREAS do
			if string.sub(code, 1, #area) == area then
				local text = Strings.format(QueueFormat.messageText(code), if type(args) == "table" then args else nil)
				UIController.toast(text, if type(kind) == "string" then kind :: any else "info")
				return
			end
		end
	end))
	c:add(CollectionService:GetInstanceAddedSignal(PODIUM_TAG):Connect(function()
		task.defer(refreshPrompts) -- after WorldBinder re-applies the baked text on stream-in
	end))
	c:add(CollectionService:GetInstanceAddedSignal(BOARD_TAG):Connect(function()
		task.defer(refreshBoard)
	end))
	c:add(clearWaypoint)
end

function QueueController.start()
	local c = cleanup
	if c == nil then
		return
	end
	c:add(WorldBinder.registerStand(PODIUM_TAG, function()
		if StateController.queue().state == "Searching" then
			QueueController.leave()
		else
			QueueController.joinAsync()
		end
	end))
	task.defer(refreshPrompts)
	refreshBoard()

	-- Follow the HUD the pill keeps clear of: its layout passes, and the coach card (it exists now: every init ran).
	local gui = UIController.screenGui(HUD_GUI)
	local function relayout()
		layoutPill()
	end
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))
	c:add(UIController.LayoutChanged:connect(relayout))
	c:add(HudController.LayoutChanged:connect(relayout))
	local coach = gui:FindFirstChild(COACH_FRAME)
	if coach and coach:IsA("GuiObject") then
		c:add(coach:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout))
		c:add(coach:GetPropertyChangedSignal("AbsolutePosition"):Connect(relayout))
		c:add(coach:GetPropertyChangedSignal("Visible"):Connect(relayout))
	else
		log:warn(`SD_Hud has no {COACH_FRAME}; the queue pill cannot keep clear of it`)
	end
	layoutPill()

	local player = Players.LocalPlayer
	if player then
		c:add(player.Idled:Connect(function()
			if StateController.queue().state == "Searching" then
				NetController.reportIdle()
			end
		end))
	end
	local function guarded(label: string, fn: () -> ())
		local ok, err = pcall(function(): any
			fn()
			return nil
		end)
		if not ok then
			log:error(`{label} failed:`, err)
		end
	end
	c:add(task.spawn(function()
		local ticks = 0
		while true do
			task.wait(TICK_SECONDS)
			ticks += 1
			local frame = pill
			if frame and (frame.Visible or StateController.queue().state == "Searching") then
				guarded("queue pill update", refreshPill)
			end
			-- A podium prompt that streams in later gets its baked text back from WorldBinder; put the live one on.
			if ticks % PROMPT_REFRESH_TICKS == 0 then
				guarded("queue prompt update", refreshPrompts)
			end
		end
	end))
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function QueueController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return QueueController
