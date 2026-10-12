--!strict
-- Signs: SurfaceGui signs for the edit-time world builders (DESIGN §7.7 "Signs", §17.6 pod signs).
-- Server only, Edit mode only (ServerStorage.SDTools); runtime code never requires it.
-- Requires Kit/Prims (relative). It builds one sign from a WorldLayout.Signs entry (the data lives there); the text
-- comes from the Strings module the caller passes in (deps.Shared Strings), so this module holds no player-facing text.
--
-- Look (§7.7): a Cream panel with a Cocoa wood frame; Ink text with a 3 px Cream UIStroke; headings FredokaOne, body
-- BuilderSansBold (built-in fonts, V); SurfaceGui LightInfluence 0.15. Colours come from the caller (Art/Palette).
-- Letter heights are in studs. A label's text size is letterHeight × PixelsPerStud pixels and Roblox caps text at
-- 100 px, so a sign whose largest letter is over 2 studs uses PixelsPerStud = floor(100 / largest letter) instead of
-- 50 (DESIGN gives both PixelsPerStud 50 and 2.4-stud headings, which cannot hold together). Every label is TextScaled
-- under a UITextSizeConstraint at its letter size, so a longer text shrinks to fit instead of overflowing.
--
-- Line kinds (WorldLayout.SignLine) and the binder contract (§1.6, §17.6):
--   * textKey: STATIC. The TextLabel is tagged SD_Sign with attribute SD_TextKey = textKey and baked with that text;
--     WorldBinder re-applies Strings.resolve(SD_TextKey) at runtime, so text edits need no rebuild.
--   * bakeKey: BAKED. Text = Strings.format(bakeKey text, line.bakeArgs or the caller's bakeArgs). No SD_Sign tag and
--     no SD_TextKey (a template with placeholders must never be re-applied raw). A live line keeps the template key
--     as attribute SD_LiveKey for its runtime owner.
--   * neither: an empty label (a live line some controller fills).
--   `live` lines never carry SD_TextKey, so two binders never fight over one label.
-- Fit: Signs.measure(spec, align?) gives the stacked line height against the panel's (same maths as the layout), so a
-- test can prove no sign's lines run past its edges (the SurfaceGui clips them).
-- Placement: a "Front" sign's readable face looks along `facing` (CFrame.lookAt), or its panel takes `spec.cframe`
-- exactly (Front face = -Z). A "Top" sign is a floor plate whose text top points along `textUp`. A Top-face
-- SurfaceGui's text top is its part's -RightVector and its lines read along the LookVector (measured in Studio, Part 3
-- lobby screenshot), so the plate looks along textUp × Y.
-- Design plates (phase 3, the design lobby's plate(), sd/lobby.js:26-33; opts.plate): no Cocoa frame and a transparent
-- panel (a host keeps its look); an optional rounded backdrop "Plate" (corner = round × the panel's short side) with an
-- optional border (7 px of the design's 512-px canvas); every line in the plate's text colour with no outline.
-- Signs.logo draws the spawn medallion's logo (sd/lobby.js:149-155) on a Top host: a disc, a dashed ring, an inner
-- disc and 8 stars around its two keyed lines.

local Prims = require(script.Parent.Prims)

-- Types

export type SignLine = {
	name: string,
	textKey: string?,
	bakeKey: string?,
	bakeArgs: { [string]: number }?,
	live: boolean,
	clientKeys: { string }?,
	letterHeight: number,
	font: "heading" | "body",
}

export type SignSpec = {
	id: string,
	position: Vector3,
	size: Vector3,
	facing: Vector3,
	face: "Front" | "Top",
	textUp: Vector3?,
	tag: string?,
	tier: number?,
	cframe: CFrame?, -- an exact panel frame (Front face = -Z) instead of position + facing
	lines: { SignLine },
}

export type Style = {
	panel: Color3, -- Cream
	frame: Color3, -- Cocoa
	text: Color3, -- Ink
	stroke: Color3, -- Cream
}

-- A design plate (sd/lobby.js:26-33): colours are resolved by the caller (Art/Palette).
export type PlateStyle = {
	background: Color3?, -- the rounded backdrop; nil = text only (the design's bg: null)
	border: Color3?, -- the backdrop's border; nil = none (border: null)
	round: number?, -- corner radius as a share of the panel's short side (default 0.24)
	text: Color3, -- every line's colour (fg)
}

-- The spawn logo's host and colours (sd/lobby.js:150-154).
export type LogoOptions = {
	host: BasePart, -- the floor plate carrying the logo (yawed so its text top points along textUp)
	colors: { disc: Color3, ring: Color3, inner: Color3, star: Color3 },
	lineColors: { Color3 }, -- per line, in order
}

-- How a sign's lines sit on its panel, in SurfaceGui pixels (see Signs.measure).
export type Fit = {
	pixelsPerStud: number,
	canvasPx: number, -- the panel's text height
	contentPx: number, -- the stacked line boxes and the gaps between them
	startPx: number, -- where the stack starts below the panel's top edge
	fits: boolean, -- the whole stack stays on the canvas (the SurfaceGui clips anything past its edges)
}

export type StringsModule = {
	resolve: (path: string) -> string?,
	format: (template: string, args: { [string]: any }?) -> string,
}

export type BuildOptions = {
	style: Style,
	host: BasePart?, -- an existing station part that carries the SurfaceGui instead of a new panel
	bakeArgs: { [string]: any }?, -- placeholders for bakeKey lines without their own bakeArgs
	frame: boolean?, -- a Cocoa frame behind the panel or host (default: true for Front signs, false for Top)
	align: ("center" | "top")?, -- vertical placement of the lines (default "center")
	parent: Instance?, -- where a new panel's Model (or a host's frame) goes
	plate: PlateStyle?, -- a design plate: no frame, a transparent panel, its own backdrop and text colour
}

-- Constants

local TAG_SIGN = "SD_Sign"
local ATTR_TEXT_KEY = "SD_TextKey"
local ATTR_LIVE_KEY = "SD_LiveKey"
local ATTR_GRIP_TIER = "GripTier"
local GUI_NAME = "SignGui"
local CONTENT_NAME = "Content"
local PANEL_NAME = "Panel"
local FRAME_NAME = "Frame"

local BASE_PIXELS_PER_STUD = 50 -- §7.7
local MAX_TEXT_PX = 100 -- engine cap for TextSize / TextScaled
local LIGHT_INFLUENCE = 0.15 -- §7.7
local STROKE_PX = 3 -- §7.7
local LINE_BOX_FACTOR = 1.25 -- a label box is this many letter heights tall
local PADDING_STUDS = 0.15 -- inside the panel edge
local GAP_STUDS = 0.08 -- between lines
local FRAME_MARGIN = 0.3 -- the Cocoa frame shows this much around the panel
local HEADING_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.BuilderSansBold
local FRAME_MATERIAL = Enum.Material.Wood -- §7.3: sign frames
local PLATE_NAME = "Plate"
local PLATE_ROUND = 0.24 -- design: lobby.js:29 (o.round ?? 0.24)
local PLATE_CANVAS_PX = 512 -- design: lobby.js:31 (a plate's canvas is 512 px wide)
local PLATE_BORDER_PX = 7 -- design: lobby.js:29 (lineWidth 7)
-- The spawn logo (design: lobby.js:149-155): a 1024-px canvas on the logo circle.
local LOGO_CANVAS_PX = 1024
local LOGO_RING_RADIUS_PX = 1024 / 2 - 40 -- design: lobby.js:151 (W / 2 - 40)
local LOGO_RING_WIDTH_PX = 18 -- design: lobby.js:151
local LOGO_DASH_PX = 46 -- design: lobby.js:151 (setLineDash([46, 26]))
local LOGO_GAP_PX = 26 -- design: lobby.js:151
local LOGO_INNER_SHARE = 0.66 -- design: lobby.js:152 (radius W × 0.33)
local LOGO_LINE_OFFSETS_PX = { -70, 92 } -- design: lobby.js:153 (H / 2 - 70, H / 2 + 92)
local LOGO_STARS = 8 -- design: lobby.js:154
local LOGO_STAR_RADIUS_SHARE = 0.4 -- design: lobby.js:154 (W × 0.4)
local LOGO_STAR_PHASE = 0.39 -- design: lobby.js:154
local LOGO_STAR_PX = 2 * 28 -- design: lobby.js:154 (outer radius 28)
local STAR_GLYPH = "★" -- the design's 5-point star path, as a symbol glyph

-- Module table

local Signs = {}
Signs.TAG_SIGN = TAG_SIGN
Signs.ATTR_TEXT_KEY = ATTR_TEXT_KEY
Signs.ATTR_LIVE_KEY = ATTR_LIVE_KEY
Signs.GUI_NAME = GUI_NAME
Signs.PANEL_NAME = PANEL_NAME

-- Private

local function pixelsPerStud(lines: { SignLine }): number
	local largest = 0
	for _, line in lines do
		largest = math.max(largest, line.letterHeight)
	end
	if largest <= 0 then
		return BASE_PIXELS_PER_STUD
	end
	return math.min(BASE_PIXELS_PER_STUD, math.floor(MAX_TEXT_PX / largest))
end

local function resolve(strings: StringsModule, key: string): string
	local text = strings.resolve(key)
	if text == nil then
		error(string.format("[SD][Signs] Strings has no text for %q", key), 0)
	end
	return text
end

-- The text a line is baked with (see the module header).
local function lineText(strings: StringsModule, line: SignLine, bakeArgs: { [string]: any }?): string
	if line.textKey then
		return resolve(strings, line.textKey)
	elseif line.bakeKey then
		return strings.format(resolve(strings, line.bakeKey), line.bakeArgs or bakeArgs)
	end
	return ""
end

local function letterPixels(line: SignLine, pps: number): number
	return math.clamp(math.floor(line.letterHeight * pps + 0.5), 1, MAX_TEXT_PX)
end

local function paddingPixels(pps: number): number
	return math.floor(PADDING_STUDS * pps + 0.5)
end

local function gapPixels(pps: number): number
	return math.floor(GAP_STUDS * pps + 0.5)
end

local function addLine(
	content: Frame,
	line: SignLine,
	text: string,
	order: number,
	pps: number,
	style: Style,
	plateText: Color3?
): TextLabel
	local letterPx = letterPixels(line, pps)
	local label = Instance.new("TextLabel")
	label.Name = line.name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Size = UDim2.new(1, 0, 0, math.ceil(letterPx * LINE_BOX_FACTOR))
	label.LayoutOrder = order
	label.Font = if line.font == "heading" then HEADING_FONT else BODY_FONT
	label.TextColor3 = plateText or style.text
	label.TextStrokeTransparency = 1
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextScaled = true
	label.TextWrapped = false
	label.RichText = false
	label.TextSize = letterPx
	label.Text = text

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = letterPx
	constraint.MinTextSize = 1
	constraint.Parent = label

	if plateText == nil then -- the design's plate text has no outline (lobby.js:30)
		local stroke = Instance.new("UIStroke")
		stroke.Color = style.stroke
		stroke.Thickness = STROKE_PX
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
	end

	if line.textKey and not line.live then
		label:AddTag(TAG_SIGN)
		label:SetAttribute(ATTR_TEXT_KEY, line.textKey)
	elseif line.live and line.bakeKey then
		label:SetAttribute(ATTR_LIVE_KEY, line.bakeKey)
	end
	label.Parent = content
	return label
end

local function newGui(face: Enum.NormalId, pps: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = GUI_NAME
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pps
	gui.LightInfluence = LIGHT_INFLUENCE
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return gui
end

-- A centred Frame filling its parent, its corners rounded by `radius` (UDim.new(0.5, 0) makes a disc).
local function roundFrame(name: string, color: Color3, radius: UDim, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

-- The design plate's rounded backdrop on the Front face of `part` (lobby.js:29), inset by its border so the stroke
-- stays on the canvas.
local function addPlateBackdrop(gui: SurfaceGui, part: BasePart, plate: PlateStyle, pps: number)
	local background = plate.background
	if background == nil then
		return
	end
	local short = math.min(part.Size.X, part.Size.Y)
	local radius = math.floor((plate.round or PLATE_ROUND) * short * pps + 0.5)
	local frame = roundFrame(PLATE_NAME, background, UDim.new(0, radius), gui)
	local border = plate.border
	if border ~= nil then
		local thickness = math.max(1, math.floor(PLATE_BORDER_PX / PLATE_CANVAS_PX * part.Size.X * pps + 0.5))
		frame.Size = UDim2.new(1, -2 * thickness, 1, -2 * thickness)
		local stroke = Instance.new("UIStroke")
		stroke.Color = border
		stroke.Thickness = thickness
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
	end
end

-- A floor plate at `position` with world size `worldSize`, yawed so its Top-face text top (the part's -RightVector)
-- points along `up`: its CFrame and its size in the part's own axes.
local function topFrame(position: Vector3, worldSize: Vector3, up: Vector3): (CFrame, Vector3)
	local frame = Prims.facing(position, up:Cross(Vector3.yAxis))
	local right, back = frame.RightVector, frame.ZVector
	local size = Vector3.new(
		math.abs(right.X) * worldSize.X + math.abs(right.Z) * worldSize.Z,
		worldSize.Y,
		math.abs(back.X) * worldSize.X + math.abs(back.Z) * worldSize.Z
	)
	return frame, size
end

-- The CFrame and part-space size of a sign panel. Front: spec.cframe, else LookVector = facing. Top: see topFrame.
local function panelFrame(spec: SignSpec): (CFrame, Vector3)
	if spec.cframe ~= nil then
		return spec.cframe, spec.size
	end
	if spec.face == "Top" then
		return topFrame(spec.position, spec.size, spec.textUp or Vector3.new(0, 0, -1))
	end
	return Prims.facing(spec.position, spec.facing), spec.size
end

-- Yaws a floor host (e.g. the spawn logo plate) like a new floor panel, keeping its world footprint.
local function orientTopHost(host: BasePart, spec: SignSpec)
	local cf, s = host.CFrame, host.Size
	local worldSize = Vector3.new(
		math.abs(cf.XVector.X) * s.X + math.abs(cf.YVector.X) * s.Y + math.abs(cf.ZVector.X) * s.Z,
		math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z,
		math.abs(cf.XVector.Z) * s.X + math.abs(cf.YVector.Z) * s.Y + math.abs(cf.ZVector.Z) * s.Z
	)
	local frame, size = topFrame(cf.Position, worldSize, spec.textUp or Vector3.new(0, 0, -1))
	host.Size = size
	host.CFrame = frame
end

-- A Cocoa plate half behind `part` (its front face is the part's mid-plane), FRAME_MARGIN larger on each side, so it
-- shows as a border and never shares a plane with the part or with a wall the part is flush against.
local function addFrame(part: BasePart, style: Style, parent: Instance)
	local size = part.Size
	Prims.part({
		name = FRAME_NAME,
		size = Vector3.new(size.X + 2 * FRAME_MARGIN, size.Y + 2 * FRAME_MARGIN, size.Z),
		cframe = part.CFrame * CFrame.new(0, 0, size.Z / 2), -- +Z is behind the Front face
		color = style.frame,
		material = FRAME_MATERIAL,
		flags = "decor",
		parent = parent,
	})
end

-- Public

-- A SurfaceGui with `lines` on face `face` of `part`. Errors on a key Strings lacks (builders check every key first).
-- `plate` (a Front face): the design plate's backdrop and text colour (see the header).
function Signs.surface(
	strings: StringsModule,
	part: BasePart,
	face: Enum.NormalId,
	lines: { SignLine },
	style: Style,
	bakeArgs: { [string]: any }?,
	align: ("center" | "top")?,
	plate: PlateStyle?
): SurfaceGui
	local pps = pixelsPerStud(lines)
	local gui = newGui(face, pps)
	if plate then
		addPlateBackdrop(gui, part, plate, pps)
	end

	local content = Instance.new("Frame")
	content.Name = CONTENT_NAME
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = gui

	local padding = Instance.new("UIPadding")
	local padPx = UDim.new(0, paddingPixels(pps))
	padding.PaddingTop = padPx
	padding.PaddingBottom = padPx
	padding.PaddingLeft = padPx
	padding.PaddingRight = padPx
	padding.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = if align == "top" then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, gapPixels(pps))
	layout.Parent = content

	local plateText = if plate then plate.text else nil
	for index, line in lines do
		addLine(content, line, lineText(strings, line, bakeArgs), index, pps, style, plateText)
	end
	gui.Parent = part
	return gui
end

-- Builds the sign `spec` and returns the part that carries its SurfaceGui (the host, or a new "Panel").
-- With opts.host: the SurfaceGui goes on the host's `spec.face`; a frame (Front signs) goes next to the host; a Top
-- host is yawed in place so its text top points along textUp.
-- Without: a Model named spec.id under opts.parent holding "Panel" (Cream, decor) and, for Front signs, "Frame".
-- `spec.tag` (SD_GripSign) and `spec.tier` (GripTier) go on the part that carries the SurfaceGui.
function Signs.build(strings: StringsModule, spec: SignSpec, opts: BuildOptions): BasePart
	local face = if spec.face == "Top" then Enum.NormalId.Top else Enum.NormalId.Front
	local wantFrame = if opts.plate then false elseif opts.frame == nil then spec.face ~= "Top" else opts.frame
	local carrier: BasePart
	local host = opts.host
	if host then
		carrier = host
		if spec.face == "Top" then
			orientTopHost(host, spec)
		end
		if wantFrame and host.Parent then
			addFrame(host, opts.style, host.Parent :: Instance)
		end
	else
		local frame, size = panelFrame(spec)
		local model = Prims.model(spec.id, nil, false, frame)
		carrier = Prims.part({
			name = PANEL_NAME,
			size = size,
			cframe = frame,
			color = opts.style.panel,
			transparency = if opts.plate then 1 else nil, -- a design plate is only its SurfaceGui
			shadow = if opts.plate then false else nil,
			flags = "decor",
			parent = model,
		})
		if wantFrame then
			addFrame(carrier, opts.style, model)
		end
		if opts.parent then
			model.Parent = opts.parent
		end
	end
	if spec.tag then
		carrier:AddTag(spec.tag)
		if spec.tier ~= nil then
			carrier:SetAttribute(ATTR_GRIP_TIER, spec.tier)
		end
	end
	Signs.surface(strings, carrier, face, spec.lines, opts.style, opts.bakeArgs, opts.align, opts.plate)
	return carrier
end

-- The spawn logo (sd/lobby.js:149-155) on the floor plate opts.host, yawed so its text top points along spec.textUp:
-- a disc ("Disc"), the dashed ring ("Dash" × 41: 46-px dashes and 26-px gaps on radius 472 of the 1024-px canvas),
-- the inner disc ("Inner"), 8 stars ("Star") and spec's two lines (static keys, SD_Sign) centred 70 px above and
-- 92 px below the middle, in opts.lineColors. Errors on a key Strings lacks.
function Signs.logo(strings: StringsModule, spec: SignSpec, opts: LogoOptions): SurfaceGui
	local host = opts.host
	orientTopHost(host, spec)
	local pps = pixelsPerStud(spec.lines)
	local gui = newGui(Enum.NormalId.Top, pps)
	local colors = opts.colors
	roundFrame("Disc", colors.disc, UDim.new(0.5, 0), gui)
	local radius = LOGO_RING_RADIUS_PX / LOGO_CANVAS_PX
	local period = LOGO_DASH_PX + LOGO_GAP_PX
	for index = 0, math.floor(2 * math.pi * LOGO_RING_RADIUS_PX / period) - 1 do
		local angle = (index * period + LOGO_DASH_PX / 2) / LOGO_RING_RADIUS_PX -- the dash's middle along the ring
		local dash = Instance.new("Frame")
		dash.Name = "Dash"
		dash.BackgroundColor3 = colors.ring
		dash.BorderSizePixel = 0
		dash.AnchorPoint = Vector2.new(0.5, 0.5)
		dash.Position = UDim2.fromScale(0.5 + radius * math.cos(angle), 0.5 + radius * math.sin(angle))
		dash.Size = UDim2.fromScale(LOGO_DASH_PX / LOGO_CANVAS_PX, LOGO_RING_WIDTH_PX / LOGO_CANVAS_PX)
		dash.Rotation = math.deg(angle) + 90 -- along the ring (the canvas and the GUI both run y downward)
		dash.ZIndex = 1
		dash.Parent = gui
	end
	local inner = roundFrame("Inner", colors.inner, UDim.new(0.5, 0), gui)
	inner.Size = UDim2.fromScale(LOGO_INNER_SHARE, LOGO_INNER_SHARE)
	inner.ZIndex = 1
	for index = 0, LOGO_STARS - 1 do
		local angle = (index / LOGO_STARS) * 2 * math.pi + LOGO_STAR_PHASE
		local star = Instance.new("TextLabel")
		star.Name = "Star"
		star.BackgroundTransparency = 1
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position = UDim2.fromScale(
			0.5 + LOGO_STAR_RADIUS_SHARE * math.cos(angle),
			0.5 + LOGO_STAR_RADIUS_SHARE * math.sin(angle)
		)
		star.Size = UDim2.fromScale(LOGO_STAR_PX / LOGO_CANVAS_PX, LOGO_STAR_PX / LOGO_CANVAS_PX)
		star.Font = HEADING_FONT
		star.Text = STAR_GLYPH
		star.TextColor3 = colors.star
		star.TextScaled = true
		star.ZIndex = 2
		star.Parent = gui
	end
	local content = Instance.new("Frame")
	content.Name = CONTENT_NAME
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 3
	content.Parent = gui
	local style: Style = { panel = colors.disc, frame = colors.disc, text = colors.ring, stroke = colors.disc }
	for index, line in spec.lines do
		local color = opts.lineColors[index] or style.text
		local label = addLine(content, line, lineText(strings, line, nil), index, pps, style, color)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5 + (LOGO_LINE_OFFSETS_PX[index] or 0) / LOGO_CANVAS_PX)
		label.Size = UDim2.new(LOGO_INNER_SHARE, 0, 0, math.ceil(letterPixels(line, pps) * LINE_BOX_FACTOR))
	end
	gui.Parent = host
	return gui
end

-- How the lines of `spec` sit on its panel, with the same maths surface() lays them out with. The canvas height is
-- the panel's Y size (Front) or its world extent along textUp (Top). "center" centres the stack between the
-- paddings; "top" starts it below the top padding. A stack taller than the space between the paddings may run into
-- them, but it fits only while it stays on the canvas: the SurfaceGui clips what lies past its edges.
function Signs.measure(spec: SignSpec, align: ("center" | "top")?): Fit
	local pps = pixelsPerStud(spec.lines)
	local heightStuds = spec.size.Y
	if spec.face == "Top" then
		local up = spec.textUp or Vector3.new(0, 0, -1)
		heightStuds = math.abs(up.X) * spec.size.X + math.abs(up.Z) * spec.size.Z
	end
	local canvas = heightStuds * pps
	local pad = paddingPixels(pps)
	local content = 0
	for index, line in spec.lines do
		content += math.ceil(letterPixels(line, pps) * LINE_BOX_FACTOR)
		if index > 1 then
			content += gapPixels(pps)
		end
	end
	local start = if align == "top" then pad else pad + (canvas - 2 * pad - content) / 2
	return {
		pixelsPerStud = pps,
		canvasPx = canvas,
		contentPx = content,
		startPx = start,
		fits = start >= -1e-6 and start + content <= canvas + 1e-6,
	}
end

-- The Strings keys a sign needs to be built (textKey and bakeKey of every line), appended to `out`.
function Signs.keysOf(spec: SignSpec, out: { string }): { string }
	for _, line in spec.lines do
		if line.textKey then
			table.insert(out, line.textKey)
		end
		if line.bakeKey then
			table.insert(out, line.bakeKey)
		end
	end
	return out
end

-- The world direction the text top of a Top-face SurfaceGui on `part` points to (for checks and tests).
function Signs.topTextUp(part: BasePart): Vector3
	return -part.CFrame.RightVector
end

return Signs
