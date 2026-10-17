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
-- UI FINAL R2 (plan work/ui/PLAN.md R2: P3, P4, T1, T2, T5):
--   * radial(frame, key, fallback): the exact picture when `key` has an id (SD_Radial, the frame's own background
--     clear); else the outer colour at its alpha and the img.fx.glow picture tinted the inner colour at its alpha,
--     centred at `centre`, with the mid ring (SD_GlowMid) of a 3-stop radial; reused when called again;
--   * rays(..., centreY): placed at centreY of the parent; nil while the picture has no id;
--   * a text role with `soft` (the toast's H:175) mirrors a soft drop: the ink at its alpha of the label's opacity,
--     no outline on it; softShadow puts SD_SoftShadow (ZIndex 0) under the target, the 9-slice picture or the
--     tinted glow.
-- UI FINAL R3 (the window frame, plan work/ui/PLAN.md R3; Config.UI.Sticker.window):
--   * window(props, kind, padding): the pink body with one 5 px inner ink border, radius 32, the ink lip under the
--     face (the bottom padding is the padding plus the lip), Active; the Squishies window's inner ring (H:182);
--   * headerTab on a window: the band (H:183-184) across its top inside the border, its face and dots in a clip
--     holder with 27 px corners, the kind's gradient with its highlight and bevel, the title in capitals in its role
--     from the band's padding, the extra at its right end, the sticker (H:251) at its spot with its drop shadow;
--     fitWindow scales the band, the paddings, the title (never under 16 base px) and the sticker with the chrome
--     scale and sets the window's top padding; attachClose puts the X at (right -22, top -22) (H:252); every kind
--     names Palette colours and a picture slot; headerTab on a panel stays the tab without the Candy shine and
--     glow; shine and bubbles are gone;
--   * scrim: a clear, unselectable, full-screen TextButton with the radial picture or its fallback (H:178);
--     scrollbar: 12 px, the design's thumb colour (H:22); windowShadow: the window's soft shadow (H:182).

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
	-- UI FINAL R3 (the window frame).
	StickerHeaderPinkEnd = "#FF4F8E",
	StickerHeaderCyanTop = "#8FF1F8",
	StickerHeaderCyanEnd = "#1FB2D2",
	StickerHeaderGoldTop = "#FFE97A",
	StickerHeaderGoldEnd = "#FFA41C",
	StickerHeaderMintEnd = "#22B383",
	StickerHeaderPurpleTop = "#CDB2FF",
	StickerHeaderPurpleEnd = "#8052EE",
	StickerHeaderLilacTop = "#C9B6FF",
	StickerHeaderLilacEnd = "#8B63FF",
	StickerScrimPink = "#FF96D2",
	StickerStickerShadow = "#140A1E",
	StickerShadowWindow = "#0F0819",
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
	-- UI FINAL R2: the idle loops (Anim/UiIdle: the shine strips, the rays) run on a private Scheduler here, so no
	-- frame event is connected (as Scheduler_Test).
	t.requireClient("Anim/UiIdle").setScheduler(t.requireClient("Anim/Scheduler").new(false))

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

	t.test(
		"headerTab on a panel: a plate on its top edge, sized from its title (UI FINAL R3: no shine, no glow)",
		function()
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
			expect.truthy(tab:FindFirstChild("SD_Rim") ~= nil)
			-- UI FINAL R3: the Candy shine stripes and header glow went with the design's window frame.
			expect.equal(tab:FindFirstChild("SD_Shine"), nil)
			expect.equal(panel:FindFirstChild("SD_HeaderGlow"), nil)
			expect.falsy(Theme.isWindow(panel))
			panel:Destroy()
		end
	)

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

	t.test("rim: one, after the outline (UI FINAL R3: the Candy shine and bubbles are gone)", function()
		local frame = Instance.new("Frame")
		local outline = Theme.stroke(Theme.Colors.inkUI, 3, frame)
		local rim = Theme.rim(frame)
		expect.equal(Theme.rim(frame), rim) -- reused
		expect.equal(frame:FindFirstChildOfClass("UIStroke"), outline)
		frame:Destroy()
		local theme = Theme :: any
		expect.equal(theme.shine, nil)
		expect.equal(theme.bubbles, nil)
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

	t.test("radial (P3): the picture with its id, else the outer colour at its alpha and the tinted glows", function()
		local white, red, blue = Color3.new(1, 1, 1), Color3.new(1, 0, 0), Color3.new(0, 0, 1)
		local key = "img.fx.radial.coinGlow"
		local fallback = {
			inner = white,
			outer = blue,
			mid = red,
			midAt = 0.3,
			innerAlpha = 0.8,
			outerAlpha = 0.5,
			centre = Vector2.new(0.5, 0.38),
		}
		local frame = Instance.new("Frame")
		local made = Theme.radial(frame, key, fallback)
		if AssetTable.image(key) then
			-- The exact picture over the frame, whose own background goes clear.
			local picture = made :: ImageLabel
			expect.equal(picture.Name, "SD_Radial")
			expect.equal(picture.ScaleType, Enum.ScaleType.Stretch)
			expect.equal(picture.Image, AssetTable.image(key))
			expect.equal(frame.BackgroundTransparency, 1)
		else
			expect.truthy(sameColor(frame.BackgroundColor3, blue))
			expect.near(frame.BackgroundTransparency, 0.5, 1e-4)
			if AssetTable.image("img.fx.glow") then
				local inner = made :: ImageLabel
				expect.equal(inner.Name, "SD_Glow")
				expect.truthy(sameColor(inner.ImageColor3, white))
				expect.near(inner.ImageTransparency, 0.2, 1e-4)
				expect.equal(inner.Position, UDim2.fromScale(0.5, 0.38))
				expect.near(inner.Size.X.Scale, 0.6, 1e-4) -- the inner glow reaches the mid stop (midAt of the radius)
				local ring = frame:FindFirstChild("SD_GlowMid") :: ImageLabel
				expect.truthy(frame:FindFirstChild("SD_GlowMid") ~= nil)
				expect.truthy(sameColor(ring.ImageColor3, red))
				expect.near(ring.ImageTransparency, 0.2, 1e-4) -- midAlpha defaults to innerAlpha
				expect.equal(ring.Position, UDim2.fromScale(0.5, 0.38))
				expect.equal(Theme.radial(frame, key, fallback), made) -- reused, not rebuilt
			else
				expect.equal(made, nil) -- neither picture: the outer colour alone
			end
		end
		frame:Destroy()
	end)

	t.test("rays (P4): at centreY of the parent; nil while the picture has no id", function()
		local frame = Instance.new("Frame")
		local rays = Theme.rays(frame, "img.fx.rays", 520, 0.28, 18, 0.6)
		if AssetTable.image("img.fx.rays") then
			local made = rays :: ImageLabel
			expect.equal(made.Name, "SD_Rays")
			expect.equal(made.Position, UDim2.fromScale(0.5, 0.6)) -- H:219: 60%
			expect.equal(made.Size, UDim2.fromOffset(520, 520))
			expect.near(made.ImageTransparency, 0.72, 1e-4)
		else
			expect.equal(rays, nil)
			expect.equal(frame:FindFirstChild("SD_Rays"), nil)
		end
		frame:Destroy()
	end)

	t.test("stickerText soft (T5): the toast's soft drop (H:175) without an outline, the label outlined", function()
		local role = Theme.Sticker.text.toastText
		expect.deepEqual(role.soft, { px = 2, alpha = 0.6 })
		local label = Instance.new("TextLabel")
		label.Text = "Saved"
		Theme.stickerText(label, "toastText")
		local drop = label:FindFirstChild("SD_Drop") :: TextLabel
		expect.truthy(label:FindFirstChild("SD_Drop") ~= nil and label:FindFirstChild("SD_Face") ~= nil)
		expect.equal(drop.Position.Y.Offset, role.soft.px)
		expect.truthy(sameColor(drop.TextColor3, Theme.Colors.inkUI))
		expect.near(drop.TextTransparency, 1 - role.soft.alpha, 1e-4) -- rgba(30,20,40,.6)
		local dropOutline = drop:FindFirstChild("SD_Outline") :: UIStroke?
		expect.truthy(dropOutline == nil or not dropOutline.Enabled)
		expect.equal((label:FindFirstChild("SD_Outline") :: UIStroke).Thickness, role.stroke / 2)
		label.TextTransparency = 0.5
		task.wait() -- property signals are deferred
		expect.near(drop.TextTransparency, 1 - 0.5 * role.soft.alpha, 1e-4) -- it fades with the label
		label:Destroy()
	end)

	t.test("softShadow (T1, T2): the 9-slice picture or the tinted glow under the target, offsetY lower", function()
		local wrapper = Instance.new("Frame")
		local spec = { offsetY = 14, blurPx = 40, alpha = 0.45 } -- test numbers (each window passes its design line)
		local shadow = Theme.softShadow(wrapper, "img.fx.shadowWindow", spec)
		if AssetTable.image("img.fx.shadowWindow") then
			local made = shadow :: ImageLabel
			expect.equal(made.Name, "SD_SoftShadow")
			expect.equal(made.ZIndex, 0)
			expect.equal(made.ScaleType, Enum.ScaleType.Slice)
			expect.equal(made.Position, UDim2.fromOffset(-120, 14 - 120)) -- the render's 120 px margin
			expect.equal(made.Size, UDim2.new(1, 240, 1, 240))
		elseif AssetTable.image("img.fx.glow") then
			local made = shadow :: ImageLabel
			expect.equal(made.Name, "SD_SoftShadow")
			expect.equal(made.ZIndex, 0)
			expect.truthy(sameColor(made.ImageColor3, Theme.Colors.inkUI))
			expect.near(made.ImageTransparency, 0.55, 1e-4)
			expect.equal(made.Position, UDim2.fromOffset(-40, 14 - 40))
			expect.equal(made.Size, UDim2.new(1, 80, 1, 80))
		else
			expect.equal(shadow, nil)
		end
		expect.equal(Theme.softShadow(wrapper, "img.fx.shadowWindow", spec), shadow) -- reused
		wrapper:Destroy()
	end)

	-- UI FINAL R3 (the window frame, plan work/ui/PLAN.md R3) -------------------------------------------------------

	local WINDOW = Config.UI.Sticker.window
	local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

	local function cornerOf(object: Instance): number?
		local corner = object:FindFirstChildOfClass("UICorner")
		return if corner then corner.CornerRadius.Offset else nil
	end

	t.test("window (H:182): the pink body, its 5 px inner ink border, radius 32, the lip and its padding", function()
		local window = Theme.window({ Name = "Quests", Size = UDim2.fromOffset(900, 400) }, "quests", 20)
		expect.equal(window.Name, "Quests")
		expect.truthy(Theme.isWindow(window))
		expect.equal(Theme.windowKind(window), "quests")
		expect.truthy(window.Active) -- a click on the window never reaches the scrim under it
		local list = strokes(window)
		expect.equal(#list, 1)
		expect.equal(list[1].Thickness, Theme.Sticker.border.heavy)
		expect.truthy(sameColor(list[1].Color, Theme.Colors.inkUI))
		local position = innerPosition(list[1])
		if position ~= nil then
			expect.equal(position, Enum.BorderStrokePosition.Inner)
		end
		expect.equal(cornerOf(window), Theme.Sticker.radius.window)
		local gradient = window:FindFirstChild("SD_Foam") :: UIGradient
		expect.truthy(sameColor(gradient.Color.Keypoints[1].Value, Palette.StickerWindowTop))
		expect.truthy(hasColor(gradient.Color, Palette.StickerWindowBottom))
		expect.truthy(sameColor(gradient.Color.Keypoints[#gradient.Color.Keypoints].Value, Theme.Colors.inkUI))
		-- The padding on every side of the face; the lip (10, H:182) under it.
		local pad = window:FindFirstChildOfClass("UIPadding") :: UIPadding
		expect.equal(pad.PaddingLeft.Offset, 20)
		expect.equal(pad.PaddingRight.Offset, 20)
		expect.equal(pad.PaddingBottom.Offset, 20 + Theme.Sticker.lip.window)
		expect.equal(window:FindFirstChild("SD_InnerRing"), nil) -- the inner ring is the Squishies window's
		window:Destroy()
		-- H:182: the Squishies window's inset 0 0 0 3px rgba(255,255,255,.05), inside the border.
		local squishies = Theme.window({ Size = UDim2.fromOffset(1060, 660) }, "squishies", 12)
		expect.truthy(squishies:FindFirstChild("SD_InnerRing") ~= nil)
		local ring = squishies:FindFirstChild("SD_InnerRing") :: Frame
		expect.equal(ring.ZIndex, 0)
		expect.equal(cornerOf(ring), Theme.Sticker.radius.window - Theme.Sticker.border.heavy)
		local ringStroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
		expect.equal(ringStroke.Thickness, WINDOW.innerRing.px)
		expect.near(ringStroke.Transparency, 1 - WINDOW.innerRing.alpha, 1e-6)
		expect.truthy(sameColor(ringStroke.Color, WHITE))
		expect.equal(ring.Position, UDim2.fromOffset(5 - 12, 5 - 12))
		expect.equal(ring.Size, UDim2.new(1, 24 - 10, 1, 12 + 22 - 10 - 10))
		squishies:Destroy()
		local panel = Theme.panel({})
		expect.falsy(Theme.isWindow(panel))
		expect.equal(Theme.windowKind(panel), nil)
		expect.deepEqual(Theme.fitWindow(panel), { top = 0, above = 0, band = 0, k = 1 })
		panel:Destroy()
	end)

	t.test(
		"headerTab on a window: the design's band (H:183-184), the title in capitals, the sticker (H:251)",
		function()
			local window = Theme.window({ Name = "Quests", Size = UDim2.fromOffset(900, 400) }, "quests", 20)
			local band, title = Theme.headerTab(window, "Quests")
			expect.equal(band.Name, "HeaderBand")
			expect.equal(band.Parent, window)
			expect.equal(title.Parent, band)
			expect.equal(title.Text, "QUESTS") -- Q5: capitals (H:354)
			expect.equal(title:GetAttribute("SD_TextKind"), Theme.Sticker.text.windowTitle.kind)
			expect.equal(title.TextXAlignment, Enum.TextXAlignment.Left)
			expect.falsy(title.TextWrapped)
			-- Sized from its measure, not AutomaticSize (the Studio sheet: under a UIScale above 1 an automatic label's
			-- box grows by the scale again, so the 1920 x 1080 Grip title's box reached under the X).
			expect.equal(title.AutomaticSize, Enum.AutomaticSize.None)
			expect.truthy(title.Size.X.Offset >= Theme.textWidth("QUESTS", "Window")) -- the windowTitle role's kind
			expect.truthy(title.Size.Y.Offset >= Theme.lineHeight("Window") - 1e-6)
			local spec = WINDOW.kinds.quests
			local b = WINDOW.band
			local height = math.ceil(math.max(b.height, Theme.lineHeight("Window") + 2 * b.titlePad))
			expect.equal(height, 98) -- the design's band at the default text size
			local chrome = Theme.fittedChrome(window)
			expect.deepEqual(chrome, { top = 5 + 98 + 20, above = 62, band = 98, k = 1 })
			local pad = window:FindFirstChildOfClass("UIPadding") :: UIPadding
			expect.equal(pad.PaddingTop.Offset, 5 + 98 + 20) -- the border, the band, the body's padding
			-- The band covers the window's top (its UIPadding undone), the face inside the 5 px border.
			expect.equal(band.Position, UDim2.fromOffset(-20, -123))
			expect.equal(band.Size, UDim2.new(1, 40, 0, 5 + 98))
			local clip = band:FindFirstChild("SD_BandClip") :: Frame
			expect.truthy(clip.ClipsDescendants)
			expect.equal(clip.Position, UDim2.fromOffset(5, 5))
			expect.equal(clip.Size, UDim2.new(1, -10, 0, 98))
			-- Its top corners rounded 27 (H:182: 32 less the border): the face is taller than the clip by the radius.
			local face = clip:FindFirstChild("SD_BandFace") :: Frame
			expect.equal(cornerOf(face), b.cornerRadius)
			expect.equal(face.Size, UDim2.new(1, 0, 0, 98 + b.cornerRadius))
			local stops = (face:FindFirstChild("SD_Foam") :: UIGradient).Color
			expect.truthy(sameColor(stops.Keypoints[1].Value, Palette.StickerMintTop:Lerp(WHITE, spec.highlightAlpha)))
			expect.truthy(hasColor(stops, Palette.StickerMintTop))
			expect.truthy(hasColor(stops, Palette.StickerHeaderMintEnd))
			expect.truthy(hasColor(stops, Palette.StickerHeaderMintEnd:Lerp(BLACK, b.bevelAlpha)))
			expect.truthy(sameColor(stops.Keypoints[#stops.Keypoints].Value, Theme.Colors.inkUI))
			if AssetTable.image("img.fx.dots") then
				local dots = clip:FindFirstChild("SD_Dots") :: ImageLabel
				expect.equal(dots.ScaleType, Enum.ScaleType.Tile)
				expect.equal(dots.TileSize, UDim2.fromOffset(b.dotsTile, b.dotsTile))
				expect.near(dots.ImageTransparency, 1 - spec.dotsAlpha, 1e-6)
				-- H:183: the dots are background; the band's 5 px bottom border paints over them.
				local edge = clip:FindFirstChild("SD_BandEdge") :: Frame
				expect.truthy(edge.ZIndex > dots.ZIndex)
				expect.equal(edge.Size, UDim2.new(1, 0, 0, b.border))
				expect.equal(edge.Position, UDim2.fromScale(0, 1))
				expect.equal(edge.AnchorPoint, Vector2.new(0, 1))
			end
			-- The title from the padding's 176 (H:183), centred on the band above its bottom border.
			expect.equal(title.Position, UDim2.fromOffset(5 + b.padLeft, math.round(5 + (98 - b.border) / 2)))
			expect.equal((title:FindFirstChild("SD_TitleScale") :: UIScale).Scale, 1)
			if AssetTable.image("img.nav.quests") then
				local sticker = band:FindFirstChild("SD_Sticker") :: Frame
				expect.equal(sticker.Size, UDim2.fromOffset(190, 190))
				expect.equal(sticker.Position, UDim2.fromOffset(-40 + 95, -62 + 95)) -- H:251: left -40, top -62
				local bob = (sticker:FindFirstChild("SD_Stick") :: Frame):FindFirstChild("SD_StickerBob") :: Frame
				local shadow = bob:FindFirstChild("SD_StickerShadow") :: ImageLabel
				expect.truthy(sameColor(shadow.ImageColor3, Palette.StickerStickerShadow))
				expect.near(shadow.ImageTransparency, 1 - WINDOW.sticker.shadowAlpha, 1e-6)
				expect.equal(shadow.Position, UDim2.fromOffset(0, 7))
				expect.truthy(bob:FindFirstChild("SD_StickerImage") ~= nil)
			end
			-- A caller's text shows in capitals too.
			title.Text = "Daily"
			task.wait() -- property signals are deferred
			expect.equal(title.Text, "DAILY")
			-- A smaller chrome (a phone): the band, the padding and the sticker shrink; the title too, never under 16.
			local half = Theme.fitWindow(window, 0.5)
			expect.deepEqual(half, { top = 5 + 49 + 20, above = 31, band = 49, k = 0.5 })
			expect.equal(pad.PaddingTop.Offset, 74)
			local titleScale = (title:FindFirstChild("SD_TitleScale") :: UIScale).Scale
			expect.truthy(titleScale <= 0.5 + 1e-6 and titleScale >= 16 / Config.UI.TextSize.Window - 1e-6)
			if AssetTable.image("img.nav.quests") then
				local sticker = band:FindFirstChild("SD_Sticker") :: Frame
				expect.equal(sticker.Size, UDim2.fromOffset(95, 95))
				expect.equal(sticker.Position, UDim2.fromOffset(math.round(-20 + 47.5), math.round(-31 + 47.5)))
			end
			expect.deepEqual(Theme.fittedChrome(window), half) -- the last fit
			-- The close X in the band at (right -22, top -22) of the window (H:252), above the band's parts.
			local x = Instance.new("TextButton")
			Theme.attachClose(window, x)
			expect.equal(x.Parent, band)
			expect.equal(x.AnchorPoint, Vector2.new(1, 0))
			expect.equal(x.Position, UDim2.new(1, 22, 0, -22))
			expect.truthy(x.ZIndex > title.ZIndex)
			window:Destroy()
		end
	)

	t.test("headerTab on a window: the extra (H:185), the small band (H:428), a window without a sticker", function()
		local squishies = Theme.window({ Size = UDim2.fromOffset(1060, 660) }, "squishies", 12)
		local chip = Instance.new("Frame")
		local band = Theme.headerTab(squishies, "Squishies", { extra = chip })
		expect.equal(chip.Parent, band)
		expect.equal(chip.AnchorPoint, Vector2.new(1, 0.5))
		expect.equal(chip.Position.X, UDim.new(1, -(5 + WINDOW.band.padRight)))
		-- With the X (H:252: 76 px at right -22, so it reaches 54 px into the window) the design's 110 stays at full
		-- size; a small chrome keeps the extra a gap clear of the X instead of 110 x k.
		local x = Instance.new("TextButton")
		x.Size = UDim2.fromOffset(76, 76)
		Theme.attachClose(squishies, x)
		expect.equal(chip.Position.X, UDim.new(1, -(5 + WINDOW.band.padRight)))
		Theme.fitWindow(squishies, 0.38)
		local reach = WINDOW.close.face - WINDOW.close.right
		expect.truthy(-chip.Position.X.Offset >= reach + math.round(WINDOW.band.gap * 0.38))
		squishies:Destroy()
		-- Settings (H:428-451): 92 high, the settingsTitle role, 140 / 100, the 150 px sticker at (-30, -46).
		local settings = Theme.window({ Size = UDim2.fromOffset(600, 400) }, "settings", 20)
		local settingsBand, settingsTitle = Theme.headerTab(settings, "Settings")
		expect.equal(settingsTitle:GetAttribute("SD_TextKind"), Theme.Sticker.text.settingsTitle.kind)
		local small = Theme.fittedChrome(settings)
		expect.equal(small.band, math.ceil(math.max(92, Theme.lineHeight("WindowSmall") + 2 * WINDOW.band.titlePad)))
		expect.equal(small.above, 46)
		expect.equal(settingsTitle.Position.X.Offset, 5 + WINDOW.band.smallPadLeft)
		if AssetTable.image("img.nav.settings") then
			local sticker = settingsBand:FindFirstChild("SD_Sticker") :: Frame
			expect.equal(sticker.Size, UDim2.fromOffset(150, 150))
			expect.equal(sticker.Position, UDim2.fromOffset(-30 + 75, -46 + 75))
		end
		-- A caller that sizes the window after fitting it: the band fits again (the title's room follows the width).
		local titleScale = settingsTitle:FindFirstChild("SD_TitleScale") :: UIScale
		local before = titleScale.Scale
		settings.Size = UDim2.fromOffset(260, 400)
		task.wait() -- property signals are deferred
		expect.truthy(titleScale.Scale < before)
		settings:Destroy()
		-- The Grip panel (a reading: no sticker): 110 on both sides; only the X hangs above it.
		local grip = Theme.window({ Size = UDim2.fromOffset(600, 400) }, "grip", 20)
		local gripBand, gripTitle = Theme.headerTab(grip, "Grip Training")
		expect.equal(gripBand:FindFirstChild("SD_Sticker"), nil)
		expect.equal(gripTitle.Position.X.Offset, 5 + WINDOW.band.plainPad)
		expect.equal(Theme.fittedChrome(grip).above, WINDOW.close.top)
		grip:Destroy()
	end)

	t.test("headerTab on a window: a tall extra stays inside the band on a small chrome", function()
		-- Inspect's 57 px Close pill at an 844 x 311 phone's chrome (k .49; the Studio component sheet found it 2.5 px
		-- over the band's top): the band grows so the centred extra clears its top and its 5 px bottom border.
		local inspect = Theme.window({ Size = UDim2.fromOffset(924, 318) }, "inspect", 12)
		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromOffset(126, 57)
		Theme.headerTab(inspect, "Cupcake Axolotl", { name = "NameTab", extra = pill })
		local chrome = Theme.fitWindow(inspect, 0.49)
		local border = Theme.Sticker.border.heavy
		local centre = pill.Position.Y.Offset
		expect.truthy(centre - 57 / 2 >= border) -- under the band's top (the clip starts inside the window's border)
		expect.truthy(centre + 57 / 2 <= border + chrome.band - WINDOW.band.border + 0.5) -- whole-px centring
		inspect:Destroy()
	end)

	t.test("every window kind names Palette colours and, with a sticker, a picture slot", function()
		local keys: { [string]: boolean } = {}
		for _, slot in AssetTable.all() do
			keys[slot.key] = true
		end
		for name, kind in WINDOW.kinds do
			for _, field in { "top", "bottom" } do
				if typeof(Palette[kind[field]]) ~= "Color3" then
					error(`window kind {name}: Palette.{kind[field]} is not a colour`)
				end
			end
			if kind.sticker ~= nil and not keys[kind.sticker] then
				error(`window kind {name}: {kind.sticker} is not an AssetTable slot`)
			end
		end
	end)

	t.test("scrim (H:178): a clear full-screen TextButton with the radial picture or its fallback", function()
		local scrim = Theme.scrim({ Name = "Dimmer" })
		expect.truthy(scrim:IsA("TextButton"))
		expect.equal(scrim.Text, "")
		expect.falsy(scrim.AutoButtonColor)
		expect.truthy(scrim.Active)
		expect.falsy(scrim.Selectable)
		expect.equal(scrim.Size, UDim2.fromScale(1, 1))
		if AssetTable.image("img.fx.radial.scrimWindow") then
			expect.equal(scrim.BackgroundTransparency, 1)
			expect.truthy(scrim:FindFirstChild("SD_Radial") ~= nil)
		else
			expect.truthy(sameColor(scrim.BackgroundColor3, Palette.StickerScrimPurple))
			expect.near(scrim.BackgroundTransparency, 1 - WINDOW.scrim.outerAlpha, 1e-4)
			if AssetTable.image("img.fx.glow") then
				local glow = scrim:FindFirstChild("SD_Glow") :: ImageLabel
				expect.truthy(sameColor(glow.ImageColor3, Palette.StickerScrimPink))
				expect.near(glow.ImageTransparency, 1 - WINDOW.scrim.innerAlpha, 1e-4)
				expect.falsy(glow.Active)
			end
		end
		scrim:Destroy()
	end)

	t.test("scrollbar (H:22) and the window's soft shadow (H:182)", function()
		local list = Instance.new("ScrollingFrame")
		expect.equal(Theme.scrollbar(list), list)
		expect.equal(list.ScrollBarThickness, 12)
		expect.equal(Theme.SCROLLBAR_PX, 12)
		expect.truthy(sameColor(list.ScrollBarImageColor3, Palette.StickerScrollThumb))
		list:Destroy()
		-- The thumb shows where it sits (3:1, a UI part): the design's colour on both pink stops; in a well (#5B36D9,
		-- where that colour is 1.1:1) ScrollHint's "well" tone keeps the light thumb.
		for _, stop in { Palette.StickerWindowTop, Palette.StickerWindowBottom } do
			expect.truthy(contrast(Theme.Colors.scrollThumb, stop) >= 3)
		end
		expect.truthy(contrast(Theme.Colors.ink2, Theme.Colors.biscuit) >= 3)
		local wrapper = Instance.new("Frame")
		local shadow = Theme.windowShadow(wrapper)
		if AssetTable.image("img.fx.shadowWindow") then
			expect.equal((shadow :: ImageLabel).ScaleType, Enum.ScaleType.Slice)
		elseif AssetTable.image("img.fx.glow") then
			local made = shadow :: ImageLabel
			expect.truthy(sameColor(made.ImageColor3, Palette.StickerShadowWindow))
			expect.near(made.ImageTransparency, 1 - WINDOW.shadow.alpha, 1e-4)
			expect.equal(made.Position, UDim2.fromOffset(-70, 34 - 70))
		end
		wrapper:Destroy()
	end)

	t.test("ScrollHint tones (UI FINAL R3): the design's thumb on a window body, the light one in a well", function()
		local ScrollHint = t.requireClient("UI/Components/ScrollHint")
		local holder = Instance.new("Frame")
		local scroll = Instance.new("ScrollingFrame")
		scroll.Parent = holder
		local thumbs: { [string]: Color3 } = { window = Theme.Colors.scrollThumb, well = Theme.Colors.ink2 }
		for tone, thumb in thumbs do
			local hint = ScrollHint.new({ scroll = scroll, parent = holder, tone = tone })
			expect.truthy(sameColor((hint.root:FindFirstChild("Thumb") :: Frame).BackgroundColor3, thumb))
			hint:destroy()
		end
		local default = ScrollHint.new({ scroll = scroll, parent = holder }) -- no tone: a window body
		expect.truthy(sameColor((default.root:FindFirstChild("Thumb") :: Frame).BackgroundColor3, thumbs.window))
		default:destroy()
		holder:Destroy()
	end)
end
