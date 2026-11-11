--!strict
-- GearLooks: the pure rules of the gear's 3D looks (big job item 9, 2026-11-10; the owner's "Launcher and gear models:
-- each tier its own look"). Shared: the server packs what a player owns into one public number (HighwayService -> the
-- Player attribute SD_Gear), every client reads it back and shows the models (Client/Controllers/GearLooksController;
-- the shop's GEAR cards through UI/GearFormat). Numbers: Config/GearLooks (its header: the owner's sheet and Claude's
-- calls); the models: ReplicatedStorage.SD_Gear (tools/meshes/gear_models.py + gear_models_setup.luau). No instances,
-- no yields, no side effects.
--
-- API:
--   GearLooks.ATTRIBUTE, GearLooks.FOLDER      "SD_Gear": the Player attribute, and the models' folder
--   GearLooks.WORN                             { "held", "arm", "armor" }: the lines worn on the body
--   GearLooks.tiers(gear) -> { [line]: 0..7 }  the tier owned on each GearMath line of a saved gear table (a power
--                                              line: the tier of its last bought step; armor: a step a tier)
--   GearLooks.pack(gear) -> number             those tiers as one number: a decimal digit a line, GearMath.LINES order
--   GearLooks.unpack(value) -> { [line]: 0..7 } back again; anything but such a number is no gear at all
--   GearLooks.modelName(line, tier) -> string  the model's name in the folder ("held_3")
--   GearLooks.mount(line, partSize, mount, grip?) -> (CFrame, Vector3)
--                                              where a worn piece's pivot sits in its body part's space, and its
--                                              scale axis by axis (mount = the part's entry of Config/GearLooks'
--                                              mounts; grip = a held launcher's hand point, the model's Grip
--                                              attribute; a held launcher is never scaled)
--   GearLooks.platformGoal(root, side) -> (Vector3, number)
--                                              the platform launcher's floor point for its player's root (both
--                                              lane-local) and the side it stands on (-1 the player's left, 1 the
--                                              right; pass the last answer, 0 the first time)
--   GearLooks.onDeck(root, was) -> boolean     whether a lane-local root is in the throw area (`was`: it was a moment
--                                              ago, so it may be leaveStuds outside)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local GearMath = require(Shared.GearMath)
local HighwayMath = require(Shared.HighwayMath)
local L = require(Shared.Config.GearLooks)
local WorldLayout = require(Shared.World.WorldLayout)

export type Mount = { part: string, y: number, h: number }

local GearLooks = {}

GearLooks.ATTRIBUTE = "SD_Gear"
GearLooks.FOLDER = "SD_Gear"
GearLooks.WORN = table.freeze({ "held", "arm", "armor" })

local ARMOR = "armor"
local HELD = "held"
local MAX_TIER = #Config.Economy.Gear.tierSteps
local AREA = WorldLayout.Highway.throwArea
local P = L.platform

function GearLooks.tiers(gear: any): { [string]: number }
	local tiers: { [string]: number } = {}
	for _, line in GearMath.LINES do
		local steps = GearMath.steps(gear, line)
		tiers[line] = if line == ARMOR then steps else GearMath.tierOf(steps)
	end
	return tiers
end

function GearLooks.pack(gear: any): number
	local tiers = GearLooks.tiers(gear)
	local value = 0
	for _, line in GearMath.LINES do
		value = value * 10 + tiers[line]
	end
	return value
end

function GearLooks.unpack(value: any): { [string]: number }
	local lines = GearMath.LINES
	local rest = 0
	if type(value) == "number" and value == value and value >= 0 and value < 10 ^ #lines then
		rest = math.floor(value)
	end
	local tiers: { [string]: number } = {}
	for i = #lines, 1, -1 do
		tiers[lines[i]] = math.min(rest % 10, MAX_TIER)
		rest //= 10
	end
	return tiers
end

function GearLooks.modelName(line: string, tier: number): string
	return `{line}_{tier}`
end

function GearLooks.mount(line: string, partSize: Vector3, mount: Mount, grip: Vector3?): (CFrame, Vector3)
	local at = Vector3.new(0, mount.y * partSize.Y, 0)
	if line == HELD then
		-- the grip point just in front of the fist; the launcher keeps the hand's own axes (up along the arm)
		local fist = Vector3.new(0, 0, -(partSize.Z / 2 + L.held.gapStuds))
		return CFrame.new(at + fist - (grip or Vector3.zero)), Vector3.one
	end
	local fit: Vector3 = (L :: any)[line].fitStuds
	local S = L.scale
	local x = math.clamp(partSize.X / fit.X, S.min, S.max)
	local y = math.clamp(partSize.Y * mount.h / fit.Y, S.min, S.max)
	local z = math.clamp(partSize.Z / fit.Z, S.min, S.max)
	local cap = math.min(x, z) * S.stretch -- no axis more than `stretch` times the thinnest: the piece keeps its shape
	return CFrame.new(at), Vector3.new(math.min(x, cap), math.min(y, cap), math.min(z, cap))
end

function GearLooks.platformGoal(root: Vector3, side: number): (Vector3, number)
	local x = root.X - AREA.position.X
	-- on the side of the deck's middle; it changes sides only once the player is flipStuds past the middle
	local now = side
	if x > P.flipStuds then
		now = -1
	elseif x < -P.flipStuds then
		now = 1
	elseif side == 0 then
		now = if x >= 0 then -1 else 1
	end
	local halfX = AREA.size.X / 2 - P.halfWidthStuds
	local front = AREA.position.Z - AREA.size.Z / 2 + P.frontStuds -- the lane is toward -Z
	local back = AREA.position.Z + AREA.size.Z / 2 - P.backStuds
	local floor = AREA.position.Y - AREA.size.Y / 2
	local goal = Vector3.new(
		AREA.position.X + math.clamp(x + now * P.sideStuds, -halfX, halfX),
		floor,
		math.clamp(root.Z - P.aheadStuds, front, back)
	)
	return goal, now
end

function GearLooks.onDeck(root: Vector3, was: boolean): boolean
	return HighwayMath.inArea(root, if was then P.leaveStuds else 0)
end

return GearLooks
