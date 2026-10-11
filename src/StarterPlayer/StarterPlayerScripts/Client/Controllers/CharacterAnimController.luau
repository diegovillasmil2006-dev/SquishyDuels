--!strict
-- CharacterAnimController (client only). DESIGN §9.4, §9.5, §9.6, §9.16.
-- One Anim/JointLayer per Player character on this client, created on CharacterAdded and destroyed on
-- CharacterRemoving / PlayerRemoving (the layer also cleans itself on the character's Destroying). The layer finds
-- the joints by name (R15 first, R6 fallback), waits up to Config.Anim.joints.waitSeconds, writes only .Transform
-- with the write-guard, and skips characters farther than Config.Anim.joints.cullStuds (150) from the camera.
--
-- Layers driven here (layer id -> pose):
--   "hold"    -> hold            the design's HOLD, an override at w = 1 while HeldSquishyController.isHolding(player)
--                                and removed otherwise (spec 2026-10-11 §4): the holding arm never swings, the throw,
--                                ult and cheer overrides win over it, and a squeeze moves no arm (only the squishy)
--   "debug"   -> any pose        Studio debug hook pose(name, weight) for the local character (sign checks)
-- Throw, ultimate, cheer, shrug, dizzy and flinch layers arrive with their parts (same API).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)

local Client = script.Parent.Parent
local JointLayer = require(Client.Anim.JointLayer)
local PoseLibrary = require(Client.Anim.PoseLibrary)
local Scheduler = require(Client.Anim.Scheduler)
local HeldSquishyController = require(script.Parent.HeldSquishyController)

-- Types

-- The JointLayer methods this controller and its callers use. JointLayer.JointLayer itself carries a Util/Cleanup
-- whose generic add<T>() makes the type checker reject calls on it ("JointLayer" vs "JointLayer"), so values are
-- viewed through this structural type.
export type Layer = {
	setPose: (self: any, id: string, poseName: string, weight: number?) -> (),
	setWeight: (self: any, id: string, weight: number) -> (),
	blendWeight: (self: any, id: string, target: number, seconds: number, clearAtEnd: boolean?) -> (),
	kick: (self: any, id: string, poseName: string, amount: number?) -> (),
	getWeight: (self: any, id: string) -> number?,
	has: (self: any, id: string) -> boolean,
	clear: (self: any, id: string) -> (),
	isReady: (self: any) -> boolean,
	isDisabled: (self: any) -> boolean,
	getRig: (self: any) -> string?,
	destroy: (self: any) -> (),
}

-- A Util/Cleanup as stored in a record (same type-checker limitation).
type Trove = {
	add: (self: any, item: any) -> any,
	clean: (self: any) -> (),
}

type Entry = {
	player: Player,
	cleanup: Trove,
	layer: Layer?,
	character: Model?,
}

-- Constants

local LAYER_HOLD = "hold"
local LAYER_DEBUG = "debug"
local POSE_HOLD = "hold"

-- Module table

local CharacterAnimController = {}

-- Private

local entries: { [Player]: Entry } = {}
local cleanup: Cleanup.Cleanup? = nil

local function dropLayer(entry: Entry)
	local layer = entry.layer
	entry.layer = nil
	entry.character = nil
	if layer then
		layer:destroy()
	end
end

local function attach(entry: Entry, character: Model)
	if entry.character == character and entry.layer ~= nil then
		return
	end
	dropLayer(entry)
	entry.character = character
	entry.layer = JointLayer.new(character) :: any
end

local function liveLayer(player: Player): Layer?
	local entry = entries[player]
	local layer = entry and entry.layer
	if layer == nil or layer:isDisabled() then
		return nil
	end
	return layer
end

-- Joint phase, added before any layer: keeps the hold layer in line with the held model, same frame.
local function step(_dt: number, _now: number): boolean
	for player, entry in entries do
		local layer = entry.layer
		if layer and not layer:isDisabled() then
			CharacterAnimController.updateHoldLayer(layer, HeldSquishyController.isHolding(player))
		end
	end
	return true
end

local function track(player: Player)
	if entries[player] then
		return
	end
	local c = Cleanup.new()
	local entry: Entry = { player = player, cleanup = c :: any, layer = nil, character = nil }
	entries[player] = entry
	c:add(player.CharacterAdded:Connect(function(character: Model)
		attach(entry, character)
	end))
	c:add(player.CharacterRemoving:Connect(function()
		dropLayer(entry)
	end))
	c:add(function()
		dropLayer(entry)
	end)
	local character = player.Character
	if character then
		attach(entry, character)
	end
end

local function untrack(player: Player)
	local entry = entries[player]
	if entry == nil then
		return
	end
	entries[player] = nil
	entry.cleanup:clean()
end

-- Public

-- The hold layer of one character's joint layer, called every joint phase: present at weight 1 while `holding`,
-- removed otherwise.
function CharacterAnimController.updateHoldLayer(layer: Layer, holding: boolean)
	local has = layer:has(LAYER_HOLD)
	if not holding then
		if has then
			layer:clear(LAYER_HOLD)
		end
		return
	end
	if not has then
		layer:setPose(LAYER_HOLD, POSE_HOLD, 1)
	elseif layer:getWeight(LAYER_HOLD) ~= 1 then
		layer:setWeight(LAYER_HOLD, 1)
	end
end

-- Studio debug: shows `poseName` at `weight` (0-1) on the player's character on top of everything else; nil name or
-- weight <= 0 removes it. Returns false (with a reason) when the pose is unknown or there is no live layer.
function CharacterAnimController.setDebugPose(player: Player, poseName: string?, weight: number?): (boolean, string?)
	local layer = liveLayer(player)
	if layer == nil then
		return false, "no joint layer for this character"
	end
	local w = weight or 1
	if poseName == nil or not (w > 0) then
		layer:clear(LAYER_DEBUG)
		return true, nil
	end
	if not PoseLibrary.has(poseName) then
		return false, `unknown pose {poseName}`
	end
	layer:setPose(LAYER_DEBUG, poseName, w)
	return true, nil
end

-- The joint layer of a player's current character (later controllers add throw/cheer/flinch layers through it).
function CharacterAnimController.getLayer(player: Player): Layer?
	return liveLayer(player)
end

-- Small table for Studio debug hooks and tests.
function CharacterAnimController.debugState(): { [string]: any }
	local players: { [string]: any } = {}
	local count = 0
	for player, entry in entries do
		local layer = entry.layer
		if layer then
			count += 1
			local character = entry.character
			local upperArm = character and character:FindFirstChild("RightUpperArm")
			local shoulder = upperArm and upperArm:FindFirstChild("RightShoulder")
			players[player.Name] = {
				ready = layer:isReady(),
				disabled = layer:isDisabled(),
				rig = layer:getRig(),
				rightShoulderClass = if shoulder then shoulder.ClassName else nil,
				hold = layer:getWeight(LAYER_HOLD),
				debug = layer:getWeight(LAYER_DEBUG),
			}
		end
	end
	return { count = count, players = players }
end

-- Lifecycle

function CharacterAnimController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(Scheduler.add(step, "joint"))
	c:add(Players.PlayerAdded:Connect(track))
	c:add(Players.PlayerRemoving:Connect(untrack))
	for _, player in Players:GetPlayers() do
		track(player)
	end
	c:add(function()
		for player in table.clone(entries) do
			untrack(player)
		end
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function CharacterAnimController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return CharacterAnimController
