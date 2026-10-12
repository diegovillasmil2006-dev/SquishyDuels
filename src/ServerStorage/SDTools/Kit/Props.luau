--!strict
-- Props: the Claude Design lobby's world kit (design package sd/lobby.js:6-70, "shared world kit") as Roblox parts, for
-- the edit-time lobby generator (phase 3, user decision 2026-10-11 "build the design's lobby"). Server only, Edit mode
-- only (ServerStorage.SDTools); runtime code never requires it. Requires Kit/Prims (relative).
-- Every constructor builds UNPARENTED unless a parent is given and returns what it made. Colours are Color3 values the
-- caller resolves from Art/Palette; sizes and positions are studs (the design's units: STUD scales them back).
-- Flags are the Kit/Prims presets; a part is "decor" unless the caller asks for "solid".
--
-- Design primitive -> Roblox (Roblox has no torus, cone or superellipsoid primitive; phase 3 spec B.0):
--   rb(w, h, d, n)  lobby.js:10  a superellipsoid box. Its exponent rises to 10 (aspect > 5) or 14 (aspect > 12); from
--                                10 up it is a plain Block, below that a clone of the shape library's RoundedBox
--                                (ReplicatedStorage.SD_ShapeLibrary; CollisionFidelity Box, so a solid one collides as
--                                its block). Without the library it is a Block (the caller warns once).
--   C(r0, r1, h)    lobby.js:13  an upright Cylinder of the bottom diameter 2·r1 (cylinder(): the axis is the frame's Y)
--   SPH(r)          lobby.js:14  a Ball part (ball())
--   pill, superF    lobby.js:11  an ellipsoid of the same size (a Sphere SpecialMesh: ellipsoid())
--   TOR(R, t)       lobby.js:15  around a solid core, a collar (cylinder() 2·(R + t) wide, the caller puts its top flush
--                                with the core's); on a surface, an annulus(); a free arc (the lock's shackle), rods()
--   flat ring       lobby.js:22  annulus(): a disc with a disc of the ground's colour on it
--   GUM             lobby.js:23  gumdrop(): an ellipsoid as wide as the gumdrop's foot, its lower half hidden in what it
--                                stands on (reading: the lathe profile has no Roblox shape)
--   ConeGeometry    (lobby.js:387, 391, 392)  cone(): a pointed ellipsoid (reading)
-- Composite props: lollipop() (lobby.js:40-47), cottonTree() (48-51), lockIcon() (52-58), checkIcon() (59-64),
-- ropeLine() (65-70) and arrow() (the wayfinding arrow board, 162-164).

local Prims = require(script.Parent.Prims)

-- Types

export type Flags = Prims.Flags

export type LollipopColors = {
	stick: Color3, -- the stick and the disk (the design's white)
	a: Color3, -- swirl rings 1 and 3 (ca)
	b: Color3, -- swirl rings 2 and 4 (cb)
}

-- Constants

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder part's X axis onto the frame's Y axis
local ROD_OVERLAP = 1.06 -- rods of a ring overlap a little so its joints never gap
local SWIRL_RADII = { 0.9, 0.7, 0.5, 0.3 } -- design: lobby.js:45 (ring radius / disk radius)
local SWIRL_TUBE = 0.07 -- design: lobby.js:45 (tube / disk radius)
local DISC_STEP = 0.02 -- each swirl disc stands this far proud of the one under it (no z-fighting)
local GUMDROP_RADIUS = 3.1 -- design: lobby.js:23 (the lathe's widest radius)
local GUMDROP_HEIGHT = 6 -- design: lobby.js:23
local ARROW_TAIL = -0.4 -- design: lobby.js:162 (the arrow shape: x -0.4 .. 5.4, tip to 6.6, y ±0.75)
local ARROW_NECK = 5.4
local ARROW_TIP = 6.6
local ARROW_HALF_HEIGHT = 0.75
local ARROW_DEPTH = 0.35 -- design: lobby.js:163 (extrude depth; the 0.12 bevel is left out)

-- Module table

local Props = {}
Props.GUMDROP_HEIGHT = GUMDROP_HEIGHT

-- Private

-- The exponent rb() ends up with (lobby.js:10).
local function exponent(size: Vector3, n: number): number
	local largest = math.max(size.X, size.Y, size.Z)
	local smallest = math.min(size.X, size.Y, size.Z)
	local aspect = largest / math.max(smallest, 1e-6)
	if aspect > 5 then
		return math.max(n, if aspect > 12 then 14 else 10)
	end
	return n
end

local function setSolid(part: BasePart)
	part.CanCollide = true
	part.CanQuery = true
end

-- Public: primitives

-- Whether rb(size, n) is a plain Block (its superellipse exponent reaches 10, lobby.js:10).
function Props.isBlock(size: Vector3, n: number?): boolean
	return exponent(size, n or 6) >= 10
end

-- A design rounded box (rb): see the header. Returns the part and whether the RoundedBox look was wanted but the
-- template was missing (the caller warns once).
function Props.rb(
	template: BasePart?,
	parent: Instance?,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	flags: Flags?,
	n: number?
): (BasePart, boolean)
	local wanted: Flags = flags or "decor"
	if Props.isBlock(size, n) or template == nil then
		local part = Prims.part({
			name = name,
			size = size,
			cframe = cframe,
			color = color,
			flags = wanted,
			parent = parent,
		})
		return part, template == nil and not Props.isBlock(size, n)
	end
	local part, fallback = Prims.roundedBox(template, name, size, cframe, color, parent)
	if wanted == "solid" then
		setSolid(part)
	end
	return part, fallback
end

-- A Cylinder of `diameter` and `height` centred on `frame`, its axis along the frame's Y axis.
function Props.cylinder(
	parent: Instance?,
	name: string,
	diameter: number,
	height: number,
	frame: CFrame,
	color: Color3,
	flags: Flags?
): Part
	return Prims.part({
		name = name,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter),
		cframe = frame * UPRIGHT,
		color = color,
		flags = flags or "decor",
		parent = parent,
	})
end

-- A Ball of `diameter` at `position`.
function Props.ball(
	parent: Instance?,
	name: string,
	diameter: number,
	position: Vector3,
	color: Color3,
	flags: Flags?
): Part
	return Prims.part({
		name = name,
		shape = Enum.PartType.Ball,
		size = Vector3.one * diameter,
		cframe = CFrame.new(position),
		color = color,
		flags = flags or "decor",
		parent = parent,
	})
end

-- An ellipsoid (Sphere SpecialMesh) of `size` at `cframe`.
function Props.ellipsoid(
	parent: Instance?,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	flags: Flags?
): Part
	return Prims.meshPart(name, Enum.MeshType.Sphere, size, cframe, color, flags or "decor", parent)
end

-- A cone (radius, height) centred on `frame` with its tip along the frame's +Y: a pointed ellipsoid (reading).
function Props.cone(parent: Instance?, name: string, radius: number, height: number, frame: CFrame, color: Color3): Part
	return Props.ellipsoid(parent, name, Vector3.new(2 * radius, height, 2 * radius), frame, color)
end

-- A flat ring (inner .. outer diameter) whose top is `top` (its axis the frame's Y): a disc of `color` `thickness` tall
-- with a disc of `ground` (the surface's colour) on it, a hair higher. Returns the ring and the cover.
function Props.annulus(
	parent: Instance?,
	name: string,
	innerDiameter: number,
	outerDiameter: number,
	top: CFrame,
	thickness: number,
	color: Color3,
	ground: Color3
): (Part, Part)
	local ring = Props.cylinder(parent, name, outerDiameter, thickness, top * CFrame.new(0, -thickness / 2, 0), color)
	local cover = Props.cylinder(
		parent,
		name .. "_cover",
		innerDiameter,
		thickness,
		top * CFrame.new(0, -thickness / 2 + 0.005, 0),
		ground
	)
	return ring, cover
end

-- An arc of a ring of `radius` and tube `tube` in the frame's XY plane around its Z axis (the design's TorusGeometry
-- lies the same way), from angle 0 (+X) toward +Y over `arc` radians, as `segments` overlapping rods.
function Props.rods(
	parent: Instance?,
	name: string,
	radius: number,
	tube: number,
	frame: CFrame,
	color: Color3,
	segments: number,
	arc: number?
): { Part }
	local sweep = arc or 2 * math.pi
	local step = sweep / segments
	local length = 2 * radius * math.sin(step / 2) * ROD_OVERLAP
	local list: { Part } = {}
	for index = 0, segments - 1 do
		local angle = (index + 0.5) * step
		table.insert(
			list,
			Prims.part({
				name = name,
				shape = Enum.PartType.Cylinder,
				size = Vector3.new(length, 2 * tube, 2 * tube),
				-- The rod's X axis along the tangent (-sin, cos) of the arc at its middle.
				cframe = frame
					* CFrame.new(radius * math.cos(angle), radius * math.sin(angle), 0)
					* CFrame.Angles(0, 0, angle + math.pi / 2),
				color = color,
				flags = "decor",
				parent = parent,
			})
		)
	end
	return list
end

-- A gumdrop (lobby.js:23) of `scale` whose foot centre is `base` (its axis the frame's Y): an ellipsoid as wide as the
-- gumdrop's foot and twice its height, centred on the foot, so its upper half is the gumdrop (reading).
function Props.gumdrop(parent: Instance?, name: string, base: CFrame, scale: number, color: Color3): Part
	local size = Vector3.new(2 * GUMDROP_RADIUS, 2 * GUMDROP_HEIGHT, 2 * GUMDROP_RADIUS) * scale
	return Props.ellipsoid(parent, name, size, base, color)
end

-- Public: composite props

-- A corner lollipop (lobby.js:40-47) whose stick stands on `foot`: stick C(0.09 r) `height` tall, a disk of radius `r`
-- 0.25 r thick facing ±Z at the stick's top, and on each face the four swirl rings (lobby.js:45) as concentric discs,
-- each ring between two disk-coloured discs (reading: no torus). A Model with WorldPivot at the foot.
function Props.lollipop(
	parent: Instance?,
	name: string,
	foot: Vector3,
	height: number,
	r: number,
	colors: LollipopColors
): Model
	local model = Prims.model(name, nil, false, CFrame.new(foot))
	Props.cylinder(
		model,
		"lollipop_stick",
		2 * 0.09 * r,
		height,
		CFrame.new(foot + Vector3.new(0, height / 2, 0)),
		colors.stick
	)
	local center = CFrame.new(foot + Vector3.new(0, height, 0))
	local disk = center * CFrame.Angles(math.pi / 2, 0, 0) -- design: lobby.js:43 (the candy turned π/2 about X: faces ±Z)
	Props.cylinder(model, "lollipop_disk", 2 * r, 0.25 * r, disk, colors.stick)
	for _, side in { 1, -1 } do
		local depth = 0.125 * r -- the disk's face
		for index, k in SWIRL_RADII do
			local ring = if index % 2 == 0 then colors.b else colors.a
			for _, entry in { { k + SWIRL_TUBE, ring }, { k - SWIRL_TUBE, colors.stick } } :: { { any } } do
				depth += DISC_STEP
				Props.cylinder(
					model,
					"lollipop_swirl",
					2 * entry[1] * r,
					DISC_STEP,
					center * CFrame.new(0, 0, side * (depth - DISC_STEP / 2)) * CFrame.Angles(math.pi / 2, 0, 0),
					entry[2]
				)
			end
		end
	end
	if parent then
		model.Parent = parent
	end
	return model
end

-- A cotton-candy tree (lobby.js:48-51) of scale `k` standing on `foot`: a candy stick C(0.45k, 0.6k, 9k) and four
-- fluff pills (ellipsoids). A Model with WorldPivot at the foot.
function Props.cottonTree(
	parent: Instance?,
	name: string,
	foot: Vector3,
	k: number,
	stick: Color3,
	fluff: Color3
): Model
	local model = Prims.model(name, nil, false, CFrame.new(foot))
	Props.cylinder(model, "kit_cotton_tree_stick", 1.2 * k, 9 * k, CFrame.new(foot + Vector3.new(0, 4.5 * k, 0)), stick)
	for _, puff in { { 0, 11, 0, 4.6 }, { 2.4, 9.4, 1.2, 3.2 }, { -2.2, 9.8, -1, 3.4 }, { 0.6, 13.6, -0.8, 3 } } do
		local r0 = puff[4]
		Props.ellipsoid(
			model,
			"kit_cotton_tree_fluff",
			Vector3.new(2 * r0 * k, 1.7 * r0 * k, 2 * r0 * k),
			CFrame.new(foot + Vector3.new(puff[1] * k, puff[2] * k, puff[3] * k)),
			fluff
		)
	end
	if parent then
		model.Parent = parent
	end
	return model
end

-- The lock icon (lobby.js:52-58) at `frame` (its front is the frame's +Z), scale `k`: a half-ring shackle, the body
-- rb(3k, 2.4k, 1.2k) and the keyhole dot. Parts go into `parent` (decor).
function Props.lockIcon(template: BasePart?, parent: Instance, frame: CFrame, k: number, gold: Color3, dark: Color3)
	Props.rods(parent, "lock_shackle", 1.1 * k, 0.32 * k, frame * CFrame.new(0, 1.2 * k, 0), gold, 4, math.pi)
	Props.rb(template, parent, "lock_body", Vector3.new(3 * k, 2.4 * k, 1.2 * k), frame, gold, "decor", 6)
	Props.cylinder(
		parent,
		"lock_keyhole_dot",
		0.64 * k,
		0.3,
		frame * CFrame.new(0, 0.2 * k, 0.6 * k) * CFrame.Angles(math.pi / 2, 0, 0),
		dark
	)
end

-- The check icon (lobby.js:59-64) at `frame`, scale `k`: two rounded strokes. Parts go into `parent` (decor).
function Props.checkIcon(template: BasePart?, parent: Instance, frame: CFrame, k: number, mint: Color3)
	Props.rb(
		template,
		parent,
		"check_stroke",
		Vector3.new(1.2 * k, 2.6 * k, 0.8),
		frame * CFrame.new(-0.7 * k, -0.2 * k, 0) * CFrame.Angles(0, 0, 0.75),
		mint,
		"decor",
		6
	)
	Props.rb(
		template,
		parent,
		"check_stroke",
		Vector3.new(1.2 * k, 4.4 * k, 0.8),
		frame * CFrame.new(0.7 * k, 0.5 * k, 0) * CFrame.Angles(0, 0, -0.6),
		mint,
		"decor",
		6
	)
end

-- A rope barrier (lobby.js:65-70) through the floor points `points` ({x, z} in `frame`), posts `height` tall: gold
-- posts C(0.32, 0.4, h) with ball caps and velvet ropes rb(L, 0.5, 0.5) 0.6 below the post tops. Parts go into
-- `parent` (decor).
function Props.ropeLine(
	template: BasePart?,
	parent: Instance,
	frame: CFrame,
	points: { { number } },
	height: number,
	gold: Color3,
	velvet: Color3
)
	for _, point in points do
		Props.cylinder(parent, "rope_post", 0.8, height, frame * CFrame.new(point[1], height / 2, point[2]), gold)
		Props.ball(parent, "rope_post_cap", 1.1, (frame * CFrame.new(point[1], height + 0.3, point[2])).Position, gold)
	end
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local length = math.sqrt(dx * dx + dz * dz)
		Props.rb(
			template,
			parent,
			"rope",
			Vector3.new(length, 0.5, 0.5),
			frame
				* CFrame.new((a[1] + b[1]) / 2, height - 0.6, (a[2] + b[2]) / 2)
				* CFrame.Angles(0, -math.atan2(dz, dx), 0),
			velvet,
			"decor",
			4
		)
	end
end

-- A wayfinding arrow board (lobby.js:162-164) in the arm frame `frame` (its +X points at the destination): the shaft
-- from x -0.4 to 5.4 and a two-wedge tip to 6.6, 1.5 tall, 0.35 thick. Parts go into `parent` (decor).
function Props.arrow(parent: Instance, frame: CFrame, color: Color3)
	local shaft = ARROW_NECK - ARROW_TAIL
	Prims.part({
		name = "wayfinding_arrow_board",
		size = Vector3.new(shaft, 2 * ARROW_HALF_HEIGHT, ARROW_DEPTH),
		cframe = frame * CFrame.new(ARROW_TAIL + shaft / 2, 0, 0),
		color = color,
		flags = "decor",
		parent = parent,
	})
	-- Each half of the tip is a WedgePart: its right angle at the neck's middle, one leg along +X to the tip, the other
	-- along ±Y to the shaft's edge (a wedge's slope runs from its front bottom edge to its back top edge).
	local tip = ARROW_TIP - ARROW_NECK
	local centerX = (ARROW_NECK + ARROW_TIP) / 2
	for _, side in { 1, -1 } do
		Prims.wedge(
			"wayfinding_arrow_board",
			Vector3.new(ARROW_DEPTH, ARROW_HALF_HEIGHT, tip),
			frame
				* CFrame.fromMatrix(
					Vector3.new(centerX, side * ARROW_HALF_HEIGHT / 2, 0),
					Vector3.new(0, 0, side),
					Vector3.new(0, side, 0)
				),
			color,
			"decor",
			parent
		)
	end
end

return Props
