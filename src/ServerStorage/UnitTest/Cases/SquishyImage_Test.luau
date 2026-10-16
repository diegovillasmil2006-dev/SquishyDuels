--!strict
-- SquishyImage_Test: StarterPlayerScripts.Client.UI.Components.SquishyImage, the UI FINAL R2 squishy picture (plan
-- work/ui/PLAN.md §2 toy thumbnails, T7, T8; `H:n` = "Squishy Duels HUD.dc.html" line n). Server only, Edit mode: built
-- unparented and destroyed.
-- Contract:
--   * every Catalog squishy has its AssetTable picture key img.squishy.<id> (pack 2; nil until uploaded);
--   * with the picture: an Image and, when asked, a Shadow copy `px` lower tinted the ink at `alpha`; not owned the
--     picture is the design's silhouette (black at ImageTransparency .58, H:922) with no shadow (H:936);
--   * while the picture has no id: the StaticIcon fallback (the 3D model) over the img.fx.glow ink shadow when a
--     shadow is asked for (none otherwise), hidden when not owned;
--   * setCatalogId rebuilds only on a new id; squash sizes the picture about its centre (the 3D fallback takes the
--     uniform part).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local SquishyImage = t.requireClient("UI/Components/SquishyImage")
	local AssetTable = t.requireShared("AssetTable")
	local Catalog = t.requireShared("Catalog")
	local Theme = t.requireClient("UI/Theme")

	t.test("every Catalog squishy has its picture key (pack 2)", function()
		local keys: { [string]: boolean } = {}
		for _, slot in AssetTable.all() do
			if slot.kind == "image" then
				keys[slot.key] = true
			end
		end
		for _, def in Catalog.list() do
			if not keys[SquishyImage.keyOf(def.id)] then
				error(`no AssetTable image key {SquishyImage.keyOf(def.id)}`)
			end
			if not keys[SquishyImage.keyOf(def.id) .. ".white"] then
				error(`no AssetTable image key {SquishyImage.keyOf(def.id)}.white`)
			end
		end
	end)

	t.test("the picture with its shadow and the silhouette, or the 3D fallback while it has no id", function()
		local id = Catalog.list()[1].id
		local image = SquishyImage.new(id, { size = 88, shadow = { px = 5, alpha = 0.3 } })
		local holder = image.root:FindFirstChild("Holder") :: Frame
		expect.truthy(image.root:FindFirstChild("Holder") ~= nil)
		expect.equal(image.root.Size, UDim2.fromOffset(88, 88))
		if AssetTable.image(SquishyImage.keyOf(id)) then
			local picture = holder:FindFirstChild("Image") :: ImageLabel
			local shadow = holder:FindFirstChild("Shadow") :: ImageLabel
			expect.truthy(holder:FindFirstChild("Image") ~= nil and holder:FindFirstChild("Shadow") ~= nil)
			expect.equal(shadow.Position, UDim2.fromOffset(0, 5))
			expect.near(shadow.ImageTransparency, 0.7, 1e-4)
			expect.equal(shadow.ImageColor3, Theme.Colors.inkUI)
			expect.near(picture.ImageTransparency, 0, 1e-4)
			image:setOwned(false)
			expect.equal(picture.ImageColor3, Color3.new(0, 0, 0))
			expect.near(picture.ImageTransparency, 0.58, 1e-4) -- H:922: brightness(0) opacity(.42)
			expect.falsy(shadow.Visible) -- H:936: the silhouette replaces the drop shadow
			image:setOwned(true)
			expect.near(picture.ImageTransparency, 0, 1e-4)
			expect.truthy(shadow.Visible)
			image:squash(1.2, 0.8)
			expect.equal(holder.Size, UDim2.fromScale(1.2, 0.8))
		else
			-- The 3D fallback: the StaticIcon over the ink glow (T7's How).
			expect.truthy(holder:FindFirstChild("Icon") ~= nil)
			expect.truthy((holder:FindFirstChild("Icon") :: Instance):IsA("ViewportFrame"))
			if AssetTable.image("img.fx.glow") then
				local glow = holder:FindFirstChild("Shadow") :: ImageLabel
				expect.truthy(holder:FindFirstChild("Shadow") ~= nil)
				expect.equal(glow.ImageColor3, Theme.Colors.inkUI)
				expect.equal(glow.Position, UDim2.new(0.5, 0, 0.5, 5))
				expect.near(glow.ImageTransparency, 0.7, 1e-4)
				image:setOwned(false) -- no error: the StaticIcon greys itself
				expect.falsy(glow.Visible)
				image:setOwned(true)
				expect.truthy(glow.Visible)
			end
			image:setOwned(false) -- no error: the StaticIcon greys itself
			-- A ViewportFrame cannot squash out of shape: the uniform part, the holder unchanged.
			image:squash(1.2, 0.8)
			expect.equal(holder.Size, UDim2.fromScale(1, 1))
			local uniform = (holder:FindFirstChild("Icon") :: Instance):FindFirstChild("SD_Squash") :: UIScale
			expect.near(uniform.Scale, math.sqrt(1.2 * 0.8), 1e-4)
		end
		expect.equal(image:catalogId(), id)
		local before = holder:GetChildren()[1]
		image:setCatalogId(id) -- the same id: nothing rebuilt
		expect.equal(holder:GetChildren()[1], before)
		local other = Catalog.list()[2].id
		image:setCatalogId(other)
		expect.equal(image:catalogId(), other)
		image:destroy()
		expect.equal(image.root.Parent, nil)
	end)

	t.test("no shadow asked for: no Shadow part (picture or 3D fallback)", function()
		local image = SquishyImage.new(Catalog.list()[1].id, { size = 88 })
		local holder = image.root:FindFirstChild("Holder") :: Frame
		expect.equal(holder:FindFirstChild("Shadow"), nil)
		image:setOwned(false)
		expect.equal(holder:FindFirstChild("Shadow"), nil)
		image:destroy()
	end)
end
