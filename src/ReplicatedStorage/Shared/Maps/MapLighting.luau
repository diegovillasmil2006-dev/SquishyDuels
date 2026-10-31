--!strict
-- MapLighting (client): the look of Diego's sky maps (NEW MAPS FINALS zip, 2026-10-30) while the local player is on
-- one. Same API as his old DuelMapScripts.MapLighting: Apply(code) when a map's match / duel view appears, Reset() when
-- it ends (back to what Lighting had before the first Apply).
-- His Roblox preset (roblox/SquishyTDMBuilder.lua CONFIG.ApplyLighting: "bright ambient, pink haze, slight saturation
-- boost"), with his demos' sky: buildSky()'s gradient (top #2f8fe6, mid #8fcdf7, bottom #dff1ff) as a skybox
-- (docs/new-maps/textures Sky*.png) and no sun or moon. His Terrain Clouds are left out: the SUPERPROMPT wants the
-- blocky clouds only ("no cloud bed under the platforms"). The same look for every map, so `code` is only checked.

local Lighting = game:GetService("Lighting")

local MapData = require(script.Parent.MapData)

local MapLighting = {}

local TAG = "SquishyMapLighting"
local SKY = {
	up = "rbxassetid://126503081362555",
	side = "rbxassetid://101839995386908",
	down = "rbxassetid://89166293545610",
}
local PROPS: { [string]: any } = {
	ClockTime = 14.5,
	Brightness = 2.2,
	Ambient = Color3.fromRGB(170, 160, 200),
	OutdoorAmbient = Color3.fromRGB(190, 180, 225),
	EnvironmentDiffuseScale = 0.6,
	EnvironmentSpecularScale = 0.2,
	GlobalShadows = true,
	ShadowSoftness = 0.35,
}

type Saved = { props: { [string]: any }, hidden: { Instance } }
local saved: Saved? = nil

local function effect(className: string): Instance
	for _, c in Lighting:GetChildren() do
		if c:IsA(className) and c:GetAttribute(TAG) then
			return c
		end
	end
	local e = Instance.new(className)
	e:SetAttribute(TAG, true)
	e.Parent = Lighting
	return e
end

local function snapshot(): Saved
	local s: Saved = { props = {}, hidden = {} }
	for k in PROPS do
		s.props[k] = (Lighting :: any)[k]
	end
	for _, c in Lighting:GetChildren() do
		if (c:IsA("Atmosphere") or c:IsA("Sky") or c:IsA("PostEffect")) and not c:GetAttribute(TAG) then
			table.insert(s.hidden, c)
		end
	end
	return s
end

-- Applies the sky-map look; `code` is a MapData id (the map's MapCode). Returns false for an unknown code.
function MapLighting.Apply(code: string): boolean
	if MapData.maps[code] == nil then
		return false
	end
	if saved == nil then
		saved = snapshot()
	end
	local s = saved :: Saved
	for _, c in s.hidden do -- park the place's own sky / atmosphere / post effects
		if c.Parent == Lighting then
			c.Parent = nil
		end
	end
	for k, v in PROPS do
		(Lighting :: any)[k] = v
	end
	local sky = effect("Sky") :: Sky
	sky.SkyboxUp = SKY.up
	sky.SkyboxDn = SKY.down
	sky.SkyboxBk = SKY.side
	sky.SkyboxFt = SKY.side
	sky.SkyboxLf = SKY.side
	sky.SkyboxRt = SKY.side
	sky.CelestialBodiesShown = false
	sky.StarCount = 0
	local atm = effect("Atmosphere") :: Atmosphere
	atm.Density = 0.32
	atm.Offset = 0.1
	atm.Color = Color3.fromHex("ffe0f0")
	atm.Decay = Color3.fromHex("6fc2ff")
	atm.Glare = 0
	atm.Haze = 1.2
	local cc = effect("ColorCorrectionEffect") :: ColorCorrectionEffect
	cc.Saturation = 0.18
	cc.Contrast = 0.06
	cc.Brightness = 0.03
	return true
end

function MapLighting.Reset()
	for _, c in Lighting:GetChildren() do
		if c:GetAttribute(TAG) then
			c:Destroy()
		end
	end
	local s = saved
	if s then
		for k, v in s.props do
			(Lighting :: any)[k] = v
		end
		for _, c in s.hidden do
			c.Parent = Lighting
		end
		saved = nil
	end
end

return MapLighting
