--!strict
-- Generated_Test: unit tests for ServerStorage.SDTools.Generated. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §1.7, §2.9): mark() tags a root SD_Generated and writes SD_GeneratorId, SD_GeneratorVersion
-- (integer) and SD_BuiltAt; findRoots(id, scope?) returns only tagged roots of that generator (never untagged
-- look-alikes, never instances outside the place when no scope is given); swap(old, new, parent) removes the old
-- roots with Parent = nil (undoable: not destroyed), parents the new root, and never touches untagged instances.
-- Every case uses in-memory folders: nothing is parented into the place.
-- RunUnitTest passes no editor folder, so the module is a fresh clone of ServerStorage.SDTools.Generated (a clone
-- also defeats the require cache). Generated has no requires, so the lone clone works.

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local TAG = "SD_Generated"
local ATTR_ID = "SD_GeneratorId"
local ATTR_VERSION = "SD_GeneratorVersion"
local ATTR_BUILT_AT = "SD_BuiltAt"

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local function loadGenerated(): (any, Instance)
	local tools = ServerStorage:FindFirstChild("SDTools")
	local source = if tools then tools:FindFirstChild("Generated") else nil
	if source == nil or not source:IsA("ModuleScript") then
		error("ServerStorage.SDTools.Generated not found (is Rojo connected?)")
	end
	local clone = source:Clone()
	return dynamicRequire(clone), clone
end

return function(t: Context)
	local Generated, moduleClone = loadGenerated()
	local Cleanup = t.requireShared("Util/Cleanup")
	local expect = t.expect

	-- A Folder owned by `scratch`, optionally parented (always to another in-memory folder).
	local function folder(scratch: any, name: string, parent: Instance?): Folder
		local f = Instance.new("Folder")
		scratch:add(f)
		f.Name = name
		f.Parent = parent
		return f
	end

	-- mark ------------------------------------------------------------------------------------------------------

	t.test("mark tags the root and writes id, integer version and build time", function()
		local scratch = Cleanup.new()
		local root = folder(scratch, "SD_ShapeLibrary")
		Generated.mark(root, "shapes", 3)
		expect.truthy(root:HasTag(TAG))
		expect.equal(root:GetAttribute(ATTR_ID), "shapes")
		expect.equal(root:GetAttribute(ATTR_VERSION), 3)
		local builtAt = root:GetAttribute(ATTR_BUILT_AT)
		expect.equal(type(builtAt), "string")
		expect.truthy(#(builtAt :: string) > 0)
		scratch:clean()
	end)

	t.test("mark rejects an invalid id or version and leaves the root unmarked", function()
		local scratch = Cleanup.new()
		local root = folder(scratch, "Root")
		expect.throws(function()
			Generated.mark(root, "", 1)
		end)
		expect.throws(function()
			Generated.mark(root, "Shapes!", 1)
		end)
		expect.throws(function()
			Generated.mark(root, "shapes", 0)
		end)
		expect.throws(function()
			Generated.mark(root, "shapes", 1.5)
		end)
		expect.throws(function()
			(Generated :: any).mark(root, "shapes", nil)
		end)
		expect.falsy(root:HasTag(TAG))
		expect.equal(root:GetAttribute(ATTR_ID), nil)
		scratch:clean()
	end)

	-- findRoots -------------------------------------------------------------------------------------------------

	t.test("findRoots in a scope returns only tagged roots of that generator", function()
		local scratch = Cleanup.new()
		local scope = folder(scratch, "Place")
		local shapes = Generated.mark(folder(scratch, "SD_ShapeLibrary", scope), "shapes", 1)
		Generated.mark(folder(scratch, "SD_Lobby", scope), "lobby", 1)
		folder(scratch, "SD_ShapeLibrary", scope) -- untagged look-alike
		local attributeOnly = folder(scratch, "AttributeOnly", scope)
		attributeOnly:SetAttribute(ATTR_ID, "shapes") -- attribute without the tag
		attributeOnly:SetAttribute(ATTR_VERSION, 1)
		local deep = Generated.mark(folder(scratch, "Deep", folder(scratch, "Holder", scope)), "shapes", 2)

		local found = Generated.findRoots("shapes", scope)
		expect.equal(#found, 2)
		local set = {}
		for _, instance in found do
			set[instance] = true
		end
		expect.truthy(set[shapes])
		expect.truthy(set[deep])
		scratch:clean()
	end)

	t.test("findRoots without a scope ignores roots outside the place", function()
		local scratch = Cleanup.new()
		Generated.mark(folder(scratch, "Probe"), "unit_test_probe", 1)
		expect.equal(#Generated.findRoots("unit_test_probe"), 0)
		scratch:clean()
	end)

	-- swap ------------------------------------------------------------------------------------------------------

	t.test("swap unparents the old root without destroying it and parents the new root", function()
		local scratch = Cleanup.new()
		local place = folder(scratch, "Place")
		local old = Generated.mark(folder(scratch, "SD_ShapeLibrary", place), "shapes", 1)
		local oldChild = folder(scratch, "RoundedBox", old)
		local new = Generated.mark(folder(scratch, "SD_ShapeLibrary"), "shapes", 2)

		local removed = Generated.swap({ old }, new, place)

		expect.equal(removed, 1)
		expect.equal(old.Parent, nil)
		expect.equal(oldChild.Parent, old) -- contents kept, so undo restores the whole tree
		expect.equal(new.Parent, place)
		old.Parent = place -- a destroyed instance could not be re-parented (this is what Undo does)
		expect.equal(old.Parent, place)
		scratch:clean()
	end)

	t.test("swap with no old roots only parents the new root", function()
		local scratch = Cleanup.new()
		local place = folder(scratch, "Place")
		local new = Generated.mark(folder(scratch, "SD_ShapeLibrary"), "shapes", 1)
		expect.equal(Generated.swap({}, new, place), 0)
		expect.equal(new.Parent, place)
		scratch:clean()
	end)

	t.test("swap leaves untagged look-alikes in place", function()
		local scratch = Cleanup.new()
		local place = folder(scratch, "Place")
		local untagged = folder(scratch, "SD_ShapeLibrary", place)
		local old = Generated.mark(folder(scratch, "SD_ShapeLibrary", place), "shapes", 1)
		local new = Generated.mark(folder(scratch, "SD_ShapeLibrary"), "shapes", 2)

		Generated.swap(Generated.findRoots("shapes", place), new, place)

		expect.equal(untagged.Parent, place)
		expect.equal(old.Parent, nil)
		expect.equal(new.Parent, place)
		scratch:clean()
	end)

	t.test("swap refuses an untagged or foreign old root and changes nothing", function()
		local scratch = Cleanup.new()
		local place = folder(scratch, "Place")
		local old = Generated.mark(folder(scratch, "SD_ShapeLibrary", place), "shapes", 1)
		local untagged = folder(scratch, "Manual", place)
		local lobby = Generated.mark(folder(scratch, "SD_Lobby", place), "lobby", 1)
		local new = Generated.mark(folder(scratch, "SD_ShapeLibrary"), "shapes", 2)

		expect.throws(function()
			Generated.swap({ old, untagged }, new, place)
		end)
		expect.throws(function()
			Generated.swap({ old, lobby }, new, place)
		end)

		expect.equal(old.Parent, place)
		expect.equal(untagged.Parent, place)
		expect.equal(lobby.Parent, place)
		expect.equal(new.Parent, nil)
		scratch:clean()
	end)

	t.test("swap refuses an unmarked new root and changes nothing", function()
		local scratch = Cleanup.new()
		local place = folder(scratch, "Place")
		local old = Generated.mark(folder(scratch, "SD_ShapeLibrary", place), "shapes", 1)
		local unmarked = folder(scratch, "SD_ShapeLibrary")

		expect.throws(function()
			Generated.swap({ old }, unmarked, place)
		end)

		expect.equal(old.Parent, place)
		expect.equal(unmarked.Parent, nil)
		scratch:clean()
	end)

	t.test("building twice leaves exactly one root of the generator", function()
		local scratch = Cleanup.new()
		local place = folder(scratch, "Place")
		local first = Generated.mark(folder(scratch, "SD_ShapeLibrary"), "shapes", 1)
		Generated.swap(Generated.findRoots("shapes", place), first, place)
		local second = Generated.mark(folder(scratch, "SD_ShapeLibrary"), "shapes", 1)
		local removed = Generated.swap(Generated.findRoots("shapes", place), second, place)

		expect.equal(removed, 1)
		local roots = Generated.findRoots("shapes", place)
		expect.equal(#roots, 1)
		expect.equal(roots[1], second)
		expect.equal(first.Parent, nil)
		scratch:clean()
	end)

	moduleClone:Destroy()
end
