--!strict
-- Button (client only). DESIGN §11.1 (UI/Components), §9.13 (button states), §11.2 (touch targets), §11.4 (focus),
-- §18.5.2 B3 (feel pass: springy release, sounds, the "no" wiggle, pulse, decorate); the foam UI restyle (spec
-- 2026-10-09, API guide docs/superpowers/specs/2026-10-09-foam-ui-components.md).
--   local button = Button.new({ name = "Queue_CancelButton", text = Strings.common.cancel, onActivated = fn })
--   button:setState("disabled", reasonText) / "loading" / "normal";   button:pulse(0.94, 60, 140);   button:destroy()
--   local feel = Button.decorate(plainGuiButton, { sound = false })   -- the same press feel on a plain button
--   Button.setSoundHook(function(key) SoundController.play(key) end) -- UIController.init (a component never requires
--                                                                       a controller)
-- Kinds (UI FINAL R1, the look kit of the design "Squishy Duels UI FINAL", 2026-10-14; `H:n` = its "Squishy Duels
-- HUD.dc.html" line n; see Button.style(kind)). Each is a sticker surface (Theme.foam): the accent's gradient face, an
-- ink border drawn inside the box, the inset highlight along the top and the bevel along the bottom
-- (Config.UI.Sticker.surfaces), and the ink lip under the face, inside the box (Layout.stickerBands):
--   primary    green 3-stop (or spec.accent), border 4, radius 18, lip 5, highlight 3 at .55, bevel 6 at .15, height 56
--              (H:245)
--   secondary  cyan 3-stop, the same shape (the default kind; the design's FIND IN BOXES, GO, reveal EQUIP, H:247)
--   cancel     the lilac CANCEL (H:462): highlight 3 at .3, no bevel
--   tile       the nav tile: the icon (spec.icon) above its outlined label (Chip kind by default), a fixed TILE_SIZE ×
--              TILE_HEIGHT box (the design's sticker, H:99) unless width / height are given, an optional count badge.
--              Until R4 gives it the design's faceless sticker and its picture (img.nav.*), it keeps its foam plate
--              (an outer 3 px ink outline, the Theme.Foam.tile bands, radius 20) in its accent's sticker colours, so
--              the lobby nav keeps a visible face and press state
--   cta        the big call to action (the Duel button, H:126): pink 3-stop, border 5, radius 28, lip 7, highlight 4 at
--              .6, bevel 8 at .3 towards the duel tint, height CTA_HEIGHT; the one kind with the sweep strip
--   close      the chunky red X (H:252): border 5, radius 24, lip 6, highlight 4 at .5, bevel 6 at .18, a square (76 by
--              default) with the "close" IconGlyph at CLOSE_ICON_SHARE of it (spec.icon may change it); the label keeps
--              spec.text (it names the action for tests and audits) but is hidden
-- Q5 (the user, 2026-10-14; Config.UI.Sticker.buttonCaps): primary, secondary, cancel and cta labels show in capitals
-- (a display transform: Strings and setText keep their case; widthFor measures the capitals). The label stays the
-- Button text kind (20 px) unless spec.textKind says otherwise: the screens that measure buttons keep their numbers
-- until their own round (R5-R9, PLAN.md) passes the design's size (Big 24, HudNumber 26, Large 28; its outline follows,
-- Theme.outlinePx).
-- Optional parts (any kind): spec.icon (UI/Components/IconGlyph; above the label on a tile, left of it otherwise),
-- spec.keycap (UI/Components/Keycap, left of the icon; the caller hides it on touch with setKeycap(nil)), spec.subtext
-- (a Chip-kind line under the label, e.g. the CTA's "Join the queue") and spec.badge (UI/Components/CountBadge on the
-- top-right corner, setBadge). A non-tile button with an icon, a keycap or a subtext lays them out in one row ("Line");
-- pass keycap = "" / subtext = "" to reserve a part that starts hidden.
-- States:
--   normal    hover: scale (Config.UI.motion.buttonHover), face brighter by fillDelta (the design's brightness 1.07,
--             H:637); pressed: scale buttonPressed, face darker; release: a spring (Util/Spring,
--             Config.UI.motion.buttonRelease.spring: ω 20, ζ 0.35, ≈ 2.5% overshoot, under 3 Hz) from the current scale
--             to 1 (the hover scale while hovered), a Scheduler render effect; buttonRelease.ms with Back Out is the
--             fallback when no spring is configured. The whole foam stack is the root, so it scales with the press.
--             The design's per-kind hover and press (H:634-644, PLAN.md §2) come with R2's motion kit.
--   focused   (gamepad selection) the custom focus ring (UI/Focus, concentric with the kind's corners) + the focus
--             scale
--   disabled  the disabled sticker (the lilac #CBBDF2 -> #A996E0, highlight 3 at .2, no bevel, H:246), the label
--             white with the ink outline (H:246), PLUS a reason text under the label, white with the ink outline too
--             (it reads on the lilac and over the ink lip alike); still selectable so a gamepad user can read it;
--             Activated is ignored, but a press plays ui.error and a "no" wiggle (the label moves ±wigglePx, `cycles`
--             times over buttonError.ms, fading out)
--   loading   the label (or the row) is replaced by the spinner (H:465: a 30 px ink ring with a white arc, one turn
--             every 0.7 s); not activatable (and silent)
-- Sounds go through the hook (§18.6): ui.click on Activated (after onActivated ran, so UIController can keep one sound
-- per action), ui.hover on MouseEnter (mouse only), ui.error on a disabled press. spec.sound = false silences the
-- click and hover of a button that opens a screen (ui.open plays instead); the disabled ui.error still plays.
-- pulse(scale, downMs, upMs): to `scale` over downMs (Quad Out), back over upMs (Back Out) (the squeeze echo, A2; the
-- coin pill bounce, B1).
-- Under ReducedMotion (Anim/Tweens.reducedMotion) every scale effect, pulse, wiggle and sweep is off and the spinner
-- stays still; the colour feedback and the sounds stay. Sizes are base px under the ScreenGui UIScale; the height is
-- raised to the touch minimum (Config.UI.Touch.minTarget). The bands and the lip are inside the button's box; the
-- content is raised by half the lip so it sits centred on the face (Style.shift; the tile's foam plate: half its
-- bands, as before). The root keeps the stable test name given in spec.name (§2.11 `<Screen>_<Action>Button`); its
-- text parts keep the names Label and Reason.
-- Part 8: Button.widthFor(text, reason?, textKind?, kind?) is the width (base px) an automatic-width Button with that
-- label (and disabled reason line) takes: the wider text (Theme.textWidth, the player's text size; the label in
-- capitals for a kind that shows them) plus the kind's side padding and MEASURE_MARGIN_PX, so a layout that wraps or
-- pins buttons from it never lets two of them touch.
-- button:setWidth(px?) switches between a fixed width (the label and reason wrap inside it; the caller sets the height
-- through root.Size) and the automatic width (nil), e.g. the shop's Buy in a narrow column at a large text size.
-- Button.PADDING_X is the side padding inside the primary / secondary kinds (base px).
-- Candy UI (UI overhaul 2026-10-11), kept: a press squishes the face (the bevel and drop bands shrink by PRESS_SINK_PX
-- and the content sinks as much) and the release springs back; labels on an accent face follow Theme.textOnColor.
-- sweep(): one pass of the design's shine strip (H:127: a 54 px white strip at .6; sdShine's moving part, H:28) across
-- a fixed-width cta (nothing on the other kinds or under ReducedMotion): the attention cue of a ready CTA, instead of a
-- bounce loop.

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
local Layout = require(UI.Layout)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Kind = "primary" | "secondary" | "cancel" | "tile" | "cta" | "close"
export type State = "normal" | "disabled" | "loading"
export type SoundHook = (key: string) -> ()

export type Spec = {
	name: string,
	text: string,
	kind: Kind?,
	accent: Theme.AccentName?, -- the face; default per kind (Button.style(kind).accent)
	width: number?, -- base px; nil = automatic width (a tile: TILE_SIZE, a close X: its height)
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
	sweep: (self: Button) -> (),
	destroy: (self: Button) -> (),
}

-- The shape of a kind (base px; UI FINAL R1: a sticker surface, Config.UI.Sticker).
export type Style = {
	accent: Theme.AccentName,
	surface: string, -- its Config.UI.Sticker.surfaces entry (the highlight and bevel)
	radius: number,
	border: number, -- the ink border (0 = none)
	inner: boolean, -- the border is drawn inside the box (a sticker); else outside (the tile's foam plate)
	lip: number, -- the ink lip under the face, inside the box
	top: number, -- the foam bands (Layout.stickerBands)
	bevel: number,
	drop: number,
	shift: number, -- the content is raised this much, so it sits centred on the face
	paddingX: number, -- side padding inside the button
	height: number, -- the default height
	iconPx: number, -- the default icon size
	caps: boolean, -- the label shows in capitals (Q5)
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
local STICKER = Config.UI.Sticker
-- UI FINAL R1 (the design's own px): the nav sticker (H:99-100), the DUEL button (H:126), the close X (H:252).
local TILE_SIZE = 118
local TILE_HEIGHT = 104
local TILE_ICON_PX = 92
local TILE_PADDING_X = 6
local CTA_HEIGHT = 92
local CTA_PADDING_X = 22
local CLOSE_SIZE = 76
local CLOSE_ICON_SHARE = 46 / 76 -- H:252: the X picture, as a share of the button
local LINE_GAP = 8 -- between the keycap, the icon and the texts in a row
local TILE_GAP = 2 -- between a tile's icon and its label
local BADGE_INSET = 5 -- the badge's centre, inside the top-right corner
local PRESS_SINK_PX = 2 -- Candy UI: a press sinks the content and shrinks the bevel and drop bands this much
-- The spinner (H:465): a SPINNER_PX ring of SPINNER_RING_PX ink whose top quarter is white (the top ARC_SHARE of its
-- height), one turn every SPINNER_TURN_SECONDS (1.4 Hz, under 3 Hz).
local SPINNER_PX = 30
local SPINNER_RING_PX = 5
local SPINNER_TURN_SECONDS = 0.7
local ARC_SHARE = 0.15
local ARC_EDGE = 0.001 -- the arc's hard edge
-- The sweep strip (H:127, H:28): STRIP_PX wide at STRIP_ALPHA, slid across over SWEEP_MS (sdShine's moving part, the
-- last 45% of 3.4 s); SWEEP_OFFSET (a share of the button) takes it from fully out on the left to fully out on the
-- right.
local STRIP_PX = 54
local STRIP_ALPHA = 0.6
local STRIP_SLANT_DEG = 20 -- skewX(-20deg)
local STRIP_MAX_HALF = 0.45 -- a narrow button keeps the strip's stops apart
local SWEEP_MS = 1530
local SWEEP_OFFSET = 1
-- Kinds whose fixed width carries the sweep strip.
local SHINE_KINDS: { [string]: boolean } = { cta = true }

-- A sticker kind's style (UI FINAL R1): its bands from the border, the surface's highlight and bevel, and the lip.
local function sticker(
	accent: Theme.AccentName,
	surface: string,
	radius: number,
	border: number,
	lip: number,
	paddingX: number,
	height: number,
	iconPx: number
): Style
	local look = STICKER.surfaces[surface]
	local bands = Layout.stickerBands(border, look.highlightPx, look.bevelPx or 0, lip)
	return {
		accent = accent,
		surface = surface,
		radius = radius,
		border = border,
		inner = true,
		lip = lip,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		shift = lip / 2,
		paddingX = paddingX,
		height = height,
		iconPx = iconPx,
		caps = surface ~= "close",
	}
end
local STYLES: { [string]: Style } = {
	primary = sticker(
		"green",
		"primary",
		STICKER.radius.button,
		STICKER.border.normal,
		STICKER.lip.button,
		HORIZONTAL_PADDING,
		TOUCH.primaryButton,
		24
	),
	secondary = sticker(
		"cyan",
		"primary",
		STICKER.radius.button,
		STICKER.border.normal,
		STICKER.lip.button,
		HORIZONTAL_PADDING,
		TOUCH.primaryButton,
		24
	),
	cancel = sticker(
		"cancel",
		"cancel",
		STICKER.radius.button,
		STICKER.border.normal,
		STICKER.lip.button,
		HORIZONTAL_PADDING,
		TOUCH.primaryButton,
		24
	),
	-- The nav tile keeps its foam plate until R4 (see the header): an outer ink outline, the Theme.Foam.tile bands, in
	-- its accent's sticker colours; no capitals (H:101 "Squishies").
	tile = {
		accent = "strawberry",
		surface = "primary",
		radius = Theme.Radius.tile,
		border = Theme.Stroke.ink,
		inner = false,
		lip = 0,
		top = Theme.Foam.tile.top,
		bevel = Theme.Foam.tile.bevel,
		drop = Theme.Foam.tile.drop,
		shift = (Theme.Foam.tile.bevel + Theme.Foam.tile.drop - Theme.Foam.tile.top) / 2,
		paddingX = TILE_PADDING_X,
		height = TILE_HEIGHT,
		iconPx = TILE_ICON_PX,
		caps = false,
	},
	cta = sticker(
		"strawberry",
		"duel",
		STICKER.radius.duel,
		STICKER.border.heavy,
		STICKER.lip.cta,
		CTA_PADDING_X,
		CTA_HEIGHT,
		44
	),
	-- H:252: radius 24 (the plate radius token).
	close = sticker(
		"red",
		"close",
		STICKER.radius.plate,
		STICKER.border.heavy,
		STICKER.lip.closeX,
		0,
		CLOSE_SIZE,
		math.floor(CLOSE_SIZE * CLOSE_ICON_SHARE)
	),
}
for _, style in STYLES do
	table.freeze(style)
end

-- Module table

local Button = {}

Button.PADDING_X = HORIZONTAL_PADDING
Button.TILE_SIZE = TILE_SIZE
Button.TILE_HEIGHT = TILE_HEIGHT
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

-- The label as a Button of `kind` (default "secondary") shows it: in capitals for a kind that shows them (Q5,
-- Config.UI.Sticker.buttonCaps), else as it is.
function Button.displayText(text: string, kind: Kind?): string
	return if STICKER.buttonCaps and Button.style(kind).caps then string.upper(text) else text
end

-- The width (base px) of an automatic-width Button of `kind` (default "secondary") showing `text` (in `textKind`,
-- default "Button"; in capitals for a kind that shows them) and, when given, the disabled `reason` line (Small) under
-- it, at the player's text size: the wider of the two, the kind's side padding and MEASURE_MARGIN_PX.
function Button.widthFor(text: string, reason: string?, textKind: Theme.TextKind?, kind: Kind?): number
	local width = Theme.textWidth(Button.displayText(text, kind), textKind or "Button")
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
	local iconOnly = kind == "close"
	local stacked = tile or iconOnly -- the icon above (or, for close, instead of) the label
	local accent = Theme.accent(spec.accent or style.accent)
	local height = math.max(spec.height or style.height, TOUCH.minTarget)
	local fixedWidth: number? = spec.width or (if tile then TILE_SIZE elseif iconOnly then height else nil)
	local soundOn = spec.sound ~= false
	-- UI FINAL R1: the content is raised so it sits centred on the face (Style.shift).
	local shift = style.shift
	local iconName: string? = spec.icon or (if iconOnly then "close" else nil)
	local inLine = not stacked and (spec.icon ~= nil or spec.keycap ~= nil or spec.subtext ~= nil)
	local sink = 0 -- the press squish now (PRESS_SINK_PX while pressed)

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
		stroke = style.border,
		inner = style.inner,
		top = style.top,
		bevel = style.bevel,
		drop = style.drop,
		colors = Theme.accentColors(spec.accent or style.accent, true, style.surface),
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, style.paddingX),
		PaddingRight = UDim.new(0, style.paddingX),
		Parent = root,
	})
	-- UI FINAL R1: the sweep strip (H:127), only while the width is fixed (an overlay inside an automatically sized
	-- button would inflate it, and the strip's share of the width must be known): a white frame over the whole box (its
	-- UIPadding undone; the button's corners, so it never shows outside them) under the content (ZIndex 0), whose
	-- UIGradient leaves one STRIP_PX soft strip, offset out of sight until sweep().
	local function applyShine(on: boolean)
		local existing = root:FindFirstChild("SD_Shine")
		local width = root.Size.X.Offset
		if not (on and SHINE_KINDS[kind] and width > 0) then
			if existing then
				existing:Destroy()
			end
			return
		end
		local strip = existing
		if strip == nil then
			local made: Frame = Create("Frame", {
				Name = "SD_Shine",
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(-style.paddingX, 0),
				Size = UDim2.new(1, 2 * style.paddingX, 1, 0),
				Active = false,
				ZIndex = 0,
				Parent = root,
			})
			Theme.corner(style.radius, made)
			Create("UIGradient", { Rotation = STRIP_SLANT_DEG, Offset = Vector2.new(-SWEEP_OFFSET, 0), Parent = made })
			strip = made
		end
		local gradient = (strip :: Instance):FindFirstChildOfClass("UIGradient")
		if gradient then
			local half = math.min(STRIP_MAX_HALF, STRIP_PX / width / 2)
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5 - half, 1),
				NumberSequenceKeypoint.new(0.5, 1 - STRIP_ALPHA),
				NumberSequenceKeypoint.new(0.5 + half, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
	end
	applyShine(fixedWidth ~= nil)

	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, -shift),
		Size = UDim2.fromScale(if fixedWidth then 1 else 0, 1),
		AutomaticSize = if fixedWidth then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		Parent = root,
	})
	Theme.list(Enum.FillDirection.Vertical, if stacked then TILE_GAP else 0, content)

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
	if iconName then
		icon = IconGlyph.new({
			name = "Icon",
			icon = iconName,
			-- UI FINAL R1: the close X's picture is CLOSE_ICON_SHARE of its square (H:252), whatever size it is given.
			sizePx = spec.iconSize or (if iconOnly then math.floor(height * CLOSE_ICON_SHARE) else style.iconPx),
			layoutOrder = if stacked then 0 else 2,
			parent = if stacked then content else line,
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
		Text = Button.displayText(spec.text, kind),
		Visible = not iconOnly,
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

	-- UI FINAL R1: the spinner (H:465), an ink ring whose top quarter is white (a UIGradient on the ring's stroke).
	local spinner: Frame = Create("Frame", {
		Name = "Spinner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -shift),
		Size = UDim2.fromOffset(SPINNER_PX, SPINNER_PX),
		Visible = false,
		Parent = root,
	})
	Theme.corner(SPINNER_PX, spinner)
	local ring = Theme.stroke(WHITE, SPINNER_RING_PX, spinner)
	pcall(function()
		(ring :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(ARC_SHARE, WHITE),
			ColorSequenceKeypoint.new(ARC_SHARE + ARC_EDGE, Theme.Colors.inkUI),
			ColorSequenceKeypoint.new(1, Theme.Colors.inkUI),
		}),
		Parent = ring,
	})

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

	-- The sticker colours of the current state (§9.13: hover brighter by buttonHover.fillDelta, pressed darker by
	-- buttonPressed.fillDelta; UI FINAL R1: the disabled sticker of H:246).
	local function surfaceColors(): Theme.FoamColors
		if state == "disabled" then
			return Theme.surfaceColors(Theme.Accents.disabled, "disabled", true)
		end
		if not (feel.pressed or feel.hovered) then
			return Theme.surfaceColors(accent, style.surface, true)
		end
		local toward = if feel.pressed then BLACK else WHITE
		local amount = if feel.pressed then -MOTION.buttonPressed.fillDelta else MOTION.buttonHover.fillDelta
		local function lift(color: Color3): Color3
			return color:Lerp(toward, amount)
		end
		local mid = accent.mid
		return Theme.surfaceColors({
			face = lift(accent.face),
			shade = lift(accent.shade),
			light = accent.light,
			top = lift(accent.top),
			mid = if mid then lift(mid) else nil,
			midAt = accent.midAt,
		}, style.surface, true)
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
				Theme.textOnColor(text, nil, accent.face)
			end
		end
		-- UI FINAL R1: white with the ink outline (H:246's text), readable on the lilac face and over the ink lip.
		Theme.textOnLight(reasonLabel, Theme.Colors.white)
		local glyph = icon
		if glyph then
			glyph:setTone(if disabled then "disabled" elseif accent.light then "dark" else "light")
		end
	end

	local function refreshVisual(animate: boolean)
		-- Candy UI: a press sinks into the foam (the bands shrink, the content drops as much); none under ReducedMotion.
		local newSink = if feel.pressed and state == "normal" and not Tweens.reducedMotion() then PRESS_SINK_PX else 0
		if newSink ~= sink then
			sink = newSink
			foam:setBands(style.top, math.max(0, style.bevel - sink), math.max(0, style.drop - sink))
			if wiggleHandle == nil then
				content.Position = UDim2.fromOffset(0, sink - shift)
			end
		end
		foam:paint(surfaceColors())
		foam:setStroke(if state == "disabled" then Theme.Colors.disabledStroke else Theme.Colors.inkUI)
		feel.refresh(animate)
	end

	local function stopWiggle()
		if wiggleHandle then
			wiggleHandle:disconnect()
			wiggleHandle = nil
		end
		content.Position = UDim2.fromOffset(0, sink - shift)
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
		spinner.Rotation = 0
	end

	-- One turn every SPINNER_TURN_SECONDS (still under ReducedMotion).
	local function startSpinner()
		stopSpinner()
		if Tweens.reducedMotion() then
			return
		end
		spinnerHandle = Scheduler.add(function(dt: number): boolean
			spinner.Rotation = (spinner.Rotation + 360 * dt / SPINNER_TURN_SECONDS) % 360
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
		label.Text = Button.displayText(text, kind)
	end

	function self.setState(_: Button, newState: State, reason: string?)
		state = newState
		local disabled = newState == "disabled"
		local loading = newState == "loading"
		local row = line
		if row then
			row.Visible = not loading
		else
			label.Visible = not loading and not iconOnly
		end
		local glyph = icon
		if glyph and stacked then
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
		applyShine(fixed)
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

	local sweepTween: Tween? = nil
	cleanup:add(function()
		Tweens.cancel(sweepTween)
	end)
	-- UI FINAL R1: the strip slides from out of sight on the left to out of sight on the right (ease-in-out, H:127).
	function self.sweep(_: Button)
		local shine = root:FindFirstChild("SD_Shine")
		local gradient = if shine then shine:FindFirstChildOfClass("UIGradient") else nil
		if gradient == nil or Tweens.reducedMotion() or state ~= "normal" then
			return
		end
		Tweens.cancel(sweepTween)
		gradient.Offset = Vector2.new(-SWEEP_OFFSET, 0)
		sweepTween = Tweens.play(
			gradient,
			SWEEP_MS,
			{ Offset = Vector2.new(SWEEP_OFFSET, 0) },
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		)
	end

	function self.destroy(_: Button)
		cleanup:clean()
	end

	return self
end

return Button
