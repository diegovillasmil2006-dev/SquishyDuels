--!strict
-- StationLabelController (client only). Owner 2026-11-08 ("i want banners like where people can see them everywhere",
-- a picture of white names floating over a lobby's places): a floating name over each Hub station in
-- Config.UI.StationLabels, turned to the camera, so a player finds every place from anywhere in the lobby. Diego's
-- flat plates stay as they are.
-- * One BillboardGui per station on its own Attachment in Workspace.Terrain (a fixed world point, so HubFX's moving
--   props never carry it), liftStuds over the station's top (its bounding box at start) plus half the label's height.
-- * Size = sizeStuds (studs: real size up close) + minPx (pixels: the floor far away). Not AlwaysOnTop (walls still
--   hide it), LightInfluence 0, seen within maxStuds.
-- * White display-font text (Palette.StationLabelText), TextScaled, with a dark outline (StationLabelStroke).
-- The Hub is Persistent (see LobbyFxController), so every station is here whole once the Hub is.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local Theme = require(script.Parent.Parent.UI.Theme)

-- Constants

local LOBBY_NAME = "SquishyDuelsLobby"
local HUB_NAME = "Hub"
local ANCHOR_PREFIX = "SD_StationLabel_"
local FONT_KIND: Theme.TextKind = "Title"

-- Module table

local StationLabelController = {}

-- Public

-- Builds the floating name of every station `hub` has (a missing one is skipped) on Attachments under `parent`
-- (Workspace.Terrain at runtime) and returns them in Config order.
function StationLabelController.build(hub: Instance, parent: Instance): { BillboardGui }
	local L = Config.UI.StationLabels
	local guis: { BillboardGui } = {}
	for _, station in L.stations do
		local model = hub:FindFirstChild(station.model)
		if not (model and model:IsA("Model")) then
			continue
		end
		local box, size = model:GetBoundingBox()
		local anchor = Instance.new("Attachment")
		anchor.Name = ANCHOR_PREFIX .. station.model
		anchor.Position = Vector3.new(box.X, box.Y + size.Y / 2 + L.liftStuds + L.sizeStuds.Y / 2, box.Z)

		local gui = Instance.new("BillboardGui")
		gui.Name = "Label"
		gui.Size = UDim2.new(L.sizeStuds.X, L.minPx.X, L.sizeStuds.Y, L.minPx.Y)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.MaxDistance = L.maxStuds

		local text = Instance.new("TextLabel")
		text.Name = "Name"
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.FontFace = Theme.font(FONT_KIND)
		text.TextScaled = true
		text.TextColor3 = Palette.StationLabelText
		text.Text = Strings.resolve(station.textKey) or ""
		local stroke = Instance.new("UIStroke")
		stroke.Color = Palette.StationLabelStroke
		stroke.Thickness = L.strokePx
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = text
		text.Parent = gui
		gui.Parent = anchor
		anchor.Parent = parent
		table.insert(guis, gui)
	end
	return guis
end

function StationLabelController.start()
	local hub = Workspace:WaitForChild(LOBBY_NAME):WaitForChild(HUB_NAME)
	StationLabelController.build(hub, Workspace.Terrain)
end

return StationLabelController
