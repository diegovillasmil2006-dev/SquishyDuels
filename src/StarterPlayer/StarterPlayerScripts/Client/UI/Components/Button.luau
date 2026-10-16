--!strict
-- Button (client only). DESIGN §11.1 (UI/Components), §9.13 (button states), §11.2 (touch targets), §11.4 (focus),
-- §18.5.2 B3 (feel pass: sounds, pulse, decorate); the foam UI restyle (spec 2026-10-09, API guide
-- docs/superpowers/specs/2026-10-09-foam-ui-components.md).
--   local button = Button.new({ name = "Queue_CancelButton", text = Strings.common.cancel, onActivated = fn })
--   button:setState("disabled", reasonText) / "loading" / "normal";   button:pulse(0.94, 60, 140);   button:destroy()
--   local feel = Button.decorate(plainGuiButton, { sound = false })   -- the same press feel on a plain button
--   Button.setSoundHook(function(key, pitch?) SoundController.play(key) end) -- UIController.init (a component never
--                                                                               requires a controller)
-- Kinds (UI FINAL R1, the look kit of the design "Squishy Duels UI FINAL", 2026-10-14; `H:n` = its "Squishy Duels
-- HUD.dc.html" line n; see Button.style(kind)). Each is a sticker surface (Theme.foam): the accent's gradient face, an
-- ink border drawn inside the box, the inset highlight along the top and the bevel along the bottom
-- (Config.UI.Sticker.surfaces), and the ink lip under the face (Layout.stickerBands):
--   primary    green 3-stop (or spec.accent), border 4, radius 18, lip 5, highlight 3 at .55, bevel 6 at .15 (H:245),
--              face Touch.primaryButton 56 (the design's CLAIM / GO, H:370-371; its EQUIP is 60, H:245)
--   secondary  cyan 3-stop, the same shape (the default kind; the design's FIND IN BOXES, GO, reveal EQUIP, H:247)
--   cancel     the lilac CANCEL (H:462): highlight 3 at .3, no bevel
--   tile       the nav sticker (UI FINAL R4, P13; H:99-102, H:157-159): no face, no outline, no plate: the picture
--              (img.nav.*, IconGlyph's slot; its drawn shape while the id is nil) IS the button, with the design's
--              drop shadow (spec.iconShadow), the label (spec.textRole, e.g. navLabel) pulled up over it by
--              spec.labelPull and drawn above it; a fixed TILE_SIZE x TILE_HEIGHT box unless width / height are given;
--              the picture sits in SD_Bob (UiIdle's bob, spec.bob) and SD_Wiggle (the nav hover's wiggle, H:639,
--              Config.UI.motion.navWiggle: PR6), and the hover's brightness is a white copy of the picture
--              (img.nav.<name>.white, pack 2; none while nil, G4.20) at the filter's .07; the count badge at the
--              design's spot (right 8, top 0, H:102) in spec.badgeAccent with its sdBadge loop (spec.badgeDelay)
--   cta        the big call to action (the Duel button, H:126): pink 3-stop, border 5, radius 28, lip 7, highlight 4 at
--              .6, bevel 8 at .3 towards the duel tint, face CTA_HEIGHT; the one kind with the moving shine strip
--   close      the chunky red X (H:252): border 5, radius 24, lip 6, highlight 4 at .5, bevel 6 at .18, a face square
--              (76 by default) with the "close" IconGlyph at CLOSE_ICON_SHARE of it (spec.icon may change it); the
--              label keeps spec.text (it names the action for tests and audits) but is hidden
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
-- UI FINAL R2 (plan work/ui/PLAN.md R2: P1, T3, T4, G2.7, P11, P12, P2, PR4, PR5, PR24):
--   * The root (spec.name) is a transparent, laid-out hit box (Activated, Selectable, the focus ring, LayoutOrder); the
--     drawn button is its child SD_Visual (button.visual): the face, bands, label, icon, badge, shine and spinner. The
--     hit box never moves, so a lift or a squash never drops the pointer.
--   * Frame = face + lip (P1): spec.height (default the kind's) is the design's face; the lip hangs under it, so the
--     root is face + lip tall (Button.frameHeight), raised to Config.UI.Touch.minTarget. SD_Visual fills the root
--     (a caller that sizes root.Size sizes the drawn button too, as before), except when the frame is under the touch
--     minimum (the "chip" size's 34 px face, a 42 px tab, PR1): that face keeps its design size, centred in the
--     touch-sized hit box. A close X is face wide (76 x 82 by default).
--   * An automatic width (no spec.width) follows the content's natural width (measured, as AutomaticSize X did: a
--     caller's own root width is a minimum). While the button moves (a pose, squash, shake or pulse) or a UIScale
--     above it is not 1 (a window popping in), a re-measure within 1 px is ignored (the rounding of a scaled size),
--     and the width is measured once more when the motion settles (Button.settledWidth, pure).
--   * Hover (mouse only; a tap's MouseEnter is not one) and gamepad focus (PR24) pose SD_Visual by its design kind
--     (spec.fx; by default primary / secondary / cancel / cta "btn", tile "nav", close "x"; Config.UI.motion.hover,
--     H:634) over buttonHover.ms on Config.UI.curves.hover, and give a live face the design's filter brightness(1.07)
--     saturate(1.06) computed exactly on its gradient stops (Button.hoverColor, H:637) over filterMs; never the filter
--     on a disabled, loading or "off" button (H:637), whose pose still plays (H:636). ui.hover at the kind's pitch
--     (Config.Audio.uiPitch.hover, H:638). The pose turns and scales about the face's centre (the CSS transform
--     origin; the lip hangs under it), so the close X's 90° turn stays on its spot.
--   * A press plays the design's squash (PR4, Config.UI.motion.buttonPress, lib:287-293: a non-uniform Size squash of
--     SD_Visual about its centre; the content keeps its size and takes the uniform part, so text never reflows) on
--     top of the pose. A disabled or "off" button's press plays ui.error and the design's "no" shake instead (PR5,
--     buttonShake: 9 px, lib:295-297). The mouse presses on pointer-down (InputBegan, H:611); a touch squashes a
--     live button on touch-down, but a disabled or off one only on the finished tap (Activated), so a scroll that
--     starts on it stays quiet (phone first); a gamepad or key activation presses on Activated (its input type says
--     which).
--   * One sound per click (G2.7): ui.click on Activated only when the action plays none of its own: spec.clickSound =
--     false, and the kinds of Config.Audio.buttonSilentKinds (tile, close: UIController plays ui.open / ui.back), keep
--     the click silent; hover sounds stay. spec.sound = false silences both, except on those kinds, where it means
--     the click only (the design keeps every data-fx hover sound, H:638: the callers' close X `sound = false`).
--   * setOff(true, priceColor?) (P11): the normal face, no hover filter, a press plays ui.error + the shake and still
--     runs onActivated (the design's click handler runs too, H:643, H:799); the subtext (a price) takes priceColor (the
--     design's StickerPriceShort on OPEN / BUY, H:278, H:946). The lilac disabled face is for EQUIPPED / OWNED only.
--   * Overrides (P12): radius, border, lip, stops = 2 (the accent's top and end only), highlight / bevel = { px, a };
--     size = "chip" (H:402: a 34 px face, padding 20, border 3, radius 12, the green #A6F796 -> #38C150, inset 2 at
--     .55, lip 3, the label 18 px with a 4 px stroke).
--   * UI FINAL R4: padLeft / padRight (the DUEL button's 0 24 0 128, H:126), align = "left" (its texts from the left
--     padding), textGap (between the label and the subtext, H:129), textRole / subtextRole (Theme.stickerText roles,
--     e.g. "duel" and "duelSub"); a close X whose face is under the touch minimum (the search bar's 48 px cancel X,
--     H:145) keeps its face size, centred in the 52 px hit box (PR1).
--   * The cta's shine (P2, G4.13): a 54 px strip in a holder inset by the border, the face's height, corner 23
--     (H:127), crossing every 3.4 s (Anim/UiIdle "shine", Config.UI.Sticker.shines.cta), its band leaning 20°
--     (Theme.shineBand, H:28); hidden while SD_Visual is turned (the shake), as Roblox stops clipping under a turn.
--   * The gamepad focus ring (PR24) is drawn inside SD_Visual (SD_FocusRing, round the face, the lip left out), so it
--     takes the pose with the face; the root's own SelectionImageObject is clear (Focus.blank).
-- Other states:
--   disabled  the disabled sticker (the lilac #CBBDF2 -> #A996E0, highlight 3 at .2, no bevel, H:246), the label
--             white with the ink outline (H:246), PLUS a reason text under the label, white with the ink outline too
--             (it reads on the lilac and over the ink lip alike); still selectable so a gamepad user can read it;
--             Activated is ignored (a press: ui.error and the shake)
--   loading   the label (or the row) is replaced by the spinner (H:465: a 30 px ink ring with a white arc, one turn
--             every 0.7 s); not activatable (and silent)
-- Sounds go through the hook (§18.6): ui.click on Activated (after onActivated ran, so UIController can keep one sound
-- per action), ui.hover on MouseEnter (mouse only), ui.error on a disabled or off press.
-- pulse(scale, downMs, upMs): to `scale` over downMs (Quad Out), back over upMs (Back Out) (the squeeze echo, A2; the
-- coin pill bounce, B1).
-- Under ReducedMotion (Anim/Tweens.reducedMotion) every pose, squash, shake, pulse and shine is off and the spinner
-- stays still; the colour feedback and the sounds stay. Sizes are base px under the ScreenGui UIScale. The content is
-- raised by half the lip so it sits centred on the face (Style.shift; the tile's foam plate: half its bands, as
-- before). The root keeps the stable test name given in spec.name (§2.11 `<Screen>_<Action>Button`); its text parts
-- keep the names Label and Reason.
-- Part 8: Button.widthFor(text, reason?, textKind?, kind?) is the width (base px) an automatic-width Button with that
-- label (and disabled reason line) takes: the wider text (Theme.textWidth, the player's text size; the label in
-- capitals for a kind that shows them) plus the kind's side padding and MEASURE_MARGIN_PX, so a layout that wraps or
-- pins buttons from it never lets two of them touch.
-- button:setWidth(px?) switches between a fixed width (the label and reason wrap inside it; the caller sets the height
-- through root.Size) and the automatic width (nil), e.g. the shop's Buy in a narrow column at a large text size.
-- Button.PADDING_X is the side padding inside the primary / secondary kinds (base px).
-- sweep(): kept for its caller (HudController's CTA loop): the cta's strip now crosses by itself (UiIdle).
-- Pure (unit-tested in Edit mode): hoverColor, squashAt, shakeAt, decoratedScale, settledWidth, fxOf, frameHeight.
-- Edit-mode tests cannot fire Activated, InputBegan, MouseEnter or SelectionGained: a Button's `_simulate(event,
-- arg?)` (not part of the Button type) runs the same handlers ("hover", "unhover", "select", "unselect", "press" and
-- "activate" with an input type, "frame" with seconds ahead: one frame of the motion at that time).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)

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
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type Kind = "primary" | "secondary" | "cancel" | "tile" | "cta" | "close"
export type State = "normal" | "disabled" | "loading"
export type SoundHook = (key: string, pitch: number?) -> ()
-- UI FINAL R2: the design's hover kinds (H:634).
export type Fx = "btn" | "nav" | "tab" | "card" | "x" | "icon" | "row"

export type Spec = {
	name: string,
	text: string,
	kind: Kind?,
	accent: Theme.AccentName?, -- the face; default per kind (Button.style(kind).accent)
	width: number?, -- base px; nil = automatic width (a tile: TILE_SIZE, a close X: its face)
	height: number?, -- base px: the design's face (UI FINAL R2, P1); the root is face + lip, at least the touch minimum
	textKind: Theme.TextKind?, -- default "Button" ("Chip" on a tile)
	onActivated: () -> (),
	layoutOrder: number?,
	parent: Instance?,
	sound: boolean?, -- false: no click / hover sound
	clickSound: boolean?, -- UI FINAL R2 (G2.7): false: no click sound (the action plays its own); hover stays
	fx: Fx?, -- UI FINAL R2: the design hover kind (default by kind)
	icon: string?, -- an IconGlyph name
	iconSize: number?, -- base px; default per kind
	keycap: string?, -- a key prompt left of the label ("" = reserved, hidden)
	subtext: string?, -- a second line under the label ("" = reserved, hidden)
	badge: number?, -- a count on the top-right corner (nil / 0 = hidden)
	-- UI FINAL R2 (P12): the design's per-button numbers.
	radius: number?,
	border: number?,
	lip: number?,
	stops: number?, -- 2: the accent's top and end stops only
	highlight: { px: number, a: number }?,
	bevel: { px: number, a: number }?,
	size: "chip"?,
	-- UI FINAL R4 (see the header).
	padLeft: number?,
	padRight: number?,
	align: "left"?,
	textGap: number?,
	textRole: string?,
	subtextRole: string?,
	labelPull: number?, -- a tile: base px its label is pulled up over the picture (H:101, H:159)
	iconShadow: { px: number, alpha: number, color: Color3? }?, -- a tile: the picture's drop shadow (H:100, H:158)
	bob: { periodS: number, delayS: number? }?, -- a tile: the picture's sdBob (H:100-118)
	badgeAccent: Theme.AccentName?, -- a tile: the badge's face ("yellow": the daily "!", H:120)
	badgeMark: string?, -- a tile: the badge shows this text (e.g. "!") instead of the count
	badgeDelay: number?, -- a tile: the badge's sdBadge delay (s; nil = no loop; H:102, H:115, H:120)
}

export type Button = {
	root: TextButton,
	visual: Frame, -- UI FINAL R2: the drawn button inside the hit box
	setText: (self: Button, text: string) -> (),
	setState: (self: Button, state: State, reason: string?) -> (),
	getState: (self: Button) -> State,
	setOff: (self: Button, off: boolean, priceColor: Color3?) -> (),
	isOff: (self: Button) -> boolean,
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

-- A design surface's inset highlight and bevel (Config.UI.Sticker.surfaces; UI FINAL R2: a button's own, P12).
export type Surface = { highlightPx: number, highlightAlpha: number, bevelPx: number?, bevelAlpha: number? }

-- The shape of a kind (base px; UI FINAL R1: a sticker surface, Config.UI.Sticker).
export type Style = {
	accent: Theme.AccentName,
	surface: string, -- its Config.UI.Sticker.surfaces entry (the highlight and bevel)
	radius: number,
	border: number, -- the ink border (0 = none)
	inner: boolean, -- the border is drawn inside the box (a sticker); else outside (the tile's foam plate)
	lip: number, -- the ink lip under the face
	top: number, -- the foam bands (Layout.stickerBands)
	bevel: number,
	drop: number,
	shift: number, -- the content is raised this much, so it sits centred on the face
	paddingX: number, -- side padding inside the button
	height: number, -- the default face (UI FINAL R2, P1)
	iconPx: number, -- the default icon size
	caps: boolean, -- the label shows in capitals (Q5)
	faceless: boolean?, -- UI FINAL R4 (P13): no face at all (the nav sticker: its picture is the button)
}

export type DecorateOptions = {
	sound: boolean?, -- false: no click / hover sound (default true)
	clickSound: boolean?, -- UI FINAL R2: false: no click sound, the hover sound stays
	fx: Fx?, -- UI FINAL R2: the design hover kind (default "btn")
}

export type Decorated = {
	pulse: (self: Decorated, scale: number, downMs: number, upMs: number) -> (),
	destroy: (self: Decorated) -> (),
}

-- UI FINAL R2: the motion of one button (pose, filter, squash, shake, pulse), written by one Scheduler render effect
-- while any of it moves.
type Feel = {
	scale: UIScale,
	hovered: boolean,
	focused: boolean,
	live: () -> boolean, -- the face may brighten (normal and not off)
	setHover: (on: boolean) -> (),
	press: () -> (),
	shake: () -> (),
	pulse: (peak: number, downMs: number, upMs: number) -> (),
	filterMix: () -> number,
	moving: () -> boolean, -- a motion is running (its Scheduler effect is on)
	frameAt: (now: number) -> boolean, -- one frame at clock `now` (the tests' "frame" seam)
	stop: () -> (),
}

-- Constants

local MOTION = Config.UI.motion
local HOVER = MOTION.buttonHover
local PRESS = MOTION.buttonPress
local SHAKE = MOTION.buttonShake
local TOUCH = Config.UI.Touch
local WHITE = Color3.new(1, 1, 1)
local HORIZONTAL_PADDING = 18
-- reading: added to a measured width (TextService rounding, the focus / hover scale) so laid-out buttons never touch
local MEASURE_MARGIN_PX = 4
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
local MOUSE_PRESS = Enum.UserInputType.MouseButton1
local TOUCH_PRESS = Enum.UserInputType.Touch
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
-- The spinner (H:465): a SPINNER_PX ring of SPINNER_RING_PX ink whose top quarter is white (the top ARC_SHARE of its
-- height), one turn every SPINNER_TURN_SECONDS (1.4 Hz, under 3 Hz).
local SPINNER_PX = 30
local SPINNER_RING_PX = 5
local SPINNER_TURN_SECONDS = 0.7
local ARC_SHARE = 0.15
local ARC_EDGE = 0.001 -- the arc's hard edge
-- UI FINAL R2: the kinds whose shine strip crosses by itself (H:127), the chip size (H:402), the hover kind of each
-- Button kind, and how far a re-measured width may be off while the button moves (the rounding of a scaled size).
local SHINE_KINDS: { [string]: string } = { cta = "cta" }
local WIDTH_SLACK_PX = 1
local FOCUS_RING_Z = 10 -- the gamepad ring over the face, the content and the badge
local CHIP_FACE = 34 -- H:402
local CHIP_PADDING_X = 20 -- H:402
local CHIP_RADIUS = 12 -- H:402
local CHIP_TEXT_KIND: Theme.TextKind = "Body" -- H:402: 18 px, its 4 px stroke = Theme.outlinePx("Body") x 2
local KIND_FX: { [string]: Fx } = {
	primary = "btn",
	secondary = "btn",
	cancel = "btn",
	cta = "btn",
	tile = "nav",
	close = "x",
}
local SILENT_KINDS = Config.Audio.buttonSilentKinds :: { [string]: boolean }
local HOVER_PITCH = Config.Audio.uiPitch.hover :: { [string]: number }
-- UI FINAL R4 (P13): the nav sticker (Config.UI.Sticker.hud.nav, H:99-102): its label's pull, the badge's spot inside
-- the tile, the hover wiggle (PR6) and the white copy that draws the hover's brightness (pack 2's ".white" pictures).
local NAV = STICKER.hud.nav
local WIGGLE = MOTION.navWiggle
local WHITE_SUFFIX = ".white"

-- A sticker kind's style (UI FINAL R1): its bands from the border, the surface's highlight and bevel, and the lip.
-- UI FINAL R2 (P12): `surface` may be a surface table (a button's own highlight / bevel).
local function sticker(
	accent: Theme.AccentName,
	surface: string | Surface,
	radius: number,
	border: number,
	lip: number,
	paddingX: number,
	height: number,
	iconPx: number
): Style
	local look: Surface = if type(surface) == "table" then surface else STICKER.surfaces[surface]
	local bands = Layout.stickerBands(border, look.highlightPx, look.bevelPx or 0, lip)
	return {
		accent = accent,
		surface = if type(surface) == "string" then surface else "",
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
	-- UI FINAL R4 (P13): the faceless nav sticker (see the header); no capitals (H:101 "Squishies"). Its radius is the
	-- gamepad ring's.
	tile = {
		accent = "strawberry",
		surface = "primary",
		radius = STICKER.radius.tile,
		border = 0,
		inner = true,
		lip = 0,
		top = 0,
		bevel = 0,
		drop = 0,
		shift = 0,
		paddingX = TILE_PADDING_X,
		height = TILE_HEIGHT,
		iconPx = TILE_ICON_PX,
		caps = false,
		faceless = true,
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
Button.CHIP_FACE = CHIP_FACE

-- Private

local log = Log.new("Button")
local soundHook: SoundHook? = nil

local function playSound(key: string, pitch: number?)
	local hook = soundHook
	if hook == nil then
		return
	end
	local ok, err = pcall(function(): any
		hook(key, pitch)
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

local function isPointer(input: InputObject): boolean
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

-- The product of the UIScales from `object` up to its ScreenGui (a measured AbsoluteSize over it is base px).
local function scaleChain(object: Instance): number
	local scale = 1
	local node: Instance? = object
	while node ~= nil do
		local uiScale = node:FindFirstChildOfClass("UIScale")
		if uiScale and uiScale.Scale > 0 then
			scale *= uiScale.Scale
		end
		if node:IsA("LayerCollector") then
			break
		end
		node = node.Parent
	end
	return scale
end

-- Whether every UIScale from `object` up to its ScreenGui (the ScreenGui's own, the UI scale, left out) is at 1: no
-- pose, squash or window pop is scaling it now.
local function scalesAtRest(object: Instance): boolean
	local node: Instance? = object
	while node ~= nil and not node:IsA("LayerCollector") do
		local uiScale = node:FindFirstChildOfClass("UIScale")
		if uiScale and math.abs(uiScale.Scale - 1) > 1e-6 then
			return false
		end
		node = node.Parent
	end
	return true
end

-- A frame list's value at u (0..1) of a one-shot: each segment eased by `curve` (the design's per-keyframe timing).
local function segmentAt(ats: { number }, values: { number }, u: number, curve: Tweens.Curve): number
	local t = math.clamp(u, 0, 1)
	local index = 1
	while index < #ats - 1 and t > ats[index + 1] do
		index += 1
	end
	local a, b = ats[index], ats[index + 1]
	local k = if b > a then math.clamp((t - a) / (b - a), 0, 1) else 1
	return values[index] + (values[index + 1] - values[index]) * curve(k)
end

-- UI FINAL R2: the motion of one button on `visual` (its pose, squash, shake and pulse; see the header). `content`
-- keeps its size through a squash and takes its uniform part; `onFilter(mix)` repaints the face; the pose turns and
-- scales about the face's centre, `pivotPx` above the visual's (half the lip); `onSettle` runs when a motion ends.
-- With `decorated` (Button.decorate) only a uniform scale is drawn (Button.decoratedScale), on the root's own UIScale
-- "Scale" (it may sit in a layout).
local function newFeel(
	visual: GuiObject,
	visualSize: UDim2,
	content: GuiObject?,
	fx: Fx,
	cleanup: Cleanup.Cleanup,
	live: () -> boolean,
	onFilter: ((mix: number) -> ())?,
	decorated: boolean,
	pivotPx: number,
	onSettle: (() -> ())?
): Feel
	local pose = (MOTION.hover :: any)[fx] or {}
	local amount = PRESS.amount * ((PRESS.amountByKind :: any)[fx] or 1)
	local hoverCurve = Tweens.curve(HOVER.curve)
	local filterCurve = Tweens.curve(HOVER.filterCurve)
	local pressCurve = Tweens.curve(PRESS.curve)
	local shakeCurve = Tweens.curve(SHAKE.curve)
	local scale: UIScale = Create("UIScale", { Name = if decorated then "Scale" else "SD_Pose", Parent = visual })
	local contentScale: UIScale? = if content then Create("UIScale", { Name = "SD_Squash", Parent = content }) else nil
	local hoverFrom, hoverTo, hoverAt = 0, 0, -math.huge
	local filterFrom, filterTo, filterAt = 0, 0, -math.huge
	local pressAt, shakeAt = -math.huge, -math.huge
	local pulseAt, pulsePeak, pulseDown, pulseUp = -math.huge, 1, 0, 0
	local handle: Scheduler.Handle? = nil
	local feel = {} :: Feel
	feel.scale = scale
	feel.hovered, feel.focused = false, false
	feel.live = live

	local function mixOf(from: number, to: number, at: number, ms: number, curve: Tweens.Curve, now: number): number
		if ms <= 0 then
			return to
		end
		local u = (now - at) * MS / ms
		if u >= 1 then
			return to
		end
		return from + (to - from) * curve(math.max(0, u))
	end

	local function hoverMix(now: number): number
		return mixOf(hoverFrom, hoverTo, hoverAt, HOVER.ms, hoverCurve, now)
	end

	local function filterMs(): number
		return if Tweens.reducedMotion()
			then math.min(HOVER.filterMs, MOTION.reducedMotionMaxFadeMs)
			else HOVER.filterMs
	end

	function feel.filterMix(): number
		return mixOf(filterFrom, filterTo, filterAt, filterMs(), filterCurve, os.clock())
	end

	-- One frame: writes the composed pose and returns whether anything still moves.
	local function frame(now: number): boolean
		local reduced = Tweens.reducedMotion()
		local moving = false
		local h = if reduced then 0 else hoverMix(now)
		moving = moving or (now - hoverAt) * MS < HOVER.ms
		local x = (pose.x or 0) * h
		local y = (pose.y or 0) * h
		local rot = (pose.rot or 0) * h
		local s = 1 + ((pose.scale or 1) - 1) * h
		local sx, sy = 1, 1
		local pressU = (now - pressAt) * MS / PRESS.ms
		if not reduced and pressU >= 0 and pressU < 1 then
			moving = true
			local ats, xs, ys = {}, {}, {}
			for _, f in PRESS.frames do
				table.insert(ats, f.at)
				table.insert(xs, f.sx or 0)
				table.insert(ys, f.sy or 0)
			end
			sx = 1 + amount * segmentAt(ats, xs, pressU, pressCurve)
			sy = 1 + amount * segmentAt(ats, ys, pressU, pressCurve)
		end
		local shakeU = (now - shakeAt) * MS / SHAKE.ms
		if not reduced and shakeU >= 0 and shakeU < 1 then
			moving = true
			local dx, turn = Button.shakeAt(shakeU, SHAKE.px, shakeCurve)
			x += dx
			rot += turn
		end
		local pulseT = (now - pulseAt) * MS
		if not reduced and pulseT >= 0 and pulseT < pulseDown + pulseUp then
			moving = true
			if pulseT < pulseDown then
				s *= 1 + (pulsePeak - 1) * ease(pulseT / pulseDown, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			else
				local k =
					ease((pulseT - pulseDown) / math.max(pulseUp, 1), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				s *= pulsePeak + (1 - pulsePeak) * k
			end
		end
		if decorated then
			scale.Scale = s * Button.decoratedScale(sx, sy)
		else
			-- About the face's centre (the CSS transform origin): Roblox turns and scales about the visual's centre,
			-- pivotPx below it.
			local turn = math.rad(rot)
			x -= s * pivotPx * math.sin(turn)
			y += pivotPx * (s * math.cos(turn) - 1)
			visual.Position = UDim2.new(0.5, math.round(x), 0.5, math.round(y))
			visual.Rotation = rot
			-- Roblox stops clipping under a turned ancestor: the shine strip hides while the visual is turned.
			local shine = visual:FindFirstChild("SD_Shine")
			if shine and shine:IsA("GuiObject") then
				shine.Visible = rot == 0
			end
			scale.Scale = s
			local b = visualSize
			visual.Size =
				UDim2.new(b.X.Scale * sx, math.round(b.X.Offset * sx), b.Y.Scale * sy, math.round(b.Y.Offset * sy))
			local inner = content
			if inner and contentScale then
				local c = inner.Size
				inner.Size = UDim2.new(if c.X.Scale > 0 then 1 / sx else 0, c.X.Offset, 1 / sy, c.Y.Offset)
				contentScale.Scale = math.sqrt(sx * sy)
			end
		end
		local filtering = onFilter ~= nil and (now - filterAt) * MS < filterMs() + 1000 / 60
		if filtering and onFilter then
			onFilter(feel.filterMix())
			moving = true
		end
		return moving
	end

	local function run()
		if handle ~= nil then
			return
		end
		frame(os.clock())
		handle = Scheduler.add(function(_dt: number, now: number): boolean
			local moving = frame(now)
			if not moving then
				handle = nil
				if onSettle then
					onSettle()
				end
			end
			return moving
		end, "render")
	end

	function feel.moving(): boolean
		return handle ~= nil
	end

	feel.frameAt = frame

	function feel.stop()
		local current = handle
		handle = nil
		if current then
			current:disconnect()
		end
	end
	cleanup:add(feel.stop)

	function feel.setHover(on: boolean)
		local now = os.clock()
		hoverFrom, hoverTo, hoverAt = hoverMix(now), if on then 1 else 0, now
		local bright = on and live()
		local mix = feel.filterMix()
		filterFrom, filterTo, filterAt = mix, if bright then 1 else 0, now
		run()
	end

	function feel.press()
		pressAt = os.clock()
		run()
	end

	function feel.shake()
		shakeAt = os.clock()
		run()
	end

	function feel.pulse(peak: number, downMs: number, upMs: number)
		pulseAt, pulsePeak, pulseDown, pulseUp = os.clock(), peak, math.max(0, downMs), math.max(0, upMs)
		run()
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

-- UI FINAL R2 (P1): a kind's default frame: its design face and the lip under it (base px).
function Button.frameHeight(kind: Kind?): number
	local style = Button.style(kind)
	return style.height + style.lip
end

-- UI FINAL R2: the design hover kind of a Button kind (spec.fx wins).
function Button.fxOf(kind: Kind?, fx: Fx?): Fx
	return fx or KIND_FX[kind or "secondary"] or "btn"
end

-- UI FINAL R2 (T4, H:637): a face colour under CSS filter brightness(b) then saturate(s) (each step clamped to 0..1;
-- the saturate matrix of the CSS Filter Effects spec). Defaults: Config.UI.motion.buttonHover's 1.07 and 1.06.
function Button.hoverColor(color: Color3, brightness: number?, saturate: number?): Color3
	local b = brightness or HOVER.brightness
	local s = saturate or HOVER.saturate
	local r = math.clamp(color.R * b, 0, 1)
	local g = math.clamp(color.G * b, 0, 1)
	local bl = math.clamp(color.B * b, 0, 1)
	local r2 = (0.213 + 0.787 * s) * r + (0.715 - 0.715 * s) * g + (0.072 - 0.072 * s) * bl
	local g2 = (0.213 - 0.213 * s) * r + (0.715 + 0.285 * s) * g + (0.072 - 0.072 * s) * bl
	local b2 = (0.213 - 0.213 * s) * r + (0.715 - 0.715 * s) * g + (0.072 + 0.928 * s) * bl
	return Color3.new(math.clamp(r2, 0, 1), math.clamp(g2, 0, 1), math.clamp(b2, 0, 1))
end

-- UI FINAL R2 (PR4): the press squash's (sx, sy) at u (0..1) of Config.UI.motion.buttonPress for a kind's amount
-- (buttonPress.amount x amountByKind; lib:287-293), each segment eased by its curve.
function Button.squashAt(u: number, amount: number): (number, number)
	local curve = Tweens.curve(PRESS.curve)
	local ats, xs, ys = {}, {}, {}
	for _, f in PRESS.frames do
		table.insert(ats, f.at)
		table.insert(xs, f.sx or 0)
		table.insert(ys, f.sy or 0)
	end
	return 1 + amount * segmentAt(ats, xs, u, curve), 1 + amount * segmentAt(ats, ys, u, curve)
end

-- UI FINAL R2 (PR5): the "no" shake's x offset (px) and turn (degrees) at u (0..1) of Config.UI.motion.buttonShake
-- (lib:297: translateX(v·px) rotate(v·rotDeg)), each step eased by `curve` (default its curve).
function Button.shakeAt(u: number, px: number, curve: Tweens.Curve?): (number, number)
	local steps = SHAKE.steps
	local ats = {}
	for index = 1, #steps do
		table.insert(ats, (index - 1) / (#steps - 1))
	end
	local v = segmentAt(ats, steps, u, curve or Tweens.curve(SHAKE.curve))
	return v * px, v * SHAKE.rotDeg
end

-- UI FINAL R2 (PR4, a reading): the uniform scale a decorated object (Button.decorate: a UIScale only) draws for a
-- squash (sx, sy): its Config.UI.motion.buttonPress.decoratedAxis series (sy: .86 at 20%, so a tap shows a press).
function Button.decoratedScale(sx: number, sy: number): number
	return if PRESS.decoratedAxis == "sx" then sx else sy
end

-- UI FINAL R4 (PR6, H:639): the nav sticker's hover wiggle at u (0..1) of Config.UI.motion.navWiggle.ms: its angles
-- (degrees) evenly spaced, linear between them (the Web Animations default); 0 outside the run.
function Button.wiggleAt(u: number): number
	local angles = WIGGLE.angles
	if not (u > 0 and u < 1) or #angles < 2 then
		return 0
	end
	local span = u * (#angles - 1)
	local index = math.floor(span) + 1
	local k = span - (index - 1)
	return angles[index] + (angles[index + 1] - angles[index]) * k
end

-- UI FINAL R2: the automatic width to keep: `measured`, unless the button is `moving` (or scaled by a UIScale above it)
-- and `measured` is within WIDTH_SLACK_PX of the `natural` width it has (a scaled size's rounding, not a new text).
function Button.settledWidth(natural: number, measured: number, moving: boolean): number
	if moving and natural > 0 and math.abs(measured - natural) <= WIDTH_SLACK_PX then
		return natural
	end
	return measured
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

-- Gives a plain GuiButton (e.g. the coin pill) the Button feel on its own UIScale "Scale": the hover scale of its
-- design kind (options.fx, default "btn"), the press squash as one uniform scale (Button.decoratedScale; it may sit in
-- a layout: no lift, tilt or non-uniform squash), pulse(), and ui.click / ui.hover unless options.sound == false
-- (options.clickSound == false: the hover only). The returned handle's destroy() removes it all.
function Button.decorate(guiButton: GuiButton, options: DecorateOptions?): Decorated
	local cleanup = Cleanup.new()
	local soundOn = not (options and options.sound == false)
	local clickOn = soundOn and not (options and options.clickSound == false)
	local fx: Fx = if options and options.fx then options.fx else "btn"
	local feel = newFeel(guiButton, guiButton.Size, nil, fx, cleanup, function(): boolean
		return true
	end, nil, true, 0, nil)
	cleanup:add(feel.scale)
	cleanup:add(guiButton.MouseEnter:Connect(function()
		if not lastInputIsMouse() then
			return
		end
		feel.hovered = true
		feel.setHover(true)
		if soundOn then
			playSound(SOUND_HOVER, HOVER_PITCH[fx])
		end
	end))
	cleanup:add(guiButton.MouseLeave:Connect(function()
		feel.hovered = false
		feel.setHover(feel.focused)
	end))
	cleanup:add(guiButton.InputBegan:Connect(function(input: InputObject)
		if isPointer(input) then
			feel.press()
		end
	end))
	cleanup:add(guiButton.SelectionGained:Connect(function()
		feel.focused = true
		feel.setHover(true)
	end))
	cleanup:add(guiButton.SelectionLost:Connect(function()
		feel.focused = false
		feel.setHover(feel.hovered)
	end))
	if clickOn then
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
	local chip = spec.size == "chip"
	local base = Button.style(kind)
	-- UI FINAL R2 (P12): the button's own numbers over its kind's.
	local style = base
	local surfaceSpec: string | Surface = base.surface
	if chip or spec.radius or spec.border or spec.lip or spec.highlight or spec.bevel then
		local look = STICKER.surfaces[if chip then "chip" else base.surface] or STICKER.surfaces.primary
		local surface: Surface = {
			highlightPx = if spec.highlight then spec.highlight.px else look.highlightPx,
			highlightAlpha = if spec.highlight then spec.highlight.a else look.highlightAlpha,
			bevelPx = if spec.bevel then spec.bevel.px elseif chip then nil else look.bevelPx,
			bevelAlpha = if spec.bevel then spec.bevel.a elseif chip then nil else look.bevelAlpha,
		}
		surfaceSpec = surface
		style = sticker(
			if chip then "greenChip" else base.accent,
			surface,
			spec.radius or (if chip then CHIP_RADIUS else base.radius),
			spec.border or (if chip then STICKER.border.thin else base.border),
			spec.lip or (if chip then STICKER.lip.bar else base.lip),
			if chip then CHIP_PADDING_X else base.paddingX,
			if chip then CHIP_FACE else base.height,
			base.iconPx
		)
	end
	local tile = kind == "tile"
	local iconOnly = kind == "close"
	local stacked = tile or iconOnly -- the icon above (or, for close, instead of) the label
	local accentName: Theme.AccentName = spec.accent or style.accent
	local accent = Theme.accent(accentName)
	-- UI FINAL R2 (P1): the face, the frame (face + lip) and the hit box (the frame, at least the touch minimum).
	local height = spec.height or style.height
	local frameHeight = height + style.lip
	-- UI FINAL R4 (PR1): a close X narrower than the touch minimum keeps its face width inside a minimum-wide hit box.
	local fixedWidth: number? = spec.width
		or (if tile then TILE_SIZE elseif iconOnly then math.max(height, TOUCH.minTarget) else nil)
	local faceWidth: number? = if iconOnly and spec.width == nil and height < TOUCH.minTarget then height else nil
	-- UI FINAL R4: the side paddings (the DUEL button's own, H:126) and the faceless sticker (P13).
	local padLeft = spec.padLeft or style.paddingX
	local padRight = spec.padRight or style.paddingX
	local faceless = style.faceless == true
	-- G2.7: a silent kind's `sound = false` silences its click only (the design keeps every hover sound, H:638).
	local hoverOn = spec.sound ~= false or SILENT_KINDS[kind] == true
	local clickOn = spec.sound ~= false and spec.clickSound ~= false and not SILENT_KINDS[kind]
	local fx: Fx = Button.fxOf(kind, spec.fx)
	-- UI FINAL R1: the content is raised so it sits centred on the face (Style.shift).
	local shift = style.shift
	local iconName: string? = spec.icon or (if iconOnly then "close" else nil)
	local inLine = not stacked and (spec.icon ~= nil or spec.keycap ~= nil or spec.subtext ~= nil)
	local textKind: Theme.TextKind = spec.textKind
		or (if tile then "Chip" elseif chip then CHIP_TEXT_KIND else "Button")
	local naturalWidth = 0 -- the automatic width (measured)
	local minWidth = 0 -- a caller's own root width under an automatic width (AutomaticSize X kept it as a minimum)
	local lastWidth = -1 -- the root width this module last wrote
	local rootHeight = math.max(frameHeight, TOUCH.minTarget)

	local root: TextButton = Create("TextButton", {
		Name = spec.name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(fixedWidth or Button.widthFor(spec.text, nil, textKind, kind), rootHeight),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	-- The drawn button: fills the hit box; a frame under the touch minimum keeps its height, centred in it (PR1).
	local visual: Frame = Create("Frame", {
		Name = "SD_Visual",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(
			if faceWidth then UDim.new(0, faceWidth) else UDim.new(1, 0),
			if frameHeight < rootHeight then UDim.new(0, frameHeight) else UDim.new(1, 0)
		),
		BackgroundTransparency = if faceless then 1 else 0,
		BorderSizePixel = 0,
		Active = false,
		Parent = root,
	})
	local foam: Theme.Foam? = if faceless
		then nil
		else Theme.foam(visual, {
			radius = style.radius,
			stroke = style.border,
			inner = style.inner,
			top = style.top,
			bevel = style.bevel,
			drop = style.drop,
			colors = Theme.surfaceColors(accent, surfaceSpec, true),
		})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, padLeft),
		PaddingRight = UDim.new(0, padRight),
		Parent = visual,
	})
	-- UI FINAL R2 (P2, G4.13): the moving shine strip (H:127): a holder inset by the border on every side, the face's
	-- height only, its corner the radius less the border, clipping a px strip that crosses it by itself (UiIdle) with
	-- the leaning band in it (Theme.shineBand); hidden while SD_Visual is turned (Roblox stops clipping under a turn).
	local shineHandle: UiIdle.Handle? = nil
	local function applyShine(on: boolean)
		local existing = visual:FindFirstChild("SD_Shine")
		local shineName = SHINE_KINDS[kind]
		if not (on and shineName) then
			if existing then
				existing:Destroy()
			end
			return
		end
		if existing then
			return
		end
		local spec2 = (STICKER.shines :: any)[shineName]
		local b = style.border
		local clip: Frame = Create("Frame", {
			Name = "SD_Shine",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(b - padLeft, b),
			Size = UDim2.new(1, padLeft + padRight - 2 * b, 1, -2 * b - style.lip),
			ClipsDescendants = true,
			Active = false,
			ZIndex = 0,
			Parent = visual,
		})
		Theme.corner(math.max(0, style.radius - b), clip)
		local strip: Frame = Create("Frame", {
			Name = "Strip",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, -spec2.overhangPx),
			Size = UDim2.new(0, spec2.px, 1, 2 * spec2.overhangPx),
			Active = false,
			ZIndex = 0,
			Parent = clip,
		})
		Theme.shineBand(strip, spec2.alpha, spec2.slantDeg) -- H:28
		clip.Visible = visual.Rotation == 0
		shineHandle = UiIdle.add(strip, "shine", { periodS = spec2.periodS })
	end
	cleanup:add(function()
		local current = shineHandle
		if current then
			current:remove()
		end
	end)
	applyShine(true)

	-- The content keeps its size through a squash (Size 1 / sx of the squashed visual) and is centred on the face.
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -shift),
		Size = UDim2.fromScale(if fixedWidth then 1 else 0, 1),
		AutomaticSize = if fixedWidth then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		Parent = visual,
	})
	-- UI FINAL R4: the faceless sticker's label is pulled up over its picture (H:101: margin-top -28; a negative list
	-- gap, the label drawn above), top-aligned; spec.align = "left" lines the content up on the left padding.
	local labelPull = if faceless then spec.labelPull or NAV.labelPull else 0
	Theme.list(
		Enum.FillDirection.Vertical,
		if faceless then -labelPull elseif stacked then TILE_GAP else 0,
		content,
		if spec.align == "left" then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Center,
		if faceless then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center
	)

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
		Theme.list(Enum.FillDirection.Vertical, spec.textGap or 0, texts, Enum.HorizontalAlignment.Left)
		line = row
	end

	local icon: IconGlyph.IconGlyph? = nil
	-- UI FINAL R4 (P13): the faceless sticker's picture: Icon (laid out, the icon size) > SD_Bob (sdBob) > SD_Wiggle
	-- (the hover wiggle) > the picture with its drop shadow and, over it, its white copy (the hover's brightness).
	local picture: Frame? = nil
	local wiggle: Frame? = nil
	local brighten: ImageLabel? = nil
	local slot = if iconName then IconGlyph.slotOf(iconName) else nil
	local pictureId = if faceless and slot then AssetTable.image(slot) else nil
	if faceless and iconName then
		local size = spec.iconSize or style.iconPx
		local holder: Frame = Create("Frame", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
			LayoutOrder = 0,
			Parent = content,
		})
		local bob: Frame = Create("Frame", {
			Name = "SD_Bob",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = holder,
		})
		local turn: Frame = Create("Frame", {
			Name = "SD_Wiggle",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Parent = bob,
		})
		if pictureId and slot then
			local image =
				IconGlyph.image(slot, { name = "Picture", sizePx = size, shadow = spec.iconShadow, parent = turn })
			image.Size = UDim2.fromScale(1, 1)
			local white = IconGlyph.image(slot .. WHITE_SUFFIX, { name = "SD_Brighten", sizePx = size, parent = turn })
			white.Size = UDim2.fromScale(1, 1)
			white.ZIndex = 2
			local whiteImage = white:FindFirstChild("Image")
			if whiteImage and whiteImage:IsA("ImageLabel") and white.Visible then
				whiteImage.ImageTransparency = 1
				brighten = whiteImage
			end
		else
			icon = IconGlyph.new({ name = "Picture", icon = iconName, sizePx = size, parent = turn })
			cleanup:add(icon)
			local glyph = icon :: IconGlyph.IconGlyph
			glyph.root.Size = UDim2.fromScale(1, 1)
		end
		if spec.bob then
			local handle = UiIdle.add(bob, "bob", { periodS = spec.bob.periodS, delayS = spec.bob.delayS })
			if handle then
				cleanup:add(function()
					handle:remove()
				end)
			end
		end
		picture = holder
		wiggle = turn
	elseif iconName then
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
		-- UI FINAL R4: the sticker's label over its picture (H:101 z-index 1).
		ZIndex = if faceless then 2 else 1,
		Parent = texts or content,
	}, textKind)
	-- UI FINAL R4: the design's text roles (outline, drop, colour; Config.UI.Sticker.text).
	if spec.textRole then
		Theme.stickerText(label, spec.textRole)
		label.TextWrapped = wraps
	end
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
		if spec.subtextRole and subLabel then
			Theme.stickerText(subLabel, spec.subtextRole)
			subLabel.TextWrapped = false
		end
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
		Parent = visual,
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
		local made = CountBadge.new({ name = "Badge", accent = spec.badgeAccent, parent = visual })
		if faceless then
			-- UI FINAL R4 (H:102): inside the sticker, its right edge 8 from the tile's and its top on the tile's; the
			-- sdBadge loop (H:32) on the badge itself (no layout places it). Centre-anchored at its 32 px resting size
			-- (CountBadge.SIZE_PX), so the loop's pop (a UIScale, about the AnchorPoint) grows evenly round it as the
			-- CSS transform-origin does (a wider count or text size grows it both ways: stated).
			local half = CountBadge.SIZE_PX / 2
			made.root.AnchorPoint = Vector2.new(0.5, 0.5)
			made.root.Position = UDim2.new(1, padRight - NAV.badgeRight - half, 0, NAV.badgeTop + half)
			if spec.badgeDelay ~= nil then
				local handle = UiIdle.add(made.root, "badge", { delayS = spec.badgeDelay })
				if handle then
					cleanup:add(function()
						handle:remove()
					end)
				end
			end
		else
			made.root.AnchorPoint = Vector2.new(0.5, 0.5)
			made.root.Position = UDim2.new(1, padRight - BADGE_INSET, 0, BADGE_INSET)
		end
		cleanup:add(made)
		badge = made
		return made
	end
	-- UI FINAL R4: a badge with a mark (the daily "!", H:120) shows it for any count >= 1.
	local function showBadge(count: number?)
		local made = ensureBadge()
		if spec.badgeMark ~= nil then
			made:setText(if CountBadge.text(count) ~= nil then spec.badgeMark else nil)
		else
			made:setCount(count)
		end
	end
	if spec.badge then
		showBadge(spec.badge)
	end

	-- UI FINAL R2 (PR24): the gamepad focus ring drawn in SD_Visual round the face (the lip left out), so it takes the
	-- pose, squash and shake with it; the hit box keeps Roblox's selection with a clear image.
	root.Selectable = true
	root.SelectionImageObject = Focus.blank()
	local focusRing = (Focus.selectionImage(style.radius, { top = 0, bottom = style.lip }):Clone() :: any) :: Frame
	-- SD_Visual's side padding moves its children in: the ring reaches back out over it.
	focusRing.Position -= UDim2.fromOffset(padLeft, 0)
	focusRing.Size += UDim2.fromOffset(padLeft + padRight, 0)
	focusRing.Visible = false
	focusRing.ZIndex = FOCUS_RING_Z
	focusRing.Parent = visual

	local state: State = "normal"
	local off = false
	local offPriceColor: Color3? = nil
	local spinnerHandle: Scheduler.Handle? = nil

	-- The sticker colours of the current state (UI FINAL R1: the disabled sticker of H:246; R2: the hover filter's mix,
	-- T4, and a 2-stop override, P12).
	local function surfaceColors(mix: number): Theme.FoamColors
		if state == "disabled" then
			return Theme.surfaceColors(Theme.Accents.disabled, "disabled", true)
		end
		local face = accent
		if spec.stops == 2 then
			face = { face = accent.top, shade = accent.shade, light = accent.light, top = accent.top }
		end
		local colors = Theme.surfaceColors(face, surfaceSpec, true) :: Theme.StickerColors
		if mix <= 0 then
			return colors :: any
		end
		local function lift(color: Color3?): Color3?
			return if color then color:Lerp(Button.hoverColor(color), mix) else nil
		end
		local lifted: Theme.StickerColors = {
			face = lift(colors.face) :: Color3,
			mid = lift(colors.mid),
			midAt = colors.midAt,
			faceEnd = lift(colors.faceEnd),
			top = lift(colors.top),
			bevel = lift(colors.bevel),
			drop = colors.drop,
		}
		return lifted :: any
	end

	local measure: () -> () -- the automatic width (below)
	local feel = newFeel(
		visual,
		visual.Size,
		content,
		fx,
		cleanup,
		function(): boolean
			return state == "normal" and not off
		end,
		function(mix: number)
			local face = foam
			if face then
				face:paint(surfaceColors(mix))
			end
			-- UI FINAL R4 (G4.20): the faceless sticker brightens through its picture's white copy (brightness 1.07:
			-- .07 of white over it; pictures cannot go above 1, plan §1.4).
			local white = brighten
			if white then
				white.ImageTransparency = 1 - (HOVER.brightness - 1) * mix
			end
		end,
		false,
		style.lip / 2,
		function()
			measure()
		end
	)

	-- Text and icon colours of the current state and accent (the outlined-text rule on an accent face).
	local function paintText()
		local disabled = state == "disabled"
		-- UI FINAL R4: a label styled by a design text role keeps its role's colour and outline.
		local shown: { TextLabel } = if spec.textRole then {} else { label }
		if subLabel and not spec.subtextRole then
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
		local sub = subLabel
		if sub and off and offPriceColor then
			Theme.textOnLight(sub, offPriceColor)
		end
		-- UI FINAL R1: white with the ink outline (H:246's text), readable on the lilac face and over the ink lip.
		Theme.textOnLight(reasonLabel, Theme.Colors.white)
		local glyph = icon
		if glyph then
			glyph:setTone(if disabled then "disabled" elseif accent.light then "dark" else "light")
		end
	end

	local function refreshVisual()
		local face = foam
		if face == nil then
			return -- UI FINAL R4: the faceless sticker has nothing to paint
		end
		face:paint(surfaceColors(if feel.live() then feel.filterMix() else 0))
		face:setStroke(if state == "disabled" then Theme.Colors.disabledStroke else Theme.Colors.inkUI)
	end

	-- UI FINAL R4 (PR6, H:639): the nav sticker's picture wiggles once on a mouse hover, added on top of its bob
	-- (SD_Wiggle under SD_Bob), linear over navWiggle.ms; none under ReducedMotion.
	local wiggleHandle: Scheduler.Handle? = nil
	local function playWiggle()
		local turn = wiggle
		if turn == nil or fx ~= "nav" or Tweens.reducedMotion() then
			return
		end
		if wiggleHandle then
			wiggleHandle:disconnect()
		end
		local started = os.clock()
		wiggleHandle = Scheduler.add(function(_dt: number, now: number): boolean
			local u = (now - started) * MS / WIGGLE.ms
			turn.Rotation = Button.wiggleAt(u)
			if u >= 1 then
				wiggleHandle = nil
				return false
			end
			return true
		end, "render")
	end
	cleanup:add(function()
		if wiggleHandle then
			wiggleHandle:disconnect()
			wiggleHandle = nil
		end
	end)

	-- UI FINAL R2: an automatic width follows the content's natural width (as AutomaticSize X did; a caller's own root
	-- width is kept as a minimum). Measured from the content (its AbsoluteSize over every UIScale up to the ScreenGui);
	-- before it is drawn (Edit mode), Button.widthFor's estimate. While it moves (or a UIScale above it is not 1), a
	-- 1 px change is the scaled size's rounding: kept out (Button.settledWidth); the settle measures again.
	local function applyWidth()
		if fixedWidth ~= nil then
			return
		end
		local want = math.max(minWidth, naturalWidth)
		if root.Size.X.Offset ~= want or root.Size.X.Scale ~= 0 then
			lastWidth = want
			root.Size = UDim2.new(0, want, root.Size.Y.Scale, root.Size.Y.Offset)
		end
	end
	local function measureNow(exact: boolean)
		if fixedWidth ~= nil then
			return
		end
		local absolute = content.AbsoluteSize.X
		local measured = if absolute > 0
			then math.ceil(absolute / scaleChain(content) - 0.01) + padLeft + padRight
			else Button.widthFor(label.Text, if reasonLabel.Visible then reasonLabel.Text else nil, textKind, kind)
		if not exact then
			measured = Button.settledWidth(naturalWidth, measured, feel.moving() or not scalesAtRest(content))
		end
		if measured ~= naturalWidth then
			naturalWidth = measured
			applyWidth()
		end
	end
	measure = function()
		measureNow(false)
	end
	-- A new text, state or width: measured at once, whatever moves.
	local function remeasure()
		measureNow(true)
	end
	cleanup:add(content:GetPropertyChangedSignal("AbsoluteSize"):Connect(measure))
	cleanup:add(root:GetPropertyChangedSignal("Size"):Connect(function()
		if fixedWidth == nil and root.Size.X.Offset ~= lastWidth then
			minWidth = root.Size.X.Offset -- a caller's own width: a minimum
			applyWidth()
		end
	end))

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

	-- A press: the squash on a live button, the error and the "no" shake on a disabled or off one; nothing loading.
	local function pressed()
		if state == "disabled" or (state == "normal" and off) then
			playSound(SOUND_ERROR)
			feel.shake()
		elseif state == "normal" then
			feel.press()
		end
	end

	local function hoverStart()
		feel.hovered = true
		feel.setHover(true)
		if hoverOn and state ~= "loading" then
			playSound(SOUND_HOVER, HOVER_PITCH[fx])
		end
		playWiggle() -- UI FINAL R4 (PR6): the nav sticker's picture (mouse hover only)
	end
	local function hoverEnd()
		feel.hovered = false
		feel.setHover(feel.focused)
	end
	local function selected(on: boolean)
		feel.focused = on
		feel.setHover(on or feel.hovered)
		focusRing.Visible = on
	end
	-- The design presses on pointer-down (H:611): the mouse at once; a touch only squashes a live button, since a
	-- finger that starts a scroll on a disabled or off one never taps it (its error and shake wait for the tap).
	local function pointerDown(inputType: Enum.UserInputType)
		if inputType == MOUSE_PRESS then
			pressed()
		elseif inputType == TOUCH_PRESS and state == "normal" and not off then
			feel.press()
		end
	end
	-- Activated: a gamepad or key activation (no pointer press) and a finished tap on a disabled or off button press
	-- now; a live (or off) button runs its action.
	local function activated(inputType: Enum.UserInputType?)
		local live = state == "normal" and not off
		local pointer = inputType == MOUSE_PRESS or inputType == TOUCH_PRESS
		if not pointer or (inputType == TOUCH_PRESS and not live) then
			pressed()
		end
		if state ~= "normal" then
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
		if clickOn and not off then
			playSound(SOUND_CLICK)
		end
	end

	cleanup:add(root.MouseEnter:Connect(function()
		if lastInputIsMouse() then
			hoverStart()
		end
	end))
	cleanup:add(root.MouseLeave:Connect(hoverEnd))
	cleanup:add(root.InputBegan:Connect(function(input: InputObject)
		pointerDown(input.UserInputType)
	end))
	cleanup:add(root.SelectionGained:Connect(function()
		selected(true)
	end))
	cleanup:add(root.SelectionLost:Connect(function()
		selected(false)
	end))
	cleanup:add(root.Activated:Connect(function(input: InputObject?)
		activated(if input then input.UserInputType else nil)
	end))

	paintText()
	refreshVisual()
	remeasure()
	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: Button
	self.root = root
	self.visual = visual

	-- Edit-mode tests (see the header): the handlers the events run, and one frame of the motion `arg` s ahead.
	local seam = self :: any
	seam._simulate = function(_: any, event: string, arg: any?)
		if event == "hover" then
			hoverStart()
		elseif event == "unhover" then
			hoverEnd()
		elseif event == "select" then
			selected(true)
		elseif event == "unselect" then
			selected(false)
		elseif event == "press" then
			pointerDown(arg or MOUSE_PRESS)
		elseif event == "activate" then
			activated(arg)
		elseif event == "frame" then
			feel.frameAt(os.clock() + (arg or 0))
		end
	end

	function self.setText(_: Button, text: string)
		label.Text = Button.displayText(text, kind)
		remeasure()
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
		local art = picture
		if art then
			art.Visible = not loading -- UI FINAL R4: the faceless sticker's picture
		end
		reasonLabel.Text = if disabled and reason then reason else ""
		reasonLabel.Visible = disabled and reason ~= nil and reason ~= ""
		spinner.Visible = loading
		if loading then
			startSpinner()
		else
			stopSpinner()
		end
		paintText()
		if feel.hovered or feel.focused then
			feel.setHover(true) -- the filter follows the new state; at rest nothing moves
		end
		refreshVisual()
		remeasure()
	end

	function self.getState(_: Button): State
		return state
	end

	-- UI FINAL R2 (P11): the "off" state (see the header).
	function self.setOff(_: Button, isOff: boolean, priceColor: Color3?)
		off = isOff
		offPriceColor = priceColor
		paintText()
		if feel.hovered or feel.focused then
			feel.setHover(true) -- the filter follows the new state; at rest nothing moves
		end
		refreshVisual()
	end

	function self.isOff(_: Button): boolean
		return off
	end

	function self.pulse(_: Button, peak: number, downMs: number, upMs: number)
		if Tweens.reducedMotion() then
			return
		end
		feel.pulse(peak, downMs, upMs)
	end

	-- A fixed width (the label and the reason wrap inside it; a row stays one line) or, with nil, the automatic width.
	-- The height stays.
	function self.setWidth(_: Button, widthPx: number?)
		local fixed = widthPx ~= nil
		fixedWidth = widthPx
		if fixed then
			lastWidth = widthPx :: number
			root.Size = UDim2.new(0, widthPx :: number, root.Size.Y.Scale, root.Size.Y.Offset)
		else
			minWidth = 0
		end
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
		if not fixed then
			naturalWidth = 0
			remeasure()
		end
	end

	function self.setAccent(_: Button, name: Theme.AccentName)
		accent = Theme.accent(name)
		paintText()
		refreshVisual()
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
		showBadge(count)
	end

	-- UI FINAL R2 (P2): the strip crosses by itself every Config.UI.Sticker.shines.cta.periodS (UiIdle); kept for its
	-- caller.
	function self.sweep(_: Button) end

	function self.destroy(_: Button)
		cleanup:clean()
	end

	return self
end

return Button
