--!strict
-- Prims: the small set of primitive constructors every edit-time world builder uses (DESIGN §7.3, §7.7, §1.7).
-- Server only, Edit mode only (ServerStorage.SDTools); runtime code never requires it. No requires.
-- Every constructor makes an UNPARENTED instance unless a parent is given, sets every flag explicitly (Anchored,
-- CanCollide, CanQuery, CanTouch, CastShadow, Material) and never yields, so a whole world is built in memory and
-- handed to Main's swap in one piece.
-- Flag presets (§7.7 props rules):
--   solid   walkable or blocking geometry: CanCollide true, CanQuery true, CanTouch false
--   decor   anything that only looks: CanCollide false, CanQuery false, CanTouch false (rule 2: out of hit queries
--           and camera occlusion)
--   volume  an invisible box the server or a binder reads (zones, keep-clear, audio): Transparency 1, nothing
--           collides, is queried or touched, CastShadow false
--   barrier an invisible wall: Transparency 1, CanCollide true, CanQuery false, CanTouch false
-- CanQuery = false is always set after CanCollide = false (the engine refuses CanQuery false on a colliding part
-- only through the property window; set in this order it always sticks).
-- Cylinders: Roblox cylinders run along the part's X axis. `Prims.upright(position)` turns X to world Y, so a disc of
-- diameter D and height H is a Cylinder part of Size (H, D, D) at `upright(centre)`.
-- ProximityPrompts are always created DISABLED (§7.6: WorldBinder enables a stand's prompt only when its UI exists).

local PhysicsService = game:GetService("PhysicsService")

-- Types

export type Flags = "solid" | "decor" | "volume" | "barrier"

export type PartOptions = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?, -- default SmoothPlastic (§7.3)
	transparency: number?,
	shape: Enum.PartType?, -- default Block
	flags: Flags?, -- default "solid"
	shadow: boolean?, -- default true (false for volumes and barriers)
	parent: Instance?,
}

export type PromptOptions = {
	actionText: string,
	textKey: string, -- the Strings key of actionText, stored as SD_TextKey so the binder can re-apply it
	maxDistance: number?, -- default 10 (§7.6, V)
	lineOfSight: boolean?, -- default true (§7.6, V)
	name: string?, -- default "Prompt"
}

-- Constants

local DEFAULT_MATERIAL = Enum.Material.SmoothPlastic
local COSMETIC_GROUP = "SD_Cosmetic"
local MESH_NAME = "Mesh"
local PROMPT_NAME = "Prompt"
local PROMPT_ATTACHMENT_NAME = "PromptAttachment"
local ATTR_TEXT_KEY = "SD_TextKey"
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- part X axis -> world Y

-- Module table

local Prims = {}
Prims.MESH_NAME = MESH_NAME
Prims.PROMPT_NAME = PROMPT_NAME
Prims.PROMPT_ATTACHMENT_NAME = PROMPT_ATTACHMENT_NAME
Prims.COSMETIC_GROUP = COSMETIC_GROUP

-- Private

local function applyFlags(part: BasePart, flags: Flags)
	part.Anchored = true
	part.CanTouch = false
	if flags == "solid" then
		part.CanCollide = true
		part.CanQuery = true
	elseif flags == "barrier" then
		part.CanCollide = true
		part.CanQuery = false
		part.Transparency = 1
		part.CastShadow = false
	else -- decor, volume
		part.CanCollide = false
		part.CanQuery = false
		if flags == "volume" then
			part.Transparency = 1
			part.CastShadow = false
		end
	end
end

-- Public

-- A CFrame at `position` whose X axis points up: the frame for an upright (vertical-axis) cylinder.
function Prims.upright(position: Vector3): CFrame
	return CFrame.new(position) * UPRIGHT
end

-- A CFrame at `position` whose front (-Z, LookVector) looks along the horizontal direction `facing`.
-- Signs built at this frame are read by someone standing on the `facing` side.
function Prims.facing(position: Vector3, facing: Vector3): CFrame
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 1e-6 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

-- An anchored Part with every flag set from `opts.flags` (default "solid").
function Prims.part(opts: PartOptions): Part
	local part = Instance.new("Part")
	part.Name = opts.name
	part.Shape = opts.shape or Enum.PartType.Block
	part.Size = opts.size
	part.CFrame = opts.cframe
	part.Color = opts.color or Color3.new(1, 1, 1)
	part.Material = opts.material or DEFAULT_MATERIAL
	part.Reflectance = 0
	part.CastShadow = if opts.shadow == nil then true else opts.shadow
	part.Transparency = opts.transparency or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	applyFlags(part, opts.flags or "solid")
	if opts.parent then
		part.Parent = opts.parent
	end
	return part
end

-- An upright cylinder (diameter along X and Z, height along Y) centred at `centre`.
function Prims.disc(
	name: string,
	diameter: number,
	height: number,
	centre: Vector3,
	color: Color3,
	flags: Flags?,
	parent: Instance?
): Part
	return Prims.part({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cframe = Prims.upright(centre),
		color = color,
		flags = flags,
		parent = parent,
	})
end

-- A WedgePart (its slope rises from the front (-Z) bottom edge to the back top edge) with the same flags as part().
-- Phase 3: the design lobby's arrow tips (lobby.js:162).
function Prims.wedge(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	flags: Flags?,
	parent: Instance?
): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Color = color
	wedge.Material = DEFAULT_MATERIAL
	wedge.Reflectance = 0
	wedge.CastShadow = true
	wedge.Transparency = 0
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	applyFlags(wedge, flags or "solid")
	if parent then
		wedge.Parent = parent
	end
	return wedge
end

-- A Part carrying a SpecialMesh child named "Mesh" (Sphere for ellipsoids, Brick, Wedge, ...), non-colliding
-- decor by default. Part.Size carries the full size; mesh Scale stays (1, 1, 1) and Offset 0, so a client animator can
-- read the rest values from the mesh.
function Prims.meshPart(
	name: string,
	meshType: Enum.MeshType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	flags: Flags?,
	parent: Instance?
): Part
	local part = Prims.part({
		name = name,
		size = size,
		cframe = cframe,
		color = color,
		flags = flags or "decor",
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.Name = MESH_NAME
	mesh.MeshType = meshType
	mesh.Scale = Vector3.one
	mesh.Offset = Vector3.zero
	mesh.Parent = part
	if parent then
		part.Parent = parent
	end
	return part
end

-- A rounded box: a clone of `template` (ReplicatedStorage.SD_ShapeLibrary.RoundedBox, a CSG solid) with Size and
-- Color set, or, when `template` is nil or cannot be cloned, a Part with a Brick SpecialMesh (§8.1 #2 fallback).
-- Always decor (non-colliding, non-query, non-touch). Returns the part and whether the fallback was used.
function Prims.roundedBox(
	template: BasePart?,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance?
): (BasePart, boolean)
	local clone: BasePart? = nil
	if template then
		local ok, result = pcall(function(): Instance?
			return template:Clone()
		end)
		if ok and typeof(result) == "Instance" and result:IsA("BasePart") then
			clone = result
		end
	end
	if clone == nil then
		return Prims.meshPart(name, Enum.MeshType.Brick, size, cframe, color, "decor", parent), true
	end
	local part = clone :: BasePart
	part:ClearAllChildren()
	for _, tag in part:GetTags() do
		part:RemoveTag(tag)
	end
	for attribute in part:GetAttributes() do
		part:SetAttribute(attribute, nil)
	end
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = DEFAULT_MATERIAL
	part.Transparency = 0
	part.CastShadow = true
	applyFlags(part, "decor")
	if parent then
		part.Parent = parent
	end
	return part, false
end

-- Puts a non-colliding part in the SD_Cosmetic collision group when that group is registered in this place (it is
-- registered at runtime by WorldService; an unregistered name is never written, as in Art/SquishyBuilder).
function Prims.cosmetic(part: BasePart)
	local ok, registered = pcall(function(): boolean
		return PhysicsService:IsCollisionGroupRegistered(COSMETIC_GROUP)
	end)
	if ok and registered then
		part.CollisionGroup = COSMETIC_GROUP
	end
end

-- A Model. `atomic` makes it a streaming unit (§7.7: a station and its prompt/SurfaceGui stream together); else
-- ModelStreamingMode Default. `pivot` sets WorldPivot (default: the origin until parts are added, then Roblox's
-- bounding-box centre, so builders pass it explicitly where runtime code reads the pivot).
function Prims.model(name: string, parent: Instance?, atomic: boolean?, pivot: CFrame?): Model
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = if atomic then Enum.ModelStreamingMode.Atomic else Enum.ModelStreamingMode.Default
	if pivot then
		model.WorldPivot = pivot
	end
	if parent then
		model.Parent = parent
	end
	return model
end

function Prims.folder(name: string, parent: Instance?): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	if parent then
		folder.Parent = parent
	end
	return folder
end

-- Adds `tag` and sets `attributes` (in sorted key order, so builds are deterministic).
function Prims.tag(instance: Instance, tag: string, attributes: { [string]: any }?)
	instance:AddTag(tag)
	if attributes then
		local keys = {}
		for key in attributes do
			table.insert(keys, key)
		end
		table.sort(keys)
		for _, key in keys do
			instance:SetAttribute(key, attributes[key])
		end
	end
end

-- A DISABLED ProximityPrompt on an Attachment of `host` at the world position `position` (the prompt point from
-- DESIGN §7.6, usually just in front of the station body so the line-of-sight ray never starts inside it).
-- KeyboardKeyCode E / GamepadKeyCode ButtonX are the engine defaults (§7.6, V). HoldDuration 0.
function Prims.prompt(host: BasePart, position: Vector3, opts: PromptOptions): ProximityPrompt
	local attachment = Instance.new("Attachment")
	attachment.Name = PROMPT_ATTACHMENT_NAME
	attachment.CFrame = CFrame.new(host.CFrame:PointToObjectSpace(position))
	attachment.Parent = host

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = opts.name or PROMPT_NAME
	prompt.ActionText = opts.actionText
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = opts.maxDistance or 10
	prompt.RequiresLineOfSight = if opts.lineOfSight == nil then true else opts.lineOfSight
	prompt.Enabled = false
	prompt:SetAttribute(ATTR_TEXT_KEY, opts.textKey)
	prompt.Parent = attachment
	return prompt
end

-- How many BaseParts `root` holds (itself included).
function Prims.countParts(root: Instance): number
	local count = if root:IsA("BasePart") then 1 else 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

-- The lowest world Y over every BasePart under `root` (its axis-aligned box; exact for unrotated blocks and
-- ellipsoids). math.huge when there is none. Used to stand built models on a surface.
function Prims.lowestY(root: Instance): number
	local lowest = math.huge
	local function visit(part: BasePart)
		local cf, half = part.CFrame, part.Size / 2
		local extentY = math.abs(cf.XVector.Y) * half.X
			+ math.abs(cf.YVector.Y) * half.Y
			+ math.abs(cf.ZVector.Y) * half.Z
		lowest = math.min(lowest, cf.Position.Y - extentY)
	end
	if root:IsA("BasePart") then
		visit(root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			visit(descendant)
		end
	end
	return lowest
end

return Prims
