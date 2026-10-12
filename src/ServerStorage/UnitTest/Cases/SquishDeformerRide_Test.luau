--!strict
-- SquishDeformerRide_Test: unit tests for StarterPlayerScripts.Client.Anim.SquishDeformer's setOffsets, the ride that
-- carries face and detail parts on Inspect's knead shell (spec phase2-squeeze §3.2). Server only
-- (ServerStorage.UnitTest). Edit mode: a hand-built model (a Root and a turned SpecialMesh part). Contract:
--   * with offsets set, the next apply writes Offset = base + R⁻¹(p ∘ S - p) + R⁻¹(o ∘ S), even with S at rest and the
--     looks at rest (a model with offsets never rests);
--   * a part without an offset keeps the plain formula; setOffsets(nil) brings the base Offset back on the next apply;
--   * the table is read on every write (the owner updates it in place).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local SquishDeformer = t.requireClient("Anim/SquishDeformer")
	local SquishRig = t.requireClient("Anim/SquishRig")
	local expect = t.expect

	local function model(): (Model, BasePart, SpecialMesh, BasePart, SpecialMesh)
		local root = Instance.new("Part")
		root.Name = "Root"
		root.CFrame = CFrame.identity
		local m = Instance.new("Model")
		root.Parent = m
		m.PrimaryPart = root
		local function meshPart(name: string, cframe: CFrame): (BasePart, SpecialMesh)
			local part = Instance.new("Part")
			part.Name = name
			part.Size = Vector3.new(0.2, 0.2, 0.1)
			part.CFrame = cframe
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
			part.Parent = m
			return part, mesh
		end
		local eye, eyeMesh = meshPart("Eye", CFrame.new(0.3, 0.2, -0.5) * CFrame.Angles(0, math.rad(90), 0))
		local curl, curlMesh = meshPart("Curl", CFrame.new(-0.2, 0.6, 0))
		return m, eye, eyeMesh, curl, curlMesh
	end

	local function near(a: Vector3, b: Vector3)
		expect.near((a - b).Magnitude, 0, 1e-5)
	end

	t.test("an offset rides on the next apply, even at rest; others keep the plain formula", function()
		local m, eye, eyeMesh, _, curlMesh = model()
		local deformer = SquishDeformer.attach(m, {})
		local out = SquishRig.newOut()
		local offsets = { [eye] = Vector3.new(0, 0, -0.1) }
		deformer:setOffsets(offsets)
		deformer:apply(out)
		near(eyeMesh.Offset, eye.CFrame:VectorToObjectSpace(Vector3.new(0, 0, -0.1)))
		near(curlMesh.Offset, Vector3.zero)
		expect.falsy(deformer:isResting())
		-- With a squash: base + R⁻¹(p ∘ S - p) + R⁻¹(o ∘ S).
		local S = Vector3.new(1.2, 0.8, 1.2)
		out.S = S
		offsets[eye] = Vector3.new(0.05, 0, -0.1) -- updated in place
		deformer:apply(out)
		local p = eye.CFrame.Position
		local expected = eye.CFrame:VectorToObjectSpace(p * S - p)
			+ eye.CFrame:VectorToObjectSpace(Vector3.new(0.05, 0, -0.1) * S)
		near(eyeMesh.Offset, expected)
		deformer:destroy()
		m:Destroy()
	end)

	t.test("setOffsets(nil): the base Offset comes back and the model rests again", function()
		local m, eye, eyeMesh = model()
		local deformer = SquishDeformer.attach(m, {})
		local out = SquishRig.newOut()
		deformer:setOffsets({ [eye] = Vector3.new(0, 0.1, 0) })
		deformer:apply(out)
		expect.truthy(eyeMesh.Offset.Magnitude > 0.05)
		deformer:setOffsets(nil)
		deformer:apply(out)
		near(eyeMesh.Offset, Vector3.zero)
		expect.truthy(deformer:isResting())
		deformer:destroy()
		m:Destroy()
	end)
end
