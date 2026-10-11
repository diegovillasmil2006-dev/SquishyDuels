--!strict
-- AmbientController (client only). DESIGN §18.5.1 A8, §9.15 "Ambient", §18.1 (principle #3's lobby exception,
-- ReducedMotion), §18.9 (budgets). The lobby background motion: every streamed-in Model tagged SD_Ambient
-- (WorldLayout.Tags.Ambient, set by LobbyBuilder with SD_AmbientKind) moves on this client only, always from its built
-- pose and the clock (Anim/AmbientMath), never added up frame by frame:
--   * movers: "spin" (Decor/Lollipop1..4) and "spinBob" (DailyStand/GiftBox): model:PivotTo(base pivot ×
--     AmbientMath.offset). At most Config.Vfx.Budgets.ambientMovers (6) are bound; any more stay still (one log line).
--   * breathers: "breathe" (GiftBoxCounter/GiftBox, SqueezeZone/Statue): SquishDeformer.attach(model) with no twist
--     target (mesh only: the Root never deforms) and deformer:setScale(AmbientMath.scale). They count in
--     Config.Vfx.Budgets.deformingRigs at the lowest priority: HeldSquishyController hands over the slots its held models
--     and then the Collection displays leave (setBreatheSlots; squishy overhaul spec 2026-10-09 §3.2: Collection first,
--     then Ambient), and the breathers nearest the camera get them; the others rest.
--   * Culling: a model moves only within Ambient.cullStuds (120) of the camera and while its bounding sphere is on
--     screen (AmbientMath.sphereOnScreen); otherwise it holds its last pose. Back in view, the clock puts it where
--     it belongs, so nothing drifts.
--   * ReducedMotion (Tweens.reducedMotion): one write back to the built pose, then nothing; the statue sparkle (the
--     StatueSparkle emitter LobbyBuilder puts on the statue's plinth) runs at Rate 1, back to
--     Config.Vfx.Effects.statueSparkleRate after.
--   * Stream-out or tag removal: the binding goes (the deformer rests first; a model still in place is put back on its
--     built pivot).
-- Only local pivots and mesh values change, on decor whose parts never collide, are queried or touched (LobbyBuilder's
-- self-check and Verify enforce it), so nothing here can touch competitive state. One Scheduler render effect; the
-- only connections are the CollectionService tag signals.

-- Services

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local AmbientMath = require(Client.Anim.AmbientMath)
local Scheduler = require(Client.Anim.Scheduler)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local Tweens = require(Client.Anim.Tweens)

-- Types

type Entry = {
	model: Model,
	spec: AmbientMath.Spec,
	phase: number,
	base: CFrame, -- the built pivot (movers return to it exactly)
	center: Vector3, -- bounding sphere centre (fixed: a mover turns about its pivot's vertical axis)
	radius: number,
	deformer: SquishDeformer.Deformer?, -- breathers only
	sparkle: ParticleEmitter?, -- the statue's sparkle
	atRest: boolean, -- the last write was the built pose
}

-- Constants

local AMBIENT = Config.Vfx.Ambient
local EFFECTS = Config.Vfx.Effects
local BUDGETS = Config.Vfx.Budgets
local TAG = WorldLayout.Tags.Ambient
local ATTR_KIND = WorldLayout.Attributes.AmbientKind
local STATUE_NAME = "Statue" -- SqueezeZone/Statue (LobbyBuilder)
local SPARKLE_NAME = "StatueSparkle" -- LobbyBuilder's emitter on the statue's plinth
local REDUCED_SPARKLE_RATE = 1 -- §18.1: ReducedMotion "statue sparkle Rate 1"

-- Module table

local AmbientController = {}

-- Private

local log = Log.new("Ambient")
local cleanup: Cleanup.Cleanup? = nil
local entries: { [Model]: Entry } = {}
local breatheSlots = math.huge -- deformingRigs slots left by the held models (HeldSquishyController)
local wasReduced = false
local warnedBudget = false
local breathersScratch: { Entry } = {} -- reused every frame (no per-frame tables)
local distances: { [Entry]: number } = {}

local function moverCount(): number
	local count = 0
	for _, entry in entries do
		if AmbientMath.isMover(entry.spec) then
			count += 1
		end
	end
	return count
end

local function findSparkle(model: Model): ParticleEmitter?
	if model.Name ~= STATUE_NAME or model.Parent == nil then
		return nil
	end
	local found = (model.Parent :: Instance):FindFirstChild(SPARKLE_NAME, true)
	return if found and found:IsA("ParticleEmitter") then found else nil
end

local function setSparkle(entry: Entry, reduced: boolean)
	local sparkle = entry.sparkle
	if sparkle == nil or sparkle.Parent == nil then
		return
	end
	local rate = if reduced then REDUCED_SPARKLE_RATE else EFFECTS.statueSparkleRate
	if sparkle.Rate ~= rate then
		sparkle.Rate = rate
	end
end

-- Back to the built pose: one write, then nothing until the entry moves again.
local function rest(entry: Entry)
	if entry.atRest then
		return
	end
	entry.atRest = true
	local deformer = entry.deformer
	if deformer then
		deformer:rest()
	elseif entry.model.Parent ~= nil then
		entry.model:PivotTo(entry.base)
	end
end

local function bind(instance: Instance)
	if entries[instance :: any] ~= nil or not instance:IsA("Model") then
		return
	end
	local model = instance :: Model
	local kind = model:GetAttribute(ATTR_KIND)
	local spec = if type(kind) == "string" then AmbientMath.spec(kind, model.Name) else nil
	if spec == nil then
		log:warn(`{model:GetFullName()} has no known {ATTR_KIND} ({tostring(kind)}); it stays still`)
		return
	end
	if AmbientMath.isMover(spec) and moverCount() >= BUDGETS.ambientMovers then
		if not warnedBudget then
			warnedBudget = true
			log:warn(
				`more than {BUDGETS.ambientMovers} ambient movers (Config.Vfx.Budgets.ambientMovers); extra ones stay still`
			)
		end
		return
	end
	local base = model:GetPivot()
	local boxFrame, boxSize = model:GetBoundingBox()
	local fromPivot = boxFrame.Position - base.Position
	local center, radius
	if AmbientMath.isMover(spec) then
		-- The box centre circles the pivot's vertical axis: a sphere on that axis that holds every turn.
		center = base.Position + Vector3.new(0, fromPivot.Y, 0)
		radius = Vector3.new(fromPivot.X, 0, fromPivot.Z).Magnitude + boxSize.Magnitude / 2
	else
		center = boxFrame.Position
		radius = boxSize.Magnitude / 2
	end
	local deformer: SquishDeformer.Deformer? = nil
	if not AmbientMath.isMover(spec) then
		local ok, result = pcall(SquishDeformer.attach, model)
		if not ok then
			log:warn(`{model:GetFullName()}: could not attach the deformer ({tostring(result)}); it stays still`)
			return
		end
		deformer = result
	end
	local entry: Entry = {
		model = model,
		spec = spec,
		phase = AmbientMath.phaseOf(model.Name),
		base = base,
		center = center,
		radius = radius,
		deformer = deformer,
		sparkle = findSparkle(model),
		atRest = true,
	}
	entries[model] = entry
	setSparkle(entry, wasReduced)
end

local function unbind(instance: Instance)
	local entry = entries[instance :: any]
	if entry == nil then
		return
	end
	entries[entry.model] = nil
	rest(entry)
	setSparkle(entry, false)
	local deformer = entry.deformer
	if deformer then
		deformer:destroy()
	end
end

local function byDistance(a: Entry, b: Entry): boolean
	return (distances[a] or math.huge) < (distances[b] or math.huge)
end

local function step(_dt: number, now: number): boolean
	if next(entries) == nil then
		return true
	end
	local reduced = Tweens.reducedMotion()
	if reduced ~= wasReduced then
		wasReduced = reduced
		for _, entry in entries do
			setSparkle(entry, reduced)
		end
	end
	if reduced then
		for _, entry in entries do
			rest(entry)
		end
		return true
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return true
	end
	local cameraPosition = camera.CFrame.Position
	local viewport = camera.ViewportSize
	local tanHalf = math.tan(math.rad(camera.FieldOfView) / 2)
	table.clear(breathersScratch)
	table.clear(distances)
	for model, entry in entries do
		if model.Parent == nil then
			continue -- streaming out: CollectionService removes it
		end
		local distance = (entry.center - cameraPosition).Magnitude
		if distance > AMBIENT.cullStuds then
			continue -- holds its last pose
		end
		local screen = camera:WorldToViewportPoint(entry.center)
		if not AmbientMath.sphereOnScreen(screen.X, screen.Y, screen.Z, entry.radius, viewport, tanHalf) then
			continue
		end
		if entry.deformer then
			distances[entry] = distance
			table.insert(breathersScratch, entry)
		else
			entry.atRest = false
			model:PivotTo(entry.base * AmbientMath.offset(entry.spec, now, entry.phase, false))
		end
	end
	-- Breathers: the lowest priority of the deforming-rig budget, nearest first.
	if #breathersScratch > 1 then
		table.sort(breathersScratch, byDistance)
	end
	for index, entry in breathersScratch do
		local deformer = entry.deformer :: SquishDeformer.Deformer
		if index > breatheSlots then
			rest(entry)
		else
			entry.atRest = false
			deformer:setScale(AmbientMath.scale(entry.spec, now, entry.phase, false))
		end
	end
	return true
end

-- Public

-- HeldSquishyController (each range pass): how many of the deforming-rig budget its held models and the Collection
-- displays leave free. The breathers nearest the camera use them; the others rest.
function AmbientController.setBreatheSlots(slots: number)
	breatheSlots = if slots == slots then math.max(0, math.floor(slots)) else 0
end

-- Small table for Studio debug hooks: bound movers and breathers, and the breathe slots.
function AmbientController.debugState(): { [string]: any }
	local movers, breathers, resting = 0, 0, 0
	for _, entry in entries do
		if entry.deformer then
			breathers += 1
		else
			movers += 1
		end
		if entry.atRest then
			resting += 1
		end
	end
	return {
		movers = movers,
		breathers = breathers,
		resting = resting,
		breatheSlots = breatheSlots,
		reduced = wasReduced,
	}
end

-- Lifecycle

function AmbientController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(CollectionService:GetInstanceAddedSignal(TAG):Connect(bind))
	c:add(CollectionService:GetInstanceRemovedSignal(TAG):Connect(unbind))
	for _, instance in CollectionService:GetTagged(TAG) do
		bind(instance)
	end
	c:add(Scheduler.add(step, "render"))
	c:add(function()
		for model in table.clone(entries) do
			unbind(model)
		end
		breatheSlots = math.huge
		wasReduced = false
		warnedBudget = false
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function AmbientController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return AmbientController
