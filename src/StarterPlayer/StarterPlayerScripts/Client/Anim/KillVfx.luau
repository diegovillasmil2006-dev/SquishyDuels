--!strict
-- KillVfx (client only; kill banners 2026-10-16, VillasmilGaming). Plays the kill effects authored for the VFX Studio
-- plugin, ReplicatedStorage.SD_KillVfx (made by ServerStorage.SDTools.Builders.KillVfxBuilder, then tuned in VFX
-- Studio). Every effect is a clone of a template Part (its carrier) under Workspace.SD_ClientFx.KillVfx: cosmetic only
-- (anchored, CanCollide / CanQuery / CanTouch false, SD_Cosmetic when that group exists), never replicated.
--
-- The emit contract is VFX Studio's, as Anim/ThrowVfx runs it (ThrowVfx.emitPlan): per ParticleEmitter, wait
-- EmitDelay; EmitDuration > 0 = Enabled for that long, else Emit(EmitCount). Ours on top:
--   * SD_MinTier (Banner/<set>): an emitter plays only when the banner's tier is at least that (tierAllows);
--   * counts and rates × Config.Vfx.reducedParticleMultiplier under ReducedMotion, at least 1 when the template asked
--     for any.
-- Banner bursts (banner(path, tier, place, radius)): the template is made for a banner disc of radius 1 stud, so every
-- emitter's Size, Speed and Acceleration and every attachment's position are scaled by `radius` (the disc's radius in
-- studs at the burst's depth, bannerRadius); its emitters are LockedToPart and `place()` is called every frame
-- (RenderStepped, after the camera) to hold the carrier in front of the camera, so the burst stays on the banner.
-- Kill effects (kill(path, at)): a burst at `at`, world up; skipped beyond Config.Vfx.KillFx.farStuds from the camera.
-- The template's "Floor" attachment (its shock rings) is moved onto the floor found within KillFx.floorStuds under
-- `at` (characters and effects ignored); with no floor there it stays where the template put it.
-- Budgets: at most KillFx.maxBursts banner bursts and KillFx.maxKills kill effects live at once (one over its cap is
-- dropped). A missing library (not replicated yet, or deleted) only means no effect.
--
-- API (paths are "<Folder>/<Template>", e.g. "Banner/standard")
--   KillVfx.kill(path, at) -> boolean
--   KillVfx.banner(path, tier, place, radius) -> boolean   place: () -> CFrame? (nil = the burst stops following)
--   KillVfx.tierAllows(minTier, tier) -> boolean           pure
--   KillVfx.bannerRadius(discPx, viewportHeightPx, fovDeg, depth) -> number   pure: studs
--   KillVfx.has(path) -> boolean                          the template exists
--   KillVfx.counts() -> { bursts, kills }  / KillVfx.clear()   Studio, tests and leak checks

-- Services

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local ThrowVfx = require(script.Parent.ThrowVfx)
local Tweens = require(script.Parent.Tweens)

-- Constants

local LIBRARY_NAME = "SD_KillVfx"
local FLOOR_ATTACHMENT = "Floor"
local FLOOR_LIFT = 0.15 -- studs over the floor (no z-fighting with it)
local FX_FOLDER = "SD_ClientFx"
local OWN_FOLDER = "KillVfx"
local COSMETIC_GROUP = "SD_Cosmetic"
local END_MARGIN = 0.15 -- seconds after the longest particle before a carrier goes
local KILL_FX = Config.Vfx.KillFx

-- Module table

local KillVfx = {}

-- Private state

local folder: Folder? = nil
local live: { [string]: number } = { bursts = 0, kills = 0 }
local carriers: { [BasePart]: string } = {} -- carrier -> "bursts" | "kills"
local followers: { [BasePart]: () -> CFrame? } = {}
local followConnection: RBXScriptConnection? = nil

-- Pure helpers ---------------------------------------------------------------------------------------------------------

function KillVfx.tierAllows(minTier: unknown, tier: number): boolean
	if type(minTier) ~= "number" or minTier ~= minTier then
		return true
	end
	return tier >= minTier
end

-- The radius in studs, at `depth` studs in front of a camera of vertical FOV `fovDeg`, of a disc `discPx` wide on a
-- viewport `viewportHeightPx` tall.
function KillVfx.bannerRadius(discPx: number, viewportHeightPx: number, fovDeg: number, depth: number): number
	if not (viewportHeightPx > 0 and discPx > 0 and fovDeg > 0 and depth > 0) then
		return 0
	end
	local viewHeightStuds = 2 * depth * math.tan(math.rad(fovDeg) / 2)
	return (discPx / 2) / viewportHeightPx * viewHeightStuds
end

-- Private ------------------------------------------------------------------------------------------------------------

local function library(): Instance?
	return ReplicatedStorage:FindFirstChild(LIBRARY_NAME)
end

local function ownFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local fx = Workspace:FindFirstChild(FX_FOLDER)
	if fx == nil then
		local made = Instance.new("Folder")
		made.Name = FX_FOLDER
		made.Parent = Workspace
		fx = made
	end
	local own = (fx :: Instance):FindFirstChild(OWN_FOLDER)
	if own == nil or not own:IsA("Folder") then
		local made = Instance.new("Folder")
		made.Name = OWN_FOLDER
		made.Parent = fx
		own = made
	end
	folder = own :: Folder
	return own :: Folder
end

local cosmeticChecked, cosmeticOk = false, false
local function styleCarrier(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	if not cosmeticChecked then
		cosmeticChecked = true
		local ok, registered = pcall(function()
			return PhysicsService:IsCollisionGroupRegistered(COSMETIC_GROUP)
		end)
		cosmeticOk = ok and registered == true
	end
	if cosmeticOk then
		part.CollisionGroup = COSMETIC_GROUP
	end
end

local function template(path: string): BasePart?
	local lib = library()
	if lib == nil then
		return nil
	end
	local node: Instance? = lib
	for name in string.gmatch(path, "[^/]+") do
		node = if node then node:FindFirstChild(name) else nil
	end
	if node and node:IsA("BasePart") then
		return node
	end
	return nil
end

local function multiplier(): number
	return if Tweens.reducedMotion() then Config.Vfx.reducedParticleMultiplier else 1
end

-- Runs one emitter's VFX Studio contract. Returns when it ends (seconds from now).
local function runEmitter(e: ParticleEmitter, m: number): number
	local delay, count, duration = ThrowVfx.emitPlan(e:GetAttributes(), m)
	if duration > 0 then
		e.Rate *= m
		task.delay(delay, function()
			if e.Parent then
				e.Enabled = true
			end
		end)
		task.delay(delay + duration, function()
			if e.Parent then
				e.Enabled = false
			end
		end)
		return delay + duration + e.Lifetime.Max
	end
	if count <= 0 then
		return 0
	end
	if delay > 0 then
		task.delay(delay, function()
			if e.Parent then
				e:Emit(count)
			end
		end)
	else
		e:Emit(count)
	end
	return delay + e.Lifetime.Max
end

local function scaleEmitter(e: ParticleEmitter, k: number)
	e.Size = ThrowVfx.scaleSequence(e.Size, k)
	e.Speed = NumberRange.new(e.Speed.Min * k, e.Speed.Max * k)
	e.Acceleration *= k
end

local function stopFollowingIfIdle()
	if next(followers) == nil and followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end
end

local function follow(part: BasePart, place: () -> CFrame?)
	followers[part] = place
	if followConnection == nil then
		followConnection = RunService.RenderStepped:Connect(function()
			for carrier, where in followers do
				if carrier.Parent == nil then
					followers[carrier] = nil
					continue
				end
				local ok, frame = pcall(where)
				if ok and typeof(frame) == "CFrame" then
					carrier.CFrame = frame
				else
					followers[carrier] = nil -- stays where it last was
				end
			end
			stopFollowingIfIdle()
		end)
	end
end

local function release(part: BasePart)
	local kind = carriers[part]
	if kind then
		carriers[part] = nil
		live[kind] = math.max(live[kind] - 1, 0)
	end
	followers[part] = nil
	part:Destroy()
	stopFollowingIfIdle()
end

-- The floor under `at` within KillFx.floorStuds (players' characters and the effects ignored), or nil.
local function floorUnder(at: Vector3): Vector3?
	local ignore: { Instance } = { ownFolder() }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local hit = Workspace:Raycast(at, Vector3.new(0, -KILL_FX.floorStuds, 0), params)
	return if hit then hit.Position else nil
end

-- Clones `path`, keeps the emitters `keep` allows, scales by `scale`, places it at `at`, plays it. Returns the
-- carrier, or nil when there is no template or nothing to play.
local function start(
	path: string,
	kind: string,
	at: CFrame,
	scale: number,
	keep: (ParticleEmitter) -> boolean,
	floor: Vector3?
): BasePart?
	local source = template(path)
	if source == nil then
		return nil
	end
	local part = source:Clone()
	styleCarrier(part)
	local emitters: { ParticleEmitter } = {}
	for _, d in part:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			if keep(d) then
				if scale ~= 1 then
					scaleEmitter(d, scale)
				end
				table.insert(emitters, d)
			else
				d:Destroy()
			end
		elseif d:IsA("Attachment") and scale ~= 1 then
			d.Position *= scale
		end
	end
	if #emitters == 0 then
		part:Destroy()
		return nil
	end
	part.CFrame = at
	if floor then
		local anchor = part:FindFirstChild(FLOOR_ATTACHMENT)
		if anchor and anchor:IsA("Attachment") then
			anchor.WorldPosition = floor + Vector3.new(0, FLOOR_LIFT, 0)
		end
	end
	part.Parent = ownFolder()
	local m = multiplier()
	local ends = 0
	for _, e in emitters do
		ends = math.max(ends, runEmitter(e, m))
	end
	carriers[part] = kind
	live[kind] += 1
	-- In the particles' own time (2026-10-28: the final K.O.'s slow motion, Anim/FeelFx, lowers every TimeScale under
	-- SD_ClientFx), so a slowed kill effect keeps its particles to their end; at most 8x longer in real time.
	local probe = emitters[1]
	task.spawn(function()
		local left, begun = ends + END_MARGIN, os.clock()
		while left > 0 and os.clock() - begun < (ends + END_MARGIN) * 8 do
			left -= task.wait() * (if probe.Parent then probe.TimeScale else 1)
		end
		if carriers[part] then
			release(part)
		end
	end)
	return part
end

-- Public -------------------------------------------------------------------------------------------------------------

function KillVfx.has(path: string): boolean
	return template(path) ~= nil
end

function KillVfx.kill(path: string, at: Vector3): boolean
	if live.kills >= KILL_FX.maxKills then
		return false
	end
	local camera = Workspace.CurrentCamera
	if camera and (camera.CFrame.Position - at).Magnitude > KILL_FX.farStuds then
		return false
	end
	return start(path, "kills", CFrame.new(at), 1, function()
		return true
	end, floorUnder(at)) ~= nil
end

function KillVfx.banner(path: string, tier: number, place: () -> CFrame?, radius: number): boolean
	if live.bursts >= KILL_FX.maxBursts or not (radius > 0) then
		return false
	end
	local ok, first = pcall(place)
	if not ok or typeof(first) ~= "CFrame" then
		return false
	end
	local part = start(path, "bursts", first, radius, function(e: ParticleEmitter): boolean
		return KillVfx.tierAllows(e:GetAttribute("SD_MinTier"), tier)
	end)
	if part == nil then
		return false
	end
	follow(part, place)
	return true
end

function KillVfx.counts(): { [string]: number }
	return { bursts = live.bursts, kills = live.kills }
end

-- Removes every live effect at once (leak checks, Studio).
function KillVfx.clear()
	for part in carriers do
		release(part)
	end
	live.bursts, live.kills = 0, 0
end

return KillVfx
