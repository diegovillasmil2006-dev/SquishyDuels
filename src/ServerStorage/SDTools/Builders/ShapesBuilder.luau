--!strict
-- ShapesBuilder: builds the shape library ReplicatedStorage.SD_ShapeLibrary (DESIGN §8.1 rule 2, §1.7 step 3).
-- Server only, Edit mode only (ServerStorage.SDTools); called by Main's pipeline, never at runtime.
-- The library is a Folder marked as generated (GeneratorId "shapes") holding `RoundedBox`, the solid
-- GeometryService:IntersectAsync(Block 2x2x2, Ball diameter 2.75) returns: an IntersectOperation, a sibling of
-- UnionOperation under PartOperation (DESIGN §8.1 #2 calls it a UnionOperation; any PartOperation is accepted).
-- UsePartColor, RenderFidelity Precise, CollisionFidelity Box, Anchored, CanCollide/CanTouch/CanQuery false. Each use
-- clones it and sets Size and Color (Art/SquishyBuilder); an RB is always centred on its pivot with no rotation.
-- Everything is built UNPARENTED. IntersectAsync on unparented parts is unverified (§1.7, U): if it fails, build()
-- returns ok = false with the reason. There is no fallback that parents anything into the place.
-- Relative requires only.

local GeometryService = game:GetService("GeometryService")

local Generated = require(script.Parent.Parent.Generated)

-- Types

type BuildContext = Generated.BuildContext
type BuildResult = Generated.BuildResult

-- Constants

local GENERATOR_ID = "shapes"
local VERSION = 1
local ROOT_NAME = "SD_ShapeLibrary"
local ROUNDED_BOX_NAME = "RoundedBox"
local BOX_SIZE = 2 -- studs, every axis
local BALL_DIAMETER = 2.75 -- studs; normalized radius 1.375 in SquishyBuilder's face ray test (§8.1 rule 6)
local BASE_COLOR = Color3.new(1, 1, 1) -- each use sets its own colour (UsePartColor)

-- Module table

local ShapesBuilder = {}
ShapesBuilder.GENERATOR_ID = GENERATOR_ID
ShapesBuilder.VERSION = VERSION
ShapesBuilder.ROOT_NAME = ROOT_NAME
ShapesBuilder.ROUNDED_BOX_NAME = ROUNDED_BOX_NAME

-- Private

local function input(scratch: any, shape: Enum.PartType, size: number): Part
	local part = Instance.new("Part")
	scratch:add(part)
	part.Name = "Input" .. shape.Name
	part.Shape = shape
	part.Size = Vector3.one * size
	part.CFrame = CFrame.identity
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = BASE_COLOR
	return part
end

local function failure(warnings: { string }, message: string): BuildResult
	return { ok = false, root = nil, warnings = warnings, error = message }
end

-- Public

-- Builds the new library tree, unparented and marked. May yield (CSG). Never changes the place.
function ShapesBuilder.build(ctx: BuildContext): BuildResult
	local warnings: { string } = {}

	-- The root is destroyed with the scratch unless Main has taken it over (handedOver), so a throw half way
	-- leaves nothing behind.
	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	local handedOver = false
	ctx.scratch:add(function()
		if not handedOver then
			root:Destroy()
		end
	end)

	local block = input(ctx.scratch, Enum.PartType.Block, BOX_SIZE)
	local ball = input(ctx.scratch, Enum.PartType.Ball, BALL_DIAMETER)

	local ok, result = pcall(function(): { any }
		return GeometryService:IntersectAsync(block, { ball }, {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Precise,
			SplitApart = false,
		})
	end)
	if not ok then
		return failure(
			warnings,
			"GeometryService:IntersectAsync failed on unparented parts (DESIGN §1.7 step 3, unverified): "
				.. tostring(result)
		)
	end

	-- Whatever came back goes under the root first, so a failure below destroys it with the root.
	-- IntersectAsync makes IntersectOperations (not UnionOperations): accept any PartOperation.
	local solids: { PartOperation } = {}
	local others = 0
	for _, item in result do
		if typeof(item) == "Instance" then
			item.Parent = root
			if item:IsA("PartOperation") then
				table.insert(solids, item)
			else
				others += 1
			end
		end
	end
	if #solids ~= 1 or others > 0 then
		return failure(
			warnings,
			string.format(
				"GeometryService:IntersectAsync returned %d solid(s) and %d other item(s); expected one PartOperation",
				#solids,
				others
			)
		)
	end

	local solid = solids[1]
	solid.Name = ROUNDED_BOX_NAME
	solid.UsePartColor = true
	solid.Color = BASE_COLOR
	solid.Material = Enum.Material.SmoothPlastic
	solid.Anchored = true
	solid.CanCollide = false
	solid.CanTouch = false
	solid.CanQuery = false -- after CanCollide = false (CanQuery false needs a non-colliding part)
	solid.CastShadow = true
	solid.Massless = true
	-- Passed as IntersectAsync options too; set again in case the options were ignored. Failures are reported by
	-- Verify, which checks the values that actually stuck.
	pcall(function()
		solid.RenderFidelity = Enum.RenderFidelity.Precise
	end)
	pcall(function()
		solid.CollisionFidelity = Enum.CollisionFidelity.Box
	end)
	solid:PivotTo(CFrame.identity)

	Generated.mark(root, GENERATOR_ID, VERSION)
	handedOver = true
	return { ok = true, root = root, warnings = warnings, error = nil }
end

return ShapesBuilder
