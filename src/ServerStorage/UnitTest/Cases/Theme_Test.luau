--!strict
-- Theme_Test: the foam UI tokens and helpers of StarterPlayerScripts.Client.UI.Theme (and the UI tokens of
-- ReplicatedStorage.Shared.Art.Palette). Server only (ServerStorage.UnitTest). Edit mode: the instances are built
-- unparented and destroyed.
-- Contract (foam UI restyle, docs/superpowers/specs/2026-10-09-foam-ui-restyle-design.md "Tokens", "Text", "Shapes"):
--   * the UI tokens have the spec's hex values; the world tokens of §7.2 are untouched (Catalog_Test checks those);
--   * the Shop accent is at least 20° of hue from CoinGold, Exclusive and Danger and from every other tile accent; no
--     accent reuses a reserved gameplay colour;
--   * contrast: InkUI on every accent face and on the paper tokens, Ink2 on Frosting and on the disabled face >= 4.5:1;
--   * the outlined-text rule: white with a 2 px InkUI Contextual UIStroke only for display kinds of >= 18 base px,
--     InkUI otherwise; textOnLight takes the outline away;
--   * fonts: display kinds draw in Fredoka One, the others in Theme.BODY_FAMILY (Nunito lifts every weight one step);
--     textBounds always answers (an estimate when TextService cannot);
--   * Theme.panel keeps its Part 8 contract (a Frame, the caller's props, one UIStroke child the caller may recolour)
--     with the foam look: Frosting, InkUI 2.5 outline, a vertical foam UIGradient, a bottom padding that clears the
--     bands; Theme.foam "exact" paints over white; headerTab straddles the panel's top edge and makes room under it;
--     Theme.inset is a Biscuit field with no outline.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

-- Foam spec "Tokens".
local UI_HEX: { [string]: string } = {
	Frosting = "#FFF6EA",
	PanelAlt = "#FFF9F1",
	Biscuit = "#F1DEC4",
	Bevel = "#EBD7BC",
	InkUI = "#2B2233",
	Ink2 = "#6A5F70",
	UIStrawberry = "#F2687F",
	UIStrawberryShade = "#D04B66",
	UIMint = "#5FD3AE",
	UIMintShade = "#36AE89",
	UIQuestMint = "#4FCBA3",
	UIQuestMintShade = "#2FA884",
	UILilac = "#A98BE8",
	UILilacShade = "#8668CF",
	UISkyBlue = "#5DB8F0",
	UISkyBlueShade = "#3C97D4",
	DisabledFace = "#E9E1D6",
	DisabledStroke = "#A79FAB",
	DisabledShade = "#D9CFC2",
	DisabledText = "#8C8290",
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
	return math.abs(a.R - b.R) < 1e-4 and math.abs(a.G - b.G) < 1e-4 and math.abs(a.B - b.B) < 1e-4
end

return function(t: Context)
	local expect = t.expect
	local Palette = t.requireShared("Art/Palette")
	local RarityStyle = t.requireShared("Art/RarityStyle")
	local Config = t.requireShared("Config")
	local Theme = t.requireClient("UI/Theme")

	t.test("the UI tokens have the spec's values", function()
		for name, hex in UI_HEX do
			local color = Palette[name]
			if not (typeof(color) == "Color3" and sameColor(color, Color3.fromHex(hex))) then
				error(`Palette.{name} is {tostring(color)}, the spec says {hex}`)
			end
		end
		expect.truthy(sameColor(Theme.Colors.inkUI, Color3.fromHex("#2B2233")))
		expect.truthy(sameColor(Theme.Colors.panel, Color3.fromHex("#FFF6EA")))
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
		-- The numbers written down in Art/Palette.
		expect.near(hue(shop), 90.5, 0.2)
		expect.near(hueGap(shop, Palette.CoinGold), 47.5, 0.2)
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

	t.test("text contrast: InkUI on every face and paper, Ink2 on Frosting and the disabled face", function()
		for name, accent in Theme.Accents do
			local ratio = contrast(Theme.Colors.inkUI, accent.face)
			if ratio < MIN_TEXT_CONTRAST then
				error(`InkUI on the {name} accent is {ratio}:1`)
			end
		end
		for _, paper in { Theme.Colors.frosting, Theme.Colors.panelAlt, Theme.Colors.biscuit } do
			expect.truthy(contrast(Theme.Colors.inkUI, paper) >= MIN_TEXT_CONTRAST)
		end
		expect.truthy(contrast(Theme.Colors.ink2, Theme.Colors.frosting) >= MIN_TEXT_CONTRAST)
		expect.truthy(contrast(Theme.Colors.ink2, Theme.Colors.disabledFace) >= MIN_TEXT_CONTRAST)
		expect.truthy(contrast(Theme.Colors.frosting, Theme.Colors.inkUI) >= MIN_TEXT_CONTRAST) -- the keycap
	end)

	t.test("the outlined-text rule: only display kinds of 18 base px or more", function()
		for kind, size in Config.UI.TextSize do
			local expected = Theme.isDisplay(kind) and size >= Theme.OUTLINE_MIN_BASE_PX
			expect.equal(Theme.outlineAllowed(kind), expected)
		end
		expect.truthy(Theme.outlineAllowed("Button"))
		expect.truthy(Theme.outlineAllowed("H2"))
		expect.falsy(Theme.outlineAllowed("Chip"))
		expect.falsy(Theme.outlineAllowed("Body"))
		expect.falsy(Theme.outlineAllowed("NoSuchKind"))
	end)

	t.test(
		"textOnColor outlines big display text and keeps small text InkUI; textOnLight removes the outline",
		function()
			local big = Theme.label({ Name = "Big", Text = "DUEL" }, "Button")
			expect.truthy(Theme.textOnColor(big))
			expect.truthy(sameColor(big.TextColor3, Color3.new(1, 1, 1)))
			local found = big:FindFirstChild("SD_Outline")
			expect.truthy(found ~= nil and found:IsA("UIStroke"))
			local outline = found :: UIStroke
			expect.truthy(outline.Enabled)
			expect.equal(outline.ApplyStrokeMode, Enum.ApplyStrokeMode.Contextual)
			expect.equal(outline.Thickness, 2)
			expect.truthy(sameColor(outline.Color, Theme.Colors.inkUI))
			Theme.textOnLight(big)
			expect.falsy(outline.Enabled)
			expect.truthy(sameColor(big.TextColor3, Theme.Colors.inkUI))
			-- Calling it again reuses the one outline.
			Theme.textOnColor(big)
			local count = 0
			for _, child in big:GetChildren() do
				if child:IsA("UIStroke") then
					count += 1
				end
			end
			expect.equal(count, 1)
			big:Destroy()

			local small = Theme.label({ Name = "Small", Text = "Squishies" }, "Chip")
			expect.falsy(Theme.textOnColor(small))
			expect.truthy(sameColor(small.TextColor3, Theme.Colors.inkUI))
			local none = small:FindFirstChild("SD_Outline") :: UIStroke?
			expect.truthy(none == nil or not none.Enabled)
			small:Destroy()
		end
	)

	t.test("fonts: display kinds in Fredoka One, body kinds in the body family", function()
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
		-- The default text colour is InkUI.
		local label = Theme.label({ Name = "Body", Text = "x" }, "Body")
		expect.truthy(sameColor(label.TextColor3, Theme.Colors.inkUI))
		label:Destroy()
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

	t.test("panel: a Frosting foam frame with one InkUI outline, a foam gradient and room for the bands", function()
		local holder = Instance.new("Folder")
		local panel = Theme.panel({ Name = "Card", Size = UDim2.fromOffset(200, 100), Parent = holder }, nil, 6)
		expect.equal(panel.Parent, holder)
		expect.equal(panel.Name, "Card")
		expect.truthy(sameColor(panel.BackgroundColor3, Theme.Colors.panel))
		expect.equal(panel.BackgroundTransparency, 0)
		local strokes = 0
		for _, child in panel:GetChildren() do
			if child:IsA("UIStroke") then
				strokes += 1
			end
		end
		expect.equal(strokes, 1)
		local stroke = panel:FindFirstChildOfClass("UIStroke") :: UIStroke
		expect.truthy(sameColor(stroke.Color, Theme.Colors.inkUI))
		expect.equal(stroke.Thickness, Theme.Stroke.ink)
		local foundGradient = panel:FindFirstChild("SD_Foam")
		expect.truthy(foundGradient ~= nil and foundGradient:IsA("UIGradient"))
		local gradient = foundGradient :: UIGradient
		expect.equal(gradient.Rotation, 90)
		local pad = panel:FindFirstChildOfClass("UIPadding") :: UIPadding
		local bands = Theme.Foam.panel
		expect.equal(pad.PaddingTop.Offset, 6)
		expect.truthy(pad.PaddingBottom.Offset >= 6 and pad.PaddingBottom.Offset > bands.bevel + bands.drop)
		-- A "tint" panel: the gradient only darkens (every stop <= 1), so a caller's colour shows as the face.
		local keypoints = gradient.Color.Keypoints
		expect.truthy(sameColor(keypoints[1].Value, Color3.new(1, 1, 1)))
		for _, point in keypoints do
			expect.truthy(point.Value.R <= 1 and point.Value.G <= 1 and point.Value.B <= 1)
		end
		local last = keypoints[#keypoints].Value
		expect.truthy(luminance(last) < 0.1) -- the ink drop at the bottom
		-- A medium padding already clears the bands and stays as it was.
		local roomy = Theme.panel({}, nil, Theme.Padding.medium)
		expect.equal((roomy:FindFirstChildOfClass("UIPadding") :: UIPadding).PaddingBottom.Offset, 12)
		roomy:Destroy()
		holder:Destroy()
	end)

	t.test("foam exact: paints the given colours over white and repaints", function()
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
		frame:Destroy()
	end)

	t.test("headerTab straddles the panel's top edge and makes room under it", function()
		local panel = Theme.panel({ Name = "Quests", Size = UDim2.fromOffset(400, 300) }, Theme.Radius.panel, 12)
		local tab, label = Theme.headerTab(panel, "Quests")
		expect.equal(tab.Parent, panel)
		expect.equal(tab.Name, "HeaderTab")
		expect.equal(label.Text, "Quests")
		local pad = panel:FindFirstChildOfClass("UIPadding") :: UIPadding
		expect.truthy(pad.PaddingTop.Offset > 12) -- room for the tab's lower half
		expect.equal(tab.Position.Y.Offset, -pad.PaddingTop.Offset) -- centred on the panel's top edge
		expect.equal(tab.AnchorPoint, Vector2.new(0.5, 0.5))
		expect.truthy(sameColor(label.TextColor3, Color3.new(1, 1, 1))) -- H2 on Strawberry: outlined white
		panel:Destroy()
	end)

	t.test("inset: a Biscuit field with no outline", function()
		local field = Theme.inset({ Name = "Stats" })
		expect.truthy(sameColor(field.BackgroundColor3, Theme.Colors.biscuit))
		expect.equal(field:FindFirstChildOfClass("UIStroke"), nil)
		expect.truthy(field:FindFirstChild("SD_Foam") ~= nil)
		field:Destroy()
	end)
end
