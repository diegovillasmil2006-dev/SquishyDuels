--!strict
-- DailyController (client only). DESIGN §6.9 (daily rewards), §11.6 (Daily screen), §7.6 / §7.7 (the daily stand and
-- its sign), §11.3 (states), §11.4 (focus), §18.5.2 B2 (coin flights). The server decides every claim
-- (DailyRewardService); this module only shows the state and sends DailyClaim. Looks: UI/DailyFormat (pure).
-- * The "daily" modal (registered in init, so the HUD's Daily button and the SD_DailyStand prompt come alive, §7.6):
--   7 day cards (Day n, its Coins (pens3 phase 1: its squeezes × the `pen` field's squeeze value, refreshed when the
--   pen changes), "Treat Box" on day 7), the Claim button (Daily_ClaimButton) on today's card, the streak and the
--   time to the next reward (refreshed every second while open).
--   Locked states (§11.3): a profile that is not ready -> disabled with reason.data.notReady; a pending save -> disabled
--   with reason.box.saving (§3.11: daily claims are blocked while a save is pending; reading, planner note 3).
-- * Claim -> NetController.invokeAsync("DailyClaim") (one at a time; the button shows its spinner). On ok: the Coins fly
--   into the pill (HudController.flyCoins, only for amounts >= coinFlight.minAmount) and common.coinsGain is toasted. A
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
-- UI FINAL R3 (the window frame, plan work/ui/PLAN.md R3; `H:n` = "Squishy Duels HUD.dc.html" line n): the panel is
-- the design's Daily Rewards window (Theme.window "daily", H:382-385: 980 x 620, shrunk to fit with its sticker and X,
-- Layout.windowFit) with its purple band (Theme.headerTab: "DAILY REWARDS", H:386; the sticker, H:421) and the 76 px
-- close X in the band (Theme.attachClose, H:422); fitBody lays the chrome out at the window's chrome scale
-- (Theme.fitWindow) and places the window as the design does (Layout.windowShift).
-- UI FINAL R8 (the design's Daily window, plan R8; Config.UI.Daily): the body (padding 18 26 26, gap 16, H:388-389):
-- the streak pill ("Day {n}", the pulsing flame, H:390) and the timer pill (pushed right: "Your reward is ready!" /
-- "Next reward in h:mm:ss", or the lock reason, H:391; no welcome back line, G8.6), then the grid (H:393,
-- DailyFormat.gridLayout; phones: 3 columns and day 7 under them, scrolling with the design bar, H:22). A day card
-- (H:395-404): the face per DailyFormat.cardLook (today's claimable day yellow with the white border, a claimed day
-- lilac with its icon at .5 and the stamped check, else the purple card), "Day n", the coin 84 (today's pulsing 1.4 s),
-- the lock on later days, the Coins, the CLAIM! chip on today's (Daily_ClaimButton, Button size "chip", PR15) or
-- "Tomorrow" on the next. Day 7 (H:406-416): the gold-to-purple card with its spinning rays, "Day 7", MEGA REWARD, the
-- floating Treat Box with two twinkles, its lock, "Treat Box" and the foot (Claimed / Claim! / Tomorrow / Locked); the
-- whole card is its claim (no chip). Every card takes the card hover (y -5, 1.035, the brightness) and the press on an
-- inner holder (Button.decorate): a press anywhere on today's card claims (squash .7, PR4), the other days are off
-- (ui.error and the 9 px shake, PR5). On open the cards rise in (sdRise, i x 50 ms; day 7 after .35 s) and the claimed
-- checks stamp in (sdStamp); a new claim stamps its check. Claim ok (H:850-858): the stamp sound, the claim sound 120
-- ms later (ui.click low / ui.purchase, RL8), the design's burst and ring at the card and 10 coins (Config.UI.Fx.events
-- .dailyClaim); on the Treat Box day the window closes after 750 ms and the reveal waits until 280 ms after that
-- (BoxController.debugHoldReveals holds the unseen reveal meanwhile, G8.7).
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
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local Create = require(Client.UI.Create)
local DailyFormat = require(Client.UI.DailyFormat)
local Focus = require(Client.UI.Focus)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local Layout = require(Client.UI.Layout)
local MotionTrack = require(Client.UI.MotionTrack)
local NotifyFormat = require(Client.UI.NotifyFormat)
local Theme = require(Client.UI.Theme)
local UiFx = require(Client.UI.UiFx)
local UiIdle = require(Client.Anim.UiIdle)
local WellPill = require(Client.UI.Components.WellPill)
local BoxController = require(script.Parent.BoxController)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

-- UI FINAL R8: a day card (days 1-6 and day 7).
type DayView = {
	day: number,
	root: Frame, -- the laid-out box (face + lip), Daily_Day<n>
	hit: TextButton, -- the press target over the card (the chip under it keeps the gamepad, PR15)
	rise: Frame, -- SD_Rise: the entrance
	foam: Theme.Foam,
	mix: number, -- the hover filter (0..1)
	look: DailyFormat.CardLook?, -- days 1-6: the painted look
	labels: { { label: TextLabel, kind: Theme.TextKind, tight: boolean } }, -- sized by fitBody (lineBox)
	name: TextLabel?,
	value: TextLabel?,
	icon: Frame?,
	pulse: Frame?, -- today's icon area loop
	pulseHandle: UiIdle.Handle?,
	check: Frame?,
	lock: Frame,
	slot: Frame?, -- the CLAIM! chip's place
	nextLabel: TextLabel?,
	foot: TextLabel?, -- day 7
	claimed: boolean, -- as last painted (a change stamps the check)
}

-- Constants

local SCREEN = "daily"
local STAND_TAG = "SD_DailyStand"
local STATUS_LABEL = "Status" -- the sign's live line (WorldLayout.Signs dailySign, built empty)
local REMOTE = "DailyClaim"
local FIELD = "daily"
local MODAL_GUI = "SD_Modal"
local WINDOW_KIND = "daily" -- UI FINAL R3: its Config.UI.Sticker.window kind (H:382-424)
local TICK_SECONDS = 1 -- the countdown and the sign line change once a second
local REASON_NOT_READY = "data.notReady"
local REASON_SAVING = "box.saving" -- §3.11 "Saving your collection…" (reading: DESIGN has no daily code for it)
local REASON_ALREADY_CLAIMED = "daily.alreadyClaimed"
local SUCCESS_KIND: UIController.ToastKind = "success"
local WARN_KIND: UIController.ToastKind = "warn"
local INFO_KIND: UIController.ToastKind = "info"
-- UI FINAL R8 (Config.UI.Daily, H:382-424, H:850-858).
local DAILY = Config.UI.Daily
local BODY, CARD, DAY7, STAMP = DAILY.body, DAILY.card, DAILY.day7, DAILY.stamp
local CARD_IN = Config.UI.motion.cardIn -- H:31: sdRise's frames
local CLAIM_FX = Config.UI.Fx.events.dailyClaim -- H:854-856
local STICKER = Config.UI.Sticker
local WINDOW_BORDER = STICKER.border.heavy
local WINDOW_LIP = STICKER.lip.window
local CHIP_LIP = STICKER.lip.bar -- Button size "chip": lip 3 (H:402)
local DAY_SURFACE = STICKER.surfaces.day -- H:395
local NAME_KIND: Theme.TextKind = CARD.nameKind :: Theme.TextKind -- H:396
-- reading: the room kept round the grid inside its scrolling frame, so a card's hover (y -5, 1.035; day 7 grows 7 px
-- each way) and its rise are not clipped; the frame reaches this far into the body's padding (26) and gap (16).
local HOVER_ROOM = 14
local DAYS = #Config.Economy.Daily.coinsByDay
local WHITE = Color3.new(1, 1, 1)
local SOUND_STAMP = "ui.click" -- the design's stamp (lib:184, 120 Hz) by its nearest clip (RL8) ...
local STAMP_PITCH = Config.Audio.pitchMin -- ... as low as a pitch goes (the press is 460 Hz, lib:135)
local SOUND_CLAIM = "ui.purchase" -- the design's claim (lib:146) by its nearest clip (RL8)

-- Module table

local DailyController = {}

-- Private

local log = Log.new("Daily")
local cleanup: Cleanup.Cleanup? = nil
local root: Frame? = nil
local grid: ScrollingFrame? = nil
local days: { DayView } = {}
local streakPill: WellPill.WellPill? = nil
local timerPill: WellPill.WellPill? = nil
local claimButton: Button.Button? = nil
local closeButton: Button.Button? = nil
local lastModel: DailyFormat.Model? = nil
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
	return DailyFormat.model(dailyState(), serverNow(), StateController.get("pen"))
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

-- UI FINAL R8: a text line's box (base px): the design's line-height 1 (`tight`: the text size, H:396, H:401, H:408,
-- H:415; the letters may overhang it a little, as in CSS) or a normal line (the measure).
local function lineBox(kind: Theme.TextKind, tight: boolean): number
	return math.ceil(if tight then Theme.textSize(kind) else Theme.lineHeight(kind))
end

-- UI FINAL R8: whether a press on day `n`'s card claims now (today's claimable day, nothing in the way).
local function isClaimTarget(n: number): boolean
	local model = lastModel
	return model ~= nil and model.canClaim and model.nextDay == n and not claiming and lockReason() == nil
end

-- A face's colours (top -> [mid ->] bottom under its inset highlight) at hover filter `mix` (Button.hoverColor, H:637).
local function faceColors(
	top: Color3,
	bottom: Color3,
	highlightAlpha: number,
	mix: number,
	mid: Color3?,
	midAt: number?
): Theme.FoamColors
	local function lit(color: Color3): Color3
		return if mix > 0 then color:Lerp(Button.hoverColor(color), mix) else color
	end
	local colors: Theme.StickerColors = {
		face = lit(top),
		mid = if mid then lit(mid) else nil,
		midAt = midAt,
		faceEnd = lit(bottom),
		top = lit(top:Lerp(WHITE, highlightAlpha)),
		drop = Theme.Colors.inkUI,
	}
	return colors :: any
end

local function paintFace(view: DayView)
	if view.day == DAYS then
		view.foam:paint(
			faceColors(
				Palette.StickerFeaturedTop,
				Palette.StickerDay7End,
				DAY7.inset.alpha,
				view.mix,
				Palette.StickerFeaturedMid,
				DAY7.midAt
			),
			"exact"
		)
		return
	end
	local look = view.look
	if look then
		local p = Palette :: any
		view.foam:paint(faceColors(p[look.top], p[look.bottom], DAY_SURFACE.highlightAlpha, view.mix), "exact")
		view.foam:setStroke(p[look.border], CARD.border)
	end
end

-- The picture's alpha (H:398 opacity .5 once claimed) and its drop shadow with it.
local function setIconAlpha(icon: Frame, alpha: number)
	local image = icon:FindFirstChild("Image")
	if image and image:IsA("ImageLabel") then
		image.ImageTransparency = 1 - alpha
	end
	local shadow = icon:FindFirstChild("Shadow")
	if shadow and shadow:IsA("ImageLabel") then
		shadow.ImageTransparency = 1 - CARD.iconShadow.alpha * alpha
	end
end

local function stamp(view: DayView, delayMs: number?)
	local check = view.check
	if check then
		MotionTrack.play(check, STAMP.frames :: any, STAMP.ms, delayMs or 0, STAMP.curve)
	end
end

local function paintDay(view: DayView, card: DailyFormat.DayCard)
	local justClaimed = card.claimed and not view.claimed
	view.claimed = card.claimed
	view.lock.Visible = card.locked
	local foot = view.foot
	if foot then
		foot.Text = card.foot
	end
	if view.day ~= DAYS then
		local look = DailyFormat.cardLook(card)
		view.look = look
		local name, value = view.name :: TextLabel, view.value :: TextLabel
		Theme.textOnLight(name, (Palette :: any)[look.name])
		value.Text = card.valueText
		setIconAlpha(view.icon :: Frame, look.iconAlpha)
		local check = view.check :: Frame
		check.Visible = card.claimed
		local claimable = card.today and not card.claimed
		local slot = view.slot :: Frame
		slot.Visible = claimable
		local nextLabel = view.nextLabel :: TextLabel
		nextLabel.Visible = card.next and not claimable
		-- H:397: today's icon area pulses (1.4 s).
		local pulse, handle = view.pulse, view.pulseHandle
		if claimable and handle == nil and pulse then
			view.pulseHandle = UiIdle.add(pulse, "pulse", { periodS = CARD.pulseS })
		elseif not claimable and handle then
			handle:remove()
			view.pulseHandle = nil
		end
		if justClaimed and UIController.isOpen(SCREEN) then
			stamp(view)
		end
	end
	paintFace(view)
end

local function refresh()
	local frame = root
	if frame == nil then
		return
	end
	local model = currentModel()
	lastModel = model
	local lock = lockReason()
	local streak, timer = streakPill, timerPill
	if streak then
		streak:setText(model.streakText)
	end
	if timer then
		timer:setText(if model.known then lock or model.timerText or "" else Strings.common.loading)
	end
	for i, card in model.cards do
		local view = days[i]
		if view then
			paintDay(view, card)
		end
	end
	-- PR15: the chip sits on today's card (days 1-6); day 7 is its own claim (no chip).
	local button = claimButton
	local today = if model.known and model.canClaim then days[model.nextDay] else nil
	if button then
		local slot = if today then today.slot else nil
		button.root.Visible = slot ~= nil
		if slot and button.root.Parent ~= slot then
			button.root.Parent = slot
		end
		if claiming then
			button:setState("loading")
		else
			button:setState(if lock then "disabled" else "normal")
		end
	end
	local seven = days[DAYS]
	if seven then
		seven.hit.Selectable = today == seven
	end
end

-- The panel's scale on screen: the UI scale times UIController's open pop (SD_OpenScale).
local function panelScale(panel: GuiObject): number
	local pop = panel:FindFirstChild("SD_OpenScale")
	local openScale = if pop and pop:IsA("UIScale") then pop.Scale else 1
	return UIController.scale() * openScale
end

-- UI FINAL R8: the window at its fitted design size (Layout.windowFit) with its chrome, the top row, and the grid
-- (DailyFormat.gridLayout) in the body; the grid scrolls only when its cards need more room than the body has
-- (phones, the largest text), its lips hanging into the bottom padding as the design's box-shadow does.
local function fitBody()
	local frame, scroll = root, grid
	if frame == nil or scroll == nil then
		return
	end
	local gui = UIController.screenGui(MODAL_GUI)
	local screen = gui.AbsoluteSize
	if not (panelScale(frame) > 0) or screen.X <= 0 or screen.Y <= 0 then
		return
	end
	local fit = Layout.windowFit(screen, WINDOW_KIND)
	local chrome = Theme.fitWindow(frame, fit.k)
	local size = UDim2.fromOffset(fit.width, fit.height + WINDOW_LIP) -- the face and its lip
	if frame.Size ~= size then
		frame.Size = size
	end
	local position = UDim2.new(0.5, 0, 0.5, fit.shift)
	if frame.Position ~= position then
		frame.Position = position
	end
	for _, view in days do
		for _, entry in view.labels do
			local height = lineBox(entry.kind, entry.tight)
			if entry.label.Size.Y.Offset ~= height then
				entry.label.Size = UDim2.new(1, 0, 0, height)
			end
		end
	end
	local width = fit.width - 2 * (WINDOW_BORDER + BODY.padX)
	local height = fit.height - chrome.top - (WINDOW_BORDER + BODY.padBottom)
	local top = DAILY.streak.height + BODY.gap
	local room = height - top
	local hang = math.max(CARD.lip, DAY7.lip)
	local cardFace = DailyFormat.cardFace(lineBox(NAME_KIND, true), lineBox("H2", true))
	local day7Face = DailyFormat.day7Face(lineBox("HudNumber", true), lineBox("Large", true), lineBox("Small", false))
	local compact = fit.class == "compact"
	local layout = DailyFormat.gridLayout(width, room, compact, cardFace, day7Face)
	-- The frame reaches HOVER_ROOM past the grid on every side (the scroll bar, when it shows, sits in that room).
	scroll.Position = UDim2.fromOffset(-HOVER_ROOM, top - HOVER_ROOM)
	scroll.Size = UDim2.fromOffset(width + 2 * HOVER_ROOM, room + hang + 2 * HOVER_ROOM)
	scroll.CanvasSize = UDim2.fromOffset(0, layout.height + 2 * HOVER_ROOM)
	for i, view in days do
		local rect = if i == DAYS then layout.day7 else layout.cards[i]
		if rect then
			view.root.Position = UDim2.fromOffset(HOVER_ROOM + rect.x, HOVER_ROOM + rect.y)
			view.root.Size = UDim2.fromOffset(rect.w, rect.h)
		end
	end
end

-- The failed Result's text with {time} filled in (daily.alreadyClaimed "Come back in {time}").
local function failureText(result: NetController.Result): string
	return Strings.format(NotifyFormat.resultText(result :: any), { time = DailyFormat.countdownText(serverNow()) })
end

local function claim()
	local model = currentModel()
	if claiming or lockReason() ~= nil or not model.canClaim then
		refresh()
		return
	end
	-- H:852: the burst and the coins start at the card (the flight's start is taken now: the reply's StateDelta may
	-- change the window before the reply returns).
	local view = days[model.nextDay]
	local at: GuiObject? = if view then view.root else nil
	local from: Vector2? = if at then at.AbsolutePosition + at.AbsoluteSize / 2 else nil
	local boxDay = model.treat
	if boxDay then
		BoxController.debugHoldReveals(true) -- G8.7: the Treat Box reveal waits for the window to close
	end
	claiming = true
	refresh()
	local result = NetController.invokeAsync(REMOTE)
	claiming = false
	if result.ok then
		-- H:852-856: the stamp, the claim sound 120 ms later, the burst and ring at the card (after the server's yes).
		SoundController.play(SOUND_STAMP, { pitch = STAMP_PITCH })
		task.delay(DAILY.claimSoundDelayMs / 1000, function()
			SoundController.play(SOUND_CLAIM)
		end)
		if at then
			UiFx.sparks(at, { n = CLAIM_FX.sparks.n, spread = CLAIM_FX.sparks.spread })
			for _, ring in CLAIM_FX.rings do
				UiFx.ring(at, UiFx.colors({ ring.color })[1], ring.size)
			end
		end
		local data = if type(result.data) == "table" then result.data else {}
		local coins = if type(data.coins) == "number" then math.floor(data.coins) else 0
		if coins > 0 then
			if from then
				HudController.flyCoins(from, coins, CLAIM_FX.coins)
			end
			UIController.toast(
				Strings.format(Strings.common.coinsGain, { coins = Format.coins(coins) }),
				SUCCESS_KIND,
				{ sound = false } -- one sound per action: the claim's
			)
		end
		if boxDay then
			local flow = DAILY.boxFlow
			task.delay(flow.closeAfterMs / 1000, function()
				if UIController.isOpen(SCREEN) then
					UIController.close(SCREEN, "button")
				end
			end)
			task.delay((flow.closeAfterMs + flow.revealAfterMs) / 1000, function()
				BoxController.debugHoldReveals(false)
			end)
		end
	else
		if boxDay then
			BoxController.debugHoldReveals(false)
		end
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

-- A one-line label with an explicit height (fitBody keeps it; no AutomaticSize under the scaled window): lineBox.
local function line(view: DayView, props: { [string]: any }, kind: Theme.TextKind, tight: boolean?): TextLabel
	props.AutomaticSize = Enum.AutomaticSize.None
	props.Size = UDim2.new(1, 0, 0, lineBox(kind, tight == true))
	props.TextWrapped = false
	props.TextXAlignment = Enum.TextXAlignment.Center
	local label = Theme.label(props, kind)
	table.insert(view.labels, { label = label, kind = kind, tight = tight == true })
	return label
end

-- An image icon centred in `parent` (or placed by the caller).
local function picture(parent: Instance, key: string, px: number, name: string, shadow: any?): Frame
	local image = IconGlyph.image(key, { name = name, sizePx = px, shadow = shadow, parent = parent })
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	return image
end

-- The frame of a card: the laid-out box, SD_Visual (hover / press) > SD_Rise (entrance) > the face, and the hit box
-- over it all (Button.decorate on it poses SD_Visual; a press on a day that is not today's claim is "off").
local function cardShell(
	n: number,
	parent: Instance,
	look: { radius: number, border: number, lip: number, inset: number }
)
	local c = cleanup :: Cleanup.Cleanup
	local box: Frame = Create("Frame", { Name = "Daily_Day" .. n, BackgroundTransparency = 1, Parent = parent })
	local visual = holder("SD_Visual", box)
	local rise = holder("SD_Rise", visual)
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = rise,
	})
	local bands = Layout.stickerBands(look.border, look.inset, 0, look.lip)
	local foam = Theme.foam(face, {
		radius = look.radius,
		stroke = look.border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
	})
	local hit: TextButton = Create("TextButton", {
		Name = "Hit",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		ZIndex = 10,
		Parent = box,
	})
	local view: DayView = {
		day = n,
		root = box,
		hit = hit,
		rise = rise,
		foam = foam,
		mix = 0,
		look = nil,
		labels = {},
		lock = nil :: any, -- set by the builder
		claimed = false,
	}
	local feel: Button.DecorateOptions = {
		fx = "card",
		visual = visual,
		clickSound = false, -- the claim plays its own (H:395 data-snd none)
		pivotPx = look.lip / 2,
		onFilter = function(mix: number)
			view.mix = mix
			paintFace(view)
		end,
		off = function(): boolean
			return not isClaimTarget(n)
		end,
	}
	c:add(Button.decorate(hit, feel))
	c:add(hit.Activated:Connect(function()
		if isClaimTarget(n) then
			claim()
		end
	end))
	return view, face
end

-- A content frame inside a face's border and padding, above its lip, with a centred column.
local function column(
	face: Frame,
	border: number,
	padTop: number,
	padX: number,
	padBottom: number,
	lip: number,
	gap: number
)
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -lip),
		Active = false,
		ZIndex = 2,
		Parent = face,
	})
	Create("UIPadding", {
		PaddingTop = UDim.new(0, border + padTop),
		PaddingBottom = UDim.new(0, border + padBottom),
		PaddingLeft = UDim.new(0, border + padX),
		PaddingRight = UDim.new(0, border + padX),
		Parent = content,
	})
	Theme.list(Enum.FillDirection.Vertical, gap, content, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
	return content
end

-- The flexible middle of a card column (CSS flex: 1), where the picture sits.
local function flexArea(parent: Instance, order: number): Frame
	local area: Frame = Create("Frame", {
		Name = "IconArea",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = order,
		Parent = parent,
	})
	Create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = area })
	return area
end

-- A day card 1-6 (H:395-404).
local function buildDay(parent: Instance, card: DailyFormat.DayCard): DayView
	local view, face = cardShell(card.day, parent, {
		radius = CARD.radius,
		border = CARD.border,
		lip = CARD.lip,
		inset = DAY_SURFACE.highlightPx,
	})
	local content = column(face, CARD.border, CARD.padTop, CARD.padX, CARD.padBottom, CARD.lip, CARD.gap)
	view.name = line(view, { Name = "Name", Text = card.label, LayoutOrder = 1, Parent = content }, NAME_KIND, true)
	local area = flexArea(content, 2)
	local pulse = holder("SD_Pulse", area)
	view.pulse = pulse
	view.icon = picture(pulse, "img.coin", CARD.iconPx, "Icon", CARD.iconShadow)
	-- H:399: the check stamped over the icon, drawn at its rest -10° (STAMP.restRot).
	local check: Frame = Create("Frame", {
		Name = "Check",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD.checkPx, CARD.checkPx),
		Rotation = STAMP.restRot,
		Visible = false,
		ZIndex = 3,
		Parent = area,
	})
	picture(check, "img.icon.check", CARD.checkPx, "Icon")
	view.check = check
	local lock = IconGlyph.image("img.icon.lock", { name = "Lock", sizePx = CARD.lockPx, parent = area })
	lock.AnchorPoint = Vector2.new(1, 1)
	lock.Position = UDim2.new(1, -CARD.lockRight, 1, -CARD.lockBottom)
	lock.ZIndex = 3
	view.lock = lock
	local value = line(view, { Name = "Value", Text = card.valueText, LayoutOrder = 3, Parent = content }, "H2", true)
	Theme.stickerText(value, CARD.valueRole)
	view.value = value
	view.slot = Create("Frame", {
		Name = "ClaimSlot",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, CARD.chipFace),
		Visible = false,
		LayoutOrder = 4,
		Parent = content,
	})
	local nextLabel = line(
		view,
		{ Name = "Tomorrow", Text = Strings.daily.tomorrow, Visible = false, LayoutOrder = 5, Parent = content },
		"Small"
	)
	Theme.stickerText(nextLabel, CARD.nextRole)
	view.nextLabel = nextLabel
	return view
end

-- Day 7 (H:406-416).
local function buildDay7(parent: Instance): DayView
	local view, face = cardShell(DAYS, parent, {
		radius = DAY7.radius,
		border = DAY7.border,
		lip = DAY7.lip,
		inset = DAY7.inset.px,
	})
	view.foam:setStroke(Palette.StickerInk, DAY7.border) -- H:406: always ink
	Focus.decorate(view.hit, DAY7.radius) -- the gamepad's claim on day 7 (refresh makes it selectable then)
	-- Inside the border, above the lip: the rays (H:407) clip there (overflow hidden, H:406).
	local clip: Frame = Create("Frame", {
		Name = "Clip",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(DAY7.border, DAY7.border),
		Size = UDim2.new(1, -2 * DAY7.border, 1, -(2 * DAY7.border + DAY7.lip)),
		ClipsDescendants = true,
		Active = false,
		Parent = face,
	})
	local rays = DAY7.rays
	Theme.rays(clip, "img.fx.rays", rays.px, rays.alpha, rays.spinS, rays.centreY)
	local content = column(face, DAY7.border, DAY7.padTop, DAY7.padX, DAY7.padBottom, DAY7.lip, DAY7.gap)
	local title = line(view, {
		Name = "Title",
		Text = Strings.format(Strings.daily.dayLabel, { n = DAYS }),
		LayoutOrder = 1,
		Parent = content,
	}, "HudNumber", true)
	Theme.stickerText(title, DAY7.titleRole)
	-- H:409: MEGA REWARD, a red pill 26 high, padding 3 10 0, border 3, sized from its text.
	local pillSpec = DAY7.pill
	local pillKind: Theme.TextKind = Theme.Sticker.text[pillSpec.textRole].kind :: Theme.TextKind
	local pillText = Strings.daily.megaReward
	local pill: Frame = Create("Frame", {
		Name = "MegaReward",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(
			math.ceil(Theme.textWidth(pillText, pillKind)) + 2 * (pillSpec.padX + pillSpec.border) + 2,
			pillSpec.height
		),
		LayoutOrder = 2,
		Parent = content,
	})
	Theme.foam(pill, {
		radius = pillSpec.height,
		stroke = pillSpec.border,
		inner = true,
		colors = { face = Palette.StickerRedTop, faceEnd = Palette.StickerRedEnd },
	})
	local pillLabel = Theme.label({
		Name = "Text",
		Text = pillText,
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, pillSpec.padTop / 2),
		Size = UDim2.new(1, 0, 0, math.ceil(Theme.lineHeight(pillKind))),
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = pill,
	}, pillKind)
	Theme.stickerText(pillLabel, pillSpec.textRole)
	-- H:410-414: the art area: the Treat Box floating, two twinkles, the lock.
	local area = flexArea(content, 3)
	local float = holder("SD_Float", area)
	picture(float, "img.box.treat", DAY7.artPx, "Art", DAY7.artShadow)
	UiIdle.add(float, "float", { periodS = DAY7.floatS })
	for index, spot in DAY7.stars do
		local star = IconGlyph.image("img.icon.star", { name = "Twinkle" .. index, sizePx = spot.px, parent = area })
		star.AnchorPoint = Vector2.new(if spot.right then 1 else 0, if spot.bottom then 1 else 0)
		star.Position = UDim2.new(
			if spot.right then 1 else 0,
			if spot.right then -spot.right else spot.left or 0,
			if spot.bottom then 1 else 0,
			if spot.bottom then -spot.bottom else spot.top or 0
		)
		local image = star:FindFirstChild("Image")
		if image and image:IsA("GuiObject") then
			image.AnchorPoint = Vector2.new(0.5, 0.5) -- sdTwinkle turns and scales about the centre
			image.Position = UDim2.fromScale(0.5, 0.5)
			UiIdle.add(image, "twinkle", { periodS = spot.periodS, delayS = spot.delayS })
		end
	end
	local lock = IconGlyph.image("img.icon.lock", { name = "Lock", sizePx = DAY7.lockPx, parent = area })
	lock.AnchorPoint = Vector2.new(1, 0)
	lock.Position = UDim2.new(1, -DAY7.lockRight, 0, DAY7.lockTop)
	lock.ZIndex = 3
	view.lock = lock
	local name =
		line(view, { Name = "Name", Text = Strings.daily.treatBox, LayoutOrder = 4, Parent = content }, "Large", true)
	Theme.stickerText(name, DAY7.nameRole)
	local foot = line(view, { Name = "Foot", Text = "", LayoutOrder = 5, Parent = content }, "Small")
	Theme.stickerText(foot, DAY7.footRole)
	view.foot = foot
	return view
end

-- On every open (the design mounts the window anew): the cards rise in and the claimed checks stamp in.
local function playEntrance()
	for i, view in days do
		local rise = if i == DAYS then DAY7.rise else CARD.rise
		local delay = if i == DAYS then DAY7.rise.delayMs else (i - 1) * CARD.rise.stepMs
		MotionTrack.play(view.rise, CARD_IN.frames :: any, rise.ms, delay, rise.curve)
		if view.claimed then
			stamp(view, delay) -- with its card (the design's card fades its check in with it)
		end
	end
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local fit = Layout.windowFit(gui.AbsoluteSize, WINDOW_KIND)
	local panel = Theme.window({
		Name = "Daily",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(fit.width, fit.height + WINDOW_LIP),
		Parent = parent,
	}, WINDOW_KIND, BODY.padTop)
	c:add(panel)
	-- UI FINAL R8 (H:389): the body's padding 18 26 26 inside the window's border (fitWindow sets the top).
	local pad = panel:FindFirstChildOfClass("UIPadding") :: UIPadding
	pad.PaddingLeft = UDim.new(0, WINDOW_BORDER + BODY.padX)
	pad.PaddingRight = UDim.new(0, WINDOW_BORDER + BODY.padX)
	pad.PaddingBottom = UDim.new(0, WINDOW_BORDER + BODY.padBottom + WINDOW_LIP)
	-- UI FINAL R3: the band (H:385-386) on the window's top (it sets the top padding).
	Theme.headerTab(panel, Strings.daily.panelTitle)
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = panel,
	})

	local close = Button.new({
		name = "Daily_CloseButton",
		text = Strings.common.close,
		kind = "close", -- UI overhaul: the chunky red X
		parent = panel,
		sound = false, -- a Close button plays ui.back through UIController.close (§18.6)
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	Theme.attachClose(panel, close.root) -- UI FINAL R3: the 76 px X in the band (H:422)
	close.root.Modal = true -- frees the cursor in shift lock / first person
	c:add(close)
	closeButton = close

	-- H:389-391: the top row: the streak pill and the timer pill pushed right.
	local topRow: Frame = Create("Frame", {
		Name = "TopRow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, DAILY.streak.height),
		Parent = content,
	})
	local streak = WellPill.new({
		name = "Streak",
		look = DAILY.streak,
		icon = "img.icon.flame",
		colors = { top = Palette.StickerStreakTop, bottom = Palette.StickerStreakEnd, inset = DAILY.streak.inset },
		parent = topRow,
	})
	c:add(streak)
	if streak.icon then
		UiIdle.add(streak.icon :: Frame, "pulse", { periodS = DAILY.streak.pulseS })
	end
	streakPill = streak
	local timer = WellPill.new({ name = "Timer", look = DAILY.timer, icon = "img.icon.clock", parent = topRow })
	timer.root.AnchorPoint = Vector2.new(1, 0)
	timer.root.Position = UDim2.fromScale(1, 0)
	c:add(timer)
	timerPill = timer

	-- H:393: the grid, in a scrolling frame (it scrolls only on phones and at the largest text; fitBody).
	local scroll: ScrollingFrame = Theme.scrollbar(Create("ScrollingFrame", {
		Name = "Grid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromScale(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = content,
	}))
	grid = scroll
	table.clear(days)
	for _, card in DailyFormat.model(nil, serverNow()).cards do
		table.insert(days, if card.day == DAYS then buildDay7(scroll) else buildDay(scroll, card))
	end
	-- PR15: Daily_ClaimButton is the design's CLAIM! chip (H:402); refresh puts it on today's card. The card over it
	-- takes the pointer; the chip keeps the gamepad, the disabled state and the spinner.
	local button = Button.new({
		name = "Daily_ClaimButton",
		text = Strings.daily.claimTag,
		kind = "primary",
		size = "chip",
		clickSound = false, -- the claim plays the stamp and the claim sounds
		onActivated = claim,
	})
	button.root.AnchorPoint = Vector2.new(0.5, 0.5)
	button.root.Position = UDim2.new(0.5, 0, 0, (CARD.chipFace + CHIP_LIP) / 2) -- the face on the slot, the lip below
	button.root.Visible = false
	c:add(button)
	claimButton = button
	root = panel
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
			fitBody()
			playEntrance()
		end,
		primary = function(): GuiObject?
			local button = claimButton
			if button and button.root.Visible then
				return button.root
			end
			local seven = days[DAYS]
			if seven and seven.hit.Selectable then
				return seven.hit
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
	c:add(StateController.changed("pen"):connect(refresh)) -- pens3 phase 1: the pen's squeeze value sets the Coins
	c:add(function()
		table.clear(days)
		root, grid, claimButton, closeButton = nil, nil, nil, nil
		streakPill, timerPill, lastModel = nil, nil, nil
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
