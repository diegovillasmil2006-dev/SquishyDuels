--!strict
-- Theme (client only). DESIGN §11.1, §11.2, §7.2; the foam UI restyle (spec docs/superpowers/specs/
-- 2026-10-09-foam-ui-restyle-design.md, API guide 2026-10-09-foam-ui-components.md): the UI tokens (colours from
-- Art/Palette, fonts, radii, paddings, foam bands), the text helpers and the foam surface helpers.
-- * Fonts: display (titles, numbers, buttons, chips) Font.fromEnum(Enum.Font.FredokaOne); body
--   Font.fromName(BODY_FAMILY, weight). BODY_FAMILY is the one font switch: "Nunito" (Bold / ExtraBold; every weight a caller asks for is lifted
--   one step, so body text is Bold and emphasis ExtraBold) or "BuilderSans" (the Part 8 look, weights one to one).
-- * Theme.text(object, kind) ALWAYS sets FontFace and TextSize (new TextButtons default to Legacy at size 8, V):
--   size = Config.UI.TextSize[kind] × the GuiService.PreferredTextSize multiplier (UI/Layout); the ScreenGui's UIScale
--   multiplies it on screen. The kind is stored as attribute SD_TextKind so refreshText(root) can re-apply every size
--   when PreferredTextSize changes (UIController listens). Text containers wrap and use AutomaticSize.Y (§11.2);
--   TextScaled is only for the countdown (with a UITextSizeConstraint). The default colour is InkUI.
-- * The outlined-text rule (spec): white text on a saturated fill carries a 2 px InkUI UIStroke (Contextual, round
--   joins) and is a display kind of at least OUTLINE_MIN_BASE_PX (18) base px; smaller text on colour is InkUI.
--   textOnColor(object) applies it, textOnLight(object) undoes it; body text on cream stays >= 4.5:1 (InkUI 14.2:1,
--   Ink2 5.6:1 on Frosting). The reserved gameplay colours (Danger, Coin*) stay where §7.2 allows them.
-- * Foam surfaces: foam(object, style) gives a GuiObject the foam look with no extra GuiObjects (so a UIListLayout
--   inside it is never disturbed): a UICorner, an InkUI UIStroke (outer) and a vertical UIGradient that paints a top
--   highlight band, the face, a bottom bevel shade band and a bottom ink "drop" band (Layout.foamStops), kept in base
--   px as the object resizes (its AbsoluteSize over the UIScales above it). Mode "exact" paints the given colours
--   over a white background (Button, chips, tabs); mode "tint" keeps the object's own BackgroundColor3 as the face and
--   darkens the bands by ratios (panel(): a caller may recolour a panel later and still gets a matching bevel).
--   Readings: the drop is drawn inside the surface's box (a UIGradient cannot paint outside it), so a foam surface
--   never reaches past its layout box apart from its outer stroke; a "tint" surface has no top highlight (a ratio can
--   only darken; white on Frosting does not show anyway).
-- * panel(props, radius?, padding?): the foam panel (Frosting face, InkUI 2.5 stroke, bevel 5, drop 4); its bottom
--   padding is at least the bands plus PANEL_BAND_GAP. headerTab(panel, text, options?): the title tab straddling a
--   panel's top edge. inset(props, radius?, padding?): a recessed Biscuit field.
-- * Measuring (Part 8): textBounds(text, kind, weight?, wrapWidth?) / textWidth(...) / lineHeight(kind, weight?)
--   measure a text in base px at the player's text size: TextService:GetTextSize with the legacy Enum.Font that draws
--   exactly like the face (Fredoka One, Builder Sans weights), else TextService:GetTextBoundsAsync with the Font object
--   (Nunito Bold / ExtraBold; cached per text, font, size and width). Reading: when TextService cannot answer (offline
--   tests, a context that cannot yield) a generous estimate is used (MEASURE_FALLBACK_EM per character,
--   MEASURE_FALLBACK_LINE lines), so a layout errs on the roomy side.
-- Candy UI (UI overhaul 2026-10-11; the bold, outlined look of the Steal an Egg references in Squishy Duels' own
-- colours, Art/Palette "Candy UI tokens"):
-- * Surfaces are dark: windows and cards PanelBody with the PlumInk 3 px outline (Stroke.ink) and a light inner rim
--   (rim(): a second UIStroke drawn inside the box, so no extra GuiObject can disturb a layout), raised rows
--   PanelRaised (Colors.panelAlt), recessed fields and bar tracks PanelRecess (Colors.biscuit). Light "stickers"
--   (chips, keycaps, world labels) keep a WarmWhite face with PlumInk text (stickerColors()).
-- * Text defaults to WarmWhite (Colors.text); captions Colors.ink2 (TextMuted), hints Colors.textFaint. Headline kinds
--   (AUTO_OUTLINE_KINDS) in the default colour carry the PlumInk outline (outlinePx(kind): 3 px from 28 base px, 2.5
--   from 22, 2 from 18, else 1.5). The outlined-text rule on an accent face now starts at the Chip kind (16 base px):
--   white with the outline; Body / Small on an accent are PlumInk, and on a dark face (isDarkFace: PlumInk would read
--   under 4.5:1, e.g. the plum neutral) white at every size (textOnColor's `face`).
-- * Accents (face / bevel shade): strawberry = Coral (brand, duel), lilac = Lavender (boxes, reveals), sky = Cyan
--   (info, daily), mint and quests = Mint (quests, success, progress), shop = Lime (shop, buying), gold (Coins,
--   celebration; PlumInk text), red (close, cancel, errors), plum (the neutral secondary face; white text), frosting
--   (the light sticker face; PlumInk text).
-- * headerTab() is a jelly title plate: the accent face with a gloss band, the outline, an inner rim and two diagonal
--   shine stripes (shine()), sized from its measured title (no AutomaticSize: an overlay inside an automatically sized
--   parent inflates it), with a soft glow of the accent across the window's header area. bubbles(window) is the
--   windows' squishy texture: a few large, faint jelly bubbles behind the content.
-- * FoamColors.faceEnd: the face band fades from `face` to `faceEnd` (a card's light-to-deep rarity face).

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Layout = require(script.Parent.Layout)
local Create = require(script.Parent.Create)

-- Types

export type TextKind = "Title" | "H2" | "Body" | "Small" | "Button" | "HudNumber" | "Countdown" | "Chip"

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
-- `light`: PlumInk text at every size; `dark`: white text at every size; neither: the outlined-text rule.
export type Accent = { face: Color3, shade: Color3, light: boolean, dark: boolean? }

-- "exact": the bands are painted in their colours over a white background; "tint": they darken BackgroundColor3.
export type FoamMode = "exact" | "tint"

-- Foam band heights in base px.
export type Bands = { top: number, bevel: number, drop: number }

-- The colours of a foam surface. Missing bands fall back to the face (top), the face (bevel) and InkUI (drop).
export type FoamColors = { face: Color3, top: Color3?, bevel: Color3?, drop: Color3?, faceEnd: Color3? }

export type FoamStyle = {
	radius: number?, -- base px; default Theme.Radius.button
	stroke: number?, -- the InkUI outline in base px; 0 = none; default Theme.Stroke.ink
	strokeColor: Color3?,
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
	paint: (self: Foam, colors: FoamColors) -> (),
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
local FOAM_GRADIENT_NAME = "SD_Foam"

local DISPLAY_FONT = Font.fromEnum(Enum.Font.FredokaOne)
-- The body font switch (spec 2026-10-09: "Nunito if Studio renders it with those weights; otherwise keep Builder
-- Sans"). Fallback: set this to "BuilderSans".
local BODY_FAMILY = "Nunito"

-- Kinds drawn in the display font; every other kind uses the body font.
local DISPLAY_KINDS: { [string]: boolean } = {
	Title = true,
	H2 = true,
	HudNumber = true,
	Countdown = true,
	Button = true,
	Chip = true,
}
-- Default body weight per kind before the BODY_FAMILY lift (Builder Sans: these weights as they are).
local DEFAULT_WEIGHT: { [string]: Enum.FontWeight } = {
	Body = Enum.FontWeight.Medium,
	Small = Enum.FontWeight.Medium,
}
-- The outlined-text rule: white text with the PlumInk outline only for display kinds this big (base px) or bigger
-- (Candy UI: 18 -> 16, the Chip kind, with a thinner outline below 18).
local OUTLINE_MIN_BASE_PX = 16
local OUTLINE_PX = 2
-- Candy UI: headline kinds that carry the outline in the default (light) colour on the dark surfaces.
local AUTO_OUTLINE_KINDS: { [string]: boolean } = {
	Title = true,
	H2 = true,
	HudNumber = true,
	Countdown = true,
	Button = true,
}
-- A face darker than this relative luminance takes white text at every size (PlumInk on it would read under 4.5:1).
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
local MEASURE_FALLBACK_EM = 0.62 -- reading: per character, wider than Fredoka One, Builder Sans and Nunito really are
local MEASURE_FALLBACK_LINE = 1.3 -- reading: the line height in TextSize units when TextService cannot answer
local MEASURE_CACHE_MAX = 2048 -- GetTextBoundsAsync answers kept (cleared when full)

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
-- Inset field: the inner shadow band at its top (base px) and how much darker it is than the field.
local INSET_SHADOW_PX = 3
local INSET_SHADOW_MIX = 0.35 -- Candy UI: towards black (the recess is darker than the window)

-- Module table

local Theme = {}

Theme.BODY_FAMILY = BODY_FAMILY
Theme.OUTLINE_MIN_BASE_PX = OUTLINE_MIN_BASE_PX

-- Colour tokens (Art/Palette, §7.2 and the foam spec). Side colours: A = Strawberry side, B = Mint side (§7.8; always
-- with text too; unchanged by the foam restyle). `ink` stays the world Ink (nameplates); UI text and outlines use
-- `inkUI`. `cream` stays the world Cream (sign and nameplate panels); foam panels use `panel` (Frosting).
Theme.Colors = {
	panel = Palette.PanelBody, -- Candy UI: windows and cards are dark
	panelStroke = Palette.UIStroke,
	cream = Palette.Cream,
	ink = Palette.Ink,
	primary = Palette.CandyCoral,
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
	-- UI surface tokens (Candy UI: the foam names kept, their values the dark candy look).
	frosting = Palette.WarmWhite, -- the light sticker face
	panelAlt = Palette.PanelRaised, -- a raised card or row on a window
	biscuit = Palette.PanelRecess, -- recessed fields and bar tracks
	bevel = Palette.PanelBevel, -- the bevel band under a dark surface
	inkUI = Palette.PlumInk, -- every outline; text on light faces
	ink2 = Palette.TextMuted, -- captions on dark surfaces
	text = Palette.WarmWhite, -- text on dark surfaces (Theme.text's default)
	textFaint = Palette.TextFaint, -- hints on dark surfaces
	rim = Palette.PanelRim, -- the inner rim highlight
	stickerBevel = Palette.StickerBevel, -- the bevel band under a light sticker
	gold = Palette.CandyGold,
	backdrop = Palette.Backdrop, -- the modal dimmer and wash
	-- World UI on light plates (collection plates, nameplates, the squeeze label) keeps the foam inks.
	worldInk = Palette.InkUI,
	worldInk2 = Palette.Ink2,
	disabledFace = Palette.DisabledFaceDark,
	disabledStroke = Palette.PlumInk,
	disabledShade = Palette.DisabledShadeDark,
	disabledText = Palette.DisabledTextDark,
}

-- Accent pairs (face / bevel shade). `light` faces carry PlumInk text, `dark` faces white text; the others follow the
-- outlined-text rule. Reserved and never an accent: CoinGold, CoinRing, CoinHighlight, Danger (§7.2).
local ACCENTS: { [string]: Accent } = {
	strawberry = { face = Palette.CandyCoral, shade = Palette.CandyCoralShade, light = false },
	mint = { face = Palette.CandyMint, shade = Palette.CandyMintShade, light = false },
	quests = { face = Palette.CandyMint, shade = Palette.CandyMintShade, light = false },
	lilac = { face = Palette.CandyLavender, shade = Palette.CandyLavenderShade, light = false },
	sky = { face = Palette.CandyCyan, shade = Palette.CandyCyanShade, light = false },
	shop = { face = Palette.CandyLime, shade = Palette.CandyLimeShade, light = false },
	gold = { face = Palette.CandyGold, shade = Palette.CandyGoldShade, light = true },
	red = { face = Palette.CandyRed, shade = Palette.CandyRedShade, light = false },
	plum = { face = Palette.CandyPlum, shade = Palette.CandyPlumShade, light = false, dark = true },
	frosting = { face = Palette.WarmWhite, shade = Palette.StickerBevel, light = true },
}
for _, accent in ACCENTS do
	table.freeze(accent)
end
Theme.Accents = table.freeze(ACCENTS)

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

local measureCache: { [string]: Vector2 } = {}
local measureCount = 0

local function preferredName(): string?
	local ok, value = pcall(function(): any
		return GuiService.PreferredTextSize
	end)
	if ok and typeof(value) == "EnumItem" then
		return (value :: EnumItem).Name
	end
	return nil
end

-- The weight drawn for a body text: Nunito lifts every weight one step (Bold body, ExtraBold emphasis, spec "Body:
-- Nunito Bold / ExtraBold"); Builder Sans keeps it.
local function bodyWeight(weight: Enum.FontWeight): Enum.FontWeight
	if BODY_FAMILY ~= "Nunito" then
		return weight
	end
	if weight == Enum.FontWeight.Bold then
		return Enum.FontWeight.ExtraBold
	elseif weight == Enum.FontWeight.ExtraBold or weight == Enum.FontWeight.Heavy then
		return Enum.FontWeight.Heavy
	end
	return Enum.FontWeight.Bold
end

-- The legacy Enum.Font that draws exactly like Theme.font(kind, weight) (TextService:GetTextSize needs one), or nil
-- when there is none (Nunito has only a Regular legacy face).
local function legacyFont(kind: string, weight: Enum.FontWeight?): Enum.Font?
	if DISPLAY_KINDS[kind] then
		return Enum.Font.FredokaOne
	end
	if BODY_FAMILY ~= "BuilderSans" then
		return nil
	end
	local w = weight or DEFAULT_WEIGHT[kind] or Enum.FontWeight.Medium
	if w == Enum.FontWeight.Bold then
		return Enum.Font.BuilderSansBold
	elseif w == Enum.FontWeight.ExtraBold or w == Enum.FontWeight.Heavy then
		return Enum.Font.BuilderSansExtraBold
	elseif w == Enum.FontWeight.Medium or w == Enum.FontWeight.SemiBold then
		return Enum.Font.BuilderSansMedium
	end
	return Enum.Font.BuilderSans
end

-- GetTextBoundsAsync for a Font object, cached. Nil when TextService cannot answer (or the caller cannot yield).
local function boundsAsync(text: string, font: Font, size: number, width: number): Vector2?
	local key = table.concat({ font.Family, font.Weight.Name, tostring(size), tostring(width), text }, "\0")
	local cached = measureCache[key]
	if cached then
		return cached
	end
	local ok, result = pcall(function(): Vector2
		local params: GetTextBoundsParams = Instance.new("GetTextBoundsParams")
		params.Text = text
		params.Font = font
		params.Size = size
		params.Width = width
		return TextService:GetTextBoundsAsync(params)
	end)
	if not ok or typeof(result) ~= "Vector2" then
		return nil
	end
	if measureCount >= MEASURE_CACHE_MAX then
		table.clear(measureCache)
		measureCount = 0
	end
	measureCache[key] = result
	measureCount += 1
	return result
end

local function setOutline(object: Instance, on: boolean, thickness: number?)
	local existing = object:FindFirstChild(OUTLINE_NAME)
	if on then
		if existing and existing:IsA("UIStroke") then
			existing.Enabled = true
			existing.Thickness = thickness or OUTLINE_PX
		else
			Create("UIStroke", {
				Name = OUTLINE_NAME,
				Color = Palette.PlumInk,
				Thickness = thickness or OUTLINE_PX,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
				LineJoinMode = Enum.LineJoinMode.Round,
				Parent = object,
			})
		end
	elseif existing and existing:IsA("UIStroke") then
		existing.Enabled = false
	end
end

-- WCAG 2 relative luminance of a colour (Candy UI: which faces take white text).
local function luminance(color: Color3): number
	local function channel(c: number): number
		return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
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

-- Public: fonts and sizes

function Theme.isDisplay(kind: string): boolean
	return DISPLAY_KINDS[kind] == true
end

function Theme.font(kind: string, weight: Enum.FontWeight?): Font
	if DISPLAY_KINDS[kind] then
		return DISPLAY_FONT
	end
	return Font.fromName(BODY_FAMILY, bodyWeight(weight or DEFAULT_WEIGHT[kind] or Enum.FontWeight.Medium))
end

-- Base text size of a kind with the player's PreferredTextSize applied (the UIScale applies on top).
function Theme.textSize(kind: string): number
	return Layout.textSize(kind, preferredName())
end

-- Sets FontFace, TextSize, TextColor3 (Colors.text, the light text of the dark surfaces, unless given) and wrapping on
-- a text object, and remembers the kind. Candy UI: a headline kind (AUTO_OUTLINE_KINDS) in the default colour carries
-- the PlumInk outline (outlinePx); a given colour, or any other kind, has none.
function Theme.text(object: GuiObject, kind: TextKind, weight: Enum.FontWeight?, color: Color3?): GuiObject
	local text = object :: any
	text.FontFace = Theme.font(kind, weight)
	text.TextSize = Theme.textSize(kind)
	text.TextColor3 = color or Theme.Colors.text
	text.TextWrapped = true
	object:SetAttribute(ATTR_TEXT_KIND, kind)
	setOutline(object, color == nil and AUTO_OUTLINE_KINDS[kind] == true, Theme.outlinePx(kind))
	return object
end

-- The size (base px, before the ScreenGui UIScale) `text` takes in `kind` at the player's text size; wrapped inside
-- `wrapWidth` base px when given. Never errors: an estimate when TextService cannot answer.
function Theme.textBounds(text: string, kind: TextKind, weight: Enum.FontWeight?, wrapWidth: number?): Vector2
	local size = Theme.textSize(kind)
	local frame = if wrapWidth and wrapWidth > 0 then wrapWidth else MEASURE_FRAME_PX
	local legacy = legacyFont(kind, weight)
	if legacy then
		local face = legacy
		local ok, result = pcall(function(): Vector2
			return TextService:GetTextSize(text, size, face, Vector2.new(frame, MEASURE_FRAME_PX))
		end)
		if ok and typeof(result) == "Vector2" then
			return result
		end
	else
		local exact = boundsAsync(text, Theme.font(kind, weight), size, frame)
		if exact then
			return exact
		end
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

-- Whether text of `kind` may be white with the PlumInk outline on a saturated fill (a display kind >= 16 base px).
function Theme.outlineAllowed(kind: string): boolean
	local base = Config.UI.TextSize[kind]
	return DISPLAY_KINDS[kind] == true and type(base) == "number" and base >= OUTLINE_MIN_BASE_PX
end

-- The outline thickness (base px) of outlined text of `kind`: 3 from 28 base px, 2.5 from 22, 2 from 18, else 1.5.
function Theme.outlinePx(kind: string): number
	local base = Config.UI.TextSize[kind]
	local px = if type(base) == "number" then base else 0
	return if px >= 28 then 3 elseif px >= 22 then 2.5 elseif px >= 18 then 2 else 1.5
end

-- The relative luminance (WCAG 2) of a colour.
function Theme.luminance(color: Color3): number
	return luminance(color)
end

-- Whether `face` is too dark for PlumInk text (it then takes white text at every size).
function Theme.isDarkFace(face: Color3): boolean
	return luminance(face) < DARK_FACE_LUMINANCE
end

-- Text on a saturated fill (an accent face): white with the PlumInk outline (outlinePx) when its kind allows it, else
-- PlumInk with no outline; on a dark `face` (isDarkFace) white at every size. `kind` defaults to the object's
-- Theme.text kind. Returns whether it is outlined.
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

-- Text on an accent face by name: PlumInk on a light accent (textOnLight), else textOnColor with its face.
function Theme.textOnAccent(object: GuiObject, accentName: string?, kind: TextKind?): boolean
	local accent = Theme.accent(accentName)
	if accent.light then
		Theme.textOnLight(object)
		return false
	end
	return Theme.textOnColor(object, kind, accent.face)
end

-- Text on a light surface (Frosting, Biscuit, the disabled face): `color` (default InkUI), no outline.
function Theme.textOnLight(object: GuiObject, color: Color3?)
	local text = object :: any
	text.TextColor3 = color or Theme.Colors.inkUI
	setOutline(object, false)
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

-- The colours of a foam surface on an accent: its face, its shade as the bevel, InkUI as the drop and, when
-- `highlight` is true, the face lightened by Theme.Foam.highlight as the top band.
function Theme.accentColors(name: string?, highlight: boolean?): FoamColors
	local accent = Theme.accent(name)
	return {
		face = accent.face,
		top = if highlight then accent.face:Lerp(Theme.Colors.white, Theme.Foam.highlight) else accent.face,
		bevel = accent.shade,
		drop = Theme.Colors.inkUI,
	}
end

-- The gradient colours of a foam surface `height` base px tall (Layout.foamStops): with `mode` "exact" (default) the
-- band colours themselves, with "tint" each band as a ratio of the face (the gradient then multiplies whatever
-- BackgroundColor3 the surface has).
function Theme.foamSequence(height: number, bands: Bands, colors: FoamColors, mode: FoamMode?): ColorSequence
	local face = colors.face
	local exact = mode ~= "tint"
	-- `ending`: the face band's last stop (Candy UI: it takes faceEnd, so the face fades from `face` to `faceEnd`).
	local function bandColor(name: Layout.FoamBand, ending: boolean): Color3
		local color = if name == "top"
			then colors.top or face
			elseif name == "bevel" then colors.bevel or face
			elseif name == "drop" then colors.drop or Theme.Colors.inkUI
			elseif ending and colors.faceEnd then colors.faceEnd
			else face
		return if exact then color else ratio(color, face)
	end
	local keypoints: { ColorSequenceKeypoint } = {}
	local previous: string? = nil
	for _, stop in Layout.foamStops(height, bands.top, bands.bevel, bands.drop) do
		local ending = stop.band == "face" and previous == "face"
		table.insert(keypoints, ColorSequenceKeypoint.new(stop.time, bandColor(stop.band, ending)))
		previous = stop.band
	end
	return ColorSequence.new(keypoints)
end

-- Gives `object` the foam look (UICorner, InkUI UIStroke, banded UIGradient; see the header). The bands follow the
-- object's size (the connection ends with the object), or, with style.fixedHeight, are drawn once for that height and
-- then scale with the object (a coin that grows and shrinks keeps its proportions). Returns a handle to repaint it.
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

	function self.paint(_: Foam, newColors: FoamColors)
		colors = newColors
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

-- The foam panel (cards, pills, dialogs): the dark PanelBody face (BackgroundColor3; a caller may recolour it, the
-- bevel follows), the PlumInk 3 px outline, the inner rim (rim()), bevel 5 and drop 4 (Theme.Foam.panel), `padding` on
-- every side but the bottom, which is at least the bands plus PANEL_BAND_GAP. Its first UIStroke is the foam outline
-- (callers recolour it for a highlight); the rim is the second, named SD_Rim.
function Theme.panel(props: { [string]: any }, radiusPx: number?, paddingPx: number?): Frame
	local frame: Frame = Create("Frame", {
		BackgroundColor3 = Theme.Colors.panel,
		BackgroundTransparency = Theme.Transparency.panel,
		BorderSizePixel = 0,
	})
	local bands = Theme.Foam.panel
	Theme.foam(frame, {
		radius = radiusPx or Theme.Radius.medium,
		mode = "tint",
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.panelColors(),
	})
	Theme.rim(frame)
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

-- A recessed field inside a panel (stats, odds, settings rows): a PanelRecess face (Candy UI: darker than the window)
-- with an inner shadow along its top, no outline, `padding` on every side (default Theme.Padding.medium). A caller may
-- recolour it; the shadow follows.
function Theme.inset(props: { [string]: any }, radiusPx: number?, paddingPx: number?): Frame
	local frame: Frame = Create("Frame", {
		BackgroundColor3 = Theme.Colors.biscuit,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
	})
	Theme.foam(frame, {
		radius = radiusPx or Theme.Radius.button,
		stroke = 0,
		mode = "tint",
		top = INSET_SHADOW_PX,
		colors = {
			face = Palette.PanelRecess,
			top = Palette.PanelRecess:Lerp(Color3.new(0, 0, 0), INSET_SHADOW_MIX),
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
