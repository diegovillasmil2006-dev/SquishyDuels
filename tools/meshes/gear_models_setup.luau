-- gear_models_setup.luau (Studio, Edit mode; run with execute_luau). Big job item 9 (2026-11-10).
-- Files the gear models of tools/meshes/gear_models.py as ReplicatedStorage.SD_Gear.<line>_<tier> (28 Models).
-- The meshes come from 4 Model assets uploaded to the group (ids in ASSETS; see gear_models.py's header and
-- Claude-Backups\2026-11-10-gear\uploaded_ids.txt); manifest.json must be served on http://127.0.0.1:34901/ (the
-- scratchpad's file server), as for the other mesh setups.
-- Each Model: one MeshPart per colour key (named by the key) + "Outline" (the ink hull), painted from the manifest's
-- colours (Smooth = SmoothPlastic, Stud = SmoothPlastic + the SquishyStud tile, Neon, Glass = a little see-through),
-- anchored templates that collide with nothing; attributes SD_Line, SD_Tier and Grip (a held launcher's hand point).
-- The uploaded models arrive turned 180 degrees about Y (checked against the manifest below), so each Model's pivot
-- is turned back: PivotTo(cf) puts the piece's origin at cf with its front along cf's LookVector.
local H = game:GetService("HttpService")
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ASSETS = { held = 84253730838448, platform = 100856204232685, arm = 84089593315763, armor = 75925478279140 }
local STUD = "SquishyStud"
local TOLERANCE = 0.03

local was = H.HttpEnabled
H.HttpEnabled = true
local got, body = pcall(function()
	return H:GetAsync("http://127.0.0.1:34901/manifest.json", true)
end)
H.HttpEnabled = was
assert(got, "manifest.json is not served: " .. tostring(body))
local manifest = H:JSONDecode(body)

local folder = Instance.new("Folder")
folder.Name = "SD_Gear"
local parts, off = 0, {}
for line, id in ASSETS do
	local asset = InsertService:LoadAsset(id)
	for _, part in asset:GetDescendants() do
		if not part:IsA("MeshPart") then
			continue
		end
		local pieceId, key = string.match(part.Name, "^(.-)__(.+)$")
		local info = manifest.objects[part.Name]
		local piece = if pieceId then manifest.pieces[pieceId] else nil
		assert(info and piece and piece.line == line, "unknown mesh " .. part.Name)
		local want = Vector3.new(-info.center[1], info.center[2], -info.center[3]) -- the import's half turn
		local size = Vector3.new(info.size[1], info.size[2], info.size[3])
		if (part.Position - want).Magnitude > TOLERANCE or (part.Size - size).Magnitude > TOLERANCE then
			table.insert(off, part.Name)
		end
		local model = folder:FindFirstChild(pieceId)
		if model == nil then
			local made = Instance.new("Model")
			made.Name = pieceId
			made:SetAttribute("SD_Line", piece.line)
			made:SetAttribute("SD_Tier", piece.tier)
			made:SetAttribute("Grip", Vector3.new(piece.grip[1], piece.grip[2], piece.grip[3]))
			made.Parent = folder
			model = made
		end
		part.Name = key
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		if key == "Outline" then
			part.Color = Color3.fromHex(manifest.ink)
		else
			local look = piece.colors[key]
			part.Color = Color3.fromHex(look.hex)
			if look.kind == "Neon" then
				part.Material = Enum.Material.Neon
			elseif look.kind == "Stud" then
				part.MaterialVariant = STUD
			elseif look.kind == "Glass" then
				part.Transparency = 0.25
			end
		end
		part.Parent = model
		parts += 1
	end
	asset:Destroy()
end
local models = 0
for _, model in folder:GetChildren() do
	(model :: Model).WorldPivot = CFrame.Angles(0, math.pi, 0)
	models += 1
end
local old = ReplicatedStorage:FindFirstChild("SD_Gear")
if old then
	old.Parent = nil -- a re-run replaces the folder this script made before
end
folder.Parent = ReplicatedStorage
return string.format("SD_Gear: %d models, %d parts; %d parts off the manifest%s", models, parts, #off,
	if #off > 0 then ": " .. table.concat(off, ", ", 1, math.min(#off, 8)) else "")
