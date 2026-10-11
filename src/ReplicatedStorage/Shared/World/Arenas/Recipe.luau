--!strict
-- Recipe: the design -> game mapping and the piece-local part constructors that the arena data modules
-- (World/Arenas/*) write their cover with, plus the decor placement rule the arena builders use (phase 4 spec
-- 2026-10-11, §1, §4.4, §4.6). Shared, pure: requiring it has no side effects.
--
-- Frames. The design (sd/arena.js, sd/blox.js, sd/arenas2.js) has its long axis on X, the mint team A at x < 0
-- (HANDOFF.md:91) and yaw ry = three.js rotation.y. The game arena (WorldLayout.Arena) has its long axis on Z, Side B
-- (mint) at Z > 0 and yaw = CFrame.Angles(0, yaw, 0): the same right-hand turn about +Y. A design point (x, z) of the
-- mint half maps to Side B (spec §1, a proper 90 deg turn, no mirror; the design half 0..L/2 lands on game |Z| 8..52,
-- past the neutral band):
--   game X = z * sW,   game Z = 8 + |x| * sL,   game yaw = ry + 90 deg,   sW = 72 / W,   sL = 88 / L
-- Positions use these court scales; props stay at player scale (spec §4.1): part sizes are design studs except where
-- a recipe names a spec §4.2 rule (R1 full cover 8 tall, R2 at most 8 long).
-- Parts are piece-local: origin = the piece's floor centre, X along the piece, Y up, Z its depth (the design's own
-- local axes, so yaw + 90 deg turns them like the design). A Cylinder's axis is its local X, as Roblox draws it:
-- disc() stands one up, rodZ() lays one along the piece's Z.

-- Types

export type Design = {
	file: string, -- "sd/arena.js"
	L: number, -- design court length (long axis, studs)
	W: number, -- design court width
}

export type Shape = "Block" | "Cylinder" | "Ball"

export type Part = {
	name: string, -- part name inside the piece Model; a piece's first part is its "Body"
	shape: Shape,
	cframe: CFrame, -- piece-local
	size: Vector3, -- Roblox Part size (a Cylinder: length along its axis, diameter, diameter)
	color: string, -- Art/Palette token
	material: string?, -- Enum.Material name; nil = SmoothPlastic
}

-- Constants

local COURT_HALF_X = 72 / 2 -- WorldLayout.Arena.halfX
local COURT_HALF_Z = 52 -- WorldLayout.Arena.halfZ
local NEUTRAL_HALF_Z = 8 -- WorldLayout.Arena.neutralHalfZ
local GAME_HALF_LENGTH = COURT_HALF_Z - NEUTRAL_HALF_Z -- 44: a design half (L / 2) maps onto |Z| 8..52
local SNAP = 0.05 -- spec §4.3: positions are rounded to 0.05
local ROLL_UP = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's axis (local X) -> up
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- a Cylinder's axis (local X) -> the piece's Z

-- Module table

local Recipe = {}
Recipe.SNAP = SNAP

-- Public: mapping

-- The court scales of a design: (sL along the long axis, sW across). Spec §1: sL = 88 / L, sW = 72 / W.
function Recipe.scales(design: Design): (number, number)
	return 2 * GAME_HALF_LENGTH / design.L, 2 * COURT_HALF_X / design.W
end

-- The Side B floor point of a mint-half design point (x <= 0), unrounded (spec §1).
function Recipe.sideB(design: Design, x: number, z: number): Vector3
	local sL, sW = Recipe.scales(design)
	return Vector3.new(z * sW, 0, NEUTRAL_HALF_Z + math.abs(x) * sL)
end

-- The game yaw of a design yaw (spec §1: + 90 deg).
function Recipe.yaw(ry: number): number
	return ry + math.pi / 2
end

-- `value` snapped to the nearest multiple of SNAP.
function Recipe.snap(value: number): number
	return math.round(value / SNAP) * SNAP
end

-- Decor placement (spec §4.6): an out-of-bounds item keeps its distance beyond the nearest design court edge, and a
-- coordinate within the court's span is scaled to the game court's span. Returns the game (X, Z) of a design (x, z);
-- the design's mint end (x < 0) lands at Z > 0 (Side B).
function Recipe.decorAt(design: Design, x: number, z: number): (number, number)
	local halfL, halfW = design.L / 2, design.W / 2
	local gameZ = if math.abs(x) > halfL
		then -math.sign(x) * (COURT_HALF_Z + math.abs(x) - halfL)
		else -x * COURT_HALF_Z / halfL
	local gameX = if math.abs(z) > halfW
		then math.sign(z) * (COURT_HALF_X + math.abs(z) - halfW)
		else z * COURT_HALF_X / halfW
	return gameX, gameZ
end

-- Public: piece-local parts

function Recipe.block(
	name: string,
	size: Vector3,
	x: number,
	y: number,
	z: number,
	color: string,
	material: string?
): Part
	return {
		name = name,
		shape = "Block",
		cframe = CFrame.new(x, y, z),
		size = size,
		color = color,
		material = material,
	}
end

-- A Block at any piece-local CFrame (a tilted brace or a turned prism face).
function Recipe.turned(name: string, size: Vector3, cframe: CFrame, color: string, material: string?): Part
	return { name = name, shape = "Block", cframe = cframe, size = size, color = color, material = material }
end

-- An upright cylinder (diameter across X and Z, `height` along Y) centred at (x, y, z).
function Recipe.disc(
	name: string,
	diameter: number,
	height: number,
	x: number,
	y: number,
	z: number,
	color: string,
	material: string?
): Part
	return {
		name = name,
		shape = "Cylinder",
		cframe = CFrame.new(x, y, z) * ROLL_UP,
		size = Vector3.new(height, diameter, diameter),
		color = color,
		material = material,
	}
end

-- A cylinder lying along the piece's Z (a log, or a flat disc on a Z face), centred at (x, y, z).
function Recipe.rodZ(
	name: string,
	diameter: number,
	length: number,
	x: number,
	y: number,
	z: number,
	color: string,
	material: string?
): Part
	return {
		name = name,
		shape = "Cylinder",
		cframe = CFrame.new(x, y, z) * ALONG_Z,
		size = Vector3.new(length, diameter, diameter),
		color = color,
		material = material,
	}
end

function Recipe.ball(
	name: string,
	diameter: number,
	x: number,
	y: number,
	z: number,
	color: string,
	material: string?
): Part
	return {
		name = name,
		shape = "Ball",
		cframe = CFrame.new(x, y, z),
		size = Vector3.one * diameter,
		color = color,
		material = material,
	}
end

return table.freeze(Recipe)
