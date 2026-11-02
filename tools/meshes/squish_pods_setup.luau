-- Squish Pods setup (MCP execute_luau, Edit mode), run once after File > Import 3D of squish_pods.py's
-- SD_SquishPods.glb (import name "SD_SquishPodsImport", Anchored ticked, scale unit Stud). Like highway_props_setup.
-- Prepend the manifest as `local MANIFEST = { ["<piece>__<key>"] = { cx, cy, cz, sx, sy, sz }, ... }`, generated from
-- manifest.json:
--   node -e 'const m=require("./manifest.json");console.log("local MANIFEST = {\n"+Object.entries(m.objects).map(
--     ([n,o])=>`\t["${n}"] = { ${o.center.join(", ")}, ${o.size.join(", ")} },`).join("\n")+"\n}")'
-- Moves every MeshPart into ServerStorage.SD_SquishPods (a Folder) under its "<piece>__<key>" name, placed by the
-- manifest centre and turned 180 degrees about Y (the importer turns a glTF scene that way). SkyMapBuilder clones and
-- paints them per map (its pod()).
local MANIFEST: { [string]: { number } } = MANIFEST

local ServerStorage = game:GetService("ServerStorage")
local import = workspace:FindFirstChild("SD_SquishPodsImport")
assert(import, "import the .glb first (name SD_SquishPodsImport)")

local TURN = CFrame.Angles(0, math.pi, 0)
local old = ServerStorage:FindFirstChild("SD_SquishPods")
local folder = Instance.new("Folder")
folder.Name = "SD_SquishPods"

local placed, problems = 0, {}
for _, part in import:GetDescendants() do
	if part:IsA("MeshPart") then
		local m = MANIFEST[part.Name]
		if m == nil then
			table.insert(problems, "not in the manifest: " .. part.Name)
			continue
		end
		local size = Vector3.new(m[4], m[5], m[6])
		if (part.Size - size).Magnitude > 0.01 then
			table.insert(problems, ("%s size %s, manifest %s"):format(part.Name, tostring(part.Size), tostring(size)))
		end
		part.CFrame = CFrame.new(m[1], m[2], m[3]) * TURN
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CollisionFidelity = Enum.CollisionFidelity.Box
		part.Parent = folder
		placed += 1
	end
end
if #problems > 0 or placed ~= #(function()
	local names = {}
	for name in MANIFEST do
		table.insert(names, name)
	end
	return names
end)() then
	folder:Destroy()
	return "NOT DONE (" .. placed .. " placed):\n" .. table.concat(problems, "\n")
end
if old then
	old:Destroy()
end
folder.Parent = ServerStorage
import:Destroy()
return ("placed %d mesh parts in ServerStorage.SD_SquishPods"):format(placed)
