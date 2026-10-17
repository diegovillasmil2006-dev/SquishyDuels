--!strict
-- Toggle (client only). DESIGN §11.1 (UI/Components: Toggle), §11.6 (Settings toggles, "Show not owned"), §11.4,
-- §11.2 (touch targets), §9.13 (never colour alone).
--   local toggle = Toggle.new({ name = "Settings_CameraShakeToggle", text = Strings.settings.cameraShake, value = true,
--       onChanged = function(on) ... end, parent = list })
--   toggle:setValue(false)   -- no callback
-- One button the full row wide (label left, switch right): a click, tap or ButtonA flips it. The state shows three
-- ways: the knob's side, the track colour and the state text (common.on / common.off).
-- Part 8: Toggle.widthFor(text) is the width (base px) a toggle needs to show `text` on one line at the player's text
-- size (Theme.textWidth + the state text and the switch), for a caller that sets widthPx (the Squishies filter row).
-- Foam UI (spec 2026-10-09): the switch is a Biscuit track (off) or the Mint accent (on) with the InkUI 2 px outline of
-- bars and chips; the knob is a Frosting foam disc with a small bevel. Sizes and behaviour unchanged.
-- UI FINAL R1 (H:197, H:437, H:980, H:1010): spec.variant "small" (56 × 32, the default; the Squishies switch) or
-- "large" (80 × 42, the Settings switches), Config.UI.Sticker.toggles: a 4 px ink border drawn inside the switch, the
-- on track StickerToggleOnTop -> StickerGreen2End, the off track StickerSwitchOff, the white knob at the design's
-- places inside the border (small: 20 px with its ink drop 2 px lower at .4; large: 28 px with a 3 px ink border and a
-- 3 px bevel at .12), the large track's inner shade (3 px at .25). The row stays one button the touch minimum tall.
-- UI FINAL R2 (G1.1, P7; H:197, H:437): a flip slides the knob over the variant's knobMs (300 / 350) on the design's
-- cubic-bezier(.3,1.8,.5,1) and eases the track's colour over trackMs (200 / 250, `ease`): Config.UI.Sticker.toggles,
-- one Scheduler render effect while it moves (Toggle.motionAt, pure); setValue and ReducedMotion snap.
-- UI FINAL R5 (H:195-197, the Squishies "Show locked" group): spec.stateText = false drops the On / Off text;
-- spec.labelBeside = "left" puts the label right-aligned just left of the switch (spec.gapPx apart, default 8: H:195),
-- in Small (16 px, PR2) with line height 1.1, wrapping on its "\n", in the window's text colour (H:196), and draws the
-- label and switch inside an unlaid-out holder (toggle.visual: a caller's Button.decorate poses it, the hit box stays).
-- Toggle.widthFor(text, variant, beside?) measures that group (its widest line).
-- UI FINAL R9 (G9.6-G9.8, H:433-438, H:634-638, H:889-892; Config.UI.Sticker.settings): spec.row = true is the
-- design's Settings row: the purple row face (74 + the 5 px lip, border 4, radius 20, padding 0 16 0 10, gap 14, the
-- row surface's 3 px highlight at .1) drawn in an inner SD_Visual with Button's feel (fx "row": x +4, the hover
-- brightness, the press squash; the hover sound, no click sound), the picture spec.icon (an AssetTable image key)
-- in its 50 px slot (kept empty without one), the label growing in the settingsRow role, the On / Off text in
-- settingsState and the switch; the whole row toggles. A row plays ui.click at Config.Audio.uiPitch toggleOn /
-- toggleOff (lib:152): a switch going off sounds before onChanged runs and one going on after it (H:891: the Sound
-- effects switch is heard both ways). Toggle.soundAfterChange(on) is that order (pure).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Client = UI.Parent
local Button = require(script.Parent.Button)
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local IconGlyph = require(script.Parent.IconGlyph)
local Layout = require(UI.Layout)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Spec = {
	name: string,
	text: string,
	value: boolean,
	onChanged: (value: boolean) -> (),
	widthPx: number?, -- nil = fill the parent's width
	variant: Variant?, -- default "small"
	layoutOrder: number?,
	parent: Instance?,
	stateText: boolean?, -- UI FINAL R5: false = no On / Off text (default shown)
	labelBeside: "left"?, -- UI FINAL R5: the label right-aligned just left of the switch (see the header)
	gapPx: number?, -- UI FINAL R5: the label's gap to the switch beside it (default BESIDE_GAP)
	row: boolean?, -- UI FINAL R9: the design's Settings row (see the header)
	icon: string?, -- UI FINAL R9: a row's picture (an AssetTable image key)
}

-- UI FINAL R1: the design's two switches (Config.UI.Sticker.toggles).
export type Variant = "small" | "large"

export type Toggle = {
	root: TextButton,
	visual: GuiObject, -- UI FINAL R5: what draws the toggle (the label beside it: an inner holder; else the root)
	setValue: (self: Toggle, value: boolean) -> (),
	getValue: (self: Toggle) -> boolean,
	setText: (self: Toggle, text: string) -> (),
	destroy: (self: Toggle) -> (),
}

-- Constants

local TOUCH = Config.UI.Touch
local TOGGLES = Config.UI.Sticker.toggles
local KNOB_CURVE = Tweens.curve(Config.UI.Sticker.toggleKnobCurve) -- H:197, H:437
local TRACK_CURVE = Tweens.curve(Config.UI.Sticker.toggleTrackCurve)
local DEFAULT_VARIANT = "small"
local STATE_WIDTH = 60
local ON_TEXT = Strings.common.on
local OFF_TEXT = Strings.common.off
local MEASURE_MARGIN_PX = 4
local ON_TOP = Palette.StickerToggleOnTop -- H:980
local ON_END = Palette.StickerGreen2End
local OFF_FILL = Palette.StickerSwitchOff -- H:980
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local BESIDE_GAP = 8 -- H:195: the label to the switch
local BESIDE_LINE_HEIGHT = 1.1 -- H:196
local BESIDE_KIND: Theme.TextKind = "Small" -- H:196: 13 px -> 16 (PR2)
-- UI FINAL R9: the Settings row (Config.UI.Sticker.settings, H:433-438) and its switch sounds (lib:152).
local SETTINGS = Config.UI.Sticker.settings
local ROW = SETTINGS.row
local ROW_SURFACE = Config.UI.Sticker.surfaces.row -- H:433: inset 0 3px 0 rgba(255,255,255,.1)
local ROW_LABEL_ROLE = "settingsRow"
local ROW_STATE_ROLE = "settingsState"
local ROW_LABEL_KIND: Theme.TextKind = "Button" -- the settingsRow role's kind (20 px, H:435)
local ROW_STATE_KIND: Theme.TextKind = "Small" -- the settingsState role's kind (14 px -> 16, H:436)
local UI_PITCH = Config.Audio.uiPitch
local SOUND_CLICK = "ui.click"

-- Everything beside the label (base px): the switch, the state text and their gaps.
local function chromePx(variant: string): number
	return (TOGGLES[variant] or TOGGLES[DEFAULT_VARIANT]).width + STATE_WIDTH + Theme.Padding.small * 2
end

-- Module table

local Toggle = {}

-- Private

local log = Log.new("Toggle")

-- Public

-- UI FINAL R2: a flip `elapsedMs` in, on `variant` ("small" / "large"): the knob's share of its way (0..1, past 1 on
-- the design's overshoot), the track colour's share (0..1) and whether both have arrived.
function Toggle.motionAt(variant: Variant, elapsedMs: number): (number, number, boolean)
	local look = TOGGLES[variant] or TOGGLES[DEFAULT_VARIANT]
	local knobU = if look.knobMs > 0 then math.clamp(elapsedMs / look.knobMs, 0, 1) else 1
	local trackU = if look.trackMs > 0 then math.clamp(elapsedMs / look.trackMs, 0, 1) else 1
	return KNOB_CURVE(knobU), math.clamp(TRACK_CURVE(trackU), 0, 1), knobU >= 1 and trackU >= 1
end

-- The width (base px) a toggle (default variant "small") needs for `text` on one line at the player's text size, with
-- its state text and switch.
function Toggle.widthFor(text: string, variant: Variant?, beside: boolean?): number
	if beside then
		-- UI FINAL R5: the label beside the switch: its widest line, the gap and the switch.
		local widest = 0
		for line in string.gmatch(text, "[^\n]+") do
			widest = math.max(widest, Theme.textWidth(line, BESIDE_KIND))
		end
		local look = TOGGLES[variant or DEFAULT_VARIANT] or TOGGLES[DEFAULT_VARIANT]
		return math.ceil(widest) + BESIDE_GAP + look.width + MEASURE_MARGIN_PX
	end
	return math.ceil(Theme.textWidth(text, "Body")) + chromePx(variant or DEFAULT_VARIANT) + MEASURE_MARGIN_PX
end

-- UI FINAL R9 (H:891): whether a row's switch sound plays after onChanged (going on: the sound effects are back on
-- first) rather than before it (going off: heard before they mute).
function Toggle.soundAfterChange(on: boolean): boolean
	return on == true
end

-- UI FINAL R9: the On / Off text's width in a row (base px): the wider of the two, measured.
local function stateWidth(): number
	local widest = math.max(Theme.textWidth(ON_TEXT, ROW_STATE_KIND), Theme.textWidth(OFF_TEXT, ROW_STATE_KIND))
	return math.ceil(widest) + MEASURE_MARGIN_PX
end

function Toggle.new(spec: Spec): Toggle
	local cleanup = Cleanup.new()
	local value = spec.value == true
	local variant: string = if spec.variant and TOGGLES[spec.variant] then spec.variant else DEFAULT_VARIANT
	local look = TOGGLES[variant]
	local chrome = chromePx(variant)
	local row = spec.row == true
	local height = if row then ROW.face + ROW.lip else TOUCH.minTarget
	local root: TextButton = Create("TextButton", {
		Name = spec.name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = if spec.widthPx then UDim2.fromOffset(spec.widthPx, height) else UDim2.new(1, 0, 0, height),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Focus.decorate(root)
	-- UI FINAL R5: beside the switch, the label and the switch sit in an unlaid-out holder a caller may pose.
	local beside = spec.labelBeside == "left"
	local holder: GuiObject = root
	if beside then
		holder = Create("Frame", {
			Name = "SD_Visual",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Active = false,
			Parent = root,
		})
	end
	local besideGap = spec.gapPx or BESIDE_GAP
	-- UI FINAL R9: the Settings row's face (H:433) in SD_Visual (Button's row feel poses it), its parts in Content.
	local rowFoam: Theme.Foam? = nil
	local rowVisual: Frame? = nil
	local rowStateWidth = 0
	if row then
		local visual: Frame = Create("Frame", {
			Name = "SD_Visual",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Active = false,
			Parent = root,
		})
		local face: Frame = Create("Frame", {
			Name = "Face",
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Active = false,
			Parent = visual,
		})
		local bands = Layout.stickerBands(ROW.border, ROW_SURFACE.highlightPx, 0, ROW.lip)
		rowFoam = Theme.foam(face, {
			radius = ROW.radius,
			stroke = ROW.border,
			inner = true,
			top = bands.top,
			drop = bands.drop,
		})
		local content: Frame = Create("Frame", {
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, -ROW.lip),
			Active = false,
			Parent = face,
		})
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, ROW.border + ROW.padLeft),
			PaddingRight = UDim.new(0, ROW.border + ROW.padRight),
			PaddingTop = UDim.new(0, ROW.border),
			PaddingBottom = UDim.new(0, ROW.border),
			Parent = content,
		})
		-- H:434: the picture in its 50 px slot (empty without one: the rows' labels line up).
		local slot: Frame = Create("Frame", {
			Name = "IconSlot",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(SETTINGS.icon, SETTINGS.icon),
			Active = false,
			Parent = content,
		})
		local icon = spec.icon
		if icon and AssetTable.image(icon) then
			IconGlyph.image(icon, { name = "Icon", sizePx = SETTINGS.icon, parent = slot })
		end
		rowStateWidth = stateWidth()
		rowVisual = visual
		holder = content
	end

	local label = Theme.label({
		Name = "Label",
		Text = spec.text,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, -chrome, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	}, "Body")
	if row then
		-- H:435: the label grows between the picture and the state text: one line, its measured height.
		Theme.stickerText(label, ROW_LABEL_ROLE)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.Position = UDim2.new(0, SETTINGS.icon + ROW.gap, 0.5, 0)
		label.Size = UDim2.new(
			1,
			-(SETTINGS.icon + ROW.gap + ROW.gap + rowStateWidth + ROW.gap + look.width),
			0,
			math.ceil(Theme.lineHeight(ROW_LABEL_KIND))
		)
	end
	if beside then
		Theme.text(label, BESIDE_KIND)
		Theme.textOnWindow(label) -- H:196: #8A2468 on the pink body
		label.LineHeight = BESIDE_LINE_HEIGHT
		label.TextXAlignment = Enum.TextXAlignment.Right
		-- Measured height, not AutomaticSize: under the window's UIScale the automatic box stayed one line tall and hid
		-- the second line ("Show" | "locked").
		local _, breaks = string.gsub(spec.text, "\n", "")
		local height = (breaks + 1) * Theme.lineHeight(BESIDE_KIND) * BESIDE_LINE_HEIGHT
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.new(1, -(look.width + besideGap), 0, math.ceil(height))
	end
	local stateLabel = Theme.label({
		Name = "State",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(look.width + Theme.Padding.small), 0.5, 0),
		Size = UDim2.fromOffset(STATE_WIDTH, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = spec.stateText ~= false,
		Parent = holder,
	}, "Small", Enum.FontWeight.Bold)
	if row then
		-- H:436: On / Off (14 px -> 16, #EDE4FF), ROW.gap before the switch, its measured box.
		Theme.stickerText(stateLabel, ROW_STATE_ROLE)
		stateLabel.AutomaticSize = Enum.AutomaticSize.None
		stateLabel.TextWrapped = false
		stateLabel.Position = UDim2.new(1, -(look.width + ROW.gap), 0.5, 0)
		stateLabel.Size = UDim2.fromOffset(rowStateWidth, math.ceil(Theme.lineHeight(ROW_STATE_KIND)))
	end
	local switch: Frame = Create("Frame", {
		Name = "Switch",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(look.width, look.height),
		Active = false,
		Parent = holder,
	})
	-- The track: a "tint" surface (BackgroundColor3 is its top colour) with the border inside and the inner shade.
	local track = Theme.foam(switch, {
		radius = look.height,
		stroke = look.border,
		inner = true,
		mode = "tint",
		top = look.border + (look.trackShadePx or 0),
		colors = { face = OFF_FILL },
	})
	local knobSize = look.knob
	local knobBorder = look.knobBorder or 0
	local knob: Frame = Create("Frame", {
		Name = "Knob",
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(knobSize, knobSize),
		Active = false,
		ZIndex = 2,
		Parent = switch,
	})
	local knobBands = Layout.stickerBands(knobBorder, 0, look.knobBevelPx or 0, 0)
	Theme.foam(knob, {
		radius = knobSize,
		stroke = knobBorder,
		inner = true,
		top = knobBands.top,
		bevel = knobBands.bevel,
		drop = knobBands.drop,
		colors = { face = WHITE, bevel = WHITE:Lerp(BLACK, look.knobBevelAlpha or 0), drop = Theme.Colors.inkUI },
	})
	-- H:197: the small knob's drop, the ink at knobDropAlpha a few px lower, behind it.
	local knobDrop: Frame? = nil
	if look.knobDropPx then
		local made: Frame = Create("Frame", {
			Name = "KnobDrop",
			BackgroundColor3 = Theme.Colors.inkUI,
			BackgroundTransparency = 1 - (look.knobDropAlpha or 0),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(knobSize, knobSize),
			Active = false,
			ZIndex = 1,
			Parent = switch,
		})
		Theme.corner(knobSize, made)
		knobDrop = made
	end

	-- The knob's left edge (inside the border) and the track's top / end colours now; draw() writes them.
	local shownX = if value then look.knobOn else look.knobOff
	local shownFace, shownEnd = OFF_FILL, OFF_FILL
	local motion: Scheduler.Handle? = nil
	local function trackColors(on: boolean): (Color3, Color3)
		return if on then ON_TOP else OFF_FILL, if on then ON_END else OFF_FILL
	end
	local function draw(x: number, face: Color3, faceEnd: Color3)
		shownX, shownFace, shownEnd = x, face, faceEnd
		switch.BackgroundColor3 = face
		track:paint({
			face = face,
			faceEnd = faceEnd,
			top = face:Lerp(BLACK, look.trackShadeAlpha or 0),
		})
		local left = look.border + math.round(x)
		local y = look.border + look.knobTop
		knob.Position = UDim2.fromOffset(left, y)
		local drop = knobDrop
		if drop then
			drop.Position = UDim2.fromOffset(left, y + (look.knobDropPx or 0))
		end
	end
	local function stopMotion()
		local current = motion
		motion = nil
		if current then
			current:disconnect()
		end
	end
	cleanup:add(stopMotion)

	-- UI FINAL R2: `animate` slides the knob and eases the track from where they are (Toggle.motionAt).
	local function paint(animate: boolean?)
		stateLabel.Text = if value then ON_TEXT else OFF_TEXT
		stopMotion()
		local toX = if value then look.knobOn else look.knobOff
		local toFace, toEnd = trackColors(value)
		if not animate or Tweens.reducedMotion() then
			draw(toX, toFace, toEnd)
			return
		end
		local fromX, fromFace, fromEnd = shownX, shownFace, shownEnd
		local elapsed = 0
		motion = Scheduler.add(function(dt: number): boolean
			elapsed += dt
			local k, c, done = Toggle.motionAt(variant :: Variant, elapsed * 1000)
			draw(fromX + (toX - fromX) * k, fromFace:Lerp(toFace, c), fromEnd:Lerp(toEnd, c))
			if done then
				motion = nil
			end
			return not done
		end, "render")
	end

	-- UI FINAL R9: the row's face colours, brightened by the hover filter's mix (Button.hoverColor, H:637).
	local function paintRow(mix: number)
		local foam = rowFoam
		if foam == nil then
			return
		end
		local function lit(color: Color3): Color3
			return if mix > 0 then color:Lerp(Button.hoverColor(color), mix) else color
		end
		foam:paint({
			face = lit(Palette.StickerCardTop),
			faceEnd = lit(Palette.StickerCardBottom),
			top = lit(Palette.StickerCardTop:Lerp(WHITE, ROW_SURFACE.highlightAlpha)),
			drop = Theme.Colors.inkUI,
		}, "exact")
	end
	if row then
		paintRow(0)
		local feel: Button.DecorateOptions = {
			fx = "row", -- H:433, H:634: x +4
			visual = rowVisual,
			clickSound = false, -- the switch's own sound (below)
			pivotPx = ROW.lip / 2,
			onFilter = paintRow,
		}
		cleanup:add(Button.decorate(root, feel))
	end

	cleanup:add(root.Activated:Connect(function()
		value = not value
		paint(true)
		local pitch = if value then UI_PITCH.toggleOn else UI_PITCH.toggleOff
		local after = Toggle.soundAfterChange(value)
		if row and not after then
			Button.playSound(SOUND_CLICK, pitch)
		end
		local ok, err = pcall(function(): any
			spec.onChanged(value)
			return nil
		end)
		if not ok then
			log:error(`{spec.name} onChanged failed:`, err)
		end
		if row and after then
			Button.playSound(SOUND_CLICK, pitch)
		end
	end))

	paint()
	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: Toggle
	self.root = root
	self.visual = holder
	function self.setValue(_: Toggle, newValue: boolean)
		value = newValue == true
		paint()
	end
	function self.getValue(_: Toggle): boolean
		return value
	end
	function self.setText(_: Toggle, text: string)
		label.Text = text
	end
	function self.destroy(_: Toggle)
		cleanup:clean()
	end
	return self
end

return Toggle
