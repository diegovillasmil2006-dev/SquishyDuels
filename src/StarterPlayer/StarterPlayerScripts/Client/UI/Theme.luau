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
--   above), each with the outline. radial(frame, inner, outer, mid?, midAt?) is the design's radial-gradient (the
--   img.fx.glow picture over the outer colour; a vertical gradient of the same stops while it has no id); rays(...) a
--   rays picture (nothing while its id is nil); setSurface(panel, colors) repaints a Theme.panel in exact colours.
-- * Still the Candy UI (UI overhaul 2026-10-11) until R3: headerTab()'s jelly plate (its shine and the header glow),
--   rim(), shine(), bubbles(); panelColors() and stickerColors() return the new tokens.

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

export type HeaderTabOptions = {
	accent: AccentName?, -- default "strawberry"
	textKind: TextKind?, -- default "H2" (a display kind >= 18 px: outlined white on the accent)
	name: string?, -- default "HeaderTab"
	align: ("center" | "left")?, -- default "center"
	inset: number?, -- base px from the panel's left edge when align = "left"
}

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
local SHINE_NAME = "SD_Shine"
local SHINE_STRENGTH = 0.2 -- the stripes' opacity
local GLOW_NAME = "SD_HeaderGlow"
local GLOW_TRANSPARENCY = 0.72 -- the header glow at its top edge (fades to clear)
local BUBBLES_NAME = "SD_Bubbles"
local BUBBLE_TRANSPARENCY = 0.93
-- The windows' jelly bubbles: centre (x, y) and size as shares of the window's height (kept inside a 16:10 window).
local BUBBLES: { { x: number, y: number, s: number } } = {
	{ x = 0.1, y = 0.8, s = 0.34 },
	{ x = 0.91, y = 0.22, s = 0.24 },
	{ x = 0.8, y = 0.86, s = 0.16 },
	{ x = 0.33, y = 0.4, s = 0.1 },
	{ x = 0.58, y = 0.7, s = 0.08 },
	{ x = 0.95, y = 0.62, s = 0.1 },
	{ x = 0.05, y = 0.36, s = 0.09 },
}

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
local SPIN_ATTR = "SD_SpinSeconds"
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

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
	-- H:234: the Ultimate chip's gold (its dark text is the ink here); the touch Ultimate and ULT READY.
	ult = stops(Palette.StickerUltTop, Palette.StickerGoldEnd, nil, true),
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
-- are copied on every change (connected once per label; a copy never writes the label, so nothing loops).
local function mirrorDrop(label: TextLabel, drop: number)
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
		dropLabel.TextColor3 = Theme.Colors.inkUI
		faceLabel.TextColor3 = label.TextColor3
		dropLabel.ZIndex = label.ZIndex
		faceLabel.ZIndex = label.ZIndex + 1
		local outline = label:FindFirstChild(OUTLINE_NAME)
		local stroke = if outline and outline:IsA("UIStroke") then outline else nil
		local on = stroke ~= nil and stroke.Enabled
		local thickness = if stroke then stroke.Thickness else OUTLINE_PX
		setOutline(dropLabel, on, thickness)
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
function Theme.surfaceColors(accent: Accent, surface: string?, highlight: boolean?): FoamColors
	local name = surface or "primary"
	local spec = Theme.Sticker.surfaces[name] or Theme.Sticker.surfaces.primary
	local bevelAlpha = spec.bevelAlpha
	local colors: StickerColors = {
		face = accent.top,
		mid = accent.mid,
		midAt = accent.midAt,
		faceEnd = accent.shade,
		top = if highlight then accent.top:Lerp(WHITE, spec.highlightAlpha) else accent.top,
		bevel = if bevelAlpha then accent.shade:Lerp(SURFACE_TINTS[name] or BLACK, bevelAlpha) else accent.shade,
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
	if drop >= DROP_MIN_PX then
		mirrorDrop(label, drop)
	end
	return label
end

-- The design's radial-gradient on `frame` (H:167, H:178, H:218): the img.fx.glow picture tinted `inner` over the
-- `outer` colour; while that picture has no id, a vertical gradient of the same stops (inner -> mid at midAt -> outer;
-- a reading). Returns the glow picture or the gradient.
function Theme.radial(frame: GuiObject, inner: Color3, outer: Color3, mid: Color3?, midAt: number?): Instance
	local content = AssetTable.image(GLOW_IMAGE_KEY)
	if content then
		frame.BackgroundColor3 = outer
		local existing = frame:FindFirstChild(GLOW_IMAGE_NAME)
		local glow: ImageLabel = if existing and existing:IsA("ImageLabel")
			then existing
			else Create("ImageLabel", {
				Name = GLOW_IMAGE_NAME,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Active = false,
				ZIndex = frame.ZIndex,
				Parent = frame,
			})
		glow.Image = content
		glow.ImageColor3 = inner
		return glow
	end
	frame.BackgroundColor3 = WHITE
	local points = { ColorSequenceKeypoint.new(0, inner) }
	if mid and midAt and midAt > MID_EDGE and midAt < 1 - MID_EDGE then
		table.insert(points, ColorSequenceKeypoint.new(midAt, mid))
	end
	table.insert(points, ColorSequenceKeypoint.new(1, outer))
	local existing = frame:FindFirstChild(RADIAL_NAME)
	local gradient: UIGradient = if existing and existing:IsA("UIGradient")
		then existing
		else Create("UIGradient", { Name = RADIAL_NAME, Rotation = 90, Parent = frame })
	gradient.Color = ColorSequence.new(points)
	return gradient
end

-- A rays picture (`key`: img.fx.rays / raysDetail / raysReveal; H:219, H:266, H:474) centred in `parent`, `sizePx`
-- square, at `alpha` (ImageTransparency 1 - alpha), at the parent's ZIndex; its turn period (`periodS`) is kept as the
-- SD_SpinSeconds attribute for R2's idle loops. Nil, nothing drawn, while the picture has no id.
function Theme.rays(parent: GuiObject, key: string, sizePx: number, alpha: number, periodS: number): ImageLabel?
	local content = AssetTable.image(key)
	if content == nil then
		return nil
	end
	local rays: ImageLabel = Create("ImageLabel", {
		Name = RAYS_NAME,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(sizePx, sizePx),
		Image = content,
		ImageTransparency = 1 - alpha,
		Active = false,
		ZIndex = parent.ZIndex,
		Parent = parent,
	})
	rays:SetAttribute(SPIN_ATTR, periodS)
	return rays
end

-- The accent glow across a window's header area (Candy UI): a frame over the panel's top padding (it follows the
-- padding as the screens re-fit their chrome), the accent fading from GLOW_TRANSPARENCY to clear downwards, with the
-- panel's corners, behind the content (ZIndex 0). One per panel.
local function headerGlow(panel: GuiObject, pad: UIPadding, color: Color3)
	if panel:FindFirstChild(GLOW_NAME) then
		return
	end
	local glow: Frame = Create("Frame", {
		Name = GLOW_NAME,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 0,
	})
	local corner = panel:FindFirstChildOfClass("UICorner")
	if corner then
		Create("UICorner", { CornerRadius = corner.CornerRadius, Parent = glow })
	end
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, GLOW_TRANSPARENCY),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = glow,
	})
	local function place()
		local top = pad.PaddingTop.Offset
		local sides = pad.PaddingLeft.Offset + pad.PaddingRight.Offset
		glow.Position = UDim2.fromOffset(-pad.PaddingLeft.Offset, -top)
		glow.Size = UDim2.new(1, sides, 0, top + TAB_GAP)
	end
	place()
	for _, property in { "PaddingTop", "PaddingLeft", "PaddingRight" } do
		pad:GetPropertyChangedSignal(property):Connect(place)
	end
	glow.Parent = panel
end

-- A title plate straddling `panel`'s top edge (spec "header-tab title"; Candy UI: a jelly plate): the accent face with
-- a gloss band, the PlumInk outline, an inner rim and two diagonal shine stripes, the title in a display kind (white
-- with the outline, the rule). Its size follows its measured title (textWidth / lineHeight, fitted again when the text
-- or its size changes) instead of AutomaticSize, so the shine overlay can never inflate it; a soft glow of the accent
-- fills the window's header area. It is positioned by hand, so `panel` must not hold a UIListLayout directly (put the
-- list in a child frame) nor clip its descendants. The panel's top padding grows to keep TAB_GAP under the tab's lower
-- half (measured at the current text size). Returns the tab (named options.name or "HeaderTab") and its label.
function Theme.headerTab(panel: GuiObject, text: string, options: HeaderTabOptions?): (Frame, TextLabel)
	local o: HeaderTabOptions = options or {}
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
	Theme.shine(tab, TAB_RADIUS)
	headerGlow(panel, pad, Theme.accent(accentName).face)
	tab.Parent = panel
	return tab, label
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

-- Two diagonal shine stripes over `object` (Candy UI gloss, like the references' header shine): a white frame over its
-- whole box (its UIPadding undone; corner `radiusPx`, so the stripes stay inside its rounded shape) faded by a UIGradient
-- into two soft bands, at the object's ZIndex (text drawn above it stays on top). Inputs pass through. Only for an
-- object whose size does not follow its children: an overlay inside an automatically sized parent inflates it (Studio
-- check). Returns the frame (an existing one is reused).
function Theme.shine(object: GuiObject, radiusPx: number?, strength: number?): Frame
	local existing = object:FindFirstChild(SHINE_NAME)
	if existing and existing:IsA("Frame") then
		return existing
	end
	local pad = object:FindFirstChildOfClass("UIPadding")
	local l = if pad then pad.PaddingLeft.Offset else 0
	local r = if pad then pad.PaddingRight.Offset else 0
	local t = if pad then pad.PaddingTop.Offset else 0
	local b = if pad then pad.PaddingBottom.Offset else 0
	local alpha = 1 - (strength or SHINE_STRENGTH)
	local soft = alpha + (1 - alpha) * 0.45
	local frame: Frame = Create("Frame", {
		Name = SHINE_NAME,
		BackgroundColor3 = Theme.Colors.white,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-l, -t),
		Size = UDim2.new(1, l + r, 1, t + b),
		Active = false,
		ZIndex = object.ZIndex,
	})
	Theme.corner(radiusPx or Theme.Radius.button, frame)
	Create("UIGradient", {
		Rotation = 25,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 1),
			NumberSequenceKeypoint.new(0.17, alpha),
			NumberSequenceKeypoint.new(0.29, alpha),
			NumberSequenceKeypoint.new(0.31, 1),
			NumberSequenceKeypoint.new(0.37, 1),
			NumberSequenceKeypoint.new(0.39, soft),
			NumberSequenceKeypoint.new(0.44, soft),
			NumberSequenceKeypoint.new(0.46, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = frame,
	})
	frame.Parent = object
	return frame
end

-- The windows' squishy texture (Candy UI): a few large, faint jelly bubbles behind a window's content (BUBBLES, shares
-- of its height), each with a soft highlight, in a holder over the window's box (its UIPadding undone, inset by the
-- outline) that clips them. ZIndex 0, inputs pass through. Never on a frame whose direct children a UIListLayout or
-- UIGridLayout places (the holder would become an item): nil then. Returns the holder (an existing one is reused).
function Theme.bubbles(window: GuiObject): Frame?
	local existing = window:FindFirstChild(BUBBLES_NAME)
	if existing and existing:IsA("Frame") then
		return existing
	end
	if window:FindFirstChildWhichIsA("UIGridStyleLayout") then
		return nil
	end
	local pad = window:FindFirstChildOfClass("UIPadding")
	local inset = Theme.Stroke.ink
	local holder: Frame = Create("Frame", {
		Name = BUBBLES_NAME,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Active = false,
		ZIndex = 0,
	})
	local function place()
		local l = if pad then pad.PaddingLeft.Offset else 0
		local r = if pad then pad.PaddingRight.Offset else 0
		local t = if pad then pad.PaddingTop.Offset else 0
		local b = if pad then pad.PaddingBottom.Offset else 0
		holder.Position = UDim2.fromOffset(inset - l, inset - t)
		holder.Size = UDim2.new(1, l + r - 2 * inset, 1, t + b - 2 * inset)
	end
	place()
	if pad then
		for _, property in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
			pad:GetPropertyChangedSignal(property):Connect(place)
		end
	end
	for index, spec in BUBBLES do
		local bubble: Frame = Create("Frame", {
			Name = "Bubble" .. index,
			BackgroundColor3 = Theme.Colors.rim,
			BackgroundTransparency = BUBBLE_TRANSPARENCY,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(spec.x, spec.y),
			Size = UDim2.fromScale(spec.s, spec.s),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			Active = false,
			ZIndex = 0,
			Parent = holder,
		})
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = bubble })
		Create("UIGradient", {
			Rotation = 55,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.45, 0.35),
				NumberSequenceKeypoint.new(1, 0.85),
			}),
			Parent = bubble,
		})
	end
	holder.Parent = window
	return holder
end

return Theme
