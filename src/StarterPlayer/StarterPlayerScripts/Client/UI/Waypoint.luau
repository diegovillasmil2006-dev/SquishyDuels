--!strict
-- Waypoint (client only). DESIGN §11.8 (waypoints), §5.4 / §11.6 (the queue's "Practice" button shows a waypoint to
-- the range; the player stays queued, no teleport). Shared by the queue now and onboarding later.
--   local handle = Waypoint.show(WorldLayout.waypoint("practice"))   ...   handle:destroy()
-- A client Beam (Lemon, the waypoint colour of §7.2) from an Attachment on the local HumanoidRootPart to an Attachment
-- in Workspace.Terrain at the target floor point. It hides within Config.Onboarding.waypointHideStuds (8) of the
-- target and follows respawns. Everything it creates is local to this client and destroyed by destroy().

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)

-- Types

export type Handle = {
	destroy: (self: Handle) -> (),
	isVisible: (self: Handle) -> boolean,
}

-- Constants

local HIDE_WITHIN = Config.Onboarding.waypointHideStuds
local TARGET_LIFT = Vector3.new(0, 1, 0) -- the beam ends just above the floor point
local BEAM_WIDTH = 0.6
local BEAM_TRANSPARENCY = 0.25
local ROOT_PART = "HumanoidRootPart"
local ROOT_WAIT_SECONDS = 5 -- reading: how long a respawned character may take to get its root part

-- Module table

local Waypoint = {}

-- Public

-- True when a character root at `rootPosition` is close enough to `target` that the beam hides (horizontal distance).
function Waypoint.shouldHide(rootPosition: Vector3, target: Vector3): boolean
	local flat = Vector3.new(rootPosition.X - target.X, 0, rootPosition.Z - target.Z)
	return flat.Magnitude <= HIDE_WITHIN
end

function Waypoint.show(target: Vector3): Handle
	local cleanup = Cleanup.new()
	local targetAttachment: Attachment = Instance.new("Attachment")
	targetAttachment.Name = "SD_WaypointTarget"
	-- Workspace.Terrain sits at the world origin, so an attachment's Position there is its world position.
	targetAttachment.Position = target + TARGET_LIFT
	cleanup:add(targetAttachment)

	local beam: Beam = Instance.new("Beam")
	beam.Name = "SD_WaypointBeam"
	beam.Color = ColorSequence.new(Palette.Lemon)
	beam.Transparency = NumberSequence.new(BEAM_TRANSPARENCY)
	beam.Width0 = BEAM_WIDTH
	beam.Width1 = BEAM_WIDTH
	beam.FaceCamera = true
	beam.LightEmission = 0
	beam.Attachment1 = targetAttachment
	beam.Enabled = false
	beam.Parent = targetAttachment
	targetAttachment.Parent = Workspace.Terrain

	local rootAttachment: Attachment? = nil
	local visible = false
	local alive = true

	local function bindCharacter(character: Model?)
		if rootAttachment then
			rootAttachment:Destroy()
			rootAttachment = nil
		end
		local root = if character then character:FindFirstChild(ROOT_PART) else nil
		if root and root:IsA("BasePart") then
			local attachment = Instance.new("Attachment")
			attachment.Name = "SD_WaypointFrom"
			attachment.Parent = root
			rootAttachment = attachment
			beam.Attachment0 = attachment
		else
			beam.Attachment0 = nil
		end
	end
	cleanup:add(function()
		alive = false
		bindCharacter(nil)
	end)

	local player = Players.LocalPlayer
	if player then
		bindCharacter(player.Character)
		cleanup:add(player.CharacterAdded:Connect(function(character: Model)
			character:WaitForChild(ROOT_PART, ROOT_WAIT_SECONDS)
			if alive then -- destroy() may have run while waiting
				bindCharacter(character)
			end
		end))
	end

	cleanup:add(Scheduler.add(function(): boolean
		local attachment = rootAttachment
		if attachment == nil or attachment.Parent == nil then
			visible = false
		else
			visible = not Waypoint.shouldHide(attachment.WorldPosition, target)
		end
		if beam.Enabled ~= visible then
			beam.Enabled = visible
		end
		return true
	end, "render"))

	local handle = {} :: Handle
	function handle.destroy(_: Handle)
		cleanup:clean()
	end
	function handle.isVisible(_: Handle): boolean
		return visible
	end
	return handle
end

return Waypoint
