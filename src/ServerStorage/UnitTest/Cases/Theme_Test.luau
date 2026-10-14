--!strict
-- Theme_Test: the UI tokens and helpers of StarterPlayerScripts.Client.UI.Theme (and the UI tokens of
-- ReplicatedStorage.Shared.Art.Palette). Server only (ServerStorage.UnitTest). Edit mode: the instances are built
-- unparented and destroyed.
-- Contract (Candy UI, the UI overhaul of 2026-10-11, on top of the foam restyle of 2026-10-09):
--   * the Candy UI tokens have their hex values; the world tokens of §7.2 are untouched (Catalog_Test checks those);
--   * the Shop accent is at least 20° of hue from CoinGold, Exclusive and Danger and from every other tile accent; no
--     accent reuses a reserved gameplay colour;
--   * contrast >= 4.5:1: PlumInk on every light or saturated accent face and on the sticker face, white on a dark
--     accent face; the light text, the captions and the hints on the dark window; the captions on the disabled face;
--   * the outlined-text rule: white with a PlumInk Contextual UIStroke only for display kinds of >= 16 base px (its
--     thickness from outlinePx), PlumInk otherwise, white at every size on a dark face; textOnLight removes it;
--     headline kinds in the default (light) colour carry the outline;
--   * fonts: display kinds draw in Fredoka One, the others in Theme.BODY_FAMILY (Nunito lifts every weight one step);
--     textBounds always answers (an estimate when TextService cannot); the default text colour is Colors.text;
--   * Theme.panel keeps its Part 8 contract (a Frame, the caller's props, its first UIStroke the outline the caller may
--     recolour) with the Candy look: PanelBody, the PlumInk 3 px outline plus the SD_Rim inner rim, a vertical foam
--     UIGradient that only darkens, a bottom padding that clears the bands; Theme.foam "exact" paints over white and a
--     faceEnd fades the face; headerTab straddles the panel's top edge, makes room under it, is sized from its title
--     (no AutomaticSize) with a shine and a rim, and lights the header area; Theme.inset is a recessed field with no
--     outline; bubbles() keeps out of laid-out frames.
-- UI FINAL R1 (the look kit of the design "Squishy Duels UI FINAL" 2026-10-14, plan work/ui/PLAN.md R1) changes that
-- contract where they differ (the Candy UI tokens stay in Palette, unread by Theme):
--   * the Sticker UI tokens have the design's hex values; Theme maps them (the ink, the purple card, white text, the
--     pink-window text) and the accents keep their names on the design's hues (the Shop accent is the green, 127°);
--   * contrast >= 4.5:1 (plan §1.3): the ink outline on every accent face, the pink-window text on both window stops,
--     the soft text in the well, the ink on the cream sticker and on the disabled lilac;
--   * every kind is a display kind (Fredoka One) of at least 16 base px, so every kind may be outlined; light text
--     carries the ink outline (outlinePx: the design's text stroke halved; the game's 2 / 1.5 below 22 px), dark text
--     none; textOnWindow is dark; the outline fades with its text; noOutline takes it off for good;
--   * the panel is the purple card: one 4 px ink outline drawn inside, no rim; setSurface repaints a panel in exact
--     colours; foam paints a 3-stop face and the surfaces' highlight and bevel; the inset is the well with its 4 px ink
--     border drawn inside;
--   * stickerText mirrors a label into an ink drop and a face for a role with a drop; radial / rays fall back with no
--     picture uploaded.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

-- Candy UI tokens (Art/Palette).
local UI_HEX: { [string]: string } = {
	CandyCoral = "#FF5B91",
	CandyLavender = "#AB78FF",
	CandyCyan = "#36C9FF",
	CandyMint = "#47D7AE",
	CandyLime = "#8DEE42",
	CandyGold = "#FFD451",
	CandyRed = "#FF414F",
	PlumInk = "#251B32",
	PanelBody = "#30283E",
	PanelRaised = "#443951",
	WarmWhite = "#FFF8EE",
	TextMuted = "#C9BEDA",
	TextFaint = "#9D91B0",
}
-- The Sticker UI tokens (Art/Palette) and their design hex.
local STICKER_HEX: { [string]: string } = {
	StickerInk = "#1E1428",
	StickerInkDeep = "#120B1E",
	StickerSwitchOff = "#1A1229",
	StickerTrough = "#5130C7",
	StickerWell = "#5B36D9",
	StickerWindowTop = "#FFD6EC",
	StickerWindowBottom = "#FFAFD6",
	StickerCardTop = "#A385FF",
	StickerCardBottom = "#7A57F2",
	StickerPillTop = "#9775FF",
	StickerPillBottom = "#6C47F5",
	StickerToyTile = "#EFE6FF",
	StickerScrollThumb = "#5A4880",
	StickerScrimPurple = "#6E3CDC",
	StickerOnWindowText = "#8A2468",
	StickerCoinText = "#FFE36B",
	StickerTextSoft = "#F3EDFF",
	StickerTextMuted = "#EDE4FF",
	StickerTextChip = "#E9E1FA",
	StickerTabOff = "#D9CFF0",
	StickerTextGrey = "#C9BFD9",
	StickerCollected = "#FFE3EF",
	StickerBoxHeaderText = "#0B4B5E",
	StickerGreenTop = "#A6F796",
	StickerGreenMid = "#4CD45C",
	StickerGreenEnd = "#2FB447",
	StickerGreen2End = "#38C150",
	StickerToggleOnTop = "#9BF58A",
	StickerCyanTop = "#9DEFFA",
	StickerCyanMid = "#3CC6E2",
	StickerCyanEnd = "#1FA6C9",
	StickerGoldTop = "#FFE88A",
	StickerGoldMid = "#FFC23A",
	StickerGoldEnd = "#F59A12",
	StickerRedTop = "#FF8A9A",
	StickerRedEnd = "#E83A5A",
	StickerCloseTop = "#FF9A9A",
	StickerCloseEnd = "#F0344A",
	StickerCancelRedTop = "#FF8A8A",
	StickerYellowTop = "#FFF08A",
	StickerYellowEnd = "#FFB627",
	StickerMintTop = "#9AF5D2",
	StickerMintEnd = "#25B886",
	StickerDisabledTop = "#CBBDF2",
	StickerDisabledEnd = "#A996E0",
	StickerCancelTop = "#C4B4F0",
	StickerCancelEnd = "#9B86DB",
	StickerPinkTop = "#FFA6C8",
	StickerPinkMid = "#FF5D97",
	StickerPinkEnd = "#EE3B7B",
	StickerDuelBevel = "#961446",
	StickerFoundBevel = "#A05000",
	StickerBlueBarTop = "#8BEBFF",
	StickerBlueBarEnd = "#25AEE6",
	StickerPurpleBarTop = "#C9A8FF",
	StickerPurpleBarEnd = "#8A55EE",
	StickerGripTop = "#B5FBE0",
	StickerGripEnd = "#2FC48F",
	StickerVolumeTop = "#FFB1CB",
	StickerVolumeEnd = "#FF5C93",
	StickerUltTop = "#FFD79A",
	StickerUltText = "#4A2600",
	StickerThrowChip = "#4A3A6E",
}
local MIN_HUE_GAP_DEG = 20
local MIN_TEXT_CONTRAST = 4.5
local TILE_ACCENTS = { "strawberry", "lilac", "shop", "quests", "sky" }

-- WCAG 2 relative luminance and contrast ratio (as Catalog_Test).
local function channel(c: number): number
	return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(color: Color3): number
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end

local function contrast(a: Color3, b: Color3): number
	local la, lb = luminance(a), luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

-- Hue in degrees (0..360) and the shortest distance between two hues.
local function hue(color: Color3): number
	local h = color:ToHSV()
	return h * 360
end

local function hueGap(a: Color3, b: Color3): number
	local d = math.abs(hue(a) - hue(b)) % 360
	return if d > 180 then 360 - d else d
end

local function sameColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
end

local function hasColor(sequence: ColorSequence, color: Color3): boolean
	for _, point in sequence.Keypoints do
		if sameColor(point.Value, color) then
			return true
		end
	end
	return false
end

local function innerPosition(stroke: UIStroke): any
	local ok, value = pcall(function(): any
		return (stroke :: any).BorderStrokePosition
	end)
	return if ok then value else nil
end

local function strokes(object: Instance): { UIStroke }
	local list: { UIStroke } = {}
	for _, child in object:GetChildren() do
		if child:IsA("UIStroke") then
			table.insert(list, child)
		end
	end
	return list
end

return function(t: Context)
	local expect = t.expect
	local Palette = t.requireShared("Art/Palette")
	local RarityStyle = t.requireShared("Art/RarityStyle")
	local AssetTable = t.requireShared("AssetTable")
	local Config = t.requireShared("Config")
	local Theme = t.requireClient("UI/Theme")

	t.test("the Candy UI tokens have their values", function()
		for name, hex in UI_HEX do
			local color = Palette[name]
			if not (typeof(color) == "Color3" and sameColor(color, Color3.fromHex(hex))) then
				error(`Palette.{name} is {tostring(color)}, the overhaul says {hex}`)
			end
		end
		-- UI FINAL R1: Theme reads the Sticker tokens instead (the next case).
		expect.truthy(sameColor(Theme.Colors.inkUI, Palette.StickerInk))
		expect.truthy(sameColor(Theme.Colors.panel, Palette.StickerCardTop))
		expect.truthy(sameColor(Theme.Colors.text, Color3.new(1, 1, 1)))
		expect.truthy(sameColor(Theme.Accents.strawberry.face, Palette.StickerPinkMid))
		expect.truthy(sameColor(Theme.Accents.shop.face, Palette.StickerGreenMid))
		-- The world keeps its own Ink and Cream (nameplates, signs).
		expect.truthy(sameColor(Theme.Colors.ink, Palette.Ink))
		expect.truthy(sameColor(Theme.Colors.cream, Palette.Cream))
	end)

	t.test("the Sticker UI tokens have the design's values and Theme maps them", function()
		for name, hex in STICKER_HEX do
			local color = Palette[name]
			if not (typeof(color) == "Color3" and sameColor(color, Color3.fromHex(hex))) then
				error(`Palette.{name} is {tostring(color)}, the design says {hex}`)
			end
		end
		expect.truthy(sameColor(Theme.Colors.inkUI, Palette.StickerInk))
		expect.truthy(sameColor(Theme.Colors.panel, Palette.StickerCardTop))
		expect.truthy(sameColor(Theme.Colors.bevel, Palette.StickerCardBottom))
		expect.truthy(sameColor(Theme.Colors.biscuit, Palette.StickerWell))
		expect.truthy(sameColor(Theme.Colors.track, Palette.StickerTrough))
		expect.truthy(sameColor(Theme.Colors.text, Color3.new(1, 1, 1)))
		expect.truthy(sameColor(Theme.Colors.textOnWindow, Palette.StickerOnWindowText))
		expect.truthy(sameColor(Theme.Colors.backdrop, Palette.StickerScrimPurple))
		-- The accents keep their names on the design's hues; `face` is the mid stop of a 3-stop gradient, else the top.
		local strawberry = Theme.Accents.strawberry
		expect.truthy(sameColor(strawberry.top, Palette.StickerPinkTop))
		expect.truthy(sameColor(strawberry.face, Palette.StickerPinkMid))
		expect.truthy(sameColor(strawberry.shade, Palette.StickerPinkEnd))
		expect.near(strawberry.midAt, 0.55, 1e-9)
		expect.truthy(sameColor(Theme.Accents.shop.face, Palette.StickerGreenMid))
		expect.equal(Theme.Accents.green, Theme.Accents.shop)
		expect.equal(Theme.Accents.cyan, Theme.Accents.sky)
		expect.truthy(sameColor(Theme.Accents.lilac.face, Palette.StickerPurpleBarTop))
		expect.equal(Theme.Accents.lilac.mid, nil)
		expect.truthy(sameColor(Theme.Accents.red.top, Palette.StickerCloseTop))
		expect.truthy(Theme.Accents.frosting.light)
		for _, name in { "pink", "green", "cyan", "closeRed", "disabled", "cancel", "yellow", "ult" } do
			expect.truthy(Theme.Accents[name] ~= nil)
		end
		-- The cream sticker is the design's #FFF6EA, already Frosting (H:171); gold text is the coin yellow (H:79,
		-- H:369); the Ultimate's gold (H:234) carries the ink, so a ready Ultimate never reads as the disabled lilac.
		expect.truthy(sameColor(Theme.Colors.frosting, Palette.Frosting))
		expect.truthy(sameColor(Palette.Frosting, Color3.fromHex("#FFF6EA")))
		expect.truthy(sameColor(Theme.Colors.gold, Palette.StickerCoinText))
		expect.truthy(sameColor(Theme.Accents.ult.top, Palette.StickerUltTop))
		expect.truthy(sameColor(Theme.Accents.ult.shade, Palette.StickerGoldEnd))
		expect.truthy(Theme.Accents.ult.light)
		-- The world keeps its own Ink and Cream (nameplates, signs) and the light sticker's bevel (world plates).
		expect.truthy(sameColor(Theme.Colors.ink, Palette.Ink))
		expect.truthy(sameColor(Theme.Colors.cream, Palette.Cream))
		expect.truthy(sameColor(Theme.Colors.worldInk, Palette.InkUI))
		expect.truthy(sameColor(Theme.Colors.stickerBevel, Palette.StickerBevel))
	end)

	t.test("the Shop accent keeps 20° of hue from the coin, Exclusive, Danger and the other tiles", function()
		local shop = Theme.Accents.shop.face
		local reserved: { [string]: Color3 } = {
			CoinGold = Palette.CoinGold,
			Exclusive = RarityStyle.get("Exclusive").color,
			Danger = Palette.Danger,
		}
		for name, color in reserved do
			if hueGap(shop, color) < MIN_HUE_GAP_DEG then
				error(`the Shop accent is {hueGap(shop, color)}° from {name}`)
			end
		end
		for _, name in TILE_ACCENTS do
			if name ~= "shop" and hueGap(shop, Theme.Accents[name].face) < MIN_HUE_GAP_DEG then
				error(`the Shop accent is {hueGap(shop, Theme.Accents[name].face)}° from the {name} tile`)
			end
		end
		-- UI FINAL R1: the design's green #4CD45C (H:245): hue 127.1°, 84.1° from CoinGold.
		expect.near(hue(shop), 127.06, 0.2)
		expect.near(hueGap(shop, Palette.CoinGold), 84.07, 0.3)
	end)

	t.test("no accent reuses a reserved gameplay colour", function()
		for name, accent in Theme.Accents do
			for _, reservedName in Palette.RESERVED do
				local reserved = Palette[reservedName]
				if sameColor(accent.face, reserved) or sameColor(accent.shade, reserved) then
					error(`accent {name} uses the reserved colour {reservedName}`)
				end
			end
		end
	end)

	t.test("text contrast: PlumInk or white on every face, the light texts on the dark surfaces", function()
		for name, accent in Theme.Accents do
			local ink = if accent.dark then Theme.Colors.white else Theme.Colors.inkUI
			local ratio = contrast(ink, accent.face)
			if ratio < MIN_TEXT_CONTRAST then
				error(`the text on the {name} accent is {ratio}:1`)
			end
			expect.equal(Theme.isDarkFace(accent.face), accent.dark == true)
		end
		expect.truthy(contrast(Theme.Colors.inkUI, Theme.Colors.frosting) >= MIN_TEXT_CONTRAST) -- stickers, keycaps
		-- UI FINAL R1 (plan §1.3): text on the purple cards is outlined (the ink against the card); the pink window's
		-- text on both stops; the soft text in the well; the outline of the disabled label and reason on the lilac.
		for _, surface in { Theme.Colors.panel, Theme.Colors.panelAlt } do
			expect.truthy(contrast(Theme.Colors.inkUI, surface) >= MIN_TEXT_CONTRAST)
		end
		for _, stop in { Palette.StickerWindowTop, Palette.StickerWindowBottom } do
			expect.truthy(contrast(Theme.Colors.textOnWindow, stop) >= MIN_TEXT_CONTRAST)
		end
		expect.truthy(contrast(Theme.Colors.textFaint, Theme.Colors.biscuit) >= MIN_TEXT_CONTRAST)
		expect.truthy(contrast(Theme.Colors.inkUI, Theme.Colors.disabledFace) >= MIN_TEXT_CONTRAST)
	end)

	t.test("the outlined-text rule: only display kinds of 16 base px or more", function()
		for kind, size in Config.UI.TextSize do
			local expected = Theme.isDisplay(kind) and size >= Theme.OUTLINE_MIN_BASE_PX
			expect.equal(Theme.outlineAllowed(kind), expected)
		end
		expect.truthy(Theme.outlineAllowed("Button"))
		expect.truthy(Theme.outlineAllowed("H2"))
		expect.truthy(Theme.outlineAllowed("Chip"))
		expect.truthy(Theme.outlineAllowed("Body")) -- UI FINAL R1: every kind is a display kind of >= 16 base px
		expect.falsy(Theme.outlineAllowed("NoSuchKind"))
		expect.equal(Theme.outlinePx("Title"), 3)
		expect.equal(Theme.outlinePx("H2"), 2.5)
		expect.equal(Theme.outlinePx("Button"), 2)
		expect.equal(Theme.outlinePx("Chip"), 1.5)
		-- UI FINAL R1: below 22 px the game's own steps (2 from 18, else 1.5: plan §1.3, the Studio-tuned small text).
		expect.equal(Theme.outlinePx("Body"), 2)
		expect.equal(Theme.outlinePx("Small"), 1.5)
		for kind in Config.UI.TextSize do
			expect.truthy(Theme.isDisplay(kind))
		end
		expect.equal(Theme.outlinePx("Big"), 2.5) -- H:370
		expect.equal(Theme.outlinePx("HudNumber"), 3) -- H:246
		expect.equal(Theme.outlinePx("Name"), 3.5) -- H:227
		expect.equal(Theme.outlinePx("Duel"), 4) -- H:130
		expect.equal(Theme.outlinePx("Window"), 4.5) -- H:184
		expect.equal(Theme.outlinePx("Reveal"), 5) -- H:490
		expect.equal(Theme.outlinePx("Congrats"), 6.5) -- H:539
	end)

	t.test(
		"textOnColor outlines display text and keeps body text PlumInk (white on a dark face); textOnLight removes it",
		function()
			local big = Theme.label({ Name = "Big", Text = "DUEL" }, "Button")
			expect.truthy(Theme.textOnColor(big))
			expect.truthy(sameColor(big.TextColor3, Color3.new(1, 1, 1)))
			local found = big:FindFirstChild("SD_Outline")
			expect.truthy(found ~= nil and found:IsA("UIStroke"))
			local outline = found :: UIStroke
			expect.truthy(outline.Enabled)
			expect.equal(outline.ApplyStrokeMode, Enum.ApplyStrokeMode.Contextual)
			expect.equal(outline.Thickness, Theme.outlinePx("Button"))
			expect.truthy(sameColor(outline.Color, Theme.Colors.inkUI))
			Theme.textOnLight(big)
			expect.falsy(outline.Enabled)
			expect.truthy(sameColor(big.TextColor3, Theme.Colors.inkUI))
			-- Calling it again reuses the one outline.
			Theme.textOnColor(big)
			expect.equal(#strokes(big), 1)
			big:Destroy()

			local chip = Theme.label({ Name = "Chip", Text = "Squishies" }, "Chip")
			expect.truthy(Theme.textOnColor(chip))
			expect.equal((chip:FindFirstChild("SD_Outline") :: UIStroke).Thickness, 1.5)
			chip:Destroy()

			local small = Theme.label({ Name = "Small", Text = "Squishies" }, "Small")
			-- UI FINAL R1: every kind is outlined white on an accent, a Small label too.
			expect.truthy(Theme.textOnColor(small))
			expect.truthy(sameColor(small.TextColor3, Color3.new(1, 1, 1)))
			expect.equal((small:FindFirstChild("SD_Outline") :: UIStroke).Thickness, 1.5)
			-- On a dark face body text turns white.
			Theme.textOnColor(small, nil, Theme.Accents.plum.face)
			expect.truthy(sameColor(small.TextColor3, Color3.new(1, 1, 1)))
			-- textOnAccent: the ink on the light accent (the cream sticker), white outlined on gold (H:498).
			Theme.textOnAccent(small, "frosting")
			expect.truthy(sameColor(small.TextColor3, Theme.Colors.inkUI))
			expect.truthy(Theme.textOnAccent(small, "gold"))
			expect.truthy(sameColor(small.TextColor3, Color3.new(1, 1, 1)))
			-- A light colour given to textOnLight keeps the outline; textOnWindow is dark with none.
			Theme.textOnLight(small, Theme.Colors.ink2)
			expect.truthy((small:FindFirstChild("SD_Outline") :: UIStroke).Enabled)
			Theme.textOnWindow(small)
			expect.truthy(sameColor(small.TextColor3, Palette.StickerOnWindowText))
			expect.falsy((small:FindFirstChild("SD_Outline") :: UIStroke).Enabled)
			small:Destroy()
			-- An unknown kind stays the ink.
			local odd = Instance.new("TextLabel")
			expect.falsy(Theme.textOnColor(odd, "NoSuchKind" :: any))
			expect.truthy(sameColor(odd.TextColor3, Theme.Colors.inkUI))
			odd:Destroy()
		end
	)

	t.test("fonts: display kinds in Fredoka One, body kinds in the body family; headlines outlined", function()
		local fredoka = Font.fromEnum(Enum.Font.FredokaOne)
		for _, kind in { "Title", "H2", "HudNumber", "Countdown", "Button", "Chip" } do
			expect.equal(Theme.font(kind).Family, fredoka.Family)
		end
		-- UI FINAL R1: every kind draws in Fredoka One (H:14, H:19), whatever the weight.
		for kind in Config.UI.TextSize do
			expect.equal(Theme.font(kind).Family, fredoka.Family)
		end
		expect.equal(Theme.font("Small", Enum.FontWeight.Bold).Family, fredoka.Family)
		-- The default text colour is the light text of the dark surfaces; a headline in it carries the outline.
		local label = Theme.label({ Name = "Body", Text = "x" }, "Body")
		expect.truthy(sameColor(label.TextColor3, Theme.Colors.text))
		-- UI FINAL R1: every kind does (white text), at its kind's thickness.
		local bodyOutline = label:FindFirstChild("SD_Outline") :: UIStroke
		expect.truthy(bodyOutline and bodyOutline.Enabled)
		expect.equal(bodyOutline.Thickness, Theme.outlinePx("Body"))
		label:Destroy()
		local title = Theme.label({ Name = "Title", Text = "x" }, "Title")
		local outline = title:FindFirstChild("SD_Outline") :: UIStroke
		expect.truthy(outline and outline.Enabled)
		expect.equal(outline.Thickness, 3)
		-- A given colour has no outline.
		Theme.text(title, "Title", nil, Theme.Colors.inkUI)
		expect.falsy(outline.Enabled)
		-- UI FINAL R1: that is a dark colour; a light caption colour keeps it.
		Theme.text(title, "Title", nil, Theme.Colors.ink2)
		expect.truthy(outline.Enabled)
		title:Destroy()
	end)

	-- Polish item 20 (2026-10-10): on the first run after a Studio restart the fonts load inside the first measures,
	-- which could pass the 5 s case limit. The text measure is warmed once per kind here, while the cases are built
	-- (RunUnitTest gives the build no limit), with a text of its own, so the case still measures fresh texts.
	for _, kind in { "Body", "Small", "Button", "Chip", "Title" } do
		pcall(Theme.textBounds, "Warm-up", kind)
	end

	t.test("textBounds always answers with a size that grows with the text", function()
		for _, kind in { "Body", "Small", "Button", "Chip", "Title" } do
			local short = Theme.textBounds("Hi", kind)
			local long = Theme.textBounds("Hello there, squishy friend", kind)
			expect.truthy(short.X > 0 and short.Y > 0)
			expect.truthy(long.X > short.X)
			-- Wrapped inside a narrow width it takes more lines.
			local wrapped = Theme.textBounds("Hello there, squishy friend", kind, nil, 60)
			expect.truthy(wrapped.Y > short.Y)
		end
		expect.truthy(Theme.lineHeight("Body") > 0)
		-- UI FINAL R1: one font, so a body text measures as a display text of the same size.
		expect.equal(Theme.textBounds("Squishies", "Small"), Theme.textBounds("Squishies", "Chip"))
	end)

	t.test("panel: the purple card, one inner ink outline (no rim) and room for the lip", function()
		local holder = Instance.new("Folder")
		local panel = Theme.panel({ Name = "Card", Size = UDim2.fromOffset(200, 100), Parent = holder }, nil, 6)
		expect.equal(panel.Parent, holder)
		expect.equal(panel.Name, "Card")
		expect.truthy(sameColor(panel.BackgroundColor3, Theme.Colors.panel))
		expect.equal(panel.BackgroundTransparency, 0)
		-- UI FINAL R1: one ink outline, 4 px, drawn inside (the design's border-box border, H:203); no Candy rim.
		local list = strokes(panel)
		expect.equal(#list, 1)
		local stroke = panel:FindFirstChildOfClass("UIStroke") :: UIStroke
		expect.truthy(sameColor(stroke.Color, Theme.Colors.inkUI))
		expect.equal(stroke.Thickness, Theme.Sticker.border.normal)
		local position = innerPosition(stroke)
		if position ~= nil then
			expect.equal(position, Enum.BorderStrokePosition.Inner)
		end
		expect.truthy(sameColor(panel.BackgroundColor3, Palette.StickerCardTop))
		local foundGradient = panel:FindFirstChild("SD_Foam")
		expect.truthy(foundGradient ~= nil and foundGradient:IsA("UIGradient"))
		local gradient = foundGradient :: UIGradient
		expect.equal(gradient.Rotation, 90)
		local pad = panel:FindFirstChildOfClass("UIPadding") :: UIPadding
		local bands = Theme.Foam.panel
		expect.equal(pad.PaddingTop.Offset, 6)
		expect.truthy(pad.PaddingBottom.Offset >= 6 and pad.PaddingBottom.Offset > bands.bevel + bands.drop)
		-- A "tint" panel: the gradient only darkens (every stop <= 1), so a caller's colour shows as the face, and the
		-- drawn bottom band is the PlumInk drop.
		local keypoints = gradient.Color.Keypoints
		expect.truthy(sameColor(keypoints[1].Value, Color3.new(1, 1, 1)))
		for _, point in keypoints do
			expect.truthy(point.Value.R <= 1 and point.Value.G <= 1 and point.Value.B <= 1)
		end
		local last = keypoints[#keypoints].Value
		local face = Theme.Colors.panel
		expect.truthy(sameColor(Color3.new(face.R * last.R, face.G * last.G, face.B * last.B), Theme.Colors.inkUI))
		-- A medium padding already clears the bands and stays as it was.
		local roomy = Theme.panel({}, nil, Theme.Padding.medium)
		expect.equal((roomy:FindFirstChildOfClass("UIPadding") :: UIPadding).PaddingBottom.Offset, 12)
		roomy:Destroy()
		holder:Destroy()
	end)

	t.test("foam exact: paints the given colours over white and repaints; faceEnd fades the face", function()
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(100, 56)
		local accent = Theme.Accents.strawberry
		local foam =
			Theme.foam(frame, { top = 2, bevel = 5, drop = 3, colors = Theme.accentColors("strawberry", true) })
		expect.truthy(sameColor(frame.BackgroundColor3, Color3.new(1, 1, 1)))
		local points = foam.gradient.Color.Keypoints
		local primary = Theme.Sticker.surfaces.primary -- UI FINAL R1: the design's highlight (H:245)
		expect.truthy(sameColor(points[1].Value, accent.top:Lerp(Color3.new(1, 1, 1), primary.highlightAlpha)))
		expect.truthy(sameColor(points[#points].Value, Theme.Colors.inkUI))
		local hasShade = false
		for _, point in points do
			hasShade = hasShade or sameColor(point.Value, accent.shade)
		end
		expect.truthy(hasShade)
		foam:paint(Theme.accentColors("sky"))
		points = foam.gradient.Color.Keypoints
		expect.truthy(sameColor(points[1].Value, Theme.Accents.sky.top))
		-- faceEnd: the face band starts at `face` and ends at `faceEnd` (no other band).
		local fade = Theme.foamSequence(100, { top = 0, bevel = 0, drop = 0 }, {
			face = Color3.new(1, 0, 0),
			faceEnd = Color3.new(0, 0, 1),
		})
		expect.truthy(sameColor(fade.Keypoints[1].Value, Color3.new(1, 0, 0)))
		expect.truthy(sameColor(fade.Keypoints[#fade.Keypoints].Value, Color3.new(0, 0, 1)))
		frame:Destroy()
	end)

	t.test("headerTab: a jelly plate on the panel's top edge, sized from its title, lighting the header", function()
		local panel = Theme.panel({ Name = "Quests", Size = UDim2.fromOffset(400, 300) }, Theme.Radius.panel, 12)
		local tab, label = Theme.headerTab(panel, "Quests")
		expect.equal(tab.Parent, panel)
		expect.equal(tab.Name, "HeaderTab")
		expect.equal(label.Text, "Quests")
		local pad = panel:FindFirstChildOfClass("UIPadding") :: UIPadding
		expect.truthy(pad.PaddingTop.Offset > 12) -- room for the tab's lower half
		expect.equal(tab.Position.Y.Offset, -pad.PaddingTop.Offset) -- centred on the panel's top edge
		expect.equal(tab.AnchorPoint, Vector2.new(0.5, 0.5))
		expect.truthy(sameColor(label.TextColor3, Color3.new(1, 1, 1))) -- H2 on Coral: outlined white
		-- Sized from the title (an overlay inside an automatically sized plate would inflate it).
		expect.equal(tab.AutomaticSize, Enum.AutomaticSize.None)
		expect.truthy(tab.Size.X.Offset >= Theme.textWidth("Quests", "H2"))
		local narrow = tab.Size.X.Offset
		label.Text = "A much longer title"
		task.wait() -- property signals are deferred: the plate fits itself on the next resumption
		expect.truthy(tab.Size.X.Offset > narrow)
		expect.truthy(tab:FindFirstChild("SD_Shine") ~= nil)
		expect.truthy(tab:FindFirstChild("SD_Rim") ~= nil)
		local glow = panel:FindFirstChild("SD_HeaderGlow") :: Frame
		expect.truthy(glow)
		expect.equal(glow.Size.Y.Offset > pad.PaddingTop.Offset, true)
		panel:Destroy()
	end)

	t.test("inset: the well, a recessed field with its 4 px ink border drawn inside (H:236)", function()
		local field = Theme.inset({ Name = "Stats" })
		expect.truthy(sameColor(field.BackgroundColor3, Theme.Colors.biscuit))
		local list = strokes(field)
		expect.equal(#list, 1)
		expect.truthy(sameColor(list[1].Color, Theme.Colors.inkUI))
		expect.equal(list[1].Thickness, Theme.Sticker.border.normal)
		local position = innerPosition(list[1])
		if position ~= nil then
			expect.equal(position, Enum.BorderStrokePosition.Inner)
		end
		expect.truthy(field:FindFirstChild("SD_Foam") ~= nil)
		field:Destroy()
	end)

	t.test("the outline fades with its text; noOutline leaves a label's own outline the only one", function()
		local label = Theme.label({ Name = "Float", Text = "+5" }, "HudNumber", nil, Palette.StickerMintTop)
		local found = label:FindFirstChild("SD_Outline") :: UIStroke?
		expect.truthy(found ~= nil and found.Enabled)
		local outline = found :: UIStroke
		label.TextTransparency = 1
		task.wait() -- property signals are deferred
		expect.equal(outline.Transparency, 1)
		label.TextTransparency = 0.25
		task.wait()
		expect.near(outline.Transparency, 0.25, 1e-6)
		-- A label that draws (and fades) its own outline: Theme's goes and never comes back.
		Theme.noOutline(label)
		local own = Theme.stroke(Theme.Colors.inkUI, 1.5, label)
		own.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		expect.equal(label:FindFirstChild("SD_Outline"), nil)
		Theme.text(label, "HudNumber", nil, Color3.new(1, 1, 1))
		Theme.textOnColor(label)
		expect.equal(#strokes(label), 1)
		expect.equal(label:FindFirstChildOfClass("UIStroke"), own)
		label:Destroy()
	end)

	t.test("rim, shine and bubbles: one each, out of the way of layouts", function()
		local frame = Instance.new("Frame")
		local outline = Theme.stroke(Theme.Colors.inkUI, 3, frame)
		local rim = Theme.rim(frame)
		expect.equal(Theme.rim(frame), rim) -- reused
		expect.equal(frame:FindFirstChildOfClass("UIStroke"), outline)
		local shine = Theme.shine(frame, 12)
		expect.equal(Theme.shine(frame, 12), shine)
		expect.falsy(shine.Active)
		local bubbles = Theme.bubbles(frame)
		expect.truthy(bubbles ~= nil and (bubbles :: Frame).ZIndex == 0)
		frame:Destroy()
		local listed = Instance.new("Frame")
		Instance.new("UIListLayout").Parent = listed
		expect.equal(Theme.bubbles(listed), nil) -- would become a list item
		listed:Destroy()
	end)

	t.test("setSurface repaints a panel in exact colours, and nothing else", function()
		local panel = Theme.panel({ Name = "Day", Size = UDim2.fromOffset(120, 160) })
		local red, blue = Color3.new(1, 0, 0), Color3.new(0, 0, 1)
		expect.truthy(Theme.setSurface(panel, { face = red, faceEnd = blue, drop = Theme.Colors.inkUI }))
		expect.truthy(sameColor(panel.BackgroundColor3, Color3.new(1, 1, 1))) -- exact: the colours are the gradient's
		local gradient = panel:FindFirstChild("SD_Foam") :: UIGradient
		expect.truthy(sameColor(gradient.Color.Keypoints[1].Value, red))
		expect.truthy(hasColor(gradient.Color, blue))
		expect.truthy(sameColor(gradient.Color.Keypoints[#gradient.Color.Keypoints].Value, Theme.Colors.inkUI))
		panel:Destroy()
		local plain = Instance.new("Frame")
		expect.falsy(Theme.setSurface(plain, { face = red }))
		plain:Destroy()
	end)

	t.test(
		"foam: exact paints a 3-stop face with its highlight, bevel and ink drop; inner outlines; faceEnd",
		function()
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromOffset(100, 65)
			local green = Theme.Accents.shop
			local primary = Theme.Sticker.surfaces.primary
			local foam = Theme.foam(frame, {
				stroke = 4,
				inner = true,
				top = 7,
				bevel = 6,
				drop = 9,
				colors = Theme.accentColors("shop", true),
			})
			expect.truthy(sameColor(frame.BackgroundColor3, Color3.new(1, 1, 1)))
			local position = innerPosition(foam.stroke :: UIStroke)
			if position ~= nil then
				expect.equal(position, Enum.BorderStrokePosition.Inner)
			end
			local sequence = foam.gradient.Color
			local points = sequence.Keypoints
			expect.truthy(sameColor(points[1].Value, green.top:Lerp(Color3.new(1, 1, 1), primary.highlightAlpha)))
			expect.truthy(sameColor(points[#points].Value, Theme.Colors.inkUI))
			expect.truthy(hasColor(sequence, green.mid :: Color3)) -- the mid stop
			expect.truthy(hasColor(sequence, green.shade:Lerp(Color3.new(0, 0, 0), primary.bevelAlpha :: number)))
			foam:paint(Theme.accentColors("sky"))
			points = foam.gradient.Color.Keypoints
			expect.truthy(sameColor(points[1].Value, Theme.Accents.sky.top))
			-- The DUEL surface's bevel takes its tint (H:126).
			local duel = Theme.accentColors("strawberry", true, "duel")
			local look = Theme.Sticker.surfaces.duel
			expect.truthy(
				sameColor(
					duel.bevel :: Color3,
					Theme.Accents.strawberry.shade:Lerp(Palette.StickerDuelBevel, look.bevelAlpha :: number)
				)
			)
			-- A 3-stop face with no bands: face at 0, mid at midAt, faceEnd at 1.
			local three = Theme.foamSequence(100, { top = 0, bevel = 0, drop = 0 }, {
				face = Color3.new(1, 0, 0),
				mid = Color3.new(0, 1, 0),
				midAt = 0.55,
				faceEnd = Color3.new(0, 0, 1),
			})
			expect.equal(#three.Keypoints, 3)
			expect.near(three.Keypoints[2].Time, 0.55, 1e-4)
			expect.truthy(sameColor(three.Keypoints[2].Value, Color3.new(0, 1, 0)))
			-- faceEnd: the face band starts at `face` and ends at `faceEnd` (no other band).
			local fade = Theme.foamSequence(100, { top = 0, bevel = 0, drop = 0 }, {
				face = Color3.new(1, 0, 0),
				faceEnd = Color3.new(0, 0, 1),
			})
			expect.truthy(sameColor(fade.Keypoints[1].Value, Color3.new(1, 0, 0)))
			expect.truthy(sameColor(fade.Keypoints[#fade.Keypoints].Value, Color3.new(0, 0, 1)))
			frame:Destroy()
		end
	)

	t.test("stickerText: a role with a drop mirrors the label into an ink drop and a face that follow it", function()
		local role = Theme.Sticker.text.duel
		local label = Instance.new("TextLabel")
		label.Text = "DUEL"
		expect.equal(Theme.stickerText(label, "duel"), label)
		expect.equal(label:GetAttribute("SD_TextKind"), role.kind)
		expect.equal(label.TextSize, Theme.textSize(role.kind))
		expect.equal(label.MaxVisibleGraphemes, 0) -- the label's own glyphs are hidden
		local drop = label:FindFirstChild("SD_Drop") :: TextLabel
		local face = label:FindFirstChild("SD_Face") :: TextLabel
		expect.truthy(label:FindFirstChild("SD_Drop") ~= nil and label:FindFirstChild("SD_Face") ~= nil)
		expect.equal(face.Text, "DUEL")
		expect.equal(drop.Text, "DUEL")
		expect.equal(face.TextSize, label.TextSize)
		expect.equal(drop.Position.Y.Offset, role.drop)
		expect.equal(face.Position.Y.Offset, 0)
		expect.truthy(face.ZIndex > drop.ZIndex)
		expect.truthy(sameColor(face.TextColor3, label.TextColor3))
		expect.truthy(sameColor(drop.TextColor3, Theme.Colors.inkUI))
		local faceOutline = face:FindFirstChild("SD_Outline") :: UIStroke
		expect.truthy(faceOutline and faceOutline.Enabled)
		expect.equal(faceOutline.Thickness, role.stroke / 2)
		expect.equal((label:FindFirstChild("SD_Outline") :: UIStroke).Thickness, role.stroke / 2)
		-- The label stays the source of truth: its text, colour and transparency reach both copies.
		label.Text = "FIGHT"
		label.TextColor3 = Color3.new(1, 0, 0)
		label.TextTransparency = 0.5
		task.wait() -- property signals are deferred
		expect.equal(face.Text, "FIGHT")
		expect.equal(drop.Text, "FIGHT")
		expect.truthy(sameColor(face.TextColor3, Color3.new(1, 0, 0)))
		expect.truthy(sameColor(drop.TextColor3, Theme.Colors.inkUI))
		expect.equal(face.TextTransparency, 0.5)
		expect.equal(drop.TextTransparency, 0.5)
		-- Styled again: still one copy of each.
		Theme.stickerText(label, "duel")
		local faces = 0
		for _, child in label:GetChildren() do
			if child.Name == "SD_Face" then
				faces += 1
			end
		end
		expect.equal(faces, 1)
		label:Destroy()

		-- A role without a drop: the label keeps its glyphs, outlined at half the role's stroke.
		local plain = Instance.new("TextLabel")
		Theme.stickerText(plain, "button")
		expect.equal(plain.MaxVisibleGraphemes, -1)
		expect.equal(plain:FindFirstChild("SD_Face"), nil)
		expect.equal((plain:FindFirstChild("SD_Outline") :: UIStroke).Thickness, Theme.Sticker.text.button.stroke / 2)
		-- A role's colour: the coin number in the coin yellow (H:79).
		Theme.stickerText(plain, "coin")
		expect.truthy(sameColor(plain.TextColor3, Palette.StickerCoinText))
		-- An unknown role leaves the label as it was.
		plain.Text = "x"
		expect.equal(Theme.stickerText(plain, "noSuchRole"), plain)
		expect.truthy(sameColor(plain.TextColor3, Palette.StickerCoinText))
		plain:Destroy()
	end)

	t.test("every text role names a TextSize kind and, when it has one, a Palette colour", function()
		for name, role in Theme.Sticker.text do
			if type(Config.UI.TextSize[role.kind]) ~= "number" then
				error(`text role {name}: {role.kind} is not a TextSize kind`)
			end
			if role.color ~= nil and typeof(Palette[role.color]) ~= "Color3" then
				error(`text role {name}: Palette.{role.color} is not a colour`)
			end
		end
	end)

	t.test("radial and rays: with no picture uploaded, a vertical gradient of the stops and no rays", function()
		local frame = Instance.new("Frame")
		local white, red, blue = Color3.new(1, 1, 1), Color3.new(1, 0, 0), Color3.new(0, 0, 1)
		local made = Theme.radial(frame, white, blue, red, 0.55)
		if AssetTable.image("img.fx.glow") == nil then
			expect.truthy(made:IsA("UIGradient"))
			local gradient = made :: UIGradient
			expect.equal(gradient.Name, "SD_Radial")
			expect.equal(gradient.Rotation, 90)
			local points = gradient.Color.Keypoints
			expect.equal(#points, 3)
			expect.truthy(sameColor(points[1].Value, white))
			expect.near(points[2].Time, 0.55, 1e-4)
			expect.truthy(sameColor(points[2].Value, red))
			expect.truthy(sameColor(points[3].Value, blue))
			expect.truthy(sameColor(frame.BackgroundColor3, white))
			expect.equal(frame:FindFirstChild("SD_Glow"), nil)
			-- Again: the same gradient.
			expect.equal(Theme.radial(frame, white, blue), made)
		end
		if AssetTable.image("img.fx.rays") == nil then
			expect.equal(Theme.rays(frame, "img.fx.rays", 520, 0.28, 18), nil)
			expect.equal(frame:FindFirstChild("SD_Rays"), nil)
		end
		frame:Destroy()
	end)
end
