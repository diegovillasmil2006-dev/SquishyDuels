--!strict
-- HighwayBuilder_Test: the contract of the highway generator ServerStorage.SDTools.Builders.HighwayBuilder (pens3
-- phase 12: the lobby design v6's highway as parts; work/pens3/PLAN.md "PHASE 12"). Server only
-- (ServerStorage.UnitTest).
-- It runs as Main's pipeline runs it (build(ctx) with a scratch Cleanup and the Shared folder under test, an
-- UNPARENTED tree that is destroyed afterwards) and pins, restated from the design and Config instead of read from the
-- builder:
--   * the root SD_Highway (marked "highway", version 4) pivoted on WorldLayout.Highway.origin: a Persistent Deck and
--     the 7 biome Models (L:1 zones Biome_1_CM..Biome_7_DH; p13v4: Persistent too, so the chase camera never meets an
--     empty sky), every placed piece its own Model (SD_Piece = its v6 piece);
--   * p13v4 (owner 2026-10-19: the TikTok throw's rings and targets): 3 flight_ring pieces a biome where
--     WorldLayout.Highway.rings puts them (12 rods of radius 10 around the lane's axis), 2 flight_pad pieces a biome on
--     the lane top where WorldLayout.Highway.pads puts them (3 discs, radius 15 / 10 / 5);
--   * distances exact (phase 13's landing math is in studs from the start line): 170 lane pieces of 50 studs end to end
--     from 0 to the Golden Gates at 8,500 (PR3:36), each in the biome Config.Economy.Highway's starts put it in, with a
--     rail on each edge (L:459-460: x ±14, 1.04 up); a distance marker every 100 studs from 100 to 8,400 at x 19
--     (L:476) showing its grouped distance and "studs" (P3D:275); Claude Design's name arch at each zone start from
--     Bakery Town (highway v2, 2026-10-23), the launch gate's banner naming Candy Meadow (L:33); each zone's own floor
--     end to end under it (Design's width; the checker floors Lego studs and the checker);
--   * the deck (L:20, :31-37): pens3 phase 13 (owner 2026-10-18: "a general area where they walk up and everybody can
--     throw"): no launch spots (v6's L:21-30 and the SD_LaunchSpot tag are gone), only the platform, the 2 watch steps,
--     the gate and its 4 fences; the launch board (SD_LaunchBoard) with its static lines (LAUNCH BOARD, LAST THROWS,
--     SERVER BEST) and its 8 empty live slots (3 last-throw rows, newest on top, a name beside its distance in the
--     LAST column; the server best in its own); the Kitty Bread mascot slot on the gate (LK:173-175);
--   * every piece placed from the origin; nothing but the deck collides; pieces per biome within v6's 600 and the part
--     counts pinned; two builds give the same tree; Verify passes on the build and catches a broken one.
-- Claude Design's zones (highway v2: HighwayZones + HighwayKit) are checked here by their floors, bounds and counts,
-- and at build time (HighwayBuilder: the kit's zones match Config, nothing in the flight tube).

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
}

-- Restated from the design.
local BIOME_MODELS =
	{ "Biome_1_CM", "Biome_2_BT", "Biome_3_BL", "Biome_4_FD", "Biome_5_LV", "Biome_6_RR", "Biome_7_DH" }
local MARKERS = 84 -- L:476 ...: d 100 .. 8,400
local LANE_PIECES = 170 -- 8,500 / 50
local FLOOR_TOP = -0.1 -- Design's road surface (HighwayZones' Y0): 0.1 under the lane's foot
-- Claude Design's zone floors (highway v2, HighwayKit): name, width, checker (Lego studs + the checker, owner
-- 2026-10-23); all 2 thick.
local FLOORS = {
	{ "Meadow floor", 140, true },
	{ "Shortbread floor", 136, true },
	{ "Lagoon water", 136, false },
	{ "Snow floor", 140, true },
	{ "Basalt floor", 136, false },
	{ "Lilac floor", 140, true },
	{ "Marble floor", 140, true },
}
-- The pieces and parts of each biome (v7, the 2026-10-23 build): the lane, its rails and markers, the arch, 3 rings
-- and 2 pads as before; Design's floor, walls, outside, particles and every prop every 100 studs (one Part per
-- material: its blocks unioned).
local PIECES = { 89, 118, 155, 236, 328, 441, 487 }
local PARTS = { 239, 382, 469, 774, 1015, 1248, 1569 }
local RINGS_PER_BIOME, PADS_PER_BIOME, ROD_COUNT = 3, 2, 12
local MAX_PIECES = 600 -- spec.txt:157
local TOLERANCE = 2e-3 -- CFrames are single precision; 8,500 studs out that is a few thousandths

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local function near(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or TOLERANCE)
end

local function countParts(root: Instance): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function pieces(root: Instance, piece: string?): { Model }
	local list: { Model } = {}
	for _, child in root:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("SD_Piece") ~= nil then
			if piece == nil or child:GetAttribute("SD_Piece") == piece then
				table.insert(list, child)
			end
		end
	end
	return list
end

-- A stable text of a tree: every instance's path, class and key properties (the build time aside).
local function dump(root: Instance): string
	local lines: { string } = {}
	local function walk(node: Instance, path: string)
		local line = path .. " " .. node.ClassName
		if node:IsA("BasePart") then
			local cf = node.CFrame
			line ..= string.format(
				" %.3f %.3f %.3f %s %s %s %s %s",
				cf.X,
				cf.Y,
				cf.Z,
				tostring(cf.LookVector),
				tostring(node.Size),
				node.Color:ToHex(),
				node.Material.Name,
				tostring(node.CanCollide)
			)
		elseif node:IsA("TextLabel") then
			line ..= " " .. node.Text
		end
		local attributes = {}
		for key, value in node:GetAttributes() do
			if key ~= "SD_BuiltAt" then
				table.insert(attributes, key .. "=" .. tostring(value))
			end
		end
		table.sort(attributes)
		line ..= " [" .. table.concat(attributes, ",") .. "] {" .. table.concat(node:GetTags(), ",") .. "}"
		table.insert(lines, line)
		local children = node:GetChildren()
		for index, child in children do
			walk(child, path .. "/" .. index .. ":" .. child.Name)
		end
	end
	walk(root, root.Name)
	return table.concat(lines, "\n")
end

local function loadTools(): (Instance, any, any)
	local source = ServerStorage:FindFirstChild("SDTools")
	if source == nil then
		error("ServerStorage.SDTools not found (is Rojo connected?)")
	end
	local clone = source:Clone()
	local builders = clone:FindFirstChild("Builders")
	local module = if builders then builders:FindFirstChild("HighwayBuilder") else nil
	if module == nil or not module:IsA("ModuleScript") then
		clone:Destroy()
		error("SDTools.Builders.HighwayBuilder not found")
	end
	return clone, dynamicRequire(module), dynamicRequire(clone:FindFirstChild("Verify") :: ModuleScript)
end

return function(t: Context)
	local expect = t.expect
	local tools, HighwayBuilder, Verify = loadTools()
	local Cleanup = t.requireShared("Util/Cleanup")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local Strings = t.requireShared("Strings")
	local H = WorldLayout.Highway
	local origin: CFrame = H.origin
	local starts = Config.Economy.Highway.starts
	local gatesAt = Config.Economy.Highway.gatesAt

	local function build(): (Model, { string })
		local scratch = Cleanup.new()
		local ok, result = pcall(HighwayBuilder.build, { scratch = scratch, Shared = t.Shared })
		if not ok or not result.ok or result.root == nil then
			scratch:clean()
			error("HighwayBuilder.build failed: " .. (if ok then tostring(result.error) else tostring(result)))
		end
		scratch:clean() -- the root was handed over: cleaning must not destroy it
		return result.root :: Model, result.warnings
	end

	local root, warnings = build()
	local deck = root:FindFirstChild("Deck") :: Model

	-- The lane-local position of a piece's pivot: (x, y, d).
	local function laneOf(model: Model): Vector3
		local p = origin:PointToObjectSpace(model.WorldPivot.Position)
		return Vector3.new(p.X, p.Y, -p.Z)
	end

	-- The biome a distance lies in (Config starts; the last ends at the gates).
	local function biomeAt(d: number): number
		local n = 1
		for index, start in starts do
			if d >= start then
				n = index
			end
		end
		return n
	end

	t.test(
		"the root is SD_Highway, unparented, marked highway v7, pivoted on the origin; a Persistent deck, 7 biomes",
		function()
			expect.equal(root.Name, "SD_Highway")
			expect.equal(root.Parent, nil)
			expect.equal(root:GetAttribute("SD_GeneratorId"), "highway")
			expect.equal(root:GetAttribute("SD_GeneratorVersion"), HighwayBuilder.VERSION)
			expect.equal(HighwayBuilder.VERSION, 7) -- 4: p13v4's rings and pads; 5-6: the stand-in; 7: Design's v2
			expect.truthy(root:HasTag("SD_Generated"))
			expect.truthy(near((root.WorldPivot.Position - origin.Position).Magnitude, 0))
			expect.equal(deck.ModelStreamingMode, Enum.ModelStreamingMode.Persistent) -- K:7881-7883 Plaza, LaunchGate
			for index, name in BIOME_MODELS do
				local found = root:FindFirstChild(name)
				expect.truthy(found ~= nil and found:IsA("Model"))
				local biome = found :: Model
				expect.equal(biome:GetAttribute("Biome"), index)
				-- P13v4 [P]: the chase camera flies up to 8,500 studs from the character: every biome always loaded.
				expect.equal(biome.ModelStreamingMode, Enum.ModelStreamingMode.Persistent)
				for _, piece in pieces(biome) do -- K:7887: each placed piece an Atomic model streamed by distance
					expect.equal(piece.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
				end
			end
			expect.equal(#root:GetChildren(), 8)
		end
	)

	t.test(
		"170 lane pieces of 50 studs end to end from 0 to the Golden Gates, each in its biome, a rail on each edge",
		function()
			local centres: { number } = {}
			for index, name in BIOME_MODELS do
				local biome = root:FindFirstChild(name) :: Model
				local lanes = pieces(biome, if index == 6 then "rr_rainbow_lane" else "lane_tile")
				expect.equal(#pieces(biome, if index == 6 then "lane_tile" else "rr_rainbow_lane"), 0)
				local rails = pieces(biome, "lane_rail")
				expect.equal(#rails, 2 * #lanes)
				for _, lane in lanes do
					local p = laneOf(lane)
					expect.truthy(near(p.X, 0) and near(p.Y, 0))
					expect.equal(biomeAt(p.Z - 25), index) -- the piece's whole 50 studs lie in its biome
					expect.equal(biomeAt(p.Z + 24.9), index)
					table.insert(centres, p.Z)
				end
				local sides: { [string]: number } = {}
				for _, rail in rails do
					local p = laneOf(rail)
					expect.truthy(near(math.abs(p.X), 14) and near(p.Y, 1.04)) -- L:459-460
					local key = string.format("%.1f", p.Z)
					sides[key] = (sides[key] or 0) + p.X
				end
				for _, sum in sides do
					expect.truthy(near(sum, 0)) -- one on each edge
				end
			end
			table.sort(centres)
			expect.equal(#centres, LANE_PIECES)
			for index, centre in centres do
				expect.truthy(near(centre, 50 * index - 25))
			end
			expect.truthy(near(centres[#centres] + 25, gatesAt))
		end
	)

	t.test("a distance marker every 100 studs from 100 to 8,400 at x 19, in its biome, showing its distance", function()
		local seen: { number } = {}
		for index, name in BIOME_MODELS do
			for _, marker in pieces(root:FindFirstChild(name) :: Model, "distance_marker") do
				local d = marker:GetAttribute("Distance") :: number
				local p = laneOf(marker)
				expect.truthy(near(p.X, 19) and near(p.Z, d))
				expect.truthy(near(p.Y, if index >= 6 then 1 else 0)) -- L:476, :1110 (the sky biomes 1 up)
				expect.equal(biomeAt(d), index)
				expect.truthy(marker.WorldPivot.LookVector:Dot(origin.LookVector) < -0.99) -- turned 180° (L:476)
				local texts: { string } = {}
				for _, label in marker:GetDescendants() do
					if label:IsA("TextLabel") then
						table.insert(texts, label.Text)
					end
				end
				table.sort(texts)
				local grouped = if d >= 1000 then string.format("%d,%03d", d // 1000, d % 1000) else tostring(d)
				expect.deepEqual(texts, { grouped, "studs" })
				table.insert(seen, d)
			end
		end
		table.sort(seen)
		expect.equal(#seen, MARKERS)
		for index, d in seen do
			expect.equal(d, 100 * index)
		end
	end)

	t.test(
		"Design's name arches at the zone starts from Bakery Town; the gate names Candy Meadow; gates at 8,500",
		function()
			expect.equal(#pieces(root:FindFirstChild(BIOME_MODELS[1]) :: Model, "biome_arch"), 0)
			for index = 2, #BIOME_MODELS do
				local arches = pieces(root:FindFirstChild(BIOME_MODELS[index]) :: Model, "biome_arch")
				expect.equal(#arches, 1)
				local arch = arches[1]
				local p = laneOf(arch)
				expect.truthy(near(p.X, 0) and near(p.Y, FLOOR_TOP) and near(p.Z, starts[index])) -- on the zone floor
				local label = arch:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel
				expect.equal(label.Text, Strings.resolve(H.biomes[index].nameKey))
				expect.equal(label:GetAttribute("SD_TextKey"), H.biomes[index].nameKey)
			end
			local gate = deck:FindFirstChild("launch_gate_01") :: Model
			local banner = gate:FindFirstChild("biome_banner") :: BasePart
			local bannerText = banner:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel
			expect.equal(bannerText.Text, "CANDY MEADOW") -- L:33 label
			local gates = pieces(root:FindFirstChild("Biome_7_DH") :: Model, "golden_gates")
			expect.equal(#gates, 1)
			local p = laneOf(gates[1])
			expect.truthy(near(p.X, 0) and near(p.Y, FLOOR_TOP) and near(p.Z, gatesAt)) -- Design: d 2,500 in, PR3:36
		end
	)

	t.test("each zone's floor end to end under it, Design's width, its top at Y0; the checker floors Lego", function()
		local covered = 0
		for index, name in BIOME_MODELS do
			local spec = FLOORS[index]
			local floors = pieces(root:FindFirstChild(name) :: Model, "zone_floor")
			expect.equal(#floors, 1)
			local run = 0
			for _, part in floors[1]:GetChildren() do
				if part:IsA("BasePart") and part.Name == spec[1] then
					expect.truthy(near(part.Size.X, spec[2]) and near(part.Size.Y, 2))
					local p = origin:PointToObjectSpace(part.Position)
					expect.truthy(near(p.X, 0) and near(p.Y + 1, FLOOR_TOP))
					expect.equal(part.TopSurface == Enum.SurfaceType.Studs, spec[3])
					expect.equal(part:FindFirstChild("Checker") ~= nil, spec[3])
					run += part.Size.Z
				end
			end
			expect.truthy(near(run, (starts[index + 1] or gatesAt) - starts[index]))
			covered += run
		end
		expect.truthy(near(covered, gatesAt))
	end)

	t.test(
		"pens3 phase 13: no launch spots; the deck is v6's platform, 2 watch steps, the gate and 4 fences",
		function()
			local kinds: { [string]: number } = {}
			for _, piece in pieces(deck) do
				local kind = piece:GetAttribute("SD_Piece") :: string
				kinds[kind] = (kinds[kind] or 0) + 1
			end
			expect.deepEqual(kinds, { launch_platform = 1, watch_steps = 2, launch_gate = 1, candy_fence = 4 })
			for _, instance in root:GetDescendants() do
				if
					instance:HasTag("SD_LaunchSpot")
					or instance.Name == "launcher_mount"
					or instance.Name == "player_stand"
				then
					error(`a launch spot is left: {instance:GetFullName()}`)
				end
			end
			-- The throw area (WorldLayout.Highway.throwArea) is the platform's top: its floor is the deck top's.
			local top = (deck:FindFirstChild("launch_platform_01") :: Model):FindFirstChild("deck_top") :: BasePart
			local area = H.throwArea
			local floor = origin:PointToObjectSpace(top.CFrame.Position).Y + top.Size.Y / 2
			expect.truthy(near(floor, area.position.Y - area.size.Y / 2))
		end
	)

	t.test("the launch board: LAUNCH BOARD, LAST THROWS, SERVER BEST and 8 empty live slots (P3D:281-292)", function()
		local boards: { BasePart } = {}
		for _, part in deck:GetDescendants() do
			if part:HasTag("SD_LaunchBoard") then
				table.insert(boards, part :: BasePart)
			end
		end
		expect.equal(#boards, 1)
		local byName: { [string]: TextLabel } = {}
		for _, label in boards[1]:GetDescendants() do
			if label:IsA("TextLabel") then
				byName[label.Name] = label
			end
		end
		expect.equal(byName.Title.Text, "LAUNCH BOARD")
		expect.equal(byName.LastHeading.Text, "LAST THROWS")
		expect.equal(byName.BestHeading.Text, "SERVER BEST")
		for _, name in H.boardSlots do
			expect.equal(byName[name].Text, "")
			expect.equal(byName[name]:GetAttribute("SD_TextKey"), nil) -- live: never re-applied by WorldBinder
			expect.falsy(byName[name]:HasTag("SD_Sign"))
		end
		-- Pens3 phase 13: 3 rows in the LAST column (left of the divider), newest on top, each a name beside its
		-- distance on one line; the server best keeps v6's two lines in its own column (P3D:287-289).
		for row = 1, H.boardRows do
			local who, distance = byName[`Last{row}Who`], byName[`Last{row}Distance`]
			expect.truthy(who.Position.Y.Scale == distance.Position.Y.Scale)
			expect.truthy(who.Position.X.Scale < distance.Position.X.Scale)
			expect.truthy(distance.Position.X.Scale + distance.Size.X.Scale / 2 < 0.5)
			if row > 1 then
				expect.truthy(who.Position.Y.Scale > byName[`Last{row - 1}Who`].Position.Y.Scale)
			end
		end
		expect.truthy(byName.BestWho.Position.X.Scale > 0.5)
		expect.equal(byName.LastWho, nil) -- phase 12's single LAST line is gone
		-- The board faces the deck (the gate is turned 180°, L:33).
		expect.truthy(boards[1].CFrame.LookVector:Dot(origin.LookVector) < -0.99)
	end)

	t.test("the Kitty Bread mascot slot on top of the gate, 11 studs wide, facing the deck (LK:173-175)", function()
		local gate = deck:FindFirstChild("launch_gate_01") :: Model
		local found = gate:FindFirstChild("gate_mascot")
		expect.truthy(found ~= nil and found:IsA("Model"))
		local mascot = found :: Model
		local parts: { BasePart } = {}
		for _, part in mascot:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				table.insert(parts, part)
			end
		end
		if #parts == 0 then
			-- Allowed (an empty named slot) only with a warning that says so.
			local warned = false
			for _, line in warnings do
				warned = warned or string.find(line, "gate_mascot", 1, true) ~= nil
			end
			expect.truthy(warned)
			return
		end
		local low, high = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, part in parts do
			local cf, half = part.CFrame, part.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local p = origin:PointToObjectSpace(cf:PointToWorldSpace(half * Vector3.new(sx, sy, sz)))
						low, high = low:Min(p), high:Max(p)
					end
				end
			end
		end
		expect.truthy(near(high.X - low.X, 11, 0.6)) -- LK:175: scaled to 11 studs wide (its boxes, not its curves)
		expect.truthy(near(low.Y, 50, 0.6)) -- standing on the gate's top (LK:173: y 50)
		expect.truthy(mascot:GetPivot().LookVector:Dot(origin.LookVector) < -0.99) -- facing the deck
		expect.equal(mascot:GetAttribute("SD_BlueprintId"), "kitty_bread")
	end)

	-- P13v4 (owner 2026-10-19: the TikTok throw's rings and BULLSEYE targets; WorldLayout.Highway.rings / pads).
	t.test("p13v4: 3 glowing rings around the lane's axis and 2 target pads a biome, where WorldLayout says", function()
		local Palette = t.requireShared("Art/Palette")
		local ringIndex, padIndex = 0, 0
		for index, name in BIOME_MODELS do
			local biome = root:FindFirstChild(name) :: Model
			local rings = pieces(biome, "flight_ring")
			local pads = pieces(biome, "flight_pad")
			expect.equal(#rings, RINGS_PER_BIOME)
			expect.equal(#pads, PADS_PER_BIOME)
			for _, ring in rings do
				ringIndex += 1
				local spec = H.rings[ringIndex]
				expect.equal(spec.biome, index)
				expect.equal(ring.Name, string.format("flight_ring_%02d", ringIndex))
				expect.equal(ring:GetAttribute("Distance"), spec.d)
				expect.equal(ring.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
				local at = laneOf(ring)
				expect.truthy(near(at.X, 0) and near(at.Y, spec.y) and near(at.Z, spec.d))
				local rods = 0
				for _, part in ring:GetDescendants() do
					if part:IsA("BasePart") then
						rods += 1
						local p = origin:PointToObjectSpace(part.CFrame.Position)
						-- On the ring's circle, in the plane across the lane (its axis along the lane).
						expect.near(math.sqrt(p.X ^ 2 + (p.Y - spec.y) ^ 2), H.ringRadius, 0.05)
						expect.near(-p.Z, spec.d, 0.01)
						expect.near(math.abs(part.CFrame.XVector:Dot(origin.LookVector)), 0, 1e-3) -- tangent to it
						expect.equal(part.Material, Enum.Material.Neon)
						expect.equal(part.Color, Palette.HighwayGlow)
						expect.falsy(part.CanCollide)
					end
				end
				expect.equal(rods, ROD_COUNT)
			end
			for _, pad in pads do
				padIndex += 1
				local spec = H.pads[padIndex]
				expect.equal(spec.biome, index)
				expect.equal(pad.Name, string.format("flight_pad_%02d", padIndex))
				expect.equal(pad:GetAttribute("Distance"), spec.d)
				expect.equal(pad.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
				local radii: { number } = {}
				for _, part in pad:GetDescendants() do
					if part:IsA("BasePart") then
						local p = origin:PointToObjectSpace(part.CFrame.Position)
						expect.truthy(near(p.X, 0) and near(-p.Z, spec.d))
						expect.equal((part :: Part).Shape, Enum.PartType.Cylinder)
						expect.near(p.Y - part.Size.X / 2, 1, 1e-3) -- flat on the lane's top
						expect.falsy(part.CanCollide)
						table.insert(radii, part.Size.Y / 2)
					end
				end
				table.sort(radii)
				expect.deepEqual(radii, { 5, 10, 15 })
			end
		end
		expect.equal(ringIndex, #H.rings)
		expect.equal(padIndex, #H.pads)
	end)

	t.test("every part is placed from the origin: all of them lie in the lane-local corridor", function()
		-- The deck and the lane's own pieces lie within x ±201, y -3..70; the rest reaches farther: Claude Design's zones
		-- (highway v2) to their outside's 900 studs across (kit-build.js:161) and from the cloud sea (y -36) to Frozen
		-- Dessert Peaks' summits (217 up), the arches over the walls, the highest ring's top 71.6 up (d 426).
		local LANE = {
			lane_tile = true,
			rr_rainbow_lane = true,
			lane_rail = true,
			distance_marker = true,
			flight_pad = true,
		}
		local outside: { string } = {}
		for _, part in root:GetDescendants() do
			if part:IsA("BasePart") then
				local node: Instance = part -- its piece: the child of the deck or of a biome
				while node.Parent and node.Parent.Parent ~= root do
					node = node.Parent
				end
				local wide, low, high = 201, -3, 70
				if node.Parent ~= deck and not LANE[node:GetAttribute("SD_Piece")] then
					wide, low, high = 910, -40, 230
				end
				local p = origin:PointToObjectSpace(part.CFrame.Position)
				if math.abs(p.X) > wide or p.Y < low or p.Y > high or p.Z > 61 or p.Z < -(gatesAt + 30) then
					table.insert(outside, part:GetFullName())
				end
			end
		end
		expect.deepEqual(outside, {})
	end)

	t.test("only the deck's walk pieces collide; every part anchored, untouched, no shadow under 2 studs", function()
		local problems: { string } = {}
		for _, part in root:GetDescendants() do
			if part:IsA("BasePart") then
				if part.CanCollide and not part:IsDescendantOf(deck) then
					table.insert(problems, part:GetFullName() .. " collides")
				end
				if not part.Anchored or part.CanTouch then
					table.insert(problems, part:GetFullName() .. " unanchored or touched")
				end
				if part.CastShadow and math.max(part.Size.X, part.Size.Y, part.Size.Z) < 2 then
					table.insert(problems, part:GetFullName() .. " casts a shadow")
				end
			end
		end
		expect.deepEqual(problems, {})
		local platform = deck:FindFirstChild("launch_platform_01") :: Model
		expect.truthy((platform:FindFirstChild("deck_top") :: BasePart).CanCollide) -- v6 "walk" (L:20)
	end)

	t.test("pieces per biome within v6's 600 (spec.txt:157); the part counts pinned", function()
		for index, name in BIOME_MODELS do
			local biome = root:FindFirstChild(name) :: Model
			local n = #pieces(biome)
			expect.truthy(n <= MAX_PIECES)
			expect.equal(n, PIECES[index])
			expect.equal(countParts(biome), PARTS[index])
		end
	end)

	t.test("two builds give the same tree", function()
		local again = build()
		local a, b = dump(root), dump(again)
		again:Destroy()
		expect.equal(#a, #b)
		expect.truthy(a == b)
	end)

	t.test("Verify passes on the build and catches a broken one", function()
		expect.deepEqual(Verify.verify("highway", root, { Shared = t.Shared }), {})
		local function caught(change: (Model) -> (), words: string)
			local copy = root:Clone()
			change(copy)
			local problems = Verify.verify("highway", copy, { Shared = t.Shared })
			copy:Destroy()
			local found = false
			for _, line in problems do
				found = found or string.find(line, words, 1, true) ~= nil
			end
			if not found then
				error(`expected a problem with "{words}", got: {table.concat(problems, " | ")}`)
			end
		end
		caught(function(copy)
			for _, label in copy:GetDescendants() do
				if label:IsA("TextLabel") and label.Name == "Last2Who" then
					label:Destroy()
				end
			end
		end, "Last2Who")
		caught(function(copy)
			local lane = (copy:FindFirstChild("Biome_2_BT") :: Model):FindFirstChild("lane_tile_07") :: Model
			(lane:FindFirstChildWhichIsA("BasePart") :: BasePart).CanCollide = true
		end, "collides")
		caught(function(copy)
			local lane = (copy:FindFirstChild("Biome_1_CM") :: Model):FindFirstChild("lane_tile_01") :: Model
			(lane:FindFirstChildWhichIsA("BasePart") :: BasePart).Anchored = false
		end, "Anchored")
		caught(function(copy)
			local biome = copy:FindFirstChild("Biome_3_BL") :: Model
			local tile = biome:FindFirstChild("lane_tile_17") :: Model
			for _ = 1, MAX_PIECES do
				tile:Clone().Parent = biome
			end
		end, "pieces")
		caught(function(copy)
			for _, label in copy:GetDescendants() do
				if label:IsA("TextLabel") and label.Name == "BestDistance" then
					label.Text = "1,000 studs"
				end
			end
		end, "BestDistance")
		caught(function(copy)
			(copy:FindFirstChild("Biome_4_FD") :: Instance):Destroy()
		end, "Biome_4_FD")
		-- P13v4: a missing ring, a ring moved off its place, a missing pad, a biome that streams out.
		caught(function(copy)
			((copy:FindFirstChild("Biome_2_BT") :: Model):FindFirstChild("flight_ring_05") :: Instance):Destroy()
		end, "flight_ring")
		caught(function(copy)
			local ring = (copy:FindFirstChild("Biome_1_CM") :: Model):FindFirstChild("flight_ring_02") :: Model
			ring:SetAttribute("Distance", 170)
		end, "flight_ring")
		caught(function(copy)
			((copy:FindFirstChild("Biome_7_DH") :: Model):FindFirstChild("flight_pad_14") :: Instance):Destroy()
		end, "flight_pad")
		caught(function(copy)
			(copy:FindFirstChild("Biome_5_LV") :: Model).ModelStreamingMode = Enum.ModelStreamingMode.Default
		end, "Persistent")
		caught(function(copy) -- a 4th light (L:2, :4, :5 are the 3)
			local light = Instance.new("PointLight")
			light.Shadows = false
			light.Parent = (copy:FindFirstChild("Biome_1_CM") :: Model):FindFirstChildWhichIsA("BasePart", true)
		end, "lights")
	end)

	t.test("the build report counts the parts of the deck and of every biome against the 600-piece cap", function()
		local report = ""
		for _, line in warnings do
			if string.find(line, "highway report", 1, true) then
				report = line
			end
		end
		expect.truthy(string.find(report, "Biome_7_DH", 1, true) ~= nil)
		expect.truthy(string.find(report, "cap 600", 1, true) ~= nil)
	end)

	t.test("a mascot that cannot be built leaves the empty gate_mascot slot and warns with the real error", function()
		local SquishyBuilder = t.requireShared("Art/SquishyBuilder")
		local original = SquishyBuilder.build
		-- The measuring build (scale 1) fails, then only the scaled build fails.
		for _, scaledOnly in { false, true } do
			SquishyBuilder.build = function(id: string, mode: string, scale: number?, options: any?): Model
				if (scale ~= 1) == scaledOnly then
					error("mascot build broke")
				end
				return original(id, mode, scale, options)
			end
			local scratch = Cleanup.new()
			local ok, result = pcall(HighwayBuilder.build, { scratch = scratch, Shared = t.Shared })
			SquishyBuilder.build = original
			scratch:clean()
			if not ok or not result.ok then
				error("HighwayBuilder.build failed: " .. tostring(if ok then result.error else result))
			end
			local gate = ((result.root :: Model):FindFirstChild("Deck") :: Model):FindFirstChild("launch_gate_01")
			local slot = (gate :: Model):FindFirstChild("gate_mascot")
			expect.truthy(slot ~= nil and slot:IsA("Model") and #slot:GetDescendants() == 0)
			local warned = false
			for _, line in result.warnings do
				warned = warned
					or string.find(line, "gate_mascot", 1, true) ~= nil
						and string.find(line, "mascot build broke", 1, true) ~= nil
			end
			expect.truthy(warned)
			result.root:Destroy()
		end
	end)

	-- Last: until here the clone is in use.
	root:Destroy()
	tools:Destroy()
end
