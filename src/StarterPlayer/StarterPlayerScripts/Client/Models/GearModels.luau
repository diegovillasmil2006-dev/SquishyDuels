--!strict
-- GearModels (client only). Big job items 9 and 10 (2026-11-10): a clone of a gear piece's model from
-- ReplicatedStorage.SD_Gear (tools/meshes/gear_models.py; the names: Shared/GearLooks.modelName), for the pieces players
-- wear (Controllers/GearLooksController) and the shop's GEAR cards (Controllers/ShopController).
--   GearModels.clone(name, golden) -> Model?   an anchored copy of the model (nil when the place has none); a Golden
--                                              one (3 gear cards, Config/Gear) with every colour blended toward
--                                              gold and a little shine (Config/GearLooks.gold), its ink hull dark
--   GearModels.OUTLINE                         the ink hull's part name

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GearLooks = require(Shared.GearLooks)
local L = require(Shared.Config.GearLooks)
local Palette = require(Shared.Art.Palette)

local GearModels = {}

GearModels.OUTLINE = "Outline"

local FALLBACK_GOLD = Color3.fromRGB(255, 212, 81)

function GearModels.clone(name: string, golden: boolean): Model?
	local folder = ReplicatedStorage:FindFirstChild(GearLooks.FOLDER)
	local template = if folder then folder:FindFirstChild(name) else nil
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	if golden then
		local look = L.gold
		local found = (Palette :: any)[look.color]
		local tint: Color3 = if typeof(found) == "Color3" then found else FALLBACK_GOLD
		for _, piece in model:GetChildren() do
			if piece:IsA("BasePart") and piece.Name ~= GearModels.OUTLINE then
				piece.Color = piece.Color:Lerp(tint, look.blend)
				piece.Reflectance = look.reflectance
			end
		end
	end
	return model
end

return GearModels
