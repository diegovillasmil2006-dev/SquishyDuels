--!strict
-- FxShapes (client only). Pooled cosmetic shapes shared by the duel VFX, the jelly ripple and the lobby (DESIGN
-- §18.4, §18.3.6, §18.5.1 A3): no duel controller is required, so lobby code can use it.
--
--   FxShapes.ring(position, normal, diameter, seconds, color, transparencyFrom?)
--
-- ring: a flat ellipsoid (an FxPool part with a Sphere SpecialMesh, RING_THICKNESS thick) lying on the surface with
-- its thin axis along `normal`, lifted SURFACE_LIFT off it, growing 0 -> diameter (Quad Out) while its Transparency
-- goes transparencyFrom (default Config.Vfx.Hit.ringTransparencyFrom) -> 1 over `seconds`; one Scheduler render
-- effect per ring. The part goes back to the pool when it ends, on stop(), or on clear(). Cosmetic only (FxPool:
-- CanCollide/CanQuery/CanTouch false, SD_Cosmetic, under Workspace.SD_ClientFx, no shadow).
-- ReducedMotion is the caller's: it decides how many rings to show (§18.1: 1 instead of 2, none at the throw or the mat).
-- Moved out of VfxController (its former local ring(); same look and numbers).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

local Anim = script.Parent
local FxPool = require(Anim.FxPool)
local Scheduler = require(Anim.Scheduler)

-- Types

export type Ring = {
	stop: (self: Ring) -> (),
	done: boolean,
}

-- What a ring runs on: the pool its part comes from, the scheduler that steps it and the clock it reads.
export type Deps = {
	pool: FxPool.FxPool,
	scheduler: Scheduler.Scheduler,
	clock: () -> number,
}

-- Constants

local HIT = Config.Vfx.Hit
local RING_THICKNESS = 0.1
-- reading (as built in VfxController): rings sit this far off the hit surface.
local SURFACE_LIFT = 0.05
local MIN_DIAMETER = 0.05

-- Module table

local FxShapes = {}

-- Private

local live: { [Ring]: boolean } = {}

local function quadOut(u: number): number
	local x = math.clamp(u, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

local function defaultDeps(): Deps
	return { pool = FxPool.default(), scheduler = Scheduler.default(), clock = os.clock }
end

-- Public

-- Pure: a ring's diameter and Transparency at u (0..1 of its life).
function FxShapes.ringSample(u: number, diameter: number, transparencyFrom: number?): (number, number)
	local from = if transparencyFrom == nil then HIT.ringTransparencyFrom else transparencyFrom
	local x = math.clamp(u, 0, 1)
	return math.max(diameter * quadOut(x), MIN_DIAMETER), from + (1 - from) * x
end

-- Pure: the ring's frame: its Y axis along `normal` (up when degenerate), lifted SURFACE_LIFT off `position`.
function FxShapes.ringFrame(position: Vector3, normal: Vector3): CFrame
	local n = if normal.Magnitude > 1e-6 then normal.Unit else Vector3.yAxis
	local right = if math.abs(n:Dot(Vector3.xAxis)) < 0.95
		then n:Cross(Vector3.xAxis).Unit
		else n:Cross(Vector3.zAxis).Unit
	local back = right:Cross(n).Unit
	return CFrame.fromMatrix(position + n * SURFACE_LIFT, right, n, back)
end

-- A ring on explicit dependencies (tests); FxShapes.ring uses the client's default pool, scheduler and os.clock.
function FxShapes.ringWith(
	deps: Deps,
	position: Vector3,
	normal: Vector3,
	diameter: number,
	seconds: number,
	color: Color3,
	transparencyFrom: number?
): Ring
	local pool = deps.pool
	local clock = deps.clock
	local from = if transparencyFrom == nil then HIT.ringTransparencyFrom else transparencyFrom
	local frame = FxShapes.ringFrame(position, normal)
	local part = pool:acquirePart({
		Name = "Ring",
		Color = color,
		Transparency = from,
		Size = Vector3.new(MIN_DIAMETER, RING_THICKNESS, MIN_DIAMETER),
		CFrame = frame,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	local started = clock()
	local length = math.max(seconds, 1e-3)
	local handle: Scheduler.Handle? = nil
	local ring = { done = false } :: Ring

	local function finish()
		if ring.done then
			return
		end
		ring.done = true
		live[ring] = nil
		pool:release(part)
		local h = handle
		if h then
			handle = nil
			h:disconnect()
		end
	end

	function ring.stop(_self: Ring)
		finish()
	end

	live[ring] = true
	handle = deps.scheduler:add(function(_dt: number, _now: number): boolean
		if ring.done then
			return false
		end
		local u = (clock() - started) / length
		local d, transparency = FxShapes.ringSample(u, diameter, from)
		part.Size = Vector3.new(d, RING_THICKNESS, d)
		part.CFrame = frame
		part.Transparency = transparency
		if u >= 1 then
			finish()
			return false
		end
		return true
	end, "render")
	return ring
end

-- A pooled ring on the client's default pool and scheduler (see the header).
function FxShapes.ring(
	position: Vector3,
	normal: Vector3,
	diameter: number,
	seconds: number,
	color: Color3,
	transparencyFrom: number?
): Ring
	return FxShapes.ringWith(defaultDeps(), position, normal, diameter, seconds, color, transparencyFrom)
end

-- Live rings (every owner's).
function FxShapes.count(): number
	local n = 0
	for _ in live do
		n += 1
	end
	return n
end

-- Stops every live ring at once and returns its part to the pool (leak checks).
function FxShapes.clear()
	for ring in table.clone(live) do
		ring:stop()
	end
end

return FxShapes
