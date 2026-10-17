--!strict
-- CongratsOverlay (client only). UI FINAL R6 (plan work/ui/PLAN.md R6 G6.8, G6.9; `H:n` = "Squishy Duels HUD.dc.html"
-- line n; Config.UI.Shop.congrats): the design's congratulations overlay after a real squishy buy (H:536-549), full
-- screen in the confirm dialog's layer (Config.UI.confirm.layer: its own ScreenGui above SD_Modal, ScreenInsets None,
-- H:537 z 40). It replaces the shop.success toast for that case.
--   local overlay = CongratsOverlay.show({ layer = gui, catalogId = id, title = name, description = text,
--       scale = UIController.scale(), trackScale = UIController.trackScale, sound = play, onClose = fn })
--   overlay:close(quiet?) (tap anywhere, AWESOME!, or the caller's back handler: quiet, its own sound plays);
--   overlay.root;   overlay.button;   overlay:rain(n)
-- * The background (H:537): the exact radial picture img.fx.radial.congrats (ellipse at 50% 45%), else Theme.radial's
--   fallback with the design's stops and alphas (#FFD65A .92, #F58C1E .9 at 35%, #7828A0 .96), fading in over .3 s
--   `ease`; the rays (H:538): img.fx.raysCongrats 1600 px at (50%, 45%), white .28, sdSpin 20 s, else img.fx.raysReveal
--   at .28 (its own mask; the CSS mask 10% -> 60% is baked in the pack 2 picture).
-- * The column (H:537: centred, gap 10) at the UI scale: "CONGRATULATIONS!" a letter at a time (the congrats role,
--   82 px stroke 13 drop 6; sdSlam .6 s per letter, .05 + .035 i s, H:45, H:1005; a TextLabel cannot squash out of
--   shape: it plays the uniform part, plan §1.4), shrunk to fit the screen's width; the icon holder 240 (sdReveal .8 s
--   after .55 s, H:38) with the glow disc inset 10 (img.fx.radial.congratsDisc, else the glow picture, white .95 -> 0;
--   sdPulse 1.6 s) and the squishy 210 (SquishyImage, drop-shadow 0 10 .35; sdFloat 3 s after 1.2 s); "You got" (24 px
--   stroke 6, sdUp .45 s `ease` after .9 s), the title (the prize role: 52 px #FFE36B stroke 10 drop 6, sdUp .45 s
--   cubic-bezier(.2,1.4,.4,1) after 1 s), the description (19 px white, soft drop 0 2 .7, sdUp .45 s `ease` after
--   1.1 s) and AWESOME! (240 x 66 + lip 5, radius 20, margin-top 12, 30 px stroke 6, sdUp .45 s after 1.25 s; H:547).
--   Every delay and curve is Config.UI.Shop.congrats.
-- * Close (H:874-882): `sound("ui.pop")`, the whole overlay fades 1 -> 0 and grows 1 -> 1.08 over 220 ms (linear),
--   removed at 210 ms, then onClose. A close while closing does nothing.
-- * The rain (H:871) falls inside the overlay (UiFx.rain's parent: it goes with the overlay); rain() starts it.
-- Under ReducedMotion (PR9) nothing moves: the tracks keep only their fades, the loops rest, the rain and jolt draw
-- nothing (UiFx).
-- Pure (unit-tested): letters(text), fitScale(width, canvasWidth).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Button = require(script.Parent.Components.Button)
local Create = require(script.Parent.Create)
local Focus = require(script.Parent.Focus)
local SquishyImage = require(script.Parent.Components.SquishyImage)
local Theme = require(script.Parent.Theme)
local UiFx = require(script.Parent.UiFx)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type Letter = { char: string, delayS: number }

export type Spec = {
	layer: Instance, -- a full-screen ScreenGui (Config.UI.confirm.layer)
	catalogId: string?, -- the squishy bought (nil: no picture, tests)
	title: string,
	description: string,
	scale: number?, -- the UI scale (UIController.scale); default 1
	trackScale: ((uiScale: UIScale) -> ())?, -- keeps the column's UIScale at the UI scale
	sound: ((key: string) -> ())?, -- the caller's sound hook (a component never requires a controller)
	onClose: (() -> ())?,
}

export type CongratsOverlay = {
	root: TextButton,
	button: Button.Button,
	rain: (self: CongratsOverlay, n: number) -> (),
	close: (self: CongratsOverlay, quiet: boolean?) -> (),
	isOpen: (self: CongratsOverlay) -> boolean,
	destroy: (self: CongratsOverlay) -> (),
}

-- Constants

local CG = Config.UI.Shop.congrats
local LIP = Config.UI.Sticker.lip.button -- H:547: 0 5px 0 #1E1428
local RADIAL_KEY = "img.fx.radial.congrats"
local DISC_KEY = "img.fx.radial.congratsDisc"
local RAYS_KEY = "img.fx.raysCongrats"
local RAYS_FALLBACK_KEY = "img.fx.raysReveal"
local WHITE = Color3.new(1, 1, 1)

-- Module table

local CongratsOverlay = {}

-- Public: pure (unit-tested) -------------------------------------------------------------------------------------

-- The letters of `text` with their sdSlam delays (H:1005: .05 + .035 i s, i from 0).
function CongratsOverlay.letters(text: string): { Letter }
	local out: { Letter } = {}
	for _, code in utf8.codes(text) do
		table.insert(out, { char = utf8.char(code), delayS = CG.letters.delayS + CG.letters.staggerS * #out })
	end
	return out
end

-- The letters row's scale: 1 while `width` fits the canvas less the margins, else what makes it fit.
function CongratsOverlay.fitScale(width: number, canvasWidth: number): number
	local room = canvasWidth - 2 * CG.margin
	if not (width > 0) or not (room > 0) then
		return 1
	end
	return math.min(1, room / width)
end

-- Private --------------------------------------------------------------------------------------------------------

-- A laid-out slot `w` x `h` holding a pose holder (the design's animated element: a layout never places it).
local function slot(parent: Instance, name: string, order: number, w: number, h: number): (Frame, Frame)
	local holder: Frame = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, h),
		LayoutOrder = order,
		Parent = parent,
	})
	local pose: Frame = Create("Frame", {
		Name = "Pose",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	})
	return holder, pose
end

-- `fn(u)` from 0 to 1 over `ms` after `delayS`, eased by `curve` (at once under ReducedMotion).
local function run(c: Cleanup.Cleanup, ms: number, delayS: number, curve: string, fn: (u: number) -> ())
	fn(0)
	if Tweens.reducedMotion() then
		fn(1)
		return
	end
	local ease = Tweens.curve(curve)
	local elapsed = -delayS
	c:add(Scheduler.add(function(dt: number): boolean
		elapsed += dt
		local u = math.clamp(elapsed * 1000 / ms, 0, 1)
		fn(ease(u))
		return u < 1
	end, "render"))
end

-- A text in its role, in a slot as big as the text (wrapped inside `wrapWidth`), rising in with sdUp (H:44).
local function riseText(
	c: Cleanup.Cleanup,
	parent: Instance,
	name: string,
	order: number,
	text: string,
	role: string,
	wrapWidth: number,
	spec: { delayS: number, curve: string }
): TextLabel
	local kind = (Theme.Sticker.text[role] :: any).kind
	local bounds = Theme.textBounds(text, kind, nil, wrapWidth)
	local _, pose = slot(parent, name, order, math.ceil(bounds.X) + 4, math.ceil(bounds.Y))
	local label = Theme.label({
		Name = "Text",
		Text = text,
		AnchorPoint = Vector2.new(0.5, 0.5), -- sdUp's move about the centre
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = pose,
	}, kind)
	Theme.stickerText(label, role)
	local up = CG.up
	c:add(
		Scheduler.add(
			Tweens.keyframes(label, up.frames :: any, { ms = up.ms, delayMs = spec.delayS * 1000, curve = spec.curve }),
			"render"
		)
	)
	return label
end

-- Public -----------------------------------------------------------------------------------------------------------

function CongratsOverlay.show(spec: Spec): CongratsOverlay
	local c = Cleanup.new()
	local scale = spec.scale or 1
	local closing = false
	local open = true
	local focusToken = Focus.capture()

	-- H:537: the whole screen (a tap anywhere closes it); the close's grow is its UIScale about the middle.
	local root: TextButton = Create("TextButton", {
		Name = "SD_Congrats",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Selectable = false,
		ClipsDescendants = true,
		ZIndex = 1,
	})
	c:add(root)
	local grow: UIScale = Create("UIScale", { Parent = root })
	root.Parent = spec.layer -- first, so the texts measure against the screen
	local background: Frame = Create("Frame", {
		Name = "Background",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = 1,
		Parent = root,
	})
	local alphas = CG.alphas
	Theme.radial(background, RADIAL_KEY, {
		inner = Palette.StickerCongratsTop,
		mid = Palette.StickerCongratsMid,
		midAt = alphas.midAt,
		outer = Palette.StickerCongratsEnd,
		innerAlpha = alphas.top,
		midAlpha = alphas.mid,
		outerAlpha = alphas.outer,
		centre = Vector2.new(0.5, CG.centreY),
	})
	local rays = CG.rays
	local raysKey = if AssetTable.image(RAYS_KEY) then RAYS_KEY else RAYS_FALLBACK_KEY
	Theme.rays(background, raysKey, math.round(rays.px * scale), rays.alpha, rays.spinS, rays.centreY)
	local backgroundFade = Tweens.fadeGroup(background)
	run(c, CG.fadeMs, 0, CG.fadeCurve, function(u: number)
		backgroundFade:setAlpha(u)
	end)

	-- H:537: the column, centred, at the UI scale.
	local column: Frame = Create("Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = 2,
		Parent = root,
	})
	local columnScale: UIScale = Create("UIScale", { Scale = scale, Parent = column })
	if spec.trackScale then
		spec.trackScale(columnScale)
	end
	Theme.list(Enum.FillDirection.Vertical, CG.gap, column, Enum.HorizontalAlignment.Center)

	-- H:539: the letters, each slamming in on its own delay.
	local row: Frame = Create("Frame", {
		Name = "Letters",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 1,
		Parent = column,
	})
	Theme.list(Enum.FillDirection.Horizontal, 0, row)
	local rowScale: UIScale = Create("UIScale", { Parent = row })
	local rowWidth = 0
	local slam = CG.letters
	for index, letter in CongratsOverlay.letters(Strings.shop.congratsTitle) do
		local size = Theme.textBounds(letter.char, "Congrats")
		rowWidth += size.X
		local _, pose = slot(row, "Letter" .. index, index, size.X, size.Y)
		local label = Theme.label({
			Name = "Text",
			Text = letter.char,
			AnchorPoint = Vector2.new(0.5, 0.5), -- sdSlam scales and turns about the centre
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = pose,
		}, "Congrats")
		Theme.stickerText(label, "congrats")
		c:add(
			Scheduler.add(
				Tweens.keyframes(
					label,
					slam.frames :: any,
					{ ms = slam.slamMs, delayMs = letter.delayS * 1000, curve = slam.curve }
				),
				"render"
			)
		)
	end
	local function fitLetters()
		local canvas = root.AbsoluteSize.X / math.max(columnScale.Scale, 1e-3)
		rowScale.Scale = if canvas > 0 then CongratsOverlay.fitScale(rowWidth, canvas) else 1
	end
	c:add(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitLetters))

	-- H:540-543: the icon holder, its glow disc and the squishy.
	local icon = CG.icon
	local _, reveal = slot(column, "Icon", 2, icon.holder, icon.holder)
	local disc: Frame = Create("Frame", {
		Name = "Disc",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * icon.glowInset, 1, -2 * icon.glowInset),
		Parent = reveal,
	})
	Theme.corner(9999, disc)
	Theme.radial(disc, DISC_KEY, { inner = WHITE, outer = WHITE, innerAlpha = icon.glowAlpha, outerAlpha = 0 })
	local pulse = UiIdle.add(disc, "pulse", { periodS = icon.pulseS })
	local float: Frame = Create("Frame", {
		Name = "Float",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(icon.size, icon.size),
		Parent = reveal,
	})
	if spec.catalogId then
		c:add(SquishyImage.new(spec.catalogId, { size = icon.size, shadow = icon.shadow, parent = float :: Instance }))
	end
	local floating = UiIdle.add(float, "float", { periodS = icon.floatS, delayS = icon.floatDelayS })
	for _, handle in { pulse, floating } do
		if handle then
			c:add(function()
				handle:remove()
			end)
		end
	end
	c:add(Scheduler.add(
		Tweens.keyframes(reveal, icon.frames :: any, {
			ms = icon.revealMs,
			delayMs = icon.revealDelayS * 1000,
			curve = icon.revealCurve,
		}),
		"render"
	))

	-- H:544-546: "You got", the title and the description.
	local wrapWidth = math.max(1, root.AbsoluteSize.X / math.max(scale, 1e-3) - 2 * CG.margin)
	if wrapWidth <= 1 then
		wrapWidth = Config.UI.Scale.referenceWidth - 2 * CG.margin
	end
	riseText(c, column, "YouGot", 3, Strings.shop.youGot, CG.youGot.textRole, wrapWidth, CG.youGot)
	riseText(c, column, "Title", 4, spec.title, CG.title.textRole, wrapWidth, CG.title)
	riseText(c, column, "Description", 5, spec.description, CG.desc.textRole, wrapWidth, CG.desc)

	-- H:547: AWESOME!, 12 px further down, rising in (its fade follows the same run).
	local b = CG.button
	local _, buttonPose = slot(column, "Awesome", 6, b.width, b.marginTop + b.face + LIP)
	local self = {} :: CongratsOverlay
	local button = Button.new({
		name = "Shop_AwesomeButton",
		text = Strings.shop.awesome,
		kind = "primary", -- H:547: the green 3-stop, bevel 6 .15, highlight 3 .55
		width = b.width,
		height = b.face,
		radius = b.radius, -- P12: the design's 20
		textRole = "awesome", -- H:547: 30 px, stroke 6
		clickSound = false, -- the close plays ui.pop (H:877)
		parent = buttonPose,
		onActivated = function()
			self:close()
		end,
	})
	c:add(button)
	button.root.Position = UDim2.fromOffset(0, b.marginTop)
	local buttonFade = Tweens.fadeGroup(buttonPose)
	local up = CG.up
	c:add(
		Scheduler.add(
			Tweens.keyframes(buttonPose, up.frames :: any, { ms = up.ms, delayMs = b.delayS * 1000, curve = b.curve }),
			"render"
		)
	)
	run(c, up.ms, b.delayS, b.curve, function(u: number)
		buttonFade:setAlpha(math.clamp(u, 0, 1))
	end)

	c:add(root.Activated:Connect(function()
		self:close()
	end))

	self.root = root
	self.button = button

	function self.rain(_: CongratsOverlay, n: number)
		if open and not closing then
			UiFx.rain(n, nil, root)
		end
	end

	function self.close(_: CongratsOverlay, quiet: boolean?)
		if closing or not open then
			return
		end
		closing = true
		if spec.sound and not quiet then
			spec.sound("ui.pop") -- H:877
		end
		local fade = Tweens.fadeGroup(root)
		run(c, CG.closeMs, 0, "linear", function(u: number)
			fade:setAlpha(1 - u)
			grow.Scale = 1 + (CG.closeScale - 1) * u
		end)
		task.delay(CG.removeMs / 1000, function()
			open = false
			Focus.restore(focusToken)
			c:clean()
			if spec.onClose then
				spec.onClose()
			end
		end)
	end

	function self.isOpen(_: CongratsOverlay): boolean
		return open and not closing
	end

	function self.destroy(_: CongratsOverlay)
		if open then
			open = false
			Focus.restore(focusToken)
			c:clean()
		end
	end

	fitLetters()
	task.defer(function()
		if open and not closing and Focus.isGamepad() then
			Focus.select(button.root)
		end
	end)
	return self
end

return CongratsOverlay
