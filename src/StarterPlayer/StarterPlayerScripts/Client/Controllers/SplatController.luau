--!strict
-- SplatController (client only). DESIGN §18.4.1 (splats), §18.3.1 (what the client knows), §9.1 #5, §18.9.
-- A pastel splat in the thrower's squishy colour where a throw hits a wall, cover or the floor. Cosmetic only: FxPool
-- parts (SmoothPlastic, no shadow, CanCollide/CanQuery/CanTouch false, SD_Cosmetic, under Workspace.SD_ClientFx),
-- started only by the server's ThrowImpact; it decides nothing and never touches a real part.
--
-- * Trigger: ThrowImpact kind "geometry" with a normal (duels and practice), at the server's position and normal. Not
--   "expired" / "fizzle" (no surface), not "player" / "target" (no splats on bodies or targets), not Dragon Rush lanes
--   (they end without a normal). ThrowImpact carries no radius or squishy, so both come from the ThrowStarted kept per
--   projId (dropped at the impact or ProjectileMaxLifetime + 5 s after the release); an unknown projId uses r = 1.0
--   and White. A practice lane-floor hit carries the projectile centre, so it is dropped to PracticeTargets.FLOOR_Y
--   (SplatMath.surfacePoint).
-- * Colour SplatMath.color(accent): whitened by 0.25, a red hue whitened by 0.6 (never red, never Danger).
-- * Visible-surface probe (a safety net; the server already leaves out the invisible barriers): a ray from
--   position + n · 0.5 along -n · probeStuds with ProjectileRenderer's contact exclusions. No hit, or a hit part with
--   Transparency >= minVisibleTransparency, gives no splat. Cover hidden by the jelly ripple (LocalTransparencyModifier)
--   keeps its real Transparency, so it still gets splats. A Ball or Cylinder Part (a gumdrop) gets the main blob only,
--   d <= curvedMaxDiameter, with no droplets or drip.
-- * Parts: a main blob (Block + Sphere SpecialMesh, Size (d, thickness, oval · d), d = diameterPerRadius × the throw
--   radius, a random roll about n) and `droplets` droplets (SplatMath.droplets), lifted lift + (serial % layers) ·
--   layerStep off the surface so newer splats sit on top and nothing flickers.
-- * Timeline (one Scheduler effect for every splat, SplatMath.sample): the blob grows 0 -> 1.12 -> 1, droplets pop in
--   from 40 ms, hold until 1.6 s, then fade to 1 (and scale to 0.9) by 2.5 s; on a wall (|n.Y| < 0.35) the lowest
--   droplet slides dripStuds down the wall between 0.3 s and 1.6 s and stretches to 1.4. ReducedMotion: full size at
--   once, no droplet pop or drip; the slow fade stays.
-- * Riding the ripple: each frame every part adds JellyRippleController.offsetAt(its surface point, n) to its lift
--   (0 when that surface is still), so a splat rides the jelly wave instead of floating or clipping. Reading: the
--   ripple module is required at init() through its ModuleScript (booted just before this one, §18.4), and a missing
--   module, a failing require or a failing offsetAt (one log line) only leaves the splats flat: the bootstrap's
--   require of this module must never fail because of a cosmetic neighbour.
-- * Caps: at most min(Splat.maxLive, Budgets.splats) live splats; a new one sends the oldest to an evictFadeSeconds
--   fade (other players' practice splats first). Only within cullStuds of the camera; other players' practice splats
--   only within othersCullStuds. Reading: a new low-priority splat (another player's practice throw) never evicts a
--   higher one; it is dropped instead. An evicting splat no longer counts as live.
-- * No sound of its own (sfx.impactSoft is VfxController's).
-- Studio: the "splat" juice piece (VfxController.debugJuice) splats where the camera looks.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local PracticeTargets = require(Shared.Practice.PracticeTargets)
local Signal = require(Shared.Util.Signal)

local Client = script.Parent.Parent
local FxPool = require(Client.Anim.FxPool)
local Scheduler = require(Client.Anim.Scheduler)
local SplatMath = require(Client.Anim.SplatMath)
local Tweens = require(Client.Anim.Tweens)
local NetController = require(script.Parent.NetController)
local ProjectileRenderer = require(script.Parent.ProjectileRenderer)
local ThrowController = require(script.Parent.ThrowController)
local VfxController = require(script.Parent.VfxController)

-- Types

-- What a ThrowStarted leaves for its impact.
type Throw = {
	radius: number,
	squishyId: string,
	throwerId: number,
	practice: boolean,
	untilAt: number, -- server time
}

type Drop = {
	part: BasePart,
	size: number, -- studs at full scale
	offset: Vector3, -- from the splat centre, in the surface plane
	drip: boolean,
}

type Splat = {
	serial: number,
	bornAt: number, -- os.clock()
	low: boolean, -- another player's practice splat: dropped first
	point: Vector3, -- on the surface
	normal: Vector3,
	right: Vector3, -- the blob's X axis (rolled about n)
	back: Vector3, -- the blob's Z axis
	down: Vector3?, -- down the wall, in the surface plane (wall splats)
	spec: SplatMath.Spec,
	color: Color3,
	main: BasePart,
	drops: { Drop },
	evictedAt: number?, -- os.clock() the eviction fade began
	evictFrom: number, -- Transparency when it began
	transparency: number, -- last written
}

-- Where a splat goes, from the server's numbers (prepare): nil = no splat.
export type Placement = {
	point: Vector3,
	normal: Vector3,
	radius: number,
	accent: Color3,
	low: boolean,
}

-- The one part of JellyRippleController (§18.3.4, lane L2) a splat uses.
type Ripple = { offsetAt: (worldPoint: Vector3, normal: Vector3) -> number }

-- Constants

local SPLAT = Config.Vfx.Splat
local RIPPLE_MODULE = "JellyRippleController"
local MAX_LIVE = math.min(SPLAT.maxLive, Config.Vfx.Budgets.splats)
local PROJECTILE_KEEP_SECONDS = Config.Duel.Rules.ProjectileMaxLifetime + 5
-- reading: the probe starts this far out along the normal (§18.4.1 "position + n · 0.5").
local PROBE_BACK_OFF = 0.5
-- reading: parts never get smaller than this (a part needs a size); a scale below it hides the part.
local MIN_STUDS = 0.01
-- reading: the Studio "splat" juice looks this far along the camera.
local DEBUG_REACH = 80

-- Module table

local SplatController = {}

-- Private

local log = Log.new("Splat")
local cleanup: Cleanup.Cleanup? = nil
local throws: { [number]: Throw } = {}
local splats: { Splat } = {}
local serial = 0
local connections: { Signal.Connection } = {}
local stats = { made = 0, dropped = 0, evicted = 0, culled = 0, probeMissed = 0 }
local ripple: Ripple? = nil -- set by init() when the ripple module is there
-- `require` with a ModuleScript found at runtime (the ripple is another lane's module).
local dynamicRequire = require :: (ModuleScript) -> any

local function reduced(): boolean
	return Tweens.reducedMotion()
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function track(connection: Signal.Connection)
	table.insert(connections, connection)
	local c = cleanup
	if c then
		c:add(connection)
	end
end

local function accentOf(squishyId: string?): Color3
	local def = if squishyId and squishyId ~= "" then Catalog.get(squishyId) else nil
	return if def then Color3.fromHex(def.visuals.accent) else Palette.White
end

local function cameraPosition(): Vector3?
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

-- A unit vector in the surface plane, perpendicular to n (any one).
local function planeAxis(n: Vector3): Vector3
	return if math.abs(n:Dot(Vector3.xAxis)) < 0.95 then n:Cross(Vector3.xAxis).Unit else n:Cross(Vector3.zAxis).Unit
end

local function releaseSplat(splat: Splat)
	local pool = FxPool.default()
	pool:release(splat.main)
	for _, drop in splat.drops do
		pool:release(drop.part)
	end
	table.clear(splat.drops)
end

local function newPart(name: string, color: Color3): BasePart
	local part = FxPool.default():acquirePart({
		Name = name,
		Color = color,
		Transparency = 1, -- shown by the first step
		Size = Vector3.new(MIN_STUDS, SPLAT.thickness, MIN_STUDS),
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- The jelly ripple module, when it is there and loads (nil otherwise: splats stay flat).
local function findRipple(): Ripple?
	local module = script.Parent:FindFirstChild(RIPPLE_MODULE)
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(dynamicRequire, module)
	if not ok or type(result) ~= "table" or type(result.offsetAt) ~= "function" then
		log:warn("the jelly ripple is not available; splats stay flat:", if ok then "no offsetAt" else result)
		return nil
	end
	return result :: Ripple
end

-- The surface offset of the jelly ripple at a point (0 when nothing moves there, or with no ripple).
local function rideAt(point: Vector3, normal: Vector3): number
	local current = ripple
	if current == nil then
		return 0
	end
	local ok, offset = pcall(current.offsetAt, point, normal)
	if not ok then
		ripple = nil
		log:warn("JellyRippleController.offsetAt failed; splats stay flat from now on:", offset)
		return 0
	end
	return if type(offset) == "number" and offset == offset then offset else 0
end

-- Writes one frame of a splat. Returns false once it is gone.
local function stepSplat(splat: Splat, clock: number, isReduced: boolean): boolean
	local t = clock - splat.bornAt
	local sample = SplatMath.sample(t, splat.spec.drip, isReduced)
	local transparency = sample.transparency
	local evictedAt = splat.evictedAt
	if evictedAt ~= nil then
		local faded, gone = SplatMath.evicted(splat.evictFrom, clock - evictedAt)
		if gone then
			return false
		end
		transparency = math.max(transparency, faded)
	elseif sample.done then
		return false
	end
	splat.transparency = transparency
	local n = splat.normal
	local lift = SplatMath.lift(splat.serial)
	local d = splat.spec.d
	-- Main blob.
	local main = splat.main
	local m = d * sample.main
	main.Size = Vector3.new(math.max(m, MIN_STUDS), SPLAT.thickness, math.max(m * SPLAT.oval, MIN_STUDS))
	local centre = splat.point
	main.CFrame = CFrame.fromMatrix(centre + n * (lift + rideAt(centre, n)), splat.right, n, splat.back)
	main.Transparency = if m > MIN_STUDS then transparency else 1
	-- Droplets.
	for _, drop in splat.drops do
		local s = drop.size * sample.droplet
		local part = drop.part
		if s <= MIN_STUDS then
			part.Transparency = 1
			continue
		end
		local at = centre + drop.offset
		local down = splat.down
		if drop.drip and down then
			at += down * (SPLAT.dripStuds * sample.drip)
			local across = n:Cross(down)
			part.Size = Vector3.new(s, SPLAT.thickness, s * sample.dripStretch)
			part.CFrame = CFrame.fromMatrix(at + n * (lift + rideAt(at, n)), across, n, down)
		else
			part.Size = Vector3.new(s, SPLAT.thickness, s)
			part.CFrame = CFrame.fromMatrix(at + n * (lift + rideAt(at, n)), splat.right, n, splat.back)
		end
		part.Transparency = transparency
	end
	return true
end

local function step(_dt: number, clock: number): boolean
	local isReduced = reduced()
	local kept = 0
	for index = 1, #splats do
		local splat = splats[index]
		local ok, alive = pcall(stepSplat, splat, clock, isReduced)
		if not ok then
			log:error("a splat failed and was removed:", alive)
		end
		if ok and alive then
			kept += 1
			splats[kept] = splat
		else
			releaseSplat(splat)
		end
	end
	for index = #splats, kept + 1, -1 do
		splats[index] = nil
	end
	local now = serverNow()
	for projId, throw in throws do
		if now > throw.untilAt then
			throws[projId] = nil
		end
	end
	return true
end

-- The live splats that still count (not evicting), for the cap.
local function liveSplats(): ({ SplatMath.Evictable }, { Splat })
	local evictable: { SplatMath.Evictable } = {}
	local list: { Splat } = {}
	for _, splat in splats do
		if splat.evictedAt == nil then
			table.insert(evictable, { bornAt = splat.bornAt, low = splat.low })
			table.insert(list, splat)
		end
	end
	return evictable, list
end

-- Makes room for a new splat. False when the new one is the one to drop (a low one and every live one is higher).
local function makeRoom(low: boolean, clock: number): boolean
	local evictable, list = liveSplats()
	if #list < MAX_LIVE then
		return true
	end
	local index = SplatMath.pickEvict(evictable)
	if index == nil then
		return true
	end
	local victim = list[index]
	if low and not victim.low then
		return false
	end
	victim.evictedAt = clock
	victim.evictFrom = victim.transparency
	stats.evicted += 1
	return true
end

-- Public ------------------------------------------------------------------------------------------------------------

-- Where a splat for this impact goes (nil = none): the trigger rules, the practice floor fix and the camera culls.
-- Pure apart from what it is given (unit-testable): `throw` is the kept ThrowStarted (nil = unknown: r 1.0, White),
-- `cameraAt` the camera position (nil = no cull).
function SplatController.prepare(
	kind: string,
	position: Vector3,
	normal: Vector3?,
	throw: { radius: number, squishyId: string, practice: boolean, own: boolean }?,
	cameraAt: Vector3?
): Placement?
	if kind ~= "geometry" or normal == nil or normal.Magnitude < 1e-6 then
		return nil
	end
	local n = normal.Unit
	local radius = if throw and throw.radius > 0 then throw.radius else 1
	local practice = throw ~= nil and throw.practice
	local low = practice and not (throw ~= nil and throw.own)
	local point = SplatMath.surfacePoint(position, n, radius, practice, PracticeTargets.FLOOR_Y)
	if cameraAt ~= nil then
		local reach = if low then SPLAT.othersCullStuds else SPLAT.cullStuds
		if (point - cameraAt).Magnitude > reach then
			return nil
		end
	end
	return {
		point = point,
		normal = n,
		radius = radius,
		accent = accentOf(if throw then throw.squishyId else nil),
		low = low,
	}
end

-- Lays a splat at `placement` after the visible-surface probe. Returns whether one was made.
function SplatController.place(placement: Placement): boolean
	local n = placement.normal
	local point = placement.point
	local hit = Workspace:Raycast(point + n * PROBE_BACK_OFF, -n * SPLAT.probeStuds, ProjectileRenderer.contactParams())
	if hit == nil or hit.Instance.Transparency >= SPLAT.minVisibleTransparency then
		stats.probeMissed += 1
		return false
	end
	local surface = hit.Instance
	local curved = surface:IsA("Part")
		and (surface.Shape == Enum.PartType.Ball or surface.Shape == Enum.PartType.Cylinder)
	local clock = os.clock()
	if not makeRoom(placement.low, clock) then
		stats.dropped += 1
		return false
	end
	local spec = SplatMath.spec(placement.radius, curved, n)
	local rng = Random.new()
	local roll = rng:NextNumber(0, 2 * math.pi)
	local axis = planeAxis(n)
	local other = axis:Cross(n).Unit
	local right = axis * math.cos(roll) + other * math.sin(roll)
	local back = right:Cross(n).Unit
	local color = SplatMath.color(placement.accent)
	serial += 1
	local splat: Splat = {
		serial = serial,
		bornAt = clock,
		low = placement.low,
		point = point,
		normal = n,
		right = right,
		back = back,
		down = nil,
		spec = spec,
		color = color,
		main = newPart("Splat", color),
		drops = {},
		evictedAt = nil,
		evictFrom = SPLAT.transparency,
		transparency = 1,
	}
	if spec.droplets then
		local lowest: Drop? = nil
		local lowestY = math.huge
		for _, droplet in SplatMath.droplets(rng, spec.d) do
			local offset = (right * math.cos(droplet.angle) + back * math.sin(droplet.angle)) * droplet.dist
			local drop: Drop =
				{ part = newPart("SplatDrop", color), size = droplet.size, offset = offset, drip = false }
			table.insert(splat.drops, drop)
			if offset.Y < lowestY then
				lowestY = offset.Y
				lowest = drop
			end
		end
		if spec.drip and lowest then
			local fall = Vector3.new(0, -1, 0)
			local down = fall - n * fall:Dot(n)
			if down.Magnitude > 1e-3 then
				splat.down = down.Unit
				lowest.drip = true
			end
		end
	end
	table.insert(splats, splat)
	stats.made += 1
	return true
end

-- Studio: the "splat" juice piece (VfxController.debugJuice "splat"): a splat at opts.position facing opts.normal
-- (DebugHooks passes the surface under the screen centre), else where the camera looks, as a throw of opts.radius
-- (default 1) with opts.squishyId's colour (default the local held one's, else White).
function SplatController.debugSplat(opts: { [string]: any }?): (boolean, string?)
	local options: { [string]: any } = opts or {}
	local point: Vector3
	local normal: Vector3
	if typeof(options.position) == "Vector3" and typeof(options.normal) == "Vector3" then
		point, normal = options.position, options.normal
	else
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return false, "no camera"
		end
		local look = camera.CFrame.LookVector
		local hit = Workspace:Raycast(camera.CFrame.Position, look * DEBUG_REACH, ProjectileRenderer.contactParams())
		if hit == nil then
			return false, "nothing in front of the camera"
		end
		point, normal = hit.Position, hit.Normal
	end
	if normal.Magnitude < 1e-6 then
		return false, "no surface normal"
	end
	local localPlayer = Players.LocalPlayer
	local squishyId = if type(options.squishyId) == "string"
		then options.squishyId
		elseif localPlayer then localPlayer:GetAttribute("SD_Equipped")
		else nil
	local placement: Placement = {
		point = point,
		normal = normal.Unit,
		radius = if type(options.radius) == "number" then options.radius else 1,
		accent = accentOf(if type(squishyId) == "string" then squishyId else nil),
		low = false,
	}
	if not SplatController.place(placement) then
		return false, "the probe found no visible surface, or the cap dropped it"
	end
	return true, nil
end

-- Studio / debug counters (juice check 12 reads them).
function SplatController.counts(): { [string]: any }
	local live, fading, parts = 0, 0, 0
	for _, splat in splats do
		if splat.evictedAt == nil then
			live += 1
		else
			fading += 1
		end
		parts += 1 + #splat.drops
	end
	local kept = 0
	for _ in throws do
		kept += 1
	end
	local connected = 0
	for _, connection in connections do
		if connection.connected then
			connected += 1
		end
	end
	return {
		live = live,
		fading = fading,
		parts = parts,
		throwsKept = kept,
		made = stats.made,
		dropped = stats.dropped,
		evicted = stats.evicted,
		culled = stats.culled,
		probeMissed = stats.probeMissed,
		connections = connected,
	}
end

-- Removes every splat at once and forgets the kept throws (leak checks).
function SplatController.clear()
	for _, splat in splats do
		releaseSplat(splat)
	end
	table.clear(splats)
	table.clear(throws)
end

-- Remote events -----------------------------------------------------------------------------------------------------

local function onThrowStarted(raw: unknown)
	local payload = ThrowController.parseThrowStarted(raw)
	if payload == nil then
		return
	end
	throws[payload.projId] = {
		radius = payload.radius,
		squishyId = payload.squishyId,
		throwerId = payload.throwerId,
		practice = payload.kind == "practice",
		untilAt = payload.releaseAt + PROJECTILE_KEEP_SECONDS,
	}
end

local function onThrowImpact(raw: unknown)
	local impact = ThrowController.parseImpact(raw)
	if impact == nil then
		return
	end
	local kept = throws[impact.projId]
	throws[impact.projId] = nil
	local localPlayer = Players.LocalPlayer
	local throw = if kept
		then {
			radius = kept.radius,
			squishyId = kept.squishyId,
			practice = kept.practice,
			own = localPlayer ~= nil and kept.throwerId == localPlayer.UserId,
		}
		else nil
	local placement = SplatController.prepare(impact.kind, impact.position, impact.normal, throw, cameraPosition())
	if placement == nil then
		if impact.kind == "geometry" and impact.normal ~= nil then
			stats.culled += 1
		end
		return
	end
	SplatController.place(placement)
end

-- Lifecycle

function SplatController.init()
	local c = Cleanup.new()
	cleanup = c
	ripple = findRipple()
	c:add(Scheduler.add(step, "render"))
	track(NetController.on("ThrowStarted", onThrowStarted))
	track(NetController.on("ThrowImpact", onThrowImpact))
	VfxController.setJuiceHook("splat", SplatController.debugSplat)
	c:add(function()
		VfxController.setJuiceHook("splat", nil)
		SplatController.clear()
		table.clear(connections)
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function SplatController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return SplatController
