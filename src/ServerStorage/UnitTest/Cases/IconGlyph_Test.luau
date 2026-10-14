--!strict
-- IconGlyph_Test: StarterPlayerScripts.Client.UI.Components.IconGlyph. Server only (ServerStorage.UnitTest). Edit mode:
-- the icons are built unparented and destroyed.
-- Contract (foam UI restyle, spec 2026-10-09, user decision 2 "placeholder icons built from shapes"):
--   * the eleven icons of the spec exist (squishies, boxes, shop, quests, daily, settings, duel / swords, change,
--     clock, upgrade, inspect), each with placeholder parts inside its 0..1 box and at least one silhouette part;
--   * each reads an AssetTable image slot (img.nav.* or img.icon.*) that exists; with every id nil today the
--     placeholder is drawn: an InkUI outline copy and a fill per silhouette part, the details on top;
--   * the tones recolour without rebuilding; setIcon rebuilds; an unknown icon draws nothing and never errors.
--   * UI FINAL R1 (plan §3): IconGlyph.image(key, props) holds the picture (and with props.shadow its drop shadow
--     behind it, px lower at the alpha) and hides itself while the id is nil; the image-only keys are not
--     IconGlyph.NAMES.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local SPEC_ICONS = {
	"squishies",
	"boxes",
	"shop",
	"quests",
	"daily",
	"settings",
	"duel",
	"change",
	"clock",
	"upgrade",
	"inspect",
	-- UI overhaul (2026-10-11).
	"close",
	"check",
}

local function countNamed(root: Instance, name: string): number
	local n = 0
	for _, child in root:GetChildren() do
		if child.Name == name then
			n += 1
		end
	end
	return n
end

return function(t: Context)
	local expect = t.expect
	local IconGlyph = t.requireClient("UI/Components/IconGlyph")
	local Theme = t.requireClient("UI/Theme")
	local AssetTable = t.requireShared("AssetTable")

	local imageKeys: { [string]: boolean } = {}
	for _, slot in AssetTable.all() do
		if slot.kind == "image" then
			imageKeys[slot.key] = true
		end
	end

	t.test("the spec's icons (eleven, plus the overhaul's close and check), each with an image slot and parts inside its box", function()
		expect.deepEqual(IconGlyph.NAMES, SPEC_ICONS)
		for _, name in SPEC_ICONS do
			local slot = IconGlyph.slotOf(name)
			if not (slot and imageKeys[slot]) then
				error(`{name} has no AssetTable image slot ({tostring(slot)})`)
			end
			local parts = IconGlyph.parts(name)
			local silhouettes = 0
			for index, part in parts do
				for _, field in { "x", "y", "w", "h" } do
					local v = part[field]
					if not (type(v) == "number" and v >= 0 and v <= 1) then
						error(`{name} part {index}: {field} = {tostring(v)} is outside the 0..1 box`)
					end
				end
				if not part.detail then
					silhouettes += 1
				end
			end
			if silhouettes == 0 then
				error(`{name} has no silhouette part`)
			end
		end
		expect.equal(IconGlyph.slotOf("swords"), IconGlyph.slotOf("duel"))
		expect.equal(IconGlyph.slotOf("nope"), nil)
		expect.deepEqual(IconGlyph.parts("nope"), {})
	end)

	t.test("with a nil slot the placeholder is drawn: an outline and a fill per silhouette part", function()
		for _, name in SPEC_ICONS do
			local slot = IconGlyph.slotOf(name) :: string
			if AssetTable.image(slot) == nil then
				local icon = IconGlyph.new({ name = "Icon", icon = name, sizePx = 40 })
				local silhouettes, details = 0, 0
				for _, part in IconGlyph.parts(name) do
					if part.detail then
						details += 1
					else
						silhouettes += 1
					end
				end
				expect.equal(countNamed(icon.root, "Outline"), silhouettes)
				expect.equal(countNamed(icon.root, "Fill"), silhouettes)
				expect.equal(countNamed(icon.root, "Detail"), details)
				expect.equal(icon.root:FindFirstChild("Image"), nil)
				expect.equal(icon:icon(), name)
				icon:destroy()
			end
		end
	end)

	t.test("tones recolour in place; setIcon rebuilds; an unknown icon is blank", function()
		local holder = Instance.new("Folder")
		-- UI FINAL R10: "settings" and "clock" now show the uploaded pictures; "upgrade" and "inspect" stay shape-drawn
		-- (no design art, UI FINAL plan §3), so they keep testing the placeholder path.
		local icon = IconGlyph.new({ name = "Icon", icon = "upgrade", sizePx = 32, parent = holder })
		expect.equal(icon.root.Parent, holder)
		local fill = icon.root:FindFirstChild("Fill") :: Frame
		local outline = icon.root:FindFirstChild("Outline") :: Frame
		expect.equal(fill.BackgroundColor3, Theme.Colors.white)
		expect.truthy(outline.Visible)
		expect.equal(outline.BackgroundColor3, Theme.Colors.inkUI)
		icon:setTone("dark")
		expect.equal(fill.BackgroundColor3, Theme.Colors.inkUI)
		expect.falsy(outline.Visible)
		expect.equal(icon.root:FindFirstChild("Fill"), fill) -- same instances
		icon:setIcon("inspect")
		expect.equal(icon:icon(), "inspect")
		local silhouettes = 0
		for _, p in IconGlyph.parts("inspect") do
			if not p.detail then
				silhouettes += 1
			end
		end
		expect.equal(countNamed(icon.root, "Fill"), silhouettes)
		expect.equal((icon.root:FindFirstChild("Fill") :: Frame).BackgroundColor3, Theme.Colors.inkUI) -- tone kept
		icon:setIcon("nope")
		expect.equal(#icon.root:GetChildren(), 0)
		icon:destroy()
		expect.equal(#holder:GetChildren(), 0)
		holder:Destroy()
	end)

	t.test("the shop reads as a storefront: a wide awning over a narrower shop, no marks across the awning", function()
		-- Foam fix: the old glyph's two stripes cut the awning into blocks and read as a castle's battlements.
		local awning: any, body: any = nil, nil
		local details: { any } = {}
		for _, part in IconGlyph.parts("shop") do
			if part.detail then
				table.insert(details, part)
			else
				if awning == nil or part.y < awning.y then
					awning = part
				end
				if body == nil or part.y > body.y then
					body = part
				end
			end
		end
		assert(awning and body, "the shop has silhouette parts")
		expect.truthy(awning.w > body.w) -- the awning overhangs the shop on both sides
		expect.truthy(awning.y + awning.h / 2 <= body.y - body.h / 2) -- above it, apart from it
		for _, mark in details do
			-- The window and the door sit on the shop, under the awning.
			expect.truthy(mark.y - mark.h / 2 >= awning.y + awning.h / 2)
		end
	end)

	t.test("image(): the picture and its shadow, hidden while the id is nil; not a drawn icon", function()
		local holder = Instance.new("Folder")
		local key = "img.icon.star"
		expect.truthy(imageKeys[key])
		local icon = IconGlyph.image(key, {
			name = "Star",
			sizePx = 40,
			layoutOrder = 3,
			parent = holder,
			shadow = { px = 5, alpha = 0.3 },
		})
		expect.equal(icon.Parent, holder)
		expect.equal(icon.Name, "Star")
		expect.equal(icon.Size, UDim2.fromOffset(40, 40))
		expect.equal(icon.LayoutOrder, 3)
		expect.equal(icon.Visible, AssetTable.image(key) ~= nil)
		local image = icon:FindFirstChild("Image") :: ImageLabel
		local shadow = icon:FindFirstChild("Shadow") :: ImageLabel
		expect.truthy(icon:FindFirstChild("Image") ~= nil and icon:FindFirstChild("Shadow") ~= nil)
		expect.equal(shadow.Position.Y.Offset, 5)
		expect.near(shadow.ImageTransparency, 0.7, 1e-4)
		expect.equal(shadow.ImageColor3, Theme.Colors.inkUI)
		expect.truthy(shadow.ZIndex < image.ZIndex)
		-- No shadow unless asked; image-only keys are not IconGlyph names.
		local plain = IconGlyph.image("img.icon.bolt", { name = "Bolt" })
		expect.equal(plain:FindFirstChild("Shadow"), nil)
		plain:Destroy()
		expect.equal(IconGlyph.canonical("star"), nil)
		holder:Destroy()
	end)

	t.test("the outline grows with the icon inside its limits", function()
		expect.near(IconGlyph.outlinePx(10), 1.5, 1e-9)
		expect.near(IconGlyph.outlinePx(40), 2.4, 1e-9)
		expect.near(IconGlyph.outlinePx(200), 3, 1e-9)
	end)
end
