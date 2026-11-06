--!strict
-- SquishyCache (client only). DESIGN §2.4, §8.1 rule 1, §10.4 step 5.
-- One built template per (blueprint id, build mode, scale), made once by the shared SquishyBuilder and kept
-- unparented for the session; every use gets its own Clone(). (DESIGN §2.4 / §8.1 #1 say "one template per blueprint
-- id": the build mode (anchoring, welds) and the scale (baked into sizes) are part of a build, so they are part of the
-- key. Callers use a small fixed set: Held and Viewport at 1, each squishy's flightScale, the display/shelf/box scales.)
-- If a blueprint fails to build (builder error, missing
-- builder, or a result that is not a Model with a PrimaryPart) the cache keeps a labelled placeholder template for
-- that key instead and logs ONE warning per blueprint id, so callers always receive a usable Model.
--
-- Placeholder ("labelled" = name + attributes, no text: squishy models carry no GUIs, §8.1 rule 3): a Model named
-- "Placeholder" with attributes SD_Placeholder = true and SD_BlueprintId = <id>; an invisible 0.2³ Root
-- (PrimaryPart) and one lavender ellipsoid Body, following the same build-mode rules as real models (Viewport: all
-- anchored, no welds; World: anchored Root, Body welded; Held: nothing anchored, Body welded), every part Massless,
-- CanCollide/CanTouch/CanQuery false, collision group SD_Cosmetic when it is registered (as the builder does).
--
-- Model slots (the team's own final models replace a blueprint without code changes):
--   * Where: a Folder ReplicatedStorage.SD_Models, made by the team in Studio (not Rojo-managed, outside Shared).
--     A child Model named exactly the blueprint id ("kitty_bread" ... "dragon": the 8 squishies use their squishy id;
--     also "gift_box", "dragon_head_vfx") replaces that blueprint in every view this cache builds at runtime (hand,
--     flight, Inspect, cells, box reveal, collection display). The folder is read when a template is first built, so
--     a change shows after SquishyCache.clear() or on the next join.
--   * Not covered: models baked into the place at edit time. The lobby generator builds the Kitty Bread statue and
--     the two lobby gift boxes (counter and daily stand) straight from the blueprints, so they keep the blueprint look
--     whatever SD_Models holds.
--   * Facing: the model's pivot (its PrimaryPart's pivot, or WorldPivot without one) becomes the Root: what the hand
--     holds and what Inspect and flight turn about. The face looks toward the pivot's -Z (LookVector), +Y up. Put
--     the pivot at the body centre.
--   * Size is auto-fitted: the model is scaled uniformly about its pivot so its longest side equals the blueprint's
--     longest side as built for the same mode and scale (hand size, flight size = hit size), measured as the
--     pivot-space box around every part's box (Size × SpecialMesh Scale at its Offset; a FileMesh SpecialMesh by its
--     part Size). Author at any size; every part counts (no invisible helper parts).
--   * Parts: 1 to 64 BaseParts (nested Models allowed). MeshParts, Parts with or without a SpecialMesh and unions all
--     work and squash through Anim/SquishDeformer; Ball and Cylinder parts only squash uniformly. A part may carry
--     the attribute SD_Rigidity (0-1) to resist squash. The name "Root" is reserved: parts named Root are removed.
--   * Kept: parts with their Material, Color and Transparency, meshes, SurfaceAppearances, Decals, Textures,
--     Attachments, part attributes. Stripped: Scripts, LocalScripts and ModuleScripts, Sounds, Lights,
--     ParticleEmitters, Fire, Smoke, Sparkles, Trails, Beams, BillboardGuis, SurfaceGuis and ScreenGuis, Highlights,
--     ProximityPrompts, ClickDetectors, Humanoids, BodyMovers, every joint and constraint (the cache welds the parts
--     itself), every CollectionService tag, the model's own attributes.
--   * Forced, as SquishyBuilder does: every part CanCollide/CanTouch/CanQuery false, Massless, CastShadow, collision
--     group SD_Cosmetic when registered; a new invisible 0.2³ Root (PrimaryPart, Massless) at the origin = the pivot;
--     Viewport: every part anchored, no welds; World: Root anchored, the parts welded; Held: nothing anchored, the
--     parts welded. Welds are Weld instances with an explicit C0 to the Root, never WeldConstraints.
--   * Invalid slot (not a Model, not cloneable (Archivable off), no parts, more than 64 parts, unmeasurable size):
--     ONE warning per id and the blueprint model is used instead.
--   * The built model is named after the blueprint id and carries SD_ModelSlot = true, SD_SlotFit (the uniform fit
--     factor) and the builder's model attributes (SD_BlueprintId, SD_BlueprintVersion, SD_Scale, SD_Mode).
--   * The pen's light copy (pen squishies never squash, flap or swap faces): a child Model <blueprint id>_pen, or
--     _pen1 (Golden) / _pen2 (Rainbow) with the form's colours already in it, replaces the World model for clonePen
--     only, fitted and built like any slot. Without the form's one, clonePen gives the normal World model.
--   * A mesh body (the squish window dents its own mesh, see Controllers/KneadController): a MeshPart with SD_Body and
--     SD_Shape "M", its colours stored in the mesh, SD_ShellLow = the lighter mesh's uri for Low quality; SD_Outline =
--     true on its one dark shell, SD_OutlineShells = how many of the biggest closed shells that covers. A part that must
--     ride, flap or squash is a Part + FileMesh SpecialMesh.
--
-- API:
--   SquishyCache.clone(id, mode, scale?) -> Model   id = a squishy id (mapped through Catalog blueprintId) or a
--                                                     blueprint id ("gift_box", "dragon_head_vfx"); scale (default 1)
--                                                     multiplies the blueprint scale, as in SquishyBuilder.build
--   SquishyCache.clonePen(id, form?) -> (Model, boolean)   the pen's copy for form 0 (plain), 1 (Golden) or 2 (Rainbow):
--                                                     the form's light slot and true (its colours are the form's
--                                                     already), else the normal World model and false
--   SquishyCache.isPlaceholder(model) -> boolean
--   SquishyCache.isSlotModel(model) -> boolean       built from a model slot
--   SquishyCache.templateCount() -> number
--   SquishyCache.clear()                              destroys the templates (clones already handed out stay)
--   SquishyCache.new(build, warn?, slots?) -> Cache   a private cache around any build function (unit tests);
--                                                     slots = the slot folder (an Instance or a function returning
--                                                     one); nil = no model slots. Methods :clone, :templateCount,
--                                                     :clear. The default cache reads ReplicatedStorage.SD_Models.
--   SquishyCache.SLOT_FOLDER, SquishyCache.SLOT_MAX_PARTS

-- Services

local ContentProvider = game:GetService("ContentProvider")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)

-- Types

export type Mode = "Viewport" | "World" | "Held"
export type BuildFn = (blueprintId: string, mode: Mode, scale: number?) -> Model
export type WarnFn = (message: string) -> ()
export type SlotSource = Instance | () -> Instance?

type CacheData = {
	_build: BuildFn,
	_warn: WarnFn,
	_slots: (() -> Instance?)?,
	_templates: { [string]: Model },
	_warned: { [string]: boolean },
	_slotWarned: { [string]: boolean },
}

-- Constants

local MODES: { [string]: boolean } = { Viewport = true, World = true, Held = true }
local ATTR_PLACEHOLDER = "SD_Placeholder"
local ATTR_BLUEPRINT = "SD_BlueprintId"
local ATTR_MODE = "SD_Mode"
local ATTR_SLOT = "SD_ModelSlot"
local ATTR_SLOT_FIT = "SD_SlotFit"
local PLACEHOLDER_NAME = "Placeholder"
local ROOT_NAME = "Root"
local WELD_NAME = "SD_PartWeld"
local COSMETIC_GROUP = "SD_Cosmetic" -- §5.3
local ROOT_SIZE = Vector3.one * 0.2 -- §8.1 rule 3
local PLACEHOLDER_BODY = Vector3.new(1.4, 1.2, 1.2) -- inside the 1.4-1.8 in-hand size band (§8.1 rule 8)
local SLOT_FOLDER = "SD_Models"
local SLOT_MAX_PARTS = 64
local PEN_SLOTS: { [number]: string } = { [0] = "_pen", [1] = "_pen1", [2] = "_pen2" } -- by form: a light slot's suffix
-- Classes (IsA) removed from a slot model: behaviour, sound, light, effects, GUIs, interaction and physics.
local SLOT_STRIPPED = {
	"LuaSourceContainer", -- Script, LocalScript, ModuleScript
	"Sound",
	"Light",
	"ParticleEmitter",
	"Fire",
	"Smoke",
	"Sparkles",
	"Trail",
	"Beam",
	"LayerCollector", -- BillboardGui, SurfaceGui, ScreenGui
	"Highlight",
	"ProximityPrompt",
	"ClickDetector",
	"Humanoid",
	"BodyMover",
	"JointInstance", -- Weld, Motor6D, ...: the cache welds the parts itself
	"WeldConstraint",
	"NoCollisionConstraint",
	"Constraint",
}

-- Module tables

local CacheClass = {}
CacheClass.__index = CacheClass

export type Cache = typeof(setmetatable({} :: CacheData, CacheClass))

local SquishyCache = {}

-- Private

local log = Log.new("SquishyCache")
local defaultCache: Cache? = nil

local function isPositiveFinite(n: unknown): boolean
	return type(n) == "number" and n == n and n > 0 and n ~= math.huge
end

local function keyOf(blueprintId: string, mode: Mode, scale: number?): string
	-- nil and 1 build the same model (the builder's default scale is 1).
	return `{blueprintId}|{mode}|{string.format("%.4f", scale or 1)}`
end

local function cosmeticGroup(): string?
	return if PhysicsService:IsCollisionGroupRegistered(COSMETIC_GROUP) then COSMETIC_GROUP else nil
end

-- The SquishyBuilder flags (Material is left alone: placeholder parts set it, slot parts keep the team's).
local function applyFlags(part: BasePart, anchored: boolean, castShadow: boolean, group: string?)
	part.Anchored = anchored
	part.Massless = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false -- after CanCollide (CanQuery false needs a non-colliding part)
	part.CastShadow = castShadow
	if group then
		part.CollisionGroup = group
	end
end

local function makeRoot(mode: Mode, group: string?): Part
	local root = Instance.new("Part")
	root.Name = ROOT_NAME
	root.Shape = Enum.PartType.Block
	root.Size = ROOT_SIZE
	root.Transparency = 1
	root.CFrame = CFrame.identity
	root.Material = Enum.Material.SmoothPlastic
	applyFlags(root, mode ~= "Held", false, group)
	return root
end

-- Explicit Weld (same rule as SquishyBuilder): a WeldConstraint captures its offset only when parented.
local function weldToRoot(root: BasePart, part: BasePart)
	local weld = Instance.new("Weld")
	weld.Name = WELD_NAME
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = root.CFrame:ToObjectSpace(part.CFrame)
	weld.C1 = CFrame.identity
	weld.Parent = part
end

local function buildPlaceholder(blueprintId: string, mode: Mode, scale: number?): Model
	local s = scale or 1
	local group = cosmeticGroup()
	local model = Instance.new("Model")
	model.Name = PLACEHOLDER_NAME
	model:SetAttribute(ATTR_PLACEHOLDER, true)
	model:SetAttribute(ATTR_BLUEPRINT, blueprintId)

	local root = makeRoot(mode, group)
	root.Parent = model

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Block
	body.Size = PLACEHOLDER_BODY * s
	body.CFrame = CFrame.identity
	body.Color = Palette.Lavender
	body.Material = Enum.Material.SmoothPlastic
	applyFlags(body, mode == "Viewport", true, group)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	body.Parent = model

	if mode ~= "Viewport" then
		weldToRoot(root, body)
	end

	model.PrimaryPart = root
	return model
end

-- Required lazily inside the cache's pcall, so a builder that fails to load also ends in placeholders + warnings.
local function defaultBuild(blueprintId: string, mode: Mode, scale: number?): Model
	local SquishyBuilder = require(Shared.Art.SquishyBuilder)
	return SquishyBuilder.build(blueprintId, mode, scale)
end

local function defaultSlots(): Instance?
	return ReplicatedStorage:FindFirstChild(SLOT_FOLDER)
end

-- Model slots: measuring ----------------------------------------------------------------------------------------

local function partsOf(model: Model, except: BasePart?): { BasePart }
	local list: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= except then
			table.insert(list, descendant :: BasePart)
		end
	end
	return list
end

local function isFileMesh(mesh: DataModelMesh): boolean
	return mesh:IsA("SpecialMesh") and (mesh :: SpecialMesh).MeshType == Enum.MeshType.FileMesh
end

-- A part's rendered box relative to `pivot`: Size × mesh Scale at the mesh Offset. A FileMesh's size does not follow
-- the part, so such a part is measured by its Size.
local function renderedBox(part: BasePart, pivot: CFrame): (CFrame, Vector3)
	local frame = pivot:ToObjectSpace(part.CFrame)
	local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
	if mesh == nil or isFileMesh(mesh) then
		return frame, part.Size
	end
	return frame * CFrame.new(mesh.Offset), part.Size * mesh.Scale
end

-- The longest side of the pivot-space axis-aligned box around the rendered boxes of `parts` (0 for no parts).
local function longestSide(parts: { BasePart }, pivot: CFrame): number
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	for _, part in parts do
		local frame, size = renderedBox(part, pivot)
		local half = size / 2
		local x, y, z = frame.XVector * half.X, frame.YVector * half.Y, frame.ZVector * half.Z
		local ex = math.abs(x.X) + math.abs(y.X) + math.abs(z.X)
		local ey = math.abs(x.Y) + math.abs(y.Y) + math.abs(z.Y)
		local ez = math.abs(x.Z) + math.abs(y.Z) + math.abs(z.Z)
		local c = frame.Position
		minX, minY, minZ = math.min(minX, c.X - ex), math.min(minY, c.Y - ey), math.min(minZ, c.Z - ez)
		maxX, maxY, maxZ = math.max(maxX, c.X + ex), math.max(maxY, c.Y + ey), math.max(maxZ, c.Z + ez)
	end
	if minX > maxX then
		return 0
	end
	return math.max(maxX - minX, maxY - minY, maxZ - minZ)
end

-- Model slots: building -----------------------------------------------------------------------------------------

local function isStripped(instance: Instance): boolean
	for _, className in SLOT_STRIPPED do
		if instance:IsA(className) then
			return true
		end
	end
	return instance:IsA("BasePart") and instance.Name == ROOT_NAME
end

local function removeTags(instance: Instance)
	for _, tag in instance:GetTags() do
		instance:RemoveTag(tag)
	end
end

-- Scales every size and position uniformly by `fit` about `pivot`, which moves to the origin.
local function bakeScale(model: Model, parts: { BasePart }, pivot: CFrame, fit: number)
	for _, part in parts do
		local relative = pivot:ToObjectSpace(part.CFrame)
		part.Size *= fit
		part.CFrame = CFrame.new(relative.Position * fit) * relative.Rotation
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("DataModelMesh") then
			local mesh = descendant :: DataModelMesh
			mesh.Offset *= fit
			if isFileMesh(mesh) then
				mesh.Scale *= fit -- a FileMesh's Scale is absolute; the other mesh types follow the part Size
			end
		elseif descendant:IsA("Attachment") then
			local attachment = descendant :: Attachment
			attachment.Position *= fit
		elseif descendant:IsA("Texture") then
			local texture = descendant :: Texture
			texture.StudsPerTileU *= fit
			texture.StudsPerTileV *= fit
			texture.OffsetStudsU *= fit
			texture.OffsetStudsV *= fit
		end
	end
end

-- Turns a clone of the team's slot model into a template (header: Model slots). `reference` is the blueprint (or
-- placeholder) model built for the same key; its longest side and model attributes are copied. Errors with a reason.
local function shapeSlot(model: Model, blueprintId: string, mode: Mode, reference: Model): Model
	local pivot = model:GetPivot() -- before stripping: the PrimaryPart may be a reserved "Root"
	for _, descendant in model:GetDescendants() do
		if descendant.Parent ~= nil and isStripped(descendant) then
			descendant:Destroy()
		end
	end
	local parts = partsOf(model, nil)
	if #parts == 0 then
		error("it has no parts", 0)
	end
	if #parts > SLOT_MAX_PARTS then
		error(`it has {#parts} parts (limit {SLOT_MAX_PARTS})`, 0)
	end
	local wanted = longestSide(partsOf(reference, reference.PrimaryPart), reference:GetPivot())
	local have = longestSide(parts, pivot)
	if not (isPositiveFinite(wanted) and isPositiveFinite(have)) then
		error("its size cannot be measured", 0)
	end
	local fit = wanted / have
	bakeScale(model, parts, pivot, fit)

	local group = cosmeticGroup()
	local root = makeRoot(mode, group)
	root.Parent = model
	model.PrimaryPart = root
	for _, part in parts do
		applyFlags(part, mode == "Viewport", true, group)
		if mode ~= "Viewport" then
			weldToRoot(root, part)
		end
	end

	removeTags(model)
	for _, descendant in model:GetDescendants() do
		removeTags(descendant)
	end
	for name in model:GetAttributes() do
		model:SetAttribute(name, nil)
	end
	for name, value in reference:GetAttributes() do
		if name ~= ATTR_PLACEHOLDER then
			model:SetAttribute(name, value)
		end
	end
	model:SetAttribute(ATTR_BLUEPRINT, blueprintId)
	model:SetAttribute(ATTR_MODE, mode)
	model:SetAttribute(ATTR_SLOT, true)
	model:SetAttribute(ATTR_SLOT_FIT, fit)
	model.Name = blueprintId
	return model
end

-- A template from the slot instance `source`, or an error with the reason it cannot be used.
local function buildSlot(source: Instance, blueprintId: string, mode: Mode, reference: Model): Model
	if not source:IsA("Model") then
		error(`it is a {source.ClassName}, not a Model`, 0)
	end
	local copy: Model? = (source :: Model):Clone()
	if copy == nil then
		error("it cannot be cloned (Archivable is off)", 0)
	end
	local model = copy :: Model
	local ok, result = pcall(shapeSlot, model, blueprintId, mode, reference)
	if not ok then
		model:Destroy()
		error(result, 0)
	end
	return model
end

-- Cache internals

-- The blueprint model for a key, or a placeholder (one warning per blueprint id) when the blueprint fails.
local function buildBlueprint(self: Cache, blueprintId: string, mode: Mode, scale: number?): Model
	local ok, result = pcall(self._build, blueprintId, mode, scale)
	if ok and typeof(result) == "Instance" and result:IsA("Model") and result.PrimaryPart ~= nil then
		return result
	end
	if ok and typeof(result) == "Instance" then
		result:Destroy() -- a non-Model or a Model without PrimaryPart is unusable
	end
	if not self._warned[blueprintId] then
		self._warned[blueprintId] = true
		local reason = if ok then "the builder did not return a Model with a PrimaryPart" else tostring(result)
		self._warn(`blueprint "{blueprintId}" failed to build ({reason}); showing a placeholder`)
	end
	return buildPlaceholder(blueprintId, mode, scale)
end

local function slotSource(self: Cache, blueprintId: string): Instance?
	local resolve = self._slots
	if resolve == nil then
		return nil
	end
	local ok, folder = pcall(resolve)
	if not ok or typeof(folder) ~= "Instance" then
		return nil
	end
	return (folder :: Instance):FindFirstChild(blueprintId)
end

local function buildTemplate(self: Cache, blueprintId: string, mode: Mode, scale: number?): Model
	local built = buildBlueprint(self, blueprintId, mode, scale)
	local source = slotSource(self, blueprintId)
	if source == nil then
		return built
	end
	local ok, result = pcall(buildSlot, source, blueprintId, mode, built)
	if ok then
		built:Destroy()
		return result
	end
	if not self._slotWarned[blueprintId] then
		self._slotWarned[blueprintId] = true
		self._warn(
			`model slot ReplicatedStorage.{SLOT_FOLDER}.{blueprintId} cannot be used ({tostring(result)});`
				.. " showing the blueprint model"
		)
	end
	return built
end

-- Cache methods

-- A fresh copy of the template for (id, mode, scale), building the template on first use.
function CacheClass.clone(self: Cache, id: string, mode: Mode, scale: number?): Model
	assert(type(id) == "string" and id ~= "", "[SD][SquishyCache] id must be a non-empty string")
	assert(MODES[mode] == true, `[SD][SquishyCache] unknown build mode {tostring(mode)}`)
	assert(scale == nil or isPositiveFinite(scale), "[SD][SquishyCache] scale must be a finite number > 0")

	local def = Catalog.get(id)
	local blueprintId = if def then def.blueprintId else id
	local key = keyOf(blueprintId, mode, scale)
	local template: Model? = self._templates[key]
	if template == nil then
		local made = buildTemplate(self, blueprintId, mode, scale)
		self._templates[key] = made
		template = made
	end
	return (template :: Model):Clone()
end

-- The pen's copy for (id, form): the form's light slot and true, else the normal World model and false (header).
function CacheClass.clonePen(self: Cache, id: string, form: number?): (Model, boolean)
	local def = Catalog.get(id)
	local blueprintId = if def then def.blueprintId else id
	local slotName = blueprintId .. (PEN_SLOTS[form or 0] or PEN_SLOTS[0])
	local key = keyOf(slotName, "World", nil)
	local template: Model? = self._templates[key]
	if template == nil then
		local source = if self._slotWarned[slotName] then nil else slotSource(self, slotName) -- a bad slot: one try
		if source == nil then
			return self:clone(id, "World"), false
		end
		local reference = buildBlueprint(self, blueprintId, "World", nil)
		local ok, result = pcall(buildSlot, source, blueprintId, "World" :: Mode, reference)
		reference:Destroy()
		if not ok then
			self._slotWarned[slotName] = true
			self._warn(
				`model slot ReplicatedStorage.{SLOT_FOLDER}.{slotName} cannot be used ({tostring(result)});`
					.. " showing the normal model"
			)
			return self:clone(id, "World"), false
		end
		self._templates[key] = result
		template = result
	end
	return (template :: Model):Clone(), true
end

function CacheClass.templateCount(self: Cache): number
	local count = 0
	for _ in self._templates do
		count += 1
	end
	return count
end

function CacheClass.clear(self: Cache)
	for _, template in self._templates do
		template:Destroy()
	end
	table.clear(self._templates)
end

-- Public

SquishyCache.SLOT_FOLDER = SLOT_FOLDER
SquishyCache.SLOT_MAX_PARTS = SLOT_MAX_PARTS

function SquishyCache.new(build: BuildFn, warn: WarnFn?, slots: SlotSource?): Cache
	local resolve: (() -> Instance?)? = nil
	if typeof(slots) == "Instance" then
		local folder = slots :: Instance
		resolve = function(): Instance?
			return folder
		end
	elseif type(slots) == "function" then
		resolve = slots :: () -> Instance?
	end
	local data: CacheData = {
		_build = build,
		_warn = warn or function(message: string)
			log:warn(message)
		end,
		_slots = resolve,
		_templates = {},
		_warned = {},
		_slotWarned = {},
	}
	return setmetatable(data, CacheClass)
end

local function default(): Cache
	local cache = defaultCache
	if cache == nil then
		cache = SquishyCache.new(defaultBuild, nil, defaultSlots)
		defaultCache = cache
		-- Uploaded meshes download the first time they show: fetch the slots' now, so no view opens on a half-drawn toy.
		local folder = defaultSlots()
		if folder then
			task.spawn(function()
				pcall(function()
					ContentProvider:PreloadAsync(folder:GetDescendants())
				end)
			end)
		end
	end
	return cache :: Cache
end

function SquishyCache.clone(id: string, mode: Mode, scale: number?): Model
	return default():clone(id, mode, scale)
end

function SquishyCache.clonePen(id: string, form: number?): (Model, boolean)
	return default():clonePen(id, form)
end

function SquishyCache.isPlaceholder(model: Instance): boolean
	return model:GetAttribute(ATTR_PLACEHOLDER) == true
end

function SquishyCache.isSlotModel(model: Instance): boolean
	return model:GetAttribute(ATTR_SLOT) == true
end

function SquishyCache.templateCount(): number
	return if defaultCache then defaultCache:templateCount() else 0
end

function SquishyCache.clear()
	if defaultCache then
		defaultCache:clear()
	end
end

return SquishyCache
