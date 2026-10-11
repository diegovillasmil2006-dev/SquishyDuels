--!strict
-- SquishDeformer (client only). Squash and stretch of a built squishy model (DESIGN §9.3, §8.1 #5).
-- Blueprint models (Art/SquishyBuilder) deform mesh-only: their parts never move, only SpecialMesh Scale/Offset (and
-- the Size of rounded boxes) change, so welds, the hand and collisions are untouched in every build mode. Team models
-- from the model slots (Models/SquishyCache, ReplicatedStorage.SD_Models) may use MeshParts and plain parts; those
-- "solid" parts are resized and moved instead (below), still from stored base values only.
--
-- Attach (once per built model; attach() on an attached model returns the same deformer): for every visual part,
-- relative to the model pivot, it stores position p, rotation R, base mesh Scale, base mesh Offset, base Size (RB and
-- solid parts), rigidity (0-1) and, for solid parts, the base Weld.C0 or the base CFrame. Base values are read from
-- the parts as built, so attach before any deformation.
-- Part data contract with Art/SquishyBuilder and Models/SquishyCache (every BasePart descendant except the model's
-- PrimaryPart, the Root, which never deforms):
--   * a part with a DataModelMesh child (SpecialMesh E/B/W, also the B fallback of RB, or a FileMesh) → mesh path;
--   * a rounded box RB without a mesh (attribute SD_Shape = "RB", or a PartOperation centred on the pivot with no
--     rotation) → Size path (an SD_Shape = "RB" part must be centred on the pivot with no rotation, §8.1 #2;
--     otherwise one warning);
--   * any other part (a MeshPart, a plain Part without a mesh, an off-centre PartOperation) → solid path;
--   * rigidity = attribute SD_Rigidity (number, clamped to 0-1; missing = 0).
--
-- setScale(S), S in pivot space, is always computed from the stored base, never incrementally:
--   kv = (|R·x̂ ∘ S|, |R·ŷ ∘ S|, |R·ẑ ∘ S|);  kv = 1 + (kv - 1)·(1 - rigidity)
--   mesh.Scale = base.Scale ∘ kv;  mesh.Offset = base.Offset + R⁻¹(p ∘ S - p);  RB: part.Size = base.Size ∘ kv
--   solid: part.Size = base.Size ∘ kv, and the part moves by d = p ∘ S - p (pivot space): a part with its own Weld
--     (a child Weld whose Part1 is the part; Held/World builds) through Weld.C0 = base.C0 + d (in Part0 space), any
--     other part (Viewport builds, anchored) through part.CFrame = pivot · CFrame(p ∘ S) · R, where pivot is the
--     model's current pivot (so a model moved by PivotTo or a "pivot" twist stays consistent). Rest writes base.Size
--     and base.C0, or base.CFrame (bit-exact while the model sits where it was at attach; else pivot · CFrame(p) · R).
--     A Ball or Cylinder part only scales uniformly (engine rule); use MeshParts or SpecialMeshes for squash.
-- S is clamped per axis to Config.Anim.deform [scaleMin, scaleMax] (options.scaleMax lifts the ceiling for one deformer:
-- the first-person copy, spec 2026-10-11 §3.5). squash(a) gives the volume-preserving S
-- (c = 1 - a on the squeeze axis, w = 1/√c on the others, a <= maxSquash).
--
-- Twist (the Uncommon flourish) turns the whole model about its pivot, never single parts. Where it is written is
-- chosen at attach: "weld" → Weld.C1 (held), "pivot" → Model:PivotTo (viewport), "root" → PrimaryPart.CFrame (world
-- display); with no target the twist is only stored (getTwist). The base CFrame is captured at attach; an owner that
-- moves the model itself while a twist target is set passes the new un-twisted CFrame to setTwistBase(). An owner
-- that calls set() right after (the per-frame idle bob) passes deferWrite = true, so the target is written once.
--
-- Rest and sleep: when |S - 1| < restEpsilon on every axis, the base values are written exactly once and then
-- nothing more is written until S leaves rest; the same for the twist below twistEpsilon.
-- Writes (rig speed-up pass): the deformer is the only writer of what it drives (no owner writes a driven property while
-- attached), so each part keeps the values it last wrote. A deformed mesh Scale (as rendered size, Size ∘ Scale; exact
-- for a FileMesh, whose Scale is absolute), mesh Offset or Size is rewritten only once it moved
-- Config.Anim.deform.writeEpsilon studs on some axis, so every shown value stays within that of the formula; a weld C0
-- only when it changed; base values (rest, a section back at its base) whenever they differ, so rest stays exact.
-- Options for whole pieces of world cover (the jelly ripple's path B, DESIGN §18.3.5): includePrimary = true also
-- deforms the model's PrimaryPart (a cover piece's `Body`; a squishy's Root never deforms); pivot = a CFrame used as
-- the deformation pivot instead of the model pivot, e.g. the piece's bottom centre, so a squash never sinks it into the
-- floor (S is then in that pivot's space). Unwelded solid parts follow the model as before: they are written against
-- the current model pivot times the stored pivot offset.
--
-- Faces, looks and sections (squishy overhaul spec 2026-10-09 §3.2; mesh parts of builder models only):
--   * apply(out) writes one Anim/SquishRig `out` per frame (scale, twist, face, blink, cheek, sections) in one pass;
--     an owner's overlay multiplies out.S before the call.
--   * setFace(state, force?): the look parts (attribute SD_Look) hide and show for "normal", "squish" and "wow"
--     (Transparency 1 or 0), written only on a change; force re-applies after an outside Transparency write. Hidden
--     parts are skipped in per-frame writes and get the current values when shown.
--   * look multipliers on mesh Scale (X, Y in the face plane; Config.Anim.rig.looks): eyes × wow and × blink on Y,
--     shines hidden (scale 0) while the blink is below blink.shineHideBelow, cheeks × cheek, the open mouth and the
--     squish mouth per face.
--   * setSections(angles?): angles (radians) per slot (SquishRig.sectionNames of the blueprint's sections, read from
--     SquishyBlueprints[SD_BlueprintId].sections × SD_Scale, or options.sections) turn each section part (SD_Section)
--     about its pivot; nil turns the section path off. A section part moves (spec §8.1 #5 exception), always from base:
--     Q = turn about the axis through pivot h, p' = h + Q(p - h), R' = Q·R; mesh.Scale = base ∘ kv(R', S) ∘ look,
--     Offset = base; placed at CFrame(p' ∘ S)·R' through its SD_PartWeld.C0 (Held/World) or as pivot·CFrame(p' ∘ S)·R'
--     with the model's current pivot, before the twist's PivotTo (Viewport). At θ = 0 it renders like the mesh path, so
--     a section part at exactly 0 takes the mesh path (no C0 or CFrame write; back from a turn its base C0 or CFrame is
--     written once). Turning the path off writes the base C0 or CFrame once; other players' models never turn it on (no
--     C0 writes).
--   * rest() also puts the face back to normal, the multipliers to 1 and the sections to their base; isResting()
--     covers every channel. The rest-and-sleep rule above holds with the looks at 1 and every angle at 0.
-- No connections, instances or threads: the owner puts the deformer (it has destroy()) in its Cleanup.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local SquishyBlueprints = require(Shared.Art.SquishyBlueprints)
local SquishRig = require(script.Parent.SquishRig)

-- Types

export type Axis = "X" | "Y" | "Z"
export type TwistTarget = "weld" | "pivot" | "root"

export type Options = {
	twist: TwistTarget?,
	weld: Weld?, -- required for twist = "weld" (Part1 = the model's Root)
	twistAxis: Axis?, -- pivot-space axis of the twist (default "Y")
	includePrimary: boolean?, -- also deform the PrimaryPart (cover pieces, §18.3.5); default false
	pivot: CFrame?, -- the deformation pivot (default the model pivot at attach)
	sections: { [string]: SquishyBlueprints.Section }?, -- instead of the blueprint's (test fixtures)
	-- This deformer's per-axis ceiling instead of Config.Anim.deform.scaleMax (never lower; math.huge = none): the
	-- first-person copy, whose owner clamps the rig's part itself and puts the design's scale keys on top (sling 1.75).
	scaleMax: number?,
}

export type Face = SquishRig.Face

-- One hinged section: its pivot and axis in pivot space (build scale).
type SectionData = { pivot: Vector3, axis: Vector3 }

type PartData = {
	part: BasePart,
	mesh: DataModelMesh?,
	solid: boolean, -- no mesh and not a rounded box: Size + position (Weld.C0 or CFrame)
	p: Vector3,
	R: CFrame,
	relative: CFrame, -- the part relative to the pivot at attach, CFrame(p) · R
	xv: Vector3,
	yv: Vector3,
	zv: Vector3,
	ox: Vector3, -- R⁻¹x̂ · p.X: the mesh Offset moves by ox(S.X - 1) + oy(S.Y - 1) + oz(S.Z - 1) = R⁻¹(p ∘ S - p)
	oy: Vector3,
	oz: Vector3,
	baseScale: Vector3,
	baseOffset: Vector3,
	baseSize: Vector3?, -- RB and solid parts
	rigidity: number,
	weld: Weld?, -- solid and section parts with their own Weld (Part1 = the part)
	baseC0: CFrame, -- welded solid and section parts: Weld.C0 at attach
	toPart0: CFrame, -- welded solid parts: rotation from pivot space to the weld's Part0 space
	pivotToPart0: CFrame, -- welded section parts: the pivot in the weld's Part0 space
	baseCFrame: CFrame, -- unwelded solid and section parts: part.CFrame at attach
	look: string?, -- SD_Look (mesh parts)
	slot: number?, -- section slot (mesh parts with a known SD_Section)
	hidden: boolean, -- hidden by the face state (skipped in per-frame writes)
	moved: boolean, -- a section part away from its base C0 or CFrame
	-- The values last written (the deformer is their only writer) and the mesh Scale's writeEpsilon per axis.
	scale: Vector3,
	offset: Vector3,
	size: Vector3?,
	c0: CFrame,
	scaleTol: Vector3,
}

type DeformerData = {
	model: Model,
	_parts: { PartData },
	_pivot: CFrame, -- the deformation pivot at attach (options.pivot, else the model pivot)
	_pivotOffset: CFrame?, -- options.pivot relative to the model pivot at attach (nil = the model pivot itself)
	_freeSolids: boolean, -- some solid part has no weld (its CFrame is written relative to the current pivot)
	_scale: Vector3,
	_scaleMax: number, -- options.scaleMax, else scaleMax
	_twist: number,
	_meshAtBase: boolean,
	_twistAtBase: boolean,
	_twistTarget: TwistTarget?,
	_twistAxis: Vector3,
	_twistBase: CFrame,
	_twistDirty: boolean, -- a deferred setTwistBase() still has to be written
	_weld: Weld?,
	_root: BasePart?,
	_destroyed: boolean,
	-- faces, looks and sections
	_face: Face,
	_blink: number,
	_cheek: number,
	_lookParts: { PartData },
	_eyeMul: Vector3, -- this pass's look multipliers (set by updateLooks)
	_shineMul: Vector3,
	_cheekMul: Vector3,
	_mouthOpenMul: Vector3,
	_squishMouthMul: Vector3,
	_sections: { SectionData },
	_sectionNames: { string },
	_angles: { number },
	_sectionsOn: boolean,
	_freeSections: boolean, -- some section part has no weld (Viewport: written against the current pivot)
}

-- Constants

local DEFORM = Config.Anim.deform
local SCALE_MIN = DEFORM.scaleMin
local SCALE_MAX = DEFORM.scaleMax
local MAX_SQUASH = DEFORM.maxSquash
local REST_EPSILON = DEFORM.restEpsilon
local TWIST_EPSILON = DEFORM.twistEpsilon
local WRITE_EPSILON = DEFORM.writeEpsilon -- studs

local RIGIDITY_ATTRIBUTE = "SD_Rigidity"
local SHAPE_ATTRIBUTE = "SD_Shape"
local ROUNDED_BOX = "RB"
local RB_CENTRE_TOLERANCE = 1e-3 -- studs / rotation-matrix units; authoring check only
local LOOK_ATTRIBUTE = "SD_Look"
local SECTION_ATTRIBUTE = "SD_Section"
local BLUEPRINT_ATTRIBUTE = "SD_BlueprintId"
local SCALE_ATTRIBUTE = "SD_Scale"

local LOOKS = Config.Anim.rig.looks
local SHINE_HIDE_BELOW = Config.Anim.rig.blink.shineHideBelow
-- The looks each face state hides (spec §3.2 table); the squish set is built hidden, as in "normal".
local HIDDEN: { [string]: { [string]: boolean } } = {
	normal = { squishEye = true, squishMouth = true, tongue = true },
	squish = { eye = true, eyeArc = true, shine = true, mouth = true },
	wow = { mouth = true, squishEye = true, tongue = true },
}

local AXES: { [Axis]: Vector3 } = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }

-- Module table

local DeformerClass = {}
DeformerClass.__index = DeformerClass

export type Deformer = typeof(setmetatable({} :: DeformerData, DeformerClass))

local SquishDeformer = {}

-- Private

local log = Log.new("SquishDeformer")
local registry: { [Model]: Deformer } = setmetatable({}, { __mode = "k" }) :: any

local function clampAxis(x: number, hi: number?): number
	if x ~= x then
		return 1
	end
	return math.clamp(x, SCALE_MIN, hi or SCALE_MAX)
end

local function clampScale(S: Vector3, hi: number?): Vector3
	return Vector3.new(clampAxis(S.X, hi), clampAxis(S.Y, hi), clampAxis(S.Z, hi))
end

local function axisVector(axis: Axis?): Vector3
	local key: Axis = if axis then axis else "Y"
	local vector = AXES[key]
	assert(vector, `[SD][SquishDeformer] axis must be "X", "Y" or "Z" (got {tostring(axis)})`)
	return vector
end

local function readRigidity(part: BasePart): number
	local value = part:GetAttribute(RIGIDITY_ATTRIBUTE)
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

local function isIdentityRotation(R: CFrame): boolean
	return (R.XVector - Vector3.xAxis).Magnitude < RB_CENTRE_TOLERANCE
		and (R.YVector - Vector3.yAxis).Magnitude < RB_CENTRE_TOLERANCE
end

-- The part's own Weld to the rest of the model (Part1 = the part, as SquishyBuilder and SquishyCache build it).
local function ownWeld(part: BasePart): Weld?
	for _, child in part:GetChildren() do
		if child:IsA("Weld") then
			local weld = child :: Weld
			if weld.Part1 == part and weld.Part0 ~= nil and weld.Part0 ~= part then
				return weld
			end
		end
	end
	return nil
end

local function collectParts(
	model: Model,
	pivot: CFrame,
	includePrimary: boolean,
	slotOf: { [string]: number }
): { PartData }
	local list: { PartData } = {}
	local warnedRB = false
	local primary = if includePrimary then nil else model.PrimaryPart
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") or descendant == primary then
			continue -- the Root never deforms (unless options.includePrimary)
		end
		local part = descendant :: BasePart
		local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
		local relative = pivot:ToObjectSpace(part.CFrame)
		local R = relative.Rotation
		local centred = relative.Position.Magnitude <= RB_CENTRE_TOLERANCE and isIdentityRotation(R)
		local taggedRB = part:GetAttribute(SHAPE_ATTRIBUTE) == ROUNDED_BOX
		local roundedBox = mesh == nil and (taggedRB or (part:IsA("PartOperation") and centred))
		local solid = mesh == nil and not roundedBox
		if roundedBox and not centred and not warnedRB then
			warnedRB = true
			log:warn(`{model.Name}.{part.Name}: a rounded box must be centred on the pivot with no rotation`)
		end
		local lookValue = if mesh then part:GetAttribute(LOOK_ATTRIBUTE) else nil
		local look = if type(lookValue) == "string" then lookValue else nil
		local sectionValue = if mesh then part:GetAttribute(SECTION_ATTRIBUTE) else nil
		local slot = if type(sectionValue) == "string" then slotOf[sectionValue] else nil
		local weld = if solid or slot then ownWeld(part) else nil
		local part0 = if weld then weld.Part0 else nil
		local p = relative.Position
		local baseScale = if mesh then mesh.Scale else Vector3.one
		local baseOffset = if mesh then mesh.Offset else Vector3.zero
		local baseSize = if mesh == nil then part.Size else nil
		local baseC0 = if weld then weld.C0 else CFrame.identity
		-- A FileMesh's Scale is absolute (no known rendered size): its writes stay exact.
		local fileMesh = mesh ~= nil
			and mesh:IsA("SpecialMesh")
			and (mesh :: SpecialMesh).MeshType == Enum.MeshType.FileMesh
		local size = part.Size
		table.insert(list, {
			part = part,
			mesh = mesh,
			solid = solid,
			p = p,
			R = R,
			relative = relative,
			xv = R.XVector,
			yv = R.YVector,
			zv = R.ZVector,
			ox = R:VectorToObjectSpace(Vector3.xAxis) * p.X,
			oy = R:VectorToObjectSpace(Vector3.yAxis) * p.Y,
			oz = R:VectorToObjectSpace(Vector3.zAxis) * p.Z,
			baseScale = baseScale,
			baseOffset = baseOffset,
			baseSize = baseSize,
			rigidity = readRigidity(part),
			weld = weld,
			baseC0 = baseC0,
			toPart0 = if part0 then part0.CFrame:ToObjectSpace(pivot).Rotation else CFrame.identity,
			pivotToPart0 = if part0 then part0.CFrame:ToObjectSpace(pivot) else CFrame.identity,
			baseCFrame = part.CFrame,
			look = look,
			slot = slot,
			hidden = look ~= nil and HIDDEN.normal[look] == true,
			moved = false,
			scale = baseScale,
			offset = baseOffset,
			size = baseSize,
			c0 = baseC0,
			scaleTol = if fileMesh
				then Vector3.zero
				else Vector3.new(WRITE_EPSILON / size.X, WRITE_EPSILON / size.Y, WRITE_EPSILON / size.Z),
		})
	end
	return list
end

-- The hinged sections of a built model (spec §3.2): options.sections, else its blueprint's, scaled by SD_Scale and
-- turned into pivot space. Returns the slot names (SquishRig.sectionNames order) and the data by slot.
local function collectSections(
	model: Model,
	pivot: CFrame,
	override: { [string]: SquishyBlueprints.Section }?
): ({ string }, { SectionData })
	local sections = override
	if sections == nil then
		local id = model:GetAttribute(BLUEPRINT_ATTRIBUTE)
		local blueprint = if type(id) == "string" then SquishyBlueprints[id] else nil
		sections = if blueprint then blueprint.sections else nil
	end
	local names = SquishRig.sectionNames(sections)
	local data: { SectionData } = {}
	if sections == nil or #names == 0 then
		return names, data
	end
	local scaleValue = model:GetAttribute(SCALE_ATTRIBUTE)
	local scale = if type(scaleValue) == "number" then scaleValue else 1
	local modelPivot = model:GetPivot()
	for index, name in names do
		local section = sections[name]
		data[index] = {
			pivot = pivot:PointToObjectSpace(modelPivot:PointToWorldSpace(section.pivot * scale)),
			axis = pivot:VectorToObjectSpace(modelPivot:VectorToWorldSpace(axisVector(section.axis))).Unit,
		}
	end
	return names, data
end

local function nearOne(S: Vector3): boolean
	return math.abs(S.X - 1) < REST_EPSILON and math.abs(S.Y - 1) < REST_EPSILON and math.abs(S.Z - 1) < REST_EPSILON
end

-- The pivot unwelded solid and section parts are written against: the current one (the owner may have moved the
-- model), with the options.pivot offset when one was given.
local function currentPivot(self: Deformer): CFrame
	if not self._freeSolids and not self._freeSections then
		return self._pivot
	end
	local offset = self._pivotOffset
	return if offset then self.model:GetPivot() * offset else self.model:GetPivot()
end

-- This pass's look multipliers (spec §3.2 table) from the face, blink and cheek.
local function updateLooks(self: Deformer)
	local face = self._face
	local wow = face == "wow"
	local eye = if wow then LOOKS.wowEye else 1
	self._eyeMul = Vector3.new(eye, eye * self._blink, 1)
	self._shineMul = if self._blink < SHINE_HIDE_BELOW then Vector3.zero else Vector3.one
	self._cheekMul = Vector3.one * self._cheek
	self._mouthOpenMul = if face == "squish"
		then LOOKS.squishMouthOpen
		elseif wow then LOOKS.wowMouthOpen
		else Vector3.one
	self._squishMouthMul = if wow then LOOKS.wowSquishMouth else Vector3.one
end

local function lookMul(self: Deformer, look: string?): Vector3
	if look == "eye" then
		return self._eyeMul
	elseif look == "shine" then
		return self._shineMul
	elseif look == "cheek" then
		return self._cheekMul
	elseif look == "mouthOpen" then
		return self._mouthOpenMul
	elseif look == "squishMouth" then
		return self._squishMouthMul
	end
	return Vector3.one
end

-- Every look multiplier is 1 and every section angle 0 (with S at rest, the model sleeps).
local function looksAtRest(self: Deformer): boolean
	if
		self._face ~= "normal"
		or math.abs(self._blink - 1) >= REST_EPSILON
		or math.abs(self._cheek - 1) >= REST_EPSILON
	then
		return false
	end
	if self._sectionsOn then
		for _, angle in self._angles do
			if math.abs(angle) >= TWIST_EPSILON then
				return false
			end
		end
	end
	return true
end

-- The writes (header "Writes"): a deformed value only once it moved writeEpsilon studs on some axis from the value last
-- written; with exact = true (base values) whenever it differs at all.
local function putScale(data: PartData, value: Vector3, exact: boolean)
	local last = data.scale
	if value == last then
		return
	end
	if not exact then
		local d, tol = value - last, data.scaleTol
		if math.abs(d.X) <= tol.X and math.abs(d.Y) <= tol.Y and math.abs(d.Z) <= tol.Z then
			return
		end
	end
	data.scale = value
	local mesh = data.mesh :: DataModelMesh
	mesh.Scale = value
end

local function putOffset(data: PartData, value: Vector3, exact: boolean)
	local last = data.offset
	if value == last then
		return
	end
	if not exact then
		local d = value - last
		if math.abs(d.X) <= WRITE_EPSILON and math.abs(d.Y) <= WRITE_EPSILON and math.abs(d.Z) <= WRITE_EPSILON then
			return
		end
	end
	data.offset = value
	local mesh = data.mesh :: DataModelMesh
	mesh.Offset = value
end

local function putSize(data: PartData, value: Vector3, exact: boolean)
	local last = data.size :: Vector3
	if value == last then
		return
	end
	if not exact then
		local d = value - last
		if math.abs(d.X) <= WRITE_EPSILON and math.abs(d.Y) <= WRITE_EPSILON and math.abs(d.Z) <= WRITE_EPSILON then
			return
		end
	end
	data.size = value
	data.part.Size = value
end

local function putC0(data: PartData, value: CFrame)
	if value ~= data.c0 then
		data.c0 = value
		local weld = data.weld :: Weld
		weld.C0 = value
	end
end

-- A section part back at its base C0 (welded) or CFrame (Viewport; bit-exact while the model is where it was).
local function placeAtBase(data: PartData, pivot: CFrame, unmoved: boolean)
	if data.weld then
		putC0(data, data.baseC0)
	else
		data.part.CFrame = if unmoved then data.baseCFrame else pivot * data.relative
	end
	data.moved = false
end

local function sectionsToBase(self: Deformer)
	local pivot: CFrame? = nil -- read once, only when a part has moved
	for _, data in self._parts do
		if data.moved then
			local at = pivot or currentPivot(self)
			pivot = at
			placeAtBase(data, at, at == self._pivot)
		end
	end
end

-- One section part turned by its slot's angle (not 0) about the section pivot, then squashed (spec §3.2 math).
local function writeSectionPart(self: Deformer, data: PartData, S: Vector3, pivot: CFrame, angle: number)
	local section = self._sections[data.slot :: number]
	local Q = CFrame.fromAxisAngle(section.axis, angle)
	local p = section.pivot + Q:VectorToWorldSpace(data.p - section.pivot)
	local R = Q * data.R
	local kv = Vector3.new((R.XVector * S).Magnitude, (R.YVector * S).Magnitude, (R.ZVector * S).Magnitude)
	kv = Vector3.one + (kv - Vector3.one) * (1 - data.rigidity)
	putScale(data, data.baseScale * kv * lookMul(self, data.look), false)
	putOffset(data, data.baseOffset, true)
	local placed = CFrame.new(p * S) * R
	if data.weld then
		putC0(data, data.pivotToPart0 * placed)
	else
		data.part.CFrame = pivot * placed
	end
	data.moved = true
end

local function writeBaseMeshes(self: Deformer)
	local pivot = currentPivot(self)
	local unmoved = pivot == self._pivot
	for _, data in self._parts do
		local mesh = data.mesh
		if mesh then
			putScale(data, data.baseScale, true)
			putOffset(data, data.baseOffset, true)
			if data.moved then
				placeAtBase(data, pivot, unmoved)
			end
		elseif data.solid then
			putSize(data, data.baseSize :: Vector3, true)
			if data.weld then
				putC0(data, data.baseC0)
			else
				data.part.CFrame = if unmoved then data.baseCFrame else pivot * data.relative
			end
		elseif data.baseSize then
			putSize(data, data.baseSize, true)
		end
	end
end

local function writeMeshes(self: Deformer, S: Vector3)
	local pivot: CFrame? = nil -- the current pivot, read once and only for a part placed against it
	local sectionsOn = self._sectionsOn
	local d = S - Vector3.one
	local dx, dy, dz = d.X, d.Y, d.Z
	for _, data in self._parts do
		if data.hidden then
			continue -- written when shown (setFaceState)
		end
		local slot = data.slot
		if sectionsOn and slot then
			local angle = self._angles[slot] or 0
			if angle ~= 0 or data.moved then
				local at = pivot or currentPivot(self)
				pivot = at
				if angle ~= 0 then
					writeSectionPart(self, data, S, at, angle)
					continue
				end
				placeAtBase(data, at, at == self._pivot) -- back at θ = 0: the mesh path below renders the same
			end
		end
		local kv = Vector3.new((data.xv * S).Magnitude, (data.yv * S).Magnitude, (data.zv * S).Magnitude)
		kv = Vector3.one + (kv - Vector3.one) * (1 - data.rigidity)
		local mesh = data.mesh
		if mesh then
			local look = data.look
			putScale(data, if look then data.baseScale * kv * lookMul(self, look) else data.baseScale * kv, false)
			-- R⁻¹(p ∘ S - p) from the per-axis steps (parts never move)
			putOffset(data, data.baseOffset + data.ox * dx + data.oy * dy + data.oz * dz, false)
		elseif data.solid then
			-- Team slot models (MeshParts, plain parts): resize and move from the base, never from the current value.
			putSize(data, (data.baseSize :: Vector3) * kv, false)
			local centre = data.p * S
			if data.weld then
				putC0(data, data.baseC0 + data.toPart0:VectorToWorldSpace(centre - data.p))
			else
				local at = pivot or currentPivot(self)
				pivot = at
				data.part.CFrame = at * CFrame.new(centre) * data.R
			end
		elseif data.baseSize then
			putSize(data, data.baseSize * kv, false) -- RB: pivot-centred, unrotated; no CFrame write
		end
	end
end

local function writeTwist(self: Deformer, angle: number)
	local target = self._twistTarget
	if target == nil then
		return
	end
	local base = self._twistBase
	if target == "weld" then
		local weld = self._weld :: Weld
		weld.C1 = if angle == 0 then base else CFrame.fromAxisAngle(self._twistAxis, -angle) * base
	elseif target == "pivot" then
		self.model:PivotTo(if angle == 0 then base else base * CFrame.fromAxisAngle(self._twistAxis, angle))
	else
		local root = self._root :: BasePart
		root.CFrame = if angle == 0 then base else base * CFrame.fromAxisAngle(self._twistAxis, angle)
	end
end

-- The face state's Transparency on the look parts, written only on a change (every look part with force).
local function setFaceState(self: Deformer, state: Face, force: boolean)
	local hidden = HIDDEN[state]
	assert(hidden, `[SD][SquishDeformer] unknown face {tostring(state)}`)
	if state == self._face and not force then
		return
	end
	self._face = state
	for _, data in self._lookParts do
		local hide = hidden[data.look :: string] == true
		if force or hide ~= data.hidden then
			data.hidden = hide
			data.part.Transparency = if hide then 1 else 0
		end
	end
end

-- Section angles by slot (radians) turn the section path on; nil turns it off (base C0 or CFrame written once).
local function setSectionsState(self: Deformer, angles: { number }?)
	local count = #self._sections
	if angles == nil or count == 0 then
		if self._sectionsOn then
			self._sectionsOn = false
			sectionsToBase(self)
		end
		return
	end
	self._sectionsOn = true
	for index = 1, count do
		local angle = angles[index]
		self._angles[index] = if angle and angle == angle then angle else 0
	end
end

local function write(self: Deformer)
	if self._destroyed then
		return
	end
	-- Mesh scale, look multipliers and sections.
	local S = self._scale
	updateLooks(self)
	if nearOne(S) and looksAtRest(self) then
		if not self._meshAtBase then
			writeBaseMeshes(self)
			self._meshAtBase = true
		end
	else
		writeMeshes(self, S)
		self._meshAtBase = false
	end
	-- Whole-model twist.
	local angle = self._twist
	if math.abs(angle) < TWIST_EPSILON then
		if not self._twistAtBase or self._twistDirty then
			writeTwist(self, 0)
			self._twistAtBase = true
		end
	else
		writeTwist(self, angle)
		self._twistAtBase = false
	end
	self._twistDirty = false
end

-- Deformer methods

-- Sets the scale S (pivot space; clamped) and writes it, from the base values.
function DeformerClass.setScale(self: Deformer, S: Vector3)
	local clamped = clampScale(S, self._scaleMax)
	if clamped == self._scale and not self._meshAtBase and not self._twistDirty then
		return -- already written
	end
	self._scale = clamped
	write(self)
end

-- Sets the whole-model twist (radians, about the twist axis) and writes it to the twist target.
function DeformerClass.setTwist(self: Deformer, angle: number)
	local value = if angle == angle then angle else 0
	if value == self._twist and not self._twistAtBase and not self._twistDirty then
		return
	end
	self._twist = value
	write(self)
end

-- Scale and twist in one call.
function DeformerClass.set(self: Deformer, S: Vector3, angle: number)
	self._scale = clampScale(S, self._scaleMax)
	self._twist = if angle == angle then angle else 0
	write(self)
end

-- One SquishRig frame in one pass: scale, twist, face, blink, cheek and (while out.sectionsOn) the section angles.
function DeformerClass.apply(self: Deformer, out: SquishRig.Out)
	if self._destroyed then
		return
	end
	self._scale = clampScale(out.S, self._scaleMax)
	self._twist = if out.twist == out.twist then out.twist else 0
	self._blink = if out.blink == out.blink then out.blink else 1
	self._cheek = if out.cheek == out.cheek then out.cheek else 1
	setFaceState(self, out.face, false)
	setSectionsState(self, if out.sectionsOn then out.sections else nil)
	write(self)
end

-- Shows the face set of `state` ("normal", "squish", "wow"); force re-applies every look part's Transparency.
function DeformerClass.setFace(self: Deformer, state: Face, force: boolean?)
	if self._destroyed then
		return
	end
	setFaceState(self, state, force == true)
	write(self)
end

function DeformerClass.getFace(self: Deformer): Face
	return self._face
end

-- Section angles (radians) by slot, in sectionNames() order; nil turns the section path off.
function DeformerClass.setSections(self: Deformer, angles: { number }?)
	if self._destroyed then
		return
	end
	setSectionsState(self, angles)
	write(self)
end

-- The section slot names (SquishRig.sectionNames order; empty for a model without sections).
function DeformerClass.sectionNames(self: Deformer): { string }
	return table.clone(self._sectionNames)
end

function DeformerClass.getScale(self: Deformer): Vector3
	return self._scale
end

function DeformerClass.getTwist(self: Deformer): number
	return self._twist
end

-- New un-twisted CFrame for the twist target (Weld.C1, model pivot or Root CFrame), e.g. after the owner's idle bob or
-- turntable moved the model. Writes it at once (with the current twist), or, with deferWrite, on the next
-- set/setScale/setTwist/rest call (one write per frame when the owner sets both).
function DeformerClass.setTwistBase(self: Deformer, base: CFrame, deferWrite: boolean?)
	if self._destroyed or self._twistTarget == nil then
		return
	end
	self._twistBase = base
	if deferWrite then
		self._twistDirty = true
		return
	end
	writeTwist(self, if self._twistAtBase then 0 else self._twist)
	self._twistDirty = false
end

-- Back to S = (1, 1, 1), no twist, the normal face, looks at 1 and the sections at their base: base values written
-- once (nothing if already resting).
function DeformerClass.rest(self: Deformer)
	if self._destroyed then
		return
	end
	self._scale = Vector3.one
	self._twist = 0
	self._blink, self._cheek = 1, 1
	setFaceState(self, "normal", false)
	setSectionsState(self, nil)
	write(self)
end

-- True when every value is at its base (nothing is being written).
function DeformerClass.isResting(self: Deformer): boolean
	return self._meshAtBase and self._twistAtBase and self._face == "normal"
end

-- Number of parts the deformer drives (meshes, rounded boxes and solid parts; never the Root).
function DeformerClass.partCount(self: Deformer): number
	return #self._parts
end

-- Rests the model and forgets it. Safe to call more than once.
function DeformerClass.destroy(self: Deformer)
	if self._destroyed then
		return
	end
	self:rest()
	self._destroyed = true
	if registry[self.model] == self then
		registry[self.model] = nil
	end
	table.clear(self._parts)
end

-- Public

-- Attaches to a built model (see the header). Returns the existing deformer if the model is already attached.
function SquishDeformer.attach(model: Model, options: Options?): Deformer
	assert(typeof(model) == "Instance" and model:IsA("Model"), "[SD][SquishDeformer] attach needs a Model")
	local existing = registry[model]
	if existing then
		return existing
	end
	local opts: Options = options or {}
	local twistTarget: TwistTarget? = opts.twist
	local twistBase = CFrame.identity
	local weld: Weld? = nil
	local root: BasePart? = nil
	if twistTarget == "weld" then
		weld = opts.weld
		assert(weld and weld:IsA("Weld"), '[SD][SquishDeformer] twist = "weld" needs options.weld')
		twistBase = (weld :: Weld).C1
	elseif twistTarget == "pivot" then
		twistBase = model:GetPivot()
	elseif twistTarget == "root" then
		root = model.PrimaryPart
		assert(root, '[SD][SquishDeformer] twist = "root" needs model.PrimaryPart')
		twistBase = (root :: BasePart).CFrame
	elseif twistTarget ~= nil then
		error(`[SD][SquishDeformer] unknown twist target {tostring(twistTarget)}`, 2)
	end
	local modelPivot = model:GetPivot()
	local customPivot = opts.pivot
	assert(customPivot == nil or typeof(customPivot) == "CFrame", "[SD][SquishDeformer] options.pivot must be a CFrame")
	local scaleMax = opts.scaleMax or SCALE_MAX
	assert(
		type(scaleMax) == "number" and scaleMax >= SCALE_MAX,
		"[SD][SquishDeformer] options.scaleMax must be a number >= Config.Anim.deform.scaleMax"
	)
	local pivot = if customPivot then customPivot else modelPivot
	local sectionNames, sections = collectSections(model, pivot, opts.sections)
	local slotOf: { [string]: number } = {}
	for index, name in sectionNames do
		slotOf[name] = index
	end
	local parts = collectParts(model, pivot, opts.includePrimary == true, slotOf)
	local freeSolids, freeSections = false, false
	local lookParts: { PartData } = {}
	for _, part in parts do
		if part.solid and part.weld == nil then
			freeSolids = true
		end
		if part.slot and part.weld == nil then
			freeSections = true
		end
		if part.look then
			table.insert(lookParts, part)
		end
	end
	local data: DeformerData = {
		model = model,
		_parts = parts,
		_pivot = pivot,
		_pivotOffset = if customPivot then modelPivot:ToObjectSpace(customPivot) else nil,
		_freeSolids = freeSolids,
		_scale = Vector3.one,
		_scaleMax = scaleMax,
		_twist = 0,
		_meshAtBase = true,
		_twistAtBase = true,
		_twistTarget = opts.twist,
		_twistAxis = axisVector(opts.twistAxis),
		_twistBase = twistBase,
		_twistDirty = false,
		_weld = weld,
		_root = root,
		_destroyed = false,
		_face = "normal",
		_blink = 1,
		_cheek = 1,
		_lookParts = lookParts,
		_eyeMul = Vector3.one,
		_shineMul = Vector3.one,
		_cheekMul = Vector3.one,
		_mouthOpenMul = Vector3.one,
		_squishMouthMul = Vector3.one,
		_sections = sections,
		_sectionNames = sectionNames,
		_angles = table.create(#sections, 0),
		_sectionsOn = false,
		_freeSections = freeSections,
	}
	local deformer = setmetatable(data, DeformerClass)
	registry[model] = deformer
	return deformer
end

-- The deformer attached to `model`, if any.
function SquishDeformer.get(model: Model): Deformer?
	return registry[model]
end

-- S with `c` on the squeeze axis and `w` on the other two (e.g. the squeeze timeline's c/w), clamped.
function SquishDeformer.axisScale(c: number, w: number, axis: Axis?): Vector3
	local which: Axis = if axis then axis else "Y"
	axisVector(which) -- validates
	local S = if which == "X"
		then Vector3.new(c, w, w)
		elseif which == "Y" then Vector3.new(w, c, w)
		else Vector3.new(w, w, c)
	return clampScale(S)
end

-- Volume-preserving squash: c = 1 - a on the axis, w = 1/√c on the others. a is clamped to
-- [1 - scaleMax, maxSquash] (a < 0 stretches along the axis).
function SquishDeformer.squash(a: number, axis: Axis?): Vector3
	local amount = if a == a then math.clamp(a, 1 - SCALE_MAX, MAX_SQUASH) else 0
	local c = 1 - amount
	return SquishDeformer.axisScale(c, 1 / math.sqrt(c), axis)
end

-- Clamps every axis of S to [scaleMin, scaleMax] (NaN → 1).
function SquishDeformer.clampScale(S: Vector3): Vector3
	return clampScale(S)
end

return SquishDeformer
