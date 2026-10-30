--!nonstrict
-- PortalController (client only). Diego's FULL FINAL lobby (owner 2026-10-30, "Yes, start step 3"): his portal trip
-- cinematic (zip src/client/PortalCinematic.client.luau), as delivered, on the game's PortalTrip remote (PortalService):
-- "enter" -> the player is yanked, lifted, spun and pulled into the vortex while the camera whips aside, pulls far
-- back, then rushes in (FOV kick, shake, blur, white flash); "arrive" -> the player pops out of the other portal while
-- the camera swoops down behind them, with the letterbox bars and the title card. The only changes are the game's own
-- hand-overs, so nothing fights the shot (SUPERPROMPT 6.4): ControlsController.block (not PlayerModule:GetControls),
-- CameraController.save / restore (the game's camera comes back as it was, not Custom at FOV 70), and the held
-- squishy (welded to the hand, outside the character) hides with the body (HeldSquishyController.setHidden).

-- Services

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local HubFX = require(Shared.SquishyLobby.HubFX)
local Cfg = require(Shared.SquishyLobby.Portal)

local Controllers = script.Parent
local CameraController = require(Controllers.CameraController)
local ControlsController = require(Controllers.ControlsController)
local HeldSquishyController = require(Controllers.HeldSquishyController)
local NetController = require(Controllers.NetController)
local SoundController = require(Controllers.SoundController)

-- Constants

local REMOTE = "PortalTrip"
local LOBBY_NAME = "SquishyDuelsLobby"
local BLOCK_REASON = "portal"
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

-- Module table

local PortalController = {}

-- Private

local player = Players.LocalPlayer
local gui, barTop, barBot, flash, title, titleStroke, sub, subStroke, blur, cc
local snapshot: any = nil -- CameraController.save() while a trip runs
local releaseControls: (() -> ())? = nil
local heldHidden = false

---------------------------------------------------------------- UI (zip :17-44)
local function buildUi()
	gui = Instance.new("ScreenGui")
	gui.Name = "PortalCinematic"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false; gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")
	local function frame(props)
		local f = Instance.new("Frame"); f.BorderSizePixel = 0
		for k, v in props do f[k] = v end
		f.Parent = gui
		return f
	end
	barTop = frame({ BackgroundColor3 = Color3.fromHex("0d0820"), Size = UDim2.fromScale(1, 0.11), Position = UDim2.fromScale(0, -0.11), ZIndex = 5 })
	barBot = frame({ BackgroundColor3 = Color3.fromHex("0d0820"), Size = UDim2.fromScale(1, 0.11), Position = UDim2.fromScale(0, 1), ZIndex = 5 })
	flash = frame({ BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 6 })
	local function label(text, size, pos, color, stroke)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1; l.FontFace = FONT; l.TextScaled = true; l.Text = text
		l.Size = size; l.AnchorPoint = Vector2.new(0.5, 0.5); l.Position = pos; l.TextColor3 = color; l.TextTransparency = 1; l.ZIndex = 7
		local s = Instance.new("UIStroke"); s.Thickness = stroke; s.Color = Color3.fromHex("2a1748"); s.Transparency = 1; s.Parent = l
		l.Parent = gui
		return l, s
	end
	title, titleStroke = label("", UDim2.fromScale(0.8, 0.13), UDim2.fromScale(0.5, 0.47), Color3.fromHex("ffe14d"), 6)
	sub, subStroke = label("", UDim2.fromScale(0.4, 0.045), UDim2.fromScale(0.5, 0.58), Color3.new(1, 1, 1), 3)

	blur = Lighting:FindFirstChild("PortalBlur") or Instance.new("BlurEffect")
	blur.Name = "PortalBlur"; blur.Size = 0; blur.Parent = Lighting
	cc = Lighting:FindFirstChild("PortalColor") or Instance.new("ColorCorrectionEffect")
	cc.Name = "PortalColor"; cc.Parent = Lighting
end

---------------------------------------------------------------- helpers (zip :46-77)
local function tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.InOut), props)
	tw:Play()
	return tw
end
local function run(dur, fn)
	local t0 = os.clock()
	while true do
		local u = math.min(1, (os.clock() - t0) / dur)
		fn(u)
		if u >= 1 then break end
		RunService.RenderStepped:Wait()
	end
end
local function io(u) return u < 0.5 and 4 * u * u * u or 1 - (-2 * u + 2) ^ 3 / 2 end
-- Game hand-over (replaces the zip's PlayerModule controls and the end's Custom camera at FOV 70).
local function controls(on)
	if on then
		if releaseControls then releaseControls(); releaseControls = nil end
		if snapshot then CameraController.restore(snapshot); snapshot = nil end
	else
		if not snapshot then snapshot = CameraController.save() end
		if not releaseControls then releaseControls = ControlsController.block(BLOCK_REASON) end
	end
end
local function bars(on)
	tween(barTop, 0.6, { Position = UDim2.fromScale(0, on and 0 or -0.11) })
	tween(barBot, 0.6, { Position = UDim2.fromScale(0, on and 0.89 or 1) })
end
local function showTitle(on, link)
	if link then title.Text = link.title; sub.Text = link.subtitle end
	local a = on and 0 or 1
	tween(title, 0.5, { TextTransparency = a }); tween(titleStroke, 0.5, { Transparency = a })
	tween(sub, 0.5, { TextTransparency = a }); tween(subStroke, 0.5, { Transparency = a })
	title.Position = UDim2.fromScale(0.5, on and 0.5 or 0.47)
	if on then tween(title, 0.7, { Position = UDim2.fromScale(0.5, 0.47) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out) end
end

---------------------------------------------------------------- sound (zip :79-90)
-- His Portal.Sfx keys play the game's sound keys (ids only in AssetTable, 2D on SFX, the settings' volume). The files
-- are his preview's own sounds at its level, so his per-call trims for stand-in clips (volume × SfxVolume) are not
-- applied; his ±4% pitch is. 2D one-shots, only during a portal trip: nothing plays while idle.
local SFX_KEYS = {
	Start = "portal.start", Windup = "portal.windup", Suck = "portal.suck", Poof = "portal.poof",
	Spit = "portal.spit", Land = "portal.land", Chime = "portal.chime",
}
local function sfx(key, _volume, speed)
	local soundKey = SFX_KEYS[key]
	if soundKey then SoundController.play(soundKey, { pitch = speed, variance = 0.04 }) end
end

---------------------------------------------------------------- sequences (zip :92-268)
local cam = Workspace.CurrentCamera
local function lobbyModel() return Workspace:FindFirstChild(LOBBY_NAME) end

-- the local character: fade with LocalTransparencyModifier, move with an anchored root during the shot
local function charBits()
	local c = player.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	local list = {}
	if c then for _, d in c:GetDescendants() do if d:IsA("BasePart") or d:IsA("Decal") then table.insert(list, d) end end end
	return root, list
end
local function fade(list, a)
	for _, d in list do d.LocalTransparencyModifier = a end
	-- Game hand-over: the held squishy is welded to the hand but lives outside the character.
	local hide = a >= 0.5
	if hide ~= heldHidden then
		heldHidden = hide
		HeldSquishyController.setHidden(player, BLOCK_REASON, hide)
	end
end

local function enter(name, model)
	local link = Cfg.Links[name]
	cam = Workspace.CurrentCamera
	local A = model or HubFX.resolve(lobbyModel(), link.from)
	local c = A.Markers.PortalCenter.CFrame
	local center, front = c.Position, c.LookVector
	local side = front:Cross(Vector3.yAxis)
	local root, bits = charBits()
	controls(false)
	cam.CameraType = Enum.CameraType.Scriptable
	bars(true)
	if Cfg.USE_SEPARATE_PLACE or (link.placeId() ~= 0 and link.spawn) then TeleportService:SetTeleportGui(gui) end
	if root then root.Anchored = true end
	HubFX.portalWave(A.Name)
	sfx("Start", 0.6); sfx("Windup", 0.55)
	-- 1. yanked toward the portal while the camera whips to the side (0.4 s)
	local c0 = cam.CFrame
	local swing = center + front * 12 - side * 7.5 + Vector3.new(0, 0.5, 0)
	local from = root and root.CFrame or CFrame.new(center + front * 8)
	local grab = Vector3.new(center.X, from.Position.Y, center.Z) + front * 4.4
	run(0.4, function(u)
		local e = io(u)
		if root then root.CFrame = CFrame.new(from.Position:Lerp(grab, u * u)) * from.Rotation end
		cam.CFrame = CFrame.lookAt(c0.Position:Lerp(swing, e), (root and root.Position or center):Lerp(center, e * 0.4))
		HubFX.setPortalBoost(A.Name, 3 + e * 4)
	end)
	-- 2. sucked in (0.85 s): off the ground, pitched head-first, spiralled down the portal axis, spun on its
	--    long axis and faded into the core; the camera punches in with FOV kick, shake, blur and a white flash
	sfx("Suck", 0.7)
	local body0 = root and root.Position or grab
	local rel = body0 - center
	local depth0 = rel:Dot(front)
	local lat0 = rel - front * depth0
	local inward = -front
	local camFrom = cam.CFrame.Position
	local camFar = center + front * 38 - side * 10 + Vector3.new(0, 7, 0)
	local camIn = center + front * 1.4
	local fov0 = cam.FieldOfView
	tween(blur, 1.05, { Size = 22 }, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
	tween(cc, 1.05, { Brightness = 0.25, Saturation = 0.5, TintColor = link.color:Lerp(Color3.new(1, 1, 1), 0.5) }, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
	run(1.05, function(u)
		local e, k = u ^ 3, io(u)
		local grabU = math.min(1, u / 0.22)
		local lat = CFrame.fromAxisAngle(front, u * u * math.pi * 3.4):VectorToWorldSpace(lat0) * (1 - k)
		local ko = 1 - (1 - u) ^ 3
		local p = center + front * (depth0 * (1 - ko * 0.55 - e * 0.45)) + lat + Vector3.new(0, math.sin(math.pi * grabU) * 1.2 * (1 - u), 0)
		if root then
			local pitch = (1 - (1 - grabU) ^ 3) * math.pi / 2
			root.CFrame = CFrame.lookAt(p, p + inward) * CFrame.Angles(-pitch, 0, 0) * CFrame.Angles(0, e * math.pi * 7, 0)
		end
		fade(bits, math.clamp((u - 0.45) / 0.45, 0, 1))
		-- 0-0.42: camera pulls far back while the lens tightens; 0.42-1: it gets sucked in after the player
		local back = u < 0.42
		local uu = back and 1 - (1 - u / 0.42) ^ 3 or ((u - 0.42) / 0.58) ^ 3
		local cp = back and camFrom:Lerp(camFar, uu) or camFar:Lerp(camIn, uu)
		local sh = back and 0 or uu * 0.5
		cam.FieldOfView = back and fov0 + (45 - fov0) * uu or 45 + 60 * uu
		cam.CFrame = CFrame.lookAt(cp + Vector3.new((math.random() - 0.5) * sh, (math.random() - 0.5) * sh, 0), p:Lerp(center, math.min(1, u * 1.2)))
		HubFX.setPortalBoost(A.Name, 6 + 12 * e)
	end)
	tween(flash, 0.12, { BackgroundTransparency = 0 })
	sfx("Poof", 0.7)
	HubFX.setPortalBoost(A.Name, 1)
end

-- Highway arrival: no portal on the far side. Fade in from white behind the player, title card, hand the camera back.
local function arriveAtSpawn(link)
	local root, bits = charBits()
	fade(bits, 0)
	if root then root.Anchored = false end
	local look = root and root.CFrame.LookVector or Vector3.zAxis
	local at = root and root.Position or Vector3.zero
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 80
	local A, B = at - look * 22 + Vector3.new(0, 16, 0), at - look * 12 + Vector3.new(0, 5, 0)
	tween(flash, 0.8, { BackgroundTransparency = 1 })
	tween(blur, 0.8, { Size = 0 }); tween(cc, 0.8, { Brightness = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) })
	sfx("Spit", 0.7)
	task.delay(0.25, function() showTitle(true, link); sfx("Chime", 0.6) end)
	run(1.4, function(u)
		local e = io(u)
		cam.CFrame = CFrame.lookAt(A:Lerp(B, e), at + look * 20 + Vector3.new(0, 2, 0))
		cam.FieldOfView = 80 - 10 * e
	end)
	task.delay(0.9, function() showTitle(false) end)
	bars(false)
	controls(true)
end

-- Highway -> lobby: quick flash out (the return trigger has no portal cinematic of its own).
local function leave()
	controls(false)
	bars(true)
	sfx("Start", 0.6)
	tween(flash, 0.35, { BackgroundTransparency = 0 })
	tween(blur, 0.35, { Size = 20 })
end

local function arrive(name)
	local link = Cfg.Links[name]
	if link.spawn then return arriveAtSpawn(link) end
	local B = HubFX.resolve(lobbyModel(), link.to)
	local s = B.Markers.ArrivalSpawn.CFrame
	local S, look = s.Position, s.LookVector
	local right = look:Cross(Vector3.yAxis)
	local toArena = name == "Portal"
	local E = S - look * 30 + right * 55 + Vector3.new(0, 62, 0)
	local ET = S + look * 30
	local F = S - look * 6 + right * 4 + Vector3.new(0, toArena and 9 or 11, 0)
	local FT = S + look * (toArena and 30 or 18) + Vector3.new(0, toArena and 2 or 4, 0)
	local ctrl = S + look * 6 + Vector3.new(0, 48, 0)
	local root, bits = charBits()
	local landing = s * CFrame.new(0, 1.5, 0)
	local center = B.Markers.PortalCenter.Position
	if root then root.Anchored = true; root.CFrame = CFrame.new(center) * landing.Rotation end
	fade(bits, 1)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 80
	cam.CFrame = CFrame.lookAt(E, ET)
	HubFX.setPortalBoost(B.Name, 10)
	HubFX.portalWave(B.Name)
	task.wait(0.08)
	sfx("Spit", 0.7)
	tween(flash, 0.5, { BackgroundTransparency = 1 })
	tween(blur, 0.8, { Size = 0 }); tween(cc, 0.8, { Brightness = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) })
	task.delay(0.25, function() showTitle(true, link); sfx("Chime", 0.6) end)
	local landed = false
	run(1.8, function(u)
		local e = io(u)
		local a, b, c = (1 - e) * (1 - e), 2 * (1 - e) * e, e * e
		cam.CFrame = CFrame.lookAt(E * a + ctrl * b + F * c, ET:Lerp(FT, 1 - (1 - u) ^ 3))
		cam.FieldOfView = 80 - 10 * e
		HubFX.setPortalBoost(B.Name, 1 + 9 * (1 - u))
		-- the player pops out of the portal and lands on the spawn (first third of the shot)
		local k = math.min(1, u / 0.26)
		if k >= 1 and not landed then landed = true; sfx("Land", 0.8) end
		if root then
			local ko = 1 - (1 - k) ^ 3
			local p = center:Lerp(landing.Position, ko) + Vector3.new(0, math.sin(math.pi * k) * 3, 0)
			root.CFrame = CFrame.new(p) * landing.Rotation * CFrame.Angles(0, (1 - ko) * 10, 0)
		end
		fade(bits, 1 - k)
	end)
	if root then root.CFrame = landing; root.Anchored = false end
	fade(bits, 0)
	task.delay(0.7, function() showTitle(false) end)
	bars(false)
	controls(true)
end

local function cancel()
	local root, bits = charBits()
	if root then root.Anchored = false end
	fade(bits, 0)
	tween(flash, 0.4, { BackgroundTransparency = 1 })
	tween(blur, 0.4, { Size = 0 }); tween(cc, 0.4, { Brightness = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) })
	bars(false)
	controls(true)
end

-- The highway's LobbyPortal (a copy of Hub.HighwayPortal tagged HubFX.CLONE_TAG): the remote names no instance.
local function returnPortal()
	return CollectionService:GetTagged(HubFX.CLONE_TAG)[1]
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function PortalController.init()
	NetController.on(REMOTE, function(kind, name)
		if type(name) ~= "string" or Cfg.Links[name] == nil or gui == nil then return end
		-- each shot in its own thread, as the zip's OnClientEvent handler ran (the shots wait on RenderStepped)
		task.spawn(function()
			if kind == "enter" then enter(name, if Cfg.Links[name].from then nil else returnPortal())
			elseif kind == "arrive" then arrive(name)
			elseif kind == "leave" then leave()
			elseif kind == "cancel" then cancel() end
		end)
	end)
end

-- Game fix (2026-10-30): after a reveal the game's camera sits its zoom (12.5) behind the player, behind the arrival
-- portal's see-through Membrane, which then tints the whole view (Diego's preview camera stops 6 studs back). On this
-- client a portal's Membrane hides while the camera is behind it and near; from the front nothing changes.
local MEMBRANE_NEAR = 20
local function watchMembranes()
	local list = {}
	local function add(m)
		local membrane = m:FindFirstChild("Membrane")
		local center = m:FindFirstChild("Markers") and m.Markers:FindFirstChild("PortalCenter")
		if membrane and center then table.insert(list, { part = membrane, cf = center.CFrame }) end
	end
	-- the portal models are Persistent: each arrives whole, a moment after the client starts
	local lobby = Workspace:WaitForChild(LOBBY_NAME)
	for _, path in { { "Hub", "Portal" }, { "Hub", "HighwayPortal" }, { "PracticeArena", "ReturnPortal" } } do
		lobby:WaitForChild(path[1])
		local m = HubFX.resolve(lobby, path)
		if m then add(m) end
	end
	for _, m in CollectionService:GetTagged(HubFX.CLONE_TAG) do add(m) end
	CollectionService:GetInstanceAddedSignal(HubFX.CLONE_TAG):Connect(add)
	RunService.RenderStepped:Connect(function()
		local cp = Workspace.CurrentCamera.CFrame.Position
		for _, q in list do
			local rel = cp - q.cf.Position
			local behind = rel:Dot(q.cf.LookVector) < 0 and rel.Magnitude < MEMBRANE_NEAR
			local want = if behind then 1 else 0
			if q.part.LocalTransparencyModifier ~= want then q.part.LocalTransparencyModifier = want end
		end
	end)
end

function PortalController.start()
	buildUi()
	watchMembranes()
end

return PortalController
