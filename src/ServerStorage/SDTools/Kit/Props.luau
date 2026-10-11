--!strict
-- Props: the few simple placeholder props of the lobby (DESIGN §7.7 "Props"): perimeter shelves as plain blocks,
-- giant lollipops, toy-block stacks and the gumdrop hedge. Server only, Edit mode only (ServerStorage.SDTools).
-- Requires Kit/Prims (relative). Positions and sizes come from the caller (WorldLayout); colours from the caller
-- (Art/Palette). No text, prompts or scripts.
-- Art scope (user decision, Part 3): functional placeholder shapes with modest decor; the team adds its own decor in
-- Workspace.SD_Manual, which generators never touch. Each prop is its own Model with plain names so its look can be
-- replaced later.
-- Rules kept here (§7.7): decor taller than 3 studs is CanCollide/CanQuery false (rule 2); nothing Neon (rule 4); the
-- shelf body is a solid wall taller than a jump (16 vs 7.2) and everything on its face is flush or non-colliding, so no
-- ledge can be stood on; a toy-block stack collides only with its bottom block.

local Prims = require(script.Parent.Prims)

-- Types

export type ShelfStyle = {
	body: Color3, -- Cocoa
	panels: { Color3 }, -- pastel back panels, cycled per unit
	awnings: { Color3 }, -- awning stripes, cycled per unit
	candy: { Color3 }?, -- candy ball colours; nil or empty = none on this run
}

export type LollipopSpec = {
	stickDiameter: number,
	stickHeight: number,
	headDiameter: number,
	headThickness: number,
}

export type LollipopStyle = {
	stick: Color3,
	head: Color3,
	swirl: Color3,
}

-- Constants

local PANEL_INSET = 0.6 -- per side
local PANEL_BOTTOM = 1.5
local PANEL_TOP_GAP = 1.5
local PANEL_PROUD = 0.05 -- how far the back panel stands out of the shelf face
local BOARD_FRACTIONS = { 0.34, 0.66 } -- shelf boards at these fractions of the height
local BOARD_HEIGHT = 0.4
local BOARD_PROUD = 0.1
local AWNING_THICKNESS = 0.2
local AWNING_OVERHANG = 1 -- past the shelf face, over the plaza
local CANDY_DIAMETER = 1.6
local CANDY_PER_UNIT = 3
local SWIRL_RATIO = 0.56 -- swirl diameter / head diameter
local SWIRL_EXTRA_THICKNESS = 0.1 -- the swirl stands out of both head faces
local TOY_BLOCK_SHRINK = 0.85 -- each block above is this much smaller ...
local TOY_BLOCK_TWIST_DEG = 25 -- ... and turned this much

-- Module table

local Props = {}

-- Private

local function pick(list: { Color3 }, index: number): Color3
	return list[(index - 1) % #list + 1]
end

-- One shelf unit of `size` (W × H × D). `frame`: centre of the unit's footprint at floor level, LookVector = toward
-- the plaza. `awningY` = { low, high }.
local function shelfUnit(
	parent: Instance,
	name: string,
	frame: CFrame,
	size: Vector3,
	awningY: { number },
	style: ShelfStyle,
	index: number
)
	local width, height, depth = size.X, size.Y, size.Z
	local unit = Prims.model(name, parent, false, frame)
	local face = -depth / 2 -- the plaza-side face, in local Z (front = -Z)
	local inner = width - 2 * PANEL_INSET
	Prims.part({
		name = "Body",
		size = size,
		cframe = frame * CFrame.new(0, height / 2, 0),
		color = style.body,
		material = Enum.Material.WoodPlanks,
		flags = "solid",
		parent = unit,
	})
	local panelHeight = height - PANEL_BOTTOM - PANEL_TOP_GAP
	Prims.part({
		name = "BackPanel",
		size = Vector3.new(inner, panelHeight, 0.2),
		cframe = frame * CFrame.new(0, PANEL_BOTTOM + panelHeight / 2, face + 0.1 - PANEL_PROUD),
		color = pick(style.panels, index),
		flags = "decor",
		parent = unit,
	})
	for boardIndex, fraction in BOARD_FRACTIONS do
		Prims.part({
			name = "Board" .. boardIndex,
			size = Vector3.new(inner, BOARD_HEIGHT, 0.4),
			cframe = frame * CFrame.new(0, height * fraction, face + 0.2 - BOARD_PROUD),
			color = style.body,
			material = Enum.Material.Wood,
			flags = "decor",
			parent = unit,
		})
	end
	-- Awning: a thin Fabric sheet from the back top edge (awningY high) down to just past the face (awningY low).
	local back = Vector3.new(0, awningY[2], depth / 2)
	local front = Vector3.new(0, awningY[1], face - AWNING_OVERHANG)
	local span = front - back
	local slope = math.atan2(-span.Y, -span.Z) -- tilt about local X so the sheet runs from back to front
	Prims.part({
		name = "Awning",
		size = Vector3.new(width, AWNING_THICKNESS, span.Magnitude),
		cframe = frame * CFrame.new((back + front) / 2) * CFrame.Angles(-slope, 0, 0),
		color = pick(style.awnings, index),
		material = Enum.Material.Fabric,
		flags = "decor",
		parent = unit,
	})
	local candy = style.candy
	if candy and #candy > 0 then
		local spacing = inner / CANDY_PER_UNIT
		local boardTop = height * BOARD_FRACTIONS[1] + BOARD_HEIGHT / 2
		for ball = 1, CANDY_PER_UNIT do
			local x = -inner / 2 + spacing * (ball - 0.5)
			Prims.part({
				name = "Candy" .. ball,
				shape = Enum.PartType.Ball,
				size = Vector3.one * CANDY_DIAMETER,
				cframe = frame * CFrame.new(x, boardTop + CANDY_DIAMETER / 2, face + CANDY_DIAMETER / 2 - 0.3),
				color = pick(candy, index + ball),
				flags = "decor",
				parent = unit,
			})
		end
	end
	return unit
end

-- Public

-- A straight run of shelf units from `from` to `to` (floor points on the run's centre line) whose fronts look along
-- `facing` (into the lobby). Units are `unitSize` wide; the last one is cut to fit. Returns the run Model.
function Props.shelfRun(
	parent: Instance,
	name: string,
	from: Vector3,
	to: Vector3,
	facing: Vector3,
	unitSize: Vector3,
	awningY: { number },
	style: ShelfStyle
): Model
	local length = (to - from).Magnitude
	local direction = (to - from).Unit
	local run = Prims.model(name, parent, false, CFrame.new((from + to) / 2))
	local look = Vector3.new(facing.X, 0, facing.Z).Unit
	local count = math.max(1, math.ceil(length / unitSize.X - 1e-6))
	for i = 1, count do
		local start = (i - 1) * unitSize.X
		local width = math.min(unitSize.X, length - start)
		local centre = from + direction * (start + width / 2)
		local frame = CFrame.lookAt(centre, centre + look)
		shelfUnit(
			run,
			string.format("Unit%02d", i),
			frame,
			Vector3.new(width, unitSize.Y, unitSize.Z),
			awningY,
			style,
			i
		)
	end
	return run
end

-- A giant lollipop standing at `base` (floor point): a stick and a disc head (centred on the stick top) whose flat
-- sides look along `facing`. All decor (taller than 3 studs, §7.7 rule 2).
function Props.lollipop(
	parent: Instance,
	name: string,
	base: Vector3,
	facing: Vector3,
	spec: LollipopSpec,
	style: LollipopStyle
): Model
	local model = Prims.model(name, parent, false, CFrame.new(base))
	Prims.disc(
		"Stick",
		spec.stickDiameter,
		spec.stickHeight,
		base + Vector3.new(0, spec.stickHeight / 2, 0),
		style.stick,
		"decor",
		model
	)
	local headCentre = base + Vector3.new(0, spec.stickHeight, 0)
	-- A cylinder runs along its X axis: aim X along `facing` so the flat sides look that way.
	local flat = Vector3.new(facing.X, 0, facing.Z)
	local axis = if flat.Magnitude > 1e-6 then flat.Unit else Vector3.xAxis
	local headFrame = CFrame.fromMatrix(headCentre, axis, Vector3.yAxis)
	Prims.part({
		name = "Head",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(spec.headThickness, spec.headDiameter, spec.headDiameter),
		cframe = headFrame,
		color = style.head,
		flags = "decor",
		parent = model,
	})
	local swirl = spec.headDiameter * SWIRL_RATIO
	Prims.part({
		name = "Swirl",
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(spec.headThickness + SWIRL_EXTRA_THICKNESS, swirl, swirl),
		cframe = headFrame,
		color = style.swirl,
		flags = "decor",
		parent = model,
	})
	return model
end

-- A stack of three toy blocks on `base` (floor point), each smaller and turned a little. Only the bottom block
-- collides (it is `footprint` tall, at most 3 studs); the upper two are decor.
function Props.toyBlocks(parent: Instance, name: string, base: Vector3, footprint: number, colors: { Color3 }): Model
	local model = Prims.model(name, parent, false, CFrame.new(base))
	local y = 0
	local side = footprint
	for level = 1, 3 do
		local twist = CFrame.Angles(0, math.rad(TOY_BLOCK_TWIST_DEG * (level - 1)), 0)
		Prims.part({
			name = "Block" .. level,
			size = Vector3.one * side,
			cframe = CFrame.new(base + Vector3.new(0, y + side / 2, 0)) * twist,
			color = pick(colors, level),
			material = Enum.Material.Plastic, -- §7.3: toy blocks
			flags = if level == 1 then "solid" else "decor",
			parent = model,
		})
		y += side
		side *= TOY_BLOCK_SHRINK
	end
	return model
end

-- A gumdrop hedge: uniform balls of `diameter` from `from` to `to` (floor points), at most `spacing` apart so
-- neighbours overlap into one low wall. Under 3 studs, so the balls collide (a hedge you can hop, not a wall).
function Props.gumdropHedge(
	parent: Instance,
	name: string,
	from: Vector3,
	to: Vector3,
	diameter: number,
	spacing: number,
	color: Color3
): Model
	local length = (to - from).Magnitude
	local count = math.max(1, math.ceil(length / spacing - 1e-6) + 1)
	local model = Prims.model(name, parent, false, CFrame.new((from + to) / 2))
	for i = 1, count do
		local t = if count == 1 then 0.5 else (i - 1) / (count - 1)
		local point = from:Lerp(to, t)
		Prims.part({
			name = string.format("Gumdrop%02d", i),
			shape = Enum.PartType.Ball,
			size = Vector3.one * diameter,
			cframe = CFrame.new(point + Vector3.new(0, diameter / 2, 0)),
			color = color,
			flags = "solid",
			parent = model,
		})
	end
	return model
end

return Props
