--!strict
-- Flicker_Test: no two visible faces of different colours lie in one plane in the lobby or any arena (user bug report
-- 2026-10-11: "all the platforms flicker"; a rim flush with its dais, markings 0.005 apart). Server only
-- (ServerStorage.UnitTest). Each builder runs as Main runs it, on an UNPARENTED tree that is destroyed afterwards.
-- The check: every flat face (block faces, cylinder caps) that faces up or sideways, of a part that shows
-- (Transparency < 0.95), outside toy blueprint models (SD_BlueprintId) and mesh-shaped parts (a SpecialMesh / FileMesh
-- child: ellipsoids and wedges are not their box); two faces fight when they face the same way, lie less than
-- MIN_GAP apart and overlap (separating axes in their plane), with a different colour or material. Faces facing down
-- rest on something and are left out. SDTools Kit/Prims.LAYER (0.03) is the gap the builders keep.

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
}

type Face = {
	part: BasePart,
	n: Vector3,
	d: number,
	c: Vector3,
	u: Vector3,
	v: Vector3,
	hu: number,
	hv: number,
	round: boolean,
	key: string,
}

local MIN_GAP = 0.02 -- closer than this, two faces flicker (the builders keep Prims.LAYER, 0.03)
local OVERLAP_SLACK = 0.02 -- faces that only touch along an edge do not fight

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local function inToyOrMesh(part: BasePart, root: Instance): boolean
	if part:FindFirstChildWhichIsA("DataModelMesh") then
		return true
	end
	local ancestor = part.Parent
	while ancestor and ancestor ~= root do
		if ancestor:GetAttribute("SD_BlueprintId") ~= nil then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function facesOf(root: Instance): { Face }
	local faces: { Face } = {}
	local function add(
		part: BasePart,
		n: Vector3,
		c: Vector3,
		u: Vector3,
		v: Vector3,
		hu: number,
		hv: number,
		round: boolean
	)
		if n.Y < -0.5 then
			return -- faces down: rests on something
		end
		table.insert(faces, {
			part = part,
			n = n,
			d = n:Dot(c),
			c = c,
			u = u,
			v = v,
			hu = hu,
			hv = hv,
			round = round,
			key = part.Color:ToHex() .. "/" .. part.Material.Name,
		})
	end
	for _, d in root:GetDescendants() do
		if not d:IsA("BasePart") or d:IsA("MeshPart") or d:IsA("Terrain") or d.Transparency >= 0.95 then
			continue
		end
		if inToyOrMesh(d, root) then
			continue
		end
		local cf, s = d.CFrame, d.Size
		local x, y, z = cf.RightVector, cf.UpVector, -cf.LookVector
		local shape = if d:IsA("Part") then d.Shape else Enum.PartType.Block
		if shape == Enum.PartType.Ball then
			continue
		elseif shape == Enum.PartType.Cylinder then
			local r = math.min(s.Y, s.Z) / 2
			add(d, x, cf.Position + x * (s.X / 2), y, z, r, r, true)
			add(d, -x, cf.Position - x * (s.X / 2), y, z, r, r, true)
		elseif shape == Enum.PartType.Block or d:IsA("PartOperation") then
			local sides: { { n: Vector3, len: number, u: Vector3, lu: number, v: Vector3, lv: number } } = {
				{ n = x, len = s.X, u = y, lu = s.Y, v = z, lv = s.Z },
				{ n = y, len = s.Y, u = x, lu = s.X, v = z, lv = s.Z },
				{ n = z, len = s.Z, u = x, lu = s.X, v = y, lv = s.Y },
			}
			for _, side in sides do
				local half = side.len / 2
				add(d, side.n, cf.Position + side.n * half, side.u, side.v, side.lu / 2, side.lv / 2, false)
				add(d, -side.n, cf.Position - side.n * half, side.u, side.v, side.lu / 2, side.lv / 2, false)
			end
		end
	end
	return faces
end

local function project(f: Face, axis: Vector3): (number, number)
	local centre = f.c:Dot(axis)
	if f.round then
		return centre - f.hu, centre + f.hu
	end
	local extent = math.abs(f.u:Dot(axis)) * f.hu + math.abs(f.v:Dot(axis)) * f.hv
	return centre - extent, centre + extent
end

local function overlaps(a: Face, b: Face): boolean
	for _, axis in { a.u, a.v, b.u, b.v } do
		local a0, a1 = project(a, axis)
		local b0, b1 = project(b, axis)
		if a1 <= b0 + OVERLAP_SLACK or b1 <= a0 + OVERLAP_SLACK then
			return false
		end
	end
	if a.round and b.round then
		return (a.c - b.c).Magnitude < a.hu + b.hu - OVERLAP_SLACK
	end
	return true
end

-- The fighting pairs as "partA | partB" lines (paths under the root).
local function flickerPairs(root: Instance): { string }
	local buckets: { [string]: { Face } } = {}
	for _, f in facesOf(root) do
		local key = string.format("%d,%d,%d", math.round(f.n.X * 100), math.round(f.n.Y * 100), math.round(f.n.Z * 100))
		local list = buckets[key]
		if list == nil then
			list = {}
			buckets[key] = list
		end
		table.insert(list, f)
	end
	local lines: { string } = {}
	for _, list in buckets do
		table.sort(list, function(p, q)
			return p.d < q.d
		end)
		for i = 1, #list do
			local a = list[i]
			local j = i + 1
			while j <= #list and list[j].d - a.d < MIN_GAP do
				local b = list[j]
				if a.part ~= b.part and a.key ~= b.key and overlaps(a, b) then
					table.insert(lines, a.part:GetFullName() .. " | " .. b.part:GetFullName())
				end
				j += 1
			end
		end
	end
	table.sort(lines)
	return lines
end

return function(t: Context)
	local source = ServerStorage:FindFirstChild("SDTools")
	if source == nil then
		error("ServerStorage.SDTools not found")
	end
	local tools = source:Clone()
	local Cleanup = t.requireShared("Util/Cleanup")
	local expect = t.expect

	local function build(module: Instance?): Instance
		if module == nil or not module:IsA("ModuleScript") then
			error("builder not found")
		end
		local scratch = Cleanup.new()
		local ok, result = pcall(dynamicRequire(module).build, { scratch = scratch, Shared = t.Shared })
		if not ok or not result.ok or result.root == nil then
			scratch:clean()
			error(
				string.format(
					"%s.build failed: %s",
					module.Name,
					if ok then tostring(result.error) else tostring(result)
				)
			)
		end
		scratch:clean()
		return result.root :: Instance
	end

	local function expectNoFlicker(module: Instance?)
		local root = build(module)
		local lines = flickerPairs(root)
		root:Destroy()
		if #lines > 0 then
			local shown = table.concat(lines, "; ", 1, math.min(#lines, 8))
			error(string.format("%d face pair(s) in one plane (flicker): %s", #lines, shown))
		end
		expect.equal(#lines, 0)
	end

	local builders = tools:FindFirstChild("Builders") :: Instance
	local arenas = builders:FindFirstChild("Arenas")

	t.test("the lobby has no two faces of different colours in one plane", function()
		expectNoFlicker(builders:FindFirstChild("LobbyBuilder"))
	end)

	t.test("Candy Court has no two faces of different colours in one plane", function()
		expectNoFlicker(builders:FindFirstChild("ArenaBuilder"))
	end)

	t.test("the five design arenas have no two faces of different colours in one plane", function()
		for _, name in { "SweetshopStadium", "PinewoodCamp", "PillowFortPark", "BubbleReefCourt", "ArcadeToyworks" } do
			expectNoFlicker(if arenas then arenas:FindFirstChild(name) else nil)
		end
	end)

	t.test(
		"the check finds a rim flush with its dais (the reported bug) and passes once it sits LAYER lower",
		function()
			local model = Instance.new("Model")
			local function disc(name: string, radius: number, top: number, colour: Color3): Part
				local p = Instance.new("Part")
				p.Name = name
				p.Shape = Enum.PartType.Cylinder
				p.Size = Vector3.new(1, 2 * radius, 2 * radius)
				p.CFrame = CFrame.new(0, top - 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
				p.Color = colour
				p.Parent = model
				return p
			end
			disc("dais", 14.5, 0.7, Color3.new(1, 1, 1))
			local rim = disc("rim", 14.8, 0.7, Color3.new(1, 0.4, 0.6))
			expect.equal(#flickerPairs(model), 1)
			rim.CFrame += Vector3.new(0, -0.03, 0)
			expect.equal(#flickerPairs(model), 0)
			model:Destroy()
		end
	)
end
