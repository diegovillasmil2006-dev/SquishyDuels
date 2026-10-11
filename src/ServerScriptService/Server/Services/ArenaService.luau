--!strict
-- ArenaService (server only). DESIGN §2.3, §5.3, §5.4, §7.8.
-- The arena slot pool: up to Config.Duel.Arena.MaxSlots (6) clones of the template
-- ServerStorage.SD_Templates.Arena_CandyCourt (found by WorldService), placed in Workspace.SD_ArenaSlots (created at
-- runtime) on the grid Config.Duel.Arena.SlotOrigins (X 320/520 x Z -300..300, far from the lobby). Clones are made
-- lazily (PrewarmSlots at start), pivoted to their slot BEFORE they are parented, and kept for the server's lifetime;
-- release() clears the slot's Runtime folder and resets its state so the next match reuses it. The template is never
-- changed. Without a template, duels are disabled: available() is false, freeCount() is 0, acquire() returns nil
-- (QueueJoin answers queue.unavailable).
--
-- A Slot (plain table, read-only for callers except through the functions below):
--   index, model, origin (the Origin part's CFrame), floorY (floor top = Origin.Y, §5.3), killY (floorY +
--   Config.Duel.Rules.OutOfBounds.KillYOffset), geometry, runtime, zones { HalfA, Neutral, HalfB, Bounds = {cframe,
--   size} }, pads { A, B = CFrame } and padParts { A, B = BasePart }, inUse, matchId, acquiredAt, leaseUntil, and
--   the projectile query parameters made once per slot:
--     raycastParams  Include = every child of Geometry except Geometry/Barriers (Floor, Markings, Rails, Cover),
--                    CollisionGroup "Default" (§5.3 Part 4 rule: the barriers and dividers are skipped because their
--                    groups collide only with SD_Characters; Roblox ignores CanQuery = false on colliding parts)
--     overlapParams  the same Include list and group, for GetPartBoundsInRadius / InBox (spawn overlap, §5.6 #11;
--                    Dragon Rush room check, §5.9)
-- Pads are rolled cylinders: a pad CFrame here is CFrame.lookAt(pad.Position, pad.Position + pad.CFrame.LookVector),
-- never pad.CFrame (§5.3). placementCFrame(slot, side, height) adds the §5.4 character height above the pad.
-- Zones are read once from the clone (CFrame and Size only). inZone / inOwnHalf / inBounds / zoneAt answer the §5.6
-- #5 and §5.4 out-of-bounds questions; a margin widens a zone in X and Z only (reading: "own half + 2 studs" is a
-- horizontal tolerance; the zones already span Y -15..40).
--
-- Leases (§5.3 "A janitor every 5 s voids matches whose lease expired"): acquire() starts a lease of leaseSeconds()
-- (reading, DESIGN gives only the grace: the longest possible match = Preparing + Positioning + Countdown + Active +
-- SuddenDeath + Result + the Returning stream wait, plus Config.Duel.Arena.LeaseGraceSeconds). renewLease extends it.
-- Every JanitorIntervalSeconds an expired slot is logged as an error and `LeaseExpired(slot, matchId)` fires once:
-- DuelService voids that match, returns its players and releases the slot itself when they are back (or at once
-- when no match of its own holds it), so a new pair never lands in an arena whose players are still being returned.
-- A slot without a matchId is released at once; one still held Config.Duel.Arena.LeaseDrainSeconds after its lease
-- expired is released by the janitor anyway (logged), so the pool never leaks.
-- Handoff (reading, for the QueueService -> DuelService call): QueueService acquires a slot only when it pairs two
-- players (§5.4 "pair only if ArenaService.acquire() returns a slot") and passes it to DuelService.startMatch. While
-- that call runs, handoff(slot) makes the next acquire() return that same slot, so a DuelService that acquires its
-- own slot still gets exactly one.
-- `SlotReleased(slot)` fires after every release (QueueService pairs again on it, §5.4).
-- No grid or zone value is typed here: everything comes from Config.Duel and the template.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local WorldService = require(script.Parent.WorldService)

-- Types

export type Zone = Types.ArenaZone

export type Slot = {
	index: number,
	model: Model,
	origin: CFrame,
	floorY: number,
	killY: number,
	geometry: Instance,
	runtime: Instance,
	raycastParams: RaycastParams,
	overlapParams: OverlapParams,
	zones: { [string]: Zone },
	pads: { [string]: CFrame }, -- "A" / "B"
	padParts: { [string]: BasePart }, -- "A" / "B"
	inUse: boolean,
	matchId: string?,
	acquiredAt: number?,
	leaseUntil: number?,
	drainUntil: number?, -- lease expired: the owner has until then to release the slot
}

-- Constants

local CONTAINER_NAME = "SD_ArenaSlots"
local CLONE_PREFIX = "Arena_"
local ATTR_SLOT = "SD_ArenaSlot"
local TAG_GENERATED = "SD_Generated"
local ORIGIN_NAME = "Origin"
local GEOMETRY_NAME = "Geometry"
local BARRIERS_NAME = "Barriers"
local ZONES_NAME = "Zones"
local SPAWNS_NAME = "Spawns"
local RUNTIME_NAME = "Runtime"
local DEFAULT_GROUP = "Default"
local ZONE_NAMES = { "HalfA", "Neutral", "HalfB", "Bounds" }
local HALF_ZONES = { "HalfA", "Neutral", "HalfB" }
local PAD_NAMES: { [string]: string } = { A = "PadA", B = "PadB" }
local HALF_BY_SIDE: { [string]: string } = { A = "HalfA", B = "HalfB" }

-- Module table

local ArenaService = {}

-- Fired with (slot) after a slot was released (and its Runtime cleared).
ArenaService.SlotReleased = Signal.new() :: Signal.Signal<Slot>
-- Fired with (slot, matchId?) when a slot's lease ran out; the slot is released right after the handlers start.
ArenaService.LeaseExpired = Signal.new() :: Signal.Signal<Slot, string?>

-- Private

-- What this module logs through (useTemplate may swap it, so tests can check the log without console noise).
export type Logger = {
	warn: (self: any, ...any) -> (),
	error: (self: any, ...any) -> (),
}

local DEFAULT_LOG: Logger = Log.new("Arena") :: any
local log: Logger = DEFAULT_LOG
local template: Instance? = nil
local templateBroken = false
local container: Instance? = nil -- clones' parent; nil = Workspace.SD_ArenaSlots (made on the first clone)
local slots: { [number]: Slot } = {}
local handoffSlot: Slot? = nil
local function serverClock(): number
	return Workspace:GetServerTimeNow()
end
local clock: () -> number = serverClock

local function getContainer(): Instance
	local existing = container
	if existing ~= nil then
		return existing
	end
	local found = Workspace:FindFirstChild(CONTAINER_NAME)
	if found == nil or not found:IsA("Folder") then
		local folder = Instance.new("Folder")
		folder.Name = CONTAINER_NAME
		folder.Parent = Workspace
		found = folder
	end
	container = found
	return found :: Instance
end

-- Every child of Geometry except Barriers: what projectiles may hit (§5.3).
local function projectileFilter(geometry: Instance): { Instance }
	local list: { Instance } = {}
	for _, child in geometry:GetChildren() do
		if child.Name ~= BARRIERS_NAME then
			table.insert(list, child)
		end
	end
	return list
end

local function zoneOf(part: Instance?): Zone?
	if part == nil or not part:IsA("BasePart") then
		return nil
	end
	return { cframe = part.CFrame, size = part.Size }
end

-- Builds the Slot of an already pivoted clone. Returns nil and a problem when the clone lacks a required child.
local function readSlot(index: number, model: Model): (Slot?, string?)
	local origin = model.PrimaryPart or model:FindFirstChild(ORIGIN_NAME)
	if origin == nil or not origin:IsA("BasePart") then
		return nil, "no Origin part"
	end
	local geometry = model:FindFirstChild(GEOMETRY_NAME)
	if geometry == nil then
		return nil, "no Geometry"
	end
	local zonesFolder = model:FindFirstChild(ZONES_NAME)
	local zones: { [string]: Zone } = {}
	for _, name in ZONE_NAMES do
		local zone = zoneOf(if zonesFolder then zonesFolder:FindFirstChild(name) else nil)
		if zone == nil then
			return nil, `no Zones/{name}`
		end
		zones[name] = zone
	end
	local spawns = model:FindFirstChild(SPAWNS_NAME)
	local pads: { [string]: CFrame } = {}
	local padParts: { [string]: BasePart } = {}
	for side, name in PAD_NAMES do
		local pad = if spawns then spawns:FindFirstChild(name) else nil
		if pad == nil or not pad:IsA("BasePart") then
			return nil, `no Spawns/{name}`
		end
		pads[side] = ArenaService.padLookAt(pad.CFrame)
		padParts[side] = pad
	end
	local runtime = model:FindFirstChild(RUNTIME_NAME)
	if runtime == nil then
		local folder = Instance.new("Folder")
		folder.Name = RUNTIME_NAME
		folder.Parent = model
		runtime = folder
	end

	local filter = projectileFilter(geometry)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = filter
	raycastParams.CollisionGroup = DEFAULT_GROUP
	raycastParams.IgnoreWater = true
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = filter
	overlapParams.CollisionGroup = DEFAULT_GROUP

	local originCFrame = origin.CFrame
	local floorY = originCFrame.Position.Y
	local slot: Slot = {
		index = index,
		model = model,
		origin = originCFrame,
		floorY = floorY,
		killY = floorY + Config.Duel.Rules.OutOfBounds.KillYOffset,
		geometry = geometry,
		runtime = runtime :: Instance,
		raycastParams = raycastParams,
		overlapParams = overlapParams,
		zones = zones,
		pads = pads,
		padParts = padParts,
		inUse = false,
		matchId = nil,
		acquiredAt = nil,
		leaseUntil = nil,
		drainUntil = nil,
	}
	return slot, nil
end

-- Clones the template into slot `index` (pivoted before parenting). Nil when the template is missing or broken.
local function buildSlot(index: number): Slot?
	local source = template
	local position = ArenaService.slotOrigin(index)
	if source == nil or templateBroken or position == nil or not source:IsA("Model") then
		return nil
	end
	local model = source:Clone() :: Model
	model.Name = CLONE_PREFIX .. index
	-- A runtime copy, not a generated root (generated roots are what the editor tools look for, §1.7).
	model:RemoveTag(TAG_GENERATED)
	model:SetAttribute(ATTR_SLOT, index)
	model:PivotTo(CFrame.new(position))
	local slot, problem = readSlot(index, model)
	if slot == nil then
		model:Destroy()
		templateBroken = true
		log:error(`arena template is incomplete ({problem}); duels are disabled`)
		return nil
	end
	model.Parent = getContainer()
	slots[index] = slot
	return slot
end

local function clearRuntime(slot: Slot)
	for _, child in slot.runtime:GetChildren() do
		child:Destroy()
	end
end

-- Public: pure helpers (unit-tested) -----------------------------------------------------------------------------------

-- The number of slots this server may use: MaxSlots, never more than the listed grid origins.
function ArenaService.maxSlots(): number
	return math.min(Config.Duel.Arena.MaxSlots, #Config.Duel.Arena.SlotOrigins)
end

-- The world position of slot `index`'s Origin (1-based), or nil outside 1..maxSlots().
function ArenaService.slotOrigin(index: number): Vector3?
	if type(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > ArenaService.maxSlots() then
		return nil
	end
	return Config.Duel.Arena.SlotOrigins[index]
end

-- The lease a match gets on acquire: the longest possible match plus LeaseGraceSeconds.
function ArenaService.leaseSeconds(): number
	local rules = Config.Duel.Rules
	return rules.PreparingTimeoutSeconds
		+ rules.PositioningTimeoutSeconds
		+ rules.CountdownSeconds
		+ rules.MatchSeconds
		+ rules.SuddenDeathSeconds
		+ rules.ResultSeconds
		+ Config.Duel.Positioning.StreamAroundTimeoutSeconds
		+ Config.Duel.Arena.LeaseGraceSeconds
end

-- The facing CFrame of a pad: its position, looking along its LookVector, with world up (§5.3: never pad.CFrame).
function ArenaService.padLookAt(padCFrame: CFrame): CFrame
	local position = padCFrame.Position
	return CFrame.lookAt(position, position + padCFrame.LookVector)
end

-- True when `point` is inside the box (cframe, size); `margin` widens it in X and Z (local axes) only.
function ArenaService.boxContains(cframe: CFrame, size: Vector3, point: Vector3, margin: number?): boolean
	local m = margin or 0
	local p = cframe:PointToObjectSpace(point)
	return math.abs(p.X) <= size.X / 2 + m and math.abs(p.Y) <= size.Y / 2 and math.abs(p.Z) <= size.Z / 2 + m
end

-- "HalfA" for side "A", "HalfB" for side "B" (nil otherwise).
function ArenaService.halfName(side: string): string?
	return HALF_BY_SIDE[side]
end

-- Public: zones and pads -----------------------------------------------------------------------------------------------

-- True when `point` is inside the slot's zone `zoneName` ("HalfA", "Neutral", "HalfB", "Bounds"), widened by margin.
function ArenaService.inZone(slot: Slot, zoneName: string, point: Vector3, margin: number?): boolean
	local zone = slot.zones[zoneName]
	if zone == nil then
		return false
	end
	return ArenaService.boxContains(zone.cframe, zone.size, point, margin)
end

-- True when `point` is inside the slot's Bounds (playable box + 2).
function ArenaService.inBounds(slot: Slot, point: Vector3): boolean
	return ArenaService.inZone(slot, "Bounds", point)
end

-- True when `point` is inside the half of `side` ("A" / "B"), widened by margin (§5.6 #5: own half + 2 studs).
function ArenaService.inOwnHalf(slot: Slot, side: string, point: Vector3, margin: number?): boolean
	local half = HALF_BY_SIDE[side]
	return half ~= nil and ArenaService.inZone(slot, half, point, margin)
end

-- The play zone that holds `point`: "HalfA", "Neutral" or "HalfB"; "Bounds" when it is only inside the Bounds (the
-- 2-stud gutter); nil outside.
function ArenaService.zoneAt(slot: Slot, point: Vector3): string?
	for _, name in HALF_ZONES do
		if ArenaService.inZone(slot, name, point) then
			return name
		end
	end
	if ArenaService.inBounds(slot, point) then
		return "Bounds"
	end
	return nil
end

-- The pad CFrame of `side` ("A"/"B"; "PadA"/"PadB" also accepted): pad position, facing the opponent, world up.
function ArenaService.padCFrame(slot: Slot, side: string): CFrame?
	local key = if side == "PadA" then "A" elseif side == "PadB" then "B" else side
	return slot.pads[key]
end

-- Where to pivot a character on `side`'s pad: padCFrame raised by `height` (§5.4: R15 HipHeight + HRP.Size.Y/2 +
-- Config.Duel.Positioning.R15ExtraHeight; R6 Config.Duel.Positioning.R6Height).
function ArenaService.placementCFrame(slot: Slot, side: string, height: number): CFrame?
	local pad = ArenaService.padCFrame(slot, side)
	if pad == nil then
		return nil
	end
	return pad + Vector3.new(0, height, 0)
end

-- The arena part of the DuelState payload (Types.DuelArenaView): zones by name, pads by child name.
function ArenaService.view(slot: Slot): Types.DuelArenaView
	local zones: { [string]: Types.ArenaZone } = {}
	for name, zone in slot.zones do
		zones[name] = { cframe = zone.cframe, size = zone.size }
	end
	return {
		slot = slot.index,
		floorY = slot.floorY,
		zones = zones,
		pads = { PadA = slot.pads.A, PadB = slot.pads.B },
	}
end

-- The projectile RaycastParams of the slot (Include = Geometry minus Barriers, group Default).
function ArenaService.raycastParams(slot: Slot): RaycastParams
	return slot.raycastParams
end

-- The projectile OverlapParams of the slot (same Include list and group).
function ArenaService.overlapParams(slot: Slot): OverlapParams
	return slot.overlapParams
end

-- Public: pool ---------------------------------------------------------------------------------------------------------

-- Uses this template and container (init() passes WorldService.arenaTemplate() and nil = Workspace.SD_ArenaSlots;
-- tests pass an in-memory template, an unparented folder, a fake clock and a recording logger). Destroys the clones
-- made so far. The clock defaults to the server time and the logger to [SD][Arena].
function ArenaService.useTemplate(
	newTemplate: Instance?,
	newContainer: Instance?,
	newClock: (() -> number)?,
	newLog: Logger?
)
	for _, slot in slots do
		slot.model:Destroy()
	end
	slots = {}
	handoffSlot = nil
	template = newTemplate
	templateBroken = false
	container = newContainer
	clock = newClock or serverClock
	log = newLog or DEFAULT_LOG
end

-- True when duels can run: the template exists and is complete.
function ArenaService.available(): boolean
	return template ~= nil and not templateBroken
end

-- Takes a free slot (the lowest cloned free index first, else a new clone) and starts its lease. Nil when every slot
-- is in use or the template is missing. During a handoff, returns the handed-off slot instead.
function ArenaService.acquire(matchId: string?): Slot?
	local handed = handoffSlot
	if handed ~= nil then
		handoffSlot = nil
		if matchId ~= nil then
			handed.matchId = matchId
		end
		return handed
	end
	if not ArenaService.available() then
		return nil
	end
	local chosen: Slot? = nil
	for index = 1, ArenaService.maxSlots() do
		local slot = slots[index]
		if slot ~= nil and not slot.inUse then
			chosen = slot
			break
		end
	end
	if chosen == nil then
		for index = 1, ArenaService.maxSlots() do
			if slots[index] == nil then
				chosen = buildSlot(index)
				break
			end
		end
	end
	if chosen == nil then
		return nil
	end
	local now = clock()
	chosen.inUse = true
	chosen.matchId = matchId
	chosen.acquiredAt = now
	chosen.leaseUntil = now + ArenaService.leaseSeconds()
	chosen.drainUntil = nil
	return chosen
end

-- While set, the next acquire() returns this slot (QueueService -> DuelService.startMatch). nil clears it.
function ArenaService.handoff(slot: Slot?)
	handoffSlot = slot
end

-- Clears the slot's Runtime, resets its state and fires SlotReleased. Idempotent (a free slot is left alone).
function ArenaService.release(slot: Slot?)
	if slot == nil or not slot.inUse then
		return
	end
	if handoffSlot == slot then
		handoffSlot = nil
	end
	clearRuntime(slot)
	slot.inUse = false
	slot.matchId = nil
	slot.acquiredAt = nil
	slot.leaseUntil = nil
	slot.drainUntil = nil
	ArenaService.SlotReleased:fire(slot)
end

-- Records which match holds the slot (logs and LeaseExpired use it).
function ArenaService.setMatch(slot: Slot, matchId: string?)
	slot.matchId = matchId
end

-- Extends an in-use slot's lease to now + seconds (default leaseSeconds()).
function ArenaService.renewLease(slot: Slot, seconds: number?)
	if slot.inUse then
		slot.leaseUntil = clock() + (seconds or ArenaService.leaseSeconds())
	end
end

-- Free slots: maxSlots() minus the slots in use (0 without a template).
function ArenaService.freeCount(): number
	if not ArenaService.available() then
		return 0
	end
	return ArenaService.maxSlots() - ArenaService.inUseCount()
end

-- Slots in use (duels in progress, including Result and Returning).
function ArenaService.inUseCount(): number
	local count = 0
	for _, slot in slots do
		if slot.inUse then
			count += 1
		end
	end
	return count
end

-- Clones made so far.
function ArenaService.clonedCount(): number
	local count = 0
	for _ in slots do
		count += 1
	end
	return count
end

-- The slot with this index, if it was cloned.
function ArenaService.getSlot(index: number): Slot?
	return slots[index]
end

-- The in-use slot that holds `matchId`, if any.
function ArenaService.slotOfMatch(matchId: string): Slot?
	for _, slot in slots do
		if slot.inUse and slot.matchId == matchId then
			return slot
		end
	end
	return nil
end

-- One janitor pass at `now` (default the clock), run every JanitorIntervalSeconds. An in-use slot whose lease ended
-- before `now` is logged and LeaseExpired fires once for it (its owner voids the match, returns the players and then
-- releases the slot); a slot with no matchId is released at once. A slot still held LeaseDrainSeconds after that is
-- released here (logged). Returns the slots whose lease newly expired in this pass.
function ArenaService.janitorStep(now: number?): { Slot }
	local t = if now ~= nil then now else clock()
	local expired: { Slot } = {}
	local stuck: { Slot } = {}
	for index = 1, ArenaService.maxSlots() do
		local slot = slots[index]
		if slot ~= nil and slot.inUse and slot.leaseUntil ~= nil and t > slot.leaseUntil then
			local drainUntil = slot.drainUntil
			if drainUntil == nil then
				table.insert(expired, slot)
			elseif t > drainUntil then
				table.insert(stuck, slot)
			end
		end
	end
	for _, slot in expired do
		log:error(`slot {slot.index} lease expired (match {tostring(slot.matchId)}); voiding it`)
		slot.drainUntil = t + Config.Duel.Arena.LeaseDrainSeconds
		local owner = slot.matchId
		ArenaService.LeaseExpired:fire(slot, owner)
		if owner == nil then
			ArenaService.release(slot)
		end
	end
	for _, slot in stuck do
		log:error(`slot {slot.index} still held after its lease expired (match {tostring(slot.matchId)}); releasing`)
		ArenaService.release(slot)
	end
	return expired
end

-- Clones slots up to `count` (default PrewarmSlots) without taking them.
function ArenaService.prewarm(count: number?)
	local target = math.min(count or Config.Duel.Arena.PrewarmSlots, ArenaService.maxSlots())
	for index = 1, target do
		if slots[index] == nil and buildSlot(index) == nil then
			return
		end
	end
end

-- Studio debug view: one line per cloned slot.
function ArenaService.debugState(): { [string]: any }
	local list = {}
	for index = 1, ArenaService.maxSlots() do
		local slot = slots[index]
		if slot ~= nil then
			table.insert(list, {
				index = index,
				inUse = slot.inUse,
				matchId = slot.matchId,
				leaseLeft = if slot.leaseUntil then slot.leaseUntil - clock() else nil,
				runtimeChildren = #slot.runtime:GetChildren(),
			})
		end
	end
	return {
		available = ArenaService.available(),
		maxSlots = ArenaService.maxSlots(),
		inUse = ArenaService.inUseCount(),
		free = ArenaService.freeCount(),
		slots = list,
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function ArenaService.init()
	ArenaService.useTemplate(WorldService.arenaTemplate(), nil)
	if template == nil then
		log:warn("no arena template; duels are disabled (queue.unavailable)")
	end
end

function ArenaService.start()
	ArenaService.prewarm()
	local interval = Config.Duel.Arena.JanitorIntervalSeconds
	while true do
		task.wait(interval)
		local ok, err = pcall(ArenaService.janitorStep)
		if not ok then
			log:error("janitor failed:", err)
		end
	end
end

return ArenaService
