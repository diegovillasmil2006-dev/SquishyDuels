--!strict
-- Theme (client only). DESIGN §11.1, §11.2, §7.2; the foam UI restyle (spec docs/superpowers/specs/
-- 2026-10-09-foam-ui-restyle-design.md, API guide 2026-10-09-foam-ui-components.md): the UI tokens (colours from
-- Art/Palette, fonts, radii, paddings, foam bands), the text helpers and the foam surface helpers.
-- * Fonts (UI FINAL R1): every kind draws in Fredoka One, Font.fromEnum(Enum.Font.FredokaOne): the design's Fredoka 700
--   everywhere (H:14, H:19) in the one built-in Fredoka face, so every text measure is exact (TextService:GetTextSize).
-- * Theme.text(object, kind) ALWAYS sets FontFace and TextSize (new TextButtons default to Legacy at size 8, V):
--   size = Config.UI.TextSize[kind] × the GuiService.PreferredTextSize multiplier (UI/Layout); the ScreenGui's UIScale
--   multiplies it on screen. The kind is stored as attribute SD_TextKind so refreshText(root) can re-apply every size
--   when PreferredTextSize changes (UIController listens). Text containers wrap and use AutomaticSize.Y (§11.2);
--   TextScaled is only for the countdown (with a UITextSizeConstraint). The default colour is white (Colors.text).
-- * The outlined-text rule (UI FINAL R1, plan work/ui/PLAN.md §1.3): text in a light colour carries the ink outline (a
--   Contextual UIStroke with round joins, outlinePx(kind) thick: the design's -webkit-text-stroke halved), text in a
--   dark colour (the ink, the pink-window text) none. Every kind may carry it (all are display kinds of at least
--   OUTLINE_MIN_BASE_PX). textOnColor(object) makes text on an accent face white and outlined, textOnLight(object) the
--   ink with none (a light colour given to it keeps the outline), textOnWindow(object) the pink window's text. The
--   reserved gameplay colours (Danger, Coin*) stay where §7.2 allows them. The outline follows its label's
--   TextTransparency (a UIStroke does not fade with its text); noOutline(object) takes it off for good, for a label
--   that draws an outline of its own (the duel and practice reticles, the squeeze floats, the HUD's small "+N").
-- * Foam surfaces: foam(object, style) gives a GuiObject the foam look with no extra GuiObjects (so a UIListLayout
--   inside it is never disturbed): a UICorner, an ink UIStroke (outer; `inner` draws it inside the box, the design's
--   border-box border) and a vertical UIGradient that paints a top highlight band, the face, a bottom bevel shade band
--   and a bottom ink "drop" band (Layout.foamStops; Layout.stickerBands for a sticker surface), kept in base px as the
--   object resizes (its AbsoluteSize over the UIScales above it). Mode "exact" paints the given colours over a white
--   background (Button, chips, tabs); mode "tint" keeps the object's own BackgroundColor3 as the face and darkens the
--   bands by ratios (panel(): a caller may recolour a panel later and still gets a matching gradient).
--   Readings: the drop (the design's lip) is drawn inside the surface's box (a UIGradient cannot paint outside it), so
--   a foam surface never reaches past its layout box apart from an outer stroke; a "tint" surface has no top highlight
--   (a ratio can only darken).
-- * panel(props, radius?, padding?): the purple card; its bottom padding is at least the bands plus PANEL_BAND_GAP.
--   headerTab(panel, text, options?): the title tab straddling a panel's top edge. inset(props, radius?, padding?): the
--   well, a recessed field with the ink border.
-- * Measuring (Part 8): textBounds(text, kind, weight?, wrapWidth?) / textWidth(...) / lineHeight(kind, weight?)
--   measure a text in base px at the player's text size with TextService:GetTextSize and Enum.Font.FredokaOne (the
--   weight is kept in the signatures; Fredoka One has one face). Reading: when TextService cannot answer a generous
--   estimate is used (MEASURE_FALLBACK_EM per character, MEASURE_FALLBACK_LINE lines), so a layout errs on the roomy
--   side.
-- UI FINAL R1 (the look kit of the design "Squishy Duels UI FINAL", 2026-10-14; plan work/ui/PLAN.md R1; `H:n` = its
-- "Squishy Duels HUD.dc.html" line n). Theme reads the Art/Palette Sticker tokens (the Candy UI tokens stay in Palette,
-- unread but StickerBevel, the world plates' bevel) and Config.UI.Sticker (Theme.Sticker):
-- * Colours: the ink for every outline and lip; the purple card (panel, panelAlt; its bottom stop `bevel`); the well
--   (biscuit) and the trough (track); white text, captions (ink2) and soft text (textFaint); the pink-window text
--   (textOnWindow); the purple dimmer (backdrop); the disabled lilac; gold text in the coin yellow. The world UI keeps
--   its tokens.
-- * Accents keep their names, each on its design hue (Accent.top -> mid at midAt -> shade: the gradient's stops; `face`
--   its main colour, the mid stop of a 3-stop gradient, else the top): strawberry / pink the DUEL pink, mint / quests
--   the mint, lilac the purple bar, sky / cyan the secondary cyan, shop / green the primary green (127° of hue, 84°
--   from CoinGold), gold, red / closeRed the close red, plum the purple pill, frosting the cream sticker (ink text);
--   and disabled, cancel, yellow, ult (the Ultimate's gold, ink text: a ready Ultimate never looks disabled).
-- * surfaceColors(accent, surface?, highlight?) paints a design surface (Config.UI.Sticker.surfaces): its face
--   gradient, the inset highlight (the top stop towards white), the bevel (the end stop towards black or the surface's
--   tint) and the ink drop. accentColors(name, highlight?, surface?) does it for an accent name.
-- * stickerText(label, role) styles a label as a Config.UI.Sticker text role: the kind, the colour, the outline (stroke
--   / 2) and, for a role with a drop of DROP_MIN_PX or more, the solid ink drop under the letters: the label stays the
--   source of truth (Text, TextColor3, TextTransparency; TextBounds read on it) with its own glyphs hidden
--   (MaxVisibleGraphemes 0), and two mirrored children draw it: SD_Drop (ink, `drop` px lower) and SD_Face (its colour,
--   above), each with the outline. UI FINAL R2 (T5, PR3): a role's `soft` drop (the design's 1-2 px text-shadow at an
--   alpha) is drawn the same way, its SD_Drop in the soft colour at that alpha with no outline. setSurface(panel,
--   colors) repaints a Theme.panel in exact colours.
-- * UI FINAL R2: radial(frame, key, fallback) is the design's radial-gradient as its exact picture (pack 2, alpha
--   baked; P3), else the fallback: the outer colour at its alpha with the img.fx.glow picture tinted the inner colour
--   (and a mid one) centred where the CSS centres it; rays(parent, key, sizePx, alpha, periodS, centreY?) a rays
--   picture centred at centreY of its parent (P4), turning through Anim/UiIdle; softShadow(wrapper, key, spec) the
--   design's soft box-shadow as a 9-slice picture behind the wrapper's target (T1, T2; the glow tinted while nil);
--   shineBand(strip, alpha, slantDeg) the leaning white band of the design's sdShine in a px strip (H:28, G4.13).
-- * UI FINAL R3 (the window frame, plan work/ui/PLAN.md R3; Config.UI.Sticker.window): window(props, kind,
--   padding?) is the design's window (H:182: the pink body #FFD6EC -> #FFAFD6, a 5 px ink border drawn inside, radius
--   32, the 10 px ink lip under the face; Active, so a click on it never reaches the scrim under it); headerTab on a
--   window is the design's header band (H:183-184): the band across the window's top inside its border, its gradient
--   with the dots and the inset highlight and bevel, its 5 px bottom border, its top corners rounded 27 (a clip
--   holder: ClipsDescendants ignores UICorner), the title left-aligned in capitals (Q5) in the windowTitle role
--   (Settings' small band: settingsTitle), an `extra` at its right end (H:185, H:260), the kind's sticker hanging off
--   the top-left corner (H:251: sdBob from the start, sdStick on every open through playSticker) and the close X at
--   (right -22, top -22) inside the band (attachClose); the Squishies window's faint inner ring (H:182).
--   fitWindow(window, k) lays the band out for the chrome scale k (Layout.windowFit: the band, its paddings, the
--   sticker and the title shrink with a window that shrinks; the title also shrinks to its room, never under 16 base
--   px; the band's right end keeps clear of the X) and sets the window's top padding (the band, then the body's
--   padding); it returns { top, above, band, k } (fittedChrome keeps the last; the band fits again when the window's
--   Size or its extra's size changes). scrim(props) is the window scrim (H:178: the radial picture, else its fallback;
--   a TextButton, so a click on it closes the top window), scrollbar(frame) the design's scroll bar (H:22). Other
--   panels keep headerTab's tab (the box reveal, R7; the capsule card, its system is being replaced), without the
--   Candy shine and header glow, which went with the jelly bubbles. rim() stays (cards, the tab, the coach).
--   panelColors() and stickerColors() return the new tokens.

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Layout = require(script.Parent.Layout)
local Create = require(script.Parent.Create)
local Scheduler = require(script.Parent.Parent.Anim.Scheduler)
local Tweens = require(script.Parent.Parent.Anim.Tweens)
local UiIdle = require(script.Parent.Parent.Anim.UiIdle)

-- Types

export type TextKind =
	"Title"
	| "H2"
	| "Body"
	| "Small"
	| "Button"
	| "HudNumber"
	| "Countdown"
	| "Chip"
	| "Big"
	| "Large"
	| "Coin"
	| "Name"
	| "Found"
	| "Ribbon"
	| "Hero"
	| "WindowSmall"
	| "Duel"
	| "Window"
	| "Prize"
	| "Reveal"
	| "Congrats"
	| "D17"
	| "D19"
	| "D23"

export type AccentName =
	"strawberry"
	| "mint"
	| "quests"
	| "lilac"
	| "sky"
	| "shop"
	| "frosting"
	| "gold"
	| "red"
	| "plum"
	| "pink"
	| "green"
	| "cyan"
	| "closeRed"
	| "disabled"
	| "cancel"
	| "yellow"
	| "ult"
	| "greenChip"
	| "blueBar"
	| "cancelX"
-- `light`: ink text at every size; `dark`: white text at every size; neither: the outlined-text rule. UI FINAL R1: the
-- gradient's stops, `top`, `mid` at `midAt` (a share of the height; 3-stop gradients only) and `shade` (the end stop);
-- `face` is the main colour (the mid stop, else the top).
export type Accent = {
	face: Color3,
	shade: Color3,
	light: boolean,
	dark: boolean?,
	top: Color3,
	mid: Color3?,
	midAt: number?,
}

-- "exact": the bands are painted in their colours over a white background; "tint": they darken BackgroundColor3.
export type FoamMode = "exact" | "tint"

-- Foam band heights in base px.
export type Bands = { top: number, bevel: number, drop: number }

-- The colours of a foam surface. Missing bands fall back to the face (top), the face (bevel) and InkUI (drop).
export type FoamColors = { face: Color3, top: Color3?, bevel: Color3?, drop: Color3?, faceEnd: Color3? }
-- UI FINAL R1: FoamColors with a 3-stop face: `face` -> `mid` (at `midAt`, a share of the surface's height) ->
-- `faceEnd` (the design's linear-gradient(180deg, A, B p%, C)). Every foam parameter keeps the FoamColors type (table
-- properties are invariant, so the two types do not mix): surfaceColors and accentColors return a StickerColors typed
-- as a FoamColors, and foamSequence reads the middle stop when it is there.
export type StickerColors = {
	face: Color3,
	top: Color3?,
	mid: Color3?,
	midAt: number?,
	bevel: Color3?,
	drop: Color3?,
	faceEnd: Color3?,
}

export type FoamStyle = {
	radius: number?, -- base px; default Theme.Radius.button
	stroke: number?, -- the ink outline in base px; 0 = none; default Theme.Stroke.ink
	strokeColor: Color3?,
	inner: boolean?, -- UI FINAL R1: the outline drawn inside the box (BorderStrokePosition Inner); default outside
	top: number?, -- band heights in base px (default 0)
	bevel: number?,
	drop: number?,
	mode: FoamMode?, -- default "exact"
	colors: FoamColors?, -- default Frosting / Bevel / InkUI with no highlight
	fixedHeight: number?, -- draw the bands once for this height (base px) instead of following the object's size
}

export type Foam = {
	gradient: UIGradient,
	corner: UICorner,
	stroke: UIStroke?,
	paint: (self: Foam, colors: FoamColors, mode: FoamMode?) -> (),
	setBands: (self: Foam, top: number, bevel: number, drop: number) -> (),
	setStroke: (self: Foam, color: Color3, thickness: number?) -> (),
}

-- UI FINAL R2: a design surface given as numbers (Config.UI.Sticker.surfaces' shape; a button's own, P12).
export type Surface = { highlightPx: number, highlightAlpha: number, bevelPx: number?, bevelAlpha: number? }

-- UI FINAL R2 (P3): radial's look while its picture has no id: the outer colour at outerAlpha, the glow tinted the
-- inner colour at innerAlpha centred at `centre` (a share of the box, default the middle) and, for a 3-stop radial,
-- a glow tinted `mid` at midAlpha under it, the inner one then sized to the mid stop (midAt of the radius).
export type RadialFallback = {
	inner: Color3,
	outer: Color3,
	mid: Color3?,
	midAt: number?,
	innerAlpha: number?,
	midAlpha: number?,
	outerAlpha: number?,
	centre: Vector2?,
}

-- UI FINAL R2 (T1, T2): a soft box-shadow `0 offsetY blurPx rgba(color, alpha)`; the picture's own render: imagePx
-- square with marginPx of shadow around the box (its 9-slice centre inside the margins).
export type SoftShadowSpec = {
	offsetY: number,
	blurPx: number,
	alpha: number,
	color: Color3?,
	marginPx: number?,
	imagePx: number?,
}

export type HeaderTabOptions = {
	accent: AccentName?, -- default "strawberry" (a tab; a window's band takes its kind's colours)
	textKind: TextKind?, -- default "H2" (a display kind >= 18 px: outlined white on the accent; a band: its role)
	name: string?, -- default "HeaderTab" (a window's band: "HeaderBand")
	align: ("center" | "left")?, -- default "center" (a tab)
	inset: number?, -- base px from the panel's left edge when align = "left" (a tab)
	extra: GuiObject?, -- UI FINAL R3: a window's band holds it at its right end (H:185, H:260)
}

-- UI FINAL R3: what a window's fitted chrome takes (fitWindow, fittedChrome; Layout.WindowChrome holds a kind's
-- design numbers), base px: the window's top padding (its band and the body's padding), how far its sticker or close X
-- reach above it, the band's height and the chrome scale.
export type FittedChrome = { top: number, above: number, band: number, k: number }

-- Constants

local ATTR_TEXT_KIND = "SD_TextKind"
local OUTLINE_NAME = "SD_Outline"
local NO_OUTLINE_ATTR = "SD_NoOutline" -- noOutline: the label draws its own outline
local FOAM_GRADIENT_NAME = "SD_Foam"

-- UI FINAL R1: every kind draws in Fredoka One (the design's Fredoka 700, H:14, H:19; the one built-in Fredoka face).
local DISPLAY_FONT = Font.fromEnum(Enum.Font.FredokaOne)
local MEASURE_FONT = Enum.Font.FredokaOne
-- The outlined-text rule: every kind may carry the ink outline when it is this big (base px) or bigger (UI FINAL R1:
-- every Config.UI.TextSize kind is, plan §1.2); OUTLINE_PX is a copy's outline when its label has none.
local OUTLINE_MIN_BASE_PX = 16
local OUTLINE_PX = 2
-- A colour darker than this relative luminance is dark: a face that takes white text at every size, a text colour that
-- carries no outline (the ink, the pink-window text).
local DARK_FACE_LUMINANCE = 0.22
local RIM_NAME = "SD_Rim"
local RIM_PX = 2
local RIM_TRANSPARENCY = 0.6

-- Text measurement: the frame it measures in is this wide when nothing wraps.
local MEASURE_FRAME_PX = 100000
local MEASURE_FALLBACK_EM = 0.62 -- reading: per character, wider than Fredoka One really is
local MEASURE_FALLBACK_LINE = 1.3 -- reading: the line height in TextSize units when TextService cannot answer

-- Foam: a surface's base height is measured again when it changes by at least this much (base px).
local FOAM_REPAINT_PX = 0.5
-- Panels: the bottom padding is at least the bevel, the drop and this gap, so content never sits on the bands.
local PANEL_BAND_GAP = 3
-- Header tab: side padding, top and bottom padding over the face, the gap kept under it inside the panel, its ZIndex.
local TAB_PADDING_X = 24
local TAB_PADDING_Y = 4
local TAB_GAP = 6
local TAB_ZINDEX = 5
local TAB_RADIUS = 18 -- Candy UI: a chunky rounded plate (was a pill)
local TAB_TOP_PX = 4 -- its gloss band
local MEASURE_MARGIN_PX = 4 -- a measured title gets this much more width (TextService rounding)
-- Inset field (the well): the inner shadow band at its top (base px) and how much darker it is (H:236: inset 0 3px 0
-- rgba(0,0,0,.3)).
local INSET_SHADOW_PX = 3
local INSET_SHADOW_MIX = 0.3
-- UI FINAL R1: the 3-stop gradients' middle stop (H:126, H:245, H:247, H:498: 55%); a mid stop keeps this far from the
-- face band's own stops (a UIGradient needs strictly rising times).
local MID_AT = 0.55
local MID_EDGE = 0.001
-- stickerText's mirrored copies: from this many px of drop (the design's thinner 1-2 px shadows sit inside the outline,
-- plan §2); the text properties a copy follows.
local DROP_NAME = "SD_Drop"
local FACE_NAME = "SD_Face"
local MIRROR_ATTR = "SD_Mirrored"
local DROP_MIN_PX = 3
local MIRRORED: { string } = {
	"Text",
	"TextSize",
	"FontFace",
	"TextTransparency",
	"TextXAlignment",
	"TextYAlignment",
	"TextWrapped",
	"TextScaled",
	"TextTruncate",
	"RichText",
	"LineHeight",
}
-- radial / rays: the glow picture and the names of what they add.
local GLOW_IMAGE_KEY = "img.fx.glow"
local GLOW_IMAGE_NAME = "SD_Glow"
local RADIAL_NAME = "SD_Radial"
local RAYS_NAME = "SD_Rays"
-- UI FINAL R2: the mid stop's glow (radial's fallback), the soft shadow and its render's default margin and size (R0b).
local GLOW_MID_NAME = "SD_GlowMid"
local SOFT_SHADOW_NAME = "SD_SoftShadow"
local SHADOW_MARGIN_PX = 120
local SHADOW_IMAGE_PX = 512
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
-- UI FINAL R3: the window frame (Config.UI.Sticker.window), the names of its parts and their layers inside the band
-- (the band itself sits above the window's content), the scrim's and the dots' pictures.
local WINDOW = Config.UI.Sticker.window
local BAND_NAME = "HeaderBand"
local BAND_ZINDEX = 5
local BAND_FACE_Z = 1
local BAND_TITLE_Z = 2
local BAND_STICKER_Z = 3
local BAND_CLOSE_Z = 4
local DOTS_KEY = "img.fx.dots"
local SCRIM_KEY = "img.fx.radial.scrimWindow"
local SHADOW_WINDOW_KEY = "img.fx.shadowWindow"
-- The title never shrinks under the text floor (plan §1.2: minTextSize at the smallest UI scale, 13 / .85 -> 16).
local TITLE_MIN_BASE_PX = math.ceil(Config.UI.minTextSize / Config.UI.Scale.min)
local MIN_CHROME_SCALE = 0.05

-- Module table

local Theme = {}

Theme.OUTLINE_MIN_BASE_PX = OUTLINE_MIN_BASE_PX

-- UI FINAL R1: the sticker look's shapes (Config.UI.Sticker: borders, lips, radii, surfaces, text roles, bars,
-- toggles).
Theme.Sticker = Config.UI.Sticker

-- Colour tokens (Art/Palette, §7.2 and the foam spec). Side colours: A = Strawberry side, B = Mint side (§7.8; always
-- with text too; unchanged by the foam restyle). `ink` stays the world Ink (nameplates); UI text and outlines use
-- `inkUI`. `cream` stays the world Cream (sign and nameplate panels); foam panels use `panel`.
Theme.Colors = {
	panel = Palette.StickerCardTop, -- UI FINAL: windows and cards are the purple card (H:203), a tint face
	panelStroke = Palette.UIStroke,
	cream = Palette.Cream,
	ink = Palette.Ink,
	primary = Palette.StickerPinkMid,
	white = Palette.White,
	danger = Palette.Danger,
	sideA = Palette.Strawberry,
	sideALight = Palette.Bubblegum,
	sideB = Palette.Mint,
	sideBLight = Palette.MintCream,
	lemon = Palette.Lemon,
	sky = Palette.Sky,
	lavender = Palette.Lavender,
	mint = Palette.Mint,
	-- UI surface tokens (UI FINAL R1: the foam names kept, the design's values).
	frosting = Palette.Frosting, -- the cream sticker face (keycaps, chips; ink text): the design's #FFF6EA, H:171
	panelAlt = Palette.StickerCardTop, -- a card or row on a window
	biscuit = Palette.StickerWell, -- the well: recessed fields (H:236)
	track = Palette.StickerTrough, -- bar, slider and switch troughs (H:141)
	bevel = Palette.StickerCardBottom, -- the purple card's bottom stop (H:203)
	inkUI = Palette.StickerInk, -- every outline and lip; text on light faces (H:75)
	ink2 = Palette.StickerTextMuted, -- captions (outlined; H:142)
	text = Palette.White, -- text on the purple surfaces and accents (Theme.text's default; outlined)
	textFaint = Palette.StickerTextSoft, -- soft text, the text in a well (H:239)
	textOnWindow = Palette.StickerOnWindowText, -- text on the pink window body, no outline (H:196)
	-- The Candy inner rim (rim(), drawn mostly transparent) until R3 / R4 remove its calls: the card's bottom colour,
	-- so it all but vanishes on the purple surfaces (the design has no rim; a reading).
	rim = Palette.StickerCardBottom,
	-- The bevel band under a light sticker: the world plates (nameplates, the squeeze label) keep theirs (plan §4), the
	-- one Candy token Theme still reads.
	stickerBevel = Palette.StickerBevel,
	gold = Palette.StickerCoinText, -- gold text and bursts: the design's coin yellow (H:79, H:369)
	backdrop = Palette.StickerScrimPurple, -- the modal dimmer and wash (H:178)
	scrollThumb = Palette.StickerScrollThumb, -- UI FINAL R3: the scroll bar's thumb (H:22; scrollbar, ScrollHint)
	-- World UI on light plates (collection plates, nameplates, the squeeze label) keeps the foam inks.
	worldInk = Palette.InkUI,
	worldInk2 = Palette.Ink2,
	disabledFace = Palette.StickerDisabledTop, -- H:246
	disabledStroke = Palette.StickerInk,
	disabledShade = Palette.StickerDisabledEnd,
	disabledText = Palette.White, -- H:246: white with the ink outline
}

-- An accent from its gradient stops (UI FINAL R1): `face` is the mid stop when there is one, else the top.
local function stops(top: Color3, shade: Color3, mid: Color3?, light: boolean?): Accent
	return table.freeze({
		face = mid or top,
		shade = shade,
		light = light == true,
		top = top,
		mid = mid,
		midAt = if mid then MID_AT else nil,
	})
end
local PINK = stops(Palette.StickerPinkTop, Palette.StickerPinkEnd, Palette.StickerPinkMid) -- H:126
local MINT = stops(Palette.StickerMintTop, Palette.StickerMintEnd) -- H:210
local CYAN = stops(Palette.StickerCyanTop, Palette.StickerCyanEnd, Palette.StickerCyanMid) -- H:247
local GREEN = stops(Palette.StickerGreenTop, Palette.StickerGreenEnd, Palette.StickerGreenMid) -- H:245
local CLOSE_RED = stops(Palette.StickerCloseTop, Palette.StickerCloseEnd) -- H:252

-- Accents (UI FINAL R1: the old names on their design hues, see the header). `light` faces carry ink text; every other
-- accent white outlined text (the design's stroked white labels). Reserved and never an accent: CoinGold, CoinRing,
-- CoinHighlight, Danger (§7.2).
local ACCENTS: { [string]: Accent } = {
	strawberry = PINK,
	pink = PINK,
	mint = MINT,
	quests = MINT,
	lilac = stops(Palette.StickerPurpleBarTop, Palette.StickerPurpleBarEnd), -- lib:39
	sky = CYAN,
	cyan = CYAN,
	shop = GREEN, -- the buying colour: 84° of hue from CoinGold (the hue rule)
	green = GREEN,
	gold = stops(Palette.StickerGoldTop, Palette.StickerGoldEnd, Palette.StickerGoldMid), -- H:498
	red = CLOSE_RED,
	closeRed = CLOSE_RED,
	plum = stops(Palette.StickerPillTop, Palette.StickerPillBottom), -- H:75: the purple pill
	frosting = stops(Palette.Frosting, Palette.Frosting, nil, true), -- H:171
	disabled = stops(Palette.StickerDisabledTop, Palette.StickerDisabledEnd), -- H:246
	cancel = stops(Palette.StickerCancelTop, Palette.StickerCancelEnd), -- H:462
	yellow = stops(Palette.StickerYellowTop, Palette.StickerYellowEnd), -- H:120
	-- UI FINAL R2 (P12): the CLAIM! chip's green, Button size "chip" (H:402).
	greenChip = stops(Palette.StickerGreenTop, Palette.StickerGreen2End),
	-- H:234: the Ultimate chip's gold (its dark text is the ink here); the touch Ultimate and ULT READY.
	ult = stops(Palette.StickerUltTop, Palette.StickerGoldEnd, nil, true),
	-- UI FINAL R4: the quest bar's blue fill (lib:37, H:956: the HUD quest tracker, an unfinished quest).
	blueBar = stops(Palette.StickerBlueBarTop, Palette.StickerBlueBarEnd),
	-- UI FINAL R4: the DUEL search bar's cancel X (H:145: #FF8A8A -> #F0344A).
	cancelX = stops(Palette.StickerCancelRedTop, Palette.StickerCloseEnd),
}
Theme.Accents = table.freeze(ACCENTS)

-- The bevel tint of a design surface (box-shadow inset 0 -Bpx 0 rgba(c, b)); black when it has none.
local SURFACE_TINTS: { [string]: Color3 } = {
	duel = Palette.StickerDuelBevel, -- H:126
	found = Palette.StickerFoundBevel, -- H:149
}

-- Shape tokens (base px, under the ScreenGui UIScale). Foam radii (spec: package px ÷ 1.25): chip 10, button 16,
-- tile 20, panel 22, pill fully round; small / medium / large are the same three steps under their Part 8 names.
Theme.Radius = {
	small = 10,
	medium = 16,
	large = 22,
	chip = 10,
	button = 16,
	tile = 20,
	panel = 22,
	pill = 999,
}
Theme.Padding = { small = 6, medium = 12, large = 20 }
-- `ink` = the foam outline of every interactive surface and panel; `bar` = bars and chips; `text` = the outlined-text
-- rule.
-- Candy UI: `ink` 2.5 -> 3 (heavy outlines); `rim` = the inner rim.
Theme.Stroke = { thin = 1.5, medium = 2, thick = 3, ink = 3, bar = 2, text = OUTLINE_PX, rim = RIM_PX }
Theme.Transparency = { panel = 0, subtle = 0.15 }

-- Foam bands per surface (base px): a top highlight (white at `highlight` over the face), a bottom bevel shade band and
-- a bottom InkUI drop band (spec "Shapes": bevel 5 / tiles 6 / primary CTA 7; drop 3 / tiles and panels 4 / CTA 5).
Theme.Foam = table.freeze({
	button = table.freeze({ top = 2, bevel = 5, drop = 3 }),
	tile = table.freeze({ top = 2, bevel = 6, drop = 4 }),
	cta = table.freeze({ top = 2, bevel = 7, drop = 5 }),
	panel = table.freeze({ top = 0, bevel = 5, drop = 4 }),
	chip = table.freeze({ top = 0, bevel = 3, drop = 2 }), -- a raised chip or tab
	highlight = 0.45,
})

-- Private

-- UI FINAL R1: the foam handle of every Theme.panel (setSurface repaints one), dropped when the panel is destroyed.
local panelFoams: { [GuiObject]: Foam } = setmetatable({}, { __mode = "k" }) :: any

-- UI FINAL R3: every Theme.window's kind, its body padding and its chrome (the band's parts once headerTab made them,
-- the last fit), dropped with the window.
type WindowParts = {
	kind: string,
	padding: number,
	band: Frame?,
	clip: Frame?,
	face: Frame?,
	dots: ImageLabel?,
	title: TextLabel?,
	titleScale: UIScale?,
	extra: GuiObject?,
	sticker: Frame?,
	stick: Frame?,
	stickerShadow: ImageLabel?,
	bobHolder: Frame?,
	bob: UiIdle.Handle?,
	ring: Frame?,
	chrome: FittedChrome?,
	stickRest: (() -> ())?,
	hasClose: boolean?,
	fittedWidth: number?,
	extraWidth: number?,
}
local windows: { [GuiObject]: WindowParts } = setmetatable({}, { __mode = "k" }) :: any

local function preferredName(): string?
	local ok, value = pcall(function(): any
		return GuiService.PreferredTextSize
	end)
	if ok and typeof(value) == "EnumItem" then
		return (value :: EnumItem).Name
	end
	return nil
end

-- UI FINAL R1: `stroke` (a text's SD_Outline) keeps its text's TextTransparency: a UIStroke does not fade with its
-- text, so a faded label left a hollow ink outline (SqueezeController's foam fix). Connected once, when it is made.
local function followFade(object: Instance, stroke: UIStroke)
	if not (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) then
		return
	end
	local text = object :: any
	stroke.Transparency = text.TextTransparency
	object:GetPropertyChangedSignal("TextTransparency"):Connect(function()
		stroke.Transparency = text.TextTransparency
	end)
end

local function setOutline(object: Instance, on: boolean, thickness: number?)
	if object:GetAttribute(NO_OUTLINE_ATTR) == true then
		return
	end
	local existing = object:FindFirstChild(OUTLINE_NAME)
	if on then
		if existing and existing:IsA("UIStroke") then
			existing.Enabled = true
			existing.Thickness = thickness or OUTLINE_PX
			existing.Color = Theme.Colors.inkUI
		else
			local made: UIStroke = Create("UIStroke", {
				Name = OUTLINE_NAME,
				Color = Theme.Colors.inkUI,
				Thickness = thickness or OUTLINE_PX,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
				LineJoinMode = Enum.LineJoinMode.Round,
				Parent = object,
			})
			followFade(object, made)
		end
	elseif existing and existing:IsA("UIStroke") then
		existing.Enabled = false
	end
end

-- WCAG 2 relative luminance of a colour (which faces take white text, which text colours carry the outline).
local function luminance(color: Color3): number
	local function channel(c: number): number
		return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end

-- A light colour (text in it carries the ink outline).
local function isLight(color: Color3): boolean
	return luminance(color) >= DARK_FACE_LUMINANCE
end

-- Per channel `color` / `face`, clamped to 0..1 (a "tint" band: the gradient multiplies the face by it).
local function ratio(color: Color3, face: Color3): Color3
	local function channel(c: number, f: number): number
		return if f > 0 then math.clamp(c / f, 0, 1) else 0
	end
	return Color3.new(channel(color.R, face.R), channel(color.G, face.G), channel(color.B, face.B))
end

-- The height of `object` in base px: its AbsoluteSize over every UIScale from it up to its ScreenGui, else (not drawn
-- yet) its offset height. Nil when neither is known.
local function baseHeight(object: GuiObject): number?
	local absolute = object.AbsoluteSize.Y
	if absolute > 0 then
		local scale = 1
		local node: Instance? = object
		while node ~= nil do
			local uiScale = node:FindFirstChildOfClass("UIScale")
			if uiScale then
				scale *= uiScale.Scale
			end
			if node:IsA("LayerCollector") then
				break
			end
			node = node.Parent
		end
		if scale > 0 then
			return absolute / scale
		end
	end
	local size = object.Size.Y
	if size.Scale == 0 and size.Offset > 0 then
		return size.Offset
	end
	return nil
end

-- stickerText's text drop: SD_Drop (ink, `drop` px lower) and SD_Face (the label's colour, above it) mirror `label`,
-- whose own glyphs are hidden. The label stays the source of truth: its text properties, colour, ZIndex and outline
-- are copied on every change (connected once per label; a copy never writes the label, so nothing loops). UI FINAL
-- R2 (T5): with `soft` the drop is the design's soft text-shadow: its colour (a Palette name, default the ink) at its
-- alpha of the label's opacity, with no outline.
local function mirrorDrop(label: TextLabel, drop: number, soft: { px: number, alpha: number, color: string? }?)
	local function copy(name: string, offsetY: number): TextLabel
		local existing = label:FindFirstChild(name)
		if existing and existing:IsA("TextLabel") then
			existing.Position = UDim2.fromOffset(0, offsetY)
			return existing
		end
		local made: TextLabel = Create("TextLabel", {
			Name = name,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, offsetY),
			Size = UDim2.fromScale(1, 1),
			Active = false,
			Parent = label,
		})
		return made
	end
	local dropLabel = copy(DROP_NAME, drop)
	local faceLabel = copy(FACE_NAME, 0)
	label.MaxVisibleGraphemes = 0
	local function sync()
		for _, property in MIRRORED do
			(dropLabel :: any)[property] = (label :: any)[property];
			(faceLabel :: any)[property] = (label :: any)[property]
		end
		local softColor = if soft and soft.color then (Palette :: any)[soft.color] else nil
		dropLabel.TextColor3 = if typeof(softColor) == "Color3" then softColor else Theme.Colors.inkUI
		if soft then
			dropLabel.TextTransparency = 1 - (1 - label.TextTransparency) * soft.alpha
		end
		faceLabel.TextColor3 = label.TextColor3
		dropLabel.ZIndex = label.ZIndex
		faceLabel.ZIndex = label.ZIndex + 1
		local outline = label:FindFirstChild(OUTLINE_NAME)
		local stroke = if outline and outline:IsA("UIStroke") then outline else nil
		local on = stroke ~= nil and stroke.Enabled
		local thickness = if stroke then stroke.Thickness else OUTLINE_PX
		setOutline(dropLabel, on and soft == nil, thickness)
		setOutline(faceLabel, on, thickness)
	end
	if label:GetAttribute(MIRROR_ATTR) ~= true then
		label:SetAttribute(MIRROR_ATTR, true)
		for _, property in MIRRORED do
			label:GetPropertyChangedSignal(property):Connect(sync)
		end
		label:GetPropertyChangedSignal("TextColor3"):Connect(sync)
		label:GetPropertyChangedSignal("ZIndex"):Connect(sync)
		local outline = label:FindFirstChild(OUTLINE_NAME)
		if outline and outline:IsA("UIStroke") then
			outline:GetPropertyChangedSignal("Enabled"):Connect(sync)
			outline:GetPropertyChangedSignal("Thickness"):Connect(sync)
		end
	end
	sync()
end

-- Public: fonts and sizes

-- UI FINAL R1: every Config.UI.TextSize kind is a display kind (all in Fredoka One).
function Theme.isDisplay(kind: string): boolean
	return type(Config.UI.TextSize[kind]) == "number"
end

-- The font of every kind: Fredoka One (UI FINAL R1; the weight is kept in the signature, Fredoka One has one face).
function Theme.font(_kind: string, _weight: Enum.FontWeight?): Font
	return DISPLAY_FONT
end

-- Base text size of a kind with the player's PreferredTextSize applied (the UIScale applies on top).
function Theme.textSize(kind: string): number
	return Layout.textSize(kind, preferredName())
end

-- Sets FontFace, TextSize, TextColor3 (Colors.text, white, unless given) and wrapping on a text object, and remembers
-- the kind. UI FINAL R1: text in a light colour carries the ink outline (outlinePx(kind)), text in a dark colour none.
function Theme.text(object: GuiObject, kind: TextKind, weight: Enum.FontWeight?, color: Color3?): GuiObject
	local text = object :: any
	local tone = color or Theme.Colors.text
	text.FontFace = Theme.font(kind, weight)
	text.TextSize = Theme.textSize(kind)
	text.TextColor3 = tone
	text.TextWrapped = true
	object:SetAttribute(ATTR_TEXT_KIND, kind)
	setOutline(object, isLight(tone), Theme.outlinePx(kind))
	return object
end

-- The size (base px, before the ScreenGui UIScale) `text` takes in `kind` at the player's text size; wrapped inside
-- `wrapWidth` base px when given. Never errors: an estimate when TextService cannot answer.
function Theme.textBounds(text: string, kind: TextKind, _weight: Enum.FontWeight?, wrapWidth: number?): Vector2
	local size = Theme.textSize(kind)
	local frame = if wrapWidth and wrapWidth > 0 then wrapWidth else MEASURE_FRAME_PX
	local ok, result = pcall(function(): Vector2
		return TextService:GetTextSize(text, size, MEASURE_FONT, Vector2.new(frame, MEASURE_FRAME_PX))
	end)
	if ok and typeof(result) == "Vector2" then
		return result
	end
	local chars = utf8.len(text) or #text
	local width = chars * size * MEASURE_FALLBACK_EM
	local lines = math.max(1, math.ceil(width / frame))
	return Vector2.new(math.min(width, frame), lines * size * MEASURE_FALLBACK_LINE)
end

-- The one-line width (base px) of `text` in `kind` at the player's text size.
function Theme.textWidth(text: string, kind: TextKind, weight: Enum.FontWeight?): number
	return Theme.textBounds(text, kind, weight).X
end

-- The height (base px) of one line of `kind` at the player's text size.
function Theme.lineHeight(kind: TextKind, weight: Enum.FontWeight?): number
	return Theme.textBounds("Hg", kind, weight).Y
end

-- Re-applies the text size of every Theme.text object under `root` (PreferredTextSize changed).
function Theme.refreshText(root: Instance)
	for _, descendant in root:GetDescendants() do
		local kind = descendant:GetAttribute(ATTR_TEXT_KIND)
		if type(kind) == "string" and descendant:IsA("GuiObject") then
			local text = descendant :: any
			if not text.TextScaled then
				text.TextSize = Theme.textSize(kind)
			end
		end
	end
end

-- Public: the outlined-text rule

-- Whether text of `kind` may be white with the ink outline on a saturated fill (a display kind >= 16 base px: UI FINAL
-- R1, every Config.UI.TextSize kind).
function Theme.outlineAllowed(kind: string): boolean
	local base = Config.UI.TextSize[kind]
	return Theme.isDisplay(kind) and type(base) == "number" and base >= OUTLINE_MIN_BASE_PX
end

-- The outline thickness (base px) of outlined text of `kind`: half the design's -webkit-text-stroke at that size (UI
-- FINAL R1, the Config.UI.Sticker text roles): 6.5 from 82 base px (H:539), 5 from 52 (H:490, H:545), 4.5 from 50
-- (H:184), 4 from 40 (H:95, H:130, H:429), 3.5 from 34 (H:151, H:227, H:527), 3 from 26 (H:79, H:245, H:246, H:269),
-- 2.5 from 22 (H:358, H:370); below that the game's own steps: 2 from 18, else 1.5 (plan §1.3: an outline the design
-- leaves off; Studio found 2 px closed up the gaps of the small kinds, DuelController's and HudController's foam
-- fixes). A role with a design stroke (Config.UI.Sticker.text, e.g. small H:89) sets its own through stickerText.
function Theme.outlinePx(kind: string): number
	local base = Config.UI.TextSize[kind]
	local px = if type(base) == "number" then base else 0
	return if px >= 82
		then 6.5
		elseif px >= 52 then 5
		elseif px >= 50 then 4.5
		elseif px >= 40 then 4
		elseif px >= 34 then 3.5
		elseif px >= 26 then 3
		elseif px >= 22 then 2.5
		elseif px >= 18 then 2
		else 1.5
end

-- The relative luminance (WCAG 2) of a colour.
function Theme.luminance(color: Color3): number
	return luminance(color)
end

-- Whether `face` is too dark for ink text (it then takes white text at every size).
function Theme.isDarkFace(face: Color3): boolean
	return luminance(face) < DARK_FACE_LUMINANCE
end

-- Text on a saturated fill (an accent face): white with the ink outline (outlinePx) when its kind allows it (every
-- kind, UI FINAL R1), else the ink with no outline; on a dark `face` (isDarkFace) white at every size. `kind` defaults
-- to the object's Theme.text kind. Returns whether it is outlined.
function Theme.textOnColor(object: GuiObject, kind: TextKind?, face: Color3?): boolean
	local stored = object:GetAttribute(ATTR_TEXT_KIND)
	local k: string = kind or (if type(stored) == "string" then stored else "Body")
	local outlined = Theme.outlineAllowed(k)
	local dark = face ~= nil and Theme.isDarkFace(face)
	local text = object :: any
	text.TextColor3 = if outlined or dark then Theme.Colors.white else Theme.Colors.inkUI
	setOutline(object, outlined, Theme.outlinePx(k))
	return outlined
end

-- Text on an accent face by name: the ink on a light accent (textOnLight), else textOnColor with its face.
function Theme.textOnAccent(object: GuiObject, accentName: string?, kind: TextKind?): boolean
	local accent = Theme.accent(accentName)
	if accent.light then
		Theme.textOnLight(object)
		return false
	end
	return Theme.textOnColor(object, kind, accent.face)
end

-- Text on a light surface (the cream sticker, the disabled lilac): `color` (default the ink); a light `color` keeps the
-- ink outline (UI FINAL R1: light text always carries it), a dark one has none.
function Theme.textOnLight(object: GuiObject, color: Color3?)
	local tone = color or Theme.Colors.inkUI
	local stored = object:GetAttribute(ATTR_TEXT_KIND)
	local text = object :: any
	text.TextColor3 = tone
	setOutline(object, isLight(tone), Theme.outlinePx(if type(stored) == "string" then stored else "Body"))
end

-- UI FINAL R1: text on the pink window body (H:196): StickerOnWindowText, no outline (6.3:1 and 4.9:1 on its stops).
function Theme.textOnWindow(object: GuiObject)
	Theme.textOnLight(object, Theme.Colors.textOnWindow)
end

-- UI FINAL R1: takes the ink outline off `object` for good, for a label that draws an outline of its own (and fades
-- it itself): its SD_Outline goes and Theme never adds one again.
function Theme.noOutline(object: Instance)
	object:SetAttribute(NO_OUTLINE_ATTR, true)
	local existing = object:FindFirstChild(OUTLINE_NAME)
	if existing then
		existing:Destroy()
	end
end

-- Public: small builders (each returns the new instance, unparented unless `parent` is given)

-- A TextLabel with Theme.text applied: transparent background, AutomaticSize.Y, wrapped.
function Theme.label(props: { [string]: any }, kind: TextKind, weight: Enum.FontWeight?, color: Color3?): TextLabel
	local label: TextLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
	})
	Theme.text(label, kind, weight, color)
	for key, value in props do
		if key ~= "Parent" then
			(label :: any)[key] = value
		end
	end
	if props.Parent then
		label.Parent = props.Parent
	end
	return label
end

function Theme.corner(radiusPx: number, parent: Instance?): UICorner
	return Create("UICorner", { CornerRadius = UDim.new(0, radiusPx), Parent = parent })
end

function Theme.stroke(color: Color3, thickness: number, parent: Instance?, transparency: number?): UIStroke
	return Create("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Theme.padding(px: number, parent: Instance?): UIPadding
	local u = UDim.new(0, px)
	return Create(
		"UIPadding",
		{ PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u, Parent = parent }
	)
end

function Theme.list(
	direction: Enum.FillDirection,
	paddingPx: number,
	parent: Instance?,
	horizontal: Enum.HorizontalAlignment?,
	vertical: Enum.VerticalAlignment?
): UIListLayout
	return Create("UIListLayout", {
		FillDirection = direction,
		Padding = UDim.new(0, paddingPx),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = horizontal or Enum.HorizontalAlignment.Center,
		VerticalAlignment = vertical or Enum.VerticalAlignment.Center,
		Parent = parent,
	})
end

-- Public: foam surfaces

-- An accent pair by name; an unknown name gives Frosting.
function Theme.accent(name: string?): Accent
	return Theme.Accents[name or "frosting"] or Theme.Accents.frosting
end

-- UI FINAL R1: the colours of a design surface on `accent` (Config.UI.Sticker.surfaces[surface], default "primary"):
-- its face gradient (top -> mid -> shade), with `highlight` the inset highlight band (the top stop towards white by
-- highlightAlpha), the bevel band (the shade towards black, or the surface's tint, by bevelAlpha) and the ink drop.
-- UI FINAL R2 (P12): `surface` may be a Surface table (a button's own numbers; no tint).
function Theme.surfaceColors(accent: Accent, surface: (string | Surface)?, highlight: boolean?): FoamColors
	local name = if type(surface) == "string" then surface else "primary"
	local spec: Surface = if type(surface) == "table"
		then surface
		else Theme.Sticker.surfaces[name] or Theme.Sticker.surfaces.primary
	local bevelAlpha = spec.bevelAlpha
	local colors: StickerColors = {
		face = accent.top,
		mid = accent.mid,
		midAt = accent.midAt,
		faceEnd = accent.shade,
		top = if highlight then accent.top:Lerp(WHITE, spec.highlightAlpha) else accent.top,
		bevel = if bevelAlpha
			then accent.shade:Lerp((if type(surface) == "table" then nil else SURFACE_TINTS[name]) or BLACK, bevelAlpha)
			else accent.shade,
		drop = Theme.Colors.inkUI,
	}
	return colors :: any
end

-- The colours of a foam surface on an accent (surfaceColors with the accent's name; `surface` default "primary").
function Theme.accentColors(name: string?, highlight: boolean?, surface: string?): FoamColors
	return Theme.surfaceColors(Theme.accent(name), surface, highlight)
end

-- The gradient colours of a foam surface `height` base px tall (Layout.foamStops): with `mode` "exact" (default) the
-- band colours themselves, with "tint" each band as a ratio of the face (the gradient then multiplies whatever
-- BackgroundColor3 the surface has).
function Theme.foamSequence(height: number, bands: Bands, colors: FoamColors, mode: FoamMode?): ColorSequence
	local face = colors.face
	local exact = mode ~= "tint"
	local function tone(color: Color3): Color3
		return if exact then color else ratio(color, face)
	end
	-- `ending`: the face band's last stop (Candy UI: it takes faceEnd, so the face fades from `face` to `faceEnd`).
	local function bandColor(name: Layout.FoamBand, ending: boolean): Color3
		local color = if name == "top"
			then colors.top or face
			elseif name == "bevel" then colors.bevel or face
			elseif name == "drop" then colors.drop or Theme.Colors.inkUI
			elseif ending and colors.faceEnd then colors.faceEnd
			else face
		return tone(color)
	end
	local keypoints: { ColorSequenceKeypoint } = {}
	local previous: string? = nil
	local three = colors :: StickerColors
	local mid, midAt = three.mid, three.midAt
	for _, stop in Layout.foamStops(height, bands.top, bands.bevel, bands.drop) do
		local ending = stop.band == "face" and previous == "face"
		-- UI FINAL R1: a 3-stop face puts `mid` at `midAt` (a share of the height) inside the face band.
		local last = keypoints[#keypoints]
		if ending and mid and midAt and last and midAt > last.Time + MID_EDGE and midAt < stop.time - MID_EDGE then
			table.insert(keypoints, ColorSequenceKeypoint.new(midAt, tone(mid)))
		end
		table.insert(keypoints, ColorSequenceKeypoint.new(stop.time, bandColor(stop.band, ending)))
		previous = stop.band
	end
	return ColorSequence.new(keypoints)
end

-- Gives `object` the foam look (UICorner, ink UIStroke, banded UIGradient; see the header). The bands follow the
-- object's size (the connection ends with the object), or, with style.fixedHeight, are drawn once for that height and
-- then scale with the object (a coin that grows and shrinks keeps its proportions). Returns a handle to repaint it
-- (paint's `mode` switches between "exact" and "tint").
function Theme.foam(object: GuiObject, style: FoamStyle?): Foam
	local s: FoamStyle = style or {}
	local mode: FoamMode = s.mode or "exact"
	local bands: Bands = { top = s.top or 0, bevel = s.bevel or 0, drop = s.drop or 0 }
	local colors: FoamColors = s.colors or { face = Palette.Frosting, bevel = Palette.Bevel, drop = Palette.InkUI }
	local corner = Theme.corner(s.radius or Theme.Radius.button, object)
	local strokePx = s.stroke or Theme.Stroke.ink
	local stroke: UIStroke? = if strokePx > 0
		then Theme.stroke(s.strokeColor or Theme.Colors.inkUI, strokePx, object)
		else nil
	if stroke and s.inner then
		pcall(function()
			(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
		end)
	end
	local gradient: UIGradient = Create("UIGradient", { Name = FOAM_GRADIENT_NAME, Rotation = 90, Parent = object })
	if mode == "exact" then
		object.BackgroundColor3 = Theme.Colors.white
	end
	local paintedHeight: number? = s.fixedHeight

	local function render(height: number?)
		gradient.Color = Theme.foamSequence(height or 0, bands, colors, mode)
		paintedHeight = height
	end

	if s.fixedHeight == nil then
		object:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			local height = baseHeight(object)
			local last = paintedHeight
			if height == nil or (last ~= nil and math.abs(height - last) < FOAM_REPAINT_PX) then
				return
			end
			render(height)
		end)
		render(baseHeight(object))
	else
		render(s.fixedHeight)
	end

	local self = {} :: Foam
	self.gradient = gradient
	self.corner = corner
	self.stroke = stroke

	function self.paint(_: Foam, newColors: FoamColors, newMode: FoamMode?)
		colors = newColors
		if newMode and newMode ~= mode then
			mode = newMode
			if mode == "exact" then
				object.BackgroundColor3 = Theme.Colors.white
			end
		end
		render(paintedHeight)
	end

	function self.setBands(_: Foam, top: number, bevel: number, drop: number)
		bands = { top = top, bevel = bevel, drop = drop }
		render(paintedHeight)
	end

	function self.setStroke(_: Foam, color: Color3, thickness: number?)
		local current = stroke
		if current then
			current.Color = color
			if thickness then
				current.Thickness = thickness
			end
		end
	end

	return self
end

-- The panel (cards, pills, dialogs; UI FINAL R1: the design's purple card, H:203): the card top as a "tint" face
-- (BackgroundColor3; a caller may recolour it, the gradient follows), its bottom stop (Colors.bevel), a 4 px ink border
-- drawn inside the box and the 5 px ink lip under the face (Config.UI.Sticker; no highlight: a ratio cannot lighten),
-- `padding` on every side but the bottom, which is at least the bands plus PANEL_BAND_GAP. Its first UIStroke is the
-- outline (callers recolour it for a highlight). setSurface repaints it in exact colours.
function Theme.panel(props: { [string]: any }, radiusPx: number?, paddingPx: number?): Frame
	local frame: Frame = Create("Frame", {
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = Theme.Transparency.panel,
		BorderSizePixel = 0,
	})
	local sticker = Theme.Sticker
	local bands = Layout.stickerBands(sticker.border.normal, 0, 0, sticker.lip.card)
	local foam = Theme.foam(frame, {
		radius = radiusPx or sticker.radius.card,
		stroke = sticker.border.normal,
		inner = true,
		mode = "tint",
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = { face = Theme.Colors.panel, faceEnd = Theme.Colors.bevel, drop = Theme.Colors.inkUI },
	})
	panelFoams[frame] = foam
	frame.Destroying:Once(function()
		panelFoams[frame] = nil
	end)
	local padding = paddingPx or Theme.Padding.medium
	local pad = Theme.padding(padding, frame)
	pad.PaddingBottom = UDim.new(0, math.max(padding, bands.bevel + bands.drop + PANEL_BAND_GAP))
	for key, value in props do
		if key ~= "Parent" then
			(frame :: any)[key] = value
		end
	end
	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

-- A recessed field inside a panel (stats, odds, settings rows; UI FINAL R1: the design's well #5B36D9 with its 4 px ink
-- border drawn inside the box and the inner shadow along its top under it, H:236), `padding` on every side (default
-- Theme.Padding.medium). A caller may recolour it; the shadow follows.
function Theme.inset(props: { [string]: any }, radiusPx: number?, paddingPx: number?): Frame
	local frame: Frame = Create("Frame", {
		BackgroundColor3 = Theme.Colors.biscuit,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
	})
	local border = Theme.Sticker.border.normal
	Theme.foam(frame, {
		radius = radiusPx or Theme.Sticker.radius.button,
		stroke = border,
		inner = true,
		mode = "tint",
		top = Layout.stickerBands(border, INSET_SHADOW_PX, 0, 0).top,
		colors = {
			face = Theme.Colors.biscuit,
			top = Theme.Colors.biscuit:Lerp(BLACK, INSET_SHADOW_MIX),
		},
	})
	Theme.padding(paddingPx or Theme.Padding.medium, frame)
	for key, value in props do
		if key ~= "Parent" then
			(frame :: any)[key] = value
		end
	end
	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

-- Public: UI FINAL R1 helpers

-- Repaints a Theme.panel in exact colours (the design's state faces: a later round's day cards, box plates and rarity
-- cards); the panel then no longer follows its BackgroundColor3. False (nothing done) for a frame that is not one.
function Theme.setSurface(frame: GuiObject, colors: FoamColors): boolean
	local foam = panelFoams[frame]
	if foam == nil then
		return false
	end
	foam:paint(colors, "exact")
	return true
end

-- Styles `label` as the Config.UI.Sticker text role `roleName` (see the header): its kind and colour (Theme.text), the
-- ink outline at half the role's stroke and, from a DROP_MIN_PX drop, the mirrored ink drop. An unknown role leaves the
-- label as it is. Returns the label.
function Theme.stickerText(label: TextLabel, roleName: string): TextLabel
	local role = Theme.Sticker.text[roleName]
	if role == nil then
		return label
	end
	local named = if role.color then (Palette :: any)[role.color] else nil
	Theme.text(label, role.kind :: TextKind, nil, if typeof(named) == "Color3" then named else nil)
	setOutline(label, true, role.stroke / 2)
	local drop = role.drop or 0
	local soft = (role :: any).soft
	if soft then
		mirrorDrop(label, soft.px, soft)
	elseif drop >= DROP_MIN_PX then
		mirrorDrop(label, drop)
	end
	return label
end

-- UI FINAL R2 (P3, plan §2): the design's radial-gradient on `frame` as the exact picture `key` (pack 2, the CSS radial
-- rendered with its alpha: an ImageLabel SD_Radial stretched over the frame, whose own background goes clear); while
-- that picture has no id, `fallback` (RadialFallback): the outer colour at outerAlpha, the img.fx.glow picture tinted
-- the inner colour at innerAlpha centred at `centre`, and for a 3-stop radial a glow tinted `mid` (midAlpha, default
-- innerAlpha) under it, the inner glow then sized to the mid stop. With neither picture, only the outer colour (a
-- reading). Calling it again reuses what it made. Returns the picture or the inner glow (nil: the outer colour alone).
function Theme.radial(frame: GuiObject, key: string, fallback: RadialFallback): ImageLabel?
	local function image(name: string): ImageLabel
		local existing = frame:FindFirstChild(name)
		if existing and existing:IsA("ImageLabel") then
			return existing
		end
		return Create("ImageLabel", {
			Name = name,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Stretch,
			Active = false,
			ZIndex = frame.ZIndex,
			Parent = frame,
		})
	end
	local content = AssetTable.image(key)
	if content then
		frame.BackgroundTransparency = 1
		local picture = image(RADIAL_NAME)
		picture.Image = content
		return picture
	end
	frame.BackgroundColor3 = fallback.outer
	frame.BackgroundTransparency = 1 - (fallback.outerAlpha or 1)
	local glow = AssetTable.image(GLOW_IMAGE_KEY)
	if glow == nil then
		return nil
	end
	local centre = fallback.centre or Vector2.new(0.5, 0.5)
	local mid, midAt = fallback.mid, fallback.midAt
	local innerAlpha = fallback.innerAlpha or 1
	if mid and midAt then
		local ring = image(GLOW_MID_NAME)
		ring.Image = glow
		ring.ImageColor3 = mid
		ring.ImageTransparency = 1 - (fallback.midAlpha or innerAlpha)
		ring.Position = UDim2.fromScale(centre.X, centre.Y)
	end
	local inner = image(GLOW_IMAGE_NAME)
	inner.Image = glow
	inner.ImageColor3 = fallback.inner
	inner.ImageTransparency = 1 - innerAlpha
	inner.Position = UDim2.fromScale(centre.X, centre.Y)
	local share = if mid and midAt then math.clamp(midAt * 2, 0.05, 1) else 1
	inner.Size = UDim2.fromScale(share, share)
	return inner
end

-- A rays picture (`key`: img.fx.rays / raysDetail / raysReveal; H:219, H:266, H:474) centred in `parent` (UI FINAL R2,
-- P4: at `centreY` of its height, default the middle: H:219 60%, H:266 55%, H:296 38%, H:407 46%, H:474 46%, H:509 44%,
-- H:538 45%), `sizePx` square, at `alpha` (ImageTransparency 1 - alpha), at the parent's ZIndex, turning once every
-- `periodS` (Anim/UiIdle's spin, the design's sdSpin; at rest under ReducedMotion). Nil, nothing drawn, while the
-- picture has no id.
function Theme.rays(
	parent: GuiObject,
	key: string,
	sizePx: number,
	alpha: number,
	periodS: number,
	centreY: number?
): ImageLabel?
	local content = AssetTable.image(key)
	if content == nil then
		return nil
	end
	local rays: ImageLabel = Create("ImageLabel", {
		Name = RAYS_NAME,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, centreY or 0.5),
		Size = UDim2.fromOffset(sizePx, sizePx),
		Image = content,
		ImageTransparency = 1 - alpha,
		Active = false,
		ZIndex = parent.ZIndex,
		Parent = parent,
	})
	UiIdle.add(rays, "spin", { periodS = periodS })
	return rays
end

-- UI FINAL R2 (G4.13, H:28): the design's shine band in `strip` (a clear px-wide holder that Anim/UiIdle's "shine"
-- moves inside a ClipsDescendants parent): a white band, clear at its sides and white at `alpha` in its middle,
-- turned `slantDeg` (skewX(-20deg) leans the band's sides 20° and keeps it the strip's width across; a turn of a
-- band strip x cos(slantDeg) wide does the same, the gradient unturned, so no hard edge shows), tall enough to
-- cover the strip after the turn. Roblox stops clipping under a turned ancestor: the caller hides the strip then.
function Theme.shineBand(strip: Frame, alpha: number, slantDeg: number): Frame
	local turn = math.rad(slantDeg)
	local width = math.round(strip.Size.X.Offset * math.cos(turn)) -- a UDim offset is whole px
	local band: Frame = Create("Frame", {
		Name = "Band",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, width, 1 / math.cos(turn), math.round(width * math.tan(turn))),
		Rotation = slantDeg,
		Active = false,
		ZIndex = strip.ZIndex,
		Parent = strip,
	})
	Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 1 - alpha),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = band,
	})
	return band
end

-- UI FINAL R2 (T1, T2, plan §2): the design's soft box-shadow behind the target that fills `wrapper` (a transparent
-- frame that takes the layout and the motion; a child cannot draw under its parent with ZIndexBehavior Sibling): an
-- ImageLabel SD_SoftShadow at ZIndex 0 in the wrapper (the target above it), `spec.offsetY` lower. With the picture
-- `key` (pack 2: the CSS shadow rendered around a box, imagePx square, marginPx of shadow on every side, colour and
-- alpha baked) it is a 9-slice reaching marginPx past the wrapper; while it has no id, the img.fx.glow picture tinted
-- spec.color at spec.alpha, blurPx past the wrapper. Nil when neither picture has an id. Calling it again reuses it.
function Theme.softShadow(wrapper: GuiObject, key: string, spec: SoftShadowSpec): ImageLabel?
	local content = AssetTable.image(key)
	local glow = if content then nil else AssetTable.image(GLOW_IMAGE_KEY)
	if content == nil and glow == nil then
		return nil
	end
	local existing = wrapper:FindFirstChild(SOFT_SHADOW_NAME)
	local shadow: ImageLabel = if existing and existing:IsA("ImageLabel")
		then existing
		else Create("ImageLabel", {
			Name = SOFT_SHADOW_NAME,
			BackgroundTransparency = 1,
			Active = false,
			ZIndex = 0,
			Parent = wrapper,
		})
	if content then
		local margin = spec.marginPx or SHADOW_MARGIN_PX
		local size = spec.imagePx or SHADOW_IMAGE_PX
		shadow.Image = content
		shadow.ScaleType = Enum.ScaleType.Slice
		shadow.SliceCenter = Rect.new(margin, margin, size - margin, size - margin)
		shadow.ImageColor3 = WHITE
		shadow.ImageTransparency = 0
		shadow.Position = UDim2.fromOffset(-margin, spec.offsetY - margin)
		shadow.Size = UDim2.new(1, 2 * margin, 1, 2 * margin)
	else
		local blur = spec.blurPx
		shadow.Image = glow :: string
		shadow.ScaleType = Enum.ScaleType.Stretch
		shadow.ImageColor3 = spec.color or Theme.Colors.inkUI
		shadow.ImageTransparency = 1 - spec.alpha
		shadow.Position = UDim2.fromOffset(-blur, spec.offsetY - blur)
		shadow.Size = UDim2.new(1, 2 * blur, 1, 2 * blur)
	end
	return shadow
end

-- Public: UI FINAL R3, the window frame (see the header) ---------------------------------------------------------

-- A window kind's Config.UI.Sticker.window entry (an unknown kind: the Squishies window's).
local function windowSpec(kind: string): { [string]: any }
	local kinds = WINDOW.kinds :: any
	return kinds[kind] or kinds.squishies
end

-- A Palette colour by name, else `fallback`.
local function paletteColor(name: string?, fallback: Color3): Color3
	local color = if name then (Palette :: any)[name] else nil
	return if typeof(color) == "Color3" then color else fallback
end

-- The width of `object` in base px: its offset width when it is sized in px alone (a window: current even before it is
-- drawn again), else its AbsoluteSize over every UIScale from it up to its ScreenGui, else its offset width; 0 when
-- neither is known (baseHeight's sibling).
local function baseWidth(object: GuiObject): number
	local size = object.Size.X
	local autoX = object.AutomaticSize == Enum.AutomaticSize.X or object.AutomaticSize == Enum.AutomaticSize.XY
	if size.Scale == 0 and size.Offset > 0 and not autoX then
		return size.Offset
	end
	local absolute = object.AbsoluteSize.X
	if absolute > 0 then
		local scale = 1
		local node: Instance? = object
		while node ~= nil do
			local uiScale = node:FindFirstChildOfClass("UIScale")
			if uiScale then
				scale *= uiScale.Scale
			end
			if node:IsA("LayerCollector") then
				break
			end
			node = node.Parent
		end
		if scale > 0 then
			return absolute / scale
		end
	end
	return if size.Scale == 0 and size.Offset > 0 then size.Offset else 0
end

-- The Squishies window's inner ring (H:182) over the window's box, inside its border and above its lip.
local function placeRing(window: GuiObject, parts: WindowParts)
	local ring = parts.ring
	local pad = window:FindFirstChildOfClass("UIPadding")
	if ring == nil or pad == nil then
		return
	end
	local border = Theme.Sticker.border.heavy
	local l, r = pad.PaddingLeft.Offset, pad.PaddingRight.Offset
	local t, b = pad.PaddingTop.Offset, pad.PaddingBottom.Offset
	ring.Position = UDim2.fromOffset(border - l, border - t)
	ring.Size = UDim2.new(1, l + r - 2 * border, 1, t + b - 2 * border - Theme.Sticker.lip.window)
end

-- The design's window (H:182; see the header): the pink body with its 5 px ink border drawn inside, radius 32 and the
-- 10 px ink lip under the face (frame = face + lip, plan P1), Active (a click on it never reaches the scrim);
-- `padding` (default Theme.Padding.medium) on every side of the face, so the bottom one is the padding plus the lip.
-- `kind` is a Config.UI.Sticker.window.kinds name: headerTab draws its band, fitWindow lays it out. The Squishies
-- window also gets its inner ring (H:182).
function Theme.window(props: { [string]: any }, kind: string, paddingPx: number?): Frame
	local frame: Frame = Create("Frame", {
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Active = true,
	})
	local sticker = Theme.Sticker
	local border, lip = sticker.border.heavy, sticker.lip.window
	local bands = Layout.stickerBands(border, 0, 0, lip)
	Theme.foam(frame, {
		radius = sticker.radius.window,
		stroke = border,
		inner = true,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = { face = Palette.StickerWindowTop, faceEnd = Palette.StickerWindowBottom, drop = Theme.Colors.inkUI },
	})
	local padding = paddingPx or Theme.Padding.medium
	local pad = Theme.padding(padding, frame)
	pad.PaddingBottom = UDim.new(0, padding + lip)
	local parts: WindowParts = { kind = kind, padding = padding }
	windows[frame] = parts
	frame.Destroying:Once(function()
		windows[frame] = nil
	end)
	if windowSpec(kind).innerRing then
		local ring: Frame = Create("Frame", {
			Name = "SD_InnerRing",
			BackgroundTransparency = 1,
			Active = false,
			ZIndex = 0,
			Parent = frame,
		})
		Theme.corner(sticker.radius.window - border, ring)
		local stroke = Theme.stroke(WHITE, WINDOW.innerRing.px, ring, 1 - WINDOW.innerRing.alpha)
		pcall(function()
			(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
		end)
		parts.ring = ring
		placeRing(frame, parts)
	end
	for key, value in props do
		if key ~= "Parent" then
			(frame :: any)[key] = value
		end
	end
	if props.Parent then
		frame.Parent = props.Parent
	end
	return frame
end

-- True for a Theme.window.
function Theme.isWindow(object: Instance): boolean
	return object:IsA("GuiObject") and windows[object :: GuiObject] ~= nil
end

-- The kind of a Theme.window, else nil.
function Theme.windowKind(object: GuiObject): string?
	local parts = windows[object]
	return if parts then parts.kind else nil
end

-- Lays out a window's chrome for the chrome scale `k` (Layout.windowFit's k; default the last one, else 1; see the
-- header): the band's height (the design's 98 / 92, or the title's line at the player's text size with titlePad over
-- and under it when that is taller, times k; never shorter than the extra and the bottom border), its paddings (with
-- an X, the right one keeps the band's end clear of the X's 54 px reach inside the window), the dots' tile, the title
-- (its UIScale: k, less when its room needs it, never under TITLE_MIN_BASE_PX at the player's text size), the extra at
-- the right end, the sticker's size and
-- spot, the inner ring and the window's top padding (the border, the band, then the body's padding). Returns the
-- chrome; a frame that is not a window gets zeros.
function Theme.fitWindow(window: GuiObject, k: number?): FittedChrome
	local parts = windows[window]
	if parts == nil then
		return { top = 0, above = 0, band = 0, k = 1 }
	end
	local last = parts.chrome
	local scale = math.clamp(k or (if last then last.k else 1), MIN_CHROME_SCALE, 1)
	local spec = windowSpec(parts.kind)
	local small = spec.small == true
	local b, s = WINDOW.band, WINDOW.sticker
	local border = Theme.Sticker.border.heavy
	local pad = window:FindFirstChildOfClass("UIPadding")
	local band, title = parts.band, parts.title
	local bandHeight = 0
	if band and title then
		local role = Theme.Sticker.text[if small then "settingsTitle" else "windowTitle"]
		local design = if small then b.smallHeight else b.height
		bandHeight = math.ceil(math.max(design, Theme.lineHeight(role.kind :: TextKind) + 2 * b.titlePad) * scale)
		local extra = parts.extra
		local extraHeight = if extra then baseHeight(extra) else nil
		if extraHeight then
			-- a small chrome: the extra (centred above the bottom border) stays inside the band
			bandHeight = math.max(bandHeight, math.ceil(extraHeight) + b.border)
		end
	end
	local top = if band then border + bandHeight + parts.padding else parts.padding
	if pad then
		pad.PaddingTop = UDim.new(0, top)
	end
	local padLeft = if pad then pad.PaddingLeft.Offset else 0
	local padRight = if pad then pad.PaddingRight.Offset else 0
	if band and title then
		band.Position = UDim2.fromOffset(-padLeft, -top)
		band.Size = UDim2.new(1, padLeft + padRight, 0, border + bandHeight)
		local clip, face, dots = parts.clip, parts.face, parts.dots
		if clip then
			clip.Position = UDim2.fromOffset(border, border)
			clip.Size = UDim2.new(1, -2 * border, 0, bandHeight)
		end
		if face then
			face.Size = UDim2.new(1, 0, 0, bandHeight + b.cornerRadius)
		end
		if dots then
			local tile = math.max(4, math.round(b.dotsTile * scale))
			dots.Size = UDim2.new(1, 0, 0, bandHeight + b.cornerRadius)
			dots.TileSize = UDim2.fromOffset(tile, tile)
		end
		local hasSticker = spec.sticker ~= nil
		local leftPad = if hasSticker then (if small then b.smallPadLeft else b.padLeft) else b.plainPad
		local rightPad = if hasSticker then (if small then b.smallPadRight else b.padRight) else b.plainPad
		local left, right = math.round(leftPad * scale), math.round(rightPad * scale)
		if parts.hasClose then -- a small chrome: the band's end stays a gap clear of the X (H:252)
			right = math.max(right, WINDOW.close.face - WINDOW.close.right - border + math.round(b.gap * scale))
		end
		local centre = math.round(border + (bandHeight - b.border) / 2)
		title.Position = UDim2.fromOffset(border + left, centre)
		local windowWidth = baseWidth(window)
		parts.fittedWidth = windowWidth
		local room = windowWidth - 2 * border - left - right
		local extra = parts.extra
		if extra then
			extra.Position = UDim2.new(1, -(border + right), 0, centre)
			local extraWidth = baseWidth(extra)
			parts.extraWidth = extraWidth
			room -= extraWidth + math.round(b.gap * scale)
		end
		local role = Theme.Sticker.text[if small then "settingsTitle" else "windowTitle"]
		local width = Theme.textWidth(title.Text, role.kind :: TextKind)
		title.Size =
			UDim2.fromOffset(math.ceil(width) + MEASURE_MARGIN_PX, math.ceil(Theme.lineHeight(role.kind :: TextKind)))
		local share = if width <= 0 then scale elseif room <= 0 then 0 else room / width
		local floor = TITLE_MIN_BASE_PX / math.max(1, Theme.textSize(role.kind)) -- at the player's text size too
		local titleScale = parts.titleScale
		if titleScale then
			titleScale.Scale = math.max(math.min(scale, share), floor)
		end
		local sticker, shadow = parts.sticker, parts.stickerShadow
		if sticker then
			local px = math.round((if small then s.smallPx else s.px) * scale)
			local x = (if small then s.smallX else s.x) * scale
			local y = (if small then s.smallY else s.y) * scale
			sticker.Size = UDim2.fromOffset(px, px)
			sticker.Position = UDim2.fromOffset(math.round(x + px / 2), math.round(y + px / 2))
			if shadow then
				shadow.Position = UDim2.fromOffset(0, math.round(s.shadowPx * scale))
			end
		end
	end
	placeRing(window, parts)
	local above = WINDOW.close.top
	if spec.sticker ~= nil then
		above = math.max(above, -(if small then s.smallY else s.y) * scale)
	end
	local chrome: FittedChrome = { top = top, above = above, band = bandHeight, k = scale }
	parts.chrome = chrome
	return chrome
end

-- The last chrome fitWindow gave a window (fitted at k = 1 when it has none yet); zeros for a frame that is not one.
function Theme.fittedChrome(window: GuiObject): FittedChrome
	local parts = windows[window]
	if parts and parts.chrome then
		return parts.chrome
	end
	return Theme.fitWindow(window, nil)
end

-- The design's band on a window (headerTab on a Theme.window; see the header and fitWindow).
local function buildBand(window: GuiObject, parts: WindowParts, text: string, o: HeaderTabOptions): (Frame, TextLabel)
	local spec = windowSpec(parts.kind)
	local small = spec.small == true
	local b, s = WINDOW.band, WINDOW.sticker
	local band: Frame = Create("Frame", {
		Name = o.name or BAND_NAME,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = BAND_ZINDEX,
	})
	-- The band's face and dots in a clip holder (its top corners rounded, its bottom square: the rounded bottom of the
	-- taller face falls outside the clip).
	local clip: Frame = Create("Frame", {
		Name = "SD_BandClip",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = false,
		ZIndex = BAND_FACE_Z,
		Parent = band,
	})
	local face: Frame = Create("Frame", {
		Name = "SD_BandFace",
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 1,
		Parent = clip,
	})
	local top = paletteColor(spec.top, Theme.Colors.panel)
	local bottom = paletteColor(spec.bottom, Theme.Colors.bevel)
	Theme.foam(face, {
		radius = b.cornerRadius,
		stroke = 0,
		top = b.highlightPx,
		bevel = b.bevelPx,
		drop = b.border + b.cornerRadius,
		colors = {
			face = top,
			faceEnd = bottom,
			top = top:Lerp(WHITE, spec.highlightAlpha),
			bevel = bottom:Lerp(BLACK, b.bevelAlpha),
			drop = Theme.Colors.inkUI,
		},
	})
	local dotsImage = AssetTable.image(DOTS_KEY)
	local dots: ImageLabel? = nil
	if dotsImage then
		local made: ImageLabel = Create("ImageLabel", {
			Name = "SD_Dots",
			BackgroundTransparency = 1,
			Image = dotsImage,
			ImageColor3 = WHITE,
			ImageTransparency = 1 - spec.dotsAlpha,
			ScaleType = Enum.ScaleType.Tile,
			Active = false,
			ZIndex = 2,
			Parent = clip,
		})
		Theme.corner(b.cornerRadius, made)
		dots = made
		-- H:183: the band's bottom border paints over its dots background (they are background), so the ink strip
		-- sits over the dots at the clip's bottom.
		Create("Frame", {
			Name = "SD_BandEdge",
			BackgroundColor3 = Theme.Colors.inkUI,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, b.border),
			Active = false,
			ZIndex = 3,
			Parent = clip,
		})
	end
	-- The title: left-aligned, in capitals, its size from its role and its UIScale (fitWindow), its box from its
	-- measure (fitWindow), not AutomaticSize: under a UIScale above 1 an automatic label's box grows by it twice.
	local title: TextLabel = Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Left,
		Active = false,
		ZIndex = BAND_TITLE_Z,
		Parent = band,
	})
	Theme.stickerText(title, if small then "settingsTitle" else "windowTitle")
	title.TextWrapped = false
	title.Text = string.upper(text)
	local titleScale: UIScale = Create("UIScale", { Name = "SD_TitleScale", Parent = title })
	local extra = o.extra
	if extra then
		extra.AnchorPoint = Vector2.new(1, 0.5)
		extra.ZIndex = BAND_TITLE_Z
		extra.Parent = band
	end
	-- The sticker (H:251): the spot fitWindow sets > sdStick (playSticker) > sdBob from the start (UiIdle) > the
	-- picture over its drop shadow. No picture id: no sticker (the band keeps its padding).
	local key = spec.sticker
	local image = if type(key) == "string" then AssetTable.image(key) else nil
	if image then
		local holder: Frame = Create("Frame", {
			Name = "SD_Sticker",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Active = false,
			ZIndex = BAND_STICKER_Z,
			Parent = band,
		})
		local function inner(name: string, parent: Instance): Frame
			return Create("Frame", {
				Name = name,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				Active = false,
				ZIndex = BAND_STICKER_Z,
				Parent = parent,
			})
		end
		local stick = inner("SD_Stick", holder)
		local bob = inner("SD_StickerBob", stick)
		local shadow: ImageLabel = Create("ImageLabel", {
			Name = "SD_StickerShadow",
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = Palette.StickerStickerShadow,
			ImageTransparency = 1 - s.shadowAlpha,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			Active = false,
			ZIndex = 1,
			Parent = bob,
		})
		Create("ImageLabel", {
			Name = "SD_StickerImage",
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			Active = false,
			ZIndex = 2,
			Parent = bob,
		})
		parts.bob = UiIdle.add(bob, "bob", { periodS = s.bobS })
		parts.sticker, parts.stick, parts.stickerShadow, parts.bobHolder = holder, stick, shadow, bob
	end
	parts.band, parts.clip, parts.face, parts.dots = band, clip, face, dots
	parts.title, parts.titleScale, parts.extra = title, titleScale, extra
	band.Parent = window
	Theme.fitWindow(window, nil)
	-- Capitals whatever a caller writes later (InspectPanel's name, the Grip panel's title); the band fits it again.
	title:GetPropertyChangedSignal("Text"):Connect(function()
		local upper = string.upper(title.Text)
		if title.Text ~= upper then
			title.Text = upper
			return
		end
		Theme.fitWindow(window, nil)
	end)
	title:GetPropertyChangedSignal("TextSize"):Connect(function()
		Theme.fitWindow(window, nil)
	end)
	-- The title's room follows the window's width and the extra's (a caller sizes the window after fitting it; the
	-- Collected count or a key hint changes the extra): fit again when either changes by a px or more.
	window:GetPropertyChangedSignal("Size"):Connect(function()
		if math.abs(baseWidth(window) - (parts.fittedWidth or 0)) >= 1 then
			Theme.fitWindow(window, nil)
		end
	end)
	if extra then
		extra:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if math.abs(baseWidth(extra) - (parts.extraWidth or 0)) >= 1 then
				Theme.fitWindow(window, nil)
			end
		end)
	end
	return band, title
end

-- A title plate straddling `panel`'s top edge (spec "header-tab title"; Candy UI: a jelly plate): the accent face with
-- a gloss band, the PlumInk outline and an inner rim, the title in a display kind (white with the outline, the rule).
-- Its size follows its measured title (textWidth / lineHeight, fitted again when the text or its size changes)
-- instead of AutomaticSize. It is positioned by hand, so `panel` must not hold a UIListLayout directly (put the list in
-- a child frame) nor clip its descendants. The panel's top padding grows to keep TAB_GAP under the tab's lower half
-- (measured at the current text size). Returns the tab (named options.name or "HeaderTab") and its label. UI FINAL
-- R3: on a Theme.window it is the design's band instead (buildBand; named options.name or "HeaderBand"; its accent,
-- textKind, align and inset come from the window's kind); the tab lost the Candy shine stripes and header glow.
function Theme.headerTab(panel: GuiObject, text: string, options: HeaderTabOptions?): (Frame, TextLabel)
	local o: HeaderTabOptions = options or {}
	local parts = windows[panel]
	if parts then
		return buildBand(panel, parts, text, o)
	end
	local kind: TextKind = o.textKind or "H2"
	local accentName = o.accent or "strawberry"
	local bands = Theme.Foam.button
	local padTop = TAB_PADDING_Y + TAB_TOP_PX
	local padBottom = TAB_PADDING_Y + bands.bevel + bands.drop
	local height = math.ceil(Theme.lineHeight(kind)) + padTop + padBottom
	local pad = panel:FindFirstChildOfClass("UIPadding") or Theme.padding(0, panel)
	local needTop = math.ceil(height / 2) + TAB_GAP
	if pad.PaddingTop.Offset < needTop then
		pad.PaddingTop = UDim.new(0, needTop)
	end
	local left = o.align == "left"
	local tab: Frame = Create("Frame", {
		Name = o.name or "HeaderTab",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(if left then 0 else 0.5, 0.5),
		Position = if left
			then UDim2.fromOffset((o.inset or Theme.Padding.large) - pad.PaddingLeft.Offset, -pad.PaddingTop.Offset)
			else UDim2.new(0.5, 0, 0, -pad.PaddingTop.Offset),
		Size = UDim2.fromOffset(2 * TAB_PADDING_X, height),
		ZIndex = TAB_ZINDEX,
	})
	Theme.foam(tab, {
		radius = TAB_RADIUS,
		top = TAB_TOP_PX,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.accentColors(accentName, true),
	})
	Theme.rim(tab, Theme.Colors.white, 0.55)
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, TAB_PADDING_X),
		PaddingRight = UDim.new(0, TAB_PADDING_X),
		PaddingTop = UDim.new(0, padTop),
		PaddingBottom = UDim.new(0, padBottom),
		Parent = tab,
	})
	local label = Theme.label({
		Name = "Title",
		Text = text,
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = TAB_ZINDEX + 1,
		Parent = tab,
	}, kind)
	Theme.textOnAccent(label, accentName, kind)
	local function fit()
		local width = math.ceil(Theme.textWidth(label.Text, kind)) + 2 * TAB_PADDING_X + MEASURE_MARGIN_PX
		local tall = math.ceil(Theme.lineHeight(kind)) + padTop + padBottom
		tab.Size = UDim2.fromOffset(width, tall)
	end
	fit()
	label:GetPropertyChangedSignal("Text"):Connect(fit)
	label:GetPropertyChangedSignal("TextSize"):Connect(fit)
	tab.Parent = panel
	return tab, label
end

-- Puts a window's close X (a Button root) into its band at the design's spot (H:252: right -22, top -22 of the
-- window), over the band's other parts, and fits the band again (its right end keeps clear of the X). Nothing for a
-- window without a band.
function Theme.attachClose(window: GuiObject, close: GuiObject)
	local parts = windows[window]
	local band = if parts then parts.band else nil
	if parts == nil or band == nil then
		return
	end
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, WINDOW.close.right, 0, -WINDOW.close.top)
	close.ZIndex = BAND_CLOSE_Z
	close.Parent = band
	parts.hasClose = true
	Theme.fitWindow(window, nil)
end

-- The window sticker's sdStick (H:27, H:251): from 40 / 60 px up-left, small, turned and clear to its spot over
-- ms after delayMs, each segment eased by its curve (Config.UI.Sticker.window.sticker; the move at the chrome scale),
-- on the SD_Stick holder (its fade: Tweens.fadeGroup; its move, scale and turn: Tweens.poser), every time the window
-- opens (UIController). A replay first puts a running one back at rest. The design remounts the sticker on every open
-- (sc-if), so its sdBob starts again with it (G3.3). Nothing under ReducedMotion (PR9) or for a window without a
-- sticker.
function Theme.playSticker(window: GuiObject)
	local parts = windows[window]
	local stick = if parts then parts.stick else nil
	if parts == nil or stick == nil then
		return
	end
	local running = parts.stickRest
	if running then
		running()
	end
	if Tweens.reducedMotion() then
		return
	end
	local s = WINDOW.sticker
	local bobHolder, bob = parts.bobHolder, parts.bob
	if bobHolder and bob then
		bob:remove()
		parts.bob = UiIdle.add(bobHolder, "bob", { periodS = s.bobS })
	end
	local k = if parts.chrome then parts.chrome.k else 1
	local frames: { Tweens.Pose } = {}
	for _, frame in s.frames :: { any } do
		local copy: Tweens.Pose = table.clone(frame)
		local x, y = copy.x, copy.y
		if x then
			copy.x = x * k
		end
		if y then
			copy.y = y * k
		end
		table.insert(frames, copy)
	end
	local fade = Tweens.fadeGroup(stick)
	local poser = Tweens.poser(stick)
	local started = os.clock()
	local handle: Scheduler.Handle? = nil
	local function settle()
		fade:restore()
		poser:rest()
		if parts.stickRest ~= nil then
			parts.stickRest = nil
		end
	end
	local function show(u: number)
		local pose = Tweens.poseAt(frames, u, s.curve)
		fade:setAlpha(pose.alpha or 1)
		poser:set({ x = pose.x, y = pose.y, scale = pose.scale, rot = pose.rot })
	end
	parts.stickRest = function()
		local h = handle
		if h then
			h:disconnect()
		end
		settle()
	end
	show(0) -- CSS fill "both": the first frame through the delay
	handle = Scheduler.add(function(_dt: number, now: number): boolean
		if stick.Parent == nil then
			settle()
			return false
		end
		local u = math.clamp(((now - started) * 1000 - s.delayMs) / s.ms, 0, 1)
		show(u)
		if u >= 1 then
			settle()
			return false
		end
		return true
	end, "render")
end

-- The window scrim (H:178; see the header): a full-screen TextButton (clear, no text, not selectable, no button
-- colour) drawing the radial picture img.fx.radial.scrimWindow, else Theme.radial's fallback (the purple at the
-- outer alpha with the pink glow at the inner one). The caller fades it and closes the top window on Activated.
function Theme.scrim(props: { [string]: any }): TextButton
	local button: TextButton = Create("TextButton", {
		Name = "Dimmer",
		Text = "",
		AutoButtonColor = false,
		Active = true,
		Selectable = false,
		BorderSizePixel = 0,
		BackgroundColor3 = Palette.StickerScrimPurple,
		Size = UDim2.fromScale(1, 1),
	})
	Theme.radial(button, SCRIM_KEY, {
		inner = Palette.StickerScrimPink,
		outer = Palette.StickerScrimPurple,
		innerAlpha = WINDOW.scrim.innerAlpha,
		outerAlpha = WINDOW.scrim.outerAlpha,
	})
	for key, value in props do
		if key ~= "Parent" then
			(button :: any)[key] = value
		end
	end
	if props.Parent then
		button.Parent = props.Parent
	end
	return button
end

-- The window's soft shadow (H:182: 0 34px 70px rgba(15,8,25,.5)) in `wrapper` (a clear frame that follows the window,
-- UIController), through softShadow: the 9-slice img.fx.shadowWindow, else the glow tinted StickerShadowWindow.
function Theme.windowShadow(wrapper: GuiObject): ImageLabel?
	local spec = WINDOW.shadow
	return Theme.softShadow(wrapper, SHADOW_WINDOW_KEY, {
		offsetY = spec.offsetY,
		blurPx = spec.blurPx,
		alpha = spec.alpha,
		color = Palette.StickerShadowWindow,
	})
end

-- The design's scroll bar (H:22): 12 px, the thumb StickerScrollThumb (its 3 px border and radius 10: plan RL4).
Theme.SCROLLBAR_PX = WINDOW.scrollbarPx
function Theme.scrollbar(frame: ScrollingFrame): ScrollingFrame
	frame.ScrollBarThickness = WINDOW.scrollbarPx
	frame.ScrollBarImageColor3 = Theme.Colors.scrollThumb
	frame.ScrollBarImageTransparency = 0
	return frame
end

-- Public: Candy UI helpers

-- The colours of a dark window or card surface (Theme.panel's): PanelBody, its dark bevel and the PlumInk drop.
function Theme.panelColors(): FoamColors
	return { face = Theme.Colors.panel, bevel = Theme.Colors.bevel, drop = Theme.Colors.inkUI }
end

-- The colours of a light sticker (chips, keycaps, world labels): WarmWhite, its light bevel and the PlumInk drop.
function Theme.stickerColors(): FoamColors
	return { face = Theme.Colors.frosting, bevel = Theme.Colors.stickerBevel, drop = Theme.Colors.inkUI }
end

-- The inner rim (the "bright inset rim" of the overhaul): a second UIStroke drawn inside `object`'s box, `color`
-- (default Colors.rim) at `transparency` (default RIM_TRANSPARENCY), `thickness` base px (default Stroke.rim). Made after
-- the outline, so FindFirstChildOfClass("UIStroke") still finds the outline. An existing rim is reused. Returns it.
function Theme.rim(object: GuiObject, color: Color3?, transparency: number?, thickness: number?): UIStroke
	local existing = object:FindFirstChild(RIM_NAME)
	local rim: UIStroke = if existing and existing:IsA("UIStroke")
		then existing
		else Create("UIStroke", { Name = RIM_NAME, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	rim.Color = color or Theme.Colors.rim
	rim.Transparency = transparency or RIM_TRANSPARENCY
	rim.Thickness = thickness or RIM_PX
	pcall(function()
		(rim :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	rim.Parent = object
	return rim
end

return Theme
