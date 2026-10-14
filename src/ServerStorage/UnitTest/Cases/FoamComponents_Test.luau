--!strict
-- FoamComponents_Test: the foam UI kit of StarterPlayerScripts.Client.UI.Components (Button kinds, CountBadge, Keycap,
-- Chip, ProgressBar, CoinCapsule, CoinIcon, and the restyled Toggle and Slider). Server only (ServerStorage.UnitTest).
-- Edit mode: everything is built unparented (or in a Folder) and destroyed; nothing is pressed, hovered or loaded, so
-- no frame effect starts.
-- Contract (foam UI restyle, spec 2026-10-09 "Components"; DESIGN §9.13 states, §11.2 touch targets, §2.11 names):
--   * every Button kind keeps its stable name and the Label / Reason parts, is at least the touch minimum tall and is a
--     foam surface (the SD_Foam gradient, one InkUI outline); its label follows the outlined-text rule (outlined white
--     on an accent at the Button kind, InkUI on Frosting or at the Chip kind);
--   * a tile is a fixed square with its icon above the label and an optional count badge; a row button carries its
--     keycap, icon and subtext; disabled shows the disabled foam, DisabledText and the reason in Ink2;
--   * Button.widthFor counts the kind's side padding; setWidth switches wrapping with the fixed width;
--   * CountBadge.text hides counts below 1 and caps them at 99; ProgressBar.clamp keeps 0..1; a Keycap reads its text
--     through KeyText; a Chip's text follows its face; the CoinCapsule is a touch-sized button around the coin disc.
-- Fill widths read back from a UDim (32-bit floats) are compared within UDIM_TOLERANCE (foam fix batch: 1e-9 failed).
-- Candy UI (UI overhaul 2026-10-11): every kind (and the new close kind) has the PlumInk outline plus the SD_Rim inner
-- rim; the outlined-text rule starts at the Chip kind (16 px), so tile and chip labels on an accent are outlined white;
-- the secondary kind is the plum neutral (white label); a press of a fixed-width kind keeps its shine under the content;
-- the Keycap is a light sticker with PlumInk letters.
-- UI FINAL R1 replaces that look (the look kit, plan work/ui/PLAN.md R1; `H:n` = the design's "Squishy Duels
-- HUD.dc.html" line n):
--   * every sticker kind (primary green, secondary cyan, cancel, cta, close) has one ink outline drawn inside the box
--     (no Candy rim), its bands Layout.stickerBands of the border, the surface's highlight and bevel and the lip; the
--     tile keeps its foam plate until R4 (one outer ink outline, the Theme.Foam.tile bands) in the sticker colours;
--     primary / secondary / cancel / cta labels show in capitals (Q5) and widthFor measures them so; the disabled
--     label and its reason are white with the ink outline (H:246), the reason readable over the ink lip of a 52 px
--     button too; only a fixed-width cta carries the sweep strip;
--   * CountBadge 32 px (H:102) and the yellow "!" (H:120); Chip 30 px (H:232); ProgressBar variants (Config.UI.Sticker
--     .bars); the two Toggle switches (H:197, H:437); the Slider's 36 px knob (H:445); the cream Keycap with the ink
--     lip (H:171); setSurface repaints a panel.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local function noop() end

-- UDim scales (and other Roblox property values) are stored as 32-bit floats: 0.4 reads back as 0.4000000059604645, so
-- they are compared within this tolerance (as the other Roblox-value tests do), never 1e-9.
local UDIM_TOLERANCE = 1e-4

-- The outlines of a surface (its UIStrokes but the SD_Rim inner rim).
local function strokesOf(object: Instance): number
	local n = 0
	for _, child in object:GetChildren() do
		if child:IsA("UIStroke") and child.Name ~= "SD_Rim" then
			n += 1
		end
	end
	return n
end

return function(t: Context)
	local expect = t.expect
	local Button = t.requireClient("UI/Components/Button")
	local Chip = t.requireClient("UI/Components/Chip")
	local CoinCapsule = t.requireClient("UI/Components/CoinCapsule")
	local CoinIcon = t.requireClient("UI/Components/CoinIcon")
	local CountBadge = t.requireClient("UI/Components/CountBadge")
	local Keycap = t.requireClient("UI/Components/Keycap")
	local ProgressBar = t.requireClient("UI/Components/ProgressBar")
	local Slider = t.requireClient("UI/Components/Slider")
	local Toggle = t.requireClient("UI/Components/Toggle")
	local Theme = t.requireClient("UI/Theme")
	local Layout = t.requireClient("UI/Layout")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local Strings = t.requireShared("Strings")
	local WHITE = Color3.new(1, 1, 1)
	local MIN_TARGET = Config.UI.Touch.minTarget
	local STICKER = Config.UI.Sticker

	t.test("every Button kind: stable name, Label and Reason, touch height, one ink outline, no rim", function()
		for _, kind in { "primary", "secondary", "cancel", "tile", "cta", "close" } do
			local button =
				Button.new({ name = "Test_" .. kind .. "Button", text = "Go", kind = kind, onActivated = noop })
			local root = button.root
			local style = Button.style(kind)
			expect.equal(root.Name, "Test_" .. kind .. "Button")
			expect.truthy(root:FindFirstChild("Label", true) ~= nil)
			expect.truthy(root:FindFirstChild("Reason", true) ~= nil)
			expect.truthy(root.Size.Y.Offset >= MIN_TARGET)
			expect.truthy(root:FindFirstChild("SD_Foam") ~= nil)
			expect.equal(root:FindFirstChild("SD_Rim"), nil)
			expect.equal(strokesOf(root), 1)
			local stroke = root:FindFirstChildOfClass("UIStroke") :: UIStroke
			expect.equal(stroke.Color, Theme.Colors.inkUI)
			expect.equal(stroke.Thickness, style.border)
			expect.equal(root.BackgroundTransparency, 0)
			if kind == "tile" then
				-- The tile's foam plate until R4: the outline outside the box, the foam tile bands.
				expect.falsy(style.inner)
				expect.equal(style.border, Theme.Stroke.ink)
				local foamTile = Theme.Foam.tile
				expect.equal(style.top + style.bevel + style.drop, foamTile.top + foamTile.bevel + foamTile.drop)
			else
				expect.truthy(style.inner)
				-- The bands: the border and the highlight on top, the bevel, the border and the lip at the bottom.
				local look = STICKER.surfaces[style.surface]
				local bands = Layout.stickerBands(style.border, look.highlightPx, look.bevelPx or 0, style.lip)
				expect.equal(style.top, bands.top)
				expect.equal(style.bevel, bands.bevel)
				expect.equal(style.drop, bands.drop)
			end
			expect.equal(button:getState(), "normal")
			button:destroy()
			expect.equal(root.Parent, nil)
		end
		-- The design's shapes (H:245, H:126, H:252).
		expect.equal(Button.style("primary").accent, "green")
		expect.equal(Button.style("primary").radius, STICKER.radius.button)
		expect.equal(Button.style("primary").lip, STICKER.lip.button)
		expect.equal(Button.style("cta").border, STICKER.border.heavy)
		expect.equal(Button.style("cta").lip, STICKER.lip.cta)
		expect.equal(Button.style("cta").surface, "duel")
		expect.equal(Button.style("close").height, 76)
		expect.equal(Button.style("cancel").accent, "cancel")
	end)

	t.test("labels: outlined white on a face, in capitals for the big kinds (Q5)", function()
		local primary = Button.new({ name = "P", text = "Change", kind = "primary", onActivated = noop })
		local label = primary.root:FindFirstChild("Label", true) :: TextLabel
		expect.equal(label.TextColor3, WHITE)
		expect.truthy((label:FindFirstChild("SD_Outline") :: UIStroke).Enabled)
		expect.equal(label.Text, if STICKER.buttonCaps then "CHANGE" else "Change")
		primary:setText("Equip")
		expect.equal(label.Text, if STICKER.buttonCaps then "EQUIP" else "Equip")
		primary:destroy()

		-- The plum neutral: outlined white too.
		-- UI FINAL R1: the secondary is the design's cyan now (H:247).
		local secondary = Button.new({ name = "S", text = "Inspect", onActivated = noop })
		local plain = secondary.root:FindFirstChild("Label", true) :: TextLabel
		expect.equal(plain.TextColor3, WHITE)
		secondary:destroy()

		-- A light face (the sticker accent): PlumInk, no outline.
		local light = Button.new({ name = "L", text = "Inspect", accent = "frosting", onActivated = noop })
		local dark = light.root:FindFirstChild("Label", true) :: TextLabel
		expect.equal(dark.TextColor3, Theme.Colors.inkUI)
		local outline = dark:FindFirstChild("SD_Outline") :: UIStroke?
		expect.truthy(outline == nil or not outline.Enabled)
		light:destroy()

		-- UI FINAL R1: every kind is outlined white on a face, a Small label too.
		local small = Button.new({ name = "C", text = "Go", kind = "primary", textKind = "Small", onActivated = noop })
		expect.equal((small.root:FindFirstChild("Label", true) :: TextLabel).TextColor3, WHITE)
		small:destroy()

		-- A tile and a close X keep their case (H:101 "Squishies").
		local tile = Button.new({ name = "T", text = "Boxes", kind = "tile", onActivated = noop })
		expect.equal((tile.root:FindFirstChild("Label", true) :: TextLabel).Text, "Boxes")
		tile:destroy()
		expect.equal(Button.displayText("Boxes", "tile"), "Boxes")
		expect.equal(Button.displayText("Go", "close"), "Go")
	end)

	t.test("a tile: a fixed square, the icon above the label, a count badge on the corner", function()
		local tile = Button.new({
			name = "Hud_BoxesButton",
			text = "Boxes",
			kind = "tile",
			accent = "lilac",
			icon = "boxes",
			badge = 3,
			onActivated = noop,
		})
		local root = tile.root
		expect.equal(root.AutomaticSize, Enum.AutomaticSize.None)
		expect.equal(root.Size.X.Offset, Button.TILE_SIZE) -- H:99: 118 × 104
		expect.equal(root.Size.Y.Offset, Button.TILE_HEIGHT)
		local content = root:FindFirstChild("Content") :: Frame
		expect.truthy(content:FindFirstChild("Icon") ~= nil and content:FindFirstChild("Label") ~= nil)
		local icon = content:FindFirstChild("Icon") :: Frame
		local label = content:FindFirstChild("Label") :: TextLabel
		expect.truthy(icon.LayoutOrder < label.LayoutOrder)
		local badge = root:FindFirstChild("Badge") :: Frame
		expect.truthy(badge.Visible)
		expect.equal((badge:FindFirstChild("Count") :: TextLabel).Text, "3")
		tile:setBadge(0)
		expect.falsy(badge.Visible)
		-- A tile label is the Chip kind: outlined white on the accent (Candy UI: the rule starts at 16 px).
		expect.equal(label.TextColor3, WHITE)
		-- UI FINAL R1: no shine stripes on a tile (the sweep strip is the cta's).
		expect.equal(root:FindFirstChild("SD_Shine"), nil)
		tile:destroy()

		-- The close kind: a square red X, its label kept but hidden.
		-- UI FINAL R1: 76 by default, its picture 46 / 76 of it (H:252).
		local close = Button.new({ name = "Test_CloseButton", text = "Close", kind = "close", onActivated = noop })
		expect.equal(close.root.Size.X.Offset, close.root.Size.Y.Offset)
		expect.equal(close.root.Size.Y.Offset, 76)
		expect.equal((close.root:FindFirstChild("Icon", true) :: Frame).Size.X.Offset, 46)
		local small =
			Button.new({ name = "Small_CloseButton", text = "Close", kind = "close", height = 52, onActivated = noop })
		expect.equal((small.root:FindFirstChild("Icon", true) :: Frame).Size.X.Offset, math.floor(52 * 46 / 76))
		small:destroy()
		local closeLabel = close.root:FindFirstChild("Label", true) :: TextLabel
		expect.equal(closeLabel.Text, "Close")
		expect.falsy(closeLabel.Visible)
		expect.truthy(close.root:FindFirstChild("Icon", true) ~= nil)
		close:setState("normal")
		expect.falsy(closeLabel.Visible)
		close:destroy()

		local plain = Button.new({ name = "NoBadge", text = "Go", onActivated = noop })
		plain:setBadge(0)
		expect.equal(plain.root:FindFirstChild("Badge"), nil) -- no badge built for nothing
		plain:setBadge(2)
		expect.truthy((plain.root:FindFirstChild("Badge") :: Frame).Visible)
		plain:destroy()
	end)

	t.test("a row button carries its keycap, icon and subtext", function()
		local cta = Button.new({
			name = "Hud_DuelButton",
			text = "DUEL",
			kind = "cta",
			icon = "duel",
			subtext = "",
			keycap = "V",
			onActivated = noop,
		})
		expect.truthy(cta.root:FindFirstChild("Line", true) ~= nil)
		local line = cta.root:FindFirstChild("Line", true) :: Frame
		expect.truthy(line:FindFirstChild("Icon") ~= nil)
		local keycap = line:FindFirstChild("Keycap") :: Frame
		expect.truthy(keycap.Visible)
		local sub = line:FindFirstChild("Subtext", true) :: TextLabel
		expect.falsy(sub.Visible) -- reserved, hidden
		cta:setSubtext("Join")
		expect.truthy(sub.Visible)
		expect.equal(sub.Text, "Join")
		cta:setKeycap(nil)
		expect.falsy(keycap.Visible)
		expect.truthy(cta.root.Size.Y.Offset >= Button.CTA_HEIGHT)
		cta:destroy()
	end)

	t.test("disabled: the disabled lilac (H:246), the label and the reason white with the ink outline", function()
		local button = Button.new({ name = "Shop_BuyButton", text = "Buy", kind = "primary", onActivated = noop })
		button:setState("disabled", "Need 5 more Coins")
		expect.equal(button:getState(), "disabled")
		local label = button.root:FindFirstChild("Label", true) :: TextLabel
		local reason = button.root:FindFirstChild("Reason", true) :: TextLabel
		expect.equal(label.TextColor3, Theme.Colors.disabledText)
		expect.truthy((label:FindFirstChild("SD_Outline") :: UIStroke).Enabled)
		expect.truthy(reason.Visible)
		expect.equal(reason.Text, "Need 5 more Coins") -- the reason keeps its case
		-- White with the ink outline: it reads on the lilac face and over the ink lip alike (a 52 px button's reason
		-- line reaches the lip at large text sizes).
		expect.equal(reason.TextColor3, WHITE)
		expect.truthy((reason:FindFirstChild("SD_Outline") :: UIStroke).Enabled)
		expect.equal((button.root:FindFirstChildOfClass("UIStroke") :: UIStroke).Color, Theme.Colors.disabledStroke)
		local points = (button.root:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints
		local lilac = false
		for _, point in points do
			lilac = lilac or point.Value == Palette.StickerDisabledEnd
		end
		expect.truthy(lilac)
		button:setState("normal")
		expect.falsy(reason.Visible)
		expect.equal(label.TextColor3, WHITE)
		expect.equal((button.root:FindFirstChildOfClass("UIStroke") :: UIStroke).Color, Theme.Colors.inkUI)
		button:destroy()
	end)

	t.test("a 52 px button disabled with a reason: the reason is outlined white, readable over the ink lip", function()
		local button = Button.new({
			name = "Quests_ClaimButton",
			text = "Claim",
			kind = "primary",
			height = 52,
			onActivated = noop,
		})
		button:setState("disabled", "Finish the quest first")
		expect.equal(button.root.Size.Y.Offset, math.max(52, MIN_TARGET))
		local reason = button.root:FindFirstChild("Reason", true) :: TextLabel
		expect.truthy(reason.Visible)
		expect.equal(reason.TextColor3, WHITE)
		local outline = reason:FindFirstChild("SD_Outline") :: UIStroke?
		expect.truthy(outline ~= nil and outline.Enabled)
		expect.equal((outline :: UIStroke).Thickness, Theme.outlinePx("Small"))
		button:destroy()
	end)

	t.test("widthFor counts the kind's padding; setWidth switches wrapping", function()
		local wide = Button.widthFor("Go", nil, "Button", "primary")
		local narrow = Button.widthFor("Go", nil, "Button", "tile")
		-- "Go" is measured in capitals for the primary, as it is for the tile (Q5).
		local capsWidth = Theme.textWidth(Button.displayText("Go", "primary"), "Button")
		local plainWidth = Theme.textWidth("Go", "Button")
		expect.near(
			(wide - capsWidth) - (narrow - plainWidth),
			2 * (Button.style("primary").paddingX - Button.style("tile").paddingX),
			1
		)
		expect.equal(Button.widthFor("Go"), wide) -- the default kind has the primary padding and capitals
		expect.equal(Button.style("tile").bevel, Theme.Foam.tile.bevel) -- the tile keeps its foam plate until R4
		expect.equal(Button.style("cta").drop, STICKER.border.heavy + STICKER.lip.cta)
		expect.equal(Button.style("nope" :: any).accent, "cyan")
		expect.equal(Button.style("close").accent, "red")

		local button = Button.new({ name = "W", text = "Confirm: 25,000 Coins", onActivated = noop })
		local label = button.root:FindFirstChild("Label", true) :: TextLabel
		expect.equal(button.root.AutomaticSize, Enum.AutomaticSize.X)
		expect.falsy(label.TextWrapped)
		button:setWidth(120)
		expect.equal(button.root.AutomaticSize, Enum.AutomaticSize.None)
		expect.equal(button.root.Size.X.Offset, 120)
		expect.truthy(label.TextWrapped)
		button:setWidth(nil)
		expect.equal(button.root.AutomaticSize, Enum.AutomaticSize.X)
		expect.falsy(label.TextWrapped)
		button:destroy()

		-- UI FINAL R1: only a cta carries the sweep strip, and only while its width is fixed (an overlay would inflate
		-- an automatic width); a primary never does.
		local primary = Button.new({ name = "P", text = "Buy", kind = "primary", onActivated = noop })
		primary:setWidth(160)
		expect.equal(primary.root:FindFirstChild("SD_Shine"), nil)
		primary:destroy()
		local cta = Button.new({ name = "Hud_DuelButton", text = "DUEL", kind = "cta", onActivated = noop })
		expect.equal(cta.root:FindFirstChild("SD_Shine"), nil)
		cta:setWidth(350)
		local strip = cta.root:FindFirstChild("SD_Shine") :: Frame
		expect.truthy(cta.root:FindFirstChild("SD_Shine") ~= nil)
		expect.equal(strip.ZIndex, 0)
		local gradient = strip:FindFirstChildOfClass("UIGradient") :: UIGradient
		expect.equal(gradient.Offset.X, -1) -- out of sight until sweep()
		cta:setWidth(360)
		expect.equal(cta.root:FindFirstChild("SD_Shine"), strip) -- kept, not rebuilt
		cta:setWidth(nil)
		expect.equal(cta.root:FindFirstChild("SD_Shine"), nil)
		cta:destroy()
	end)

	t.test("CountBadge: hidden below 1, capped at 99", function()
		expect.equal(CountBadge.text(0), nil)
		expect.equal(CountBadge.text(-2), nil)
		expect.equal(CountBadge.text(0 / 0), nil)
		expect.equal(CountBadge.text(nil), nil)
		expect.equal(CountBadge.text(1.7), "1")
		expect.equal(CountBadge.text(42), "42")
		expect.equal(CountBadge.text(150), "99")
		local badge = CountBadge.new({ name = "Badge" })
		expect.falsy(badge.root.Visible)
		badge:setCount(5)
		expect.truthy(badge.root.Visible)
		expect.equal(badge.label.Text, "5")
		badge:setText(nil)
		expect.falsy(badge.root.Visible)
		-- H:102: at least 32 px, a 3 px ink border, the badge red, the number white (18 px, outline 1.5).
		expect.equal(CountBadge.SIZE_PX, 32)
		expect.equal(badge.root.Size.Y.Offset, 32)
		expect.equal((badge.root:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, STICKER.border.thin)
		expect.equal(badge.label.TextColor3, WHITE)
		expect.equal(badge.label.TextSize, Theme.textSize("Body"))
		expect.equal((badge.label:FindFirstChild("SD_Outline") :: UIStroke).Thickness, 1.5)
		local foam = (badge.root:FindFirstChild("SD_Foam") :: UIGradient).Color
		local red = false
		for _, point in foam.Keypoints do
			red = red or point.Value == Palette.StickerRedEnd
		end
		expect.truthy(red)
		badge:destroy()
		-- H:120: the yellow "!" with its 20 px mark.
		local daily = CountBadge.new({ name = "DailyBadge", accent = "yellow" })
		daily:setText("!")
		expect.equal(daily.label.TextSize, Theme.textSize("Button"))
		expect.equal((daily.label:FindFirstChild("SD_Outline") :: UIStroke).Thickness, 2)
		-- Its own surface: the top highlight 2 px at .6 (H:120), not the red badge's .5.
		local mark = STICKER.surfaces.badgeMark
		expect.equal(mark.highlightAlpha, 0.6)
		local top = (daily.root:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints[1].Value
		local want = Palette.StickerYellowTop:Lerp(WHITE, mark.highlightAlpha)
		expect.near(top.R, want.R, 1e-3)
		expect.near(top.G, want.G, 1e-3)
		expect.near(top.B, want.B, 1e-3)
		daily:destroy()
	end)

	t.test("ProgressBar: 0..1, the fill hides at 0; the design's variants", function()
		expect.equal(ProgressBar.clamp(0 / 0), 0)
		expect.equal(ProgressBar.clamp(-1), 0)
		expect.equal(ProgressBar.clamp(2), 1)
		expect.equal(ProgressBar.clamp(0.25), 0.25)
		local bar = ProgressBar.new({ name = "Bar" })
		expect.falsy(bar.fill.Visible)
		expect.equal(bar:get(), 0)
		bar:set(0.5)
		expect.truthy(bar.fill.Visible)
		expect.near(bar.fill.Size.X.Scale, 0.5, UDIM_TOLERANCE)
		bar:set(0)
		expect.falsy(bar.fill.Visible)
		expect.equal(bar.root.BackgroundColor3, Theme.Colors.track) -- Candy UI: the darkest surface
		-- UI FINAL R1: the default "stat" bar (H:240), the trough with the deep ink border, 3 px.
		local stroke = bar.root:FindFirstChildOfClass("UIStroke") :: UIStroke
		expect.equal(stroke.Thickness, STICKER.bars.stat.border)
		expect.equal(stroke.Color, Palette.StickerInkDeep)
		bar:destroy()
		-- The Grip bar (H:84-85): a white trough at .7 with the ink border, its own green fill.
		local grip = ProgressBar.new({ name = "Grip", variant = "grip", fraction = 0.5 })
		expect.equal(grip.root.BackgroundColor3, WHITE)
		expect.near(grip.root.BackgroundTransparency, 1 - STICKER.bars.grip.troughAlpha, UDIM_TOLERANCE)
		expect.equal((grip.root:FindFirstChildOfClass("UIStroke") :: UIStroke).Color, Theme.Colors.inkUI)
		local fillPoints = (grip.fill:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints
		expect.equal(fillPoints[#fillPoints].Value, Palette.StickerGripEnd)
		grip:destroy()
		-- The quest bar (H:367): the trough's shade along its top.
		local quest = ProgressBar.new({ name = "Quest", variant = "quest", heightPx = 20 })
		expect.truthy(quest.root:FindFirstChild("SD_Foam") ~= nil)
		quest:destroy()
		-- An unknown variant is the stat bar.
		local odd = ProgressBar.new({ name = "Odd", variant = "nope" :: any })
		expect.equal(odd.root.BackgroundColor3, Theme.Colors.track)
		odd:destroy()
	end)

	t.test("Keycap reads its key through KeyText and hides without one; the cream key with the ink lip", function()
		local cap = Keycap.new({ name = "Keycap", key = "controls.key.inspectKeyboard" })
		expect.equal(cap.label.Text, Strings.controls.key.inspectKeyboard)
		expect.truthy(cap.root.Visible)
		cap:setText(nil)
		expect.falsy(cap.root.Visible)
		cap:setKey("controls.key.inspectGamepad")
		expect.equal(cap.label.Text, Strings.controls.key.inspectGamepad)
		expect.equal(cap.label.TextColor3, Theme.Colors.inkUI) -- Candy UI: a light sticker key
		-- H:171: the cream face, a 3 px ink border, radius 10, the ink lip at the bottom; still 24 at least (the dock).
		expect.equal(cap.root.Size.Y.Offset, Keycap.SIZE_PX)
		expect.equal((cap.root:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, STICKER.border.thin)
		expect.equal(
			(cap.root:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius,
			UDim.new(0, STICKER.radius.chip)
		)
		local points = (cap.root:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints
		expect.equal(points[1].Value, Palette.Frosting)
		expect.equal(points[#points].Value, Theme.Colors.inkUI)
		cap:destroy()
	end)

	t.test("Chip: the ink on the cream face, the given colour on a rarity face; 30 px, the border inside", function()
		local chip = Chip.new({ name = "EquippedChip", text = "Equipped" })
		expect.equal(chip.label.TextColor3, Theme.Colors.inkUI)
		expect.equal(chip.root.Size.Y.Offset, 30) -- H:232
		expect.equal((chip.root:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, STICKER.border.thin)
		chip:setAccent("strawberry")
		expect.equal(chip.label.TextColor3, WHITE) -- Candy UI: the Chip kind is outlined white on an accent
		chip:setAccent("frosting")
		expect.equal(chip.label.TextColor3, Theme.Colors.inkUI) -- a light accent: PlumInk
		chip:setAccent("gold")
		expect.equal(chip.label.TextColor3, WHITE) -- UI FINAL R1: gold carries white outlined text too (H:498)
		chip:setColor(Color3.fromHex("#7C3AED"), WHITE)
		expect.equal(chip.label.TextColor3, WHITE)
		chip:setText("Epic")
		expect.equal(chip.label.Text, "Epic")
		chip:destroy()
	end)

	t.test("CoinCapsule and CoinIcon: a touch-sized coin button and a foam coin", function()
		local capsule = CoinCapsule.new({ name = "Hud_CoinsButton", text = "0" })
		expect.equal(capsule.root.Name, "Hud_CoinsButton")
		expect.truthy(capsule.root:IsA("TextButton"))
		expect.truthy(capsule.root.Size.Y.Offset >= MIN_TARGET)
		expect.equal(capsule.disc.root.Parent, capsule.root)
		expect.equal(capsule.capsule.Parent, capsule.root)
		capsule:setText("12,450")
		expect.equal(capsule.label.Text, "12,450")
		capsule:destroy()

		local coin = CoinIcon.new({ name = "Coin", sizePx = 22 })
		expect.truthy(coin.root:FindFirstChild("Disc") ~= nil)
		local disc = coin.root:FindFirstChild("Disc") :: Frame
		expect.truthy(disc:FindFirstChild("SD_Foam") ~= nil)
		expect.truthy(disc:FindFirstChild("Ring") ~= nil)
		expect.equal((disc:FindFirstChildOfClass("UIStroke") :: UIStroke).Color, Theme.Colors.inkUI)
		coin:destroy()
	end)

	t.test("Toggle and Slider keep their parts; the design's two switches and the volume slider", function()
		local toggle =
			Toggle.new({ name = "Settings_ShowTipsToggle", text = "Show tips", value = true, onChanged = noop })
		expect.truthy(toggle.root:FindFirstChild("Knob", true) ~= nil)
		local knob = toggle.root:FindFirstChild("Knob", true) :: Frame
		expect.truthy(knob:FindFirstChild("SD_Foam") ~= nil)
		local switch = toggle.root:FindFirstChild("Switch") :: Frame
		local small = STICKER.toggles.small -- H:197
		expect.equal(switch.Size, UDim2.fromOffset(small.width, small.height))
		expect.equal(switch.BackgroundColor3, Palette.StickerToggleOnTop)
		expect.equal(knob.Position, UDim2.fromOffset(small.border + small.knobOn, small.border + small.knobTop))
		expect.truthy(toggle.root:FindFirstChild("KnobDrop", true) ~= nil)
		toggle:setValue(false)
		expect.equal(switch.BackgroundColor3, Palette.StickerSwitchOff)
		expect.equal(knob.Position, UDim2.fromOffset(small.border + small.knobOff, small.border + small.knobTop))
		expect.truthy(toggle.root.Size.Y.Offset >= MIN_TARGET) -- the hit box
		toggle:destroy()
		-- H:437: the Settings switch, 80 × 42 with a bordered knob.
		local large = STICKER.toggles.large
		local big =
			Toggle.new({ name = "Big", text = "Screen shake", value = true, variant = "large", onChanged = noop })
		local bigSwitch = big.root:FindFirstChild("Switch") :: Frame
		expect.equal(bigSwitch.Size, UDim2.fromOffset(large.width, large.height))
		local bigKnob = big.root:FindFirstChild("Knob", true) :: Frame
		expect.equal(bigKnob.Size, UDim2.fromOffset(large.knob, large.knob))
		expect.equal((bigKnob:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, large.knobBorder)
		expect.equal(big.root:FindFirstChild("KnobDrop", true), nil)
		expect.equal(
			Toggle.widthFor("Screen shake", "large") - Toggle.widthFor("Screen shake"),
			large.width - small.width
		)
		big:destroy()

		local slider = Slider.new({ name = "S", min = 0, max = 100, step = 5, value = 40, onChanged = noop })
		local fill = slider.root:FindFirstChild("Fill", true) :: Frame
		expect.truthy(fill:FindFirstChild("SD_Foam") ~= nil)
		expect.near(fill.Size.X.Scale, 0.4, UDIM_TOLERANCE) -- stored as 0.4000000059604645
		local sliderKnob = slider.root:FindFirstChild("Knob", true) :: Frame
		expect.truthy(slider.root:FindFirstChild("Knob", true) ~= nil)
		-- H:444-445: the 20 px track (its 3 px border outside a 14 px bar), the 36 px knob with its 3 px lip.
		local bar = slider.root:FindFirstChild("Bar", true) :: Frame
		expect.equal(bar.Size.Y.Offset + 2 * (bar:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, 20)
		expect.equal(sliderKnob.Size, UDim2.fromOffset(36, 36 + STICKER.lip.bar))
		local fillPoints = (fill:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints
		expect.equal(fillPoints[#fillPoints].Value, Palette.StickerVolumeEnd)
		slider:destroy()
	end)

	t.test("setSurface repaints a Theme.panel in the exact colours (a later round's state faces)", function()
		local panel = Theme.panel({ Name = "Card", Size = UDim2.fromOffset(120, 160) })
		expect.equal(panel.BackgroundColor3, Theme.Colors.panel)
		expect.truthy(Theme.setSurface(panel, Theme.accentColors("gold", true)))
		expect.equal(panel.BackgroundColor3, WHITE)
		local points = (panel:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints
		local gold = Theme.Accents.gold
		local sawMid = false
		for _, point in points do
			sawMid = sawMid or point.Value == gold.mid
		end
		expect.truthy(sawMid)
		panel:Destroy()
	end)
end
