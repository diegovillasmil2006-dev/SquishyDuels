--!strict
-- StaticIcon (client only). DESIGN §11.1 ("StaticIcon: a static ViewportFrame per id per screen, built once, never
-- animated, reused across filter changes by toggling Visible"), §11.6 (cards and the equipped card), §10.5 (framing and
-- lighting values, Config.Inspect), §8.3 (models come from Models/SquishyCache, model slots included).
--   local icon = StaticIcon.new({ name = "Preview", squishyId = "toast", sizePx = 88, parent = card })
--   icon:setSquishy("dragon")   -- rebuilds only when the id changes
--   icon:setOwned(false)        -- greyed (Lavender tint): "Not owned" always comes with a text and a lock elsewhere
-- The model is a SquishyCache "Viewport" clone at scale 1 (anchored, no welds), never animated and never in
-- Workspace. The camera looks at the model's bounding-box centre from the squishy's Catalog `inspect` yaw / pitch (the
-- face looks along the pivot's LookVector, §8.3), at fitDistance(r) with r = half the box diagonal. Lighting is the
-- Inspect key light and ambient, with the light direction fixed for this camera (the icon never turns).
-- With a Catalog `icon` (reading: an AssetTable image key) whose id is vetted, an ImageLabel replaces the viewport (none
-- exist in v1, §4.1).
-- The maths (viewDirection, fitDistance) is pure and unit-tested in Edit mode.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local SquishyCache = require(Client.Models.SquishyCache)

-- Types

export type Spec = {
	name: string,
	squishyId: string,
	sizePx: number?,
	layoutOrder: number?,
	parent: Instance?,
}

export type StaticIcon = {
	root: ViewportFrame,
	setSquishy: (self: StaticIcon, squishyId: string) -> (),
	setOwned: (self: StaticIcon, owned: boolean) -> (),
	squishyId: (self: StaticIcon) -> string,
	destroy: (self: StaticIcon) -> (),
}

-- Constants

local INSPECT = Config.Inspect
local FRAMING = INSPECT.Framing
local LIGHTING = INSPECT.Lighting
local DEFAULT_SIZE_PX = 88
local UNOWNED_TINT = Palette.Lavender
local OWNED_TINT = Color3.new(1, 1, 1)

-- Module table

local StaticIcon = {}

-- Private

local log = Log.new("StaticIcon")

-- Public: pure maths -------------------------------------------------------------------------------------------------

-- The unit direction from the model centre to the camera, in the model pivot's space: in front of the face (-Z),
-- turned by `yawDeg` about +Y and raised by `pitchDeg` (positive = from above).
function StaticIcon.viewDirection(yawDeg: number, pitchDeg: number): Vector3
	local yaw, pitch = math.rad(yawDeg), math.rad(pitchDeg)
	return Vector3.new(-math.sin(yaw) * math.cos(pitch), math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
end

-- Camera distance that fits a sphere of radius `r` in a square view of vertical FOV `vFovDeg` (§10.5 fitDist, with
-- the fit padding and the minimum clearance of Config.Inspect.Framing).
function StaticIcon.fitDistance(r: number, vFovDeg: number): number
	local radius = if r == r and r > 0 then r else 1
	local half = math.rad(vFovDeg) / 2
	local distance = radius / math.sin(half) * FRAMING.fitPadding
	return math.max(distance, radius + FRAMING.minClearance)
end

-- Public -------------------------------------------------------------------------------------------------------------

function StaticIcon.new(spec: Spec): StaticIcon
	local cleanup = Cleanup.new()
	local size = spec.sizePx or DEFAULT_SIZE_PX
	local root: ViewportFrame = Create("ViewportFrame", {
		Name = spec.name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = spec.layoutOrder or 0,
		Ambient = LIGHTING.ambient,
		LightColor = LIGHTING.lightColor,
		ImageColor3 = OWNED_TINT,
	})
	cleanup:add(root)
	local camera: Camera = Create("Camera", {
		Name = "Camera",
		FieldOfView = FRAMING.vFovDeg,
		Parent = root,
	})
	root.CurrentCamera = camera

	local currentId = ""
	local model: Model? = nil
	local image: ImageLabel? = nil

	local function clear()
		if model then
			model:Destroy()
			model = nil
		end
		if image then
			image:Destroy()
			image = nil
		end
	end
	cleanup:add(clear)

	local function build(squishyId: string)
		clear()
		currentId = squishyId
		local def = Catalog.get(squishyId)
		local imageId = if def and def.icon then AssetTable.image(def.icon) else nil
		if imageId then
			image = Create("ImageLabel", {
				Name = "Image",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = imageId,
				ImageColor3 = root.ImageColor3,
				Parent = root,
			})
			return
		end
		local ok, result = pcall(function(): Model
			return SquishyCache.clone(squishyId, "Viewport", 1)
		end)
		if not ok or typeof(result) ~= "Instance" then
			log:warn(`no preview for {squishyId}:`, result)
			return
		end
		local built = result :: Model
		local center, boxSize = built:GetBoundingBox()
		local yaw = if def then def.inspect.yaw else INSPECT.Orbit.defaultYawDeg
		local pitch = if def then def.inspect.pitch else INSPECT.Orbit.defaultPitchDeg
		local direction = built:GetPivot().Rotation:VectorToWorldSpace(StaticIcon.viewDirection(yaw, pitch))
		local distance = StaticIcon.fitDistance(boxSize.Magnitude / 2, FRAMING.vFovDeg)
		local eye = center.Position + direction * distance
		camera.CFrame = CFrame.lookAt(eye, center.Position)
		root.LightDirection = camera.CFrame:VectorToWorldSpace(LIGHTING.lightDirection.Unit)
		built.Parent = root
		model = built
	end

	build(spec.squishyId)
	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: StaticIcon
	self.root = root
	function self.setSquishy(_: StaticIcon, squishyId: string)
		if squishyId ~= currentId then
			build(squishyId)
		end
	end
	function self.setOwned(_: StaticIcon, owned: boolean)
		root.ImageColor3 = if owned then OWNED_TINT else UNOWNED_TINT
		if image then
			image.ImageColor3 = root.ImageColor3
		end
	end
	function self.squishyId(_: StaticIcon): string
		return currentId
	end
	function self.destroy(_: StaticIcon)
		cleanup:clean()
	end
	return self
end

return StaticIcon
