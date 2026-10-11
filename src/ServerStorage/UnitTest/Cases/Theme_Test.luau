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
	local Config = t.requireShared("Config")
	local Theme = t.requireClient("UI/Theme")

	t.test("the Candy UI tokens have their values", function()
		for name, hex in UI_HEX do
			local color = Palette[name]
			if not (typeof(color) == "Color3" and sameColor(color, Color3.fromHex(hex))) then
				error(`Palette.{name} is {tostring(color)}, the overhaul says {hex}`)
			end
		end
		expect.truthy(sameColor(Theme.Colors.inkUI, Palette.PlumInk))
		expect.truthy(sameColor(Theme.Colors.panel, Palette.PanelBody))
		expect.truthy(sameColor(Theme.Colors.text, Palette.WarmWhite))
		expect.truthy(sameColor(Theme.Accents.strawberry.face, Palette.CandyCoral))
		expect.truthy(sameColor(Theme.Accents.shop.face, Palette.CandyLime))
		-- The world keeps its own Ink and Cream (nameplates, signs).
		expect.truthy(sameColor(Theme.Colors.ink, Palette.Ink))
		expect.truthy(sameColor(Theme.Colors.cream, Palette.Cream))
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
		-- Lime #8DEE42: hue 93.8°, 50.8° from CoinGold.
		expect.near(hue(shop), 93.8, 0.2)
		expect.near(hueGap(shop, Palette.CoinGold), 50.8, 0.3)
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
		for _, surface in { Theme.Colors.panel, Theme.Colors.panelAlt, Theme.Colors.biscuit } do
			expect.truthy(contrast(Theme.Colors.text, surface) >= MIN_TEXT_CONTRAST)
			expect.truthy(contrast(Theme.Colors.ink2, surface) >= MIN_TEXT_CONTRAST)
		end
		expect.truthy(contrast(Theme.Colors.textFaint, Theme.Colors.panel) >= MIN_TEXT_CONTRAST)
		expect.truthy(contrast(Theme.Colors.ink2, Theme.Colors.disabledFace) >= MIN_TEXT_CONTRAST)
	end)

	t.test("the outlined-text rule: only display kinds of 16 base px or more", function()
		for kind, size in Config.UI.TextSize do
			local expected = Theme.isDisplay(kind) and size >= Theme.OUTLINE_MIN_BASE_PX
			expect.equal(Theme.outlineAllowed(kind), expected)
		end
		expect.truthy(Theme.outlineAllowed("Button"))
		expect.truthy(Theme.outlineAllowed("H2"))
		expect.truthy(Theme.outlineAllowed("Chip"))
		expect.falsy(Theme.outlineAllowed("Body"))
		expect.falsy(Theme.outlineAllowed("NoSuchKind"))
		expect.equal(Theme.outlinePx("Title"), 3)
		expect.equal(Theme.outlinePx("H2"), 2.5)
		expect.equal(Theme.outlinePx("Button"), 2)
		expect.equal(Theme.outlinePx("Chip"), 1.5)
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
			expect.falsy(Theme.textOnColor(small))
			expect.truthy(sameColor(small.TextColor3, Theme.Colors.inkUI))
			local none = small:FindFirstChild("SD_Outline") :: UIStroke?
			expect.truthy(none == nil or not none.Enabled)
			-- On a dark face body text turns white.
			Theme.textOnColor(small, nil, Theme.Accents.plum.face)
			expect.truthy(sameColor(small.TextColor3, Color3.new(1, 1, 1)))
			-- textOnAccent: PlumInk on a light accent.
			Theme.textOnAccent(small, "gold")
			expect.truthy(sameColor(small.TextColor3, Theme.Colors.inkUI))
			small:Destroy()
		end
	)

	t.test("fonts: display kinds in Fredoka One, body kinds in the body family; headlines outlined", function()
		local fredoka = Font.fromEnum(Enum.Font.FredokaOne)
		for _, kind in { "Title", "H2", "HudNumber", "Countdown", "Button", "Chip" } do
			expect.equal(Theme.font(kind).Family, fredoka.Family)
		end
		local body = Theme.font("Body")
		expect.truthy(string.find(body.Family, Theme.BODY_FAMILY, 1, true) ~= nil)
		if Theme.BODY_FAMILY == "Nunito" then
			expect.equal(Theme.font("Body").Weight, Enum.FontWeight.Bold)
			expect.equal(Theme.font("Small", Enum.FontWeight.Bold).Weight, Enum.FontWeight.ExtraBold)
		end
		-- The default text colour is the light text of the dark surfaces; a headline in it carries the outline.
		local label = Theme.label({ Name = "Body", Text = "x" }, "Body")
		expect.truthy(sameColor(label.TextColor3, Theme.Colors.text))
		expect.equal(label:FindFirstChild("SD_Outline"), nil)
		label:Destroy()
		local title = Theme.label({ Name = "Title", Text = "x" }, "Title")
		local outline = title:FindFirstChild("SD_Outline") :: UIStroke
		expect.truthy(outline ~= nil and outline.Enabled)
		expect.equal(outline.Thickness, 3)
		-- A given colour has no outline.
		Theme.text(title, "Title", nil, Theme.Colors.ink2)
		expect.falsy(outline.Enabled)
		title:Destroy()
	end)

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
	end)

	t.test("panel: a dark foam frame with the PlumInk outline, the inner rim and room for the bands", function()
		local holder = Instance.new("Folder")
		local panel = Theme.panel({ Name = "Card", Size = UDim2.fromOffset(200, 100), Parent = holder }, nil, 6)
		expect.equal(panel.Parent, holder)
		expect.equal(panel.Name, "Card")
		expect.truthy(sameColor(panel.BackgroundColor3, Theme.Colors.panel))
		expect.equal(panel.BackgroundTransparency, 0)
		local list = strokes(panel)
		expect.equal(#list, 2)
		local stroke = panel:FindFirstChildOfClass("UIStroke") :: UIStroke
		expect.truthy(stroke.Name ~= "SD_Rim")
		expect.truthy(sameColor(stroke.Color, Theme.Colors.inkUI))
		expect.equal(stroke.Thickness, Theme.Stroke.ink)
		local rim = panel:FindFirstChild("SD_Rim") :: UIStroke
		expect.truthy(rim ~= nil and rim:IsA("UIStroke"))
		expect.equal((rim :: any).BorderStrokePosition, Enum.BorderStrokePosition.Inner)
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
		expect.truthy(sameColor(points[1].Value, accent.face:Lerp(Color3.new(1, 1, 1), Theme.Foam.highlight)))
		expect.truthy(sameColor(points[#points].Value, Theme.Colors.inkUI))
		local hasShade = false
		for _, point in points do
			hasShade = hasShade or sameColor(point.Value, accent.shade)
		end
		expect.truthy(hasShade)
		foam:paint(Theme.accentColors("sky"))
		points = foam.gradient.Color.Keypoints
		expect.truthy(sameColor(points[1].Value, Theme.Accents.sky.face))
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
		expect.truthy(glow ~= nil)
		expect.equal(glow.Size.Y.Offset > pad.PaddingTop.Offset, true)
		panel:Destroy()
	end)

	t.test("inset: a recessed field with no outline", function()
		local field = Theme.inset({ Name = "Stats" })
		expect.truthy(sameColor(field.BackgroundColor3, Theme.Colors.biscuit))
		expect.equal(field:FindFirstChildOfClass("UIStroke"), nil)
		expect.truthy(field:FindFirstChild("SD_Foam") ~= nil)
		field:Destroy()
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
end
