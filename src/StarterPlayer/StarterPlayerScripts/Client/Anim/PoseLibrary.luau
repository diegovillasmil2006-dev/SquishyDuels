--!strict
-- PoseLibrary (client only). Read access to the character poses of DESIGN §9.4 for R15 and R6. The pose table itself
-- (degrees in joint space, mode, priority, sway, spring) lives in Config.Anim.poses and the joint names in
-- Config.Anim.joints, so every number stays tunable in one place; this module converts them for JointLayer:
--   angles(name, rig)  → { [joint]: Vector3 } in radians (x, y, z), for additive layers (scaled by the weight)
--   cframes(name, rig) → { [joint]: CFrame } = CFrame.fromEulerAnglesYXZ(x, y, z), for override layers
-- Joint keys are the logical names of Config.Anim.joints (RightShoulder, RightElbow, RightWrist, LeftShoulder,
-- LeftElbow, Waist, Neck, Root); a pose lists only the joints it moves. Results are cached and frozen (computed on
-- first use, nothing at require). Unknown pose names are an error (an authoring mistake).
-- Poses: hold, throwWindup, throwRelease, throwFollow, ultCharge, rushRecovery, cheer, shrug, dizzy, flinch. Signs are
-- confirmed once in Play (SD_DebugClient.pose).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

-- Types

export type Rig = "R15" | "R6"
export type Pose = typeof(Config.Anim.poses.hold)
export type JointPath = { string } -- { parent part name, joint name }

-- Constants

local POSES = Config.Anim.poses
local JOINTS = Config.Anim.joints

-- Module table

local PoseLibrary = {}

-- Private

local anglesCache: { [string]: { [string]: Vector3 } } = {}
local cframeCache: { [string]: { [string]: CFrame } } = {}

local function checkRig(rig: string)
	assert(rig == "R15" or rig == "R6", `[SD][PoseLibrary] rig must be "R15" or "R6" (got {tostring(rig)})`)
end

local function poseOrError(name: string): Pose
	local pose = POSES[name]
	if pose == nil then
		error(`[SD][PoseLibrary] unknown pose {tostring(name)}`, 3)
	end
	return pose
end

-- Public

-- The Config entry of a pose (mode, priority, R15, R6, sway, spring).
function PoseLibrary.get(name: string): Pose
	return poseOrError(name)
end

function PoseLibrary.has(name: string): boolean
	return POSES[name] ~= nil
end

-- Every pose name, sorted.
function PoseLibrary.names(): { string }
	local names: { string } = {}
	for name in POSES do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Joint angles in radians for `rig`, keyed by logical joint name.
function PoseLibrary.angles(name: string, rig: string): { [string]: Vector3 }
	checkRig(rig)
	local key = name .. "|" .. rig
	local cached = anglesCache[key]
	if cached then
		return cached
	end
	local pose = poseOrError(name)
	local result: { [string]: Vector3 } = {}
	local degreesByJoint = if rig == "R15" then pose.R15 else pose.R6
	for joint, degrees in degreesByJoint do
		result[joint] = Vector3.new(math.rad(degrees.X), math.rad(degrees.Y), math.rad(degrees.Z))
	end
	table.freeze(result)
	anglesCache[key] = result
	return result
end

-- Full joint-space CFrames for `rig` (override poses), keyed by logical joint name.
function PoseLibrary.cframes(name: string, rig: string): { [string]: CFrame }
	local key = name .. "|" .. rig
	local cached = cframeCache[key]
	if cached then
		return cached
	end
	local result: { [string]: CFrame } = {}
	for joint, radians in PoseLibrary.angles(name, rig) do
		result[joint] = PoseLibrary.toCFrame(radians, 1)
	end
	table.freeze(result)
	cframeCache[key] = result
	return result
end

-- CFrame.fromEulerAnglesYXZ(x·w, y·w, z·w) for angles in radians (the additive composition of §9.4).
function PoseLibrary.toCFrame(radians: Vector3, weight: number): CFrame
	return CFrame.fromEulerAnglesYXZ(radians.X * weight, radians.Y * weight, radians.Z * weight)
end

-- Logical joint name → { parent part name, joint name } for `rig` (Config.Anim.joints).
function PoseLibrary.joints(rig: string): { [string]: JointPath }
	checkRig(rig)
	return if rig == "R15" then JOINTS.R15 else JOINTS.R6
end

-- "R15" or "R6" from a Humanoid's RigType.
function PoseLibrary.rigOf(humanoid: Humanoid): Rig
	return if humanoid.RigType == Enum.HumanoidRigType.R6 then "R6" else "R15"
end

return PoseLibrary
