--!strict
-- ArenaService (server only). DESIGN §2.3, §5.3, §5.4, §7.8.
-- The arena slot pool: up to Config.Duel.Arena.MaxSlots (6) clones of the arena templates: since 2026-10-30 Diego's 1v1
-- sky maps in ServerStorage.SquishyMaps (skyMapTemplates(), by MapId; the old SD_Templates arenas left), placed in
-- Workspace.SD_ArenaSlots (created at runtime) on the grid Config.Duel.Arena.SlotOrigins (a sky row, Y 300, far
-- from the lobby). Clones are made lazily (PrewarmSlots at start), pivoted to their slot BEFORE they are parented, and
-- kept for the server's lifetime; release() clears the slot's Runtime folder and resets its state so the next match
-- reuses it. The templates are never changed. Without a usable template, duels are disabled: available() is false,
-- freeCount() is 0, acquire() returns nil (QueueJoin answers queue.unavailable).
-- Random arena (phase 4 spec 2026-10-11 §5.3, D7): acquire() rolls the match's arena with pickArena(), an equal chance
-- over the usable templates (a server Random, never the client; repeats allowed), then takes a free clone of it, else
-- clones it into the lowest never-cloned slot, else re-clones the lowest free slot that holds another arena (the old
-- model is destroyed; at most one clone per match start). A template whose clone lacks a required child leaves the
-- rotation (logged once); the others keep the duels going. Every arena shares Candy Court's gameplay frame, so zones,
-- pads, killY and the projectile filter read the same from any clone. view(slot).arenaId names the arena (DuelState).
--
-- A Slot (plain table, read-only for callers except through the functions below):
--   index, arenaId (World/Arenas id of the clone), model, origin (the Origin part's CFrame), floorY (floor top =
--   Origin.Y, §5.3), killY (floorY +
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
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Arenas = require(Shared.World.Arenas)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

-- Types

export type Zone = Types.ArenaZone

export type Slot = {
	index: number,
	arenaId: string, -- World/Arenas id of the template this slot was cloned from
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
local SKY_MAPS_NAME = "SquishyMaps" -- ServerStorage: Diego's sky maps (the 1v1 ones are the arena templates)
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

-- What this module logs through (useTemplates may swap it, so tests can check the log without console noise).
export type Logger = {
	warn: (self: any, ...any) -> (),
	error: (self: any, ...any) -> (),
}

local DEFAULT_LOG: Logger = Log.new("Arena") :: any
local log: Logger = DEFAULT_LOG
local templates: { [string]: Instance } = {} -- arena id -> template
local broken: { [string]: boolean } = {} -- arena ids whose clone lacked a required child
local rng: Random = Random.new() -- the arena roll (server only)
local forcedArena: string? = nil -- Studio (debugForceArena): every pick returns it while it is usable
local preferredArena: string? = nil -- one match per server (prefer): the next pick only
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
local function readSlot(index: number, model: Model, arenaId: string): (Slot?, string?)
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
		arenaId = arenaId,
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

-- The arena ids that can still be cloned, sorted.
local function usableIds(): { string }
	local ids: { string } = {}
	for id in templates do
		if not broken[id] then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- Clones arena `arenaId` into slot `index` (pivoted before parenting). A free clone already in that slot (another
-- arena) is destroyed once the new one is complete. Nil when the template is missing, not a Model or incomplete (it
-- then leaves the rotation, logged once).
local function cloneInto(index: number, arenaId: string): Slot?
	local source: Instance? = templates[arenaId]
	local position = ArenaService.slotOrigin(index)
	if source == nil or broken[arenaId] or position == nil then
		return nil
	end
	local slot: Slot?, problem: string? = nil, `a {source.ClassName}, not a Model`
	if source:IsA("Model") then
		local model = source:Clone() :: Model
		model.Name = CLONE_PREFIX .. index
		-- A runtime copy, not a generated root (generated roots are what the editor tools look for, §1.7).
		model:RemoveTag(TAG_GENERATED)
		model:SetAttribute(ATTR_SLOT, index)
		model:PivotTo(CFrame.new(position))
		slot, problem = readSlot(index, model, arenaId)
		if slot == nil then
			model:Destroy()
		end
	end
	if slot == nil then
		broken[arenaId] = true
		local consequence = if #usableIds() == 0 then "duels are disabled" else "it leaves the rotation"
		log:error(`arena template {arenaId} is incomplete ({problem}); {consequence}`)
		return nil
	end
	local old = slots[index]
	if old ~= nil then
		old.model:Destroy()
	end
	slot.model.Parent = getContainer()
	slots[index] = slot
	return slot
end

-- The slot for arena `arenaId`: a free clone of it, else a new clone in the lowest never-cloned slot, else the lowest
-- free slot re-cloned with it. Returns (nil, true) when every slot is in use and (nil, false) when the clone failed.
local function slotFor(arenaId: string): (Slot?, boolean)
	local freeOther: Slot? = nil
	for index = 1, ArenaService.maxSlots() do
		local slot = slots[index]
		if slot ~= nil and not slot.inUse then
			if slot.arenaId == arenaId then
				return slot, false
			end
			freeOther = freeOther or slot
		end
	end
	for index = 1, ArenaService.maxSlots() do
		if slots[index] == nil then
			return cloneInto(index, arenaId), false
		end
	end
	if freeOther ~= nil then
		return cloneInto(freeOther.index, arenaId), false
	end
	return nil, true
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
		arenaId = slot.arenaId,
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

-- Uses these templates (arena id -> template) and container (init() passes skyMapTemplates() and nil =
-- Workspace.SD_ArenaSlots; tests pass in-memory templates, an unparented folder, a fake clock, a recording logger and a
-- scripted Random). Destroys the clones made so far and clears the Studio pin. The clock defaults to the server time,
-- the logger to [SD][Arena], the Random to a new one.
function ArenaService.useTemplates(
	newTemplates: { [string]: Instance },
	newContainer: Instance?,
	newClock: (() -> number)?,
	newLog: Logger?,
	newRng: Random?
)
	for _, slot in slots do
		slot.model:Destroy()
	end
	slots = {}
	handoffSlot = nil
	templates = table.clone(newTemplates)
	broken = {}
	forcedArena = nil
	container = newContainer
	clock = newClock or serverClock
	log = newLog or DEFAULT_LOG
	rng = newRng or Random.new()
end

-- Candy Court alone (Arenas.DEFAULT_ID): useTemplates({ candy_court = template }, ...); nil = no template.
function ArenaService.useTemplate(
	newTemplate: Instance?,
	newContainer: Instance?,
	newClock: (() -> number)?,
	newLog: Logger?
)
	ArenaService.useTemplates(
		if newTemplate then { [Arenas.DEFAULT_ID] = newTemplate } else {},
		newContainer,
		newClock,
		newLog
	)
end

-- True when duels can run: at least one template exists and is complete.
function ArenaService.available(): boolean
	return #usableIds() > 0
end

-- The next match's arena: the Studio pin (debugForceArena) while it is usable, else an equal-chance roll over the
-- usable arena ids (D7; one usable arena needs no roll). Nil when none is usable.
function ArenaService.pickArena(): string?
	local usable = usableIds()
	local forced = forcedArena
	if forced ~= nil and table.find(usable, forced) then
		return forced
	end
	local wanted = preferredArena
	preferredArena = nil
	if wanted ~= nil and table.find(usable, wanted) then
		return wanted -- a match server's ticket (prefer)
	end
	if #usable <= 1 then
		return usable[1]
	end
	return usable[rng:NextInteger(1, #usable)]
end

-- One match per server (2026-10-30, MatchServerService): the next pickArena returns `arenaId` (a match server's
-- ticket) when it is usable, once.
function ArenaService.prefer(arenaId: string?)
	preferredArena = arenaId
end

-- Takes a slot holding a freshly picked arena (pickArena, then a free clone of it, else a new clone, else a free slot
-- re-cloned) and starts its lease. Nil when every slot is in use or no template is usable. During a handoff, returns
-- the handed-off slot instead.
function ArenaService.acquire(matchId: string?): Slot?
	local handed = handoffSlot
	if handed ~= nil then
		handoffSlot = nil
		if matchId ~= nil then
			handed.matchId = matchId
		end
		return handed
	end
	if not ArenaService.available() or ArenaService.inUseCount() >= ArenaService.maxSlots() then
		return nil
	end
	local chosen: Slot? = nil
	while chosen == nil do
		local arenaId = ArenaService.pickArena()
		if arenaId == nil then
			return nil -- every template broke
		end
		local slot, busy = slotFor(arenaId)
		if busy or (slot == nil and not broken[arenaId]) then
			return nil
		end
		chosen = slot -- nil: that arena just left the rotation; roll again
	end
	local now = clock()
	local slot = chosen :: Slot
	slot.inUse = true
	slot.matchId = matchId
	slot.acquiredAt = now
	slot.leaseUntil = now + ArenaService.leaseSeconds()
	slot.drainUntil = nil
	return slot
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

-- Clones slots up to `count` (default PrewarmSlots) without taking them, each with a picked arena.
function ArenaService.prewarm(count: number?)
	local target = math.min(count or Config.Duel.Arena.PrewarmSlots, ArenaService.maxSlots())
	for index = 1, target do
		while slots[index] == nil do
			local arenaId = ArenaService.pickArena()
			if arenaId == nil or (cloneInto(index, arenaId) == nil and not broken[arenaId]) then
				return
			end -- a failed clone left the rotation: pick again
		end
	end
end

-- Studio only (DebugHooks "forceArena"): every pick returns `arenaId` while it is usable; nil restores the roll.
-- Returns false and a reason for an id with no template.
function ArenaService.debugForceArena(arenaId: string?): (boolean, string?)
	if arenaId ~= nil then
		local template: Instance? = templates[arenaId]
		if template == nil then
			return false, `no arena template {arenaId}`
		end
	end
	forcedArena = arenaId
	return true, nil
end

-- Studio debug view: one line per cloned slot.
function ArenaService.debugState(): { [string]: any }
	local list = {}
	for index = 1, ArenaService.maxSlots() do
		local slot = slots[index]
		if slot ~= nil then
			table.insert(list, {
				index = index,
				arenaId = slot.arenaId,
				inUse = slot.inUse,
				matchId = slot.matchId,
				leaseLeft = if slot.leaseUntil then slot.leaseUntil - clock() else nil,
				runtimeChildren = #slot.runtime:GetChildren(),
			})
		end
	end
	local brokenIds: { string } = {}
	for id in broken do
		table.insert(brokenIds, id)
	end
	table.sort(brokenIds)
	return {
		available = ArenaService.available(),
		maxSlots = ArenaService.maxSlots(),
		inUse = ArenaService.inUseCount(),
		free = ArenaService.freeCount(),
		arenas = usableIds(),
		broken = brokenIds,
		forced = forcedArena,
		slots = list,
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

-- Diego's 1v1 sky maps (NEW MAPS FINALS, 2026-10-30; SDTools "sky_maps"): the Models of `folder` whose Mode is DUEL,
-- by their MapId ("D1"...). They replace the old arenas (WorldService.arenaTemplates) in the rotation.
function ArenaService.skyMapTemplates(folder: Instance?): { [string]: Instance }
	local list: { [string]: Instance } = {}
	for _, child in if folder then folder:GetChildren() else {} do
		local id = child:GetAttribute("MapId")
		if child:IsA("Model") and child:GetAttribute("Mode") == "DUEL" and type(id) == "string" then
			list[id] = child
		end
	end
	return list
end

function ArenaService.init()
	ArenaService.useTemplates(ArenaService.skyMapTemplates(ServerStorage:FindFirstChild(SKY_MAPS_NAME)), nil)
	if not ArenaService.available() then
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
