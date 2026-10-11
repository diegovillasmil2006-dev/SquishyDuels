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

export type AccentName = "strawberry" | "mint" | "quests" | "lilac" | "sky" | "shop" | "frosting"
export type Accent = { face: Color3, shade: Color3, light: boolean }

-- "exact": the bands are painted in their colours over a white background; "tint": they darken BackgroundColor3.
export type FoamMode = "exact" | "tint"

-- Foam band heights in base px.
export type Bands = { top: number, bevel: number, drop: number }

-- The colours of a foam surface. Missing bands fall back to the face (top), the face (bevel) and InkUI (drop).
export type FoamColors = { face: Color3, top: Color3?, bevel: Color3?, drop: Color3? }

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
-- The outlined-text rule: white text with the InkUI outline only for display kinds this big (base px) or bigger.
local OUTLINE_MIN_BASE_PX = 18
local OUTLINE_PX = 2

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
local TAB_PADDING_X = 20
local TAB_PADDING_Y = 4
local TAB_GAP = 6
local TAB_ZINDEX = 5
-- Inset field: the inner shadow band at its top (base px) and how much darker it is than the field.
local INSET_SHADOW_PX = 3
local INSET_SHADOW_MIX = 0.06

-- Module table

local Theme = {}

Theme.BODY_FAMILY = BODY_FAMILY
Theme.OUTLINE_MIN_BASE_PX = OUTLINE_MIN_BASE_PX

-- Colour tokens (Art/Palette, §7.2 and the foam spec). Side colours: A = Strawberry side, B = Mint side (§7.8; always
-- with text too; unchanged by the foam restyle). `ink` stays the world Ink (nameplates); UI text and outlines use
-- `inkUI`. `cream` stays the world Cream (sign and nameplate panels); foam panels use `panel` (Frosting).
Theme.Colors = {
	panel = Palette.Frosting,
	panelStroke = Palette.UIStroke,
	cream = Palette.Cream,
	ink = Palette.Ink,
	primary = Palette.UIStrawberry,
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
	-- Foam UI tokens.
	frosting = Palette.Frosting,
	panelAlt = Palette.PanelAlt,
	biscuit = Palette.Biscuit,
	bevel = Palette.Bevel,
	inkUI = Palette.InkUI,
	ink2 = Palette.Ink2,
	disabledFace = Palette.DisabledFace,
	disabledStroke = Palette.DisabledStroke,
	disabledShade = Palette.DisabledShade,
	disabledText = Palette.DisabledText,
}

-- Accent pairs (face / bevel shade). `light` faces carry InkUI text; the others follow the outlined-text rule.
-- Reserved and never an accent: CoinGold, CoinRing, CoinHighlight, Danger (§7.2).
local ACCENTS: { [string]: Accent } = {
	strawberry = { face = Palette.UIStrawberry, shade = Palette.UIStrawberryShade, light = false },
	mint = { face = Palette.UIMint, shade = Palette.UIMintShade, light = false },
	quests = { face = Palette.UIQuestMint, shade = Palette.UIQuestMintShade, light = false },
	lilac = { face = Palette.UILilac, shade = Palette.UILilacShade, light = false },
	sky = { face = Palette.UISkyBlue, shade = Palette.UISkyBlueShade, light = false },
	shop = { face = Palette.UIApple, shade = Palette.UIAppleShade, light = false },
	frosting = { face = Palette.Frosting, shade = Palette.Bevel, light = true },
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
Theme.Stroke = { thin = 1.5, medium = 2, thick = 3, ink = 2.5, bar = 2, text = OUTLINE_PX }
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

local function setOutline(object: Instance, on: boolean)
	local existing = object:FindFirstChild(OUTLINE_NAME)
	if on then
		if existing and existing:IsA("UIStroke") then
			existing.Enabled = true
		else
			Create("UIStroke", {
				Name = OUTLINE_NAME,
				Color = Palette.InkUI,
				Thickness = OUTLINE_PX,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
				LineJoinMode = Enum.LineJoinMode.Round,
				Parent = object,
			})
		end
	elseif existing and existing:IsA("UIStroke") then
		existing.Enabled = false
	end
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

-- Sets FontFace, TextSize, TextColor3 (InkUI unless given) and wrapping on a text object, and remembers the kind.
function Theme.text(object: GuiObject, kind: TextKind, weight: Enum.FontWeight?, color: Color3?): GuiObject
	local text = object :: any
	text.FontFace = Theme.font(kind, weight)
	text.TextSize = Theme.textSize(kind)
	text.TextColor3 = color or Theme.Colors.inkUI
	text.TextWrapped = true
	object:SetAttribute(ATTR_TEXT_KIND, kind)
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

-- Whether text of `kind` may be white with the InkUI outline on a saturated fill (a display kind >= 18 base px).
function Theme.outlineAllowed(kind: string): boolean
	local base = Config.UI.TextSize[kind]
	return DISPLAY_KINDS[kind] == true and type(base) == "number" and base >= OUTLINE_MIN_BASE_PX
end

-- Text on a saturated fill (an accent face): white with the 2 px InkUI outline when its kind allows it, else InkUI
-- with no outline. `kind` defaults to the object's Theme.text kind. Returns whether it is outlined.
function Theme.textOnColor(object: GuiObject, kind: TextKind?): boolean
	local stored = object:GetAttribute(ATTR_TEXT_KIND)
	local k: string = kind or (if type(stored) == "string" then stored else "Body")
	local outlined = Theme.outlineAllowed(k)
	local text = object :: any
	text.TextColor3 = if outlined then Theme.Colors.white else Theme.Colors.inkUI
	setOutline(object, outlined)
	return outlined
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
	local function bandColor(name: Layout.FoamBand): Color3
		local color = if name == "top"
			then colors.top or face
			elseif name == "bevel" then colors.bevel or face
			elseif name == "drop" then colors.drop or Theme.Colors.inkUI
			else face
		return if exact then color else ratio(color, face)
	end
	local keypoints: { ColorSequenceKeypoint } = {}
	for _, stop in Layout.foamStops(height, bands.top, bands.bevel, bands.drop) do
		table.insert(keypoints, ColorSequenceKeypoint.new(stop.time, bandColor(stop.band)))
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

-- The foam panel (cards, pills, dialogs): Frosting face (BackgroundColor3; a caller may recolour it, the bevel
-- follows), the InkUI 2.5 outline, bevel 5 and drop 4 (Theme.Foam.panel), `padding` on every side but the bottom, which is at
-- least the bands plus PANEL_BAND_GAP. Its UIStroke is the foam outline (callers recolour it for a highlight).
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
		colors = { face = Palette.Frosting, bevel = Palette.Bevel, drop = Palette.InkUI },
	})
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

-- A recessed field inside a panel (stats, odds, settings rows): a Biscuit face with an inner shadow along its top, no
-- outline, `padding` on every side (default Theme.Padding.medium). A caller may recolour it; the shadow follows.
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
			face = Palette.Biscuit,
			top = Palette.Biscuit:Lerp(Palette.InkUI, INSET_SHADOW_MIX),
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

-- A title tab straddling `panel`'s top edge (spec "header-tab title"): an accent foam pill with the title in a display
-- kind (outlined white, the rule). It is positioned by hand, so `panel` must not hold a UIListLayout directly (put the
-- list in a child frame) nor clip its descendants. The panel's top padding grows to keep TAB_GAP under the tab's lower
-- half (measured at the current text size). Returns the tab (named options.name or "HeaderTab") and its label.
function Theme.headerTab(panel: GuiObject, text: string, options: HeaderTabOptions?): (Frame, TextLabel)
	local o: HeaderTabOptions = options or {}
	local kind: TextKind = o.textKind or "H2"
	local bands = Theme.Foam.button
	local height = math.ceil(Theme.lineHeight(kind)) + 2 * TAB_PADDING_Y + bands.top + bands.bevel + bands.drop
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
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = TAB_ZINDEX,
	})
	Theme.foam(tab, {
		radius = Theme.Radius.pill,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.accentColors(o.accent or "strawberry", true),
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, TAB_PADDING_X),
		PaddingRight = UDim.new(0, TAB_PADDING_X),
		PaddingTop = UDim.new(0, TAB_PADDING_Y + bands.top),
		PaddingBottom = UDim.new(0, TAB_PADDING_Y + bands.bevel + bands.drop),
		Parent = tab,
	})
	local label = Theme.label({
		Name = "Title",
		Text = text,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = TAB_ZINDEX,
		Parent = tab,
	}, kind)
	if Theme.accent(o.accent or "strawberry").light then
		Theme.textOnLight(label)
	else
		Theme.textOnColor(label)
	end
	tab.Parent = panel
	return tab, label
end

return Theme
