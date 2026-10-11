--!strict
-- Builders_Test: smoke tests for the Part 3 world generators in ServerStorage.SDTools.Builders. Server only
-- (ServerStorage.UnitTest). Each builder runs exactly as Main's pipeline runs it (§1.7 step 3): build(ctx) with a
-- scratch Cleanup and the Shared folder under test, on an UNPARENTED tree. The result must be ok, unparented, marked
-- with its generator id and VERSION, and pass Verify with that same Shared (Strings, World/WorldLayout).
-- Nothing is parented into the place and every tree is destroyed afterwards.
-- ArenaBuilder cases also pin the §5.3 / §7.8 contract details the runtime relies on: pad facing, divider and barrier
-- collision groups, dividers wall to wall, floor out to the walls, point-symmetric cover (pieces named after
-- WorldLayout.Arena.cover), the wall stripes (WorldLayout.Arena.wallStripes, §18.3.4), the Runtime folder and the
-- part budget.
-- LobbyBuilder is written by another Part 3 helper; until it exists its smoke case fails with "not found".

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
}

type Built = {
	builder: any,
	root: Instance,
	warnings: { string },
}

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local function loadTools(): (Instance, any)
	local source = ServerStorage:FindFirstChild("SDTools")
	if source == nil then
		error("ServerStorage.SDTools not found (is Rojo connected?)")
	end
	local clone = source:Clone()
	local verify = clone:FindFirstChild("Verify")
	if verify == nil or not verify:IsA("ModuleScript") then
		clone:Destroy()
		error("SDTools.Verify is missing")
	end
	return clone, dynamicRequire(verify)
end

return function(t: Context)
	local tools, Verify = loadTools()
	local Cleanup = t.requireShared("Util/Cleanup")
	local expect = t.expect

	-- Builds `name` like Main does and returns the handed-over root (the caller destroys it).
	local function build(name: string, generatorId: string): Built
		local builders = tools:FindFirstChild("Builders")
		local module = if builders then builders:FindFirstChild(name) else nil
		if module == nil or not module:IsA("ModuleScript") then
			error(string.format("SDTools.Builders.%s not found", name))
		end
		local shared = t.Shared
		if shared == nil then
			error("no Shared folder under test")
		end
		local builder = dynamicRequire(module)
		expect.equal(type(builder.build), "function")
		expect.equal(type(builder.VERSION), "number")
		local scratch = Cleanup.new()
		local ok, result = pcall(builder.build, { scratch = scratch, Shared = shared })
		if not ok or not result.ok or result.root == nil then
			scratch:clean()
			error(string.format("%s.build failed: %s", name, if ok then tostring(result.error) else tostring(result)))
		end
		local root = result.root :: Instance
		-- The builder hands the root over on success, so cleaning the scratch must not destroy it.
		scratch:clean()
		expect.equal(root.Parent, nil)
		expect.equal(root:GetAttribute("SD_GeneratorId"), generatorId)
		expect.equal(root:GetAttribute("SD_GeneratorVersion"), builder.VERSION)
		return { builder = builder, root = root, warnings = result.warnings }
	end

	-- Errors with every problem line; returns true when Verify is clean (a value, so pcall returns two).
	local function expectVerified(target: string, root: Instance): boolean
		local problems = Verify.verify(target, root, { Shared = t.Shared })
		if #problems > 0 then
			error(string.format("Verify(%s) found %d problem(s): %s", target, #problems, table.concat(problems, " | ")))
		end
		return true
	end

	t.test("ArenaBuilder builds an unparented, marked template that passes Verify", function()
		local built = build("ArenaBuilder", "arena")
		local ok, err = pcall(expectVerified, "arena", built.root)
		local warnings = table.concat(built.warnings, " | ")
		built.root:Destroy()
		if not ok then
			error(tostring(err) .. (if warnings ~= "" then " (build warnings: " .. warnings .. ")" else ""))
		end
	end)

	t.test("ArenaBuilder: pads face each other along Z and lie on the floor", function()
		local root = build("ArenaBuilder", "arena").root
		local spawns = root:FindFirstChild("Spawns") :: Instance
		local padA = spawns:FindFirstChild("PadA") :: BasePart
		local padB = spawns:FindFirstChild("PadB") :: BasePart
		local facingA, facingB = padA.CFrame.LookVector, padB.CFrame.LookVector
		local a, b = padA.CFrame.Position, padB.CFrame.Position
		root:Destroy()
		expect.near(facingA.Z, 1, 1e-3)
		expect.near(facingB.Z, -1, 1e-3)
		expect.near(a.Z, -44, 1e-3)
		expect.near(b.Z, 44, 1e-3)
		expect.near((a - b).Magnitude, 88, 1e-3)
		expect.falsy(padA:IsA("SpawnLocation"))
	end)

	t.test("ArenaBuilder: dividers are the only SD_Divider parts and sit at Z +-8", function()
		local built = build("ArenaBuilder", "arena")
		local positions: { number } = {}
		for _, descendant in built.root:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.CollisionGroup == "SD_Divider" then
				table.insert(positions, descendant.CFrame.Position.Z)
			end
		end
		built.root:Destroy()
		table.sort(positions)
		if #positions ~= 2 then
			error(
				string.format(
					"expected 2 SD_Divider parts, found %d (build warnings: %s)",
					#positions,
					table.concat(built.warnings, " | ")
				)
			)
		end
		expect.near(positions[1], -8, 1e-3)
		expect.near(positions[2], 8, 1e-3)
	end)

	-- Roblox ignores CanQuery = false on colliding parts: the walls and the ceiling stay out of Default-group projectile
	-- rays only through a collision group that collides with characters alone (§5.3 "not hit by projectiles").
	t.test("ArenaBuilder: walls and ceiling are the SD_Barrier parts; dividers span the court to the walls", function()
		local built = build("ArenaBuilder", "arena")
		local barrierNames: { string } = {}
		local dividerWidths: { number } = {}
		for _, descendant in built.root:GetDescendants() do
			if descendant:IsA("BasePart") then
				if descendant.CollisionGroup == "SD_Barrier" then
					table.insert(barrierNames, descendant.Name)
					expect.equal(descendant.CanCollide, true)
					expect.equal(descendant.Transparency, 1)
				elseif descendant.CollisionGroup == "SD_Divider" then
					table.insert(dividerWidths, descendant.Size.X)
				end
			end
		end
		local warnings = table.concat(built.warnings, " | ")
		built.root:Destroy()
		table.sort(barrierNames)
		if #barrierNames ~= 5 then
			error(string.format("expected 5 SD_Barrier parts, found %d (build warnings: %s)", #barrierNames, warnings))
		end
		expect.deepEqual(barrierNames, { "Ceiling", "WallEast", "WallEndA", "WallEndB", "WallWest" })
		for _, width in dividerWidths do
			expect.near(width, 76, 1e-3) -- X -38..38: wall to wall
		end
	end)

	t.test("ArenaBuilder: the floor reaches the barrier walls behind every rail", function()
		local root = build("ArenaBuilder", "arena").root
		local floor = (root:FindFirstChild("Geometry") :: Instance):FindFirstChild("Floor") :: Instance
		local function covered(x: number, z: number): boolean
			for _, part in floor:GetChildren() do
				if part:IsA("BasePart") and part.CanCollide then
					local p = part.CFrame:PointToObjectSpace(Vector3.new(x, -0.5, z))
					local half = part.Size / 2
					if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
						return true
					end
				end
			end
			return false
		end
		-- Between each rail's outer face and its wall (X 36.8..38, Z 52.8..54), and the corners.
		local points = {
			Vector3.new(37.4, 0, 0),
			Vector3.new(-37.4, 0, 0),
			Vector3.new(37.4, 0, -8),
			Vector3.new(0, 0, 53.4),
			Vector3.new(0, 0, -53.4),
			Vector3.new(37.4, 0, 53.4),
			Vector3.new(-37.4, 0, -53.4),
		}
		local missing = {}
		for _, point in points do
			if not covered(point.X, point.Z) then
				table.insert(missing, string.format("(%g, %g)", point.X, point.Z))
			end
		end
		root:Destroy()
		expect.deepEqual(missing, {})
	end)

	t.test("ArenaBuilder: 12 Atomic cover pieces, Side A the point reflection of Side B", function()
		local root = build("ArenaBuilder", "arena").root
		local cover = (root:FindFirstChild("Geometry") :: Instance):FindFirstChild("Cover") :: Instance
		local pieces = cover:GetChildren()
		local count = #pieces
		local mismatched: { string } = {}
		for _, piece in pieces do
			local name = piece.Name
			expect.equal((piece :: Model).ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
			-- WorldLayout names a piece and its point reflection alike: B_Wall1 <-> A_Wall1.
			if string.sub(name, 1, 8) == "Cover_B_" then
				local twinName = "Cover_A_" .. string.sub(name, 9)
				local twin = cover:FindFirstChild(twinName)
				local body = piece:FindFirstChild("Body") :: BasePart?
				local twinBody = if twin then twin:FindFirstChild("Body") :: BasePart? else nil
				if body == nil or twinBody == nil then
					table.insert(mismatched, name .. " (no twin " .. twinName .. ")")
				else
					local p, q = body.CFrame.Position, twinBody.CFrame.Position
					if (Vector3.new(-p.X, p.Y, -p.Z) - q).Magnitude > 1e-3 then
						table.insert(mismatched, name)
					end
				end
			end
		end
		root:Destroy()
		expect.equal(count, 12)
		expect.deepEqual(mismatched, {})
	end)

	-- Feel pass (§18.3.4): the stripe constants moved to WorldLayout.Arena.wallStripes with identical values, and the
	-- builder reads them, so the built arena does not change.
	t.test("ArenaBuilder: the wall stripes equal WorldLayout.Arena.wallStripes", function()
		local stripes = t.requireShared("World/WorldLayout").Arena.wallStripes
		expect.deepEqual(stripes, { heights = { 2, 4, 6 }, thickness = 0.5, proud = 0.1, insetX = 0.02 })
		local root = build("ArenaBuilder", "arena").root
		local cover = (root:FindFirstChild("Geometry") :: Instance):FindFirstChild("Cover") :: Instance
		local problems: { string } = {}
		local walls = 0
		for _, piece in cover:GetChildren() do
			if string.find(piece.Name, "_Wall", 1, true) == nil then
				continue
			end
			walls += 1
			local body = piece:FindFirstChild("Body") :: BasePart
			local bottom = body.Position.Y - body.Size.Y / 2
			local found = 0
			for _, child in piece:GetChildren() do
				if string.sub(child.Name, 1, 7) == "Stripe_" then
					found += 1
				end
			end
			if found ~= #stripes.heights then
				table.insert(problems, `{piece.Name}: {found} stripes`)
			end
			for index, height in stripes.heights do
				local stripe = piece:FindFirstChild("Stripe_" .. index) :: BasePart?
				if stripe == nil then
					table.insert(problems, `{piece.Name}: no Stripe_{index}`)
					continue
				end
				local size = Vector3.new(body.Size.X - stripes.insetX, stripes.thickness, body.Size.Z + stripes.proud)
				local position = Vector3.new(body.Position.X, bottom + height, body.Position.Z)
				if (stripe.Size - size).Magnitude > 1e-3 or (stripe.Position - position).Magnitude > 1e-3 then
					table.insert(problems, `{piece.Name}.Stripe_{index}: {stripe.Size} at {stripe.Position}`)
				end
			end
		end
		root:Destroy()
		expect.equal(walls, 4)
		expect.deepEqual(problems, {})
	end)

	t.test("ArenaBuilder: Runtime is empty and the template stays within 400 parts", function()
		local root = build("ArenaBuilder", "arena").root
		local runtime = root:FindFirstChild("Runtime")
		local runtimeChildren = if runtime then #runtime:GetChildren() else -1
		local parts = 0
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("BasePart") then
				parts += 1
			end
		end
		root:Destroy()
		expect.equal(runtimeChildren, 0)
		expect.truthy(parts > 0 and parts <= 400)
	end)

	t.test("LobbyBuilder builds an unparented, marked lobby that passes Verify", function()
		local built = build("LobbyBuilder", "lobby")
		local ok, err = pcall(expectVerified, "lobby", built.root)
		local warnings = table.concat(built.warnings, " | ")
		built.root:Destroy()
		if not ok then
			error(tostring(err) .. (if warnings ~= "" then " (build warnings: " .. warnings .. ")" else ""))
		end
	end)

	tools:Destroy()
end
