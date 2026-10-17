--!strict
-- BoxModels_Test: ReplicatedStorage.Shared.Art.BoxBuilder and the three box blueprints (Art/BoxSoft, BoxSweet, BoxRoyal;
-- UI FINAL R7 G7.9, `stage:n` = Diego's uploads/box-stage.html line n). Server only (ServerStorage.UnitTest), Edit mode.
-- Contract:
--   * every box id has its blueprint (snack -> soft, sweet -> sweet, treat -> royal); nodes come after their parents;
--     part names are unique; every part's node exists and its colour is an Art/Palette name;
--   * the sizes and hinges are the design's (stage:104, 114, 130, 138, 160, 170) and each box has the groups the
--     timeline drives (base, hinge, lid; Soft's ears, Royal's crown, seam and keyhole);
--   * build makes one anchored, non-colliding part per spec (a Tri two), each tagged with its node, at rest at the
--     origin; write() with no squash keeps the rest, the hinge's swing moves only the lid's parts, and a squash scales
--     the positions about the floor.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local BoxBuilder = t.requireShared("Art/BoxBuilder")
	local Palette = t.requireShared("Art/Palette")

	local KINDS = { snack = "soft", sweet = "sweet", treat = "royal" }

	local function lidNodes(bp: any): { [string]: boolean }
		local under: { [string]: boolean } = { hinge = true }
		for _, name in bp.order do
			local parent = bp.nodes[name].parent
			if parent and under[parent] then
				under[name] = true
			end
		end
		return under
	end

	t.test(
		"each box id has its blueprint, nodes after their parents, unique parts on known nodes, Palette colours",
		function()
			for boxId, kind in KINDS do
				local bp = BoxBuilder.blueprint(boxId)
				expect.truthy(bp ~= nil)
				expect.equal(bp.kind, kind)
				local seen: { [string]: boolean } = {}
				for _, name in bp.order do
					local node = bp.nodes[name]
					expect.truthy(node ~= nil)
					if node.parent then
						expect.truthy(seen[node.parent] == true)
					end
					seen[name] = true
				end
				for _, group in { "base", "hinge", "lid" } do
					expect.truthy(seen[group] == true)
				end
				local names: { [string]: boolean } = {}
				for _, spec in bp.parts do
					expect.falsy(names[spec.name])
					names[spec.name] = true
					expect.truthy(seen[spec.node] == true)
					expect.equal(typeof((Palette :: any)[spec.color]), "Color3")
				end
				for _, key in { bp.light, bp.beam } do
					expect.equal(typeof((Palette :: any)[key]), "Color3")
				end
				for _, key in bp.sparkles do
					expect.equal(typeof((Palette :: any)[key]), "Color3")
				end
			end
			expect.equal(BoxBuilder.blueprint("nope"), nil)
		end
	)

	t.test("the design's sizes, hinges and groups (stage:104-187)", function()
		local function part(bp: any, name: string): any
			for _, spec in bp.parts do
				if spec.name == name then
					return spec
				end
			end
			return nil
		end
		local soft = BoxBuilder.blueprint("snack")
		local function same(a: Vector3, b: Vector3)
			expect.truthy((a - b).Magnitude < 1e-5)
		end
		same(part(soft, "Body").size, Vector3.new(2, 1.5, 2))
		same(soft.nodes.hinge.pos, Vector3.new(0, 1.5, -1.08))
		expect.equal(soft.top, 1.5)
		expect.truthy(soft.nodes.earL ~= nil and soft.nodes.earR ~= nil)
		local sweet = BoxBuilder.blueprint("sweet")
		expect.near(part(sweet, "Core").size.Y, 1.3, 1e-5)
		same(sweet.nodes.hinge.pos, Vector3.new(0, 1.3, 0))
		local sprinkles = 0
		for _, spec in sweet.parts do
			if string.sub(spec.name, 1, 8) == "Sprinkle" then
				sprinkles += 1
			end
		end
		expect.equal(sprinkles, 90) -- stage:141
		local royal = BoxBuilder.blueprint("treat")
		same(part(royal, "Velvet").size, Vector3.new(2.4, 1.3, 1.6))
		same(royal.nodes.hinge.pos, Vector3.new(0, 1.3, -0.8))
		expect.truthy(royal.nodes.crown ~= nil)
		expect.truthy(part(royal, "Seam") ~= nil and part(royal, "Keyhole") ~= nil)
		expect.equal(part(royal, "Seam").transparency, 1)
	end)

	t.test("build: one anchored part per spec (a Tri two), tagged with its node; write keeps the rest", function()
		for boxId in KINDS do
			local bp = BoxBuilder.blueprint(boxId)
			local built = BoxBuilder.build(bp, 1)
			local parts = {}
			for _, child in built.model:GetChildren() do
				if child:IsA("BasePart") then
					table.insert(parts, child)
					expect.equal(child.Anchored, true)
					expect.equal(child.CanCollide, false)
					expect.truthy(BoxBuilder.nodeOf(child) ~= nil)
				end
			end
			expect.equal(#parts, BoxBuilder.partCount(bp))
			local before: { [Instance]: CFrame } = {}
			for _, p in parts do
				before[p] = p.CFrame
			end
			BoxBuilder.write(built, CFrame.identity, Vector3.one, nil)
			for _, p in parts do
				expect.truthy((p.CFrame.Position - before[p].Position).Magnitude < 1e-4)
			end
			-- the hinge's swing moves the lid's parts only
			local lid = lidNodes(bp)
			BoxBuilder.write(built, CFrame.identity, Vector3.one, { hinge = CFrame.Angles(-1, 0, 0) })
			for _, p in parts do
				local moved = (p.CFrame.Position - before[p].Position).Magnitude > 1e-3
				local node = BoxBuilder.nodeOf(p) :: string
				if not lid[node] then
					expect.falsy(moved)
				end
			end
			-- a squash about the floor: heights scale by y
			BoxBuilder.write(built, CFrame.identity, Vector3.new(1, 0.5, 1), nil)
			local body = built.named.Body or built.named.Core or built.named.Velvet
			expect.truthy(body ~= nil)
			expect.near(body.CFrame.Position.Y, before[body].Position.Y * 0.5, 1e-4)
			built.model:Destroy()
		end
	end)

	t.test("nodeFrames: a child node follows its parent's motion", function()
		local bp = BoxBuilder.blueprint("snack")
		local rest = BoxBuilder.nodeFrames(bp, 1, nil)
		local swung = BoxBuilder.nodeFrames(bp, 1, { hinge = CFrame.Angles(-0.5, 0, 0) })
		expect.truthy((rest.base.Position - swung.base.Position).Magnitude < 1e-9)
		expect.truthy((rest.lid.Position - swung.lid.Position).Magnitude > 0.1)
		expect.truthy((rest.earL.Position - swung.earL.Position).Magnitude > 0.1)
		local scaled = BoxBuilder.nodeFrames(bp, 2, nil)
		expect.truthy((scaled.hinge.Position - rest.hinge.Position * 2).Magnitude < 1e-9)
	end)
end
