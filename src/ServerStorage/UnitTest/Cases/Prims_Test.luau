--!strict
-- Prims_Test: unit tests for ServerStorage.SDTools.Kit.Prims, the primitive constructors of the world generators.
-- Server only (ServerStorage.UnitTest). Contract (DESIGN §7.7 props rules, §7.6 prompts, §8.1 #2 rounded boxes):
--   * flag presets: solid (collide + query), decor (neither), volume (invisible, nothing), barrier (invisible, collides,
--     never queried); every part anchored and never touched;
--   * an upright disc has its height on world Y; a prompt is DISABLED, keyed, and sits exactly at the requested world
--     point even on a rotated host; a rounded box falls back to a Brick SpecialMesh and a clone is stripped clean.
-- Every instance stays in memory and is destroyed.

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
}

local TOLERANCE = 1e-3 -- CFrames are stored in single precision

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local function loadPrims(): (any, Instance)
	local source = ServerStorage:FindFirstChild("SDTools")
	if source == nil then
		error("ServerStorage.SDTools not found (is Rojo connected?)")
	end
	local clone = source:Clone()
	local kit = clone:FindFirstChild("Kit")
	local module = if kit then kit:FindFirstChild("Prims") else nil
	if module == nil or not module:IsA("ModuleScript") then
		clone:Destroy()
		error("SDTools.Kit.Prims is missing")
	end
	return dynamicRequire(module), clone
end

return function(t: Context)
	local Prims, toolsClone = loadPrims()
	local expect = t.expect

	local function make(flags: string): Part
		return Prims.part({
			name = "P",
			size = Vector3.new(2, 3, 4),
			cframe = CFrame.new(1, 2, 3),
			flags = flags,
		})
	end

	t.test("flag presets (§7.7)", function()
		local cases = {
			{ flags = "solid", collide = true, query = true, transparency = 0 },
			{ flags = "decor", collide = false, query = false, transparency = 0 },
			{ flags = "volume", collide = false, query = false, transparency = 1 },
			{ flags = "barrier", collide = true, query = false, transparency = 1 },
		}
		for _, case in cases do
			local part = make(case.flags)
			expect.equal(part.Anchored, true)
			expect.equal(part.CanTouch, false)
			expect.equal(part.CanCollide, case.collide)
			expect.equal(part.CanQuery, case.query)
			expect.equal(part.Transparency, case.transparency)
			expect.equal(part.Material, Enum.Material.SmoothPlastic)
			part:Destroy()
		end
	end)

	t.test("an upright disc has its diameter on X and Z and its height on Y", function()
		local disc = Prims.disc("D", 8, 0.3, Vector3.new(5, 0.15, -2), Color3.new(1, 0, 0), "solid")
		expect.equal(disc.Shape, Enum.PartType.Cylinder)
		expect.near(disc.CFrame.RightVector.Y, 1, TOLERANCE) -- the cylinder axis (part X) points up
		expect.near(disc.Size.X, 0.3, TOLERANCE)
		expect.near(disc.Size.Y, 8, TOLERANCE)
		expect.near(disc.CFrame.Position.Y, 0.15, TOLERANCE)
		disc:Destroy()
	end)

	t.test("facing() looks along a horizontal direction, +Z included", function()
		for _, direction in { Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1) } do
			local frame = Prims.facing(Vector3.new(3, 4, 5), direction)
			expect.near((frame.LookVector - direction).Magnitude, 0, TOLERANCE)
			expect.near((frame.Position - Vector3.new(3, 4, 5)).Magnitude, 0, TOLERANCE)
		end
	end)

	t.test("a prompt is disabled, keyed and placed at the world point on a rotated host (§7.6)", function()
		local host = Prims.part({
			name = "Host",
			size = Vector3.new(3, 3.5, 12),
			cframe = CFrame.new(29.5, 1.75, -42) * CFrame.Angles(0, math.rad(37), 0),
		})
		local target = Vector3.new(28.5, 3, -42)
		local prompt = Prims.prompt(host, target, {
			actionText = "See Boxes",
			textKey = "prompt.seeBoxes",
			maxDistance = 12,
			lineOfSight = false,
		})
		expect.equal(prompt.Enabled, false)
		expect.equal(prompt.ActionText, "See Boxes")
		expect.equal(prompt:GetAttribute("SD_TextKey"), "prompt.seeBoxes")
		expect.equal(prompt.MaxActivationDistance, 12)
		expect.equal(prompt.RequiresLineOfSight, false)
		expect.equal(prompt.HoldDuration, 0)
		local attachment = prompt.Parent :: Attachment
		expect.truthy(attachment:IsA("Attachment") and attachment.Parent == host)
		expect.near(((host.CFrame * attachment.CFrame).Position - target).Magnitude, 0, TOLERANCE)
		host:Destroy()
	end)

	t.test("roundedBox without a template is a decor Part with a Brick mesh", function()
		local part, fallback = Prims.roundedBox(nil, "Base", Vector3.new(8, 1, 8), CFrame.new(0, 0.5, 0), Color3.new())
		expect.equal(fallback, true)
		local mesh = part:FindFirstChildOfClass("SpecialMesh")
		expect.truthy(mesh ~= nil and mesh.MeshType == Enum.MeshType.Brick)
		expect.equal(part.CanCollide, false)
		expect.equal(part.CanQuery, false)
		expect.near((part.Size - Vector3.new(8, 1, 8)).Magnitude, 0, TOLERANCE)
		part:Destroy()
	end)

	t.test("roundedBox clones a template and strips its tags, attributes and children", function()
		local template = Instance.new("Part")
		template:AddTag("SD_Generated")
		template:SetAttribute("SD_GeneratorId", "shapes")
		Instance.new("Attachment").Parent = template
		local part, fallback = Prims.roundedBox(template, "Base", Vector3.new(9, 1.2, 9), CFrame.identity, Color3.new())
		expect.equal(fallback, false)
		expect.equal(#part:GetTags(), 0)
		expect.equal(part:GetAttribute("SD_GeneratorId"), nil)
		expect.equal(#part:GetChildren(), 0)
		expect.equal(part.CanCollide, false)
		expect.equal(part.CanTouch, false)
		part:Destroy()
		template:Destroy()
	end)

	t.test("lowestY ignores invisible parts and sees rotated boxes", function()
		local model = Instance.new("Model")
		Prims.part({
			name = "Hidden",
			size = Vector3.one,
			cframe = CFrame.new(0, -10, 0),
			flags = "volume",
			parent = model,
		})
		Prims.part({
			name = "Tilted",
			size = Vector3.new(2, 2, 2),
			cframe = CFrame.new(0, 5, 0) * CFrame.Angles(0, 0, math.rad(45)),
			parent = model,
		})
		expect.near(Prims.lowestY(model), 5 - math.sqrt(2), TOLERANCE)
		model:Destroy()
	end)

	-- Phase 3: the wayfinding arrow tips (lobby.js:162) are two wedges.
	t.test("a wedge is a WedgePart with the size, frame, colour and flags given", function()
		local frame = CFrame.new(1, 2, 3) * CFrame.Angles(0, 0.5, 0)
		local wedge = Prims.wedge("Tip", Vector3.new(0.6, 0.75, 1.2), frame, Color3.new(1, 0, 0), "decor")
		expect.equal(wedge.ClassName, "WedgePart")
		expect.equal(wedge.Name, "Tip")
		expect.near((wedge.Size - Vector3.new(0.6, 0.75, 1.2)).Magnitude, 0, TOLERANCE)
		expect.near((wedge.CFrame.Position - frame.Position).Magnitude, 0, TOLERANCE)
		expect.equal(wedge.Color, Color3.new(1, 0, 0))
		expect.equal(wedge.Anchored, true)
		expect.equal(wedge.CanCollide, false)
		expect.equal(wedge.CanQuery, false)
		expect.equal(wedge.CanTouch, false)
		expect.equal(wedge.Material, Enum.Material.SmoothPlastic)
		wedge:Destroy()
	end)

	t.test("teardown", function()
		toolsClone:Destroy()
	end)
end
