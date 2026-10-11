--!strict
-- DesignArm (client only): one 3D Lab first-person arm (spec 2026-10-11 §3.2; design: fp.js:64-76).
--
-- An arm is five parts named as Config.FirstPerson.arm.parts (hand, thumb, forearm, cuff, sleeve), each a SuperMesh
-- superellipsoid of the part's exponent (its fallback without the mesh path) sized size × studsPerDu, in the design's
-- colours (Config.FirstPerson.colours: skin, cuff, sleeve). With the mesh path each part also gets its outline hull
-- (toon.js:46-54; closest option §3.9): SuperMesh.newPart(n, (size + 2t) × studsPerDu, true) named "<part>_outline"
-- (toon.js:53), coloured Config.FirstPerson.outline.colour, in Arm.hulls under the part's name; t = OUTLINE_DU, the
-- design's 3 px (fp.js:72) at refHeightPx rows and the hold depth: px · 2 · refDepthDu · tan(fovDeg / 2) / refHeightPx.
-- The parts and hulls are never made transparent one by one: the invulnerability ghost fades the whole overlay image
-- evenly, hulls included (ViewmodelController, ViewportFrame.ImageTransparency).
-- The arm frame (fp.js:76): root at the hand point H, +Z aimed at the arm's shoulder, then rolled about its own Z:
-- CFrame.lookAt(H, shoulder) · Angles(0, π, 0) · Angles(0, 0, roll) (three.js's lookAt for an object: +Z at the target,
-- X = up × Z). Each part sits at its Config pos with its Euler XYZ rot in that frame; pos.X and rot.Y are × side (the
-- design mirrors only these, fp.js:70). Everything in studs: du × studsPerDu.
--
-- API
--   DesignArm.PARTS                              the part names, in Config order
--   DesignArm.OUTLINE_DU                         the hull's thickness t (du), about 0.0018
--   DesignArm.new(side, parent?, studsPerDu?) -> Arm   side -1 = left, +1 = right; an "SD_Arm_L" / "SD_Arm_R" Model
--       parented to `parent` (nil: unparented); studsPerDu defaults to Config.FirstPerson.overlayStudsPerDu. Never
--       yields (SuperMesh.newPart); run SuperMesh.prepare() first for the mesh path on the first arms
--   DesignArm.setColours(arm, sleeve)            the sleeve's colour (the team's, spec §3.2); skin and cuff are fixed
--   DesignArm.partFrames(hand, shoulder, roll, side, studsPerDu, out) -> out   pure: fills out[name] = each part's
--       CFrame (studs, the overlay camera's space) for the hand point and the arm's own shoulder (both du, the
--       shoulder already on this arm's side), the roll (rad) and the side; returns out
--   DesignArm.apply(arm, frames)                 writes each part's (and hull's) CFrame from partFrames' table
--   DesignArm.destroy(arm)
-- Require direction: Anim/SuperMesh and Shared Config only.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)
local SuperMesh = require(script.Parent.SuperMesh)

-- Types

export type Arm = {
	side: number,
	studsPerDu: number,
	model: Model,
	parts: { [string]: BasePart },
	hulls: { [string]: BasePart },
}

-- Constants

local FP = Config.FirstPerson
local ROWS = FP.arm.parts
local OUTLINE = FP.outline
local FLIP = CFrame.Angles(0, math.pi, 0) -- Roblox's lookAt aims -Z; the design's aims +Z (spec §3.2)
-- design: fp.js:72 (3 px), toon.js:12 (pixels at the vertex's depth)
local OUTLINE_DU = OUTLINE.px * 2 * OUTLINE.refDepthDu * math.tan(math.rad(FP.fovDeg) / 2) / OUTLINE.refHeightPx

-- Module table

local DesignArm = {}

local names = {}
for i, row in ROWS do
	names[i] = row.name
end
DesignArm.PARTS = table.freeze(names)
DesignArm.OUTLINE_DU = OUTLINE_DU

-- Public

function DesignArm.new(side: number, parent: Instance?, studsPerDu: number?): Arm
	assert(side == -1 or side == 1, "[SD][DesignArm] side must be -1 or 1")
	local u = studsPerDu or FP.overlayStudsPerDu
	assert(type(u) == "number" and u > 0 and u < math.huge, "[SD][DesignArm] studsPerDu must be a number > 0")
	local model = Instance.new("Model")
	model.Name = if side < 0 then "SD_Arm_L" else "SD_Arm_R"
	local parts: { [string]: BasePart } = {}
	local hulls: { [string]: BasePart } = {}
	for _, row in ROWS do
		local part = SuperMesh.newPart(row.exponent, row.size * u) :: BasePart
		part.Name = row.name
		part.Color = (FP.colours :: any)[row.colour]
		part.Parent = model
		parts[row.name] = part
		local hull = SuperMesh.newPart(row.exponent, (row.size + Vector3.one * (2 * OUTLINE_DU)) * u, true)
		if hull then
			hull.Name = row.name .. "_outline" -- design: toon.js:53
			hull.Color = OUTLINE.colour
			hull.Parent = model
			hulls[row.name] = hull
		end
	end
	model.Parent = parent
	return { side = side, studsPerDu = u, model = model, parts = parts, hulls = hulls }
end

function DesignArm.setColours(arm: Arm, sleeve: Color3)
	for _, row in ROWS do
		if row.colour == "sleeve" then
			arm.parts[row.name].Color = sleeve
		end
	end
end

function DesignArm.partFrames(
	hand: Vector3,
	shoulder: Vector3,
	roll: number,
	side: number,
	studsPerDu: number,
	out: { [string]: CFrame }
): { [string]: CFrame }
	local u = studsPerDu
	local root = CFrame.lookAt(hand * u, shoulder * u) * FLIP * CFrame.Angles(0, 0, roll)
	for _, row in ROWS do
		local pos, rot = row.pos, row.rot
		out[row.name] = root
			* CFrame.new(pos.X * side * u, pos.Y * u, pos.Z * u)
			* CFrame.Angles(rot.X, rot.Y * side, rot.Z)
	end
	return out
end

function DesignArm.apply(arm: Arm, frames: { [string]: CFrame })
	for name, part in arm.parts do
		local frame: CFrame? = frames[name]
		if frame and part.CFrame ~= frame then
			part.CFrame = frame
			local hull = arm.hulls[name]
			if hull then
				hull.CFrame = frame
			end
		end
	end
end

function DesignArm.destroy(arm: Arm)
	arm.model:Destroy()
end

return DesignArm
