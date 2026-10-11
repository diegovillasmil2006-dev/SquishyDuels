--!strict
-- Arenas_Test: unit tests for ReplicatedStorage.Shared.World.Arenas (the duel arena registry) and its Recipe helper
-- (phase 4 spec 2026-10-11, §1, §4.2-§4.4, §5.1, §5.5). Server only (ServerStorage.UnitTest). Pure data: no instances.
-- Contract:
--   * ids: Candy Court first (template, generator and apron are WorldLayout.Arena's, no cover copy), then the 5 design
--     arenas, each with template "Arena_<Name>", generator "arena_<id>" (Generated's id rule: ^[a-z_]+$, <= 24 chars)
--     and an apron that fits its 200-stud slot cell (<= 190 x 190);
--   * cover: 12 pieces per design arena, 6 per side, unique names no Candy Court piece uses, a "Body" first and unique
--     part names; Side A is the point reflection of Side B ((x, z) -> (-x, -z), yaw + 180 deg, the same part geometry,
--     colours through swapA);
--   * spec §4.2: full cover tops >= 8 (R1), low cover tops 3..5 (R3), every piece <= 8 long along its own axes (R2),
--     only Block / Cylinder / Ball parts with valid sizes (R4), nothing in the pad-to-pad lane X -6..6 and a slid
--     piece's near edge at |X| 6.5 (R5), >= 3 studs between pieces and from the rails, nothing within 5 of a pad
--     centre, out of the neutral band, inside the playable court (R6); every piece reaches down to the floor;
--   * spec §1: Side B positions are the design's, mapped and snapped to 0.05 (one piece pinned to the spec's table);
--     the decor rule keeps an out-of-bounds distance and scales an in-court coordinate;
--   * every colour is an Art/Palette world token (never a reserved one) and every material an Enum.Material name.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

local DESIGN_IDS = { "sweetshop_stadium", "pinewood_camp", "pillow_fort_park", "bubble_reef_court", "arcade_toyworks" }
local TEMPLATE_NAMES: { [string]: string } = {
	sweetshop_stadium = "Arena_SweetshopStadium",
	pinewood_camp = "Arena_PinewoodCamp",
	pillow_fort_park = "Arena_PillowFortPark",
	bubble_reef_court = "Arena_BubbleReefCourt",
	arcade_toyworks = "Arena_ArcadeToyworks",
}
local SLOT_CELL = 190 -- studs: the slot origins are 200 apart (Config.Duel.Arena.SlotOrigins)
local FULL_MIN_TOP = 8 -- R1
local LOW_TOP = { 3, 5 } -- R3
local MAX_LENGTH = 8 -- R2
local LANE_HALF_X = 6 -- R5 (WorldLayout.Arena.openLaneHalfX)
local LANE_EDGE = 6.5 -- R5: a slid piece's near edge
local MIN_GAP = 3 -- R6
local PAD_CLEARANCE = 5 -- R6
local EPSILON = 1e-4

type Vec2 = { x: number, z: number }

return function(t: Context)
	local expect = t.expect
	local Arenas = t.requireShared("World/Arenas")
	local Recipe = t.requireShared("World/Arenas/Recipe")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local Palette = t.requireShared("Art/Palette")
	local Arena = WorldLayout.Arena

	local function designArenas(): { any }
		local list = {}
		for _, id in DESIGN_IDS do
			local def = Arenas.byId[id]
			if def == nil then
				error(`no arena {id}`)
			end
			table.insert(list, def)
		end
		return list
	end

	local function pieceFrame(piece: any): CFrame
		return CFrame.new(piece.position) * CFrame.Angles(0, piece.yaw, 0)
	end

	-- Half extents of a box (cframe, size) along the axes its cframe is expressed in.
	local function extent(cf: CFrame, size: Vector3): Vector3
		local h = size / 2
		local x, y, z = cf.XVector, cf.YVector, cf.ZVector
		return Vector3.new(
			math.abs(x.X) * h.X + math.abs(y.X) * h.Y + math.abs(z.X) * h.Z,
			math.abs(x.Y) * h.X + math.abs(y.Y) * h.Y + math.abs(z.Y) * h.Z,
			math.abs(x.Z) * h.X + math.abs(y.Z) * h.Y + math.abs(z.Z) * h.Z
		)
	end

	-- Bounds of the parts' boxes in `frame` (identity = the piece's own axes).
	local function bounds(piece: any, frame: CFrame): (Vector3, Vector3)
		local low = Vector3.one * math.huge
		local high = -Vector3.one * math.huge
		for _, part in piece.parts do
			local cf = frame * part.cframe
			local e = extent(cf, part.size)
			low = low:Min(cf.Position - e)
			high = high:Max(cf.Position + e)
		end
		return low, high
	end

	-- The piece's own-axes footprint rectangle, in arena XZ.
	local function footprint(piece: any): { Vec2 }
		local low, high = bounds(piece, CFrame.identity)
		local frame = pieceFrame(piece)
		local corners: { Vec2 } = {}
		for _, c in { { low.X, low.Z }, { high.X, low.Z }, { high.X, high.Z }, { low.X, high.Z } } do
			local p = frame:PointToWorldSpace(Vector3.new(c[1], 0, c[2]))
			table.insert(corners, { x = p.X, z = p.Z })
		end
		return corners
	end

	local function pointSegment(p: Vec2, a: Vec2, b: Vec2): number
		local dx, dz = b.x - a.x, b.z - a.z
		local length2 = dx * dx + dz * dz
		local s = if length2 > 0 then math.clamp(((p.x - a.x) * dx + (p.z - a.z) * dz) / length2, 0, 1) else 0
		local qx, qz = a.x + dx * s - p.x, a.z + dz * s - p.z
		return math.sqrt(qx * qx + qz * qz)
	end

	local function cross(o: Vec2, a: Vec2, b: Vec2): number
		return (a.x - o.x) * (b.z - o.z) - (a.z - o.z) * (b.x - o.x)
	end

	local function inside(p: Vec2, polygon: { Vec2 }): boolean
		local sign = 0
		for i, a in polygon do
			local c = cross(a, polygon[i % #polygon + 1], p)
			if math.abs(c) > 1e-9 then
				local s = if c > 0 then 1 else -1
				if sign == 0 then
					sign = s
				elseif s ~= sign then
					return false
				end
			end
		end
		return true
	end

	local function crossing(a: Vec2, b: Vec2, c: Vec2, d: Vec2): boolean
		return cross(a, b, c) * cross(a, b, d) < 0 and cross(c, d, a) * cross(c, d, b) < 0
	end

	-- Distance between two convex polygons (0 when they touch or overlap).
	local function gap(p: { Vec2 }, q: { Vec2 }): number
		for _, v in p do
			if inside(v, q) then
				return 0
			end
		end
		for _, v in q do
			if inside(v, p) then
				return 0
			end
		end
		local best = math.huge
		for i, a in p do
			local b = p[i % #p + 1]
			for j, c in q do
				local d = q[j % #q + 1]
				if crossing(a, b, c, d) then
					return 0
				end
				best = math.min(
					best,
					pointSegment(a, c, d),
					pointSegment(b, c, d),
					pointSegment(c, a, b),
					pointSegment(d, a, b)
				)
			end
		end
		return best
	end

	local function pointPolygon(p: Vec2, polygon: { Vec2 }): number
		if inside(p, polygon) then
			return 0
		end
		local best = math.huge
		for i, a in polygon do
			best = math.min(best, pointSegment(p, a, polygon[i % #polygon + 1]))
		end
		return best
	end

	-- Registry -------------------------------------------------------------------------------------------------------

	t.test("ids: Candy Court first, then the 5 design arenas, each with its template, generator and apron", function()
		local expected = { Arenas.DEFAULT_ID }
		for _, id in DESIGN_IDS do
			table.insert(expected, id)
		end
		expect.deepEqual(Arenas.ids, expected)
		expect.equal(Arenas.DEFAULT_ID, "candy_court")
		local candy = Arenas.byId.candy_court
		expect.equal(candy.templateName, Arena.templateName)
		expect.equal(candy.generatorId, Arena.generatorId)
		expect.equal(candy.cover, nil) -- WorldLayout.Arena.cover
		expect.equal(candy.apron, Arena.apron.size)
		for _, def in designArenas() do
			expect.equal(def.templateName, TEMPLATE_NAMES[def.id])
			expect.equal(def.generatorId, "arena_" .. def.id)
			expect.truthy(#def.generatorId <= 24 and string.match(def.generatorId, "^[a-z_]+$") ~= nil)
			expect.truthy(def.apron.X <= SLOT_CELL and def.apron.Z <= SLOT_CELL)
			expect.equal(Arenas.get(def.id), def)
		end
		expect.equal(Arenas.get("nowhere"), nil)
		expect.truthy(table.isfrozen(Arenas.byId) and table.isfrozen(Arenas.byId.pinewood_camp.cover[1].parts))
	end)

	t.test("12 cover pieces per design arena, 6 per side, unique names, a Body first", function()
		local candyNames: { [string]: boolean } = {}
		for _, piece in Arena.cover do
			candyNames[piece.name] = true
		end
		for _, def in designArenas() do
			expect.equal(#def.cover, 12)
			local names: { [string]: boolean } = {}
			local perSide: { [string]: number } = { A = 0, B = 0 }
			for _, piece in def.cover do
				if names[piece.name] or candyNames[piece.name] then
					error(`{def.id}: duplicate or Candy Court name {piece.name}`)
				end
				names[piece.name] = true
				perSide[piece.side] += 1
				expect.equal(string.sub(piece.name, 1, 2), piece.side .. "_")
				expect.equal(piece.parts[1].name, "Body")
				local partNames: { [string]: boolean } = {}
				for _, part in piece.parts do
					if partNames[part.name] then
						error(`{def.id} {piece.name}: two parts named {part.name}`)
					end
					partNames[part.name] = true
				end
			end
			expect.deepEqual(perSide, { A = 6, B = 6 })
		end
	end)

	t.test("Side A is the point reflection of Side B (yaw + 180, same parts, colours through swapA)", function()
		for _, def in designArenas() do
			local byName: { [string]: any } = {}
			for _, piece in def.cover do
				byName[piece.name] = piece
			end
			for _, piece in def.cover do
				if piece.side ~= "B" then
					continue
				end
				local twin = byName["A_" .. string.sub(piece.name, 3)]
				if twin == nil then
					error(`{def.id}: {piece.name} has no Side A twin`)
				end
				local p, q = piece.position, twin.position
				expect.near((Vector3.new(-p.X, p.Y, -p.Z) - q).Magnitude, 0, EPSILON)
				local turn = (twin.yaw - piece.yaw) % (2 * math.pi)
				expect.near(turn, math.pi, EPSILON)
				expect.equal(twin.kind, piece.kind)
				expect.equal(#twin.parts, #piece.parts)
				for index, part in piece.parts do
					local other = twin.parts[index]
					expect.equal(other.name, part.name)
					expect.equal(other.shape, part.shape)
					expect.equal(other.size, part.size)
					expect.equal(other.cframe, part.cframe)
					expect.equal(other.color, def.swapA[part.color] or part.color)
				end
			end
		end
	end)

	-- Spec §4.2 rules ------------------------------------------------------------------------------------------------

	t.test("R1-R4: full tops >= 8, low tops 3..5, <= 8 long on its own axes, Block / Cylinder / Ball only", function()
		for _, def in designArenas() do
			for _, piece in def.cover do
				local low, high = bounds(piece, CFrame.identity)
				local what = `{def.id} {piece.name}`
				if piece.kind == "full" then
					if high.Y < FULL_MIN_TOP - EPSILON then
						error(`{what}: full cover top {high.Y} < {FULL_MIN_TOP}`)
					end
				elseif piece.kind == "low" then
					if high.Y < LOW_TOP[1] - EPSILON or high.Y > LOW_TOP[2] + EPSILON then
						error(`{what}: low cover top {high.Y} outside {LOW_TOP[1]}..{LOW_TOP[2]}`)
					end
				else
					error(`{what}: unknown kind {piece.kind}`)
				end
				local length = math.max(high.X - low.X, high.Z - low.Z)
				if length > MAX_LENGTH + EPSILON then
					error(`{what}: {length} long along its own axes`)
				end
				if low.Y > EPSILON then
					error(`{what}: floats {low.Y} above the floor`)
				end
				for _, part in piece.parts do
					local size = part.size
					expect.truthy(size.X > 0 and size.Y > 0 and size.Z > 0)
					if part.shape == "Ball" then
						expect.truthy(size.X == size.Y and size.Y == size.Z)
					elseif part.shape == "Cylinder" then
						expect.near(size.Y, size.Z, EPSILON)
					elseif part.shape ~= "Block" then
						error(`{what}.{part.name}: shape {part.shape}`)
					end
				end
			end
		end
	end)

	t.test("R5/R6: out of the lane and the neutral band, clear of the pads and rails, >= 3 apart", function()
		for _, def in designArenas() do
			local prints = {}
			for index, piece in def.cover do
				local what = `{def.id} {piece.name}`
				local wLow, wHigh = bounds(piece, pieceFrame(piece))
				-- The lane box X -6..6 between the pads (Z -44..44), above the floor paint (Y 0.5).
				if
					wLow.X < LANE_HALF_X
					and wHigh.X > -LANE_HALF_X
					and wHigh.Y > 0.5
					and wLow.Z < 44
					and wHigh.Z > -44
				then
					error(`{what}: reaches the pad-to-pad lane (X {wLow.X}..{wHigh.X})`)
				end
				if wLow.Z < Arena.neutralHalfZ and wHigh.Z > -Arena.neutralHalfZ then
					error(`{what}: reaches the neutral band`)
				end
				local polygon = footprint(piece)
				for _, v in polygon do
					if
						math.abs(v.x) > Arena.halfX - MIN_GAP + EPSILON
						or math.abs(v.z) > Arena.halfZ - MIN_GAP + EPSILON
					then
						error(`{what}: closer than {MIN_GAP} to a rail ({v.x}, {v.z})`)
					end
				end
				for _, padZ in { -44, 44 } do
					local d = pointPolygon({ x = 0, z = padZ }, polygon)
					if d < PAD_CLEARANCE then
						error(`{what}: {d} from the pad at Z {padZ}`)
					end
				end
				prints[index] = polygon
			end
			for i = 1, #def.cover do
				for j = i + 1, #def.cover do
					local d = gap(prints[i], prints[j])
					if d < MIN_GAP - EPSILON then
						error(`{def.id}: {def.cover[i].name} and {def.cover[j].name} are {d} apart`)
					end
				end
			end
		end
	end)

	t.test("R5: a piece slid out of the lane has its near edge at |X| 6.5", function()
		local slid = 0
		for _, def in designArenas() do
			for _, piece in def.cover do
				if piece.side ~= "B" then
					continue
				end
				local mapped = Recipe.sideB(def.design, piece.design.x, piece.design.z)
				if math.abs(mapped.X - piece.position.X) > Recipe.SNAP then
					slid += 1
					local wLow, wHigh = bounds(piece, pieceFrame(piece))
					local edge = if piece.position.X > 0 then wLow.X else -wHigh.X
					expect.near(edge, LANE_EDGE, Recipe.SNAP)
				end
			end
		end
		expect.equal(slid, 3) -- Bubble Reef's first pillar and Arcade Toyworks' two cabinets (spec §4.3)
	end)

	-- Mapping (spec §1) ----------------------------------------------------------------------------------------------

	t.test("Side B positions are the design's, mapped and snapped to 0.05 (spec §1, §4.3)", function()
		local sweetshop = Arenas.byId.sweetshop_stadium
		local wafer = sweetshop.cover[1]
		expect.equal(wafer.name, "B_WaferBack1")
		-- Spec §4.3: design wafer back_S (-64, -32, pi/2) -> X -17.72, Z 39.29, yaw 180, snapped.
		expect.near(wafer.position.X, -17.70, EPSILON)
		expect.near(wafer.position.Z, 39.30, EPSILON)
		expect.near(wafer.yaw % (2 * math.pi), math.pi, EPSILON)
		expect.equal(wafer.source, "sd/arena.js:88")
		for _, def in designArenas() do
			for _, piece in def.cover do
				for _, value in { piece.position.X, piece.position.Y, piece.position.Z } do
					local steps = value / Recipe.SNAP
					expect.near(steps, math.round(steps), EPSILON)
				end
				expect.equal(piece.position.Y, 0)
			end
		end
	end)

	t.test("Recipe: the court scales, the Side B map and the decor rule (spec §1, §4.6)", function()
		local design = { file = "x", L = 176, W = 128 }
		local sL, sW = Recipe.scales(design)
		expect.near(sL, 0.5, EPSILON)
		expect.near(sW, 0.5625, EPSILON)
		local p = Recipe.sideB(design, -26, -24) -- spec §4.3 B_PillowFwd1: X -13.50, Z 21.00
		expect.near(p.X, -13.5, EPSILON)
		expect.near(p.Z, 21, EPSILON)
		expect.near(Recipe.yaw(-0.46), math.rad(63.64), 1e-3)
		-- Decor: 40 beyond the design's long side keeps 40 beyond the game's; inside the court span it scales.
		local x, z = Recipe.decorAt(design, 0, 104) -- spec §4.6 giant sofa: X 76
		expect.near(x, 76, EPSILON)
		expect.near(z, 0, EPSILON)
		local x2, z2 = Recipe.decorAt(design, -50, -34) -- spec §4.6 hanging star: (-19.1, 29.5)
		expect.near(x2, -19.125, EPSILON)
		expect.near(z2, 29.545, 1e-3)
		local _, z3 = Recipe.decorAt(design, -114, 0) -- 26 beyond the mint end -> Z 52 + 26
		expect.near(z3, 78, EPSILON)
	end)

	-- Colours and materials ------------------------------------------------------------------------------------------

	t.test("every cover colour is a Palette world token and every material an Enum.Material name", function()
		local reserved: { [string]: boolean } = {}
		for _, name in Palette.RESERVED do
			reserved[name] = true
		end
		for _, def in designArenas() do
			for _, piece in def.cover do
				for _, part in piece.parts do
					local what = `{def.id} {piece.name}.{part.name}`
					if typeof(Palette[part.color]) ~= "Color3" or reserved[part.color] then
						error(`{what}: colour {part.color} is not a Palette world token`)
					end
					local material = part.material
					if material ~= nil then
						local ok, value = pcall(function(): any
							return (Enum.Material :: any)[material]
						end)
						if not ok or typeof(value) ~= "EnumItem" or material == "Neon" then
							error(`{what}: material {material}`)
						end
					end
				end
			end
			for from, to in def.swapA do
				expect.equal(typeof(Palette[from]), "Color3")
				expect.equal(typeof(Palette[to]), "Color3")
			end
		end
	end)
end
