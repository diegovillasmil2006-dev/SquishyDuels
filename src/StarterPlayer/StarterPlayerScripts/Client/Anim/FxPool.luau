--!strict
-- FxPool (client only). Pooled cosmetic instances for the animation runtime (DESIGN §9.1 #5, §9.2, §9.15):
-- ParticleEmitters, Trails and indicator Parts, kept under Workspace.SD_ClientFx. The folder and the pooled
-- instances are created on first use, never at require. Client-created parts never stream out.
--
--   local fx = FxPool.default()
--   fx:emit(cframe, 6, { Texture = Config.Vfx.Textures.smoke, Lifetime = NumberRange.new(0.35, 0.5) })
--   local trail = fx:acquireTrail(root, Vector3.new(0, 0.3, 0), Vector3.new(0, -0.3, 0), { Lifetime = 0.25 })
--   local ring = fx:acquirePart({ Size = Vector3.new(1, 0.1, 1) })
--   fx:release(trail); fx:release(ring)
--
-- * Emitters sit on Attachments of one invisible anchored "Anchor" part; emit() moves the attachment, Emit()s, and
--   releases the emitter once its longest particle has died. Counts are capped by Config.Vfx.Budgets
--   (liveParticlesPerEffect, liveParticlesTotal: the cosmetic burst is trimmed or dropped) and multiplied by
--   Config.Vfx.reducedParticleMultiplier while ReducedMotion (or setReduced(true), the "Effects: Reduced" setting) is on.
-- * Trails: acquireTrail() parents the trail and its two attachments to the caller's part and returns nil when
--   Config.Vfx.Budgets.activeTrails trails are out.
-- * Parts: anchored, CanCollide/CanTouch/CanQuery false, no shadow, collision group SD_Cosmetic when registered.
-- * release() calls Emitter:Clear() / Trail:Clear(), puts back every property the caller changed through `props`
--   (from a pristine copy), hides parts (Transparency 1) and destroys children the caller added to a part. An
--   instance whose parent was destroyed with it is dropped from the pool. Idle instances above
--   Config.Vfx.Pool.idlePerKind are destroyed. destroy() destroys the anchor and everything in the pool. The
--   SD_ClientFx folder is shared (HeldSquishyController parents the held models there too), so it is destroyed only
--   when this pool created it and nothing else is left in it.
-- Owns no frame connections; release timers are tracked and cancelled by destroy().

-- Services

local GuiService = game:GetService("GuiService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)

-- Types

export type Props = { [string]: any }

type Kind = "emitter" | "trail" | "part"

type Item = {
	kind: Kind,
	instance: Instance,
	attachment0: Attachment?, -- emitter: its attachment; trail: Attachment0
	attachment1: Attachment?, -- trail: Attachment1
	touched: { string }, -- property names set from props (reset on release)
	active: boolean,
}

type PoolData = {
	_parent: Instance,
	_folder: Folder?,
	_ownFolder: Folder?, -- the folder this pool created (nil when it found one)
	_anchor: BasePart?,
	_items: { [Instance]: Item },
	_idle: { [Kind]: { Item } },
	_active: { [Kind]: number },
	_bursts: { { count: number, untilAt: number } },
	_timers: { [thread]: boolean },
	_reduced: boolean,
	_destroyed: boolean,
}

-- Constants

local FOLDER_NAME = "SD_ClientFx"
local ANCHOR_NAME = "Anchor"
local COSMETIC_GROUP = "SD_Cosmetic"
local BUDGETS = Config.Vfx.Budgets
local REDUCED_MULTIPLIER = Config.Vfx.reducedParticleMultiplier
-- Pool sizing: idle instances kept per kind, and the delay after a burst's longest lifetime before its emitter is
-- reused.
local IDLE_LIMIT = Config.Vfx.Pool.idlePerKind
local RELEASE_MARGIN_SECONDS = Config.Vfx.Pool.releaseMarginSeconds

-- Module table

local PoolClass = {}
PoolClass.__index = PoolClass

export type FxPool = typeof(setmetatable({} :: PoolData, PoolClass))

local FxPool = {}

-- Private

local log = Log.new("FxPool")
local defaultPool: FxPool? = nil
local pristine: { [Kind]: Instance } = {}

local function cosmeticGroupRegistered(): boolean
	local ok, registered = pcall(PhysicsService.IsCollisionGroupRegistered, PhysicsService, COSMETIC_GROUP)
	return ok and registered == true
end

local function styleCosmeticPart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if cosmeticGroupRegistered() then
		part.CollisionGroup = COSMETIC_GROUP
	end
end

-- A never-parented reference copy per kind, used to put back properties a caller changed.
local function pristineOf(kind: Kind): Instance
	local existing = pristine[kind]
	if existing then
		return existing
	end
	local instance: Instance
	if kind == "emitter" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		instance = emitter
	elseif kind == "trail" then
		local trail = Instance.new("Trail")
		trail.Enabled = false
		instance = trail
	else
		local part = Instance.new("Part")
		styleCosmeticPart(part)
		instance = part
	end
	pristine[kind] = instance
	return instance
end

local function applyProps(item: Item, props: Props?)
	if props == nil then
		return
	end
	local target = item.instance :: any
	for key, value in props do
		target[key] = value
		if not table.find(item.touched, key) then
			table.insert(item.touched, key)
		end
	end
end

local function resetProps(item: Item)
	local reference = pristineOf(item.kind) :: any
	local target = item.instance :: any
	for _, key in item.touched do
		local ok, err = pcall(function()
			target[key] = reference[key]
		end)
		if not ok then
			log:warn(`could not reset {item.kind}.{key}:`, err)
		end
	end
	table.clear(item.touched)
end

local function ensureFolder(self: FxPool): (Folder, BasePart)
	local folder = self._folder
	if folder == nil or folder.Parent ~= self._parent then
		local found = self._parent:FindFirstChild(FOLDER_NAME)
		if found and found:IsA("Folder") then
			folder = found
		else
			local created = Instance.new("Folder")
			created.Name = FOLDER_NAME
			created.Parent = self._parent
			folder = created
			self._ownFolder = created
		end
		self._folder = folder
	end
	local anchor = self._anchor
	if anchor == nil or anchor.Parent ~= folder then
		local part = Instance.new("Part")
		part.Name = ANCHOR_NAME
		part.Size = Vector3.one * 0.2
		part.Transparency = 1
		part.CFrame = CFrame.identity
		styleCosmeticPart(part)
		part.Parent = folder
		anchor = part
		self._anchor = part
	end
	return folder :: Folder, anchor :: BasePart
end

local function takeIdle(self: FxPool, kind: Kind): Item?
	local idle = self._idle[kind]
	while #idle > 0 do
		local item = table.remove(idle) :: Item
		if item.instance.Parent ~= nil then
			return item
		end
		self._items[item.instance] = nil -- destroyed with a former parent
	end
	return nil
end

local function activate(self: FxPool, item: Item)
	item.active = true
	self._active[item.kind] += 1
end

local function liveParticles(self: FxPool, now: number): number
	local total = 0
	local bursts = self._bursts
	for index = #bursts, 1, -1 do
		local burst = bursts[index]
		if burst.untilAt <= now then
			table.remove(bursts, index)
		else
			total += burst.count
		end
	end
	return total
end

local function isReduced(self: FxPool): boolean
	return self._reduced or GuiService.ReducedMotionEnabled
end

-- Methods

-- A pooled ParticleEmitter (Enabled = false by default) on an attachment of the anchor part, with `props` applied.
function PoolClass.acquireEmitter(self: FxPool, props: Props?): ParticleEmitter
	assert(not self._destroyed, "[SD][FxPool] pool destroyed")
	local _, anchor = ensureFolder(self)
	local item = takeIdle(self, "emitter")
	if item == nil then
		local attachment = Instance.new("Attachment")
		attachment.Name = "Emitter"
		attachment.Parent = anchor
		local emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = false
		emitter.Parent = attachment
		local created: Item = {
			kind = "emitter",
			instance = emitter,
			attachment0 = attachment,
			attachment1 = nil,
			touched = {},
			active = false,
		}
		self._items[emitter] = created
		item = created
	end
	local ready = item :: Item
	applyProps(ready, props)
	activate(self, ready)
	return ready.instance :: ParticleEmitter
end

-- One-shot burst of `count` particles at `at` (CFrame or position), within the particle budgets. Returns the number
-- actually emitted (0 when the budget is full).
function PoolClass.emit(self: FxPool, at: CFrame | Vector3, count: number, props: Props?): number
	local wanted = math.floor(count * (if isReduced(self) then REDUCED_MULTIPLIER else 1))
	local now = os.clock()
	local room = BUDGETS.liveParticlesTotal - liveParticles(self, now)
	local n = math.min(wanted, BUDGETS.liveParticlesPerEffect, room)
	if n <= 0 then
		return 0
	end
	local emitter = self:acquireEmitter(props)
	local item = self._items[emitter]
	local attachment = item.attachment0 :: Attachment
	attachment.WorldCFrame = if typeof(at) == "CFrame" then at else CFrame.new(at)
	emitter:Emit(n)
	local lifetime = emitter.Lifetime.Max + RELEASE_MARGIN_SECONDS
	table.insert(self._bursts, { count = n, untilAt = now + lifetime })
	local timer: thread
	timer = task.delay(lifetime, function()
		self._timers[timer] = nil
		self:release(emitter)
	end)
	self._timers[timer] = true
	return n
end

-- A pooled Trail between two attachments placed at offset0/offset1 on `part` (the trail is parented to the part),
-- with `props` applied and Enabled = true. nil when the active-trail budget is used up.
function PoolClass.acquireTrail(self: FxPool, part: BasePart, offset0: Vector3, offset1: Vector3, props: Props?): Trail?
	assert(not self._destroyed, "[SD][FxPool] pool destroyed")
	local trailKind: Kind = "trail"
	if self._active[trailKind] >= BUDGETS.activeTrails then
		return nil
	end
	local _, anchor = ensureFolder(self)
	local item = takeIdle(self, "trail")
	if item == nil then
		local a0 = Instance.new("Attachment")
		a0.Name = "Trail0"
		local a1 = Instance.new("Attachment")
		a1.Name = "Trail1"
		local trail = Instance.new("Trail")
		trail.Enabled = false
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		a0.Parent = anchor
		a1.Parent = anchor
		trail.Parent = anchor
		local created: Item = {
			kind = "trail",
			instance = trail,
			attachment0 = a0,
			attachment1 = a1,
			touched = {},
			active = false,
		}
		self._items[trail] = created
		item = created
	end
	local ready = item :: Item
	local trail = ready.instance :: Trail
	local a0, a1 = ready.attachment0 :: Attachment, ready.attachment1 :: Attachment
	a0.Position = offset0
	a1.Position = offset1
	a0.Parent = part
	a1.Parent = part
	trail.Parent = part
	trail:Clear()
	applyProps(ready, props)
	trail.Enabled = true
	activate(self, ready)
	return trail
end

-- A pooled indicator Part in the SD_ClientFx folder (cosmetic settings, visible), with `props` applied.
function PoolClass.acquirePart(self: FxPool, props: Props?): BasePart
	assert(not self._destroyed, "[SD][FxPool] pool destroyed")
	local folder = ensureFolder(self)
	local item = takeIdle(self, "part")
	if item == nil then
		local part = Instance.new("Part")
		part.Name = "Indicator"
		styleCosmeticPart(part)
		part.Parent = folder
		local created: Item = {
			kind = "part",
			instance = part,
			attachment0 = nil,
			attachment1 = nil,
			touched = {},
			active = false,
		}
		self._items[part] = created
		item = created
	end
	local ready = item :: Item
	local part = ready.instance :: BasePart
	part.Transparency = (pristineOf("part") :: BasePart).Transparency
	applyProps(ready, props)
	activate(self, ready)
	return part
end

-- Returns an instance from acquire*() to the pool. Unknown or already released instances are ignored.
function PoolClass.release(self: FxPool, instance: Instance)
	local item = self._items[instance]
	if item == nil or not item.active or self._destroyed then
		return
	end
	item.active = false
	self._active[item.kind] -= 1
	local alive = pcall(function()
		if item.kind == "emitter" then
			local emitter = instance :: ParticleEmitter
			emitter.Enabled = false
			emitter:Clear()
		elseif item.kind == "trail" then
			local trail = instance :: Trail
			trail.Enabled = false
			trail:Clear()
			local _, anchor = ensureFolder(self)
			local a0 = item.attachment0 :: Attachment
			local a1 = item.attachment1 :: Attachment
			trail.Parent = anchor
			a0.Parent = anchor
			a1.Parent = anchor
		else
			local part = instance :: BasePart
			part:ClearAllChildren()
		end
	end)
	if not alive then
		self._items[instance] = nil -- destroyed with the caller's part
		return
	end
	resetProps(item)
	if item.kind == "part" then
		local part = instance :: BasePart
		part.Transparency = 1 -- hidden while idle
	end
	local idle = self._idle[item.kind]
	if #idle >= IDLE_LIMIT then
		self._items[instance] = nil
		instance:Destroy()
		local a0, a1 = item.attachment0, item.attachment1
		if a0 then
			a0:Destroy()
		end
		if a1 then
			a1:Destroy()
		end
		return
	end
	table.insert(idle, item)
end

-- Number of acquired (not yet released) instances of a kind.
function PoolClass.activeCount(self: FxPool, kind: Kind): number
	return self._active[kind]
end

-- "Effects: Reduced" setting: particle counts × Config.Vfx.reducedParticleMultiplier (ReducedMotion always counts).
function PoolClass.setReduced(self: FxPool, reduced: boolean)
	self._reduced = reduced
end

-- Cancels pending releases and destroys the anchor and every pooled instance. The shared SD_ClientFx folder is
-- destroyed only when this pool created it and it is empty (held models live there too).
function PoolClass.destroy(self: FxPool)
	if self._destroyed then
		return
	end
	self._destroyed = true
	for timer in self._timers do
		if coroutine.status(timer) == "suspended" then
			task.cancel(timer)
		end
	end
	table.clear(self._timers)
	for instance, item in self._items do
		instance:Destroy()
		if item.attachment0 then
			item.attachment0:Destroy()
		end
		if item.attachment1 then
			item.attachment1:Destroy()
		end
	end
	table.clear(self._items)
	local anchor = self._anchor
	if anchor then
		anchor:Destroy()
	end
	local folder = self._folder
	if folder and folder == self._ownFolder and #folder:GetChildren() == 0 then
		folder:Destroy()
	end
	self._folder = nil
	self._ownFolder = nil
	self._anchor = nil
	if defaultPool == self then
		defaultPool = nil
	end
end

-- Public

-- A pool whose SD_ClientFx folder goes under `parent` (default Workspace). Nothing is created until first use.
function FxPool.new(parent: Instance?): FxPool
	local data: PoolData = {
		_parent = parent or Workspace,
		_folder = nil,
		_ownFolder = nil,
		_anchor = nil,
		_items = {},
		_idle = { emitter = {}, trail = {}, part = {} },
		_active = { emitter = 0, trail = 0, part = 0 },
		_bursts = {},
		_timers = {},
		_reduced = false,
		_destroyed = false,
	}
	return setmetatable(data, PoolClass)
end

-- The client's shared pool (Workspace.SD_ClientFx), created on first use.
function FxPool.default(): FxPool
	if defaultPool == nil then
		defaultPool = FxPool.new(Workspace)
	end
	return defaultPool :: FxPool
end

return FxPool
