--!strict
-- ThrowVfx (client only). Plays the throw effects authored for the VFX Studio plugin, ReplicatedStorage.SD_ThrowVfx
-- (made by ServerStorage.SDTools.Builders.ThrowVfxBuilder, then tuned in VFX Studio; 2026-10-15 throw overhaul).
-- Every effect is a clone of a template Part (its carrier) under Workspace.SD_ClientFx.ThrowVfx: cosmetic only
-- (anchored, CanCollide / CanQuery / CanTouch false, SD_Cosmetic when that group exists), never replicated.
--
-- VFX Studio's emit contract, as the plugin's own trigger code runs it (read in Studio 2026-10-15), per ParticleEmitter:
-- wait EmitDelay (default 0); EmitDuration > 0 = Enabled for that long, else Emit(EmitCount) (default 1). Ours on top:
--   * scale: the templates are sized for a throw radius of 1 stud; attachment positions, particle sizes and
--     accelerations × scale, speeds × sqrt(scale) (scaleSequence, pure);
--   * SD_Tint "accent" (emitters and trails): coloured accent -> accent:Lerp(White, TINT_LIGHTEN) (tintSequence);
--   * SD_Feels (emitters): only for toys of those feels (feelAllowed);
--   * SD_Role "flight" / "while": rate-driven emitters a handle switches on and off (trail(), hold());
--   * counts and rates × Config.Vfx.reducedParticleMultiplier under ReducedMotion, × LOW_SHARE for `low` effects
--     (another player's practice throw), at least 1 when the template asked for any (emitPlan, pure).
-- Budgets (our own): at most MAX_TRAILS flight trails and MAX_BURSTS live bursts; a new one over the cap is dropped
-- (a trail returns nil). A missing library (SD_ThrowVfx not replicated yet, or deleted) only means no effect.
--
-- API
--   ThrowVfx.burst(name, at, opts?) -> boolean           a one-shot Bursts/<name> at CFrame `at` (its Y = up/normal)
--   ThrowVfx.trail(squishyId, opts?) -> Handle?          Trails/<squishyId> on, following handle:set(cframe, roll?)
--   ThrowVfx.hold(name, opts?) -> Handle?                a "while" effect (Bursts/Skid): handle:set(...), :setOn(on)
--   ThrowVfx.swoosh(hand, opts?) -> boolean              Bursts/HandSwoosh's trail on `hand` for opts.seconds
--   Handle:set(cframe, roll?)   moves the carrier (roll about its -Z only for SD_FollowRoll templates)
--   Handle:setOn(on)            switches its "flight" / "while" emitters (trails stay on)
--   Handle:stop()               stops emitting and trailing; the carrier goes once the last particle has died
--   ThrowVfx.emitPlan(attrs, multiplier) -> (delay, count, duration)   pure: the contract above
--   ThrowVfx.scaleSequence(seq, k) / tintSequence(accent) / feelAllowed(list, feel)   pure helpers (tests)
--   ThrowVfx.counts() -> { trails, bursts, holds }   / ThrowVfx.clear()   Studio, tests and leak checks

-- Services

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local Tweens = require(script.Parent.Tweens)

-- Types

export type Options = {
	accent: Color3?, -- SD_Tint "accent" pieces take it (default Palette.White)
	feel: string?, -- the toy's Config.Anim.rig.feels name, for SD_Feels
	scale: number?, -- the throw radius in studs (templates are made for 1)
	low: boolean?, -- another player's practice throw: fewer particles
	seconds: number?, -- swoosh: how long the hand trails
}

export type Handle = {
	part: BasePart,
	followRoll: boolean,
	set: (self: Handle, frame: CFrame, roll: number?) -> (),
	setOn: (self: Handle, on: boolean) -> (),
	stop: (self: Handle) -> (),
	stopped: boolean,
	emitters: { ParticleEmitter },
	trails: { Trail },
	linger: number,
	kind: string,
}

-- Constants

local LIBRARY_NAME = "SD_ThrowVfx"
local FX_FOLDER = "SD_ClientFx"
local OWN_FOLDER = "ThrowVfx"
local COSMETIC_GROUP = "SD_Cosmetic"
local MAX_TRAILS = 10
local MAX_BURSTS = 28
local MAX_HOLDS = 8
local LOW_SHARE = 0.5
local TINT_LIGHTEN = 0.55
local END_MARGIN = 0.15 -- seconds after the longest particle before a carrier goes
local ROLE_FLIGHT = "flight"
local ROLE_WHILE = "while"

-- Module table

local ThrowVfx = {}

-- Private state

local folder: Folder? = nil
local live = { trails = 0, bursts = 0, holds = 0 }
local handles: { [Handle]: boolean } = {}
local bursts: { [BasePart]: boolean } = {}

-- Pure helpers ------------------------------------------------------------------------------------------------------

-- VFX Studio's contract for one emitter's attributes, with our particle multiplier: (delay, count, duration).
-- duration > 0 means "Enabled for duration"; else Emit(count). A template that asked for particles keeps >= 1.
function ThrowVfx.emitPlan(attrs: { [string]: any }, multiplier: number): (number, number, number)
	local delay = if type(attrs.EmitDelay) == "number" then math.max(attrs.EmitDelay, 0) else 0
	local asked = if type(attrs.EmitCount) == "number" then attrs.EmitCount else 1
	local duration = if type(attrs.EmitDuration) == "number" then math.max(attrs.EmitDuration, 0) else 0
	local count = 0
	if asked > 0 then
		count = math.max(1, math.floor(asked * multiplier + 0.5))
	end
	return delay, count, duration
end

-- A NumberSequence with every value and envelope × k.
function ThrowVfx.scaleSequence(seq: NumberSequence, k: number): NumberSequence
	local keys = {}
	for _, key in seq.Keypoints do
		table.insert(keys, NumberSequenceKeypoint.new(key.Time, key.Value * k, key.Envelope * k))
	end
	return NumberSequence.new(keys)
end

-- The accent tint: accent -> a lighter accent.
function ThrowVfx.tintSequence(accent: Color3): ColorSequence
	return ColorSequence.new(accent, accent:Lerp(Palette.White, TINT_LIGHTEN))
end

-- SD_Feels: nil or empty = every toy; else a comma list that must name `feel`.
function ThrowVfx.feelAllowed(list: unknown, feel: string?): boolean
	if type(list) ~= "string" or list == "" then
		return true
	end
	if feel == nil then
		return false
	end
	for name in string.gmatch(list, "[^,%s]+") do
		if name == feel then
			return true
		end
	end
	return false
end

-- Private -----------------------------------------------------------------------------------------------------------

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
	return m
end

-- Clones a template and prepares it: scale, tint and the feel filter. Returns the carrier, its emitters (feel-allowed
-- only), its trails and the longest particle or trail lifetime.
local function prepare(template: BasePart, opts: Options?): (BasePart, { ParticleEmitter }, { Trail }, number)
	local part = template:Clone()
	styleCarrier(part)
	local scale = if opts and opts.scale and opts.scale > 0 then opts.scale else 1
	local accent = if opts and opts.accent then opts.accent else Palette.White
	local feel = if opts then opts.feel else nil
	local speedK = math.sqrt(scale)
	local emitters: { ParticleEmitter } = {}
	local trails: { Trail } = {}
	local longest = 0
	for _, d in part:GetDescendants() do
		if d:IsA("Attachment") and scale ~= 1 then
			d.Position *= scale
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
			if not ThrowVfx.feelAllowed(d:GetAttribute("SD_Feels"), feel) then
				d:Destroy()
				continue
			end
			if scale ~= 1 then
				d.Size = ThrowVfx.scaleSequence(d.Size, scale)
				d.Speed = NumberRange.new(d.Speed.Min * speedK, d.Speed.Max * speedK)
				d.Acceleration *= scale
			end
			if d:GetAttribute("SD_Tint") == "accent" then
				d.Color = ThrowVfx.tintSequence(accent)
			end
			longest = math.max(longest, d.Lifetime.Max)
			table.insert(emitters, d)
		elseif d:IsA("Trail") then
			if d:GetAttribute("SD_Tint") == "accent" then
				d.Color = ColorSequence.new(Palette.White, accent)
			end
			longest = math.max(longest, d.Lifetime)
			table.insert(trails, d)
		end
	end
	return part, emitters, trails, longest
end

local function template(group: string, name: string): BasePart?
	local lib = library()
	local holder = lib and lib:FindFirstChild(group)
	local found = holder and holder:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		return found
	end
	return nil
end

-- Runs one emitter's VFX Studio contract (burst effects). Returns when it ends (seconds from now).
local function runEmitter(e: ParticleEmitter, multiplier: number): number
	local attrs = e:GetAttributes()
	local delay, count, duration = ThrowVfx.emitPlan(attrs, multiplier)
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

local function newHandle(
	kind: string,
	part: BasePart,
	emitters: { ParticleEmitter },
	trails: { Trail },
	linger: number
): Handle
	local handle = {
		part = part,
		followRoll = part:GetAttribute("SD_FollowRoll") == true,
		stopped = false,
		emitters = emitters,
		trails = trails,
		linger = linger,
		kind = kind,
	} :: any
	function handle.set(self: Handle, frame: CFrame, roll: number?)
		if self.stopped then
			return
		end
		if self.followRoll and roll then
			self.part.CFrame = frame * CFrame.Angles(0, 0, roll)
		else
			self.part.CFrame = frame
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
			t.Enabled = false -- its segments fade out on their own lifetime
		end
		local carrier = self.part
		task.delay(self.linger + END_MARGIN, function()
			if handles[self] then
				handles[self] = nil
				if self.kind == "trail" then
					live.trails = math.max(live.trails - 1, 0)
				else
					live.holds = math.max(live.holds - 1, 0)
				end
			end
			carrier:Destroy()
		end)
	end
	handles[handle :: Handle] = true
	return handle :: Handle
end

-- Public ------------------------------------------------------------------------------------------------------------

function ThrowVfx.burst(name: string, at: CFrame, opts: Options?): boolean
	if live.bursts >= MAX_BURSTS then
		return false
	end
	local source = template("Bursts", name)
	if source == nil then
		return false
	end
	local part, emitters, _, _ = prepare(source, opts)
	part.CFrame = at
	part.Parent = ownFolder()
	local multiplier = multiplierFor(opts)
	local ends = 0
	for _, e in emitters do
		ends = math.max(ends, runEmitter(e, multiplier))
	end
	live.bursts += 1
	bursts[part] = true
	task.delay(ends + END_MARGIN, function()
		if bursts[part] then
			bursts[part] = nil
			live.bursts = math.max(live.bursts - 1, 0)
		end
		part:Destroy()
	end)
	return true
end

function ThrowVfx.trail(squishyId: string, opts: Options?): Handle?
	if live.trails >= MAX_TRAILS then
		return nil
	end
	local source = template("Trails", squishyId)
	if source == nil then
		return nil
	end
	local part, emitters, trails, longest = prepare(source, opts)
	local multiplier = multiplierFor(opts)
	local flight: { ParticleEmitter } = {}
	for _, e in emitters do
		if e:GetAttribute("SD_Role") == ROLE_FLIGHT then
			e.Rate *= multiplier
			table.insert(flight, e)
		else
			runEmitter(e, multiplier) -- a template's one-shot piece (none today) plays at the start
		end
	end
	part.Parent = ownFolder()
	live.trails += 1
	local handle = newHandle("trail", part, flight, trails, longest)
	handle:setOn(true)
	return handle
end

function ThrowVfx.hold(name: string, opts: Options?): Handle?
	if live.holds >= MAX_HOLDS then
		return nil
	end
	local source = template("Bursts", name)
	if source == nil then
		return nil
	end
	local part, emitters, trails, longest = prepare(source, opts)
	local multiplier = multiplierFor(opts)
	local held: { ParticleEmitter } = {}
	for _, e in emitters do
		if e:GetAttribute("SD_Role") == ROLE_WHILE then
			e.Rate *= multiplier
			table.insert(held, e)
		end
	end
	part.Parent = ownFolder()
	live.holds += 1
	return newHandle("hold", part, held, trails, longest)
end

function ThrowVfx.swoosh(hand: BasePart, opts: Options?): boolean
	local source = template("Bursts", "HandSwoosh")
	if source == nil or hand.Parent == nil then
		return false
	end
	local part, _, trails, longest = prepare(source, opts)
	local seconds = if opts and opts.seconds then opts.seconds else 0.3
	-- The trail's attachments move onto the hand; the carrier itself stays out of the world.
	local moved: { Instance } = {}
	for _, t in trails do
		local a0, a1 = t.Attachment0, t.Attachment1
		if a0 and a1 then
			a0.Parent = hand
			a1.Parent = hand
			t.Parent = hand
			table.insert(moved, a0)
			table.insert(moved, a1)
			table.insert(moved, t)
		end
	end
	part:Destroy()
	task.delay(seconds, function()
		for _, t in trails do
			t.Enabled = false
		end
	end)
	task.delay(seconds + longest + END_MARGIN, function()
		for _, item in moved do
			item:Destroy()
		end
	end)
	return #moved > 0
end

function ThrowVfx.counts(): { [string]: number }
	return { trails = live.trails, bursts = live.bursts, holds = live.holds }
end

-- Removes every live effect at once (leak checks, Studio).
function ThrowVfx.clear()
	for handle in handles do
		handles[handle] = nil
		handle.stopped = true
		handle.part:Destroy()
	end
	for part in bursts do
		bursts[part] = nil
		part:Destroy()
	end
	live.trails, live.bursts, live.holds = 0, 0, 0
end

return ThrowVfx
