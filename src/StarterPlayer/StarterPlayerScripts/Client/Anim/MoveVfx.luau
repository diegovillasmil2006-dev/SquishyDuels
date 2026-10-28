--!strict
-- MoveVfx (client only). Plays the dash and double jump effects authored for the VFX Studio plugin,
-- ReplicatedStorage.SD_MoveVfx (made by ServerStorage.SDTools.Builders.MoveVfxBuilder, then tuned in VFX Studio;
-- 2026-10-15 dash + double jump overhaul). Every effect is a clone of a template Part (its carrier) under
-- Workspace.SD_ClientFx.MoveVfx: cosmetic only (anchored, CanCollide / CanQuery / CanTouch false, SD_Cosmetic when that
-- group exists), never replicated.
--
-- The emit contract is VFX Studio's, as Anim/ThrowVfx runs it (ThrowVfx.emitPlan): per ParticleEmitter, wait
-- EmitDelay; EmitDuration > 0 = Enabled for that long, else Emit(EmitCount). Ours on top:
--   * SD_Tint "team" (emitters and trails): emitters take tint -> a lighter tint (ThrowVfx.tintSequence); trails
--     white -> tint, or tint -> white when SD_TintFirst;
--   * SD_Role "while": rate-driven emitters a hold switches on and off (Handle:setOn); a hold's other emitters play
--     their burst once when it starts;
--   * counts and rates × Config.Vfx.reducedParticleMultiplier under ReducedMotion, × LOW_SHARE for `low` effects
--     (a player who is neither this one nor the duel opponent), at least 1 when the template asked for any.
-- Budgets (our own): at most MAX_BURSTS live bursts, MAX_HOLDS holds and MAX_PART_TRAILS part trails; one over its cap
-- is dropped. A missing library (not replicated yet, or deleted) only means no effect.
--
-- API (paths are "<Folder>/<Template>", e.g. "Dash/Start")
--   MoveVfx.burst(path, at, opts?) -> boolean            a one-shot at CFrame `at`
--   MoveVfx.hold(path, opts?) -> Handle?                  a held effect: handle:set(cframe) each frame, :setOn(on), :stop()
--   MoveVfx.onParts(path, parts, seconds, opts?) -> number   the template's trails (and their attachments) on each part
--                                                          for `seconds`, then they fade; returns how many parts got one
--   MoveVfx.trailColor(tint, tintFirst) -> ColorSequence  pure (tests)
--   MoveVfx.counts() -> { bursts, holds, partTrails }  / MoveVfx.clear()   Studio, tests and leak checks

-- Services

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local ThrowVfx = require(script.Parent.ThrowVfx)
local Tweens = require(script.Parent.Tweens)

-- Types

export type Options = {
	tint: Color3?, -- SD_Tint "team" pieces take it (none = they keep the template's own colours)
	low: boolean?, -- a far-away player's effect: fewer particles
	-- 2026-10-28 physics upgrade (Anim/FeelFx): SD_Tint "floor" emitters take `floor` (the extras' floor-tinted dust);
	-- counts and rates x `scale` (the phone's halves, the hop chain); trails last x `trailScale` (phones).
	floor: Color3?,
	scale: number?,
	trailScale: number?,
}

export type Handle = {
	part: BasePart,
	set: (self: Handle, frame: CFrame) -> (),
	setOn: (self: Handle, on: boolean) -> (),
	stop: (self: Handle) -> (),
	stopped: boolean,
	emitters: { ParticleEmitter },
	trails: { Trail },
	linger: number,
}

-- Constants

local LIBRARY_NAME = "SD_MoveVfx"
local FX_FOLDER = "SD_ClientFx"
local OWN_FOLDER = "MoveVfx"
local COSMETIC_GROUP = "SD_Cosmetic"
local MAX_BURSTS = 24
local MAX_HOLDS = 10
local MAX_PART_TRAILS = 10
local LOW_SHARE = 0.5
local END_MARGIN = 0.15 -- seconds after the longest particle before a carrier goes
local ROLE_WHILE = "while"
local TINT_TEAM = "team"
local TINT_FLOOR = "floor"

-- Module table

local MoveVfx = {}

-- Private state

local folder: Folder? = nil
local live = { bursts = 0, holds = 0, partTrails = 0 }
local handles: { [Handle]: boolean } = {}
local bursts: { [BasePart]: boolean } = {}
local partTrails: { [Instance]: boolean } = {} -- the moved trails (cleared by clear())

-- Pure helpers ---------------------------------------------------------------------------------------------------------

function MoveVfx.trailColor(tint: Color3, tintFirst: boolean): ColorSequence
	if tintFirst then
		return ColorSequence.new(tint, Palette.White)
	end
	return ColorSequence.new(Palette.White, tint)
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

local function multiplierFor(opts: Options?): number
	local m = 1
	if Tweens.reducedMotion() then
		m *= Config.Vfx.reducedParticleMultiplier
	end
	if opts and opts.low then
		m *= LOW_SHARE
	end
	if opts and opts.scale then
		m *= opts.scale
	end
	return m
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

-- Clones a template and tints it. Returns the carrier, its emitters, its trails and the longest lifetime.
local function prepare(source: BasePart, opts: Options?): (BasePart, { ParticleEmitter }, { Trail }, number)
	local part = source:Clone()
	styleCarrier(part)
	local tint = if opts then opts.tint else nil
	local floor = if opts then opts.floor else nil
	local trailScale = if opts and opts.trailScale then opts.trailScale else 1
	local emitters: { ParticleEmitter } = {}
	local trails: { Trail } = {}
	local longest = 0
	for _, d in part:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			local kind = d:GetAttribute("SD_Tint")
			if kind == TINT_TEAM and tint then
				d.Color = ThrowVfx.tintSequence(tint)
			elseif kind == TINT_FLOOR and floor then
				d.Color = ColorSequence.new(floor)
			end
			longest = math.max(longest, d.Lifetime.Max)
			table.insert(emitters, d)
		elseif d:IsA("Trail") then
			if d:GetAttribute("SD_Tint") == TINT_TEAM and tint then
				d.Color = MoveVfx.trailColor(tint, d:GetAttribute("SD_TintFirst") == true)
			end
			d.Lifetime *= trailScale
			longest = math.max(longest, d.Lifetime)
			table.insert(trails, d)
		end
	end
	return part, emitters, trails, longest
end

-- Calls fn after `seconds` of the particles' own time: FeelFx's slow motion and hit-stop freeze lower the TimeScale of
-- every emitter under SD_ClientFx, and a slowed burst keeps its particles to their end (at most 8x longer in real time).
local function afterParticleTime(seconds: number, probe: ParticleEmitter?, fn: () -> ())
	task.spawn(function()
		local left, start = seconds, os.clock()
		while left > 0 and os.clock() - start < seconds * 8 do
			left -= task.wait() * (if probe and probe.Parent then probe.TimeScale else 1)
		end
		fn()
	end)
end

-- Runs one emitter's VFX Studio contract. Returns when it ends (seconds from now).
local function runEmitter(e: ParticleEmitter, multiplier: number): number
	local delay, count, duration = ThrowVfx.emitPlan(e:GetAttributes(), multiplier)
	if duration > 0 then
		e.Rate *= multiplier
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

-- Public -------------------------------------------------------------------------------------------------------------

function MoveVfx.burst(path: string, at: CFrame, opts: Options?): boolean
	if live.bursts >= MAX_BURSTS then
		return false
	end
	local source = template(path)
	if source == nil then
		return false
	end
	local part, emitters, trails, _ = prepare(source, opts)
	for _, t in trails do
		t.Enabled = false -- a burst does not move, so its trails would draw nothing
	end
	part.CFrame = at
	part.Parent = ownFolder()
	local multiplier = multiplierFor(opts)
	local ends = 0
	for _, e in emitters do
		ends = math.max(ends, runEmitter(e, multiplier))
	end
	live.bursts += 1
	bursts[part] = true
	afterParticleTime(ends + END_MARGIN, emitters[1], function()
		if bursts[part] then
			bursts[part] = nil
			live.bursts = math.max(live.bursts - 1, 0)
		end
		part:Destroy()
	end)
	return true
end

function MoveVfx.hold(path: string, opts: Options?): Handle?
	if live.holds >= MAX_HOLDS then
		return nil
	end
	local source = template(path)
	if source == nil then
		return nil
	end
	local part, emitters, trails, longest = prepare(source, opts)
	local multiplier = multiplierFor(opts)
	local held: { ParticleEmitter } = {}
	local once: { ParticleEmitter } = {}
	for _, e in emitters do
		if e:GetAttribute("SD_Role") == ROLE_WHILE then
			e.Rate *= multiplier
			table.insert(held, e)
		else
			table.insert(once, e)
		end
	end
	for _, t in trails do
		t.Enabled = false -- on with the first set(), so nothing streaks in from the template's spot
	end
	part.Parent = ownFolder()
	for _, e in once do
		runEmitter(e, multiplier)
	end
	live.holds += 1
	local placed = false
	local handle = {
		part = part,
		stopped = false,
		emitters = held,
		trails = trails,
		linger = longest,
	} :: any
	function handle.set(self: Handle, frame: CFrame)
		if self.stopped then
			return
		end
		self.part.CFrame = frame
		if not placed then
			placed = true
			for _, t in self.trails do
				t:Clear()
				t.Enabled = true
			end
		end
	end
	function handle.setOn(self: Handle, on: boolean)
		if self.stopped then
			return
		end
		for _, e in self.emitters do
			e.Enabled = on
		end
	end
	function handle.stop(self: Handle)
		if self.stopped then
			return
		end
		self.stopped = true
		for _, e in self.emitters do
			e.Enabled = false
		end
		for _, t in self.trails do
			t.Enabled = false -- its segments fade on their own lifetime
		end
		local carrier = self.part
		afterParticleTime(self.linger + END_MARGIN, self.emitters[1], function()
			if handles[self] then
				handles[self] = nil
				live.holds = math.max(live.holds - 1, 0)
			end
			carrier:Destroy()
		end)
	end
	handles[handle :: Handle] = true
	return handle :: Handle
end

function MoveVfx.onParts(path: string, parts: { BasePart }, seconds: number, opts: Options?): number
	local source = template(path)
	if source == nil then
		return 0
	end
	local placed = 0
	for _, target in parts do
		if live.partTrails >= MAX_PART_TRAILS or target.Parent == nil then
			continue
		end
		local part, _, trails, longest = prepare(source, opts)
		local moved: { Instance } = {}
		for _, t in trails do
			local a0, a1 = t.Attachment0, t.Attachment1
			if a0 and a1 then
				a0.Parent = target
				a1.Parent = target
				t.Parent = target
				t:Clear()
				t.Enabled = true
				table.insert(moved, a0)
				table.insert(moved, a1)
				table.insert(moved, t)
			end
		end
		part:Destroy()
		if #moved == 0 then
			continue
		end
		placed += 1
		live.partTrails += 1
		for _, item in moved do
			partTrails[item] = true
		end
		task.delay(seconds, function()
			for _, item in moved do
				if item:IsA("Trail") then
					item.Enabled = false
				end
			end
		end)
		task.delay(seconds + longest + END_MARGIN, function()
			local counted = false
			for _, item in moved do
				if partTrails[item] then
					partTrails[item] = nil
					counted = true
				end
				item:Destroy()
			end
			if counted then
				live.partTrails = math.max(live.partTrails - 1, 0)
			end
		end)
	end
	return placed
end

function MoveVfx.counts(): { [string]: number }
	return { bursts = live.bursts, holds = live.holds, partTrails = live.partTrails }
end

-- Removes every live effect at once (leak checks, Studio).
function MoveVfx.clear()
	for handle in handles do
		handles[handle] = nil
		handle.stopped = true
		handle.part:Destroy()
	end
	for part in bursts do
		bursts[part] = nil
		part:Destroy()
	end
	for item in partTrails do
		partTrails[item] = nil
		item:Destroy()
	end
	live.bursts, live.holds, live.partTrails = 0, 0, 0
end

return MoveVfx
