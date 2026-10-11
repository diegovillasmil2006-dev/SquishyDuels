--!strict
-- IconGlyph_Test: StarterPlayerScripts.Client.UI.Components.IconGlyph. Server only (ServerStorage.UnitTest). Edit mode:
-- the icons are built unparented and destroyed.
-- Contract (foam UI restyle, spec 2026-10-09, user decision 2 "placeholder icons built from shapes"):
--   * the eleven icons of the spec exist (squishies, boxes, shop, quests, daily, settings, duel / swords, change,
--     clock, upgrade, inspect), each with placeholder parts inside its 0..1 box and at least one silhouette part;
--   * each reads an AssetTable image slot (img.nav.* or img.icon.*) that exists; with every id nil today the
--     placeholder is drawn: an InkUI outline copy and a fill per silhouette part, the details on top;
--   * the tones recolour without rebuilding; setIcon rebuilds; an unknown icon draws nothing and never errors.

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
		local icon = IconGlyph.new({ name = "Icon", icon = "settings", sizePx = 32, parent = holder })
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
		icon:setIcon("clock")
		expect.equal(icon:icon(), "clock")
		expect.equal(countNamed(icon.root, "Fill"), 1) -- the clock face
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

	t.test("the outline grows with the icon inside its limits", function()
		expect.near(IconGlyph.outlinePx(10), 1.5, 1e-9)
		expect.near(IconGlyph.outlinePx(40), 2.4, 1e-9)
		expect.near(IconGlyph.outlinePx(200), 3, 1e-9)
	end)
end
