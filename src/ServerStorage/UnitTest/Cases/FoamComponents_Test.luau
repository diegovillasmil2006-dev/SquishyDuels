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
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local WHITE = Color3.new(1, 1, 1)
	local MIN_TARGET = Config.UI.Touch.minTarget

	t.test("every Button kind: stable name, Label and Reason, touch height, one foam outline and a rim", function()
		for _, kind in { "primary", "secondary", "tile", "cta", "close" } do
			local button =
				Button.new({ name = "Test_" .. kind .. "Button", text = "Go", kind = kind, onActivated = noop })
			local root = button.root
			expect.equal(root.Name, "Test_" .. kind .. "Button")
			expect.truthy(root:FindFirstChild("Label", true) ~= nil)
			expect.truthy(root:FindFirstChild("Reason", true) ~= nil)
			expect.truthy(root.Size.Y.Offset >= MIN_TARGET)
			expect.truthy(root:FindFirstChild("SD_Foam") ~= nil)
			expect.equal(strokesOf(root), 1)
			expect.equal((root:FindFirstChildOfClass("UIStroke") :: UIStroke).Color, Theme.Colors.inkUI)
			expect.truthy(root:FindFirstChild("SD_Rim") ~= nil)
			expect.equal(button:getState(), "normal")
			button:destroy()
			expect.equal(root.Parent, nil)
		end
	end)

	t.test("labels follow the outlined-text rule", function()
		local primary = Button.new({ name = "P", text = "Change", kind = "primary", onActivated = noop })
		local label = primary.root:FindFirstChild("Label", true) :: TextLabel
		expect.equal(label.TextColor3, WHITE)
		expect.truthy((label:FindFirstChild("SD_Outline") :: UIStroke).Enabled)
		primary:destroy()

		-- The plum neutral: outlined white too.
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

		-- A Small (body) label on a saturated accent: PlumInk.
		local small = Button.new({ name = "C", text = "Go", kind = "primary", textKind = "Small", onActivated = noop })
		expect.equal((small.root:FindFirstChild("Label", true) :: TextLabel).TextColor3, Theme.Colors.inkUI)
		small:destroy()
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
		expect.equal(root.Size.X.Offset, Button.TILE_SIZE)
		expect.equal(root.Size.Y.Offset, Button.TILE_SIZE)
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
		-- A fixed-width tile carries the shine under its content.
		local shine = root:FindFirstChild("SD_Shine") :: Frame
		expect.truthy(shine ~= nil)
		expect.equal(shine.ZIndex, 0)
		tile:destroy()

		-- The close kind: a square red X, its label kept but hidden.
		local close = Button.new({ name = "Test_CloseButton", text = "Close", kind = "close", onActivated = noop })
		expect.equal(close.root.Size.X.Offset, close.root.Size.Y.Offset)
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

	t.test("disabled: the disabled foam, DisabledText and the reason in Ink2", function()
		local button = Button.new({ name = "Shop_BuyButton", text = "Buy", kind = "primary", onActivated = noop })
		button:setState("disabled", "Need 5 more Coins")
		expect.equal(button:getState(), "disabled")
		local label = button.root:FindFirstChild("Label", true) :: TextLabel
		local reason = button.root:FindFirstChild("Reason", true) :: TextLabel
		expect.equal(label.TextColor3, Theme.Colors.disabledText)
		expect.truthy(reason.Visible)
		expect.equal(reason.Text, "Need 5 more Coins")
		expect.equal(reason.TextColor3, Theme.Colors.ink2)
		expect.equal((button.root:FindFirstChildOfClass("UIStroke") :: UIStroke).Color, Theme.Colors.disabledStroke)
		button:setState("normal")
		expect.falsy(reason.Visible)
		expect.equal(label.TextColor3, WHITE)
		expect.equal((button.root:FindFirstChildOfClass("UIStroke") :: UIStroke).Color, Theme.Colors.inkUI)
		button:destroy()
	end)

	t.test("widthFor counts the kind's padding; setWidth switches wrapping", function()
		local wide = Button.widthFor("Go", nil, "Button", "primary")
		local narrow = Button.widthFor("Go", nil, "Button", "tile")
		expect.near(wide - narrow, 2 * (Button.style("primary").paddingX - Button.style("tile").paddingX), 1e-9)
		expect.equal(Button.widthFor("Go"), wide) -- the default kind has the primary padding
		expect.equal(Button.style("tile").bevel, Theme.Foam.tile.bevel)
		expect.equal(Button.style("cta").drop, Theme.Foam.cta.drop)
		expect.equal(Button.style("nope" :: any).accent, "plum")
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

		-- A primary gets its shine only while its width is fixed (an overlay would inflate an automatic width).
		local primary = Button.new({ name = "P", text = "Buy", kind = "primary", onActivated = noop })
		expect.equal(primary.root:FindFirstChild("SD_Shine"), nil)
		primary:setWidth(160)
		expect.truthy(primary.root:FindFirstChild("SD_Shine") ~= nil)
		primary:setWidth(nil)
		expect.equal(primary.root:FindFirstChild("SD_Shine"), nil)
		primary:destroy()
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
		badge:destroy()
	end)

	t.test("ProgressBar: 0..1, the fill hides at 0", function()
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
		expect.equal(bar.root.BackgroundColor3, Theme.Colors.biscuit)
		expect.equal((bar.root:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, Theme.Stroke.bar)
		bar:destroy()
	end)

	t.test("Keycap reads its key through KeyText and hides without one", function()
		local cap = Keycap.new({ name = "Keycap", key = "controls.key.inspectKeyboard" })
		expect.equal(cap.label.Text, Strings.controls.key.inspectKeyboard)
		expect.truthy(cap.root.Visible)
		cap:setText(nil)
		expect.falsy(cap.root.Visible)
		cap:setKey("controls.key.inspectGamepad")
		expect.equal(cap.label.Text, Strings.controls.key.inspectGamepad)
		expect.equal(cap.label.TextColor3, Theme.Colors.inkUI) -- Candy UI: a light sticker key
		cap:destroy()
	end)

	t.test("Chip: InkUI on a light face, the given colour on a rarity face", function()
		local chip = Chip.new({ name = "EquippedChip", text = "Equipped" })
		expect.equal(chip.label.TextColor3, Theme.Colors.inkUI)
		chip:setAccent("strawberry")
		expect.equal(chip.label.TextColor3, WHITE) -- Candy UI: the Chip kind is outlined white on an accent
		chip:setAccent("gold")
		expect.equal(chip.label.TextColor3, Theme.Colors.inkUI) -- a light accent: PlumInk
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

	t.test("Toggle and Slider keep their parts with the foam knob and fill", function()
		local toggle =
			Toggle.new({ name = "Settings_ShowTipsToggle", text = "Show tips", value = true, onChanged = noop })
		expect.truthy(toggle.root:FindFirstChild("Knob", true) ~= nil)
		local knob = toggle.root:FindFirstChild("Knob", true) :: Frame
		expect.truthy(knob:FindFirstChild("SD_Foam") ~= nil)
		expect.equal((toggle.root:FindFirstChild("Switch") :: Frame).BackgroundColor3, Theme.Accents.mint.face)
		toggle:setValue(false)
		expect.equal((toggle.root:FindFirstChild("Switch") :: Frame).BackgroundColor3, Theme.Colors.biscuit)
		toggle:destroy()

		local slider = Slider.new({ name = "S", min = 0, max = 100, step = 5, value = 40, onChanged = noop })
		local fill = slider.root:FindFirstChild("Fill", true) :: Frame
		expect.truthy(fill:FindFirstChild("SD_Foam") ~= nil)
		expect.near(fill.Size.X.Scale, 0.4, UDIM_TOLERANCE) -- stored as 0.4000000059604645
		expect.truthy(slider.root:FindFirstChild("Knob", true) ~= nil)
		slider:destroy()
	end)
end
