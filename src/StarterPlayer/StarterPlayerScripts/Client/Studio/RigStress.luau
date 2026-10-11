--!strict
-- RigStress (client only, Studio only; DebugHooks "rigStress"). Squishy overhaul spec 2026-10-09 §5 "Measuring": n
-- client-only rigged squishies on stands in a row in front of the local character, each stepped like a held model
-- (its rig, the lobby breathing, one deformer write, the far stride) inside the "SD_Rigs" profiler scope, for the perf
-- scenarios rigs_12 and rigs_12_squeeze. Each is a "Held" clone welded to its stand as a held model is to its hand, so
-- the twist writes Weld.C1 like the real thing (a twisted anchored Root moved the whole assembly: rigs_12_squeeze read
-- ~1.9 ms where a real squeeze costs ~0.25 ms). Never sends a remote; the models and stands live in
-- Workspace.SD_ClientFx/SD_RigStress and set(0) removes them.
--   RigStress.set(n, { squeeze?, detail? }) -> { ok, count, error? }   n models, the catalog's toys in turn (0 = none);
--                         squeeze = each taps its rig every Config.Grip.Hold.repeatSeconds, staggered; detail =
--                         "hero" | "near" (default, like other players' near models) | "far"
--   RigStress.state() -> { count, squeeze, detail }

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local SquishyBlueprints = require(Shared.Art.SquishyBlueprints)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local SquishRig = require(Client.Anim.SquishRig)
local SquishyCache = require(Client.Models.SquishyCache)
local HeldSquishyController = require(Client.Controllers.HeldSquishyController)

-- Types

export type Options = { squeeze: boolean?, detail: string? }

type Stand = {
	model: Model,
	stand: Part,
	deformer: SquishDeformer.Deformer,
	rig: SquishRig.Rig,
	out: SquishRig.Out,
	phase: number, -- the breathing's phase
	nextTap: number, -- os.clock() of the next squeeze (squeeze mode)
	odd: boolean, -- the far stride's frame parity (HeldSquishyController.farStride)
}

-- Constants

local MAX_MODELS = 24
local COLUMNS = 6
local SPACING_STUDS = 3
local AHEAD_STUDS = 8 -- the first row this far in front of the character
local STAND_SIZE = Vector3.new(1.4, 0.4, 1.4)
local LIFT_STUDS = 1.2 -- the squishy's centre above the stand's top
local REPEAT_SECONDS = Config.Grip.Hold.repeatSeconds
local DETAILS: { [string]: SquishRig.Detail } = { hero = "hero", near = "near", far = "far" }
local PROFILE_RIGS = "SD_Rigs"
local FOLDER_NAME = "SD_RigStress"
local CLIENT_FX = "SD_ClientFx"

-- Module table

local RigStress = {}

-- Private

local stands: { Stand } = {}
local handle: Scheduler.Handle? = nil
local folder: Folder? = nil
local squeezing = false
local detailName = "near"

local function clear()
	local h = handle
	handle = nil
	if h then
		h:disconnect()
	end
	for _, entry in stands do
		entry.deformer:destroy()
		entry.model:Destroy()
		entry.stand:Destroy()
	end
	table.clear(stands)
	local f = folder
	folder = nil
	if f then
		f:Destroy()
	end
end

local function step(dt: number, now: number): boolean
	debug.profilebegin(PROFILE_RIGS)
	for _, entry in stands do
		local rig, out = entry.rig, entry.out
		if squeezing and now >= entry.nextTap then
			entry.nextTap = now + REPEAT_SECONDS
			rig:tap()
		end
		-- As a held model: a sleeping far rig is stepped and written every 2nd frame.
		local skip, odd = HeldSquishyController.farStride(DETAILS[detailName], rig:isAwake(), false, entry.odd)
		entry.odd = odd
		if skip then
			continue
		end
		rig:step(dt, out)
		out.S *= HeldSquishyController.idleSample(now, entry.phase, 1, false)
		entry.deformer:apply(out)
	end
	debug.profileend()
	return true
end

-- The stand of the index-th model: rows of COLUMNS in front of the character, facing it.
local function placeAt(origin: CFrame, index: number): CFrame
	local column = (index - 1) % COLUMNS
	local row = (index - 1) // COLUMNS
	local x = (column - (COLUMNS - 1) / 2) * SPACING_STUDS
	local z = -(AHEAD_STUDS + row * SPACING_STUDS)
	return origin * CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi, 0)
end

-- Public

function RigStress.set(n: number, opts: Options?): { [string]: any }
	clear()
	local count = math.clamp(math.floor(n), 0, MAX_MODELS)
	squeezing = opts ~= nil and opts.squeeze == true
	detailName = if opts and opts.detail and DETAILS[opts.detail] then opts.detail else "near"
	if count == 0 then
		return { ok = true, count = 0 }
	end
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return { ok = false, count = 0, error = "no local character" }
	end
	local look = root.CFrame.LookVector
	local origin = CFrame.lookAt(root.Position, root.Position + Vector3.new(look.X, 0, look.Z))
	local fx = Workspace:FindFirstChild(CLIENT_FX)
	local parent = if fx then fx else Workspace
	local box = Instance.new("Folder")
	box.Name = FOLDER_NAME
	box.Parent = parent
	folder = box
	local defs = Catalog.list()
	local start = os.clock()
	for index = 1, count do
		local def = defs[(index - 1) % #defs + 1]
		local blueprint = SquishyBlueprints[def.blueprintId]
		local at = placeAt(origin, index)
		local stand = Instance.new("Part")
		stand.Name = "SD_RigStand"
		stand.Anchored = true
		stand.CanCollide = false
		stand.CanQuery = false
		stand.CanTouch = false
		stand.Size = STAND_SIZE
		stand.CFrame = at
		stand.Parent = box
		local model = SquishyCache.clone(def.id, "Held")
		model.Parent = box
		local modelRoot = model.PrimaryPart :: BasePart
		local weld = Instance.new("Weld")
		weld.Name = "SD_RigStressWeld"
		weld.Part0 = stand
		weld.Part1 = modelRoot
		weld.C0 = CFrame.new(0, STAND_SIZE.Y / 2 + LIFT_STUDS, 0)
		weld.C1 = CFrame.identity
		weld.Parent = modelRoot
		local rig = SquishRig.new(blueprint.motion :: SquishRig.Motion, {
			axis = def.anim.squeezeAxis,
			rarity = def.rarity :: string,
			sections = blueprint.sections,
			foamRecoveryT = def.anim.foamRecoveryT,
			seed = index,
		})
		rig:setDetail(DETAILS[detailName])
		table.insert(stands, {
			model = model,
			stand = stand,
			deformer = SquishDeformer.attach(model, { twist = "weld", weld = weld, twistAxis = def.anim.squeezeAxis }),
			rig = rig,
			out = SquishRig.newOut(),
			phase = index * 0.7,
			nextTap = start + (index - 1) * REPEAT_SECONDS / count,
			odd = index % 2 == 0,
		})
	end
	handle = Scheduler.add(step, "render")
	return { ok = true, count = count }
end

function RigStress.state(): { [string]: any }
	return { ok = true, count = #stands, squeeze = squeezing, detail = detailName }
end

return RigStress
