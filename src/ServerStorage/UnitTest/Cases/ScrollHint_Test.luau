--!strict
-- ScrollHint_Test: StarterPlayerScripts.Client.UI.Components.ScrollHint (foam fix round 2). Server only
-- (ServerStorage.UnitTest). Edit mode: built in a Folder-like holder and destroyed; nothing scrolls and no input is
-- touch, so the rail stays hidden.
-- Contract (DESIGN §11.2 as built, fix round 2): the rail ("ScrollRail", or the given name) holds a "Thumb"; neither is
-- Active or Selectable, so it never takes a tap or the gamepad focus; it sits over the list (ZIndex 2), starts hidden
-- while the list fits, parents itself where it is told, and destroy removes it. Its maths is Layout.scrollThumb
-- (UILayout_Test).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local ScrollHint = t.requireClient("UI/Components/ScrollHint")

	t.test("the rail and its thumb: inactive, over the list, hidden while the list fits, gone after destroy", function()
		local holder = Instance.new("Frame")
		local list = Instance.new("ScrollingFrame")
		list.Parent = holder
		local hint = ScrollHint.new({ scroll = list, parent = holder })
		local rail = hint.root
		expect.equal(rail.Name, "ScrollRail")
		expect.equal(rail.Parent, holder)
		local thumb = rail:FindFirstChild("Thumb")
		expect.truthy(thumb ~= nil and thumb:IsA("Frame"))
		for _, part in { rail, thumb :: Frame } do
			expect.equal(part.Active, false)
			expect.equal(part.Selectable, false)
		end
		expect.truthy(rail.ZIndex > list.ZIndex)
		expect.equal(rail.Visible, false)
		hint:destroy()
		expect.equal(holder:FindFirstChild("ScrollRail"), nil)
		local named = ScrollHint.new({ scroll = list, parent = holder, name = "InfoRail" })
		expect.equal(named.root.Name, "InfoRail")
		named:destroy()
		holder:Destroy()
	end)
end
