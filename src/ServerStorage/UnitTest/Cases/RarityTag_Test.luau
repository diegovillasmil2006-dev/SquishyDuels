--!strict
-- RarityTag_Test: StarterPlayerScripts.Client.UI.Components.RarityTag (the rarity pips beside or above the label chip).
-- Server only (ServerStorage.UnitTest). Edit mode: tags are built unparented and destroyed; measure() reads the text
-- size through Theme (TextService).
-- Contract (DESIGN §4.3; foam fix batch 2026-10-09, "rarity dots touch the label"):
--   * the gap between the pips and the chip counts both 2 px outlines (drawn outside their boxes) and still leaves air,
--     side by side and stacked; the tag keeps at least one outline of room inside its own box on every side;
--   * measure() matches the built tag: pips + the list's gap + chip + the padding on both sides, both ways round; an
--     unknown rarity measures 0;
--   * setStacked switches the list's direction and gap;
--   * a diamond pip (a rotated square) fits its pip box;
--   * fix round 2: tallest() is the tallest side-by-side tag over every rarity (the room the Squishies and Shop details
--     keep for the tag under the name).
--   * UI FINAL R1 (H:209, H:271, H:933): the pill is at least 22 px tall with a 3 px ink border, in the design's rarity
--     colour (Common #6F7D8B), the label white, outlined, in capitals; the pips in the same colour, still with their
--     2 px outline, so the gaps count a 2 px and a 3 px outline (the room inside the tag the larger one).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local RarityTag = t.requireClient("UI/Components/RarityTag")
	local Theme = t.requireClient("UI/Theme")
	local EPS = 1e-6
	local OUTLINE = Theme.Stroke.bar
	local PIP_PX = 8

	-- The built tag's list gap and padding (one side), side by side or stacked.
	local function parts(stacked: boolean): (number, number)
		local tag = RarityTag.new({ name = "Rarity", rarity = "Exclusive", pipSizePx = PIP_PX, stacked = stacked })
		local list = tag.root:FindFirstChildOfClass("UIListLayout") :: UIListLayout
		local pad = tag.root:FindFirstChildOfClass("UIPadding") :: UIPadding
		local gap, room = list.Padding.Offset, pad.PaddingTop.Offset
		expect.equal(pad.PaddingLeft.Offset, room)
		expect.equal(pad.PaddingRight.Offset, room)
		expect.equal(pad.PaddingBottom.Offset, room)
		tag:destroy()
		return gap, room
	end

	t.test("the gaps count both outlines and leave air; the tag keeps room for its outlines", function()
		local inlineGap, room = parts(false)
		local stackedGap = parts(true)
		expect.truthy(inlineGap >= 2 * OUTLINE + 2)
		expect.truthy(stackedGap >= 2 * OUTLINE + 2)
		expect.truthy(inlineGap >= Theme.Padding.small + 2 * OUTLINE) -- the old 6 px of air between them, kept
		expect.truthy(room >= OUTLINE)
		-- UI FINAL R1: the pips' 2 px and the pill's 3 px outlines (H:209), and room for the larger.
		local pill = t.requireShared("Config").UI.Sticker.border.thin
		expect.truthy(inlineGap >= Theme.Padding.small + OUTLINE + pill)
		expect.truthy(stackedGap >= 2 + OUTLINE + pill)
		expect.truthy(room >= pill)
	end)

	t.test("measure matches the built tag both ways round", function()
		local inlineGap, room = parts(false)
		local stackedGap = parts(true)
		for _, rarity in { "Common", "Uncommon", "Epic", "Exclusive" } do
			local m = RarityTag.measure(rarity, PIP_PX)
			expect.truthy(m.pipsWidth > 0 and m.chipWidth > 0 and m.chipHeight > 0)
			expect.near(m.inlineWidth, m.pipsWidth + inlineGap + m.chipWidth + 2 * room, EPS)
			expect.near(m.inlineHeight, math.max(PIP_PX, m.chipHeight) + 2 * room, EPS)
			expect.near(m.stackedWidth, math.max(m.pipsWidth, m.chipWidth) + 2 * room, EPS)
			expect.near(m.stackedHeight, PIP_PX + stackedGap + m.chipHeight + 2 * room, EPS)
		end
		local unknown = RarityTag.measure("Mythic", PIP_PX)
		expect.deepEqual(unknown, {
			pipsWidth = 0,
			chipWidth = 0,
			chipHeight = 0,
			inlineWidth = 0,
			inlineHeight = 0,
			stackedWidth = 0,
			stackedHeight = 0,
		})
	end)

	t.test("setStacked switches the direction and the gap", function()
		local inlineGap = parts(false)
		local stackedGap = parts(true)
		local tag = RarityTag.new({ name = "Rarity", rarity = "Epic", pipSizePx = PIP_PX })
		local list = tag.root:FindFirstChildOfClass("UIListLayout") :: UIListLayout
		expect.equal(list.FillDirection, Enum.FillDirection.Horizontal)
		expect.equal(list.Padding.Offset, inlineGap)
		tag:setStacked(true)
		expect.equal(list.FillDirection, Enum.FillDirection.Vertical)
		expect.equal(list.Padding.Offset, stackedGap)
		tag:setStacked(false)
		expect.equal(list.Padding.Offset, inlineGap)
		tag:destroy()
	end)

	t.test("a diamond pip fits its pip box", function()
		local tag = RarityTag.new({ name = "Rarity", rarity = "Exclusive", pipSizePx = PIP_PX })
		local pips = tag.root:FindFirstChild("Pips") :: Frame
		local first = pips:FindFirstChild("Pip1") :: Frame
		local shape = first:FindFirstChild("Shape") :: Frame
		expect.equal(shape.Rotation, 45)
		-- A square rotated 45° spans its side × √2.
		expect.truthy(shape.Size.X.Scale * math.sqrt(2) <= 1 + EPS)
		tag:destroy()
	end)

	t.test("the design's pill: 22 px at least, the rarity's design colour, white outlined capitals", function()
		local RarityStyle = t.requireShared("Art/RarityStyle")
		local Palette = t.requireShared("Art/Palette")
		expect.equal(RarityTag.color("Common"), Color3.fromHex("#6F7D8B")) -- H:933
		expect.equal(RarityTag.color("Epic"), Color3.fromHex("#9A63E8")) -- lib:15
		expect.equal(RarityTag.color("Nope"), Theme.Colors.inkUI)
		expect.equal(RarityStyle.get("Uncommon").ui.light, Color3.fromHex("#D8F8E7")) -- lib:14
		for _, rarity in { "Common", "Uncommon", "Epic", "Exclusive" } do
			expect.truthy(RarityTag.measure(rarity).chipHeight >= 22)
			local tag = RarityTag.new({ name = "Rarity", rarity = rarity })
			local chip = tag.root:FindFirstChild("Chip") :: Frame
			local label = chip:FindFirstChild("Label") :: TextLabel
			expect.equal(chip.BackgroundColor3, RarityTag.color(rarity))
			expect.equal((chip:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, 3)
			expect.equal(label.Text, string.upper(label.Text))
			expect.equal(label.TextColor3, Palette.White)
			expect.truthy((label:FindFirstChild("SD_Outline") :: UIStroke).Enabled)
			local pip = (tag.root:FindFirstChild("Pips") :: Frame):FindFirstChild("Pip1") :: Frame
			local shape = pip:FindFirstChild("Shape") :: Frame
			expect.equal(shape.BackgroundColor3, RarityTag.color(rarity))
			-- The pips keep the bar outline (H:209 draws them bare; a reading), the pill the design's 3 px.
			expect.equal((shape:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness, Theme.Stroke.bar)
			tag:destroy()
		end
	end)

	t.test("tallest: the tallest side-by-side tag over every rarity (the room a detail keeps for it)", function()
		local Rarity = t.requireShared("Rarity")
		local tallest = 0
		for _, rarity in Rarity.ORDER do
			tallest = math.max(tallest, RarityTag.measure(rarity).inlineHeight)
		end
		expect.truthy(tallest > 0)
		expect.near(RarityTag.tallest(), tallest, EPS)
		local small = 0
		for _, rarity in Rarity.ORDER do
			small = math.max(small, RarityTag.measure(rarity, PIP_PX).inlineHeight)
		end
		expect.near(RarityTag.tallest(PIP_PX), small, EPS)
	end)
end
