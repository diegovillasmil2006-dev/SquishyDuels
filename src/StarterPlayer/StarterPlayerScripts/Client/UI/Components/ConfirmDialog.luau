--!strict
-- ConfirmDialog (client only). UI FINAL R6 (plan work/ui/PLAN.md R6, PR13 decided 2026-10-15; `H:n` = "Squishy Duels
-- HUD.dc.html" line n; Config.UI.confirm): the design's confirm dialog (H:455-469), the second step of a coin spend
-- (§11.5: the confirm step with "Balance after"), with the coin price and the coin instead of Robux. R6 opens it from
-- the Shop's featured BUY (as the design's buyFeat does, H:1023 -> ask H:862); R7 reuses it for the boxes.
--   local dialog = ConfirmDialog.open({ layer = gui, title = name, description = text, price = 10000,
--       catalogId = "toast", onBuy = function() ... end, onCancel = function(reason) ... end })
--   dialog:cancel(reason) (the caller's Backspace / ButtonB handler: UIController.pushBack), dialog:setBusy(on),
--   dialog:close(), dialog:primary() (the BUY to focus), dialog.root
-- The look: the scrim rgba(110,60,220,.4) over the whole layer, fading in over .2 s `ease` (a tap on it cancels,
-- H:456); the card 480 wide, its top 200 above the middle, padding 64 28 26, border 5, radius 30, #9775FF -> #6C47F5,
-- the 10 px lip, the inset 4 at .12 and the soft shadow 0 30 60 at .5 (the window shadow picture, R3), column gap 12,
-- popping in with sdPop .45 s cubic-bezier(.2,1.5,.4,1) (H:457); the medallion 130 at top -70, border 5, the radial
-- img.fx.radial.medallion (circle at 50% 35%, #FFF6C8 -> #FFC23A; its Theme.radial fallback while it has no id), the
-- 6 px lip, sticking in with sdStick .6 s after .05 s (the window sticker's frames, H:27), holding the item's picture
-- 100 with sdBob 2.4 s (H:458); the title 34 px stroke 7 drop 4 (the confirmTitle role, H:459); the description 16 px
-- #F3EDFF (H:460); the buttons row gap 12, margin-top 8 (H:461): CANCEL lilac flex 1, 62 + lip 5, 24 px stroke 5
-- (H:462), BUY green flex 1.4, 62 + lip 5, "BUY", the coin 30 and the price, 26 px stroke 6 (H:463-464), the spinner
-- while the server answers (H:465). It shrinks to fit a small screen (fit: the card and the medallion inside the
-- margin) and never covers less than the whole layer.
-- Behaviour: BUY ignores presses for guardMs after the dialog opens (ConfirmButton's double-press guard), then calls
-- onBuy once (the dialog turns busy until the caller closes it or calls setBusy(false)); CANCEL, the scrim and the
-- caller's back handler call onCancel(reason) ("cancel" / "scrim" / the caller's) and close it; nothing cancels while
-- busy. No sound of its own: BUY's click is silent (the purchase result plays ui.purchase, H:868) and the caller plays
-- the close sound (ui.back, H:886; UIController.back plays it for "back"); the design's whoosh has no sound [RL8].
-- The gamepad focus starts on BUY and stays inside the card (a SelectionGroup that stops at its edges).
-- Readings: the medallion's inset highlight (inset 0 5px 0 rgba(255,255,255,.6) on a circle) is not drawn; the
-- picture is a SquishyImage (spec.catalogId) or the caller's own picture (spec.picture, e.g. R7's box art).
-- Pure (unit-tested): initial(now), step(state, event, now, guardS?), balanceText(balance, price),
-- fit(canvas, cardHeight), flexWidths(rowWidth).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Client = UI.Parent
local Button = require(script.Parent.Button)
local CoinIcon = require(script.Parent.CoinIcon)
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local Layout = require(UI.Layout)
local SquishyImage = require(script.Parent.SquishyImage)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type Phase = "open" | "busy" | "closed"
export type State = { phase: Phase, openedAt: number }
export type Event = "buy" | "cancel" | "done"
export type Action = "buy" | "cancel" | "close" | "ignored"

export type Spec = {
	layer: Instance, -- a full-screen ScreenGui (Config.UI.confirm.layer) or a frame filling one
	title: string,
	description: string,
	price: number,
	catalogId: string?, -- the squishy's picture in the medallion
	picture: ((parent: Frame, sizePx: number) -> ())?, -- or the caller's own picture
	scale: number?, -- the UI scale of the layer's base px (UIController.scale); default 1
	trackScale: ((uiScale: UIScale) -> ())?, -- keeps the dialog's UIScale at the UI scale (UIController.trackScale)
	onBuy: () -> (), -- may yield; the dialog stays busy until close() or setBusy(false)
	onCancel: (reason: string) -> (),
}

export type ConfirmDialog = {
	root: Frame,
	buy: Button.Button,
	cancelButton: Button.Button,
	cancel: (self: ConfirmDialog, reason: string) -> (),
	setBusy: (self: ConfirmDialog, on: boolean) -> (),
	primary: (self: ConfirmDialog) -> GuiObject,
	isOpen: (self: ConfirmDialog) -> boolean,
	close: (self: ConfirmDialog) -> (),
	destroy: (self: ConfirmDialog) -> (),
}

-- Constants

local C = Config.UI.confirm
local CARD = C.card
local MEDAL = C.medallion
local BUTTONS = C.buttons
local LIP = Config.UI.Sticker.lip.button -- H:462-463: 0 5px 0 #1E1428
local STICK = Config.UI.Sticker.window.sticker -- H:27: sdStick's frames (the window sticker's)
local POP_FRAMES: any = Config.UI.motion.modalOpen.frames -- H:25: sdPop (its fade and tilt not drawn, plan §1.4 RL3)
local MEDALLION_KEY = "img.fx.radial.medallion"
local SHADOW_KEY = "img.fx.shadowWindow"
local BUY_ROLE = "buttonLarge" -- H:464: 26 px, stroke 6
local CANCEL_ROLE = "button" -- H:462: 24 px, stroke 5
local WHITE = Color3.new(1, 1, 1)

-- Module table

local ConfirmDialog = {}

-- Public: pure (unit-tested) -------------------------------------------------------------------------------------

-- A dialog that opened at clock `now`.
function ConfirmDialog.initial(now: number): State
	return { phase = "open", openedAt = now }
end

-- One step: "buy" (BUY pressed: spends once, after the guard), "cancel" (CANCEL, the scrim, Backspace / ButtonB),
-- "done" (the caller's answer arrived). `guardS` defaults to Config.UI.confirm.guardMs. Returns a new state and what
-- the step did.
function ConfirmDialog.step(state: State, event: Event, now: number, guardS: number?): (State, Action)
	local guard = guardS or C.guardMs / 1000
	local phase = state.phase
	if event == "buy" then
		if phase == "open" and now - state.openedAt >= guard - 1e-6 then -- 1e-6: float slack at exactly the guard
			return { phase = "busy", openedAt = state.openedAt }, "buy"
		end
		return state, "ignored"
	elseif event == "cancel" then
		if phase == "open" then
			return { phase = "closed", openedAt = state.openedAt }, "cancel"
		end
		return state, "ignored"
	elseif event == "done" then
		if phase ~= "closed" then
			return { phase = "closed", openedAt = state.openedAt }, "close"
		end
	end
	return state, "ignored"
end

-- "Balance after: {n}" (spend.balanceAfter, §11.5) for a `price` spent from `balance`, never below 0.
function ConfirmDialog.balanceText(balance: number, price: number): string
	local function whole(n: number): number
		return if n == n and n > -math.huge and n < math.huge then math.max(0, math.floor(n)) else 0
	end
	return Strings.format(
		Strings.spend.balanceAfter,
		{ balance = Format.coins(math.max(0, whole(balance) - whole(price))) }
	)
end

-- The fit on a layer `canvas` base px big for a card `cardHeight` tall (its face and lip): the scale k (at most 1)
-- that keeps the card and the medallion over it inside Config.UI.confirm.margin, and the card's top from the
-- layer's top: the design's (the middle + shiftY) kept on the screen.
function ConfirmDialog.fit(canvas: Vector2, cardHeight: number): (number, number)
	local m = C.margin
	local reach = -MEDAL.top
	local w = if canvas.X == canvas.X and canvas.X > 0 then canvas.X else CARD.width + 2 * m
	local h = if canvas.Y == canvas.Y and canvas.Y > 0 then canvas.Y else cardHeight + reach + 2 * m
	local k = math.clamp(math.min(1, (w - 2 * m) / CARD.width, (h - 2 * m) / (cardHeight + reach)), 0.05, 1)
	local low = m + reach * k
	local high = h - m - cardHeight * k
	local top = math.max(low, math.min(h / 2 + CARD.shiftY, high))
	return k, math.floor(top + 0.5)
end

-- The CANCEL and BUY widths in a buttons row `rowWidth` wide (flex 1 : 1.4, the gap between them, H:461-463).
function ConfirmDialog.flexWidths(rowWidth: number): (number, number)
	local free = math.max(0, rowWidth - BUTTONS.gap)
	local total = BUTTONS.cancelFlex + BUTTONS.buyFlex
	return free * BUTTONS.cancelFlex / total, free * BUTTONS.buyFlex / total
end

-- Private --------------------------------------------------------------------------------------------------------

-- A design surface as a foam face: `top` -> `bottom`, the ink border inside the box, the inset highlight and the lip.
local function sticker(
	frame: GuiObject,
	top: Color3,
	bottom: Color3,
	border: number,
	radius: number,
	lip: number,
	inset: { px: number, alpha: number }
)
	local bands = Layout.stickerBands(border, inset.px, 0, lip)
	Theme.foam(frame, {
		radius = radius,
		stroke = border,
		inner = true,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = { face = top, faceEnd = bottom, top = top:Lerp(WHITE, inset.alpha), drop = Theme.Colors.inkUI },
	})
end

-- `fn(u)` over `ms` after `delayMs` on the render phase, u eased by `curve` (u = 1 at the end; at once under
-- ReducedMotion for a fade).
local function run(c: Cleanup.Cleanup, ms: number, curve: string, fn: (u: number) -> ())
	if Tweens.reducedMotion() then
		fn(1)
		return
	end
	local ease = Tweens.curve(curve)
	local elapsed = 0
	fn(0)
	c:add(Scheduler.add(function(dt: number): boolean
		elapsed += dt
		local u = math.clamp(elapsed * 1000 / ms, 0, 1)
		fn(ease(u))
		return u < 1
	end, "render"))
end

-- Public -----------------------------------------------------------------------------------------------------------

function ConfirmDialog.open(spec: Spec): ConfirmDialog
	local c = Cleanup.new()
	local state = ConfirmDialog.initial(os.clock())
	local focusToken = Focus.capture()

	local root: Frame = Create("Frame", {
		Name = "SD_ConfirmDialog",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	})
	c:add(root)
	local uiScale: UIScale = Create("UIScale", { Scale = spec.scale or 1, Parent = root })
	if spec.trackScale then
		spec.trackScale(uiScale)
	end

	-- H:456: the scrim (a tap on it cancels).
	local scrim: TextButton = Create("TextButton", {
		Name = "Scrim",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = Palette.StickerScrimPurple,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		ZIndex = 1,
		Parent = root,
	})

	-- The card's height from its parts (H:457: padding 64 / 26, gap 12; the buttons row's margin 8 and face 62).
	local innerWidth = CARD.width - 2 * CARD.padX
	local titleHeight = Theme.textBounds(spec.title, "Name", nil, innerWidth).Y
	local descHeight = Theme.textBounds(spec.description, "Small", nil, innerWidth).Y
	local rowHeight = BUTTONS.marginTop + BUTTONS.face + LIP
	local cardHeight = CARD.padTop
		+ titleHeight
		+ CARD.gap
		+ descHeight
		+ CARD.gap
		+ rowHeight
		+ CARD.padBottom
		+ CARD.lip

	-- The fitted holder (its own UIScale k, its top at the fitted spot) with the soft shadow behind the card.
	local fit: Frame = Create("Frame", {
		Name = "Fit",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(CARD.width, cardHeight),
		Active = false,
		ZIndex = 2,
		Parent = root,
	})
	local fitScale: UIScale = Create("UIScale", { Parent = fit })
	local function place()
		local s = math.max(uiScale.Scale, 1e-3)
		local canvas = root.AbsoluteSize / s
		local k, top = ConfirmDialog.fit(canvas, cardHeight)
		fitScale.Scale = k
		fit.Position = UDim2.new(0.5, 0, 0, top)
	end
	c:add(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(place))
	c:add(uiScale:GetPropertyChangedSignal("Scale"):Connect(place))
	local shadow = CARD.shadow
	Theme.softShadow(fit, SHADOW_KEY, {
		offsetY = shadow.offsetY,
		blurPx = shadow.blurPx,
		alpha = shadow.alpha,
		color = Palette.StickerShadowWindow,
	})

	-- H:457: the card (the pose holder of its pop; Active, so a tap on it never reaches the scrim).
	local card: Frame = Create("Frame", {
		Name = "Card",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), -- sdPop scales about the centre
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Active = true,
		SelectionGroup = true,
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
		ZIndex = 1,
		Parent = fit,
	})
	sticker(card, Palette.StickerPillTop, Palette.StickerPillBottom, CARD.border, CARD.radius, CARD.lip, CARD.inset)
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = card,
	})
	Create("UIPadding", {
		PaddingTop = UDim.new(0, CARD.padTop),
		PaddingLeft = UDim.new(0, CARD.padX),
		PaddingRight = UDim.new(0, CARD.padX),
		PaddingBottom = UDim.new(0, CARD.padBottom + CARD.lip),
		Parent = content,
	})
	Theme.list(Enum.FillDirection.Vertical, CARD.gap, content, Enum.HorizontalAlignment.Center)
	local title = Theme.label({
		Name = "Title",
		Text = spec.title,
		Size = UDim2.fromScale(1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		Parent = content,
	}, "Name")
	Theme.stickerText(title, "confirmTitle") -- H:459
	local desc = Theme.label({
		Name = "Description",
		Text = spec.description,
		Size = UDim2.fromScale(1, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = content,
	}, "Small")
	Theme.stickerText(desc, "confirmDesc") -- H:460

	-- H:461: the buttons row (margin-top 8), CANCEL flex 1 and BUY flex 1.4.
	local row: Frame = Create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, rowHeight),
		LayoutOrder = 3,
		Parent = content,
	})
	local cancelWidth, buyWidth = ConfirmDialog.flexWidths(innerWidth)
	local self = {} :: ConfirmDialog

	local function finish()
		state = { phase = "closed", openedAt = state.openedAt }
		Focus.restore(focusToken)
		c:clean()
	end

	local cancelButton = Button.new({
		name = "Confirm_CancelButton",
		text = Strings.common.cancel,
		kind = "cancel", -- H:462: #C4B4F0 -> #9B86DB, inset 3 .3
		width = cancelWidth,
		height = BUTTONS.face,
		textRole = CANCEL_ROLE,
		clickSound = false, -- the caller plays ui.back (H:886)
		parent = row,
		onActivated = function()
			self:cancel("cancel")
		end,
	})
	c:add(cancelButton)
	cancelButton.root.Position = UDim2.fromOffset(0, BUTTONS.marginTop)

	local buy = Button.new({
		name = "Confirm_BuyButton",
		text = Format.coins(math.max(0, math.floor(spec.price))),
		kind = "primary", -- H:463: the green 3-stop, bevel 6 .15, highlight 3 .55
		width = buyWidth,
		height = BUTTONS.face,
		textRole = BUY_ROLE,
		keycap = "", -- reserves the row: "BUY", the coin and the price (H:464)
		clickSound = false, -- the purchase result plays ui.purchase (H:868)
		parent = row,
		onActivated = function()
			local nextState, action = ConfirmDialog.step(state, "buy", os.clock())
			state = nextState
			if action == "buy" then
				self:setBusy(true)
				spec.onBuy()
			end
		end,
	})
	c:add(buy)
	buy.root.Position = UDim2.fromOffset(cancelWidth + BUTTONS.gap, BUTTONS.marginTop)
	local line = buy.visual:FindFirstChild("Line", true)
	if line then
		local word = Theme.label({
			Name = "Word",
			Text = Button.displayText(Strings.shop.buy, "primary"),
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			TextWrapped = false,
			LayoutOrder = 1,
			Parent = line,
		}, "HudNumber")
		Theme.stickerText(word, BUY_ROLE)
		c:add(CoinIcon.new({ name = "Coin", sizePx = BUTTONS.coinPx, layoutOrder = 2, parent = line }))
	end

	-- H:458: the medallion over the card's top edge, its lip, the radial face, the item's picture bobbing in it.
	local medal: Frame = Create("Frame", {
		Name = "Medallion",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), -- sdStick turns and scales about the centre
		Position = UDim2.new(0.5, 0, 0, MEDAL.top + MEDAL.px / 2),
		Size = UDim2.fromOffset(MEDAL.px, MEDAL.px),
		ZIndex = 3,
		Parent = card,
	})
	local medalLip: Frame = Create("Frame", {
		Name = "Lip",
		BackgroundColor3 = Theme.Colors.inkUI,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, MEDAL.lip),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = medal,
	})
	Theme.corner(9999, medalLip)
	local face: Frame = Create("Frame", {
		Name = "Face",
		BackgroundColor3 = Palette.StickerGoldMid,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = medal,
	})
	Theme.corner(9999, face)
	Theme.radial(face, MEDALLION_KEY, {
		inner = Palette.StickerMedallionTop,
		outer = Palette.StickerGoldMid,
		centre = Vector2.new(0.5, MEDAL.centreY),
	})
	local ring: Frame = Create("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = medal,
	})
	Theme.corner(9999, ring)
	local ringStroke = Theme.stroke(Theme.Colors.inkUI, MEDAL.border, ring)
	pcall(function()
		(ringStroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner -- H:458 border-box
	end)
	local bob: Frame = Create("Frame", {
		Name = "SD_Bob",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(MEDAL.icon, MEDAL.icon),
		ZIndex = 3,
		Parent = medal,
	})
	if spec.catalogId then
		c:add(SquishyImage.new(spec.catalogId, { size = MEDAL.icon, parent = bob :: Instance }))
	elseif spec.picture then
		spec.picture(bob, MEDAL.icon)
	end
	local bobHandle = UiIdle.add(bob, "bob", { periodS = MEDAL.bobS })
	if bobHandle then
		c:add(function()
			bobHandle:remove()
		end)
	end

	-- Motion: the scrim fades in (H:456), the card pops (H:457), the medallion sticks on (H:458).
	run(c, C.fadeMs, C.fadeCurve, function(u: number)
		scrim.BackgroundTransparency = 1 - C.scrimAlpha * u
	end)
	c:add(Scheduler.add(Tweens.keyframes(card, POP_FRAMES, { ms = CARD.popMs, curve = CARD.popCurve }), "render"))
	c:add(Scheduler.add(
		Tweens.keyframes(medal, STICK.frames :: any, {
			ms = MEDAL.stickMs,
			delayMs = MEDAL.stickDelayMs,
			curve = MEDAL.stickCurve,
		}),
		"render"
	))

	c:add(scrim.Activated:Connect(function()
		self:cancel("scrim")
	end))

	self.root = root
	self.buy = buy
	self.cancelButton = cancelButton

	function self.cancel(_: ConfirmDialog, reason: string)
		local nextState, action = ConfirmDialog.step(state, "cancel", os.clock())
		state = nextState
		if action == "cancel" then
			finish()
			spec.onCancel(reason)
		end
	end

	function self.setBusy(_: ConfirmDialog, on: boolean)
		if state.phase == "closed" then
			return
		end
		state = { phase = if on then "busy" else "open", openedAt = state.openedAt }
		buy:setState(if on then "loading" else "normal") -- H:465: the spinner (CANCEL is ignored meanwhile)
	end

	function self.primary(_: ConfirmDialog): GuiObject
		return buy.root
	end

	function self.isOpen(_: ConfirmDialog): boolean
		return state.phase ~= "closed"
	end

	function self.close(_: ConfirmDialog)
		if state.phase ~= "closed" then
			finish()
		end
	end
	self.destroy = self.close

	root.Parent = spec.layer
	place()
	-- The gamepad starts on BUY once it is drawn (a selection must be rendered to take).
	task.defer(function()
		if state.phase ~= "closed" and Focus.isGamepad() then
			Focus.select(buy.root)
		end
	end)
	return self
end

return ConfirmDialog
