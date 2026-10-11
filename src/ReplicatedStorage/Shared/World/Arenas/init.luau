--!strict
-- Arenas: the duel arena registry (phase 4 spec 2026-10-11 §5.1). Shared, data only: requiring it builds and
-- deep-freezes plain tables (no side effects). Read by WorldService and ArenaService (which templates exist, the random
-- pick), the SDTools arena builders (through the injected Shared clone) and the client's jelly ripple guard.
-- Candy Court (WorldLayout.Arena, generator "arena") plus the 5 Claude Design arenas, each built by its own SDTools
-- generator into ServerStorage.SD_Templates; ArenaService picks one at random per match (D7: equal chance, repeats
-- allowed). Every arena keeps Candy Court's gameplay frame (WorldLayout.Arena: floor top Y 0, playable X +-36 /
-- Z +-52, neutral band Z -8..8 and its dividers, pads at Z +-44, barriers, ceiling, zones, audio zone); only the art and
-- the 12 cover pieces differ, so no hit, movement, camera or throw code changes per arena.
--
--   id                  template                 generator                 design
--   candy_court         Arena_CandyCourt         arena                     (WorldLayout.Arena)
--   sweetshop_stadium   Arena_SweetshopStadium   arena_sweetshop_stadium   sd/arena.js
--   pinewood_camp       Arena_PinewoodCamp       arena_pinewood_camp       sd/blox.js
--   pillow_fort_park    Arena_PillowFortPark     arena_pillow_fort_park    sd/arenas2.js:45-114
--   bubble_reef_court   Arena_BubbleReefCourt    arena_bubble_reef_court   sd/arenas2.js:116-175
--   arcade_toyworks     Arena_ArcadeToyworks     arena_arcade_toyworks     sd/arenas2.js:177-259
--
-- Cover (spec §4.2-§4.4): each child module lists its 6 Side B pieces by their design position. Here each one is
-- mapped (Recipe.sideB, yaw + 90 deg), slid sideways when its parts reach the pad-to-pad lane X -6..6 until its near
-- edge is at |X| 6.5 (R5), snapped to 0.05, and point-reflected into Side A ((x, z) -> (-x, -z), yaw + 180 deg, the
-- same parts with the arena's swapA colours), as Candy Court does and Verify demands. Candy Court's cover stays in
-- WorldLayout.Arena (its `cover` here is nil).
--
-- API
--   Arenas.DEFAULT_ID   "candy_court"
--   Arenas.ids          every arena id, Candy Court first (frozen list)
--   Arenas.byId[id]     its ArenaDef (frozen)
--   Arenas.get(id)      the ArenaDef, or nil for an unknown id

local Recipe = require(script.Recipe)
local WorldLayout = require(script.Parent.WorldLayout)

-- Types

export type CoverPiece = {
	name: string, -- "B_WaferBack1": the side, then the design piece; the Model is "Cover_" .. name
	side: "A" | "B",
	kind: "full" | "low", -- full: top >= 8, nobody stands on it (R1); low: top 3..5, can be hopped on (R3, D2)
	source: string, -- the design line it comes from ("sd/arena.js:88")
	design: { x: number, z: number, ry: number }, -- the Side B piece's design position
	position: Vector3, -- floor centre, arena space (relative to Origin)
	yaw: number, -- radians about +Y
	parts: { Recipe.Part }, -- piece-local; [1] = "Body", the Model's PrimaryPart
}

export type ArenaDef = {
	id: string,
	templateName: string, -- the ServerStorage.SD_Templates child
	generatorId: string, -- the SDTools target (SD_GeneratorId)
	design: Recipe.Design?, -- the design court; nil for Candy Court
	swapA: { [string]: string }, -- Side A colour of a Side B Palette token (team prints)
	cover: { CoverPiece }?, -- 12 pieces (Side B, then Side A); nil = WorldLayout.Arena.cover
	apron: Vector3, -- decor floor size under the arena (the slot cell is 200 x 200)
}

-- What a child module returns (its Side B cover by design position).
type CoverSpec = {
	name: string,
	kind: string,
	source: string,
	x: number,
	z: number,
	ry: number,
	parts: { Recipe.Part },
}

type ArenaSpec = {
	id: string,
	templateName: string,
	generatorId: string,
	design: Recipe.Design,
	swapA: { [string]: string },
	cover: { CoverSpec },
}

-- Constants

local DEFAULT_ID = "candy_court"
local LANE_HALF_X = WorldLayout.Arena.openLaneHalfX -- 6: the pad-to-pad lane X -6..6
local LANE_EDGE = 6.5 -- spec §4.2 R5: a slid piece's near edge
local DESIGN_APRON = Vector3.new(190, 4, 190) -- spec §4.6: decor stays inside |X|, |Z| <= 95 of the 200-stud cell
local SPECS: { ArenaSpec } = {
	require(script.SweetshopStadium) :: any,
	require(script.PinewoodCamp) :: any,
	require(script.PillowFortPark) :: any,
	require(script.BubbleReefCourt) :: any,
	require(script.ArcadeToyworks) :: any,
}

-- Private

local function deepFreeze(value: any)
	if type(value) ~= "table" or table.isfrozen(value) then
		return
	end
	table.freeze(value)
	for _, child in value do
		deepFreeze(child)
	end
end

-- The arena-space X range of a piece's part boxes when it stands at `position`, turned by `yaw`.
local function spanX(parts: { Recipe.Part }, position: Vector3, yaw: number): (number, number)
	local frame = CFrame.new(position) * CFrame.Angles(0, yaw, 0)
	local low, high = math.huge, -math.huge
	for _, part in parts do
		local cf = frame * part.cframe
		local half = part.size / 2
		local reach = math.abs(cf.XVector.X) * half.X
			+ math.abs(cf.YVector.X) * half.Y
			+ math.abs(cf.ZVector.X) * half.Z
		low = math.min(low, cf.Position.X - reach)
		high = math.max(high, cf.Position.X + reach)
	end
	return low, high
end

-- R5: slides a piece that reaches the lane sideways until its near edge is at |X| LANE_EDGE.
local function outOfLane(parts: { Recipe.Part }, position: Vector3, yaw: number, what: string): Vector3
	local low, high = spanX(parts, position, yaw)
	if low >= LANE_HALF_X or high <= -LANE_HALF_X then
		return position
	end
	if math.abs(position.X) < 1e-6 then
		error(`Arenas: {what} sits on the lane axis and cannot be slid out of the lane`)
	end
	local shift = if position.X > 0 then LANE_EDGE - low else -LANE_EDGE - high
	return position + Vector3.new(shift, 0, 0)
end

local function coverOf(spec: ArenaSpec): { CoverPiece }
	local sideB: { CoverPiece } = {}
	local sideA: { CoverPiece } = {}
	for _, piece in spec.cover do
		local what = `{spec.id} {piece.name}`
		local yaw = Recipe.yaw(piece.ry)
		local mapped = outOfLane(piece.parts, Recipe.sideB(spec.design, piece.x, piece.z), yaw, what)
		local position = Vector3.new(Recipe.snap(mapped.X), 0, Recipe.snap(mapped.Z))
		local kind: "full" | "low" = if piece.kind == "low" then "low" else "full"
		local design = { x = piece.x, z = piece.z, ry = piece.ry }
		table.insert(sideB, {
			name = "B_" .. piece.name,
			side = "B",
			kind = kind,
			source = piece.source,
			design = design,
			position = position,
			yaw = yaw,
			parts = piece.parts,
		})
		local partsA: { Recipe.Part } = {}
		for _, part in piece.parts do
			local copy = table.clone(part)
			copy.color = spec.swapA[part.color] or part.color
			table.insert(partsA, copy)
		end
		table.insert(sideA, {
			name = "A_" .. piece.name,
			side = "A",
			kind = kind,
			source = piece.source,
			design = design,
			position = Vector3.new(-position.X, 0, -position.Z),
			yaw = yaw + math.pi,
			parts = partsA,
		})
	end
	for _, piece in sideA do
		table.insert(sideB, piece)
	end
	return sideB
end

-- Module table

local ids: { string } = { DEFAULT_ID }
local byId: { [string]: ArenaDef } = {
	[DEFAULT_ID] = {
		id = DEFAULT_ID,
		templateName = WorldLayout.Arena.templateName,
		generatorId = WorldLayout.Arena.generatorId,
		design = nil,
		swapA = {},
		cover = nil,
		apron = WorldLayout.Arena.apron.size,
	},
}
for _, spec in SPECS do
	table.insert(ids, spec.id)
	byId[spec.id] = {
		id = spec.id,
		templateName = spec.templateName,
		generatorId = spec.generatorId,
		design = spec.design,
		swapA = spec.swapA,
		cover = coverOf(spec),
		apron = DESIGN_APRON,
	}
end

local Arenas = {
	DEFAULT_ID = DEFAULT_ID,
	ids = ids,
	byId = byId,
}

-- The ArenaDef of `id`, or nil.
function Arenas.get(id: string): ArenaDef?
	return byId[id]
end

deepFreeze(Arenas)

return Arenas
