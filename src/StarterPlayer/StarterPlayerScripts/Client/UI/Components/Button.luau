--!strict
-- Button (client only). DESIGN §11.1 (UI/Components), §9.13 (button states), §11.2 (touch targets), §11.4 (focus),
-- §18.5.2 B3 (feel pass: springy release, sounds, the "no" wiggle, pulse, decorate); the foam UI restyle (spec
-- 2026-10-09, API guide docs/superpowers/specs/2026-10-09-foam-ui-components.md).
--   local button = Button.new({ name = "Queue_CancelButton", text = Strings.common.cancel, onActivated = fn })
--   button:setState("disabled", reasonText) / "loading" / "normal";   button:pulse(0.94, 60, 140);   button:destroy()
--   local feel = Button.decorate(plainGuiButton, { sound = false })   -- the same press feel on a plain button
--   Button.setSoundHook(function(key) SoundController.play(key) end) -- UIController.init (a component never requires
--                                                                       a controller)
-- Kinds (foam surfaces, Theme.foam: a face, a white top highlight, a bottom bevel shade band and a bottom InkUI drop
-- band, the InkUI 2.5 outline; see Button.style(kind)):
--   primary    Strawberry (or spec.accent), radius 16, bands 2 / 5 / 3, height 56; the label outlined white (the rule)
--   secondary  Frosting, the same shape, InkUI label (the default kind)
--   tile       an accent face (spec.accent, default Strawberry), radius 20, bands 2 / 6 / 4, a fixed TILE_SIZE square
--              unless width / height are given: the icon (spec.icon) above the label (Chip kind by default: InkUI by
--              the rule; textKind "Button" for an outlined white label, which needs a wider tile), an optional count badge
--   cta        the big call to action (the Duel button): Strawberry, radius 22, bands 2 / 7 / 5, height CTA_HEIGHT
-- Optional parts (any kind): spec.icon (UI/Components/IconGlyph; above the label on a tile, left of it otherwise),
-- spec.keycap (UI/Components/Keycap, left of the icon; the caller hides it on touch with setKeycap(nil)), spec.subtext
-- (a Chip-kind line under the label, e.g. the CTA's "Join the queue") and spec.badge (UI/Components/CountBadge on the
-- top-right corner, setBadge). A non-tile button with an icon, a keycap or a subtext lays them out in one row ("Line");
-- pass keycap = "" / subtext = "" to reserve a part that starts hidden.
-- States:
--   normal    hover: scale 1.04 in 80 ms, face +8%; pressed: scale 0.92 in 60 ms, face -10%; release: a spring
--             (Util/Spring, Config.UI.motion.buttonRelease.spring: ω 20, ζ 0.35, ≈ 2.5% overshoot, under 3 Hz) from the
--             current scale to 1 (1.04 while hovered), a Scheduler render effect; buttonRelease.ms with Back Out is the
--             fallback when no spring is configured. The whole foam stack is the root, so it scales with the press.
--   focused   (gamepad selection) the custom focus ring (UI/Focus, concentric with the kind's corners) + scale 1.04
--   disabled  the disabled foam (face #E9E1D6, outline #A79FAB, shade #D9CFC2, no ink drop), the label in DisabledText,
--             PLUS a reason text in Ink2 (4.65:1) under the label; still selectable so a gamepad user can read it;
--             Activated is ignored, but a press plays ui.error and a "no" wiggle (the label moves ±wigglePx, `cycles`
--             times over buttonError.ms, fading out)
--   loading   the label (or the row) is replaced by a 3-dot spinner; not activatable (and silent)
-- Sounds go through the hook (§18.6): ui.click on Activated (after onActivated ran, so UIController can keep one sound
-- per action), ui.hover on MouseEnter (mouse only), ui.error on a disabled press. spec.sound = false silences the
-- click and hover of a button that opens a screen (ui.open plays instead); the disabled ui.error still plays.
-- pulse(scale, downMs, upMs): to `scale` over downMs (Quad Out), back over upMs (Back Out) (the squeeze echo, A2; the
-- coin pill bounce, B1).
-- Under ReducedMotion (Anim/Tweens.reducedMotion) every scale effect, pulse and wiggle is off and the spinner dots stay
-- still; the colour feedback and the sounds stay. Sizes are base px under the ScreenGui UIScale; the height is raised to
-- the touch minimum (Config.UI.Touch.minTarget). The bands are inside the button's box; the content is raised by half
-- of them so it sits centred on the face. The root keeps the stable test name given in spec.name (§2.11
-- `<Screen>_<Action>Button`); its text parts keep the names Label and Reason.
-- Part 8: Button.widthFor(text, reason?, textKind?, kind?) is the width (base px) an automatic-width Button with that
-- label (and disabled reason line) takes: the wider text (Theme.textWidth, the player's text size) plus the kind's side
-- padding and MEASURE_MARGIN_PX, so a layout that wraps or pins buttons from it never lets two of them touch.
-- button:setWidth(px?) switches between a fixed width (the label and reason wrap inside it; the caller sets the height
-- through root.Size) and the automatic width (nil), e.g. the shop's Buy in a narrow column at a large text size.
-- Button.PADDING_X is the side padding inside the primary / secondary kinds (base px).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Spring = require(Shared.Util.Spring)

local UI = script.Parent.Parent
local Client = UI.Parent
local CountBadge = require(script.Parent.CountBadge)
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local IconGlyph = require(script.Parent.IconGlyph)
local Keycap = require(script.Parent.Keycap)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Kind = "primary" | "secondary" | "tile" | "cta"
export type State = "normal" | "disabled" | "loading"
export type SoundHook = (key: string) -> ()

export type Spec = {
	name: string,
	text: string,
	kind: Kind?,
	accent: Theme.AccentName?, -- the face; default per kind (primary / tile / cta Strawberry, secondary Frosting)
	width: number?, -- base px; nil = automatic width (a tile: TILE_SIZE)
	height: number?, -- base px; raised to Config.UI.Touch.minTarget
	textKind: Theme.TextKind?, -- default "Button" ("Chip" on a tile)
	onActivated: () -> (),
	layoutOrder: number?,
	parent: Instance?,
	sound: boolean?, -- false: no click / hover sound (a button that opens a screen; ui.open plays instead)
	icon: string?, -- an IconGlyph name
	iconSize: number?, -- base px; default per kind
	keycap: string?, -- a key prompt left of the label ("" = reserved, hidden)
	subtext: string?, -- a second line under the label ("" = reserved, hidden)
	badge: number?, -- a count on the top-right corner (nil / 0 = hidden)
}

export type Button = {
	root: TextButton,
	setText: (self: Button, text: string) -> (),
	setState: (self: Button, state: State, reason: string?) -> (),
	getState: (self: Button) -> State,
	pulse: (self: Button, scale: number, downMs: number, upMs: number) -> (),
	setWidth: (self: Button, widthPx: number?) -> (),
	setAccent: (self: Button, accent: Theme.AccentName) -> (),
	setIcon: (self: Button, icon: string) -> (),
	setKeycap: (self: Button, text: string?) -> (),
	setSubtext: (self: Button, text: string?) -> (),
	setBadge: (self: Button, count: number?) -> (),
	destroy: (self: Button) -> (),
}

-- The shape of a kind (base px).
export type Style = {
	accent: Theme.AccentName,
	radius: number,
	top: number, -- the foam bands (Theme.Foam)
	bevel: number,
	drop: number,
	paddingX: number, -- side padding inside the button
	height: number, -- the default height
	iconPx: number, -- the default icon size
}

export type DecorateOptions = {
	sound: boolean?, -- false: no click / hover sound (default true)
}

export type Decorated = {
	pulse: (self: Decorated, scale: number, downMs: number, upMs: number) -> (),
	destroy: (self: Decorated) -> (),
}

-- The press feel shared by Button.new and Button.decorate.
type Feel = {
	scale: UIScale,
	hovered: boolean,
	pressed: boolean,
	focused: boolean,
	refresh: (animate: boolean) -> (),
	pulse: (peak: number, downMs: number, upMs: number) -> (),
	stop: () -> (),
}

-- Constants

local MOTION = Config.UI.motion
local TOUCH = Config.UI.Touch
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local SPINNER_DOTS = 3
local SPINNER_DOT_PX = 8
-- reading (DESIGN gives no spinner timing): one dot after another, a full cycle per second (well under 3 Hz).
local SPINNER_CYCLE_SECONDS = 1
local HORIZONTAL_PADDING = 18
-- reading: added to a measured width (TextService rounding, the focus / hover scale) so laid-out buttons never touch
local MEASURE_MARGIN_PX = 4
local SETTLE_EPSILON = 0.001 -- the release spring is done when scale and speed are this close to rest
local MS = 1000
local SOUND_CLICK = "ui.click"
local SOUND_HOVER = "ui.hover"
local SOUND_ERROR = "ui.error"
local MOUSE_INPUTS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseMovement] = true,
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
	[Enum.UserInputType.MouseWheel] = true,
}
-- Foam kinds (readings where the spec gives no number: the tile is the design's 100 px tile ÷ 1.25 plus room for a
-- Chip label at the default text size; the CTA is the design's 116 px ÷ 1.25; its radius is the panel token).
local TILE_SIZE = 84
local TILE_PADDING_X = 6
local CTA_HEIGHT = 92
local CTA_PADDING_X = 22
local LINE_GAP = 8 -- between the keycap, the icon and the texts in a row
local TILE_GAP = 2 -- between a tile's icon and its label
local BADGE_INSET = 5 -- the badge's centre, inside the top-right corner
local STYLES: { [string]: Style } = {
	primary = {
		accent = "strawberry",
		radius = Theme.Radius.button,
		top = Theme.Foam.button.top,
		bevel = Theme.Foam.button.bevel,
		drop = Theme.Foam.button.drop,
		paddingX = HORIZONTAL_PADDING,
		height = TOUCH.primaryButton,
		iconPx = 24,
	},
	secondary = {
		accent = "frosting",
		radius = Theme.Radius.button,
		top = Theme.Foam.button.top,
		bevel = Theme.Foam.button.bevel,
		drop = Theme.Foam.button.drop,
		paddingX = HORIZONTAL_PADDING,
		height = TOUCH.primaryButton,
		iconPx = 24,
	},
	tile = {
		accent = "strawberry",
		radius = Theme.Radius.tile,
		top = Theme.Foam.tile.top,
		bevel = Theme.Foam.tile.bevel,
		drop = Theme.Foam.tile.drop,
		paddingX = TILE_PADDING_X,
		height = TILE_SIZE,
		iconPx = 36,
	},
	cta = {
		accent = "strawberry",
		radius = Theme.Radius.panel,
		top = Theme.Foam.cta.top,
		bevel = Theme.Foam.cta.bevel,
		drop = Theme.Foam.cta.drop,
		paddingX = CTA_PADDING_X,
		height = CTA_HEIGHT,
		iconPx = 44,
	},
}
for _, style in STYLES do
	table.freeze(style)
end

-- Module table

local Button = {}

Button.PADDING_X = HORIZONTAL_PADDING
Button.TILE_SIZE = TILE_SIZE
Button.CTA_HEIGHT = CTA_HEIGHT

-- Private

local log = Log.new("Button")
local soundHook: SoundHook? = nil

local function playSound(key: string)
	local hook = soundHook
	if hook == nil then
		return
	end
	local ok, err = pcall(function(): any
		hook(key)
		return nil
	end)
	if not ok then
		log:warn(`sound hook failed for {key}:`, err)
	end
end

-- "Mouse only" (§18.5.2 B3): a tap on a touch screen also fires MouseEnter; its last input is Touch.
local function lastInputIsMouse(): boolean
	local ok, kind = pcall(function(): Enum.UserInputType
		return UserInputService:GetLastInputType()
	end)
	return ok and MOUSE_INPUTS[kind] == true
end

local function ease(alpha: number, style: Enum.EasingStyle, direction: Enum.EasingDirection): number
	return TweenService:GetValue(math.clamp(alpha, 0, 1), style, direction)
end

-- The press feel of one GuiButton: hover / press tweens, the springy release and pulses on one UIScale, never more than
-- one tween or effect at a time. `interactive()` says whether hover and press scales apply (a normal Button).
local function newFeel(root: GuiButton, cleanup: Cleanup.Cleanup, interactive: () -> boolean): Feel
	local scale: UIScale = Create("UIScale", { Name = "Scale", Parent = root })
	local tween: Tween? = nil
	local motion: Scheduler.Handle? = nil
	local feel = {} :: Feel
	feel.scale = scale
	feel.hovered, feel.pressed, feel.focused = false, false, false

	local function stop()
		Tweens.cancel(tween)
		tween = nil
		if motion then
			motion:disconnect()
			motion = nil
		end
	end
	feel.stop = stop
	cleanup:add(stop)

	local function target(): number
		local live = interactive()
		if live and feel.pressed then
			return MOTION.buttonPressed.scale
		elseif live and (feel.hovered or feel.focused) then
			return MOTION.buttonHover.scale
		elseif feel.focused then
			return MOTION.focus.scale
		end
		return 1
	end

	local function tweenTo(goal: number, ms: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
		stop()
		if Tweens.reducedMotion() then
			scale.Scale = 1
			return
		end
		tween = Tweens.play(scale, ms, { Scale = goal }, style, direction)
	end

	local function springTo(goal: number)
		local spec = MOTION.buttonRelease.spring
		if spec == nil then
			tweenTo(goal, MOTION.buttonRelease.ms, MOTION.buttonRelease.style, MOTION.buttonRelease.direction)
			return
		end
		stop()
		if Tweens.reducedMotion() then
			scale.Scale = 1
			return
		end
		local spring = Spring.new(scale.Scale, spec.omega, spec.zeta, goal)
		motion = Scheduler.add(function(dt: number): boolean
			scale.Scale = spring:step(dt)
			if spring:isSettled(SETTLE_EPSILON) then
				scale.Scale = goal
				motion = nil
				return false
			end
			return true
		end, "render")
	end

	function feel.refresh(animate: boolean)
		local goal = target()
		if animate and feel.pressed then
			tweenTo(goal, MOTION.buttonPressed.ms)
		elseif animate then
			springTo(goal)
		else
			tweenTo(goal, MOTION.buttonHover.ms)
		end
	end

	function feel.pulse(peak: number, downMs: number, upMs: number)
		stop()
		if Tweens.reducedMotion() then
			scale.Scale = 1
			return
		end
		local from = scale.Scale
		local down = math.max(0, downMs) / MS
		local up = math.max(0, upMs) / MS
		local elapsed = 0
		motion = Scheduler.add(function(dt: number): boolean
			elapsed += dt
			local goal = target()
			if elapsed < down then
				scale.Scale = from
					+ (peak - from) * ease(elapsed / down, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				return true
			elseif elapsed < down + up then
				local alpha = ease((elapsed - down) / up, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				scale.Scale = peak + (goal - peak) * alpha
				return true
			end
			scale.Scale = goal
			motion = nil
			return false
		end, "render")
	end

	return feel
end

-- Public

-- Installs the function every Button plays its sounds through (UIController.init); nil removes it.
function Button.setSoundHook(fn: SoundHook?)
	soundHook = fn
end

-- The shape of a kind (an unknown kind gives "secondary").
function Button.style(kind: Kind?): Style
	return STYLES[kind or "secondary"] or STYLES.secondary
end

-- The width (base px) of an automatic-width Button of `kind` (default "secondary") showing `text` (in `textKind`,
-- default "Button") and, when given, the disabled `reason` line (Small) under it, at the player's text size: the wider
-- of the two, the kind's side padding and MEASURE_MARGIN_PX.
function Button.widthFor(text: string, reason: string?, textKind: Theme.TextKind?, kind: Kind?): number
	local width = Theme.textWidth(text, textKind or "Button")
	if reason and reason ~= "" then
		width = math.max(width, Theme.textWidth(reason, "Small"))
	end
	return math.ceil(width) + 2 * Button.style(kind).paddingX + MEASURE_MARGIN_PX
end

-- Gives a plain GuiButton (e.g. the coin pill) the Button press feel: hover 1.04, press 0.92, the springy release,
-- pulse(), and ui.click / ui.hover unless options.sound == false. The returned handle's destroy() removes it all.
function Button.decorate(guiButton: GuiButton, options: DecorateOptions?): Decorated
	local cleanup = Cleanup.new()
	local soundOn = not (options and options.sound == false)
	local feel = newFeel(guiButton, cleanup, function(): boolean
		return true
	end)
	cleanup:add(feel.scale)
	cleanup:add(guiButton.MouseEnter:Connect(function()
		feel.hovered = true
		feel.refresh(false)
		if soundOn and lastInputIsMouse() then
			playSound(SOUND_HOVER)
		end
	end))
	cleanup:add(guiButton.MouseLeave:Connect(function()
		feel.hovered, feel.pressed = false, false
		feel.refresh(false)
	end))
	cleanup:add(guiButton.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			feel.pressed = true
			feel.refresh(true)
		end
	end))
	cleanup:add(guiButton.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			feel.pressed = false
			feel.refresh(true)
		end
	end))
	cleanup:add(guiButton.SelectionGained:Connect(function()
		feel.focused = true
		feel.refresh(false)
	end))
	cleanup:add(guiButton.SelectionLost:Connect(function()
		feel.focused = false
		feel.refresh(false)
	end))
	if soundOn then
		-- Deferred one resumption cycle, so the pill's own Activated handler (connected earlier or later) runs first and
		-- UIController can keep one sound per action.
		cleanup:add(guiButton.Activated:Connect(function()
			task.defer(playSound, SOUND_CLICK)
		end))
	end

	local self = {} :: Decorated
	function self.pulse(_: Decorated, peak: number, downMs: number, upMs: number)
		feel.pulse(peak, downMs, upMs)
	end
	function self.destroy(_: Decorated)
		cleanup:clean()
	end
	return self
end

function Button.new(spec: Spec): Button
	local cleanup = Cleanup.new()
	local kind: Kind = spec.kind or "secondary"
	local style = Button.style(kind)
	local tile = kind == "tile"
	local accent = Theme.accent(spec.accent or style.accent)
	local fixedWidth: number? = spec.width or (if tile then TILE_SIZE else nil)
	local height = math.max(spec.height or style.height, TOUCH.minTarget)
	local soundOn = spec.sound ~= false
	-- The content is raised by half the bands so it sits centred on the face.
	local shift = (style.bevel + style.drop - style.top) / 2
	local inLine = not tile and (spec.icon ~= nil or spec.keycap ~= nil or spec.subtext ~= nil)

	local root: TextButton = Create("TextButton", {
		Name = spec.name,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(fixedWidth or 0, height),
		AutomaticSize = if fixedWidth then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	local foam = Theme.foam(root, {
		radius = style.radius,
		top = style.top,
		bevel = style.bevel,
		drop = style.drop,
		colors = Theme.accentColors(spec.accent or style.accent, true),
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, style.paddingX),
		PaddingRight = UDim.new(0, style.paddingX),
		Parent = root,
	})

	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, -shift),
		Size = UDim2.fromScale(if fixedWidth then 1 else 0, 1),
		AutomaticSize = if fixedWidth then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Vertical, if tile then TILE_GAP else 0, content)

	-- A row (keycap, icon, the label over the subtext) for a non-tile button with any of those parts.
	local line: Frame? = nil
	local texts: Frame? = nil
	if inLine then
		local row: Frame = Create("Frame", {
			Name = "Line",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			LayoutOrder = 1,
			Parent = content,
		})
		Theme.list(Enum.FillDirection.Horizontal, LINE_GAP, row)
		texts = Create("Frame", {
			Name = "Texts",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			LayoutOrder = 3,
			Parent = row,
		})
		Theme.list(Enum.FillDirection.Vertical, 0, texts, Enum.HorizontalAlignment.Left)
		line = row
	end

	local icon: IconGlyph.IconGlyph? = nil
	if spec.icon then
		icon = IconGlyph.new({
			name = "Icon",
			icon = spec.icon,
			sizePx = spec.iconSize or style.iconPx,
			layoutOrder = if tile then 0 else 2,
			parent = if tile then content else line,
		})
		cleanup:add(icon)
	end
	local keycap: Keycap.Keycap? = nil
	if spec.keycap ~= nil and line then
		keycap = Keycap.new({ name = "Keycap", text = spec.keycap, layoutOrder = 1, parent = line })
		cleanup:add(keycap)
	end

	-- An automatic-width button grows to its text, so its lines never wrap: wrapped, a fractional UIScale (0.85 on
	-- phones) rounded the automatic width a pixel short and pushed the last letter onto a second line ("Cance / l" on
	-- the queue pill, Part 8 UI shots). A fixed-width button still wraps inside its width (a row never wraps).
	local wraps = fixedWidth ~= nil and not inLine
	local label = Theme.label({
		Name = "Label",
		Text = spec.text,
		LayoutOrder = 1,
		Size = UDim2.fromScale(if wraps then 1 else 0, 0),
		AutomaticSize = if wraps then Enum.AutomaticSize.Y else Enum.AutomaticSize.XY,
		TextXAlignment = if inLine then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		TextWrapped = wraps,
		Parent = texts or content,
	}, spec.textKind or (if tile then "Chip" else "Button"))
	local subLabel: TextLabel? = nil
	if spec.subtext ~= nil and texts then
		subLabel = Theme.label({
			Name = "Subtext",
			Text = spec.subtext,
			Visible = spec.subtext ~= "",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = false,
			Parent = texts,
		}, "Chip")
	end
	local reasonWraps = fixedWidth ~= nil
	local reasonLabel = Theme.label({
		Name = "Reason",
		Text = "",
		Visible = false,
		LayoutOrder = 2,
		Size = UDim2.fromScale(if reasonWraps then 1 else 0, 0),
		AutomaticSize = if reasonWraps then Enum.AutomaticSize.Y else Enum.AutomaticSize.XY,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = reasonWraps,
		Parent = content,
	}, "Small")

	local spinner: Frame = Create("Frame", {
		Name = "Spinner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -shift),
		Size = UDim2.fromOffset(SPINNER_DOTS * SPINNER_DOT_PX * 2, SPINNER_DOT_PX),
		Visible = false,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Horizontal, SPINNER_DOT_PX, spinner)
	local dots: { Frame } = {}
	for i = 1, SPINNER_DOTS do
		local dot: Frame = Create("Frame", {
			Name = "Dot" .. i,
			LayoutOrder = i,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(SPINNER_DOT_PX, SPINNER_DOT_PX),
			Parent = spinner,
		})
		Theme.corner(SPINNER_DOT_PX, dot)
		table.insert(dots, dot)
	end

	local badge: CountBadge.CountBadge? = nil
	local function ensureBadge(): CountBadge.CountBadge
		local current = badge
		if current then
			return current
		end
		local made = CountBadge.new({ name = "Badge", parent = root })
		made.root.AnchorPoint = Vector2.new(0.5, 0.5)
		made.root.Position = UDim2.new(1, style.paddingX - BADGE_INSET, 0, BADGE_INSET)
		cleanup:add(made)
		badge = made
		return made
	end
	if spec.badge then
		ensureBadge():setCount(spec.badge)
	end

	Focus.decorate(root, style.radius)

	local state: State = "normal"
	local spinnerHandle: Scheduler.Handle? = nil
	local wiggleHandle: Scheduler.Handle? = nil
	local feel = newFeel(root, cleanup, function(): boolean
		return state == "normal"
	end)

	-- The foam colours of the current state (§9.13: hover face +8%, pressed -10%).
	local function surfaceColors(): Theme.FoamColors
		if state == "disabled" then
			local colors = Theme.Colors
			return {
				face = colors.disabledFace,
				top = colors.disabledFace,
				bevel = colors.disabledShade,
				drop = colors.disabledShade,
			}
		end
		local face, shade = accent.face, accent.shade
		if feel.pressed then
			face = face:Lerp(BLACK, -MOTION.buttonPressed.fillDelta)
			shade = shade:Lerp(BLACK, -MOTION.buttonPressed.fillDelta)
		elseif feel.hovered then
			face = face:Lerp(WHITE, MOTION.buttonHover.fillDelta)
			shade = shade:Lerp(WHITE, MOTION.buttonHover.fillDelta)
		end
		return {
			face = face,
			top = face:Lerp(WHITE, Theme.Foam.highlight),
			bevel = shade,
			drop = Theme.Colors.inkUI,
		}
	end

	-- Text and icon colours of the current state and accent (the outlined-text rule on an accent face).
	local function paintText()
		local disabled = state == "disabled"
		local shown: { TextLabel } = { label }
		if subLabel then
			table.insert(shown, subLabel)
		end
		for _, text in shown do
			if disabled then
				Theme.textOnLight(text, Theme.Colors.disabledText)
			elseif accent.light then
				Theme.textOnLight(text)
			else
				Theme.textOnColor(text)
			end
		end
		Theme.textOnLight(reasonLabel, Theme.Colors.ink2)
		local glyph = icon
		if glyph then
			glyph:setTone(if disabled then "disabled" elseif accent.light then "dark" else "light")
		end
		for _, dot in dots do
			dot.BackgroundColor3 = label.TextColor3
		end
	end

	local function refreshVisual(animate: boolean)
		foam:paint(surfaceColors())
		foam:setStroke(if state == "disabled" then Theme.Colors.disabledStroke else Theme.Colors.inkUI)
		feel.refresh(animate)
	end

	local function stopWiggle()
		if wiggleHandle then
			wiggleHandle:disconnect()
			wiggleHandle = nil
		end
		content.Position = UDim2.fromOffset(0, -shift)
	end
	cleanup:add(stopWiggle)

	-- The "no" wiggle of a disabled press (§18.5.2 B3). Reading: the label moves (Content), since a Button inside a
	-- UIListLayout can't move its own Position.
	local function wiggle()
		stopWiggle()
		if Tweens.reducedMotion() then
			return
		end
		local wiggleSpec = MOTION.buttonError
		local duration = wiggleSpec.ms / MS
		local elapsed = 0
		wiggleHandle = Scheduler.add(function(dt: number): boolean
			elapsed += dt
			if elapsed >= duration then
				content.Position = UDim2.fromOffset(0, -shift)
				wiggleHandle = nil
				return false
			end
			local u = elapsed / duration
			local x = wiggleSpec.wigglePx * math.sin(2 * math.pi * wiggleSpec.cycles * u) * (1 - u)
			content.Position = UDim2.fromOffset(x, -shift)
			return true
		end, "render")
	end

	local function stopSpinner()
		if spinnerHandle then
			spinnerHandle:disconnect()
			spinnerHandle = nil
		end
		for _, dot in dots do
			dot.BackgroundTransparency = 0
		end
	end

	local function startSpinner()
		stopSpinner()
		if Tweens.reducedMotion() then
			return
		end
		local elapsed = 0
		spinnerHandle = Scheduler.add(function(dt: number): boolean
			elapsed = (elapsed + dt) % SPINNER_CYCLE_SECONDS
			local lit = math.floor(elapsed / SPINNER_CYCLE_SECONDS * SPINNER_DOTS) + 1
			for i, dot in dots do
				dot.BackgroundTransparency = if i == lit then 0 else 0.6
			end
			return true
		end, "render")
	end
	cleanup:add(stopSpinner)

	cleanup:add(root.MouseEnter:Connect(function()
		feel.hovered = true
		refreshVisual(false)
		if soundOn and state ~= "loading" and lastInputIsMouse() then
			playSound(SOUND_HOVER)
		end
	end))
	cleanup:add(root.MouseLeave:Connect(function()
		feel.hovered, feel.pressed = false, false
		refreshVisual(false)
	end))
	cleanup:add(root.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			feel.pressed = true
			refreshVisual(true)
		end
	end))
	cleanup:add(root.InputEnded:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			feel.pressed = false
			refreshVisual(true)
		end
	end))
	cleanup:add(root.SelectionGained:Connect(function()
		feel.focused = true
		refreshVisual(false)
	end))
	cleanup:add(root.SelectionLost:Connect(function()
		feel.focused = false
		refreshVisual(false)
	end))
	cleanup:add(root.Activated:Connect(function()
		if state == "disabled" then
			playSound(SOUND_ERROR)
			wiggle()
			return
		elseif state ~= "normal" then
			return
		end
		task.spawn(function()
			local ok, err = pcall(function(): any
				spec.onActivated()
				return nil
			end)
			if not ok then
				log:error(`{spec.name} failed:`, err)
			end
		end)
		-- After onActivated ran up to its first yield: an open or close it made has already asked for its sound.
		if soundOn then
			playSound(SOUND_CLICK)
		end
	end))

	paintText()
	refreshVisual(false)
	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: Button
	self.root = root

	function self.setText(_: Button, text: string)
		label.Text = text
	end

	function self.setState(_: Button, newState: State, reason: string?)
		state = newState
		local disabled = newState == "disabled"
		local loading = newState == "loading"
		local row = line
		if row then
			row.Visible = not loading
		else
			label.Visible = not loading
		end
		local glyph = icon
		if glyph and tile then
			glyph.root.Visible = not loading
		end
		reasonLabel.Text = if disabled and reason then reason else ""
		reasonLabel.Visible = disabled and reason ~= nil and reason ~= ""
		spinner.Visible = loading
		if loading then
			startSpinner()
		else
			stopSpinner()
		end
		if not disabled then
			stopWiggle()
		end
		paintText()
		refreshVisual(false)
	end

	function self.getState(_: Button): State
		return state
	end

	function self.pulse(_: Button, peak: number, downMs: number, upMs: number)
		feel.pulse(peak, downMs, upMs)
	end

	-- A fixed width (the label and the reason wrap inside it; a row stays one line) or, with nil, the automatic width.
	-- The height stays.
	function self.setWidth(_: Button, widthPx: number?)
		local fixed = widthPx ~= nil
		root.AutomaticSize = if fixed then Enum.AutomaticSize.None else Enum.AutomaticSize.X
		root.Size = UDim2.new(0, widthPx or 0, root.Size.Y.Scale, root.Size.Y.Offset)
		content.Size = UDim2.fromScale(if fixed then 1 else 0, 1)
		content.AutomaticSize = if fixed then Enum.AutomaticSize.None else Enum.AutomaticSize.X
		local wrapping: { TextLabel } = { reasonLabel }
		if not inLine then
			table.insert(wrapping, label)
		end
		for _, text in wrapping do
			text.Size = UDim2.fromScale(if fixed then 1 else 0, 0)
			text.AutomaticSize = if fixed then Enum.AutomaticSize.Y else Enum.AutomaticSize.XY
			text.TextWrapped = fixed
		end
	end

	function self.setAccent(_: Button, name: Theme.AccentName)
		accent = Theme.accent(name)
		paintText()
		refreshVisual(false)
	end

	function self.setIcon(_: Button, name: string)
		local glyph = icon
		if glyph then
			glyph:setIcon(name)
		else
			log:warn(`{spec.name} has no icon slot (pass spec.icon to Button.new)`)
		end
	end

	function self.setKeycap(_: Button, text: string?)
		local cap = keycap
		if cap then
			cap:setText(text)
		elseif text ~= nil and text ~= "" then
			log:warn(`{spec.name} has no keycap slot (pass spec.keycap to Button.new)`)
		end
	end

	function self.setSubtext(_: Button, text: string?)
		local sub = subLabel
		if sub then
			sub.Text = text or ""
			sub.Visible = text ~= nil and text ~= ""
		elseif text ~= nil and text ~= "" then
			log:warn(`{spec.name} has no subtext slot (pass spec.subtext to Button.new)`)
		end
	end

	function self.setBadge(_: Button, count: number?)
		if badge == nil and CountBadge.text(count) == nil then
			return
		end
		ensureBadge():setCount(count)
	end

	function self.destroy(_: Button)
		cleanup:clean()
	end

	return self
end

return Button
