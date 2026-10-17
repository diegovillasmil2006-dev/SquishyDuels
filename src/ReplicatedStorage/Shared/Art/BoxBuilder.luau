--!strict
-- BoxBuilder (shared; the client builds with it). UI FINAL R7 (plan work/ui/PLAN.md R7 G7.9; `stage:n` = Diego's
-- uploads/box-stage.html line n): builds the box reveal's three box models from their blueprints (Art/BoxSoft = the
-- Snack box, Art/BoxSweet, Art/BoxRoyal = the Treat box) and poses them every frame for UI/BoxReveal.
--   local built = BoxBuilder.build(BoxBuilder.blueprint("snack"), sceneScale)   -- a Model of anchored parts
--   BoxBuilder.write(built, rootCFrame, squash, motion)   -- poses every part: motion = { [node]: CFrame } (the hinge's
--                                                         -- swing, an ear's flick, the crown's turn, ...)
-- A blueprint is data in the design's units (one unit = `scale` studs): `nodes` (the design's groups: base, hinge,
-- lid, ears, crown, ...; each at `pos` in its parent, turned `rot`), `order` (every node after its parent) and
-- `parts`, each on a node at `pos` / `rot` (radians, CFrame.Angles order = three.js's XYZ Euler) with a shape:
--   Block, Ball (size.X), Ellipsoid (a Block with a Sphere SpecialMesh: any three radii), Cylinder (size = diameter,
--   height, diameter, standing on Y), Tri (an isosceles triangle w x h, t thick: SquishyBuilder's two wedge halves)
-- and a Palette colour (`color`), an optional `transparency` and `material` (an Enum.Material name).
-- Roblox limits, stated (G7.9): no rounded boxes, cones, tori, canvas textures or back-face ink hulls; each is the
-- nearest primitive (see each blueprint's header). The models are the reveal's fallback until the user imports the
-- Blender meshes named after the nodes (plan G7.9).
-- write() keeps the squash exact for parts turned with the box and close for the others: a part's size follows the
-- squash along its own axes (|R x squash| per axis). Sizes are written only when the squash changes.
-- Pure (unit-tested): blueprint(boxId), nodeFrames(blueprint, scale, motion), partCount(blueprint), nodeOf(part).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Palette = require(ReplicatedStorage.Shared.Art.Palette)

-- Types

export type Shape = "Block" | "Ball" | "Ellipsoid" | "Cylinder" | "Tri"
export type BoxNode = { parent: string?, pos: Vector3, rot: Vector3? }
export type BoxPart = {
	name: string,
	node: string,
	shape: Shape,
	size: Vector3, -- Tri: (w, h, t)
	pos: Vector3?,
	rot: Vector3?,
	color: string, -- an Art/Palette name
	transparency: number?,
	material: string?,
}
export type BoxBlueprint = {
	kind: "soft" | "sweet" | "royal",
	nodes: { [string]: BoxNode },
	order: { string },
	parts: { BoxPart },
	top: number, -- the seam's height (stage:126, 155, 186): the inner light, the sparkles and the burst rise from it
	light: string, -- the inner light's Palette colour
	beam: string, -- the beam's and the floor wave's
	sparkles: { string }, -- the sparkles' colours
}
type Placed = {
	part: BasePart,
	node: string,
	rest: CFrame, -- in its node's frame, the scale applied
	size: Vector3,
}
export type Built = {
	model: Model,
	blueprint: BoxBlueprint,
	scale: number,
	placed: { Placed },
	named: { [string]: BasePart },
	lastSquash: Vector3?,
}

-- Constants

local CYLINDER_FIX = CFrame.Angles(0, 0, math.pi / 2) -- a Roblox cylinder lies on X; the blueprints stand it on Y
local TRI_HALF_YAW = math.rad(90) -- SquishyBuilder's TRI_HALF_YAW_DEG: the two halves make a "Λ"
local SQUASH_EPSILON = 1e-4
local MODELS = { snack = "BoxSoft", sweet = "BoxSweet", treat = "BoxRoyal" } :: { [string]: string }

-- Module table

local BoxBuilder = {}

-- Private

local function angles(rot: Vector3?): CFrame
	return if rot then CFrame.Angles(rot.X, rot.Y, rot.Z) else CFrame.identity
end

local function newPart(
	className: string,
	name: string,
	color: string,
	transparency: number?,
	material: string?
): BasePart
	local part = Instance.new(className) :: BasePart
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	local tone = (Palette :: any)[color]
	part.Color = if typeof(tone) == "Color3" then tone else Color3.new(1, 1, 1)
	part.Transparency = transparency or 0
	local ok, enum = pcall(function(): Enum.Material
		return (Enum.Material :: any)[material or "SmoothPlastic"]
	end)
	part.Material = if ok and enum then enum else Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Public: pure

-- The blueprint of a box id (snack -> BoxSoft, sweet -> BoxSweet, treat -> BoxRoyal); nil for anything else.
function BoxBuilder.blueprint(boxId: string): BoxBlueprint?
	local name = MODELS[boxId]
	if name == nil then
		return nil
	end
	local module = script.Parent:FindFirstChild(name)
	return if module and module:IsA("ModuleScript") then (require(module) :: any) :: BoxBlueprint else nil
end

-- Every node's frame (model space, studs) at `scale`, with each node's `motion` applied after its own rest turn.
function BoxBuilder.nodeFrames(bp: BoxBlueprint, scale: number, motion: { [string]: CFrame }?): { [string]: CFrame }
	local frames: { [string]: CFrame } = {}
	local moves = motion or {}
	for _, name in bp.order do
		local node = bp.nodes[name]
		local parent = if node.parent then frames[node.parent] else nil
		frames[name] = (parent or CFrame.identity)
			* CFrame.new(node.pos * scale)
			* angles(node.rot)
			* (moves[name] or CFrame.identity)
	end
	return frames
end

-- The number of parts a blueprint builds (a Tri is two).
function BoxBuilder.partCount(bp: BoxBlueprint): number
	local n = 0
	for _, spec in bp.parts do
		n += if spec.shape == "Tri" then 2 else 1
	end
	return n
end

-- The node a built part is on (its SD_BoxNode attribute), or nil.
function BoxBuilder.nodeOf(part: Instance): string?
	local node = part:GetAttribute("SD_BoxNode")
	return if type(node) == "string" then node else nil
end

-- Public: build and pose

-- A Model of the blueprint's parts at `scale` studs per unit, posed at rest (root at the origin).
function BoxBuilder.build(bp: BoxBlueprint, scale: number): Built
	local s = if scale > 0 then scale else 1
	local model = Instance.new("Model")
	model.Name = "SD_Box_" .. bp.kind
	local placed: { Placed } = {}
	local named: { [string]: BasePart } = {}
	local function add(part: BasePart, spec: BoxPart, rest: CFrame, size: Vector3)
		part:SetAttribute("SD_BoxNode", spec.node)
		part.Size = size
		part.Parent = model
		table.insert(placed, { part = part, node = spec.node, rest = rest, size = size })
	end
	for _, spec in bp.parts do
		local at = CFrame.new((spec.pos or Vector3.zero) * s) * angles(spec.rot)
		local size = spec.size * s
		if spec.shape == "Tri" then
			local half = Vector3.new(size.Z, size.Y, size.X / 2)
			for side, x in { -size.X / 4, size.X / 4 } do
				local yaw = if side == 1 then TRI_HALF_YAW else -TRI_HALF_YAW
				local wedge = newPart("WedgePart", spec.name .. (if side == 1 then "_HalfL" else "_HalfR"), spec.color)
				add(wedge, spec, at * CFrame.new(x, 0, 0) * CFrame.Angles(0, yaw, 0), half)
			end
		else
			local part = newPart("Part", spec.name, spec.color, spec.transparency, spec.material)
			local rest = at
			local dims = size
			if spec.shape == "Ball" then
				(part :: Part).Shape = Enum.PartType.Ball
				dims = Vector3.new(size.X, size.X, size.X)
			elseif spec.shape == "Cylinder" then
				(part :: Part).Shape = Enum.PartType.Cylinder
				rest = at * CYLINDER_FIX
				dims = Vector3.new(size.Y, size.X, size.Z)
			elseif spec.shape == "Ellipsoid" then
				local mesh = Instance.new("SpecialMesh")
				mesh.Name = "Mesh"
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = part
			end
			add(part, spec, rest, dims)
			named[spec.name] = part
		end
	end
	local built: Built = { model = model, blueprint = bp, scale = s, placed = placed, named = named, lastSquash = nil }
	BoxBuilder.write(built, CFrame.identity, Vector3.one, nil)
	return built
end

-- Poses the model: every node at its rest with `motion` on it, the whole squashed by `squash` (x, y, z) about the
-- root's origin (the floor point under the box) and placed at `root`.
function BoxBuilder.write(built: Built, root: CFrame, squash: Vector3, motion: { [string]: CFrame }?)
	local frames = BoxBuilder.nodeFrames(built.blueprint, built.scale, motion)
	local last = built.lastSquash
	local resize = last == nil or (last - squash).Magnitude > SQUASH_EPSILON
	for _, entry in built.placed do
		local cf = (frames[entry.node] or CFrame.identity) * entry.rest
		local rotation = cf.Rotation
		entry.part.CFrame = root * CFrame.new(cf.Position * squash) * rotation
		if resize then
			entry.part.Size = entry.size
				* Vector3.new(
					(rotation.XVector * squash).Magnitude,
					(rotation.YVector * squash).Magnitude,
					(rotation.ZVector * squash).Magnitude
				)
		end
	end
	if resize then
		built.lastSquash = squash
	end
end

return BoxBuilder
