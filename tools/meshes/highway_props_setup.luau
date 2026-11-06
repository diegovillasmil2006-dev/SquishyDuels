-- Highway props setup (Studio command bar / MCP execute_luau, Edit mode), run once after File > Import 3D of
-- highway_props.py's SD_HighwayProps.glb (import name "SD_HighwayPropsImport", Anchored ticked, scale unit Stud).
-- Prepend the manifest as `local MANIFEST = { ["<id>__<key>"] = { cx, cy, cz, sx, sy, sz }, ... }`, generated from
-- manifest.json:
--   node -e 'const m=require("./manifest.json");console.log("local MANIFEST = {\n"+Object.entries(m.objects).map(
--     ([n,o])=>`\t["${n}"] = { ${o.center.join(", ")}, ${o.size.join(", ")} },`).join("\n")+"\n}")'
-- Moves every MeshPart into ServerStorage.SD_HighwayProps.<id> (a Model, pivot = the lane top centre) named by its
-- palette key, placed by the manifest centre and turned 180 degrees about Y (the importer turns a glTF scene that
-- way, see WorldLook.IMPORT_TURN). Art/HighwayTraps paints them at runtime.
local MANIFEST: { [string]: { number } } = MANIFEST

local ServerStorage = game:GetService("ServerStorage")
local import = workspace:FindFirstChild("SD_HighwayPropsImport")
assert(import, "import the .glb first (name SD_HighwayPropsImport)")

local TURN = CFrame.Angles(0, math.pi, 0)
local old = ServerStorage:FindFirstChild("SD_HighwayProps")
local folder = Instance.new("Folder")
folder.Name = "SD_HighwayProps"

local placed, problems = 0, {}
for _, part in import:GetDescendants() do
	if part:IsA("MeshPart") then
		local id, key = part.Name:match("^(.-)__(.+)$")
		local m = MANIFEST[part.Name]
		if id == nil or m == nil then
			table.insert(problems, "not in the manifest: " .. part.Name)
			continue
		end
		local size = Vector3.new(m[4], m[5], m[6])
		if (part.Size - size).Magnitude > 0.01 then
			table.insert(problems, ("%s size %s, manifest %s"):format(part.Name, tostring(part.Size), tostring(size)))
		end
		local model = folder:FindFirstChild(id)
		if model == nil then
			model = Instance.new("Model")
			model.Name = id
			model.Parent = folder
		end
		part.Name = key
		part.CFrame = CFrame.new(m[1], m[2], m[3]) * TURN
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = key ~= "Outline"
		part.CollisionFidelity = Enum.CollisionFidelity.Box
		part.Parent = model
		placed += 1
	end
end
for _, model in folder:GetChildren() do
	(model :: Model).WorldPivot = CFrame.identity
end
if #problems > 0 then
	folder:Destroy()
	return "NOT DONE:\n" .. table.concat(problems, "\n")
end
local pieces = #folder:GetChildren()
if old then -- a partial import (HIGHWAY_PROPS_ONLY) keeps the other pieces
	for _, model in folder:GetChildren() do
		local same = old:FindFirstChild(model.Name)
		if same then
			same:Destroy()
		end
		model.Parent = old
	end
	folder:Destroy()
else
	folder.Parent = ServerStorage
end
import:Destroy()
return ("placed %d mesh parts in %d pieces"):format(placed, pieces)
