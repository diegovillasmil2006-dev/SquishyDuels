--!strict
-- SideIcon_Test: unit tests for StarterPlayerScripts.Client.UI.Components.SideIcon. Server only
-- (ServerStorage.UnitTest). Edit mode: the icons are built unparented and destroyed.
-- Contract (DESIGN §7.8 "always labelled with text and icon in the UI, never colour alone", §11.6):
--   * side "A" (Strawberry side) shows the berry, side "B" (Mint side) the mint leaf, like DuelFormat.sideText;
--   * the two icons differ in shape, not only in colour (round berry with a leaf cap vs. a diamond leaf with a vein);
--   * setSide switches the icon in place; destroy removes it.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local SideIcon = t.requireClient("UI/Components/SideIcon")
	local expect = t.expect

	t.test("side A is the strawberry, side B the mint leaf", function()
		expect.equal(SideIcon.kindOf("A"), "strawberry")
		expect.equal(SideIcon.kindOf("B"), "mint")
	end)

	t.test("the icon shows one shape for its side and switches in place", function()
		local holder = Instance.new("Folder")
		local icon = SideIcon.new({ name = "SideIcon", side = "A", parent = holder })
		expect.equal(icon.root.Parent, holder)
		expect.truthy(icon.root:FindFirstChild("Strawberry") and icon.root:FindFirstChild("Mint"))
		local strawberry = icon.root:FindFirstChild("Strawberry") :: Frame
		local mint = icon.root:FindFirstChild("Mint") :: Frame
		expect.equal(icon:kind(), "strawberry")
		expect.truthy(strawberry.Visible)
		expect.falsy(mint.Visible)
		icon:setSide("B")
		expect.equal(icon:kind(), "mint")
		expect.falsy(strawberry.Visible)
		expect.truthy(mint.Visible)
		icon:destroy()
		expect.equal(#holder:GetChildren(), 0)
		holder:Destroy()
	end)

	t.test("the two shapes differ in outline, not only in colour", function()
		local icon = SideIcon.new({ name = "SideIcon", side = "A" })
		local strawberry = icon.root:FindFirstChild("Strawberry") :: Frame
		local mint = icon.root:FindFirstChild("Mint") :: Frame
		-- The berry: a round body (corner 0.5) under a leaf cap.
		expect.truthy(strawberry:FindFirstChild("Body"))
		local body = strawberry:FindFirstChild("Body") :: Frame
		local bodyCorner = body:FindFirstChildOfClass("UICorner") :: UICorner
		expect.equal(bodyCorner.CornerRadius.Scale, 0.5)
		expect.truthy(strawberry:FindFirstChild("Leaf1") ~= nil and strawberry:FindFirstChild("Leaf2") ~= nil)
		-- The mint leaf: a diamond (a rounded square turned 45°) with a centre vein.
		expect.truthy(mint:FindFirstChild("Leaf"))
		local leaf = mint:FindFirstChild("Leaf") :: Frame
		expect.equal(leaf.Rotation, 45)
		expect.truthy(leaf:FindFirstChild("Vein") ~= nil)
		expect.truthy((leaf:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius.Scale < 0.5)
		icon:destroy()
	end)
end
