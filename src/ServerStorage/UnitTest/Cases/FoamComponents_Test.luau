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
-- UI FINAL R2 (plan work/ui/PLAN.md R2: P1, P2, P7-P9, P11, P12, T3, T4, PR4, PR5, PR24): the root is a transparent
-- hit box and the drawn button its SD_Visual child (button.visual: the face, bands, content, badge and shine); the
-- frame is the face + the lip (a close X 76 x 82); the cta's shine strip is built with it and crosses by itself
-- (Anim/UiIdle skips an unparented strip, so nothing moves here); the bars draw their border inside their height.
-- UI FINAL R4 (plan R4; P13, PR1, PR6, G4.22, G4.23): the tile is the faceless nav sticker (no face, no outline, no
-- bands; its picture in SD_Bob > SD_Wiggle, the label drawn over it, the badge inside it at right 8, top 0, H:99-102)
-- with the 0 / -12 / 9 / -4 / 0 hover wiggle (Button.wiggleAt); the search bar's cancel X is a 48 px face in the 52 px
-- hit box (H:145); the coin pill is the design's 58 px pill with its 5 px lip and the 78 px coin over it (H:75-81);
-- SegmentedTabs is the testers' TDM / FFA picker (N:144-162).

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
	local Tweens = t.requireClient("Anim/Tweens")
	local Slider = t.requireClient("UI/Components/Slider")
	local Toggle = t.requireClient("UI/Components/Toggle")
	local Theme = t.requireClient("UI/Theme")
	local Layout = t.requireClient("UI/Layout")
	local Config = t.requireShared("Config")
	local AssetTable = t.requireShared("AssetTable")
	local Palette = t.requireShared("Art/Palette")
	local Strings = t.requireShared("Strings")
	local WHITE = Color3.new(1, 1, 1)
	local MIN_TARGET = Config.UI.Touch.minTarget
	local STICKER = Config.UI.Sticker
	-- UI FINAL R2: the idle loops (Anim/UiIdle: the shine strips, the rays) run on a private Scheduler here, so no
	-- frame event is connected (as Scheduler_Test).
	t.requireClient("Anim/UiIdle").setScheduler(t.requireClient("Anim/Scheduler").new(false))

	t.test("every Button kind: stable name, Label and Reason, touch height, one ink outline, no rim", function()
		for _, kind in { "primary", "secondary", "cancel", "tile", "cta", "close" } do
			local button =
				Button.new({ name = "Test_" .. kind .. "Button", text = "Go", kind = kind, onActivated = noop })
			local root = button.root
			local visual = button.visual -- UI FINAL R2 (T3): the drawn button
			local style = Button.style(kind)
			expect.equal(root.Name, "Test_" .. kind .. "Button")
			expect.truthy(root:FindFirstChild("Label", true) ~= nil)
			expect.truthy(root:FindFirstChild("Reason", true) ~= nil)
			expect.truthy(root.Size.Y.Offset >= MIN_TARGET)
			expect.equal(visual:FindFirstChild("SD_Rim"), nil)
			if kind == "tile" then
				-- UI FINAL R4 (P13): the faceless nav sticker: no face, no outline, no bands (its picture is the
				-- button).
				expect.truthy(style.faceless)
				expect.equal(visual:FindFirstChild("SD_Foam"), nil)
				expect.equal(strokesOf(visual), 0)
				expect.equal(visual.BackgroundTransparency, 1)
				expect.equal(style.border, 0)
				expect.equal(style.top + style.bevel + style.drop, 0)
			else
				expect.truthy(visual:FindFirstChild("SD_Foam") ~= nil)
				expect.equal(strokesOf(visual), 1)
				local stroke = visual:FindFirstChildOfClass("UIStroke") :: UIStroke
				expect.equal(stroke.Color, Theme.Colors.inkUI)
				expect.equal(stroke.Thickness, style.border)
				expect.equal(visual.BackgroundTransparency, 0)
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
		local content = tile.visual:FindFirstChild("Content") :: Frame
		expect.truthy(content:FindFirstChild("Icon") ~= nil and content:FindFirstChild("Label") ~= nil)
		local icon = content:FindFirstChild("Icon") :: Frame
		local label = content:FindFirstChild("Label") :: TextLabel
		expect.truthy(icon.LayoutOrder < label.LayoutOrder)
		local badge = tile.visual:FindFirstChild("Badge") :: Frame
		expect.truthy(badge.Visible)
		expect.equal((badge:FindFirstChild("Count") :: TextLabel).Text, "3")
		tile:setBadge(0)
		expect.falsy(badge.Visible)
		-- A tile label is the Chip kind: outlined white on the accent (Candy UI: the rule starts at 16 px).
		expect.equal(label.TextColor3, WHITE)
		-- UI FINAL R1: no shine stripes on a tile (the sweep strip is the cta's).
		expect.equal(tile.visual:FindFirstChild("SD_Shine"), nil)
		-- UI FINAL R4 (P13, H:99-102): no face; the picture in SD_Bob > SD_Wiggle (the bob and the hover wiggle), the
		-- label drawn over it, the badge inside the sticker (its right edge 8 in, its top on the tile's).
		expect.equal(tile.visual.BackgroundTransparency, 1)
		expect.equal(tile.visual:FindFirstChild("SD_Foam"), nil)
		local bob = icon:FindFirstChild("SD_Bob")
		expect.truthy(bob ~= nil and bob:FindFirstChild("SD_Wiggle") ~= nil)
		expect.equal(label.ZIndex, 2)
		-- Centre-anchored at its resting 32 px, so its sdBadge pop (a UIScale) grows about its centre (H:32).
		expect.equal(badge.AnchorPoint, Vector2.new(0.5, 0.5))
		expect.equal(badge.Position.Y.Offset, STICKER.hud.nav.badgeTop + CountBadge.SIZE_PX / 2)
		expect.equal(badge.Position.X.Scale, 1)
		tile:destroy()
		-- The hover wiggle (PR6, H:639): 0 / -12 / 9 / -4 / 0 evenly over navWiggle.ms, linear between; 0 outside.
		expect.equal(Button.wiggleAt(0), 0)
		expect.near(Button.wiggleAt(0.125), -6, 1e-9)
		expect.near(Button.wiggleAt(0.25), -12, 1e-9)
		expect.near(Button.wiggleAt(0.5), 9, 1e-9)
		expect.near(Button.wiggleAt(0.75), -4, 1e-9)
		expect.equal(Button.wiggleAt(1), 0)
		expect.equal(Button.wiggleAt(1.5), 0)

		-- The close kind: a square red X, its label kept but hidden.
		-- UI FINAL R1: 76 by default, its picture 46 / 76 of it (H:252).
		local close = Button.new({ name = "Test_CloseButton", text = "Close", kind = "close", onActivated = noop })
		-- UI FINAL R2 (P1): the face wide (76), the face + the lip tall (82).
		expect.equal(close.root.Size.X.Offset, 76)
		expect.equal(close.root.Size.Y.Offset, 76 + STICKER.lip.closeX)
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
		-- UI FINAL R4 (G4.22, H:145): the search bar's cancel X: a 48 px face (+ its 4 px lip) in the 52 px hit box.
		local hud = STICKER.hud.cancelX
		local cancel = Button.new({
			name = "Queue_CancelButton",
			text = "Cancel",
			kind = "close",
			accent = "cancelX",
			height = hud.face,
			radius = hud.radius,
			border = hud.border,
			lip = hud.lip,
			highlight = { px = hud.highlightPx, a = hud.highlightAlpha },
			bevel = { px = 0, a = 0 },
			iconSize = hud.iconPx,
			onActivated = noop,
		})
		expect.equal(cancel.root.Size, UDim2.fromOffset(MIN_TARGET, MIN_TARGET))
		expect.equal(cancel.visual.Size, UDim2.new(0, hud.face, 1, 0))
		expect.equal((cancel.root:FindFirstChild("Icon", true) :: Frame).Size.X.Offset, hud.iconPx)
		expect.equal((cancel.visual:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, hud.border)
		cancel:destroy()
		expect.equal(Theme.Accents.cancelX.top, Palette.StickerCancelRedTop) -- #FF8A8A -> #F0344A
		expect.equal(Theme.Accents.cancelX.shade, Palette.StickerCloseEnd)

		local plain = Button.new({ name = "NoBadge", text = "Go", onActivated = noop })
		plain:setBadge(0)
		expect.equal(plain.visual:FindFirstChild("Badge"), nil) -- no badge built for nothing
		plain:setBadge(2)
		expect.truthy((plain.visual:FindFirstChild("Badge") :: Frame).Visible)
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
		expect.equal((button.visual:FindFirstChildOfClass("UIStroke") :: UIStroke).Color, Theme.Colors.disabledStroke)
		local points = (button.visual:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints
		local lilac = false
		for _, point in points do
			lilac = lilac or point.Value == Palette.StickerDisabledEnd
		end
		expect.truthy(lilac)
		button:setState("normal")
		expect.falsy(reason.Visible)
		expect.equal(label.TextColor3, WHITE)
		expect.equal((button.visual:FindFirstChildOfClass("UIStroke") :: UIStroke).Color, Theme.Colors.inkUI)
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
		expect.equal(button.root.Size.Y.Offset, math.max(52 + STICKER.lip.button, MIN_TARGET)) -- UI FINAL R2 (P1)
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
		expect.equal(Button.style("tile").bevel, 0) -- UI FINAL R4 (P13): the faceless sticker has no bands
		expect.equal(Button.style("cta").drop, STICKER.border.heavy + STICKER.lip.cta)
		expect.equal(Button.style("nope" :: any).accent, "cyan")
		expect.equal(Button.style("close").accent, "red")

		local button = Button.new({ name = "W", text = "Confirm: 25,000 Coins", onActivated = noop })
		local label = button.root:FindFirstChild("Label", true) :: TextLabel
		-- UI FINAL R2 (T3): the content's natural width sizes the root (the hit box has no AutomaticSize of its own).
		local content = button.visual:FindFirstChild("Content") :: Frame
		expect.equal(button.root.AutomaticSize, Enum.AutomaticSize.None)
		expect.equal(content.AutomaticSize, Enum.AutomaticSize.X)
		expect.falsy(label.TextWrapped)
		button:setWidth(120)
		expect.equal(content.AutomaticSize, Enum.AutomaticSize.None)
		expect.equal(button.root.Size.X.Offset, 120)
		expect.truthy(label.TextWrapped)
		button:setWidth(nil)
		expect.equal(content.AutomaticSize, Enum.AutomaticSize.X)
		expect.falsy(label.TextWrapped)
		button:destroy()

		-- UI FINAL R2 (P2): the cta's strip is built with it (it crosses by itself, Anim/UiIdle) and kept through any
		-- width (it sits in SD_Visual, so it never inflates an automatic width); a primary never has one.
		local primary = Button.new({ name = "P", text = "Buy", kind = "primary", onActivated = noop })
		primary:setWidth(160)
		expect.equal(primary.root:FindFirstChild("SD_Shine"), nil)
		expect.equal(primary.visual:FindFirstChild("SD_Shine"), nil)
		primary:destroy()
		local cta = Button.new({ name = "Hud_DuelButton", text = "DUEL", kind = "cta", onActivated = noop })
		local strip = cta.visual:FindFirstChild("SD_Shine") :: Frame
		expect.truthy(cta.visual:FindFirstChild("SD_Shine") ~= nil)
		expect.equal(strip.ZIndex, 0)
		cta:setWidth(350)
		expect.equal(cta.visual:FindFirstChild("SD_Shine"), strip) -- kept, not rebuilt
		cta:setWidth(nil)
		expect.equal(cta.visual:FindFirstChild("SD_Shine"), strip)
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

	t.test("CoinCapsule (UI FINAL R4, H:75-81) and CoinIcon: the design's coin pill and a foam coin", function()
		local hud = STICKER.hud.coins
		local border = STICKER.border.normal
		local capsule = CoinCapsule.new({ name = "Hud_CoinsButton", text = "0" })
		expect.equal(capsule.root.Name, "Hud_CoinsButton")
		expect.truthy(capsule.root:IsA("TextButton"))
		-- G4.23: the 58 px face and the 5 px lip, 63 tall (>= the touch minimum); at least 220 wide (H:75).
		expect.equal(capsule.root.Size.Y.Offset, math.max(hud.face + STICKER.lip.button, MIN_TARGET))
		expect.equal(capsule.root.Size.X.Offset, hud.minWidth)
		expect.equal(capsule.visual.Name, "SD_Visual")
		expect.equal(capsule.visual.Parent, capsule.root)
		expect.equal(capsule.capsule.Parent, capsule.visual)
		expect.truthy(capsule.capsule:FindFirstChild("SD_Foam") ~= nil)
		expect.equal(strokesOf(capsule.capsule), 1)
		-- The number after the 68 px padding, 10 on the right, both inside the 4 px border (H:18 border-box).
		local padding = capsule.capsule:FindFirstChildOfClass("UIPadding") :: UIPadding
		expect.equal(padding.PaddingLeft.Offset, border + hud.padLeft)
		expect.equal(padding.PaddingRight.Offset, border + hud.padRight)
		-- The 78 px coin over the face at (-14, -12) of its padding edge (H:78), in its sdCoin holder > Flip.
		local coin = capsule.visual:FindFirstChild("Coin") :: Frame
		expect.equal(coin.Size, UDim2.fromOffset(hud.coinPx, hud.coinPx))
		expect.equal(coin.Position, UDim2.fromOffset(border + hud.coinX, border + hud.coinY))
		expect.truthy(coin.ZIndex > capsule.capsule.ZIndex)
		local flip = capsule.disc.root.Parent :: Frame
		expect.equal(flip.Name, "Flip")
		expect.equal((flip.Parent :: Frame).Name, "SD_Idle")
		-- A longer number widens the pill.
		capsule:setText("999.99M")
		expect.equal(capsule.label.Text, "999.99M")
		local wide = math.ceil(2 * border + hud.padLeft + Theme.textWidth("999.99M", "Coin") + hud.padRight)
		expect.equal(capsule.root.Size.X.Offset, math.max(hud.minWidth, wide))
		-- The squash, the shake and a flash start without an error (nothing is drawn in Edit mode).
		capsule:squash(0.8)
		capsule:shake()
		capsule:flash(true, false)
		capsule:destroy()
		expect.equal(capsule.root.Parent, nil)
		-- The flip's track (H:566-571): a whole turn, its white copy at .9 at the peak (brightness 1.9).
		local FLASH = Config.UI.motion.coinCounter.flash
		local peak = CoinCapsule.flashTrack(FLASH.flipFrames, 0.35, "linear")
		expect.near(peak.rot :: number, 180, 1e-6)
		expect.near(peak.scale :: number, 1.45, 1e-6)
		expect.near(peak.alpha :: number, 0.9, 1e-6)
		local done = CoinCapsule.flashTrack(FLASH.flipFrames, 1, "linear")
		expect.near(done.rot :: number, 360, 1e-6)
		expect.near(done.alpha :: number, 0, 1e-6)

		local coin = CoinIcon.new({ name = "Coin", sizePx = 22 })
		local coinImage = AssetTable.image("img.coin")
		if coinImage then -- UI FINAL R10: the design's coin picture (uploaded 2026-10-14) replaces the drawn disc
			expect.equal((coin.root:FindFirstChild("Image") :: ImageLabel).Image, coinImage)
			expect.equal(coin.root:FindFirstChild("Disc"), nil)
		else
			expect.truthy(coin.root:FindFirstChild("Disc") ~= nil)
			local disc = coin.root:FindFirstChild("Disc") :: Frame
			expect.truthy(disc:FindFirstChild("SD_Foam") ~= nil)
			expect.truthy(disc:FindFirstChild("Ring") ~= nil)
			expect.equal((disc:FindFirstChildOfClass("UIStroke") :: UIStroke).Color, Theme.Colors.inkUI)
		end
		coin:destroy()
	end)

	t.test("SegmentedTabs (UI FINAL R4, N:144-162): the testers' TDM / FFA picker, one tab picked", function()
		local SegmentedTabs = t.requireClient("UI/Components/SegmentedTabs")
		local picked: { string } = {}
		local tabs = SegmentedTabs.new({
			name = "Hud_DuelModes",
			tabs = {
				{
					id = "tdm",
					label = "TEAM DEATHMATCH",
					chip = "6v6",
					short = "TEAM 6v6",
					rotation = 10,
					stops = { { at = 0, color = WHITE }, { at = 1, color = Palette.StickerTdmBlue } },
				},
				{
					id = "ffa",
					label = "FREE FOR ALL",
					chip = "SOLO",
					short = "FREE FOR ALL", -- the design's MODES.FFA.tab is its name (N:712)
					rotation = 90,
					stops = { { at = 0, color = WHITE } },
				},
			},
			selected = "tdm",
			onSelect = function(id: string)
				table.insert(picked, id)
			end,
		})
		expect.equal(tabs.root.Name, "Hud_DuelModes")
		expect.deepEqual(tabs.order, { "tdm", "ffa" })
		expect.equal(tabs:selected(), "tdm")
		for _, id in tabs.order do
			local hit = tabs.tabs[id]
			expect.truthy(hit:IsA("TextButton"))
			expect.equal(hit.Size.Y.Offset, MIN_TARGET) -- PR1: each tab's 42 px face in a 52 px touch box
		end
		-- A pick by code repaints without reporting; the same tab again does nothing.
		tabs:select("ffa")
		expect.equal(tabs:selected(), "ffa")
		tabs:select("nope")
		expect.equal(tabs:selected(), "ffa")
		expect.deepEqual(picked, {})
		local size = tabs:size()
		expect.truthy(size.X >= tabs.tabs.tdm.Size.X.Offset + tabs.tabs.ffa.Size.X.Offset)
		expect.truthy(size.Y >= MIN_TARGET)
		-- The narrow fit: each tab's short name alone (N:711-712 MODES.*.tab), no chip, narrower; still 52 px tall.
		local label = tabs.tabs.tdm:FindFirstChild("Label", true) :: TextLabel
		local chip = tabs.tabs.tdm:FindFirstChild("Chip", true) :: Frame
		expect.truthy(tabs:size(true).X < size.X)
		tabs:setShort(true)
		expect.equal(label.Text, "TEAM 6v6")
		expect.falsy(chip.Visible)
		expect.equal(tabs:size().X, tabs:size(true).X)
		expect.equal(tabs.tabs.tdm.Size.Y.Offset, MIN_TARGET)
		expect.equal((tabs.tabs.ffa:FindFirstChild("Label", true) :: TextLabel).Text, "FREE FOR ALL")
		expect.falsy((tabs.tabs.ffa:FindFirstChild("Chip", true) :: Frame).Visible)
		tabs:setShort(false)
		expect.equal(label.Text, "TEAM DEATHMATCH")
		expect.truthy(chip.Visible)
		expect.equal(tabs:size().X, size.X)
		-- The gradient's turn: 10 degrees on the screen is about 2 in a 220 x 42 tab's own 0..1 space (a UIGradient
		-- rotates there); 0 and 90 stay; a bad size leaves it.
		local turned = math.deg(math.atan(math.tan(math.rad(10)) * 42 / 220))
		expect.near(SegmentedTabs.gradientRotation(10, 220, 42), turned, 1e-9)
		expect.truthy(turned > 1.5 and turned < 2.5)
		expect.near(SegmentedTabs.gradientRotation(90, 220, 42), 90, 1e-9)
		expect.near(SegmentedTabs.gradientRotation(0, 220, 42), 0, 1e-9)
		expect.equal(SegmentedTabs.gradientRotation(10, 0, 42), 10)
		local face = tabs.tabs.tdm:FindFirstChild("Face") :: Frame
		local gradient = face:FindFirstChildOfClass("UIGradient") :: UIGradient
		expect.truthy(gradient.Rotation > 0 and gradient.Rotation < 10)
		tabs:destroy()
		expect.equal(tabs.root.Parent, nil)
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

	-- UI FINAL R2 (plan work/ui/PLAN.md R2: P1, T3, T4, P11, P12, P2, PR4, PR5, PR24) ---------------------------------

	t.test(
		"frame = face + lip (P1): every kind's root is its face and lip, the drawn button fills the hit box",
		function()
			for _, kind in { "primary", "secondary", "cancel", "tile", "cta", "close" } do
				local style = Button.style(kind)
				expect.equal(Button.frameHeight(kind), style.height + style.lip)
				local button = Button.new({ name = "F_" .. kind, text = "Go", kind = kind, onActivated = noop })
				expect.equal(button.root.Size.Y.Offset, math.max(style.height + style.lip, MIN_TARGET))
				expect.equal(button.root.BackgroundTransparency, 1) -- a transparent hit box
				expect.equal(button.visual.Name, "SD_Visual")
				expect.equal(button.visual.Parent, button.root)
				expect.equal(button.visual.Size, UDim2.fromScale(1, 1))
				expect.equal(button.visual.AnchorPoint, Vector2.new(0.5, 0.5))
				button:destroy()
			end
			expect.equal(Button.frameHeight("cta"), Button.CTA_HEIGHT + STICKER.lip.cta) -- 92 + 7 = 99 (H:126)
			expect.equal(Button.frameHeight("close"), 76 + STICKER.lip.closeX) -- 82 (H:252)
			-- A given height is the face: a 60 px EQUIP (H:245) is 65 tall.
			local equip = Button.new({ name = "E", text = "Equip", kind = "primary", height = 60, onActivated = noop })
			expect.equal(equip.root.Size.Y.Offset, 60 + STICKER.lip.button)
			equip:destroy()
		end
	)

	t.test("the hover kinds (H:634) and the exact hover filter brightness(1.07) saturate(1.06) (T4, H:637)", function()
		expect.equal(Button.fxOf("primary"), "btn")
		expect.equal(Button.fxOf("secondary"), "btn")
		expect.equal(Button.fxOf("cancel"), "btn")
		expect.equal(Button.fxOf("cta"), "btn")
		expect.equal(Button.fxOf("tile"), "nav")
		expect.equal(Button.fxOf("close"), "x")
		expect.equal(Button.fxOf("tile", "icon"), "icon") -- the Settings sticker (H:157)
		local HOVER = Config.UI.motion.hover
		expect.deepEqual(HOVER.btn, { scale = 1.04, y = -3 })
		expect.deepEqual(HOVER.nav, { scale = 1.13, rot = -4 })
		expect.deepEqual(HOVER.x, { scale = 1.1, rot = 90 })
		expect.deepEqual(HOVER.row, { x = 4 })
		-- The CSS filter on the green face's top stop #A6F796: x1.07 clamped, then the saturate matrix (s = 1.06).
		local c = Palette.StickerGreenTop
		local r, g, b = math.min(1, c.R * 1.07), math.min(1, c.G * 1.07), math.min(1, c.B * 1.07)
		local s = 1.06
		local want = Color3.new(
			math.clamp((0.213 + 0.787 * s) * r + (0.715 - 0.715 * s) * g + (0.072 - 0.072 * s) * b, 0, 1),
			math.clamp((0.213 - 0.213 * s) * r + (0.715 + 0.285 * s) * g + (0.072 - 0.072 * s) * b, 0, 1),
			math.clamp((0.213 - 0.213 * s) * r + (0.715 - 0.715 * s) * g + (0.072 + 0.928 * s) * b, 0, 1)
		)
		local got = Button.hoverColor(c)
		expect.near(got.R, want.R, 1e-6)
		expect.near(got.G, want.G, 1e-6)
		expect.near(got.B, want.B, 1e-6)
		expect.truthy(got.G > c.G) -- brighter
		-- White stays white; black stays black.
		local white, black = Button.hoverColor(Color3.new(1, 1, 1)), Button.hoverColor(Color3.new(0, 0, 0))
		for _, channel in { "R", "G", "B" } do
			expect.near((white :: any)[channel], 1, 1e-6)
			expect.near((black :: any)[channel], 0, 1e-6)
		end
	end)

	t.test(
		"the press squash (PR4, lib:287-293) over 667 ms and the 'no' shake (PR5, lib:295-297) over 1000 ms",
		function()
			local PRESS = Config.UI.motion.buttonPress
			expect.equal(PRESS.ms, 667)
			expect.equal(PRESS.designMs, 460)
			local a = PRESS.amount
			local sx, sy = Button.squashAt(0.2, a)
			expect.near(sx, 1 + a, 1e-6)
			expect.near(sy, 1 - a, 1e-6)
			sx, sy = Button.squashAt(0.45, a)
			expect.near(sx, 1 - 0.5 * a, 1e-6)
			expect.near(sy, 1 + 0.6 * a, 1e-6)
			sx, sy = Button.squashAt(0.7, a * 1.4) -- a nav sticker (H:644)
			expect.near(sx, 1 + 0.2 * a * 1.4, 1e-6)
			expect.near(sy, 1 - 0.15 * a * 1.4, 1e-6)
			sx, sy = Button.squashAt(1, a)
			expect.near(sx, 1, 1e-9)
			expect.near(sy, 1, 1e-9)
			-- Each swing eased ease-out (per segment): a tenth into the first, more than a tenth of the way.
			local early = Button.squashAt(0.02, a)
			expect.truthy(early - 1 > a * 0.1)
			-- The swings between extremes 167 ms apart: 3 Hz (§9.12).
			expect.truthy((0.45 - 0.2) * PRESS.ms >= 1000 / 6 - 1e-6)
			local SHAKE = Config.UI.motion.buttonShake
			expect.equal(SHAKE.ms, 1000)
			expect.equal(SHAKE.px, 9) -- H:643
			expect.equal(SHAKE.pillPx, 12) -- H:676
			local steps = SHAKE.steps
			for index, v in steps do
				local x, turn = Button.shakeAt((index - 1) / (#steps - 1), 9)
				expect.near(x, v * 9, 1e-6)
				expect.near(turn, v * SHAKE.rotDeg, 1e-6)
			end
			expect.truthy(SHAKE.ms / (#steps - 1) >= 1000 / 6 - 1e-6)
		end
	)

	t.test("one sound per click (G2.7): tile and close clicks silent by kind, the hover kept", function()
		expect.truthy(Config.Audio.buttonSilentKinds.tile)
		expect.truthy(Config.Audio.buttonSilentKinds.close)
		expect.equal(Config.Audio.buttonSilentKinds.primary, nil)
		-- The hover pitch by kind (H:638): nav .8, card 1.15, tab 1.3, else 1.
		local pitch = Config.Audio.uiPitch.hover
		expect.equal(pitch.nav, 0.8)
		expect.equal(pitch.card, 1.15)
		expect.equal(pitch.tab, 1.3)
		expect.equal(pitch.btn, 1)
	end)

	t.test("off (P11): the normal face, the subtext in the price colour; setOff(false) back", function()
		local open = Button.new({
			name = "Boxes_OpenButton",
			text = "Open",
			kind = "primary",
			icon = "coin",
			subtext = "500",
			onActivated = noop,
		})
		local face = (open.visual:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints
		open:setOff(true, Palette.StickerPriceShort)
		expect.truthy(open:isOff())
		expect.equal(open:getState(), "normal") -- still activatable (the design's click handler runs, H:643)
		local sub = open.visual:FindFirstChild("Subtext", true) :: TextLabel
		expect.equal(sub.TextColor3, Palette.StickerPriceShort) -- H:946
		local same = (open.visual:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints
		expect.equal(#same, #face)
		expect.equal(same[1].Value, face[1].Value) -- the normal face, not the lilac
		open:setOff(false)
		expect.falsy(open:isOff())
		expect.equal(sub.TextColor3, WHITE)
		open:destroy()
	end)

	t.test("overrides (P12) and the chip size (H:402): a 34 px face in a touch-sized hit box", function()
		local custom = Button.new({
			name = "O",
			text = "Go",
			kind = "primary",
			radius = 16,
			border = 3,
			lip = 4,
			onActivated = noop,
		})
		expect.equal((custom.visual:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius, UDim.new(0, 16))
		expect.equal((custom.visual:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, 3)
		expect.equal(custom.root.Size.Y.Offset, Button.style("primary").height + 4)
		custom:destroy()
		local chip = Button.new({ name = "Daily_ClaimChip", text = "Claim!", size = "chip", onActivated = noop })
		expect.equal(chip.root.Size.Y.Offset, math.max(34 + STICKER.lip.bar, MIN_TARGET))
		expect.equal(chip.visual.Size, UDim2.new(1, 0, 0, 34 + STICKER.lip.bar)) -- the face keeps its size (PR1)
		expect.equal((chip.visual:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, STICKER.border.thin)
		expect.equal((chip.visual:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius, UDim.new(0, 12))
		local label = chip.root:FindFirstChild("Label", true) :: TextLabel
		expect.equal(label:GetAttribute("SD_TextKind"), "Body") -- 18 px (H:402)
		expect.equal(label.Text, "CLAIM!") -- capitals (Q5)
		local points = (chip.visual:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints
		local green2 = false
		for _, point in points do
			green2 = green2 or point.Value == Palette.StickerGreen2End
		end
		expect.truthy(green2) -- #A6F796 -> #38C150
		chip:destroy()
		-- 2 stops: the accent's top and end only (no mid).
		local two = Button.new({ name = "T", text = "Go", kind = "primary", stops = 2, onActivated = noop })
		local twoPoints = (two.visual:FindFirstChild("SD_Foam") :: UIGradient).Color.Keypoints
		for _, point in twoPoints do
			expect.truthy(point.Value ~= Palette.StickerGreenMid)
		end
		two:destroy()
	end)

	t.test("the cta's shine (P2): a holder inset by the border, the face's height, corner 23, a 54 px strip", function()
		local cta =
			Button.new({ name = "Hud_DuelButton", text = "DUEL", kind = "cta", width = 350, onActivated = noop })
		local style = Button.style("cta")
		local clip = cta.visual:FindFirstChild("SD_Shine") :: Frame
		expect.truthy(cta.visual:FindFirstChild("SD_Shine") ~= nil)
		expect.truthy(clip.ClipsDescendants)
		expect.equal(clip.ZIndex, 0) -- under the content
		local b = style.border
		expect.equal(clip.Position, UDim2.fromOffset(b - style.paddingX, b))
		expect.equal(clip.Size, UDim2.new(1, 2 * style.paddingX - 2 * b, 1, -2 * b - style.lip))
		expect.equal((clip:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius, UDim.new(0, 23)) -- H:127
		local strip = clip:FindFirstChild("Strip") :: Frame
		local shine = STICKER.shines.cta
		expect.equal(strip.Size, UDim2.new(0, shine.px, 1, 2 * shine.overhangPx)) -- 54 px, top / bottom -10
		expect.equal(strip.Position.Y.Offset, -shine.overhangPx)
		expect.equal(strip.BackgroundTransparency, 1) -- the holder UiIdle moves
		-- H:28 skewX(-20deg): the band itself turned 20°, strip x cos 20° wide (54 px across), its gradient unturned.
		local band = strip:FindFirstChild("Band") :: Frame
		expect.truthy(strip:FindFirstChild("Band") ~= nil)
		expect.equal(band.Rotation, shine.slantDeg)
		expect.equal(band.Size.X.Offset, math.round(shine.px * math.cos(math.rad(shine.slantDeg)))) -- whole px
		expect.equal((band:FindFirstChildOfClass("UIGradient") :: UIGradient).Rotation, 0)
		expect.truthy(clip.Visible)
		cta:sweep() -- kept, a no-op
		cta:destroy()
		local primary = Button.new({ name = "P", text = "Buy", kind = "primary", width = 160, onActivated = noop })
		expect.equal(primary.visual:FindFirstChild("SD_Shine"), nil)
		primary:destroy()
	end)

	t.test(
		"the focus ring (PR24): drawn in SD_Visual round the face (the lip left out), shown while selected",
		function()
			local button = Button.new({ name = "R", text = "Go", kind = "primary", onActivated = noop })
			local outset = Config.UI.motion.focus.outerStrokePx + Config.UI.motion.focus.innerStrokePx
			local padX = Button.style("primary").paddingX
			expect.equal(button.root.Selectable, true)
			expect.equal((button.root.SelectionImageObject :: Frame).BackgroundTransparency, 1) -- a clear hit-box image
			expect.equal(#(button.root.SelectionImageObject :: Frame):GetChildren(), 0)
			local ring = button.visual:FindFirstChild("SD_FocusRing") :: Frame
			expect.truthy(button.visual:FindFirstChild("SD_FocusRing") ~= nil)
			expect.falsy(ring.Visible)
			-- SD_Visual's side padding is reached back over; the lip under the face is left out.
			expect.equal(ring.Size, UDim2.new(1, 2 * outset + 2 * padX, 1, 2 * outset - STICKER.lip.button))
			expect.equal(ring.Position, UDim2.fromOffset(-outset - padX, -outset))
			local seam = button :: any
			seam:_simulate("select")
			expect.truthy(ring.Visible)
			seam:_simulate("unselect")
			expect.falsy(ring.Visible)
			button:destroy()
			-- The chip's face is its own SD_Visual (centred in the touch box): the ring goes round it.
			local chip = Button.new({ name = "C", text = "Claim!", size = "chip", onActivated = noop })
			local chipRing = chip.visual:FindFirstChild("SD_FocusRing") :: Frame
			expect.equal(chipRing.Position, UDim2.fromOffset(-outset - 20, -outset)) -- H:402's padding 20
			chip:destroy()
		end
	)

	t.test("Toggle (G1.1, P7): the knob over 300 / 350 ms on the switch curve, the track over 200 / 250 ms", function()
		local small, large = STICKER.toggles.small, STICKER.toggles.large
		expect.equal(small.knobMs, 300) -- H:197
		expect.equal(small.trackMs, 200)
		expect.equal(large.knobMs, 350) -- H:437
		expect.equal(large.trackMs, 250)
		local k, c, done = Toggle.motionAt("large", 0)
		expect.near(k, 0, 1e-9)
		expect.near(c, 0, 1e-9)
		expect.falsy(done)
		k, c, done = Toggle.motionAt("large", 250)
		expect.near(c, 1, 1e-9) -- the track has arrived
		expect.falsy(done) -- the knob has not
		expect.truthy(k > 1) -- the design's overshoot (cubic-bezier(.3,1.8,.5,1))
		k, c, done = Toggle.motionAt("large", 350)
		expect.near(k, 1, 1e-9)
		expect.truthy(done)
		k, c, done = Toggle.motionAt("small", 300)
		expect.near(k, 1, 1e-9)
		expect.truthy(done)
	end)

	t.test("Chip (P8, H:232, H:234): its icon 20 px, 6 px from the text", function()
		local chip = Chip.new({ name = "Stat", text = "x2", icon = "coin" })
		expect.equal((chip.root:FindFirstChildOfClass("UIListLayout") :: UIListLayout).Padding, UDim.new(0, 6))
		local icon = chip.root:FindFirstChild("Icon") :: Frame
		expect.equal(icon.Size, UDim2.fromOffset(20, 20))
		chip:destroy()
	end)

	t.test("ProgressBar (P9, G2.5): the border inside the design height, the Grip min fill and shine", function()
		local bars = STICKER.bars
		-- The default (stat) bar is its design's 14 px with the 3 px border inside, the fill in the track inside it.
		local stat = ProgressBar.new({ name = "Stat" })
		expect.equal(stat.root.Size.Y.Offset, bars.stat.height)
		local track = stat.root:FindFirstChild("Track") :: Frame
		expect.equal(track.Position, UDim2.fromOffset(bars.stat.border, bars.stat.border))
		expect.equal(track.Size, UDim2.new(1, -2 * bars.stat.border, 1, -2 * bars.stat.border))
		expect.equal(stat.fill.Parent, track)
		stat:destroy()
		-- The design heights (H:84, H:187, H:240, H:271, H:367).
		expect.equal(bars.grip.height, 14)
		expect.equal(bars.collected.height, 16)
		expect.equal(bars.stat.height, 14)
		expect.equal(bars.odds.height, 12)
		expect.equal(bars.quest.height, 20)
		expect.equal(bars.grip.fillMs, 550)
		expect.equal(bars.quest.fillMs, 600)
		expect.equal(STICKER.barFillCurve, "bars")
		-- The Grip bar: never narrower than 10 px (H:85 min-width), shown at 0 too; its 22 px shine strip.
		local grip = ProgressBar.new({ name = "Grip", variant = "grip" })
		expect.truthy(grip.fill.Visible)
		local min = grip.fill:FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
		expect.equal(min.MinSize, Vector2.new(bars.grip.minFillPx, 0))
		local strip = grip.fill:FindFirstChild("SD_Shine") :: Frame
		expect.equal(strip.Size, UDim2.new(0, STICKER.shines.grip.px, 1, 0))
		local gripBand = strip:FindFirstChild("Band") :: Frame
		expect.equal(gripBand.Rotation, STICKER.shines.grip.slantDeg) -- H:28: it leans like the CTA's
		grip:destroy()
		local quest = ProgressBar.new({ name = "Quest", variant = "quest" })
		expect.equal((quest.fill:FindFirstChild("SD_Shine") :: Frame).Size.X.Offset, STICKER.shines.quest.px)
		quest:destroy()
		-- A bar too thin for its border keeps a 2 px track (the compact Grip card's 4 px bar).
		local thin = ProgressBar.new({ name = "Thin", heightPx = 4 })
		expect.equal((thin.root:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, 1)
		expect.equal((thin.root:FindFirstChild("Track") :: Frame).Size, UDim2.new(1, -2, 1, -2))
		thin:destroy()
	end)

	t.test("ProgressBar.fillAt: the design's overshoot shows inside the track, never past its end (H:84)", function()
		local peak = 0
		for step = 0, 100 do
			local u = step / 100
			local full = ProgressBar.fillAt(0.5, 1, u)
			expect.truthy(full >= 0.5 - 1e-9 and full <= 1)
			peak = math.max(peak, ProgressBar.fillAt(0.5, 0.9, u))
		end
		expect.near(ProgressBar.fillAt(0.5, 1, 1), 1, 1e-9)
		expect.truthy(peak > 0.9 and peak <= 1) -- cubic-bezier(.3,1.5,.5,1) peaks at 1.08 of the way
		expect.near(ProgressBar.fillAt(0.2, 0, 1), 0, 1e-9)
	end)

	t.test("a face whose frame is under the touch minimum keeps its size, centred in a 52 px hit box (PR1)", function()
		local tab = Button.new({ name = "Tab", text = "Epic", kind = "primary", height = 42, onActivated = noop })
		local frame = 42 + STICKER.lip.button -- H:194's 42 px tab with the lip: 47
		expect.equal(tab.root.Size.Y.Offset, MIN_TARGET)
		expect.equal(tab.visual.Size, UDim2.new(1, 0, 0, frame))
		expect.equal(tab.visual.Position, UDim2.fromScale(0.5, 0.5))
		tab:destroy()
	end)

	t.test("hover and focus pose SD_Visual by kind about the face's centre, the hit box stays (T3, PR24)", function()
		if Tweens.reducedMotion() then
			return -- the poses rest under ReducedMotion (this Studio has it on)
		end
		local button = Button.new({ name = "P", text = "Equip", kind = "primary", onActivated = noop })
		local seam = button :: any
		local rootPosition = button.root.Position
		local pose = button.visual:FindFirstChild("SD_Pose") :: UIScale
		seam:_simulate("hover")
		seam:_simulate("frame", 1) -- a second later: arrived
		expect.equal(button.visual.Position, UDim2.new(0.5, 0, 0.5, -3)) -- btn: up 3 (H:634)
		expect.near(pose.Scale, 1.04, UDIM_TOLERANCE) -- a 32-bit float
		expect.equal(button.root.Position, rootPosition) -- the hit box never moves
		seam:_simulate("unhover")
		seam:_simulate("frame", 1)
		expect.equal(button.visual.Position, UDim2.fromScale(0.5, 0.5))
		expect.near(pose.Scale, 1, 1e-9)
		-- PR24: a gamepad selection gives the same pose.
		seam:_simulate("select")
		seam:_simulate("frame", 1)
		expect.equal(button.visual.Position, UDim2.new(0.5, 0, 0.5, -3))
		button:destroy()
		-- The close X turns 90° about its face (76 x 76), not its frame with the 6 px lip: 3 px left and up.
		local close = Button.new({ name = "X", text = "Close", kind = "close", onActivated = noop })
		local closeSeam = close :: any
		closeSeam:_simulate("hover")
		closeSeam:_simulate("frame", 1)
		expect.near(close.visual.Rotation, 90, 1e-9)
		expect.equal(close.visual.Position, UDim2.new(0.5, -3, 0.5, -3))
		close:destroy()
	end)

	t.test(
		"presses: an off press plays ui.error and the shake and still acts (P11); a touch waits for the tap",
		function()
			local keys: { string } = {}
			Button.setSoundHook(function(key: string)
				table.insert(keys, key)
			end)
			local ran = 0
			local open = Button.new({
				name = "Boxes_OpenButton",
				text = "Open",
				kind = "primary",
				onActivated = function()
					ran += 1
				end,
			})
			local seam = open :: any
			open:setOff(true, Palette.StickerPriceShort)
			seam:_simulate("press", Enum.UserInputType.MouseButton1) -- the mouse: on pointer-down (H:611, H:643)
			expect.deepEqual(keys, { "ui.error" })
			if not Tweens.reducedMotion() then
				seam:_simulate("frame", 0.25)
				expect.truthy(open.visual.Rotation ~= 0) -- the shake's turn (lib:297)
			end
			seam:_simulate("activate", Enum.UserInputType.MouseButton1)
			expect.equal(ran, 1) -- the design's click handler runs too (deny follows)
			expect.deepEqual(keys, { "ui.error" }) -- no second error, no click
			-- A disabled button and a touch: nothing at touch-down (a scroll may start there), the error on the tap.
			table.clear(keys)
			open:setOff(false)
			open:setState("disabled", "Not enough Coins")
			seam:_simulate("press", Enum.UserInputType.Touch)
			expect.deepEqual(keys, {})
			seam:_simulate("activate", Enum.UserInputType.Touch)
			expect.deepEqual(keys, { "ui.error" })
			expect.equal(ran, 1) -- a disabled button never acts
			-- A live button: a touch squashes at once, the tap acts and clicks once.
			table.clear(keys)
			open:setState("normal")
			seam:_simulate("press", Enum.UserInputType.Touch)
			seam:_simulate("activate", Enum.UserInputType.Touch)
			expect.equal(ran, 2)
			expect.deepEqual(keys, { "ui.click" })
			open:destroy()
			-- The cta's shine hides while its shake turns it (Roblox stops clipping under a turn).
			if not Tweens.reducedMotion() then
				local cta = Button.new({ name = "D", text = "DUEL", kind = "cta", width = 350, onActivated = noop })
				local ctaSeam = cta :: any
				cta:setState("disabled")
				ctaSeam:_simulate("press", Enum.UserInputType.MouseButton1)
				ctaSeam:_simulate("frame", 0.25)
				expect.falsy((cta.visual:FindFirstChild("SD_Shine") :: Frame).Visible)
				ctaSeam:_simulate("frame", 2) -- the shake is over
				expect.truthy((cta.visual:FindFirstChild("SD_Shine") :: Frame).Visible)
				cta:destroy()
			end
			Button.setSoundHook(nil)
		end
	)

	t.test(
		"one sound per click (G2.7): a tile or close X click is silent, its hover sounds even with sound = false",
		function()
			local keys: { string } = {}
			Button.setSoundHook(function(key: string)
				table.insert(keys, key)
			end)
			for _, kind in { "tile", "close" } do
				table.clear(keys)
				local button = Button.new({ name = "S", text = "Go", kind = kind, sound = false, onActivated = noop })
				local seam = button :: any
				seam:_simulate("hover")
				seam:_simulate("activate") -- a gamepad press
				expect.deepEqual(keys, { "ui.hover" })
				button:destroy()
			end
			-- Any other kind: sound = false silences both; clickSound = false the click only.
			table.clear(keys)
			local quiet = Button.new({ name = "Q", text = "Go", kind = "primary", sound = false, onActivated = noop })
			local quietSeam = quiet :: any
			quietSeam:_simulate("hover")
			quietSeam:_simulate("activate")
			expect.deepEqual(keys, {})
			quiet:destroy()
			local own =
				Button.new({ name = "O", text = "Go", kind = "primary", clickSound = false, onActivated = noop })
			local ownSeam = own :: any
			ownSeam:_simulate("hover")
			ownSeam:_simulate("activate")
			expect.deepEqual(keys, { "ui.hover" })
			own:destroy()
			local plain = Button.new({ name = "N", text = "Go", kind = "primary", onActivated = noop })
			table.clear(keys)
			local plainSeam = plain :: any
			plainSeam:_simulate("activate")
			expect.deepEqual(keys, { "ui.click" })
			plain:destroy()
			Button.setSoundHook(nil)
		end
	)

	t.test("decorated objects press on the squash's sy track (a reading); the width keeps out 1 px rounding", function()
		local PRESS = Config.UI.motion.buttonPress
		-- .86 at 20% (lib:290): a tap on the coin pill or a box card still shows a press.
		expect.near(Button.decoratedScale(Button.squashAt(0.2, PRESS.amount)), 1 - PRESS.amount, 1e-9)
		expect.near(Button.decoratedScale(Button.squashAt(0.45, PRESS.amount)), 1 + 0.6 * PRESS.amount, 1e-9)
		-- While it moves, a re-measure within 1 px keeps the width; a real change or a still button takes it.
		expect.equal(Button.settledWidth(100, 101, true), 100)
		expect.equal(Button.settledWidth(100, 99, true), 100)
		expect.equal(Button.settledWidth(100, 102, true), 102)
		expect.equal(Button.settledWidth(100, 101, false), 101)
		expect.equal(Button.settledWidth(0, 101, true), 101)
	end)
end
