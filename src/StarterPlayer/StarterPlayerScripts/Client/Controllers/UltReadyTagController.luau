--!strict
-- UltReadyTagController (client only). jayyyyy (2026-10-15): "in duels i want it to show on top of the players that
-- they have ult ready". Diego's HUD draws no overhead marker, so this reuses the duel HUD's own READY badge
-- (Components/Chip with Strings.duel.ultReady, raised, DuelController's READY_CHIP_PX 24) instead of new art.
-- * One BillboardGui per OTHER duelist whose ultimate is charged (StateController's duel view: participant.ultReady,
--   kept from UltimateCharge); the local player's own READY stays on the duel HUD. It lives in this client's PlayerGui
--   with the character's Head (else its HumanoidRootPart) as Adornee, UltReadyTag.headOffsetStuds above it, the same
--   px size at any distance, LightInfluence 0, AlwaysOnTop false (walls hide it) and MaxDistance maxDistanceStuds.
-- * Shown while the match is on (shownFor, pure: not Result, Returning, Cancelled or Void); hidden at once when the
--   charge is spent, the duelist leaves or the match ends.
-- * Motion like the HUD's READY (DuelController, §18.5.2 B8): it pops Config.UI.motion.readyPop.from -> 1 when it
--   appears (DuelFormat.readyPop), then pulses 1 ± PULSE_SCALE every motion.ultReadyPulseSeconds; static under
--   ReducedMotion (Anim/Tweens). One Anim/Scheduler "render" effect (DESIGN §9.1 #3: the Scheduler holds the client's
--   only per-frame connections), only while at least one tag shows.
-- * Sizes and distances: Config.UI.UltReadyTag. Studio test dummies get no tag (no Player to stand on).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local Create = require(Client.UI.Create)
local DuelFormat = require(Client.UI.DuelFormat)
local Chip = require(Client.UI.Components.Chip)
local StateController = require(script.Parent.StateController)

-- Constants

local MOTION = Config.UI.motion
local TAG = Config.UI.UltReadyTag
local CHIP_PX = 24 -- DuelController LAYOUT.READY_CHIP_PX: the same badge as on the HUD
local PULSE_SCALE = 0.08 -- DuelController LAYOUT.READY_PULSE_SCALE
local END_PHASES: { [string]: boolean } = { Result = true, Returning = true, Cancelled = true, Void = true }

-- Types

type Tag = {
	userId: number,
	gui: BillboardGui,
	scale: UIScale,
	chip: any,
	since: number,
}

-- Module table

local UltReadyTagController = {}

-- State

local log = Log.new("UltReadyTag")
local cleanup: any = nil
local tags: { [number]: Tag } = {}
local stepHandle: Scheduler.Handle? = nil

-- Public (pure)

-- The userIds that get a READY tag: every duelist of the view but the local player whose ultReady is true, while the
-- match is on (not an end phase). Empty without a view.
function UltReadyTagController.shownFor(view: any, localUserId: number?): { number }
	local out: { number } = {}
	if type(view) ~= "table" or END_PHASES[view.phase] then
		return out
	end
	for _, participant in { view.you, view.opponent } do
		if
			type(participant) == "table"
			and participant.ultReady == true
			and participant.isTestDummy ~= true
			and participant.userId ~= localUserId
		then
			table.insert(out, participant.userId)
		end
	end
	return out
end

-- The tag's scale `t` seconds after it appeared: the READY pop, then the pulse; 1 under ReducedMotion once popped.
function UltReadyTagController.scaleAt(t: number, reduced: boolean): number
	local scale, _, popDone = DuelFormat.readyPop(t, reduced)
	if not popDone then
		return scale
	end
	if reduced then
		return 1
	end
	local period = MOTION.ultReadyPulseSeconds
	local phase = ((t - MOTION.readyPop.ms / 1000) % period) / period
	return 1 + PULSE_SCALE * math.sin(phase * 2 * math.pi)
end

-- Private

local function adorneeOf(userId: number): (BasePart?, boolean)
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	if character == nil then
		return nil, false
	end
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head, true
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root, false
	end
	return nil, false
end

local function removeTag(userId: number)
	local tag = tags[userId]
	if tag == nil then
		return
	end
	tags[userId] = nil
	tag.chip:destroy()
	tag.gui:Destroy()
end

local function stopStepping()
	if stepHandle then
		stepHandle:disconnect()
		stepHandle = nil
	end
end

local function step()
	if next(tags) == nil then
		stopStepping()
		return
	end
	local now = os.clock()
	local reduced = Tweens.reducedMotion()
	for userId, tag in tags do
		local adornee, isHead = adorneeOf(userId)
		if adornee == nil then
			tag.gui.Enabled = false
		else
			if tag.gui.Adornee ~= adornee then
				tag.gui.Adornee = adornee
				tag.gui.StudsOffset = Vector3.new(0, TAG.headOffsetStuds + (if isHead then 0 else TAG.rootToHeadStuds), 0)
			end
			tag.gui.Enabled = true
			tag.scale.Scale = UltReadyTagController.scaleAt(now - tag.since, reduced)
		end
	end
end

local function addTag(userId: number)
	local localPlayer = Players.LocalPlayer
	local playerGui = if localPlayer then localPlayer:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui == nil or tags[userId] then
		return
	end
	local gui: BillboardGui = Create("BillboardGui", {
		Name = "SD_UltReady_" .. userId,
		Size = UDim2.fromOffset(TAG.guiPx.X, TAG.guiPx.Y),
		LightInfluence = 0,
		AlwaysOnTop = false,
		MaxDistance = TAG.maxDistanceStuds,
		ResetOnSpawn = false,
		Enabled = false,
	})
	local chip = Chip.new({
		name = "Ready",
		text = Strings.duel.ultReady,
		raised = true,
		heightPx = CHIP_PX,
		parent = gui,
	})
	chip.root.AnchorPoint = Vector2.new(0.5, 0.5)
	chip.root.Position = UDim2.fromScale(0.5, 0.5)
	local scale: UIScale = Create("UIScale", { Name = "Pop", Parent = chip.root })
	gui.Parent = playerGui
	tags[userId] = { userId = userId, gui = gui, scale = scale, chip = chip, since = os.clock() }
	if stepHandle == nil then
		stepHandle = Scheduler.add(function(): boolean
			local ok, err = pcall(step)
			if not ok then
				log:error("ult ready tag update failed:", err)
			end
			local alive = ok and next(tags) ~= nil
			if not alive then
				stepHandle = nil
			end
			return alive
		end, "render")
	end
end

local function refresh(view: any)
	local localPlayer = Players.LocalPlayer
	local wanted: { [number]: boolean } = {}
	for _, userId in UltReadyTagController.shownFor(view, if localPlayer then localPlayer.UserId else nil) do
		wanted[userId] = true
	end
	for userId in table.clone(tags) do
		if not wanted[userId] then
			removeTag(userId)
		end
	end
	for userId in wanted do
		addTag(userId)
	end
	if next(tags) == nil then
		stopStepping()
	end
end

-- Lifecycle

function UltReadyTagController.init()
	cleanup = Cleanup.new()
end

function UltReadyTagController.start()
	local c = cleanup
	if c == nil then
		return
	end
	c:add(StateController.DuelChanged:connect(function(view: StateController.DuelView?)
		local ok, err = pcall(refresh, view)
		if not ok then
			log:error("ult ready tags refresh failed:", err)
		end
	end))
	c:add(function()
		for userId in table.clone(tags) do
			removeTag(userId)
		end
		stopStepping()
	end)
	refresh(StateController.duel())
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function UltReadyTagController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return UltReadyTagController
