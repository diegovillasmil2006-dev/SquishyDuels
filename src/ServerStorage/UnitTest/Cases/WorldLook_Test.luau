--!strict
-- WorldLook_Test: unit tests for ServerStorage.SDTools.Kit.WorldLook, the lobby look upgrade's numbers and its finish
-- pass (user OK 2026-10-14, "do fixes from 1 to 3": FIX 2 finishes, FIX 3 the Blender mesh library). Server only
-- (ServerStorage.UnitTest). Contract:
--   * finish(root, palette) gives every visible SmoothPlastic part whose colour is a FINISH token that token's material
--     and reflectance; a MeshPart keeps SmoothPlastic (it takes only the reflectance); toys (an SD_BlueprintId model),
--     Neon and invisible parts are left alone; reflectance never goes down;
--   * a palette without a FINISH token, or with two FINISH tokens of one colour, fails loudly (the pass matches by
--     colour); the real Art/Palette passes;
--   * meshTemplates(library, pieces) gives a set's library MeshParts by name, at any depth (inside a same-named
--     wrapper Model too) and any uniform scale, or nil with no library or a missing, plain (not MeshPart),
--     unarchivable or turned piece; MESHES names a piece once.
-- A fake palette gives every FINISH token its own colour, so the cases do not depend on the real hexes; a fake library
-- of MeshParts without a MeshId stands in for the user's import. Every instance stays in memory and is destroyed.

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

local TOLERANCE = 1e-3 -- Reflectance is stored in single precision

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local function loadWorldLook(): (any, Instance)
	local source = ServerStorage:FindFirstChild("SDTools")
	if source == nil then
		error("ServerStorage.SDTools not found (is Rojo connected?)")
	end
	local clone = source:Clone()
	local kit = clone:FindFirstChild("Kit")
	local module = if kit then kit:FindFirstChild("WorldLook") else nil
	if module == nil or not module:IsA("ModuleScript") then
		clone:Destroy()
		error("SDTools.Kit.WorldLook is missing")
	end
	return dynamicRequire(module), clone
end

return function(t: Context)
	local WorldLook, toolsClone = loadWorldLook()
	local expect = t.expect

	-- Every FINISH token in its own colour (sorted, so the colours never depend on table order).
	local function fakePalette(): { [string]: any }
		local tokens = {}
		for token in WorldLook.FINISH do
			table.insert(tokens, token)
		end
		table.sort(tokens)
		local palette: { [string]: any } = {}
		for index, token in tokens do
			palette[token] = Color3.fromRGB(index, 100, 200)
		end
		return palette
	end

	local function part(parent: Instance, className: string, color: Color3): BasePart
		local p = Instance.new(className) :: BasePart
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = parent
		return p
	end

	t.test("a FINISH colour gives its material; a MeshPart keeps SmoothPlastic, takes only the shine", function()
		local palette = fakePalette()
		local root = Instance.new("Folder")
		local grass = part(root, "Part", palette.IslandGrass)
		local meshGrass = part(root, "MeshPart", palette.IslandGrass)
		local gold = part(root, "Part", palette.LobbyGold)
		local meshGold = part(root, "MeshPart", palette.LobbyGold)
		local other = part(root, "Part", Color3.fromRGB(1, 2, 3))
		WorldLook.finish(root, palette)
		expect.equal(grass.Material, Enum.Material.Grass)
		expect.equal(meshGrass.Material, Enum.Material.SmoothPlastic) -- no UVs for a textured material
		expect.equal(gold.Material, Enum.Material.SmoothPlastic)
		expect.near(gold.Reflectance, WorldLook.FINISH.LobbyGold.reflectance, TOLERANCE)
		expect.near(meshGold.Reflectance, WorldLook.FINISH.LobbyGold.reflectance, TOLERANCE)
		expect.equal(other.Material, Enum.Material.SmoothPlastic)
		expect.equal(other.Reflectance, 0)
		root:Destroy()
	end)

	t.test("toys, Neon, other materials and invisible parts keep their look; reflectance never goes down", function()
		local palette = fakePalette()
		local root = Instance.new("Folder")
		local toy = Instance.new("Model")
		toy:SetAttribute("SD_BlueprintId", "butter")
		toy.Parent = root
		local inner = Instance.new("Model") -- a toy part one level down is still the toy's
		inner.Parent = toy
		local toyPart = part(inner, "Part", palette.IslandGrass)
		local neon = part(root, "Part", palette.IslandGrass)
		neon.Material = Enum.Material.Neon
		local plastic = part(root, "Part", palette.IslandGrass)
		plastic.Material = Enum.Material.Plastic -- the plots' studded floors stay Plastic
		local hidden = part(root, "Part", palette.LobbyGold)
		hidden.Transparency = 1
		local shiny = part(root, "Part", palette.LobbyGold)
		shiny.Reflectance = 0.3
		WorldLook.finish(root, palette)
		expect.equal(toyPart.Material, Enum.Material.SmoothPlastic)
		expect.equal(toyPart.Reflectance, 0)
		expect.truthy(WorldLook.inToy(toyPart, root))
		expect.falsy(WorldLook.inToy(neon, root))
		expect.equal(neon.Material, Enum.Material.Neon)
		expect.equal(plastic.Material, Enum.Material.Plastic)
		expect.equal(hidden.Reflectance, 0)
		expect.near(shiny.Reflectance, 0.3, TOLERANCE)
		root:Destroy()
	end)

	t.test("a palette without a FINISH token, or with two FINISH tokens of one colour, fails loudly", function()
		local missing = fakePalette()
		missing.IslandSand = nil
		expect.throws(function()
			WorldLook.finish(Instance.new("Folder"), missing)
		end, "IslandSand")
		local twins = fakePalette()
		twins.IslandSand = twins.IslandGrass
		expect.throws(function()
			WorldLook.finish(Instance.new("Folder"), twins)
		end, "share the colour")
	end)

	t.test("the real Art/Palette holds every FINISH, LAMPS and HALO token, each FINISH colour once", function()
		local Palette = t.requireShared("Art/Palette")
		WorldLook.finish(Instance.new("Folder"), Palette) -- throws on a missing or shared colour
		for _, lamp in WorldLook.LAMPS do
			expect.equal(typeof(Palette[lamp.token]), "Color3")
		end
		expect.equal(typeof(Palette[WorldLook.HALO.token]), "Color3")
	end)

	-- FIX 3: a fake set and a library of MeshParts at `scale` (only names, classes and sizes are read).
	local PIECES = {
		{ name = "Body", size = Vector3.new(2, 1, 2), center = Vector3.zero },
		{ name = "Ear", size = Vector3.new(0.5, 3, 0.5), center = Vector3.new(0, 2, 0) },
	}
	local function library(scale: number): Folder
		local folder = Instance.new("Folder")
		for _, piece in PIECES do
			local mesh = Instance.new("MeshPart")
			mesh.Name = piece.name
			mesh.Size = piece.size * scale
			mesh.Parent = folder
		end
		return folder
	end

	t.test("meshTemplates: the library's MeshParts by name, nested one level down, at any uniform scale", function()
		local folder = library(3)
		local inner = Instance.new("Model") -- the 3D importer may group the pieces
		inner.Parent = folder
		local ear = folder:FindFirstChild("Ear") :: Instance
		ear.Parent = inner
		local found = WorldLook.meshTemplates(folder, PIECES)
		expect.truthy(found ~= nil)
		expect.equal(found.Body, folder:FindFirstChild("Body"))
		expect.equal(found.Ear, ear)
		folder:Destroy()
	end)

	t.test("meshTemplates: a MeshPart inside a same-named Model (an importer wrapper) is still found", function()
		local folder = library(1)
		local ear = folder:FindFirstChild("Ear") :: Instance
		local wrapper = Instance.new("Model")
		wrapper.Name = "Ear"
		wrapper.Parent = folder
		ear.Parent = wrapper
		local found = WorldLook.meshTemplates(folder, PIECES)
		expect.truthy(found ~= nil)
		expect.equal(found and found.Ear, ear)
		folder:Destroy()
	end)

	t.test("meshTemplates: nil with no library, or a missing, plain, unarchivable or turned piece", function()
		expect.equal(WorldLook.meshTemplates(nil, PIECES), nil)
		local missing = library(1)
		local gone = missing:FindFirstChild("Ear") :: Instance
		gone:Destroy()
		expect.equal(WorldLook.meshTemplates(missing, PIECES), nil)
		local plain = library(1)
		local meshEar = plain:FindFirstChild("Ear") :: Instance
		meshEar:Destroy()
		local plainEar = Instance.new("Part")
		plainEar.Name = "Ear"
		plainEar.Size = PIECES[2].size
		plainEar.Parent = plain
		expect.equal(WorldLook.meshTemplates(plain, PIECES), nil)
		local locked = library(1)
		local lockedBody = locked:FindFirstChild("Body") :: Instance
		lockedBody.Archivable = false -- Clone() would return nil
		expect.equal(WorldLook.meshTemplates(locked, PIECES), nil)
		local turned = library(1)
		local turnedBody = turned:FindFirstChild("Body") :: BasePart
		turnedBody.Size = Vector3.new(1, 2, 2) -- (2, 1, 2) turned on its side
		expect.equal(WorldLook.meshTemplates(turned, PIECES), nil)
		for _, folder in { missing, plain, locked, turned } do
			folder:Destroy()
		end
	end)

	t.test("MESHES: the 5 round-1 sets, 13 pieces, every name once (the library is searched by name)", function()
		local sets, names = 0, {}
		for _, pieces in WorldLook.MESHES do
			sets += 1
			for _, piece in pieces do
				expect.falsy(names[piece.name])
				names[piece.name] = true
				expect.truthy(piece.size.X > 0 and piece.size.Y > 0 and piece.size.Z > 0)
			end
		end
		local count = 0
		for _ in names do
			count += 1
		end
		expect.equal(sets, 5)
		expect.equal(count, 13)
		expect.equal(WorldLook.MESH_LIBRARY, "SD_MeshLibrary")
		expect.equal(WorldLook.MESH_APPROVED, "SD_MeshesApproved") -- the coordinator sets it after Roblox's check
		expect.near(WorldLook.IMPORT_TURN.LookVector.Z, 1, 1e-6) -- a half turn about Y (the importer's turn, undone)
		expect.near(WorldLook.IMPORT_TURN.UpVector.Y, 1, 1e-6)
	end)

	t.test("teardown", function()
		toolsClone:Destroy()
	end)
end
